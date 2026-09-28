"""Peer mode (a laptop as one person's device) and joining a plant: through the server, through a join request +
bundle, and what admins/devices can do afterwards. Real HTTP servers + real sync between separate databases."""
import gzip, json, os, shutil, sys, tempfile, threading, unittest
from http.server import ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import app
from server import config as config_mod
from server.auth import Auth
from server.engine import Engine
from server.store import Store
from server.syncsvc import SyncService
from tests.test_server import Client


class Site:
    """One node: its own database, web server and sync listener."""
    def __init__(self, tmp, name, mode):
        d = os.path.join(tmp, name)
        os.makedirs(os.path.join(d, 'data'))
        for n in ('tags.json', 'sheets.json'):
            with open(os.path.join(d, 'data', n), 'w') as f:
                f.write('[]')
        with open(os.path.join(d, 'config.json'), 'w') as f:
            json.dump({'mode': mode, 'port': 0, 'data_dir': 'data', 'db': 'plant.db', 'photos_dir': 'photos',
                       'backup_dir': 'backups', 'discovery': False, 'sync_host': '127.0.0.1', 'sync_interval': 0}, f)
        self.cfg = config_mod.load(os.path.join(d, 'config.json'))
        os.makedirs(self.cfg['photos_dir'])
        self.store = Store(self.cfg)
        self.auth = Auth(self.store, self.cfg)
        self.E = Engine(self.store, self.cfg)
        self.svc = SyncService(self.E, self.cfg, log=lambda *a: None)
        self.cfg['sync_port'] = self.svc.listen('127.0.0.1', 0)
        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), app.make_handler(self.cfg, self.store, self.auth, self.E, self.svc))
        self.cfg['port'] = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.url = f'http://127.0.0.1:{self.cfg["port"]}'

    def client(self):
        return Client(self.cfg['port'])

    def close(self):
        self.httpd.shutdown(); self.httpd.server_close(); self.svc.srv.close()


def S_peer(site):
    from peer import proto
    return proto.peer_id(site.E.identity())


class PeerTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.sites = []

    def tearDown(self):
        for s in self.sites:
            s.close()
            own = {k: v for k, v in s.E.run.ignored.items() if s.E.entries[k]['peer'] in s.E.keys}
            self.assertEqual(own, {})
        shutil.rmtree(self.tmp)

    def site(self, name, mode):
        s = Site(self.tmp, name, mode)
        self.sites.append(s)
        return s

    def server_with_users(self):
        srv = self.site('server', 'server')
        m = srv.client()
        tok = srv.auth.make_token('setup', None, 3600)
        self.assertEqual(m.post('/api/setup', {'token': tok, 'username': 'boss', 'password': 'correct horse', 'full_name': 'Boss Person'})[0], 200)
        link = m.post('/api/users', {'username': 'usr', 'role': 'user', 'full_name': 'Usr Person'})[1]['link']
        u = srv.client()
        self.assertEqual(u.post('/api/password-reset', {'token': link.split('#reset=')[1], 'password': 'usr password!'})[0], 200)
        m.post('/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 1, 'kks': '11LAB70AA501'}})
        return srv, m, u

    def test_peer_mode_is_local_only_and_passwordless(self):
        lap = self.site('laptop', 'peer')
        c = lap.client()
        self.assertEqual(c.req('GET', '/api/config', headers={'Host': 'evil.example:80'})[0], 403)   # DNS rebinding
        cfg = c.get('/api/config')[1]
        self.assertEqual((cfg['mode'], cfg['node']['joined']), ('peer', False))
        self.assertEqual(c.get('/api/state')[0], 401)
        s, r = c.post('/api/node/new-plant', {'plant': 'Home plant', 'username': 'me', 'full_name': 'Me Myself'})
        self.assertEqual(s, 200, r)
        self.assertTrue(c.get('/api/config')[1]['node']['joined'])
        self.assertEqual(c.get('/api/me')[1]['user']['role'], 'manager')   # no password, no cookie
        self.assertTrue(os.path.exists(lap.E.root_path))
        self.assertEqual(c.post('/api/submit', {'kind': 'link', 'payload': {'proc': 'p', 'step': 1, 'kks': '11LAB70AA501'}})[1]['status'], 'approved')
        self.assertEqual(c.post('/api/node/new-plant', {'username': 'x2', 'full_name': 'Again'})[0], 404)   # only before joining

    def test_join_through_the_server(self):
        srv, m, u = self.server_with_users()
        lap = self.site('laptop', 'peer')
        c = lap.client()
        s, r = c.post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'wrong password!'})
        self.assertEqual(s, 400); self.assertIn('Wrong username or password', r['error'])
        s, r = c.post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})
        self.assertEqual(s, 200, r)
        me = c.get('/api/me')[1]['user']
        self.assertEqual((me['username'], me['role'], me['full_name']), ('usr', 'user', 'Usr Person'))
        self.assertEqual(lap.E.run.state(), srv.E.run.state())
        # the laptop's edit becomes a proposal on the server, approved there, and comes back
        self.assertEqual(c.post('/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 2, 'kks': '11LAB70AA501'}})[1]['status'], 'pending')
        c.post('/api/sync/now', {'address': f'127.0.0.1:{srv.cfg["sync_port"]}'})
        sub = next(x for x in m.get('/api/submissions')[1]['submissions'] if x['kind'] == 'link')
        self.assertEqual(sub['by_name'], 'Usr Person')
        self.assertEqual(m.post(f'/api/submissions/{sub["id"]}/approve')[0], 200)
        c.post('/api/sync/now', {'address': f'127.0.0.1:{srv.cfg["sync_port"]}'})
        self.assertEqual(len(c.get('/api/state')[1]['links']), 2)
        self.assertEqual({d['label'] for d in u.get('/api/devices')[1]['mine']}, {'server', lap.E.run.devices[lap.E.node_device()]['label']})
        # deactivating the account on the server removes the laptop too
        uid = next(x['id'] for x in m.get('/api/users')[1]['users'] if x['username'] == 'usr')
        self.assertEqual(m.post(f'/api/users/{uid}', {'active': False})[0], 200)
        self.assertIn(lap.E.node_device(), srv.E.run.cuts)
        S = __import__('peer.sync', fromlist=['x'])
        with self.assertRaises(S.SyncError):                  # it is shown the revoke entry and deletes the plant
            S.sync_with(lap.E, '127.0.0.1', srv.cfg['sync_port'])
        self.assertIsNone(lap.E.owner())
        self.sites.remove(lap); lap.close()

    def test_restart_keeps_the_plant(self):
        # regression: a joined laptop restarted once ran the old-database migration and made a plant of its own
        srv, m, u = self.server_with_users()
        lap = self.site('laptop', 'peer')
        lap.client().post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})
        anchor, n = lap.E.anchor, len(lap.E.entries)
        again = Engine(lap.store, lap.cfg)
        self.assertEqual((again.anchor, len(again.entries)), (anchor, n))
        self.assertEqual(again.owner()['username'], 'usr')
        self.assertFalse(os.path.exists(again.root_path))
        with self.assertRaises(ValueError):
            with again.tx() as c:
                again.genesis(c, 'f' * 32, 'x', 'X Person', None, 'P')

    def test_join_with_request_and_bundle(self):
        srv, m, u = self.server_with_users()
        lap = self.site('laptop', 'peer')
        c = lap.client()
        req = c.post('/api/node/join-request', {'username': 'newbie', 'full_name': 'New Person', 'position': 'Technician'})[1]['request']
        self.assertEqual(u.post('/api/devices/import-request', {'request': req})[0], 403)          # admins only
        bad = dict(req, username='boss')                                                             # changed after signing
        self.assertIn('changed', m.post('/api/devices/import-request', {'request': bad})[1]['error'])
        s, r = m.post('/api/devices/import-request', {'request': req})
        self.assertEqual((s, r['username']), (200, 'newbie'))
        self.assertEqual(u.get('/api/bundle')[0], 403)                                               # export: admins only
        s, bundle = m.req('GET', '/api/bundle?photos=1')
        self.assertEqual(s, 200)
        self.assertEqual(json.loads(gzip.decompress(bundle))['root'], srv.E.anchor)
        import http.client
        h = http.client.HTTPConnection('127.0.0.1', lap.cfg['port'])
        h.request('POST', '/api/bundle/import', bundle, {'Content-Type': 'application/octet-stream'})
        r = json.loads(h.getresponse().read())
        self.assertTrue(r['joined'] and r['adopted'])
        me = c.get('/api/me')[1]['user']
        self.assertEqual((me['username'], me['position']), ('newbie', 'Technician'))
        users = m.get('/api/users')[1]['users']
        nb = next(x for x in users if x['username'] == 'newbie')
        self.assertTrue(nb['no_account'] and nb['devices'] == 1)
        # a second laptop for an existing person needs the admin's explicit OK
        lap2 = self.site('laptop2', 'peer')
        req2 = lap2.client().post('/api/node/join-request', {'username': 'usr', 'full_name': 'Usr Person'})[1]['request']
        s, r = m.post('/api/devices/import-request', {'request': req2})
        self.assertEqual((s, r['existing']['username']), (409, 'usr'))
        self.assertEqual(m.post('/api/devices/import-request', {'request': req2, 'existing_ok': True})[0], 200)
        # the person without an account can be managed from the server by the log
        self.assertEqual(m.post(f'/api/persons/{nb["person"]}', {'active': False})[0], 200)
        self.assertIn(lap.E.node_device(), srv.E.run.cuts)

    def test_join_by_invite(self):
        """PROTOCOL.md §16: the admin shows an invite (QR code), the new device asks over the sync port, the admin
        accepts, the device syncs the plant."""
        import time
        from peer import sync as S
        from server import node as node_mod
        srv, m, u = self.server_with_users()
        real, app.lan_addresses = app.lan_addresses, lambda port: [f'127.0.0.1:{port}']   # the listeners are on loopback
        node_mod.InviteJoin.POLL = 0.1
        try:
            self.assertEqual(u.post('/api/invites', {})[0], 403)                                   # admins only
            s, r = m.post('/api/invites', {})
        finally:
            app.lan_addresses = real
        self.assertEqual(s, 200)
        inv, tok = r['invite'], r['invite']['token']
        self.assertEqual((inv['root'], inv['peer'], json.loads(r['code'])), (srv.E.anchor, S.P.peer_id(srv.E.identity()), inv))
        self.assertEqual(m.get(f'/api/invites/{tok}')[1]['state'], 'open')
        self.assertEqual(m.post(f'/api/invites/{tok}', {'action': 'accept'})[0], 409)             # nobody asked yet
        lap = self.site('laptop', 'peer')
        c = lap.client()
        self.assertEqual(c.post('/api/node/join-invite', {'invite': '{"x":1}', 'username': 'newbie', 'full_name': 'N P'})[0], 400)
        s, r = c.post('/api/node/join-invite', {'invite': r['code'], 'username': 'newbie', 'full_name': 'New Person'})
        self.assertEqual(s, 200)

        def until(fn, what):
            for _ in range(100):
                v = fn()
                if v:
                    return v
                time.sleep(0.05)
            self.fail(what)
        st = until(lambda: (lambda x: x if x['state'] == 'asked' else None)(m.get(f'/api/invites/{tok}')[1]), 'no request arrived')
        self.assertEqual((st['request']['username'], st['request']['device'], st['existing']), ('newbie', lap.E.node_device(), None))
        until(lambda: c.get('/api/node/join-invite')[1]['state'] == 'waiting', 'joiner not waiting')
        # another device can't use the same invite
        lap2 = self.site('laptop2', 'peer')
        req2 = lap2.client().post('/api/node/join-request', {'username': 'other', 'full_name': 'O P'})[1]['request']
        self.assertEqual(S.join_ask(lap2.E.identity(), '127.0.0.1', srv.cfg['sync_port'], inv['peer'], tok, req2)[0], 'used')
        # a wrong expected peer is refused by the joiner before it says anything
        with self.assertRaises(S.SyncError):
            S.join_ask(lap2.E.identity(), '127.0.0.1', srv.cfg['sync_port'], lap2.E.node_device(), tok, req2)
        self.assertEqual(S.join_ask(lap2.E.identity(), '127.0.0.1', srv.cfg['sync_port'], inv['peer'], 'x' * 22, req2)[0], 'unknown')
        self.assertEqual(m.post(f'/api/invites/{tok}', {'action': 'accept'})[0], 200)
        until(lambda: c.get('/api/node/join-invite')[1]['state'] == 'joined', 'joiner did not join')
        me = c.get('/api/me')[1]['user']
        self.assertEqual((me['username'], me['full_name']), ('newbie', 'New Person'))
        self.assertEqual(lap.E.anchor, srv.E.anchor)
        self.assertEqual(m.post(f'/api/invites/{tok}', {'action': 'accept'})[0], 409)             # one use

        # refused, and an existing username needs the admin's OK (same rule as a join request file)
        app.lan_addresses = lambda port: [f'127.0.0.1:{port}']
        try:
            code = m.post('/api/invites', {})[1]['code']
        finally:
            app.lan_addresses = real
        tok2 = json.loads(code)['token']
        c2 = lap2.client()
        c2.post('/api/node/join-invite', {'invite': code, 'username': 'usr', 'full_name': 'Usr Person'})
        st = until(lambda: (lambda x: x if x['state'] == 'asked' else None)(m.get(f'/api/invites/{tok2}')[1]), 'no request')
        self.assertEqual(st['existing']['username'], 'usr')
        s, r = m.post(f'/api/invites/{tok2}', {'action': 'accept'})
        self.assertEqual((s, r['existing']['username']), (409, 'usr'))
        self.assertEqual(m.post(f'/api/invites/{tok2}', {'action': 'refuse'})[0], 200)
        st = until(lambda: (lambda x: x if x['state'] == 'failed' else None)(c2.get('/api/node/join-invite')[1]), 'not refused')
        self.assertIn('refused', st['error'])
        self.assertIsNone(lap2.E.owner())

    def test_join_nearby_without_invite(self):
        """§16 without a token: a laptop asks an admin's device found on the Wi-Fi; both screens show the same code;
        the admin accepts, the person confirms the code, the laptop syncs."""
        import time
        from server import node as node_mod
        node_mod.InviteJoin.POLL = 0.1
        srv, m, u = self.server_with_users()
        lap = self.site('laptop', 'peer')
        c = lap.client()
        self.assertEqual(c.get('/api/node/nearby')[1]['devices'], [])            # (discovery is off in tests)
        server_peer = S_peer(srv)
        near = {'peer': server_peer, 'host': '127.0.0.1', 'port': srv.cfg['sync_port'], 'plant': 'KKS Explorer'}
        s, r = c.post('/api/node/join-invite', {'nearby': near, 'username': 'lina', 'full_name': 'Lina Person'})
        self.assertEqual(s, 200)

        def until(fn, what):
            for _ in range(100):
                v = fn()
                if v:
                    return v
                time.sleep(0.05)
            self.fail(what)
        reqs = until(lambda: m.get('/api/join-requests')[1]['requests'], 'no request in the lobby')
        mine = c.get('/api/node/join-invite')[1]
        self.assertEqual((reqs[0]['request']['username'], reqs[0]['code']), ('lina', mine['code']))
        self.assertEqual(len(mine['code']), 6)
        self.assertEqual(u.get('/api/join-requests')[0], 403)                          # admins only
        self.assertEqual(m.post(f'/api/join-requests/{reqs[0]["device"]}', {'action': 'accept'})[0], 200)
        until(lambda: c.get('/api/node/join-invite')[1]['state'] == 'confirm', 'not waiting for the code OK')
        time.sleep(0.3)
        self.assertIsNone(lap.E.owner())                                               # nothing trusted before the OK
        self.assertEqual(c.post('/api/node/join-invite', {'confirm': True})[0], 200)
        until(lambda: c.get('/api/node/join-invite')[1]['state'] == 'joined', 'did not join')
        self.assertEqual(c.get('/api/me')[1]['user']['username'], 'lina')
        self.assertEqual(m.get('/api/join-requests')[1]['requests'], [])

    def test_course_progress_is_private_and_follows_the_person(self):
        """M4: progress = private entries; the server relays them but can't read them; two laptops of one person swap
        their person secrets directly (§17) and then both see the merged progress."""
        from server import progress
        srv, m, u = self.server_with_users()
        a, b = self.site('lapA', 'peer'), self.site('lapB', 'peer')
        ca, cb = a.client(), b.client()
        for c in (ca, cb):
            self.assertEqual(c.post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})[0], 200)
        self.assertEqual(u.get('/api/progress')[0], 404)                                  # a plant server keeps none
        self.assertEqual(ca.post('/api/progress', {'course': 'ppt', 'data': {'solved': '{"q1":true}', 'finalBest': '7'}})[0], 200)
        self.assertEqual(ca.post('/api/progress', {'course': 'PPT!', 'data': {'x': '1'}})[0], 400)
        self.assertEqual(ca.get('/api/progress?course=ppt')[1]['data'], {'solved': '{"q1":true}', 'finalBest': '7'})
        a.svc.sync_one('127.0.0.1', srv.cfg['sync_port']); b.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])
        self.assertEqual(cb.get('/api/progress')[1]['courses'], {})                        # has the entry, not the key
        person = b.E.owner()['person']
        self.assertTrue(srv.E.run.private.get(person))                                    # the server holds it...
        self.assertEqual(progress.load(srv.E, person), {})                                # ...and can't read it
        self.assertEqual(progress.secrets_of(srv.E, person), [])
        self.assertEqual(cb.post('/api/progress', {'course': 'ppt', 'data': {'solved': '{"q2":true}', 'finalBest': '5.5'}})[0], 200)
        b.svc.sync_one('127.0.0.1', a.cfg['sync_port'])                                   # same person: secrets swapped
        a.svc.sync_one('127.0.0.1', b.cfg['sync_port'])
        for c in (ca, cb):
            got = c.get('/api/progress?course=ppt')[1]['data']
            self.assertEqual((json.loads(got['solved']), got['finalBest']), ({'q1': True, 'q2': True}, '7'))
        self.assertEqual(len(progress.secrets_of(a.E, person)), 2)
        self.assertEqual(progress.secrets_of(srv.E, person), [])                          # the server never got one

    def test_removed_laptop_wipes_itself(self):
        """Field report 2026-09-28: removing a device only stopped its syncs. Now the next sync shows it the signed
        revoke entry; it checks it against its own log and deletes the plant (§15 `revoked`)."""
        from peer import sync as S
        from server import progress
        srv, m, u = self.server_with_users()
        lap = self.site('laptop', 'peer')
        c = lap.client()
        c.post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})
        c.post('/api/progress', {'course': 'ppt', 'data': {'solved': '{"q1":true}'}})
        lap.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])
        dev = lap.E.node_device()
        # a stranger can't make it wipe: a revoke entry signed by a device the laptop doesn't know
        from peer import proto as P
        stranger = P.key_from_seed(os.urandom(32))
        fake = P.make_entry(stranger, 1, None, [1, 0], 'revoke', {'device': dev, 'last_seq': 0})
        self.assertFalse(lap.E.accept_revocation(fake))
        self.assertIsNotNone(lap.E.owner())
        # the real one: an admin removes it on the server; the laptop's next sync gets the proof and wipes
        self.assertEqual(m.post('/api/devices/revoke', {'device': dev})[0], 200)
        with self.assertRaises(S.SyncError):
            lap.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])
        self.assertIsNone(lap.E.owner())
        self.assertEqual((len(lap.E.entries), lap.E.anchor), (0, None))
        cfg = c.get('/api/config')[1]['node']
        self.assertEqual((cfg['joined'], cfg['removed']['by']), (False, 'Boss Person'))
        self.assertEqual(c.get('/api/me')[0], 401)
        conn = lap.store.conn()
        try:
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM entries').fetchone()[0], 0)
            self.assertEqual(conn.execute('SELECT COUNT(*) FROM person_secrets').fetchone()[0], 0)
        finally:
            conn.close()
        for root, _, files in os.walk(lap.cfg['backup_dir']):                             # the backups hold nothing old
            for f in files:
                with open(os.path.join(root, f), 'rb') as fh:
                    self.assertNotIn(dev.encode(), fh.read(), f)
        with open(lap.cfg['db'], 'rb') as fh:
            self.assertNotIn(dev.encode(), fh.read())                                     # (VACUUM: no freed pages)
        self.assertNotEqual(lap.E.ensure_node_device(), dev)                               # a new key for a new start
        self.sites.remove(lap)                                                             # (its replay is empty now)
        lap.close()

    def test_devices_revoke_rules(self):
        srv, m, u = self.server_with_users()
        lap = self.site('laptop', 'peer')
        lap.client().post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})
        boss_dev = next(d['device'] for d in m.get('/api/devices')[1]['mine'])
        self.assertEqual(u.post('/api/devices/revoke', {'device': boss_dev})[0], 403)             # not theirs
        own = u.get('/api/devices')[1]['mine']
        self.assertEqual(u.post('/api/devices/revoke', {'device': next(d['device'] for d in own if d['this_computer'])})[0], 400)
        self.assertEqual(u.post('/api/devices/revoke', {'device': lap.E.node_device()})[0], 200)  # a lost laptop
        self.assertIn(lap.E.node_device(), srv.E.run.cuts)


class Desktop(unittest.TestCase):
    def test_launcher_self_test(self):
        # the double-click entry point, from source: its own temporary folder, page + API + a new plant, then stops
        import subprocess
        r = subprocess.run([sys.executable, os.path.join(ROOT, 'desktop.py'), '--self-test'], capture_output=True, text=True, timeout=120)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('self-test OK', r.stdout)


if __name__ == '__main__':
    unittest.main()
