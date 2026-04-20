# ADR — 아키텍처 결정 기록

> 각 결정은 당시 맥락에서 최선이었던 이유를 기록한다.

## ADR-001: Flutter 선택

- **상태**: 채택
- **맥락**: iOS + Android + Web을 단일 코드베이스로 지원해야 함
- **결정**: Flutter (Dart 3.8+)
- **이유**:
  - 하나의 코드로 iOS/Android/Web 동시 지원
  - 커스텀 UI(고지도 테마, 양피지 질감)를 위한 렌더링 자유도
  - flutter_map 등 지도 패키지 생태계 충분
  - Dart의 null safety, 강타입으로 안정성 확보

## ADR-002: Supabase 선택

- **상태**: 채택
- **맥락**: 인증, DB, 스토리지, RLS를 통합 관리할 BaaS 필요
- **결정**: Supabase (PostgreSQL + Auth + Storage)
- **이유**:
  - PostgreSQL 기반으로 복잡한 관계형 쿼리 지원
  - Row Level Security (RLS)로 사용자별 데이터 보호
  - Auth에서 Apple/Google/Kakao 소셜 로그인 통합
  - pgvector 확장으로 향후 시맨틱 검색 대비
  - supabase_flutter SDK로 Flutter 통합 간편

## ADR-003: Riverpod 선택

- **상태**: 채택
- **맥락**: Flutter 상태 관리 프레임워크 선택
- **결정**: flutter_riverpod 2.6
- **이유**:
  - Provider와 달리 compile-time safety 보장
  - 테스트 시 ProviderContainer로 의존성 주입 용이
  - NotifierProvider 패턴으로 상태 + 로직 캡슐화
  - 전역 상태(StoryController)와 로컬 상태 분리 명확

## ADR-004: flutter_map 선택

- **상태**: 채택
- **맥락**: 인터랙티브 지도 위에 성경 사건 핀을 표시해야 함
- **결정**: flutter_map 8.2 + OpenStreetMap 타일
- **이유**:
  - Google Maps와 달리 API 키 비용 없음
  - 타일 서버 자유롭게 변경 가능 (고지도 스타일 등)
  - latlong2와 조합으로 좌표 계산 간편
  - 오픈소스로 커스터마이징 가능

## ADR-005: Vertex AI Imagen으로 에셋 생성

- **상태**: 채택
- **맥락**: 50+ 인물 아바타와 215×4=860장 장면 이미지를 수작업으로 제작 불가
- **결정**: Google Cloud Vertex AI Imagen API로 자동 생성
- **이유**:
  - 일관된 아트 스타일로 대량 생성 가능
  - 프롬프트 기반으로 반복 생성/개선 용이
  - GCP 프로젝트 내에서 인증 통합
  - 생성 후 수동 검수 + 후처리 가능

## ADR-006: 에셋을 앱 번들에 포함

- **상태**: 채택
- **맥락**: 아바타/장면 이미지를 서버에서 로드할지, 앱에 포함할지
- **결정**: `assets/avatars_thumbs/`, `assets/story_images_thumbs/`를 앱 번들에 포함
- **이유**:
  - 오프라인에서도 이미지 즉시 표시
  - 네트워크 지연 없이 빠른 로딩
  - 이미지 개수가 유한(~860장 썸네일)하여 앱 크기 관리 가능
  - 원본은 서버/로컬에만 보관, 앱에는 썸네일만

## ADR-007: KRV 성경 SQL 시딩 방식

- **상태**: 채택
- **맥락**: 31,904절의 KRV 성경 텍스트를 DB에 적재하는 방법
- **결정**: Python 스크립트로 SQL 파일 생성 → Supabase SQL Editor에서 실행
- **이유**:
  - 대용량 INSERT를 분할 SQL로 안전하게 처리
  - Supabase CLI 없이도 SQL Editor로 적재 가능
  - `--split-parts` 옵션으로 파일 크기 제한 대응
  - 번역본(`translation`) 컬럼으로 향후 다국어 확장 대비

## ADR-008: 도메인별 서브에이전트 아키텍처

- **상태**: 채택
- **맥락**: Claude Code로 작업 시 매번 전체 코드베이스 컨텍스트를 로드하면 토큰 낭비
- **결정**: 도메인별 레퍼런스 MD + Claude 스킬로 컨텍스트를 분리
- **이유**:
  - 프론트엔드 변경 시 `docs/FRONTEND.md`만 로드 → 토큰 절약
  - 백엔드 변경 시 `docs/BACKEND.md`만 로드
  - 각 스킬이 해당 도메인의 파일 범위, 패턴, 규칙을 정의
  - 향후 특정 도메인 수정 요청 시 관련 컨텍스트만 효율적으로 사용
- **구조**:
  - `docs/FRONTEND.md` → `.claude/skills/frontend/SKILL.md`
  - `docs/BACKEND.md` → `.claude/skills/backend/SKILL.md`
  - `docs/DATA_PIPELINE.md` → `.claude/skills/data-pipeline/SKILL.md`
  - `docs/TESTING.md` → `.claude/skills/testing/SKILL.md`

## ADR-009: 큰 위젯 파일은 part 파일 + extension으로 분해

- **상태**: 채택 (2026-04-16)
- **맥락**: `profile_tab_page.dart` 2,628줄, `story_selection_panel.dart` 1,648줄 등
  단일 위젯 파일이 비대해져 가독성·리뷰·작업 분담이 어려움.
- **결정**: 1,000줄 이상 위젯 파일은 다음 패턴으로 분해.
  - `widgets/{domain}/` 디렉토리에 part 파일 위치 (예: `selection/`, `map/`, `profile/`, `weekly/`)
  - 각 part 파일은 `part of '../{parent}.dart';` 선언
  - Stateful 위젯의 메소드는 `extension on _State` 형태로 정의
    (같은 라이브러리이므로 private 멤버 접근 가능, 코드 변경 0건)
  - 자식 private 위젯(`_PinStyle`, `_CardShell` 등)은 그대로 part 파일로 이동
- **이유**:
  - **공개 API 시그니처 무변경**: 외부에서 보는 클래스/메소드 이름 동일 → 호출자 영향 없음
  - **메소드 이동만으로 안전한 분해**: 로직 변경 0, diff는 거의 순수 이동
  - **part 파일은 같은 라이브러리**로 취급되어 underscore 접근 가능
  - Riverpod Controller로의 풀 마이그레이션은 위험도/비용이 높아 보류
- **결과**:
  - `story_selection_panel.dart` 1648 → 561줄 (−66%)
  - `story_map_panel.dart` 1500 → 1244줄 (−17%)
  - `profile_tab_page.dart` 2628 → 1755줄 (−33%)
  - `weekly_tab_page.dart` 884 → 574줄 (−35%)
- **트레이드오프**:
  - part/part of는 modern Dart에서 비주류로 간주되지만, 클래스 분할에는 사실상 유일한 선택
  - extension 기반이라 일부 도구가 처음에 헷갈릴 수 있음
  - 진정한 SoC가 필요하면 향후 Riverpod Controller로 단계적 승격 가능

## ADR-010: 순수 함수는 lib/utils로 추출 + 단위 테스트 강제

- **상태**: 채택 (2026-04-16)
- **맥락**: 위젯 State 내부 private 메소드 중 입출력만 있는 순수 함수
  (지도 수학, 주간 인물 시드 등)는 테스트 가능하지만 실제 테스트가 없었음.
- **결정**: 순수 함수는 `lib/utils/{domain}.dart`로 top-level public 함수로 추출,
  각각에 단위 테스트 동시 추가.
- **이유**:
  - 위젯 테스트보다 단위 테스트가 훨씬 빠르고 안정적
  - 같은 함수가 여러 위젯에서 재사용될 가능성
  - 리팩토링 시 행위 보존 검증의 핵심 안전망
- **결과**:
  - `utils/map_math.dart` (9개 함수) + `test/utils/map_math_test.dart` (27 tests)
  - `utils/weekly_selection.dart` (3개 함수) + `test/utils/weekly_selection_test.dart` (10 tests)

## ADR-011: $refactor 스킬 신설 + GitHub Actions CI

- **상태**: 채택 (2026-04-16)
- **맥락**: 대규모 파일 분해/중복 제거 작업이 빈번한데, 도메인 스킬
  (`$frontend`, `$backend` 등) 어디에도 속하지 않음. 또한 로컬 pre-push hook만 있어
  `--no-verify`로 우회 가능했음.
- **결정 1**: `.claude/skills/refactor/SKILL.md` 신설로 분해 절차 강제
  - 1) Read로 전체 파악 → 2) 분해 계획 → 3) 사용자 승인 → 4) 단계별 실행 → 5) 검증
  - 가드레일: 공개 API 무변경, 한 PR당 한 파일, flutter analyze + test 전후 비교
- **결정 2**: `.github/workflows/flutter_ci.yml` 신설로 원격 검증
  - PR/push 마다 analyze + test + coverage + forbidden patterns + asset paths 자동 실행
  - `--no-verify` 우회 차단
- **결정 3**: pre-commit hook 강화
  - `dart-import-sort` (import_sorter 검증)
  - `forbidden-patterns` (print(), JWT 시크릿, Google API key 차단)
  - `verify-asset-paths` (pubspec.yaml과 실제 파일 일치 검증)
