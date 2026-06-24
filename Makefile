# Story Bible — 데이터 파이프라인 오케스트레이션
#
# 사용법:
#   make <target>        # 특정 타겟 실행
#   make all             # 전체 파이프라인
#   make -n <target>     # dry-run (실행 없이 명령만 출력)
#
# 선행 조건:
#   - source .venv/bin/activate (Python 가상환경)
#   - .env 설정 (앱 실행용 공개 Supabase URL/anon key 등)
#   - .env.ops 설정 (DB URL, service_role 등 운영 비밀 — 앱 번들 제외)
#
# 상세: docs/DATA_PIPELINE.md

# =============================================================================
# 설정
# =============================================================================

PYTHON ?= python3
TOOLS_DIR := tools
ASSETS_DIR := assets
SUPABASE_DIR := supabase

# 주요 파일 경로
CHARACTER_META := $(TOOLS_DIR)/seed/character_meta.json
STORIES_DIR := $(ASSETS_DIR)/200_stories
BIBLE_DIR := $(ASSETS_DIR)/bible
AVATARS_DIR := $(ASSETS_DIR)/avatars
AVATARS_THUMBS_DIR := $(ASSETS_DIR)/avatars_thumbs
STORY_IMAGES_DIR := $(ASSETS_DIR)/story_images
STORY_IMAGES_THUMBS_DIR := $(ASSETS_DIR)/story_images_thumbs
STORY_DRAFTS_DIR := $(ASSETS_DIR)/story_drafts
STORY_IMAGE_SOURCE_BUCKET ?= story-image-sources
AVATAR_CODES ?=
AVATAR_OVERWRITE ?=
AVATAR_EXTRA_ARGS := $(if $(strip $(AVATAR_CODES)),--only-codes $(AVATAR_CODES),) $(if $(filter 1 true yes,$(AVATAR_OVERWRITE)),--overwrite,)

# 출력 SQL
KRV_SQL := $(SUPABASE_DIR)/seeds/krv_bible_verses.sql
STORIES_SQL := $(SUPABASE_DIR)/200_stories/200_stories_seed.sql
CHARACTERS_SQL := $(SUPABASE_DIR)/200_stories/characters_seed.sql
LANDMARKS_SQL := $(SUPABASE_DIR)/200_stories/landmarks_seed.sql
QUIZZES_SQL := $(SUPABASE_DIR)/quizzes/quizzes_seed.sql
QUIZZES_REPORT := $(SUPABASE_DIR)/quizzes/quizzes_report.json
LANDMARKS_DIR := $(ASSETS_DIR)/landmarks

# =============================================================================
# .PHONY 선언
# =============================================================================

.PHONY: help all \
        seed-bible-verses build-character-meta renumber-story-indices generate-story-contexts \
        seed-stories seed-characters seed-stories-characters seed-quizzes \
        seed-landmarks audit-landmark-polygons refine-landmark-polygons \
        apply-seeds-landmarks-v2 \
        generate-avatars generate-story-images generate-draft-story-images thumbnails \
        seed-all generate-all \
        export-stories-json export-quizzes-json export-event-region-mapping release-sync-stories \
        db-init apply-patch apply-seeds apply-bible-verses-seeds apply-seeds-stories-characters \
        apply-seeds-landmarks apply-seeds-quizzes \
        upload-character-avatars upload-character-avatars-force \
        ensure-story-image-sources ensure-story-image-sources-dry \
        upload-story-image-sources upload-story-image-sources-dry \
        apply-draft apply-drafts \
        sync-approved-proposal-assets sync-approved-proposal-assets-all \
        sync-approved-proposal-assets-dry sync-approved-proposal-assets-clean \
        cleanup-orphan-proposal-assets cleanup-orphan-proposal-assets-dry \
        build-guides \
        update-pubspec-assets check-pubspec-assets \
        clean-generated lint

# =============================================================================
# 기본 타겟
# =============================================================================

help:
	@echo "Story Bible 데이터 파이프라인 Makefile"
	@echo ""
	@echo "개별 타겟:"
	@echo "  seed-bible-verses       성경 구절 SQL 생성 (독립)"
	@echo "  build-character-meta       character_meta.json 생성 (인물 카탈로그 + 아바타 프롬프트, 모든 인물 포함)"
	@echo "  generate-story-contexts    curated summary 정규화 + background_context 생성"
	@echo "  seed-stories            events SQL 생성 (→ character-meta 의존)"
	@echo "  seed-characters            characters SQL 생성 (→ character-meta 의존)"
	@echo "  seed-stories-characters    events + characters SQL 한 번에 생성 (권장)"
	@echo "  seed-quizzes               퀴즈 SQL 생성 (→ seed-stories 선행 필요)"
	@echo "  audit-landmark-polygons    박스형/저정점 region polygon 감사"
	@echo "  refine-landmark-polygons   Natural Earth 기반 region polygon 정제 후보 생성"
	@echo "  generate-avatars        Vertex AI Gemini 아바타 생성 (→ character-meta 의존, 기존 png 보존)"
	@echo "  generate-story-images   Vertex AI 장면 이미지 생성"
	@echo "  generate-draft-story-images [STORY=assets/story_drafts/foo.json|DRAFT=foo] draft 장면 이미지 생성"
	@echo "  thumbnails              썸네일 생성 (→ avatars, story-images 의존)"
	@echo ""
	@echo "묶음 타겟:"
	@echo "  seed-all                전체 SQL 생성 (bible + stories + characters + quizzes + landmarks)"
	@echo "  generate-all            전체 이미지 생성 (avatars + story-images + thumbnails)"
	@echo "  all                     전체 파이프라인 (seed-all + generate-all)"
	@echo ""
	@echo "DB → 로컬 동기화:"
	@echo "  export-stories-json       [ENV=dev]  DB events → assets/200_stories/*.json 역추출 (빌더 사전 조건)"
	@echo "  export-quizzes-json       [ENV=dev]  DB quiz_questions → assets/quizzes/*.json + db_events.json"
	@echo "  export-event-region-mapping [ENV=dev] DB events.landmark_id → assets/landmarks/event_region_mapping.json"
	@echo "  release-sync-stories      [ENV=dev|real] approved proposal 자산 + DB events/quiz/mapping → 로컬 번들 준비"
	@echo ""
	@echo "DB 적용 (psql + .env.ops의 SUPABASE_DB_URL_DEV/PROD; ENV=real은 PROD 사용):"
	@echo "  db-init                   [ENV=dev]       db_init.sql 실행 (drop & recreate, 파괴적!)"
	@echo "                            [ENV=real CONFIRM_REAL_DB_INIT=1] 신규/복구 real 부트스트랩 전용"
	@echo "  apply-patch               [ENV=dev|real PATCH=path.sql] idempotent schema/RLS/RPC patch 적용"
	@echo "  apply-bible-verses-seeds  [ENV=dev|real]  krv 성경 구절만 적용 (1회성, 중복 INSERT 시 에러)"
	@echo "  apply-seeds-stories-characters       [ENV=dev|real]  characters + 200_stories + scene_captions 적용 (UPSERT — 재실행 안전)"
	@echo "  apply-seeds-quizzes                  [ENV=dev|real]  quiz_questions 적용 (delete 후 insert — 재실행 안전)"
	@echo "  apply-seeds               [ENV=dev|real]  전체 시드 적용 (최초 부트스트랩용)"
	@echo ""
	@echo "Supabase Storage (service_role 키 필요):"
	@echo "  upload-character-avatars        [ENV=dev|real]  assets/avatars/*.png → characters/ 버킷 (이미 있으면 스킵)"
	@echo "  upload-character-avatars-force  [ENV=dev|real]  전부 덮어쓰기 업로드 (--overwrite)"
	@echo "  ensure-story-image-sources      [ENV=dev|real]  private 원본 bucket → assets/story_images missing/changed PNG 다운로드"
	@echo "  upload-story-image-sources      [ENV=dev|real]  assets/story_images → private 원본 bucket delta 업로드"
	@echo "  apply-draft                     [ENV=dev|real STORY=assets/story_drafts/foo.json|DRAFT=foo] draft → proposal-scenes + pending event_proposals"
	@echo "  apply-drafts                    [ENV=dev|real DRAFTS=\"foo bar\"|STORIES_GLOB=\"assets/story_drafts/202606*.json\"] 여러 draft 순차 업로드"
	@echo ""
	@echo "승인된 제안 → 로컬 assets 동기화 (service_role 키 필요, idempotent):"
	@echo "  - Phase A: 승인된 신규 제안의 PNG 다운로드(synced_to_local_at NULL 만)"
	@echo "  - Phase B: 삭제 승인된 events / 비활성화된 characters 의 로컬+storage 잔존 정리"
	@echo "  sync-approved-proposal-assets         [ENV=dev|real]  Phase A + B 자동 실행"
	@echo "  sync-approved-proposal-assets-all     [ENV=dev|real]  Phase A 마커 무시하고 재동기화 + B"
	@echo "  sync-approved-proposal-assets-dry     [ENV=dev|real]  dry-run — 대상 목록만 출력"
	@echo "  sync-approved-proposal-assets-clean   [ENV=dev|real]  Phase A 동기화 후 proposal-* 원본 삭제 (앱 배포 후에만!)"
	@echo ""
	@echo "미제출 제안 고아 자산 정리 (주기적 운영 — 24h grace window):"
	@echo "  cleanup-orphan-proposal-assets-dry    [ENV=dev|real]  dry-run — 삭제 후보만 나열"
	@echo "  cleanup-orphan-proposal-assets        [ENV=dev|real]  실제 삭제"
	@echo ""
	@echo "기타:"
	@echo "  update-pubspec-assets   story_images_thumbs 경로를 pubspec.yaml에 반영"
	@echo "  check-pubspec-assets    pubspec.yaml이 최신인지 확인 (CI용)"
	@echo "  build-guides            story_guide.md + docs/guides/html/*.html 생성"
	@echo "  lint                    Python 포맷 검사 (black)"
	@echo "  clean-generated         생성된 SQL 파일 삭제"
	@echo ""
	@echo "선행 조건: source .venv/bin/activate"

all: seed-all generate-all

# =============================================================================
# SQL 생성
# =============================================================================

seed-bible-verses:
	@echo "[Makefile] KRV 성경 구절 SQL 생성 (10개 분할)..."
	$(PYTHON) $(TOOLS_DIR)/seed/build_krv_seed_sql.py \
		--input-dir $(BIBLE_DIR) \
		--output $(KRV_SQL) \
		--split-parts 10 \
		--truncate-translation

build-character-meta:
	@echo "[Makefile] character_meta.json 생성 (인물 카탈로그 + 아바타 프롬프트)..."
	$(PYTHON) $(TOOLS_DIR)/seed/build_character_meta_json.py \
		--stories-dir $(STORIES_DIR) \
		--output $(CHARACTER_META)

renumber-story-indices:
	@echo "[Makefile] story_index 를 era 별 1..N 으로 재정렬..."
	$(PYTHON) $(TOOLS_DIR)/seed/renumber_story_indices.py \
		--stories-dir $(STORIES_DIR)

generate-story-contexts:
	@echo "[Makefile] summary/background_context 생성..."
	$(PYTHON) $(TOOLS_DIR)/seed/generate_story_background_contexts.py \
		--stories-dir $(STORIES_DIR) \
		--bible-dir $(BIBLE_DIR)

# 이벤트 lat/lng 를 매칭되는 landmark 의 정확한 좌표로 정렬.
# 같은 장소(예: "헤브론") 인 이벤트들이 핀 분산 알고리즘에 의해 떨어져 보이는
# 문제 + landmark 와 미세 좌표 차이 문제 둘 다 해결. assets/200_stories/*.json
# 을 직접 수정하므로 실행 후 git diff 로 검증 권장.
align-events-to-landmarks:
	@echo "[Makefile] 이벤트 lat/lng → landmark 좌표 정렬..."
	$(PYTHON) $(TOOLS_DIR)/seed/align_events_to_landmarks.py \
		--landmarks $(LANDMARKS_DIR)/landmarks.json \
		--stories-dir $(STORIES_DIR)

align-events-to-landmarks-dry:
	@echo "[Makefile] 이벤트 정렬 dry-run (변경만 출력)"
	$(PYTHON) $(TOOLS_DIR)/seed/align_events_to_landmarks.py \
		--landmarks $(LANDMARKS_DIR)/landmarks.json \
		--stories-dir $(STORIES_DIR) \
		--dry-run

seed-stories: build-character-meta
	@echo "[Makefile] events SQL 생성..."
	@echo "  → 사전 조건: assets/200_stories/*.json 의 각 항목에 story_index 가 있어야 함"
	$(PYTHON) $(TOOLS_DIR)/seed/build_200_stories_seed_sql.py \
		--output-dir $(SUPABASE_DIR)/200_stories \
		--character-meta-json $(CHARACTER_META)

seed-characters: build-character-meta
	@echo "[Makefile] characters SQL 생성..."
	$(PYTHON) $(TOOLS_DIR)/seed/build_characters_seed_sql.py \
		--character-meta-json $(CHARACTER_META) \
		--stories-dir $(STORIES_DIR) \
		--output $(CHARACTERS_SQL)

# events + characters 묶음 — apply-seeds-stories-characters 와 대칭되는 seed 단계.
# build-character-meta 는 Make 의존성 그래프에서 한 번만 실행된다.
seed-stories-characters: seed-stories seed-characters
	@echo "[Makefile] stories + characters SQL 생성 완료."

seed-landmarks:
	@echo "[Makefile] landmarks SQL 생성 (assets/landmarks/landmarks.json)..."
	$(PYTHON) $(TOOLS_DIR)/seed/build_landmarks_seed_sql.py

audit-landmark-polygons:
	@echo "[Makefile] region polygon 감사 (박스형/저정점 후보)..."
	$(PYTHON) $(TOOLS_DIR)/seed/audit_landmark_polygons.py \
		--landmarks $(LANDMARKS_DIR)/landmarks.json

# region 폴리곤 정제 후보 생성 — 기본은 검토용 JSON 만 출력한다.
# landmarks.json 에 바로 반영하려면 스크립트를 직접 `--in-place` 로 실행하고
# `python3 tools/seed/verify_polygons_contain_events.py` 로 사건 포함 여부 확인.
refine-landmark-polygons:
	@echo "[Makefile] region polygon 정제 후보 생성 (Natural Earth GeoJSON 클립)..."
	$(PYTHON) $(TOOLS_DIR)/seed/refine_landmark_polygons_from_geojson.py \
		--landmarks $(LANDMARKS_DIR)/landmarks.json \
		--geojson $(ASSETS_DIR)/maps/ne_50m_admin_0_countries.geojson \
		--out $(TOOLS_DIR)/seed/refined_polygons.json

seed-quizzes:
	@echo "[Makefile] 퀴즈 SQL 생성..."
	@# 권위 소스: supabase/quizzes/db_events.json (dev DB 스냅샷).
	@# main 의 200_stories_seed.sql 과 dev DB 가 같은 (era,story_index) 키에
	@# 서로 다른 이야기를 담고 있어, 시드 파일을 기준으로 빌드하면 title이
	@# 어긋난 SQL 이 생성된다. DB 와 seed 가 일치할 때까지 db_events.json 을
	@# 단일 진실 소스로 사용한다.
	$(PYTHON) $(TOOLS_DIR)/seed/build_quizzes_seed_sql.py \
		--input-dir $(ASSETS_DIR)/quizzes \
		--output $(QUIZZES_SQL) \
		--report $(QUIZZES_REPORT) \
		--events-from-json $(SUPABASE_DIR)/quizzes/db_events.json

seed-all: seed-bible-verses seed-stories seed-characters seed-quizzes seed-landmarks
	@echo "[Makefile] 전체 SQL 생성 완료. Supabase SQL Editor에서 실행하세요."

# =============================================================================
# 이미지 생성 (Vertex AI)
# =============================================================================

generate-avatars: build-character-meta
	@echo "[Makefile] Vertex AI Gemini 아바타 생성..."
	@echo "  → .env의 GOOGLE_CLOUD_PROJECT 확인 필요"
	$(PYTHON) $(TOOLS_DIR)/images/generate_avatars_vertex.py \
		--character-meta-json $(CHARACTER_META) \
		--output-dir $(AVATARS_DIR) \
		$(AVATAR_EXTRA_ARGS)

generate-story-images:
	@echo "[Makefile] Vertex AI 장면 이미지 생성..."
	@echo "  → .env의 GOOGLE_CLOUD_PROJECT 확인 필요"
	$(PYTHON) $(TOOLS_DIR)/images/generate_event_story_images_vertex.py

generate-draft-story-images:
	@story_json="$(STORY)"; \
	if [ -z "$$story_json" ] && [ -n "$(DRAFT)" ]; then story_json="$(STORY_DRAFTS_DIR)/$(DRAFT).json"; fi; \
	if [ -z "$$story_json" ]; then \
		echo "ERROR: STORY=assets/story_drafts/foo.json or DRAFT=foo is required"; \
		exit 1; \
	fi; \
	out_dir="$${story_json%.json}"; \
	echo "[Makefile] draft 장면 이미지 생성: $$story_json → $$out_dir"; \
	$(PYTHON) $(TOOLS_DIR)/images/generate_event_story_images_vertex.py \
		--stories-dir "$$(dirname "$$story_json")" \
		--stories-glob "$$(basename "$$story_json")" \
		--output-root "$$out_dir" \
		--single-output-dir "$$out_dir" \
		--no-prune-orphans

thumbnails:
	@echo "[Makefile] 썸네일 생성..."
	$(PYTHON) $(TOOLS_DIR)/images/generate_runtime_thumbnails.py

generate-all: generate-avatars generate-story-images thumbnails
	@echo "[Makefile] 전체 이미지 생성 완료."

# =============================================================================
# Supabase Storage 업로드 (아바타)
# =============================================================================
# 전제: .env 에 SUPABASE_URL_<ENV>, .env.ops 에 SUPABASE_SERVICE_ROLE_KEY_<ENV> 설정
# db_init.sql 실행 후 한 번 돌리면 characters/ 버킷에 124개 PNG 업로드
# + characters.avatar_storage_path 가 채워진다.
# 기본 업로드는 characters 버킷을 먼저 비운 뒤 새로 업로드한다.
# 그래도 기존 객체가 감지되면 중단한다.
# 강제 덮어쓰기는 upload-character-avatars-force 를 사용한다.

upload-character-avatars:
	@echo "[Makefile] Supabase Storage 에 캐릭터 아바타 업로드 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/purge_owned_buckets.py --env $(OPS_ENV) --bucket characters --strict
	$(PYTHON) $(TOOLS_DIR)/supabase/upload_character_avatars.py --env $(OPS_ENV) --fail-on-existing

upload-character-avatars-force:
	@echo "[Makefile] 캐릭터 아바타 강제 덮어쓰기 업로드 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/upload_character_avatars.py --env $(OPS_ENV) --overwrite

# -----------------------------------------------------------------------------
# 앱 번들용 썸네일의 원본 PNG 보관소 (release-only private bucket)
# -----------------------------------------------------------------------------
# bucket 기본값은 story-image-sources. purge_owned_buckets.py 대상이 아니므로
# db-init 으로 characters/proposal-* 버킷을 비워도 이 원본 저장소는 유지된다.

ensure-story-image-sources:
	@echo "[Makefile] story 원본 PNG pull (bucket=$(STORY_IMAGE_SOURCE_BUCKET), ENV=$(ENV) → ops=$(OPS_ENV))"
	STORY_IMAGE_SOURCE_BUCKET=$(STORY_IMAGE_SOURCE_BUCKET) \
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_story_image_sources.py pull --env $(OPS_ENV)

ensure-story-image-sources-dry:
	@echo "[Makefile] story 원본 PNG pull dry-run (bucket=$(STORY_IMAGE_SOURCE_BUCKET), ENV=$(ENV) → ops=$(OPS_ENV))"
	STORY_IMAGE_SOURCE_BUCKET=$(STORY_IMAGE_SOURCE_BUCKET) \
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_story_image_sources.py pull --env $(OPS_ENV) --dry-run

upload-story-image-sources:
	@echo "[Makefile] story 원본 PNG push (bucket=$(STORY_IMAGE_SOURCE_BUCKET), ENV=$(ENV) → ops=$(OPS_ENV))"
	STORY_IMAGE_SOURCE_BUCKET=$(STORY_IMAGE_SOURCE_BUCKET) \
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_story_image_sources.py push --env $(OPS_ENV)

upload-story-image-sources-dry:
	@echo "[Makefile] story 원본 PNG push dry-run (bucket=$(STORY_IMAGE_SOURCE_BUCKET), ENV=$(ENV) → ops=$(OPS_ENV))"
	STORY_IMAGE_SOURCE_BUCKET=$(STORY_IMAGE_SOURCE_BUCKET) \
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_story_image_sources.py push --env $(OPS_ENV) --dry-run

apply-draft:
	@story_json="$(STORY)"; \
	if [ -z "$$story_json" ] && [ -n "$(DRAFT)" ]; then story_json="$(STORY_DRAFTS_DIR)/$(DRAFT).json"; fi; \
	if [ -z "$$story_json" ]; then \
		echo "ERROR: STORY=assets/story_drafts/foo.json or DRAFT=foo is required"; \
		exit 1; \
	fi; \
	echo "[Makefile] draft → pending proposal (ENV=$(ENV) → ops=$(OPS_ENV)): $$story_json"; \
	$(PYTHON) $(TOOLS_DIR)/supabase/apply_story_draft.py \
		--env $(OPS_ENV) \
		--story "$$story_json" \
		$(if $(strip $(PROPOSER_USER_ID)),--proposer-user-id $(PROPOSER_USER_ID),) \
		$(if $(filter 1 true yes,$(DRY_RUN)),--dry-run,)

apply-drafts:
	@story_args=""; \
	for draft in $(DRAFTS); do story_args="$$story_args --story $(STORY_DRAFTS_DIR)/$$draft.json"; done; \
	for story in $(STORIES); do story_args="$$story_args --story $$story"; done; \
	glob_arg=""; \
	if [ -n "$(STORIES_GLOB)" ]; then glob_arg="--stories-glob $(STORIES_GLOB)"; fi; \
	if [ -z "$$story_args" ] && [ -z "$$glob_arg" ]; then \
		echo "ERROR: DRAFTS=\"foo bar\", STORIES=\"path/a.json path/b.json\", or STORIES_GLOB=\"assets/story_drafts/*.json\" is required"; \
		exit 1; \
	fi; \
	echo "[Makefile] 여러 draft → pending proposals (ENV=$(ENV) → ops=$(OPS_ENV))"; \
	$(PYTHON) $(TOOLS_DIR)/supabase/apply_story_draft.py \
		--env $(OPS_ENV) \
		$$story_args \
		$$glob_arg \
		$(if $(strip $(PROPOSER_USER_ID)),--proposer-user-id $(PROPOSER_USER_ID),) \
		$(if $(filter 1 true yes,$(DRY_RUN)),--dry-run,)

# -----------------------------------------------------------------------------
# 승인된 제안 → 로컬 assets 동기화
# -----------------------------------------------------------------------------
# 관리자가 제안을 승인한 뒤, proposal-scenes / proposal-characters 버킷에 있는
# AI 생성 이미지를 로컬 assets/ 로 내려받아 번들에 포함시킨다. 동시에 새 캐릭터
# 는 characters 버킷으로 복사 + characters.avatar_storage_path 도 canonical
# 경로(`{code}.png`) 로 재세팅. 이 타겟을 돌린 뒤 make thumbnails +
# apply-seeds-stories-characters 를 실행해 최종 반영.

sync-approved-proposal-assets:
	@echo "[Makefile] 승인된 제안 자산 동기화 (ENV=$(ENV) → ops=$(OPS_ENV)) — synced_to_local_at NULL 인 것만"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(OPS_ENV)

sync-approved-proposal-assets-all:
	@echo "[Makefile] 승인된 제안 자산 전체 재동기화 (ENV=$(ENV) → ops=$(OPS_ENV)) — synced marker 무시"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(OPS_ENV) --all

sync-approved-proposal-assets-dry:
	@echo "[Makefile] 승인된 제안 자산 동기화 dry-run (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(OPS_ENV) --dry-run

sync-approved-proposal-assets-clean:
	@echo "[Makefile] 승인된 제안 자산 동기화 + 원본 버킷 정리 (ENV=$(ENV) → ops=$(OPS_ENV))"
	@echo "  ⚠️  앱 배포 전이면 하이브리드 fallback 깨짐 — 배포 완료 후 사용 권장"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(OPS_ENV) --delete-source

# -----------------------------------------------------------------------------
# 미제출 / 버려진 제안 자산 청소
# -----------------------------------------------------------------------------
# 사역자가 이미지 생성 버튼을 누른 뒤 [제안 등록] 안 하고 창을 닫으면 Storage
# 에 고아 이미지가 남는다. 이 타겟은 24시간 이상 지났고 event_proposals
# 어디에도 참조되지 않은 proposal-* 파일을 정리한다. 주 1회 cron 이나 운영
# 루틴에 끼워 넣으면 깔끔.

cleanup-orphan-proposal-assets-dry:
	@echo "[Makefile] 고아 제안 자산 dry-run — 실제 삭제 없이 나열만 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/cleanup_orphan_proposal_assets.py --env $(OPS_ENV) --dry-run

cleanup-orphan-proposal-assets:
	@echo "[Makefile] 고아 제안 자산 정리 — 24시간 이상 지난 미참조 파일 삭제 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/cleanup_orphan_proposal_assets.py --env $(OPS_ENV)

# =============================================================================
# Supabase DB 적용 (psql 사용)
# =============================================================================
# 사용법:
#   make apply-seeds              # ENV=dev (기본) — SUPABASE_DB_URL_DEV 사용
#   make apply-seeds ENV=real     # SUPABASE_DB_URL_PROD 사용
#   make apply-seeds ENV=prod     # real alias — SUPABASE_DB_URL_PROD 사용
#
# .env.ops 에 다음을 추가해야 한다:
#   SUPABASE_DB_URL_DEV="postgresql://postgres.[ref]:[pw]@aws-0-...:5432/postgres"
#   SUPABASE_DB_URL_PROD="postgresql://..."  # 운영용
#
# Connection string 위치: Supabase 대시보드
#   Project Settings → Database → Connection string → URI
# 큰 INSERT 가 끊기지 않도록 direct 5432 또는 session pooler 5432 사용 권장.
# transaction pooler 6543은 seed 대량 적용에 비권장.

ENV ?= dev
OPS_ENV_FILE ?= .env.ops
OPS_ENV := $(shell if [ "$(ENV)" = "dev" ]; then printf "dev"; elif [ "$(ENV)" = "real" ] || [ "$(ENV)" = "prod" ]; then printf "prod"; else printf "invalid"; fi)
OPS_ENV_SUFFIX := $(shell if [ "$(OPS_ENV)" = "dev" ]; then printf "DEV"; elif [ "$(OPS_ENV)" = "prod" ]; then printf "PROD"; else printf "INVALID"; fi)
DB_URL_VAR := SUPABASE_DB_URL_$(OPS_ENV_SUFFIX)

# DB의 published events 를 assets/200_stories/*.json 으로 역추출.
# 빌더(build-character-meta 등)가 로컬 JSON만 스캔하므로, 로컬이 비었거나
# 오래된 상태에서 빌드하면 description 이 부분 정보로 덮어써질 수 있다.
# 새 이야기 추가 전에 항상 이 타겟으로 로컬을 DB 와 동기화한 뒤 작업한다.
# 상세: docs/CONTENT_UPDATE.md §2.1b [0]
export-stories-json:
	@echo "[Makefile] DB events → $(STORIES_DIR)/*.json 역추출 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/export/export_events_to_json.py \
		--output-dir $(STORIES_DIR) \
		--env $(OPS_ENV)

export-quizzes-json:
	@echo "[Makefile] DB quiz_questions → $(ASSETS_DIR)/quizzes/*.json 역추출 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/export/export_quizzes_to_json.py \
		--output-dir $(ASSETS_DIR)/quizzes \
		--events-output $(SUPABASE_DIR)/quizzes/db_events.json \
		--env $(OPS_ENV)

export-event-region-mapping:
	@echo "[Makefile] DB events.landmark_id → $(LANDMARKS_DIR)/event_region_mapping.json 역추출 (ENV=$(ENV) → ops=$(OPS_ENV))"
	$(PYTHON) $(TOOLS_DIR)/export/export_event_region_mapping.py \
		--output $(LANDMARKS_DIR)/event_region_mapping.json \
		--env $(OPS_ENV)

release-sync-stories:
	$(MAKE) export-stories-json ENV=$(ENV) OPS_ENV_FILE=$(OPS_ENV_FILE)
	$(MAKE) export-quizzes-json ENV=$(ENV) OPS_ENV_FILE=$(OPS_ENV_FILE)
	$(MAKE) export-event-region-mapping ENV=$(ENV) OPS_ENV_FILE=$(OPS_ENV_FILE)
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(OPS_ENV) --skip-post-processing
	$(MAKE) ensure-story-image-sources ENV=$(ENV) OPS_ENV_FILE=$(OPS_ENV_FILE) STORY_IMAGE_SOURCE_BUCKET=$(STORY_IMAGE_SOURCE_BUCKET)
	$(MAKE) thumbnails
	$(MAKE) update-pubspec-assets
	$(MAKE) upload-story-image-sources ENV=$(ENV) OPS_ENV_FILE=$(OPS_ENV_FILE) STORY_IMAGE_SOURCE_BUCKET=$(STORY_IMAGE_SOURCE_BUCKET)
	@echo "[Makefile] release sync 완료 — stories, quizzes, landmark mapping, 승인 자산, 썸네일, pubspec 확인 필요."

# .env + .env.ops 파일을 한 셸 안에서만 source 한 뒤 psql 호출.
# ON_ERROR_STOP=1 → 첫 에러에서 즉시 중단.
# --single-transaction → 자체 begin/commit 이 없는 SQL 파일만 감싸 부분 적용 방지.
define PSQL_APPLY
	@if [ ! -f .env ]; then echo "ERROR: .env not found"; exit 1; fi; \
	if [ "$(OPS_ENV)" = "invalid" ]; then \
		echo "ERROR: ENV must be dev, real, or prod (got: $(ENV))"; exit 1; \
	fi; \
	ops_env_file="$(OPS_ENV_FILE)"; \
	set -a; . ./.env; \
	if [ -f "$$ops_env_file" ]; then . "$$ops_env_file"; fi; \
	set +a; \
	url="$${$(DB_URL_VAR)}"; \
	if [ -z "$$url" ]; then \
		echo "ERROR: $(DB_URL_VAR) is empty in $(OPS_ENV_FILE)"; exit 1; \
	fi; \
	for f in $(1); do \
		[ -f "$$f" ] || { echo "skip (missing): $$f"; continue; }; \
		echo "[apply] $$f"; \
		if grep -Eiq '^[[:space:]]*(begin|start transaction)[[:space:];]*($$|--)' "$$f"; then \
			psql "$$url" -v ON_ERROR_STOP=1 -f "$$f" || exit 1; \
		else \
			psql "$$url" -v ON_ERROR_STOP=1 --single-transaction -f "$$f" || exit 1; \
		fi; \
	done
endef

db-init:
	@if [ "$(OPS_ENV)" = "prod" ] && [ "$(CONFIRM_REAL_DB_INIT)" != "1" ]; then \
		echo "ERROR: real/prod db-init is blocked because it drops and recreates the database."; \
		echo "Use idempotent patch SQL: make apply-patch ENV=real PATCH=supabase/patches/<file>.sql"; \
		echo "Only for brand-new/recovery bootstrap, rerun with CONFIRM_REAL_DB_INIT=1."; \
		exit 1; \
	fi
	@echo "[Makefile] db_init.sql 적용 (ENV=$(ENV) → ops=$(OPS_ENV), $(DB_URL_VAR)) — DROP & RECREATE 주의"
	@echo "[Makefile] 선행: Storage buckets 비우기 (SQL 에선 트리거 차단됨 → REST API)"
	$(PYTHON) $(TOOLS_DIR)/supabase/purge_owned_buckets.py --env $(OPS_ENV) --strict
	$(call PSQL_APPLY,db_init.sql)

apply-patch:
	@if [ -z "$(PATCH)" ]; then \
		echo "ERROR: PATCH is required. Example: make apply-patch ENV=real PATCH=supabase/patches/20260622_add_column.sql"; \
		exit 1; \
	fi
	@if [ ! -f "$(PATCH)" ]; then \
		echo "ERROR: patch file not found: $(PATCH)"; \
		exit 1; \
	fi
	@echo "[Makefile] patch 적용 (ENV=$(ENV) → ops=$(OPS_ENV), $(DB_URL_VAR)): $(PATCH)"
	$(call PSQL_APPLY,$(PATCH))

# Bible verses 시드는 PK 충돌 시 에러 → 보통 1회만 실행 (db_init.sql 직후).
apply-bible-verses-seeds:
	@echo "[Makefile] KRV 성경 구절 시드 적용 (ENV=$(ENV) → ops=$(OPS_ENV), $(DB_URL_VAR))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql)

# characters / events 는 UPSERT 패턴이라 재실행 안전.
apply-seeds-stories-characters:
	@echo "[Makefile] characters + 200_stories 시드 적용 (ENV=$(ENV) → ops=$(OPS_ENV), $(DB_URL_VAR))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/200_stories/characters_seed.sql $(SUPABASE_DIR)/200_stories/events_scene_captions_schema_patch.sql $(SUPABASE_DIR)/200_stories/200_stories_seed_part_*.sql)

# landmarks 는 UPSERT 패턴 — 재실행 안전.
apply-seeds-landmarks:
	@echo "[Makefile] landmarks 시드 적용 (ENV=$(ENV) → ops=$(OPS_ENV), $(DB_URL_VAR))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/200_stories/landmarks_seed.sql)

apply-seeds-quizzes:
	@echo "[Makefile] quiz_questions 시드 적용 (ENV=$(ENV) → ops=$(OPS_ENV), $(DB_URL_VAR))"
	$(call PSQL_APPLY,$(QUIZZES_SQL))

apply-seeds: apply-bible-verses-seeds apply-seeds-landmarks apply-seeds-stories-characters apply-seeds-quizzes
	@echo "[Makefile] 전체 시드 적용 완료."

# =============================================================================
# 유틸리티
# =============================================================================

update-pubspec-assets:
	@echo "[Makefile] pubspec.yaml의 story_images_thumbs 경로 업데이트..."
	$(PYTHON) $(TOOLS_DIR)/app/update_pubspec_assets.py

check-pubspec-assets:
	@echo "[Makefile] pubspec.yaml이 story_images_thumbs 디렉토리와 동기화되어 있는지 확인..."
	$(PYTHON) $(TOOLS_DIR)/app/update_pubspec_assets.py --check

build-guides:
	@echo "[Makefile] docs/guides story guide + HTML 문서 생성..."
	$(PYTHON) $(TOOLS_DIR)/docs/build_guides.py

lint:
	@echo "[Makefile] Python 포맷 검사 (black)..."
	black --check $(TOOLS_DIR)/seed $(TOOLS_DIR)/images $(TOOLS_DIR)/app $(TOOLS_DIR)/lint $(TOOLS_DIR)/export $(TOOLS_DIR)/docs

clean-generated:
	@echo "[Makefile] 생성된 SQL 삭제..."
	rm -f $(KRV_SQL) $(STORIES_SQL) $(CHARACTERS_SQL) $(LANDMARKS_SQL) $(QUIZZES_SQL) $(QUIZZES_REPORT)
	rm -f $(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql
	@echo "  → tools/seed/character_meta.json은 유지됨 (수동 삭제)"
