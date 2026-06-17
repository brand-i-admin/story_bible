#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import tempfile
import unicodedata
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

STORY_SIZE_CANDIDATES = (768, 720, 672, 640, 608, 576, 544, 512, 480, 448, 416, 384)
STORY_QUALITY_CANDIDATES = (72, 66, 60, 54, 48, 42, 36)
AVATAR_SIZE_CANDIDATES = (192, 176, 160, 144, 128)


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
        "--stories-dir",
        default="assets/200_stories",
        help=(
            "Directory containing story JSON files. Used to map long Korean "
            "story titles to short stable thumbnail asset directories."
        ),
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
    parser.add_argument(
        "--no-prune-orphans",
        action="store_true",
        help=(
            "기본 동작은 source 에 없는 thumbnail 을 자동 삭제한다. "
            "이 플래그를 주면 정리 단계를 스킵한다."
        ),
    )
    return parser.parse_args()


def normalize_nfc(text: str) -> str:
    return unicodedata.normalize("NFC", text)


def story_dir_name_for_title(title: str) -> str:
    replaced = title.replace("/", "_").replace(":", "_")
    for char in '\\*?"<>|':
        replaced = replaced.replace(char, "_")
    collapsed = " ".join(replaced.strip().split())
    trimmed = collapsed.strip(".")
    return normalize_nfc(trimmed or "untitled_event")


def era_asset_slug(era_code: str) -> str:
    era = era_code.strip().lower()
    if era.startswith("era_"):
        era = era[4:]
    safe = []
    for char in era:
        if char.isalnum() or char == "_":
            safe.append(char)
        else:
            safe.append("_")
    slug = "".join(safe).strip("_")
    return slug or "story"


def short_story_thumb_dir(event: dict) -> str:
    era_code = str(event.get("era") or "story")
    story_index = int(event.get("story_index") or 0)
    return f"{era_asset_slug(era_code)}_{story_index:03d}"


def load_story_thumb_index(stories_dir: Path) -> tuple[dict[str, str], dict]:
    """Return source-dir -> short-dir mapping and JSON index payload."""
    source_to_short: dict[str, str] = {}
    by_title: dict[str, str] = {}
    by_source_dir: dict[str, str] = {}
    items: list[dict[str, object]] = []

    for path in sorted(stories_dir.glob("*.json")):
        events = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(events, list):
            continue
        for event in events:
            if not isinstance(event, dict):
                continue
            title = str(event.get("title") or "").strip()
            if not title:
                continue
            source_dir = story_dir_name_for_title(title)
            asset_dir = short_story_thumb_dir(event)
            source_to_short[source_dir] = asset_dir
            by_title[title] = asset_dir
            by_source_dir[source_dir] = asset_dir
            items.append(
                {
                    "title": title,
                    "era": str(event.get("era") or ""),
                    "story_index": int(event.get("story_index") or 0),
                    "source_dir": source_dir,
                    "asset_dir": asset_dir,
                }
            )

    payload = {
        "version": 1,
        "by_title": by_title,
        "by_source_dir": by_source_dir,
        "items": sorted(
            items,
            key=lambda item: (str(item["era"]), int(item["story_index"])),
        ),
    }
    return source_to_short, payload


def prune_orphan_thumbs(
    expected: set[Path],
    output_root: Path,
    pattern: str,
) -> list[Path]:
    """output_root 안의 pattern 매칭 파일 중 expected 에 없는 것을 삭제한다.

    파일이 사라지면 부모 디렉토리도 비어 있으면 정리한다.
    macOS 의 NFD vs NFC 파일명 차이를 고려해 NFC 정규화로 비교한다.
    """
    if not output_root.exists():
        return []
    import unicodedata

    def norm(p: Path) -> str:
        return unicodedata.normalize("NFC", str(p))

    expected_norm = {norm(p) for p in expected}
    removed: list[Path] = []
    for path in sorted(output_root.rglob(pattern)):
        if norm(path) in expected_norm:
            continue
        path.unlink()
        removed.append(path)
        print(f"[PRUNE] removed orphan thumb: {path}")
        # 부모 디렉토리가 비면 청소.
        parent = path.parent
        while parent != output_root and parent.exists() and not any(parent.iterdir()):
            parent.rmdir()
            print(f"[PRUNE] removed empty dir: {parent}")
            parent = parent.parent
    return removed


def prune_orphan_dirs(expected_dirs: set[Path], output_root: Path) -> list[Path]:
    """Remove generated thumbnail directories that are no longer expected.

    This catches leftover non-image files such as `.DS_Store` in legacy
    title-based folders after all scene JPGs have already been pruned.
    """
    if not output_root.exists():
        return []

    def norm(p: Path) -> str:
        return unicodedata.normalize("NFC", str(p))

    expected_norm = {norm(p) for p in expected_dirs}
    removed: list[Path] = []
    for child in sorted(output_root.iterdir()):
        if not child.is_dir():
            continue
        if norm(child) in expected_norm:
            continue
        shutil.rmtree(child)
        removed.append(child)
        print(f"[PRUNE] removed orphan dir: {child}")
    return removed


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


def relative_story_dest(
    src_root: Path,
    dest_root: Path,
    src: Path,
    source_dir_to_short: dict[str, str],
) -> Path:
    relative = src.relative_to(src_root)
    source_dir = normalize_nfc(relative.parts[0]) if relative.parts else ""
    short_dir = source_dir_to_short.get(source_dir, source_dir)
    return dest_root / short_dir / f"{src.stem}.jpg"


def relative_avatar_dest(src_root: Path, dest_root: Path, src: Path) -> Path:
    return dest_root / src.relative_to(src_root)


def main() -> int:
    args = parse_args()
    story_source = Path(args.story_source)
    story_output = Path(args.story_output)
    stories_dir = Path(args.stories_dir)
    avatar_source = Path(args.avatar_source)
    avatar_output = Path(args.avatar_output)

    if not story_source.exists():
        raise SystemExit(f"Story source not found: {story_source}")
    if not stories_dir.exists():
        raise SystemExit(f"Stories dir not found: {stories_dir}")
    if not avatar_source.exists():
        raise SystemExit(f"Avatar source not found: {avatar_source}")

    source_dir_to_short, story_index_payload = load_story_thumb_index(stories_dir)
    story_output.mkdir(parents=True, exist_ok=True)
    (story_output / "index.json").write_text(
        json.dumps(story_index_payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    story_files = sorted(story_source.rglob("scene_*.png"))
    avatar_files = sorted(avatar_source.glob("*.png"))

    if not args.no_prune_orphans:
        expected_story_thumbs = {
            relative_story_dest(story_source, story_output, src, source_dir_to_short)
            for src in story_files
        }
        prune_orphan_thumbs(expected_story_thumbs, story_output, "*.jpg")
        prune_orphan_dirs(
            {path.parent for path in expected_story_thumbs},
            story_output,
        )
        expected_avatar_thumbs = {
            relative_avatar_dest(avatar_source, avatar_output, src)
            for src in avatar_files
        }
        prune_orphan_thumbs(expected_avatar_thumbs, avatar_output, "*.png")

    built_story = 0
    built_avatar = 0
    skipped_story = 0
    skipped_avatar = 0

    with ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = []
        for src in story_files:
            dest = relative_story_dest(
                story_source,
                story_output,
                src,
                source_dir_to_short,
            )
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

    print(
        f"Story thumbs: built {built_story}, skipped {skipped_story}, total {len(story_files)}"
    )
    print(
        f"Avatar thumbs: built {built_avatar}, skipped {skipped_avatar}, total {len(avatar_files)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
