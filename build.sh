#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p Mote.app/Contents/MacOS Mote.app/Contents/Resources
swiftc -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o Mote.app/Contents/MacOS/Mote -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
if [[ ! -f Resources/Mote.icns || Tools/GenerateIcon.swift -nt Resources/Mote.icns ]]; then
  icon_dir=$(mktemp -d)
  trap 'rm -rf "$icon_dir"' EXIT
  swiftc -parse-as-library Tools/GenerateIcon.swift -o "$icon_dir/generate" -framework AppKit
  "$icon_dir/generate" "$icon_dir/Mote.iconset"
  iconutil -c icns "$icon_dir/Mote.iconset" -o Resources/Mote.icns
fi
cp Resources/Mote.icns Mote.app/Contents/Resources/
cat > Mote.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.local.mote</string><key>CFBundleName</key><string>Mote</string><key>CFBundleIconFile</key><string>Mote</string><key>CFBundleExecutable</key><string>Mote</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.2.0</string><key>CFBundleVersion</key><string>2</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
PLIST
source_revision=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
/usr/libexec/PlistBuddy -c "Add :MoteSourceRevision string $source_revision" Mote.app/Contents/Info.plist
if [[ -n "${MOTE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MOTE_SIGN_IDENTITY" Mote.app
else
  codesign --force --sign - Mote.app
fi
