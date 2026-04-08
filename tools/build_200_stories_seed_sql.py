#!/usr/bin/env python3
"""Build SQL seed for assets/200_stories JSON data.

The script reads 215 story JSON entries and generates SQL for:
  - events
  - event_persons
  - event_bible_refs

Output directory defaults to: supabase/200_stories
"""

from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


BOOK_ABBR_TO_NO: dict[str, int] = {
    "창": 1,
    "출": 2,
    "레": 3,
    "민": 4,
    "신": 5,
    "수": 6,
    "삿": 7,
    "룻": 8,
    "삼상": 9,
    "삼하": 10,
    "왕상": 11,
    "왕하": 12,
    "대상": 13,
    "대하": 14,
    "스": 15,
    "느": 16,
    "에": 17,
    "욥": 18,
    "시": 19,
    "잠": 20,
    "전": 21,
    "아": 22,
    "사": 23,
    "렘": 24,
    "애": 25,
    "겔": 26,
    "단": 27,
    "호": 28,
    "욜": 29,
    "암": 30,
    "옵": 31,
    "욘": 32,
    "미": 33,
    "나": 34,
    "합": 35,
    "습": 36,
    "학": 37,
    "슥": 38,
    "말": 39,
    "마": 40,
    "막": 41,
    "눅": 42,
    "요": 43,
    "행": 44,
    "롬": 45,
    "고전": 46,
    "고후": 47,
    "갈": 48,
    "엡": 49,
    "빌": 50,
    "골": 51,
    "살전": 52,
    "살후": 53,
    "딤전": 54,
    "딤후": 55,
    "딛": 56,
    "몬": 57,
    "히": 58,
    "약": 59,
    "벧전": 60,
    "벧후": 61,
    "요일": 62,
    "요이": 63,
    "요삼": 64,
    "유": 65,
    "계": 66,
}

BOOK_NO_TO_NAME: dict[int, str] = {
    1: "창세기",
    2: "출애굽기",
    3: "레위기",
    4: "민수기",
    5: "신명기",
    6: "여호수아",
    7: "사사기",
    8: "룻기",
    9: "사무엘상",
    10: "사무엘하",
    11: "열왕기상",
    12: "열왕기하",
    13: "역대상",
    14: "역대하",
    15: "에스라",
    16: "느헤미야",
    17: "에스더",
    18: "욥기",
    19: "시편",
    20: "잠언",
    21: "전도서",
    22: "아가",
    23: "이사야",
    24: "예레미야",
    25: "예레미야애가",
    26: "에스겔",
    27: "다니엘",
    28: "호세아",
    29: "요엘",
    30: "아모스",
    31: "오바댜",
    32: "요나",
    33: "미가",
    34: "나훔",
    35: "하박국",
    36: "스바냐",
    37: "학개",
    38: "스가랴",
    39: "말라기",
    40: "마태복음",
    41: "마가복음",
    42: "누가복음",
    43: "요한복음",
    44: "사도행전",
    45: "로마서",
    46: "고린도전서",
    47: "고린도후서",
    48: "갈라디아서",
    49: "에베소서",
    50: "빌립보서",
    51: "골로새서",
    52: "데살로니가전서",
    53: "데살로니가후서",
    54: "디모데전서",
    55: "디모데후서",
    56: "디도서",
    57: "빌레몬서",
    58: "히브리서",
    59: "야고보서",
    60: "베드로전서",
    61: "베드로후서",
    62: "요한일서",
    63: "요한이서",
    64: "요한삼서",
    65: "유다서",
    66: "요한계시록",
}

VERSE_ROW_RE = re.compile(
    r"\('([^']*)',\s*'([^']*)',\s*(\d+),\s*'([^']*)',\s*(\d+),\s*(\d+),\s*'((?:[^']|'')*)'\)"
)
EVENT_NO_RE = re.compile(r"^(\d{3})\s+(.*)$")
CV_RE = re.compile(r"^\s*(\d+)\s*:\s*(\d+)\s*$")
SCENE_PREFIX_RE = re.compile(r"^\s*장면\s*\d+\s*:\s*")
MULTI_SPACE_RE = re.compile(r"\s+")

DISCIPLES_WITH_JUDAS = [
    "peter",
    "andrew",
    "james_zebedee",
    "john",
    "philip",
    "bartholomew",
    "matthew",
    "thomas",
    "james_alphaeus",
    "thaddaeus",
    "simon_zealot",
    "judas",
]
DISCIPLES_NO_JUDAS = [code for code in DISCIPLES_WITH_JUDAS if code != "judas"]
APOSTLES_AFTER_MATTHIAS = DISCIPLES_NO_JUDAS + ["matthias"]
BROTHERS_ALL = [
    "reuben",
    "simeon",
    "levi",
    "judah",
    "dan",
    "naphtali",
    "gad",
    "asher",
    "issachar",
    "zebulun",
    "benjamin",
]
BROTHERS_WITHOUT_BENJAMIN = [code for code in BROTHERS_ALL if code != "benjamin"]
ROSTER_EXCLUDED_CODES = {"dan"}

# Commonly used NT anchor years (kept conservative; mostly still approx).
# AD 70 temple destruction is treated as exact.
YEAR_OVERRIDES: dict[int, tuple[int | None, int | None, str]] = {
    185: (46, 46, "approx"),
    186: (46, 46, "approx"),
    187: (46, 46, "approx"),
    188: (47, 47, "approx"),
    189: (47, 47, "approx"),
    190: (48, 48, "approx"),
    191: (49, 49, "approx"),
    192: (50, 50, "approx"),
    193: (50, 50, "approx"),
    194: (50, 50, "approx"),
    195: (51, 51, "approx"),
    196: (51, 52, "approx"),
    197: (53, 55, "approx"),
    198: (56, 56, "approx"),
    199: (56, 57, "approx"),
    200: (57, 57, "approx"),
    201: (57, 57, "approx"),
    202: (59, 59, "approx"),
    203: (59, 59, "approx"),
    204: (60, 60, "approx"),
    205: (60, 62, "approx"),
    206: (70, 70, "exact"),
    207: (95, 95, "approx"),
    208: (95, 95, "approx"),
}

# When a story has no precise map point, keep it visible on the map with a
# conservative estimated anchor and an explicit "(추정)" label.
APPROX_LOCATION_OVERRIDES: dict[int, tuple[str, float, float]] = {
    1: ("메소포타미아(추정)", 31.018, 47.423),
    2: ("에덴 지역(추정)", 31.018, 47.423),
    3: ("에덴 지역(추정)", 31.018, 47.423),
    4: ("에덴 동쪽(추정)", 31.09, 47.52),
    5: ("에덴 밖 들판(추정)", 31.16, 47.61),
    132: ("그발 강가(추정)", 32.55, 44.42),
    166: ("베레아(요단 동편, 추정)", 31.93, 35.62),
    209: ("밧모섬(추정)", 37.31, 26.55),
    210: ("밧모섬(추정)", 37.31, 26.55),
    211: ("밧모섬(추정)", 37.31, 26.55),
    212: ("밧모섬(추정)", 37.31, 26.55),
    213: ("밧모섬(추정)", 37.31, 26.55),
    214: ("밧모섬(추정)", 37.31, 26.55),
    215: ("밧모섬(추정)", 37.31, 26.55),
}


@dataclass(frozen=True)
class BibleRef:
    book_abbr: str
    book_no: int
    book_name: str
    chapter_start: int
    verse_start: int
    chapter_end: int
    verse_end: int
    display_text: str


@dataclass
class NormalizedEvent:
    number: int
    code: str
    display_number: str
    era_code: str
    title: str
    summary: str
    story: str
    short_story: str
    story_scenes_text: str | None
    timeline_rank: float
    start_year: int | None
    end_year: int | None
    time_precision: str
    time_sort_key: int
    place_name: str
    lat: float | None
    lng: float | None
    persons: list[str]
    refs: list[BibleRef]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build seed SQL from assets/200_stories JSON files."
    )
    parser.add_argument(
        "--input-dir",
        default="assets/200_stories",
        help="Directory with 200 story JSON files.",
    )
    parser.add_argument(
        "--verse-source-sql",
        default="supabase/seeds/krv_bible_verses.sql",
        help="SQL file used as verse source.",
    )
    parser.add_argument(
        "--output-dir",
        default="supabase/200_stories",
        help="Output directory for generated SQL and reports.",
    )
    parser.add_argument(
        "--avatar-prompt-json",
        default="tools/avatar_prompts.json",
        help="Prompt JSON used as whitelist for person codes.",
    )
    parser.add_argument(
        "--translation",
        default="KRV",
        help="Translation code to read from verse source SQL.",
    )
    parser.add_argument(
        "--events-chunk-size",
        type=int,
        default=12,
        help="How many events to emit per SQL CTE chunk.",
    )
    parser.add_argument(
        "--refs-chunk-size",
        type=int,
        default=260,
        help="How many bible refs to emit per SQL CTE chunk.",
    )
    parser.add_argument(
        "--persons-chunk-size",
        type=int,
        default=420,
        help="How many event_person rows to emit per SQL CTE chunk.",
    )
    parser.add_argument(
        "--max-story-chars",
        type=int,
        default=18000,
        help="Maximum story text length per event.",
    )
    parser.add_argument(
        "--split-parts",
        type=int,
        default=2,
        help=(
            "Also write split SQL files for SQL Editor size limits. "
            "0 disables splitting."
        ),
    )
    parser.add_argument(
        "--events-per-part",
        type=int,
        default=0,
        help=(
            "When > 0, split SQL by this many events per part. "
            "Overrides --split-parts."
        ),
    )
    return parser.parse_args()


def sql_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def sql_value(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        text = f"{value:.8f}".rstrip("0").rstrip(".")
        return text if text else "0"
    return sql_literal(str(value))


def chunked(items: list[Any], size: int) -> list[list[Any]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def split_event_chunks(
    events: list["NormalizedEvent"], split_parts: int, events_per_part: int
) -> list[list["NormalizedEvent"]]:
    if not events:
        return []
    if events_per_part > 0:
        return chunked(events, max(1, events_per_part))
    if split_parts > 1:
        per_part = max(1, (len(events) + split_parts - 1) // split_parts)
        return chunked(events, per_part)
    return [events]


def normalize_space(text: str) -> str:
    return MULTI_SPACE_RE.sub(" ", text.replace("\n", " ").replace("\r", " ")).strip()


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    ordered: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        ordered.append(item)
    return ordered


def parse_cv(raw: str) -> tuple[int, int]:
    match = CV_RE.match(str(raw))
    if match is None:
        raise ValueError(f"Invalid chapter:verse value: {raw!r}")
    return int(match.group(1)), int(match.group(2))


def parse_event_number_and_title(raw_title: str) -> tuple[int, str]:
    match = EVENT_NO_RE.match(raw_title.strip())
    if match is None:
        raise ValueError(f"Title does not start with 3-digit index: {raw_title!r}")
    return int(match.group(1)), match.group(2).strip()


def strip_event_number_prefix(raw_title: str) -> str:
    match = EVENT_NO_RE.match(raw_title.strip())
    if match is None:
        return raw_title.strip()
    return match.group(2).strip()


def parse_story_number_and_title(row: dict[str, Any]) -> tuple[int, str]:
    raw_number = row.get("number")
    raw_title = str(row.get("title", "")).strip()
    if isinstance(raw_number, int):
        return raw_number, strip_event_number_prefix(raw_title)
    return parse_event_number_and_title(raw_title)


def parse_story_era_code(row: dict[str, Any]) -> str:
    era_code = str(row.get("era_code") or row.get("era") or "").strip()
    if not era_code:
        raise ValueError(f"Story row missing era/era_code: {row!r}")
    return era_code


def parse_story_refs(row: dict[str, Any]) -> list[Any]:
    value = row.get("bible_ref")
    if value is None:
        value = row.get("bible_refs")
    if not isinstance(value, list):
        return []
    return value


def parse_optional_timeline_rank(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    text = str(value).strip()
    if not text:
        return None
    return float(text)


def load_avatar_prompt_codes(prompt_json_path: Path) -> set[str]:
    if not prompt_json_path.exists():
        raise FileNotFoundError(f"Avatar prompt JSON not found: {prompt_json_path}")
    data = json.loads(prompt_json_path.read_text(encoding="utf-8"))
    characters = data.get("characters")
    if not isinstance(characters, list):
        raise ValueError(
            f"Invalid avatar prompt JSON format (missing characters list): {prompt_json_path}"
        )
    codes: set[str] = set()
    for item in characters:
        if not isinstance(item, dict):
            continue
        code = str(item.get("code", "")).strip()
        if code and code not in ROSTER_EXCLUDED_CODES:
            codes.add(code)
    if not codes:
        raise ValueError(f"No character codes found in avatar prompt JSON: {prompt_json_path}")
    return codes


def expand_person_codes(number: int, persons: list[str]) -> list[str]:
    expanded: list[str] = []
    persons_set = {code for code in persons}
    for code in persons:
        if code == "disciples":
            if "judas" in persons_set or number >= 175:
                expanded.extend(DISCIPLES_NO_JUDAS)
            else:
                expanded.extend(DISCIPLES_WITH_JUDAS)
            continue
        if code == "apostles":
            expanded.extend(APOSTLES_AFTER_MATTHIAS)
            continue
        if code == "brothers":
            if number in {38, 43, 44, 45}:
                expanded.extend(BROTHERS_WITHOUT_BENJAMIN)
            else:
                expanded.extend(BROTHERS_ALL)
            continue
        expanded.append(code)
    return dedupe_preserve_order(expanded)


def build_event_code(number: int, title: str, era_code: str, persons: list[str]) -> str:
    if era_code == "era_nt_apostolic" and "paul" in persons:
        if number in {185, 186, 187, 188, 189, 190} or "1차 선교" in title:
            return f"evt_nt_paul_j1_n{number:03d}"
        if number in {191, 192, 193, 194, 195, 196} or "2차 선교" in title:
            return f"evt_nt_paul_j2_n{number:03d}"
        if number in {197, 198, 199, 200} or "3차 선교" in title:
            return f"evt_nt_paul_j3_n{number:03d}"
        if number in {201, 202, 203, 204, 205} or "로마행" in title:
            return f"evt_nt_paul_rome_n{number:03d}"
    return f"evt_n{number:03d}"


def normalize_person_name(code: str) -> str:
    parts = [part for part in code.strip().split("_") if part]
    if not parts:
        return code
    return " ".join(part.capitalize() for part in parts)


def build_ref_display_text(book_abbr: str, ch_s: int, v_s: int, ch_e: int, v_e: int) -> str:
    if ch_s == ch_e and v_s == v_e:
        return f"{book_abbr} {ch_s}:{v_s}"
    if ch_s == ch_e:
        return f"{book_abbr} {ch_s}:{v_s}-{v_e}"
    return f"{book_abbr} {ch_s}:{v_s}-{ch_e}:{v_e}"


def parse_bible_ref(raw: dict[str, Any]) -> BibleRef:
    book_abbr = str(raw.get("book", "")).strip()
    if not book_abbr:
        raise ValueError(f"Missing bible_ref.book: {raw!r}")
    if book_abbr not in BOOK_ABBR_TO_NO:
        raise ValueError(f"Unknown bible book abbreviation: {book_abbr!r}")
    chapter_start, verse_start = parse_cv(str(raw.get("from", "")))
    chapter_end, verse_end = parse_cv(str(raw.get("to", "")))
    book_no = BOOK_ABBR_TO_NO[book_abbr]
    return BibleRef(
        book_abbr=book_abbr,
        book_no=book_no,
        book_name=BOOK_NO_TO_NAME[book_no],
        chapter_start=chapter_start,
        verse_start=verse_start,
        chapter_end=chapter_end,
        verse_end=verse_end,
        display_text=build_ref_display_text(
            book_abbr, chapter_start, verse_start, chapter_end, verse_end
        ),
    )


def load_verse_map(
    verse_sql_path: Path, translation: str
) -> tuple[dict[tuple[int, int, int], str], dict[tuple[int, int], int]]:
    if not verse_sql_path.exists():
        raise FileNotFoundError(f"Verse source SQL not found: {verse_sql_path}")

    verse_map: dict[tuple[int, int, int], str] = {}
    chapter_last_verse: dict[tuple[int, int], int] = {}
    with verse_sql_path.open("r", encoding="utf-8") as f:
        for line in f:
            for match in VERSE_ROW_RE.finditer(line):
                tr = match.group(1).strip().upper()
                if tr != translation.upper():
                    continue
                book_no = int(match.group(3))
                chapter_no = int(match.group(5))
                verse_no = int(match.group(6))
                verse_text = match.group(7).replace("''", "'").strip()
                key = (book_no, chapter_no, verse_no)
                verse_map[key] = normalize_space(verse_text)
                cv_key = (book_no, chapter_no)
                last = chapter_last_verse.get(cv_key, 0)
                if verse_no > last:
                    chapter_last_verse[cv_key] = verse_no
    return verse_map, chapter_last_verse


def collect_ref_verses(
    ref: BibleRef,
    verse_map: dict[tuple[int, int, int], str],
    chapter_last_verse: dict[tuple[int, int], int],
) -> list[str]:
    verses: list[str] = []
    for chapter in range(ref.chapter_start, ref.chapter_end + 1):
        start_verse = ref.verse_start if chapter == ref.chapter_start else 1
        if chapter == ref.chapter_end:
            end_verse = ref.verse_end
        else:
            end_verse = chapter_last_verse.get((ref.book_no, chapter), 0)
        if end_verse <= 0:
            continue
        for verse_no in range(start_verse, end_verse + 1):
            text = verse_map.get((ref.book_no, chapter, verse_no))
            if text:
                verses.append(text)
    return verses


def sanitize_scene_lines(lines: list[str]) -> list[str]:
    cleaned: list[str] = []
    for raw in lines:
        line = SCENE_PREFIX_RE.sub("", str(raw).strip())
        line = normalize_space(line)
        if not line:
            continue
        if line[-1] not in ".!?":
            line += "."
        cleaned.append(line)
    return cleaned


def build_short_story(summary: str, verse_lines: list[str], scene_lines: list[str]) -> str:
    if verse_lines:
        if len(verse_lines) <= 5:
            picked = verse_lines
        else:
            indexes = [0, len(verse_lines) // 4, len(verse_lines) // 2, (len(verse_lines) * 3) // 4, len(verse_lines) - 1]
            picked = []
            seen: set[int] = set()
            for idx in indexes:
                if idx not in seen:
                    picked.append(verse_lines[idx])
                    seen.add(idx)
        normalized = []
        for item in picked:
            sentence = normalize_space(item)
            if sentence and sentence[-1] not in ".!?":
                sentence += "."
            if sentence:
                normalized.append(sentence)
        if normalized:
            return " ".join(normalized[:5]).strip()

    scenes = sanitize_scene_lines(scene_lines)
    if scenes:
        return " ".join(scenes[:5]).strip()
    return normalize_space(summary)


def build_story(summary: str, refs: list[BibleRef], all_ref_verses: list[list[str]], max_chars: int) -> str:
    paragraphs: list[str] = []
    summary_text = normalize_space(summary)
    if summary_text:
        paragraphs.append(summary_text)

    for ref, verses in zip(refs, all_ref_verses):
        if not verses:
            continue
        if len(verses) <= 90:
            selected = verses
            suffix = ""
        else:
            selected = verses[:45] + verses[-45:]
            suffix = " (중간 본문 일부 생략)"
        body = " ".join(normalize_space(v) for v in selected if normalize_space(v))
        if not body:
            continue
        paragraphs.append(f"{ref.display_text} 본문 흐름: {body}{suffix}")

    if not paragraphs:
        return summary_text

    story = "\n\n".join(paragraphs).strip()
    if len(story) > max_chars:
        story = story[: max_chars - 1].rstrip() + "…"
    return story


def normalize_timeline(
    number: int, start_year: int | None, end_year: int | None, time_precision: str
) -> tuple[int | None, int | None, str]:
    if number in YEAR_OVERRIDES:
        return YEAR_OVERRIDES[number]
    precision = (time_precision or "approx").strip().lower()
    if precision not in {"approx", "exact"}:
        precision = "approx"
    return start_year, end_year, precision


def make_time_sort_key(number: int, start_year: int | None, end_year: int | None) -> int:
    year = start_year
    if year is None:
        year = end_year
    if year is None:
        return 900_000 + number
    return year * 1_000 + number


def apply_approx_location_override(
    number: int, place_name: str, lat: float | None, lng: float | None
) -> tuple[str, float | None, float | None]:
    if lat is not None and lng is not None:
        return place_name, lat, lng
    override = APPROX_LOCATION_OVERRIDES.get(number)
    if override is None:
        return place_name, lat, lng
    override_place_name, override_lat, override_lng = override
    return override_place_name, override_lat, override_lng


def parse_story_rows(input_dir: Path) -> list[dict[str, Any]]:
    if not input_dir.exists():
        raise FileNotFoundError(f"Input dir not found: {input_dir}")
    files = sorted(input_dir.glob("*.json"), key=lambda p: p.name)
    if not files:
        raise FileNotFoundError(f"No JSON files found in: {input_dir}")

    rows: list[dict[str, Any]] = []
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError(f"JSON root must be list: {path}")
        for item in data:
            if not isinstance(item, dict):
                raise ValueError(f"Story row is not object in {path}: {item!r}")
            rows.append(item)
    rows.sort(key=lambda row: parse_story_number_and_title(row)[0])
    return rows


def normalize_events(
    rows: list[dict[str, Any]],
    verse_map: dict[tuple[int, int, int], str],
    chapter_last_verse: dict[tuple[int, int], int],
    allowed_person_codes: set[str],
    max_story_chars: int,
) -> tuple[list[NormalizedEvent], set[str], int]:
    events: list[NormalizedEvent] = []
    person_codes: set[str] = set()
    missing_verse_segments = 0

    used_codes: set[str] = set()

    for row in rows:
        number, clean_title = parse_story_number_and_title(row)
        raw_persons = [
            str(code).strip() for code in row.get("persons", []) if str(code).strip()
        ]
        persons = [
            code
            for code in expand_person_codes(number, raw_persons)
            if code in allowed_person_codes
        ]
        refs = [parse_bible_ref(item) for item in parse_story_refs(row)]
        scene_lines = row.get("story_scenes") or row.get("short_story") or []
        scene_lines = [str(item) for item in scene_lines if str(item).strip()]

        ref_verses: list[list[str]] = []
        combined_verses: list[str] = []
        for ref in refs:
            verses = collect_ref_verses(ref, verse_map, chapter_last_verse)
            if not verses:
                missing_verse_segments += 1
            ref_verses.append(verses)
            combined_verses.extend(verses)

        start_year = row.get("start_year")
        end_year = row.get("end_year")
        start_year_int = int(start_year) if isinstance(start_year, int) else None
        end_year_int = int(end_year) if isinstance(end_year, int) else None
        start_year_int, end_year_int, time_precision = normalize_timeline(
            number=number,
            start_year=start_year_int,
            end_year=end_year_int,
            time_precision=str(row.get("time_precision", "approx")),
        )

        summary = normalize_space(str(row.get("summary", "")))
        story = build_story(summary, refs, ref_verses, max_chars=max_story_chars)
        short_story = build_short_story(summary, combined_verses, scene_lines)

        story_scenes_text: str | None = None
        if scene_lines:
            story_scenes_text = json.dumps(
                sanitize_scene_lines(scene_lines), ensure_ascii=False
            )

        era_code = parse_story_era_code(row)
        explicit_code = str(row.get("code") or "").strip()
        code = explicit_code or build_event_code(number, clean_title, era_code, persons)
        if code in used_codes:
            code = f"{code}_{number}"
        used_codes.add(code)
        display_number = str(row.get("display_number") or "").strip() or f"{number:03d}"

        place_name = normalize_space(str(row.get("place_name", "")))
        lat = row.get("lat")
        lng = row.get("lng")
        lat_f = float(lat) if isinstance(lat, (int, float)) else None
        lng_f = float(lng) if isinstance(lng, (int, float)) else None
        place_name, lat_f, lng_f = apply_approx_location_override(
            number, place_name, lat_f, lng_f
        )

        explicit_timeline_rank = parse_optional_timeline_rank(row.get("timeline_rank"))

        event = NormalizedEvent(
            number=number,
            code=code,
            display_number=display_number,
            era_code=era_code,
            title=clean_title,
            summary=summary,
            story=story,
            short_story=short_story,
            story_scenes_text=story_scenes_text,
            timeline_rank=explicit_timeline_rank
            if explicit_timeline_rank is not None
            else float(make_time_sort_key(number, start_year_int, end_year_int)),
            start_year=start_year_int,
            end_year=end_year_int,
            time_precision=time_precision,
            time_sort_key=make_time_sort_key(number, start_year_int, end_year_int),
            place_name=place_name,
            lat=lat_f,
            lng=lng_f,
            persons=persons,
            refs=refs,
        )
        person_codes.update(persons)
        events.append(event)

    return events, person_codes, missing_verse_segments


def render_events_sql(events: list[NormalizedEvent], chunk_size: int) -> list[str]:
    lines: list[str] = []
    for chunk in chunked(events, chunk_size):
        lines.append(
            "with seed_events ("
            "code, display_number, era_code, title, summary, story, short_story, story_scenes, "
            "timeline_rank, "
            "start_year, end_year, time_sort_key, time_precision, place_name, lat, lng"
            ") as ("
        )
        lines.append("  values")
        values = []
        for event in chunk:
            values.append(
                "    ("
                f"{sql_value(event.code)}, "
                f"{sql_value(event.display_number)}, "
                f"{sql_value(event.era_code)}, "
                f"{sql_value(event.title)}, "
                f"{sql_value(event.summary)}, "
                f"{sql_value(event.story)}, "
                f"{sql_value(event.short_story)}, "
                f"{sql_value(event.story_scenes_text)}, "
                f"{sql_value(event.timeline_rank)}, "
                f"{sql_value(event.start_year)}, "
                f"{sql_value(event.end_year)}, "
                f"{sql_value(event.time_sort_key)}, "
                f"{sql_value(event.time_precision)}, "
                f"{sql_value(event.place_name)}, "
                f"{sql_value(event.lat)}, "
                f"{sql_value(event.lng)}"
                ")"
            )
        lines.append(",\n".join(values))
        lines.append(")")
        lines.append(
            "insert into events ("
            "code, display_number, era_id, title, summary, story, short_story, story_scenes, "
            "timeline_rank, "
            "start_year, end_year, time_sort_key, time_precision, place_name, lat, lng"
            ")"
        )
        lines.append("select")
        lines.append("  s.code,")
        lines.append("  s.display_number,")
        lines.append("  e.id,")
        lines.append("  s.title,")
        lines.append("  s.summary,")
        lines.append("  s.story,")
        lines.append("  s.short_story,")
        lines.append("  s.story_scenes,")
        lines.append("  s.timeline_rank,")
        lines.append("  s.start_year,")
        lines.append("  s.end_year,")
        lines.append("  s.time_sort_key,")
        lines.append("  s.time_precision,")
        lines.append("  s.place_name,")
        lines.append("  s.lat,")
        lines.append("  s.lng")
        lines.append("from seed_events s")
        lines.append("join eras e on e.code = s.era_code")
        lines.append("on conflict (code) do update set")
        lines.append("  display_number = excluded.display_number,")
        lines.append("  era_id = excluded.era_id,")
        lines.append("  title = excluded.title,")
        lines.append("  summary = excluded.summary,")
        lines.append("  story = excluded.story,")
        lines.append("  short_story = excluded.short_story,")
        lines.append("  story_scenes = excluded.story_scenes,")
        lines.append("  timeline_rank = excluded.timeline_rank,")
        lines.append("  start_year = excluded.start_year,")
        lines.append("  end_year = excluded.end_year,")
        lines.append("  time_sort_key = excluded.time_sort_key,")
        lines.append("  time_precision = excluded.time_precision,")
        lines.append("  place_name = excluded.place_name,")
        lines.append("  lat = excluded.lat,")
        lines.append("  lng = excluded.lng")
        lines.append(";")
        lines.append("")
    return lines


def render_event_persons_sql(events: list[NormalizedEvent], chunk_size: int) -> list[str]:
    rows: list[tuple[str, str, int, str]] = []
    for event in events:
        seen: set[str] = set()
        for idx, person_code in enumerate(event.persons, start=1):
            if person_code in seen:
                continue
            seen.add(person_code)
            role = "main" if idx == 1 else "support"
            rows.append((event.code, person_code, idx, role))

    lines: list[str] = []
    for chunk in chunked(rows, chunk_size):
        lines.append(
            "with seed_event_persons (event_code, person_code, person_sequence, role) as ("
        )
        lines.append("  values")
        values = [
            "    ("
            f"{sql_value(event_code)}, {sql_value(person_code)}, {sql_value(seq)}, {sql_value(role)}"
            ")"
            for event_code, person_code, seq, role in chunk
        ]
        lines.append(",\n".join(values))
        lines.append(")")
        lines.append("insert into event_persons (event_id, person_id, person_sequence, role)")
        lines.append("select")
        lines.append("  e.id,")
        lines.append("  p.id,")
        lines.append("  s.person_sequence,")
        lines.append("  s.role")
        lines.append("from seed_event_persons s")
        lines.append("join events e on e.code = s.event_code")
        lines.append("join persons p on p.code = s.person_code")
        lines.append("on conflict (event_id, person_id) do update set")
        lines.append("  person_sequence = excluded.person_sequence,")
        lines.append("  role = excluded.role")
        lines.append(";")
        lines.append("")
    return lines


def render_event_refs_sql(events: list[NormalizedEvent], chunk_size: int) -> list[str]:
    rows: list[tuple[str, str, int, int, int, int, str]] = []
    for event in events:
        for ref in event.refs:
            rows.append(
                (
                    event.code,
                    ref.book_name,
                    ref.chapter_start,
                    ref.verse_start,
                    ref.chapter_end,
                    ref.verse_end,
                    ref.display_text,
                )
            )

    lines: list[str] = []
    for chunk in chunked(rows, chunk_size):
        lines.append(
            "with seed_event_refs ("
            "event_code, book, chapter_start, verse_start, chapter_end, verse_end, display_text"
            ") as ("
        )
        lines.append("  values")
        values = [
            "    ("
            f"{sql_value(event_code)}, "
            f"{sql_value(book)}, "
            f"{sql_value(ch_s)}, "
            f"{sql_value(v_s)}, "
            f"{sql_value(ch_e)}, "
            f"{sql_value(v_e)}, "
            f"{sql_value(display)}"
            ")"
            for event_code, book, ch_s, v_s, ch_e, v_e, display in chunk
        ]
        lines.append(",\n".join(values))
        lines.append(")")
        lines.append(
            "insert into event_bible_refs ("
            "event_id, book, chapter_start, verse_start, chapter_end, verse_end, display_text"
            ")"
        )
        lines.append("select")
        lines.append("  e.id,")
        lines.append("  r.book,")
        lines.append("  r.chapter_start,")
        lines.append("  r.verse_start,")
        lines.append("  r.chapter_end,")
        lines.append("  r.verse_end,")
        lines.append("  r.display_text")
        lines.append("from seed_event_refs r")
        lines.append("join events e on e.code = r.event_code")
        lines.append("on conflict (event_id, display_text) do update set")
        lines.append("  book = excluded.book,")
        lines.append("  chapter_start = excluded.chapter_start,")
        lines.append("  verse_start = excluded.verse_start,")
        lines.append("  chapter_end = excluded.chapter_end,")
        lines.append("  verse_end = excluded.verse_end")
        lines.append(";")
        lines.append("")
    return lines


def render_delete_links_sql(event_codes: list[str]) -> list[str]:
    lines: list[str] = []
    for chunk in chunked(event_codes, 120):
        in_values = ", ".join(sql_value(code) for code in chunk)
        lines.append(
            "delete from event_persons ep using events e "
            "where ep.event_id = e.id and e.code in "
            f"({in_values});"
        )
        lines.append(
            "delete from event_bible_refs br using events e "
            "where br.event_id = e.id and e.code in "
            f"({in_values});"
        )
    lines.append("")
    return lines


def render_persons_sql(person_codes: list[str]) -> list[str]:
    lines: list[str] = []
    for chunk in chunked(person_codes, 120):
        lines.append("insert into persons (code, name, is_active)")
        lines.append("values")
        values = [
            f"  ({sql_value(code)}, {sql_value(normalize_person_name(code))}, true)"
            for code in chunk
        ]
        lines.append(",\n".join(values))
        lines.append("on conflict (code) do nothing;")
        lines.append("")
    return lines


def build_seed_sql(
    events: list[NormalizedEvent],
    person_codes: set[str],
    *,
    events_chunk_size: int,
    refs_chunk_size: int,
    persons_chunk_size: int,
) -> str:
    lines: list[str] = []
    generated_at = datetime.now(timezone.utc).isoformat()
    lines.append("-- Generated by tools/build_200_stories_seed_sql.py")
    lines.append(f"-- Generated at UTC: {generated_at}")
    lines.append("-- Target tables: events, event_persons, event_bible_refs")
    lines.append("begin;")
    lines.append("")
    lines.append("-- Ensure person codes exist (placeholder names for unknown codes)")
    lines.extend(render_persons_sql(sorted(person_codes)))
    lines.append("-- Upsert events from 200 stories")
    lines.extend(render_events_sql(events, events_chunk_size))
    lines.append("-- Refresh link tables for target events")
    lines.extend(render_delete_links_sql([event.code for event in events]))
    lines.append("-- Insert event-person links")
    lines.extend(render_event_persons_sql(events, persons_chunk_size))
    lines.append("-- Insert bible references")
    lines.extend(render_event_refs_sql(events, refs_chunk_size))
    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


def write_report(report_path: Path, events: list[NormalizedEvent], missing_verse_segments: int) -> None:
    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "event_count": len(events),
        "event_codes_sample": [event.code for event in events[:12]],
        "missing_verse_segments": missing_verse_segments,
        "notes": [
            "story is auto-composed from bible_verses (KRV) ranges",
            "short_story uses scene lines when present, otherwise verse-based fallback",
            "timeline uses JSON values plus conservative NT overrides",
            "person codes are expanded for disciples/apostles/brothers then filtered by avatar prompt whitelist",
        ],
    }
    report_path.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def write_normalized_json(path: Path, events: list[NormalizedEvent]) -> None:
    payload: list[dict[str, Any]] = []
    for event in events:
        payload.append(
            {
                "number": event.number,
                "code": event.code,
                "display_number": event.display_number,
                "era_code": event.era_code,
                "title": event.title,
                "summary": event.summary,
                "timeline_rank": event.timeline_rank,
                "start_year": event.start_year,
                "end_year": event.end_year,
                "time_precision": event.time_precision,
                "time_sort_key": event.time_sort_key,
                "place_name": event.place_name,
                "lat": event.lat,
                "lng": event.lng,
                "persons": event.persons,
                "bible_refs": [
                    {
                        "book_name": ref.book_name,
                        "display_text": ref.display_text,
                        "chapter_start": ref.chapter_start,
                        "verse_start": ref.verse_start,
                        "chapter_end": ref.chapter_end,
                        "verse_end": ref.verse_end,
                    }
                    for ref in event.refs
                ],
            }
        )
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> int:
    args = parse_args()
    input_dir = Path(args.input_dir)
    verse_source = Path(args.verse_source_sql)
    avatar_prompt_json = Path(args.avatar_prompt_json)
    output_dir = Path(args.output_dir)

    rows = parse_story_rows(input_dir)
    verse_map, chapter_last_verse = load_verse_map(verse_source, args.translation)
    allowed_person_codes = load_avatar_prompt_codes(avatar_prompt_json)
    events, person_codes, missing_verse_segments = normalize_events(
        rows,
        verse_map,
        chapter_last_verse,
        allowed_person_codes,
        max_story_chars=args.max_story_chars,
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    seed_sql_text = build_seed_sql(
        events,
        person_codes,
        events_chunk_size=max(1, args.events_chunk_size),
        refs_chunk_size=max(1, args.refs_chunk_size),
        persons_chunk_size=max(1, args.persons_chunk_size),
    )

    sql_path = output_dir / "200_stories_seed.sql"
    report_path = output_dir / "200_stories_report.json"
    normalized_path = output_dir / "200_stories_normalized.json"

    sql_path.write_text(seed_sql_text, encoding="utf-8")
    write_report(report_path, events, missing_verse_segments)
    write_normalized_json(normalized_path, events)

    part_paths: list[Path] = []
    part_chunks = split_event_chunks(
        events,
        split_parts=max(0, int(args.split_parts)),
        events_per_part=max(0, int(args.events_per_part)),
    )
    if len(part_chunks) > 1:
        for idx, part_events in enumerate(part_chunks, start=1):
            part_person_codes = {
                person_code for event in part_events for person_code in event.persons
            }
            part_sql_text = build_seed_sql(
                part_events,
                part_person_codes,
                events_chunk_size=max(1, args.events_chunk_size),
                refs_chunk_size=max(1, args.refs_chunk_size),
                persons_chunk_size=max(1, args.persons_chunk_size),
            )
            part_path = output_dir / f"200_stories_seed_part_{idx:02d}.sql"
            part_path.write_text(part_sql_text, encoding="utf-8")
            part_paths.append(part_path)

    print(f"input dir            : {input_dir}")
    print(f"verse source         : {verse_source}")
    print(f"avatar prompt json   : {avatar_prompt_json}")
    print(f"events parsed        : {len(events)}")
    print(f"unique person codes  : {len(person_codes)}")
    print(f"missing verse ranges : {missing_verse_segments}")
    print(f"output sql           : {sql_path}")
    print(f"output report        : {report_path}")
    print(f"output normalized    : {normalized_path}")
    if part_paths:
        print(f"output split sql     : {len(part_paths)} files")
        for path in part_paths:
            print(f"  - {path}")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
