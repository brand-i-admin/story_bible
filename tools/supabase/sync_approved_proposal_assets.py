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

  1. Query approved proposals that haven't been synced yet
     (we consider a proposal "synced" when its event's avatars are in the
     `characters` bucket and scene pngs are on local disk).
  2. For each approved proposal:
       a. Download each proposal-scenes/*.png to
          `assets/story_images/{title}/scene_{i}.png` (for Vertex output
          parity with generate-story-images output).
       b. Download each proposal-characters/*.png to
          `assets/avatars/{code}.png`.
       c. Re-upload the PNGs to the `characters/` bucket with clean path
          `{code}.png` and update characters.avatar_storage_path = '{code}.png'.
       d. (Optional) delete source proposal-* objects.

After running, the operator proceeds with the regular content pipeline:
    make thumbnails                   # makes runtime thumbnails
    make build-character-meta         # if character_meta.json needs new entry
    make seed-stories-characters      # regenerate SQL
    make apply-seeds-stories-characters  # push to DB

Usage:
    python3 tools/supabase/sync_approved_proposal_assets.py --env dev [--dry-run]
                                                             [--delete-source]

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


def fetch_approved_proposals(session: requests.Session, base_url: str) -> list[dict]:
    url = f"{base_url}/rest/v1/event_proposals"
    params = {
        "select": (
            "id,title,character_codes,scene_image_paths,scene_image_prompts,"
            "proposed_characters,approved_event_id,status"
        ),
        "status": "eq.approved",
    }
    r = sb_get(session, url, params=params)
    return r.json()


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
) -> None:
    pid = proposal["id"]
    title = proposal.get("title", "")
    print(f"\n== [{pid}] {title}")

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
        data = download_public(session, base_url, path)
        dst.write_bytes(data)

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
        data = download_public(session, base_url, src_path)
        dst.write_bytes(data)
        # Re-upload to canonical `characters/{code}.png`
        upload_bytes(session, base_url, AVATAR_BUCKET, f"{code}.png", data)
        patch_character_avatar_path(
            session, base_url, code=code, avatar_storage_path=f"{code}.png"
        )

    # 3) Optionally delete source objects from proposal-* buckets.
    if delete_source and not dry_run:
        # scene PNGs
        for path in scene_paths:
            if not path:
                continue
            url = f"{base_url}/storage/v1/object/{path}"
            sb_delete(session, url)
        # proposed character PNGs
        for pc in proposal.get("proposed_characters") or []:
            p = pc.get("storage_path") or ""
            if not p:
                continue
            url = f"{base_url}/storage/v1/object/{p}"
            sb_delete(session, url)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--env", default="dev", choices=["dev", "prod"])
    parser.add_argument(
        "--delete-source",
        action="store_true",
        help="proposal-* 버킷의 원본 파일을 동기화 후 삭제",
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

    proposals = fetch_approved_proposals(session, base_url)
    print(f"approved proposals: {len(proposals)}")
    for p in proposals:
        sync_one_proposal(
            p,
            session=session,
            base_url=base_url,
            delete_source=args.delete_source,
            dry_run=args.dry_run,
        )

    print("\nDone. Next steps:")
    print("  make thumbnails                        # regenerate runtime thumbs")
    print("  make build-character-meta              # if you added new characters")
    print("  make seed-stories-characters           # regenerate SQL")
    print("  make apply-seeds-stories-characters    # push to DB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
