# story_bible

## bible_verses 테이블 적재 (Python으로 SQL 생성 -> SQL 실행)

중요: Python이 `bible_verses`에 직접 insert 하지 않습니다.

전체 흐름:
1. Python 스크립트로 `krv_bible_verses.sql` 생성
2. 생성된 SQL을 Supabase에서 실행하여 적재

사용 스크립트:
- `tools/seed/build_krv_seed_sql.py`

입력 데이터:
- 기본 모드: `assets/bible/*.txt` (예: `01 창세기.txt`, `02 출애굽기.txt`)
- 파일 모드: CSV/TSV/JSONL (`assets/bible/  # 텍스트 디렉토리 모드 사용` 참고)

### 1) SQL 생성

`assets/bible` 디렉토리에서 생성:

```bash
python3 tools/seed/build_krv_seed_sql.py \
  --input-dir assets/bible \
  --output supabase/seeds/krv_bible_verses.sql \
  --truncate-translation
```

CSV 파일에서 생성:

```bash
python3 tools/seed/build_krv_seed_sql.py \
  --input assets/bible/  # 텍스트 디렉토리 모드 사용 \
  --input-format csv \
  --output supabase/seeds/krv_bible_verses.sql \
  --truncate-translation
```

옵션 설명:
- `--truncate-translation`: 같은 번역본(`KRV`) 기존 데이터를 먼저 지우고 다시 채웁니다.
- `--translation`: 기본 번역 코드 (기본값 `KRV`)

### 2) Supabase에 반영

아래 중 하나를 선택합니다.

1. Supabase SQL Editor에서 `supabase/seeds/krv_bible_verses.sql` 실행
2. 파일이 너무 크면 `supabase/seeds/krv_bible_verses_part_01.sql` ~ `..._10.sql` 순서대로 실행
3. DB 접속 문자열이 있으면 `psql`로 실행

```bash
psql "$SUPABASE_DB_URL" -f supabase/seeds/krv_bible_verses.sql
```

### 3) 적재 확인

```sql
select translation, count(*) as verse_count
from bible_verses
group by translation;
```

## 초기 세팅 Flow (권장)

### 0) db_init.sql 을 Supabase Editor 에 실행

### 1) 성경 구절(`bible_verses`)을 Supabase에 넣기
- 이 문서 상단 `bible_verses 테이블 적재` 절차를 그대로 사용합니다.
- 핵심: `tools/seed/build_krv_seed_sql.py --split-parts 10`로 SQL 생성 -> Supabase SQL Editor 실행. -> 31904 개 생성 확인

### 2) `assets/events`에 통합 이벤트 JSON 준비
- `assets/events/*.json` 형태로 준비합니다.
- 각 항목은 `title`, `era`, `characters`, `landmark_code`, `bible_ref`, `story_index`, `story_scenes`, `quiz_questions` 등을 포함합니다.

### 3) 인물 메타 JSON 생성 (`tools/seed/character_meta.json`)
- 사용 스크립트: `tools/seed/build_character_meta_json.py`
- 한 파일에 **인물 카탈로그**(code/name/is_active_default)와 **아바타 프롬프트**가 함께 들어감
- 규칙: `2회 이상 등장 개인`만 포함 (집합/비개인 코드 제거 + group 확장 반영)

```bash
python3 tools/seed/build_character_meta_json.py \
  --stories-dir assets/events \
  --output tools/seed/character_meta.json
```

### 4) 이야기 JSON을 Supabase 적재용 SQL로 정제/생성 후 적용
- 사용 스크립트: `tools/seed/build_events_seed_sql.py`
- 주의: `tools/seed/character_meta.json`이 먼저 있어야 합니다. (3번 단계 선행)
- 정제 규칙:
  - `disciples`, `apostles`, `brothers`는 개인 코드로 확장
  - `mysterious_man`, `babel_people`, `abraham_servant` 등 비개인/집합 코드는 제거
  - 인물 화이트리스트는 `tools/seed/character_meta.json` 기준으로 필터링

```bash
python3 tools/seed/build_events_seed_sql.py \
  --output-dir supabase/events \
  --character-meta-json tools/seed/character_meta.json
```

- 생성 결과:
  - `supabase/events/events_seed.sql`
  - `supabase/events/events_report.json`
  - `supabase/events/events_normalized.json`
- Supabase SQL Editor에서 `events_seed.sql`를 실행해 `events`를 반영합니다.
- SQL Editor에서 `Query is too large` 에러가 나면 분할 SQL을 생성해 순서대로 실행합니다.

```bash
# 기본은 2분할 생성
python3 tools/seed/build_events_seed_sql.py \
  --output-dir supabase/events \
  --character-meta-json tools/seed/character_meta.json
```

### 5) `assets/avatars` 인물 이미지 생성
- 사용 스크립트: `tools/images/generate_avatars_vertex.py`
- 기본 입력은 `tools/seed/character_meta.json`입니다 (여기서 아바타 프롬프트를 읽음).

```bash
source .env
python3 tools/images/generate_avatars_vertex.py \
  --character-meta-json tools/seed/character_meta.json \
  --output-dir assets/avatars
```

### 6) 선정 인물을 Supabase `persons`/`person_eras`에 반영
- SQL 생성 스크립트: `tools/seed/build_characters_seed_sql.py`

```bash
python3 tools/seed/build_characters_seed_sql.py \
  --character-meta-json tools/seed/character_meta.json \
  --stories-dir assets/events \
  --output supabase/events/characters_seed.sql
```

- 생성된 `supabase/events/characters_seed.sql`을 Supabase SQL Editor에서 실행합니다.

## 기타 자산 메모

### `assets/elements` 관리
- 기본 생성: `(제거됨)`
- 생성 후 배경 제거/크기 보정 수작업 필요

### `assets/maps` 재세팅
- 필요 파일: `assets/maps/ne_50m_admin_0_countries.geojson`

```bash
mkdir -p assets/maps
curl -L -o /tmp/ne_50m_admin_0_countries.zip \
  https://naciscdn.org/naturalearth/50m/cultural/ne_50m_admin_0_countries.zip
unzip -o /tmp/ne_50m_admin_0_countries.zip -d /tmp/ne_50m_admin_0_countries
ogr2ogr -f GeoJSON assets/maps/ne_50m_admin_0_countries.geojson \
  /tmp/ne_50m_admin_0_countries/ne_50m_admin_0_countries.shp
```

### `assets/story_images` 생성
- 사용 스크립트: `tools/images/generate_event_story_images_vertex.py`
- `assets/events/*.json`의 `story_scenes` 리스트를 읽어 장면(1~4)을 생성합니다.


```bash
python3 tools/images/generate_event_story_images_vertex.py
```
