"""index.html's valve type (systems.js KSys.valveType, a port of core model.valveTypeOf) in all three engines, against
the Nim server with a small synthetic plant published through `kks-server publish-data`: a valve tag whose tags.json
"symbol" was read from the drawing shows "Valve type: … (from the drawing, unchecked)" with the symbol outlined on the
drawing while its panel is open; Confirm saves it as it is (the equipment custom field "Valve type"), Correct saves the
person's value instead; then the panel shows the confirmed type (and what the drawing said, when it differs). Each
engine works on codes of its own (the server is shared).
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_valve.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (default /tmp/kks-web-shots)."""
import json, os, re, shutil, subprocess, sys, tempfile, unittest
from playwright.sync_api import sync_playwright

sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import CSP_WATCH
from test_web_systems import Client, free_port, png, tag

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-web-shots')
ENGINES = ('chromium', 'firefox', 'webkit')


def valve(i, kks, x, typ, actuator='none', nc=False):
    t = tag(i, 'a', kks, x)
    t['symbol'] = {'type': typ, 'actuator': actuator, 'nc': nc, 'conf': 0.9, 'bbox': [x + 10, 40, x + 46, 62]}
    return t


SHEETS = [{'id': 'a', 'name': 'Sheet A', 'w': 1000, 'h': 600, 'file': 'data/sheets/a.png', 'notes': []}]
TAGS = []
for n, e in enumerate(ENGINES):
    x = 40 + n * 180
    TAGS += [valve(f'a:{e}1', f'11LAB70AA5{n}1', x, 'gate valve', 'motor'),
             valve(f'a:{e}2', f'11LAB70AA5{n}2', x + 62, 'globe valve', nc=True),
             tag(f'a:{e}3', 'a', f'11LAB70CP5{n}3', x + 124)]


class WebValve(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-valve-')
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
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager'}).get('ok')
        d = os.path.join(cls.dir, 'fixture')
        os.makedirs(os.path.join(d, 'sheets'))
        for name, obj in (('sheets.json', SHEETS), ('tags.json', TAGS)):
            with open(os.path.join(d, name), 'w') as f: json.dump(obj, f)
        with open(os.path.join(d, 'sheets', 'a.png'), 'wb') as f: f.write(png(100, 60))
        r = subprocess.run([SERVER, 'publish-data', d, '--config', cls.cfg], cwd=cls.dir, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stdout + r.stderr
        os.makedirs(SHOTS, exist_ok=True)

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def custom(self, code):
        return self.boss.req('GET', '/api/state')['equipment'].get(code, {}).get('custom')

    def run_engine(self, name):
        n = ENGINES.index(name)
        gate, globe, cp = f'11LAB70AA5{n}1', f'11LAB70AA5{n}2', f'11LAB70CP5{n}3'
        x = 40 + n * 180
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
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length === 9 && typeof cur !== 'undefined' && cur", timeout=30000)
            # the gate valve: its tag clicked on the drawing
            page.click(f'#layer .hs[data-id="a:{name}1"]')
            page.wait_for_selector('#vtLine')
            self.assertEqual(page.text_content('#vtLine'), 'Valve type: gate valve, motor-operated (from the drawing, unchecked)')
            self.assertIn('90 % sure', page.text_content('#valveSec'))
            # its symbol outlined on the drawing (bbox in level-0 px, 3 px around it like the tags)
            self.assertEqual(page.locator('#layer .vsym').count(), 1)
            self.assertEqual(page.evaluate("(() => { const s = document.querySelector('#layer .vsym').style; return [s.left, s.top, s.width, s.height] })()"),
                             [f'{x + 7}px', '37px', '42px', '28px'])
            page.screenshot(path=os.path.join(SHOTS, f'valve-{name}.png'))
            # only while the panel is open
            page.click('#panel .phead .x')
            self.assertEqual(page.locator('#layer .vsym').count(), 0)
            page.click(f'#layer .hs[data-id="a:{name}1"]')
            page.wait_for_selector('#layer .vsym')
            # Confirm: sent as it is
            page.click('#valveSec button:text-is("Confirm")')
            page.wait_for_function("() => document.getElementById('vtLine')?.textContent === 'Valve type: gate valve, motor-operated (confirmed)'",
                                   timeout=15000)
            self.assertEqual(self.custom(gate), [{'k': 'Valve type', 'v': 'gate valve, motor-operated'}])
            self.assertEqual(page.locator('#layer .vsym').count(), 0, 'a confirmed type has no symbol box to show')
            self.assertEqual(page.locator('#valveSec button').count(), 0)
            # the hatched globe valve: Correct, an edited value, Send
            page.click(f'#layer .hs[data-id="a:{name}2"]')
            page.wait_for_function("() => document.getElementById('vtLine')?.textContent === 'Valve type: globe valve, normally closed (from the drawing, unchecked)'")
            self.assertEqual(page.locator('#layer .vsym').count(), 1)
            page.click('#valveSec button:text-is("Correct")')
            self.assertEqual(page.input_value('#vtValue'), 'globe valve, normally closed')
            self.assertEqual(page.evaluate("document.activeElement.id"), 'vtValue')
            # Cancel goes back to the two buttons; an empty value is refused
            page.click('#valveSec button:text-is("Cancel")')
            self.assertEqual(page.locator('#vtValue').count(), 0)
            page.click('#valveSec button:text-is("Correct")')
            page.fill('#vtValue', '   ')
            page.click('#valveSec button:text-is("Send")')
            self.assertEqual(page.text_content('#toast'), 'Type the valve type first')
            self.assertIsNone(self.custom(globe))
            page.fill('#vtValue', 'check valve')
            page.click('#valveSec button:text-is("Send")')
            page.wait_for_function("() => document.getElementById('vtLine')?.textContent === 'Valve type: check valve (confirmed)'",
                                   timeout=15000)
            self.assertIn("The drawing's symbol reads: globe valve, normally closed", page.text_content('#valveSec'))
            self.assertEqual(self.custom(globe), [{'k': 'Valve type', 'v': 'check valve'}])
            # also listed with the other custom fields
            self.assertEqual(page.input_value('#cfs .cf input >> nth=1'), 'check valve')
            # not a valve: no valve type, no outline
            page.click(f'#layer .hs[data-id="a:{name}3"]')
            page.wait_for_function(f"() => document.querySelector('#panelBody .phead .kks')?.textContent === '{cp}'")
            self.assertEqual(page.locator('#valveSec').count(), 0)
            self.assertEqual(page.locator('#layer .vsym').count(), 0)
            browser.close()
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
