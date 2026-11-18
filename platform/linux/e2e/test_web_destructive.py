"""#365 (D1, D2 in docs/UI-UX-POLICY.md): on the drawing page, unlinking a procedure step's code acts at once and offers
Undo, which puts the link back; removing a hand-marked tag asks first in the page's own dialog (the action named on its
button, the focus on Cancel, Escape keeps), never with the browser's confirm(). In Chromium, Firefox and WebKit.
  KKS_SERVER=… KKS_IMPORTER=… .venv/bin/python platform/linux/e2e/test_web_destructive.py"""
import json, os, shutil, sys, tempfile, time, unittest
from playwright.sync_api import sync_playwright, expect

sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import REPO, SERVER, IMPORTER, start_server, Client, CSP_WATCH, PageErrors  # noqa: E402

KKS = '11LAB70AA501'
PROCS = [{'id': 'EP-1', 'title': 'Start the feed pump', 'path': ['Feedwater'], 'page': 3,
          'steps': [{'n': 1, 'text': 'Open the suction valve'}, {'n': 2, 'text': 'Start the pump'}]}]


class Destructive(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-destr-')
        cfg = {'address': '127.0.0.1', 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        cls.server, setup = start_server(SERVER, cls.dir, cfg)
        cls.base = 'http://127.0.0.1:%d' % cfg['port']
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert cls.boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = cls.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def run_engine(self, name, n):
        code = KKS[:-1] + str(n)                       # (each engine its own tag and link)
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400 + 60 * n, 300, 450 + 60 * n, 340],
                                                                                  'kks': code, 'isa': '', 'note': ''}})
        self.assertEqual(r['status'], 'approved')
        self.assertEqual(self.boss.req('POST', '/api/submit', {'kind': 'link', 'payload': {'proc': 'EP-1', 'step': 2, 'kks': code, 'on': True}})['status'], 'approved')
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1200, 'height': 800}, service_workers='block')
            ctx.add_init_script(CSP_WATCH)
            self.assertTrue(ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                                             headers={'Origin': self.base}).ok)
            page = ctx.new_page()
            errors = PageErrors(page)
            browser_asked = []
            page.on('dialog', lambda d: (browser_asked.append(d.message), d.dismiss()))
            page.route('**/data/procedures.json', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(PROCS)))
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length > 0", timeout=30000)

            # Unlink: no question; the link goes, Undo for a while, and Undo brings it back
            page.click('#procBtn')
            page.locator('#procBody .proc').first.click()
            step = page.locator('#procBody .step').nth(1)
            chip = lambda: page.locator('#procBody .step').nth(1).locator('.chip.mono', has_text=code)
            expect(chip()).to_have_count(1)
            step.get_by_role('button', name='Unlink ' + code).click()
            expect(chip()).to_have_count(0)
            bar = page.locator('#kundo')
            expect(bar).to_contain_text(f'Unlinked {code} from step 2')
            self.assertEqual(bar.get_attribute('role'), 'status')
            page.wait_for_timeout(3500)
            expect(bar).to_be_visible()                                   # (still there after 3.5 s: D1's 4 s)
            bar.get_by_role('button', name='Undo').click()
            expect(chip()).to_have_count(1, timeout=15000)
            expect(bar).to_have_count(0)

            # Remove a hand-marked tag: the page's own question; Escape and Enter keep it, the named button removes it
            page.evaluate("(c) => select(eff(TAGS.find(t => full(t) === c)))", code)
            remove = page.get_by_role('button', name='Remove this tag')
            remove.click()
            ask = page.get_by_role('alertdialog', name=f'Remove the tag {code}?')
            expect(ask).to_be_visible()
            self.assertEqual([b.text_content() for b in ask.get_by_role('button').all()], ['Cancel', 'Remove tag'])
            self.assertEqual(page.evaluate('document.activeElement.textContent'), 'Cancel')
            page.keyboard.press('Escape')
            expect(ask).to_have_count(0)
            self.assertEqual(page.evaluate('document.activeElement.textContent'), 'Remove this tag')   # the focus came back
            page.keyboard.press('Enter')                                  # (the focused Remove this tag asks again)
            expect(ask).to_be_visible()
            page.keyboard.press('Enter')                                  # Enter presses Cancel
            expect(ask).to_have_count(0)
            page.wait_for_timeout(300)
            self.assertTrue(page.evaluate("(c) => TAGS.some(t => full(t) === c)", code))
            remove.click()
            ask.get_by_role('button', name='Remove tag').click()
            page.wait_for_function("(c) => !TAGS.some(t => full(t) === c)", arg=code, timeout=15000)
            self.assertEqual(browser_asked, [])
            browser.close()
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium', 1)
    def test_firefox(self): self.run_engine('firefox', 2)
    def test_webkit(self): self.run_engine('webkit', 3)


if __name__ == '__main__':
    unittest.main()
