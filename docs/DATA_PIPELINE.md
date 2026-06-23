# 데이터 파이프라인 도메인 레퍼런스

> 이 문서는 `.agents/skills/data-pipeline` 스킬이 참조하는 데이터 파이프라인 가이드이다.

## 0. 입력 데이터 (사람·AI 이전 단계에서 준비됨)

- **`assets/bible/*.txt`** — KRV 개역한글 66권 텍스트 (31,904절). 외부 공개 본문을 정리해 둔 gitignore 로컬 입력.
- **`assets/200_stories/*.json`** — 시대별 이야기 dict 리스트. **사람이 의도하고 AI(LLM)로 초안을 뽑아 정리한 결과물**이다. 파이프라인은 이 정리된 JSON을 초기/배포 canonical 입력으로 사용한다. 신규 이야기는 `assets/story_drafts/*.json`에서 초안을 만들고 proposal 승인 후 release sync 단계에서 이 canonical JSON으로 편입한다.

### 가장 단순한 흐름: KRV 성경 시드

```
assets/bible/{창세기,출애굽기, ... ,요한계시록}.txt   (66 파일, 31,904절)
    │
    ▼  make seed-bible-verses
        (build_krv_seed_sql.py --input-dir assets/bible --split-parts 10)
    │
    ▼
supabase/seeds/
  ├── krv_bible_verses.sql          (전체 통합본, 한 파일)
  └── krv_bible_verses_part_01.sql  ~  _10.sql   (분할본; SQL Editor 크기 제한 우회용)

    │
    ▼  make apply-bible-verses-seeds
        (psql 로 part_*.sql 차례 적용)
    │
    ▼
DB의 bible_verses 테이블
```

이야기/인물/이미지 흐름은 §2 DAG 참조.

## 1. 파일 범위

```
tools/                                  # Python 스크립트 (서브디렉토리로 분리)
├── seed/                               # 1단계: SQL 시드 빌더 + character_meta.json
├── images/                             # Vertex AI 호출 + 썸네일 + scene 공용 utils
├── app/                                # pubspec/asset 검증
├── lint/                               # 금지패턴 + 코드 메트릭
├── export/                             # DB → JSON 검수용
└── docs/                               # story_guide.md + HTML 가이드 생성
assets/                                 # 입력/출력 에셋
├── 200_stories/*.json                  # 이야기 소스
└── quizzes/*.json                      # 이야기별 퀴즈 원본
Makefile                                # 파이프라인 오케스트레이션
.venv/                                  # Python 가상환경
```

## 2. 파이프라인 DAG (의존 관계)

```
                    ┌─────────────────────────────────────────────┐
                    │         assets/200_stories/*.json           │
                    │         (현재 310개 이야기 소스)             │
                    └──┬──────────────────────────┬───────────────┘
                       │                          │
                       ▼                          ▼
        build_character_meta_json.py       generate_event_story_images_vertex.py
               │                                  │
               ▼                                  ▼
      character_meta.json                     assets/story_images/ (생성 완료 시 778장면)
         │        │       │                       │
         ▼        ▼       ▼                       │
  generate_   build_    build_200_                │
  avatars_    characters_  stories_                  │
  vertex.py   seed_     seed_sql.py               │
    │         sql.py      │                       │
    ▼           │         ▼                       │
  assets/       │   200_stories_                  │
  avatars/      │   seed.sql                      │
    │           ▼                                 │
    │     characters_seed.sql                        │
    │                                             │
    └─────────────────────┬───────────────────────┘
                          │
                          ▼
                generate_runtime_thumbnails.py
                          │
                          ▼
                assets/avatars_thumbs/
                assets/story_images_thumbs/
```

## 3. 스크립트 상세

### 3.1 SQL 생성 스크립트 (DB 시딩)

#### `build_krv_seed_sql.py` — 성경 구절 SQL (독립)
- **입력**: `assets/bible/*.txt` (66권 텍스트) 또는 CSV/TSV/JSONL
- **출력**: `supabase/seeds/krv_bible_verses.sql` (또는 분할 파일)
- **본문 줄바꿈 처리**: TXT 원문은 고정 폭 표시용 줄바꿈이 단어 중간에도 들어올 수 있다.
  빌더는 이어진 줄을 붙일 때 원문 줄 끝에 실제 공백이 있으면 한 칸만 보존하고,
  공백 없이 끊긴 줄은 바로 이어 붙여 `보\n이시며` → `보이시며`처럼 복원한다.
- **옵션**:
  - `--input-dir assets/bible` — 입력 디렉토리
  - `--output supabase/seeds/krv_bible_verses.sql`
  - `--truncate-translation` — 기존 KRV 데이터 삭제 후 재삽입
  - `--split-parts 10` — 파일 분할 (SQL Editor 크기 제한 대응)
- **결과**: 31,904절 INSERT

#### `build_character_meta_json.py` — 인물 메타 JSON 생성 (카탈로그 + 아바타 프롬프트)
- **입력**: `assets/200_stories/*.json` (⚠️ **로컬에 있는 파일만** 스캔 — 부분 스캔 주의)
- **출력**: `tools/seed/character_meta.json`
- **역할**: 한 파일이 **characters 테이블 모집단**(code/name/is_active_default), **events FK 화이트리스트**(code 목록), **아바타 이미지 생성 프롬프트**(prompt/negative_prompt_extra)를 모두 담는 단일 진실 소스
- **옵션**:
  - `--min-mentions 1` (기본) — 모든 개인 인물 포함. 노출 여부는 DB의 `characters.is_active`로 제어
  - `--active-threshold 2` (기본) — 이 횟수 이상이면 `is_active_default=true` 표시 → seed에서 활성으로 INSERT. 단, `era_judges` 사건에 실제 등장한 인물은 사사시대 특성상 1회 등장이어도 활성으로 표시한다.
- **규칙**:
  - `disciples`, `apostles`, `brothers` → 개별 인물로 확장
  - top-level `characters`뿐 아니라 `scene_characters`에만 등장하는 개인 인물도 카탈로그와 한글 표시명 fallback에 포함
  - `NON_INDIVIDUAL_CODES`(`crowd`, `angels` 등) 제외
  - 아직 story JSON 에 등장하지 않았지만 아바타를 먼저 준비해야 하는 인물은
    빌더의 `CURATED_AVATAR_ROSTER`에 보관한다. 현재 사사시대 예비 아바타
    roster에는 `othniel`, `ehud`, `shamgar`, `deborah`, `tola`, `jair`,
    `jephthah`, `ibzan`, `elon`, `abdon`, `samson`이 들어 있다. 분열왕국
    왕들은 `DIVIDED_KINGDOM_KING_ROSTER`에서 북이스라엘/남유다 동명이인을
    코드로 분리해 관리하고, 향후 사건 추가 전에 앱에서 보일 수 있도록
    `is_active_default=true`로 생성한다. 그 외 story 미등장 일반 curated
    인물은 `mention_count=0`, `is_active_default=false`로 생성된다.
  - `era_judges` 이야기에서 한 번이라도 실제 등장한 인물은 앱에서 바로 보이도록 `is_active_default=true`로 생성된다.
  - 개별 노출 예외도 있다. 예: `jonathan`은 1회 등장이어도 활성, `god`은 사건 장면 참조에는 쓰지만 인물 카드에는 노출하지 않도록 비활성.
  - 결과: 100+ 인물 코드 + 프롬프트 + `is_active_default` 힌트
- **UI 전용 아바타**: 설명 팝업 안내자처럼 DB 인물이 아닌 에셋은
  `asset_only=true`로 `characters` 목록에 함께 출력한다. 현재 `guide`가 이에
  해당하며 `make generate-avatars`에서 `assets/avatars/guide.png`로 생성되지만,
  `build_characters_seed_sql.py`와 events whitelist에서는 제외된다.
- ⚠️ **부분 스캔 주의**: 이 빌더는 로컬 디렉토리에 있는 JSON만 스캔한다. 로컬이 DB와 동기화되지 않은 상태(예: 새 이야기 파일 1개만 있는 상태)에서 생성된 meta로 `build_characters_seed_sql`을 돌리면 그 안에 포함된 **기존 DB 인물의 description이 부분 정보로 덮어써질 수 있다** (UPSERT는 `coalesce(excluded.description, persons.description)` — excluded가 항상 non-null이라 덮어씀). 안전 절차: [guides/CONTENT_UPDATE.md §2.1b \[0\]](guides/CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로) 참조.

#### `build_200_stories_seed_sql.py` — events SQL
- **의존**: `tools/seed/character_meta.json` (인물 화이트리스트). 입력 JSON 각 항목에 `story_index` 키가 있어야 함 (없으면 `ValueError` 즉시 raise).
- **입력**: `assets/200_stories/*.json` + `tools/seed/character_meta.json`
- **스키마 원본**: 현재처럼 실사용자 없는 초기화 단계에서는 `db_init.sql`이 기준이다.
  아래 schema patch SQL은 나중에 기존 운영 DB를 보존하며 증분 적용해야 할 때만 쓴다.
- **출력**:
  - `supabase/200_stories/200_stories_seed.sql` — `events` 한 테이블 INSERT (배열 + JSONB 컬럼 포함)
  - `supabase/200_stories/200_stories_seed_part_*.sql` — SQL Editor 분할 파일
  - `supabase/200_stories/events_scene_captions_schema_patch.sql` — 기존 DB에 `scene_captions` 컬럼과 `events_ordered` view 확장을 비파괴로 적용하는 패치
  - `supabase/200_stories/events_background_context_schema_patch.sql` — 기존 DB에 `background_context` 컬럼과 `events_ordered` view 확장을 비파괴로 적용하는 패치
  - `supabase/200_stories/200_stories_report.json` — 리포트
  - `supabase/200_stories/200_stories_normalized.json` — 검수용 정규화 JSON
- **출력 컬럼**: `era_id`(eras 조인), `title`, `summary`, `background_context`, `story_scenes`(jsonb), `scene_captions`(jsonb, 장면별 사용자용 이미지 설명), `scene_characters`(jsonb), `character_codes`(text[]), `bible_refs`(jsonb), `start_year`/`end_year`/`time_precision`, `story_index`, `unit_code`/`unit_title`/`unit_order`(시간 순 보기 구간), `landmark_id`(landmarks 조인), `status='published'`
- **요약/배경 지식**: `summary`는 `bible_ref` 본문을 읽고 작성한 curated 문구를 원본으로 보존한다. `tools/seed/generate_story_background_contexts.py`는 summary를 `scene_captions`로 재작성하지 않고 길이/문장 수만 정규화하며, `background_context`는 시대 배경과 해당 사건이 무엇을 다루는지만 1~2문장으로 생성한다. 서신서는 발신자, 수신자, 상황, 작성 의도를 구체적으로 담는다. 결과는 JSON에 직접 남겨 사람이 검수한다.
- **장면 캡션**: `scene_captions`는 `assets/200_stories/*.json`에서 직접 수정 가능하다. `tools/seed/generate_scene_captions.py`는 기존 `story_scenes`/`summary`/`bible_ref` 맥락에서 프롬프트 지시문을 제거한 초안을 다시 만들 때만 사용한다.
- **시간 순 구간**: `unit_code`/`unit_title`/`unit_order`는 `assets/200_stories/*.json`이 원본이다. 구약 시대는 원역사 2개, 족장 3개, 출애굽 3개, 사사 3개, 왕정 3개, 분열왕국 5개, 포로/귀환 3개 구간으로 나눠 `TimelineUnitPickPanel`의 가로 카드 선택에 사용한다.
- **on conflict 키**: `(era_id, story_index)` — 시드 재실행 시 같은 자리의 이벤트를 갱신
- **stale 정리**: 시드 SQL 머리에 `delete from events where (era_id, story_index) not in keep_pairs` 절이 들어간다 → JSON 에서 삭제된 이벤트는 DB 에서도 사라진다. quiz_questions 등 의존 테이블은 cascade.
- **split 파일 주의**: `200_stories_seed_part_01.sql` 만 stale-delete 를 포함, part_02 는 INSERT 만.
- ⚠️ **real 중간 삽입 주의**: 이미 공개된 era 중간에 이야기를 끼워 넣고 뒤쪽 `story_index`를 재번호 매긴 SQL을 seed-only로 real에 적용하면 기존 `(era_id, story_index)` row가 다른 이야기 내용으로 업데이트될 수 있다. `saved_events`, `user_event_progress`, `quiz_questions` 등은 `event_id`를 참조하므로, 운영 DB에서는 먼저 `insert_event_at_position(...)` 또는 별도 patch로 기존 row id를 보존한 채 index shift+insert를 수행한 뒤 seed와 로컬 JSON을 맞춘다.
- **참고**: `code`/`story`/`short_story`/`time_sort_key`/`event_characters`/`event_bible_refs` 산출 로직은 폐기됨 (스키마 v3 변경)

#### `build_characters_seed_sql.py` — characters SQL
- **의존**: `tools/seed/character_meta.json` (선행 필수)
- **입력**: `tools/seed/character_meta.json` + `assets/200_stories/*.json` (대표 스토리 선택용)
- **출력**: `supabase/200_stories/characters_seed.sql` — `characters` UPSERT. `tagline`은 인물 선택 카드에 쓰는 짧은 정체성 문구로, 왕은 나라/순서/대표 행적을, 사사와 선지자는 함께 활동한 인물이나 대표 사역을 최대한 담는다(예: `북이스라엘 7대 왕 바알 숭배`, `바락과 승리한 여사사`, `히스기야를 도운 예루살렘 선지자`). `is_active_default=true`인 행은 seed 적용 시 기존 DB 행도 `is_active=true`로 승격하고, 일반 `false` 기본값은 기존 런타임 설정을 끄지 않는다. 단, `god`, `gabriel`, `elizabeth`처럼 명시 비활성 예외인 코드는 seed 적용 시 `false`로 강제한다.
- **era_codes**: `assets/200_stories` 의 실제 등장 사건을 기준으로 계산한다. 인물이 여러 시대에 등장하면 여러 `era_code` 를 가진다. 등장 사건이 없는 메타 항목만 아바타 스타일용 era 를 fallback 으로 사용한다.
- **stale 정리**: meta 에 없는 `characters` 행을 삭제. `weekly_character_selection` 의 FK 위반을 막기 위해 그 테이블도 동시 청소.
- **참고**: `person_eras`는 view라 INSERT 대상 아님 (db_init.sql 정의)

#### `build_quizzes_seed_sql.py` — quiz_questions SQL
- **입력**: `assets/quizzes/*.json` + `assets/200_stories/*.json`(`bible_ref` 범위 검증용) + `supabase/quizzes/db_events.json` (dev DB 이벤트 스냅샷)
- **출력**:
  - `supabase/quizzes/quizzes_seed.sql` — 이벤트별 `quiz_questions` delete 후 1~3문항 insert
  - `supabase/quizzes/quizzes_report.json` — orphan/title mismatch/길이 경고 리포트
- **문항 슬롯**: `fact`, `attitude`, `story_context` 순서. 세 문항 모두 `bible_ref` 본문에서 이야기 이해에 중요한 사건·행동·말·반응·상태를 묻는다. `scene_captions`는 중요한 장면을 찾는 참고 자료로만 쓰고, 실제 질문과 해설은 성경 본문을 읽어 작성한다. `story_context`는 성경 책/장/절/구절 위치 암기, 제목 맞추기, "핵심 내용/요약" 고르기, 본문 표현 찾기, 빈칸 채우기가 아니라, 1번/2번처럼 특정 구절에서 확인되는 실제 사건·행동·반응·상태를 묻는 짧은 사실 이해 문제로 JSON에 직접 작성한다. 이야기 퀴즈 화면은 이미 상단에 제목을 보여 주므로 `「이야기 제목」에서 ...`, `'이야기 제목'에서 ...` 같은 제목 prefix 질문은 금지한다.
- **보기 구성**: JSON 원본은 선택지 3개와 `answer_index` 0~2만 가진다. SQL 생성 시 `choice_d='헷갈렸어요'`를 자동 추가해 앱에서는 항상 4번 보기로 노출한다. 보기는 본문 표현을 그대로 찾게 하지 말고, 사용자가 사실을 이해했는지 고를 수 있는 일상적인 한국어 문장으로 쓴다.
- **검증**: 모든 질문에 `본문에서 먼저 두드러지는 장면`, `이어지는 장면에서 중심 인물`, `이 사건의 끝부분에서 이어진 일` 같은 storyboard placeholder 문구가 들어오면 실패한다. `story_context` 질문에 "성경 책", "몇 장", "어느 장", "어느 구절" 등 출처 위치를 묻는 패턴, 이야기 제목/전체 요약을 묻는 패턴, "핵심 내용/요약" 선택형 패턴, "본문에서 확인되는 표현" 같은 표현 찾기 패턴, `빈칸`/`____` 패턴이 들어오면 실패한다. 또한 `왕은 어떻게 했습니까?`, `무리는 무엇이라고 말했습니까?`처럼 구체적 장면/대상이 없는 질문과 이야기 제목을 따옴표 prefix로 반복하는 질문은 실패한다. "어떻게/무엇이라고" 질문의 보기는 모두 문법적으로 그 질문에 답할 수 있는 문장형이어야 하며, `그 일을 숨기고 물러났다`, `다른 사람에게 책임을 돌렸다` 같은 범용 filler 오답은 금지한다. 선택지가 `하시니라`, `하였더라`, `가로되` 같은 본문투 조각이면 실패하고, 해설은 `창 1:3 — '...'`처럼 구체적인 절 근거와 본문 인용을 포함해야 한다. 모든 문항의 해설 첫머리 구절은 해당 이야기의 `bible_ref` 범위 안에 있어야 하며, 범위를 넘으면 `verse_scope_violations` 리포트와 함께 빌드가 실패한다.
- **적용**: `make apply-seeds`에 `apply-seeds-quizzes`가 포함되어 `events` 적용 뒤 `quiz_questions`도 함께 반영된다.

#### `build_landmarks_seed_sql.py` — 시대별 지도 랜드마크 SQL (독립)
- **입력**: `assets/landmarks/landmarks.json` (성경 지명·구조물 — 예루살렘 성전, 시내산, 떨기나무 등)
- **출력**: `supabase/200_stories/landmarks_seed.sql` — `landmarks` UPSERT
- **스키마**: `code` (unique), `name`, `description`, `emoji`, `category`, `lat`, `lng`, `display_priority`, **`era_codes` (text[])**, `related_event_codes`, `is_active`
- **의존**: 없음 (인물·이야기와 독립). `db_init.sql` 또는 `make db-init` 으로 `landmarks` 테이블이 먼저 생성되어 있어야 한다 (별도 마이그레이션 없음).
- **stale 정리**: 현재 JSON 에 없는 `landmarks.code` 행을 삭제. 사용자가 JSON 에서 항목을 빼면 DB 에서도 사라진다.
- **목적**: 사용자가 시대를 선택하면 그 시대 era_code 가 포함된 랜드마크만 지도에 떠올라 시대별 무대 감각을 잡아 준다. 한 랜드마크가 여러 시대에 의미가 있으면(예: 예루살렘 성전 = 왕정 + 포로/귀환 + 예수 사역) 다중 코드.
- **PoC 단계**: emoji 컬럼만 사용 (이미지 자산 불필요). 향후 실제 일러스트가 필요하면 `icon_storage_path` 같은 새 컬럼을 추가하는 식으로 확장.

#### `renumber_story_indices.py` — story_index 재정렬
- **언제**: stories JSON 을 추가/삭제/수정해서 era 안의 `story_index` 가 듬성듬성 비거나 `None` 이 생겼을 때.
- **동작**: 같은 era 안에서 현재 `story_index` (정수) 순으로 정렬, `None` 항목은 같은 파일의 JSON 배열 위치 기준으로 이웃 사이에 보간(interpolate). 그 결과 1..N 으로 빈틈없이 재할당.
- **사용**: `python tools/seed/renumber_story_indices.py [--dry-run]`
- **재실행**: idempotent — 이미 1..N 인 era 는 그대로 둔다.
- **운영 주의**: 이 스크립트는 로컬 JSON만 바꾼다. real DB에 이미 공개된 시대의 중간 삽입을 이것만으로 처리하고 seed를 바로 apply하면 기존 event row id와 사용자 진행도 연결이 꼬일 수 있다.

### 3.2 이미지 생성 스크립트

#### `generate_avatars_vertex.py` — 인물 아바타 생성
- **의존**: `tools/seed/character_meta.json`
- **출력**: `assets/avatars/{code}.png`
- **API**: Google Cloud Vertex AI Gemini (`gemini-3-pro-image`, fallback `gemini-2.5-flash-image`)
- **옵션**: `--output-dir`, `--overwrite`, `--limit`, `--only-codes`, `--no-prune-orphans`
- **환경**: `GOOGLE_CLOUD_PROJECT` 환경변수 필요
- **stale 정리**: 시작 시 `character_meta.json` 의 code 집합과 `assets/avatars/` 의 PNG stem 을 비교, 불일치 PNG 를 삭제. 끄려면 `--no-prune-orphans`.
- **스타일 레퍼런스**: 개별 meta 항목의 `style_reference_codes`가 있으면 해당 `assets/avatars/{code}.png`를 Gemini 요청에 함께 넣어 기존 아바타 그림체를 맞춘다.
- **아바타 스타일 제약**: 전역 프롬프트는 윤곽선, 잉크선, 굵은 stroke를 금지하고 색 면 경계로만 형태를 구분하게 한다. 또한 지나치게 연한 색을 피하고 중간 이상 채도의 진한 색 면, 자연스러운 전신 비율(머리가 과하게 크지 않은 비율)을 요구한다. 특정 인물(예: 바울)은 정면 전신 포즈를 명시해 side/three-quarter view를 피한다.
- **저장 보정**: 모델이 가로/세로로 치우친 PNG를 반환해도 흰 배경 여백을 잘라낸 뒤 1:1 정사각형 캔버스로 패딩해 저장한다.
- **쿼터/일시 오류 재시도**: Vertex가 `429`, `503`, `504`를 반환하면 기본 30초 대기 후 2회 재시도한다. `VERTEX_IMAGE_RETRY_ATTEMPTS`, `VERTEX_IMAGE_RETRY_WAIT_SEC` 또는 `--retry-attempts`, `--retry-wait-sec`로 조절할 수 있다.
- **재생성**: 기존 PNG 가 있으면 skip, 없으면 새로 생성 → 사용자가 마음에 안 드는 PNG 를 지워두면 다음 실행에서 자동 재생성.
- **단일 인물 재생성**: `make generate-avatars AVATAR_CODES=hagar AVATAR_OVERWRITE=1` 처럼 전체 아바타를 다시 뽑지 않고 특정 코드만 덮어쓸 수 있다.
- **UI 안내자 아바타**: `guide`는 설명 팝업용 asset-only 항목이다.
  `make generate-avatars AVATAR_CODES=guide` 또는 전체 `make generate-avatars`로
  `assets/avatars/guide.png`를 만들고, `make thumbnails` 후
  `assets/avatars_thumbs/guide.png`를 앱에서 사용한다.

#### `generate_event_story_images_vertex.py` — 장면 이미지 생성
- **입력**: `assets/200_stories/*.json` (story_scenes 필드)
- **출력**: `assets/story_images/{title}/scene_{1-4}.png`, `manifest.json`, `prompt.txt`
- **API**: Google Cloud Vertex AI Gemini (`gemini-3-pro-image`, fallback `gemini-2.5-flash-image`)
- **결과**: 현재 시대별 stories JSON의 모든 `story_scenes` 기준으로 장면 이미지 생성
- **옵션**: `--no-prune-orphans`
- **요청 간 대기/쿼터 재시도**: 성공한 장면 요청 뒤에는 기본 2초 대기하고, Vertex가 `429`를 반환하면 기본 31초 대기 후 같은 요청을 재시도한다. 최종 실패 후 다음 장면으로 넘어갈 때도 기본 31초 대기한다. `--sleep-sec`, `--sleep-on-429-sec`, `--sleep-on-failure-sec`, `--retry-429-attempts`로 조절할 수 있다.
- **프롬프트 기록**: 이미지 생성 전에 각 이벤트 이미지 디렉토리의 `prompt.txt` 첫 줄에 `성경: 마 24:3-24:14`를 쓰고, 그 아래에 `scene_01.png: 한글 장면 프롬프트` 형식의 장면 줄을 순서대로 보장한다. 사건에 `bible_ref`/`bible_refs`가 여러 개 있으면 모든 `book from-to` 범위를 쉼표로 연결한다. 기존 내용이 같으면 다시 쓰지 않아 실패 장면만 재시도해도 멱등성을 유지한다.
- **장면 구체화**: 생성 프롬프트는 원문 장면의 장소·행동·표정 정보를 보존하고, 반복적인 추상 표정 꼬리말은 제거한다. Vertex 요청에는 사건에 맞는 옷차림·행색(어부 그물, 제사장 옷, 로마 갑옷, 법정/감옥/항해 상황 등)을 반영하라는 지시를 함께 넣는다. 족장/출애굽/왕정 핵심 인물은 기준 아바타와 별도로 장면의 성경 시점에 맞는 나이와 복장(예: 사라 노년, 이삭 성인, 모세 40/80/120세, 아론 제사장 이전 복장, 므리바 물 이후 아론의 흰수염 노년 대제사장 복장, 다윗 즉위 이후 왕복, 솔로몬 즉위 이후 왕복)을 자동 보강한다.
- **그림 말풍선**: `story_scenes`가 말풍선을 명시하면 기본 금지 정책 대신 말풍선 1개를 허용한다. 장면이 `글자 없는 말풍선`을 요청하면 읽을 수 있는 글자 대신 약속·명령·경고·복음 등 말의 내용을 작은 그림으로 표현한다.
- **인물 이름 매핑**: `characters_seed.sql`의 모든 `seed_persons` chunk를 읽어 `code → 한글 이름`을 복원하므로, `john_mark`처럼 뒤쪽 chunk에 있는 인물도 Vertex 프롬프트에서 `마가 요한 (john_mark)`으로 표시된다.
- **stale 정리**: 시작 시 현재 stories JSON 의 title 로 만들어진 디렉토리 외에는 모두 삭제 (NFC 정규화 비교).
- **재생성**: 기존 scene PNG 가 있으면 skip, 없으면 새로 생성 → 마음에 안 드는 scene 을 지워두면 다음 실행에서 자동 재생성.

#### `delete_selected_story_scenes.py` — 선택 장면 이미지 삭제
- **목적**: 프롬프트나 특정 아바타가 바뀐 장면만 PNG/JPG를 지워 다음 `make generate-story-images`/`make thumbnails`에서 재생성되게 한다.
- **모드**: `god-strict`는 `scene_characters`에 `god`가 있는 장면, `god-visual`은 하나님/성령/하늘 음성처럼 시각적으로 God이 등장하는 장면까지 포함, `nt-pictorial-bubbles`는 신약에서 `글자 없는 말풍선` 프롬프트가 들어간 장면을 대상으로 한다.
- **안전장치**: 기본은 dry-run이며 `--delete`를 붙여야 실제 파일을 삭제한다. 삭제 대상은 `assets/story_images/{title}/scene_XX.png`와 `assets/story_images_thumbs/{short_dir}/scene_XX.jpg`뿐이다. 옛 제목 기반 썸네일 경로도 있으면 함께 정리한다.

#### `generate_runtime_thumbnails.py` — 썸네일 생성
- **입력**: `assets/avatars/`, `assets/story_images/`, `assets/200_stories/*.json`
- **출력**: `assets/avatars_thumbs/`, `assets/story_images_thumbs/`
- **방식**: 로컬 이미지 리사이즈 (Vertex AI 불필요)
- **옵션**: `--no-prune-orphans`
- **story thumb 경로**: 원본 `assets/story_images/{한글 제목}/`은 그대로 두지만, 앱 번들용 썸네일은 Android/iOS 파일명 길이 제한을 피하기 위해 `assets/story_images_thumbs/{era_slug}_{story_index}/` 같은 짧은 디렉토리에 저장한다. `assets/story_images_thumbs/index.json`이 이야기 제목/원본 디렉토리와 짧은 디렉토리를 매핑한다.
- **stale 정리**: source 에 없는 thumbnail 자동 삭제 (빈 부모 디렉토리도 정리). 제목 기반 옛 썸네일 디렉토리는 새 짧은 디렉토리로 재생성된 뒤 orphan 으로 정리된다.

> 이전에 있던 `generate_assets_vertex.py` (UI 장식 요소 일괄 생성), `generate_app_icons.py` (런처 아이콘 일괄 생성)는 사용 빈도가 낮아 폐기됨. 결과물(`assets/elements/`, iOS/Android 런처 아이콘)은 이미 생성된 상태로 유지.

#### `tools/supabase/upload_character_avatars.py` — 캐릭터 아바타 Storage 업로드
- **입력**: `assets/avatars/*.png`
- **출력**: Supabase Storage `characters/{code}.png` + `characters.avatar_storage_path`
- **Make target**: `make upload-character-avatars [ENV=dev|real]`, 강제 덮어쓰기는 `make upload-character-avatars-force`
- **재실행 동작**: Make target 은 업로드 전에 `characters` 버킷을 먼저 비운다. 비운 뒤에도 기존 객체가 감지되면 중단한다. 스크립트를 직접 실행할 때만 기존 객체 skip 모드를 쓸 수 있다.
- **네트워크 재시도**: timeout, 429, 5xx 계열 응답은 기본 3회 재시도한다. timeout 직후 재시도에서 duplicate 응답이 오면 직전 요청이 서버에 반영된 것으로 보고 정상 skip 처리한다.

### 3.3 유틸리티 스크립트

#### `tools/images/story_scene_utils.py`
- scene 텍스트 파싱/정규화 공통 유틸리티. `generate_event_story_images_vertex.py`가 import 해서 prompt 빌드 시 사용.
- 단독 실행은 안 한다.

> 이전에 있던 `rewrite_story_scenes_for_image_generation.py` (story_scenes 자연어 → 시각 묘사 정제)는 이야기들이 이미 정제된 상태라 폐기됨.

#### `export_event_short_story_examples.py`
- DB에서 short_story 예시를 추출하여 JSON으로 출력 (검수용)

#### `update_pubspec_assets.py`
- **입력**: `assets/story_images_thumbs/index.json` + 하위 짧은 디렉토리 스캔
- **출력**: `pubspec.yaml`의 assets 블록을 갱신 (index.json + 이야기별 짧은 폴더 자동 반영)
- **옵션**: `--check` (변경 없이 diff만 확인, CI용)
- **배경**: Flutter는 assets 디렉토리 등록 시 직접 자식 파일만 포함하므로, 각 이야기 폴더를 개별 등록해야 한다. 긴 한글 제목 디렉토리를 그대로 등록하면 Android asset bundle 단계에서 URL-encoded 파일명이 OS 제한을 넘을 수 있어 짧은 폴더와 index.json 매핑을 쓴다.

#### `verify_polygons_contain_events.py`
- **입력**: `assets/landmarks/landmarks.json` + `assets/200_stories/*.json`
- **출력**: stdout 에 `OK: N events, all inside their region polygon.` (성공) 또는 stderr 에 위반 목록 + exit code 1 (실패)
- **목적**: 모든 사건의 (lat, lng) 가 소속 region polygon 안에 있는지 ray-casting 으로 검증. 새 이야기 추가 시 좌표가 polygon 밖으로 빠져 사건 핀이 색칠된 영역 밖에 표시되는 시각 모순을 차단.
- **옵션**: `--landmarks <path>`, `--stories <path>` (디렉토리이면 *.json 글롭). 기본값은 프로젝트 표준 경로.
- **자동 실행**: `.pre-commit-config.yaml` 의 pre-push 훅 — `landmarks.json` 또는 `assets/200_stories/*.json` 변경 시 push 전에 검증.

#### `audit_landmark_polygons.py`
- **입력**: `assets/landmarks/landmarks.json`
- **출력**: 박스형/저정점 region 후보 목록 (`--json` 지정 시 JSON)
- **목적**: `shapely` 없이도 axis-aligned edge 비율과 정점 수로 사각형에 가까운 region 을 빠르게 찾는다. 정제 우선순위 선정용이며 CI 차단용으로 쓰려면 `--fail-on-findings` 를 명시한다.
- **옵션**: `--max-vertices`, `--min-axis-ratio`, `--json`, `--fail-on-findings`
- **Make target**: `make audit-landmark-polygons`

#### `refine_landmark_polygons_from_geojson.py`
- **입력**: `assets/landmarks/landmarks.json` + `assets/maps/ne_50m_admin_0_countries.geojson` (Natural Earth 1:50m 국경)
- **출력**: 기본 `tools/seed/refined_polygons.json` (검토용), `--in-place` 옵션 시 `landmarks.json` 의 polygon 직접 교체
- **목적**: 사람이 사각형으로 그린 region polygon 을 Natural Earth 해안선/국경 정점에 스냅해 자연 곡선으로 정밀화한다.
- **동작**: 각 region 의 polygon bbox 를 `BBOX_PADDING_DEG` 만큼 패딩 → 그 영역과 교차하는 country feature 들을 union/intersect → 결과 polygon 에서 가장 큰 ring 채택 + simplify
- **자동 필터**: 결과 정점 수가 `MIN_REFINEMENT_VERTICES` (10) 미만이면 skip — country bbox 슬라이스(사각형)에 그치는 sub-country region (유대/사마리아 등) 은 원본 hand-drawn 이 더 나음
- **명시 skip**: `SKIP_CODES` (홍해 같은 수역, 비지리적 region)
- **옵션**: `--regions rgn_xxx,rgn_yyy` 일부만, `--simplify <deg>`, `--in-place`
- **재실행**: idempotent — 같은 입력이면 같은 결과
- **의존**: `pip install shapely` (`requirements.txt` 에 이미 포함)
- **Make target**: `make refine-landmark-polygons` 는 검토용 `tools/seed/refined_polygons.json` 만 생성한다. 실제 반영은 수동 `--in-place` 후 `verify_polygons_contain_events.py` 를 반드시 실행한다.

## 4. Makefile 타겟

Make target별 입력/출력/원격 영향과 신규 이야기 중간 삽입 주의점은
[guides/MAKE_TARGETS.md](guides/MAKE_TARGETS.md)를 canonical 운영 지도처럼 본다.

DB-first release 동기화는 다음 export target을 묶어 사용한다.

- `make export-stories-json`: published `events`를 `assets/200_stories/*.json`으로 역추출한다.
- `make export-quizzes-json`: `quiz_questions`를 `assets/quizzes/*.json`으로 역추출하고 `supabase/quizzes/db_events.json` 스냅샷을 갱신한다. 제안/RPC와 동일하게 1~3문항을 허용한다.
- `make export-event-region-mapping`: `events.landmark_id`와 `landmarks.parent_landmark_id` 기준으로 `assets/landmarks/event_region_mapping.json`을 갱신한다.
- `make release-sync-stories`: 위 세 export와 승인 proposal 이미지 동기화, 썸네일 생성, pubspec 갱신을 순서대로 실행한다. 여러 approved proposal이 한 번에 쌓여 있어도 전체 DB 상태를 로컬 release 번들로 당겨온다.

```makefile
# 개별 타겟
make seed-bible-verses       # build_krv_seed_sql.py 실행
make build-character-meta       # build_character_meta_json.py (모든 인물 카탈로그 + 아바타 프롬프트)
make generate-story-contexts # curated summary 정규화 + background_context 생성
make seed-stories            # build_200_stories_seed_sql.py (→ person-meta 의존)
make seed-characters            # build_characters_seed_sql.py (→ person-meta 의존)
make seed-quizzes            # build_quizzes_seed_sql.py (→ assets/quizzes + db_events)
make seed-landmarks          # build_landmarks_seed_sql.py (시대별 랜드마크, 독립)
make audit-landmark-polygons # 박스형/저정점 region polygon 감사
make refine-landmark-polygons # Natural Earth 기반 region polygon 정제 후보 생성
make generate-avatars        # generate_avatars_vertex.py (→ person-meta 의존, 기존 png 보존)
make generate-story-images   # generate_event_story_images_vertex.py
make thumbnails              # generate_runtime_thumbnails.py (→ avatars, story-images)
make build-guides            # story_guide.md + docs/guides/html/*.html 생성
make apply-draft             # draft JSON 1건 → proposal-scenes + pending proposal
make apply-drafts            # draft JSON 여러 건 → pending proposals 순차 등록
make export-stories-json     # DB events → assets/200_stories
make export-quizzes-json     # DB quiz_questions → assets/quizzes + db_events
make export-event-region-mapping # DB events.landmark_id → event_region_mapping
make release-sync-stories    # release canonical export + 승인 assets + thumbnails/pubspec

# DB 적용 (psql)
make apply-seeds-landmarks   # landmarks_seed.sql 적용 (UPSERT, 재실행 안전)
make apply-seeds-quizzes     # quizzes_seed.sql 적용 (delete 후 insert, 재실행 안전)

# 묶음 타겟
make seed-stories-characters    # seed-stories + seed-characters (권장, apply-seeds-stories-characters 와 대칭)
make seed-all                # seed-bible-verses + seed-stories + seed-characters + seed-quizzes + seed-landmarks
make generate-all            # generate-avatars + generate-story-images + thumbnails
make all                     # seed-all + generate-all
```

> **`story_index`**: `assets/200_stories/*.json` 의 각 이야기에 직접 박힌 정수 (era 내 1..N).
> 현재 로컬 직접 편집 운영에서는 사용자가 era 내 unique한 값을 직접 채운다.

문서 생성:
- `make build-guides` 는 `tools/docs/build_guides.py` 를 실행해 현재
  `assets/200_stories/*.json`, `assets/landmarks/event_region_mapping.json`,
  `tools/seed/character_meta.json` 기준의 `docs/guides/story_guide.md` 를
  재생성하고, `docs/guides/*.md` 전체를 `docs/guides/html/` HTML 문서로 변환한다.
  콘텐츠 JSON이나 가이드 문서가 바뀌면 함께 실행한다.

## 5. 에셋 디렉토리 구조

```
assets/
├── 200_stories/              # 소스 JSON (시대별 파일, story_index는 era 내 1..N)
│   ├── era_primeval.json
│   ├── era_patriarch.json
│   ├── era_exodus.json
│   ├── era_judges.json
│   ├── era_monarchy.json
│   ├── era_divided_kingdom.json
│   ├── era_exile_return.json
│   └── era_nt_*.json
├── avatars/                  # 원본 아바타 PNG (50+)
├── avatars_thumbs/           # 썸네일 아바타 (앱 번들)
├── story_images/             # 원본 장면 이미지 (제목 폴더 기준, stories JSON의 story_scenes와 동기화)
├── story_images_thumbs/      # 썸네일 장면 이미지 (앱 번들: 짧은 dir + index.json 매핑)
├── elements/                 # UI 장식 요소
├── bible/                    # KRV 성경 텍스트 (66 .txt)
├── maps/                     # GeoJSON 세계 지도
├── landmarks/                # 지도용 정적 데이터
│   └── landmarks.json        #   - 랜드마크 + region polygon (era_codes 포함)
└── app_icon/                 # 앱 런처 아이콘
```

## 6. 스토리 JSON 구조

```json
{
  "title": "창조: 7일과 안식",
  "era": "era_primeval",
  "characters": ["god"],
  "place_name": "메소포타미아(추정)",
  "lat": 31.018,
  "lng": 47.423,
  "summary": "하나님이 말씀으로 세상을 창조하시고 안식으로 완성하신다.",
  "background_context": "창세기 원역사는 창조부터 바벨 사건까지를 다루는 초반 이야기입니다. 이 이야기는 「창조」를 다룹니다.",
  "bible_ref": [{"book": "창", "from": "1:1", "to": "2:3"}],
  "start_year": -4000,
  "end_year": -4000,
  "time_precision": "approx",
  "story_index": 1,
  "story_scenes": ["장면1 설명", "장면2", "장면3", "장면4"],
  "scene_captions": ["이미지 설명1", "이미지 설명2", "이미지 설명3", "이미지 설명4"],
  "scene_characters": [[], ["god"], [], []]
}
```

- `story_index`: era 내부의 정수 순서. 현재 운영에서는 로컬 JSON 수동 편집으로 채운다.
- `background_context`: 상세 페이지 첫 카드에 표시되는 짧은 배경 지식 문구. 해설이나 읽기 가이드, 절 주소, 이전/다음 링크, 시간순 구간명이 아니라 시대 배경과 해당 사건이 무엇을 다루는지, 서신서 작성 배경을 1~2문장으로 담는다.
- `scene_captions`: `story_scenes`와 같은 길이의 사용자용 이미지 설명. 이미지 생성
  프롬프트가 아니라 상세 페이지 overlay에 그대로 표시되는 문구이며, summary 검수 때
  빠진 장면이 없는지 참고하는 보조 자료다.
- `story`/`short_story` 필드는 더 이상 빌더가 사용하지 않는다 (스키마에서 제거됨).

## 7. 환경 설정

```bash
# Python 가상환경 활성화
source .venv/bin/activate

# 필수 환경변수 (.env에서 로드)
export GOOGLE_CLOUD_PROJECT="your-project-id"

# DB/Storage 운영 비밀은 앱 번들에 들어가지 않는 .env.ops 에 둔다.
# 예: SUPABASE_DB_URL_DEV/PROD, SUPABASE_SERVICE_ROLE_KEY_DEV/PROD

# GCP 인증 (Vertex AI 사용 시)
gcloud auth application-default login
```

## 8. 실행 순서 (전체 초기 세팅 — drop & recreate)

> psql 통해 적용 (`make db-init`, `make apply-bible-verses-seeds`, `make apply-seeds-stories-characters`).
> Makefile 운영 타겟 기본값은 `ENV=dev`다. real 운영 DB는 초기화하지 않고,
> schema/RLS/RPC/cron 변경은 `make apply-patch ENV=real PATCH=...`로 적용한다.

1. `make seed-bible-verses` → 분할 SQL `krv_bible_verses_part_*.sql` 생성
2. `make seed-stories-characters` → `characters_seed.sql` + `200_stories_seed_part_*.sql` 생성
   (내부에서 `build-character-meta`가 한 번 실행되어 `character_meta.json`도 갱신)
3. `make db-init` — 앱 소유 Storage 버킷(`characters`, `proposal-scenes`, `proposal-characters`)을 먼저 비우고 남은 객체까지 확인/삭제한 뒤 스키마, 함수, 트리거, RLS, eras 시드 재생성 (drop & recreate). Storage purge 실패나 service_role 키 누락 시 SQL 실행 전 중단한다.
4. `make apply-bible-verses-seeds` — KRV 31,904절 적용 (1회만)
5. `make apply-seeds-stories-characters` — persons + events 적용 (UPSERT)
6. `make generate-avatars` (Vertex 비용; 기존 `assets/avatars/{code}.png`는 자동 보존, 신규만 생성)
7. `make generate-story-images` (장면 이미지 필요 시)
8. `make thumbnails` (앱 번들용 썸네일 생성)
9. `make update-pubspec-assets` (pubspec.yaml의 story_images_thumbs index.json + 짧은 디렉토리 자동 갱신)
10. `scripts/run_dev.sh` 또는 `scripts/run_real.sh`

real 신규 프로젝트 최초 bootstrap 예:

```bash
make seed-all && make thumbnails && make update-pubspec-assets
CONFIRM_REAL_DB_INIT=1 make db-init ENV=real
make apply-seeds ENV=real
make upload-character-avatars ENV=real
```

위 bootstrap 명령은 새 Supabase 프로젝트를 처음 만들거나 복구할 때만 쓴다.
real 배포 이후 DB 구조 변경은 [guides/develop-flow.md](guides/develop-flow.md)의
patch 흐름을 따른다.

### 신규 이야기 1건 추가된 경우
⚠️ **반드시 먼저**: 로컬 `assets/200_stories/`가 DB와 동기화된 상태여야 한다. 로컬이 비었거나 오래됐다면 `make export-stories-json` (운영 기준은 `ENV=real` 또는 `ENV=prod`) 으로 DB의 published events를 JSON으로 역추출해 복원한다. 이 사전 조건을 빼먹고 부분 상태에서 빌드하면 기존 인물 description이 손상된다.

사전 조건 충족 후:
`make seed-stories-characters && make apply-seeds-stories-characters && make generate-avatars && make thumbnails && make update-pubspec-assets`.

단계별 동작과 안전성 근거(UPSERT PK, description 덮어쓰기 주의, SKIP 조건)는 [guides/CONTENT_UPDATE.md §2.1b](guides/CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로) 참조.
개발/배포 시 어떤 target 을 dev 와 real 에 적용할지는 [guides/develop-flow.md](guides/develop-flow.md)를 따른다.
