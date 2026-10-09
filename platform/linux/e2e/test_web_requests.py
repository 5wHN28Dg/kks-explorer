"""The web pages for the batch of user requests of 2026-10-08, in Chromium, Firefox and WebKit, against the Nim server
with the synthetic sample sheet:
  1. who took each photo and who set each field (index.html panel);
  2. drafted descriptions (descriptions.json): "Draft description (unchecked)", Confirm, Edit, "Confirmed by …";
  3. the floor before a photo: asked first when the code has none, sent with the photo, kept while offline;
  4. approvals grouped by code: equipment and tag plate photos apart, Pick only among several of one kind, the code a
     link to the drawing, the submitter's full name;
  5. the leaderboard (names and numbers only);
  6. a position for every new member (setup and new-account forms; join requests without one can't be accepted);
  7. removed devices hidden ("Clear removed", per-item Hide, "Show hidden (n)");
  8. My submissions filtered by status and kind and grouped by code;
  9. photos converted in the background and sent in order: closing the panel or reloading the page loses none;
 10. updates in their own tab, not in Account.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_requests.py [unittest arguments]
$KKS_SERVER and $KKS_IMPORTER name the builds (default /tmp/kkslinux, /tmp/kksimp)."""
import json, os, re, shutil, struct, subprocess, sys, tempfile, time, unittest, urllib.parse, zlib
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
IMPORTER = os.environ.get('KKS_IMPORTER', '/tmp/kksimp/kks_import')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client

PW = 'a long password'
BOSS, TOM = 'The Boss', 'Tom Smith'


def png(w, h):
    """a small RGB PNG: a gradient, so it is a real picture"""
    raw = b''.join(b'\0' + b''.join(bytes((x * 255 // w, y * 255 // h, 128)) for x in range(w)) for y in range(h))
    def chunk(t, d): return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


class WebRequests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-web-req-')
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
        boss = cls.boss = Client(cls.base)
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': BOSS,
                                               'position': 'Plant manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert boss.req('POST', '/api/sheets/import?id=sample&name=Sample', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        cls.tom = cls.account('tom', TOM)
        # a JPEG XL photo, made by the browser as the pages do (the server stores nothing else)
        with sync_playwright() as p:
            # whichever engine is installed (CI installs one per job)
            for eng in (p.chromium, p.firefox, p.webkit):
                try:
                    b = eng.launch(); break
                except Exception:
                    continue
            else:
                raise RuntimeError('no Playwright browser installed')
            ctx = b.new_context()
            ctx.request.post(cls.base + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': cls.base})
            pg = ctx.new_page()
            pg.goto(cls.base + '/learning.html')
            pg.wait_for_function("() => typeof K !== 'undefined' && K.me")
            cls.jxl = pg.evaluate("""() => { const c = document.createElement('canvas'); c.width = 64; c.height = 48;
                const g = c.getContext('2d'); g.fillStyle = '#3c5a96'; g.fillRect(0, 0, 64, 48); return K.jxlEncode(c, 1.9, 3) }""")
            b.close()

    @classmethod
    def account(cls, username, name):
        link = cls.boss.req('POST', '/api/users', {'username': username, 'full_name': name, 'position': 'Technician', 'role': 'user'})['link']
        c = Client(cls.base)
        assert c.req('POST', '/api/password-reset', {'token': link.split('#reset=')[1], 'password': PW}).get('ok')
        return c

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    # ---------------------------------------------------------------- helpers
    def context(self, p, name, user, offline_ok=False):
        browser = getattr(p, name).launch()
        # (no service worker: page.route sees every request, and offline means offline)
        ctx = browser.new_context(viewport={'width': 1300, 'height': 900}, service_workers='block')
        r = ctx.request.post(self.base + '/api/login', data={'username': user, 'password': PW}, headers={'Origin': self.base})
        self.assertTrue(r.ok, r.text())
        page = ctx.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.on('dialog', lambda d: d.accept(''))
        return browser, ctx, page, errors

    def tag(self, code, n):
        """a tag for `code` marked on the sample sheet (so /?kks=code opens it)"""
        x = 100 + 40 * n
        self.assertEqual(self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [x, 500, x + 30, 520],
                                                                                         'kks': code, 'isa': '', 'note': ''}})['status'], 'approved')

    def subs(self, client, q):
        return client.req('GET', '/api/submissions?' + q)['submissions']

    def open_panel(self, page, code):
        page.goto(self.base + '/?kks=' + code)
        page.wait_for_function("k => typeof selTag !== 'undefined' && selTag && full(selTag) === k", arg=code, timeout=30000)

    def idle(self, page, timeout=90000):
        """every photo converted and every queued change sent"""
        page.wait_for_function("() => K.outbox.length === 0 && !K.converting", timeout=timeout)

    # ---------------------------------------------------------------- index.html (as tom)
    def viewer(self, p, name, n):
        code, plain = '11LAB71AA50%d' % n, '11LAB72AA50%d' % n
        self.tag(code, n)
        self.tag(plain, n + 3)
        boss, tom = self.boss, self.tom
        # 1. the manager's notes; tom's photo, approved by the manager: credit is the proposer's
        self.assertEqual(boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'notes': 'Check the gland'}, 'base': {}}})['status'], 'approved')
        sid = tom.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': code, 'dataUrl': self.jxl}})['id']
        self.assertEqual(boss.req('POST', f'/api/submissions/{sid}/approve', {}).get('ok', True), True)
        browser, ctx, page, errors = self.context(p, name, 'tom')
        page.route('**/data/descriptions.json', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(
            {code: {'text': 'Feed water pump inlet valve', 'basis': 'P&ID note'}, plain: 'Drain valve'})))
        self.open_panel(page, code)
        P = '#panelBody'
        self.assertIn(f'by {TOM}', page.text_content(P + ' .photos figcaption'))
        self.assertIn(f'by {BOSS}', page.text_content('label[for=f_notes]'))

        # 2. the drafted description: confirm it (tom: pending), the manager approves, then it shows who confirmed it
        sec = page.locator('#descSec')
        self.assertIn('Draft description (unchecked)', sec.text_content())
        self.assertIn('Feed water pump inlet valve', sec.text_content())
        self.assertIn('Basis: P&ID note', sec.text_content())
        sec.get_by_role('button', name='Confirm').click()
        page.wait_for_function("() => document.getElementById('descSec').textContent.includes('awaiting approval')")
        pend = [s for s in self.subs(tom, 'mine=1&status=open&kind=equipment') if s['payload']['kks'] == code]
        self.assertEqual(pend[0]['payload']['changes']['custom'], [{'k': 'Description', 'v': 'Feed water pump inlet valve'}])
        boss.req('POST', f"/api/submissions/{pend[0]['id']}/approve", {})
        self.open_panel(page, code)
        self.assertIn(f'Confirmed by {TOM}', page.text_content('#descSec'))
        self.assertEqual(page.locator('#descSec').get_by_role('button', name='Confirm').count(), 0)
        # the custom field holding it shows in its own section, not twice
        self.assertFalse(page.locator('#cfs .cf').first.is_visible())
        # Edit: a new text goes as a proposal
        page.locator('#descSec').get_by_role('button', name='Edit').click()
        page.fill('#descEdit', 'Feed water pump inlet isolation valve')
        page.locator('#descSec').get_by_role('button', name='Save').click()
        page.wait_for_function("() => document.getElementById('descSec').textContent.includes('awaiting approval')")
        # a plain string in descriptions.json is the text
        self.open_panel(page, plain)
        self.assertIn('Drain valve', page.text_content('#descSec'))

        # 3. the floor first: the photo buttons appear once a floor is typed; the photo goes with it, offline too
        self.assertTrue(page.is_visible('#phFloor'))
        self.assertFalse(page.is_visible('#phAdd'))
        page.fill('#phFloor', '11')
        self.assertFalse(page.is_visible('#phAdd'))
        page.fill('#phFloor', '3')
        self.assertTrue(page.is_visible('#phAdd'))
        page.set_input_files('#phAdd input[data-plate="1"]', files=[{'name': 'plate.png', 'mimeType': 'image/png', 'buffer': png(320, 240)}])
        page.wait_for_selector('[data-a="ok"]')
        page.wait_for_function("() => document.querySelector('[data-a=arrow]').style.borderColor !== ''")   # (the photo is in the editor)
        # offline from here (WebKit's offline emulation refuses even blob: URLs, so not before the photo is read)
        ctx.set_offline(True)
        page.click('[data-a="ok"]')
        # kept on this device: converted if the converter is at hand, else as taken until it is (never dropped)
        page.wait_for_function("() => K.outbox.length === 1 && !K.converting", timeout=90000)
        q = page.evaluate("K.outbox[0].payload")
        self.assertEqual((q['kks'], q['floor'], q['caption']), (plain, '3', 'Tag plate'))
        self.assertRegex(page.text_content('#pendingSec'), 'queued offline|converting, then sent')
        self.assertFalse(page.is_visible('#phFloor'))   # the floor travels with the queued photo: not asked again
        page.wait_for_timeout(500)
        self.assertEqual(page.evaluate("K.outbox.length"), 1)
        ctx.set_offline(False)
        page.evaluate("K.convertPhotos(); K.flush()")
        self.idle(page)
        mine = [s for s in self.subs(tom, 'mine=1&status=all') if s.get('code') == plain]
        self.assertEqual(sorted(s['group_kind'] for s in mine), ['equipment', 'plate_photo'])
        self.assertEqual([s['payload']['changes'] for s in mine if s['kind'] == 'equipment'], [{'floor': '3'}])

        # a proxy or a restarting server answering 503: the photo stays queued (never dropped) and goes later
        page.route('**/api/submit', lambda r: r.fulfill(status=503, content_type='application/json', body='{"error":"unavailable"}'))
        page.evaluate("""async k => { const c = document.createElement('canvas'); c.width = 200; c.height = 150;
            c.getContext('2d').fillRect(0, 0, 50, 50); await K.queuePhoto(c, {kks: k, caption: 'after 503'}) }""", plain)
        page.wait_for_function("() => K.outbox.length === 1 && !K.outbox[0].raw && !K.converting", timeout=90000)
        page.wait_for_timeout(300)
        self.assertEqual(page.evaluate("K.outbox.length"), 1)
        page.unroute('**/api/submit')
        page.evaluate("K.flush()")
        self.idle(page)
        self.assertIn('after 503', [s['payload'].get('caption') for s in self.subs(tom, 'mine=1&status=all&kind=photo') if s.get('code') == plain])

        # a proxy refusing the body (413, a smaller limit than the server's): the photo is kept, marked refused and shown,
        # later flushes leave it alone, and Try again sends it (before, any 4xx dropped the photo for good)
        page.route('**/api/submit', lambda r: r.fulfill(status=413, content_type='text/plain', body='Request Entity Too Large'))
        page.evaluate("""async k => { const c = document.createElement('canvas'); c.width = 200; c.height = 150;
            c.getContext('2d').fillRect(0, 0, 80, 50); await K.queuePhoto(c, {kks: k, caption: 'after 413'}) }""", plain)
        page.wait_for_function("() => K.outbox.length === 1 && K.outbox[0].refused && !K.converting", timeout=90000)
        page.evaluate("K.flush()")
        page.wait_for_timeout(300)
        self.assertEqual(page.evaluate("K.outbox.length"), 1, 'a refused photo was dropped')
        self.assertIn('1 refused', page.text_content('#syncStatus'))
        page.unroute('**/api/submit')
        page.evaluate("K.retryRefused(K.outbox[0].client_id)")
        self.idle(page)
        self.assertIn('after 413', [s['payload'].get('caption') for s in self.subs(tom, 'mine=1&status=all&kind=photo') if s.get('code') == plain])

        # 9. three photos in a row: the panel closed at once; converted in the background, sent in the order taken
        page.evaluate("""async k => { for (const i of [1, 2, 3]) { const c = document.createElement('canvas'); c.width = 900; c.height = 700;
            const g = c.getContext('2d'), d = g.createImageData(900, 700); for (let j = 0; j < d.data.length; j++) d.data[j] = (j * 7919 + i * 31) % 251;
            g.putImageData(d, 0, 0); await K.queuePhoto(c, {kks: k, caption: 'order ' + i}) } closePanel() }""", plain)
        page.wait_for_selector('#photoq', state='attached', timeout=30000)
        self.assertIn('converting photo', page.text_content('#syncStatus'))
        self.assertFalse(page.is_visible('#panel'))
        self.idle(page)
        self.assertFalse(page.is_visible('#panel'))   # a photo sent never reopens a closed panel
        caps = [s['payload'].get('caption') for s in sorted(self.subs(tom, 'mine=1&status=all&kind=photo'), key=lambda s: s['id'])
                if s.get('code') == plain and s['payload'].get('caption', '').startswith('order')]
        self.assertEqual(caps, ['order 1', 'order 2', 'order 3'])
        # a photo still converting when the page goes: the next visit converts and sends it
        page.evaluate("""async k => { const c = document.createElement('canvas'); c.width = 1400; c.height = 1000;
            const g = c.getContext('2d'), d = g.createImageData(1400, 1000); for (let j = 0; j < d.data.length; j++) d.data[j] = (j * 104729) % 253;
            g.putImageData(d, 0, 0); await K.queuePhoto(c, {kks: k, caption: 'after reload'}) }""", plain)
        page.reload()
        page.wait_for_function("() => typeof K !== 'undefined' && K.me", timeout=30000)
        # (K.me is set before the outbox is read back, so an empty outbox right now proves nothing: wait for the server)
        def after_reload():
            return [s['payload'].get('caption') for s in self.subs(tom, 'mine=1&status=all&kind=photo')
                    if s.get('code') == plain].count('after reload')
        for _ in range(180):
            if after_reload(): break
            page.wait_for_timeout(500)
        self.idle(page)
        self.assertEqual(after_reload(), 1)
        browser.close()
        self.assertEqual(errors, [], name)
        return plain

    # ---------------------------------------------------------------- admin.html
    def admin(self, p, name, n, plain):
        code = '11LAB73AA50%d' % n
        self.tag(code, n + 6)
        tom, boss = self.tom, self.boss
        ids = [tom.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': code, 'caption': c, 'dataUrl': self.jxl}})['id']
               for c in ('front', 'side', 'Tag plate')]
        tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'near': 'Stairs'}, 'base': {}}})
        browser, ctx, page, errors = self.context(p, name, 'boss')
        # 4. approvals: one card per code, the kinds apart, Pick only among the two equipment photos
        page.goto(self.base + '/admin.html#queue')
        card = page.locator(f'#main .card.group[data-code="{code}"]')
        card.wait_for()
        self.assertEqual(card.locator('h3 a').get_attribute('href'), '/?kks=' + code)
        eqp, plate = card.locator('[data-kind=equipment_photo]'), card.locator('[data-kind=plate_photo]')
        self.assertEqual(eqp.get_by_role('button', name='Use this one').count(), 2)
        self.assertEqual(plate.get_by_role('button', name='Use this one').count(), 0)
        self.assertEqual(plate.get_by_role('button', name='Approve').count(), 1)
        self.assertIn(f'{TOM} (tom)', plate.text_content())
        self.assertNotIn('vote', plate.text_content())
        self.assertIn('Stairs', card.locator('[data-kind=equipment]').text_content())
        eqp.locator('figure', has_text='front').get_by_role('button', name='Use this one').click()
        page.wait_for_function("c => !document.querySelector(`.card.group[data-code='${c}'] [data-kind=equipment_photo]`)", arg=code)
        self.assertEqual(card.locator('[data-kind=plate_photo]').count(), 1)   # the tag plate photo was not rejected by the pick
        st = {s['id']: s['status'] for s in self.subs(boss, 'status=all&kind=photo') if s['id'] in ids}
        self.assertEqual([st[i] for i in ids], ['approved', 'rejected', 'pending'])

        # 7. removed devices: a person whose device was removed; Hide, Clear removed, Show hidden (n)
        gone = 'gone%d' % n
        self.account(gone, 'Gone Person %d' % n)
        dev = [d for d in boss.req('GET', '/api/devices')['all'] if d['username'] == gone][0]['device']
        boss.req('POST', '/api/devices/revoke', {'device': dev})
        page.goto(self.base + '/admin.html#devices')
        alld = page.locator('#allDevices')
        alld.wait_for()
        row = alld.locator('tr', has_text=gone)
        self.assertIn('removed', row.text_content())
        alld.get_by_role('button', name='Clear removed').click()
        page.wait_for_function("g => document.getElementById('allDevices') && !document.getElementById('allDevices').textContent.includes(g)", arg=gone)
        alld.get_by_role('button', name=re.compile(r'^Show hidden \(\d+\)$')).click()
        page.wait_for_function("g => document.getElementById('allDevices').textContent.includes(g)", arg=gone)
        alld.locator('tr', has_text=gone).get_by_role('button', name='Show again').click()
        page.wait_for_function("g => [...document.querySelectorAll('#allDevices tr')].some(r => r.textContent.includes(g) && r.textContent.includes('Hide'))", arg=gone)
        alld.locator('tr', has_text=gone).get_by_role('button', name='Hide').click()
        page.wait_for_function("g => document.getElementById('allDevices') && !document.getElementById('allDevices').textContent.includes(g) || "
                               "[...document.querySelectorAll('#allDevices tr')].some(r => r.textContent.includes(g) && r.textContent.includes('Show again'))", arg=gone)
        page.locator('#tabs button', has_text='Users').click()
        # an element only the Users tab has: the Devices tab's table is still there until it renders
        page.wait_for_selector('#main form.inline input[name=position]')
        self.assertEqual(page.locator('#main td.mono', has_text=gone).count(), 1)   # (shown again above, with the device)
        page.get_by_role('button', name='Clear removed').click()
        page.wait_for_function("g => document.querySelector('#main table') && ![...document.querySelectorAll('#main td.mono')].some(t => t.textContent === g)", arg=gone)

        # 6. a position for every new member: the new-account form, a join request without one
        self.assertIsNotNone(page.get_attribute('#main form.inline input[name=position]', 'required'))
        page.route('**/api/join-requests', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(
            {'requests': [{'device': 'dev-x', 'code': '123456', 'request': {'full_name': 'New Person', 'username': 'newp', 'label': 'phone'},
                           'existing': None, 'needs_position': True}]})))
        page.locator('#tabs button', has_text='Devices').click()
        page.wait_for_selector('#lobby .needs-position')
        self.assertIn('ask New Person to send a new request with their position', page.text_content('#lobby'))
        self.assertTrue(page.locator('#lobby').get_by_role('button', name='Accept').is_disabled())

        # 10. updates: their own tab; Account has none
        page.route('**/api/update', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(
            {'current': '1.0.0', 'latest': '1.1.0', 'available': True, 'notes': 'Fixes', 'can_install': True, 'checked': 0, 'auto': True})))
        page.locator('#tabs button', has_text='Account').click()
        page.wait_for_selector('#main input[name=full_name]')   # the Account tab itself, not the last tab's cards
        self.assertEqual(page.locator('#upd').count(), 0)
        page.locator('#tabs button', has_text='Updates').click()
        page.wait_for_selector('#upd .card')
        self.assertIn('Version 1.1.0 is out.', page.text_content('#upd'))
        self.assertEqual(page.get_by_role('button', name='Download and install').count(), 1)
        browser.close()
        self.assertEqual(errors, [], name)

        # the setup link's form: the position is required (a fresh page: the form shows before signing in)
        browser, ctx, page, errors = self.context(p, name, 'tom')
        page.goto(self.base + '/admin.html#setup=not-a-token')
        page.wait_for_selector('#kov input[name=position]')
        self.assertIsNotNone(page.get_attribute('#kov input[name=position]', 'required'))
        self.assertEqual(page.locator('#upd').count(), 0)

        # 5. the leaderboard (tom, a user): names and numbers, what each contributed
        page = ctx.new_page()
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto(self.base + '/admin.html#board')
        page.wait_for_selector('#main table')
        trow = page.locator('#main tr', has_text=TOM)
        self.assertIn('Equipment photos', trow.text_content())
        self.assertIn('Tag plate photos', trow.text_content())
        self.assertIn(BOSS, page.text_content('#main table'))
        self.assertNotIn('tom', [page.locator('#main td').nth(i).text_content() for i in range(page.locator('#main td').count())])
        cells = trow.locator('td')
        self.assertGreaterEqual(int(cells.nth(2).text_content()), 1)   # approved
        self.assertGreaterEqual(int(cells.nth(3).text_content()), 1)   # rejected (the photo the pick rejected)
        self.assertRegex(cells.nth(8).text_content(), r'ago|just now')

        # 8. My submissions: filters and groups (tom)
        page.goto(self.base + '/admin.html#mine')
        page.wait_for_selector('#mineFilters')
        def pick(status, kind):
            page.select_option('#mineFilters select[name=status]', status)
            page.wait_for_selector(f'#mineFilters[data-f^="{status}|"]')
            page.select_option('#mineFilters select[name=kind]', kind)
            page.wait_for_selector(f'#mineFilters[data-f="{status}|{kind}"]')
        pick('rejected', 'equipment_photo')
        grp = page.locator(f'#main .card.mine[data-code="{code}"]')
        self.assertEqual(grp.locator('tr').count(), 2)   # head + the rejected photo
        self.assertIn('Equipment photo', grp.text_content())
        self.assertIn('rejected', grp.text_content())
        pick('all', 'floor')
        self.assertIn('floor → 3', page.text_content(f'#main .card.mine[data-code="{plain}"]'))
        self.assertEqual(page.locator(f'#main .card.mine[data-code="{code}"]').count(), 0)
        pick('all', 'plate_photo')
        self.assertIn('new tag plate photo', page.text_content('#main'))
        # two renders overlapping: the floor filter's answer is slow, the person picks Tag plate photos meanwhile;
        # the older answer, arriving last, must not replace the newer page (before: the floor list came back)
        page.evaluate("""() => { const api = K.api; let once = true;
            K.api = async (u, ...a) => { if (once && String(u).includes('field=floor')) { once = false;
                await new Promise(r => setTimeout(r, 1500)) } return api(u, ...a) } }""")
        page.select_option('#mineFilters select[name=kind]', 'floor')
        page.wait_for_timeout(100)
        page.select_option('#mineFilters select[name=kind]', 'plate_photo')
        page.wait_for_timeout(2500)
        self.assertEqual(page.get_attribute('#mineFilters', 'data-f'), 'all|plate_photo')
        self.assertIn('new tag plate photo', page.text_content('#main'))
        browser.close()
        self.assertEqual(errors, [], name)

    def run_engine(self, name, n):
        with sync_playwright() as p:
            plain = self.viewer(p, name, n)
            self.admin(p, name, n, plain)

    def test_chromium(self): self.run_engine('chromium', 1)
    def test_firefox(self): self.run_engine('firefox', 2)
    def test_webkit(self): self.run_engine('webkit', 3)


if __name__ == '__main__':
    unittest.main()
