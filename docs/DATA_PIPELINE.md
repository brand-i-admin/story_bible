# 데이터 파이프라인 도메인 레퍼런스

> 이 문서는 `$data-pipeline` 스킬이 참조하는 데이터 파이프라인 가이드이다.

## 1. 파일 범위

```
tools/                                  # Python 스크립트 (12개)
assets/                                 # 입력/출력 에셋
Makefile                                # 파이프라인 오케스트레이션
.venv/                                  # Python 가상환경
```

## 2. 파이프라인 DAG (의존 관계)

```
                    ┌─────────────────────────────────────────────┐
                    │         assets/200_stories/*.json           │
                    │         (215개 이야기 소스)                  │
                    └──┬──────────────┬───────────────┬───────────┘
                       │              │               │
                       ▼              │               ▼
        build_avatar_prompts_json.py  │   rewrite_story_scenes_*.py
               │                      │               │
               ▼                      │               ▼
      avatar_prompts.json             │   generate_event_story_images_vertex.py
         │        │       │           │               │
         │        │       │           │               ▼
         │        │       │           │     assets/story_images/ (860장)
         │        │       │           │               │
         ▼        ▼       ▼           │               │
  generate_   build_    build_200_    │               │
  avatars_    persons_  stories_      │               │
  vertex.py   seed_     seed_sql.py   │               │
    │         sql.py      │           │               │
    ▼           │         ▼           │               │
  assets/       │   200_stories_      │               │
  avatars/      │   seed.sql          │               │
    │           ▼                     │               │
    │     persons_seed.sql            │               │
    │                                 │               │
    └────────────┬────────────────────┘               │
                 │                                    │
                 ▼                                    │
        generate_runtime_thumbnails.py ◄──────────────┘
                 │
                 ▼
        assets/avatars_thumbs/
        assets/story_images_thumbs/

  ┌────────────────────────────────────┐
  │   assets/bible/*.txt  (독립)       │
  │         │                          │
  │         ▼                          │
  │  build_krv_seed_sql.py             │
  │         │                          │
  │         ▼                          │
  │  krv_bible_verses*.sql             │
  └────────────────────────────────────┘
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

#### `build_avatar_prompts_json.py` — 아바타 프롬프트 생성
- **입력**: `assets/200_stories/*.json`
- **출력**: `tools/avatar_prompts.json`
- **옵션**: `--min-mentions 2` (2회 이상 등장 인물만)
- **규칙**:
  - `disciples`, `apostles` → 개별 사도명으로 확장
  - `mysterious_man`, `babel_people` 등 비개인 코드 제거
  - 결과: 50+ 인물 코드 + 이미지 생성 프롬프트

#### `build_200_stories_seed_sql.py` — 이야기 SQL
- **의존**: `tools/avatar_prompts.json` (선행 필수)
- **입력**: `assets/200_stories/*.json` + `tools/avatar_prompts.json`
- **출력**:
  - `supabase/200_stories/200_stories_seed.sql` — events, event_persons, event_bible_refs INSERT
  - `supabase/200_stories/200_stories_report.json` — 리포트
  - `supabase/200_stories/200_stories_normalized.json` — 정규화된 JSON
- **옵션**: `--output-dir supabase/200_stories`

#### `build_persons_seed_sql.py` — 인물 SQL
- **의존**: `tools/avatar_prompts.json` (선행 필수)
- **입력**: `tools/avatar_prompts.json` + `assets/200_stories/*.json`
- **출력**: `supabase/200_stories/persons_seed.sql` — persons, person_eras INSERT

### 3.2 이미지 생성 스크립트

#### `generate_avatars_vertex.py` — 인물 아바타 생성
- **의존**: `tools/avatar_prompts.json`
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

#### `generate_assets_vertex.py` — UI 장식 요소
- **출력**: `assets/elements/`
- **프롬프트**: 하드코딩 (장식 프레임, 구분선 등)

#### `generate_app_icons.py` — 앱 아이콘
- **출력**: iOS/Android 런처 아이콘

### 3.3 유틸리티 스크립트

#### `rewrite_story_scenes_for_image_generation.py`
- story_scenes 텍스트를 Vertex AI 이미지 생성에 최적화된 프롬프트로 보강

#### `story_scene_utils.py`
- 공통 유틸리티 (scene 텍스트 파싱, 정규화 등)

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
make build-avatar-prompts    # build_avatar_prompts_json.py 실행
make seed-stories            # build_200_stories_seed_sql.py (→ build-avatar-prompts 의존)
make seed-persons            # build_persons_seed_sql.py (→ build-avatar-prompts 의존)
make generate-avatars        # generate_avatars_vertex.py (→ build-avatar-prompts 의존)
make generate-story-images   # generate_event_story_images_vertex.py
make thumbnails              # generate_runtime_thumbnails.py (→ avatars, story-images 의존)

# 묶음 타겟
make seed-all                # seed-bible-verses + seed-stories + seed-persons
make generate-all            # generate-avatars + generate-story-images + thumbnails
make all                     # seed-all + generate-all
```

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
  "summary": "...",
  "story": "...",
  "short_story": "...",
  "bible_ref": [{"book": "창", "from": "1:1", "to": "2:3"}],
  "start_year": -4000,
  "end_year": -4000,
  "time_precision": "approx",
  "story_scenes": ["장면1 설명", "장면2", "장면3", "장면4"],
  "scene_persons": [[], ["god"], [], []]
}
```

## 7. 환경 설정

```bash
# Python 가상환경 활성화
source .venv/bin/activate

# 필수 환경변수 (.env에서 로드)
export GOOGLE_CLOUD_PROJECT="your-project-id"

# GCP 인증 (Vertex AI 사용 시)
gcloud auth application-default login
```

## 8. 실행 순서 (전체 초기 세팅)

1. `make seed-bible-verses` → Supabase SQL Editor에서 실행
2. `make build-avatar-prompts`
3. `make seed-stories` → Supabase SQL Editor에서 실행
4. `make seed-persons` → Supabase SQL Editor에서 실행
5. `make generate-avatars`
6. `make generate-story-images`
7. `make thumbnails`
