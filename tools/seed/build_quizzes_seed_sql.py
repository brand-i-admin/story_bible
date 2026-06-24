"""Build SQL seed for quiz_questions from assets/events/*.json.

Each event JSON row embeds ``quiz_questions`` and is keyed by
``(era, story_index)``, mirroring how the events seed identifies stories. The
generated SQL deletes existing rows for each managed event and re-inserts the
questions, so the script is safely re-runnable.
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


@dataclass(frozen=True)
class VerseEvidence:
    book: str
    chapter: int
    verse: int
    end_verse: int

    @property
    def label(self) -> str:
        if self.end_verse == self.verse:
            return f"{self.book} {self.chapter}:{self.verse}"
        return f"{self.book} {self.chapter}:{self.verse}-{self.end_verse}"


@dataclass(frozen=True)
class BibleRefRange:
    book: str
    start: tuple[int, int]
    end: tuple[int, int]

    @property
    def label(self) -> str:
        start = f"{self.start[0]}:{self.start[1]}"
        end = f"{self.end[0]}:{self.end[1]}"
        return f"{self.book} {start}-{end}"

    def contains(self, evidence: VerseEvidence) -> bool:
        if self.book != evidence.book:
            return False
        start = (evidence.chapter, evidence.verse)
        end = (evidence.chapter, evidence.end_verse)
        return self.start <= start <= self.end and self.start <= end <= self.end


@dataclass(frozen=True)
class StoryVerseScope:
    title: str
    refs: tuple[BibleRefRange, ...]


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

_EVENT_ROW_WITH_UNIT_PATTERN = re.compile(
    r"""
    \(\s*'(?P<era>era_[a-z_]+)',\s*
    '(?P<title>(?:''|[^'])*)',\s*
    .+?,\s*
    '(?:exact|approx)',\s*
    (?P<sidx>\d+),\s*
    '[^']*',\s*
    '(?:''|[^']*)',\s*
    \d+,\s*
    '[^']*',\s*
    '(?:published|draft)'\s*\)
    """,
    re.DOTALL | re.VERBOSE,
)


def _unescape_sql_string(text: str) -> str:
    """Unescape the SQL string styles emitted by our seed builders."""
    return text.replace("''", "'").replace("\\'", "'")


def extract_events_from_seed_sql(sql_text: str) -> list[EventKey]:
    """Return events parsed from the events seed SQL."""
    out: list[EventKey] = []
    for m in _EVENT_ROW_PATTERN.finditer(sql_text):
        title = _unescape_sql_string(m.group("title"))
        out.append(
            EventKey(
                era_code=m.group("era"),
                title=title,
                story_index=int(m.group("sidx")),
            )
        )
    if out:
        return out

    for m in _EVENT_ROW_WITH_UNIT_PATTERN.finditer(sql_text):
        title = _unescape_sql_string(m.group("title"))
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
    seed_key: str,
    display_order: int,
    choices: list[str],
    answer_index: int = 0,
) -> tuple[list[str], int]:
    """Shuffle deterministically from `(seed_key, display_order)`.

    Returns `(shuffled, new_answer_index)` while preserving the source
    `answer_index`. Older hand-authored quiz entries usually used index 0 as the
    correct answer, but DB exports may already contain shuffled choices.
    """
    seed_input = f"{seed_key}:{display_order}"
    seed_int = int.from_bytes(
        hashlib.sha256(seed_input.encode("utf-8")).digest()[:8], "big"
    )
    rng = random.Random(seed_int)
    indexed = list(enumerate(choices))
    rng.shuffle(indexed)
    new_answer_index = next(
        i for i, (orig, _) in enumerate(indexed) if orig == answer_index
    )
    shuffled = [text for _, text in indexed]
    return shuffled, new_answer_index


# ---------------------------------------------------------------------------
# QuizFile schema
# ---------------------------------------------------------------------------
QUESTION_TYPES_IN_ORDER: tuple[str, str, str] = ("fact", "attitude", "story_context")
CONFUSED_CHOICE_LABEL = "헷갈렸어요"
SOURCE_LOCATION_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"성경\s*(책|어느\s*책|무슨\s*책)"),
    re.compile(r"(어느|무슨)\s*성경\s*책"),
    re.compile(r"기록.*(성경\s*)?책"),
    re.compile(r"기록.*(몇|어느|무슨)\s*장(?!면|막)"),
    re.compile(r"기록.*(몇|어느|무슨)\s*절"),
    re.compile(r"(몇|어느|무슨)\s*절.*(기록|나옵니까|나오나요)"),
    re.compile(r"(몇|어느|무슨)\s*구절"),
    re.compile(
        r"(창세기|출애굽기|마태복음|마가복음|누가복음|요한복음)\s*(몇|어느|무슨)\s*장(?!면|막)"
    ),
    re.compile(r"(몇|어느|무슨)\s*장(?!면|막).*(기록|나옵니까|나오나요)"),
    re.compile(r"성경\s*책과\s*장"),
)
TITLE_MATCH_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"설명에\s*맞는\s*이야기"),
    re.compile(r"맞는\s*이야기는\s*무엇"),
    re.compile(r"이야기\s*제목"),
    re.compile(r"제목을?\s*(고르|맞추)"),
    re.compile(r"「[^」]+」에서\s*실제로\s*일어난\s*일"),
    re.compile(r"이야기에서\s*실제로\s*일어난\s*일"),
)
STORY_TITLE_PREFIX_QUOTES: tuple[str, ...] = ("'", "「", "《", '"')
SUMMARY_CHOICE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"핵심\s*내용"),
    re.compile(r"중심\s*내용"),
    re.compile(r"요약\s*(내용|문장)"),
)
BLANK_CHOICE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"빈\s*칸|빈칸"),
    re.compile(r"_{2,}"),
)
GENERIC_STORY_CONTEXT_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"본문에\s*따르면\s*다음\s*중\s*맞는\s*내용"),
    re.compile(r"본문에\s*따르면\s*맞는\s*설명"),
    re.compile(r"다음\s*중\s*이\s*이야기\s*본문에서\s*확인되는\s*표현"),
    re.compile(r"본문에서\s*확인되는\s*표현"),
)
PLACEHOLDER_SCENE_QUESTION_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"본문에서\s*먼저\s*두드러지는\s*장면"),
    re.compile(r"이어지는\s*장면에서\s*중심\s*인물"),
    re.compile(r"이\s*사건의\s*끝부분에서\s*이어진\s*일"),
)
VERSE_LIKE_CHOICE_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"(가로되|이르되|가라사대)"),
    re.compile(r"(하시니라|하니라|하였더라|하였더니|되니라|되었더라)"),
    re.compile(r"(하였으며|하였고|하매)"),
    re.compile(r"(더라|니라)$"),
)
VERSE_EVIDENCE_PATTERN = re.compile(r"^[가-힣0-9]+\s+\d+:\d+(?:-\d+)?\s+—\s+'[^']+'$")
VERSE_REFERENCE_PATTERN = re.compile(
    r"^\s*(?P<book>[가-힣0-9]+)\s+"
    r"(?P<chapter>\d+):(?P<verse>\d+)"
    r"(?:-(?P<end_verse>\d+))?"
)
STORY_REF_POINT_PATTERN = re.compile(r"^(?P<chapter>\d+):(?P<verse>\d+)$")
MAX_STORY_CONTEXT_CHOICE_CHARS = 72
GENERIC_QUESTION_ENDINGS: tuple[str, ...] = (
    "어떻게 했습니까?",
    "어떻게 하였습니까?",
    "무엇을 했습니까?",
    "무엇이라고 말했습니까?",
    "무엇이라고 했습니까?",
    "무엇이라 말했습니까?",
    "무엇이라고 하였습니까?",
)
QUESTION_CONTEXT_MARKERS: tuple[str, ...] = (
    "때",
    "후",
    "뒤",
    "앞에서",
    "에게",
    "대해",
    "왜",
    "무엇을",
    "어디",
    "누가",
    "어느",
    "어떤",
    "어디서",
    "기도 금지령",
    "준비한",
    "금지령",
    "체포",
    "입성",
    "환상",
    "을 ",
    "를 ",
)
NOUNISH_CHOICE_PATTERN = re.compile(
    r"^([가-힣A-Za-z0-9·\s()]+|[일이삼사오육칠팔구십백천만]+ 명|[일이삼사오육칠팔구십백천만]+ 일|[일이삼사오육칠팔구십백천만]+ 규빗)$"
)
ANSWER_SHAPE_VERB_PATTERN = re.compile(
    r"(다|했다|하였다|하셨다|말했다|대답했다|명했다|요청했다|구했다|기도했다|"
    r"살렸다|죽였다|돌아갔다|떠났다|섬겼다|보냈다|주었다|드렸다|불렀다|"
    r"선포했다|믿었다|순종했다|거절했다|엎드렸다|울었다|찾았다|만났다|"
    r"따랐다|숨겼다|건넜다|쳤다|보았다|하라|말라|되리라|주소서|하소서|"
    r"가라|오라|두라|내라|하라|말라|살리라|오리라|되리라|준비하시리라|"
    r"지어다|나이다|소이다|로소이다|가자|고)$"
)
GENERIC_DISTRACTOR_CHOICES: frozenset[str] = frozenset(
    {
        "그 일을 숨기고 물러났다",
        "다른 사람에게 책임을 돌렸다",
        "자신은 책임이 없다고 주장했다",
        "지금은 아무 조치도 하지 않겠다고 답했다",
        "그 일을 그냥 지나쳤다",
    }
)


class QuizValidationError(ValueError):
    """Raised when a quiz entry fails schema validation."""


def asks_for_source_location(question_text: str) -> bool:
    """Return True if a question asks users to recall book/chapter location."""
    return any(pattern.search(question_text) for pattern in SOURCE_LOCATION_PATTERNS)


def asks_for_story_title(question_text: str) -> bool:
    """Return True if a question asks users to identify a story title."""
    return any(pattern.search(question_text) for pattern in TITLE_MATCH_PATTERNS)


def starts_with_story_title_prefix(question_text: str, story_title: str) -> bool:
    """Return True for awkward story-quiz prompts like "'제목'에서 ...".

    Daily quiz copy may quote era/event names, but per-story quiz cards already
    show the story title in the UI. The question itself should ask about the
    scene, action, or reaction without repeating the title as a prefix.
    """
    if not story_title:
        return False
    stripped = question_text.strip()
    return any(
        stripped.startswith(f"{quote}{story_title}")
        for quote in STORY_TITLE_PREFIX_QUOTES
    )


def asks_for_summary_choice(question_text: str) -> bool:
    """Return True if a question asks users to pick a core/summary sentence."""
    return any(pattern.search(question_text) for pattern in SUMMARY_CHOICE_PATTERNS)


def asks_for_blank_choice(question_text: str) -> bool:
    """Return True if a question asks users to fill a blank in the passage."""
    return any(pattern.search(question_text) for pattern in BLANK_CHOICE_PATTERNS)


def asks_generic_story_context(question_text: str) -> bool:
    """Return True if a story-context question is a generic passage prompt."""
    return any(
        pattern.search(question_text) for pattern in GENERIC_STORY_CONTEXT_PATTERNS
    )


def asks_placeholder_scene_question(question_text: str) -> bool:
    """Return True for draft scene-order prompts that are not real quizzes."""
    return any(
        pattern.search(question_text) for pattern in PLACEHOLDER_SCENE_QUESTION_PATTERNS
    )


def choice_looks_like_verse_fragment(choice_text: str) -> bool:
    """Return True if a choice keeps KRV-style verse wording instead of paraphrase."""
    return any(pattern.search(choice_text) for pattern in VERSE_LIKE_CHOICE_PATTERNS)


def has_verse_evidence(explanation: str) -> bool:
    """Return True when the explanation points to a concrete verse quote."""
    return VERSE_EVIDENCE_PATTERN.search(explanation.strip()) is not None


def parse_verse_evidence(explanation: str) -> VerseEvidence | None:
    """Parse the leading verse reference from a quiz explanation."""
    m = VERSE_REFERENCE_PATTERN.match(explanation.strip())
    if m is None:
        return None
    verse = int(m.group("verse"))
    end_verse = int(m.group("end_verse") or verse)
    return VerseEvidence(
        book=m.group("book"),
        chapter=int(m.group("chapter")),
        verse=verse,
        end_verse=end_verse,
    )


def parse_story_ref_point(
    value: str, *, path: Path, story_title: str
) -> tuple[int, int]:
    m = STORY_REF_POINT_PATTERN.match(value)
    if m is None:
        raise QuizValidationError(
            f"{path.name}: story {story_title!r} has invalid bible_ref point {value!r}"
        )
    return int(m.group("chapter")), int(m.group("verse"))


def load_story_ref_scopes(stories_dir: Path) -> dict[tuple[str, int], StoryVerseScope]:
    """Load `(era_code, story_index)` -> Bible reference ranges from stories JSON."""
    scopes: dict[tuple[str, int], StoryVerseScope] = {}
    for path in sorted(stories_dir.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, list):
            raise QuizValidationError(f"{path.name}: root must be a list")
        for story in raw:
            if not isinstance(story, dict):
                raise QuizValidationError(f"{path.name}: story entry must be an object")
            era_code = story.get("era")
            story_index = story.get("story_index")
            title = str(story.get("title", "")).strip()
            if not isinstance(era_code, str) or not isinstance(story_index, int):
                raise QuizValidationError(
                    f"{path.name}: story {title!r} must have era and story_index"
                )
            ranges: list[BibleRefRange] = []
            for ref in story.get("bible_ref", []):
                if not isinstance(ref, dict):
                    raise QuizValidationError(
                        f"{path.name}: story {title!r} has non-object bible_ref"
                    )
                book = ref.get("book")
                start = ref.get("from")
                end = ref.get("to")
                if (
                    not isinstance(book, str)
                    or not isinstance(start, str)
                    or not isinstance(end, str)
                ):
                    raise QuizValidationError(
                        f"{path.name}: story {title!r} has incomplete bible_ref"
                    )
                ranges.append(
                    BibleRefRange(
                        book=book,
                        start=parse_story_ref_point(
                            start, path=path, story_title=title
                        ),
                        end=parse_story_ref_point(end, path=path, story_title=title),
                    )
                )
            key = (era_code, story_index)
            if key in scopes:
                raise QuizValidationError(
                    f"{path.name}: duplicate story key {key!r} for quiz verse scope"
                )
            scopes[key] = StoryVerseScope(title=title, refs=tuple(ranges))
    return scopes


def asks_contextless_generic_question(question_text: str) -> bool:
    """Return True for vague prompts like '왕은 어떻게 했습니까?'."""
    stripped = question_text.strip()
    if not stripped.endswith(GENERIC_QUESTION_ENDINGS):
        return False
    if any(marker in stripped for marker in QUESTION_CONTEXT_MARKERS):
        return False
    # A short subject + generic predicate gives learners no clue which moment
    # the question asks about.
    return len(stripped) <= 24


def choice_matches_action_or_speech_prompt(choice_text: str) -> bool:
    """Return True if a choice can grammatically answer 'how/what did X say?'."""
    stripped = choice_text.strip()
    if ANSWER_SHAPE_VERB_PATTERN.search(stripped):
        return True
    if len(stripped) >= 15 and (
        " " in stripped or "을" in stripped or "를" in stripped
    ):
        return True
    if NOUNISH_CHOICE_PATTERN.fullmatch(stripped) and len(stripped) <= 14:
        return False
    return False


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


def load_quiz_file(
    path: Path,
    raw_payload: dict | None = None,
    *,
    validate_filename: bool = True,
) -> QuizFile:
    raw = (
        json.loads(path.read_text(encoding="utf-8"))
        if raw_payload is None
        else raw_payload
    )
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

    if validate_filename:
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

    story_title = str(raw.get("story_title", "")).strip()
    questions_raw = raw.get("questions")
    if not isinstance(questions_raw, list) or not (1 <= len(questions_raw) <= 3):
        raise QuizValidationError(f"{path.name}: questions length must be 1 to 3")

    questions: list[QuizQuestionDraft] = []
    for i, q in enumerate(questions_raw):
        if not isinstance(q, dict):
            raise QuizValidationError(f"{path.name}: questions[{i}] must be an object")
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
            if c.strip() in GENERIC_DISTRACTOR_CHOICES:
                raise QuizValidationError(
                    f"{path.name}: questions[{i}].choices[{j}] is a generic "
                    "filler distractor; use a plausible story-specific choice"
                )
            if choice_looks_like_verse_fragment(c.strip()):
                raise QuizValidationError(
                    f"{path.name}: questions[{i}].choices[{j}] looks like a "
                    "copied verse fragment; use everyday fact wording instead"
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
        if starts_with_story_title_prefix(question_text, story_title):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question repeats the story title "
                "as a quoted prefix; ask the concrete scene question directly"
            )
        if asks_placeholder_scene_question(question_text):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question is a placeholder scene "
                "prompt; ask about an important passage fact instead"
            )
        if expected_type == "story_context" and asks_for_source_location(question_text):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question asks for Bible source "
                "location; use story-context comprehension instead"
            )
        if expected_type == "story_context" and asks_for_story_title(question_text):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question asks learners to match "
                "a story title; use passage comprehension instead"
            )
        if expected_type == "story_context" and asks_for_summary_choice(question_text):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question asks learners to pick "
                "a core/summary sentence; use a normal story question instead"
            )
        if expected_type == "story_context" and asks_for_blank_choice(question_text):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question asks learners to fill "
                "a blank; use passage fact choices instead"
            )
        if expected_type == "story_context" and asks_generic_story_context(
            question_text
        ):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question is too generic; ask "
                "about a concrete fact from a specific verse"
            )
        if asks_contextless_generic_question(question_text):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].question is ambiguous; include "
                "the concrete moment or object being asked about"
            )
        if any(
            phrase in question_text
            for phrase in ("어떻게", "무엇이라고", "뭐라", "무엇이라")
        ):
            for j, choice in enumerate(choices):
                if not choice_matches_action_or_speech_prompt(choice.strip()):
                    raise QuizValidationError(
                        f"{path.name}: questions[{i}].choices[{j}] does not "
                        "grammatically answer the question"
                    )
        if (
            expected_type == "story_context"
            and story_title
            and any(c.strip() == story_title for c in choices)
        ):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].choices include the story title; "
                "use passage-content choices instead"
            )
        if expected_type == "story_context":
            for j, choice in enumerate(choices):
                if len(choice.strip()) > MAX_STORY_CONTEXT_CHOICE_CHARS:
                    raise QuizValidationError(
                        f"{path.name}: questions[{i}].choices[{j}] is too long; "
                        "use a short fact answer instead of a full verse"
                    )
        if not isinstance(explanation, str):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].explanation must be a string"
            )
        if expected_type == "story_context" and not has_verse_evidence(explanation):
            raise QuizValidationError(
                f"{path.name}: questions[{i}].explanation must cite a verse "
                "and quote the passage evidence"
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
        story_title=story_title,
        source_version=str(raw.get("source_version", "")).strip(),
        questions=questions,
    )


def load_events_and_quizzes_from_events_dir(
    events_dir: Path,
) -> tuple[list[EventKey], list[QuizFile]]:
    """Load EventKey rows and embedded quiz_questions from canonical events JSON."""
    events: list[EventKey] = []
    quiz_files: list[QuizFile] = []
    for path in sorted(events_dir.glob("*.json")):
        raw = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(raw, list):
            raise QuizValidationError(f"{path.name}: root must be a list")
        for story in raw:
            if not isinstance(story, dict):
                raise QuizValidationError(f"{path.name}: story entry must be object")
            era_code = story.get("era")
            story_index = story.get("story_index")
            story_title = str(story.get("title", "")).strip()
            if not isinstance(era_code, str) or not era_code.startswith("era_"):
                raise QuizValidationError(
                    f"{path.name}: story {story_title!r} must have era"
                )
            if not isinstance(story_index, int) or story_index < 1:
                raise QuizValidationError(
                    f"{path.name}: story {story_title!r} must have story_index"
                )
            events.append(
                EventKey(
                    era_code=era_code,
                    title=story_title,
                    story_index=story_index,
                )
            )
            questions = story.get("quiz_questions")
            if questions is None:
                continue
            payload = {
                "era_code": era_code,
                "story_index": story_index,
                "story_title": story_title,
                "source_version": str(story.get("quiz_source_version", "")).strip(),
                "questions": questions,
            }
            quiz_files.append(load_quiz_file(path, payload, validate_filename=False))
    return events, quiz_files


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
        "-- source: assets/events/*.json quiz_questions",
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
            f"and e.story_index = {quiz.story_index} "
            "and e.deleted_at is null;"
        )

        for q in quiz.questions:
            shuffled, new_answer_index = deterministic_shuffle(
                quiz.seed_key, q.display_order, q.choices, q.answer_index
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
                f"{_dollar_quote(CONFUSED_CHOICE_LABEL)}, "
                f"{new_answer_index}, "
                f"{_dollar_quote(q.explanation)}, "
                f"{q.display_order}"
            )
            lines.append(
                f"from events e join eras er on er.id = e.era_id "
                f"where er.code = '{quiz.era_code}' "
                f"and e.story_index = {quiz.story_index} "
                "and e.deleted_at is null;"
            )
            lines.append("")

    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------
_LENGTH_LIMITS = {"question": 40, "choice": 20, "explanation": 60}
_STORY_CONTEXT_LENGTH_LIMITS = {
    "question": 58,
    "choice": MAX_STORY_CONTEXT_CHOICE_CHARS,
    "explanation": 140,
}


def _length_limits_for(question: QuizQuestionDraft) -> dict[str, int]:
    if question.type == "story_context":
        return _STORY_CONTEXT_LENGTH_LIMITS
    return _LENGTH_LIMITS


def build_report(
    *,
    quiz_files: list[QuizFile],
    events: list[EventKey],
    story_scopes: dict[tuple[str, int], StoryVerseScope] | None = None,
) -> dict:
    event_by_key: dict[tuple[str, int], EventKey] = {
        (e.era_code, e.story_index): e for e in events
    }

    answer_dist: Counter[int] = Counter()
    length_warnings: list[dict] = []
    title_mismatches: list[dict] = []
    orphan_quizzes: list[dict] = []
    verse_scope_violations: list[dict] = []
    quiz_keys: set[tuple[str, int]] = set()

    for quiz in quiz_files:
        key = (quiz.era_code, quiz.story_index)
        quiz_keys.add(key)
        ek = event_by_key.get(key)
        story_scope = story_scopes.get(key) if story_scopes is not None else None
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
                quiz.seed_key, q.display_order, q.choices, q.answer_index
            )
            answer_dist[shuffled_answer_index] += 1
            length_limits = _length_limits_for(q)

            if len(q.question) > length_limits["question"]:
                length_warnings.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "field": "question",
                        "length": len(q.question),
                    }
                )
            for idx, c in enumerate(q.choices):
                if len(c) > length_limits["choice"]:
                    length_warnings.append(
                        {
                            "filename": quiz.path.name,
                            "display_order": q.display_order,
                            "field": f"choices[{idx}]",
                            "length": len(c),
                        }
                    )
            if len(q.explanation) > length_limits["explanation"]:
                length_warnings.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "field": "explanation",
                        "length": len(q.explanation),
                    }
                )

            if story_scopes is None:
                continue
            evidence = parse_verse_evidence(q.explanation)
            if story_scope is None:
                verse_scope_violations.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "question_type": q.type,
                        "reason": "missing_story_scope",
                        "story_title": quiz.story_title,
                        "explanation": q.explanation,
                        "story_refs": [],
                    }
                )
                continue
            if evidence is None:
                verse_scope_violations.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "question_type": q.type,
                        "reason": "missing_verse_reference",
                        "story_title": story_scope.title,
                        "explanation": q.explanation,
                        "story_refs": [ref.label for ref in story_scope.refs],
                    }
                )
                continue
            if not any(ref.contains(evidence) for ref in story_scope.refs):
                verse_scope_violations.append(
                    {
                        "filename": quiz.path.name,
                        "display_order": q.display_order,
                        "question_type": q.type,
                        "reason": "outside_story_bible_ref",
                        "story_title": story_scope.title,
                        "evidence_ref": evidence.label,
                        "explanation": q.explanation,
                        "story_refs": [ref.label for ref in story_scope.refs],
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
        "verse_scope_violations": verse_scope_violations,
        "events_without_quiz": events_without_quiz,
        "length_warnings": length_warnings,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build quiz_questions seed SQL from assets/events/*.json."
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("supabase/quizzes/quizzes_seed.sql"),
        help="SQL output path.",
    )
    parser.add_argument(
        "--report",
        type=Path,
        default=Path("supabase/quizzes/quizzes_report.json"),
        help="Validation report path (JSON).",
    )
    parser.add_argument(
        "--stories-dir",
        type=Path,
        default=Path("assets/events"),
        help=(
            "Directory containing canonical event JSON files with embedded "
            "quiz_questions."
        ),
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(list(sys.argv[1:]) if argv is None else argv)

    if not args.stories_dir.exists():
        print(f"ERROR: events directory not found: {args.stories_dir}", file=sys.stderr)
        return 1
    try:
        events, quiz_files = load_events_and_quizzes_from_events_dir(args.stories_dir)
        story_scopes = load_story_ref_scopes(args.stories_dir)
    except QuizValidationError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1
    if not events:
        print("ERROR: no events parsed", file=sys.stderr)
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

    report = build_report(
        quiz_files=quiz_files,
        events=events,
        story_scopes=story_scopes,
    )

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

    if report["verse_scope_violations"]:
        print(
            f"ERROR: {len(report['verse_scope_violations'])} quiz verse refs "
            f"outside story bible_ref. See report for details.",
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
        f"OK: {report['total_quiz_files']} events with quizzes, "
        f"{report['total_questions']} questions -> {args.output}",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
