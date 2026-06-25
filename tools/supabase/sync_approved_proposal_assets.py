#!/usr/bin/env python3
"""Sync approved proposals AND deletion approvals to the local `assets/` tree.

이 스크립트는 두 가지 phase 를 한 번에 처리한다:

Phase A — **추가** (approved proposals):
  - event_proposals.status = 'approved' AND synced_to_local_at IS NULL
  - 장면 이미지/아바타 PNG 를 proposal-* 버킷에서 로컬로 다운로드
  - characters/<code>.png 로 다시 업로드 + characters.avatar_storage_path 패치
  - 완료 시 synced_to_local_at = now() 로 멱등 마커 세팅
  - (--delete-source) proposal-* 버킷의 원본 파일 삭제

Phase B — **삭제/정리** (approve_delete_proposal 결과 반영):
  - active events(status='published' AND deleted_at IS NULL)의 title 집합을
    기준으로 로컬 `assets/story_images/<title>/` 디렉토리 diff 정리.
    soft-deleted row 는 DB에 남아 있어도 앱 번들 source 에서는 제외된다.
  - 과거 sync 버그로 공백이 `_`로 바뀐 story_images 폴더가 있으면 현재
    canonical 폴더명으로 옮긴다.
  - deleted events 의 scene_image_paths Storage 원본은 best-effort 로 삭제한다.
    이미 앱에서는 보이지 않으므로 fallback 보존 대상이 아니다.
  - characters 는 DB에 없는 code의 로컬 avatar/thumb만 diff 정리한다.

  Phase B 는 별도 마커 없이 **파일 존재 여부**로 멱등성 보장 — 이미 정리된
  것은 자연스럽게 skip. 사용자가 요청한 "이전에 sync 할 때 이미 삭제했다면
  진행 안 함" 의미를 그대로 따른다.

후처리(추천):
    make thumbnails                   # 새 캐릭터 썸네일
    make build-character-meta         # character_meta.json 갱신
    make seed-stories-characters      # SQL 재생성
    make apply-seeds-stories-characters  # DB 반영
    ...앱 재빌드/배포.

Usage:
    python3 tools/supabase/sync_approved_proposal_assets.py --env dev [--dry-run]
                                                             [--all]
                                                             [--delete-source]
                                                             [--skip-deletions]

  --all             : 재sync — synced_to_local_at 가 세팅된 것도 다시 처리
                      (Phase A only; Phase B 는 항상 모든 deleted/inactive 처리)
  --dry-run         : 실제 파일/DB 수정 없이 대상 목록만 출력
  --delete-source   : Phase A 후 proposal-* 버킷의 원본 파일 삭제
                      ⚠️ 앱 배포 전엔 하이브리드 fallback 이 깨질 수 있음
  --skip-deletions  : Phase B 를 건너뜀 (Phase A 만 실행)

Env vars required (.env + .env.ops):
    SUPABASE_URL_{ENV}
    SUPABASE_SERVICE_ROLE_KEY_{ENV}
Values are loaded from .env and .env.ops when python-dotenv is installed.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import unicodedata
from pathlib import Path

import requests

try:
    from dotenv import load_dotenv

    load_dotenv()
    load_dotenv(".env.ops")
except ImportError:
    pass


REPO_ROOT = Path(__file__).resolve().parents[2]
AVATARS_DIR = REPO_ROOT / "assets" / "avatars"
AVATARS_THUMBS_DIR = REPO_ROOT / "assets" / "avatars_thumbs"
STORIES_IMG_DIR = REPO_ROOT / "assets" / "story_images"
STORIES_IMG_THUMBS_DIR = REPO_ROOT / "assets" / "story_images_thumbs"

AVATAR_BUCKET = "characters"
PROPOSAL_SCENES_BUCKET = "proposal-scenes"
PROPOSAL_CHARS_BUCKET = "proposal-characters"
ASSET_ONLY_AVATAR_CODES = {"guide"}


def env_var(name: str, env_suffix: str) -> str | None:
    return os.environ.get(f"{name}_{env_suffix.upper()}") or os.environ.get(name)


def safe_dirname(title: str) -> str:
    """Convert a proposal title to a filesystem-safe directory name.

    Consistent with how `generate_event_story_images_vertex.py` names the
    `assets/story_images/<title>/` directory for production events.
    """
    cleaned = re.sub(r"[\\/:*?\"<>|]+", "_", title).strip()
    cleaned = cleaned.strip(".")
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return unicodedata.normalize("NFC", cleaned or "untitled_event")


def legacy_underscore_dirname(title: str) -> str:
    """Return the old sync-only folder name that replaced spaces with `_`."""
    cleaned = re.sub(r"\s+", " ", title.strip())
    keep = re.compile(r"[^\w가-힣 \-]+", re.UNICODE)
    out = keep.sub("", cleaned)
    return unicodedata.normalize("NFC", out.replace(" ", "_") or "untitled")


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
        raise RuntimeError(f"PATCH characters[{code}] failed: {r.status_code} {r.text}")


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


# =====================================================================
# Phase B — deletion sync: active event diff / local orphan cleanup.
# =====================================================================


def fetch_events(
    session: requests.Session,
    base_url: str,
    *,
    deleted_at_filter: str,
) -> list[dict]:
    """Fetch events for local asset diffing."""
    url = f"{base_url}/rest/v1/events"
    params: dict[str, str] = {
        "select": "id,title,scene_image_paths,deleted_at",
        "status": "eq.published",
        "deleted_at": deleted_at_filter,
        "limit": "2000",
    }
    r = sb_get(session, url, params=params)
    return r.json()


def fetch_active_events(
    session: requests.Session,
    base_url: str,
) -> list[dict]:
    return fetch_events(session, base_url, deleted_at_filter="is.null")


def fetch_deleted_events(
    session: requests.Session,
    base_url: str,
) -> list[dict]:
    return fetch_events(session, base_url, deleted_at_filter="not.is.null")


def fetch_all_characters(
    session: requests.Session,
    base_url: str,
) -> list[dict]:
    """모든 characters 를 가져온다 (row 가 있으면 로컬 avatar 보존 대상)."""
    url = f"{base_url}/rest/v1/characters"
    params: dict[str, str] = {
        "select": "code,avatar_url,avatar_storage_path",
    }
    r = sb_get(session, url, params=params)
    return r.json()


def remove_local_path(
    path: Path,
    *,
    dry_run: bool,
) -> bool:
    """파일/디렉토리 삭제. 이미 없으면 False 반환(no-op)."""
    if not path.exists():
        return False
    print(f"  delete local: {path.relative_to(REPO_ROOT)}")
    if dry_run:
        return True
    if path.is_dir():
        # 디렉토리 안의 파일들도 함께 제거.
        for child in sorted(path.rglob("*"), reverse=True):
            try:
                if child.is_file():
                    child.unlink()
                elif child.is_dir():
                    child.rmdir()
            except OSError as exc:
                print(f"    WARN: {child}: {exc}")
        try:
            path.rmdir()
        except OSError:
            pass  # 비어있지 않으면 그냥 둠
    else:
        try:
            path.unlink()
        except OSError as exc:
            print(f"    WARN: {exc}")
    return True


def migrate_legacy_story_dirs(
    active_events: list[dict],
    *,
    dry_run: bool,
) -> int:
    """Move old underscore-space folders to the canonical title folder name."""
    if not STORIES_IMG_DIR.exists():
        return 0
    moved = 0
    for ev in active_events:
        title = ev.get("title") or ""
        canonical = safe_dirname(title)
        legacy = legacy_underscore_dirname(title)
        if canonical == legacy:
            continue
        legacy_path = STORIES_IMG_DIR / legacy
        canonical_path = STORIES_IMG_DIR / canonical
        if not legacy_path.exists() or not legacy_path.is_dir():
            continue
        if canonical_path.exists():
            continue
        print(
            f"  rename legacy story dir: "
            f"{legacy_path.relative_to(REPO_ROOT)} → "
            f"{canonical_path.relative_to(REPO_ROOT)}"
        )
        if not dry_run:
            legacy_path.rename(canonical_path)
        moved += 1
    return moved


def cleanup_storage_paths(
    session: requests.Session,
    base_url: str,
    paths: list[str],
    *,
    dry_run: bool,
) -> None:
    """'bucket/sub/path.png' 경로 묶음을 best-effort 로 storage 에서 제거.

    approve_delete_proposal RPC 가 이미 시도하지만, 그 시점에 권한/네트워크로
    실패했을 수 있어 sync 시점에 한 번 더 청소한다. 404 는 무시.
    """
    for p in paths:
        if not p:
            continue
        print(f"  delete storage: {p}")
        if dry_run:
            continue
        try:
            sb_delete(session, f"{base_url}/storage/v1/object/{p}")
        except Exception as exc:  # noqa: BLE001
            print(f"    WARN: {exc}")


def sync_deletions(
    *,
    session: requests.Session,
    base_url: str,
    dry_run: bool,
) -> dict[str, int]:
    """**Diff-based** 정리.

      - active events(status='published' AND deleted_at IS NULL)의 title 집합을
        가져와, 로컬 `assets/story_images/` 디렉토리 중 **그 집합에 없는**
        디렉토리를 삭제. soft-deleted row 는 DB 에 남아도 이 집합에서 제외된다.
        `assets/story_images_thumbs/`는 짧은 asset 디렉토리 + index.json 구조라
        후속 `make thumbnails` 단계의 source diff/prune 에 맡긴다.
      - characters 테이블의 code 집합을 가져와, 로컬 `assets/avatars/` 와
        `assets/avatars_thumbs/` 의 PNG 중 **그 집합에 없는** 파일을 삭제.

    멱등성: file-exists check 으로 자연스럽게 skip. 이미 일치하면 카운터 0.
    """
    print("\n=== Phase B: deletions (diff-based) ===")
    totals = {
        "event_dirs": 0,
        "event_dirs_renamed": 0,
        "avatars": 0,
        "thumbs": 0,
    }

    # 1) active events.title diff
    active_events = fetch_active_events(session, base_url)
    deleted_events = fetch_deleted_events(session, base_url)
    totals["event_dirs_renamed"] = migrate_legacy_story_dirs(
        active_events,
        dry_run=dry_run,
    )
    db_safe_titles = {safe_dirname(ev.get("title") or "") for ev in active_events}
    print(
        f"DB active events: {len(active_events)} "
        f"(unique story dirs {len(db_safe_titles)}), "
        f"soft-deleted events: {len(deleted_events)}"
    )

    if STORIES_IMG_DIR.exists():
        for child in sorted(STORIES_IMG_DIR.iterdir()):
            if not child.is_dir():
                continue
            if child.name in db_safe_titles:
                continue
            print(f"\n-- {STORIES_IMG_DIR.name}/{child.name}  (DB 에 없음 → 삭제)")
            if remove_local_path(child, dry_run=dry_run):
                totals["event_dirs"] += 1

    deleted_scene_paths: list[str] = []
    for ev in deleted_events:
        for path in ev.get("scene_image_paths") or []:
            if path:
                deleted_scene_paths.append(path)
    if deleted_scene_paths:
        print("\n-- deleted event storage fallbacks")
        cleanup_storage_paths(
            session,
            base_url,
            sorted(set(deleted_scene_paths)),
            dry_run=dry_run,
        )

    # 2) characters.code diff
    chars = fetch_all_characters(session, base_url)
    db_codes = {(c.get("code") or "").strip() for c in chars if c.get("code")}
    print(f"\nDB characters: {len(chars)} (unique codes {len(db_codes)})")

    for path in sorted(AVATARS_DIR.glob("*.png")) if AVATARS_DIR.exists() else []:
        code = path.stem
        if code in ASSET_ONLY_AVATAR_CODES:
            continue
        if code in db_codes:
            continue
        print(f"\n-- avatars/{path.name}  (DB 에 code={code} 없음 → 삭제)")
        if remove_local_path(path, dry_run=dry_run):
            totals["avatars"] += 1

    for path in (
        sorted(AVATARS_THUMBS_DIR.glob("*.png")) if AVATARS_THUMBS_DIR.exists() else []
    ):
        code = path.stem
        if code in ASSET_ONLY_AVATAR_CODES:
            continue
        if code in db_codes:
            continue
        # _placeholder 같은 시스템 파일이 있으면 보호 (현 코드베이스엔 없지만 방어).
        if code.startswith("_"):
            continue
        print(f"\n-- avatars_thumbs/{path.name}  (DB 에 code={code} 없음 → 삭제)")
        if remove_local_path(path, dry_run=dry_run):
            totals["thumbs"] += 1

    return totals


def run_thumbnails(*, dry_run: bool) -> bool:
    """`make thumbnails` 를 호출해 새로 내려받은 PNG 의 썸네일 생성.

    sync 의 마지막 단계. 실패해도 sync 자체는 성공으로 친다 (스크립트 별도
    실행 가능). dry-run 이면 명령만 출력.
    """
    import subprocess

    cmd = ["make", "thumbnails"]
    print(f"\n=== Step C: thumbnails ===\n  $ {' '.join(cmd)}")
    if dry_run:
        return True
    try:
        subprocess.run(cmd, cwd=REPO_ROOT, check=True)
        return True
    except subprocess.CalledProcessError as exc:
        print(f"  WARN: thumbnails 실패: {exc}")
        return False


def run_pubspec_update(*, dry_run: bool) -> bool:
    """`make update-pubspec-assets` 호출 — story_images_thumbs index/short dirs
    목록을 pubspec.yaml flutter.assets 섹션에 동기화."""
    import subprocess

    cmd = ["make", "update-pubspec-assets"]
    print(f"\n=== Step D: pubspec.yaml ===\n  $ {' '.join(cmd)}")
    if dry_run:
        return True
    try:
        subprocess.run(cmd, cwd=REPO_ROOT, check=True)
        return True
    except subprocess.CalledProcessError as exc:
        print(f"  WARN: pubspec 업데이트 실패: {exc}")
        return False


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
    parser.add_argument(
        "--skip-deletions",
        action="store_true",
        help=(
            "Phase B (DB 와 로컬 자산 diff 정리) 를 건너뜀. " "Phase A(추가) 만 실행"
        ),
    )
    parser.add_argument(
        "--skip-post-processing",
        action="store_true",
        help=(
            "Step C (make thumbnails) + Step D (make update-pubspec-assets) 를 "
            "건너뜀. 별도 워크플로우에서 처리할 때 사용"
        ),
    )
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
        session.headers.update({"apikey": key, "Authorization": f"Bearer {key}"})

    proposals = fetch_approved_proposals(
        session, base_url, include_already_synced=args.all
    )
    scope_label = "all approved" if args.all else "approved & unsynced"
    print(f"{scope_label}: {len(proposals)} proposal(s)")

    totals = {"synced": 0, "failed": 0, "skipped": 0}
    if not proposals:
        print(
            "Phase A: nothing to add. "
            "(Use --all to force re-sync of previously-synced proposals.)"
        )
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

    # Phase B — DB 와의 diff 로 로컬에 남은 이미지/디렉토리 정리.
    deletion_totals: dict[str, int] = {
        "event_dirs": 0,
        "event_dirs_renamed": 0,
        "avatars": 0,
        "thumbs": 0,
    }
    if not args.skip_deletions:
        try:
            deletion_totals = sync_deletions(
                session=session, base_url=base_url, dry_run=args.dry_run
            )
        except Exception as exc:  # noqa: BLE001
            print(f"  WARN: Phase B failed: {exc}")
    else:
        print("\n=== Phase B: skipped (--skip-deletions) ===")

    any_change = (
        totals["synced"] > 0
        or deletion_totals["event_dirs"] > 0
        or deletion_totals["event_dirs_renamed"] > 0
        or deletion_totals["avatars"] > 0
        or deletion_totals["thumbs"] > 0
    )

    # Step C — 썸네일 생성 (스토리/아바타 모두 로컬에 새 PNG 가 들어왔으니 재생성).
    # Step D — pubspec.yaml 의 story_images_thumbs/<title>/ 엔트리 동기화.
    # 둘 다 변경이 있을 때만 실행 (멱등이긴 하지만 빠른 종료 위해).
    if any_change and not args.skip_post_processing:
        run_thumbnails(dry_run=args.dry_run)
        run_pubspec_update(dry_run=args.dry_run)

    print("\n=== Summary ===")
    print(f"  Phase A — synced (marker 업데이트됨): {totals['synced']}")
    print(
        f"  Phase A — failed (마커 미세팅 — 다음 run 에서 재시도): {totals['failed']}"
    )
    if args.dry_run:
        print(f"  Phase A — skipped (dry-run): {totals['skipped']}")
    print(
        f"  Phase B — local 정리: "
        f"event_dirs={deletion_totals['event_dirs']}, "
        f"event_dirs_renamed={deletion_totals['event_dirs_renamed']}, "
        f"avatars={deletion_totals['avatars']}, "
        f"thumbs={deletion_totals['thumbs']}"
    )

    if any_change and not args.dry_run:
        print(
            "\nNext steps: 앱 재빌드 + 배포. (build-character-meta / seed-* / apply-* 는 "
            "DB seed 가 갱신될 때만 — 신규 코드/이야기 시 별도로 돌리세요.)"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
