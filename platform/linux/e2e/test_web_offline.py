"""The whole plant on the device ("Download for offline", the user, 2026-10-10), in Chromium, Firefox and WebKit, against
the Nim server with the synthetic sample sheet:
  1. Manage → Account → "Download for offline": progress, then "Ready for offline: N MB, updated <when>"; every file of
     the server's list (GET /api/offline), the state and every photo is in the service worker's caches, although no
     drawing, photo or course was opened before;
  2. offline (the server stopped, and context.set_offline where the engine can: see offline() below): the drawing opens (overview and the sharp layer), search finds a tag, its photo
     shows, a place is edited, a photo is taken (queued, converted, kept), several tags get a note, the Learning page
     lists the courses and a course opens;
  3. a restart while offline: everything still there, the queue too;
  4. the lease: 29 days later it still works; 31 days later it says that offline access expired, and why;
  5. back online: the queued changes and the photo arrive, once;
  6. honest about failure: a download started without a connection says so and finishes by itself when the server is
     back; a full disk is said in words; new plant data and new photos are fetched without asking; "Remove" removes;
  7. an iPhone in a Safari tab is told to add the app to the Home Screen first.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_offline.py [unittest arguments]
$KKS_SERVER and $KKS_IMPORTER name the builds (default /tmp/kkslinux, /tmp/kksimp)."""
import datetime, json, os, re, shutil, subprocess, sys, tempfile, time, unittest
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
IMPORTER = os.environ.get('KKS_IMPORTER', '/tmp/kksimp/kks_import')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client, CSP_WATCH, PageErrors
from test_web_requests import png

PW = 'a long password'
# each engine has its own two codes (the server is shared): [the one with a photo, the one that gets a photo offline]
CODES = {'chromium': ('11LAB70AA501', '11LAB70AA503'), 'firefox': ('11LAB71AA501', '11LAB71AA503'), 'webkit': ('11LAB72AA501', '11LAB72AA503')}
JXL_1PX = 'data:image/jxl;base64,/woAEBAJCAABACgASxiLFcJJQU5/AA=='
IPHONE = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1'
SHEET_SHOWN = "() => { const i = document.getElementById('sheetimg'); return i && i.complete && i.naturalWidth > 0 }"


class WebOffline(unittest.TestCase):
    @classmethod
    def start_server(cls):
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            if 'setup link file: ' in line:
                with open(line.split('setup link file: ', 1)[1].strip()) as f: setup = re.search(r'#setup=([A-Za-z0-9_-]+)', f.read())[1]
            if 'server on' in line: break
        return setup

    @classmethod
    def stop_server(cls):
        cls.server.terminate()
        cls.server.wait(10)
        cls.server.stdout.close()

    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-offline-')
        cls.port = free_port()
        # the web files as the server serves them, in a folder of the test's own: links to the repository's, and its
        # own copy of sw.js (an update of the app is a changed sw.js)
        cls.web = os.path.join(cls.dir, 'web')
        os.makedirs(cls.web)
        for n in os.listdir(REPO):
            if n == 'vendor' or (os.path.isfile(os.path.join(REPO, n)) and n.endswith(('.html', '.js', '.css', '.png', '.svg', '.webmanifest')) and n != 'sw.js'):
                os.symlink(os.path.join(REPO, n), os.path.join(cls.web, n))
        shutil.copy(os.path.join(REPO, 'sw.js'), os.path.join(cls.web, 'sw.js'))
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': cls.web,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl'), 'offline_days': 30}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        setup = cls.start_server()
        cls.base = 'http://127.0.0.1:%d' % cls.port
        boss = cls.boss = Client(cls.base)
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': 'The Manager',
                                               'position': 'Plant manager'}).get('ok')
        cls.import_sheet('sample', 'Sample sheet')
        for j, pair in enumerate(CODES.values()):
            for i, k in enumerate(pair):
                assert boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400 + 200 * i, 300 + 80 * j, 520 + 200 * i, 360 + 80 * j],
                                'kks': k, 'isa': '', 'note': ''}}).get('status') == 'approved'
            cls.add_photo(pair[0], 'Before the download')

    @classmethod
    def import_sheet(cls, sid, name):
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert cls.boss.req('POST', f'/api/sheets/import?id={sid}&name={name.replace(" ", "%20")}', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = cls.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']

    @classmethod
    def add_photo(cls, kks, caption):
        r = cls.boss.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': kks, 'caption': caption, 'dataUrl': JXL_1PX}})
        assert r.get('status') == 'approved', r

    @classmethod
    def tearDownClass(cls):
        cls.stop_server()
        shutil.rmtree(cls.dir, ignore_errors=True)

    def photos(self, kks):
        return [p for p in self.boss.req('GET', '/api/state')['photos'] if p['kks'] == kks]

    def until(self, page, js, arg=None, timeout=30000):
        """wait for an async predicate (page.wait_for_function takes a pending promise for "true")"""
        end = time.time() + timeout / 1000
        while True:
            if page.evaluate(js, arg): return
            if time.time() > end: self.fail('timed out waiting for: ' + js[:200])
            page.wait_for_timeout(250)

    def account(self, page):
        page.goto(self.base + '/admin.html#account')
        expect(page.locator('#offlineCard')).to_be_visible(timeout=30000)

    def engine(self, name):
        A, B = CODES[name]
        if self.server.poll() is not None: self.start_server()     # (an engine that failed while "offline" left it stopped)
        with sync_playwright() as p:
            # a browser with a profile on disk, so that it can really be closed and started again
            profile = tempfile.mkdtemp(prefix='profile-', dir=self.dir)
            off = False
            def launch():
                c = p[name].launch_persistent_context(profile, viewport={'width': 1200, 'height': 800})
                c.add_init_script(CSP_WATCH)
                if off and name != 'webkit': c.set_offline(True)
                return c
            ctx = launch()
            r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.pages[0] if ctx.pages else ctx.new_page()
            errors = PageErrors(page)
            # Offline here = the server is gone (stopped), and in Chromium and Firefox the browser is told it has no
            # network as well (context.set_offline). Not in WebKit: its offline emulation fails every navigation with
            # an internal error before the service worker is asked, and refuses blob: URLs; there the device "has a
            # network" and the server can't be reached, which is the other way a phone is offline.
            def offline():
                nonlocal off
                off = True
                self.stop_server()
                if name != 'webkit': ctx.set_offline(True)
            def online():
                nonlocal off
                off = False
                self.start_server()
                ctx.set_offline(False)

            # ---- 6a. a download started without a connection says so, and finishes by itself when the server is back
            self.account(page)
            page.wait_for_function("() => navigator.serviceWorker.controller")
            expect(page.locator('#offlineState')).to_contain_text('To work where there is no connection')
            self.assertEqual(page.locator('#offlineIos').count(), 0)
            offline()
            page.get_by_role('button', name='Download for offline').click()
            expect(page.locator('#offlineState')).to_contain_text('Not ready for offline yet', timeout=30000)
            expect(page.locator('#offlineState')).to_contain_text('The connection was lost before everything was saved')
            self.assertFalse(page.evaluate("K.offline.state.done"))
            online()
            # ---- 1. …then: ready, with its size and time; the status line counted along
            expect(page.locator('#offlineState')).to_contain_text('Ready for offline', timeout=120000)
            text = page.text_content('#offlineState')
            self.assertRegex(text, r'Ready for offline: \d+(\.\d)? MB in \d+ files, updated ')
            st = page.evaluate("K.offline.state")
            self.assertTrue(st['on'] and st['done'] and st['error'] is None, st)
            self.assertGreater(st['bytes'], 10_000_000)      # the pages, the decoders and encoder, the fonts, the courses, the drawing
            self.assertLess(abs(st['at'] / 1000 - time.time()), 300)
            # every file the server lists, the state and the photo are in the caches: nothing of it was opened before
            missing = page.evaluate("""async () => {
              const man = await (await fetch('/api/offline')).json(), st = await (await fetch('/api/state')).json(), out = [];
              const urls = [...new Set([...man.files.map(f => f[0]), '/api/state', '/api/courses', '/api/config', ...st.photos.map(p => '/photos/' + p.file)])];
              for (const u of urls) if (!await caches.match(u)) out.push(u);
              return {missing: out, n: urls.length, v: man.plant_data, sheets: man.files.filter(f => f[0].startsWith('/data/sheets/')).map(f => f[0]),
                      kinds: ['/index.html', '/vendor/kks/kks-simd.wasm', '/data/courses/', '/data/tags.json', '/data/kks.json', '.woff2', '/apple-touch-icon.png']
                               .filter(k => !man.files.some(f => f[0].includes(k)))} }""")
            self.assertEqual(missing['missing'], [])
            self.assertEqual(missing['kinds'], [])
            self.assertEqual(missing['n'], st['files'])
            v = '?v=%d' % missing['v']
            self.assertTrue(any(u.endswith('sample.kkp' + v) for u in missing['sheets']) and any(u.endswith('sample.o0.jxl' + v) for u in missing['sheets']), missing['sheets'])
            self.assertGreaterEqual(len(self.photos(A)), 1)

            # (Chromium and WebKit have opened the drawings page once while connected, so they know the plant data
            # version behind the drawings' ?v=; Firefox has not, and finds the saved files all the same)
            if name != 'firefox':
                errors.leave(); page.goto(self.base + '/')
                page.wait_for_function(SHEET_SHOWN, timeout=30000)
                self.until(page, "() => K.idb.get('pdv').then(v => !!v)")
            # ---- 2. offline: a new page (nothing in memory), the drawing, search, the tag, its photo
            errors.leave()
            offline()
            failed = []
            def watch(pg):
                pg.on('requestfailed', lambda q: failed.append(q.url))
                if os.environ.get('KKS_DEBUG'):
                    pg.on('console', lambda m: print('console:', m.type, m.text[:300], file=sys.stderr))
                    pg.on('requestfailed', lambda q: print('failed:', q.url, q.failure, file=sys.stderr))
                return pg
            np = watch(ctx.new_page()); page.close(); page = np
            errors = PageErrors(page)
            page.goto(self.base + '/')
            page.wait_for_function(SHEET_SHOWN, timeout=30000)
            expect(page.locator('#syncStatus')).to_contain_text('Offline')
            self.assertIn('Offline access lasts until', page.get_attribute('#syncStatus', 'title'))
            # zoom in: the sharp layer is drawn from the saved path store
            box = page.locator('#viewer').bounding_box()
            page.mouse.move(box['x'] + box['width'] / 2, box['y'] + box['height'] / 2)
            for _ in range(6): page.mouse.wheel(0, -400); page.wait_for_timeout(80)
            page.wait_for_function("() => { const c = document.getElementById('sharp'); return c && c.style.display === 'block' }", timeout=30000)
            # search → the tag → its panel, with the photo taken before the download (decoded from the saved file)
            page.fill('#q', A)
            page.locator('#results .res').first.click()
            page.wait_for_function("k => typeof selTag !== 'undefined' && selTag && full(selTag) === k", arg=A, timeout=15000)
            page.wait_for_function("""() => { const i = document.querySelector('#panel .photos img');
              return i && i.complete && i.naturalWidth > 0 && getComputedStyle(i).visibility === 'visible' }""", timeout=30000)
            # edit a place: queued
            page.get_by_role('button', name='Edit Near / landmark').click()
            page.fill('#f_near', 'pump hall, ' + name)
            page.locator('#eqSave').get_by_role('button', name='Save').click()
            page.wait_for_function("() => K.outbox.length === 1")
            # several tags, one note: queued, one item per code
            ids = page.evaluate("ks => ks.map(k => TAGS.find(t => full(t) === k).id)", [A, B])
            page.locator('#panel .x').first.click()
            page.get_by_role('button', name='Select tags').click()
            for i in ids: page.locator(f'#layer .hs[data-id="{i}"]').dispatch_event('click')
            page.click('#pickNote')
            page.locator('dialog[open]').get_by_label('Note', exact=True).fill('noted offline by ' + name)
            page.locator('dialog[open] [data-send]').click()
            page.wait_for_function("() => K.outbox.length === 3")
            if page.is_visible('#pickDone'): page.click('#pickDone')
            # a photo
            page.goto(self.base + '/?kks=' + B)
            page.wait_for_function("k => typeof selTag !== 'undefined' && selTag && full(selTag) === k", arg=B, timeout=30000)
            self.assertFalse(page.evaluate("K.online"))
            page.fill('#phFloor', '3')
            page.set_input_files('#phAdd input:not([data-plate])', files=[{'name': 'p.png', 'mimeType': 'image/png', 'buffer': png(320, 240)}])
            page.wait_for_selector('[data-a="ok"]')
            page.wait_for_function("() => document.querySelector('[data-a=arrow]').style.borderColor !== ''")
            page.click('[data-a="ok"]')
            # kept, and converted here although the encoder was never used before: it came with the download
            page.wait_for_function("() => K.outbox.length === 4 && !K.converting && K.outbox.every(i => !i.raw)", timeout=120000)
            self.assertTrue(page.evaluate("K.outbox.find(i => i.kind === 'photo').payload.dataUrl.startsWith('data:image/jxl')"))
            # the courses: the list, and a course with its text (pages reached with ?c=…, fonts, pictures)
            page.goto(self.base + '/learning.html')
            expect(page.locator('#main a.course').first).to_be_visible(timeout=15000)
            page.locator('#main a.course').first.click()
            page.wait_for_function("() => location.pathname === '/course.html' && document.querySelectorAll('h1, h2').length > 0", timeout=30000)
            page.wait_for_function("() => [...document.fonts].some(f => f.status === 'loaded')", timeout=30000)   # its fonts, from the copy

            # ---- 3. a restart while offline (the browser closed and started again): the queue is there, the tag and
            # its changes too, and Manage → Account still says the copy is ready
            errors.leave(); ctx.close()
            ctx = launch()
            page = watch(ctx.pages[0] if ctx.pages else ctx.new_page())
            errors = PageErrors(page)
            self.account(page)
            expect(page.locator('#offlineState')).to_contain_text('Ready for offline')
            errors.leave()
            page.goto(self.base + '/?kks=' + A)
            page.wait_for_function("k => typeof selTag !== 'undefined' && selTag && full(selTag) === k", arg=A, timeout=30000)
            self.assertEqual(page.evaluate("K.outbox.map(i => i.kind).sort()"), ['equipment', 'equipment', 'equipment', 'photo'])
            expect(page.locator('#syncStatus')).to_contain_text('4 queued')
            expect(page.locator('#pendingSec')).to_contain_text('queued offline')
            # nothing the pages asked for was missing offline (the server's own API can't answer, of course)
            self.assertEqual([u for u in failed if '/api/' not in u], [])

            # ---- 4. the lease: 29 days on, still working and saying how long; 31 days on, expired, in words
            now = datetime.datetime.now()
            page.clock.set_fixed_time(now + datetime.timedelta(days=29, hours=12))
            errors.leave(); page.reload()
            page.wait_for_function(SHEET_SHOWN, timeout=30000)
            expect(page.locator('#syncStatus')).to_contain_text('Offline · 0 days left · 4 queued')
            page.clock.set_fixed_time(now + datetime.timedelta(days=31))
            errors.leave(); page.reload()
            expect(page.locator('#kov .box')).to_contain_text('Offline access on this device expired (it lasts 30 days after the last sign-in check)', timeout=15000)
            expect(page.locator('#kov .box')).to_contain_text('are kept on this device and are sent then')
            self.assertEqual(page.evaluate("K.idb.all().then(a => a.length)"), 3)      # (the note for two codes is one item)
            # (a page left open over the end of the lease says so too, without a reload)
            page.clock.set_fixed_time(now + datetime.timedelta(days=29))
            errors.leave(); page.reload()
            page.wait_for_function(SHEET_SHOWN, timeout=30000)
            self.assertEqual(page.locator('#kov .box').count(), 0)
            page.clock.set_fixed_time(now + datetime.timedelta(days=31))
            expect(page.locator('#kov .box')).to_contain_text('Offline access on this device expired', timeout=40000)

            # ---- 5. back online, on a page that was started offline and stays open: it notices the server by itself
            # and everything queued arrives, once
            page.clock.set_fixed_time(datetime.datetime.now())
            errors.leave(); page.reload()
            page.wait_for_function(SHEET_SHOWN, timeout=30000)
            self.assertEqual(page.evaluate("[K.online, K.outbox.length]"), [False, 4])
            online()
            n_before = len(self.photos(B))
            page.wait_for_function("() => K.online && K.outbox.length === 0 && !K.converting", timeout=120000)
            page.wait_for_timeout(1500)
            page.evaluate("K.flush()")
            state = self.boss.req('GET', '/api/state')
            self.assertEqual(state['equipment'][A]['near'], 'pump hall, ' + name)
            for k in (A, B):
                self.assertEqual(state['equipment'][k]['notes'].count('noted offline by ' + name), 1, state['equipment'][k])
            self.assertEqual(len(self.photos(B)), n_before + 1)
            self.assertEqual(state['equipment'][B]['floor'], '3')

            # ---- 6b. kept up to date by itself: a photo somebody adds and a newly published drawing are fetched
            self.account(page)
            expect(page.locator('#offlineState')).to_contain_text('Ready for offline', timeout=60000)
            self.add_photo(A, 'After the download, ' + name)
            new_file = self.photos(A)[-1]['file']
            self.import_sheet('more' + name, 'More ' + name)
            self.until(page, """async f => !!(await caches.match('/photos/' + f))
              && (await (await caches.open('kks-data-v2')).keys()).some(r => r.url.includes('/data/sheets/more') && r.url.includes('.kkp'))""",
                       arg=new_file, timeout=240000)
            # the older version's drawing files are gone (only the current ?v= stays)
            self.until(page, """async () => { const pd = (await (await fetch('/api/offline')).json()).plant_data;
              const ks = (await (await caches.open('kks-data-v2')).keys()).map(r => r.url).filter(u => u.includes('/data/sheets/'));
              return !K.offline.run && K.offline.state.done && K.offline.state.plant_data === pd && ks.length > 0 && ks.every(u => u.endsWith('?v=' + pd)) }""", timeout=120000)
            expect(page.locator('#offlineState')).to_contain_text('Ready for offline', timeout=60000)
            # the server (or its proxy) busy for a moment takes nothing from a copy that is ready
            page.route('**/api/offline', lambda r: r.fulfill(status=502, content_type='application/json', body='{"error":"bad gateway"}'))
            page.get_by_role('button', name='Update now').click()
            page.wait_for_function("() => !K.offline.run && K.offline.ranAt > 0")
            page.wait_for_timeout(300)
            self.assertTrue(page.evaluate("K.offline.state.done"))
            expect(page.locator('#offlineState')).to_contain_text('Ready for offline')
            page.unroute('**/api/offline')
            # an update of the app (a new service worker, which drops the older one's cache of pages): the decoders, the
            # encoder, the fonts and the rest that was saved beside the pages are still there
            with open(os.path.join(self.web, 'sw.js')) as f: sw = f.read()
            new_shell = 'kks-shell-t' + name
            with open(os.path.join(self.web, 'sw.js'), 'w') as f: f.write(re.sub(r"kks-shell-[a-z0-9]+'", new_shell + "'", sw, count=1))
            old_shell = page.evaluate("K.offline.sw({t: 'hello'}).then(r => r.shell)")
            self.assertNotEqual(old_shell, new_shell)
            page.evaluate("navigator.serviceWorker.ready.then(r => r.update())")
            self.until(page, "async ([s, old]) => (await K.offline.sw({t: 'hello'}, 2000)).shell === s && !(await caches.keys()).includes(old)",
                       arg=[new_shell, old_shell], timeout=60000)      # (the new worker is the active one and has finished moving in)
            left = page.evaluate("""async () => { const man = await (await fetch('/api/offline')).json();
              const ck = await K.offline.sw({t: 'check', urls: [...man.files.map(f => f[0]), '/api/config', '/api/state', '/api/courses']});
              return {missing: ck.missing, caches: await caches.keys(), n: man.files.length} }""")
            self.assertEqual(left['missing'], [], left)
            self.assertGreater(left['n'], 50)
            self.assertEqual(sorted(left['caches']), ['kks-data-v2', new_shell])
            # a full disk is said in words, not hidden
            page.evaluate("""() => { const real = K.offline.sw.bind(K.offline);
              K.offline.sw = (m, ms) => m.t === 'keep' && m.url.startsWith('/data/sheets/') ? Promise.resolve({ok: false, quota: true, error: 'QuotaExceededError'}) : real(m, ms) }""")
            page.get_by_role('button', name='Update now').click()
            expect(page.locator('#offlineState')).to_contain_text('This device has no room left for the offline copy', timeout=60000)
            self.assertFalse(page.evaluate("K.offline.state.done"))
            # Remove: the drawings and photos saved for offline go, and nothing is fetched again
            errors.leave(); page.reload()
            expect(page.locator('#offlineCard')).to_be_visible(timeout=30000)
            page.get_by_role('button', name='Remove the offline copy').click()
            expect(page.locator('#offlineState')).to_contain_text('To work where there is no connection')
            self.until(page, """async () => !K.offline.run && (await (await caches.open('kks-data-v2')).keys()).filter(r => /\\/data\\/sheets\\/|\\/photos\\//.test(r.url)).length === 0""", timeout=30000)
            self.assertEqual(list(errors), [])

            # ---- 7. an iPhone in a Safari tab: told to add the app to the Home Screen first; from the Home Screen, not
            ctx.close()
            browser = p[name].launch()
            ictx = browser.new_context(viewport={'width': 390, 'height': 844}, user_agent=IPHONE)
            ictx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': self.base})
            ip = ictx.new_page()
            self.account(ip)
            expect(ip.locator('#offlineIos')).to_contain_text('add Walkdown to the Home Screen first')
            self.assertEqual(ip.evaluate("getComputedStyle(document.querySelector('input')).fontSize"), '16px')   # (no zoom into fields)
            ictx.add_init_script("Object.defineProperty(Navigator.prototype, 'standalone', {get: () => true})")
            ip.reload()
            expect(ip.locator('#offlineCard')).to_be_visible(timeout=30000)
            self.assertEqual(ip.locator('#offlineIos').count(), 0)
            # the pages say they are an app for the Home Screen
            head = ip.evaluate("""() => Object.fromEntries([...document.head.querySelectorAll('meta[name], link[rel]')].map(e => [e.name || e.rel, e.content || e.getAttribute('href')]))""")
            self.assertEqual((head['apple-mobile-web-app-capable'], head['apple-mobile-web-app-title'], head['apple-touch-icon'], head['manifest']),
                             ('yes', 'Walkdown', '/apple-touch-icon.png', '/manifest.webmanifest'))
            self.assertIn('viewport-fit=cover', head['viewport'])
            browser.close()

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
