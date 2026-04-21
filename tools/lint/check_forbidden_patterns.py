#!/usr/bin/env python3
"""
Pre-commit hook: 금지 패턴 검사.

검사 대상:
- lib/ 또는 test/ 의 .dart 파일에서 `print(` 사용 (대신 debugPrint)
- 모든 파일에서 잘못된 시크릿 패턴 (Supabase service role key, Vertex AI key 등)
- TODO 코멘트가 이슈 번호 없이 작성된 경우 경고만 (차단하지 않음)

사용법:
    python3 tools/check_forbidden_patterns.py [<file>...]

pre-commit이 변경된 파일을 인자로 넘긴다. 인자가 없으면 lib/ test/ tools/ 전체를 검사.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# (정규식, 설명, 차단 여부)
PATTERNS: list[tuple[re.Pattern[str], str, bool]] = [
    # Dart에서 print() 사용 차단 (lib/ test/ 만)
    (
        re.compile(r"^[^/]*\bprint\s*\("),
        "Dart 코드에서 `print(` 사용 금지. `debugPrint`를 사용하세요.",
        True,
    ),
    # Supabase service role key 패턴 (eyJ로 시작하는 long JWT)
    (
        re.compile(r"eyJ[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{30,}\.[A-Za-z0-9_-]{20,}"),
        "JWT 형식 시크릿이 코드/설정에 포함되어 있습니다. .env로 옮기세요.",
        True,
    ),
    # 알려진 시크릿 변수 노출
    (
        re.compile(r"SUPABASE_SERVICE_ROLE_KEY\s*=\s*['\"][^'\"]+['\"]"),
        "SUPABASE_SERVICE_ROLE_KEY 값이 코드에 노출되어 있습니다.",
        True,
    ),
    # Google API key 패턴
    (
        re.compile(r"AIza[0-9A-Za-z_-]{35}"),
        "Google API key가 노출되어 있습니다. .env로 옮기세요.",
        True,
    ),
    # 이슈 번호 없는 TODO (경고만)
    (
        re.compile(r"//\s*TODO(?!\s*\(#\d+\))"),
        "TODO에 이슈 번호가 없습니다 (예: `// TODO(#123): ...`)",
        False,
    ),
]


def files_to_check(args: list[str]) -> list[Path]:
    if args:
        return [REPO_ROOT / a if not Path(a).is_absolute() else Path(a) for a in args]
    targets: list[Path] = []
    for sub in ("lib", "test", "tools"):
        root = REPO_ROOT / sub
        if not root.exists():
            continue
        for p in root.rglob("*.dart"):
            targets.append(p)
        for p in root.rglob("*.py"):
            targets.append(p)
    return targets


def is_dart(path: Path) -> bool:
    return path.suffix == ".dart"


def check_file(path: Path) -> tuple[int, int]:
    """Returns (errors, warnings)."""
    if not path.exists() or not path.is_file():
        return (0, 0)
    try:
        text = path.read_text(encoding="utf-8")
    except (UnicodeDecodeError, PermissionError):
        return (0, 0)

    errors = 0
    warnings = 0
    for line_no, line in enumerate(text.splitlines(), 1):
        # 라인 코멘트는 스킵 (단, TODO 패턴은 코멘트 안에서 잡아야 하므로 별도 처리)
        stripped = line.lstrip()
        is_pure_comment = stripped.startswith("//") or stripped.startswith("#")

        for pattern, message, blocking in PATTERNS:
            # print( 패턴은 Dart 파일이 아니면 스킵
            if "print" in pattern.pattern and not is_dart(path):
                continue
            # print( 패턴은 코멘트 라인이면 스킵
            if "print" in pattern.pattern and is_pure_comment:
                continue

            if pattern.search(line):
                rel = path.relative_to(REPO_ROOT) if path.is_absolute() else path
                kind = "ERROR" if blocking else "WARN"
                print(f"  [{kind}] {rel}:{line_no}: {message}")
                print(f"          > {line.rstrip()}")
                if blocking:
                    errors += 1
                else:
                    warnings += 1
    return (errors, warnings)


def main() -> int:
    args = sys.argv[1:]
    targets = files_to_check(args)
    total_errors = 0
    total_warnings = 0
    for path in targets:
        e, w = check_file(path)
        total_errors += e
        total_warnings += w

    if total_warnings:
        print(f"\n경고 {total_warnings}개 (차단하지 않음).")
    if total_errors:
        print(f"\n금지 패턴 {total_errors}건 발견. 커밋이 차단됩니다.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
