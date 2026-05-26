#!/usr/bin/env python3
"""
Pre-push hook: pubspec.yaml의 assets 경로가 실제 파일시스템과 일치하는지 검증.

- pubspec.yaml의 `flutter:assets:` 섹션을 파싱
- 디렉토리 경로(끝이 `/`)는 디렉토리 존재 + 비어있지 않은지 확인
- 파일 경로는 파일 존재 확인
- 누락된 경로가 있으면 1로 종료
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
PUBSPEC = REPO_ROOT / "pubspec.yaml"


def parse_assets() -> list[str]:
    """pubspec.yaml에서 assets 목록 추출."""
    if not PUBSPEC.exists():
        return []
    text = PUBSPEC.read_text(encoding="utf-8")
    lines = text.splitlines()

    # `flutter:` → `assets:` 블록 찾기
    in_flutter = False
    in_assets = False
    assets: list[str] = []
    flutter_indent = 0
    for raw in lines:
        line = raw.rstrip()
        stripped = line.lstrip()
        indent = len(line) - len(stripped)

        if not stripped or stripped.startswith("#"):
            continue

        if stripped == "flutter:" and indent == 0:
            in_flutter = True
            flutter_indent = indent
            continue

        if in_flutter and indent == 0 and stripped != "flutter:":
            # flutter 블록 끝
            break

        if (
            in_flutter
            and stripped.startswith("assets:")
            and indent == flutter_indent + 2
        ):
            in_assets = True
            continue

        if in_assets:
            if indent <= flutter_indent + 2:
                in_assets = False
                continue
            # 항목: "- assets/foo/" or "- .env"
            m = re.match(r"-\s+(.+?)\s*$", stripped)
            if m:
                assets.append(m.group(1).strip())
    return assets


# CI 환경에서 존재하지 않는 파일 (.gitignore 대상이지만 pubspec.yaml에 필요)
_CI_SKIP_ASSETS = {".env"}


def verify(asset: str) -> tuple[bool, str]:
    """Returns (ok, reason)."""
    if asset in _CI_SKIP_ASSETS:
        return (True, "skipped (CI)")
    p = REPO_ROOT / asset
    if asset.endswith("/"):
        if not p.exists():
            return (False, "디렉토리 없음")
        if not p.is_dir():
            return (False, "디렉토리가 아님")
        # 적어도 하나 이상의 파일이 있어야 함
        try:
            has_file = any(child.is_file() for child in p.iterdir())
        except PermissionError:
            return (False, "권한 없음")
        if not has_file:
            return (False, "디렉토리가 비어있음")
        return (True, "ok")
    else:
        if not p.exists():
            return (False, "파일 없음")
        if not p.is_file():
            return (False, "파일이 아님")
        return (True, "ok")


def main() -> int:
    assets = parse_assets()
    if not assets:
        print("pubspec.yaml에서 assets 목록을 찾지 못했습니다.")
        return 1

    missing: list[tuple[str, str]] = []
    for asset in assets:
        ok, reason = verify(asset)
        if not ok:
            missing.append((asset, reason))

    if missing:
        print(f"에셋 경로 검증 실패 ({len(missing)}건):\n")
        for asset, reason in missing:
            print(f"  [{reason}] {asset}")
        print(f"\npubspec.yaml의 assets 항목과 실제 파일시스템이 일치하지 않습니다.")
        print(f"전체 검사된 항목: {len(assets)}개")
        return 1

    print(f"에셋 경로 검증 OK ({len(assets)}개 항목).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
