#!/usr/bin/env python3
"""Generate map decoration PNG files from Vertex AI Imagen.

지도 위에 양피지 톤 일러스트 데코(산·도시·피라미드·나무 등)를 생성한다.
카탈로그(`assets/decos/decos_catalog.json`)의 `kinds` 배열을 읽어 각 kind 별로
프롬프트 1개씩 호출 → `assets/decos/{kind}.png` 로 저장. kind 1개 = PNG 1장.

배치(어디에 그리는지)는 `placements` 배열이 담당하며 코드 변경 없이 데이터만
수정해 늘리거나 줄일 수 있다.

Usage:
    export GOOGLE_CLOUD_PROJECT="your-project-id"
    export GOOGLE_CLOUD_LOCATION="us-central1"
    python tools/images/generate_decos_vertex.py            # 모든 kind 생성
    python tools/images/generate_decos_vertex.py --only mountain pyramid  # 일부만
    python tools/images/generate_decos_vertex.py --overwrite   # 기존 파일 덮어쓰기
    python tools/images/generate_decos_vertex.py --dry-run     # 프롬프트만 출력

기존 `tools/images/generate_avatars_vertex.py` 와 동일한 인증·요청 방식.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

import google.auth
from google.auth.transport.requests import Request
import requests

CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"

# Service Usage API metric for per-base-model online prediction RPM 한도.
# Vertex Imagen 의 quota 가 이 metric 으로 노출됨. 모델 revision (e.g. -001)
# 은 base_model 차원에서 떼고 매칭한다 — `imagen-4.0-generate-001` →
# `imagen-4.0-generate`.
_QUOTA_METRIC = "aiplatform.googleapis.com/online_prediction_requests_per_base_model"

# Service Usage API 가 quota 를 못 알려줄 때(권한·네트워크) 쓰는 보수적 기본.
# Imagen 4.0 의 default 가 통상 5 RPM 이라 13s 면 안전.
_FALLBACK_SLEEP_SEC = 13.0


def _base_model_from_full(model: str) -> str:
    """`imagen-4.0-generate-001` → `imagen-4.0-generate` 처럼 마지막 `-숫자`
    revision suffix 만 떼낸 base model 을 반환. revision 이 없으면 그대로.
    """
    parts = model.rsplit("-", 1)
    if len(parts) == 2 and parts[1].isdigit():
        return parts[0]
    return model


def fetch_quota_rpm(
    *,
    project: str,
    location: str,
    model: str,
    token: str,
) -> int | None:
    """Service Usage API 로 현재 프로젝트의 Imagen RPM quota 를 조회.

    찾은 effective limit (RPM) 를 반환, 못 찾으면 None. 실패는 silent —
    호출자가 fallback 시간을 사용한다.

    공식 endpoint:
      GET v1beta1/projects/{project}/services/aiplatform.googleapis.com
          /consumerQuotaMetrics/{metric_url_encoded}

    응답 안의 quotaBuckets 중 region+base_model 차원이 매칭되는 bucket 의
    effectiveLimit 을 사용. 같은 차원의 bucket 이 여러 개면 가장 작은 값을
    채택 (가장 제한적인 quota 가 실제 적용 한도).
    """
    base_model = _base_model_from_full(model)
    metric_path = requests.utils.quote(_QUOTA_METRIC, safe="")
    url = (
        f"https://serviceusage.googleapis.com/v1beta1"
        f"/projects/{project}"
        f"/services/aiplatform.googleapis.com"
        f"/consumerQuotaMetrics/{metric_path}"
    )
    try:
        resp = requests.get(
            url,
            headers={"Authorization": f"Bearer {token}"},
            timeout=20,
        )
        if resp.status_code != 200:
            return None
        data = resp.json()
    except Exception:  # noqa: BLE001
        return None

    best: int | None = None
    for limit in data.get("consumerQuotaLimits", []) or []:
        unit = limit.get("unit", "")
        # per-minute 한도만 사용. 다른 단위 (per-day 등) 는 무시.
        if "/min/" not in unit:
            continue
        for bucket in limit.get("quotaBuckets", []) or []:
            dims = bucket.get("dimensions") or {}
            region = dims.get("region")
            base = dims.get("base_model")
            # region/base_model 차원이 명시됐으면 매칭만 채택. 명시 안 됐으면
            # 전 region/모델 공통 default 라 보고 후보로 둔다.
            if region and region != location:
                continue
            if base and base != base_model:
                continue
            eff = bucket.get("effectiveLimit") or bucket.get("defaultLimit")
            if eff is None:
                continue
            try:
                val = int(eff)
            except (TypeError, ValueError):
                continue
            if val <= 0:
                continue
            if best is None or val < best:
                best = val
    return best


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate map decoration sprites with Vertex AI Imagen."
    )
    parser.add_argument(
        "--catalog",
        default="assets/decos/decos_catalog.json",
        help="Decoration catalog JSON path.",
    )
    parser.add_argument(
        "--output-dir",
        default="assets/decos",
        help="Directory to save generated PNG files.",
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
        default="imagen-4.0-generate-001",
        help="Imagen model id.",
    )
    parser.add_argument(
        "--aspect-ratio",
        default="1:1",
        help="Image aspect ratio (e.g. 1:1, 4:3).",
    )
    parser.add_argument(
        "--only",
        nargs="+",
        default=None,
        help="Generate only listed kinds (space-separated). Default: all.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing PNG files. Default skips existing.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print prompts without calling API.",
    )
    parser.add_argument(
        "--sleep-sec",
        type=float,
        default=None,
        help=(
            "Sleep seconds between requests. Default: auto-discover via Service "
            "Usage API — query the live RPM quota for the chosen model and "
            "space requests at 60/RPM + 1s buffer. Pass an explicit value "
            "(e.g. 13) to skip auto-discover. Fallback when API call fails: "
            f"{_FALLBACK_SLEEP_SEC}s. (429 is also auto-retried with backoff.)"
        ),
    )
    parser.add_argument(
        "--max-retries",
        type=int,
        default=5,
        help="Max retries on HTTP 429 / 5xx, with exponential backoff.",
    )
    parser.add_argument(
        "--initial-backoff-sec",
        type=float,
        default=20.0,
        help="Initial backoff seconds for 429 retry. Doubles each retry.",
    )
    parser.add_argument(
        "--no-chroma-key",
        action="store_true",
        help="Skip the white-background → transparent post-processing step.",
    )
    parser.add_argument(
        "--rekey-only",
        action="store_true",
        help=(
            "Skip Imagen calls entirely; just re-run the chroma-key on existing "
            "PNGs in --output-dir matching catalog kinds. Lets you iterate on "
            "tolerance/soft-edge without burning credits."
        ),
    )
    parser.add_argument(
        "--chroma-tolerance",
        type=int,
        default=42,
        help=(
            "Color distance tolerance (0-255) for the corner flood-fill that "
            "converts the solid background to transparent. Lower = stricter. "
            "Raise if the background bleeds into the subject; lower if too "
            "much of the background remains."
        ),
    )
    parser.add_argument(
        "--chroma-soft-edge",
        type=int,
        default=2,
        help=(
            "Pixels of soft alpha feather at the transparent/opaque boundary. "
            "0 disables. Higher = softer edge, less aliasing on the map."
        ),
    )
    return parser.parse_args()


def get_access_token() -> str:
    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


def chroma_key_to_transparent(
    img_bytes: bytes,
    *,
    tolerance: int,
    soft_edge: int,
) -> bytes:
    """평면 흰색 배경을 투명으로 바꾼 PNG 를 반환.

    Imagen 4.0 은 진정한 alpha PNG 를 만들지 못하고 흰색/베이지 면을 그려 준다.
    카탈로그 prompt 가 "isolated illustration on pure white background" 으로
    유도하므로, 여기서 네 모서리에서 flood-fill 로 연결된 흰 영역만 투명화한다
    (그림 내부의 흰 디테일은 보존). soft_edge 만큼 alpha feather 를 줘 지도
    위에 합성할 때 가장자리 톱니를 줄임.

    구현 의존성: Pillow (requirements.txt 에 포함).
    """
    try:
        from io import BytesIO

        from PIL import Image, ImageDraw, ImageFilter
    except ImportError as e:  # noqa: BLE001
        raise RuntimeError(
            "Pillow 가 설치되지 않았습니다. `pip install -r requirements.txt`"
            " 또는 `pip install Pillow` 후 다시 실행하세요. (--no-chroma-key"
            " 로 후처리를 건너뛸 수도 있음)"
        ) from e

    img = Image.open(BytesIO(img_bytes)).convert("RGBA")
    width, height = img.size

    # 4개 모서리에서 flood-fill 로 외부 배경 영역만 투명화. tolerance 는
    # 모서리 픽셀과의 RGB 거리 임계.
    corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)]
    for cx, cy in corners:
        try:
            ImageDraw.floodfill(
                img,
                xy=(cx, cy),
                value=(0, 0, 0, 0),
                thresh=tolerance,
            )
        except Exception:  # noqa: BLE001
            # 모서리가 이미 투명/특수 상태면 skip — 다음 모서리로 진행.
            continue

    if soft_edge > 0:
        # alpha 채널에 살짝 blur — 가장자리 anti-alias 매끄럽게.
        alpha = img.split()[-1]
        alpha = alpha.filter(ImageFilter.GaussianBlur(radius=soft_edge))
        img.putalpha(alpha)

    out = BytesIO()
    img.save(out, format="PNG", optimize=True)
    return out.getvalue()


def _maybe_decode_base64(raw: str) -> bytes | None:
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


def _extract_image_bytes(node: Any) -> bytes | None:
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
    token: str,
    max_retries: int = 5,
    initial_backoff_sec: float = 20.0,
) -> bytes:
    """Vertex Imagen 호출 + 429 자동 재시도.

    Imagen 의 기본 per-minute quota 가 매우 낮아 (보통 ~5 req/min) 연속 호출이
    바로 RESOURCE_EXHAUSTED 로 떨어지는 일이 잦다. 여기서 429 를 감지하면
    20s → 40s → 80s … 지수 backoff 로 자동 재시도해 사용자가 손으로 sleep
    조절하지 않아도 끝까지 진행되게 한다. (5xx 도 동일 처리.)

    HTTP 4xx (429 외) 는 prompt/권한 문제라 재시도하지 않고 즉시 RuntimeError.
    """
    url = (
        f"https://{location}-aiplatform.googleapis.com/v1/projects/{project}"
        f"/locations/{location}/publishers/google/models/{model}:predict"
    )
    body = {
        "instances": [{"prompt": prompt}],
        "parameters": {
            "sampleCount": 1,
            "aspectRatio": aspect_ratio,
            "addWatermark": False,
            "negativePrompt": negative_prompt,
            # 데코는 비인물 이미지지만 안전장치로 dont_allow.
            "personGeneration": "dont_allow",
        },
    }

    backoff = initial_backoff_sec
    last_err: str | None = None
    for attempt in range(max_retries + 1):
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

        # 429 (quota) 또는 5xx 는 재시도 가능. 그 외 4xx 는 즉시 실패.
        is_retryable = resp.status_code == 429 or 500 <= resp.status_code < 600
        last_err = f"{resp.status_code}: {resp.text[:300]}"
        if not is_retryable or attempt >= max_retries:
            raise RuntimeError(f"Imagen API {last_err}")

        wait_s = backoff
        print(
            f"  [retry] HTTP {resp.status_code} (quota?) — "
            f"attempt {attempt + 1}/{max_retries}, sleeping {wait_s:.0f}s "
            "before retry...",
            file=sys.stderr,
        )
        time.sleep(wait_s)
        backoff = min(backoff * 2.0, 240.0)

    # max_retries 소진 (위 raise 로 도달 안 하지만 type checker 만족용).
    raise RuntimeError(f"Imagen API exhausted retries: {last_err}")


def _rekey_existing(
    *,
    args: argparse.Namespace,
    kinds: list[dict[str, Any]],
    out_dir: Path,
) -> int:
    """기존 PNG 들에 chroma-key 만 다시 돌리는 fast path.

    Imagen 호출 없이 `assets/decos/{kind}.png` 를 열어 흰 배경을 투명화하고
    덮어쓴다. tolerance / soft_edge 튜닝 용도.
    """
    print(
        f"Re-keying existing PNG(s) in {out_dir} "
        f"(tolerance={args.chroma_tolerance}, soft_edge={args.chroma_soft_edge})"
    )
    succeeded: list[str] = []
    skipped: list[str] = []
    failed: list[tuple[str, str]] = []
    for entry in kinds:
        kind = entry.get("kind")
        if not kind:
            continue
        path = out_dir / f"{kind}.png"
        if not path.exists():
            print(f"[SKIP] {kind} (no PNG yet)")
            skipped.append(kind)
            continue
        try:
            data = path.read_bytes()
            keyed = chroma_key_to_transparent(
                data,
                tolerance=args.chroma_tolerance,
                soft_edge=args.chroma_soft_edge,
            )
            path.write_bytes(keyed)
            print(f"[KEY ] {kind} → {path}")
            succeeded.append(kind)
        except Exception as e:  # noqa: BLE001
            print(f"  ERROR: {e}", file=sys.stderr)
            failed.append((kind, str(e)))

    print()
    print("==== Summary (rekey-only) ====")
    print(f"  succeeded: {len(succeeded)}  {succeeded}")
    print(f"  skipped:   {len(skipped)}    {skipped}")
    print(f"  failed:    {len(failed)}     {[k for k, _ in failed]}")
    return 1 if failed else 0


def main() -> int:
    args = parse_args()
    if not args.project and not args.dry_run and not args.rekey_only:
        print(
            "ERROR: GOOGLE_CLOUD_PROJECT not set. Use --project or env var.",
            file=sys.stderr,
        )
        return 2

    catalog_path = Path(args.catalog)
    if not catalog_path.exists():
        print(f"ERROR: catalog not found: {catalog_path}", file=sys.stderr)
        return 2
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    kinds: list[dict[str, Any]] = catalog.get("kinds") or []
    common_style = (catalog.get("common_style") or "").strip()
    negative_prompt = (catalog.get("negative_prompt") or "").strip()

    if args.only:
        wanted = set(args.only)
        kinds = [k for k in kinds if k.get("kind") in wanted]
        missing = wanted - {k.get("kind") for k in kinds}
        if missing:
            print(f"WARN: --only kinds not found in catalog: {missing}")

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # --rekey-only: Imagen 생략, 기존 PNG 만 chroma-key 재처리. tolerance/
    # soft_edge 튜닝 시 비용 없이 반복 가능. PNG 가 이미 RGBA 투명이어도
    # flood-fill 은 모서리에서 매칭되는 픽셀만 다시 처리하므로 안전.
    if args.rekey_only:
        return _rekey_existing(args=args, kinds=kinds, out_dir=out_dir)

    print(
        f"Generating {len(kinds)} deco PNG(s) → {out_dir} "
        f"(model={args.model}, aspect={args.aspect_ratio})"
    )
    token = "" if args.dry_run else get_access_token()

    # 요청 간격 결정 — 사용자가 --sleep-sec 명시했으면 그걸 쓰고, 아니면
    # Service Usage API 로 현재 프로젝트의 RPM quota 를 조회해 자동 산출.
    # 조회 실패 시 보수적 fallback (_FALLBACK_SLEEP_SEC).
    if args.sleep_sec is not None:
        sleep_sec = args.sleep_sec
        print(f"[quota] sleep override → {sleep_sec:.1f}s between requests")
    elif args.dry_run:
        sleep_sec = 0.0
    else:
        rpm = fetch_quota_rpm(
            project=args.project,
            location=args.location,
            model=args.model,
            token=token,
        )
        if rpm and rpm > 0:
            # 60s/RPM + 1s safety buffer. 토큰 갱신/네트워크 jitter 흡수.
            sleep_sec = (60.0 / rpm) + 1.0
            print(
                f"[quota] auto-discovered {rpm} req/min for "
                f"{_base_model_from_full(args.model)} @ {args.location} → "
                f"spacing {sleep_sec:.1f}s between requests"
            )
        else:
            sleep_sec = _FALLBACK_SLEEP_SEC
            print(
                f"[quota] auto-discover failed (Service Usage API not "
                f"reachable or quota not exposed) → using fallback "
                f"{sleep_sec:.0f}s between requests. Override with --sleep-sec."
            )

    skipped: list[str] = []
    succeeded: list[str] = []
    failed: list[tuple[str, str]] = []

    for entry in kinds:
        kind = entry.get("kind")
        if not kind:
            continue
        out_path = out_dir / f"{kind}.png"
        if out_path.exists() and not args.overwrite:
            print(f"[SKIP] {kind} (exists; use --overwrite to regenerate)")
            skipped.append(kind)
            continue

        raw_prompt = (entry.get("prompt") or "").strip()
        if not raw_prompt:
            failed.append((kind, "no prompt in catalog"))
            continue

        # common_style 의 {SUBJECT} 자리표시자를 kind prompt 로 치환. 치환자가
        # 없으면 단순 prepend 로 fallback (구버전 카탈로그 호환).
        if common_style and "{SUBJECT}" in common_style:
            prompt = common_style.replace("{SUBJECT}", raw_prompt)
        elif common_style:
            prompt = f"{common_style}, {raw_prompt}"
        else:
            prompt = raw_prompt

        if args.dry_run:
            print(f"[DRY] {kind}\n  prompt: {prompt}\n  neg:    {negative_prompt}\n")
            continue

        print(f"[GEN] {kind} → {out_path}")
        try:
            img_bytes = call_imagen(
                project=args.project,
                location=args.location,
                model=args.model,
                prompt=prompt,
                negative_prompt=negative_prompt,
                aspect_ratio=args.aspect_ratio,
                token=token,
                max_retries=args.max_retries,
                initial_backoff_sec=args.initial_backoff_sec,
            )
            # 후처리 — 흰 배경 → 투명 PNG. 사용자가 --no-chroma-key 로 끄거나
            # 후처리가 실패하면 원본 PNG 를 그대로 저장.
            if not args.no_chroma_key:
                try:
                    img_bytes = chroma_key_to_transparent(
                        img_bytes,
                        tolerance=args.chroma_tolerance,
                        soft_edge=args.chroma_soft_edge,
                    )
                except Exception as e:  # noqa: BLE001
                    print(
                        f"  WARN: chroma-key 후처리 실패 ({e}). 원본 저장.",
                        file=sys.stderr,
                    )
            out_path.write_bytes(img_bytes)
            succeeded.append(kind)
        except Exception as e:  # noqa: BLE001
            print(f"  ERROR: {e}", file=sys.stderr)
            failed.append((kind, str(e)))
        time.sleep(sleep_sec)

    print()
    print(f"==== Summary ====")
    print(f"  succeeded: {len(succeeded)}  {succeeded}")
    print(f"  skipped:   {len(skipped)}    {skipped}")
    print(f"  failed:    {len(failed)}     {[k for k, _ in failed]}")
    if failed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
