#!/usr/bin/env python3
"""Build daily_quiz seed SQL and guide docs from the current story/map seed.

The generated questions intentionally follow the app's map flow:

  era -> event-bearing region -> event

`place_name` / landmark names are used only as explanation detail. They are not
used as selectable region choices.
"""

from __future__ import annotations

import argparse
import collections
import glob
import hashlib
import json
import random
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUTPUT = ROOT / "supabase" / "seeds" / "daily_quiz.sql"
DEFAULT_DOCS_OUTPUT = ROOT / "docs" / "DAILY_QUIZ_SEED_GUIDE.md"

CATEGORY_LABELS: dict[str, str] = {
    "event_region_match": "사건-지역 매칭형",
    "region_event_exclusion": "시대-지역 사건 제외형",
    "character_region_exclusion": "인물-지역 대비형",
    "character_event_region_match": "인물 사건-지역 매칭형",
    "region_event_inclusion": "지역 사건 포함형",
}

CATEGORY_CAPS: dict[str, int] = {
    "event_region_match": 40,
    "region_event_exclusion": 20,
    "character_region_exclusion": 15,
    "character_event_region_match": 15,
    "region_event_inclusion": 10,
}

CHARACTER_NAME_FALLBACKS: dict[str, str] = {
    "god": "하나님",
    "disciples": "제자들",
    "israelites": "이스라엘 백성",
    "apostles": "사도들",
    "heavenly_beings": "하늘의 존재들",
    "lamb": "어린양",
    "church_of_antioch": "안디옥 교회",
}


@dataclass(frozen=True)
class EventSeed:
    era: str
    story_index: int
    title: str
    place_name: str
    region_code: str
    landmark_code: str
    characters: tuple[str, ...]


@dataclass(frozen=True)
class DailyQuizDraft:
    quiz_type: str
    question: str
    choices: tuple[str, ...]
    answer_index: int
    explanation: str
    source: str

    @property
    def answer(self) -> str:
        return self.choices[self.answer_index - 1]

    @property
    def slug(self) -> str:
        digest = hashlib.sha256(
            f"{self.quiz_type}:{self.question}".encode("utf-8")
        ).hexdigest()[:10]
        return f"daily_map_{self.quiz_type}_{digest}"


def _quote_label(value: str) -> str:
    return f"'{value}'"


def _stable_shuffle(seed_key: str, values: Iterable) -> list:
    out = list(values)
    seed = int.from_bytes(hashlib.sha256(seed_key.encode("utf-8")).digest()[:8], "big")
    random.Random(seed).shuffle(out)
    return out


def _parse_era_names(db_init_path: Path) -> dict[str, str]:
    text = db_init_path.read_text(encoding="utf-8")
    names: dict[str, str] = {}
    pattern = re.compile(
        r"\('(?P<code>era_[^']+)',\s*(?:'(?P<testament>old|new)',\s*)?'(?P<name>[^']+)'"
    )
    for match in pattern.finditer(text):
        names.setdefault(match.group("code"), match.group("name"))
    return names


def _load_story_characters(stories_dir: Path) -> dict[tuple[str, int], tuple[str, ...]]:
    out: dict[tuple[str, int], tuple[str, ...]] = {}
    for path_text in glob.glob(str(stories_dir / "*.json")):
        path = Path(path_text)
        for row in json.loads(path.read_text(encoding="utf-8")):
            out[(row["era"], row["story_index"])] = tuple(row.get("characters", []))
    return out


def _load_character_names(meta_path: Path) -> dict[str, str]:
    raw = json.loads(meta_path.read_text(encoding="utf-8"))
    names = {
        row["code"]: row.get("name_ko") or row["code"]
        for row in raw.get("characters", [])
    }
    names.update(CHARACTER_NAME_FALLBACKS)
    return names


def _load_event_seeds(
    root: Path,
) -> tuple[list[EventSeed], dict[str, str], dict[str, str], dict[str, str]]:
    era_names = _parse_era_names(root / "db_init.sql")

    landmarks = json.loads(
        (root / "assets" / "landmarks" / "landmarks.json").read_text(encoding="utf-8")
    )
    region_names = {row["code"]: row["name"] for row in landmarks["regions"]}
    character_names = _load_character_names(
        root / "tools" / "seed" / "character_meta.json"
    )
    story_characters = _load_story_characters(root / "assets" / "200_stories")
    mapping = json.loads(
        (root / "assets" / "landmarks" / "event_region_mapping.json").read_text(
            encoding="utf-8"
        )
    )["rows"]

    events: list[EventSeed] = []
    for row in mapping:
        events.append(
            EventSeed(
                era=row["era"],
                story_index=row["story_index"],
                title=row["title"],
                place_name=row["place_name"],
                region_code=row["region_code"],
                landmark_code=row["landmark_code"],
                characters=story_characters.get(
                    (row["era"], row["story_index"]), tuple()
                ),
            )
        )
    return events, era_names, region_names, character_names


class DailyQuizBuilder:
    def __init__(
        self,
        *,
        events: list[EventSeed],
        era_names: dict[str, str],
        region_names: dict[str, str],
        character_names: dict[str, str],
    ) -> None:
        self.events = events
        self.era_names = era_names
        self.region_names = region_names
        self.character_names = character_names
        self.by_era: dict[str, list[EventSeed]] = collections.defaultdict(list)
        self.by_era_region: dict[str, dict[str, list[EventSeed]]] = (
            collections.defaultdict(lambda: collections.defaultdict(list))
        )
        self.by_era_character: dict[str, dict[str, list[EventSeed]]] = (
            collections.defaultdict(lambda: collections.defaultdict(list))
        )
        for event in events:
            self.by_era[event.era].append(event)
            self.by_era_region[event.era][event.region_code].append(event)
            for character in event.characters:
                self.by_era_character[event.era][character].append(event)

    def build(self, max_questions: int) -> list[DailyQuizDraft]:
        candidates: list[DailyQuizDraft] = []
        candidates.extend(self._event_region_match())
        candidates.extend(self._region_event_exclusion())
        candidates.extend(self._character_region_exclusion())
        candidates.extend(self._character_event_region_match())
        candidates.extend(self._region_event_inclusion())

        selected: list[DailyQuizDraft] = []
        counts: collections.Counter[str] = collections.Counter()
        seen_questions: set[str] = set()
        for draft in candidates:
            if draft.question in seen_questions:
                continue
            if counts[draft.quiz_type] >= CATEGORY_CAPS[draft.quiz_type]:
                continue
            selected.append(draft)
            counts[draft.quiz_type] += 1
            seen_questions.add(draft.question)
            if len(selected) >= max_questions:
                break
        return selected

    def _region_choices(
        self,
        *,
        era: str,
        answer_region: str,
        seed_key: str,
    ) -> tuple[str, ...]:
        regions = sorted(
            self.by_era_region[era], key=lambda code: self.region_names[code]
        )
        others = [code for code in regions if code != answer_region]
        if len(regions) <= 6:
            picked = [answer_region, *others]
        else:
            picked = [answer_region, *_stable_shuffle(seed_key, others)[:5]]
        return tuple(
            self.region_names[code] for code in _stable_shuffle(seed_key + ":c", picked)
        )

    def _add(
        self,
        out: list[DailyQuizDraft],
        *,
        quiz_type: str,
        question: str,
        choices: Iterable[str],
        answer: str,
        explanation: str,
        source: str,
    ) -> None:
        choice_list = tuple(choices)
        if not (2 <= len(choice_list) <= 6):
            return
        if len(set(choice_list)) != len(choice_list):
            return
        if answer not in choice_list:
            return
        out.append(
            DailyQuizDraft(
                quiz_type=quiz_type,
                question=question,
                choices=choice_list,
                answer_index=choice_list.index(answer) + 1,
                explanation=explanation,
                source=source,
            )
        )

    def _event_region_match(self) -> list[DailyQuizDraft]:
        out: list[DailyQuizDraft] = []
        for era in sorted(self.by_era):
            if len(self.by_era_region[era]) < 2:
                continue
            for event in sorted(
                self.by_era[era], key=lambda item: (item.story_index, item.title)
            ):
                answer = self.region_names[event.region_code]
                self._add(
                    out,
                    quiz_type="event_region_match",
                    question=(
                        f"{_quote_label(self.era_names[event.era])}에서 {_quote_label(event.title)} "
                        "사건이 속한 지역은 어디입니까?"
                    ),
                    choices=self._region_choices(
                        era=event.era,
                        answer_region=event.region_code,
                        seed_key=f"event-region:{event.era}:{event.story_index}",
                    ),
                    answer=answer,
                    explanation=(
                        f"{_quote_label(event.title)} 사건은 {_quote_label(answer)} 지역의 세부 장소 "
                        f"{_quote_label(event.place_name)}에 매핑되어 있습니다."
                    ),
                    source=f"{event.era}:{event.story_index}",
                )
        return out

    def _region_event_exclusion(self) -> list[DailyQuizDraft]:
        out: list[DailyQuizDraft] = []
        for era in sorted(self.by_era_region):
            for region_code in sorted(
                self.by_era_region[era], key=lambda code: self.region_names[code]
            ):
                inside = sorted(
                    self.by_era_region[era][region_code],
                    key=lambda item: (item.story_index, item.title),
                )
                outside = sorted(
                    [
                        event
                        for event in self.by_era[era]
                        if event.region_code != region_code
                    ],
                    key=lambda item: (
                        self.region_names[item.region_code],
                        item.story_index,
                        item.title,
                    ),
                )
                if not inside or not outside:
                    continue
                answer_event = _stable_shuffle(
                    f"region-exclusion:out:{era}:{region_code}", outside
                )[0]
                inside_events = _stable_shuffle(
                    f"region-exclusion:in:{era}:{region_code}", inside
                )[: min(3, len(inside))]
                choices = _stable_shuffle(
                    f"region-exclusion:choices:{era}:{region_code}",
                    [event.title for event in inside_events] + [answer_event.title],
                )
                region_name = self.region_names[region_code]
                answer_region = self.region_names[answer_event.region_code]
                self._add(
                    out,
                    quiz_type="region_event_exclusion",
                    question=(
                        f"{_quote_label(self.era_names[era])}에서 {_quote_label(region_name)} 지역을 "
                        "선택했을 때 볼 수 없는 사건은 무엇입니까?"
                    ),
                    choices=choices,
                    answer=answer_event.title,
                    explanation=(
                        f"{_quote_label(answer_event.title)} 사건은 {_quote_label(answer_region)} 지역 사건입니다. "
                        f"나머지 선택지는 {_quote_label(region_name)} 지역에서 볼 수 있습니다."
                    ),
                    source=f"{era}:{region_code}",
                )
        return out

    def _character_region_exclusion(self) -> list[DailyQuizDraft]:
        out: list[DailyQuizDraft] = []
        for era in sorted(self.by_era_character):
            region_codes = sorted(
                self.by_era_region[era], key=lambda code: self.region_names[code]
            )
            if len(region_codes) < 2:
                continue
            for character, events in sorted(
                self.by_era_character[era].items(),
                key=lambda item: (-len(item[1]), item[0]),
            ):
                connected_regions = sorted(
                    {event.region_code for event in events},
                    key=lambda code: self.region_names[code],
                )
                disconnected_regions = [
                    code for code in region_codes if code not in connected_regions
                ]
                if not connected_regions or not disconnected_regions:
                    continue
                answer_region = _stable_shuffle(
                    f"character-region:answer:{era}:{character}",
                    disconnected_regions,
                )[0]
                picked_connected = _stable_shuffle(
                    f"character-region:connected:{era}:{character}",
                    connected_regions,
                )[: min(5, len(connected_regions))]
                choices = tuple(
                    self.region_names[code]
                    for code in _stable_shuffle(
                        f"character-region:choices:{era}:{character}",
                        [*picked_connected, answer_region],
                    )
                )
                answer = self.region_names[answer_region]
                name = self.character_names.get(character, character)
                connected_text = ", ".join(
                    self.region_names[code] for code in connected_regions
                )
                self._add(
                    out,
                    quiz_type="character_region_exclusion",
                    question=(
                        f"{_quote_label(self.era_names[era])}에서 {_quote_label(name)} 이야기들과 "
                        "직접 연결되지 않은 지역은 어디입니까?"
                    ),
                    choices=choices,
                    answer=answer,
                    explanation=(
                        f"{_quote_label(name)} 관련 사건은 현재 seed에서 {_quote_label(connected_text)} "
                        f"지역에 매핑되어 있습니다. {_quote_label(answer)} 지역은 이 인물의 "
                        "사건 지역이 아닙니다."
                    ),
                    source=f"{era}:{character}",
                )
        return out

    def _character_event_region_match(self) -> list[DailyQuizDraft]:
        out: list[DailyQuizDraft] = []
        for era in sorted(self.by_era_character):
            if len(self.by_era_region[era]) < 2:
                continue
            for character, events in sorted(
                self.by_era_character[era].items(),
                key=lambda item: (-len(item[1]), item[0]),
            ):
                name = self.character_names.get(character, character)
                for event in sorted(
                    events, key=lambda item: (item.story_index, item.title)
                ):
                    answer = self.region_names[event.region_code]
                    self._add(
                        out,
                        quiz_type="character_event_region_match",
                        question=(
                            f"{_quote_label(self.era_names[era])}에서 {_quote_label(name)} 관련 "
                            f"{_quote_label(event.title)} 사건은 어느 지역에서 확인할 수 있습니까?"
                        ),
                        choices=self._region_choices(
                            era=era,
                            answer_region=event.region_code,
                            seed_key=(
                                f"character-event-region:{era}:"
                                f"{character}:{event.story_index}"
                            ),
                        ),
                        answer=answer,
                        explanation=(
                            f"{_quote_label(event.title)} 사건은 {_quote_label(answer)} 지역의 세부 장소 "
                            f"{_quote_label(event.place_name)}에 매핑되어 있습니다."
                        ),
                        source=f"{era}:{event.story_index}:{character}",
                    )
        return out

    def _region_event_inclusion(self) -> list[DailyQuizDraft]:
        out: list[DailyQuizDraft] = []
        for era in sorted(self.by_era_region):
            for region_code in sorted(
                self.by_era_region[era], key=lambda code: self.region_names[code]
            ):
                inside = sorted(
                    self.by_era_region[era][region_code],
                    key=lambda item: (item.story_index, item.title),
                )
                outside = sorted(
                    [
                        event
                        for event in self.by_era[era]
                        if event.region_code != region_code
                    ],
                    key=lambda item: (
                        self.region_names[item.region_code],
                        item.story_index,
                        item.title,
                    ),
                )
                if not inside or not outside:
                    continue
                answer_event = _stable_shuffle(
                    f"region-inclusion:in:{era}:{region_code}", inside
                )[0]
                outside_events = _stable_shuffle(
                    f"region-inclusion:out:{era}:{region_code}", outside
                )[: min(3, len(outside))]
                choices = _stable_shuffle(
                    f"region-inclusion:choices:{era}:{region_code}",
                    [answer_event.title] + [event.title for event in outside_events],
                )
                region_name = self.region_names[region_code]
                self._add(
                    out,
                    quiz_type="region_event_inclusion",
                    question=(
                        f"{_quote_label(self.era_names[era])}에서 {_quote_label(region_name)} 지역을 "
                        "선택했을 때 볼 수 있는 사건은 무엇입니까?"
                    ),
                    choices=choices,
                    answer=answer_event.title,
                    explanation=(
                        f"{_quote_label(answer_event.title)} 사건은 {_quote_label(region_name)} 지역의 세부 장소 "
                        f"{_quote_label(answer_event.place_name)}에 매핑되어 있습니다."
                    ),
                    source=f"{era}:{region_code}:{answer_event.story_index}",
                )
        return out


def _dollar_quote(value: str) -> str:
    tag = "dq"
    while f"${tag}$" in value:
        tag += "q"
    return f"${tag}${value}${tag}$"


def _jsonb_array(values: Iterable[str]) -> str:
    return f"{_dollar_quote(json.dumps(list(values), ensure_ascii=False))}::jsonb"


def _sql_str(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def build_sql(questions: list[DailyQuizDraft]) -> str:
    lines = [
        "-- auto-generated by tools/seed/build_daily_quiz_seed_sql.py",
        "-- source: assets/200_stories/*.json + assets/landmarks/event_region_mapping.json",
        "-- idempotent: upsert by daily_quiz.slug",
        "",
        "begin;",
        "",
        "insert into daily_quiz (",
        "  slug, quiz_type, question, choices, answer_index, explanation",
        ")",
        "values",
    ]
    rows: list[str] = []
    for draft in questions:
        rows.append(
            "  ("
            f"{_sql_str(draft.slug)}, "
            f"{_sql_str(draft.quiz_type)}, "
            f"{_dollar_quote(draft.question)}, "
            f"{_jsonb_array(draft.choices)}, "
            f"{draft.answer_index}, "
            f"{_dollar_quote(draft.explanation)}"
            ")"
        )
    lines.append(",\n".join(rows))
    lines.extend(
        [
            "on conflict (slug) do update set",
            "  quiz_type = excluded.quiz_type,",
            "  question = excluded.question,",
            "  choices = excluded.choices,",
            "  answer_index = excluded.answer_index,",
            "  explanation = excluded.explanation;",
            "",
            "commit;",
            "",
        ]
    )
    return "\n".join(lines)


def _md_escape(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", "<br>")


def build_docs(questions: list[DailyQuizDraft]) -> str:
    counts = collections.Counter(q.quiz_type for q in questions)
    lines = [
        "# 매일 지도 퀴즈 시드 가이드",
        "",
        "이 문서는 `tools/seed/build_daily_quiz_seed_sql.py`가 현재 seed 데이터를 기준으로 생성했다.",
        "",
        "## 핵심 원칙",
        "",
        "- 모든 문항은 앱의 탐색 흐름인 `시대 선택 -> 사건이 있는 지역 선택 -> 사건 확인`을 따른다.",
        "- 질문의 시대명은 `eras.name` 값을 사용한다.",
        "- 보기의 지역명은 사건이 실제로 매핑된 region만 사용한다. 사건이 없는 region은 선택지에 넣지 않는다.",
        "- `place_name`이나 landmark 이름은 해설에서만 사용한다. 예: `수산 궁(페르시아)`는 region이 아니라 `페르시아` region 안의 세부 장소다.",
        "- 보기 수는 2~6개다. 어떤 시대는 사건 보유 region이 2~3개뿐이므로 4지선다를 강제하지 않는다.",
        "- 같은 질문 문장을 중복 생성하지 않는다.",
        "- `다음`, `바로 다음`, `몇 번째`처럼 `story_index` 재정렬에 취약한 표현은 쓰지 않는다.",
        "",
        "## 문항 유형",
        "",
        "| 유형 | 목적 | 생성 규칙 | 예시 |",
        "|------|------|-----------|------|",
        "| 사건-지역 매칭형 | 사건을 보고 시대 안의 region을 찾게 한다 | 정답/오답 모두 같은 시대의 사건 보유 region | `'출애굽 시대'에서 '홍해: 길이 열리다' 사건이 속한 지역은 어디입니까?` |",
        "| 시대-지역 사건 제외형 | 특정 시대/region에서 보이는 사건과 아닌 사건을 구분한다 | 정답은 같은 시대의 다른 region 사건, 오답은 해당 region 사건 | `'포로 및 포로 후기 시대'에서 '페르시아' 지역을 선택했을 때 볼 수 없는 사건은 무엇입니까?` |",
        "| 인물-지역 대비형 | 인물의 행적이 걸친 region을 비교한다 | 정답은 같은 시대이지만 해당 인물 사건이 없는 region | `'족장 시대'에서 '아브라함' 이야기들과 직접 연결되지 않은 지역은 어디입니까?` |",
        "| 인물 사건-지역 매칭형 | 인물+사건을 같이 보고 region을 찾게 한다 | 사건의 region을 정답으로 두고 같은 시대 region을 오답으로 둔다 | `'사도의 시대'에서 '바울' 관련 '빌립보: 감옥의 찬송' 사건은 어느 지역에서 확인할 수 있습니까?` |",
        "| 지역 사건 포함형 | 특정 region을 선택했을 때 볼 수 있는 사건을 찾게 한다 | 정답은 해당 region 사건, 오답은 같은 시대의 다른 region 사건 | `'왕정 시대'에서 '유대' 지역을 선택했을 때 볼 수 있는 사건은 무엇입니까?` |",
        "",
        "## 생성 결과 요약",
        "",
    ]
    for quiz_type, label in CATEGORY_LABELS.items():
        lines.append(f"- {label}: {counts.get(quiz_type, 0)}문항")
    lines.extend(
        [
            f"- 총 문항: {len(questions)}문항",
            "",
            "## 생성 문항",
            "",
            "| # | 유형 | 질문 | 보기 | 정답 | 해설 |",
            "|---|------|------|------|------|------|",
        ]
    )
    for index, draft in enumerate(questions, 1):
        choices = "<br>".join(
            f"{choice_index + 1}. {_md_escape(choice)}"
            for choice_index, choice in enumerate(draft.choices)
        )
        lines.append(
            "| "
            f"{index} | "
            f"{CATEGORY_LABELS[draft.quiz_type]} | "
            f"{_md_escape(draft.question)} | "
            f"{choices} | "
            f"{draft.answer_index}. {_md_escape(draft.answer)} | "
            f"{_md_escape(draft.explanation)} |"
        )
    lines.append("")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build daily_quiz seed SQL and guide docs."
    )
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--docs-output", type=Path, default=DEFAULT_DOCS_OUTPUT)
    parser.add_argument("--max-questions", type=int, default=100)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    events, era_names, region_names, character_names = _load_event_seeds(ROOT)
    questions = DailyQuizBuilder(
        events=events,
        era_names=era_names,
        region_names=region_names,
        character_names=character_names,
    ).build(args.max_questions)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(build_sql(questions), encoding="utf-8")

    if args.docs_output:
        args.docs_output.parent.mkdir(parents=True, exist_ok=True)
        args.docs_output.write_text(build_docs(questions), encoding="utf-8")

    print(f"wrote {len(questions)} daily quiz questions to {args.output}")
    if args.docs_output:
        print(f"wrote guide to {args.docs_output}")


if __name__ == "__main__":
    main()
