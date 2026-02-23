# 이야기 성경 앱 프로토타입 상세 설계서 (v0.1)

작성일: 2026-02-19  
대상: 프로토타입 1차(구약 일부 시대)  
기술 전제: Flutter + Riverpod + Supabase

## 1) 목표와 범위

### 1.1 목표
- 시대/인물/사건을 끊김 없이 탐색할 수 있는 인터랙티브 지도형 성경 이야기 앱 프로토타입을 만든다.
- 첨부 UI 레퍼런스처럼 게임형 분위기(고지도, 핀, 진행도, 퀴즈 CTA)를 제공한다.
- 검색(키워드/문장)으로 사건에 즉시 점프할 수 있게 한다.
- 인물 복수 선택 시, 시간축 기준으로 이야기를 합쳐 보고 인물별 색상으로 비교할 수 있게 한다.

### 1.2 1차 범위(In Scope)
- 시대 선택 바
- 좌측 인물 패널(복수 선택)
- 중앙 지도(핀/경로/하이라이트/이벤트 제목 라벨)
- 우측 사건 리스트(단일/복수 인물 병합 타임라인)
- 사건 상세 팝업(요약, 성경구절, 퀴즈 시작)
- 완료 체크/XP 반영
- 검색 결과 클릭 시 시대/인물/사건 자동 선택
- Supabase 기반 데이터 조회/진행도 저장

### 1.3 1차 제외(Out of Scope)
- 정교한 소셜 기능(랭킹/친구)
- 다국어 전체 지원
- 고급 영상 편집 기능
- 대규모 운영용 관리자 CMS

## 2) 사용자 시나리오

### 시나리오 A: 단일 인물 탐색
1. 사용자가 하단 시대 탭에서 `출애굽 시대` 선택
2. 좌측 인물 리스트가 해당 시대로 필터됨
3. 사용자가 `모세` 선택
4. 우측 리스트에 모세 사건이 시간순으로 표시
5. 지도 핀이 sequence 순으로 순차 등장
6. 사건 클릭 시 해당 핀 강조 + 카메라 이동 + 상세 팝업 열기
7. 퀴즈 완료 시 체크/XP 반영

### 시나리오 B: 복수 인물 비교 탐색
1. 사용자가 같은 시대에서 `모세`, `여호수아`를 동시에 선택
2. 우측 리스트가 두 인물 사건을 하나의 시간순 타임라인으로 병합
3. 각 사건 행에 인물 색상 배지 표시
4. 같은 사건을 공유하거나 시간/장소가 겹치는 구간은 `교차 구간` 스타일로 표시
5. 지도에는 인물별 색상 핀/경로가 함께 렌더링

### 시나리오 C: 검색 점프
1. 사용자가 우상단 검색창에 `홍해를 건넌 장면` 입력
2. 검색 결과에서 사건 선택
3. 시스템이 자동으로 시대/인물 선택을 맞추고 해당 사건으로 스크롤/포커스

## 3) UX/화면 구조

### 3.1 메인 레이아웃 (웹/데스크탑 우선)
- Top Bar
- 우상단: 검색 입력 + 드롭다운
- Body 3열
- Left Panel: 인물 카드(아바타/이름/진행률/선택 토글)
- Center Panel: 지도 + 핀 + 경로 + 이벤트 라벨
- Right Panel: 사건 리스트 + 퀴즈 시작 버튼
- Bottom Bar: 시대 탭

### 3.2 반응형 기준
- Desktop(>=1280): 3열 고정
- Tablet(900~1279): 좌/우 패널 폭 축소
- Mobile(<900): 좌측 인물/우측 사건을 Drawer + BottomSheet로 분리

### 3.3 시각 테마 가이드
- 고지도/양피지 질감의 배경
- 골드/브라운 계열 액션 버튼
- 지도 핀 강조 시 광택/글로우
- 인물 색상 팔레트는 고채도 8~12개 고정 세트 + 자동 재사용 규칙

### 3.4 컴포넌트 명세
- EraTabBar
- PersonMultiSelectPanel
- StoryMapView
- EventTimelinePanel
- EventDetailSheet
- SearchBoxWithResult

## 4) 상태 모델 및 상호작용 명세

### 4.1 전역 상태(Riverpod)
- `selectedEraId: String`
- `selectedPersonIds: Set<String>`
- `selectedEventId: String?`
- `visibleEventIds: Set<String>` (순차 핀 렌더링용)
- `completedEventIds: Set<String>`
- `personColorMap: Map<String, Color>`
- `searchQuery: String`
- `searchResults: List<SearchResult>`
- `isQuizAvailable: bool`

### 4.2 주요 이벤트 핸들러
- `onEraSelected(eraId)`
- `selectedEraId` 변경
- `selectedPersonIds`를 해당 시대 기본 1인으로 초기화
- `selectedEventId` 초기화
- 인물 기본 선택 기준: 최근 학습 인물 > 시대 첫 인물

- `onPersonToggled(personId)`
- 단일/복수 공통 토글
- 비어있는 선택 금지(최소 1명 유지)
- 선택 집합 변경 시 병합 타임라인 재계산
- 핀 순차 등장 애니메이션 재실행

- `onEventSelected(eventId)`
- `selectedEventId` 변경
- 지도 카메라 이동
- 상세 시트 표시

- `onMapPinClicked(eventId)`
- `onEventSelected(eventId)`와 동일

- `onQuizCompleted(eventId)`
- `completedEventIds` 업데이트
- 사용자 XP 증가
- 우측 리스트 체크 표시 업데이트

- `onSearchResultSelected(result)`
- `selectedEraId` 세팅
- `selectedPersonIds` 세팅(해당 사건 관련 인물 포함)
- `selectedEventId` 세팅
- 해당 이벤트로 UI 포커스

## 5) 복수 인물 선택 및 교차 시각화 설계

### 5.1 핵심 요구
- 인물 선택은 최대 인원 제한 없음
- 선택된 인물들의 사건을 `시간순`으로 병합
- 인물별 색상으로 구분
- 행적이 겹치는 구간을 시각적으로 식별 가능

### 5.2 병합 타임라인 규칙
- 기준 정렬 키: `time_sort_key`(필수)
- 동률 정렬: `start_year ASC`, `event_id ASC`
- 각 리스트 아이템에 다음 메타 포함
- `relatedPersonIds`
- `primaryPersonId`
- `isSharedEvent` (하나의 사건이 여러 인물에 연결)
- `overlapGroupId?` (시간/장소 겹침 판단된 그룹)

### 5.3 겹침(overlap) 판단
- 우선순위 1: 같은 `event_id`를 여러 인물이 공유하면 무조건 겹침
- 우선순위 2: 서로 다른 사건이라도 아래 조건을 모두 만족하면 약한 겹침
- `abs(start_year diff) <= overlap_year_threshold` (기본 5년)
- 위치 좌표 거리 <= `overlap_distance_km` (기본 80km)
- 같은 era

### 5.4 우측 리스트 표현
- 사건 제목 왼쪽에 `인물 컬러 도트/태그`
- 겹침 그룹은 행 배경에 옅은 스트라이프 + `교차` 배지
- hover/select 시 관련 인물 경로도 동시에 강조

### 5.5 지도 표현
- 핀 색상
- 단일 인물 사건: 해당 인물 단색 핀
- 공유 사건: 다색 링(외곽) + 중앙 번호
- 경로
- 인물별 polyline 색상 고정
- 겹침 구간은 굵기 증가 + 점선 오버레이
- 성능
- 선택 인물이 많아지면 라벨 렌더 수 제한(예: 상위 30개만 제목 노출)

### 5.6 색상 할당 규칙
- 고정 팔레트(12색) 순환
- `personColorMap[personId]`는 세션 내 고정
- 팔레트 소진 시 HSL 기반 자동 생성
- 명도/채도 제한으로 가독성 보장

## 6) 데이터 설계 (Supabase/Postgres)

### 6.1 엔티티 관계
- Era 1:N PersonEra
- Person 1:N PersonEra
- Era 1:N Event
- Event N:M Person (`event_persons`)
- Event 1:N QuizQuestion
- User 1:N UserEventProgress

### 6.2 테이블 정의(초안)

### `eras`
- `id uuid pk`
- `code text unique` (예: `era_exodus`)
- `name text`
- `display_order int`
- `start_year int`
- `end_year int`
- `theme_color text`
- `map_center_lat double precision`
- `map_center_lng double precision`
- `map_zoom numeric(4,2)`
- `created_at timestamptz default now()`

### `persons`
- `id uuid pk`
- `code text unique`
- `name text`
- `tagline text`
- `avatar_url text`
- `description text`
- `is_active boolean default true`
- `created_at timestamptz default now()`

### `person_eras`
- `id uuid pk`
- `person_id uuid references persons(id)`
- `era_id uuid references eras(id)`
- `display_order int`
- unique(`person_id`, `era_id`)

### `events`
- `id uuid pk`
- `code text unique`
- `era_id uuid references eras(id)`
- `title text`
- `summary text`
- `short_text text`
- `start_year int`
- `end_year int`
- `time_sort_key bigint` (정렬 안정화 키)
- `time_precision text` (`year`/`range`/`approx`)
- `place_name text`
- `lat double precision`
- `lng double precision`
- `is_major boolean default false`
- `video_url text`
- `thumb_url text`
- `search_text text`
- `created_at timestamptz default now()`

### `event_persons`
- `id uuid pk`
- `event_id uuid references events(id) on delete cascade`
- `person_id uuid references persons(id)`
- `role text` (주인공/동행/언급)
- `person_sequence int` (해당 인물 관점 순번)
- unique(`event_id`, `person_id`)
- index(`person_id`, `person_sequence`)

### `event_bible_refs`
- `id uuid pk`
- `event_id uuid references events(id) on delete cascade`
- `book text`
- `chapter_start int`
- `verse_start int`
- `chapter_end int`
- `verse_end int`
- `display_text text` (예: 출 3:1-12)

### `quiz_questions`
- `id uuid pk`
- `event_id uuid references events(id) on delete cascade`
- `question text`
- `choice_a text`
- `choice_b text`
- `choice_c text`
- `choice_d text`
- `answer_index int`
- `explanation text`
- `display_order int`

### `user_event_progress`
- `id uuid pk`
- `user_id uuid`
- `event_id uuid references events(id) on delete cascade`
- `is_completed boolean default false`
- `score int default 0`
- `xp_earned int default 0`
- `completed_at timestamptz`
- unique(`user_id`, `event_id`)

### `search_embeddings` (2차 시맨틱)
- `id uuid pk`
- `entity_type text` (`event`/`person`)
- `entity_id uuid`
- `chunk_text text`
- `embedding vector(1536)`
- `updated_at timestamptz default now()`

### 6.3 인덱스 권장
- `events(era_id, time_sort_key)`
- `event_persons(person_id, person_sequence)`
- `event_persons(person_id, event_id)`
- `user_event_progress(user_id, is_completed)`
- `search_embeddings using ivfflat (embedding vector_cosine_ops)`

### 6.4 RLS 초안
- 콘텐츠(`eras/persons/events/...`)는 anon read 허용
- 진행도(`user_event_progress`)는 `auth.uid() = user_id`만 read/write

### 6.5 SQL 마이그레이션 초안 (v0)
- 파일로 분리: `db_init.sql`
- 목적: Supabase 초기 스키마/인덱스/벡터 확장 생성
- 실행: Supabase SQL Editor 또는 migration 파이프라인에서 `db_init.sql` 적용

## 7) 쿼리/로딩 전략

### 7.1 초기 로딩
- 앱 시작 시 `eras`, 선택 시대의 `persons`, `events`, `event_persons` 조회
- 첫 화면 체감속도 목표: 1.5초 이내

### 7.2 시대 변경
- 선택 시대 관련 데이터만 재조회 또는 캐시 사용

### 7.3 복수 인물 병합 조회
- 서버에서 1차 필터 후 클라이언트에서 병합 정렬
- SQL 개념
- `event_persons.person_id in selectedPersonIds`
- `events.era_id = selectedEraId`
- `events.time_sort_key asc`

### 7.4 진행도 저장
- 퀴즈 완료 시 upsert
- 낙관적 업데이트 후 실패 시 롤백

### 7.5 병합 타임라인 알고리즘 (클라이언트)
```text
입력:
- selectedEraId
- selectedPersonIds (N >= 1)
- eraEvents (해당 시대 events)
- eraEventPersons (해당 시대 event_persons)
- overlap_year_threshold (기본 5)
- overlap_distance_km (기본 80)

절차:
1) selectedPersonIds에 해당하는 event_persons만 필터한다.
2) event_id 기준으로 이벤트를 dedupe한다.
3) 각 이벤트에 relatedPersonIds를 채운다.
4) events를 (time_sort_key, start_year, id) 기준으로 정렬한다.
5) 순회하며 overlapGroupId를 부여한다.
   - 공유 사건(relatedPersonIds.size > 1)은 즉시 overlapGroupId 부여
   - 아니면 인접 이벤트와 연도/거리 조건 비교해 그룹 연결
6) 결과를 Right Timeline과 Map Marker 입력으로 전달한다.

출력:
- mergedTimelineItems[]
- markerPresentationModel[]
```

### 7.6 겹침 그룹 판정 의사코드
```text
currentGroup = 0
for i in 0..n-1:
  if item[i].isSharedEvent:
    if item[i].overlapGroupId is null:
      currentGroup += 1
      item[i].overlapGroupId = currentGroup
    continue

  for j in i+1..n-1:
    if abs(year(i)-year(j)) > overlap_year_threshold:
      break
    if sameEra(i,j) and distanceKm(i,j) <= overlap_distance_km:
      if item[i].overlapGroupId is null and item[j].overlapGroupId is null:
        currentGroup += 1
        item[i].overlapGroupId = currentGroup
        item[j].overlapGroupId = currentGroup
      else:
        item[j].overlapGroupId = item[i].overlapGroupId ?? item[j].overlapGroupId
```

## 8) 시맨틱 검색 설계

### 8.1 단계형 적용
- 1단계(필수): 키워드 검색
- 대상: `events.search_text`, `events.title`, `persons.name`, `persons.tagline`
- 방식: `ilike '%query%'`

- 2단계(선택): 임베딩 검색
- 쿼리 임베딩 생성(Edge Function 또는 API)
- `match_search_embeddings` RPC로 top-k 반환

### 8.2 결과 타입
- `event` 결과
- 즉시 시대/인물/사건 선택
- `person` 결과
- 시대/인물 선택 후 해당 인물 첫 사건 포커스

### 8.3 자동 선택 규칙
- 이벤트 결과 선택 시
- `selectedEraId = event.era_id`
- `selectedPersonIds = event.relatedPersonIds`
- `selectedEventId = event.id`

## 9) 지도 렌더링/애니메이션

### 9.1 지도 옵션
- 1안: `flutter_map` + 타일
- 2안: 고정 배경 이미지 + 좌표 매핑 (프로토타입 속도 우선 시 권장)

### 9.2 핀 순차 등장
- 입력: 병합 타임라인 이벤트 목록
- 로직: 500ms 간격으로 `visibleEventIds`에 추가
- 끊김 방지: 인물 선택 변경 시 기존 타이머 취소 후 재시작

### 9.3 카메라 제어
- 사건 선택 시 해당 좌표로 move/animate
- 다중 선택 직후에는 전체 핀 bounds fit

### 9.4 라벨 규칙
- 선택 사건: 항상 제목 라벨 표시
- 비선택 사건: 확대율/중요도 기준 제한 표시

## 10) 퀴즈/진행도 설계

### 10.1 퀴즈 구조
- 사건당 2~3문항
- 객관식 3~4지선다
- 제출 후 정답/해설 제공

### 10.2 완료 처리
- 조건: 최소 정답률(예: 60%) 또는 `완료 처리` 버튼 클릭
- 완료 시
- 리스트 체크 아이콘
- XP 증가
- 인물 진행률 자동 갱신

### 10.3 진행률 계산
- 인물 진행률 = 완료 사건 수 / 인물 전체 사건 수
- 시대 진행률 = 선택 시대 내 완료 사건 수 / 시대 전체 사건 수

## 11) Flutter 앱 아키텍처

### 11.1 폴더 구조(권장)
```text
lib/
  core/
    theme/
    constants/
    utils/
  data/
    models/
    dto/
    repositories/
    services/
    mappers/
  features/
    era/
    person/
    event/
    map/
    search/
    quiz/
    progress/
  state/
    providers/
    notifiers/
  ui/
    screens/
    widgets/
```

### 11.2 주요 서비스
- `TimelineMergeService`
- `OverlapDetectionService`
- `PersonColorService`
- `SearchService`
- `MapPresentationService`

### 11.3 테스트 우선순위
- 병합 정렬 정확성 테스트
- overlap 판단 테스트
- 색상 할당 안정성 테스트
- 검색 결과 자동 선택 테스트

## 12) 성능/운영 고려사항

- 병합 대상 이벤트가 500개 이상이면 가상 스크롤 적용
- 지도 마커는 화면 밖 최소 렌더링
- 이미지 에셋 prefetch
- 검색 디바운스 200~300ms
- 에러 처리: 네트워크 실패 시 캐시 fallback

## 13) 단계별 구현 계획

### Phase 1: 데이터/스키마/더미 시드
- Supabase 테이블 생성
- 2개 시대, 4명 인물, 24개 사건 시드
- 기본 조회 API/Repository 연결

### Phase 2: 기본 UI 골격
- 3열 + 하단 시대 바 + 검색바
- 시대/인물 선택 상태 반영

### Phase 3: 지도/핀/리스트 동기화
- 사건 선택 -> 핀 강조/센터링
- 핀 클릭 -> 리스트 선택 동기화

### Phase 4: 복수 인물/병합 타임라인
- `selectedPersonIds` 적용
- 병합 정렬 + 색상 표시 + 교차 배지
- 지도 다중 경로/다색 핀

### Phase 5: 상세/퀴즈/진행도
- 상세 팝업 + 퀴즈
- 완료 체크/XP 저장

### Phase 6: 검색
- 1차 키워드 검색
- 2차 임베딩 검색(선택)

## 14) 수용 기준(Acceptance Criteria)

- 시대 탭 전환 시 1초 내 인물/이벤트 목록이 갱신된다.
- 인물 복수 선택 시 우측 리스트가 시간순 병합으로 즉시 갱신된다.
- 각 사건 항목에 인물 색상 표시가 일관되게 적용된다.
- 공유 사건/겹침 구간이 리스트와 지도에서 모두 구분된다.
- 사건 클릭 시 지도 포커스와 상세 팝업이 동작한다.
- 퀴즈 완료 후 진행도가 즉시 반영되고 재실행 시 유지된다.
- 검색 결과 선택 시 시대/인물/사건이 자동 선택된다.

## 15) 리뷰 필요 결정사항

- 겹침 판정 기본값
- 시간 허용치 5년이 적절한가?
- 위치 허용치 80km가 적절한가?

- 복수 선택 UX
- 최소 1명 강제 선택 유지 여부
- 너무 많은 인물 선택 시 UI 제한(예: 12명 초과 경고) 필요 여부

- 검색 1차 범위
- 제목/요약/구절만 우선할지, 인물 설명까지 포함할지

- 퀴즈 완료 기준
- 정답률 기준 vs 버튼 기반 완료 중 어떤 정책을 기본으로 할지

---

이 문서는 `리뷰 후 수정 -> 구현` 전환을 전제로 작성된 1차 설계안이다.
리뷰 반영 후 v0.2에서 ERD 확정본과 SQL migration 초안을 분리한다.

---

## 16) UI 에셋 분석 및 구현 참고 노트 (v0.1 구현 중 축적)

### 16.1 게임 UI 에셋 PNG 픽셀 분석 결과

**`assets/elements/panel_left_and_right.png`** (768×1408)
- 비투명 영역: rows 99–1275 (7%–90.6%)
- 상단 스크롤 장식: rows 99–211 (7%–15%)
- 양피지 내용 영역: rows 211–1000 (15%–71%)
- 하단 스크롤 장식: rows 1000–1275 (71%–90.6%)
- 구현 패딩: `panelContentPaddingForSize` — top `(height*0.15).clamp(60,100)`, bottom `(height*0.10).clamp(36,60)`, horizontal `(width*0.075).clamp(9,16)`

**`assets/elements/btn_default.png`** (1408×768)
- 타원형 버튼 영역: rows 224–536 (29%–70%), cols 100–1311 (7%–93%)
- 위/아래 투명 여백 각 29%씩 존재
- 구현: `BoxFit.fitWidth` + `alignment: Alignment.center` → 컨테이너 중앙에 타원이 표시됨
- `centerSlice` 사용 금지 (9-slice 경계 계산이 맞지 않아 콘텐츠 범람 발생)

**`assets/elements/btn_selected.png`** (1408×768)
- btn_default.png와 동일한 레이아웃, 선택 상태 색상

**`assets/elements/tab_item_inactive.png`** (1063×399)
- 나무 재질 탭 아이템; 전체 행에 콘텐츠 존재 (투명 여백 없음)
- 구현: `BoxFit.fill` — inactive/active 크기 불일치 해결에 필수

**`assets/elements/tab_item_active.png`** (1080×422)
- inactive와 다른 소스 치수(1063×399 vs 1080×422) → `BoxFit.fill` 필수
- `BoxFit.fitWidth` 사용 시 두 이미지가 다른 높이로 렌더링됨 (버그)

**`assets/elements/tab_bar.png`** (1408×768)
- 대부분 투명; 세로 중심부에 어두운 줄만 존재
- 배경 색상 추가 금지 (검정 배경 노출 문제 발생)
- 구현: `BoxFit.fill`, 배경 없이 `tab_bar.png`만 표시

**`assets/elements/scroll_popup.png`** (1280×896)
- 상단 스크롤 장식: rows 0–107 (0%–12%)
- 양피지 내용 영역: rows 107–582 (12%–65%)
- 하단 롤러 장식: rows 582–762 (65%–85%)
- 하단 여백: rows 762–896 (85%–100%)
- 구현 패딩: top `(height*0.16).clamp(60,110)`, bottom `(height*0.38).clamp(120,280)`, horizontal `(width*0.12).clamp(44,88)`

**`assets/elements/pin_normal.png`** / **`pin_selected.png`**
- 핀 이미지의 뾰족한 끝(tip)은 이미지 하단 중앙에 위치
- flutter_map `Marker`의 기본 anchor는 위젯 중앙(`Alignment.center`) → 핀 tip이 좌표에 맞지 않음
- 비선택 마커(148px): 핀 이미지 94px + 레이블 ~20px. 핀 tip = row 94 → alignment y = (94-74)/74 ≈ 0.27
- 선택 마커(334px): 말풍선 ~171px + 핀 106px. 핀 tip = row ~277 → alignment y = (277-167)/167 ≈ 0.66
- 구현: `alignment: selected ? Alignment(0, 0.66) : Alignment(0, 0.27)`

### 16.2 핵심 구현 패턴

**BoxDecoration 배경 이미지 fitMode 결정 기준:**
- 고정 비율 유지 필요 + 잘림 허용: `BoxFit.cover`
- 반드시 전체 이미지 표시 + 컨테이너 채움: `BoxFit.fill`
- 가로 고정, 세로 중앙 클리핑: `BoxFit.fitWidth` + `alignment: Alignment.center`
- `centerSlice` (9-slice)는 이미지 픽셀 경계를 정확히 알아야 하며, 오차 발생 시 콘텐츠 범람 → 가급적 사용 금지

**flutter_map Marker 앵커 설정:**
- `alignment: Alignment(x, y)` — 위젯 내 어느 지점이 지리 좌표와 일치하는지 지정
- y = (원하는_위치_px - 위젯높이/2) / (위젯높이/2)
- 핀 tip을 좌표에 맞추려면 tip의 위젯 내 위치를 픽셀로 계산한 후 위 공식 적용

**camera focus (이벤트 선택 시 팝업 가시성):**
- 사건 선택 시 카메라를 이벤트 좌표 남쪽으로 오프셋 이동 → 핀이 뷰포트 하단에 표시되어 위쪽 말풍선이 보임
- 위도 오프셋 계산: `220 * (360 / (256 * 2^zoom) / cos(lat))`
- `_focusToSelectedEvent()` 메서드로 구현

**인물 선택 변경 vs 이벤트 선택:**
- 인물/시대 변경 → `_startRevealAnimation()` 호출 → 카메라 전체 범위 fit + 핀 순차 등장
- 개별 이벤트 선택 → `_focusToSelectedEvent()` → 해당 이벤트로 소프트 이동

### 16.3 레이아웃 상수 (현재 적용값)

| 상수 | 값 | 위치 |
|------|----|------|
| `eraHeight` | 64.0 | `story_home_screen.dart` |
| `outerMargin` | 20.0 | `story_home_screen.dart` |
| `selectorGap` | 4.0 | `story_home_screen.dart` |
| `leftPanelWidth` | `(usableWidth*0.235).clamp(176,252)` | `story_home_screen.dart` |
| `rightPanelWidth` | `(usableWidth*0.225).clamp(176,252)` | `story_home_screen.dart` |
| 패널 상단 패딩 | `(height*0.15).clamp(60,100)` | `game_ui_skin.dart` |
| 패널 하단 패딩 | `(height*0.10).clamp(36,60)` | `game_ui_skin.dart` |
| 팝업 상단 패딩 | `(height*0.16).clamp(60,110)` | `story_home_screen.dart` |
| 팝업 하단 패딩 | `(height*0.38).clamp(120,280)` | `story_home_screen.dart` |
| era 버튼 높이 | 42 | `era_selector.dart` |
| 인물 아이템 외부 margin | `horizontal:4, vertical:3.5` | `person_panel.dart` |
| 사건 아이템 외부 margin | `horizontal:4, vertical:4` | `story_list_panel.dart` |

### 16.4 알려진 주의사항

1. **tab_item_inactive/active 크기 불일치**: 두 에셋의 소스 해상도가 다름. `BoxFit.fill` 사용 시 동일한 컨테이너 크기로 렌더링됨.
2. **scroll_close.png 버튼 크기**: 92×92px (2배). 위치 `top:8, right:8`. 팝업 상단 스크롤 장식(12% 높이)과 겹칠 수 있으나, 상단 스크롤 영역에 위치해 자연스럽게 표시됨.
3. **Mercator 보정**: 위도별 픽셀/도 변환 시 `cos(lat)` 보정 필요. 중동 지역(30–35°N) 기준 cos ≈ 0.87.
4. **핀 앵커 오차**: 말풍선 높이가 콘텐츠에 따라 가변적 → 선택 마커의 `alignment y=0.66`은 근삿값. 말풍선 내용이 없을 경우 오차 발생 가능.
