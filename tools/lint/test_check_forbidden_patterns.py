"""Unit tests for tools/lint/check_forbidden_patterns.py."""

from __future__ import annotations

import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import check_forbidden_patterns as mod  # noqa: E402


class ForbiddenPatternTests(unittest.TestCase):
    def setUp(self) -> None:
        self._old_root = mod.REPO_ROOT
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        mod.REPO_ROOT = self.root

    def tearDown(self) -> None:
        mod.REPO_ROOT = self._old_root
        self.tmp.cleanup()

    def write(self, relative: str, text: str) -> Path:
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_blocks_supabase_access_token(self) -> None:
        token = "sbp_" + "1234567890abcdef1234567890abcdef12345678"
        path = self.write(
            ".cursor/mcp.json",
            f'{{"SUPABASE_ACCESS_TOKEN":"{token}"}}',
        )

        with redirect_stdout(StringIO()):
            errors, warnings = mod.check_file(path)

        self.assertEqual(errors, 1)
        self.assertEqual(warnings, 0)

    def test_blocks_dart_print_in_code(self) -> None:
        path = self.write("lib/probe.dart", "void main() {\n  print('nope');\n}\n")

        with redirect_stdout(StringIO()):
            errors, _ = mod.check_file(path)

        self.assertEqual(errors, 1)

    def test_allows_dart_print_in_comment(self) -> None:
        path = self.write("lib/probe.dart", "// print('example')\n")

        errors, warnings = mod.check_file(path)

        self.assertEqual(errors, 0)
        self.assertEqual(warnings, 0)

    def test_allows_flutterfire_client_api_key_file(self) -> None:
        api_key = "AIza" + "SyC7pyz5ZQ7GUnXQFezMUs_CZevYbYb7I0I"
        path = self.write(
            "lib/firebase_options.dart",
            f"const apiKey = '{api_key}';\n",
        )

        errors, warnings = mod.check_file(path)

        self.assertEqual(errors, 0)
        self.assertEqual(warnings, 0)

    def test_default_scan_includes_cursor_json(self) -> None:
        token = "sbp_" + "1234567890abcdef1234567890abcdef12345678"
        self.write(
            ".cursor/mcp.json",
            f'{{"SUPABASE_ACCESS_TOKEN":"{token}"}}',
        )

        targets = mod.files_to_check([])

        self.assertIn(self.root / ".cursor" / "mcp.json", targets)


if __name__ == "__main__":
    unittest.main()
