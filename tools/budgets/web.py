"""WEB-15: the web client's bundle sizes and lab metrics (budgets.json "web").
  python3 tools/budgets/web.py bundles OUT.json
  python3 tools/budgets/web.py lab SERVER IMPORTER OUT.json        (Playwright's Chromium; tools/budgets/requirements.txt)

Bundles: the bytes of the files each glob in budgets.json names, as the server sends them. kks_server sends static
files uncompressed (server.nim staticFile), so "none" counts the files themselves; "gzip" (level 9) is supported for a
server that compresses. KB = 1024 bytes.

Lab: the pages a person opens first, served by the Nim server with the measurement plant (plant.py), signed in as the
manager, each run in a fresh browser context (cold cache, no service worker yet):
- the viewer `/` (index.html): ready when the sheet's overview image is decoded and shown;
- a course page with an animated figure, `/course.html?c=fnd#cycle`: ready when the module's heading is shown.
Profile (budgets.json web.lab.profile): Chromium with Playwright's "Pixel 7" device (412x839, DPR 2.625, touch, mobile
viewport), CPU slowed 4x and the network shaped through the DevTools protocol (Emulation.setCPUThrottlingRate,
Network.emulateNetworkConditions).
Metrics, from the browser's own PerformanceObserver entries:
- LCP: the last largest-contentful-paint entry;
- CLS: the largest session window of layout-shift entries without recent input (gap 1 s, window at most 5 s);
- TBT: sum of (duration - 50 ms) over longtask entries that start after first-contentful-paint;
observed until 10 s after the page is ready. Each run's value is the larger of the two pages; the median over the
runs budgets.json states is compared."""
import glob, gzip, json, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import budgetlib  # noqa: E402

# the profile's numbers (budgets.json web.lab.profile says the same in words)
CPU_SLOWDOWN = 4
RTT_MS = 40
DOWN_BPS = 10_000_000 / 8      # bytes per second
UP_BPS = 5_000_000 / 8
DEVICE = 'Pixel 7'
OBSERVE_S = 10

OBSERVER = r"""
(() => {
  const m = window.__kksLab = {lcp: 0, fcp: 0, shifts: [], tasks: []};
  new PerformanceObserver(l => { for (const e of l.getEntries()) m.lcp = e.renderTime || e.loadTime || e.startTime; })
    .observe({type: 'largest-contentful-paint', buffered: true});
  new PerformanceObserver(l => { for (const e of l.getEntries()) if (!e.hadRecentInput) m.shifts.push([e.startTime, e.value]); })
    .observe({type: 'layout-shift', buffered: true});
  new PerformanceObserver(l => { for (const e of l.getEntries()) m.tasks.push([e.startTime, e.duration]); })
    .observe({type: 'longtask', buffered: true});
  new PerformanceObserver(l => { for (const e of l.getEntries()) if (e.name === 'first-contentful-paint') m.fcp = e.startTime; })
    .observe({type: 'paint', buffered: true});
})();
"""

PAGES = [
    ('viewer', '/', "() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }"),
    ('course', '/course.html?c=fnd#cycle', "() => !!document.querySelector('#main h1')"),
]


def cls_of(shifts):
    best = cur = 0.0
    start = last = None
    for t, v in sorted(shifts):
        if start is None or t - last > 1000 or t - start > 5000:
            start, cur = t, 0.0
        cur += v
        last = t
        best = max(best, cur)
    return best


def bundles(out):
    metrics = {}
    for b in budgetlib.budgets()['web']['bundles']:
        files = sorted(glob.glob(os.path.join(budgetlib.REPO, b['files'])))
        if not files:
            raise SystemExit(f'bundle {b["name"]}: no file matches {b["files"]}')
        n = 0
        for f in files:
            data = open(f, 'rb').read()
            n += len(gzip.compress(data, 9, mtime=0)) if b['compression'] == 'gzip' else len(data)
            if b['compression'] not in ('gzip', 'none'):
                raise SystemExit(f'bundle {b["name"]}: compression {b["compression"]} is not measured here')
        metrics[f'web.bundles[{b["name"]}]'] = ([round(n / 1024, 1)], 'KB')
        print(b['name'], [os.path.relpath(f, budgetlib.REPO) for f in files], flush=True)
    budgetlib.write(out, metrics)


def measure(browser, pw, base, path, ready):
    ctx = browser.new_context(**pw.devices[DEVICE])
    try:
        r = ctx.request.post(base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                             headers={'Origin': base})
        assert r.ok, r.text()
        page = ctx.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        cdp = ctx.new_cdp_session(page)
        cdp.send('Network.enable')
        cdp.send('Network.emulateNetworkConditions', {'offline': False, 'latency': RTT_MS,
                                                      'downloadThroughput': DOWN_BPS, 'uploadThroughput': UP_BPS})
        cdp.send('Emulation.setCPUThrottlingRate', {'rate': CPU_SLOWDOWN})
        page.add_init_script(OBSERVER)
        page.goto(base + path, wait_until='load', timeout=120000)
        page.wait_for_function(ready, timeout=120000)
        page.wait_for_timeout(OBSERVE_S * 1000)
        m = page.evaluate('window.__kksLab')
        if errors:
            raise SystemExit(f'{path}: page errors {errors}')
        if not m['lcp']:
            raise SystemExit(f'{path}: no largest-contentful-paint entry')
        tbt = sum(max(0.0, d - 50) for t, d in m['tasks'] if t >= m['fcp'])
        return {'lcpMs': m['lcp'], 'cls': cls_of(m['shifts']), 'tbtMs': tbt}
    finally:
        ctx.close()


def lab(server, importer, out):
    import plant
    from playwright.sync_api import sync_playwright
    runs = budgetlib.runs_for('lab')
    p = plant.Plant(server, importer).start()
    vals = {'lcpMs': [], 'cls': [], 'tbtMs': []}
    per_page = []
    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch()
            for n in range(1, runs + 1):
                got = {name: measure(browser, pw, p.base, path, ready) for name, path, ready in PAGES}
                per_page.append(got)
                for k in vals:
                    vals[k].append(round(max(g[k] for g in got.values()), 4 if k == 'cls' else 0))
                print(f'run {n}: ' + '; '.join(f'{name} LCP {g["lcpMs"]:.0f} ms, CLS {g["cls"]:.3f}, TBT {g["tbtMs"]:.0f} ms'
                                              for name, g in got.items()), flush=True)
            version = browser.version
            browser.close()
    finally:
        p.stop()
    budgetlib.write(out, {'web.lab.lcpMs': (vals['lcpMs'], 'ms'), 'web.lab.cls': (vals['cls'], ''),
                          'web.lab.tbtMs': (vals['tbtMs'], 'ms')}, per_page=per_page, chromium=version,
                    where='CI ' + os.environ.get('ImageOS', 'local'))


if __name__ == '__main__':
    if sys.argv[1] == 'bundles':
        bundles(sys.argv[2])
    elif sys.argv[1] == 'lab':
        lab(*sys.argv[2:5])
    else:
        sys.exit(__doc__)
