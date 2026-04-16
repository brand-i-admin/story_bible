# 테스트 도메인 레퍼런스

> 이 문서는 `$testing` 스킬이 참조하는 테스트 전략 가이드이다.

## 1. 파일 범위

```
test/
├── widget_test.dart           # 기존 sanity test (1+1=2)
├── models/                    # 모델 단위 테스트
├── state/                     # Controller/Provider 테스트
├── data/                      # Repository 테스트 (mock)
└── widgets/                   # 위젯 테스트

.pre-commit-config.yaml        # pre-commit/pre-push 훅
analysis_options.yaml           # 린트 규칙
pubspec.yaml                   # dev_dependencies
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

  test('selectEra loads persons and events', () async {
    when(() => mockRepo.fetchPersonsByEra(any()))
        .thenAnswer((_) async => [/* mock persons */]);
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
```

## 6. 린트 규칙

`analysis_options.yaml`:
```yaml
include: package:flutter_lints/flutter.yaml
```

- Flutter 공식 추천 린트 세트 사용
- 추가 커스텀 규칙 없음 (필요 시 추가)

## 7. 테스트 디렉토리 명명 규칙

```
test/
├── models/
│   ├── era_test.dart
│   ├── person_test.dart
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
    └── person_panel_test.dart
```

- 파일명: `{원본파일명}_test.dart`
- 경로: 원본 `lib/` 구조를 미러링
- 그룹: `group('클래스명', () { ... })`
- 테스트명: 한국어 또는 영어 설명 (`'parses valid map'`)
