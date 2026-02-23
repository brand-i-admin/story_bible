#!/usr/bin/env python3
"""Generate UI element PNG files from Vertex AI image models using assets.json.

Usage example:
  export GOOGLE_CLOUD_PROJECT="your-project-id"
  export GOOGLE_CLOUD_LOCATION="us-central1"
  python tools/generate_assets_vertex.py
"""

from __future__ import annotations

import argparse
import base64
import json
import math
import os
from pathlib import Path
import sys
import time
from typing import Any

import google.auth
from google.auth.transport.requests import Request
import requests


CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
SUPPORTED_ASPECT_RATIOS = ("1:1", "3:4", "4:3", "9:16", "16:9")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate UI element assets with Vertex AI (Imagen or Gemini)."
    )
    parser.add_argument(
        "--prompt-json",
        default="tools/assets.json",
        help="Path to assets prompt JSON file.",
    )
    parser.add_argument(
        "--project",
        default=os.getenv("GOOGLE_CLOUD_PROJECT", ""),
        help="GCP project id. Defaults to GOOGLE_CLOUD_PROJECT.",
    )
    parser.add_argument(
        "--location",
        default=os.getenv("GOOGLE_CLOUD_LOCATION", "us-central1"),
        help="Vertex AI region. Defaults to GOOGLE_CLOUD_LOCATION or us-central1.",
    )
    parser.add_argument(
        "--model",
        default="imagen-4.0-ultra-generate-001",
        help="Vertex model id (for example, imagen-4.0-generate-001 or gemini-2.5-flash-image).",
    )
    parser.add_argument(
        "--output-dir",
        default="assets/elements",
        help="Directory to save generated PNG files.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing files.",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="Generate only first N assets (0 = all).",
    )
    parser.add_argument(
        "--sleep-sec",
        type=float,
        default=0.2,
        help="Sleep seconds between requests.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print prompts without calling API.",
    )
    parser.add_argument(
        "--ids",
        default="",
        help="Comma-separated asset ids to generate (empty = all).",
    )
    parser.add_argument(
        "--aspect-ratio",
        default="auto",
        choices=["auto", *SUPPORTED_ASPECT_RATIOS],
        help="Force aspect ratio or choose best from size_px (auto).",
    )
    parser.add_argument(
        "--enhance-prompt",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Enable/disable Imagen prompt enhancement.",
    )
    parser.add_argument(
        "--sample-count",
        type=int,
        default=1,
        help="Number of samples per request (first usable image is saved).",
    )
    return parser.parse_args()


def load_assets_config(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if "assets" not in data or not isinstance(data["assets"], list):
        raise ValueError("Invalid JSON: 'assets' list is required.")
    return data


def get_access_token() -> str:
    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


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


def decode_image_bytes(prediction: dict[str, Any]) -> bytes:
    image_bytes = _extract_image_bytes(prediction)
    if image_bytes is None:
        keys = sorted(prediction.keys())
        raise ValueError(f"No image base64 field found in prediction. keys={keys}")
    return image_bytes


def normalize_text_list(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [value.strip()]
    return []


def build_final_prompt(
    asset_prompt: str,
    global_rules: list[str],
    *,
    transparent_background: bool = False,
) -> str:
    parts: list[str] = []
    parts.extend(global_rules)
    parts.append(asset_prompt.strip())
    prompt = ", ".join(part for part in parts if part)

    if transparent_background and "transparent background" not in prompt.lower():
        prompt = f"{prompt}, PNG with transparent background"

    return prompt


def parse_size_px(asset: dict[str, Any]) -> tuple[int | None, int | None]:
    size_px = asset.get("size_px")
    if not isinstance(size_px, dict):
        return None, None
    w = size_px.get("w")
    h = size_px.get("h")
    if not isinstance(w, (int, float)) or not isinstance(h, (int, float)):
        return None, None
    if w <= 0 or h <= 0:
        return None, None
    return int(w), int(h)


def aspect_ratio_value(ratio: str) -> float:
    w_text, h_text = ratio.split(":")
    return float(w_text) / float(h_text)


def choose_aspect_ratio(
    width: int | None,
    height: int | None,
    forced_ratio: str,
) -> str:
    if forced_ratio != "auto":
        return forced_ratio
    if not width or not height:
        return "1:1"

    target = float(width) / float(height)
    best = "1:1"
    best_score = float("inf")
    for ratio in SUPPORTED_ASPECT_RATIOS:
        candidate = aspect_ratio_value(ratio)
        score = abs(math.log(target) - math.log(candidate))
        if score < best_score:
            best_score = score
            best = ratio
    return best


def build_request_body(
    prompt: str,
    negative_prompt: str,
    *,
    aspect_ratio: str,
    sample_count: int,
    enhance_prompt: bool,
) -> dict[str, Any]:
    return {
        "instances": [{"prompt": prompt}],
        "parameters": {
            "sampleCount": max(1, int(sample_count)),
            "aspectRatio": aspect_ratio,
            "enhancePrompt": bool(enhance_prompt),
            "negativePrompt": negative_prompt,
            "outputOptions": {"mimeType": "image/png"},
        },
    }


def build_gemini_request_body(
    prompt: str,
    negative_prompt: str,
    *,
    aspect_ratio: str,
    sample_count: int,
) -> dict[str, Any]:
    instruction_parts = [
        f"Generate an image with aspect ratio {aspect_ratio}.",
        "Return only generated image content.",
    ]
    if negative_prompt:
        instruction_parts.append(f"Avoid the following in the image: {negative_prompt}.")
    prompt_text = f"{prompt}\n\n{' '.join(instruction_parts)}"

    return {
        "contents": [{"role": "user", "parts": [{"text": prompt_text}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "candidateCount": max(1, int(sample_count)),
        },
    }


def is_gemini_model(model: str) -> bool:
    return model.strip().lower().startswith("gemini")


def main() -> int:
    args = parse_args()
    use_gemini_api = is_gemini_model(args.model)

    prompt_path = Path(args.prompt_json)
    if not prompt_path.exists():
        print(f"ERROR: prompt json not found: {prompt_path}", file=sys.stderr)
        return 2

    config = load_assets_config(prompt_path)
    style_rules = config.get("style_rules", {})
    global_rules = normalize_text_list(style_rules.get("global"))
    negative_prompt = ", ".join(normalize_text_list(style_rules.get("negative_prompt")))

    assets = config["assets"]
    if args.ids.strip():
        allowed = {item.strip() for item in args.ids.split(",") if item.strip()}
        assets = [asset for asset in assets if asset.get("id") in allowed]
    if args.limit > 0:
        assets = assets[: args.limit]

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    endpoint = (
        f"https://{args.location}-aiplatform.googleapis.com/v1/projects/"
        f"{args.project}/locations/{args.location}/publishers/google/models/"
        f"{args.model}:{'generateContent' if use_gemini_api else 'predict'}"
    )

    if args.dry_run:
        for idx, asset in enumerate(assets, start=1):
            asset_id = str(asset.get("id", f"asset_{idx}"))
            filename = str(asset.get("filename", f"{asset_id}.png"))
            width, height = parse_size_px(asset)
            aspect_ratio = choose_aspect_ratio(width, height, args.aspect_ratio)
            prompt = build_final_prompt(
                str(asset.get("prompt", "")).strip(),
                global_rules,
                transparent_background=bool(asset.get("transparent_background", False)),
            )
            print(
                f"[DRY] {idx:02d} {asset_id} -> {filename} "
                f"(size={width}x{height}, aspect={aspect_ratio})"
            )
            print(f"      {prompt}")
        print(f"DRY-RUN complete: {len(assets)} assets")
        return 0

    if not args.project:
        print(
            "ERROR: project id is required. Set --project or GOOGLE_CLOUD_PROJECT.",
            file=sys.stderr,
        )
        return 2

    token = get_access_token()
    session = requests.Session()
    session.headers.update(
        {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        }
    )

    success = 0
    failure = 0

    for idx, asset in enumerate(assets, start=1):
        asset_id = str(asset.get("id", f"asset_{idx}"))
        filename = str(asset.get("filename", f"{asset_id}.png"))
        out_file = out_dir / filename

        if out_file.exists() and not args.overwrite:
            print(f"[SKIP] {idx:02d} {asset_id} -> {out_file} (exists)")
            continue

        width, height = parse_size_px(asset)
        aspect_ratio = choose_aspect_ratio(width, height, args.aspect_ratio)
        prompt = build_final_prompt(
            str(asset.get("prompt", "")).strip(),
            global_rules,
            transparent_background=bool(asset.get("transparent_background", False)),
        )

        if use_gemini_api:
            body = build_gemini_request_body(
                prompt,
                negative_prompt,
                aspect_ratio=aspect_ratio,
                sample_count=args.sample_count,
            )
        else:
            body = build_request_body(
                prompt,
                negative_prompt,
                aspect_ratio=aspect_ratio,
                sample_count=args.sample_count,
                enhance_prompt=args.enhance_prompt,
            )

        try:
            response = session.post(endpoint, json=body, timeout=180)
            if response.status_code >= 400:
                failure += 1
                print(
                    f"[FAIL] {idx:02d} {asset_id} status={response.status_code} "
                    f"body={response.text[:300]}"
                )
                continue

            payload = response.json()
            predictions = (
                payload.get("candidates", [])
                if use_gemini_api
                else payload.get("predictions", [])
            )
            if not predictions:
                failure += 1
                empty_key = "candidates" if use_gemini_api else "predictions"
                print(f"[FAIL] {idx:02d} {asset_id} no {empty_key}")
                continue

            img_bytes = None
            last_error = ""
            for prediction in predictions:
                try:
                    img_bytes = decode_image_bytes(prediction)
                    break
                except ValueError as exc:
                    last_error = str(exc)

            if img_bytes is None:
                failure += 1
                print(
                    f"[FAIL] {idx:02d} {asset_id} "
                    f"{last_error or 'No usable image found.'}"
                )
                continue

            out_file.write_bytes(img_bytes)
            success += 1
            print(
                f"[OK]   {idx:02d} {asset_id} -> {out_file} "
                f"(size={width}x{height}, aspect={aspect_ratio})"
            )
        except Exception as exc:  # noqa: BLE001
            failure += 1
            print(f"[FAIL] {idx:02d} {asset_id} error={exc}")

        if args.sleep_sec > 0:
            time.sleep(args.sleep_sec)

    print(f"Done. success={success} failure={failure}")
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
