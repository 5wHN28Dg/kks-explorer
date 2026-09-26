#!/usr/bin/env python3
"""Build tests/fixtures/v1/ (plant.db + photos/): a database written by the pre-log server (commit 2d5fbdc), used
to test the one-time migration onto the signed log (server/migrate_v1.py, tests/test_migrate.py).

Runs the OLD server code (git archive 2d5fbdc) and drives it over HTTP through the flows that leave traces in the
old tables: approvals, conflicts forced, rejections, withdrawals, pending submissions, photo votes + pick, a
corrected tag mark, reviews, links on/off, a revert, an admin's held conflict and a deactivated account.
  python3 tools/make_v1_fixture.py"""
import base64, json, os, shutil, subprocess, sys, tempfile, threading, time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(REPO, 'tests', 'fixtures', 'v1')
COMMIT = '2d5fbdc'


def main():
    old = tempfile.mkdtemp()
    subprocess.run(f'git -C {REPO} archive {COMMIT} app.py server tests | tar -x -C {old}', shell=True, check=True)
    sys.path.insert(0, old)
    import app
    from server import config as config_mod
    from server.store import Store
    from server.auth import Auth
    from http.server import ThreadingHTTPServer
    from tests.test_server import Client

    work = tempfile.mkdtemp()
    os.makedirs(os.path.join(work, 'data'))
    for n in ('tags.json', 'sheets.json'):
        open(os.path.join(work, 'data', n), 'w').write('[]')
    cfgp = os.path.join(work, 'config.json')
    json.dump({'port': 0, 'data_dir': 'data', 'db': 'plant.db', 'photos_dir': 'photos', 'backup_dir': 'backups'}, open(cfgp, 'w'))
    cfg = config_mod.load(cfgp)
    os.makedirs(cfg['photos_dir'])
    store = Store(cfg)
    auth = Auth(store, cfg)
    httpd = ThreadingHTTPServer(('127.0.0.1', 0), app.make_handler(cfg, store, auth))
    cfg['port'] = httpd.server_address[1]
    threading.Thread(target=httpd.serve_forever, daemon=True).start()

    def ok(r, want=200):
        assert r[0] == want, r
        return r[1]

    def client():
        return Client(cfg['port'])

    m = client()
    ok(m.post('/api/setup', {'token': auth.make_token('setup', None, 3600), 'username': 'boss',
                             'password': 'correct horse', 'full_name': 'Hashim Boss', 'position': 'I&C Engineer'}))

    def invite(name, role='user', full=None):
        link = ok(m.post('/api/users', {'username': name, 'role': role, 'full_name': full or name.title() + ' Person'}))['link']
        u = client()
        ok(u.post('/api/password-reset', {'token': link.split('#reset=')[1], 'password': name + ' password!'}))
        return u

    adm, u1, u2, gone = invite('adm', 'admin'), invite('u1'), invite('u2'), invite('gone')
    k, k2 = '11LAB70AA501', '11LBA10AA402'
    sub = lambda c, kind, p, cid=None: ok(c.post('/api/submit', {'kind': kind, 'payload': p, **({'client_id': cid} if cid else {})}))
    subs = lambda: {s['id']: s for s in ok(m.get('/api/submissions?status=all'))['submissions']}

    sub(m, 'equipment', {'kks': k, 'changes': {'floor': '6 m', 'notes': 'n'}})
    a = sub(u1, 'equipment', {'kks': k, 'changes': {'floor': '10 m'}, 'base': {'floor': '6 m'}}, 'fixture-000001')
    b = sub(u2, 'equipment', {'kks': k, 'changes': {'notes': 'm'}, 'base': {'notes': 'n'}})
    c = sub(u2, 'equipment', {'kks': k, 'changes': {'floor': '14 m'}, 'base': {'floor': '6 m'}})
    time.sleep(1.1)
    ok(adm.post(f'/api/submissions/{a["id"]}/approve'))
    ok(m.post(f'/api/submissions/{b["id"]}/approve'))
    ok(m.post(f'/api/submissions/{c["id"]}/approve', {'force': True}))   # forced over the conflict
    sub(adm, 'equipment', {'kks': k2, 'changes': {'custom': [{'k': 'Size', 'v': 'DN50'}], 'loc': 'pump house'}})
    r = sub(u1, 'review', {'tag_id': 'hp:12', 'data': {'status': 'confirmed', 'kks': '11LAB90AA301', 'suffix': '', 'isa': ''}, 'base': None})
    ok(m.post(f'/api/submissions/{r["id"]}/approve'))
    sub(m, 'review', {'tag_id': 'lp:7', 'data': {'status': 'rejected'}, 'base': None})
    for step in (1, 2, 3):
        sub(m, 'link', {'proc': '3.6.1', 'step': step, 'kks': k})
    sub(m, 'link', {'proc': '3.6.1', 'step': 2, 'kks': k, 'on': False})
    lnk = sub(u2, 'link', {'proc': '3.6.1', 'step': 1, 'kks': k})   # already there: approving changes nothing
    ok(m.post(f'/api/submissions/{lnk["id"]}/approve'))
    time.sleep(1.1)
    jpeg = lambda n: 'data:image/jpeg;base64,' + base64.b64encode(b'\xff\xd8\xff\xe0' + bytes([n]) * 100).decode()
    p1 = sub(u1, 'photo', {'kks': k, 'dataUrl': jpeg(1), 'caption': 'from the stairs'})
    p2 = sub(u2, 'photo', {'kks': k, 'dataUrl': jpeg(2)})
    p3 = sub(u2, 'photo', {'kks': k2, 'dataUrl': jpeg(3)})
    ok(u2.post(f'/api/submissions/{p1["id"]}/vote'))
    ok(u1.post(f'/api/submissions/{p3["id"]}/vote'))           # stays open, with its vote
    ok(m.post(f'/api/submissions/{p1["id"]}/pick'))            # p2 rejected
    ok(u1.post(f'/api/submissions/{sub(u1, "link", {"proc": "4.1", "step": 1, "kks": k2})["id"]}/withdraw'))
    rj = sub(u1, 'equipment', {'kks': k2, 'changes': {'area': 'wrong'}, 'base': {}})
    ok(adm.post(f'/api/submissions/{rj["id"]}/reject', {'note': 'not this one'}))
    t = sub(u1, 'tag_add', {'sheet': 'hp', 'bbox': [100.5, 200, 180, 230.3], 'kks': '11LAB90CP502', 'isa': 'PI', 'note': 'missed'})
    ok(m.post(f'/api/submissions/{t["id"]}/approve', {'edit': {'kks': '11LAB90CP501', 'isa': 'PI'}}))
    sub(m, 'tag_add', {'sheet': 'lp', 'bbox': [10, 10, 60, 40], 'kks': ''})
    sub(u2, 'equipment', {'kks': k2, 'changes': {'near': 'tank'}, 'base': {}}, 'fixture-000002')   # stays pending
    time.sleep(1.1)
    sub(m, 'equipment', {'kks': k2, 'changes': {'loc': 'yard'}, 'base': {'loc': 'pump house'}})
    revs = ok(m.get('/api/revisions'))['revisions']
    last_loc = next(x['rev'] for x in revs if x['entity'] == 'equipment' and x['key'] == k2)
    ok(m.post(f'/api/revisions/{last_loc}/revert'))            # back to pump house
    held = sub(adm, 'equipment', {'kks': k, 'changes': {'notes': 'stale'}, 'base': {'notes': 'n'}})
    assert held['status'] == 'conflict', held                  # an admin's change held for a decision
    gid = next(u['id'] for u in ok(m.get('/api/users'))['users'] if u['username'] == 'gone')
    ok(m.post(f'/api/users/{gid}', {'active': False}))
    ids = sorted(subs())
    httpd.shutdown()
    httpd.server_close()

    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(OUT)
    import sqlite3
    src, dst = sqlite3.connect(cfg['db']), sqlite3.connect(os.path.join(OUT, 'plant.db'))
    src.backup(dst)
    dst.execute('DELETE FROM sessions'); dst.execute('DELETE FROM tokens'); dst.commit()
    dst.execute('VACUUM'); dst.close(); src.close()
    shutil.copytree(cfg['photos_dir'], os.path.join(OUT, 'photos'))
    print('wrote', OUT, 'submissions', ids, 'photos:', os.listdir(os.path.join(OUT, 'photos')))


if __name__ == '__main__':
    main()
