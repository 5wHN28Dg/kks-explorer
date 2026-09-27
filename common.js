// Shared by index.html and admin.html: API calls, login gate, offline storage (IndexedDB), outbox sync.
// Offline model: plant data is cached by the service worker (sw.js); changes made offline go to an outbox and are
// sent as ordinary submissions when the server is reachable. Submissions are proposals, so replaying them later
// can't clobber anything: the server merges non-overlapping edits and flags real conflicts for an admin.
'use strict';
const K = {me: null, online: true, reauth: false, outbox: [], listeners: []};

// Inside the Android app (window.KKSNative): API calls go to the app's own node through the bridge (the WebView can't
// hand POST bodies to the app); replies arrive via K.nativeReply. Everything else is the same as in a browser.
K.native = window.KKSNative || null;
K.nativeCalls = new Map(); K.nativeSeq = 0;
K.nativeReply = (id, status, text) => { const f = K.nativeCalls.get(id); K.nativeCalls.delete(id); if (f) f([status, text]) };
K.nativeCall = (method, url, body, base64) => new Promise(res => {
  const id = String(++K.nativeSeq); K.nativeCalls.set(id, res);
  if (base64 !== undefined) K.native.requestBytes(id, url, base64);
  else K.native.request(id, method, url, body === undefined ? null : JSON.stringify(body));
});
K.nativeResult = ([status, text]) => {
  let d = null; try { d = JSON.parse(text) } catch (e) {}
  if (status >= 400) { const e = new Error(d?.error || 'error ' + status); e.status = status; e.data = d; throw e }
  return d;
};

K.api = async (url, body) => {
  if (K.native && url.startsWith('/api/')) return K.nativeResult(await K.nativeCall(body === undefined ? 'GET' : 'POST', url, body));
  let r;
  try {
    r = await fetch(url, body === undefined ? {credentials: 'same-origin'} :
      {method: 'POST', credentials: 'same-origin', headers: {'Content-Type': 'application/json'}, body: JSON.stringify(body)});
  } catch (e) {
    K.setReauth(await K.accessExpired()); K.setOnline(false);
    throw e;  // either way the server can't be used right now: callers queue changes / use the offline copy
  }
  const cached = r.headers.get('X-KKS-From-Cache');  // set by sw.js when it answered from the saved copy
  K.setReauth(cached === 'reauth'); K.setOnline(!cached);
  let d = null; try { d = await r.json() } catch (e) {}
  if (!r.ok) { const e = new Error(d?.error || r.statusText); e.status = r.status; e.data = d; throw e }
  return d;
};
K.isNetErr = e => !e.status;  // fetch rejects without a status when the server can't be reached
// Behind Cloudflare Access, an expired Access session turns every request into a redirect to the Cloudflare login
// page. fetch() reports that exactly like a network failure, so probe once without following redirects.
K.accessExpired = async () => {
  try { return (await fetch('/api/config', {redirect: 'manual', cache: 'no-store'})).type === 'opaqueredirect' }
  catch (e) { return false }
};
K.setReauth = on => { if (K.reauth !== on) { K.reauth = on; K.renderStatus() } };
K.esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[c]));
K.uid = () => [...crypto.getRandomValues(new Uint8Array(16))].map(b => b.toString(16).padStart(2, '0')).join('');

// ---------- IndexedDB: kv (cached session info) + outbox (queued submissions) ----------
K.idb = (() => {
  let p;
  const open = () => p ??= new Promise((res, rej) => {
    const q = indexedDB.open('kks-explorer', 1);
    q.onupgradeneeded = () => { q.result.createObjectStore('kv'); q.result.createObjectStore('outbox', {keyPath: 'client_id'}) };
    q.onsuccess = () => res(q.result); q.onerror = () => rej(q.error);
  });
  const tx = async (store, mode, fn) => { const db = await open(); return new Promise((res, rej) => {
    const t = db.transaction(store, mode), r = fn(t.objectStore(store));
    t.oncomplete = () => res(r?.result); t.onerror = () => rej(t.error) }) };
  return {
    get: k => tx('kv', 'readonly', s => s.get(k)), set: (k, v) => tx('kv', 'readwrite', s => s.put(v, k)),
    clear: () => tx('kv', 'readwrite', s => s.clear()),
    queue: it => tx('outbox', 'readwrite', s => s.put(it)), all: () => tx('outbox', 'readonly', s => s.getAll()),
    unqueue: id => tx('outbox', 'readwrite', s => s.delete(id)),
  };
})();

K.onChange = fn => K.listeners.push(fn);
K.emit = async () => { K.outbox = (await K.idb.all()).filter(i => i.user === K.me?.user.id); K.renderStatus(); K.listeners.forEach(f => f()) };

// ---------- overlay screens (login, setup, password link, offline lock) ----------
K.css = `#kov{position:fixed;inset:0;z-index:200;background:var(--chrome,#1c2730);color:var(--ink,#e9eef2);display:flex;align-items:center;justify-content:center;font:14px/1.45 system-ui,sans-serif;padding:16px}
#kov form,#kov .box{background:var(--chrome2,#243440);border:1px solid var(--line,#3a5061);border-radius:10px;padding:20px;width:100%;max-width:360px;display:flex;flex-direction:column;gap:10px}
#kov h1{font-size:18px;margin:0}#kov p{margin:0;color:var(--muted,#94a6b4)}#kov input{padding:9px 10px;border-radius:6px;border:1px solid var(--line,#3a5061);background:var(--chrome,#1c2730);color:inherit;font:inherit}
#kov button{background:var(--accent,#ff7a1a);color:#1c2730;border:0;border-radius:6px;padding:9px;font-weight:650;cursor:pointer;font:inherit}#kov button.back{background:none;border:1px solid var(--line,#3a5061);color:inherit;font-weight:400}#kov .err{color:var(--bad,#ff5a5a);min-height:1em}`;
K.overlay = html => {
  if (!document.getElementById('kovcss')) { const s = document.createElement('style'); s.id = 'kovcss'; s.textContent = K.css; document.head.appendChild(s) }
  let o = document.getElementById('kov'); if (!o) { o = document.createElement('div'); o.id = 'kov'; document.body.appendChild(o) }
  o.innerHTML = html; return o;
};
// back: optional; adds "← Back" (also Esc) for forms reached from a choice screen
K.form = (title, sub, fields, button, onsubmit, back) => {
  const o = K.overlay(`<form autocomplete="on"><h1>${K.esc(title)}</h1>${sub ? `<p>${sub}</p>` : ''}
    ${fields.map(f => `<input name="${f.name}" type="${f.type || 'text'}" placeholder="${K.esc(f.label)}" autocomplete="${f.ac || 'off'}" ${f.value ? `value="${K.esc(f.value)}" readonly` : ''} ${f.optional ? '' : 'required'}>`).join('')}
    <div class="err"></div><button>${K.esc(button)}</button>${back ? '<button type="button" class="back">← Back</button>' : ''}</form>`);
  const f = o.querySelector('form'); f.querySelector('input:not([readonly])')?.focus();
  if (back) { f.querySelector('.back').onclick = back; f.onkeydown = e => { if (e.key === 'Escape') back() } }
  f.onsubmit = async e => { e.preventDefault(); const v = Object.fromEntries(new FormData(f)); f.querySelector('.err').textContent = '';
    try { await onsubmit(v) } catch (err) { f.querySelector('.err').textContent = K.isNetErr(err) ? 'Cannot reach the server.' : err.message } };
};
const pwFields = [{name: 'password', type: 'password', label: 'New password (10+ characters)', ac: 'new-password'},
                  {name: 'password2', type: 'password', label: 'Repeat password', ac: 'new-password'}];
const samePw = v => { if (v.password !== v.password2) throw new Error('Passwords differ.') };
const done = () => { history.replaceState(null, '', location.pathname); location.reload() };

// Resolves with /api/me when the app may proceed (online, or offline within the lease). Otherwise shows a screen.
K.start = async () => {
  K.renderStatus();
  const h = new URLSearchParams(location.hash.slice(1));
  const cfg = K.cfg = await K.api('/api/config').catch(() => null);
  if (cfg) document.title = cfg.plant_name + ' — KKS Explorer';
  if (cfg?.mode === 'peer') document.documentElement.classList.add('peer');
  if (cfg?.app) document.documentElement.classList.add('app');   // inside the Android app: it has its own header and back
  if (cfg?.mode === 'peer' && !cfg.node.joined) return new Promise(() => K.joinScreen(cfg));
  if (h.get('setup')) return new Promise(() => K.form('Create the manager account', 'One-time link from the server console. The manager is the top account: it promotes admins and can hand the role over later.',
    [{name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position at the company (optional)', ac: 'organization-title', optional: true},
     {name: 'username', label: 'Username', ac: 'username'}, ...pwFields], 'Create manager', async v => {
      samePw(v); await K.api('/api/setup', {token: h.get('setup'), username: v.username, password: v.password, full_name: v.full_name, position: v.position}); done() }));
  if (h.get('reset')) {
    const info = await K.api(`/api/token-info?kind=reset&token=${encodeURIComponent(h.get('reset'))}`).catch(e => ({error: e.message}));
    if (info.error) { K.overlay(`<div class="box"><h1>Link not valid</h1><p>${K.esc(info.error)} Ask an admin for a new one.</p></div>`); return new Promise(() => {}) }
    return new Promise(() => K.form('Set your password', '', [{name: 'u', label: '', value: info.username, ac: 'username'}, ...pwFields], 'Save password', async v => {
      samePw(v); await K.api('/api/password-reset', {token: h.get('reset'), password: v.password}); done() }));
  }
  try {
    const me = await K.api('/api/me');
    K.me = me; K.setOnline(true);
    await K.idb.set('me', {...me, lease_until: Date.now() + me.offline_days * 864e5});
    await K.emit(); K.flushSoon(500);
    return me;
  } catch (e) {
    if (e.status === 401) {
      await K.wipe();
      return new Promise(() => K.form(cfg?.plant_name || 'KKS Explorer', cfg?.setup_needed ? 'No manager account exists yet: use the setup link printed on the server console.' : 'Sign in to see plant data.',
        [{name: 'username', label: 'Username', ac: 'username'}, {name: 'password', type: 'password', label: 'Password', ac: 'current-password'}], 'Sign in',
        async v => { await K.api('/api/login', v); location.reload() }));
    }
    const c = await K.idb.get('me');
    if (c && c.lease_until > Date.now()) { K.me = c; K.setOnline(false); await K.emit(); return c }
    if (K.reauth) {  // remote access sign-in expired and no usable offline copy: send them through the login
      K.overlay(`<div class="box"><h1>Sign in again</h1><p>Your remote-access sign-in has expired.</p><button onclick="location.reload()">Continue</button></div>`);
      return new Promise(() => {});
    }
    K.overlay(`<div class="box"><h1>Offline</h1><p>${c ? `Offline access on this device expired (it lasts ${c.offline_days} days after the last sign-in check). Connect to the server to continue.` : 'Cannot reach the server, and this device has no offline copy yet.'}</p><button onclick="location.reload()">Retry</button></div>`);
    return new Promise(() => {});
  }
};

// ---------- peer mode: this computer is one person's device; set it up before first use ----------
K.download = (data, name, type = 'application/json') => {
  if (K.native) return K.native.saveFile(name, type, data);   // Android: its own "save as" dialog
  const a = document.createElement('a'); a.href = URL.createObjectURL(new Blob([data], {type})); a.download = name;
  document.body.appendChild(a); a.click(); setTimeout(() => { URL.revokeObjectURL(a.href); a.remove() }, 1000);
};
K.importBundle = async file => {
  if (K.native) {
    const b64 = await new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(fr.result.split(',')[1] || ''); fr.onerror = rej; fr.readAsDataURL(file) });
    return K.nativeResult(await K.nativeCall('POST', '/api/bundle/import', undefined, b64));
  }
  const r = await fetch('/api/bundle/import', {method: 'POST', credentials: 'same-origin', headers: {'Content-Type': 'application/octet-stream'}, body: file});
  const d = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(d.error || r.statusText);
  return d;
};
K.joinScreen = (cfg, note = '') => {
  const dev = cfg.app ? 'phone' : 'computer';
  const o = K.overlay(`<div class="box"><h1>Set up this ${dev}</h1>
    <p>This ${dev} keeps its own copy of the plant data and syncs with the other devices on the same Wi-Fi.</p>
    ${cfg.node.has_plant ? '<p>It already holds a plant\'s data but is not certified in it yet: import the bundle an admin gave you, or join through the server.</p>' : ''}
    <button data-a="qr">Join with a QR code from an admin</button>
    <button data-a="server">Join through the plant server</button>
    <button data-a="request">Join through an admin (no server)</button>
    <button data-a="bundle">Import a bundle an admin gave you</button>
    ${cfg.node.has_plant || cfg.node.can_create === false ? '' : '<button data-a="new" style="background:none;border:1px solid var(--line,#3a5061);color:inherit">Start a new plant (you become its manager)</button>'}
    <input type="file" accept=".kksbundle" hidden><div class="err">${K.esc(note)}</div>
    <p style="font-size:12px;opacity:.7">Device ${K.esc((cfg.node.device || 'not created yet').slice(0, 12))}…</p></div>`);
  const back = n => K.joinScreen(cfg, n);
  const choices = () => { if (history.state?.join) history.back(); else back() };   // ← Back = the browser's Back
  onpopstate = () => { const n = K.joinNote || ''; K.joinNote = ''; back(n) };
  const sub = (...a) => { history.pushState({join: 1}, ''); K.form(...a, choices); K.back = () => { choices(); return true } };
  K.back = null;   // on the choices themselves, the phone's Back leaves the app
  const file = o.querySelector('input[type=file]');
  file.onchange = async () => {
    try { const r = await K.importBundle(file.files[0]); if (r.joined) return location.reload();
      back(`Imported ${r.entries} entries, but this ${dev} is not certified in that bundle. Ask the admin to import your join request first.`) }
    catch (e) { back(e.message) }
  };
  o.querySelectorAll('button[data-a]').forEach(b => b.onclick = () => ({
    bundle: () => file.click(),
    qr: () => { const scan = !!(K.native && K.native.scanQr);
      sub('Join with a QR code', `For when an admin is next to you on the same network: they open Manage → Devices → “Add a device with a QR code”. `
        + (scan ? 'Fill in your details, then scan their screen.' : `This ${dev} can't scan: ask the admin to copy the code under the QR code and send it to you, then paste it here.`),
      [{name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position (optional)', optional: true},
       {name: 'username', label: 'Username (if you have an account already, the same one)', ac: 'username'},
       ...(scan ? [] : [{name: 'invite', label: 'Invite code (starts with {"kks_invite"…)'}])], scan ? 'Scan the QR code' : 'Join',
      async v => { if (scan) { v.invite = await K.scanQr(); if (!v.invite) return }
        await K.api('/api/node/join-invite', v); K.joinWait(cfg) }) },
    server: () => sub('Join through the plant server', `Your normal account on the plant server. The server certifies this ${dev} as yours; afterwards it syncs by itself on the same Wi-Fi.`,
      [{name: 'url', label: 'Server address, e.g. http://192.168.1.20:8420'}, {name: 'username', label: 'Username', ac: 'username'},
       {name: 'password', type: 'password', label: 'Password', ac: 'current-password'}], 'Join',
      async v => { await K.api('/api/node/join-server', v); location.reload() }),
    request: () => sub('Join through an admin', `You get a small file to give an admin (USB, WhatsApp, email). They certify this ${dev} and give you a bundle file back; import it here.`,
      [{name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position (optional)', optional: true},
       {name: 'username', label: 'Username (if you have an account already, the same one)', ac: 'username'}], 'Make the request file',
      async v => { const r = await K.api('/api/node/join-request', v);
        K.download(JSON.stringify(r.request, null, 1), `join-${v.username}.kksjoin`);
        cfg.node.device = r.request.device;
        K.joinNote = 'Request file saved. When the admin gives you a bundle, choose "Import a bundle".'; history.back() }),
    new: () => sub('Start a new plant', 'Only if no plant exists yet. This computer creates the plant\'s root key and you become the manager. Back the key up afterwards (Manage → Devices).',
      [{name: 'plant', label: 'Plant name'}, {name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position (optional)', optional: true},
       {name: 'username', label: 'Username', ac: 'username'}], 'Create the plant',
      async v => { await K.api('/api/node/new-plant', v); location.reload() }),
  })[b.dataset.a]());
};

// Scanning a QR code: only the Android app can (native scanner). -> the text, or null if cancelled.
K.scanQr = () => new Promise(res => {
  const id = String(++K.nativeSeq); K.nativeCalls.set(id, ([status, text]) => res(status === 200 ? text : null));
  K.native.scanQr(id);
});
// Join by invite, after the request went out: wait for the admin to accept, then for the first sync.
K.joinWait = cfg => {
  const o = K.overlay(`<div class="box"><h1>Joining ${K.esc(cfg.plant_name || 'the plant')}</h1><p class="st">Connecting to the admin's device…</p>
    <div class="err"></div><button type="button" class="back">Cancel</button></div>`);
  let stop = false;
  const cancel = async () => { stop = true; try { await K.api('/api/node/join-invite', {cancel: true}) } catch (e) {} K.joinScreen(cfg) };
  o.querySelector('.back').onclick = cancel; K.back = () => { cancel(); return true };
  const tick = async () => {
    if (stop) return;
    let st; try { st = await K.api('/api/node/join-invite') } catch (e) { st = {state: 'connecting', error: e.message} }
    if (st.state === 'joined') return location.reload();
    const msg = {connecting: 'Connecting to the admin\'s device…', waiting: 'Waiting for the admin to accept on their screen…',
                 syncing: 'Accepted. Getting the plant data…'}[st.state];
    if (!msg) { o.querySelector('.st').textContent = st.state === 'cancelled' ? 'Cancelled.' : 'Could not join.';
      o.querySelector('.err').textContent = st.error || ''; o.querySelector('.back').textContent = '← Back'; return }
    o.querySelector('.st').textContent = msg;
    o.querySelector('.err').textContent = st.state === 'connecting' ? (st.error || '') : '';
    setTimeout(tick, 1000);
  };
  tick();
};

// Remove plant data from this device (logout, account revoked, session expired). Queued changes are kept per user.
K.wipe = async () => {
  try { await caches.delete('kks-data') } catch (e) {}
  try { await K.idb.clear() } catch (e) {}
};
K.logout = async () => {
  if (K.outbox.length && !confirm(`${K.outbox.length} change(s) not sent yet. They stay on this device and are sent the next time you sign in here. Log out?`)) return;
  try { await K.api('/api/logout', {}) } catch (e) {}
  await K.wipe(); location.href = '/';
};

// ---------- submissions + outbox ----------
K.submit = async (kind, payload) => {
  const item = {client_id: K.uid(), kind, payload};
  try { const r = await K.api('/api/submit', item); K.setOnline(true); return r }
  catch (e) {
    if (!K.isNetErr(e)) throw e;
    await K.idb.queue({...item, user: K.me.user.id, ts: Date.now()}); K.setOnline(false); await K.emit(); K.flushSoon();
    return {status: 'queued'};
  }
};
let flushing = false, flushTimer = null;
K.flushSoon = (ms = 20000) => { clearTimeout(flushTimer); flushTimer = setTimeout(K.flush, ms) };
K.flush = async () => {
  if (flushing || !K.me) return; flushing = true;
  const res = {approved: 0, pending: 0, conflict: 0, failed: 0};
  try {
    for (const it of (await K.idb.all()).filter(i => i.user === K.me.user.id).sort((a, b) => a.ts - b.ts)) {
      try {
        const r = await K.api('/api/submit', {client_id: it.client_id, kind: it.kind, payload: it.payload});
        res[r.status] = (res[r.status] || 0) + 1; await K.idb.unqueue(it.client_id); K.setOnline(true);
      } catch (e) {
        if (K.isNetErr(e)) { K.setOnline(false); break }
        if (e.status === 401) { location.reload(); return }
        res.failed++; await K.idb.unqueue(it.client_id);  // rejected as invalid: retrying won't help
        console.warn('queued submission refused', it, e.message);
      }
    }
  } finally { flushing = false }
  await K.emit();
  const sent = res.approved + res.pending + res.conflict;
  if (sent || res.failed) K.toast?.(`Synced ${sent} offline change(s)` + (res.pending ? ` · ${res.pending} awaiting approval` : '') +
    (res.conflict ? ` · ${res.conflict} conflict(s) for an admin` : '') + (res.failed ? ` · ${res.failed} refused` : ''));
  if (K.outbox.length) K.flushSoon();
  if (sent) K.listeners.forEach(f => f('synced'));
};
K.setOnline = on => { if (K.online !== on) { K.online = on; K.renderStatus() } };
addEventListener('online', () => K.flushSoon(500));
addEventListener('offline', () => K.setOnline(false));

K.renderStatus = () => {
  const el = document.getElementById('syncStatus'); if (!el) return;
  const n = K.outbox.length;
  if (K.reauth) {  // a top-level load of the page lets Cloudflare Access show its login, then comes back here
    el.innerHTML = `<span style="color:var(--review)">●</span> <a href="${location.pathname}" style="color:var(--accent)">Sign in again</a>${n ? ` · ${n} queued` : ''}`;
    el.title = 'Your remote-access sign-in expired. Working from the copy on this device; changes are queued.';
    return;
  }
  el.innerHTML = `<span style="color:${K.online ? 'var(--ok)' : 'var(--review)'}">●</span> ${K.online ? 'Online' : 'Offline'}${n ? ` · ${n} queued` : ''}`;
  el.title = K.online ? 'Connected to the server' : 'Working from the copy on this device; changes are queued';
};

// Human summary of a submission payload.
K.describe = (kind, p) => ({
  equipment: () => Object.entries(p.changes).map(([f, v]) => `${f} → ${f === 'custom' ? v.map(c => c.k + ': ' + c.v).join('; ') || '(none)' : v || '(empty)'}`).join(' · '),
  review: () => !p.data ? `tag ${p.tag_id}: clear the review decision` : p.data.status === 'rejected' ? `tag ${p.tag_id}: not a tag` : `tag ${p.tag_id}: confirm as ${p.data.kks}${p.data.suffix || ''}${p.data.isa ? ' (' + p.data.isa + ')' : ''}`,
  link: () => `${p.on === false ? 'unlink' : 'link'} ${p.kks} ${p.on === false ? 'from' : 'to'} procedure ${p.proc} step ${p.step}`,
  photo: () => `new photo for ${p.kks}${p.caption ? ': ' + p.caption : ''}`,
  photo_delete: () => `delete photo ${p.photo_id.slice(0, 8)}`,
  tag_add: () => `mark a missed tag on ${p.sheet}: ${p.kks ? (p.isa ? p.isa + ' ' : '') + p.kks + (p.suffix || '') : '(code not given)'}`,
  tag_remove: () => `remove hand-added tag ${p.id.slice(0, 8)}`,
}[kind] || (() => kind))();

if ('serviceWorker' in navigator && !K.native) navigator.serviceWorker.register('/sw.js').catch(e => console.warn('service worker not registered', e));
