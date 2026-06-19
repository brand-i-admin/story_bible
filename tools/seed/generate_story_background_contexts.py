#!/usr/bin/env python3
"""Normalize story summaries and generate background_context fields for story JSON.

The story JSON remains the source of truth. This helper keeps the generated
blurbs reviewable next to ``summary``, ``story_scenes`` and ``scene_captions``.
Summaries are curated from the Bible text and are not rebuilt from scene captions.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

MAX_SUMMARY_CHARS = 130
MAX_BACKGROUND_CHARS = 220

ERA_CONTEXT: dict[str, str] = {
    "era_primeval": "창세기 원역사는 창조부터 바벨 사건까지를 다루는 초반 이야기입니다.",
    "era_patriarch": "족장 시대는 아브라함, 이삭, 야곱, 요셉의 가족 이야기가 중심입니다.",
    "era_exodus": "출애굽과 광야 여정은 이스라엘이 애굽을 떠나 시내산과 광야를 지나는 시기입니다.",
    "era_judges": "사사 시대는 여호수아 이후부터 왕정 이전까지의 이스라엘 이야기입니다.",
    "era_monarchy": "통일왕국 시대는 사울, 다윗, 솔로몬이 이스라엘 전체를 다스리던 시기입니다.",
    "era_divided_kingdom": "분열왕국 시대는 솔로몬 이후 남유다와 북이스라엘로 나뉜 시기입니다.",
    "era_exile_return": "포로와 귀환 시대는 바벨론 포로와 페르시아 때의 귀환을 다룹니다.",
    "era_nt_public_ministry": "복음서의 예수님 이야기는 예수님의 탄생, 공적 사역, 십자가와 부활로 이어집니다.",
    "era_nt_apostolic": "사도행전 시대는 예루살렘 교회에서 시작해 지중해 지역으로 이어진 시기입니다.",
    "era_nt_post_apostolic": "서신서 시대는 사도들과 교회 지도자들이 여러 교회와 성도에게 보낸 편지가 중심입니다.",
    "era_nt_consummation": "요한계시록은 소아시아 일곱 교회에 보낸 계시와 환상을 담은 책입니다.",
}

EPISTLE_CONTEXT: dict[str, str] = {
    "롬": "로마서는 바울이 로마 방문을 앞두고, 유대인과 이방인이 함께 있던 로마 교회에 복음과 선교 계획을 설명하려고 쓴 편지입니다.",
    "고전": "고린도전서는 바울이 에베소에 머무는 동안, 분열과 음행, 소송, 예배 문제를 겪던 고린도 교회에 보낸 편지입니다.",
    "고후": "고린도후서는 바울이 마게도냐에서, 관계가 흔들렸던 고린도 교회에 사도의 진심과 연보 참여를 전하려고 쓴 편지입니다.",
    "갈": "갈라디아서는 바울이 할례와 율법 준수 요구에 흔들리던 갈라디아 교회들에게 복음의 자유를 지키라고 쓴 편지입니다.",
    "엡": "에베소서는 바울이 감옥에서, 에베소와 주변 성도들에게 유대인과 이방인이 그리스도 안에서 한 몸임을 전한 편지입니다.",
    "빌": "빌립보서는 바울이 감옥에서, 복음 동역과 후원을 이어 온 빌립보 교회에 기쁨과 겸손을 권하려고 쓴 편지입니다.",
    "골": "골로새서는 바울이 감옥에서, 거짓 가르침의 영향을 받을 수 있던 골로새 교회에 그리스도의 충분함을 전한 편지입니다.",
    "살전": "데살로니가전서는 바울이 갑작스럽게 떠난 뒤, 박해 속에 남은 새 신자들에게 믿음과 재림 소망을 격려하려고 쓴 편지입니다.",
    "살후": "데살로니가후서는 바울이 박해와 재림 오해로 흔들리던 데살로니가 교회에 인내와 성실한 삶을 권하려고 쓴 편지입니다.",
    "딤전": "디모데전서는 바울이 에베소에 남겨 둔 디모데에게 거짓 교훈을 막고 교회 질서를 세우라고 맡긴 편지입니다.",
    "딤후": "디모데후서는 바울이 마지막 투옥 중, 동역자 디모데에게 고난 속에서도 말씀과 사명을 지키라고 쓴 편지입니다.",
    "딛": "디도서는 바울이 그레데에 남겨 둔 디도에게 장로를 세우고 거짓 가르침을 바로잡으라고 맡긴 편지입니다.",
    "몬": "빌레몬서는 바울이 감옥에서, 도망쳤다가 바울을 만난 오네시모를 빌레몬이 형제로 받아들이게 부탁한 편지입니다.",
    "히": "히브리서는 저자가 이름을 밝히지 않은 채, 압박 속에 흔들리던 유대 배경 성도들에게 예수님의 뛰어남을 전한 글입니다.",
    "약": "야고보서는 예루살렘의 야고보가 흩어진 유대 그리스도인들에게 시험과 가난 속에서도 행하는 믿음을 권한 편지입니다.",
    "벧전": "베드로전서는 베드로가 소아시아 여러 지역에서 고난과 사회적 압박을 겪던 성도들에게 소망을 전한 편지입니다.",
    "벧후": "베드로후서는 베드로가 거짓 교사와 재림 조롱에 흔들릴 수 있던 성도들에게 사도적 가르침을 기억시키려 쓴 편지입니다.",
    "요일": "요한일서는 요한이 예수님의 성육신을 부정하는 가르침과 공동체 분열을 겪던 교회들에게 참 믿음을 분별하게 한 편지입니다.",
    "요이": "요한이서는 요한이 한 교회 공동체에 사랑과 진리 안에 머물며 거짓 교사를 경계하라고 보낸 짧은 편지입니다.",
    "요삼": "요한삼서는 요한이 가이오에게 순회 전도자들을 환대하라고 격려하며 디오드레베의 독단을 경계한 짧은 편지입니다.",
    "유": "유다서는 야고보의 형제 유다가 거짓 교사들이 들어온 교회에 믿음의 도를 지키라고 보낸 짧은 편지입니다.",
    "계": "요한계시록은 요한이 밧모섬에서 받은 계시를 소아시아 일곱 교회에 전하도록 기록한 책입니다.",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Regenerate summary and background_context for story JSON."
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/200_stories",
        help="Directory containing era story JSON files.",
    )
    parser.add_argument(
        "--bible-dir",
        default="assets/bible",
        help="Reserved for compatibility; background text uses bible_ref metadata.",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Do not write files; exit 1 if generated content would differ.",
    )
    return parser.parse_args()


def normalize_space(text: str) -> str:
    return re.sub(r"\s+", " ", text).strip()


def trim_sentence(text: str, *, max_chars: int = 120) -> str:
    text = normalize_space(text)
    text = re.sub(r"^(장면\s*\d+\s*[:：.-]\s*)", "", text)
    if len(text) <= max_chars:
        return text
    cut = text[:max_chars].rstrip()
    for marker in ("다.", "다", "며", "고", ","):
        index = cut.rfind(marker)
        if index >= max_chars * 0.55:
            return cut[: index + len(marker)].rstrip(" ,")
    return cut.rstrip(" ,") + "..."


def clamp_summary(text: str) -> str:
    text = ensure_period(text)
    if len(text) <= MAX_SUMMARY_CHARS:
        return text
    shortened = trim_sentence(text, max_chars=MAX_SUMMARY_CHARS - 1)
    return ensure_period(shortened.replace("...", "").rstrip(" .,"))


def ensure_period(text: str) -> str:
    text = normalize_space(text).rstrip(" .")
    if not text:
        return text
    return f"{text}."


def title_short(title: str) -> str:
    title = re.sub(r"^\d+\s*", "", title).strip()
    return title.split(":", 1)[0].strip() or title


def josa_eul(word: str) -> str:
    word = word.strip()
    if not word:
        return "를"
    last = word[-1]
    code = ord(last)
    if not (0xAC00 <= code <= 0xD7A3):
        return "를"
    return "을" if (code - 0xAC00) % 28 else "를"


def build_flow_sentence(event: dict[str, Any]) -> str:
    topic = title_short(str(event.get("title", "")))
    if topic:
        return ensure_period(f"이 이야기는 「{topic}」{josa_eul(topic)} 다룹니다")
    return "이 이야기는 성경 전체 흐름 안에 놓인 사건입니다."


def clamp_background_context(text: str) -> str:
    text = ensure_period(text)
    if len(text) <= MAX_BACKGROUND_CHARS:
        return text
    shortened = trim_sentence(text, max_chars=MAX_BACKGROUND_CHARS - 1)
    return ensure_period(shortened.replace("...", "").rstrip(" .,"))


def build_summary(event: dict[str, Any]) -> str:
    summary = str(event.get("summary", "")).strip()
    fallback = title_short(str(event.get("title", "")))
    return clamp_summary(summary or fallback)


def build_background_context(event: dict[str, Any]) -> str:
    era = str(event.get("era", "")).strip()
    first_book = ""
    if event.get("bible_ref"):
        first_book = str(event["bible_ref"][0].get("book", "")).strip()
    opening = EPISTLE_CONTEXT.get(first_book) or ERA_CONTEXT.get(
        era,
        "이 이야기는 성경 전체 흐름 안에 놓인 사건입니다.",
    )

    result = f"{ensure_period(opening)} {build_flow_sentence(event)}".strip()
    return clamp_background_context(result)


def insert_after_summary(
    event: dict[str, Any],
    summary: str,
    background: str,
) -> dict[str, Any]:
    updated: dict[str, Any] = {}
    inserted_background = False
    for key, value in event.items():
        if key == "summary":
            updated[key] = summary
            updated["background_context"] = background
            inserted_background = True
        elif key == "background_context":
            continue
        else:
            updated[key] = value
    if not inserted_background:
        updated["summary"] = summary
        updated["background_context"] = background
    return updated


def update_story_file(path: Path) -> tuple[bool, list[dict[str, Any]]]:
    events = json.loads(path.read_text(encoding="utf-8"))
    updated_events: list[dict[str, Any]] = []
    changed = False
    for event in events:
        summary = build_summary(event)
        background = build_background_context(event)
        updated = insert_after_summary(event, summary, background)
        if updated != event:
            changed = True
        updated_events.append(updated)
    return changed, updated_events


def main() -> int:
    args = parse_args()
    stories_dir = Path(args.stories_dir)
    changed_paths: list[Path] = []

    for path in sorted(stories_dir.glob("*.json")):
        changed, events = update_story_file(path)
        if not changed:
            continue
        changed_paths.append(path)
        if not args.check:
            path.write_text(
                json.dumps(events, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )

    if args.check and changed_paths:
        for path in changed_paths:
            print(f"would update {path}")
        return 1

    print(f"{'Would update' if args.check else 'Updated'} {len(changed_paths)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
