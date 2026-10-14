"""End-to-end: the GNOME app driven through its accessibility tree (AT-SPI), against the Nim server. No plant data:
the drawing is importer/tests/vectors/kkp-sample.pdf and the tag is added through the server.
  python3 apps/gnome/e2e/test_gnome.py [APP] [SERVER] [IMPORTER]
(defaults /tmp/kksgnome/kks_explorer, /tmp/kkslinux/kks_server, /tmp/kksimp/kks_import). Needs a graphical session
with the accessibility bus (GNOME)."""
import json, os, re, shutil, signal, subprocess, sys, tempfile, time, unittest, urllib.error, urllib.request, http.cookiejar
sys.path.insert(0, os.path.dirname(__file__))
import atspi  # noqa: E402
from gi.repository import Atspi, GLib  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
APP = sys.argv[1] if len(sys.argv) > 1 else '/tmp/kksgnome/kks_explorer'
HERE = os.path.dirname(os.path.abspath(__file__))
VENV_PY = os.path.join(HERE, '..', '..', '..', '.venv', 'bin', 'python')   # OpenCV, for the QR video
INVITE = '{"kks_invite":1,"root":"TEST-ROOT","peer":"TESTPEER","addrs":["192.0.2.1:8421"],"token":"camera-test","plant":"Camera test"}'
SERVER = sys.argv[2] if len(sys.argv) > 2 else '/tmp/kkslinux/kks_server'
IMPORTER = sys.argv[3] if len(sys.argv) > 3 else '/tmp/kksimp/kks_import'
SHOTS = os.environ.get('KKS_SHOTS', '/tmp/kks-gnome-shots')
del sys.argv[1:]


sys.path.append(os.path.join(REPO, 'tests'))
from e2e_server import free_port, start_server  # noqa: E402  (the ports and the server start of every e2e suite, #155)


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


class Plant(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-gnome-e2e-')
        cfg = {'address': '127.0.0.1', 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        cls.server, setup = start_server(SERVER, cls.dir, cfg, sync=True)
        cls.port, cls.sport = cfg['port'], cfg['sync_port']
        cls.base = f'http://127.0.0.1:{cls.port}'
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        # a floor set on the server: the apps show who set it
        assert cls.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'floor': '2'},
                             'base': {}}}).get('status') == 'approved'
        # a drafted description (descriptions.json, published with the sheet below)
        os.makedirs(cfg['plant_dir'], exist_ok=True)
        json.dump({'11LCB20AA101': {'text': 'Condensate drain valve', 'basis': 'drawing note'}},
                  open(os.path.join(cfg['plant_dir'], 'descriptions.json'), 'w'))
        pdf = open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb').read()
        assert cls.boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = cls.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        # a second sheet without tags (the Coverage page opens a sheet that isn't the one shown)
        assert cls.boss.req('POST', '/api/sheets/import?id=second&name=Second%20sheet', raw=pdf, ctype='application/pdf').get('ok')
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

    def start_app(self, name, wait=True, **extra):
        """the app on its own data folder (the same one again for the same name); wait=False: don't wait for its
        window (returns None; the process is self.apps[-1])"""
        d = os.path.join(self.dir, name)
        os.makedirs(d, exist_ok=True)
        env = dict(os.environ, KKS_DATA_DIR=d, KKS_STORAGE_KEY_FILE=os.path.join(d, 'key'), KKS_NO_MDNS='1',
                   KKS_SYNC_PORT=str(free_port()), **extra)
        before = atspi.app_pids()
        log = open(f'/tmp/kks-gnome-e2e-{name}.log', 'w')       # the app's own output, for when a test fails
        p = subprocess.Popen([APP], env=env, stdout=log, stderr=subprocess.STDOUT)
        self.apps.append(p)
        if not wait:
            return None
        return atspi.app_pid(p.pid, name=('walkdown', 'kks_explorer'), before=before)

    def criticals(self, name):
        """What went wrong inside the app, from its output (start_app's log): GTK's complaints (a call on a widget
        that was freed shows there as a failed assertion, GTK_IS_WIDGET, GTK_IS_BOX …, when it doesn't crash) and the
        errors the app caught in a handler. (Until #163 one message was left out: GTK logged "gtk_widget_is_ancestor:
        assertion 'GTK_IS_WIDGET (widget)' failed" after every rebuild of a panel that held the focus.)"""
        with open(f'/tmp/kks-gnome-e2e-{name}.log', errors='replace') as f:
            return [ln.strip() for ln in f if '-CRITICAL' in ln or 'error in a UI callback' in ln]

    def press(self, a, button, then):
        """press a button until what it leads to is there (a press within GTK's 250 ms before a reload is lost)"""
        for _ in range(5):
            try:
                atspi.click(atspi.find(a, 'button', name=button, timeout=8))
            except AssertionError:
                pass                 # (the press before did work, late: the button has gone)
            try:
                return atspi.find(a, *then, timeout=4)
            except AssertionError:
                pass
        self.fail(f'{button}: never got {then}')

    @staticmethod
    def typed(a, name):
        """what the entry of this name holds now; None when there is no such entry on the screen"""
        rows = atspi.find_all(a, 'text', name=name)
        if not rows:
            return None
        for c in atspi.walk(rows[0]):
            t = c.get_text_iface()
            if t is not None:
                return Atspi.Text.get_text(t, 0, t.get_character_count())
        return None

    def join(self, a, user='boss', password='a long password'):
        atspi.click(atspi.find(a, 'button', name='Join through a server'))
        atspi.set_text(atspi.find(a, 'text', name='Server address'), f'127.0.0.1:{self.sport}')
        atspi.set_text(atspi.find(a, 'text', name='Username'), user)
        atspi.set_text(atspi.find(a, 'password text', name='Password'), password)
        atspi.click(atspi.find(a, 'button', name='Join'))
        atspi.find(a, 'list item', contains='Sample sheet', timeout=30)

    def drawing_shot(self, a, pid, shot):
        """a screenshot of the window (KKS_SHOT_ON_SIGNAL) cropped to the drawing: (median grey, light pixels, dark
        pixels) of the sheet's area"""
        from PIL import Image
        if os.path.exists(shot):
            os.remove(shot)
        time.sleep(3)                      # the overview, then the vector tiles
        os.kill(pid, signal.SIGUSR1)
        for _ in range(40):
            time.sleep(0.25)
            if os.path.exists(shot):
                break
        time.sleep(0.5)
        view = atspi.find(a, 'image', name='Drawing Sample sheet')
        e = view.get_component_iface().get_extents(Atspi.CoordType.WINDOW)
        im = Image.open(shot).convert('RGB')
        # the middle half of the view: the sheet (fitted), not the grey around it
        box = (e.x + e.width // 4, e.y + e.height // 4, e.x + 3 * e.width // 4, e.y + 3 * e.height // 4)
        px = list(im.crop(box).get_flattened_data()) if hasattr(Image.Image, 'get_flattened_data') else list(im.crop(box).getdata())
        greys = sorted(sum(p) // 3 for p in px)
        light = sum(1 for p in px if min(p) > 170 and max(p) - min(p) < 30)
        dark = sum(1 for p in px if max(p) < 90)
        return greys[len(greys) // 2], light, dark, len(px)

    @staticmethod
    def pressed(node):
        # GTK 4 reports a toggle button's state as PRESSED (aria-pressed), not CHECKED
        st = node.get_state_set()
        return st.contains(Atspi.StateType.PRESSED) or st.contains(Atspi.StateType.CHECKED)

    def magenta(self, a, pid, shot):
        """pixels of the valve symbol's outline (dashed magenta, viewer.nim) in the drawing's part of a window shot"""
        from PIL import Image
        if os.path.exists(shot):
            os.remove(shot)
        time.sleep(1.5)
        os.kill(pid, signal.SIGUSR1)
        for _ in range(40):
            time.sleep(0.25)
            if os.path.exists(shot):
                break
        time.sleep(0.5)
        e = atspi.find(a, 'image', contains='Drawing ').get_component_iface().get_extents(Atspi.CoordType.WINDOW)
        im = Image.open(shot).convert('RGB').crop((e.x, e.y, e.x + e.width, e.y + e.height))
        px = list(im.get_flattened_data()) if hasattr(Image.Image, 'get_flattened_data') else list(im.getdata())
        # the outline's colour (176, 23, 158) within 30 on every channel: with the drawing sharp at device pixels, the
        # anti-aliased pixel where a red and a blue markup line cross came out (170, 65, 150), which `g < 70` took
        # for the outline
        return sum(1 for r, g, b in px if abs(r - 176) < 30 and abs(g - 23) < 30 and abs(b - 158) < 30)


class Gnome(Plant):
    """the app's screens, one test after another on one server: later tests see what earlier ones added"""

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
        # no tag plate photo of this code yet: the app offers one (as Android does)
        ask = atspi.find(a, 'alert', name='And its tag plate?', timeout=10)
        atspi.click(atspi.find(ask, 'button', name='Not now'))
        for _ in range(60):
            if any(p['kks'] == '11LAB70AA501' for p in self.boss.req('GET', '/api/state')['photos']):
                break
            time.sleep(0.5)
        self.assertTrue(any(p['kks'] == '11LAB70AA501' for p in self.boss.req('GET', '/api/state')['photos']))
        tb = atspi.find(a, 'toggle button', name='Colour tags by photos')
        atspi.click(tb)
        for _ in range(20):
            if tb.get_state_set().contains(Atspi.StateType.PRESSED):
                break
            time.sleep(0.3)
        self.assertTrue(tb.get_state_set().contains(Atspi.StateType.PRESSED), 'the toggle does not say it is on')

    def test_photo_queue_crash(self):
        """the photo queue survives the app ending (the user's rule: a photo is never lost). Two photos are queued and
        the app is killed (SIGKILL) before they are compressed (KKS_TEST_PHOTO_HOLD); started again, it sends the
        first and dies right after the core took it, before the queue forgot it (KKS_TEST_PHOTO_DIE_AFTER_SEND);
        started a third time, it sends the first again (kept once: its client_id) and then the second, in order."""
        from PIL import Image
        pic = os.path.join(self.dir, 'queued.png')
        Image.new('RGB', (320, 240), (90, 140, 200)).save(pic)
        a = self.start_app('crasher', KKS_PHOTO_FILE=pic, KKS_TEST_PHOTO_HOLD='1')
        self.join(a)
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), 'LAB70AA501')
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501'))
        time.sleep(2)            # the panel is built for this code
        for cap in ('queued one', 'queued two'):
            for _ in range(5):   # the panel rebuilds after a sync and when a photo is queued: a lost click is retried
                atspi.click(atspi.find(a, 'button', name='+ Add photo', timeout=10))
                try:
                    caption = atspi.find(a, 'text', name='Caption', timeout=8)
                    break
                except AssertionError:
                    continue
            atspi.set_text(caption, cap)
            atspi.click(atspi.find(a, 'button', name='Add the photo'))
            ask = atspi.find(a, 'alert', name='And its tag plate?', timeout=10)
            atspi.click(atspi.find(ask, 'button', name='Not now'))
        atspi.find(a, 'label', contains='Compressing 2 photos', timeout=10)
        first = self.apps[-1]
        first.kill()
        first.wait(10)

        def mine():
            return [p for p in self.boss.req('GET', '/api/state')['photos'] if p.get('caption', '').startswith('queued ')]
        self.start_app('crasher', wait=False, KKS_TEST_PHOTO_DIE_AFTER_SEND='1')
        second = self.apps[-1]
        second.wait(120)
        self.assertEqual(second.returncode, -signal.SIGKILL, 'the app should have died after sending the first photo')
        a = self.start_app('crasher')
        got = []
        for _ in range(120):
            got = mine()
            if len(got) >= 2:
                break
            time.sleep(0.5)
        time.sleep(6)            # a second copy of the first photo would arrive with the next sync
        got = mine()
        self.assertEqual(sorted(p['caption'] for p in got), ['queued one', 'queued two'])
        ids = {p['id']: p['caption'] for p in got}
        revs = [r for r in self.boss.req('GET', '/api/revisions?limit=200')['revisions']
                if r.get('entity') == 'photo' and r.get('key') in ids]
        self.assertEqual([ids[r['key']] for r in revs], ['queued two', 'queued one'], 'newest first: sent in the order added')
        self.assertEqual(atspi.find_all(a, 'label', contains='Compressing '), [], 'the queue is empty')
        third = self.apps[-1]    # done: its syncs must not rebuild the other tests' screens
        third.terminate()
        third.wait(10)

    def test_flow(self):
        a = self.start_app('laptop', KKS_SYNC_EVERY='2000')   # rounds every 2 s: pages must stay usable through them
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
        r = self.boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali Member', 'position': 'Technician', 'role': 'user'})
        ali = Client(self.base)
        ali.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'ali password 1'})
        ali.req('POST', '/api/login', {'username': 'ali', 'password': 'ali password 1'})
        self.assertEqual(ali.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                         'changes': {'floor': '2'}}})['status'], 'pending')
        atspi.click(atspi.find(a, 'button', name='Sync now'))
        time.sleep(3)
        atspi.click(atspi.find(a, 'button', name='Manage'))
        atspi.click(atspi.find(a, 'button', name='Approvals'))
        # the page rebuilds after a sync that brought data: a click on the button it just replaced is lost (half the Flatpak runs,
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
            ls = [nm for _, nm in atspi.nodes(a, 'label', maxdepth=80) if nm.startswith('{"kks_invite"')]
            if ls:
                code = ls[0]
                break
        self.assertTrue(code)
        b = self.start_app('phone')
        atspi.click(atspi.find(b, 'button', name='Join with a code'))
        atspi.set_text(atspi.find(b, 'text', name='Invite text'), code)
        atspi.set_text(atspi.find(b, 'text', name='Your username'), 'sara')
        atspi.set_text(atspi.find(b, 'text', name='Your full name'), 'Sara Engineer')
        # every new member needs a position (the user's request): the form refuses without one
        atspi.click(atspi.find(b, 'button', name='Join with this code'))
        atspi.find(b, 'label', contains='every new member needs a position', timeout=10)
        atspi.set_text(atspi.find(b, 'text', name='Your position (job title)'), 'Process engineer')
        atspi.click(atspi.find(b, 'button', name='Join with this code'))
        acc = None
        for _ in range(30):
            time.sleep(0.5)
            # (the Devices page is rebuilt when the request arrives: a button found may be gone when it is read, #143)
            acc = [n for n, nm in atspi.nodes(a, 'button', maxdepth=80) if nm == 'Accept']
            if acc:
                break
        self.assertTrue(acc, 'the admin never saw the request')
        # the admin sees the position the request carries
        atspi.find(a, 'label', contains='position Process engineer', timeout=10)
        atspi.click_named(a, 'button', 'Accept', maxdepth=80)
        atspi.find(b, 'list item', contains='Sample sheet', timeout=30)
        # the manager removes the second device (Manage → Devices → Remove); it learns it at its next sync with this
        # laptop and wipes itself (§15), then starts over at the setup screen. The phone app is closed meanwhile: a
        # covered window draws nothing, and an alert dialog in it has no accessible contents until it draws.
        pb = self.apps.pop()
        pb.terminate()
        pb.wait(5)
        inv = atspi.find(a, 'dialog', name='Add a device with a QR code')
        atspi.click(atspi.find(inv, 'button', name='Close'))
        # the page rebuilds itself after a sync that brought data: a click on a row it just replaced is lost, so find it again
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
        # "remove deleted users and devices": Clear removed hides the removed device; Show hidden brings it back
        # a sync round that brings nothing new leaves the page as it is: it was rebuilt after every round, and a click
        # that came in between went to the page just replaced (2 of 4 runs here: "the removed device is still listed")
        clear = atspi.find(a, 'button', name='Clear removed', timeout=10)
        log = '/tmp/kks-gnome-e2e-laptop.log'
        rounds = open(log).read().count('sync with ')
        for _ in range(40):
            if open(log).read().count('sync with ') > rounds:
                break
            time.sleep(0.25)
        self.assertGreater(open(log).read().count('sync with '), rounds, 'no sync round came')
        time.sleep(1)       # the app reloads 300 ms after a sync: wait past that before looking
        self.assertTrue(clear.get_state_set().contains(Atspi.StateType.SHOWING), 'a sync that brought nothing rebuilt the page')
        atspi.click(clear)
        for _ in range(20):
            if not atspi.find_all(a, contains='· sara'):
                break
            time.sleep(0.5)
        self.assertFalse(atspi.find_all(a, contains='· sara'), 'the removed device is still listed')
        atspi.click(atspi.find(a, None, name='Show hidden (1)', timeout=10))
        atspi.find(a, None, contains='· hidden', timeout=10)
        atspi.click(atspi.find(a, None, name='Hide hidden', timeout=10))
        # People: Sara has no active device left, so Clear removed hid her too
        atspi.click(atspi.find(a, 'button', name='Back'))
        atspi.click(atspi.find(a, 'button', name='People'))
        atspi.find(a, None, contains='The Manager (boss)', timeout=10)
        self.assertFalse(atspi.find_all(a, contains='Sara Engineer'), 'the removed person is still listed')
        atspi.click(atspi.find(a, None, name='Show hidden (1)', timeout=10))
        atspi.find(a, None, contains='Sara Engineer', timeout=10)

    def test_multi(self):
        """Select tags, then one place and one note for all of them (core /api/submit-many). Selecting: two tags by
        their search results (the keyboard's way; the headless session has no pointer to click the drawing with) and
        two through KKS_SELECT_BOX, which stands in for a box dragged with the pointer and goes through the same code
        as the drag's end (one of them has no code: it is refused, with a toast). One is unticked in the List."""
        b = self.boss
        tags = {'11LAC10AP001': [600, 300, 720, 360], '11LAC10AP002': [800, 300, 920, 360],
                '11LAC10AP003': [600, 500, 720, 560], '11LAC20AA101': [800, 500, 920, 560], '': [960, 500, 1060, 560]}
        for k, bb in tags.items():
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb, 'kks': k,
                                                                             'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAC10AP002',
                                          'changes': {'floor': '1', 'notes': 'Old note'}}})
        self.assertEqual(r.get('status'), 'approved', r)
        os.makedirs(SHOTS, exist_ok=True)
        from PIL import Image
        pic = os.path.join(self.dir, 'several.png')
        Image.new('RGB', (320, 240), (90, 120, 150)).save(pic)
        a = self.start_app('multi', KKS_SELECT_BOX='780,480,1080,580',     # 11LAC20AA101 and the unread tag
                           KKS_PHOTO_FILE=pic, KKS_MAX_PICK='3',             # the cap (200 in use), lowered
                           KKS_SHOT_ON_SIGNAL=os.path.join(SHOTS, 'gnome-multi.png'))
        pid = self.apps[-1].pid
        self.join(a)
        mode = atspi.find(a, 'toggle button', name='Select tags')
        atspi.click(mode)
        atspi.find(a, 'label', name="Tags without a code can't be selected: review them first", timeout=10)
        atspi.find(a, 'label', name='1 selected', timeout=10)
        self.assertTrue(mode.get_state_set().contains(Atspi.StateType.PRESSED))
        search = atspi.find(a, 'entry', contains='Search equipment')
        for i, k in enumerate(('11LAC10AP001', '11LAC10AP002')):
            atspi.set_text(search, k[2:])
            atspi.click(atspi.find(a, 'button', name=k, timeout=10))
            atspi.find(a, 'label', name=f'{i + 2} selected', timeout=10)
        # a fourth over the cap: not added, and said
        atspi.set_text(search, 'LAC10AP003')
        atspi.click(atspi.find(a, 'button', name='11LAC10AP003', timeout=10))
        atspi.find(a, 'label', name='At most 3 tags at once: send these first', timeout=10)
        atspi.find(a, 'label', name='3 selected', timeout=10)
        atspi.set_text(search, '')
        os.kill(pid, signal.SIGUSR1)       # a picture of the selection on the drawing, to look at
        # the List: every selected code with a switch, on; turn the box-selected one off (GTK 4 gives a check button
        # no AT-SPI action, a switch has one)
        atspi.click(atspi.find(a, 'button', name='List'))
        dlg = atspi.find(a, 'dialog', name='Selected codes', timeout=10)
        boxes = {n.get_name(): n for n in atspi.walk(dlg) if n.get_role_name() == 'switch'}
        self.assertEqual(set(boxes), {'11LAC10AP001', '11LAC10AP002', '11LAC20AA101'})
        self.assertTrue(all(x.get_state_set().contains(Atspi.StateType.CHECKED) for x in boxes.values()))
        atspi.click(boxes['11LAC20AA101'])
        atspi.find(a, 'label', name='2 selected', timeout=10)
        self.assertFalse(boxes['11LAC20AA101'].get_state_set().contains(Atspi.StateType.CHECKED))
        atspi.click(atspi.find(dlg, 'button', name='Close'))
        time.sleep(0.5)
        # Place for all: a floor; one of the two has another floor already, so the app says so before sending
        atspi.click(atspi.find(a, 'button', name='Place for all…'))
        pd = atspi.find(a, 'dialog', name='Place for all', timeout=10)
        atspi.set_text(atspi.find(pd, 'text', name='Floor'), '3')
        atspi.click(atspi.find(pd, 'button', name='Send'))
        alert = atspi.find(a, 'alert', name='Replace values?', timeout=10)
        atspi.find(alert, None, contains='1 of 2 already have a floor; it will be replaced.', timeout=5)
        atspi.click(atspi.find(alert, 'button', name='Send'))
        atspi.find(a, 'label', name='Sent for 2 codes · saved', timeout=10)
        self.assertFalse(mode.get_state_set().contains(Atspi.StateType.PRESSED), 'the mode did not end')
        want = {'11LAC10AP001': '3', '11LAC10AP002': '3', '11LAC10AP003': '', '11LAC20AA101': ''}
        for _ in range(60):
            eq = b.req('GET', '/api/state')['equipment']
            got = {k: eq.get(k, {}).get('floor', '') for k in want}
            if got == want:
                break
            time.sleep(0.5)
        self.assertEqual(got, want)
        # the server's history: a change to floor 3 for exactly those two codes, one each
        def floor(v):
            return json.loads(v).get('floor', '') if v else ''
        revs = b.req('GET', '/api/revisions?limit=500')['revisions']
        to3 = sorted(r['key'] for r in revs if r['entity'] == 'equipment' and floor(r['after']) == '3'
                     and floor(r['before']) != '3')
        self.assertEqual(to3, ['11LAC10AP001', '11LAC10AP002'])
        # Note for all: appended under each code's own note
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        for i, k in enumerate(('11LAC10AP002', '11LAC10AP003')):
            atspi.set_text(search, k[2:])
            atspi.click(atspi.find(a, 'button', name=k, timeout=10))
            atspi.find(a, 'label', name=f'{i + 1} selected', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Note for all…'))
        nd = atspi.find(a, 'dialog', name='Note for all', timeout=10)
        atspi.set_text(atspi.find(nd, 'text', name='Note'), 'Checked on the walkdown')
        atspi.click(atspi.find(nd, 'button', name='Send'))
        atspi.find(a, 'label', name='Sent for 2 codes · saved', timeout=10)
        want = {'11LAC10AP002': 'Old note\nChecked on the walkdown', '11LAC10AP003': 'Checked on the walkdown',
                '11LAC10AP001': ''}
        for _ in range(60):
            eq = b.req('GET', '/api/state')['equipment']
            got = {k: eq.get(k, {}).get('notes', '') for k in want}
            if got == want:
                break
            time.sleep(0.5)
        self.assertEqual(got, want)
        # Photo for all: one picture through the mark-up editor, a photo entry for each code (KKS_PHOTO_FILE stands in
        # for the file chooser)
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        for i, k in enumerate(('11LAC10AP001', '11LAC10AP003')):
            atspi.set_text(search, k[2:])
            atspi.click(atspi.find(a, 'button', name=k, timeout=10))
            atspi.find(a, 'label', name=f'{i + 1} selected', timeout=10)
        # a photo needs each code's floor: AP003 has none, so Photo for all asks for it first and says which code it
        # is for (AP001 keeps its floor 3); it goes with the photo
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
        dlg = atspi.find(a, 'alert', name='Which floor are they on?', timeout=10)
        atspi.find(dlg, None, contains='Floor for 11LAC10AP003: this one has none yet; the others keep theirs', timeout=5)
        atspi.set_text(atspi.find(dlg, None, name='Floor of the codes without one'), '4')
        atspi.click(atspi.find(dlg, 'button', name='Continue'))
        atspi.set_text(atspi.find(a, 'text', name='Caption', timeout=10), 'Both drains')
        atspi.click(atspi.find(a, 'button', name='Add the photo'))
        # queued like any photo (kept on disk, compressed on the worker thread), then one submit-many
        atspi.find(a, 'label', contains='Photo queued for 2 codes', timeout=10)
        for _ in range(60):
            ph = sorted(p['kks'] for p in b.req('GET', '/api/state')['photos'] if p.get('caption') == 'Both drains')
            if len(ph) >= 2:
                break
            time.sleep(0.5)
        self.assertEqual(ph, ['11LAC10AP001', '11LAC10AP003'])
        eq = b.req('GET', '/api/state')['equipment']
        self.assertEqual((eq['11LAC10AP001'].get('floor'), eq['11LAC10AP003'].get('floor')), ('3', '4'))
    def test_systems(self):
        """Equipment by system: the page lists the code under block → system → subsystem → kind, collapsed at the
        system level; a search opens every level down to the code's row (photo dot named); the row opens the tag's
        panel"""
        a = self.start_app('systems', KKS_SYNC_EVERY='2000')   # sync rounds every 2 s: the page follows the server
        self.join(a)
        atspi.click(atspi.find(a, 'button', name='Equipment by system'))
        # the sample sheet's one code, plus the tags other tests on this server marked by hand (test_multi)
        n = len({'11LAB70AA501'} | {t['kks'] + (t.get('suffix') or '') for t in self.boss.req('GET', '/api/state').get('added_tags', [])
                                    if t.get('kks')})
        on = lambda k: f'{k} code{"" if k == 1 else "s"} on the drawings'
        atspi.find(a, 'label', name=on(n), timeout=10)
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
        atspi.find(a, 'label', name=on(n + 1), timeout=20)
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
            self.assertTrue(atspi.find_all(a, 'label', contains=on(n + 1)), 'rebuilt under the focus')
            atspi.find(a, 'entry', name='Search equipment by system').get_component_iface().grab_focus()
            atspi.find(a, 'label', name=on(n + 2), timeout=10)
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
        before = len(atspi.find_all(a, 'label', name='11LAB70AA501'))
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501', timeout=10))
        atspi.find(a, 'button', name='Close the panel', timeout=10)
        for _ in range(20):
            after = len(atspi.find_all(a, 'label', name='11LAB70AA501'))
            if after > before:
                break
            time.sleep(0.5)
        self.assertGreater(after, before, 'the panel does not show the code')

    def test_dark_drawings(self):
        """Dark drawings: the header's toggle turns the sheet light-on-dark at once (dark paper, light lines), off
        restores it, and the choice survives a restart of the app"""
        os.makedirs(SHOTS, exist_ok=True)
        shot = os.path.join(SHOTS, 'gnome-dark.png')
        a = self.start_app('darkdrawings', KKS_SHOT_ON_SIGNAL=shot)
        pid = self.apps[-1].pid
        self.join(a)
        med, light, dark, n = self.drawing_shot(a, pid, shot)
        self.assertGreater(med, 200, 'light mode: white paper')
        self.assertGreater(dark, 0, 'light mode: dark lines')
        toggle = atspi.find(a, 'toggle button', name='Dark drawings')
        self.assertFalse(self.pressed(toggle))
        atspi.click(toggle)
        med, light, dark, n = self.drawing_shot(a, pid, shot)
        shutil.copy(shot, os.path.join(SHOTS, 'gnome-dark-on.png'))
        self.assertLess(med, 40, 'dark mode: dark paper')
        self.assertGreater(light, 0, 'dark mode: light lines')
        self.assertTrue(self.pressed(toggle))
        atspi.click(atspi.find(a, 'toggle button', name='Dark drawings'))
        med, light, dark, n = self.drawing_shot(a, pid, shot)
        self.assertGreater(med, 200, 'off again: white paper')
        atspi.click(atspi.find(a, 'toggle button', name='Dark drawings'))
        time.sleep(1)
        # a restart keeps it (this device's store)
        p = self.apps.pop()
        p.terminate()
        p.wait(5)
        a = self.start_app('darkdrawings', KKS_SHOT_ON_SIGNAL=shot)
        pid = self.apps[-1].pid
        toggle = atspi.find(a, 'toggle button', name='Dark drawings', timeout=20)
        self.assertTrue(self.pressed(toggle), 'the toggle is on after a restart')
        med, light, dark, n = self.drawing_shot(a, pid, shot)
        shutil.copy(shot, os.path.join(SHOTS, 'gnome-dark-restart.png'))
        self.assertLess(med, 40, 'after a restart: still dark')
        self.assertGreater(light, 0)

    def test_valve_type(self):
        """The valve type read from a drawn symbol (tags.json "symbol", core tagView's valve_type): the panel says
        "(from the drawing, unchecked)" and the symbol is outlined while the panel is open; Confirm saves it as it is,
        Correct saves the edited value (the equipment custom field "Valve type"); then the panel shows it confirmed.
        (Named to run after test_systems, which counts the codes on this shared server.)"""
        # two valve tags with their symbols, added to the imported sample sheet and published again
        pd = os.path.join(self.dir, 'plant-data')
        with open(os.path.join(pd, 'tags.json')) as f:
            tags = json.load(f)
        with open(os.path.join(pd, 'sheets.json')) as f:
            sh = [x for x in json.load(f) if x['id'] == 'sample'][0]
        cx, cy = sh['w'] // 2, sh['h'] // 2
        for i, (code, typ, nc) in enumerate((('11LBA10AA101', 'gate valve', False), ('11LBA10AA102', 'globe valve', True))):
            x = cx + i * 400
            tags.append({'id': f'sample:v{i}', 'sheet': 'sample', 'kks': code, 'suffix': '', 'isa': None, 'kind': 'equipment',
                         'status': 'auto', 'conf': 0.9, 'bbox': [x, cy, x + 120, cy + 50], 'read': ['', ''],
                         'symbol': {'type': typ, 'actuator': 'motor' if i == 0 else 'none', 'nc': nc, 'conf': 0.9,
                                    'bbox': [x + 10, cy - 90, x + 110, cy - 20]}})
        with open(os.path.join(pd, 'tags.json'), 'w') as f:
            json.dump(tags, f)
        r = subprocess.run([SERVER, 'publish-data', pd, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        os.makedirs(SHOTS, exist_ok=True)
        shot = os.path.join(SHOTS, 'gnome-valve.png')
        a = self.start_app('valve', KKS_SHOT_ON_SIGNAL=shot, KKS_SYNC_EVERY='2000')
        pid = self.apps[-1].pid
        self.join(a)
        def custom(code):        # saved in the app's own node first, then on the server by sync
            for _ in range(40):
                c = self.boss.req('GET', '/api/state')['equipment'].get(code, {}).get('custom')
                if c:
                    return c
                time.sleep(0.5)
        q = atspi.find(a, 'entry', contains='Search equipment')

        def press(button, then):
            # the panel is rebuilt when a sync brings something for it: a click on the button it just replaced is
            # lost, so again
            for _ in range(5):
                atspi.click(atspi.find(a, 'button', name=button, timeout=15))
                try:
                    return atspi.find(a, *then, timeout=4)
                except AssertionError:
                    pass
            self.fail(f'{button}: never got {then}')

        def cancel_edit():
            # the Edit form's Cancel (the panel's, not another page's): until the form is gone
            for _ in range(5):
                for c in atspi.find_all(a, 'button', name='Cancel'):
                    atspi.click(c)
                    time.sleep(1)
                    if not atspi.find_all(a, 'text', contains='Notes'):
                        return
            self.fail('the Edit form did not close')

        def open_tag(code):
            for _ in range(20):          # the new tags.json reaches the app by sync
                atspi.set_text(q, code)
                time.sleep(1)
                if atspi.find_all(a, 'button', contains=code):
                    break
            atspi.click(atspi.find(a, 'button', name=code))
        # the gate valve: unchecked, its symbol outlined; Confirm sends it as it is
        open_tag('11LBA10AA101')
        atspi.find(a, 'label', name='Valve type: gate valve, motor-operated (from the drawing, unchecked)', timeout=15)
        self.assertGreater(self.magenta(a, pid, shot), 50, 'the symbol is outlined while the panel is open')
        shutil.copy(shot, os.path.join(SHOTS, 'gnome-valve-open.png'))
        atspi.click(atspi.find(a, 'button', name='Close the panel'))
        self.assertEqual(self.magenta(a, pid, shot), 0, 'no outline once the panel is closed')
        open_tag('11LBA10AA101')
        press('Confirm type', ('label', 'Valve type: gate valve, motor-operated (confirmed)'))
        self.assertEqual(custom('11LBA10AA101'), [{'k': 'Valve type', 'v': 'gate valve, motor-operated'}])
        self.assertEqual(self.magenta(a, pid, shot), 0, 'a confirmed type has no symbol to point at')
        # the hatched globe valve: Correct, a value of the person's own, Send
        open_tag('11LBA10AA102')
        atspi.find(a, 'label', name='Valve type: globe valve, normally closed (from the drawing, unchecked)', timeout=15)
        # #147: a sync round that brings nothing leaves the panel as it is. It used to be rebuilt after every round,
        # and a button pressed within GTK's 250 ms before that was lost with the old panel (the presses below came
        # in step with the rounds, five lost in a row). The rounds are read from the app's own output.
        log = '/tmp/kks-gnome-e2e-valve.log'          # (start_app)
        def rounds():
            with open(log) as f:
                return [tuple(int(x) for x in m.groups()) for m in
                        re.finditer(r'sent (\d+), received (\d+) \(photos sent (\d+), received (\d+)\)', f.read())]
        def until(cond, what, timeout=40):
            t0 = time.time()
            while not cond():
                self.assertLess(time.time() - t0, timeout, what)
                time.sleep(0.2)
        quiet = lambda r: len(r) >= 2 and not any(r[-1]) and not any(r[-2])
        for attempt in range(5):
            until(lambda: quiet(rounds()), 'two sync rounds in a row that bring nothing')
            time.sleep(0.6)                      # the reload comes 300 ms after a round
            n = len(rounds())                    # (before the lookup: a round that ends during it counts as after)
            edit = atspi.find(a, 'button', name='Edit')
            until(lambda: len(rounds()) >= n + 2, 'two more sync rounds')
            time.sleep(0.6)
            if not any(x for r in rounds()[n:] for x in r):
                break                            # (else something did arrive in between: once more)
        else:
            self.fail('the sync rounds never went quiet')
        st = edit.get_state_set()
        self.assertTrue(st.contains(Atspi.StateType.SHOWING) and not st.contains(Atspi.StateType.DEFUNCT),
                        'two sync rounds that brought nothing replaced the panel (its Edit button is gone)')
        self.assertEqual(atspi.find(a, 'button', name='Edit'), edit, 'the Edit button is another one than before the rounds')
        # not while the Edit form is open: sending rebuilds the panel, which would lose what is typed there
        press('Edit', ('text', 'Notes'))
        atspi.set_text(atspi.find(a, 'text', name='Notes'), 'half typed')
        atspi.click(atspi.find(a, 'button', name='Confirm type'))
        time.sleep(1.5)
        self.assertTrue(atspi.find_all(a, 'text', contains='Notes'), 'Confirm type rebuilt the panel under the Edit form')
        self.assertIsNone(self.boss.req('GET', '/api/state')['equipment'].get('11LBA10AA102', {}).get('custom'))
        cancel_edit()
        press('Correct type', ('text', 'Valve type'))
        # the sync rounds (every 2 s here) bring the confirmed gate valve back from the server: the open form stays
        time.sleep(5)
        self.assertTrue(atspi.find_all(a, 'text', contains='Valve type'), 'a sync rebuilt the panel under the form')
        # (a toast's title is Pango markup: the typed "&" must not blank it)
        atspi.set_text(atspi.find(a, 'text', name='Valve type'), 'check & lift valve')
        atspi.click(atspi.find(a, 'button', name='Send'))
        atspi.find(a, 'label', name='Valve type: check & lift valve (confirmed)', timeout=15)
        atspi.find(a, None, contains='Saved: 11LBA10AA102 valve type: check & lift valve', timeout=5)
        atspi.find(a, None, contains="The drawing's symbol reads: globe valve, normally closed", timeout=10)
        self.assertEqual(custom('11LBA10AA102'), [{'k': 'Valve type', 'v': 'check & lift valve'}])
        # the same for the panel's Edit form (found with this test: every sync round rebuilt the panel under it)
        press('Edit', ('text', 'Notes'))
        self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LBA10AA101', 'changes': {'floor': '3'}}})
        time.sleep(6)
        self.assertTrue(atspi.find_all(a, 'text', contains='Notes'), 'a sync rebuilt the panel under the Edit form')
        cancel_edit()
        # and a round that does bring something for the open panel shows it (no form open now)
        r = self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LBA10AA102', 'changes': {'near': 'by the test pump'}}})
        self.assertEqual(r.get('status'), 'approved', r)
        atspi.find(a, 'label', contains='by the test pump', timeout=20)
        # GTK had nothing to complain about on the way (#163: it logged a failed assertion after each of the rebuilds
        # above that took the focused button or entry away)
        self.assertEqual(self.criticals('valve'), [])

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
        # the fourth course (Instrumentation and control) opens, and a page of it shows its figure
        atspi.click(atspi.find(a, 'button', name='Instrumentation and control'))
        atspi.click(atspi.find(a, 'button', name='1 · The loop', timeout=15))
        atspi.find(a, 'image', name='A control loop: drum level', timeout=10)
        # a table is as tall as its rows: the paragraph after it starts right below its last row. (A table with
        # sentences in its cells was given thousands of pixels of empty card below the last row, 2026-10-12.)
        def top(text):
            return atspi.find(a, 'label', contains=text, showing=False).get_component_iface().get_extents(Atspi.CoordType.WINDOW).y
        gap = top('A sensor is an input transducer') - top('pneumatic diaphragm, electric motor')
        self.assertTrue(0 < gap < 150, f'{gap} px from the last row of "The parts" to the paragraph after the table')
        # a photo keeps its shape: a 4:3 picture in the wider box the page gives it has the page's background left and
        # right of it. (Every course photo was stretched to fill its box, 2026-10-13.) The page's animated figure is
        # scrolled into view (SIGUSR2); the photo is the next block.
        from PIL import Image
        atspi.click(atspi.find(a, 'button', name='7 · The four measurements'))
        pic = atspi.find(a, 'image', contains='Differential pressure transmitter', timeout=10, showing=False)
        inc_shot = shot.replace('.png', '-inc.png')
        if os.path.exists(inc_shot):
            os.remove(inc_shot)
        time.sleep(1)                  # the page is laid out (SIGUSR2 scrolls nothing before that)
        os.kill(pid, signal.SIGUSR2)
        time.sleep(1.5)
        os.kill(pid, signal.SIGUSR1)
        for _ in range(40):
            time.sleep(0.25)
            if os.path.exists(inc_shot):
                break
        time.sleep(0.5)
        e = pic.get_component_iface().get_extents(Atspi.CoordType.WINDOW)
        im = Image.open(inc_shot).convert('L')
        self.assertGreater(e.width, e.height * 1.5, 'the box is wider than 4:3, or this check proves nothing')
        top, bottom = max(e.y, 60) + 10, min(e.y + e.height, im.height) - 10
        self.assertGreater(bottom - top, 60, f'the photo is not on screen: {e.x},{e.y} {e.width}x{e.height} in {im.size}')
        for x0 in (e.x + 6, e.x + e.width - 36):
            band = im.crop((x0, top, x0 + 30, bottom))
            lo, hi = band.getextrema()
            self.assertLess(hi - lo, 12, f'the photo fills its box from edge to edge (greys {lo} to {hi} at x={x0}): stretched')
        mid = im.crop((e.x + e.width // 2 - 100, top, e.x + e.width // 2 + 100, bottom)).getextrema()
        self.assertGreater(mid[1] - mid[0], 40, 'no photo in the middle of its box')
        # a number stays on one line with its unit (docs/COURSES.md §3): the run's spaces are no-break spaces in what
        # the label lays out (the layout itself at every width: tests/test_coursetext.nim)
        atspi.click(atspi.find(a, 'button', name='5 · Strain gauges & RTDs'))
        para = atspi.find(a, 'label', contains='a platinum element with', timeout=10, showing=False).get_name()
        self.assertIn('0.385\u00a0Ω\u00a0per\u00a0°C', para)
        self.assertIn('100.0\u00a0Ω', para)
        # a question's heading is shown as written: the placement test names each question's module, and in capitals
        # "4 · 4–20 mA" read "4–20 MA"
        # (this course's window: the Foundations window is still open, with a Placement test of its own)
        inc = [a.get_child_at_index(i) for i in range(a.get_child_count())
               if atspi.find_all(a.get_child_at_index(i), 'button', name='4 · 4–20 mA')]
        self.assertEqual(len(inc), 1, 'the Instrumentation and control window')
        inc = inc[0]
        # a number column's short cell is one line too ("12 mA" in a table of this course's module 4)
        atspi.click(atspi.find(inc, 'button', name='4 · 4–20 mA'))
        atspi.find(inc, 'label', name='12\u00a0mA', timeout=10, showing=False)
        atspi.click(atspi.find(inc, 'button', name='Placement test'))
        atspi.find(inc, 'label', contains=' · 4 · 4–20 mA', timeout=10, showing=False)
        self.assertFalse(atspi.find_all(a, 'label', contains='4–20 MA') or
                         [n for _, n in atspi.nodes(a, 'label') if '4–20 MA' in n], 'a question heading in capitals')
        # In the dark theme a photo's credit can be read, and its licence link has the accent colour at full strength
        # (as a dim label the whole line was drawn at 55 % opacity, the link with it: 2026-10-13). The same person's
        # app again, dark; KKS_TEST_SCROLL=credit makes SIGUSR2 bring the page's first credit on screen.
        self.apps[-1].terminate()
        self.apps[-1].wait(10)
        dark_shot = os.path.join(SHOTS, 'gnome-course-dark.png')
        a = self.start_app('learner', KKS_SHOT_ON_SIGNAL=dark_shot, ADW_DEBUG_COLOR_SCHEME='prefer-dark', KKS_TEST_SCROLL='credit')
        pid = self.apps[-1].pid
        atspi.find(a, 'list item', contains='Sample sheet', timeout=30)
        atspi.click(atspi.find(a, 'button', name='Learning'))
        atspi.click(atspi.find(a, 'button', name='Instrumentation and control', timeout=15))
        atspi.click(atspi.find(a, 'button', name='5 · Strain gauges & RTDs', timeout=15))
        credit = atspi.find(a, 'label', contains='Photo: Pleriche', timeout=10, showing=False)
        inc_dark = dark_shot.replace('.png', '-inc.png')
        if os.path.exists(inc_dark):
            os.remove(inc_dark)
        time.sleep(1)
        os.kill(pid, signal.SIGUSR2)
        time.sleep(1.5)
        os.kill(pid, signal.SIGUSR1)
        for _ in range(40):
            time.sleep(0.25)
            if os.path.exists(inc_dark):
                break
        time.sleep(0.5)
        e = credit.get_component_iface().get_extents(Atspi.CoordType.WINDOW)
        im = Image.open(inc_dark).convert('RGB')
        self.assertTrue(0 < e.y < im.height - e.height and e.height > 8, f'the credit is not on screen: {e.x},{e.y} {e.width}x{e.height}')
        crop = im.crop((e.x, e.y, e.x + e.width, e.y + e.height))
        px = list(crop.get_flattened_data()) if hasattr(Image.Image, 'get_flattened_data') else list(crop.getdata())
        back = max(set(px), key=px.count)
        self.assertLess(max(back), 90, f'not the dark theme: the page is {back}')
        grey = max(min(p) for p in px if max(p) - min(p) < 12)           # the plain text at its lightest
        link = max(px, key=lambda p: max(p) - min(p))                   # the link: the most coloured pixel
        self.assertGreater(grey, 175, f'the credit\'s text is too faint on the dark page (lightest grey {grey} on {back})')
        self.assertGreater(max(link), 165, f'the credit\'s link is dimmed with its line ({link})')
        # closing the main window closes its course windows too (#163): they kept the app running, and a code's link
        # in them then opened its tag in the main window that was gone
        wins = [a.get_child_at_index(i) for i in range(a.get_child_count())]
        main = [x for x in wins if not any(n.get_name() == '5 · Strain gauges & RTDs' for n in atspi.walk(x))]
        self.assertEqual((len(wins), len(main)), (2, 1), 'the main window and the course window')
        atspi.click(atspi.find(main[0], 'button', name='Close'))
        try:
            self.apps[-1].wait(15)
        except subprocess.TimeoutExpired:
            self.fail('the app kept running with its course window after the main window was closed')

    def test_zzz_multi_member(self):
        """A MEMBER's "Photo for all" (their changes wait for approval), with codes of two drawings (runs last: its
        open proposals would show in the lists the other tests count). A search result of another drawing joins the
        selection without leaving the mode or the open drawing; the selection survives a change of drawing; codes
        typed into the List join it (one that is on no drawing is named); the List says which drawings a code is on.
        Photo for all asks for the floor first, for the codes without one: every code gets the photo, and each code
        without a floor a floor proposal."""
        b = self.boss
        for sheet, k, bb in (('sample', '11LAD10AP001', [200, 100, 320, 160]), ('second', '11LAD10AP001', [600, 100, 720, 160]),
                             ('second', '11LAD10AP002', [200, 100, 320, 160]), ('second', '11LAD10AP003', [400, 100, 520, 160])):
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': sheet, 'bbox': bb, 'kks': k, 'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAD10AP003', 'changes': {'floor': '5'}}})
        self.assertEqual(r.get('status'), 'approved', r)
        r = b.req('POST', '/api/users', {'username': 'mina', 'full_name': 'Mina Tech', 'position': 'Technician', 'role': 'user'})
        self.assertTrue(Client(self.base).req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1],
                                                                              'password': 'mina password 1'}).get('ok'))
        from PIL import Image
        pic = os.path.join(self.dir, 'corner.png')
        Image.new('RGB', (320, 240), (150, 120, 90)).save(pic)
        a = self.start_app('member', KKS_PHOTO_FILE=pic)
        self.join(a, 'mina', 'mina password 1')
        atspi.find(a, 'image', name='Drawing Sample sheet', timeout=15)
        mode = atspi.find(a, 'toggle button', name='Select tags')
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        search = atspi.find(a, 'entry', contains='Search equipment')
        # a code of another drawing, from its search result: selected, said, and the open drawing stays
        atspi.set_text(search, 'LAD10AP002')
        atspi.click(atspi.find(a, 'button', name='11LAD10AP002', timeout=10))
        atspi.find(a, 'label', name='11LAD10AP002 selected (on Second sheet) · 1 selected', timeout=10)
        atspi.find(a, 'label', name='1 selected', timeout=10)
        atspi.find(a, 'image', name='Drawing Sample sheet', timeout=5)
        self.assertTrue(self.pressed(mode))
        atspi.set_text(search, 'LAD10AP001')
        atspi.click(atspi.find(a, 'button', name='11LAD10AP001', timeout=10))
        atspi.find(a, 'label', name='2 selected', timeout=10)
        # the selection survives a change of drawing
        atspi.set_text(search, '')
        atspi.click(atspi.find(a, 'button', name='Second sheet', timeout=10))
        atspi.find(a, 'image', name='Drawing Second sheet', timeout=15)
        atspi.find(a, 'label', name='2 selected', timeout=10)
        self.assertTrue(self.pressed(mode))
        atspi.click(atspi.find(a, 'button', name='Sample sheet', timeout=10))
        atspi.find(a, 'image', name='Drawing Sample sheet', timeout=15)
        atspi.find(a, 'label', name='2 selected', timeout=10)
        # the List: the drawings each code is on; codes typed in (any case), one of them on no drawing
        atspi.click(atspi.find(a, 'button', name='List'))
        dlg = atspi.find(a, 'dialog', name='Selected codes', timeout=10)
        atspi.find(dlg, None, contains='Sample sheet, Second sheet', timeout=5)
        atspi.set_text(atspi.find(dlg, 'text', name='KKS codes'), '11lad10ap003, 99XXX99XX999 11LAD10AP002')
        atspi.click(atspi.find(dlg, 'button', name='Add codes'))
        atspi.find(dlg, 'label', name='Added 1 code. Not on any drawing, not added: 99XXX99XX999.', timeout=10)
        atspi.find(a, 'label', name='3 selected', timeout=10)
        for _ in range(20):
            boxes = {n.get_name() for n in atspi.walk(dlg) if n.get_role_name() == 'switch'}
            if len(boxes) == 3:
                break
            time.sleep(0.25)
        self.assertEqual(boxes, {'11LAD10AP001', '11LAD10AP002', '11LAD10AP003'})
        atspi.click(atspi.find(dlg, 'button', name='Close'))
        time.sleep(0.5)
        # Photo for all: the floor first, for the two codes without one (AP003 has floor 5)
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
        fd = atspi.find(a, 'alert', name='Which floor are they on?', timeout=10)
        atspi.find(fd, None, contains='Floor for 11LAD10AP002, 11LAD10AP001: these have none yet; the others keep theirs', timeout=5)
        atspi.set_text(atspi.find(fd, None, name='Floor of the codes without one'), '4')
        atspi.click(atspi.find(fd, 'button', name='Continue'))
        atspi.set_text(atspi.find(a, 'text', name='Caption', timeout=10), 'Same corner')
        atspi.click(atspi.find(a, 'button', name='Add the photo'))
        atspi.find(a, 'label', contains='Photo queued for 3 codes', timeout=10)
        three = ['11LAD10AP001', '11LAD10AP002', '11LAD10AP003']
        for _ in range(120):
            subs = b.req('GET', '/api/submissions?status=all')['submissions']
            photos = [x for x in subs if x['kind'] == 'photo' and x['payload'].get('caption') == 'Same corner']
            floors = {x['payload']['kks']: (x['payload']['changes'], x['status']) for x in subs
                      if x['kind'] == 'equipment' and x['payload']['kks'] in three and x['status'] == 'pending'}
            if len(photos) >= 3 and len(floors) >= 2:
                break
            time.sleep(0.5)
        self.assertEqual(sorted(x['payload']['kks'] for x in photos), three)
        self.assertEqual({x['status'] for x in photos}, {'pending'})
        self.assertEqual(len({x['payload']['file'] for x in photos}), 1)
        self.assertEqual(floors, {'11LAD10AP001': ({'floor': '4'}, 'pending'), '11LAD10AP002': ({'floor': '4'}, 'pending')})
        self.assertNotEqual(b.req('GET', '/api/state')['equipment']['11LAD10AP003'].get('floor'), '4')
        # the floors are known now (their own open proposals): the next Photo for all asks for none
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        atspi.set_text(search, 'LAD10AP002')
        atspi.click(atspi.find(a, 'button', name='11LAD10AP002', timeout=10))
        atspi.find(a, 'label', name='1 selected', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
        atspi.find(a, 'text', name='Caption', timeout=10)
        self.assertEqual(atspi.find_all(a, 'alert', name='Which floor are they on?'), [])

    def test_zz_requests(self):
        """the user's requests of 2026-10-08 (runs last: it adds codes test_systems would count). Who took the photo
        and set a field; drafted descriptions; the floor before a photo; the photo queue; approvals per code and kind;
        my proposals' filters; the leaderboard; a position for a new plant's manager."""
        import base64
        from PIL import Image
        for code, bb in (('11LCB20AA101', [600, 400, 720, 460]), ('11LCB20AA102', [600, 500, 720, 560])):
            r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb,
                                                      'kks': code, 'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        # a member proposes two equipment photos and a tag plate photo of one code
        r = self.boss.req('POST', '/api/users', {'username': 'omar', 'full_name': 'Omar Tech', 'position': 'Technician', 'role': 'user'})
        omar = Client(self.base)
        omar.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'omar password 1'})
        omar.req('POST', '/api/login', {'username': 'omar', 'password': 'omar password 1'})
        for f, cap in (('fnd-05.jxl', 'pump side'), ('ppt-01.jxl', 'pump front'), ('ppt-02.jxl', 'Tag plate of the pump')):
            data = open(os.path.join(REPO, 'data', 'courses', f), 'rb').read()
            r = omar.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': cap,
                         'dataUrl': 'data:image/jxl;base64,' + base64.b64encode(data).decode()}})
            self.assertEqual(r.get('status'), 'pending', r)
        pic = os.path.join(self.dir, 'noisy.png')        # big and noisy: compressing takes a moment
        Image.effect_noise((2400, 1800), 40).convert('RGB').save(pic)
        a = self.start_app('requests', KKS_PHOTO_FILE=pic)
        self.join(a)
        q = atspi.find(a, 'entry', contains='Search equipment')
        # who set a field: the floor the manager set on the server
        atspi.set_text(q, 'LAB70AA501')
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501'))
        atspi.find(a, None, contains='\nby The Manager, ', timeout=10)
        # a drafted description: shown unchecked, confirmed in one click, then who confirmed it
        atspi.set_text(q, 'LCB20AA101')
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name='11LCB20AA101'))
        atspi.find(a, 'label', name='Draft description (unchecked)', timeout=10)
        atspi.find(a, None, name='Condensate drain valve', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Confirm description'))
        atspi.find(a, None, contains='Confirmed by The Manager', timeout=15)
        for _ in range(40):
            eq = self.boss.req('GET', '/api/state')['equipment'].get('11LCB20AA101', {})
            if eq.get('custom'):
                break
            time.sleep(0.5)
        self.assertEqual(eq.get('custom'), [{'k': 'Description', 'v': 'Condensate drain valve'}])
        # the floor before a photo: asked first for a code without one; two photos queue and are sent in order, also
        # with the panel closed
        atspi.set_text(q, 'LCB20AA102')
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name='11LCB20AA102'))
        time.sleep(2)            # the panel is rebuilt for this code (the last one's buttons go)
        for cap in ('first', 'second'):
            # the panel rebuilds when a photo is queued and after each sync: a click on the button it just replaced is
            # lost, so click again until the floor question or the editor shows
            for _ in range(5):
                atspi.click(atspi.find(a, 'button', name='+ Add photo', timeout=10))
                if cap == 'first':
                    try:
                        dlg = atspi.find(a, 'alert', name='Which floor is 11LCB20AA102 on?', timeout=5)
                    except AssertionError:
                        continue
                    atspi.set_text(atspi.find(dlg, None, name='Floor of 11LCB20AA102'), '3')
                    atspi.click(atspi.find(dlg, 'button', name='Continue'))
                try:
                    caption = atspi.find(a, 'text', name='Caption', timeout=8)
                    break
                except AssertionError:
                    continue
            self.assertFalse(cap == 'second' and atspi.find_all(a, 'alert'), 'the floor was asked twice')
            atspi.set_text(caption, cap)
            atspi.click(atspi.find(a, 'button', name='Add the photo'))
            # no tag plate photo yet: offered after each equipment photo; the second time it is taken
            ask = atspi.find(a, 'alert', name='And its tag plate?', timeout=10)
            if cap == 'first':
                atspi.click(atspi.find(ask, 'button', name='Not now'))
                continue
            atspi.click(atspi.find(ask, 'button', name='Add it'))
            atspi.find(a, None, name='Add a tag plate photo', timeout=15)
            atspi.set_text(atspi.find(a, 'text', name='Caption', timeout=10), 'plate')
            atspi.click(atspi.find(a, 'button', name='Add the photo'))
        atspi.click(atspi.find(a, 'button', name='Close the panel'))
        atspi.find(a, 'label', contains='Compressing ', timeout=5)
        # closing the window now would lose them: the app asks first
        atspi.click(atspi.find(a, 'button', name='Close', timeout=5))
        ask = atspi.find(a, 'alert', contains='still being prepared', timeout=5)
        atspi.click(atspi.find(ask, 'button', name='Wait'))
        caps = {}
        for _ in range(120):
            st = self.boss.req('GET', '/api/state')
            caps = {p['id']: p['caption'] for p in st['photos'] if p['kks'] == '11LCB20AA102'}
            if len(caps) == 3:
                break
            time.sleep(0.5)
        self.assertEqual(sorted(caps.values()), ['Tag plate · plate', 'first', 'second'])
        self.assertEqual(st['equipment']['11LCB20AA102'].get('floor'), '3')
        revs = [r for r in self.boss.req('GET', '/api/revisions?limit=200')['revisions'] if r.get('entity') == 'photo' and r.get('key') in caps]
        self.assertEqual([caps[r['key']] for r in revs], ['Tag plate · plate', 'second', 'first'], 'newest first: sent in the order added')
        # who took the photo
        atspi.click(atspi.find(a, 'button', name='11LCB20AA102'))
        atspi.find(a, 'label', contains='by The Manager, ', timeout=10)
        # approvals per code: two equipment photos compete (Pick), the tag plate photo doesn't (Approve); full names
        atspi.click(atspi.find(a, 'button', name='Sync now'))
        time.sleep(3)
        atspi.click(atspi.find(a, 'button', name='Manage'))
        atspi.click(atspi.find(a, 'button', name='Approvals'))
        atspi.find(a, 'label', name='Equipment photo (2)', timeout=15)
        atspi.find(a, 'label', name='Tag plate photo', timeout=10)
        atspi.find(a, None, contains='by Omar Tech', timeout=10)
        # the page may be rebuilding (a photo's picture arrives after its entry): count it once it is complete
        for _ in range(20):
            picks = len(atspi.find_all(a, 'button', contains='Pick this photo'))
            if picks == 2:
                break
            time.sleep(0.5)
        self.assertEqual(picks, 2)
        for _ in range(5):          # the page rebuilds after a sync that brought data: a lost click is retried
            atspi.click(atspi.find(a, 'button', name='Pick this photo', timeout=15))
            try:
                atspi.find(a, 'label', contains='Photo chosen', timeout=4)
                break
            except AssertionError:
                pass
        for _ in range(40):
            subs = omar.req('GET', '/api/submissions?status=all&kind=photo')['submissions']
            got = sorted((s['payload']['caption'], s['status']) for s in subs)
            if [x[1] for x in got].count('pending') == 1:
                break
            time.sleep(0.5)
        self.assertEqual(sorted(x[1] for x in got), ['approved', 'pending', 'rejected'])
        self.assertEqual([x for x in got if x[1] == 'pending'][0][0], 'Tag plate of the pump', 'the plate photo must stay')
        # the code opens on the drawing
        atspi.click(atspi.find(a, 'button', name='Open 11LAB70AA501 on the drawing', timeout=10))
        atspi.find(a, 'button', name='Close the panel', timeout=10)
        # my proposals: filtered by kind and status, grouped by code
        atspi.click(atspi.find(a, 'button', name='Back'))
        atspi.click(atspi.find(a, 'button', name='My proposals'))
        atspi.click(atspi.find(a, 'toggle button', name='Equipment photos', timeout=10))
        atspi.find(a, 'label', name='2 proposals, 1 code', timeout=10)
        atspi.click(atspi.find(a, 'toggle button', name='Tag plate photos', timeout=10))
        atspi.find(a, 'label', name='1 proposal, 1 code', timeout=10)
        atspi.find(a, 'label', name='11LCB20AA102', timeout=10)
        atspi.click(atspi.find(a, 'toggle button', name='Rejected', timeout=10))
        atspi.find(a, 'label', name='None of your proposals match.', timeout=10)
        # the leaderboard
        atspi.click(atspi.find(a, 'button', name='Back'))
        atspi.click(atspi.find(a, 'button', name='Leaderboard'))
        atspi.find(a, None, contains='Omar Tech', timeout=10)
        atspi.find(a, None, contains='1 approved · 1 rejected · 1 waiting', timeout=10)
        # a new plant's manager needs a position too
        f = self.start_app('founder')
        atspi.click(atspi.find(f, 'button', name='Start a new plant'))
        atspi.set_text(atspi.find(f, 'text', name='Plant name'), 'Founded plant')
        atspi.set_text(atspi.find(f, 'text', name='Your username'), 'founder')
        atspi.set_text(atspi.find(f, 'text', name='Your full name'), 'Fay Founder')
        atspi.click(atspi.find(f, 'button', name='Create the plant'))
        atspi.find(f, 'label', contains='your position (job title)', timeout=10)
        atspi.set_text(atspi.find(f, 'text', name='Your position (job title)'), 'Plant manager')
        atspi.click(atspi.find(f, 'button', name='Create the plant'))
        atspi.find(f, 'button', name='Manage', timeout=15)
        # the new plant's manager has an account here (the genesis took effect: the plant's root adopted), not empty
        # details without a role (the bug the Windows test caught)
        atspi.click(atspi.find(f, 'button', name='Manage'))
        atspi.click(atspi.find(f, 'button', name='Account', timeout=10))
        atspi.find(f, 'label', name='founder', timeout=10)
        atspi.find(f, 'label', name='manager', timeout=10)

    def test_zzzz_kept_floor(self):
        """#144: a floor that only rides on a photo still in the queue is not a known floor for Photo for all. One
        photo of a code without a floor is queued with the floor asked for it and stays in the queue (not compressed:
        KKS_TEST_PHOTO_HOLD, the same list a photo kept after a failure waits in). Photo for all for that code and
        another without a floor then asks for both: asked for the other only, its floor would be written for the
        first code too when this photo is sent before the waiting one."""
        b = self.boss
        one, two = '11LAE10AP001', '11LAE10AP002'
        for k, bb in ((one, [200, 700, 320, 760]), (two, [400, 700, 520, 760])):
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb, 'kks': k, 'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        from PIL import Image
        pic = os.path.join(self.dir, 'kept.png')
        Image.new('RGB', (320, 240), (120, 150, 90)).save(pic)
        a = self.start_app('keptfloor', KKS_PHOTO_FILE=pic, KKS_TEST_PHOTO_HOLD='1')
        self.join(a)
        search = atspi.find(a, 'entry', contains='Search equipment')
        atspi.set_text(search, one[2:])
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name=one, timeout=10))
        time.sleep(2)            # the panel is built for this code
        dlg = None
        for _ in range(5):       # the panel rebuilds after a sync: a lost click is retried
            atspi.click(atspi.find(a, 'button', name='+ Add photo', timeout=10))
            try:
                dlg = atspi.find(a, 'alert', name=f'Which floor is {one} on?', timeout=5)
                break
            except AssertionError:
                continue
        self.assertIsNotNone(dlg, 'the floor was never asked for the first photo')
        atspi.set_text(atspi.find(dlg, None, name=f'Floor of {one}'), '7')
        atspi.click(atspi.find(dlg, 'button', name='Continue'))
        atspi.set_text(atspi.find(a, 'text', name='Caption', timeout=10), 'waits with its floor')
        atspi.click(atspi.find(a, 'button', name='Add the photo'))
        atspi.click(atspi.find(atspi.find(a, 'alert', name='And its tag plate?', timeout=10), 'button', name='Not now'))
        atspi.find(a, 'label', contains='Compressing 1 photo', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Close the panel'))
        self.assertFalse(b.req('GET', '/api/state')['equipment'].get(one, {}).get('floor'), 'the floor is only in the queue')
        mode = atspi.find(a, 'toggle button', name='Select tags')
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        for i, k in enumerate((one, two)):
            atspi.set_text(search, k[2:])
            atspi.click(atspi.find(a, 'button', name=k, timeout=10))
            atspi.find(a, 'label', name=f'{i + 1} selected', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
        dlg = atspi.find(a, 'alert', name='Which floor are they on?', timeout=10)
        atspi.find(dlg, None, contains=f'Floor for {one}, {two}: they have none yet', timeout=5)
        atspi.click(atspi.find(dlg, 'button', name='Cancel'))
        # the first code alone: its floor rides on the waiting photo only, so it is asked (not sent without one)
        atspi.click(atspi.find(a, 'button', name='List'))
        ld = atspi.find(a, 'dialog', name='Selected codes', timeout=10)
        atspi.click(atspi.find(ld, 'switch', name=two, timeout=10))
        atspi.find(a, 'label', name='1 selected', timeout=10)
        atspi.click(atspi.find(ld, 'button', name='Close'))
        time.sleep(0.5)
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
        dlg = atspi.find(a, 'alert', name='Which floor are they on?', timeout=10)
        atspi.find(dlg, None, contains=f'Floor for {one}: it has none yet', timeout=5)
        atspi.click(atspi.find(dlg, 'button', name='Cancel'))
        last = self.apps[-1]     # done (its photo stays held): its syncs must not rebuild other tests' screens
        last.kill()
        last.wait(10)

    def test_zzzz_kept_floor_sent_later(self):
        """#149: a second photo of a code is not asked for the floor while a queued photo carries one. When that photo
        fails and waits at the end of the queue for its retry, the second goes first: it takes the floor with it
        (before, it arrived without one, and the floor came only with the retry a minute later). When that photo is
        refused, the second takes its floor over (before, the floor was lost and never asked). KKS_TEST_PHOTO_FAIL
        fails the next send while its file exists ("refused" in it: the core refuses it)."""
        b = self.boss
        from PIL import Image
        pic = os.path.join(self.dir, 'later.png')
        Image.new('RGB', (320, 240), (90, 120, 150)).save(pic)
        hold = os.path.join(self.dir, 'hold-later')
        fail = os.path.join(self.dir, 'fail-later')
        rounds = (('11LAE12AP001', '7', 'failed', 200), ('11LAE13AP001', '5', 'refused', 400))
        for code, _, _, x in rounds:
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [x, 850, x + 120, 910],
                                                                           'kks': code, 'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        open(hold, 'w').close()
        a = self.start_app('floorlater', KKS_PHOTO_FILE=pic, KKS_TEST_PHOTO_HOLD=hold, KKS_TEST_PHOTO_FAIL=fail)
        app = self.apps[-1]
        self.join(a)
        search = atspi.find(a, 'entry', contains='Search equipment')

        def photos(code):
            return {p['caption'] for p in b.req('GET', '/api/state')['photos'] if p['kks'] == code}
        for code, floor, how, _ in rounds:
            open(hold, 'w').close()
            with open(fail, 'w') as f:
                f.write(how)
            for i in range(30):      # (the tag reaches the app with a sync round; the text changes each time)
                atspi.set_text(search, code[i % 2 * 2:])
                time.sleep(1)
                if atspi.find_all(a, 'button', name=code):
                    break
            atspi.click(atspi.find(a, 'button', name=code))
            time.sleep(2)            # the panel is built for this code
            for cap in ('asked', 'not asked'):
                caption = None
                for _ in range(5):   # the panel rebuilds after a sync: a lost click is retried
                    atspi.click(atspi.find(a, 'button', name='+ Add photo', timeout=10))
                    if cap == 'asked':
                        try:
                            dlg = atspi.find(a, 'alert', name=f'Which floor is {code} on?', timeout=5)
                        except AssertionError:
                            continue
                        atspi.set_text(atspi.find(dlg, None, name=f'Floor of {code}'), floor)
                        atspi.click(atspi.find(dlg, 'button', name='Continue'))
                    try:
                        caption = atspi.find(a, 'text', name='Caption', timeout=8)
                        break
                    except AssertionError:
                        continue
                self.assertIsNotNone(caption, f'the photo editor never opened ({cap}, {how})')
                self.assertFalse(cap == 'not asked' and atspi.find_all(a, 'alert'), f'the floor was asked again ({how})')
                atspi.set_text(caption, cap)
                atspi.click(atspi.find(a, 'button', name='Add the photo'))
                atspi.click(atspi.find(atspi.find(a, 'alert', name='And its tag plate?', timeout=10), 'button', name='Not now'))
            atspi.find(a, 'label', contains='Compressing 2 photos', timeout=10)
            os.remove(hold)          # the first fails (or is refused); the second goes first (or alone)
            for _ in range(120):
                if 'not asked' in photos(code):
                    break
                time.sleep(0.5)
            self.assertEqual(photos(code), {'not asked'}, f'the second photo did not go first ({how})')
            self.assertFalse(os.path.exists(fail), f'the first photo\'s send did not fail ({how})')
            self.assertEqual(b.req('GET', '/api/state')['equipment'].get(code, {}).get('floor'), floor,
                             f'the photo not asked for its floor arrived without the floor of the first photo ({how})')
            if how == 'failed':      # its retry, a minute later: sent, so the next round's failure is not its
                for _ in range(240):
                    if 'asked' in photos(code):
                        break
                    time.sleep(0.5)
                self.assertEqual(photos(code), {'asked', 'not asked'}, 'the failed photo was not sent at its retry')
        self.assertEqual(self.criticals('floorlater'), [])
        app.kill()
        app.wait(10)

    def test_zzzzz_stale_click(self):
        """#160: a button's handler runs a moment after the press (from an idle callback), and a reload can rebuild
        the tag panel in between. The handler of the panel that is gone must then do nothing: it used to hide and
        read that panel's freed widgets (a crash), leave the new panel marked as being edited (every Edit then said
        "Save or cancel your edits first"), or send what the old form held. KKS_TEST_STALE_CLICK forces that order:
        while the file it names exists, the next press is followed by a rebuild of the panel before its handler.
        (Named to run last: it only reads the shared server's data, but must find it settled.)"""
        flag = os.path.join(self.dir, 'stale-click')
        a = self.start_app('stale', KKS_TEST_STALE_CLICK=flag, KKS_SYNC_EVERY='2000')
        app = self.apps[-1]
        self.join(a)
        code = '11LAB70AA501'
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), code)
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name=code))
        atspi.find(a, 'button', name='Edit', timeout=15)
        time.sleep(3)                # (the first rounds' data is in: the sheet list's rows are the final ones)
        sheet_row = atspi.find(a, 'list item', contains='Sample sheet', showing=False)
        before = self.boss.req('GET', '/api/state')['equipment'].get(code)

        def press(button, then):     # (a press within GTK's 250 ms before a real reload is lost: again)
            for _ in range(5):
                try:
                    atspi.click(atspi.find(a, 'button', name=button, timeout=8))
                except AssertionError:
                    pass             # (the press before did work, late: the button has gone)
                try:
                    return atspi.find(a, *then, timeout=4)
                except AssertionError:
                    pass
            self.fail(f'{button}: never got {then}')

        def stale_press(button):
            # press it with the rebuild forced in between (the app removes the file when it has done that)
            for _ in range(5):       # (a press within GTK's 250 ms before a real reload is lost: again)
                open(flag, 'w').close()
                atspi.click(atspi.find(a, 'button', name=button, timeout=15))
                t0 = time.time()
                while os.path.exists(flag) and time.time() - t0 < 5:
                    time.sleep(0.1)
                if not os.path.exists(flag):
                    break
            else:
                self.fail(f'{button}: the app never rebuilt the panel after the press')
            time.sleep(1.5)          # the handler, had it run, is long done
            self.assertIsNone(app.poll(), f'the app died after {button} was pressed on a panel that was then rebuilt')

        # Edit, on the panel that is then replaced: no form opens, and the new panel's Edit works
        stale_press('Edit')
        self.assertFalse(atspi.find_all(a, 'text', contains='Notes'), 'the replaced panel\'s Edit opened a form')
        notes = press('Edit', ('text', 'Notes'))      # (stuck, it said "Save or cancel your edits first")
        # Save, on a form that is then replaced: nothing is sent, here or to the server
        atspi.set_text(notes, 'typed into the form that was replaced')
        atspi.set_text(atspi.find(a, 'text', name='Floor'), '7')
        stale_press('Save')
        self.assertFalse(atspi.find_all(a, None, contains='Saved: '), 'the replaced form\'s Save sent something')   # (its toast)
        self.assertFalse(atspi.find_all(a, 'text', contains='Notes'), 'the form is still there: the panel was not rebuilt')
        time.sleep(6)                # three sync rounds: a change saved here would be on the server by now
        self.assertIsNone(app.poll(), 'the app died')
        self.assertFalse(atspi.find_all(a, None, contains='typed into the form that was replaced'),
                         'the replaced form\'s Save was carried out')
        self.assertEqual(self.boss.req('GET', '/api/state')['equipment'].get(code), before,
                         'the replaced form\'s Save changed the equipment')
        # and the panel still works: a form opens and closes
        press('Edit', ('text', 'Notes'))
        press('Cancel', ('button', 'Edit'))
        # the sheet list was reloaded by every sync round on the way (every 2 s) and nothing in it changed: its rows
        # are the ones from before (a row replaced loses a press on it, as the panel's buttons did)
        self.assertFalse(sheet_row.get_state_set().contains(Atspi.StateType.DEFUNCT),
                         'sync rounds that changed nothing replaced the sheet list\'s rows')
        self.assertEqual(atspi.find(a, 'list item', contains='Sample sheet', showing=False), sheet_row,
                         'sync rounds that changed nothing replaced the sheet list\'s rows')
        self.assertEqual(self.criticals('stale'), [], 'a handler worked on widgets that were gone')
        app.kill()                   # done: its syncs must not rebuild other tests' screens
        app.wait(10)

    def test_zzzzzz_escape(self):
        """#183: Escape on the drawing ends its modes as their own buttons do. Mark a tag: the banner and the crosshair
        go, a drag pans again and marks nothing, a click on a tag opens its panel (before, Escape ended only the
        viewer's half of the mode: the banner and the crosshair stayed). The banner's Cancel leaves the same (it left
        the crosshair), and so does Escape with the focus elsewhere. Link mode ends as its Done ends it, the select mode
        as its toggle. KKS_TEST_VIEWER drives the drawing: the headless session has no pointer or keyboard, so a key
        goes to the drawing's handler and then the window's directly, not through GTK's propagation, and "the focus
        elsewhere" is the window's handler alone. (Named to run before link_done: it publishes the same procedure.)"""
        pd = os.path.join(self.dir, 'plant-data')
        with open(os.path.join(pd, 'procedures.json'), 'w') as f:
            json.dump([{'id': 'P-1', 'title': 'Start the test pump', 'path': ['Test chapter'], 'page': 1, 'intro': '',
                        'steps': [{'n': 1, 'text': 'Open the suction valve'}]}], f)
        r = subprocess.run([SERVER, 'publish-data', pd, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        state = os.path.join(self.dir, 'escape-viewer')
        a = self.start_app('escape', KKS_TEST_VIEWER=state)
        app = self.apps[-1]
        self.join(a)
        sent = [0]

        def read():
            try:
                with open(state) as f:
                    return dict(kv.split('=', 1) for kv in f.read().split())
            except FileNotFoundError:
                return {}

        def drawing(*cmds):          # commands for the drawing; returns its state once they are done
            with open(state + '.do.tmp', 'w') as f:
                f.write('\n'.join(cmds) + '\n')
            os.replace(state + '.do.tmp', state + '.do')
            sent[0] += len(cmds)
            for _ in range(100):
                s = read()
                if s.get('n') == str(sent[0]):
                    return s
                time.sleep(0.1)
            self.fail(f'the drawing did not take {cmds}: {read()}')

        def settles(what, **want):   # the drawing's state comes to this
            for _ in range(50):
                s = read()
                if all(s.get(k) == v for k, v in want.items()):
                    return s
                time.sleep(0.1)
            self.fail(f'{what}: {read()}, wanted {want}')

        def gone(role, what, **match):
            for _ in range(30):
                if not atspi.find_all(a, role, **match):
                    return
                time.sleep(0.2)
            self.fail(what)

        code = '11LAB70AA501'
        banner = 'Drag a box around the tag the app missed'
        escape = 'key 0xff1b'
        settles('the drawing is not up', marking='0', cursor='grab')

        def start_marking():
            atspi.click(atspi.find(a, 'button', name='Mark a tag the app missed'))
            atspi.find(a, 'label', name=banner, timeout=10)
            settles('Mark a tag did not start', marking='1', cursor='crosshair')

        def mode_ended(how):         # all of Mark a tag gone, and the drawing pans and clicks as usual again
            gone('label', f'{how} left the banner up', name=banner)
            gone('button', f'{how} left the banner\'s Cancel up', name='Cancel')
            s = settles(f'{how} left the drawing in mark mode', marking='0', cursor='grab')
            moved = drawing('drag 300 300 80 60')
            self.assertNotEqual((moved['ox'], moved['oy']), (s['ox'], s['oy']), f'after {how} a drag did not pan')
            time.sleep(1)
            self.assertFalse(atspi.find_all(a, 'label', contains='Type the code if you can read it'),
                             f'after {how} a drag still marked a tag')
            drawing(f'click-tag {code}')
            atspi.find(a, 'button', name='Edit', timeout=10)     # its panel
            self.press(a, 'Close the panel', ('button', 'Mark a tag the app missed'))
            gone('button', f'the panel did not close after {how}', name='Edit')

        # while marking, a click on a tag does nothing (the mode is on)
        start_marking()
        drawing(f'click-tag {code}')
        time.sleep(1)
        self.assertFalse(atspi.find_all(a, 'button', name='Edit'), 'a click while marking opened a panel')
        drawing(escape)
        mode_ended('Escape')
        start_marking()
        atspi.click(atspi.find(a, 'button', name='Cancel'))
        mode_ended('Cancel')
        # a drag while marking does mark (its dialog: closed, the mode stays), and Escape with the focus off the
        # drawing (on the button that started the mode, say) ends the mode as well
        start_marking()
        drawing('drag 300 300 80 60')
        atspi.find(a, 'label', contains='Type the code if you can read it', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Close'))
        gone('label', 'the mark\'s dialog did not close', contains='Type the code if you can read it')
        settles('closing the mark\'s dialog ended the mode', marking='1', cursor='crosshair')
        drawing('window-key 0xff1b')
        mode_ended('Escape with the focus off the drawing')
        # link mode: Escape ends it as Done does (the banner goes, the procedure's page stays, drawn again)
        self.press(a, 'Procedures', ('button', 'P-1  Start the test pump'))
        self.press(a, 'P-1  Start the test pump', ('label', 'Open the suction valve'))
        self.press(a, '+ Link equipment', ('button', 'Done'))
        # (the focus stays on that button, in the sidebar: its Escape, going back a page, is off in link mode)
        settles('the sidebar still goes back at Escape in link mode', pop_on_escape='0')
        drawing(escape)
        gone('label', 'Escape left link mode\'s banner up', contains='to link them to step')
        settles('the sidebar does not go back at Escape after link mode', pop_on_escape='1')
        atspi.find(a, 'label', name='Open the suction valve', timeout=5)
        # the select mode: Escape ends it as its toggle does
        mode = atspi.find(a, 'toggle button', name='Select tags')
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        settles('Select tags did not start', selecting='1', cursor='crosshair')
        drawing(escape)
        settles('Escape left the select mode on', selecting='0', cursor='grab')
        for _ in range(20):
            if not self.pressed(mode):
                break
            time.sleep(0.2)
        self.assertFalse(self.pressed(mode), 'Escape left the Select tags toggle pressed')
        self.assertIsNone(app.poll(), 'the app died')
        self.assertEqual(self.criticals('escape'), [])
        app.kill()
        app.wait(10)

    def test_zzzzzz_link_done(self):
        """Link mode's banner: Done takes the banner down and draws the procedure's page again, also after Back has
        closed that page (#160's review: Done kept the closed page's widgets, and by taking the banner down freed
        its own closure while it ran). (Named to run last: it publishes a procedure.)"""
        pd = os.path.join(self.dir, 'plant-data')
        with open(os.path.join(pd, 'procedures.json'), 'w') as f:
            json.dump([{'id': 'P-1', 'title': 'Start the test pump', 'path': ['Test chapter'], 'page': 1, 'intro': '',
                        'steps': [{'n': 1, 'text': 'Open the suction valve'}]}], f)
        r = subprocess.run([SERVER, 'publish-data', pd, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        a = self.start_app('linkdone')
        app = self.apps[-1]
        self.join(a)

        def press(button, then):     # (a press within GTK's 250 ms before a reload is lost: again)
            for _ in range(5):
                try:
                    atspi.click(atspi.find(a, 'button', name=button, timeout=8))
                except AssertionError:
                    pass             # (the press before did work, late: the button has gone)
                try:
                    return atspi.find(a, *then, timeout=4)
                except AssertionError:
                    pass
            self.fail(f'{button}: never got {then}')

        def gone(role, name, what):
            for _ in range(30):
                if not atspi.find_all(a, role, name=name):
                    return
                time.sleep(0.2)
            self.fail(what)
        press('Procedures', ('button', 'P-1  Start the test pump'))
        press('P-1  Start the test pump', ('label', 'Open the suction valve'))
        for _ in range(3):           # Done with the page open: the banner goes, the page is drawn again and works
            press('+ Link equipment', ('button', 'Done'))
            atspi.click(atspi.find(a, 'button', name='Done'))
            gone('button', 'Done', 'Done left the banner up')
            time.sleep(0.5)
            self.assertIsNone(app.poll(), 'the app died at Done')
            atspi.find(a, 'label', name='Open the suction valve', timeout=5)
        for _ in range(3):           # Done after Back closed the page: the banner goes, the app lives, the page opens again
            press('+ Link equipment', ('button', 'Done'))
            atspi.click(atspi.find(a, 'button', name='Back'))
            gone('label', 'Open the suction valve', 'Back did not close the procedure')
            time.sleep(0.5)          # (the page's closing animation: it is freed after it)
            atspi.click(atspi.find(a, 'button', name='Done'))
            gone('button', 'Done', 'Done left the banner up')
            time.sleep(0.5)
            self.assertIsNone(app.poll(), 'the app died at Done after the procedure\'s page was closed')
            press('P-1  Start the test pump', ('label', 'Open the suction valve'))
        # #163: link mode ends with its banner, whoever takes the banner. The panel's "Link … to step" button is link
        # mode as the keyboard sees it (the headless session has no pointer to click a tag with).
        code = '11LAB70AA501'
        link = f'Link {code} to step 1 of P-1'

        def select_tag():            # from the sidebar's first page (the search is there)
            for _ in range(3):
                if atspi.find_all(a, 'entry', contains='Search equipment'):
                    break
                atspi.click(atspi.find(a, 'button', name='Back'))
                time.sleep(0.7)
            atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), code)
            self.press(a, code, ('button', 'Edit'))

        def open_proc():
            if not atspi.find_all(a, 'button', name='P-1  Start the test pump'):
                self.press(a, 'Procedures', ('button', 'P-1  Start the test pump'))
            self.press(a, 'P-1  Start the test pump', ('label', 'Open the suction valve'))
        def banner_gone(what):       # link mode's banner (the select mode's bar has a Done of its own)
            for _ in range(30):
                if not atspi.find_all(a, 'label', contains='to link them to step'):
                    return
                time.sleep(0.2)
            self.fail(what)
        atspi.click(atspi.find(a, 'button', name='Back'))
        gone('label', 'Open the suction valve', 'Back did not close the procedure')
        select_tag()
        self.assertFalse(atspi.find_all(a, 'button', name=link), 'link mode was still on after Done')
        open_proc()
        # link mode starting and ending under an open form: the form stays, the Link button comes and goes beside it
        self.press(a, 'Edit', ('text', 'Notes'))
        atspi.set_text(atspi.find(a, 'text', name='Notes'), 'typed before link mode')
        self.press(a, '+ Link equipment', ('button', link))
        self.assertEqual(self.typed(a, 'Notes'), 'typed before link mode', 'link mode started: the panel was rebuilt under the open form')
        atspi.click(atspi.find(a, 'button', name='Done'))
        gone('button', link, 'Done left the panel\'s Link button (a form is open)')
        self.assertEqual(self.typed(a, 'Notes'), 'typed before link mode', 'link mode ended: the panel was rebuilt under the open form')
        self.press(a, 'Cancel', ('button', 'Edit'))
        # "Select tags" takes the banner down: link mode is over (it stayed on, with no Done to press)
        self.press(a, '+ Link equipment', ('button', link))
        mode = atspi.find(a, 'toggle button', name='Select tags')
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        banner_gone('Select tags left link mode\'s banner up')
        gone('button', link, 'link mode outlived its banner: Select tags took the banner, the panel still links')
        atspi.click(mode)
        time.sleep(1)
        # the other way round: link mode started while tags are being selected ends that mode
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        self.press(a, '+ Link equipment', ('button', link))
        atspi.find(a, 'label', contains='to link them to step', timeout=5)
        for _ in range(20):
            if not self.pressed(mode):
                break
            time.sleep(0.2)
        self.assertFalse(self.pressed(mode), 'link mode started with the select mode still on')
        # "Mark a tag" replaces the banner (and closes the panel): link mode is over
        atspi.click(atspi.find(a, 'button', name='Mark a tag the app missed'))
        atspi.find(a, 'button', name='Cancel', timeout=10)
        banner_gone('Mark a tag left link mode\'s banner up')
        atspi.click(atspi.find(a, 'button', name='Cancel'))
        gone('button', 'Cancel', 'Cancel left the banner up')
        select_tag()
        time.sleep(1)
        self.assertFalse(atspi.find_all(a, 'button', name=link),
                         'link mode outlived its banner: Mark a tag replaced the banner, the panel still links')
        # Done after Back and opening the procedure again: the page now on screen shows the link made meanwhile
        open_proc()
        self.press(a, '+ Link equipment', ('button', link))
        atspi.click(atspi.find(a, 'button', name='Back'))
        gone('label', 'Open the suction valve', 'Back did not close the procedure')
        time.sleep(0.5)
        self.press(a, 'P-1  Start the test pump', ('label', 'Open the suction valve'))
        unlink = f'Unlink {code} from step 1'
        self.assertFalse(atspi.find_all(a, 'button', name=unlink))
        atspi.click(atspi.find(a, 'button', name=link))
        for _ in range(40):
            if any(l['kks'] == code and l['proc'] == 'P-1' for l in self.boss.req('GET', '/api/state')['links']):
                break
            time.sleep(0.5)
        else:
            self.fail('the panel\'s Link button linked nothing')
        atspi.click(atspi.find(a, 'button', name='Done'))
        gone('button', 'Done', 'Done left the banner up')
        atspi.find(a, 'button', name=unlink, timeout=5)      # (the page was the one from before: not drawn again)
        gone('button', link, 'Done left the panel\'s Link button')
        self.assertIsNone(app.poll(), 'the app died')
        self.assertEqual(self.criticals('linkdone'), [], 'Done worked on widgets that were gone')
        app.kill()
        app.wait(10)

    def test_zzzzzzz_form_kept(self):
        """#163: nothing rebuilds the tag panel under an open form but the form's own Save and Cancel. A photo
        leaving the queue (KKS_TEST_PHOTO_HOLD names a file: held while it exists) and a photo queued from the panel
        rebuilt it; a sync round that changed the equipment and another sheet opened already left it alone, and stay
        that way. What is typed stays, and the parts that must not wait are brought up to date beside the form (the
        queue's line, the photo, a line saying what changed underneath). (Link mode under a form: test_zzzzzz_link_done.) Save then sends only what was typed, with the values the form was opened on: a field someone
        else changed meanwhile is not written over (the core holds the change as a clash). The review form ("Check
        this tag") keeps what is typed in it the same way. (Named to run last: it adds tags and photos.)"""
        b = self.boss
        code = '11LAE30AP001'
        r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [600, 700, 720, 760],
                                                                       'kks': code, 'isa': '', 'note': ''}})
        self.assertEqual(r.get('status'), 'approved', r)
        # (with a floor: the photo is not asked for one)
        r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'floor': '3'}, 'base': {}}})
        self.assertEqual(r.get('status'), 'approved', r)
        # a reading the importer was not sure of (as it writes them), published: its panel has the review form and,
        # since it has a code, the Edit form too
        doubt = '11LAE32AP001'
        pd = os.path.join(self.dir, 'plant-data')
        with open(os.path.join(pd, 'tags.json')) as f:
            tags = json.load(f)
        tags.append({'id': 'sample:doubt', 'sheet': 'sample', 'kks': doubt, 'suffix': '', 'isa': None, 'kind': 'equipment',
                     'status': 'review', 'conf': 0.4, 'bbox': [800, 700, 920, 760], 'read': ['11LAE32', 'AP001']})
        with open(os.path.join(pd, 'tags.json'), 'w') as f:
            json.dump(tags, f)
        r = subprocess.run([SERVER, 'publish-data', pd, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        from PIL import Image
        pic = os.path.join(self.dir, 'formkept.png')
        Image.new('RGB', (320, 240), (150, 110, 90)).save(pic)
        hold = os.path.join(self.dir, 'hold-photos')
        open(hold, 'w').close()
        a = self.start_app('formkept', KKS_PHOTO_FILE=pic, KKS_TEST_PHOTO_HOLD=hold, KKS_SYNC_EVERY='2000')
        app = self.apps[-1]
        self.join(a)

        def equipment():
            return b.req('GET', '/api/state')['equipment'].get(code, {})

        def wait_for(what, fn, secs=30):
            t0 = time.time()
            while time.time() - t0 < secs:
                if fn():
                    return
                time.sleep(0.3)
            self.fail(what)
        def tags_listed():           # the sheet list's count of the sample sheet's tags: what the app has loaded
            n = [int(m.group(1)) for _, nm in atspi.nodes(a, 'label') for m in [re.match(r'(\d+) tags', nm)] if m]
            return max(n) if n else -1

        def round_arrives():
            """the app has synced with the server and reloaded: a tag added there now is counted in its sheet list"""
            was = tags_listed()
            round_arrives.n += 1
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'kks': '', 'isa': '', 'note': '',
                                              'bbox': [100 + 40 * round_arrives.n, 900, 130 + 40 * round_arrives.n, 930]}})
            self.assertEqual(r.get('status'), 'approved', r)
            wait_for('the app never showed a tag added on the server', lambda: tags_listed() == was + 1)
            time.sleep(1)            # (the same reload's panel part is done)
        round_arrives.n = 0
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), code)
        self.press(a, code, ('button', 'Edit'))
        time.sleep(3)                # (the first rounds' data is in)

        def add_photo(caption):
            atspi.click(atspi.find(a, 'button', name='+ Add photo', timeout=10))
            atspi.set_text(atspi.find(a, 'text', name='Caption', timeout=10), caption)
            atspi.click(atspi.find(a, 'button', name='Add the photo'))
            atspi.click(atspi.find(atspi.find(a, 'alert', name='And its tag plate?', timeout=10), 'button', name='Not now'))
        # 1. a photo leaves the queue while the form is open
        add_photo('held first')
        atspi.find(a, 'label', contains='1 photo of this equipment being compressed', timeout=10)
        self.press(a, 'Edit', ('text', 'Notes'))
        note = 'typed while the photo waits; ملاحظة'
        atspi.set_text(atspi.find(a, 'text', name='Notes'), note)
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), note)
        os.remove(hold)
        wait_for('the photo was never sent', lambda: any(p['kks'] == code for p in b.req('GET', '/api/state')['photos']))
        wait_for('the queue\'s line stayed in the panel',
                 lambda: not atspi.find_all(a, 'label', contains='of this equipment being compressed'), 15)
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), note, 'a photo left the queue: the panel was rebuilt under the open form')
        atspi.find(a, 'button', name='Open photo: held first', timeout=10)      # shown beside the form
        # 2. a photo queued from the panel while the form is open (and sent: nothing holds it now)
        add_photo('while editing')
        wait_for('the second photo was never sent',
                 lambda: sum(p['kks'] == code for p in b.req('GET', '/api/state')['photos']) == 2)
        atspi.find(a, 'button', name='Open photo: while editing', timeout=15)
        time.sleep(1)                # (the rebuild after a photo is queued is long done)
        self.assertEqual(self.typed(a, 'Notes'), note, 'a photo was queued: the panel was rebuilt under the open form')
        # 3. a sync round that changed this equipment (another field), 4. another sheet opened
        r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'near': 'by the north door'},
                                                                         'base': {}}})
        self.assertEqual(r.get('status'), 'approved', r)
        said = atspi.find(a, 'label', contains='Changed since you opened this form', timeout=20)
        self.assertIn('Near / landmark', said.get_name())
        self.assertNotIn('Notes', said.get_name())
        self.assertEqual(self.typed(a, 'Notes'), note, 'a sync changed the equipment: the panel was rebuilt under the open form')
        atspi.click(atspi.find(a, 'button', name='Second sheet'))
        round_arrives()
        self.assertEqual(self.typed(a, 'Notes'), note, 'another sheet was opened: the panel was rebuilt under the open form')
        self.assertEqual(equipment().get('notes', ''), '', 'nothing was saved yet')
        # Save: what was typed goes, the field changed underneath stays as the other left it
        atspi.click(atspi.find(a, 'button', name='Save'))
        wait_for('Save sent nothing', lambda: equipment().get('notes') == note)
        self.assertEqual(equipment().get('near'), 'by the north door', 'Save wrote over a field changed underneath')
        atspi.find(a, 'button', name='Edit', timeout=10)       # the form closed, the panel is drawn again
        atspi.find(a, 'label', contains='by the north door', timeout=10)
        # 5. the same field changed underneath and in the form: held as a clash, not written over
        self.press(a, 'Edit', ('text', 'Near / landmark'))
        atspi.set_text(atspi.find(a, 'text', name='Near / landmark'), 'typed here')
        r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'near': 'set on the server'},
                                                                         'base': {'near': 'by the north door'}}})
        self.assertEqual(r.get('status'), 'approved', r)
        said = atspi.find(a, 'label', contains='Changed since you opened this form', timeout=20)
        self.assertIn('Near / landmark', said.get_name())
        self.assertEqual(self.typed(a, 'Near / landmark'), 'typed here')
        atspi.click(atspi.find(a, 'button', name='Save'))
        atspi.find(a, None, contains='Held: it clashes', timeout=10)
        round_arrives()              # a change written here would be on the server by now
        self.assertEqual(equipment().get('near'), 'set on the server', 'Save wrote over a change made underneath')
        # 6. the review form ("Check this tag") and the Edit form in one panel: neither is lost to the other
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), doubt)
        self.press(a, doubt, ('text', 'KKS (with suffix)'))
        time.sleep(3)

        def reviewed():
            return b.req('GET', '/api/state')['reviews'].get('sample:doubt')
        self.press(a, 'Edit', ('text', 'Notes'))
        atspi.set_text(atspi.find(a, 'text', name='Notes'), 'typed under the review form')
        atspi.click(atspi.find(a, 'button', name='Confirm'))       # (it would send, and rebuild the panel)
        atspi.find(a, None, contains='Save or cancel your edits first', timeout=10)
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), 'typed under the review form', 'the review form\'s Confirm rebuilt the panel under the Edit form')
        self.assertIsNone(reviewed(), 'Confirm sent the review with the Edit form open')
        # the other way: the review form typed in while the Edit form is open, then Cancel (it rebuilds the panel)
        atspi.set_text(atspi.find(a, 'text', name='KKS (with suffix)', timeout=10), '11LAE31AP001')
        self.press(a, 'Cancel', ('button', 'Edit'))
        self.assertEqual(self.typed(a, 'KKS (with suffix)'), '11LAE31AP001', 'the Edit form\'s Cancel put the reader\'s text back in the review form')
        # what is typed in the review form stays through a sync round that brought a change (the reader's text came back)
        round_arrives()
        self.assertEqual(self.typed(a, 'KKS (with suffix)'), '11LAE31AP001', 'a sync round put the reader\'s text back in the review form')
        atspi.click(atspi.find(a, 'button', name='Edit'))          # (a second form: its Save would rebuild the panel)
        atspi.find(a, None, contains='Finish checking this tag first', timeout=10)
        self.assertIsNone(self.typed(a, 'Notes'), 'an Edit form opened over a review form that holds something typed')
        atspi.click(atspi.find(a, 'button', name='Confirm'))
        wait_for('Confirm sent nothing', lambda: (reviewed() or {}).get('kks') == '11LAE31AP001')
        wait_for('the review form stayed after Confirm', lambda: not atspi.find_all(a, 'text', name='KKS (with suffix)'), 10)
        # 7. the tag itself goes (removed on the server) under an open form: the form stays for what is typed, and
        # its Save closes the panel (it stayed open for good, each Save sending again)
        atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), code)
        time.sleep(1)
        atspi.click(atspi.find(a, 'button', name=code))
        atspi.find(a, 'label', contains='set on the server', timeout=10)       # this tag's panel
        self.press(a, 'Edit', ('text', 'Notes'))
        atspi.set_text(atspi.find(a, 'text', name='Notes'), 'typed on a tag that then goes')
        mark = [t for t in b.req('GET', '/api/state')['added_tags'] if t.get('kks') == code]
        self.assertEqual(len(mark), 1, mark)
        was = tags_listed()
        r = b.req('POST', '/api/submit', {'kind': 'tag_remove', 'payload': {'id': mark[0]['id']}})
        self.assertEqual(r.get('status'), 'approved', r)
        wait_for('the app never dropped the removed tag', lambda: tags_listed() == was - 1)
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), 'typed on a tag that then goes', 'the tag was removed: the form went with what was typed')
        atspi.click(atspi.find(a, 'button', name='Save'))
        wait_for('Save sent nothing', lambda: equipment().get('notes') == 'typed on a tag that then goes')
        wait_for('the panel of a tag that has gone stayed open after Save', lambda: not atspi.find_all(a, 'button', name='Save'), 10)
        self.assertFalse(atspi.find_all(a, 'button', name='Close the panel'), 'the panel of a tag that has gone stayed open')
        atspi.find(a, None, contains='no longer on the drawing', timeout=5)     # (said, not closed without a word)
        self.assertIsNone(app.poll(), 'the app died')
        self.assertEqual(self.criticals('formkept'), [])
        # 8. the window closed over an Edit form with nothing typed: it closes without a question (#163; the one that
        # asks: test_zzzzzzzz_form_ask)
        last = '11LAE33AP001'
        r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [1000, 500, 1120, 560],
                                                                       'kks': last, 'isa': '', 'note': ''}})
        self.assertEqual(r.get('status'), 'approved', r)
        for i in range(30):          # (the tag reaches the app with a sync round; the text changes each time)
            atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), last[i % 2 * 2:])
            time.sleep(1)
            if atspi.find_all(a, 'button', name=last):
                break
        atspi.click(atspi.find(a, 'button', name=last))
        self.press(a, 'Edit', ('text', 'Notes'))
        atspi.click(atspi.find(a, 'button', name='Close'))
        try:
            app.wait(15)
        except subprocess.TimeoutExpired:
            self.fail('the window did not close over a form with nothing typed' +
                      (' (it asked)' if atspi.find_all(a, 'alert') else ''))
        self.assertEqual(self.criticals('formkept'), [])

    def test_zzzzzzzz_form_ask(self):
        """Leaving a form that holds something typed asks first (the user, 2026-10-13; before, the text went without
        a word): another tag picked, the panel closed, "Mark a tag" started. Keep editing leaves everything as it
        was (the other tag is not opened); Discard goes on. A form with nothing typed leaves without a question.
        And after a form's Save or Cancel the keyboard's place is the new panel's Edit button (the window had no
        focus). (Named to run after form_kept: it adds tags.)"""
        b = self.boss
        one, two, doubt = '11LAE40AP001', '11LAE41AP001', '11LAE42AP001'
        for i, (code, near) in enumerate(((one, 'near the first'), (two, 'near the second'))):
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'kks': code, 'isa': '', 'note': '',
                                              'bbox': [1000 + 200 * i, 300, 1120 + 200 * i, 360]}})
            self.assertEqual(r.get('status'), 'approved', r)
            r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'near': near}, 'base': {}}})
            self.assertEqual(r.get('status'), 'approved', r)
        pd = os.path.join(self.dir, 'plant-data')
        with open(os.path.join(pd, 'tags.json')) as f:
            tags = json.load(f)
        tags.append({'id': 'sample:doubt2', 'sheet': 'sample', 'kks': doubt, 'suffix': '', 'isa': None, 'kind': 'equipment',
                     'status': 'review', 'conf': 0.4, 'bbox': [1000, 700, 1120, 760], 'read': ['11LAE42', 'AP001']})
        with open(os.path.join(pd, 'tags.json'), 'w') as f:
            json.dump(tags, f)
        r = subprocess.run([SERVER, 'publish-data', pd, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        focus_file = os.path.join(self.dir, 'formask-focus')
        a = self.start_app('formask', KKS_SYNC_EVERY='2000', KKS_TEST_FOCUS=focus_file)
        app = self.apps[-1]
        self.join(a)
        question = 'Discard your edits?'

        def pick(code):
            atspi.set_text(atspi.find(a, 'entry', contains='Search equipment'), code)
            time.sleep(1)
            atspi.click(atspi.find(a, 'button', name=code))

        def shows(text):
            return bool(atspi.find_all(a, 'label', contains=text))

        def asked(secs=6):
            """the question, if it comes within `secs`"""
            t0 = time.time()
            while time.time() - t0 < secs:
                d = atspi.find_all(a, 'alert', name=question)
                if d:
                    return d[0]
                time.sleep(0.3)
            return None

        def answer(d, button):
            atspi.click(atspi.find(d, 'button', name=button))
            for _ in range(40):
                if not atspi.find_all(a, 'alert', name=question):
                    return
                time.sleep(0.25)
            self.fail(f'the question stayed after {button}')

        def notes():
            return b.req('GET', '/api/state')['equipment'].get(one, {}).get('notes', '')

        def edit(text):
            self.press(a, 'Edit', ('text', 'Notes'))
            if text:
                atspi.set_text(atspi.find(a, 'text', name='Notes'), text)
                time.sleep(0.5)
                self.assertEqual(self.typed(a, 'Notes'), text)
        pick(one)
        atspi.find(a, 'label', contains='near the first', timeout=15)
        time.sleep(3)                # (the first rounds' data is in)
        # 1. a form with nothing typed: another tag opens without a question
        edit('')
        pick(two)
        atspi.find(a, 'label', contains='near the second', timeout=10)
        self.assertIsNone(asked(2), 'a form with nothing typed asked before leaving')
        # 2. something typed, another tag picked in the search: asked; Keep editing leaves everything as it was
        pick(one)
        atspi.find(a, 'label', contains='near the first', timeout=10)
        edit('typed, then another tag picked')
        pick(two)
        d = asked()
        self.assertIsNotNone(d, 'another tag was picked: the form went without a question' if shows('near the second')
                             else 'another tag was picked over a form holding something typed: no question')
        self.assertFalse(shows('near the second'), 'the other tag opened before the answer')
        self.assertEqual(self.typed(a, 'Notes'), 'typed, then another tag picked')
        answer(d, 'Keep editing')
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), 'typed, then another tag picked', 'Keep editing lost what was typed')
        self.assertFalse(shows('near the second'), 'Keep editing opened the other tag')
        # … and Discard opens the other tag; nothing was sent
        pick(two)
        d = asked()
        self.assertIsNotNone(d, 'the second pick did not ask')
        answer(d, 'Discard')
        atspi.find(a, 'label', contains='near the second', timeout=10)
        self.assertIsNone(self.typed(a, 'Notes'), 'Discard left the form open')
        time.sleep(5)                # (two sync rounds: something sent would be on the server by now)
        self.assertEqual(notes(), '', 'Discard sent what was typed')
        # 3. the panel closed
        pick(one)
        atspi.find(a, 'label', contains='near the first', timeout=10)
        edit('typed, then the panel closed')
        atspi.click(atspi.find(a, 'button', name='Close the panel'))
        d = asked()
        self.assertIsNotNone(d, 'closing the panel over a form holding something typed did not ask')
        answer(d, 'Keep editing')
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), 'typed, then the panel closed', 'Keep editing lost what was typed')
        atspi.click(atspi.find(a, 'button', name='Close the panel'))
        d = asked()
        self.assertIsNotNone(d, 'closing the panel a second time did not ask')
        answer(d, 'Discard')
        for _ in range(40):
            if not atspi.find_all(a, 'button', name='Close the panel'):
                break
            time.sleep(0.25)
        self.assertFalse(atspi.find_all(a, 'button', name='Close the panel'), 'Discard did not close the panel')
        # 4. "Mark a tag" (it closes the panel)
        pick(one)
        atspi.find(a, 'label', contains='near the first', timeout=10)
        edit('typed, then Mark a tag')
        atspi.click(atspi.find(a, 'button', name='Mark a tag the app missed'))
        d = asked()
        self.assertIsNotNone(d, 'Mark a tag over a form holding something typed did not ask')
        answer(d, 'Keep editing')
        time.sleep(1)
        self.assertEqual(self.typed(a, 'Notes'), 'typed, then Mark a tag', 'Keep editing lost what was typed')
        self.assertFalse(atspi.find_all(a, None, contains='Drag a box around the tag'), 'Keep editing started marking')
        atspi.click(atspi.find(a, 'button', name='Mark a tag the app missed'))
        d = asked()
        self.assertIsNotNone(d, 'Mark a tag a second time did not ask')
        answer(d, 'Discard')
        atspi.find(a, None, contains='Drag a box around the tag', timeout=10)
        for _ in range(40):          # (the panel slides out)
            if not atspi.find_all(a, 'button', name='Close the panel'):
                break
            time.sleep(0.25)
        self.assertFalse(atspi.find_all(a, 'button', name='Close the panel'), 'marking started with the panel left open')
        atspi.click(atspi.find(a, 'button', name='Cancel'))        # the banner's
        # 5. the review form ("Check this tag") holding something typed
        pick(doubt)
        atspi.find(a, 'text', name='KKS (with suffix)', timeout=10)
        time.sleep(1)
        atspi.set_text(atspi.find(a, 'text', name='KKS (with suffix)'), '11LAE43AP001')
        time.sleep(0.5)
        pick(two)
        d = asked()
        self.assertIsNotNone(d, 'another tag picked over a review form holding something typed did not ask')
        answer(d, 'Keep editing')
        time.sleep(1)
        self.assertEqual(self.typed(a, 'KKS (with suffix)'), '11LAE43AP001', 'Keep editing lost the review form\'s text')
        pick(two)
        d = asked()
        self.assertIsNotNone(d, 'the second pick over the review form did not ask')
        answer(d, 'Discard')
        atspi.find(a, 'label', contains='near the second', timeout=10)
        time.sleep(5)
        self.assertIsNone(b.req('GET', '/api/state')['reviews'].get('sample:doubt2'), 'Discard sent the review')
        # 6. the keyboard's place after Cancel and after Save: the new panel's Edit button

        def focus():
            with open(focus_file) as f:
                return f.read()

        def edit_has_focus(after):
            for _ in range(40):
                if focus() == 'button Edit':
                    return
                time.sleep(0.25)
            self.fail(f'after {after} the keyboard focus is on {focus()!r}, not on the panel\'s Edit button')
        pick(one)
        atspi.find(a, 'label', contains='near the first', timeout=10)
        edit('')
        atspi.click(atspi.find(a, 'button', name='Cancel'))
        edit_has_focus('Cancel')
        edit('saved, then the focus')
        for _ in range(40):          # (the form's opening hid Edit: the focus has left it, so finding it there after Save is new)
            if focus() != 'button Edit':
                break
            time.sleep(0.25)
        self.assertNotEqual(focus(), 'button Edit')
        atspi.click(atspi.find(a, 'button', name='Save'))
        for _ in range(60):
            if notes() == 'saved, then the focus':
                break
            time.sleep(0.25)
        self.assertEqual(notes(), 'saved, then the focus')
        edit_has_focus('Save')
        self.assertIsNone(app.poll(), 'the app died')
        # 7. the window closed (#163): asked the same way; the close is refused while the question is up, Keep editing
        # keeps the window and the text, Discard closes it without sending. (A form with nothing typed closes at
        # once: test_zzzzzzz_form_kept's end.)
        edit('typed, then the window closed')
        atspi.click(atspi.find(a, 'button', name='Close'))
        d = asked()
        self.assertIsNotNone(d, 'closing the window over a form holding something typed did not ask'
                             if app.poll() is None else 'the window closed over a form holding something typed')
        self.assertIsNone(app.poll(), 'the window closed while the question was on screen')
        answer(d, 'Keep editing')
        time.sleep(1)
        self.assertIsNone(app.poll(), 'Keep editing closed the window')
        self.assertEqual(self.typed(a, 'Notes'), 'typed, then the window closed', 'Keep editing lost what was typed')
        atspi.click(atspi.find(a, 'button', name='Close'))
        d = asked()
        self.assertIsNotNone(d, 'closing the window a second time did not ask')
        self.assertEqual(self.criticals('formask'), [])
        atspi.click(atspi.find(d, 'button', name='Discard'))
        try:
            app.wait(15)
        except subprocess.TimeoutExpired:
            self.fail('Discard did not close the window')
        self.assertEqual(notes(), 'saved, then the focus', 'Discard sent what was typed')
        self.assertEqual(self.criticals('formask'), [])


class Coverage(Plant):
    """Coverage counts every code, tag, place and photo of the plant: on a server of its own, so the totals are the
    test plant's whatever ran before (on the shared one they changed with the tags test_multi and test_systems add)"""

    def test_coverage(self):
        """Coverage: the totals match the test plant (one code, marked by a person, so checked); the photo bars are
        named by their numbers; a sheet row opens that sheet coloured by photos; a system row opens Equipment by system
        filtered to it"""
        os.makedirs(SHOTS, exist_ok=True)
        shot = os.path.join(SHOTS, 'gnome-coverage.png')
        a = self.start_app('coverage', KKS_SHOT_ON_SIGNAL=shot, KKS_SYNC_EVERY='2000')
        pid = self.apps[-1].pid
        self.join(a)
        st = self.boss.req('GET', '/api/state')
        eq = st['equipment'].get('11LAB70AA501', {})
        placed = 1 if any(str(eq.get(f, '')).strip() for f in ('area', 'floor', 'elev', 'near', 'loc')) else 0
        caps = [p.get('caption') or '' for p in st['photos'] if p['kks'] == '11LAB70AA501']
        plate, equip = any(c.startswith('Tag plate') for c in caps), any(not c.startswith('Tag plate') for c in caps)
        ph = {'both': int(plate and equip), 'equipment': int(equip and not plate), 'plate': int(plate and not equip)}
        ph['none'] = 1 - sum(ph.values())
        atspi.click(atspi.find(a, 'button', name='Coverage'))
        atspi.find(a, None, name='1 code on the drawings, in 1 tag', timeout=10)
        atspi.find(a, 'label', name='1 of 1 tag (100 %)', timeout=10)               # checked by a person
        atspi.find(a, 'label', name=f'{placed} of 1 code ({100 * placed} %)')       # known place
        atspi.find(a, 'label', name=f"both {ph['both']} · equipment only {ph['equipment']} · tag plate only "
                                    f"{ph['plate']} · none {ph['none']}")
        words = (f"photos: {ph['both']} equipment and tag plate, {ph['equipment']} equipment only, {ph['plate']} tag "
                 f"plate only, {ph['none']} none")
        for _ in range(20):        # the bars' accessible names can arrive a moment after the labels
            bars = atspi.find_all(a, 'image', name=words)
            if len(bars) >= 3: break
            time.sleep(0.5)
        self.assertGreaterEqual(len(bars), 3, 'the totals, the sheet and the system each have a named bar')
        os.kill(pid, signal.SIGUSR1)       # a picture of the page, to look at
        for title, value in (('Readings to review', '0'), ('Missed tags marked', '1')):
            item = atspi.find(a, 'list item', name=title)
            self.assertIn(value, [n.get_name() for n in atspi.walk(item) if n.get_role_name() == 'label'])
        atspi.find(a, 'label', name='0 codes · – of tags checked · – placed')               # the second sheet has no tags
        # the open page follows a sync: a place given on the server is counted without reopening it
        if not placed:
            r = self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                                                      'changes': {'area': 'Test hall'}}})
            self.assertEqual(r.get('status'), 'approved', r)
            atspi.find(a, 'label', name='1 of 1 code (100 %)', timeout=20)
        # a sheet row opens that sheet (the first one is shown at the start) with the photo colours on
        tb = atspi.find(a, 'toggle button', name='Colour tags by photos', showing=False)
        self.assertFalse(tb.get_state_set().contains(Atspi.StateType.PRESSED))
        before = len(atspi.find_all(a, 'label', name='Second sheet'))
        # (an AdwActionRow names its activatable button by the row's title; the sidebar's own row is not showing)
        atspi.click(atspi.find(a, 'button', name='Second sheet'))
        for _ in range(20):
            after = len(atspi.find_all(a, 'label', name='Second sheet'))
            if after > before and tb.get_state_set().contains(Atspi.StateType.PRESSED):
                break
            time.sleep(0.5)
        self.assertGreater(after, before, 'the drawing\'s title does not show the second sheet')
        self.assertTrue(tb.get_state_set().contains(Atspi.StateType.PRESSED), 'the photo colours are not on')
        # a system row opens Equipment by system with that system only, opened down to the code
        atspi.click(atspi.find(a, 'button', name='LAB · Feed water piping system'))
        atspi.find(a, 'label', name='1 code in system LAB', timeout=10)
        atspi.find(a, 'list item', name='11LAB70AA501', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Show all systems'))
        atspi.find(a, 'label', name='1 code on the drawings', timeout=10)


class FakeNode:
    """an accessible object as the helpers read it; `gone`: the app removed it after it was found (every read fails
    as AT-SPI's does); `clicks`: how many clicks fail that way before one works (-1: it has no
    action interface, which is what a vanished object answers there)"""

    def __init__(self, role, name='', kids=(), gone=False, clicks=0, hung=False, showing=True):
        self.role, self.name, self.kids, self.gone, self.clicks, self.clicked = role, name, list(kids), gone, clicks, 0
        self.hung, self.showing = hung, showing

    def _read(self, v):
        if self.hung:              # another error than "gone": the app does not answer
            raise GLib.GError('atspi_error: Timeout was reached')
        if self.gone:
            raise GLib.GError('atspi_error: No such interface \u201corg.a11y.atspi.Accessible\u201d on object at path /x')
        return v

    def get_child_count(self): return self._read(len(self.kids))
    def get_role_name(self): return self._read(self.role)
    def get_name(self): return self._read(self.name)
    def get_state_set(self): return self._read(self)
    def contains(self, state): return self.showing
    def get_action_iface(self): return None if self.clicks < 0 else self
    def get_n_actions(self): return 1
    def get_action_name(self, i): return 'click'

    def get_child_at_index(self, i):
        k = self.kids[i]
        if k == 'gone':            # removed between the count and the read
            raise GLib.GError('atspi_error: No such interface')
        return k

    def do_action(self, i):
        if self.clicks > 0:
            self.clicks -= 1
            raise GLib.GError('atspi_error: No such interface')
        self.clicked += 1
        return True


class Vanished(unittest.TestCase):
    """#143: the app rebuilds parts of its screen (a sync, a request arriving), so an object the test found can be gone
    when it is read. The helpers leave such an object out and look again; a widget that is really missing still fails."""

    def tree(self):
        self.ok = FakeNode('button', 'Accept')
        return FakeNode('window', 'w', [FakeNode('button', 'Accept', gone=True), 'gone',
                                        FakeNode('box', '', [self.ok, FakeNode('label', 'Accept')])])

    def test_vanished_nodes_are_left_out(self):
        root = self.tree()
        self.assertEqual([n for n, nm in atspi.nodes(root, 'button') if nm == 'Accept'], [self.ok])
        self.assertEqual(atspi.find_all(root, 'button', name='Accept'), [self.ok])
        self.assertEqual(atspi.find_all(root, 'button', name='Accep'), [], 'an exact name, not a part of one')
        self.assertIs(atspi.find(root, 'button', name='Accept', timeout=1), self.ok)

    def test_a_missing_widget_still_fails(self):
        root = FakeNode('window', 'w', [FakeNode('button', 'Accept', gone=True), 'gone'])
        self.assertEqual(list(atspi.nodes(root, 'button')), [])
        with self.assertRaisesRegex(AssertionError, "no button named 'Accept'"):
            atspi.find(root, 'button', name='Accept', timeout=0.5)
        with self.assertRaisesRegex(AssertionError, "no button named 'Accept' to click"):
            atspi.click_named(root, 'button', 'Accept', timeout=0.5)

    def test_other_errors_and_hidden_nodes_are_not_swallowed(self):
        root = FakeNode('window', 'w', [FakeNode('box', '', [FakeNode('button', 'Accept', hung=True)])])
        with self.assertRaisesRegex(GLib.GError, 'Timeout was reached'):
            list(atspi.nodes(root, 'button'))
        with self.assertRaisesRegex(GLib.GError, 'Timeout was reached'):
            atspi.click_named(root, 'button', 'Accept', timeout=0.5)
        hidden = FakeNode('window', 'w', [FakeNode('button', 'Accept', showing=False)])
        self.assertEqual(atspi.find_all(hidden, 'button', name='Accept'), [], 'a node that is not showing was counted')
        self.assertEqual(len(list(atspi.nodes(hidden, 'button'))), 1)

    def test_click_looks_again(self):
        root = self.tree()
        self.ok.clicks = 2         # gone twice between the lookup and the click, then there
        atspi.click_named(root, 'button', 'Accept', timeout=5)
        self.assertEqual(self.ok.clicked, 1)
        for never in (10 ** 6, -1):    # never clickable: said, not looped for ever
            self.ok.clicks = never
            with self.assertRaisesRegex(AssertionError, "button 'Accept' could not be clicked: each time it had gone"):
                atspi.click_named(root, 'button', 'Accept', timeout=0.7)


if __name__ == '__main__':
    unittest.main()
