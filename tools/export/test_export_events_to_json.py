"""Unit tests for tools/export/export_events_to_json.py.

DB 호출은 mock 으로 대체하고, events row → JSON dict 변환 로직만 검증한다.
실행: pytest tools/export/test_export_events_to_json.py -v
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

# 같은 폴더의 모듈을 import 가능하게.
sys.path.insert(0, str(Path(__file__).parent))

from export_events_to_json import (  # noqa: E402
    bucket_for_story_index,
    event_row_to_json,
    group_events_by_bucket,
)


def test_event_row_to_json_basic_published_row() -> None:
    row = {
        "title": "001 창조: 7일과 안식",
        "era_code": "era_primeval",
        "summary": "하나님이 말씀으로 세상을 창조하신다.",
        "person_codes": ["god"],
        "place_name": "메소포타미아(추정)",
        "lat": 31.018,
        "lng": 47.423,
        "bible_refs": [{"book": "창", "from": "1:1", "to": "2:3"}],
        "start_year": -4000,
        "end_year": -4000,
        "time_precision": "approx",
        "story_index": 1,
        "story_scenes": ["장면 1", "장면 2"],
        "scene_persons": [["god"], []],
    }
    result = event_row_to_json(row)
    assert result["title"] == "001 창조: 7일과 안식"
    assert result["era"] == "era_primeval"
    assert result["persons"] == ["god"]
    assert result["lat"] == 31.018
    assert result["lng"] == 47.423
    assert result["bible_ref"] == [{"book": "창", "from": "1:1", "to": "2:3"}]
    assert result["story_index"] == 1
    assert result["story_scenes"] == ["장면 1", "장면 2"]
    assert result["scene_persons"] == [["god"], []]
    # 키 순서: 사람이 보던 JSON 포맷과 일치
    assert list(result.keys()) == [
        "title",
        "era",
        "persons",
        "place_name",
        "lat",
        "lng",
        "summary",
        "bible_ref",
        "start_year",
        "end_year",
        "time_precision",
        "story_index",
        "story_scenes",
        "scene_persons",
    ]


def test_event_row_to_json_handles_nulls_and_missing_fields() -> None:
    row = {
        "title": "999 빈 이야기",
        "era_code": "era_judges",
        "summary": None,
        "person_codes": None,
        "place_name": None,
        "lat": None,
        "lng": None,
        "bible_refs": None,
        "start_year": None,
        "end_year": None,
        "time_precision": None,
        "story_index": 5,
        "story_scenes": None,
        "scene_persons": None,
    }
    result = event_row_to_json(row)
    assert result["persons"] == []
    assert result["bible_ref"] == []
    assert result["story_scenes"] == []
    assert result["scene_persons"] == []
    assert result["time_precision"] == "approx"
    assert result["lat"] is None
    assert result["summary"] == ""


def test_bucket_for_story_index_uses_50_step_buckets() -> None:
    # 1..50 → "1_50.json", 51..100 → "51_100.json" 등
    assert bucket_for_story_index(1) == "1_50.json"
    assert bucket_for_story_index(50) == "1_50.json"
    assert bucket_for_story_index(51) == "51_100.json"
    assert bucket_for_story_index(100) == "51_100.json"
    assert bucket_for_story_index(101) == "101_150.json"
    assert bucket_for_story_index(184) == "151_200.json"
    assert bucket_for_story_index(215) == "201_250.json"


def test_group_events_by_bucket_groups_and_sorts_within_each_file() -> None:
    rows = [
        {"title": "002 a", "era_code": "era_primeval", "story_index": 2},
        {"title": "001 b", "era_code": "era_primeval", "story_index": 1},
        {"title": "060 c", "era_code": "era_exodus", "story_index": 60},
    ]
    rows_full = [
        {
            **row,
            "summary": "",
            "person_codes": [],
            "place_name": "",
            "lat": None,
            "lng": None,
            "bible_refs": [],
            "start_year": None,
            "end_year": None,
            "time_precision": "approx",
            "story_scenes": [],
            "scene_persons": [],
        }
        for row in rows
    ]
    grouped = group_events_by_bucket(rows_full)
    assert set(grouped.keys()) == {"1_50.json", "51_100.json"}
    titles = [item["title"] for item in grouped["1_50.json"]]
    assert titles == ["001 b", "002 a"]  # story_index 오름차순
    assert grouped["51_100.json"][0]["title"] == "060 c"


def test_round_trip_json_serializable() -> None:
    """결과가 JSON 직렬화 가능해야 한다."""
    row = {
        "title": "001 X",
        "era_code": "era_primeval",
        "summary": "s",
        "person_codes": ["god"],
        "place_name": "p",
        "lat": 1.0,
        "lng": 2.0,
        "bible_refs": [{"book": "창", "from": "1:1", "to": "1:1"}],
        "start_year": -4000,
        "end_year": -4000,
        "time_precision": "approx",
        "story_index": 1,
        "story_scenes": ["scene"],
        "scene_persons": [["god"]],
    }
    out = event_row_to_json(row)
    encoded = json.dumps(out, ensure_ascii=False)
    decoded = json.loads(encoded)
    assert decoded["title"] == "001 X"
