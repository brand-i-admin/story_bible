# 테스트 가이드 — Story Bible

> 현재 `test/`와 `tools/**/test_*.py` 기준으로 정리한 테스트 지도다.
> 코드나 데이터 파이프라인을 바꿀 때 어느 테스트가 변경 책임을 갖는지 빠르게 찾기
> 위해 사용한다.

## 0. 한 장 요약

| 영역 | 파일 수 | 정적 테스트 수 | 주요 책임 |
|------|---------|----------------|-----------|
| `test/` 루트 | 2 | 4 | 앱 smoke, 기본 widget scaffold |
| `test/models/` | 15 | 89 | 불변 모델, `fromMap()`, enum/값 객체 변환 |
| `test/data/` | 4 | 33 | Repository, Supabase row 변환, fallback |
| `test/state/` | 3 | 25 | Riverpod provider/controller 상태 전환 |
| `test/theme/` | 1 | 14 | 디자인 토큰 회귀 방지 |
| `test/utils/` | 9 | 108 | 날짜, 지도 수학, asset loader, 선택 로직 |
| `test/widgets/` | 27 | 141 | 주요 화면 조각, 다이얼로그, 프로필/지도 UI |
| `tools/**/test_*.py` | 13 | 93 | seed, lint, asset, docs, Supabase 도구 |

Dart 쪽 정적 카운트는 `test/**/*.dart`의 `test()`/`testWidgets()` 호출 기준
445개다. `test/state/story_controller_test_groups.dart`처럼 helper 파일 안에서
공유되는 테스트 그룹도 포함되므로 디렉토리별 단순 합보다 크다.

## 1. 기본 실행 명령

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python3 tools/run_unit_tests.py
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
python3 tools/lint/check_forbidden_patterns.py
python3 tools/lint/check_code_metrics.py
```

커밋/푸시 전에는 로컬 hook도 같은 책임을 나눠 가진다.

| 단계 | 대표 검사 |
|------|-----------|
| pre-commit | forbidden pattern, import sort, black, large file, YAML, whitespace |
| pre-push | `flutter analyze`, `flutter test`, asset path, polygon mapping, Python tool tests, code metrics |
| CI | dummy `.env` 생성 후 pre-commit/pre-push 성격의 검사를 원격에서 재확인 |

## 2. 모델 테스트

`test/models/`는 Supabase row와 앱 모델 사이의 계약을 지킨다.

| 파일 | 확인하는 것 |
|------|-------------|
| `app_notification_test.dart` | 알림 row 파싱, deep link/metadata |
| `app_user_profile_test.dart` | 프로필 모델 기본값과 role |
| `bible_ref_test.dart`, `bible_verse_test.dart`, `saved_bible_verse_test.dart` | 성경 본문/저장 구절 값 변환 |
| `character_test.dart`, `character_study_progress_test.dart` | 인물, 아바타, 학습 진행 모델 |
| `era_test.dart`, `story_event_test.dart`, `landmark_test.dart` | 시대/사건/랜드마크 row 변환 |
| `event_emotion_mark_test.dart`, `intercessory_prayer_item_test.dart` | 감정/기도 모델 |
| `event_proposal_test.dart` | 제안 상태, 제안 payload, 관리자 workflow 데이터 |
| `quiz_attempt_summary_test.dart` | 퀴즈 결과 요약 |
| `user_companion_diary_entry_test.dart` | 오늘의 동행 일지 row 변환 |

새 Supabase row 기반 모델은 `fromMap()` 테스트를 먼저 추가한다. nullable 컬럼,
enum 문자열, JSON list/map 변환은 정상값과 빈값을 같이 넣는다.

## 3. Repository / State 테스트

| 영역 | 파일 | 변경 시 확인 |
|------|------|--------------|
| Repository | `test/data/story_repository_test.dart` | story, era, landmark, event query와 row mapping |
| Repository | `test/data/user_repository_test.dart` | 유저 프로필, 알림, 진행도, 일지 |
| Repository | `test/data/font_scale_repository_test.dart` | 접근성 글자 크기 저장/복원 |
| Repository | `test/data/character_name_fallbacks_test.dart` | 인물 이름 fallback |
| State | `test/state/story_state_test.dart` | `StoryState.copyWith`, 로딩/에러 상태 |
| State | `test/state/story_controller_test.dart` | controller orchestration |
| State | `test/state/story_controller_test_groups.dart` | controller 공유 테스트 그룹 |
| State | `test/state/font_scale_providers_test.dart` | 글자 크기 provider 동작 |

Controller는 `try/catch`와 `state.copyWith(error: ...)` 패턴을 우선한다. 새 실패
경로를 넣으면 성공 테스트만 추가하지 말고 에러 상태 테스트도 함께 둔다.

## 4. Utils 테스트

| 파일 | 책임 |
|------|------|
| `bible_book_meta_test.dart` | 성경 책 메타와 정렬 |
| `daily_exploration_prompt_test.dart` | 오늘의 묵상 prompt 조합 |
| `daily_exploration_selection_test.dart` | 날짜별 탐색 선택 안정성 |
| `home_back_navigation_test.dart` | 홈 back navigation 정책 |
| `kst_date_test.dart` | KST 기준 날짜 계산 |
| `map_math_test.dart` | 지도 좌표/거리 계산 |
| `scene_asset_loader_test.dart` | 장면 썸네일 로컬 우선, Storage fallback |
| `system_insets_test.dart` | 안전영역 inset 계산 |
| `weekly_selection_test.dart` | 주간 선택 로직 |

콘텐츠/지도/날짜 로직은 UI보다 utils에서 먼저 고정한다. pure function으로 뺄 수
있으면 widget test보다 빠르고 회귀 지점도 더 선명하다.

## 5. Widget 테스트

`test/widgets/`는 사용자에게 보이는 한국어 문구, 버튼 노출, 비어 있는 상태,
레이아웃 제약을 확인한다.

대표 그룹:

| 그룹 | 파일 예 |
|------|---------|
| 성경/이야기 | `bible_reader_page_test.dart`, `event_detail_page_test.dart`, `event_timeline_row_test.dart`, `story_scene_row_test.dart` |
| 지도 | `map/map_tile_style_test.dart`, `map/story_terrain_3d_map_marker_test.dart`, `map_hint_overlay_test.dart`, `region_pick_panel_test.dart`, `timeline_unit_pick_panel_test.dart` |
| 퀴즈/제안 | `event_quiz_dialog_test.dart`, `proposal_quiz_editor_test.dart` |
| 프로필 | `profile_*_test.dart`, `saved_verse_row_test.dart` |
| 접근성/공통 UI | `font_scale_bottom_sheet_test.dart`, `pulse_highlight_test.dart`, `story_home_styles_test.dart`, `emotion_badge_icon_test.dart` |
| 알림 | `notification_deep_link_test.dart` |

새 위젯은 raw 색/spacing보다 `lib/theme/` 토큰을 먼저 쓰고, 테스트에서는 깨지기
쉬운 픽셀값보다 실제 동작과 노출 상태를 검증한다.

## 6. Python 도구 테스트

| 디렉토리 | 파일 수 | 테스트 수 | 책임 |
|----------|---------|-----------|------|
| `tools/app` | 1 | 5 | `pubspec.yaml` asset 경로 검증 |
| `tools/docs` | 1 | 3 | `story_guide.md`와 HTML guide 생성 |
| `tools/export` | 1 | 5 | DB events → JSON 역추출 |
| `tools/images` | 2 | 17 | runtime thumbnail, scene utility |
| `tools/lint` | 1 | 5 | secret/forbidden pattern scan |
| `tools/seed` | 5 | 49 | KRV seed, quiz seed, captions, timeline, polygons |
| `tools/supabase` | 2 | 9 | bucket purge, avatar upload |

도구를 추가하면 `tools/<area>/test_*.py`를 같이 추가하고,
`python3 tools/run_unit_tests.py`에 잡히는지 확인한다. Python 코드는 `black`
포맷 대상이며, 현재 pre-commit hook은 `tools/seed|images|app|lint|export|docs`
경로를 포맷한다.

## 7. 변경 유형별 최소 검증

| 변경 | 최소 검증 |
|------|-----------|
| Dart 모델/Repository | 관련 `test/models`, `test/data` + `flutter test` |
| Riverpod 상태 | 관련 `test/state` + 영향을 받는 widget test |
| UI/위젯 | 해당 `test/widgets` + `flutter analyze` |
| 콘텐츠 JSON/seed | `make seed-*`, `python3 tools/seed/verify_polygons_contain_events.py`, 관련 Python tests |
| 이미지/asset | `make thumbnails`, `make update-pubspec-assets`, `python3 tools/app/verify_asset_paths.py` |
| Supabase schema/RLS/RPC | patch SQL 검토, 관련 Repository/RPC 테스트, `docs/BACKEND.md` 동기화 |
| docs/guides | `make build-guides`, `python3 tools/docs/test_build_guides.py`, 링크 검증 |

## 8. 남은 테스트 공백

- Supabase RPC와 RLS는 로컬 unit test보다 SQL 리뷰/patch 검증 의존도가 높다.
- Edge Function은 README와 수동 smoke 중심이며, 자동 통합 테스트는 아직 얕다.
- 제안 승인/수정/삭제 workflow의 end-to-end 테스트는 분산되어 있다.
- 시각 회귀용 golden test는 기본 파이프라인에 강제되어 있지 않다.
- 실기기 푸시 수신은 Firebase/APNs/브라우저 권한이 얽혀 있어 수동 smoke가 필요하다.

이 공백은 위험도가 큰 변경부터 작은 통합 테스트나 smoke checklist로 보강한다.
