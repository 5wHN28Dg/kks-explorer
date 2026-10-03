// Course progress bridge (M4, https://github.com/5wHN28Dg/kks-explorer/wiki/Architecture-v1 §8). tools/build_courses.py puts this before each course's own
// script, with data-course = the course's localStorage prefix (course.html: ?c=<id>) ("ppt" → keys "ppt.solved", "ppt.last", …).
// - Before the course reads its progress: fill its localStorage keys from this device's log (private entries only
//   this person's own devices can read; server/progress.py, LocalApi). Synchronously, since the course reads them as
//   soon as its script starts.
// - Every write the course makes to those keys is saved to the log a moment later (and kept in a pending list until
//   that worked, e.g. across a reload).
// On a plant server (a browser, no app) there is no log for this: progress then stays in this browser only.
(() => {
  // the v1 HTML courses name themselves (data-course); course.html (the JSON courses) carries the id as ?c=
  const course = document.currentScript.dataset.course || new URLSearchParams(location.search).get('c') || '';
  if (!/^[a-z_][a-z0-9_]{0,31}$/.test(course)) return;
  const P = course + '.', PENDING = '__kks_pending.' + course;
  const native = window.KKSNative && window.KKSNative.progress ? window.KKSNative : null;
  const setItem = Storage.prototype.setItem;

  // the same merge as server/progress.py: objects → union, "…Best" numbers → the larger, else the newer value
  const merge = (key, old, now) => {
    if (old == null) return now;
    try {
      const a = JSON.parse(old), b = JSON.parse(now);
      if (a && b && typeof a === 'object' && typeof b === 'object' && !Array.isArray(a) && !Array.isArray(b)) return JSON.stringify({...a, ...b});
      if (key.endsWith('Best') && typeof a === 'number' && typeof b === 'number') return a > b ? old : now;
    } catch (e) {}
    return now;
  };

  let saved = null;
  try {
    if (native) saved = JSON.parse(native.progress(course));
    else {
      const x = new XMLHttpRequest();
      x.open('GET', '/api/progress?course=' + encodeURIComponent(course), false);
      x.send();
      if (x.status === 200) saved = JSON.parse(x.responseText).data;
    }
  } catch (e) { saved = null }
  if (!saved) return;   // no log here (plant server) or not reachable: plain localStorage, as the course was made

  let pending = {};
  try { pending = JSON.parse(localStorage.getItem(PENDING) || '{}') } catch (e) {}
  for (const [k, v] of Object.entries(saved)) {
    const mine = pending[k];
    setItem.call(localStorage, P + k, mine == null ? v : merge(k, v, mine));
    if (mine != null) pending[k] = merge(k, v, mine);
  }

  const send = data => {
    try {
      if (native) return Promise.resolve(native.progressSave(course, JSON.stringify(data)) < 400);
      return fetch('/api/progress', {method: 'POST', credentials: 'same-origin', keepalive: true,
        headers: {'Content-Type': 'application/json'}, body: JSON.stringify({course, data})}).then(r => r.ok, () => false);
    } catch (e) { return Promise.resolve(false) }
  };
  let timer = null;
  const flush = () => {
    clearTimeout(timer); timer = null;
    const data = {...pending};
    if (!Object.keys(data).length) return;
    send(data).then(ok => {
      if (!ok) return;
      for (const k in data) if (pending[k] === data[k]) delete pending[k];
      setItem.call(localStorage, PENDING, JSON.stringify(pending));
    });
  };
  Storage.prototype.setItem = function (k, v) {
    setItem.call(this, k, v);
    if (this === localStorage && typeof k === 'string' && k.startsWith(P)) {
      pending[k.slice(P.length)] = String(v);
      setItem.call(this, PENDING, JSON.stringify(pending));
      clearTimeout(timer); timer = setTimeout(flush, 1500);
    }
  };
  addEventListener('pagehide', flush);
  if (Object.keys(pending).length) timer = setTimeout(flush, 500);
})();
