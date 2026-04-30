"""Build SQL seed for quiz_questions from assets/quizzes/*.json.

Each quiz JSON is keyed by `(era_code, story_index)`, mirroring how the events
seed identifies stories. Filenames follow `<era_code>_n<story_index:03d>.json`
(e.g. `era_primeval_n001.json`). The generated SQL deletes existing rows for
each managed event and re-inserts the 3 questions, so the script is safely
re-runnable.
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
    """Return events parsed from the events seed SQL."""
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
    seed_key: str, display_order: int, choices: list[str]
) -> tuple[list[str], int]:
    """Shuffle deterministically from `(seed_key, display_order)`.

    Draft convention: `answer_index == 0`. Returns `(shuffled, new_answer_index)`.
    """
    seed_input = f"{seed_key}:{display_order}"
    seed_int = int.from_bytes(
        hashlib.sha256(seed_input.encode("utf-8")).digest()[:8], "big"
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
    era_code: str
    story_index: int
    story_title: str
    source_version: str
    questions: list[QuizQuestionDraft]

    @property
    def seed_key(self) -> str:
        return f"{self.era_code}:n{self.story_index:03d}"


_FILENAME_PATTERN = re.compile(r"^(?P<era>era_[a-z_]+)_n(?P<sidx>\d+)$")


def load_quiz_file(path: Path) -> QuizFile:
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise QuizValidationError(f"{path.name}: root must be an object")

    era_code = raw.get("era_code")
    if not isinstance(era_code, str) or not era_code.startswith("era_"):
        raise QuizValidationError(
            f"{path.name}: era_code must be a string starting with 'era_'"
        )
    story_index = raw.get("story_index")
    if not isinstance(story_index, int) or story_index < 1:
        raise QuizValidationError(
            f"{path.name}: story_index must be a positive integer"
        )

    m = _FILENAME_PATTERN.match(path.stem)
    if m is None:
        raise QuizValidationError(
            f"{path.name}: filename stem must match '<era_code>_n<int>' "
            f"(e.g. era_primeval_n001)"
        )
    if m.group("era") != era_code:
        raise QuizValidationError(
            f"{path.name}: filename era {m.group('era')!r} does not match "
            f"era_code {era_code!r}"
        )
    if int(m.group("sidx")) != story_index:
        raise QuizValidationError(
            f"{path.name}: filename story_index {m.group('sidx')!r} does not "
            f"match story_index {story_index!r}"
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
        era_code=era_code,
        story_index=story_index,
        story_title=str(raw.get("story_title", "")).strip(),
        source_version=str(raw.get("source_version", "")).strip(),
        questions=questions,
    )


def _dollar_quote(text: str) -> str:
    """Wrap text in a unique dollar-quote tag."""
    tag = "q"
    while f"${tag}$" in text:
        tag = tag + "q"
    return f"${tag}${text}${tag}$"


# ---------------------------------------------------------------------------
# SQL generation
# ---------------------------------------------------------------------------
def build_sql_statements(quiz_files: Iterable[QuizFile]) -> str:
    """Generate idempotent seed SQL.

    For each quiz: delete existing quiz_questions for `(era_code, story_index)`,
    then insert the 3 shuffled questions via the same lookup.
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
        lines.append(
            "delete from quiz_questions q using events e "
            "join eras er on er.id = e.era_id"
        )
        lines.append(
            f"  where q.event_id = e.id and er.code = '{quiz.era_code}' "
            f"and e.story_index = {quiz.story_index};"
        )

        for q in quiz.questions:
            shuffled, new_answer_index = deterministic_shuffle(
                quiz.seed_key, q.display_order, q.choices
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
                f"where er.code = '{quiz.era_code}' "
                f"and e.story_index = {quiz.story_index};"
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
    event_by_key: dict[tuple[str, int], EventKey] = {
        (e.era_code, e.story_index): e for e in events
    }

    answer_dist: Counter[int] = Counter()
    length_warnings: list[dict] = []
    title_mismatches: list[dict] = []
    orphan_quizzes: list[dict] = []
    quiz_keys: set[tuple[str, int]] = set()

    for quiz in quiz_files:
        key = (quiz.era_code, quiz.story_index)
        quiz_keys.add(key)
        ek = event_by_key.get(key)
        if ek is None:
            orphan_quizzes.append(
                {
                    "filename": quiz.path.name,
                    "era_code": quiz.era_code,
                    "story_index": quiz.story_index,
                    "story_title": quiz.story_title,
                }
            )
        elif quiz.story_title and quiz.story_title != ek.title:
            title_mismatches.append(
                {
                    "filename": quiz.path.name,
                    "json_title": quiz.story_title,
                    "event_title": ek.title,
                }
            )

        for q in quiz.questions:
            _, shuffled_answer_index = deterministic_shuffle(
                quiz.seed_key, q.display_order, q.choices
            )
            answer_dist[shuffled_answer_index] += 1

            if len(q.question) > _LENGTH_LIMITS["question"]:
                length_warnings.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "field": "question",
                        "length": len(q.question),
                    }
                )
            for idx, c in enumerate(q.choices):
                if len(c) > _LENGTH_LIMITS["choice"]:
                    length_warnings.append(
                        {
                            "filename": quiz.path.name,
                            "display_order": q.display_order,
                            "field": f"choices[{idx}]",
                            "length": len(c),
                        }
                    )
            if len(q.explanation) > _LENGTH_LIMITS["explanation"]:
                length_warnings.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "field": "explanation",
                        "length": len(q.explanation),
                    }
                )

    events_without_quiz = sorted(
        [
            {"era_code": e.era_code, "story_index": e.story_index, "title": e.title}
            for e in events
            if (e.era_code, e.story_index) not in quiz_keys
        ],
        key=lambda d: (d["era_code"], d["story_index"]),
    )
    total_questions = sum(len(q.questions) for q in quiz_files)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "total_quiz_files": len(quiz_files),
        "total_events": len(events),
        "total_questions": total_questions,
        "answer_index_distribution": {
            "0": answer_dist.get(0, 0),
            "1": answer_dist.get(1, 0),
            "2": answer_dist.get(2, 0),
        },
        "orphan_quizzes": orphan_quizzes,
        "title_mismatches": title_mismatches,
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

    json_paths = sorted(args.input_dir.glob("*.json"))
    quiz_files: list[QuizFile] = []
    for p in json_paths:
        try:
            quiz_files.append(load_quiz_file(p))
        except QuizValidationError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1

    seen_keys: set[tuple[str, int]] = set()
    for q in quiz_files:
        key = (q.era_code, q.story_index)
        if key in seen_keys:
            print(
                f"ERROR: duplicate quiz key {key!r} (file {q.path.name})",
                file=sys.stderr,
            )
            return 1
        seen_keys.add(key)

    report = build_report(quiz_files=quiz_files, events=events)

    if report["orphan_quizzes"]:
        print(
            f"ERROR: {len(report['orphan_quizzes'])} orphan quizzes "
            f"(no matching event in seed). See report for details.",
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

    if report["title_mismatches"]:
        print(
            f"WARNING: {len(report['title_mismatches'])} title mismatches "
            f"(JSON story_title vs event title).",
            file=sys.stderr,
        )

    sql = build_sql_statements(quiz_files)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(
        f"OK: {report['total_quiz_files']} files, "
        f"{report['total_questions']} questions -> {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
