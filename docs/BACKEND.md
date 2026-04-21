# 백엔드 도메인 레퍼런스

> 이 문서는 `$backend` 스킬이 참조하는 백엔드 도메인 가이드이다.
> Supabase 공식 [agent-skills](https://github.com/supabase/agent-skills)가 설치되어 있으면
> 본 프로젝트의 규칙(아래)과 공식 가이드가 함께 적용된다.

## 1. 파일 범위

```
db_init.sql                            # 스키마 정의 — 단일 진실 소스
supabase/
├── migrations/
│   └── 20260331_user_personal_features.sql
├── 200_stories/                       # 생성된 시드 SQL
│   ├── 200_stories_seed.sql           # events INSERT (배열/JSONB 컬럼 포함)
│   ├── persons_seed.sql               # persons INSERT (is_active 만, mention_count 는 person_meta.json 메타)
│   └── 200_stories_report.json
└── seeds/
    └── krv_bible_verses*.sql          # KRV 성경 구절 시드

lib/data/
├── auth_repository.dart               # 인증
├── story_repository.dart              # events_ordered/person_eras view 쿼리
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
- 구약 6시대 + 신약 4시대 = 총 10시대
- `testament`: 'old' 또는 'new' (era 코드로도 판별: `era_nt_` 접두사)

#### `persons` — 성경 인물 (table)
```sql
id uuid PK, code text UNIQUE, name text, tagline text,
avatar_url text, description text,
is_active boolean DEFAULT false   -- 어드민이 노출 여부 결정
```
- 모든 개인 코드(그룹/플레이스홀더 제외)가 한 행으로 들어옴.
- 빌더는 `person_meta.json`의 `is_active_default` 값(등장 2회 이상이면 true)을
  따라 초기값을 결정한다. 어드민이 토글한 `is_active`는 시드 재실행 시에도
  보존된다 (`on conflict ... do update`에서 `is_active` 제외).
- 단 `description`은 `coalesce(excluded.description, persons.description)`로 UPSERT되고 excluded가 항상 non-null이므로 **시드에 포함된 인물은 매번 새 description으로 덮어써진다**. 로컬 `assets/200_stories/`가 DB와 동기화된 상태여야 description이 엉뚱한 "대표 이야기"로 망가지지 않는다 — 상세 절차는 [CONTENT_UPDATE.md §2.1b \[0\]](CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로).

#### `events` — 성경 사건 (table)
```sql
id uuid PK, era_id uuid FK→eras, title text, summary text,
story_scenes jsonb DEFAULT '[]',     -- ["장면1", ...]
scene_persons jsonb DEFAULT '[]',    -- [["god"], [], ...]
person_codes text[] DEFAULT '{}',    -- 평탄화된 인물 코드
bible_refs jsonb DEFAULT '[]',       -- [{book, from, to}, ...]
start_year int, end_year int,
time_precision text DEFAULT 'approx',
story_index int NOT NULL,            -- era 내 정수 (UNIQUE: era_id+story_index)
place_name text, lat float8, lng float8,
video_url text,
status text DEFAULT 'published'      -- draft / published (어드민 전용)
  CHECK (status in ('draft','published'))
```
- 정렬 기준은 view에서 동적으로 계산 (`time_sort_key`/`code` 컬럼 폐기).
- `story`/`short_story` 컬럼 폐기 — UI는 `summary` + `story_scenes`로 충분.
- `bible_refs`/`person_codes`가 events row에 직접 임베드 → `event_persons`/`event_bible_refs` 테이블 폐기.
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
- 새 이야기가 끼어들면 view가 자동 재계산되므로 사전 정렬값 갱신이 불필요.

#### `person_eras` — 인물-시대 매핑 view
```sql
WITH first AS (
  SELECT p.id person_id, p.code, e.era_id, MIN(e.story_index) first_story_index
  FROM persons p JOIN events e
    ON e.person_codes @> ARRAY[p.code] AND e.status='published'
  WHERE p.is_active = true
  GROUP BY p.id, p.code, e.era_id
)
SELECT person_id, era_id,
  row_number() OVER (PARTITION BY era_id ORDER BY first_story_index, code) AS display_order
FROM first;
```
- 인물 첫 등장 story_index 기준으로 era별 1..N 순서를 동적으로 부여.
- `is_active=false` 인물은 자동 제외.

#### 새 이야기 삽입 패턴 (어드민용 RPC, 향후 작업)
- `(era_id, story_index)` UNIQUE 제약 → 끼워넣기는 `story_index >= 새값`인 행을 +1 시프트한 뒤 INSERT.
- 동시성: era별 advisory lock 또는 deferred constraint 권장.

#### `bible_verses` — KRV 성경 전문 (31,904절)
```sql
id uuid PK, translation text DEFAULT 'KRV',
book_no int, book_name text, chapter_no int,
verse_no int, verse_text text,
UNIQUE(translation, book_no, chapter_no, verse_no)
```

### 2.2 사용자 테이블

#### `user_profiles`
```sql
user_id uuid PK FK→auth.users, share_id text UNIQUE (7자리 자동생성),
nickname text, photo_url text, prayer_request text
```

#### `user_event_progress`
```sql
user_id uuid FK→auth.users, event_id uuid FK→events,
is_completed boolean DEFAULT false, completed_at timestamptz,
UNIQUE(user_id, event_id)
```
- 완료 여부만 기록. 게이미피케이션(score/xp) 계획 없어서 제거됨.

#### `user_notes`
```sql
id uuid PK, user_id uuid FK→auth.users,
title text, content text, created_at, updated_at
```

#### `user_saved_verses`
```sql
id uuid PK, user_id uuid FK→auth.users,
translation text, book_no int, book_name text,
chapter_no int, verse_no int, verse_text text
```

#### `user_intercessory_prayers`
```sql
id uuid PK, subscriber_id uuid FK→auth.users,
target_user_id uuid FK→auth.users
```

#### `user_daily_activity`
```sql
user_id uuid FK→auth.users, activity_date date,
attended boolean DEFAULT false, studied boolean DEFAULT false,
created_at, updated_at,
PRIMARY KEY (user_id, activity_date)
```
- 하루 한 row 로 출석/학습을 함께 기록. PostgREST upsert 는 요청에 포함된
  컬럼만 SET 하므로 `attended`/`studied` 플래그가 서로 덮어쓰이지 않는다.
- Partial index: `(user_id, activity_date desc) where attended|studied = true`
  로 streak 조회 최적화.

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

## 3. RLS 정책

| 테이블 / view | 읽기 | 쓰기 |
|--------|------|------|
| eras, bible_verses, quiz_questions | 공개 (anon) | — |
| persons | 공개, **`is_active = true`만 노출** (admin은 전체) | admin만 |
| events | 공개, **`status = 'published'`만 노출** (admin은 전체) | admin만 |
| events_ordered, person_eras (view) | 공개 | — (view, underlying RLS 따름) |
| user_profiles | 본인만 | 본인만 |
| user_event_progress | 본인만 | 본인만 |
| user_notes | 본인만 | 본인만 |
| user_saved_verses | 본인만 | 본인만 |
| user_intercessory_prayers | 본인 구독 | 본인만 |
| user_daily_activity | 본인만 | 본인만 |

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

## 5. Repository 패턴

### 5.1 StoryRepository (`lib/data/story_repository.dart`)

| 메서드 | 쿼리 | 반환 |
|--------|------|------|
| `fetchEras()` | `eras` ORDER BY display_order | `List<Era>` |
| `fetchPersonsByEra(eraId)` | `person_eras` view JOIN `persons` WHERE era_id ORDER BY display_order | `List<Person>` |
| `fetchEventsByEra(eraId)` | `events_ordered` view WHERE era_id ORDER BY rank_in_era | `List<StoryEvent>` |
| `fetchEventsForPerson(personCode)` | `events_ordered` WHERE person_codes @> ARRAY[code] ORDER BY global_rank | `List<StoryEvent>` |
| `fetchPersonTimelineOrder()` | `events_ordered` → personCode별 첫 등장 global_rank | `Map<String, int>` |
| `searchEventsByText(query)` | 전체 `events_ordered` + persons name lookup → 클라이언트 가중치 검색 | `List<StoryEvent>` (상위 20) |
| `fetchQuizQuestions(eventId)` | `quiz_questions` WHERE event_id | `List<QuizQuestion>` |
| `fetchBibleVersesByChapter(...)` | `bible_verses` WHERE book_no, chapter_no | `List<BibleVerse>` |
| `fetchCompletedEventIds(userId)` | `user_event_progress` WHERE is_completed | `Set<String>` |
| `upsertEventProgress({userId, eventId, isCompleted})` | UPSERT `user_event_progress` ON (user_id, event_id) | void |

검색 가중치 (`scoreEventMatch`): title +130, summary +120, story_scenes +100, person names +80, place +30. 토큰별 매치 추가점.

### 5.2 UserRepository (`lib/data/user_repository.dart`, 485줄)

| 메서드 | 주요 쿼리 | 반환 |
|--------|----------|------|
| `ensureSignedInUser(user)` | user_profiles SELECT/INSERT | `AppUserProfile` |
| `fetchUserProfile(userId)` | user_profiles SELECT | `AppUserProfile` |
| `updateUserProfile(...)` | user_profiles UPDATE | `AppUserProfile` |
| `uploadProfileImage(...)` | Storage uploadBinary | `String` (public URL) |
| `recordAttendance(userId)` | user_daily_activity UPSERT attended=true | void |
| `recordStudyDay(userId)` | user_daily_activity UPSERT studied=true | void |
| `fetchAttendanceStreak(userId)` | user_daily_activity WHERE attended → 연속일 계산 | `int` |
| `fetchStudyStreak(userId)` | user_daily_activity WHERE studied → 연속일 계산 | `int` |
| `fetchUserNotesPage(...)` | user_notes SELECT + 페이지네이션 | `PagedResult<UserNote>` |
| `createUserNote(...)` | user_notes INSERT | `UserNote` |
| `deleteUserNote(noteId)` | user_notes DELETE | void |
| `fetchSavedVersesPage(...)` | user_saved_verses SELECT + 페이지네이션 | `PagedResult<SavedBibleVerse>` |
| `toggleSavedVerse(...)` | user_saved_verses INSERT/DELETE | `bool` |
| `fetchIntercessoryPrayerPage(...)` | RPC list_intercessory_prayer_requests | `PagedResult<IntercessoryPrayerItem>` |
| `addIntercessoryPrayerByShareId(shareId)` | RPC add_intercessory_prayer_by_share_id | `IntercessoryPrayerItem` |
| `fetchPersonStudyProgress(...)` | user_event_progress + events_ordered.person_codes (배열 매치) | `List<PersonStudyProgress>` |

### 5.3 AuthRepository (`lib/data/auth_repository.dart`, 77줄)

| 메서드 | 역할 |
|--------|------|
| `signInWithApple()` | Apple ID 로그인 (SHA256 nonce) |
| `signInWithGoogle()` | Google 로그인 |
| `signInWithKakao()` | Kakao 로그인 |
| `signOut()` | 로그아웃 |

## 6. Storage

- **버킷**: `profile-images`
- **제한**: 5MB, PNG/JPEG/WebP
- **경로 패턴**: `{userId}/profile_{timestamp}.{ext}`
- **접근**: 본인만 업로드, public URL로 읽기

## 7. 마이그레이션 관리 규칙

1. `db_init.sql`이 스키마의 **단일 진실 소스** (Single Source of Truth)
2. 스키마 변경 시: `db_init.sql` 수정 → `supabase/migrations/` 마이그레이션 생성
3. 로컬 초기화: `db_init.sql` 전체 실행 (DROP + CREATE)
4. 운영 반영: 마이그레이션 파일 또는 SQL Editor

## 8. Supabase 공식 Agent Skills

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
