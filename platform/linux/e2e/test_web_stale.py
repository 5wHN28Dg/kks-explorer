"""What a browser kept from before the stored-content fix (finding #25, advisory GHSA-f86j-phv6-36c6) goes, in all three
engines: the service worker's old data cache, any service worker other than /sw.js (a stored photo could once be
served as a script and registered as one), and the HTTP cache (bypassed by the service worker for photos and plant
data, and cleared on logout with Clear-Site-Data: "cache").
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_stale.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server). `Upgrade` also needs a server from before the fix,
$KKS_OLD_SERVER, built from commit af8bb3c (`git worktree add --detach D af8bb3c`, then `nim c -d:release` in
D/platform/linux); it serves that commit's own web files, taken with `git archive`."""
import base64, json, os, re, shutil, subprocess, tempfile, time, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')


def until(page, js, timeout=20):
    """poll an async expression with evaluate, which awaits it (wait_for_function would take its Promise as true)"""
    t0 = time.time()
    while time.time() - t0 < timeout:
        if page.evaluate(js): return
        time.sleep(0.2)
    raise AssertionError('timed out waiting for ' + js)


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


class Stale(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-stale-')
        cls.port = free_port()
        # the web folder with one more script under /vendor/, standing in for a planted service worker
        web = os.path.join(cls.dir, 'web')
        os.makedirs(os.path.join(web, 'vendor'))
        for e in os.listdir(REPO):
            if e != 'vendor': os.symlink(os.path.join(REPO, e), os.path.join(web, e))
        for e in os.listdir(os.path.join(REPO, 'vendor')):
            os.symlink(os.path.join(REPO, 'vendor', e), os.path.join(web, 'vendor', e))
        with open(os.path.join(web, 'vendor', 'planted-sw.js'), 'w') as f:
            f.write("self.addEventListener('fetch', e => e.respondWith(new Response('<script>1</script>', "
                    "{headers: {'Content-Type': 'text/html'}})));\n")
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'web_dir': web,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        cls.setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m: cls.setup = m[1]
            if 'server on' in line: break
        cls.base = 'http://127.0.0.1:%d' % cls.port

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = p[name].launch()
            ctx = browser.new_context()
            page = ctx.new_page()
            page.goto(self.base + '/learning.html')
            sw = page.evaluate("'serviceWorker' in navigator")
            if sw:
                page.evaluate("navigator.serviceWorker.ready")
                # what a browser could hold from before the fix: the old data cache with a page in it, and a second
                # service worker
                page.evaluate("""async () => {
                    const c = await caches.open('kks-data');
                    await c.put('/photos/x.html', new Response('<script>1</script>', {headers: {'Content-Type': 'text/html'}}));
                    const other = await caches.open('evil');   // a cache under any other name a script could have made
                    await other.put('/photos/y.html', new Response('<script>1</script>', {headers: {'Content-Type': 'text/html'}}));
                    await navigator.serviceWorker.register('/vendor/planted-sw.js', {scope: '/vendor/'});
                }""")
                scripts = page.evaluate("async () => (await navigator.serviceWorker.getRegistrations())"
                                        ".map(r => (r.active || r.waiting || r.installing)?.scriptURL)")
                self.assertTrue(any(u and u.endswith('/vendor/planted-sw.js') for u in scripts), scripts)
                self.assertIn('kks-data', page.evaluate("caches.keys()"))
                page.reload()
                until(page, """async () => {
                    const rs = await navigator.serviceWorker.getRegistrations();
                    return rs.every(r => { const w = r.active || r.waiting || r.installing;
                                           return !w || new URL(w.scriptURL).pathname === '/sw.js' });
                }""")
                until(page, "async () => (await caches.keys()).every(k => k === 'kks-shell-v10' || k === 'kks-data-v2')")
            browser.close()
            return sw

    def test_chromium(self): self.assertTrue(self.run_engine('chromium'))
    def test_firefox(self): self.assertTrue(self.run_engine('firefox'))
    def test_webkit(self): print('webkit service worker:', self.run_engine('webkit'))

    def test_logout_clears_the_http_cache(self):
        with sync_playwright() as p:
            ctx = p.request.new_context(base_url=self.base, extra_http_headers={'Origin': self.base})
            r = ctx.post('/api/setup', data={'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                             'full_name': 'The Manager'})
            self.assertTrue(r.ok, r.text())
            r = ctx.post('/api/logout', data={})
            self.assertTrue(r.ok)
            self.assertEqual(r.headers.get('clear-site-data'), '"cache"')
            ctx.dispose()


OLD = 'af8bb3c'   # adopt-policy before the fix
POLY = b'\xff\x0a<html><script>window.pwned=1</script></html>'   # JPEG XL's signature, then a page


class Upgrade(unittest.TestCase):
    """A browser attacked before the fix: it opened /photos/<sha>.html while the old server served it as a page,
    cached as immutable for a year, and the old service worker kept a copy. After the upgrade, on the same origin,
    that URL no longer runs anything."""

    def start(self, binary, web):
        cfg = {'address': '127.0.0.1', 'port': self.port, 'sync_port': 0, 'web_dir': web,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'),
               'plant_dir': os.path.join(self.dir, 'plant-data'), 'backup_dir': os.path.join(self.dir, 'backups')}
        with open(os.path.join(self.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        proc = subprocess.Popen([binary, 'serve', '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = proc.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m: setup = m[1]
            if 'server on' in line: break
        time.sleep(0.3)
        return proc, setup

    def engine(self, name):
        old = os.environ.get('KKS_OLD_SERVER')
        if not old: self.skipTest('set KKS_OLD_SERVER (see the module docstring)')
        self.dir = tempfile.mkdtemp(prefix='kks-web-upgrade-')
        self.port = free_port()
        base = 'http://127.0.0.1:%d' % self.port
        oldweb = os.path.join(self.dir, 'oldweb')
        os.makedirs(oldweb)
        tar = subprocess.run(['git', '-C', REPO, 'archive', OLD], capture_output=True, check=True).stdout
        subprocess.run(['tar', '-x', '-C', oldweb], input=tar, check=True)
        proc, setup = self.start(old, oldweb)
        try:
            with sync_playwright() as p:
                browser = p[name].launch()
                ctx = browser.new_context()
                r = ctx.request.post(base + '/api/setup', headers={'Origin': base}, data={
                    'token': setup, 'username': 'boss', 'password': 'a long password', 'full_name': 'The Manager'})
                self.assertTrue(r.ok, r.text())
                r = ctx.request.post(base + '/api/submit', headers={'Origin': base}, data={'kind': 'photo', 'payload': {
                    'kks': '11LAB70AA501', 'caption': 'x', 'floor': '1', 'dataUrl': 'data:image/jxl;base64,' + base64.b64encode(POLY).decode()}})
                self.assertTrue(r.ok, r.text())
                sha = ctx.request.get(base + '/api/state').json()['photos'][0]['file'].split('.')[0]
                page = ctx.new_page()
                page.goto(base + '/learning.html')                     # the old pages and service worker
                page.evaluate("navigator.serviceWorker.ready")
                page.reload()                                          # now controlled by the old worker
                page.goto(base + '/photos/%s.html' % sha)
                self.assertEqual(page.evaluate("window.pwned"), 1)    # the attack, before the fix
                page.goto(base + '/learning.html')     # what such a script could leave: a page in a cache of its own
                page.evaluate("""async () => {
                    const c = await caches.open('evil');
                    await c.put('/photos/z.html', new Response('<script>window.pwned=2</script>', {headers: {'Content-Type': 'text/html'}}));
                }""")
                proc.terminate(); proc.wait(5)
                proc, _ = self.start(SERVER, REPO)                     # the upgrade, same origin and store
                page.goto(base + '/learning.html')
                until(page, "async () => !(await caches.keys()).includes('kks-data')")
                try:
                    resp = page.goto(base + '/photos/%s.html' % sha)
                    self.assertEqual(resp.headers.get('content-type'), 'image/jxl')   # WebKit shows it as an image
                except Exception as e:
                    if 'Download is starting' not in str(e): raise         # a browser without JPEG XL saves it
                self.assertIsNone(page.evaluate("window.pwned"))
                try:
                    page.goto(base + '/photos/z.html')
                except Exception as e:
                    if 'Download is starting' not in str(e): raise
                self.assertIsNone(page.evaluate("window.pwned"))
                browser.close()
        finally:
            proc.terminate(); proc.wait(5)
            shutil.rmtree(self.dir, ignore_errors=True)

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
