#!/usr/bin/env python3
"""Generate peer/vectors/v1.json: the shared test vectors for protocol v1 (docs/PROTOCOL.md).

Deterministic (fixed seeds; Ed25519 signatures are deterministic). The file is committed and FROZEN: once another
implementation depends on it, regenerating must produce identical bytes (tests/test_protocol.py checks this).
  .venv/bin/python peer/make_vectors.py [--write]"""
import hashlib, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peer import proto as P

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'v1.json')


def seed(name):  # fixed, readable seeds for the vector devices
    return hashlib.sha256(b'kks-vector-seed:' + name.encode()).digest()


def build():
    V = {'protocol': 1, 'note': 'Shared test vectors. Reproduce every value exactly. See docs/PROTOCOL.md.'}

    # RFC 8032 section 7.1, test 1: checks the Ed25519 library itself against the standard
    rfc_seed = bytes.fromhex('9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60')
    k = P.key_from_seed(rfc_seed)
    V['ed25519_rfc8032_test1'] = {'seed_hex': rfc_seed.hex(), 'message_hex': '',
                                  'public_b64u': P.peer_id(k), 'signature_hex': k.sign(b'').hex()}

    # §1 canonical encoding
    ok = [
        {'a': 1, 'b': [True, False, None], 'c': 'x'},
        {'z': 1, 'a': {'y': 2, 'b': 3}},                     # key order, nested
        {'s': 'quote " backslash \\ slash /'},
        {'s': 'nl\ncr\rtab\tbs\bff\f'},                       # short escapes
        {'s': '\x00\x01\x1f\x7f'},                            # other controls → \u00xx lowercase; DEL as-is
        {'s': 'ÜML 中文 ☃ 😀  '},                         # non-ASCII as-is (UTF-8)
        {'n': [0, -1, 9007199254740991, -9007199254740991]},
        {'e': {}, 'l': [], 'k_2': ''},
    ]
    V['canonical'] = [{'input': o, 'canonical_utf8_hex': P.canonical(o).hex(),
                       'canonical_text': P.canonical(o).decode('utf-8')} for o in ok]
    V['canonical_reject'] = [
        {'why': 'float', 'input_json': '{"a":1.5}'},
        {'why': 'integer too large', 'input_json': '{"a":9007199254740992}'},
        {'why': 'uppercase key', 'input_json': '{"A":1}'},
        {'why': 'key with dash', 'input_json': '{"a-b":1}'},
        {'why': 'key too long', 'input_json': '{"' + 'a' * 33 + '":1}'},
    ]

    # §2 keys
    devs = {n: P.key_from_seed(seed(n)) for n in ('alice-phone', 'alice-laptop', 'bob-phone')}
    V['keys'] = [{'name': n, 'seed_hex': seed(n).hex(), 'peer': P.peer_id(k)} for n, k in devs.items()]

    # §3–4 entries and a chain
    a = devs['alice-phone']
    e1 = P.make_entry(a, 1, None, [1790000000000, 0], 'note', {'text': 'first'})
    e2 = P.make_entry(a, 2, P.entry_id(e1), [1790000000000, 1], 'note', {'text': 'ÜML ☃', 'n': 42})
    e3 = P.make_entry(a, 3, P.entry_id(e2), [1790000005000, 0], 'note', {'nested': {'b': [1, 2], 'a': None}})
    V['entries'] = [{'device': 'alice-phone', 'entry': e, 'signed_bytes_hex': P.signed_bytes(e).hex(),
                     'entry_id': P.entry_id(e)} for e in (e1, e2, e3)]

    def bad(e, **ch):
        x = json.loads(json.dumps(e)); x.update(ch); return x
    fork2 = P.make_entry(a, 2, P.entry_id(e1), [1790000000000, 1], 'note', {'text': 'different'})
    V['entry_reject'] = [
        {'why': 'tampered body', 'code': 'bad_sig', 'entry': bad(e2, body={'text': 'changed', 'n': 42})},
        {'why': 'tampered clock', 'code': 'bad_sig', 'entry': bad(e2, hlc=[1790000000000, 2])},
        {'why': 'signature from another device', 'code': 'bad_sig', 'entry': bad(e2, peer=P.peer_id(devs['bob-phone']))},
        {'why': 'extra field', 'code': 'bad_fields', 'entry': bad(e1, extra=1)},
        {'why': 'seq 1 with prev', 'code': 'bad_prev', 'entry': bad(e1, prev=P.entry_id(e2))},
        {'why': 'seq 0', 'code': 'bad_seq', 'entry': bad(e1, seq=0)},
        {'why': 'version 2', 'code': 'bad_version', 'entry': bad(e1, v=2)},
        {'why': 'float in body', 'code': 'bad_encoding', 'entry_json': json.dumps(e1).replace('"text": "first"', '"text": 1.5')},
    ]
    V['chains'] = [
        {'why': 'valid, given out of order', 'entries': [e3, e1, e2], 'result': 'ok', 'order': [1, 2, 3]},
        {'why': 'gap', 'entries': [e1, e3], 'result': 'chain_gap'},
        {'why': 'does not start at 1', 'entries': [e2, e3], 'result': 'chain_gap'},
        {'why': 'fork: two different seq 2', 'entries': [e1, e2, fork2], 'result': 'fork'},
        {'why': 'prev points elsewhere', 'entries': [e1, fork2, e3], 'result': 'chain_prev'},
    ]

    # §5 hybrid logical clock: a script of operations from state [0, 0]
    ops = [('now', 1000), ('now', 1000), ('now', 999), ('recv', [1500, 3], 1200), ('now', 1200),
           ('recv', [1500, 9], 1500), ('recv', [1400, 0], 1600), ('recv', [1600 + P.SKEW_MS + 1, 0], 1600),
           ('now', 2000)]
    h, script = P.HLC(), []
    for op in ops:
        out = h.now(op[1]) if op[0] == 'now' else h.recv(op[1], op[2])
        script.append({'op': op[0], 'wall': op[-1], **({'remote': op[1]} if op[0] == 'recv' else {}), 'state': out})
    V['hlc'] = script

    # §6 total order across devices (ties on the clock broken by peer, then seq)
    b = devs['bob-phone']; l = devs['alice-laptop']
    mix = [P.make_entry(b, 1, None, [1790000000000, 0], 'note', {}),
           P.make_entry(l, 1, None, [1790000000000, 1], 'note', {}),
           P.make_entry(l, 2, 'f' * 64, [1790000000000, 0], 'note', {}),   # order doesn't need a valid chain
           e1, e2, e3]
    V['order'] = {'entry_ids': [P.entry_id(e) for e in mix],
                  'entries': mix,
                  'sorted_entry_ids': [P.entry_id(e) for e in sorted(mix, key=P.order_key)]}
    return V


def dump(V):
    return json.dumps(V, ensure_ascii=False, indent=1, sort_keys=True) + '\n'


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
        print('wrote', OUT)
    else:
        print(text[:2000])
