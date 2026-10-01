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
del sys.argv[1:]
PKG = 'kks.explorer.v2'


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
               'glyphs': os.path.join(REPO, 'extractor', 'fontlib.kgl')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
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
        # a fresh app
        ui.adb('install', '-r', APK)
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

    def test_courses(self):
        """the JSON courses (decision 0036): Learning lists them; a course page; a figure as an image for TalkBack;
        a question answered (progress shown); an animated figure on screen"""
        ui.tap('Join through a server', exact=True)
        ui.type_into('Server address', f'10.0.2.2:{self.sport}')
        ui.type_into('Username', 'boss')
        ui.type_into('Password', 'a long password')
        ui.tap('Join', exact=True)
        ui.find('Sample sheet', timeout=40)
        ui.tap('Learning', exact=True)
        ui.find('0 of 76 questions solved', timeout=15)
        ui.tap('Rumaila Plant Foundations', exact=True)
        ui.tap('Contents', exact=True, timeout=15)
        ui.tap('1 · Combined cycle', exact=True)
        ui.find('The combined cycle. Combined cycle:', timeout=15)
        ui.scroll_to('Once the gas cools below HP boiling temperature')
        ui.tap('Once the gas cools below HP boiling temperature')
        ui.find('Right.', exact=True, timeout=10)
        ui.find('1 of 76 solved', exact=True, timeout=10)
        ui.tap('Contents', exact=True)
        ui.tap('6 · Valves & pumps', exact=True)
        ui.scroll_to('Gate valve cutaway. ', tries=30)
        time.sleep(1.5)
        with open('/tmp/kks-android-course.png', 'wb') as f:
            f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
        # leave a fresh app and no extra device for test_flow
        model = ui.sh('getprop', 'ro.product.model').strip()
        for d in self.boss.req('GET', '/api/devices')['all']:
            if d['username'] == 'boss' and d['label'] == model and not d['revoked']:
                self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
        ui.sh('pm', 'clear', PKG)
        ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')
        time.sleep(3)

    def test_flow(self):
        # join through the server (PROTOCOL-v2 §16 enroll over TLS)
        ui.tap('Join through a server', exact=True)
        ui.type_into('Server address', f'10.0.2.2:{self.sport}')
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
        r = self.boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali Member', 'role': 'user'})
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


if __name__ == '__main__':
    unittest.main()
