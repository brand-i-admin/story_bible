#!/usr/bin/env python3
"""기존 region polygon 의 bbox 를 Natural Earth 해안선으로 클립해 정밀화.

목적:
  손으로 작성한 사각형스러운 region polygon 들을 Natural Earth (1:50m,
  ~1km 해상도) 해안선/국경 정점에 스냅해 자연스러운 곡선 폴리곤으로 교체.
  era_boundaries 와 같은 GeoJSON 클립 방식이지만 region 단위.

흐름:
  1. assets/landmarks/landmarks.json 의 각 region polygon 을 읽음
  2. polygon bbox + padding 으로 clip box 생성 (사용자가 의도한 영역 보존)
  3. Natural Earth countries GeoJSON 에서 해당 bbox 와 교차하는 모든 country
     feature 의 union 을 계산
  4. 그 union 을 clip box 로 intersect → 자연 해안선 + 국경 따라가는 land 폴리곤
  5. 결과를 [lat, lng] 배열로 변환, 작은 파편(섬·돌) 제거
  6. 출력:
     - --in-place: landmarks.json 의 polygon 필드를 직접 교체
     - 기본: refined_polygons.json 별도 파일로 출력 (검토용)

특수 처리:
  - polygon 빈 region (비지리적 종말 환상): skip
  - 정점 < 3: skip
  - 명시적 SKIP_CODES: 사용자가 명시한 region (수역, 작은 섬 등) 은 원본 유지

사용:
  python3 tools/seed/refine_landmark_polygons_from_geojson.py
  python3 tools/seed/refine_landmark_polygons_from_geojson.py --in-place
  python3 tools/seed/refine_landmark_polygons_from_geojson.py --regions rgn_judea,rgn_galilee
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

from shapely.geometry import box, mapping, shape
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LANDMARKS = ROOT / "assets" / "landmarks" / "landmarks.json"
DEFAULT_GEOJSON = ROOT / "assets" / "maps" / "ne_50m_admin_0_countries.geojson"
DEFAULT_OUT = ROOT / "tools" / "seed" / "refined_polygons.json"

# 클립을 건너뛸 region. 수역/매우 작은 섬/비지리적 — Natural Earth 해안선
# 클립이 의미 없거나 결과가 빈 폴리곤이 됨.
SKIP_CODES = {
    "rgn_red_sea",  # 수역. 해안선 클립하면 사라짐.
    "rgn_heavenly_throne",  # 비지리적
    "rgn_new_jerusalem",  # 비지리적
}

# bbox 양옆에 추가할 도(degree) — 해안선 약간 여유 있게 잡기.
BBOX_PADDING_DEG = 0.05

# 정점 simplify tolerance (도 단위). 0.0 이면 simplify 안 함.
# 0.005 ≈ 500m 정도. region 크기 10~50km 에 적절.
DEFAULT_SIMPLIFY = 0.01

# 최소 면적 (제곱 도) — 이보다 작은 파편(돌·섬)은 제거.
MIN_FRAGMENT_AREA = 0.005

# Natural Earth 클립이 의미 있는 결과를 내려면 최소 이 이상의 정점이 나와야
# 함. 미만이면 그냥 country bbox 슬라이스라 원본 (사람이 그린 것) 보다 못함 →
# 그 region 은 skip 하고 원본 polygon 유지. 갈릴리/사마리아 같은 sub-country
# region 은 50m 해상도 country boundary 안에 내부 디테일이 없어 이 케이스가 됨.
MIN_REFINEMENT_VERTICES = 10


def load_geojson_features(path: Path) -> list[Any]:
    """Natural Earth GeoJSON 의 모든 feature 의 shapely geometry 리스트."""
    with path.open() as fp:
        data = json.load(fp)
    features = []
    for feat in data.get("features", []):
        geom = feat.get("geometry")
        if geom is None:
            continue
        try:
            features.append(shape(geom))
        except Exception as exc:  # noqa: BLE001
            print(f"  [warn] failed to parse feature: {exc}", file=sys.stderr)
    return features


def polygon_bbox(polygon: list[list[float]]) -> tuple[float, float, float, float]:
    """polygon=[[lat, lng], ...] → (min_lng, min_lat, max_lng, max_lat)."""
    lats = [p[0] for p in polygon]
    lngs = [p[1] for p in polygon]
    return (min(lngs), min(lats), max(lngs), max(lats))


def geom_to_lat_lng_ring(geom) -> list[list[float]] | None:
    """shapely geometry → 가장 큰 외곽 ring 을 [lat, lng] 배열로.

    MultiPolygon 이면 면적 가장 큰 polygon 을 채택. 작은 파편은 버린다.
    """
    if geom.is_empty:
        return None
    if geom.geom_type == "Polygon":
        target = geom
    elif geom.geom_type == "MultiPolygon":
        # 가장 면적 큰 polygon
        target = max(geom.geoms, key=lambda g: g.area)
    elif geom.geom_type == "GeometryCollection":
        polys = [g for g in geom.geoms if g.geom_type in ("Polygon", "MultiPolygon")]
        if not polys:
            return None
        flat = []
        for p in polys:
            if p.geom_type == "Polygon":
                flat.append(p)
            else:
                flat.extend(p.geoms)
        target = max(flat, key=lambda g: g.area)
    else:
        return None

    # GeoJSON coords are (lng, lat) → 우리 포맷은 [lat, lng]
    coords = list(target.exterior.coords)
    # 마지막 좌표가 첫 좌표와 같으면 (closed ring) 제거 — 우리 포맷은 자동 close
    if coords and coords[0] == coords[-1]:
        coords = coords[:-1]
    return [[round(lat, 4), round(lng, 4)] for lng, lat in coords]


def refine_region(
    region: dict[str, Any],
    countries: list[Any],
    simplify: float,
) -> dict[str, Any] | None:
    """region 한 건의 polygon 을 GeoJSON 클립으로 정제.

    반환: 변경 사항 정보 dict, 변경 없으면 None.
    """
    code = region["code"]
    if code in SKIP_CODES:
        return None
    polygon = region.get("polygon")
    if not polygon or len(polygon) < 3:
        return None

    bbox = polygon_bbox(polygon)
    pad = BBOX_PADDING_DEG
    clip_box = box(bbox[0] - pad, bbox[1] - pad, bbox[2] + pad, bbox[3] + pad)

    # bbox 와 교차하는 country 만 필터 (전체 union 은 너무 무거움)
    intersecting = [c for c in countries if c.intersects(clip_box)]
    if not intersecting:
        return None

    union = unary_union(intersecting)
    clipped = union.intersection(clip_box)

    if clipped.is_empty:
        return None

    # 작은 파편 제거 — MultiPolygon 의 작은 조각 필터
    if clipped.geom_type == "MultiPolygon":
        big = [g for g in clipped.geoms if g.area >= MIN_FRAGMENT_AREA]
        if not big:
            big = list(clipped.geoms)  # 전부 작으면 그대로
        # 가장 큰 거 하나만 (작은 섬은 라벨 위치 혼동 유발)
        target = max(big, key=lambda g: g.area)
    else:
        target = clipped

    if simplify > 0:
        target = target.simplify(simplify, preserve_topology=True)

    new_ring = geom_to_lat_lng_ring(target)
    if new_ring is None or len(new_ring) < 3:
        return None
    if len(new_ring) < MIN_REFINEMENT_VERTICES:
        # bbox slice — 원본보다 못함. skip.
        return None

    return {
        "code": code,
        "name": region.get("name"),
        "old_vertex_count": len(polygon),
        "new_vertex_count": len(new_ring),
        "polygon": new_ring,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--landmarks", type=Path, default=DEFAULT_LANDMARKS)
    parser.add_argument("--geojson", type=Path, default=DEFAULT_GEOJSON)
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help="검토용 출력 경로 (--in-place 미지정 시).",
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help="landmarks.json 의 polygon 필드를 직접 교체.",
    )
    parser.add_argument(
        "--simplify",
        type=float,
        default=DEFAULT_SIMPLIFY,
        help=f"정점 simplify tolerance (도). 기본 {DEFAULT_SIMPLIFY}.",
    )
    parser.add_argument(
        "--regions",
        type=str,
        default=None,
        help="콤마 구분 region code 리스트. 미지정 시 모든 region.",
    )
    args = parser.parse_args()

    if not args.geojson.exists():
        raise FileNotFoundError(f"GeoJSON not found: {args.geojson}")

    print(f"loading {args.geojson} ...")
    countries = load_geojson_features(args.geojson)
    print(f"  {len(countries)} country features")

    with args.landmarks.open() as fp:
        cat = json.load(fp)

    target_codes: set[str] | None = None
    if args.regions:
        target_codes = {c.strip() for c in args.regions.split(",") if c.strip()}

    refinements: list[dict[str, Any]] = []
    skipped: list[str] = []
    for region in cat.get("regions", []):
        if target_codes and region["code"] not in target_codes:
            continue
        refined = refine_region(region, countries, args.simplify)
        if refined is None:
            skipped.append(region["code"])
            continue
        refinements.append(refined)
        print(
            f"  refined {refined['code']:30s} {refined['old_vertex_count']:3d} → "
            f"{refined['new_vertex_count']:3d} vertices"
        )

    if skipped:
        print(f"\nskipped ({len(skipped)}): {', '.join(skipped)}")

    if args.in_place:
        # 원본 landmarks.json 의 polygon 필드 교체
        idx = {r["code"]: r for r in cat["regions"]}
        for r in refinements:
            idx[r["code"]]["polygon"] = r["polygon"]
        with args.landmarks.open("w") as fp:
            json.dump(cat, fp, ensure_ascii=False, indent=2)
            fp.write("\n")
        print(f"\nupdated {args.landmarks} in place ({len(refinements)} regions)")
    else:
        with args.out.open("w") as fp:
            json.dump(
                {"refined": refinements, "skipped": skipped},
                fp,
                ensure_ascii=False,
                indent=2,
            )
            fp.write("\n")
        print(f"\nwrote {args.out} for review (no in-place edit)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
