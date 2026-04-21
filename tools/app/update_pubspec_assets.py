#!/usr/bin/env python3
"""assets/story_images_thumbs 하위 디렉토리를 pubspec.yaml에 자동 등록한다.

Flutter는 assets 목록에서 디렉토리를 하나 지정하면 그 디렉토리의 직접 자식
파일만 포함하고, 하위 디렉토리는 포함하지 않는다. 그래서 215개 이야기
이미지 폴더마다 개별 라인이 필요하다.

사용법:
    python3 tools/app/update_pubspec_assets.py \
        --pubspec pubspec.yaml \
        --images-dir assets/story_images_thumbs

동작:
    1. assets/story_images_thumbs/ 하위의 모든 직접 자식 디렉토리 목록을 스캔
    2. pubspec.yaml의 `assets:` 블록에서 story_images_thumbs/ 관련 라인 제거
    3. 스캔한 디렉토리 경로들을 정렬된 순서로 재삽입
    4. 변경 사항을 파일에 저장 (--check는 diff만 보고 종료)
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

PREFIX = "assets/story_images_thumbs/"
LINE_PREFIX = f"    - {PREFIX}"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pubspec", default="pubspec.yaml")
    parser.add_argument("--images-dir", default="assets/story_images_thumbs")
    parser.add_argument(
        "--check",
        action="store_true",
        help="변경 없이 diff만 출력하고 종료 (변경 있으면 exit 1)",
    )
    return parser.parse_args()


def scan_directories(images_dir: Path) -> list[str]:
    if not images_dir.exists():
        print(f"[error] {images_dir} 가 존재하지 않습니다.", file=sys.stderr)
        sys.exit(2)

    dirs = sorted(p.name for p in images_dir.iterdir() if p.is_dir())
    return dirs


def rewrite_pubspec(
    pubspec_path: Path,
    subdirs: list[str],
    check_only: bool,
) -> bool:
    content = pubspec_path.read_text(encoding="utf-8")
    lines = content.splitlines(keepends=True)

    # assets 블록에서 story_images_thumbs 관련 라인 제거
    kept: list[str] = []
    for line in lines:
        stripped = line.lstrip()
        if stripped.startswith(f"- {PREFIX}"):
            # 기존 story_images_thumbs 라인은 전부 삭제
            continue
        kept.append(line)

    # assets: 블록을 찾아 마지막 `- assets/` 라인 다음에 새 라인 삽입
    # 여기서는 기존 스타일에 맞추기 위해 `- assets/avatars_thumbs/`를 찾아
    # 그 다음 줄에 story_images_thumbs 엔트리를 삽입한다
    insert_idx: int | None = None
    for i, line in enumerate(kept):
        if line.rstrip().endswith("- assets/avatars_thumbs/"):
            insert_idx = i + 1
            break
        if line.rstrip().endswith("- assets/elements/"):
            insert_idx = i + 1
            break

    if insert_idx is None:
        print(
            "[error] pubspec.yaml의 assets 블록에서 기준이 되는 라인을 찾지 못했습니다.",
            file=sys.stderr,
        )
        sys.exit(3)

    new_entries = [f"{LINE_PREFIX}{name}/\n" for name in subdirs]
    new_lines = kept[:insert_idx] + new_entries + kept[insert_idx:]
    new_content = "".join(new_lines)

    if new_content == content:
        return False

    if check_only:
        print("[diff] pubspec.yaml의 story_images_thumbs 엔트리가 최신이 아닙니다.")
        return True

    pubspec_path.write_text(new_content, encoding="utf-8")
    print(f"[ok] pubspec.yaml 업데이트: {len(subdirs)} 디렉토리 반영")
    return True


def main() -> int:
    args = parse_args()
    pubspec_path = Path(args.pubspec)
    images_dir = Path(args.images_dir)

    subdirs = scan_directories(images_dir)
    changed = rewrite_pubspec(pubspec_path, subdirs, check_only=args.check)

    if args.check and changed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
