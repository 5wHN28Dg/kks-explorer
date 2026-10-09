"""Walkdown's self-update on an emulator (decision 0044): the app joins a Nim server; a fake GitHub serves a release whose
manifest is signed with a test P-256 key. A wrongly signed release shows nothing; the right one shows the banner, and
Install downloads the APK, checks it against the manifest, and Android installs it after its own dialog.
  python3 android/app2/e2e/test_update.py [APK] [NEWER_APK] [SERVER]
NEWER_APK: the same app built with -PkksVersion=9.9.9 (default /tmp/walkdown-9.9.9.apk). Needs .venv (cryptography)."""
import base64, hashlib, json, os, re, shutil, subprocess, sys, tempfile, time, unittest
sys.path.insert(0, os.path.dirname(__file__))
import adbui as ui  # noqa: E402
# read before test_app2 is imported: it takes (and deletes) the arguments as its own. Read after, they were gone, and
# the test installed whatever debug APK was at the default path instead of the one named (the 0.10.0 rehearsal "failed"
# because that path held the 9.9.9 build, to which 9.9.9 is not an update)
ARGS = sys.argv[1:4]
from test_app2 import Client, free_port  # noqa: E402
from fakegithub import FakeGitHub, calm, HOST  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
APK = ARGS[0] if len(ARGS) > 0 else os.path.join(REPO, 'android/app2/build/outputs/apk/debug/app2-debug.apk')
NEWER = ARGS[1] if len(ARGS) > 1 else '/tmp/walkdown-9.9.9.apk'
SERVER = ARGS[2] if len(ARGS) > 2 else '/tmp/kkslinux/kks_server'
del sys.argv[1:]
PKG = 'io.github.walkdown'


def p256_release(files, version='9.9.9'):
    """{name: path} → the manifest bytes, its P-256 signature (base64 DER) and the public key (base64 X.509 DER)"""
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    k = ec.generate_private_key(ec.SECP256R1())
    out = {}
    for n, p in files.items():
        data = open(p, 'rb').read()
        out[n] = {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
    m = json.dumps({'app': 'kks-explorer', 'version': version, 'notes': 'Test release', 'files': out}, indent=1).encode()
    sig = k.sign(b'kks-release-v2\n' + m, ec.ECDSA(hashes.SHA256()))
    pub = k.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    return m, base64.b64encode(sig).decode(), base64.b64encode(pub).decode()


def version_installed():
    out = ui.sh('dumpsys', 'package', PKG)
    m = re.search(r'versionName=(\S+)', out)
    return m[1] if m else None


def apk_version(path):
    """an APK file's versionName (aapt2 from the SDK's newest build-tools)"""
    tools = os.path.join(os.path.dirname(os.path.dirname(ui.ADB[0])), 'build-tools')
    aapt2 = os.path.join(tools, max(os.listdir(tools), key=lambda v: [int(x) if x.isdigit() else 0 for x in re.split(r'[.-]', v)]), 'aapt2')
    m = re.search(r"versionName='([^']*)'", subprocess.run([aapt2, 'dump', 'badging', path], capture_output=True, text=True).stdout)
    assert m, f'no versionName in {path}'
    return m[1]


def newer(a, b):
    """the app's own comparison (Updates.newer): numeric major.minor.patch"""
    def parts(v):
        return ([int(x) if x.isdigit() else 0 for x in v.split('.')] + [0, 0, 0])[:3]
    return parts(a) > parts(b)


class Update(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-update-')
        self.port, self.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': self.port, 'sync_port': self.sport, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups')}
        with open(os.path.join(self.dir, 'config.json'), 'w') as f:
            json.dump(cfg, f)
        self.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = self.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
        assert Client(f'http://127.0.0.1:{self.port}').req('POST', '/api/setup', {
            'token': setup, 'username': 'boss', 'password': 'a long password', 'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        subprocess.run(ui.ADB + ['uninstall', PKG], capture_output=True)
        r = subprocess.run(ui.ADB + ['install', '-t', APK], capture_output=True, text=True)
        assert 'Success' in r.stdout, r.stdout + r.stderr
        # the app under test is the one named, and the release offered is newer than it (else no banner is right)
        self.assertEqual(version_installed(), apk_version(APK), f'installed is not {APK}')
        self.assertTrue(newer(apk_version(NEWER), version_installed()),
                        f'{NEWER} ({apk_version(NEWER)}) is not newer than {APK} ({version_installed()})')
        try:
            kind = 'debuggable' if ui.debuggable(PKG) else 'not debuggable'
        except AssertionError as e:      # only informative here
            kind = f'debuggable unknown: {e}'
        print(f'\n  app under test: {APK} ({version_installed()}, {kind})')
        ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')

    def tearDown(self):
        ui.sh('am', 'force-stop', PKG)
        self.server.terminate(); self.server.wait(5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_update(self):
        calm()
        ui.tap('Join through a server', exact=True, timeout=30)
        ui.type_into('Server address', f'{HOST}:{self.sport}')
        ui.type_into('Username', 'boss')
        ui.type_into('Password', 'a long password')
        ui.tap('Join', exact=True)
        ui.find('Drawings', exact=True, timeout=40)
        before = version_installed()
        m, sig, pub = p256_release({'walkdown.apk': NEWER})
        gh = FakeGitHub({'walkdown.apk': NEWER})
        gh.blobs['release.json'], gh.blobs['release.json.p256'] = m, sig.encode()
        # a release signed by another key: nothing to offer
        _, _, other = p256_release({'walkdown.apk': NEWER})
        ui.sh('am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_UPDATE', '-p', PKG, '--es', 'api', gh.api, '--es', 'pub', other)
        time.sleep(4)
        self.assertFalse(ui.present('Walkdown 9.9.9 is out.', exact=True), 'a wrongly signed release was offered')
        # the right key: the banner, then Android's own install dialog
        ui.sh('appops', 'set', PKG, 'REQUEST_INSTALL_PACKAGES', 'allow')
        ui.sh('am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_UPDATE', '-p', PKG, '--es', 'api', gh.api, '--es', 'pub', pub)
        calm()
        ui.find('Walkdown 9.9.9 is out.', exact=True, timeout=20)
        ui.tap('Install', exact=True)
        t0 = time.time()
        while time.time() - t0 < 90:
            calm()
            for label in ('UPDATE', 'Update', 'INSTALL', 'Install'):
                if ui.present(label, exact=True) and not ui.present('Walkdown 9.9.9 is out.', exact=True):
                    ui.tap(label, exact=True)
                    break
            if version_installed() == '9.9.9':
                break
            time.sleep(1)
        print(f'\n  installed: {before} → {version_installed()}')
        self.assertEqual(version_installed(), '9.9.9')


if __name__ == '__main__':
    unittest.main()
