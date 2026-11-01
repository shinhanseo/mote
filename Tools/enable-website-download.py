#!/usr/bin/env python3
"""Enable the public CTA only after a verified notarized release has been published."""
import json,pathlib,re,sys
root=pathlib.Path(__file__).resolve().parents[1]
manifest=json.loads(pathlib.Path(sys.argv[1]).read_text())
assert manifest.get('notarized') is True
version=manifest['version']; assert re.fullmatch(r'\d+\.\d+\.\d+',version)
assert set(manifest['architectures'])=={'arm64','x86_64'}
url=f'https://github.com/shinhanseo/mote/releases/download/v{version}/Mote-{version}.dmg'
p=root/'website/index.html';s=p.read_text()
old='<a class="button dark" href="#demo">모트 만나보기 <span aria-hidden="true">↓</span></a>'
new=f'<a class="button dark" href="{url}">Mac용 다운로드 <span aria-hidden="true">↓</span></a>'
assert old in s,'Download CTA already changed; review the website before updating another release'
s=s.replace(old,new)
s=s.replace('macOS 14+ · Codex Desktop 전용 · 로컬 중심','macOS 14+ · Apple Silicon / Intel · Codex Desktop 전용')
s=s.replace('모트는 지금 직접 쓰며 다듬고 있는 개발 버전이에요.<br>먼저 살펴보고, 함께 더 편하게 만들어가요.','모트를 내려받고 응용 프로그램 폴더로 옮겨주세요.<br>Codex를 켜면 작은 동료가 작업을 챙기기 시작해요.')
s=s.replace('DEVELOPER PREVIEW · 0.2.0',f'MAC APP · {version}')
s=s.replace('<h3>지금은 GitHub에서</h3>','<h3>Mac에서 바로 시작하기</h3>')
s=s.replace('소스를 내려받아 Mac에서 직접 빌드할 수 있어요.<br>설치 방법과 현재 지원 범위를 함께 안내합니다.','DMG를 열고 Mote를 응용 프로그램 폴더로 옮겨주세요.<br>Codex Desktop이 설치되어 있어야 해요.')
s=s.replace('<a class="button dark" href="https://github.com/shinhanseo/mote#run" target="_blank" rel="noopener">설치 안내 보기 <span aria-hidden="true">↗</span></a>',new)
s=s.replace('macOS 14+ · Xcode 명령줄 도구 필요','macOS 14+ · Apple Silicon / Intel')
s=s.replace('편하게 설치하는 버전은 준비 중','설치 전에 확인해 주세요').replace('배포용 서명과 공증을 마치면<br>여기서 바로 내려받을 수 있게 할게요.','Developer ID로 서명하고 Apple 공증을 마쳤어요.<br>버전별 변경 내용과 소스는 GitHub에서 확인하세요.').replace('공식 다운로드 준비 중','서명·공증 완료').replace('현재 일반 사용자용 공증 배포본은 제공하지 않습니다.','Codex 업데이트에 따라 감지 기능의 대응이 필요할 수 있어요.')
p.write_text(s)
p=root/'website/README.md';s=p.read_text();s+=f'\nPublic notarized download: {url}\n';p.write_text(s)
print('Website download CTA updated for verified version',version)
