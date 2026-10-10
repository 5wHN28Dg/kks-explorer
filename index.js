// The drawings page (index.html). A file of its own, not an inline script, so the Content-Security-Policy can
// allow scripts from this site only (#8).
const $=s=>document.querySelector(s);
let SHEETS=[],BASE_TAGS=[],TAGS=[],PROCS=[],KKS={},LOC={},DESC={},LOCSRC='location list',STATE={equipment:{},reviews:{},photos:[],links:[],mine:[]};
let cur=null, view={s:1,x:0,y:0}, selId=null, linkTarget=null, activeProc=null, floor='', PDV='';
const api=u=>K.api(u);
// Views are built as elements (K.h: text as text nodes, handlers as functions), never as markup.
const h=K.h;
// el's children := these (arrays flattened; null, undefined and false left out)
const put=(el,...kids)=>el.replaceChildren(...kids.flat(Infinity).filter(c=>c!=null&&c!==false));
function toast(t){const e=$('#toast');e.textContent=t;e.style.display='block';clearTimeout(e._t);e._t=setTimeout(()=>e.style.display='none',2200)}

// effective tag = extracted tag + your review decision
function eff(t){
  const r=STATE.reviews[t.id];
  if(r){ if(r.status==='rejected') return null; return {...t,kks:r.kks,isa:r.isa||null,suffix:r.suffix||'',status:'confirmed'} }
  if(t.status==='review') return {...t,kks:t.kks||null};
  return t;
}
const full=t=>(t.kks||'')+(t.suffix||'');
const tagsOf=sid=>TAGS.filter(t=>t.sheet===sid).map(eff).filter(Boolean);
const eq=k=>STATE.equipment[k]||{};

// location list (data/locations.json from 'KKS LOCATION HRSG.pdf'): keyed by KKS without the unit number and suffix
const lvlName=l=>{ const m=(l||'').match(/^(\d+(?:\.\d+)?)\s*m$/i); return m?(+m[1])+' m':/out/i.test(l||'')?'Outside HRSG':(l||'') };
function refLoc(b){ // one value per field, or '' when the list contradicts itself
  const L=LOC[b]||[], one=f=>{ const v=[...new Set(L.map(f).filter(Boolean))]; return v.length===1?v[0]:'' };
  return {rows:L, elev:one(e=>lvlName(e.level)), cabinet:one(e=>e.cabinet)};
}
const bodyOf=t=>(t.kks||'').slice(2);
// floors are numbers 0–10 set by people (the location list only knows elevations in metres: see elevOf)
const floorOf=t=>(eq(full(t)).floor||'').trim();
const floorName=f=>/^\d+$/.test(f)?'Floor '+f:f;
const elevOf=t=>(eq(full(t)).elev||'').trim()||refLoc(bodyOf(t)).elev;
function locSec(b,sfx){
  const L=LOC[b]||[]; if(!L.length) return null;
  const conflict=new Set(L.map(r=>[r.level,r.cabinet,r.desc,r.direction].join('|'))).size>1;
  return h('div',{class:'sec'},h('h3',null,'Location list',sfx?[' ',h('span',{style:'font-weight:400'},`(listed as ${b}, without suffix ${sfx})`)]:null),
    conflict?h('div',{class:'warn'},`Listed ${L.length} times with different values — check on site.`):null,
    L.map(r=>h('dl',{style:'margin-bottom:6px'},h('dt',null,'Level'),h('dd',null,lvlName(r.level)),
      r.cabinet?[h('dt',null,'Cabinet'),h('dd',{class:'mono'},r.cabinet)]:null,r.desc?[h('dt',null,'Description'),h('dd',null,r.desc)]:null,
      r.direction?[h('dt',null,'Direction'),h('dd',null,r.direction)]:null,h('dt',null,'Source'),h('dd',{class:'sub'},`${LOCSRC}, page ${r.page}`))));
}
const closeX=()=>h('button',{class:'x',onclick:()=>closePanel(),'aria-label':'Close the panel'},'×');
function selectLoc(b){
  selId=null; selTag=null; drawTags();
  put($('#panelBody'),h('div',{class:'phead'},h('div',{style:'flex:1'},h('div',{class:'kks',tabindex:'-1',role:'heading','aria-level':'2'},b),
      h('div',{class:'sub'},KKS.components[b.slice(5,7)]||'')),closeX()),
    h('div',{class:'sec'},h('div',{class:'warn'},'In the location list but not found on any loaded drawing: on a sheet not loaded yet, misread by the tag reader, or mistyped in the list.')),
    locSec(b));
  $('#panel').classList.add('open'); $('#panel').scrollTop=0;
  if(focusPanel){ focusPanel=false; $('#panelBody .phead .kks')?.focus() }
}

async function load(){
  const me=await K.start(); K.toast=toast;
  $('#who').textContent=me.user.full_name||me.user.username; $('#plantName').textContent=K.cfg?.plant_name?'· '+K.cfg.plant_name:'';
  try{
    // procedures are optional: a plant may not have published its operation manual (yet)
    [SHEETS,BASE_TAGS,PROCS,KKS]=await Promise.all(['data/sheets.json','data/tags.json','data/procedures.json','data/kks.json'].map(u=>fetch(u).then(r=>{
      if(r.status===404&&u.endsWith('procedures.json')) return [];
      if(!r.ok)throw new Error(u+': '+r.status);return r.json()})));
  }catch(e){
    // no drawings here yet: they come by sync once the manager has published them (PROTOCOL-v2.md §19)
    const pd=await api('/api/sync/status').then(s=>s.plant_data).catch(()=>null);
    const msg=!K.online?'You are offline and this device has no saved copy of the plant data. Offline copies need the app opened over HTTPS (or localhost) at least once while online.'
      :pd&&pd.version?`The drawings (version ${pd.version}) are on their way: ${pd.missing} file${pd.missing===1?'':'s'}, ${(pd.missing_bytes/1048576).toFixed(1)} MB left. They arrive with the next sync; this page opens by itself.`
      :pd?'No drawings yet. The manager publishes them (Manage → Drawings on the server, or kks-server publish-data); they reach this device by sync, and this page opens by itself.'
      :e.message;
    K.box(pd?'Waiting for the drawings':'Plant data not available',msg,'Retry',()=>location.reload());
    if(pd){ K.onChange(why=>{ if(why==='plantdata') location.reload() }); K.watchChanges() }
    return }
  if(SHEETS.some(s=>s.levels)){   // offline: the version this device last saw (the saved drawings carry it in their URLs)
    const pd=(await api('/api/sync/status').catch(()=>null))?.plant_data;
    if(pd){ PDV=String(pd.active??''); K.idb.set('pdv',PDV).catch(()=>{}) } else PDV=(await K.idb.get('pdv').catch(()=>null))||'' }
  try{ STATE={mine:[],...await api('/api/state')} }catch(e){ if(e.status===401) return location.reload(); toast('Offline: no saved copy of notes/photos on this device yet') }
  mergeTags();
  // drafted descriptions (optional plant data; core model.parseDescriptions): code -> {text, basis}
  DESC=await fetch('data/descriptions.json').then(r=>r.ok?r.json():{}).catch(()=>({})); DESC=parseDesc(DESC);
  const lj=await fetch('data/locations.json').then(r=>r.ok?r.json():{entries:[]}).catch(()=>({entries:[]}));
  for(const e of lj.entries)(LOC[e.kks]??=[]).push(e); if(lj.source) LOCSRC=lj.source;
  K.onChange(why=>{
    if(why==='plantdata'){   // new drawings/tag lists published: load them, unless the person is typing in the panel
      const P=$('#panel'); if(P.contains(document.activeElement)||P.querySelector('.editing')) toast('New drawings arrived: they load the next time you open this page'); else location.reload();
      return }
    if(why==='synced') refreshState(); else { updatePending(); if(cur) drawTags() } });
  updateQueueBadge(); setTimeout(cacheSheets,3000);
  if(K.cfg?.mode==='peer'&&!K.cfg?.app) api('/api/update').then(u=>{   // once per new version (M5b)
    if(u.available&&!u.staged&&localStorage.getItem('updSeen')!==u.latest){ localStorage.setItem('updSeen',u.latest); toast(`Walkdown ${u.latest} is out: Manage → Updates to install it`) } }).catch(()=>{});
  put($('#sheetSel'),SHEETS.map(s=>h('option',{value:s.id},s.name)));
  refreshFloors(); refreshReviewCount(); renderProcs();
  const want=new URLSearchParams(location.search).get('sheet')||localStorage.getItem('sheet');  // ?sheet=id from Manage → Drawings
  const wantK=(new URLSearchParams(location.search).get('kks')||'').toUpperCase().replace(/\s+/g,'');  // ?kks= from a course link
  const wantT=new URLSearchParams(location.search).get('tag');   // ?tag=id from Manage → Approvals (a tag without a code)
  const hitK=wantK&&TAGS.find(t=>full(t)===wantK||t.kks===wantK)||wantT&&TAGS.find(t=>t.id===wantT);
  if(hitK){ goTo(hitK.id); history.replaceState(null,'',location.pathname); return }
  openSheet(SHEETS.find(s=>s.id===want)?want:SHEETS[0].id);
  if(wantK){ $('#q').value=wantK; $('#q').dispatchEvent(new Event('input')); $('#q').focus() }
}

// ---------- tags marked by hand (approved ones live in the DB, not tags.json, so they survive re-imports) ----------
function mergeTags(){
  TAGS=BASE_TAGS.concat((STATE.added_tags||[]).map(a=>({id:'u:'+a.id, sheet:a.sheet, kks:a.kks, suffix:a.suffix||'', isa:a.isa,
    kind:a.kind, status:a.kks?'verified':'review', conf:1, bbox:a.bbox, orient:a.orient, read:['',''], note:a.note||'',
    flag:'', suggestion:null, added:a.id})));
}
const mark={on:false,start:null,box:null};
function markMode(on){
  if(on) pickMode(false);
  mark.on=on; $('#viewer').classList.toggle('marking',on); $('#zmark').classList.toggle('on',on);
  if(on){ linkTarget=null; closePanel(); $('#bannerText').textContent='Drag a box around the tag the app missed'; $('#bannerDone').textContent='Cancel'; $('#banner').style.display='flex' }
  else{ $('#banner').style.display='none'; $('#bannerDone').textContent='Done'; $('#markbox')?.remove(); mark.start=null }
}
$('#zmark').onclick=()=>markMode(!mark.on);
function setCover(on){ document.body.classList.toggle('cover',on); $('#zcover').classList.toggle('on',on);
  $('#zcover').setAttribute('aria-pressed',String(on)); if(cur) drawTags() }
$('#zcover').onclick=()=>setCover(!document.body.classList.contains('cover'));
function toStage(e){ const r=$('#viewer').getBoundingClientRect(); return {x:(e.clientX-r.left-view.x)/view.s, y:(e.clientY-r.top-view.y)/view.s} }
function markDraw(e,phase){
  const p=toStage(e);
  if(phase==='start'){ mark.start=p; $('#markbox')?.remove(); const b=document.createElement('div'); b.id='markbox'; $('#layer').appendChild(b) }
  const a=mark.start; if(!a) return;
  mark.box=[Math.max(0,Math.min(a.x,p.x)),Math.max(0,Math.min(a.y,p.y)),Math.min(cur.w,Math.max(a.x,p.x)),Math.min(cur.h,Math.max(a.y,p.y))];
  const b=mark.box; $('#markbox').style.cssText=`left:${b[0]}px;top:${b[1]}px;width:${b[2]-b[0]}px;height:${b[3]-b[1]}px`;
  if(phase==='end'){ mark.start=null; if(b[2]-b[0]<8||b[3]-b[1]<8){ toast('Box too small: drag across the whole tag'); $('#markbox').remove(); return } markForm(b) }
}
function markForm(bb){
  const t={sheet:cur.id,bbox:bb}, cancel=()=>{ markMode(false); closePanel() };
  put($('#panelBody'),h('div',{class:'phead'},h('div',{style:'flex:1'},h('div',{class:'kks',style:'font-size:17px'},'Mark a missing tag'),h('div',{class:'sub'},cur.name)),
      h('button',{class:'x',onclick:cancel},'×')),
    h('div',{class:'sec'},h('div',{class:'crop','data-sheet':t.sheet,style:cropStyle(t)}),
      h('div',{class:'sub'},'Type the code if you can read it. If not, leave it empty: it goes to the review queue.'),
      h('div',{class:'row2',style:'margin-top:8px'},h('div',{class:'field'},h('label',null,'KKS (with suffix)'),h('input',{id:'mkK',class:'mono',placeholder:'e.g. 11LAB90CP501'})),
        h('div',{class:'field'},h('label',null,'Function letters (instruments)'),h('input',{id:'mkI',class:'mono',placeholder:'e.g. PI, TIAC'}))),
      h('div',{class:'field'},h('label',null,'Note (optional)'),h('input',{id:'mkN',placeholder:'e.g. hard to read, second one below it'})),
      h('button',{class:'primary',onclick:()=>sendMark()},'Send'),' ',h('button',{class:'ghost',onclick:cancel},'Cancel')));
  $('#panel').classList.add('open'); $('#mkK').focus(); mark.pending=bb;
}
async function sendMark(){
  const kks=$('#mkK').value.trim().toUpperCase().replace(/\s/g,''), isa=$('#mkI').value.trim().toUpperCase();
  if(kks&&!/^\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3}[A-Z0-9]{0,4}$/.test(kks)){ toast('That is not a valid KKS (e.g. 11LAB70AA501); leave it empty if unsure'); return }
  const r=await send('tag_add',{sheet:cur.id,bbox:mark.pending.map(v=>Math.round(v*10)/10),kks,isa,note:$('#mkN').value.trim()},kks||'marked tag');
  if(r){ markMode(false); closePanel() }
}
async function removeAdded(id,label){ if(!confirm(`Remove the hand-added tag ${label}?`)) return; if(await send('tag_remove',{id},'remove '+label)) closePanel() }

// ---------- saving: every edit is a submission (applied at once for admins, otherwise queued for approval) ----------
async function refreshState(){
  try{ STATE={mine:[],...await api('/api/state')} }catch(e){ if(e.status===401) return location.reload(); if(K.isNetErr(e)) K.setOnline(false) }
  mergeTags();
  refreshFloors(); refreshReviewCount(); drawTags(); updateQueueBadge(); updatePending();
  // the open systems list follows the sync too, but never redraws under the keyboard or a screen reader's focus
  const SD=$('#sysDrawer');
  if(SD.classList.contains('open')){ if(SD.contains(document.activeElement)) sysStale=true; else renderSystems() }
  const CD=$('#covDrawer');   // the coverage numbers likewise
  // rebuilt at once unless the focus is on something the rebuild replaces (a row in #covBody; the heading stays)
  if(CD.classList.contains('open')){ if($('#covBody').contains(document.activeElement)) covStale=true; else renderCoverage() }
  // an open panel shows what changed elsewhere (an approval, a rejection, a new photo), unless you are editing in it
  const P=$('#panel');
  if(selId&&P.classList.contains('open')&&!P.contains(document.activeElement)&&!P.querySelector('.editing')){
    const t=TAGS.find(x=>x.id===selId); if(t){ const sc=P.scrollTop; select(eff(t)); P.scrollTop=sc }
  }
}
const canApprove=()=>['admin','manager'].includes(K.me?.user?.role);   // their edits apply at once: no note needed
async function send(kind,payload,what,note){
  let r; try{ r=await K.submit(kind,payload,note) }catch(e){ toast('Not saved: '+e.message); return null }
  toast({approved:'Saved: ',pending:'Sent for approval: ',conflict:'Clashes with a newer change, an admin will decide: ',queued:K.reauth?'Queued until you sign in again: ':'Offline, queued: '}[r.status]+what);
  if(r.status!=='queued') await refreshState(); else updatePending();
  return r;
}
function updateQueueBadge(){ const n=STATE.queue||0, b=$('#queueCount'); b.textContent=n; b.style.display=n?'':'none'; b.title=n+' change(s) waiting for approval' }
// your own submissions that aren't live yet (server-side pending/conflict + offline outbox), shown in the panel
function myPendingEq(k){ // your not-yet-approved equipment edits for k, oldest first
  const L=[...(STATE.mine||[]).filter(s=>s.kind==='equipment').map(s=>s.payload),...K.outbox.filter(i=>i.kind==='equipment').map(i=>i.payload)];
  return Object.assign({},...L.filter(p=>p.kks===k).map(p=>p.changes));
}
function pendingFor(t){
  const k=full(t), rel=(kind,p)=>kind==='review'?p.tag_id===t.id:kind==='photo_delete'?STATE.photos.some(x=>x.id===p.photo_id&&x.kks===k):!!k&&p.kks===k;
  return [...(STATE.mine||[]).map(s=>({kind:s.kind,p:s.payload,status:s.status})),...K.outbox.map(i=>({kind:i.kind,p:i.payload,status:i.refused?'refused':i.raw?'converting':'queued'}))].filter(x=>rel(x.kind,x.p));
}
function pendingSec(t){
  const L=pendingFor(t); if(!L.length) return null;
  const label={pending:'awaiting approval',conflict:'conflict: admin decides',queued:'queued offline',converting:'converting, then sent',refused:'refused by the server: see Manage → My submissions'};
  return h('div',{class:'sec'},h('h3',null,'Your changes, not live yet'),L.map(x=>h('div',{class:'pend'},h('span',{class:'badge '+x.status},label[x.status]),' '+K.describe(x.kind,x.p),
    x.kind==='photo'&&(x.p.file||x.p.dataUrl)?h('img',{src:x.p.file?'photos/'+x.p.file:x.p.dataUrl,alt:''}):null)));
}
function updatePending(){ const el=$('#pendingSec'); if(el&&selTag&&$('#panel').classList.contains('open')) put(el,pendingSec(selTag)) }
// with a service worker, fetching each sheet once stores it for offline use
async function cacheSheets(){ if(!navigator.serviceWorker?.controller) return;
  for(const s of SHEETS){
    const us=s.levels?[...Array(s.levels).keys()].map(k=>sheetFile(s.id,'.o'+k+'.jxl')).concat(sheetFile(s.id,'.kkp')):[s.file,s.vector];
    for(const u of us.filter(Boolean)){ try{ await fetch(u) }catch(e){ return } } } }

// ---------- viewer ----------
function openSheet(id,then){
  cur=SHEETS.find(s=>s.id===id); linkSel=null; $('#sheetSel').value=id; try{localStorage.setItem('sheet',id)}catch(e){}
  const img=$('#sheetimg'); let first=true;
  img.onload=()=>{ if(!first) return; first=false; fit(); drawTags(); then&&then(); };
  const s=cur, g=dark.gen;
  // nosemgrep: web-10-dynamic-url-sink -- an <img> source (the sheet overview) can't run script
  const show=u=>{ if(cur===s&&dark.gen===g) img.src=u };   // only if neither the sheet nor dark drawings changed meanwhile
  if(cur.levels){ const k=startLevel(); img.dataset.level=k; if(dark.on) levelSrc(k).then(show); else show(levelUrl(k)) }
  else { delete img.dataset.level; show(cur.file) }
  loadVector();
  img.style.width=cur.w+'px'; img.style.height=cur.h+'px'; $('#stage').style.width=cur.w+'px';
  renderNotes(); renderLinks();
}
// ---------- v2 plant data (decision 0034): an overview pyramid of JPEG XL levels + the path store drawn by tiles.js ----
// Level k is the sheet at 1/2^k of level 0 (cur.w × cur.h px). The <img> shows the coarsest level that is sharp enough
// for the view; browsers without JPEG XL get it decoded by K.jxl (libjxl in WebAssembly).
// URLs carry the plant data version (PDV), so a re-imported sheet is never served from an old cache entry
function sheetFile(id,ext){ return 'data/sheets/'+encodeURIComponent(id)+ext+(PDV?'?v='+PDV:'') }
function levelUrl(k){ return sheetFile(cur.id,'.o'+k+'.jxl') }
function startLevel(){ const v=$('#viewer').getBoundingClientRect(), need=Math.max(v.width,v.height)*(devicePixelRatio||1);
  let k=cur.levels-1; while(k>0&&Math.max(cur.w,cur.h)/2**k<need) k--; return k }
function wantLevel(){ const need=view.s*(devicePixelRatio||1); let k=cur.levels-1; while(k>0&&1/2**k<need) k--; return k }
function upgradeLevel(){
  if(!cur?.levels) return; const k=wantLevel(), img=$('#sheetimg'), shown=+(img.dataset.level??cur.levels-1);
  if(k>=shown) return;
  img.dataset.level=k;   // asked for: not asked again while it loads
  const s=cur, g=dark.gen;
  // swap once decoded (and only if neither the sheet nor dark drawings changed meanwhile)
  // nosemgrep: web-10-dynamic-url-sink -- an <img> source (the overview pyramid) can't run script
  levelSrc(k).then(u=>{ const pre=new Image(); pre.onload=()=>{ if(cur===s&&dark.gen===g) img.src=u }; pre.src=u })
    .catch(e=>console.warn('overview level',k,e));
}
// a level's image URL: the file itself where the browser shows JPEG XL, else K.jxl's decode (a detached image isn't
// watched); in dark drawings the tile worker decodes it with our libjxl and transforms every pixel (dark.js), off this
// thread. Dark levels are kept per sheet (blob: URLs, freed when another sheet opens).
function levelSrc(k){
  if(dark.on) sharp.worker??=startTiles();
  if(!dark.on||!sharp.worker||sharp.worker.failed){ const url=levelUrl(k); return K.jxl.native().then(n=>n?url:K.jxl.url(url)) }
  // dark: at most ~4 megapixels (the vector tiles draw the detail when zoomed in): a level 0 of 6400 × 4800 would cost
  // ~120 MB of decoder memory in the worker, a copy and a 92 MB BMP here, where light mode shows the file itself
  while(k<cur.levels-1&&cur.w*cur.h/4**k>DARK_MAX_PX) k++;
  const url=levelUrl(k);
  if(dark.sheet!==cur.id){ dropDarkLevels(); dark.sheet=cur.id }
  if(!dark.levels.has(url)){
    const p=new Promise((res,rej)=>{ const id=++dark.seq; dark.wait.set(id,{res,rej}); sharp.worker.postMessage({t:'level',id,url}) })
      .then(b=>URL.createObjectURL(b));
    p.catch(()=>{ if(dark.levels.get(url)===p) dark.levels.delete(url) });   // a failure isn't kept: tried again next time
    dark.levels.set(url,p);
  }
  // a failed dark decode shows the light level rather than nothing (the sheet must open, fit and take /?kks= links)
  return dark.levels.get(url).catch(e=>{ console.warn('dark overview level',k,e);
    if(!dark.warned){ dark.warned=true; toast('Dark drawings: the overview could not be made dark here; showing it light') }
    return K.jxl.native().then(n=>n?url:K.jxl.url(url)) });
}
const DARK_MAX_PX=4e6;
function dropDarkLevels(){ for(const p of dark.levels.values()) p.then(u=>URL.revokeObjectURL(u),()=>{}); dark.levels.clear() }
// ---------- dark drawings: like a PDF reader's dark mode; remembered on this device ----------
const dark={on:false,gen:0,sheet:null,levels:new Map(),wait:new Map(),seq:0,warned:false};
function setDark(on){
  dark.on=on; dark.gen++; document.body.classList.toggle('darkdwg',on);
  const b=$('#zdark'); b.classList.toggle('on',on); b.setAttribute('aria-pressed',String(on));
  try{ on?localStorage.setItem('darkDrawings','1'):localStorage.removeItem('darkDrawings') }catch(e){}
  if(!on){ dropDarkLevels(); dark.sheet=null }      // their blob: URLs are freed with them
  if(!cur?.levels) return;
  sharp.worker??=startTiles();
  // the overview level on screen again in the new colours, and the sharp layer redrawn now (not after the 150 ms pause)
  const img=$('#sheetimg'), s=cur, g=dark.gen, k=+(img.dataset.level??cur.levels-1);
  // nosemgrep: web-10-dynamic-url-sink -- an <img> source (the overview pyramid) can't run script
  levelSrc(k).then(u=>{ if(cur===s&&dark.gen===g) img.src=u }).catch(e=>console.warn('overview level',k,e));
  clearTimeout(sharp.timer); drawSharp();
}
$('#zdark').onclick=()=>setDark(!dark.on);
try{ if(localStorage.getItem('darkDrawings')==='1') setDark(true) }catch(e){}
function apply(){ const t=`translate(${view.x}px,${view.y}px) scale(${view.s})`; $('#stage').style.transform=t; $('#stage2').style.transform=t; followSharp() }

// ---------- sharp layer: the sheet's vector drawing, redrawn for the visible area once the view stops moving ----------
// The PNG is a fixed-resolution bitmap; beyond ~1:1 it gets blocky. The canvas draws the vector file (the PDF's own
// drawing) at the screen's real resolution. While panning/zooming, the last drawing is moved along with CSS (and the
// PNG shows at the edges); ~150 ms after the view settles it is redrawn sharp.
const sharp={img:null,at:null,timer:null,worker:null,key:0,ready:null,pending:null};
function loadVector(){
  sharp.img=null; sharp.at=null; sharp.ready=null; $('#sharp').style.display='none';
  if(cur.levels){   // v2: the path store in the worker
    sharp.worker??=startTiles();
    if(sharp.worker) sharp.worker.postMessage({t:'open',sheet:cur.id,url:sheetFile(cur.id,'.kkp')});
    return;
  }
  if(!cur.vector) return;
  const im=new Image(), s=cur; im.onload=()=>{ if(cur===s){ sharp.img=im; drawSharp() } }; im.src=cur.vector;
}
function startTiles(){
  try{
    const w=new Worker('/tiles.js',{type:'module'});
    w.onmessage=e=>{ const m=e.data;
      if(m.t==='opened'){ if(cur&&m.sheet===cur.id){ sharp.ready=cur.id; drawSharp() } }
      else if(m.t==='frame'){ if(sharp.pending&&m.key===sharp.pending.key) showFrame(m.bmp,sharp.pending.at); else m.bmp.close() }
      else if(m.t==='level'){ const p=dark.wait.get(m.id); dark.wait.delete(m.id); if(!p) return;
        if(m.blob){ dark.lastMs=m.ms; p.res(m.blob) } else p.rej(new Error(m.why)) }
      else if(m.t==='error') console.warn('drawing',m.sheet,m.why);
    };
    // a worker that failed to load (or died) never answers: the overview levels it was asked for fall back to light
    // (levelSrc), and no more are asked of it, rather than the sheet staying blank
    w.onerror=e=>{ console.warn('tile worker',e.message||e); w.failed=true;
      for(const p of dark.wait.values()) p.rej(new Error('the tile worker stopped')); dark.wait.clear() };
    return w;
  }catch(e){ console.warn('no tile worker: the overview only',e); return null }
}
function showFrame(bmp,at){
  const c=$('#sharp'), v=$('#viewer').getBoundingClientRect(), d=devicePixelRatio||1;
  if(c.width!==bmp.width||c.height!==bmp.height){ c.width=bmp.width; c.height=bmp.height; c.style.width=bmp.width/d+'px'; c.style.height=bmp.height/d+'px' }
  const x=c.getContext('2d'); x.setTransform(1,0,0,1,0,0); x.drawImage(bmp,0,0); bmp.close();
  sharp.at=at; c.style.display='block'; followSharp(true);
}
function drawSharp(){
  const c=$('#sharp'), v=$('#viewer').getBoundingClientRect(), d=devicePixelRatio||1;
  if(cur?.levels){
    upgradeLevel();
    if(sharp.ready!==cur.id||view.s*d<0.7){ c.style.display='none'; sharp.at=null; return }  // the overview is as sharp
    const W=Math.round(v.width*d), H=Math.round(v.height*d), sc=cur.scale||2;
    // the area in points: level-0 px = (screen − view.x) / view.s, points = px / scale
    const key=++sharp.key; sharp.pending={key,at:{...view}};
    sharp.worker.postMessage({t:'render',key,sheet:cur.id,x0:-view.x/view.s/sc,y0:-view.y/view.s/sc,s:view.s*d*sc,W,H,dark:dark.on});
    return;
  }
  if(!sharp.img||view.s*d<0.7){ c.style.display='none'; sharp.at=null; return }  // zoomed out: the PNG is as sharp
  const W=Math.round(v.width*d), H=Math.round(v.height*d);
  if(c.width!==W||c.height!==H){ c.width=W; c.height=H; c.style.width=v.width+'px'; c.style.height=v.height+'px' }
  const x=c.getContext('2d'); x.setTransform(1,0,0,1,0,0); x.clearRect(0,0,W,H);
  x.setTransform(d*view.s,0,0,d*view.s,d*view.x,d*view.y); x.fillStyle='#fff'; x.fillRect(0,0,cur.w,cur.h);
  x.drawImage(sharp.img,0,0,cur.w,cur.h);
  sharp.at={...view}; c.style.transform=''; c.style.display='block';
}
function followSharp(justDrawn){
  const a=sharp.at, c=$('#sharp');
  if(a){ const k=view.s/a.s; c.style.transform=`translate(${view.x-k*a.x}px,${view.y-k*a.y}px) scale(${k})` }
  if(justDrawn) return;
  clearTimeout(sharp.timer); if(sharp.img||cur?.levels) sharp.timer=setTimeout(drawSharp,150);
}
addEventListener('resize',()=>{ clearTimeout(sharp.timer); sharp.timer=setTimeout(drawSharp,150) });
function fit(){ const v=$('#viewer').getBoundingClientRect(); view.s=Math.min(v.width/cur.w,v.height/cur.h)*0.98; view.x=(v.width-cur.w*view.s)/2; view.y=(v.height-cur.h*view.s)/2; apply() }
// A page loaded while hidden (a background tab; the Android app moving its viewer between layouts) measures the viewer
// as 0 px and fits the sheet at scale 0. Fit again once it has a real size; a view the person set is never reset.
new ResizeObserver(()=>{ const v=$('#viewer').getBoundingClientRect(); if(cur&&v.width&&v.height&&!(view.s>0)) fit() }).observe($('#viewer'));
// max zoom 16x when the sheet has a vector file (it stays sharp), 4x otherwise
function zoomAt(f,cx,cy){ const v=$('#viewer').getBoundingClientRect(); cx??=v.width/2; cy??=v.height/2;
  const ns=Math.max(0.05,Math.min(cur.vector||cur.levels?16:4,view.s*f)); view.x=cx-(cx-view.x)*ns/view.s; view.y=cy-(cy-view.y)*ns/view.s; view.s=ns; apply() }
function centerOn(b,scale=0.9){ const v=$('#viewer').getBoundingClientRect(); view.s=scale;
  const mobile=innerWidth<=720, pw=mobile?0:430, ph=mobile?v.height*0.62:0;
  view.x=(v.width-pw)/2-((b[0]+b[2])/2)*view.s; view.y=(v.height-ph)/2-((b[1]+b[3])/2)*view.s; apply() }
$('#zin').onclick=()=>zoomAt(1.4); $('#zout').onclick=()=>zoomAt(1/1.4); $('#zfit').onclick=fit;
(function pan(){
  const el=$('#viewer'), pts=new Map(); let last=null, pinch=null, moved=false;
  el.addEventListener('wheel',e=>{e.preventDefault(); const r=el.getBoundingClientRect(); zoomAt(e.deltaY<0?1.15:1/1.15,e.clientX-r.left,e.clientY-r.top)},{passive:false});
  el.addEventListener('pointerdown',e=>{ if(mark.on&&!pts.size&&e.button===0){ e.preventDefault(); el.setPointerCapture?.(e.pointerId); markDraw(e,'start'); moved=true; return }
    pts.set(e.pointerId,{x:e.clientX,y:e.clientY}); moved=false;
    // select mode: one pointer drags a box (no panning); a second finger turns it into a pinch
    if(multi.on){ if(pts.size===1&&e.button===0) multi.start={p:toStage(e),x:e.clientX,y:e.clientY}; else pickBox(null) }
    if(pts.size===1){last={x:e.clientX,y:e.clientY}; el.classList.add('drag')}
    if(pts.size===2){const [a,b]=[...pts.values()]; pinch={d:Math.hypot(a.x-b.x,a.y-b.y)}} });
  el.addEventListener('pointermove',e=>{ if(mark.start){ markDraw(e,'move'); return } if(!pts.has(e.pointerId))return; pts.set(e.pointerId,{x:e.clientX,y:e.clientY});
    if(multi.start&&pts.size===1){ if(multi.box||Math.abs(e.clientX-multi.start.x)+Math.abs(e.clientY-multi.start.y)>6){ moved=true; pickBox(toStage(e)) } return }
    if(pts.size===2&&pinch){const [a,b]=[...pts.values()],d=Math.hypot(a.x-b.x,a.y-b.y),r=el.getBoundingClientRect();
      zoomAt(d/pinch.d,(a.x+b.x)/2-r.left,(a.y+b.y)/2-r.top); pinch.d=d; moved=true; return}
    if(last){const dx=e.clientX-last.x,dy=e.clientY-last.y; if(Math.abs(dx)+Math.abs(dy)>3)moved=true; view.x+=dx; view.y+=dy; last={x:e.clientX,y:e.clientY}; apply()} });
  const up=e=>{ if(mark.start){ markDraw(e,'end'); return }
    if(multi.start&&pts.size===1&&pts.has(e.pointerId)){ const b=multi.box; pickBox(null); if(b&&e.type==='pointerup') addBox(b) }
    pts.delete(e.pointerId); if(pts.size<2)pinch=null; if(pts.size===1)last={...[...pts.values()][0]}; if(!pts.size){last=null; el.classList.remove('drag')} };
  el.addEventListener('pointerup',up); el.addEventListener('pointercancel',up);
  el.addEventListener('click',e=>{ if(moved&&e.detail){e.stopPropagation();e.preventDefault()} },true);
  // a focused tag (the select mode's Tab order) must not scroll the viewer itself: the view pans to it instead
  el.addEventListener('scroll',()=>{ el.scrollLeft=0; el.scrollTop=0 });
  el.addEventListener('focusin',e=>{ const t=e.target; if(!t.classList?.contains('hs')||!t.matches(':focus-visible')) return;   // keyboard focus only
    const r=t.getBoundingClientRect(), v=el.getBoundingClientRect(), m=24;
    let dx=0, dy=0;
    if(r.left<v.left+m) dx=v.left+m-r.left; else if(r.right>v.right-m) dx=v.right-m-r.right;
    if(r.top<v.top+m) dy=v.top+m-r.top; else if(r.bottom>v.bottom-m) dy=v.bottom-m-r.bottom;
    if(dx||dy){ view.x+=dx; view.y+=dy; apply() } });
})();

// a photo of the tag plate is a photo whose caption starts with "Tag plate" (PROTOCOL-v2 §9; core model.photoCover)
const photoCover=k=>KSys.photoCover(k,STATE.photos);
const COVER_WORDS={both:'equipment and tag plate photos',equipment:'equipment photo only',plate:'tag plate photo only',none:'no photos'};
function drawTags(){
  // a sync redraws the tags at any moment, so their buttons are updated in place (by tag id), never replaced: a button
  // replaced between the press and the release lost the click. A box being dragged (select mode, or marking a missed
  // tag) and the focus stay too.
  const L=$('#layer'), fe=L.contains(document.activeElement)?document.activeElement:null, old=new Map(), want=[];
  for(const x of L.querySelectorAll('.hs[data-id]')) old.set(x.dataset.id,x);
  const covers=KSys.photoCovers(STATE.photos), photoCover=k=>covers.get(k)||'none';   // one pass over the photos
  const hl=new Set(activeProc?STATE.links.filter(l=>l.proc===activeProc).map(l=>l.kks):[]);
  const picked=new Set(multi.on?multi.codes:[]);
  // off-page connectors (C16, D2 …), under the tags (a click on a tag next to one stays the tag's): dashed violet circles; a click opens where the line continues (followLink). Not
  // while selecting tags (clicks pick tags only) or marking a missed tag
  // Kept in place like the tags (by sheet, label and corner); each button reads its connector at click time.
  const sc=pxScale(cur), oldC=new Map();
  for(const x of L.querySelectorAll('button.conn')) oldC.set(x.dataset.key,x);
  for(const l of linksHere()){
    const sel=linkSel&&linkSel.sheet===cur.id&&Math.abs(linkSel.x0-l.x0)<0.01&&Math.abs(linkSel.y0-l.y0)<0.01;
    const key=cur.id+'\n'+l.label+'\n'+l.x0+'\n'+l.y0;
    let d=oldC.get(key); oldC.delete(key);
    if(!d){ d=h('button',{type:'button',tabindex:'-1','data-key':key,
      onclick:e=>{ e.stopPropagation(); if(multi.on||mark.on) return; followLink(d._l.sheet,d._l.label,d._l.x0,d._l.y0) }}) }
    d._l={sheet:cur.id,label:l.label,x0:l.x0,y0:l.y0};
    d.className='conn'+(sel?' sel':''); d.dataset.label=l.label; d.setAttribute('aria-label',linkName(l)); d.title=linkName(l);
    d.style.cssText=`left:${l.x0*sc-3}px;top:${l.y0*sc-3}px;width:${(l.x1-l.x0)*sc+6}px;height:${(l.y1-l.y0)*sc+6}px`;
    want.push(d);
  }
  for(const t of tagsOf(cur.id)){
    // a button: Enter or Space acts like a click; in the tab order only while selecting tags
    let d=old.get(t.id); old.delete(t.id);
    if(!d){ d=document.createElement('button'); d.type='button'; d.dataset.id=t.id }
    const b=t.bbox, k=full(t);
    d.dataset.k=k; d.tabIndex=multi.on?0:-1; d.setAttribute('aria-label',k||'unreadable tag');
    if(multi.on) d.setAttribute('aria-pressed',String(picked.has(k))); else d.removeAttribute('aria-pressed');
    d.className='hs'+(t.status==='review'?' review':'')+(t.id===selId?' sel':'')+(k&&hl.has(k)?' hl':'')+(k&&picked.has(k)?' picked':'')+' p-'+photoCover(k);
    if(floor){ const f=floorOf(t); d.classList.add(f.toLowerCase()===floor.toLowerCase()?'floor':'dim') }
    d.style.cssText=`left:${b[0]-3}px;top:${b[1]-3}px;width:${b[2]-b[0]+6}px;height:${b[3]-b[1]+6}px`;
    d.title=(k||'unreadable tag')+(document.body.classList.contains('cover')?' · '+COVER_WORDS[photoCover(k)]:''); d.onclick=e=>{e.stopPropagation(); tagClick(t)};
    want.push(d);
  }
  // your marks awaiting approval (sent, or queued offline)
  for(const p of [...(STATE.mine||[]).filter(s=>s.kind==='tag_add').map(s=>s.payload),...K.outbox.filter(i=>i.kind==='tag_add').map(i=>i.payload)]){
    if(p.sheet!==cur.id) continue; const b=p.bbox, d=document.createElement('div'); d.className='hs pendmark';
    d.style.cssText=`left:${b[0]-3}px;top:${b[1]-3}px;width:${b[2]-b[0]+6}px;height:${b[3]-b[1]+6}px`; d.title='Your mark, awaiting approval'; want.push(d);
  }
  // the valve symbol of the tag whose panel is open (the core's valve_type box), while the panel shows it
  const vt=selTag&&selTag.sheet===cur.id?valveTypeOf(selTag):null;
  if(vt?.box){ const b=vt.box, d=document.createElement('div'); d.className='vsym'; d.setAttribute('aria-hidden','true');
    d.title='The valve symbol the type was read from';
    d.style.cssText=`left:${b[0]-3}px;top:${b[1]-3}px;width:${b[2]-b[0]+6}px;height:${b[3]-b[1]+6}px`; want.push(d) }
  want.push(...L.querySelectorAll('#selbox,#markbox'));
  // the rest go first, then this order: a node already in its place isn't moved (a move is a removal: it would lose
  // a press on it, and its focus)
  const keep=new Set(want);
  for(const x of [...L.childNodes]) if(!keep.has(x)) x.remove();
  let at=L.firstChild;
  for(const d of want){ if(d===at) at=at.nextSibling; else L.insertBefore(d,at) }
  if(fe&&fe.isConnected&&document.activeElement!==fe) fe.focus({preventScroll:true});
}
function tagClick(t){
  if(multi.on){ togglePick(t); return }
  if(linkTarget){
    const k=full(t); if(!k){toast('This tag has no KKS yet — review it first');return}
    const lt=linkTarget;
    send('link',{proc:lt.proc,step:lt.step,kks:k,on:true},`${k} → step ${lt.step}`).then(()=>{ drawTags(); renderProcDetail(lt.proc) });
    return;
  }
  select(t);
}
function goTo(tagId){
  const t=TAGS.find(x=>x.id===tagId); if(!t)return;
  const go=()=>{ const e=eff(t)||t; centerOn(e.bbox); select(e) };
  if(cur?.id!==t.sheet) openSheet(t.sheet,go); else go();
}

// ---------- KKS decoding ----------
const decode=t=>KSys.decode(t,KKS);
function kindName(t){ const d=decode(t); if(!d) return t.kind; return KKS.components[d.comp]||('Component code '+d.comp) }

// ---------- who and when (/api/state: photos[].by_name, equipment_by {code: {field: {by, by_name, at}}}) ----------
const day=t=>t?new Date(t*1000).toLocaleDateString():'';
const byLine=w=>w&&w.by_name?`by ${w.by_name}${w.at?', '+day(w.at):''}`:'';
const eqBy=k=>(STATE.equipment_by||{})[k]||{};

// ---------- descriptions: drafts from descriptions.json until a person confirms one (core views.descriptionOf) ----------
// Confirming is an equipment proposal that adds the custom field "Description"; a confirmed one is that field.
const DESC_KEY='Description';
function parseDesc(j){   // core model.parseDescriptions: a string = the text; text capped at 2000 characters
  const out={}; if(!j||typeof j!=='object'||Array.isArray(j)) return out;
  for(const [k,v] of Object.entries(j)){ let text='',basis='';
    if(typeof v==='string') text=v; else if(v&&typeof v==='object'){ if(typeof v.text==='string') text=v.text; if(typeof v.basis==='string') basis=v.basis }
    text=[...text.trim()].slice(0,2000).join('').trim(); if(k&&text) out[k]={text,basis:basis.trim()} }
  return out;
}
const customOf=(e,key)=>((e&&e.custom||[]).find(c=>c.k===key)||{}).v||'';
function descriptionOf(t){
  const k=full(t); if(!k) return null;
  const live=eq(k), have=customOf(live,DESC_KEY), draft=DESC[k]||(t.suffix?DESC[t.kks]:null)||null;
  if(have){ const w=eqBy(k)['custom:'+DESC_KEY];
    return {status:'confirmed',text:have,basis:draft?.basis||'',by_name:w?.by_name||'',at:w?.at??null,draft_differs:!!draft&&draft.text!==have} }
  if(!draft) return null;
  const base=(live.custom||[]).map(c=>({k:c.k,v:c.v}));
  return {status:'draft',text:draft.text,basis:draft.basis,
    confirm:{kind:'equipment',payload:{kks:k,changes:{custom:[...base,{k:DESC_KEY,v:draft.text}]},base:{custom:base}}}};
}
function descSec(t){
  const d=descriptionOf(t), k=full(t); if(!d) return null;
  const pe=myPendingEq(k), waiting=!!pe.custom&&customOf(pe,DESC_KEY)!==customOf(eq(k),DESC_KEY);   // your confirmation or edit, not live yet
  const tools=waiting?h('div',{class:'sub',style:'margin-top:6px'},'Your change to the description is awaiting approval.')
    :h('div',{style:'margin-top:8px'},d.status==='draft'?[h('button',{class:'primary',onclick:()=>confirmDesc(t)},'Confirm'),' ']:null,
      h('button',{class:'ghost',onclick:()=>editDesc(t,d.text)},'Edit'));
  const basis=d.basis?h('div',{class:'sub'},'Basis: '+d.basis):null;
  return h('div',{class:'sec',id:'descSec'},h('h3',null,'Description'),
    d.status==='draft'?h('div',{class:'draft'},h('div',{class:'lbl'},'Draft description (unchecked)'),h('div',{class:'desc'},d.text),basis)
      :[h('div',{class:'desc'},d.text),h('div',{class:'by'},'Confirmed'+(d.by_name?' by '+d.by_name:'')+(d.at?', '+day(d.at):'')),basis,
        d.draft_differs?h('div',{class:'sub'},'Differs from the drafted text.'):null],
    tools);
}
async function confirmDesc(t){ const d=descriptionOf(t); if(d?.status!=='draft') return;
  if(await send(d.confirm.kind,d.confirm.payload,full(t)+': description confirmed')) reselect() }
// the open panel again, at the same scroll position (after a change made from it: focus is still in it)
function reselect(){ const P=$('#panel'); if(!selTag||!P.classList.contains('open')) return; const sc=P.scrollTop; select(eff(TAGS.find(x=>x.id===selTag.id)||selTag)); P.scrollTop=sc }
function editDesc(t,text){
  const ta=h('textarea',{id:'descEdit',rows:4,maxlength:2000,style:'width:100%'},text);
  put($('#descSec'),h('h3',null,'Description'),h('div',{class:'field'},h('label',{for:'descEdit'},'What this equipment does'),ta),
    h('button',{class:'primary',onclick:()=>saveDesc(t,ta.value.trim())},'Save'),' ',h('button',{class:'ghost',onclick:()=>$('#descSec').replaceWith(descSec(t))},'Cancel'));
  $('#descSec').classList.add('editing'); ta.focus();
}
async function saveDesc(t,text){
  const k=full(t), base=(eq(k).custom||[]).map(c=>({k:c.k,v:c.v})), rest=base.filter(c=>c.k!==DESC_KEY);
  const custom=text?[...rest,{k:DESC_KEY,v:text}]:rest;
  if(JSON.stringify(custom)===JSON.stringify(base)){ toast('Nothing changed'); return }
  if(await send('equipment',{kks:k,changes:{custom},base:{custom:base}},k+': description')) reselect();
}

// ---------- photos: the floor first, then the photo; converted and sent in the background (K.queuePhoto) ----------
// `queued` false: a floor that only rides on a photo still in the outbox (waiting, or kept after it was refused) doesn't count
const floorKnown=(k,queued=true)=>!!((eq(k).floor||'').trim()||String(myPendingEq(k).floor??'').trim()
  ||[...(STATE.mine||[]).map(s=>s.payload),...(queued?K.outbox:[]).map(i=>i.payload)].some(p=>p&&p.kks===k&&p.floor));
function photoAdd(k){
  const need=!floorKnown(k);
  const pick=(label,plate)=>h('label',{class:'ghost',style:'display:inline-block;margin:8px 6px 0 0;cursor:pointer'},label,
    h('input',{type:'file',accept:'image/*',capture:'environment',style:'display:none','data-plate':plate?'1':null,onchange:ev=>addPhoto(ev.currentTarget,k,plate)}));
  const btns=h('div',{id:'phAdd',style:need?'display:none':null},pick('+ Equipment photo',false),pick('+ Tag plate photo',true));
  if(!need) return btns;
  const inp=h('input',{id:'phFloor',type:'number',inputmode:'numeric',min:0,max:10,step:1,placeholder:'0–10',style:'width:90px',
    oninput:()=>{ btns.style.display=/^(\d|10)$/.test(inp.value.trim())?'':'none' }});
  return [h('div',{class:'field',style:'margin-top:8px'},h('label',{for:'phFloor'},'Floor: needed before a photo (this equipment has none yet)'),inp),btns];
}

// ---------- equipment panel ----------
let selTag=null, panelEq=null;
function select(t){
  selId=t.id; selTag=t; drawTags();
  const k=full(t), d=decode(t), e={...eq(k),...myPendingEq(k)}, P=$('#panelBody');
  const where=TAGS.map(eff).filter(x=>x&&full(x)===k&&k).map(x=>x);
  const procs=[...new Set(STATE.links.filter(l=>l.kks===k).map(l=>l.proc))];
  const photos=STATE.photos.filter(p=>p.kks===k);
  const sheetName=id=>SHEETS.find(s=>s.id===id)?.name||id;
  const out=[h('div',{class:'phead'},h('div',{style:'flex:1'},
      h('div',{class:'kks',tabindex:'-1',role:'heading','aria-level':'2'},k?[t.kks,t.suffix?h('span',{class:'sfx'},t.suffix):null]:h('span',{style:'color:var(--review)'},'Unread tag')),
      h('div',{class:'sub'},t.isa?t.isa+' · ':'',kindName(t))),closeX()),
    h('div',{id:'pendingSec'},pendingSec(t)),descSec(t)];
  if(t.status==='review'){
    const s=t.suggestion||{};
    out.push(h('div',{class:'sec'},h('h3',null,'Check this tag'),
      h('div',{class:'crop','data-sheet':t.sheet,style:cropStyle(t)}),
      h('div',{class:'sub'},'Reader saw: ',h('span',{class:'mono'},`${t.read[0]??''} / ${t.read[1]??''}`),` · confidence ${Math.round(t.conf*100)}%`),
      t.note?h('div',{class:'warn'},t.note):null,s.note?h('div',{class:'warn'},s.note):null,
      h('div',{class:'row2',style:'margin-top:8px'},h('div',{class:'field'},h('label',null,'KKS (with suffix)'),h('input',{id:'rvK',class:'mono',value:(s.kks)||((t.kks||'')+(t.suffix||''))})),
        h('div',{class:'field'},h('label',null,'Function letters (instruments)'),h('input',{id:'rvI',class:'mono',value:s.isa||t.isa||''}))),
      h('button',{class:'primary',onclick:()=>review(t.id,'confirmed')},'Confirm'),' ',h('button',{class:'ghost',onclick:()=>review(t.id,'rejected')},'Not a tag'),
      s.kks?h('div',{class:'sub',style:'margin-top:6px'},'Pre-filled value was checked visually during extraction.'):null));
  }
  if(d){
    const code=(c,name)=>h('dd',null,h('span',{class:'mono'},c),' '+name);
    out.push(h('div',{class:'sec'},h('h3',null,'From the drawing'),h('dl',null,
      h('dt',null,'Plant unit'),code(d.blk,KKS.blocks[d.blk]||''),
      h('dt',null,'System'),code(d.sys,KKS.systems[d.sys]||'not in legend'),
      h('dt',null,'Subsystem no.'),h('dd',{class:'mono'},d.fn),
      h('dt',null,'Component'),code(d.comp,KKS.components[d.comp]||''),
      h('dt',null,'Number'),h('dd',{class:'mono'},d.num),
      d.isa?[h('dt',null,'Instrument'),h('dd',null,d.isa)]:null,
      h('dt',null,'Reading'),h('dd',null,t.status==='confirmed'?'confirmed by you':t.status==='verified'?'checked by eye against the drawing':'automatic, '+Math.round(t.conf*100)+'% confidence'),
      t.flag?[h('dt',null,'Flag'),h('dd',{style:'color:var(--review)'},t.flag)]:null)));
  }
  const vt=valveTypeOf(t); if(vt) out.push(valveSec(t,vt));
  out.push(locSec(bodyOf(t),t.suffix));
  if(t.added) out.push(h('div',{class:'sec'},h('h3',null,'Added by hand'),h('div',{class:'sub'},'The app\'s reader missed this tag; someone marked it on the drawing.'+(t.note?' Note: '+t.note:'')),
    h('button',{class:'ghost',style:'margin-top:6px',onclick:()=>removeAdded(t.added,k||'this mark')},'Remove this tag')));
  if(where.length){
    out.push(h('div',{class:'sec'},h('h3',null,'Appears on'),where.map(x=>h('span',{class:'chip',onclick:()=>goTo(x.id)},sheetName(x.sheet)))));
  }
  if(procs.length){
    out.push(h('div',{class:'sec'},h('h3',null,'Used in procedures'),procs.map(p=>{const pr=PROCS.find(x=>x.id===p);return h('span',{class:'chip',onclick:()=>openProc(p)},`${p} ${pr?pr.title??'':''}`)})));
  }
  if(k){
    panelEq={k,live:JSON.parse(JSON.stringify(eq(k))),shown:JSON.parse(JSON.stringify(e))};
    const cf=e.custom||[], R=refLoc(bodyOf(t)), ph=v=>v?v+' (location list)':'', B=eqBy(k), by=f=>byLine(B[f]);
    // read-only until you tap ✎ next to a field (no accidental edits); Save appears once something is unlocked
    out.push(h('div',{class:'sec'},h('h3',null,'Location'),
        h('div',{class:'row2'},fld('f_area','Building / area',e.area,{by:by('area')}),fld('f_floor','Floor',e.floor,{type:'number',ph:'0–10',by:by('floor')})),
        h('div',{class:'row2'},fld('f_elev','Elevation',e.elev,{ph:ph(R.elev)||'e.g. 14 m',by:by('elev')}),fld('f_near','Near / landmark',e.near,{by:by('near')})),
        fld('f_loc','How to find it',e.loc,{area:1,by:by('loc')})),
      h('div',{class:'sec'},h('h3',null,'Notes & custom fields'),
        fld('f_notes','Notes',e.notes,{area:1,ph:'Anything worth remembering',by:by('notes')}),
        h('div',{class:'field lock'},h('label',null,'Custom fields'),
          h('div',{class:'lk'},h('div',{id:'cfs',style:'flex:1'},cf.length?cf.map(c=>cfRow(c.k,c.v,true,byLine(B['custom:'+c.k]))):null,
            cf.some(c=>c.k!==DESC_KEY)?null:h('div',{class:'sub cfnone'},'None')),
            h('button',{class:'pen',onclick:()=>unlockCustom(),title:'Edit custom fields','aria-label':'Edit custom fields'},'✎')),
          h('button',{class:'ghost',id:'cfAdd',style:'display:none',onclick:()=>$('#cfs').append(cfRow('',''))},'+ Custom field')),
        h('div',{id:'eqSave',style:'margin-top:10px;display:none'},
          canApprove()?null:h('input',{id:'f_rnote',maxlength:500,placeholder:'Note for the approver (optional)',style:'width:100%;margin-bottom:8px'}),
          h('button',{class:'primary',onclick:()=>saveEq(k)},'Save'),' ',h('button',{class:'ghost',onclick:()=>select(eff(selTag))},'Cancel'))),
      h('div',{class:'sec'},h('h3',null,'Photos'),
        h('div',{class:'photos'},photos.map(p=>h('figure',null,h('img',{src:'photos/'+encodeURIComponent(p.file),alt:p.caption||'Photo',onclick:ev=>lightbox(ev.currentTarget.src)}),
          h('button',{onclick:()=>delPhoto(p.id,t.id),'aria-label':'Delete this photo'},'✕'),
          h('figcaption',null,p.kind==='plate'||String(p.caption||'').startsWith('Tag plate')?'Tag plate · ':'',byLine({by_name:p.by_name,at:p.submitted??p.created})||day(p.created))))),
        photoAdd(k)));
  }
  put(P,out); $('#panel').classList.add('open'); $('#panel').scrollTop=0;
  if(focusPanel){ focusPanel=false; P.querySelector('.phead .kks')?.focus() }
}
// ---------- valve type: read from the drawn symbol (unchecked) until someone confirms or corrects it ----------
// (systems.js KSys.valveType, a port of core model.valveTypeOf; kept as the equipment custom field "Valve type")
const valveTypeOf=t=>{ const k=full(t); return k?KSys.valveType(t,eq(k)):null };
function valveSec(t,vt){
  const k=full(t), sec=h('div',{class:'sec',id:'valveSec'},h('h3',null,'Valve type'),h('div',{id:'vtLine'},vt.line));
  if(vt.status==='confirmed'){
    if(vt.drawn_differs) sec.append(h('div',{class:'sub'},'The drawing\'s symbol reads: '+vt.drawn));
    return sec }
  sec.append(h('div',{class:'sub'},'Read from the valve symbol drawn next to the tag (outlined on the drawing)'+
    (vt.conf!=null?', '+Math.round(vt.conf*100)+' % sure':'')+'. Confirm it, or correct it if the symbol says otherwise.'));
  if(!vt.confirm){ sec.append(h('div',{class:'warn'},'This equipment already has 100 custom fields: remove one to save the valve type.')); return sec }
  // your own proposal of a type, not live yet (a member's waits for approval): said, and no second one offered
  const mine=(myPendingEq(k).custom||[]).find(x=>x&&x.k===KSys.VALVE_KEY&&x.v);
  if(mine){ sec.append(h('div',{class:'sub',id:'vtMine'},'Your valve type “'+mine.v+'” is waiting for approval.')); return sec }
  const done=r=>{ if(r){ const x=TAGS.find(y=>y.id===t.id); select(x?eff(x)||t:t) } };
  // one proposal at a time: every button of the section waits for the answer (a second one would clash with the
  // first), and none while another form of the panel is open (the rebuild after sending would lose what is typed there)
  const busy=on=>sec.querySelectorAll('button').forEach(b=>b.disabled=on);
  const otherForm=()=>[...$('#panel').querySelectorAll('.editing')].some(e=>!sec.contains(e));
  const go=(c,what)=>{ if(sec.dataset.busy) return; if(otherForm()){ toast('Save or cancel your edits first'); return }
    sec.dataset.busy='1'; busy(true);
    send(c.kind,c.payload,k+' valve type: '+what).then(r=>{ delete sec.dataset.busy; busy(false); done(r) }) };
  const ok=h('button',{class:'primary',onclick:()=>go(vt.confirm,vt.text)},'Confirm type');
  const btns=h('div',{class:'vtBtns',style:'margin-top:8px'},ok,' ',h('button',{class:'ghost',onclick:()=>{ if(otherForm()){ toast('Save or cancel your edits first'); return } correct() }},'Correct type'));
  sec.append(btns);
  function correct(){
    const submit=()=>{ const c=KSys.withValveType(vt.confirm,inp.value);
      if(!c){ toast('Type the valve type first'); return }
      go(c,c.payload.changes.custom.find(x=>x.k===KSys.VALVE_KEY).v) };
    const inp=h('input',{id:'vtValue',value:vt.text,maxlength:200,'aria-label':'Valve type',onkeydown:e=>{ if(e.key==='Enter') submit() }});
    const sendBtn=h('button',{class:'primary',onclick:submit},'Send');   // (the section's buttons wait while it sends)
    const form=h('div',{class:'field editing'},h('label',{for:'vtValue'},'Valve type (as it really is)'),inp,
      h('div',{style:'margin-top:8px'},sendBtn,' ',
        h('button',{class:'ghost',onclick:()=>{ form.remove(); btns.style.display='' }},'Cancel')));
    btns.style.display='none'; sec.append(form); inp.focus(); inp.select();
  }
  return sec;
}
function cfRow(k,v,ro,by){
  const row=h('div',{class:'cf',style:ro&&k===DESC_KEY?'display:none':null},h('input',{placeholder:'Field',value:k??'',readonly:!!ro}),h('input',{placeholder:'Value',value:v??'',readonly:!!ro}),
    h('button',{class:'x',style:ro?'display:none':null,onclick:()=>row.remove()},'×'),by?h('div',{class:'by'},by):null);
  return row;
}
function fld(id,label,val,o={}){
  const a={id,readonly:true,placeholder:'—','data-ph':o.ph||''};   // the hint only once it is being edited
  return h('div',{class:'field lock'},h('label',{for:id},label,o.by&&val?[' ',h('span',{class:'by'},'· '+o.by)]:null),h('div',{class:'lk'},
    o.area?h('textarea',{...a,rows:2},val||''):h('input',{...(o.type==='number'?{type:'number',inputmode:'numeric',min:0,max:10,step:1}:{}),...a,value:val||''}),
    h('button',{class:'pen',onclick:()=>unlock(id),title:`Edit ${label}`,'aria-label':`Edit ${label}`},'✎')));
}
function unlock(id){ const el=document.getElementById(id); el.readOnly=false; el.placeholder=el.dataset.ph||''; el.closest('.field').classList.add('editing'); el.focus(); $('#eqSave').style.display='' }
function unlockCustom(){ const c=$('#cfs'); c.closest('.field').classList.add('editing'); c.querySelector('.cfnone')?.remove();
  c.querySelectorAll('input').forEach(i=>i.readOnly=false); c.querySelectorAll('.x').forEach(b=>b.style.display=''); $('#cfAdd').style.display=''; $('#eqSave').style.display='' }
function closePanel(){ $('#panel').classList.remove('open'); selId=null; selTag=null; drawTags() }
// The phone's Back button (Android app): close what is open first, one thing at a time; false = nothing left to close.
K.back = () => {
  if (K.lightbox.isOpen?.()) { K.lightbox.close(); return true }
  if ($('#panel').classList.contains('open')) { closePanel(); return true }
  const d = document.querySelector('.drawer.open');
  if (d) { closeDrawer(d, true); return true }
  if (multi.on) { pickMode(false); return true }
  return false;
};
function cropStyle(t){ const S=SHEETS.find(s=>s.id===t.sheet), b=t.bbox, w=b[2]-b[0]+20, h=b[3]-b[1]+20, sc=Math.min(360/w,64/h);
  // v1: the sheet PNG; v2: level 0 of the pyramid, filled in by the watcher below (it may need decoding first)
  const bg=S.levels?'':`background-image:url("${encodeURI(S.file)}");`;
  return bg+`background-size:${S.w*sc}px auto;background-position:${-(b[0]-10)*sc}px ${-(b[1]-10)*sc}px;width:${Math.min(360,w*sc)}px` }
const cropBg={};
function cropUrl(id){ return cropBg[id]??=K.jxl.native().then(n=>{ const u=sheetFile(id,'.o0.jxl'); return n?u:K.jxl.url(u) }) }
new MutationObserver(()=>document.querySelectorAll('.crop[data-sheet]:not([data-bg])').forEach(el=>{
  el.dataset.bg='1'; const S=SHEETS.find(x=>x.id===el.dataset.sheet);
  if(S?.levels) cropUrl(S.id).then(u=>{ el.style.backgroundImage=`url("${u}")` }).catch(e=>console.warn('crop',e)) }))
  .observe(document.body,{childList:true,subtree:true});
const P0=k=>panelEq?.k===k?panelEq.shown:{...eq(k),...myPendingEq(k)};
async function saveEq(k){
  const v=id=>document.getElementById(id).value.trim();
  const custom=[...document.querySelectorAll('#cfs .cf')].map(r=>({k:r.children[0].value.trim(),v:r.children[1].value.trim()})).filter(c=>c.k||c.v);
  const now={area:v('f_area'),floor:v('f_floor'),elev:v('f_elev'),near:v('f_near'),loc:v('f_loc'),notes:v('f_notes'),custom};
  if(now.floor!==(P0(k).floor||'')&&!/^(\d|10)$/.test(now.floor)&&now.floor!==''){ toast('Floor: a whole number from 0 to 10 (the height goes in Elevation)'); return }
  // send only fields changed in the form (which shows your own pending values), each with the live value you saw,
  // so the server can merge edits to different fields and flag real clashes
  const P=panelEq?.k===k?panelEq:{live:eq(k),shown:{...eq(k),...myPendingEq(k)}}, def=f=>f==='custom'?[]:'', changes={}, was={};
  for(const f in now) if(JSON.stringify(now[f])!==JSON.stringify(P.shown[f]??def(f))){ changes[f]=now[f]; was[f]=P.live[f]??def(f) }
  if(!Object.keys(changes).length){ toast('Nothing changed'); return }
  const r=await send('equipment',{kks:k,changes,base:was},k,document.getElementById('f_rnote')?.value.trim());
  if(r) panelEq={k,live:r.status==='approved'?{...P.live,...changes}:P.live,shown:{...P.shown,...changes}};
}
async function review(id,status){
  const kv=($('#rvK')?.value||'').trim().toUpperCase().replace(/\s/g,''), iv=($('#rvI')?.value||'').trim().toUpperCase();
  let d={status};
  if(status==='confirmed'){ const m=kv.match(/^(\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3})([A-Z0-9]*)$/); if(!m){toast('That is not a valid KKS (e.g. 11LAB70AA501)');return}
    d={status,kks:m[1],suffix:m[2],isa:iv||null} }
  const r=await send('review',{tag_id:id,data:d,base:STATE.reviews[id]||null},status==='confirmed'?`${d.kks}${d.suffix}`:'not a tag'); if(!r) return;
  renderReview(); const t=TAGS.find(x=>x.id===id);
  if(r.status==='approved'){ if(status==='confirmed') select(eff(t)); else closePanel() }
}
async function addPhoto(input,k,plate){
  const f=input.files[0]; input.value=''; if(!f) return;
  // no floor for this code yet: the one typed above the buttons goes with the photo (written first, PROTOCOL-v2 §9)
  const fl=floorKnown(k)?'':($('#phFloor')?.value||'').trim();
  if(!floorKnown(k)&&!/^(\d|10)$/.test(fl)){ toast('The floor first: a whole number from 0 to 10'); return }
  const a=await photoCanvas(f); if(!a) return;
  // queued at once (kept on this device), converted in the background, sent in order: closing the panel stops nothing
  try{ await K.queuePhoto(a.canvas,{kks:k,...(plate?{caption:'Tag plate'}:{}),...(fl?{floor:fl}:{})},a.note) }
  catch(e){ toast('Not saved: '+e.message); return }
  toast(`${plate?'Tag plate photo':'Photo'} for ${k}: converting, then sent`);
  if(selTag&&full(selTag)===k&&!$('#panel').querySelector('.editing')) reselect();
}
// a picture file → scaled and marked up in the editor -> {canvas, note} or null
async function photoCanvas(f){
  const img=new Image(), url=URL.createObjectURL(f);
  try{ await new Promise((ok,no)=>{img.onload=ok;img.onerror=()=>no(new Error('That file could not be read as a picture.'));img.src=url}) }
  catch(e){ toast(e.message); return null } finally{ URL.revokeObjectURL(url) }
  const m=1600,s=Math.min(1,m/Math.max(img.width,img.height)),c=document.createElement('canvas');
  c.width=Math.round(img.width*s); c.height=Math.round(img.height*s); c.getContext('2d').drawImage(img,0,0,c.width,c.height);
  return K.annotate(c.toDataURL('image/png'),!canApprove());   // mark what matters, or just "Use photo"
}
// a picture file → marked up and encoded as the server wants it, for a photo of several codes at once (sent at once,
// not queued: /api/submit-many) -> {dataUrl, note} or null
async function photoData(f){
  const a=await photoCanvas(f);
  if(!a) return null;
  const up=K.cfg?.photo_upload||{type:'image/jpeg',q:0.85};
  const mp=a.canvas.width*a.canvas.height/1e6;
  let dataUrl;
  if(up.type==='image/jxl'){   // the server stores JPEG XL only: encode here (decision 0037)
    const bar=K.progress('Converting the photo to JPEG XL…',(up.ms_per_mp||2500)*mp);
    try{ dataUrl=await K.jxlEncode(a.canvas,up.distance||1.9,up.effort||7) }catch(e){ bar.done(); toast(e.message); return null }
    bar.done();
  } else {                     // the v1 server and the app convert it themselves (server/photos.py, the app's libjxl)
    const bar=up.ms_per_mp?K.progress('Converting the photo to JPEG XL…',up.ms_per_mp*mp+(up.type==='image/png'?0:1500)):null;
    dataUrl=a.canvas.toDataURL(up.type,up.q); bar?.done();
  }
  return {dataUrl,note:a.note};
}
async function delPhoto(pid,tid){
  const a=await K.ask('Delete this photo?',canApprove()?'':'An admin decides.',!canApprove(),'Delete'); if(!a) return;
  if(await send('photo_delete',{photo_id:pid},'delete photo',a.note)) select(eff(TAGS.find(x=>x.id===tid)));
}
const lightbox=src=>K.lightbox(src);   // pinch / wheel zoom, drag to pan (common.js)

// ---------- several tags at once: one photo, place or note for all their codes (/api/submit-many) ----------
// The "Select tags" mode: a click (or Enter / Space on a focused tag) toggles a tag's code, a dragged box adds every
// tag it touches; every tag showing a selected code gets the ring. The bar under the drawing sends to all of them.
const multi={on:false,codes:[],saidUnread:false,start:null,box:null};
const PLACE_FIELDS=[['area','Building / area','a building / area'],['floor','Floor','a floor'],['elev','Elevation','an elevation'],
                    ['near','Near / landmark','a landmark'],['loc','How to find it','directions']];
const nCodes=n=>n+' code'+(n===1?'':'s');
function pickMode(on){
  if(on===multi.on) return;
  if(on){ if(mark.on) markMode(false); if(linkTarget){ linkTarget=null; $('#banner').style.display='none' } }
  multi.on=on; multi.codes=[]; multi.saidUnread=false; pickBox(null);
  $('#viewer').classList.toggle('selecting',on); $('#zpick').classList.toggle('on',on); $('#zpick').setAttribute('aria-pressed',String(on));
  $('#pickbar').classList.toggle('open',on); document.body.classList.toggle('picking',on); $('#pickCount').textContent='0 selected';
  if(cur) drawTags();
}
// the ring and aria-pressed follow the codes, in place (a redraw would take the focus off the tag)
function updatePick(){
  $('#pickCount').textContent=multi.codes.length+' selected';
  const on=new Set(multi.codes);
  for(const d of $('#layer').querySelectorAll('.hs[data-id]')){ const p=!!d.dataset.k&&on.has(d.dataset.k);
    d.classList.toggle('picked',p); d.setAttribute('aria-pressed',String(p)) }
}
function unreadOnce(){ if(!multi.saidUnread){ multi.saidUnread=true; toast("Tags without a code can't be selected: review them first") } }
// at most this many codes in one selection: the server takes up to 200 per submit-many (core submitMany), and a set it
// refused while queued offline would be dropped from the outbox
const MAX_PICK=200;
const fullOnce=()=>toast(`At most ${MAX_PICK} tags at once: send these first`);
function togglePick(t){
  const k=full(t); if(!k){ unreadOnce(); return }
  const i=multi.codes.indexOf(k); if(i>=0) multi.codes.splice(i,1); else if(multi.codes.length<MAX_PICK) multi.codes.push(k); else fullOnce();
  updatePick();
}
// the dragged box (sheet units), drawn while it moves; null removes it
function pickBox(p){
  if(!p){ multi.start=null; multi.box=null; $('#selbox')?.remove(); return }
  const a=multi.start.p, b=multi.box=[Math.min(a.x,p.x),Math.min(a.y,p.y),Math.max(a.x,p.x),Math.max(a.y,p.y)];
  let el=$('#selbox'); if(!el){ el=document.createElement('div'); el.id='selbox'; $('#layer').appendChild(el) }
  el.style.cssText=`left:${b[0]}px;top:${b[1]}px;width:${b[2]-b[0]}px;height:${b[3]-b[1]}px`;
}
// every tag on this sheet whose box intersects b: added (never removed)
function addBox(b){
  const hidden=document.body.classList.contains('hide-review');
  let added=0, unread=false, full_=false;
  for(const t of tagsOf(cur.id)){
    const r=t.bbox; if(hidden&&t.status==='review') continue;
    if(!(r[0]<=b[2]&&r[2]>=b[0]&&r[1]<=b[3]&&r[3]>=b[1])) continue;
    const k=full(t); if(!k){ unread=true; continue }
    if(!multi.codes.includes(k)){ if(multi.codes.length>=MAX_PICK){ full_=true; break } multi.codes.push(k); added++ }
  }
  if(unread) unreadOnce(); if(full_) fullOnce();
  updatePick();
}
function dialog(title,...kids){
  const d=h('dialog',{class:'multi','aria-labelledby':'dlgT'},h('h2',{id:'dlgT'},title),kids);
  d.addEventListener('close',()=>d.remove()); document.body.appendChild(d); d.showModal(); return d;
}
const dlgButtons=(d,label,go)=>h('div',{class:'btns'},h('button',{type:'button',class:'ghost',onclick:()=>d.close()},'Cancel'),
  h('button',{type:'button',class:'primary','data-send':'',onclick:go},label));
// the drawings a code is on (their names, in the sheets' order), and what it is
const sheetsOf=k=>{ const ids=new Set(TAGS.map(eff).filter(x=>x&&full(x)===k).map(x=>x.sheet)); return SHEETS.filter(s=>ids.has(s.id)).map(s=>s.name) };
// codes typed or pasted (spaces, commas, semicolons or new lines between them): each one that is on a drawing joins the
// selection, up to MAX_PICK -> {added, unknown: not on any drawing, over: left out by the limit}
function addCodes(text){
  const known=new Set(TAGS.map(eff).filter(Boolean).map(full).filter(Boolean));
  const out={added:[],unknown:[],over:[]};
  for(const k of new Set(text.toUpperCase().split(/[\s,;]+/).filter(Boolean))){
    if(!known.has(k)) out.unknown.push(k);
    else if(multi.codes.includes(k)) continue;
    else if(multi.codes.length>=MAX_PICK) out.over.push(k);
    else{ multi.codes.push(k); out.added.push(k) }
  }
  updatePick();
  return out;
}
function pickList(){
  const where=k=>{ const t=TAGS.map(eff).find(x=>x&&full(x)===k); return t?kindName(t)+' · '+sheetsOf(k).join(', '):'' };
  const list=h('div',{id:'pickCodes'});
  const draw=()=>{ const codes=[...multi.codes];
    put(list,codes.length?[h('p',{class:'sub',style:'margin:0'},'Untick a code to leave it out.'),
      h('ul',null,codes.map(k=>h('li',null,h('label',null,h('input',{type:'checkbox',checked:true,onchange:e=>{
        const on=e.currentTarget.checked, i=multi.codes.indexOf(k);
        if(on&&i<0){ if(multi.codes.length>=MAX_PICK){ e.currentTarget.checked=false; fullOnce(); return } multi.codes.push(k) }
        else if(!on&&i>=0) multi.codes.splice(i,1);
        updatePick() }}),h('span',{class:'mono'},k),h('span',{class:'sub'},where(k))))))]
      :h('p',null,'Nothing selected yet: click tags on the drawing, drag a box around several, pick search results, or add codes below.')) };
  draw();
  const said=h('div',{class:'warn',id:'pickAddSaid',role:'status',style:'display:none'});
  const ta=h('textarea',{id:'pickAddText',rows:2,class:'mono',placeholder:'11LAB70AA501, 11LAB70AA502 …'});
  const add=()=>{ const r=addCodes(ta.value); if(!r.added.length&&!r.unknown.length&&!r.over.length&&!ta.value.trim()){ toast('Type the codes first'); return }
    const L=[];
    if(r.added.length) L.push(`Added ${nCodes(r.added.length)}.`);
    if(r.unknown.length) L.push(`Not on any drawing, not added: ${r.unknown.slice(0,20).join(', ')}${r.unknown.length>20?` and ${r.unknown.length-20} more`:''}.`);
    if(r.over.length) L.push(`At most ${MAX_PICK} at once, not added: ${r.over.slice(0,20).join(', ')}${r.over.length>20?` and ${r.over.length-20} more`:''}.`);
    if(!L.length) L.push('Already selected.');
    said.textContent=L.join(' '); said.style.display='';
    ta.value=r.unknown.concat(r.over).join(' ');     // what was not added stays, to be corrected
    draw() };
  const d=dialog('Selected codes',list,
    h('div',{class:'field',style:'margin-top:10px'},h('label',{for:'pickAddText'},'Add codes (from any drawing)'),ta,
      h('div',{class:'sub'},'Type or paste KKS codes, separated by spaces, commas or new lines.')),said,
    h('div',{class:'btns'},h('button',{type:'button',class:'ghost',id:'pickAddBtn',onclick:add},'Add codes'),
      h('button',{type:'button',class:'primary',onclick:()=>d.close()},'Close')));
  d.querySelector('input,textarea,button')?.focus();
}
// one submit-many for the selected codes; says how it went and leaves the mode. `codes`: the selection as it was when
// the person was asked (a photo is converted for seconds after its dialog closed, and the drawing stays live meanwhile)
async function sendMany(kind,payload,note,codes=[...multi.codes]){
  if(!codes.length){ toast('Nothing selected'); return false }
  if(kind==='equipment'){
    // the values this page shows for the fields it changes: a value someone changed meanwhile (or before an offline
    // send goes out) is then a clash (core submitMany bases), not overwritten silently
    const fields=Object.keys(payload.changes||{});   // replaced fields only: an appended note can't lose anything
    payload={...payload,bases:Object.fromEntries(codes.map(k=>[k,Object.fromEntries(fields.map(f=>[f,(STATE.equipment?.[k]||{})[f]??'']))]))};
  }
  let r; try{ r=await K.submitMany(kind,codes,payload,note) }catch(e){ toast('Not saved: '+e.message); return false }
  pickMode(false);
  if(r.status==='queued'){ toast(`Offline, queued for ${nCodes(codes.length)}`); updatePending(); drawTags(); return true }
  const st=(r.results||[]).map(x=>x.status), held=st.filter(x=>x==='conflict').length, waiting=st.filter(x=>x!=='approved'&&x!=='conflict').length;
  // said once the page knows what was sent (said first, a quick "Photo for all" still asked for a floor just sent).
  // A refresh that fails, or takes more than 5 s, doesn't hide the send
  await Promise.race([refreshState().catch(e=>console.warn('refresh after send',e)),new Promise(r=>setTimeout(r,5000))]);
  toast(`Sent for ${nCodes(codes.length)}`+(waiting?` · ${waiting} await approval`:'')+(held?` · ${held} held (they clash with pending changes)`:''));
  return true;
}
const approverNote=()=>canApprove()?null:h('div',{class:'field'},h('label',{for:'dlgNote'},'Note for the approver (optional)'),h('input',{id:'dlgNote',maxlength:500}));
const noteValue=d=>d.querySelector('#dlgNote')?.value.trim()||'';
function pickNothing(){ if(multi.codes.length) return false; toast('Select tags first'); return true }
// the codes of a selection with no floor known: the floor asked for them. A floor riding on a photo in the outbox
// doesn't count here (#144): this photo keeps one floor for all its codes, so a code left out of the question would get
// another code's floor when that photo is refused and kept, or none once it is discarded. Such a code is asked again.
const floorless=codes=>codes.filter(k=>!floorKnown(k,false));
const floorAsk=(missing,all)=>`Floor for ${missing.slice(0,5).join(', ')}${missing.length>5?` and ${missing.length-5} more`:''}: `+
  (missing.length===all?(all===1?'it has none yet':'they have none yet'):(missing.length===1?'this one has':'these have')+' none yet; the others keep theirs');
function photoForAll(){
  if(pickNothing()) return;
  // the user's rule, as for one photo: the floor first when a code has none, sent with the photo (core submitMany
  // writes it for the codes without one only; nobody has to wait for an approval before the photo)
  const codes=[...multi.codes], missing=floorless(codes), okFloor=v=>/^(\d|10)$/.test(v.trim());
  const choose=h('label',{class:'primary',id:'dlgChoose',style:'cursor:pointer'+(missing.length?';display:none':'')},'Choose photo…',h('input',{type:'file',id:'dlgFile',accept:'image/*',capture:'environment',style:'display:none',
    onchange:async ev=>{ const f=ev.currentTarget.files[0], caption=$('#dlgCaption').value.trim(), fl=missing.length?$('#dlgFloor').value.trim():'';
      if(missing.length&&!okFloor(fl)){ ev.currentTarget.value=''; toast('The floor first: a whole number from 0 to 10'); return }
      d.close(); if(!f) return;
      const p=await photoData(f); if(p) await sendMany('photo',{dataUrl:p.dataUrl,caption,...(fl?{floor:fl}:{})},p.note,codes) }}));
  const d=dialog('Photo for all',
    h('p',{class:'sub',style:'margin:0 0 8px'},`One photo for ${nCodes(codes.length)}: it is kept once, every code gets it.`),
    missing.length?h('div',{class:'field'},h('label',{for:'dlgFloor',id:'dlgFloorLabel'},floorAsk(missing,codes.length)),
      h('input',{id:'dlgFloor',type:'number',inputmode:'numeric',min:0,max:10,step:1,placeholder:'0–10',style:'width:90px',
        oninput:e=>{ choose.style.display=okFloor(e.currentTarget.value)?'':'none' }}),
      h('div',{class:'sub'},'A photo needs its floor: a whole number from 0 (ground) to 10. It is sent with the photo.')):null,
    h('div',{class:'field'},h('label',{for:'dlgCaption'},'Caption (optional)'),h('input',{id:'dlgCaption',maxlength:200,placeholder:'e.g. Tag plate, or what the photo shows'}),
      h('div',{class:'sub'},'A caption starting “Tag plate” marks a photo of the tag plate.')),
    h('div',{class:'btns'},h('button',{type:'button',class:'ghost',onclick:()=>d.close()},'Cancel'),choose));
  $(missing.length?'#dlgFloor':'#dlgCaption').focus();
}
function placeForAll(){
  if(pickNothing()) return;
  let confirmed='';
  const read=()=>{ const ch={}; for(const [f] of PLACE_FIELDS){ const v=d.querySelector('#dlg_'+f).value.trim(); if(v) ch[f]=v } return ch };
  // how many codes already have a value in each filled field that differs: it will be replaced
  const replaced=ch=>Object.entries(ch).map(([f,v])=>{ const n=multi.codes.filter(k=>{ const c=eq(k)[f]; return typeof c==='string'&&c.trim()&&c.trim()!==v }).length;
    return n?`${n} of ${nCodes(multi.codes.length)} already ${n===1?'has':'have'} ${PLACE_FIELDS.find(x=>x[0]===f)[2]}; it will be replaced.`:null }).filter(Boolean);
  const warn=h('div',{class:'warn',role:'status',style:'display:none'});
  const update=()=>{ const L=replaced(read()); warn.textContent=L.join(' '); warn.style.display=L.length?'':'none';
    if(confirmed!==JSON.stringify(read())){ confirmed=''; d.querySelector('[data-send]').textContent='Send' } };
  const d=dialog('Place for all',
    h('p',{class:'sub',style:'margin:0 0 8px'},`For ${nCodes(multi.codes.length)}. Only the fields you fill are sent; the others stay as they are for each code.`),
    PLACE_FIELDS.map(([f,label])=>h('div',{class:'field'},h('label',{for:'dlg_'+f},label),
      f==='loc'?h('textarea',{id:'dlg_'+f,rows:2,oninput:update}):h('input',{id:'dlg_'+f,oninput:update,...(f==='floor'?{type:'number',inputmode:'numeric',min:0,max:10,step:1,placeholder:'0–10'}:{})}))),
    approverNote(),warn);
  d.append(dlgButtons(d,'Send',async()=>{
    const ch=read();
    if(!Object.keys(ch).length){ toast('Fill at least one field'); return }
    if('floor' in ch&&!/^(\d|10)$/.test(ch.floor)){ toast('Floor: a whole number from 0 to 10 (the height goes in Elevation)'); return }
    const key=JSON.stringify(ch);
    if(replaced(ch).length&&confirmed!==key){   // said above the button; the second press sends
      confirmed=key; d.querySelector('[data-send]').textContent='Replace and send'; return }
    if(await sendMany('equipment',{changes:ch},noteValue(d))) d.close() }));
  $('#dlg_area').focus();
}
function noteForAll(){
  if(pickNothing()) return;
  const d=dialog('Note for all',
    h('p',{class:'sub',style:'margin:0 0 8px'},`For ${nCodes(multi.codes.length)}. Added under each code's own notes; nothing already there is removed.`),
    h('div',{class:'field'},h('label',{for:'dlgText'},'Note'),h('textarea',{id:'dlgText',rows:3})),
    approverNote());
  d.append(dlgButtons(d,'Send',async()=>{
    const v=$('#dlgText').value.trim(); if(!v){ toast('Write the note first'); return }
    if(await sendMany('equipment',{append:{notes:v}},noteValue(d))) d.close() }));
  $('#dlgText').focus();
}
$('#zpick').onclick=()=>pickMode(!multi.on);
$('#pickDone').onclick=()=>{ pickMode(false); $('#zpick').focus() };
$('#pickList').onclick=pickList; $('#pickPhoto').onclick=photoForAll; $('#pickPlace').onclick=placeForAll; $('#pickNote').onclick=noteForAll;
// Escape leaves the mode (a dialog's Escape closes the dialog only)
document.addEventListener('keydown',e=>{ if(e.key==='Escape'&&multi.on&&!document.querySelector('dialog[open]')&&
  (e.target===document.body||e.target.closest?.('#viewer,#pickbar,.zoom'))){ pickMode(false); $('#zpick').focus() } });

// ---------- search ----------
let hits=[],hi=0;
$('#q').addEventListener('input',()=>{
  const q=$('#q').value.trim().toUpperCase().replace(/\s+/g,''), qr=$('#q').value.trim().toLowerCase(), R=$('#results');
  if(q.length<2){R.style.display='none';$('#q').setAttribute('aria-expanded','false');return}
  const seen=new Set(); hits=[];
  for(const t0 of TAGS){ const t=eff(t0); if(!t)continue; const k=full(t); const e=eq(k);
    const text=[e.area,e.floor,e.loc,e.near,e.notes,...(e.custom||[]).map(c=>c.k+' '+c.v),
      ...(LOC[bodyOf(t)]||[]).map(r=>[r.cabinet,r.desc,r.direction,lvlName(r.level)].join(' '))].join(' ').toLowerCase();
    let score=0;
    if(k&&k===q)score=100; else if(k&&k.startsWith(q))score=80; else if(k&&k.includes(q))score=60; else if(t.isa&&t.isa===q)score=30; else if(qr.length>2&&text.includes(qr))score=40;
    if(!score&&t.status==='review'&&(t.read.join('').includes(q)))score=10;
    if(score){ hits.push({t,score,k}) } }
  const drawn=new Set(TAGS.map(eff).filter(Boolean).map(bodyOf)), qb=q.replace(/^\d{2}(?=[A-Z])/,'');
  for(const b in LOC){ if(drawn.has(b))continue; const text=LOC[b].map(r=>[r.cabinet,r.desc,r.direction].join(' ')).join(' ').toLowerCase();
    const score=b===qb?90:b.startsWith(qb)?70:b.includes(qb)?50:qr.length>2&&text.includes(qr)?35:0; if(score)hits.push({loc:b,score,k:b}) }
  hits.sort((a,b)=>b.score-a.score||a.k.localeCompare(b.k)); hits=hits.slice(0,60); hi=0;
  const sn=id=>SHEETS.find(s=>s.id===id).name;
  put(R,hits.length?hits.map((x,i)=>{ const opt={class:'res'+(i===0?' on':''),role:'option',id:'res-'+i,'aria-selected':String(i===0),onclick:()=>pick(i)};
    if(x.loc){const r=refLoc(x.loc);return h('div',opt,h('div',{class:'k'},x.loc+' ',h('span',{class:'m',style:'color:var(--review)'},'location list only')),
      h('div',{class:'m'},(r.elev||'level varies')+(r.cabinet?' · '+r.cabinet:'')+(r.rows[0].desc?' · '+r.rows[0].desc:'')))}
    const e=eq(x.k), fl=floorOf(x.t), cab=refLoc(bodyOf(x.t)).cabinet;
    return h('div',opt,h('div',{class:'k'},x.k||x.t.read.join(' / '),x.t.isa?[' ',h('span',{class:'m'},x.t.isa)]:null,x.t.status==='review'?[' ',h('span',{class:'m',style:'color:var(--review)'},'unverified')]:null),
      h('div',{class:'m'},`${sn(x.t.sheet)} · ${kindName(x.t)??''}`+(fl?' · '+floorName(fl):'')+(cab?' · '+cab:'')+(e.area?' · '+e.area:'')))})
    :h('div',{class:'res m',role:'option','aria-disabled':'true'},'No match. It may be on a sheet not loaded yet, or still in the review queue under a misread.'));
  R.style.display='block';
  $('#q').setAttribute('aria-expanded','true'); $('#q').setAttribute('aria-activedescendant', hits.length?'res-0':'');
});
$('#q').addEventListener('keydown',e=>{ const R=$('#results');
  if(e.key==='ArrowDown'||e.key==='ArrowUp'){ hi=Math.max(0,Math.min(hits.length-1,hi+(e.key==='ArrowDown'?1:-1)));
    [...R.children].forEach((c,i)=>{ c.classList.toggle('on',i===hi); c.setAttribute('aria-selected', String(i===hi)) });
    $('#q').setAttribute('aria-activedescendant','res-'+hi); R.children[hi]?.scrollIntoView({block:'nearest'}); e.preventDefault() }
  if(e.key==='Enter'&&hits.length) pick(hi); if(e.key==='Escape'){ R.style.display='none'; $('#q').setAttribute('aria-expanded','false') } });
// a pick moves keyboard focus into the panel it opens (screen readers then read the equipment)
let focusPanel=false;
function pick(i){ $('#results').style.display='none'; $('#q').setAttribute('aria-expanded','false');
  if(multi.on){ pickHit(hits[i]); return }      // Select tags: the result joins the selection, the drawing stays
  focusPanel=true; hits[i].loc?selectLoc(hits[i].loc):goTo(hits[i].t.id) }
// a search result picked in the "Select tags" mode: its code is added (from any drawing), nothing else moves
function pickHit(x){
  if(x.loc){ toast(`${x.loc} is in the location list only, not on a drawing: it can't be selected`); return }
  const k=full(x.t); if(!k){ unreadOnce(); return }
  if(multi.codes.includes(k)){ toast(`${k} is already selected`); return }
  if(multi.codes.length>=MAX_PICK){ fullOnce(); return }
  multi.codes.push(k); updatePick();
  const here=TAGS.map(eff).some(t=>t&&t.sheet===cur?.id&&full(t)===k);
  toast(`${k} selected`+(here?'':` (on ${sheetsOf(k).join(', ')})`)+` · ${multi.codes.length} selected`);
}
document.addEventListener('click',e=>{ if(!e.target.closest('.search')) $('#results').style.display='none' });

// ---------- floors ----------
function refreshFloors(){
  const num=f=>{const n=parseFloat(f); return isNaN(n)?1e9:n};
  const fl=[...new Set(Object.values(STATE.equipment).map(e=>(e.floor||'').trim()).filter(Boolean))]
    .sort((a,b)=>num(a)-num(b)||a.localeCompare(b));
  put($('#floorSel'),h('option',{value:''},'All floors'),fl.map(f=>h('option',{value:f,selected:f===floor},floorName(f))));
  let dl=$('#floors'); if(!dl){dl=document.createElement('datalist');dl.id='floors';document.body.appendChild(dl)} put(dl,fl.map(f=>h('option',{value:f})));
}
$('#floorSel').onchange=e=>{ floor=e.target.value; drawTags();
  if(floor){ const n=TAGS.map(eff).filter(t=>t&&floorOf(t).toLowerCase()===floor.toLowerCase()); const here=n.filter(t=>t.sheet===cur.id).length;
    toast(`${n.length} tagged on ${floorName(floor)} (${here} on this sheet)`) } };

// ---------- procedures ----------
function renderProcs(){
  const q=$('#procQ').value.trim().toLowerCase(), out=[]; let last='';
  for(const p of PROCS){
    const txt=(p.id+' '+p.title+' '+p.path.join(' ')+' '+p.steps.map(s=>s.text).join(' ')).toLowerCase(); if(q&&!txt.includes(q))continue;
    const ch=p.path[0]||p.title; if(ch!==last){out.push(h('div',{class:'chapter'},ch)); last=ch}
    const n=STATE.links.filter(l=>l.proc===p.id).length;
    out.push(h('div',{class:'proc',onclick:()=>openProc(p.id)},h('span',{class:'id'},p.id),p.title,' ',h('span',{class:'path'},`· ${p.steps.length} steps${n?` · ${n} linked`:''}`)));
  }
  put($('#procBody'),out.length?out:h('div',{class:'sub'},'No procedure matches.'));
}
$('#procQ').oninput=renderProcs;
function openProc(id){ openDrawer('procDrawer'); activeProc=id; renderProcDetail(id); drawTags() }
function renderProcDetail(id){
  const p=PROCS.find(x=>x.id===id); const L=STATE.links.filter(l=>l.proc===id);
  const byKks=k=>TAGS.map(eff).filter(t=>t&&full(t)===k);
  const counts={}; for(const l of L) for(const t of byKks(l.kks)) counts[t.sheet]=(counts[t.sheet]||0)+1;
  const out=[h('button',{class:'ghost',onclick:()=>{ activeProc=null; renderProcs(); drawTags() }},'← All procedures'),
    h('h3',{style:'margin:12px 0 2px'},`${p.id} ${p.title??''}`),h('div',{class:'sub'},`${p.path.join(' › ')} · ${p.source?p.source:`manual page ${p.page??'?'}`}`)];
  if(Object.keys(counts).length) out.push(h('div',{style:'margin:8px 0'},'Linked equipment on: ',
    Object.entries(counts).map(([s,n])=>h('span',{class:'chip',onclick:()=>openSheet(s)},`${SHEETS.find(x=>x.id===s).name} (${n})`))));
  else out.push(h('div',{class:'warn'},'No equipment linked yet. The manual names equipment by description, not KKS — tap “Link equipment” on a step, then tap the matching tags on the drawing. You do this once per step.'));
  for(const s of p.steps){
    const ls=L.filter(l=>l.step===s.n);
    out.push(h('div',{class:'step'},h('span',{class:'n'},`${s.n})`),s.text,h('div',{style:'margin-top:5px'},
      ls.map(l=>{const t=byKks(l.kks)[0];return [h('span',{class:'chip mono',onclick:()=>{ if(t) goTo(t.id) }},l.kks),
        h('button',{class:'x',style:'font-size:14px',title:'Unlink','aria-label':`Unlink ${l.kks}`,onclick:()=>unlink(id,+s.n,l.kks)},'×')]}),
      ' ',h('button',{class:'ghost',style:'font-size:12.5px;padding:3px 8px',onclick:()=>startLink(id,+s.n)},'+ Link equipment'))));
  }
  put($('#procBody'),out);
}
function startLink(proc,step){ pickMode(false); linkTarget={proc,step}; $('#bannerText').textContent=`Tap tags on the drawing to link them to step ${step}`; $('#banner').style.display='flex';
  if(innerWidth<=720) $('#procDrawer').classList.remove('open') }
$('#bannerDone').onclick=()=>{ if(mark.on){ markMode(false); closePanel(); return } const p=linkTarget?.proc; linkTarget=null; $('#banner').style.display='none'; if(p){openDrawer('procDrawer'); renderProcDetail(p)} };
async function unlink(proc,step,kks){ await send('link',{proc,step,kks,on:false},`unlink ${kks}`); renderProcDetail(proc); drawTags() }

// ---------- equipment by system (core views.systemsView, ported in systems.js) ----------
// While filtering, every level opens when few codes match; otherwise blocks open and systems closed.
const SYS_OPEN_ALL=300;
function renderSystems(){
  sysStale=false;
  const q=$('#sysQ').value.trim();
  const v=KSys.systemsView({tags:TAGS.map(eff).filter(Boolean),sheets:SHEETS,kks:KKS,loc:LOC,photos:STATE.photos},q);
  if(sysOnly){   // one system (from Coverage), in every block; SYS_OTHER = the codes that don't decode
    v.blocks=v.blocks.map(b=>({...b,systems:b.systems.filter(s=>s.sys===sysOnly)})).filter(b=>b.systems.length);
    if(sysOnly!==SYS_OTHER) v.other=[];
    v.total=v.blocks.reduce((a,b)=>a+b.systems.reduce((c,s)=>c+s.count,0),0)+v.other.length;
  }
  const all=(q!==''||!!sysOnly)&&v.total<=SYS_OPEN_ALL;
  const sum=(label,n)=>h('summary',null,label,' ',h('span',{class:'c'},`(${n})`));
  const row=it=>h('button',{type:'button',class:'sysrow','data-tag':it.tag,onclick:()=>{ focusPanel=true; if(innerWidth<=720){ $('#sysDrawer').classList.remove('open'); $('#sysBtn').setAttribute('aria-expanded','false') } goTo(it.tag) }},
    h('span',{class:'sysdot p-'+it.photos,'aria-hidden':'true',title:COVER_WORDS[it.photos]}),
    h('span',{class:'mono'},it.code),
    h('span',{class:'d'},[it.desc,it.sheet_name].filter(Boolean).join(' · '),it.count>1?' · ×'+it.count:''),
    h('span',{class:'vh'},' · '+COVER_WORDS[it.photos]));
  const out=v.blocks.map(b=>{ const n=b.systems.reduce((a,s)=>a+s.count,0);
    return h('details',{class:'lvl-blk',open:true},sum(b.blk+(b.blk_name?' · '+b.blk_name:''),n),
      b.systems.map(s=>h('details',{class:'lvl-sys',open:all},sum(s.sys+(s.sys_name?' · '+s.sys_name:''),s.count),
        s.subsystems.map(f=>h('details',{class:'lvl-sub',open:all},sum(f.code,f.count),
          f.kinds.map(c=>h('details',{class:'lvl-kind',open:all},sum(c.comp+(c.comp_name?' · '+c.comp_name:''),c.count),c.items.map(row))))))))});
  if(v.other.length) out.push(h('details',{class:'lvl-blk lvl-other',open:all},sum('Other: codes that are not a full KKS',v.other.length),v.other.map(row)));
  put($('#sysBody'),out.length?out:h('div',{class:'sub'},q?'No code matches.':'No tags on the drawings yet.'));
  $('#sysCount').textContent=`${v.total} code${v.total===1?'':'s'}`+(sysOnly?(sysOnly===SYS_OTHER?(v.total===1?" that doesn't decode":" that don't decode"):' in system '+sysOnly):q?' match':'');
  put($('#sysOnlyBar'),sysOnly?h('button',{type:'button',class:'ghost',style:'margin-top:6px',onclick:()=>{ sysOnly=''; renderSystems(); $('#sysQ').focus() }},'Show all systems'):null);
}
const SYS_OTHER='-';
let sysT=0, sysStale=false, sysOnly='';
// a search covers every system again
$('#sysQ').oninput=()=>{ sysOnly=''; clearTimeout(sysT); sysT=setTimeout(renderSystems,120) };
function openSystem(code){ sysOnly=code||SYS_OTHER; $('#sysQ').value=''; openDrawer('sysDrawer'); renderSystems(); $('#sysQ').focus() }

// ---------- coverage (core views.coverageView, ported in systems.js) ----------
// Totals, then per sheet and per system, each with a bar of the photo coverage colours (its numbers in words beside it,
// for screen readers). A sheet opens with the tags coloured by photos; a system opens in Equipment by system.
const PHOTO_KINDS=['both','equipment','plate','none'];
const pct=(a,b)=>b?KSys.pct(a,b)+' %':'–';   // 100 % only when all, 0 % only when none
const plural=(n,one,many)=>n+' '+(n===1?one:many);
const photoWords=p=>`photos: ${p.both} equipment and tag plate, ${p.equipment} equipment only, ${p.plate} tag plate only, ${p.none} none`;
function covBar(p,wide){
  return h('span',{class:'covbar'+(wide?' wide':''),'aria-hidden':'true',title:photoWords(p)},
    PHOTO_KINDS.filter(k=>p[k]>0).map(k=>h('span',{class:'p-'+k,style:`flex:${p[k]} 0 0`})));
}
let covStale=false;
function renderCoverage(){
  covStale=false;
  const v=KSys.coverageView({tags:TAGS.map(eff).filter(Boolean),sheets:SHEETS,kks:KKS,loc:LOC,equipment:STATE.equipment,photos:STATE.photos});
  const t=v.total, p=t.photos;
  const sheetSub=s=>[plural(s.codes,'code','codes'),pct(s.verified,s.tags)+' of tags checked',pct(s.located,s.codes)+' placed',
    s.review?s.review+' to review':null,s.marked?s.marked+' marked':null].filter(Boolean).join(' · ');
  const sysSub=s=>[plural(s.codes,'code','codes'),pct(s.verified,s.codes)+' of codes checked',pct(s.located,s.codes)+' placed'].join(' · ');
  const row=(title,sub,p,onclick,label)=>h('button',{type:'button',class:'covrow',onclick,title:label},covBar(p),
    h('span',{class:'t'},title,h('span',{class:'d'},sub),h('span',{class:'vh'},' · '+photoWords(p))));
  put($('#covBody'),
    h('h3',null,'Totals'),
    h('div',{class:'sub',style:'margin-bottom:6px'},`${plural(t.codes,'code','codes')} on the drawings, in ${plural(t.tags,'tag','tags')}`),
    h('dl',{id:'covTotals'},
      h('dt',null,'Checked by a person'),h('dd',null,`${t.verified} of ${plural(t.tags,'tag','tags')} (${pct(t.verified,t.tags)})`),
      h('dt',null,'Known place'),h('dd',null,`${t.located} of ${plural(t.codes,'code','codes')} (${pct(t.located,t.codes)})`),
      h('dt',null,'Photos'),h('dd',null,covBar(p,true),h('div',null,`both ${p.both} · equipment only ${p.equipment} · tag plate only ${p.plate} · none ${p.none}`)),
      h('dt',null,'Readings to review'),h('dd',null,t.review),
      h('dt',null,'Missed tags marked'),h('dd',null,t.marked)),
    h('div',{class:'covlegend',role:'note'},'Photo colours:',PHOTO_KINDS.map(k=>[h('i',{class:'p-'+k,'aria-hidden':'true'}),
      {both:'both',equipment:'equipment only',plate:'tag plate only',none:'none'}[k]])),
    h('h3',null,'By sheet'),h('div',{class:'sub'},'Open a sheet to see its tags coloured by photos'),
    v.sheets.map(s=>row(s.name,sheetSub(s),s.photos,()=>openCovered(s.id),`Open ${s.name} coloured by photos`)),
    h('h3',null,'By system'),h('div',{class:'sub'},'Open a system in Equipment by system'),
    v.systems.length?v.systems.map(s=>row(s.sys?s.sys+(s.sys_name?' · '+s.sys_name:''):"Codes that don't decode",sysSub(s),s.photos,
      ()=>openSystem(s.sys),s.sys?`Show system ${s.sys} in Equipment by system`:"Show the codes that don't decode in Equipment by system"))
      :h('div',{class:'sub'},'No codes on the drawings yet.'));
}
function openCovered(id){
  // a hand-marked tag can outlive its sheet: its row is counted, but there is nothing to open
  if(!SHEETS.some(s=>s.id===id)){ toast('That sheet is no longer in the plant data'); return }
  if(innerWidth<=720) closeDrawer($('#covDrawer'),false);
  setCover(true);
  if(cur?.id!==id){ closePanel(); openSheet(id) }
  toast(`${SHEETS.find(s=>s.id===id)?.name||id}: tags coloured by photos`);
}
$('#covBody').addEventListener('focusout',e=>{ if(covStale&&!$('#covBody').contains(e.relatedTarget)){ covStale=false; renderCoverage() } });
$('#sysDrawer').addEventListener('focusout',e=>{ if(sysStale&&!$('#sysDrawer').contains(e.relatedTarget)){ sysStale=false; renderSystems() } });

// ---------- review queue ----------
function pending(){ return TAGS.filter(t=>t.status==='review'&&!STATE.reviews[t.id]) }
function refreshReviewCount(){ $('#revCount').textContent=pending().length }
function renderReview(){
  const P=pending(), sn=id=>SHEETS.find(s=>s.id===id).name, out=[]; let last='';
  const sorted=[...P].sort((a,b)=>(a.sheet===cur.id?0:1)-(b.sheet===cur.id?0:1)||a.sheet.localeCompare(b.sheet)||(b.suggestion?1:0)-(a.suggestion?1:0));
  for(const t of sorted.slice(0,250)){ if(t.sheet!==last){out.push(h('div',{class:'chapter'},`${sn(t.sheet)} (${P.filter(x=>x.sheet===t.sheet).length})`)); last=t.sheet}
    out.push(h('div',{class:'revitem',onclick:()=>goTo(t.id)},h('div',{class:'crop','data-sheet':t.sheet,style:cropStyle(t)}),h('span',{class:'mono'},`${t.read[0]??''} / ${t.read[1]??''}`),
      t.suggestion?[' → ',h('span',{class:'mono',style:'color:var(--accent)'},t.suggestion.kks)]:null)) }
  put($('#revBody'),out.length?out:h('div',{class:'sub'},'Nothing left to review.'));
}
$('#hideRev').onchange=e=>document.body.classList.toggle('hide-review',e.target.checked);

// ---------- notes ----------
function renderNotes(){ const n=cur.notes||[]; put($('#notesBody'),n.length?[h('div',{class:'sub'},'Text added to this PDF by markup (not part of the CAD drawing).'),n.map(x=>h('div',{class:'step'},x))]
                                                    :h('div',{class:'sub'},'No markups on this sheet.')) }

// ---------- links between drawings: the off-page connectors (systems.js KSys.linksView, a port of the core's) ----------
// Each connector is a hotspot on the drawing and a row in "Connectors on this sheet". Activating one opens where its
// line continues: one target goes there, several ask which, none says so (GNOME's links.nim).
let linkSel=null;                  // the connector just arrived at {sheet, x0, y0} (points), drawn bold
const pxScale=s=>s&&typeof s.scale==='number'&&s.scale>0?s.scale:2;   // level-0 px per point (core views: scale or 2)
const linksMemo={sheets:null,id:null,v:[]};
function linksHere(){ if(!cur) return [];
  if(linksMemo.sheets!==SHEETS||linksMemo.id!==cur.id) Object.assign(linksMemo,{sheets:SHEETS,id:cur.id,v:KSys.linksView(SHEETS,cur.id)});
  return linksMemo.v }
const targetName=t=>t.same_sheet?'elsewhere on this sheet':t.sheet_name;
function whereText(l){ const names=[...new Set(l.targets.map(targetName))];
  return names.length?'continues on '+names.join(', '):"the other end isn't on any drawing in the app" }
const linkName=l=>'Connector '+l.label+', '+whereText(l);
// the choice's buttons, one per target: the sheet's name, numbered when one sheet has the code more than once
function targetLabels(ts){ const names=ts.map(targetName), n=x=>names.filter(y=>y===x).length;
  return names.map((x,i)=>n(x)>1?`${x} (${names.slice(0,i+1).filter(y=>y===x).length} of ${n(x)})`:x) }
function goToLink(label,t){
  if(!SHEETS.some(s=>s.id===t.sheet)){ toast('Connector '+label+': that drawing is no longer in the app'); return }
  if(innerWidth<=720) $('#linksDrawer').classList.remove('open');   // full width there: the drawing must show
  const go=()=>{ const sc=pxScale(cur); linkSel={sheet:t.sheet,x0:t.x0,y0:t.y0};
    centerOn([t.x0*sc,t.y0*sc,t.x1*sc,t.y1*sc]); drawTags();
    // the list was rebuilt for the new sheet: keyboard focus goes back into it, not to the page
    if($('#linksDrawer').classList.contains('open')&&!$('#linksDrawer').contains(document.activeElement)) $('#linksBody .connrow')?.focus();
    toast('Connector '+label+' on '+(t.sheet_name||t.sheet)) };
  if(cur?.id!==t.sheet){ closePanel(); openSheet(t.sheet,go) } else go();
}
// the connector `label` at (x0, y0) of `sheet`: looked up again (a sync between showing and clicking can reorder them)
function followLink(sheet,label,x0,y0){
  const ls=KSys.linksView(SHEETS,sheet), i=KSys.findLink(ls,label,x0,y0);
  if(i<0){ toast('Connector '+label+' is no longer on this drawing'); return }
  const ts=ls[i].targets;
  if(!ts.length){ toast('Connector '+label+": the other end isn't on any drawing in the app"); return }
  if(ts.length===1){ goToLink(label,ts[0]); return }
  const labels=targetLabels(ts);
  const d=dialog('Where does '+label+' continue?',h('p',{class:'sub',style:'margin:0 0 8px'},"This connector's code appears in more than one place."),
    h('div',{class:'btns',style:'flex-wrap:wrap;justify-content:flex-start'},ts.map((t,j)=>h('button',{type:'button',class:j?'ghost':'primary',
      onclick:()=>{ d.close(); goToLink(label,t) }},labels[j]))),
    h('div',{class:'btns'},h('button',{type:'button',class:'ghost',onclick:()=>d.close()},'Cancel')));
  d.querySelector('button')?.focus();
}
function renderLinks(){
  const here=cur.id, ls=linksHere();
  put($('#linksBody'),ls.length?[h('div',{class:'sub'},'Where this sheet\'s lines continue (the circled codes on the drawing).'),
    ls.map(l=>h('button',{type:'button',class:'connrow','aria-label':linkName(l),onclick:()=>followLink(here,l.label,l.x0,l.y0)},
      h('span',{class:'mono'},'Connector '+l.label),h('span',{class:'sub'},whereText(l))))]
    :h('div',{class:'sub'},'No connectors to other drawings on this sheet.'));
}

// ---------- drawers ----------
const DRAWER_BTN={sysDrawer:'#sysBtn',covDrawer:'#covBtn'};   // buttons that say whether their drawer is open
function openDrawer(id){ document.querySelectorAll('.drawer').forEach(d=>d.classList.toggle('open',d.id===id));
  for(const d in DRAWER_BTN) $(DRAWER_BTN[d]).setAttribute('aria-expanded',String(id===d)) }
// focus: back to the drawer's button (when it has one)
function closeDrawer(d,focus){ d.classList.remove('open'); const b=DRAWER_BTN[d.id]&&$(DRAWER_BTN[d.id]);
  if(b){ b.setAttribute('aria-expanded','false'); if(focus) b.focus() } if(d.id==='procDrawer'){ activeProc=null; drawTags() } }
document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>closeDrawer($('#'+b.dataset.close),true));
$('#procBtn').onclick=()=>{ if($('#procDrawer').classList.contains('open')){$('#procDrawer').classList.remove('open');activeProc=null;drawTags()} else {openDrawer('procDrawer'); activeProc?renderProcDetail(activeProc):renderProcs()} };
$('#sysBtn').onclick=()=>{ if($('#sysDrawer').classList.contains('open')) closeDrawer($('#sysDrawer'),false);
  else { sysOnly=''; openDrawer('sysDrawer'); renderSystems(); $('#sysQ').focus() } };
$('#covBtn').onclick=()=>{ if($('#covDrawer').classList.contains('open')) closeDrawer($('#covDrawer'),false);
  else { openDrawer('covDrawer'); renderCoverage(); $("#covTitle").focus() } };
$('#revBtn').onclick=()=>{ if($('#revDrawer').classList.contains('open'))$('#revDrawer').classList.remove('open'); else {openDrawer('revDrawer'); renderReview()} };
$('#linksBtn').onclick=()=>{ if($('#linksDrawer').classList.contains('open'))$('#linksDrawer').classList.remove('open'); else { renderLinks(); openDrawer('linksDrawer') } };
$('#notesBtn').onclick=()=>{ if($('#notesDrawer').classList.contains('open'))$('#notesDrawer').classList.remove('open'); else openDrawer('notesDrawer') };
$('#sheetSel').onchange=e=>{ closePanel(); openSheet(e.target.value) };
addEventListener('resize',()=>{});
load();
