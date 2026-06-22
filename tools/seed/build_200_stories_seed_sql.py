#!/usr/bin/env python3
"""Build SQL seed for the events table from assets/200_stories JSON data.

The script reads ~215 story JSON entries and generates one INSERT statement
per chunk into the ``events`` table. Per the new schema:
  - ``character_codes`` (text[]) embeds the expanded character list — no event_persons
  - ``bible_refs`` (jsonb)    embeds [{book, from, to}, ...] — no event_bible_refs
  - ``background_context`` stores a short user-facing background knowledge blurb
  - ``story_scenes`` (jsonb)  embeds the scene array as-is
  - ``scene_captions`` (jsonb) embeds short captions aligned with story_scenes
  - ``scene_characters`` (jsonb) embeds the per-scene character lists
  - ``story_index`` is taken straight from the JSON; uniqueness is enforced
    by (era_id, story_index) so the upsert key is the same pair

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
ROSTER_EXCLUDED_CODES = {"dan", "lot_wife"}

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
    era_code: str
    title: str
    summary: str
    background_context: str
    story_scenes: list[str]
    scene_captions: list[str]
    scene_characters: list[list[str]]
    start_year: int | None
    end_year: int | None
    time_precision: str
    story_index: int
    unit_code: str
    unit_title: str
    unit_order: int
    landmark_code: str  # v2 위치 모델 — events.landmark_id 의 source
    characters: list[str]
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
        "--output-dir",
        default="supabase/200_stories",
        help="Output directory for generated SQL and reports.",
    )
    parser.add_argument(
        "--character-meta-json",
        default="tools/seed/character_meta.json",
        help="Character meta JSON used as whitelist for character codes.",
    )
    parser.add_argument(
        "--landmark-mapping",
        default="assets/landmarks/event_region_mapping.json",
        help=(
            "Mapping JSON: (era, story_index) → (region_code, landmark_code). "
            "v3 카탈로그 기준 — landmark_code 가 lm_<era>_<name> 형식."
        ),
    )
    parser.add_argument(
        "--events-chunk-size",
        type=int,
        default=24,
        help="How many events to emit per SQL CTE chunk.",
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
    """제목 앞 3자리 번호가 있으면 분리, 없으면 (0, 원본 title) 반환.

    히스토리: 예전엔 모든 제목이 "001 창조: 7일과 안식" 형태였으나, JSON 에서
    번호를 빼는 변경으로 이제 "창조: 7일과 안식" 만 남는다. 이 함수는 (a) 번호
    없는 새 포맷도 받아들이고, (b) caller 가 number 가 필요하면 row.story_index
    로부터 받도록 권장하기 위한 호환 래퍼다.
    """
    match = EVENT_NO_RE.match(raw_title.strip())
    if match is None:
        return 0, raw_title.strip()
    return int(match.group(1)), match.group(2).strip()


def load_person_meta_codes(meta_json_path: Path) -> set[str]:
    if not meta_json_path.exists():
        raise FileNotFoundError(f"Character meta JSON not found: {meta_json_path}")
    data = json.loads(meta_json_path.read_text(encoding="utf-8"))
    characters = data.get("characters")
    if not isinstance(characters, list):
        raise ValueError(
            f"Invalid character meta JSON format (missing characters list): {meta_json_path}"
        )
    codes: set[str] = set()
    for item in characters:
        if not isinstance(item, dict):
            continue
        if bool(item.get("asset_only", False)):
            continue
        code = str(item.get("code", "")).strip()
        if code and code not in ROSTER_EXCLUDED_CODES:
            codes.add(code)
    if not codes:
        raise ValueError(
            f"No character codes found in character meta JSON: {meta_json_path}"
        )
    return codes


def expand_person_codes(number: int, characters: list[str]) -> list[str]:
    expanded: list[str] = []
    persons_set = {code for code in characters}
    for code in characters:
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


def build_ref_display_text(
    book_abbr: str, ch_s: int, v_s: int, ch_e: int, v_e: int
) -> str:
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


def sanitize_scene_line(raw: str) -> str:
    line = SCENE_PREFIX_RE.sub("", str(raw).strip())
    return normalize_space(line)


def normalize_timeline(
    number: int, start_year: int | None, end_year: int | None, time_precision: str
) -> tuple[int | None, int | None, str]:
    if number in YEAR_OVERRIDES:
        return YEAR_OVERRIDES[number]
    precision = (time_precision or "approx").strip().lower()
    if precision not in {"approx", "exact"}:
        precision = "approx"
    return start_year, end_year, precision


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
    # 번호 없는 새 JSON 포맷에서는 title 앞 3자리가 없어 parse_* 가 0 을 반환 →
    # 정렬이 무의미. story_index 로 안정 정렬한다.
    rows.sort(
        key=lambda row: (
            int(row["story_index"]) if isinstance(row.get("story_index"), int) else 0,
            str(row.get("title", "")),
        )
    )
    return rows


def normalize_events(
    rows: list[dict[str, Any]],
    allowed_person_codes: set[str],
    landmark_mapping: dict[tuple[str, int], str],
) -> tuple[list[NormalizedEvent], set[str]]:
    events: list[NormalizedEvent] = []
    character_codes: set[str] = set()

    for row in rows:
        # JSON 의 새 포맷은 title 에 번호가 없으므로 number 는 story_index 에서 가져온다.
        # parse_event_number_and_title 는 번호가 있으면 분리하고 없으면 (0, title) 반환 →
        # 양쪽 모두 호환되도록 story_index 를 우선 신뢰한다.
        _, clean_title = parse_event_number_and_title(str(row["title"]))
        story_index_for_number = row.get("story_index")
        if isinstance(story_index_for_number, int):
            number = story_index_for_number
        else:
            number = _
        raw_persons = [
            str(code).strip() for code in row.get("characters", []) if str(code).strip()
        ]
        characters = [
            code
            for code in expand_person_codes(number, raw_persons)
            if code in allowed_person_codes
        ]
        refs = [parse_bible_ref(item) for item in row.get("bible_ref", [])]

        raw_scenes = row.get("story_scenes") or []
        story_scenes = [
            sanitize_scene_line(item) for item in raw_scenes if str(item).strip()
        ]
        story_scenes = [scene for scene in story_scenes if scene]

        raw_captions = row.get("scene_captions") or []
        scene_captions = [
            normalize_space(str(item)) for item in raw_captions if str(item).strip()
        ]
        if story_scenes and len(scene_captions) < len(story_scenes):
            scene_captions.extend(
                "" for _ in range(len(story_scenes) - len(scene_captions))
            )
        if story_scenes and len(scene_captions) > len(story_scenes):
            scene_captions = scene_captions[: len(story_scenes)]

        raw_scene_persons = row.get("scene_characters") or []
        scene_characters: list[list[str]] = []
        for entry in raw_scene_persons:
            if isinstance(entry, list):
                expanded = [
                    code
                    for code in expand_person_codes(
                        number, [str(c).strip() for c in entry if str(c).strip()]
                    )
                    if code in allowed_person_codes
                ]
                scene_characters.append(expanded)
            else:
                scene_characters.append([])
        # Pad / trim to align with story_scenes length when both present.
        if story_scenes and len(scene_characters) < len(story_scenes):
            scene_characters.extend(
                [] for _ in range(len(story_scenes) - len(scene_characters))
            )
        if story_scenes and len(scene_characters) > len(story_scenes):
            scene_characters = scene_characters[: len(story_scenes)]

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
        background_context = normalize_space(str(row.get("background_context", "")))

        story_index = row.get("story_index")
        if not isinstance(story_index, int):
            raise ValueError(
                f"story_index missing or not int for title={row.get('title')!r}; "
                "Each item in assets/200_stories/*.json must include an integer story_index "
                "(era-scoped 1..N). Add it manually or via the admin web UI."
            )

        era_code = str(row["era"]).strip()
        story_index_int = int(story_index)
        unit_code = normalize_space(str(row.get("unit_code", "default"))) or "default"
        unit_title = (
            normalize_space(str(row.get("unit_title", "전체 흐름"))) or "전체 흐름"
        )
        raw_unit_order = row.get("unit_order", 1)
        unit_order = int(raw_unit_order) if isinstance(raw_unit_order, int) else 1
        landmark_code = landmark_mapping.get((era_code, story_index_int))
        if not landmark_code:
            raise ValueError(
                f"매핑 누락: era={era_code} story_index={story_index_int} "
                f"title={row.get('title')!r} — "
                "assets/landmarks/event_region_mapping.json 에서 "
                "이 (era, story_index) 키에 대응하는 region/anchor/minor code 를 추가하세요."
            )

        events.append(
            NormalizedEvent(
                number=number,
                era_code=era_code,
                title=str(row["title"]).strip(),
                summary=summary,
                background_context=background_context,
                story_scenes=story_scenes,
                scene_captions=scene_captions,
                scene_characters=scene_characters,
                start_year=start_year_int,
                end_year=end_year_int,
                time_precision=time_precision,
                story_index=story_index_int,
                unit_code=unit_code,
                unit_title=unit_title,
                unit_order=unit_order,
                landmark_code=landmark_code,
                characters=characters,
                refs=refs,
            )
        )
        character_codes.update(characters)

    return events, character_codes


def text_array_literal(items: list[str]) -> str:
    if not items:
        return "ARRAY[]::text[]"
    quoted = ", ".join(sql_literal(item) for item in items)
    return f"ARRAY[{quoted}]::text[]"


def jsonb_literal(value: Any) -> str:
    text = json.dumps(value, ensure_ascii=False)
    return f"{sql_literal(text)}::jsonb"


def serialize_bible_refs(refs: list[BibleRef]) -> list[dict[str, str]]:
    return [
        {
            "book": ref.book_abbr,
            "from": f"{ref.chapter_start}:{ref.verse_start}",
            "to": f"{ref.chapter_end}:{ref.verse_end}",
        }
        for ref in refs
    ]


def render_events_sql(events: list[NormalizedEvent], chunk_size: int) -> list[str]:
    lines: list[str] = []
    columns = (
        "era_code, title, summary, background_context, story_scenes, scene_captions, "
        "scene_characters, character_codes, "
        "bible_refs, start_year, end_year, time_precision, story_index, "
        "unit_code, unit_title, unit_order, landmark_code, status"
    )
    for chunk in chunked(events, chunk_size):
        lines.append(f"with seed_events ({columns}) as (")
        lines.append("  values")
        values: list[str] = []
        for event in chunk:
            values.append(
                "    ("
                f"{sql_value(event.era_code)}, "
                f"{sql_value(event.title)}, "
                f"{sql_value(event.summary)}, "
                f"{sql_value(event.background_context)}, "
                f"{jsonb_literal(event.story_scenes)}, "
                f"{jsonb_literal(event.scene_captions)}, "
                f"{jsonb_literal(event.scene_characters)}, "
                f"{text_array_literal(event.characters)}, "
                f"{jsonb_literal(serialize_bible_refs(event.refs))}, "
                f"{sql_value(event.start_year)}, "
                f"{sql_value(event.end_year)}, "
                f"{sql_value(event.time_precision)}, "
                f"{sql_value(event.story_index)}, "
                f"{sql_value(event.unit_code)}, "
                f"{sql_value(event.unit_title)}, "
                f"{sql_value(event.unit_order)}, "
                f"{sql_value(event.landmark_code)}, "
                f"{sql_value('published')}"
                ")"
            )
        lines.append(",\n".join(values))
        lines.append(")")
        lines.append(
            "insert into events ("
            "era_id, title, summary, background_context, story_scenes, scene_captions, "
            "scene_characters, character_codes, "
            "bible_refs, start_year, end_year, time_precision, story_index, "
            "unit_code, unit_title, unit_order, landmark_id, status"
            ")"
        )
        lines.append("select")
        lines.append("  e.id,")
        lines.append("  s.title,")
        lines.append("  s.summary,")
        lines.append("  s.background_context,")
        lines.append("  s.story_scenes,")
        lines.append("  s.scene_captions,")
        lines.append("  s.scene_characters,")
        lines.append("  s.character_codes,")
        lines.append("  s.bible_refs,")
        lines.append("  s.start_year,")
        lines.append("  s.end_year,")
        lines.append("  s.time_precision,")
        lines.append("  s.story_index,")
        lines.append("  s.unit_code,")
        lines.append("  s.unit_title,")
        lines.append("  s.unit_order,")
        lines.append("  lm.id,")
        lines.append("  s.status")
        lines.append("from seed_events s")
        lines.append("join eras e on e.code = s.era_code")
        lines.append("join landmarks lm on lm.code = s.landmark_code")
        lines.append("on conflict (era_id, story_index) do update set")
        lines.append("  title = excluded.title,")
        lines.append("  summary = excluded.summary,")
        lines.append("  background_context = excluded.background_context,")
        lines.append("  story_scenes = excluded.story_scenes,")
        lines.append("  scene_captions = excluded.scene_captions,")
        lines.append("  scene_characters = excluded.scene_characters,")
        lines.append("  character_codes = excluded.character_codes,")
        lines.append("  bible_refs = excluded.bible_refs,")
        lines.append("  start_year = excluded.start_year,")
        lines.append("  end_year = excluded.end_year,")
        lines.append("  time_precision = excluded.time_precision,")
        lines.append("  unit_code = excluded.unit_code,")
        lines.append("  unit_title = excluded.unit_title,")
        lines.append("  unit_order = excluded.unit_order,")
        lines.append("  landmark_id = excluded.landmark_id,")
        lines.append("  status = excluded.status")
        lines.append(";")
        lines.append("")
    return lines


def render_delete_stale_events_sql(events: list[NormalizedEvent]) -> list[str]:
    """현재 JSON 에 없는 (era_id, story_index) 조합의 events 를 삭제한다.

    user 가 stories JSON 에서 사건을 지우면 DB 에 남은 row 도 정리되어야
    "JSON 이 단일 진실 소스" 약속이 유지된다. events 의존 테이블들은
    on delete cascade 로 잡혀 있어 안전하다 (quiz_questions 등).
    """
    lines: list[str] = []
    lines.append("-- Delete events that no longer exist in current stories JSON")
    if not events:
        # JSON 이 비어있으면 통째로 비우는 것은 위험. 방어적으로 skip.
        lines.append(
            "-- (skipped: events list is empty — refusing to wipe the whole table)"
        )
        return lines
    pairs: list[tuple[str, int]] = sorted(
        {(event.era_code, event.story_index) for event in events}
    )
    pair_values = ", ".join(
        f"({sql_literal(era_code)}, {story_index})" for era_code, story_index in pairs
    )
    lines.append("with keep_pairs (era_code, story_index) as (")
    lines.append(f"  values {pair_values}")
    lines.append(")")
    lines.append("delete from events e")
    lines.append("using eras er")
    lines.append("where er.id = e.era_id")
    lines.append("  and not exists (")
    lines.append("    select 1 from keep_pairs k")
    lines.append("    where k.era_code = er.code and k.story_index = e.story_index")
    lines.append("  );")
    lines.append("")
    return lines


def build_seed_sql(
    events: list[NormalizedEvent],
    *,
    events_chunk_size: int,
    include_delete_stale: bool = True,
    full_keep_events: list[NormalizedEvent] | None = None,
) -> str:
    """SQL 시드 텍스트 생성.

    include_delete_stale=True 이면 현재 events 에 없는 stale row 를 먼저 삭제한다.
    split 파일에서는 부분 events 만 들어오므로, full set 을 별도 인자(full_keep_events)
    로 받아 그것으로 keep_pairs 를 만든다. 그렇게 하지 않으면 part_02 가 part_01 의
    upsert 결과를 지워버리는 사고가 난다.
    """
    lines: list[str] = []
    generated_at = datetime.now(timezone.utc).isoformat()
    lines.append("-- Generated by tools/seed/build_200_stories_seed_sql.py")
    lines.append(f"-- Generated at UTC: {generated_at}")
    lines.append("-- Target table: events")
    lines.append(
        "-- (character_codes / bible_refs / story_scenes / scene_captions / scene_characters live"
    )
    lines.append(
        "--  on the events row itself; person_eras and events_ordered are views.)"
    )
    lines.append("begin;")
    lines.append("")
    # 시드 INSERT 가 notify_on_new_event 트리거를 깨워 broadcast_notifications 에
    # 215개 알림을 만드는 부작용 방지. 시드 적용 동안만 비활성화 후 복구.
    # set_config 의 두번째 인자 true → tx-local. 운영 트래픽엔 영향 없음.
    lines.append(
        "-- 시드 INSERT 가 알림 트리거(broadcast)를 깨우는 것 방지. tx 종료 후 자동 복구."
    )
    lines.append("alter table events disable trigger trg_notify_on_new_event;")
    lines.append("")
    if include_delete_stale:
        keep_basis = full_keep_events if full_keep_events is not None else events
        lines.extend(render_delete_stale_events_sql(keep_basis))
    lines.append("-- Upsert events from 200 stories")
    lines.extend(render_events_sql(events, events_chunk_size))
    lines.append("")
    lines.append("alter table events enable trigger trg_notify_on_new_event;")
    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


def write_report(report_path: Path, events: list[NormalizedEvent]) -> None:
    by_era: dict[str, int] = {}
    for event in events:
        by_era[event.era_code] = by_era.get(event.era_code, 0) + 1
    payload = {
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "event_count": len(events),
        "events_by_era": by_era,
        "notes": [
            "story_index is taken straight from JSON (admin UI / manual edit owns it)",
            "character codes expanded for disciples/apostles/brothers, then filtered by avatar prompt whitelist",
            "bible_refs/story_scenes/scene_characters are stored as jsonb on events",
            "background_context is a short user-facing background knowledge blurb",
            "scene_captions are short user-facing captions aligned with story_scenes",
            "character_codes is text[] on events; event_persons table is gone",
            "unit_code/unit_title/unit_order group events before timeline reveal",
            "events_ordered (rank_in_era, global_rank) is a view; sorted at read time",
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
                "era_code": event.era_code,
                "story_index": event.story_index,
                "title": event.title,
                "summary": event.summary,
                "background_context": event.background_context,
                "start_year": event.start_year,
                "end_year": event.end_year,
                "time_precision": event.time_precision,
                "unit_code": event.unit_code,
                "unit_title": event.unit_title,
                "unit_order": event.unit_order,
                "landmark_code": event.landmark_code,
                "character_codes": event.characters,
                "bible_refs": serialize_bible_refs(event.refs),
                "story_scenes": event.story_scenes,
                "scene_captions": event.scene_captions,
                "scene_characters": event.scene_characters,
            }
        )
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def load_landmark_mapping(path: Path) -> dict[tuple[str, int], str]:
    """매핑 JSON → (era_code, story_index) → landmark_code (region/anchor/minor)."""
    if not path.exists():
        raise FileNotFoundError(
            f"landmark mapping not found at {path}. "
            "tools/seed/map_events_to_landmarks_v2.py 를 먼저 실행하세요."
        )
    data = json.loads(path.read_text(encoding="utf-8"))
    out: dict[tuple[str, int], str] = {}
    for row in data.get("rows", []):
        era = str(row.get("era") or "").strip()
        idx = row.get("story_index")
        target = row.get("landmark_code") or row.get("region_code")
        if not era or not isinstance(idx, int) or not target:
            continue
        out[(era, idx)] = target
    return out


def main() -> int:
    args = parse_args()
    input_dir = Path(args.input_dir)
    character_meta_json = Path(args.character_meta_json)
    output_dir = Path(args.output_dir)
    landmark_mapping_path = Path(args.landmark_mapping)

    rows = parse_story_rows(input_dir)
    allowed_person_codes = load_person_meta_codes(character_meta_json)
    landmark_mapping = load_landmark_mapping(landmark_mapping_path)
    events, character_codes = normalize_events(
        rows, allowed_person_codes, landmark_mapping
    )

    output_dir.mkdir(parents=True, exist_ok=True)
    seed_sql_text = build_seed_sql(
        events,
        events_chunk_size=max(1, args.events_chunk_size),
    )

    sql_path = output_dir / "200_stories_seed.sql"
    report_path = output_dir / "200_stories_report.json"
    normalized_path = output_dir / "200_stories_normalized.json"

    sql_path.write_text(seed_sql_text, encoding="utf-8")
    write_report(report_path, events)
    write_normalized_json(normalized_path, events)

    part_paths: list[Path] = []
    part_chunks = split_event_chunks(
        events,
        split_parts=max(0, int(args.split_parts)),
        events_per_part=max(0, int(args.events_per_part)),
    )
    if len(part_chunks) > 1:
        for idx, part_events in enumerate(part_chunks, start=1):
            part_sql_text = build_seed_sql(
                part_events,
                events_chunk_size=max(1, args.events_chunk_size),
                # split 파일은 INSERT 만 — 첫 part 에서만 stale 삭제하고,
                # 나머지는 INSERT 만 추가. 첫 part 에는 full event set 을
                # keep 기준으로 넘긴다.
                include_delete_stale=(idx == 1),
                full_keep_events=events if idx == 1 else None,
            )
            part_path = output_dir / f"200_stories_seed_part_{idx:02d}.sql"
            part_path.write_text(part_sql_text, encoding="utf-8")
            part_paths.append(part_path)

    print(f"input dir            : {input_dir}")
    print(f"character meta json     : {character_meta_json}")
    print(f"events parsed        : {len(events)}")
    print(f"unique character codes  : {len(character_codes)}")
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
