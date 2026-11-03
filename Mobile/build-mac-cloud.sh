#!/bin/zsh
# Provisioned owner-only Mac test build. Public release remains CloudKit-disabled.
set -eu
cd "$(dirname "$0")/.."
: "${MOTE_CLOUD_PROFILE:?Set MOTE_CLOUD_PROFILE to a profile authorizing dev.local.mote and iCloud.im.mote.companion}"
: "${MOTE_CLOUD_IDENTITY:?Set MOTE_CLOUD_IDENTITY to the matching code signing identity}"
: "${MOTE_OUTPUT_DIR:?Use an isolated output folder}"
./build.sh
python3 - <<'PY'
import os,plistlib,pathlib,subprocess,shutil
profile=pathlib.Path(os.environ['MOTE_CLOUD_PROFILE'])
data=plistlib.loads(subprocess.check_output(['security','cms','-D','-i',str(profile)]))
e=data['Entitlements']
assert e.get('com.apple.application-identifier',e.get('application-identifier'))=='2RQKCF6Z9C.dev.local.mote'
assert 'iCloud.im.mote.companion' in e.get('com.apple.developer.icloud-container-identifiers',[])
allowed=e.get('com.apple.developer.icloud-container-environment',[])
assert allowed=='Production' or 'Production' in allowed
e['com.apple.developer.icloud-container-environment']='Production'
app=pathlib.Path(os.environ['MOTE_OUTPUT_DIR'])/'Mote.app'
p=app/'Contents/Info.plist';info=plistlib.loads(p.read_bytes());info['MoteCloudKitEnabled']=True;p.write_bytes(plistlib.dumps(info))
shutil.copy(profile,app/'Contents/embedded.provisionprofile')
entitlements=pathlib.Path(os.environ['MOTE_OUTPUT_DIR'])/'cloud.entitlements';entitlements.write_bytes(plistlib.dumps(e))
subprocess.run(['codesign','--force','--sign',os.environ['MOTE_CLOUD_IDENTITY'],'--entitlements',str(entitlements),str(app)],check=True)
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
PY
