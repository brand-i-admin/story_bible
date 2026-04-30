"""Build SQL seed for quiz_questions from assets/quizzes/*.json.

Quiz JSONs are matched to events by `story_title`. Events are keyed by
`(era_code, story_index)` in the current events seed (codes like `evt_*` are
no longer used). The generated SQL deletes existing rows for each managed
event and re-inserts the 3 questions, so the script is safely re-runnable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
import sys
from collections import Counter
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable


# ---------------------------------------------------------------------------
# Title aliases — quiz title -> current event title (events seed renames/merges)
# ---------------------------------------------------------------------------
TITLE_ALIASES: dict[str, str] = {
    "십계명: 하나님 나라의 기준": "시내산 도착: 십계명과 하나님 기준",
    "풀무불: 함께하시는 분": "풀무불: 다니엘과 세 친구",
    "성벽 재건: 밤의 조사": "성벽 재건: 밤의 조사와 한 손엔 무기",
}


# ---------------------------------------------------------------------------
# Events seed parsing
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class EventKey:
    era_code: str
    title: str
    story_index: int


_EVENT_ROW_PATTERN = re.compile(
    r"""
    \(\s*'(?P<era>era_[a-z_]+)',\s*
    '(?P<title>(?:[^'\\]|\\.)+)',\s*
    .+?,\s*
    '(?:exact|approx)',\s*
    (?P<sidx>\d+),\s*
    '[^']*',\s*
    -?[\d.]+,\s*-?[\d.]+,\s*
    '(?:published|draft)'\s*\)
    """,
    re.DOTALL | re.VERBOSE,
)


def extract_events_from_seed_sql(sql_text: str) -> list[EventKey]:
    """Return events parsed from the events seed SQL (`(era_code, title, story_index)`)."""
    out: list[EventKey] = []
    for m in _EVENT_ROW_PATTERN.finditer(sql_text):
        title = m.group("title").replace("\\'", "'")
        out.append(
            EventKey(
                era_code=m.group("era"),
                title=title,
                story_index=int(m.group("sidx")),
            )
        )
    return out


# ---------------------------------------------------------------------------
# Deterministic shuffle
# ---------------------------------------------------------------------------
def deterministic_shuffle(
    story_code: str, display_order: int, choices: list[str]
) -> tuple[list[str], int]:
    """Shuffle deterministically from `(story_code, display_order)`.

    Draft convention: `answer_index == 0`. Returns `(shuffled, new_answer_index)`.
    """
    seed_key = f"{story_code}:{display_order}"
    seed_int = int.from_bytes(
        hashlib.sha256(seed_key.encode("utf-8")).digest()[:8], "big"
    )
    rng = random.Random(seed_int)
    indexed = list(enumerate(choices))
    rng.shuffle(indexed)
    new_answer_index = next(i for i, (orig, _) in enumerate(indexed) if orig == 0)
    shuffled = [text for _, text in indexed]
    return shuffled, new_answer_index


# ---------------------------------------------------------------------------
# QuizFile schema
# ---------------------------------------------------------------------------
QUESTION_TYPES_IN_ORDER: tuple[str, str, str] = ("fact", "attitude", "bible_context")


class QuizValidationError(ValueError):
    """Raised when a quiz JSON file fails schema validation."""


@dataclass(frozen=True)
class QuizQuestionDraft:
    type: str
    display_order: int
    question: str
    choices: list[str]
    answer_index: int
    explanation: str


@dataclass(frozen=True)
class QuizFile:
    path: Path
    story_code: str
    story_title: str
    source_version: str
    questions: list[QuizQuestionDraft]


def load_quiz_file(path: Path) -> QuizFile:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise QuizValidationError(f"{path.name}: root must be an object")

    story_code = str(raw.get("story_code", "")).strip()
    if not story_code:
        raise QuizValidationError(f"{path.name}: story_code is required")
    if path.stem != story_code:
        raise QuizValidationError(
            f"{path.name}: filename stem {path.stem!r} must equal story_code "
            f"{story_code!r}"
        )

    questions_raw = raw.get("questions")
    if not isinstance(questions_raw, list) or len(questions_raw) != 3:
        raise QuizValidationError(
            f"{path.name}: questions length must be exactly 3"
        )

    questions: list[QuizQuestionDraft] = []
    for i, q in enumerate(questions_raw):
        if not isinstance(q, dict):
            raise QuizValidationError(
                f"{path.name}: questions[{i}] must be an object"
            )
        expected_type = QUESTION_TYPES_IN_ORDER[i]
        if q.get("type") != expected_type:
            raise QuizValidationError(
                f"{path.name}: questions[{i}].type must be {expected_type!r}, "
                f"got {q.get('type')!r}"
            )
        if q.get("display_order") != i:
            raise QuizValidationError(
                f"{path.name}: questions[{i}].display_order must be {i}"
            )
        choices = q.get("choices")
        if not isinstance(choices, list) or len(choices) != 3:
            raise QuizValidationError(
                f"{path.name}: questions[{i}].choices length must be exactly 3"
            )
        for j, c in enumerate(choices):
            if not isinstance(c, str) or not c.strip():
                raise QuizValidationError(
                    f"{path.name}: questions[{i}].choices[{j}] must be a non-empty string"
                )
        answer_index = q.get("answer_index")
        if answer_index not in (0, 1, 2):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].answer_index must be 0, 1, or 2"
            )
        question_text = q.get("question")
        explanation = q.get("explanation", "")
        if not isinstance(question_text, str) or not question_text.strip():
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question must be a non-empty string"
            )
        if not isinstance(explanation, str):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].explanation must be a string"
            )
        questions.append(
            QuizQuestionDraft(
                type=expected_type,
                display_order=i,
                question=question_text.strip(),
                choices=[c.strip() for c in choices],
                answer_index=answer_index,
                explanation=explanation.strip(),
            )
        )

    return QuizFile(
        path=path,
        story_code=story_code,
        story_title=str(raw.get("story_title", "")).strip(),
        source_version=str(raw.get("source_version", "")).strip(),
        questions=questions,
    )


# ---------------------------------------------------------------------------
# Title-based event resolution
# ---------------------------------------------------------------------------
def resolve_event_for_quiz(
    quiz_title: str, title_to_event: dict[str, EventKey]
) -> EventKey | None:
    """Try the quiz title verbatim, then via TITLE_ALIASES."""
    direct = title_to_event.get(quiz_title)
    if direct is not None:
        return direct
    aliased = TITLE_ALIASES.get(quiz_title)
    if aliased is not None:
        return title_to_event.get(aliased)
    return None


def _dollar_quote(text: str) -> str:
    """Wrap text in a unique dollar-quote tag."""
    tag = "q"
    while f"${tag}$" in text:
        tag = tag + "q"
    return f"${tag}${text}${tag}$"


# ---------------------------------------------------------------------------
# SQL generation
# ---------------------------------------------------------------------------
def build_sql_statements(
    quiz_files: Iterable[QuizFile],
    title_to_event: dict[str, EventKey],
) -> str:
    """Generate idempotent seed SQL.

    For each managed quiz:
      - Resolve event by `(era_code, story_index)` via title (with aliases).
      - Delete existing quiz_questions rows for that event.
      - Insert the 3 shuffled questions.

    Quizzes whose title doesn't resolve are skipped (with a SQL comment) and
    surfaced in the validation report.
    """
    lines: list[str] = [
        "-- auto-generated by tools/seed/build_quizzes_seed_sql.py",
        "-- source: assets/quizzes/*.json",
        "-- idempotent: delete-then-insert per (era_code, story_index)",
        "",
        "begin;",
        "",
    ]

    for quiz in quiz_files:
        ek = resolve_event_for_quiz(quiz.story_title, title_to_event)
        if ek is None:
            lines.append(
                f"-- SKIPPED {quiz.story_code}: title {quiz.story_title!r} "
                f"does not match any event"
            )
            lines.append("")
            continue

        # Idempotent purge.
        lines.append(
            "delete from quiz_questions q using events e join eras er on er.id = e.era_id"
        )
        lines.append(
            f"  where q.event_id = e.id and er.code = '{ek.era_code}' "
            f"and e.story_index = {ek.story_index};"
        )

        for q in quiz.questions:
            shuffled, new_answer_index = deterministic_shuffle(
                quiz.story_code, q.display_order, q.choices
            )
            lines.append(
                "insert into quiz_questions ("
                "event_id, question, choice_a, choice_b, choice_c, choice_d, "
                "answer_index, explanation, display_order)"
            )
            lines.append(
                f"select e.id, {_dollar_quote(q.question)}, "
                f"{_dollar_quote(shuffled[0])}, "
                f"{_dollar_quote(shuffled[1])}, "
                f"{_dollar_quote(shuffled[2])}, "
                f"null, "
                f"{new_answer_index}, "
                f"{_dollar_quote(q.explanation)}, "
                f"{q.display_order}"
            )
            lines.append(
                f"from events e join eras er on er.id = e.era_id "
                f"where er.code = '{ek.era_code}' and e.story_index = {ek.story_index};"
            )
            lines.append("")

    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
_LENGTH_LIMITS = {"question": 40, "choice": 20, "explanation": 60}


def build_report(
    *, quiz_files: list[QuizFile], events: list[EventKey]
) -> dict:
    title_to_event = {e.title: e for e in events}
    event_titles = set(title_to_event.keys())
    quiz_resolved_titles: set[str] = set()
    unresolved_quizzes: list[dict] = []

    answer_dist: Counter[int] = Counter()
    length_warnings: list[dict] = []

    for quiz in quiz_files:
        ek = resolve_event_for_quiz(quiz.story_title, title_to_event)
        if ek is None:
            unresolved_quizzes.append(
                {"story_code": quiz.story_code, "story_title": quiz.story_title}
            )
        else:
            quiz_resolved_titles.add(ek.title)

        for q in quiz.questions:
            _, shuffled_answer_index = deterministic_shuffle(
                quiz.story_code, q.display_order, q.choices
            )
            answer_dist[shuffled_answer_index] += 1

            if len(q.question) > _LENGTH_LIMITS["question"]:
                length_warnings.append(
                    {
                        "story_code": quiz.story_code,
                        "display_order": q.display_order,
                        "field": "question",
                        "length": len(q.question),
                    }
                )
            for idx, c in enumerate(q.choices):
                if len(c) > _LENGTH_LIMITS["choice"]:
                    length_warnings.append(
                        {
                            "story_code": quiz.story_code,
                            "display_order": q.display_order,
                            "field": f"choices[{idx}]",
                            "length": len(c),
                        }
                    )
            if len(q.explanation) > _LENGTH_LIMITS["explanation"]:
                length_warnings.append(
                    {
                        "story_code": quiz.story_code,
                        "display_order": q.display_order,
                        "field": "explanation",
                        "length": len(q.explanation),
                    }
                )

    events_without_quiz = sorted(event_titles - quiz_resolved_titles)
    total_questions = sum(len(q.questions) for q in quiz_files)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "total_quiz_files": len(quiz_files),
        "total_events": len(events),
        "resolved_quiz_count": len(quiz_resolved_titles),
        "total_questions": total_questions,
        "answer_index_distribution": {
            "0": answer_dist.get(0, 0),
            "1": answer_dist.get(1, 0),
            "2": answer_dist.get(2, 0),
        },
        "unresolved_quizzes": unresolved_quizzes,
        "events_without_quiz": events_without_quiz,
        "length_warnings": length_warnings,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build quiz_questions seed SQL from assets/quizzes/*.json."
    )
    parser.add_argument(
        "--input-dir", type=Path, default=Path("assets/quizzes"),
        help="Directory containing per-event quiz JSON files.",
    )
    parser.add_argument(
        "--output", type=Path,
        default=Path("supabase/quizzes/quizzes_seed.sql"),
        help="SQL output path.",
    )
    parser.add_argument(
        "--report", type=Path,
        default=Path("supabase/quizzes/quizzes_report.json"),
        help="Validation report path (JSON).",
    )
    parser.add_argument(
        "--events-seed-sql", type=Path,
        default=Path("supabase/200_stories/200_stories_seed.sql"),
        help="Events seed SQL used as the authority for (era_code, story_index, title).",
    )
    parser.add_argument(
        "--max-unresolved", type=int, default=10,
        help="Fail if more than this many quizzes can't be matched to an event.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(list(sys.argv[1:]) if argv is None else argv)

    if not args.events_seed_sql.exists():
        print(f"ERROR: events seed SQL not found: {args.events_seed_sql}", file=sys.stderr)
        return 1
    events = extract_events_from_seed_sql(
        args.events_seed_sql.read_text(encoding="utf-8")
    )
    if not events:
        print("ERROR: no events parsed from events seed SQL", file=sys.stderr)
        return 1

    title_to_event = {e.title: e for e in events}

    json_paths = sorted(args.input_dir.glob("*.json"))
    quiz_files: list[QuizFile] = []
    for p in json_paths:
        try:
            quiz_files.append(load_quiz_file(p))
        except QuizValidationError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1

    seen_codes: set[str] = set()
    for q in quiz_files:
        if q.story_code in seen_codes:
            print(f"ERROR: duplicate story_code {q.story_code!r}", file=sys.stderr)
            return 1
        seen_codes.add(q.story_code)

    report = build_report(quiz_files=quiz_files, events=events)

    if len(report["unresolved_quizzes"]) > args.max_unresolved:
        print(
            f"ERROR: {len(report['unresolved_quizzes'])} unresolved quizzes "
            f"(max {args.max_unresolved}). See report for details.",
            file=sys.stderr,
        )
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(
            json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return 1

    dist = report["answer_index_distribution"]
    total = sum(dist.values())
    if total > 0:
        ratios = [v / total for v in dist.values()]
        if any(r < 0.28 or r > 0.39 for r in ratios):
            print(
                f"WARNING: answer_index distribution skewed: {dist} "
                f"(33% ±5% target; continuing anyway).",
                file=sys.stderr,
            )

    if report["length_warnings"]:
        print(
            f"WARNING: {len(report['length_warnings'])} length warnings "
            f"(see report JSON).",
            file=sys.stderr,
        )

    if report["unresolved_quizzes"]:
        print(
            f"WARNING: {len(report['unresolved_quizzes'])} unresolved quizzes "
            f"will be skipped (see report).",
            file=sys.stderr,
        )

    sql = build_sql_statements(quiz_files, title_to_event)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(
        f"OK: {report['total_quiz_files']} files "
        f"({report['resolved_quiz_count']} resolved), "
        f"{report['total_questions']} questions -> {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
