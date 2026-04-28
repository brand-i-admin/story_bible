# PRD — 이야기 성경 (Story Bible)

> 최종 수정: 2026-04-16

## 1. 제품 비전

지도 위에서 성경 이야기를 인물별로 탐색하며, 퀴즈와 학습 진행 추적을 통해 성경을 체계적으로 공부할 수 있는 인터랙티브 학습 앱.

## 2. 핵심 사용자

| 구분 | 설명 |
|------|------|
| 1차 사용자 | 한국어 성경 공부 초중급자 (개인/소그룹) |
| 2차 사용자 | 교회학교 교사, 성경 스터디 리더 |
| 언어 | 한국어 (KRV 개역한글) |

## 3. 기술 스택

| 영역 | 기술 |
|------|------|
| 프론트엔드 | Flutter (Dart 3.8+), Riverpod 2.6 |
| 백엔드 | Supabase (PostgreSQL + Auth + Storage + RLS) |
| 지도 | flutter_map + OpenStreetMap 타일 |
| AI 에셋 생성 | Google Cloud Vertex AI Imagen |
| 인증 | Apple / Google / Kakao 소셜 로그인 |
| 성경 텍스트 | KRV 개역한글 (31,904절) |

## 4. 핵심 기능

### 4.1 MVP (현재 구현됨)

#### 시대/인물/사건 탐색
- 구약(6시대) / 신약(4시대) 선택
- 시대별 인물 목록 → 복수 선택 가능
- 선택된 인물의 사건을 시간순 타임라인으로 병합
- 인물별 색상(8색 팔레트) 구분

#### 인터랙티브 지도
- 사건 위치를 지도 핀으로 표시
- 시대별 지도 중심/줌 자동 이동
- 핀 클릭 → 이야기 상세 다이얼로그

#### 이야기 상세
- 요약(summary), 4장면 이미지 + 장면별 등장인물
- 성경 구절 참조 (KRV)
- 학습 완료 체크 + XP 획득 (score × 10)

#### 사용자 기능
- 프로필 관리 (닉네임, 사진, 기도제목)
- 개인 노트 작성/관리
- 성경 구절 북마크
- 출석/학습 연속일수 추적

#### 기도 공유
- 7자리 공유 코드로 타인의 기도제목 구독
- 중보기도 목록 관리

#### 검색
- 이벤트 전체 텍스트 검색 (디바운스 220ms)
- 제목/요약/본문/장소/인물명 가중치 스코어링

### 4.2 향후 기능

| 기능 | 상태 | 비고 |
|------|------|------|
| 어드민 웹 | admin/ 폐기, 메인 앱 웹 버전으로 이전 진행 중 (ADR-016) | 2026-04 구조 전환: 별도 `admin/` Flutter Web 제거 → 메인 앱의 웹 버전에 "이야기 제안" 게시판 탭 신설. 사역자(목회자)로 인증된 사용자만 제안 가능, 관리자가 승인하면 events 로 반영. DB 준비(Phase 1) 완료, UI 구현(Phase 2~6) 진행 예정. |
| 퀴즈 시스템 | DB 스키마 있음, 데이터 미구축 | `quiz_questions` 테이블 존재 |
| 시맨틱 검색 | 스키마 있음 | `search_embeddings` (pgvector 1536차원) |
| 다국어 지원 | 미착수 | bible_verses.translation 컬럼 대응 가능 |
| 소셜 확장 | 기본만 | 랭킹, 친구, 그룹 스터디 |

## 5. 데이터 파이프라인 개요

성경 텍스트 → 이야기 JSON → DB 시딩 + AI 이미지 생성의 다단계 파이프라인.
상세는 `docs/DATA_PIPELINE.md` 참조.

```
assets/bible/*.txt ─→ build_krv_seed_sql.py ─→ bible_verses SQL
assets/200_stories/ (각 항목에 story_index 직접 박힘)
                    ├→ build_character_meta_json.py    ─→ character_meta.json (모든 인물 + 아바타 프롬프트)
                    ├→ build_200_stories_seed_sql.py ─→ events SQL (jsonb/배열 흡수)
                    ├→ build_characters_seed_sql.py ─→ characters SQL (is_active 토글 보존)
                    ├→ generate_avatars_vertex.py ─→ 아바타 PNG (기존 보존)
                    └→ generate_event_story_images_vertex.py ─→ 장면 이미지
```

## 6. 성공 지표

| 지표 | 목표 |
|------|------|
| 인물별 학습 완료율 | 사용자당 최소 1시대 전체 완료 |
| 일일 활성 사용자 (DAU) | 출시 후 3개월 100명 |
| 학습 연속일수 | 평균 7일 이상 |
| 퀴즈 정답률 | 70% 이상 |
