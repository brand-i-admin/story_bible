# 데이터 파이프라인 도메인 레퍼런스

> 이 문서는 `$data-pipeline` 스킬이 참조하는 데이터 파이프라인 가이드이다.

## 0. 입력 데이터 (사람·AI 이전 단계에서 준비됨)

- **`assets/bible/*.txt`** — KRV 개역한글 66권 텍스트 (31,904절). 외부 공개 본문을 정리해 둔 입력.
- **`assets/200_stories/*.json`** — 215개 이야기 dict 리스트 (5개 파일). **사람이 의도하고 AI(LLM)로 초안을 뽑아 정리한 결과물**이다. 파이프라인은 이 정리된 JSON을 입력으로만 사용하고, AI 생성 단계는 파이프라인 밖에서 1회 수행되었다. 이후 새 이야기는 어드민 웹/수동 편집으로 같은 포맷에 맞춰 추가한다.

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
└── export/                             # DB → JSON 검수용
assets/                                 # 입력/출력 에셋
Makefile                                # 파이프라인 오케스트레이션
.venv/                                  # Python 가상환경
```

## 2. 파이프라인 DAG (의존 관계)

```
                    ┌─────────────────────────────────────────────┐
                    │         assets/200_stories/*.json           │
                    │         (215개 이야기 소스)                  │
                    └──┬──────────────────────────┬───────────────┘
                       │                          │
                       ▼                          ▼
        build_character_meta_json.py       generate_event_story_images_vertex.py
               │                                  │
               ▼                                  ▼
      character_meta.json                     assets/story_images/ (860장)
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
  - `--active-threshold 2` (기본) — 이 횟수 이상이면 `is_active_default=true` 표시 → seed에서 활성으로 INSERT
- **규칙**:
  - `disciples`, `apostles`, `brothers` → 개별 인물로 확장
  - `NON_INDIVIDUAL_CODES`(`crowd`, `angels` 등) 제외
  - 결과: 100+ 인물 코드 + 프롬프트 + `is_active_default` 힌트
- ⚠️ **부분 스캔 주의**: 이 빌더는 로컬 디렉토리에 있는 JSON만 스캔한다. 로컬이 DB와 동기화되지 않은 상태(예: 새 이야기 파일 1개만 있는 상태)에서 생성된 meta로 `build_characters_seed_sql`을 돌리면 그 안에 포함된 **기존 DB 인물의 description이 부분 정보로 덮어써질 수 있다** (UPSERT는 `coalesce(excluded.description, persons.description)` — excluded가 항상 non-null이라 덮어씀). 안전 절차: [guides/CONTENT_UPDATE.md §2.1b \[0\]](guides/CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로) 참조.

#### `build_200_stories_seed_sql.py` — events SQL
- **의존**: `tools/seed/character_meta.json` (인물 화이트리스트). 입력 JSON 각 항목에 `story_index` 키가 있어야 함 (없으면 `ValueError` 즉시 raise).
- **입력**: `assets/200_stories/*.json` + `tools/seed/character_meta.json`
- **출력**:
  - `supabase/200_stories/200_stories_seed.sql` — `events` 한 테이블 INSERT (배열 + JSONB 컬럼 포함)
  - `supabase/200_stories/200_stories_seed_part_*.sql` — SQL Editor 분할 파일
  - `supabase/200_stories/200_stories_report.json` — 리포트
  - `supabase/200_stories/200_stories_normalized.json` — 검수용 정규화 JSON
- **출력 컬럼**: `era_id`(eras 조인), `title`, `summary`, `story_scenes`(jsonb), `scene_characters`(jsonb), `character_codes`(text[]), `bible_refs`(jsonb), `start_year`/`end_year`/`time_precision`, `story_index`, `place_name`/`lat`/`lng`, `status='published'`
- **on conflict 키**: `(era_id, story_index)` — 시드 재실행 시 같은 자리의 이벤트를 갱신
- **참고**: `code`/`story`/`short_story`/`time_sort_key`/`event_characters`/`event_bible_refs` 산출 로직은 폐기됨 (스키마 v3 변경)

#### `build_characters_seed_sql.py` — characters SQL
- **의존**: `tools/seed/character_meta.json` (선행 필수)
- **입력**: `tools/seed/character_meta.json` + `assets/200_stories/*.json` (대표 스토리 선택용)
- **출력**: `supabase/200_stories/characters_seed.sql` — `persons` INSERT (UPSERT — `is_active`는 보존)
- **참고**: `character_eras`는 view라 INSERT 대상 아님 (db_init.sql 정의)

### 3.2 이미지 생성 스크립트

#### `generate_avatars_vertex.py` — 인물 아바타 생성
- **의존**: `tools/seed/character_meta.json`
- **출력**: `assets/avatars/{code}.png`
- **API**: Google Cloud Vertex AI Imagen
- **옵션**: `--output-dir`, `--overwrite`, `--limit`
- **환경**: `GOOGLE_CLOUD_PROJECT` 환경변수 필요

#### `generate_event_story_images_vertex.py` — 장면 이미지 생성
- **입력**: `assets/200_stories/*.json` (story_scenes 필드)
- **출력**: `assets/story_images/{title}/scene_{1-4}.png`
- **API**: Google Cloud Vertex AI Imagen
- **결과**: 215 이벤트 × 4장면 = 최대 860장

#### `generate_runtime_thumbnails.py` — 썸네일 생성
- **입력**: `assets/avatars/`, `assets/story_images/`
- **출력**: `assets/avatars_thumbs/`, `assets/story_images_thumbs/`
- **방식**: 로컬 이미지 리사이즈 (Vertex AI 불필요)

> 이전에 있던 `generate_assets_vertex.py` (UI 장식 요소 일괄 생성), `generate_app_icons.py` (런처 아이콘 일괄 생성)는 사용 빈도가 낮아 폐기됨. 결과물(`assets/elements/`, iOS/Android 런처 아이콘)은 이미 생성된 상태로 유지.

### 3.3 유틸리티 스크립트

#### `tools/images/story_scene_utils.py`
- scene 텍스트 파싱/정규화 공통 유틸리티. `generate_event_story_images_vertex.py`가 import 해서 prompt 빌드 시 사용.
- 단독 실행은 안 한다.

> 이전에 있던 `rewrite_story_scenes_for_image_generation.py` (story_scenes 자연어 → 시각 묘사 정제)는 215개 이야기가 이미 정제된 상태라 폐기됨.

#### `export_event_short_story_examples.py`
- DB에서 short_story 예시를 추출하여 JSON으로 출력 (검수용)

#### `update_pubspec_assets.py`
- **입력**: `assets/story_images_thumbs/` 하위 디렉토리 스캔
- **출력**: `pubspec.yaml`의 assets 블록을 갱신 (211+개 폴더 자동 반영)
- **옵션**: `--check` (변경 없이 diff만 확인, CI용)
- **배경**: Flutter는 assets 디렉토리 등록 시 직접 자식 파일만 포함하므로, 각 이야기 폴더를 개별 등록해야 한다.

## 4. Makefile 타겟

```makefile
# 개별 타겟
make seed-bible-verses       # build_krv_seed_sql.py 실행
make build-character-meta       # build_character_meta_json.py (모든 인물 카탈로그 + 아바타 프롬프트)
make seed-stories            # build_200_stories_seed_sql.py (→ person-meta 의존)
make seed-characters            # build_characters_seed_sql.py (→ person-meta 의존)
make generate-avatars        # generate_avatars_vertex.py (→ person-meta 의존, 기존 png 보존)
make generate-story-images   # generate_event_story_images_vertex.py
make thumbnails              # generate_runtime_thumbnails.py (→ avatars, story-images)

# 묶음 타겟
make seed-stories-characters    # seed-stories + seed-characters (권장, apply-seeds-stories-characters 와 대칭)
make seed-all                # seed-bible-verses + seed-stories + seed-characters
make generate-all            # generate-avatars + generate-story-images + thumbnails
make all                     # seed-all + generate-all
```

> **`story_index`**: `assets/200_stories/*.json` 의 각 이야기에 직접 박힌 정수 (era 내 1..N).
> 어드민 웹이 등록 시 자동 부여하며, 수동으로 JSON 편집할 때는 era 내 unique한 값을 사용자가 직접 채운다.

## 5. 에셋 디렉토리 구조

```
assets/
├── 200_stories/              # 소스 JSON (5파일: 1_50, 51_100, ...)
│   ├── 1_50.json
│   ├── 51_100.json
│   ├── 101_150.json
│   ├── 151_184.json
│   └── 185_215.json
├── avatars/                  # 원본 아바타 PNG (50+)
├── avatars_thumbs/           # 썸네일 아바타 (앱 번들)
├── story_images/             # 원본 장면 이미지 (215폴더 × 4장)
├── story_images_thumbs/      # 썸네일 장면 이미지 (앱 번들)
├── elements/                 # UI 장식 요소
├── bible/                    # KRV 성경 텍스트 (66 .txt)
├── maps/                     # GeoJSON 세계 지도
└── app_icon/                 # 앱 런처 아이콘
```

## 6. 스토리 JSON 구조

```json
{
  "title": "001 창조: 7일과 안식",
  "era": "era_primeval",
  "persons": ["god"],
  "place_name": "메소포타미아(추정)",
  "lat": 31.018,
  "lng": 47.423,
  "summary": "하나님이 말씀으로 세상을 창조하시고 안식으로 완성하신다.",
  "bible_ref": [{"book": "창", "from": "1:1", "to": "2:3"}],
  "start_year": -4000,
  "end_year": -4000,
  "time_precision": "approx",
  "story_index": 1,
  "story_scenes": ["장면1 설명", "장면2", "장면3", "장면4"],
  "scene_characters": [[], ["god"], [], []]
}
```

- `story_index`: era 내부의 정수 순서. 어드민 웹 또는 수동 편집으로 채운다.
- `story`/`short_story` 필드는 더 이상 빌더가 사용하지 않는다 (스키마에서 제거됨).

## 7. 환경 설정

```bash
# Python 가상환경 활성화
source .venv/bin/activate

# 필수 환경변수 (.env에서 로드)
export GOOGLE_CLOUD_PROJECT="your-project-id"

# GCP 인증 (Vertex AI 사용 시)
gcloud auth application-default login
```

## 8. 실행 순서 (전체 초기 세팅 — drop & recreate)

> psql 통해 적용 (`make db-init`, `make apply-bible-verses-seeds`, `make apply-seeds-stories-characters`).

1. `make seed-bible-verses` → 분할 SQL `krv_bible_verses_part_*.sql` 생성
2. `make seed-stories-characters` → `characters_seed.sql` + `200_stories_seed_part_*.sql` 생성
   (내부에서 `build-character-meta`가 한 번 실행되어 `character_meta.json`도 갱신)
3. `make db-init` — 스키마, 함수, 트리거, RLS, eras 시드 (drop & recreate)
4. `make apply-bible-verses-seeds` — KRV 31,904절 적용 (1회만)
5. `make apply-seeds-stories-characters` — persons + events 적용 (UPSERT)
6. `make generate-avatars` (Vertex 비용; 기존 `assets/avatars/{code}.png`는 자동 보존, 신규만 생성)
7. `make generate-story-images` (장면 이미지 필요 시)
8. `make thumbnails` (앱 번들용 썸네일 생성)
9. `make update-pubspec-assets` (pubspec.yaml의 story_images_thumbs 디렉토리 자동 갱신)
10. `flutter run` (또는 `--dart-define=ENV=prod`)

### 신규 이야기 1건 추가된 경우
⚠️ **반드시 먼저**: 로컬 `assets/200_stories/`가 DB와 동기화된 상태여야 한다. 로컬이 비었거나 오래됐다면 `make export-stories-json` (또는 `ENV=prod` 버전) 으로 DB의 published events를 JSON으로 역추출해 복원한다. 이 사전 조건을 빼먹고 부분 상태에서 빌드하면 기존 인물 description이 손상된다.

사전 조건 충족 후:
`make seed-stories-characters && make apply-seeds-stories-characters && make generate-avatars && make thumbnails && make update-pubspec-assets`.

단계별 동작과 안전성 근거(UPSERT PK, description 덮어쓰기 주의, SKIP 조건)는 [guides/CONTENT_UPDATE.md §2.1b](guides/CONTENT_UPDATE.md#21b-어드민-웹-없이-json-직접-편집--신규-이야기-1건-추가-백업-경로) 참조.
