#!/usr/bin/env python3
"""
event_landmark_mapping_draft.json + 옛 v1 landmarks_seed.sql → 새 v3 카탈로그.

산출물:
  - assets/landmarks/landmarks.json 의 'landmarks' 배열 채움
  - assets/landmarks/event_region_mapping.json (사건 → 새 region/landmark 매핑)

규칙:
  - landmark code: lm_<era_short>_<v1_clean_code>
  - 시대마다 별개 landmark (감람산 왕정 vs 신약 = 다른 record)
  - parent_region_code: 새 36개 region 중 하나
  - kind: 옛 v1 category 또는 이름 키워드로 추정

옛 region → 새 region 매핑 테이블은 코드 안에 정의.
ambiguous 케이스 (rgn_transjordan / rgn_asia_minor / rgn_syria) 는
place_name 키워드로 분기.
"""
from __future__ import annotations

import json
import re
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[2]
MAP_PATH = ROOT / "assets" / "landmarks" / "event_landmark_mapping_draft.json"
LANDMARKS_PATH = ROOT / "assets" / "landmarks" / "landmarks.json"
OLD_SQL_PATH = Path("/tmp/old_landmarks_seed.sql")
EVENT_REGION_OUT = ROOT / "assets" / "landmarks" / "event_region_mapping.json"

ERA_SHORT = {
    "era_primeval": "prim",
    "era_patriarch": "pat",
    "era_exodus": "exo",
    "era_judges": "jud",
    "era_monarchy": "mon",
    "era_exile_return": "exi",
    "era_nt_public_ministry": "nt_pm",
    "era_nt_apostolic": "nt_ap",
    "era_nt_post_apostolic": "nt_post",
    "era_nt_consummation": "nt_con",
}

# 옛 region → 새 region (단순 1:1)
SIMPLE_REGION_MAP = {
    "rgn_canaan_south": "rgn_judea",
    "rgn_canaan_central": "rgn_samaria",
    "rgn_canaan_north": "rgn_galilee",
    "rgn_mesopotamia": "rgn_mesopotamia",
    "rgn_egypt": "rgn_egypt",
    "rgn_sinai": "rgn_sinai_peninsula",
    "rgn_persia": "rgn_persia",
    "rgn_negev_arabah": "rgn_negev",
    "rgn_macedonia": "rgn_macedonia",
    "rgn_greece": "rgn_achaia",
    "rgn_philistia": "rgn_philistia",
    "rgn_coastal_plain": "rgn_coastal_plain",
    "rgn_cyprus": "rgn_cyprus",
    "rgn_crete_mediterranean": "rgn_crete",
    "rgn_malta": "rgn_malta",
    "rgn_italy": "rgn_italy",
    "rgn_red_sea": "rgn_red_sea",
    "rgn_ararat": "rgn_ararat",
}


def resolve_ambiguous_region(
    old_region: str, place_name: str, lc: str, era: str
) -> str:
    """transjordan/asia_minor/syria 같이 한 옛 region 이 여러 새 region 으로 쪼개진 경우."""
    if old_region == "rgn_transjordan":
        # 길르앗 / 모압 / 암몬 / 베레아 / 바산
        if any(
            k in place_name for k in ("길르앗", "얍복", "라못", "마하나임", "얍베스")
        ):
            return "rgn_gilead"
        if "모압" in place_name or "느보" in place_name or "헤스본" in place_name:
            return "rgn_moab"
        if "암몬" in place_name or "랍바" in place_name:
            return "rgn_ammon"
        if "바산" in place_name or "헤르몬" in place_name:
            return "rgn_bashan"
        if era == "era_nt_public_ministry":
            return "rgn_perea"
        # 기본: 길르앗
        return "rgn_gilead"

    if old_region == "rgn_asia_minor":
        # 갈라디아 (안디옥-비시디아·이고니온·루스드라·더베) vs 아시아 (에베소·드로아·밀레도·일곱교회·무라)
        galatia_kw = ("비시디아", "이고니온", "루스드라", "더베", "갈라디아")
        if any(k in place_name for k in galatia_kw):
            return "rgn_galatia"
        return "rgn_asia_province"

    if old_region == "rgn_syria":
        if "다메섹" in place_name or "다마스" in place_name:
            return "rgn_aram_damascus"
        return "rgn_syria_north"  # 안디옥(시리아) 등

    if old_region in SIMPLE_REGION_MAP:
        return SIMPLE_REGION_MAP[old_region]

    raise ValueError(f"Unknown old region: {old_region} (place={place_name})")


# 옛 v2 lm_xxx 코드 → v1 simple code (좌표 룩업용)
def v2_to_v1_code(v2_code: str) -> str:
    if not v2_code:
        return ""
    s = v2_code.removeprefix("lm_")
    # mt_ → mount_
    if s.startswith("mt_"):
        s = "mount_" + s[3:]
    return s


def parse_old_sql() -> dict[str, dict]:
    """옛 v1 landmarks_seed.sql 파싱 → {code: {name, lat, lng, category, emoji}}."""
    if not OLD_SQL_PATH.exists():
        return {}
    text = OLD_SQL_PATH.read_text()
    # values 라인은 들여쓰기 4 공백 + ('code', 'name', '...', 'emoji', 'category', lat, lng, ...
    # 줄별로 처리해 multiline 회피.
    out: dict[str, dict] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("('") or not (
            line.endswith(",") or line.endswith(");") or line.endswith(")")
        ):
            continue
        # quotes 안 처리하면서 컬럼 분리
        # 간단 파싱: split with respecting quotes
        parts = _split_csv_quoted(line)
        if len(parts) < 8:
            continue
        try:
            code = parts[0].strip().strip("'")
            name = parts[1].strip().strip("'")
            emoji = parts[3].strip().strip("'")
            category = parts[4].strip().strip("'")
            lat = float(parts[5].strip())
            lng = float(parts[6].strip())
        except (ValueError, IndexError):
            continue
        out[code] = dict(name=name, lat=lat, lng=lng, category=category, emoji=emoji)
    return out


def _split_csv_quoted(s: str) -> list[str]:
    """간단한 CSV-with-quotes split. SQL row 의 첫 괄호 안 컬럼들."""
    inner = s[s.index("(") + 1 : s.rindex(")")]
    out, buf, in_str = [], [], False
    i = 0
    depth = 0  # ARRAY[...] 같은 중첩 처리
    while i < len(inner):
        c = inner[i]
        if c == "'" and (i == 0 or inner[i - 1] != "\\"):
            # SQL '' (escaped quote)?
            if in_str and i + 1 < len(inner) and inner[i + 1] == "'":
                buf.append("'")
                i += 2
                continue
            in_str = not in_str
            buf.append(c)
        elif c in ("[", "(") and not in_str:
            depth += 1
            buf.append(c)
        elif c in ("]", ")") and not in_str:
            depth -= 1
            buf.append(c)
        elif c == "," and not in_str and depth == 0:
            out.append("".join(buf))
            buf = []
        else:
            buf.append(c)
        i += 1
    if buf:
        out.append("".join(buf))
    return out


# 이름 → kind 추정 (옛 category 활용 + 키워드 폴백)
KIND_FROM_CATEGORY = {
    "city": "city",
    "battle": "city",
    "holy_site": "holy_site",
    "temple": "holy_site",
    "monument": "holy_site",
    "mountain": "mountain",
    "water": "river",
    "river": "river",
    "sea": "sea",
    "wilderness": "wilderness",
    "campsite": "campsite",
    "palace": "palace",
    "prison": "city",
    "oasis": "city",
    "region_label": "wilderness",
    "garden": "holy_site",
}


def estimate_kind(name: str, category: str | None) -> str:
    if category and category in KIND_FROM_CATEGORY:
        return KIND_FROM_CATEGORY[category]
    n = name
    if "산" in n or "산지" in n:
        return "mountain"
    if "강" in n or "시내" in n or "여울" in n:
        return "river"
    if "바다" in n or "호수" in n or "해" in n:
        return "sea"
    if "광야" in n or "사막" in n:
        return "wilderness"
    if "섬" in n:
        return "island"
    if "궁" in n or "왕궁" in n or "수산궁" in n:
        return "palace"
    if "성전" in n or "회당" in n or "동산" in n or "골고다" in n or "겟세마네" in n:
        return "holy_site"
    if "진영" in n or "장막" in n:
        return "campsite"
    return "city"  # 기본


def main():
    mapping = json.loads(MAP_PATH.read_text())
    old_coords = parse_old_sql()
    print(f"옛 v1 좌표 추출: {len(old_coords)}")

    rows = mapping["rows"]
    print(f"사건: {len(rows)}")

    # unique (era, old_lm_code) → 새 landmark
    new_landmarks: dict[tuple, dict] = {}  # (era, lm_code) → {...}
    event_region_map = []  # 각 사건의 (story_index, region_code, landmark_code)

    unmatched_coords = []

    for r in rows:
        era = r["era"]
        old_lm = r["landmark_code"]
        place = r["place_name"]
        old_region = r["region_code"]

        new_region = resolve_ambiguous_region(old_region, place, old_lm, era)

        # 새 landmark code: lm_<era_short>_<old_lm_clean>
        era_short = ERA_SHORT.get(era, era.replace("era_", ""))
        old_clean = old_lm.removeprefix("lm_") if old_lm else "unknown"
        new_lm_code = f"lm_{era_short}_{old_clean}"

        # 좌표 룩업
        v1_code = v2_to_v1_code(old_lm)
        coords = old_coords.get(v1_code)

        # 별칭 시도 (rachel_tomb, mount_moriah 등)
        if coords is None:
            # mount_xxx → xxx 또는 mt_xxx
            for k in old_coords:
                if (
                    k.replace("mount_", "mt_") == v1_code
                    or k.replace("mt_", "mount_") == v1_code
                ):
                    coords = old_coords[k]
                    break

        if coords is None:
            unmatched_coords.append((era, old_lm, place, v1_code))

        key = (era, old_lm)
        if key not in new_landmarks:
            new_landmarks[key] = {
                "code": new_lm_code,
                "name": place,  # place_name 우선 (사건 관점)
                "kind": estimate_kind(
                    place, coords.get("category") if coords else None
                ),
                "emoji": coords.get("emoji", "📍") if coords else "📍",
                "lat": coords.get("lat") if coords else None,
                "lng": coords.get("lng") if coords else None,
                "parent_region_code": new_region,
                "era_codes": [era],
                "display_priority": 50,
            }

        event_region_map.append(
            {
                "story_index": r["story_index"],
                "title": r["title"],
                "era": era,
                "place_name": place,
                "region_code": new_region,
                "landmark_code": new_lm_code,
            }
        )

    # 좌표 없는 landmark 보고
    print()
    print(f"좌표 매칭 실패: {len(unmatched_coords)}")
    for e, lc, pn, v1 in unmatched_coords[:20]:
        print(f"  {e:25s} {lc:30s} → v1='{v1}' ({pn})")

    # landmarks.json 의 landmarks 배열에 채우기
    ldata = json.loads(LANDMARKS_PATH.read_text())
    ldata["landmarks"] = sorted(new_landmarks.values(), key=lambda x: x["code"])
    # anchors/minors 키는 빈 배열로
    ldata.pop("anchors", None)
    ldata.pop("minors", None)
    ldata["landmarks_count"] = len(ldata["landmarks"])
    LANDMARKS_PATH.write_text(json.dumps(ldata, ensure_ascii=False, indent=2) + "\n")
    print()
    print(f"landmarks.json 의 landmarks: {len(ldata['landmarks'])} 개 채움")

    # event_region_mapping 별도 파일
    EVENT_REGION_OUT.write_text(
        json.dumps(
            {
                "_doc": "사건 → 새 region/landmark 매핑. Phase 3 에서 events 데이터에 적용.",
                "rows": event_region_map,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n"
    )
    print(f"event_region_mapping.json: {len(event_region_map)} 사건 매핑 저장")

    # 새 region 별 landmark 수
    by_region = defaultdict(int)
    for lm in new_landmarks.values():
        by_region[lm["parent_region_code"]] += 1
    print()
    print("새 region 별 landmark 수:")
    for r, c in sorted(by_region.items(), key=lambda x: -x[1]):
        print(f"  {r}: {c}")


if __name__ == "__main__":
    main()
