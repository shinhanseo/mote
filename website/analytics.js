/* Mote website only. Never embedded in the Mac app. */
(()=>{
 'use strict';
 const id='G-XK24RFR4W6',key='mote.analytics.excluded';
 const settings=document.querySelector('[data-analytics-settings]');
 let excluded=true,storageAvailable=true;
 try{
  if(location.hash==='#exclude')localStorage.setItem(key,'1');
  if(location.hash==='#include')localStorage.removeItem(key);
  excluded=localStorage.getItem(key)==='1';
 }catch{storageAvailable=false;} // Fail closed if the preference cannot be read.
 const privacySignal=navigator.globalPrivacyControl===true||navigator.doNotTrack==='1';
 const production=location.hostname==='shinhanseo.github.io'&&location.pathname.startsWith('/mote/');
 const blocked=excluded||privacySignal||!production;
 window['ga-disable-'+id]=blocked;
 if(settings){
  const en=document.documentElement.lang==='en';
  const status=settings.querySelector('[data-analytics-status]');
  status.textContent=!storageAvailable?(en?'Browser storage is unavailable. Analytics is off.':'브라우저 저장소를 사용할 수 없어 통계 수집을 껐어요.'):excluded?(en?'This browser is excluded. No analytics script is loaded.':'이 브라우저는 집계에서 제외돼요. 분석 스크립트도 불러오지 않아요.'):privacySignal?(en?'Your browser privacy signal disables analytics.':'브라우저의 추적 방지 신호에 따라 집계하지 않아요.'):(en?'This browser is included in website analytics.':'이 브라우저는 홈페이지 통계에 포함돼요.');
  settings.querySelectorAll('[data-analytics-choice]').forEach(button=>button.addEventListener('click',()=>{
   location.hash=button.dataset.analyticsChoice==='exclude'?'exclude':'include';location.reload();
  }));
 }
 // Settings visits and language redirects are never counted.
 if(blocked||settings)return;
 if(document.documentElement.lang==='ko'){
  try{const p=localStorage.getItem('mote.language');if(p==='en'||(!p&&!navigator.language.toLowerCase().startsWith('ko')))return;}catch{return;}
 }
 // Strip arbitrary queries/fragments. Only public campaign tags are forwarded.
 const page=new URL(location.origin+location.pathname);
 const query=new URLSearchParams(location.search);
 for(const k of ['utm_source','utm_medium','utm_campaign']){
  const v=query.get(k);if(v&&/^[a-zA-Z0-9_.-]{1,80}$/.test(v))page.searchParams.set(k,v);
 }
 let referrer='';try{referrer=new URL(document.referrer).origin+'/';}catch{}
 window.dataLayer=window.dataLayer||[];
 const gtag=function(){window.dataLayer.push(arguments);};
 gtag('consent','default',{analytics_storage:'granted',ad_storage:'denied',ad_user_data:'denied',ad_personalization:'denied'});
 gtag('js',new Date());
 gtag('config',id,{send_page_view:true,page_location:page.href,page_referrer:referrer,allow_google_signals:false,allow_ad_personalization_signals:false,cookie_path:'/mote/',cookie_expires:60*60*24*90});
 const tag=document.createElement('script');tag.async=true;tag.src='https://www.googletagmanager.com/gtag/js?id='+id;document.head.appendChild(tag);
 document.addEventListener('click',event=>{
  const link=event.target.closest?.('a[href]');if(!link)return;
  let url;try{url=new URL(link.href);}catch{return;}
  if(url.hostname!=='github.com'||!/^\/shinhanseo\/mote\/releases\/download\/[^/]+\/Mote-[\d.]+\.dmg$/.test(url.pathname))return;
  // Clicks indicate download intent, not successful installation or unique users.
  gtag('event','download_click',{file_name:url.pathname.split('/').pop(),file_extension:'dmg',link_url:url.origin+url.pathname,button_location:link.closest('.hero')?'hero':link.closest('#start')?'install':'other',language:document.documentElement.lang,transport_type:'beacon'});
 });
})();
