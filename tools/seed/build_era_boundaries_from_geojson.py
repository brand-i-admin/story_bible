#!/usr/bin/env python3
"""Generate era_boundaries.json by clipping Natural Earth country polygons.

기존 hand-crafted 폴리곤은 정점 수가 적어 박스 같이 보였다. 이 스크립트는
Natural Earth (1:50m) 국가 폴리곤을 시대별 bounding box 로 잘라 실제 해안선을
따라가는 정밀한 폴리곤을 생성한다.

알고리즘:
    1. Natural Earth GeoJSON 로드 (assets/maps/ne_50m_admin_0_countries.geojson)
    2. 시대별 정의 (CLIP_REGIONS):
        - country_codes: 포함할 ISO_A2 국가 코드 목록
        - bbox: (min_lng, min_lat, max_lng, max_lat) 클립 박스
        - extra_polygons: bbox 외 추가/제외 영역 (선택)
    3. 각 국가 폴리곤을 bbox 로 intersection
    4. 모든 조각을 union → 시대 멀티폴리곤 (구멍은 제거, 외곽만 유지)
    5. simplify(0.05°) 로 정점 100~300개 수준으로 단순화
    6. era_boundaries.json 으로 저장

특징:
    - 해안선이 GeoJSON 정밀도(1:50m, ~1km 해상도)로 자연스럽게 따라감
    - 바다는 자동으로 제외됨 (육지 폴리곤만 사용)
    - 시대 단위로 단순한 정의만 추가하면 자동 생성

요구사항: shapely>=2.0
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from shapely.geometry import mapping, shape
from shapely.ops import unary_union


# 시대별 클립 정의.
# country_iso_a2: Natural Earth 의 ISO_A2 국가 코드 (대문자 2글자)
# bbox: (min_lng, min_lat, max_lng, max_lat) — 이 영역으로 국가 폴리곤을 자른다
# 주: 일부 시대는 여러 디스조인트 영역을 가지므로 클립 박스가 적절히 넓어야
#     원하는 부분만 잡힌다.
CLIP_REGIONS: dict[str, dict[str, Any]] = {
    "era_primeval": {
        # 메소포타미아 + 아라랏 (이라크, 동부 시리아, 동남부 터키, 서부 이란).
        "country_iso_a2": ["IQ", "TR", "IR", "SY"],
        "bbox": (38.5, 29.5, 49.5, 41.0),
        "color": "#E76F51",
        "fill_opacity": 0.18,
        "display_order": 1,
    },
    "era_patriarch": {
        # Fertile Crescent: 메소포타미아 → 시리아 → 가나안 → 시내 → 이집트 동부.
        "country_iso_a2": [
            "IQ",
            "SY",
            "LB",
            "IL",
            "PS",
            "JO",
            "EG",
            "TR",
            "SA",
        ],
        "bbox": (29.5, 28.0, 49.5, 38.0),
        "color": "#F4A261",
        "fill_opacity": 0.18,
        "display_order": 2,
    },
    "era_exodus": {
        # 이집트 동부 + 시내반도 + 가나안 남부.
        "country_iso_a2": ["EG", "IL", "PS", "JO", "SA"],
        "bbox": (30.0, 27.5, 36.0, 32.5),
        "color": "#F1C40F",
        "fill_opacity": 0.20,
        "display_order": 3,
    },
    "era_judges": {
        # 가나안 본토 (이스라엘 + 팔레스타인 + 요단 동편 일부).
        "country_iso_a2": ["IL", "PS", "JO", "LB"],
        "bbox": (34.2, 30.7, 36.1, 33.5),
        "color": "#3498DB",
        "fill_opacity": 0.18,
        "display_order": 4,
    },
    "era_monarchy": {
        # 이스라엘 + 유다 (judges 와 거의 같지만 약간 더 넓게).
        "country_iso_a2": ["IL", "PS", "JO", "LB", "SY"],
        "bbox": (34.2, 30.5, 36.5, 33.8),
        "color": "#E91E63",
        "fill_opacity": 0.18,
        "display_order": 5,
    },
    "era_exile_return": {
        # 가나안 → 시리아 → 메소포타미아 → 페르시아.
        "country_iso_a2": [
            "IL",
            "PS",
            "JO",
            "LB",
            "SY",
            "IQ",
            "IR",
            "TR",
        ],
        "bbox": (34.0, 29.5, 50.0, 38.0),
        "color": "#8E44AD",
        "fill_opacity": 0.16,
        "display_order": 6,
    },
    "era_nt_public_ministry": {
        # 갈릴리 + 사마리아 + 유대.
        "country_iso_a2": ["IL", "PS", "JO", "LB"],
        "bbox": (34.4, 30.9, 36.0, 33.5),
        "color": "#27AE60",
        "fill_opacity": 0.20,
        "display_order": 7,
    },
    "era_nt_apostolic": {
        # 사도 시대: 이탈리아 + 그리스 + 소아시아 + 시리아 + 가나안 + 키프로스 +
        # 몰타. 바울 항해이므로 지중해 포함은 OK 이나 GeoJSON 클립으로는 육지만.
        # 결과적으로 육지 부분만 강조됨 — 사도 활동지 자체가 도시들이라 OK.
        "country_iso_a2": [
            "IT",
            "GR",
            "AL",
            "MK",
            "BG",
            "TR",
            "CY",
            "SY",
            "LB",
            "IL",
            "PS",
            "JO",
            "EG",
            "MT",
        ],
        "bbox": (10.0, 30.0, 40.0, 43.5),
        "color": "#16A085",
        "fill_opacity": 0.16,
        "display_order": 8,
    },
    "era_nt_post_apostolic": {
        # 사도 후 시대 — 비슷한 영역이지만 좁게.
        "country_iso_a2": [
            "IT",
            "GR",
            "AL",
            "MK",
            "BG",
            "TR",
            "CY",
            "SY",
            "LB",
            "IL",
            "PS",
        ],
        "bbox": (10.0, 30.0, 40.0, 43.0),
        "color": "#1ABC9C",
        "fill_opacity": 0.14,
        "display_order": 9,
    },
    "era_nt_consummation": {
        # 요한계시록 7교회 (소아시아 서부).
        "country_iso_a2": ["TR"],
        "bbox": (25.0, 36.5, 30.5, 40.5),
        "color": "#9B59B6",
        "fill_opacity": 0.12,
        "display_order": 10,
    },
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build era_boundaries.json from Natural Earth GeoJSON."
    )
    parser.add_argument(
        "--geojson",
        default="assets/maps/ne_50m_admin_0_countries.geojson",
        help="Natural Earth countries GeoJSON path.",
    )
    parser.add_argument(
        "--output",
        default="assets/landmarks/era_boundaries.json",
        help="Output era_boundaries.json path.",
    )
    parser.add_argument(
        "--simplify-tolerance",
        type=float,
        default=0.05,
        help="Douglas-Peucker simplify tolerance in degrees (smaller = "
        "more vertices, more accurate). 0.05 ≈ 5km at lat 32°N.",
    )
    return parser.parse_args()


def load_country_features(path: Path) -> dict[str, Any]:
    """ISO_A2 코드 → GeoJSON feature 매핑."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    by_iso: dict[str, Any] = {}
    for feature in raw.get("features", []):
        props = feature.get("properties") or {}
        iso = (props.get("ISO_A2") or props.get("iso_a2") or "").upper()
        # NE 의 ISO_A2 가 '-99' 인 일부 항목 (북키프로스 등) 은 NAME 매핑으로
        # 보충. 단, 우리 시대 정의에는 메이저 국가만 들어가 무시해도 무방.
        if iso and iso != "-99":
            by_iso.setdefault(iso, feature)
    return by_iso


def coords_from_geom(geom: Any) -> list[list[list[float]]]:
    """Shapely 멀티폴리곤/폴리곤 → [[lat, lng] 외곽 정점 리스트] 의 리스트.
    내부 hole 은 무시하고 외곽 ring 만 사용 (시각적 영역 표시 목적)."""
    rings: list[list[list[float]]] = []
    geom_type = geom.geom_type
    polygons: list[Any]
    if geom_type == "Polygon":
        polygons = [geom]
    elif geom_type == "MultiPolygon":
        polygons = list(geom.geoms)
    else:
        return rings
    for poly in polygons:
        if poly.is_empty:
            continue
        coords = list(poly.exterior.coords)
        # GeoJSON 은 (lng, lat). 우리 era_boundaries.json 은 [lat, lng].
        ring = [[round(lat, 4), round(lng, 4)] for (lng, lat) in coords]
        if len(ring) < 4:
            continue
        # shapely 가 닫힌 ring 을 첫=마지막 으로 표현 — flutter_map Polygon 은
        # 마지막 정점 자동 처리하므로 명시적 close 정점을 제거.
        if ring[0] == ring[-1]:
            ring = ring[:-1]
        rings.append(ring)
    return rings


def build_polygons_for_era(
    era_def: dict[str, Any],
    countries: dict[str, Any],
    simplify_tol: float,
) -> list[list[list[float]]]:
    """시대 정의 → 클립 후 단순화된 폴리곤(들) 좌표."""
    bbox = era_def["bbox"]
    from shapely.geometry import box

    clip = box(*bbox)
    pieces = []
    for iso in era_def["country_iso_a2"]:
        feature = countries.get(iso)
        if feature is None:
            print(f"  [warn] country {iso} not found in GeoJSON — skip")
            continue
        geom = shape(feature["geometry"])
        clipped = geom.intersection(clip)
        if clipped.is_empty:
            continue
        pieces.append(clipped)
    if not pieces:
        return []
    merged = unary_union(pieces)
    simplified = merged.simplify(simplify_tol, preserve_topology=True)
    return coords_from_geom(simplified)


def main() -> int:
    args = parse_args()
    geojson_path = Path(args.geojson)
    output_path = Path(args.output)

    if not geojson_path.exists():
        raise FileNotFoundError(f"GeoJSON not found: {geojson_path}")

    countries = load_country_features(geojson_path)
    print(f"loaded {len(countries)} country features")

    output_rows: list[dict[str, Any]] = []
    for era_code, era_def in CLIP_REGIONS.items():
        polygons = build_polygons_for_era(era_def, countries, args.simplify_tolerance)
        if not polygons:
            print(f"  [skip] {era_code}: no polygons")
            continue
        total_pts = sum(len(p) for p in polygons)
        print(
            f"  {era_code}: {len(polygons)} polygon(s), " f"{total_pts} total vertices"
        )
        output_rows.append(
            {
                "era_code": era_code,
                "color": era_def["color"],
                "fill_opacity": era_def["fill_opacity"],
                "display_order": era_def["display_order"],
                "polygons": polygons,
            }
        )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(output_rows, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"\nwrote {len(output_rows)} eras to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
