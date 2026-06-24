#!/usr/bin/env python3
"""모든 사건 landmark 좌표가 region polygon 내부에 있는지 검증.

사용:
  python tools/seed/verify_polygons_contain_events.py
  python tools/seed/verify_polygons_contain_events.py \
      --landmarks /tmp/test_landmarks.json --stories /tmp/test_stories.json

종료 코드:
  0 — 모든 사건의 landmark가 region polygon 내부 (또는 region 미배정 사건)
  1 — 1건 이상 외부에 위치 (위반 목록 stderr 로 출력)

stories 인자가 디렉토리이면 *.json 글롭으로 일괄 검사한다.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LANDMARKS = ROOT / "assets" / "landmarks" / "landmarks.json"
DEFAULT_STORIES = ROOT / "assets" / "events"


def point_in_polygon(point, polygon):
    """ray-casting. polygon=[[lat,lng], ...]. point=(lat, lng)."""
    if not polygon or len(polygon) < 3:
        return False
    x, y = point[1], point[0]
    inside = False
    n = len(polygon)
    j = n - 1
    for i in range(n):
        yi, xi = polygon[i][0], polygon[i][1]
        yj, xj = polygon[j][0], polygon[j][1]
        if ((yi > y) != (yj > y)) and (x < (xj - xi) * (y - yi) / (yj - yi) + xi):
            inside = not inside
        j = i
    return inside


def load_stories(path: Path):
    """stories 입력 로드 — 파일이면 단일 JSON, 디렉토리면 *.json 일괄."""
    if path.is_dir():
        events = []
        for f in sorted(path.glob("*.json")):
            with f.open() as fp:
                items = json.load(fp)
            if isinstance(items, list):
                events.extend(items)
        return events
    with path.open() as fp:
        data = json.load(fp)
    return data if isinstance(data, list) else []


def parent_region(landmark_code, regions_by_code, landmarks_by_code):
    if landmark_code in regions_by_code:
        return regions_by_code[landmark_code]
    lm = landmarks_by_code.get(landmark_code)
    if lm is None:
        return None
    prc = lm.get("parent_region_code")
    return regions_by_code.get(prc)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--landmarks", type=Path, default=DEFAULT_LANDMARKS)
    parser.add_argument("--stories", type=Path, default=DEFAULT_STORIES)
    args = parser.parse_args()

    with args.landmarks.open() as fp:
        cat = json.load(fp)

    regions = [r for r in cat.get("regions", []) if r.get("polygon")]
    regions_by_code = {r["code"]: r for r in regions}
    landmarks_by_code = {l["code"]: l for l in cat.get("landmarks", []) or []}

    events = load_stories(args.stories)

    violations = []
    for ev in events:
        lm_code = ev.get("landmark_code")
        landmark = landmarks_by_code.get(lm_code) if lm_code else None
        if landmark is not None:
            lat = landmark.get("lat")
            lng = landmark.get("lng")
            place = landmark.get("name") or ev.get("place_name")
        else:
            lat = ev.get("lat")
            lng = ev.get("lng")
            place = ev.get("place_name")
        if lat is None or lng is None:
            continue
        region = (
            parent_region(lm_code, regions_by_code, landmarks_by_code)
            if lm_code
            else None
        )
        if region is None:
            inside_any = any(
                point_in_polygon((lat, lng), r["polygon"]) for r in regions
            )
            if not inside_any:
                violations.append(
                    {
                        "title": ev.get("title"),
                        "lat": lat,
                        "lng": lng,
                        "place": place,
                        "reason": "no region polygon contains this point",
                    }
                )
            continue
        if not point_in_polygon((lat, lng), region["polygon"]):
            violations.append(
                {
                    "title": ev.get("title"),
                    "lat": lat,
                    "lng": lng,
                    "place": place,
                    "region_code": region["code"],
                    "region_name": region["name"],
                    "reason": "outside parent region polygon",
                }
            )

    if violations:
        print(
            f"[polygon-violation] {len(violations)} 사건이 polygon 외부:",
            file=sys.stderr,
        )
        for v in violations:
            loc = f"({v['lat']}, {v['lng']})"
            tail = (
                f" → {v.get('region_name')} ({v.get('region_code')})"
                if v.get("region_code")
                else ""
            )
            print(
                f"  - '{v['title']}' @ {loc} [{v['place']}]{tail}: {v['reason']}",
                file=sys.stderr,
            )
        return 1

    print(f"OK: {len(events)} events, all inside their region polygon.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
