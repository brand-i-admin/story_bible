#!/usr/bin/env python3
"""Build SQL seed/upsert script for bible_verses (KRV).

Supported input modes:
  1) Structured rows file (.csv/.tsv/.jsonl)
  2) Book text directory (default: assets/bible, CP949 text files)

Structured rows expected fields (aliases supported):
  - book_no OR book_name
  - chapter_no OR chapter
  - verse_no OR verse
  - verse_text OR text

Optional fields:
  - translation (default: KRV)
  - testament (old/new, ot/nt, 구약/신약). If omitted, inferred by book_no.

Examples:
  # Directory mode (assets/bible/*.txt)
  python tools/build_krv_seed_sql.py \
    --input-dir assets/bible \
    --output supabase/seeds/krv_bible_verses.sql \
    --truncate-translation

  # CSV mode
  python tools/build_krv_seed_sql.py \
    --input /path/to/krv.csv \
    --output supabase/seeds/krv_bible_verses.sql \
    --truncate-translation
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Any, TypeVar


BOOKS: list[tuple[str, int]] = [
    ("창세기", 50),
    ("출애굽기", 40),
    ("레위기", 27),
    ("민수기", 36),
    ("신명기", 34),
    ("여호수아", 24),
    ("사사기", 21),
    ("룻기", 4),
    ("사무엘상", 31),
    ("사무엘하", 24),
    ("열왕기상", 22),
    ("열왕기하", 25),
    ("역대상", 29),
    ("역대하", 36),
    ("에스라", 10),
    ("느헤미야", 13),
    ("에스더", 10),
    ("욥기", 42),
    ("시편", 150),
    ("잠언", 31),
    ("전도서", 12),
    ("아가", 8),
    ("이사야", 66),
    ("예레미야", 52),
    ("예레미야애가", 5),
    ("에스겔", 48),
    ("다니엘", 12),
    ("호세아", 14),
    ("요엘", 3),
    ("아모스", 9),
    ("오바댜", 1),
    ("요나", 4),
    ("미가", 7),
    ("나훔", 3),
    ("하박국", 3),
    ("스바냐", 3),
    ("학개", 2),
    ("스가랴", 14),
    ("말라기", 4),
    ("마태복음", 28),
    ("마가복음", 16),
    ("누가복음", 24),
    ("요한복음", 21),
    ("사도행전", 28),
    ("로마서", 16),
    ("고린도전서", 16),
    ("고린도후서", 13),
    ("갈라디아서", 6),
    ("에베소서", 6),
    ("빌립보서", 4),
    ("골로새서", 4),
    ("데살로니가전서", 5),
    ("데살로니가후서", 3),
    ("디모데전서", 6),
    ("디모데후서", 4),
    ("디도서", 3),
    ("빌레몬서", 1),
    ("히브리서", 13),
    ("야고보서", 5),
    ("베드로전서", 5),
    ("베드로후서", 3),
    ("요한일서", 5),
    ("요한이서", 1),
    ("요한삼서", 1),
    ("유다서", 1),
    ("요한계시록", 22),
]


KOR_ALIAS_TO_BOOK_NO = {
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


def norm_book_name(text: str) -> str:
    return re.sub(r"\s+", "", text).strip().lower()


BOOK_NO_TO_NAME: dict[int, str] = {idx + 1: name for idx, (name, _) in enumerate(BOOKS)}
BOOK_NO_TO_CHAPTERS: dict[int, int] = {
    idx + 1: chapter_count for idx, (_, chapter_count) in enumerate(BOOKS)
}
BOOK_NAME_TO_NO: dict[str, int] = {
    norm_book_name(name): no for no, name in BOOK_NO_TO_NAME.items()
}
for alias, no in KOR_ALIAS_TO_BOOK_NO.items():
    BOOK_NAME_TO_NO[norm_book_name(alias)] = no

BOOK_FILE_RE = re.compile(r"^\s*(\d{1,2})\s*.+\.txt\s*$", re.IGNORECASE)
VERSE_LINE_RE = re.compile(r"^\s*(\d+):(\d+)\s*(.*)\s*$")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate SQL for inserting KRV bible_verses data."
    )
    input_group = parser.add_mutually_exclusive_group(required=False)
    input_group.add_argument(
        "--input",
        help="Input file path (.csv, .tsv, .jsonl).",
    )
    input_group.add_argument(
        "--input-dir",
        help="Directory containing per-book txt files (example: assets/bible).",
    )
    parser.add_argument(
        "--output",
        default="supabase/seeds/krv_bible_verses.sql",
        help="Output SQL file path.",
    )
    parser.add_argument(
        "--input-format",
        choices=["auto", "csv", "tsv", "jsonl"],
        default="auto",
        help="Input format. auto detects by extension.",
    )
    parser.add_argument(
        "--translation",
        default="KRV",
        help="Default translation code when missing in source.",
    )
    parser.add_argument(
        "--batch-size",
        type=int,
        default=500,
        help="Rows per INSERT statement.",
    )
    parser.add_argument(
        "--truncate-translation",
        action="store_true",
        help="Delete existing rows for --translation before inserting.",
    )
    parser.add_argument(
        "--encoding",
        default="utf-8",
        help="CSV/TSV/JSONL input + output SQL encoding.",
    )
    parser.add_argument(
        "--book-text-encodings",
        default="cp949,euc-kr,utf-8",
        help="Comma-separated encodings for --input-dir txt files.",
    )
    return parser.parse_args()


def detect_format(path: Path, forced: str) -> str:
    if forced != "auto":
        return forced
    ext = path.suffix.lower()
    if ext == ".jsonl":
        return "jsonl"
    if ext == ".tsv":
        return "tsv"
    return "csv"


def pick_value(row: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = row.get(key)
        if value is None:
            continue
        text = str(value).strip()
        if text:
            return text
    return None


def parse_int(value: str, label: str, line_no: int) -> int:
    match = re.search(r"-?\d+", value.replace(",", ""))
    if match is None:
        raise ValueError(f"{line_no}행: {label} 값이 숫자가 아닙니다: {value!r}")
    return int(match.group(0))


def normalize_testament(raw: str | None, book_no: int) -> str:
    if raw:
        lowered = raw.strip().lower()
        if lowered in {"old", "ot", "구약"}:
            return "old"
        if lowered in {"new", "nt", "신약"}:
            return "new"
    return "old" if book_no <= 39 else "new"


@dataclass(frozen=True)
class VerseRow:
    translation: str
    testament: str
    book_no: int
    book_name: str
    chapter_no: int
    verse_no: int
    verse_text: str
    source_line_no: int


def to_verse_row(
    row: dict[str, Any],
    *,
    line_no: int,
    default_translation: str,
) -> VerseRow:
    raw_book_no = pick_value(row, "book_no", "bookNo", "book_number")
    raw_book_name = pick_value(row, "book_name", "book", "bookName")
    raw_chapter = pick_value(row, "chapter_no", "chapter", "chapterNo")
    raw_verse = pick_value(row, "verse_no", "verse", "verseNo")
    raw_text = pick_value(row, "verse_text", "text", "content")
    raw_translation = pick_value(row, "translation")
    raw_testament = pick_value(row, "testament")

    if raw_chapter is None or raw_verse is None or raw_text is None:
        raise ValueError(
            f"{line_no}행: chapter/verse/text 컬럼이 필요합니다. row={row}"
        )

    if raw_book_no is not None:
        book_no = parse_int(raw_book_no, "book_no", line_no)
    elif raw_book_name is not None:
        normalized = norm_book_name(raw_book_name)
        if normalized not in BOOK_NAME_TO_NO:
            raise ValueError(
                f"{line_no}행: 알 수 없는 book_name 입니다: {raw_book_name!r}"
            )
        book_no = BOOK_NAME_TO_NO[normalized]
    else:
        raise ValueError(f"{line_no}행: book_no 또는 book_name이 필요합니다.")

    if not (1 <= book_no <= 66):
        raise ValueError(f"{line_no}행: book_no 범위 오류: {book_no}")

    chapter_no = parse_int(raw_chapter, "chapter_no", line_no)
    verse_no = parse_int(raw_verse, "verse_no", line_no)
    if chapter_no <= 0:
        raise ValueError(f"{line_no}행: chapter_no는 1 이상이어야 합니다.")
    if verse_no <= 0:
        raise ValueError(f"{line_no}행: verse_no는 1 이상이어야 합니다.")

    max_chapter = BOOK_NO_TO_CHAPTERS[book_no]
    if chapter_no > max_chapter:
        raise ValueError(
            f"{line_no}행: chapter_no가 최대 장수를 초과합니다. "
            f"book_no={book_no}, chapter_no={chapter_no}, max={max_chapter}"
        )

    verse_text = raw_text.strip()
    if not verse_text:
        raise ValueError(f"{line_no}행: verse_text가 비어 있습니다.")

    translation = (raw_translation or default_translation).strip().upper()
    testament = normalize_testament(raw_testament, book_no)

    return VerseRow(
        translation=translation,
        testament=testament,
        book_no=book_no,
        book_name=BOOK_NO_TO_NAME[book_no],
        chapter_no=chapter_no,
        verse_no=verse_no,
        verse_text=verse_text,
        source_line_no=line_no,
    )


def read_csv_rows(path: Path, *, delimiter: str, encoding: str) -> list[dict[str, Any]]:
    with path.open("r", encoding=encoding, newline="") as f:
        reader = csv.DictReader(f, delimiter=delimiter)
        return [dict(row) for row in reader]


def read_jsonl_rows(path: Path, *, encoding: str) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    with path.open("r", encoding=encoding) as f:
        for idx, line in enumerate(f, start=1):
            text = line.strip()
            if not text:
                continue
            value = json.loads(text)
            if not isinstance(value, dict):
                raise ValueError(f"{idx}행: JSON object 형식이 아닙니다.")
            rows.append(value)
    return rows


def parse_book_no_from_filename(path: Path) -> int:
    match = BOOK_FILE_RE.match(path.name)
    if match is None:
        raise ValueError(f"책 번호를 파일명에서 찾을 수 없습니다: {path.name!r}")
    book_no = int(match.group(1))
    if not (1 <= book_no <= 66):
        raise ValueError(f"책 번호 범위 오류: {path.name!r}")
    return book_no


def read_text_with_fallback(path: Path, encodings: list[str]) -> str:
    last_error: Exception | None = None
    for encoding in encodings:
        try:
            return path.read_text(encoding=encoding)
        except Exception as exc:  # noqa: BLE001
            last_error = exc
    raise ValueError(
        f"파일 인코딩을 해석하지 못했습니다: {path} (tried={encodings})"
    ) from last_error


def parse_book_text_file(
    path: Path,
    *,
    book_no: int,
    default_translation: str,
    text_encodings: list[str],
) -> list[VerseRow]:
    text = read_text_with_fallback(path, text_encodings)
    lines = text.replace("\r\n", "\n").replace("\r", "\n").split("\n")
    rows: list[VerseRow] = []

    current: dict[str, str] | None = None
    current_line_no = 1
    canonical_book_name = BOOK_NO_TO_NAME[book_no]

    for line_no, raw in enumerate(lines, start=1):
        line = raw.replace("\ufeff", "").strip()
        if not line:
            continue

        # Skip title line (book name)
        if norm_book_name(line) == norm_book_name(canonical_book_name):
            continue

        verse_match = VERSE_LINE_RE.match(line)
        if verse_match is not None:
            if current is not None:
                rows.append(
                    to_verse_row(
                        current,
                        line_no=current_line_no,
                        default_translation=default_translation,
                    )
                )
            current = {
                "book_no": str(book_no),
                "chapter_no": verse_match.group(1),
                "verse_no": verse_match.group(2),
                "verse_text": verse_match.group(3).strip(),
                "translation": default_translation,
            }
            current_line_no = line_no
            continue

        # Wrapped line: append to previous verse.
        if current is None:
            continue
        if current["verse_text"]:
            current["verse_text"] = f"{current['verse_text']} {line}"
        else:
            current["verse_text"] = line

    if current is not None:
        rows.append(
            to_verse_row(
                current,
                line_no=current_line_no,
                default_translation=default_translation,
            )
        )

    return rows


def read_rows_from_book_dir(
    input_dir: Path,
    *,
    default_translation: str,
    text_encodings: list[str],
) -> tuple[list[VerseRow], int]:
    if not input_dir.exists():
        raise ValueError(f"입력 디렉토리가 없습니다: {input_dir}")
    if not input_dir.is_dir():
        raise ValueError(f"입력 경로가 디렉토리가 아닙니다: {input_dir}")

    txt_files = sorted(input_dir.glob("*.txt"), key=lambda p: p.name)
    if not txt_files:
        raise ValueError(f"txt 파일이 없습니다: {input_dir}")

    book_file_pairs: list[tuple[int, Path]] = []
    for path in txt_files:
        book_no = parse_book_no_from_filename(path)
        book_file_pairs.append((book_no, path))

    # Keep the first file for each book number in filename order.
    unique_pairs: dict[int, Path] = {}
    for book_no, path in book_file_pairs:
        unique_pairs.setdefault(book_no, path)

    parsed_rows: list[VerseRow] = []
    for book_no in sorted(unique_pairs.keys()):
        rows = parse_book_text_file(
            unique_pairs[book_no],
            book_no=book_no,
            default_translation=default_translation,
            text_encodings=text_encodings,
        )
        parsed_rows.extend(rows)

    return parsed_rows, len(unique_pairs)


T = TypeVar("T")


def chunked(items: list[T], size: int) -> list[list[T]]:
    return [items[i : i + size] for i in range(0, len(items), size)]


def sql_literal(value: str) -> str:
    escaped = value.replace("'", "''")
    return f"'{escaped}'"


def row_to_sql_values(row: VerseRow) -> str:
    return (
        f"({sql_literal(row.translation)}, {sql_literal(row.testament)}, "
        f"{row.book_no}, {sql_literal(row.book_name)}, {row.chapter_no}, "
        f"{row.verse_no}, {sql_literal(row.verse_text)})"
    )


def build_sql(
    rows: list[VerseRow],
    *,
    translation: str,
    truncate_translation: bool,
    batch_size: int,
) -> str:
    lines: list[str] = []
    lines.append("-- Generated by tools/build_krv_seed_sql.py")
    lines.append("-- Target table: public.bible_verses")
    lines.append("begin;")
    if truncate_translation:
        lines.append(
            f"delete from bible_verses where translation = {sql_literal(translation)};"
        )

    for batch in chunked(rows, batch_size):
        lines.append(
            "insert into bible_verses "
            "(translation, testament, book_no, book_name, chapter_no, verse_no, verse_text)"
        )
        lines.append("values")
        lines.append(",\n".join(row_to_sql_values(row) for row in batch))
        lines.append(
            "on conflict (translation, book_no, chapter_no, verse_no) do update set "
            "testament = excluded.testament, "
            "book_name = excluded.book_name, "
            "verse_text = excluded.verse_text;"
        )

    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    output_path = Path(args.output)
    translation = args.translation.upper()
    if args.batch_size <= 0:
        raise SystemExit("--batch-size는 1 이상이어야 합니다.")

    parsed_rows: list[VerseRow] = []
    raw_row_count = 0
    source_info = ""

    if args.input:
        input_path = Path(args.input)
        if not input_path.exists():
            raise SystemExit(f"입력 파일이 없습니다: {input_path}")

        input_format = detect_format(input_path, args.input_format)
        if input_format == "jsonl":
            raw_rows = read_jsonl_rows(input_path, encoding=args.encoding)
            line_offset = 1
        elif input_format == "tsv":
            raw_rows = read_csv_rows(input_path, delimiter="\t", encoding=args.encoding)
            line_offset = 2
        else:
            raw_rows = read_csv_rows(input_path, delimiter=",", encoding=args.encoding)
            line_offset = 2

        for idx, row in enumerate(raw_rows):
            source_line = idx + line_offset
            parsed_rows.append(
                to_verse_row(
                    row,
                    line_no=source_line,
                    default_translation=translation,
                )
            )
        raw_row_count = len(raw_rows)
        source_info = f"file:{input_path}"
    else:
        input_dir = Path(args.input_dir) if args.input_dir else Path("assets/bible")
        text_encodings = [
            encoding.strip()
            for encoding in args.book_text_encodings.split(",")
            if encoding.strip()
        ]
        if not text_encodings:
            raise SystemExit("--book-text-encodings 값이 비어 있습니다.")

        parsed_rows, used_files = read_rows_from_book_dir(
            input_dir,
            default_translation=translation,
            text_encodings=text_encodings,
        )
        raw_row_count = len(parsed_rows)
        source_info = f"dir:{input_dir} (books={used_files})"

    # Deduplicate by PK, keep last row when duplicated.
    dedup: dict[tuple[str, int, int, int], VerseRow] = {}
    for row in parsed_rows:
        key = (row.translation, row.book_no, row.chapter_no, row.verse_no)
        dedup[key] = row

    rows = sorted(
        dedup.values(),
        key=lambda r: (r.translation, r.book_no, r.chapter_no, r.verse_no),
    )

    sql_text = build_sql(
        rows,
        translation=translation,
        truncate_translation=args.truncate_translation,
        batch_size=args.batch_size,
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(sql_text, encoding=args.encoding)

    print(f"source           : {source_info}")
    print(f"input rows       : {raw_row_count}")
    print(f"deduped rows     : {len(rows)}")
    print(f"dropped duplicate: {raw_row_count - len(rows)}")
    print(f"translation      : {translation}")
    print(f"output           : {output_path}")
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
