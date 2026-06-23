# 콘텐츠 추가/수정 → 앱 반영 워크플로우

> 현재 운영 기준: 웹 제안/승인 화면은 배포하지 않는다. 새 이야기 요청이 들어오면
> 운영자가 로컬에서 `assets/200_stories/*.json`, 이미지, seed SQL, 앱 번들을 직접
> 갱신한다.

문서 계층: 이 문서는 [develop-flow.md](develop-flow.md)를 보조하는 콘텐츠 운영
하위 문서다. real 공개 타이밍과 배포 판단은 develop-flow에서 결정하고, 여기서는
JSON/이미지/seed 작업 순서를 다룬다.

## 0. 현재 코드 기준 한 줄 요약

| 변경 종류 | 기준 소스 | 적용 타이밍 |
|----------|-----------|-------------|
| 이야기 메타 | `assets/200_stories/*.json` → `supabase/200_stories/*.sql` | DB seed 적용 즉시 |
| 이야기 위치 | `assets/landmarks/event_region_mapping.json` | `seed-stories-characters` 전에 필수 |
| 인물 메타 | `tools/seed/character_meta.json` 생성물 | `make build-character-meta` / `make seed-characters` |
| 장면 원본 이미지 | `assets/story_images/<title>/scene_N.png` | 앱 번들 전 |
| 런타임 썸네일 | `assets/story_images_thumbs/<short_dir>/scene_N.jpg` + `index.json` | `make thumbnails` |
| 장면 Storage fallback | `events.scene_image_paths` | 현재 수동 JSON seed 흐름에서는 자동 생성/업로드 없음 |
| 앱 asset 목록 | `pubspec.yaml` | `make update-pubspec-assets` |
| 퀴즈 | `assets/quizzes/*.json` → `supabase/quizzes/quizzes_seed.sql` | `apply-seeds-quizzes` |

중요한 현재 사실:

- `title`에는 `001` 같은 번호 prefix를 붙이지 않는다. 화면에 보일 순수 제목만 쓴다.
- 이야기 순서는 `story_index`가 결정한다.
- 인물 필드는 `characters`를 쓴다. 예전 문서의 `persons`는 현재 JSON 포맷이 아니다.
- canonical seed는 `events.scene_image_paths`를 채우지 않는다.
- `SceneAssetLoader`는 장면 이미지를 로컬 번들에서 먼저 찾고, 호출부가
  `publicUrlFor`를 넘긴 경우에만 `scene_image_paths` Storage fallback을 쓴다.
- `make apply-seeds-stories-characters`는 Storage에 장면 이미지나 썸네일을 업로드하지
  않는다. `make upload-character-avatars`도 캐릭터 아바타 전용이다.
- 중간 삽입으로 기존 이야기들의 `story_index`가 밀리면 real DB에는 seed-only로
  적용하지 않는다. 기존 `events.id`를 보존하는 DB shift+insert가 먼저 필요하다.

## 1. 신규 이야기 1건 추가

### 1.1 작업 전 동기화

로컬 JSON이 기준이다. 다만 real/dev DB에서 직접 수정한 내용이 있을 수 있으면
먼저 역추출한다. 이 명령은 로컬 파일을 덮어쓸 수 있으므로, 작업 중 변경이 있으면
먼저 diff를 확인한다.

```bash
git status --short assets/200_stories
make export-stories-json ENV=dev
```

real DB를 기준으로 복원해야 할 때만:

```bash
make export-stories-json ENV=real
```

현재 운영에서 웹 제안 화면은 쓰지 않으므로, 평소에는 저장소의
`assets/200_stories/*.json`이 기준 소스라고 보면 된다.

### 1.2 JSON 추가

해당 시대 파일에 새 객체를 추가한다.

예:

```json
{
  "title": "새 이야기 제목",
  "era": "era_divided_kingdom",
  "characters": ["elijah", "ahab"],
  "place_name": "갈멜 산",
  "lat": 32.731,
  "lng": 35.049,
  "summary": "한 문장 요약",
  "background_context": "시대 배경과 이 사건의 의미를 1~2문장으로 적는다.",
  "bible_ref": [{"book": "왕상", "from": "18:20", "to": "18:40"}],
  "start_year": -860,
  "end_year": -860,
  "time_precision": "approx",
  "story_index": 99,
  "unit_code": "div_elijah",
  "unit_title": "엘리야와 북이스라엘",
  "unit_order": 3,
  "story_scenes": [
    "장면 1 설명",
    "장면 2 설명",
    "장면 3 설명",
    "장면 4 설명"
  ],
  "scene_captions": [
    "사용자에게 보일 장면 1 설명",
    "사용자에게 보일 장면 2 설명",
    "사용자에게 보일 장면 3 설명",
    "사용자에게 보일 장면 4 설명"
  ],
  "scene_characters": [
    ["elijah"],
    ["ahab"],
    ["elijah"],
    []
  ]
}
```

작성 규칙:

- `story_index`는 같은 era 안에서 중복되면 안 된다.
- 중간에 끼워 넣으면 뒤 이야기들의 `story_index`와
  `assets/landmarks/event_region_mapping.json`도 같이 조정해야 한다.
- 단, real에 이미 공개된 시대의 중간 삽입은 로컬 JSON 재번호 + seed apply만으로
  처리하지 않는다. generated seed는 `(era_id, story_index)`를 UPSERT 키로 쓰므로,
  기존 row id가 다른 이야기 내용으로 덮일 수 있다.
- `story_scenes`, `scene_captions`, `scene_characters` 길이는 맞춘다.
- `characters`와 `scene_characters`에는 인물 code를 쓴다.
- 새 인물 code는 JSON에 먼저 넣어도 된다. 이후 `build-character-meta`가 meta에 반영한다.

### 1.3 위치 매핑 추가

`make seed-stories-characters`는 모든 이벤트에 `landmark_id`가 필요하다. 새 이야기의
`(era, story_index)`에 대응하는 row를 `assets/landmarks/event_region_mapping.json`에
추가한다.

```json
{
  "story_index": 99,
  "title": "새 이야기 제목",
  "era": "era_divided_kingdom",
  "place_name": "갈멜 산",
  "region_code": "rgn_div_north_israel",
  "landmark_code": "lm_div_mt_carmel"
}
```

`landmark_code`는 `assets/landmarks/landmarks.json`에 존재해야 한다. 새 landmark가
필요하면 `landmarks.json`도 추가하고 `make seed-landmarks`를 실행한다.

### 1.4 인물 meta / seed 생성

```bash
make build-character-meta
make seed-stories-characters
```

확인할 것:

- `tools/seed/character_meta.json`에 신규 인물이 들어갔는지
- 신규 인물의 `name`, `tagline`, `prompt`, `is_active_default`가 의도와 맞는지
- `supabase/200_stories/characters_seed.sql`과
  `supabase/200_stories/200_stories_seed_part_*.sql` diff가 의도한 범위인지

신규 인물의 prompt가 마음에 들지 않으면
`tools/seed/build_character_meta_json.py`의 override/hint를 보강한 뒤 다시 실행한다.

### 1.5 장면 이미지와 썸네일 생성

```bash
make generate-avatars      # 신규 인물이 있을 때
make generate-story-images # 새 이야기 장면 이미지 생성
make thumbnails
make update-pubspec-assets
```

동작:

- 기존 아바타/장면 PNG가 있으면 skip한다.
- 마음에 들지 않는 장면은 해당 `assets/story_images/<title>/scene_N.png`를 지우고
  `make generate-story-images`를 다시 실행한다.
- `make thumbnails`는 앱 런타임용 짧은 디렉토리
  `assets/story_images_thumbs/<era_slug>_<story_index>/`와 `index.json`을 만든다.
- `make update-pubspec-assets`를 빼먹으면 새 썸네일이 앱 번들에 포함되지 않는다.

### 1.6 퀴즈를 같이 추가할 때

퀴즈 파일은 `assets/quizzes/<era_code>_n<story_index:03d>.json` 형식이다.

현재 Makefile의 `seed-quizzes`는 `supabase/quizzes/db_events.json`을 기준 이벤트
목록으로 사용한다. 따라서 신규 이야기 퀴즈를 추가하면 이 snapshot에도 아래 형태의
항목을 같이 추가해야 한다.

```json
{
  "era_code": "era_divided_kingdom",
  "story_index": 99,
  "title": "새 이야기 제목"
}
```

그 다음:

```bash
make seed-quizzes
```

주의:

- snapshot에 신규 이야기가 없으면 `orphan quizzes` 에러가 난다.
- 이 구조는 임시 운영상 제약이다. 나중에 seed SQL과 DB snapshot이 완전히 맞으면
  `seed-quizzes`가 `200_stories_seed.sql`을 직접 기준으로 쓰도록 정리할 수 있다.

### 1.7 dev 적용과 검증

```bash
make apply-seeds-stories-characters ENV=dev
make apply-seeds-landmarks ENV=dev       # landmark가 바뀌었으면
make apply-seeds-quizzes ENV=dev         # 퀴즈가 있으면
make upload-character-avatars ENV=dev    # 신규 인물 아바타가 있으면
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
scripts/run_dev.sh
```

검증:

- 지도에서 새 이야기가 올바른 region/landmark에 보이는지
- 시대/방법, 인물, 이야기 탭에서 순서가 자연스러운지
- 상세 화면에서 장면 이미지와 caption이 보이는지
- 신규 인물 카드, 아바타, tagline이 맞는지
- 퀴즈를 추가했다면 퀴즈 진입/정답/해설이 맞는지

## 2. real 배포

### 2.1 가장 중요한 주의점

신규 이야기를 real DB에 먼저 공개하면 즉시 사용자에게 보인다. 하지만 새 장면 이미지는
앱 번들에 들어가는 구조라서, 아직 새 앱을 설치하지 않은 사용자는 새 썸네일을 갖고
있지 않다.

현재 canonical seed는 `events.scene_image_paths`를 비워 둔다. 따라서 real DB를 먼저
공개하면 구버전 앱 사용자는 새 이야기를 보되 장면 이미지는 비어 보일 수 있다.

중간 삽입이면 이미지보다 먼저 `event_id` 보존을 확인한다. `events` seed는
`(era_id, story_index)` 기준으로 UPSERT하므로, 기존 5번 자리에 새 이야기를 넣고
뒤쪽 index를 모두 바꾼 SQL을 그대로 real에 적용하면 기존 5번 row의 id가 새 이야기
내용을 갖게 될 수 있다. 사용자 저장/읽기/퀴즈 기록은 `event_id`를 참조하므로,
운영 DB에서는 `insert_event_at_position(...)` RPC나 별도 patch로 기존 row를 먼저
shift+insert한 다음 seed와 로컬 JSON을 맞춘다.

### 2.2 기본 배포 순서

이미지 없는 노출을 줄이는 보수적 순서:

```bash
# 1. dev에서 검증 완료
scripts/run_dev.sh

# 2. real 앱 빌드 준비
scripts/run_real.sh
scripts/build_android_real.sh
scripts/build_ios_real.sh

# 3. Store 심사/출시 준비
# Play Console / App Store Connect 업로드

# 4. 출시 타이밍에 real DB 공개
make apply-seeds-stories-characters ENV=real
make apply-seeds-landmarks ENV=real       # landmark가 바뀌었으면
make apply-seeds-quizzes ENV=real         # 퀴즈가 있으면
make upload-character-avatars ENV=real    # 신규 인물 아바타가 있으면
scripts/run_real.sh
```

현실적으로 사용자가 모두 즉시 업데이트하지는 않는다. 이미지 빈 상태를 절대 피해야 하는
콘텐츠라면 2.3을 먼저 해결해야 한다.

### 2.3 구버전 앱에도 이미지를 보여야 할 때

필요한 구조:

1. 로컬에서 만든 장면 이미지를 public Supabase Storage에 업로드한다.
2. real DB의 해당 이벤트에 `events.scene_image_paths`를 채운다.
3. 구버전 앱은 Storage URL로 이미지를 본다.
4. 신버전 앱은 로컬 번들 이미지를 먼저 보므로 Storage 호출이 줄어든다.

현재 repo에는 이 작업을 자동화하는 로컬 Make target이 없다. 과거 웹 제안/승인
흐름은 이 역할을 했지만, 지금 웹을 배포하지 않는 운영에서는 표준 경로가 아니다.

`make upload-character-avatars ENV=real`은 `characters` 버킷만 다룬다. 이야기 장면
PNG/JPG 또는 `assets/story_images_thumbs`를 Storage에 올리고 `events.scene_image_paths`
를 채우는 target은 아직 없다.

또한 Storage fallback은 `SceneAssetLoader.loadForEvent(..., publicUrlFor: ...)`를
넘기는 화면에서만 동작한다. 상세 화면의 큰 장면 row는 이 경로를 쓰지만, 모든 작은
카드 썸네일까지 보장하려면 앱 호출부 패치를 함께 확인한다.

따라서 선택지는 둘이다.

- real 공개를 새 앱 출시 이후로 미룬다.
- 별도 도구를 만든다: `assets/story_images/<title>/scene_N.png`를 Storage에 업로드하고
  `events.scene_image_paths = ARRAY['bucket/path/scene_1.png', ...]`를 patch하는
  운영 스크립트/Make target.

수동 SQL/Storage 업로드로도 가능하지만, 경로 오타나 cleanup 타이밍 실수가 나기 쉬워
반복 운영에는 권장하지 않는다.

### 2.4 실수로 real에 먼저 공개했을 때

바로 draft로 숨긴다.

```sql
update public.events
set status = 'draft'
where title in ('새 이야기 제목');
```

앱은 `events_ordered` view를 읽고, 이 view는 `status='published'`만 노출한다.
fallback 준비 또는 앱 출시 타이밍이 되었을 때 다시 공개한다.

```sql
update public.events
set status = 'published'
where title in ('새 이야기 제목');
```

## 3. 기존 콘텐츠 수정

### 3.1 제목/요약/본문/좌표/장면 문구 수정

```bash
make seed-stories-characters
make apply-seeds-stories-characters ENV=dev
scripts/run_dev.sh
make apply-seeds-stories-characters ENV=real
```

장면 문구를 바꿔 새 이미지가 필요하면 해당 PNG를 지우고 이미지를 재생성한다.

```bash
make generate-story-images
make thumbnails
make update-pubspec-assets
```

이미지가 바뀌면 앱 재빌드와 Store 배포가 필요하다.

### 3.2 인물 노출만 바꾸기

DB에서 직접 토글할 수 있다.

```sql
update public.characters
set is_active = true
where code = 'goliath';
```

`make seed-characters`는 일반 false 기본값으로 기존 런타임 설정을 끄지 않지만,
명시 비활성 예외 코드는 seed에서 다시 false가 될 수 있으므로 diff를 확인한다.

## 4. 배포 전 체크리스트

- [ ] `assets/200_stories/*.json` title에 번호 prefix를 넣지 않았다.
- [ ] `characters`, `scene_characters` code가 맞다.
- [ ] `story_index`가 era 안에서 unique하다.
- [ ] `assets/landmarks/event_region_mapping.json`에 새 `(era, story_index)` 매핑이 있다.
- [ ] `landmark_code`가 `assets/landmarks/landmarks.json`에 존재한다.
- [ ] `make seed-stories-characters` 성공.
- [ ] 퀴즈가 있으면 `supabase/quizzes/db_events.json` snapshot도 갱신했고 `make seed-quizzes` 성공.
- [ ] `make thumbnails`와 `make update-pubspec-assets` 실행.
- [ ] `make check-pubspec-assets` 통과.
- [ ] `python3 tools/seed/verify_polygons_contain_events.py` 통과.
- [ ] `scripts/run_dev.sh`에서 새 이야기/이미지/퀴즈 확인.
- [ ] real DB 공개 타이밍을 앱 Store 배포 타이밍과 맞췄다.

## 5. 관련 문서

- [develop-flow.md](develop-flow.md) — dev/real 운영 흐름
- [MAKE_TARGETS.md](MAKE_TARGETS.md) — Make target별 입력/출력/원격 영향
- [DATA_PIPELINE.md](../DATA_PIPELINE.md) — seed/image 도구 상세
- [BACKEND.md](../BACKEND.md) — events/characters/storage schema
- [WORKFLOW_GUIDE.md](WORKFLOW_GUIDE.md) — 웹 제안/승인 기능의 역사적 설계 참고
