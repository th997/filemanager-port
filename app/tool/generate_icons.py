#!/usr/bin/env python3
"""Generate every platform launcher icon from one drawn master.

Run from the app directory: `python3 tool/generate_icons.py`.

The mark is a white two-panel folder on a blue gradient; it is drawn at
2048px and downsampled so the 48px launcher stays legible.
"""

import os
from PIL import Image, ImageDraw, ImageFilter

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
S = 2048
TOP = (66, 165, 245)
BOTTOM = (21, 101, 192)
FLAT_BG = (33, 150, 243)


def gradient(size):
    img = Image.new("RGB", (size, size))
    draw = ImageDraw.Draw(img)
    for y in range(size):
        t = y / (size - 1)
        draw.line(
            [(0, y), (size, y)],
            fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)),
        )
    return img


def folder(size, scale, shadow=True):
    """White folder glyph on a transparent canvas, centered."""
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    w = size * scale
    cx = size / 2
    left = cx - w * 0.40
    right = cx + w * 0.40
    tab_w = w * 0.34
    tab_top = size / 2 - w * 0.30
    body_top = tab_top + w * 0.10
    body_bottom = size / 2 + w * 0.30
    radius = w * 0.06

    if shadow:
        sh = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        off = w * 0.035
        ImageDraw.Draw(sh).rounded_rectangle(
            [left + off, body_top + off, right + off, body_bottom + off],
            radius=radius,
            fill=(0, 0, 0, 70),
        )
        layer = Image.alpha_composite(layer, sh.filter(ImageFilter.GaussianBlur(w * 0.03)))

    draw = ImageDraw.Draw(layer)
    back = (214, 232, 250, 255)
    draw.rounded_rectangle(
        [left, tab_top, left + tab_w, body_top + w * 0.06], radius=radius, fill=back
    )
    draw.rounded_rectangle([left, body_top, right, body_bottom], radius=radius, fill=back)
    draw.rounded_rectangle(
        [left, body_top + w * 0.13, right, body_bottom],
        radius=radius,
        fill=(255, 255, 255, 255),
    )
    return layer


def square(size, rounded=0.0, folder_scale=0.62):
    base = gradient(size).convert("RGBA")
    if rounded > 0:
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, size - 1, size - 1], radius=int(size * rounded), fill=255
        )
        base.putalpha(mask)
    return Image.alpha_composite(base, folder(size, folder_scale))


def save(image, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path)


master = square(S)
rounded = square(S, rounded=0.22)
# Adaptive foreground: glyph only, sized to the 66dp safe zone of a 108dp canvas.
foreground = folder(S, 0.58)

# Android legacy launcher icons.
ANDROID = os.path.join(APP, "android/app/src/main/res")
for density, px in [
    ("mdpi", 48),
    ("hdpi", 72),
    ("xhdpi", 96),
    ("xxhdpi", 144),
    ("xxxhdpi", 192),
]:
    save(rounded, os.path.join(ANDROID, f"mipmap-{density}/ic_launcher.png"), px)

# Android adaptive icon (API 26+): glyph over a flat background color.
for density, px in [
    ("mdpi", 108),
    ("hdpi", 162),
    ("xhdpi", 216),
    ("xxhdpi", 324),
    ("xxxhdpi", 432),
]:
    save(
        foreground,
        os.path.join(ANDROID, f"mipmap-{density}/ic_launcher_foreground.png"),
        px,
    )

# iOS uses full-bleed square art; the system applies the rounded mask.
IOS = os.path.join(APP, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
for name, px in [
    ("Icon-App-20x20@1x.png", 20),
    ("Icon-App-20x20@2x.png", 40),
    ("Icon-App-20x20@3x.png", 60),
    ("Icon-App-29x29@1x.png", 29),
    ("Icon-App-29x29@2x.png", 58),
    ("Icon-App-29x29@3x.png", 87),
    ("Icon-App-40x40@1x.png", 40),
    ("Icon-App-40x40@2x.png", 80),
    ("Icon-App-40x40@3x.png", 120),
    ("Icon-App-60x60@2x.png", 120),
    ("Icon-App-60x60@3x.png", 180),
    ("Icon-App-76x76@1x.png", 76),
    ("Icon-App-76x76@2x.png", 152),
    ("Icon-App-83.5x83.5@2x.png", 167),
    ("Icon-App-1024x1024@1x.png", 1024),
]:
    save(master.convert("RGB"), os.path.join(IOS, name), px)

# macOS gets the pre-rounded shape, matching Big Sur icon conventions.
MACOS = os.path.join(APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
for px in [16, 32, 64, 128, 256, 512, 1024]:
    save(rounded, os.path.join(MACOS, f"app_icon_{px}.png"), px)

# Windows .ico with the sizes Explorer asks for.
rounded.save(
    os.path.join(APP, "windows/runner/resources/app_icon.ico"),
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

# Linux: hicolor theme icons plus a desktop entry installed by CMake.
LINUX = os.path.join(APP, "linux")
for px in [16, 32, 48, 64, 128, 256, 512]:
    save(rounded, os.path.join(LINUX, f"icons/{px}x{px}/apps/filemanager.png"), px)

print("icons written")
