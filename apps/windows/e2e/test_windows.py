"""End-to-end: the Windows app in a Windows 10 or 11 VM (decision 0033), against the Nim server on this machine.
No plant data: the drawing is importer/tests/vectors/kkp-sample.pdf. The app is driven through the native UI
Automation core (uiadrive.exe, what Narrator uses) inside the VM's desktop session.
  python3 apps/windows/e2e/test_windows.py VM_IP [APP.exe] [uiadrive.exe] [SERVER] [IMPORTER]
The VM: OpenSSH with the test key (~/.ssh/kks_vm), auto-logon user kks, reachable from here; the host is 192.168.122.1
from its side (libvirt's default network). See apps/windows/README.md."""
import base64, json, os, re, shutil, subprocess, sys, tempfile, time, unittest, urllib.error, urllib.request, http.cookiejar

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
VM = sys.argv[1] if len(sys.argv) > 1 else '192.168.122.181'
APP = sys.argv[2] if len(sys.argv) > 2 else '/tmp/kkswin/Walkdown.exe'
DRIVER = sys.argv[3] if len(sys.argv) > 3 else '/tmp/kkswin/uiadrive.exe'
SERVER = sys.argv[4] if len(sys.argv) > 4 else '/tmp/kkslinux/kks_server'
IMPORTER = sys.argv[5] if len(sys.argv) > 5 else '/tmp/kksimp/kks_import'
HOST = os.environ.get('KKS_HOST_FROM_VM', '192.168.122.1')
KEY = os.path.expanduser('~/.ssh/kks_vm')
del sys.argv[1:]
SSH = ['-i', KEY, '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'LogLevel=ERROR', '-o', 'BatchMode=yes']


def vm(cmd, check=False):
    r = subprocess.run(['ssh'] + SSH + ['kks@' + VM, cmd], capture_output=True, text=True, timeout=120, errors='replace')
    if check and r.returncode != 0: raise AssertionError(r.stdout + r.stderr)
    return r.stdout


def put(*files):
    subprocess.run(['scp', '-q'] + SSH + list(files) + ['kks@%s:C:/kks/' % VM], check=True, timeout=300)


# KKS_WIN_MSIX=signed.msix KKS_WIN_MSIX_CER=its.cer: test the installed MSIX instead of the plain exe (decision 0043):
# the certificate goes into LocalMachine\TrustedPeople (what IT does by policy), both are removed afterwards
MSIX, MSIX_CER = os.environ.get('KKS_WIN_MSIX'), os.environ.get('KKS_WIN_MSIX_CER')


def ui(name, lines, keep=True, sync_every=0, restart=False, env=None):
    """run uiadrive with these script lines in the desktop session; -> (passed, log). sync_every (ms): a fresh app's
    automatic sync rounds (KKS_SYNC_EVERY); restart: a new app process on the same data (not wiped); env: more
    environment for a fresh app"""
    path = os.path.join(tempfile.gettempdir(), name)
    with open(path, 'w') as f: f.write('\n'.join(lines) + '\n')
    put(path)
    vm('Remove-Item C:\\kks\\uia.log -ErrorAction SilentlyContinue')
    args = '-NoProfile -ExecutionPolicy Bypass -File C:\\kks\\run.ps1 -Script %s%s%s%s%s%s' % (
        name, ' -Keep' if keep and not restart else '', ' -Msix' if MSIX else '', ' -SyncEvery %d' % sync_every if sync_every else '',
        ' -Restart' if restart else '', ' -AppEnv "%s"' % ';'.join('%s=%s' % kv for kv in env.items()) if env else '')
    b64 = base64.b64encode(args.encode()).decode()
    vm('powershell -NoProfile -ExecutionPolicy Bypass -File C:\\kks\\runapp.ps1 -Exe powershell.exe -ArgB64 %s -Name kksuia' % b64)
    for _ in range(120):
        time.sleep(2)
        log = vm('[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-Content C:\\kks\\uia.log -Encoding UTF8 -ErrorAction SilentlyContinue')
        if ' done' in log: return ('PASSED' in log, log)
    return (False, log)


def msix(args):
    """msix.ps1 in the desktop session (installs need one); -> its result line"""
    vm('Remove-Item C:\\kks\\msix.log -ErrorAction SilentlyContinue')
    b64 = base64.b64encode(('-NoProfile -ExecutionPolicy Bypass -File C:\\kks\\msix.ps1 ' + args).encode()).decode()
    vm('powershell -NoProfile -ExecutionPolicy Bypass -File C:\\kks\\runapp.ps1 -Exe powershell.exe -ArgB64 %s -Name kksmsix' % b64)
    for _ in range(60):
        time.sleep(2)
        out = vm('Get-Content C:\\kks\\msix.log -ErrorAction SilentlyContinue').strip()
        if out: return out
    return 'no answer from msix.ps1'


def free_port():
    import socket
    s = socket.socket(); s.bind(('127.0.0.1', 0)); p = s.getsockname()[1]; s.close(); return p


class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None, raw=None, ctype='application/json'):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        r = urllib.request.Request(self.base + p, data=data, method=m, headers={'Content-Type': ctype} if data is not None else {})
        try:
            with self.op.open(r) as resp: return json.loads(resp.read())
        except urllib.error.HTTPError as e: return {'status': e.code, 'error': e.read().decode()}


class Windows(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dir = tempfile.mkdtemp(prefix='kks-win-e2e-')
        cls.port, cls.sport = free_port(), free_port()
        cfg = {'address': '127.0.0.1', 'port': cls.port, 'sync_port': cls.sport, 'plant_name': 'Test plant',
               'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(cls.dir, 'server.db'),
               'storage_key_file': os.path.join(cls.dir, 'storage.key'), 'plant_dir': os.path.join(cls.dir, 'plant-data'),
               'backup_dir': os.path.join(cls.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        with open(os.path.join(cls.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        cls.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(cls.dir, 'config.json')], cwd=cls.dir,
                                      stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = cls.server.stdout.readline()
            m = re.search(r'#setup=([A-Za-z0-9_-]+)', open(line.split('setup link file: ', 1)[1].strip()).read() if 'setup link file: ' in line else line)   # the link is in a 0600 file (#69)
            if m: setup = m[1]
            if 'server on' in line: break
        cls.boss = Client('http://127.0.0.1:%d' % cls.port)
        assert cls.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                                   'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert cls.boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = cls.boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        r = cls.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360],
                                                 'kks': '11LAB70AA501', 'isa': '', 'note': ''}})
        assert r.get('status') == 'approved', r
        vm('New-Item -ItemType Directory -Force C:\\kks | Out-Null; Get-Process Walkdown,uiadrive -ErrorAction SilentlyContinue | Stop-Process -Force')
        time.sleep(1)
        # a synthetic picture for the photo step (blue with a white square)
        photo = os.path.join(cls.dir, 'photo.jpg')
        subprocess.run([sys.executable, '-c', 'from PIL import Image, ImageDraw; im = Image.new("RGB", (1200, 900), (60, 90, 150)); '
                        'ImageDraw.Draw(im).rectangle([400, 300, 800, 600], fill=(240, 240, 240)); im.save(%r, quality=92)' % photo], check=True)
        put(APP, DRIVER, os.path.join(HERE, 'run.ps1'), os.path.join(HERE, 'runapp.ps1'), photo)
        if MSIX:
            put(MSIX, MSIX_CER, os.path.join(HERE, 'msix.ps1'))
            vm('Import-Certificate -FilePath C:\\kks\\%s -CertStoreLocation Cert:\\LocalMachine\\TrustedPeople | Out-Null'
               % os.path.basename(MSIX_CER))
            out = msix('-Add C:\\kks\\' + os.path.basename(MSIX))
            assert out.startswith('ok Walkdown_'), 'the MSIX did not install: ' + out

    @classmethod
    def tearDownClass(cls):
        vm('Get-Process Walkdown,uiadrive -ErrorAction SilentlyContinue | Stop-Process -Force')
        if MSIX:      # leave the VM as it was: no package, no trusted test certificate
            msix('-Remove')
            vm('$t = (New-Object Security.Cryptography.X509Certificates.X509Certificate2 C:\\kks\\%s).Thumbprint; '
               'Remove-Item Cert:\\LocalMachine\\TrustedPeople\\$t' % os.path.basename(MSIX_CER))
        cls.server.terminate()
        cls.server.wait(5)
        shutil.rmtree(cls.dir, ignore_errors=True)

    def wait_server(self, cond, what, tries=40):
        for _ in range(tries):
            v = cond()
            if v: return v
            time.sleep(0.5)
        self.fail(what)

    def check(self, name, lines, keep=True, sync_every=0, restart=False, env=None):
        ok, log = ui(name, lines, keep, sync_every, restart, env)
        self.assertTrue(ok, log)

    JOIN = ['click\tJoin through a server', 'set\tServer address\t%s:%d', 'set\tUsername\tboss',
            'set\tPassword\ta long password', 'click\tJoin', 'wait\t~Sample sheet\t60']

    def join(self, name, **kw):
        self.check(name, [l % (HOST, self.sport) if '%' in l else l for l in self.JOIN], keep=False, **kw)

    def leave(self):
        """the manager removes this VM's device on the server: test_flow finds the one it joins by its label"""
        host = vm('$env:COMPUTERNAME').strip().lower()
        for d in self.boss.req('GET', '/api/devices')['all']:
            if d['username'] == 'boss' and d['label'].lower() == host and not d['revoked']:
                self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})

    def test_dark_drawings(self):
        """Dark drawings: the check box turns the sheet light-on-dark at once (dark paper, light lines, as drawn on the
        screen), off restores it, and the choice survives a restart of the app (this device's store)"""
        self.join('djoin.uia')
        self.check('dark0.uia', ['state\tDark drawings\toff', 'shade\tDrawing\tlight', 'toggle\tDark drawings',
                                 'state\tDark drawings\ton', 'shade\tDrawing\tdark',
                                 'toggle\tDark drawings', 'shade\tDrawing\tlight', 'toggle\tDark drawings',
                                 'shade\tDrawing\tdark', 'sleep\t500'])
        # zoomed in: the vector tiles (Direct2D on the workers) are dark too
        self.check('dark1.uia', ['keys\tDrawing\t0x6B,0x6B,0x6B,0x6B,0x6B,0x6B', 'sleep\t1500', 'shade\tDrawing\tdark',
                                 'click\tFit the sheet (0)'])
        self.check('dark2.uia', ['wait\t~Sample sheet\t60', 'state\tDark drawings\ton', 'shade\tDrawing\tdark'],
                   restart=True)
        self.leave()

    def test_multi(self):
        """Select tags, then one place, one note and one photo for all of them (core /api/submit-many). Selecting: a box
        dragged on the drawing (one tag in it has no code: refused, said), search results (the keyboard's way) and a
        tag button of the drawing (a screen reader's way); one is turned off in the List; a cap (KKS_MAX_PICK)"""
        b = self.boss
        tags = {'11LAC10AP001': [600, 300, 720, 360], '11LAC10AP002': [800, 300, 920, 360],
                '11LAC10AP003': [600, 500, 720, 560], '11LAC20AA101': [800, 500, 920, 560], '': [960, 500, 1060, 560]}
        for k, bb in tags.items():
            r = b.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb, 'kks': k,
                                                                             'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        r = b.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAC10AP002',
                                          'changes': {'floor': '1', 'notes': 'Old note'}}})
        self.assertEqual(r.get('status'), 'approved', r)
        self.join('mjoin.uia', env={'KKS_MAX_PICK': '3'})
        def pick(code, n):
            return ['set\tSearch equipment by KKS code or description\t' + code[2:], 'select\t~' + code,
                    'click\tSelect or unselect', 'wait\t%d selected\t10' % n]
        self.check('multi0.uia', [
            'toggle\tSelect tags', 'state\tSelect tags\ton', 'wait\t0 selected\t10',
            # a box from 11LAC20AA101 over the unread tag next to it: the code is added, the unread one refused
            # the panel opened beside the drawing: the whole sheet again, so the unread tag is in view too
            'click\tFit the sheet (0)', 'wait\t~Unread tag, \t20',
            'wait\t~11LAC20AA101, \t20', 'boxdrag\tDrawing\t~11LAC20AA101, \t2.3\t1.1',
            'wait\t1 selected\t10', "wait\t~Tags without a code can't be selected: review them first\t10",
            'wait\t~, in the selection\t10'] +
            pick('11LAC10AP001', 2) + pick('11LAC10AP002', 3) + [
            # a fourth over the cap: not added, and said
            'set\tSearch equipment by KKS code or description\tLAC10AP003', 'select\t~11LAC10AP003',
            'click\tSelect or unselect', 'wait\t~At most 3 tags at once: send these first\t10', 'wait\t3 selected\t5',
            # a tag button of the drawing toggles too (off, then on again)
            'click\t~11LAC10AP001, ', 'wait\t2 selected\t10', 'click\t~11LAC10AP001, ', 'wait\t3 selected\t10',
            # the List: turn the box-selected code off
            'click\tList', 'wait\tSelected codes\t10', 'state\t~11LAC20AA101\ton', 'toggle\t~11LAC20AA101',
            'wait\t2 selected\t10', 'state\t~11LAC20AA101\toff', 'click\tClose the list', 'gone\tSelected codes',
            # Place for all: a floor; one of the two has another floor already, so the app asks first
            'click\tPlace for all…', 'wait\tPlace for all\t10', 'set\tFloor (0–10)\t3', 'click\tSend',
            'wait\t~1 of 2 already have a floor; it will be replaced.\t10', 'click\tOK',
            'wait\t~Sent for 2 codes · saved\t20', 'state\tSelect tags\toff'])
        want = {'11LAC10AP001': '3', '11LAC10AP002': '3', '11LAC10AP003': '', '11LAC20AA101': ''}
        def floors():
            eq = b.req('GET', '/api/state')['equipment']
            got = {k: eq.get(k, {}).get('floor', '') for k in want}
            return got if got == want else None
        self.wait_server(floors, 'the floors never reached the server: %s' % b.req('GET', '/api/state')['equipment'], tries=80)
        # Note for all: appended under each code's own note; Escape on the drawing ends the mode first, once
        self.check('multi1.uia', ['toggle\tSelect tags', 'wait\t0 selected\t10', 'keys\tDrawing\t0x1B',
                                  'state\tSelect tags\toff', 'toggle\tSelect tags', 'wait\t0 selected\t10'] +
                   pick('11LAC10AP002', 1) + pick('11LAC10AP003', 2) + [
                   'click\tNote for all…', 'wait\tNote for all\t10', 'set\tNote\tChecked on the walkdown', 'click\tSend',
                   'wait\t~Sent for 2 codes · saved\t20'])
        want2 = {'11LAC10AP002': 'Old note\nChecked on the walkdown', '11LAC10AP003': 'Checked on the walkdown',
                 '11LAC10AP001': ''}
        def notes():
            eq = b.req('GET', '/api/state')['equipment']
            got = {k: eq.get(k, {}).get('notes', '') for k in want2}
            return got if got == want2 else None
        self.wait_server(notes, 'the notes never reached the server', tries=80)
        # Photo for all needs every code's floor (the user's rule): refused while one has none, naming it; its floor
        # set with Place for all, then one picture through the mark-up editor, sent once for both codes
        self.check('multi2.uia', ['toggle\tSelect tags', 'wait\t0 selected\t10'] + pick('11LAC10AP001', 1) +
                   pick('11LAC10AP003', 2) + [
                   'click\tPhoto for all…', "wait\tA photo needs each code's floor. No floor yet: 11LAC10AP003. "
                   "Set it with Place for all first.\t20", 'gone\tPhoto to mark up', 'click\tDone',
                   'toggle\tSelect tags', 'wait\t0 selected\t10'] + pick('11LAC10AP003', 1) + [
                   'click\tPlace for all…', 'wait\tPlace for all\t10', 'set\tFloor (0–10)\t5', 'click\tSend',
                   'wait\t~Sent for 1 code · saved\t20',
                   'toggle\tSelect tags', 'wait\t0 selected\t10'] + pick('11LAC10AP001', 1) + pick('11LAC10AP003', 2) + [
                   'click\tPhoto for all…', 'wait\tPhoto to mark up\t30', 'set\tCaption (optional)\tBoth drains',
                   'click\tSend', 'wait\t~Sent for 2 codes · saved\t90'])
        def photos():
            ph = [p for p in b.req('GET', '/api/state').get('photos', []) if p.get('caption') == 'Both drains']
            ok = sorted(p['kks'] for p in ph) == ['11LAC10AP001', '11LAC10AP003'] and all(p.get('file') for p in ph)
            return ph if ok else None
        ph = self.wait_server(photos, 'the photos never reached the server', tries=80)
        self.assertEqual(len({p['file'] for p in ph}), 1, 'one image for both codes: %s' % ph)
        self.leave()

    def test_valve_type(self):
        """the valve type read from the drawing's symbol (tags.json "symbol", core valveTypeOf): shown as unchecked in
        the panel; Confirm sends the core's proposal as it is, and the panel then says confirmed"""
        fix = os.path.join(self.dir, 'valve-fixture')
        shutil.rmtree(fix, ignore_errors=True)
        shutil.copytree(os.path.join(self.dir, 'plant-data'), fix)
        tags = json.load(open(os.path.join(fix, 'tags.json')))
        tags.append({'id': 'sample:v1', 'sheet': 'sample', 'kks': '11LAB70AA777', 'suffix': '', 'isa': None,
                     'kind': 'equipment', 'status': 'auto', 'conf': 1, 'bbox': [800, 700, 920, 760],
                     'read': ['11LAB70', 'AA777'],
                     'symbol': {'type': 'gate valve', 'actuator': 'motor', 'nc': False, 'conf': 0.93,
                                'bbox': [800, 640, 920, 690]}})
        with open(os.path.join(fix, 'tags.json'), 'w') as f: json.dump(tags, f)
        r = subprocess.run([SERVER, 'publish-data', fix, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.join('vjoin.uia')
        self.check('valve.uia', ['set\tSearch equipment by KKS code or description\tLAB70AA777', 'select\t~11LAB70AA777',
                                 'click\tShow on the drawing',
                                 'wait\tValve type: gate valve, motor-operated (from the drawing, unchecked)\t20',
                                 'click\tConfirm valve type', 'wait\t~Saved: valve type of 11LAB70AA777\t20',
                                 'wait\tValve type: gate valve, motor-operated (confirmed)\t20', 'gone\tConfirm valve type'])
        def custom():
            c = self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA777', {}).get('custom', [])
            return c if c else None
        self.assertEqual(self.wait_server(custom, 'the valve type never reached the server', tries=80),
                         [{'k': 'Valve type', 'v': 'gate valve, motor-operated'}])
        self.leave()

    def add_tag(self, code, bb, floor=None):
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb, 'kks': code,
                                                                              'isa': '', 'note': ''}})
        self.assertEqual(r.get('status'), 'approved', r)
        if floor is not None:
            r = self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'changes': {'floor': floor}}})
            self.assertEqual(r.get('status'), 'approved', r)

    def show(self, code):
        """script lines: find a code by the search and open its panel"""
        return ['click\tDrawings', 'set\tSearch equipment by KKS code or description\t' + code[2:], 'select\t~' + code,
                'click\tShow on the drawing']

    def test_photo_queue(self):
        """photos are compressed on a worker thread through a queue, one after another, and sent as each is ready, while
        the panel closes; a photo that fails (KKS_TEST_ENCODE_FAIL: the first encode fails) is kept and reported, not
        dropped, and Try again sends it; closing the window while one is kept asks first"""
        self.add_tag('11LBA10AA101', [600, 900, 720, 960], floor='1')
        self.add_tag('11LBA10AA102', [800, 900, 920, 960], floor='1')
        self.join('qjoin.uia', env={'KKS_TEST_ENCODE_FAIL': '1'})
        self.check('queue0.uia', self.show('11LBA10AA101') + [
            'click\tAdd a photo from a file…', 'wait\tPhoto to mark up\t30', 'set\tCaption (optional)\tQueue A',
            'click\tSend', 'wait\tAnd its tag plate?\t20', 'click\tNo',
            'wait\t~The photo of 11LBA10AA101 could not be compressed\t30', 'wait\tPhotos not sent (1)…\t10',
            'wait\t~1 photo of this equipment not sent\t10',
            # closing the window now would lose it: the app asks, Cancel keeps it open
            'close\tPhotos not sent (1)…', 'wait\tClose Walkdown?\t10', 'click\tCancel', 'gone\tClose Walkdown?',
            'wait\tPhotos not sent (1)…\t10'])
        # another code's photo: compressed in the background while the panel closes, then sent
        self.check('queue1.uia', self.show('11LBA10AA102') + [
            'click\tAdd a photo from a file…', 'wait\tPhoto to mark up\t30', 'set\tCaption (optional)\tQueue B',
            'click\tSend', 'wait\t~Compressing 1 photo (11LBA10AA102)\t10', 'wait\tAnd its tag plate?\t20', 'click\tNo',
            'click\tClose', 'wait\t~Saved: photo of 11LBA10AA102\t90', 'gone\t~Compressing 1 photo'])
        # the kept one: Try again
        self.check('queue2.uia', ['click\tPhotos not sent (1)…', 'wait\tPhotos not sent\t10', 'wait\t~Could not be compressed\t10',
                                  'click\tTry again', 'wait\t~Saved: photo of 11LBA10AA101\t90',
                                  'wait\tEvery photo was sent or discarded.\t20', 'click\tClose'])
        def both():
            ph = {p['kks']: p for p in self.boss.req('GET', '/api/state').get('photos', []) if p.get('caption', '').startswith('Queue ')}
            return ph if set(ph) == {'11LBA10AA101', '11LBA10AA102'} else None
        ph = self.wait_server(both, 'the queued photos never reached the server', tries=80)
        self.assertEqual((ph['11LBA10AA101']['caption'], ph['11LBA10AA102']['caption']), ('Queue A', 'Queue B'))
        self.assertEqual(ph['11LBA10AA101'].get('by_name'), 'The Manager')
        self.leave()

    def test_description(self):
        """a drafted description (descriptions.json, core tagView.description) shows as unchecked; Confirm sends it as it
        is, Edit lets it be changed first; both become the custom field "Description", shown as confirmed by whom"""
        fix = os.path.join(self.dir, 'desc-fixture')
        shutil.rmtree(fix, ignore_errors=True)
        shutil.copytree(os.path.join(self.dir, 'plant-data'), fix)
        tags = json.load(open(os.path.join(fix, 'tags.json')))
        for i, code in enumerate(['11LAB70AA888', '11LAB70AA889']):
            tags.append({'id': 'sample:d%d' % i, 'sheet': 'sample', 'kks': code, 'suffix': '', 'isa': None,
                         'kind': 'equipment', 'status': 'auto', 'conf': 1, 'bbox': [1000 + 140 * i, 700, 1120 + 140 * i, 760],
                         'read': [code[:7], code[7:]]})
        with open(os.path.join(fix, 'tags.json'), 'w') as f: json.dump(tags, f)
        with open(os.path.join(fix, 'descriptions.json'), 'w') as f:
            json.dump({'11LAB70AA888': {'text': 'Feed water drain valve', 'basis': 'the sample sheet'},
                       '11LAB70AA889': 'Feed water vent valve'}, f)
        r = subprocess.run([SERVER, 'publish-data', fix, '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                           capture_output=True, text=True, timeout=60)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.join('descjoin.uia')
        self.check('desc0.uia', self.show('11LAB70AA888') + [
            'wait\tDraft description (unchecked)\t20', 'wait\tFeed water drain valve\t10', 'wait\tBasis: the sample sheet\t10',
            'click\tConfirm description', 'wait\t~Saved: description of 11LAB70AA888\t20',
            'wait\t~Confirmed by The Manager\t20', 'gone\tConfirm description'])
        self.check('desc1.uia', self.show('11LAB70AA889') + [
            'wait\tFeed water vent valve\t20', 'click\tEdit description', 'set\tDescription\tFeed water vent valve, DN25',
            'click\tSend description', 'wait\t~Saved: description of 11LAB70AA889\t20', 'wait\t~Confirmed by The Manager\t20',
            'wait\tFeed water vent valve, DN25\t10'])
        def descs():
            eq = self.boss.req('GET', '/api/state')['equipment']
            got = {k: [c['v'] for c in eq.get(k, {}).get('custom', []) if c.get('k') == 'Description'] for k in ('11LAB70AA888', '11LAB70AA889')}
            return got if all(got.values()) else None
        self.assertEqual(self.wait_server(descs, 'the descriptions never reached the server', tries=80),
                         {'11LAB70AA888': ['Feed water drain valve'], '11LAB70AA889': ['Feed water vent valve, DN25']})
        self.leave()

    def member(self, username, full_name):
        """a member on the server (web login)"""
        r = self.boss.req('POST', '/api/users', {'username': username, 'full_name': full_name, 'position': 'Technician', 'role': 'user'})
        c = Client(self.boss.base)
        c.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': username + ' password 1'})
        c.req('POST', '/api/login', {'username': username, 'password': username + ' password 1'})
        return c

    def test_approvals(self):
        """Approvals: one card per code, the proposals by kind; "Use this one" only where two equipment photos compete
        (a tag plate photo is no rival: Approve), the submitter's full name, the card opens its tag; then the
        Leaderboard counts what the member did"""
        self.add_tag('11LAC30AP001', [600, 1000, 720, 1060], floor='1')
        self.add_tag('11LAC30AP002', [800, 1000, 920, 1060], floor='1')
        omar = self.member('omar', 'Omar Fieldman')
        def jxl(name):
            with open(os.path.join(REPO, 'data', 'courses', name), 'rb') as f:
                return 'data:image/jxl;base64,' + base64.b64encode(f.read()).decode()
        for cap, pic in [('Pump front', 'ppt-07.jxl'), ('Pump side', 'ppt-12.jxl'), ('Tag plate', 'ppt-15.jxl')]:
            r = omar.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAC30AP001', 'caption': cap, 'dataUrl': jxl(pic)}})
            self.assertEqual(r.get('status'), 'pending', r)
        r = omar.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAC30AP002', 'changes': {'notes': 'Seal leaks'}}})
        self.assertEqual(r.get('status'), 'pending', r)
        self.join('ajoin.uia')
        self.check('appr0.uia', ['click\tManage', 'click\tApprovals', 'wait\t11LAC30AP001\t30',
                                 'wait\tOpen 11LAC30AP001 on the drawing\t10', 'wait\tEquipment photo (2)\t10',
                                 'wait\tTag plate photo\t10', 'wait\t~by Omar Fieldman · \t10', 'wait\t11LAC30AP002\t10',
                                 'click\tOpen 11LAC30AP001 on the drawing', 'value\tNumber\t001',
                                 'wait\tTag plate photo from a file…\t10', 'click\tClose',
                                 'click\tUse this one', 'wait\t~Photo chosen\t20', 'gone\tUse this one',
                                 'gone\tEquipment photo (2)', 'wait\tTag plate photo\t20'])
        def decided():
            subs = omar.req('GET', '/api/submissions?status=all')['submissions']
            got = sorted((s.get('payload', {}).get('caption', ''), s['status']) for s in subs if s['kind'] == 'photo')
            return got if [g[1] for g in got].count('pending') == 1 and 'approved' in [g[1] for g in got] else None
        got = self.wait_server(decided, 'the pick never reached the server', tries=80)
        self.assertEqual(sorted(st for _, st in got), ['approved', 'pending', 'rejected'], got)
        self.assertEqual([st for cap, st in got if cap == 'Tag plate'], ['pending'], 'the pick rejected the tag plate photo: %s' % got)
        # the tag plate photo and the notes: Approve each
        self.check('appr1.uia', ['click\tApprove', 'wait\t~Approved\t20', 'sleep\t1000', 'click\tApprove',
                                 'wait\tNothing waits for approval.\t30'])
        self.wait_server(lambda: not [s for s in omar.req('GET', '/api/submissions?status=all')['submissions'] if s['status'] == 'pending'],
                         'the approvals never reached the server', tries=80)
        # the Leaderboard: Omar, by name only, with his numbers
        self.check('board.uia', ['click\t‹ Manage', 'click\tLeaderboard', 'wait\t~. Omar Fieldman\t20',
                                 'wait\t3 approved · 0 waiting · 1 rejected · 4 in all · 75 % approved\t20',
                                 'wait\t~Equipment photos: 1 approved of 2, 1 rejected\t10'])
        self.leave()

    def test_position(self):
        """every new member needs a position (job title): the join form refuses without one and sends it with the join
        request (the admin sees it); a new plant needs the manager's too"""
        inv = self.boss.req('POST', '/api/invites', {})
        self.assertIn('code', inv, inv)
        token = inv['invite']['token']
        lines = ['click\tJoin with a code', 'set\tInvite text\t' + inv['code'], 'set\tYour username\tsara',
                 'set\tYour full name\tSara Engineer', 'click\tJoin with this code',
                 'wait\tFill in a username (2+ characters), your full name and your position (job title).\t10',
                 'set\tYour position (job title)\tI&C technician', 'click\tJoin with this code',
                 'wait\tWaiting for the admin to accept…\t60']
        self.check('pos0.uia', lines, keep=False)
        st = self.wait_server(lambda: (lambda x: x if x.get('state') == 'asked' else None)(self.boss.req('GET', '/api/invites/' + token)),
                              'the join request never reached the server', tries=80)
        self.assertEqual(st['request'].get('position'), 'I&C technician', st)
        self.assertFalse(st.get('needs_position'), st)
        self.assertTrue(self.boss.req('POST', '/api/invites/' + token, {'action': 'accept'}).get('ok'))
        self.check('pos1.uia', ['wait\t~Sample sheet\t60', 'click\tManage', 'click\tAccount',
                                'value\tPosition\tI&C technician'])
        sara = [u for u in self.boss.req('GET', '/api/users')['users'] if u.get('username') == 'sara']
        self.assertEqual([u.get('position') for u in sara], ['I&C technician'], sara)
        for d in self.boss.req('GET', '/api/devices')['all']:
            if d['username'] == 'sara' and not d['revoked']: self.boss.req('POST', '/api/devices/revoke', {'device': d['device']})
        # a new plant: the manager's position too
        self.check('pos2.uia', ['click\tStart a new plant', 'set\tPlant name\tPosition test plant', 'set\tYour username\tmona',
                                'set\tYour full name\tMona Manager', 'click\tCreate the plant',
                                'wait\tFill in the plant name, a username (2+ characters), your full name and your position (job title).\t10',
                                'set\tYour position (job title)\tShift engineer', 'click\tCreate the plant',
                                'wait\tManage\t30', 'click\tManage', 'click\tAccount', 'value\tPosition\tShift engineer'],
                   keep=False)

    def test_hidden(self):
        """removed devices hidden from the lists (a setting of this device): Clear removed, Show hidden (n), Show … again"""
        self.join('hjoin0.uia')
        self.leave()                     # this VM's device is removed …
        self.join('hjoin1.uia')          # … and joins again as a new one
        self.check('hide0.uia', ['click\tManage', 'click\tDevices', 'wait\t~ · removed\t30', 'click\tClear removed',
                                 'wait\t~Cleared \t20', 'gone\t~ · removed', 'click\t~Show hidden (',
                                 'wait\t~ · removed · hidden\t20', 'click\t~ again', 'wait\t~Shown again\t20',
                                 'click\tHide hidden', 'wait\t~ · removed\t20', 'gone\t~ · hidden'])
        self.leave()

    def test_scan_camera(self):
        """decision 0039: the scan window reads an invite through Media Foundation; KKS_CAMERA_FILE (run.ps1) plays a
        video of a QR code through the same Source Reader (the VMs have no camera)"""
        venv_py = os.path.join(REPO, '.venv', 'bin', 'python')
        if not os.path.exists(venv_py) or not shutil.which('ffmpeg'):
            self.skipTest('needs the importer .venv (OpenCV) and ffmpeg to make the QR video')
        invite = '{"kks_invite":1,"root":"TEST-ROOT","peer":"TESTPEER","addrs":["192.0.2.1:8421"],"token":"camera-test","plant":"Camera test"}'
        video = os.path.join(tempfile.gettempdir(), 'qr.mp4')
        subprocess.run([venv_py, os.path.join(REPO, 'apps', 'gnome', 'e2e', 'make_qr_video.py'), video, invite], check=True)
        put(video)
        self.check('scan.uia', ['click\tJoin with a code', 'click\tScan with the camera…',
                                'value\tInvite text\t"token":"camera-test"\t30'], keep=False)

    def test_courses(self):
        """the JSON courses (decision 0036): Learning lists them; a course window with its rail; a question answered
        (progress in the window title); a figure is a named window; RichEdit text is there"""
        # the program's own data next to the exe: data/courses (JSON + JPEG XL) and the course faces
        vm('New-Item -ItemType Directory -Force C:\\kks\\data\\courses, C:\\kks\\vendor\\fonts | Out-Null')
        cdir = os.path.join(REPO, 'data', 'courses')
        files = [os.path.join(cdir, f) for f in os.listdir(cdir) if f.endswith('.jxl') or f in ('ppt.json', 'fnd.json', 'hrsg.json')]
        subprocess.run(['scp', '-q'] + SSH + files + ['kks@%s:C:/kks/data/courses/' % VM], check=True, timeout=300)
        fdir = os.path.join(REPO, 'vendor', 'fonts')
        subprocess.run(['scp', '-q'] + SSH + [os.path.join(fdir, f) for f in os.listdir(fdir) if f.endswith('.woff2')] +
                       ['kks@%s:C:/kks/vendor/fonts/' % VM], check=True, timeout=300)
        self.check('cjoin.uia', ['click\tJoin through a server', 'set\tServer address\t%s:%d' % (HOST, self.sport),
                                 'set\tUsername\tboss', 'set\tPassword\ta long password', 'click\tJoin',
                                 'wait\t~Sample sheet\t60'], keep=False)
        self.check('course.uia', ['click\tLearning', 'select\t~Rumaila Plant Foundations', 'click\tOpen the course',
                                  'wait\t~Rumaila Plant Foundations — 0 of 76 solved\t30',
                                  'select\t1 · Combined cycle', 'click\tOpen the selected page', 'wait\tThe combined cycle. Combined cycle: gas turbine exhaust goes to the HRSG or bypass stack; HRSG steam drives the steam turbine; condensate returns\t20',
                                  'click\t~Once the gas cools below HP boiling temperature',
                                  'wait\t~Rumaila Plant Foundations — 1 of 76 solved\t20',
                                  'select\t6 · Valves & pumps', 'click\tOpen the selected page', 'wait\t~Gate valve cutaway.\t20',
                                  # pausing focuses the figure's button, which scrolls the figure into view; then play on
                                  'click\tPause', 'wait\tPlay\t10', 'click\tPlay', 'wait\tPause\t10', 'sleep\t1500'])
        shot = os.path.join(tempfile.gettempdir(), 'kks-win-course.ppm')
        dom = 'kks-win11' if VM.endswith('.20') else 'kks-win10'
        subprocess.run(['virsh', '-c', 'qemu:///system', 'screenshot', dom, shot], capture_output=True)
        self.leave()       # leave no device behind for test_flow (it finds this VM's device by its label)

    def test_systems_follows_sync(self):
        """Equipment by system follows a sync without a search, but never under the focus. Sync rounds every 3 s, in
        an app of its own: in the main flow such fast rounds rebuild the Manage pages under its clicks."""
        self.check('sysjoin.uia', ['click\tJoin through a server', 'set\tServer address\t%s:%d' % (HOST, self.sport),
                                   'set\tUsername\tboss', 'set\tPassword\ta long password', 'click\tJoin',
                                   'wait\t~Sample sheet\t60'], keep=False, sync_every=3000)
        # the sample sheet's one code, plus the tags other tests on this server marked by hand (test_multi)
        n = len({'11LAB70AA501'} | {t['kks'] + (t.get('suffix') or '') for t in self.boss.req('GET', '/api/state').get('added_tags', [])
                                    if t.get('kks')})
        on = lambda k: f'{k} code{"" if k == 1 else "s"} on the drawings'
        self.check('systems0.uia', ['click\tEquipment by system…', 'wait\tEquipment by system\t20',
                                    'wait\t%s\t20' % on(n)])
        # a code approved on the server appears without a search
        def add(code, bb):
            r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': bb,
                                                      'kks': code, 'isa': '', 'note': ''}})
            self.assertEqual(r.get('status'), 'approved', r)
        add('11PAB10AP001', [600, 700, 720, 760])
        self.check('systems1.uia', ['wait\t%s\t40' % on(n + 1), 'wait\t~PAB (1)\t10', 'focus\t~PAB (1)'])
        # but never under the focus: with the focus in the tree a sync only marks it stale; it is rebuilt once the
        # focus leaves the tree (here: to the search field)
        add('11PAB10AP002', [600, 800, 720, 860])
        time.sleep(10)          # three sync rounds
        self.check('systems2.uia', ['wait\t%s\t1' % on(n + 1), 'focus\tSearch codes, systems, descriptions',
                                    'wait\t%s\t15' % on(n + 2)])
        self.check('systems3.uia', ['keys\tSearch codes, systems, descriptions\t0x1B', 'gone\tEquipment by system'])

    def test_flow(self):
        # join through the server (PROTOCOL-v2 §16 enroll over Schannel)
        self.check('join.uia', ['click\tJoin through a server', 'set\tServer address\t%s:%d' % (HOST, self.sport),
                                'set\tUsername\tboss', 'set\tPassword\ta long password', 'click\tJoin',
                                'wait\t~Sample sheet\t60'], keep=False)
        # the drawing's tags are buttons for UI Automation (kks_uia.cpp): invoking one opens its panel
        self.check('tag.uia', ['wait\t~11LAB70AA501, \t30', 'click\t~11LAB70AA501, ', 'value\tSystem\tFeed water piping system',
                               'click\tClose', 'click\tFit the sheet (0)', 'wait\t~11LAB70AA501, \t10'])   # the whole sheet again
        # Equipment by system (core systemsView): a window with a search field and a native tree; a search opens every
        # level; Enter on a code (what a keyboard or screen-reader user does) opens its tag; Esc closes the window
        self.check('systems.uia', ['click\tEquipment by system…', 'wait\tEquipment by system\t20',
                                   'wait\t~LAB · Feed water piping system (\t20',
                                   'set\tSearch codes, systems, descriptions\tLAB70AA501', 'wait\t~ found\t20',
                                   'wait\t~LAB70 (\t20', 'wait\t~AA · \t20',
                                   'enter\t~11LAB70AA501 · Sample sheet\t20', 'value\tSystem\tFeed water piping system',
                                   'select\t~11LAB70AA501 · ', 'click\tShow the selected code on its drawing',
                                   'value\tSystem\tFeed water piping system',
                                   'keys\tSearch codes, systems, descriptions\t0x1B', 'gone\tEquipment by system'])
        # search → the panel decodes the tag; an edit reaches the server by the automatic sync
        note = 'Gland repacked (Windows %s)' % time.strftime('%H:%M:%S')
        self.check('panel.uia', ['set\tSearch equipment by KKS code or description\tLAB70AA501', 'select\t~11LAB70AA501',
                                 'click\tShow on the drawing', 'value\tSystem\tFeed water piping system', 'click\tEdit',
                                 'set\tNotes\t' + note, 'click\tSave', 'wait\t~Saved: 11LAB70AA501\t20'])
        got = self.wait_server(lambda: self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('notes'),
                               'the edit never reached the server')
        self.assertEqual(got, note)
        # a photo: the code has no floor, so the floor is asked first and sent with the photo (the user's rule); then
        # the annotation editor, a red box burned in, JPEG XL (the queue), synced; the app offers a tag plate photo
        self.check('photo.uia', ['click\tAdd a photo from a file…', 'wait\tWhich floor is 11LAB70AA501 on?\t20',
                                 'set\tFloor of 11LAB70AA501 (0–10)\t11', 'click\tContinue',
                                 'wait\tFloor: a whole number from 0 to 10 (the height goes in Elevation).\t10',
                                 'set\tFloor of 11LAB70AA501 (0–10)\t4', 'click\tContinue',
                                 'wait\tPhoto to mark up\t30', 'click\tBox',
                                 'drag\tPhoto to mark up\t0.2\t0.2\t0.8\t0.8',
                                 # a finger (injected touch: WM_POINTER), thick and yellow, zoomed in and back
                                 'click\tYellow', 'click\tThick lines', 'click\tZoom in', 'click\tFit',
                                 'touchdrag\tPhoto to mark up\t0.15\t0.92\t0.85\t0.92', 'set\tCaption (optional)\tValve from Windows',
                                 'click\tSend', 'wait\tAnd its tag plate?\t20', 'click\tNo',
                                 'wait\t~Saved: photo of 11LAB70AA501\t90'])
        self.assertEqual(self.wait_server(lambda: self.boss.req('GET', '/api/state')['equipment'].get('11LAB70AA501', {}).get('floor'),
                                          'the floor sent with the photo never reached the server'), '4')
        ph = self.wait_server(lambda: [p for p in self.boss.req('GET', '/api/state').get('photos', [])
                                       if p.get('kks') == '11LAB70AA501' and p.get('caption') == 'Valve from Windows'],
                              'the photo never reached the server', tries=80)
        def fetch_blob():   # the photo's entry can arrive before its file; until then its `file` is "": read it again
            f = [p for p in self.boss.req('GET', '/api/state').get('photos', [])
                 if p.get('kks') == '11LAB70AA501' and p.get('caption') == 'Valve from Windows'][0]['file']
            if not f: return None
            try: return self.boss.op.open(self.boss.base + '/photos/' + f).read()
            except urllib.error.HTTPError: return None
        blob = self.wait_server(fetch_blob, 'the photo file never reached the server', tries=80)
        self.assertEqual(blob[:2], b'\xff\x0a', 'not a JPEG XL codestream')
        if shutil.which('djxl'):
            jxl = os.path.join(self.dir, 'got.jxl')
            png = os.path.join(self.dir, 'got.png')
            with open(jxl, 'wb') as f: f.write(blob)
            subprocess.run(['djxl', jxl, png], check=True, capture_output=True)
            from PIL import Image
            im = Image.open(png).convert('RGB')
            reds = sum(1 for x in range(im.width) for y in range(0, im.height, 7)
                       if (lambda p: p[0] > 180 and p[1] < 90 and p[2] < 90)(im.getpixel((x, y))))
            self.assertGreater(reds, 50, 'no red box in the photo')
            yellows = sum(1 for x in range(im.width) for y in range(0, im.height, 3)
                          if (lambda p: p[0] > 200 and p[1] > 180 and p[2] < 90)(im.getpixel((x, y))))
            self.assertGreater(yellows, 50, 'the touch-drawn line is not in the photo')
        # a member proposes on the server; the manager approves in the app
        r = self.boss.req('POST', '/api/users', {'username': 'ali', 'full_name': 'Ali Member', 'position': 'Technician', 'role': 'user'})
        ali = Client(self.boss.base)
        ali.req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'ali password 1'})
        ali.req('POST', '/api/login', {'username': 'ali', 'password': 'ali password 1'})
        self.assertEqual(ali.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                         'changes': {'floor': '2'}, 'base': {'floor': '4'}}})['status'], 'pending')
        self.check('approve.uia', ['click\tManage', 'click\tAccount', 'click\tSync now', 'wait\t~Synced with 1 device\t30',
                                   'click\t‹ Manage', 'click\tApprovals', 'wait\tApprove\t30', 'click\tApprove',
                                   'wait\t~Approved'])
        self.wait_server(lambda: [s for s in ali.req('GET', '/api/submissions?status=all')['submissions'] if s['status'] == 'approved'],
                         'the approval never reached the server')
        # who took the photo and who set each field (/api/state photos[].by_name, equipment_by): the floor is Ali's
        # now, the notes and the photo the manager's
        self.check('who.uia', ['click\tDrawings', 'set\tSearch equipment by KKS code or description\tLAB70AA501', 'select\t~11LAB70AA501',
                               'click\tShow on the drawing', 'value\tFloor\t2', 'wait\t~by Ali Member, 20\t30',
                               'wait\t~by The Manager, 20\t10', 'wait\t~Open photo: Valve from Windows\t10'])
        # My proposals, filtered by the core (status, kind, field)
        self.check('mine.uia', ['click\tClose', 'click\tManage', 'click\tMy proposals',
                                'choose\tRejected', 'chosen\tRejected', 'wait\tNone of your proposals match.\t20',
                                'choose\tAll', 'chosen\tAll', 'choose\tFloor', 'chosen\tFloor', 'value\tFloor\t4',
                                'gone\t~New photo · 11LAB70AA501',
                                'choose\tEquipment photos', 'chosen\tEquipment photos', 'wait\t~New photo · 11LAB70AA501\t20',
                                'choose\tNotes', 'wait\t~Location and notes · 11LAB70AA501\t20', 'value\tNotes\tGland repacked',
                                'choose\tAll kinds', 'chosen\tAll kinds'])
        # deleting the photo sends its id (the Android bug: "bad photo id")
        self.check('delete.uia', ['click\tDrawings', 'set\tSearch equipment by KKS code or description\tLAB70AA501',
                                  'select\t~11LAB70AA501', 'click\tShow on the drawing', 'click\tDelete',
                                  'wait\tDelete this photo?\t10', 'click\tOK', 'wait\t~Saved: delete a photo\t20'])
        self.wait_server(lambda: not [p for p in self.boss.req('GET', '/api/state').get('photos', [])
                                      if p.get('caption') == 'Valve from Windows'], 'the photo was never deleted', tries=80)
        # the manager removes this device on the server; at its next sync it wipes itself and starts over
        devs = self.boss.req('GET', '/api/devices')['all']
        host = vm('$env:COMPUTERNAME').strip()
        mine = [d for d in devs if d['username'] == 'boss' and d['label'].lower() == host.lower() and not d['revoked']]
        self.assertEqual(len(mine), 1, (host, devs))
        self.assertTrue(self.boss.req('POST', '/api/devices/revoke', {'device': mine[0]['device']}).get('ok'))
        self.check('removed.uia', ['click\tManage', 'click\tAccount', 'click\tSync now',
                                   'wait\t~removed from the plant by The Manager\t60'])


if __name__ == '__main__':
    unittest.main()
