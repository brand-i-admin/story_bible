# 테스트 도메인 레퍼런스

> 이 문서는 `.agents/skills/testing` 스킬이 참조하는 테스트 전략 가이드이다.
> 현재 테스트 파일/정적 테스트 수 카탈로그는 [docs/guides/TEST_GUIDE.md](guides/TEST_GUIDE.md)를 우선한다.

## 1. 파일 범위

```
test/
├── widget_test.dart           # Flutter sanity test
├── models/                    # 모델 단위 테스트
├── state/                     # Controller/Provider 테스트
├── data/                      # Repository 테스트 (mock)
├── theme/                     # 디자인 토큰 테스트
├── utils/                     # 순수 로직/asset loader 테스트
└── widgets/                   # 위젯 테스트

.pre-commit-config.yaml        # pre-commit/pre-push 훅
analysis_options.yaml           # 린트 규칙
pubspec.yaml                   # dev_dependencies
integration_test/              # dev Supabase 연결 실기기/에뮬레이터 흐름
tools/**/test_*.py             # Python 도구 단위 테스트
```

Flutter 테스트 런타임과 CI는 Flutter 3.44.7 stable / Dart 3.12 이상을 기준으로
한다. 패치 버전 차이로 렌더링·분석 결과가 달라지지 않도록 CI는 3.44.7을 고정한다.

## 2. 테스트 전략

### 2.1 테스트 피라미드

```
          ╱╲
         ╱  ╲          Integration (dev Supabase 연결)
        ╱────╲         - Android 에뮬레이터/실기기 수동 실행
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

### 2.4 통합 테스트

`integration_test/divided_kingdom_flow_test.dart`는 새 설치의 기본 상태와 지도
탐색의 실제 데이터 연결을 검증한다.

- 첫 화면: `오늘` 탭 선택
- 접근성 기본값: `보통` 글자(1.2배)
- 색 조합 기본값: `네이비`
- 지도 탭: 분열왕국의 남유다/북이스라엘 사건과 인물 첫 등장 순서

콘텐츠가 늘어날 때마다 전체 제목·인원 수를 소스에 고정하지 않는다. 현재 Supabase가
반환한 사건·랜드마크·인물에서 기대 순서를 계산하고, 제품 계약에 중요한 대표
사건과 인물은 별도로 확인한다. 테스트 시작 전 글자 크기와 색 조합 저장 키를
지워 새 설치 상태를 재현한다.

```bash
set -a
source .env
set +a
flutter test integration_test/divided_kingdom_flow_test.dart -d <device-id> \
  --dart-define=ENV=dev \
  --dart-define=SUPABASE_URL="$SUPABASE_URL_DEV" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY_DEV"
```

dev Supabase와 Android 에뮬레이터/실기기가 필요한 테스트라 CI 기본 job에는 넣지
않는다. Flutter SDK 또는 지도·홈 기본 동작을 바꿀 때 수동으로 함께 실행한다.

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
- `black` — Python 포맷 (`tools/seed|images|app|lint|export|docs`)
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

## 10. 테스트 현황 (2026-07-22)

| 영역 | 파일 수 | 테스트 수 | 커버리지 |
|------|---------|----------|---------|
| 모델 fromMap/로직 | 15 | 87 | Supabase row와 불변 모델 계약 |
| 상태 (Controller + State) | 3 | 67 | Riverpod 상태 전환과 사용자 기록 동기화 |
| 리포지토리 | 7 | 45 | Supabase 쿼리, row 변환, fallback |
| 서비스 | 4 | 18 | Firebase 이벤트·개인정보·수집 정책, 인증 스트림 오류 격리 |
| 유틸 | 12 | 149 | 날짜, 지도, 에셋, 선택·통독 순수 로직 |
| 화면·위젯·테마 | 41 | 324 | 화면 입력과 주요 UI·디자인 토큰 |
| 기본 | 2 | 4 | 앱 smoke와 scaffold |
| **합계 (정적 호출 기준)** | **84** | **694** | — |

> 정확한 수치는 `flutter test` 실행 시 마지막 줄 `All tests passed!` 앞의 카운트로 확인.
> `integration_test/`의 실환경 시나리오 3개는 이 정적 단위/위젯 테스트 합계와 별도다.
