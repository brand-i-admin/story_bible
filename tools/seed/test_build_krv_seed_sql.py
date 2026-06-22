"""Unit tests for tools/seed/build_krv_seed_sql.py.

Run: python3 tools/seed/test_build_krv_seed_sql.py -v
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import build_krv_seed_sql as mod  # noqa: E402


class ParseBookTextFileTests(unittest.TestCase):
    def _parse_text(self, text: str) -> list[mod.VerseRow]:
        with tempfile.TemporaryDirectory() as tmp_dir:
            path = Path(tmp_dir) / "44 사도행전.txt"
            path.write_text(text, encoding="utf-8")
            return mod.parse_book_text_file(
                path,
                book_no=44,
                default_translation="KRV",
                text_encodings=["utf-8"],
            )

    def test_word_wrapped_inside_korean_word_is_joined_without_space(self) -> None:
        rows = self._parse_text(
            "사도행전\n"
            "1:3 해 받으신 후에 또한 저희에게 보\n"
            "이시며 하나님 나라의 일을 말씀하시니라\n"
        )

        self.assertEqual(len(rows), 1)
        self.assertEqual(
            rows[0].verse_text,
            "해 받으신 후에 또한 저희에게 보이시며 하나님 나라의 일을 말씀하시니라",
        )

    def test_wrapped_line_preserves_source_trailing_space(self) -> None:
        rows = self._parse_text(
            "사도행전\n"
            "1:12 이 산은 예루살렘에서 가까와 안식일에 \n"
            "가기 알맞은 길이라\n"
        )

        self.assertEqual(len(rows), 1)
        self.assertEqual(
            rows[0].verse_text,
            "이 산은 예루살렘에서 가까와 안식일에 가기 알맞은 길이라",
        )


if __name__ == "__main__":
    unittest.main()
