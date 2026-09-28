"""M5: sync across the internet through the relay (PROTOCOL.md §18), with the Python relay (peer/relay_server.py,
the same protocol as the Cloudflare Worker). No STUN in tests (offline): candidates are this machine's addresses, so
hole punching succeeds directly; the pipe path is forced by withholding candidates.
KKS_RELAY_URL=ws://127.0.0.1:8787 runs them against the Cloudflare Worker (relay/) under `wrangler dev`."""
import json, os, sys, time, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from peer import internet as I, relay_server as RS, sync as S
from tests import test_peer


class InternetTest(unittest.TestCase):
    site, server_with_users = test_peer.PeerTest.site, test_peer.PeerTest.server_with_users
    def setUp(self):
        test_peer.PeerTest.setUp(self)
        self.relay = RS.Relay()
        port = self.relay.serve()
        # KKS_RELAY_URL: run the same tests against another relay, e.g. the Cloudflare Worker under `wrangler dev`
        self.url = os.environ.get('KKS_RELAY_URL') or f'ws://127.0.0.1:{port}'
        self.nets = []

    def tearDown(self):
        for n in self.nets:
            n.stop()
        self.relay.stop()
        test_peer.PeerTest.tearDown(self)

    def net(self, site):
        log = []
        n = I.Internet(site.E, lambda: self.url, lambda *a: log.append(a), log=lambda *a: None, stun_servers=[])
        n.records = log
        n.start()
        self.nets.append(n)
        return n

    def until(self, fn, what, t=10):
        end = time.time() + t
        while time.time() < end:
            v = fn()
            if v:
                return v
            time.sleep(0.05)
        self.fail(what)

    def two_laptops(self):
        srv, m, u = self.server_with_users()
        a, b = self.site('lapA', 'peer'), self.site('lapB', 'peer')
        for s in (a, b):
            self.assertEqual(s.client().post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})[0], 200)
        a.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])   # (a joined first: learn b's certificate)
        return srv, m, a, b

    def test_presence_needs_the_device_key(self):
        srv, m, a, b = self.two_laptops()
        na, nb = self.net(a), self.net(b)
        self.until(lambda: b.E.node_device() in na.online and a.E.node_device() in nb.online, 'not online')
        # a hello signed by another key is refused
        from peer import ws as W, proto as P
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        room = RS.room_of(a.E.root())
        w = W.WebSocket(f'{self.url}/v1/room/{room}')
        ts = int(time.time())
        w.send_text(json.dumps({'t': 'hello', 'peer': a.E.node_device(), 'ts': ts,
                                'sig': P.b64u(Ed25519PrivateKey.generate().sign(RS.HELLO_DOMAIN + room.encode() + b'\n' + str(ts).encode()))}))
        self.assertEqual(json.loads(w.recv()[1])['t'], 'error')
        self.assertIn(b.E.node_device(), na.online)          # the real one is still there

    def test_direct_sync(self):
        srv, m, a, b = self.two_laptops()
        na, nb = self.net(a), self.net(b)
        self.until(lambda: b.E.node_device() in na.online, 'b not online')
        a.client().post('/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 7, 'kks': '11LAB70AA501'}})
        remote, st = na.sync(b.E.node_device())
        self.assertEqual((remote, st['sent'] >= 1), (b.E.node_device(), True))
        self.assertIn('internet (direct)', [r[1] for r in na.records])
        self.until(lambda: len(b.client().get('/api/submissions?status=all')[1]['submissions']) >= 1, 'b did not get it')

    def test_relay_pipe_when_punching_fails(self):
        srv, m, a, b = self.two_laptops()
        na, nb = self.net(a), self.net(b)
        for n in (na, nb):   # nothing to punch to: the pipe must carry it
            n._udp = lambda: (__import__('socket').socket(2, 2), [])
        self.until(lambda: b.E.node_device() in na.online, 'b not online')
        a.client().post('/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 8, 'kks': '11LAB70AA501'}})
        remote, st = na.sync(b.E.node_device())
        self.assertEqual(remote, b.E.node_device())
        self.assertIn('internet (relay)', [r[1] for r in na.records])
        self.assertIn('internet (relay)', [r[1] for r in nb.records])

    def test_relay_setting_and_auto_sync(self):
        """The manager sets the relay once; laptops learn it by sync and sync with each other over it by themselves."""
        srv, m, a, b = self.two_laptops()
        self.assertEqual(a.client().post('/api/settings/relay', {'url': self.url})[0], 403)      # manager only
        self.assertEqual(m.post('/api/settings/relay', {'url': 'http://x'})[0], 400)
        self.assertEqual(m.post('/api/settings/relay', {'url': self.url})[0], 200)
        for s in (a, b):
            s.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])
            self.assertEqual(s.E.run.settings['relay'], self.url)
            s.svc.net.stun_servers = []
            s.svc.net.start()
        self.until(lambda: b.E.node_device() in a.svc.net.online, 'b not on the relay')
        a.client().post('/api/submit', {'kind': 'link', 'payload': {'proc': '3.6.1', 'step': 9, 'kks': '11LAB70AA501'}})
        a.svc.sync_internet()                              # (what the automatic round does)
        self.until(lambda: any(x['payload'].get('step') == 9 for x in b.client().get('/api/submissions?status=all')[1]['submissions']), 'not synced')
        net = a.client().get('/api/devices')[1]['sync']['internet']
        self.assertEqual((net['relay'], net['state'], b.E.node_device() in net['online']), (self.url, 'connected', True))
        self.assertGreaterEqual(a.client().get('/api/sync/status')[1]['reachable'], 1)
        for s in (a, b):
            s.svc.net.stop()

    def test_other_plant_and_absent_peer(self):
        srv, m, a, b = self.two_laptops()
        na = self.net(a)
        self.until(lambda: na.state == 'connected', 'not connected')
        with self.assertRaises(S.SyncError):
            na.sync('A' * 43)                                # nobody by that ID in the room


if __name__ == '__main__':
    unittest.main()
