#!/usr/bin/env python3
"""Run all Python unit tests under tools/.

The tools tree is organized by script domain rather than Python packages, so
`unittest discover` does not recurse reliably without package marker files.
This runner executes each `test_*.py` file directly and preserves the first
failing exit code.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    test_files = sorted((repo_root / "tools").rglob("test_*.py"))
    if not test_files:
        print("No Python tool tests found.")
        return 1

    for test_file in test_files:
        rel = test_file.relative_to(repo_root)
        print(f"\n==> {rel}")
        result = subprocess.run([sys.executable, str(test_file)], cwd=repo_root)
        if result.returncode != 0:
            return result.returncode

    print(f"\nPython tool tests passed ({len(test_files)} files).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
