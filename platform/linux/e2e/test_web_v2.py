"""The browser client on v2 plant data (decision 0034), in all three engines: the Nim server with the synthetic sample
sheet (importer/tests/vectors/kkp-sample.pdf), index.html's overview pyramid (JPEG XL: native or libjxl in
WebAssembly) and the sharp layer from tiles.js (the path store drawn in a Worker).
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_v2.py [unittest arguments]
$KKS_SERVER and $KKS_IMPORTER name the builds (default /tmp/kkslinux, /tmp/kksimp); screenshots go to $KKS_SHOTS
(default /tmp/kks-web-shots)."""
import json, os, re, shutil, subprocess, sys, tempfile, time, unittest, urllib.request, http.cookiejar
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
IMPORTER = os.environ.get('KKS_IMPORTER', '/tmp/kksimp/kks_import')
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-web-shots')


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p



# A Content-Security-Policy violation becomes a page error (#8): the tests that collect page errors then fail on any
# script, worker, picture or style the policy blocks.
CSP_WATCH = """document.addEventListener('securitypolicyviolation', e => {
  throw new Error('CSP violation: ' + e.violatedDirective + ' blocked ' + (e.blockedURI || 'inline')) })"""

class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None, raw=None, ctype='application/json'):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        r = urllib.request.Request(self.base + p, data=data, method=m,
                                   headers=({'Content-Type': ctype} if data is not None else {}) | {'Origin': self.base})
        with self.op.open(r) as resp: return json.loads(resp.read())


class WebV2(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-v2-')
        cls.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m: setup = m[1]
            if 'server on' in line: break
        cls.base = 'http://127.0.0.1:%d' % cls.port
        boss = Client(cls.base)
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                               'full_name': 'The Manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        assert boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360],
                        'kks': '11LAB70AA501', 'isa': '', 'note': ''}}).get('status') == 'approved'
        os.makedirs(SHOTS, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1200, 'height': 800})
            ctx.add_init_script(CSP_WATCH)
            r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                                 headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(self.base + '/')
            # the overview: a pyramid level is shown (decoded natively or by K.jxl), hotspots are drawn
            page.wait_for_function("() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }",
                                   timeout=30000)
            page.wait_for_selector('#layer [data-id], #layer .hot, #layer > *', timeout=15000)
            # tags coloured by their photos: the tag has none yet (red); the button says it is pressed
            page.click('#zcover')
            self.assertEqual(page.get_attribute('#zcover', 'aria-pressed'), 'true')
            self.assertTrue(page.is_visible('#coverlegend'))
            self.assertGreater(page.locator('#layer .hs.p-none').count(), 0)
            self.assertIn('no photos', page.get_attribute('#layer .hs.p-none >> nth=0', 'title'))
            page.click('#zcover')
            # zoom in: the sharp layer comes from the worker
            page.evaluate("() => zoomAt(8)")
            page.wait_for_function("() => { const c = document.getElementById('sharp'); return c && c.style.display === 'block' }",
                                   timeout=30000)
            dark = page.evaluate("""() => { const c = document.getElementById('sharp'), x = c.getContext('2d');
                const d = x.getImageData(0, 0, c.width, c.height).data; let n = 0;
                for (let i = 0; i < d.length; i += 16) if (d[i] < 100 && d[i + 1] < 100 && d[i + 2] < 100) n++;
                return n }""")
            page.screenshot(path=os.path.join(SHOTS, name + '.png'))
            # keyboard and screen reader: the search is a combobox with a listbox; Enter opens the panel and moves
            # focus to its heading
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)
            box = page.get_by_role('combobox', name='Search equipment by KKS code or description')
            box.focus()
            page.keyboard.type('LAB70AA501')
            page.wait_for_selector('#results [role=option]')
            self.assertEqual(box.get_attribute('aria-expanded'), 'true')
            self.assertEqual(box.get_attribute('aria-activedescendant'), 'res-0')
            page.keyboard.press('Enter')
            page.wait_for_function("() => document.activeElement && document.activeElement.getAttribute('role') === 'heading'", timeout=15000)
            self.assertIn('11LAB70AA501', page.evaluate("document.activeElement.textContent"))
            self.assertEqual(page.get_by_role('button', name='Close the panel').count(), 1)
            # a course's KKS link: /?kks=CODE opens that equipment
            page.goto(self.base + '/?kks=11LAB70AA501')
            page.wait_for_function("() => typeof selTag !== 'undefined' && selTag && full(selTag) === '11LAB70AA501'", timeout=30000)
            # the photo editor: a touch draw shows the loupe and hides it when lifted; a mouse draw never shows it; line
            # sizes; zoom; the result is the photo at its own size with the marks burned in
            page.evaluate("""() => { const c = document.createElement('canvas'); c.width = 800; c.height = 600;
                const x = c.getContext('2d'); x.fillStyle = '#808080'; x.fillRect(0, 0, 800, 600);
                window.__ann = K.annotate(c.toDataURL('image/png'), false).then(r => window.__res = r) }""")
            page.wait_for_selector('canvas.view')
            page.wait_for_timeout(300)
            box = page.locator('canvas.view').bounding_box()
            cxp, cyp = box['x'] + box['width'] / 2, box['y'] + box['height'] / 2
            def ptr(kind, typ, x, y, pid):
                page.dispatch_event('canvas.view', kind, {'pointerId': pid, 'pointerType': typ, 'clientX': x, 'clientY': y,
                                                          'button': 0, 'buttons': 1 if kind != 'pointerup' else 0, 'isPrimary': True, 'bubbles': True})
            page.click('[data-s="1.8"]')
            self.assertEqual(page.get_attribute('[data-s="1.8"]', 'aria-pressed'), 'true')
            ptr('pointerdown', 'touch', cxp - 100, cyp, 7)
            ptr('pointermove', 'touch', cxp + 100, cyp, 7)
            page.wait_for_timeout(150)
            self.assertTrue(page.is_visible('canvas.loupe'), name + ': no loupe while a finger draws')
            ptr('pointerup', 'touch', cxp + 100, cyp, 7)
            self.assertFalse(page.is_visible('canvas.loupe'), name + ': the loupe stayed after the finger left')
            page.click('[aria-label="Zoom in"]')
            ptr('pointerdown', 'mouse', cxp - 50, cyp + 60, 1)
            ptr('pointermove', 'mouse', cxp + 50, cyp + 60, 1)
            page.wait_for_timeout(150)
            self.assertFalse(page.is_visible('canvas.loupe'), name + ': a loupe for the mouse')
            ptr('pointerup', 'mouse', cxp + 50, cyp + 60, 1)
            page.click('[data-a="ok"]')
            page.wait_for_function('() => window.__res')
            w, red = page.evaluate("""() => { const c = window.__res.canvas, x = c.getContext('2d');
                const d = x.getImageData(0, 0, c.width, c.height).data; let n = 0;
                for (let i = 0; i < d.length; i += 4) if (d[i] > 200 && d[i + 1] < 120 && d[i + 2] < 120) n++;
                return [c.width, n] }""")
            self.assertEqual(w, 800)
            self.assertGreater(red, 500, name + ': the marks were not burned in')
            # the plant's name next to Walkdown; the manager clears it in the admin page: then no name and no "·"
            self.assertEqual(page.text_content('#plantName'), '· Test plant')
            page.goto(self.base + '/admin.html#devices')
            field = page.get_by_role('textbox', name='Plant name')
            self.assertEqual(field.input_value(), 'Test plant')
            field.fill('')
            field.press('Enter')
            page.wait_for_function("() => document.title === 'Walkdown'", timeout=15000)
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)
            self.assertEqual(page.text_content('#plantName'), '')
            self.assertEqual(page.title(), 'Walkdown')
            ctx.request.post(self.base + '/api/settings/plant', data={'name': 'Test plant'}, headers={'Origin': self.base})
            browser.close()
            self.assertGreater(dark, 100, name + ': the sharp layer drew nothing dark')
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
