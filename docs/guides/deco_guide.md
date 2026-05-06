# 지도 데코(Map Decoration) 가이드

> 양피지 지도 위에 깔리는 분위기용 일러스트(산·도시·피라미드·나무 등)를 Vertex
> AI Imagen 으로 생성하고 시대별로 노출하는 파이프라인 전체 설명.

## 0. 한 줄 요약

| 무엇 | 어디 | 누가 만드나 |
|------|------|------------|
| 데코 카탈로그 | `assets/decos/decos_catalog.json` | 사람이 직접 편집 |
| 데코 PNG (kind 당 1장) | `assets/decos/{kind}.png` | `tools/images/generate_decos_vertex.py` 가 Vertex AI Imagen 으로 생성 → Pillow 로 흰 배경 chroma-key → 투명 PNG 저장 |
| 지도 위 표시 | `lib/widgets/map_deco_layer.dart` (`MapDecoLayer`) | flutter_map `MarkerLayer` |
| 시대별 노출 제어 | `placements[].era_codes` | 카탈로그에서 코드별 필터링 |

핵심: **kind 1개 = PNG 1장**. 같은 kind 를 카탈로그 `placements` 에서 여러 좌표에 재사용한다 (예: `mountain_range` 1장 → 갈멜·헤르몬·시내·아라랏 4곳에 배치).

> ⚠️ **중요 — Imagen 은 진짜 투명 PNG 를 못 만든다**: prompt 에 "transparent
> background" 를 넣어도 Imagen 4.0 은 흰 면이나 양피지/스크롤 프레임이 그려진
> PNG 를 돌려준다. 그래서 이 파이프라인은 두 단계로 동작한다 — (1) prompt 가
> "isolated subject on pure white background" 를 유도, (2) Pillow 의 모서리
> flood-fill 로 그 흰 배경만 투명화. 결과가 완전히 끝까지 깔린 양피지/프레임이
> 들어와도 다시 prompt 만 살짝 손보고 `--overwrite` 또는 `--rekey-only` 로 처리.

---

## 1. 시스템 구조

### 1.1 데이터 흐름

```
┌──────────────────────────────────────┐
│  assets/decos/decos_catalog.json     │  ← 사람이 편집 (kind 추가/배치 변경)
│  • kinds[]    : kind + prompt        │
│  • placements[]: lat/lng/era_codes   │
│  • common_style ({SUBJECT} 치환)     │
│  • negative_prompt (양피지/프레임 차단) │
└────────────────┬─────────────────────┘
                 │
        ┌────────▼─────────────────────────────┐
        │ tools/images/generate_decos_vertex.py│  ← `kinds[]` 만 읽음
        │  ① common_style.{SUBJECT} 치환       │
        │  ② Vertex AI Imagen 호출             │
        │  ③ Pillow flood-fill 로 흰 배경 투명 │
        │  → assets/decos/{kind}.png (RGBA)    │
        └────────────────┬─────────────────────┘
                         │
                  ┌──────▼─────────────────┐
                  │  assets/decos/*.png    │  ← 앱 번들에 포함, 투명 PNG
                  └──────┬─────────────────┘
                         │
                  ┌──────▼──────────────────────────┐
                  │ lib/widgets/map_deco_layer.dart │
                  │  카탈로그 다시 로드             │
                  │  `placements[]` 만 사용         │
                  │  activeEraCodes 로 필터링       │
                  │  MarkerLayer 로 그리기          │
                  └─────────────────────────────────┘
```

### 1.2 책임 분리

- **kinds[]** = "어떤 일러스트가 있나" (이미지 종류 + 프롬프트). PNG 생성 단계에서만 읽힘.
- **placements[]** = "어디에, 어느 시대에 노출되나" (좌표 + era 필터). 앱 런타임에서 읽힘.
- 따라서 새 데코 추가는 두 단계: **(a) kind 등록 + 이미지 생성 → (b) 좌표 등록**.
- 같은 kind 를 여러 placements 에 재사용 가능. PNG 는 한 번만 생성.

---

## 2. 사전 준비

이미지 생성기는 `generate_avatars_vertex.py` 와 동일한 인증 방식을 쓴다.

### 2.1 환경 변수 (`.env` 또는 셸)

```bash
export GOOGLE_CLOUD_PROJECT="your-gcp-project-id"
export GOOGLE_CLOUD_LOCATION="us-central1"   # 옵션, 기본값 us-central1
```

### 2.2 GCP 인증

```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project "$GOOGLE_CLOUD_PROJECT"
```

(이미 아바타 생성기를 돌렸다면 이 단계는 끝나 있음)

### 2.3 Python 의존성

`tools/images/generate_avatars_vertex.py` 와 같은 패키지를 쓴다:
- `google-auth`
- `requests`

`.venv` 가 활성화돼 있으면 추가 설치 불필요.

```bash
source .venv/bin/activate
```

### 2.4 Vertex AI Imagen 권한

GCP 프로젝트에서 **Vertex AI API** 가 활성화돼 있어야 한다. 아바타 생성기를 한 번이라도 성공시켰으면 자동 충족.

```bash
gcloud services enable aiplatform.googleapis.com
```

---

## 3. 카탈로그 편집

`assets/decos/decos_catalog.json` 구조:

```json
{
  "_doc": { ... },           // 사람 읽기 용 (코드 영향 없음)
  "kinds": [                  // PNG 1장 = 항목 1개
    {
      "kind": "mountain_range",
      "label": "산맥",
      "prompt": "a mountain range with three to four peaks, sepia ink line drawing with light brown watercolor wash"
    }
  ],
  // common_style 이 {SUBJECT} 자리표시자를 갖고, 생성기가 kind 의 prompt 로
  // 치환한다. Imagen 이 양피지/스크롤 프레임을 그리지 않도록 "isolated on
  // pure plain white background" 가 핵심 신호.
  "common_style": "isolated illustration of {SUBJECT} on a pure plain white background, hand-drawn ink and watercolor sketch in vintage cartography style, ...",
  // negative_prompt 가 양피지·스크롤·프레임·테두리 어휘를 명시 차단.
  "negative_prompt": "parchment, scroll, paper texture, weathered paper, frame, border, torn edges, ...",
  "placements": [             // 좌표마다 1개
    {
      "kind": "mountain_range",
      "lat": 32.74,
      "lng": 35.05,
      "era_codes": ["era_judges", "era_monarchy"],  // 비면 모든 시대
      "scale": 1.0,
      "rotation_deg": 0,
      "comment": "갈멜 산"
    }
  ]
}
```

### 3.1 새 kind 추가

1. `kinds[]` 에 항목 추가 (`kind`, `label`, `prompt`).
2. **`prompt` 에는 subject 만 적는다** — 양피지/스크롤/프레임/배경 어휘는 절대
   넣지 말 것. `common_style` 이 `{SUBJECT}` 자리에 prompt 를 끼워 넣고
   "isolated ... on pure plain white background" 로 감싼다.
3. 좋은 prompt 예시 (subject 만):
   - ✅ `"a single oak tree with broad canopy, sepia ink line drawing with light olive watercolor wash"`
   - ❌ `"ancient parchment map illustration of a single oak tree on weathered tan paper"` ← 양피지 그려짐
4. `placements[]` 에 좌표를 함께 추가하지 않으면 PNG 만 만들어지고 지도엔 안 보인다.

### 3.1.1 prompt 작성 체크리스트

- [ ] subject 1줄로 단순 묘사 (예: "a single olive tree with silvery foliage")
- [ ] 화풍 키워드는 추가 OK (sepia ink line drawing / light watercolor wash)
- [ ] 양피지·스크롤·테두리·종이 텍스처 단어 **금지**
- [ ] "transparent background" 도 **불필요** — 후처리가 처리함
- [ ] `top-down isometric view`/`profile` 등 시점 키워드는 OK

### 3.2 새 placement 추가

PNG 가 이미 있는 kind 라면 placements 만 추가하면 즉시 반영 (앱 hot restart):

```json
{
  "kind": "city_walled",
  "lat": 31.78,
  "lng": 35.22,
  "era_codes": ["era_monarchy"],
  "scale": 0.95,
  "comment": "예루살렘"
}
```

### 3.3 era_codes 값

`assets/landmarks/landmarks.json` 의 era 코드와 일치해야 한다. 현재 사용 중:

- `era_primeval` (창세 원시사)
- `era_patriarch` (족장 시대)
- `era_exodus` (출애굽)
- `era_judges` (사사 시대)
- `era_monarchy` (왕정 시대)
- `era_exile_return` (포로기·귀환)
- `era_intertestamental` (중간기)
- `era_nt_birth` (NT 탄생)
- `era_nt_public_ministry` (NT 공생애)
- `era_nt_passion_resurrection` (수난·부활)
- `era_nt_apostolic` (사도 시대)
- `era_nt_consummation` (종말)

배열이 비어 있으면 모든 시대에 노출.

### 3.4 scale / rotation_deg

- `scale`: 기본 1.0, 권장 0.7 ~ 1.3.
- `rotation_deg`: 산처럼 회전하면 어색한 데코는 0 유지. ship/swords 등은 약간 기울여도 OK.

---

## 4. PNG 생성 실행

### 4.1 dry-run (프롬프트 확인)

```bash
python tools/images/generate_decos_vertex.py --dry-run
```

각 kind 에 보낼 prompt 를 출력한다. API 호출 없음.

### 4.2 전체 생성

```bash
python tools/images/generate_decos_vertex.py
```

- 카탈로그의 모든 `kinds[]` 항목에 대해 PNG 1장씩 생성 → `assets/decos/{kind}.png`.
- **이미 존재하는 PNG 는 자동 SKIP**. 새 kind 만 비용 발생.

### 4.3 일부만 / 덮어쓰기

```bash
# mountain, pyramid 만 (재)생성
python tools/images/generate_decos_vertex.py --only mountain pyramid

# 모든 PNG 강제 재생성 (마음에 안 드는 결과 다시 뽑기)
python tools/images/generate_decos_vertex.py --overwrite

# 특정 kind 만 강제 재생성
python tools/images/generate_decos_vertex.py --only mountain --overwrite
```

### 4.4 옵션 전체

| 플래그 | 기본값 | 설명 |
|--------|--------|------|
| `--catalog` | `assets/decos/decos_catalog.json` | 카탈로그 경로 |
| `--output-dir` | `assets/decos` | PNG 저장 디렉토리 |
| `--project` | `$GOOGLE_CLOUD_PROJECT` | GCP project id |
| `--location` | `$GOOGLE_CLOUD_LOCATION` 또는 `us-central1` | Vertex 리전 |
| `--model` | `imagen-4.0-generate-001` | Imagen 모델 |
| `--aspect-ratio` | `1:1` | 종횡비 |
| `--only` | (전체) | 일부 kind 만 |
| `--overwrite` | false | 기존 PNG 덮어쓰기 |
| `--dry-run` | false | API 호출 없이 prompt 만 출력 |
| `--sleep-sec` | 0.4 | rate limit 회피용 sleep |
| `--no-chroma-key` | false | 흰 배경 → 투명 후처리 끄기 (디버깅용) |
| `--chroma-tolerance` | 42 | 모서리 flood-fill 색상 거리 임계 (0–255). 낮을수록 엄격 |
| `--chroma-soft-edge` | 2 | alpha feather 픽셀. 0 이면 오프, 높을수록 가장자리 부드러움 |
| `--rekey-only` | false | Imagen 호출 안 하고 기존 PNG 만 다시 chroma-key (튜닝용, 비용 0) |

### 4.5 후처리 튜닝 (rekey-only)

생성된 PNG 가 조금 흰 가장자리가 남거나 너무 깎였다면 — Imagen 다시 안 부르고
파라미터만 바꿔 재처리:

```bash
# 더 공격적으로 흰 영역 잡아내기
python tools/images/generate_decos_vertex.py --rekey-only --chroma-tolerance 60

# 가장자리 더 부드럽게
python tools/images/generate_decos_vertex.py --rekey-only --chroma-soft-edge 4

# 특정 kind 만
python tools/images/generate_decos_vertex.py --rekey-only --only mountain pyramid \
    --chroma-tolerance 50 --chroma-soft-edge 3
```

`--rekey-only` 는 Imagen API 를 호출하지 않으므로 **무료**. tolerance / soft_edge
조합을 빠르게 시도해보고 마음에 드는 값을 찾으면 본 생성에 그 값을 쓴다.

#### tolerance 가이드

- `30 미만` — 매우 엄격. 흰색만 거의 그대로 매칭. 미묘한 회색 그림자가 남음
- `40~50` (기본) — 흰색 + 약한 회색 음영까지 투명화. 대부분 OK
- `60~80` — 베이지/연한 노란 배경도 잡음. subject 가 너무 깎이지 않는지 확인
- `90+` — 너무 공격적. subject 의 옅은 색까지 투명해짐. 권장 X

### 4.5 비용 감각

- 1장 ≈ Imagen 4.0 단가 (현재 $0.04/이미지 수준, 변동 가능).
- 카탈로그 17 kinds 전체 첫 생성 ≈ $0.7 미만.
- 한 번 만든 PNG 는 재사용되므로 placements 늘려도 추가 비용 없음.

---

## 5. 결과 확인

### 5.1 PNG 품질 검수

생성 직후 `assets/decos/` 폴더의 각 PNG 를 열어보고:

| 체크 | 합격 기준 |
|------|----------|
| 배경 | 가능한 한 투명 또는 양피지 톤. 흰 박스/회색 배경이면 재생성 |
| 색감 | sepia/ochre. 채도 높은 컬러면 재생성 |
| 모양 | 한눈에 알아볼 수 있는 단순 실루엣 (작은 마커로 보일 거라 디테일 과하면 안 좋음) |
| 텍스트 | 라벨/글씨 없음 (있으면 재생성) |
| 그림자 | 강한 drop shadow 없음 |

기준 미달이면 prompt 미세 조정 후 `--only <kind> --overwrite` 로 재생성.

### 5.2 앱에서 확인

```bash
flutter pub get   # assets 변경 후 첫 실행 시 1회
flutter run
```

- 시대 선택 → 그 시대의 `era_codes` 에 매칭되는 placements 만 지도 위에 떠야 한다.
- 줌 인/아웃 시 데코 마커가 비례 축소된다 (`MapDecoLayer` 가 `MapCamera.zoom` 기준으로 0.45 ~ 1.1 사이로 clamp).
- PNG 가 없는 kind 는 **자연스럽게 안 보인다** (`Image.asset.errorBuilder` 가 `SizedBox.shrink()` 반환). 즉, kinds 에 등록만 하고 PNG 안 만들어도 앱이 깨지지 않음.

### 5.3 Hot reload 가 안 먹을 때

- `pubspec.yaml` 의 `assets:` 목록은 캐시되므로 신규 파일을 추가하면 **full restart** 가 필요하다.
- 카탈로그(JSON) 내용 변경은 hot restart 1회로 반영.

---

## 6. MapDecoLayer 가 그리는 방식

`lib/widgets/map_deco_layer.dart`:

```dart
MapDecoLayer(activeEraCodes: { 'era_monarchy', 'era_nt_public_ministry' });
```

- 카탈로그 로드 → `placements` 중 `era_codes` 가 비어있거나 `activeEraCodes` 와 1개 이상 겹치는 항목만 필터.
- 각 placement → `Marker` 1개. width/height = 96 × scale (zoom-up 시 잘림 방지).
- `IgnorePointer` 로 감싸 클릭 이벤트가 region/event 핀을 가리지 않게 함.
- 이미지가 없으면 `errorBuilder` → `SizedBox.shrink()` (조용히 사라짐).

### 6.1 자연스러운 통합 — 3 stage 합성

각 데코 마커는 다음 3 단계 효과로 양피지에 "그려진" 느낌을 낸다:

1. **Drop shadow** (Stack 아래 layer): `BlendMode.srcIn` 으로 alpha 형상만 갈색
   `0x664A2E10` 으로 채운 silhouette 을 `ui.ImageFilter.blur(σ=2.5)` 로 흐리게 +
   `Transform.translate(1.5, 2.5)` 로 살짝 우하단 이동 → 부드러운 갈색 그림자.
2. **Parchment modulate** (Stack 위 layer): `BlendMode.modulate` 로 데코 RGB 를
   `0xFFE8D2A8` (parchment cream) 과 곱해 채도/색감을 지도 톤에 동기화. Imagen 이
   준 강한 녹색·회색 등이 따뜻한 sepia 로 변환됨.
3. **Zoom-responsive scaling**: `scale = 1.5^(zoom - 6.5)` (clamp 0.45~3.0) →
   사용자가 zoom-in 했을 때 데코가 지도와 함께 자라 fixed-pixel sticker 느낌
   사라짐. 기준점 zoom 6.5 에서 1.0배.

### 6.2 양피지 grain (전역 overlay)

`lib/screens/story_home_screen.dart` 의 `ParchmentTextureLayer` 가 화면 전체에
`assets/elements/parchment_texture.png` 를 멀티플라이로 합성 (opacity 0.22, tint
`0xFFB89570`). 데코·지도·핀 모두 위에 깔리므로 통일된 paper 입자감을 부여.

`story_map_panel.dart` 통합 위치:

```dart
// 폴리곤 위 / 마커 아래
PolygonLayer(...),
MapDecoLayer(activeEraCodes: { ... }),  // ← 여기
MarkerLayer(markers: _countryLabelMarkers),
... 사건 마커들 ...
```

---

## 7. 자주 묻는 질문

### Q1. 같은 kind 인데 시대마다 다른 그림을 보여주고 싶다

→ kind 를 분리한다 (예: `temple_solomon`, `temple_second`). PNG 도 각각 1장씩 생성.

### Q2. PNG 가 너무 화려해서 지도를 가린다

→ `MapDecoLayer` 의 `Opacity(0.85)` 를 더 낮추거나, `scale` 을 placements 마다 줄인다.

### Q3. 모든 시대에 나오는 공통 데코를 만들고 싶다

→ placement 의 `era_codes` 를 **빈 배열** `[]` 로 두면 모든 시대에 노출.

### Q4. 일부 placement 는 잠시 숨기고 싶다 (소스에는 남기고)

→ `era_codes` 에 존재하지 않는 더미 코드(`"_disabled"`)를 넣어두면 활성 시대와 매칭되지 않아 안 보인다.

### Q5. `assets/parchment.png` 도 따로 있는데?

→ 그건 타일 위에 깔리는 **양피지 텍스처 배경** (Level A). 이 가이드의 deco PNG 와는 별개.
- `parchment.png` = 전체 지도 배경 텍스처 (large)
- `decos/*.png` = 점점이 흩뿌려지는 작은 일러스트 (per kind)

---

## 8. 트러블슈팅

### 8.1 `ERROR: GOOGLE_CLOUD_PROJECT not set`

`.env` 가 셸에 로드 안 됐다. `source .env` 또는 직접 export.

### 8.2 `Imagen API 403: PERMISSION_DENIED`

ADC 토큰의 quota project 가 다르다. `gcloud auth application-default set-quota-project "$GOOGLE_CLOUD_PROJECT"` 재실행.

### 8.3 `Imagen API 400: prompt rejected`

프롬프트가 안전 정책에 걸렸다. negative_prompt 단어를 prompt 에 다시 넣지 말 것 (역효과). 사람/유혈/현대 무기는 피하기.

### 8.3.1 `Imagen API 429: RESOURCE_EXHAUSTED` (quota 초과)

Vertex Imagen 4.0 의 기본 per-minute quota 가 매우 낮다 (보통 5 req/min). 스크립트는 이를 자동으로 처리한다:

**①  Quota 자동 탐지 (Service Usage API)** — 스크립트 시작 시 현재 프로젝트의 RPM quota 를 Google Cloud Service Usage API 로 조회한다 (metric: `aiplatform.googleapis.com/online_prediction_requests_per_base_model`). 발견된 RPM 으로 요청 간격을 `60/RPM + 1s` 로 자동 설정. 출력 예:

```
[quota] auto-discovered 5 req/min for imagen-4.0-generate @ us-central1 → spacing 13.0s between requests
```

조회 실패 시 (권한 부족·네트워크 등) `--sleep-sec` 의 fallback 값(13초) 사용.

**②  자동 재시도 (지수 backoff)** — 그래도 429 를 받으면 20s → 40s → 80s 로 최대 5회 자동 재시도. quota 가 일시 초과돼도 그냥 두면 끝까지 완료.

**③  수동 override** — 명시적으로 간격 지정 가능:
```bash
# 더 안전하게
python tools/images/generate_decos_vertex.py --sleep-sec 20

# quota 증가 신청해서 RPM 이 늘었으면 (예: 30 RPM)
python tools/images/generate_decos_vertex.py --sleep-sec 3

# 재시도 횟수도 늘리기 (동시에 여러 프로세스 share 시)
python tools/images/generate_decos_vertex.py --max-retries 8 --initial-backoff-sec 30
```

**④  장기적**: GCP 콘솔 → IAM → 할당량 페이지에서 `Online prediction requests per base model per minute per region per base_model` 검색 → `imagen-4.0-generate` 행 quota 증가 요청. 승인 시 자동 탐지가 새 RPM 을 읽어 자동으로 간격 단축.

**⑤  Service Usage API 권한 부족 시**: 스크립트는 `cloud-platform` OAuth scope 로 토큰을 받아 quota 조회를 시도한다. 권한이 없으면 fallback 13s 가 사용되며 동작에는 문제 없음. 정확한 quota 를 알고 싶다면 IAM 에서 `serviceusage.services.list` 권한 (대부분의 Editor/Owner 가 보유) 확인.

### 8.4 PNG 가 흰 배경/투명 안 됨

기본 파이프라인이 자동으로 chroma-key 후처리를 한다. 그래도 흰 가장자리가 남거나 너무 깎였다면 §4.5 의 `--rekey-only` 로 tolerance/soft_edge 만 튜닝해 재처리.

### 8.5 PNG 결과가 사진 / 꽃 / 엉뚱한 그림으로 나옴

Imagen 4.0 은 짧은 prompt 에서 가끔 stock-photo 스타일로 빠지거나(특히 식물·자연 카테고리), 학습 데이터의 hashtag/캡션 텍스트를 이미지 위에 그려 넣기도 한다. 대처:

1. **prompt 에 "icon" / "map symbol" / "pictogram" 명시** — `"a tiny oak tree icon as drawn on an old fantasy map"` 처럼 cartography 맥락을 강하게 anchor.
2. **subject 묘사 길이 늘리기** — "a single oak tree" 보다 "a single oak tree with thick trunk and round leafy crown, side-on view" 가 안정적.
3. **negative_prompt 에 photo / hashtag / flower 추가** — 이번 카탈로그의 negative_prompt 가 `"photograph, photo, stock photo, hashtag, rose, flower"` 등을 포함.
4. **`--overwrite` 로 재시도** — Imagen 은 매번 다른 seed 를 쓰므로 같은 prompt 라도 재실행 시 결과가 다름.

### 8.6 앱에서 PNG 가 안 보임

체크 순서:
1. `assets/decos/{kind}.png` 파일 실제로 있나?
2. `pubspec.yaml` 의 `flutter.assets` 에 `assets/decos/` 가 있나?
3. `placements[].era_codes` 가 현재 선택된 시대와 매칭되나?
4. `flutter run` 을 hot restart (`R`) 가 아닌 **full restart** (`r` 두 번 또는 재시작) 했나?

---

## 9. 관련 파일

| 파일 | 역할 |
|------|------|
| `assets/decos/decos_catalog.json` | kinds + placements + 스타일 |
| `assets/decos/{kind}.png` | 생성된 일러스트 (gitignore 권장 — 용량 크면) |
| `tools/images/generate_decos_vertex.py` | Vertex AI 호출 + PNG 저장 |
| `tools/images/generate_avatars_vertex.py` | (참고) 동일한 인증 패턴의 모델 |
| `lib/widgets/map_deco_layer.dart` | flutter_map 위에 그리는 `MapDecoLayer` |
| `lib/widgets/story_map_panel.dart` | `MapDecoLayer` 를 폴리곤과 마커 사이에 끼움 |
| `pubspec.yaml` | `assets/decos/` 등록 |

---

## 10. 향후 개선 아이디어

- **시대별 분위기 차이**: 각 시대 대표 색조를 prompt 에 섞어 보여줘도 좋다 (`era_exodus` 는 모래색 강조 등).
- **lat/lng → region 자동 매칭**: 현재는 좌표를 직접 적지만, region 폴리곤 안에 자동 분포시키는 헬퍼를 만들 수도 있다.
- **z(줌) 별 가시성**: 줌 4 미만일 때만 큰 지형(산맥), 줌 7 이상일 때만 작은 데코(올리브) 식으로 가시 범위를 분리.
- **간단한 애니메이션**: 깃발/배 같은 일부 데코에 hover/idle bob 추가.

---

## 11. 변경 이력

| 날짜 | 변경 |
|------|------|
| 2026-05-06 | 최초 작성 — 17 kinds + 약 30 placements + Vertex 생성기 + MapDecoLayer 도입 |
| 2026-05-06 | prompt 재작성 (양피지/스크롤 프레임 제거, `{SUBJECT}` 치환자) + Pillow chroma-key 후처리 + `--rekey-only` 튜닝 모드 |
