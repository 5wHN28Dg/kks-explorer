#!/usr/bin/env python3
"""Generate peer/vectors/v3-sync.json: vectors for docs/PROTOCOL.md §15 (sync connection). Deterministic; FROZEN once
another implementation depends on it (tests/test_sync.py checks regeneration is byte-identical).
  .venv/bin/python peer/make_sync_vectors.py [--write]"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cryptography.hazmat.primitives import serialization
from peer import noise as N, proto as P, sync as S
from peer.make_vectors import dump, seed

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'v3-sync.json')


def raw(k, private=False):
    if private:
        return k.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw, serialization.NoEncryption())
    return k.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def build():
    V = {'protocol': 1, 'note': 'Sync connection vectors (docs/PROTOCOL.md §15). Reproduce every value exactly.'}
    ids = {n: P.key_from_seed(seed(n)) for n in ('alice-phone', 'bob-phone')}
    V['static_keys'] = [{'device': n, 'ed25519_seed_hex': seed(n).hex(), 'peer': P.peer_id(k),
                         'x25519_private_hex': raw(S.static_key(k), True).hex(), 'x25519_public_hex': raw(S.static_key(k)).hex()}
                        for n, k in ids.items()]
    a, b = ids['alice-phone'], ids['bob-phone']
    V['identity_payload'] = {'device': 'bob-phone', 'signed_bytes_hex': (S.STATIC_DOMAIN + raw(S.static_key(b))).hex(),
                             'payload_utf8': S.identity_payload(b, S.static_key(b)).decode()}
    # a whole handshake with fixed ephemeral keys: alice connects to bob
    ei, er = seed('eph-initiator'), seed('eph-responder')
    i = N.Handshake(True, S.static_key(a), S.PROLOGUE, N.x25519(ei))
    r = N.Handshake(False, S.static_key(b), S.PROLOGUE, N.x25519(er))
    m1 = i.write(b''); r.read(m1)
    m2 = r.write(S.identity_payload(b, S.static_key(b))); p2 = i.read(m2)
    m3 = i.write(S.identity_payload(a, S.static_key(a))); p3 = r.read(m3)
    assert S.check_identity(p2, i.rs) == P.peer_id(b) and S.check_identity(p3, r.rs) == P.peer_id(a)
    (itx, _), (_, rrx) = i.split(), r.split()
    hello = {'t': 'hello', 'v': 1, 'root': P.peer_id(P.key_from_seed(seed('root'))), 'vv': {}}
    import json
    body = json.dumps(hello, separators=(',', ':')).encode()
    first = itx.encrypt(b'', b'\x00' + body)
    assert rrx.decrypt(b'', first)[1:] == body
    V['handshake'] = {'initiator': 'alice-phone', 'responder': 'bob-phone', 'prologue_utf8': S.PROLOGUE.decode(),
                      'initiator_ephemeral_hex': ei.hex(), 'responder_ephemeral_hex': er.hex(),
                      'messages_hex': [m1.hex(), m2.hex(), m3.hex()], 'handshake_hash_hex': i.h.hex(),
                      'first_transport': {'plaintext_utf8': body.decode(), 'flag': 0, 'ciphertext_hex': first.hex()}}
    return V


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
        print('wrote', OUT)
    else:
        print(text[:2000])
