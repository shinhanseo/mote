#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
: "${MOTE_SIGN_IDENTITY:?Set a Developer ID Application certificate identity first}"
: "${MOTE_NOTARY_PROFILE:?Set an existing notarytool Keychain profile first}"
./build.sh
codesign --verify --strict Mote.app
mkdir -p release
ditto -c -k --keepParent Mote.app release/Mote-notarization.zip
xcrun notarytool submit release/Mote-notarization.zip --keychain-profile "$MOTE_NOTARY_PROFILE" --wait
xcrun stapler staple Mote.app
xcrun stapler validate Mote.app
spctl --assess --type execute --verbose Mote.app
ditto -c -k --keepParent Mote.app release/Mote-0.2.0.zip
