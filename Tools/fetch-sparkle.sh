#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
[[ -d Vendor/Sparkle/Sparkle.framework ]] && exit 0
sparkle_tmp=$(mktemp -d)
trap 'rm -rf "$sparkle_tmp"' EXIT
curl -fL --retry 2 https://github.com/sparkle-project/Sparkle/releases/download/2.10.1/Sparkle-2.10.1.tar.xz -o "$sparkle_tmp/Sparkle.tar.xz"
print '1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27  '"$sparkle_tmp/Sparkle.tar.xz" | shasum -a 256 -c -
mkdir -p Vendor/Sparkle
tar -xf "$sparkle_tmp/Sparkle.tar.xz" -C Vendor/Sparkle
