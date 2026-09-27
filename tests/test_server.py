"""End-to-end tests for the server: python3 -m unittest discover -s tests"""
import base64, http.client, json, os, re, shutil, sys, tempfile, threading, unittest
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import app
from server import config as config_mod
from server.store import Store, restore
from server.auth import Auth
from server.engine import Engine

JPEG = ('/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAAQABADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDyrSfDv3fk/Suz0nw70+T9K7HSfDv3fk/Suz0nw7935P0rXHZ5vqLhXiP4dT//2Q==')   # a real 16x16 JPEG: photos are decoded (and kept as JPEG XL when server/photos.py can)


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


class Base(unittest.TestCase):
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
        self.E = Engine(self.store, self.cfg)
        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), app.make_handler(self.cfg, self.store, self.auth, self.E))
        self.cfg['port'] = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.anon = Client(self.cfg['port'])

    def tearDown(self):
        self.httpd.shutdown(); self.httpd.server_close()
        # the server never writes an entry the replay would ignore, and a fresh replay gives the same state
        self.E.refresh()
        self.assertEqual(self.E.run.ignored, {})
        self.assertEqual(Engine(self.store, self.cfg).run.state(), self.E.run.state())
        shutil.rmtree(self.tmp)

    def client(self):
        return Client(self.cfg['port'])

    def setup_manager(self):
        tok = self.auth.make_token('setup', None, 3600)
        m = self.client()
        s, r = m.post('/api/setup', {'token': tok, 'username': 'boss', 'password': 'correct horse', 'full_name': 'Hashim Boss'})
        self.assertEqual(s, 200, r)
        return m

    def invite(self, by, name, role='user'):
        s, r = by.post('/api/users', {'username': name, 'role': role, 'full_name': name.title() + ' Person'})
        self.assertEqual(s, 200, r)
        tok = r['link'].split('#reset=')[1]
        u = self.client()
        s, r = u.post('/api/password-reset', {'token': tok, 'password': name + ' password!'})
        self.assertEqual(s, 200, r)
        return u

class ServerTest(Base):
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
        self.assertEqual(a.post('/api/setup', {'token': tok, 'username': 'a1', 'password': 'x' * 12})[0], 400)  # full name required
        self.assertEqual(a.post('/api/setup', {'token': tok, 'username': 'a1', 'password': 'x' * 12, 'full_name': 'A One'})[0], 200)
        self.assertEqual(b.post('/api/setup', {'token': tok, 'username': 'b1', 'password': 'x' * 12, 'full_name': 'B One'})[0], 403)
        tok2 = self.auth.make_token('setup', None, 3600)  # even a fresh token can't make a second manager
        self.assertEqual(b.post('/api/setup', {'token': tok2, 'username': 'b1', 'password': 'x' * 12, 'full_name': 'B Two'})[0], 403)

    def test_csrf_and_content_type(self):
        m = self.setup_manager()
        self.assertEqual(m.post('/api/users', {'username': 'x1'}, headers={'Origin': 'http://evil.example'})[0], 403)
        self.assertEqual(m.req('POST', '/api/users', None, {'Content-Type': 'text/plain'})[0], 415)

    def test_proxy_origin(self):
        m = self.setup_manager()
        self.cfg['public_url'] = 'https://kks.example.ts.net'
        self.assertEqual(m.post('/api/users', {'username': 'p1', 'full_name': 'Proxy User'}, headers={'Origin': 'https://kks.example.ts.net'})[0], 200)

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

    def test_full_name_and_position(self):
        m = self.setup_manager()
        self.assertEqual(m.post('/api/users', {'username': 'noname'})[0], 400)  # full name is required
        s, r = m.post('/api/users', {'username': 'ali', 'full_name': '  Ali   Hassan ', 'position': 'I&C Technician'})
        self.assertEqual(s, 200, r)
        adm = self.invite(m, 'adm', 'admin')
        users = {u['username']: u for u in m.get('/api/users')[1]['users']}
        self.assertEqual((users['ali']['full_name'], users['ali']['position']), ('Ali Hassan', 'I&C Technician'))
        self.assertEqual(users['boss']['full_name'], 'Hashim Boss')
        # everyone edits their own details; admins edit users' details, not the manager's
        self.assertEqual(adm.post('/api/profile', {'full_name': 'Adm Person', 'position': 'Shift supervisor'})[0], 200)
        self.assertEqual(adm.get('/api/me')[1]['user']['position'], 'Shift supervisor')
        self.assertEqual(adm.post('/api/profile', {'full_name': ''})[0], 400)
        self.assertEqual(adm.post(f'/api/users/{users["ali"]["id"]}', {'position': 'Senior technician'})[0], 200)
        self.assertEqual(adm.post(f'/api/users/{users["boss"]["id"]}', {'full_name': 'X'})[0], 403)
        users = {u['username']: u for u in m.get('/api/users')[1]['users']}
        self.assertEqual((users['ali']['full_name'], users['ali']['position']), ('Ali Hassan', 'Senior technician'))
        # submissions and history show the person's name
        adm.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': 1, 'kks': '11AAA10AA001'}})
        self.assertEqual(m.get('/api/submissions?status=all')[1]['submissions'][0]['by_name'], 'Adm Person')
        self.assertIn('Adm Person', [r['full_name'] for r in m.get('/api/revisions')[1]['revisions']])

    def test_old_database_gets_new_columns(self):
        import sqlite3
        from server import store as store_mod
        old = os.path.join(self.tmp, 'old.db')
        c = sqlite3.connect(old)
        c.execute('CREATE TABLE users(id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, pw TEXT, '
                  "role TEXT NOT NULL CHECK(role IN ('manager','admin','user')), active INTEGER NOT NULL DEFAULT 1, created INTEGER)")
        c.execute("INSERT INTO users(username, role) VALUES ('kept', 'user')"); c.commit(); c.close()
        cfg = dict(self.cfg, db=old, backup_dir=os.path.join(self.tmp, 'b2'))
        st = store_mod.Store(cfg); c = st.conn()
        self.assertEqual(c.execute("SELECT username, full_name FROM users").fetchall()[0][:], ('kept', None))
        c.close()
        # restore: a snapshot from before the upgrade + journal rows that carry the new columns
        with st.write():
            st.put('users', {'username': 'new', 'role': 'user', 'active': 1, 'full_name': 'New Person', 'position': None})
        snaps = st.snapshots()
        oldest = snaps[0][1]
        c = sqlite3.connect(oldest); c.execute('CREATE TABLE u2 AS SELECT id,username,pw,role,active,created FROM users')
        c.execute('DROP TABLE users'); c.execute('ALTER TABLE u2 RENAME TO users'); c.commit(); c.close()
        out = os.path.join(self.tmp, 'r.db'); store_mod.restore(cfg, out)
        c = sqlite3.connect(out)
        self.assertIn(('new', 'New Person'), c.execute('SELECT username, full_name FROM users').fetchall()); c.close()

    def test_manager_transfer(self):
        m = self.setup_manager()
        adm = self.invite(m, 'adm', 'admin')
        self.assertEqual(m.post('/api/manager/transfer', {'username': 'adm', 'password': 'nope'})[0], 403)
        self.assertEqual(m.post('/api/manager/transfer', {'username': 'adm', 'password': 'correct horse'})[0], 200)
        self.assertTrue(adm.get('/api/me')[1]['transfer_offer'])
        self.assertEqual(adm.post('/api/manager/accept')[0], 200)
        roles = {u['username']: u['role'] for u in adm.get('/api/users')[1]['users']}
        self.assertEqual(roles, {'boss': 'admin', 'adm': 'manager'})
        self.assertEqual(self.E.run.persons[self.E.run.manager]['username'], 'adm')   # signed by the root key

    def test_transfer_needs_root_key(self):
        m = self.setup_manager()
        self.invite(m, 'adm', 'admin')
        os.rename(self.E.root_path, self.E.root_path + '.away')
        s, r = m.post('/api/manager/transfer', {'username': 'adm', 'password': 'correct horse'})
        self.assertEqual(s, 409); self.assertIn('root key', r['error'])
        os.rename(self.E.root_path + '.away', self.E.root_path)

    def test_root_key_backup(self):
        self.setup_manager()
        text = self.E.export_root('a long passphrase')
        self.assertNotIn(open(self.E.root_path).read().strip(), text)
        os.remove(self.E.root_path)
        with self.assertRaises(Exception):
            self.E.import_root(text, 'wrong passphrase!')
        self.E.import_root(text, 'a long passphrase')
        if os.name != 'nt':
            self.assertEqual(oct(os.stat(self.E.root_path).st_mode & 0o777), '0o600')
        self.E.root_key()

    def test_deactivate_revokes_the_key(self):
        m = self.setup_manager()
        u = self.invite(m, 'usr')
        s, r = u.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': 1, 'kks': '11AAA10AA001'}})
        uid = next(x['id'] for x in m.get('/api/users')[1]['users'] if x['username'] == 'usr')
        old_dev = self.store.conn().execute('SELECT device FROM users WHERE id=?', (uid,)).fetchone()[0]
        self.assertEqual(m.post(f'/api/users/{uid}', {'active': False})[0], 200)
        self.assertEqual(self.E.run.cuts[old_dev], 1)            # entries up to the proposal still count
        self.assertEqual(u.get('/api/state')[0], 401)
        self.assertEqual(m.post(f'/api/submissions/{r["id"]}/approve')[0], 200)
        self.assertEqual(m.post(f'/api/users/{uid}', {'active': True})[0], 200)
        new_dev = self.store.conn().execute('SELECT device FROM users WHERE id=?', (uid,)).fetchone()[0]
        self.assertNotEqual(new_dev, old_dev)
        self.assertNotIn(new_dev, self.E.run.cuts)

    def test_manager_value_beats_admin(self):
        m = self.setup_manager()
        adm, usr = self.invite(m, 'adm', 'admin'), self.invite(m, 'usr')
        k = '11LAB70AA501'
        usr.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'floor': '3 m'}, 'base': {}}})
        m.post('/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {'floor': '6 m'}, 'base': {}}})
        sid = adm.get('/api/submissions')[1]['submissions'][0]['id']
        s, r = adm.post(f'/api/submissions/{sid}/approve', {'force': True})
        self.assertEqual(s, 403); self.assertIn('manager', r['error'])
        self.assertEqual(m.post(f'/api/submissions/{sid}/approve', {'force': True})[0], 200)   # the manager may
        self.assertEqual(m.get('/api/state')[1]['equipment'][k]['floor'], '3 m')

    def test_withdraw_and_vote_toggle(self):
        m = self.setup_manager()
        u1, u2 = self.invite(m, 'u1'), self.invite(m, 'u2')
        r = u1.post('/api/submit', {'kind': 'photo', 'payload': {'kks': '11LAB70AA501', 'dataUrl': 'data:image/jpeg;base64,' + JPEG}})[1]
        for n in (1, 0, 1):
            u2.post(f'/api/submissions/{r["id"]}/vote')
            self.assertEqual({s['id']: s for s in u2.get('/api/submissions')[1]['submissions']}[r['id']]['votes'], n)
        self.assertEqual(u2.post(f'/api/submissions/{r["id"]}/withdraw')[0], 403)
        self.assertEqual(u1.post(f'/api/submissions/{r["id"]}/withdraw')[0], 200)
        self.assertEqual(m.post(f'/api/submissions/{r["id"]}/approve')[0], 409)

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

    def test_mark_missing_tag(self):
        m = self.setup_manager()
        u = self.invite(m, 'usr')
        box = {'sheet': 'hp', 'bbox': [100, 200, 180, 230], 'kks': '11LAB90CP5O1', 'isa': 'pi'}
        self.assertEqual(u.post('/api/submit', {'kind': 'tag_add', 'payload': box})[0], 400)  # O is not a digit: invalid KKS
        self.assertEqual(u.post('/api/submit', {'kind': 'tag_add', 'payload': {**box, 'kks': '', 'bbox': [5, 5, 6, 6]}})[0], 400)
        s, r = u.post('/api/submit', {'kind': 'tag_add', 'payload': {**box, 'kks': '11LAB90CP502'}})
        self.assertEqual(r['status'], 'pending')
        self.assertEqual(u.get('/api/state')[1]['added_tags'], [])
        sub = m.get('/api/submissions')[1]['submissions'][0]
        self.assertEqual(sub['kind'], 'tag_add')
        # the admin sees it is really CP501 and corrects it while approving
        self.assertEqual(m.post(f'/api/submissions/{sub["id"]}/approve', {'edit': {'kks': '11LAB90CP501', 'isa': 'PI'}})[0], 200)
        added = u.get('/api/state')[1]['added_tags']
        self.assertEqual([(t['sheet'], t['kks'], t['isa'], t['kind']) for t in added], [('hp', '11LAB90CP501', 'PI', 'instrument')])
        # a mark without a code is allowed (it goes to the review queue in the app)
        self.assertEqual(m.post('/api/submit', {'kind': 'tag_add', 'payload': {**box, 'kks': ''}})[1]['status'], 'approved')
        self.assertEqual(len(m.get('/api/state')[1]['added_tags']), 2)
        # removing an added tag is a normal change: logged and revertible
        tid = added[0]['id']
        self.assertEqual(m.post('/api/submit', {'kind': 'tag_remove', 'payload': {'id': tid}})[1]['status'], 'approved')
        self.assertEqual(len(m.get('/api/state')[1]['added_tags']), 1)
        rev = next(r['rev'] for r in m.get('/api/revisions')[1]['revisions'] if r['entity'] == 'added_tag' and r['after'] is None)
        self.assertEqual(m.post(f'/api/revisions/{rev}/revert')[0], 200)
        self.assertIn(tid, [t['id'] for t in m.get('/api/state')[1]['added_tags']])

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
        # the UI uses stable row IDs (numbers can shift when older entries arrive by sync)
        rows = [r for r in m.get('/api/revisions')[1]['revisions'] if r['entity'] == 'equipment']
        three = next(r for r in rows if r['after'] and json.loads(r['after']).get('floor') == '3 m')
        self.assertEqual(m.post('/api/restore', {'hid': three['hid']})[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment'][k]['floor'], '3 m')
        last = next(r for r in m.get('/api/revisions')[1]['revisions'] if r['entity'] == 'equipment')
        self.assertEqual(m.post(f'/api/revisions/{last["hid"]}/revert')[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment'], {})
        self.assertEqual(m.post('/api/revisions/nosuch-0/revert')[0], 400)

    def test_backup_restore_roundtrip(self):
        m = self.setup_manager()
        for i in range(12):  # crosses snapshot_every=5 a few times
            m.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': i, 'kks': '11AAA10AA001'}})
        m.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': 3, 'kks': '11AAA10AA001', 'on': False}})
        live = sorted(r['step'] for r in m.get('/api/state')[1]['links'])
        out = os.path.join(self.tmp, 'restored.db')
        restore(self.cfg, out)
        import sqlite3
        c = sqlite3.connect(out)   # plant data is the signed log: replaying the restored entries gives the same links
        from peer import replay as R
        root = json.loads(c.execute("SELECT v FROM meta WHERE k='root_pub'").fetchone()[0])
        run, _ = R.replay_run([json.loads(r[0]) for r in c.execute('SELECT data FROM entries')], root)
        self.assertEqual(sorted(step for _, step, _ in run.links), live)
        self.assertEqual(c.execute('SELECT COUNT(*) FROM users').fetchone()[0], 1)
        c.close()
        with self.assertRaises(SystemExit):
            restore(self.cfg, out)  # never overwrites


if __name__ == '__main__':
    unittest.main()


VENV_PY = None
try:
    from server import sheets as _sheets
    VENV_PY = _sheets.venv_python({})
except Exception:  # noqa: BLE001
    pass


@unittest.skipUnless(VENV_PY, 'importer venv not set up (python3 app.py setup-importer)')
class SheetImportTest(Base):
    """Manage → Drawings, using the real importer in .venv on a small generated PDF."""

    def pdf(self):
        out = os.path.join(self.tmp, 'drawing.pdf')
        import subprocess
        subprocess.run([VENV_PY, '-c', 'import pymupdf,sys; d=pymupdf.open(); p=d.new_page(width=842,height=595); '
                        'p.draw_rect(pymupdf.Rect(100,100,200,140)); p.insert_text((110,125),"11LAB70AA501"); d.save(sys.argv[1])', out],
                       check=True)
        return open(out, 'rb').read()

    def upload(self, client, data, **q):
        from urllib.parse import urlencode
        c = http.client.HTTPConnection('127.0.0.1', self.cfg['port'], timeout=30)
        c.request('POST', '/api/sheets/import?' + urlencode(q), data,
                  {'Content-Type': 'application/pdf', 'Cookie': client.cookie or ''})
        r = c.getresponse(); body = json.loads(r.read()); c.close()
        return r.status, body

    def wait(self, client):
        import time
        for _ in range(240):
            job = client.get('/api/sheets/job')[1]['job']
            if job['state'] != 'running':
                return job
            time.sleep(0.5)
        self.fail('import did not finish')

    def test_import_remove_and_failure(self):
        m = self.setup_manager()
        u = self.invite(m, 'usr')
        self.assertTrue(m.get('/api/sheets')[1]['importer']['available'])
        self.assertEqual(self.upload(u, self.pdf(), id='t1', name='Test')[0], 403)
        self.assertEqual(self.upload(m, b'not a pdf', id='t1', name='Test')[0], 400)
        s, r = self.upload(m, self.pdf(), id='t1', name='Test sheet')
        self.assertEqual(s, 200, r)
        self.assertEqual(self.upload(m, self.pdf(), id='t2', name='x')[0], 400)  # one import at a time
        job = self.wait(m)
        self.assertEqual(job['state'], 'done', job['log'])
        sheets = {x['id']: x for x in m.get('/data/sheets.json')[1]}
        self.assertIn('t1', sheets)
        self.assertEqual(m.get('/' + sheets['t1']['file'])[0], 200)  # image served (the ?v= is ignored)
        self.assertEqual(self.upload(m, self.pdf(), id='t1', name='again')[0], 400)  # exists, replace not set
        # a PDF the importer can't read: job fails and sheets.json/tags.json are put back exactly
        before = (open(os.path.join(self.cfg['data_dir'], 'sheets.json')).read(),
                  open(os.path.join(self.cfg['data_dir'], 'tags.json')).read())
        self.assertEqual(self.upload(m, b'%PDF-1.4 garbage', id='bad', name='Bad')[0], 200)
        self.assertEqual(self.wait(m)['state'], 'failed')
        after = (open(os.path.join(self.cfg['data_dir'], 'sheets.json')).read(),
                 open(os.path.join(self.cfg['data_dir'], 'tags.json')).read())
        self.assertEqual(before, after)
        # re-import from the stored PDF with forced rotation, then remove
        self.assertEqual(m.post('/api/sheets/reimport', {'id': 't1', 'rotate': '180'})[0], 200)
        job = self.wait(m)
        self.assertEqual((job['state'], job['result']['rotation'], job['result']['name']), ('done', 180, 'Test sheet'))
        s, r = m.post('/api/sheets/t1/remove')
        self.assertEqual(s, 400); self.assertIn('only sheet', r['error'])  # never leave the app with no drawings
        self.upload(m, self.pdf(), id='keep', name='Keep'); self.assertEqual(self.wait(m)['state'], 'done')
        self.assertEqual(m.post('/api/sheets/t1/remove')[0], 200)
        self.assertNotIn('t1', {x['id'] for x in m.get('/data/sheets.json')[1]})
        notes = [r['note'] for r in m.get('/api/revisions')[1]['revisions'] if r['entity'] == 'sheet']
        self.assertEqual(len(notes), 4, notes)  # t1 added, re-imported, keep added, t1 removed (failure not logged)
