// The Manage page (admin.html). A file of its own, not an inline script, so the Content-Security-Policy can allow
// scripts from this site only (#8).
const $=s=>document.querySelector(s);
// Views are built as elements (K.h: text as text nodes, handlers as functions), never as markup. (Before, a
// full name with a quote ran script through an inline handler: fixed 2026-10-01; there are no such handlers now.)
const h=K.h;
$('#logout').addEventListener('click',()=>K.logout());
// el's children := these (arrays flattened; null, undefined and false left out)
const put=(el,...kids)=>el.replaceChildren(...kids.flat(Infinity).filter(c=>c!=null&&c!==false));
// a table of rows (in a tbody, as the HTML parser makes it)
const table=(...rows)=>h('table',null,h('tbody',null,rows));
const head=(...names)=>h('tr',null,names.map(n=>h('th',null,n)));
// a link inside the app (a path and query this page made): href through the URL check
const appLink=(url,props,...kids)=>{ const a=h('a',props,...kids); a.href=K.safeUrl(url); return a };
let ME=null, tab=null, SHEETS=[];
// My submissions: the filters ([id, label, kind param, field param]: core api listSubs)
const MINE_KINDS=[['all','Everything'],['equipment_photo','Equipment photos','equipment_photo'],['plate_photo','Tag plate photos','plate_photo'],
  ['equipment','Places and notes (all fields)','equipment'],['floor','Floor','equipment','floor'],['notes','Notes','equipment','notes'],
  ['custom','Custom fields','equipment','custom'],['link','Procedure links','link'],['review','Tag readings','review'],['tag_add','Marked tags','tag_add'],
  ['removals','Removals','tag_remove,photo_delete']];
const MINE_F={status:'all',kind:'all'};
let SHOW_HIDDEN=false;   // Users and Devices: removed ones an admin hid, shown anyway
// v2 crops (approving a marked tag): level 0 of the sheet's pyramid, decoded by K.jxl where the browser can't
const cropBg={};
new MutationObserver(()=>document.querySelectorAll('[data-crop]:not([data-bg])').forEach(el=>{
  el.dataset.bg='1'; const id=el.dataset.crop, v=K.syncStatus?.plant_data?.active;
  const u='/data/sheets/'+encodeURIComponent(id)+'.o0.jxl'+(v!=null?'?v='+v:'');
  (cropBg[id]??=K.jxl.native().then(n=>n?u:K.jxl.url(u))).then(x=>{ el.style.backgroundImage=`url("${x}")` }).catch(e=>console.warn('crop',e)) }))
  .observe(document.body,{childList:true,subtree:true});
const isAdmin=()=>['admin','manager'].includes(ME.user.role), isManager=()=>ME.user.role==='manager';
function toast(t){const e=$('#toast');e.textContent=t;e.style.display='block';clearTimeout(e._t);e._t=setTimeout(()=>e.style.display='none',3500)}
const when=ts=>ts?new Date(ts*1000).toLocaleString():'';
const lightbox=src=>K.lightbox(src);   // pinch / wheel zoom, drag to pan (common.js)
async function act(fn,ok){ try{ const r=await fn(); if(ok) toast(ok); await show(tab); return r }catch(e){ toast(K.isNetErr(e)?'Offline: this needs the server.':e.message); return null } }

// Updates is its own tab, not part of Account (the Android app shows updates in its own screens)
const canUpdate=()=>!K.cfg?.app&&(K.cfg?.mode==='peer'||isAdmin());
const TABS=[['queue','Approvals',isAdmin],['mine','My submissions',()=>true],['board','Leaderboard',()=>true],['users','Users',isAdmin],['devices','Devices',()=>true],['drawings','Drawings',()=>isManager()&&!K.cfg?.app],['history','History',isAdmin],['updates','Updates',canUpdate],['account','Account',()=>true]];
async function init(){
  ME=await K.start(); K.toast=toast;
  $('#who').textContent=`${ME.user.full_name||ME.user.username} · ${ME.user.role}`;
  const t=location.hash.slice(1); show(TABS.some(x=>x[0]===t&&x[2]())?t:isAdmin()?'queue':'mine');
}
// Each show() gets a number; a view draws into #main only if no later show() started meanwhile (a sync and a filter
// change, or two tabs clicked quickly: the older answer arriving last used to replace the newer page)
let SHOW_GEN=0;
const mainFor=g=>g===SHOW_GEN?$('#main'):document.createElement('div');
async function show(t){
  const g=++SHOW_GEN;
  if(t!==tab) SHOW_HIDDEN=false;   // (hidden items shown again: on the page where that was asked only)
  tab=t; history.replaceState(null,'','#'+t);
  put($('#tabs'),TABS.filter(x=>x[2]()).map(([id,label])=>h('button',{class:'btn'+(id===t?' on':''),onclick:()=>show(id)},label,
    id==='queue'?h('span',{class:'count',id:'qn',style:'display:none'}):null,id==='users'?h('span',{class:'count',id:'un',style:'display:none'}):null,
    id==='account'&&ME.transfer_offer?h('span',{class:'count'},'!'):null)));
  if(t!=='users') signups().then(S=>signupBadge(S));   // account requests waiting: the Users tab shows how many (its own view fills it too)
  if(!K.online&&t!=='account'){ put(mainFor(g),h('div',{class:'warn'},'You are offline. Approvals, users and history need the server. Changes you make on the drawings are queued and sent when you reconnect.')); return }
  try{ await VIEWS[t](g) }catch(e){ if(e.status===401) return location.reload(); put(mainFor(g),h('div',{class:'warn bad'},K.isNetErr(e)?'Cannot reach the server.':e.message)) }
}
K.onChange(why=>{ if(why==='synced') show(tab) });
addEventListener('hashchange',()=>{ const t=location.hash.slice(1); if(ME&&t!==tab&&TABS.some(x=>x[0]===t&&x[2]())) show(t) });

// Account requests (sign-up with the plant's code): a plant server's admins only. -> {enabled, set, requests} or null
const signups=async()=>K.cfg?.mode==='server'&&isAdmin()&&K.online?K.api('/api/signups').catch(()=>null):null;
const signupBadge=S=>{ const b=$('#un'), n=S?.requests.length||0; if(b){ b.textContent=n; b.style.display=n?'':'none' } };
// ---------- rendering a submission ----------
const val=v=>v==null||v===''?h('span',{class:'sub'},'(empty)'):Array.isArray(v)?v.map(c=>c.k+': '+c.v).join('; ')||'(none)':typeof v==='object'?h('span',{class:'mono'},JSON.stringify(v)):String(v);
const photoImg=file=>h('img',{src:'photos/'+file,alt:'',onclick:e=>lightbox(e.currentTarget.src)});
function detail(s){
  const p=s.payload;
  if(s.kind==='equipment'){
    const live=(s.live?.[0]?.value)||{}, cf=new Set((s.conflicts||[]).map(c=>c.field));
    return table(head('Field','Now','Proposed',...(cf.size?['Submitter saw']:[])),Object.entries(p.changes).map(([f,v])=>
      h('tr',{style:cf.has(f)?'background:rgba(255,90,90,.08)':null},h('td',null,f),h('td',null,val(live[f])),h('td',null,val(v)),cf.size?h('td',null,cf.has(f)?val(p.base[f]):''):null)));
  }
  if(s.kind==='tag_add'){
    const sh=SHEETS.find(x=>x.id===p.sheet), b=p.bbox;
    let crop=null;
    if(sh){ const w=b[2]-b[0]+40, ht=b[3]-b[1]+40, sc=Math.min(420/w,160/ht);
      // v1: the sheet PNG; v2 (pyramid levels): level 0, filled in once decoded (fillCrops)
      const bg=sh.levels?'':`url(${JSON.stringify(encodeURI(sh.file))})`;
      crop=h('div',{'data-crop':sh.levels?sh.id:null,style:`width:${Math.round(w*sc)}px;height:${Math.round(ht*sc)}px;background:#fff ${bg} no-repeat;background-size:${sh.w*sc}px auto;background-position:${-(b[0]-20)*sc}px ${-(b[1]-20)*sc}px;border:1px solid var(--line);border-radius:4px;margin:6px 0`}) }
    return [h('div',null,K.describe(s.kind,p)+' ',appLink('/?sheet='+encodeURIComponent(p.sheet),{class:'sub'},'open sheet')),crop,
      p.note?h('div',{class:'sub'},'Note: '+p.note):null,
      h('div',{class:'row',style:'margin-top:4px'},h('span',{class:'sub'},'Code as it should be saved:'),
        h('input',{id:'ek-'+s.id,class:'mono',value:(p.kks||'')+(p.suffix||''),placeholder:'KKS, empty = review queue',style:'width:190px'}),
        h('input',{id:'ei-'+s.id,class:'mono',value:p.isa||'',placeholder:'letters',style:'width:80px'}))];
  }
  if(s.kind==='tag_remove') return h('div',{class:'del'},K.describe(s.kind,p));
  if(s.kind==='review') return [h('div',null,K.describe(s.kind,p)),s.live?h('div',{class:'sub'},'Now: ',val(s.live[0].value)):null];
  if(s.kind==='photo_delete') return [h('div',{class:'del'},'Delete this photo'),s.live?.[0]?.value?h('div',{class:'photos'},h('figure',null,photoImg(s.live[0].value.file))):h('div',{class:'sub'},'(already gone)')];
  return h('div',{class:s.kind==='link'&&p.on===false?'del':'add'},K.describe(s.kind,p));
}
const who=s=>s.by_name&&s.by_name!==s.by?[s.by_name+' ',h('span',{class:'mono'},`(${s.by??''})`)]:String(s.by??'');  // full name + username
const rnote=s=>s.request_note?h('div',{class:'rnote'},`“${s.request_note}”`):null;   // the requester's note for the approver
const badge=s=>{ const st=String((s.conflicts?.length?'conflict':s.status)??''); return h('span',{class:'badge '+st},st) };

// ---------- views ----------
const VIEWS={
  async queue(g){
    if(!SHEETS.length) SHEETS=await K.api('/data/sheets.json').catch(()=>[]);
    // grouped by code (core api groupSubmissions): per code, each kind of change is its own group, so an equipment photo
    // and a tag plate photo never compete; Pick and votes only where several of the same kind wait ("pick")
    const R=await K.api('/api/submissions?status=open&group=code'), groups=R.groups||[];
    const qn=$('#qn'); if(qn){qn.textContent=R.submissions.length; qn.style.display=R.submissions.length?'':'none'}
    if(!groups.length){ put(mainFor(g),h('p',{class:'sub'},'Nothing waiting for approval.')); return }
    const out=[h('p',{class:'sub'},'Grouped by code, oldest first. Approving applies the change and records it in History, where it can be reverted.')];
    const button=(cls,label,onclick)=>h('button',{class:cls,onclick},label);
    const oldest=g=>Math.min(...g.kinds.flatMap(k=>k.items.map(s=>s.created||0)));
    for(const g of [...groups].sort((a,b)=>oldest(a)-oldest(b))){
      // the code opens its tag on the drawing; a change without a code (a review) opens its tag by id
      const marked=g.kinds.every(k=>k.kind==='tag_add');
      const title=g.code?appLink('/?kks='+encodeURIComponent(g.code),{class:'mono',title:'Show it on the drawing'},g.code)
        :g.tag&&!marked?appLink('/?tag='+encodeURIComponent(g.tag),{title:'Show it on the drawing'},'Tag '+g.tag)
        :'Marked tags without a code';
      out.push(h('div',{class:'card group','data-code':g.code||g.tag||''},h('h3',null,title),g.kinds.map(kd=>{
        const L=[...kd.items].sort((a,b)=>(a.created||0)-(b.created||0));
        if(kd.kind.endsWith('_photo')) return h('div',{class:'kind','data-kind':kd.kind},h('h4',null,`${kd.label} (${L.length})`),
          kd.pick?h('div',{class:'sub'},`Several ${kd.label.toLowerCase()}s proposed. “Use this one” approves it and rejects the other ${kd.label.toLowerCase()}s of this code. Votes are only a hint.`):null,
          h('div',{class:'photos'},L.map(s=>h('figure',null,photoImg(s.payload.file),
            h('div',{class:'sub'},who(s),` · ${when(s.created)}`,kd.pick?` · ${s.votes} vote${s.votes===1?'':'s'}`:''),s.payload.caption?h('div',null,s.payload.caption):null,rnote(s),
            h('div',{class:'row',style:'margin-top:6px'},
              kd.pick?[button('primary','Use this one',()=>decide(s.id,'pick')),button('ghost','Add',()=>decide(s.id,'approve'))]:button('primary','Approve',()=>decide(s.id,'approve')),
              button('danger','Reject',()=>decide(s.id,'reject')))))));
        return h('div',{class:'kind','data-kind':kd.kind},h('h4',null,`${kd.label} (${L.length})`),L.map(s=>h('div',{class:'item',style:'margin:8px 0;padding-top:6px;border-top:1px solid var(--chrome3)'},
          h('div',{class:'row'},badge(s),h('span',{class:'sub'},`#${s.id} · `,who(s),` · ${when(s.created)}`)),rnote(s),
          s.conflicts?.length?h('div',{class:'warn bad'},`Conflict: ${s.kind==='equipment'?'highlighted field(s) changed after this was submitted':'this changed after it was submitted'}. Approving overwrites the current value.`):null,
          detail(s),
          h('div',{class:'row',style:'margin-top:6px'},
            s.conflicts?.length?button('primary','Overwrite with proposal',()=>decide(s.id,'approve',true)):button('primary','Approve',()=>decide(s.id,'approve')),
            button('danger','Reject',()=>decide(s.id,'reject'))))));
      })));
    }
    put(mainFor(g),out);
  },
  async mine(g){
    // filtered by the server (/api/submissions: status, kind, field, mine), grouped here by code
    const F=MINE_F, q=new URLSearchParams({mine:'1',status:F.status,limit:'300'});
    const kf=MINE_KINDS.find(x=>x[0]===F.kind)||MINE_KINDS[0]; if(kf[2]) q.set('kind',kf[2]); if(kf[3]) q.set('field',kf[3]);
    const [mineR,others]=await Promise.all([K.api('/api/submissions?'+q),K.api('/api/submissions?status=open&kind=photo')]);
    const mine=mineR.submissions.filter(s=>s.mine), toVote=others.submissions.filter(s=>!s.mine&&['pending','conflict'].includes(s.status));
    const out=[];
    if(K.outbox.length) out.push(h('div',{class:'card'},h('h3',null,`Queued on this device (${K.outbox.length})`),h('div',{class:'sub'},'Sent automatically when the server is reachable.'),
      K.outbox.map(i=>h('div',null,K.describe(i.kind,i.payload),i.raw?[' ',h('span',{class:'badge pending'},'converting')]:null,
        i.refused?[' ',h('span',{class:'badge conflict'},'refused: '+i.refused),' ',
          h('button',{class:'ghost',onclick:async()=>{await K.retryRefused(i.client_id);show(tab)}},'Try again'),' ',
          h('button',{class:'ghost',onclick:async()=>{if(confirm('Discard this photo? It is not on the server.')){await K.discardQueued(i.client_id);show(tab)}}},'Discard')]:null))));
    if(toVote.length) out.push(h('div',{class:'card'},h('h3',null,'Photo proposals from others'),h('div',{class:'sub'},'Vote for the photo that shows the equipment best. An admin makes the final choice.'),
      h('div',{class:'photos'},toVote.map(s=>h('figure',null,photoImg(s.payload.file),h('div',{class:'sub'},`${s.payload.kks??''} · ${s.by_name||s.by||''} · ${s.votes} vote${s.votes===1?'':'s'}`),
        h('button',{class:s.voted?'primary':'ghost',onclick:()=>vote(s.id)},s.voted?'Voted ✓':'Vote'))))));
    const sel=(name,label,opts,v)=>h('label',{class:'sub'},label+' ',h('select',{name,'aria-label':label,onchange:e=>{ MINE_F[name]=e.currentTarget.value; show('mine') }},
      opts.map(([val,text])=>h('option',{value:val,selected:val===v},text))));
    out.push(h('div',{class:'row',id:'mineFilters','data-f':F.status+'|'+F.kind,style:'margin:8px 0'},
      sel('status','Status',[['all','All'],['open','Waiting (pending or conflict)'],['approved','Approved'],['rejected','Rejected'],['withdrawn','Withdrawn'],['conflict','Conflict']],F.status),
      sel('kind','Kind',MINE_KINDS.map(x=>[x[0],x[1]]),F.kind),
      h('span',{class:'sub'},`${mine.length} shown`)));
    // grouped by code; a change without one (a review, a marked tag without a code) by its tag or sheet
    const groups=new Map();
    for(const s of mine){ const g=s.code||(s.kind==='tag_add'?'Marked tags on '+(s.payload.sheet||'?'):s.tag?'Tag '+s.tag:s.target||'Other'); if(!groups.has(g)) groups.set(g,[]); groups.get(g).push(s) }
    const kindName={equipment_photo:'Equipment photo',plate_photo:'Tag plate photo',equipment:'Place and notes',link:'Procedure link',review:'Tag reading',tag_add:'Marked tag',tag_remove:'Tag removal',photo_delete:'Photo removal'};
    for(const [g,L] of groups){
      const s0=L[0], code=s0.code;
      out.push(h('div',{class:'card mine','data-code':g},h('h3',null,code?appLink('/?kks='+encodeURIComponent(code),{class:'mono'},code):g),
        table(head('#','Kind','Status','Change','Sent','Decision',''),L.map(s=>h('tr',null,h('td',{class:'sub'},s.id),
          h('td',{class:'sub'},kindName[s.group_kind]||s.kind,s.fields?.length?h('div',null,s.fields.join(', ')):null),h('td',null,badge(s)),
          h('td',null,K.describe(s.kind,s.payload),rnote(s)),
          h('td',{class:'sub'},when(s.created)),
          h('td',{class:'sub'},s.status==='conflict'?'waiting for an admin (clashes with a newer change)':s.note&&!s.note.startsWith('[')?s.note:''),
          h('td',null,['pending','conflict'].includes(s.status)?h('button',{class:'ghost',onclick:()=>withdraw(s.id)},'Withdraw'):null))))));
    }
    if(!mine.length) out.push(h('p',{class:'sub'},F.status==='all'&&F.kind==='all'?'You haven\'t submitted anything yet.':'Nothing matches these filters.'));
    put(mainFor(g),out);
  },
  async users(g){
    // removed people an admin hid (POST /api/hidden) stay out of the list unless shown
    const all=(await K.api('/api/users?show_hidden=1')).users, nHidden=all.filter(u=>u.hidden).length, U=all.filter(u=>SHOW_HIDDEN||!u.hidden);
    const gone=u=>!u.active&&u.id!==ME.user.id&&u.person;
    const canEdit=u=>u.role==='user'||(u.role==='admin'&&isManager());
    const ghost=(label,onclick)=>h('button',{class:'ghost',onclick},label), other=u=>u.role==='admin'?'user':'admin';
    const actions=u=>{
      const out=[];
      if(u.no_account){ if(canEdit(u)){
          if(u.active) out.push(ghost('Remove devices',()=>confirm('Remove all devices of '+u.username+'? They stop syncing.')&&setPerson(u.person,{active:false})));
          if(isManager()) out.push(ghost(u.role==='admin'?'Make user':'Make admin',()=>setPerson(u.person,{role:other(u)})));
          // someone who joined with the app has no account on the server: this makes one for the same person
          if(K.cfg?.mode==='server') out.push(ghost('Web sign-in',()=>webSignin(u))) } }
      else if(canEdit(u)&&u.id!==ME.user.id){
        out.push(ghost(u.active?'Deactivate':'Activate',()=>setUser(+u.id,{active:!u.active})));
        if(isManager()) out.push(ghost(u.role==='admin'?'Make user':'Make admin',()=>setUser(+u.id,{role:other(u)})));
        out.push(ghost('Password link',()=>resetLink(u.id,u.username)));
      }
      if(canEdit(u)&&u.id!==ME.user.id&&!u.no_account) out.push(ghost('Edit details',()=>editDetails(+u.id,u.full_name||'',u.position||'')));
      if(gone(u)) out.push(u.hidden?ghost('Show again',()=>setHidden([u.person],false)):ghost('Hide',()=>setHidden([u.person],true)));
      return out;
    };
    const F=h('form',{class:'inline',onsubmit:e=>{ e.preventDefault(); createUser(F) }},h('input',{name:'full_name',placeholder:'Full name',required:true,maxlength:80,style:'min-width:200px'}),
      h('input',{name:'position',placeholder:'Position (job title)',required:true,maxlength:80}),h('input',{name:'username',placeholder:'username',required:true,maxlength:40}),
      h('select',{name:'role'},h('option',{value:'user'},'user'),isManager()?h('option',{value:'admin'},'admin'):null),h('button',{class:'primary'},'Create and get link'));
    // sign-up: people with the code ask for an account in the browser; each request is approved or rejected here
    const S=await signups(); signupBadge(S);
    const code=h('input',{name:'code','aria-label':'Sign-up code',placeholder:S?.enabled?'a new code':'a code, 6+ characters',autocomplete:'off',autocapitalize:'none',spellcheck:'false',minlength:6,maxlength:64,required:true});
    const SU=S?[h('div',{class:'card',id:'signups'},h('h3',null,`Account requests (${S.requests.length})`),
        S.requests.length?table(head('Name','Username','Asked',''),S.requests.map(r=>h('tr',{'data-user':r.username},
          h('td',null,r.full_name,r.position?h('div',{class:'sub'},r.position):null),
          h('td',{class:'mono'},r.username,r.person?h('div',{class:'del'},`this is the username of ${whoIs(r.person)}, who uses the app and has no web sign-in`,
              canEdit(r.person)?null:' (only the manager can approve an admin as the same person)')
            :r.taken?h('div',{class:'del'},'this username exists already: approve with another one'):null,
            r.same>1?h('div',{class:'del'},`${r.same} requests ask for this username: ask the person which one is theirs before approving`):null),
          h('td',{class:'sub'},when(r.created),h('div',null,`expires ${when(r.expires)}`)),
          h('td',{class:'row'},r.person?[canEdit(r.person)?h('button',{class:'primary',onclick:()=>decideSignup(r,'same')},'Approve as the same person'):null,
              h('button',{class:'ghost',onclick:()=>decideSignup(r,'approve')},'Approve with another username')]
            :h('button',{class:'primary',onclick:()=>decideSignup(r,'approve')},'Approve'),h('button',{class:'danger',onclick:()=>decideSignup(r,'reject')},'Reject')))))
          :h('div',{class:'sub'},S.enabled?'Nobody is waiting.':'Nobody is waiting, and sign-up is off.'),
        h('div',{class:'sub',style:'margin-top:6px'},`Approving makes the account (role user) with the password the person chose; they can sign in at once. Rejecting deletes the request. A request nobody decides is dropped after ${S.days} days.`)),
      h('div',{class:'card',id:'signupCode'},h('h3',null,'Sign-up code'),
        h('div',{id:'signupState'},S.enabled?['Sign-up is ',h('b',null,'on'),` (code set ${when(S.set)}). The sign-in screen offers “Request an account” to whoever has the code.`]
          :['Sign-up is ',h('b',null,'off'),': only an admin can add accounts.']),
        isManager()?[h('form',{class:'inline',onsubmit:e=>{ e.preventDefault(); setSignupCode(code.value) }},code,h('button',{class:'primary'},S.enabled?'Change the code':'Switch sign-up on'),
            S.enabled?h('button',{class:'ghost',type:'button',onclick:()=>confirm('Switch sign-up off? Requests already waiting stay until you decide them.')&&setSignupCode('')},'Switch sign-up off'):null),
          h('div',{class:'sub'},'Give the code to your team only. It is not shown again, here or anywhere: if it is forgotten or got out, set a new one. Changing it does not touch accounts or requests already made.')]
          :h('div',{class:'sub'},'The manager sets, changes or clears the code.'))]:null;
    put(mainFor(g),SU,h('div',{class:'card server-only'},h('h3',null,'Add an account'),F,
        h('div',{class:'sub'},'There is no email: you get a one-time link (valid 7 days) to give the person. They set their own password with it.'),h('div',{id:'newlink'})),
      hiddenBar(true,nHidden),   // (whether a person still has a device is the server's to tell: Clear removed asks it)
      table(head('Name','Username','Role','Status',''),U.map(u=>h('tr',{class:u.hidden?'hidden-row':null},
        h('td',null,u.full_name?u.full_name:h('span',{class:'del'},'no name yet'),u.position?h('div',{class:'sub'},u.position):null),
        h('td',{class:'mono'},u.username,u.id===ME.user.id?[' ',h('span',{class:'sub'},'(you)')]:null),
        h('td',null,u.role),
        h('td',null,u.no_account?(u.active?[`own device${u.devices===1?'':'s'} `,h('span',{class:'sub'},`(${u.devices})`)]:h('span',{class:'del'},'all devices removed'))
                    :u.active?(u.has_password?'active':h('span',{class:'sub'},'link not used yet')):h('span',{class:'del'},'deactivated')),
        h('td',{class:'row'},actions(u))))),
      h('p',{class:'sub server-only'},'Web sign-in is for someone who joined with the app (own devices) and also wants the web app: you get a one-time link for them, and they stay one person on both.'),
      h('p',{class:'sub'},`Deactivating signs the person out everywhere and stops syncing. Plant data already saved on their device for offline use stays there until they next connect (at most ${ME.offline_days} days of offline access).`));
  },
  async devices(g){
    const D=await K.api('/api/devices'+(SHOW_HIDDEN?'?show_hidden=1':'')), S=D.sync, ago=t=>t?`${Math.max(0,Math.round((Date.now()/1000-t)/60))} min ago`:'';
    const devRow=(d,mine)=>h('tr',null,h('td',null,d.label||'device',d.this_computer?[' ',h('span',{class:'sub'},'(this one)')]:null,mine?null:h('div',{class:'sub'},d.username)),
      h('td',{class:'mono sub'},`${d.device.slice(0,12)}…`),h('td',null,d.revoked?h('span',{class:'del'},'removed'):'active'),
      h('td',null,!d.revoked&&!d.this_computer?h('button',{class:'ghost',onclick:()=>confirm('Remove this device? It stops syncing; what it already holds stays on it.')&&act(()=>K.api('/api/devices/revoke',{device:d.device}),'Device removed')},'Remove')
        :d.revoked&&isAdmin()?h('button',{class:'ghost',onclick:()=>d.hidden?setHidden([d.device,d.person],false):setHidden([d.device],true)},d.hidden?'Show again':'Hide'):null));
    const N=S.internet||{}, syncs=Object.values(S.syncs);
    const addr=h('input',{name:'address',placeholder:'or an address, e.g. 192.168.1.20',style:'min-width:220px'});
    const relay=h('input',{name:'url',value:N.relay||'',placeholder:'wss://kks-relay.….workers.dev',style:'min-width:280px'});
    const plant=h('input',{name:'name','aria-label':'Plant name',maxlength:80,value:K.cfg?.plant_name||'',style:'min-width:280px'});
    const exportLink=(photos,label)=>{ const a=h('a',{class:'ghost',style:'text-decoration:none;color:inherit',onclick:e=>{ if(!exportBundle(photos)) e.preventDefault() }},label);
      if(photos) a.href='/api/bundle?photos=1'; else a.href='/api/bundle'; return a };
    const out=[h('div',{class:'card'},h('h3',null,'Your devices'),table(D.mine.map(d=>devRow(d,true))),
        h('div',{class:'sub'},'A lost or stolen phone or laptop: remove it here from any of your other devices (or ask an admin). Its changes made after that don\'t count anywhere.')),
      h('div',{class:'card'},h('h3',null,'Syncing'),
        h('div',{class:'sub'},`This ${D.mode==='peer'?'computer':'server'}: `,h('span',{class:'mono'},`${(D.node||'').slice(0,12)}…`),` · sync port ${D.sync_port||'off'} · finding devices on this Wi-Fi: ${S.discovery??''}`),
        table(head('Device','Address','Last sync',''),syncs.length?syncs.map(s=>h('tr',null,h('td',null,s.name||(s.peer?s.peer.slice(0,12)+'…':'unknown device')),h('td',{class:'mono sub'},s.address||''),
            h('td',null,ago(s.at)+' ',s.ok?h('span',{class:'sub'},`received ${s.result.received}, sent ${s.result.sent}${s.result.they_denied?' · it does not know this device yet':''}${s.result.denied?' · not certified here: sent nothing':''}`)
                                     :h('span',{class:'del'},s.error||'failed')),h('td')))
          :h('tr',null,h('td',{colspan:4,class:'sub'},'No syncs yet.'))),
        S.found.length?h('div',{class:'sub',style:'margin-top:6px'},'Found on this Wi-Fi: '+S.found.map(f=>f.name||f.host).join(', ')):null,
        // admins only (the server refuses others, #32); "Sync now" with no address is a device's round, not the server's
        isAdmin()?h('form',{class:'inline',onsubmit:e=>{ e.preventDefault(); syncNow(addr.value) }},
          D.mode==='peer'?h('button',{class:'primary',type:'button',onclick:()=>syncNow('')},'Sync now'):null,
          addr,h('button',{class:'ghost'},'Sync with it')):null),
      h('div',{class:'card'},h('h3',null,'Internet'),
        h('div',{class:'sub'},N.relay?['Relay ',h('span',{class:'mono'},N.relay),` · ${N.state||''}`+(N.online?.length?` · online there: ${N.online.map(p=>D.names?.[p]||p.slice(0,8)+'…').join(', ')}`:'')]
          :'No internet relay set: devices sync only on the same network (or with files).',' Everything that passes the relay is end-to-end encrypted between devices: it can\'t read plant data.'),
        isManager()?h('form',{class:'inline',style:'margin-top:6px',onsubmit:e=>{ e.preventDefault(); setRelay(relay.value) }},relay,h('button',{class:'ghost'},'Save')):null),
      isManager()?h('div',{class:'card'},h('h3',null,'Plant name'),h('div',{class:'sub'},'Shown next to Walkdown on every device. Leave it empty for none.'),
        h('form',{class:'inline',style:'margin-top:6px',onsubmit:e=>{ e.preventDefault(); setPlantName(plant.value) }},plant,h('button',{class:'ghost'},'Save'))):null,
      h('div',{class:'card'},h('h3',null,'Bundle files'),h('div',{class:'sub'},'A bundle carries the plant log (optionally with photos) by USB or messaging, where Wi-Fi sync can\'t reach. It is not encrypted: treat it like a copy of the database.'),
        h('div',{class:'row',style:'margin-top:8px'},isAdmin()?[exportLink(0,'Export bundle'),exportLink(1,'Export with photos')]:null,
          h('label',{class:'ghost',style:'cursor:pointer'},'Import a bundle',h('input',{type:'file',accept:'.kksbundle',hidden:true,onchange:e=>importBundle(e.currentTarget)}))))];
    if(isAdmin()) out.push(h('div',{class:'card'},h('h3',null,'Add a device with a QR code'),
        h('div',{class:'sub'},`For someone next to you on the same network: they choose "Join with a QR code" when they set up the app and scan this. You then see who asks and accept; their device syncs the plant from this ${K.cfg?.app?'phone':D.mode==='peer'?'computer':'server'}. No files needed. The code works once, for 15 minutes.`),
        h('div',{id:'invite'},qrButton())),
      h('div',{class:'card'},h('h3',null,'Waiting to join'),h('div',{class:'sub'},'Devices on this Wi-Fi that asked without a code (“Ask an admin on this Wi-Fi”). Accept only if the code next to the name is the one on their screen.'),h('div',{id:'lobby'})),
      h('div',{class:'card'},h('h3',null,'Add a computer from a join request'),
        h('div',{class:'sub'},'Someone set up the app on their laptop and gave you a ',h('span',{class:'mono'},'.kksjoin'),' file. Importing it certifies that laptop; then give them a bundle (export above) to import, or let it sync on the same Wi-Fi.'),
        h('label',{class:'primary',style:'display:inline-block;margin-top:8px;cursor:pointer'},'Import join request',h('input',{type:'file',accept:'.kksjoin,.json',hidden:true,onchange:e=>importJoin(e.currentTarget)}))),
      h('div',{class:'card',id:'allDevices'},h('h3',null,'All devices'),hiddenBar(D.all.some(d=>d.revoked&&!d.hidden),D.hidden||0),table(D.all.map(d=>devRow(d,false)))));
    put(mainFor(g),out);
    if(isAdmin()) pollLobby();
  },
  async history(g,before){
    const R=(await K.api('/api/revisions'+(before?`?before=${before}`:''))).revisions;
    const str=v=>String(v??''), add=t=>h('span',{class:'add'},t), del=t=>h('span',{class:'del'},t);
    const summary=r=>{ const a=r.after?JSON.parse(r.after):null, b=r.before?JSON.parse(r.before):null;
      if(r.entity==='user') return str(r.note);
      if(r.entity==='sheet') return [h('span',{class:'mono'},str(r.key)),' '+str(r.note)];
      if(r.entity==='link'){ const [p,s,k]=JSON.parse(r.key); return [a?add('linked'):del('unlinked'),` ${str(k)} · proc ${str(p)} step ${s}`] }
      if(r.entity==='added_tag'){ const t=a||b; return [a?add('tag marked'):del('marked tag removed'),` ${t.isa||''} ${(t.kks||'(no code)')+(t.suffix||'')} on ${str(t.sheet)}`] }
      if(r.entity==='photo') return a?[add('photo added'),' '+str(a.kks)]:[del('photo removed'),' '+(b?.kks||'')];
      if(r.entity==='equipment'){ const keys=[...new Set([...Object.keys(a||{}),...Object.keys(b||{})])].filter(k=>JSON.stringify((a||{})[k])!==JSON.stringify((b||{})[k]));
        return [`${str(r.key)}: `,keys.map((k,i)=>[i?' · ':'',`${k} `,val((b||{})[k]),' → ',val((a||{})[k])])] }
      return [`${str(r.entity)} ${str(r.key)}: `,val(b),' → ',val(a)] };
    put(mainFor(g),h('p',{class:'sub'},'Every applied change, newest first. ',h('b',null,'Revert'),' undoes one change. ',h('b',null,'Restore to here'),' puts all data (notes, locations, photos, links, reviews) back to how it was right after that change. Both are new entries themselves, so they can be undone too. Accounts are not affected.'),
      table(head('Rev','When','By','Change',''),R.map(r=>h('tr',null,h('td',{class:'mono'},r.rev),h('td',{class:'sub'},when(r.ts)),h('td',null,r.full_name||r.username||'server console'),
        h('td',null,summary(r),r.note&&!['user','sheet'].includes(r.entity)?[' ',h('span',{class:'sub'},`(${r.note})`)]:null),
        h('td',{class:'row'},!['user','sheet'].includes(r.entity)?[h('button',{class:'ghost',onclick:()=>revert(String(r.hid))},'Revert'),h('button',{class:'ghost',onclick:()=>restoreTo(String(r.hid),r.rev)},'Restore to here')]:null)))),
      R.length?h('div',{class:'row',style:'margin-top:10px'},R.length===100?h('button',{class:'ghost',onclick:()=>VIEWS.history(++SHOW_GEN,R[R.length-1].rev)},'Older →'):null,
                                                          isAdmin()?h('button',{class:'danger',onclick:()=>restoreTo(0)},'Restore to before any logged change'):null)
              :h('p',{class:'sub'},'No changes yet.'));
  },
  async drawings(g){
    const D=await K.api('/api/sheets'), imp=D.importer, job=D.job;
    const busy=job?.state==='running', ids=new Set(D.sheets.map(s=>s.id)), pd=D.plant_data||{};
    const rotations=(props,auto)=>h('select',props,h('option',{value:'auto'},auto),['0','90','180','270'].map(v=>h('option',{value:v},v+'°')));
    const card=h('div',{class:'card'},h('h3',null,'Add a drawing'));
    if(!imp.available) card.append(h('div',{class:'warn bad'},`The importer isn't set up on the server: ${imp.error??''}`),
      h('div',{class:'sub'},'The server\'s ',h('span',{class:'mono'},'kks-import'),' is installed with it (',h('span',{class:'mono'},'deploy/install-server-user.sh'),'; config key ',
        h('span',{class:'mono'},'importer'),'). Then reload this page.'));
    else{ const F=h('form',{id:'impForm',onsubmit:e=>{ e.preventDefault(); startImport(F) }},
        h('div',{class:'row'},h('input',{type:'file',name:'pdf',accept:'application/pdf,.pdf',required:true,onchange:e=>impFile(e.currentTarget)}),
          h('input',{name:'name',placeholder:'Name, e.g. Condensate System',required:true,maxlength:80,style:'flex:1;min-width:200px',oninput:e=>impName(e.currentTarget)}),
          h('input',{name:'id',placeholder:'sheet id',required:true,maxlength:24,style:'width:150px',class:'mono',oninput:e=>impId(e.currentTarget)})),
        h('div',{class:'row',style:'margin-top:8px'},h('label',null,'Orientation ',rotations({name:'rotate'},'Auto')),
          h('label',{id:'impReplace',style:'display:none'},h('input',{type:'checkbox',name:'replace'}),' Replace the existing sheet with this id'),
          h('button',{class:'primary',disabled:busy},'Import')),
        h('div',{class:'sub',style:'margin-top:6px'},'Vector PDFs plotted from AutoCAD only (scans won\'t work); page 1 is read. Takes about a minute. The tag list is backed up first and put back if the import fails.'));
      card.append(F) }
    put(mainFor(g),h('div',{class:'sub',style:'margin-bottom:8px'},`${pd.version?`Plant data version ${pd.version}`:'No plant data published yet'}: every import or removal publishes a new version, and every device gets it by sync.`),
      card,h('div',{id:'job'}),
      table(head('Drawing','Id','Tags',''),D.sheets.map(s=>{
        const rot=s.has_source&&imp.available?rotations({id:'rot-'+s.id},'auto'):null;
        return h('tr',null,h('td',null,s.name,h('div',{class:'sub'},`${s.w}×${s.h} px${s.notes?.length?` · ${s.notes.length} markup note(s)`:''}`)),
          h('td',{class:'mono'},s.id),h('td',{class:'sub'},`${s.tags.auto||0} auto · ${s.tags.verified||0} verified · ${s.tags.review||0} to review`),
          h('td',{class:'row'},appLink('/?sheet='+encodeURIComponent(s.id),{class:'ghost',style:'text-decoration:none;color:inherit'},'Open'),
            rot?[rot,h('button',{class:'ghost',disabled:busy,onclick:()=>reimport(s.id,rot.value)},'Re-import')]:null,
            h('button',{class:'danger',disabled:busy,onclick:()=>removeSheet(s.id,s.name)},'Remove')))})),
      h('p',{class:'sub'},'Remove takes the sheet and its tags out of the app. The image, tag list and uploaded PDF stay in the server\'s backups folder. Notes, photos and procedure links are stored per KKS, so they come back if the sheet is imported again.'));
    window._sheetIds=ids; renderJob(job);
    if(busy) pollJob();
  },
  async board(g){
    // every member sees names and numbers only (core api leaderboard: no usernames, roles or IDs)
    const B=await K.api('/api/leaderboard'), kinds=B.kinds||{}, P=B.people||[];
    const pct=x=>x==null?'–':Math.round(x*100)+' %';
    const what=p=>Object.entries(p.kinds||{}).filter(([,v])=>v.total).map(([k,v])=>h('div',null,`${kinds[k]||k}: ${v.approved} approved`+(v.rejected?`, ${v.rejected} rejected`:'')+(v.pending?`, ${v.pending} waiting`:'')));
    put(mainFor(g),h('p',{class:'sub'},'Everyone who contributed, by approved contributions. Approved changes include an admin\'s own (applied without review). Ratio: approved per rejected.'),
      P.length?table(head('#','Name','Approved','Rejected','Ratio','Approval rate','Waiting','What','Last contribution'),P.map(p=>h('tr',{'data-key':p.key},
        h('td',{class:'mono'},p.rank),h('td',null,p.name),h('td',null,h('b',null,p.approved)),h('td',null,p.rejected),
        h('td',null,p.ratio==null?(p.approved?'no rejections':'–'):p.ratio.toFixed(1)),h('td',null,pct(p.approval_rate)),h('td',null,p.pending),
        h('td',{class:'sub'},what(p)),h('td',{class:'sub'},p.last?`${when(p.last)} (${K.ago(p.last)})`:'')))):h('p',{class:'sub'},'No contributions yet.'));
  },
  async updates(g){ put(mainFor(g),h('div',{id:'upd'},h('p',{class:'sub'},'Checking…'))); await renderUpdate() },
  async account(g){
    if(K.online){ try{ ME=await K.api('/api/me') }catch(e){} }
    const sw=!!navigator.serviceWorker?.controller, secure=window.isSecureContext;
    const lease=await K.idb.get('me');
    const D=h('form',{class:'inline',onsubmit:e=>{ e.preventDefault(); saveDetails(D) }},
      h('input',{name:'full_name',placeholder:'Full name',value:ME.user.full_name??'',required:true,maxlength:80,style:'min-width:220px'}),
      h('input',{name:'position',placeholder:'Position (optional)',value:ME.user.position??'',maxlength:80}),h('button',{class:'primary'},'Save'));
    const P=h('form',{class:'inline',onsubmit:e=>{ e.preventDefault(); changePw(P) }},
      h('input',{type:'password',name:'old',placeholder:'current password',autocomplete:'current-password',required:true}),
      h('input',{type:'password',name:'new',placeholder:'new password (10+)',autocomplete:'new-password',required:true,minlength:10}),h('button',{class:'primary'},'Change password'));
    const out=[h('div',{class:'card'},h('h3',null,'Your details'),ME.user.full_name?null:h('div',{class:'warn'},'Add your full name, so others can tell whose account this is.'),D,
        h('div',{class:'sub'},'Username ',h('span',{class:'mono'},ME.user.username),` · ${ME.user.role}`)),
      h('div',{class:'card server-only'},h('h3',null,'Password'),P)];
    if(ME.transfer_offer) out.push(h('div',{class:'card'},h('h3',null,'The manager wants to hand the manager role to you'),
      h('div',{class:'sub'},'You would become the single top account. The current manager becomes an admin.'),
      h('div',{class:'row',style:'margin-top:8px'},h('button',{class:'primary',onclick:()=>mgr('accept')},'Accept'),h('button',{class:'ghost',onclick:()=>mgr('decline')},'Decline'))));
    if(isManager()){
      const t=ME.transfer_pending;
      const T=h('form',{class:'inline',onsubmit:e=>{ e.preventDefault(); mgr('transfer',{username:T.username.value,password:T.password.value}) }},
        h('input',{name:'username',placeholder:'admin username',required:true}),
        h('input',{type:'password',name:'password',placeholder:'your password',autocomplete:'current-password',required:true}),h('button',{class:'primary'},'Offer role'));
      out.push(h('div',{class:'card server-only'},h('h3',null,'Hand over the manager role'),
        t?h('div',null,'Offered to ',h('b',null,t.to_name),`, waiting for them to accept (until ${when(t.expires)}). `,h('button',{class:'ghost',onclick:()=>mgr('cancel')},'Cancel offer'))
         :[h('div',{class:'sub'},'Only to an existing admin. They must accept; you then become an admin. If the manager account is ever lost, whoever runs the server can name another account manager with ',
             h('span',{class:'mono'},'kks-server reset-manager --user NAME'),'.'),T]));
    }
    await K.offline.load(); out.push(K.offline.card());
    out.push(h('div',{class:'card server-only'},h('h3',null,'This device'),table(
        h('tr',null,h('td',null,'Offline app'),h('td',null,sw?'installed: drawings and data you have opened work without the server (all of it with the offline copy above)':secure?'installing… reload once'
          :[h('span',{class:'del'},'not available'),': needs HTTPS (or localhost). Over plain http on the LAN the page works only while connected.'])),
        h('tr',null,h('td',null,'Offline access until'),h('td',null,(lease?new Date(lease.lease_until).toLocaleString():'-')+' ',h('span',{class:'sub'},`(renewed each time you connect; ${ME.offline_days} days)`))),
        h('tr',null,h('td',null,'Queued changes'),h('td',null,K.outbox.length))),
      h('div',{class:'row',style:'margin-top:8px'},h('button',{class:'ghost',onclick:()=>K.flush()},'Sync now'),h('button',{class:'danger',onclick:()=>K.logout()},'Log out and remove plant data from this device'))));
    put(mainFor(g),out);
  },
};

// ---------- drawings ----------
const slug=v=>v.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-+|-+$/g,'').slice(0,24);
let idTouched=false;
function impFile(inp){ const f=inp.files[0], F=inp.form; if(!f) return; if(!F.name.value) F.name.value=f.name.replace(/\.pdf$/i,'').replace(/[_]+/g,' ').trim(); if(!idTouched){ F.id.value=slug(F.name.value); impId(F.id,true) } }
function impName(inp){ if(!idTouched){ inp.form.id.value=slug(inp.value); impId(inp.form.id,true) } }
function impId(inp,auto){ if(!auto) idTouched=true; $('#impReplace').style.display=window._sheetIds?.has(inp.value)?'':'none' }
async function startImport(F){
  const f=F.pdf.files[0]; if(!f) return;
  const q=new URLSearchParams({id:F.id.value.trim(),name:F.name.value.trim(),rotate:F.rotate.value,replace:F.replace.checked?'1':'0'});
  if(F.replace.checked&&!confirm(`Replace sheet "${F.id.value}"? Its tags are re-read from this PDF (the current ones are backed up).`)) return;
  toast('Uploading…');
  try{
    const r=await fetch('/api/sheets/import?'+q,{method:'POST',credentials:'same-origin',headers:{'Content-Type':'application/pdf'},body:f});
    const d=await r.json().catch(()=>({})); if(!r.ok) throw new Error(d.error||r.statusText);
    idTouched=false; await show('drawings');
  }catch(e){ toast(K.isNetErr(e)?'Offline: this needs the server.':e.message) }
}
async function reimport(id,rotate){
  if(!confirm(`Re-read sheet "${id}" from its stored PDF (orientation: ${rotate})? The current tags are backed up.`)) return;
  await act(()=>K.api('/api/sheets/reimport',{id,rotate}),'Import started');
}
function removeSheet(id,name){ confirm(`Remove "${name}" (${id}) from the app?`)&&act(()=>K.api(`/api/sheets/${encodeURIComponent(id)}/remove`,{}),'Sheet removed') }
function renderJob(job){
  const el=$('#job'); if(!el||!job) return;
  const r=job.result, title={running:'Importing…',done:'Import finished',failed:'Import failed'}[job.state], str=v=>String(v??'');
  const card=h('div',{class:'card'},h('h3',null,`${title} · ${str(job.name)} (${str(job.sheet)})`),
    h('div',{class:'sub'},`by ${str(job.by)} · orientation ${str(job.rotate)}${job.state==='running'?' · this page updates by itself':''}`),
    h('pre',{class:'linkbox',style:'max-height:220px;overflow:auto;white-space:pre-wrap'},job.log.join('\n')));
  if(job.state==='done'&&r){
    const back=(r.rotation+180)%360;
    card.append(h('div',null,h('b',null,String(r.auto)),' tags read automatically, ',h('b',null,String(r.review)),` in the review queue${r.notes?`, ${r.notes} markup note(s)`:''}.${job.version?` Published as plant data version ${job.version}.`:''}`),
      h('div',{class:'sub',style:'margin:6px 0'},'Check the preview is upright. Auto orientation retries sheets that read badly, but it isn\'t guaranteed.'),
      h('img',{src:`data/sheets/${r.id}.png?v=${job.finished}`,alt:'',style:'width:100%;max-height:420px;object-fit:contain;background:#fff;border-radius:4px',onclick:e=>lightbox(e.currentTarget.src)}),
      h('div',{class:'row',style:'margin-top:8px'},appLink('/?sheet='+encodeURIComponent(r.id),{class:'primary',style:'text-decoration:none'},'Open in viewer'),
        h('button',{class:'ghost',onclick:()=>reimport(r.id,String(back))},`Upside down? Re-import rotated to ${back}°`)));
  }
  put(el,card);
}
let pollT=null;
function pollJob(){ clearTimeout(pollT); pollT=setTimeout(async()=>{
  if(tab!=='drawings') return;
  try{ const {job}=await K.api('/api/sheets/job'); if(job?.state==='running'){ renderJob(job); pollJob() } else show('drawings') }catch(e){ pollJob() }
},1500) }

// ---------- actions ----------
async function decide(id,action,force){
  let note='';
  if(action==='reject'){ note=prompt('Reason (optional, shown to the submitter):',''); if(note===null) return }
  if(force&&!confirm('Overwrite the current value with this proposal?')) return;
  const ek=document.getElementById('ek-'+id), ei=document.getElementById('ei-'+id);   // hand-marked tag: approve with the edited code
  const edit=ek&&action==='approve'?{kks:ek.value.trim().toUpperCase(),isa:ei.value.trim().toUpperCase()}:undefined;
  await act(()=>K.api(`/api/submissions/${id}/${action}`,{force:!!force,note,edit}),{approve:'Approved',pick:'Photo chosen, the others of its kind rejected',reject:'Rejected'}[action]);
}
// removed devices and people: hidden from the lists (display only: the log, History and the leaderboard keep them)
const setHidden=(ids,hide)=>act(()=>K.api('/api/hidden',{ids,hide}),hide?'Hidden':'Shown again');
const clearRemoved=()=>act(()=>K.api('/api/hidden',{clear_removed:true}),'Removed devices and people cleared from the lists');
const hiddenBar=(any,n)=>isAdmin()&&(any||n)?h('div',{class:'row',style:'margin:6px 0'},
  any?h('button',{class:'ghost',onclick:clearRemoved},'Clear removed'):null,
  n?h('button',{class:'ghost','aria-pressed':String(SHOW_HIDDEN),onclick:()=>{ SHOW_HIDDEN=!SHOW_HIDDEN; show(tab) }},SHOW_HIDDEN?'Leave hidden out':`Show hidden (${n})`):null):null;
const vote=id=>act(()=>K.api(`/api/submissions/${id}/vote`,{}));
const withdraw=id=>confirm('Withdraw this submission?')&&act(()=>K.api(`/api/submissions/${id}/withdraw`,{}),'Withdrawn');
async function createUser(f){
  const r=await act(()=>K.api('/api/users',{username:f.username.value.trim(),role:f.role.value,full_name:f.full_name.value,position:f.position.value}),'Account created');
  if(r) put($('#newlink'),h('div',{class:'warn'},'Give this link to ',h('b',null,f.username.value),` (valid ${r.expires_days} days, works once):`,h('div',{class:'linkbox'},r.link)));
}
const setUser=(id,d)=>act(()=>K.api(`/api/users/${id}`,d),'Updated');
const setSignupCode=code=>act(()=>K.api('/api/signup-code',{code}),code?'Sign-up is on with the new code':'Sign-up is off');
// "Full Name (username, position, role, 2 devices)": who a person without an account is, for the admin to recognise
const whoIs=p=>`${p.full_name} (${[p.username,p.position,p.role,(p.devices?`${p.devices} device${p.devices===1?'':'s'}`:'no device')+(p.removed?`, ${p.removed} removed`:'')].filter(x=>x).join(', ')})`;
function decideSignup(r,action){
  if(action==='reject') return confirm(`Reject the request of ${r.full_name} (${r.username})? It is deleted.`)&&act(()=>K.api(`/api/signups/${r.id}/reject`,{}),'Request rejected');
  const p=r.person;
  // never by itself: the admin says the request is that person's own
  if(action==='same') return confirm(`This request (sent as “${r.full_name}”) asks for the username of ${whoIs(p)}.\n\nApproving as the same person lets whoever sent it act as ${p.full_name}${p.role==='admin'?', an admin':''} on the web: their submissions, their name on every change. Anyone with the sign-up code can send such a request, so check with ${p.full_name} that it is theirs.\n\nApprove as the same person?`)
    &&act(()=>K.api(`/api/signups/${r.id}/approve`,{person:p.person}),`Approved: ${p.username} can sign in on the web as the same person`);
  let username=r.username;
  if(r.taken){ username=prompt(`The username ${r.username} exists already. Approve ${r.full_name} with which username? (Tell them: they sign in with it.)`,''); if(!username) return }
  return act(()=>K.api(`/api/signups/${r.id}/approve`,{username}),`Approved: ${username} can sign in now`);
}
const exportBundle=photos=>{ if(!K.native) return true; K.native.saveApi('plant.kksbundle','/api/bundle'+(photos?'?photos=1':'')); return false };
const setPerson=(pid,d)=>act(()=>K.api(`/api/persons/${pid}`,d),'Updated');
const syncNow=address=>act(()=>K.api('/api/sync/now',{address}),'Synced');
const setPlantName=name=>act(async()=>{await K.api('/api/settings/plant',{name}); if(K.cfg) K.cfg.plant_name=name.trim();
  document.title=(name.trim()?name.trim()+' — ':'')+'Walkdown'},name.trim()?'Plant name saved: every device shows it after its next sync':'Plant name removed');
const setRelay=url=>act(()=>K.api('/api/settings/relay',{url}),url?'Relay saved: every device learns it at its next sync':'Relay removed');
async function importBundle(inp){ const f=inp.files[0]; if(!f) return; try{ const r=await K.importBundle(f); toast(`Imported ${r.entries} entries, ${r.photos} photos`); show('devices') }catch(e){ toast(e.message) } }
// ---------- join by invite (QR code, or asked on the Wi-Fi without one): PROTOCOL-v2.md §16 ----------
let lobbyTimer=null, lobbySeen='';
async function pollLobby(){
  clearTimeout(lobbyTimer);
  const el=$('#lobby'); if(!el) return;          // left the Devices page
  let r; try{ r=await K.api('/api/join-requests') }catch(e){ put(el,h('div',{class:'sub'},e.message)); return }
  const key=JSON.stringify(r.requests.map(q=>[q.device,q.existing?.username,q.needs_position])), str=v=>String(v??'');
  if(key!==lobbySeen||!el.firstChild){ lobbySeen=key;
    put(el,r.requests.length?r.requests.map(q=>{const x=q.request, c=str(q.code);return h('div',{class:'row',style:'margin-top:8px;align-items:center'},
      h('span',{style:'font-family:var(--mono);font-size:18px;letter-spacing:2px'},`${c.slice(0,3)} ${c.slice(3)}`),
      h('span',null,h('b',null,str(x.full_name)),` (${str(x.username)}${x.position?', '+x.position:''}) · “${x.label||'?'}”`,
        q.existing?[h('br'),h('span',{class:'sub'},`${str(q.existing.full_name)} (${str(q.existing.username)}, ${str(q.existing.role)}) already exists: accepting adds this device as theirs.`)]:null,
        q.needs_position?h('div',{class:'warn needs-position'},noPosition(x.full_name)):null),
      h('button',{class:'primary',disabled:!!q.needs_position,onclick:()=>decideLobby(q.device,'accept',!!q.existing)},'Accept'),h('button',{class:'ghost',onclick:()=>decideLobby(q.device,'refuse')},'Refuse'))})
      :h('div',{class:'sub',style:'margin-top:6px'},'Nobody is waiting.')) }
  lobbyTimer=setTimeout(pollLobby,2000);
}
// every new member needs a position (core certify refuses one without): the request has to be sent again with it
const noPosition=name=>`No position (job title) given. Every new member needs one: ask ${String(name??'them')} to send a new request with their position.`;
async function decideLobby(device,action,existing){
  try{ const r=await K.api(`/api/join-requests/${encodeURIComponent(device)}`,{action,existing_ok:!!existing}); toast(action==='accept'?`Accepted ${r.username}: their device gets the plant over the Wi-Fi now`:'Refused'); lobbySeen=''; pollLobby() }catch(e){ toast(e.message) }
}
async function qrSvg(text){   // zxing-cpp in WebAssembly (decision 0037), error correction M, quiet zone included
  const {qrWrite}=await import('/kks-wasm.js'), q=await qrWrite(text), n=q.side; let d='';
  for(let y=0;y<n;y++) for(let x=0;x<n;x++) if(q.modules[y*n+x]<128) d+=`M${x},${y}h1v1h-1z`;
  return K.svg('svg',{viewBox:`0 0 ${n} ${n}`,width:280,height:280,'shape-rendering':'crispEdges',role:'img','aria-label':'Invite QR code',
    style:'background:#fff;border-radius:6px;display:block;max-width:100%;height:auto'},K.svg('path',{d,fill:'#000'}));
}
const qrButton=()=>h('button',{class:'primary',style:'margin-top:8px',onclick:()=>startInvite()},'Show QR code');
let inviteTimer=null;
async function startInvite(){
  clearTimeout(inviteTimer);
  let r; try{ r=await K.api('/api/invites',{}) }catch(e){ return toast(e.message) }
  const tok=r.invite.token, box=$('#invite');
  const qr=await qrSvg(r.code);
  put(box,h('div',{class:'row',style:'align-items:flex-start;margin-top:8px'},h('div',null,qr),
    h('div',{style:'flex:1;min-width:220px'},h('div',{class:'sub'},`Plant ${r.invite.plant||''} · reachable at ${r.invite.addrs.join(', ')}`),
      h('div',{id:'invstate',style:'margin:8px 0'},'Waiting for a device to scan it…'),
      h('details',null,h('summary',{class:'sub',style:'cursor:pointer'},'No camera? Copy the code instead'),
        h('textarea',{readonly:true,rows:4,style:'width:100%;font-family:var(--mono);font-size:11px',onclick:e=>e.currentTarget.select()},r.code),' ',
        h('button',{class:'ghost',onclick:()=>navigator.clipboard.writeText(r.code).then(()=>toast('Copied'))},'Copy')),
      h('button',{class:'ghost',style:'margin-top:8px',onclick:()=>cancelInvite(tok)},'Cancel'))));
  pollInvite(tok);
}
async function pollInvite(tok){
  const el=$('#invstate'); if(!el) return;            // left the Devices page
  let st; try{ st=await K.api(`/api/invites/${tok}`) }catch(e){ el.textContent=e.message; return }
  const str=v=>String(v??''), who=q=>[h('b',null,str(q.full_name)),` (${str(q.username)}${q.position?', '+q.position:''}) · device “${q.label||'?'}”`];
  if(st.state==='open') el.textContent='Waiting for a device to scan it…';
  else if(st.state==='asked'){ if(el.dataset.asked!==st.request.device){ el.dataset.asked=st.request.device;
      put(el,who(st.request),' wants to join.',st.existing?h('div',{class:'sub'},`${str(st.existing.full_name)} (${str(st.existing.username)}, ${str(st.existing.role)}) already exists: accepting adds this device as theirs. Only if you know it is them.`)
                                                    :h('div',{class:'sub'},'A new person (role: user).'),
        st.needs_position?h('div',{class:'warn needs-position'},noPosition(st.request.full_name)):null,
        h('div',{class:'row',style:'margin-top:6px'},h('button',{class:'primary',disabled:!!st.needs_position,onclick:()=>decideInvite(tok,'accept',!!st.existing)},'Accept'),h('button',{class:'ghost',onclick:()=>decideInvite(tok,'refuse')},'Refuse'))) } }
  else { const end={accepted:()=>['Accepted ',who(st.request),'. Their device is syncing the plant now.'],refused:()=>'Refused.',cancelled:()=>'Cancelled.',expired:()=>'Expired. Show a new code if they still need one.'};
    put(el,Object.prototype.hasOwnProperty.call(end,st.state)?end[st.state]():str(st.state)); return }
  inviteTimer=setTimeout(()=>pollInvite(tok),1500);
}
async function decideInvite(tok,action,existing){
  try{ await K.api(`/api/invites/${tok}`,{action,existing_ok:!!existing}); clearTimeout(inviteTimer); pollInvite(tok) }catch(e){ toast(e.message) }
}
async function cancelInvite(tok){ clearTimeout(inviteTimer); try{ await K.api(`/api/invites/${tok}`,{action:'cancel'}) }catch(e){} put($('#invite'),qrButton()) }
async function importJoin(inp,existing_ok){
  const f=inp.files?inp.files[0]:null, request=inp.request||JSON.parse(await f.text());
  try{ const r=await K.api('/api/devices/import-request',{request,existing_ok:!!existing_ok}); toast(`Certified a device for ${r.username}. Now give them a bundle.`); show('devices') }
  catch(e){ if(e.status===409&&e.data?.existing){ const x=e.data.existing;
      if(confirm(`${x.full_name} (${x.username}, ${x.role}) already exists. Add this computer as another device of theirs? Only if you know it is them.`)) return importJoin({request},true) }
    else toast(e.message) }
}
const linkBox=(name,r)=>r&&$('#main').prepend(h('div',{class:'warn'},'Password link for ',h('b',null,name),` (valid ${r.expires_days} days, works once):`,h('div',{class:'linkbox'},r.link)));
async function resetLink(id,name){
  if(!confirm(`Create a new password link for ${name}? Their current password keeps working until they use it.`)) return;
  linkBox(name,await act(()=>K.api(`/api/users/${id}/reset`,{})));
}
async function webSignin(u){
  if(!confirm(`Give ${u.full_name||u.username} (${u.username}${u.role==='admin'?', an admin':''}) a web sign-in? You get a one-time link to send them: with it they set a password and use the web app as the same person.`+(u.active?'':' Their devices were all removed: this lets them in again, on the web.'))) return;
  linkBox(u.username,await act(()=>K.api(`/api/persons/${u.person}/account`,{}),'Web sign-in created'));
}
async function revert(rev,force){
  try{ await K.api(`/api/revisions/${rev}/revert`,{force:!!force}); toast('Reverted'); show('history') }
  catch(e){ if(e.status===409&&confirm('This item was changed again after that revision. Revert anyway (discarding the later change)?')) return revert(rev,true); if(e.status!==409) toast(e.message) }
}
const restoreTo=(hid,rev)=>confirm(hid?`Put all plant data back to how it was right after revision ${rev}? Later changes stay in History and can be re-applied.`:'Put all plant data back to how it was before the first logged change?')&&act(()=>K.api('/api/restore',hid?{hid}:{rev:0}),'Restored');
// ---------- updates (M5b): signed GitHub releases, checked daily, installed only when asked ----------
async function renderUpdate(u){
  const el=$('#upd'); if(!el) return;
  try{ u=u||await K.api('/api/update') }catch(e){ put(el,h('p',{class:'sub'},K.isNetErr(e)?'Cannot reach the server.':e.message)); return }   // (server: admins only)
  const mayAct=K.cfg?.mode==='peer'||isManager(), str=v=>String(v??'');
  const out=[h('h3',null,'Updates'),h('div',null,'This is version ',h('b',null,str(u.current)),'.')];
  if(u.staged) out.push(h('div',{class:'warn',style:'margin-top:8px'},`Version ${u.staged} is installed: close Walkdown (Quit) and start it again to use it.`));
  else if(u.busy) out.push(h('div',{class:'sub',style:'margin-top:8px'},`${u.busy==='unpacking'?'Unpacking…':'Downloading…'} this page updates by itself.`));
  else if(u.available){
    let page=null;   // the release page, from the update check: http(s) only
    if(u.page){ page=h('a',{target:'_blank',rel:'noopener'},'What\'s new'); page.href=K.safeUrl(u.page) }
    out.push(h('div',{style:'margin-top:8px'},h('b',null,`Version ${str(u.latest)} is out.`),' ',page),
      u.notes?h('pre',{class:'linkbox',style:'max-height:160px;overflow:auto;white-space:pre-wrap'},u.notes):null,
      u.can_install&&mayAct?[h('div',{class:'row',style:'margin-top:8px'},h('button',{class:'primary',onclick:()=>installUpdate()},'Download and install')),
          h('div',{class:'sub'},'Checked against the release\'s signature before anything is installed; your data stays where it is. It runs from the next start.')]
        :h('div',{class:'sub',style:'margin-top:6px'},u.how==='git'?['This copy runs from source: update it with ',h('span',{class:'mono'},'git pull'),' and restart it.']:'There is no package of it for this system.'));
  } else if(u.latest) out.push(h('div',{class:'sub',style:'margin-top:6px'},'Up to date.'));
  if(u.error) out.push(h('div',{class:'sub del',style:'margin-top:6px'},`Last check: ${u.error}`));
  out.push(h('div',{class:'row',style:'margin-top:8px'},mayAct?h('button',{class:'ghost',onclick:()=>checkUpdate()},'Check now'):null,
    h('span',{class:'sub'},(u.checked?`Checked ${K.ago(u.checked)}`:'Not checked yet')+(u.auto?' · checks by itself once a day':' · automatic checks are off (update_check)'))));
  put(el,h('div',{class:'card'},out));
  if(u.busy) setTimeout(()=>tab==='updates'&&renderUpdate(),1500);
}
async function checkUpdate(){ try{ renderUpdate(await K.api('/api/update/check',{})) }catch(e){ toast(e.message) } }
async function installUpdate(){ try{ renderUpdate(await K.api('/api/update/install',{})) }catch(e){ toast(e.message) } }
async function saveDetails(f){ if(await act(()=>K.api('/api/profile',{full_name:f.full_name.value,position:f.position.value}),'Saved')){ ME=await K.api('/api/me'); $('#who').textContent=`${ME.user.full_name||ME.user.username} · ${ME.user.role}`; show('account') } }
async function editDetails(id,name,pos){
  const n=prompt('Full name:',name); if(n===null) return; const p=prompt('Position (optional):',pos); if(p===null) return;
  await act(()=>K.api(`/api/users/${id}`,{full_name:n,position:p}),'Details updated');
}
async function changePw(f){ if(await act(()=>K.api('/api/password',{old:f.old.value,new:f.new.value}),'Password changed. Other devices are signed out.')) f.reset() }
const mgr=(a,d={})=>(a!=='accept'||confirm('Become the manager?'))&&act(()=>K.api('/api/manager/'+a,d),{transfer:'Offer sent',accept:'You are now the manager',decline:'Declined',cancel:'Offer cancelled'}[a]).then(r=>{ if(r&&a==='accept') location.reload() });
init();
