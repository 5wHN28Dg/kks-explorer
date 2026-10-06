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


class Cli(Base):
    def cli(self, *args):
        r = subprocess.run([BIN, *args, '--config', os.path.join(self.dir, 'config.json')], capture_output=True, text=True,
                           cwd=self.dir, timeout=60)
        return r.returncode, (r.stdout + r.stderr).strip()

    def test_cli_through_the_running_server(self):
        """found 2026-10-04: publish-data in a second process wrote to the store, but the running server never saw it
        (new sheets reached no device until a restart). Now the server runs it: no restart, at once."""
        boss = self.manager()
        sock = os.path.join(self.dir, 'kks-server.sock')
        self.assertEqual(os.stat(sock).st_mode & 0o777, 0o600)
        d = os.path.join(self.dir, 'cli-data')
        os.makedirs(d)
        for n in ('sheets.json', 'tags.json'):
            open(os.path.join(d, n), 'w').write('[]')
        self.assertEqual(self.cli('publish-data', d), (0, 'Published plant data version 1.'))
        self.assertEqual(boss.req('GET', '/api/sync/status')[1]['plant_data']['version'], 1)
        self.assertEqual(boss.req('GET', '/data/sheets.json')[1], [])
        self.assertEqual(self.cli('publish-data', d), (0, 'Unchanged: the files equal the latest version.'))
        # the plant's name: from the CLI and from the admin page; "" = none
        self.assertEqual(self.cli('set-plant-name', 'Unit test plant'), (0, 'The plant is called Unit test plant now.'))
        self.assertEqual(Client(self.base).req('GET', '/api/config')[1]['plant_name'], 'Unit test plant')
        self.assertEqual(boss.req('POST', '/api/settings/plant', {'name': '  '})[0], 200)
        self.assertEqual(Client(self.base).req('GET', '/api/config')[1]['plant_name'], '')
        self.assertEqual(boss.req('POST', '/api/settings/plant', {'name': 'x' * 81})[0], 400)
        code, out = self.cli('set-plant-name')
        self.assertNotEqual(code, 0)
        self.assertIn('usage', out)
        # submissions from a file, as the manager (tools/procedure_import.py writes these); a second run adds nothing
        subs = os.path.join(self.dir, 'subs.json')
        with open(subs, 'w') as f:
            json.dump([{'kind': 'link', 'payload': {'proc': 'EP-1', 'step': 1, 'kks': '11LAB70AA501', 'on': True}, 'client_id': 'imp-test-link-1'},
                       {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'custom': [{'k': 'Before start-up', 'v': 'open'}]},
                                                         'base': {'custom': []}}, 'client_id': 'imp-test-field-1'}], f)
        self.assertEqual(self.cli('submit-file', subs), (0, '2 submissions: 2 approved.'))
        self.assertEqual(self.cli('submit-file', subs), (0, '2 submissions: 2 already there.'))
        st = boss.req('GET', '/api/state')[1]
        self.assertEqual([l['kks'] for l in st['links'] if l['proc'] == 'EP-1'], ['11LAB70AA501'])
        self.assertEqual(st['equipment']['11LAB70AA501']['custom'], [{'k': 'Before start-up', 'v': 'open'}])
        # a password link and a new manager, from whoever runs the server (the manager account was lost)
        st, r, _ = boss.req('POST', '/api/users', {'username': 'sara', 'full_name': 'Sara Admin', 'role': 'admin'})
        self.assertEqual(st, 200, r)
        code, out = self.cli('reset-password', '--user', 'sara')
        self.assertEqual(code, 0, out)
        sara = Client(self.base)
        self.assertEqual(sara.req('POST', '/api/password-reset', {'token': out.split('#reset=')[1].strip(),
                                                                  'password': 'sara password 1'})[0], 200)
        self.assertEqual(sara.req('POST', '/api/login', {'username': 'sara', 'password': 'sara password 1'})[0], 200)
        self.assertEqual(self.cli('reset-manager', '--user', 'nobody')[0] != 0, True)
        code, out = self.cli('reset-manager', '--user', 'sara')
        self.assertEqual(code, 0, out)
        self.assertIn('sara is the manager now', out)
        roles = {u['username']: u['role'] for u in sara.req('GET', '/api/users')[1]['users']}
        self.assertEqual((roles['sara'], roles['boss']), ('manager', 'admin'))
        self.assertIn('already the manager', self.cli('reset-manager', '--user', 'sara')[1])


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



class Limits(Base):
    """finding #27 (advisory GHSA-xfj6-p785-whg5): request limits before authentication"""

    def conn(self, src='127.0.0.1', timeout=None):
        return socket.create_connection(('127.0.0.1', self.port), timeout=timeout, source_address=(src, 0))

    def closed_count(self, socks):
        time.sleep(1)
        closed = 0
        for s in socks:                  # one non-blocking look each: waiting per socket would reach the idle timeout
            s.setblocking(False)
            try:
                if s.recv(1) == b'':
                    closed += 1
            except BlockingIOError:
                pass
            except ConnectionResetError:
                closed += 1
            s.close()
        return closed

    def raw(self, data, wait=5.0):
        c = self.conn(timeout=wait)
        c.sendall(data)
        out = b''
        try:
            while True:
                b = c.recv(65536)
                if not b:
                    break
                out += b
        except socket.timeout:
            out += b'<timeout>'
        c.close()
        return out

    def test_chunked_body_refused(self):
        r = self.raw(b'POST /api/login HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\nffffffff\r\n')
        self.assertTrue(r.startswith(b'HTTP/1.1 411'), r[:80])
        self.assertEqual(Client(self.base).req('GET', '/api/config')[0], 200)   # still serving

    def test_any_transfer_encoding_refused(self):
        """not only chunked POST: another method's chunked body would be read as the next request (smuggling)"""
        smuggled = b'5\r\nGET /\r\n0\r\n\r\n'
        for head in (b'PUT /api/config HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: chunked\r\n\r\n',
                     b'POST /api/login HTTP/1.1\r\nHost: x\r\nContent-Length: 5\r\nTransfer-Encoding: chunked\r\n\r\n',
                     b'GET /api/config HTTP/1.1\r\nHost: x\r\nTransfer-Encoding: gzip\r\n\r\n'):
            with self.subTest(head=head[:40]):
                r = self.raw(head + smuggled)
                self.assertTrue(r.startswith(b'HTTP/1.1 411'), r[:80])
                self.assertEqual(r.count(b'HTTP/1.1 '), 1, r)      # nothing after it was read as a request

    def test_slow_headers_closed(self):
        c = socket.create_connection(('127.0.0.1', self.port), timeout=40)
        c.sendall(b'GET /api/config HTTP/1.1\r\nHost: x\r\n')         # never finishes the headers
        t0 = time.time()
        self.assertEqual(c.recv(1), b'')                                  # the server closes it
        self.assertLess(time.time() - t0, 30)
        c.close()

    def test_connections_per_address_capped(self):
        # from 127.0.0.2, which no other test uses, so no other connection shares the count
        closed = self.closed_count([self.conn('127.0.0.2') for _ in range(70)])
        self.assertGreaterEqual(closed, 6)       # 64 per address: the rest are closed at once
        self.assertLessEqual(closed, 6)          # ... and only those
        self.assertEqual(Client(self.base).req('GET', '/api/config')[0], 200)
        # the slots come back when connections end: 64 complete requests at once, twice
        time.sleep(1)
        for _ in range(2):
            socks = [self.conn('127.0.0.2', timeout=10) for _ in range(64)]
            for s in socks:
                s.sendall(b'GET /api/config HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n\r\n' % self.port)
            ok = 0
            for s in socks:
                if s.recv(12).startswith(b'HTTP/1.1 200'):
                    ok += 1
                s.close()
            self.assertEqual(ok, 64)
            time.sleep(1)

    def test_connections_capped_in_total(self):
        # 9 addresses x 60, each under the per-address cap: only the total of 512 applies
        socks = [self.conn('127.0.0.%d' % (10 + a)) for a in range(9) for _ in range(60)]
        closed = self.closed_count(socks)
        self.assertGreaterEqual(closed, 540 - 512)
        self.assertLessEqual(closed, 540 - 512 + 2)   # + the odd connection of an earlier test still closing
        time.sleep(1)
        self.assertEqual(Client(self.base).req('GET', '/api/config')[0], 200)

    def test_idle_connection_closed(self):
        """a connection that never sends a request line is closed after the idle timeout (60 s)"""
        c = self.conn(timeout=90)
        t0 = time.time()
        self.assertEqual(c.recv(1), b'')
        self.assertGreater(time.time() - t0, 55)
        self.assertLess(time.time() - t0, 75)
        c.close()

    def test_slow_header_lines_closed(self):
        """the header deadline is for all header lines together, not per line (one line every 5 s doesn't extend it)"""
        c = socket.create_connection(('127.0.0.1', self.port), timeout=60)
        c.sendall(b'GET /api/config HTTP/1.1\r\n')
        t0 = time.time()
        closed = False
        while time.time() - t0 < 45:
            try:
                c.sendall(b'X-Slow: a\r\n')
            except OSError:
                closed = True
                break
            c.settimeout(5)
            try:
                if c.recv(1) == b'':
                    closed = True
                    break
            except socket.timeout:
                pass
        self.assertTrue(closed)
        self.assertLess(time.time() - t0, 30)
        c.close()

if __name__ == '__main__':
    unittest.main()
