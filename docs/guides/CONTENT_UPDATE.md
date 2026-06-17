# 콘텐츠 추가/수정 → 앱 반영 워크플로우

> 새 인물·이야기를 등록한 뒤 사용자 폰에 실제로 보이기까지의 전체 흐름과 체크리스트.

> ✅ **2026-04 Phase 2~6 완료**: 사역자 제안 폼이 메인 앱 웹에 구축되고, AI
> 장면 이미지 생성(Supabase Edge Function + Vertex Gemini) 이 통합됐다. 이제
> **사역자가 직접 등록 폼에서 AI 로 그림을 만들어 제안 → 관리자가 승인** 하는
> 흐름이 가능하다 (아래 §2.1c 참조).
>
> - ADR-016: `admin/` 별도 Flutter Web 앱 폐기 → 메인 앱 웹으로 이전
> - 도메인 용어 전환: `persons` → `characters` (DB / 코드 / 문서 전반)
> - 신규 Storage 버킷: `characters` (아바타 public), `proposal-scenes` (생성 장면 public)
> - 신규 Edge Function: `generate-proposal-scene` (Vertex Gemini wrapper)
> - 신규 컬럼: `event_proposals.scene_image_paths` / `scene_image_prompts` (각 장면 이미지 추적)

## 0. 한 줄 요약

| 변경 종류 | DB | 이미지 | 사용자 폰에 보이기까지 |
|----------|-----|--------|----------------------|
| **이야기/인물 메타** (제목, 요약, 좌표, 성경 본문, is_active) | `apply-seeds-stories-characters` 또는 어드민 직접 INSERT | — | **즉시** (status=published 시) |
| **인물 아바타 이미지** | persons.avatar_url 갱신 | `assets/avatars_thumbs/{code}.png` 추가 | **앱 재빌드 + Store 재심사 필요** |
| **이야기 4장면 이미지** | (로컬 번들에 포함) | `assets/story_images/{title}/scene_*.png` 추가 후 `make thumbnails`로 `assets/story_images_thumbs/{short_dir}/scene_*.jpg` + `index.json` 생성 | **앱 재빌드 + Store 재심사 필요** |

핵심 한계: 이미지가 앱 번들에 포함되는 구조([ADR-006](../ADR.md))이라, 새 이미지가 사용자에게 보이려면 **앱 빌드 + 스토어 배포가 반드시 필요**하다. 이미지를 Supabase Storage로 옮기면 즉시 반영 가능하지만 현재는 그렇게 운영하지 않는다.

핵심 보장 (파이프라인 재실행 안전성):
- `make build-character-meta`는 **전체 스캔** — `assets/200_stories/*.json`에 있는 **모든 파일**을 읽어 character_meta.json을 통째로 재생성한다 (부분 빌드 아님).
- `make generate-avatars`는 **기존 PNG 자동 SKIP** — `assets/avatars/{code}.png`가 존재하면 Vertex 호출을 건너뛴다. 신규 인물만 비용이 든다. 재생성하려면 `--overwrite`.
- `make apply-seeds-stories-characters`는 **UPSERT** — persons는 `(code)` PK 기준 갱신(단 `is_active`는 **admin 토글 보존**을 위해 업데이트 대상에서 제외), events는 `(era_id, story_index)` PK 기준 갱신.

> ⚠️ **사전 조건 (중요)**: `build-character-meta`는 **로컬 `assets/200_stories/*.json`에 있는 것만 스캔한다**. 만약 운영자 머신에 일부 이야기 JSON만 있는 상태(예: 새로 받은 `1.json` 한 개뿐)에서 빌드·apply하면 **그 seed에 포함된 기존 DB 인물의 `description`이 부분 정보로 덮어써질 수 있다** (description UPSERT는 `coalesce(excluded.description, persons.description)` 방식이라 excluded가 항상 non-null ⇒ 무조건 덮어씀). 기존 DB에 있던 "대표 이야기" 문구가 신규 이야기 제목으로 바뀌는 식.
>

> 따라서 **빌드 전에 반드시 로컬 `assets/200_stories/`가 DB와 동기화된 상태**여야 한다. 로컬이 비었거나 오래됐다면 `make export-stories-json`(DB의 published events를 JSON으로 역추출)으로 먼저 복원한다. 상세 절차는 아래 §2.1b **[0] 단계**. `is_active` / 기존 events / seed에 없는 인물은 영향받지 않지만, seed에 등장하는 기존 인물의 description은 덮어써진다.

## 1. 단계별 흐름 (관리자 등록 표준 경로)

외부 기여자 제출 기능은 폐기됨. 이야기 등록 **요청**은 구글폼/노션 등 별도 채널에서
수집하고, 관리자가 어드민 웹으로 직접 등록한다.

```
[1] 요청자 (앱 외부 채널)                [2] 관리자 (어드민 웹)              [3] 운영자 (이미지 + 앱 출시)
─────────────────────────              ──────────────────────────       ──────────────────────────
구글폼 / 노션 / 메일 등으로             admin/ Flutter Web 로그인          git pull 후 로컬에서:
신규 이야기 요청 제출                   └ "새 이야기 등록" 폼                 a. make seed-characters
(제목, 요약, 4장면, 인물,                  - 시대 (era) 선택                  b. make seed-stories
 성경 본문, 좌표 등)                       - "이 이야기 다음에" 슬롯 선택     c. make apply-seeds-stories-characters
                                           - 제목/요약/인물코드 입력          d. make generate-avatars
                                           - 지도 클릭으로 lat/lng            (신규 인물만 Vertex)
                                           - bible_ref / 연도 / 4장면         e. make generate-story-images
                                           ↓ "제출"                           f. make thumbnails
                                                                              g. make update-pubspec-assets
                                        DB RPC: insert_event_at_position      h. flutter build → Store 업로드
                                           → admin 권한 체크 (is_admin)
                                           → era 단위 advisory lock           사용자 폰에서 다음 fetch부터
                                           → 뒤 인덱스 +1 시프트               새 이야기 표시 (이미지는 placeholder)
                                           → events row INSERT
                                           → status='published' 로 강제       ⚠️ 이미지가 사용자에게 보이려면
                                           → 누락 인물 placeholder 자동 생성     반드시 (3) 단계 완료 + Store 심사
```

> **대량 일괄 등록**: `assets/200_stories/*.json`에 여러 항목을 추가한 뒤
> `make seed-stories-characters` + `apply-seeds-stories-characters`로 일괄 upsert. 어드민 웹은 건건이
> 등록용, JSON+Make는 대량 처리용.

## 2. 운영자가 새 콘텐츠를 앱에 반영하는 정확한 명령

### 2.1 어드민 웹에서 등록된 신규 이야기를 앱 이미지에 반영

> 어드민 웹의 "제출"은 **DB에 status='published' 로 즉시 등록**한다. 누락된 인물 코드는
> `is_active=false` placeholder 로 자동 생성되며, 어드민이 토글해 노출 여부를 결정한다.
> 운영자는 그 후 아래를 실행해 이미지/번들/앱 빌드를 갱신한다.

```bash
source .venv/bin/activate

# 1. 어드민이 등록한 events 와 인물을 다시 JSON 으로 추출 (선택)
#    - DB-first 로 가는 동안은 assets/200_stories/*.json 를 안 건들여도 OK.
#    - 다만 prompts.json / characters_seed.sql 빌더는 JSON 기반이라,
#      신규 인물 아바타 생성을 위해서는 신규 인물 코드를 prompts.json 에 반영해야 함.
#    - 가장 간단: 새 인물 코드를 직접 JSON 의 다른 이야기 persons[] 에 추가하거나,
#      신규 이야기 항목을 통째로 JSON 에 추가해 두기.

# 2. character_meta.json 재생성 (신규 인물이 meta 에 들어와야 다음 generate-avatars 가 호출됨)
make build-character-meta

# 3. 신규 인물 아바타 생성 (기존 png 자동 보존, 신규만 Vertex 호출)
make generate-avatars

# 4. 신규 이야기 4장면 이미지 생성 (빈 디렉토리만 처리)
make generate-story-images

# 5. 썸네일 + pubspec.yaml 갱신
make thumbnails
make update-pubspec-assets       # ⚠️ 빼먹으면 새 이미지가 앱 번들에 포함 안 됨

# 6. 검증
flutter analyze
flutter test
flutter run                      # 시뮬레이터에서 새 이야기/인물 + 이미지 확인

# 7. 스토어 빌드/배포
flutter build ios --release
flutter build appbundle --release
# Xcode/Transporter, Play Console 로 업로드
```

### 2.1b 어드민 웹 없이 JSON 직접 편집 — 신규 이야기 1건 추가 (백업 경로)

가장 흔한 시나리오. 어드민 웹 대신 `assets/200_stories/*.json`에 이야기 1건을
직접 추가하고 앱에 반영하는 전체 흐름. 각 단계가 재실행해도 안전한 이유를 함께 기록.

```bash
source .venv/bin/activate
```

**[0] ⚠️ 필수 사전 조건 — 로컬 `assets/200_stories/`를 DB와 동기화**

`build-character-meta`는 **로컬 디렉토리에 있는 JSON만 스캔**한다. 로컬이 DB와 어긋난 상태에서 빌드·apply하면 seed에 포함된 기존 DB 인물의 description이 부분 정보로 덮어써진다 (§0 경고 참조).

먼저 로컬 상태를 확인:

```bash
ls assets/200_stories/*.json 2>/dev/null | wc -l
# 현재 운영 기준 215개 이상이면 "있음", 0~수개면 "없음/부족"
```

**[0-A] 로컬에 200_stories가 이미 있고 최신인 경우** — 별도 복원 없이 [A]로 이동.

"최신"의 기준: 마지막 작업 이후 어드민 웹에서 새 이벤트가 published 되지 않았고, 다른 개발자가 JSON을 수정한 뒤 push하지 않은 상태. 확신이 없다면 아래 [0-B]를 돌려 덮어써도 무해하다 (export는 DB의 published events를 그대로 파일로 내보내므로 결과는 결정적).

**[0-B] 로컬이 비어 있거나 오래된 경우 — DB에서 역추출 (권장)**

```bash
make export-stories-json            # ENV=dev (기본)
# 또는
make export-stories-json ENV=prod   # 운영 DB 기준으로 복원
```

- DB의 `status='published'` events를 시대별 JSON(`era_monarchy.json`, `era_divided_kingdom.json`, ...)으로 역추출해 `assets/200_stories/` 에 쓴다.
- anon key로 read-only 접근이므로 DB에 영향 없음.
- 어드민 웹이 JSON 없이 DB만 갱신하는 현재 운영 기준, **이 방법이 가장 안전하고 항상 최신**이다.

> `git pull`도 이론상 가능하지만 **저장소 정책에 따라 `assets/200_stories/*.json`이 추적되지 않을 수 있으므로** 권장하지 않는다. 현재 이 저장소는 추적 중이지만 운영이 DB-first로 기울면 언제든 변경될 수 있다. DB 기반이 정책 변화와 무관하게 결정적이다.

이후 진행은 동일. 이 [0] 단계를 빠뜨리면 기존 인물 description이 손상될 수 있다.

**[A] JSON에 신규 이야기 항목 추가**
- `assets/200_stories/{해당_era_파일}.json` 배열 끝에 새 객체 추가
- `title`은 화면에 보일 순수 제목으로 쓰고, `story_index`는 era 내 unique 정수로 채운다
- `persons[]` 에 기존 코드를 쓸 수도, 신규 코드를 새로 등장시킬 수도 있다
- 신규 인물이면 새 코드명을 적어두기만 하면 됨 (다음 단계에서 meta에 자동 편입)

**[B] character_meta.json 재생성 — 전체 스캔**
```bash
make build-character-meta
```
- `assets/200_stories/*.json`을 **전부** 읽어 `tools/seed/character_meta.json`을 통째로 재생성
- 결과물에는 **기존 인물 + 신규 인물**이 모두 들어있다 (부분 빌드 아님)
- 신규 인물에는 자동으로 아바타 프롬프트가 부여되며 mention_count가 기록됨

**[C] SQL 생성 — 모든 인물/이야기를 담은 전체 seed**
```bash
make seed-stories-characters   # B 단계 포함 (의존성)
```
- `characters_seed.sql` — 기존 + 신규 인물 전부의 UPSERT 구문
- `200_stories_seed_part_*.sql` — 기존 + 신규 이야기 전부의 UPSERT 구문
- 파일이 커 보여도 다음 단계가 UPSERT라 중복 INSERT 없음

**[D] DB 적용 — UPSERT로 중복·덮어쓰기 없이 안전**
```bash
make apply-seeds-stories-characters
```
- **persons** (`on conflict (code) do update set ...`):
  - 기존 인물: `name` / `avatar_url` / `description`만 갱신
  - 기존 인물의 `is_active`는 **업데이트 대상에서 제외** → 어드민이 토글한 노출 설정이 그대로 살아남음
  - 신규 인물: 정상 INSERT. `is_active` 초기값은 `character_meta.json`의 `is_active_default` (= mention_count ≥ 2 기본) 값 적용
- **events** (`on conflict (era_id, story_index) do update set ...`):
  - 새 `story_index` → INSERT (새 row)
  - 같은 `(era_id, story_index)`를 재시딩한 경우 → UPDATE (title/summary/scenes/좌표/bible_refs/등을 최신 JSON으로 갱신)

**[E] 아바타 이미지 생성 — 신규 인물만 Vertex 호출**
```bash
make generate-avatars
```
- `assets/avatars/{code}.png`가 이미 있으면 `[SKIP]` 출력 후 스킵 → **기존 인물은 Vertex 비용 0**
- 신규 인물만 Imagen 호출
- 기존 아바타를 새 프롬프트로 다시 그리려면 `python3 tools/images/generate_avatars_vertex.py --overwrite ...` (또는 해당 png 파일을 지우고 `make generate-avatars`)

**[F] 장면 이미지 + 썸네일 + 번들**
```bash
make generate-story-images    # 빈 {title}/ 디렉토리만 처리
make thumbnails               # 썸네일 생성 (로컬, 비용 0)
make update-pubspec-assets    # ⚠️ 빼먹으면 새 이미지가 앱 번들에 포함 안 됨
```

**[G] 검증 + 스토어 빌드** — 2.1의 6~7 단계와 동일.

### 2.1c 신규 인물 코드만 추가하고 싶을 때 (이야기는 그대로)

예: 기존 이야기에 `persons[]`를 하나 추가해 새 얼굴이 등장하도록 하고 싶다.
흐름은 2.1b와 동일하되 [A]가 "기존 이야기의 `persons[]`에 코드 한 줄 추가"로 바뀔 뿐.
이후 [B]~[D]로 meta/persons/events UPSERT가 돌며 신규 인물 row만 DB에 추가된다.

### 2.2 이미 있는 이야기 메타만 수정한 경우 (제목/요약 등)

```bash
make seed-stories-characters
make apply-seeds-stories-characters
# 끝. 앱 재빌드 불필요 (DB만 바뀜)
```

동작: events UPSERT가 같은 `(era_id, story_index)` 행을 UPDATE로 덮어쓰므로 제목·요약·좌표·bible_ref·scenes가 최신 JSON으로 즉시 반영. persons도 UPSERT지만 이야기 메타만 바꿨다면 persons 쪽 diff는 0이다.

### 2.3 인물 노출 토글만 (is_active true ↔ false)

어드민 웹/SQL Editor에서 직접:
```sql
update persons set is_active = true where code = 'goliath';
```
- view `character_eras`가 자동 재계산 → 앱이 다음 새로고침에 즉시 반영
- 앱 재빌드 불필요

## 3. 사전·사후 체크리스트

### 등록 전 (어드민 웹/JSON 작성 시)
- [ ] `title`이 `"### 제목"` 형식 — 3자리 prefix 포함 (scene asset 매칭에 사용)
- [ ] `era` 코드 정확 (`era_primeval`, `era_patriarch`, ..., `era_nt_consummation`)
- [ ] `story_index` 가 era 내 unique 정수 (어드민 웹은 자동 부여, JSON 수동 편집 시 직접)
- [ ] `lat/lng` 가 합리적 범위 (-90~90 / -180~180)
- [ ] `bible_ref` 의 `book` 이 한국어 약어 (`창`, `출`, `요`, `행` 등)
- [ ] `story_scenes` 4개, `scene_characters` 4개 (길이 일치)
- [ ] `persons[]` 의 코드들이 `tools/seed/character_meta.json` 에 존재하거나, 신규 인물이라면 등록 후 빌더가 자동 추가하도록

### 운영자 검토 시
- [ ] 신규 인물의 prompt가 적절한지 (`tools/seed/character_meta.json` 확인 후 필요 시 `tools/seed/build_character_meta_json.py` 의 `CODE_SIGNATURE_HINTS`/`CHARACTER_VISUAL_OVERRIDES`/`CHARACTER_MOOD_OVERRIDES` 보강)
- [ ] 신규 인물의 `is_active_default` (character_meta.json 의 mention_count >= 2) 가 의도와 맞는지 — 1회 등장이지만 중요한 인물이면 어드민에서 수동으로 `is_active=true` 토글
- [ ] story_scenes 텍스트가 시각화 가능한 묘사인지 (대사·메타 단어 없이)

### 빌드 전
- [ ] `flutter analyze` 0 issues
- [ ] `flutter test` 통과
- [ ] `make check-pubspec-assets` (= `update_pubspec_assets.py --check`) 통과 — pubspec ↔ 디스크 동기화
- [ ] 시뮬레이터 골든 패스: era 선택 → 인물 패널 정렬 → 신규 이야기 카드 → 이벤트 상세 (이미지 4장 + bible_ref 표시)

### 배포 후
- [ ] 사용자에게 알림: "새 이야기 N건 추가, 앱을 업데이트하세요"
- [ ] 신규 이야기/인물의 DB row는 이미 published 상태이지만, **이미지가 안 보이는 사용자는 구버전 앱**임을 안내

## 4. 이미지가 안 보이는 흔한 원인 디버깅

1. **`pubspec.yaml`에 디렉토리 누락** → `make update-pubspec-assets` 다시 실행 후 빌드
2. **`assets/{...}_thumbs/` 디렉토리에 png 없음** → `make thumbnails` 다시 실행 (또는 원본부터 `make generate-avatars`/`generate-story-images`)
3. **scene 디렉토리 이름 매칭 실패** → 디렉토리 명이 `001 창조: 7일과 안식` 처럼 title 그대로여야 함. 새 이야기의 title을 변경했다면 옛 이름 디렉토리 삭제 + 재생성
4. **persons.avatar_url 경로 오타** — `assets/avatars/{code}.png` 형태인지 확인. 빌더가 `code`로 채우므로 `code` 자체가 오타면 png 파일명과 안 맞음
5. **앱이 아직 구버전 캐시** — 앱 재시작, 안 되면 `flutter clean && flutter run`

## 5. 향후 개선 후보

이미지를 매번 앱 번들로 묶는 부담을 줄이려면:

1. **Supabase Storage로 전환** — 어드민 "배포" 즉시 사용자 폰에 새 이미지 표시. ADR-006 폐기 결정 필요. cached_network_image 도입.
2. **Hybrid** — 기존 215개는 번들, 신규만 Storage. 모델 필드가 `assets/...` / `https://...` 둘 다 허용하도록 분기.
3. **CodeMagic/Fastlane으로 자동 빌드** — 어드민 "배포" → CI가 자동으로 `make` 일괄 + flutter build + 스토어 업로드. 심사 주기는 여전히 며칠.

현재는 운영 단순성을 우선해 1번/2번을 보류한 상태. 외부 기여 빈도가 높아지면 재고 필요.

## 6. 관련 문서

- [DATA_PIPELINE.md](../DATA_PIPELINE.md) — 빌더 스크립트 상세
- [BACKEND.md](../BACKEND.md) — DB 스키마, RLS, view
- [FRONTEND.md](../FRONTEND.md) — Flutter 모델/상태/위젯
- [ADR.md](../ADR.md) — ADR-006 (이미지 번들 포함), ADR-012/013/014 (스키마 v3)
