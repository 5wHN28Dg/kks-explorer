"""index.html's "Select tags" mode in all three engines, against the Nim server (core api.submitMany behind
/api/submit-many) with a small synthetic plant published through `kks-server publish-data`: two tags picked by click and
two by a dragged box, a tag without a code refused, Space / Enter on a focused tag, one code unticked in the List dialog;
"Place for all" with a floor (the warning about a floor it replaces first) gives exactly those codes that floor in
/api/submissions; "Note for all" appends under an existing note; "Photo for all" (the mark-up editor, JPEG XL encoded in
the browser) gives one photo entry per code, all sharing one file, and asks for the floor first when a code has none
(sent with the photo: core submitMany writes it for those codes only). As a MEMBER (test_member_*): codes from another
drawing join the selection from the search and from codes typed in the List dialog, the selection survives a change of
drawing, and Photo for all with the floor asked first gives every code the photo and each code without a floor a floor
proposal, online and queued offline. A fresh server per engine.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_multi.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (default /tmp/kks-web-shots)."""
import json, os, re, shutil, struct, subprocess, tempfile, unittest, urllib.request, http.cookiejar, zlib
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-web-shots')


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


def png(w, h, rgb=b'\xff\xff\xff'):
    raw = b''.join(b'\0' + rgb * w for _ in range(h))
    chunk = lambda t, d: struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) + \
        chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')


def tag(i, kks, x, suffix='', isa=None, status='auto'):
    return {'id': i, 'sheet': i.split(':')[0], 'kks': kks, 'suffix': suffix, 'isa': isa, 'kind': 'instrument' if isa else 'equipment',
            'status': status, 'conf': 0.9, 'bbox': [x, 100, x + 60, 130], 'read': ['?', '?']}


SHEETS = [{'id': 'a', 'name': 'Sheet A', 'w': 1000, 'h': 600, 'file': 'data/sheets/a.png', 'notes': []},
          {'id': 'b', 'name': 'Sheet B', 'w': 1000, 'h': 600, 'file': 'data/sheets/b.png', 'notes': []}]
TAGS = [tag('a:1', '11LAB70AA501', 50), tag('a:2', '11HAD70CT101', 150, 'R', 'TIAC'), tag('a:3', None, 250, status='review'),
        tag('a:4', '11LAB70AA503', 350), tag('a:5', '12LBA10AA101', 450), tag('a:6', '11LAB71AP001', 650),
        tag('a:7', '11LAB72AP002', 800),
        # another drawing: two codes of its own, and one that is on Sheet A too
        tag('b:1', '12LBA20AA101', 50), tag('b:2', '12LBA20AA102', 150), tag('b:3', '11LAB70AA501', 250)]
PW = 'a long password'



class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + p, data=data, method=m,
                                   headers=({'Content-Type': 'application/json'} if data is not None else {}) | {'Origin': self.base})
        with self.op.open(r) as resp: return json.loads(resp.read())


class WebMulti(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-web-multi-')
        self.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': self.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups')}
        self.cfg = os.path.join(self.dir, 'config.json')
        with open(self.cfg, 'w') as f: json.dump(cfg, f)
        self.log = open(os.path.join(self.dir, 'server.log'), 'w+')
        self.server = subprocess.Popen([SERVER, 'serve', '--config', self.cfg], cwd=self.dir, stdout=self.log,
                                       stderr=subprocess.STDOUT, text=True)
        self.addCleanup(self.stop)   # runs even when setUp fails below (tearDown doesn't: it left servers running)
        setup = None
        for _ in range(100):
            self.log.flush(); self.log.seek(0); out = self.log.read()
            f = re.search(r'setup link file: (.+)', out)   # the link is in a 0600 file (#69)
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(f[1].strip()).read()) if f else None
            if m: setup = m[1]
            if 'server on' in out and setup: break
            import time; time.sleep(0.1)
        self.base = 'http://127.0.0.1:%d' % self.port
        self.boss = Client(self.base)
        assert self.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                    'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        d = os.path.join(self.dir, 'fixture')
        os.makedirs(os.path.join(d, 'sheets'))
        for name, obj in (('sheets.json', SHEETS), ('tags.json', TAGS)):
            with open(os.path.join(d, name), 'w') as f: json.dump(obj, f)
        for n in 'ab':
            with open(os.path.join(d, 'sheets', n + '.png'), 'wb') as f: f.write(png(100, 60))
        r = subprocess.run([SERVER, 'publish-data', d, '--config', self.cfg], cwd=self.dir, capture_output=True, text=True, timeout=60)
        assert r.returncode == 0, r.stdout + r.stderr
        # what is there before: a note on AA501, a floor on AA503 (Place for all says it replaces it)
        for k, ch in (('11LAB70AA501', {'notes': 'old note'}), ('11LAB70AA503', {'floor': '3'})):
            assert self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': ch, 'base': {f: '' for f in ch}}}).get('status') == 'approved'
        self.photo = os.path.join(self.dir, 'photo.png')
        with open(self.photo, 'wb') as f: f.write(png(160, 120, b'\x30\x80\xc0'))
        os.makedirs(SHOTS, exist_ok=True)

    def stop(self):
        self.server.terminate()
        self.server.wait(5)
        self.log.close()
        shutil.rmtree(self.dir, ignore_errors=True)

    def subs(self, kind):
        return [s for s in self.boss.req('GET', '/api/submissions?status=all')['submissions'] if s['kind'] == kind]

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
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length === 10 && typeof cur !== 'undefined' && cur", timeout=30000)
            hs = lambda i: page.locator(f'#layer .hs[data-id="{i}"]')
            count = lambda: page.text_content('#pickCount')
            picked = lambda: page.evaluate("[...document.querySelectorAll('#layer .hs.picked')].map(e => e.dataset.id)")
            toast = lambda text: page.wait_for_function("t => document.getElementById('toast').textContent.startsWith(t)", arg=text, timeout=30000)
            # outside the mode the tags are buttons out of the tab order
            self.assertEqual(hs('a:1').get_attribute('tabindex'), '-1')
            btn = page.get_by_role('button', name='Select tags')
            self.assertEqual(btn.get_attribute('aria-pressed'), 'false')
            btn.click()
            self.assertEqual(btn.get_attribute('aria-pressed'), 'true')
            self.assertTrue(page.is_visible('#pickbar'))
            self.assertEqual(page.get_attribute('#pickCount', 'aria-live'), 'polite')
            self.assertEqual(count(), '0 selected')
            # two by click; the panel doesn't open
            hs('a:1').click()
            hs('a:2').click()
            self.assertEqual(count(), '2 selected')
            self.assertFalse(page.is_visible('#panel'))
            self.assertEqual(hs('a:2').get_attribute('aria-pressed'), 'true')
            # a sync redraws the tags at any moment: a press and a release around a redraw still click the tag, whose
            # button is the same one (it was replaced: the click was lost, and the test's own measurements of a tag
            # came back empty, run 37893946756)
            a6 = hs('a:6').element_handle()
            b6 = a6.bounding_box()
            page.mouse.move(b6['x'] + b6['width'] / 2, b6['y'] + b6['height'] / 2)
            page.mouse.down()
            # (with something to remove ahead of the tags: the redraw removes it, and moves none of them)
            page.evaluate("() => { document.getElementById('layer').prepend(document.createElement('i')); drawTags() }")
            page.mouse.up()
            self.assertEqual(count(), '3 selected')
            self.assertTrue(a6.evaluate("e => e.isConnected"))
            self.assertEqual(a6.get_attribute('aria-pressed'), 'true')
            hs('a:6').click()
            self.assertEqual(count(), '2 selected')
            # a tag without a code: refused, said once
            hs('a:3').click()
            toast("Tags without a code can't be selected")
            self.assertEqual(count(), '2 selected')
            # a dragged box from above-left of a:4 to below-right of a:5 adds both (and passes over no other)
            # (a sync can redraw the tags between finding one and measuring it: measured again until both are there)
            for _ in range(50):
                b4, b5 = hs('a:4').bounding_box(), hs('a:5').bounding_box()
                if b4 and b5: break
                page.wait_for_timeout(100)
            page.mouse.move(b4['x'] - 4, b4['y'] - 15)
            page.mouse.down()
            page.mouse.move((b4['x'] + b5['x']) / 2, b5['y'], steps=4)
            page.mouse.move(b5['x'] + b5['width'] - 6, b5['y'] + b5['height'] + 10, steps=4)
            self.assertTrue(page.is_visible('#selbox'))
            page.evaluate("() => drawTags()")      # a sync redraws the tags mid-drag: the box stays
            self.assertTrue(page.is_visible('#selbox'))
            page.mouse.up()
            self.assertFalse(page.is_visible('#selbox'))
            self.assertEqual(count(), '4 selected')
            self.assertEqual(sorted(picked()), ['a:1', 'a:2', 'a:4', 'a:5'])
            page.screenshot(path=os.path.join(SHOTS, 'multi-' + name + '.png'))
            # keyboard: Tab reaches the tags in the mode; Space and Enter toggle the focused one
            self.assertEqual(hs('a:1').get_attribute('tabindex'), '0')
            hs('a:1').focus()
            page.keyboard.press('Space')
            self.assertEqual(count(), '3 selected')
            self.assertEqual(hs('a:1').get_attribute('aria-pressed'), 'false')
            self.assertEqual(page.evaluate("document.activeElement.dataset.id"), 'a:1')
            page.keyboard.press('Enter')
            self.assertEqual(count(), '4 selected')
            # at most 200 (the server's limit per submit-many): a 201st tag isn't added, and that is said
            saved = page.evaluate("() => { const s = [...multi.codes]; multi.codes = Array.from({length: 200}, (_, i) => '11LAB70AA' + (700 + i)); updatePick(); return s }")
            hs('a:1').click()
            toast('At most 200 tags at once')
            self.assertEqual(count(), '200 selected')
            page.evaluate("s => { multi.codes = s; updatePick() }", saved)
            self.assertEqual(count(), '4 selected')
            # the List: untick 12LBA10AA101
            page.click('#pickList')
            dlg = page.locator('dialog[open]')
            self.assertEqual(dlg.locator('input[type=checkbox]').count(), 4)
            dlg.get_by_role('checkbox', name=re.compile('12LBA10AA101')).uncheck()
            self.assertEqual(count(), '3 selected')
            self.assertNotIn('a:5', picked())
            dlg.get_by_role('button', name='Close').click()
            self.assertEqual(page.locator('dialog[open]').count(), 0)
            # Place for all: floor 5; AA503's floor 3 is replaced (said before sending: the second press sends)
            page.click('#pickPlace')
            dlg = page.locator('dialog[open]')
            dlg.get_by_label('Floor').fill('5')
            self.assertIn('1 of 3 codes already has a floor; it will be replaced.', dlg.locator('.warn').text_content())
            dlg.locator('[data-send]').click()
            self.assertEqual(dlg.locator('[data-send]').text_content(), 'Replace and send')
            self.assertEqual(self.subs('equipment').__len__(), 2)   # nothing sent yet (the two set up)
            dlg.locator('[data-send]').click()
            toast('Sent for 3 codes')
            self.assertEqual(btn.get_attribute('aria-pressed'), 'false')   # sending leaves the mode
            floors = {s['payload']['kks']: s['payload']['changes'].get('floor') for s in self.subs('equipment')
                      if 'floor' in s['payload'].get('changes', {}) and s['payload']['changes']['floor'] == '5'}
            self.assertEqual(floors, {'11LAB70AA501': '5', '11HAD70CT101R': '5', '11LAB70AA503': '5'})
            st = self.boss.req('GET', '/api/state')['equipment']
            self.assertEqual(st['11LAB70AA503']['floor'], '5')
            self.assertNotIn('floor', st.get('12LBA10AA101', {}))
            # Note for all: added under the note already there
            btn.click()
            hs('a:1').click()
            hs('a:5').click()
            page.evaluate("document.getElementById('toast').textContent = ''")
            page.click('#pickNote')
            dlg = page.locator('dialog[open]')
            dlg.get_by_label('Note', exact=True).fill('checked on the walkdown')
            dlg.locator('[data-send]').click()
            toast('Sent for 2 codes')
            st = self.boss.req('GET', '/api/state')['equipment']
            self.assertEqual(st['11LAB70AA501']['notes'], 'old note\nchecked on the walkdown')
            self.assertEqual(st['12LBA10AA101']['notes'], 'checked on the walkdown')
            # Photo for all: the mark-up editor, JPEG XL in the browser, one file for both codes
            btn.click()
            hs('a:4').click()
            hs('a:6').click()
            # a photo needs each code's floor: 11LAB71AP001 has none, so Photo for all asks for it first (the photo
            # can't be chosen before) and says which code it is for; AA503 keeps its floor 5
            page.click('#pickPhoto')
            dlg = page.locator('dialog[open]')
            self.assertEqual(dlg.locator('#dlgFloorLabel').text_content(),
                             'Floor for 11LAB71AP001: this one has none yet; the others keep theirs')
            self.assertFalse(dlg.locator('#dlgChoose').is_visible())
            dlg.locator('#dlgFloor').fill('11')
            self.assertFalse(dlg.locator('#dlgChoose').is_visible())
            dlg.locator('#dlgFloor').fill('2')
            self.assertTrue(dlg.locator('#dlgChoose').is_visible())
            dlg.get_by_label('Caption (optional)').fill('Tag plate · both')
            page.evaluate("document.getElementById('toast').textContent = ''")   # the note's toast may still show
            dlg.locator('#dlgFile').set_input_files(self.photo)
            page.locator('button[data-a="ok"]').click(timeout=15000)
            toast('Sent for 2 codes')
            allp = self.boss.req('GET', '/api/state')['photos']
            photos = [x for x in allp if x.get('caption') == 'Tag plate · both']
            self.assertEqual(sorted(x['kks'] for x in photos), ['11LAB70AA503', '11LAB71AP001'])
            self.assertEqual(len({x['file'] for x in photos}), 1, photos)
            self.assertEqual(len({x['id'] for x in photos}), 2)
            self.assertTrue(photos[0]['file'].endswith('.jxl'), photos[0])
            st = self.boss.req('GET', '/api/state')['equipment']
            self.assertEqual((st['11LAB71AP001']['floor'], st['11LAB70AA503']['floor']), ('2', '5'))
            # every code has a floor now: Photo for all asks for none
            btn.click()
            hs('a:4').click()
            hs('a:6').click()
            page.click('#pickPhoto')
            self.assertEqual(page.locator('dialog[open] #dlgFloor').count(), 0)
            self.assertTrue(page.locator('dialog[open] #dlgChoose').is_visible())
            page.locator('dialog[open]').get_by_role('button', name='Cancel').click()
            page.click('#pickDone')
            self.assertEqual(btn.get_attribute('aria-pressed'), 'false')
            # the tags show it: a tag plate photo only (blue) once colouring by photos is on
            page.click('#zcover')
            # (a predicate as a function: Playwright evaluates an expression again at every poll, which the page's
            # Content-Security-Policy refuses, so it failed whenever the first check came too early)
            page.wait_for_function("() => document.querySelector('#layer .hs[data-id=\"a:6\"]').classList.contains('p-plate')")
            # offline: queued like K.submit, shown per code, sent by the outbox's flush (the prefix dedupes a retry)
            btn.click()
            hs('a:6').click()
            page.click('#pickNote')
            page.locator('dialog[open]').get_by_label('Note', exact=True).fill('noted offline')
            page.evaluate("document.getElementById('toast').textContent = ''")
            ctx.set_offline(True)
            page.locator('dialog[open] [data-send]').click()
            toast('Offline, queued for 1 code')
            self.assertEqual(page.evaluate("K.outbox.map(i => [i.kind, i.payload.kks, K.describe(i.kind, i.payload)])"),
                             [['equipment', '11LAB71AP001', 'notes + noted offline']])
            ctx.set_offline(False)
            page.evaluate("K.flush()")
            page.wait_for_function("() => K.outbox.length === 0", timeout=15000)
            self.assertEqual(self.boss.req('GET', '/api/state')['equipment']['11LAB71AP001']['notes'], 'noted offline')
            # a finger drags a box too (synthetic touch pointer events, as the engines get them from a touch screen)
            btn.click()
            for _ in range(50):
                b1, b2 = hs('a:1').bounding_box(), hs('a:2').bounding_box()
                if b1 and b2: break
                page.wait_for_timeout(100)
            page.evaluate("""([x0, y0, x1, y1]) => {
              const ev = (type, x, y) => (document.elementFromPoint(x, y) || document.getElementById('viewer')).dispatchEvent(
                new PointerEvent(type, {bubbles: true, cancelable: true, pointerId: 7, pointerType: 'touch', isPrimary: true,
                                        button: type === 'pointermove' ? -1 : 0, buttons: type === 'pointerup' ? 0 : 1, clientX: x, clientY: y}));
              ev('pointerdown', x0, y0);
              for (let i = 1; i <= 5; i++) ev('pointermove', x0 + (x1 - x0) * i / 5, y0 + (y1 - y0) * i / 5);
              ev('pointerup', x1, y1) }""", [b1['x'] - 4, b1['y'] - 15, b2['x'] + 10, b2['y'] + b2['height'] + 10])
            self.assertEqual(count(), '2 selected')
            self.assertEqual(sorted(picked()), ['a:1', 'a:2'])
            # Escape leaves the mode
            page.keyboard.press('Escape')
            self.assertEqual(btn.get_attribute('aria-pressed'), 'false')
            self.assertFalse(page.is_visible('#pickbar'))
            self.assertEqual(picked(), [])
            browser.close()
            self.assertEqual(errors, [], name)

    def run_member(self, name):
        """a member (their changes wait for approval): codes from two drawings, the floor asked with the photo"""
        link = self.boss.req('POST', '/api/users', {'username': 'tom', 'full_name': 'Tom Tech', 'position': 'Technician', 'role': 'user'})['link']
        assert Client(self.base).req('POST', '/api/password-reset', {'token': link.split('#reset=')[1], 'password': PW}).get('ok')
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1200, 'height': 800})
            r = ctx.request.post(self.base + '/api/login', data={'username': 'tom', 'password': PW}, headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length === 10 && typeof cur !== 'undefined' && cur", timeout=30000)
            hs = lambda i: page.locator(f'#layer .hs[data-id="{i}"]')
            count = lambda: page.text_content('#pickCount')
            toast = lambda text: page.wait_for_function("t => document.getElementById('toast').textContent.startsWith(t)", arg=text, timeout=30000)
            clear_toast = lambda: page.evaluate("document.getElementById('toast').textContent = ''")
            btn = page.get_by_role('button', name='Select tags')
            self.assertEqual(page.evaluate("cur.id"), 'a')
            btn.click()
            hs('a:6').click()
            # a search result from another drawing joins the selection: the mode and the drawing stay
            page.fill('#q', '12LBA20AA101')
            page.locator('#results .res').first.click()
            toast('12LBA20AA101 selected (on Sheet B)')
            self.assertEqual(count(), '2 selected')
            self.assertEqual(btn.get_attribute('aria-pressed'), 'true')
            self.assertEqual(page.evaluate("cur.id"), 'a')
            self.assertFalse(page.is_visible('#panel'))
            # picked again: said, not added twice (and not removed)
            page.fill('#q', '12LBA20AA101')
            page.keyboard.press('Enter')
            toast('12LBA20AA101 is already selected')
            self.assertEqual(count(), '2 selected')
            # the selection survives a change of drawing: Sheet B rings its tag, Sheet A's again on the way back
            page.select_option('#sheetSel', 'b')
            page.wait_for_function("() => cur.id === 'b' && document.querySelector('#layer .hs[data-id=\"b:1\"]')?.classList.contains('picked')")
            self.assertEqual(count(), '2 selected')
            self.assertEqual(btn.get_attribute('aria-pressed'), 'true')
            hs('b:3').click()            # 11LAB70AA501, which is on Sheet A too
            self.assertEqual(count(), '3 selected')
            page.select_option('#sheetSel', 'a')
            page.wait_for_function("() => cur.id === 'a' && document.querySelector('#layer .hs[data-id=\"a:1\"]')?.classList.contains('picked')")
            self.assertTrue(page.evaluate("document.querySelector('#layer .hs[data-id=\"a:6\"]').classList.contains('picked')"))
            # the List: codes typed or pasted; one that is on no drawing is named and not added
            page.click('#pickList')
            dlg = page.locator('dialog[open]')
            self.assertIn('Sheet A, Sheet B', dlg.locator('li', has_text='11LAB70AA501').text_content())
            self.assertIn('Sheet B', dlg.locator('li', has_text='12LBA20AA101').text_content())
            self.assertNotIn('Sheet A', dlg.locator('li', has_text='12LBA20AA101').text_content())
            dlg.locator('#pickAddText').fill('12lba20aa102, 99XXX99XX999\n11LAB70AA503 11LAB71AP001')
            dlg.locator('#pickAddBtn').click()
            said = dlg.locator('#pickAddSaid').text_content()
            self.assertIn('Added 2 codes.', said)
            self.assertIn('Not on any drawing, not added: 99XXX99XX999.', said)
            self.assertEqual(count(), '5 selected')
            self.assertEqual(dlg.locator('input[type=checkbox]').count(), 5)
            self.assertIn('Sheet B', dlg.locator('li', has_text='12LBA20AA102').text_content())
            self.assertEqual(dlg.locator('#pickAddText').input_value(), '99XXX99XX999')
            # the limit holds for typed codes too
            saved = page.evaluate("() => { const s = [...multi.codes]; multi.codes = Array.from({length: 200}, (_, i) => '11LAB70AA' + (700 + i)); return s }")
            dlg.locator('#pickAddText').fill('11LAB72AP002')
            dlg.locator('#pickAddBtn').click()
            self.assertIn('At most 200 at once, not added: 11LAB72AP002.', dlg.locator('#pickAddSaid').text_content())
            page.evaluate("s => { multi.codes = s; updatePick() }", saved)
            dlg.get_by_role('button', name='Close').click()
            self.assertEqual(count(), '5 selected')
            page.screenshot(path=os.path.join(SHOTS, 'multi-member-' + name + '.png'))
            # Photo for all, as a member: the floor is asked first, for the four codes without one (AA503 has floor 3)
            page.click('#pickPhoto')
            dlg = page.locator('dialog[open]')
            self.assertEqual(dlg.locator('#dlgFloorLabel').text_content(),
                             'Floor for 11LAB71AP001, 12LBA20AA101, 11LAB70AA501, 12LBA20AA102: these have none yet; the others keep theirs')
            self.assertFalse(dlg.locator('#dlgChoose').is_visible())
            dlg.locator('#dlgFloor').fill('4')
            page.screenshot(path=os.path.join(SHOTS, 'multi-member-floor-' + name + '.png'))
            dlg.get_by_label('Caption (optional)').fill('same corner')
            clear_toast()
            dlg.locator('#dlgFile').set_input_files(self.photo)
            page.locator('button[data-a="ok"]').click(timeout=15000)
            toast('Sent for 5 codes · 5 await approval')
            five = ['11LAB70AA501', '11LAB70AA503', '11LAB71AP001', '12LBA20AA101', '12LBA20AA102']
            photos = [x for x in self.subs('photo') if x['payload'].get('caption') == 'same corner']
            self.assertEqual(sorted(x['payload']['kks'] for x in photos), five)
            self.assertEqual({x['status'] for x in photos}, {'pending'})
            self.assertEqual(len({x['payload']['file'] for x in photos}), 1)
            floors = {x['payload']['kks']: (x['payload']['changes'], x['status']) for x in self.subs('equipment')
                      if x.get('by') != 'boss' and x['status'] == 'pending'}
            self.assertEqual(floors, {k: ({'floor': '4'}, 'pending') for k in five if k != '11LAB70AA503'})
            # their own open proposals count as known: the next Photo for all for these codes asks for no floor
            page.wait_for_function("() => !multi.on && floorKnown('11LAB71AP001') && floorKnown('12LBA20AA102')", timeout=15000)
            btn.click()
            hs('a:6').click()
            page.click('#pickPhoto')
            self.assertEqual(page.locator('dialog[open] #dlgFloor').count(), 0)
            page.locator('dialog[open]').get_by_role('button', name='Cancel').click()
            # offline: the floor is queued with the photo, counts as known meanwhile, and is proposed when it is sent
            hs('a:6').click()
            hs('a:7').click()
            self.assertEqual(count(), '1 selected')
            page.click('#pickPhoto')
            dlg = page.locator('dialog[open]')
            self.assertEqual(dlg.locator('#dlgFloorLabel').text_content(), 'Floor for 11LAB72AP002: it has none yet')
            dlg.locator('#dlgFloor').fill('6')
            clear_toast()
            dlg.locator('#dlgFile').set_input_files(self.photo)
            page.locator('button[data-a="ok"]').wait_for(timeout=15000)
            ctx.set_offline(True)        # (once the editor is open: offline, Playwright's WebKit loads no blob: picture)
            page.locator('button[data-a="ok"]').click(timeout=15000)
            toast('Offline, queued for 1 code')
            self.assertEqual(page.evaluate("K.outbox.map(i => [i.kind, i.payload.kks, i.payload.floor])"), [['photo', '11LAB72AP002', '6']])
            self.assertTrue(page.evaluate("floorKnown('11LAB72AP002')"))
            self.assertEqual([x for x in self.subs('equipment') if x['payload']['kks'] == '11LAB72AP002'], [])
            ctx.set_offline(False)
            page.evaluate("K.flush()")
            page.wait_for_function("() => K.outbox.length === 0", timeout=15000)
            self.assertEqual([(x['payload']['changes'], x['status']) for x in self.subs('equipment') if x['payload']['kks'] == '11LAB72AP002'],
                             [({'floor': '6'}, 'pending')])
            self.assertEqual(len([x for x in self.subs('photo') if x['payload']['kks'] == '11LAB72AP002']), 1)
            browser.close()
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')
    def test_member_chromium(self): self.run_member('chromium')
    def test_member_firefox(self): self.run_member('firefox')
    def test_member_webkit(self): self.run_member('webkit')


if __name__ == '__main__':
    unittest.main()
