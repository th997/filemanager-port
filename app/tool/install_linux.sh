#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Building FP File Manager (Linux Release) ==="
cd "$APP_DIR"
flutter build linux --release

BUNDLE_DIR="$APP_DIR/build/linux/x64/release/bundle"
TARGET_DIR="${HOME}/.local/share/filemanager"
BIN_DIR="${HOME}/.local/bin"
APP_DIR_USER="${HOME}/.local/share/applications"
ICON_BASE="${HOME}/.local/share/icons/hicolor"

echo "=== Installing to $TARGET_DIR ==="
rm -rf "$TARGET_DIR"
cp -a "$BUNDLE_DIR" "$TARGET_DIR"

echo "=== Creating symlink in $BIN_DIR/filemanager ==="
mkdir -p "$BIN_DIR"
ln -sf "$TARGET_DIR/filemanager" "$BIN_DIR/filemanager"

echo "=== Installing Desktop Entry ==="
mkdir -p "$APP_DIR_USER"
cp -a "$APP_DIR/linux/com.github.th997.filemanager.desktop" "$APP_DIR_USER/"

echo "=== Installing High-Resolution Icons ==="
for size in 16 32 48 64 128 256 512; do
  mkdir -p "$ICON_BASE/${size}x${size}/apps"
  cp -a "$APP_DIR/linux/icons/${size}x${size}/apps/filemanager.png" "$ICON_BASE/${size}x${size}/apps/"
done

echo "=== Updating Desktop and Icon Databases ==="
update-desktop-database "$APP_DIR_USER" 2>/dev/null || true
gtk-update-icon-cache -f -t "$ICON_BASE" 2>/dev/null || true

echo "=== Done! You can run 'filemanager' from terminal or find 'FP File Manager' in your Application Menu / Open With. ==="
