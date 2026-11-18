#!/usr/bin/env python3
import os
from PIL import Image, ImageDraw

APP = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(APP, "tool/master_icon.png")

master = Image.open(SRC).convert("RGBA")
W, H = master.size

# 1. Prepare Android adaptive foreground (108dp canvas with safe zone 66dp)
# Scale the master down to 70% so all edges/tabs fit comfortably inside circular mask
scaled_size = int(W * 0.70)
scaled_master = master.resize((scaled_size, scaled_size), Image.LANCZOS)
# Foreground canvas MUST be transparent
fg_canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
offset = ((W - scaled_size) // 2, (H - scaled_size) // 2)
fg_canvas.paste(scaled_master, offset, scaled_master)

# 2. Prepare rounded squircle version for legacy launcher & desktop
rounded = master.copy()
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, W - 1, H - 1], radius=int(W * 0.20), fill=255)
rounded.putalpha(mask)

# 3. Prepare circular round version for round icon requests
circle_icon = master.copy()
circle_mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(circle_mask).ellipse([0, 0, W - 1, H - 1], fill=255)
circle_icon.putalpha(circle_mask)

def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)

# Update Android background color to #FFFFFF
bg_xml = os.path.join(APP, "android/app/src/main/res/values/ic_launcher_background.xml")
with open(bg_xml, "w") as f:
    f.write('<?xml version="1.0" encoding="utf-8"?>\n<resources>\n    <color name="ic_launcher_background">#FFFFFF</color>\n</resources>\n')

# Android mipmaps
ANDROID = os.path.join(APP, "android/app/src/main/res")
for density, px in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
    save(rounded, os.path.join(ANDROID, f"mipmap-{density}/ic_launcher.png"), px)
    save(circle_icon, os.path.join(ANDROID, f"mipmap-{density}/ic_launcher_round.png"), px)

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

# iOS AppIcon
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

# macOS AppIcon
MACOS = os.path.join(APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
for px in [16, 32, 64, 128, 256, 512, 1024]:
    save(rounded, os.path.join(MACOS, f"app_icon_{px}.png"), px)

# Windows .ico
rounded.save(
    os.path.join(APP, "windows/runner/resources/app_icon.ico"),
    sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

# Linux icons
LINUX = os.path.join(APP, "linux")
for px in [16, 32, 48, 64, 128, 256, 512]:
    save(rounded, os.path.join(LINUX, f"icons/{px}x{px}/apps/filemanager.png"), px)

print("All platform launcher icons successfully generated and applied!")
