'use strict';
const english=document.documentElement.lang==='en';
try {
  const preferred=localStorage.getItem('mote.language');
  if(!english && (preferred==='en' || (!preferred && !navigator.language.toLowerCase().startsWith('ko')))) location.replace(new URL('en/'+location.hash,location.href));
}catch{}

const root = document.querySelector('.demo-stage');
const states = {
  working: { title:'2개 작업이<br>진행 중이에요.', menu:'진행 2', row:'web-app · 작업 중', icon:'', spinner:true, reason:null, announcement:'모트가 작업 중인 상태입니다.' },
  approval: { title:'1개 작업이<br>승인을 기다려요.', menu:'진행 1 · 대기 1', row:'web-app · 승인 대기', icon:'!', spinner:false, reason:'명령 실행 승인이 필요해요. 실제 승인은 Codex에서 직접 합니다.', announcement:'승인이 필요해 요정이 손을 흔듭니다.' },
  unread: { title:'미확인 답변이<br>1개 있어요.', menu:'답변 1', row:'web-app · 답변 도착 · 미확인', icon:'✉', spinner:false, reason:'읽은 답변은 미확인 표시가 해제돼요. 작업 대화는 그대로 남아요.', announcement:'읽지 않은 답변이 도착해 편지를 표시합니다.' },
  idle: { title:'지금은<br>쉬고 있어요.', menu:'', row:'web-app · 완료', icon:'✓', spinner:false, reason:null, announcement:'작업을 마치고 쉬고 있습니다.' }
};
if(english) Object.assign(states,{
 working:{title:'2 tasks<br>in progress.',menu:'Working 2',row:'web-app · Working',icon:'',spinner:true,reason:null,announcement:'Mote is working.'},
 approval:{title:'1 task needs<br>your approval.',menu:'Working 1 · Waiting 1',row:'web-app · Approval needed',icon:'!',spinner:false,reason:'Command approval needed. Approve in Codex yourself.',announcement:'Approval needed.'},
 unread:{title:'1 unread<br>reply.',menu:'Unread 1',row:'web-app · Reply ready · Unread',icon:'✉',spinner:false,reason:'Read replies clear the unread indicator. Pinned chats stay in your list.',announcement:'A reply is ready.'},
 idle:{title:'Resting<br>for now.',menu:'',row:'web-app · Done',icon:'✓',spinner:false,reason:null,announcement:'Mote is resting.'}
});
Object.assign(states,english ? {
 answer:{title:'1 task needs<br>your reply.',menu:'Input 1',row:'web-app · Choose how to proceed',icon:'?',spinner:false,reason:'Waiting 5m · Since detection',announcement:'Your input is needed.'},
 offline:{title:'Check your<br>network connection.',menu:'Status unavailable',row:'web-app · Working · Check progress',icon:'⌁',spinner:false,reason:'No network path. Check Wi-Fi or Ethernet.',announcement:'Network path unavailable.'}
}: {
 answer:{title:'1개 작업이<br>답변을 기다려요.',menu:'답변 대기 1',row:'web-app · 진행 방식을 선택해 주세요',icon:'?',spinner:false,reason:'기다린 지 5분 · 감지 시점 기준',announcement:'입력이 필요합니다.'},
 offline:{title:'네트워크 연결을<br>확인해 주세요.',menu:'상태 확인 불가',row:'web-app · 작업 중 · 진행 확인 필요',icon:'⌁',spinner:false,reason:'네트워크 경로가 없어요. Wi-Fi·유선 연결을 확인해 주세요.',announcement:'네트워크 경로가 없습니다.'}
});
states.working.row=english?'web-app · Working · Last activity 12s ago':'web-app · 작업 중 · 마지막 활동 12초 전';
states.approval.row=english?'web-app · Command approval needed':'web-app · 명령 실행 승인 필요';
states.approval.reason=english?'Waiting 5m · Since detection':'기다린 지 5분 · 감지 시점 기준';
document.querySelectorAll('[data-demo]').forEach(button=>button.addEventListener('click',()=>{
  const name=button.dataset.demo;const state=states[name];if(!state)return;
  root.dataset.state=name;
  const badge=document.getElementById('demo-badge');badge.hidden=!['approval','answer','offline'].includes(name);badge.textContent=name==='approval'?'!':name==='answer'?'?':'⌁';
  document.getElementById('demo-headline').innerHTML=state.title;
  document.getElementById('menu-label').textContent=state.menu;
  document.getElementById('demo-summary').textContent=name==='offline' ? (english?'Status unavailable':'상태 확인 불가'):(english?'Needs attention '+(['approval','answer','unread'].includes(name)?1:0)+' · Detected chats 2':'확인할 작업 '+(['approval','answer','unread'].includes(name)?1:0)+' · 감지한 대화 2');
  document.getElementById('demo-connection').textContent=name==='offline' ? (english?'● No network':'● 네트워크 없음'):(english?'● Connected':'● 연결됨');
  document.getElementById('demo-row-status').textContent=state.row;
  const icon=document.getElementById('demo-status-icon');icon.classList.toggle('spinner',state.spinner);icon.textContent=state.icon;
  const reason=document.getElementById('request-reason');reason.hidden=!state.reason;reason.textContent=state.reason||'';
  document.querySelectorAll('[data-demo]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
  document.getElementById('demo-announcement').textContent=state.announcement;
}));

// Explicit language links work without JavaScript; preference is an enhancement.
document.querySelectorAll('[data-language]').forEach(link=>link.addEventListener('click',()=>{
  try{localStorage.setItem('mote.language',link.dataset.language);}catch{}
}));

// Illustrative alerts share the same state switch as the panel.
document.querySelectorAll('[data-demo]').forEach(button=>button.addEventListener('click',()=>{
 const name=button.dataset.demo;
 const titles=english ? {approval:'Mote · Approval needed',answer:'Mote · Your reply is needed',unread:'Mote · A reply is ready'} : {approval:'모트 · 승인이 필요해요',answer:'모트 · 답변을 기다려요',unread:'모트 · 답변이 도착했어요'};
 const toast=document.getElementById('demo-toast');
 toast.hidden=!titles[name];
 document.getElementById('toast-title').textContent=titles[name]||'';
 document.getElementById('toast-symbol').textContent=name==='approval'?'!':name==='answer'?'?':'✉';
}));
