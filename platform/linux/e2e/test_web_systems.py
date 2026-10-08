"""index.html's "Equipment by system" view (systems.js, a port of core views.systemsView) in all three engines, against
the Nim server with a small synthetic plant published through `kks-server publish-data` (no importer needed): the
grouping block → system → subsystem → kind, a code on two sheets once with ×2, codes that don't decode under "Other",
the filter, keyboard only (Tab to a summary, Enter opens it, Enter on a row opens the panel with focus on the code),
and a row on another sheet switching the drawing.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_systems.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (default /tmp/kks-web-shots)."""
import json, os, re, shutil, subprocess, tempfile, unittest, urllib.request, http.cookiejar, zlib, struct
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-web-shots')


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


def png(w, h):
    """a plain white PNG (the sheet's picture: v1-style sheets without a pyramid)"""
    raw = b''.join(b'\0' + b'\xff' * (w * 3) for _ in range(h))
    chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


def tag(i, sheet, kks, x, suffix='', isa=None, status='auto'):
    return {'id': i, 'sheet': sheet, 'kks': kks, 'suffix': suffix, 'isa': isa, 'kind': 'instrument' if isa else 'equipment',
            'status': status, 'conf': 0.9, 'bbox': [x, 100, x + 60, 130], 'read': ['', '']}


SHEETS = [{'id': 'a', 'name': 'Sheet A', 'w': 1000, 'h': 600, 'file': 'data/sheets/a.png', 'notes': []},
          {'id': 'b', 'name': 'Sheet B', 'w': 1000, 'h': 600, 'file': 'data/sheets/b.png', 'notes': []}]
TAGS = [tag('a:1', 'a', '11LAB70', 50), tag('a:2', 'a', '11LAB70AA501', 150),
        tag('a:3', 'a', '11HAD70CT101', 250, 'R', 'TIAC'), tag('a:4', 'a', '11LAB70AA503', 350, status='verified'),
        tag('a:6', 'a', '12LBA10AA101', 450),
        tag('b:1', 'b', '11LAB70AA501', 150), tag('b:2', 'b', '11LAB71AP001', 650)]
LOCATIONS = {'source': 'test list', 'entries': [{'kks': 'LAB70AA501', 'level': '14.50m', 'cabinet': 'C1', 'desc': 'feed valve north', 'page': 1}]}


class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + p, data=data, method=m,
                                   headers=({'Content-Type': 'application/json'} if data is not None else {}) | {'Origin': self.base})
        with self.op.open(r) as resp: return json.loads(resp.read())


class WebSystems(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-sys-')
        cls.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups')}
        cls.cfg = os.path.join(cls.dir, 'config.json')
        with open(cls.cfg, 'w') as f: json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', cls.cfg], cwd=cls.dir,
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
        d = os.path.join(cls.dir, 'fixture')
        os.makedirs(os.path.join(d, 'sheets'))
        for name, obj in (('sheets.json', SHEETS), ('tags.json', TAGS), ('locations.json', LOCATIONS)):
            with open(os.path.join(d, name), 'w') as f: json.dump(obj, f)
        for s in SHEETS:
            with open(os.path.join(d, 'sheets', s['id'] + '.png'), 'wb') as f: f.write(png(100, 60))
        r = subprocess.run([SERVER, 'publish-data', d, '--config', cls.cfg], cwd=cls.dir, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stdout + r.stderr
        # a hand-added tag joins the list (mergeTags)
        assert boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'a', 'bbox': [550, 100, 610, 130],
                        'kks': '11LAB70AA504', 'isa': '', 'note': ''}}).get('status') == 'approved'
        with open(os.path.join(REPO, 'data', 'kks.json'), encoding='utf-8') as f: cls.kks = json.load(f)
        os.makedirs(SHOTS, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def expected_tree(self):
        K = self.kks
        n = lambda t, k: k + ' · ' + K[t][k]
        return [
            [n('blocks', '11') + ' (5)', [
                [n('systems', 'HAD') + ' (1)', [['HAD70 (1)', [[n('components', 'CT') + ' (1)', ['11HAD70CT101R']]]]]],
                [n('systems', 'LAB') + ' (4)', [
                    ['LAB70 (3)', [[n('components', 'AA') + ' (3)', ['11LAB70AA501', '11LAB70AA503', '11LAB70AA504']]]],
                    ['LAB71 (1)', [[n('components', 'AP') + ' (1)', ['11LAB71AP001']]]]]]]],
            [n('blocks', '12') + ' (1)', [
                [n('systems', 'LBA') + ' (1)', [['LBA10 (1)', [[n('components', 'AA') + ' (1)', ['12LBA10AA101']]]]]]]],
            ['Other: codes that are not a full KKS (1)', ['11LAB70']]]

    TREE = r"""() => { const S = d => d.querySelector(':scope > summary').textContent.replace(/\s+/g, ' ').trim();
      const rows = d => [...d.querySelectorAll(':scope > .sysrow .mono')].map(e => e.textContent);
      const level = (d, depth) => { const kids = [...d.querySelectorAll(':scope > details')];
        return [S(d), kids.length ? kids.map(k => level(k, depth + 1)) : rows(d)] };
      return [...document.querySelectorAll('#sysBody > details')].map(d => level(d, 0)) }"""

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1200, 'height': 800})
            r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                                 headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length === 8 && typeof cur !== 'undefined' && cur", timeout=30000)
            btn = page.get_by_role('button', name='Systems')
            self.assertEqual(btn.get_attribute('aria-expanded'), 'false')
            btn.click()
            self.assertEqual(btn.get_attribute('aria-expanded'), 'true')
            self.assertTrue(page.is_visible('#sysDrawer'))
            self.assertEqual(page.evaluate("document.activeElement.id"), 'sysQ')
            self.assertEqual(page.text_content('#sysCount'), '7 codes')
            # the grouping, as the page shows it; "Other" last
            self.assertEqual(page.evaluate(self.TREE), self.expected_tree())
            # blocks open, systems closed until a filter narrows the list
            self.assertEqual(page.evaluate("[...document.querySelectorAll('#sysBody details')].filter(d => d.open).length"), 2)
            row = page.locator('.sysrow', has_text='11LAB70AA501')
            self.assertEqual(row.count(), 1)
            label = re.sub(r'\s+', ' ', row.text_content())
            for part in ('feed valve', 'Sheet A', '×2', 'no photos'):
                self.assertIn(part, label, name)
            self.assertEqual(row.locator('.sysdot').get_attribute('class'), 'sysdot p-none')
            # the filter: every word somewhere in the code, names, subsystem or description; levels open when few match
            page.fill('#sysQ', 'feed valve')   # 'feed' in LAB's name, 'valve' in AA's: the three LAB70 valves
            page.wait_for_function("document.getElementById('sysCount').textContent === '3 codes match'")
            self.assertEqual(page.evaluate("[...document.querySelectorAll('#sysBody details')].every(d => d.open)"), True)
            page.fill('#sysQ', 'NORTH')   # only in the location list's description
            page.wait_for_function("document.getElementById('sysCount').textContent === '1 code match'")
            self.assertTrue(page.is_visible('.sysrow:has-text("11LAB70AA501")'))
            page.fill('#sysQ', 'lab')
            page.wait_for_function("document.getElementById('sysCount').textContent === '5 codes match'")
            page.fill('#sysQ', 'temperature 11had')
            page.wait_for_function("document.getElementById('sysCount').textContent === '1 code match'")
            page.fill('#sysQ', 'nothing like this')
            page.wait_for_function("document.getElementById('sysCount').textContent === '0 codes match'")
            self.assertIn('No code matches', page.text_content('#sysBody'))
            page.fill('#sysQ', '')
            page.wait_for_function("document.getElementById('sysCount').textContent === '7 codes'")
            page.screenshot(path=os.path.join(SHOTS, 'systems-' + name + '.png'))
            # keyboard only: Tab from the filter to the block, to its first system; Enter opens each level; Enter on the
            # row opens the panel with focus on the code
            page.focus('#sysQ')
            focused = lambda: page.evaluate("(() => { const e = document.activeElement; return e.tagName + ':' + e.textContent.replace(/\\s+/g, ' ').trim() })()")
            page.keyboard.press('Tab')
            self.assertTrue(focused().startswith('SUMMARY:11 '), focused())
            for want in ('SUMMARY:HAD ', 'SUMMARY:HAD70 ', 'SUMMARY:CT '):
                page.keyboard.press('Tab')
                self.assertTrue(focused().startswith(want), name + ': ' + focused())
                page.keyboard.press('Enter')
                self.assertTrue(page.evaluate("document.activeElement.parentElement.open"), name + ': Enter did not open ' + want)
            page.keyboard.press('Tab')
            self.assertTrue(focused().startswith('BUTTON:') and '11HAD70CT101R' in focused(), name + ': ' + focused())
            page.keyboard.press('Enter')
            page.wait_for_function("document.activeElement && document.activeElement.getAttribute('role') === 'heading'", timeout=15000)
            self.assertIn('11HAD70CT101R', page.evaluate("document.activeElement.textContent"))
            # a row on another sheet switches the drawing
            page.get_by_role('button', name='Systems').click()   # (closes)
            page.get_by_role('button', name='Systems').click()   # (opens, rebuilt)
            page.fill('#sysQ', 'lab71')
            page.wait_for_function("document.getElementById('sysCount').textContent === '1 code match'")
            page.click('.sysrow:has-text("11LAB71AP001")')
            page.wait_for_function("() => cur.id === 'b' && selTag && full(selTag) === '11LAB71AP001'", timeout=15000)
            self.assertIn('11LAB71AP001', page.text_content('#panelBody .phead .kks'))
            # the close button returns focus to the Systems button
            page.click('#sysDrawer [data-close]')
            self.assertFalse(page.is_visible('#sysDrawer'))
            self.assertEqual(page.evaluate("document.activeElement.id"), 'sysBtn')
            browser.close()
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
