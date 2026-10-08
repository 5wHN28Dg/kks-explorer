"""Signing in on the server machine itself (http://127.0.0.1) while public_url is https, in all three engines. The
session cookie is Secure for the public address; WebKit drops a Secure cookie set over http://127.0.0.1, so a page
on this machine's own http address gets it without Secure.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_local_login.py
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server)."""
import json, os, re, shutil, subprocess, tempfile, time, unittest, urllib.request
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


class LocalLogin(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-local-login-')
        cls.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': 0, 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'public_url': 'https://walk.example'}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m: setup = m[1]
            if 'server on' in line: break
        time.sleep(0.3)
        cls.base = 'http://127.0.0.1:%d' % cls.port
        r = urllib.request.Request(cls.base + '/api/setup', method='POST', headers={'Content-Type': 'application/json'},
                                   data=json.dumps({'token': setup, 'username': 'boss', 'password': 'a long password',
                                                    'full_name': 'The Manager', 'position': 'Plant manager'}).encode())
        with urllib.request.urlopen(r) as resp:
            assert '; Secure' in resp.headers['Set-Cookie']   # no Origin: not a page here, so Secure

    @classmethod
    def tearDownClass(cls):
        cls.server.terminate(); cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def engine(self, name):
        with sync_playwright() as p:
            browser = p[name].launch()
            page = browser.new_page()
            page.goto(self.base + '/learning.html')
            st = page.evaluate("""() => fetch('/api/login', {method: 'POST', headers: {'Content-Type': 'application/json'},
                body: JSON.stringify({username: 'boss', password: 'a long password'})}).then(r => r.status)""")
            self.assertEqual(st, 200)
            self.assertEqual(page.evaluate("() => fetch('/api/state').then(r => r.status)"), 200)   # signed in
            browser.close()

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
