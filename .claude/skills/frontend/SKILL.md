---
name: frontend
description: "프론트엔드(UI/위젯/화면/상태/모델) 변경 시 사용하는 스킬. docs/FRONTEND.md와 docs/UI_GUIDE.md를 참조하여 lib/screens/, lib/widgets/, lib/state/, lib/models/ 범위에서 작업한다."
---

# Frontend

## 개요

Flutter 앱의 프론트엔드 도메인(UI, 위젯, 화면, 상태관리, 모델)을 수정할 때 사용한다.

## 작업 순서

1. 먼저 `docs/FRONTEND.md`를 읽어 현재 파일 구조, 상태 관리 패턴, 모델 목록을 파악한다.
2. UI 관련 작업이면 `docs/UI_GUIDE.md`도 함께 읽어 테마, 팔레트, 레이아웃 규칙을 확인한다.
3. 수정 대상 파일을 읽고 현재 코드 패턴을 확인한다.
4. 변경을 구현한다:
   - 모델: 순수 데이터 클래스, `fromMap()` 팩토리 패턴 유지
   - 상태: `StoryState.copyWith()` 패턴, `StoryController`에서 비즈니스 로직
   - 위젯: `ConsumerWidget` 또는 `ConsumerStatefulWidget` (Riverpod)
   - UI 텍스트: 한국어
   - 색상: `docs/UI_GUIDE.md`의 팔레트 참조
5. 변경 후 검증한다:
   - `dart format --output=none --set-exit-if-changed .`
   - `flutter analyze`
   - `flutter test`

## 파일 범위

```
lib/
├── main.dart
├── app.dart
├── models/          (모든 데이터 모델)
├── state/           (Riverpod Provider/Notifier)
├── screens/         (전체 화면 위젯)
└── widgets/         (재사용 UI 컴포넌트)
```

## 이 저장소 기본값

- Riverpod 2.6 사용 — Provider, Notifier 패턴
- Material3 + 커스텀 양피지 테마 (`Color(0xFFEEE0C6)`)
- 인물 색상 팔레트 8색 고정 (StoryController._palette)
- 반응형: Desktop ≥1280, Tablet 900~1279, Mobile <900

## 가드레일

- `docs/FRONTEND.md`를 읽지 않고 코드를 수정하지 않는다.
- 기존 위젯 패턴(ConsumerWidget, GameUiSkin 등)을 따른다.
- 새 모델에 비즈니스 로직을 넣지 않는다 (Controller에서 처리).
- 새 기능은 테스트를 먼저 작성한다 (TDD).

## 문서 동기화

프론트엔드 파일(`lib/screens/`, `lib/widgets/`, `lib/state/`, `lib/models/`)에 추가/이동/삭제/큰 변경이 있으면 **같은 커밋에서** 아래 문서도 갱신한다. (CLAUDE.md 「문서 동기화 규칙」 참조)

- `docs/FRONTEND.md` — 화면/위젯/모델 표, 의존 패키지 목록, Riverpod Provider 트리
- `docs/UI_GUIDE.md` — 새 UI 패턴, 색상·테마·레이아웃 규칙 변경
- `docs/ARCHITECTURE.md` — 대규모 구조 변경 시 다이어그램/섹션 3 (화면 구성)
