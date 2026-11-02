import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const script=readFileSync(new URL('../website/analytics.js',import.meta.url),'utf8');
function run({exclude=false,hash='',dnt=false,local=false,broken=false}={}){
 const saved=new Map(exclude?[['mote.analytics.excluded','1']]:[]),tags=[],listeners={};
 const location={hostname:local?'localhost':'shinhanseo.github.io',pathname:'/mote/',origin:'https://shinhanseo.github.io',hash,search:'?token=secret&utm_source=syde',reload(){}};
 const ctx={URL,URLSearchParams,Date,location,navigator:{language:'ko',doNotTrack:dnt?'1':'0'},window:{},localStorage:{getItem(k){if(broken)throw Error();return saved.get(k)||null},setItem(k,v){saved.set(k,v)},removeItem(k){saved.delete(k)}},document:{querySelector(){return null},documentElement:{lang:'ko'},referrer:'https://news.hada.io/topic?id=123',head:{appendChild(x){tags.push(x)}},createElement(){return {}},addEventListener(k,v){listeners[k]=v}}};
 vm.runInNewContext(script,ctx);return {ctx,saved,tags,listeners,events:ctx.window.dataLayer||[]};
}
for(const options of [{exclude:true},{hash:'#exclude'},{dnt:true},{local:true},{broken:true}]){const r=run(options);assert.equal(r.tags.length,0);assert.equal(r.events.length,0);assert.equal(r.ctx.window['ga-disable-G-XK24RFR4W6'],true)}
const r=run();assert.equal(r.tags.length,1);
const config=r.events.find(e=>e[0]==='config')[2];assert.equal(config.page_location,'https://shinhanseo.github.io/mote/?utm_source=syde');assert.equal(config.page_referrer,'https://news.hada.io/');assert.equal(config.allow_google_signals,false);
function click(href){r.listeners.click({target:{closest(){return {href,closest(selector){return selector==='.hero'?{}:null}}}}})}
click('https://github.com/shinhanseo/mote/releases/download/v0.4.1/Mote-0.4.1.dmg');assert.equal(r.events.filter(e=>e[0]==='event'&&e[1]==='download_click').length,1);
click('https://example.com/Mote-0.4.1.dmg');click('https://github.com/shinhanseo/mote');assert.equal(r.events.filter(e=>e[0]==='event').length,1);
assert.equal(run({exclude:true,hash:'#include'}).tags.length,1);
console.log('PASS: owner exclusion, DNT, localhost, storage failure, sanitized attribution, DMG click, opt-in');
