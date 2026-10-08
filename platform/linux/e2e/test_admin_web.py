"""The web pages' views with hostile plant data (#7: no HTML sink takes data), in Chromium, Firefox and WebKit, against
the Nim server with the synthetic sample sheet: every view of admin.html (approvals with pending proposals from a
second user whose full name and values are markup, my submissions, users, devices with the invite QR, history,
drawings with the import job, account with a pending hand-over and an update), and index.html's equipment panel,
pending changes, photos, search results, procedures, location list, review queue, sheet notes and the missed-tag form.
Each value must appear as text, no element of it may appear and no script of it may run. Keyboard: a rewritten button
reached with Tab and pressed with Enter on each page.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_admin_web.py [unittest arguments]
$KKS_SERVER and $KKS_IMPORTER name the builds (default /tmp/kkslinux, /tmp/kksimp)."""
import json, os, re, shutil, subprocess, sys, tempfile, time, unittest, urllib.parse
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
IMPORTER = os.environ.get('KKS_IMPORTER', '/tmp/kksimp/kks_import')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client, CSP_WATCH

# short enough for a name (80 characters): closes an attribute, an <img> whose onerror runs, an element with an id
NAME = '"><img src=x onerror=pwned=1><b id=injected>N</b>\''
# for longer fields: the same, plus a <script>
EVIL = '<img src=x onerror="window.pwned=1"><b id=injected>x</b>"><script>window.pwned=2</script>\'"'
PW = 'a long password'
KKS = '11LAB70AA501'   # the tag marked on the sample sheet below
ENGINES = ('chromium', 'firefox', 'webkit')


class AdminWeb(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-admin-web-')
        cls.port = free_port()
        # a sync port: the invite QR needs one ("Sync is off on this device" otherwise)
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': free_port(), 'plant_name': 'Test plant', 'web_dir': REPO,
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
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': NAME,
                                               'position': NAME}).get('ok')
        # the drawing's name is markup too; it shows in Drawings, the import job, the sheet list, search results, chips
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert boss.req('POST', '/api/sheets/import?id=sample&name=' + urllib.parse.quote(NAME), raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        # the manager's own changes apply at once: a marked tag with a note, one without a code (the review queue), the
        # equipment's fields, a procedure link
        for body in ({'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360], 'kks': KKS, 'isa': '', 'note': EVIL}},
                     {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [600, 300, 700, 360], 'kks': '', 'isa': '', 'note': EVIL}},
                     {'kind': 'equipment', 'payload': {'kks': KKS, 'changes': {'area': NAME, 'notes': EVIL, 'custom': [{'k': NAME, 'v': EVIL}]}, 'base': {}}},
                     {'kind': 'link', 'payload': {'proc': 'EP-1', 'step': 1, 'kks': KKS, 'on': True}}):
            assert boss.req('POST', '/api/submit', body).get('status') == 'approved', body
        # a second user (tom) and an admin (ann), both named with markup; the manager offers ann the manager role
        cls.tom = cls.account('tom', 'user')
        cls.account('ann', 'admin')
        assert boss.req('POST', '/api/manager/transfer', {'username': 'ann', 'password': PW}).get('ok') is not None
        # a JPEG XL photo, made by the browser as the pages do (the server stores nothing else)
        with sync_playwright() as p:
            b = p.chromium.launch()
            ctx = b.new_context()
            ctx.request.post(cls.base + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': cls.base})
            pg = ctx.new_page()
            pg.goto(cls.base + '/learning.html')
            pg.wait_for_function("() => typeof K !== 'undefined' && K.me")
            cls.jxl = pg.evaluate("""() => { const c = document.createElement('canvas'); c.width = 64; c.height = 48;
                const g = c.getContext('2d'); g.fillStyle = '#3c5a96'; g.fillRect(0, 0, 64, 48); return K.jxlEncode(c, 1.9, 3) }""")
            b.close()
        assert boss.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': KKS, 'caption': NAME, 'dataUrl': cls.jxl}}).get('status') == 'approved'
        # tom's change to the tag stays pending: index.html shows it under "Your changes, not live yet"
        assert cls.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': KKS, 'changes': {'near': EVIL}, 'base': {}}}).get('status') == 'pending'

    @classmethod
    def account(cls, username, role):
        link = cls.boss.req('POST', '/api/users', {'username': username, 'full_name': NAME, 'position': NAME, 'role': role})['link']
        c = Client(cls.base)
        assert c.req('POST', '/api/password-reset', {'token': link.split('#reset=')[1], 'password': PW}).get('ok')
        return c

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    # ---------------------------------------------------------------- helpers
    def clean(self, page, where):
        """nothing of NAME or EVIL became an element, and none of their script ran"""
        page.wait_for_timeout(300)   # (an <img onerror> fires once the image has failed to load)
        self.assertEqual(page.locator('#injected').count(), 0, where)
        self.assertEqual(page.evaluate("[...document.scripts].filter(s => s.textContent.includes('pwned')).length"), 0, where)
        self.assertFalse(page.evaluate('!!window.pwned'), where)

    def text(self, page, sel):
        return page.locator(sel).first.text_content()

    def context(self, p, name, user):
        browser = getattr(p, name).launch()
        # (no service worker: it would answer the data files and /api/update itself, and page.route sees no request)
        ctx = browser.new_context(viewport={'width': 1300, 'height': 900}, service_workers='block')
        ctx.add_init_script(CSP_WATCH)
        r = ctx.request.post(self.base + '/api/login', data={'username': user, 'password': PW}, headers={'Origin': self.base})
        self.assertTrue(r.ok, r.text())
        page = ctx.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        # confirm() is accepted; prompt() (a rejection's reason) gets a hostile answer
        page.on('dialog', lambda d: d.accept(NAME) if d.type == 'prompt' else d.accept())
        return browser, page, errors

    def proposals(self, n):
        """tom's proposals for this engine's own equipment (a fresh one per engine: approvals change state)"""
        k = '11LAB70AA51%d' % n
        tom = self.tom
        self.assertEqual(tom.req('POST', '/api/submit', {'kind': 'equipment', 'note': EVIL, 'payload': {'kks': k,
                         'changes': {'notes': EVIL, 'custom': [{'k': NAME, 'v': EVIL}]}, 'base': {}}})['status'], 'pending')
        self.assertEqual(tom.req('POST', '/api/submit', {'kind': 'photo', 'note': EVIL, 'payload': {'kks': k, 'caption': EVIL,
                         'dataUrl': self.jxl}})['status'], 'pending')
        self.assertEqual(tom.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [100 + 10 * n, 100, 200, 150],
                         'kks': '', 'isa': 'PI', 'note': EVIL}})['status'], 'pending')
        self.assertEqual(tom.req('POST', '/api/submit', {'kind': 'link', 'payload': {'proc': 'EP-9', 'step': 2, 'kks': k, 'on': True}})['status'], 'pending')
        return k

    # ---------------------------------------------------------------- admin.html
    def admin(self, p, name, n):
        k = self.proposals(n)
        browser, page, errors = self.context(p, name, 'boss')
        # an update offer whose release page is a javascript: URL and whose texts are markup (the update check's data)
        page.route('**/api/update', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(
            {'current': EVIL, 'latest': EVIL, 'available': True, 'page': 'javascript:window.pwned=9', 'notes': EVIL,
             'can_install': False, 'how': 'git', 'checked': 0, 'auto': True, 'error': EVIL})))
        page.goto(self.base + '/admin.html#queue')
        page.wait_for_selector('#main .card')
        self.clean(page, name + ' approvals')
        self.assertEqual(page.text_content('#who'), NAME + ' · manager')
        # tom's equipment proposal: who, the request note, every field as text
        card = page.locator('#main .card', has=page.locator('h3', has_text='equipment:' + k))
        self.assertIn(f'{NAME} (tom)', card.text_content())
        self.assertEqual(card.locator('.rnote').text_content(), f'“{EVIL}”')
        self.assertEqual(card.locator('td').nth(0).text_content(), 'notes')
        self.assertIn(EVIL, card.locator('table').text_content())
        self.assertIn(f'{NAME}: {EVIL}', card.locator('table').text_content())
        self.assertEqual(card.locator('.sub', has_text='(empty)').count(), 2)
        # the photo proposal: caption and request note as text, the photo shown from the server
        ph = page.locator('#main .card', has=page.locator('h3', has_text='Photo proposals · ' + k))
        self.assertIn(EVIL, ph.locator('figure').text_content())
        self.assertRegex(ph.locator('img').get_attribute('src'), r'^(photos/|blob:)')   # (blob: once K.jxl decoded it)
        # the marked tag: note as text, the codes in their fields, a link to the sheet
        tags = page.locator('#main .card', has=page.locator('h3', has_text='tag_add:sample'))
        self.assertIn('Note: ' + EVIL, tags.text_content())
        self.assertIn('PI', [tags.locator('input.mono').nth(i).input_value() for i in range(tags.locator('input.mono').count())])
        self.assertEqual(tags.locator('a.sub').first.get_attribute('href'), '/?sheet=sample')
        # the link proposal
        self.assertIn(f'link {k} to procedure EP-9 step 2', page.text_content('#main'))
        # approve the equipment proposal, reject the photo with a hostile reason (prompt)
        card.get_by_role('button', name='Approve').click()
        page.wait_for_function("t => ![...document.querySelectorAll('#main .card h3')].some(h => h.textContent === t)", arg='equipment:' + k)
        ph = page.locator('#main .card', has=page.locator('h3', has_text='Photo proposals · ' + k))
        ph.get_by_role('button', name='Reject').click()
        page.wait_for_function("t => ![...document.querySelectorAll('#main .card h3')].some(h => h.textContent === t)", arg='Photo proposals · ' + k)
        self.clean(page, name + ' after deciding')

        # history: the approved change, field by field, as text
        page.locator('#tabs button', has_text='History').click()
        page.wait_for_selector('#main table tr:nth-child(2)')
        row = page.locator('#main tr', has_text=k + ':').first
        self.assertIn(f'notes (empty) → {EVIL}', row.text_content())
        self.assertIn(NAME, row.text_content())   # who: the manager's name
        self.assertEqual(row.get_by_role('button').count(), 2)   # Revert, Restore to here
        self.clean(page, name + ' history')

        # users: names and positions as text; a password link for tom; a new account from the form (Enter submits)
        page.locator('#tabs button', has_text='Users').click()
        page.wait_for_selector('#main table')
        trow = page.locator('#main tr', has=page.locator('td.mono', has_text='tom'))
        self.assertEqual(trow.locator('td').first.text_content(), NAME + NAME)
        trow.get_by_role('button', name='Password link').click()
        page.wait_for_selector('#main > .warn')
        self.assertIn('Password link for tom', page.text_content('#main > .warn'))
        page.fill('#main form.inline input[name=full_name]', NAME)
        page.fill('#main form.inline input[name=username]', 'u' + name)
        page.press('#main form.inline input[name=username]', 'Enter')
        page.wait_for_selector('#newlink .linkbox')
        self.assertIn('Give this link to u' + name, page.text_content('#newlink'))
        self.clean(page, name + ' users')

        # devices: the plant's name saved from its form; the invite QR reached with Tab and opened with Enter
        page.locator('#tabs button', has_text='Devices').click()
        field = page.get_by_role('textbox', name='Plant name')
        field.fill(NAME)
        field.press('Enter')
        page.wait_for_function("t => document.title === t", arg=NAME + ' — Walkdown')
        self.assertEqual(page.text_content('#main .card h3 >> nth=0'), 'Your devices')
        page.wait_for_function("() => document.getElementById('lobby').textContent === 'Nobody is waiting.'")
        page.get_by_text('Export with photos').focus()
        page.keyboard.press('Tab')
        self.assertEqual(page.evaluate('document.activeElement.textContent'), 'Show QR code')
        page.keyboard.press('Enter')
        page.wait_for_selector('#invite svg[aria-label="Invite QR code"] path', state='attached')
        self.assertIn('kks_invite', page.input_value('#invite textarea'))
        self.assertIn(f'Plant {NAME} · reachable at', page.text_content('#invite'))
        page.locator('#invite').get_by_role('button', name='Cancel').click()
        page.wait_for_selector('#invite > button')
        # syncing with an address is for admins (#32); "Sync now" without one is a device's round, not the server's
        self.assertEqual(page.get_by_role('button', name='Sync with it').count(), 1)
        self.assertEqual(page.get_by_role('button', name='Sync now').count(), 0)
        tb, tpage, _ = self.context(p, name, 'tom')
        tpage.goto(self.base + '/admin.html#devices')
        tpage.wait_for_selector('#main .card h3')
        self.assertEqual(tpage.get_by_role('button', name='Sync with it').count(), 0)
        tb.close()
        self.assertEqual(page.text_content('#invite > button'), 'Show QR code')
        self.clean(page, name + ' devices')
        ctxreq = page.context.request
        ctxreq.post(self.base + '/api/settings/plant', data={'name': 'Test plant'}, headers={'Origin': self.base})

        # drawings: the sheet's name as text in the list and in the last import job; the links stay in the app
        page.locator('#tabs button', has_text='Drawings').click()
        page.wait_for_selector('#job .card')
        self.assertIn(f'Import finished · {NAME} (sample)', page.text_content('#job h3'))
        row = page.locator('#main table tr', has=page.locator('td.mono', has_text='sample'))
        self.assertEqual(row.locator('td').first.evaluate('td => td.firstChild.textContent'), NAME)
        self.assertEqual(row.get_by_text('Open').get_attribute('href'), '/?sheet=sample')
        self.assertEqual(page.locator('#job a').get_attribute('href'), '/?sheet=sample')
        self.assertEqual(row.locator('select').input_value(), 'auto')
        self.clean(page, name + ' drawings')

        # account: the pending hand-over; the update's texts as text and its javascript: page link neutralised
        page.locator('#tabs button', has_text='Account').click()
        page.wait_for_selector('#upd .card')
        self.assertIn('Offered to ann, waiting', page.text_content('#main'))
        self.assertEqual(page.input_value('#main input[name=full_name]'), NAME)
        upd = page.text_content('#upd')
        self.assertIn(f'This is version {EVIL}.', upd)
        self.assertIn(f'Version {EVIL} is out.', upd)
        self.assertIn(f'Last check: {EVIL}', upd)
        self.assertEqual(page.get_attribute('#upd a', 'href'), 'about:blank')
        self.clean(page, name + ' account')

        # my submissions: tom's photo proposals to vote on (the kks and who), the manager's own changes
        page.locator('#tabs button', has_text='My submissions').click()
        page.wait_for_selector('#main table')
        self.assertGreaterEqual(page.locator('#main tr').count(), 2)
        self.clean(page, name + ' mine')
        browser.close()
        self.assertEqual(errors, [], name)

    # ---------------------------------------------------------------- index.html (as tom)
    def viewer(self, p, name):
        browser, page, errors = self.context(p, name, 'tom')
        # a published operation manual, a location list and markup notes on the sheet, all with markup in them
        page.route('**/data/procedures.json', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(
            [{'id': 'EP-1', 'title': EVIL, 'path': [NAME], 'page': 3, 'steps': [{'n': 1, 'text': EVIL}, {'n': 2, 'text': NAME}]}])))
        page.route('**/data/locations.json', lambda r: r.fulfill(status=200, content_type='application/json', body=json.dumps(
            {'source': NAME, 'entries': [{'kks': KKS[2:], 'level': EVIL, 'cabinet': NAME, 'desc': EVIL, 'direction': NAME, 'page': 4},
                                         {'kks': 'LBA10AA001', 'level': '14 m', 'cabinet': NAME, 'desc': EVIL, 'direction': '', 'page': 5}]})))

        def sheets(route):
            r = route.fetch()
            s = r.json()
            s[0]['notes'] = [EVIL, NAME]
            route.fulfill(response=r, body=json.dumps(s))
        page.route('**/data/sheets.json*', sheets)
        page.goto(self.base + '/?kks=' + KKS)
        page.wait_for_function("k => typeof selTag !== 'undefined' && selTag && full(selTag) === k", arg=KKS, timeout=30000)
        self.clean(page, name + ' panel')
        P = '#panelBody'
        self.assertEqual(self.text(page, P + ' .phead .kks'), KKS)
        # tom's change, not live yet
        self.assertIn('Your changes, not live yet', page.text_content('#pendingSec'))
        self.assertIn(f'near → {EVIL}', page.text_content('#pendingSec'))
        # the location list, the manager's fields, the custom field, the photo's caption, the sheet chip, the hand mark
        loc = page.locator(P + ' .sec', has=page.locator('h3', has_text='Location list'))
        self.assertIn(EVIL, loc.text_content())
        self.assertIn(f'{NAME}, page 4', loc.text_content())
        self.assertEqual(page.input_value('#f_area'), NAME)
        self.assertEqual(page.input_value('#f_notes'), EVIL)
        self.assertEqual(page.input_value('#f_near'), EVIL)   # (your pending value is shown)
        self.assertEqual([page.locator('#cfs .cf input').nth(i).input_value() for i in range(2)], [NAME, EVIL])
        self.assertEqual(page.get_attribute(P + ' .photos img', 'alt'), NAME)
        self.assertIn(NAME, page.locator(P + ' .sec', has=page.locator('h3', has_text='Appears on')).text_content())
        self.assertIn('Note: ' + EVIL, page.locator(P + ' .sec', has=page.locator('h3', has_text='Added by hand')).text_content())
        self.assertIn('EP-1 ' + EVIL, page.locator(P + ' .sec', has=page.locator('h3', has_text='Used in procedures')).text_content())
        # keyboard: Tab from the field to its ✎ button, Enter unlocks the field and shows Save
        page.focus('#f_area')
        page.keyboard.press('Tab')
        self.assertEqual(page.evaluate('document.activeElement.getAttribute("aria-label")'), 'Edit Building / area')
        page.keyboard.press('Enter')
        self.assertFalse(page.evaluate("document.getElementById('f_area').readOnly"))
        self.assertTrue(page.is_visible('#eqSave'))
        # a custom field added (+ Custom field), then removed with its ×
        page.locator(P).get_by_role('button', name='Edit custom fields').click()
        page.locator('#cfAdd').click()
        self.assertEqual(page.locator('#cfs .cf').count(), 2)
        page.locator('#cfs .cf >> nth=1').locator('button.x').click()
        self.assertEqual(page.locator('#cfs .cf').count(), 1)
        page.locator(P).get_by_role('button', name='Cancel').click()
        self.clean(page, name + ' panel edit')

        # the sheet list and the search results: the sheet's name, the area and the location list as text
        self.assertEqual(page.locator('#sheetSel option').first.text_content(), NAME)
        page.fill('#q', 'injected')
        page.wait_for_selector('#results [role=option]')
        res = page.text_content('#results')
        self.assertIn(KKS, res)
        self.assertIn(NAME, res)
        self.assertIn('LBA10AA001 location list only', res)
        self.clean(page, name + ' search')
        page.locator('#results [role=option]', has_text='LBA10AA001').click()   # a code only in the location list
        page.wait_for_selector(P + ' .warn')
        self.assertEqual(self.text(page, P + ' .phead .kks'), 'LBA10AA001')
        self.assertIn(EVIL, page.text_content(P))
        self.clean(page, name + ' location only')

        # procedures: the list, then one procedure's steps, its linked equipment and the sheet chip
        page.click('#procBtn')
        page.wait_for_selector('#procBody .proc')
        self.assertEqual(page.text_content('#procBody .chapter'), NAME)
        self.assertIn(EVIL, page.text_content('#procBody .proc'))
        page.click('#procBody .proc')
        page.wait_for_selector('#procBody .step')
        body = page.text_content('#procBody')
        self.assertIn(f'EP-1 {EVIL}', body)
        self.assertIn(f'{NAME} · manual page 3', body)
        self.assertIn(f'Linked equipment on: {NAME} (1)', body)
        self.assertIn('1)' + EVIL, body)
        self.assertEqual(page.locator('#procBody .step >> nth=0').locator('.chip.mono').text_content(), KKS)
        self.assertEqual(page.locator('#procBody .step >> nth=0').get_by_role('button', name='Unlink ' + KKS).count(), 1)
        page.locator('#procBody').get_by_role('button', name='← All procedures').click()
        page.wait_for_selector('#procBody .proc')
        self.clean(page, name + ' procedures')

        # the review queue (the tag marked without a code), the sheet's markup notes, the missed-tag form
        page.click('#revBtn')
        page.wait_for_selector('#revBody .revitem')
        self.assertIn(NAME, page.text_content('#revBody .chapter'))
        page.click('#notesBtn')
        self.assertEqual([page.locator('#notesBody .step').nth(i).text_content() for i in range(2)], [EVIL, NAME])
        page.evaluate('markForm([10, 10, 60, 40])')
        self.assertEqual(self.text(page, P + ' .phead .sub'), NAME)
        self.clean(page, name + ' drawers')
        browser.close()
        self.assertEqual(errors, [], name)

    def run_engine(self, name, n):
        with sync_playwright() as p:
            self.admin(p, name, n)
            self.viewer(p, name)

    def test_chromium(self): self.run_engine('chromium', 1)
    def test_firefox(self): self.run_engine('firefox', 2)
    def test_webkit(self): self.run_engine('webkit', 3)


if __name__ == '__main__':
    unittest.main()
