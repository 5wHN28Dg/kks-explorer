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


DIAG = os.environ.get('KKS_E2E_DIAG', '')      # a folder: per-test timing, the emulator's memory, the screen at a failure


def emulator_memory():
    """the emulator's cgroup (its capped scope): (bytes now, peak), or None"""
    try:
        pid = subprocess.run(['pgrep', '-f', '^/.*/qemu-system-[^ ]* -avd'], capture_output=True, text=True).stdout.split()[0]
        with open(f'/proc/{pid}/cgroup') as f:
            cg = '/sys/fs/cgroup' + f.read().strip().split('::', 1)[1]
        out = []
        for k in ('current', 'peak'):
            with open(f'{cg}/memory.{k}') as f:
                out.append(int(f.read()))
        return tuple(out)
    except (IndexError, OSError, ValueError):
        return None


def diag(line):
    if DIAG:
        os.makedirs(DIAG, exist_ok=True)
        with open(os.path.join(DIAG, 'diag.log'), 'a') as f:
            f.write(time.strftime('%H:%M:%S ') + line + '\n')


def diag_fail(text, ns):
    if not DIAG:
        return
    stamp = time.strftime('%H%M%S')
    mem = emulator_memory()
    diag(f'FAIL find {text!r} emulator={mem} -> {stamp}.png/.txt')
    with open(os.path.join(DIAG, stamp + '.txt'), 'w') as f:
        for at, screen in ui.recent:
            f.write(f'---- screen read at {at}\n' + '\n'.join(f'{n.get("bounds")} {ui.label(n)!r}' for n in screen if ui.label(n)) + '\n')
    with open(os.path.join(DIAG, stamp + '.png'), 'wb') as f:
        f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)


ui.on_fail = diag_fail


class Phone(unittest.TestCase):
    def run(self, result=None):
        if not DIAG:
            return super().run(result)
        t0 = time.time()
        ui.nodes()
        dump = time.time() - t0
        before = len(result.failures) + len(result.errors) if result else 0
        r = super().run(result)
        bad = (len(result.failures) + len(result.errors) - before) if result else 0
        mem = emulator_memory()
        diag(f'{self._testMethodName} {"FAILED" if bad else "ok"} {time.time() - t0:.0f}s dump_before={dump:.2f}s '
             f'emulator_now={mem[0] / 2**30:.2f}G peak={mem[1] / 2**30:.2f}G' if mem else f'{self._testMethodName} bad={bad} (no emulator cgroup)')
        return r

    @classmethod
    def setUpClass(cls):
        subprocess.run(ui.ADB + ['uninstall', PKG], capture_output=True)   # a newer test build (test_update's 9.9.9) blocks -r
        r = subprocess.run(ui.ADB + ['install', '-t', APK], capture_output=True, text=True)
        assert 'Success' in r.stdout, 'install failed: ' + r.stdout + r.stderr

    def setUp(self):
        """every test gets a server of its own (a new plant: the manager, the sample sheet with one marked tag) and
        the app with its data cleared. Until #150 the tests shared one server, and what a test saw depended on the
        tests before it: test_coverage counted the tags test_multi had marked, and in test_hide_removed the button
        was pushed off the screen by the devices of the earlier tests' members. A server takes about a second."""
        self.dir = tempfile.mkdtemp(prefix='kks-app2-e2e-')
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.port, self.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': self.port, 'sync_port': self.sport, 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        with open(os.path.join(self.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
        self.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        self.addCleanup(self.stop_server)
        setup = None
        for _ in range(50):
            line = self.server.stdout.readline()
            if 'setup link file: ' in line:      # the link is in a 0600 file (#69)
                with open(line.split('setup link file: ', 1)[1].strip()) as f:
                    line = f.read()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
        self.base = f'http://127.0.0.1:{self.port}'
        self.boss = Client(self.base)
        assert self.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                    'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        self.import_sheet('sample', 'Sample sheet')
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360],
                                                  'kks': '11LAB70AA501', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
        if PHONE_HOST == '127.0.0.1':
            ui.adb('reverse', f'tcp:{self.sport}', f'tcp:{self.sport}')
            self.addCleanup(ui.adb, 'reverse', '--remove', f'tcp:{self.sport}')
        self.addCleanup(ui.sh, 'am', 'force-stop', PKG)      # before the server goes (cleanups run last first)
        ui.fresh_app(PKG)
        time.sleep(3)

    def import_sheet(self, sid, name):
        """the sample drawing as a sheet of the test plant"""
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f:
            pdf = f.read()
        assert self.boss.req('POST', f'/api/sheets/import?id={sid}&name={name.replace(" ", "%20")}', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = self.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']

    def stop_server(self):
        self.server.terminate()
        try:
            self.server.wait(5)
        except subprocess.TimeoutExpired:
            self.server.kill()
            self.server.wait(5)
        self.server.stdout.close()

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
        """remove this phone's device on the server and start the app fresh (to join again, or as someone else)"""
        model = ui.sh('getprop', 'ro.product.model').strip()
        for d in self.boss.req('GET', '/api/devices?show_hidden=1')['all']:
            if d['username'] == user and d['label'] == model and not d['revoked']:
                self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
        ui.fresh_app(PKG)
        time.sleep(3)

    def member(self, username, full_name, pw):
        """a member with a password on the server"""
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
        # Photo for all: a photo needs each code's floor; 504 has none, so it is asked for first, for that code
        # (before 2026-10-10 the app refused here and sent the person to Place for all); Cancel opens nothing
        ui.tap('More', exact=True)
        ui.tap('Select tags', exact=True)
        tap_tag('11LAB70AA501')
        tap_tag('11LAB70AA504')
        ui.find('2 selected', exact=True)
        ui.tap('Photo for all', exact=True)
        ui.find('Which floor is it on?', exact=True, timeout=10)
        ui.find('11LAB70AA504 has no floor yet.')
        ui.find('The other codes keep the floor they have.')
        ui.tap('Cancel', exact=True)
        time.sleep(1)
        self.assertFalse(ui.present('Photo for 2 codes', exact=True), 'Photo for all opened without the floor')
        ui.find('2 selected', exact=True)
        # with the floor chosen it goes on to the photo; all codes with a floor: no question
        ui.tap('Photo for all', exact=True)
        ui.tap('Floor 6', timeout=10)
        ui.tap('Continue', exact=True)
        ui.find('Photo for 2 codes', exact=True, timeout=10)
        ui.tap('Cancel', exact=True)
        tap_tag('11LAB70AA504')
        ui.find('1 selected', exact=True)
        ui.tap('Photo for all', exact=True)
        ui.find('Photo for 1 code', exact=True, timeout=10)
        self.assertFalse(ui.present('Which floor', exact=False), 'the floor was asked for a code that has one')
        ui.tap('Cancel', exact=True)

    @unittest.skipUnless(PHONE_HOST == '10.0.2.2', 'drives the emulator\'s camera app')
    def test_multi_across(self):
        """the user, 2026-10-10. Tags in the same place live on different drawings: in Select mode a search result (any
        drawing) adds its code without leaving the mode or the drawing, the selection survives opening another sheet,
        and the List takes typed codes (one that is on no drawing is named and left out) and shows each code's sheet.
        Then a MEMBER's Photo for all on codes without a floor: the floor is asked first, for those codes; the photo
        goes through the disk queue (it survives the app being stopped) and reaches the server for every code, with a
        floor proposal for exactly the codes that had none."""
        self.import_sheet('second', 'Second sheet')
        codes = ['11LAB70AA711', '11LAB70AA712', '11LAB70AA713', '11LAB70AA714']
        # 711 and 714 on the sample sheet, 712 and 713 on the second; only 714 has a floor
        for code, sheet, bb in ((codes[0], 'sample', [700, 300, 820, 360]), (codes[1], 'second', [400, 300, 520, 360]),
                                (codes[2], 'second', [1000, 300, 1120, 360]), (codes[3], 'sample', [700, 800, 820, 860])):
            r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': sheet, 'bbox': bb, 'kks': code, 'isa': '', 'note': ''}})
            assert r.get('status') == 'approved', r
        r = self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': codes[3], 'changes': {'floor': '2'}, 'base': {'floor': ''}}})
        assert r.get('status') == 'approved', r
        # one more code without a floor, on the second sheet: never in a photo here (picked with 713 below, while 713's floor is only in the queue)
        extra = '11LAB70AA715'
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'second', 'bbox': [700, 600, 820, 660], 'kks': extra, 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
        self.member('mira', 'Mira Member', 'mira password 1')
        w, h = map(int, re.findall(r'(\d+)x(\d+)', ui.sh('wm', 'size'))[-1])

        def tag(code):
            for n in ui.nodes():
                if ui.label(n).startswith(code + ','):
                    return n
            self.fail(f'{code} is not on screen')

        def mine(kind):
            return [x for x in self.boss.req('GET', '/api/submissions?status=open')['submissions'] if x['by'] == 'mira' and x['kind'] == kind]

        def again(what):
            """712 and 713 picked by search, Photo for all: no floor question (`what` says why); then out of the mode"""
            ui.tap('More', exact=True)
            ui.tap('Select tags', exact=True)
            for c in codes[1:3]:
                ui.type_into('Search KKS or description', c[2:])
                ui.tap(c, exact=True)
                ui.tap('Clear the search', exact=True)
            ui.find('2 selected', exact=True)
            ui.tap('Photo for all', exact=True)
            ui.find('Photo for 2 codes', exact=True, timeout=10)
            self.assertFalse(ui.present('Which floor'), what)
            ui.tap('Cancel', exact=True)
            ui.tap('Done', exact=True)
        self.join('mira', 'mira password 1')
        ui.find(codes[0] + ', ', timeout=30)
        ui.tap('More', exact=True)
        ui.tap('Select tags', exact=True)
        ui.find('0 selected', exact=True)
        x, y = ui.center(tag(codes[0]))
        ui.sh('input', 'tap', str(x), str(y))
        ui.find('1 selected', exact=True)
        # a search result on the other drawing: added; the mode and the drawing stay
        ui.type_into('Search KKS or description', codes[1][2:])
        ui.tap(codes[1], exact=True)
        ui.find('2 selected', exact=True)
        self.assertTrue(ui.present('Sample sheet', exact=True), 'the search result opened its drawing')
        self.assertFalse(ui.present('Feed water piping system'), 'the search result opened its panel')
        ui.tap('Clear the search', exact=True)
        # the selection survives opening the other drawing, where the code picked by search shows as selected
        ui.tap('Sheets', exact=True)
        ui.tap('Second sheet', exact=True)
        ui.find(codes[1] + ', ', timeout=30)
        ui.find('2 selected', exact=True)
        self.assertTrue(ui.label(tag(codes[1])).endswith(', selected'), ui.label(tag(codes[1])))
        self.assertTrue(ui.label(tag(codes[2])).endswith(', not selected'), ui.label(tag(codes[2])))
        # the List: each code with its drawing; typed codes (any case; one that is on no drawing is named, not added)
        ui.tap('List', exact=True)
        ui.find(codes[0], exact=True)
        self.assertEqual(sorted(ui.label(n) for n in ui.nodes() if ui.label(n) in ('Sample sheet', 'Second sheet')),
                         ['Sample sheet', 'Second sheet'], 'the list does not say which drawing each code is on')
        ui.type_into('Add codes', f'{codes[2].lower()},{codes[3]},11XYZ99AA999')
        ui.tap('Add', exact=True)
        ui.find('Not on any drawing, not added: 11XYZ99AA999', timeout=10)
        ui.find(codes[2], exact=True)
        ui.find(codes[3], exact=True)
        os.makedirs(SHOTS, exist_ok=True)
        with open(os.path.join(SHOTS, 'android-multi-list.png'), 'wb') as f:
            f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
        ui.tap('Close', exact=True)
        ui.find('4 selected', exact=True)
        # Photo for all: three codes have no floor, so it is asked first, naming them; 714 keeps its own
        ui.tap('Photo for all', exact=True)
        ui.find('Which floor are they on?', exact=True, timeout=10)
        ui.find(f'No floor yet: {codes[0]}, {codes[1]}, {codes[2]}.')
        ui.find('The other codes keep the floor they have.')
        with open(os.path.join(SHOTS, 'android-multi-floor.png'), 'wb') as f:
            f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
        ui.tap('Floor 4')
        ui.tap('Continue', exact=True)
        ui.find('Photo for 4 codes', exact=True, timeout=10)
        # held (debug builds): the job waits, so the app can be stopped with it queued
        ui.adb('shell', 'am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_PHOTO', '-p', PKG, '--ez', 'hold', 'true')
        ui.tap('Take a photo', exact=True)
        if ui.present('WHILE USING THE APP', exact=True):
            ui.tap('WHILE USING THE APP', exact=True)
        time.sleep(5)                                     # the emulator's camera app: shutter, then confirm
        ui.sh('input', 'tap', str(w // 2), str(int(h * 0.94)))
        time.sleep(4)
        ui.sh('input', 'tap', str(w // 2), str(int(h * 0.94)))
        ui.find('Send', exact=True, timeout=30)
        ui.tap('Send', exact=True)
        ui.find('1 photo being prepared', timeout=30)
        self.assertFalse(ui.present('4 selected', exact=True), 'still selecting after the photo was queued')
        # the floor waiting in the queue for both codes is used again without asking
        again('the floor was asked again for codes whose floor is queued with a photo')
        # … but a floor that only rides on a queued photo is not a known floor (#144): picked with a code that has
        # none anywhere, that code is asked for again, with the other (one photo carries one floor for its codes).
        # Asked for 715 alone, the title would read "Which floor is it on?"; the queued floor used again, no question
        ui.tap('More', exact=True)
        ui.tap('Select tags', exact=True)
        for c in (codes[2], extra):
            ui.type_into('Search KKS or description', c[2:])
            ui.tap(c, exact=True)
            ui.tap('Clear the search', exact=True)
        ui.find('2 selected', exact=True)
        ui.tap('Photo for all', exact=True)
        ui.find('Which floor are they on?', exact=True, timeout=10)
        ui.find(f'No floor yet: {codes[2]}, {extra}.')
        ui.tap('Cancel', exact=True)
        ui.tap('Done', exact=True)
        # the job is on disk once its .json is there (a full camera frame takes a moment to seal)
        if ui.debuggable(PKG):
            self.wait_server(lambda: any(n.endswith('.json') for n in ui.adb('exec-out', 'run-as', PKG, 'ls', 'files/photo-queue').split()),
                             'the photo for all was never written to the queue', tries=60)
        else:
            time.sleep(5)
        ui.sh('am', 'force-stop', PKG)
        time.sleep(2)
        self.assertEqual(mine('photo'), [], 'the held photo was sent')
        with self.subTest('one sealed job for all four codes'):
            if not ui.debuggable(PKG):
                self.skipTest('not a debuggable build (rehearsal/release): run-as cannot reach the queue\'s files')
            names = ui.adb('exec-out', 'run-as', PKG, 'ls', 'files/photo-queue').split()
            self.assertEqual(sorted(n.rsplit('.', 1)[1] for n in names), ['json', 'px'], f'the queued files: {names}')
            for n in names:
                raw = subprocess.run(ui.ADB + ['exec-out', 'run-as', PKG, 'cat', 'files/photo-queue/' + n], capture_output=True).stdout
                self.assertTrue(raw.startswith(b'KSL1'), f'{n} is not sealed')
                for k in codes:
                    self.assertNotIn(k.encode(), raw, f'{n} holds a code in clear text')
        # the app starts again: the queue sends it, one photo for every code
        ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
        ph = self.wait_server(lambda: (lambda p: p if len(p) >= 4 else None)(mine('photo')),
                              'the photo for all never reached the server for every code', tries=360)
        time.sleep(3)      # anything sent twice would have arrived with it
        ph = mine('photo')
        self.assertEqual(sorted(x['payload']['kks'] for x in ph), codes)
        self.assertEqual(len({x['payload']['file'] for x in ph}), 1, 'the codes did not get the same image')
        # a floor proposal for exactly the codes that had none, with the floor chosen
        fl = [x for x in mine('equipment') if 'floor' in x['payload'].get('changes', {})]
        self.assertEqual(sorted((x['payload']['kks'], x['payload']['changes']['floor']) for x in fl),
                         [(codes[0], '4'), (codes[1], '4'), (codes[2], '4')])
        ui.find('Sample sheet', timeout=20)
        self.assertFalse(ui.present('photo being prepared'), 'the queue count stayed after the photo was sent')
        self.assertFalse(ui.present('A photo was not sent'), 'the photo for all was reported as not sent')
        # the member's floor proposals are still open: the core keeps them, so the floor is not asked again
        again('the floor was asked again for codes this member has an open floor proposal for')

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
        # the code has no floor: it is asked first, and goes with the photo (request 4, 2026-10-08)
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
        ui.tap('Join through a server', exact=True)
        ui.type_into('Server address', f'{PHONE_HOST}:{self.sport}')
        ui.type_into('Username', 'boss')
        ui.type_into('Password', 'a long password')
        ui.tap('Join', exact=True)
        ui.find('Sample sheet', timeout=40)
        # the colour function on the device (its files are reached with run-as: debug builds only)
        with self.subTest('DarkColor against the Nim vectors'):
            if not ui.debuggable(PKG):
                self.skipTest('not a debuggable build (rehearsal/release): run-as cannot reach the app\'s files')
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

    def test_diagnostics(self):
        """decision 0040: the manager's phone switches reports on; an event is sealed into a report the server stores
        but can't open; the phone (holding the report key) shows it under Manage → Diagnostics. Needs the debug build
        (DebugDiagReceiver records the event: a real report waits for a real error)."""
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

    def test_systems(self):
        """Equipment by system (core systemsView): the ⋮ menu opens it; systems start closed; a header opens on a tap
        and says whether it is open; a filter opens the whole path; a code opens its tag like a search result"""
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

    def test_coverage(self):
        """the coverage dashboard (core coverageView): totals on the test plant; a sheet row opens that sheet with the
        photo colours on; a system row opens Equipment by system showing that system only"""
        self.import_sheet('second', 'Second sheet')
        # a hand-marked tag whose sheet is not in the plant data (a tag can outlive its sheet): counted, nothing to open
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'removed-sheet', 'bbox': [400, 300, 520, 360],
                                                 'kks': '11LAB70AA509', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
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
        with self.subTest('the store is wiped'):
            if not ui.debuggable(PKG):
                self.skipTest('not a debuggable build (rehearsal/release): run-as cannot read the store')
            # the store's size, 0 if the wipe removed it; anything but a number (run-as failed) fails, so an error
            # message can't pass for a small store
            size = ui.sh('run-as', PKG, 'sh', '-c', '"if [ -e files/core/kks.db ]; then stat -c %s files/core/kks.db; else echo 0; fi"').strip()
            self.assertRegex(size, r'^\d+$', 'run-as could not read the store')
            self.assertLess(int(size), 64 * 1024, 'the plant data is still on the phone')


    # ---------------------------------------------------------------- the user's requests of 2026-10-08

    def test_photo_queue(self):
        """request 1: photos go through a background queue (WorkManager): sent in order with the panel closed, kept
        across the app being stopped, a floor sent with the first photo of a code without one, failures shown"""
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
        with self.subTest('the queued files are sealed'):
            if not ui.debuggable(PKG):
                self.skipTest('not a debuggable build (rehearsal/release): run-as cannot reach the queue\'s files')
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

    def test_links_and_valve(self):
        """links between drawings (#106) and the valve type (#101, #108) on the phone, on plant data made for it: the
        sample sheet's connectors as circles (TalkBack names them) and in "Connectors on this sheet"; one target opens
        it, several ask, none says so. A valve tag's panel shows the type read from its symbol (outlined on the
        drawing), Correct type saves the person's value; a member's Confirm type waits for approval."""
        plant = os.path.join(self.dir, 'plant-data')
        cfg = os.path.join(self.dir, 'config.json')
        def plant_file(n):
            with open(os.path.join(plant, n)) as f:
                return json.load(f)

        def publish():
            r = subprocess.run([SERVER, 'publish-data', plant, '--config', cfg], cwd=self.dir, capture_output=True, text=True, timeout=60)
            self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

        def conn(label, x, y):
            return {'label': label, 'bbox': [x, y, x + 40, y + 40], 'conf': 0.9}

        # a second sheet: the sample's drawing again; C16 continues there, D2 twice there, S3 nowhere
        sheets = plant_file('sheets.json')
        sample = next(s for s in sheets if s['id'] == 'sample')
        sample['links'] = [conn('C16', 1300, 900), conn('D2', 1400, 900), conn('S3', 1500, 900)]
        linked = dict(sample, id='linked', name='Linked sheet', links=[conn('C16', 200, 200), conn('D2', 300, 200), conn('D2', 1200, 700)])
        sheets.append(linked)
        for f in os.listdir(os.path.join(plant, 'sheets')):
            if f.startswith('sample.'):
                shutil.copy(os.path.join(plant, 'sheets', f), os.path.join(plant, 'sheets', 'linked.' + f[len('sample.'):]))
        tags = plant_file('tags.json')

        def valve(i, kks, x, typ, actuator):
            return {'id': i, 'sheet': 'sample', 'kks': kks, 'suffix': '', 'isa': None, 'kind': 'equipment', 'status': 'auto',
                    'conf': 0.95, 'bbox': [x, 520, x + 120, 580], 'read': ['', ''],
                    'symbol': {'type': typ, 'actuator': actuator, 'nc': False, 'conf': 0.9, 'bbox': [x + 20, 590, x + 100, 640]}}
        tags += [valve('sample:v1', '11LAB70AA601', 700, 'gate valve', 'motor'), valve('sample:v2', '11LAB70AA602', 1000, 'globe valve', 'none')]
        with open(os.path.join(plant, 'sheets.json'), 'w') as f: json.dump(sheets, f)
        with open(os.path.join(plant, 'tags.json'), 'w') as f: json.dump(tags, f)
        publish()
        self.join()
        # the list: every connector with where it continues
        ui.tap('More', exact=True)
        ui.tap('Connectors on this sheet (3)', exact=True)
        ui.find('continues on Linked sheet')
        ui.find("the other end isn't on any drawing in the app")
        ui.tap('Connector S3', exact=True)
        ui.find("Connector S3: the other end isn't on any drawing in the app", timeout=10)
        # on the drawing (named for TalkBack): one target opens it
        ui.tap('Fit the sheet to the screen', exact=True)     # every circle on screen
        ui.tap('Connector C16, continues on Linked sheet', exact=True)
        ui.find('Connector C16 on Linked sheet', timeout=10)
        ui.find('Linked sheet', exact=True)                  # the title
        ui.tap('Fit the sheet to the screen', exact=True)
        ui.tap('Connector C16, continues on Sample sheet', exact=True)
        ui.find('Connector C16 on Sample sheet', timeout=10)
        # several: asked which, numbered
        ui.tap('Fit the sheet to the screen', exact=True)
        ui.tap('Connector D2, continues on Linked sheet', exact=True)
        ui.find('Where does D2 continue?', exact=True)
        ui.find('Linked sheet (1 of 2)', exact=True)
        ui.tap('Linked sheet (2 of 2)', exact=True)
        ui.find('Connector D2 on Linked sheet', timeout=10)
        ui.find('Connector D2, continues on Sample sheet, elsewhere on this sheet', exact=True)
        # the valve type: read from the drawing, its symbol outlined while the panel is open
        self.open_tag('11LAB70AA601')
        ui.scroll_to('Valve type: gate valve, motor-operated (from the drawing, unchecked)', exact=True)
        ui.scroll_to('90 % sure')
        from PIL import Image
        import io
        im = Image.open(io.BytesIO(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)).convert('RGB')
        os.makedirs(SHOTS, exist_ok=True)
        im.save(os.path.join(SHOTS, 'valve-type.png'))
        magenta = sum(1 for r, g, b in im.getdata() if 150 < r < 200 and g < 60 and 130 < b < 185)
        self.assertGreater(magenta, 50, 'the valve symbol is not outlined')
        ui.tap('Correct type', exact=True)
        ui.scroll_to('gate valve, motor-operated', exact=True)      # the field, holding the drawing's reading
        ui.type_into('gate valve, motor-operated', 'check valve', clear=True)
        ui.scroll_to('Send', exact=True)
        ui.tap('Send', exact=True)

        def typed():
            c = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA601', {}).get('custom') or []
            return [x for x in c if x['k'] == 'Valve type']
        self.assertEqual(self.wait_server(typed, 'the corrected valve type never reached the server'), [{'k': 'Valve type', 'v': 'check valve'}])
        ui.find('Valve type: check valve (confirmed)', exact=True, timeout=20)
        ui.find("The drawing's symbol reads: gate valve, motor-operated", exact=True)
        self.assertFalse(ui.present('Confirm type', exact=True))
        self.leave()
        # a member: Confirm type is a proposal; the panel says it waits and offers no second one
        self.member('vera', 'Vera Valve', 'vera password 1')
        self.join('vera', 'vera password 1')
        self.open_tag('11LAB70AA602')
        ui.scroll_to('Valve type: globe valve (from the drawing, unchecked)', exact=True)
        ui.scroll_to('Confirm type', exact=True)
        ui.tap('Confirm type', exact=True)
        ui.find('Your valve type “globe valve” is waiting for approval.', exact=True, timeout=20)
        self.assertFalse(ui.present('Confirm type', exact=True))
        subs = self.wait_server(lambda: [x for x in self.boss.req('GET', '/api/submissions?status=open')['submissions']
                                         if x['by'] == 'vera' and x['kind'] == 'equipment'], 'the proposal never reached the server')
        time.sleep(3)      # a second one would have arrived with it
        subs = [x for x in self.boss.req('GET', '/api/submissions?status=open')['submissions'] if x['by'] == 'vera' and x['kind'] == 'equipment']
        self.assertEqual(len(subs), 1, subs)
        self.assertEqual(subs[0]['payload']['changes']['custom'], [{'k': 'Valve type', 'v': 'globe valve'}])
        self.assertFalse(subs[0].get('note'), 'a note to the approver nobody wrote')

    @unittest.skipUnless(PHONE_HOST == '10.0.2.2', 'drives the emulator\'s camera app')
    def test_floor_first(self):
        """request 4: a code without a floor asks for it before the camera opens; Cancel opens no camera"""
        self.join()
        # a code with no tag on the drawing has no panel: the sample tag, which has no floor
        self.open_tag()
        ui.scroll_to('Take a photo', exact=True)
        ui.tap('Take a photo', exact=True)
        ui.find('Which floor is it on?', exact=True)
        ui.tap('Cancel', exact=True)
        time.sleep(2)
        self.assertTrue(ui.present('Take a photo', exact=True), 'the camera opened without a floor')
        # the photo buttons wrap: "From the gallery" is on the row under "Take a photo", below the screen's edge
        # when the swipes stopped with "Take a photo" at the bottom (run 37899373392)
        ui.scroll_to('From the gallery', exact=True)
        ui.tap('From the gallery', exact=True)
        ui.find('Which floor is it on?', exact=True)
        ui.tap('Floor 4')
        ui.tap('Continue', exact=True)
        time.sleep(2)
        self.assertFalse(ui.present('Which floor is it on?', exact=True))

    def test_approvals_grouped(self):
        """request 5: one card per code with the equipment and tag plate photos together; Approve/Reject only, unless
        several photos of one kind compete (then "Use this one", which leaves the other kind alone); the full name; the
        code opens its tag on the drawing"""
        omar = self.member('omar', 'Omar Fullname', 'omar password 1')
        for cap, tag in (('', 'eq1'), ('Tag plate', 'plate1')):
            r = omar.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': cap, 'dataUrl': self.jxl(tag)}})
            self.assertIn(r.get('status'), ('pending', 'conflict'), r)
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

    def test_position_required(self):
        """request 7: a new member's join forms need a position; an admin's Add a person too"""
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

    def test_hide_removed(self):
        """request 8: Devices → Clear removed hides removed devices (this phone's own list), Show hidden brings them back"""
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


if __name__ == '__main__':
    unittest.main()
