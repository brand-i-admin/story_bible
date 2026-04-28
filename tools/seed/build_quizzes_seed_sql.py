"""Build SQL seed for quiz_questions from assets/quizzes/*.json.

CLI will be wired in Task 7. This module is import-safe from the test harness.
"""

from __future__ import annotations

# Functions will be added task-by-task (TDD order).

import re


_EVT_CODE_PATTERN = re.compile(r"'(evt_[a-z0-9_]+)'")


def extract_event_codes_from_seed_sql(sql_text: str) -> list[str]:
    """Return the sorted unique list of `evt_*` string literals appearing in SQL.

    Used to discover which event codes are seeded in
    `supabase/200_stories/200_stories_seed.sql` so that quiz JSON filenames
    can be validated against real DB rows.
    """
    codes = set(_EVT_CODE_PATTERN.findall(sql_text))
    return sorted(codes)


import hashlib
import random


def deterministic_shuffle(
    story_code: str, display_order: int, choices: list[str]
) -> tuple[list[str], int]:
    """Shuffle `choices` deterministically from `(story_code, display_order)`.

    The draft convention is `answer_index == 0` (correct answer is first).
    After shuffling, the correct answer lands wherever `choices[0]` moved to.
    Returns `(shuffled_choices, new_answer_index)`.
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


import json
from dataclasses import dataclass
from pathlib import Path


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
    """Load one quiz JSON file, validate its schema, and return a QuizFile.

    Raises QuizValidationError with a human-readable reason on any violation.
    The file stem (filename without .json) must equal `story_code`.
    """
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


from typing import Iterable


_STORY_INDEX_PATTERN = re.compile(r"_n(\d+)$")


def _story_index_from_code(story_code: str) -> int:
    """Extract trailing `_n###` integer from a code like 'evt_n001' or 'evt_nt_paul_j1_n185'.

    The DB events table identifies rows by `story_index` (integer), not by a text
    code. Every event code in this project ends with `_n<int>`, where the int
    matches `events.story_index`.
    """
    m = _STORY_INDEX_PATTERN.search(story_code)
    if not m:
        raise ValueError(
            f"story_code {story_code!r} does not end with _n<int>; cannot derive story_index"
        )
    return int(m.group(1))


def _dollar_quote(text: str) -> str:
    """Wrap text in a unique dollar-quote tag to avoid quoting headaches.

    If the text accidentally contains `$q$`, bump the tag to `$q2$`, etc.
    """
    tag = "q"
    while f"${tag}$" in text:
        tag = tag + "q"
    return f"${tag}${text}${tag}$"


def build_sql_statements(quiz_files: Iterable[QuizFile]) -> str:
    """Generate the complete seed SQL (begin + N inserts + commit)."""
    lines: list[str] = [
        "-- auto-generated by tools/build_quizzes_seed_sql.py",
        "-- source: assets/quizzes/*.json",
        "-- idempotent via on conflict (event_id, display_order)",
        "",
        "begin;",
        "",
    ]

    for quiz in quiz_files:
        for q in quiz.questions:
            shuffled, new_answer_index = deterministic_shuffle(
                quiz.story_code, q.display_order, q.choices
            )
            lines.append(
                f"insert into quiz_questions ("
                f"event_id, question, choice_a, choice_b, choice_c, choice_d, "
                f"answer_index, explanation, display_order)"
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
            story_index = _story_index_from_code(quiz.story_code)
            lines.append(f"from events e where e.story_index = {story_index}")
            lines.append("on conflict (event_id, display_order) do update set")
            lines.append("    question = excluded.question,")
            lines.append("    choice_a = excluded.choice_a,")
            lines.append("    choice_b = excluded.choice_b,")
            lines.append("    choice_c = excluded.choice_c,")
            lines.append("    choice_d = excluded.choice_d,")
            lines.append("    answer_index = excluded.answer_index,")
            lines.append("    explanation = excluded.explanation;")
            lines.append("")

    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


import argparse
import sys
from collections import Counter
from datetime import datetime, timezone


_LENGTH_LIMITS = {"question": 40, "choice": 20, "explanation": 60}


def build_report(
    *, quiz_files: list[QuizFile], expected_codes: list[str]
) -> dict:
    file_codes = {q.story_code for q in quiz_files}
    expected_set = set(expected_codes)

    missing = sorted(expected_set - file_codes)
    unknown = sorted(file_codes - expected_set)

    answer_dist: Counter[int] = Counter()
    length_warnings: list[dict] = []

    for quiz in quiz_files:
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

    total_questions = sum(len(q.questions) for q in quiz_files)
    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "total_files": len(quiz_files),
        "total_questions": total_questions,
        "expected_event_codes": len(expected_codes),
        "answer_index_distribution": {
            "0": answer_dist.get(0, 0),
            "1": answer_dist.get(1, 0),
            "2": answer_dist.get(2, 0),
        },
        "missing_story_codes": missing,
        "unknown_story_codes": unknown,
        "length_warnings": length_warnings,
    }


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
        help="Existing events seed SQL used as the authority for expected event codes.",
    )
    parser.add_argument(
        "--expected-count", type=int, default=None,
        help=(
            "Override the expected JSON file count. Omit for full production run "
            "(must equal #codes discovered in --events-seed-sql). "
            "Use during calibration: --expected-count 10."
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(list(sys.argv[1:]) if argv is None else argv)

    if not args.events_seed_sql.exists():
        print(f"ERROR: events seed SQL not found: {args.events_seed_sql}", file=sys.stderr)
        return 1
    expected_codes = extract_event_codes_from_seed_sql(
        args.events_seed_sql.read_text(encoding="utf-8")
    )

    json_paths = sorted(args.input_dir.glob("*.json"))
    if args.expected_count is not None:
        if len(json_paths) != args.expected_count:
            print(
                f"ERROR: expected {args.expected_count} JSON files, found {len(json_paths)}",
                file=sys.stderr,
            )
            return 1
    else:
        if len(json_paths) != len(expected_codes):
            print(
                f"ERROR: found {len(json_paths)} JSON files; "
                f"events seed has {len(expected_codes)} codes. Use "
                f"--expected-count to override during calibration.",
                file=sys.stderr,
            )
            return 1

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

    report = build_report(quiz_files=quiz_files, expected_codes=expected_codes)

    if args.expected_count is None and (
        report["missing_story_codes"] or report["unknown_story_codes"]
    ):
        print(
            "ERROR: code set mismatch. See report for missing/unknown lists.",
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

    sql = build_sql_statements(quiz_files)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(sql, encoding="utf-8")

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    print(
        f"OK: {report['total_files']} files, "
        f"{report['total_questions']} questions -> {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
