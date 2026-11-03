'use strict';
const english=document.documentElement.lang==='en';
try {
  const preferred=localStorage.getItem('mote.language');
  if(!english && (preferred==='en' || (!preferred && !navigator.language.toLowerCase().startsWith('ko')))) location.replace(new URL('en/'+location.hash,location.href));
}catch{}
document.querySelectorAll('[data-language]').forEach(link=>link.addEventListener('click',()=>{
  try{localStorage.setItem('mote.language',link.dataset.language);}catch{}
}));
const root=document.querySelector('.demo-stage');
const states=english ? {
 working:{title:'1 task<br>in progress.',menu:'Working 1',row:'web-app · Working · Last activity 12s ago',icon:'',spinner:true},
 approval:{title:'1 task needs<br>your approval.',menu:'Approval 1',row:'web-app · Command approval needed',icon:'!',reason:'Waiting 5m · Since detection',toast:'Mote · Approval needed'},
 answer:{title:'1 task needs<br>your reply.',menu:'Input 1',row:'web-app · Choose how to proceed',icon:'?',reason:'Waiting 5m · Since detection',toast:'Mote · Your reply is needed'},
 unread:{title:'1 unread<br>reply.',menu:'Unread 1',row:'web-app · Reply ready · Unread',icon:'✉',reason:'Read replies clear the indicator. Pinned chats stay.',toast:'Mote · A reply is ready'},
 batch:{title:'2 unread<br>replies.',menu:'Unread 2',row:'web-app · Reply ready · Unread',icon:'✉',reason:'Completed together · One notification',toast:'Mote · 2 tasks finished'},
 unknown:{title:'Unable to verify<br>the current status.',menu:'Check monitoring',row:'web-app · Last-known state: Working',icon:'?',reason:'Last record check 9:41 · Live status unavailable'},
 offline:{title:'Check your<br>network connection.',menu:'Check connection',row:'web-app · Last-known state: Working',icon:'?',reason:'Check Wi-Fi or Ethernet. This is not a confirmed task failure.'},
 idle:{title:'Resting<br>for now.',menu:'',row:'web-app · Done',icon:'✓'}
}: {
 working:{title:'1개 작업이<br>진행 중이에요.',menu:'진행 1',row:'web-app · 작업 중 · 마지막 활동 12초 전',icon:'',spinner:true},
 approval:{title:'1개 작업이<br>승인을 기다려요.',menu:'승인 1',row:'web-app · 명령 실행 승인 필요',icon:'!',reason:'기다린 지 5분 · 감지 시점 기준',toast:'모트 · 승인이 필요해요'},
 answer:{title:'1개 작업이<br>답변을 기다려요.',menu:'답변 1',row:'web-app · 진행 방식을 선택해 주세요',icon:'?',reason:'기다린 지 5분 · 감지 시점 기준',toast:'모트 · 답변을 기다려요'},
 unread:{title:'미확인 답변이<br>1개 있어요.',menu:'미확인 1',row:'web-app · 답변 도착 · 미확인',icon:'✉',reason:'읽으면 미확인 표시를 해제해요. 고정한 대화는 남아요.',toast:'모트 · 답변이 도착했어요'},
 batch:{title:'미확인 답변이<br>2개 있어요.',menu:'미확인 2',row:'web-app · 답변 도착 · 미확인',icon:'✉',reason:'함께 끝난 작업 · 알림은 한 번에',toast:'모트 · 작업 2개가 끝났어요'},
 unknown:{title:'작업 상태를<br>확인할 수 없어요.',menu:'감지 확인',row:'web-app · 마지막 기록: 작업 중',icon:'?',reason:'마지막 기록 확인 9:41 · 실시간 상태 확인 불가'},
 offline:{title:'네트워크 연결을<br>확인해 주세요.',menu:'연결 확인',row:'web-app · 마지막 기록: 작업 중',icon:'?',reason:'Wi-Fi·유선 연결을 확인해 주세요. 작업 실패로 단정하지 않아요.'},
 idle:{title:'지금은<br>쉬고 있어요.',menu:'',row:'web-app · 완료',icon:'✓'}
};
let toastTimer;
function renderDemo(name,announce=true){
 const state=states[name];if(!root || !state)return;
 const attention=['approval','answer','unread','batch'].includes(name),uncertain=['offline','unknown'].includes(name);
 root.dataset.state=name;
 document.getElementById('demo-headline').innerHTML=state.title;
 document.getElementById('menu-label').textContent=state.menu;
 document.getElementById('demo-row-status').textContent=state.row;
 const icon=document.getElementById('demo-status-icon');icon.classList.toggle('spinner',!!state.spinner);icon.textContent=state.icon;
 const reason=document.getElementById('request-reason');reason.hidden=!state.reason;reason.textContent=state.reason||'';
 const badge=document.getElementById('demo-badge');badge.hidden=!['approval','answer','offline','unknown'].includes(name);badge.textContent=name==='approval'?'!':'?';
 document.getElementById('demo-connection').textContent=english ? (name==='offline'?'● No network':name==='unknown'?'● Checking live connection':'● Connected'):(name==='offline'?'● 네트워크 없음':name==='unknown'?'● 실시간 연결 확인 중':'● 연결됨');
 document.getElementById('demo-summary').textContent=uncertain ? (english?'Status unavailable':'상태 확인 불가'):(english?'Needs attention '+(name==='batch'?2:attention?1:0)+' · Detected chats 2':'확인할 작업 '+(name==='batch'?2:attention?1:0)+' · 감지한 대화 2');
 document.getElementById('demo-list-label').textContent=attention ? (english?'Needs attention '+(name==='batch'?2:1):'지금 확인할 일 '+(name==='batch'?2:1)):(english?'Pinned chats 2':'고정한 대화 2');
 document.getElementById('demo-quiet-label').hidden=!attention || name==='batch';
 const second=document.getElementById('demo-second-row');second.classList.toggle('muted-row',name!=='batch');second.querySelector('.status-icon').textContent=name==='batch'?'✉':'✓';second.querySelector('small').textContent=name==='batch'?(english?'mac-app · Reply ready · Unread':'mac-app · 답변 도착 · 미확인'):(english?'mac-app · Done':'mac-app · 완료');
 clearTimeout(toastTimer);
 const toast=document.getElementById('demo-toast');toast.hidden=!state.toast;
 document.getElementById('toast-title').textContent=state.toast||'';
 toast.querySelector('small').textContent=name==='batch'?(english?'Sign-in screen · Settings':'로그인 화면 · 설정 화면'):(english?'Build the sign-in screen':'로그인 화면 구현');
 document.getElementById('toast-symbol').textContent=name==='approval'?'!':name==='answer'?'?':'✉';
 if(state.toast)toastTimer=setTimeout(()=>{toast.hidden=true;},10000);
 document.querySelectorAll('[data-demo]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.demo===name)));
 if(announce)document.getElementById('demo-announcement').textContent=state.title.replace(/<br>/g,' ')+' '+(state.reason||'');
}
document.querySelectorAll('[data-demo]').forEach(button=>button.addEventListener('click',()=>renderDemo(button.dataset.demo)));
renderDemo('working',false);
