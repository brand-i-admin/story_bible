# Make target 운영 지도

> `Makefile`은 Story Bible 데이터/이미지/DB/Storage 작업의 진입점이다. 이 문서는
> 각 target이 내부적으로 무엇을 읽고, 무엇을 만들고, 원격 상태를 바꾸는지 설명한다.

문서 계층: 이 문서는 [develop-flow.md](develop-flow.md)를 보조하는 Make target
하위 문서다. 개발/배포 판단은 develop-flow에서 하고, 여기서는 target별 입력,
출력, 원격 영향만 확인한다.

## 0. 먼저 알아야 할 원칙

`make` target은 크게 네 종류다.

| 종류 | 예 | 원격 변경 | 주의 |
|------|----|-----------|------|
| 로컬 생성 | `seed-stories-characters`, `thumbnails`, `update-pubspec-assets` | 없음 | git diff 검토 후 커밋 |
| 원격 DB 적용 | `apply-seeds-stories-characters ENV=real` | Postgres 변경 | `.env.ops`의 DB URL 사용 |
| 원격 Storage 변경 | `upload-character-avatars ENV=real` | Supabase Storage 변경 | service role 사용 |
| 앱 실행/빌드 | `scripts/build_android_real.sh` | 없음 | `.env`의 공개 URL/anon key만 주입 |

기본 `ENV`는 `dev`다. real 운영 DB/Storage에 적용할 때만 `ENV=real`을 명시한다.
Makefile 내부에서는 `ENV=real`과 `ENV=prod`가 운영 suffix `PROD`로 매핑된다.

```bash
make -n apply-seeds-stories-characters ENV=real
make -n upload-character-avatars ENV=real
```

`make -n`은 실제 실행 없이 어떤 명령이 호출될지 보여 준다. 원격을 바꾸는 target은
먼저 `make -n`으로 env 매핑을 확인하는 습관이 좋다.

## 1. 신규 이야기 중간 삽입에서 가장 위험한 부분

중간에 이야기를 하나 끼워 넣으면 같은 시대의 뒤쪽 `story_index`가 모두 밀린다.
이때 real DB에 **seed만 바로 적용하면 안 된다.**

왜냐하면 `events` seed의 UPSERT 키가 `(era_id, story_index)`이기 때문이다.
예를 들어 기존 5번 자리에 새 이야기를 넣고 로컬 JSON을 5..N+1로 재번호 매긴 뒤
곧바로 `make apply-seeds-stories-characters ENV=real`을 실행하면, DB의 기존
5번 row가 새 이야기 내용으로 업데이트될 수 있다. 그러면 그 row의 `events.id`를
붙잡고 있던 저장한 이야기, 읽기 진행도, 퀴즈 기록이 다른 이야기로 보이는 문제가 생긴다.

real에서 중간 삽입을 안전하게 하려면 먼저 DB에서 기존 row의 `story_index`를 뒤로
밀어 **기존 row id를 보존**하고, 새 row를 insert해야 한다. 이 로직은 DB RPC
`insert_event_at_position(...)` 안에 있지만, 현재 로컬 JSON 기반 운영을 위한
별도 Make target으로 포장되어 있지는 않다.

안전한 운영 선택지는 세 가지다.

| 선택 | 언제 사용 | 설명 |
|------|-----------|------|
| 맨 뒤 추가 | 순서상 뒤에 붙여도 될 때 | 기존 `story_index`가 안 밀려 seed apply가 단순하다. |
| proposal 승인 경로 | 중간 삽입 + 배포 전 이미지 fallback이 필요할 때 | draft를 proposal로 올리고 관리자 승인 RPC가 `insert_event_at_position(...)`을 호출한다. |
| DB 위치 삽입 patch/RPC 먼저 | 관리자가 직접 SQL로 처리해야 할 때 | `insert_event_at_position(...)` 또는 별도 idempotent patch로 DB row를 먼저 shift+insert한다. |
| 새 앱 출시 이후 공개 지연 | 이미지/순서 리스크를 줄이고 싶을 때 | 앱 번들에 새 썸네일이 포함된 뒤 real 공개한다. |

중간 삽입 후 canonical JSON도 결국 새 순서와 같아야 하므로, DB에서 안전하게 shift+insert한
뒤에는 release sync로 DB 상태를 `assets/events` 통합 JSON,
원본 이미지, thumbnails, `pubspec.yaml`에 반영한다.

## 2. 이야기/인물 seed 생성 target

이 섹션의 seed/이미지 생성 target은 기본적으로 `STORIES_DIR=assets/initial_seed_events`를 읽는다.
`assets/initial_seed_events`는 초기 DB bootstrap과 레거시 원본 보존용 소스다. 운영 중
승인/삭제/재정렬이 반영된 DB active snapshot으로 seed 산출물을 만들 필요가 있을 때만
`STORIES_DIR=assets/events`를 명시한다.

### `make export-stories-json`

DB의 active `events`를 `assets/events/*.json`으로 역추출한다. 각 event row에는
`landmark_code`와 연결된 `quiz_questions`가 함께 들어간다.

- 입력: 원격 DB의 `status='published' AND deleted_at IS NULL` events, landmarks, quiz_questions
- 출력: `assets/events/*.json`
- 원격 변경: 없음, 읽기만 함
- 정리: 현재 active export에 없는 stale era JSON 파일을 제거한다.
- 주의: 로컬 JSON을 덮어쓸 수 있으므로 `git status --short assets/events`를 먼저 본다.

### `make renumber-story-indices`

로컬 JSON의 `story_index`를 시대별 1..N으로 재정렬한다.

- 입력: `$(STORIES_DIR)/*.json` (기본 `assets/initial_seed_events`)
- 출력: 같은 JSON 파일 수정
- 원격 변경: 없음
- 주의: real에 이미 공개된 중간 삽입에는 이것만 믿고 seed apply하지 않는다. §1의 row id 보존 문제가 있다.

### `make seed-stories-characters`

이야기와 인물 SQL을 함께 생성한다.

내부 흐름:

1. `build-character-meta`
2. `tools/seed/build_events_seed_sql.py`
3. `tools/seed/build_characters_seed_sql.py`

입력과 출력:

| 입력 | 출력 |
|------|------|
| `$(STORIES_DIR)/*.json` (기본 `assets/initial_seed_events`) | `supabase/events/events_seed.sql` |
| 각 event row의 `landmark_code` | `supabase/events/events_seed_part_*.sql` |
| `tools/seed/character_meta.json` 생성물 | `supabase/events/characters_seed.sql` |

이 target은 로컬 파일만 만든다. DB에는 적용하지 않는다.

중요한 동작:

- 모든 이야기에 정수 `story_index`가 있어야 한다.
- 각 이야기에 `landmark_code`가 있어야 하고, 그 code가 `assets/landmarks/landmarks.json`에 있어야 한다.
- 생성된 events SQL은 `(era_id, story_index)` 기준으로 UPSERT한다.
- `part_01`에는 JSON에 없는 활성 `(era_id, story_index)`를 삭제하는 stale 정리가
  들어간다. 삭제 제안 승인으로 `deleted_at` 이 set 된 row 는 사용자 진행도/제안
  이력 보존을 위해 stale 정리에서 hard delete 하지 않는다.

### `make seed-quizzes`

퀴즈 SQL을 생성한다.

- 입력: `$(STORIES_DIR)/*.json` 안의 `quiz_questions` (기본 `assets/initial_seed_events`)
- 출력: `supabase/quizzes/quizzes_seed.sql`, `quizzes_report.json`
- 원격 변경: 없음
- 주의: 같은 event row의 `bible_ref` 범위 안에 해설 절 근거가 있어야 한다.

### `make seed-landmarks`

랜드마크 SQL을 생성한다.

- 입력: `assets/landmarks/landmarks.json`
- 출력: `supabase/events/landmarks_seed.sql`
- 원격 변경: 없음

## 3. 이미지와 앱 번들 asset target

### `make generate-story-images`

로컬 이야기 JSON의 `story_scenes`를 기준으로 Vertex AI 장면 이미지를 만든다.

- 입력: `$(STORIES_DIR)/*.json` (기본 `assets/initial_seed_events`), `.env`의 `GOOGLE_CLOUD_PROJECT`
- 출력: `assets/story_images/<title>/scene_N.png`
- 원격 변경: 없음
- 비용: Vertex AI 호출 비용 발생 가능
- 주의: 기존 PNG가 있으면 skip한다. 마음에 안 드는 장면은 해당 PNG를 지운 뒤 다시 실행한다.

### `make generate-draft-story-images STORY=...`

신규 이야기 draft JSON 하나만 기준으로 Vertex AI 장면 이미지를 만든다.

- 입력: `assets/story_drafts/YYYYMMDD_slug.json`, `.env`의 `GOOGLE_CLOUD_PROJECT`
- 출력: `assets/story_drafts/YYYYMMDD_slug/scene_N.png`
- 원격 변경: 없음
- 비용: Vertex AI 호출 비용 발생 가능
- 주의: canonical `assets/events`나 `assets/story_images`를 prune하지 않는다.
  `DRAFT=YYYYMMDD_slug`를 쓰면 `assets/story_drafts/YYYYMMDD_slug.json`으로 해석한다.

이 target은 새 이야기 표준 흐름에서 `make generate-story-images`를 대체한다.
`generate-story-images`는 전체 canonical 이야기 세트를 대상으로 하므로 draft 한 건을
운영하기에는 범위가 넓다.

### `make thumbnails`

앱 런타임용 썸네일을 만든다.

- 입력: `assets/story_images/`, `assets/avatars/`, `$(THUMBNAIL_STORIES_DIR)/*.json` (기본 `assets/events`)
- 출력: `assets/story_images_thumbs/<era_slug>_<story_index>/scene_N.jpg`, `assets/story_images_thumbs/index.json`, `assets/avatars_thumbs/*.png`
- 원격 변경: 없음
- 전제: current `assets/events/*.json`에 들어 있는 모든 active story title에 대해
  `assets/story_images/<safe title>/scene_*.png` 원본이 로컬에 있어야 한다.

`assets/story_images_thumbs/index.json`은 한글 제목 기반 원본 폴더와 짧은 런타임 폴더를
연결한다. Android/iOS asset 경로 길이 문제를 피하려고 짧은 폴더를 쓴다.
썸네일 생성 대상은 current story JSON에 등장하는 title 폴더뿐이다. 스크립트는 먼저
current story 전체에 대응하는 원본 PNG가 있는지 검사하고, 통과한 뒤
`assets/story_images_thumbs/`의 story 하위 디렉토리를 모두 지운 다음 현재
`era + story_index` 기준으로 다시 만든다. 삭제 승인 후 로컬
`assets/story_images/<삭제된 제목>/` 원본 폴더가 남아 있어도 current JSON에 없으면 앱
번들 썸네일로 다시 생성하지 않는다.

이 clean rebuild는 중간 삽입/삭제 때문에 필요하다. 예를 들어 기존 `primeval_004`가
요셉 이야기였는데 새 이야기가 앞에 들어와 `primeval_004`가 다른 이야기를 가리키게 되면,
mtime 기반 skip만으로는 옛 JPG가 같은 폴더에 남을 수 있다. 전체 story thumb 디렉토리를
비우고 다시 만들면 경로 재사용과 실제 이미지가 항상 current JSON 기준으로 맞는다.

`assets/story_images/`는 `.gitignore` 대상인 원본 staging 디렉토리다.
이미 sync가 끝난 커밋을 단순히 앱 빌드만 하는 컴퓨터는 git에 포함된
`assets/story_images_thumbs/`로 충분하지만, `make thumbnails`나
`make release-sync-stories`를 실행하는 release builder는 원본 PNG 전체가 필요하다.
원본이 빠진 상태에서 삭제/reindex가 반영되면 `<era_slug>_<story_index>` 폴더가
이전 이야기 이미지를 가리킬 수 있으므로, 스크립트는 누락 원본을 발견하면 실패한다.

### `make update-pubspec-assets`

Flutter가 새 썸네일 폴더를 번들에 포함하도록 `pubspec.yaml`의 assets 블록을 갱신한다.

- 입력: `assets/story_images_thumbs/index.json`, 하위 폴더 목록
- 출력: `pubspec.yaml`
- 원격 변경: 없음

이 target을 빼먹으면 로컬에는 JPG가 있어도 새 앱 번들에 포함되지 않는다.

### `make ensure-story-image-sources ENV=real`

release builder의 로컬 원본 캐시를 private source archive에서 채운다.

- 입력: `assets/events/*.json`, Supabase Storage private bucket
  `story-image-sources`
- 출력: missing/changed `assets/story_images/<safe title>/scene_*.png`
- 원격 변경: 없음
- dry-run: `make ensure-story-image-sources-dry ENV=real`

이 target은 `story-image-sources/_manifests/story_images_manifest.json`의
`size`/`sha256`과 로컬 파일을 비교한다. remote manifest가 없고 로컬 원본이 이미
완전하면 통과한다. 이 경우 다음 `upload-story-image-sources`가 현재 로컬 전체를 최초
seed 한다. remote manifest도 없고 로컬 원본도 없으면 복구할 출처가 없으므로 실패한다.

### `make upload-story-image-sources ENV=real`

release builder의 로컬 원본 캐시를 private source archive로 밀어 올린다.

- 입력: `assets/events/*.json`, `assets/story_images/<safe title>/scene_*.png`
- 출력: `story-image-sources/story_images/<source_key>/scene_*.png`,
  `story-image-sources/_manifests/story_images_manifest.json`
- 원격 변경: private bucket 생성, 신규/변경 object upsert, stale object 삭제,
  active manifest 갱신
- dry-run: `make upload-story-image-sources-dry ENV=real`

`story-image-sources`는 앱 런타임용 public bucket이 아니라 release-only private bucket이다.
`db_init.sql`에는 bucket 정의가 있지만 `make db-init` 전 purge 대상이 아니므로,
`characters`/`proposal-scenes`/`proposal-characters`를 초기화해도 이 원본 archive는
비워지지 않는다. 원격 object path는 한글 title이 아니라
`story_images/<source_key>/scene_*.png` 형식의 ASCII key를 쓰고, 실제 title/source_dir은
manifest에 보존한다.

push 계획의 기준:

- old manifest에 없고 current active local set에 있는 object: upload
- old manifest와 같은 `object_path`지만 `size` 또는 `sha256`이 다름: upsert overwrite
- old manifest와 current active local set이 같은 `size`/`sha256`: skip
- old manifest에는 있지만 current active local set에는 없음: delete_stale

`delete_stale`는 bucket 전체를 훑어서 지우는 것이 아니라 이전 manifest entries와 현재
active entries의 차이만 대상으로 한다. manifest에 기록되지 않은 수동 object는 이 target이
삭제하지 않는다.

## 3.1 Draft / proposal 운영 target

### `make apply-draft ENV=real STORY=...`

운영자가 만든 draft를 proposal 대기열로 올린다.

- 입력: `assets/story_drafts/YYYYMMDD_slug.json`,
  `assets/story_drafts/YYYYMMDD_slug/scene_N.png`
- 원격 DB 변경: `event_proposals(status='pending')` insert
- 원격 Storage 변경: `proposal-scenes/<uid-or-system>/<draft>/scene_N.png` 업로드
- 필요 환경값: `.env.ops`의 `SUPABASE_SERVICE_ROLE_KEY_DEV/PROD`,
  `STORY_DRAFT_PROPOSER_USER_ID_DEV/PROD`
- dry-run: `make apply-draft ENV=real STORY=... DRY_RUN=1`
- 검증: `background_context`, 장면/캡션 수, 장면 이미지 수, 퀴즈 1~3개,
  퀴즈 선택지/정답/해설, 기존 event/pending proposal 제목 중복을 확인한 뒤 업로드한다.
- 주의: 아직 `events`를 만들지 않으므로 일반 사용자에게는 보이지 않는다. 관리자 UI에서
  승인해야 `approve_event_proposal`이 `events`와 `quiz_questions`를 만든다.

### `make apply-drafts ENV=real DRAFTS="a b"`

여러 draft JSON을 순차적으로 proposal 대기열에 올린다.

```bash
make apply-drafts ENV=real DRAFTS="20260623_elijah_ravens 20260624_amos_call"
make apply-drafts ENV=real STORIES="assets/story_drafts/a.json assets/story_drafts/b.json"
make apply-drafts ENV=real STORIES_GLOB="assets/story_drafts/202606*.json"
```

- 입력: 각 draft JSON과 같은 이름의 이미지 폴더
- 원격 DB/Storage 변경: `apply-draft`를 각 파일에 순차 적용
- dry-run: `DRY_RUN=1`
- 주의: 여러 proposal이 같은 era + 같은 after 위치를 겨냥할 수 있다. 승인 시 관리자
  UI에서 위치 override를 고르면 그 자리로 바로 재배치 승인되고, 같은 effective 위치의
  다른 pending 제안은 위치 재선택 상태로 잠긴다.

### `make release-sync-stories ENV=real`

관리자 승인 후 real DB 상태를 다음 앱 배포용 로컬 canonical 파일로 되돌린다.

- 실행 순서: `export-stories-json` → `sync-approved-proposal-assets --skip-post-processing` →
  `ensure-story-image-sources` → `thumbnails` → `update-pubspec-assets` →
  `upload-story-image-sources`
- 입력: DB의 active published events, quiz_questions, landmarks, 승인 proposal assets
- 출력: `assets/events/*.json`, `assets/story_images/<title>/scene_N.png`,
  `assets/story_images_thumbs/`,
  `pubspec.yaml`
- 원격 변경: `sync-approved-proposal-assets` 단계에서 신규 캐릭터 이미지를
  `characters` 버킷으로 복사하고 `characters.avatar_storage_path`를 갱신할 수 있다.
- 여러 approved proposal과 delete approval이 한 번에 쌓여 있어도 DB의 현재 active
  published 상태 전체를 release canonical 파일로 되돌린다.
- 삭제 승인된 이야기는 DB row가 `deleted_at`으로 보존되어도 export에서 제외된다.
  `sync-approved-proposal-assets` Phase B가 active title diff로 로컬
  `assets/story_images/<삭제된 제목>/` 폴더를 제거하고, `thumbnails`가 story thumb
  디렉토리를 current JSON 기준으로 clean rebuild한다.
- `assets/story_images/` 원본은 git에 없으므로, 이 target은 원본이 복원된 release
  builder에서 실행해야 한다. 다른 컴퓨터에서 실행할 때는 먼저
  `make ensure-story-image-sources-dry ENV=real`로 source archive 상태를 확인하고,
  필요하면 `make ensure-story-image-sources ENV=real`로 missing/changed 원본을 내려받는다.
  `release-sync-stories` 안에도 이 pull 단계가 포함되어 있다. proposal-backed 신규
  이야기의 경우 `proposal-scenes`에 남아 있는 원본도 sync 단계에서 내려받지만, 초기 seed
  이야기처럼 proposal 원본이 없는 이미지는 `story-image-sources` archive 없이는
  재생성할 수 없다.
- 원본 archive는 매 release마다 2GB+ 전체를 다시 받거나 올리는 대상이 아니다. 원격
  private bucket(Supabase/GCS 등)을 권위 저장소로 두고, release builder의
  `assets/story_images/`는 로컬 캐시로 취급한다. manifest/etag/sha256 기준으로
  missing/changed PNG만 다운로드하고, proposal 승인으로 새로 생긴 story 폴더만 업로드하는
  delta sync가 효율적이다.
- release sync가 끝난 뒤에는 `make upload-story-image-sources-dry ENV=real`로 새로 올릴
  원본이나 지울 stale object가 남았는지 확인할 수 있다. 정상적으로 push까지 끝났다면 보통
  `upload=0, skip=<현재 원본 수>, delete_stale=0`이 나온다.

예: 같은 era에서 4번과 8번을 삭제 승인하고, 새 이야기 2건을 각각 2번 뒤와 마지막에
승인한 뒤 이 target을 실행하면, DB의 active `story_index=1..N` 상태가 그대로
`assets/events`, `story_images_thumbs`,
`pubspec.yaml`에 반영된다. 삭제된 title은 통합 events JSON과 썸네일 디렉토리에 남지 않는다.

## 4. DB 적용 target

### `make apply-seeds-stories-characters ENV=dev|real`

생성된 characters/events SQL을 DB에 적용한다.

- 입력: `.env`, `.env.ops`, `characters_seed.sql`, `events_seed_part_*.sql`
- 원격 변경: `characters`, `events`
- Storage 업로드: 하지 않음

중요한 사실:

- 이 target은 `events.scene_image_paths`를 자동으로 채우지 않는다.
- 이 target은 `assets/story_images_thumbs/`를 Storage에 올리지 않는다.
- real에 적용하면 `status='published'`인 새 이야기가 즉시 사용자에게 보인다.

### `make apply-seeds-quizzes ENV=dev|real`

`quiz_questions`를 적용한다.

- 입력: `supabase/quizzes/quizzes_seed.sql`
- 원격 변경: 이벤트별 기존 quiz delete 후 insert
- 주의: 이벤트 row가 먼저 존재해야 한다.

### `make apply-seeds-landmarks ENV=dev|real`

랜드마크를 적용한다.

- 입력: `supabase/events/landmarks_seed.sql`
- 원격 변경: `landmarks`
- 주의: 새 이야기의 `landmark_id`가 새 landmark를 참조하면 stories보다 먼저 적용한다.

## 5. Storage target

### `make upload-character-avatars ENV=dev|real`

캐릭터 아바타를 `characters` 버킷에 업로드한다.

- 입력: `assets/avatars/*.png`, `.env`, `.env.ops`의 service role key
- 원격 변경: Supabase Storage `characters/`, DB `characters.avatar_storage_path`
- 주의: 기본 target은 `characters` 버킷을 먼저 비우고 새로 업로드한다.

이 target은 이야기 장면 이미지나 썸네일을 업로드하지 않는다.

### `make sync-approved-proposal-assets ENV=dev|real`

승인된 proposal 이미지를 로컬 canonical assets로 동기화한다.

- 입력: `event_proposals`, active/deleted `events`, `characters`, `proposal-scenes`, `proposal-characters`
- 출력: `assets/story_images/`, `assets/avatars/`
- 원격 변경: 신규 캐릭터 이미지를 `characters` 버킷으로 복사하고 `characters.avatar_storage_path` 갱신 가능

이 target은 proposal asset sync의 기반이다. 신규 이야기 표준 흐름에서는
`release-sync-stories`가 이 target을 포함해 DB → canonical JSON export, thumbnails,
pubspec 갱신까지 이어서 실행한다.
Phase A는 unsynced approved proposal 이미지를 내려받고 marker를 set한다. Phase B는
active event title 집합에 없는 로컬 story image 폴더를 제거하고, soft-deleted events의
Storage fallback을 best-effort로 지운다. 과거 underscore 폴더명은 canonical 제목 폴더로
마이그레이션한다.

### 직접 seed 경로에 없는 target: 이야기 썸네일 Storage 업로드

직접 `assets/events` seed를 real에 적용하는 경로에는 다음 일을 자동으로 하는
Make target이 없다.

1. `assets/story_images/<title>/scene_N.png` 또는 `assets/story_images_thumbs/.../scene_N.jpg`를 public Storage에 업로드
2. 업로드 path를 `events.scene_image_paths`에 patch
3. 구버전 앱이 새 앱 배포 전에도 Storage fallback으로 장면 이미지를 보게 함

구버전 앱까지 이미지 빈 상태 없이 보장해야 한다면 이 운영 도구를 먼저 만들어야 한다.
그 전에는 real 공개를 새 앱 출시 이후로 늦추는 것이 가장 단순하다.

Storage path만 채운다고 모든 썸네일 위치가 자동으로 해결되는 것도 아니다.
현재 fallback은 `SceneAssetLoader.loadForEvent(..., publicUrlFor: ...)`를 호출하는
화면에서 동작한다. 상세 화면의 큰 장면 row는 이 경로를 쓰지만, 지역 카드/이전·다음
카드 같은 작은 썸네일까지 완전 보장하려면 앱 호출부도 같이 점검한다.

## 6. 검증 target과 명령

```bash
make check-pubspec-assets
python3 tools/app/verify_asset_paths.py
python3 tools/seed/verify_polygons_contain_events.py
python3 tools/lint/check_forbidden_patterns.py
```

검증 의미:

| 명령 | 확인하는 것 |
|------|-------------|
| `make check-pubspec-assets` | `pubspec.yaml`의 story thumbnail assets 블록 최신성 |
| `verify_asset_paths.py` | pubspec에 등록된 파일/디렉토리가 실제 존재하는지 |
| `verify_polygons_contain_events.py` | event의 `landmark_code` 좌표가 해당 region polygon 안에 있는지 |
| `check_forbidden_patterns.py` | JWT/API key/금지 `print` 등 커밋 차단 패턴 |

## 7. 새 이야기 작업 추천 순서

맨 뒤에 추가하는 단순 케이스:

```bash
make seed-stories-characters
make seed-quizzes              # 퀴즈가 있으면
make generate-story-images
make thumbnails
make update-pubspec-assets
make apply-seeds-stories-characters ENV=dev
make apply-seeds-quizzes ENV=dev
scripts/run_dev.sh
```

real 공개:

```bash
scripts/build_android_real.sh
scripts/build_ios_real.sh
# Store 출시 준비/심사 후
make apply-seeds-stories-characters ENV=real
make apply-seeds-quizzes ENV=real
```

중간 삽입 케이스:

1. seed-only 적용 금지.
2. DB에서 `insert_event_at_position(...)` 또는 별도 patch로 기존 row를 shift+insert.
3. `make export-stories-json ENV=real` 또는 수동 JSON 정리로 로컬 canonical 순서 동기화.
4. 이미지 생성, 썸네일, pubspec 갱신, 앱 빌드.
5. 필요할 때만 seed apply로 canonical 내용을 재확인.
