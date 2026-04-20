# Generated Media Flow

이 문서는 현재 프로젝트의 이미지 생성/썸네일/DB 반영 구조를 이해하기 쉽게 정리한 문서다.

핵심 방향은 다음과 같다.

- 원본 이미지는 생성 파이프라인용으로 유지할 수 있다.
- 앱에서 실제로 보여주는 이미지는 가능한 한 `thumbnail asset`을 우선 사용한다.
- DB는 이미지 파일 자체를 저장하는 것이 아니라, 어떤 인물/이벤트/장면이 어떤 asset 경로를 써야 하는지 아는 인덱스 역할을 한다.

## 왜 이렇게 바꿨는가

기존에는 아바타나 스토리 장면 이미지가 `assets/...` 폴더에만 존재했고, 앱은 폴더명이나 파일명 규칙을 추측해서 이미지를 찾고 있었다.

이 방식은 당장은 동작하지만 다음 문제가 있다.

- 새 이미지를 생성한 뒤 Supabase에 반영하는 흐름이 불명확하다.
- 어떤 이벤트의 몇 번째 장면 이미지인지 DB가 직접 알 수 없다.
- 재생성이나 재실행 시 중복/덮어쓰기 기준이 약하다.

그래서 이번 구조에서는:

- 생성 스크립트가 이미지와 함께 `manifest`를 남긴다.
- DB merge는 manifest를 읽어 stable key 기준으로 upsert 한다.
- Flutter 앱은 DB 정보를 우선 사용하되, 데이터가 없으면 기존 asset 추론 방식을 fallback 으로 유지한다.

## 1. 실제 운영 플로우

권장 순서는 다음과 같다.

1. 아바타 원본 생성
   - [`tools/generate_avatars_vertex.py`](/Users/wonny/workspace/story_bible/tools/generate_avatars_vertex.py)
   - 결과:
     - `assets/avatars/...png`
     - `supabase/generated_media/avatars.json`

2. 스토리 장면 원본 생성
   - [`tools/generate_event_story_images_vertex.py`](/Users/wonny/workspace/story_bible/tools/generate_event_story_images_vertex.py)
   - 결과:
     - `assets/story_images/...`
     - `supabase/generated_media/story_scenes.json`

3. 썸네일 생성
   - [`tools/generate_runtime_thumbnails.py`](/Users/wonny/workspace/story_bible/tools/generate_runtime_thumbnails.py)
   - 결과:
     - `assets/avatars_thumbs/...`
     - `assets/story_images_thumbs/...`
     - 기존 manifest에 thumbnail 정보 반영

4. DB merge SQL 생성
   - [`tools/build_generated_media_merge_sql.py`](/Users/wonny/workspace/story_bible/tools/build_generated_media_merge_sql.py)
   - 결과:
     - `supabase/generated_media/generated_media_merge.sql`

5. Supabase 반영
   - 스키마 반영:
     - [`supabase/migrations/20260407_generated_media_schema.sql`](/Users/wonny/workspace/story_bible/supabase/migrations/20260407_generated_media_schema.sql)
   - 그 다음 media merge SQL 반영

정리하면:

- `supabase push`는 스키마 반영 단계
- `generated_media_merge.sql` 반영은 생성된 이미지 메타데이터 반영 단계

## 2. DB 테이블별 역할

### `persons`

기존 인물 테이블이다.

- `avatar_url`
  - 원본 이미지 경로
- `avatar_thumb_url`
  - 앱에서 우선 사용할 썸네일 asset 경로

### `events`

기존 이벤트 테이블이다.

- `thumb_url`
  - 대표 썸네일 경로
- `story_asset_dir`
  - 원본 장면 이미지 폴더
- `story_thumbnail_dir`
  - 장면 썸네일 폴더
- `story_scene_count`
  - 장면 수

### `person_generated_assets`

인물 이미지 생성 결과 상세 기록 테이블이다.

- 어떤 인물의 아바타가 생성되었는지
- 원본 경로와 썸네일 경로가 무엇인지
- 어떤 모델로 생성했는지
- 추가 메타데이터가 무엇인지

를 저장한다.

### `event_scene_generated_assets`

이벤트 장면 이미지 생성 결과 상세 기록 테이블이다.

`(event_id, scene_index)` 기준으로:

- 원본 경로
- 썸네일 경로
- 생성 상태
- 프롬프트 관련 메타데이터
- 생성 모델 정보

를 저장한다.

### 왜 요약 테이블과 상세 테이블을 나눴는가

- `persons`, `events`는 앱이 빠르게 읽는 대표 정보
- `*_generated_assets`는 생성 파이프라인 상세 이력

이 두 역할을 분리해야 앱 조회와 생성 자동화가 서로 덜 엉킨다.

## 3. Manifest JSON 예시

### 아바타 manifest 예시

```json
{
  "schema_version": 1,
  "asset_family": "avatars",
  "assets": [
    {
      "natural_key": "person:moses:avatar:none:original",
      "owner_type": "person",
      "owner_code": "moses",
      "asset_role": "avatar",
      "scene_index": null,
      "variant": "original",
      "relative_path": "assets/avatars/moses.png",
      "source_relative_path": null,
      "mime_type": "image/png",
      "generator": "tools/generate_avatars_vertex.py",
      "generator_model": "imagen-4.0-generate-001",
      "metadata": {}
    },
    {
      "natural_key": "person:moses:avatar:none:thumbnail",
      "owner_type": "person",
      "owner_code": "moses",
      "asset_role": "avatar",
      "scene_index": null,
      "variant": "thumbnail",
      "relative_path": "assets/avatars_thumbs/moses.png",
      "source_relative_path": "assets/avatars/moses.png",
      "mime_type": "image/png",
      "generator": "tools/generate_runtime_thumbnails.py",
      "generator_model": null,
      "metadata": {}
    }
  ]
}
```

### 스토리 장면 manifest 예시

```json
{
  "schema_version": 1,
  "asset_family": "story_scenes",
  "assets": [
    {
      "natural_key": "event:evt_024:story_scene:1:original",
      "owner_type": "event",
      "owner_code": "evt_024",
      "asset_role": "story_scene",
      "scene_index": 1,
      "variant": "original",
      "relative_path": "assets/story_images/024 사라의 죽음과 막벨라 굴/scene_01.png",
      "source_relative_path": null,
      "mime_type": "image/png",
      "generator": "tools/generate_event_story_images_vertex.py",
      "metadata": {
        "event_title": "사라의 죽음과 막벨라 굴",
        "scene_prompt": "..."
      }
    },
    {
      "natural_key": "event:evt_024:story_scene:1:thumbnail",
      "owner_type": "event",
      "owner_code": "evt_024",
      "asset_role": "story_scene",
      "scene_index": 1,
      "variant": "thumbnail",
      "relative_path": "assets/story_images_thumbs/024 사라의 죽음과 막벨라 굴/scene_01.jpg",
      "source_relative_path": "assets/story_images/024 사라의 죽음과 막벨라 굴/scene_01.png",
      "mime_type": "image/jpeg",
      "generator": "tools/generate_runtime_thumbnails.py",
      "metadata": {
        "event_title": "사라의 죽음과 막벨라 굴"
      }
    }
  ]
}
```

### `natural_key`가 중요한 이유

이 키는 재실행 시 같은 레코드를 덮어쓰기 위한 기준이다.

예:

- `person:moses:avatar:none:thumbnail`
- `event:evt_024:story_scene:1:thumbnail`

같은 이미지 논리 단위를 계속 같은 키로 바라보므로 중복 없이 upsert 할 수 있다.

## 4. 실제 실행 명령

### 아바타 생성

```bash
python3 tools/generate_avatars_vertex.py
```

### 스토리 장면 생성

```bash
python3 tools/generate_event_story_images_vertex.py
```

### 썸네일 생성

```bash
python3 tools/generate_runtime_thumbnails.py
```

### merge SQL 생성

```bash
python3 tools/build_generated_media_merge_sql.py
```

### Python 문법 점검

```bash
python3 -m py_compile \
  tools/build_generated_media_merge_sql.py \
  tools/generate_avatars_vertex.py \
  tools/generate_runtime_thumbnails.py \
  tools/generate_event_story_images_vertex.py
```

### Flutter / Dart 점검

```bash
dart analyze
flutter test
```

## Thumbnail asset 전략 기준 정리

현재 프로젝트는 용량 문제 때문에 가능한 한 `thumbnail을 asset에 포함해서 쓰는 방향`을 우선한다.

이 구조는 그 방향과 잘 맞는다.

### 권장 원칙

- 앱에서 실제로 보여주는 이미지는 thumbnail 기준으로 본다.
- `persons.avatar_thumb_url`에는 `assets/avatars_thumbs/...` 경로를 넣는다.
- `event_scene_generated_assets.thumbnail_path`에는 `assets/story_images_thumbs/...` 경로를 넣는다.
- `events.thumb_url`에는 이벤트 대표 썸네일 asset 경로를 넣는다.
- 원본 이미지는 생성/보관/재처리 용도로 유지하고, 앱 기본 렌더링에서는 우선순위를 낮춘다.

### 이 방식의 장점

- 네트워크 의존 없이 즉시 로딩 가능
- 앱에서 표시할 이미지 용량을 통제하기 쉬움
- DB는 실제 파일 저장소가 아니라 “경로 인덱스”로만 동작하므로 구조가 단순함
- 나중에 필요하면 원본만 따로 보관/이관할 수 있음

## Flutter 앱 소비 방식

Flutter는 다음 순서로 이미지를 찾는 구조가 안전하다.

### 아바타

1. `avatar_thumb_url` 우선 사용
2. 없으면 기존 `avatar_url -> avatars_thumbs` 치환 fallback
3. 그것도 없으면 placeholder 사용

### 스토리 장면 이미지

1. `event_scene_generated_assets.thumbnail_path` 우선 사용
2. DB에 아직 데이터가 없으면 기존 `AssetManifest` 기반 폴더 탐색 fallback
3. 그것도 없으면 장면 UI를 숨기거나 빈 상태 유지

이 fallback 구조 덕분에:

- DB migration을 먼저 배포해도 앱이 바로 깨지지 않고
- 생성/백필이 끝나면 점진적으로 새 구조로 전환된다

## 요약

이번 구조의 목적은 3가지다.

1. 생성된 이미지를 DB가 안정적으로 식별하게 만들기
2. 생성 자동화를 재실행 가능하게 만들기
3. 앱 전환을 안전하게 만들기

현재 thumbnail asset 우선 전략과도 잘 맞으며, DB는 이미지 저장소가 아니라 “무슨 이미지를 써야 하는지 알려주는 인덱스” 역할로 이해하면 된다.
