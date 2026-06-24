#!/usr/bin/env python3
"""Align event lat/lng to matching landmark coordinates.

이벤트의 place_name 또는 title 에 특정 키워드가 들어있으면 그 키워드와 매칭되는
landmark 의 정확한 좌표로 lat/lng 를 업데이트한다. 핀이 흩어져 보이는 문제 방지
+ 같은 장소를 가리키는 이벤트가 같은 좌표에 모이도록.

사용:
    python tools/seed/align_events_to_landmarks.py            # apply (수정 저장)
    python tools/seed/align_events_to_landmarks.py --dry-run  # 변경 사항만 출력
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

# (place_name 또는 title 에 들어가는 키워드, 매칭할 landmark code)
# 우선순위: 더 구체적인 키워드를 먼저 (막벨라 > 헤브론, 모리아 > 예루살렘 등).
# 첫 매칭 발견 시 즉시 적용.
KEYWORD_TO_LANDMARK: list[tuple[str, str]] = [
    # 가장 구체적인 키워드 먼저
    ("막벨라", "machpelah"),
    ("모리아", "mount_moriah"),
    ("라헬 무덤", "rachel_tomb"),
    ("라헬의 죽음", "rachel_tomb"),
    ("브니엘", "peniel"),
    ("브엘세바", "beersheba"),
    ("도단", "dothan"),
    ("바벨탑", "tower_of_babel"),
    ("아라랏", "mount_ararat"),
    ("에덴", "garden_of_eden"),
    ("우르", "ur"),
    ("하란", "haran"),
    ("소돔", "sodom"),
    ("고센", "goshen"),
    ("라암셋", "rameses"),
    ("떨기나무", "burning_bush"),
    ("홍해", "red_sea"),
    ("르비딤", "rephidim"),
    ("시내산", "mount_sinai"),
    ("호렙", "mount_sinai"),
    ("가데스", "kadesh_barnea"),
    ("느보산", "mount_nebo"),
    ("여리고", "jericho"),
    ("아이성", "ai"),
    ("길갈", "gilgal"),
    ("실로", "shiloh"),
    ("다볼산", "mount_tabor"),
    ("미스바", "mizpah"),
    ("길보아", "mount_gilboa"),
    ("엔돌", "endor"),
    ("엘라 골짜기", "elah_valley"),
    ("골리앗", "elah_valley"),  # 다윗-골리앗 사건 연결
    ("갈멜", "mount_carmel"),
    ("사르밧", "zarephath"),
    ("사마리아", "samaria"),
    ("벧엘", "bethel"),
    ("기손", "kishon_river"),
    ("그릿", "brook_cherith"),
    ("므깃도", "megiddo"),
    ("아마겟돈", "megiddo"),
    ("하솔", "hazor"),
    ("헤스본", "heshbon"),
    ("벳새다", "bethsaida"),
    ("고라신", "chorazin"),
    ("가버나움", "capernaum"),
    ("나사렛", "nazareth"),
    # "가나" 는 "가나안" 과 substring 충돌 — 현재 데이터에 cana 이벤트가 별도 가나
    # place_name 으로 들어 있지 않으므로 키워드 매핑에서 제외. 추후 가나 사건이
    # 명확한 place_name 으로 추가되면 ("가나(갈릴리)" 같이) 다시 등록.
    ("베다니", "bethany"),
    ("게쎄마네", "gethsemane"),
    ("겟세마네", "gethsemane"),
    ("감람산", "gethsemane"),
    ("골고다", "golgotha"),
    ("게헨나", "gehenna"),
    ("수가", "sychar_well"),
    ("수가성", "sychar_well"),
    ("야곱의 우물", "sychar_well"),
    ("데가볼리", "decapolis"),
    ("두로", "tyre"),
    ("가이사랴 빌립보", "caesarea_philippi"),
    ("가이사랴 마리티마", "caesarea_maritima"),
    ("헤르몬", "mount_hermon"),
    ("변화산", "mount_hermon"),
    ("다소", "tarsus"),
    ("살라미", "salamis_cyprus"),
    ("비시디아 안디옥", "antioch_pisidia"),
    ("안디옥", "antioch_syria"),  # 비시디아 보다 뒤에 — "비시디아 안디옥" 우선
    ("루스드라", "lystra"),
    ("빌립보", "philippi"),
    ("데살로니가", "thessalonica"),
    ("베뢰아", "berea"),
    ("아덴", "athens"),
    ("아테네", "athens"),
    ("고린도", "corinth"),
    ("에베소", "ephesus"),
    ("밀레도", "miletus"),
    ("멜리데", "malta"),
    ("몰타", "malta"),
    ("드로아", "troas"),
    ("앗소", "assos"),
    ("로마", "rome"),
    ("밧모", "patmos"),
    ("서머나", "smyrna"),
    ("버가모", "pergamon"),
    ("두아디라", "thyatira"),
    ("사데", "sardis"),
    ("빌라델비아", "philadelphia"),
    ("라오디게아", "laodicea"),
    ("욥바", "joppa"),
    ("니느웨", "nineveh"),
    ("바벨론", "babylon"),
    ("그발", "kebar_river"),
    ("수사", "susa"),
    ("다메섹 문", "jerusalem_damascus_gate"),
    ("다메섹", "damascus"),  # 다메섹 문 보다 뒤에 — 더 구체적인 게 우선 매칭
    ("성전", "jerusalem_temple"),
    # 가장 일반적인 키워드 마지막
    ("마므레", "hebron"),  # 마므레 = 헤브론 일대 (마므레 상수리)
    ("헤브론", "hebron"),
    ("예루살렘", "jerusalem_temple"),
    ("유다 광야", "judean_wilderness"),
    ("신 광야", "wilderness_of_zin"),
    ("바란 광야", "wilderness_of_paran"),
    ("사해", "dead_sea"),
    ("염해", "dead_sea"),
    ("요단", "jordan_river"),
    ("갈릴리 호수", "sea_of_galilee"),
    ("갈릴리 바다", "sea_of_galilee"),
    ("디베랴", "sea_of_galilee"),
    ("게네사렛", "sea_of_galilee"),
    ("베들레헴", "bethlehem"),
    ("세겜", "shechem"),
    ("다윗의 성", "city_of_david"),
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Align event lat/lng to matching landmark coordinates."
    )
    parser.add_argument(
        "--landmarks",
        default="assets/landmarks/landmarks.json",
        help="Landmarks JSON path.",
    )
    parser.add_argument(
        "--stories-dir",
        default="assets/events",
        help="Stories JSON directory.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print changes without writing.",
    )
    return parser.parse_args()


def load_landmark_coords(path: Path) -> dict[str, tuple[float, float]]:
    raw = json.loads(path.read_text(encoding="utf-8"))
    coords: dict[str, tuple[float, float]] = {}
    for item in raw:
        code = str(item["code"]).strip()
        coords[code] = (float(item["lat"]), float(item["lng"]))
    return coords


def find_landmark_for_event(
    event: dict[str, Any],
    keyword_to_landmark: list[tuple[str, str]],
) -> str | None:
    """이벤트의 place_name 만 검사 (title 은 사건 줄거리라 매칭 노이즈가 많음).
    첫 매칭이 우선 — KEYWORD_TO_LANDMARK 의 순서로 specificity 보장."""
    place = str(event.get("place_name", "") or "")
    if not place.strip():
        return None
    for keyword, code in keyword_to_landmark:
        if keyword in place:
            return code
    return None


def coords_close(a: float, b: float, tol: float = 1e-4) -> bool:
    return abs(a - b) < tol


def main() -> int:
    args = parse_args()
    landmarks_path = Path(args.landmarks)
    stories_dir = Path(args.stories_dir)

    landmark_coords = load_landmark_coords(landmarks_path)
    print(f"loaded {len(landmark_coords)} landmarks from {landmarks_path}")

    json_files = sorted(stories_dir.glob("*.json"))
    total_changed = 0
    for jf in json_files:
        rows = json.loads(jf.read_text(encoding="utf-8"))
        if not isinstance(rows, list):
            continue
        file_changed = 0
        for row in rows:
            if not isinstance(row, dict):
                continue
            code = find_landmark_for_event(row, KEYWORD_TO_LANDMARK)
            if code is None or code not in landmark_coords:
                continue
            target_lat, target_lng = landmark_coords[code]
            cur_lat = row.get("lat")
            cur_lng = row.get("lng")
            if cur_lat is None or cur_lng is None:
                continue
            if coords_close(float(cur_lat), target_lat) and coords_close(
                float(cur_lng), target_lng
            ):
                continue
            print(
                f"  [{jf.name}] '{row.get('title','')[:40]}' "
                f"({cur_lat:.4f},{cur_lng:.4f}) → "
                f"{code} ({target_lat:.4f},{target_lng:.4f})"
            )
            row["lat"] = target_lat
            row["lng"] = target_lng
            file_changed += 1
        if file_changed and not args.dry_run:
            jf.write_text(
                json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
                encoding="utf-8",
            )
            print(f"  wrote {file_changed} updates to {jf.name}")
        elif file_changed:
            print(f"  [DRY-RUN] would write {file_changed} updates to {jf.name}")
        total_changed += file_changed

    print(f"\ntotal events updated: {total_changed}")
    if args.dry_run:
        print("DRY-RUN — no files modified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
