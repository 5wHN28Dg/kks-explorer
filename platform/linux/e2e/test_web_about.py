"""The About page of the web client (the user, 2026-10-15), in Chromium, Firefox and WebKit, against the Nim server:
  1. from the sign-in screen, before any account: Walkdown, its summary, the server's version and commit, a link to
     the source of exactly that commit (the AGPL's offer of the Corresponding Source, §13), the licence, the links;
     Escape closes it;
  2. signed in, from the main page's About button: the web app's and the server's third-party parts with their
     licences and notices, the course photos' credits, the licence texts; Close closes it;
  3. Manage → About shows the same as a page;
  4. offline (the server stopped), the copy the service worker kept is shown.
Every text comes from /api/about and is shown as text (K.h), the page raises no error and no CSP violation.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_about.py [unittest arguments]
$KKS_SERVER and $KKS_IMPORTER name the builds (default /tmp/kkslinux, /tmp/kksimp; the main page needs a drawing)."""
import json, os, shutil, sys, tempfile, time, unittest, urllib.request
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
IMPORTER = os.environ.get('KKS_IMPORTER', '/tmp/kksimp/kks_import')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import start_server, Client, CSP_WATCH, PageErrors

PW = 'a long password'


class WebAbout(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-web-about-')
        cfg = {'address': '127.0.0.1', 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        self.server, setup = start_server(SERVER, self.dir, cfg)
        self.base = 'http://127.0.0.1:%d' % cfg['port']
        boss = Client(self.base)
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW,
                                               'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f:
            pdf = f.read()
        assert boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        with urllib.request.urlopen(self.base + '/api/about') as r:
            self.about = json.load(r)

    def tearDown(self):
        if self.server.poll() is None:
            self.server.terminate()
            self.server.wait(5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def check_head(self, dlg):
        a, d = self.about, self.about['about']
        expect(dlg.get_by_role('heading', name='Walkdown', exact=True)).to_be_visible()
        expect(dlg).to_contain_text(d['summary'])
        expect(dlg).to_contain_text('Server version ' + a['version'])
        src = dlg.locator('.kab-version a')
        self.assertEqual(src.get_attribute('href'), a['source'])
        self.assertEqual(src.get_attribute('rel'), 'noopener noreferrer')
        if a['commit']:
            expect(dlg.locator('.kab-version code')).to_have_text(a['commit'][:12])
            expect(src).to_have_text("Source code of that commit, without this build's local changes (they are not published)"
                                     if a['modified'] else 'Source code of this version')
            self.assertTrue(a['source'].endswith('/tree/' + a['commit']))
        expect(dlg).to_contain_text('By Walkdown contributors. Licence: GNU Affero General Public License v3.0 or later.')
        for name, url in (('Home page', d['links']['homepage']), ('Report a problem', d['links']['issues']), ('Help', d['links']['help'])):
            self.assertEqual(dlg.get_by_role('link', name=name, exact=True).get_attribute('href'), url)

    def check_parts(self, view):
        d = self.about['about']
        expect(view.get_by_role('heading', name='The web app')).to_be_visible()
        expect(view.get_by_role('heading', name='The server')).to_be_visible()
        for c in d['components']:
            if 'web' in c['platforms'] or 'server' in c['platforms']:
                expect(view.get_by_role('link', name=c['name'], exact=True).first).to_be_visible()
        libjxl = view.locator('li', has=view.page.get_by_role('link', name='libjxl', exact=True)).first
        expect(libjxl).to_contain_text('BSD 3-Clause License')
        libjxl.get_by_text('Copyright and licence notice').click()
        expect(libjxl.locator('pre')).to_contain_text('Copyright (c) the JPEG XL Project Authors.')
        # every course photo's credit, with its links
        expect(view.get_by_role('heading', name='Course photos')).to_be_visible()
        texts = [p['text'] for p in d['photos']]
        for t in set(texts):
            expect(view.get_by_text(t, exact=True)).to_have_count(texts.count(t))
        # the licence texts: Walkdown's own among them
        agpl = view.locator('details', has_text='GNU Affero General Public License v3.0 or later')
        agpl.locator('summary').click()
        expect(agpl.locator('pre')).to_contain_text('GNU AFFERO GENERAL PUBLIC LICENSE')

    def engine(self, name):
        with sync_playwright() as p:
            browser = p[name].launch()
            ctx = browser.new_context()
            ctx.add_init_script(CSP_WATCH)
            page = ctx.new_page()
            errors = PageErrors(page)

            # ---- 1. the sign-in screen
            page.goto(self.base + '/')
            expect(page.locator('#kov form input[name=username]')).to_be_visible()
            page.get_by_role('button', name='About Walkdown').click()
            dlg = page.locator('dialog#kabout')
            expect(dlg).to_be_visible()
            self.check_head(dlg)
            page.keyboard.press('Escape')
            expect(dlg).to_have_count(0)

            # (in a context of its own without the service worker: routes don't see what a worker answers)
            rctx = browser.new_context(service_workers='block')
            rctx.add_init_script(CSP_WATCH)
            rp = rctx.new_page()
            rerrors = PageErrors(rp)
            rp.goto(self.base + '/')
            rdlg = rp.locator('dialog#kabout')
            # a build with local changes: the link says it is the commit the build started from, not this version
            changed = dict(self.about, commit='0123456789abcdef0123456789abcdef01234567', modified=True,
                           source='https://github.com/5wHN28Dg/kks-explorer/tree/0123456789abcdef0123456789abcdef01234567')
            rp.route('**/api/about', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(changed)))
            rp.get_by_role('button', name='About Walkdown').click()
            expect(rdlg.locator('.kab-version')).to_contain_text('commit 0123456789ab with local changes')
            expect(rdlg.locator('.kab-version a')).to_have_text("Source code of that commit, without this build's local changes (they are not published)")
            self.assertEqual(rdlg.locator('.kab-version a').get_attribute('href'), changed['source'])
            # an error from the server is said as one, not as "not saved"
            rp.unroute('**/api/about')
            rp.route('**/api/about', lambda r: r.fulfill(status=500, content_type='application/json', body='{"error": "internal error"}'))
            rp.keyboard.press('Escape')
            expect(rdlg).to_have_count(0)
            rp.get_by_role('button', name='About Walkdown').click()
            expect(rdlg).to_contain_text('The About page could not be loaded: internal error')
            rp.unroute('**/api/about')
            self.assertEqual(rerrors, [])
            rctx.close()

            # ---- 2. signed in, the main page's About button
            f = page.locator('#kov form')
            f.locator('input[name=username]').fill('boss')
            f.locator('input[name=password]').fill(PW)
            errors.leave()
            f.get_by_role('button', name='Sign in').click()
            expect(page.locator('#aboutBtn')).to_be_visible()
            page.locator('#aboutBtn').click()
            dlg = page.locator('dialog#kabout')
            expect(dlg).to_be_visible()
            self.check_head(dlg)
            self.check_parts(dlg)
            dlg.get_by_role('button', name='Close').click()
            expect(dlg).to_have_count(0)

            # ---- 3. Manage → About
            errors.leave()
            page.goto(self.base + '/admin.html')
            page.locator('#tabs').get_by_role('button', name='About').click()
            view = page.locator('#main .kab')
            expect(view).to_be_visible()
            self.check_head(view)
            self.check_parts(view)
            self.assertIn('#about', page.url)

            # ---- 4. offline: the service worker's copy
            page.wait_for_function("() => navigator.serviceWorker.controller")
            page.locator('#tabs').get_by_role('button', name='Account').click()   # opened again, now through the worker
            page.locator('#tabs').get_by_role('button', name='About').click()
            expect(page.locator('#main .kab')).to_be_visible()
            page.wait_for_function("async () => !!(await caches.match('/api/about'))")
            self.server.terminate(); self.server.wait(5)
            if name != 'webkit': ctx.set_offline(True)
            errors.leave()
            page.reload()
            view = page.locator('#main .kab')
            expect(view).to_be_visible(timeout=20000)
            self.check_head(view)
            expect(view.get_by_role('link', name='MuPDF', exact=True)).to_be_visible()

            self.assertEqual(errors, [])
            browser.close()

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
