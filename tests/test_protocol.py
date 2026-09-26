"""Protocol v1 against the shared test vectors (docs/PROTOCOL.md, peer/vectors/v1.json).
Needs `cryptography`: run with the importer venv:  .venv/bin/python -m unittest discover -s tests"""
import json, os, sys, unittest
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
try:
    from peer import proto as P
    from peer import make_vectors, make_replay_vectors
    from peer import replay as R
except ImportError:  # system python without `cryptography`
    P = None

VEC = os.path.join(ROOT, 'peer', 'vectors', 'v1.json')
VEC2 = os.path.join(ROOT, 'peer', 'vectors', 'v2-replay.json')


@unittest.skipUnless(P, 'needs the cryptography package (use .venv/bin/python)')
class Vectors(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(VEC, encoding='utf-8') as f:
            cls.V = json.load(f)

    def test_file_is_frozen(self):
        # regenerating must give identical bytes: other implementations depend on this file
        with open(VEC, encoding='utf-8') as f:
            self.assertEqual(f.read(), make_vectors.dump(make_vectors.build()))

    def test_ed25519_rfc8032(self):
        t = self.V['ed25519_rfc8032_test1']
        k = P.key_from_seed(bytes.fromhex(t['seed_hex']))
        self.assertEqual(k.sign(bytes.fromhex(t['message_hex'])).hex(), t['signature_hex'])
        # the value published in RFC 8032, section 7.1, test 1
        self.assertTrue(t['signature_hex'].startswith('e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b'[:64]))

    def test_canonical(self):
        for c in self.V['canonical']:
            self.assertEqual(P.canonical(c['input']).hex(), c['canonical_utf8_hex'])
            self.assertEqual(P.canonical(c['input']).decode('utf-8'), c['canonical_text'])
        for r in self.V['canonical_reject']:
            with self.assertRaises(P.ProtocolError) as cm:
                P.canonical(json.loads(r['input_json']))
            self.assertEqual(cm.exception.code, 'bad_encoding', r['why'])

    def test_keys(self):
        for k in self.V['keys']:
            self.assertEqual(P.peer_id(P.key_from_seed(bytes.fromhex(k['seed_hex']))), k['peer'])

    def test_entries(self):
        keys = {k['name']: P.key_from_seed(bytes.fromhex(k['seed_hex'])) for k in self.V['keys']}
        for x in self.V['entries']:
            e = x['entry']
            P.verify_entry(e)
            self.assertEqual(P.signed_bytes(e).hex(), x['signed_bytes_hex'])
            self.assertEqual(P.entry_id(e), x['entry_id'])
            again = P.make_entry(keys[x['device']], e['seq'], e['prev'], e['hlc'], e['type'], e['body'])
            self.assertEqual(again, e)  # deterministic signatures: same inputs, same entry
        for r in self.V['entry_reject']:
            e = r['entry'] if 'entry' in r else json.loads(r['entry_json'])
            with self.assertRaises(P.ProtocolError) as cm:
                P.verify_entry(e)
            self.assertEqual(cm.exception.code, r['code'], r['why'])

    def test_chains(self):
        for c in self.V['chains']:
            if c['result'] == 'ok':
                self.assertEqual([e['seq'] for e in P.verify_chain(c['entries'])], c['order'])
            else:
                with self.assertRaises(P.ProtocolError) as cm:
                    P.verify_chain(c['entries'])
                self.assertEqual(cm.exception.code, c['result'], c['why'])

    def test_hlc(self):
        h = P.HLC()
        for s in self.V['hlc']:
            out = h.now(s['wall']) if s['op'] == 'now' else h.recv(s['remote'], s['wall'])
            self.assertEqual(out, s['state'], s)

    def test_order(self):
        o = self.V['order']
        self.assertEqual([P.entry_id(e) for e in sorted(o['entries'], key=P.order_key)], o['sorted_entry_ids'])

    def test_log_appends_a_valid_chain(self):
        log = P.Log(P.key_from_seed(b'\x01' * 32))
        for i, wall in enumerate((5, 5, 3, 9)):
            log.append('note', {'i': i}, wall)
        chain = P.verify_chain(list(reversed(log.entries)))
        self.assertEqual([e['hlc'] for e in chain], [[5, 0], [5, 1], [5, 2], [9, 0]])


if __name__ == '__main__':
    unittest.main()


@unittest.skipUnless(P, 'needs the cryptography package (use .venv/bin/python)')
class Replay(unittest.TestCase):
    """docs/PROTOCOL.md §8–14 against peer/vectors/v2-replay.json."""
    @classmethod
    def setUpClass(cls):
        with open(VEC2, encoding='utf-8') as f:
            cls.V = json.load(f)
        cls.S = {s['why'].split(':')[0]: s for s in cls.V['scenarios']}

    def test_file_is_frozen(self):
        with open(VEC2, encoding='utf-8') as f:
            self.assertEqual(f.read(), make_vectors.dump(make_replay_vectors.build()))

    def test_statement(self):
        t = self.V['statement']
        root = P.key_from_seed(bytes.fromhex(t['root_seed_hex']))
        self.assertEqual(P.peer_id(root), t['root'])
        self.assertEqual((R.STMT_DOMAIN + P.canonical(t['stmt'])).hex(), t['signed_bytes_hex'])
        self.assertEqual(R.sign_statement(root, t['stmt']), t['root_sig'])
        R.check_statement(t['root'], t['stmt'], t['root_sig'])
        with self.assertRaises(R.Ignore):
            R.check_statement(t['root'], dict(t['stmt'], person='0' * 32), t['root_sig'])

    def test_private(self):
        t = self.V['private']
        secret = bytes.fromhex(t['secret_hex'])
        body = R.private_body(secret, t['person'], t['plaintext']['type'], t['plaintext']['body'],
                              nonce=bytes.fromhex(t['nonce_hex']))
        self.assertEqual(body, t['body'])
        self.assertEqual(R.private_open(secret, t['body']), t['plaintext'])
        from cryptography.exceptions import InvalidTag
        with self.assertRaises(InvalidTag):          # wrong key
            R.private_open(bytes(32), t['body'])
        with self.assertRaises(InvalidTag):          # moved to another person: the AAD binds it
            R.private_open(secret, dict(t['body'], person='0' * 32))

    def test_scenarios_reproduce(self):
        for s in self.V['scenarios']:
            with self.subTest(s['why']):
                got = R.replay(s['entries'], s['root'])
                self.assertEqual(R.state_bytes(got), R.state_bytes(s['state']))

    def test_any_input_order(self):
        import random
        for s in self.V['scenarios']:
            want = R.state_bytes(s['state'])
            for i in range(5):
                entries = list(s['entries'])
                random.Random(i).shuffle(entries)
                self.assertEqual(R.state_bytes(R.replay(entries, s['root'])), want, s['why'])

    def test_wrong_anchor_gives_empty_plant(self):
        s = self.S['one plant']
        st = R.replay(s['entries'], P.peer_id(P.key_from_seed(bytes(32))))
        self.assertIsNone(st['manager'])
        self.assertEqual(st['equipment'], {})

    def _named(self, s):
        names = {v: k for k, v in s['devices'].items()}
        return {P.entry_id(e): (names[e['peer']], e['seq'], e['type']) for e in s['entries'] if e['peer'] in names}

    def test_main_semantics(self):
        s = self.S['one plant']
        st, n = s['state'], self._named(s)
        why = {n[k]: v for k, v in st['ignored'].items() if k in n}
        self.assertEqual(st['equipment'], {'11LAB70AA501': {'floor': '9 m', 'notes': 'manager note'}})
        self.assertEqual(st['links'], [['p12', 5, '11LAB70AA501']])
        tag, = st['added_tags'].values()
        self.assertEqual((tag['kks'], tag['suffix'], tag['isa']), ('11HAH90CT103', 'K', 'TE'))
        self.assertEqual(len(st['photos']), 1)
        self.assertEqual(st['settings']['photo_mode'], 'on_open')
        self.assertEqual(sorted(p['username'] for p in st['persons'].values()), ['ali', 'bob', 'carol', 'hashim'])
        self.assertEqual(st['persons'][make_replay_vectors.pid('carol')]['role'], 'user')
        self.assertEqual(st['persons'][make_replay_vectors.pid('bob')]['full_name'], 'Bob Bobson')
        self.assertEqual(sorted(st['proposals'].values()),
                         ['approved', 'approved', 'approved', 'pending', 'rejected', 'rejected'])
        lost = [(c['field'], c['kept'], c['lost']) for c in st['conflicts']]
        self.assertIn(('notes', 'manager note', 'admin note'), lost)     # manager value survives an admin write
        self.assertIn(('floor', '9 m', '6 m'), lost)
        self.assertEqual(why[('stranger', 1, 'genesis')], 'bad_genesis')
        self.assertEqual(why[('bob-phone', 1, 'equipment')], 'not_certified')
        self.assertEqual(why[('bob-phone', 9, 'equipment')], 'revoked')
        self.assertEqual(why[('bob-phone', 10, 'revoke')], 'revoked')
        self.assertEqual(why[('mgr-laptop', 8, 'root')], 'bad_root_sig')
        self.assertEqual(why[('mgr-phone', 7, 'person')], 'username_taken')
        self.assertIn(s['devices']['mgr-tablet'], st['devices'])
        self.assertIsNone(st['devices'][s['devices']['bob-tablet']]['cut'])
        self.assertEqual(list(st['private']), [make_replay_vectors.pid('bob')])

    def test_stolen_manager_phone(self):
        s = self.S['stolen manager phone']
        st = s['state']
        self.assertEqual(st['devices'][s['devices']['mgr-phone']]['cut'], 2)
        self.assertIsNone(st['devices'][s['devices']['mgr-laptop']]['cut'])
        self.assertEqual(st['settings']['photo_mode'], 'on_open')
        # without the root-signed revoke the thief's earlier revoke wins: the log alone can't tell them apart
        root_entry = next(e for e in s['entries'] if e['type'] == 'root')
        st2 = R.replay([e for e in s['entries'] if e is not root_entry], s['root'])
        self.assertEqual(st2['devices'][s['devices']['mgr-laptop']]['cut'], 0)

    def test_fork(self):
        s = self.S['fork, gap, bad signature']
        st = s['state']
        self.assertEqual(st['devices'][s['devices']['bob-phone']]['cut'], 1)
        self.assertEqual(sorted(st['ignored'].values()), ['bad_sig', 'chain_gap', 'fork', 'fork', 'fork'])
