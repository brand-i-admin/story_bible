# 백엔드 도메인 레퍼런스

> 이 문서는 `$backend` 스킬이 참조하는 백엔드 도메인 가이드이다.
> Supabase 공식 [agent-skills](https://github.com/supabase/agent-skills)가 설치되어 있으면
> 본 프로젝트의 규칙(아래)과 공식 가이드가 함께 적용된다.

## 1. 파일 범위

```
db_init.sql                            # 스키마 정의 (673줄) — 단일 진실 소스
supabase/
├── migrations/
│   └── 20260331_user_personal_features.sql
├── 200_stories/                       # 생성된 시드 SQL
│   ├── 200_stories_seed.sql
│   ├── persons_seed.sql
│   └── 200_stories_report.json
└── seeds/
    └── krv_bible_verses*.sql          # KRV 성경 구절 시드

lib/data/
├── auth_repository.dart               # 인증 (77줄)
├── story_repository.dart              # 이야기/이벤트 쿼리 (382줄)
└── user_repository.dart               # 사용자 데이터 (485줄)
```

## 2. DB 스키마

### 2.1 핵심 이야기 테이블

#### `eras` — 성경 시대
```sql
id uuid PK, code text UNIQUE, name text, testament text,
display_order int, start_year int, end_year int,
theme_color text, map_center_lat float8, map_center_lng float8, map_zoom numeric(4,2)
```
- 구약 6시대 + 신약 4시대 = 총 10시대
- `testament`: 'old' 또는 'new' (era 코드로도 판별: `era_nt_` 접두사)

#### `persons` — 성경 인물
```sql
id uuid PK, code text UNIQUE, name text, tagline text,
avatar_url text, description text, is_active boolean DEFAULT true
```
- `avatar_url`: `assets/avatars/{code}.png` 형태
- 2회 이상 등장하는 개인만 포함 (집합/비개인 코드 제외)

#### `person_eras` — 인물-시대 매핑
```sql
id uuid PK, person_id uuid FK→persons, era_id uuid FK→eras,
display_order int DEFAULT 0, UNIQUE(person_id, era_id)
```

#### `events` — 성경 사건 (215개)
```sql
id uuid PK, code text UNIQUE, era_id uuid FK→eras,
title text, summary text, story text, short_story text,
story_scenes text, -- 4장면 JSON 텍스트
start_year int, end_year int, time_sort_key bigint,
time_precision text DEFAULT 'approx',
place_name text, lat float8, lng float8,
video_url text, thumb_url text
```
- `time_sort_key`: 정렬 기준 (연도 × 1000 + 보정값)
- `story_scenes`: 4장면 설명 (이미지 생성 프롬프트로도 사용)

#### `event_persons` — 사건-인물 매핑
```sql
id uuid PK, event_id uuid FK→events, person_id uuid FK→persons,
role text, person_sequence int, UNIQUE(event_id, person_id)
```

#### `event_bible_refs` — 사건 성경 참조
```sql
id uuid PK, event_id uuid FK→events,
book text, chapter_start int, verse_start int,
chapter_end int, verse_end int, display_text text
```

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
is_completed boolean DEFAULT false, score int DEFAULT 0,
xp_earned int DEFAULT 0, completed_at timestamptz,
UNIQUE(user_id, event_id)
```

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

#### `user_daily_attendance` / `user_daily_study`
```sql
user_id uuid FK→auth.users, attended_on/studied_on date,
UNIQUE(user_id, attended_on/studied_on)
```

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

| 테이블 | 읽기 | 쓰기 |
|--------|------|------|
| eras, persons, person_eras, events, event_persons, event_bible_refs, bible_verses | 공개 (anon) | — |
| quiz_questions | 공개 | — |
| user_profiles | 본인만 | 본인만 |
| user_event_progress | 본인만 | 본인만 |
| user_notes | 본인만 | 본인만 |
| user_saved_verses | 본인만 | 본인만 |
| user_intercessory_prayers | 본인 구독 | 본인만 |
| user_daily_attendance/study | 본인만 | 본인만 |

## 4. PostgreSQL 함수 / 트리거

| 이름 | 종류 | 역할 |
|------|------|------|
| `generate_profile_share_id()` | 함수 | 유니크 7자리 영숫자 코드 생성 |
| `handle_new_user_profile()` | 트리거 함수 | auth.users INSERT → user_profiles 자동 생성 |
| `on_auth_user_created` | 트리거 | auth.users AFTER INSERT → handle_new_user_profile() |
| `touch_updated_at()` | 트리거 함수 | updated_at 자동 갱신 |
| `list_intercessory_prayer_requests(p_limit, p_offset)` | RPC 함수 | 중보기도 목록 페이지네이션 |
| `add_intercessory_prayer_by_share_id(p_share_id)` | RPC 함수 | 공유 코드로 중보기도 추가 |

## 5. Repository 패턴

### 5.1 StoryRepository (`lib/data/story_repository.dart`, 382줄)

| 메서드 | 쿼리 | 반환 |
|--------|------|------|
| `fetchEras()` | `eras` ORDER BY display_order | `List<Era>` |
| `fetchPersonsByEra(eraId)` | `person_eras` JOIN `persons` WHERE era_id | `List<Person>` |
| `fetchEventsByEra(eraId)` | `events` + event_persons + event_bible_refs WHERE era_id | `List<StoryEvent>` |
| `fetchEventsForPerson(personId)` | `events` + event_persons!inner WHERE person_id | `List<StoryEvent>` |
| `fetchPersonTimelineOrder()` | 전체 events → person별 첫 등장 time_sort_key | `Map<String, int>` |
| `searchEventsByText(query)` | 전체 events → 클라이언트 사이드 가중치 검색 | `List<StoryEvent>` (상위 20) |
| `fetchQuizQuestions(eventId)` | `quiz_questions` WHERE event_id | `List<QuizQuestion>` |
| `fetchBibleVersesByChapter(...)` | `bible_verses` WHERE book_no, chapter_no | `List<BibleVerse>` |
| `fetchCompletedEventIds(userId)` | `user_event_progress` WHERE is_completed | `Set<String>` |
| `upsertEventProgress(...)` | UPSERT `user_event_progress` ON (user_id, event_id) | void |

### 5.2 UserRepository (`lib/data/user_repository.dart`, 485줄)

| 메서드 | 주요 쿼리 | 반환 |
|--------|----------|------|
| `ensureSignedInUser(user)` | user_profiles SELECT/INSERT | `AppUserProfile` |
| `fetchUserProfile(userId)` | user_profiles SELECT | `AppUserProfile` |
| `updateUserProfile(...)` | user_profiles UPDATE | `AppUserProfile` |
| `uploadProfileImage(...)` | Storage uploadBinary | `String` (public URL) |
| `recordAttendance(userId)` | user_daily_attendance INSERT | void |
| `recordStudyDay(userId)` | user_daily_study INSERT | void |
| `fetchAttendanceStreak(userId)` | user_daily_attendance SELECT → 연속일 계산 | `int` |
| `fetchUserNotesPage(...)` | user_notes SELECT + 페이지네이션 | `PagedResult<UserNote>` |
| `createUserNote(...)` | user_notes INSERT | `UserNote` |
| `deleteUserNote(noteId)` | user_notes DELETE | void |
| `fetchSavedVersesPage(...)` | user_saved_verses SELECT + 페이지네이션 | `PagedResult<SavedBibleVerse>` |
| `toggleSavedVerse(...)` | user_saved_verses INSERT/DELETE | `bool` |
| `fetchIntercessoryPrayerPage(...)` | RPC list_intercessory_prayer_requests | `PagedResult<IntercessoryPrayerItem>` |
| `addIntercessoryPrayerByShareId(shareId)` | RPC add_intercessory_prayer_by_share_id | `IntercessoryPrayerItem` |
| `fetchPersonStudyProgress(...)` | user_event_progress + events + event_persons | `List<PersonStudyProgress>` |

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
# Claude Code 플러그인 (권장)
claude plugin install supabase@supabase-agent-skills

# 또는 npx로 특정 스킬만
npx skills add supabase/agent-skills --skill supabase
npx skills add supabase/agent-skills --skill supabase-postgres-best-practices
```

### 제공되는 공식 스킬

| 스킬 | 커버 영역 |
|------|----------|
| `supabase` | Database / Auth / Edge Functions / Realtime / Storage / Vectors / Cron / Queues, supabase-js/ssr, Next.js/React/SvelteKit 통합, JWT/RLS 트러블슈팅 |
| `supabase-postgres-best-practices` | Query Performance, Connection Management, Security & RLS, Schema Design, Concurrency & Locking, Data Access Patterns, Monitoring, Advanced Features — 8개 카테고리 |

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
