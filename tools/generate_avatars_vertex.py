#!/usr/bin/env python3
"""Generate avatar PNG files from Vertex AI Imagen using a prompt JSON file.

Usage example:
  export GOOGLE_CLOUD_PROJECT="your-project-id"
  export GOOGLE_CLOUD_LOCATION="us-central1"
  python tools/generate_avatars_vertex.py
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time
from typing import Any

import google.auth
from google.auth.transport.requests import Request
import requests


CLOUD_PLATFORM_SCOPE = "https://www.googleapis.com/auth/cloud-platform"
MANIFEST_SCHEMA_VERSION = 1
AVATAR_MANIFEST_PATH = Path("supabase/generated_media/avatars.json")
ADULT_GUARDRAIL = (
    "all characters are clearly adults age 25+, adult body proportions, "
    "fully clothed, no children, no minors, non-photoreal 2D cartoon "
    "illustration, stylized geometric character, not a real person photo"
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate character avatars with Vertex AI Imagen."
    )
    parser.add_argument(
        "--prompt-json",
        default="tools/avatar_prompts.json",
        help="Path to prompt JSON file.",
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
        default="imagen-4.0-generate-001",
        help="Imagen model id.",
    )
    parser.add_argument(
        "--person-generation",
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
        "--no-normalize-framing",
        action="store_true",
        help="Do not normalize avatar framing after generation.",
    )
    parser.add_argument(
        "--content-ratio",
        type=float,
        default=0.90,
        help="Target visible content ratio inside the avatar canvas. Default is 0.90.",
    )
    parser.add_argument(
        "--white-threshold",
        type=int,
        default=248,
        help="Near-white threshold used by the framing normalizer. Default is 248.",
    )
    return parser.parse_args()


def load_prompt_config(path: Path) -> dict[str, Any]:
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


def normalize_avatar_files(
    paths: list[Path],
    *,
    content_ratio: float,
    white_threshold: int,
) -> None:
    if not paths:
        return

    script_path = Path(__file__).with_name("normalize_avatar_pngs.swift")
    if not script_path.exists():
        raise FileNotFoundError(f"Normalizer script not found: {script_path}")

    cmd = [
        "swift",
        str(script_path),
        "--content-ratio",
        f"{content_ratio:.4f}",
        "--white-threshold",
        str(white_threshold),
    ]
    cmd.extend(str(path) for path in paths)
    module_cache_dir = Path("/tmp/swift-module-cache")
    module_cache_dir.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.setdefault("CLANG_MODULE_CACHE_PATH", str(module_cache_dir))
    subprocess.run(cmd, check=True, env=env)


def get_access_token() -> str:
    creds, _ = google.auth.default(scopes=[CLOUD_PLATFORM_SCOPE])
    if not creds.valid:
        creds.refresh(Request())
    return creds.token


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
            "with --person-generation allow_all."
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


def build_request_body(
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


def natural_key(
    *,
    owner_type: str,
    owner_code: str,
    asset_role: str,
    variant: str,
    scene_index: int | None = None,
) -> str:
    scene_part = str(scene_index) if scene_index is not None else "none"
    return f"{owner_type}:{owner_code}:{asset_role}:{scene_part}:{variant}"


def repo_relative_path(path: Path) -> str:
    if not path.is_absolute():
        return path.as_posix()
    try:
        return path.relative_to(Path.cwd()).as_posix()
    except ValueError:
        return path.as_posix()


def sha256_for_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def build_avatar_manifest_asset(
    *,
    path: Path,
    prompt_item: dict[str, Any] | None,
    model: str,
) -> dict[str, Any]:
    code = path.stem
    metadata: dict[str, Any] = {}
    if prompt_item is not None:
        prompt_index = prompt_item.get("index")
        if isinstance(prompt_index, int):
            metadata["prompt_index"] = prompt_index
        name_ko = str(prompt_item.get("name_ko") or "").strip()
        if name_ko:
            metadata["name_ko"] = name_ko
        name_en = str(prompt_item.get("name_en") or "").strip()
        if name_en:
            metadata["name_en"] = name_en

    return {
        "natural_key": natural_key(
            owner_type="person",
            owner_code=code,
            asset_role="avatar",
            variant="original",
        ),
        "owner_type": "person",
        "owner_code": code,
        "asset_role": "avatar",
        "scene_index": None,
        "variant": "original",
        "relative_path": repo_relative_path(path),
        "source_relative_path": None,
        "mime_type": "image/png",
        "byte_size": path.stat().st_size,
        "content_hash": sha256_for_file(path),
        "generator": "tools/generate_avatars_vertex.py",
        "generator_model": model,
        "metadata": metadata,
    }


def write_avatar_manifest(
    *,
    out_dir: Path,
    prompt_items_by_code: dict[str, dict[str, Any]],
    model: str,
) -> None:
    assets = [
        build_avatar_manifest_asset(
            path=path,
            prompt_item=prompt_items_by_code.get(path.stem),
            model=model,
        )
        for path in sorted(out_dir.glob("*.png"))
    ]
    assets.sort(key=lambda item: item["natural_key"])

    AVATAR_MANIFEST_PATH.parent.mkdir(parents=True, exist_ok=True)
    AVATAR_MANIFEST_PATH.write_text(
        json.dumps(
            {
                "schema_version": MANIFEST_SCHEMA_VERSION,
                "asset_family": "avatars",
                "assets": assets,
            },
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()

    if not args.project:
        print(
            "ERROR: project id is required. Set --project or GOOGLE_CLOUD_PROJECT.",
            file=sys.stderr,
        )
        return 2

    prompt_path = Path(args.prompt_json)
    if not prompt_path.exists():
        print(f"ERROR: prompt json not found: {prompt_path}", file=sys.stderr)
        return 2

    config = load_prompt_config(prompt_path)
    common_style = config.get("common_style", "").strip()
    negative_prompt = config.get("negative_prompt", "").strip()
    defaults = config.get("generation_defaults", {})
    characters = sorted(
        config["characters"],
        key=lambda c: int(c.get("index", 0)),
    )
    prompt_items_by_code = {
        str(item.get("code", "")).strip(): item
        for item in config["characters"]
        if isinstance(item, dict) and str(item.get("code", "")).strip()
    }
    if args.limit > 0:
        characters = characters[: args.limit]

    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    endpoint = (
        f"https://{args.location}-aiplatform.googleapis.com/v1/projects/"
        f"{args.project}/locations/{args.location}/publishers/google/models/"
        f"{args.model}:predict"
    )

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
        print(f"DRY-RUN complete: {len(characters)} prompts")
        return 0

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
    generated_files: list[Path] = []

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

        body = build_request_body(
            prompt,
            final_negative_prompt,
            defaults,
            person_generation_override=(
                args.person_generation or per_item_person_generation
            ),
        )
        try:
            response = session.post(endpoint, json=body, timeout=180)
            if response.status_code >= 400:
                failure += 1
                print(
                    f"[FAIL] {index:02d} {code} status={response.status_code} "
                    f"body={response.text[:300]}"
                )
                continue

            payload = response.json()
            predictions = payload.get("predictions", [])
            if not predictions:
                failure += 1
                reason = extract_filter_reason(payload)
                if reason:
                    hint = get_filter_hint(reason)
                    print(f"[FAIL] {index:02d} {code} no predictions ({reason}){hint}")
                else:
                    print(f"[FAIL] {index:02d} {code} no predictions")
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
                reason = extract_filter_reason(payload)
                detail = reason or last_error or "No usable image found."
                hint = get_filter_hint(detail)
                print(f"[FAIL] {index:02d} {code} {detail}{hint}")
                continue

            out_file.write_bytes(img_bytes)
            generated_files.append(out_file)
            success += 1
            print(f"[OK]   {index:02d} {code} -> {out_file}")
        except Exception as exc:  # noqa: BLE001
            failure += 1
            print(f"[FAIL] {index:02d} {code} error={exc}")

        if args.sleep_sec > 0:
            time.sleep(args.sleep_sec)

    if generated_files and not args.no_normalize_framing:
        try:
            normalize_avatar_files(
                generated_files,
                content_ratio=args.content_ratio,
                white_threshold=args.white_threshold,
            )
            print(
                "[OK]   normalized framing "
                f"({len(generated_files)} files, target ratio={args.content_ratio:.2f})"
            )
        except Exception as exc:  # noqa: BLE001
            failure += 1
            print(f"[FAIL] framing normalization error={exc}")

    write_avatar_manifest(
        out_dir=out_dir,
        prompt_items_by_code=prompt_items_by_code,
        model=args.model,
    )
    print(f"[OK]   wrote manifest -> {AVATAR_MANIFEST_PATH}")

    print(f"Done. success={success} failure={failure}")
    return 0 if failure == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
