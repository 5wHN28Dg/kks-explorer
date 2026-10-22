"""Course progress between a person's own devices, end to end over the real sync (PROTOCOL-v2 §17, decision 0062):
three devices of the manager join the Nim server through "Join through a server" (apps/gnome/e2e/progress_peer, the
apps' own code without a window). Two pair by code and read each other's progress; the third, never paired, reads
nothing; the server answers no progress and no pairing, and its database file holds no progress in the clear.
  .venv/bin/python platform/linux/e2e/test_progress_pairing.py
$KKS_SERVER names the server build (default /tmp/kkslinux/kks_server), $KKS_PEER the progress_peer build."""
import http.cookiejar, json, os, shutil, subprocess, sys, tempfile, unittest, urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
PEER = os.environ.get('KKS_PEER', '/tmp/kkslinux/progress_peer')
sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(REPO, 'tests'))
from e2e_server import start_server  # noqa: E402


class Client:
    """the web API with a session cookie (no Playwright needed here)"""
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None):
        data = json.dumps(body).encode() if body is not None else None
        r = urllib.request.Request(self.base + p, data=data, method=m,
                                   headers=({'Content-Type': 'application/json'} if data else {}) | {'Origin': self.base})
        with self.op.open(r) as resp:
            return json.loads(resp.read())


class Peer:
    """one device: a data folder of its own, driven by progress_peer"""
    def __init__(self, root, name):
        self.dir = os.path.join(root, name)
        os.makedirs(self.dir)
        self.env = {**os.environ, 'KKS_DATA_DIR': self.dir, 'KKS_STORAGE_KEY_FILE': os.path.join(self.dir, 'key')}

    def run(self, *args):
        r = subprocess.run([PEER, *args], env=self.env, capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise AssertionError(f'progress_peer {args}: {r.stdout}{r.stderr}')
        return r.stdout.strip().splitlines()[-1] if r.stdout.strip() else ''

    def json(self, *args):
        return json.loads(self.run(*args))


class ProgressPairing(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-progress-')
        cfg = {'address': '127.0.0.1', 'plant_name': 'Test plant', 'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'),
               'store': os.path.join(cls.dir, 'server.db'), 'storage_key_file': os.path.join(cls.dir, 'storage.key'),
               'plant_dir': os.path.join(cls.dir, 'plant-data'), 'backup_dir': os.path.join(cls.dir, 'backups')}
        cls.server, setup = start_server(SERVER, cls.dir, cfg, sync=True)
        cls.base = 'http://127.0.0.1:%d' % cfg['port']
        cls.boss = Client(cls.base)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        cls.boss.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'})
        cls.a, cls.b, cls.c = (Peer(cls.dir, n) for n in ('laptop', 'tablet', 'other'))
        for p in (cls.a, cls.b, cls.c):
            assert p.run('join', '127.0.0.1:%d' % cfg['sync_port'], 'boss', 'a long password') == 'joined'
            p.id = p.run('device')

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def row(self, peer, other):
        got = peer.json('pairing')
        self.assertTrue(got['ready'], got)
        return next((d for d in got['devices'] if d['device'] == other.id), None)

    def until(self, peer, other, state, tries=8):
        """sync this device until its row for `other` reaches `state` (pairing steps travel through the server)"""
        for _ in range(tries):
            r = self.row(peer, other)
            if r and r['state'] == state:
                return r
        self.fail(f'{state!r} never reached: {r}')

    def test_pairing_and_progress(self):
        # every device must have synced its box key before the others list it
        for p in (self.a, self.b, self.c):
            p.run('pairing')
        self.assertEqual(self.row(self.a, self.b)['state'], 'none')
        self.a.run('save', 'fnd', 'solved', '{"q1_r":true}')
        self.assertEqual(self.b.json('progress', 'fnd'), {}, 'nothing before pairing')
        self.a.json('pair', self.b.id)
        self.until(self.b, self.a, 'asked')
        self.assertEqual(self.row(self.a, self.b)['state'], 'waiting')
        self.b.json('pair', self.a.id)
        ab = self.until(self.a, self.b, 'compare')['code']
        ba = self.until(self.b, self.a, 'compare')['code']
        self.assertRegex(ab, r'^\d{6}$')
        self.assertEqual(ab, ba, 'both screens show the same code')
        self.assertEqual(self.b.json('progress', 'fnd'), {}, 'nothing before the person confirmed')
        self.a.json('confirm', self.b.id, ab)
        self.b.json('confirm', self.a.id, ba)
        self.a.run('pairing')         # takes the tablet's share in
        self.assertEqual(json.loads(self.b.json('progress', 'fnd')['solved']), {'q1_r': True})
        self.b.run('save', 'fnd', 'finalBest', '9')
        self.b.run('save', 'fnd', 'solved', '{"q1_r":true,"q2_f":true}')
        got = self.a.json('progress', 'fnd')
        self.assertEqual(got['finalBest'], '9')
        self.assertEqual(json.loads(got['solved']), {'q1_r': True, 'q2_f': True})
        # the device nobody paired: certified for the same person by the server, it reads nothing
        self.assertEqual(self.c.json('progress', 'fnd'), {})
        # the server answers neither, and keeps no progress in the clear
        for path in ('/api/progress', '/api/pairing'):
            with self.assertRaises(Exception) as e:
                self.boss.req('GET', path)
            self.assertIn('404', str(e.exception))
        with open(os.path.join(self.dir, 'server.db'), 'rb') as f:
            raw = f.read()
        for word in (b'q1_r', b'q2_f', b'finalBest', b'solved'):
            self.assertNotIn(word, raw)


if __name__ == '__main__':
    unittest.main()
