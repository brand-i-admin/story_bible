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
AVATAR_PROMPTS := $(TOOLS_DIR)/avatar_prompts.json
STORIES_DIR := $(ASSETS_DIR)/200_stories
BIBLE_DIR := $(ASSETS_DIR)/bible
AVATARS_DIR := $(ASSETS_DIR)/avatars
AVATARS_THUMBS_DIR := $(ASSETS_DIR)/avatars_thumbs
STORY_IMAGES_DIR := $(ASSETS_DIR)/story_images
STORY_IMAGES_THUMBS_DIR := $(ASSETS_DIR)/story_images_thumbs

# 출력 SQL
KRV_SQL := $(SUPABASE_DIR)/seeds/krv_bible_verses.sql
STORIES_SQL := $(SUPABASE_DIR)/200_stories/200_stories_seed.sql
PERSONS_SQL := $(SUPABASE_DIR)/200_stories/persons_seed.sql

# =============================================================================
# .PHONY 선언
# =============================================================================

.PHONY: help all \
        seed-bible-verses build-avatar-prompts seed-stories seed-persons \
        seed-quizzes \
        generate-avatars generate-story-images thumbnails \
        seed-all generate-all \
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
	@echo "  build-avatar-prompts    아바타 프롬프트 JSON 생성"
	@echo "  seed-stories            이야기 SQL 생성 (→ avatar-prompts 의존)"
	@echo "  seed-persons            인물 SQL 생성 (→ avatar-prompts 의존)"
	@echo "  seed-quizzes            퀴즈 SQL 생성 (→ seed-stories 선행 필요)"
	@echo "  generate-avatars        Vertex AI 아바타 생성 (→ avatar-prompts 의존)"
	@echo "  generate-story-images   Vertex AI 장면 이미지 생성"
	@echo "  thumbnails              썸네일 생성 (→ avatars, story-images 의존)"
	@echo ""
	@echo "묶음 타겟:"
	@echo "  seed-all                전체 SQL 생성 (bible + stories + persons + quizzes)"
	@echo "  generate-all            전체 이미지 생성 (avatars + story-images + thumbnails)"
	@echo "  all                     전체 파이프라인 (seed-all + generate-all)"
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
	@echo "[Makefile] KRV 성경 구절 SQL 생성..."
	$(PYTHON) $(TOOLS_DIR)/build_krv_seed_sql.py \
		--input-dir $(BIBLE_DIR) \
		--output $(KRV_SQL) \
		--truncate-translation

build-avatar-prompts:
	@echo "[Makefile] 아바타 프롬프트 JSON 생성..."
	$(PYTHON) $(TOOLS_DIR)/build_avatar_prompts_json.py \
		--stories-dir $(STORIES_DIR) \
		--output $(AVATAR_PROMPTS) \
		--min-mentions 2

seed-stories: build-avatar-prompts
	@echo "[Makefile] 200 stories SQL 생성..."
	$(PYTHON) $(TOOLS_DIR)/build_200_stories_seed_sql.py \
		--output-dir $(SUPABASE_DIR)/200_stories \
		--avatar-prompt-json $(AVATAR_PROMPTS)

seed-persons: build-avatar-prompts
	@echo "[Makefile] persons SQL 생성..."
	$(PYTHON) $(TOOLS_DIR)/build_persons_seed_sql.py \
		--avatar-prompt-json $(AVATAR_PROMPTS) \
		--stories-dir $(STORIES_DIR) \
		--output $(PERSONS_SQL)

seed-quizzes:
	@echo "[Makefile] 퀴즈 SQL 생성..."
	$(PYTHON) $(TOOLS_DIR)/build_quizzes_seed_sql.py \
		--input-dir $(ASSETS_DIR)/quizzes \
		--output $(SUPABASE_DIR)/quizzes/quizzes_seed.sql \
		--report $(SUPABASE_DIR)/quizzes/quizzes_report.json \
		--events-seed-sql $(SUPABASE_DIR)/200_stories/200_stories_seed.sql

seed-all: seed-bible-verses seed-stories seed-persons seed-quizzes
	@echo "[Makefile] 전체 SQL 생성 완료. Supabase SQL Editor에서 실행하세요."

# =============================================================================
# 이미지 생성 (Vertex AI)
# =============================================================================

generate-avatars: build-avatar-prompts
	@echo "[Makefile] Vertex AI 아바타 생성..."
	@echo "  → .env의 GOOGLE_CLOUD_PROJECT 확인 필요"
	$(PYTHON) $(TOOLS_DIR)/generate_avatars_vertex.py \
		--prompt-json $(AVATAR_PROMPTS) \
		--output-dir $(AVATARS_DIR)

generate-story-images:
	@echo "[Makefile] Vertex AI 장면 이미지 생성..."
	@echo "  → .env의 GOOGLE_CLOUD_PROJECT 확인 필요"
	$(PYTHON) $(TOOLS_DIR)/generate_event_story_images_vertex.py

thumbnails:
	@echo "[Makefile] 썸네일 생성..."
	$(PYTHON) $(TOOLS_DIR)/generate_runtime_thumbnails.py

generate-all: generate-avatars generate-story-images thumbnails
	@echo "[Makefile] 전체 이미지 생성 완료."

# =============================================================================
# 유틸리티
# =============================================================================

update-pubspec-assets:
	@echo "[Makefile] pubspec.yaml의 story_images_thumbs 경로 업데이트..."
	$(PYTHON) $(TOOLS_DIR)/update_pubspec_assets.py

check-pubspec-assets:
	@echo "[Makefile] pubspec.yaml이 story_images_thumbs 디렉토리와 동기화되어 있는지 확인..."
	$(PYTHON) $(TOOLS_DIR)/update_pubspec_assets.py --check

lint:
	@echo "[Makefile] Python 포맷 검사 (black)..."
	black --check $(TOOLS_DIR)

clean-generated:
	@echo "[Makefile] 생성된 SQL 삭제..."
	rm -f $(KRV_SQL) $(STORIES_SQL) $(PERSONS_SQL)
	rm -f $(SUPABASE_DIR)/seeds/krv_bible_verses_part_*.sql
	@echo "  → tools/avatar_prompts.json은 유지됨 (수동 삭제)"
