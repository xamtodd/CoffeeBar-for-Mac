#!/bin/bash
# Baut KaffeeBar.app und installiert sie nach ~/Applications
set -euo pipefail
cd "$(dirname "$0")"

APP="KaffeeBar.app"
swift build -c release

rm -rf "build/$APP"
mkdir -p "build/$APP/Contents/MacOS"
cp .build/release/KaffeeBar "build/$APP/Contents/MacOS/"
cp Info.plist "build/$APP/Contents/"

# App-Icon: Resources/AppIcon.png (1024px) → AppIcon.icns
mkdir -p "build/$APP/Contents/Resources" build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out build/AppIcon.iconset/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns build/AppIcon.iconset -o "build/$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "build/$APP"

mkdir -p ~/Applications
pkill -x KaffeeBar 2>/dev/null || true
rm -rf ~/Applications/"$APP"
cp -R "build/$APP" ~/Applications/
open ~/Applications/"$APP"
echo "✅ Installiert: ~/Applications/$APP"
