---
name: frontend
description: "Story Bible Flutter 프론트엔드 작업 스킬. UI, 위젯, 화면, Riverpod 상태, 모델, 테마, 레이아웃, 한국어 사용자 문구를 수정할 때 사용한다."
---

# Frontend

## 작업 순서

1. 현재 구조와 패턴을 확인하기 위해 `docs/FRONTEND.md`를 읽는다.
2. 시각/상호작용 작업이면 `docs/UI_GUIDE.md`도 함께 읽는다.
3. 수정 전 관련 테스트를 `test/`에서 찾는다.
4. 기존 Riverpod, model, widget, theme 패턴을 따른다.
5. 파일 지도, 위젯 목록, 디자인 규칙, 상태 구조가 바뀌면 문서를 갱신한다.
6. 변경 범위에 맞게 focused test를 먼저 돌리고, 필요하면 `dart format`, `flutter analyze`, `flutter test`까지 실행한다.

## 기본값

- Riverpod 2.6: `NotifierProvider`, 불변 state, repository provider.
- 위젯은 보통 `ConsumerWidget` 또는 `ConsumerStatefulWidget`이다.
- 모델은 불변 데이터 클래스이며 Supabase row 기반 모델은 `fromMap()`을 쓴다.
- 사용자에게 보이는 UI 문구는 한국어로 쓴다.
- 새 UI는 `lib/theme/`의 `AppColors`, `AppSpacing`, `AppRadii`, `AppShadows`, `AppTextStyles`, `AppSurfaces`를 우선 사용한다.
- 기존 양피지/게임풍 장식 표면의 inline 색은 유지 가능하지만, 새 ad-hoc hex 색을 추가하기 전 토큰을 먼저 검토한다.

## PDCA 적용

- Plan: 화면/상태/테스트/문서 영향 범위를 먼저 확인한다.
- Do: 기존 위젯 구조와 디자인 토큰을 따라 작게 수정한다.
- Check: UI 문구, layout overflow 가능성, 관련 문서 갱신 여부를 보고 focused widget/unit test 후 `dart format`, `flutter analyze`, 필요 시 `flutter test`를 실행한다.
- Act: 실패한 테스트나 overflow 가능성을 반영해 재수정하거나, 통과 결과와 잔여 리스크를 보고한다.

## 가드레일

- 관련 문서와 주변 구현을 확인하기 전에 UI 코드를 바로 수정하지 않는다.
- 비즈니스 로직을 model에 넣지 않는다. controller/repository 또는 순수 util로 둔다.
- 기존 테스트를 조용히 바꾸지 않는다. 테스트 변경은 스펙 변경이므로 범위와 이유를 분명히 한다.
- 모바일/데스크톱 레이아웃이 모두 자연스러워야 한다. 라벨 추가 시 text overflow 위험을 확인한다.

## 함께 갱신할 문서

- `docs/FRONTEND.md`: 새/이동/삭제된 screen, widget, model, provider.
- `docs/UI_GUIDE.md`: 시각, 레이아웃, 지도, 접근성, 상호작용 규칙 변화.
- `docs/ARCHITECTURE.md`: 큰 구조 변화.
