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
        # the manager is a new member too: a position is required
        st, r, _ = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager'})
        self.assertEqual(st, 400, r)
        self.assertIn('position', r['error'])
        st, r, _ = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'})
        self.assertEqual(st, 200, r)
        return boss


def many_circles_pdf(n):
    """a page of n empty circles 21 pt across (Bezier, like the drawings' off-page connectors)"""
    ops = ['0.35 w']
    for i in range(n):
        cx, cy, r = 20 + (i % 60) * 30, 20 + (i // 60) * 30, 10.5
        c = 0.5523 * r
        ops.append(f'{cx + r} {cy} m {cx + r} {cy + c} {cx + c} {cy + r} {cx} {cy + r} c '
                   f'{cx - c} {cy + r} {cx - r} {cy + c} {cx - r} {cy} c {cx - r} {cy - c} {cx - c} {cy - r} {cx} {cy - r} c '
                   f'{cx + c} {cy - r} {cx + r} {cy - c} {cx + r} {cy} c S')
    content = '\n'.join(ops).encode() + b'\n'
    objs = [b'<< /Type /Catalog /Pages 2 0 R >>', b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
            b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 1840 560] /Contents 4 0 R >>',
            b'<< /Length %d >>\nstream\n' % len(content) + content + b'endstream']
    out = b'%PDF-1.4\n'
    offs = []
    for i, o in enumerate(objs):
        offs.append(len(out))
        out += b'%d 0 obj\n' % (i + 1) + o + b'\nendobj\n'
    xref = len(out)
    out += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objs) + 1) + b''.join(b'%010d 00000 n \n' % o for o in offs)
    out += b'trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n' % (len(objs) + 1, xref)
    return out


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
        # a crafted page past the connector finder's limit (MaxCircles, 1000) is refused; nothing changes (2026-10-09)
        sheets_dir = os.path.join(self.dir, 'plant-data', 'sheets')
        files = {n: open(os.path.join(sheets_dir, n), 'rb').read() for n in os.listdir(sheets_dir)}
        boss.req('POST', '/api/sheets/import?id=circles&name=Circles', raw=many_circles_pdf(1001),
                 headers={'Content-Type': 'application/pdf'})
        job = self.wait(boss)
        self.assertEqual(job['state'], 'failed', job['log'])
        self.assertTrue(any('MaxCircles' in l and '1001' in l for l in job['log']), job['log'])
        self.assertEqual(open(os.path.join(self.dir, 'plant-data', 'sheets.json')).read(), before)
        self.assertEqual({n: open(os.path.join(sheets_dir, n), 'rb').read() for n in os.listdir(sheets_dir)}, files)
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


OOM_IMPORTER = os.path.join(FAKE_DIR, 'kks-import-oom')
with open(OOM_IMPORTER, 'w') as f:   # records its limit, then runs out of memory as kks-import reports it (exit code 3)
    f.write('#!/bin/sh\nulimit -v > "$0.limits"\necho "The importer ran out of memory: the import stopped." >&2\nexit 3\n')
os.chmod(OOM_IMPORTER, 0o755)
CRASH_IMPORTER = os.path.join(FAKE_DIR, 'kks-import-crash')
with open(CRASH_IMPORTER, 'w') as f:   # dies of a signal, as a C library can when an allocation fails
    f.write('#!/bin/sh\nkill -SEGV $$\n')
os.chmod(CRASH_IMPORTER, 0o755)


class ImportFailure(Base):
    def run_import(self, boss):
        before = open(os.path.join(self.dir, 'plant-data', 'sheets.json')).read() \
            if os.path.exists(os.path.join(self.dir, 'plant-data', 'sheets.json')) else None
        st, r, _ = boss.req('POST', '/api/sheets/import?id=one&name=One', raw=b'%PDF-1.4 x', headers={'Content-Type': 'application/pdf'})
        self.assertEqual(st, 200, r)
        for _ in range(100):
            job = boss.req('GET', '/api/sheets/job')[1]['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        self.assertEqual(job['state'], 'failed', job)
        after = open(os.path.join(self.dir, 'plant-data', 'sheets.json')).read() \
            if os.path.exists(os.path.join(self.dir, 'plant-data', 'sheets.json')) else None
        self.assertEqual(after, before)
        return job['log']


class ImportOutOfMemory(ImportFailure):
    """2026-10-09: the default limit is 2560 MB (below the service's 3G cap), and an import that runs out of memory
    says which setting to raise"""
    extra = {'importer': OOM_IMPORTER}

    def test_out_of_memory_names_the_limit(self):
        log = self.run_import(self.manager())
        self.assertEqual(open(OOM_IMPORTER + '.limits').read().split(), [str(2560 * 1024)])
        hint = [l for l in log if 'import_memory_mb' in l]
        self.assertEqual(len(hint), 1, log)
        self.assertIn('2560 MB', hint[0])
        self.assertIn('raise import_memory_mb', hint[0])
        self.assertIn('MemoryMax', hint[0])


@unittest.skipUnless(os.path.exists(IMPORTER), 'the importer (kks_import) is not built')
class ImportRealOutOfMemory(ImportFailure):
    """the real importer at the smallest limit: whichever allocation fails first (Nim, MuPDF, or a libjxl thread or
    buffer, which aborts), the log names the limit and the setting to raise"""
    extra = {'import_memory_mb': 256}

    def test_real_importer_out_of_memory(self):
        boss = self.manager()
        pdf = open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb').read()
        st, r, _ = boss.req('POST', '/api/sheets/import?id=one&name=One', raw=pdf, headers={'Content-Type': 'application/pdf'})
        self.assertEqual(st, 200, r)
        for _ in range(600):
            job = boss.req('GET', '/api/sheets/job')[1]['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        self.assertEqual(job['state'], 'failed', job['log'])
        hint = [l for l in job['log'] if 'raise import_memory_mb' in l]
        self.assertEqual(len(hint), 1, job['log'])
        self.assertIn('256 MB', hint[0])
        self.assertFalse(os.path.exists(os.path.join(self.dir, 'plant-data', 'sheets', 'one.kkp')))


class ImportCrash(ImportFailure):
    extra = {'importer': CRASH_IMPORTER, 'import_memory_mb': 1000}

    def test_crash_mentions_the_limit(self):
        log = self.run_import(self.manager())
        hint = [l for l in log if 'import_memory_mb' in l]
        self.assertEqual(len(hint), 1, log)
        self.assertIn('signal 11', hint[0])
        self.assertIn('1000 MB', hint[0])
        self.assertIn('raise import_memory_mb', hint[0])


class Cli(Base):
    def cli(self, *args, stdin=None):
        r = subprocess.run([BIN, *args, '--config', os.path.join(self.dir, 'config.json')], capture_output=True, text=True,
                           cwd=self.dir, timeout=60, input=stdin)
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
        st, r, _ = boss.req('POST', '/api/users', {'username': 'sara', 'full_name': 'Sara Admin', 'position': 'Shift engineer', 'role': 'admin'})
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
                                                   'full_name': 'The Manager', 'position': 'Plant manager'})
        self.assertEqual(st, 200, r)
        self.assertEqual(boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'other', 'password': 'a long password',
                                                         'full_name': 'Nope', 'position': 'Nobody'})[0], 403)
        st, me, _ = boss.req('GET', '/api/me')
        self.assertEqual((me['user']['username'], me['user']['role']), ('boss', 'manager'))
        # cross-origin and non-JSON posts are refused
        self.assertEqual(boss.req('POST', '/api/submit', {}, headers={'Origin': 'http://evil.example'})[0], 403)
        self.assertEqual(boss.req('POST', '/api/submit', raw=b'kind=x', headers={'Content-Type': 'application/x-www-form-urlencoded'})[0], 415)
        # an account for a user, password set by the one-time link
        # a new account needs a position (the user's rule for new members)
        st, r, _ = boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali User', 'role': 'user'})
        self.assertEqual(st, 400, r)
        self.assertIn('position', r['error'])
        st, r, _ = boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali User', 'position': 'Technician',
                                                   'role': 'user'})
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
        # a photo: kept as a blob, served by hash; a floor may come with it (the clients ask for one first)
        png = b'\xff\x0a' + b'0' * 64     # a JPEG XL codestream's signature: the server stores JXL only
        photo = {'kks': '11LAB70AA501', 'caption': 'gland', 'dataUrl': 'data:image/jxl;base64,' + base64.b64encode(png).decode()}
        st, r, _ = boss.req('POST', '/api/submit', {'kind': 'photo', 'payload': dict(photo, floor='2')})
        self.assertEqual(r.get('floor', {}).get('status'), 'approved', r)
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



class Signup(Base):
    """Sign-up with the plant's code, then an admin's approval (the user, 2026-10-10). The proxy's X-Forwarded-For
    gives each step its own address, as browsers have (the throttle counts per address)."""
    extra = {'trusted_proxy': True}
    CODE = 'team-7391-plant'
    REFUSED = 'The request was not accepted. Check the sign-up code with your manager, or try again later.'
    WAITING = "Your account request is waiting for an admin's approval."

    def cli(self, *args, stdin=None):
        r = subprocess.run([BIN, *args, '--config', os.path.join(self.dir, 'config.json')], capture_output=True, text=True,
                           cwd=self.dir, timeout=60, input=stdin)
        return r.returncode, (r.stdout + r.stderr).strip()

    def ask(self, ip, **over):
        body = {'code': self.CODE, 'username': 'ali', 'full_name': 'Ali Hassan', 'position': 'Operator', 'password': 'ali password 1'}
        body.update(over)
        body = {k: v for k, v in body.items() if v is not None}
        t0 = time.time()
        st, r, _ = Client(self.base).req('POST', '/api/signup', body, headers={'X-Forwarded-For': ip})
        self.seen.append(json.dumps(r) if not isinstance(r, bytes) else r.decode('utf-8', 'replace'))
        return st, r, time.time() - t0

    def login(self, username, password, ip='10.9.9.9'):
        c = Client(self.base)
        st, r, _ = c.req('POST', '/api/login', {'username': username, 'password': password}, headers={'X-Forwarded-For': ip})
        self.seen.append(json.dumps(r))
        return st, r, c

    def test_signup(self):
        self.seen = []                       # every response body: the code must be in none
        say = lambda c, m, path, body=None: self.seen.append(json.dumps(c.req(m, path, body)[1], default=repr)) or json.loads(self.seen[-1])
        boss = self.manager()
        anon = Client(self.base)
        # off until the manager sets a code: /api/config says only that
        self.assertIs(anon.req('GET', '/api/config')[1]['signup'], False)
        st, r, t_off = self.ask('10.0.0.1')
        self.assertEqual((st, r), (403, {'error': self.REFUSED}))
        # who may set it: the manager only, signed in; 6 to 64 characters
        self.assertEqual(anon.req('POST', '/api/signup-code', {'code': self.CODE})[0], 401)
        st, r, _ = boss.req('POST', '/api/users', {'username': 'sara', 'full_name': 'Sara Admin', 'position': 'Shift engineer', 'role': 'admin'})
        sara = Client(self.base)
        self.assertEqual(sara.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'sara password 1'})[0], 200)
        st, r, _ = boss.req('POST', '/api/users', {'username': 'omar', 'full_name': 'Omar User', 'position': 'Technician'})
        omar = Client(self.base)
        self.assertEqual(omar.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'omar password 1'})[0], 200)
        self.assertEqual(sara.req('POST', '/api/signup-code', {'code': self.CODE})[0], 403)
        self.assertEqual(omar.req('POST', '/api/signup-code', {'code': self.CODE})[0], 403)
        self.assertEqual(boss.req('POST', '/api/signup-code', {'code': 'short'})[0], 400)
        self.assertEqual(boss.req('POST', '/api/signup-code', {'code': 'x' * 65})[0], 400)
        self.assertIs(anon.req('GET', '/api/config')[1]['signup'], False)
        r = say(boss, 'POST', '/api/signup-code', {'code': self.CODE})
        self.assertEqual(r, {'ok': True, 'enabled': True})
        self.assertIs(say(anon, 'GET', '/api/config')['signup'], True)

        # the form's own rules, answered as they are (nothing secret decides them), whatever the code
        for code in (self.CODE, 'not the code'):
            for over, word in (({'username': 'a'}, 'Username'), ({'username': 'has space'}, 'Username'), ({'username': None}, 'Username'),
                               ({'password': 'short'}, 'Password'), ({'password': None}, 'Password'), ({'password': 12345678901}, 'Password'),
                               ({'full_name': ''}, 'name'), ({'full_name': None}, 'name'), ({'position': ''}, 'position'),
                               ({'position': None}, 'position')):
                st, r, _ = self.ask('10.0.1.1', code=code, **over)
                self.assertEqual(st, 400, (over, r))
                self.assertIn(word.lower(), r['error'].lower(), over)
        # too large, not JSON, not an object, from another site
        st, r, _ = self.ask('10.0.1.2', full_name='x' * 5000)
        self.assertEqual(st, 413, r)
        c = Client(self.base)
        self.assertEqual(c.req('POST', '/api/signup', raw=b'code=' + self.CODE.encode(), headers={'Content-Type': 'application/x-www-form-urlencoded'})[0], 415)
        self.assertEqual(c.req('POST', '/api/signup', raw=b'[1]', headers={'Content-Type': 'application/json'})[0], 400)
        self.assertEqual(c.req('POST', '/api/signup', {'code': self.CODE}, headers={'Origin': 'https://evil.example'})[0], 403)
        self.assertEqual(c.req('GET', '/api/signup')[0], 401)        # nothing to read there
        self.assertEqual(c.req('GET', '/api/signups')[0], 401)

        # a wrong code, no code, a code of another type, the code with other case: one answer
        slow = []
        for i, code in enumerate(('wrong-code-1', '', None, 12345678, self.CODE.upper(), self.CODE + 'x', self.CODE[:-1])):
            st, r, dt = self.ask('10.0.2.%d' % i, code=code)
            self.assertEqual((st, r), (403, {'error': self.REFUSED}), code)
            slow.append(dt)
        # no username oracle: a name somebody has (an account, an admin, the manager) is filed like any other, and
        # refused like any other with a wrong code
        filed = []
        for i, name in enumerate(('boss', 'sara', 'ali', 'ali', 'nadia')):
            st, r, dt = self.ask('10.0.3.%d' % i, username=name, full_name='  Ali   Hassan ', password='%s password 1' % name)
            self.assertEqual((st, r), (200, {'ok': True}), name)
            filed.append(dt)
            st, r, dt = self.ask('10.0.4.%d' % i, username=name, code='wrong-code-2')
            self.assertEqual((st, r), (403, {'error': self.REFUSED}), name)
            slow.append(dt)
        # a refusal is no faster than a request that is filed (the password is hashed before the code is looked at)
        self.assertGreater(min(slow + [t_off]), 0.4 * min(filed), (slow, t_off, filed))

        # no account before approval: not in Users, no session; signing in says it waits, to the right password only
        users = lambda: {u['username'] for u in boss.req('GET', '/api/users?show_hidden=1')[1]['users']}
        self.assertEqual(users(), {'boss', 'sara', 'omar'})
        st, r, c = self.login('nadia', 'nadia password 1')
        self.assertEqual((st, r), (403, {'error': self.WAITING}))
        self.assertEqual(c.req('GET', '/api/me')[0], 401)
        self.assertEqual(c.req('GET', '/api/state')[0], 401)
        wrong = self.login('nadia', 'not her password')[:2]
        self.assertEqual(wrong, (401, {'error': 'Wrong username or password.'}))
        self.assertEqual(self.login('nobody', 'not her password')[:2], wrong)          # as for a name nobody asked for
        # a request under a name that has an account answers as one under a name nobody has: it waits, to its own
        # password; so asking for a name and then signing in tells nothing about who has an account
        self.assertEqual(self.login('boss', 'boss password 1')[:2], (403, {'error': self.WAITING}))
        self.assertEqual(self.login('boss', 'not the password', ip='10.9.9.7')[:2], wrong)
        self.assertEqual(self.login('boss', 'a long password')[0], 200)

        # the list: admins and the manager; never a password's hash, never the code
        self.assertEqual(omar.req('GET', '/api/signups')[0], 403)
        for who in (boss, sara):
            L = say(who, 'GET', '/api/signups')
            self.assertEqual((L['enabled'], L['max'], L['days']), (True, 50, 14))
            self.assertEqual([(q['username'], q['full_name'], q['position'], q['taken']) for q in L['requests']],
                             [('boss', 'Ali Hassan', 'Operator', True), ('sara', 'Ali Hassan', 'Operator', True),
                              ('ali', 'Ali Hassan', 'Operator', False), ('ali', 'Ali Hassan', 'Operator', False),
                              ('nadia', 'Ali Hassan', 'Operator', False)])
            for q in L['requests']:
                self.assertEqual(sorted(q), ['created', 'expires', 'full_name', 'id', 'position', 'same', 'taken', 'username'])
                self.assertEqual(q['expires'] - q['created'], 14 * 86400)
                self.assertEqual(q['same'], 2 if q['username'] == 'ali' else 1)      # two asked for "ali": the list says so
                self.assertLess(abs(q['created'] - time.time()), 120)
        ids = [q['id'] for q in L['requests']]

        # approve and reject: admins only
        self.assertEqual(omar.req('POST', f'/api/signups/{ids[4]}/approve', {})[0], 403)
        self.assertEqual(omar.req('POST', f'/api/signups/{ids[4]}/reject', {})[0], 403)
        self.assertEqual(anon.req('POST', f'/api/signups/{ids[4]}/approve', {})[0], 401)
        self.assertEqual(boss.req('POST', '/api/signups/nosuchid/approve', {})[0], 404)
        # (another site's page can't decide a request or set the code with the admin's session)
        for path, body in ((f'/api/signups/{ids[4]}/approve', {}), (f'/api/signups/{ids[4]}/reject', {}), ('/api/signup-code', {'code': 'evil-code-1'})):
            self.assertEqual(boss.req('POST', path, body, headers={'Origin': 'https://evil.example'})[0], 403, path)
        self.assertEqual(len(boss.req('GET', '/api/signups')[1]['requests']), 5)
        self.assertEqual(boss.req('POST', f'/api/signups/{ids[4]}/delete', {})[0], 404)
        # approving makes the account "Add an account" would: a person (role user, the position), a custodial device
        devs = lambda: boss.req('GET', '/api/devices')[1]['all']
        before = len(devs())
        st, r, _ = sara.req('POST', f'/api/signups/{ids[4]}/approve', {})
        self.assertEqual((st, r['ok'], r['username']), (200, True, 'nadia'), r)
        nadia = [u for u in boss.req('GET', '/api/users')[1]['users'] if u['username'] == 'nadia'][0]
        self.assertEqual((nadia['role'], nadia['active'], nadia['has_password'], nadia['full_name'], nadia['position'], nadia.get('no_account')),
                         ('user', True, True, 'Ali Hassan', 'Operator', None))
        mine = [d for d in devs() if d['person'] == nadia['person']]
        self.assertEqual((len(devs()), len(mine), mine[0]['revoked']), (before + 1, 1, False), mine)
        st, r, nc = self.login('nadia', 'nadia password 1')
        self.assertEqual(st, 200, r)
        self.assertEqual(nc.req('GET', '/api/me')[1]['user']['username'], 'nadia')
        self.assertEqual(nc.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501', 'changes': {'near': 'pump'}, 'base': {}}})[1]['status'], 'pending')
        self.assertEqual(nc.req('GET', '/api/signups')[0], 403)
        self.assertEqual(boss.req('POST', f'/api/signups/{ids[4]}/approve', {})[0], 404)     # decided: gone
        # a name somebody has: refused as it is, approved under another one (their password stays theirs)
        st, r, _ = boss.req('POST', f'/api/signups/{ids[0]}/approve', {})
        self.assertEqual(st, 409, r)
        self.assertEqual(boss.req('POST', f'/api/signups/{ids[0]}/approve', {'username': 'SARA'})[0], 409)
        self.assertEqual(boss.req('POST', f'/api/signups/{ids[0]}/approve', {'username': 'no good'})[0], 400)
        self.assertEqual(boss.req('POST', f'/api/signups/{ids[0]}/approve', {'username': 'boss2'})[0], 200)
        self.assertEqual(self.login('boss2', 'boss password 1')[0], 200)
        self.assertEqual(self.login('boss', 'boss password 1', ip='10.9.9.8')[:2], wrong)    # no request waits under "boss" now
        self.assertEqual(self.login('boss', 'a long password')[0], 200)                       # the manager's own: untouched
        # two asked for "ali": the first approved takes it, the second then shows as taken
        self.assertEqual(boss.req('POST', f'/api/signups/{ids[2]}/approve', {})[0], 200)
        left = {q['id']: q['taken'] for q in boss.req('GET', '/api/signups')[1]['requests']}
        self.assertEqual(left, {ids[1]: True, ids[3]: True})
        # rejecting deletes the request: nothing waits, nothing signs in
        for i in (1, 3):
            self.assertEqual(sara.req('POST', f'/api/signups/{ids[i]}/reject', {})[0], 200)
        self.assertEqual(boss.req('GET', '/api/signups')[1]['requests'], [])
        self.assertEqual(sara.req('POST', f'/api/signups/{ids[1]}/reject', {})[0], 404)
        self.assertEqual(self.login('sara', 'sara password 1')[0], 200)
        self.assertEqual(users(), {'boss', 'sara', 'omar', 'nadia', 'boss2', 'ali'})

        # a rejected person: as if they had never asked
        st, r, _ = self.ask('10.0.5.1', username='zaid', password='zaid password 1')
        self.assertEqual(st, 200)
        zid = boss.req('GET', '/api/signups')[1]['requests'][0]['id']
        self.assertEqual(self.login('zaid', 'zaid password 1')[:2], (403, {'error': self.WAITING}))
        self.assertEqual(boss.req('POST', f'/api/signups/{zid}/reject', {})[0], 200)
        self.assertEqual(self.login('zaid', 'zaid password 1')[:2], wrong)

        # one username, several requests (each person's own password): at most 3 wait, a 4th is refused in the usual
        # words; each of the three is told it waits (not only the newest), and the list tells the admin there are three
        for i in range(3):
            self.assertEqual(self.ask('10.0.8.%d' % i, username='dup', password='dup password %d' % i)[0], 200)
        self.assertEqual(self.ask('10.0.8.9', username='dup', password='dup password 9')[:2], (403, {'error': self.REFUSED}))
        for i in range(3):
            self.assertEqual(self.login('dup', 'dup password %d' % i, ip='10.0.9.%d' % i)[:2], (403, {'error': self.WAITING}), i)
        self.assertEqual(self.login('dup', 'dup password 9', ip='10.0.9.9')[:2], wrong)
        dups = boss.req('GET', '/api/signups')[1]['requests']
        self.assertEqual([(q['username'], q['same']) for q in dups], [('dup', 3)] * 3)
        for q in dups:
            self.assertEqual(boss.req('POST', '/api/signups/%s/reject' % q['id'], {})[0], 200)
        # "it waits" is slowed like a wrong password: the sixth time in a row from one address has to wait
        self.assertEqual(self.ask('10.0.8.20', username='keen', password='keen password 1')[0], 200)
        codes = [self.login('keen', 'keen password 1', ip='10.0.9.20')[0] for _ in range(6)]
        self.assertEqual(codes, [403] * 5 + [429])
        kid = boss.req('GET', '/api/signups')[1]['requests'][0]['id']
        self.assertEqual(boss.req('POST', f'/api/signups/{kid}/reject', {})[0], 200)

        # throttled per address like sign-in: after 5 refusals an address waits, the right code included; others don't
        codes = [self.ask('10.0.6.1', code='guess-%d' % i)[0] for i in range(7)]
        self.assertEqual(codes[:5], [403] * 5)
        self.assertEqual(codes[5:], [429, 429])
        self.assertEqual(self.ask('10.0.6.1', username='late')[0], 429)
        self.assertEqual(self.ask('10.0.6.2', username='other')[0], 200)
        # refused requests never lock a sign-in out (their own counter), and the other way round
        self.assertEqual(self.login('boss', 'a long password', ip='10.0.6.1')[0], 200)

        # the CLI, through the running server: change the code, switch sign-up off; what it prints never repeats it
        code, out = self.cli('set-signup-code', 'second-code-88')
        self.assertEqual(code, 0, out)
        self.assertIn('Sign-up is on', out)
        self.seen.append(out)
        self.assertEqual(self.ask('10.0.7.1', username='old')[0], 403)                       # the old code is dead
        self.assertEqual(self.ask('10.0.7.2', username='new', code='second-code-88')[0], 200)
        code, out = self.cli('set-signup-code', 'short')
        self.assertNotEqual(code, 0)
        self.seen.append(out)
        # "-": the code comes on standard input, so it is in no process list and no shell history
        code, out = self.cli('set-signup-code', '-', stdin='third-code-99\n')
        self.assertEqual(code, 0, out)
        self.assertIn('Sign-up is on', out)
        self.seen.append(out)
        self.assertEqual(self.ask('10.0.7.5', username='old2', code='second-code-88')[0], 403)
        self.assertEqual(self.ask('10.0.7.6', username='new2', code='third-code-99')[0], 200)
        self.assertEqual(self.ask('10.0.7.7', username='dash', code='-')[0], 403)             # "-" itself is not the code
        code, out = self.cli('set-signup-code', '')
        self.assertEqual((code, out), (0, 'Sign-up is off.'))
        self.assertIs(anon.req('GET', '/api/config')[1]['signup'], False)
        self.assertEqual(self.ask('10.0.7.3', username='late', code='second-code-88')[:2], (403, {'error': self.REFUSED}))
        self.assertEqual(self.ask('10.0.7.4', username='late', code='')[:2], (403, {'error': self.REFUSED}))
        # switched off from Manage too (an empty code); the requests already waiting stay for the admin
        self.assertEqual(boss.req('POST', '/api/signup-code', {'code': self.CODE})[0], 200)
        self.assertEqual(say(boss, 'POST', '/api/signup-code', {'code': ''}), {'ok': True, 'enabled': False})
        L = say(boss, 'GET', '/api/signups')
        self.assertEqual((L['enabled'], L['set'], sorted(q['username'] for q in L['requests'])), (False, None, ['new', 'new2', 'other']))

        # the code is in no response, not in the plant's log (a bundle is the whole log), not in the server's output
        import gzip
        st, bundle, _ = boss.req('GET', '/api/bundle')
        self.assertEqual(st, 200)
        log = gzip.decompress(bundle)
        self.assertIn(b'nadia', log)
        self.seen.append(json.dumps(boss.req('GET', '/api/users?show_hidden=1')[1]))
        self.seen.append(json.dumps(boss.req('GET', '/api/revisions')[1]))
        self.seen.append(json.dumps(boss.req('GET', '/api/state')[1]))
        self.proc.terminate()
        out = self.proc.stdout.read()
        for word in (self.CODE, 'second-code-88', 'nadia password 1'):
            self.assertNotIn(word.encode(), log)
            self.assertNotIn(word, out)
            for body in self.seen:
                self.assertNotIn(word, body)
        with open(os.path.join(self.dir, 'server.db'), 'rb') as f:
            db = f.read()
        for word in (self.CODE, 'second-code-88', 'nadia password 1', '$argon2id$'):
            self.assertNotIn(word.encode(), db)      # the store's rows are sealed


class SignupCap(Base):
    extra = {'trusted_proxy': True}

    def test_cap_then_pressure(self):
        """at most 50 requests wait; the 51st is refused in the same words as a wrong code, until one is decided. Then
        50 refusals from anywhere within 15 minutes close sign-up for every address for a while."""
        boss = self.manager()
        self.assertEqual(boss.req('POST', '/api/signup-code', {'code': 'cap-code-123'})[0], 200)
        ask = lambda ip, name, code='cap-code-123': Client(self.base).req('POST', '/api/signup', {
            'code': code, 'username': name, 'full_name': 'Some One', 'position': 'Operator', 'password': 'a long password'},
            headers={'X-Forwarded-For': ip})[:2]
        for i in range(50):
            self.assertEqual(ask('10.1.0.%d' % i, 'user%d' % i)[0], 200, i)
        full = ask('10.1.1.1', 'late')
        self.assertEqual(full, (403, {'error': Signup.REFUSED}))
        self.assertEqual(full, ask('10.1.1.2', 'late', 'wrong-code'))
        L = boss.req('GET', '/api/signups')[1]['requests']
        self.assertEqual(len(L), 50)
        self.assertEqual(boss.req('POST', '/api/signups/%s/reject' % L[0]['id'], {})[0], 200)
        self.assertEqual(ask('10.1.1.3', 'late')[0], 200)
        self.assertEqual(ask('10.1.1.4', 'later')[0], 403)
        # under pressure: 3 refusals so far, 47 more from as many addresses; then nobody gets through, right code or not
        self.assertEqual(boss.req('POST', '/api/signups/%s/reject' % L[1]['id'], {})[0], 200)
        for i in range(47):
            self.assertEqual(ask('10.1.2.%d' % i, 'guess', 'wrong-%d' % i)[0], 403, i)
        self.assertEqual(ask('10.1.3.1', 'fresh')[0], 429)
        self.assertEqual(len(boss.req('GET', '/api/signups')[1]['requests']), 49)
        # signing in is not held up by it
        self.assertEqual(Client(self.base).req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'},
                                               headers={'X-Forwarded-For': '10.1.3.1'})[0], 200)


class SignupOneSource(Base):
    extra = {'trusted_proxy': True}

    def test_one_source(self):
        """one address files at most 10 requests in 15 minutes (a person with the code can't fill the list at once);
        another address is not held up, and nothing was filed by the refused ones"""
        boss = self.manager()
        self.assertEqual(boss.req('POST', '/api/signup-code', {'code': 'cap-code-123'})[0], 200)
        ask = lambda ip, name: Client(self.base).req('POST', '/api/signup', {
            'code': 'cap-code-123', 'username': name, 'full_name': 'Some One', 'position': 'Operator', 'password': 'a long password'},
            headers={'X-Forwarded-For': ip})[0]
        self.assertEqual([ask('10.4.0.1', 'one%d' % i) for i in range(12)], [200] * 10 + [429, 429])
        self.assertEqual(ask('10.4.0.2', 'two'), 200)
        self.assertEqual(len(boss.req('GET', '/api/signups')[1]['requests']), 11)


class OfflineList(Base):
    """GET /api/offline: the files a browser saves to work without the server ("Download for offline")"""

    def cli(self, *args):
        r = subprocess.run([BIN, *args, '--config', os.path.join(self.dir, 'config.json')], capture_output=True, text=True,
                           cwd=self.dir, timeout=60)
        return r.returncode, (r.stdout + r.stderr).strip()

    def test_offline_list(self):
        anon = Client(self.base)
        self.assertEqual(anon.req('GET', '/api/offline')[0], 401)             # the plant's file names: members only
        self.assertEqual(anon.req('GET', '/apple-touch-icon.png')[0], 200)    # (the icon iOS asks for, before any sign-in)
        boss = self.manager()
        st, L, _ = boss.req('GET', '/api/offline')
        self.assertEqual((st, L['plant_data']), (200, None), L)
        urls = [f[0] for f in L['files']]
        self.assertEqual(urls, sorted(set(urls)))
        # the pages and scripts (not the worker's own script), the decoders and the encoder, the fonts, the program's data
        for u in ('/', '/index.html', '/admin.js', '/common.js', '/tiles.js', '/course.html', '/manifest.webmanifest', '/apple-touch-icon.png',
                  '/vendor/kks/kks-simd.wasm', '/vendor/kks/kks-dec.wasm', '/vendor/fonts/courses.css', '/data/kks.json', '/data/courses/fnd.json'):
            self.assertIn(u, urls)
        self.assertTrue(any(u.startswith('/vendor/fonts/') and u.endswith('.woff2') for u in urls))
        self.assertTrue(any(u.startswith('/data/courses/') and u.endswith('.jxl') for u in urls))
        self.assertNotIn('/sw.js', urls)
        self.assertFalse([u for u in urls if u.endswith(('.md', '.txt', '.ttf')) or 'SHA256SUMS' in u or '..' in u])
        # every one is served, and is as long as the list says
        for u, n in L['files']:
            st, body, _ = boss.req('GET', u)
            self.assertEqual(st, 200, u)
            if isinstance(body, bytes): self.assertEqual(len(body), n, u)      # (JSON comes back parsed)
        self.assertEqual(boss.req('GET', '/api/offline')[1]['version'], L['version'])       # nothing changed: the same
        # published plant data: its files are listed, the drawings' with ?v=<version>
        d = os.path.join(self.dir, 'pd')
        os.makedirs(os.path.join(d, 'sheets'))
        open(os.path.join(d, 'sheets.json'), 'w').write(json.dumps([{'id': 'a', 'name': 'A', 'levels': 1, 'w': 10, 'h': 10}]))
        open(os.path.join(d, 'tags.json'), 'w').write('[]')
        open(os.path.join(d, 'sheets', 'a.kkp'), 'wb').write(b'KKP1 not really')
        open(os.path.join(d, 'sheets', 'a.o0.jxl'), 'wb').write(b'\xff\x0a')
        self.assertEqual(self.cli('publish-data', d)[0], 0)
        L2 = boss.req('GET', '/api/offline')[1]
        u2 = dict(map(tuple, L2['files']))
        self.assertEqual(L2['plant_data'], 1)
        self.assertNotEqual(L2['version'], L['version'])
        self.assertEqual((u2['/data/sheets/a.kkp?v=1'], u2['/data/sheets/a.o0.jxl?v=1']), (15, 2))
        self.assertIn('/data/sheets.json', u2)
        self.assertEqual(u2['/data/tags.json'], 2)
        for u in ('/data/sheets/a.kkp?v=1', '/data/tags.json', '/data/sheets.json'):
            self.assertEqual(boss.req('GET', u)[0], 200, u)
        # a change to one file changes the version
        open(os.path.join(d, 'sheets', 'a.kkp'), 'wb').write(b'KKP1 not really!')
        self.assertEqual(self.cli('publish-data', d)[0], 0)
        L3 = boss.req('GET', '/api/offline')[1]
        self.assertEqual(L3['plant_data'], 2)
        self.assertNotEqual(L3['version'], L2['version'])
        self.assertIn('/data/sheets/a.kkp?v=2', [f[0] for f in L3['files']])


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
            # the line comes once the listener is open: a connection right after it is taken (it was refused while
            # the line came before mDNS and the listeners were set up)
            try:
                socket.create_connection(('127.0.0.1', cfg['port']), timeout=5).close()
            except ConnectionRefusedError:
                self.fail('nothing listens on 127.0.0.1 when the server says it is on')
        finally:
            p.terminate(); p.wait(5)

class Front(Base):
    """the web pages behind an HTTPS proxy (finding #26's adversarial pass): Secure cookies under an https public URL,
    only this server's host names, X-Forwarded-For only from a proxy the operator vouches for"""

    def test_defaults_without_proxy(self):
        boss = Client(self.base)
        st, r, hdr = boss.req('POST', '/api/setup', {'token': self.setup, 'username': 'boss', 'password': 'a long password',
                                                     'full_name': 'The Manager', 'position': 'Plant manager'})
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
                                                     'full_name': 'The Manager', 'position': 'Plant manager'})
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
