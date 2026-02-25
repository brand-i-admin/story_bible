#!/usr/bin/env python3
"""Build tools/avatar_prompts.json from assets/200_stories JSON files.

Rules:
- Expand group codes: disciples/apostles/brothers -> individual person codes.
- Remove non-individual codes (groups/placeholders like mysterious_man, babel_people).
- Keep only person codes with mention_count >= min_mentions.
- Reuse existing prompt metadata when available.
- If no template exists, use built-in default style/palette config.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

EVENT_NO_RE = re.compile(r"^(\d{3})\s+.*$")

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

DEFAULT_STYLE_SOURCE: dict[str, Any] = {
    "common_style": (
        "cute chibi character, big head small body (2.5 heads tall), "
        "low-poly faceted polygon style, origami papercraft look, "
        "clean vector-like shading, pastel colors, soft gradients, "
        "thick simple outline, minimal details, friendly expression, "
        "front 3/4 view, full body, centered, plain white background, "
        "high resolution, consistent proportions, no text, no watermark, "
        "same character design system as a consistent set, same face proportions, "
        "same polygon count, same shading style, same outline thickness"
    ),
    "negative_prompt": (
        "realistic, photoreal, anime, manga, 3D render, clay, pixel art, "
        "gritty, dark, horror, complex background, text, logo, watermark"
    ),
    "palettes": {
        "primeval": "soft beige + olive + sky blue accents",
        "patriarch": "warm sand + cream + muted teal accents",
        "exodus_wilderness": "teal + desert tan + bronze accents",
        "judges": "olive green + clay brown + muted gold accents",
        "monarchy": "royal purple + navy + gold accents (still pastel)",
        "prophets_exile": "muted indigo + gray + parchment cream accents",
        "post_exile_return": "stone gray + sage green + parchment cream accents",
        "gospels": "cream + sky blue + soft rose accents",
        "early_church": "teal + sea blue + warm brown accents",
    },
    "generation_defaults": {
        "sampleCount": 1,
        "aspectRatio": "1:1",
        "enhancePrompt": False,
        "personGeneration": "allow_adult",
        "outputMimeType": "image/png",
    },
}

# Known group/non-individual/noise codes in story JSON.
NON_INDIVIDUAL_CODES = {
    "abraham_servant",
    "angels",
    "apostles",
    "babel_people",
    "beasts",
    "believers",
    "bleeding_woman",
    "brothers",
    "builders",
    "chief_baker",
    "chief_cupbearer",
    "chief_priests",
    "church_of_antioch",
    "crowd",
    "danites",
    "disciples",
    "dragon",
    "egyptian_taskmaster",
    "ephesus_elders",
    "ethiopian_eunuch",
    "father",
    "gibeonites",
    "good_samaritan",
    "heavenly_beings",
    "heavenly_voice",
    "islanders",
    "israelites",
    "jerusalem_crowd",
    "jerusalem_people",
    "judge",
    "lamb",
    "lame_man",
    "lawyer",
    "leaders",
    "magi",
    "moneychangers",
    "moses_mother",
    "mysterious_man",
    "older_brother",
    "people",
    "pharaoh_daughter",
    "potiphar_wife",
    "prodigal_son",
    "prophets_of_baal",
    "queen_of_sheba",
    "remnant_people",
    "returnees",
    "saints",
    "samaritans",
    "shepherds",
    "ship_crew",
    "tempter",
}

ERA_CODE_TO_STYLE = {
    "era_primeval": "primeval",
    "era_patriarch": "patriarch",
    "era_exodus": "exodus_wilderness",
    "era_judges": "judges",
    "era_monarchy": "monarchy",
    "era_exile_return": "post_exile_return",
    "era_nt_public_ministry": "gospels",
    "era_nt_apostolic": "early_church",
    "era_nt_post_apostolic": "early_church",
    "era_nt_consummation": "early_church",
}

KO_NAME_OVERRIDES = {
    "jesus": "예수님",
    "moses": "모세",
    "paul": "바울",
    "john": "요한",
    "peter": "베드로",
    "joseph": "요셉",
    "jacob": "야곱",
    "abraham": "아브라함",
    "philip": "빌립",
    "andrew": "안드레",
    "david": "다윗",
    "matthew": "마태",
    "thomas": "도마",
    "saul": "사울",
    "joshua": "여호수아",
    "judas": "유다",
    "sarah": "사라",
    "aaron": "아론",
    "samuel": "사무엘",
    "elijah": "엘리야",
    "esther": "에스더",
    "mary": "마리아",
    "nehemiah": "느헤미야",
    "isaac": "이삭",
    "mordecai": "모르드개",
    "solomon": "솔로몬",
    "adam": "아담",
    "daniel": "다니엘",
    "eve": "하와",
    "james": "야고보",
    "lot": "롯",
    "noah": "노아",
    "rachel": "라헬",
    "ruth": "룻",
    "abimelech": "아비멜렉",
    "ahab": "아합",
    "boaz": "보아스",
    "elisha": "엘리사",
    "ezra": "에스라",
    "gideon": "기드온",
    "hagar": "하갈",
    "haman": "하만",
    "isaiah": "이사야",
    "jeremiah": "예레미야",
    "leah": "레아",
    "naomi": "나오미",
    "rebekah": "리브가",
    "dan": "단",
    "ananias": "아나니아",
    "asher": "아셀",
    "barnabas": "바나바",
    "bartholomew": "바돌로매",
    "benjamin": "베냐민",
    "elizabeth": "엘리사벳",
    "esau": "에서",
    "ezekiel": "에스겔",
    "gad": "갓",
    "gabriel": "가브리엘",
    "god": "하나님",
    "hezekiah": "히스기야",
    "ishmael": "이스마엘",
    "issachar": "잇사갈",
    "james_alphaeus": "야고보(알패오의 아들)",
    "james_zebedee": "야고보(세베대의 아들)",
    "judah": "유다",
    "laban": "라반",
    "levi": "레위",
    "matthias": "맛디아",
    "naphtali": "납달리",
    "nathan": "나단",
    "pharaoh": "바로",
    "reuben": "르우벤",
    "silas": "실라",
    "simeon": "시므온",
    "simon_zealot": "시몬(셀롯)",
    "thaddaeus": "다대오(유다)",
    "timothy": "디모데",
    "zebulun": "스불론",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build avatar prompt JSON from assets/200_stories data."
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing 200 story JSON files.",
    )
    parser.add_argument(
        "--base-prompt-json",
        default="tools/avatar_prompts_51.json",
        help="Deprecated. Ignored (kept only for CLI backward compatibility).",
    )
    parser.add_argument(
        "--output",
        default="tools/avatar_prompts.json",
        help="Output avatar prompt JSON path.",
    )
    parser.add_argument(
        "--min-mentions",
        type=int,
        default=2,
        help="Minimum mention count to include.",
    )
    return parser.parse_args()


def parse_event_number(raw_title: str) -> int:
    match = EVENT_NO_RE.match(raw_title.strip())
    if match is None:
        raise ValueError(f"Title does not start with 3-digit index: {raw_title!r}")
    return int(match.group(1))


def load_story_rows(stories_dir: Path) -> list[dict[str, Any]]:
    if not stories_dir.exists():
        raise FileNotFoundError(f"Stories dir not found: {stories_dir}")
    rows: list[dict[str, Any]] = []
    for path in sorted(stories_dir.glob("*.json"), key=lambda p: p.name):
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise ValueError(f"JSON root must be a list: {path}")
        for item in data:
            if not isinstance(item, dict):
                raise ValueError(f"Story row must be object in {path}: {item!r}")
            rows.append(item)
    rows.sort(key=lambda row: parse_event_number(str(row.get("title", ""))))
    return rows


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


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


def is_individual_code(code: str) -> bool:
    if code in NON_INDIVIDUAL_CODES:
        return False
    if not code:
        return False
    return True


def normalize_style_era(era: str) -> str:
    raw = era.strip()
    if raw in {
        "primeval",
        "patriarch",
        "exodus_wilderness",
        "judges",
        "monarchy",
        "prophets_exile",
        "post_exile_return",
        "gospels",
        "early_church",
    }:
        return raw
    return ERA_CODE_TO_STYLE.get(raw, "patriarch")


def prettify_name_en(code: str) -> str:
    return " ".join(part.capitalize() for part in code.split("_") if part)


def has_hangul(text: str) -> bool:
    return any("가" <= ch <= "힣" for ch in text)


def build_generic_prompt(name_en: str, palette_text: str) -> str:
    return (
        f"COMMON_STYLE, palette: {palette_text}, {name_en}, "
        "adult biblical character (age 25+), cute friendly expression, "
        "simple iconic ancient outfit, clean silhouette, cohesive chibi low-poly style"
    )


def build_god_prompt(palette_text: str) -> str:
    return (
        f"palette: {palette_text}, unseen radiant divine presence, "
        "abstract luminous holy form, flowing gentle light and soft glow, "
        "no human figure, no face, no eyes, no mouth, no body, "
        "no sun disk, no star icon, sacred non-anthropomorphic presence"
    )


def load_prompt_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def has_style_keys(data: dict[str, Any]) -> bool:
    return all(
        key in data for key in ["common_style", "negative_prompt", "palettes", "generation_defaults"]
    )


def build_template_map(*json_paths: Path) -> dict[str, dict[str, Any]]:
    templates: dict[str, dict[str, Any]] = {}
    for path in json_paths:
        if not path.exists():
            continue
        data = load_prompt_json(path)
        for character in data.get("characters", []):
            if not isinstance(character, dict):
                continue
            code = str(character.get("code", "")).strip()
            if not code:
                continue
            if code in templates:
                continue
            templates[code] = character
    return templates


def build_avatar_prompts(
    rows: list[dict[str, Any]],
    style_source: dict[str, Any],
    template_map: dict[str, dict[str, Any]],
    min_mentions: int,
) -> dict[str, Any]:
    mention_counts: Counter[str] = Counter()
    era_votes: dict[str, Counter[str]] = defaultdict(Counter)

    for row in rows:
        number = parse_event_number(str(row.get("title", "")))
        era_style = normalize_style_era(str(row.get("era", "")))
        raw_persons = [str(code).strip() for code in row.get("persons", []) if str(code).strip()]
        persons = expand_person_codes(number, raw_persons)
        for code in persons:
            if not is_individual_code(code):
                continue
            mention_counts[code] += 1
            era_votes[code][era_style] += 1

    selected_codes = sorted(
        [code for code, count in mention_counts.items() if count >= min_mentions],
        key=lambda code: (-mention_counts[code], code),
    )

    palettes = style_source["palettes"]
    default_style = "patriarch"

    characters: list[dict[str, Any]] = []
    for idx, code in enumerate(selected_codes, start=1):
        template = template_map.get(code, {})

        voted_style = default_style
        if era_votes.get(code):
            voted_style = sorted(
                era_votes[code].items(), key=lambda item: (-item[1], item[0])
            )[0][0]

        era_style = normalize_style_era(str(template.get("era", voted_style)))
        if era_style not in palettes:
            era_style = voted_style if voted_style in palettes else default_style

        name_en = str(template.get("name_en", "")).strip() or prettify_name_en(code)
        template_name_ko = str(template.get("name_ko", "")).strip()
        if has_hangul(template_name_ko):
            name_ko = template_name_ko
        elif code in KO_NAME_OVERRIDES:
            name_ko = KO_NAME_OVERRIDES[code]
        elif template_name_ko:
            name_ko = template_name_ko
        else:
            name_ko = name_en

        palette_text = str(palettes.get(era_style, palettes[default_style]))
        prompt = str(template.get("prompt", "")).strip()
        use_common_style = bool(template.get("use_common_style", True))
        disable_adult_guardrail = bool(template.get("disable_adult_guardrail", False))
        person_generation = str(template.get("person_generation", "")).strip()

        if code == "god":
            prompt = build_god_prompt(palette_text=palette_text)
            use_common_style = False
            disable_adult_guardrail = True
            person_generation = "dont_allow"

        if not prompt:
            prompt = build_generic_prompt(name_en=name_en, palette_text=palette_text)

        character = {
            "index": idx,
            "code": code,
            "name_ko": name_ko,
            "name_en": name_en,
            "era": era_style,
            "prompt": prompt,
            "mention_count": mention_counts[code],
        }
        if not use_common_style:
            character["use_common_style"] = False
        if disable_adult_guardrail:
            character["disable_adult_guardrail"] = True
        if person_generation:
            character["person_generation"] = person_generation
        characters.append(character)

    output = {
        "meta": {
            "title": "Bible avatar prompts (2+ mentions, individual-only from 200 stories)",
            "version": "1.0",
            "count": len(characters),
            "note": (
                "Generated from assets/200_stories with "
                "disciples/apostles/brothers expanded to individuals, then filtered "
                f"to mention_count >= {min_mentions}."
            ),
        },
        "common_style": style_source["common_style"],
        "negative_prompt": style_source["negative_prompt"],
        "palettes": style_source["palettes"],
        "generation_defaults": style_source["generation_defaults"],
        "characters": characters,
    }
    return output


def main() -> int:
    args = parse_args()
    stories_dir = Path(args.stories_dir)
    output_path = Path(args.output)

    template_paths: list[Path] = []
    if output_path.exists():
        template_paths.append(output_path)

    style_source: dict[str, Any] = DEFAULT_STYLE_SOURCE
    style_source_path = "<built-in defaults>"
    for path in template_paths:
        data = load_prompt_json(path)
        if has_style_keys(data):
            style_source = data
            style_source_path = str(path)
            break

    rows = load_story_rows(stories_dir)
    template_map = build_template_map(*template_paths)

    output = build_avatar_prompts(
        rows=rows,
        style_source=style_source,
        template_map=template_map,
        min_mentions=max(1, int(args.min_mentions)),
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(output, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"stories dir   : {stories_dir}")
    print(f"template base : {style_source_path}")
    print(f"output        : {output_path}")
    print(f"count         : {output['meta']['count']}")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
