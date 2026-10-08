"""End-to-end: the GNOME app driven through its accessibility tree (AT-SPI), against the Nim server. No plant data:
the drawing is importer/tests/vectors/kkp-sample.pdf and the tag is added through the server.
  python3 apps/gnome/e2e/test_gnome.py [APP] [SERVER] [IMPORTER]
(defaults /tmp/kksgnome/kks_explorer, /tmp/kkslinux/kks_server, /tmp/kksimp/kks_import). Needs a graphical session
with the accessibility bus (GNOME)."""
import json, os, re, shutil, signal, subprocess, sys, tempfile, time, unittest, urllib.error, urllib.request, http.cookiejar
sys.path.insert(0, os.path.dirname(__file__))
import atspi  # noqa: E402
from gi.repository import Atspi  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
APP = sys.argv[1] if len(sys.argv) > 1 else '/tmp/kksgnome/kks_explorer'
HERE = os.path.dirname(os.path.abspath(__file__))
VENV_PY = os.path.join(HERE, '..', '..', '..', '.venv', 'bin', 'python')   # OpenCV, for the QR video
INVITE = '{"kks_invite":1,"root":"TEST-ROOT","peer":"TESTPEER","addrs":["192.0.2.1:8421"],"token":"camera-test","plant":"Camera test"}'
SERVER = sys.argv[2] if len(sys.argv) > 2 else '/tmp/kkslinux/kks_server'
IMPORTER = sys.argv[3] if len(sys.argv) > 3 else '/tmp/kksimp/kks_import'
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-gnome-shots')
del sys.argv[1:]


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


class Gnome(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-gnome-e2e-')
        cls.port, cls.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': cls.sport, 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        json.dump(cfg, open(os.path.join(cls.dir, 'config.json'), 'w'))
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
        cls.base = f'http://127.0.0.1:{cls.port}'
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager'}).get('ok')
        pdf = open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb').read()
        assert cls.boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = cls.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        # a tag on the sheet (as if someone had marked it), approved directly by the manager
        r = cls.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360],
                                                 'kks': '11LAB70AA501', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
        cls.apps = []

    @classmethod
    def tearDownClass(cls):
        for p in cls.apps:
            p.terminate()
            p.wait(5)
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def start_app(self, name, **extra):
        d = os.path.join(self.dir, name)
        os.makedirs(d, exist_ok=True)
        env = dict(os.environ, KKS_DATA_DIR=d, KKS_STORAGE_KEY_FILE=os.path.join(d, 'key'), KKS_NO_MDNS='1',
                   KKS_SYNC_PORT=str(free_port()), **extra)
        before = atspi.app_pids()
        log = open(f'/tmp/kks-gnome-e2e-{name}.log', 'w')       # the app's own output, for when a test fails
        p = subprocess.Popen([APP], env=env, stdout=log, stderr=subprocess.STDOUT)
        self.apps.append(p)
        return atspi.app_pid(p.pid, name=('walkdown', 'kks_explorer'), before=before)

    def test_scan_camera(self):
        """decision 0039: the scan dialog reads an invite from the camera; KKS_CAMERA_FILE plays a video of a QR code
        through the same GStreamer pipeline (a QR in front of a real webcam needs a person)"""
        if not os.path.exists(VENV_PY) or not shutil.which('ffmpeg'):
            self.skipTest('needs the importer .venv (OpenCV) and ffmpeg to make the QR video')
        video = os.path.join(self.dir, 'qr.mp4')
        subprocess.run([VENV_PY, os.path.join(HERE, 'make_qr_video.py'), video, INVITE], check=True)
        a = self.start_app('scanner', KKS_CAMERA_FILE=video)
        atspi.click(atspi.find(a, 'button', name='Join with a code'))
        atspi.click(atspi.find(a, 'button', name='Scan with the camera…'))
        field = atspi.find(a, 'text', name='Invite text')
        got = ''
        for _ in range(40):
            time.sleep(0.5)
            for c in [field] + list(atspi.walk(field)):
                t = c.get_text_iface()
                if t is not None and t.get_character_count():
                    got = atspi.Atspi.Text.get_text(t, 0, t.get_character_count())
            if got: break
        self.assertEqual(got, INVITE)

    def test_links(self):
        """links between drawings: a second sheet, connectors written into sheets.json (as the importer does) and
        published; "Connectors on this sheet" names each with where it continues; one target opens that sheet, none
        says so, several ask which"""
        pdf = open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb').read()
        assert self.boss.req('POST', '/api/sheets/import?id=other&name=Other%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = self.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        self.assertEqual(job['state'], 'done', job['log'])
        cfgp = os.path.join(self.dir, 'config.json')
        plant = json.load(open(cfgp))['plant_dir']
        sheets = json.load(open(os.path.join(plant, 'sheets.json')))
        def link(label, x, y, sc):   # bbox in level-0 px, like the importer's
            return {'label': label, 'bbox': [x * sc, y * sc, (x + 12) * sc, (y + 12) * sc], 'conf': 0.95}
        for sh in sheets:
            sc = sh.get('scale') or 2.0
            if sh['id'] == 'sample':
                sh['links'] = [link('C16', 100, 100, sc), link('D2', 200, 100, sc), link('A3', 300, 100, sc)]
            elif sh['id'] == 'other':
                sh['links'] = [link('C16', 150, 300, sc), link('A3', 250, 300, sc), link('A3', 350, 300, sc)]
        json.dump(sheets, open(os.path.join(plant, 'sheets.json'), 'w'))
        out = subprocess.run([SERVER, 'publish-data', plant, '--config', cfgp], cwd=self.dir, capture_output=True, text=True)
        self.assertIn('Published', out.stdout + out.stderr)
        a = self.start_app('linker')
        self.join(a)
        atspi.click(atspi.find(a, 'button', name='Sample sheet'))
        atspi.click(atspi.find(a, 'button', name='Connectors on this sheet', timeout=10))
        # each row: the connector (its name) and where it continues (read with it)
        atspi.find(a, 'label', name="the other end isn't on any drawing in the app", timeout=10)
        atspi.click(atspi.find(a, 'button', name='Connector D2', timeout=10))
        atspi.find(a, 'label', contains="D2: the other end isn't on any drawing", timeout=10)
        atspi.find(a, 'label', name='continues on Other sheet')
        atspi.click(atspi.find(a, 'button', name='Connector C16'))
        atspi.find(a, 'label', name='Connector C16 on Other sheet', timeout=10)
        # now on the other sheet: its connectors; A3 is there twice, so following one asks where to go
        atspi.click(atspi.find(a, 'button', name='Back'))
        atspi.click(atspi.find(a, 'button', name='Connectors on this sheet', timeout=10))
        atspi.find(a, 'label', name='continues on Sample sheet', timeout=10)
        atspi.find(a, 'label', name='continues on Sample sheet, elsewhere on this sheet', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Connector A3'))
        ask = atspi.find(a, 'alert', name='Where does A3 continue?', timeout=10)
        atspi.click(atspi.find(ask, 'button', name='Sample sheet'))
        atspi.find(a, 'label', name='Connector A3 on Sample sheet', timeout=10)

    def test_photo_editor(self):
        """the photo editor's controls (line sizes, zoom) are reachable; a photo goes to the server; the drawing can be
        coloured by photos. KKS_PHOTO_FILE stands in for the file chooser. (Drawing and the touch loupe need a pointer
        or a finger: not driven here.)"""
        from PIL import Image
        pic = os.path.join(self.dir, 'valve.png')
        Image.new('RGB', (640, 480), (128, 128, 128)).save(pic)
        a = self.start_app('photographer', KKS_PHOTO_FILE=pic)
        atspi.click(atspi.find(a, 'button', name='Join through a server'))
        atspi.set_text(atspi.find(a, 'text', name='Server address'), f'127.0.0.1:{self.sport}')
        atspi.set_text(atspi.find(a, 'text', name='Username'), 'boss')
        atspi.set_text(atspi.find(a, 'password text', name='Password'), 'a long password')
        atspi.click(atspi.find(a, 'button', name='Join'))
        atspi.find(a, 'list item', contains='Sample sheet', timeout=30)
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), 'LAB70AA501')
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501'))
        atspi.click(atspi.find(a, 'button', name='+ Add photo', timeout=10))
        for b in ('Thick', 'Zoom in', 'Zoom out', 'Fit the photo'):
            atspi.click(atspi.find(a, None, name=b, timeout=10))
        atspi.click(atspi.find(a, 'button', name='Add the photo'))
        for _ in range(60):
            if any(p['kks'] == '11LAB70AA501' for p in self.boss.req('GET', '/api/state')['photos']):
                break
            time.sleep(0.5)
        self.assertTrue(any(p['kks'] == '11LAB70AA501' for p in self.boss.req('GET', '/api/state')['photos']))
        atspi.click(atspi.find(a, 'button', name='Colour tags by photos'))

    def test_flow(self):
        a = self.start_app('laptop')
        # join through the server, from the setup screen
        atspi.click(atspi.find(a, 'button', name='Join through a server'))
        atspi.set_text(atspi.find(a, 'text', name='Server address'), f'127.0.0.1:{self.sport}')
        atspi.set_text(atspi.find(a, 'text', name='Username'), 'boss')
        atspi.set_text(atspi.find(a, 'password text', name='Password'), 'a long password')
        atspi.click(atspi.find(a, 'button', name='Join'))
        atspi.find(a, 'list item', contains='Sample sheet', timeout=30)
        # search finds the tag; its panel decodes it
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), 'LAB70AA501')
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501'))
        atspi.find(a, 'label', contains='Feed water piping system', timeout=10)
        # edit a field; the change reaches the server by the automatic sync
        atspi.click(atspi.find(a, 'button', name='Edit'))
        time.sleep(0.5)
        atspi.set_text(atspi.find(a, 'text', name='Notes'), 'Gland repacked; ملاحظة')
        atspi.click(atspi.find(a, 'button', name='Save'))
        for _ in range(40):
            eq = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {})
            if eq.get('notes'):
                break
            time.sleep(0.5)
        self.assertEqual(eq.get('notes'), 'Gland repacked; ملاحظة')
        # a member proposes on the server; the manager approves in the app
        r = self.boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali Member', 'role': 'user'})
        ali = Client(self.base)
        ali.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'ali password 1'})
        ali.req('POST', '/api/login', {'username': 'ali', 'password': 'ali password 1'})
        self.assertEqual(ali.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                         'changes': {'floor': '2'}}})['status'], 'pending')
        atspi.click(atspi.find(a, 'button', name='Sync now'))
        time.sleep(3)
        atspi.click(atspi.find(a, 'button', name='Manage'))
        atspi.click(atspi.find(a, 'button', name='Approvals'))
        # the page rebuilds after each sync: a click on the button it just replaced is lost (half the Flatpak runs,
        # 2026-10-04), so click again until the app says it approved
        for _ in range(5):
            atspi.click(atspi.find(a, 'button', name='Approve', timeout=15))
            try:
                atspi.find(a, 'label', name='Approved', timeout=4)
                break
            except AssertionError:
                pass
        for _ in range(40):
            subs = ali.req('GET', '/api/submissions?status=all')['submissions']
            if subs and subs[0]['status'] == 'approved':
                break
            time.sleep(0.5)
        self.assertEqual(subs[0]['status'], 'approved')
        # a second device joins with an invite (QR text)
        atspi.click(atspi.find(a, 'button', name='Back'))
        atspi.click(atspi.find(a, 'button', name='Devices'))
        atspi.click(atspi.find(a, 'button', name='Show an invite…'))
        code = None
        for _ in range(20):
            time.sleep(0.5)
            ls = [n.get_name() for n in atspi.walk(a, maxdepth=80)
                  if n.get_role_name() == 'label' and (n.get_name() or '').startswith('{"kks_invite"')]
            if ls:
                code = ls[0]
                break
        self.assertTrue(code)
        b = self.start_app('phone')
        atspi.click(atspi.find(b, 'button', name='Join with a code'))
        atspi.set_text(atspi.find(b, 'text', name='Invite text'), code)
        atspi.set_text(atspi.find(b, 'text', name='Your username'), 'sara')
        atspi.set_text(atspi.find(b, 'text', name='Your full name'), 'Sara Engineer')
        atspi.click(atspi.find(b, 'button', name='Join with this code'))
        acc = None
        for _ in range(30):
            time.sleep(0.5)
            acc = [n for n in atspi.walk(a, maxdepth=80) if n.get_role_name() == 'button' and n.get_name() == 'Accept']
            if acc:
                break
        self.assertTrue(acc, 'the admin never saw the request')
        atspi.click(acc[0])
        atspi.find(b, 'list item', contains='Sample sheet', timeout=30)
        # the manager removes the second device (Manage → Devices → Remove); it learns it at its next sync with this
        # laptop and wipes itself (§15), then starts over at the setup screen. The phone app is closed meanwhile: a
        # covered window draws nothing, and an alert dialog in it has no accessible contents until it draws.
        pb = self.apps.pop()
        pb.terminate()
        pb.wait(5)
        inv = atspi.find(a, 'dialog', name='Add a device with a QR code')
        atspi.click(atspi.find(inv, 'button', name='Close'))
        # the page rebuilds itself after each sync: a click on a row it just replaced is lost, so find it again
        dlg = None
        for _ in range(5):
            row = atspi.find(a, None, contains='· sara', timeout=15)
            atspi.click(atspi.find(row, 'button', name='Remove'))
            try:
                dlg = atspi.find(a, 'alert', name='Remove this device?', timeout=4)
                break
            except AssertionError:
                continue
        self.assertTrue(dlg, 'no alert named Remove this device?')
        atspi.click(atspi.find(dlg, 'button', name='Remove', timeout=10))
        atspi.find(a, None, contains='removed', timeout=10)
        b = self.start_app('phone')
        atspi.click(atspi.find(b, 'button', name='Sync now', timeout=15))
        note = None
        for _ in range(60):
            time.sleep(0.5)
            # the app re-executes itself after the wipe; under Flatpak it keeps the sandbox proxy's PID, so look in
            # every Walkdown app on the bus (only the removed one says this)
            for b2 in atspi.apps_named('walkdown') + atspi.apps_named('kks_explorer'):
                try:
                    note = atspi.find(b2, None, contains='removed from the plant by The Manager', timeout=1)
                    break
                except AssertionError:
                    continue
            if note:
                break
        self.assertTrue(note, 'the removed device did not wipe itself')
        self.assertNotIn(b'Sample sheet', open(os.path.join(self.dir, 'phone', 'kks.db'), 'rb').read())

    def test_systems(self):
        """Equipment by system: the page lists the code under block → system → subsystem → kind, collapsed at the
        system level; a search opens every level down to the code's row (photo dot named); the row opens the tag's
        panel"""
        a = self.start_app('systems', KKS_SYNC_EVERY='2000')   # sync rounds every 2 s: the page follows the server
        self.join(a)
        atspi.click(atspi.find(a, 'button', name='Equipment by system'))
        atspi.find(a, 'label', name='1 code on the drawings', timeout=10)
        atspi.find(a, 'list item', name='LAB · Feed water piping system', timeout=10)
        # collapsed at the system level: the code's row is not there yet. (Opening a row by hand is Enter/Space or a
        # click; its header row has no AT-SPI action, and keys can't be typed into the headless session.)
        self.assertFalse(atspi.find_all(a, contains='11LAB70AA501'))
        # the open page follows a sync without a search: a code added on the server shows up
        def add(code, bb):
            r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb,
                                                      'kks': code, 'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        add('11PAB10AP001', [600, 700, 720, 760])
        atspi.find(a, 'label', name='2 codes on the drawings', timeout=20)
        row = atspi.find(a, 'list item', contains='PAB', timeout=10)
        # but never under the focus: with the focus on a row of the tree, the next sync only marks it stale; it is
        # rebuilt when the focus leaves the tree (here: to the search field)
        try:
            focused = row.get_component_iface().grab_focus()
        except Exception:        # GTK 4's AT-SPI has no GrabFocus (2026-10-07), and keys can't be typed headless
            focused = False
        if focused:
            add('11PAB10AP002', [600, 800, 720, 860])
            time.sleep(4)
            self.assertTrue(atspi.find_all(a, 'label', contains='2 codes on the drawings'), 'rebuilt under the focus')
            atspi.find(a, 'entry', name='Search equipment by system').get_component_iface().grab_focus()
            atspi.find(a, 'label', name='3 codes on the drawings', timeout=10)
        else:
            print('note: AT-SPI could not move the focus; the focus case was not driven', file=sys.stderr)
        # a search opens every level of what it finds
        q = atspi.find(a, 'entry', name='Search equipment by system')
        atspi.set_text(q, 'nothing like this')
        atspi.find(a, 'label', name='Nothing found', timeout=10)
        atspi.set_text(q, 'feed water 70')
        atspi.find(a, 'label', name='1 code found', timeout=10)
        for level in ('LAB · Feed water piping system', 'LAB70'):
            atspi.find(a, 'list item', name=level, timeout=10)
        atspi.find(a, 'list item', contains='AA · ', timeout=10)
        item = atspi.find(a, 'list item', name='11LAB70AA501', timeout=10)
        # what Orca reads: the code (labelled by) and its description · sheet (described by)
        described = [r.get_target(i).get_name() for r in item.get_relation_set()
                     if r.get_relation_type() == Atspi.RelationType.DESCRIBED_BY for i in range(r.get_n_targets())]
        self.assertIn('Sample sheet', described)
        # the photo coverage dot, named (test_photo_editor may have added a photo of this code first)
        dots = [n.get_name() for n in atspi.walk(item) if n.get_role_name() == 'image']
        self.assertEqual(len(dots), 1)
        self.assertIn(dots[0], ('no photos', 'equipment photo only', 'tag plate photo only', 'equipment and tag plate photos'))
        before = len([n for n in atspi.find_all(a, 'label') if n.get_name() == '11LAB70AA501'])
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501', timeout=10))
        atspi.find(a, 'button', name='Close the panel', timeout=10)
        for _ in range(20):
            after = len([n for n in atspi.find_all(a, 'label') if n.get_name() == '11LAB70AA501'])
            if after > before:
                break
            time.sleep(0.5)
        self.assertGreater(after, before, 'the panel does not show the code')

    def join(self, a):
        atspi.click(atspi.find(a, 'button', name='Join through a server'))
        atspi.set_text(atspi.find(a, 'text', name='Server address'), f'127.0.0.1:{self.sport}')
        atspi.set_text(atspi.find(a, 'text', name='Username'), 'boss')
        atspi.set_text(atspi.find(a, 'password text', name='Password'), 'a long password')
        atspi.click(atspi.find(a, 'button', name='Join'))
        atspi.find(a, 'list item', contains='Sample sheet', timeout=30)

    def test_courses(self):
        """the JSON courses (decision 0036): Learning lists them; a course window with its rail; a static and an
        animated figure exposed as images; a question answered (progress shown); a driven slider moves by itself"""
        os.makedirs(SHOTS, exist_ok=True)
        shot = os.path.join(SHOTS, 'gnome-course.png')
        a = self.start_app('learner', KKS_SHOT_ON_SIGNAL=shot)
        pid = self.apps[-1].pid
        self.join(a)
        atspi.click(atspi.find(a, 'button', name='Learning'))
        atspi.find(a, None, contains='of 76 solved', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Rumaila Plant Foundations'))
        atspi.click(atspi.find(a, 'button', name='1 · Combined cycle', timeout=15))
        atspi.find(a, 'image', name='The combined cycle', timeout=10)
        atspi.click(atspi.find(a, 'button', contains='Once the gas cools below HP boiling temperature'))
        atspi.find(a, 'label', name='Right.', timeout=10)
        atspi.find(a, 'label', name='1 of 76 solved', timeout=10)
        # an animated figure with a driven slider: its value changes while it plays
        atspi.click(atspi.find(a, 'button', name='6 · Valves & pumps'))
        atspi.find(a, 'image', name='Gate valve cutaway', timeout=10)
        sl = atspi.find(a, 'slider', name='Opening', timeout=10, showing=False)
        v0 = sl.get_value_iface().get_current_value()
        time.sleep(1)
        self.assertEqual(v0, sl.get_value_iface().get_current_value(), 'a figure off screen must not move (§9.6)')
        os.kill(pid, signal.SIGUSR2)   # KKS_DEBUG_FIGURE: scroll the first animated figure on screen
        time.sleep(1)
        v1 = sl.get_value_iface().get_current_value()
        time.sleep(1.5)
        v2 = sl.get_value_iface().get_current_value()
        os.kill(pid, signal.SIGUSR1)
        time.sleep(2)
        self.assertNotAlmostEqual(v1, v2, places=3)
        self.assertTrue(os.path.exists(shot.replace('.png', '-fnd.png')))


if __name__ == '__main__':
    unittest.main()
