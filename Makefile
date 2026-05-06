# Story Bible — 데이터 파이프라인 오케스트레이션
#
# 사용법:
#   make <target>        # 특정 타겟 실행
#   make all             # 전체 파이프라인
#   make -n <target>     # dry-run (실행 없이 명령만 출력)
#
# 선행 조건:
#   - source .venv/bin/activate (Python 가상환경)
#   - .env 설정 (GOOGLE_CLOUD_PROJECT 등)
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

# 출력 SQL
KRV_SQL := $(SUPABASE_DIR)/seeds/krv_bible_verses.sql
STORIES_SQL := $(SUPABASE_DIR)/200_stories/200_stories_seed.sql
CHARACTERS_SQL := $(SUPABASE_DIR)/200_stories/characters_seed.sql
LANDMARKS_SQL := $(SUPABASE_DIR)/200_stories/landmarks_seed.sql
ERA_BOUNDARIES_SQL := $(SUPABASE_DIR)/200_stories/era_boundaries_seed.sql
LANDMARKS_DIR := $(ASSETS_DIR)/landmarks

# =============================================================================
# .PHONY 선언
# =============================================================================

.PHONY: help all \
        seed-bible-verses build-character-meta renumber-story-indices \
        seed-stories seed-characters seed-stories-characters seed-quizzes \
        seed-landmarks seed-era-boundaries \
        apply-seeds-landmarks-v2 \
        generate-avatars generate-story-images generate-basemap thumbnails \
        seed-all generate-all \
        export-stories-json \
        db-init apply-seeds apply-bible-verses-seeds apply-seeds-stories-characters \
        apply-seeds-landmarks apply-seeds-era-boundaries \
        upload-character-avatars upload-character-avatars-force \
        sync-approved-proposal-assets sync-approved-proposal-assets-all \
        sync-approved-proposal-assets-dry sync-approved-proposal-assets-clean \
        cleanup-orphan-proposal-assets cleanup-orphan-proposal-assets-dry \
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
	@echo "  seed-stories            events SQL 생성 (→ character-meta 의존)"
	@echo "  seed-characters            characters SQL 생성 (→ character-meta 의존)"
	@echo "  seed-stories-characters    events + characters SQL 한 번에 생성 (권장)"
	@echo "  seed-quizzes               퀴즈 SQL 생성 (→ seed-stories 선행 필요)"
	@echo "  generate-avatars        Vertex AI 아바타 생성 (→ character-meta 의존, 기존 png 보존)"
	@echo "  generate-story-images   Vertex AI 장면 이미지 생성"
	@echo "  generate-basemap        Vertex AI 양피지 일러스트 베이스맵 1장 생성 (assets/maps/)"
	@echo "  thumbnails              썸네일 생성 (→ avatars, story-images 의존)"
	@echo ""
	@echo "묶음 타겟:"
	@echo "  seed-all                전체 SQL 생성 (bible + stories + characters + quizzes)"
	@echo "  generate-all            전체 이미지 생성 (avatars + story-images + thumbnails)"
	@echo "  all                     전체 파이프라인 (seed-all + generate-all)"
	@echo ""
	@echo "DB → 로컬 동기화:"
	@echo "  export-stories-json       [ENV=dev]  DB events → assets/200_stories/*.json 역추출 (빌더 사전 조건)"
	@echo ""
	@echo "DB 적용 (psql + .env의 SUPABASE_DB_URL_$(ENV)):"
	@echo "  db-init                   [ENV=dev]  db_init.sql 실행 (drop & recreate, 파괴적!)"
	@echo "  apply-bible-verses-seeds  [ENV=dev]  krv 성경 구절만 적용 (1회성, 중복 INSERT 시 에러)"
	@echo "  apply-seeds-stories-characters       [ENV=dev]  characters + 200_stories 적용 (UPSERT — 재실행 안전)"
	@echo "  apply-seeds               [ENV=dev]  위 둘 모두 (최초 부트스트랩용)"
	@echo ""
	@echo "Supabase Storage (service_role 키 필요):"
	@echo "  upload-character-avatars        [ENV=dev]  assets/avatars/*.png → characters/ 버킷 (이미 있으면 스킵)"
	@echo "  upload-character-avatars-force  [ENV=dev]  전부 덮어쓰기 업로드 (--overwrite)"
	@echo ""
	@echo "승인된 제안 → 로컬 assets 동기화 (service_role 키 필요, idempotent):"
	@echo "  - Phase A: 승인된 신규 제안의 PNG 다운로드(synced_to_local_at NULL 만)"
	@echo "  - Phase B: 삭제 승인된 events / 비활성화된 characters 의 로컬+storage 잔존 정리"
	@echo "  sync-approved-proposal-assets         [ENV=dev]  Phase A + B 자동 실행"
	@echo "  sync-approved-proposal-assets-all     [ENV=dev]  Phase A 마커 무시하고 재동기화 + B"
	@echo "  sync-approved-proposal-assets-dry     [ENV=dev]  dry-run — 대상 목록만 출력"
	@echo "  sync-approved-proposal-assets-clean   [ENV=dev]  Phase A 동기화 후 proposal-* 원본 삭제 (앱 배포 후에만!)"
	@echo ""
	@echo "미제출 제안 고아 자산 정리 (주기적 운영 — 24h grace window):"
	@echo "  cleanup-orphan-proposal-assets-dry    [ENV=dev]  dry-run — 삭제 후보만 나열"
	@echo "  cleanup-orphan-proposal-assets        [ENV=dev]  실제 삭제"
	@echo ""
	@echo "기타:"
	@echo "  update-pubspec-assets   story_images_thumbs 경로를 pubspec.yaml에 반영"
	@echo "  check-pubspec-assets    pubspec.yaml이 최신인지 확인 (CI용)"
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

seed-era-boundaries:
	@echo "[Makefile] era_boundaries SQL 생성 (assets/landmarks/era_boundaries.json)..."
	$(PYTHON) $(TOOLS_DIR)/seed/build_era_boundaries_seed_sql.py \
		--input $(LANDMARKS_DIR)/era_boundaries.json \
		--output $(ERA_BOUNDARIES_SQL)

# 시대 폴리곤 재생성 — Natural Earth GeoJSON 을 시대별 bbox 로 클립해 정밀한
# 해안선 폴리곤으로 era_boundaries.json 을 덮어쓴다. 시대 정의 변경 시 (CLIP_REGIONS
# in tools/seed/build_era_boundaries_from_geojson.py) 실행.
# ⚠️ 수동 편집한 era_boundaries.json 이 있다면 덮어쓰니 주의.
regen-era-boundaries:
	@echo "[Makefile] era_boundaries.json 재생성 (Natural Earth GeoJSON 클립)..."
	$(PYTHON) $(TOOLS_DIR)/seed/build_era_boundaries_from_geojson.py \
		--geojson $(ASSETS_DIR)/maps/ne_50m_admin_0_countries.geojson \
		--output $(LANDMARKS_DIR)/era_boundaries.json
	@$(MAKE) seed-era-boundaries

seed-quizzes:
	@echo "[Makefile] 퀴즈 SQL 생성..."
	@# 권위 소스: supabase/quizzes/db_events.json (dev DB 스냅샷).
	@# main 의 200_stories_seed.sql 과 dev DB 가 같은 (era,story_index) 키에
	@# 서로 다른 이야기를 담고 있어, 시드 파일을 기준으로 빌드하면 title이
	@# 어긋난 SQL 이 생성된다. DB 와 seed 가 일치할 때까지 db_events.json 을
	@# 단일 진실 소스로 사용한다.
	$(PYTHON) $(TOOLS_DIR)/seed/build_quizzes_seed_sql.py \
		--input-dir $(ASSETS_DIR)/quizzes \
		--output $(SUPABASE_DIR)/quizzes/quizzes_seed.sql \
		--report $(SUPABASE_DIR)/quizzes/quizzes_report.json \
		--events-from-json $(SUPABASE_DIR)/quizzes/db_events.json

seed-all: seed-bible-verses seed-stories seed-characters seed-quizzes seed-landmarks seed-era-boundaries
	@echo "[Makefile] 전체 SQL 생성 완료. Supabase SQL Editor에서 실행하세요."

# =============================================================================
# 이미지 생성 (Vertex AI)
# =============================================================================

generate-avatars: build-character-meta
	@echo "[Makefile] Vertex AI 아바타 생성..."
	@echo "  → .env의 GOOGLE_CLOUD_PROJECT 확인 필요"
	$(PYTHON) $(TOOLS_DIR)/images/generate_avatars_vertex.py \
		--character-meta-json $(CHARACTER_META) \
		--output-dir $(AVATARS_DIR)

generate-story-images:
	@echo "[Makefile] Vertex AI 장면 이미지 생성..."
	@echo "  → .env의 GOOGLE_CLOUD_PROJECT 확인 필요"
	$(PYTHON) $(TOOLS_DIR)/images/generate_event_story_images_vertex.py

generate-basemap:
	@. .venv/bin/activate && python $(TOOLS_DIR)/images/generate_illustrated_basemap.py

thumbnails:
	@echo "[Makefile] 썸네일 생성..."
	$(PYTHON) $(TOOLS_DIR)/images/generate_runtime_thumbnails.py

generate-all: generate-avatars generate-story-images thumbnails
	@echo "[Makefile] 전체 이미지 생성 완료."

# =============================================================================
# Supabase Storage 업로드 (아바타)
# =============================================================================
# 전제: .env 에 SUPABASE_URL_<ENV>, SUPABASE_SERVICE_ROLE_KEY_<ENV> 설정
# db_init.sql 실행 후 한 번 돌리면 characters/ 버킷에 124개 PNG 업로드
# + characters.avatar_storage_path 가 채워진다.
# 재실행 안전: --overwrite 로 덮어쓰기 가능.

upload-character-avatars:
	@echo "[Makefile] Supabase Storage 에 캐릭터 아바타 업로드 (ENV=$(ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/upload_character_avatars.py --env $(ENV)

upload-character-avatars-force:
	@echo "[Makefile] 캐릭터 아바타 강제 덮어쓰기 업로드 (ENV=$(ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/upload_character_avatars.py --env $(ENV) --overwrite

# -----------------------------------------------------------------------------
# 승인된 제안 → 로컬 assets 동기화
# -----------------------------------------------------------------------------
# 관리자가 제안을 승인한 뒤, proposal-scenes / proposal-characters 버킷에 있는
# AI 생성 이미지를 로컬 assets/ 로 내려받아 번들에 포함시킨다. 동시에 새 캐릭터
# 는 characters 버킷으로 복사 + characters.avatar_storage_path 도 canonical
# 경로(`{code}.png`) 로 재세팅. 이 타겟을 돌린 뒤 make thumbnails +
# apply-seeds-stories-characters 를 실행해 최종 반영.

sync-approved-proposal-assets:
	@echo "[Makefile] 승인된 제안 자산 동기화 (ENV=$(ENV)) — synced_to_local_at NULL 인 것만"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(ENV)

sync-approved-proposal-assets-all:
	@echo "[Makefile] 승인된 제안 자산 전체 재동기화 (ENV=$(ENV)) — synced marker 무시"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(ENV) --all

sync-approved-proposal-assets-dry:
	@echo "[Makefile] 승인된 제안 자산 동기화 dry-run (ENV=$(ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(ENV) --dry-run

sync-approved-proposal-assets-clean:
	@echo "[Makefile] 승인된 제안 자산 동기화 + 원본 버킷 정리 (ENV=$(ENV))"
	@echo "  ⚠️  앱 배포 전이면 하이브리드 fallback 깨짐 — 배포 완료 후 사용 권장"
	$(PYTHON) $(TOOLS_DIR)/supabase/sync_approved_proposal_assets.py --env $(ENV) --delete-source

# -----------------------------------------------------------------------------
# 미제출 / 버려진 제안 자산 청소
# -----------------------------------------------------------------------------
# 사역자가 이미지 생성 버튼을 누른 뒤 [제안 등록] 안 하고 창을 닫으면 Storage
# 에 고아 이미지가 남는다. 이 타겟은 24시간 이상 지났고 event_proposals
# 어디에도 참조되지 않은 proposal-* 파일을 정리한다. 주 1회 cron 이나 운영
# 루틴에 끼워 넣으면 깔끔.

cleanup-orphan-proposal-assets-dry:
	@echo "[Makefile] 고아 제안 자산 dry-run — 실제 삭제 없이 나열만 (ENV=$(ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/cleanup_orphan_proposal_assets.py --env $(ENV) --dry-run

cleanup-orphan-proposal-assets:
	@echo "[Makefile] 고아 제안 자산 정리 — 24시간 이상 지난 미참조 파일 삭제 (ENV=$(ENV))"
	$(PYTHON) $(TOOLS_DIR)/supabase/cleanup_orphan_proposal_assets.py --env $(ENV)

# =============================================================================
# Supabase DB 적용 (psql 사용)
# =============================================================================
# 사용법:
#   make apply-seeds              # ENV=dev (기본) — SUPABASE_DB_URL_DEV 사용
#   make apply-seeds ENV=prod     # SUPABASE_DB_URL_PROD 사용
#
# .env 에 다음을 추가해야 한다:
#   SUPABASE_DB_URL_DEV="postgresql://postgres.[ref]:[pw]@aws-0-...:5432/postgres"
#   SUPABASE_DB_URL_PROD="postgresql://..."  # 운영용
#
# Connection string 위치: Supabase 대시보드
#   Project Settings → Database → Connection string → URI
# 큰 INSERT 가 끊기지 않도록 direct 5432 포트 사용 권장 (pooler 6543 비권장).

ENV ?= dev
DB_URL_VAR := SUPABASE_DB_URL_$(shell echo $(ENV) | tr a-z A-Z)

# DB의 published events 를 assets/200_stories/*.json 으로 역추출.
# 빌더(build-character-meta 등)가 로컬 JSON만 스캔하므로, 로컬이 비었거나
# 오래된 상태에서 빌드하면 description 이 부분 정보로 덮어써질 수 있다.
# 새 이야기 추가 전에 항상 이 타겟으로 로컬을 DB 와 동기화한 뒤 작업한다.
# 상세: docs/CONTENT_UPDATE.md §2.1b [0]
export-stories-json:
	@echo "[Makefile] DB events → $(STORIES_DIR)/*.json 역추출 (ENV=$(ENV))"
	$(PYTHON) $(TOOLS_DIR)/export/export_events_to_json.py \
		--output-dir $(STORIES_DIR) \
		--env $(ENV)

# .env 파일을 한 셸 안에서만 source 한 뒤 psql 호출.
# ON_ERROR_STOP=1 → 첫 에러에서 즉시 중단.
# --single-transaction → 시드 한 파일을 트랜잭션으로 감싸 부분 적용 방지.
define PSQL_APPLY
	@if [ ! -f .env ]; then echo "ERROR: .env not found"; exit 1; fi; \
	set -a; . ./.env; set +a; \
	url="$${$(DB_URL_VAR)}"; \
	if [ -z "$$url" ]; then \
		echo "ERROR: $(DB_URL_VAR) is empty in .env"; exit 1; \
	fi; \
	for f in $(1); do \
		[ -f "$$f" ] || { echo "skip (missing): $$f"; continue; }; \
		echo "[apply] $$f"; \
		psql "$$url" -v ON_ERROR_STOP=1 --single-transaction -f "$$f" || exit 1; \
	done
endef

db-init:
	@echo "[Makefile] db_init.sql 적용 (ENV=$(ENV)) — DROP & RECREATE 주의"
	@echo "[Makefile] 선행: Storage buckets 비우기 (SQL 에선 트리거 차단됨 → REST API)"
	@$(PYTHON) $(TOOLS_DIR)/supabase/purge_owned_buckets.py --env $(ENV) || \
	  echo "[Makefile] (Storage purge 스킵 — service_role 키 없거나 실패, db-init 은 계속)"
	$(call PSQL_APPLY,db_init.sql)

# Bible verses 시드는 PK 충돌 시 에러 → 보통 1회만 실행 (db_init.sql 직후).
apply-bible-verses-seeds:
	@echo "[Makefile] KRV 성경 구절 시드 적용 (ENV=$(ENV))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql)

# characters / events 는 UPSERT 패턴이라 재실행 안전.
apply-seeds-stories-characters:
	@echo "[Makefile] characters + 200_stories 시드 적용 (ENV=$(ENV))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/200_stories/characters_seed.sql $(SUPABASE_DIR)/200_stories/200_stories_seed_part_*.sql)

# landmarks / era_boundaries 모두 UPSERT 패턴 — 재실행 안전.
apply-seeds-landmarks:
	@echo "[Makefile] landmarks 시드 적용 (ENV=$(ENV))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/200_stories/landmarks_seed.sql)

apply-seeds-era-boundaries:
	@echo "[Makefile] era_boundaries 시드 적용 (ENV=$(ENV))"
	$(call PSQL_APPLY,$(ERA_BOUNDARIES_SQL))

apply-seeds: apply-bible-verses-seeds apply-seeds-landmarks apply-seeds-stories-characters apply-seeds-era-boundaries
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

lint:
	@echo "[Makefile] Python 포맷 검사 (black)..."
	black --check $(TOOLS_DIR)/seed $(TOOLS_DIR)/images $(TOOLS_DIR)/app $(TOOLS_DIR)/lint $(TOOLS_DIR)/export

clean-generated:
	@echo "[Makefile] 생성된 SQL 삭제..."
	rm -f $(KRV_SQL) $(STORIES_SQL) $(CHARACTERS_SQL) $(LANDMARKS_SQL) $(ERA_BOUNDARIES_SQL)
	rm -f $(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql
	@echo "  → tools/seed/character_meta.json은 유지됨 (수동 삭제)"
