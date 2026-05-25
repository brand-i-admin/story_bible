# 테스트 도메인 레퍼런스

> 이 문서는 `.agents/skills/testing` 스킬이 참조하는 테스트 전략 가이드이다.

## 1. 파일 범위

```
test/
├── widget_test.dart           # Flutter sanity test
├── models/                    # 모델 단위 테스트
├── state/                     # Controller/Provider 테스트
├── data/                      # Repository 테스트 (mock)
└── widgets/                   # 위젯 테스트

.pre-commit-config.yaml        # pre-commit/pre-push 훅
analysis_options.yaml           # 린트 규칙
pubspec.yaml                   # dev_dependencies
tools/**/test_*.py             # Python 도구 단위 테스트
```

## 2. 테스트 전략

### 2.1 테스트 피라미드

```
          ╱╲
         ╱  ╲          Integration (Supabase 연결)
        ╱────╲         - 향후 CI에서 dev Supabase 연결
       ╱      ╲
      ╱ Widget  ╲      Widget Tests
     ╱──────────╲     - 주요 위젯 렌더링 + 인터랙션
    ╱            ╲
   ╱    Unit      ╲   Unit Tests
  ╱────────────────╲  - 모델 fromMap, Controller 로직
```

### 2.2 우선순위

| 순위 | 영역 | 이유 |
|------|------|------|
| 1 | models/ | 순수 함수, 외부 의존성 없음 |
| 2 | state/ | StoryController 비즈니스 로직 |
| 3 | data/ | Repository mock 테스트 |
| 4 | widgets/ | UI 렌더링 + 사용자 인터랙션 |

### 2.3 커버리지 목표 (초기)

| 영역 | 목표 |
|------|------|
| models/ | 100% (fromMap, getter, 유틸리티) |
| state/ | 80% (Controller 메서드, 상태 전환) |
| data/ | 60% (핵심 쿼리 로직) |
| widgets/ | 50% (핵심 위젯 렌더링) |

## 3. TDD 규칙

1. **새 기능은 테스트 먼저 작성** (Red → Green → Refactor)
2. **버그 수정 시 실패 테스트 먼저** 추가 → 수정 → 통과 확인
3. **리팩토링 전에 기존 테스트 확인** → 리팩토링 → 테스트 통과 유지

## 4. Mock 패턴

### 4.1 mocktail 사용

```dart
// dev_dependencies에 추가
// mocktail: ^1.0.4

import 'package:mocktail/mocktail.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockStoryRepository extends Mock implements StoryRepository {}
class MockUserRepository extends Mock implements UserRepository {}
```

### 4.2 Riverpod 테스트 패턴

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ProviderContainer container;
  late MockStoryRepository mockRepo;

  setUp(() {
    mockRepo = MockStoryRepository();
    container = ProviderContainer(
      overrides: [
        storyRepositoryProvider.overrideWithValue(mockRepo),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('selectEra loads characters and events', () async {
    when(() => mockRepo.fetchCharactersByEra(any()))
        .thenAnswer((_) async => [/* mock characters */]);
    when(() => mockRepo.fetchEventsByEra(any()))
        .thenAnswer((_) async => [/* mock events */]);

    final controller = container.read(storyControllerProvider.notifier);
    await controller.selectEra('test-era-id');

    final state = container.read(storyControllerProvider);
    expect(state.persons, isNotEmpty);
    expect(state.events, isNotEmpty);
  });
}
```

### 4.3 모델 테스트 패턴

```dart
void main() {
  group('Era.fromMap', () {
    test('parses valid map', () {
      final map = {
        'id': 'test-id',
        'code': 'era_primeval',
        'testament': 'old',
        'name': '태초',
        'display_order': 1,
        'start_year': -4000,
        'end_year': -2000,
        'map_center_lat': 31.0,
        'map_center_lng': 47.0,
        'map_zoom': 5.0,
      };
      final era = Era.fromMap(map);
      expect(era.code, 'era_primeval');
      expect(era.testament, 'old');
    });

    test('handles null testament as old', () {
      final map = {
        'id': 'test-id', 'code': 'era_test', 'name': '테스트',
        'display_order': 1,
      };
      final era = Era.fromMap(map);
      expect(era.testament, 'old');
    });
  });
}
```

## 5. Pre-commit / Pre-push 훅

### 현재 구성 (`.pre-commit-config.yaml`)

#### pre-commit 단계 (커밋 시)
- `check-added-large-files` — 대용량 파일 차단
- `check-merge-conflict` — 머지 충돌 마커 검사
- `check-yaml` — YAML 문법 검사
- `end-of-file-fixer` — 파일 끝 개행
- `trailing-whitespace` — 후행 공백 제거
- `black` — Python 포맷 (`tools/*.py`)
- `dart-format` — Dart 포맷 (`.dart` 파일)

#### pre-push 단계 (푸시 시)
- `flutter analyze` — 린트 검사
- `flutter test` — 전체 테스트
- `verify-asset-paths` — pubspec assets 경로 검증
- `verify-polygons-contain-events` — 사건 좌표가 region polygon 안에 있는지 검증
- `python-tools-test` — `tools/**/test_*.py` 단위 테스트
- `code-metrics` — 파일/메소드 크기 보고

#### 수동 로컬 검증
- `tools/supabase/check_edge_functions.sh` — Deno 로 Supabase Edge Function
  `index.ts` 타입 체크. CI 의 edge-functions job 과 같은 목적이며, Deno/npm
  캐시가 없으면 첫 실행 때 네트워크가 필요하다.

### 실행 명령어

```bash
# 커밋 전 수동 실행
pre-commit run --all-files

# 푸시 전 수동 실행
pre-commit run --hook-stage pre-push --all-files

# Flutter 개별
flutter analyze
flutter test
flutter test --coverage  # 커버리지 포함
python3 tools/run_unit_tests.py
tools/supabase/check_edge_functions.sh
```

## 6. 린트 규칙

`analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
```

- Flutter 공식 추천 린트 세트 + `analysis_options.yaml`의 프로젝트 추가 규칙 사용

## 7. 테스트 디렉토리 명명 규칙

```
test/
├── models/
│   ├── era_test.dart
│   ├── character_test.dart
│   ├── story_event_test.dart
│   └── bible_verse_test.dart
├── state/
│   └── story_controller_test.dart
├── data/
│   ├── story_repository_test.dart
│   └── user_repository_test.dart
└── widgets/
    ├── era_selector_test.dart
    ├── search_box_test.dart
    └── character_panel_test.dart
```

- 파일명: `{원본파일명}_test.dart`
- 경로: 원본 `lib/` 구조를 미러링
- 그룹: `group('클래스명', () { ... })`
- 테스트명: 한국어 또는 영어 설명 (`'parses valid map'`)

## 8. 코드 메트릭 검사

`tools/lint/check_code_metrics.py`가 파일/메소드 크기를 자동 검사한다:

| 항목 | 경고 기준 | 차단 기준 |
|------|----------|----------|
| 파일 줄 수 | 500줄 | 1,500줄 |
| 메소드/함수 수 | 20개 | 40개 |
| 단일 메소드 줄 수 | 80줄 | 200줄 |

- `test/` 파일은 기준이 2배로 완화
- `part of` 파일은 부모에 귀속되므로 자동 제외
- CI에서 보고 모드로 자동 실행한다. 기존 차단 기준 초과 항목을 정리한 뒤
  `--ci` 플래그를 추가하면 차단 모드로 전환할 수 있다.

```bash
python3 tools/lint/check_code_metrics.py        # 보고 모드
python3 tools/lint/check_code_metrics.py --ci    # 차단 모드 (FAIL 시 exit 1)
```

## 9. Golden Test (UI 스크린샷 비교)

**목적**: 위젯 렌더링 결과를 "골든 이미지(정답 스크린샷)"와 픽셀 단위로 비교하여 UI regression 자동 감지.

**세팅 완료 사항**:
- `golden_toolkit` dev_dependency 설치
- `test/flutter_test_config.dart` — 폰트 로딩 설정

**사용법**:
```dart
// test/golden/my_widget_golden_test.dart
import 'package:golden_toolkit/golden_toolkit.dart';

testGoldens('MyWidget 스냅샷', (tester) async {
  await tester.pumpWidgetBuilder(
    const MyWidget(),
    surfaceSize: const Size(200, 200),
  );
  await screenMatchesGolden(tester, 'my_widget_snapshot');
});
```

```bash
# 골든 이미지 생성/갱신
flutter test --update-goldens test/golden/

# 골든 비교 실행 (차이 나면 실패)
flutter test test/golden/
```

**주의사항**:
- `Image.asset`을 사용하는 위젯은 테스트 환경에서 에셋 로드 실패 → `errorBuilder` 표시됨. 이런 위젯은 mock image provider를 주입하거나 에셋 번들을 세팅해야 함.
- 골든 이미지는 OS/Flutter 버전에 따라 렌더링이 미묘하게 다를 수 있음 → CI에서는 특정 Flutter 버전 고정 필요.
- `.gitignore`에 `test/golden/failures/` 추가 (실패 diff 이미지 제외).

## 10. 테스트 현황 (2026-04-22)

| 영역 | 파일 수 | 테스트 수 | 커버리지 |
|------|---------|----------|---------|
| 모델 fromMap/로직 | 10+ | 50+ | ✅ 전체 모델 완전 (AppNotification 포함) |
| 상태 (Controller + State) | 2 | 38 | ✅ 주요 메소드 27개 + copyWith 11개 |
| 리포지토리 순수 함수 | 2 | 29 | ✅ @visibleForTesting 전부 |
| 유틸 순수 함수 | 4 | 70 | ✅ 전 함수 완전 |
| 위젯 | 2+ | 15+ | CharacterAvatar + NotificationDeepLink 파서 |
| 기본 | 1 | 1 | sanity |
| **합계 (최근 기준)** | **21+** | **214** | — |

> 정확한 수치는 `flutter test` 실행 시 마지막 줄 `All tests passed!` 앞의 카운트로 확인.
