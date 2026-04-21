#!/usr/bin/env python3
"""
코드 메트릭 검사 — 거대 파일 / 거대 메소드 재발 방지.

DCM(Dart Code Metrics)의 무료 대안으로, 이 프로젝트에 맞는 규칙만 검사.
CI의 pre-push 또는 GitHub Actions에서 실행.

검사 항목:
1. 파일 줄 수 — 경고 500줄, 차단 1,500줄
2. 메소드/함수 수 — 경고 20개, 차단 40개
3. 단일 메소드 줄 수 — 경고 80줄, 차단 200줄

part 파일은 부모 파일에 포함되므로 제외.
test/ 파일은 검사하되 기준을 2배로 완화.

사용법:
    python3 tools/check_code_metrics.py [--ci]

--ci: 차단 기준 위반 시 exit 1 (CI용). 없으면 경고만 출력.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LIB_DIR = REPO_ROOT / "lib"
TEST_DIR = REPO_ROOT / "test"

# (경고 기준, 차단 기준)
THRESHOLDS = {
    "file_lines": (500, 1500),
    "method_count": (20, 40),
    "method_lines": (80, 200),
}

# test/ 파일은 기준 2배 완화
TEST_MULTIPLIER = 2

# part 파일은 부모에 귀속되므로 제외
PART_OF_PATTERN = re.compile(r"^part\s+of\s+['\"]")

# 메소드/함수 시작 패턴 (Dart)
METHOD_PATTERN = re.compile(
    r"^\s+"  # 들여쓰기 (클래스 내부)
    r"(?:static\s+)?"
    r"(?:Future<[^>]*>\s+|void\s+|Widget\s+|[A-Z]\w*\??\s+|bool\s+|int\s+|double\s+|String\??\s+|List<[^>]*>\s+|Map<[^>]*>\s+|Set<[^>]*>\s+)"
    r"(\w+)\s*[\(<{]"
)

TOP_LEVEL_FUNC = re.compile(
    r"^(?:Future<[^>]*>\s+|void\s+|Widget\s+|[A-Z]\w*\??\s+|bool\s+|int\s+|double\s+|String\??\s+|List<[^>]*>\s+|Map<[^>]*>\s+|Set<[^>]*>\s+)"
    r"(\w+)\s*[\(<{]"
)


def is_part_file(path: Path) -> bool:
    try:
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                stripped = line.strip()
                if not stripped or stripped.startswith("//"):
                    continue
                if PART_OF_PATTERN.match(stripped):
                    return True
                # import/part 선언이 아닌 코드 시작이면 part 아님
                if not stripped.startswith(("import ", "export ", "library ", "part ")):
                    return False
    except (UnicodeDecodeError, PermissionError):
        pass
    return False


def analyze_file(path: Path, is_test: bool) -> list[tuple[str, str, str]]:
    """Returns list of (level, message, detail)."""
    issues: list[tuple[str, str, str]] = []
    multiplier = TEST_MULTIPLIER if is_test else 1

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (UnicodeDecodeError, PermissionError):
        return issues

    # 1. 파일 줄 수
    warn, fail = THRESHOLDS["file_lines"]
    total = len(lines)
    if total > fail * multiplier:
        issues.append(("FAIL", f"파일 {total}줄 (차단 기준: {fail * multiplier})", ""))
    elif total > warn * multiplier:
        issues.append(("WARN", f"파일 {total}줄 (경고 기준: {warn * multiplier})", ""))

    # 2~3. 메소드 분석
    methods: list[tuple[str, int, int]] = []  # (name, start_line, line_count)
    current_method: str | None = None
    current_start = 0
    brace_depth = 0
    in_method = False

    for i, line in enumerate(lines, 1):
        stripped = line.strip()

        # 메소드 시작 감지
        m = METHOD_PATTERN.match(line) or TOP_LEVEL_FUNC.match(line)
        if m and not in_method:
            current_method = m.group(1)
            current_start = i
            brace_depth = 0
            in_method = True

        if in_method:
            brace_depth += stripped.count("{") - stripped.count("}")
            if brace_depth <= 0 and current_method:
                method_lines = i - current_start + 1
                methods.append((current_method, current_start, method_lines))
                current_method = None
                in_method = False

    # 메소드 수
    warn_mc, fail_mc = THRESHOLDS["method_count"]
    mc = len(methods)
    if mc > fail_mc * multiplier:
        issues.append(
            ("FAIL", f"메소드 {mc}개 (차단 기준: {fail_mc * multiplier})", "")
        )
    elif mc > warn_mc * multiplier:
        issues.append(
            ("WARN", f"메소드 {mc}개 (경고 기준: {warn_mc * multiplier})", "")
        )

    # 단일 메소드 줄 수
    warn_ml, fail_ml = THRESHOLDS["method_lines"]
    for name, start, ml in methods:
        if ml > fail_ml * multiplier:
            issues.append(
                (
                    "FAIL",
                    f"메소드 `{name}` {ml}줄 (차단 기준: {fail_ml * multiplier})",
                    f"line {start}",
                )
            )
        elif ml > warn_ml * multiplier:
            issues.append(
                (
                    "WARN",
                    f"메소드 `{name}` {ml}줄 (경고 기준: {warn_ml * multiplier})",
                    f"line {start}",
                )
            )

    return issues


def main() -> int:
    ci_mode = "--ci" in sys.argv

    all_issues: list[tuple[Path, str, str, str]] = []

    for root_dir, is_test in [(LIB_DIR, False), (TEST_DIR, True)]:
        if not root_dir.exists():
            continue
        for dart_file in sorted(root_dir.rglob("*.dart")):
            if is_part_file(dart_file):
                continue
            issues = analyze_file(dart_file, is_test)
            for level, msg, detail in issues:
                all_issues.append((dart_file, level, msg, detail))

    if not all_issues:
        print("코드 메트릭 검사 통과 ✓")
        return 0

    has_fail = False
    for path, level, msg, detail in all_issues:
        rel = path.relative_to(REPO_ROOT)
        loc = f" ({detail})" if detail else ""
        marker = "❌" if level == "FAIL" else "⚠️"
        print(f"  {marker} [{level}] {rel}{loc}: {msg}")
        if level == "FAIL":
            has_fail = True

    warn_count = sum(1 for _, l, _, _ in all_issues if l == "WARN")
    fail_count = sum(1 for _, l, _, _ in all_issues if l == "FAIL")
    print(f"\n메트릭 검사: {fail_count}건 차단, {warn_count}건 경고.")

    if ci_mode and has_fail:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
