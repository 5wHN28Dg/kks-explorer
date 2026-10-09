"""index.html's links between drawings (systems.js KSys.linksView, a port of core views.linksView) in all three engines,
against the Nim server with a small synthetic plant published through `kks-server publish-data`: sheets.json "links"
become dashed circles on the drawing and rows in "Connectors on this sheet". A connector with one target opens it
(another sheet, or elsewhere on this one) and marks the connector arrived at; several ask which; none says so. While
selecting tags the circles take no clicks.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_links.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (default /tmp/kks-web-shots)."""
import json, os, re, shutil, subprocess, sys, tempfile, unittest
from playwright.sync_api import sync_playwright

sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import CSP_WATCH
from test_web_systems import Client, free_port, png, tag

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-web-shots')


def link(label, x, y, side=30):
    return {'label': label, 'bbox': [x, y, x + side, y + side], 'conf': 0.9}


# sheet a: C16 continues on b; D2 twice on b (a choice); S3 nowhere; E5 twice on a itself. a has no scale (2 px per
# point), b says 2, c has no connectors at all
SHEETS = [{'id': 'a', 'name': 'Sheet A', 'w': 1000, 'h': 600, 'file': 'data/sheets/a.png', 'notes': [],
           'links': [link('C16', 100, 300), link('D2', 200, 300), link('S3', 300, 300), link('E5', 400, 300),
                     link('E5', 800, 500)]},
          {'id': 'b', 'name': 'Sheet B', 'w': 1000, 'h': 600, 'scale': 2, 'file': 'data/sheets/b.png', 'notes': [],
           'links': [link('C16', 900, 500), link('D2', 120, 80), link('D2', 600, 80)]},
          {'id': 'c', 'name': 'Sheet C', 'w': 1000, 'h': 600, 'file': 'data/sheets/c.png', 'notes': []}]
TAGS = [tag('a:1', 'a', '11LAB70AA501', 40), tag('b:1', 'b', '11LAB70AA502', 40)]


class WebLinks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-links-')
        cls.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups')}
        cls.cfg = os.path.join(cls.dir, 'config.json')
        with open(cls.cfg, 'w') as f: json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', cls.cfg], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        cls.addClassCleanup(cls.stop)   # runs even when setUpClass fails below (tearDownClass doesn't)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m: setup = m[1]
            if 'server on' in line: break
        cls.base = 'http://127.0.0.1:%d' % cls.port
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        d = os.path.join(cls.dir, 'fixture')
        os.makedirs(os.path.join(d, 'sheets'))
        for name, obj in (('sheets.json', SHEETS), ('tags.json', TAGS)):
            with open(os.path.join(d, name), 'w') as f: json.dump(obj, f)
        for s in SHEETS:
            with open(os.path.join(d, 'sheets', s['id'] + '.png'), 'wb') as f: f.write(png(100, 60))
        r = subprocess.run([SERVER, 'publish-data', d, '--config', cls.cfg], cwd=cls.dir, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stdout + r.stderr
        os.makedirs(SHOTS, exist_ok=True)

    @classmethod
    def stop(cls):
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
            page.wait_for_function("() => typeof cur !== 'undefined' && cur && cur.id === 'a' && document.querySelector('#layer .conn')",
                                   timeout=30000)
            conn = '#layer .conn[data-label="%s"]'
            sheet = lambda: page.evaluate('cur.id')
            toast = lambda: page.text_content('#toast')
            # the circles: in level-0 px (points × 2), 3 px around like the tags; named for screen readers
            self.assertEqual(page.locator('#layer .conn').count(), 5)
            self.assertEqual(page.evaluate("(() => { const s = document.querySelector('#layer .conn[data-label=\"C16\"]').style; return [s.left, s.top, s.width, s.height] })()"),
                             ['97px', '297px', '36px', '36px'])
            self.assertEqual(page.get_attribute(conn % 'C16', 'aria-label'), 'Connector C16, continues on Sheet B')
            self.assertEqual(page.get_attribute(conn % 'S3', 'aria-label'), "Connector S3, the other end isn't on any drawing in the app")
            self.assertEqual(page.get_attribute(f'{conn % "E5"} >> nth=0', 'aria-label'), 'Connector E5, continues on elsewhere on this sheet')
            page.screenshot(path=os.path.join(SHOTS, f'links-{name}.png'))
            # none: said, and the sheet stays
            page.click(conn % 'S3')
            self.assertEqual(toast(), "Connector S3: the other end isn't on any drawing in the app")
            self.assertEqual(sheet(), 'a')
            # one: the other sheet opens at the connector, which is drawn bold
            page.click(conn % 'C16')
            page.wait_for_function("() => cur.id === 'b' && document.querySelector('#layer .conn.sel')")
            self.assertEqual(toast(), 'Connector C16 on Sheet B')
            self.assertEqual(page.locator('#layer .conn.sel').count(), 1)
            self.assertEqual(page.get_attribute('#layer .conn.sel', 'data-label'), 'C16')
            self.assertEqual(page.get_attribute(conn % 'C16', 'aria-label'), 'Connector C16, continues on Sheet A')
            # only on the sheet it was followed to: another sheet and back, no longer bold
            page.select_option('#sheetSel', 'c')
            page.wait_for_function("() => cur.id === 'c'")
            page.select_option('#sheetSel', 'b')
            page.wait_for_function("() => cur.id === 'b' && document.querySelector('#layer .conn')")
            self.assertEqual(page.locator('#layer .conn.sel').count(), 0)
            page.click(conn % 'C16')                                     # back to a's C16, then to b's again
            page.wait_for_function("() => cur.id === 'a' && document.querySelector('#layer .conn.sel')")
            page.click(conn % 'C16')
            page.wait_for_function("() => cur.id === 'b' && document.querySelector('#layer .conn.sel')")
            # centred on it (the viewer is 1200 wide less the panel's room; the box is 900-930 px on the sheet)
            mid = page.evaluate("(() => { const r = document.querySelector('#layer .conn.sel').getBoundingClientRect(), v = document.getElementById('viewer').getBoundingClientRect(); return [r.left + r.width / 2 - v.left, v.width] })()")
            self.assertAlmostEqual(mid[0], (mid[1] - 430) / 2, delta=3)
            # several: asked which, numbered when one sheet has the code twice
            page.select_option('#sheetSel', 'a')
            page.wait_for_function("() => cur.id === 'a' && document.querySelector('#layer .conn')")
            page.click(conn % 'D2')
            page.wait_for_selector('dialog[open]')
            self.assertEqual(page.text_content('dialog[open] h2'), 'Where does D2 continue?')
            self.assertEqual(page.locator('dialog[open] button').all_text_contents(), ['Sheet B (1 of 2)', 'Sheet B (2 of 2)', 'Cancel'])
            page.click('dialog[open] button:text-is("Cancel")')
            page.wait_for_selector('dialog', state='detached')     # (removed on its close event)
            self.assertEqual(sheet(), 'a')
            page.click(conn % 'D2')
            page.click('dialog[open] button:text-is("Sheet B (2 of 2)")')
            page.wait_for_function("() => cur.id === 'b' && document.querySelector('#layer .conn.sel')")
            self.assertEqual(page.evaluate("document.querySelector('#layer .conn.sel').style.left"), '597px')
            self.assertEqual(toast(), 'Connector D2 on Sheet B')
            # the list: "Connectors on this sheet", the same choices; elsewhere on the same sheet
            page.select_option('#sheetSel', 'a')
            page.wait_for_function("() => cur.id === 'a' && document.querySelector('#layer .conn')")
            page.click('#linksBtn')
            self.assertEqual(page.locator('#linksBody .connrow').count(), 5)
            self.assertEqual(page.locator('#linksBody .connrow >> nth=0').text_content(), 'Connector C16continues on Sheet B')
            page.click('#linksBody .connrow >> nth=4')       # the second E5: goes to the first
            page.wait_for_function("() => document.querySelector('#layer .conn.sel')")
            self.assertEqual(sheet(), 'a')
            self.assertEqual(toast(), 'Connector E5 on Sheet A')
            self.assertEqual(page.evaluate("document.querySelector('#layer .conn.sel').style.left"), '397px')
            page.click('#linksBody .connrow >> nth=0')
            page.wait_for_function("() => cur.id === 'b'")
            page.wait_for_function("() => document.activeElement?.classList.contains('connrow')")   # focus back in the rebuilt list
            self.assertEqual(page.locator('#linksBody .connrow').count(), 3, 'the list follows the open sheet')
            page.select_option('#sheetSel', 'c')
            page.wait_for_function("() => cur.id === 'c'")
            self.assertEqual(page.text_content('#linksBody'), 'No connectors to other drawings on this sheet.')
            self.assertEqual(page.locator('#layer .conn').count(), 0)
            page.click('#linksDrawer [data-close]')
            # selecting tags: a click on a circle doesn't follow it
            page.select_option('#sheetSel', 'a')
            page.wait_for_function("() => cur.id === 'a' && document.querySelector('#layer .conn')")
            page.click('#zpick')
            page.evaluate("document.getElementById('toast').textContent = ''")
            b = page.locator(conn % 'C16').bounding_box()
            page.mouse.click(b['x'] + b['width'] / 2, b['y'] + b['height'] / 2)
            page.wait_for_timeout(500)
            self.assertEqual(sheet(), 'a')
            self.assertEqual(toast(), '')
            browser.close()
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
