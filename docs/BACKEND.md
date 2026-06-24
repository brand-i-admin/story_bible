# 백엔드 도메인 레퍼런스

> 이 문서는 `.agents/skills/backend` 스킬이 참조하는 백엔드 도메인 가이드이다.
> Supabase 관련 최신 동작이 중요하면 공식 Supabase 문서나 사용 가능한 Supabase
> 도구로 확인하고, 본 프로젝트의 규칙(아래)을 함께 적용한다.

## 1. 파일 범위

```
db_init.sql                            # 스키마 정의 — 단일 진실 소스
supabase/
├── events/                       # 생성된 시드 SQL
│   ├── events_seed.sql           # events INSERT (배열/JSONB 컬럼 포함)
│   ├── characters_seed.sql               # persons INSERT (is_active 만, mention_count 는 character_meta.json 메타)
│   └── events_report.json
└── seeds/
    └── krv_bible_verses*.sql          # KRV 성경 구절 시드

lib/data/
├── auth_repository.dart               # 인증
├── story_repository.dart              # events_ordered/character_eras view 쿼리
└── user_repository.dart               # 사용자 데이터
```

## 2. DB 스키마

### 2.1 핵심 이야기 테이블

#### `eras` — 성경 시대
```sql
id uuid PK, code text UNIQUE, name text, testament text,
display_order int, start_year int, end_year int,
map_center_lat float8, map_center_lng float8, map_zoom numeric(4,2)
```
- 구약 7시대 + 신약 4시대 = 총 11시대. `era_monarchy`는 통일왕국, `era_divided_kingdom`은 왕상 11장 이후 남북 분열부터 예루살렘 포위 전후까지의 분열왕국 이야기를 담는다. 앱은 검수 전인 `era_nt_consummation`을 `hiddenEraCodes`로 숨긴다.
- `testament`: 'old' 또는 'new' (era 코드로도 판별: `era_nt_` 접두사)

#### `persons` — 성경 인물 (table)
```sql
id uuid PK, code text UNIQUE, name text, tagline text,
avatar_url text, description text,
is_active boolean DEFAULT false   -- 어드민이 노출 여부 결정
```
- 모든 개인 코드(그룹/플레이스홀더 제외)가 한 행으로 들어옴.
- 빌더는 `character_meta.json`의 `is_active_default` 값(등장 2회 이상이면 true)을
  따라 초기값을 결정한다. 어드민이 토글한 `is_active`는 시드 재실행 시에도
  보존된다 (`on conflict ... do update`에서 `is_active` 제외).
- 단 `description`은 `coalesce(excluded.description, persons.description)`로 UPSERT되고 excluded가 항상 non-null이므로 **시드에 포함된 인물은 매번 새 description으로 덮어써진다**. 로컬 `assets/events/`가 DB와 동기화된 상태여야 description이 엉뚱한 "대표 이야기"로 망가지지 않는다 — 상세 절차는 [CONTENT_UPDATE.md §2.1b \[0\]](CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로).

#### `events` — 성경 사건 (table)
```sql
id uuid PK, era_id uuid FK→eras, title text, summary text,
background_context text,          -- 상세 첫 카드의 배경 지식 문구
story_scenes jsonb DEFAULT '[]',     -- ["장면1", ...]
scene_captions jsonb DEFAULT '[]',   -- ["사용자용 이미지 설명1", ...]
scene_characters jsonb DEFAULT '[]',    -- [["god"], [], ...]
character_codes text[] DEFAULT '{}',    -- 평탄화된 인물 코드
bible_refs jsonb DEFAULT '[]',       -- [{book, from, to}, ...]
start_year int, end_year int,
time_precision text DEFAULT 'approx',
story_index int NOT NULL,            -- era 내 정수 (UNIQUE: era_id+story_index)
unit_code text DEFAULT 'default',     -- 시간 순 보기 전 복수 선택 구간 코드
unit_title text DEFAULT '전체 흐름',  -- 앱에 표시되는 구간명
unit_order int DEFAULT 1,             -- 시대 안 구간 정렬
landmark_id uuid NOT NULL → landmarks(id),    -- v2 위치 모델
video_url text,
status text DEFAULT 'published'      -- draft / published (어드민 전용)
  CHECK (status in ('draft','published'))
```
- 정렬 기준은 view에서 동적으로 계산 (`time_sort_key`/`code` 컬럼 폐기).
- 활성 published 이야기는 각 era 안에서 `story_index = 1..N` 을 유지한다. 삭제
  승인된 soft-deleted row 는 보존하되 활성 row 뒤쪽 번호로 밀어, 다음 삽입 위치와
  앱/시드 canonical 순서가 어긋나지 않게 한다.
- `unit_code`/`unit_title`/`unit_order`는 시간 순 보기의 중간 선택 단계에 사용한다.
  구약도 시대별 curated 구간(원역사 2개, 족장 3개, 출애굽 3개, 사사 3개,
  왕정 3개, 분열왕국 5개, 포로/귀환 3개)로 나눠 카드 선택에 사용한다.
- `scene_captions`는 `story_scenes`와 같은 순서의 사용자용 이미지 설명이다. 원본
  이미지 프롬프트는 `story_scenes`에 유지하고, 상세 페이지는 이 캡션만 overlay로
  노출한다.
- `background_context`는 이야기 상세 첫 섹션의 1~2문장 사실형 배경 지식이다.
- `story`/`short_story` 컬럼 폐기 — UI는 `background_context` + `summary` + `story_scenes` + `scene_captions`를 사용한다.
- `bible_refs`/`character_codes`가 events row에 직접 임베드 → `event_characters`/`event_bible_refs` 테이블 폐기.
- 외부 기여자 제출 기능 폐기: `submitted_by`/`thumb_url`/`pending_review` 상태 제거됨.

#### `events_ordered` — 정렬 view
```sql
SELECT e.*,
  row_number() OVER (PARTITION BY era_id ORDER BY story_index) AS rank_in_era,
  row_number() OVER (ORDER BY eras.display_order, story_index) AS global_rank
FROM events e JOIN eras ON eras.id = e.era_id
WHERE e.status = 'published';
```
- Repository는 `events` 대신 이 view에서 select.
- view는 `unit_code`/`unit_title`/`unit_order`도 그대로 노출해 Flutter
  `StoryEvent.fromMap()`이 구간 선택 UI를 구성한다. `background_context`도 그대로
  노출해 상세 페이지 배경 지식 카드에 사용한다.
- 새 이야기가 끼어들면 view가 자동 재계산되므로 사전 정렬값 갱신이 불필요.

#### `character_eras` — 인물-시대 매핑 view
```sql
WITH first AS (
  SELECT p.id person_id, p.code, e.era_id, MIN(e.story_index) first_story_index
  FROM characters p
  JOIN events e ON e.character_codes @> ARRAY[p.code] AND e.status='published' AND e.deleted_at IS NULL
  JOIN eras   er ON er.id = e.era_id
  WHERE p.is_active = true
    AND (p.era_codes = '{}'::text[] OR p.era_codes && ARRAY[er.code])  -- 인물 era 소속 필터
  GROUP BY p.id, p.code, e.era_id
)
SELECT person_id, era_id,
  row_number() OVER (PARTITION BY era_id ORDER BY first_story_index, code) AS display_order
FROM first;
```
- 인물 첫 등장 story_index 기준으로 era별 1..N 순서를 동적으로 부여.
- `is_active=false` 인물은 자동 제외.
- `characters.era_codes` 가 비어있지 않으면 인물 카드 노출 era 를 추가로 제한한다 (변화산처럼 OT 인물이 NT 사건 character_codes 에 포함되어도 NT 시대 카드엔 안 뜸). 비어있으면 후방 호환을 위해 통과.

#### `characters.era_codes text[]` — 인물 카드 노출 시대
- 인물이 어느 시대(들)의 카드 화면에 나타날지 정의하는 인물 단위 정책 필드.
- `events.character_codes` 는 "이 사건에 누가 등장했는가"의 사실 데이터로 손대지 않는다 — 변화산 사건의 `character_codes` 에는 모세/엘리야가 그대로 남아 사건 본문/검색에서 보존됨.
- 동명이인은 코드를 분리한다. 현재 분리된 케이스: `saul`(왕 사울, era_monarchy) vs `paul`(=청년 사울, era_nt_apostolic), `joseph`(야곱의 아들, era_patriarch) vs `joseph_nazareth`(예수 양아버지, era_nt_public_ministry).
- 시드 빌더(`tools/seed/build_characters_seed_sql.py`)가 `character_meta.json` 의 `era` 단축형(예: `monarchy`)을 `STYLE_TO_ERA_CODE` 매핑으로 era code(예: `era_monarchy`)로 변환해 채운다. 다중 시대 인물은 향후 character_meta 측에서 배열 확장이 필요할 때 추가.

#### 새 이야기 삽입 패턴 (관리자 직접 / 사역자 제안→관리자 승인)
- `(era_id, story_index)` UNIQUE 제약 → 끼워넣기는 `story_index >= 새값`인 행을 +1 시프트한 뒤 INSERT.
- 동시성: era별 advisory lock 또는 deferred constraint 권장.
- 관리자 직접 경로: `insert_event_at_position(...)` RPC 호출.
- 사역자 제안 경로: `event_proposals` 에 `submit_event_proposal(...)` 로 INSERT → 관리자가 `approve_event_proposal(proposal_id)` 호출 시 내부에서 `insert_event_at_position` 이 실행됨. 상세는 §6 Story proposal workflow.

### 2.2b Story proposal workflow (2026-04 도입, ADR-016)

별도 `admin/` Flutter Web 앱 폐기 후 메인 앱의 웹 버전에 "사역자 제안 → 관리자 승인" 게시판을 도입했다 (Phase 0~1 DB 완료, Phase 2~6 UI 구축 예정).

#### `user_profiles.is_pastor boolean` — 사역자 플래그
- 기본 `false`. 외부 사역자가 메일(admin@brand-i.net)로 성함/소속/직책을 제출하면 운영자가 Supabase 대시보드에서 수동으로 `true` 토글.
- `is_pastor()` SECURITY DEFINER 함수가 RLS/RPC 내부에서 호출자의 값을 읽는다 (`is_admin()` 와 대칭).

#### `event_proposals` — 제안 테이블
```sql
id uuid PK, proposer_user_id uuid FK→auth.users, era_id uuid FK→eras (NULL for 'general'),
proposal_type text CHECK ('new'/'delete'/'general') DEFAULT 'new',
target_event_id uuid FK→events (NULL for 'new'/'general', required for 'delete'),
title text, summary text, background_context text,
character_codes text[], landmark_id uuid → landmarks(id),
start_year/end_year/time_precision, bible_refs jsonb,
story_scenes jsonb, scene_captions jsonb, scene_characters jsonb,
unit_code/unit_title/unit_order,
scene_image_paths text[], scene_image_prompts text[],
proposed_characters jsonb, quiz_questions jsonb,
image_paths text[],   -- 'general' 첨부 이미지 (최대 5장)
after_story_index int,
status text CHECK ('pending'/'approved'/'rejected'),
reviewed_by_user_id, reviewed_at, review_note, approved_event_id uuid FK→events,
synced_to_local_at timestamptz,
position_invalidated_at, position_invalidation_reason,
created_at, updated_at
```
- 제안 종류 (`proposal_type`):
  - `'new'`: 새 이야기 제안 — 기존 플로우, `quiz_questions` 1~3개 강제 (목회자 작성 선택지 3개 + 해설 필수, 승인 시 4번 "헷갈렸어요" 자동 추가).
  - `'delete'`: 기존 이야기 삭제 제안 — `target_event_id` 필수, `quiz_questions` 빈 배열 강제. `summary` 에 삭제 사유 저장.
  - `'general'` (2026-04-29 도입): 앱 일반 제안 — `era_id` / `target_event_id` 모두 NULL. `summary` 가 본문, `image_paths` 가 첨부 이미지 (최대 5장). 승인/거절은 단순 status 변경 (events 변경 없음, 정리 없음).
- CHECK 제약:
  - `chk_proposal_type_target`: new ↔ target IS NULL / delete ↔ target IS NOT NULL / general ↔ target IS NULL
  - `chk_quiz_count_by_type`: new → 1~3개, delete/general → 0개
  - `chk_era_id_required_unless_general`: 'general' 만 era_id NULL 허용
  - `chk_scene_captions_count_for_new`: new → `scene_captions` 길이가 `story_scenes`와 같아야 함
  - `chk_new_story_required_payload`: service-role direct insert 경로에서도 new 제안은
    `landmark_id`, `background_context`, 1개 이상 `story_scenes`,
    장면 수와 같은 `scene_image_paths`/`scene_image_prompts`를 가져야 함
  - `chk_general_image_count`: 'general' 의 image_paths 는 최대 5장
- Partial unique index `uniq_pending_delete_target`: 동일 이벤트에 pending 삭제 제안은 1건만 허용 (두 명이 동시에 같은 이야기 삭제 못 냄).
- 승인 전까지 `events` 와 격리되므로 모바일 앱 쿼리(`events_ordered` view, `events.status='published' AND deleted_at IS NULL`)에 영향 0.
- `approve_event_proposal` RPC 가 `insert_event_at_position` 호출 + 퀴즈 1~3개를 `quiz_questions` 로 풀어 넣음(작성 선택지 3개만 셔플, `choice_d='헷갈렸어요'`) + `approved_event_id` 역참조 기록.
  - 같은 era + 같은 effective `after_story_index`를 겨냥한 다른 pending 제안은 `position_invalidated_at`으로 잠긴다.
  - 관리자는 승인 다이얼로그에서 새 위치를 명시해 `p_after_story_index_override`로 바로 재배치 승인할 수 있다. 제안자가 직접 풀 때는 `revise_proposal_position`을 사용한다.
- `approve_delete_proposal` RPC 가 `events.deleted_at = now()` 로 soft delete. 퀴즈/진도(`quiz_questions` / `user_event_progress`)는 보존 — `events_ordered` view 의 `deleted_at IS NULL` 필터가 앱 전체 가시성을 차단한다. 이후 같은 era 의 활성 published 이벤트를 `story_index = 1..N` 으로 재번호 매기고, 삭제된 위치 이후를 가리키던 pending NEW 제안은 `position_invalidated_at` 으로 잠가 위치 재선택을 요구한다. ⚠️ **HARD DELETE 사용 금지** — `target_event_id` FK 의 `ON DELETE SET NULL` 가 발화되어 `chk_proposal_type_target` 위반(23514) 을 유발한다.
- `approve_general_proposal` / `reject_general_proposal` RPC 는 status 만 갱신 (이미지 정리/row 삭제 없음).

#### `event_proposal_comments` — 댓글
```sql
id uuid PK, proposal_id uuid FK→event_proposals, author_user_id uuid FK→auth.users,
body text, created_at, updated_at
```

#### RLS 요약
- 게시판 SELECT: `is_pastor() or is_admin()` (동료 사역자 간 열람·댓글 공개)
- 제안 INSERT: pastor 만, `proposer_user_id = auth.uid()` 강제, 초기 `status='pending'`
- 제안 UPDATE: pastor 는 본인 것 + pending 에 한함 (내용 수정), admin 은 status/review 필드 변경용
- 댓글: pastor + admin 작성 가능, 본인 것만 UPDATE, 삭제는 본인 또는 admin
- 제안 DELETE: admin 만

#### 주요 RPC
| 이름 | 호출자 | 역할 |
|------|------|------|
| `submit_event_proposal(..., p_quiz_questions)` | pastor | 새 이야기 제안 INSERT (`proposal_type='new'`). 퀴즈 1~3개 검증 (작성 선택지 3개 + 해설 필수). |
| `submit_delete_proposal(target_event_id, reason)` | pastor | 기존 이야기 삭제 제안 INSERT (`proposal_type='delete'`, `summary=reason`). 이미 삭제된 이벤트면 거부. |
| `submit_general_proposal(title, body, image_paths)` | pastor | 일반 제안 INSERT (`proposal_type='general'`). 본문 필수, 이미지 최대 5장. |
| `approve_event_proposal(proposal_id, after_override, character_active_overrides)` | admin | `proposal_type='new'` 전용. 위치 override 가능. `insert_event_at_position` 호출 → events 반영 + 퀴즈 rows insert + proposal status='approved'. |
| `approve_delete_proposal(proposal_id)` | admin | `proposal_type='delete'` 전용. 대상 이벤트 `deleted_at=now()` set (idempotent, soft delete) 후 같은 era 활성 이벤트 `story_index`를 1..N으로 압축. 삭제된 위치 이후 pending NEW 제안은 위치 재선택 필요 상태로 전환. 퀴즈/진도/캐릭터/이미지 정리 모두 미수행. |
| `approve_general_proposal(proposal_id)` | admin | `proposal_type='general'` 전용. status='approved' 만. 이미지 정리 없음. |
| `reject_event_proposal(proposal_id, note)` | admin | status='rejected' + review_note 저장 (new/delete 공통). 반환 jsonb 에 정리 후보 storage 경로 포함. |
| `reject_general_proposal(proposal_id, note)` | admin | `proposal_type='general'` 전용. status='rejected' + 사유만 갱신. |
| `revise_proposal_position(proposal_id, after_story_index, start_year, end_year, landmark_id)` | proposer | 같은 위치 제안이 먼저 승인되어 잠긴 pending new 제안의 위치/연도/랜드마크를 다시 제출. |
| `add_proposal_comment(proposal_id, body)` | pastor/admin | 댓글 INSERT 편의 함수 |

상세 SQL: [db_init.sql](../db_init.sql) §Story proposal workflow. (개별 증분 마이그레이션 파일은 폐기 — `db_init.sql` 이 단일 진실 소스.)

#### Soft delete — events.deleted_at

이야기 삭제 제안이 승인되면 `events.deleted_at` 이 `now()` 로 set 된다. `quiz_questions`/`user_event_progress`/`user_quiz_attempts`/`user_event_emotion_marks` 의 FK 연쇄 삭제나 orphan 을 피하기 위해 hard delete 는 의도적으로 피한다 ([ADR-017](ADR.md#adr-017-이야기-삭제-제안--soft-delete--퀴즈-필수화)). 여기서 "보존"은 DB의 과거 기록 row 를 남긴다는 뜻이지, 앱에 보이는 진행률을 유지한다는 뜻이 아니다. 앱과 프로필은 active `events_ordered` id 기준으로 진행/퀴즈/감정 기록을 필터링하므로 삭제된 이야기에만 있던 완료, 퀴즈, 감정 기록은 현재 진행률과 달력/기록 탭에서 빠진다. 대신 같은 era 의 활성 published 이벤트를 `story_index = 1..N` 으로 즉시 재번호 매기고, soft-deleted row 는 활성 row 뒤쪽 번호로 이동한다 ([ADR-028](ADR.md#adr-028-삭제-승인-후-active-story_index-재번호-매김)).

앱 전체에서 자동으로 숨겨지도록 두 곳에 필터를 건다:

| view/함수 | 필터 |
|----------|------|
| `events_ordered` (view) | `where e.status = 'published' and e.deleted_at is null` |
| `character_eras` (view) | join 조건에 `and e.deleted_at is null` |
| `list_characters_by_era(era_id)` RPC | join 조건에 `and e.deleted_at is null` |

Flutter 앱은 사건 목록을 `events_ordered` / RPC 로만 호출한다. 사용자 기록 조회도 active `events_ordered` id 와 교차해 필터링하므로 프로필의 인물 진행도, 장소 진행도, 기록 탭 퀴즈 통계, 감정 달력에서 soft-deleted event 는 제외된다. `fetchQuizQuestions(event_id)` 는 앱 흐름상 삭제된 event 로 도달하지 않아 별도 필터 생략 (이미 목록에서 제외됨).
삭제로 인해 같은 era 의 숫자 위치가 바뀌면, 삭제된 `story_index` 이상을 가리키던
pending NEW 제안은 `position_invalidated_at` 이 set 된다. 제안자는 현재 활성 목록을
보고 `revise_proposal_position` 으로 위치/연도/랜드마크를 다시 제출해야 한다.

#### `bible_verses` — KRV 성경 전문 (31,102절)
```sql
id uuid PK, translation text DEFAULT 'KRV',
book_no int, book_name text, chapter_no int,
verse_no int, verse_text text,
UNIQUE(translation, book_no, chapter_no, verse_no)
```

#### `landmarks` — 위치 모델 v3 (region polygon + 시각 마크 통합)
```sql
id uuid PK, code text UNIQUE, name text,
description text, emoji text DEFAULT '📍', category text,
lat double precision, lng double precision,
kind text DEFAULT 'city'
  CHECK (kind in (
    'region',
    'mountain','city','sea','river','island',
    'palace','wilderness','holy_site','campsite',
    'valley','battlefield',
    'anchor','minor','point'
  )),
polygon jsonb,                            -- kind='region' 만 채움
parent_landmark_id uuid → landmarks(id),  -- non-region 마크의 parent region
alias_group_id uuid → landmark_alias_groups(id),  -- 같은 점 다른 시대 이름
display_priority int DEFAULT 0,
era_codes text[] DEFAULT '{}',
related_event_codes text[] DEFAULT '{}',
is_active boolean DEFAULT true
```
- **v2 위치 모델 (2026-05-04)**: `events.lat/lng/place_name` 직접 좌표 → `events.landmark_id` FK 로 전환. 시드: `assets/landmarks/landmarks_v2_draft.json` → `tools/seed/build_landmarks_v2_seed_sql.py` → `supabase/events/landmarks_v2_seed.sql`.
- **3 종**:
  - `region`: 폴리곤으로 영역 표시. 사건 발생 가능 영역을 빈틈없이 덮음. parent 없음.
  - `anchor`: region 의 대표 점, 자주 사건이 일어나는 핵심 위치 (예: 예루살렘, 시내산). parent = region.
  - `minor`: region 안의 작은 위치 (예: 베다니, 골고다). parent = region.
- **alias_group_id**: 같은 지리적 위치인데 시대마다 다른 이름인 경우 같은 그룹 (예: 모리아산 ↔ 예루살렘 성전, 시내산 ↔ 호렙산, 시날 ↔ 바벨론).
- **관련 테이블**: `landmark_alias_groups (id, group_key UNIQUE, description)`.
- RLS: `landmarks_read_active` (is_active = true). `anon, authenticated` 에 SELECT grant.
- 인덱스: `idx_landmarks_active` (활성 partial), `idx_landmarks_era_codes_gin` (era 필터 GIN).
- 스키마: `db_init.sql` 에 통합. 별도 마이그레이션 없음.
- Repository: `StoryRepository.fetchLandmarks()` (display_priority 오름차순, name asc 정렬). 클라이언트가 selectedEraId 의 era code 로 필터.
- 클라이언트: `StoryState.landmarks` 에 부팅 시 한 번 전체 로드. `StoryHomeScreen` 이 selectedEraId 로 필터한 non-region landmark 는 `StoryMapPanel.activeLandmarks`, region polygon 은 `StoryMapPanel.eraRegionLandmarks` 로 전달한다. 운영 지도는 이를 `StoryTerrain3dMap` WebView 내부 MapLibre GeoJSON layer/DOM marker 로 렌더링한다.
- PoC 단계는 emoji 컬럼만 사용. 향후 실제 일러스트가 필요하면 `icon_storage_path` 같은 새 컬럼 추가로 확장.

### 2.2c Notifications & Push (2026-04-22 도입)

인앱 알림함(bell 아이콘)과 FCM 푸시를 지원한다. 하이브리드 팬아웃:

#### `notifications` — 개인 알림 (Fan-out on Write)
```sql
id uuid PK, user_id uuid FK→auth.users,
type text CHECK IN (
  'proposal_comment','proposal_comment_admin','new_proposal_admin',
  'proposal_approved','proposal_rejected','proposal_position_invalidated',
  'quiz_completed'
),
title text, body text, deep_link text, payload jsonb,
read_at timestamptz, created_at timestamptz
```
- `deep_link`: `/proposal/<id>` | `/event/<id>` | `/weekly` 중 하나.
- 인덱스: `(user_id, created_at desc)` + unread 필터 부분 인덱스.

#### `broadcast_notifications` — 공지 (Fan-out on Read)
```sql
id uuid PK, type text CHECK IN ('new_event'),
target_audience text CHECK IN ('all','pastor_or_admin'),
title text, body text, deep_link text, payload jsonb, created_at timestamptz
```
- `new_event` 만 broadcast 테이블을 사용한다 (bell + 푸시 둘 다 필요).
- 월/수/금 정기 푸시는 **push-only** — broadcast 테이블에 row 안 만들고 `send-push` 만 호출 (bell drop 에 안 쌓임).

#### `broadcast_notification_reads` — 읽음 교차표
```sql
user_id uuid, broadcast_id uuid, read_at timestamptz,
PRIMARY KEY(user_id, broadcast_id)
```

#### `user_push_tokens` — FCM 디바이스 토큰
```sql
id uuid PK, user_id uuid, platform text CHECK IN ('web','ios','android'),
token text UNIQUE, device_label text
```

#### `weekly_character_selection` — 금주 인물 단일 소스
```sql
week_key text PK ('YYYY-M-D'), character_code text FK→characters, picked_at timestamptz
```
- pg_cron 이 월요일 00:00 UTC (= KST 9시) 에 `pick_weekly_character()` 실행 → 이 테이블에 row 저장 후 주간 탐험 시작 FCM 을 직접 발송.
- Dart 쪽 `weekly_selection.dart` 의 `seedFromKey` 를 plpgsql `_seed_from_week_key` 로 포팅해 동일 결과 보장.

#### 트리거
- `trg_notify_on_new_proposal` (event_proposals AFTER INSERT) → admin 전원에게 개인 알림
- `trg_notify_on_proposal_comment` (event_proposal_comments AFTER INSERT) → proposer + admin
- `trg_notify_on_proposal_reviewed` (event_proposals AFTER UPDATE) → proposer 에게 승인/거절 알림
- `trg_notify_on_new_event` (events AFTER INSERT) → 전체 대상 브로드캐스트. **세션 플래그 `app.suppress_event_broadcast='true'` 가 set 돼 있으면 skip** — `approve_event_proposal` RPC 는 사건+신규 인물 정보를 직접 묶어 broadcast row 1건을 만들기 위해 이 플래그를 사용.
- `trg_push_after_broadcast` (broadcast_notifications AFTER INSERT) → `_fire_push_broadcast` 호출 → `send-push` Edge Function 으로 FCM 자동 발송.

#### Push 디스패치 인프라 (2026-05-11 도입)
- **`_fire_push_broadcast(title, body, deep_link, type)`** — Vault 의 `service_role_key` + `supabase_url` 두 secret 을 읽어 `pg_net.http_post` 로 `send-push` Edge Function 호출. 실패 시 raise warning 후 silent return (호출 트랜잭션 안 깨짐).
- 사전 조건: ① `pg_net` 확장 활성화, ② Vault 에 두 secret 등록 (`service_role_key`, `supabase_url`), ③ `send-push` 함수 배포.
- 적용: `make db-init ENV=<env>` (db_init.sql 전체 DROP & CREATE).

#### 주요 RPC
| 함수 | 용도 |
|------|------|
| `list_my_notifications(limit, only_unread)` | 개인 + 공지 UNION, 최근 30일 |
| `unread_notification_count()` | bell 배지용 |
| `mark_notification_read(id)` / `mark_broadcast_read(id)` | 개별 읽음 |
| `mark_all_notifications_read()` / `mark_all_broadcasts_read()` | 일괄 읽음 |
| `notify_quiz_completed(event_id)` | 퀴즈 완료 시 클라이언트가 호출 |
| `register_push_token(token, platform, label)` | FCM 토큰 upsert |
| `unregister_push_token(token)` | 로그아웃/토큰 갱신 시 |
| `pick_weekly_character()` | pg_cron 월요일 KST 9시 — 금주 인물을 뽑고 주간 탐험 시작 push-only 발송 |
| `dispatch_daily_exploration_push()` | pg_cron 수요일 KST 9시 — KST 날짜 시드로 오늘의 사건 제목을 고른 뒤 “「사건명」 사건을 함께 탐험해봐요.” push-only 발송 |
| `notify_weekly_diary_reflection()` | pg_cron 금요일 KST 9시 — 나의 다이어리 묵상/신앙 정리 push-only 발송 |

#### 30일 보관
- hard delete 하지 않음. `list_my_notifications` / `unread_notification_count` 가 `WHERE created_at > now() - interval '30 days'` 로 필터.

### 2.2 사용자 테이블

#### `user_profiles`
```sql
user_id uuid PK FK→auth.users, share_id text UNIQUE (7자리 자동생성),
nickname text, photo_url text, prayer_request text
```

#### `user_event_progress`
```sql
user_id uuid FK→auth.users, event_id uuid FK→events,
is_bible_read boolean DEFAULT false, is_quiz_completed boolean DEFAULT false,
is_completed boolean DEFAULT false, completed_at timestamptz, created_at, updated_at,
UNIQUE(user_id, event_id)
```
- 본문 읽기/퀴즈 완료/감정 새김이 모두 끝났을 때만 `is_completed=true`.
- 게이미피케이션(score/xp) 계획 없어서 제거됨.

#### `user_event_emotion_marks` (2026-05-25)
```sql
user_id uuid FK→auth.users, event_id uuid FK→events,
emotion_key text, emotion_label text, emotion_emoji text,
note text CHECK char_length(note) <= 100, created_at, updated_at,
UNIQUE(user_id, event_id)
```
- 이야기 상세의 "지도 위에 새기기" 결과. 감정 선택지는 앱 모델의 8개 옵션과 DB CHECK가 함께 제한한다.
- 이 row가 있어야 사건 완료 도장이 찍히고 지도/프로필에 감정 새김이 반영된다.
- 사용자가 "완료 취소"를 누르면 본인 row를 delete 하고, `user_event_progress.is_completed`도 다시 false로 동기화한다.

#### `user_companion_diary_entries` (2026-06-23)
```sql
id uuid PK, user_id uuid FK→auth.users,
entry_date date, title text CHECK <= 80, body text CHECK <= 1000,
created_at, updated_at,
UNIQUE(user_id, entry_date)
```
- 프로필 "나의 다이어리" 탭의 "오늘의 동행 일지" 저장소.
- `entry_date`는 앱이 계산한 KST 날짜를 저장하며, `(user_id, entry_date)` unique 제약으로 하루 1개만 허용한다.
- 본인만 read/write/delete 가능한 RLS를 사용한다.

#### `user_notes`
```sql
id uuid PK, user_id uuid FK→auth.users,
title text, content text, created_at, updated_at
```
- 레거시 노트 기능 저장소. 현재 앱 UI/Repository에서는 사용하지 않는다.

#### `user_saved_verses`
```sql
id uuid PK, user_id uuid FK→auth.users,
translation text, book_no int, book_name text,
chapter_no int, verse_no int, verse_text text,
comment text DEFAULT '' CHECK char_length(comment) <= 200,
created_at timestamptz
```
- 성경 리더 별표 저장 시 optional 묵상 코멘트를 함께 저장한다. 빈 코멘트도 저장 가능한 정상 상태다.

#### `user_saved_events` (2026-05-26)
```sql
user_id uuid FK→auth.users, event_id uuid FK→events,
created_at timestamptz, PRIMARY KEY(user_id, event_id)
```
- 사건 상세 제목 옆 별표 토글로 저장/해제한다.
- 프로필 저장 탭에서 era 순, story_index 순으로 카드 목록을 보여 준다.

#### `user_intercessory_prayers`
```sql
id uuid PK, subscriber_id uuid FK→auth.users,
target_user_id uuid FK→auth.users
```

_(2026-05-08: `user_daily_activity` 테이블 — "연속 출석일 / 연속 인물 공부"
스트릭 기능 — 제거됨. db_init.sql 의 `drop table if exists` 만 정리용으로 유지.)_

#### 매일/주간 탐험 진행도 (2026-06-23)
- `daily_quiz`, `user_daily_quiz_attempts`, `weekly_quiz_progress` 는 제거했다.
- 매일 탐험과 주간 탐험은 별도 문제/진행도 테이블을 만들지 않고, 앱의 일반 사건 상세 플로우를 여는 진입점으로만 동작한다.
- 읽기/퀴즈/감정 새김 결과는 모두 `user_event_progress`, `user_quiz_attempts`, `user_event_emotion_marks` 에 저장되어 홈 지도, 프로필, 나의 다이어리와 동일하게 연결된다.
- 이미 완료한 사건이 매일/주간 탐험에 다시 선정될 수 있다. 이 경우에도 동일 사건 상세를 연다. 매일 탐험은 해당 사건의 감정 기록이 이전 날짜면 재탐험 문구를, 오늘 KST 기록이면 축복 문구를 사건 카드 패널에 표시한다. 주간 탐험은 별도 재탐험 문구를 표시하지 않는다.

#### `user_quiz_attempts` (2026-05-25)
```sql
user_id uuid FK→auth.users, event_id uuid FK→events,
correct_count, total_count, wrong_count, confused_count,
selected_answers jsonb, updated_at,
UNIQUE (user_id, event_id)
```
- 이야기별 최근 퀴즈 풀이 결과. "헷갈렸어요" 선택과 오답을 프로필/사건 카드의 복습 신호로 보여 주기 위한 본인 전용 기록.
- 매일/주간 탐험에서 푼 결과도 같은 사건 학습 기록으로 저장된다.
- RLS: 본인만 read/write.

### 2.3 검색/ML (향후)

#### `search_embeddings`
```sql
id uuid PK, source_type text, source_id uuid,
content_preview text, embedding vector(1536)
```

#### `quiz_questions` (데이터 미구축)
```sql
id uuid PK, event_id uuid FK→events,
question text, choice_a~d text, answer_index int,
explanation text, display_order int
```
- 시드/제안 승인 경로는 `choice_d='헷갈렸어요'`를 자동으로 채우고, 정답은 `choice_a~c` 중 하나만 가리킨다.

## 3. RLS 정책

| 테이블 / view | 읽기 | 쓰기 |
|--------|------|------|
| eras, bible_verses, quiz_questions | 공개 (anon) | — |
| persons | 공개, **`is_active = true`만 노출** (admin은 전체) | admin만 |
| events | 공개, **`status = 'published'`만 노출** (admin은 전체) | admin만 |
| events_ordered, character_eras (view) | 공개 | — (view, underlying RLS 따름) |
| user_profiles | 본인만 | 본인만 |
| user_event_progress | 본인만 | 본인만 |
| user_quiz_attempts | 본인만 | 본인만 |
| user_event_emotion_marks | 본인만 | 본인만 |
| user_companion_diary_entries | 본인만 | 본인만 |
| user_notes | 본인만 | 본인만 (레거시, 현재 앱 미사용) |
| user_saved_verses | 본인만 | 본인만 |
| user_saved_events | 본인만 | 본인만 |
| user_intercessory_prayers | 본인 구독 | 본인만 |

관리자 식별: `auth.users.raw_app_meta_data ->> 'role' = 'admin'`. `is_admin()`
PL/pgSQL 함수로 RLS 안에서 사용.

## 4. PostgreSQL 함수 / 트리거

| 이름 | 종류 | 역할 |
|------|------|------|
| `generate_profile_share_id()` | 함수 | 유니크 7자리 영숫자 코드 생성 |
| `handle_new_user_profile()` | 트리거 함수 | auth.users INSERT → user_profiles 자동 생성 |
| `on_auth_user_created` | 트리거 | auth.users AFTER INSERT → handle_new_user_profile() |
| `touch_updated_at()` | 트리거 함수 | updated_at 자동 갱신 (profiles/notes/daily_activity) |
| `is_admin()` | 함수 | app_metadata.role == 'admin' 여부 반환 (RLS/RPC에서 호출) |
| `list_intercessory_prayer_requests(p_limit, p_offset)` | RPC | 중보기도 목록 페이지네이션 |
| `add_intercessory_prayer_by_share_id(p_share_id)` | RPC | 공유 코드로 중보기도 추가 |
| `insert_event_at_position(...)` | RPC (admin 전용) | 새 이야기를 era 안 특정 위치에 끼워 넣기. story_index 시프트 + INSERT 를 advisory lock 안에서 처리. status 는 항상 'published'. |
| `approve_delete_proposal(...)` | RPC (admin 전용) | 삭제 제안 승인. soft delete + 같은 era 활성 story_index 압축 + 영향받은 pending NEW 제안 위치 무효화를 advisory lock 안에서 처리. |

## 5. Repository 패턴

### 5.1 StoryRepository (`lib/data/story_repository.dart`)

| 메서드 | 쿼리 | 반환 |
|--------|------|------|
| `fetchEras()` | `eras` ORDER BY display_order → `hiddenEraCodes` 제외 | `List<Era>` |
| `fetchCharactersByEra(eraId)` | `character_eras` view JOIN `persons` WHERE era_id ORDER BY display_order | `List<Character>` |
| `fetchEventsByEra(eraId)` | `events_ordered` view WHERE era_id ORDER BY rank_in_era → 숨김 era 제외 | `List<StoryEvent>` |
| `fetchEventsForCharacter(personCode)` | `events_ordered` WHERE character_codes @> ARRAY[code] ORDER BY global_rank → 숨김 era 제외 | `List<StoryEvent>` |
| `fetchEventsByIds(eventIds)` | `events_ordered` WHERE id IN (...) ORDER BY global_rank → 숨김 era 제외 | `List<StoryEvent>` |
| `fetchCharacterTimelineOrder()` | `events_ordered` → 숨김 era 제외 → personCode별 첫 등장 global_rank | `Map<String, int>` |
| `searchEventsByText(query)` | 전체 `events_ordered` + persons name lookup → 숨김 era 제외 → 클라이언트 가중치 검색 | `List<StoryEvent>` (상위 20) |
| `fetchQuizQuestions(eventId)` | `quiz_questions` WHERE event_id | `List<QuizQuestion>` |
| `fetchBibleVersesByChapter(...)` | `bible_verses` WHERE book_no, chapter_no | `List<BibleVerse>` |
| `fetchCompletedEventIds(userId)` | `user_event_progress` WHERE is_completed | `Set<String>` |
| `fetchEventProgress(userId)` | `user_event_progress` WHERE user_id | `Map<eventId, read/quiz/completed>` |
| `upsertEventProgress({userId, eventId, isBibleRead, isQuizCompleted, isCompleted})` | UPSERT `user_event_progress` ON (user_id, event_id) | void |
| `fetchQuizAttemptSummaries(userId)` | `user_quiz_attempts` WHERE user_id ORDER BY updated_at DESC | `Map<eventId, QuizAttemptSummary>` |
| `upsertQuizAttempt(...)` | UPSERT `user_quiz_attempts` ON (user_id, event_id) | void |
| `fetchEventEmotionMarks(userId)` | `user_event_emotion_marks` WHERE user_id ORDER BY updated_at DESC | `Map<eventId, EventEmotionMark>` |
| `upsertEventEmotionMark(...)` | UPSERT `user_event_emotion_marks` ON (user_id, event_id) | void |
| `deleteEventEmotionMark(...)` | DELETE `user_event_emotion_marks` WHERE user_id AND event_id | void |
| `fetchSavedEventIds(userId)` | `user_saved_events` WHERE user_id ORDER BY created_at DESC | `Set<String>` |
| `toggleSavedEvent(...)` | `user_saved_events` INSERT/DELETE | `bool` |

검색 가중치 (`scoreEventMatch`): title +130, summary +120, story_scenes +100, person names +80, background_context +70, place +30. 토큰별 매치 추가점.

### 5.2 UserRepository (`lib/data/user_repository.dart`, 485줄)

| 메서드 | 주요 쿼리 | 반환 |
|--------|----------|------|
| `ensureSignedInUser(user)` | user_profiles SELECT/INSERT | `AppUserProfile` |
| `fetchUserProfile(userId)` | user_profiles SELECT | `AppUserProfile` |
| `updateUserProfile(...)` | user_profiles UPDATE | `AppUserProfile` |
| `uploadProfileImage(...)` | Storage uploadBinary | `String` (public URL) |
| `fetchSavedVersesPage(...)` | user_saved_verses SELECT + 페이지네이션 | `PagedResult<SavedBibleVerse>` |
| `fetchSavedVerseMap(userId)` | user_saved_verses SELECT 본인 전체 | `Map<verseKey, SavedBibleVerse>` |
| `saveBibleVerse(...)` | user_saved_verses INSERT (comment 포함) | `SavedBibleVerse` |
| `deleteSavedVerse(verseId)` | user_saved_verses DELETE | void |
| `fetchCompanionDiaryEntries(userId)` | user_companion_diary_entries WHERE user_id ORDER BY entry_date DESC | `List<UserCompanionDiaryEntry>` |
| `upsertCompanionDiaryEntry(...)` | UPSERT `user_companion_diary_entries` ON (user_id, entry_date) | `UserCompanionDiaryEntry` |
| `deleteCompanionDiaryEntry(...)` | DELETE `user_companion_diary_entries` WHERE user_id AND entry_date | void |
| `fetchIntercessoryPrayerPage(...)` | RPC list_intercessory_prayer_requests | `PagedResult<IntercessoryPrayerItem>` |
| `addIntercessoryPrayerByShareId(shareId)` | RPC add_intercessory_prayer_by_share_id | `IntercessoryPrayerItem` |
| `fetchCharacterStudyProgress(...)` | user_event_progress + events_ordered.character_codes (배열 매치) | `List<CharacterStudyProgress>` |

### 5.x NotificationRepository (`lib/data/notification_repository.dart`, 2026-04-22)

| 메서드 | 주요 쿼리 | 반환 |
|--------|----------|------|
| `fetchNotifications({limit, onlyUnread})` | RPC `list_my_notifications` | `List<AppNotification>` |
| `fetchUnreadCount()` | RPC `unread_notification_count` | `int` |
| `markRead(notification)` | source 에 따라 `mark_notification_read` 또는 `mark_broadcast_read` | void |
| `markAllRead()` | `mark_all_notifications_read` + `mark_all_broadcasts_read` | void |
| `watchUnreadCount({interval})` | polling 스트림 (기본 30초) | `Stream<int>` |
| `registerPushToken(...)` / `unregisterPushToken(token)` | RPC `register_push_token` / `unregister_push_token` | void |
| `notifyQuizCompleted(eventId)` | RPC `notify_quiz_completed` (퀴즈 완료 시) | void |

### 5.3 AuthRepository (`lib/data/auth_repository.dart`, 77줄)

| 메서드 | 역할 |
|--------|------|
| `signInWithApple()` | Apple ID 로그인 (SHA256 nonce) |
| `signInWithGoogle()` | Google 로그인. Android는 `google_sign_in` 네이티브 토큰 → `signInWithIdToken`, Web/iOS는 Supabase OAuth redirect |
| `signInWithKakao()` | Kakao 로그인 |
| `signOut()` | 로그아웃 |

## 6. Storage

Storage 버킷은 `db_init.sql` 에 선언된다. 앱 런타임/public 자산과 release-only
원본 archive는 분리한다.

### `profile-images` (기존)
- **제한**: 5 MB, PNG/JPEG/WebP
- **경로 패턴**: `{userId}/profile_{timestamp}.{ext}`
- **접근**: 본인만 업로드, public URL 로 읽기

### `characters` (신규, 2026-04)
- 성경 인물 아바타 — `generate_event_story_images_vertex.py` 스타일의 장면
  생성에서 AI 참조 이미지로 inline 첨부됨.
- **제한**: 10 MB, PNG/WebP
- **경로 패턴**: `{code}.png`  (예: `abraham.png`, `jesus.png`)
- **쓰기 권한**: admin 만 (`is_admin()`). 초기 부트스트랩은
  `make upload-character-avatars` 로 `assets/avatars/*.png` 일괄 업로드.
- **읽기 권한**: public — 프론트 `ProposalCharacterRow` 아바타 노출 +
  Edge Function 이 base64 로 재포장해 Vertex 에 전달.
- **DB 연동**: `characters.avatar_storage_path` 가 `{code}.png` 값을 보관.
- **운영 도구**: `make upload-character-avatars` 는 업로드 전에 `characters`
  버킷을 먼저 비운다. 비운 뒤에도 기존 객체가 감지되면 중단하고,
  timeout/429/5xx 응답은 재시도한다.

### `proposal-scenes` (신규, 2026-04)
- 제안 작성 폼에서 생성된 장면 AI 이미지.
- **제한**: 10 MB, PNG/JPEG/WebP
- **경로 패턴**: `{user_id}/{draft_id}/scene_{idx}.png`
- **쓰기 권한**: authenticated 본인 폴더. 실제 업로드 주체는 Edge Function
  (`generate-proposal-scene`) 으로, service role key 사용.
- **읽기 권한**: public — 제안 상세 페이지에서 다른 pastor/admin 이 열람.
- **DB 연동**: `event_proposals.scene_image_paths` 가 이 경로 목록을 유지
  (인덱스 순서 = 장면 순서).

### `story-image-sources` (release-only, private)
- 앱 번들 썸네일을 만들기 위한 원본 장면 PNG archive.
- **제한**: 20 MB, PNG/JSON(manifest)
- **경로 패턴**:
  - `story_images/<source_key>/scene_*.png` (`source_key`는 한글 source dir의 SHA prefix)
  - `_manifests/story_images_manifest.json`
- **접근**: public read 없음. 앱 런타임은 사용하지 않고 service_role 운영 도구
  `sync_story_image_sources.py`만 pull/push한다.
- **운영**: `make ensure-story-image-sources`가 manifest 기준 missing/changed 원본을
  내려받는다. `make upload-story-image-sources`는 current active story 원본 중
  신규/변경 PNG를 upsert하고, 이전 manifest에만 남은 stale object를 삭제한 뒤
  active manifest를 업로드한다.
- **삭제 범위**: stale 삭제는 bucket listing 전체가 아니라 이전
  `_manifests/story_images_manifest.json` entries와 current active entries의 차이만
  대상으로 한다. manifest에 없는 수동 object는 건드리지 않는다.
- **db-init 보존**: `db_init.sql`에는 bucket 정의가 있지만
  `tools/supabase/purge_owned_buckets.py`의 purge 대상이 아니다. 따라서
  `make db-init`이 `characters`, `proposal-scenes`, `proposal-characters`를 비워도
  이 source archive는 유지된다.

## 7. Edge Functions

### `generate-proposal-scene`
- 경로: `supabase/functions/generate-proposal-scene/index.ts`
- 호출 시점: 제안 작성 폼의 "이미지 생성" 버튼
- 배포: `supabase functions deploy generate-proposal-scene`
- 배포 전제 secrets:
  - `GOOGLE_CLOUD_PROJECT` — GCP 프로젝트 id
  - `GOOGLE_CLOUD_LOCATION` — Vertex region (기본 `global`)
  - `GCP_SERVICE_ACCOUNT_JSON` — service account JSON (JSON 전체를 한 줄로)
- 기능 개요:
  1. Supabase JWT 로 사용자 인증
  2. `characters.code` 로 아바타 PNG 조회 → Vertex Gemini multimodal 요청의
     `inlineData` 로 첨부
  3. `COMMON_SCENE_STYLE` + 장면 텍스트 + 장소/제목으로 prompt 조립
  4. 생성된 PNG 를 `proposal-scenes/{uid}/{draft}/scene_{idx}.png` 로 upsert
  5. 반환: `{ storage_path, prompt }`
- 동시성: 프론트가 modal overlay 로 블록 (한 번에 한 장만)
- 상세: `supabase/functions/generate-proposal-scene/README.md`

### `send-push` (2026-04-22, 자동 디스패치 2026-05-11)
- 경로: `supabase/functions/send-push/index.ts`
- 호출 경로:
  - **broadcast_notifications AFTER INSERT** → `trg_push_after_broadcast` → `_fire_push_broadcast` → 이 함수 (자동)
  - **주간/매일 cron** → `_fire_push_broadcast` 직접 호출 (broadcast 테이블 우회)
  - 수동 발송: `supabase.functions.invoke('send-push', { ... })`
- 배포: `supabase functions deploy send-push`
- 배포 전제 secrets:
  - `FIREBASE_SERVICE_ACCOUNT` — Firebase 서비스 계정 JSON 전체
- 기능 개요:
  1. 입력 body 의 `user_id`(개인) 또는 `broadcast: true`(공지) 로 대상 판정
  2. `user_push_tokens` 에서 FCM 토큰 조회
  3. OAuth 2.0 토큰 발급 (GCP scope: `firebase.messaging`)
  4. FCM HTTP v1 API `POST /v1/projects/{id}/messages:send` 로 각 디바이스에 전송
  5. 404/UNREGISTERED 응답은 해당 토큰을 자동 정리
- 상세: `supabase/functions/send-push/README.md` + `docs/guides/PUSH_SETUP.md`

### 로컬 개발

```bash
supabase start                                 # 로컬 스택
supabase functions serve \
  --env-file .env.supabase.secrets \
  generate-proposal-scene
```

브라우저/Flutter 에서 호출 시 base URL 을 로컬 것으로 바꿔 테스트.

배포 전 타입 체크:

```bash
tools/supabase/check_edge_functions.sh
```

이 스크립트는 `generate-proposal-character`, `generate-proposal-scene`,
`send-push` 의 `index.ts` 를 모두 `deno check` 한다.

## 8. DB 개발/운영 적용 워크플로우

> 현재 정책: dev 는 `db_init.sql` 기반 reset 으로 최종 상태를 검증한다.
> real 은 운영 DB 로 취급하며 reset 하지 않는다. schema/RLS/RPC/cron 변경은
> `supabase/patches/*.sql`의 idempotent patch 로 적용한다.

### 8.1 적용 경로

| 트랙 | 역할 | 적용 환경 | 적용 명령 |
|------|------|----------|----------|
| `db_init.sql` | 스키마 **단일 진실 소스** (최종 desired schema) | dev reset / 신규 bootstrap | `make db-init ENV=dev` |
| `supabase/patches/*.sql` | 운영 DB 를 보존하며 schema/RLS/RPC/cron 변경 | dev/real patch | `make apply-patch ENV=<env> PATCH=<file>` |
| `supabase/seeds/*.sql`, `supabase/events/*.sql`, `supabase/quizzes/*.sql` | 기준 콘텐츠/퀴즈/성경 구절 seed | dev/real seed 적용 | `make apply-seeds ENV=<env>` |

Makefile 운영 타겟의 기본값은 `ENV=dev`다. real DB/Storage에 적용할 때만
명시적으로 `ENV=real`을 붙인다 (`ENV=prod`도 real alias로 동작한다).
`make db-init ENV=real`은 기본 차단되어 있으며, 신규/복구 bootstrap 에서만
`CONFIRM_REAL_DB_INIT=1`을 붙여 실행한다.
신규 Supabase 환경 구축 순서와 Auth/Push/secret/Vault 체크리스트는
[DB_SETUP.md](guides/DB_SETUP.md)를 따르고, 일상 개발/배포 순서는
[develop-flow.md](guides/develop-flow.md)를 따른다.

개발 DB 를 기준 상태로 다시 세우는 표준 시퀀스:

```bash
make seed-all && make db-init && make apply-seeds && make upload-character-avatars
```

### 8.2 변경 시 작업 흐름

스키마/함수/RLS/cron/extension 등 DB 구조가 바뀌면 **반드시 `db_init.sql` 에 최종 상태를 반영**한다.
seed 로 들어가는 기준 데이터는 생성 스크립트와 출력 SQL 을 함께 갱신한다.

1. **`db_init.sql`** — 변경 후 최종 schema/function/RLS/cron 상태.
2. **Seed builder** — 기준 데이터 생성 로직 (`tools/seed/*`) 이 바뀌면 수정.
3. **Seed SQL** — `make seed-all` 또는 필요한 개별 `make seed-*` 로 재생성.
4. **문서** — schema 는 이 문서, 파이프라인은 `docs/DATA_PIPELINE.md` 갱신.

real 운영 DB 에는 같은 변경을 patch SQL 로 적용한다. patch 는 `alter table if exists`,
`add column if not exists`, `create or replace function`, `drop policy if exists`처럼
여러 번 실행해도 안전하게 작성한다.

### 8.3 적용 절차

```bash
# 1. 기준 SQL 재생성
make seed-all

# 2. DB 구조 전체 리셋
make db-init ENV=dev

# 3. 기준 데이터 적용
make apply-seeds ENV=dev

# 4. Storage 기준 아바타 업로드
make upload-character-avatars ENV=dev

# 5. real 운영 DB 에 적용할 patch dry-run/검토 후 적용
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
```

`make db-init`은 SQL 실행 전에 앱 소유 재생성 버킷(`characters`,
`proposal-scenes`, `proposal-characters`)을 REST API로 먼저 비운다.
service_role 키가 없거나 purge가 실패하면 기존 파일이 남지 않도록 DB 초기화도
중단한다. 사용자 업로드 버킷인 `profile-images`와 release 원본 archive인
`story-image-sources`는 건드리지 않는다.

### 8.4 이력 보존

- ADR-023 은 이전 증분 마이그레이션 정책의 역사로 보존한다.
- ADR-025 는 dev reset 정책의 역사로 보존한다.
- real 운영 DB 는 reset 이 아니라 patch 방식으로 수정한다.

### 8.5 자주 빠트리는 것

- **스키마 변경을 seed SQL 에만 넣기 금지**: table/column/function/RLS 는 `db_init.sql` 에 있어야 한다.
- **기준 데이터 변경 후 SQL 재생성 누락**: `tools/seed/*` 나 `assets/*` 를 바꾸면 `make seed-all`
  또는 관련 `make seed-*` 를 실행해 출력 SQL 도 갱신한다.
- **부분 리셋 착각**: `make db-init` 은 파괴적이다. 개발 DB 리셋용으로만 사용한다.

## 9. Supabase 공식 Agent Skills

본 프로젝트는 Supabase 공식 [agent-skills](https://github.com/supabase/agent-skills)와 병행 사용을 권장한다.

### 설치

```bash
# 1. 마켓플레이스 등록 (최초 1회)
claude plugin marketplace add supabase/agent-skills

# 2. 플러그인 설치
claude plugin install supabase@supabase-agent-skills
claude plugin install postgres-best-practices@supabase-agent-skills

# 또는 npx로 특정 스킬만
npx skills add supabase/agent-skills --skill supabase
npx skills add supabase/agent-skills --skill supabase-postgres-best-practices
```

### 제공되는 공식 플러그인

| 플러그인 | 커버 영역 |
|---------|----------|
| `supabase` | Database / Auth / Edge Functions / Realtime / Storage / Vectors / Cron / Queues, supabase-js/ssr, Next.js/React/SvelteKit 통합, JWT/RLS 트러블슈팅 |
| `postgres-best-practices` | Query Performance, Connection Management, Security & RLS, Schema Design, Concurrency & Locking, Data Access Patterns, Monitoring, Advanced Features — 8개 카테고리 |

### 사용 가이드

- **쿼리 최적화 / EXPLAIN 분석** → postgres-best-practices의 `query-` 규칙 적용
- **RLS 정책 신규 작성** → supabase 스킬의 RLS 안티패턴 체크리스트 확인
- **Auth 세션/쿠키/JWT 이슈** → supabase 스킬의 최신 auth 패턴 참조
- **Storage 업로드/다운로드 정책** → supabase 스킬의 storage 가이드 참조
- **새 Supabase API 기능** → supabase 스킬이 "훈련 데이터가 금방 낡는다"는 전제로 최신 문서를 재확인하라고 안내

### 본 프로젝트 규칙과의 관계

- 공식 스킬은 **범용 Supabase 베스트 프랙티스**를 제공
- 본 문서(`docs/BACKEND.md`)는 **프로젝트 고유 규칙** 정의:
  - `db_init.sql`이 단일 진실 소스
  - `testament` 필드 규약 (`old` / `new`, `era_nt_` 접두사)
  - 한국어 UI 텍스트
  - `generate_profile_share_id()` 등 프로젝트 전용 함수
  - Riverpod Provider + 생성자 주입 Repository 패턴

충돌 시 **본 문서의 프로젝트 고유 규칙이 우선**한다.

## Story proposal workflow (ADR-016)

### 역할 체계
- `is_admin()` — `auth.jwt().app_metadata.role == 'admin'` (기존). events/persons 쓰기 권한.
- `is_pastor()` — `user_profiles.is_pastor = true`. 이야기 제안 제출 권한. 운영자가 수동으로 토글 (admin@brand-i.net 이메일 수신 후 Supabase 대시보드에서 set true).

두 역할은 **독립적** — pastor 는 admin 아니고, admin 은 자동으로 pastor 가 아니다. 단, 두 역할 모두 댓글 작성이 가능.

### 테이블
#### `event_proposals`
사역자가 제출하는 이야기 초안. 승인 전까지 `events` 와 격리 → 모바일 앱 쿼리(`events.status='published'`)에 섞이지 않음.

| 컬럼 | 타입 | 의미 |
|---|---|---|
| `id` | uuid PK | |
| `proposer_user_id` | uuid | 작성자 (auth.users) |
| `era_id` | uuid | `eras(id)` 참조 |
| `title`, `summary`, `character_codes[]`, `landmark_id` (uuid → landmarks), `start_year`, `end_year`, `time_precision`, `bible_refs`, `story_scenes`, `scene_characters`, `after_story_index` | | `events` 와 동일한 콘텐츠 필드 + 삽입 위치 힌트 |
| `status` | text CHECK | `pending` → `approved` / `rejected` |
| `reviewed_by_user_id`, `reviewed_at`, `review_note` | | admin 승인/거절 메타 |
| `approved_event_id` | uuid | 승인 시 생성된 `events.id` 참조 (이후 추적용) |
| `created_at`, `updated_at` | timestamptz | `touch_updated_at` 트리거 |

#### `event_proposal_comments`
제안별 댓글. pastor + admin 모두 읽기·쓰기 가능 (커뮤니티 형태).

### RLS 요약

| 대상 | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `event_proposals` | pastor + admin | pastor (본인 proposer, `status=pending`) | pastor 본인 `pending` 수정 / admin status 변경 | admin |
| `event_proposal_comments` | pastor + admin | pastor + admin (본인 author) | 본인 author | 본인 author 또는 admin |

모든 "pastor + admin" SELECT 는 게시판 공개 의도 — pastor 는 본인 제안뿐 아니라 동료 사역자의 제안도 열람·댓글 가능.

### RPC
- `submit_event_proposal(p_era_id, p_title, p_summary, p_character_codes, p_landmark_id (uuid), p_start_year, p_end_year, p_time_precision, p_bible_refs, p_story_scenes, p_scene_characters, p_scene_image_paths, p_scene_image_prompts, p_proposed_characters, p_quiz_questions, p_after_story_index) returns uuid` — pastor 만, proposer=auth.uid() 로 강제 INSERT. v2 위치 모델 — landmark_id 필수.
- `approve_event_proposal(p_proposal_id, p_after_story_index_override default null) returns uuid` — admin 만, 내부에서 `eras.code` 조회 후 기존 `insert_event_at_position` 재호출하여 events 에 반영. 반환값은 생성된 event.id. proposal.status='approved', approved_event_id 갱신.
- `reject_event_proposal(p_proposal_id, p_note default null) returns void` — admin 만, pending → rejected + note 저장.
- `add_proposal_comment(p_proposal_id, p_body) returns uuid` — pastor + admin, author=auth.uid() 로 강제 INSERT.

### 운영 주의
- 목회자 인증 토글은 수동: `update user_profiles set is_pastor = true where user_id = '...'` 또는 Supabase 대시보드. ADR-016 참조.
- 승인된 제안의 `events` row 는 `insert_event_at_position` 가 era 내 뒤 인덱스를 +1 시프트하는 기존 로직을 그대로 따름.
- 댓글 삭제는 본인 또는 admin 만. 스팸/부적절 댓글은 admin 이 직접 수동 삭제.
