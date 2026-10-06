"""OTH-5: the server's memory after a scripted workload (budgets.json custom "server memory after the workload").
  python3 tools/budgets/server_mem.py SERVER IMPORTER OUT.json

Each run starts a fresh server (plant.py) and does, as the manager over HTTP:
- the plant: setup, the sample sheet imported by kks-import (a child process: not counted), one tag;
- 10 sign-ins (each an Argon2id hash);
- 20 photos (JPEG XL, the sample sheet's 50 KB overview level each time with a different caption);
- 100 equipment edits (approved at once: the manager);
- reads: /api/state 100 times, sheets.json, tags.json and every file of the sheet 20 times each, a bundle with photos
  5 times;
then idles 5 s and reads VmRSS. The median over the runs budgets.json states is compared."""
import base64, os, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import budgetlib, plant  # noqa: E402

NAME = 'server memory after the workload'
SERVER, IMPORTER, OUT = sys.argv[1:4]


def workload(p):
    c = p.client
    for _ in range(10):
        assert c.req('POST', '/api/login', {'username': plant.USER, 'password': plant.PASSWORD}).get('user')
    jxl = open(os.path.join(p.dir, 'plant-data', 'sheets', 'sample.o0.jxl'), 'rb').read()
    url = 'data:image/jxl;base64,' + base64.b64encode(jxl).decode()
    for i in range(20):
        r = c.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'caption': f'photo {i}',
                                                                          'dataUrl': url}})
        assert r.get('status') == 'approved', r
    for i in range(100):
        r = c.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': '11LAB70AA501',
                                                                            'changes': {'notes': f'edit {i}'},
                                                                            'base': {'notes': f'edit {i - 1}' if i else ''}}})
        assert r.get('status') == 'approved', r
    files = ['/data/sheets.json', '/data/tags.json'] + [
        '/data/sheets/' + f for f in sorted(os.listdir(os.path.join(p.dir, 'plant-data', 'sheets')))]
    for _ in range(100):
        assert 'equipment' in c.req('GET', '/api/state')
    for _ in range(20):
        for f in files:
            c.raw('GET', f)
    for _ in range(5):
        assert c.raw('GET', '/api/bundle?photos=1').startswith(b'\x1f\x8b')


def main():
    runs = budgetlib.runs_for('custom', NAME)
    mems, after_start = [], []
    for n in range(1, runs + 1):
        p = plant.Plant(SERVER, IMPORTER).start()
        try:
            after_start.append(round(p.rss_mb(), 1))
            workload(p)
            time.sleep(5)
            mems.append(round(p.rss_mb(), 1))
        finally:
            p.stop()
        print(f'run {n}: VmRSS {after_start[-1]} MB after the plant was set up, {mems[-1]} MB after the workload', flush=True)
    budgetlib.write(OUT, {f'custom[{NAME}]': (mems, 'MB')}, after_setup_mb=after_start,
                    where='CI ' + os.environ.get('ImageOS', 'local'))


main()
