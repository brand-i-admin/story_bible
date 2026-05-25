---
name: refactor
description: "Story Bible 리팩터링 작업 스킬. 대형 파일 분리, 공유 위젯 추출, 중복 제거, 상태 분해, 순수 유틸 추출, 동작 보존형 구조 정리에 사용한다."
---

# Refactor

## 작업 순서

1. 대상 파일, 관련 import, 도메인 문서를 읽고 시작한다.
2. public API, 호출자, 테스트, 문서 항목 중 영향받는 것을 확인한다.
3. 큰 리팩터링은 수정 전 짧은 단계 계획을 제시한다.
4. leaf/self-contained 코드부터 옮기고 호출자를 갱신한다.
5. 의미 있는 단계마다 가장 좁은 검증을 먼저 돌리고, 마지막에 넓은 검증을 실행한다.
6. 새 파일, 디렉토리, 위젯, provider, util, 아키텍처 선택이 생기면 문서를 갱신한다.

## 추출 기준

다음에 해당하면 추출 후보로 본다.

- 독립적인 widget/dialog/panel.
- 두 곳 이상 반복되는 코드.
- 순수 parsing/calculation/formatting 로직.
- props로 표현 가능한 큰 `build` subtree.
- 별도 lifecycle이 뚜렷한 state slice.

## PDCA 적용

- Plan: 리팩터링 목적, 보존할 동작, 단계별 파일 이동 범위를 먼저 정한다.
- Do: 한 번에 한 주제만 옮긴다. 가능하면 leaf 위젯/순수 함수부터 추출한다.
- Check: 이동인지 동작 변경인지 diff를 읽어 구분하고, focused test → `flutter analyze` → 필요 시 전체 `flutter test`와 code metrics 순서로 확인한다.
- Act: 실패나 메트릭 악화를 반영해 단계를 쪼개거나 되돌릴 범위를 제안한다.

## 가드레일

- public API signature를 가볍게 바꾸지 않는다.
- 한 변경에는 리팩터링 주제 하나만 담는다.
- 사용자가 요청하지 않았다면 pure movement와 동작 변경을 섞지 않는다.
- 사용자 변경과 관련 없는 dirty file을 보존한다.
- 추출된 순수 함수나 변경된 contract에는 테스트를 추가한다.

## 검증

focused test를 먼저 실행한 뒤 다음을 사용한다.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python3 tools/lint/check_code_metrics.py
```
