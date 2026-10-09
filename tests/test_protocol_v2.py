"""Protocol v2 (docs/PROTOCOL-v2.md) against its vectors (ref/vectors/v2-*.json), using the test-only Python reference
in ref/. The Nim core must pass the same files."""
import json, os, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from ref import crypto2 as C, make_v2_vectors as G, proto2 as P, replay2 as R

VEC = os.path.join(ROOT, 'ref', 'vectors')


def load(name):
    with open(os.path.join(VEC, name), encoding='utf-8') as f:
        return json.load(f)


class Frozen(unittest.TestCase):
    def test_files_are_frozen(self):
        for name, build in G.FILES.items():
            with open(os.path.join(VEC, name), encoding='utf-8') as f:
                self.assertEqual(f.read(), G.dump(build()), f'{name} would change: add new vectors in a new file')


class Core(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.V = load('v2-core.json')

    def test_canonical(self):
        for c in self.V['canonical']:
            self.assertEqual(P.canonical(c['input']).hex(), c['canonical_utf8_hex'])
        for c in self.V['canonical_reject']:
            with self.assertRaises(P.ProtocolError):
                P.canonical(json.loads(c['input_json']))

    def test_keys(self):
        for k in self.V['keys']:
            key = P.key_from_seed(bytes.fromhex(k['seed_hex']))
            self.assertEqual(f'{key.private_numbers().private_value:064x}', k['private_scalar_hex'])
            self.assertEqual(P.key_string(key), k['key'])
            self.assertEqual(P.peer_id_of_key(k['key']), k['peer'])
        for k in self.V['keys_reject']:
            with self.assertRaises(ValueError, msg=k['why']):
                P.public_key(k['key'])

    def test_entries(self):
        key = None
        for x in self.V['entries']:
            e = x['entry']
            self.assertEqual(P.signed_bytes(e).hex(), x['signed_bytes_hex'])
            self.assertEqual(P.entry_id(e), x['entry_id'])
            P.verify_entry(e, key)
            key = key or e['key']
        for x in self.V['entry_reject']:
            e = json.loads(x['entry_json']) if 'entry_json' in x else x['entry']
            with self.assertRaises(P.ProtocolError, msg=x['why']) as cm:
                P.verify_entry(e, x['chain_key'])
            self.assertEqual(cm.exception.code, x['code'], x['why'])
        s = self.V['entry_id_ignores_sig']
        self.assertEqual(P.entry_id(s['entry']), s['entry_id'])
        self.assertEqual(P.entry_id(s['resigned_high_s']), s['entry_id'])

    def test_chains(self):
        for c in self.V['chains']:
            if c['result'] == 'ok':
                self.assertEqual([e['seq'] for e in P.verify_chain(c['entries'])], c['order'])
            else:
                with self.assertRaises(P.ProtocolError, msg=c['why']) as cm:
                    P.verify_chain(c['entries'])
                self.assertEqual(cm.exception.code, c['result'], c['why'])

    def test_hlc(self):
        h = P.HLC()
        for op in self.V['hlc']:
            out = h.now(op['wall']) if op['op'] == 'now' else h.recv(op['remote'], op['wall'])
            self.assertEqual(out, op['state'])

    def test_order(self):
        o = self.V['order']
        self.assertEqual([P.entry_id(e) for e in sorted(o['entries'], key=P.order_key)], o['sorted_entry_ids'])


class Replay(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.V = load('v2-replay.json')

    def test_statement(self):
        s = self.V['statement']
        self.assertEqual((R.STMT_DOMAIN + P.canonical(s['stmt'])).hex(), s['signed_bytes_hex'])
        self.assertTrue(P.verify(s['root'], bytes.fromhex(s['signed_bytes_hex']), s['root_sig']))
        self.assertEqual(P.peer_id_of_key(s['root']), s['root_id'])

    def test_private(self):
        p = self.V['private']
        self.assertEqual(R.private_open(bytes.fromhex(p['secret_hex']), p['body']), p['plaintext'])
        again = R.private_body(bytes.fromhex(p['secret_hex']), p['person'], p['plaintext']['type'],
                               p['plaintext']['body'], nonce=bytes.fromhex(p['nonce_hex']))
        self.assertEqual(again, p['body'])

    def test_scenarios_in_any_order(self):
        for s in self.V['scenarios'] + load('v2-malformed.json')['scenarios']:
            want = R.state_bytes(s['state'])
            self.assertEqual(R.state_bytes(R.replay(s['entries'], s['root'])), want, s['why'])
            self.assertEqual(R.state_bytes(R.replay(list(reversed(s['entries'])), s['root'])), want, s['why'])

    def test_wrong_anchor_gives_empty_plant(self):
        s = self.V['scenarios'][0]
        st = R.replay(s['entries'], P.key_string(P.key_from_seed(b'x' * 32)))
        self.assertIsNone(st['manager'])
        self.assertEqual(st['devices'], {})


class Crypto(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.V = load('v2-crypto.json')

    def test_join(self):
        for j in self.V['join_code']:
            self.assertEqual(C.join_code(j['joiner'], j['answering']), j['code'])
        self.assertTrue(C.check_join_request(self.V['join_request']['valid']))
        for r in self.V['join_request']['reject']:
            self.assertFalse(C.check_join_request(r['request']), r['why'])

    def test_relay(self):
        r = self.V['relay']
        self.assertEqual(C.relay_room(r['member']), r['room'])
        self.assertTrue(C.check_relay_hello(r['hello'], r['room'], r['now']))
        for x in r['reject']:
            self.assertFalse(C.check_relay_hello(x['hello'], r['room'], x['now']), x['why'])

    def test_ecies(self):
        from cryptography.hazmat.primitives.asymmetric import ec
        e = self.V['ecies']
        key = ec.derive_private_key(int(e['recipient_private_scalar_hex'], 16), ec.SECP256R1())
        self.assertEqual(C.ecies_open(key, e['sealed']).hex(), e['plaintext_hex'])

    def test_root_backup(self):
        b = self.V['root_backup']
        self.assertEqual(C.passphrase_open(b['passphrase'], b['sealed']).hex(), b['plaintext_hex'])
        with self.assertRaises(Exception):
            C.passphrase_open(b['passphrase'] + 'x', b['sealed'])
        with self.assertRaises(ValueError):
            C.passphrase_seal('p', b'x', iterations=1000)


class Signatures(unittest.TestCase):
    def test_low_s_rule(self):
        k = P.key_from_seed(b's' * 32)
        for i in range(40):   # a platform may return either s: the normalized one verifies, the high one never
            sig = P.sign(k, b'm%d' % i)
            self.assertTrue(P.verify(P.key_string(k), b'm%d' % i, sig))
            self.assertFalse(P.verify(P.key_string(k), b'm%d' % i, P.high_s(sig)))


if __name__ == '__main__':
    unittest.main()
