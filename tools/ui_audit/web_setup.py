"""The web audit's setup, shared by audit_web.py and the probes: on import it starts the Nim server ($KKS_SERVER)
with the sample sheet ($KKS_IMPORTER) and makes the synthetic items (sys.argv[1] is the output folder)."""
import json, os, sys, time, urllib.parse, traceback
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'platform', 'linux', 'e2e'))
sys.path.insert(0, os.path.join(REPO, 'tests'))
from e2e_server import start_server  # noqa: E402
from test_web_v2 import Client, CSP_WATCH  # noqa: E402
from playwright.sync_api import sync_playwright  # noqa: E402
import tempfile, shutil  # noqa: E402

SERVER = os.environ['KKS_SERVER']; IMPORTER = os.environ['KKS_IMPORTER']
OUT = sys.argv[1]; ENGINES = sys.argv[2:] or ['chromium', 'webkit', 'firefox']
PW = 'a long password'; KKS = '11LAB70AA500'
ARABIC = 'مضخة التغذية 11LAB70AA500 تعمل'
MEASURE = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'measure.js')).read()
os.makedirs(OUT, exist_ok=True)
LOG = open(os.path.join(OUT, 'log.txt'), 'a')
def log(*a):
    s = ' '.join(str(x) for x in a); print(s, flush=True); LOG.write(s + '\n'); LOG.flush()

d = tempfile.mkdtemp(prefix='kks-uiaudit-web-', dir=os.environ.get('TMPDIR'))
cfg = {'address': '127.0.0.1', 'plant_name': 'Test plant', 'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'),
       'store': os.path.join(d, 'server.db'), 'storage_key_file': os.path.join(d, 'storage.key'),
       'plant_dir': os.path.join(d, 'plant-data'), 'backup_dir': os.path.join(d, 'backups'), 'importer': IMPORTER,
       'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
server, setup = start_server(SERVER, d, cfg, sync=True)
log('server pid', server.pid, 'port', cfg['port'])
BASE = 'http://127.0.0.1:%d' % cfg['port']
try:
    boss = Client(BASE)
    assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
    with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
    assert boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=pdf, ctype='application/pdf').get('ok')
    for _ in range(600):
        job = boss.req('GET', '/api/sheets/job')['job']
        if job['state'] != 'running': break
        time.sleep(0.2)
    assert job['state'] == 'done', job['log']
    def sub(c, body): return c.req('POST', '/api/submit', body).get('status')
    assert sub(boss, {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [400, 300, 520, 360], 'kks': KKS, 'isa': '', 'note': ''}}) == 'approved'
    custom = [{'k': 'Field %d' % i, 'v': 'Synthetic value number %d, long enough to wrap in the panel' % i} for i in range(1, 9)]
    assert sub(boss, {'kind': 'equipment', 'payload': {'kks': KKS, 'changes': {'area': 'Building A', 'floor': '2', 'near': 'Pump bay',
        'loc': 'Second platform, east side, behind the railing', 'notes': ARABIC, 'custom': custom}, 'base': {}}}) == 'approved'
    sub(boss, {'kind': 'link', 'payload': {'proc': 'EP-1', 'step': 1, 'kks': KKS, 'on': True}})
    # 20 tags without a code: the review queue on the drawings page
    for i in range(20):
        x = 100 + (i % 10) * 90; y = 500 + (i // 10) * 70
        sub(boss, {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [x, y, x + 70, y + 40], 'kks': '', 'isa': '', 'note': 'synthetic review item %d' % i}})
    # a user, tom, whose 20 marked tags wait for approval
    link = boss.req('POST', '/api/users', {'username': 'tom', 'full_name': 'Tom Tester', 'position': 'Technician', 'role': 'user'})['link']
    tom = Client(BASE); assert tom.req('POST', '/api/password-reset', {'token': link.split('#reset=')[1], 'password': PW}).get('ok')
    tom.req('POST', '/api/login', {'username': 'tom', 'password': PW})
    for i in range(20):
        x = 150 + (i % 10) * 95; y = 700 + (i // 10) * 70
        st = sub(tom, {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [x, y, x + 80, y + 40], 'kks': '11LAB80AA%03d' % (501 + i), 'isa': '', 'note': ''}})
    log('tom marks', st)
    # 20 sign-ups
    boss.req('POST', '/api/signup-code', {'code': 'synthetic-code-1'})
    for i in range(20):
        try:
            Client(BASE).req('POST', '/api/signup', {'code': 'synthetic-code-1', 'username': 'person%02d' % i, 'full_name': 'Person %02d' % i,
                                                     'position': 'Operator', 'password': 'a password for %02d' % i})
        except Exception as e:
            log('signup', i, e); break
    log('signups', len(boss.req('GET', '/api/signups')['requests']))
    log('open submissions', len(boss.req('GET', '/api/submissions?status=open')['submissions']))
except Exception:
    traceback.print_exc(); server.terminate(); raise

