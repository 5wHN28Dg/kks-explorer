"""A plant for the startup measurements (docs/m6/MEASUREMENTS.md "Startup, 2026-10-21"): the Nim server with no plant
data of ours, holding a log about the size of a real plant's.

  python3 tools/m6/startup_data.py SERVER IMPORTER FOLDER [SHEETS [TAGS [EDITS]]]

- SHEETS copies of importer/tests/vectors/kkp-sample.pdf (17, like a real plant's P&ID set);
- TAGS tags marked on them by the manager (2,600: a real plant's 2,673 drawing tags, here as log entries);
- EDITS approved equipment edits (1,500).
The server keeps running on FOLDER (its config.json) until this script is stopped; it prints the sync address, the
manager's username and password, and "ready" once everything is in. Apps then join with that account
(apps/gnome/e2e/startup_join.nim, or by hand)."""
import json, os, sys, time, urllib.request, http.cookiejar

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'tests'))
from e2e_server import start_server  # noqa: E402

PASSWORD = 'a long password'


class Client:
    def __init__(self, base):
        self.base = base
        self.op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def req(self, m, p, body=None, raw=None, ctype='application/json'):
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        r = urllib.request.Request(self.base + p, data=data, method=m,
                                   headers={'Content-Type': ctype} if data is not None else {})
        with self.op.open(r) as resp:
            return json.loads(resp.read())


def main():
    server, importer, folder = sys.argv[1:4]
    sheets = int(sys.argv[4]) if len(sys.argv) > 4 else 17
    tags = int(sys.argv[5]) if len(sys.argv) > 5 else 2600
    edits = int(sys.argv[6]) if len(sys.argv) > 6 else 1500
    os.makedirs(folder, exist_ok=True)
    cfg = {'address': '127.0.0.1', 'plant_name': 'Startup plant', 'web_dir': REPO,
           'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(folder, 'server.db'),
           'storage_key_file': os.path.join(folder, 'storage.key'), 'plant_dir': os.path.join(folder, 'plant-data'),
           'backup_dir': os.path.join(folder, 'backups'), 'importer': importer,
           'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
    proc, setup = start_server(server, folder, cfg, sync=True)
    try:
        boss = Client(f'http://127.0.0.1:{cfg["port"]}')
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PASSWORD,
                                               'full_name': 'The Manager', 'position': 'Plant manager'}).get('ok')
        pdf = open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb').read()
        for s in range(sheets):
            assert boss.req('POST', f'/api/sheets/import?id=s{s:02d}&name=Sheet%20{s + 1}', raw=pdf,
                            ctype='application/pdf').get('ok')
            for _ in range(600):
                job = boss.req('GET', '/api/sheets/job')['job']
                if job['state'] != 'running':
                    break
                time.sleep(0.2)
            assert job['state'] == 'done', job['log']
        t0 = time.time()
        for i in range(tags):
            x, y = 40 + (i % 40) * 60, 40 + (i // 40 % 40) * 40
            kks = f'1{i % 2}LA{"BCDE"[i % 4]}{i % 90 + 10:02d}AA{i % 900 + 100:03d}'
            r = boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {
                'sheet': f's{i % sheets:02d}', 'bbox': [x, y, x + 50, y + 25], 'kks': kks, 'isa': '', 'note': ''}})
            assert r.get('status') == 'approved', r
        live = {}                     # kks -> its fields now (an edit names what it changes from)
        for i in range(edits):
            kks = f'1{i % 2}LA{"BCDE"[i % 4]}{i % 90 + 10:02d}AA{i % 900 + 100:03d}'
            changes = {'notes': f'checked on round {i}', 'floor': str(i % 5)}
            r = boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {
                'kks': kks, 'changes': changes, 'base': live.get(kks, {})}})
            assert r.get('status') == 'approved', r
            live[kks] = changes
        print(f'log written in {time.time() - t0:.0f} s', flush=True)
        print(f'sync 127.0.0.1:{cfg["sync_port"]} user boss password {PASSWORD!r}', flush=True)
        print('ready', flush=True)
        while proc.poll() is None:
            time.sleep(1)
    finally:
        if proc.poll() is None:
            proc.terminate()
            proc.wait(10)


if __name__ == '__main__':
    main()
