'use strict';
const root = document.querySelector('.demo-stage');
const states = {
  working: { title:'2개 작업이<br>진행 중이에요.', menu:'진행 2', row:'web-app · 작업 중', icon:'', spinner:true, reason:null, announcement:'모트가 작업 중인 상태입니다.' },
  approval: { title:'1개 작업이<br>승인을 기다려요.', menu:'진행 1 · 대기 1', row:'web-app · 승인 대기', icon:'!', spinner:false, reason:'명령 실행 승인이 필요해요. 실제 승인은 Codex에서 직접 합니다.', announcement:'승인이 필요해 요정이 손을 흔듭니다.' },
  unread: { title:'미확인 답변이<br>1개 있어요.', menu:'답변 1', row:'web-app · 답변 도착 · 미확인', icon:'✉', spinner:false, reason:'읽은 답변은 미확인 표시가 해제돼요. 작업 대화는 그대로 남아요.', announcement:'읽지 않은 답변이 도착해 편지를 표시합니다.' },
  idle: { title:'지금은<br>쉬고 있어요.', menu:'', row:'web-app · 완료', icon:'✓', spinner:false, reason:null, announcement:'작업을 마치고 쉬고 있습니다.' }
};
document.querySelectorAll('[data-demo]').forEach(button=>button.addEventListener('click',()=>{
  const name=button.dataset.demo;const state=states[name];if(!state)return;
  root.dataset.state=name;
  document.getElementById('demo-headline').innerHTML=state.title;
  document.getElementById('menu-label').textContent=state.menu;
  document.getElementById('demo-summary').textContent=state.menu||'모두 확인했어요';
  document.getElementById('demo-row-status').textContent=state.row;
  const icon=document.getElementById('demo-status-icon');icon.classList.toggle('spinner',state.spinner);icon.textContent=state.icon;
  const reason=document.getElementById('request-reason');reason.hidden=!state.reason;reason.textContent=state.reason||'';
  document.querySelectorAll('[data-demo]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
  document.getElementById('demo-announcement').textContent=state.announcement;
}));
