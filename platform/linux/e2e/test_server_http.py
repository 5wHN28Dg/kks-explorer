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
    extra = {}       # config entries a test class adds

    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-nim-server-')
        cls.port, cls.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': cls.sport, 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        cfg.update(cls.extra)
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
        cls.proc = subprocess.Popen([BIN, 'serve', '--config', os.path.join(cls.dir, 'config.json')], stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, text=True, cwd=cls.dir)
        cls.setup = None
        t0 = time.time()
        while time.time() - t0 < 10:
            line = cls.proc.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
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
        # a name that looks like an option is a name, not an importer option (issue #38)
        boss.req('POST', '/api/sheets/import?id=four&name=--replace', raw=pdf, headers={'Content-Type': 'application/pdf'})
        job = self.wait(boss)
        self.assertEqual((job['state'], job['result'] and job['result']['name']), ('done', '--replace'), job['log'])
        # managers only
        self.assertEqual(Client(self.base).req('GET', '/api/sheets')[0], 401)


FAKE_DIR = tempfile.mkdtemp(prefix='kks-fake-importer-')
import atexit, shutil
atexit.register(shutil.rmtree, FAKE_DIR, True)
FAKE_IMPORTER = os.path.join(FAKE_DIR, 'kks-import')
with open(FAKE_IMPORTER, 'w') as f:   # records its limits and arguments, then hangs like a PDF that never finishes
    f.write('#!/bin/sh\nulimit -v > "$0.limits"; ulimit -c >> "$0.limits"\n'
            'for a in "$@"; do printf "%s\\n" "$a"; done > "$0.args"\nexec sleep 60\n')
os.chmod(FAKE_IMPORTER, 0o755)


class ImportLimits(Base):
    """issue #34: the importer runs with an address-space limit, no core dumps, and is stopped at a deadline"""
    extra = {'importer': FAKE_IMPORTER, 'import_timeout_s': 2, 'import_memory_mb': 700}

    def test_limits_and_deadline(self):
        boss = self.manager()
        st, r, _ = boss.req('POST', '/api/sheets/import?id=one&name=-x%20y', raw=b'%PDF-1.4 x', headers={'Content-Type': 'application/pdf'})
        self.assertEqual(st, 200, r)
        t0 = time.time()
        while time.time() - t0 < 20:
            job = boss.req('GET', '/api/sheets/job')[1]['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        self.assertEqual(job['state'], 'failed', job)
        self.assertLess(time.time() - t0, 10)
        self.assertTrue(any('stopped after 2 s' in l for l in job['log']), job['log'])
        self.assertEqual(open(FAKE_IMPORTER + '.limits').read().split(), [str(700 * 1024), '0'])
        args = open(FAKE_IMPORTER + '.args').read().splitlines()
        self.assertEqual(args[-4:-1], ['--', os.path.join(self.dir, 'backups', 'uploads', 'one.pdf'), '-x y'])  # issue #38


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
        # /data/ (2026-10-06): published files and the program's own data/ are never pages of this site: the types the
        # pages use go out sandboxed, anything else as a download
        os.makedirs(os.path.join(d, 'courses'))
        open(os.path.join(d, 'courses', 'evil.html'), 'w').write('<script>parent.pwned=1</script>')
        open(os.path.join(d, 'courses', 'evil.svg'), 'w').write('<svg xmlns="http://www.w3.org/2000/svg"><script>1</script></svg>')
        import gzip
        open(os.path.join(d, 'courses', 'big.json.gz'), 'wb').write(gzip.compress(b'{"a": 1}'))
        open(os.path.join(d, 'courses', 'page.html.gz'), 'wb').write(gzip.compress(b'<script>parent.pwned=1</script>'))
        self.assertEqual(self.cli('publish-data', d), (0, 'Published plant data version 2.'))
        for name in ('courses/evil.html', 'courses/evil.svg'):
            st, data, hdr = boss.req('GET', '/data/' + name)
            self.assertEqual(st, 200, name)
            self.assertEqual(hdr['Content-Type'], 'application/octet-stream', name)
            self.assertEqual(hdr['Content-Disposition'], 'attachment', name)
            self.assertIn('sandbox', hdr['Content-Security-Policy'])
        with boss.op.open(urllib.request.Request(boss.base + '/data/courses/big.json')) as resp:   # the .gz copy
            st, hdr = resp.status, resp.headers
        self.assertEqual((st, hdr['Content-Type'], hdr['Content-Encoding']), (200, 'application/json', 'gzip'))
        self.assertIn('sandbox', hdr['Content-Security-Policy'])
        # a page compressed: asked by its own name it is gzip bytes, not a page; asked without .gz it downloads
        st, data, hdr = boss.req('GET', '/data/courses/page.html.gz')
        self.assertEqual((st, hdr['Content-Type'], hdr.get('Content-Encoding')), (200, 'application/gzip', None))
        self.assertIn('sandbox', hdr['Content-Security-Policy'])
        with boss.op.open(urllib.request.Request(boss.base + '/data/courses/page.html')) as resp:
            st, hdr = resp.status, resp.headers
        self.assertEqual((st, hdr['Content-Type'], hdr['Content-Encoding'], hdr['Content-Disposition']),
                         (200, 'application/octet-stream', 'gzip', 'attachment'))
        self.assertIn('sandbox', hdr['Content-Security-Policy'])
        st, data, hdr = boss.req('GET', '/data/sheets.json')
        self.assertEqual((st, hdr['Content-Type']), (200, 'application/json'))
        self.assertIn('sandbox', hdr['Content-Security-Policy'])
        st, data, hdr = boss.req('GET', '/data/kks.json')     # the program's own data/, not published
        self.assertEqual((st, hdr['Content-Type']), (200, 'application/json'))
        self.assertIn('sandbox', hdr['Content-Security-Policy'])
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


class SecretFiles(Base):
    cli = Cli.cli

    def test_secret_files(self):
        """the setup link is never printed by serve (#69); backups and root key exports are 0600 (#28, #29), the
        root key's passphrase generated (80 bits)"""
        link = os.path.join(self.dir, 'setup-link.txt')
        self.assertEqual(os.stat(link).st_mode & 0o777, 0o600)
        self.assertIn('#setup=' + self.setup, open(link).read())
        self.manager()
        self.assertFalse(os.path.exists(link))              # used: gone
        old = os.umask(0o022)
        try:
            bundle, root, pp = (os.path.join(self.dir, n) for n in ('b.kksbackup', 'r.kksroot', 'r.passphrase'))
            # decision 0051: no plain backup, ever: refused until a root key export made the backup key
            code0, out0 = self.cli('backup', '--out', bundle)
            self.assertNotEqual(code0, 0)
            self.assertIn('export-root-key', out0)
            self.assertFalse(os.path.exists(bundle))
            code, out = self.cli('export-root-key', '--out', root, '--passphrase-out', pp)
            self.assertEqual(code, 0, out)
            self.assertEqual(self.cli('backup', '--out', bundle)[0], 0)
            code2, out2 = self.cli('export-root-key', '--out', root + '2')
            opened = os.path.join(self.dir, 'opened.kksbundle')
            code3, out3 = self.cli('open-backup', '--in', bundle, '--out', opened, '--passphrase-file', pp)
            wrong = os.path.join(self.dir, 'wrong.passphrase')
            open(wrong, 'w').write('0000-0000-0000-0000\n')
            code4, out4 = self.cli('open-backup', '--in', bundle, '--out', opened + '2', '--passphrase-file', wrong)
        finally:
            os.umask(old)
        for f in (bundle, root, pp, root + '2', opened):
            self.assertEqual(os.stat(f).st_mode & 0o777, 0o600, f)
        raw = open(bundle, 'rb').read()
        self.assertNotEqual(raw[:2], b'\x1f\x8b')                   # not a gzip bundle: encrypted
        doc = json.loads(raw)
        self.assertEqual((doc['kks_server_backup'], doc['kdf'], doc['iter']), (2, 'pbkdf2-sha256', 600000))
        self.assertNotIn(b'The Manager', raw)
        self.assertEqual(code3, 0, out3)                          # the passphrase of the export before it opens it
        import gzip
        b = json.loads(gzip.decompress(open(opened, 'rb').read()))
        self.assertEqual(b['kks_bundle'], 2)
        self.assertTrue(any(e.get('type') == 'genesis' for e in b['entries']))
        self.assertNotEqual(code4, 0)
        self.assertFalse(os.path.exists(opened + '2'))
        for change in ({'created': doc['created'] + 1}, {'iter': 2 ** 31}):   # the header is authenticated; no hours of PBKDF2
            bad = os.path.join(self.dir, 'bad.kksbackup')
            open(bad, 'w').write(json.dumps(dict(doc, **change)))
            t0 = time.time()
            self.assertNotEqual(self.cli('open-backup', '--in', bad, '--out', opened + '3', '--passphrase-file', pp)[0], 0, change)
            self.assertLess(time.time() - t0, 30)
            self.assertFalse(os.path.exists(opened + '3'))
        phrase = open(pp).read().strip()
        self.assertRegex(phrase, r'^[0-9a-hjkmnp-tv-z]{4}(-[0-9a-hjkmnp-tv-z]{4}){3}$')
        self.assertNotIn(phrase, out)
        self.assertEqual(code2, 0, out2)
        self.assertRegex(out2, r'\n  [0-9a-z]{4}(-[0-9a-z]{4}){3}\n')   # printed when no file is given
        sys.path.insert(0, REPO)
        from ref import crypto2
        key = json.loads(crypto2.passphrase_open(phrase, json.loads(open(root).read())['sealed']))
        self.assertIn('scalar', key)
        r = subprocess.run([BIN, 'export-root-key', '--out', root, '--config', os.path.join(self.dir, 'config.json')],
                           capture_output=True, text=True, env=dict(os.environ, KKS_ROOT_PASSPHRASE='weak but 12+'))
        self.assertNotEqual(r.returncode, 0)                 # a chosen passphrase is refused


class Server(Base):
    def test_page_policy(self):
        """#8: the pages, their scripts and workers come with a Content-Security-Policy: scripts from this site only
        (no inline script or handler), no plugins, no <base>, not framed"""
        c = Client(self.base)
        for path in ('/', '/index.html', '/admin.html', '/learning.html', '/course.html', '/index.js', '/admin.js',
                     '/learning.js', '/common.js', '/tiles.js', '/systems.js', '/sw.js', '/kks-wasm-worker.js', '/vendor/kks/kks-dec.js'):
            st, _, hdr = c.req('GET', path)
            self.assertEqual(st, 200, path)
            csp = {d.split()[0]: d.split()[1:] for d in (x.strip() for x in hdr['Content-Security-Policy'].split(';')) if d}
            self.assertEqual(csp['script-src'], ["'self'", "'wasm-unsafe-eval'"], path)
            self.assertEqual(csp['object-src'], ["'none'"], path)
            self.assertEqual(csp['base-uri'], ["'none'"], path)
            self.assertEqual(csp['frame-ancestors'], ["'none'"], path)
            self.assertEqual(csp['default-src'], ["'self'"], path)

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
        # #32: only admins can make the server connect somewhere
        self.assertEqual(ali2.req('POST', '/api/sync/now', {'address': '127.0.0.1:9'})[0], 403)
        self.assertEqual(boss.req('POST', '/api/sync/now', {'address': '127.0.0.1:notaport'})[0], 400)
        self.assertEqual(boss.req('POST', '/api/sync/now', {'address': '127.0.0.1:9'})[0], 502)   # nothing listens there
        # 2026-10-06 stored XSS: a member's "photo" that starts with the JPEG XL signature and goes on as HTML, asked
        # for as <sha>.html. Its type comes from its bytes, never the URL, and it is sandboxed.
        poly = b'\xff\x0a<html><script>parent.pwned=1</script></html>'
        st, r, _ = ali2.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': 'x',
                            'dataUrl': 'data:image/jxl;base64,' + base64.b64encode(poly).decode()}})
        self.assertEqual(st, 200, r)
        sha = [p for p in ali2.req('GET', '/api/submissions')[1]['submissions'] if p['kind'] == 'photo'][0]['payload']['file'].split('.')[0]
        for ext in ('html', 'svg', 'htm', 'xml', 'js', 'jxl'):
            st, data, hdr = boss.req('GET', f'/photos/{sha}.{ext}')
            self.assertEqual((st, data), (200, poly))
            self.assertEqual(hdr['Content-Type'], 'image/jxl', ext)
            self.assertEqual(hdr['X-Content-Type-Options'], 'nosniff')
            self.assertIn('sandbox', hdr['Content-Security-Policy'])
            self.assertIn("default-src 'none'", hdr['Content-Security-Policy'])
        # History, the program's data, a bundle
        revs = boss.req('GET', '/api/revisions')[1]['revisions']
        self.assertGreaterEqual(len(revs), 2)
        self.assertEqual(ali2.req('GET', '/api/revisions')[0], 403)
        st, kks, _ = boss.req('GET', '/data/kks.json')
        self.assertEqual(st, 200)
        st, b, hdr = boss.req('GET', '/api/bundle?photos=1')
        self.assertEqual(st, 200); self.assertTrue(b.startswith(b'\x1f\x8b'))
        # #33: the HTTP enroll route is gone (devices enroll over TLS on the sync port, §16; it took a password over
        # HTTP and certified any device ID without proof of its key)
        st, r, _ = anon.req('POST', '/api/devices/enroll', {'username': 'ali', 'password': 'ali password 1',
                                                            'device': 'A' * 32, 'label': 'phone'})
        self.assertIn(st, (401, 404), r)
        self.assertNotIn('A' * 32, json.dumps(boss.req('GET', '/api/devices')[1]))
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
        except ConnectionResetError:     # closed with our bytes unread: the answer may be lost to the reset
            out += b'<reset>'
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

    def rss_mb(self):
        for line in open('/proc/%d/status' % self.proc.pid):
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) / 1024

    def test_bad_request_lines_close(self):
        """a stream of bad request lines gets one answer and the connection closes (answers were queued unread)"""
        r = self.raw(b'X\r\n' * 5000, wait=5)
        self.assertTrue(r.startswith(b'HTTP/1.1 400') or r == b'<reset>', r[:80])
        self.assertLessEqual(r.count(b'HTTP/1.1 '), 1)
        self.assertNotIn(b'<timeout>', r)              # closed, not kept open

    def test_bad_framing_refused(self):
        h = 'Host: 127.0.0.1:%d\r\n' % self.port
        for req in ('POST /api/login HTTP/1.1\r\n%sContent-Length: 5abc\r\n\r\n12345' % h,
                    'POST /api/login HTTP/1.1\r\n%sContent-Length: 5\r\nContent-Length: 7\r\n\r\n12345' % h,
                    'POST /api/login HTTP/1.1\r\n%sTransfer-Encoding : chunked\r\nContent-Length: 5\r\n\r\n12345' % h,
                    'POST /api/login HTTP/1.1\r\n%sContent-Length: 5, 7\r\n\r\n12345' % h,
                    'POST /api/login HTTP/1.1\r\n%sContent-Length: 5,\r\n\r\n12345' % h,
                    'POST /api/login HTTP/1.1\r\n%sNo colon here\r\nContent-Length: 5\r\n\r\n12345' % h,
                    'POST /api/login HTTP/1.1\r\n%sExpect: something\r\nContent-Length: 5\r\n\r\n12345' % h,
                    'GET /api/config\r\n%s\r\n' % h):
            with self.subTest(req=req[:60]):
                r = self.raw(req.encode() + b'GET /api/config HTTP/1.1\r\n' + h.encode() + b'\r\n')
                self.assertTrue(r.startswith(b'HTTP/1.1 400') or r.startswith(b'HTTP/1.1 417') or r == b'<reset>', r[:80])
                self.assertLessEqual(r.count(b'HTTP/1.1 '), 1, r)   # what followed was not read as a request
                self.assertNotIn(b'<timeout>', r)

    def test_header_size_capped(self):
        r = self.raw(b'GET /api/config HTTP/1.1\r\n' + b''.join(b'X-%d: %s\r\n' % (i, b'a' * 1000) for i in range(80)) + b'\r\n')
        self.assertTrue(r.startswith(b'HTTP/1.1 431') or r == b'<reset>', r[:80])
        r = self.raw(b'GET /api/config HTTP/1.1\r\n' + b''.join(b'X-%d: a\r\n' % i for i in range(150)) + b'\r\n')
        self.assertTrue(r.startswith(b'HTTP/1.1 431') or r == b'<reset>', r[:80])

    def test_body_memory_follows_what_arrives(self):
        """a large Content-Length with one byte sent doesn't make the server allocate the whole body"""
        before = self.rss_mb()
        socks = [self.conn('127.0.0.4') for _ in range(10)]
        for c in socks:
            c.sendall(b'POST /api/login HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\n'
                      b'Content-Length: 25000000\r\n\r\n{')
        time.sleep(1.5)
        grown = self.rss_mb() - before
        for c in socks: c.close()
        self.assertLess(grown, 50, 'RSS grew by %.0f MB' % grown)   # was ~25 MB per connection

    def test_pipelined_requests_memory(self):
        """many short pipelined requests on a few connections: memory stays flat (a timer per read once grew it by a
        gigabyte in seconds)"""
        before = self.rss_mb()
        req = (b'GET /api/config HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n' % self.port +
               b''.join(b'X-%d: a\r\n' % i for i in range(90)) + b'\r\n')
        import threading
        socks = [self.conn('127.0.0.6') for _ in range(4)]
        stop = time.time() + 6
        def send(c):
            try:
                while time.time() < stop: c.sendall(req * 20)
            except OSError: pass
        def drain(c):
            c.settimeout(1)
            try:
                while time.time() < stop + 1 and c.recv(1 << 16): pass
            except OSError: pass
        ts = [threading.Thread(target=f, args=(c,)) for c in socks for f in (send, drain)]
        for t in ts: t.start()
        for t in ts: t.join()
        grown = self.rss_mb() - before
        for c in socks: c.close()
        self.assertLess(grown, 100, 'RSS grew by %.0f MB' % grown)

    def test_declared_sizes_dont_block_uploads(self):
        """headers that announce large bodies and send nothing don't use up the upload budget (it counts bytes held)"""
        budget = 256 * 1024 * 1024                         # MaxBodiesInFlight
        sizes = [31_000_000] * 8 + [budget - 8 * 31_000_000 - 10]   # announced up to 10 bytes short of it
        socks = [self.conn('127.0.0.7') for _ in sizes]
        for c, n in zip(socks, sizes):
            c.sendall(b'POST /api/login HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\n'
                      b'Content-Length: %d\r\n\r\n' % (self.port, n))
        time.sleep(1)
        st = Client(self.base).req('POST', '/api/login', {'username': 'nobody', 'password': 'x'})[0]
        for c in socks: c.close()
        self.assertIn(st, (401, 429))                     # an answer from the handler, not 503

    def test_refusal_closes(self):
        """a POST without Content-Length is refused and the connection closed, so a pipeline of them can't hold it"""
        r = self.raw(b'POST /x HTTP/1.1\r\nHost: 127.0.0.1:%d\r\n\r\n' % self.port * 50)
        self.assertTrue(r.startswith(b'HTTP/1.1 411') or r == b'<reset>', r[:80])
        self.assertLessEqual(r.count(b'HTTP/1.1 '), 1)
        self.assertNotIn(b'<timeout>', r)

    def test_bodies_not_held_by_idle_connections(self):
        """large bodies on connections left open and idle: memory levels off instead of growing per connection"""
        body = b'{' + b' ' * 30_000_000
        socks, rss = [], []
        for _ in range(10):
            c = self.conn('127.0.0.8', timeout=30)
            c.sendall(b'POST /api/login HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\n'
                      b'Content-Length: %d\r\n\r\n' % (self.port, len(body)) + body)
            self.assertTrue(c.recv(12).startswith(b'HTTP/1.1 4'))   # answered; the connection stays open, idle
            socks.append(c)
            rss.append(self.rss_mb())
        for c in socks: c.close()
        self.assertLess(rss[-1] - rss[3], 60, rss)       # 30 MB per idle connection would be 180 MB here

    def test_upload_budget_bounds_memory(self):
        """bodies sent for real fill the server-wide upload budget (256 MB, charged at twice each buffer): past it uploads
        get 503, memory stays bounded over several rounds (625 MB before the buffer was charged by its real size), and
        once those connections end, uploads work again"""
        import threading
        before = self.rss_mb()
        n = 30_000_000
        head = (b'POST /api/login HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nContent-Type: application/json\r\n'
                b'Content-Length: %d\r\n\r\n{' % (self.port, n))
        peak, refused = 0, 0
        for _ in range(3):
            answers = []
            def send(c):
                try:
                    c.sendall(head + b' ' * (n - 2))      # all but the last byte: the body stays held
                    c.settimeout(2)
                    answers.append(c.recv(12))
                except OSError:
                    answers.append(b'<closed>')
            socks = [self.conn('127.0.0.9') for _ in range(20)]
            ts = [threading.Thread(target=send, args=(c,)) for c in socks]
            for t in ts: t.start()
            for t in ts: t.join(60)
            peak = max(peak, self.rss_mb() - before)
            refused += sum(1 for a in answers if a.startswith(b'HTTP/1.1 503') or a == b'<closed>')
            for c in socks: c.close()
            time.sleep(1)
        self.assertGreaterEqual(refused, 30)
        self.assertLess(peak, 450, 'RSS grew by %.0f MB' % peak)
        self.assertIn(Client(self.base).req('POST', '/api/login', {'username': 'nobody', 'password': 'x'})[0], (401, 429))

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

class Address(unittest.TestCase):
    """finding #26 (advisory GHSA-m2gr-gcrf-xc6m): the web pages and sign-in are plain HTTP, so they listen on this
    machine only; a network address in the config is refused before anything starts"""

    def config(self, address):
        d = tempfile.mkdtemp(prefix='kks-addr-')
        cfg = {'port': free_port(), 'sync_port': free_port(), 'store': os.path.join(d, 'server.db'),
               'storage_key_file': os.path.join(d, 'storage.key'), 'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data')}
        if address is not None:
            cfg['address'] = address
        json.dump(cfg, open(os.path.join(d, 'config.json'), 'w'))
        return d, cfg

    def test_network_address_refused(self):
        for a in ('0.0.0.0', '192.168.1.10', '::', '::1', '127.999.999.999', ''):
            with self.subTest(address=a):
                d, _ = self.config(a)
                p = subprocess.run([BIN, 'serve', '--config', os.path.join(d, 'config.json')], capture_output=True,
                                   text=True, cwd=d, timeout=5)
                self.assertNotEqual(p.returncode, 0)
                self.assertIn('plain HTTP', p.stdout + p.stderr)

    def test_public_url_must_be_https(self):
        for u in ('http://walk.example', 'walk.example', 'ftp://walk.example'):
            with self.subTest(public_url=u):
                d, cfg = self.config('127.0.0.1')
                cfg['public_url'] = u
                json.dump(cfg, open(os.path.join(d, 'config.json'), 'w'))
                p = subprocess.run([BIN, 'serve', '--config', os.path.join(d, 'config.json')], capture_output=True,
                                   text=True, cwd=d, timeout=5)
                self.assertNotEqual(p.returncode, 0)
                self.assertIn('https://', p.stdout + p.stderr)

    def test_public_url_default_port(self):
        d, cfg = self.config('127.0.0.1')
        cfg['public_url'] = 'https://Walk.Example:443/'
        json.dump(cfg, open(os.path.join(d, 'config.json'), 'w'))
        p = subprocess.Popen([BIN, 'serve', '--config', os.path.join(d, 'config.json')], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, cwd=d)
        try:
            for _ in range(20):
                if 'server on' in p.stdout.readline(): break
            time.sleep(0.3)
            c = Client('http://127.0.0.1:%d' % cfg['port'])
            self.assertEqual(c.req('GET', '/api/config', headers={'Host': 'walk.example'})[0], 200)
        finally:
            p.terminate(); p.wait(5)

    def test_default_is_loopback(self):
        self.serves(None, 'http://127.0.0.1:')

    def test_loopback_forms_serve(self):
        for a, shown in (('127.0.0.1', 'http://127.0.0.1:'), (' LocalHost ', 'http://localhost:')):
            with self.subTest(address=a):
                self.serves(a, shown)

    def serves(self, address, shown):
        d, cfg = self.config(address)
        p = subprocess.Popen([BIN, 'serve', '--config', os.path.join(d, 'config.json')], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True, cwd=d)
        try:
            line = ''
            for _ in range(20):
                line = p.stdout.readline()
                if 'server on' in line:
                    break
            self.assertIn(shown, line)
            for i in range(50):        # the line is printed just before the listener opens
                try:
                    socket.create_connection(('127.0.0.1', cfg['port']), timeout=5).close()
                    break
                except ConnectionRefusedError:
                    time.sleep(0.1)
            else:
                self.fail('nothing listens on 127.0.0.1')
        finally:
            p.terminate(); p.wait(5)

class Front(Base):
    """the web pages behind an HTTPS proxy (finding #26's adversarial pass): Secure cookies under an https public URL,
    only this server's host names, X-Forwarded-For only from a proxy the operator vouches for"""

    def test_defaults_without_proxy(self):
        boss = Client(self.base)
        st, r, hdr = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                     'full_name': 'The Manager'})
        self.assertEqual(st, 200, r)
        self.assertNotIn('Secure', hdr['Set-Cookie'])     # plain http://127.0.0.1 on this machine
        # X-Forwarded-For is anyone's to send: a new value per attempt does not escape the per-address limit
        codes = [Client(self.base).req('POST', '/api/login', {'username': 'nobody%d' % i, 'password': 'x'},
                                       headers={'X-Forwarded-For': '10.0.0.%d' % i})[0] for i in range(7)]
        self.assertIn(429, codes)

    def test_host_names(self):
        c = Client(self.base)
        self.assertEqual(c.req('GET', '/api/config', headers={'Host': 'localhost:%d' % self.port})[0], 200)
        for h in ('evil.example', 'evil.example:%d' % self.port, '127.0.0.1', 'walk.example',
                  '127.0.0.1:%d, evil.example' % self.port):
            with self.subTest(host=h):
                self.assertEqual(c.req('GET', '/api/config', headers={'Host': h})[0], 421)
                self.assertEqual(c.req('GET', '/', headers={'Host': h})[0], 421)
        # two Host lines
        s = socket.create_connection(('127.0.0.1', self.port), timeout=5)
        s.sendall(b'GET /api/config HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nHost: evil.example\r\nConnection: close\r\n\r\n' % self.port)
        self.assertIn(s.recv(12)[:12], (b'HTTP/1.1 421', b'HTTP/1.1 400'))   # refused by the app or already by the HTTP layer
        s.close()
        # X-Forwarded-Host doesn't widen the Origin check
        st = c.req('POST', '/api/login', {'username': 'x', 'password': 'y'},
                   headers={'Origin': 'http://evil.example', 'X-Forwarded-Host': 'evil.example'})[0]
        self.assertEqual(st, 403)


class FrontProxy(Base):
    extra = {'public_url': 'HTTPS://Walk.example', 'trusted_proxy': True}   # the scheme's case doesn't matter

    def test_behind_proxy(self):
        boss = Client(self.base)
        st, r, hdr = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                     'full_name': 'The Manager'})
        self.assertEqual(st, 200, r)
        self.assertIn('; Secure', hdr['Set-Cookie'])
        self.assertEqual(boss.req('GET', '/api/config', headers={'Host': 'walk.example'})[0], 200)
        self.assertEqual(boss.req('GET', '/api/config', headers={'Host': 'evil.example'})[0], 421)
        # a browser's sign-in through a proxy, with Host passed on or rewritten to this server's own: not refused as
        # cross-origin (the public URL's host is compared in lower case)
        for h in ('walk.example', '127.0.0.1:%d' % self.port):
            with self.subTest(host=h):
                st = Client(self.base).req('POST', '/api/login', {'username': 'boss', 'password': 'wrong'},
                                           headers={'Host': h, 'Origin': 'https://walk.example'})[0]
                self.assertEqual(st, 401)
        # the proxy appends the browser's address: the last entry counts, whatever the browser put before it
        fails = lambda ip, n: [Client(self.base).req('POST', '/api/login', {'username': 'x%s%d' % (ip, i), 'password': 'x'},
                                                     headers={'X-Forwarded-For': 'spoof%d, %s' % (i, ip)})[0] for i in range(n)]
        self.assertIn(429, fails('10.0.0.1', 7))
        self.assertEqual(fails('10.0.0.2', 1), [401])   # another browser is not locked out


if __name__ == '__main__':
    unittest.main()
