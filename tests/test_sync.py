"""Peer-to-peer sync (docs/PROTOCOL.md §15): Noise against its published vector, then real TCP syncs between
separate nodes (each its own database), through peer/sync.py and server/engine.py."""
import hashlib, json, os, secrets, shutil, socket, sys, tempfile, threading, time, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from peer import noise as N, proto as P, sync as S
from server import changes as ch
from server import config as config_mod
from server.engine import Engine
from server.store import Store


class NoiseVector(unittest.TestCase):
    def test_published_xx_vector(self):
        with open(os.path.join(ROOT, 'peer', 'vectors', 'noise-xx.json')) as f:
            v = json.load(f)['vectors'][0]
        b = bytes.fromhex
        i = N.Handshake(True, N.x25519(b(v['init_static'])), b(v['init_prologue']), N.x25519(b(v['init_ephemeral'])))
        r = N.Handshake(False, N.x25519(b(v['resp_static'])), b(v['resp_prologue']), N.x25519(b(v['resp_ephemeral'])))
        for k, m in enumerate(v['messages'][:3]):
            w, rd = (i, r) if k % 2 == 0 else (r, i)
            ct = w.write(b(m['payload']))
            self.assertEqual(ct.hex(), m['ciphertext'])
            self.assertEqual(rd.read(ct), b(m['payload']))
        self.assertEqual(i.h.hex(), v['handshake_hash'])
        (isend, irecv), (rsend, rrecv) = i.split(), r.split()
        for k, m in enumerate(v['messages'][3:], 3):
            tx, rx = (rsend, irecv) if k % 2 else (isend, rrecv)
            ct = tx.encrypt(b'', b(m['payload']))
            self.assertEqual(ct.hex(), m['ciphertext'])
            self.assertEqual(rx.decrypt(b'', ct), b(m['payload']))

    def test_sync_vectors_frozen(self):
        from peer import make_sync_vectors
        with open(os.path.join(ROOT, 'peer', 'vectors', 'v3-sync.json'), encoding='utf-8') as f:
            self.assertEqual(f.read(), make_sync_vectors.dump(make_sync_vectors.build()))

    def test_tampering_detected(self):
        a, b = N.Handshake(True, N.x25519(secrets.token_bytes(32))), N.Handshake(False, N.x25519(secrets.token_bytes(32)))
        b.read(a.write())
        m = bytearray(b.write(b'x'))
        m[-1] ^= 1
        with self.assertRaises(N.NoiseError):
            a.read(bytes(m))


class Node:
    """A node with its own database, photos and backups, like a separate laptop."""
    def __init__(self, tmp, name):
        d = os.path.join(tmp, name)
        os.makedirs(d)
        self.cfg = dict(config_mod.load(os.path.join(tmp, 'none.json')), db=os.path.join(d, 'plant.db'),
                        photos_dir=os.path.join(d, 'photos'), backup_dir=os.path.join(d, 'backups'), root_key=os.path.join(d, 'root.key'))
        os.makedirs(self.cfg['photos_dir'])
        self.store = Store(self.cfg)
        self.E = Engine(self.store, self.cfg)

    def user(self, person, device, role='user', name='x'):
        with self.E.tx():
            return self.store.put('users', {'username': name, 'pw': None, 'role': role, 'active': 1, 'created': 0,
                                            'full_name': name.title() + ' Person', 'position': None, 'person': person, 'device': device})

    def listen(self):
        """Accept connections in the background until the test ends. -> port"""
        srv = socket.socket()
        srv.bind(('127.0.0.1', 0)); srv.listen()
        self.results, self._srv = [], srv

        def loop():
            while True:
                try:
                    sock, _ = srv.accept()
                except OSError:
                    return
                try:
                    self.results.append(S.serve_one(self.E, sock))
                except (S.SyncError, OSError) as e:
                    self.results.append(e)
        threading.Thread(target=loop, daemon=True).start()
        return srv.getsockname()[1]

    def close(self):
        if hasattr(self, '_srv'):
            self._srv.close()


class SyncTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.nodes = []

    def tearDown(self):
        for n in self.nodes:
            n.close()
            own = {eid: why for eid, why in n.E.run.ignored.items() if n.E.entries[eid]['peer'] in n.E.keys}
            self.assertEqual(own, {}, 'a node signed an entry its own replay ignores')
        shutil.rmtree(self.tmp)

    def write_raw(self, n, dev, type_, body):
        """Sign and store an entry without the engine's own check (for devices that misbehave on purpose)."""
        last = n.store.conn().execute('SELECT id, seq FROM entries WHERE peer=? ORDER BY seq DESC LIMIT 1', (dev,)).fetchone()
        e = P.make_entry(n.E.keys[dev], last[1] + 1 if last else 1, last[0] if last else None,
                         n.E.clock.now(int(__import__('time').time() * 1000)), type_, body)
        with n.store.write():
            n.store.put('entries', {'id': P.entry_id(e), 'peer': dev, 'seq': e['seq'], 'hlc0': e['hlc'][0],
                                    'hlc1': e['hlc'][1], 'type': type_, 'data': P.canonical(e).decode(), 'received': 0})
        n.E._load()

    def node(self, name):
        n = Node(self.tmp, name)
        self.nodes.append(n)
        return n

    def plant(self):
        """Node A: a plant with a manager."""
        a = self.node('a')
        self.M = secrets.token_hex(16)
        with a.E.tx() as c:
            self.mdev = a.E.genesis(c, self.M, 'boss', 'Boss Person', None, 'Test plant')
        a.user(self.M, self.mdev, 'manager', 'boss')
        return a

    def join(self, a, name, person=None, role='user'):
        """A new laptop: makes its own key; A's manager certifies it (for a new person unless given)."""
        n = self.node(name)
        with n.E.tx() as c:
            dev = n.E.new_device(c, person or 'pending')
        if person is None:
            person = secrets.token_hex(16)
            with a.E.tx() as c:
                a.E.append(c, self.mdev, 'person', {'person': person, 'username': name, 'full_name': name.title() + ' Person',
                                                     'position': None, 'role': role})
        with a.E.tx() as c:
            a.E.append(c, self.mdev, 'device_cert', {'device': dev, 'person': person, 'label': name})
        n.person, n.dev = person, dev
        return n

    def served(self, node, n):
        """The listener's n-th result (it records it only after the initiator already returned)."""
        for _ in range(200):
            if len(node.results) >= n:
                return node.results[n - 1]
            time.sleep(0.01)
        self.fail('the listener recorded nothing')

    def sync(self, frm, to_port, adopt=None):
        return S.sync_with(frm.E, '127.0.0.1', to_port, adopt_root=adopt)

    def test_join_propose_approve_relay(self):
        a = self.plant()
        pa = a.listen()
        b = self.join(a, 'bob')
        remote, st = self.sync(b, pa, adopt=a.E.anchor)          # b adopts the plant, gets the log
        self.assertEqual(remote, P.peer_id(a.E.identity()))
        self.assertEqual(b.E.run.state(), a.E.run.state())
        self.assertGreater(st['received'], 0)
        b.user(b.person, b.dev, 'user', 'bob')
        with b.E.tx() as c:                                       # bob proposes on his laptop, offline from A
            prop = b.E.append(c, b.dev, 'link', {'proc': '3.6.1', 'step': 2, 'kks': '11LAB70AA501', 'on': True})
        self.sync(b, pa)
        self.assertEqual(a.E.run.proposals[prop], 'pending')
        users = {}
        with a.E.lock:                                            # it shows in A's Approvals, by bob's name
            me = {'id': 1, 'role': 'manager', 'person': self.M}
            subs = ch.list_subs(a.E, me, users, 'open', 10)
        self.assertEqual([(s['kind'], s['by']) for s in subs], [('link', 'bob')])
        with a.E.tx() as c:
            a.E.append(c, self.mdev, 'approve', {'entry': prop, 'edit': None})
        c3 = self.join(a, 'carol')
        pb = b.listen()
        self.sync(b, pa)                                          # b learns the approval and carol's cert
        self.sync(c3, pb, adopt=a.E.anchor)                       # carol only ever talks to bob: relayed
        self.assertEqual(c3.E.run.state(), a.E.run.state())
        self.assertEqual(c3.E.run.links, {('3.6.1', 2, '11LAB70AA501')})

    def test_stranger_gets_nothing_and_leaves_nothing(self):
        a = self.plant()
        pa = a.listen()
        x = self.node('x')
        with x.E.tx() as c:
            x.E.new_device(c, 'nobody')
        with self.assertRaises(S.SyncError):                     # no plant, and not told which one to trust
            self.sync(x, pa)
        x.E.adopt(a.E.anchor)
        self.write_raw(x, next(iter(x.E.keys)), 'link', {'proc': 'p', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
        _, st = self.sync(x, pa)
        self.assertEqual(st['received'], 0)                       # A sent nothing
        self.assertTrue(self.served(a, 2)[1]['denied'])          # (the listener records after the initiator is done)
        self.assertEqual(len(a.E.entries), 1)                    # A kept none of the stranger's entries
        self.nodes.remove(x)                                      # (x's own replay ignores its entry: expected)

    def test_other_plant_refused(self):
        a = self.plant()
        pa = a.listen()
        other = self.node('other')
        with other.E.tx() as c:
            other.E.genesis(c, secrets.token_hex(16), 'eve', 'Eve Person', None, 'Other plant')
        with self.assertRaises(S.SyncError):
            S.sync_with(other.E, '127.0.0.1', pa)
        self.assertEqual(len(a.E.entries), 1)

    def test_photo_blob_follows_its_entry(self):
        a = self.plant()
        pa = a.listen()
        b = self.join(a, 'bob')
        self.sync(b, pa, adopt=a.E.anchor)
        data = b'\xff\xd8\xff\xe0' + os.urandom(3000)
        sha = hashlib.sha256(data).hexdigest()
        with open(os.path.join(b.cfg['photos_dir'], f'{sha}.jpg'), 'wb') as f:
            f.write(data)
        with b.E.tx() as c:
            b.store.put('blobs', {'sha': sha, 'file': f'{sha}.jpg', 'size': len(data)})
            b.E.blob_files[sha] = f'{sha}.jpg'
            b.E.append(c, b.dev, 'photo', {'photo': secrets.token_hex(16), 'kks': '11LAB70AA501', 'blob': sha, 'caption': ''})
        _, st = self.sync(b, pa)
        self.assertEqual(st['blobs_sent'], 1)
        self.assertEqual(a.E.blob_get(sha), data)
        self.assertFalse(a.E.blob_put(sha, b'other bytes'))       # only what the log asks for, only matching bytes

    def test_revoked_device_is_cut_off(self):
        a = self.plant()
        pa = a.listen()
        b = self.join(a, 'bob')
        self.sync(b, pa, adopt=a.E.anchor)
        with a.E.tx() as c:
            a.E.append(c, self.mdev, 'revoke', {'device': b.dev, 'last_seq': 0})
        _, st = self.sync(b, pa)
        self.assertTrue(self.served(a, 2)[1]['denied'])
        self.assertEqual(st['received'], 0)

    def test_cloned_key_fork_is_caught(self):
        a = self.plant()
        pa = a.listen()
        b = self.join(a, 'bob')
        self.sync(b, pa, adopt=a.E.anchor)
        clone = self.node('clone')                                 # someone copied bob's key file
        seed = b.store.conn().execute('SELECT seed FROM custodial').fetchone()[0]
        with clone.E.tx():
            clone.store.put('custodial', {'device': b.dev, 'person': b.person, 'seed': seed, 'created': 0})
        clone.E.keys[b.dev] = P.key_from_seed(bytes.fromhex(seed))
        self.sync(clone, pa, adopt=a.E.anchor)                    # a copied laptop has the plant's log too
        with b.E.tx() as c:                                       # both write "seq 1" of bob's device
            b.E.append(c, b.dev, 'link', {'proc': 'p', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
        self.write_raw(clone, b.dev, 'link', {'proc': 'p', 'step': 2, 'kks': '11LAB70AA501', 'on': True})
        self.sync(b, pa)
        self.sync(clone, pa)
        self.assertEqual(a.E.run.cuts.get(b.dev), 0)             # the device is cut before the fork
        self.assertEqual(a.E.run.proposals, {})
        pa2 = a.listen()
        c3 = self.join(a, 'carol')
        self.sync(c3, pa2, adopt=a.E.anchor)                       # the evidence travels on
        self.assertEqual(c3.E.run.cuts.get(b.dev), 0)
        for n in (b, clone):
            self.nodes.remove(n)                                  # their own replays see only their own side


if __name__ == '__main__':
    unittest.main()
