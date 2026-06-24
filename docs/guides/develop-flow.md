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

순서:

1. dev 로 실행한다.
2. 코드를 수정한다.
3. 관련 테스트를 추가/수정한다.
4. dev 로 확인한다.
5. 분석/테스트를 돌린다.
6. 필요하면 real 로 한 번 smoke test 한다.
7. real build script 로 배포 후보를 만든다.

명령:

```bash
scripts/run_dev.sh
flutter analyze
flutter test
scripts/run_real.sh
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

이 경우 DB reset 이 필요 없다.

### 3.2 공개 콘텐츠 / 이야기 데이터 Flow

공개 콘텐츠는 앱 번들, Supabase DB, Supabase Storage가 동시에 얽힌다. 특히 새
이야기는 `story_index`와 이미지 fallback 때문에 일반 seed 수정처럼 처리하지 않는다.

#### 3.2.0 초기 데이터 세팅

초기 데이터는 저장소의 canonical 파일을 기준으로 한 번에 세팅한다. 현재
`assets/200_stories/*.json`에는 310개 이야기가 있고, 향후 더 늘어날 수
있다. 이 파일들이 초기 앱 번들/DB의 기준이다.

초기 세팅에 들어가는 주요 로컬 파일:

| 영역 | 기준 파일 | 생성/적용 |
|------|-----------|-----------|
| 이야기 본문 | `assets/200_stories/*.json` | `make seed-stories-characters` |
| 배경 지식 | 각 story JSON의 `background_context` | `events.background_context` |
| 장면 캡션 | 각 story JSON의 `scene_captions` | `events.scene_captions` |
| 지도 위치 | `assets/landmarks/*.json`, `event_region_mapping.json` | `make seed-landmarks`, `make seed-stories-characters` |
| 퀴즈 | `assets/quizzes/*.json` | `make seed-quizzes` |
| 원본 장면 이미지 | `assets/story_images/<title>/scene_N.png` | 로컬 원본 |
| 앱용 썸네일 | `assets/story_images_thumbs/<era>_<index>/scene_N.jpg` | `make thumbnails` |
| 앱 asset 등록 | `pubspec.yaml` | `make update-pubspec-assets` |

초기 세팅 명령:

```bash
make seed-all
make thumbnails
make update-pubspec-assets
make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
scripts/run_dev.sh
```

real 신규 구축이나 복구 상황에서만 같은 산출물을 real에 적용한다.

```bash
make apply-seeds ENV=real
make upload-character-avatars ENV=real
scripts/run_real.sh
```

원리:

1. 초기 앱 배포에는 모든 초기 이야기 썸네일이 앱 번들에 포함된다.
2. 초기 이야기의 `events.scene_image_paths`는 비어 있어도 된다.
3. 앱은 초기/번들된 이야기를 로컬 `assets/story_images_thumbs/index.json` 매핑으로 찾는다.
4. 중간에 새 이야기가 추가되어 기존 이야기들의 `story_index`가 밀려도, 기존 이야기 제목은 그대로라 구버전 앱의 옛 `index.json`이 기존 이미지들을 계속 찾을 수 있다.
5. 새 이야기는 구버전 앱의 `index.json`에 없으므로 로컬 매핑으로는 이미지를 찾지 못한다. 이때 `events.scene_image_paths` fallback이 연결된 화면에서만 `proposal-scenes/...` Storage 이미지를 보여줄 수 있다.
6. Storage fallback은 초기 데이터가 아니라, 앱 배포 뒤 추가되는 새 이야기의 임시 노출을 위한 장치다.

#### 3.2.1 새 이야기 추가 Flow

표준 후보 흐름은 `draft JSON → draft 이미지 생성 → proposal row 생성 + Storage 업로드
→ 관리자 승인 → release sync → 앱 배포`다. 이 흐름은 구버전 앱 사용자도 승인 직후
Storage fallback으로 새 이야기 이미지를 볼 수 있게 하려는 운영 방식이다.

새 이야기를 추가할 때는 먼저 아래 순서대로 진행한다. 상세 원리는 뒤쪽
`make generate-draft-story-images` / `make apply-draft` 설명을 참고한다.

**1. draft JSON 생성**

- 파일 위치: `assets/story_drafts/<draft_slug>.json`
- 예: `assets/story_drafts/20260624_cain_test_story.json`

**2. draft 장면 이미지 생성**

```bash
make generate-draft-story-images STORY=assets/story_drafts/20260624_cain_test_story.json
```

`STORY=`를 쓸 때는 반드시 `.json`까지 포함한 파일 경로를 넣는다.
이미지는 `assets/story_drafts/20260624_cain_test_story/scene_01.png`처럼
draft JSON과 같은 stem의 폴더에 생성된다.

**3. real 적용 전 dry-run**

```bash
make apply-draft ENV=real DRAFT=20260624_cain_test_story PROPOSER_USER_ID=<Supabase auth.users.id> DRY_RUN=1
```

`DRAFT=20260624_cain_test_story`는
`assets/story_drafts/20260624_cain_test_story.json`으로 해석된다.
`PROPOSER_USER_ID`는 운영 Supabase `auth.users.id`이며, 매번 넘기지 않으려면
`.env.ops`에 `STORY_DRAFT_PROPOSER_USER_ID_PROD=<Supabase auth.users.id>`를 둔다.

**4. pending proposal 등록 + proposal-scenes 업로드**

```bash
make apply-draft ENV=real DRAFT=20260624_cain_test_story PROPOSER_USER_ID=<Supabase auth.users.id>
```

**5. 관리자 UI에서 proposal 승인**

- 승인 다이얼로그에서 삽입 위치와 인물 노출을 확인한다.
- 같은 위치를 겨냥한 다른 pending 제안이 있으면 승인 다이얼로그에서 위치를 조정한다.

**6. release sync 실행**

```bash
make release-sync-stories ENV=real
```

**7. 검증 후 real 앱 빌드/배포**

```bash
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

현재 구현 상태:

- `db_init.sql` 기준으로 `event_proposals`, `submit_event_proposal`,
  `approve_event_proposal`, `insert_event_at_position`이 `background_context`,
  `scene_captions`, `unit_code/unit_title/unit_order`를 함께 다룬다.
- Flutter `EventProposal` 모델, Repository, 목사님 제안 작성 UI, 관리자 상세 UI가
  최신 story schema를 입력/검수/승인 payload로 전달한다.
- 관리자 승인 다이얼로그는 같은 era의 현재 이야기 목록을 보여 주고
  `after_story_index` override를 전달한다. 같은 위치를 겨냥한 draft/목사님 제안이
  겹쳐도 관리자가 UI에서 새 위치를 골라 바로 승인할 수 있다.
- `make generate-draft-story-images`가 draft JSON 한 건에서
  `assets/story_drafts/<slug>/scene_N.png`를 만든다.
- `make apply-draft`가 draft 원본 이미지를 `proposal-scenes`에 업로드하고
  pending proposal row를 만든다. 여러 건은 `make apply-drafts`로 순차 등록한다.
- `SceneAssetLoader.loadForEvent(event)`는 로컬 번들 썸네일이 없고
  `events.scene_image_paths`가 있으면 기본 Supabase client로 Storage public URL을
  만들어 fallback한다. 따라서 `StoryEventThumbCard`, 상세 이전/다음 카드,
  프로필 미니맵처럼 별도 `publicUrlFor`를 넘기지 않는 진입점도 새 이야기 이미지를
  표시할 수 있다.
- `make release-sync-stories`는 DB events export, DB quiz export,
  DB landmark mapping export, 승인 자산 다운로드, thumbnails, `pubspec.yaml`
  갱신을 묶는다. 여러 approved proposal이 한 번에 쌓여 있어도 현재 DB published
  상태 전체를 다음 앱 배포용 로컬 canonical 파일로 되돌린다.

여러 draft를 한 번에 pending proposal로 올릴 때는 각 slug를 공백으로 나열한다.
이 경우에도 real 전에는 `DRY_RUN=1`로 먼저 확인한다.

```bash
make apply-drafts ENV=real DRAFTS="20260623_elijah_ravens 20260624_amos_call" DRY_RUN=1
make apply-drafts ENV=real DRAFTS="20260623_elijah_ravens 20260624_amos_call"
```

`release-sync-stories`는 `export-stories-json`, `export-quizzes-json`,
`export-event-region-mapping`, `sync-approved-proposal-assets`, `thumbnails`,
`update-pubspec-assets`를 순서대로 실행한다. 즉 앱 번들용 이야기 JSON, 퀴즈 JSON,
landmark mapping, 원본 이미지, 썸네일, pubspec 준비까지 담당한다.

권장 draft 구조:

```text
assets/story_drafts/
  20260623_elijah_ravens.json
  20260623_elijah_ravens/
    scene_01.png
    scene_02.png
    scene_03.png
    scene_04.png
```

draft JSON은 앱의 현재 story schema를 따라야 한다. `background_context`와
`scene_captions`를 빼면 승인 후 상세 화면의 배경 지식/장면 설명이 비거나 낡은
fallback에 의존하게 된다.

```json
{
  "title": "까마귀가 먹인 엘리야",
  "era": "era_divided_kingdom",
  "characters": ["elijah", "ahab"],
  "summary": "엘리야가 가뭄을 전하고 그릿 시냇가에서 하나님의 공급을 받는다.",
  "background_context": "북이스라엘이 바알 숭배로 흔들리던 때, 엘리야는 하나님이 비와 생명의 주인이심을 선포한다.",
  "bible_ref": [{"book": "왕상", "from": "17:1", "to": "17:7"}],
  "start_year": -870,
  "end_year": -870,
  "time_precision": "approx",
  "after_story_index": 12,
  "unit_code": "div_elijah",
  "unit_title": "엘리야와 엘리사",
  "unit_order": 2,
  "landmark_code": "lm_div_kerith_brook",
  "story_scenes": [
    "장면 1 이미지 생성용 설명",
    "장면 2 이미지 생성용 설명"
  ],
  "scene_captions": [
    "사용자에게 보일 장면 1 설명",
    "사용자에게 보일 장면 2 설명"
  ],
  "scene_characters": [
    ["elijah", "ahab"],
    ["elijah"]
  ],
  "quiz_questions": [
    {
      "question": "엘리야가 아합에게 전한 말의 핵심은 무엇인가요?",
      "choices": ["하나님 말씀 없이는 비가 오지 않는다", "궁전을 새로 지어야 한다", "전쟁을 준비해야 한다"],
      "answer_index": 0,
      "explanation": "왕상 17:1에서 엘리야는 하나님 말씀 없이는 비도 이슬도 없을 것이라고 전합니다."
    }
  ]
}
```

`after_story_index`는 "몇 번 뒤에 넣을지"를 뜻한다. 관리자 승인 시
`insert_event_at_position(...)`가 같은 시대의 뒤쪽 `story_index`를 +1 밀고 새 row를
삽입한다. 이렇게 해야 기존 `events.id`가 보존되고, 사용자의 저장/진행도/퀴즈 기록이
다른 이야기로 붙는 일을 막는다.

단계별 인프라와 앱 상태:

| 단계 | 운영자 행동 | DB 상태 | Storage 상태 | 앱 사용자에게 보이는 상태 |
|------|-------------|---------|---------------|----------------------------|
| 1. draft JSON 작성 | `assets/story_drafts/*.json` 작성 | 변화 없음 | 변화 없음 | 변화 없음 |
| 2. draft 이미지 생성 | `make generate-draft-story-images STORY=assets/story_drafts/<slug>.json` | 변화 없음 | 변화 없음 | 변화 없음 |
| 3. draft dry-run | `make apply-draft ENV=real DRAFT=<slug> PROPOSER_USER_ID=<Supabase auth.users.id> DRY_RUN=1` | 변화 없음 | 변화 없음 | JSON/이미지/중복/payload만 확인 |
| 4. draft 적용 | `make apply-draft ENV=real DRAFT=<slug> PROPOSER_USER_ID=<Supabase auth.users.id>` | `event_proposals(status='pending')` 생성 | `proposal-scenes/<uid>/<draft>/scene_N.png` 업로드 | 일반 사용자에게는 아직 안 보임. 관리자/제안자는 proposal 상세에서 이미지 확인 |
| 5. 관리자 승인 | 관리자 UI에서 위치/인물 노출 확정 후 승인 | `events`에 published row 삽입, 뒤 index shift, `scene_image_paths` 복사, 퀴즈 row 생성 | proposal scene 원본 유지 | 새 이야기가 즉시 보임. 새 앱 전에는 Storage 이미지 fallback |
| 6. release sync | DB → 로컬 stories/quiz/mapping export, 원본 복사/다운로드, thumbnails/pubspec 생성 | DB는 이미 공개 상태 | Storage는 fallback 보호용으로 유지 | 구버전은 Storage, 신버전 빌드는 로컬 썸네일 준비 완료 |
| 7. 앱 배포 | real 빌드 후 Store 배포 | 변화 없음 | cleanup 전까지 유지 | 업데이트한 사용자는 로컬 썸네일 우선. 미업데이트 사용자는 Storage fallback |

`make generate-draft-story-images` 원리:

- 입력은 draft JSON 하나다.
- 출력은 `assets/story_drafts/<draft_slug>/scene_N.png` 원본 PNG다.
- `STORY=`를 쓸 때는 `assets/story_drafts/<draft_slug>.json`처럼 `.json`까지 포함한
  파일 경로를 넘긴다. 예:
  `make generate-draft-story-images STORY=assets/story_drafts/20260624_cain_test_story.json`
- 기존 `make generate-story-images`처럼 `assets/200_stories` 전체나
  `assets/story_images` canonical 디렉토리를 prune하지 않는다.
- prompt 생성은 `story_scenes`, `scene_characters`, `characters`, `bible_ref`,
  인물 아바타 레퍼런스를 사용한다.

`make apply-draft` 원리:

- draft JSON schema를 검증한다. 필수 항목은 `title`, `summary`,
  `background_context`, 1개 이상 `story_scenes`, 장면 수와 같은
  `scene_captions`, 1~3개 `quiz_questions`다. 각 퀴즈는 질문, 3개 작성 선택지,
  `answer_index` 0~2, 해설이 필요하다.
- `DRAFT=<draft_slug>`는 `assets/story_drafts/<draft_slug>.json`으로 해석된다.
  `STORY=`를 직접 쓰려면 `.json` 파일 경로를 넘긴다.
- real 적용 전에는 항상 `DRY_RUN=1`로 먼저 확인한다. 예:
  `make apply-draft ENV=real DRAFT=20260624_cain_test_story PROPOSER_USER_ID=<Supabase auth.users.id> DRY_RUN=1`
- `PROPOSER_USER_ID`는 `event_proposals.proposer_user_id`에 들어갈 운영 Supabase
  `auth.users.id`다. 매번 넘기지 않으려면 `.env.ops`에
  `STORY_DRAFT_PROPOSER_USER_ID_PROD=<Supabase auth.users.id>`를 둔다.
- 같은 제목의 published event 또는 pending new proposal이 이미 있으면 중단한다.
- `assets/story_drafts/<draft_slug>/scene_N.png`가 `story_scenes` 길이만큼 있는지 확인한다.
- 원본 PNG를 `proposal-scenes/<proposer_user_id>/<draft_slug>/scene_N.png`로 업로드한다.
- `event_proposals`에 pending row를 만든다. 이때 `scene_image_paths`에는 업로드된
  Storage path가 들어간다.
- 이 단계는 아직 `events`를 바꾸지 않으므로 일반 사용자에게 노출되지 않는다.
- `db_init.sql`의 `event_proposals` CHECK 제약도 같은 최소 조건을 한 번 더 막는다.
  즉 service-role direct insert 도 incomplete new proposal을 만들 수 없다.

`make apply-drafts` 원리:

- `DRAFTS="slug1 slug2"`는 각각 `assets/story_drafts/<slug>.json`으로 해석한다.
- `STORIES="path/a.json path/b.json"` 또는 `STORIES_GLOB="assets/story_drafts/202606*.json"`도 사용할 수 있다.
- 내부적으로 같은 `apply_story_draft.py`가 각 JSON을 순차 처리한다. 하나가 실패하면 그 지점에서 중단되므로, real 전에는 `DRY_RUN=1`로 전체 후보를 먼저 확인한다.

관리자 승인 원리:

- 승인 RPC는 `insert_event_at_position(...)`을 통해 `events`에 published row를 만든다.
- 승인 다이얼로그에서 고른 위치는 `p_after_story_index_override`로 전달된다. 무효화된
  pending 제안도 관리자가 새 위치를 명시하면 바로 승인 가능하다.
- 같은 시대에서 `after_story_index + 1` 이후의 기존 row는 `story_index`가 +1 밀린다.
- 승인된 effective 위치와 같은 위치를 겨냥한 다른 pending 제안은
  `position_invalidated_at`이 set되어 위치 재선택 상태가 된다. 제안자가 직접 고쳐도 되고,
  관리자가 그 제안 승인 시 새 위치를 골라도 된다.
- proposal의 `scene_image_paths`가 `events.scene_image_paths`로 복사된다.
- 앱은 `events_ordered` view를 읽으므로 승인 직후부터 새 이야기를 볼 수 있다.
- 앱 번들에 아직 로컬 썸네일이 없으면 `scene_image_paths`를 public URL로 바꿔
  네트워크 이미지를 보여준다.

`make release-sync-stories` 원리:

1. real DB의 active published `events`(`status='published' AND deleted_at IS NULL`)를
   era별로 `assets/200_stories/*.json`에 export한다. export는
   `background_context`, `scene_captions`, `unit_code/unit_title/unit_order`를
   보존하고 stale era JSON 파일을 제거한다.
2. 같은 active events snapshot에 연결된 `quiz_questions`를 `assets/quizzes/*.json`으로
   export하고, `supabase/quizzes/db_events.json`을 갱신한다. snapshot에 없는 stale
   quiz JSON은 삭제해 reindex 뒤 옛 퀴즈가 새 번호의 다른 이야기에 붙지 않게 한다.
3. active events의 `events.landmark_id`를
   `assets/landmarks/event_region_mapping.json`으로 export한다.
4. 새 이야기 원본 이미지를 `assets/story_images/<title>/scene_N.png`로 둔다.
   로컬 draft 원본이 있으면 복사하고, 웹/앱에서 생성한 proposal이면
   `proposal-scenes`에서 다운로드한다.
5. 삭제 승인된 title은 active events에 없으므로
   `sync-approved-proposal-assets` Phase B가 로컬 `assets/story_images/<title>/`
   폴더를 제거한다. 과거 sync 버그로 공백이 `_`가 된 폴더는 canonical 제목 폴더로
   먼저 옮긴 뒤 비교한다.
6. `make thumbnails`로 현재 story JSON에 등장하는 title만 짧은 썸네일 디렉토리와
   `assets/story_images_thumbs/index.json`에 반영한다. 삭제된 원본 폴더가 남아 있어도
   current JSON에 없으면 앱 번들 썸네일로 다시 생성하지 않는다.
7. `make update-pubspec-assets`로 현재 썸네일 디렉토리를 앱 asset 목록에 등록한다.
8. 검증 후 커밋하고 새 앱을 빌드/배포한다.

예를 들어 4번과 8번 이야기를 삭제 승인한 뒤 새 이야기 2건을 2번 뒤/마지막 뒤에
승인해도, DB RPC가 active `story_index`를 1..N으로 유지한다. 이후
`make release-sync-stories ENV=real`을 실행하면 삭제된 title은 story JSON, quiz JSON,
thumbnail index, pubspec asset 목록에서 빠지고, 새 이야기는 proposal Storage의 이미지를
로컬 번들로 가져온다.

Storage cleanup은 앱 배포 직후 하지 않는다. 사용자가 앱을 업데이트하기 전까지는
구버전 앱이 `events.scene_image_paths`의 `proposal-scenes/...`를 읽을 수 있기 때문이다.
충분한 업데이트 기간이 지난 뒤에만 `sync-approved-proposal-assets-clean ENV=real` 같은
정리 명령을 검토한다.

#### 3.2.2 목사님 이야기 제안 Flow

목사님이 앱/웹 UI에서 직접 이야기를 제안하는 흐름도 같은 인프라를 쓴다. 차이는
draft JSON을 운영자가 만드는 대신, UI wizard가 같은 필드를 수집한다는 점이다.

UI가 반드시 수집해야 하는 현재 story 필드:

- `title`
- `summary`
- `background_context`
- `bible_refs`
- `characters`
- `landmark_id` 또는 `landmark_code`
- `start_year`, `end_year`, `time_precision`
- `after_story_index`
- `unit_code`, `unit_title`, `unit_order`
- `story_scenes`
- `scene_captions`
- `scene_characters`
- `scene_image_paths`, `scene_image_prompts`
- `quiz_questions`

목사님 제안 단계별 상태:

| 단계 | UI/사용자 행동 | DB | Storage | 앱 상태 |
|------|----------------|----|---------|---------|
| 작성 | wizard에서 본문/배경/장면/캡션/퀴즈 작성 | 변화 없음 또는 로컬 draft state | 이미지 생성 시 `proposal-scenes`에 upsert | 일반 사용자에게 안 보임 |
| 제출 | "제안 등록" | `event_proposals(status='pending')` insert | 생성된 scene path가 row에 연결 | 관리자/제안자는 proposal 상세에서 확인 |
| 검토 | 관리자 상세 화면 | 변화 없음 | 변화 없음 | 일반 사용자에게 안 보임 |
| 승인 | 관리자 승인 | `events` insert + index shift + quiz insert | proposal asset 유지 | 일반 사용자에게 즉시 노출. 앱 번들 전에는 Storage fallback |
| sync/배포 | 운영자 release sync | canonical 파일 갱신 | fallback 보호용 유지 | 새 앱 배포 후 로컬 썸네일 우선 |

현재 코드 기준으로는 목사님 제안 UI/RPC/model이 `background_context`,
`scene_captions`, unit 필드를 다룬다. 관리자는 상세 화면에서 배경 지식, 장면 원고,
장면 캡션, 시간순 구간을 함께 검수한 뒤 승인한다.

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

현재 개발 정책:

- `db_init.sql`이 schema 단일 진실 소스다.
- dev 는 reset 방식으로 최종 상태를 검증한다.
- real 은 reset 하지 않고 `supabase/patches/*.sql`로 기존 DB를 수정한다.

dev 검증 순서:

```bash
# 1. db_init.sql 수정
# 2. 필요하면 seed builder / seed SQL 수정
make seed-all
make db-init ENV=dev
make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
scripts/run_dev.sh
```

문서도 함께 갱신한다.

- schema/RLS/RPC/Edge Function: `docs/BACKEND.md`
- 데이터/Makefile 흐름: `docs/DATA_PIPELINE.md`
- 중요한 운영 결정: `docs/ADR.md`
- 신규 환경 구축/운영 순서: `docs/guides/DB_SETUP.md` 또는 이 문서

real 적용은 patch 방식으로 진행한다.

1. `db_init.sql`에는 최종 desired schema 를 계속 반영한다.
2. real 기존 DB 에 적용할 **idempotent patch SQL**을 `supabase/patches/`에 만든다.
3. patch 는 가능한 `alter table if exists`, `add column if not exists`,
   `create or replace function`, `drop policy if exists` 패턴으로 작성한다.
4. dev 에서 reset 검증 + patch 검증을 한다.
5. real 적용 전 백업을 만든다.
6. real 에 patch 를 적용한다.

```bash
make apply-patch ENV=dev PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
```

운영 patch 는 반드시 "여러 번 실행해도 안전한 SQL"이어야 한다. 신규 Supabase
프로젝트를 다시 만드는 복구 상황이 아니라면 `make db-init ENV=real`을 쓰지 않는다.

## 4. real 배포 Flow

real 배포는 변경 종류별로 다르게 간다.

### 4.1 앱 코드만 배포

DB 변경이 없다면:

```bash
scripts/run_dev.sh
flutter analyze
flutter test
scripts/run_real.sh
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

확인:

- 로그인 3종
- 홈 데이터 로드
- 푸시 토큰 등록
- 중요한 화면 진입

### 4.2 콘텐츠/seed 변경 배포

DB schema 변경 없이 seed 만 바뀌는 경우도 두 종류로 나눈다.

기존 이야기의 제목/요약/좌표/퀴즈/landmark처럼 이미지 번들 문제가 없는 변경:

```bash
make seed-all
make thumbnails
make update-pubspec-assets

make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
scripts/run_dev.sh

make apply-seeds ENV=real
make upload-character-avatars ENV=real
scripts/run_real.sh

scripts/build_android_real.sh
scripts/build_ios_real.sh
```

더 좁게 적용할 수 있으면 전체 `apply-seeds`보다 개별 target 을 쓴다.

신규 이야기를 추가하는 변경:

- `3.2.1 새 이야기 추가 Flow`를 우선한다.
- draft를 proposal로 올리고 관리자 승인으로 real DB에 삽입하면
  `events.scene_image_paths`가 채워져 새 앱 배포 전에도 Storage fallback이 동작한다.
- release sync로 canonical JSON/quiz/mapping/original/thumb/pubspec을 만든 뒤 새 앱을
  배포한다.
- 직접 seed apply로 새 이야기를 공개하는 방식은 구버전 앱 이미지 공백과
  중간 삽입 row id 위험이 있으므로 예외 경로로 본다.

표준 배포 순서:

```bash
# 1. draft 작성 + 이미지 생성
make generate-draft-story-images STORY=assets/story_drafts/YYYYMMDD_slug.json

# 2. real 적용 전 dry-run
make apply-draft ENV=real DRAFT=YYYYMMDD_slug PROPOSER_USER_ID=<Supabase auth.users.id> DRY_RUN=1

# 3. proposal row 생성 + proposal-scenes 업로드
make apply-draft ENV=real DRAFT=YYYYMMDD_slug PROPOSER_USER_ID=<Supabase auth.users.id>

# 4. 관리자 UI 승인 후 release sync
make release-sync-stories ENV=real

# 5. 검증 + real 앱 빌드
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

`generate-draft-story-images`, `apply-draft`, `apply-drafts`, `release-sync-stories`는
현재 Make target으로 제공된다. `release-sync-stories`는 stories, quizzes,
event-region mapping, approved proposal assets, thumbnails, pubspec을 함께 갱신한다.

### 4.3 schema 변경 배포

schema 변경 배포:

```bash
make seed-all
make thumbnails
make update-pubspec-assets

make db-init ENV=dev
make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
scripts/run_dev.sh

# real
# 1. 백업
# 2. idempotent patch SQL 적용
# 3. 필요한 seed 만 적용
# 4. 앱 smoke test
# 5. real build
make apply-patch ENV=real PATCH=supabase/patches/YYYYMMDD_HHMM_description.sql
make apply-seeds ENV=real
make upload-character-avatars ENV=real
scripts/run_real.sh
```

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
- schema 변경이면 `supabase/patches/*.sql`이 있고 dev에서 먼저 적용/검증했는지 확인.
- real 에 `db-init`을 실행하지 않는지 확인.
- seed 만 바뀐 변경이면 개별 `apply-seeds-* ENV=real`로 충분한지 확인.
- `flutter analyze`, 관련 `flutter test` 통과.
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
- real 을 기본값으로 쓰지 않는다.
- real `db-init`은 기본 차단되며, 운영 DB 변경은 `apply-patch`로 한다.

핵심 운영 결정:

> real 은 reset 방식 배포를 멈추고 `supabase/patches/*.sql` 기반의
> idempotent patch 방식으로 수정한다.
