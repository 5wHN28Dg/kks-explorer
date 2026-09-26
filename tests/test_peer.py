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
                       'backup_dir': 'backups', 'discovery': False, 'sync_host': '127.0.0.1'}, f)
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
        _, st = __import__('peer.sync', fromlist=['x']).sync_with(lap.E, '127.0.0.1', srv.cfg['sync_port'])
        self.assertTrue(st['they_denied'])

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


if __name__ == '__main__':
    unittest.main()
