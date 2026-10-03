"""The phone move rehearsal (decision 0042, PROTOCOL-v2 §21a) on an emulator, end to end:
  1. a v1 plant (tools/m6/v1_test_plant.py) served by the v1 Python server; the old app (debug build of android/app,
     the bridge) joins it as teammate tom;
  2. the v1 server stops; on the phone tom then adds a photo with a note for the approver and a procedure link: they
     never reach the v1 server;
  3. the cutover: migrate_v1 export, kks-server import-v1, succession, import-succession; the Nim server starts on the
     v1 server's sync port;
  4. the bridge finds the new app in a signed test release (a local fake GitHub), installs it (Android's dialog), opens it;
  5. the new app moves by itself: the server shows tom's photo (with its note and file) and link as open proposals
     from Tom, and the bridge offers to remove the old app.
  python3 android/app2/e2e/test_move.py [V1_APK] [V2_APK] [SERVER]
Needs a running emulator, .venv (cryptography), and the debug builds (DebugApiReceiver, DebugUpdateReceiver)."""
import base64, http.server, json, os, re, shutil, subprocess, sys, tempfile, threading, time, unittest, urllib.request, urllib.error, http.cookiejar
sys.path.insert(0, os.path.dirname(__file__))
import adbui as ui  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
V1_APK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'android/app/build/outputs/apk/debug/app-debug.apk')
V2_APK = sys.argv[2] if len(sys.argv) > 2 else os.path.join(REPO, 'android/app2/build/outputs/apk/debug/app2-debug.apk')
SERVER = sys.argv[3] if len(sys.argv) > 3 else '/tmp/kkslinux/kks_server'
del sys.argv[1:]
OLD, NEW = 'kks.explorer', 'io.github.walkdown'
PY = os.path.join(REPO, '.venv/bin/python') if os.path.exists(os.path.join(REPO, '.venv/bin/python')) else 'python3'
HOST = '10.0.2.2'          # this machine, seen from the emulator
sys.path.insert(0, REPO)
from tools import release  # noqa: E402


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + p, data=data, method=m, headers={'Content-Type': 'application/json'} if data else {})
        try:
            with self.op.open(r) as resp:
                b = resp.read()
                return json.loads(b) if resp.headers.get('Content-Type', '').startswith('application/json') else b
        except urllib.error.HTTPError as e:
            return {'status': e.code, 'error': e.read().decode()}


_n = [0]


def old_api(method, path, body=None, timeout=60):
    """one call of the old app's local API (DebugApiReceiver); -> (status, json)"""
    _n[0] += 1
    n = str(_n[0])
    ui.adb('logcat', '-c')
    req = base64.b64encode(json.dumps({'method': method, 'path': path, 'body': body}).encode()).decode()
    ui.sh('am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_API', '-p', OLD, '--es', 'req', req, '--es', 'n', n)
    t0 = time.time()
    while time.time() - t0 < timeout:
        out = subprocess.run(ui.ADB + ['logcat', '-d', '-s', 'KKSDebug'], capture_output=True, text=True).stdout
        m = re.search(rf'result {n} (\d+) (.*)$', out, re.M)
        if m:
            return int(m[1]), json.loads(m[2])
        time.sleep(0.5)
    raise AssertionError(f'no answer from the old app for {path}')


def tiny_png():
    import struct, zlib
    def chunk(t, d):
        return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    rows = b''.join(b'\x00' + b''.join(bytes([(x * 5 + y * 3) % 256, (x * 2) % 256, 180]) for x in range(64)) for y in range(48))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 64, 48, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))


def calm():
    """the emulator's "System UI isn't responding" dialog eats taps (CLAUDE.md, M3c): wait it out"""
    for _ in range(3):
        if ui.present("isn't responding"):
            ui.tap('Wait', exact=True)
            time.sleep(1)


class FakeGitHub:
    """GitHub's releases/latest with a release.json signed by a test key, and the files"""
    def __init__(self, files):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        key = Ed25519PrivateKey.generate()
        self.pub = release.public_b64u(key)
        version = open(os.path.join(REPO, 'VERSION')).read().strip()
        m = release.manifest(version, files)
        self.blobs = {n: open(p, 'rb').read() for n, p in files.items()}
        self.blobs['release.json'] = m
        self.blobs['release.json.sig'] = release.sign(m, key).encode()
        me = self

        class H(http.server.BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                if self.path == '/repos/x/releases/latest':
                    base = f'http://{HOST}:{self.server.server_address[1]}/f/'
                    body = json.dumps({'assets': [{'name': n, 'browser_download_url': base + n} for n in me.blobs]}).encode()
                elif self.path.startswith('/f/') and self.path[3:] in me.blobs:
                    body = me.blobs[self.path[3:]]
                else:
                    self.send_response(404); self.end_headers(); return
                self.send_response(200); self.send_header('Content-Length', str(len(body))); self.end_headers()
                self.wfile.write(body)
        self.httpd = http.server.ThreadingHTTPServer(('127.0.0.1', 0), H)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.api = f'http://{HOST}:{self.httpd.server_address[1]}/repos/x/releases/latest'


class Move(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-move-')
        subprocess.run([PY, os.path.join(REPO, 'tools/m6/v1_test_plant.py'), 'make', cls.dir], check=True, capture_output=True)
        cls.port1, cls.sport = free_port(), free_port()
        v1 = os.path.join(cls.dir, 'v1')
        cfg1 = {'host': '127.0.0.1', 'port': cls.port1, 'sync_port': cls.sport, 'mode': 'server', 'discovery': False,
                'db': os.path.join(v1, 'plant.db'), 'photos_dir': os.path.join(v1, 'photos'), 'root_key': os.path.join(v1, 'root.key'),
                'backup_dir': os.path.join(v1, 'backups'), 'plant_name': 'Test plant', 'sync_interval': 0}
        with open(os.path.join(cls.dir, 'v1.json'), 'w') as f:
            json.dump(cfg1, f)
        cls.v1 = subprocess.Popen([PY, os.path.join(REPO, 'app.py')], cwd=REPO, env=dict(os.environ, KKS_CONFIG=os.path.join(cls.dir, 'v1.json')),
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        cls.v2 = None
        time.sleep(3)
        ui.sh('am', 'force-stop', OLD)
        for p in (NEW, OLD):                                     # a clean emulator: no earlier copies of either app
            subprocess.run(ui.ADB + ['uninstall', p], capture_output=True)
        r = subprocess.run(ui.ADB + ['install', '-t', V1_APK], capture_output=True, text=True)
        assert 'Success' in r.stdout, r.stdout + r.stderr
        ui.sh('am', 'start', '-n', f'{OLD}/.MainActivity')     # out of the stopped state (broadcasts reach it)
        time.sleep(3)

    @classmethod
    def tearDownClass(cls):
        for p in (cls.v1, cls.v2):
            if p and p.poll() is None:
                p.terminate(); p.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def test_move(self):
        # 1. the old app joins the v1 plant as tom
        st, r = old_api('POST', '/api/node/join-server', {'url': f'http://{HOST}:{self.port1}', 'username': 'tom', 'password': 'a long password'})
        self.assertEqual(st, 200, r)
        st, cfg = old_api('GET', '/api/config')
        dev = cfg['node']['device']
        import sqlite3
        db = sqlite3.connect(f'file:{os.path.join(self.dir, "v1", "plant.db")}?mode=ro', uri=True)
        self.assertTrue(db.execute('SELECT count(*) FROM entries WHERE data LIKE ?', (f'%{dev}%',)).fetchone()[0] > 0,
                        'the v1 server never certified the phone')
        db.close()
        # 2. the v1 server stops; the phone works on: a photo with a note, a link
        self.v1.terminate(); self.v1.wait(5)
        png = 'data:image/png;base64,' + base64.b64encode(tiny_png()).decode()
        st, r = old_api('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'dataUrl': png, 'caption': 'Nameplate — ü'},
                                                 'note': 'Taken today'}, timeout=120)
        self.assertEqual((st, r.get('status')), (200, 'pending'), r)
        st, r = old_api('POST', '/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 4, 'kks': '11LAB70AA501', 'on': True}})
        self.assertEqual((st, r.get('status')), (200, 'pending'), r)
        # 3. the cutover on the server side
        pkg, succ = os.path.join(self.dir, 'pkg.json'), os.path.join(self.dir, 'succ.json')
        subprocess.run([PY, os.path.join(REPO, 'tools/m6/migrate_v1.py'), 'export', '--db', os.path.join(self.dir, 'v1/plant.db'),
                        '--photos', os.path.join(self.dir, 'v1/photos'), '--out', pkg], check=True, capture_output=True)
        port2 = free_port()
        cfg2 = {'address': '127.0.0.1', 'port': port2, 'sync_port': self.sport, 'plant_name': 'Test plant',
                'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
                'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
                'backup_dir': os.path.join(self.dir, 'backups')}
        c2 = os.path.join(self.dir, 'v2.json')
        with open(c2, 'w') as f:
            json.dump(cfg2, f)
        out = subprocess.run([SERVER, 'import-v1', pkg, '--config', c2], capture_output=True, text=True, check=True).stdout
        root = re.search(r'v2 root: (\S+)', out)[1]
        server = re.search(r'server:\s+(\S+)', out)[1]
        subprocess.run([PY, os.path.join(REPO, 'tools/m6/migrate_v1.py'), 'succession', '--db', os.path.join(self.dir, 'v1/plant.db'),
                        '--root-key', os.path.join(self.dir, 'v1/root.key'), '--v2-root', root, '--server', server, '--out', succ],
                       check=True, capture_output=True)
        out = subprocess.run([SERVER, 'import-succession', succ, '--config', c2], capture_output=True, text=True, check=True).stdout
        self.assertIn('succession statement kept', out)
        self.v2 = Move.v2 = subprocess.Popen([SERVER, 'serve', '--config', c2], cwd=self.dir, stdout=subprocess.PIPE,
                                             stderr=subprocess.STDOUT, text=True)
        time.sleep(1.5)
        boss = Client(f'http://127.0.0.1:{port2}')
        self.assertIn('user', boss.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'}))   # the v1 password still works
        # 4. the bridge: a signed test release with the new app; Android's installer asks once
        gh = FakeGitHub({'kks-explorer.apk': V1_APK, 'walkdown.apk': V2_APK})
        ui.sh('appops', 'set', OLD, 'REQUEST_INSTALL_PACKAGES', 'allow')
        ui.sh('am', 'broadcast', '-a', 'kks.explorer.DEBUG_UPDATE', '-p', OLD, '--es', 'api', gh.api, '--es', 'pub', gh.pub)
        time.sleep(2)
        ui.sh('am', 'start', '-n', f'{OLD}/.MainActivity')
        calm()
        ui.tap('Install Walkdown', exact=True, timeout=30)
        # Android's own dialog ("INSTALL" on Android 16, "Install" on others)
        t0 = time.time()
        while not (ui.present('INSTALL', exact=True) or ui.present('Install', exact=True)) and time.time() - t0 < 90:
            calm(); time.sleep(1)
        ui.tap('INSTALL' if ui.present('INSTALL', exact=True) else 'Install', exact=True)
        # 5. the new app opens by itself and moves
        t0 = time.time()
        subs = []
        while time.time() - t0 < 180:
            subs = [s for s in boss.req('GET', '/api/submissions?status=open').get('submissions', []) if s.get('by_name') == 'Tom Teammate']
            if len(subs) >= 2:
                break
            time.sleep(2)
        kinds = sorted(s['kind'] for s in subs)
        self.assertEqual(kinds, ['link', 'photo'], subs)
        photo = next(s for s in subs if s['kind'] == 'photo')
        self.assertEqual(photo['request_note'], 'Taken today')
        self.assertEqual(photo['payload']['caption'], 'Nameplate — ü')
        f = boss.req('GET', '/photos/' + photo['payload']['file'])
        self.assertTrue(isinstance(f, bytes) and f[:2] == b'\xff\x0a', 'the photo file did not arrive as JPEG XL')
        devs = boss.req('GET', '/api/devices')
        self.assertEqual(devs['sync'].get('v1_waiting', []) and [w['name'] for w in devs['sync']['v1_waiting'] if w['name'] == 'Tom Teammate'], [],
                         'the server still lists Tom\'s old phone as not moved')
        # the bridge knows it is done
        ui.sh('am', 'start', '-n', f'{OLD}/.MainActivity')
        calm()
        ui.find('Remove the old app', exact=True, timeout=20)
        # a second start of the new app writes nothing twice
        ui.sh('am', 'force-stop', NEW)
        ui.sh('am', 'start', '-n', f'{NEW}/kks.explorer.MainActivity')
        time.sleep(8)
        again = [s for s in boss.req('GET', '/api/submissions?status=open').get('submissions', []) if s.get('by_name') == 'Tom Teammate']
        self.assertEqual(len(again), 2)


if __name__ == '__main__':
    unittest.main()
