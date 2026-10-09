"""End-to-end: the Android app (v2, Nim core) on an emulator, against the Nim server on this machine. No plant data:
the drawing is importer/tests/vectors/kkp-sample.pdf. Driven through the accessibility tree (adbui.py).
  python3 android/app2/e2e/test_app2.py [APK] [SERVER] [IMPORTER]
Needs a running emulator (adb devices); the app's data is cleared first. The emulator reaches this machine as
10.0.2.2."""
import json, os, re, shutil, subprocess, sys, tempfile, time, unittest, urllib.error, urllib.request, http.cookiejar
sys.path.insert(0, os.path.dirname(__file__))
import adbui as ui  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
APK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'android/app2/build/outputs/apk/debug/app2-debug.apk')
SERVER = sys.argv[2] if len(sys.argv) > 2 else '/tmp/kkslinux/kks_server'
IMPORTER = sys.argv[3] if len(sys.argv) > 3 else '/tmp/kksimp/kks_import'
del sys.argv[1:4]     # what follows goes to unittest (e.g. Phone.test_flow)
PKG = 'io.github.walkdown'
# the emulator reaches this machine at 10.0.2.2; a real phone over USB uses `adb reverse` and 127.0.0.1
# (choose the phone with ANDROID_SERIAL; KKS_PHONE_HOST=127.0.0.1)
PHONE_HOST = os.environ.get('KKS_PHONE_HOST', '10.0.2.2')
SHOTS = os.environ.get('KKS_SHOTS', os.path.expanduser('~/kks-work/shots-android'))


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None, raw=None, ctype='application/json'):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        r = urllib.request.Request(self.base + p, data=data, method=m, headers={'Content-Type': ctype} if data is not None else {})
        try:
            with self.op.open(r) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as e:
            return {'status': e.code, 'error': e.read().decode()}


class Phone(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-app2-e2e-')
        cls.port, cls.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': cls.sport, 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
        cls.base = f'http://127.0.0.1:{cls.port}'
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f:
            pdf = f.read()
        assert cls.boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = cls.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        r = cls.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360],
                                                 'kks': '11LAB70AA501', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
        if PHONE_HOST == '127.0.0.1':
            ui.adb('reverse', f'tcp:{cls.sport}', f'tcp:{cls.sport}')
        # a fresh app
        subprocess.run(ui.ADB + ['uninstall', PKG], capture_output=True)   # a newer test build (test_update's 9.9.9) blocks -r
        r = subprocess.run(ui.ADB + ['install', '-t', APK], capture_output=True, text=True)
        assert 'Success' in r.stdout, 'install failed: ' + r.stdout + r.stderr
        ui.sh('pm', 'clear', PKG)
        ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')

    @classmethod
    def tearDownClass(cls):
        ui.sh('am', 'force-stop', PKG)
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def wait_server(self, cond, what, tries=40):
        for _ in range(tries):
            v = cond()
            if v:
                return v
            time.sleep(0.5)
        self.fail(what)

    # ---- helpers for the 2026-10-08 requests' tests
    def join(self, user='boss', pw='a long password'):
        ui.tap('Join through a server', exact=True)
        ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
        ui.type_into('Username', user)
        ui.type_into('Password', pw)
        ui.tap('Join', exact=True)
        ui.find('Sample sheet', timeout=40)

    def leave(self, user='boss'):
        """remove this phone's device on the server and start the app fresh (the next test joins again)"""
        model = ui.sh('getprop', 'ro.product.model').strip()
        for d in self.boss.req('GET', '/api/devices?show_hidden=1')['all']:
            if d['username'] == user and d['label'] == model and not d['revoked']:
                self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
        ui.sh('pm', 'clear', PKG)
        ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
        time.sleep(3)

    def member(self, username, full_name, pw):
        """a member with a password on the server (made once per test run)"""
        if not any(u['username'] == username for u in self.boss.req('GET', '/api/users?show_hidden=1')['users']):
            r = self.boss.req('POST', '/api/users', {'username': username, 'full_name': full_name, 'position': 'Technician', 'role': 'user'})
            Client(self.base).req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': pw})
        c = Client(self.base)
        c.req('POST', '/api/login', {'username': username, 'password': pw})
        return c

    @staticmethod
    def jxl(tag):
        """a stand-in photo: the JPEG XL signature (the server stores JXL only) and some bytes, a different blob per tag"""
        import base64
        return 'data:image/jxl;base64,' + base64.b64encode(b'\xff\x0a' + tag.encode() * 8).decode()

    def open_tag(self, code='11LAB70AA501'):
        ui.type_into('Search KKS or description', code[2:])
        ui.tap(code, exact=True)
        ui.find('Feed water piping system', timeout=10)

    def test_courses(self):
        """the JSON courses (decision 0036): Learning lists them; a course page; a figure as an image for TalkBack;
        a question answered (progress shown); an animated figure on screen"""
        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            ui.tap('Learning', exact=True)
            ui.find('0 of 76 questions solved', timeout=15)
            ui.tap('Rumaila Plant Foundations', exact=True)
            ui.tap('Contents', exact=True, timeout=15)
            ui.tap('1 · Combined cycle', exact=True)
            ui.scroll_to('The combined cycle. Combined cycle:', tries=20)
            ui.scroll_to('Once the gas cools below HP boiling temperature')
            ui.tap('Once the gas cools below HP boiling temperature')
            ui.find('Right.', exact=True, timeout=10)
            ui.find('1 of 76 solved', exact=True, timeout=10)
            ui.tap('Contents', exact=True)
            ui.scroll_to('6 · Valves & pumps', exact=True)
            ui.tap('6 · Valves & pumps', exact=True)
            ui.scroll_to('Gate valve cutaway. ', tries=30)
            time.sleep(1.5)
            with open('/tmp/kks-android-course.png', 'wb') as f:
                f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
        finally:
            # leave a fresh app and no extra device for test_flow
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)

    def test_multi(self):
        """one place and one note for several codes (/api/submit-many): Select tags from the ⋮ menu, two tags tapped
        and one taken by a box (hold, then drag), one unticked in the List; Place for all with a floor warns about the
        code that already has one, and the server gets a submission for exactly the codes left; Note for all appends"""
        for code, bb in (('11LAB70AA502', [1000, 300, 1120, 360]), ('11LAB70AA503', [400, 800, 520, 860]),
                         ('11LAB70AA504', [1000, 800, 1120, 860])):
            r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb, 'kks': code, 'isa': '', 'note': ''}})
            assert r.get('status') == 'approved', r
        self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'floor': '2'},
                                                                              'base': {'floor': self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('floor', '')}}})

        def tag(code):
            for n in ui.nodes():
                if ui.label(n).startswith(code + ','):
                    return n
            self.fail(f'{code} is not on screen')

        def tap_tag(code):
            x, y = ui.center(tag(code))
            ui.sh('input', 'tap', str(x), str(y))
            time.sleep(1)

        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            ui.find('11LAB70AA504, ', timeout=30)
            ui.tap('More', exact=True)
            ui.tap('Select tags', exact=True)
            ui.find('0 selected', exact=True)
            tap_tag('11LAB70AA501')
            tap_tag('11LAB70AA502')
            ui.find('2 selected', exact=True)
            self.assertTrue(ui.label(tag('11LAB70AA501')).endswith(', selected'), ui.label(tag('11LAB70AA501')))
            # a box around 503: hold on the paper above-left of it, then drag past its lower-right corner
            a, b, c, d = map(int, re.findall(r'\d+', tag('11LAB70AA503').get('bounds')))
            x0, y0, x1, y1 = a - 25, b - 25, c + 25, d + 25
            ui.sh('input', 'motionevent', 'DOWN', str(x0), str(y0))
            time.sleep(1.2)                                         # longer than the long-press timeout
            for k in range(1, 6):
                ui.sh('input', 'motionevent', 'MOVE', str(x0 + (x1 - x0) * k // 5), str(y0 + (y1 - y0) * k // 5))
            ui.sh('input', 'motionevent', 'UP', str(x1), str(y1))
            ui.find('3 selected', exact=True, timeout=10)
            self.assertTrue(ui.label(tag('11LAB70AA504')).endswith('not selected'))
            os.makedirs(SHOTS, exist_ok=True)
            with open(os.path.join(SHOTS, 'android-multi-selected.png'), 'wb') as f:
                f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
            # the List: untick 502
            ui.tap('List', exact=True)
            ui.tap('11LAB70AA502', exact=True)
            time.sleep(0.5)
            self.assertFalse(ui.present('11LAB70AA502', exact=True), '502 is still in the list')
            ui.tap('Close', exact=True)
            ui.find('2 selected', exact=True)
            # Place for all: a floor; 501 already has floor 2, so the dialog warns about one code
            ui.tap('Place for all', exact=True)
            ui.find('Place for 2 codes', exact=True)
            ui.type_into('Floor', '3')
            ui.find('1 of 2 codes already have another value here: it will be replaced.', exact=True)
            ui.tap('Send', exact=True)
            ui.find('Sent for 2 codes', timeout=10)

            # the phone's entries reach the server by sync (approved at once: the manager's phone); exactly the two codes
            def placed():
                e = self.boss.req('GET', '/api/state')['equipment']
                floor3 = sorted(k for k, v in e.items() if v.get('floor') == '3')
                return floor3 if len(floor3) >= 2 else None
            self.assertEqual(self.wait_server(placed, 'the place never reached the server', tries=80), ['11LAB70AA501', '11LAB70AA503'])
            time.sleep(3)
            st = self.boss.req('GET', '/api/state')['equipment']
            self.assertEqual(sorted(k for k, v in st.items() if v.get('floor') == '3'), ['11LAB70AA501', '11LAB70AA503'])
            # Note for all: appended under each code's own notes
            old = st['11LAB70AA501'].get('notes', '')
            ui.tap('More', exact=True)
            ui.tap('Select tags', exact=True)
            tap_tag('11LAB70AA501')
            tap_tag('11LAB70AA504')
            ui.find('2 selected', exact=True)
            ui.tap('Note for all', exact=True)
            ui.type_into('Note to add', 'Lagging checked')
            ui.tap('Send', exact=True)
            ui.find('Sent for 2 codes', timeout=10)

            def noted():
                e = self.boss.req('GET', '/api/state')['equipment']
                return e if e.get('11LAB70AA504', {}).get('notes') and 'Lagging' in e.get('11LAB70AA501', {}).get('notes', '') else None
            e = self.wait_server(noted, 'the note never reached the server', tries=80)
            self.assertEqual(e['11LAB70AA501']['notes'], (old + '\n' if old.strip() else '') + 'Lagging checked')
            self.assertEqual(e['11LAB70AA504']['notes'], 'Lagging checked')
            # Photo for all: a photo needs each code's floor; 504 has none, so the app says so and opens nothing
            ui.tap('More', exact=True)
            ui.tap('Select tags', exact=True)
            tap_tag('11LAB70AA501')
            tap_tag('11LAB70AA504')
            ui.find('2 selected', exact=True)
            ui.tap('Photo for all', exact=True)
            ui.find('No floor yet: 11LAB70AA504', timeout=10)
            self.assertFalse(ui.present('Photo for 2 codes', exact=True), 'Photo for all opened without the floors')
        finally:
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)

    @unittest.skipUnless(PHONE_HOST == '10.0.2.2', 'drives the emulator\'s camera app')
    def test_photos(self):
        """the photo editor (the user's Honor 600, 2026-10-04): every button on screen above the navigation bar, undo,
        retake; then the tag plate: offered after an equipment photo, sent with a caption that starts with Tag plate"""
        w, h = map(int, re.findall(r'(\d+)x(\d+)', ui.sh('wm', 'size'))[-1])
        nav = int(48 * int(re.findall(r'(\d+)', ui.sh('wm', 'density'))[-1]) / 160)     # the 3-button navigation bar

        def orange_pixels():   # the loupe's ring (#FF7A1A) in a screenshot
            from PIL import Image
            import io
            im = Image.open(io.BytesIO(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)).convert('RGB')
            return sum(1 for r, g, b in im.getdata() if r > 230 and 100 < g < 145 and b < 60)

        def snap():          # the emulator's camera app: shutter, then confirm, both at the bottom centre
            if ui.present('WHILE USING THE APP', exact=True):
                ui.tap('WHILE USING THE APP', exact=True)
            time.sleep(5)
            ui.sh('input', 'tap', str(w // 2), str(int(h * 0.94)))
            time.sleep(4)
            ui.sh('input', 'tap', str(w // 2), str(int(h * 0.94)))
            ui.find('Send', exact=True, timeout=30)
        cur = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('floor', '')
        if cur:       # an earlier test set one
            self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'floor': ''}, 'base': {'floor': cur}}})
        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            ui.type_into('Search KKS or description', 'LAB70AA501')
            ui.tap('11LAB70AA501', exact=True)
            ui.scroll_to('Take a photo', exact=True)
            ui.tap('Take a photo', exact=True)
            # the code has no floor (cleared above): it is asked first, and goes with the photo (request 4, 2026-10-08)
            ui.find('Which floor is it on?', exact=True)
            ui.tap('Floor 5')
            ui.tap('Continue', exact=True)
            snap()
            for b in ('Undo', 'Retake', 'Cancel', 'Send', 'Arrow', 'Circle', 'White'):
                bottom = int(re.findall(r'\d+', ui.find(b, exact=b != 'White').get('bounds'))[3])
                self.assertLessEqual(bottom, h - nav, f'{b} is under the navigation bar or off the screen')
            def undo_enabled():      # the clickable button around the label (the label itself always says enabled)
                box = [int(v) for v in re.findall(r'\d+', ui.find('Undo', exact=True).get('bounds'))]
                for n in ui.nodes():
                    b = [int(v) for v in re.findall(r'\d+', n.get('bounds', '[0,0][0,0]'))]
                    if n.get('clickable') == 'true' and b[0] <= box[0] and b[1] <= box[1] and b[2] >= box[2] and b[3] >= box[3]:
                        return n.get('enabled') == 'true'
                self.fail('no button around Undo')
            self.assertFalse(undo_enabled(), 'Undo before anything was drawn')
            ui.sh('input', 'swipe', str(w // 3), str(h // 2), str(w * 2 // 3), str(h * 3 // 5), '400')    # an arrow
            self.assertTrue(undo_enabled(), 'Undo after an arrow')
            ui.tap('Undo', exact=True)
            self.assertFalse(undo_enabled(), 'Undo after undoing the only arrow')
            # thick lines, zoomed in; a finger held mid-stroke shows the loupe (its orange ring), gone once lifted
            ui.tap('Thick lines', exact=True)
            ui.tap('Zoom in', exact=True)
            ui.sh('input', 'motionevent', 'DOWN', str(w // 3), str(h // 2))
            ui.sh('input', 'motionevent', 'MOVE', str(w // 2), str(h * 11 // 20))
            time.sleep(1)
            held = orange_pixels()
            ui.sh('input', 'motionevent', 'UP', str(w // 2), str(h * 11 // 20))
            time.sleep(1)
            self.assertGreater(held, 2000, 'no loupe while the finger draws')
            self.assertLess(orange_pixels(), 200, 'the loupe stayed after the finger left')
            ui.tap('Retake', exact=True)
            snap()
            ui.tap('Send', exact=True)
            ui.find('And its tag plate?', exact=True, timeout=60)
            ui.tap('Take it', exact=True)
            snap()
            ui.find('Tag plate', exact=True)
            ui.tap('Send', exact=True)
            def caps():
                c = sorted(p['caption'] for p in self.boss.req('GET', '/api/state')['photos'] if p['kks'] == '11LAB70AA501')
                return c if len(c) == 2 else None
            self.assertEqual(self.wait_server(caps, 'the two photos never reached the server', tries=120), ['', 'Tag plate'])
            self.assertEqual(self.boss.req('GET', '/api/state')['equipment']['11LAB70AA501'].get('floor'), '5', 'the floor sent with the photo')
            # the drawing coloured by photos: this tag has both now (the drawing's tags carry it in their names)
            ui.sh('input', 'keyevent', '4')
            ui.tap('More', exact=True)
            ui.tap('Colour tags by photos', exact=True)
            ui.find('11LAB70AA501, equipment and tag plate photos', timeout=20)
            # delete one: the confirm dialog sent an empty photo id ("bad photo id") before the fix
            ui.tap('11LAB70AA501, equipment and tag plate photos')
            ui.scroll_to('Delete', exact=True)
            ui.tap('Delete', exact=True)
            ui.find('Delete this photo?', exact=True)
            ui.tap('Delete', exact=True)
            self.assertFalse(ui.present('bad photo id'), 'the delete sent no photo id')
            def left():
                c = [p for p in self.boss.req('GET', '/api/state')['photos'] if p['kks'] == '11LAB70AA501']
                return c if len(c) == 1 else None
            self.wait_server(left, 'the deleted photo is still on the server', tries=60)
        finally:
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)

    def test_dark(self):
        """dark drawings: DarkColor equals the Nim function (tests/web/dark-vectors.json, checked on the device by the
        debug-only DebugDarkReceiver) and the markers keep 3:1; the ⋮ toggle turns the paper dark and the lines light
        at once (a screenshot against the light one, pixel by pixel), and it is still on after the app restarts"""
        from PIL import Image
        import io

        def shot(name):
            png = subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout
            os.makedirs(SHOTS, exist_ok=True)
            with open(os.path.join(SHOTS, name), 'wb') as f:
                f.write(png)
            return Image.open(io.BytesIO(png)).convert('RGB')

        def checked(text):   # the checkable node around a label (the menu item; the label itself is not checkable)
            box = [int(v) for v in re.findall(r'\d+', ui.find(text, exact=True).get('bounds'))]
            for n in ui.nodes():
                b = [int(v) for v in re.findall(r'\d+', n.get('bounds', '[0,0][0,0]'))]
                if n.get('checkable') == 'true' and b[0] <= box[0] and b[1] <= box[1] and b[2] >= box[2] and b[3] >= box[3]:
                    return n.get('checked')
            self.fail(f'nothing checkable around {text!r}: ' + repr([(n.get('class'), label(n), n.get('checkable'), n.get('bounds')) for n in ui.nodes()][-12:]))

        def label(n):
            return ui.label(n)

        def region():        # the middle of the drawing: below the search field, clear of the buttons and the sides
            a, b, c, d = map(int, re.findall(r'\d+', ui.find('Drawing sample').get('bounds')))
            top = int(re.findall(r'\d+', ui.find('Search equipment by KKS code or description').get('bounds'))[3]) + 20
            return a + (c - a) // 5, top, c - (c - a) // 5, top + (d - top) * 2 // 3
        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            # the colour function on the device
            with open(os.path.join(REPO, 'tests', 'web', 'dark-vectors.json'), 'rb') as f:
                subprocess.run(ui.ADB + ['shell', 'run-as', PKG, 'sh', '-c', '"cat > files/dark-vectors.json"'], input=f.read(), check=True)
            subprocess.run(ui.ADB + ['shell', 'run-as', PKG, 'rm', '-f', 'files/dark-check.txt'])
            ui.adb('shell', 'am', 'broadcast', '-a', 'kks.explorer.DEBUG_DARK', '-p', PKG)
            check = ''
            for _ in range(30):
                check = subprocess.run(ui.ADB + ['exec-out', 'run-as', PKG, 'cat', 'files/dark-check.txt'], capture_output=True, text=True).stdout
                if check:
                    break
                time.sleep(0.5)
            self.assertTrue(check.startswith('ok '), check)
            # the sheet in light mode: which pixels are paper (white) and which are lines (dark grey/black)
            time.sleep(3)
            box = region()
            light = shot('android-dark-before.png')
            paper, lines = [], []
            for y in range(box[1], box[3], 2):
                for x in range(box[0], box[2], 2):
                    r, g, b = light.getpixel((x, y))
                    if min(r, g, b) >= 250:
                        paper.append((x, y))
                    elif max(r, g, b) <= 70 and max(r, g, b) - min(r, g, b) <= 10:
                        lines.append((x, y))
            self.assertGreater(len(paper), 1000, 'no paper in the light screenshot')
            self.assertGreater(len(lines), 20, 'no lines in the light screenshot')
            ui.tap('More', exact=True)
            self.assertEqual(checked('Dark drawings'), 'false')
            ui.tap('Dark drawings', exact=True)
            time.sleep(4)

            def judge(im):
                dark_paper = sum(1 for p in paper if max(im.getpixel(p)) <= 40)
                light_lines = sum(1 for p in lines if min(im.getpixel(p)) >= 150)
                return dark_paper / len(paper), light_lines / len(lines)
            pf, lf = judge(shot('android-dark-on.png'))
            self.assertGreater(pf, 0.95, f'only {pf:.0%} of the paper turned dark')
            self.assertGreater(lf, 0.8, f'only {lf:.0%} of the lines turned light')
            # remembered: the app restarted shows the sheet dark, the menu item checked
            ui.sh('am', 'force-stop', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            ui.find('Sample sheet', timeout=40)
            time.sleep(4)
            pf, lf = judge(shot('android-dark-restarted.png'))
            self.assertGreater(pf, 0.95, f'after a restart only {pf:.0%} of the paper is dark')
            self.assertGreater(lf, 0.8, f'after a restart only {lf:.0%} of the lines are light')
            ui.tap('More', exact=True)
            self.assertEqual(checked('Dark drawings'), 'true')
            ui.sh('input', 'keyevent', '4')
        finally:
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)

    def test_diagnostics(self):
        """decision 0040: the manager's phone switches reports on; an event is sealed into a report the server stores
        but can't open; the phone (holding the report key) shows it under Manage → Diagnostics. Needs the debug build
        (DebugDiagReceiver records the event: a real report waits for a real error)."""
        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            ui.tap('Manage', exact=True)
            ui.tap('Account', exact=True)
            ui.scroll_to('Switch reports on', exact=True, tries=12)
            ui.tap('Switch reports on', exact=True)
            self.wait_server(lambda: self.boss.req('GET', '/api/diagnostics')['on'], 'the setting never reached the server')
            ui.adb('shell', 'am', 'broadcast', '-a', 'kks.explorer.DEBUG_DIAG', '-p', PKG, '--es', 'text', 'e2e-diagnostics-event')
            reports = self.wait_server(lambda: self.boss.req('GET', '/api/diagnostics')['reports'], 'no report reached the server', tries=120)
            self.assertIsNone(reports[0]['report'], 'a server must not open reports (it holds no person secret)')
            self.assertFalse(self.boss.req('GET', '/api/diagnostics')['can_switch'])
            ui.sh('input', 'keyevent', '4')
            ui.tap('Diagnostics', exact=True)
            ui.find('e2e-diagnostics-event', timeout=15)
        finally:
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)

    def test_systems(self):
        """Equipment by system (core systemsView): the ⋮ menu opens it; systems start closed; a header opens on a tap
        and says whether it is open; a filter opens the whole path; a code opens its tag like a search result"""
        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            ui.tap('More', exact=True)
            ui.tap('Equipment by system', exact=True)
            ui.find('LAB · Feed water piping system, ', timeout=15)
            self.assertFalse(ui.present('LAB70, '), 'systems start closed')
            ui.tap('LAB · Feed water piping system, ')
            ui.find('LAB70, ', timeout=10)
            time.sleep(1)
            self.assertFalse(ui.present('11LAB70AA501, '), 'the subsystem opened by itself')
            ui.type_into('Filter equipment by system', 'LAB70AA501')
            ui.find('AA · ', timeout=10)
            row = ui.find('11LAB70AA501, ', timeout=10)
            self.assertIn('Sample sheet', label := ui.label(row), label)
            with open('/tmp/kks-android-systems.png', 'wb') as f:
                f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
            ui.tap('11LAB70AA501, ')
            # the screen closes; the tag's panel is open on its sheet
            ui.find('Feed water piping system', timeout=15)
            self.assertFalse(ui.present('Equipment by system', exact=True), 'the screen stayed open')
        finally:
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)

    def test_coverage(self):
        """the coverage dashboard (core coverageView): totals on the test plant; a sheet row opens that sheet with the
        photo colours on; a system row opens Equipment by system showing that system only"""
        r = self.boss.req('GET', '/api/sheets')
        if not any(s.get('id') == 'second' for s in r.get('sheets', [])):
            with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f:
                pdf = f.read()
            assert self.boss.req('POST', '/api/sheets/import?id=second&name=Second%20sheet', raw=pdf, ctype='application/pdf').get('ok')
            for _ in range(300):
                job = self.boss.req('GET', '/api/sheets/job')['job']
                if job['state'] != 'running':
                    break
                time.sleep(0.2)
            assert job['state'] == 'done', job['log']
        # a hand-marked tag whose sheet is not in the plant data (a tag can outlive its sheet): counted, nothing to open
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'removed-sheet', 'bbox': [400, 300, 520, 360],
                                                 'kks': '11LAB70AA509', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
        try:
            ui.tap('Join through a server', exact=True)
            ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
            ui.type_into('Username', 'boss')
            ui.type_into('Password', 'a long password')
            ui.tap('Join', exact=True)
            ui.find('Sample sheet', timeout=40)
            ui.tap('More', exact=True)
            ui.tap('Coverage', exact=True)
            # the test plant: two codes marked by the manager (so checked), no place, no photos: 11LAB70AA501 on the
            # sample sheet, 11LAB70AA509 on a sheet that isn't there
            for t in ('Codes on the drawings: 2 (on 2 tags)', 'Checked by a person: 100 % (2 of 2 tags)',
                      'Known place: 0 % (0 of 2 codes)', 'To review: 0', 'Missed tags marked: 2'):
                ui.find(t, timeout=15)
            ui.find('Sample sheet: 1 code on 1 tag, 100 % of tags checked by a person, 0 % with a known place, photos: 0 both, '
                    '0 equipment only, 0 tag plate only, 1 none, 0 to review, 1 missed tags marked')
            ui.find('LAB · Feed water piping system: 2 codes, 100 % of codes checked by a person')
            # the missing sheet's row: the message shows in the dashboard, which stays open (it is its own window, so
            # the app's snackbar behind it would never be seen)
            ui.tap('removed-sheet: 1 code on 1 tag')
            ui.find('That sheet is no longer in the plant data', exact=True, timeout=10)
            self.assertTrue(ui.present('Codes on the drawings'), 'the dashboard closed')
            os.makedirs(SHOTS, exist_ok=True)
            with open(os.path.join(SHOTS, 'android-coverage.png'), 'wb') as f:
                f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
            # a sheet row: that sheet, coloured by photos (the legend shows)
            ui.tap('Second sheet: ')
            ui.find('Second sheet', exact=True, timeout=15)
            self.assertFalse(ui.present('Codes on the drawings'), 'the dashboard stayed open')
            ui.find('Tag plate', exact=True)
            # a system row: Equipment by system, that system only, open
            ui.tap('More', exact=True)
            ui.tap('Coverage', exact=True)
            ui.tap('LAB · Feed water piping system: ', timeout=15)
            ui.find('Only system LAB', exact=True, timeout=15)
            ui.find('LAB70, ', timeout=10)
        finally:
            removed = []
            for a in self.boss.req('GET', '/api/state').get('added_tags', []):
                if a.get('sheet') == 'removed-sheet':
                    removed.append(self.boss.req('POST', '/api/submit', {'kind': 'tag_remove', 'payload': {'id': a['id']}}))
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.sh('pm', 'clear', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            time.sleep(3)
            # after the rest of the clean-up: else the later tests would count this tag
            assert removed and all(r.get('status') == 'approved' for r in removed), removed

    def test_flow(self):
        # join through the server (PROTOCOL-v2 §16 enroll over TLS)
        ui.tap('Join through a server', exact=True)
        ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
        ui.type_into('Username', 'boss')
        ui.type_into('Password', 'a long password')
        ui.tap('Join', exact=True)
        ui.find('Sample sheet', timeout=40)
        # search → the panel decodes the tag
        ui.type_into('Search KKS or description', 'LAB70AA501')
        ui.tap('11LAB70AA501', exact=True)
        ui.find('Feed water piping system', timeout=10)
        # edit a field; the change reaches the server by the automatic sync
        ui.scroll_to('Edit', exact=True)
        ui.tap('Edit', exact=True)
        ui.scroll_to('Notes', exact=True)
        ui.type_into('Notes', 'Gland repacked')
        ui.scroll_to('Save', exact=True)
        ui.tap('Save', exact=True)
        eq = self.wait_server(lambda: self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('notes'),
                              'the edit never reached the server')
        self.assertEqual(eq, 'Gland repacked')
        # a member proposes on the server; the manager approves on the phone
        r = self.boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali Member', 'position': 'Technician', 'role': 'user'})
        ali = Client(self.base)
        ali.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'ali password 1'})
        ali.req('POST', '/api/login', {'username': 'ali', 'password': 'ali password 1'})
        self.assertEqual(ali.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                         'changes': {'floor': '2'}}})['status'], 'pending')
        ui.sh('input', 'keyevent', '4')                    # close the panel
        ui.tap('Sync', exact=True)
        time.sleep(3)
        ui.tap('Manage', exact=True)
        ui.tap('Approvals', exact=True)
        ui.tap('Approve', exact=True, timeout=20)
        subs = self.wait_server(lambda: [s for s in ali.req('GET', '/api/submissions?status=all')['submissions'] if s['status'] == 'approved'],
                                'the approval never reached the server')
        self.assertEqual(len(subs), 1)
        # the manager removes the phone on the server; at its next sync it wipes itself and starts over
        devs = self.boss.req('GET', '/api/devices')['all']
        model = ui.sh('getprop', 'ro.product.model').strip()
        phone = [d for d in devs if d['username'] == 'boss' and d['label'] == model and not d['revoked']]
        self.assertEqual(len(phone), 1, devs)
        self.assertTrue(self.boss.req('POST', '/api/devices/revoke', {'device': phone[0]['device']}).get('ok'))
        ui.sh('input', 'keyevent', '4')
        ui.tap('Drawings', exact=True)
        ui.tap('Sync', exact=True)
        ui.find('removed from the plant by The Manager', timeout=30)
        db = subprocess.run(ui.ADB + ['exec-out', 'run-as', PKG, 'cat', 'files/core/kks.db'], capture_output=True).stdout
        self.assertLess(len(db), 64 * 1024, 'the plant data is still on the phone')


    # ---------------------------------------------------------------- the user's requests of 2026-10-08

    def test_photo_queue(self):
        """request 1: photos go through a background queue (WorkManager): sent in order with the panel closed, kept
        across the app being stopped, a floor sent with the first photo of a code without one, failures shown"""
        try:
            self.join()
            self.open_tag()
            ui.sh('input', 'keyevent', '4')                    # close the panel: the queue must not care
            codes = ['11LAB70AA502', '11LAB70AA503', '11LAB70AA504']
            # held (debug builds): the jobs wait, so their files can be checked and the app stopped with all three queued
            ui.adb('shell', 'am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_PHOTO', '-p', PKG, '--ez', 'hold', 'true')
            for i, k in enumerate(codes):
                extra = ['--es', 'floor', '3'] if i == 0 else []
                ui.adb('shell', 'am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_PHOTO', '-p', PKG, '--es', 'kks', k,
                       '--es', 'caption', f'queued_{i}', *extra)     # no spaces: adb shell joins the words
            ui.find('3 photos being prepared', timeout=20)
            time.sleep(1)
            # the process stops with photos still queued; WorkManager brings the work back when the app starts again
            ui.sh('am', 'force-stop', PKG)
            time.sleep(2)
            # queued photos are plant data: sealed at rest (Keys.seal, decision 0049), never the raw pixels or the code
            def jhash(t):           # Java's String.hashCode: the debug photo's background is (hash & 0xff, 120, 180)
                h = 0
                for ch in t:
                    h = (31 * h + ord(ch)) & 0xFFFFFFFF
                return h
            names = ui.adb('exec-out', 'run-as', PKG, 'ls', 'files/photo-queue').split()
            self.assertEqual(len([n for n in names if n.endswith('.px')]), 3, f'the queued photos: {names}')
            self.assertEqual(len([n for n in names if n.endswith('.json')]), 3, f'the queued jobs: {names}')
            for n in names:
                raw = subprocess.run(ui.ADB + ['exec-out', 'run-as', PKG, 'cat', 'files/photo-queue/' + n], capture_output=True).stdout
                self.assertTrue(raw.startswith(b'KSL1'), f'{n} is not sealed')
                for k in codes:
                    self.assertNotIn(k.encode(), raw, f'{n} holds a code in clear text')
                    self.assertNotIn(bytes([jhash(k) & 0xff, 120, 180, 255]) * 8, raw, f'{n} holds raw pixels')
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')

            def arrived():
                ph = [p for p in self.boss.req('GET', '/api/state')['photos'] if p['kks'] in codes]
                return ph if len(ph) == 3 else None
            ph = self.wait_server(arrived, 'the queued photos never all reached the server', tries=360)
            by = {p['kks']: p for p in ph}
            self.assertEqual([by[k]['caption'] for k in codes], ['queued_0', 'queued_1', 'queued_2'])
            sent = [by[k].get('submitted') or by[k].get('created') or 0 for k in codes]
            self.assertEqual(sent, sorted(sent), 'the photos were not sent in the order taken')
            self.assertEqual(self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA502', {}).get('floor'), '3',
                             'the floor sent with the photo was not written')
            ui.find('Sample sheet', timeout=20)
            self.assertFalse(ui.present('photos being prepared'), 'the queue count stayed after the photos were sent')
            # an encode that fails (out of memory) keeps the photo and tries again: it arrives, and nothing is reported
            ui.adb('shell', 'am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_PHOTO', '-p', PKG, '--ei', 'fail_encodes', '2')
            ui.adb('shell', 'am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_PHOTO', '-p', PKG, '--es', 'kks', '11LAB70AA505',
                   '--es', 'caption', 'retried')
            def retried():
                return [p for p in self.boss.req('GET', '/api/state')['photos'] if p['kks'] == '11LAB70AA505'] or None
            self.assertEqual(self.wait_server(retried, 'a photo whose encode failed was dropped', tries=600)[0]['caption'], 'retried')
            self.assertFalse(ui.present('A photo was not sent'), 'a retried photo was reported as not sent')
            # a photo the core refuses (a bad code) is reported, and the queue goes on
            ui.adb('shell', 'am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_PHOTO', '-p', PKG, '--es', 'kks', 'bad-code')
            ui.find('A photo was not sent', timeout=120)
            ui.find('bad-code: ', timeout=5)
            ui.tap('Dismiss', exact=True)
            time.sleep(1)
            self.assertFalse(ui.present('A photo was not sent'))
        finally:
            self.leave()

    def test_description_and_credit(self):
        """requests 2 and 3: the panel says who set a field and when; a draft description from the plant data is
        "Draft description (unchecked)" until Confirm, then "Confirmed by …" """
        plant = os.path.join(self.dir, 'plant-data')
        with open(os.path.join(plant, 'descriptions.json'), 'w') as f:
            json.dump({'11LAB70AA501': {'text': 'Feed water isolation valve', 'basis': 'e2e test'}}, f)
        r = subprocess.run([SERVER, 'publish-data', plant, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        nura = self.member('nura', 'Nura Credit', 'nura password 1')
        r = nura.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'near': 'by the e2e stair'}}})
        self.assertEqual(r.get('status'), 'pending', r)
        sub = [x for x in self.boss.req('GET', '/api/submissions')['submissions'] if x['by'] == 'nura'][0]
        self.assertTrue(self.boss.req('POST', f'/api/submissions/{sub["id"]}/approve', {}).get('ok', True))
        try:
            self.join()
            self.open_tag()
            # the description comes before the location fields
            ui.scroll_to('Draft description (unchecked)', exact=True)
            ui.scroll_to('Feed water isolation valve', exact=True)
            ui.scroll_to('Confirm', exact=True)
            ui.tap('Confirm', exact=True)

            def confirmed():
                c = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('custom') or []
                return [x for x in c if x['k'] == 'Description']
            self.assertEqual(self.wait_server(confirmed, 'the confirmed description never reached the server')[0]['v'],
                             'Feed water isolation valve')
            ui.find('Confirmed by The Manager', timeout=20)
            ui.scroll_to('by the e2e stair')
            ui.find('by Nura Credit, ')                         # the author of the field, not the approver
        finally:
            self.leave()

    @unittest.skipUnless(PHONE_HOST == '10.0.2.2', 'drives the emulator\'s camera app')
    def test_floor_first(self):
        """request 4: a code without a floor asks for it before the camera opens; Cancel opens no camera"""
        try:
            self.join()
            # a code with no tag on the drawing has no panel: use the sample tag after clearing its floor
            cur = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('floor', '')
            if cur:
                self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'floor': ''},
                                                                                     'base': {'floor': cur}}})
                ui.tap('Sync', exact=True)
                time.sleep(3)
            self.open_tag()
            ui.scroll_to('Take a photo', exact=True)
            ui.tap('Take a photo', exact=True)
            ui.find('Which floor is it on?', exact=True)
            ui.tap('Cancel', exact=True)
            time.sleep(2)
            self.assertTrue(ui.present('Take a photo', exact=True), 'the camera opened without a floor')
            ui.tap('From the gallery', exact=True)
            ui.find('Which floor is it on?', exact=True)
            ui.tap('Floor 4')
            ui.tap('Continue', exact=True)
            time.sleep(2)
            self.assertFalse(ui.present('Which floor is it on?', exact=True))
        finally:
            ui.sh('input', 'keyevent', '4')
            self.leave()

    def test_approvals_grouped(self):
        """request 5: one card per code with the equipment and tag plate photos together; Approve/Reject only, unless
        several photos of one kind compete (then "Use this one", which leaves the other kind alone); the full name; the
        code opens its tag on the drawing"""
        omar = self.member('omar', 'Omar Fullname', 'omar password 1')
        for cap, tag in (('', 'eq1'), ('Tag plate', 'plate1')):
            r = omar.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': cap, 'dataUrl': self.jxl(tag)}})
            self.assertIn(r.get('status'), ('pending', 'conflict'), r)
        try:
            self.join()
            ui.tap('Manage', exact=True)
            ui.tap('Approvals', exact=True)
            ui.find('Equipment photo', exact=True, timeout=20)
            ui.find('Tag plate photo', exact=True)
            self.assertTrue(ui.present('by Omar Fullname'), 'the full name of the sender')
            self.assertFalse(ui.present('by omar ·'), 'the username instead of the full name')
            self.assertFalse(ui.present('Use this one', exact=True), 'Pick offered with one photo per kind')
            self.assertEqual(sum(1 for n in ui.nodes() if ui.label(n) == '11LAB70AA501'), 1, 'one card for the code')
            # a second equipment photo: now those two compete
            omar.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': 'second', 'dataUrl': self.jxl('eq2')}})
            ui.sh('input', 'keyevent', '4')
            ui.tap('Drawings', exact=True)
            ui.tap('Sync', exact=True)
            time.sleep(3)
            ui.tap('Manage', exact=True)
            ui.tap('Approvals', exact=True)
            ui.find('Equipment photo (2)', exact=True, timeout=20)
            ui.tap('Use this one', exact=True)

            def decided():
                subs = [x for x in omar.req('GET', '/api/submissions?status=all')['submissions'] if x['kind'] == 'photo']
                st = {x['payload'].get('caption', ''): x['status'] for x in subs}
                return st if 'approved' in st.values() else None
            st = self.wait_server(decided, 'the pick never reached the server')
            self.assertEqual(sorted(v for k, v in st.items() if not k.startswith('Tag plate')), ['approved', 'rejected'])
            self.assertEqual(st['Tag plate'], 'pending', 'Pick rejected the tag plate photo too')
            # the code opens its tag on the drawing
            ui.tap('Open on the drawing', exact=True)
            ui.find('Feed water piping system', timeout=15)
        finally:
            for x in self.boss.req('GET', '/api/submissions')['submissions']:
                if x['by'] == 'omar':
                    self.boss.req('POST', f'/api/submissions/{x["id"]}/reject', {})
            # the photo "Use this one" approved stays on the code: remove it, or test_photos counts it as its own
            for p in self.boss.req('GET', '/api/state')['photos']:
                if p.get('by') == 'omar':
                    self.boss.req('POST', '/api/submit', {'kind': 'photo_delete', 'payload': {'photo_id': p['id']}})
            self.leave()

    def test_position_required(self):
        """request 7: a new member's join forms need a position; an admin's Add a person too"""
        try:
            ui.tap('Join with a file', exact=True)
            ui.type_into('Your username', 'nopos')
            ui.type_into('Your full name', 'No Position')
            ui.tap('Save a join request…', exact=True)
            ui.find('your position (job title)', timeout=5)
            ui.type_into('Your position (job title)', 'Technician')
            ui.tap('Save a join request…', exact=True)
            time.sleep(2)
            self.assertFalse(ui.present('your position (job title).'), 'refused with a position')
            ui.sh('input', 'keyevent', '4')                    # the system's file picker
            time.sleep(1)
            ui.sh('am', 'force-stop', PKG)
            ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
            self.join()
            ui.tap('Manage', exact=True)
            ui.tap('People', exact=True)
            ui.scroll_to('Position (job title)', exact=True)
            ui.type_into('Username', 'noposition')
            ui.type_into('Full name', 'No Position Either')
            ui.tap('Add', exact=True)
            ui.find('every new member needs one', timeout=10)
            self.assertFalse(any(u['username'] == 'noposition' for u in self.boss.req('GET', '/api/users?show_hidden=1')['users']))
        finally:
            self.leave()

    def test_hide_removed(self):
        """request 8: Devices → Clear removed hides removed devices (this phone's own list), Show hidden brings them back"""
        try:
            # a removed device of our own: join, be removed, join again
            self.join()
            model = ui.sh('getprop', 'ro.product.model').strip()
            for d in self.boss.req('GET', '/api/devices')['all']:
                if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                    self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
            ui.tap('Sync', exact=True)
            ui.find('removed from the plant', timeout=30)
            self.join()
            ui.tap('Manage', exact=True)
            ui.tap('Devices', exact=True)
            ui.scroll_to('Clear removed', exact=True)
            self.assertTrue(ui.present('· removed'), 'no removed device listed')
            ui.tap('Clear removed', exact=True)
            ui.find('Show hidden (', timeout=10)
            self.assertFalse(ui.present('· removed'), 'removed devices still listed')
            ui.tap('Show hidden (')
            ui.find('· removed', timeout=10)
            ui.find('Show', exact=True)
        finally:
            self.leave()

    def test_member_pages(self):
        """requests 6, 9 and 10 as a member: the leaderboard; Updates on Manage's top level (not in Account); My
        proposals filtered by status and grouped by code"""
        tala = self.member('tala', 'Tala Member', 'tala password 1')
        now = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('notes', '')
        for note in ('first e2e note', 'second e2e note'):     # the second is held: it clashes with the first
            r = tala.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'notes': note},
                                                                                'base': {'notes': now}}})
            self.assertIn(r.get('status'), ('pending', 'conflict'), r)
        first = [x for x in self.boss.req('GET', '/api/submissions')['submissions']
                 if x['by'] == 'tala' and x['payload']['changes'].get('notes') == 'first e2e note']
        self.boss.req('POST', f'/api/submissions/{first[0]["id"]}/reject', {})
        try:
            self.join('tala', 'tala password 1')
            ui.tap('Manage', exact=True)
            ui.scroll_to('Check now', exact=True)              # Updates on the top level
            ui.scroll_to('Leaderboard', exact=True)
            ui.tap('Leaderboard', exact=True)
            ui.find('Tala Member', timeout=15)
            ui.find('The Manager')
            self.assertFalse(ui.present('tala', exact=True), 'a username on the leaderboard')
            ui.sh('input', 'keyevent', '4')
            ui.tap('Account', exact=True)
            time.sleep(1)
            for _ in range(4):
                ui.sh('input', 'swipe', '500', '1600', '500', '600', '300')
            self.assertFalse(ui.present('Check now', exact=True), 'Updates still in Account')
            ui.sh('input', 'keyevent', '4')
            ui.tap('My proposals', exact=True)
            ui.find('11LAB70AA501', exact=True, timeout=15)
            ui.find('second e2e note')
            ui.tap('Status: Rejected')
            ui.find('first e2e note', timeout=10)
            time.sleep(1)
            self.assertFalse(ui.present('second e2e note'), 'the status filter let a pending proposal through')
            ui.tap('Status: Waiting')
            ui.find('second e2e note', timeout=10)
            ui.tap('Kind: Tag plate photos')
            ui.find('Nothing matches these filters.', timeout=10)
        finally:
            for x in self.boss.req('GET', '/api/submissions')['submissions']:
                if x['by'] == 'tala':
                    self.boss.req('POST', f'/api/submissions/{x["id"]}/reject', {})
            self.leave('tala')


if __name__ == '__main__':
    unittest.main()
