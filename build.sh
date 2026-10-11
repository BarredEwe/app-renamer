#!/bin/bash
# Builds build/AppRenamer.app (universal: arm64 + x86_64) and build/AppRenamer.zip.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-1.1.0}"
BUILD=build
APP="$BUILD/AppRenamer.app"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
    swiftc -O -parse-as-library -target "$arch-apple-macos14" \
        Sources/*.swift -o "$BUILD/AppRenamer-$arch"
done
lipo -create "$BUILD"/AppRenamer-{arm64,x86_64} -output "$APP/Contents/MacOS/AppRenamer"
rm "$BUILD"/AppRenamer-{arm64,x86_64}

# Icon: Resources/icon.png -> AppIcon.icns
ICONSET="$BUILD/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>AppRenamer</string>
  <key>CFBundleIdentifier</key><string>io.github.barredewe.apprenamer</string>
  <key>CFBundleName</key><string>App Renamer</string>
  <key>CFBundleDisplayName</key><string>App Renamer</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>ru</string></array>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --sign - "$APP"
ditto -c -k --keepParent "$APP" "$BUILD/AppRenamer.zip"
echo "Собрано: $(pwd)/$APP"
