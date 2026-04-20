#!/usr/bin/env python3

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


MANIFEST_SCHEMA_VERSION = 1
AVATAR_MANIFEST_PATH = Path("supabase/generated_media/avatars.json")
STORY_SCENE_MANIFEST_PATH = Path("supabase/generated_media/story_scenes.json")
STORY_SIZE_CANDIDATES = (768, 720, 672, 640, 608, 576, 544, 512, 480, 448, 416, 384)
STORY_QUALITY_CANDIDATES = (72, 66, 60, 54, 48, 42, 36)
AVATAR_SIZE_CANDIDATES = (192, 176, 160, 144, 128)
SCENE_FILENAME_PATTERN = re.compile(r"scene_(\d+)\.(?:png|jpe?g|webp)$", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate runtime thumbnail assets without touching originals.",
    )
    parser.add_argument(
        "--story-source",
        default="assets/story_images",
        help="Source directory for original story images.",
    )
    parser.add_argument(
        "--story-output",
        default="assets/story_images_thumbs",
        help="Output directory for story image thumbnails.",
    )
    parser.add_argument(
        "--avatar-source",
        default="assets/avatars",
        help="Source directory for original avatar images.",
    )
    parser.add_argument(
        "--avatar-output",
        default="assets/avatars_thumbs",
        help="Output directory for avatar thumbnails.",
    )
    parser.add_argument(
        "--story-max-bytes",
        type=int,
        default=100_000,
        help="Maximum file size for each story thumbnail.",
    )
    parser.add_argument(
        "--workers",
        type=int,
        default=max(2, min(8, (os.cpu_count() or 4))),
        help="Number of parallel workers.",
    )
    return parser.parse_args()


def run_sips(command: list[str]) -> None:
    subprocess.run(
        command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def is_up_to_date(src: Path, dest: Path, max_bytes: int) -> bool:
    if not dest.exists():
        return False
    return (
        dest.stat().st_size <= max_bytes and dest.stat().st_mtime >= src.stat().st_mtime
    )


def build_story_thumb(src: Path, dest: Path, max_bytes: int) -> tuple[Path, bool]:
    if is_up_to_date(src, dest, max_bytes):
        return dest, False

    ensure_parent(dest)

    with tempfile.TemporaryDirectory(prefix="story_thumb_") as temp_dir:
        temp_root = Path(temp_dir)
        best_path: Path | None = None
        best_size: int | None = None

        for max_dim in STORY_SIZE_CANDIDATES:
            for quality in STORY_QUALITY_CANDIDATES:
                candidate = temp_root / f"{src.stem}_{max_dim}_{quality}.jpg"
                run_sips(
                    [
                        "sips",
                        "-Z",
                        str(max_dim),
                        "-s",
                        "format",
                        "jpeg",
                        "-s",
                        "formatOptions",
                        str(quality),
                        str(src),
                        "--out",
                        str(candidate),
                    ]
                )
                candidate_size = candidate.stat().st_size
                if best_size is None or candidate_size < best_size:
                    best_size = candidate_size
                    best_path = candidate
                if candidate_size <= max_bytes:
                    shutil.copy2(candidate, dest)
                    return dest, True

        if best_path is None:
            raise RuntimeError(f"Failed to generate thumbnail for {src}")
        shutil.copy2(best_path, dest)
        return dest, True


def build_avatar_thumb(
    src: Path, dest: Path, max_bytes: int = 100_000
) -> tuple[Path, bool]:
    if is_up_to_date(src, dest, max_bytes):
        return dest, False

    ensure_parent(dest)

    with tempfile.TemporaryDirectory(prefix="avatar_thumb_") as temp_dir:
        temp_root = Path(temp_dir)
        best_path: Path | None = None
        best_size: int | None = None

        for max_dim in AVATAR_SIZE_CANDIDATES:
            candidate = temp_root / f"{src.stem}_{max_dim}.png"
            run_sips(
                [
                    "sips",
                    "-Z",
                    str(max_dim),
                    str(src),
                    "--out",
                    str(candidate),
                ]
            )
            candidate_size = candidate.stat().st_size
            if best_size is None or candidate_size < best_size:
                best_size = candidate_size
                best_path = candidate
            if candidate_size <= max_bytes:
                shutil.copy2(candidate, dest)
                return dest, True

        if best_path is None:
            raise RuntimeError(f"Failed to generate avatar thumbnail for {src}")
        shutil.copy2(best_path, dest)
        return dest, True


def relative_story_dest(src_root: Path, dest_root: Path, src: Path) -> Path:
    relative = src.relative_to(src_root)
    return dest_root / relative.parent / f"{src.stem}.jpg"


def relative_avatar_dest(src_root: Path, dest_root: Path, src: Path) -> Path:
    return dest_root / src.relative_to(src_root)


def repo_relative_path(path: Path) -> str:
    if not path.is_absolute():
        return path.as_posix()
    try:
        return path.relative_to(Path.cwd()).as_posix()
    except ValueError:
        return path.as_posix()


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def natural_key(
    *,
    owner_type: str,
    owner_code: str,
    asset_role: str,
    variant: str,
    scene_index: int | None = None,
) -> str:
    scene_part = str(scene_index) if scene_index is not None else "none"
    return f"{owner_type}:{owner_code}:{asset_role}:{scene_part}:{variant}"


def load_manifest_assets(path: Path, asset_family: str) -> dict[str, dict]:
    if not path.exists():
        return {}
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("asset_family") != asset_family:
        raise ValueError(f"Unexpected asset_family in {path}: {data.get('asset_family')}")
    assets = data.get("assets", [])
    if not isinstance(assets, list):
        raise ValueError(f"Invalid assets payload in {path}")
    indexed: dict[str, dict] = {}
    for item in assets:
        if not isinstance(item, dict):
            continue
        key = str(item.get("natural_key") or "").strip()
        if not key:
            continue
        indexed[key] = item
    return indexed


def write_manifest(path: Path, asset_family: str, assets: dict[str, dict]) -> None:
    ordered_assets = [assets[key] for key in sorted(assets)]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schema_version": MANIFEST_SCHEMA_VERSION,
                "asset_family": asset_family,
                "assets": ordered_assets,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def scene_index_from_path(path: Path) -> int | None:
    match = SCENE_FILENAME_PATTERN.search(path.name)
    if match is None:
        return None
    return int(match.group(1))


def build_story_manifest_index(story_source: Path) -> dict[str, dict]:
    index: dict[str, dict] = {}
    for manifest_path in sorted(story_source.rglob("manifest.json")):
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
        entries = data.get("entries", [])
        if not isinstance(entries, list):
            continue

        event_code = str(data.get("event_code") or "").strip()
        event_title = str(data.get("title") or "").strip()
        source_json = str(data.get("source_json") or "").strip()
        source_index = int(data.get("source_index") or 0)
        generator_model = str(data.get("model") or "").strip()
        generator_location = str(data.get("location") or "").strip()

        for entry in entries:
            if not isinstance(entry, dict):
                continue
            filename = str(entry.get("file") or "").strip()
            if not filename:
                continue
            original_path = manifest_path.parent / filename
            relative_path = repo_relative_path(original_path)
            scene_index = entry.get("scene_index")
            if not isinstance(scene_index, int):
                scene_index = scene_index_from_path(original_path)
            if scene_index is None:
                continue
            index[relative_path] = {
                "event_code": event_code or manifest_path.parent.name,
                "event_title": event_title,
                "scene_index": scene_index,
                "scene_prompt": str(entry.get("scene_prompt") or "").strip(),
                "scene_prompt_note": str(entry.get("scene_prompt_note") or "").strip(),
                "scene_person_codes": list(entry.get("scene_person_codes") or []),
                "scene_reference_person_codes": list(
                    entry.get("scene_reference_person_codes") or []
                ),
                "reference_avatar_codes": list(entry.get("reference_avatar_codes") or []),
                "missing_reference_avatar_codes": list(
                    entry.get("missing_reference_avatar_codes") or []
                ),
                "source_json": source_json,
                "source_index": source_index,
                "generator_model": generator_model,
                "generator_location": generator_location,
            }
    return index


def build_avatar_original_asset(src: Path) -> dict:
    code = src.stem
    return {
        "natural_key": natural_key(
            owner_type="person",
            owner_code=code,
            asset_role="avatar",
            variant="original",
        ),
        "owner_type": "person",
        "owner_code": code,
        "asset_role": "avatar",
        "scene_index": None,
        "variant": "original",
        "relative_path": repo_relative_path(src),
        "source_relative_path": None,
        "mime_type": "image/png",
        "byte_size": src.stat().st_size,
        "content_hash": sha256_for_file(src),
        "generator": "tools/generate_avatars_vertex.py",
        "generator_model": None,
        "metadata": {},
    }


def build_avatar_thumbnail_asset(src: Path, dest: Path, metadata: dict | None) -> dict:
    code = src.stem
    return {
        "natural_key": natural_key(
            owner_type="person",
            owner_code=code,
            asset_role="avatar",
            variant="thumbnail",
        ),
        "owner_type": "person",
        "owner_code": code,
        "asset_role": "avatar",
        "scene_index": None,
        "variant": "thumbnail",
        "relative_path": repo_relative_path(dest),
        "source_relative_path": repo_relative_path(src),
        "mime_type": "image/png",
        "byte_size": dest.stat().st_size,
        "content_hash": sha256_for_file(dest),
        "generator": "tools/generate_runtime_thumbnails.py",
        "generator_model": None,
        "metadata": metadata or {},
    }


def build_story_original_asset(src: Path, index_entry: dict | None) -> dict | None:
    scene_index = (
        index_entry.get("scene_index") if index_entry is not None else scene_index_from_path(src)
    )
    event_code = (
        str(index_entry.get("event_code") or "").strip() if index_entry is not None else ""
    )
    if not event_code or scene_index is None:
        return None

    metadata = {
        "event_title": str(index_entry.get("event_title") or "").strip()
        if index_entry is not None
        else "",
        "scene_prompt": str(index_entry.get("scene_prompt") or "").strip()
        if index_entry is not None
        else "",
        "scene_prompt_note": str(index_entry.get("scene_prompt_note") or "").strip()
        if index_entry is not None
        else "",
        "scene_person_codes": list(index_entry.get("scene_person_codes") or [])
        if index_entry is not None
        else [],
        "scene_reference_person_codes": list(
            index_entry.get("scene_reference_person_codes") or []
        )
        if index_entry is not None
        else [],
        "reference_avatar_codes": list(index_entry.get("reference_avatar_codes") or [])
        if index_entry is not None
        else [],
        "missing_reference_avatar_codes": list(
            index_entry.get("missing_reference_avatar_codes") or []
        )
        if index_entry is not None
        else [],
        "source_json": str(index_entry.get("source_json") or "").strip()
        if index_entry is not None
        else "",
        "source_index": int(index_entry.get("source_index") or 0)
        if index_entry is not None
        else 0,
        "generator_location": str(index_entry.get("generator_location") or "").strip()
        if index_entry is not None
        else "",
    }

    return {
        "natural_key": natural_key(
            owner_type="event",
            owner_code=event_code,
            asset_role="story_scene",
            scene_index=scene_index,
            variant="original",
        ),
        "owner_type": "event",
        "owner_code": event_code,
        "asset_role": "story_scene",
        "scene_index": scene_index,
        "variant": "original",
        "relative_path": repo_relative_path(src),
        "source_relative_path": None,
        "mime_type": "image/png",
        "byte_size": src.stat().st_size,
        "content_hash": sha256_for_file(src),
        "generator": "tools/generate_event_story_images_vertex.py",
        "generator_model": (
            str(index_entry.get("generator_model") or "").strip()
            if index_entry is not None
            else None
        )
        or None,
        "metadata": metadata,
    }


def build_story_thumbnail_asset(src: Path, dest: Path, original_asset: dict) -> dict:
    return {
        "natural_key": natural_key(
            owner_type="event",
            owner_code=str(original_asset["owner_code"]),
            asset_role="story_scene",
            scene_index=int(original_asset["scene_index"]),
            variant="thumbnail",
        ),
        "owner_type": "event",
        "owner_code": original_asset["owner_code"],
        "asset_role": "story_scene",
        "scene_index": original_asset["scene_index"],
        "variant": "thumbnail",
        "relative_path": repo_relative_path(dest),
        "source_relative_path": repo_relative_path(src),
        "mime_type": "image/jpeg",
        "byte_size": dest.stat().st_size,
        "content_hash": sha256_for_file(dest),
        "generator": "tools/generate_runtime_thumbnails.py",
        "generator_model": None,
        "metadata": dict(original_asset.get("metadata") or {}),
    }


def main() -> int:
    args = parse_args()
    story_source = Path(args.story_source)
    story_output = Path(args.story_output)
    avatar_source = Path(args.avatar_source)
    avatar_output = Path(args.avatar_output)

    if not story_source.exists():
        raise SystemExit(f"Story source not found: {story_source}")
    if not avatar_source.exists():
        raise SystemExit(f"Avatar source not found: {avatar_source}")

    story_files = sorted(story_source.rglob("scene_*.png"))
    avatar_files = sorted(avatar_source.glob("*.png"))

    built_story = 0
    built_avatar = 0
    skipped_story = 0
    skipped_avatar = 0

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = []
        for src in story_files:
            dest = relative_story_dest(story_source, story_output, src)
            futures.append(
                executor.submit(build_story_thumb, src, dest, args.story_max_bytes)
            )
        for src in avatar_files:
            dest = relative_avatar_dest(avatar_source, avatar_output, src)
            futures.append(executor.submit(build_avatar_thumb, src, dest))

        for future in as_completed(futures):
            output_path, changed = future.result()
            if "story_images_thumbs" in str(output_path):
                if changed:
                    built_story += 1
                else:
                    skipped_story += 1
            else:
                if changed:
                    built_avatar += 1
                else:
                    skipped_avatar += 1

    avatar_existing_assets = load_manifest_assets(AVATAR_MANIFEST_PATH, "avatars")
    avatar_assets: dict[str, dict] = {}
    for src in avatar_files:
        original_asset = build_avatar_original_asset(src)
        existing_original = avatar_existing_assets.get(original_asset["natural_key"])
        if existing_original is not None:
            original_asset["metadata"] = dict(existing_original.get("metadata") or {})
            original_asset["generator_model"] = existing_original.get("generator_model")
        avatar_assets[original_asset["natural_key"]] = original_asset
        dest = relative_avatar_dest(avatar_source, avatar_output, src)
        if dest.exists():
            avatar_assets[
                natural_key(
                    owner_type="person",
                    owner_code=src.stem,
                    asset_role="avatar",
                    variant="thumbnail",
                )
            ] = build_avatar_thumbnail_asset(
                src,
                dest,
                metadata=dict(
                    avatar_assets[original_asset["natural_key"]].get("metadata") or {}
                ),
            )
    write_manifest(AVATAR_MANIFEST_PATH, "avatars", avatar_assets)

    story_existing_assets = load_manifest_assets(STORY_SCENE_MANIFEST_PATH, "story_scenes")
    story_assets: dict[str, dict] = {}
    story_existing_originals_by_path = {
        str(asset.get("relative_path")): asset
        for asset in story_existing_assets.values()
        if asset.get("variant") == "original" and asset.get("relative_path")
    }
    story_index = build_story_manifest_index(story_source)
    for src in story_files:
        original_relative = repo_relative_path(src)
        original_asset = build_story_original_asset(src, story_index.get(original_relative))
        existing_original = story_existing_originals_by_path.get(original_relative)
        if original_asset is None and existing_original is not None:
            original_asset = dict(existing_original)
        if original_asset is None:
            continue
        story_assets[original_asset["natural_key"]] = original_asset

        dest = relative_story_dest(story_source, story_output, src)
        if dest.exists():
            thumb_asset = build_story_thumbnail_asset(src, dest, original_asset)
            story_assets[thumb_asset["natural_key"]] = thumb_asset
    write_manifest(STORY_SCENE_MANIFEST_PATH, "story_scenes", story_assets)

    print(
        f"Story thumbs: built {built_story}, skipped {skipped_story}, total {len(story_files)}"
    )
    print(
        f"Avatar thumbs: built {built_avatar}, skipped {skipped_avatar}, total {len(avatar_files)}"
    )
    print(f"Avatar manifest: {AVATAR_MANIFEST_PATH}")
    print(f"Story manifest: {STORY_SCENE_MANIFEST_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
