#!/usr/bin/env python3
"""Report landmark region polygons that look boxy or under-specified.

This is a lightweight pre-flight check for the heavier Shapely-based refinement
script. It has no third-party dependencies, so it can run before a local venv is
prepared.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LANDMARKS = ROOT / "assets" / "landmarks" / "landmarks.json"


def axis_aligned_edge_count(
    polygon: list[list[float]],
    tolerance: float = 0.0001,
) -> int:
    """Count edges that are effectively horizontal or vertical."""
    if len(polygon) < 2:
        return 0
    count = 0
    for start, end in zip(polygon, polygon[1:] + polygon[:1]):
        if abs(start[0] - end[0]) <= tolerance or abs(start[1] - end[1]) <= tolerance:
            count += 1
    return count


def bbox_for_polygon(polygon: list[list[float]]) -> dict[str, float]:
    lats = [point[0] for point in polygon]
    lngs = [point[1] for point in polygon]
    return {
        "min_lat": min(lats),
        "min_lng": min(lngs),
        "max_lat": max(lats),
        "max_lng": max(lngs),
    }


def audit_regions(
    catalog: dict[str, Any],
    *,
    max_vertices: int,
    min_axis_ratio: float,
) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    for region in catalog.get("regions", []):
        polygon = region.get("polygon") or []
        if len(polygon) < 3:
            continue
        axis_edges = axis_aligned_edge_count(polygon)
        axis_ratio = axis_edges / len(polygon)
        if len(polygon) <= max_vertices or axis_ratio >= min_axis_ratio:
            findings.append(
                {
                    "code": region.get("code"),
                    "name": region.get("name"),
                    "vertex_count": len(polygon),
                    "axis_aligned_edges": axis_edges,
                    "axis_ratio": round(axis_ratio, 4),
                    "bbox": bbox_for_polygon(polygon),
                }
            )
    findings.sort(
        key=lambda item: (
            -float(item["axis_ratio"]),
            int(item["vertex_count"]),
            str(item["code"]),
        )
    )
    return findings


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--landmarks", type=Path, default=DEFAULT_LANDMARKS)
    parser.add_argument(
        "--max-vertices",
        type=int,
        default=20,
        help="Flag polygons with this many vertices or fewer.",
    )
    parser.add_argument(
        "--min-axis-ratio",
        type=float,
        default=0.55,
        help="Flag polygons whose horizontal/vertical edge ratio is at least this value.",
    )
    parser.add_argument("--json", action="store_true", help="Print JSON output.")
    parser.add_argument(
        "--fail-on-findings",
        action="store_true",
        help="Exit 1 when any suspect polygon is found.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    catalog = json.loads(args.landmarks.read_text(encoding="utf-8"))
    findings = audit_regions(
        catalog,
        max_vertices=args.max_vertices,
        min_axis_ratio=args.min_axis_ratio,
    )
    if args.json:
        print(json.dumps(findings, ensure_ascii=False, indent=2))
    else:
        print(f"suspect region polygons: {len(findings)}")
        for item in findings:
            print(
                f"  {item['code']:24s} {item['name']:12s} "
                f"vertices={item['vertex_count']:3d} "
                f"axis={item['axis_aligned_edges']:3d} "
                f"ratio={item['axis_ratio']:.2f}"
            )

    if args.fail_on_findings and findings:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
