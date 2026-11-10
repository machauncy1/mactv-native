#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
sdk="${MACTV_SDK:-$(xcrun --show-sdk-path)}"
mkdir -p .build dist
cargo_bin="${CARGO:-cargo}"
command -v "$cargo_bin" >/dev/null || { printf 'Rust cargo is required to build the iPhone receiver.\n' >&2; exit 1; }
for target in aarch64-apple-darwin x86_64-apple-darwin; do
  "$cargo_bin" build --locked --release --manifest-path RemoteReceiver/Cargo.toml --target "$target"
done
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
xcrun lipo -create RemoteReceiver/target/aarch64-apple-darwin/release/mactv-remote-receiver RemoteReceiver/target/x86_64-apple-darwin/release/mactv-remote-receiver -output "$app/Contents/MacOS/MacTVRemoteReceiver"
mkdir -p "$app/Contents/Resources/ThirdParty"
cp RemoteReceiver/UPSTREAM.md "$app/Contents/Resources/ThirdParty/atv-core.md"
codesign --force --sign - --identifier studio.machauncy.mactv.remote "$app/Contents/MacOS/MacTVRemoteReceiver"
codesign --force --sign - --identifier studio.machauncy.mactv.native "$app"
codesign --verify --deep --strict "$app"
architectures="$(xcrun lipo "$app/Contents/MacOS/MacTVNative" -archs)"
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
receiver_architectures="$(xcrun lipo "$app/Contents/MacOS/MacTVRemoteReceiver" -archs)"
[[ "$receiver_architectures" == *arm64* && "$receiver_architectures" == *x86_64* ]]
printf 'Built Universal 2: %s\n' "$app"
