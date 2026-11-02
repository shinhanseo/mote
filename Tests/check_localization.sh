#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
localization_dir=$(mktemp -d)
trap 'rm -rf "$localization_dir"' EXIT
cp Tests/localization.swift "$localization_dir/main.swift"
swiftc Sources/Localizations.swift "$localization_dir/main.swift" -o "$localization_dir/check"
MOTE_TEST_SUITE="dev.local.mote.l10n.$RANDOM" "$localization_dir/check"
