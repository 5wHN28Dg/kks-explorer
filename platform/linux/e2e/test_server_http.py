"""End-to-end: the Nim server binary over real HTTP, driven like the web pages do (stdlib only).
  python3 platform/linux/e2e/test_server_http.py /path/to/kks_server
The Drawings test also needs the importer: KKS_IMPORT=/path/to/kks_import (default /tmp/kksimp/kks_import)."""
import base64, http.cookiejar, json, os, re, socket, subprocess, sys, tempfile, time, unittest, urllib.request, urllib.error

BIN = sys.argv.pop(1) if len(sys.argv) > 1 else '/tmp/kkslinux/kks_server'
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))


def free_port():
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


class Client:
    def __init__(self, base):
        self.base, self.jar = base, http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))

    def req(self, method, path, body=None, headers=None, raw=None):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        h = {'Content-Type': 'application/json'} if body is not None else {}
        h.update(headers or {})
        r = urllib.request.Request(self.base + path, data=data, method=method, headers=h)
        try:
            with self.op.open(r) as resp:
                b = resp.read()
                return resp.status, (json.loads(b) if resp.headers.get('Content-Type', '').startswith('application/json') else b), resp.headers
        except urllib.error.HTTPError as e:
            b = e.read()
            try:
                return e.code, json.loads(b), e.headers
            except ValueError:
                return e.code, b, e.headers


IMPORTER = os.environ.get('KKS_IMPORT', '/tmp/kksimp/kks_import')


class Base(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-nim-server-')
        cls.port, cls.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': cls.sport, 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
        cls.proc = subprocess.Popen([BIN, 'serve', '--config', os.path.join(cls.dir, 'config.json')], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, cwd=cls.dir)
        cls.setup = None
        t0 = time.time()
        while time.time() - t0 < 10:
            line = cls.proc.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m:
                cls.setup = m[1]
            if 'server on' in line:
                break
        time.sleep(0.3)
        cls.base = f'http://127.0.0.1:{cls.port}'

    @classmethod
    def tearDownClass(cls):
        cls.proc.terminate(); cls.proc.wait(5)

    def manager(self):
        boss = Client(self.base)
        st, r, _ = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager'})
        self.assertEqual(st, 200, r)
        return boss


@unittest.skipUnless(os.path.exists(IMPORTER), 'the importer (kks_import) is not built')
class Drawings(Base):
    def wait(self, c):
        for _ in range(600):
            job = c.req('GET', '/api/sheets/job')[1]['job']
            if job['state'] != 'running':
                return job
            time.sleep(0.2)
        self.fail('import did not finish')

    def test_drawings(self):
        boss = self.manager()
        pdf = open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb').read()
        st, r, _ = boss.req('GET', '/api/sheets')
        self.assertEqual((st, r['importer']['available'], r['sheets']), (200, True, []), r)
        # upload: raw PDF body, the importer runs in the background, then the plant data is published
        st, r, _ = boss.req('POST', '/api/sheets/import?id=one&name=Sheet%20one', raw=pdf, headers={'Content-Type': 'application/pdf'})
        self.assertEqual(st, 200, r)
        self.assertEqual(boss.req('POST', '/api/sheets/import?id=two&name=Two', raw=pdf,
                                  headers={'Content-Type': 'application/pdf'})[0], 400)      # one import at a time
        job = self.wait(boss)
        self.assertEqual(job['state'], 'done', job['log'])
        self.assertEqual(job['result']['id'], 'one')
        self.assertIn('Rendering the overview pyramid...', job['log'])
        sheets = boss.req('GET', '/api/sheets')[1]['sheets']
        self.assertEqual([s['id'] for s in sheets], ['one'])
        self.assertTrue(sheets[0]['has_source'])
        self.assertGreaterEqual(sheets[0]['levels'], 1)
        version = boss.req('GET', '/api/sync/status')[1]['plant_data']
        st, kkp, _ = boss.req('GET', '/data/sheets/one.kkp')
        self.assertEqual((st, kkp[:4]), (200, b'KKP1'))
        st, o0, _ = boss.req('GET', '/data/sheets/one.o0.jxl')
        self.assertEqual(st, 200)
        self.assertEqual(boss.req('GET', '/data/sheets.json')[1][0]['id'], 'one')
        # not a PDF; an id that exists without replace
        self.assertEqual(boss.req('POST', '/api/sheets/import?id=bad&name=Bad', raw=b'%PDX', headers={'Content-Type': 'application/pdf'})[0], 400)
        self.assertEqual(boss.req('POST', '/api/sheets/import?id=one&name=Again', raw=pdf, headers={'Content-Type': 'application/pdf'})[0], 400)
        # re-import from the stored PDF with another rotation: the name is kept
        st, r, _ = boss.req('POST', '/api/sheets/reimport', {'id': 'one', 'rotate': '90'})
        self.assertEqual(st, 200, r)
        job = self.wait(boss)
        self.assertEqual((job['state'], job['result']['rotation'], job['result']['name']), ('done', 90, 'Sheet one'), job['log'])
        # a second sheet, then remove the first: its files go to a backup, a new version is published
        boss.req('POST', '/api/sheets/import?id=two&name=Two', raw=pdf, headers={'Content-Type': 'application/pdf'})
        self.assertEqual(self.wait(boss)['state'], 'done')
        st, r, _ = boss.req('POST', '/api/sheets/one/remove', {})
        self.assertEqual(st, 200, r)
        self.assertTrue(os.path.exists(os.path.join(self.dir, 'backups', r['backup'], 'one.kkp')))
        self.assertEqual([s['id'] for s in boss.req('GET', '/api/sheets')[1]['sheets']], ['two'])
        self.assertFalse(os.path.exists(os.path.join(self.dir, 'plant-data', 'sheets', 'one.kkp')))
        self.assertEqual(boss.req('POST', '/api/sheets/two/remove', {})[0], 400)            # the only sheet
        self.assertNotEqual(boss.req('GET', '/api/sync/status')[1]['plant_data'], version)
        # a failed import restores the sheet list
        before = open(os.path.join(self.dir, 'plant-data', 'sheets.json')).read()
        boss.req('POST', '/api/sheets/import?id=three&name=Broken', raw=b'%PDF-1.4 not really', headers={'Content-Type': 'application/pdf'})
        job = self.wait(boss)
        self.assertEqual(job['state'], 'failed')
        self.assertEqual(open(os.path.join(self.dir, 'plant-data', 'sheets.json')).read(), before)
        # managers only
        self.assertEqual(Client(self.base).req('GET', '/api/sheets')[0], 401)


class Server(Base):
    def test_flow(self):
        anon = Client(self.base)
        st, cfg, _ = anon.req('GET', '/api/config')
        self.assertEqual((st, cfg['setup_needed'], cfg['mode']), (200, True, 'server'))
        st, body, _ = anon.req('GET', '/')
        self.assertEqual(st, 200); self.assertIn(b'<html', body.lower())
        self.assertEqual(anon.req('GET', '/api/state')[0], 401)
        self.assertEqual(anon.req('GET', f'/api/token-info?kind=setup&token={self.setup}')[1]['kind'], 'setup')
        # setup creates the plant and signs the manager in
        boss = Client(self.base)
        st, r, _ = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager'})
        self.assertEqual(st, 200, r)
        self.assertEqual(boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'other', 'password': 'a long password',
                                                         'full_name': 'Nope'})[0], 403)
        st, me, _ = boss.req('GET', '/api/me')
        self.assertEqual((me['user']['username'], me['user']['role']), ('boss', 'manager'))
        # cross-origin and non-JSON posts are refused
        self.assertEqual(boss.req('POST', '/api/submit', {}, headers={'Origin': 'http://evil.example'})[0], 403)
        self.assertEqual(boss.req('POST', '/api/submit', raw=b'kind=x', headers={'Content-Type': 'application/x-www-form-urlencoded'})[0], 415)
        # an account for a user, password set by the one-time link
        st, r, _ = boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali User', 'role': 'user'})
        self.assertEqual(st, 200, r)
        token = r['link'].split('#reset=')[1]
        ali = Client(self.base)
        self.assertEqual(ali.req('POST', '/api/password-reset', {'token': token, 'password': 'short'})[0], 400)
        self.assertEqual(ali.req('POST', '/api/password-reset', {'token': token, 'password': 'ali password 1'})[0], 200)
        self.assertEqual(ali.req('POST', '/api/password-reset', {'token': token, 'password': 'ali password 2'})[0], 403)
        ali2 = Client(self.base)
        self.assertEqual(ali2.req('POST', '/api/login', {'username': 'ali', 'password': 'wrong one!!'})[0], 401)
        self.assertEqual(ali2.req('POST', '/api/login', {'username': 'ali', 'password': 'ali password 1'})[0], 200)
        # a proposal, the manager approves
        st, r, _ = ali2.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                                                    'changes': {'notes': 'leaks at the gland'}}, 'client_id': 'clientid01'})
        self.assertEqual((st, r['status']), (200, 'pending'), r)
        subs = boss.req('GET', '/api/submissions')[1]['submissions']
        self.assertEqual(subs[0]['by_name'], 'Ali User')
        self.assertEqual(boss.req('POST', f'/api/submissions/{subs[0]["id"]}/approve', {})[0], 200)
        self.assertEqual(ali2.req('GET', '/api/state')[1]['equipment']['11LAB70AA501']['notes'], 'leaks at the gland')
        # a photo: kept as a blob, served by hash
        png = b'\xff\x0a' + b'0' * 64     # a JPEG XL codestream's signature: the server stores JXL only
        st, r, _ = boss.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': 'gland',
                            'dataUrl': 'data:image/jxl;base64,' + base64.b64encode(png).decode()}})
        self.assertEqual((st, r['status']), (200, 'approved'), r)
        ph = boss.req('GET', '/api/state')[1]['photos'][0]
        st, data, hdr = boss.req('GET', '/photos/' + ph['file'])
        self.assertEqual((st, data), (200, png)); self.assertIn('immutable', hdr['Cache-Control'])
        self.assertEqual(anon.req('GET', '/photos/' + ph['file'])[0], 401)
        # History, the program's data, a bundle
        revs = boss.req('GET', '/api/revisions')[1]['revisions']
        self.assertGreaterEqual(len(revs), 2)
        self.assertEqual(ali2.req('GET', '/api/revisions')[0], 403)
        st, kks, _ = boss.req('GET', '/data/kks.json')
        self.assertEqual(st, 200)
        st, b, hdr = boss.req('GET', '/api/bundle?photos=1')
        self.assertEqual(st, 200); self.assertTrue(b.startswith(b'\x1f\x8b'))
        # a device enrolls with its owner's password (the GNOME/Android join via server)
        st, r, _ = anon.req('POST', '/api/devices/enroll', {'username': 'ali', 'password': 'ali password 1',
                                                            'device': 'A' * 32, 'label': 'phone'})
        self.assertEqual(st, 200, r); self.assertEqual(r['sync_port'], self.sport)
        # deactivation ends the session
        uid = [u for u in boss.req('GET', '/api/users')[1]['users'] if u['username'] == 'ali'][0]['id']
        self.assertEqual(boss.req('POST', f'/api/users/{uid}', {'active': False})[0], 200)
        self.assertEqual(ali2.req('GET', '/api/state')[0], 401)
        # logout
        self.assertEqual(boss.req('POST', '/api/logout', {})[0], 200)
        self.assertEqual(boss.req('GET', '/api/state')[0], 401)

    def test_login_throttle(self):
        c = Client(self.base)
        codes = [c.req('POST', '/api/login', {'username': 'nobody', 'password': 'x'})[0] for _ in range(7)]
        self.assertIn(429, codes)


if __name__ == '__main__':
    unittest.main()
