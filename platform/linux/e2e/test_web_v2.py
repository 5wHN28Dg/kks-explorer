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

class PageErrors(list):
    """The page's own errors (Playwright's pageerror). A navigation cancels the requests the page left in flight (the
    sync poll, cacheSheets' fetches), and WebKit logs each one it cancels as the console error "Fetch API cannot load
    URL due to access control checks.", which Playwright passes on as a page error (test_dark_webkit failed on one,
    run 37895485771). Exactly that report, and only from the start of a navigation the test makes (leave(), before
    reload, goto and close) until the new document commits, is the old document's teardown and isn't kept."""
    def __init__(self, page):
        super().__init__()
        self.leaving = False
        page.on('pageerror', self.add)
        page.on('framenavigated', lambda f: f.parent_frame is None and self.arrived())

    def leave(self): self.leaving = True
    def arrived(self): self.leaving = False

    def add(self, e):
        if self.leaving and (e.name or '').startswith('Fetch API cannot load ') and e.message.endswith(' due to access control checks.'):
            return
        self.append(str(e))


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
                                               'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
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
            errors = PageErrors(page)
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
            errors.leave()
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
            errors.leave()
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
            # a finger that lifts before the next frame: the loupe that frame was to draw stays hidden (it came back
            # after the finger left, and then showed over the next mouse draw: a WebKit flake on CI)
            page.evaluate("""() => new Promise(ok => { const c = document.querySelector('canvas.view'), r = c.getBoundingClientRect();
                const ev = (k, x) => c.dispatchEvent(new PointerEvent(k, {pointerId: 9, pointerType: 'touch', clientX: r.left + x,
                    clientY: r.top + r.height / 2, button: 0, buttons: k === 'pointerup' ? 0 : 1, isPrimary: true, bubbles: true}));
                ev('pointerdown', r.width / 2 - 80); ev('pointermove', r.width / 2 + 80); ev('pointerup', r.width / 2 + 80);
                requestAnimationFrame(() => requestAnimationFrame(ok)) })""")
            self.assertFalse(page.is_visible('canvas.loupe'), name + ': the loupe came back after a quick finger draw')
            page.click('[data-a="undo"]')
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
            errors.leave()
            page.goto(self.base + '/admin.html#devices')
            field = page.get_by_role('textbox', name='Plant name')
            self.assertEqual(field.input_value(), 'Test plant')
            field.fill('')
            field.press('Enter')
            page.wait_for_function("() => document.title === 'Walkdown'", timeout=15000)
            errors.leave()
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)
            self.assertEqual(page.text_content('#plantName'), '')
            self.assertEqual(page.title(), 'Walkdown')
            ctx.request.post(self.base + '/api/settings/plant', data={'name': 'Test plant'}, headers={'Origin': self.base})
            errors.leave()
            browser.close()
            self.assertGreater(dark, 100, name + ': the sharp layer drew nothing dark')
            self.assertEqual(errors, [], name)

    def run_dark(self, name):
        """dark drawings: the toggle turns the sharp layer and the overview dark (lines light), is remembered across a
        reload, and turning it off restores the light drawing"""
        stats = """(sel) => { const e = document.querySelector(sel); let c = e;
            if (e.tagName === 'IMG') { c = document.createElement('canvas'); c.width = e.naturalWidth; c.height = e.naturalHeight;
              c.getContext('2d').drawImage(e, 0, 0) }
            const d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data, n = new Map(); let light = 0, dark = 0;
            for (let i = 0; i < d.length; i += 4) { const k = d[i] + ',' + d[i + 1] + ',' + d[i + 2]; n.set(k, (n.get(k) || 0) + 1);
              if (d[i] > 180 && d[i + 1] > 180 && d[i + 2] > 180) light++; if (d[i] < 60 && d[i + 1] < 60 && d[i + 2] < 60) dark++ }
            return {bg: [...n].sort((a, b) => b[1] - a[1])[0][0], light, dark, src: e.currentSrc || e.src || ''} }"""
        sharp_on = "() => { const c = document.getElementById('sharp'); return c && c.style.display === 'block' }"
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1200, 'height': 800})
            r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                                 headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.new_page()
            errors = PageErrors(page)
            page.goto(self.base + '/')
            loaded = "() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }"
            page.wait_for_function(loaded, timeout=30000)
            button = page.get_by_role('button', name='Dark drawings')
            self.assertEqual(button.get_attribute('aria-pressed'), 'false')
            light_img = page.evaluate(stats, '#sheetimg')
            self.assertEqual(light_img['bg'], '255,255,255', name)
            # on: the overview becomes a transformed level (a blob: URL from the worker), the sharp layer redraws dark
            button.click()
            self.assertEqual(button.get_attribute('aria-pressed'), 'true')
            page.wait_for_function("(was) => document.getElementById('sheetimg').src !== was", arg=light_img['src'], timeout=30000)
            page.wait_for_function(loaded, timeout=30000)
            img = page.evaluate(stats, '#sheetimg')
            self.assertEqual(img['bg'], '18,18,18', name + ': the overview paper is not #121212')
            self.assertGreater(img['light'], 50, name + ': no light lines on the dark overview')
            page.evaluate("() => zoomAt(8)")
            page.wait_for_function(sharp_on, timeout=30000)
            page.wait_for_timeout(500)
            on = page.evaluate(stats, '#sharp')
            self.assertEqual(on['bg'], '18,18,18', name + ': the sharp layer\'s background is not #121212')
            self.assertGreater(on['light'], 100, name + ': no light lines on the dark sharp layer')
            ms = page.evaluate("() => dark.lastMs")
            print(f'{name}: dark overview transform {ms:.1f} ms', flush=True)
            # the dark tag colours: a coverage outline is the lightened red
            page.click('#zcover')
            self.assertEqual(page.evaluate("() => getComputedStyle(document.querySelector('#layer .hs.p-none')).outlineColor"),
                             'rgb(232, 115, 115)')
            page.click('#zcover')
            page.screenshot(path=os.path.join(SHOTS, name + '-dark.png'))
            # remembered: after a reload the drawing opens dark
            errors.leave()
            page.reload()
            page.wait_for_function("() => document.getElementById('sheetimg').src.startsWith('blob:')", timeout=30000)
            page.wait_for_function(loaded, timeout=30000)
            self.assertEqual(page.get_by_role('button', name='Dark drawings').get_attribute('aria-pressed'), 'true')
            self.assertEqual(page.evaluate(stats, '#sheetimg')['bg'], '18,18,18', name + ': not dark after a reload')
            # off: the light drawing again, at once
            page.evaluate("() => zoomAt(8)")
            page.wait_for_function(sharp_on, timeout=30000)
            page.wait_for_timeout(500)
            self.assertEqual(page.evaluate(stats, '#sharp')['bg'], '18,18,18', name)
            page.get_by_role('button', name='Dark drawings').focus()   # by keyboard this time
            page.keyboard.press('Space')
            self.assertEqual(page.get_by_role('button', name='Dark drawings').get_attribute('aria-pressed'), 'false')
            for _ in range(100):   # the light level (native, or K.jxl's cached decode) and a new frame
                page.wait_for_timeout(100)
                off, offimg = page.evaluate(stats, '#sharp'), page.evaluate(stats, '#sheetimg')
                if off['bg'] == offimg['bg'] == '255,255,255': break
            self.assertEqual(off['bg'], '255,255,255', name + ': the sharp layer stayed dark')
            self.assertGreater(off['dark'], 100, name + ': no dark lines after turning it off')
            self.assertEqual(offimg['bg'], '255,255,255', name + ': the overview stayed dark')
            errors.leave()
            page.reload()
            page.wait_for_function(loaded, timeout=30000)
            self.assertEqual(page.get_by_role('button', name='Dark drawings').get_attribute('aria-pressed'), 'false')
            # dark, but the worker can't make the overview dark: the sheet still opens, fits and draws its tags, with
            # the light level (before the fix img.src was never set and the sheet stayed blank)
            page.get_by_role('button', name='Dark drawings').click()
            page.evaluate("""() => { const w = sharp.worker, pm = w.postMessage.bind(w);
              w.postMessage = m => { if (m.t === 'level') { const x = dark.wait.get(m.id); dark.wait.delete(m.id); x.rej(new Error('test: no dark level')); return } pm(m) };
              dark.levels.clear(); dark.sheet = null; window.__opened = false; openSheet(cur.id, () => { window.__opened = true }) }""")
            # its callback (fit, tags, a /?kks= link) runs only once the overview loads
            page.wait_for_function("() => window.__opened === true", timeout=30000)
            page.wait_for_function(loaded, timeout=30000)
            self.assertTrue(page.evaluate("() => dark.warned && dark.levels.size === 0"), name + ': no light fallback')
            # a big sheet's dark overview is at most ~4 megapixels: 6400 × 4800 asks the worker for level 2, not 0
            asked = page.evaluate("""() => { const save = cur; let asked = null; const w = sharp.worker, pm = w.postMessage;
              w.postMessage = m => { if (m.t === 'level') { asked = m.url; const x = dark.wait.get(m.id); dark.wait.delete(m.id); x.rej(new Error('test')); return } pm.call(w, m) };
              cur = {...cur, id: 'big', w: 6400, h: 4800, levels: 5}; levelSrc(0).catch(() => {}); w.postMessage = pm; cur = save; return asked }""")
            self.assertIn('big.o2.jxl', asked or '', name)
            # dark, and the tile worker stops without answering (failed to load, or died): the pending level falls back
            # to light and the sheet opens (before the fix it waited for the answer forever, the sheet blank)
            page.evaluate("""() => { const w = sharp.worker, pm = w.postMessage.bind(w);
              w.postMessage = m => { if (m.t !== 'level') pm(m) };
              dark.levels.clear(); dark.sheet = null; window.__opened = false; openSheet(cur.id, () => { window.__opened = true });
              setTimeout(() => w.dispatchEvent(new ErrorEvent('error', {message: 'test'})), 200) }""")
            page.wait_for_function("() => sharp.worker.failed === true && dark.wait.size === 0", timeout=30000)
            page.wait_for_function("() => window.__opened === true", timeout=30000)
            errors.leave()
            browser.close()
            self.assertEqual([e for e in errors if 'test: no dark level' not in e and 'test' != e], [], name)

    def test_dark_chromium(self): self.run_dark('chromium')
    def test_dark_firefox(self): self.run_dark('firefox')
    def test_dark_webkit(self): self.run_dark('webkit')

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
