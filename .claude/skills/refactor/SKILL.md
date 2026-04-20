---
name: refactor
description: "대규모 파일 분해/중복 제거/아키텍처 개선 시 사용하는 스킬. 분석 → 분해 계획 → 사용자 승인 → 단계별 실행 → 검증 절차를 강제한다."
---

# Refactor

## 개요

다음 상황에서 사용한다:

- 단일 파일이 1,000줄을 넘어 분해가 필요할 때
- 동일/유사 위젯이 3곳 이상에 중복되어 공유 컴포넌트로 묶을 때
- 큰 State 클래스를 여러 Riverpod Controller로 쪼갤 때
- 디렉토리 구조 재편(예: `lib/widgets/profile/` 신설) 시
- 순수 함수(파싱/계산/포맷)를 `@visibleForTesting`으로 노출해 테스트 가능하게 만들 때

## 작업 순서 (필수)

1. **현황 파악**
   - 대상 파일들을 Read로 전부 읽는다 (grep만으론 부족).
   - 파일별 클래스/메소드/state 필드/build 트리 구조를 파악한다.
   - 다른 파일에서 import하는 공개 API(클래스명, 함수명)를 Grep으로 확인한다.

2. **분해 계획 작성**
   - 각 추출 대상을 다음 형식으로 정리:
     - 원본 line range
     - 새 파일 경로 (`lib/widgets/{domain}/{name}.dart` 등)
     - 예상 줄 수
     - 추출 사유 (self-contained / 재사용 / 순수 로직 / 중복 제거 등)
     - 의존성 (다른 추출 파일이 먼저 만들어져야 하는지)
   - 디렉토리 구조 변경이 있으면 미리 명시 (`map/`, `selection/`, `profile/`, `weekly/`, `shared/`)
   - 큰 변경(공개 API 변경, 상태 관리 패턴 변경)은 별도 표시

3. **사용자 승인**
   - 계획을 사용자에게 제시하고 명시적 승인을 받는다.
   - 범위 옵션(P1만 / P1+P2 / 전부)을 제공.

4. **단계별 실행**
   - **순서 원칙**: 의존성 없는 leaf부터 (공유 위젯 먼저 → 그것을 쓰는 화면 분해)
   - 한 번에 하나의 파일만 추출 → 즉시 `flutter analyze`로 검증
   - 추출 후 원본 파일에서 동일 로직 제거 + import 갱신
   - 위젯 추출 시 `class _Foo extends StatelessWidget` (private) 또는 `class Foo extends StatelessWidget` (재사용 가능) 결정
   - 순수 함수는 top-level 함수로 옮기고 `@visibleForTesting` 어노테이션

5. **검증**
   - `dart format .`
   - `flutter analyze` — 0 issues
   - `flutter test` — 모든 기존 테스트 통과
   - 추출한 순수 함수에 대해 새 테스트 추가 (TDD)
   - 시뮬레이터 빌드 확인 (선택)

6. **문서 동기화**
   - 큰 구조 변경이면 `docs/FRONTEND.md` (위젯 표 갱신), `docs/ARCHITECTURE.md` 업데이트
   - 새 ADR이 필요한 결정이면 `docs/ADR.md`에 추가

## 가드레일

- **공개 API 시그니처는 절대 임의 변경하지 않는다** (다른 파일에서 사용 중일 가능성).
- **한 PR/커밋당 한 파일 분해**가 원칙. 4개 파일을 한 번에 손대면 리뷰가 불가능.
- **분리 후 동작 동일성** 검증 전까지는 다음 단계로 가지 않는다.
- **import 경로 갱신을 빠뜨리지 않는다** — `flutter analyze`가 잡아주지만 IDE 보조 활용.
- **상태 관리 패턴 변경**(local state → Riverpod Controller)은 위험도 높음 — 별도 단계로 분리.
- 단순 분할로 충분하면 **굳이 Controller 승격하지 않는다**.

## 분해 가능성 판단 체크리스트

위젯/메소드가 다음 중 하나라도 만족하면 추출 후보:

- [ ] 200줄 이상의 build 메소드 (또는 `Widget _foo()` 빌더)
- [ ] 외부 state 의존성이 명확히 props로 표현 가능
- [ ] 한 화면에서만 쓰이지만 자체 완결적 (다이얼로그, 카드, 헤더)
- [ ] 두 곳 이상에서 거의 동일한 코드 (중복)
- [ ] 순수 함수 (입력 → 출력, side effect 없음)
- [ ] `setState` 없는 부분이 큰 영역을 차지 (StatefulWidget을 StatelessWidget으로 분리 가능)

## 자주 쓰는 분해 패턴

### 패턴 1: 거대 다이얼로그 분리
```dart
// 원본: _openMyDialog() 안에 400줄
void _openMyDialog(BuildContext context, Foo foo) { showDialog(... 400줄 ...); }

// 추출: lib/widgets/profile/my_overview_dialog.dart
class MyOverviewDialog extends StatelessWidget { final Foo foo; ... }
Future<void> showMyOverviewDialog(BuildContext context, {required Foo foo}) =>
    showDialog(context: context, builder: (_) => MyOverviewDialog(foo: foo));
```

### 패턴 2: 순수 함수 추출 + @visibleForTesting
```dart
// 원본: class _State extends State { Foo _parse(String s) { ... 50줄 ... } }

// 추출: lib/utils/foo_parser.dart
import 'package:flutter/foundation.dart';

@visibleForTesting
Foo parseFoo(String s) { ... }
```

### 패턴 3: pagination/loading state → AsyncNotifier
```dart
// 원본: class _State { bool _loading; List<Item> _items; int _page; ... }

// 추출: lib/state/items_controller.dart
class ItemsState { ... }
class ItemsController extends AsyncNotifier<ItemsState> { ... }
final itemsControllerProvider = AsyncNotifierProvider<ItemsController, ItemsState>(...);
```

## 병렬 탐색 활용

여러 파일을 동시에 분석할 때는 메인 에이전트의 컨텍스트를 절약하기 위해 `Agent` 도구로 explore subagent를 병렬로 띄워라:

```
Agent(subagent_type: "general-purpose", prompt: "파일 X 구조 분석", description: "X 분석")
Agent(subagent_type: "general-purpose", prompt: "파일 Y 구조 분석", description: "Y 분석")
```

Subagent는 Read를 자유롭게 쓰고 요약만 메인에 돌려준다. CLAUDE.md 「병렬 탐색 권장 케이스」 참조.

## 문서 동기화

리팩토링 완료 후 **같은 커밋에서** 아래도 갱신한다.

- `docs/FRONTEND.md` — 새 위젯/디렉토리/파일 목록 표 갱신
- `docs/ARCHITECTURE.md` — 큰 구조 변경 (예: 디렉토리 신설, Controller 승격)이면 §3 화면 구성 다이어그램 업데이트
- `docs/ADR.md` — 패턴 결정(예: "프로필 데이터는 Riverpod AsyncNotifier로 관리")이 새로 생기면 ADR 추가
- 추출된 순수 함수가 있으면 `test/utils/`, `test/data/`에 테스트 동시 추가
