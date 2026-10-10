// Service worker: makes the app installable and usable offline.
// - App shell (public): network-first, cached copy when offline.
// - Plant data (/data, /photos, /api/state; needs login): cached as it's fetched. The page deletes the 'kks-data'
//   caches on logout or when the server rejects the session. Error responses (401 etc.) are never cached.
// - "Download for offline" (common.js K.offline) stores everything at once through the `keep` message below, instead of
//   file by file as pages happen to ask.
// Service workers only run over HTTPS or on localhost.
const SHELL = 'kks-shell-v13', DATA = 'kks-data-v2';   // v2: nothing cached before the fix of finding #25
const SHELL_FILES = ['/', '/index.html', '/index.js', '/admin.html', '/admin.js', '/common.js', '/tiles.js', '/dark.js', '/systems.js', '/course-bridge.js', '/learning.html', '/learning.js', '/course.html', '/course.js', '/course-figure.js', '/course.css', '/kks-wasm.js', '/kks-wasm-worker.js', '/vendor/fonts/courses.css', '/vendor/kks/kks-simd-dec.js', '/vendor/kks/kks-simd-dec.wasm', '/manifest.webmanifest', '/icon.svg', '/icon-192.png', '/icon-512.png', '/apple-touch-icon.png'];

self.addEventListener('install', e => { e.waitUntil(caches.open(SHELL).then(c => c.addAll(SHELL_FILES))); self.skipWaiting() });
// Activation keeps only this version's two caches: any other (an older version's, or one a script made before the
// stored-content fix) goes, and lookups below read only the cache they name.
self.addEventListener('activate', e => e.waitUntil(caches.keys()
  .then(ks => Promise.all(ks.filter(k => k !== SHELL && k !== DATA).map(k => caches.delete(k))))
  .then(() => self.clients.claim())));

// Where a URL's saved copy lives and how it is used: [cache, 'net' (network first) or 'kept' (the copy first)], or null
// for what is never saved. One rule for the pages' own requests and for "Download for offline" (the `keep` message).
function route(u) {
  const p = u.pathname;
  if (u.origin !== location.origin) return null;
  if (p === '/api/config') return [SHELL, 'net'];
  if (p.startsWith('/data/courses/')) return [DATA, 'net'];   // courses change with the app
  if (p.startsWith('/vendor/')) return [SHELL, 'net'];        // fonts, decoders (public)
  if (p === '/api/state' || p === '/api/courses' || (p.startsWith('/data/') && p.endsWith('.json'))) return [DATA, 'net'];
  if (p.startsWith('/data/') || p.startsWith('/photos/')) return [DATA, 'kept'];  // images, drawings: big, rarely change
  if (SHELL_FILES.includes(p)) return [SHELL, 'net'];
  return null;
}
self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const r = route(new URL(e.request.url));
  if (r) e.respondWith(r[1] === 'net' ? networkFirst(e.request, r[0]) : cacheFirst(e.request, r[0]));
});

// "Download for offline" (common.js K.offline): the page names each file, this worker fetches and stores it and says
// how it went, so a file counts as saved only once it is in the cache (a full disk is an answer, not a silence).
//   {t: 'keep', url, fresh}  -> {ok: true, bytes, had} or {ok: false, error, quota, status}
//       fresh: fetch it even if a copy is here. had: the copy was here already (nothing fetched).
//   {t: 'prune', keep: [urls]} -> {ok: true, removed}: drawings and photos saved here that are no longer on the list
//       (an older plant data version, a deleted photo) go.
//   {t: 'hello'} -> {ok: true, shell: SHELL}
self.addEventListener('message', e => {
  const m = e.data || {}, port = e.ports && e.ports[0];
  if (!port || !e.source || new URL(e.source.url).origin !== location.origin) return;
  const work = m.t === 'keep' ? keep(m) : m.t === 'prune' ? prune(m) : m.t === 'hello' ? Promise.resolve({ok: true, shell: SHELL}) : null;
  if (work) e.waitUntil(work.catch(err => ({ok: false, error: String(err && err.message || err), quota: isQuota(err)})).then(r => port.postMessage(r)));
});
const isQuota = err => !!err && (err.name === 'QuotaExceededError' || /quota/i.test(String(err.message || '')));
const sizeOf = async r => { const n = Number(r.headers.get('Content-Length')); return n > 0 ? n : (await r.clone().arrayBuffer()).byteLength };
async function keep(m) {
  const u = new URL(m.url, location.origin), r = route(u);
  if (!r) return {ok: false, error: 'not a file this app keeps'};
  const cache = await caches.open(r[0]);
  if (!m.fresh) { const c = await cache.match(u.href); if (c) return {ok: true, had: true, bytes: await sizeOf(c)} }
  const resp = await fetch(u.href, {credentials: 'same-origin', cache: 'no-cache'});
  if (!resp.ok) return {ok: false, status: resp.status, error: 'the server answered ' + resp.status};
  const bytes = await sizeOf(resp);
  await cache.put(u.href, resp);            // (awaited: the answer is "saved", or the error that stopped it)
  return {ok: true, bytes};
}
async function prune(m) {
  const want = new Set((m.keep || []).map(x => new URL(x, location.origin).href)), cache = await caches.open(DATA);
  let removed = 0;
  for (const req of await cache.keys()) {
    const p = new URL(req.url).pathname;
    if ((p.startsWith('/data/sheets/') || p.startsWith('/photos/')) && !want.has(req.url)) { await cache.delete(req); removed++ }
  }
  return {ok: true, removed};
}

async function networkFirst(req, name) {
  try {
    const r = await fetch(req);
    if (r.ok) (await caches.open(name)).put(req, r.clone());
    return r;
  } catch (err) {
    // (a page is saved under its path: /?kks=…, /course.html?c=… and /?sheet=… are the same file)
    const c = await (await caches.open(name)).match(req, {ignoreSearch: name === SHELL});
    // a plant data list that is not saved: "not there", as the server says of one the plant never published
    // (procedures, descriptions and the location list are optional, and the pages know what a 404 means)
    if (!c && /^\/data\/[^/]+\.json$/.test(new URL(req.url).pathname))
      return new Response('{"error":"not saved on this device"}', {status: 404, headers: {'Content-Type': 'application/json', 'X-KKS-From-Cache': 'offline'}});
    if (!c) throw err;
    // Serve the saved copy, marked so the page doesn't mistake it for fresh data: 'offline' when the server can't be
    // reached, 'reauth' when Cloudflare Access redirected us to its login (its session expired).
    const h = new Headers(c.headers);
    h.set('X-KKS-From-Cache', await accessExpired() ? 'reauth' : 'offline');
    return new Response(c.body, {status: c.status, statusText: c.statusText, headers: h});
  }
}
async function accessExpired() {
  try { return (await fetch('/api/config', {redirect: 'manual', cache: 'no-store'})).type === 'opaqueredirect' }
  catch (e) { return false }
}
async function cacheFirst(req, name) {
  const c = await (await caches.open(name)).match(req);
  if (c) return c;
  // past the HTTP cache: it may hold a photo from before the fix of finding #25, served with the URL's type and
  // cached as immutable for a year
  let r;
  try { r = await fetch(req, {cache: 'no-cache'}) }   // (a non-empty init makes a navigation's mode same-origin)
  catch (err) {
    // offline, and the page asks under another ?v= than the copy has (it could not learn the plant data version):
    // the copy saved for offline is the one to show ("Download for offline" keeps only the current version's files)
    const any = await (await caches.open(name)).match(req, {ignoreSearch: true});
    if (any) return any;
    throw err;
  }
  if (r.ok) (await caches.open(name)).put(req, r.clone());
  return r;
}
