"""The phone's direct path (PROTOCOL-v2 §18, decision 0028) on an emulator: the phone joins the Nim server on the LAN,
then the server restarts with its LAN sync port closed, so "Sync now" must go through the relay (the Python twin,
relay/twin.py, reached from the emulator through `adb reverse`). Both sides offer candidates: the sync should go
direct (hole punching + the core's reliable UDP) and bring the server's change to the phone.
  python3 android/app2/e2e/test_direct.py [APK] [SERVER]
Needs a running emulator and .venv (the relay twin needs cryptography)."""
import json, os, re, shutil, socket, subprocess, sys, tempfile, time, unittest
sys.path.insert(0, os.path.dirname(__file__))
import adbui as ui  # noqa: E402
from test_app2 import Client, free_port  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
APK = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, 'android/app2/build/outputs/apk/debug/app2-debug.apk')
SERVER = sys.argv[2] if len(sys.argv) > 2 else '/tmp/kkslinux/kks_server'
del sys.argv[1:]
PKG = 'io.github.walkdown'
PY = os.path.join(REPO, '.venv/bin/python') if os.path.exists(os.path.join(REPO, '.venv/bin/python')) else 'python3'


class Direct(unittest.TestCase):
    def start_server(self, sync_port):
        self.cfg['sync_port'] = sync_port
        with open(os.path.join(self.dir, 'config.json'), 'w') as f:
            json.dump(self.cfg, f)
        self.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = self.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
            if m:
                setup = m[1]
            if 'server on' in line:
                break
        return setup

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-direct-')
        self.port, self.sport, self.rport = free_port(), free_port(), free_port()
        self.relay = subprocess.Popen([PY, os.path.join(REPO, 'relay', 'twin.py'), str(self.rport)], cwd=REPO,
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.cfg = {'address': '127.0.0.1', 'port': self.port, 'plant_name': 'Test plant', 'web_dir': REPO,
                    'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
                    'storage_key_file': os.path.join(self.dir, 'storage.key'),
                    'plant_dir': os.path.join(self.dir, 'plant-data'), 'backup_dir': os.path.join(self.dir, 'backups')}
        setup = self.start_server(self.sport)
        self.boss = Client(f'http://127.0.0.1:{self.port}')
        assert self.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                    'full_name': 'The Manager'}).get('ok')
        # one address for both: the emulator reaches the host's relay through adb reverse
        ui.adb('reverse', f'tcp:{self.rport}', f'tcp:{self.rport}')
        r = self.boss.req('POST', '/api/settings/relay', {'url': f'ws://127.0.0.1:{self.rport}'})
        assert r.get('ok'), r
        subprocess.run(ui.ADB + ['uninstall', 'kks.explorer'], capture_output=True)   # no old app on the setup screen
        subprocess.run(ui.ADB + ['uninstall', PKG], capture_output=True)   # a newer test build (test_update's 9.9.9) blocks -r
        r = subprocess.run(ui.ADB + ['install', '-t', APK], capture_output=True, text=True)
        assert 'Success' in r.stdout, 'install failed: ' + r.stdout + r.stderr
        ui.sh('pm', 'clear', PKG)
        ui.sh('am', 'start', '-n', f'{PKG}/kks.explorer.MainActivity')

    def tearDown(self):
        ui.sh('am', 'force-stop', PKG)
        for p in (self.server, self.relay):
            p.terminate(); p.wait(5)
        ui.adb('reverse', '--remove', f'tcp:{self.rport}')
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_direct(self):
        self.internet_sync(stall=False)

    def test_stalled_direct_falls_back(self):
        """found in the field 2026-10-03: a direct path punched through, then stalled on every sync. The same sync must
        go again through the pipe, and that device keeps the pipe for an hour"""
        self.internet_sync(stall=True)

    def internet_sync(self, stall):
        ui.tap('Join through a server', exact=True, timeout=30)
        ui.type_into('Server address', f'10.0.2.2:{self.sport}')
        ui.type_into('Username', 'boss')
        ui.type_into('Password', 'a long password')
        ui.tap('Join', exact=True)
        model = ui.sh('getprop', 'ro.product.model').strip()
        for _ in range(60):
            if any(d['label'] == model for d in self.boss.req('GET', '/api/devices').get('all', [])):
                break
            time.sleep(1)
        else:
            self.fail('the phone never joined')
        time.sleep(3)
        # the LAN path closes; a change waits on the server
        ui.sh('am', 'broadcast', '-f', '32', '-a', 'kks.explorer.DEBUG_DIRECT', '-p', PKG, '--ez', 'stall', 'true' if stall else 'false')
        ui.adb('logcat', '-c')
        self.server.terminate(); self.server.wait(5)
        self.start_server(0)
        self.boss = Client(f'http://127.0.0.1:{self.port}')
        assert 'user' in self.boss.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'})
        r = self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                                                  'changes': {'notes': 'over the internet'}, 'base': {'notes': ''}}})
        self.assertEqual(r.get('status'), 'approved', r)
        time.sleep(3)                                  # the server back in the relay room
        ui.tap('Manage', exact=True)
        ui.tap('Account', exact=True)
        ui.scroll_to('Sync now', exact=True)
        ui.tap('Sync now', exact=True)
        # every sync since the LAN closed (an automatic one may come before the tap): the change arrived, directly
        got, syncs = '', []
        for _ in range(60):
            got = subprocess.run(ui.ADB + ['logcat', '-d', '-s', 'KKSSync'], capture_output=True, text=True).stdout
            syncs = re.findall(r'relay sync \((direct|relay)\) (?:with|from) \S+: sent (\d+), received (\d+)', got)
            if any(int(r) > 0 for _, _, r in syncs):
                break
            time.sleep(1)
        print(f'\n  phone ↔ server since the LAN closed{" (direct path stalled)" if stall else ""}:', syncs)
        self.assertTrue(any(int(r) > 0 for _, _, r in syncs), got[-3000:])
        if stall:
            self.assertIn('the relay pipe for this device for an hour', got)
            self.assertTrue(all(how == 'relay' for how, _, _ in syncs), 'a sync claimed the stalled direct path')
        else:
            self.assertTrue(all(how == 'direct' for how, _, _ in syncs), 'hole punching failed; the pipe carried a sync')


if __name__ == '__main__':
    unittest.main()
