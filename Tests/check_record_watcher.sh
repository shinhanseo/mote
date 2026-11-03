#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp Tests/record_watcher.swift "$test_dir/main.swift"
swiftc Sources/RecordWatcher.swift "$test_dir/main.swift" -o "$test_dir/check"
"$test_dir/check"
