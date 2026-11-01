import json,pathlib,shutil,subprocess,tempfile
root=pathlib.Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
 p=pathlib.Path(directory);(p/'Tools').mkdir();(p/'website').mkdir()
 shutil.copy(root/'Tools/enable-website-download.py',p/'Tools')
 for name in ['index.html','README.md']:shutil.copy(root/'website'/name,p/'website'/name)
 original=(p/'website/index.html').read_text()
 manifest={'version':'0.2.0','notarized':False,'architectures':['arm64','x86_64']}
 (p/'manifest.json').write_text(json.dumps(manifest))
 result=subprocess.run(['python3',str(p/'Tools/enable-website-download.py'),str(p/'manifest.json')],capture_output=True)
 assert result.returncode!=0 and (p/'website/index.html').read_text()==original
 manifest['notarized']=True;(p/'manifest.json').write_text(json.dumps(manifest))
 subprocess.run(['python3',str(p/'Tools/enable-website-download.py'),str(p/'manifest.json')],check=True)
 page=(p/'website/index.html').read_text()
 assert 'releases/download/v0.2.0/Mote-0.2.0.dmg' in page
 assert '공식 다운로드 준비 중' not in page
 print('PASS: unverified downloads rejected; verified release links generated in isolated copy')
