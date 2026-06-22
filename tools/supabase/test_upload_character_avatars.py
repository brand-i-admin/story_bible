"""Unit tests for tools/supabase/upload_character_avatars.py.

Run: python3 tools/supabase/test_upload_character_avatars.py -v
"""

from __future__ import annotations

import sys
import tempfile
import unittest
import os
from pathlib import Path
from typing import Any

import requests

sys.path.insert(0, str(Path(__file__).resolve().parent))

import upload_character_avatars as mod  # noqa: E402


class _FakeResponse:
    def __init__(
        self,
        status_code: int,
        *,
        body: dict[str, Any] | None = None,
        text: str = "",
    ) -> None:
        self.status_code = status_code
        self._body = body
        self.text = text
        self.ok = 200 <= status_code < 300

    def json(self) -> dict[str, Any]:
        if self._body is None:
            raise ValueError("no json")
        return self._body


class _FakeSession:
    def __init__(self, responses: list[_FakeResponse | Exception]) -> None:
        self.responses = responses
        self.calls: list[dict[str, Any]] = []
        self.headers: dict[str, str] = {}

    def request(self, method: str, url: str, **kwargs: Any) -> _FakeResponse:
        self.calls.append({"method": method, "url": url, **kwargs})
        response = self.responses.pop(0)
        if isinstance(response, Exception):
            raise response
        return response


class UploadCharacterAvatarsTests(unittest.TestCase):
    def test_upload_one_returns_uploaded_for_success(self) -> None:
        session = _FakeSession([_FakeResponse(200)])

        status = mod.upload_one(
            session=session,
            base_url="https://example.supabase.co",
            bucket="characters",
            storage_path="abraham.png",
            png_bytes=b"png",
            overwrite=False,
            timeout_sec=5,
            retry_attempts=1,
            retry_wait_sec=0,
        )

        self.assertEqual(status, "uploaded")
        self.assertEqual(session.calls[0]["method"], "POST")
        self.assertEqual(session.calls[0]["timeout"], 5)

    def test_upload_one_treats_duplicate_as_existing_skip(self) -> None:
        session = _FakeSession(
            [
                _FakeResponse(
                    400,
                    body={"statusCode": "409", "error": "Duplicate"},
                    text="duplicate",
                )
            ]
        )

        status = mod.upload_one(
            session=session,
            base_url="https://example.supabase.co",
            bucket="characters",
            storage_path="abraham.png",
            png_bytes=b"png",
            overwrite=False,
            timeout_sec=5,
            retry_attempts=1,
            retry_wait_sec=0,
        )

        self.assertEqual(status, "skipped_existing")

    def test_upload_one_recovers_when_timeout_retry_finds_duplicate(self) -> None:
        session = _FakeSession(
            [
                requests.exceptions.ReadTimeout("slow upload"),
                _FakeResponse(
                    400,
                    body={"statusCode": "409", "error": "Duplicate"},
                    text="duplicate",
                ),
            ]
        )

        status = mod.upload_one(
            session=session,
            base_url="https://example.supabase.co",
            bucket="characters",
            storage_path="abraham.png",
            png_bytes=b"png",
            overwrite=False,
            timeout_sec=5,
            retry_attempts=2,
            retry_wait_sec=0,
        )

        self.assertEqual(status, "skipped_existing")
        self.assertEqual(len(session.calls), 2)

    def test_update_avatar_path_rpc_retries_transient_status(self) -> None:
        session = _FakeSession([_FakeResponse(503), _FakeResponse(204)])

        mod.update_avatar_path_rpc(
            session=session,
            base_url="https://example.supabase.co",
            code="abraham",
            path="abraham.png",
            timeout_sec=5,
            retry_attempts=2,
            retry_wait_sec=0,
        )

        self.assertEqual(
            [call["method"] for call in session.calls],
            ["PATCH", "PATCH"],
        )

    def test_main_fails_fast_on_existing_when_flag_is_set(self) -> None:
        original_session = mod.requests.Session
        original_argv = sys.argv
        original_url = os.environ.get("SUPABASE_URL_DEV")
        original_key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY_DEV")
        with tempfile.TemporaryDirectory() as tmp_dir:
            avatar_path = Path(tmp_dir) / "abraham.png"
            avatar_path.write_bytes(b"png")
            session = _FakeSession(
                [
                    _FakeResponse(
                        400,
                        body={"statusCode": "409", "error": "Duplicate"},
                        text="duplicate",
                    )
                ]
            )
            mod.requests.Session = lambda: session
            sys.argv = [
                "upload_character_avatars.py",
                "--env",
                "dev",
                "--avatars-dir",
                tmp_dir,
                "--fail-on-existing",
            ]
            os.environ["SUPABASE_URL_DEV"] = "https://example.supabase.co"
            os.environ["SUPABASE_SERVICE_ROLE_KEY_DEV"] = "service-role"
            try:
                exit_code = mod.main()
            finally:
                mod.requests.Session = original_session
                sys.argv = original_argv
                if original_url is None:
                    os.environ.pop("SUPABASE_URL_DEV", None)
                else:
                    os.environ["SUPABASE_URL_DEV"] = original_url
                if original_key is None:
                    os.environ.pop("SUPABASE_SERVICE_ROLE_KEY_DEV", None)
                else:
                    os.environ["SUPABASE_SERVICE_ROLE_KEY_DEV"] = original_key

        self.assertEqual(exit_code, 1)
        self.assertEqual([call["method"] for call in session.calls], ["POST"])


if __name__ == "__main__":
    unittest.main()
