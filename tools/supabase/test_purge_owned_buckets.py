"""Unit tests for tools/supabase/purge_owned_buckets.py.

Run: python3 tools/supabase/test_purge_owned_buckets.py -v
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

import purge_owned_buckets as mod  # noqa: E402


class _FakeResponse:
    def __init__(
        self,
        status_code: int,
        *,
        body: Any = None,
        text: str = "",
    ) -> None:
        self.status_code = status_code
        self._body = body
        self.text = text
        self.ok = 200 <= status_code < 300

    def json(self) -> Any:
        if self._body is None:
            raise ValueError("no json")
        return self._body


class _FakeSession:
    def __init__(self, responses: list[_FakeResponse]) -> None:
        self.responses = responses
        self.calls: list[dict[str, Any]] = []

    def post(self, url: str, **kwargs: Any) -> _FakeResponse:
        self.calls.append({"method": "POST", "url": url, **kwargs})
        return self.responses.pop(0)

    def delete(self, url: str, **kwargs: Any) -> _FakeResponse:
        self.calls.append({"method": "DELETE", "url": url, **kwargs})
        return self.responses.pop(0)


class PurgeOwnedBucketsTests(unittest.TestCase):
    def test_purge_bucket_verifies_empty_after_bucket_empty(self) -> None:
        session = _FakeSession([
            _FakeResponse(200),
            _FakeResponse(200, body=[]),
        ])

        ok, message = mod.purge_bucket(
            session,
            "https://example.supabase.co",
            "characters",
        )

        self.assertTrue(ok)
        self.assertIn("verified empty", message)
        self.assertEqual([call["method"] for call in session.calls], ["POST", "POST"])

    def test_purge_bucket_deletes_objects_left_after_empty(self) -> None:
        session = _FakeSession([
            _FakeResponse(200),
            _FakeResponse(
                200,
                body=[
                    {"id": None, "name": "nested"},
                    {"id": "file-1", "name": "aaron.png"},
                ],
            ),
            _FakeResponse(
                200,
                body=[{"id": "file-2", "name": "moses.png"}],
            ),
            _FakeResponse(200),
            _FakeResponse(200),
            _FakeResponse(200, body=[]),
        ])

        ok, message = mod.purge_bucket(
            session,
            "https://example.supabase.co",
            "characters",
        )

        self.assertTrue(ok)
        self.assertIn("deleted 2 leftover objects", message)
        delete_urls = [
            call["url"] for call in session.calls if call["method"] == "DELETE"
        ]
        self.assertEqual(
            delete_urls,
            [
                "https://example.supabase.co/storage/v1/object/characters/nested/moses.png",
                "https://example.supabase.co/storage/v1/object/characters/aaron.png",
            ],
        )

    def test_purge_bucket_treats_object_not_found_delete_as_success(self) -> None:
        session = _FakeSession([
            _FakeResponse(200),
            _FakeResponse(200, body=[{"id": "file-1", "name": "agrippa.png"}]),
            _FakeResponse(
                400,
                body={
                    "statusCode": "404",
                    "error": "not_found",
                    "message": "Object not found",
                },
                text=(
                    '{"statusCode":"404","error":"not_found",'
                    '"message":"Object not found"}'
                ),
            ),
            _FakeResponse(200, body=[]),
        ])

        ok, message = mod.purge_bucket(
            session,
            "https://example.supabase.co",
            "characters",
        )

        self.assertTrue(ok)
        self.assertIn("deleted 1 leftover objects", message)

    def test_purge_bucket_reports_failure_if_objects_remain(self) -> None:
        session = _FakeSession([
            _FakeResponse(200),
            _FakeResponse(200, body=[{"id": "file-1", "name": "aaron.png"}]),
            _FakeResponse(200),
            _FakeResponse(200, body=[{"id": "file-1", "name": "aaron.png"}]),
        ])

        ok, message = mod.purge_bucket(
            session,
            "https://example.supabase.co",
            "characters",
        )

        self.assertFalse(ok)
        self.assertIn("still remain", message)


if __name__ == "__main__":
    unittest.main()
