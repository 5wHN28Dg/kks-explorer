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
// ---------- building elements without markup (no HTML sink takes data) ----------
// K.h(tag, props, ...children) -> a new element; K.svg the same in the SVG namespace. Children: strings and numbers
// become text nodes, nodes go in as they are, arrays are flattened; null, undefined and false are left out. props:
// attributes by name (true = present; false, null or undefined = left out); `on<event>` must be a function and is
// attached with addEventListener (a string is refused: no inline handlers). Attributes that take a URL are refused,
// except an image's or media element's src: a link's href is set on the element itself, through K.safeUrl, where the
// static check sees it. Elements that run or load code (script, iframe, object, ...) are refused.
K.build = (el, props, kids) => {
  const tag = el.localName.toLowerCase();
  if (/^(script|iframe|frame|frameset|object|embed|applet|base|link|meta|style|template|foreignobject|use|animate|set)$/.test(tag))
    throw new TypeError(`K.h: <${tag}> is not built here`);
  for (const [k, v] of Object.entries(props || {})) {
    const name = k.toLowerCase();
    if (name.startsWith('on')) {
      if (v == null || v === false) continue;   // no handler, like any other absent attribute
      if (typeof v !== 'function') throw new TypeError(`K.h: ${k} must be a function`);
      el.addEventListener(name.slice(2), v); continue;
    }
    if (/^(href|xlink:href|action|formaction|srcdoc|data|poster|background|ping|codebase|cite|longdesc|manifest|src|srcset)$/.test(name)
        && !(/^(src|srcset)$/.test(name) && /^(img|source|audio|video|track)$/.test(tag)))
      throw new TypeError(`K.h: set ${k} on the element itself`);
    if (v == null || v === false) continue;
    el.setAttribute(k, v === true ? '' : String(v));
  }
  el.append(...kids.flat(Infinity).filter(c => c != null && c !== false).map(c => c instanceof Node ? c : String(c)));
  return el;
};
K.h = (tag, props, ...kids) => K.build(document.createElement(tag), props, kids);
K.svg = (tag, props, ...kids) => K.build(document.createElementNS('http://www.w3.org/2000/svg', tag), props, kids);
// A URL from data, checked before it becomes a link. Allowed: http and https (a relative URL resolves against
// this page). -> the URL as given, or 'about:blank' for anything else (javascript:, data:, blob:, a URL that doesn't
// parse, no URL at all).
K.safeUrl = (u, schemes = ['http:', 'https:']) => {
  try { if (u != null && schemes.includes(new URL(String(u), location.href).protocol)) return String(u) } catch (e) {}
  return 'about:blank';
};
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
// The overlay screen, holding these nodes (K.h).
K.overlay = (...nodes) => {
  if (!document.getElementById('kovcss')) { const s = document.createElement('style'); s.id = 'kovcss'; s.textContent = K.css; document.head.appendChild(s) }
  let o = document.getElementById('kov'); if (!o) { o = document.createElement('div'); o.id = 'kov'; document.body.appendChild(o) }
  o.replaceChildren(...nodes); return o;
};
// A box on the overlay: a title, a text, and optionally a button (its label, what it does).
K.box = (title, text, button, onclick) => K.overlay(K.h('div', {class: 'box'}, K.h('h1', null, title), K.h('p', null, text),
  button ? K.h('button', {onclick}, button) : null));
// back: optional; adds "← Back" (also Esc) for forms reached from a choice screen
K.form = (title, sub, fields, button, onsubmit, back) => {
  const h = K.h;
  const o = K.overlay(h('form', {autocomplete: 'on'}, h('h1', null, title), sub ? h('p', null, sub) : null,
    fields.map(f => h('input', {name: f.name, type: f.type || 'text', placeholder: f.label, autocomplete: f.ac || 'off',
                                value: f.value || null, readonly: !!f.value, required: !f.optional})),
    h('div', {class: 'err'}), h('button', null, button), back ? h('button', {type: 'button', class: 'back'}, '← Back') : null));
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
  if (cfg) document.title = (cfg.plant_name ? cfg.plant_name + ' — ' : '') + 'Walkdown';
  if (cfg?.mode === 'peer') document.documentElement.classList.add('peer');
  if (cfg?.app) document.documentElement.classList.add('app');   // inside the Android app: it has its own header and back
  if (cfg?.mode === 'peer' && !cfg.node.joined) {
    if (cfg.node.removed) await K.wipe();   // removed from the plant: nothing of it stays in this browser either
    return new Promise(() => K.joinScreen(cfg));
  }
  if (h.get('setup')) return new Promise(() => K.form('Create the manager account', 'One-time link from the server console. The manager is the top account: it promotes admins and can hand the role over later.',
    [{name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position at the company (optional)', ac: 'organization-title', optional: true},
     {name: 'username', label: 'Username', ac: 'username'}, ...pwFields], 'Create manager', async v => {
      samePw(v); await K.api('/api/setup', {token: h.get('setup'), username: v.username, password: v.password, full_name: v.full_name, position: v.position}); done() }));
  if (h.get('reset')) {
    const info = await K.api(`/api/token-info?kind=reset&token=${encodeURIComponent(h.get('reset'))}`).catch(e => ({error: e.message}));
    if (info.error) { K.box('Link not valid', `${info.error} Ask an admin for a new one.`); return new Promise(() => {}) }
    return new Promise(() => K.form('Set your password', '', [{name: 'u', label: '', value: info.username, ac: 'username'}, ...pwFields], 'Save password', async v => {
      samePw(v); await K.api('/api/password-reset', {token: h.get('reset'), password: v.password}); done() }));
  }
  try {
    const me = await K.api('/api/me');
    K.me = me; K.setOnline(true);
    await K.idb.set('me', {...me, lease_until: Date.now() + me.offline_days * 864e5});
    await K.emit(); K.flushSoon(500);
    K.watchChanges();
    return me;
  } catch (e) {
    if (e.status === 401) {
      await K.wipe();
      return new Promise(() => K.form(cfg?.plant_name || 'Walkdown', cfg?.setup_needed ? 'No manager account exists yet: use the setup link printed on the server console.' : 'Sign in to see plant data.',
        [{name: 'username', label: 'Username', ac: 'username'}, {name: 'password', type: 'password', label: 'Password', ac: 'current-password'}], 'Sign in',
        async v => { await K.api('/api/login', v); location.reload() }));
    }
    const c = await K.idb.get('me');
    if (c && c.lease_until > Date.now()) { K.me = c; K.setOnline(false); await K.emit(); return c }
    if (K.reauth) {  // remote access sign-in expired and no usable offline copy: send them through the login
      K.box('Sign in again', 'Your remote-access sign-in has expired.', 'Continue', () => location.reload());
      return new Promise(() => {});
    }
    K.box('Offline', c ? `Offline access on this device expired (it lasts ${c.offline_days} days after the last sign-in check). Connect to the server to continue.`
                       : 'Cannot reach the server, and this device has no offline copy yet.', 'Retry', () => location.reload());
    return new Promise(() => {});
  }
};

// ---------- peer mode: this computer is one person's device; set it up before first use ----------
K.download = (data, name, type = 'application/json') => {
  if (K.native) return K.native.saveFile(name, type, data);   // Android: its own "save as" dialog
  // nosemgrep: web-10-dynamic-url-sink -- a download link to a blob: URL this function made; it saves, never navigates
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
  const h = K.h;
  const o = K.overlay(h('div', {class: 'box'}, h('h1', null, `Set up this ${dev}`),
    h('p', null, `This ${dev} keeps its own copy of the plant data and syncs with the other devices on the same Wi-Fi.`),
    cfg.node.removed ? h('div', {class: 'err', style: 'margin-bottom:10px'}, `This ${dev} was removed from ${cfg.node.removed.plant || 'the plant'} by ${cfg.node.removed.by || 'an admin'}. Its plant data has been deleted from it. To use it again, join again.`) : null,
    cfg.node.has_plant ? h('p', null, 'It already holds a plant\'s data but is not certified in it yet: import the bundle an admin gave you, or join through the server.') : null,
    h('button', {'data-a': 'qr'}, 'Join with a QR code from an admin'),
    h('button', {'data-a': 'nearby'}, 'Ask an admin on this Wi-Fi (no camera, no files)'),
    h('button', {'data-a': 'server'}, 'Join through the plant server'),
    h('button', {'data-a': 'request'}, 'Join through an admin (no server)'),
    h('button', {'data-a': 'bundle'}, 'Import a bundle an admin gave you'),
    cfg.node.has_plant || cfg.node.can_create === false ? null
      : h('button', {'data-a': 'new', style: 'background:none;border:1px solid var(--line,#3a5061);color:inherit'}, 'Start a new plant (you become its manager)'),
    h('input', {type: 'file', accept: '.kksbundle', hidden: true}), h('div', {class: 'err'}, note),
    h('p', {style: 'font-size:12px;opacity:.7'}, `Device ${(cfg.node.device || 'not created yet').slice(0, 12)}…`)));
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
    qr: () => { const cam = K.canScan();
      sub('Join with a QR code', `For when an admin is next to you on the same network: they open Manage → Devices → “Add a device with a QR code”. `
        + (K.native ? 'Fill in your details, then scan their screen.' : cam ? 'Fill in your details, then scan their screen with this computer\'s camera, or paste the code they copied for you.'
                    : `This ${dev} has no camera: ask the admin to copy the code under the QR code for you and paste it here, or go back and choose “Ask an admin on this Wi-Fi”.`),
      [{name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position (optional)', optional: true},
       {name: 'username', label: 'Username (if you have an account already, the same one)', ac: 'username'},
       ...(K.native ? [] : [{name: 'invite', label: cam ? 'Invite code (leave empty to use the camera)' : 'Invite code (starts with {"kks_invite"…)', optional: cam}])],
      K.native || cam ? 'Scan the QR code' : 'Join',
      async v => { if (!v.invite) { v.invite = await K.scanQr(); if (!v.invite) return }
        await K.api('/api/node/join-invite', v); K.joinWait(cfg) }) },
    nearby: () => sub('Ask an admin on this Wi-Fi', `An admin's phone or computer on the same Wi-Fi gets your request; when they accept, the plant data comes over the Wi-Fi by itself.`,
      [{name: 'full_name', label: 'Your full name', ac: 'name'}, {name: 'position', label: 'Position (optional)', optional: true},
       {name: 'username', label: 'Username (if you have an account already, the same one)', ac: 'username'}], 'Find admins on this Wi-Fi',
      async v => K.pickNearby(cfg, v)),
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
// Scanning an invite without the app: this computer's camera, read by BarcodeDetector where the browser has it, else
// our zxing-cpp build (kks-wasm.js, decision 0037). -> the text, or null if cancelled.
K.canScan = () => !!(K.native ? K.native.scanQr : navigator.mediaDevices?.getUserMedia);
if (!K.native) K.scanQr = async () => {
  let stream;
  try { stream = await navigator.mediaDevices.getUserMedia({video: {facingMode: 'environment'}}) }
  catch (e) { throw new Error(e.name === 'NotFoundError' ? 'No camera found on this computer. Paste the code instead, or choose “Ask an admin on this Wi-Fi”.'
                              : 'The camera could not be used: ' + (e.message || e.name)) }
  let detector = null, zx = null;
  try { if ('BarcodeDetector' in window && (await BarcodeDetector.getSupportedFormats()).includes('qr_code')) detector = new BarcodeDetector({formats: ['qr_code']}) } catch (e) {}
  if (!detector) zx = await import('/kks-wasm.js');
  const box = document.createElement('div');
  box.style.cssText = 'position:fixed;inset:0;z-index:300;background:#000d;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px;color:#fff;font:14px system-ui';
  box.innerHTML = '<video playsinline muted style="max-width:90vw;max-height:70vh;border-radius:8px"></video><div>Hold the admin\'s QR code in front of the camera</div><button type="button" style="padding:8px 16px">Cancel</button>';
  document.body.appendChild(box);
  const video = box.querySelector('video'), cv = document.createElement('canvas'), g = cv.getContext('2d', {willReadFrequently: true});
  video.srcObject = stream; await video.play();
  return new Promise(res => {
    let done = false;
    const finish = v => { if (done) return; done = true; stream.getTracks().forEach(t => t.stop()); box.remove(); res(v) };
    box.querySelector('button').onclick = () => finish(null);
    const tick = async () => {
      if (done) return;
      if (video.videoWidth) {
        let text = null;
        try {
          if (detector) text = (await detector.detect(video))[0]?.rawValue || null;
          else {
            cv.width = video.videoWidth; cv.height = video.videoHeight; g.drawImage(video, 0, 0);
            const px = g.getImageData(0, 0, cv.width, cv.height).data, lum = new Uint8Array(cv.width * cv.height);
            for (let i = 0, j = 0; j < lum.length; i += 4, j++) lum[j] = (px[i] * 77 + px[i + 1] * 150 + px[i + 2] * 29) >> 8;
            text = await zx.qrRead(lum, cv.width, cv.height);
          }
        } catch (e) { /* a frame that couldn't be read */ }
        if (text && text.includes('kks_invite')) return finish(text);
      }
      setTimeout(tick, 150);
    };
    tick();
  });
};
// Ask an admin on this Wi-Fi: pick one of the admins' devices found by mDNS (the list refreshes itself).
K.pickNearby = (cfg, who) => {
  const h = K.h;
  const o = K.overlay(h('div', {class: 'box'}, h('h1', null, 'Admins on this Wi-Fi'), h('p', null, 'Pick the device of the admin who is adding you.'),
    h('div', {class: 'list'}, h('p', {style: 'opacity:.7'}, 'Looking…')), h('div', {class: 'err'}), h('button', {type: 'button', class: 'back'}, '← Back')));
  let stop = false;
  o.querySelector('.back').onclick = () => { stop = true; history.back() };
  K.back = () => { stop = true; history.back(); return true };
  const tick = async () => {
    if (stop) return;
    let r; try { r = await K.api('/api/node/nearby') } catch (e) { r = {devices: [], discovery: e.message} }
    const list = o.querySelector('.list');
    list.replaceChildren(...(r.devices.length ? r.devices.map((d, i) => h('button', {type: 'button', 'data-i': i}, `${d.plant || 'a plant'} — ${d.label || d.host}`))
      : [h('p', {style: 'opacity:.7'}, `No admin's device found yet. The admin needs the app open on the same Wi-Fi (finding devices: ${r.discovery || '?'}).`)]));
    list.querySelectorAll('button').forEach(b => b.onclick = async () => {
      stop = true;
      try { await K.api('/api/node/join-invite', {...who, nearby: r.devices[+b.dataset.i]}); K.joinWait(cfg) }
      catch (e) { o.querySelector('.err').textContent = e.message; stop = false; tick() }
    });
    setTimeout(tick, 2000);
  };
  tick();
};
// Join by invite, after the request went out: wait for the admin to accept, then for the first sync.
K.joinWait = cfg => {
  const h = K.h;
  const o = K.overlay(h('div', {class: 'box'}, h('h1', null, `Joining ${cfg.plant_name || 'the plant'}`), h('p', {class: 'st'}, 'Connecting to the admin\'s device…'),
    h('p', {class: 'code', style: 'display:none'}), h('button', {type: 'button', class: 'ok', style: 'display:none'}, 'Yes, the admin\'s screen shows this code'),
    h('div', {class: 'err'}), h('button', {type: 'button', class: 'back'}, 'Cancel')));
  o.querySelector('.ok').onclick = async () => { o.querySelector('.ok').disabled = true; await K.api('/api/node/join-invite', {confirm: true}) };
  let stop = false;
  const cancel = async () => { stop = true; try { await K.api('/api/node/join-invite', {cancel: true}) } catch (e) {} K.joinScreen(cfg) };
  o.querySelector('.back').onclick = cancel; K.back = () => { cancel(); return true };
  const tick = async () => {
    if (stop) return;
    let st; try { st = await K.api('/api/node/join-invite') } catch (e) { st = {state: 'connecting', error: e.message} }
    if (st.state === 'joined') return location.reload();
    const msg = {connecting: 'Connecting to the admin\'s device…', waiting: 'Waiting for the admin to accept on their screen…',
                 confirm: 'The admin accepted. Check the code on their screen first:', syncing: 'Accepted. Getting the plant data…'}[st.state];
    if (st.code) { const c = o.querySelector('.code'); c.style.display = '';
      // as text: the code comes from the local API (#16)
      c.replaceChildren('Code: ', h('b', {style: 'font-size:22px;letter-spacing:3px'}, String(st.code).slice(0, 3) + ' ' + String(st.code).slice(3)),
        h('br'), h('span', {style: 'opacity:.7'}, 'The admin sees the same code next to your name. Only continue if it matches.'));
      o.querySelector('.ok').style.display = st.state === 'syncing' ? 'none' : '' }
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
  try { for (const k of await caches.keys()) if (!k.startsWith('kks-shell-')) await caches.delete(k) } catch (e) {}   // all but the app shell
  try { await K.idb.clear() } catch (e) {}
  // a peer (own laptop / the app) that lost its plant: the courses' copies of the progress go too (on a plant server
  // they are the only copy, so logging out keeps them)
  if (K.cfg?.mode === 'peer') try { localStorage.clear() } catch (e) {}
};
K.logout = async () => {
  if (K.outbox.length && !confirm(`${K.outbox.length} change(s) not sent yet. They stay on this device and are sent the next time you sign in here. Log out?`)) return;
  try { await K.api('/api/logout', {}) } catch (e) {}
  await K.wipe(); location.href = '/';
};

// ---------- submissions + outbox ----------
K.submit = async (kind, payload, note) => {
  const item = {client_id: K.uid(), kind, payload, ...(note ? {note} : {})};   // note: words for the approver
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
        const r = await K.api('/api/submit', {client_id: it.client_id, kind: it.kind, payload: it.payload, ...(it.note ? {note: it.note} : {})});
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

// Changes made elsewhere (another device's edits arriving by sync, an admin's decision) reach an open page by polling
// /api/sync/status: its `rev` moves with every stored change; the page then reloads its data (K.onChange('synced')).
// On a peer (own laptop / the app) the same answer feeds the status line: devices reachable, last sync, internet.
K.watchChanges = () => {
  if (K.watching) return; K.watching = true;
  const every = K.cfg?.mode === 'peer' ? 3000 : 15000;
  const tick = async () => {
    try {
      const st = await K.api('/api/sync/status');
      K.syncStatus = st;
      if (K.cfg?.mode !== 'peer') K.setOnline(true); else K.renderStatus();
      if (K.rev != null && st.rev !== K.rev) K.listeners.forEach(f => f('synced'));
      K.rev = st.rev;
      // a new plant data version became complete on this device (PROTOCOL-v2.md §19): pages load the drawings again
      const pa = st.plant_data ? st.plant_data.active : undefined;
      if (K.plantActive !== undefined && pa !== undefined && pa !== K.plantActive) K.listeners.forEach(f => f('plantdata'));
      if (pa !== undefined) K.plantActive = pa;
    } catch (e) { if (e.status === 401) return location.reload(); if (K.isNetErr(e)) K.setOnline(false) }
  };
  tick();
  setInterval(() => { if (!document.hidden) tick() }, every);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) tick() });
  addEventListener('online', tick); addEventListener('offline', () => K.renderStatus());
};
K.ago = t => { if (!t) return 'never'; const s = Math.max(0, Date.now() / 1000 - t); return s < 60 ? 'just now' : s < 3600 ? `${Math.round(s / 60)} min ago` : s < 86400 ? `${Math.round(s / 3600)} h ago` : `${Math.round(s / 86400)} d ago` };

K.renderStatus = () => {
  const el = document.getElementById('syncStatus'); if (!el) return;
  const n = K.outbox.length;
  if (K.cfg?.mode === 'peer') {   // no server here: what matters is which devices this one can sync with
    const st = K.syncStatus; if (!st) { el.textContent = ''; return }
    const r = st.reachable || 0, net = st.internet ?? (navigator.onLine ? null : false);
    el.replaceChildren(K.h('span', {style: `color:${r ? 'var(--ok)' : 'var(--review)'}`}, '●'),
      ` ${r ? `${r} device${r === 1 ? '' : 's'} reachable` : 'No devices reachable'}` + ` · synced ${K.ago(st.last_sync)}`
      + (net === true ? ' · Internet ✓' : net === false ? ' · No internet' : ''));
    el.title = `Devices of this plant found on this network or synced with in the last 3 minutes: ${r}. Your changes are kept on this device and go to the others when they are reachable.`
      + (net == null ? ' (Whether there is internet can\'t be told from here: the browser only knows it is on a network.)' : '');
    return;
  }
  if (K.reauth) {  // a top-level load of the page lets Cloudflare Access show its login, then comes back here
    const a = K.h('a', {style: 'color:var(--accent)'}, 'Sign in again'); a.href = K.safeUrl(location.pathname);
    el.replaceChildren(K.h('span', {style: 'color:var(--review)'}, '●'), ' ', a, n ? ` · ${n} queued` : '');
    el.title = 'Your remote-access sign-in expired. Working from the copy on this device; changes are queued.';
    return;
  }
  el.replaceChildren(K.h('span', {style: `color:${K.online ? 'var(--ok)' : 'var(--review)'}`}, '●'), ` ${K.online ? 'Online' : 'Offline'}${n ? ` · ${n} queued` : ''}`);
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

if ('serviceWorker' in navigator && !K.native) {
  navigator.serviceWorker.register('/sw.js').catch(e => console.warn('service worker not registered', e));
  // Before 2026-10-06 a stored photo could be served as a script (finding #25), and so registered as a service worker
  // under /photos/ (a script there can only take a scope under /photos/). Only /sw.js, for the whole site, belongs
  // here: any other registration goes. (Right after register() ours can have no worker yet: Firefox.)
  navigator.serviceWorker.getRegistrations().then(rs => rs.forEach(r => {
    const w = r.active || r.waiting || r.installing;
    if (new URL(r.scope).pathname !== '/' || (w && new URL(w.scriptURL).pathname !== '/sw.js')) r.unregister();
  })).catch(() => {});
}

// ---------- JPEG XL photos ----------
// Photos are stored as JXL. A browser that shows JXL itself gets the file as it is; any other decodes it here with
// our own libjxl build in WebAssembly (kks-wasm.js, decision 0037, loaded only then) into a BMP: plain pixels, no lossy
// re-encoding. (The Android app answers /photos/*.jxl with a BMP from its own libjxl instead.)
K.jxl = {
  probe: null, dec: null, done: new Map(),   // photo URL -> Promise of a blob: URL
  native() {
    return this.probe ??= new Promise(res => {
      const i = new Image(); i.onload = () => res(i.width === 1); i.onerror = () => res(false);
      i.src = 'data:image/jxl;base64,/woAEBAJCAABACgASxiLFcJJQU5/AA==';   // 1×1 px
    });
  },
  bmp(d) {   // ImageData -> 24-bit BMP blob (rows bottom-up, BGR, padded to 4 bytes)
    const w = d.width, h = d.height, row = (w * 3 + 3) & ~3, size = 54 + row * h;
    const buf = new Uint8Array(size), v = new DataView(buf.buffer);
    buf[0] = 66; buf[1] = 77; v.setUint32(2, size, true); v.setUint32(10, 54, true); v.setUint32(14, 40, true);
    v.setInt32(18, w, true); v.setInt32(22, h, true); v.setUint16(26, 1, true); v.setUint16(28, 24, true);
    v.setUint32(34, row * h, true);
    const px = d.data;
    for (let y = 0; y < h; y++) {
      let o = 54 + (h - 1 - y) * row, s = y * w * 4;
      for (let x = 0; x < w; x++, s += 4) { buf[o++] = px[s + 2]; buf[o++] = px[s + 1]; buf[o++] = px[s] }
    }
    return new Blob([buf], {type: 'image/bmp'});
  },
  url(src) {
    if (!this.done.has(src)) this.done.set(src, (async () => {
      this.dec ??= import('/kks-wasm.js');
      const [{jxlDecode}, r] = await Promise.all([this.dec, fetch(src, {credentials: 'same-origin'})]);
      if (!r.ok) throw new Error('photo ' + r.status);
      const d = await jxlDecode(new Uint8Array(await r.arrayBuffer()));
      return URL.createObjectURL(this.bmp({width: d.width, height: d.height, data: d.rgba}));
    })());
    return this.done.get(src);
  },
  async fix(img) {
    const src = img.getAttribute('src') || '';
    if (!/\.jxl(\?|$)/.test(src) || img.dataset.jxl === src) return;
    img.dataset.jxl = src;
    if (await this.native()) { img.style.visibility = 'visible'; return }
    // nosemgrep: web-10-dynamic-url-sink -- an <img> source (a blob: URL of the decoded photo) can't run script
    try { const u = await this.url(src); if (img.dataset.jxl === src) { img.src = u; img.dataset.jxl = u; img.style.visibility = 'visible' } }
    catch (e) { console.warn('JXL photo not shown', src, e); img.style.visibility = 'visible'; img.alt = 'photo could not be shown' }
  },
  watch() {
    if (K.native) return;
    const s = document.createElement('style');   // no broken-image flash while a JXL photo is decoded
    s.textContent = 'img[src$=".jxl"]{visibility:hidden}'; document.head.appendChild(s);
    const scan = n => { if (n.tagName === 'IMG') this.fix(n); else n.querySelectorAll?.('img[src$=".jxl"]').forEach(i => this.fix(i)) };
    new MutationObserver(ms => ms.forEach(m => m.type === 'attributes' ? scan(m.target) : m.addedNodes.forEach(scan)))
      .observe(document.documentElement, {subtree: true, childList: true, attributes: true, attributeFilter: ['src']});
    scan(document.documentElement);
  },
};
K.jxl.watch();

// A photo from this browser becomes JPEG XL here, before it is sent (decision 0018: no JPEG anywhere): our libjxl
// build in a worker, so the page stays responsive. canvas → a data: URL of the JXL codestream.
K.jxlEncode = (canvas, distance = 1.9, effort = 7) => new Promise((res, rej) => {
  const d = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height);
  K.jxlWorker ??= new Worker('/kks-wasm-worker.js', {type: 'module'});
  const id = (K.jxlSeq = (K.jxlSeq || 0) + 1);
  const on = e => {
    if (e.data.id !== id) return;
    K.jxlWorker.removeEventListener('message', on);
    if (e.data.error) return rej(new Error(e.data.error));
    const b = e.data.jxl; let s = '';
    for (let i = 0; i < b.length; i += 0x8000) s += String.fromCharCode.apply(null, b.subarray(i, i + 0x8000));
    res('data:image/jxl;base64,' + btoa(s));
  };
  K.jxlWorker.addEventListener('message', on);
  K.jxlWorker.postMessage({id, rgba: d.data.buffer, width: d.width, height: d.height, distance, effort}, [d.data.buffer]);
});


// ---------- photo viewer: pinch / wheel to zoom, drag to pan, double tap to zoom in or back ----------
K.lightbox = src => {
  let box = document.getElementById('kzoom');
  if (!box) {
    box = document.createElement('div'); box.id = 'kzoom';
    box.style.cssText = 'position:fixed;inset:0;z-index:150;background:rgba(0,0,0,.92);display:none;overflow:hidden;touch-action:none';
    box.innerHTML = '<img alt="" draggable="false" style="position:absolute;left:0;top:0;transform-origin:0 0;user-select:none;max-width:none">'
      + '<button type="button" aria-label="Close" style="position:absolute;top:calc(10px + env(safe-area-inset-top,0px));right:12px;width:40px;height:40px;border-radius:20px;border:0;background:#000a;color:#fff;font-size:22px;cursor:pointer">×</button>';
    document.body.appendChild(box);
    const img = box.querySelector('img'), z = K.lightbox.z = {s: 1, x: 0, y: 0, min: 1};
    const apply = () => { img.style.transform = `translate(${z.x}px,${z.y}px) scale(${z.s})` };
    const clamp = () => {   // keep the photo on screen; centred while it is smaller than the screen
      const W = box.clientWidth, H = box.clientHeight, w = img.naturalWidth * z.s, h = img.naturalHeight * z.s;
      z.x = w <= W ? (W - w) / 2 : Math.min(0, Math.max(W - w, z.x));
      z.y = h <= H ? (H - h) / 2 : Math.min(0, Math.max(H - h, z.y));
    };
    const zoomAt = (f, cx, cy) => { const s2 = Math.min(Math.max(z.s * f, z.min), z.min * 8); z.x = cx - (cx - z.x) * s2 / z.s; z.y = cy - (cy - z.y) * s2 / z.s; z.s = s2; clamp(); apply() };
    K.lightbox.fit = () => { const W = box.clientWidth, H = box.clientHeight; z.min = z.s = Math.min(W / img.naturalWidth, H / img.naturalHeight, 1) * 0.96; z.x = z.y = 0; clamp(); apply() };
    img.onload = () => K.lightbox.fit();
    const close = () => { box.style.display = 'none'; img.removeAttribute('src') };
    K.lightbox.close = close;
    box.querySelector('button').onclick = close;
    box.addEventListener('wheel', e => { e.preventDefault(); zoomAt(Math.exp(-e.deltaY * 0.0015), e.clientX, e.clientY) }, {passive: false});
    const pts = new Map(); let moved = false, last = null, lastTap = 0;
    box.addEventListener('pointerdown', e => { if (e.target.tagName === 'BUTTON') return; box.setPointerCapture(e.pointerId); pts.set(e.pointerId, {x: e.clientX, y: e.clientY}); moved = false; last = null });
    box.addEventListener('pointermove', e => {
      if (!pts.has(e.pointerId)) return;
      const p = pts.get(e.pointerId), dx = e.clientX - p.x, dy = e.clientY - p.y;
      if (Math.abs(dx) + Math.abs(dy) > 3) moved = true;
      if (pts.size === 2) {   // pinch: scale by the change of distance, around the midpoint
        const [a, b] = [...pts.values()], d0 = Math.hypot(a.x - b.x, a.y - b.y);
        pts.set(e.pointerId, {x: e.clientX, y: e.clientY});
        const [c, d] = [...pts.values()], d1 = Math.hypot(c.x - d.x, c.y - d.y);
        if (d0 > 0) zoomAt(d1 / d0, (c.x + d.x) / 2, (c.y + d.y) / 2);
        return;
      }
      pts.set(e.pointerId, {x: e.clientX, y: e.clientY}); z.x += dx; z.y += dy; clamp(); apply();
    });
    const up = e => {
      if (!pts.delete(e.pointerId) || pts.size || moved) return;
      const now = Date.now();
      if (now - lastTap < 300) { lastTap = 0; if (z.s > z.min * 1.1) K.lightbox.fit(); else zoomAt(2.5, e.clientX, e.clientY); return }
      lastTap = now;
      if (e.target === box) setTimeout(() => { if (lastTap === now) close() }, 300);   // a single tap beside the photo closes
    };
    box.addEventListener('pointerup', up); box.addEventListener('pointercancel', e => pts.delete(e.pointerId));
    addEventListener('keydown', e => { if (e.key === 'Escape' && box.style.display !== 'none') close() });
    addEventListener('resize', () => { if (box.style.display !== 'none') K.lightbox.fit() });
  }
  box.style.display = 'block';
  // nosemgrep: web-10-dynamic-url-sink -- an <img> source can't run script
  const img = box.querySelector('img'); img.src = src;
  if (img.complete && img.naturalWidth) K.lightbox.fit();
};
K.lightbox.isOpen = () => document.getElementById('kzoom')?.style.display === 'block';

// ---------- marking a photo before it is sent: arrow, rectangle, circle ----------
// -> Promise of {canvas, note} with the marks drawn in, or null if cancelled. askNote: offer "note for the approver".
// The photo editor (R6): arrow, box or circle, four colours, three line sizes, undo; zoom (buttons, wheel, two-finger
// pinch and pan) and, while a finger draws, a loupe: the area under the finger magnified, above it (touch only).
K.annotate = (src, askNote) => new Promise(done => {
  const box = document.createElement('div');
  box.style.cssText = 'position:fixed;inset:0;z-index:160;background:#0b1116;display:flex;flex-direction:column;color:#e9eef2;font:14px system-ui,sans-serif;padding-top:env(safe-area-inset-top,0px)';
  const h = K.h, b = (t, a, extra = '', label = '') => h('button', {type: 'button', 'data-a': a, 'aria-label': label || null,
    style: 'padding:8px 12px;border-radius:6px;border:1px solid #3a5061;background:#1c2730;color:inherit;cursor:pointer;' + extra}, t);
  box.append(h('div', {style: 'display:flex;gap:6px;flex-wrap:wrap;padding:8px;align-items:center'}, b('↗ Arrow', 'arrow'), b('▭ Box', 'rect'), b('◯ Circle', 'circle'),
      h('span', {style: 'display:inline-flex;gap:4px'}, ['#ff3b30', '#ffcc00', '#34c759', '#ffffff'].map(c => h('button', {type: 'button', 'data-c': c, 'aria-label': 'Colour',
        style: `width:30px;height:30px;border-radius:15px;border:2px solid #3a5061;background:${c};cursor:pointer`}))),
      h('span', {style: 'display:inline-flex;gap:4px', role: 'group', 'aria-label': 'Line size'}, [['S', 0.6, 'Thin lines'], ['M', 1, 'Medium lines'], ['L', 1.8, 'Thick lines']].map(([t, f, l]) =>
        h('button', {type: 'button', 'data-s': f, 'aria-label': l, style: 'width:34px;padding:6px 0;border-radius:6px;border:1px solid #3a5061;background:#1c2730;color:inherit;cursor:pointer'}, t))),
      h('span', {style: 'display:inline-flex;gap:4px'}, b('−', 'zout', '', 'Zoom out'), b('+', 'zin', '', 'Zoom in'), b('Fit', 'zfit', '', 'Fit the photo')),
      h('span', {style: 'opacity:.7;font-size:12.5px'}, 'Drag on the photo to point at what matters (optional) · two fingers zoom and move')),
    h('div', {class: 'vp', style: 'flex:1;min-height:0;position:relative;overflow:hidden;touch-action:none'},
      h('canvas', {class: 'view', style: 'position:absolute;inset:0;width:100%;height:100%;touch-action:none'}),
      h('canvas', {class: 'loupe', width: 180, height: 180, style: 'position:absolute;display:none;width:180px;height:180px;border-radius:90px;border:3px solid #ff7a1a;box-shadow:0 4px 16px #000a;pointer-events:none'})),
    h('div', {style: 'display:flex;gap:8px;padding:8px;padding-bottom:calc(8px + env(safe-area-inset-bottom,0px));align-items:center;flex-wrap:wrap'},
      askNote ? h('input', {class: 'note', maxlength: 500, placeholder: 'Note for the approver (optional)', style: 'flex:1;min-width:180px;padding:8px;border-radius:6px;border:1px solid #3a5061;background:#1c2730;color:inherit'})
              : h('span', {style: 'flex:1'}),
      b('Undo', 'undo'), b('Cancel', 'cancel'), b('Use photo', 'ok', 'background:#ff7a1a;color:#1c2730;border:0;font-weight:650')));
  document.body.appendChild(box);
  const vp = box.querySelector('.vp'), cv = box.querySelector('canvas.view'), g = cv.getContext('2d'), base = new Image();
  const lp = box.querySelector('canvas.loupe'), lg = lp.getContext('2d');
  let tool = 'arrow', color = '#ff3b30', size = 1, shapes = [], draft = null;
  let zoom = 1, cx = 0, cy = 0, fit = 1;           // the image point at the view's centre; view px per image px = fit · zoom
  const W0 = () => Math.max(3, Math.round(Math.max(base.naturalWidth, base.naturalHeight) * 0.006));
  const draw = (ctx, sh) => {
    const w = W0() * (sh.s || 1);
    ctx.lineWidth = w; ctx.strokeStyle = ctx.fillStyle = sh.c; ctx.lineCap = ctx.lineJoin = 'round';
    ctx.shadowColor = 'rgba(0,0,0,.6)'; ctx.shadowBlur = w;
    const [x0, y0, x1, y1] = sh.p;
    ctx.beginPath();
    if (sh.t === 'rect') ctx.strokeRect(Math.min(x0, x1), Math.min(y0, y1), Math.abs(x1 - x0), Math.abs(y1 - y0));
    else if (sh.t === 'circle') { ctx.ellipse((x0 + x1) / 2, (y0 + y1) / 2, Math.abs(x1 - x0) / 2, Math.abs(y1 - y0) / 2, 0, 0, 2 * Math.PI); ctx.stroke() }
    else {
      const a = Math.atan2(y1 - y0, x1 - x0), h = w * 4.5;
      ctx.moveTo(x0, y0); ctx.lineTo(x1 - Math.cos(a) * h * 0.6, y1 - Math.sin(a) * h * 0.6); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x1 - h * Math.cos(a - 0.45), y1 - h * Math.sin(a - 0.45));
      ctx.lineTo(x1 - h * Math.cos(a + 0.45), y1 - h * Math.sin(a + 0.45)); ctx.closePath(); ctx.fill();
    }
    ctx.shadowBlur = 0;
  };
  const scene = ctx => { ctx.drawImage(base, 0, 0); shapes.concat(draft ? [draft] : []).forEach(sh => draw(ctx, sh)) };
  const clampView = () => {
    const s = fit * zoom, hw = cv.width / 2 / s, hh = cv.height / 2 / s, iw = base.naturalWidth, ih = base.naturalHeight;
    cx = hw * 2 >= iw ? iw / 2 : Math.min(Math.max(cx, hw), iw - hw);
    cy = hh * 2 >= ih ? ih / 2 : Math.min(Math.max(cy, hh), ih - hh);
  };
  const paint = () => {
    const r = vp.getBoundingClientRect(), dpr = window.devicePixelRatio || 1;
    if (cv.width !== Math.round(r.width * dpr) || cv.height !== Math.round(r.height * dpr)) { cv.width = Math.round(r.width * dpr); cv.height = Math.round(r.height * dpr) }
    fit = Math.min(cv.width / base.naturalWidth, cv.height / base.naturalHeight); clampView();
    const s = fit * zoom;
    g.setTransform(1, 0, 0, 1, 0, 0); g.fillStyle = '#000'; g.fillRect(0, 0, cv.width, cv.height);
    g.setTransform(s, 0, 0, s, cv.width / 2 - cx * s, cv.height / 2 - cy * s); scene(g);
  };
  // view px (CSS) → image px
  const toImg = (px, py) => { const dpr = window.devicePixelRatio || 1, s = fit * zoom; return [cx + (px * dpr - cv.width / 2) / s, cy + (py * dpr - cv.height / 2) / s] };
  const zoomAt = (px, py, z) => { const [ix, iy] = toImg(px, py), dpr = window.devicePixelRatio || 1; zoom = Math.min(8, Math.max(1, z));
    const s = fit * zoom; cx = ix - (px * dpr - cv.width / 2) / s; cy = iy - (py * dpr - cv.height / 2) / s; paint() };
  const loupe = (px, py) => {                     // the area under the finger, 2.5× the view, above the finger
    const L = 180, k = 2.5, dpr = window.devicePixelRatio || 1, s = fit * zoom * k / dpr, [ix, iy] = toImg(px, py);
    lg.setTransform(1, 0, 0, 1, 0, 0); lg.fillStyle = '#000'; lg.fillRect(0, 0, L, L);
    lg.setTransform(s, 0, 0, s, L / 2 - ix * s, L / 2 - iy * s); scene(lg);
    lg.setTransform(1, 0, 0, 1, 0, 0); lg.strokeStyle = '#ff7a1a'; lg.lineWidth = 1.5;
    lg.beginPath(); lg.moveTo(L / 2 - 10, L / 2); lg.lineTo(L / 2 + 10, L / 2); lg.moveTo(L / 2, L / 2 - 10); lg.lineTo(L / 2, L / 2 + 10); lg.stroke();
    const r = vp.getBoundingClientRect(), above = py - 40 - L >= 0;
    lp.style.left = Math.min(Math.max(px - L / 2, 0), r.width - L) + 'px'; lp.style.top = (above ? py - 40 - L : py + 40) + 'px'; lp.style.display = 'block';
  };
  const pick = () => box.querySelectorAll('[data-a]').forEach(x => x.style.borderColor = x.dataset.a === tool ? '#ff7a1a' : '#3a5061');
  const pickC = () => box.querySelectorAll('[data-c]').forEach(x => x.style.borderColor = x.dataset.c === color ? '#ff7a1a' : '#3a5061');
  const pickS = () => box.querySelectorAll('[data-s]').forEach(x => { x.style.borderColor = +x.dataset.s === size ? '#ff7a1a' : '#3a5061'; x.setAttribute('aria-pressed', String(+x.dataset.s === size)) });
  base.onload = () => { cx = base.naturalWidth / 2; cy = base.naturalHeight / 2; paint(); pick(); pickC(); pickS() };
  base.src = src;
  const ro = new ResizeObserver(() => { if (base.naturalWidth) paint() }); ro.observe(vp);
  const at = e => { const r = cv.getBoundingClientRect(); return [e.clientX - r.left, e.clientY - r.top] };
  // repaint at most once a frame: redrawing the whole photo on every move is slow on phones, and then moves pile up
  let queued = false;
  const later = f => { if (!queued) { queued = true; requestAnimationFrame(() => { queued = false; paint(); f && f() }) } };
  const pts = new Map();     // touch points down: one draws, two zoom and pan
  let pinch = null;
  cv.addEventListener('pointerdown', e => {
    try { cv.setPointerCapture(e.pointerId) } catch (_) {}   // (a pointer the browser no longer knows: draw anyway)
    pts.set(e.pointerId, at(e));
    if (pts.size === 2) {   // a second finger: no drawing, zoom and pan instead
      draft = null; lp.style.display = 'none';
      const [a, c] = [...pts.values()]; pinch = {d: Math.hypot(a[0] - c[0], a[1] - c[1]), z: zoom, m: [(a[0] + c[0]) / 2, (a[1] + c[1]) / 2]}; paint(); return;
    }
    if (pts.size > 2 || e.button === 2 || e.button === 1) return;
    const [x, y] = toImg(...at(e)); draft = {t: tool, c: color, s: size, p: [x, y, x, y], touch: e.pointerType === 'touch'};
    if (draft.touch) loupe(...at(e));
  });
  cv.addEventListener('pointermove', e => {
    if (!pts.has(e.pointerId)) return;
    const q = at(e), prev = pts.get(e.pointerId); pts.set(e.pointerId, q);
    if (pinch && pts.size === 2) {
      const [a, c] = [...pts.values()], m = [(a[0] + c[0]) / 2, (a[1] + c[1]) / 2], dpr = window.devicePixelRatio || 1;
      zoom = Math.min(8, Math.max(1, pinch.z * Math.hypot(a[0] - c[0], a[1] - c[1]) / pinch.d));
      const s = fit * zoom; cx -= (m[0] - pinch.m[0]) * dpr / s; cy -= (m[1] - pinch.m[1]) * dpr / s; pinch.m = m; later(); return;
    }
    if ((e.buttons & 6) && !draft) { const dpr = window.devicePixelRatio || 1, s = fit * zoom; cx -= (q[0] - prev[0]) * dpr / s; cy -= (q[1] - prev[1]) * dpr / s; later(); return }   // right or middle button: pan
    if (!draft) return;
    const [x, y] = toImg(...q); draft.p[2] = x; draft.p[3] = y; later(draft.touch ? () => loupe(...q) : null);
  });
  const up = e => {          // (the end is where the finger left, even if moves were skipped)
    pts.delete(e.pointerId);
    if (pts.size < 2) pinch = null;
    lp.style.display = 'none';
    if (!draft) return;
    const [x, y] = toImg(...at(e)); draft.p[2] = x; draft.p[3] = y;
    if (Math.hypot(draft.p[2] - draft.p[0], draft.p[3] - draft.p[1]) > W0() * 2) shapes.push(draft);
    draft = null; paint();
  };
  cv.addEventListener('pointerup', up);
  cv.addEventListener('pointercancel', e => { pts.delete(e.pointerId); if (pts.size < 2) pinch = null; draft = null; lp.style.display = 'none'; paint() });
  cv.addEventListener('contextmenu', e => e.preventDefault());
  cv.addEventListener('wheel', e => { e.preventDefault(); zoomAt(...at(e), zoom * Math.exp(-e.deltaY / 400)) }, {passive: false});
  const finish = v => { ro.disconnect(); box.remove(); done(v) };
  box.querySelectorAll('[data-c]').forEach(x => x.onclick = () => { color = x.dataset.c; pickC() });
  box.querySelectorAll('[data-s]').forEach(x => x.onclick = () => { size = +x.dataset.s; pickS() });
  box.querySelectorAll('[data-a]').forEach(x => x.onclick = () => {
    const a = x.dataset.a, r = vp.getBoundingClientRect();
    if (a === 'undo') { shapes.pop(); paint() }
    else if (a === 'zin') zoomAt(r.width / 2, r.height / 2, zoom * 1.5);
    else if (a === 'zout') zoomAt(r.width / 2, r.height / 2, zoom / 1.5);
    else if (a === 'zfit') { zoom = 1; paint() }
    else if (a === 'cancel') finish(null);
    else if (a === 'ok') {   // the photo at its own size with the marks burned in
      const out = document.createElement('canvas'); out.width = base.naturalWidth; out.height = base.naturalHeight;
      scene(out.getContext('2d')); finish({canvas: out, note: box.querySelector('.note')?.value.trim() || ''});
    }
    else { tool = a; pick() }
  });
});

// ---------- a progress bar for work the device does without reporting progress (JPEG XL encoding) ----------
// The encoder gives no progress callback: the bar follows the time the last photos took per megapixel on this
// device (estimate), stops at 95 % until the work is done, then fills.
K.progress = (title, estimateMs) => {
  const box = document.createElement('div');
  box.style.cssText = 'position:fixed;left:50%;bottom:calc(24px + env(safe-area-inset-bottom,0px));transform:translateX(-50%);z-index:170;background:#243440;color:#e9eef2;border:1px solid #3a5061;border-radius:10px;padding:12px 14px;min-width:260px;max-width:90vw;font:14px system-ui,sans-serif;box-shadow:0 6px 24px #0008';
  const h = K.h, bar = h('i', {style: 'display:block;height:100%;width:0;background:#ff7a1a;transition:width .3s'}), t = h('div', {class: 't', style: 'font-size:12.5px;opacity:.75'});
  box.append(h('div', null, title), h('div', {style: 'height:6px;border-radius:3px;background:#3a5061;margin:8px 0 4px;overflow:hidden'}, bar), t);
  document.body.appendChild(box);
  const t0 = Date.now();
  const tick = () => {
    const el = Date.now() - t0, f = Math.min(0.95, el / Math.max(estimateMs, 500));
    bar.style.width = (f * 100).toFixed(0) + '%';
    const left = Math.max(0, (estimateMs - el) / 1000);
    t.textContent = `${Math.round(f * 100)} %` + (left > 1 ? ` · about ${Math.ceil(left)} s left` : el > estimateMs ? ' · almost done' : '');
  };
  tick(); const iv = setInterval(tick, 250);
  return {done() { clearInterval(iv); bar.style.width = '100%'; t.textContent = '100 %'; setTimeout(() => box.remove(), 500) }};
};

// Ask a question with an optional note ("Delete this photo?"). -> Promise of {note} or null.
K.ask = (title, text, askNote, okLabel = 'OK') => new Promise(done => {
  const o = document.createElement('div');
  o.style.cssText = 'position:fixed;inset:0;z-index:180;background:#000a;display:flex;align-items:center;justify-content:center;padding:16px;font:14px system-ui,sans-serif';
  const h = K.h, note = askNote ? h('input', {class: 'note', maxlength: 500, placeholder: 'Note for the approver (optional)',
    style: 'width:100%;padding:8px;border-radius:6px;border:1px solid #3a5061;background:#1c2730;color:inherit;margin-bottom:10px'}) : null;
  const answer = ok => () => { const v = ok ? {note: note?.value.trim() || ''} : null; o.remove(); done(v) };
  o.append(h('div', {style: 'background:#243440;color:#e9eef2;border:1px solid #3a5061;border-radius:10px;padding:16px;max-width:420px;width:100%'},
    h('div', {style: 'font-weight:650;margin-bottom:6px'}, title), text ? h('div', {style: 'opacity:.8;margin-bottom:8px'}, text) : null, note,
    h('div', {style: 'display:flex;gap:8px;justify-content:flex-end'},
      h('button', {type: 'button', 'data-v': '0', style: 'padding:8px 12px;border-radius:6px;border:1px solid #3a5061;background:none;color:inherit;cursor:pointer', onclick: answer(false)}, 'Cancel'),
      h('button', {type: 'button', 'data-v': '1', style: 'padding:8px 12px;border-radius:6px;border:0;background:#ff7a1a;color:#1c2730;font-weight:650;cursor:pointer', onclick: answer(true)}, okLabel))));
  document.body.appendChild(o);
  note?.focus();
});
