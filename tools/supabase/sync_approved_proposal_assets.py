#!/usr/bin/env python3
"""Download approved proposal assets (scene images + new character avatars)
to the local `assets/` tree, then clean up source buckets.

After an admin approves a proposal via `approve_event_proposal` RPC:
  - event_proposals.status = 'approved', approved_event_id set.
  - characters rows for `proposed_characters` get avatar_storage_path =
    'proposal-characters/<uid>/<draft>/<code>.png' (still in proposal bucket).
  - scene_image_paths still point to 'proposal-scenes/<uid>/<draft>/scene_<n>.png'.

This script (run by an operator after approval is done) performs the final
"freeze & migrate to canonical assets":

  1. Query approved proposals where `synced_to_local_at IS NULL`
     (i.e., not yet synced to local). `--all` overrides to re-sync everything.
  2. For each approved proposal:
       a. Download each proposal-scenes/*.png to
          `assets/story_images/{title}/scene_{i}.png` (for Vertex output
          parity with generate-story-images output).
       b. Download each proposal-characters/*.png to
          `assets/avatars/{code}.png`.
       c. Re-upload the PNGs to the `characters/` bucket with clean path
          `{code}.png` and update characters.avatar_storage_path = '{code}.png'.
       d. PATCH event_proposals.synced_to_local_at = now() so subsequent
          runs skip this proposal (idempotency).
       e. (Optional) delete source proposal-* objects.

After running, the operator proceeds with the regular content pipeline:
    make thumbnails                   # makes runtime thumbnails
    make build-character-meta         # if character_meta.json needs new entry
    make seed-stories-characters      # regenerate SQL
    make apply-seeds-stories-characters  # push to DB
    ...then rebuild + release the app.

Usage:
    python3 tools/supabase/sync_approved_proposal_assets.py --env dev [--dry-run]
                                                             [--all]
                                                             [--delete-source]

  --all            : 재sync — 이미 synced_to_local_at 가 세팅된 것도 다시 처리
                     (예: 로컬 assets 날리고 통째로 다시 내려받을 때)
  --dry-run        : 실제 파일/DB 수정 없이 대상 목록만 출력
  --delete-source  : 동기화 후 proposal-* 버킷의 원본 파일 삭제
                     ⚠️ 앱 배포 전엔 위험 — `하이브리드 로딩 fallback 이 깨짐`

Env vars required (.env):
    SUPABASE_URL_{ENV}
    SUPABASE_SERVICE_ROLE_KEY_{ENV}
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
except ImportError:
    pass


REPO_ROOT = Path(__file__).resolve().parents[2]
AVATARS_DIR = REPO_ROOT / "assets" / "avatars"
STORIES_IMG_DIR = REPO_ROOT / "assets" / "story_images"

AVATAR_BUCKET = "characters"
PROPOSAL_SCENES_BUCKET = "proposal-scenes"
PROPOSAL_CHARS_BUCKET = "proposal-characters"


def env_var(name: str, env_suffix: str) -> str | None:
    return (
        os.environ.get(f"{name}_{env_suffix.upper()}")
        or os.environ.get(name)
    )


def safe_dirname(title: str) -> str:
    """Convert a proposal title to a filesystem-safe directory name.

    Consistent with how `generate_event_story_images_vertex.py` names the
    `assets/story_images/<title>/` directory for production events.
    """
    cleaned = re.sub(r"\s+", " ", title.strip())
    # Keep hangul, latin, digits, spaces, hyphens, underscores; replace rest.
    keep = re.compile(r"[^\w가-힣 \-]+", re.UNICODE)
    out = keep.sub("", cleaned)
    return out.replace(" ", "_") or "untitled"


def sb_get(session: requests.Session, url: str, **kw) -> requests.Response:
    r = session.get(url, timeout=60, **kw)
    if not r.ok:
        raise RuntimeError(f"GET {url} failed: {r.status_code} {r.text}")
    return r


def sb_post(session: requests.Session, url: str, **kw) -> requests.Response:
    r = session.post(url, timeout=60, **kw)
    if not r.ok:
        raise RuntimeError(f"POST {url} failed: {r.status_code} {r.text}")
    return r


def sb_delete(session: requests.Session, url: str, **kw) -> None:
    r = session.delete(url, timeout=30, **kw)
    if not r.ok and r.status_code != 404:
        raise RuntimeError(f"DELETE {url} failed: {r.status_code} {r.text}")


def fetch_approved_proposals(
    session: requests.Session,
    base_url: str,
    *,
    include_already_synced: bool = False,
) -> list[dict]:
    """Fetch approved proposals ready to sync.

    Default: only rows with `synced_to_local_at IS NULL` — idempotent.
    `--all` on CLI sets include_already_synced=True to force re-sync of
    previously-synced proposals (useful when local assets got wiped).
    """
    url = f"{base_url}/rest/v1/event_proposals"
    params: dict[str, str] = {
        "select": (
            "id,title,character_codes,scene_image_paths,scene_image_prompts,"
            "proposed_characters,approved_event_id,status,synced_to_local_at"
        ),
        "status": "eq.approved",
    }
    if not include_already_synced:
        # PostgREST 연산자: `is.null` 은 `synced_to_local_at IS NULL`.
        params["synced_to_local_at"] = "is.null"
    r = sb_get(session, url, params=params)
    return r.json()


def patch_proposal_synced(
    session: requests.Session,
    base_url: str,
    proposal_id: str,
) -> None:
    """sync 완료 마커 세팅. 실패해도 치명적이진 않음(다음 run 에서 중복 처리)."""
    url = f"{base_url}/rest/v1/event_proposals"
    r = session.patch(
        url,
        params={"id": f"eq.{proposal_id}"},
        json={"synced_to_local_at": "now()"},
        timeout=30,
    )
    if not r.ok:
        raise RuntimeError(
            f"PATCH event_proposals[{proposal_id}] synced_to_local_at failed: "
            f"{r.status_code} {r.text}"
        )


def download_public(
    session: requests.Session,
    base_url: str,
    storage_path: str,
) -> bytes:
    # storage_path is `bucket/sub/path.png`
    url = f"{base_url}/storage/v1/object/public/{storage_path}"
    return sb_get(session, url).content


def upload_bytes(
    session: requests.Session,
    base_url: str,
    bucket: str,
    storage_path: str,
    data: bytes,
    *,
    overwrite: bool = True,
) -> None:
    url = f"{base_url}/storage/v1/object/{bucket}/{storage_path}"
    headers = {
        "Content-Type": "image/png",
        "x-upsert": "true" if overwrite else "false",
        "cache-control": "3600",
    }
    sb_post(session, url, data=data, headers=headers)


def patch_character_avatar_path(
    session: requests.Session,
    base_url: str,
    code: str,
    avatar_storage_path: str,
) -> None:
    url = f"{base_url}/rest/v1/characters"
    r = session.patch(
        url,
        params={"code": f"eq.{code}"},
        json={"avatar_storage_path": avatar_storage_path},
        timeout=30,
    )
    if not r.ok:
        raise RuntimeError(
            f"PATCH characters[{code}] failed: {r.status_code} {r.text}"
        )


def sync_one_proposal(
    proposal: dict,
    *,
    session: requests.Session,
    base_url: str,
    delete_source: bool,
    dry_run: bool,
) -> bool:
    """Sync one proposal. Returns True if everything succeeded (= safe to
    mark synced_to_local_at). False on any file-level error."""
    pid = proposal["id"]
    title = proposal.get("title", "")
    already_synced_at = proposal.get("synced_to_local_at")
    tag = f"(re-sync, prev={already_synced_at})" if already_synced_at else ""
    print(f"\n== [{pid}] {title} {tag}")

    all_ok = True

    # 1) Scene images → assets/story_images/{safe_title}/scene_{i}.png
    scene_paths = proposal.get("scene_image_paths") or []
    out_story_dir = STORIES_IMG_DIR / safe_dirname(title)
    if not dry_run:
        out_story_dir.mkdir(parents=True, exist_ok=True)
    for i, path in enumerate(scene_paths):
        if not path:
            continue
        dst = out_story_dir / f"scene_{i + 1}.png"
        print(f"  scene[{i}] {path} → {dst.relative_to(REPO_ROOT)}")
        if dry_run:
            continue
        try:
            data = download_public(session, base_url, path)
            dst.write_bytes(data)
        except Exception as exc:  # noqa: BLE001
            print(f"    ERROR: {exc}")
            all_ok = False

    # 2) Proposed characters → assets/avatars/{code}.png + characters/<code>.png
    #    + patch avatar_storage_path = '{code}.png'
    for pc in proposal.get("proposed_characters") or []:
        code = (pc.get("code") or "").strip()
        src_path = (pc.get("storage_path") or "").strip()
        if not code or not src_path:
            continue
        dst = AVATARS_DIR / f"{code}.png"
        print(f"  character {code} {src_path} → {dst.relative_to(REPO_ROOT)}")
        if dry_run:
            continue
        try:
            data = download_public(session, base_url, src_path)
            dst.write_bytes(data)
            upload_bytes(session, base_url, AVATAR_BUCKET, f"{code}.png", data)
            patch_character_avatar_path(
                session, base_url, code=code, avatar_storage_path=f"{code}.png"
            )
        except Exception as exc:  # noqa: BLE001
            print(f"    ERROR: {exc}")
            all_ok = False

    # 3) Optionally delete source objects from proposal-* buckets.
    if delete_source and not dry_run and all_ok:
        for path in scene_paths:
            if not path:
                continue
            try:
                sb_delete(session, f"{base_url}/storage/v1/object/{path}")
            except Exception as exc:  # noqa: BLE001
                print(f"    delete source scene failed: {exc}")
        for pc in proposal.get("proposed_characters") or []:
            p = pc.get("storage_path") or ""
            if not p:
                continue
            try:
                sb_delete(session, f"{base_url}/storage/v1/object/{p}")
            except Exception as exc:  # noqa: BLE001
                print(f"    delete source character failed: {exc}")

    return all_ok


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument(
        "--all",
        action="store_true",
        help=(
            "이미 synced_to_local_at 가 세팅된 제안도 재처리 "
            "(로컬 assets 날리고 통째로 복구할 때)"
        ),
    )
    parser.add_argument(
        "--delete-source",
        action="store_true",
        help=(
            "proposal-* 버킷의 원본 파일을 동기화 후 삭제. "
            "⚠️ 앱 배포 전이면 하이브리드 fallback 이 깨져 다른 사용자에게 "
            "이미지가 안 보일 수 있음 — 배포 완료 후에만 사용 권장"
        ),
    )
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    base_url = env_var("SUPABASE_URL", args.env)
    key = env_var("SUPABASE_SERVICE_ROLE_KEY", args.env)
    if not base_url:
        print(
            f"ERROR: SUPABASE_URL_{args.env.upper()} not set",
            file=sys.stderr,
        )
        return 2
    if not key and not args.dry_run:
        print(
            f"ERROR: SUPABASE_SERVICE_ROLE_KEY_{args.env.upper()} not set",
            file=sys.stderr,
        )
        return 2

    session = requests.Session()
    if key:
        session.headers.update(
            {"apikey": key, "Authorization": f"Bearer {key}"}
        )

    proposals = fetch_approved_proposals(
        session, base_url, include_already_synced=args.all
    )
    scope_label = "all approved" if args.all else "approved & unsynced"
    print(f"{scope_label}: {len(proposals)} proposal(s)")
    if not proposals:
        print(
            "Nothing to do. "
            "(Use --all to force re-sync of previously-synced proposals.)"
        )
        return 0

    totals = {"synced": 0, "failed": 0, "skipped": 0}
    for p in proposals:
        try:
            ok = sync_one_proposal(
                p,
                session=session,
                base_url=base_url,
                delete_source=args.delete_source,
                dry_run=args.dry_run,
            )
        except Exception as exc:  # noqa: BLE001
            print(f"  FATAL: {exc}")
            ok = False

        if args.dry_run:
            totals["skipped"] += 1
            continue

        if ok:
            try:
                patch_proposal_synced(session, base_url, p["id"])
                totals["synced"] += 1
            except Exception as exc:  # noqa: BLE001
                print(f"  WARN: could not PATCH synced_to_local_at: {exc}")
                totals["failed"] += 1
        else:
            totals["failed"] += 1

    print("\n=== Summary ===")
    print(f"  synced (marker 업데이트됨): {totals['synced']}")
    print(f"  failed (마커 미세팅 — 다음 run 에서 재시도): {totals['failed']}")
    if args.dry_run:
        print(f"  skipped (dry-run): {totals['skipped']}")

    if totals["synced"] > 0 and not args.dry_run:
        print("\nNext steps (recommended):")
        print("  make thumbnails                        # runtime thumbs")
        print("  make build-character-meta              # if new characters")
        print("  make seed-stories-characters           # regenerate SQL")
        print("  make apply-seeds-stories-characters    # push to DB")
        print("  ...then rebuild + release the app.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
