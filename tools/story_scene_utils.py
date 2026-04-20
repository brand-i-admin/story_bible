#!/usr/bin/env python3
"""Shared helpers for Bible story scene text cleanup and person matching."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any


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

GROUP_EXPANSIONS: dict[str, list[str]] = {
    "disciples": DISCIPLES_WITH_JUDAS,
    "apostles": APOSTLES_AFTER_MATTHIAS,
    "brothers": BROTHERS_ALL,
}

GROUP_KO_NAMES: dict[str, str] = {
    "disciples": "제자들",
    "apostles": "사도들",
    "brothers": "형제들",
}

GROUP_ALIASES: dict[str, list[str]] = {
    "disciples": ["제자들", "제자", "열두 제자", "열두제자"],
    "apostles": ["사도들", "사도", "열두 사도", "열두사도"],
    "brothers": ["형제들", "형제", "열두 형제", "열두형제"],
}

PERSON_EXTRA_ALIASES: dict[str, list[str]] = {
    "jesus": ["예수", "주님"],
    "god": ["여호와"],
    "gabriel": ["천사 가브리엘", "가브리엘 천사"],
    "john_the_baptist": ["세례 요한", "세례요한", "요한"],
}

SCENE_PREFIX_REGEX = re.compile(r"^\s*장면\s*\d+\s*[:：]\s*")
MULTI_SPACE_REGEX = re.compile(r"\s+")
LEFTOVER_QUOTE_REGEX = re.compile(r"""["“”'‘’]""")
NARRATION_REGEX = re.compile(r"\(?\s*(?:내레이션|내래이션|나레이션)\s*\)?")
PAREN_CONTENT_REGEX = re.compile(r"\(([^()]*)\)")
MULTI_PUNCT_REGEX = re.compile(r"\s*([,.;:])(?:\s*[,.;:])+\s*")
PUNCT_SPACE_REGEX = re.compile(r"\s*([,.;:])\s*")
NAME_PAREN_REGEX = re.compile(r"\s*\(([^)]*)\)")
SQL_PERSON_TUPLE_REGEX = re.compile(r"\(\s*'((?:[^']|'')*)'\s*,\s*'((?:[^']|'')*)'")
VOICE_ONLY_REGEX = re.compile(r"^[가-힣A-Za-z0-9_·(),\s/:：-]+$")
NON_NAME_CHARS_REGEX = re.compile(r"[,:：./·()\-\s]+")
ELLIPSIS_REGEX = re.compile(r"[.…]+")
DIALOGUE_LABEL_REGEX = re.compile(
    r"(?P<speaker>[가-힣A-Za-z0-9_·()\s]{1,30})\s*[:：]\s*(?P<speech>[^.?!…]+(?:[.?!…]|$))"
)
SPEECH_CONTENT_HINT_REGEX = re.compile(
    r"(내가|내|우리|너|너희|당신|주여|아버지|무엇을|누구라|주소서|하라|말라|느냐|노라|겠나이다|도다|하리라|그리스도시요|아들이요|멸하지 않겠다|전쟁입니다|가라|오라|가자|하자|보라)"
)
TRAILING_SPEECH_REGEX = re.compile(
    r"(?P<head>.*?\b(?:말한다|외친다|명령한다|대답한다|고백한다|전한다|선언한다|묻는다|부른다|부르짖는다|짧게 명령한다|변명한다|비유를 말한다))\.\s*(?P<trail>.+)$"
)
HUMAN_ACTION_HINT_REGEX = re.compile(
    r"(기도|절하|손을|팔을|고개|서 있|앉아|걷|달리|도망|쌓|드리|바치|만나|안고|업고|포옹|붙잡|들고|건네|씻|치유|축복|전하|말하|외치|노래|명령|대답|웃|울|씨름|머리|얼굴|옷|눈빛)"
)
ENVIRONMENT_ONLY_HINT_REGEX = re.compile(
    r"(비구름|햇빛|무지개|하늘|땅|광야|산지|산|바다|강|성전|도성|성벽|들판|광채|연기|별|배경|길|불기둥|구름기둥|지도|성막)"
)
META_SCENE_REGEX = re.compile(
    r"(?:누가복음\s*상징|상징적\s*(?:연출|전개|처리|포즈)?|상징(?:으로|로|과 함께| 아래로)?|몽타주|연출)"
)
SPEECH_VERB_REGEX = re.compile(
    r"(말한다|외친다|묻는다|대답한다|전한다|선언한다|명령한다|고백한다|노래한다|답한다|부른다|부르짖는다|짧게 명령한다|비유를 말한다)"
)
GENERIC_SCENE_CENTER_REGEX = re.compile(
    r"^(?P<subject>.+?)\s+장면\s*(?:앞쪽|중심)?(?:에\s*있고|이\s*드러난다|에\s*서 있는 모습)?\s*,?\s*(?P<rest>.*)$"
)


def sql_unescape(value: str) -> str:
    return value.replace("''", "'")


def parse_person_name_map_from_seed_sql(path: Path) -> dict[str, str]:
    if not path.exists():
        raise FileNotFoundError(f"persons seed SQL not found: {path}")

    text = path.read_text(encoding="utf-8")
    start = text.find("with seed_persons")
    if start == -1:
        raise ValueError(
            "Could not find 'with seed_persons' block in persons seed SQL."
        )
    end = text.find("insert into persons", start)
    block = text[start:end] if end != -1 else text[start:]

    mapping: dict[str, str] = {}
    for code, name in SQL_PERSON_TUPLE_REGEX.findall(block):
        code_key = sql_unescape(code).strip().lower()
        name_value = sql_unescape(name).strip()
        if code_key and name_value:
            mapping[code_key] = name_value

    mapping.update(GROUP_KO_NAMES)
    return mapping


def parse_event_person_codes(event: dict[str, Any]) -> list[str]:
    persons_data = event.get("persons")
    codes: list[str] = []
    if isinstance(persons_data, list):
        for item in persons_data:
            if isinstance(item, str):
                code = item.strip().lower()
            elif isinstance(item, dict):
                code = str(item.get("code") or "").strip().lower()
            else:
                code = ""
            if code:
                codes.append(code)
    elif isinstance(event.get("event_persons"), list):
        for item in event["event_persons"]:
            if not isinstance(item, dict):
                continue
            person = item.get("persons")
            if not isinstance(person, dict):
                continue
            code = str(person.get("code") or "").strip().lower()
            if code:
                codes.append(code)
    return dedupe_preserve_order(codes)


def dedupe_preserve_order(values: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        key = value.strip().lower()
        if not key or key in seen:
            continue
        seen.add(key)
        result.append(key)
    return result


def expand_person_codes(codes: list[str]) -> list[str]:
    expanded: list[str] = []
    for code in codes:
        members = GROUP_EXPANSIONS.get(code, [code])
        expanded.extend(members)
    return dedupe_preserve_order(expanded)


def normalize_scene_text(raw: str) -> str:
    return MULTI_SPACE_REGEX.sub(
        " ", SCENE_PREFIX_REGEX.sub("", str(raw).strip())
    ).strip()


def aliases_for_person(code: str, code_to_name: dict[str, str]) -> list[str]:
    aliases: list[str] = [code]
    name = code_to_name.get(code, "").strip()
    if name:
        aliases.append(name)
        aliases.append(name.replace(" ", ""))
        if name.endswith("님") and len(name) > 1:
            aliases.append(name[:-1])
            aliases.append(name[:-1].replace(" ", ""))
        no_paren = NAME_PAREN_REGEX.sub("", name).strip()
        if no_paren and no_paren != name:
            aliases.append(no_paren)
            aliases.append(no_paren.replace(" ", ""))
            aliases.append(NAME_PAREN_REGEX.sub(r" \1", name).strip())
    aliases.extend(GROUP_ALIASES.get(code, []))
    aliases.extend(PERSON_EXTRA_ALIASES.get(code, []))
    return [alias for alias in dedupe_preserve_order(aliases) if alias]


def detect_scene_person_codes(
    raw_text: str,
    event_person_codes: list[str],
    code_to_name: dict[str, str],
) -> list[str]:
    text = str(raw_text)
    lowered = text.lower()
    compact = text.replace(" ", "")
    matched: list[str] = []

    for code in event_person_codes:
        found = False
        for alias in aliases_for_person(code, code_to_name):
            alias = alias.strip()
            if not alias:
                continue
            if alias.isascii():
                found = alias.lower() in lowered
            else:
                alias_compact = alias.replace(" ", "")
                found = alias in text or alias_compact in compact
            if found:
                matched.append(code)
                break

    if matched:
        return dedupe_preserve_order(matched)

    non_group_codes = [
        code for code in event_person_codes if code not in GROUP_EXPANSIONS
    ]
    if len(non_group_codes) == 1:
        has_human_action = bool(HUMAN_ACTION_HINT_REGEX.search(text))
        looks_environment_only = bool(ENVIRONMENT_ONLY_HINT_REGEX.search(text))
        if has_human_action and not looks_environment_only:
            return non_group_codes

    return []


def choose_josa(word: str, consonant_form: str, vowel_form: str) -> str:
    cleaned = word.strip()
    if not cleaned:
        return vowel_form
    last = cleaned[-1]
    code = ord(last)
    if 0xAC00 <= code <= 0xD7A3:
        jong = (code - 0xAC00) % 28
        return consonant_form if jong else vowel_form
    if last.lower() in {"l", "m", "n", "r"}:
        return consonant_form
    return vowel_form


def join_names_for_subject(codes: list[str], code_to_name: dict[str, str]) -> str:
    names = [code_to_name.get(code, code) for code in codes]
    if not names:
        return ""
    if len(names) == 1:
        name = names[0]
        if codes[0] == "god":
            return f"{name}의 빛이"
        return f"{name}{choose_josa(name, '이', '가')}"
    if len(names) == 2:
        first = names[0]
        second = names[1]
        return f"{first}{choose_josa(first, '과', '와')} {second}{choose_josa(second, '이', '가')}"
    shown = ", ".join(names[:3])
    return f"{shown}가"


def build_fallback_scene_text(codes: list[str], code_to_name: dict[str, str]) -> str:
    if not codes:
        return "배경과 분위기만 보이는 장면"
    if codes == ["god"]:
        return "하나님의 빛이 하늘에서 임한다"
    subject = join_names_for_subject(codes, code_to_name)
    if len(codes) == 1:
        return f"{subject} 앞쪽에 서서 표정과 몸짓이 또렷하게 보인다"
    return f"{subject} 함께 서서 서로를 바라본다"


def _remove_quoted_content(text: str) -> str:
    result = text
    quote_pair_patterns = [
        re.compile(r'"[^"]*"'),
        re.compile(r"“[^”]*”"),
        re.compile(r"‘[^’]*’"),
        re.compile(r"'[^']*'"),
    ]
    changed = True
    while changed:
        changed = False
        for pattern in quote_pair_patterns:
            next_result, count = pattern.subn("", result)
            result = next_result
            changed = changed or count > 0
    return LEFTOVER_QUOTE_REGEX.sub("", result)


def _cleanup_scene_text(text: str) -> str:
    cleaned = normalize_scene_text(text)
    cleaned = NARRATION_REGEX.sub("", cleaned)
    cleaned = _remove_quoted_content(cleaned)
    cleaned = PAREN_CONTENT_REGEX.sub(
        lambda match: f", {match.group(1).strip()}" if match.group(1).strip() else "",
        cleaned,
    )
    cleaned = cleaned.replace("’", "").replace("‘", "")
    cleaned = cleaned.replace("“", "").replace("”", "")
    cleaned = cleaned.replace("—", ", ").replace("–", ", ").replace("→", ", ")
    cleaned = ELLIPSIS_REGEX.sub(". ", cleaned)
    cleaned = MULTI_PUNCT_REGEX.sub(r"\1 ", cleaned)
    cleaned = PUNCT_SPACE_REGEX.sub(r"\1 ", cleaned)
    cleaned = MULTI_SPACE_REGEX.sub(" ", cleaned)
    cleaned = cleaned.strip(" ,.;:·")
    return cleaned


def _strip_meta_words(text: str) -> str:
    cleaned = META_SCENE_REGEX.sub("", text)
    cleaned = cleaned.replace("장면으로 끝난다", "마무리된다")
    cleaned = cleaned.replace("예고가 이어진다", "놀람이 번진다")
    cleaned = cleaned.replace(
        "큰 기쁨의 좋은 소식을 전한다", "천사가 나타나고 목자들이 놀라 눈을 들어 올린다"
    )
    cleaned = cleaned.replace("그가 누구이기에", "두려움과 놀람이 엇갈린다")
    cleaned = cleaned.replace("하나님이 대답하시리이다", "")
    cleaned = MULTI_PUNCT_REGEX.sub(r"\1 ", cleaned)
    cleaned = MULTI_SPACE_REGEX.sub(" ", cleaned)
    return cleaned.strip(" ,.;:·")


def _rewrite_dialogue_labels(
    text: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    matches = list(DIALOGUE_LABEL_REGEX.finditer(text))
    if not matches:
        return text

    if len(matches) >= 2:
        return build_fallback_scene_text(codes, code_to_name)

    match = matches[0]
    speaker_fragment = match.group("speaker").strip()
    speaker_codes = (
        detect_scene_person_codes(speaker_fragment, codes, code_to_name) or codes
    )
    subject = join_names_for_subject(speaker_codes, code_to_name)
    if not subject:
        subject = speaker_fragment

    prefix = text[: match.start()].strip(" ,.;")
    suffix = text[match.end() :].strip(" ,.;")

    if prefix and suffix:
        return f"{prefix}, {subject} 앞쪽에 서 있고, {suffix}"
    if prefix:
        return f"{prefix}, {subject} 실루엣이 또렷하다"
    if suffix:
        return f"{subject} 앞쪽에 서 있고, {suffix}"
    return build_fallback_scene_text(speaker_codes, code_to_name)


def _strip_trailing_speech_content(
    text: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    match = TRAILING_SPEECH_REGEX.match(text)
    if not match:
        return text

    trail = match.group("trail").strip()
    if not trail:
        return match.group("head").strip()
    if detect_scene_person_codes(trail, codes, code_to_name):
        return text
    if HUMAN_ACTION_HINT_REGEX.search(trail) or ENVIRONMENT_ONLY_HINT_REGEX.search(
        trail
    ):
        return text
    if SPEECH_CONTENT_HINT_REGEX.search(trail):
        return match.group("head").strip()
    if len(trail) <= 24:
        return match.group("head").strip()
    return text


def _rewrite_center_scene_phrase(
    text: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    match = GENERIC_SCENE_CENTER_REGEX.match(text.strip())
    if not match:
        return text

    subject = match.group("subject").strip()
    rest = match.group("rest").strip(" ,.;:")
    if subject.startswith("하나님") or subject.startswith("하나님의 빛"):
        if rest:
            return f"하나님의 빛이 임하고, {rest}"
        return "하나님의 빛이 임한다"
    if not codes:
        if subject == "음성":
            if rest:
                return f"하늘에서 빛이 비치고, {rest}"
            return "하늘에서 빛이 비친다"
        if rest:
            return f"{subject}, {rest}".strip(" ,.;:")
        return subject
    if rest:
        return f"{subject} 앞쪽에 서 있고, {rest}"
    return f"{subject} 앞쪽에 서 있다"


def _cleanup_visual_stub(text: str, codes: list[str]) -> str:
    cleaned = text.strip(" ,.;:")
    if not cleaned:
        return cleaned
    if not codes and cleaned.startswith("음성 앞쪽에 서 있고, "):
        return f"하늘에서 빛이 비치고, {cleaned.removeprefix('음성 앞쪽에 서 있고, ').strip()}"
    if not codes and cleaned.endswith("앞쪽에 서 있다"):
        cleaned = cleaned.removesuffix(" 앞쪽에 서 있다").strip(" ,.;:")
    cleaned = cleaned.replace("그물 가득한", "그물이 가득하다")
    cleaned = MULTI_SPACE_REGEX.sub(" ", cleaned)
    return cleaned.strip(" ,.;:")


def _visual_fragment_for_speech(
    fragment: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    stripped = fragment.strip(" ,.;:")
    if not stripped:
        return ""

    if not SPEECH_VERB_REGEX.search(stripped):
        if SPEECH_CONTENT_HINT_REGEX.search(stripped) and not (
            HUMAN_ACTION_HINT_REGEX.search(stripped)
            or ENVIRONMENT_ONLY_HINT_REGEX.search(stripped)
        ):
            return ""
        return stripped

    speaker_codes = detect_scene_person_codes(stripped, codes, code_to_name) or codes
    subject = join_names_for_subject(speaker_codes, code_to_name)
    if not subject:
        return build_fallback_scene_text(speaker_codes, code_to_name)

    if "묻는다" in stripped:
        return f"{subject} 상대를 바라보며 기다린다"
    if "외친다" in stripped or "부르짖는다" in stripped:
        return f"{subject} 두 손을 들어 다급하게 몸짓한다"
    if "명령한다" in stripped:
        return f"{subject} 급히 방향을 가리킨다"
    if "대답한다" in stripped or "답한다" in stripped:
        return f"{subject} 조용히 고개를 끄덕인다"
    if "노래한다" in stripped:
        return f"{subject} 얼굴을 들어 기쁨을 드러낸다"
    if "고백한다" in stripped:
        return f"{subject} 무거운 표정으로 고개를 숙인다"
    if "선언한다" in stripped:
        return f"{subject} 사람들 앞에 굳게 선다"
    if "전한다" in stripped:
        return f"{subject} 엄숙한 표정으로 손짓한다"
    return f"{subject} 결연한 표정으로 선다"


def _rewrite_speech_fragments(
    text: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    fragments = [
        fragment.strip()
        for fragment in re.split(r"(?<=[.!?])\s+", text)
        if fragment.strip()
    ]
    if len(fragments) <= 1:
        rewritten = _visual_fragment_for_speech(text, codes, code_to_name)
        return rewritten or ""

    rewritten_fragments: list[str] = []
    for fragment in fragments:
        rewritten = _visual_fragment_for_speech(fragment, codes, code_to_name)
        if rewritten:
            rewritten_fragments.append(rewritten)
    return ", ".join(rewritten_fragments).strip(" ,.;:")


def _dedupe_subject_prefixes(
    text: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    cleaned = text.strip()
    center_match = GENERIC_SCENE_CENTER_REGEX.match(cleaned)
    if center_match:
        subject = center_match.group("subject").strip()
        rest = center_match.group("rest").strip()
        if subject and subject in rest:
            return rest

    for code in codes:
        aliases = [
            alias
            for alias in aliases_for_person(code, code_to_name)
            if alias and not alias.isascii()
        ]
        alias_set = set(aliases)
        for alias in aliases:
            subject_forms = [
                f"{alias}이 ",
                f"{alias}가 ",
                f"{alias}의 빛이 ",
            ]
            for subject_form in subject_forms:
                if cleaned.startswith(subject_form):
                    rest = cleaned[len(subject_form) :].strip()
                    if any(other_alias in rest for other_alias in alias_set):
                        return rest
    return cleaned


def _is_name_only_text(
    text: str, codes: list[str], code_to_name: dict[str, str]
) -> bool:
    if not text:
        return True

    reduced = text
    for code in codes:
        for alias in aliases_for_person(code, code_to_name):
            if alias and not alias.isascii():
                reduced = reduced.replace(alias, " ")
    reduced = NON_NAME_CHARS_REGEX.sub("", reduced)
    return len(reduced) <= 2 and bool(VOICE_ONLY_REGEX.match(text))


def ensure_scene_mentions_people(
    text: str,
    codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    if not text or not codes:
        return text

    for code in codes:
        for alias in aliases_for_person(code, code_to_name):
            if alias and not alias.isascii() and alias in text:
                return text

    subject = join_names_for_subject(codes, code_to_name)
    if not subject:
        return text
    return f"{subject} {text}".strip()


def sanitize_scene_text_for_visual(
    raw_text: str,
    *,
    scene_person_codes: list[str],
    code_to_name: dict[str, str],
) -> str:
    cleaned = _cleanup_scene_text(raw_text)
    cleaned = _strip_meta_words(cleaned)
    cleaned = _rewrite_dialogue_labels(cleaned, scene_person_codes, code_to_name)
    cleaned = _strip_trailing_speech_content(cleaned, scene_person_codes, code_to_name)
    cleaned = _rewrite_speech_fragments(cleaned, scene_person_codes, code_to_name)
    cleaned = _rewrite_center_scene_phrase(cleaned, scene_person_codes, code_to_name)
    cleaned = _cleanup_visual_stub(cleaned, scene_person_codes)
    if not cleaned or _is_name_only_text(cleaned, scene_person_codes, code_to_name):
        cleaned = build_fallback_scene_text(scene_person_codes, code_to_name)
    cleaned = ensure_scene_mentions_people(cleaned, scene_person_codes, code_to_name)
    cleaned = _dedupe_subject_prefixes(cleaned, scene_person_codes, code_to_name)
    cleaned = MULTI_SPACE_REGEX.sub(" ", cleaned).strip(" ,.;:·")
    return cleaned


def normalize_scene_persons_list(
    value: Any,
    event_person_codes: list[str],
) -> list[str]:
    allowed = set(event_person_codes)
    normalized: list[str] = []
    if isinstance(value, list):
        for item in value:
            if isinstance(item, str):
                code = item.strip().lower()
            elif isinstance(item, dict):
                code = str(item.get("code") or "").strip().lower()
            else:
                code = ""
            if code and code in allowed:
                normalized.append(code)
    return dedupe_preserve_order(normalized)
