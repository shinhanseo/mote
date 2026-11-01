#!/bin/zsh
set -eu
cd "$(dirname "$0")"
mkdir -p Mote.app/Contents/MacOS
swiftc Sources/*.swift -o Mote.app/Contents/MacOS/Mote -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
cat > Mote.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.local.mote</string><key>CFBundleName</key><string>Mote</string><key>CFBundleExecutable</key><string>Mote</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.1.0</string><key>CFBundleVersion</key><string>1</string><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
PLIST
codesign --force --sign - Mote.app
