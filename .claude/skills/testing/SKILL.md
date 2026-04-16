---
name: testing
description: "테스트 작성/실행/TDD 워크플로우에 사용하는 스킬. docs/TESTING.md를 참조하여 test/ 범위에서 작업한다."
---

# Testing

## 개요

단위 테스트, 위젯 테스트, TDD 워크플로우를 수행할 때 사용한다.

## 작업 순서

1. 먼저 `docs/TESTING.md`를 읽어 테스트 전략, Mock 패턴, 디렉토리 구조를 파악한다.
2. TDD 방식으로 작업한다:
   - Red: 실패하는 테스트 먼저 작성
   - Green: 최소한의 코드로 테스트 통과
   - Refactor: 코드 정리 (테스트 유지)
3. 테스트 파일 위치:
   - `test/models/` — 모델 단위 테스트
   - `test/state/` — Controller/Provider 테스트
   - `test/data/` — Repository 테스트 (mocktail mock)
   - `test/widgets/` — 위젯 렌더링 테스트
4. Mock 작성:
   - `mocktail` 패키지 사용
   - `MockSupabaseClient`, `MockStoryRepository` 등
   - Riverpod: `ProviderContainer` + `overrides`
5. 실행 및 검증:
   - `flutter test` — 전체 테스트
   - `flutter test test/models/` — 특정 디렉토리
   - `flutter test --coverage` — 커버리지
   - `flutter analyze` — 린트 (테스트 코드 포함)

## 파일 범위

```
test/
├── widget_test.dart           # 기존 sanity test
├── models/                    # 모델 단위 테스트
├── state/                     # Controller 테스트
├── data/                      # Repository 테스트
└── widgets/                   # 위젯 테스트

.pre-commit-config.yaml        # 훅 설정
analysis_options.yaml           # 린트 규칙
```

## 이 저장소 기본값

- `flutter_test` SDK + `mocktail` (dev dependency)
- `flutter_lints` 5.0 린트 규칙
- pre-push 단계에서 `flutter test` 실행
- 테스트 파일명: `{원본}_test.dart`
- 그룹: `group('ClassName', () { ... })`

## 가드레일

- `docs/TESTING.md`를 읽지 않고 테스트를 작성하지 않는다.
- 기존 Mock 패턴(mocktail)을 따른다.
- Supabase에 직접 연결하는 테스트를 단위 테스트에 넣지 않는다 (mock 사용).
- 테스트가 통과하지 않는 상태로 커밋하지 않는다.
- 새 기능/버그 수정 시 반드시 테스트를 먼저 작성한다 (TDD).

## 문서 동기화

테스트 구조/전략/커버리지가 변경되면 **같은 커밋에서** 아래도 갱신한다. (CLAUDE.md 「문서 동기화 규칙」 참조)

- `docs/TESTING.md` — 디렉토리 구조, Mock 패턴, 커버리지 목표, 현재 테스트 개수
- `.pre-commit-config.yaml` — pre-push hook 검증 규칙이 바뀌면
- 테스트 대상 코드를 `@visibleForTesting`으로 노출한 경우 원본 파일 근처 주석/문서도 반영

## Mock 예시

```dart
import 'package:mocktail/mocktail.dart';

class MockStoryRepository extends Mock implements StoryRepository {}

// Riverpod 테스트
final container = ProviderContainer(
  overrides: [
    storyRepositoryProvider.overrideWithValue(MockStoryRepository()),
  ],
);
```
