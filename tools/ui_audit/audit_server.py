"""A test server for the UI audit (synthetic data only): the manager, the sample sheet, a marked tag 11LAB70AA500 with
long and Arabic notes, a member with 20 open proposals (B1), a pending join-less user. Runs until killed; writes
the ports to OUT/server.json. Usage: python3 audit_server.py SERVER IMPORTER DIR [address]"""
import json, os, sys, time
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO + '/android/app2/e2e')
sys.argv, args = sys.argv[:1], sys.argv[1:]
sys.argv += ['x', 'x', 'x']          # test_app2 takes three paths off argv
import test_app2 as t  # noqa
SERVER, IMPORTER, DIR = args[:3]
ADDR = args[3] if len(args) > 3 else '127.0.0.1'
os.makedirs(DIR, exist_ok=True)
cfg = {'address': ADDR, 'plant_name': 'Test plant',
       'web_dir': REPO, 'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(DIR, 'server.db'),
       'storage_key_file': os.path.join(DIR, 'storage.key'), 'plant_dir': os.path.join(DIR, 'plant-data'),
       'backup_dir': os.path.join(DIR, 'backups'), 'importer': IMPORTER,
       'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
fresh = not os.path.exists(cfg['store'])
if not fresh:   # the same ports again (devices remember them)
    with open(os.path.join(DIR, 'server.json')) as f:
        old = json.load(f)
    cfg['port'], cfg['sync_port'] = old['port'], old['sync_port']
    proc, _ = t.start_server(SERVER, DIR, cfg, sync=True, fixed=True)
    print('restarted', proc.pid, flush=True)
    for line in proc.stdout: pass
    proc.wait()
    sys.exit()
proc, setup = t.start_server(SERVER, DIR, cfg, sync=True)
try:
    base = f'http://127.0.0.1:{cfg["port"]}'
    boss = t.Client(base)
    assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': 'a long password',
                                           'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
    with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f:
        assert boss.req('POST', '/api/sheets/import?id=sample&name=Sample%20sheet', raw=f.read(), ctype='application/pdf').get('ok')
    for _ in range(300):
        job = boss.req('GET', '/api/sheets/job')['job']
        if job['state'] != 'running':
            break
        time.sleep(0.2)
    assert job['state'] == 'done', job
except BaseException:
    proc.terminate()   # never leave the test server running after a failed setup
    raise
codes = ['11LAB70AA500'] + [f'11LAB70AA5{i:02d}' for i in range(2, 22)]
for i, c in enumerate(codes):
    x, y = 100 + (i % 7) * 140, 300 + (i // 7) * 90
    r = boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [x, y, x + 120, y + 60], 'kks': c, 'isa': '', 'note': ''}})
    assert r.get('status') == 'approved', r
long = ' '.join(['The valve sits behind the second pump skid, reached from the north stair; check the gland for leaks.'] * 6)
r = boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA500', 'changes': {
    'area': 'Feedwater pump house', 'floor': '2', 'elev': '+6.5 m', 'near': 'مضخة التغذية 11LAB70AA500 تعمل',
    'loc': long, 'notes': 'مضخة التغذية 11LAB70AA500 تعمل'}}})
print('equipment', r, flush=True)
mem = t.Client(base)
r = boss.req('POST', '/api/users', {'username': 'tala', 'full_name': 'تالا Member', 'position': 'Technician', 'role': 'user'})
t.Client(base).req('POST', '/api/password-reset', {'token': r['link'].split('#reset=')[1], 'password': 'tala password 1'})
mem.req('POST', '/api/login', {'username': 'tala', 'password': 'tala password 1'})
for c in codes[1:]:
    r = mem.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'near': 'by stair B'}, 'base': {'near': ''}}})
print('member proposals done', r, flush=True)
with open(os.path.join(DIR, 'server.json'), 'w') as f:
    json.dump({'port': cfg['port'], 'sync_port': cfg['sync_port'], 'pid': proc.pid}, f)
with open(os.path.join(DIR, 'config.json'), 'w') as f:
    json.dump(cfg, f)
print('ready', cfg['port'], cfg['sync_port'], proc.pid, flush=True)
for line in proc.stdout: pass
proc.wait()
