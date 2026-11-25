#!/usr/bin/env python3
import os
import numpy as np
from PIL import Image, ImageFilter

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(APP, "tool/master_icon.png")

master = Image.open(SRC).convert("RGBA")
W, H = master.size

# Soft cool gray-blue tones (Gboard / Material-style off-white surface)
BG_TOP = (236, 241, 247)      # #ECF1F7
BG_BOTTOM = (222, 230, 240)   # #DEE6F0
BG_SOLID_HEX = "#E6EDF5"


def make_gradient_bg(size, top_rgb, bot_rgb):
    arr = np.zeros((size, size, 4), dtype=np.uint8)
    t_arr = np.linspace(0.0, 1.0, size)[:, None]
    for c in range(3):
        arr[:, :, c] = np.round(top_rgb[c] * (1.0 - t_arr) + bot_rgb[c] * t_arr).astype(np.uint8)
    arr[:, :, 3] = 255
    return Image.fromarray(arr, mode="RGBA")


def add_soft_shadow(canvas_size, fg_img, offset, blur_radius=14, opacity=0.14, y_shift=10):
    alpha = fg_img.split()[3]
    sh_layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    sh_fg = Image.new("RGBA", fg_img.size, (15, 35, 65, 255))
    sh_fg.putalpha(alpha.point(lambda p: int(p * opacity)))
    sh_layer.paste(sh_fg, (offset[0], offset[1] + y_shift), sh_fg)
    return sh_layer.filter(ImageFilter.GaussianBlur(blur_radius))


# 1. Prepare Android adaptive foreground (108dp canvas with safe zone 66dp)
# Scale the full-bleed master to 58% so corners fit comfortably inside circular mask
scaled_size = int(W * 0.58)
scaled_master = master.resize((scaled_size, scaled_size), Image.LANCZOS)
fg_offset = ((W - scaled_size) // 2, (H - scaled_size) // 2)
fg_canvas = add_soft_shadow(W, scaled_master, fg_offset, blur_radius=10, opacity=0.12, y_shift=8)
fg_canvas.paste(scaled_master, fg_offset, scaled_master)

# 2. Prepare iOS opaque RGB master (Gboard-style soft cool gray-blue backdrop)
ios_size = int(W * 0.92)
ios_scaled = master.resize((ios_size, ios_size), Image.LANCZOS)
ios_offset = ((W - ios_size) // 2, (H - ios_size) // 2)
ios_master = make_gradient_bg(W, BG_TOP, BG_BOTTOM)
ios_shadow = add_soft_shadow(W, ios_scaled, ios_offset, blur_radius=14, opacity=0.14, y_shift=10)
ios_master = Image.alpha_composite(ios_master, ios_shadow)
ios_master.paste(ios_scaled, ios_offset, ios_scaled)
ios_rgb = ios_master.convert("RGB")

def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)

# Update Android adaptive background color to soft cool gray-blue
bg_xml = os.path.join(APP, "android/app/src/main/res/values/ic_launcher_background.xml")
with open(bg_xml, "w") as f:
    f.write(f'<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">{BG_SOLID_HEX}</color>\n</resources>\n')

# Android mipmaps
ANDROID = os.path.join(APP, "android/app/src/main/res")
for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    save(master, os.path.join(ANDROID, f"mipmap-{density}/ic_launcher.png"), px)
    save(master, os.path.join(ANDROID, f"mipmap-{density}/ic_launcher_round.png"), px)

for density, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
    save(fg_canvas, os.path.join(ANDROID, f"mipmap-{density}/ic_launcher_foreground.png"), px)

# Adaptive round icon xml
round_xml = os.path.join(ANDROID, "mipmap-anydpi-v26/ic_launcher_round.xml")
with open(round_xml, "w") as f:
    f.write('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')

# iOS AppIcon (opaque RGB on white background)
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
    save(ios_rgb, os.path.join(IOS, name), px)

# macOS AppIcon (transparent background preserved)
MACOS = os.path.join(APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
for px in [16, 32, 64, 128, 256, 512, 1024]:
    save(master, os.path.join(MACOS, f"app_icon_{px}.png"), px)

# Windows .ico (transparent background preserved)
master.save(
    os.path.join(APP, "windows/runner/resources/app_icon.ico"),
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

# Linux icons (transparent background preserved)
LINUX = os.path.join(APP, "linux")
for px in [16, 32, 48, 64, 128, 256, 512]:
    save(master, os.path.join(LINUX, f"icons/{px}x{px}/apps/filemanager.png"), px)

print("All platform launcher icons successfully generated and applied!")
