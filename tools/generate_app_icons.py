#!/usr/bin/env python3
"""Generate iOS and Android app icons from the tracked source icon."""

from __future__ import annotations

import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SOURCE_ICON = ROOT / "assets" / "app_icon" / "story_bible_icon.png"
OPAQUE_ICON = ROOT / "assets" / "app_icon" / "story_bible_icon_opaque.png"
FALLBACK_SOURCE_ICON = ROOT / "story_bible_icon.png"

IOS_ICONS = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}

ANDROID_ICONS = {
    "mipmap-mdpi/ic_launcher.png": 48,
    "mipmap-hdpi/ic_launcher.png": 72,
    "mipmap-xhdpi/ic_launcher.png": 96,
    "mipmap-xxhdpi/ic_launcher.png": 144,
    "mipmap-xxxhdpi/ic_launcher.png": 192,
}


def ensure_source_icon() -> Path:
    SOURCE_ICON.parent.mkdir(parents=True, exist_ok=True)
    if SOURCE_ICON.exists():
        return SOURCE_ICON
    if FALLBACK_SOURCE_ICON.exists():
        shutil.copy2(FALLBACK_SOURCE_ICON, SOURCE_ICON)
        return SOURCE_ICON
    raise SystemExit(
        "Source icon not found. Expected " f"{SOURCE_ICON} or {FALLBACK_SOURCE_ICON}."
    )


def sample_background_color(image: Image.Image) -> tuple[int, int, int]:
    width, height = image.size
    center_x = (width - 1) / 2
    center_y = (height - 1) / 2
    seeds = [
        (0, 0),
        (width - 1, 0),
        (0, height - 1),
        (width - 1, height - 1),
        (width // 2, 0),
        (width // 2, height - 1),
        (0, height // 2),
        (width - 1, height // 2),
    ]
    samples: list[tuple[int, int, int]] = []

    for start_x, start_y in seeds:
        steps = int(max(abs(center_x - start_x), abs(center_y - start_y)))
        for step in range(steps + 1):
            progress = 0 if steps == 0 else step / steps
            x = round(start_x + (center_x - start_x) * progress)
            y = round(start_y + (center_y - start_y) * progress)
            red, green, blue, alpha = image.getpixel((x, y))
            if alpha >= 220:
                samples.append((red, green, blue))
                break

    if not samples:
        return (27, 26, 59)

    red = round(sum(sample[0] for sample in samples) / len(samples))
    green = round(sum(sample[1] for sample in samples) / len(samples))
    blue = round(sum(sample[2] for sample in samples) / len(samples))
    return (red, green, blue)


def save_resized(image: Image.Image, size: int, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    resized = image.resize((size, size), Image.Resampling.LANCZOS)
    resized.save(output_path, format="PNG", optimize=True)


def main() -> None:
    source_icon = ensure_source_icon()
    source_image = Image.open(source_icon).convert("RGBA")
    background = sample_background_color(source_image)

    opaque_base = Image.new("RGBA", source_image.size, background + (255,))
    opaque_base.alpha_composite(source_image)
    opaque_rgb = opaque_base.convert("RGB")
    opaque_rgb.save(OPAQUE_ICON, format="PNG", optimize=True)

    ios_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in IOS_ICONS.items():
        save_resized(opaque_rgb, size, ios_dir / filename)

    android_dir = ROOT / "android" / "app" / "src" / "main" / "res"
    for relative_path, size in ANDROID_ICONS.items():
        save_resized(opaque_rgb, size, android_dir / relative_path)

    print(f"Source icon: {source_icon}")
    print(f"Opaque icon: {OPAQUE_ICON}")
    print(f"Background color: rgb{background}")
    print("Updated iOS AppIcon.appiconset and Android mipmap launcher icons.")


if __name__ == "__main__":
    main()
