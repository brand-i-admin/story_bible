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
│   ├── characters_seed.sql               # persons INSERT (is_active 만, mention_count 는 character_meta.json 메타)
│   └── 200_stories_report.json
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
- 구약 6시대 + 신약 4시대 = 총 10시대
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
- 단 `description`은 `coalesce(excluded.description, persons.description)`로 UPSERT되고 excluded가 항상 non-null이므로 **시드에 포함된 인물은 매번 새 description으로 덮어써진다**. 로컬 `assets/200_stories/`가 DB와 동기화된 상태여야 description이 엉뚱한 "대표 이야기"로 망가지지 않는다 — 상세 절차는 [CONTENT_UPDATE.md §2.1b \[0\]](CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로).

#### `events` — 성경 사건 (table)
```sql
id uuid PK, era_id uuid FK→eras, title text, summary text,
story_scenes jsonb DEFAULT '[]',     -- ["장면1", ...]
scene_characters jsonb DEFAULT '[]',    -- [["god"], [], ...]
character_codes text[] DEFAULT '{}',    -- 평탄화된 인물 코드
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
- 새 이야기가 끼어들면 view가 자동 재계산되므로 사전 정렬값 갱신이 불필요.

#### `character_eras` — 인물-시대 매핑 view
```sql
WITH first AS (
  SELECT p.id person_id, p.code, e.era_id, MIN(e.story_index) first_story_index
  FROM persons p JOIN events e
    ON e.character_codes @> ARRAY[p.code] AND e.status='published'
  WHERE p.is_active = true
  GROUP BY p.id, p.code, e.era_id
)
SELECT person_id, era_id,
  row_number() OVER (PARTITION BY era_id ORDER BY first_story_index, code) AS display_order
FROM first;
```
- 인물 첫 등장 story_index 기준으로 era별 1..N 순서를 동적으로 부여.
- `is_active=false` 인물은 자동 제외.

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
id uuid PK, proposer_user_id uuid FK→auth.users, era_id uuid FK→eras,
title text, summary text, character_codes text[], place_name text, lat/lng,
start_year/end_year/time_precision, bible_refs jsonb,
story_scenes jsonb, scene_characters jsonb, after_story_index int,
status text CHECK ('pending'/'approved'/'rejected'),
reviewed_by_user_id, reviewed_at, review_note, approved_event_id uuid FK→events,
created_at, updated_at
```
- 승인 전까지 `events` 와 격리되므로 모바일 앱 쿼리(`events_ordered` view, `events.status='published'`)에 영향 0.
- `approve_event_proposal` RPC 가 `insert_event_at_position` 을 호출해 events 에 반영 + `approved_event_id` 역참조 기록.

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

#### RPC 4종
| 이름 | 호출자 | 역할 |
|------|------|------|
| `submit_event_proposal(...)` | pastor | 제안 INSERT (status='pending' 강제) |
| `approve_event_proposal(proposal_id, after_override)` | admin | 내부에서 `insert_event_at_position` 호출 → events 반영 + proposal status='approved' |
| `reject_event_proposal(proposal_id, note)` | admin | status='rejected' + review_note 저장 |
| `add_proposal_comment(proposal_id, body)` | pastor/admin | 댓글 INSERT 편의 함수 |

상세 SQL: [db_init.sql](../db_init.sql) §Story proposal workflow, 마이그레이션: [supabase/migrations/20260421_event_proposals.sql](../supabase/migrations/20260421_event_proposals.sql).

#### `bible_verses` — KRV 성경 전문 (31,904절)
```sql
id uuid PK, translation text DEFAULT 'KRV',
book_no int, book_name text, chapter_no int,
verse_no int, verse_text text,
UNIQUE(translation, book_no, chapter_no, verse_no)
```

### 2.2c Notifications & Push (2026-04-22 도입)

인앱 알림함(bell 아이콘)과 FCM 푸시를 지원한다. 하이브리드 팬아웃:

#### `notifications` — 개인 알림 (Fan-out on Write)
```sql
id uuid PK, user_id uuid FK→auth.users,
type text CHECK IN (
  'proposal_comment','proposal_comment_admin','new_proposal_admin',
  'proposal_approved','proposal_rejected','quiz_completed'
),
title text, body text, deep_link text, payload jsonb,
read_at timestamptz, created_at timestamptz
```
- `deep_link`: `/proposal/<id>` | `/event/<id>` | `/weekly` 중 하나.
- 인덱스: `(user_id, created_at desc)` + unread 필터 부분 인덱스.

#### `broadcast_notifications` — 공지 (Fan-out on Read)
```sql
id uuid PK, type text CHECK IN ('new_event','weekly_character','weekly_progress_check'),
target_audience text CHECK IN ('all','pastor_or_admin'),
title text, body text, deep_link text, payload jsonb, created_at timestamptz
```

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
- pg_cron 이 월요일 00:00 UTC 에 `pick_weekly_character()` 실행 → 이 테이블에 row + broadcast.
- Dart 쪽 `weekly_selection.dart` 의 `seedFromKey` 를 plpgsql `_seed_from_week_key` 로 포팅해 동일 결과 보장.

#### 트리거
- `trg_notify_on_new_proposal` (event_proposals AFTER INSERT) → admin 전원에게 개인 알림
- `trg_notify_on_proposal_comment` (event_proposal_comments AFTER INSERT) → proposer + admin
- `trg_notify_on_proposal_reviewed` (event_proposals AFTER UPDATE) → proposer 에게 승인/거절 알림
- `trg_notify_on_new_event` (events AFTER INSERT) → 전체 대상 브로드캐스트

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
| `pick_weekly_character()` | pg_cron 월요일 |
| `notify_weekly_progress()` | pg_cron 수/금 |

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
| events_ordered, character_eras (view) | 공개 | — (view, underlying RLS 따름) |
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
| `fetchCharactersByEra(eraId)` | `character_eras` view JOIN `persons` WHERE era_id ORDER BY display_order | `List<Character>` |
| `fetchEventsByEra(eraId)` | `events_ordered` view WHERE era_id ORDER BY rank_in_era | `List<StoryEvent>` |
| `fetchEventsForCharacter(personCode)` | `events_ordered` WHERE character_codes @> ARRAY[code] ORDER BY global_rank | `List<StoryEvent>` |
| `fetchCharacterTimelineOrder()` | `events_ordered` → personCode별 첫 등장 global_rank | `Map<String, int>` |
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
| `signInWithGoogle()` | Google 로그인 |
| `signInWithKakao()` | Kakao 로그인 |
| `signOut()` | 로그아웃 |

## 6. Storage

세 버킷이 `db_init.sql` 에 선언된다.

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

### `proposal-scenes` (신규, 2026-04)
- 제안 작성 폼에서 생성된 장면 AI 이미지.
- **제한**: 10 MB, PNG/JPEG/WebP
- **경로 패턴**: `{user_id}/{draft_id}/scene_{idx}.png`
- **쓰기 권한**: authenticated 본인 폴더. 실제 업로드 주체는 Edge Function
  (`generate-proposal-scene`) 으로, service role key 사용.
- **읽기 권한**: public — 제안 상세 페이지에서 다른 pastor/admin 이 열람.
- **DB 연동**: `event_proposals.scene_image_paths` 가 이 경로 목록을 유지
  (인덱스 순서 = 장면 순서).

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

### `send-push` (2026-04-22)
- 경로: `supabase/functions/send-push/index.ts`
- 호출 시점: `notifications` / `broadcast_notifications` INSERT 이후 pg_net 디스패치 (선택적)
- 배포: `supabase functions deploy send-push`
- 배포 전제 secrets:
  - `FIREBASE_SERVICE_ACCOUNT` — Firebase 서비스 계정 JSON 전체
- 기능 개요:
  1. 입력 body 의 `user_id`(개인) 또는 `broadcast: true`(공지) 로 대상 판정
  2. `user_push_tokens` 에서 FCM 토큰 조회
  3. OAuth 2.0 토큰 발급 (GCP scope: `firebase.messaging`)
  4. FCM HTTP v1 API `POST /v1/projects/{id}/messages:send` 로 각 디바이스에 전송
  5. 404/UNREGISTERED 응답은 해당 토큰을 자동 정리
- 상세: `supabase/functions/send-push/README.md` + `docs/PUSH_SETUP.md`

### 로컬 개발

```bash
supabase start                                 # 로컬 스택
supabase functions serve \
  --env-file .env.supabase.secrets \
  generate-proposal-scene
```

브라우저/Flutter 에서 호출 시 base URL 을 로컬 것으로 바꿔 테스트.

## 8. 마이그레이션 관리 규칙

1. `db_init.sql`이 스키마의 **단일 진실 소스** (Single Source of Truth)
2. 스키마 변경 시: `db_init.sql` 수정 → `supabase/migrations/` 마이그레이션 생성
3. 로컬 초기화: `db_init.sql` 전체 실행 (DROP + CREATE)
4. 운영 반영: 마이그레이션 파일 또는 SQL Editor

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
| `title`, `summary`, `character_codes[]`, `place_name`, `lat`, `lng`, `start_year`, `end_year`, `time_precision`, `bible_refs`, `story_scenes`, `scene_characters`, `after_story_index` | | `events` 와 동일한 콘텐츠 필드 + 삽입 위치 힌트 |
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
- `submit_event_proposal(p_era_id, p_title, p_summary, p_character_codes, p_place_name, p_lat, p_lng, p_start_year, p_end_year, p_time_precision, p_bible_refs, p_story_scenes, p_scene_characters, p_after_story_index) returns uuid` — pastor 만, proposer=auth.uid() 로 강제 INSERT.
- `approve_event_proposal(p_proposal_id, p_after_story_index_override default null) returns uuid` — admin 만, 내부에서 `eras.code` 조회 후 기존 `insert_event_at_position` 재호출하여 events 에 반영. 반환값은 생성된 event.id. proposal.status='approved', approved_event_id 갱신.
- `reject_event_proposal(p_proposal_id, p_note default null) returns void` — admin 만, pending → rejected + note 저장.
- `add_proposal_comment(p_proposal_id, p_body) returns uuid` — pastor + admin, author=auth.uid() 로 강제 INSERT.

### 운영 주의
- 목회자 인증 토글은 수동: `update user_profiles set is_pastor = true where user_id = '...'` 또는 Supabase 대시보드. ADR-016 참조.
- 승인된 제안의 `events` row 는 `insert_event_at_position` 가 era 내 뒤 인덱스를 +1 시프트하는 기존 로직을 그대로 따름.
- 댓글 삭제는 본인 또는 admin 만. 스팸/부적절 댓글은 admin 이 직접 수동 삭제.
