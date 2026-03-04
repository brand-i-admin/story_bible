#!/usr/bin/env python3
"""Generate high-quality study metadata + SQL seed.

This script produces:
1) JSON payload with polished meta/points.
2) SQL that upserts books/meta/points and rebuilds verse_pages from bible_verses.
"""

from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NORMALIZED_PATH = ROOT / "supabase" / "200_stories" / "200_stories_normalized.json"
SEED_SQL_PATH = ROOT / "supabase" / "200_stories" / "200_stories_seed.sql"
OUT_DIR = ROOT / "supabase" / "study_generated"
OUT_JSON = OUT_DIR / "study_meta_seed_215_hq_dbmatch.json"
OUT_SQL = OUT_DIR / "study_meta_seed_215_hq_dbmatch.sql"


BOOK_ORDER = {
    "창세기": 1,
    "출애굽기": 2,
    "레위기": 3,
    "민수기": 4,
    "신명기": 5,
    "여호수아": 6,
    "사사기": 7,
    "룻기": 8,
    "사무엘상": 9,
    "사무엘하": 10,
    "열왕기상": 11,
    "열왕기하": 12,
    "역대상": 13,
    "역대하": 14,
    "에스라": 15,
    "느헤미야": 16,
    "에스더": 17,
    "욥기": 18,
    "시편": 19,
    "잠언": 20,
    "전도서": 21,
    "아가": 22,
    "이사야": 23,
    "예레미야": 24,
    "예레미야애가": 25,
    "에스겔": 26,
    "다니엘": 27,
    "호세아": 28,
    "요엘": 29,
    "아모스": 30,
    "오바댜": 31,
    "요나": 32,
    "미가": 33,
    "나훔": 34,
    "하박국": 35,
    "스바냐": 36,
    "학개": 37,
    "스가랴": 38,
    "말라기": 39,
    "마태복음": 40,
    "마가복음": 41,
    "누가복음": 42,
    "요한복음": 43,
    "사도행전": 44,
    "로마서": 45,
    "고린도전서": 46,
    "고린도후서": 47,
    "갈라디아서": 48,
    "에베소서": 49,
    "빌립보서": 50,
    "골로새서": 51,
    "데살로니가전서": 52,
    "데살로니가후서": 53,
    "디모데전서": 54,
    "디모데후서": 55,
    "디도서": 56,
    "빌레몬서": 57,
    "히브리서": 58,
    "야고보서": 59,
    "베드로전서": 60,
    "베드로후서": 61,
    "요한일서": 62,
    "요한이서": 63,
    "요한삼서": 64,
    "유다서": 65,
    "요한계시록": 66,
}

GOSPEL = {"마태복음", "마가복음", "누가복음", "요한복음"}
PAUL = {
    "로마서",
    "고린도전서",
    "고린도후서",
    "갈라디아서",
    "에베소서",
    "빌립보서",
    "골로새서",
    "데살로니가전서",
    "데살로니가후서",
    "디모데전서",
    "디모데후서",
    "디도서",
    "빌레몬서",
}
GENERAL_EPISTLES = {
    "히브리서",
    "야고보서",
    "베드로전서",
    "베드로후서",
    "요한일서",
    "요한이서",
    "요한삼서",
    "유다서",
}

SECTION_ORDER = {
    "태초와 족장": 1,
    "출애굽과 율법": 2,
    "정복과 사사": 3,
    "왕국의 흥망": 4,
    "시와 지혜": 5,
    "예언과 경고": 6,
    "포로 귀환": 7,
    "예수님의 사역": 8,
    "교회의 탄생": 9,
    "복음의 확장": 10,
    "교회의 권면": 11,
    "종말과 소망": 12,
}


def parse_sql_string(token: str):
    token = token.strip()
    if token.lower() == "null":
        return None
    if token.startswith("'") and token.endswith("'"):
        return token[1:-1].replace("''", "'")
    try:
        if "." in token:
            return float(token)
        return int(token)
    except Exception:
        return token


def split_fields(tuple_text: str) -> list[str]:
    out: list[str] = []
    cur: list[str] = []
    in_str = False
    i = 0
    while i < len(tuple_text):
        ch = tuple_text[i]
        if in_str:
            cur.append(ch)
            if ch == "'":
                if i + 1 < len(tuple_text) and tuple_text[i + 1] == "'":
                    cur.append("'")
                    i += 1
                else:
                    in_str = False
        else:
            if ch == "'":
                in_str = True
                cur.append(ch)
            elif ch == ",":
                out.append("".join(cur).strip())
                cur = []
            else:
                cur.append(ch)
        i += 1
    if cur:
        out.append("".join(cur).strip())
    return out


def parse_seed_events(seed_sql: str) -> dict[str, dict]:
    starts = [
        m.start()
        for m in re.finditer(r"with\s+seed_events\s*\(", seed_sql, flags=re.IGNORECASE)
    ]
    rows: list[dict] = []
    for st in starts:
        i = seed_sql.find("values", st)
        if i < 0:
            continue
        i += len("values")
        n = len(seed_sql)
        depth = 0
        in_str = False
        tuple_start = None
        while i < n:
            if depth == 0 and seed_sql.startswith(")\ninsert into events", i):
                break
            ch = seed_sql[i]
            if in_str:
                if ch == "'":
                    if i + 1 < n and seed_sql[i + 1] == "'":
                        i += 1
                    else:
                        in_str = False
            else:
                if ch == "'":
                    in_str = True
                elif ch == "(":
                    if depth == 0:
                        tuple_start = i + 1
                    depth += 1
                elif ch == ")":
                    depth -= 1
                    if depth == 0 and tuple_start is not None:
                        fields = split_fields(seed_sql[tuple_start:i])
                        if len(fields) == 14:
                            vals = [parse_sql_string(f) for f in fields]
                            rows.append(
                                {
                                    "code": vals[0],
                                    "title": vals[2],
                                    "summary": vals[3],
                                    "story": vals[4],
                                    "short_story": vals[5],
                                }
                            )
            i += 1
    return {row["code"]: row for row in rows}


def split_sentences(text: str) -> list[str]:
    compact = re.sub(r"\s+", " ", (text or "").strip())
    if not compact:
        return []
    return [
        s.strip()
        for s in re.split(r"(?<=다\.)\s+|(?<=[.!?])\s+", compact)
        if s.strip()
    ]


def section_for_book(book: str) -> str:
    if book == "창세기":
        return "태초와 족장"
    if book in {"출애굽기", "레위기", "민수기", "신명기"}:
        return "출애굽과 율법"
    if book in {"여호수아", "사사기", "룻기"}:
        return "정복과 사사"
    if book in {"사무엘상", "사무엘하", "열왕기상", "열왕기하", "역대상", "역대하"}:
        return "왕국의 흥망"
    if book in {"욥기", "시편", "잠언", "전도서", "아가"}:
        return "시와 지혜"
    if book in {
        "이사야",
        "예레미야",
        "예레미야애가",
        "에스겔",
        "다니엘",
        "호세아",
        "요엘",
        "아모스",
        "오바댜",
        "요나",
        "미가",
        "나훔",
        "하박국",
        "스바냐",
        "학개",
        "스가랴",
        "말라기",
    }:
        return "예언과 경고"
    if book in {"에스라", "느헤미야", "에스더"}:
        return "포로 귀환"
    if book in GOSPEL:
        return "예수님의 사역"
    if book == "사도행전":
        return "교회의 탄생"
    if book in PAUL:
        return "복음의 확장"
    if book in GENERAL_EPISTLES:
        return "교회의 권면"
    if book == "요한계시록":
        return "종말과 소망"
    return "태초와 족장"


def theme_for(book: str, title: str, summary: str) -> str:
    text = f"{title} {summary}"
    if any(k in text for k in ["창조", "에덴", "바벨", "홍수"]):
        return "origin"
    if any(k in text for k in ["언약", "약속", "부르심", "축복"]):
        return "covenant"
    if any(k in text for k in ["타락", "죄", "심판", "멸망", "포로"]):
        return "judgment"
    if any(k in text for k in ["왕", "전쟁", "반역", "혁명"]):
        return "kingdom"
    if any(k in text for k in ["예언", "선지자"]):
        return "prophecy"
    if book in GOSPEL:
        return "gospel"
    if book == "사도행전":
        return "mission"
    if book in PAUL or book in GENERAL_EPISTLES:
        return "church"
    if book == "요한계시록":
        return "consummation"
    return "general"


def emoji_for(theme: str, testament: str) -> str:
    m = {
        "origin": "🌌",
        "covenant": "🌈",
        "judgment": "⚖️",
        "kingdom": "👑",
        "prophecy": "📯",
        "gospel": "✝️",
        "mission": "🕊️",
        "church": "📜",
        "consummation": "✨",
        "general": "📖" if testament == "OT" else "✝️",
    }
    return m.get(theme, "📖")


def pick_quote(short_story: str, ref: str) -> str:
    sentences = split_sentences(short_story)
    if not sentences:
        return ref
    priority = ["하나님", "여호와", "예수", "성령", "언약", "회개", "복음", "부활", "십자가"]
    selected = None
    for s in sentences:
        if any(k in s for k in priority) and 18 <= len(s) <= 90:
            selected = s
            break
    if selected is None:
        selected = min(sentences, key=lambda s: abs(len(s) - 52))
    if len(selected) > 92:
        selected = selected[:92].rstrip(" ,.") + "…"
    return f"“{selected}” ({ref})" if ref else f"“{selected}”"


def point_labels(h: int) -> tuple[str, str, str]:
    l1 = ["핵심 메시지:", "서사 포인트:", "구속사 포인트:", "장면 해설:"][h % 4]
    l2 = ["본문 관찰:", "문맥 연결:", "신학적 통찰:", "본문 읽기:"][(h // 5) % 4]
    l3 = ["삶의 적용:", "오늘의 결단:", "공동체 적용:", "묵상 질문:"][(h // 11) % 4]
    return l1, l2, l3


def point_three(theme: str, h: int) -> str:
    options = {
        "origin": [
            "하나님이 세우신 질서를 신뢰하고, 삶의 자리에서도 창조의 선함을 지키는 선택이 필요하다.",
            "혼돈처럼 보이는 상황에서도 하나님의 말씀은 질서를 회복하신다는 믿음을 붙들어야 한다.",
            "출발점이 흔들릴수록 피조물의 자리가 아니라 창조주의 주권을 먼저 고백해야 한다.",
        ],
        "covenant": [
            "언약의 약속은 지연되어 보여도 폐기되지 않는다. 조급함보다 신뢰를 선택하는 훈련이 필요하다.",
            "하나님이 먼저 시작하신 약속에 응답하는 순종이 신앙의 방향을 바르게 세운다.",
            "눈앞의 계산보다 말씀의 약속을 우선할 때, 작은 순종이 긴 역사로 이어진다.",
        ],
        "judgment": [
            "심판의 본문은 두려움을 넘어서 회개로 부르시는 하나님의 자비를 함께 읽게 한다.",
            "죄의 결과를 가볍게 여기지 말고, 관계 회복을 향한 즉각적인 돌이킴으로 나아가야 한다.",
            "무너짐의 장면에서도 하나님은 회복의 문을 남겨 두신다는 사실을 놓치지 말아야 한다.",
        ],
        "kingdom": [
            "권력의 성패보다 중요한 기준은 하나님의 통치에 대한 순종인지 여부라는 점을 기억해야 한다.",
            "강한 리더십보다 말씀 앞에서 자신을 낮추는 겸손이 공동체를 살린다.",
            "역사의 승부는 인간의 전략만이 아니라 하나님이 세우시는 질서에 의해 결정된다.",
        ],
        "prophecy": [
            "예언의 말씀은 미래 정보가 아니라 현재 순종을 요구하는 하나님의 부르심으로 들어야 한다.",
            "경고의 음성을 회피하지 말고, 말씀의 기준으로 삶의 방향을 재정렬해야 한다.",
            "하나님은 시대의 혼란 속에서도 말씀으로 길을 제시하신다는 확신을 붙들어야 한다.",
        ],
        "gospel": [
            "복음의 중심은 사건의 정보가 아니라 예수 그리스도의 인격과 통치에 대한 응답이다.",
            "예수님의 길을 따른다는 것은 기적의 감탄을 넘어 제자의 순종으로 이어져야 한다.",
            "은혜로 부르심을 받은 자답게, 말보다 삶으로 복음의 진실성을 드러내야 한다.",
        ],
        "mission": [
            "복음은 환경의 제약을 넘어 전진한다. 막힘처럼 보이는 자리도 선교의 통로가 될 수 있다.",
            "교회의 사명은 확장보다 본질이다. 말씀과 성령에 붙들릴 때 길이 열린다.",
            "증언의 삶은 거창한 계획보다 오늘 주어진 자리에서 담대히 말하는 데서 시작된다.",
        ],
        "church": [
            "교회는 지식의 축적보다 복음에 합당한 삶으로 진리를 증언해야 한다.",
            "신학적 고백은 공동체의 실제 관계와 섬김 속에서 검증되고 완성된다.",
            "은혜로 받은 복음은 개인 경건을 넘어 공동체적 책임으로 확장되어야 한다.",
        ],
        "consummation": [
            "종말의 본문은 공포의 자극이 아니라 끝내 이루실 하나님의 승리를 바라보게 한다.",
            "마지막 심판의 선언은 현재의 삶을 거룩과 인내로 재정렬하라는 요청이기도 하다.",
            "새 하늘과 새 땅의 소망은 현실 도피가 아니라 오늘의 충성을 가능하게 하는 힘이다.",
        ],
        "general": [
            "눈앞의 유불리보다 말씀의 방향을 우선할 때 신앙의 축이 바로 선다.",
            "실패와 흔들림 속에서도 하나님이 여시는 회복의 길을 신뢰해야 한다.",
            "본문의 메시지를 정보로 끝내지 말고, 오늘의 선택과 관계 속에서 살아내야 한다.",
        ],
    }
    arr = options.get(theme, options["general"])
    return arr[h % len(arr)]


def build_points(
    event_code: str,
    title: str,
    summary: str,
    short_story: str,
    ref: str,
    theme: str,
) -> list[dict]:
    h = sum(ord(c) for c in event_code)
    l1, l2, l3 = point_labels(h)
    clean_summary = summary.strip()
    if clean_summary and clean_summary[-1] not in ".!?…":
        clean_summary += "."

    p1 = f"{title} 사건의 핵심은 {clean_summary or '본문의 중심 메시지를 선명하게 드러내는 데 있다.'}"
    short_sentences = split_sentences(short_story)
    core_obs = short_sentences[1] if len(short_sentences) > 1 else (short_sentences[0] if short_sentences else "")
    if core_obs and len(core_obs) > 110:
        core_obs = core_obs[:110].rstrip(" ,.") + "…"
    if core_obs:
        p2 = f"{ref} 본문은 \"{core_obs}\"라는 장면을 통해 사건의 신학적 방향을 밝혀 준다."
    else:
        p2 = f"{ref} 본문을 따라 읽으면 하나님의 주권과 인간의 반응이 어떻게 맞물리는지 분명히 드러난다."

    p3 = point_three(theme, h)

    return [
        {"order_num": 1, "bold_label": l1, "content": p1},
        {"order_num": 2, "bold_label": l2, "content": p2},
        {"order_num": 3, "bold_label": l3, "content": p3},
    ]


def event_order_by_book(normalized_rows: list[dict]) -> dict[str, int]:
    by_book: dict[str, list[dict]] = {}
    for row in normalized_rows:
        refs = row.get("bible_refs") or []
        book = refs[0].get("book_name") if refs else ""
        by_book.setdefault(book, []).append(row)
    for book, rows in by_book.items():
        rows.sort(
            key=lambda x: (
                x.get("time_sort_key") or 0,
                x.get("number") or 0,
                x.get("code") or "",
            )
        )
    out: dict[str, int] = {}
    for _, rows in by_book.items():
        for idx, row in enumerate(rows, start=1):
            out[row["code"]] = idx
    return out


def build_records(normalized_rows: list[dict], seed_by_code: dict[str, dict]) -> list[dict]:
    order_map = event_order_by_book(normalized_rows)
    records: list[dict] = []
    for row in sorted(normalized_rows, key=lambda x: x.get("number") or 0):
        code = row["code"]
        seed = seed_by_code.get(code, {})

        refs = row.get("bible_refs") or []
        first_ref = refs[0] if refs else {}
        book = first_ref.get("book_name") or ""
        ref_text = first_ref.get("display_text") or ""

        title = (seed.get("title") or row.get("title") or "").strip()
        summary = (seed.get("summary") or row.get("summary") or "").strip()
        short_story = (seed.get("short_story") or "").strip()

        testament = "NT" if BOOK_ORDER.get(book, 0) >= 40 else "OT"
        theme = theme_for(book, title, summary)
        section = section_for_book(book)

        points = build_points(
            event_code=code,
            title=title,
            summary=summary,
            short_story=short_story,
            ref=ref_text,
            theme=theme,
        )

        # Verse text is built from bible_verses in SQL phase.
        verse_pages = [
            {"order_num": idx + 1, "ref": ref_item.get("display_text") or "", "text": ""}
            for idx, ref_item in enumerate(refs)
        ]

        records.append(
            {
                "event_code": code,
                "book_name": book,
                "testament": testament,
                "book_order_num": BOOK_ORDER.get(book, 999),
                "event_order_num": order_map.get(code, 9999),
                "section": section,
                "section_order": SECTION_ORDER.get(section, 99),
                "emoji": emoji_for(theme, testament),
                "snippet": summary or title,
                "quote": pick_quote(short_story, ref_text),
                "box_title": f"{title} 핵심 메시지",
                "points": points,
                "verse_pages": verse_pages,
            }
        )
    return records


def build_sql(payload_json: str) -> str:
    return f"""begin;
create temp table if not exists _study_payload_hq_dbmatch (data jsonb not null);
truncate _study_payload_hq_dbmatch;
insert into _study_payload_hq_dbmatch(data) values ('{payload_json}'::jsonb);

with rows as (
  select *
  from jsonb_to_recordset((select data from _study_payload_hq_dbmatch)) as x(
    event_code text,
    book_name text,
    testament text,
    book_order_num int,
    event_order_num int,
    section text,
    section_order int,
    emoji text,
    snippet text,
    quote text,
    box_title text,
    points jsonb,
    verse_pages jsonb
  )
)
insert into books(name, testament, order_num)
select distinct book_name, testament, book_order_num
from rows
where coalesce(book_name, '') <> ''
on conflict (name) do update
set testament = excluded.testament,
    order_num = excluded.order_num;

with rows as (
  select *
  from jsonb_to_recordset((select data from _study_payload_hq_dbmatch)) as x(
    event_code text,
    book_name text,
    testament text,
    book_order_num int,
    event_order_num int,
    section text,
    section_order int,
    emoji text,
    snippet text,
    quote text,
    box_title text,
    points jsonb,
    verse_pages jsonb
  )
),
resolved as (
  select
    e.id as event_id,
    b.id as book_id,
    r.*
  from rows r
  join events e on e.code = r.event_code
  left join books b on b.name = r.book_name
)
insert into study_event_meta(
  event_id, book_id, order_num, section, section_order, emoji, snippet, quote, box_title
)
select
  event_id,
  book_id,
  event_order_num,
  section,
  coalesce(section_order, 0),
  emoji,
  coalesce(snippet, ''),
  coalesce(quote, ''),
  coalesce(box_title, '')
from resolved
on conflict (event_id) do update
set
  book_id = excluded.book_id,
  order_num = excluded.order_num,
  section = excluded.section,
  section_order = excluded.section_order,
  emoji = excluded.emoji,
  snippet = excluded.snippet,
  quote = excluded.quote,
  box_title = excluded.box_title;

with rows as (
  select *
  from jsonb_to_recordset((select data from _study_payload_hq_dbmatch)) as x(
    event_code text,
    book_name text,
    testament text,
    book_order_num int,
    event_order_num int,
    section text,
    section_order int,
    emoji text,
    snippet text,
    quote text,
    box_title text,
    points jsonb,
    verse_pages jsonb
  )
),
targets as (
  select e.id as event_id
  from rows r
  join events e on e.code = r.event_code
)
delete from study_event_points p
using targets t
where p.event_id = t.event_id;

with rows as (
  select *
  from jsonb_to_recordset((select data from _study_payload_hq_dbmatch)) as x(
    event_code text,
    book_name text,
    testament text,
    book_order_num int,
    event_order_num int,
    section text,
    section_order int,
    emoji text,
    snippet text,
    quote text,
    box_title text,
    points jsonb,
    verse_pages jsonb
  )
),
resolved as (
  select e.id as event_id, r.points
  from rows r
  join events e on e.code = r.event_code
)
insert into study_event_points(event_id, order_num, bold_label, content)
select
  r.event_id,
  p.order_num,
  p.bold_label,
  p.content
from resolved r
cross join lateral jsonb_to_recordset(r.points) as p(
  order_num int,
  bold_label text,
  content text
);

-- Rebuild verse_pages directly from bible_verses (KRV), chunked by 8 verses per page.
with rows as (
  select *
  from jsonb_to_recordset((select data from _study_payload_hq_dbmatch)) as x(
    event_code text,
    book_name text,
    testament text,
    book_order_num int,
    event_order_num int,
    section text,
    section_order int,
    emoji text,
    snippet text,
    quote text,
    box_title text,
    points jsonb,
    verse_pages jsonb
  )
),
targets as (
  select e.id as event_id
  from rows r
  join events e on e.code = r.event_code
)
delete from study_verse_pages v
using targets t
where v.event_id = t.event_id;

with rows as (
  select *
  from jsonb_to_recordset((select data from _study_payload_hq_dbmatch)) as x(
    event_code text,
    book_name text,
    testament text,
    book_order_num int,
    event_order_num int,
    section text,
    section_order int,
    emoji text,
    snippet text,
    quote text,
    box_title text,
    points jsonb,
    verse_pages jsonb
  )
),
target_events as (
  select e.id as event_id
  from rows r
  join events e on e.code = r.event_code
),
refs as (
  select
    te.event_id,
    r.id as ref_id,
    r.book,
    r.chapter_start,
    r.verse_start,
    coalesce(r.chapter_end, r.chapter_start) as chapter_end,
    coalesce(r.verse_end, r.verse_start) as verse_end
  from target_events te
  join event_bible_refs r on r.event_id = te.event_id
),
verses as (
  select
    rf.event_id,
    rf.ref_id,
    rf.book,
    bv.chapter_no,
    bv.verse_no,
    bv.verse_text,
    row_number() over (
      partition by rf.event_id, rf.ref_id
      order by bv.chapter_no, bv.verse_no
    ) as rn
  from refs rf
  join bible_verses bv
    on bv.translation = 'KRV'
   and bv.book_name = rf.book
   and (
     (bv.chapter_no > rf.chapter_start
      or (bv.chapter_no = rf.chapter_start and bv.verse_no >= rf.verse_start))
     and
     (bv.chapter_no < rf.chapter_end
      or (bv.chapter_no = rf.chapter_end and bv.verse_no <= rf.verse_end))
   )
),
chunked as (
  select
    event_id,
    ref_id,
    book,
    chapter_no,
    verse_no,
    verse_text,
    ((rn - 1) / 8) + 1 as chunk_no
  from verses
),
chunk_agg as (
  select
    event_id,
    ref_id,
    book,
    chunk_no,
    (array_agg(chapter_no order by chapter_no, verse_no))[1] as start_ch,
    (array_agg(verse_no order by chapter_no, verse_no))[1] as start_vs,
    (array_agg(chapter_no order by chapter_no desc, verse_no desc))[1] as end_ch,
    (array_agg(verse_no order by chapter_no desc, verse_no desc))[1] as end_vs,
    string_agg(verse_text, ' ' order by chapter_no, verse_no) as text
  from chunked
  group by event_id, ref_id, book, chunk_no
),
pages as (
  select
    event_id,
    row_number() over (partition by event_id order by ref_id, chunk_no) as order_num,
    case
      when start_ch = end_ch
        then format('%s %s:%s-%s', book, start_ch, start_vs, end_vs)
      else format('%s %s:%s-%s:%s', book, start_ch, start_vs, end_ch, end_vs)
    end as ref,
    text
  from chunk_agg
)
insert into study_verse_pages(event_id, order_num, ref, text)
select event_id, order_num, ref, text
from pages;

commit;
"""


def main() -> None:
    normalized = json.loads(NORMALIZED_PATH.read_text(encoding="utf-8"))
    seed_by_code = parse_seed_events(SEED_SQL_PATH.read_text(encoding="utf-8"))
    records = build_records(normalized, seed_by_code)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(records, ensure_ascii=False, indent=2), encoding="utf-8")

    payload = json.dumps(records, ensure_ascii=False).replace("'", "''")
    OUT_SQL.write_text(build_sql(payload), encoding="utf-8")

    print(f"generated records: {len(records)}")
    print(f"json: {OUT_JSON}")
    print(f"sql : {OUT_SQL}")


if __name__ == "__main__":
    main()
