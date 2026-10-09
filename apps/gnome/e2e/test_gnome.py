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


class Plant(unittest.TestCase):
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
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
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

    def join(self, a):
        atspi.click(atspi.find(a, 'button', name='Join through a server'))
        atspi.set_text(atspi.find(a, 'text', name='Server address'), f'127.0.0.1:{self.sport}')
        atspi.set_text(atspi.find(a, 'text', name='Username'), 'boss')
        atspi.set_text(atspi.find(a, 'password text', name='Password'), 'a long password')
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
        return sum(1 for r, g, b in px if abs(r - 176) < 30 and g < 70 and abs(b - 158) < 30)


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
        # every new member needs a position (the user's request): the form refuses without one
        atspi.click(atspi.find(b, 'button', name='Join with this code'))
        atspi.find(b, 'label', contains='every new member needs a position', timeout=10)
        atspi.set_text(atspi.find(b, 'text', name='Your position (job title)'), 'Process engineer')
        atspi.click(atspi.find(b, 'button', name='Join with this code'))
        acc = None
        for _ in range(30):
            time.sleep(0.5)
            acc = [n for n in atspi.walk(a, maxdepth=80) if n.get_role_name() == 'button' and n.get_name() == 'Accept']
            if acc:
                break
        self.assertTrue(acc, 'the admin never saw the request')
        # the admin sees the position the request carries
        atspi.find(a, 'label', contains='position Process engineer', timeout=10)
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
        # a photo needs each code's floor: AP003 has none, so Photo for all says so and opens nothing; Place for all
        # sets it (AP001's floor 3 is replaced), then the photo goes
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
        atspi.find(a, 'label', contains="No floor yet: 11LAC10AP003", timeout=10)
        atspi.click(atspi.find(a, 'button', name='Place for all…'))
        pd = atspi.find(a, 'dialog', name='Place for all', timeout=10)
        atspi.set_text(atspi.find(pd, 'text', name='Floor'), '4')
        atspi.click(atspi.find(pd, 'button', name='Send'))
        alert = atspi.find(a, 'alert', name='Replace values?', timeout=10)
        atspi.click(atspi.find(alert, 'button', name='Send'))
        atspi.find(a, 'label', name='Sent for 2 codes · saved', timeout=10)
        atspi.click(mode)
        atspi.find(a, 'label', name='0 selected', timeout=10)
        for i, k in enumerate(('11LAC10AP001', '11LAC10AP003')):
            atspi.set_text(search, k[2:])
            atspi.click(atspi.find(a, 'button', name=k, timeout=10))
            atspi.find(a, 'label', name=f'{i + 1} selected', timeout=10)
        atspi.click(atspi.find(a, 'button', name='Photo for all…'))
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
        before = len([n for n in atspi.find_all(a, 'label') if n.get_name() == '11LAB70AA501'])
        atspi.click(atspi.find(a, 'button', name='11LAB70AA501', timeout=10))
        atspi.find(a, 'button', name='Close the panel', timeout=10)
        for _ in range(20):
            after = len([n for n in atspi.find_all(a, 'label') if n.get_name() == '11LAB70AA501'])
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
            # the panel rebuilds after each sync round: a click on the button it just replaced is lost, so again
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
                for c in [n for n in atspi.find_all(a, 'button', contains='Cancel') if n.get_name() == 'Cancel']:
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
            bars = [n for n in atspi.find_all(a, 'image') if n.get_name() == words]
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
        before = len([n for n in atspi.find_all(a, 'label') if n.get_name() == 'Second sheet'])
        # (an AdwActionRow names its activatable button by the row's title; the sidebar's own row is not showing)
        atspi.click(atspi.find(a, 'button', name='Second sheet'))
        for _ in range(20):
            after = len([n for n in atspi.find_all(a, 'label') if n.get_name() == 'Second sheet'])
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


if __name__ == '__main__':
    unittest.main()
