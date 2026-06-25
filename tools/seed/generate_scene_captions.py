#!/usr/bin/env python3
"""Generate editable scene captions for assets/events story JSON.

The source ``story_scenes`` values are image-generation prompts, so they often
include art-direction phrases such as "글자 없는 말풍선" or safety notes such as
"피와 시신은 보이지 않는다". This tool keeps the visible story action and writes
short user-facing ``scene_captions`` aligned with each scene.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_STORY_DIR = ROOT / "assets" / "events"

MAX_CAPTION_CHARS = 58
MIN_CAPTION_CHARS = 8

PROMPT_ONLY_MARKERS = (
    "글자 없는 말풍선",
    "큰 글자 없는 말풍선",
    "말풍선에는",
    "말풍선 안에는",
    "작은 그림처럼",
    "읽을 수 있는 글자",
    "글자는 보이지",
    "글자도 보이지",
    "글자는 없다",
    "글자는 없음",
    "글자가 없다",
    "이름표나 글자",
    "직접 보이지 않는다",
    "보이지 않는다",
    "전혀 보이지 않는다",
    "잔혹한 묘사",
    "세부 묘사",
    "선정적 묘사",
    "성적 장면",
    "성폭력 행위",
    "노골적 신체 묘사",
    "도살 장면",
)

CAPTION_FORBIDDEN_MARKERS = (
    "글자 없는",
    "글자 없는 말풍선",
    "말풍선",
    "작은 그림처럼",
    "보이지 않는다",
    "글자는",
    "글자가",
    "읽을 수 있는",
    "직접적인",
    "잔혹한",
    "선정적",
    "성적 장면",
    "노골적",
    "위 칸",
    "가운데 칸",
    "아래 칸",
)

AGE_PREFIX_RE = re.compile(
    r"\b(?:십대|20대|30대|40대|50대|60대|70대|80대|팔십\s*세|"
    r"노년|젊은|늙은|나이 든|흰수염의|흰 머리의|흰수염|머리가 하얀)\s+"
)
SPLIT_RE = re.compile(r"[.!?]\s*|,\s*|;\s*")
MULTI_SPACE_RE = re.compile(r"\s+")

DROP_PHRASES = (
    "장면",
    "컷",
    "세로 3단 분할",
    "세로 3등분 구도",
    "절제된 세로 2분할",
    "두 구역으로 나눈",
    "화면은 좌우로 분명히 나뉜다",
    "피나",
    "피와",
    "시신이나",
    "시신과",
    "상처와",
    "폭력이나",
    "노출이나",
)

ENDING_REPLACEMENTS = (
    ("보이는 모습", "보인다"),
    ("보이는 장면", "보인다"),
    ("하는 모습", "한다"),
    ("있는 모습", "있다"),
    ("표현한다", "보인다"),
    ("표현된다", "드러난다"),
    ("보이며", "보이고"),
)

TRIM_AFTER_MARKERS = (
    "두 사람의 얼굴에는",
    "얼굴에는",
    "표정이며",
    "표정으로",
    "뒤쪽에는",
    "위쪽에는",
    "주변에는",
    "곁에는",
    "가까운 한쪽에는",
)

ACTION_ENDING_REPLACEMENTS = (
    ("가는 장면", "간다"),
    ("하는 장면", "한다"),
    ("보이는 장면", "보인다"),
    ("하지만", "한다"),
    ("준비하였고", "준비한다"),
    ("지으시고", "지으신다"),
    ("명하시", "명하신다"),
    ("덮고", "덮는다"),
    ("채워지고", "채워진다"),
    ("가르치고", "가르친다"),
    ("전하고", "전한다"),
    ("준비하고", "준비한다"),
    ("말하고", "말한다"),
    ("바라보고", "바라본다"),
    ("바라보며", "바라본다"),
    ("듣고", "듣는다"),
    ("서고", "선다"),
    ("들고", "든다"),
    ("쌓고", "쌓는다"),
    ("놓고", "놓는다"),
    ("숨고", "숨는다"),
    ("피하고", "피한다"),
    ("도망가고", "도망간다"),
    ("모이고", "모인다"),
    ("있고", "있다"),
    ("하며", "한다"),
)

AWKWARD_SUFFIX_REPLACEMENTS = (
    ("졌으다", "졌다"),
    ("놓으다", "놓는다"),
    ("있으다", "있다"),
    ("받으다", "받는다"),
    ("뱉으다", "뱉는다"),
    ("얹으다", "얹는다"),
    ("모으다", "모은다"),
    ("안으다", "안는다"),
    ("꿇으다", "꿇는다"),
    ("닦으다", "닦는다"),
    ("걸으다", "걷는다"),
    ("넣으다", "넣는다"),
    ("나아가다", "나아간다"),
    ("끌려가다", "끌려간다"),
    ("걸어 나가다", "걸어 나간다"),
    ("가져가다", "가져간다"),
    ("지나가다", "지나간다"),
    ("돌아오다", "돌아온다"),
    ("내려오다", "내려온다"),
    ("들어오다", "들어온다"),
    ("나오다", "나온다"),
    ("세우다", "세운다"),
    ("섬기다", "섬긴다"),
    ("숨기다", "숨긴다"),
    ("이기다", "이긴다"),
    ("넘기다", "넘긴다"),
    ("들이다", "들인다"),
    ("하시다", "하신다"),
    ("휩싸이다", "휩싸인다"),
    ("하는", "한다"),
    ("하다", "한다"),
    ("되다", "된다"),
    ("지다", "진다"),
    ("놓다", "놓는다"),
    ("보이다", "보인다"),
    ("주다", "준다"),
    ("드리다", "드린다"),
    ("엎드리다", "엎드린다"),
    ("보내다", "보낸다"),
    ("오르다", "오른다"),
    ("서다", "선다"),
    ("알리다", "알린다"),
    ("받다", "받는다"),
    ("앉다", "앉는다"),
    ("흘리다", "흘린다"),
    ("묻다", "묻는다"),
    ("들어서다", "들어선다"),
    ("읽다", "읽는다"),
    ("내려앉다", "내려앉는다"),
    ("남다", "남는다"),
    ("울부짖다", "울부짖는다"),
    ("늘어나다", "늘어난다"),
)


def normalize_space(text: str) -> str:
    return MULTI_SPACE_RE.sub(" ", text.replace("\n", " ")).strip()


def strip_title_number(title: str) -> str:
    return re.sub(r"^\d{3}\s+", "", title).strip()


def _remove_prompt_tail(clause: str) -> str:
    text = clause
    for marker in ("글자 없는 말풍선", "말풍선 안에는", "말풍선에는"):
        if marker in text:
            before = text.split(marker, 1)[0]
            generic_before = (
                "하나님의 빛에서 나오는",
                "하나님의 영광에서 나온",
                "그 말의 뜻을 보여 주는",
                "큰",
                "모세 옆의 큰",
            )
            if any(phrase in before for phrase in generic_before):
                return ""
            text = before
    text = re.sub(r"\([^)]*말풍선[^)]*\)", "", text)
    return normalize_space(text)


def _clean_clause(clause: str) -> str:
    text = normalize_space(clause)
    text = re.sub(r"^\s*장면\s*\d+\s*:\s*", "", text)
    text = re.sub(
        r"^(?:세로\s*\d+단\s*분할\s*컷|세로\s*\d+등분\s*구도)\s*:\s*", "", text
    )
    text = re.sub(r"^(?:두 구역으로 나눈 장면|절제된 세로 2분할 장면)\s*:\s*", "", text)
    text = re.sub(r"^(?:위|가운데|아래)\s*칸에는\s*", "", text)
    text = AGE_PREFIX_RE.sub("", text)
    text = _remove_prompt_tail(text)
    text = text.replace("옷을 입지 않은 ", "")
    text = text.replace("벌거벗은 ", "")
    text = text.replace("사람 형상 없는 ", "")
    text = text.replace("하나님의 영을 상징하는 ", "")
    text = text.replace("같은 모습으로 보이며", "")
    text = text.replace("같은 모습으로 표현한다", "")
    text = text.replace("이름 없는 ", "")
    text = text.replace("라는 글자나 깃발 문구는 보이지 않는다", "")
    if "먹지말라" in text:
        return "하나님이 아담에게 선악을 알게 하는 나무를 먹지 말라 명하신다"
    text = re.sub(r"\b(?:아무|어떤) 사람도 보이지 않는다\b", "", text)
    text = re.sub(r"\b사람은 전혀 보이지 않는다\b", "", text)
    text = re.sub(
        r"\b(?:피|피와 상처|피와 시신|시신|폭력|노출|성적 장면)[^,。.]*보이지 않는다\b",
        "",
        text,
    )
    text = re.sub(r"\b글자[^,。.]*(?:보이지 않는다|없다)\b", "", text)
    text = re.sub(r"\b읽을 수 있는 글자[^,。.]*\b", "", text)
    for marker in TRIM_AFTER_MARKERS:
        if marker in text and len(text) > 32:
            text = text.split(marker, 1)[0]
    text = re.sub(r"(?:두 사람의|그의|그녀의|그들의)\s*$", "", text)
    text = normalize_space(text.strip(" ,.;:"))
    for old, new in ENDING_REPLACEMENTS:
        if text.endswith(old):
            text = f"{text[: -len(old)]}{new}"
    text = polish_ending(text)
    return normalize_space(text.strip(" ,.;:"))


def _is_prompt_only(clause: str) -> bool:
    compact = normalize_space(clause)
    if not compact:
        return True
    if "말풍선" in compact and len(_remove_prompt_tail(compact)) < MIN_CAPTION_CHARS:
        return True
    return any(marker in compact for marker in PROMPT_ONLY_MARKERS)


def _caption_from_clauses(scene: str) -> str:
    cleaned: list[str] = []
    for raw_clause in SPLIT_RE.split(scene):
        clause = _clean_clause(raw_clause)
        if not clause:
            continue
        if _is_prompt_only(clause):
            continue
        if clause in cleaned:
            continue
        cleaned.append(clause)

    if not cleaned:
        fallback = _clean_clause(scene)
        if fallback and not _is_prompt_only(fallback):
            cleaned.append(fallback)

    if not cleaned:
        return ""

    caption = cleaned[0]
    if len(caption) < 26 and len(cleaned) > 1:
        next_clause = cleaned[1]
        if len(f"{caption}, {next_clause}") <= MAX_CAPTION_CHARS + 12:
            caption = f"{caption}, {next_clause}"
    return shorten_caption(caption)


def polish_ending(text: str) -> str:
    caption = normalize_space(text.strip(" ,.;:"))
    if caption.endswith("가 있으며"):
        caption = f"{caption[: -len('가 있으며')]}가 있다"
    elif caption.endswith("이 있으며"):
        caption = f"{caption[: -len('이 있으며')]}이 있다"
    for old, new in ACTION_ENDING_REPLACEMENTS:
        if caption.endswith(old):
            caption = f"{caption[: -len(old)]}{new}"
            break
    if caption.endswith("하고"):
        caption = f"{caption[: -len('하고')]}한다"
    elif caption.endswith("되고"):
        caption = f"{caption[: -len('되고')]}된다"
    elif caption.endswith("지고"):
        caption = f"{caption[: -len('지고')]}진다"
    elif caption.endswith("가고"):
        caption = f"{caption[: -len('가고')]}간다"
    elif caption.endswith("오고"):
        caption = f"{caption[: -len('오고')]}온다"
    elif caption.endswith("우고"):
        caption = f"{caption[: -len('우고')]}운다"
    elif caption.endswith("하시"):
        caption = f"{caption[: -len('시')]}신다"
    elif caption.endswith("가"):
        caption = f"{caption[: -len('가')]}간다"
    elif caption.endswith("고"):
        caption = f"{caption[: -len('고')]}다"
    elif caption.endswith("며"):
        caption = f"{caption[: -len('며')]}다"
    elif caption.endswith("지만"):
        caption = f"{caption[: -len('지만')]}다"
    elif caption.endswith("기다"):
        caption = f"{caption[: -len('기다')]}긴다"
    elif caption.endswith("서서"):
        caption = f"{caption[: -len('서서')]}서 있다"
    elif caption.endswith("평안한"):
        caption = f"{caption[: -len('평안한')]}평안하다"
    for old, new in AWKWARD_SUFFIX_REPLACEMENTS:
        if caption.endswith(old):
            caption = f"{caption[: -len(old)]}{new}"
            break
    return normalize_space(caption.strip(" ,.;:"))


def focus_action(text: str) -> str:
    caption = normalize_space(text)
    if "자 " in caption:
        candidate = normalize_space(caption.split("자 ", 1)[1])
        if MIN_CAPTION_CHARS <= len(candidate) <= MAX_CAPTION_CHARS:
            return polish_ending(candidate)
    if "지만 " in caption:
        candidate = normalize_space(caption.split("지만 ", 1)[0])
        if len(candidate) >= MIN_CAPTION_CHARS:
            return polish_ending(candidate)
    if " 있으며 " in caption:
        candidate = normalize_space(caption.split(" 있으며 ", 1)[0])
        if len(candidate) >= MIN_CAPTION_CHARS:
            return polish_ending(f"{candidate} 있다")
    return polish_ending(caption)


def shorten_caption(text: str) -> str:
    caption = focus_action(text)
    if len(caption) <= MAX_CAPTION_CHARS:
        return caption.strip(" ,.;:")

    candidates = [
        caption[:MAX_CAPTION_CHARS].rsplit("하며", 1)[0],
        caption[:MAX_CAPTION_CHARS].rsplit("하고", 1)[0],
        caption[:MAX_CAPTION_CHARS].rsplit("이며", 1)[0],
        caption[:MAX_CAPTION_CHARS].rsplit("며", 1)[0],
        caption[:MAX_CAPTION_CHARS].rsplit("고", 1)[0],
        caption[:MAX_CAPTION_CHARS].rsplit("서", 1)[0],
        caption[:MAX_CAPTION_CHARS].rsplit(" ", 1)[0],
    ]
    for candidate in candidates:
        candidate = normalize_space(candidate.strip(" ,.;:"))
        if len(candidate) >= MIN_CAPTION_CHARS:
            return polish_ending(candidate)
    return caption[:MAX_CAPTION_CHARS].strip(" ,.;:")


def _summary_fallback(event: dict[str, Any], scene_index: int) -> str:
    title = strip_title_number(str(event.get("title", "")))
    summary = _clean_clause(str(event.get("summary", "")))
    if summary:
        caption = shorten_caption(summary)
        if caption.endswith("다"):
            return caption
    if title:
        caption = shorten_caption(f"{title}의 중요한 순간이다")
        if caption.endswith("다"):
            return caption
    return f"{scene_index + 1}번째 이야기의 중요한 순간이다"


def _complete_caption(event: dict[str, Any], caption: str, scene_index: int) -> str:
    text = normalize_space(caption)
    if text.endswith("장면"):
        text = f"{text}이다"
    elif text.endswith("모습"):
        text = f"{text}이다"
    elif text.endswith("편지"):
        text = f"{text}를 쓴다"
    elif text.endswith("기도"):
        text = f"{text}한다"
    text = shorten_caption(text)
    if text.endswith("다"):
        return text
    return _summary_fallback(event, scene_index)


def build_caption(event: dict[str, Any], scene: str, scene_index: int) -> str:
    caption = _caption_from_clauses(scene)
    if not caption:
        caption = _summary_fallback(event, scene_index)
    for marker in CAPTION_FORBIDDEN_MARKERS:
        if marker in caption:
            caption = _summary_fallback(event, scene_index)
            break
    return _complete_caption(event, caption, scene_index)


def _insert_after_story_scenes(
    event: dict[str, Any],
    captions: list[str],
) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    inserted = False
    for key, value in event.items():
        updated[key] = value
        if key == "story_scenes":
            updated["scene_captions"] = captions
            inserted = True
        elif key == "scene_captions":
            updated[key] = captions
            inserted = True
    if not inserted:
        updated["scene_captions"] = captions
    return updated


def update_story_file(path: Path, *, dry_run: bool) -> tuple[int, int]:
    events = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(events, list):
        raise ValueError(f"JSON root must be list: {path}")

    changed = 0
    scene_count = 0
    updated_events: list[dict[str, Any]] = []
    for event in events:
        if not isinstance(event, dict):
            raise ValueError(f"Story event must be object in {path}: {event!r}")
        raw_scenes = event.get("story_scenes") or []
        if not isinstance(raw_scenes, list):
            raise ValueError(
                f"story_scenes must be list in {path}: {event.get('title')}"
            )
        scenes = [str(scene) for scene in raw_scenes]
        captions = [
            build_caption(event, scene, index) for index, scene in enumerate(scenes)
        ]
        scene_count += len(captions)
        if captions != event.get("scene_captions"):
            changed += 1
        updated_events.append(_insert_after_story_scenes(event, captions))

    if not dry_run:
        path.write_text(
            json.dumps(updated_events, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
    return changed, scene_count


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--story-dir",
        default=str(DEFAULT_STORY_DIR),
        help="Directory containing era_*.json story files.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report changes without writing files.",
    )
    args = parser.parse_args()

    story_dir = Path(args.story_dir)
    files = sorted(story_dir.glob("era_*.json"))
    if not files:
        raise FileNotFoundError(f"No era_*.json files found in {story_dir}")

    changed_events = 0
    scenes = 0
    for path in files:
        file_changed, file_scenes = update_story_file(path, dry_run=args.dry_run)
        changed_events += file_changed
        scenes += file_scenes

    mode = "would update" if args.dry_run else "updated"
    print(f"{mode} {changed_events} events / {scenes} scene captions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
