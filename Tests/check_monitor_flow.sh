#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
python3 - "$test_dir/main.swift" <<'PY'
import pathlib,sys
source=pathlib.Path('Sources/main.swift').read_text().split('if CommandLine.arguments.contains("--diagnose")')[0]
pathlib.Path(sys.argv[1]).write_text(source+'\n'+pathlib.Path('Tests/monitor_flow.swift').read_text())
PY
mkdir -p "$test_dir/MoteTests.app/Contents/MacOS"
cat > "$test_dir/MoteTests.app/Contents/Info.plist" <<'PLIST'
<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>dev.local.mote.tests</string><key>CFBundleExecutable</key><string>MoteTests</string></dict></plist>
PLIST
other_sources=(Sources/*.swift)
other_sources=("${(@)other_sources:#Sources/main.swift}")
swiftc "$test_dir/main.swift" "${other_sources[@]}" -o "$test_dir/MoteTests.app/Contents/MacOS/MoteTests" -framework AppKit -framework SwiftUI -framework UserNotifications -lsqlite3
MOTE_TEST_SUITE="dev.local.mote.tests.$RANDOM.$RANDOM" "$test_dir/MoteTests.app/Contents/MacOS/MoteTests"
