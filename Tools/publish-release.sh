#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
[[ -z "$(git status --porcelain)" ]] || { print -u2 '먼저 저장소 변경을 커밋하세요.'; exit 1; }
python3 - <<'PY'
import json,subprocess,pathlib
m=json.loads(pathlib.Path('release/verified-release.json').read_text())
assert m['notarized'] is True
assert m['source_revision']==subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'Release source differs from current HEAD'
for report in ['app','dmg']:
 assert json.loads(pathlib.Path('release/notarization-'+report+'.json').read_text())['status']=='Accepted'
for filename in [m['dmg'],m['zip']]:assert pathlib.Path('release',filename).is_file()
PY
version=$(python3 -c 'import json;print(json.load(open("release/verified-release.json"))["version"])')
tag="v$version"
xcrun stapler validate "release/Mote-$version.dmg"
codesign --verify --strict "release/Mote-$version.dmg"
spctl --assess --type open --context context:primary-signature "release/Mote-$version.dmg"
git fetch origin main
git merge-base --is-ancestor HEAD origin/main || { print -u2 '먼저 main에 소스를 푸시하세요.'; exit 1; }
cat > release/release-notes.md <<EOF_NOTES
Mote $version — Codex Desktop companion for macOS.

- Requires macOS 14 or later; Apple Silicon and Intel.
- Developer ID signed, notarized by Apple, and tickets stapled.
- Open the DMG and drag Mote into Applications. Launch Codex Desktop before using Mote.
- Mote reads Codex local records; compatibility may change with Codex updates.

Checksums are provided in SHA256SUMS.txt.
EOF_NOTES
gh release create "$tag" "release/Mote-$version.dmg" "release/Mote-$version.zip" release/SHA256SUMS.txt --repo shinhanseo/mote --target "$(git rev-parse HEAD)" --title "Mote $version" --notes-file release/release-notes.md --latest
python3 Tools/enable-website-download.py release/verified-release.json
git add website/index.html website/README.md website/en/index.html
git commit -m "Enable website download for notarized Mote $version"
git push origin main
print '공개 릴리스와 웹 다운로드 연결 완료'
