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

## ADR-019: 위치 모델 v2 — region/anchor/minor + landmark_id FK (2026-05-04)

- **결정**: events 의 위치를 직접 좌표(`lat/lng/place_name`) 에서 `landmark_id` (uuid → landmarks) FK 로 전환. landmarks 테이블을 region(폴리곤 영역) / anchor(region 의 대표 점) / minor(region 안의 작은 점) 3 종으로 확장. `alias_group_id` 로 같은 점 다른 시대 이름(모리아산 ↔ 예루살렘 성전, 시내산 ↔ 호렙산, 시날 ↔ 바벨론) 묶음.
- **이유**:
  1. 새 이야기 제안 시 사용자(목사)가 자유 좌표를 찍으면 일관성/품질이 떨어짐. 미리 정해진 region/anchor/minor 칩에서 고르도록 하면 데이터 정합성 유지.
  2. "이 지역에서 일어난 사건들" 같은 쿼리가 단순 FK 조회로 가능 → "지역으로 탐색" UX 가능.
  3. 같은 위치 다른 시대 이름 처리(alias_group)로 시대 멀티 선택 시에도 같은 점에 라벨을 합쳐 표시.
- **마이그레이션**:
  - `supabase/migrations/20260504_landmarks_v2.sql` (스키마 + landmark_id 컬럼)
  - `supabase/200_stories/landmarks_v2_seed.sql` (31 region + 66 anchor + 17 minor + 4 alias_group)
  - `supabase/200_stories/event_landmark_update.sql` (168 events 의 landmark_id 채움)
  - `supabase/migrations/20260504_landmarks_v2_finalize.sql` (NOT NULL + RPC 시그니처 변경 + lat/lng/place_name DROP + events_ordered view 재정의)
- **RPC 시그니처 변경 4건**:
  - `insert_event_at_position`: `p_place_name/p_lat/p_lng` → `p_landmark_id uuid`
  - `submit_event_proposal`: 동일
  - `approve_event_proposal`: 내부에서 `v_proposal.landmark_id` 사용
  - `revise_proposal_position`: `p_landmark_id uuid default null` 추가 (위치 재선택 가능)
- **호환 정책**: `events_ordered` view 가 landmarks JOIN 으로 `lat/lng/place_name` 을 derived 로 노출 → 기존 클라이언트 호출처 변경 최소화. `StoryEvent.lat/lng/placeName` 은 view derive 값, `landmarkId` 가 진실 소스.
- **UI**:
  - 시대 단수 → `selectedEraIds: Set<String>` 멀티.
  - 시대 선택 후 `SelectionModeDialog` 가 [지역(region) / 인물(character)] 분기.
  - region 모드: 지도 region 폴리곤 + anchor/minor 점 + region 클릭 시 `RegionModeCardStrip` 가로 카드 슬라이딩.
  - character 모드: 인물 칩 멀티 선택 + `CharacterModeGrid` 5열 세로 카드 + 점선 연결 + 좌우 화살표.
- **결과**: 새 위치 v2 카탈로그 (`assets/landmarks/landmarks_v2_draft.json`) + 168 events 매핑 (`assets/landmarks/event_landmark_mapping_draft.json`). v2 흐름 진입은 메인 화면 상단 "탐색 v2" 버튼 → `V2ExploreScreen`.


- **Phase 2 (2026-05-04 추가)**: app.dart 의 home 을 `V2ExploreScreen` 으로 교체. 기존 StoryHomeScreen 은 V2ExploreScreen 의 AppBar 의 'history' 아이콘에서 진입 가능 (레거시 utility 풀세트 — 검색/주간/성경/프로필/알림/Aa/이야기 등록).
- **Phase 3 (2026-05-04 추가)**:
  - 지역 모드 region 마커에 그곳에서 발생한 사건의 인물 아바타(첫 4명) 동그라미 stack 표시 (`_RegionMarkerWithAvatars`).
  - 사건 카드 탭 → 미리보기 다이얼로그 (제목/요약/장소·연도 메타 + 닫기). 풀 EventDetailPage 진입은 추후 v2 화면용 콜백 통합 후.
  - `RevisePositionDialog` 가 landmark ChoiceChip 그룹으로 region/anchor/minor 재선택 가능. `revise_proposal_position` RPC 의 `p_landmark_id` 파라미터로 전달.
- **시드 빌더 변경**: `build_200_stories_seed_sql.py` 가 `assets/landmarks/event_landmark_mapping_draft.json` 을 읽어 events.landmark_id 를 INSERT 시 lookup. 별도 event_landmark_update.sql 적용 불필요.
- **Make pipeline**: `make seed-all` 이 `seed-landmarks-v2` 를 포함, `make apply-seeds` 가 v2 landmarks 를 stories 보다 먼저 적용.

## ADR-020: 프로필 "진행률 표시" 섹션 + 지도 region 정복(D안) (2026-05-08)

- **결정**:
  - "연속 출석일" / "연속 인물 공부" 스트릭 기능 제거. 관련 테이블(`user_daily_activity`), Repository 메서드(`recordAttendance`/`recordStudyDay`/`fetchAttendanceStreak`/`fetchStudyStreak`/`computeDailyStreak`/`dateOnly`), UI 카드, 테스트 모두 삭제.
  - 프로필 우측 패널을 "진행률 표시" 탭형 섹션으로 교체. 좌측 상단 제목 + 두 탭(`장소로 시작` / `인물과 걷기`) — 탭은 섹션 최상단 pinned, 탭 아래 컨텐츠는 `Expanded(SingleChildScrollView)` 로 스크롤.
  - **장소로 시작** 탭: `EraPickRows`(구약/신약 시대 칩) + `ProfileMiniMap`. 시대 미선택 시 안내 빈 상태("시대를 골라보세요").
  - **인물과 걷기** 탭: 기존 구약/신약 토글 + 5열 character grid (AvatarProgressRing) 그대로 이전.
  - **지도 딱지 모으기 (D안)**: region 폴리곤이 진행률(완료/총 이벤트)에 따라 검정→시대컬러로 알파 보간 채움. 100% region 은 골드 보더 + 중심에 작은 황금 깃발 마커. 상단에 "정복: X / N" 다크 칩 카운터.
  - 사건↔region 매핑은 클라이언트에서 point-in-polygon (ray-casting, `lib/utils/region_membership.dart`).
  - 프로필 헤더 컴팩트화: 아바타 78 → 40, 이름 + 수정/안내/로그아웃 버튼 한 줄. 중보 기도 리스트는 320px fixed 로 ~3.5명 보이게 + 내부 스크롤.
- **이유**:
  1. 스트릭은 사용 가치가 낮고 동기부여가 약했음. region 정복 시각화 + 인물 progress ring 이 학습 진행도를 더 직관적으로 전달.
  2. 두 탭 구조는 앱의 핵심 두 축("장소로 시작" / "인물과 걷기") 과 1:1 대응 — 홈 화면의 EraPickRows 를 그대로 재사용해 일관성 확보.
  3. D안(채움 + 정복 깃발 + 카운터) 은 부분 진행 가시화 + 완료 보상 + 게이미피케이션 카운터 세 가지를 모두 제공하면서 양피지 톤과 자연스럽게 어울림 (B안 = 정보 손실, C안 = 별 배치 알고리즘 부담, E안 = 톤 충돌).
- **공유 컴포넌트 추출**:
  - `lib/widgets/v2/era_pick_rows.dart` — `EraPickRows`/`EraPickRow`/`eraIconFor()`. HomeIntroPanel 도 이 위젯을 사용 (구 `_EraRow`/`_EraChip`/`_eraIconFor` 제거).
  - `lib/utils/region_membership.dart` — `isPointInPolygon` + `polygonCenter`. ray-casting 알고리즘.
  - `lib/widgets/profile/profile_mini_map.dart` — 미니 맵 (flutter_map 8.x).
  - `lib/widgets/profile/profile_progress_section.dart` — part 파일, 섹션 wrapper + 두 탭 본문.
- **DB 변경**: `db_init.sql` 에서 `user_daily_activity` 테이블 정의/index/trigger/grant/RLS 모두 제거. 상단 cleanup 섹션의 `drop table if exists user_daily_activity cascade;` 만 잔존(idempotent 정리용).
- **결과**:
  - 프로필 상단(헤더 + 중보) 높이 약 35% 감소 → 진행률 섹션이 더 큰 비중.
  - region 정복 카운터로 "다음 어느 region 을 마저 끝낼까" 동기 형성.
  - 홈/프로필이 동일 era picker 컴포넌트 공유 → 시대별 색·아이콘 일관성 자동 보장.

## ADR-021: 퀴즈 페이지 (매일+주간) + 독립 진행도 + 인물/지역 모드 (2026-05-15)

- **결정**:
  - 홈 상단 "금주 인물" 버튼 → **"퀴즈"** (성경 옆, 프로필 앞). 클릭 시 `QuizTabPage` 가 두 탭으로 열린다 — **매일 퀴즈** + **주간 퀴즈**.
  - **매일 퀴즈**: `daily_quiz` 테이블의 최신 1건. 4지선다 + 제출 → CompletionCelebration (도장+별가루) + 정/오답 결과 + 해설.
  - **주간 퀴즈**: 기존 WeeklyTabPage embedded. 지도(StoryMapPanel) + 하단 EventTimelineRow (홈과 동일).
  - **두 모드** — 시드 짝/홀수로 50/50 결정:
    - `WeeklyMode.character`: 랜덤 인물 + 그 인물의 사건 (기존).
    - `WeeklyMode.region`: 랜덤 시대 + 사건이 있는 랜덤 region + 그 region 사건. 헤더 = "금주 지역: 시대명 · 지역명". 지도 = region 폴리곤 강조 (`eraRegionLandmarks: [region]`).
  - **독립 진행도**: `weekly_quiz_progress(user_id, week_key, event_id, is_bible_read, is_quiz_completed, last_score_correct/total)` 신설. 프로필의 `user_event_progress` 와 무관 — 같은 인물이 다음 주에 또 뽑혀도 `week_key` 가 달라 자동 reset.
  - **EventDetailPage**: 옵셔널 `quizWeekKey: String?` prop. 비-null 이면 read/write 가 weekly* state/setter 로 분기. CompletionCelebration·"다음 이야기" glow 도 weekly 기준.
  - **HomeScreen**: `_openEventDetailPage(event, {quizWeekKey})` + `_startQuiz(eventId, {quizWeekKey})` — `setBibleRead`/`setQuizCompleted` 호출이 quizWeekKey 유무로 분기.
- **이유**:
  1. 인물 학습이 단조로워 같은 인물 반복이 지루해질 수 있음 → 지역 모드 추가로 "한 지역의 사건들" 학습 흐름 확보.
  2. 프로필 진행도 (캐릭터 학습 완료) 와 퀴즈 풀이가 섞이면 동기 부여가 약해짐 — 퀴즈는 "이번 주에 풀었나" 라는 이벤트 단위 완료에 집중.
  3. 독립 테이블(`weekly_quiz_progress`) 로 분리하면 프로필 진행도에 영향 없이 같은 인물/지역 재방문 가능.
- **DB 변경**:
  - `db_init.sql`: `daily_quiz` (4지선다 + 해설), `weekly_quiz_progress` (사용자/주차/사건 키) 추가. 둘 다 RLS 적용 — daily_quiz 공개 read, weekly_quiz_progress 본인만 r/w.
  - 시드: `supabase/seeds/daily_quiz.sql` 1건.
- **아키텍처 변경**:
  - `WeeklyStudyData` — 단일 character 필드 → mode + character/era/region 옵셔널.
  - `weekly_selection.dart` — `WeeklyMode` enum + `weeklyModeForSeed()` 추가.
  - `EventTimelineRow` 재사용으로 weekly 의 사건 카드가 홈 하단 패널과 100% 일치.
  - `CompletionCelebration` 재사용으로 매일 퀴즈 제출 시에도 같은 도장+별가루 효과.
- **결과**:
  - 한 페이지에서 매일/주간 두 가지 학습 흐름.
  - 같은 인물/지역 반복 가능 — 매주 새로 풀어 보는 의식적 학습.
  - 홈/주간이 같은 카드 코드로 일관 (시각·동작 동일).

## ADR-022: 푸쉬 디스패치 자동화 + 매일/주간 퀴즈 push-only 전환 (2026-05-11)

- **배경**: ADR-018 에서 broadcast/personal 알림 + FCM 토큰 인프라를 도입했지만, DB row INSERT → `send-push` Edge Function 호출의 마지막 연결고리(`pg_net`)가 누락돼 실제 푸시가 발송되지 않았다. 또 매일 퀴즈/주간 인물·진도 알림이 모두 `broadcast_notifications` 에 row 를 만들어 bell drop 에 누적되면서 사용자 수가 늘수록 무한 누적 + 시각적 노이즈 우려.
- **결정**:
  1. **자동 디스패치**: `broadcast_notifications` AFTER INSERT 트리거 `trg_push_after_broadcast` 추가. row 가 만들어지면 헬퍼 `_fire_push_broadcast(title, body, deep_link, type)` 가 `net.http_post` 로 `send-push` Edge Function 호출.
  2. **Vault 기반 시크릿**: Supabase Vault 에 `service_role_key`, `supabase_url` 두 secret 저장. 헬퍼가 `vault.decrypted_secrets` 에서 읽어 헤더 구성. ALTER DATABASE SET 보다 안전(백업·덤프에 평문 노출 없음).
  3. **푸시 only 채널**: 매일/주간 알림은 broadcast 테이블을 거치지 않고 `_fire_push_broadcast` 를 직접 호출. bell drop 에 row 가 안 쌓이고 푸시 알림으로만 전달.
  4. **이벤트+인물 묶음 broadcast**: `approve_event_proposal` RPC 가 세션 플래그 `app.suppress_event_broadcast='true'` 로 events 트리거 자동 broadcast 를 막고, 사건 INSERT 후 신규 활성화 인물 이름까지 모아 broadcast row 1건을 직접 생성. 본문 예: `"새 이야기 '<title>' — 새 인물 '<name>' 외 N명도 함께 만나봐요"`.
  5. **스케줄**: pg_cron 4개 — `daily-quiz-9am-kst (0 0 * * *)`, `weekly-character-monday (0 0 * * 1)`, `weekly-progress-wed (0 0 * * 3)`, `weekly-progress-fri (0 0 * * 5)`. 모두 KST 9시 = UTC 0시.
- **이유**:
  1. 모든 사용자에게 `notifications` 테이블 row 를 fan-out 하면 N×M 폭발 — push 채널은 본질적으로 broadcast 라 토큰 N개에 한 번 발송이면 끝.
  2. 매일 발생하는 퀴즈 알림이 bell drop 에 누적되면 사용자 인식 부담 큼. 푸시는 클릭/dismiss 시 사라져 일시적.
  3. 새 이야기 + 인물을 별도 broadcast row 2개로 보내면 사용자 입장에서 같은 사건의 알림이 둘로 쪼개져 노이즈. 한 건으로 묶는 게 자연스러움.
- **DB 변경** (`db_init.sql` 단일 진실 소스 — `make db-init ENV=<env>` 로 적용):
  - 신규 함수: `_fire_push_broadcast`, `_push_after_broadcast`, `dispatch_daily_quiz_push`.
  - `notify_on_new_event` 트리거에 suppress 분기 추가.
  - `pick_weekly_character`, `notify_weekly_progress` 의 broadcast INSERT 제거 → `_fire_push_broadcast` 호출.
  - `broadcast_notifications.type` CHECK 에서 `weekly_*` 두 값 제거 (현재는 `new_event` 만).
  - pg_cron `daily-quiz-9am-kst` 추가.
- **운영 적용 전제**: `pg_net` 확장 ON + Vault 두 secret 등록 + `send-push` 배포. 누락 시 헬퍼가 raise warning 후 silent return — 호출 트랜잭션(이벤트 승인 등)은 항상 성공.
- **결과**:
  - 사용자가 사용하지 않아도 매일/주간 알림이 자동 발송.
  - bell drop 은 "새 이야기" 같은 영구 기록성 알림만 받음.
  - service_role_key 가 SQL 함수 본문에 박히지 않아 코드 리뷰 시 노출 방지.
- **보충 (매일 퀴즈 자동 초기화)**: `dispatch_daily_quiz_push` 는 단순히 푸시만 발송하지 않고 매 호출마다 daily_quiz 풀에서 random 1건을 pick 해 같은 content 로 **새 row 를 INSERT** 한다. 이렇게 하면 새 daily_quiz_id 가 발급되고, `user_daily_quiz_attempts` (PK: user_id, daily_quiz_id) 가 자연스럽게 다음 날 row 와 분리되어 사용자는 "어제 푼 결과가 사라진" 상태로 매일 새로 풀 수 있다. 주간 퀴즈는 `weekly_quiz_progress` 의 week_key 가 매주 자동으로 달라져서 별도 처리 불필요.

## ADR-023: supabase/migrations/ 부활 + db-migrate 타겟 (2026-05-12)

- **배경**: ADR-022 가 `dispatch_daily_quiz_push` 함수 + pg_cron 4개 스케줄을 `db_init.sql` 에 추가했으나, 그 변경분을 prod DB 에 별도로 적용하지 않아 매일 KST 9시의 자동 새 quiz 발급이 누락됐다. 사용자는 "어제 답한 quiz/답안이 그대로" 라고 보고했고, 진단 결과 `cron.job` 테이블에 4개 cron 이 모두 미등록 상태였다 (수동 SQL 실행 후 복구). 같은 형태의 사고 — `db_init.sql` 에는 들어갔으나 prod 적용 누락 — 가 이 PR 이전에도 잠재적으로 있었을 가능성이 있고, 향후 DB 변경 시마다 반복될 위험.
- **결정**: 옛 정책 ("`supabase/migrations/` 디렉토리 폐기, `db_init.sql` 만 단일 진실 소스") 을 뒤집어 **두 트랙을 동시에** 운영한다.
  1. **`db_init.sql`** — 여전히 단일 진실 소스. 신규 환경 부트스트랩 (DROP & CREATE) 용.
  2. **`supabase/migrations/<YYYYMMDD>_<HHMM>_<slug>.sql`** — 직전 prod 상태 → 현재 desired 상태로 가는 증분 패치. 모두 idempotent (`create or replace`, `if exists`, `cron.unschedule + cron.schedule` 등) 패턴 강제.
  3. **`make db-migrate`** 신규 타겟 — `supabase/migrations/*.sql` 알파벳 순 적용. `make db-init` 끝에 자동 호출되어 신규 환경에서도 동일 적용 (idempotent 라 no-op). prod 증분 적용은 `make db-migrate ENV=prod`.
  4. **PR 워크플로 강화**: schema/function/cron 등 DB 변경 PR 은 항상 두 곳을 동시 수정 (db_init.sql + supabase/migrations/). reviewer 가 두 파일이 같은 변경을 표현하는지 확인.
- **이유**:
  1. db_init.sql 이 완벽하게 prod 의 desired state 를 표현해도, prod 에 그 SQL 을 누군가 실행하지 않으면 무의미. `make db-init ENV=prod` 는 파괴적이라 사실상 못 돌리고, 결국 운영자가 SQL Editor 에 발췌해 수동 실행 — 누락 위험이 누적된다.
  2. 증분 마이그레이션 트랙이 있으면 prod 적용이 한 명령 (`make db-migrate ENV=prod`) 으로 통일되고, idempotent 파일이라 머지 후 언제 돌려도 안전.
  3. 신규 환경 부트스트랩은 `db_init.sql` 한 번이면 충분하므로 두 트랙이 redundant 해 보이지만, 두 곳 동기화 비용은 한 PR 당 SQL 한 블록 복사 정도로 작은 반면 prod 누락 사고를 원천 차단할 수 있음.
- **사용자 워크플로 변경**: 없음. 신규 환경 부트스트랩 시퀀스 — `make seed-all && make db-init && make apply-seeds && make upload-character-avatars` — 는 그대로 유지. `make db-init` 안에서 `make db-migrate` 가 자동 호출되어 마이그레이션 파일도 함께 적용된다 (idempotent 라 no-op). 신규 워크플로는 "prod 증분 적용 = `make db-migrate ENV=prod`" 한 줄만 추가.
- **DB/파일 변경**:
  - 신규 디렉토리: `supabase/migrations/`
  - 첫 마이그레이션 파일: `20260512_1144_pg_cron_dispatch_and_schedules.sql` — ADR-022 의 dispatch_daily_quiz_push 함수 + pg_cron 4개 스케줄 등록 (idempotent). prod 에는 이미 수동 적용됐지만 신규 환경 / 다른 prod (향후) / 정책 reference 로 명문화.
  - `Makefile`: `db-migrate` 타겟 추가, `db-init` 끝에 `make db-migrate` 자동 호출 추가, `.PHONY`/help 갱신.
  - `docs/BACKEND.md §8` 전면 개정 (위 정책 반영).
- **결과**:
  - 향후 DB 변경은 PR 단계에서 두 파일이 함께 들어와야 하므로 reviewer 가 prod 적용 누락을 사전에 catch.
  - prod 운영자는 `make db-migrate ENV=prod` 한 줄로 모든 idempotent 변경분 일괄 적용 가능.
  - dev 환경은 기존 `make db-init` 워크플로 그대로 — 마이그레이션은 bonus 로 자동 적용.
- **남은 옵션 (향후)**:
  - 마이그레이션 적용 이력 추적 테이블 (`_schema_migrations`) 도입해 같은 파일 중복 실행 방지 — 현재는 idempotent 패턴으로 안전하지만, 마이그레이션 수가 누적되면 매번 모두 실행은 비효율.
  - GitHub Actions 로 main 머지 시 dev `make db-migrate` 자동 실행 — prod 자동 적용은 위험하니 수동 trigger 유지.
  - Supabase CLI 의 정식 마이그레이션 (`supabase db push`) 으로 전환 — `supabase_migrations.schema_migrations` 자동 추적 + Studio 통합. 다만 본 프로젝트는 db_init.sql 을 신규 환경 부트스트랩 용도로 유지하고 싶어 두 트랙 병행 (CLI 는 마이그레이션만 추적).
