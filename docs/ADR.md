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

## ADR-012: 정렬 컬럼 → view 기반으로 전환 (time_sort_key 폐기)

- **상태**: 채택 (2026-04-21)
- **맥락**: `events.time_sort_key`(year × 1000 + 이벤트 번호)는 빌드 타임에 고정.
  외부 기여자가 새 이야기를 끼워 넣으면 기존 키와 충돌하거나 전 이야기 재생성 필요.
- **결정**:
  - `events.story_index`(int, era 내 unique) 컬럼만 저장.
  - `events_ordered` view가 `(era_id, story_index)`로 `rank_in_era` + `global_rank`를 계산.
  - `character_eras`도 view로 전환 — 인물 첫 등장 story_index 기준으로 era 내 자동 정렬.
  - 어드민의 새 이야기 삽입은 RPC `insert_event_at_position` (선후 이야기 사이에 끼워 넣고 뒤 인덱스 +1 시프트)로 처리.
- **이유**:
  - 외부 기여 워크플로우에서 "기존 215개 사이에 추가" 시 정렬값을 사전 협상할 필요 없음
  - view가 항상 1..N 연속 정수를 보장 → 클라이언트 정렬 코드 단순
  - `time_sort_key` 보정 메타데이터(`YEAR_OVERRIDES` 등)도 빌더에서 사용처가 줄어 의도가 분명해짐

## ADR-013: events 비정규화 — character_codes / bible_refs를 컬럼으로 흡수

- **상태**: 채택 (2026-04-21)
- **맥락**: `event_characters.role`, `event_bible_refs.book/chapter/verse` 컬럼이 앱에서
  어디에도 안 쓰이고 `display_text`/`person_id`만 소비되고 있었음. 정규화의 효용 없음.
- **결정**:
  - `events.character_codes text[]`(GIN 인덱스)로 인물 매핑 흡수 → `event_characters` 테이블 제거.
  - `events.bible_refs jsonb`로 성경 참조 통합 → `event_bible_refs` 테이블 제거.
  - `events.story_scenes`/`scene_characters`도 jsonb로 events row에 보관.
- **이유**:
  - 한 이벤트 select로 인물 + 성경 참조 + 장면을 모두 회수 (네트워크 round-trip 1회)
  - 인물별 이벤트 조회는 `character_codes @> ARRAY[code]` + GIN 인덱스로 빠름
  - 향후 어드민 등록도 events 한 번 INSERT로 끝남 (3개 테이블 트랜잭션 불필요)
- **트레이드오프**: events row 크기는 늘어나지만 215~수천 건 규모에서 무의미.

## ADR-014: characters.is_active 어드민 토글 + mention_count 분리

- **상태**: 채택 (2026-04-21)
- **맥락**: 기존 `mention_count >= 2` 필터가 빌드 타임 결정이라 1회 등장 인물은
  중요해도 아바타가 안 만들어짐. 또한 잡음 인물(2회 등장이지만 중요도 낮음)도 노출됨.
- **결정**:
  - 빌더는 모든 개인 인물의 아바타 prompt를 생성 (`--min-mentions 1`).
  - 신규 인물의 `is_active`는 기본 `false` (mention_count >= 2 이상이면 빌더가 `true`).
  - 어드민이 토글한 `is_active` 값은 시드 재실행 시 보존 (`on conflict ... do update`에서 제외).
  - `mention_count` 컬럼은 어드민 화면에서 참고용으로 표시.
- **이유**:
  - "1회 등장이지만 중요한 인물" / "여러 번 등장이지만 노출 불필요한 인물"을 어드민이 직접 선별
  - RLS 정책에서 `characters.is_active = true`만 노출 → 클라이언트가 별도 필터링할 필요 없음
- **결과**: 132명 모두 prompts.json 포함, 그 중 77명만 시드에서 활성으로 INSERT.

## ADR-015: 외부 기여 제출 폐기 + 스키마 경량화

- **상태**: 채택 (2026-04-21)
- **맥락**: 앱 내부에 "외부 기여자가 이야기 제출 → 어드민 검토 → 배포" 흐름을
  위해 `events.submitted_by`, `events.status = 'pending_review'`, `publish_event` RPC,
  `audit_log` 테이블/트리거가 준비되어 있었으나 실제 사용자 검증 전 방향 전환.
  등록 요청은 앱 밖(구글폼/노션 등)에서 수집하고, 어드민이 직접 등록하는 것으로 확정.
- **결정**: 외부 기여 관련 객체 일괄 제거.
  - `events.submitted_by`, `events.thumb_url` 컬럼 DROP
  - `events.status` CHECK → `('draft','published')` 로 축소
  - `publish_event(uuid)` RPC 제거, `insert_event_at_position` RPC 는 admin 전용으로 단순화 (status 항상 'published', submitted_by 없음)
  - `audit_log` 테이블 + `record_audit()` 함수 + `trg_events_audit`/`trg_persons_audit` 트리거 제거
  - 그 외 동시 정리: `eras.theme_color`, `persons.mention_count`, `user_event_progress.score`/`xp_earned`, `idx_bible_verses_book_name` 제거
- **이유**:
  - 제출→검토 UX 는 앱 밖 도구가 이미 충분 (폼/노션). DB 레벨 상태 머신은 불필요.
  - `audit_log` 는 git + seed SQL 재실행으로 복구 경로 확보됨. 공간/복잡도 대비 가치 낮음.
  - 게이미피케이션(score/xp) 계획 현재 없음. 완료 여부(`is_completed`)만 사용 중.
- **결과**: `db_init.sql` 약 180줄 감소, RLS/트리거/RPC 단순화. admin 앱은 관리자
  전용으로 축소 (pending_review 검토 화면 제거, 즉시 published 등록).

## ADR-016: admin/ 폐기 → 메인 앱 웹 버전 통합 + pastor 역할 + event_proposals 승인 워크플로우

- **상태**: 채택 (2026-04-21)
- **맥락**: 별도 `admin/` Flutter Web 프로젝트를 유지하던 동안 빌드·의존성·문서
  이중화 비용이 누적되고 있었고, 원래 관리자 전용이던 이야기 등록 흐름을
  **"사역자(목회자) 자격이 있는 사용자"** 에게도 열어 크라우드소싱하고 싶다는
  요구가 생겼다. 단, 누구나 글쓰기는 부적절하므로 제출 전 단계에 "인증된 목회자"
  게이트가 필요하고, 콘텐츠 품질 보장을 위해 관리자 승인 게이트도 필요하다.
- **결정**:
  1. `admin/` 디렉토리 폐기. 재사용 위젯 (`bible_refs_picker`,
     `character_codes_picker`, `scene_characters_grid`) 만 `lib/widgets/proposal/` 로
     이주해 메인 앱에서 재사용.
  2. 메인 앱 Flutter 코드베이스에 **웹에서만** 노출되는 "이야기 제안" 게시판 탭을
     `kIsWeb` 분기로 추가 (후속 Phase 2~6).
  3. `user_profiles.is_pastor boolean default false` 컬럼과 `is_pastor()` SECURITY
     DEFINER 함수를 도입. 운영자가 이메일(admin@brand-i.net) 확인 후 Supabase
     대시보드에서 수동 토글.
  4. 제안 전용 테이블 `event_proposals` 신설 — 승인 전까지 `events` 와 격리되어
     모바일 앱 쿼리(`events.status='published'`)에 섞이지 않는다. 승인 시 기존
     `insert_event_at_position` RPC 를 통해 `events` 에 반영.
  5. RPC 4개 도입: `submit_event_proposal`(pastor), `approve_event_proposal`(admin),
     `reject_event_proposal`(admin), `add_proposal_comment`(pastor+admin).
  6. 댓글 테이블 `event_proposal_comments` 로 동료 사역자 피드백 가능.
- **이유**:
  - `event_proposals` 를 별도 테이블로 두면 RLS 분리가 명확하고, 승인 전 proposal
    이 실수로 모바일 앱 쿼리에 섞여 보이는 리스크가 구조적으로 0이다.
  - `is_pastor` 를 `is_admin` 과 분리함으로써 "콘텐츠 기여" 와 "운영 승인" 권한을
    독립적으로 관리한다. 목회자 인증은 수동 이메일 검증으로 스팸 방지.
  - 웹 전용 탭은 `kIsWeb` 런타임 분기로 충분 — 모바일 번들에 등록 UI 코드가
    포함되지만 버튼이 노출되지 않아 UX 충돌 없음.
  - `admin/` 폐기로 유지보수 대상 코드베이스가 1개로 단일화.
- **결과**: admin/ 디렉토리 제거, `lib/widgets/proposal/` 위젯 3개 대기, DB 에
  `event_proposals`/`event_proposal_comments` + 관련 RPC/RLS 준비. 후속 Phase 에서
  UI 탭·게시판 리스트·상세·댓글·관리자 승인 UI 를 메인 앱에 구축한다.

## ADR-017: 이야기 삭제 제안 + soft delete + 퀴즈 필수화

- **날짜**: 2026-04-22
- **상태**: 승인
- **맥락**: ADR-016 에서 도입한 제안 워크플로가 "새 이야기 추가" 만 지원했다.
  이후 사역자가 잘못 등록된 이야기를 **삭제** 하거나 기존 이야기를 **수정** 할
  방법이 필요하다는 요구가 나왔다. 그리고 새 이야기 제안 시 퀴즈가 누락되어
  사용자 학습 사이클이 완성되지 않는 문제도 있었다.
- **고려한 대안**:
  - (A) 기존 이야기 수정 제안 (amendment) 지원 — `events` 를 UPDATE. 장면·인물·
    장면 이미지 부분 수정 UX 가 복잡하고 "아바타 교체/인물 삭제/장면 부분
    재생성" 등 엣지 케이스가 많아 놓치기 쉬움. 이번 라운드에서는 제외.
  - (B) 기존 이야기 **삭제 제안** 만 도입 + 재등록은 기존 "새 이야기 제안" 플로우
    재사용. 사용자 UX 2단계(삭제 → 신규)지만 구조가 단순.
  - (C) 삭제를 hard delete 로 처리. `quiz_questions` / `user_event_progress` 에
    걸린 `ON DELETE CASCADE` 때문에 사용자 진도까지 연쇄 삭제 → UX 치명적.
- **결정**:
  1. 옵션 **B + soft delete** 채택. `event_proposals.proposal_type` 컬럼 추가
     (`'new'`/`'delete'`) + `target_event_id` 로 대상 지정.
  2. `events.deleted_at timestamptz` 추가. `events_ordered` view / `character_eras`
     view / `list_characters_by_era` RPC 세 곳에 `deleted_at IS NULL` 필터를 걸어
     앱 전체에서 자동으로 숨긴다. 퀴즈/진도 row 는 보존 — rollback 쉬움.
  3. 새 이야기 제안 Step 4 로 **퀴즈 1~3개** 강제. 각 문제는 4지선다 + 해설 필수.
     `event_proposals.quiz_questions jsonb` 에 스냅샷으로 담기고, 승인 RPC 가
     `quiz_questions` 테이블에 row 로 풀어 넣음.
  4. 중복 방지: `uniq_pending_delete_target` partial unique index 로 동일 이벤트
     에 pending 삭제 제안이 여러 건 쌓이지 않도록 차단.
  5. RPC 2개 신규 (`submit_delete_proposal`, `approve_delete_proposal`) + 기존
     `submit_event_proposal` / `approve_event_proposal` 에 퀴즈 검증·insert 추가.
- **이유**:
  - 수정 제안은 인물·장면 구성 요소가 얽혀 "어느 필드만 바꾸고 어느 에셋을
    재사용할지" 결정 지점이 많다. MVP 제약으로 쳐내기 어렵다고 판단.
  - CASCADE 를 끄는 방식은 스키마 전반 재검토가 필요하고, 향후 실제 hard-delete
    가 필요한 경우도 막아 버리므로 soft delete 가 더 유연하다.
  - 퀴즈 강제화는 사용자 학습 사이클 완결성과 사역자 책임감 모두에 기여.
    기존 215개 이야기는 퀴즈가 아직 없어 backfill 작업이 별도 필요 — 본 ADR
    에서는 **새 제안만 강제**, 기존 이야기 backfill 은 별도 운영 작업.
  - "수정" 니즈는 사역자가 삭제 후 다시 새 이야기를 제안하는 경로로 우회 가능.
    실제 수요가 확인되면 amendment 기능을 추가 ADR 로 뒤따라 도입.
- **결과**: 마이그레이션 `20260422_proposal_type_soft_delete_quiz.sql`, Step 4 퀴즈
  편집기 UI (`ProposalQuizEditor`), 삭제 제안 바텀시트 (`DeleteEventProposalSheet`),
  `ProposalRepository` 에 `submitDeleteProposal` / `approveDelete` 추가.
  제안 상세 화면은 `proposal_type='delete'` 를 감지해 붉은 배너 + 수정 버튼 숨김
  + 승인 시 `approve_delete_proposal` 분기.

## ADR-018: 인앱 알림 + FCM 푸시 — 하이브리드 팬아웃 구조

- **날짜**: 2026-04-22
- **상태**: 승인
- **맥락**: 제안 워크플로(ADR-016/017)가 돌아가려면 사역자/관리자 사이의
  커뮤니케이션이 즉각 전달돼야 한다. 인앱 bell 아이콘 + 브라우저/모바일 푸시
  두 경로를 모두 지원하면서 운영 규모(유저 ~1000명 예상) 까지 확장 가능해야 한다.
- **고려한 대안**:
  - (A) 모든 알림을 `notifications` 한 테이블에 Fan-out on Write — 유저 수만큼
    row 를 INSERT. RLS 가 단순하지만 "새 이야기 등록" 같은 전체 대상 알림에서
    215개 이야기 × 1000명 = 21만 row 가 순식간에 생성 → 부담.
  - (B) 모든 알림을 공지 1 row + `seen` 교차표 (Fan-out on Read) — 효율은 좋지만
    개인 알림(내 제안에 댓글) 에는 과한 정규화. 쿼리 JOIN 복잡.
  - (C) **하이브리드**: 개인 알림은 Fan-out on Write(`notifications`), 전체 대상
    알림은 Fan-out on Read(`broadcast_notifications` + `broadcast_notification_reads`).
- **결정**: 옵션 C 채택.
  1. 테이블 5개 신설: `notifications`(개인), `broadcast_notifications`(공지),
     `broadcast_notification_reads`(읽음 교차), `user_push_tokens`(FCM),
     `weekly_character_selection`(금주 인물 단일 소스).
  2. DB 트리거 4개로 자동 생성: 제안 INSERT → admin 전체, 댓글 INSERT → 관계자,
     proposal status UPDATE → proposer, events INSERT → broadcast.
  3. `list_my_notifications` RPC 가 두 소스를 UNION 해 앱엔 하나의 목록으로 반환.
  4. 30일 보관은 hard delete 없이 `WHERE created_at > now() - 30d` 필터로 처리.
  5. 푸시 경로는 별도: Supabase Edge Function `send-push` 가 FCM HTTP v1 을 호출.
     인앱 bell 과 독립 — DB 트리거가 pg_net 으로 send-push 를 호출하면 둘 다 자동화.
  6. 금주 인물은 Dart `seedFromKey` 알고리즘을 plpgsql `_seed_from_week_key` 로
     포팅해 앱/pg_cron 양쪽이 동일 결과를 내도록 단일 소스 보장.
- **이유**:
  - 유저가 1000명을 넘어도 broadcast 는 유저 수에 비례해 폭증하지 않음.
  - 개인 알림은 단순 Fan-out on Write 유지로 RLS/쿼리 단순.
  - 금주 인물 선정을 DB 쪽에 포팅한 이유: pg_cron 에서 "월요일 00:00 UTC 에
    broadcast 를 보내려면" 서버가 어느 인물이 선정될지 알아야 함. 앱만 아는 상태
    면 drift 발생 가능.
  - Firebase FCM 선택 이유: iOS(APNs)/Android/Web 세 프로토콜을 단일 API 로
    통합, 특히 APNs p8 키 관리를 대행해줌. 자체 구현 부담 회피.
- **결과**: 8개 커밋으로 Phase 1~4 반영. DB 스키마 + Repository + UI + Firebase/
  FCM + Edge Function + flutterfire 플랫폼 설정 + 포그라운드 웹 알림 수정
  + 토큰 등록 타이밍 버그 수정 포함. `docs/guides/INFRA_GUIDE.md` 에 전체
  동작 원리(JWT, Apple nonce 이중 해싱, GCP access_token 교환 등) 문서화.
