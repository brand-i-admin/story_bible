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

# =============================================================================
# .PHONY 선언
# =============================================================================

.PHONY: help all \
        seed-bible-verses build-character-meta \
        seed-stories seed-characters seed-stories-characters \
        generate-avatars generate-story-images thumbnails \
        seed-all generate-all \
        export-stories-json \
        db-init apply-seeds apply-bible-verses-seeds apply-seeds-stories-characters \
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
	@echo "  generate-avatars        Vertex AI 아바타 생성 (→ character-meta 의존, 기존 png 보존)"
	@echo "  generate-story-images   Vertex AI 장면 이미지 생성"
	@echo "  thumbnails              썸네일 생성 (→ avatars, story-images 의존)"
	@echo ""
	@echo "묶음 타겟:"
	@echo "  seed-all                전체 SQL 생성 (bible + stories + characters)"
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

seed-all: seed-bible-verses seed-stories seed-characters
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

thumbnails:
	@echo "[Makefile] 썸네일 생성..."
	$(PYTHON) $(TOOLS_DIR)/images/generate_runtime_thumbnails.py

generate-all: generate-avatars generate-story-images thumbnails
	@echo "[Makefile] 전체 이미지 생성 완료."

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
	$(call PSQL_APPLY,db_init.sql)

# Bible verses 시드는 PK 충돌 시 에러 → 보통 1회만 실행 (db_init.sql 직후).
apply-bible-verses-seeds:
	@echo "[Makefile] KRV 성경 구절 시드 적용 (ENV=$(ENV))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql)

# characters / events 는 UPSERT 패턴이라 재실행 안전.
apply-seeds-stories-characters:
	@echo "[Makefile] characters + 200_stories 시드 적용 (ENV=$(ENV))"
	$(call PSQL_APPLY,$(SUPABASE_DIR)/200_stories/characters_seed.sql $(SUPABASE_DIR)/200_stories/200_stories_seed_part_*.sql)

apply-seeds: apply-bible-verses-seeds apply-seeds-stories-characters
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
	rm -f $(KRV_SQL) $(STORIES_SQL) $(CHARACTERS_SQL)
	rm -f $(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql
	@echo "  → tools/seed/character_meta.json은 유지됨 (수동 삭제)"
