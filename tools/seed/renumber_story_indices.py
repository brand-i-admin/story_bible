#!/usr/bin/env python3
"""Renumber `story_index` per era across assets/events/*.json.

Why: 사용자가 stories 를 추가/삭제하면서 era 안에서 story_index 가 듬성듬성
비거나 None 으로 남는 경우가 있다. 이 스크립트는 era 마다 1..N 으로 다시
연속 번호를 매긴다.

정렬 규칙:
  - 같은 era 안에서, 현재 story_index 가 정수인 항목은 그 값으로 정렬한다.
  - story_index 가 None 인 항목은 같은 파일의 JSON 배열 위치 기준으로
    이웃한 정수 값들 사이에 보간(interpolate)하여 자연스러운 위치를 잡는다.
  - 같은 정수 값을 가진 항목이 둘 이상 있으면 (file_name, array_index) 으로
    안정 정렬한다.

쓰는 순서:
  1) 모든 *.json 파일을 알파벳 순으로 읽어 (file, array_index, item) 수집.
  2) era 별로 그룹화 → 같은 era 안에서 effective_index 계산 → 정렬 → 1..N 재할당.
  3) 각 파일을 원래 배열 순서 그대로 유지하면서 story_index 만 갱신해서 저장.

CLI:
  python tools/seed/renumber_story_indices.py             # 실제 적용
  python tools/seed/renumber_story_indices.py --dry-run   # 무엇이 바뀌는지 미리 보기
"""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Renumber story_index per era across stories JSON files."
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/events",
        help="Directory containing the stories JSON files.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print plan without writing files.",
    )
    return parser.parse_args()


def fill_none_with_interpolation(
    sequence: list[float | None],
) -> list[float]:
    """sequence: 같은 era 의 항목들이 (file 알파벳, array index) 순으로 정렬된 리스트.

    None 항목은 양쪽 이웃의 정수 값들로 선형 보간한다. 양 끝에만 정수 값이
    있으면 ±0.5 식으로 끝점에 붙는 효과를 낸다.
    """
    n = len(sequence)
    out: list[float] = [0.0] * n
    # 1) 정수 그대로 채우기
    for i, v in enumerate(sequence):
        out[i] = float(v) if v is not None else float("nan")
    # 2) NaN 구간 보간
    i = 0
    while i < n:
        if not _is_nan(out[i]):
            i += 1
            continue
        gap_start = i
        while i < n and _is_nan(out[i]):
            i += 1
        gap_end = i - 1  # 마지막 NaN 인덱스
        prev_idx = gap_start - 1
        next_idx = gap_end + 1
        prev_val = out[prev_idx] if prev_idx >= 0 else None
        next_val = out[next_idx] if next_idx < n else None
        gap_count = gap_end - gap_start + 1
        if prev_val is not None and next_val is not None:
            step = (next_val - prev_val) / (gap_count + 1)
            for k in range(gap_count):
                out[gap_start + k] = prev_val + step * (k + 1)
        elif prev_val is not None:
            for k in range(gap_count):
                out[gap_start + k] = prev_val + 0.5 + k * 1e-3
        elif next_val is not None:
            for k in range(gap_count):
                out[gap_start + k] = next_val - 0.5 + k * 1e-3
        else:
            for k in range(gap_count):
                out[gap_start + k] = float(k)
    return out


def _is_nan(x: float) -> bool:
    return x != x


def main() -> int:
    args = parse_args()
    stories_dir = Path(args.stories_dir)
    if not stories_dir.exists():
        raise SystemExit(f"stories dir not found: {stories_dir}")

    files = sorted(stories_dir.glob("*.json"), key=lambda p: p.name)
    if not files:
        raise SystemExit(f"no JSON files in {stories_dir}")

    file_data: dict[str, list[dict[str, Any]]] = {}
    flat: list[tuple[str, int, dict[str, Any]]] = []
    for path in files:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            raise SystemExit(f"JSON root must be list: {path}")
        file_data[path.name] = data
        for arr_idx, item in enumerate(data):
            if not isinstance(item, dict):
                raise SystemExit(f"non-object row in {path}: {item!r}")
            flat.append((path.name, arr_idx, item))

    # era 별 항목 모으기 (file 알파벳, array index 순).
    by_era: dict[str, list[tuple[str, int, dict[str, Any]]]] = defaultdict(list)
    for fname, arr_idx, item in flat:
        era = str(item.get("era", "")).strip()
        if not era:
            raise SystemExit(f"missing era in {fname}[{arr_idx}]: {item!r}")
        by_era[era].append((fname, arr_idx, item))

    # era 별로 effective index 계산 → 정렬 → 1..N 재할당.
    plan: list[tuple[str, str, int, int | None, int]] = []
    for era, entries in by_era.items():
        cur_indices: list[float | None] = []
        for _, _, item in entries:
            raw = item.get("story_index")
            cur_indices.append(float(raw) if isinstance(raw, int) else None)
        eff = fill_none_with_interpolation(cur_indices)

        # eff + (file, array index) 로 안정 정렬.
        order = sorted(
            range(len(entries)),
            key=lambda i: (eff[i], entries[i][0], entries[i][1]),
        )
        for new_idx, pos in enumerate(order, start=1):
            fname, arr_idx, item = entries[pos]
            old = item.get("story_index")
            old_int = old if isinstance(old, int) else None
            plan.append((era, fname, arr_idx, old_int, new_idx))

    plan.sort(key=lambda t: (t[0], t[4]))

    print("== renumber plan ==")
    cur_era = ""
    changed = 0
    for era, fname, arr_idx, old_int, new_idx in plan:
        if era != cur_era:
            cur_era = era
            print(f"\n[{era}]")
        title = file_data[fname][arr_idx].get("title", "")
        marker = " (no change)" if old_int == new_idx else ""
        if old_int != new_idx:
            changed += 1
        print(
            f"  {old_int!s:>4} -> {new_idx:>3}  | {fname:<16} arr#{arr_idx:<3} | {title}{marker}"
        )
    print(f"\nchanged: {changed}/{len(plan)}")

    if args.dry_run:
        print("(dry-run) no files written")
        return 0

    # 적용: file 단위로 array 그대로 두고 story_index 필드만 덮어쓴다.
    for era, fname, arr_idx, _, new_idx in plan:
        file_data[fname][arr_idx]["story_index"] = new_idx

    for fname, data in file_data.items():
        path = stories_dir / fname
        path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
