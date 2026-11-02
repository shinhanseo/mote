#!/bin/zsh
set -eu
cd "$(dirname "$0")"
./Tools/fetch-sparkle.sh
app_path="${MOTE_OUTPUT_DIR:-.}/Mote.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
if [[ "${MOTE_ARCHS:-native}" == universal ]]; then
  arch_dir=$(mktemp -d)
  trap 'rm -rf "$arch_dir"' EXIT
  for arch in arm64 x86_64; do
    swiftc -target "$arch-apple-macos14.0" Sources/*.swift -o "$arch_dir/Mote-$arch" -F Vendor/Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
  done
  lipo -create "$arch_dir/Mote-arm64" "$arch_dir/Mote-x86_64" -output "$app_path/Contents/MacOS/Mote"
else
  swiftc -target "$(uname -m)-apple-macos14.0" Sources/*.swift -o "$app_path/Contents/MacOS/Mote" -F Vendor/Sparkle -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
fi
mkdir -p "$app_path/Contents/Frameworks"
ditto Vendor/Sparkle/Sparkle.framework "$app_path/Contents/Frameworks/Sparkle.framework"
if [[ ! -f Resources/Mote.icns || Tools/GenerateIcon.swift -nt Resources/Mote.icns ]]; then
  icon_dir=$(mktemp -d)
  trap 'rm -rf "$icon_dir"; [[ -z "${arch_dir:-}" ]] || rm -rf "$arch_dir"' EXIT
  swiftc -parse-as-library Tools/GenerateIcon.swift -o "$icon_dir/generate" -framework AppKit
  "$icon_dir/generate" "$icon_dir/Mote.iconset"
  iconutil -c icns "$icon_dir/Mote.iconset" -o Resources/Mote.icns
fi
cp Resources/Mote.icns "$app_path/Contents/Resources/"
cp website/assets/mote-dust-soft.svg website/assets/mote-dust-sleep*.svg "$app_path/Contents/Resources/"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.local.mote</string><key>CFBundleName</key><string>Mote</string><key>CFBundleIconFile</key><string>Mote</string><key>CFBundleExecutable</key><string>Mote</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleShortVersionString</key><string>0.4.1</string><key>CFBundleVersion</key><string>6</string><key>CFBundleDevelopmentRegion</key><string>en</string><key>CFBundleLocalizations</key><array><string>ko</string><string>en</string></array><key>SUFeedURL</key><string>https://shinhanseo.github.io/mote/appcast.xml</string><key>SUPublicEDKey</key><string>ubD49dy51z67xs3d8xz8yfKe1K+1kQhMMJkIx5zL2Do=</string><key>SUEnableAutomaticChecks</key><false/><key>SUAutomaticallyUpdate</key><false/><key>SUEnableInstallerLauncherService</key><true/><key>SUVerifyUpdateBeforeExtraction</key><true/><key>SURequireSignedFeed</key><true/><key>LSUIElement</key><true/><key>NSHighResolutionCapable</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
PLIST
source_revision=$(git rev-parse HEAD 2>/dev/null || echo unknown)
/usr/libexec/PlistBuddy -c "Add :MoteSourceRevision string $source_revision" "$app_path/Contents/Info.plist"
signer=$(printenv MOTE_SIGN_IDENTITY || true)
[[ -n "$signer" ]] || signer=-
framework="$app_path/Contents/Frameworks/Sparkle.framework"
for nested in "$framework/Versions/B/Autoupdate" "$framework/Versions/B/Updater.app" "$framework/Versions/B/XPCServices/Downloader.xpc" "$framework/Versions/B/XPCServices/Installer.xpc" "$framework"; do
  if [[ "$signer" == - ]]; then
    codesign --force --sign - "$nested"
  else
    codesign --force --options runtime --timestamp --sign "$signer" "$nested"
  fi
done
if [[ -n "${MOTE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$MOTE_SIGN_IDENTITY" "$app_path"
else
  codesign --force --sign - "$app_path"
fi
