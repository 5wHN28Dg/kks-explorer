"""A measurement plant with no plant data, as in the e2e tests: the Nim server, the synthetic sample sheet
(importer/tests/vectors/kkp-sample.pdf, imported by kks-import) and one approved tag (11LAB70AA501). The manager is
"boss" / "a long password".

As a module: Plant(server, importer).start() -> .base, .sync_port, .client; .stop().
As a command (the Windows job, whose server runs in WSL):
  python3 plant.py prepare DIR SERVER IMPORTER   make the plant in DIR and stop
  python3 plant.py serve DIR SERVER PORT SYNC_PORT   run the server on DIR's plant until killed"""
import http.cookiejar, json, os, re, socket, subprocess, sys, time, urllib.error, urllib.request

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
USER, PASSWORD = 'boss', 'a long password'


def free_port():
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    p = s.getsockname()[1]
    s.close()
    return p


class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def raw(self, m, p, body=None, raw=None, ctype='application/json'):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        h = {'Origin': self.base}
        if data is not None:
            h['Content-Type'] = ctype
        r = urllib.request.Request(self.base + p, data=data, method=m, headers=h)
        with self.op.open(r, timeout=60) as resp:
            return resp.read()

    def req(self, m, p, body=None, raw=None, ctype='application/json'):
        try:
            return json.loads(self.raw(m, p, body, raw, ctype))
        except urllib.error.HTTPError as e:
            return {'status': e.code, 'error': e.read().decode()}


def config(d, port, sync_port, importer=''):
    cfg = {'address': '127.0.0.1', 'port': port, 'sync_port': sync_port, 'plant_name': 'Measurement plant',
           'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(d, 'server.db'),
           'storage_key_file': os.path.join(d, 'storage.key'), 'plant_dir': os.path.join(d, 'plant-data'),
           'backup_dir': os.path.join(d, 'backups'), 'importer': importer,
           'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
    with open(os.path.join(d, 'config.json'), 'w') as f:
        json.dump(cfg, f)
    return os.path.join(d, 'config.json')


class Plant:
    def __init__(self, server, importer='', d=None, port=None, sync_port=None, log=None):
        import tempfile
        self.server, self.importer = server, importer
        self.dir = d or tempfile.mkdtemp(prefix='kks-budget-')
        self.port = port or free_port()
        self.sync_port = free_port() if sync_port is None else sync_port
        self.base = f'http://127.0.0.1:{self.port}'
        self.log = log
        self.proc = None

    def start(self, fresh=True):
        cfg = config(self.dir, self.port, self.sync_port, self.importer)
        self.proc = subprocess.Popen([self.server, 'serve', '--config', cfg], cwd=self.dir, stdout=subprocess.PIPE,
                                     stderr=subprocess.STDOUT, text=True)
        setup = None
        t0 = time.time()
        while time.time() - t0 < 60:
            line = self.proc.stdout.readline()
            if not line and self.proc.poll() is not None:
                raise RuntimeError('the server stopped at start')
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
        # keep reading its output, so the pipe never fills
        import threading
        out = open(self.log, 'a') if self.log else None

        def drain():
            for line in self.proc.stdout:
                if out:
                    out.write(line)
                    out.flush()
        threading.Thread(target=drain, daemon=True).start()
        self.client = Client(self.base)
        if fresh:
            assert setup, 'no setup link from a fresh server'
            assert self.client.req('POST', '/api/setup', {'token': setup, 'username': USER, 'password': PASSWORD,
                                                          'full_name': 'The Manager'}).get('ok')
            self.add_sheet()
        else:
            assert self.client.req('POST', '/api/login', {'username': USER, 'password': PASSWORD}).get('user')
        return self

    def add_sheet(self):
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f:
            pdf = f.read()
        assert self.client.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf,
                               ctype='application/pdf').get('ok')
        for _ in range(600):
            job = self.client.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running':
                break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        r = self.client.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {
            'sheet': 'sample', 'bbox': [400, 300, 520, 360], 'kks': '11LAB70AA501', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r

    def rss_mb(self):
        return rss_mb(self.proc.pid)

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(5)


def rss_mb(pid):
    """VmRSS of a Linux process, in MB (MiB, as docs/m6/MEASUREMENTS.md)"""
    with open(f'/proc/{pid}/status') as f:
        for line in f:
            if line.startswith('VmRSS:'):
                return int(line.split()[1]) / 1024
    raise RuntimeError(f'no VmRSS for {pid}')


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'prepare':
        d, server, importer = sys.argv[2:5]
        os.makedirs(d, exist_ok=True)
        p = Plant(os.path.abspath(server), os.path.abspath(importer), d=os.path.abspath(d)).start()
        p.stop()
        print('plant ready in', d)
    elif cmd == 'serve':
        d, server, port, sync_port = sys.argv[2:6]
        p = Plant(os.path.abspath(server), d=os.path.abspath(d), port=int(port), sync_port=int(sync_port),
                  log=os.path.join(d, 'server.log')).start(fresh=False)
        print('serving', p.base, 'sync', p.sync_port, flush=True)
        try:
            p.proc.wait()
        finally:
            p.stop()
    else:
        sys.exit(__doc__)
