#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import tempfile
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

    print(
        f"Story thumbs: built {built_story}, skipped {skipped_story}, total {len(story_files)}"
    )
    print(
        f"Avatar thumbs: built {built_avatar}, skipped {skipped_avatar}, total {len(avatar_files)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
