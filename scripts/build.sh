#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${MACTV_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p .build dist
for arch in arm64 x86_64; do
  xcrun swiftc -parse-as-library -swift-version 5 -O -target "$arch-apple-macos14.0" -sdk "$sdk" \
    Sources/*.swift -o ".build/MacTVNative-$arch" \
    -framework AppKit -framework SwiftUI -framework AVKit -framework AVFoundation -framework WebKit -framework IOKit
done
app="dist/MacTV Native.app"
if [[ -d "$app" ]]; then mv "$app" ".build/previous-app-$(date +%Y%m%d%H%M%S)-$$.app"; fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp Resources/Info.plist "$app/Contents/Info.plist"
ditto Resources/Brand "$app/Contents/Resources/Brand"
ditto Resources/Bilibili "$app/Contents/Resources/Bilibili"
ditto Resources/Playback "$app/Contents/Resources/Playback"
xcrun swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
xcrun lipo -create .build/MacTVNative-arm64 .build/MacTVNative-x86_64 -output "$app/Contents/MacOS/MacTVNative"
codesign --force --sign - --identifier studio.machauncy.mactv.native "$app"
codesign --verify --strict "$app"
architectures="$(xcrun lipo "$app/Contents/MacOS/MacTVNative" -archs)"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
printf 'Built Universal 2: %s\n' "$app"
