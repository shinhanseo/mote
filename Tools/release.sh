#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
./Tools/release-preflight.sh
if [[ -z "${MOTE_SIGN_IDENTITY:-}" ]]; then
  export MOTE_SIGN_IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
fi
profile="${MOTE_NOTARY_PROFILE:-Mote}"
[[ -z "$(git status --porcelain --untracked-files=no)" ]] || { print -u2 '먼저 추적 중인 변경을 커밋하세요.'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Mote.app/Contents/Info.plist 2>/dev/null || echo 0.2.0)
mkdir -p release
stage=$(mktemp -d "$PWD/release/build.XXXXXX")
trap 'rm -rf "$stage"' EXIT
MOTE_ARCHS=universal MOTE_OUTPUT_DIR="$stage" ./build.sh
app="$stage/Mote.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
[[ "$(lipo -archs "$app/Contents/MacOS/Mote")" == *arm64* && "$(lipo -archs "$app/Contents/MacOS/Mote")" == *x86_64* ]] || exit 1
codesign --verify --strict "$app"
codesign -dv --verbose=4 "$app" 2>&1 | grep -Fq 'Authority=Developer ID Application:'
notarize() {
  local artifact="$1" output="$2"
  xcrun notarytool submit "$artifact" --keychain-profile "$profile" --wait --output-format json > "$output"
  python3 - "$output" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status')!='Accepted':
    raise SystemExit('Notarization not accepted. Inspect local report: '+sys.argv[1])
print('PASS: Apple notarization Accepted')
PY
}
ditto -c -k --keepParent "$app" "$stage/Mote-notarization.zip"
notarize "$stage/Mote-notarization.zip" "release/notarization-app.json"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose "$app"
mkdir -p "$stage/dmg"
ditto "$app" "$stage/dmg/Mote.app"
ln -s /Applications "$stage/dmg/Applications"
dmg="$PWD/release/Mote-$version.dmg"
[[ ! -e "$dmg" ]] || { print -u2 '이미 DMG가 존재합니다. 이전 파일을 다른 위치로 옮긴 후 실행하세요.'; exit 1; }
hdiutil create -volname Mote -srcfolder "$stage/dmg" -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$MOTE_SIGN_IDENTITY" "$dmg"
notarize "$dmg" "release/notarization-dmg.json"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose "$dmg"
ditto -c -k --keepParent "$app" "release/Mote-$version.zip"
(cd release && shasum -a 256 "Mote-$version.dmg" "Mote-$version.zip" > SHA256SUMS.txt)
python3 - "$version" <<'PY'
import json,subprocess,sys,pathlib
v=sys.argv[1]
manifest={'version':v,'tag':'v'+v,'source_revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'notarized':True,'architectures':['arm64','x86_64'],'dmg':'Mote-'+v+'.dmg','zip':'Mote-'+v+'.zip'}
pathlib.Path('release/verified-release.json').write_text(json.dumps(manifest,indent=2)+'\n')
PY
print "서명·공증 검증 완료: $dmg"
print 'Tools/publish-release.sh 로 GitHub 릴리스와 웹 다운로드를 공개할 수 있습니다.'
