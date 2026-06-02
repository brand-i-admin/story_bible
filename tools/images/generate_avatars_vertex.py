#!/usr/bin/env python3
"""Generate avatar PNG files from Vertex AI Gemini using a prompt JSON file.

Usage example:
  export GOOGLE_CLOUD_PROJECT="your-project-id"
  export GOOGLE_CLOUD_LOCATION="global"
  python tools/images/generate_avatars_vertex.py
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import sys
import time
from typing import Any

import google.auth
from google.auth.transport.requests import Request
import requests

CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
LATEST_IMAGE_MODEL = "gemini-3-pro-image"
LATEST_STABLE_IMAGE_MODEL = "gemini-2.5-flash-image"
ADULT_GUARDRAIL = (
    "all characters are clearly adults age 25+, adult body proportions, "
    "fully clothed, no children, no minors, non-photoreal 2D cartoon "
    "illustration, stylized geometric character, not a real character photo"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate character avatars with Vertex AI Gemini image models."
    )
    parser.add_argument(
        "--character-meta-json",
        default="tools/seed/character_meta.json",
        help="Path to character meta JSON file (source of avatar prompts).",
    )
    parser.add_argument(
        "--project",
        default=os.getenv("GOOGLE_CLOUD_PROJECT", ""),
        help="GCP project id. Defaults to GOOGLE_CLOUD_PROJECT.",
    )
    parser.add_argument(
        "--location",
        default=os.getenv("GOOGLE_CLOUD_LOCATION", "global"),
        help="Vertex AI region. Defaults to GOOGLE_CLOUD_LOCATION or global.",
    )
    parser.add_argument(
        "--model",
        default=os.getenv(
            "VERTEX_AVATAR_IMAGE_MODEL",
            os.getenv("VERTEX_IMAGE_MODEL", "latest"),
        ),
        help=(
            "Vertex image model id. Aliases: latest -> "
            f"{LATEST_IMAGE_MODEL}, stable -> {LATEST_STABLE_IMAGE_MODEL}."
        ),
    )
    parser.add_argument(
        "--character-generation",
        default="",
        choices=["", "allow_adult", "allow_all", "dont_allow"],
        help=(
            "Override people generation policy. Empty string uses JSON default. "
            "Values: allow_adult | allow_all | dont_allow."
        ),
    )
    parser.add_argument(
        "--output-dir",
        default="assets/avatars",
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
        help="Generate only first N characters (0 = all).",
    )
    parser.add_argument(
        "--only-codes",
        default="",
        help="Comma-separated character codes to generate, e.g. hagar,sarah.",
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
        "--no-adult-guardrail",
        action="store_true",
        help="Do not append adult-only guardrail text to prompts.",
    )
    parser.add_argument(
        "--no-prune-orphans",
        action="store_true",
        help=(
            "기본 동작은 character_meta.json 에 없는 PNG 를 자동 삭제한다. "
            "이 플래그를 주면 정리 단계를 스킵한다."
        ),
    )
    return parser.parse_args()


def prune_orphan_avatars(
    out_dir: Path,
    active_codes: set[str],
) -> list[Path]:
    """character_meta.json 에 없는 *.png 를 삭제한다.

    user 가 stories 에서 인물을 빼면 character_meta.json 에서도 빠지는데,
    assets/avatars/ 에 PNG 가 남으면 stale 자산이 된다. 여기서 깔끔하게 정리.
    """
    if not out_dir.exists():
        return []
    removed: list[Path] = []
    for path in sorted(out_dir.glob("*.png")):
        if path.stem not in active_codes:
            path.unlink()
            removed.append(path)
            print(f"[PRUNE] removed orphan avatar: {path}")
    return removed


def load_person_meta(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    if "characters" not in data or not isinstance(data["characters"], list):
        raise ValueError("Invalid JSON: 'characters' list is required.")
    return data


def combine_negative_prompt(
    base_negative_prompt: str, extra_negative_prompt: str
) -> str:
    parts = [
        part.strip()
        for part in (base_negative_prompt, extra_negative_prompt)
        if part and part.strip()
    ]
    return ", ".join(parts)


def build_final_prompt(
    raw_prompt: str,
    common_style: str,
    *,
    include_adult_guardrail: bool = True,
    use_common_style: bool = True,
) -> str:
    prompt = raw_prompt.strip()
    if use_common_style and common_style:
        if "COMMON_STYLE" in prompt:
            prompt = prompt.replace("COMMON_STYLE", common_style).strip()
        elif not prompt.startswith(common_style):
            prompt = f"{common_style}, {prompt}"
    else:
        prompt = prompt.replace("COMMON_STYLE", "").strip()

    # Normalize comma spacing and remove empty segments after token replacement.
    prompt = ", ".join(part.strip() for part in prompt.split(",") if part.strip())

    if not include_adult_guardrail:
        return prompt

    lower = prompt.lower()
    if "no children" in lower or "no minors" in lower or "age 25+" in lower:
        return prompt
    return f"{prompt}, {ADULT_GUARDRAIL}"


def get_access_token() -> str:
    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


def dedupe_preserve_order(items: list[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        result.append(item)
    return result


def resolve_model_alias(model: str) -> str:
    normalized = str(model).strip()
    if not normalized or normalized == "latest":
        return LATEST_IMAGE_MODEL
    if normalized == "stable":
        return LATEST_STABLE_IMAGE_MODEL
    return normalized


def resolve_location_for_model(location: str, model: str) -> str:
    requested = str(location).strip() or "global"
    if model.startswith("gemini-3-") and requested != "global":
        return "global"
    return requested


def request_model_candidates(primary_model: str) -> list[str]:
    models = [primary_model]
    if primary_model == LATEST_IMAGE_MODEL:
        models.append(LATEST_STABLE_IMAGE_MODEL)
    return dedupe_preserve_order(models)


def build_vertex_endpoint(*, project: str, location: str, model: str) -> str:
    host = (
        "aiplatform.googleapis.com"
        if location == "global"
        else f"{location}-aiplatform.googleapis.com"
    )
    method = "generateContent" if model.lower().startswith("gemini") else "predict"
    return (
        f"https://{host}/v1/projects/{project}/locations/{location}/"
        f"publishers/google/models/{model}:{method}"
    )


def extract_filter_reason(node: Any) -> str | None:
    """Extract a safety/filter reason from a nested API response payload."""
    if isinstance(node, dict):
        for key in (
            "raiFilteredReason",
            "raiFilterReason",
            "blockedReason",
            "safetyFilterReason",
            "filteredReason",
        ):
            if key not in node:
                continue
            value = node[key]
            if value is None:
                continue
            if isinstance(value, str):
                value = value.strip()
                if value:
                    return f"{key}={value}"
                continue
            return f"{key}={value}"

        for value in node.values():
            reason = extract_filter_reason(value)
            if reason:
                return reason
        return None

    if isinstance(node, list):
        for item in node:
            reason = extract_filter_reason(item)
            if reason:
                return reason
        return None

    return None


def get_filter_hint(reason: str) -> str:
    lower = reason.lower()
    if "children" in lower or "minors" in lower:
        return (
            " hint=Prompt looked child-like. Try a less childlike style or run "
            "with --character-generation allow_all."
        )
    return ""


def _maybe_decode_base64(raw: str) -> bytes | None:
    value = raw.strip()
    if not value:
        return None

    if value.startswith("data:"):
        parts = value.split(",", 1)
        if len(parts) != 2:
            return None
        value = parts[1]

    # Some APIs include line breaks in base64 payloads.
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
    if image_bytes is not None:
        return image_bytes

    reason = extract_filter_reason(prediction)
    if reason:
        raise ValueError(f"Image filtered: {reason}")

    keys = sorted(prediction.keys())
    raise ValueError(f"No image base64 field found in prediction. keys={keys}")


def build_imagen_request_body(
    prompt: str,
    negative_prompt: str,
    defaults: dict[str, Any],
    person_generation_override: str = "",
) -> dict[str, Any]:
    mime_type = defaults.get("outputMimeType", "image/png")
    person_generation = person_generation_override or defaults.get(
        "personGeneration", "allow_adult"
    )
    body = {
        "instances": [{"prompt": prompt}],
        "parameters": {
            "sampleCount": int(defaults.get("sampleCount", 1)),
            "aspectRatio": defaults.get("aspectRatio", "1:1"),
            "enhancePrompt": bool(defaults.get("enhancePrompt", True)),
            "personGeneration": person_generation,
            "negativePrompt": negative_prompt,
            "outputOptions": {"mimeType": mime_type},
        },
    }
    return body


def build_gemini_request_body(
    prompt: str,
    negative_prompt: str,
    defaults: dict[str, Any],
) -> dict[str, Any]:
    sample_count = int(defaults.get("sampleCount", 1))
    text = prompt
    if negative_prompt:
        text = f"{text}\n\nNegative prompt: avoid {negative_prompt}."
    return {
        "contents": [{"role": "user", "parts": [{"text": text}]}],
        "generationConfig": {
            "responseModalities": ["IMAGE"],
            "candidateCount": max(1, sample_count),
        },
    }


def main() -> int:
    args = parse_args()
    resolved_model = resolve_model_alias(args.model)
    resolved_location = resolve_location_for_model(args.location, resolved_model)
    request_models = request_model_candidates(resolved_model)

    meta_path = Path(args.character_meta_json)
    if not meta_path.exists():
        print(f"ERROR: character meta json not found: {meta_path}", file=sys.stderr)
        return 2

    config = load_person_meta(meta_path)
    common_style = config.get("common_style", "").strip()
    negative_prompt = config.get("negative_prompt", "").strip()
    defaults = config.get("generation_defaults", {})
    all_characters = sorted(
        config["characters"],
        key=lambda c: int(c.get("index", 0)),
    )
    characters = list(all_characters)
    only_codes = {
        code.strip() for code in str(args.only_codes).split(",") if code.strip()
    }
    if only_codes:
        characters = [
            character
            for character in characters
            if str(character.get("code", "")).strip() in only_codes
        ]
        missing_codes = sorted(
            only_codes
            - {str(character.get("code", "")).strip() for character in characters}
        )
        if missing_codes:
            print(
                f"ERROR: unknown character codes: {', '.join(missing_codes)}",
                file=sys.stderr,
            )
            return 2
    if args.limit > 0:
        characters = characters[: args.limit]

    if args.dry_run:
        for item in characters:
            use_common_style = bool(item.get("use_common_style", True))
            disable_adult_guardrail = bool(item.get("disable_adult_guardrail", False))
            prompt = build_final_prompt(
                item["prompt"],
                common_style,
                include_adult_guardrail=(not args.no_adult_guardrail)
                and (not disable_adult_guardrail),
                use_common_style=use_common_style,
            )
            print(f"[DRY] {item['index']:02d} {item['code']}: {prompt}")
        print(
            f"DRY-RUN complete: {len(characters)} prompts "
            f"model={resolved_model} location={resolved_location}"
        )
        return 0

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # Prune 은 GCP project 없이도 안전하게 동작 → project 검증 전에 실행.
    if not args.no_prune_orphans:
        active_codes = {str(c.get("code", "")).strip() for c in all_characters}
        active_codes.discard("")
        prune_orphan_avatars(out_dir, active_codes)

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

    for item in characters:
        code = item["code"]
        index = int(item.get("index", 0))
        use_common_style = bool(item.get("use_common_style", True))
        disable_adult_guardrail = bool(item.get("disable_adult_guardrail", False))
        per_item_person_generation = str(item.get("person_generation", "")).strip()
        per_item_negative_prompt = str(item.get("negative_prompt_extra", "")).strip()
        prompt = build_final_prompt(
            item["prompt"],
            common_style,
            include_adult_guardrail=(not args.no_adult_guardrail)
            and (not disable_adult_guardrail),
            use_common_style=use_common_style,
        )
        final_negative_prompt = combine_negative_prompt(
            negative_prompt,
            per_item_negative_prompt,
        )
        out_file = out_dir / f"{code}.png"

        if out_file.exists() and not args.overwrite:
            print(f"[SKIP] {index:02d} {code} -> {out_file} (exists)")
            continue

        try:
            response: requests.Response | None = None
            used_model = request_models[0]
            used_location = resolved_location
            for model_index, candidate_model in enumerate(request_models):
                used_model = candidate_model
                used_location = resolve_location_for_model(
                    resolved_location,
                    candidate_model,
                )
                endpoint = build_vertex_endpoint(
                    project=args.project,
                    location=used_location,
                    model=candidate_model,
                )
                if candidate_model.lower().startswith("gemini"):
                    body = build_gemini_request_body(
                        prompt,
                        final_negative_prompt,
                        defaults,
                    )
                else:
                    body = build_imagen_request_body(
                        prompt,
                        final_negative_prompt,
                        defaults,
                        person_generation_override=(
                            args.character_generation or per_item_person_generation
                        ),
                    )

                response = session.post(endpoint, json=body, timeout=180)
                if response.status_code != 404:
                    break
                if model_index + 1 < len(request_models):
                    print(
                        f"[FALLBACK] {index:02d} {code} model={candidate_model} "
                        f"returned 404, retrying with {request_models[model_index + 1]}"
                    )

            assert response is not None
            if response.status_code >= 400:
                failure += 1
                print(
                    f"[FAIL] {index:02d} {code} status={response.status_code} "
                    f"model={used_model} body={response.text[:300]}"
                )
                continue

            payload = response.json()
            response_items = (
                payload.get("candidates", [])
                if used_model.lower().startswith("gemini")
                else payload.get("predictions", [])
            )
            if not response_items:
                failure += 1
                reason = extract_filter_reason(payload)
                if reason:
                    hint = get_filter_hint(reason)
                    print(f"[FAIL] {index:02d} {code} no image items ({reason}){hint}")
                else:
                    print(f"[FAIL] {index:02d} {code} no image items")
                continue

            img_bytes = None
            last_error = ""
            for item_payload in response_items:
                try:
                    img_bytes = decode_image_bytes(item_payload)
                    break
                except ValueError as exc:
                    last_error = str(exc)

            if img_bytes is None:
                failure += 1
                reason = extract_filter_reason(payload)
                detail = reason or last_error or "No usable image found."
                hint = get_filter_hint(detail)
                print(f"[FAIL] {index:02d} {code} {detail}{hint}")
                continue

            out_file.write_bytes(img_bytes)
            success += 1
            print(
                f"[OK]   {index:02d} {code} -> {out_file} "
                f"(model={used_model}, location={used_location})"
            )
        except Exception as exc:  # noqa: BLE001
            failure += 1
            print(f"[FAIL] {index:02d} {code} error={exc}")

        if args.sleep_sec > 0:
            time.sleep(args.sleep_sec)

    print(f"Done. success={success} failure={failure}")
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
