// Shared by index.html and admin.html: API calls, login gate, offline storage (IndexedDB), outbox sync.
// Offline model: plant data is cached by the service worker (sw.js); changes made offline go to an outbox and are
// sent as ordinary submissions when the server is reachable. Submissions are proposals, so replaying them later
// can't clobber anything: the server merges non-overlapping edits and flags real conflicts for an admin.
'use strict';
const K = {me: null, online: true, reauth: false, outbox: [], listeners: []};

K.api = async (url, body) => {
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
#kov button{background:var(--accent,#ff7a1a);color:#1c2730;border:0;border-radius:6px;padding:9px;font-weight:650;cursor:pointer;font:inherit}#kov .err{color:var(--bad,#ff5a5a);min-height:1em}`;
K.overlay = html => {
  if (!document.getElementById('kovcss')) { const s = document.createElement('style'); s.id = 'kovcss'; s.textContent = K.css; document.head.appendChild(s) }
  let o = document.getElementById('kov'); if (!o) { o = document.createElement('div'); o.id = 'kov'; document.body.appendChild(o) }
  o.innerHTML = html; return o;
};
K.form = (title, sub, fields, button, onsubmit) => {
  const o = K.overlay(`<form autocomplete="on"><h1>${K.esc(title)}</h1>${sub ? `<p>${sub}</p>` : ''}
    ${fields.map(f => `<input name="${f.name}" type="${f.type || 'text'}" placeholder="${K.esc(f.label)}" autocomplete="${f.ac || 'off'}" ${f.value ? `value="${K.esc(f.value)}" readonly` : ''} required>`).join('')}
    <div class="err"></div><button>${K.esc(button)}</button></form>`);
  const f = o.querySelector('form'); f.querySelector('input:not([readonly])')?.focus();
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
  if (h.get('setup')) return new Promise(() => K.form('Create the manager account', 'One-time link from the server console. The manager is the top account: it promotes admins and can hand the role over later.',
    [{name: 'username', label: 'Username', ac: 'username'}, ...pwFields], 'Create manager', async v => {
      samePw(v); await K.api('/api/setup', {token: h.get('setup'), username: v.username, password: v.password}); done() }));
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
  review: () => p.data.status === 'rejected' ? `tag ${p.tag_id}: not a tag` : `tag ${p.tag_id}: confirm as ${p.data.kks}${p.data.suffix || ''}${p.data.isa ? ' (' + p.data.isa + ')' : ''}`,
  link: () => `${p.on === false ? 'unlink' : 'link'} ${p.kks} ${p.on === false ? 'from' : 'to'} procedure ${p.proc} step ${p.step}`,
  photo: () => `new photo for ${p.kks}${p.caption ? ': ' + p.caption : ''}`,
  photo_delete: () => `delete photo ${p.photo_id.slice(0, 8)}`,
}[kind] || (() => kind))();

if ('serviceWorker' in navigator) navigator.serviceWorker.register('/sw.js').catch(e => console.warn('service worker not registered', e));
