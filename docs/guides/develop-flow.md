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

### 3.2 공개 콘텐츠나 seed 를 바꾸는 경우

예:

- `assets/200_stories/*.json` 수정
- 인물 설명, 사건, landmark, quiz 수정
- 썸네일 대상 이미지 추가
- seed builder 수정

순서:

1. 로컬 JSON 이 DB 와 맞는지 확인한다.
2. 필요한 JSON/assets 를 수정한다.
3. seed SQL 을 재생성한다.
4. dev DB 에 적용한다.
5. dev 앱에서 확인한다.
6. 문제가 없으면 real 에 같은 seed 를 적용한다.

기본 명령:

```bash
make seed-all
make thumbnails
make update-pubspec-assets
make apply-seeds ENV=dev
make upload-character-avatars ENV=dev
scripts/run_dev.sh
```

real 적용:

```bash
make apply-seeds ENV=real
make upload-character-avatars ENV=real
scripts/run_real.sh
```

주의:

- seed 만 바꾼 경우 보통 `db-init`까지 할 필요는 없다.
- `apply-seeds-stories-characters`, `apply-seeds-landmarks`, `apply-seeds-quizzes`처럼
  필요한 타겟만 적용하는 것이 더 안전할 때가 많다.
- KRV 성경 구절 seed 는 중복 INSERT 시 에러가 날 수 있으므로 최초 bootstrap 뒤에는
  매번 다시 넣는 대상으로 보지 않는다.

필요한 타겟만 적용하는 예:

```bash
# 사건/인물만 바뀐 경우
make seed-stories-characters
make apply-seeds-stories-characters ENV=dev
make apply-seeds-stories-characters ENV=real

# 퀴즈만 바뀐 경우
make seed-quizzes
make apply-seeds-quizzes ENV=dev
make apply-seeds-quizzes ENV=real

# schema/RPC 만 바뀐 경우
make apply-patch ENV=dev PATCH=supabase/patches/<file>.sql
make apply-patch ENV=real PATCH=supabase/patches/<file>.sql
```

### 3.2.1 신규 이야기 추가 Flow

새 이야기는 일반 seed 변경보다 조심해서 배포한다. 특히 **중간 삽입**은
`story_index`가 뒤쪽 이야기 전체에 영향을 주므로 seed-only 적용을 피한다.

현재 코드 기준 결론:

| 질문 | 답 |
|------|----|
| 새 이야기 DB seed apply가 장면 이미지를 Storage에 자동 업로드하는가? | 아니다. `apply-seeds-stories-characters`는 DB만 바꾸고 Storage는 건드리지 않는다. |
| 로컬 썸네일이 앱 번들에 들어가는가? | `make thumbnails` + `make update-pubspec-assets` 후 새 앱을 빌드해야 들어간다. |
| 새 앱 배포 전 real DB에 먼저 공개하면 구버전 앱도 이미지가 보장되는가? | 기본 흐름에서는 보장되지 않는다. `events.scene_image_paths` fallback이 비어 있기 때문이다. |
| 현재 로컬 canonical 이미지를 Storage에 올리고 `scene_image_paths`를 채우는 Make target이 있는가? | 없다. 필요하면 별도 운영 도구/patch를 먼저 만들어야 한다. |

이미지 로딩 원리:

1. 새 앱 번들 안의 `assets/story_images_thumbs/<short_dir>/scene_N.jpg`
2. 번들에 없으면 DB의 `events.scene_image_paths`를 Supabase Storage public URL로 변환
3. 둘 다 없으면 이미지 row를 숨김

이 fallback은 `SceneAssetLoader.loadForEvent(..., publicUrlFor: ...)`를 호출하는
화면에서만 동작한다. 현재 상세 화면의 큰 장면 row는 이 경로를 쓰지만, 모든 작은
카드 썸네일까지 완전 보장하려면 호출부 패치가 더 필요할 수 있다. 그러므로 새 앱
배포 전 구버전 사용자에게 이미지까지 확실히 보이게 하려면 Storage 업로드 도구와
앱 fallback 범위를 함께 점검한다.

`assets/200_stories/*.json`으로 만든 canonical seed는 기본적으로
`scene_image_paths`를 채우지 않는다. real에 바로 `apply-seeds-stories-characters
ENV=real`을 하면 새 이야기는 DB에 `published`로 보이지만, 아직 새 앱을 받지 못한
사용자는 새 썸네일 번들이 없고 DB fallback도 없어서 장면 이미지가 비어 보일 수 있다.

중간 삽입의 DB 적용 원리:

- `events`에는 `(era_id, story_index)` unique 제약이 있다.
- generated seed는 같은 `(era_id, story_index)`를 만나면 그 row를 update한다.
- 따라서 기존 5번 자리에 새 이야기를 넣고 뒤쪽 index를 전부 재번호 매긴 뒤,
  seed만 바로 real에 apply하면 기존 5번 row의 `events.id`가 새 이야기 내용으로
  바뀔 수 있다.
- `saved_events`, `user_event_progress`, `quiz_questions`, 감정 표시 등은
  `event_id`를 참조하므로, 운영 DB에서는 기존 이야기 row id를 보존해야 한다.
- 안전한 중간 삽입은 DB에서 먼저 뒤쪽 row의 `story_index`를 +1 shift하고 새 row를
  insert한 뒤, 로컬 JSON/seed를 그 상태에 맞추는 방식이다. 이 로직은
  `insert_event_at_position(...)` RPC에 있지만, 현재 Make target으로 포장되어 있지는 않다.

Make target별 내부 동작은 [MAKE_TARGETS.md](MAKE_TARGETS.md)를 먼저 확인한다.

#### dev에서 만드는 순서

```bash
# 0. 로컬 stories JSON 이 DB와 맞는지 먼저 확인
#    DB에서 복원해야 할 때만 실행한다. 작업 중인 로컬 JSON이 있으면 먼저 diff 확인.
# make export-stories-json ENV=dev

# 1. assets/200_stories/*.json 에 신규 이야기 추가
# 2. assets/landmarks/event_region_mapping.json 에 (era, story_index) 매핑 추가
# 3. 필요한 경우 퀴즈/landmark/인물 메타도 같이 수정

# 4. seed 생성
make seed-stories-characters
make seed-quizzes          # 신규 이야기 퀴즈가 있으면
make seed-landmarks        # landmark가 바뀌었으면

# 5. 이미지 생성과 앱 번들 갱신
make generate-avatars      # 신규 인물이 있으면
make generate-story-images # 신규 이야기 장면 이미지
make thumbnails
make update-pubspec-assets

# 6. dev DB에 먼저 적용하고 앱에서 확인
make apply-seeds-stories-characters ENV=dev
make apply-seeds-quizzes ENV=dev       # 퀴즈가 있으면
scripts/run_dev.sh
```

dev에서 확인할 것:

- 지도/지역/인물 탭에서 새 이야기가 의도한 위치에 보이는지
- 상세 화면에서 장면 4장이 보이는지
- 큰 글자/작은 화면에서 텍스트가 깨지지 않는지
- 신규 인물 카드와 아바타가 보이는지
- 퀴즈를 추가했다면 퀴즈 진입과 정답 처리

추가 주의:

- `assets/landmarks/event_region_mapping.json`에 새 `(era, story_index)` 매핑이 없으면
  `make seed-stories-characters`가 실패한다.
- `title`에는 `001` 같은 번호 prefix를 붙이지 않는다. 순서는 `story_index`가 결정한다.
- 인물 필드는 `characters`를 쓴다. 예전 문서의 `persons`는 현재 포맷이 아니다.
- 퀴즈를 추가하면 현재 Makefile 기준으로 `supabase/quizzes/db_events.json`에도
  `{era_code, story_index, title}` 항목을 추가해야 `make seed-quizzes`의
  orphan 검사를 통과한다.

#### real 배포 원칙

새 이야기를 real에 공개하는 타이밍은 앱 배포와 묶어서 본다.

안전한 기본 원칙:

- real DB에 새 이야기를 공개하기 전에 real 앱 빌드를 먼저 준비한다.
- 새 앱이 Store 심사를 통과하고 출시될 준비가 되기 전까지는 real에
  canonical seed를 적용하지 않는다.
- real에 먼저 적용해야 한다면 `scene_image_paths` fallback을 채워야 한다.
- 중간 삽입이면 seed apply 전에 DB row shift+insert 절차로 기존 `events.id`를
  보존한다. seed-only 재번호 적용은 금지한다.

#### 권장 A: Store 출시 후 real 공개

이미지 fallback 없이 가장 단순한 방법이다.

```bash
# dev에서 검증 완료 후
scripts/run_real.sh
scripts/build_android_real.sh
scripts/build_ios_real.sh
```

이 빌드를 Play Console / App Store Connect에 올리고 심사를 통과시킨다. 출시 후
새 앱이 사용자에게 배포되기 시작하면 real DB에 seed를 적용한다.

```bash
make apply-seeds-stories-characters ENV=real
make apply-seeds-quizzes ENV=real       # 퀴즈가 있으면
scripts/run_real.sh
```

주의:

- 이 방식은 간단하지만, 사용자가 아직 구버전 앱을 쓰고 있으면 새 이야기는 보이되
  장면 이미지는 비어 보일 수 있다.
- 이미지 빈 상태를 절대 피해야 하면 권장 B를 쓴다.

#### 선택 B: Storage fallback을 직접 마련한 뒤 real 공개

구버전 앱 사용자까지 이미지가 보여야 하면 이 방식이 제일 안전하다.

원리:

- 구버전 앱: 로컬 번들에 새 썸네일이 없으므로 `events.scene_image_paths`의
  Supabase Storage URL을 사용한다.
- 신버전 앱: 로컬 번들에 새 썸네일이 있으므로 Storage를 호출하지 않는다.
- 앱 출시 후 1~2주 정도 지나 대부분 업데이트된 뒤에 Storage 원본 정리를 고려한다.

과거에는 사역자 웹 제안/승인 흐름이 이 역할을 했다. 하지만 현재 운영 정책은
웹을 배포하지 않고 로컬에서 직접 이야기와 이미지를 추가하는 방식이다. 따라서
제안/승인 문서를 표준 경로로 보지 않는다.

현재 repo에는 로컬에서 생성한 canonical 장면 이미지를 Storage에 업로드하고
`events.scene_image_paths`를 채우는 전용 Make target이 없다. 그래서 구버전 앱까지
이미지를 보장해야 하는 배포를 자주 할 계획이면 먼저 별도 운영 도구를 추가해야 한다.

주의: `make upload-character-avatars`는 캐릭터 아바타 전용이다. 이야기 장면 이미지나
`assets/story_images_thumbs`를 업로드하지 않는다.

필요한 도구의 역할:

1. `assets/story_images/<title>/scene_N.png` 또는 썸네일을 public Storage에 업로드한다.
2. 업로드 결과를 `bucket/path/scene_N.png` 형식으로 모은다.
3. real DB의 해당 이벤트에 `scene_image_paths = ARRAY[...]`를 patch 한다.
4. 앱 출시 후 충분히 시간이 지난 뒤에만 Storage 원본 정리를 검토한다.

이 도구가 없는 현재 상태에서 이미지 빈 상태를 피하는 가장 단순한 운영은
real 공개 자체를 새 앱 출시 이후로 늦추는 것이다.

#### 실수로 real에 먼저 공개했을 때

`apply-seeds-stories-characters ENV=real`을 먼저 실행해서 이미지 없는 새 이야기가
보이기 시작했다면, 바로 draft로 숨긴다.

```sql
update public.events
set status = 'draft'
where title in ('새 이야기 제목');
```

앱은 `events_ordered` view를 읽고 이 view는 `status='published'`만 노출하므로,
draft 상태의 이야기는 일반 사용자에게 보이지 않는다.

fallback을 채웠거나 새 앱 출시 타이밍이 됐을 때 다시 공개한다.

```sql
update public.events
set status = 'published'
where title in ('새 이야기 제목');
```

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

- dev에는 먼저 적용해 충분히 확인한다.
- real에는 앱 Store 심사/출시 타이밍을 고려해 적용한다.
- 새 이야기 장면 이미지가 로컬 번들에만 있고 `events.scene_image_paths`가 비어 있으면
  구버전 앱 사용자는 이미지 없는 새 이야기를 볼 수 있다.
- 이를 피하려면 `3.2.1 신규 이야기 추가 Flow`의 권장 B처럼 Storage fallback을
  채운 뒤 공개한다.

보수적인 배포 순서:

```bash
# dev 검증
make seed-stories-characters
make generate-story-images
make thumbnails
make update-pubspec-assets
make apply-seeds-stories-characters ENV=dev
scripts/run_dev.sh

# real 빌드 먼저 준비
scripts/run_real.sh
scripts/build_android_real.sh
scripts/build_ios_real.sh

# Store 심사 통과/출시 준비 후 real DB 공개
make apply-seeds-stories-characters ENV=real
scripts/run_real.sh
```

이미지 빈 상태를 피해야 하면 real 공개 전에 `events.scene_image_paths` fallback이
있는지 확인한다.

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
