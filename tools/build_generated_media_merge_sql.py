#!/usr/bin/env python3
"""Build idempotent SQL upserts from generated media manifests."""

from __future__ import annotations

import argparse
import json
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class AssetRecord:
    owner_type: str
    owner_code: str
    asset_role: str
    variant: str
    scene_index: int | None
    relative_path: str | None
    source_relative_path: str | None
    generator: str | None
    generator_model: str | None
    generated_at: str | None
    metadata: dict[str, Any]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Build generated media merge SQL from JSON manifests.",
    )
    parser.add_argument(
        "--avatars-manifest",
        default="supabase/generated_media/avatars.json",
        help="Avatar manifest path.",
    )
    parser.add_argument(
        "--story-scenes-manifest",
        default="supabase/generated_media/story_scenes.json",
        help="Story scene manifest path.",
    )
    parser.add_argument(
        "--output",
        default="supabase/generated_media/generated_media_merge.sql",
        help="SQL output path.",
    )
    return parser.parse_args()


def sql_value(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    text = str(value).replace("'", "''")
    return f"'{text}'"


def load_manifest(path: Path) -> list[AssetRecord]:
    if not path.exists():
        return []

    data = json.loads(path.read_text(encoding="utf-8"))
    assets = data.get("assets", [])
    if not isinstance(assets, list):
        raise ValueError(f"Invalid manifest format: {path}")

    records: list[AssetRecord] = []
    for item in assets:
        if not isinstance(item, dict):
            continue
        owner_type = str(item.get("owner_type") or "").strip()
        owner_code = str(item.get("owner_code") or "").strip()
        asset_role = str(item.get("asset_role") or "").strip()
        variant = str(item.get("variant") or "").strip()
        if not owner_type or not owner_code or not asset_role or not variant:
            continue

        raw_scene_index = item.get("scene_index")
        scene_index = int(raw_scene_index) if isinstance(raw_scene_index, int) else None
        metadata = item.get("metadata")
        records.append(
            AssetRecord(
                owner_type=owner_type,
                owner_code=owner_code,
                asset_role=asset_role,
                variant=variant,
                scene_index=scene_index,
                relative_path=_clean_optional_text(item.get("relative_path")),
                source_relative_path=_clean_optional_text(
                    item.get("source_relative_path")
                ),
                generator=_clean_optional_text(item.get("generator")),
                generator_model=_clean_optional_text(item.get("generator_model")),
                generated_at=_clean_optional_text(item.get("generated_at")),
                metadata=metadata if isinstance(metadata, dict) else {},
            )
        )
    return records


def _clean_optional_text(value: Any) -> str | None:
    text = str(value).strip() if value is not None else ""
    return text or None


def render_person_rows(records: list[AssetRecord]) -> list[tuple[str, str | None, str | None, str | None, str | None, str | None, str]]:
    by_code: dict[str, dict[str, AssetRecord]] = defaultdict(dict)
    for record in records:
        if record.owner_type != "person" or record.asset_role != "avatar":
            continue
        by_code[record.owner_code][record.variant] = record

    rows = []
    for owner_code in sorted(by_code):
        variants = by_code[owner_code]
        original = variants.get("original")
        thumbnail = variants.get("thumbnail")
        preferred = thumbnail or original
        if preferred is None:
            continue
        rows.append(
            (
                owner_code,
                original.relative_path if original else None,
                thumbnail.relative_path if thumbnail else None,
                preferred.generator,
                preferred.generator_model,
                preferred.generated_at,
                json.dumps(_merge_metadata(original, thumbnail), ensure_ascii=False),
            )
        )
    return rows


def render_scene_rows(
    records: list[AssetRecord],
) -> list[tuple[str, int, str | None, str | None, str | None, str | None, str | None, str | None, str]]:
    by_key: dict[tuple[str, int], dict[str, AssetRecord]] = defaultdict(dict)
    for record in records:
        if record.owner_type != "event" or record.asset_role != "story_scene":
            continue
        if record.scene_index is None:
            continue
        by_key[(record.owner_code, record.scene_index)][record.variant] = record

    rows = []
    for (owner_code, scene_index) in sorted(by_key):
        variants = by_key[(owner_code, scene_index)]
        original = variants.get("original")
        thumbnail = variants.get("thumbnail")
        preferred = thumbnail or original
        if preferred is None:
            continue
        rows.append(
            (
                owner_code,
                scene_index,
                original.relative_path if original else None,
                thumbnail.relative_path if thumbnail else None,
                (
                    str(original.metadata.get("scene_prompt") or "").strip()
                    if original is not None
                    else None
                )
                or None,
                preferred.generator,
                preferred.generator_model,
                preferred.generated_at,
                json.dumps(_merge_metadata(original, thumbnail), ensure_ascii=False),
            )
        )
    return rows


def _merge_metadata(original: AssetRecord | None, thumbnail: AssetRecord | None) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    if original is not None:
        merged["original"] = original.metadata
    if thumbnail is not None:
        merged["thumbnail"] = thumbnail.metadata
    return merged


def render_values(rows: list[tuple[Any, ...]]) -> str:
    return ",\n".join(
        f"  ({', '.join(sql_value(value) for value in row)})" for row in rows
    )


def parent_dir(path: str | None) -> str | None:
    if not path:
        return None
    return str(Path(path).parent).replace("\\", "/")


def build_sql(
    person_rows: list[
        tuple[str, str | None, str | None, str | None, str | None, str | None, str]
    ],
    scene_rows: list[
        tuple[
            str,
            int,
            str | None,
            str | None,
            str | None,
            str | None,
            str | None,
            str | None,
            str,
        ]
    ],
) -> str:
    lines = [
        "-- Generated by tools/build_generated_media_merge_sql.py",
        "begin;",
        "",
    ]

    if person_rows:
        lines.extend(
            [
                "with avatar_rows (person_code, original_path, thumbnail_path, generator, generator_model, generated_at, metadata) as (",
                "values",
                render_values(person_rows),
                ")",
                "insert into public.person_generated_assets (",
                "  person_id, original_path, thumbnail_path, status, generator, generator_model, generated_at, metadata",
                ")",
                "select",
                "  p.id,",
                "  a.original_path,",
                "  a.thumbnail_path,",
                "  'ready',",
                "  a.generator,",
                "  a.generator_model,",
                "  a.generated_at::timestamptz,",
                "  a.metadata::jsonb",
                "from avatar_rows a",
                "join public.persons p on p.code = a.person_code",
                "on conflict (person_id) do update set",
                "  original_path = excluded.original_path,",
                "  thumbnail_path = excluded.thumbnail_path,",
                "  status = excluded.status,",
                "  generator = excluded.generator,",
                "  generator_model = excluded.generator_model,",
                "  generated_at = excluded.generated_at,",
                "  metadata = excluded.metadata;",
                "",
                "with avatar_rows (person_code, original_path, thumbnail_path) as (",
                "values",
                render_values([row[:3] for row in person_rows]),
                ")",
                "update public.persons p",
                "set",
                "  avatar_url = coalesce(a.original_path, p.avatar_url),",
                "  avatar_thumb_url = coalesce(a.thumbnail_path, p.avatar_thumb_url)",
                "from avatar_rows a",
                "where p.code = a.person_code;",
                "",
            ]
        )
    else:
        lines.append("-- No avatar manifest rows found.")
        lines.append("")

    if scene_rows:
        lines.extend(
            [
                "with scene_rows (event_code, scene_index, original_path, thumbnail_path, prompt_text, generator, generator_model, generated_at, metadata) as (",
                "values",
                render_values(scene_rows),
                ")",
                "insert into public.event_scene_generated_assets (",
                "  event_id, scene_index, original_path, thumbnail_path, status, prompt_text, generator, generator_model, generated_at, metadata",
                ")",
                "select",
                "  e.id,",
                "  s.scene_index,",
                "  s.original_path,",
                "  s.thumbnail_path,",
                "  'ready',",
                "  s.prompt_text,",
                "  s.generator,",
                "  s.generator_model,",
                "  s.generated_at::timestamptz,",
                "  s.metadata::jsonb",
                "from scene_rows s",
                "join public.events e on e.code = s.event_code",
                "on conflict (event_id, scene_index) do update set",
                "  original_path = excluded.original_path,",
                "  thumbnail_path = excluded.thumbnail_path,",
                "  status = excluded.status,",
                "  generator = excluded.generator,",
                "  generator_model = excluded.generator_model,",
                "  generated_at = excluded.generated_at,",
                "  metadata = excluded.metadata;",
                "",
            ]
        )

        event_rollups: list[tuple[str, str | None, str | None, int, str | None]] = []
        by_event: dict[
            str,
            list[
                tuple[
                    str,
                    int,
                    str | None,
                    str | None,
                    str | None,
                    str | None,
                    str | None,
                    str | None,
                    str,
                ]
            ],
        ] = defaultdict(list)
        for row in scene_rows:
            by_event[row[0]].append(row)
        for event_code in sorted(by_event):
            rows = sorted(by_event[event_code], key=lambda row: row[1])
            story_asset_dir = parent_dir(rows[0][2])
            story_thumbnail_dir = parent_dir(rows[0][3])
            story_scene_count = max(row[1] for row in rows)
            cover_thumb = rows[0][3] or rows[0][2]
            event_rollups.append(
                (
                    event_code,
                    story_asset_dir,
                    story_thumbnail_dir,
                    story_scene_count,
                    cover_thumb,
                )
            )
        lines.extend(
            [
                "with event_rollups (event_code, story_asset_dir, story_thumbnail_dir, story_scene_count, thumb_url) as (",
                "values",
                render_values(event_rollups),
                ")",
                "update public.events e",
                "set",
                "  story_asset_dir = r.story_asset_dir,",
                "  story_thumbnail_dir = r.story_thumbnail_dir,",
                "  story_scene_count = r.story_scene_count,",
                "  thumb_url = coalesce(r.thumb_url, e.thumb_url)",
                "from event_rollups r",
                "where e.code = r.event_code;",
                "",
            ]
        )
    else:
        lines.append("-- No story-scene manifest rows found.")
        lines.append("")

    lines.append("commit;")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    args = parse_args()
    avatar_records = load_manifest(Path(args.avatars_manifest))
    scene_records = load_manifest(Path(args.story_scenes_manifest))
    person_rows = render_person_rows(avatar_records)
    scene_rows = render_scene_rows(scene_records)
    sql = build_sql(person_rows, scene_rows)

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(sql, encoding="utf-8")

    print(f"avatar rows : {len(person_rows)}")
    print(f"scene rows  : {len(scene_rows)}")
    print(f"output      : {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
