#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
cp Tests/live_state.swift "$test_dir/main.swift"
swiftc Sources/LiveObserver.swift Sources/NotificationPolicy.swift "$test_dir/main.swift" -o "$test_dir/check"
"$test_dir/check"
