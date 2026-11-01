#!/bin/zsh
set -eu
cd "$(dirname "$0")"
app_path="${MOTE_OUTPUT_DIR:-.}/Mote.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "${MOTE_ARCHS:-native}" == universal ]]; then
  arch_dir=$(mktemp -d)
  trap 'rm -rf "$arch_dir"' EXIT
  for arch in arm64 x86_64; do
    swiftc -target "$arch-apple-macos14.0" Sources/*.swift -o "$arch_dir/Mote-$arch" -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
  done
  lipo -create "$arch_dir/Mote-arm64" "$arch_dir/Mote-x86_64" -output "$app_path/Contents/MacOS/Mote"
else
  swiftc -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$app_path/Contents/MacOS/Mote" -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
fi
if [[ ! -f Resources/Mote.icns || Tools/GenerateIcon.swift -nt Resources/Mote.icns ]]; then
  icon_dir=$(mktemp -d)
  trap 'rm -rf "$icon_dir"; [[ -z "${arch_dir:-}" ]] || rm -rf "$arch_dir"' EXIT
  swiftc -parse-as-library Tools/GenerateIcon.swift -o "$icon_dir/generate" -framework AppKit
  "$icon_dir/generate" "$icon_dir/Mote.iconset"
  iconutil -c icns "$icon_dir/Mote.iconset" -o Resources/Mote.icns
fi
cp Resources/Mote.icns "$app_path/Contents/Resources/"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.local.mote</string><key>CFBundleName</key><string>Mote</string><key>CFBundleIconFile</key><string>Mote</string><key>CFBundleExecutable</key><string>Mote</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.2.0</string><key>CFBundleVersion</key><string>2</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
PLIST
source_revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)
/usr/libexec/PlistBuddy -c "Add :MoteSourceRevision string $source_revision" "$app_path/Contents/Info.plist"
if [[ -n "${MOTE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MOTE_SIGN_IDENTITY" "$app_path"
else
  codesign --force --sign - "$app_path"
fi
