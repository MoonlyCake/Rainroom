#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
resource_path="$PWD"
if [[ $# -gt 0 ]]; then
    resource_path="$(cd "$1" && pwd)"
fi
app="$PWD/build/雨间.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/module-cache
swiftc -parse-as-library -O -target arm64-apple-macosx14.0 -module-cache-path build/module-cache -framework SwiftUI -framework AppKit -framework AVFoundation AudioPlayer.swift Rainroom.swift Theme.swift -o "$app/Contents/MacOS/Rainroom"
cp Info.plist "$app/Contents/Info.plist"
if [[ $# -gt 0 ]]; then
    cp -R "$resource_path/." "$app/Contents/Resources/"
else
    cp AppIcon.icns Tracks.json "$app/Contents/Resources/"
fi
codesign --force --sign - "$app"
codesign --verify --deep --strict "$app"
print "构建完成：$app"
