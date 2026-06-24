# 개발 / 배포 Flow

> dev 에서 안전하게 개발하고, real 에 배포할 때 무엇을 어디까지 적용해야 하는지
> 정리한 운영 문서다. Supabase 신규 환경 구축 자체는
> [DB_SETUP.md](DB_SETUP.md)를 먼저 본다.

문서 계층: 이 문서가 개발/배포의 메인 문서다. 새 이야기/퀴즈/이미지 세부 절차는
[CONTENT_UPDATE.md](CONTENT_UPDATE.md), Make target 내부 동작과 원격 영향은
[MAKE_TARGETS.md](MAKE_TARGETS.md)를 본다.

## 0. 결론부터

앞으로 앱 실행과 빌드는 아래 스크립트만 쓰면 된다.

```bash
scripts/run_dev.sh
scripts/run_real.sh
scripts/build_android_dev.sh
scripts/build_android_real.sh
scripts/build_ios_dev.sh
scripts/build_ios_real.sh
```

이 스크립트들은 실행 전에 `.env`의 선택 환경 값을 검증하고, Flutter 에
`--dart-define`으로 주입한다. 앱은 `.env` 파일을 직접 읽지 않는다.

새 컴퓨터나 팀원 온보딩 시 필요한 로컬 파일 기준은
[LOCAL_ENV_FILES.md](LOCAL_ENV_FILES.md)를 먼저 본다. 앱 실행/빌드에는 `.env`,
DB/Storage 운영 명령에는 `.env.ops`, Edge Function secret 갱신에는
`.env.supabase.secrets`가 필요하지만, 세 실파일은 모두 git에 올리지 않는다.

DB / Storage 운영은 Makefile 을 쓴다.
각 target이 로컬 파일만 바꾸는지, 원격 DB/Storage를 바꾸는지는
[MAKE_TARGETS.md](MAKE_TARGETS.md)에 따로 정리했다.

```bash
# dev reset / seed / storage
make db-init
make apply-seeds
make upload-character-avatars

# real schema/RLS/RPC 변경은 reset 이 아니라 patch 로 적용
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql

# real 기준 콘텐츠/Storage 변경만 명시적으로 적용
make apply-seeds ENV=real
make upload-character-avatars ENV=real
```

가장 중요한 원칙:

- 평소 개발은 dev 에서 한다.
- real 에는 검증된 변경만 적용한다.
- real 은 이제 보존해야 하는 운영 DB 로 취급한다.
- `make db-init ENV=real`은 기본 차단되어 있으며 운영 배포에 쓰지 않는다.
- DB 구조 변경은 `db_init.sql`에 최종 상태를 반영하고,
  `supabase/patches/*.sql`의 idempotent patch 로 real 에 적용한다.

상황별 선택표:

| 상황 | real DB 변경 | release sync | 앱 빌드 | 표준 명령 |
|------|-------------|--------------|---------|-----------|
| 앱 기능/UI만 변경 | 없음 | 필요 없음 | 필요 | `flutter analyze` → `flutter test` → `scripts/build_*_real.sh` |
| 앱 코드가 새 column/RPC/RLS에 의존 | patch 필요 | 보통 필요 없음 | 필요 | `make apply-patch ENV=real PATCH=...` 후 real smoke/build |
| 기존 seed/콘텐츠 수정(새 이야기 추가/삭제 아님) | seed apply | 필요한 경우만 | 보통 필요 | `make seed-*` → `make apply-seeds-* ENV=real` |
| 이야기 추가/삭제 proposal 승인 후 배포 | DB는 이미 승인으로 변경됨 | 필요 | 필요 | `make release-sync-stories ENV=real` → 검증 → build |
| 신규/복구 Supabase bootstrap | reset | 초기 자산 생성 | 필요 | `CONFIRM_REAL_DB_INIT=1 make db-init ENV=real` |

`release-sync-stories`는 이야기/퀴즈/랜드마크/이미지 번들을 운영 DB 상태로 되돌리는
콘텐츠 배포 명령이다. 일반 UI 수정이나 단순 DB schema patch를 배포할 때는 실행하지
않는다. 반대로 이야기 추가/삭제 승인이 real DB에 쌓여 있으면, 앱 배포 전
`release-sync-stories`를 실행해 로컬 번들 JSON과 썸네일을 최신 DB 상태로 맞춘다.

## 1. 환경 분리 구조

| 구분 | dev | real |
|------|-----|------|
| Supabase ref | `cvnutbizsgeycdjcbled` | `zmcffwcfmyhdykdhxhgy` |
| 앱 실행 ENV | `dev` | `real` 또는 `prod` |
| Makefile 기본값 | 기본 | `ENV=real` 명시 필요 |
| 운영 env suffix | `DEV` | `PROD` |
| DB URL 변수 | `SUPABASE_DB_URL_DEV` | `SUPABASE_DB_URL_PROD` |
| service role 변수 | `SUPABASE_SERVICE_ROLE_KEY_DEV` | `SUPABASE_SERVICE_ROLE_KEY_PROD` |

왜 real 의 운영 suffix 가 `PROD`인가:

- Flutter/Dart 쪽은 `ENV=real`과 `ENV=prod`를 둘 다 허용한다.
- 로컬 운영 도구는 기존 관례상 운영값을 `*_PROD`로 둔다.
- 그래서 `ENV=real`은 Makefile 내부에서 `ops=prod`로 매핑된다.

## 2. 앱 실행 / 빌드 Flow

### 2.1 dev 실행

개발 중에는 이것만 쓴다.

```bash
scripts/run_dev.sh
```

특정 디바이스:

```bash
scripts/run_dev.sh -d chrome
scripts/run_dev.sh -d ios
scripts/run_dev.sh -d emulator-5554
```

동작:

1. `.env`에서 `SUPABASE_URL_DEV`, `SUPABASE_ANON_KEY_DEV`를 읽는다.
2. URL 과 anon key 안의 project ref 가 dev ref 와 맞는지 검사한다.
3. `flutter clean` 실행.
4. `flutter pub get` 실행.
5. `flutter run --no-pub --dart-define=ENV=dev ...` 실행.

### 2.2 real 실행

real 동작을 직접 확인할 때만 쓴다.

```bash
scripts/run_real.sh
```

특정 디바이스:

```bash
scripts/run_real.sh -d ios
scripts/run_real.sh -d chrome
```

동작은 dev 와 같지만, `.env`의 `SUPABASE_URL_PROD`,
`SUPABASE_ANON_KEY_PROD`를 읽고 real ref 를 검사한다.

### 2.3 dev 빌드

dev Supabase 를 바라보는 설치 파일이 필요할 때 쓴다.

```bash
scripts/build_android_dev.sh
scripts/build_ios_dev.sh
```

용도:

- 내부 테스트
- 실기기 smoke test
- real 에 보내기 전에 빌드 자체가 깨지지 않는지 확인

### 2.4 real 빌드

배포 후보 빌드다.

```bash
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

빌드 번호를 올릴 때:

```bash
scripts/build_android_real.sh --build-number=23
scripts/build_ios_real.sh --build-number=23
```

또는 `pubspec.yaml`의 `version: 1.0.0+23`을 올린 뒤 빌드한다.

real 빌드 전 권장 검증:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
```

## 3. 평소 개발 Flow

### 3.1 일반 앱 코드만 바꾸는 경우

예: UI, Riverpod state, repository 쿼리, 로그인 UI, 푸시 수신 UI.

전제:

- `db_init.sql`, `supabase/patches/`, `supabase/functions/`를 바꾸지 않는다.
- 새 table/column/RPC/RLS 정책이 필요하지 않다.
- `assets/events`, `assets/landmarks`, `assets/story_images*`를
  운영 DB 상태와 다시 맞출 필요가 없다.

순서:

1. dev 로 실행한다.
2. 코드를 수정한다.
3. 관련 테스트를 추가/수정한다.
4. dev 로 확인한다.
5. 분석/테스트를 돌린다.
6. real 데이터와 연결했을 때만 드러나는 문제가 있으면 real 로 한 번 smoke test 한다.
7. build number를 올리고 real build script 로 배포 후보를 만든다.

명령:

```bash
scripts/run_dev.sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test

# 필요할 때만 real smoke
scripts/run_real.sh

# 배포 후보
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

이 경우 실행하지 않는 것:

- `make db-init ENV=real`
- `make apply-patch ENV=real ...`
- `make release-sync-stories ENV=real`
- `make apply-seeds ENV=real`

단, repository 쿼리가 새 column을 읽거나 앱이 새 RPC를 호출하도록 바뀌면 더 이상
"앱 코드만" 변경이 아니다. 그때는 §3.3의 DB patch 동반 흐름으로 간다. 앱 코드가
기존 DB와도 동작하고 새 DB와도 동작하도록 만들 수 있으면, 먼저 patch를 적용하고
그 다음 앱을 배포하는 순서가 가장 안전하다.

### 3.2 공개 콘텐츠 / 이야기 데이터 Flow

공개 콘텐츠는 앱 번들, Supabase DB, Supabase Storage가 동시에 얽힌다. 특히 새
이야기는 `story_index`와 이미지 fallback 때문에 일반 seed 수정처럼 처리하지 않는다.

#### 3.2.0 초기 데이터 세팅

초기 데이터 세팅은 “사람이 관리하는 canonical 파일”에서 “로컬 SQL/asset 산출물”을 만들고, 그 산출물을 Supabase DB와 Storage에 적용하는 흐름이다. 이 절은 아직 운영 사용자가 없는 real DB를 새로 만들거나, dev DB를 같은 기준으로 다시 세팅할 때 읽는다. 이미 운영 중인 DB에서는 `db-init`으로 전체 초기화하지 않고, 필요한 patch와 release sync 절차를 사용한다.

전체 명령은 아래 순서다.

```bash
make seed-all \
  && make thumbnails \
  && make update-pubspec-assets \
  && make check-pubspec-assets \
  && CONFIRM_REAL_DB_INIT=1 make db-init ENV=real \
  && make apply-seeds ENV=real \
  && make upload-character-avatars ENV=real \
  && make upload-story-image-sources ENV=real
```

핵심 원칙은 세 가지다.

| 구분 | 위치 | 의미 |
|------|------|------|
| 사람이 관리하는 원본 | `assets/events/*.json`, `assets/landmarks/landmarks.json`, `assets/bible/*.txt`, `assets/story_images/`, `assets/avatars/` | 초기 세팅의 기준이다. 이 파일들이 틀리면 뒤의 SQL/asset도 그대로 틀어진다. |
| 로컬 생성 산출물 | `supabase/events/`, `supabase/quizzes/`, `supabase/seeds/`, `assets/story_images_thumbs/`, `assets/avatars_thumbs/` | Make target이 다시 만드는 결과물이다. 예를 들어 `supabase/events/`는 지워도 `make seed-all`로 다시 만들 수 있다. |
| 원격 적용 결과 | Supabase DB tables, Supabase Storage buckets | `make db-init`, `make apply-seeds`, `make upload-character-avatars`, `make upload-story-image-sources`가 실제 원격 상태를 바꾼다. |

주의할 점은 `make seed-all`이 현재 로컬 `assets/events/*.json`만 믿는다는 것이다. `assets/events`가 비어 있거나 일부 파일만 남은 상태에서 실행하면 그 일부 상태를 기준으로 SQL이 만들어진다. 운영 DB의 active 상태를 기준으로 복원해야 하는 경우에는 먼저 `make export-stories-json ENV=real`로 DB snapshot을 다시 받아 둔다.

##### 3.2.0.1 `make seed-all` — 로컬 seed SQL 만들기

`make seed-all`은 DB나 Storage에 적용하지 않는다. 입력 파일을 읽어 로컬 SQL과 검수 리포트만 다시 만든다.

| 내부 단계 | 입력 | 출력 | 다음에 쓰이는 곳 |
|-----------|------|------|------------------|
| `seed-bible-verses` | `assets/bible/*.txt` | `supabase/seeds/krv_bible_verses.sql`, `supabase/seeds/krv_bible_verses_part_01.sql` ~ `part_10.sql` | `make apply-seeds`가 `bible_verses` 테이블에 넣는다. |
| `build-character-meta` | `assets/events/*.json`의 `characters`, `scene_characters` | `tools/seed/character_meta.json` | 인물 seed, events 인물 코드 검증, 아바타 생성 후보에 쓰인다. |
| `seed-stories` | `assets/events/*.json`, `tools/seed/character_meta.json` | `supabase/events/events_seed.sql`, `supabase/events/events_seed_part_*.sql`, `supabase/events/events_report.json`, `supabase/events/events_normalized.json` | `make apply-seeds`가 `events` 테이블에 넣는다. |
| `seed-characters` | `tools/seed/character_meta.json`, `assets/events/*.json` | `supabase/events/characters_seed.sql` | `make apply-seeds`가 `characters` 테이블에 넣는다. |
| `seed-quizzes` | `assets/events/*.json` 안의 `quiz_questions` | `supabase/quizzes/quizzes_seed.sql`, `supabase/quizzes/quizzes_report.json` | `make apply-seeds`가 `quiz_questions` 테이블에 넣는다. |
| `seed-landmarks` | `assets/landmarks/landmarks.json` | `supabase/events/landmarks_seed.sql` | `make apply-seeds`가 `landmarks` 테이블에 넣고, `events.landmark_id` 연결의 기준이 된다. |

흐름만 짧게 보면 이렇다.

```text
assets/bible/*.txt
  -> supabase/seeds/krv_bible_verses_part_*.sql
  -> DB bible_verses

assets/landmarks/landmarks.json
  -> supabase/events/landmarks_seed.sql
  -> DB landmarks

assets/events/*.json
  -> tools/seed/character_meta.json
  -> supabase/events/characters_seed.sql
  -> DB characters

assets/events/*.json + tools/seed/character_meta.json
  -> supabase/events/events_seed_part_*.sql
  -> DB events

assets/events/*.json 안의 quiz_questions
  -> supabase/quizzes/quizzes_seed.sql
  -> DB quiz_questions
```

예를 들어 `assets/events/era_primeval.json`의 한 event row는 이런 구조다.

```json
{
  "title": "창조: 7일과 안식",
  "era": "era_primeval",
  "story_index": 1,
  "characters": ["god"],
  "landmark_code": "lm_prim_unknown",
  "background_context": "창세기 원역사는 창조부터 바벨 사건까지를 다루는 초반 이야기입니다.",
  "summary": "하나님이 말씀으로 세상을 창조하시고 안식으로 완성하신다.",
  "bible_ref": [{ "book": "창", "from": "1:1", "to": "2:3" }],
  "unit_code": "primeval_creation_mission",
  "unit_title": "창조와 사람의 사명",
  "unit_order": 1,
  "story_scenes": ["완전한 어둠과 혼돈 위에 부드러운 빛이 수면 위를 덮는다"],
  "scene_captions": ["완전한 어둠과 혼돈 위에 부드러운 빛이 수면 위를 덮는다"],
  "scene_characters": [["god"]],
  "quiz_questions": [
    {
      "type": "fact",
      "display_order": 0,
      "question": "하나님이 빛을 만드신 것은 몇째 날입니까?",
      "choices": ["첫째 날", "넷째 날", "여섯째 날"],
      "answer_index": 0,
      "explanation": "창 1:3-5 — '빛이 있으라 하시매 ... 첫째 날이니라'"
    }
  ]
}
```

이 한 row는 `events_seed_part_*.sql`에서는 `events` 한 행이 되고, `characters_seed.sql`에서는 `god` 같은 인물 코드가 `characters` 후보가 되며, `quizzes_seed.sql`에서는 이 event에 연결될 `quiz_questions` 행이 된다. `landmark_code` 자체가 `events`에 문자열로 저장되는 것은 아니고, seed SQL 적용 시 `landmarks.code = 'lm_prim_unknown'`을 찾아 그 id를 `events.landmark_id`에 넣는다.

`supabase/events/events_report.json`은 생성 결과 요약과 경고를 보는 파일이고, `supabase/events/events_normalized.json`은 SQL에 들어가기 직전의 정규화된 events snapshot이다. 둘 다 사람이 직접 편집하는 원본은 아니며, 이상한 diff가 생겼을 때 원인 확인용으로 본다.

##### 3.2.0.2 `make thumbnails` — 앱 번들용 이미지 다시 만들기

`make seed-all`은 썸네일을 만들지 않는다. 앱에 포함될 이미지까지 현재 `assets/events/*.json`과 맞추려면 다음으로 `make thumbnails`를 실행한다.

| 입력 | 출력 | 동작 |
|------|------|------|
| `assets/events/*.json` | `assets/story_images_thumbs/index.json` | 각 이야기 title, era, story_index와 짧은 썸네일 디렉토리의 매핑을 만든다. |
| `assets/story_images/<title>/scene_*.png` | `assets/story_images_thumbs/<era_slug>_<story_index>/scene_*.jpg` | current events에 있는 이야기의 원본 PNG를 앱 번들용 JPG 썸네일로 만든다. |
| `assets/avatars/*.png` | `assets/avatars_thumbs/*.png` | 인물 아바타 썸네일을 만든다. |

story thumbnail은 매번 clean rebuild다. 먼저 current `assets/events/*.json`에 필요한 원본 PNG가 모두 있는지 확인하고, 통과하면 `assets/story_images_thumbs/`의 story 하위 디렉토리를 지운 뒤 현재 `era + story_index` 기준으로 다시 만든다. 그래서 중간 삽입이나 삭제로 뒤쪽 story_index가 바뀌어도 예전 썸네일 디렉토리가 앱 번들에 남아 잘못 매칭되는 일을 막는다.

만약 원본 PNG가 없다면 `make thumbnails`는 중단된다. 새 컴퓨터나 원본 캐시가 비어 있는 환경에서는 먼저 `make ensure-story-image-sources ENV=real`로 private source archive에서 원본을 내려받는다.

##### 3.2.0.3 `make update-pubspec-assets`와 `make check-pubspec-assets`

썸네일을 만든 뒤에는 Flutter가 그 파일들을 번들 asset으로 인식하도록 `pubspec.yaml`을 갱신하고 검증한다.

| 명령 | 입력 | 출력/검증 |
|------|------|-----------|
| `make update-pubspec-assets` | `assets/story_images_thumbs/`, `assets/avatars_thumbs/`, 기타 asset 디렉토리 | `pubspec.yaml`의 `flutter.assets` 목록을 현재 파일 상태에 맞게 다시 쓴다. |
| `make check-pubspec-assets` | `pubspec.yaml`, 실제 asset 파일 | 등록된 asset이 실제로 존재하는지, 필요한 asset이 빠지지 않았는지 확인한다. |

이 두 명령도 DB나 Storage를 바꾸지 않는다. 로컬 앱 번들 목록만 정리한다.

##### 3.2.0.4 `CONFIRM_REAL_DB_INIT=1 make db-init ENV=real` — real DB 스키마 초기화

이 명령은 real Supabase DB를 초기 상태로 만든다. 아직 운영 중이 아닌 DB를 새로 만들거나 완전 복구할 때만 사용한다.

| 입력 | 원격 출력 |
|------|-----------|
| `db_init.sql`, Supabase real 접속 환경변수 | 테이블, view, function/RPC, RLS, grant, Storage bucket 정의, 기본 era 데이터 |

`db-init`은 스키마를 다시 세팅하는 강한 명령이다. 운영 사용자가 있는 DB에서는 사용자 진행도, 제안 이력, 저장 이벤트 같은 데이터를 잃을 수 있으므로 쓰지 않는다. 운영 중 스키마 변경은 `supabase/patches/*.sql`과 `make apply-patch ENV=real PATCH=<file>`로 처리한다.

Storage 쪽에서는 `characters`, `proposal-scenes`, `proposal-characters` 같은 app-owned bucket을 초기화 대상으로 삼지만, release builder용 private 원본 archive인 `story-image-sources`는 purge 대상이 아니다. 즉 `db-init`을 해도 1~2GB 원본 PNG archive는 보존된다.

##### 3.2.0.5 `make apply-seeds ENV=real`와 `make upload-character-avatars ENV=real`

`make apply-seeds`는 `make seed-all`이 만든 SQL을 실제 DB 테이블에 적용한다. Storage에는 파일을 올리지 않는다.

| 적용 순서 | 입력 SQL | DB 대상 | 동작 |
|-----------|----------|---------|------|
| 1 | `supabase/seeds/krv_bible_verses_part_*.sql` | `bible_verses` | KRV 성경 본문을 넣는다. 보통 `db-init` 직후 1회 실행한다. |
| 2 | `supabase/events/landmarks_seed.sql` | `landmarks` | region과 point landmark를 upsert한다. `events.landmark_id`가 참조하므로 events보다 먼저 들어간다. |
| 3 | `supabase/events/characters_seed.sql` | `characters` | 인물 이름, tagline, 활성 기본값, avatar path를 upsert한다. |
| 4 | `supabase/events/events_seed_part_*.sql` | `events` | 이야기 제목, 요약, 배경 지식, 장면, 캡션, 인물 코드, 본문 범위, 시간 구간, `landmark_id`를 upsert한다. `events_seed_part_01.sql`에는 current JSON에 없는 active event 정리도 포함된다. |
| 5 | `supabase/quizzes/quizzes_seed.sql` | `quiz_questions` | 각 event의 기존 quiz row를 지운 뒤 `assets/events/*.json` 안의 `quiz_questions`를 다시 insert한다. |

`make upload-character-avatars ENV=real`은 DB seed가 아니라 Storage 업로드다. 입력은 `assets/avatars/*.png`이고, 출력은 Supabase Storage `characters/{code}.png`와 DB `characters.avatar_storage_path` 갱신이다. 이 target은 업로드 전에 `characters` bucket을 먼저 비우고 현재 로컬 아바타를 다시 올린다.

##### 3.2.0.6 `make upload-story-image-sources ENV=real` — 원본 PNG archive 갱신

`story-image-sources`는 앱이 직접 읽는 public bucket이 아니다. release builder와 운영 도구가 쓰는 private 원본 PNG archive다. 목적은 새 컴퓨터나 CI에서도 `assets/story_images/` 원본 캐시를 복구하고, 썸네일을 언제든 다시 만들 수 있게 하는 것이다.

| 구분 | 내용 |
|------|------|
| 입력 | `assets/events/*.json`, `assets/story_images/<title>/scene_*.png`, 기존 remote manifest |
| 원격 출력 | `story-image-sources/story_images/<source_key>/scene_*.png`, `story-image-sources/_manifests/story_images_manifest.json` |
| 비교 기준 | `object_path`, `size`, `sha256` |
| dry-run | `make upload-story-image-sources-dry ENV=real` |

내부 동작은 다음 순서다.

| 단계 | 하는 일 | 예시 |
|------|---------|------|
| active story 목록 계산 | `assets/events/*.json`을 읽고 현재 앱에 살아 있어야 하는 이야기 title과 scene 원본 목록을 만든다. | `창조: 7일과 안식`이 current JSON에 있으면 `assets/story_images/창조: 7일과 안식/scene_01.png`가 active local source가 된다. |
| 로컬 원본 완전성 확인 | active story인데 `assets/story_images/<title>/` 원본이 하나도 없으면 publish를 거부한다. | 원본이 빠진 상태로 manifest를 올리면 다음 사람이 복구할 수 없으므로 중단한다. |
| remote manifest 읽기 | `_manifests/story_images_manifest.json`에서 이전 release의 object 목록, size, sha256을 읽는다. | manifest가 없으면 remote가 비어 있다고 보고, 로컬 원본 전체를 최초 seed 대상으로 본다. |
| upload 계획 계산 | old manifest에는 없고 active local set에는 있는 object를 upload 대상으로 잡는다. 같은 object_path인데 size/sha256이 다르면 upsert 대상으로 잡는다. 같으면 skip한다. | 새 이야기가 추가되면 그 story의 `scene_*.png`가 upload에 잡힌다. 이미지 파일을 다시 뽑아 내용이 바뀌면 같은 path라도 upsert된다. |
| stale 삭제 계획 계산 | old manifest에는 있지만 current active local set에는 없는 object를 delete_stale 대상으로 잡는다. | 삭제 승인된 이야기가 current `assets/events`에서 빠졌다면 이전 manifest에 있던 그 이야기 원본 object를 삭제한다. |
| 원격 반영 | upload/upsert를 실행하고, delete_stale을 삭제한 뒤, 마지막에 current active manifest를 다시 올린다. | 다음 release builder는 새 manifest를 기준으로 missing/changed 원본만 내려받는다. |

원격 object path는 한글 title을 그대로 쓰지 않고 `story_images/<source_key>/scene_*.png` 형태의 ASCII key를 쓴다. `<source_key>`는 NFC 정규화한 `source_dir`의 SHA-256 앞 16자리이므로 같은 `source_dir`에서는 재실행해도 같고, title/source_dir이 바뀌면 새 key가 된다. 실제 title/source_dir 매핑은 manifest에 남기 때문에 Supabase Storage key 제약이나 긴 한글 경로 문제를 피하면서도 어떤 object가 어떤 이야기 원본인지 추적할 수 있다.

중요한 삭제 규칙은 “bucket 전체를 훑어서 지우지 않는다”는 것이다. `delete_stale`은 이전 manifest에 있었고 현재 active manifest에는 없는 object만 대상으로 한다. manifest에 기록되지 않은 수동 object는 이 target이 삭제하지 않는다.

원본이 없는 컴퓨터에서 시작할 때는 push가 아니라 pull부터 한다.

```bash
make ensure-story-image-sources ENV=real
make thumbnails
make update-pubspec-assets
make check-pubspec-assets
```

`ensure-story-image-sources`는 remote manifest의 `size`/`sha256`과 로컬 `assets/story_images/`를 비교해 missing/changed PNG만 내려받는다. remote manifest가 없고 로컬 원본이 이미 완전하면 통과하며, 그 경우 이어지는 `upload-story-image-sources`가 현재 로컬 전체를 최초 seed 한다. remote manifest도 없고 로컬 원본도 없으면 복구할 출처가 없으므로 중단한다.

#### 3.2.1 새 이야기 추가 Flow

표준 후보 흐름은 `draft JSON 작성 → draft 이미지 생성 → pending proposal 등록 → 관리자 승인 → release sync → 앱 배포`다. 이 흐름을 쓰면 승인 직후에는 구버전 앱이 Storage fallback으로 새 이미지를 보고, 다음 앱 배포부터는 로컬 썸네일 번들이 우선된다. 새 이야기를 seed SQL로 바로 밀어 넣는 방식은 중간 삽입과 사용자 진행도 연결 위험이 있으므로 예외 경로로 둔다.

##### 3.2.1.1 전체 순서

운영자가 직접 draft JSON을 만들어 새 이야기를 올릴 때의 기본 명령은 아래 순서다.

```bash
make generate-draft-story-images STORY=assets/story_drafts/<draft_slug>.json
make apply-draft ENV=real DRAFT=<draft_slug> PROPOSER_USER_ID=<Supabase auth.users.id> DRY_RUN=1
make apply-draft ENV=real DRAFT=<draft_slug> PROPOSER_USER_ID=<Supabase auth.users.id>
# 관리자 UI에서 proposal 승인
make release-sync-stories ENV=real
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

각 단계의 원격 영향은 다음처럼 나뉜다.

| 단계 | 운영자 행동 | 로컬 출력 | DB 변화 | Storage 변화 | 앱 사용자 상태 |
|------|-------------|-----------|---------|---------------|----------------|
| draft 작성 | `assets/story_drafts/<slug>.json` 작성 | draft JSON | 없음 | 없음 | 변화 없음 |
| draft 이미지 생성 | `make generate-draft-story-images STORY=...` | `assets/story_drafts/<slug>/scene_N.png` | 없음 | 없음 | 변화 없음 |
| dry-run | `make apply-draft ... DRY_RUN=1` | 없음 | 없음 | 없음 | JSON, 이미지, 중복, payload만 확인 |
| proposal 등록 | `make apply-draft ...` | 없음 | `event_proposals(status='pending')` 생성 | `proposal-scenes/<uid>/<slug>/scene_N.png` 업로드 | 일반 사용자에게 아직 안 보임 |
| 관리자 승인 | 관리자 UI에서 위치와 인물 노출 확정 | 없음 | `events` published row 삽입, 뒤쪽 index shift, 퀴즈 row 생성 | proposal scene 원본 유지 | 승인 직후 새 이야기가 보임. 앱 번들 전에는 Storage fallback |
| release sync | `make release-sync-stories ENV=real` | `assets/events`, 원본 이미지, 썸네일, `pubspec.yaml` 갱신 | DB는 이미 공개 상태 | `story-image-sources` archive 갱신 | 다음 앱 배포용 번들 준비 완료 |
| 앱 배포 | real build 후 Store 배포 | build artifact | 없음 | cleanup 전까지 fallback 유지 | 업데이트 사용자는 로컬 썸네일 우선 |

##### 3.2.1.2 draft JSON 준비

권장 파일 구조는 draft JSON과 같은 stem의 이미지 폴더를 나란히 두는 방식이다.

```text
assets/story_drafts/
  20260623_elijah_ravens.json
  20260623_elijah_ravens/
    scene_01.png
    scene_02.png
    scene_03.png
    scene_04.png
```

draft JSON은 앱의 현재 story schema를 따라야 한다. 특히 `background_context`, `scene_captions`, `landmark_code`, `quiz_questions`를 빠뜨리면 승인 후 상세 화면, 지도, 퀴즈가 빈 값이나 fallback에 의존하게 된다.

| 묶음 | 필드 | 의미 |
|------|------|------|
| 기본 정보 | `title`, `era`, `summary`, `background_context`, `bible_ref` | 이야기 제목, 시대, 요약, 배경 지식, 본문 범위 |
| 위치/시간 | `landmark_code`, `start_year`, `end_year`, `time_precision`, `unit_code`, `unit_title`, `unit_order` | 지도 연결과 시간순 구간 |
| 삽입 위치 | `after_story_index` | 같은 era에서 몇 번 이야기 뒤에 넣을지. 승인 시 뒤쪽 `story_index`가 +1 밀린다. |
| 이미지/장면 | `story_scenes`, `scene_captions`, `scene_characters`, `characters` | 이미지 생성 프롬프트, 사용자에게 보일 장면 설명, 장면별 등장 인물 |
| 퀴즈 | `quiz_questions` | 1~3개 문항. 각 문항은 질문, 3개 작성 선택지, `answer_index` 0~2, 해설이 필요하다. |

예시:

```json
{
  "title": "까마귀가 먹인 엘리야",
  "era": "era_divided_kingdom",
  "characters": ["elijah", "ahab"],
  "summary": "엘리야가 가뭄을 전하고 그릿 시냇가에서 하나님의 공급을 받는다.",
  "background_context": "북이스라엘이 바알 숭배로 흔들리던 때, 엘리야는 하나님이 비와 생명의 주인이심을 선포한다.",
  "bible_ref": [{ "book": "왕상", "from": "17:1", "to": "17:7" }],
  "after_story_index": 12,
  "landmark_code": "lm_div_kerith_brook",
  "unit_code": "div_elijah",
  "unit_title": "엘리야와 엘리사",
  "unit_order": 2,
  "story_scenes": ["장면 1 이미지 생성용 설명", "장면 2 이미지 생성용 설명"],
  "scene_captions": ["사용자에게 보일 장면 1 설명", "사용자에게 보일 장면 2 설명"],
  "scene_characters": [["elijah", "ahab"], ["elijah"]],
  "quiz_questions": [
    {
      "type": "fact",
      "display_order": 0,
      "question": "엘리야가 아합에게 전한 말의 핵심은 무엇인가요?",
      "choices": ["하나님 말씀 없이는 비가 오지 않는다", "궁전을 새로 지어야 한다", "전쟁을 준비해야 한다"],
      "answer_index": 0,
      "explanation": "왕상 17:1에서 엘리야는 하나님 말씀 없이는 비도 이슬도 없을 것이라고 전합니다."
    }
  ]
}
```

`after_story_index`는 새 row의 id를 직접 정하는 값이 아니다. 관리자 승인 시 `insert_event_at_position(...)`이 같은 시대의 뒤쪽 `story_index`만 밀고 새 row를 끼워 넣는다. 이렇게 해야 기존 `events.id`가 보존되어 사용자의 저장, 진행도, 퀴즈 기록이 다른 이야기로 붙는 일을 막는다.

##### 3.2.1.3 draft 장면 이미지 생성

```bash
make generate-draft-story-images STORY=assets/story_drafts/<draft_slug>.json
```

| 입력 | 출력 | 주의점 |
|------|------|--------|
| `assets/story_drafts/<draft_slug>.json` | `assets/story_drafts/<draft_slug>/scene_N.png` | `STORY=`에는 `.json`까지 포함한 파일 경로를 넘긴다. |
| JSON의 `story_scenes`, `scene_characters`, `characters`, `bible_ref` | draft 전용 원본 PNG | `assets/events` 전체나 `assets/story_images` canonical 디렉토리는 prune하지 않는다. |

이미지 개수는 `story_scenes` 개수와 맞아야 한다. 마음에 들지 않는 장면은 해당 `scene_N.png`만 지운 뒤 다시 실행하면 그 장면을 다시 만들 수 있다.

##### 3.2.1.4 pending proposal 등록

real DB에 넣기 전에는 반드시 dry-run부터 실행한다.

```bash
make apply-draft ENV=real DRAFT=<draft_slug> PROPOSER_USER_ID=<Supabase auth.users.id> DRY_RUN=1
make apply-draft ENV=real DRAFT=<draft_slug> PROPOSER_USER_ID=<Supabase auth.users.id>
```

`DRAFT=<draft_slug>`는 `assets/story_drafts/<draft_slug>.json`으로 해석된다. `STORY=`를 직접 쓰려면 `.json` 파일 경로를 넘긴다. `PROPOSER_USER_ID`는 운영 Supabase `auth.users.id`이며, 매번 넘기지 않으려면 `.env.ops`에 `STORY_DRAFT_PROPOSER_USER_ID_PROD=<Supabase auth.users.id>`를 둔다.

`make apply-draft`가 확인하고 바꾸는 것은 다음과 같다.

| 구분 | 내용 |
|------|------|
| 검증 | 필수 필드, 장면 수와 `scene_captions` 수 일치, 1~3개 퀴즈, 같은 제목의 published event 또는 pending new proposal 중복 여부 |
| 로컬 입력 | `assets/story_drafts/<draft_slug>.json`, `assets/story_drafts/<draft_slug>/scene_N.png` |
| Storage 출력 | `proposal-scenes/<proposer_user_id>/<draft_slug>/scene_N.png` |
| DB 출력 | `event_proposals(status='pending')` row. `scene_image_paths`에는 업로드된 Storage path가 들어간다. |
| 앱 노출 | 아직 `events`를 바꾸지 않으므로 일반 사용자에게 보이지 않는다. 관리자와 제안자만 proposal 상세에서 확인한다. |

여러 draft를 한 번에 pending proposal로 올릴 때는 각 slug를 공백으로 나열한다. 이 경우에도 real 전에는 전체 후보를 dry-run으로 먼저 확인한다.

```bash
make apply-drafts ENV=real DRAFTS="20260623_elijah_ravens 20260624_amos_call" DRY_RUN=1
make apply-drafts ENV=real DRAFTS="20260623_elijah_ravens 20260624_amos_call"
```

`make apply-drafts`는 내부적으로 같은 `apply_story_draft.py`를 순차 실행한다. 하나가 실패하면 그 지점에서 멈추므로, 실패한 항목을 고친 뒤 다시 실행한다.

##### 3.2.1.5 관리자 승인

pending proposal은 관리자 UI에서 검수한 뒤 승인한다.

| 영역 | 승인 시 동작 |
|------|--------------|
| DB | `approve_event_proposal`이 `insert_event_at_position(...)`을 호출해 `events`에 published row를 만든다. 같은 era에서 `after_story_index + 1` 이후 row는 `story_index`가 +1 밀린다. |
| 위치 충돌 | 같은 위치를 겨냥한 다른 pending proposal은 `position_invalidated_at`이 set되어 위치 재선택 상태가 된다. 관리자가 새 위치를 골라 바로 승인할 수도 있다. |
| 이미지 | proposal의 `scene_image_paths`가 `events.scene_image_paths`로 복사된다. |
| 퀴즈 | proposal payload의 `quiz_questions`가 새 event에 연결된다. |
| 앱 | 앱은 `events_ordered` view를 읽으므로 승인 직후 새 이야기를 볼 수 있다. 아직 로컬 썸네일이 없으면 `scene_image_paths`를 public URL로 바꿔 네트워크 이미지를 보여준다. |

승인 다이얼로그에서는 삽입 위치, 인물 노출, 배경 지식, 장면 원고, 장면 캡션, 시간순 구간을 함께 확인한다.

##### 3.2.1.6 release sync 실행

```bash
make release-sync-stories ENV=real
```

이 명령은 새 proposal을 승인하는 명령이 아니다. **이미 관리자 승인으로 real DB에 반영된 active 상태**를 다음 앱 배포용 로컬 번들로 당겨오는 명령이다.

| 순서 | 단계 | Input | Output | 핵심 동작 |
|------|------|-------|--------|-----------|
| 1 | `export-stories-json ENV=real` | real DB의 `status='published' AND deleted_at IS NULL` events | `assets/events/*.json` | active published events를 era별 JSON으로 다시 쓰고, 각 row에 `landmark_code`와 연결된 `quiz_questions`를 함께 넣는다. |
| 2 | `sync-approved-proposal-assets --skip-post-processing` | 승인됐지만 `synced_to_local_at`이 비어 있는 proposal, `proposal-scenes` Storage | `assets/story_images/<canonical title>/scene_N.png`, 필요 시 `assets/avatars/<code>.png` | 승인된 proposal 원본을 로컬 원본 폴더로 내려받고, 성공한 proposal에만 `synced_to_local_at`을 set한다. active set에 없는 로컬 이야기 원본 폴더도 제거한다. |
| 3 | `ensure-story-image-sources ENV=real` | private `story-image-sources` manifest, 로컬 `assets/story_images/` | missing/changed 원본 PNG | proposal sync로 채워지지 않은 active story 원본을 private archive에서 보충한다. remote manifest에도 없고 로컬에도 없으면 중단한다. |
| 4 | `make thumbnails` | current `assets/events/*.json`, `assets/story_images/<title>/scene_*.png` | `assets/story_images_thumbs/<era_slug>_<story_index>/scene_*.jpg`, `index.json` | 모든 active 원본 PNG가 있는지 검사한 뒤 story thumbnail 디렉토리를 clean rebuild한다. |
| 5 | `make update-pubspec-assets` | 현재 썸네일 디렉토리 | `pubspec.yaml` | Flutter asset 목록을 현재 썸네일 상태와 맞춘다. |
| 6 | `upload-story-image-sources ENV=real` | current active local source set, old remote manifest | private `story-image-sources` object와 active manifest | 신규/변경 원본은 upload/upsert하고, old manifest에만 있는 object는 `delete_stale`로 삭제한 뒤 active manifest를 올린다. |

실행 후 기대되는 로컬 diff와 로그는 아래를 기준으로 본다.

| 확인 | 기대값 |
|------|--------|
| 로컬 JSON | 새/삭제/재정렬된 이야기가 `assets/events/*.json`에 반영되고, 퀴즈와 `landmark_code`가 같은 event row 안에 들어간다. |
| 로컬 원본 | 새 proposal 장면 원본이 `assets/story_images/<title>/scene_N.png`에 생긴다. 삭제된 active story 원본은 정리된다. |
| 썸네일/pubspec | 삭제된 이야기는 `assets/story_images_thumbs/index.json`, story thumb 디렉토리, `pubspec.yaml` asset 목록에서 빠진다. |
| pull 로그 | `Pull plan: download=..., skip=..., missing_remote=...`에서 `missing_remote=0`이어야 정상이다. |
| push 로그 | `Push plan: upload=..., skip=..., delete_stale=..., manifest_entries=...`를 확인한다. 새 proposal이 있으면 `upload`, 삭제 승인된 이야기가 있으면 `delete_stale`가 늘 수 있다. |
| 재실행 | release sync 직후 다시 dry-run하면 보통 `upload=0`, `delete_stale=0`이 기대값이다. |

실패하면 원인을 고친 뒤 같은 명령을 다시 실행한다. 단, 실행 전 로컬에 수동으로 작업한 `assets/events`나 `assets/story_images` 변경이 있으면 덮어쓸 수 있으니 먼저 `git status --short`와 diff를 확인한다.

예를 들어 4번과 8번 이야기를 삭제 승인한 뒤 새 이야기 2건을 2번 뒤와 마지막 뒤에 승인해도, DB RPC가 active `story_index`를 1..N으로 유지한다. 이후 `make release-sync-stories ENV=real`을 실행하면 삭제된 title은 통합 story JSON, thumbnail index, pubspec asset 목록에서 빠지고, 새 이야기는 proposal Storage의 이미지를 로컬 번들로 가져온다.

##### 3.2.1.7 검증, 배포, cleanup

release sync 후에는 앱 번들 asset과 지도 위치를 확인하고 real 빌드를 만든다.

```bash
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

Storage cleanup은 앱 배포 직후 하지 않는다. 사용자가 앱을 업데이트하기 전까지는 구버전 앱이 `events.scene_image_paths`의 `proposal-scenes/...`를 읽을 수 있기 때문이다. 충분한 업데이트 기간이 지난 뒤에만 `sync-approved-proposal-assets-clean ENV=real` 같은 정리 명령을 검토한다.

현재 구현에서 이 흐름을 받치는 연결은 다음과 같다.

| 영역 | 구현 상태 |
|------|-----------|
| DB/RPC | `event_proposals`, `submit_event_proposal`, `approve_event_proposal`, `insert_event_at_position`이 `background_context`, `scene_captions`, `unit_code/unit_title/unit_order`를 함께 다룬다. |
| Flutter | `EventProposal` 모델, Repository, 목사님 제안 작성 UI, 관리자 상세 UI가 최신 story schema를 입력/검수/승인 payload로 전달한다. |
| 이미지 fallback | `SceneAssetLoader.loadForEvent(event)`는 로컬 번들 썸네일이 없고 `events.scene_image_paths`가 있으면 기본 Supabase client로 Storage public URL을 만들어 fallback한다. |
| 운영 target | `make generate-draft-story-images`, `make apply-draft`, `make apply-drafts`, `make release-sync-stories`가 draft 생성부터 release bundle 준비까지 연결한다. |

#### 3.2.2 목사님 이야기 제안 Flow

목사님이 앱/웹 UI에서 직접 이야기를 제안하는 흐름도 3.2.1과 같은 proposal 인프라를 쓴다. 차이는 운영자가 `assets/story_drafts/*.json`을 직접 만드는 대신, UI wizard가 같은 story schema를 수집하고 `event_proposals` row를 만든다는 점이다.

##### 3.2.2.1 운영자 draft 경로와의 차이

| 구분 | 운영자 draft 경로 | 목사님 UI 제안 경로 |
|------|------------------|--------------------|
| 입력 위치 | `assets/story_drafts/<slug>.json` | 앱/웹 wizard 입력값 |
| 이미지 준비 | `make generate-draft-story-images`로 로컬 PNG 생성 | UI 또는 서버 흐름이 생성/업로드한 scene path 사용 |
| proposal 등록 | `make apply-draft`가 `event_proposals` row 생성 | UI submit/RPC가 `event_proposals` row 생성 |
| 승인 이후 | 관리자 승인 → `make release-sync-stories ENV=real` | 동일 |
| 앱 노출 | 승인 전에는 숨김, 승인 직후 Storage fallback, 배포 후 로컬 썸네일 | 동일 |

즉 “제안 작성 방식”만 다르고, 관리자 승인 이후의 DB index shift, Storage fallback, release sync, 앱 배포 흐름은 3.2.1과 같다.

##### 3.2.2.2 UI가 수집해야 하는 필드

UI wizard는 결국 `assets/events/*.json` 한 row와 같은 정보를 proposal payload에 담아야 한다. 필드를 화면 단계별로 묶으면 아래처럼 볼 수 있다.

| 화면/묶음 | 필드 | 검수 포인트 |
|-----------|------|-------------|
| 기본 이야기 | `title`, `summary`, `background_context`, `bible_refs` | 제목 중복, 본문 범위, 배경 지식이 비어 있지 않은지 확인한다. |
| 위치와 시간 | `landmark_id` 또는 `landmark_code`, `start_year`, `end_year`, `time_precision`, `after_story_index` | 지도 위치와 삽입 위치가 현재 시대의 흐름과 맞는지 확인한다. |
| 시간순 구간 | `unit_code`, `unit_title`, `unit_order` | 시간순 보기에서 어느 묶음 카드에 들어갈지 확인한다. |
| 인물 | `characters`, `scene_characters` | story-level 인물과 장면별 인물이 과하거나 빠지지 않았는지 확인한다. |
| 장면 | `story_scenes`, `scene_captions`, `scene_image_paths`, `scene_image_prompts` | 이미지 생성용 설명과 사용자에게 보일 캡션을 분리한다. 장면 수와 캡션 수가 같아야 한다. |
| 퀴즈 | `quiz_questions` | 1~3개 문항, 3개 작성 선택지, `answer_index` 0~2, 본문 근거가 있는 해설을 확인한다. |

`background_context`, `scene_captions`, `unit_code/unit_title/unit_order`, `landmark_code`, `quiz_questions`는 이제 별도 파일이 아니라 통합 story row의 일부다. UI에서 빠뜨리면 승인 후 DB에는 들어가도 상세 화면, 지도, 퀴즈, 시간순 보기 중 일부가 빈 값이나 fallback에 기대게 된다.

##### 3.2.2.3 상태 전이

| 단계 | UI/사용자 행동 | DB | Storage | 앱 상태 |
|------|----------------|----|---------|---------|
| 작성 | wizard에서 본문, 배경, 위치, 장면, 캡션, 퀴즈를 입력한다. | 아직 없거나 로컬 draft state만 있다. | 이미지 생성 전이면 없음. | 일반 사용자에게 안 보임 |
| 이미지 생성 | UI/서버가 장면 이미지를 만들고 proposal용 path를 준비한다. | proposal row 생성 전이면 변화 없음. | `proposal-scenes/.../scene_N.png`가 생긴다. | 일반 사용자에게 안 보임 |
| 제출 | "제안 등록"을 누른다. | `event_proposals(status='pending')` row가 생성된다. | 생성된 scene path가 proposal row에 연결된다. | 관리자/제안자는 proposal 상세에서 확인 |
| 검토 | 관리자가 상세 화면에서 내용, 위치, 인물, 장면, 퀴즈를 본다. | 변화 없음 | 변화 없음 | 일반 사용자에게 안 보임 |
| 승인 | 관리자가 삽입 위치와 인물 노출을 확정하고 승인한다. | `events`에 published row가 삽입되고 뒤쪽 `story_index`가 밀리며, 퀴즈 row가 생성된다. | proposal scene 원본은 유지된다. | 승인 직후 새 이야기가 보임. 새 앱 전에는 Storage fallback |
| release sync | 운영자가 `make release-sync-stories ENV=real`을 실행한다. | DB는 이미 공개 상태다. | `story-image-sources` archive가 갱신된다. | 다음 앱 배포용 로컬 썸네일 준비 완료 |
| 앱 배포 | real 앱을 빌드/배포한다. | 변화 없음 | cleanup 전까지 fallback 유지 | 업데이트한 사용자는 로컬 썸네일 우선 |

##### 3.2.2.4 관리자 승인 체크리스트

3.2.2.3은 상태 흐름이고, 이 표는 승인 버튼을 누르기 전의 품질 체크리스트다. 모두 통과하지 않으면 반려하거나 수정 요청한다.

| 항목 | 통과 기준 |
|------|-----------|
| 위치 | `after_story_index`가 현재 era 흐름상 자연스럽고, 같은 위치를 겨냥한 다른 pending proposal이 있으면 승인 위치를 다시 고른다. |
| 본문/요약 | `summary`와 `background_context`가 성경 본문 범위와 맞고, 과도한 해석이나 중복 설명이 없다. |
| 지도 | `landmark_id` 또는 `landmark_code`가 실제 사건 위치에 가장 가깝고, 확정 위치가 애매하면 적절한 region으로 연결한다. |
| 장면/캡션 | `story_scenes`는 이미지 생성용으로 구체적이고, `scene_captions`는 사용자에게 보일 짧은 설명으로 자연스럽다. 장면 수와 캡션 수가 같다. |
| 인물 | `characters`와 `scene_characters`가 실제 등장 인물을 과장하지 않고, 앱 인물 노출 정책과 맞는다. |
| 퀴즈 | 질문이 본문 이해를 묻고, 보기 3개와 `answer_index`가 맞으며, 해설에 본문 근거가 있다. |

승인 자체의 index shift와 기존 `events.id` 보존은 3.2.2.3의 “승인” 단계에서 처리된다.

##### 3.2.2.5 승인 후 운영자가 할 일

승인 직후 새 이야기는 DB에는 이미 공개되어 있고, 앱은 `events.scene_image_paths`를 통해 Storage fallback 이미지를 볼 수 있다. 하지만 다음 앱 배포에 로컬 썸네일을 포함하려면 운영자가 release sync를 실행해야 한다.

```bash
make release-sync-stories ENV=real
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

release sync 이후에는 `assets/events/*.json`에 목사님 제안으로 승인된 이야기가 들어오고, `assets/story_images/<title>/scene_N.png`, `assets/story_images_thumbs/`, `pubspec.yaml`, `story-image-sources` manifest가 함께 맞춰진다. Storage cleanup은 3.2.1과 동일하게 앱 배포 직후 하지 않고, 구버전 사용자 fallback 기간을 충분히 둔 뒤 검토한다.

#### 3.2.3 기존 콘텐츠나 seed 만 수정하는 경우

이미 공개된 이야기의 제목, 요약, 좌표, 퀴즈, landmark, 인물 노출 같은 수정은 새
이야기 추가보다 단순하다. `events.id`를 새로 만들지 않고 기존 row를 갱신하는 변경이면
필요한 seed만 재생성하고 적용한다.

```bash
# 사건/인물만 바뀐 경우
make seed-stories-characters
make apply-seeds-stories-characters ENV=dev
make apply-seeds-stories-characters ENV=real

# 퀴즈만 바뀐 경우
make seed-quizzes
make apply-seeds-quizzes ENV=dev
make apply-seeds-quizzes ENV=real

# landmark만 바뀐 경우
make seed-landmarks
make apply-seeds-landmarks ENV=dev
make apply-seeds-landmarks ENV=real
```

장면 원본 이미지가 바뀌면 앱 번들도 다시 만들어야 한다.

```bash
make generate-story-images
make thumbnails
make update-pubspec-assets
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

KRV 성경 구절 seed는 최초 bootstrap 대상이다. 중복 INSERT 시 에러가 날 수 있으므로
평소 콘텐츠 수정 때 매번 다시 넣지 않는다.

### 3.3 DB schema / RLS / RPC / cron 을 바꾸는 경우

예:

- 새 table / column / index 추가
- RLS policy 변경
- RPC 변경
- Edge Function 호출 경로 변경
- `pg_cron` 스케줄 변경
- Storage bucket / policy 변경

이 섹션은 이야기 추가/삭제가 아니라 앱 기능 개발 중 DB 구조나 동작이 바뀌는 경우를
다룬다. 예를 들어 새 프로필 설정 컬럼, 새 알림 RPC, RLS 정책 보정, Storage bucket
정의 변경, cron 함수 수정은 여기로 온다.

현재 정책:

- `db_init.sql`이 schema 단일 진실 소스다.
- dev 는 reset 방식으로 최종 상태를 검증한다.
- real 은 reset 하지 않고 `supabase/patches/*.sql`로 기존 DB를 수정한다.
- patch 파일은 여러 번 실행해도 안전한 idempotent SQL이어야 한다.
- 앱 코드가 새 DB 기능에 의존하면, patch를 real에 먼저 적용하고 real smoke 후 앱을
  빌드/배포한다.

변경 파일 기준:

| 변경 | 반드시 수정 | 보통 함께 수정 |
|------|-------------|----------------|
| table/column/index/trigger/RLS/RPC/cron | `db_init.sql`, `supabase/patches/*.sql` | `docs/BACKEND.md`, 관련 repository/model/test |
| Edge Function 코드 | `supabase/functions/<name>/index.ts` | `docs/BACKEND.md`, function README, secret 문서 |
| seed 생성 규칙 | `tools/seed/*`, 생성 SQL | `docs/DATA_PIPELINE.md`, `Makefile` help |
| Storage bucket/policy | `db_init.sql`, patch SQL | `tools/supabase/*`, `docs/BACKEND.md` |

dev 검증 순서:

```bash
# 1. db_init.sql 수정
# 2. supabase/patches/YYYYMMDD_HHMM_description.sql 작성
# 3. 필요하면 seed builder / seed SQL / 앱 코드 수정
make seed-all
make db-init ENV=dev
make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
scripts/run_dev.sh

# patch 자체도 dev에서 한 번 이상 실행해 idempotency를 확인한다.
make apply-patch ENV=dev PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
make apply-patch ENV=dev PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
```

`make db-init ENV=dev`는 최종 schema가 깨지지 않는지 보는 reset 검증이다.
`make apply-patch ENV=dev`는 patch가 문법적으로 안전하고 반복 실행 가능한지 보는 검증이다.
복잡한 data backfill, column rename, destructive migration은 dev reset만으로 충분하지
않다. 그런 patch는 실제 기존 상태와 가까운 dev DB 또는 백업 복제 DB에 먼저 적용해
데이터 변환 결과를 확인한다.

문서도 함께 갱신한다.

- schema/RLS/RPC/Edge Function: `docs/BACKEND.md`
- 데이터/Makefile 흐름: `docs/DATA_PIPELINE.md`
- 중요한 운영 결정: `docs/ADR.md`
- 신규 환경 구축/운영 순서: `docs/guides/DB_SETUP.md` 또는 이 문서
- patch 작성 세부 규칙: `supabase/patches/README.md`

patch 작성 패턴:

```sql
alter table if exists public.app_user_profiles
  add column if not exists preferred_font_scale text;

create or replace function public.some_rpc()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  -- ...
end;
$$;

drop policy if exists some_policy on public.some_table;
create policy some_policy
  on public.some_table
  for select
  using (public.is_admin() or auth.uid() = user_id);
```

real 적용 순서:

1. `git diff`에서 `db_init.sql`, patch SQL, 앱 코드, 문서가 같은 의도를 말하는지 확인한다.
2. real 적용 전 백업 또는 Supabase Dashboard snapshot 상태를 확인한다.
3. patch를 real에 적용한다.
4. seed도 필요한 변경이면 patch 이후 필요한 `apply-seeds-* ENV=real`만 좁게 적용한다.
5. `scripts/run_real.sh`로 새 DB 상태와 앱 코드가 함께 동작하는지 smoke test 한다.
6. build number를 올리고 real build script로 배포 후보를 만든다.

```bash
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql

# seed가 필요한 경우만, 가능한 좁은 target 사용
make apply-seeds-stories-characters ENV=real
make apply-seeds-quizzes ENV=real
make apply-seeds-landmarks ENV=real

scripts/run_real.sh
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

운영 patch 에서 피할 것:

- `drop table`, `truncate`, 대량 `delete`처럼 사용자 데이터를 지우는 변경.
- `not null` column을 default/backfill 없이 바로 추가하는 변경.
- 기존 RPC signature를 앱 배포 전에 깨는 변경.
- RLS를 잠시라도 과하게 열어 두는 변경.
- `make db-init ENV=real`로 reset해서 patch를 대신하는 것.

breaking change가 필요하면 2단계로 나눈다.

1. 기존 앱과 새 앱이 모두 동작하는 확장형 patch를 먼저 배포한다.
2. 새 앱 배포와 충분한 업데이트 기간 이후, 낡은 column/RPC/policy를 정리하는 별도
   patch를 만든다.

## 4. real 배포 Flow

3장은 변경 유형별로 실제 개발/운영 절차를 설명한다. 4장은 그 절차를 다시 반복하지 않고, **real에 적용하거나 앱을 배포하기 직전의 최종 게이트**만 다룬다. 어떤 명령을 실행해야 하는지는 먼저 3장에서 결정하고, 4장에서는 “정말 배포 가능한 상태인가?”를 확인한다.

### 4.1 먼저 어떤 3장 절차를 탔는지 확인

| 이번 변경 | 먼저 완료해야 하는 절차 | 4장에서 확인할 것 |
|-----------|--------------------------|-------------------|
| 앱 코드만 변경 | §3.1 일반 앱 코드만 바꾸는 경우 | real DB/Storage를 바꾸는 명령을 실행하지 않았는지 확인한다. |
| 기존 콘텐츠/seed 수정 | §3.2.3 기존 콘텐츠나 seed 만 수정하는 경우 | 필요한 seed target만 좁게 real에 적용했는지, KRV bootstrap seed를 불필요하게 반복하지 않았는지 확인한다. |
| 신규 이야기 추가/삭제 승인 | §3.2.1 또는 §3.2.2, 이후 `make release-sync-stories ENV=real` | active DB export, 원본 이미지, 썸네일, `pubspec.yaml`, `story-image-sources` manifest가 같은 상태인지 확인한다. |
| DB schema/RLS/RPC/cron 변경 | §3.3 DB schema / RLS / RPC / cron 을 바꾸는 경우 | real patch가 먼저 적용됐고, 앱 코드가 그 DB 상태와 함께 동작하는지 확인한다. |

### 4.2 공통 배포 전 게이트

real 배포 후보를 만들기 직전에 항상 확인한다.

| 확인 | 기준 |
|------|------|
| diff 범위 | `git diff`에서 코드, 생성물, 문서가 같은 의도를 말해야 한다. unrelated 변경은 섞지 않는다. |
| 환경 | dev/real env가 의도대로 선택됐는지 확인한다. real 적용 명령에는 반드시 `ENV=real`이 보인다. |
| 원격 변경 | `make apply-patch ENV=real`, `make apply-seeds-* ENV=real`, `make release-sync-stories ENV=real`, Storage upload 계열 중 무엇을 실행했는지 설명 가능해야 한다. |
| 검증 | 변경 성격에 맞는 `flutter analyze`, `flutter test`, asset/path 검증, polygon 검증, patch idempotency 검증이 끝나야 한다. |
| secret | `.env`, service role key, Supabase PAT, private service account JSON이 diff에 없어야 한다. |
| build number | 앱 배포가 있으면 `pubspec.yaml` version/build number 또는 build script 인자를 확인한다. |

자주 쓰는 최종 검증 명령은 아래 조합이다. 변경 범위가 좁으면 필요한 것만 실행하되, 앱 배포 후보를 만들 때는 `scripts/run_real.sh` smoke를 권장한다.

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
make check-pubspec-assets
scripts/run_real.sh
```

### 4.3 real 적용 순서 게이트

real 원격 상태를 바꾸는 작업은 순서가 중요하다.

| 상황 | 순서 기준 |
|------|-----------|
| 앱 코드만 변경 | DB/Storage 적용 없이 앱만 빌드한다. `make apply-patch ENV=real`, `make apply-seeds ENV=real`, `make release-sync-stories ENV=real`은 실행하지 않는다. |
| 기존 seed 수정 | dev에서 seed 적용과 앱 확인을 끝낸 뒤, real에는 필요한 `apply-seeds-*` target만 좁게 적용한다. 전체 `make apply-seeds ENV=real`이 필요한지 다시 확인한다. |
| 신규 이야기/삭제 승인 | 관리자 승인으로 DB active 상태가 먼저 바뀐다. 그 다음 `make release-sync-stories ENV=real`로 로컬 JSON/thumb/pubspec/source archive를 맞춘다. |
| DB patch 동반 | real patch를 앱 배포보다 먼저 적용한다. 앱이 새 column/RPC를 즉시 필요로 하면 patch 후 `scripts/run_real.sh`로 확인한 뒤 빌드한다. |
| breaking change | 한 번에 바꾸지 않는다. 기존 앱과 새 앱이 모두 동작하는 호환 patch를 먼저 내고, 앱 업데이트 기간 이후 정리 patch를 따로 만든다. |

### 4.4 빌드와 배포 후 확인

최종 빌드는 real 환경을 바라보는 script로 만든다.

```bash
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

배포 직후 확인 항목:

| 영역 | 확인 |
|------|------|
| 앱 시작 | real 앱이 시작되고 홈 데이터가 로드되는지 확인한다. |
| 인증 | Google, Apple, Kakao 로그인 중 변경 영향이 있는 경로를 확인한다. |
| 콘텐츠 | 이야기 추가/삭제/seed 변경이 있었다면 새 이야기, 삭제된 이야기, 퀴즈, 지도 위치, 썸네일을 확인한다. |
| DB/RPC | patch가 있었다면 변경된 RPC, RLS, repository 쿼리 경로를 real에서 smoke test 한다. |
| 푸시 | 푸시 관련 변경이면 token 등록과 최근 push/log 상태를 확인한다. |
| fallback cleanup | proposal scene cleanup은 앱 배포 직후 하지 않는다. 구버전 사용자의 Storage fallback 기간이 충분히 지난 뒤 검토한다. |

문제가 발견되면 원인을 먼저 분리한다. 앱 코드 문제면 앱 재빌드/재배포, DB patch 문제면 forward patch, 콘텐츠 export 문제면 release sync 재실행이 기본 대응이다. 운영 DB에서 `make db-init ENV=real`로 되돌리는 방식은 사용하지 않는다.

## 5. 푸시 / Firebase 운영 Flow

현재 결정:

- dev 와 real 이 같은 Firebase 프로젝트를 쓴다.
- Supabase 는 dev/real 이 분리되어 있다.
- FCM token 은 각 Supabase DB 의 `user_push_tokens`에 따로 저장된다.

평소에는 건드릴 일이 없다.

푸시 테스트:

```sql
select public.dispatch_daily_exploration_push();
```

확인 SQL:

```sql
select platform, count(*)
from public.user_push_tokens
group by platform
order by platform;

select id, status_code, timed_out, error_msg, left(content, 500)
from net._http_response
order by id desc
limit 10;
```

주의:

- dev DB 에 내 기기 token 이 있으면 dev push 도 같은 휴대폰으로 온다.
- 실제 사용자에게 배포한 뒤 dev push 가 섞이면 곤란하다면 dev cron 비활성화 또는
  dev/real Firebase 분리를 검토한다.

## 6. 자주 쓰는 명령 모음

### 실행

```bash
scripts/run_dev.sh
scripts/run_real.sh
```

### 빌드

```bash
scripts/build_android_dev.sh
scripts/build_android_real.sh
scripts/build_ios_dev.sh
scripts/build_ios_real.sh
```

### dev 전체 reset

```bash
make seed-all
make thumbnails
make update-pubspec-assets
make db-init ENV=dev
make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
```

`ENV=dev`는 생략 가능하다.

### real 전체 bootstrap

신규 Supabase 프로젝트를 처음 만들거나 복구하면서 real DB 를 정말 초기화해야 할
때만 쓴다. 일반 운영 배포에서는 쓰지 않는다.

```bash
make seed-all
make thumbnails
make update-pubspec-assets
CONFIRM_REAL_DB_INIT=1 make db-init ENV=real
make apply-seeds ENV=real
make upload-character-avatars ENV=real
```

### Makefile 매핑 확인

```bash
make -n db-init
make -n apply-patch ENV=real PATCH=supabase/patches/example.sql
make -n upload-character-avatars
make -n upload-character-avatars ENV=real
```

기대 결과:

- dev: `ops=dev`, `SUPABASE_DB_URL_DEV`, `--env dev`
- real patch/storage: `ops=prod`, `SUPABASE_DB_URL_PROD`, `--env prod`

### 코드 검증

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
python3 tools/app/verify_asset_paths.py
python3 tools/lint/check_forbidden_patterns.py
```

## 7. 배포 전 체크리스트

real build 전 확인:

- `scripts/run_dev.sh`로 dev 정상 동작.
- `scripts/run_real.sh`로 real 정상 동작.
- Google/Kakao/Apple 로그인 확인.
- 앱-only 배포라면 `apply-patch`, `apply-seeds`, `release-sync-stories`를 실행하지 않았는지 확인.
- DB schema/RLS/RPC/cron/Storage 변경이면 `db_init.sql`과 `supabase/patches/*.sql`이
  함께 있고 dev reset + dev patch 반복 적용으로 먼저 검증했는지 확인.
- real 에 `db-init`을 실행하지 않는지 확인.
- seed 만 바뀐 변경이면 전체 `apply-seeds ENV=real`이 아니라 개별
  `apply-seeds-* ENV=real`로 충분한지 확인.
- 이야기 추가/삭제 승인 후 배포라면 `make release-sync-stories ENV=real`을 실행했고,
  `ensure-story-image-sources`/`upload-story-image-sources` dry-run의
  `upload`, `skip`, `delete_stale` 결과가 기대와 맞는지 확인.
- `flutter analyze`, 관련 `flutter test` 통과.
- `python3 tools/app/verify_asset_paths.py`, `make check-pubspec-assets` 통과.
- secret 이 git diff 에 포함되지 않았는지 확인.
- real push 테스트가 필요하면 `dispatch_daily_exploration_push()`를 한 번만 실행.
- build number 증가.

## 8. 현재 상태 판정

현재 코드 기준으로 다음은 세팅되어 있다.

- 앱 실행/빌드 script 는 dev/real 을 분리한다.
- `.env`에는 앱 공개값만 둔다.
- `.env.ops`에는 DB URL/service role 을 둔다.
- Makefile 기본값은 dev 다.
- `ENV=real`은 운영 `PROD` 값으로 매핑된다.
- Python Storage 운영 도구는 `--env dev|prod`를 받고 Makefile 이 올바르게 넘긴다.
- 앱은 `ENV`, `SUPABASE_URL`, `SUPABASE_ANON_KEY` dart-define 이 없으면 실패한다.
- `release-sync-stories`는 승인 proposal 자산, private story source archive,
  썸네일, pubspec 갱신까지 포함하는 다음 앱 배포 준비 target이다.
- `story-image-sources` bucket은 release builder 전용 private 원본 archive이고,
  `db-init` purge 대상이 아니다.
- real 을 기본값으로 쓰지 않는다.
- real `db-init`은 기본 차단되며, 운영 DB 변경은 `apply-patch`로 한다.

핵심 운영 결정:

> real 은 reset 방식 배포를 멈추고 `supabase/patches/*.sql` 기반의
> idempotent patch 방식으로 수정한다.
