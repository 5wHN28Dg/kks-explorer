"""M5b self-updates (server/updates.py): a signed release on a fake GitHub (local HTTP server), checked, refused when
anything doesn't match the pinned key or the signed hashes, installed into a user folder and handed over to."""
import io, json, os, shutil, subprocess, sys, tarfile, tempfile, threading, unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from server import updates as U
from server.store import Store
from tools import release as R


def targz(members):
    b = io.BytesIO()
    with tarfile.open(fileobj=b, mode='w:gz') as t:
        for name, data in members.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(data), 0o755
            t.addfile(info, io.BytesIO(data))
    return b.getvalue()


class FakeGitHub:
    def __init__(self):
        self.files = {}
        fake = self

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                port = self.server.server_address[1]
                if self.path == '/repos/x/releases/latest':
                    body = json.dumps({'tag_name': 'v', 'assets': [{'name': n, 'browser_download_url': f'http://127.0.0.1:{port}/dl/{n}'}
                                                                   for n in fake.files]}).encode()
                elif self.path.startswith('/dl/') and self.path[4:] in fake.files:
                    body = fake.files[self.path[4:]]
                else:
                    self.send_response(404); self.end_headers(); return
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), H)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.api = f'http://127.0.0.1:{self.httpd.server_address[1]}/repos/x/releases/latest'

    def publish(self, version, files, key, notes='notes'):
        m = R.manifest(version, files, notes)
        self.files = {**files, 'release.json': m, 'release.json.sig': R.sign(m, key).encode()}


class UpdatesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.store = Store({'db': os.path.join(self.tmp, 'plant.db'), 'backup_dir': os.path.join(self.tmp, 'backups'),
                            'snapshot_every': 1000, 'snapshot_keep': 3})
        self.key = Ed25519PrivateKey.generate()
        self.gh = FakeGitHub()
        self.home = os.path.join(self.tmp, 'home')
        os.makedirs(self.home)
        self.saved = (U.frozen, U.current, sys.platform)
        U.current = lambda: '1.0.0'

    def tearDown(self):
        U.frozen, U.current, sys.platform = self.saved
        self.gh.httpd.shutdown()
        shutil.rmtree(self.tmp)

    def updater(self, home=None):
        return U.Updater({'update_check': True}, self.store, home=home, api=self.gh.api, log=lambda *a: None,
                         pub=R.public_b64u(self.key))

    def test_check_signature_and_version(self):
        self.gh.publish('1.2.0', {'KKS-Explorer-linux.tar.gz': b'x'}, self.key)
        st = self.updater().check()
        self.assertEqual((st['latest'], st['available'], st['error'], st['how']), ('1.2.0', True, None, 'git'))
        self.assertFalse(st['can_install'])                        # running from source: update with git
        # signed by another key, or changed after signing: not a release
        self.gh.publish('1.3.0', {'KKS-Explorer-linux.tar.gz': b'x'}, Ed25519PrivateKey.generate())
        st = self.updater().check()
        self.assertIn('not signed', st['error'])
        self.assertEqual(st['latest'], '1.2.0')                    # the last good one is kept
        self.gh.publish('1.3.0', {'KKS-Explorer-linux.tar.gz': b'x'}, self.key)
        self.gh.files['release.json'] = self.gh.files['release.json'].replace(b'1.3.0', b'9.9.9')
        self.assertIn('not signed', self.updater().check()['error'])
        # an older or equal version is not an update
        self.gh.publish('1.0.0', {'KKS-Explorer-linux.tar.gz': b'x'}, self.key)
        self.assertFalse(self.updater().check()['available'])
        # the state survives a restart (checked at most daily)
        self.assertEqual(self.updater().status()['latest'], '1.0.0')

    def test_install_and_handoff(self):
        U.frozen, sys.platform = (lambda: True), 'linux'
        pkg = targz({'KKS Explorer/KKS Explorer': b'#!/bin/sh\necho new\n', 'KKS Explorer/_internal/x': b'lib',
                     'install-linux.sh': b'not unpacked', '../evil': b'never'})
        self.gh.publish('1.2.0', {'KKS-Explorer-linux.tar.gz': pkg}, self.key)
        u = self.updater(self.home)
        st = u.check()
        self.assertTrue(st['can_install'], st)
        st = u.install()
        self.assertEqual(st['staged'], '1.2.0')
        d = os.path.join(self.home, 'versions', '1.2.0')
        self.assertEqual(sorted(os.listdir(d)), ['KKS Explorer'])
        self.assertFalse(os.path.exists(os.path.join(self.tmp, 'evil')))
        exe = os.path.join(d, 'KKS Explorer', 'KKS Explorer')
        self.assertTrue(os.access(exe, os.X_OK))
        # next start: the old program starts the new one and steps aside; the new one runs itself
        started = []
        real = subprocess.Popen
        subprocess.Popen = lambda cmd, **kw: started.append((cmd, kw['env'].get('KKS_HANDOFF')))
        try:
            self.assertTrue(U.handoff(self.home, ['old-exe', '--no-window']))
            self.assertEqual(started, [([exe, '--no-window'], '1')])
            U.current = lambda: '1.2.0'
            self.assertFalse(U.handoff(self.home, ['new-exe']))
        finally:
            subprocess.Popen = real
        # older unpacked versions go away, the running and the newest stay
        os.makedirs(os.path.join(self.home, 'versions', '1.1.0'))
        U.cleanup(self.home)
        self.assertEqual(sorted(os.listdir(os.path.join(self.home, 'versions'))), ['1.2.0', 'ready.json'])

    def test_download_must_match_the_signed_hash(self):
        U.frozen, sys.platform = (lambda: True), 'linux'
        pkg = targz({'KKS Explorer/KKS Explorer': b'good'})
        self.gh.publish('1.2.0', {'KKS-Explorer-linux.tar.gz': pkg}, self.key)
        u = self.updater(self.home)
        u.check()
        self.gh.files['KKS-Explorer-linux.tar.gz'] = targz({'KKS Explorer/KKS Explorer': b'evil'})   # swapped afterwards
        with self.assertRaisesRegex(ValueError, 'does not match'):
            u.install()
        self.assertIsNone(u.status()['staged'])
        self.assertFalse(os.path.exists(os.path.join(self.home, 'versions', '1.2.0')))


if __name__ == '__main__':
    unittest.main()
