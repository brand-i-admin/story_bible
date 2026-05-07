#!/usr/bin/env python3
"""Generate a single illustrated parchment basemap with Vertex AI Imagen.

flutter_map 의 OverlayImageLayer 자산으로 쓸 양피지 톤 손그림 일러스트 베이스맵을
Vertex AI Imagen 으로 한 장 생성한다. 지리 범위: 위도 28~37°N, 경도 30~46°E
(이집트·시나이·레반트·메소포타미아·북아라비아). 생성 모델 기본값 imagen-4.0-generate-001.

인증·재시도 패턴은 generate_decos_vertex.py 와 동일:
  - google.auth.default() + Request() 토큰 갱신
  - 429 / 5xx 는 지수 backoff 로 1회 재시도

Usage:
    export GOOGLE_CLOUD_PROJECT="your-project-id"
    export GOOGLE_CLOUD_LOCATION="us-central1"          # 선택 (기본 us-central1)
    export IMAGEN_MODEL="imagen-4.0-generate-001"       # 선택 (모델 override)

    python tools/images/generate_illustrated_basemap.py
    python tools/images/generate_illustrated_basemap.py --output PATH
    python tools/images/generate_illustrated_basemap.py --aspect-ratio 16:9
    python tools/images/generate_illustrated_basemap.py --seed 42
    python tools/images/generate_illustrated_basemap.py --dry-run
    python tools/images/generate_illustrated_basemap.py --overwrite
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

# google-auth 와 requests 는 API 호출 시에만 필요.
# --dry-run 은 이 라이브러리 없이도 동작하도록 lazy import 사용.

# ---------------------------------------------------------------------------
# 상수
# ---------------------------------------------------------------------------

CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"

# 단일 호출이라 RPM 체크는 생략. 429 시 한 번 재시도할 때 사용.
_RETRY_SLEEP_SEC = 13.0

# 베이스맵 지리 범위 (lat/lng)
_BOUNDS = {
    "north": 37.0,
    "south": 28.0,
    "east": 46.0,
    "west": 30.0,
}

# Vertex AI Imagen 에 전달할 메인 prompt
_BASEMAP_PROMPT = (
    "A vintage hand-drawn watercolor map of the biblical world, parchment background"
    " tone (warm beige #EEE0C6), soft brown ink outlines, gentle color washes."
    " Painted in old fantasy treasure map style. The visible landmass spans Egypt in"
    " the southwest, the Sinai peninsula, the Levant (Israel, Lebanon, Syria),"
    " Mesopotamia (Tigris and Euphrates rivers) in the east, and northern Arabia."
    "\n\n"
    "Show natural terrain only:\n"
    "- Mountain ranges with rolling soft peaks (no sharp triangular icons),"
    " watercolor-shaded in muted brown and grey-green\n"
    "- Rivers as winding pale-blue lines (the Nile, Jordan, Euphrates, Tigris)\n"
    "- Lakes (Galilee, Dead Sea) as soft blue patches\n"
    "- Mediterranean Sea as a soft pale blue-green wash\n"
    "- Sandy desert areas in pale tan, with subtle dune textures\n"
    "- Olive groves and small wooded patches as soft green washes (no individual"
    " tree symbols)\n"
    "\n"
    "Do NOT include:\n"
    "- Any cities, towers, walls, temples, pyramids, buildings of any kind\n"
    "- Roads, paths, or borders\n"
    "- Text labels or place names\n"
    "- Compass roses or grid lines\n"
    "- Coastline labels\n"
    "\n"
    "Style:\n"
    "- Aged parchment texture, slightly weathered edges\n"
    "- Soft watercolor bleed\n"
    "- Painterly, hand-drawn, not photographic\n"
    "- Muted, harmonious palette (parchment beige, soft brown, sage green, dusty blue)\n"
    "- High resolution"
)

# "Do NOT include" 항목들을 negative prompt 로도 전달
_NEGATIVE_PROMPT = (
    "cities, buildings, towers, walls, temples, pyramids, roads, paths, borders,"
    " text labels, place names, compass rose, grid lines, coastline labels,"
    " photographic, realistic photo, 3D render"
)

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate a single illustrated parchment basemap with Vertex AI Imagen."
        )
    )
    parser.add_argument(
        "--output",
        default="assets/maps/parchment_basemap.png",
        help="Output PNG path (default: assets/maps/parchment_basemap.png).",
    )
    parser.add_argument(
        "--project",
        default=os.getenv("GOOGLE_CLOUD_PROJECT", ""),
        help="GCP project id (or env GOOGLE_CLOUD_PROJECT).",
    )
    parser.add_argument(
        "--location",
        default=os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1"),
        help="Vertex AI region (or env GOOGLE_CLOUD_LOCATION).",
    )
    parser.add_argument(
        "--model",
        default=os.getenv("IMAGEN_MODEL", "imagen-4.0-generate-001"),
        help=(
            "Imagen model id (or env IMAGEN_MODEL)."
            " Default: imagen-4.0-generate-001."
        ),
    )
    parser.add_argument(
        "--aspect-ratio",
        default="16:9",
        help="Image aspect ratio (default: 16:9).",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        help="Random seed for reproducible output. Omit for a new result each run.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing output file. Default refuses if file already exists.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help=(
            "Print prompt and output path without calling the API."
            " Also prints bounds JSON."
        ),
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# 인증
# ---------------------------------------------------------------------------


def get_access_token() -> str:
    """Application Default Credentials 로 Bearer 토큰을 취득."""
    import google.auth  # noqa: PLC0415
    from google.auth.transport.requests import Request  # noqa: PLC0415

    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


# ---------------------------------------------------------------------------
# Imagen API 호출
# ---------------------------------------------------------------------------


def _maybe_decode_base64(raw: str) -> bytes | None:
    """data URI 또는 순수 base64 문자열 → bytes. 실패 시 None."""
    value = raw.strip()
    if not value:
        return None
    if value.startswith("data:"):
        parts = value.split(",", 1)
        if len(parts) != 2:
            return None
        value = parts[1]
    value = "".join(value.split())
    if len(value) < 16:
        return None
    try:
        return base64.b64decode(value, validate=True)
    except Exception:  # noqa: BLE001
        return None


def _extract_image_bytes(node: object) -> bytes | None:
    """Vertex AI 응답 JSON 에서 재귀적으로 base64 이미지를 추출."""
    if isinstance(node, str):
        return _maybe_decode_base64(node)
    if isinstance(node, list):
        for item in node:
            decoded = _extract_image_bytes(item)
            if decoded is not None:
                return decoded
        return None
    if not isinstance(node, dict):
        return None
    for key in (
        "bytesBase64Encoded",
        "b64Json",
        "image",
        "imageBytes",
        "images",
        "generatedImages",
        "inlineData",
        "data",
    ):
        if key not in node:
            continue
        decoded = _extract_image_bytes(node[key])
        if decoded is not None:
            return decoded
    for value in node.values():
        decoded = _extract_image_bytes(value)
        if decoded is not None:
            return decoded
    return None


def call_imagen(
    *,
    project: str,
    location: str,
    model: str,
    prompt: str,
    negative_prompt: str,
    aspect_ratio: str,
    seed: int | None,
    token: str,
) -> bytes:
    """Vertex Imagen API 를 호출하고 PNG bytes 를 반환.

    429 / 5xx 는 _RETRY_SLEEP_SEC 후 1회 재시도. 그 외 4xx 는 즉시 RuntimeError.
    """
    url = (
        f"https://{location}-aiplatform.googleapis.com/v1/projects/{project}"
        f"/locations/{location}/publishers/google/models/{model}:predict"
    )
    parameters: dict[str, object] = {
        "sampleCount": 1,
        "aspectRatio": aspect_ratio,
        "addWatermark": False,
        "negativePrompt": negative_prompt,
        "personGeneration": "dont_allow",
    }
    if seed is not None:
        parameters["seed"] = seed

    body = {
        "instances": [{"prompt": prompt}],
        "parameters": parameters,
    }

    import requests  # noqa: PLC0415

    for attempt in range(2):  # 최초 시도 + 1회 재시도
        resp = requests.post(
            url,
            headers={
                "Authorization": f"Bearer {token}",
                "Content-Type": "application/json",
            },
            data=json.dumps(body),
            timeout=120,
        )
        if resp.status_code == 200:
            payload = resp.json()
            img_bytes = _extract_image_bytes(payload)
            if img_bytes is None:
                raise RuntimeError(
                    f"No image in response. Snippet: {json.dumps(payload)[:500]}"
                )
            return img_bytes

        is_retryable = resp.status_code == 429 or 500 <= resp.status_code < 600
        err_msg = f"HTTP {resp.status_code}: {resp.text[:300]}"

        if not is_retryable or attempt >= 1:
            raise RuntimeError(f"Imagen API error — {err_msg}")

        print(
            f"  [retry] {err_msg} — sleeping {_RETRY_SLEEP_SEC:.0f}s before retry...",
            file=sys.stderr,
        )
        time.sleep(_RETRY_SLEEP_SEC)

    # 도달 불가 (루프 내 raise 가 먼저 발생). type checker 만족용.
    raise RuntimeError("Imagen API exhausted retries")


# ---------------------------------------------------------------------------
# 메인
# ---------------------------------------------------------------------------


def main() -> int:
    args = parse_args()

    out_path = Path(args.output)
    meta_path = out_path.with_suffix(".json")

    # --dry-run: API 호출 없이 정보만 출력
    if args.dry_run:
        print("=== DRY RUN ===")
        print(f"Output PNG : {out_path}")
        print(f"Meta JSON  : {meta_path}")
        print(f"Model      : {args.model}")
        print(f"Aspect     : {args.aspect_ratio}")
        print(f"Seed       : {args.seed}")
        print(f"Bounds     : {_BOUNDS}")
        print()
        print("=== PROMPT ===")
        print(_BASEMAP_PROMPT)
        print()
        print("=== NEGATIVE PROMPT ===")
        print(_NEGATIVE_PROMPT)
        return 0

    # 환경 변수 검증
    if not args.project:
        print(
            "ERROR: GOOGLE_CLOUD_PROJECT not set. Use --project or env var.",
            file=sys.stderr,
        )
        return 2

    # 기존 파일 존재 확인
    if out_path.exists() and not args.overwrite:
        print(
            f"ERROR: {out_path} already exists. Use --overwrite to replace it.",
            file=sys.stderr,
        )
        return 2

    # 출력 디렉토리 확보
    out_path.parent.mkdir(parents=True, exist_ok=True)

    # 토큰 취득
    print(f"Authenticating with GCP project '{args.project}'...")
    token = get_access_token()

    # Imagen 호출
    print(
        f"Generating basemap → {out_path}"
        f"  (model={args.model}, aspect={args.aspect_ratio}"
        + (f", seed={args.seed}" if args.seed is not None else "")
        + ")"
    )
    img_bytes = call_imagen(
        project=args.project,
        location=args.location,
        model=args.model,
        prompt=_BASEMAP_PROMPT,
        negative_prompt=_NEGATIVE_PROMPT,
        aspect_ratio=args.aspect_ratio,
        seed=args.seed,
        token=token,
    )

    # PNG 저장
    out_path.write_bytes(img_bytes)
    size_mb = len(img_bytes) / (1024 * 1024)
    print(f"Done: {out_path} ({size_mb:.1f} MB)")

    # 메타 JSON 저장
    meta = {
        **_BOUNDS,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "model": args.model,
        "aspect_ratio": args.aspect_ratio,
        "prompt": _BASEMAP_PROMPT,
    }
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Meta: {meta_path}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
