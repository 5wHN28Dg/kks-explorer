// Service worker: makes the app installable and usable offline.
// - App shell (public): network-first, cached copy when offline.
// - Plant data (/data, /photos, /api/state; needs login): cached as it's fetched. The page deletes the 'kks-data'
//   cache on logout or when the server rejects the session. Error responses (401 etc.) are never cached.
// Service workers only run over HTTPS or on localhost.
const SHELL = 'kks-shell-v6', DATA = 'kks-data';
const SHELL_FILES = ['/', '/index.html', '/admin.html', '/common.js', '/qrcodegen.js', '/course-bridge.js', '/learning.html', '/vendor/fonts/courses.css', '/vendor/jxl/decode.js', '/vendor/jxl/utils.js', '/vendor/jxl/codec/dec/jxl_dec.js', '/vendor/jxl/codec/dec/jxl_dec.wasm', '/vendor/jsqr/jsQR.js', '/manifest.webmanifest', '/icon.svg', '/icon-192.png', '/icon-512.png'];

self.addEventListener('install', e => { e.waitUntil(caches.open(SHELL).then(c => c.addAll(SHELL_FILES))); self.skipWaiting() });
self.addEventListener('activate', e => e.waitUntil(caches.keys()
  .then(ks => Promise.all(ks.filter(k => k.startsWith('kks-shell-') && k !== SHELL).map(k => caches.delete(k))))
  .then(() => self.clients.claim())));

self.addEventListener('fetch', e => {
  const u = new URL(e.request.url), p = u.pathname;
  if (e.request.method !== 'GET' || u.origin !== location.origin) return;
  if (p === '/api/config') return e.respondWith(networkFirst(e.request, SHELL));
  if (p.startsWith('/data/courses/')) return e.respondWith(networkFirst(e.request, DATA));   // courses change with the app
  if (p.startsWith('/vendor/')) return e.respondWith(networkFirst(e.request, SHELL));        // fonts, decoders (public)
  if (p === '/api/state' || (p.startsWith('/data/') && p.endsWith('.json'))) return e.respondWith(networkFirst(e.request, DATA));
  if (p.startsWith('/data/') || p.startsWith('/photos/')) return e.respondWith(cacheFirst(e.request, DATA));  // images: big, rarely change
  if (SHELL_FILES.includes(p)) return e.respondWith(networkFirst(e.request, SHELL));
});

async function networkFirst(req, name) {
  try {
    const r = await fetch(req);
    if (r.ok) (await caches.open(name)).put(req, r.clone());
    return r;
  } catch (err) {
    const c = await caches.match(req);
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
  const c = await caches.match(req);
  if (c) return c;
  const r = await fetch(req);
  if (r.ok) (await caches.open(name)).put(req, r.clone());
  return r;
}
