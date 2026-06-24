#!/usr/bin/env python3
"""Sync original story scene PNGs with a private release-source bucket.

The app bundles `assets/story_images_thumbs/`, but `make thumbnails` needs the
large original PNGs under `assets/story_images/`. This tool treats that local
directory as a cache and `story-image-sources` as the release-only source of
truth.

Usage:
    python3 tools/supabase/sync_story_image_sources.py pull --env prod
    python3 tools/supabase/sync_story_image_sources.py push --env prod
    python3 tools/supabase/sync_story_image_sources.py push --env prod --dry-run
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from dataclasses import asdict, dataclass
from pathlib import Path
import sys
import time
from typing import Any
import unicodedata
from urllib.parse import quote

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv(".env.ops")
except ImportError:
    pass


REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "tools" / "images"))

from generate_runtime_thumbnails import load_story_thumb_index  # noqa: E402

DEFAULT_BUCKET = "story-image-sources"
DEFAULT_MANIFEST_PATH = "_manifests/story_images_manifest.json"
DEFAULT_OBJECT_PREFIX = "story_images"
DEFAULT_STORIES_DIR = REPO_ROOT / "assets" / "200_stories"
DEFAULT_SOURCE_DIR = REPO_ROOT / "assets" / "story_images"
RETRYABLE_STATUS_CODES = {408, 429, 500, 502, 503, 504}


@dataclass(frozen=True)
class StoryItem:
    title: str
    era: str
    story_index: int
    source_dir: str


@dataclass(frozen=True)
class SourceEntry:
    object_path: str
    source_dir: str
    filename: str
    title: str
    era: str
    story_index: int
    size: int
    sha256: str
    local_path: str | None = None


@dataclass(frozen=True)
class PushPlan:
    upload: list[SourceEntry]
    skip: list[SourceEntry]


@dataclass(frozen=True)
class PullPlan:
    download: list[SourceEntry]
    skip: list[SourceEntry]
    keep_local: list[SourceEntry]
    missing_remote: list[StoryItem]


def env_var(name: str, env_suffix: str) -> str | None:
    return os.environ.get(f"{name}_{env_suffix.upper()}") or os.environ.get(name)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def object_path_for(
    *,
    object_prefix: str,
    source_dir: str,
    filename: str,
) -> str:
    prefix = object_prefix.strip("/")
    parts = [source_key_for(source_dir), filename]
    if prefix:
        parts.insert(0, prefix)
    return "/".join(parts)


def source_key_for(source_dir: str) -> str:
    normalized = unicodedata.normalize("NFC", source_dir)
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()[:16]


def load_story_items(stories_dir: Path) -> list[StoryItem]:
    _, payload = load_story_thumb_index(stories_dir)
    items: list[StoryItem] = []
    for item in payload.get("items", []):
        if not isinstance(item, dict):
            continue
        source_dir = str(item.get("source_dir") or "").strip()
        title = str(item.get("title") or "").strip()
        if not source_dir or not title:
            continue
        items.append(
            StoryItem(
                title=title,
                era=str(item.get("era") or ""),
                story_index=int(item.get("story_index") or 0),
                source_dir=source_dir,
            )
        )
    return items


def collect_local_entries(
    *,
    story_items: list[StoryItem],
    source_root: Path,
    object_prefix: str,
) -> list[SourceEntry]:
    entries: list[SourceEntry] = []
    for item in story_items:
        story_dir = source_root / item.source_dir
        if not story_dir.is_dir():
            continue
        for path in sorted(story_dir.glob("scene_*.png")):
            if not path.is_file():
                continue
            entries.append(
                SourceEntry(
                    object_path=object_path_for(
                        object_prefix=object_prefix,
                        source_dir=item.source_dir,
                        filename=path.name,
                    ),
                    source_dir=item.source_dir,
                    filename=path.name,
                    title=item.title,
                    era=item.era,
                    story_index=item.story_index,
                    size=path.stat().st_size,
                    sha256=sha256_file(path),
                    local_path=repo_relative_or_absolute(path),
                )
            )
    return entries


def repo_relative_or_absolute(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT))
    except ValueError:
        return str(path)


def has_any_local_scene(source_root: Path, source_dir: str) -> bool:
    story_dir = source_root / source_dir
    return story_dir.is_dir() and any(story_dir.glob("scene_*.png"))


def build_manifest(
    *,
    entries: list[SourceEntry],
    bucket: str,
    object_prefix: str,
) -> dict[str, Any]:
    return {
        "version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
        "bucket": bucket,
        "object_prefix": object_prefix.strip("/"),
        "entries": [
            {key: value for key, value in asdict(entry).items() if key != "local_path"}
            for entry in sorted(entries, key=lambda item: item.object_path)
        ],
    }


def entries_from_manifest(payload: dict[str, Any] | None) -> dict[str, SourceEntry]:
    if not payload:
        return {}
    out: dict[str, SourceEntry] = {}
    for raw in payload.get("entries", []):
        if not isinstance(raw, dict):
            continue
        object_path = str(raw.get("object_path") or "").strip()
        if not object_path:
            continue
        out[object_path] = SourceEntry(
            object_path=object_path,
            source_dir=str(raw.get("source_dir") or ""),
            filename=str(raw.get("filename") or Path(object_path).name),
            title=str(raw.get("title") or ""),
            era=str(raw.get("era") or ""),
            story_index=int(raw.get("story_index") or 0),
            size=int(raw.get("size") or 0),
            sha256=str(raw.get("sha256") or ""),
            local_path=None,
        )
    return out


def plan_push(
    *,
    local_entries: list[SourceEntry],
    remote_entries: dict[str, SourceEntry],
) -> PushPlan:
    upload: list[SourceEntry] = []
    skip: list[SourceEntry] = []
    for entry in local_entries:
        remote = remote_entries.get(entry.object_path)
        if (
            remote is not None
            and remote.sha256 == entry.sha256
            and remote.size == entry.size
        ):
            skip.append(entry)
        else:
            upload.append(entry)
    return PushPlan(upload=upload, skip=skip)


def plan_pull(
    *,
    story_items: list[StoryItem],
    local_entries: dict[str, SourceEntry],
    remote_entries: dict[str, SourceEntry],
    source_root: Path,
) -> PullPlan:
    active_source_dirs = {item.source_dir for item in story_items}
    remote_active = {
        key: entry
        for key, entry in remote_entries.items()
        if entry.source_dir in active_source_dirs
    }
    download: list[SourceEntry] = []
    skip: list[SourceEntry] = []
    for object_path, remote in sorted(remote_active.items()):
        local = local_entries.get(object_path)
        if (
            local is not None
            and local.sha256 == remote.sha256
            and local.size == remote.size
        ):
            skip.append(local)
        else:
            download.append(remote)

    remote_source_dirs = {entry.source_dir for entry in remote_active.values()}
    missing_remote = [
        item
        for item in story_items
        if not has_any_local_scene(source_root, item.source_dir)
        and item.source_dir not in remote_source_dirs
    ]
    keep_local = [
        entry
        for entry in local_entries.values()
        if entry.source_dir in active_source_dirs
        and entry.object_path not in remote_active
    ]
    return PullPlan(
        download=download,
        skip=skip,
        keep_local=keep_local,
        missing_remote=missing_remote,
    )


def request_with_retries(
    session: requests.Session,
    method: str,
    url: str,
    *,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
    **kwargs: Any,
) -> requests.Response:
    attempts = max(1, retry_attempts)
    for attempt in range(1, attempts + 1):
        try:
            response = session.request(method, url, timeout=timeout_sec, **kwargs)
        except requests.exceptions.RequestException as exc:
            if attempt >= attempts:
                raise
            print(
                f"  [retry] {method} {url} failed on attempt "
                f"{attempt}/{attempts}: {exc}",
                file=sys.stderr,
            )
            time.sleep(retry_wait_sec)
            continue

        if response.status_code in RETRYABLE_STATUS_CODES and attempt < attempts:
            print(
                f"  [retry] {method} {url} returned {response.status_code} "
                f"on attempt {attempt}/{attempts}",
                file=sys.stderr,
            )
            time.sleep(retry_wait_sec)
            continue
        return response
    raise AssertionError("unreachable retry state")


def is_not_found_body(response: requests.Response, expected: str) -> bool:
    try:
        body = response.json()
    except ValueError:
        return False
    if not isinstance(body, dict):
        return False
    return (
        str(body.get("statusCode", "")) == "404"
        and expected in str(body.get("message", body.get("error", ""))).lower()
    )


def is_duplicate_body(response: requests.Response) -> bool:
    try:
        body = response.json()
    except ValueError:
        return False
    if not isinstance(body, dict):
        return False
    message = str(body.get("message", "")).lower()
    return (
        str(body.get("statusCode", "")) == "409"
        or str(body.get("error", "")).lower() == "duplicate"
        or "already exists" in message
        or "duplicate" in message
    )


def ensure_bucket(
    *,
    session: requests.Session,
    base_url: str,
    bucket: str,
    dry_run: bool,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
) -> None:
    url = f"{base_url.rstrip('/')}/storage/v1/bucket/{bucket}"
    response = request_with_retries(
        session,
        "GET",
        url,
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
    )
    if response.ok:
        return
    if response.status_code not in (400, 404) and not is_not_found_body(
        response, "bucket not found"
    ):
        raise RuntimeError(
            f"bucket lookup failed for {bucket}: "
            f"{response.status_code} {response.text[:200]}"
        )
    if dry_run:
        print(f"  [dry-run] would create private bucket: {bucket}")
        return
    create_url = f"{base_url.rstrip('/')}/storage/v1/bucket"
    create = request_with_retries(
        session,
        "POST",
        create_url,
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
        json={
            "id": bucket,
            "name": bucket,
            "public": False,
            "file_size_limit": 20 * 1024 * 1024,
            "allowed_mime_types": ["image/png", "application/json"],
        },
    )
    if create.status_code in (200, 201) or is_duplicate_body(create):
        print(f"  [bucket] ensured private bucket: {bucket}")
        return
    raise RuntimeError(
        f"bucket create failed for {bucket}: "
        f"{create.status_code} {create.text[:200]}"
    )


def download_object(
    *,
    session: requests.Session,
    base_url: str,
    bucket: str,
    object_path: str,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
) -> bytes | None:
    encoded_path = quote(object_path, safe="/")
    response = request_with_retries(
        session,
        "GET",
        f"{base_url.rstrip('/')}/storage/v1/object/{bucket}/{encoded_path}",
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
    )
    if response.status_code in (400, 404) and is_not_found_body(
        response, "object not found"
    ):
        return None
    if response.status_code in (400, 404) and is_not_found_body(
        response, "bucket not found"
    ):
        return None
    if response.status_code == 404:
        return None
    if not response.ok:
        raise RuntimeError(
            f"download failed for {bucket}/{object_path}: "
            f"{response.status_code} {response.text[:200]}"
        )
    return response.content


def load_remote_manifest(
    *,
    session: requests.Session,
    base_url: str,
    bucket: str,
    manifest_path: str,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
) -> dict[str, Any] | None:
    data = download_object(
        session=session,
        base_url=base_url,
        bucket=bucket,
        object_path=manifest_path,
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
    )
    if data is None:
        return None
    return json.loads(data.decode("utf-8"))


def upload_object(
    *,
    session: requests.Session,
    base_url: str,
    bucket: str,
    object_path: str,
    data: bytes,
    content_type: str,
    dry_run: bool,
    timeout_sec: int,
    retry_attempts: int,
    retry_wait_sec: float,
) -> None:
    if dry_run:
        print(f"  [dry-run] upload {bucket}/{object_path} ({len(data)} bytes)")
        return
    encoded_path = quote(object_path, safe="/")
    response = request_with_retries(
        session,
        "POST",
        f"{base_url.rstrip('/')}/storage/v1/object/{bucket}/{encoded_path}",
        timeout_sec=timeout_sec,
        retry_attempts=retry_attempts,
        retry_wait_sec=retry_wait_sec,
        data=data,
        headers={
            "Content-Type": content_type,
            "x-upsert": "true",
            "cache-control": "3600",
        },
    )
    if not response.ok and not is_duplicate_body(response):
        raise RuntimeError(
            f"upload failed for {bucket}/{object_path}: "
            f"{response.status_code} {response.text[:200]}"
        )


def write_downloaded_entry(
    *,
    entry: SourceEntry,
    source_root: Path,
    data: bytes,
) -> Path:
    digest = hashlib.sha256(data).hexdigest()
    if entry.sha256 and digest != entry.sha256:
        raise RuntimeError(
            f"sha256 mismatch for {entry.object_path}: "
            f"expected {entry.sha256}, got {digest}"
        )
    dst = source_root / entry.source_dir / entry.filename
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(data)
    return dst


def command_pull(args: argparse.Namespace) -> int:
    story_items = load_story_items(args.stories_dir)
    local_entries = {
        entry.object_path: entry
        for entry in collect_local_entries(
            story_items=story_items,
            source_root=args.source_dir,
            object_prefix=args.object_prefix,
        )
    }

    session = make_session(args)
    remote_payload = None
    if session is not None:
        remote_payload = load_remote_manifest(
            session=session,
            base_url=args.base_url,
            bucket=args.bucket,
            manifest_path=args.manifest_path,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
    remote_entries = entries_from_manifest(remote_payload)

    if remote_payload is None:
        missing_local = [
            item
            for item in story_items
            if not has_any_local_scene(args.source_dir, item.source_dir)
        ]
        if missing_local:
            print(
                "ERROR: remote story image source manifest is missing, and "
                f"{len(missing_local)} local story source dir(s) are missing.",
                file=sys.stderr,
            )
            print("Run upload-story-image-sources from a machine with originals.")
            for item in missing_local[:20]:
                print(
                    f"  - {item.era} #{item.story_index}: {item.title}",
                    file=sys.stderr,
                )
            return 1
        print(
            "Remote manifest is missing, but local story image sources are complete. "
            "Continuing; upload-story-image-sources can seed the bucket."
        )
        return 0

    plan = plan_pull(
        story_items=story_items,
        local_entries=local_entries,
        remote_entries=remote_entries,
        source_root=args.source_dir,
    )
    print(
        f"Pull plan: download={len(plan.download)}, skip={len(plan.skip)}, "
        f"keep_local={len(plan.keep_local)}, "
        f"missing_remote={len(plan.missing_remote)}"
    )
    if plan.missing_remote:
        for item in plan.missing_remote[:20]:
            print(
                f"  [missing remote] {item.era} #{item.story_index}: {item.title}",
                file=sys.stderr,
            )
        return 1

    for entry in plan.download:
        print(f"  [download] {entry.object_path}")
        if args.dry_run:
            continue
        if session is None:
            raise RuntimeError("session unexpectedly missing")
        data = download_object(
            session=session,
            base_url=args.base_url,
            bucket=args.bucket,
            object_path=entry.object_path,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
        if data is None:
            raise RuntimeError(f"remote object disappeared: {entry.object_path}")
        dst = write_downloaded_entry(
            entry=entry,
            source_root=args.source_dir,
            data=data,
        )
        print(f"    -> {dst.relative_to(REPO_ROOT)}")
    return 0


def command_push(args: argparse.Namespace) -> int:
    story_items = load_story_items(args.stories_dir)
    local_entries = collect_local_entries(
        story_items=story_items,
        source_root=args.source_dir,
        object_prefix=args.object_prefix,
    )
    missing_local = [
        item
        for item in story_items
        if not has_any_local_scene(args.source_dir, item.source_dir)
    ]
    if missing_local:
        print(
            f"ERROR: {len(missing_local)} active story source dir(s) are missing; "
            "refusing to publish an incomplete source manifest.",
            file=sys.stderr,
        )
        for item in missing_local[:20]:
            print(
                f"  - {item.era} #{item.story_index}: {item.title}",
                file=sys.stderr,
            )
        return 1

    session = make_session(args)
    if session is not None:
        ensure_bucket(
            session=session,
            base_url=args.base_url,
            bucket=args.bucket,
            dry_run=args.dry_run,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
        remote_payload = load_remote_manifest(
            session=session,
            base_url=args.base_url,
            bucket=args.bucket,
            manifest_path=args.manifest_path,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
    else:
        remote_payload = None
    remote_entries = entries_from_manifest(remote_payload)
    plan = plan_push(local_entries=local_entries, remote_entries=remote_entries)
    print(
        f"Push plan: upload={len(plan.upload)}, skip={len(plan.skip)}, "
        f"manifest_entries={len(local_entries)}"
    )

    if session is None and not args.dry_run:
        print("ERROR: service role session is required for push.", file=sys.stderr)
        return 2

    for entry in plan.upload:
        src = REPO_ROOT / (entry.local_path or "")
        print(f"  [upload] {repo_relative_or_absolute(src)} -> {entry.object_path}")
        if args.dry_run:
            continue
        if session is None:
            raise RuntimeError("session unexpectedly missing")
        upload_object(
            session=session,
            base_url=args.base_url,
            bucket=args.bucket,
            object_path=entry.object_path,
            data=src.read_bytes(),
            content_type="image/png",
            dry_run=False,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )

    manifest = build_manifest(
        entries=local_entries,
        bucket=args.bucket,
        object_prefix=args.object_prefix,
    )
    manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode(
        "utf-8"
    )
    if args.dry_run:
        print(
            f"  [dry-run] upload manifest {args.bucket}/{args.manifest_path} "
            f"({len(manifest_bytes)} bytes)"
        )
    elif session is not None:
        upload_object(
            session=session,
            base_url=args.base_url,
            bucket=args.bucket,
            object_path=args.manifest_path,
            data=manifest_bytes,
            content_type="application/json",
            dry_run=False,
            timeout_sec=args.timeout_sec,
            retry_attempts=args.retry_attempts,
            retry_wait_sec=args.retry_wait_sec,
        )
        print(f"  [manifest] {args.bucket}/{args.manifest_path}")
    return 0


def make_session(args: argparse.Namespace) -> requests.Session | None:
    service_key = env_var("SUPABASE_SERVICE_ROLE_KEY", args.env)
    if not args.base_url:
        print(
            f"ERROR: SUPABASE_URL_{args.env.upper()} (or SUPABASE_URL) not set",
            file=sys.stderr,
        )
        raise SystemExit(2)
    if not service_key:
        if args.dry_run and args.command == "push":
            print("No service role key; push dry-run will assume remote is empty.")
            return None
        print(
            f"ERROR: SUPABASE_SERVICE_ROLE_KEY_{args.env.upper()} not set",
            file=sys.stderr,
        )
        raise SystemExit(2)
    session = requests.Session()
    session.headers.update(
        {
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
        }
    )
    return session


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Sync original story scene PNGs with private Storage."
    )
    subparsers = parser.add_subparsers(dest="command", required=True)
    for name in ("pull", "push"):
        sub = subparsers.add_parser(name)
        sub.add_argument("--env", default="dev", choices=["dev", "prod"])
        sub.add_argument(
            "--bucket",
            default=os.environ.get("STORY_IMAGE_SOURCE_BUCKET", DEFAULT_BUCKET),
        )
        sub.add_argument("--stories-dir", type=Path, default=DEFAULT_STORIES_DIR)
        sub.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE_DIR)
        sub.add_argument("--object-prefix", default=DEFAULT_OBJECT_PREFIX)
        sub.add_argument("--manifest-path", default=DEFAULT_MANIFEST_PATH)
        sub.add_argument("--dry-run", action="store_true")
        sub.add_argument("--timeout-sec", type=int, default=120)
        sub.add_argument("--retry-attempts", type=int, default=3)
        sub.add_argument("--retry-wait-sec", type=float, default=3.0)
    return parser


def normalize_args(args: argparse.Namespace) -> argparse.Namespace:
    args.base_url = env_var("SUPABASE_URL", args.env)
    args.stories_dir = args.stories_dir.resolve()
    args.source_dir = args.source_dir.resolve()
    if args.timeout_sec <= 0:
        raise SystemExit("ERROR: --timeout-sec must be greater than 0")
    if args.retry_attempts <= 0:
        raise SystemExit("ERROR: --retry-attempts must be greater than 0")
    if args.retry_wait_sec < 0:
        raise SystemExit("ERROR: --retry-wait-sec must be 0 or greater")
    return args


def main() -> int:
    args = normalize_args(build_parser().parse_args())
    if args.command == "pull":
        return command_pull(args)
    if args.command == "push":
        return command_push(args)
    raise AssertionError(f"unknown command {args.command}")


if __name__ == "__main__":
    sys.exit(main())
