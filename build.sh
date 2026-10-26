#!/bin/bash
# Builds "KWGS Radio.app" next to this script.
# Requires Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

APP="KWGS Radio.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O main.swift \
  -o "$APP/Contents/MacOS/KWGSRadio" \
  -framework Cocoa -framework AVFoundation -framework MediaPlayer

cp Info.plist "$APP/Contents/Info.plist"

# App icon: converts icon.png (any square image, ideally 1024x1024) into AppIcon.icns
if [ -f icon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -s format png -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -s format png -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

# Strip Finder/quarantine extended attributes (picked up when the source was
# downloaded and unzipped), which codesign rejects as "detritus"
xattr -cr "$APP"
codesign --force -s - "$APP"

# Bump the bundle's mtime and re-register it so Finder and the Dock drop any
# cached icon and pick up AppIcon.icns
touch "$APP"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Built: $(pwd)/$APP"
echo "Drag it to /Applications or run: open \"$APP\""
