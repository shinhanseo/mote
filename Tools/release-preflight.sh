#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
identity="${MOTE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)
fi
if [[ "$identity" != 'Developer ID Application:'* ]]; then
  print -u2 '배포용 Developer ID Application 인증서와 개인 키가 필요합니다. Xcode → Settings → Accounts → Manage Certificates에서 발급하세요.'
  exit 1
fi
security find-identity -v -p codesigning | grep -Fq -- "\"$identity\"" || { print -u2 '선택한 인증서의 사용 가능한 개인 키를 찾지 못했습니다.'; exit 1; }
profile="${MOTE_NOTARY_PROFILE:-Mote}"
xcrun notarytool history --keychain-profile "$profile" >/dev/null || { print -u2 '공증 인증이 필요합니다. 터미널에서 xcrun notarytool store-credentials Mote 를 실행하세요.'; exit 1; }
print 'PASS: Developer ID signing identity and notarization authentication available'
