#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./Tools/fetch-sparkle.sh
python3 - <<'PY'
import json,pathlib
m=json.loads(pathlib.Path('release/verified-release.json').read_text())
assert m['notarized'] is True
for name in ['app','dmg']:
 assert json.loads(pathlib.Path('release/notarization-'+name+'.json').read_text())['status']=='Accepted'
PY
version=$(python3 -c 'import json;print(json.load(open("release/verified-release.json"))["version"])')
feed_dir=$(mktemp -d "$PWD/release/feed.XXXXXX")
trap 'rm -rf "$feed_dir"' EXIT
cp "release/Mote-$version.dmg" "$feed_dir/"
Vendor/Sparkle/bin/generate_appcast --download-url-prefix "https://github.com/shinhanseo/mote/releases/download/v$version/" --maximum-deltas 0 --link https://shinhanseo.github.io/mote/ -o "$feed_dir/appcast.xml" "$feed_dir"
Vendor/Sparkle/bin/sign_update --verify "$feed_dir/appcast.xml"
cp "$feed_dir/appcast.xml" release/appcast.xml
