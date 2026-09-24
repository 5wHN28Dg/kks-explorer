"""End-to-end tests for the server: python3 -m unittest discover -s tests"""
import base64, http.client, json, os, re, shutil, sys, tempfile, threading, unittest
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import app
from server import config as config_mod
from server.store import Store, restore
from server.auth import Auth

JPEG = base64.b64encode(b'\xff\xd8\xff\xe0' + b'0' * 100).decode()


class Client:
    def __init__(self, port):
        self.port, self.cookie = port, None

    def req(self, method, path, body=None, headers=None):
        c = http.client.HTTPConnection('127.0.0.1', self.port, timeout=10)
        h = {'Content-Type': 'application/json', **(headers or {})}
        if self.cookie:
            h['Cookie'] = self.cookie
        c.request(method, path, json.dumps(body) if body is not None else None, h)
        r = c.getresponse()
        data = r.read()
        sc = r.getheader('Set-Cookie')
        if sc:
            m = re.match(r'kks_session=([^;]*)', sc)
            self.cookie = f'kks_session={m[1]}' if m and m[1] else None
        c.close()
        try:
            return r.status, json.loads(data)
        except ValueError:
            return r.status, data

    def get(self, p): return self.req('GET', p)
    def post(self, p, b=None, **kw): return self.req('POST', p, b if b is not None else {}, **kw)


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        data = os.path.join(self.tmp, 'data')
        os.makedirs(data)
        for name in ('tags.json', 'sheets.json'):
            with open(os.path.join(data, name), 'w') as f:
                f.write('[]')
        cfgp = os.path.join(self.tmp, 'config.json')
        with open(cfgp, 'w') as f:
            json.dump({'port': 0, 'data_dir': 'data', 'db': 'plant.db', 'photos_dir': 'photos', 'backup_dir': 'backups',
                       'snapshot_every': 5}, f)
        self.cfg = config_mod.load(cfgp)
        os.makedirs(self.cfg['photos_dir'])
        self.store = Store(self.cfg)
        self.auth = Auth(self.store, self.cfg)
        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), app.make_handler(self.cfg, self.store, self.auth))
        self.cfg['port'] = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.anon = Client(self.cfg['port'])

    def tearDown(self):
        self.httpd.shutdown(); self.httpd.server_close()
        shutil.rmtree(self.tmp)

    def client(self):
        return Client(self.cfg['port'])

    def setup_manager(self):
        tok = self.auth.make_token('setup', None, 3600)
        m = self.client()
        s, r = m.post('/api/setup', {'token': tok, 'username': 'boss', 'password': 'correct horse'})
        self.assertEqual(s, 200, r)
        return m

    def invite(self, by, name, role='user'):
        s, r = by.post('/api/users', {'username': name, 'role': role})
        self.assertEqual(s, 200, r)
        tok = r['link'].split('#reset=')[1]
        u = self.client()
        s, r = u.post('/api/password-reset', {'token': tok, 'password': name + ' password!'})
        self.assertEqual(s, 200, r)
        return u

    # ---------- access ----------
    def test_public_vs_private(self):
        self.assertEqual(self.anon.get('/')[0], 200)
        self.assertEqual(self.anon.get('/api/config')[1]['setup_needed'], True)
        for p in ('/data/tags.json', '/api/state', '/photos/x.jpg', '/api/users'):
            self.assertEqual(self.anon.get(p)[0], 401, p)
        m = self.setup_manager()
        self.assertEqual(m.get('/data/tags.json')[0], 200)
        self.assertEqual(m.req('GET', '/data/../plant.db')[0] in (400, 404), True)
        self.assertEqual(self.anon.get('/api/config')[1]['setup_needed'], False)

    def test_setup_token_single_use_and_one_manager(self):
        tok = self.auth.make_token('setup', None, 3600)
        a, b = self.client(), self.client()
        self.assertEqual(a.post('/api/setup', {'token': tok, 'username': 'a1', 'password': 'x' * 12})[0], 200)
        self.assertEqual(b.post('/api/setup', {'token': tok, 'username': 'b1', 'password': 'x' * 12})[0], 403)
        tok2 = self.auth.make_token('setup', None, 3600)  # even a fresh token can't make a second manager
        self.assertEqual(b.post('/api/setup', {'token': tok2, 'username': 'b1', 'password': 'x' * 12})[0], 403)

    def test_csrf_and_content_type(self):
        m = self.setup_manager()
        self.assertEqual(m.post('/api/users', {'username': 'x1'}, headers={'Origin': 'http://evil.example'})[0], 403)
        self.assertEqual(m.req('POST', '/api/users', None, {'Content-Type': 'text/plain'})[0], 415)

    def test_proxy_origin(self):
        m = self.setup_manager()
        self.cfg['public_url'] = 'https://kks.example.ts.net'
        self.assertEqual(m.post('/api/users', {'username': 'p1'}, headers={'Origin': 'https://kks.example.ts.net'})[0], 200)

    def test_hsts_only_with_https_public_url(self):
        def hsts():
            c = http.client.HTTPConnection('127.0.0.1', self.cfg['port'], timeout=10)
            c.request('GET', '/api/config'); r = c.getresponse(); r.read(); c.close()
            return r.getheader('Strict-Transport-Security')
        self.assertIsNone(hsts())
        self.cfg['public_url'] = 'https://kks.example.com'
        self.assertEqual(hsts(), 'max-age=31536000')

    def test_check_command(self):
        from server import check
        fails = lambda: [m for lvl, m in check.run(self.cfg, self.store, self.auth) if lvl == 'FAIL']
        self.cfg.update(public_url='https://kks.example.com', host='0.0.0.0', secure_cookies=False)
        f = fails()
        self.assertTrue(any('bypassing Cloudflare' in m for m in f), f)
        self.assertTrue(any('secure_cookies' in m for m in f), f)
        self.assertTrue(any('manager' in m for m in f), f)
        self.setup_manager()
        self.cfg.update(host='127.0.0.1', secure_cookies=True)
        if not any(os.path.exists(p) for p in check.CLOUDFLARED_CONFIGS):
            self.assertEqual(fails(), [])

    def test_login_throttle(self):
        self.setup_manager()
        c = self.client()
        for _ in range(5):
            self.assertEqual(c.post('/api/login', {'username': 'boss', 'password': 'wrong'})[0], 401)
        s, r = c.post('/api/login', {'username': 'boss', 'password': 'correct horse'})
        self.assertEqual(s, 401); self.assertIn('Too many', r['error'])

    # ---------- roles ----------
    def test_role_rules(self):
        m = self.setup_manager()
        adm = self.invite(m, 'adm', 'admin')
        usr = self.invite(adm, 'usr')
        self.assertEqual(adm.post('/api/users', {'username': 'adm2', 'role': 'admin'})[0], 403)  # admins can't make admins
        self.assertEqual(usr.post('/api/users', {'username': 'x2'})[0], 403)
        self.assertEqual(usr.get('/api/users')[0], 403)
        users = {u['username']: u for u in m.get('/api/users')[1]['users']}
        self.assertEqual(adm.post(f'/api/users/{users["boss"]["id"]}', {'active': False})[0], 403)
        self.assertEqual(adm.post(f'/api/users/{users["usr"]["id"]}', {'role': 'admin'})[0], 403)
        # deactivating logs the user out immediately
        self.assertEqual(adm.post(f'/api/users/{users["usr"]["id"]}', {'active': False})[0], 200)
        self.assertEqual(usr.get('/api/state')[0], 401)

    def test_manager_transfer(self):
        m = self.setup_manager()
        adm = self.invite(m, 'adm', 'admin')
        self.assertEqual(m.post('/api/manager/transfer', {'username': 'adm', 'password': 'nope'})[0], 403)
        self.assertEqual(m.post('/api/manager/transfer', {'username': 'adm', 'password': 'correct horse'})[0], 200)
        self.assertTrue(adm.get('/api/me')[1]['transfer_offer'])
        self.assertEqual(adm.post('/api/manager/accept')[0], 200)
        roles = {u['username']: u['role'] for u in adm.get('/api/users')[1]['users']}
        self.assertEqual(roles, {'boss': 'admin', 'adm': 'manager'})

    def test_cli_reset_manager(self):
        m = self.setup_manager()
        self.invite(m, 'adm', 'admin')
        os.environ['KKS_CONFIG'] = self.cfg['config_path']
        try:
            app.main(['reset-manager', '--user', 'adm'])
        finally:
            del os.environ['KKS_CONFIG']
        roles = {u['username']: u['role'] for u in m.get('/api/users')[1]['users']}
        self.assertEqual(roles, {'boss': 'admin', 'adm': 'manager'})

    # ---------- submissions ----------
    def test_user_submission_needs_approval(self):
        m = self.setup_manager()
        u = self.invite(m, 'usr')
        s, r = u.post('/api/submit', {'kind': 'equipment', 'client_id': 'c-000001',
                                      'payload': {'kks': '11LAB70AA501', 'changes': {'floor': '6 m'}, 'base': {}}})
        self.assertEqual(r['status'], 'pending')
        self.assertEqual(u.get('/api/state')[1]['equipment'], {})
        self.assertEqual(len(u.get('/api/state')[1]['mine']), 1)
        # offline replay of the same client_id is not duplicated
        self.assertTrue(u.post('/api/submit', {'kind': 'equipment', 'client_id': 'c-000001',
                                               'payload': {'kks': '11LAB70AA501', 'changes': {'floor': '6 m'}}})[1]['duplicate'])
        q = m.get('/api/submissions')[1]['submissions']
        self.assertEqual(len(q), 1)
        self.assertEqual(m.post(f'/api/submissions/{q[0]["id"]}/approve')[0], 200)
        self.assertEqual(u.get('/api/state')[1]['equipment'], {'11LAB70AA501': {'floor': '6 m'}})
        self.assertEqual(m.post(f'/api/submissions/{q[0]["id"]}/approve')[0], 409)  # already decided

    def test_admin_applies_directly(self):
        m = self.setup_manager()
        s, r = m.post('/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 2, 'kks': '11QEA10AN001'}})
        self.assertEqual(r['status'], 'approved')
        self.assertEqual(len(m.get('/api/state')[1]['links']), 1)

    def test_field_merge_and_conflict(self):
        m = self.setup_manager()
        u1, u2 = self.invite(m, 'u1'), self.invite(m, 'u2')
        k = '11LAB70AA501'
        m.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'floor': '6 m', 'notes': 'n'}}})
        # both users saw floor=6 m, notes=n. u1 edits floor, u2 edits notes → no overlap → both merge
        u1.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'floor': '10 m'}, 'base': {'floor': '6 m'}}})
        u2.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'notes': 'm'}, 'base': {'notes': 'n'}}})
        # u2 also changes floor based on the stale value → conflicts after u1's is approved
        u2.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'floor': '14 m'}, 'base': {'floor': '6 m'}}})
        subs = sorted(m.get('/api/submissions')[1]['submissions'], key=lambda s: s['id'])
        for s in subs[:2]:
            self.assertEqual(m.post(f'/api/submissions/{s["id"]}/approve')[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment'][k], {'floor': '10 m', 'notes': 'm'})
        s, r = m.post(f'/api/submissions/{subs[2]["id"]}/approve')
        self.assertEqual(s, 409); self.assertEqual(r['conflicts'][0]['live'], '10 m')
        self.assertEqual(m.post(f'/api/submissions/{subs[2]["id"]}/approve', {'force': True})[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment'][k]['floor'], '14 m')

    def test_photo_votes_and_pick(self):
        m = self.setup_manager()
        u1, u2 = self.invite(m, 'u1'), self.invite(m, 'u2')
        ids = []
        for u in (u1, u2):
            s, r = u.post('/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'dataUrl': 'data:image/jpeg;base64,' + JPEG}})
            self.assertEqual(r['status'], 'pending', r); ids.append(r['id'])
        self.assertEqual(u1.post(f'/api/submissions/{ids[1]}/vote')[0], 200)
        seen = {s['id']: s for s in u1.get('/api/submissions')[1]['submissions']}
        self.assertEqual(seen[ids[1]]['votes'], 1)  # users see others' photo proposals to vote on them
        self.assertEqual(u1.post(f'/api/submissions/{ids[1]}/pick')[0], 403)
        s, r = m.post(f'/api/submissions/{ids[1]}/pick')
        self.assertEqual((s, r['rejected']), (200, 1))
        st = m.get('/api/state')[1]
        self.assertEqual(len(st['photos']), 1)
        self.assertEqual(m.get('/photos/' + st['photos'][0]['file'])[0], 200)
        self.assertEqual(u1.post('/api/submit', {'kind': 'photo', 'payload': {'kks': '11X', 'dataUrl': 'data:image/png;base64,' + base64.b64encode(b'<svg>').decode()}})[0], 400)

    # ---------- history / backups ----------
    def test_revert_and_restore(self):
        m = self.setup_manager()
        k = '11LAB70AA501'
        for f in ('3 m', '6 m', '10 m'):
            m.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'floor': f},
                                                                    'base': {'floor': m.get('/api/state')[1]['equipment'].get(k, {}).get('floor', '')}}})
        revs = [r for r in m.get('/api/revisions')[1]['revisions'] if r['entity'] == 'equipment']
        self.assertEqual(len(revs), 3)
        first = min(r['rev'] for r in revs)
        # reverting an old revision whose entity changed later is a conflict unless forced
        self.assertEqual(m.post(f'/api/revisions/{first}/revert')[0], 409)
        self.assertEqual(m.post('/api/restore', {})[0], 400)  # no silent restore-everything default
        self.assertEqual(m.post('/api/restore', {'rev': first})[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment'][k]['floor'], '3 m')
        self.assertEqual(m.post('/api/restore', {'rev': 0})[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment'], {})

    def test_backup_restore_roundtrip(self):
        m = self.setup_manager()
        for i in range(12):  # crosses snapshot_every=5 a few times
            m.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': i, 'kks': '11AAA10AA001'}})
        m.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': 3, 'kks': '11AAA10AA001', 'on': False}})
        live = sorted(r['step'] for r in m.get('/api/state')[1]['links'])
        out = os.path.join(self.tmp, 'restored.db')
        restore(self.cfg, out)
        import sqlite3
        c = sqlite3.connect(out)
        self.assertEqual(sorted(r[0] for r in c.execute('SELECT step FROM links')), live)
        self.assertEqual(c.execute('SELECT COUNT(*) FROM users').fetchone()[0], 1)
        c.close()
        with self.assertRaises(SystemExit):
            restore(self.cfg, out)  # never overwrites


if __name__ == '__main__':
    unittest.main()
