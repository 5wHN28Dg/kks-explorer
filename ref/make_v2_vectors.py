#!/usr/bin/env python3
"""Generate the protocol v2 test vectors (docs/PROTOCOL-v2.md) into ref/vectors/:
  v2-core.json       §1–7: canonical encoding, keys, entries, chains, clock, order
  v2-replay.json     §8–14, §21: statements, private entries, scenarios (incl. the v1 import)
  v2-malformed.json  every entry type with every field replaced by every kind of wrong value
  v2-crypto.json     §16, §18, §20: join code and request, relay room and hello, ECIES, passphrase backup

Deterministic (fixed seeds, RFC 6979 signatures, fixed clocks and nonces). The files are FROZEN once the Nim core
depends on them: regenerating must give identical bytes (tests/test_protocol_v2.py).
  .venv/bin/python ref/make_v2_vectors.py [--write]"""
import hashlib, json, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from cryptography.hazmat.primitives.asymmetric import ec

from ref import crypto2 as C
from ref import proto2 as P
from ref import replay2 as R

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors')
T0 = 1790000000000
NOTE = 'Protocol v2 test vectors (docs/PROTOCOL-v2.md). Reproduce every value exactly; verify signatures (they are ' \
       'RFC 6979 here, but any valid low-S signature must verify).'


def seed(name):
    return hashlib.sha256(b'kks-vector-seed:' + name.encode()).digest()


def pid(name):
    return hashlib.sha256(b'kks-vector-person:' + name.encode()).hexdigest()[:32]


def rid(name):
    return hashlib.sha256(b'kks-vector-id:' + name.encode()).hexdigest()[:32]


def dump(V):
    return json.dumps(V, ensure_ascii=False, indent=1, sort_keys=True) + '\n'


def private_scalar_hex(k):
    return f'{k.private_numbers().private_value:064x}'


# ====================================================================== v2-core
def core():
    V = {'protocol': 2, 'note': NOTE}
    ok = [
        {'a': 1, 'b': [True, False, None], 'c': 'x'},
        {'z': 1, 'a': {'y': 2, 'b': 3}},
        {'s': 'quote " backslash \\ slash /'},
        {'s': 'nl\ncr\rtab\tbs\bff\f'},
        {'s': '\x00\x01\x1f\x7f'},
        {'s': 'ÜML 中文 ☃ 😀  '},
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
    devs = {n: P.key_from_seed(seed(n)) for n in ('alice-phone', 'alice-laptop', 'bob-phone')}
    V['keys'] = [{'name': n, 'seed_hex': seed(n).hex(), 'private_scalar_hex': private_scalar_hex(k),
                  'key': P.key_string(k), 'peer': P.peer_id(k)} for n, k in devs.items()]
    V['keys_reject'] = [
        {'why': 'not on the curve', 'key': P.b64u(b'\x04' + b'\x01' * 64)},
        {'why': 'compressed form (33 bytes)', 'key': P.b64u(b'\x02' + b'\x11' * 32)},
        {'why': 'wrong length', 'key': P.key_string(devs['bob-phone'])[:-2]},
    ]
    a = devs['alice-phone']
    e1 = P.make_entry(a, 1, None, [1790000000000, 0], 'note', {'text': 'first'})
    e2 = P.make_entry(a, 2, P.entry_id(e1), [1790000000000, 1], 'note', {'text': 'ÜML ☃', 'n': 42})
    e3 = P.make_entry(a, 3, P.entry_id(e2), [1790000005000, 0], 'note', {'nested': {'b': [1, 2], 'a': None}})
    V['entries'] = [{'device': 'alice-phone', 'entry': e, 'signed_bytes_hex': P.signed_bytes(e).hex(),
                     'entry_id': P.entry_id(e)} for e in (e1, e2, e3)]

    def bad(e, **ch):
        x = json.loads(json.dumps(e)); x.update(ch); return x
    other = P.make_entry(devs['bob-phone'], 1, None, [1790000000000, 0], 'note', {'text': 'first'})
    no_key = bad(e1); no_key.pop('key')
    fork2 = P.make_entry(a, 2, P.entry_id(e1), [1790000000000, 1], 'note', {'text': 'different'})
    chain_key = P.key_string(a)
    V['entry_reject'] = [
        {'why': 'tampered body', 'code': 'bad_sig', 'chain_key': chain_key, 'entry': bad(e2, body={'text': 'changed', 'n': 42})},
        {'why': 'tampered clock', 'code': 'bad_sig', 'chain_key': chain_key, 'entry': bad(e2, hlc=[1790000000000, 2])},
        {'why': 'signature from another device', 'code': 'bad_sig', 'chain_key': chain_key, 'entry': bad(e2, sig=other['sig'])},
        {'why': 'high-S signature', 'code': 'bad_sig', 'chain_key': chain_key, 'entry': bad(e2, sig=P.high_s(e2['sig']))},
        {'why': 'key does not hash to peer', 'code': 'bad_key', 'chain_key': None, 'entry': bad(e1, key=P.key_string(devs['bob-phone']))},
        {'why': 'seq 1 without key', 'code': 'bad_fields', 'chain_key': None, 'entry': no_key},
        {'why': 'seq 2 with a key', 'code': 'bad_fields', 'chain_key': chain_key, 'entry': bad(e2, key=chain_key)},
        {'why': 'extra field', 'code': 'bad_fields', 'chain_key': None, 'entry': bad(e1, extra=1)},
        {'why': 'seq 1 with prev', 'code': 'bad_prev', 'chain_key': None, 'entry': bad(e1, prev=P.entry_id(e2))},
        {'why': 'version 1', 'code': 'bad_version', 'chain_key': None, 'entry': bad(e1, v=1)},
        {'why': 'float in body', 'code': 'bad_encoding', 'chain_key': None,
         'entry_json': json.dumps(e1).replace('"text": "first"', '"text": 1.5')},
    ]
    V['entry_id_ignores_sig'] = {'entry': e2, 'resigned_high_s': bad(e2, sig=P.high_s(e2['sig'])),
                                 'entry_id': P.entry_id(e2)}
    V['chains'] = [
        {'why': 'valid, given out of order', 'entries': [e3, e1, e2], 'result': 'ok', 'order': [1, 2, 3]},
        {'why': 'gap', 'entries': [e1, e3], 'result': 'chain_gap'},
        {'why': 'does not start at 1 (no key to verify with)', 'entries': [e2, e3], 'result': 'chain_gap'},
        {'why': 'fork: two different seq 2', 'entries': [e1, e2, fork2], 'result': 'fork'},
        {'why': 'prev points elsewhere', 'entries': [e1, fork2, e3], 'result': 'chain_prev'},
    ]
    ops = [('now', 1000), ('now', 1000), ('now', 999), ('recv', [1500, 3], 1200), ('now', 1200),
           ('recv', [1500, 9], 1500), ('recv', [1400, 0], 1600), ('recv', [1600 + P.SKEW_MS + 1, 0], 1600),
           ('now', 2000)]
    h, script = P.HLC(), []
    for op in ops:
        out = h.now(op[1]) if op[0] == 'now' else h.recv(op[1], op[2])
        script.append({'op': op[0], 'wall': op[-1], **({'remote': op[1]} if op[0] == 'recv' else {}), 'state': out})
    V['hlc'] = script
    b, l = devs['bob-phone'], devs['alice-laptop']
    mix = [P.make_entry(b, 1, None, [1790000000000, 0], 'note', {}),
           P.make_entry(l, 1, None, [1790000000000, 1], 'note', {}),
           P.make_entry(l, 2, 'f' * 64, [1790000000000, 0], 'note', {}),
           e1, e2, e3]
    V['order'] = {'entry_ids': [P.entry_id(e) for e in mix], 'entries': mix,
                  'sorted_entry_ids': [P.entry_id(e) for e in sorted(mix, key=P.order_key)]}
    return V


# ====================================================================== v2-replay
class World:
    """Devices writing logs with explicit clocks (t = ms after T0)."""
    def __init__(self):
        self.root = P.key_from_seed(seed('root'))
        self.logs, self.entries = {}, []

    def key(self, name):
        return P.key_from_seed(seed(name))

    def peer(self, name):
        return P.peer_id(self.key(name))

    def w(self, dev, t, type_, body):
        log = self.logs.setdefault(dev, P.Log(self.key(dev)))
        e = log.append(type_, body, T0 + t)
        self.entries.append(e)
        return P.entry_id(e)

    def next_id(self, dev, t, type_, body):
        """The ID the next entry of `dev` would get (to decide on it before it exists in the order)."""
        log = self.logs[dev]
        e = P.make_entry(self.key(dev), len(log.entries) + 1, P.entry_id(log.entries[-1]), [T0 + t, 0], type_, body)
        return P.entry_id(e)

    def stmt(self, stmt, key=None):
        return {'stmt': stmt, 'root_sig': R.sign_statement(key or self.root, stmt)}

    def genesis(self, dev, t, person, username, full_name, position=None, root=None, imp=None):
        root = root or self.root
        sm = {'kind': 'manager', 'person': person}
        sd = {'kind': 'device', 'device': self.peer(dev), 'person': person}
        return self.w(dev, t, 'genesis', {
            'plant': 'Test plant', 'root': P.key_string(root),
            'manager': {'person': person, 'username': username, 'full_name': full_name, 'position': position},
            'stmt_manager': sm, 'stmt_device': sd,
            'sig_manager': R.sign_statement(root, sm), 'sig_device': R.sign_statement(root, sd), 'import': imp})

    def scenario(self, why, expect, extra=()):
        entries = sorted(self.entries + list(extra), key=P.entry_id)
        return {'why': why, 'expect': expect, 'root': P.key_string(self.root),
                'devices': {n: self.peer(n) for n in sorted(self.logs)},
                'entries': entries, 'state': R.replay(entries, P.key_string(self.root))}


def person(p, username, full_name, role, position=None):
    return {'person': p, 'username': username, 'full_name': full_name, 'position': position, 'role': role}


def main_scenario():
    W = World()
    M, A, B, Cc = pid('manager'), pid('ali'), pid('bob'), pid('carol')
    secret = seed('bob-person-secret')
    W.genesis('stranger', 900, pid('stranger'), 'stranger', 'Some One', root=W.key('fake-root'))
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M', 'I&C Maintenance Engineer')
    W.w('mgr-phone', 1100, 'device_cert', {'device': W.peer('mgr-laptop'), 'person': M, 'label': 'laptop'})
    W.w('mgr-phone', 1200, 'person', person(A, 'ali', 'Ali Admin', 'admin', 'Shift Supervisor'))
    W.w('mgr-phone', 1210, 'person', person(B, 'bob', 'Bob User', 'user'))
    W.w('mgr-phone', 1300, 'device_cert', {'device': W.peer('ali-phone'), 'person': A, 'label': 'phone'})
    W.w('bob-phone', 1250, 'equipment', {'kks': '11LAB70AA501', 'changes': {'area': 'x'}, 'base': {}})
    W.w('ali-phone', 1400, 'device_cert', {'device': W.peer('bob-phone'), 'person': B, 'label': 'phone'})
    p1 = W.w('bob-phone', 1500, 'equipment', {'kks': '11LAB70AA501', 'changes': {'floor': '3 m', 'notes': 'near pump'}, 'base': {}})
    W.w('ali-phone', 1600, 'approve', {'entry': p1, 'edit': None})
    p2 = W.w('bob-phone', 1700, 'link', {'proc': 'p12', 'step': 3, 'kks': '11LAB70AA501', 'on': True})
    W.w('ali-phone', 1750, 'reject', {'entry': p2, 'note': 'wrong step'})
    W.w('mgr-laptop', 1800, 'approve', {'entry': p2, 'edit': None})
    W.w('ali-phone', 1900, 'equipment', {'kks': '11LAB70AA501', 'changes': {'floor': '6 m'}, 'base': {'floor': '3 m'}})
    W.w('mgr-laptop', 2000, 'equipment', {'kks': '11LAB70AA501', 'changes': {'notes': 'manager note'}, 'base': {'notes': ''}})
    W.w('ali-phone', 2100, 'equipment', {'kks': '11LAB70AA501', 'changes': {'notes': 'admin note'}, 'base': {'notes': 'near pump'}})
    W.w('ali-phone', 2150, 'equipment', {'kks': '11LBA10AA402', 'changes': {'custom': [{'k': 'Size', 'v': 'DN50'}], 'loc': 'x'}, 'base': {}})
    W.w('ali-phone', 2160, 'equipment', {'kks': '11LBA10AA402', 'changes': {'custom': [], 'loc': ''}, 'base': {'custom': [{'k': 'Size', 'v': 'DN50'}], 'loc': 'x'}})
    p3 = W.w('bob-phone', 2200, 'tag_add', {'tag': rid('t1'), 'sheet': 'hp', 'bbox': [1000, 2000, 1800, 2400],
                                            'kks': '11HAH90CT103', 'suffix': '', 'isa': 'TI', 'note': 'missed'})
    W.w('mgr-laptop', 2300, 'approve', {'entry': p3, 'edit': {'kks': '11HAH90CT103', 'suffix': 'K', 'isa': 'TE'}})
    photo = {'photo': rid('ph1'), 'kks': '11LAB70AA501', 'blob': hashlib.sha256(b'jxl bytes').hexdigest(), 'caption': 'valve'}
    p4_id = W.next_id('bob-phone', 2400, 'photo', photo)
    W.w('ali-phone', 2350, 'approve', {'entry': p4_id, 'edit': None})
    assert W.w('bob-phone', 2400, 'photo', photo) == p4_id
    p6 = W.w('bob-phone', 2410, 'review', {'tag_id': 'hp:12', 'data': {'status': 'confirmed', 'kks': '11LAB90AA301'}, 'base': None})
    W.w('ali-phone', 2420, 'approve', {'entry': p6, 'edit': {'kks': '11LAB90AA301', 'suffix': '', 'isa': None}})
    W.w('ali-phone', 2500, 'person', person(Cc, 'carol', 'Carol C', 'admin'))
    W.w('ali-phone', 2510, 'setting', {'key': 'photo_mode', 'value': 'all'})
    W.w('mgr-phone', 2600, 'setting', {'key': 'photo_mode', 'value': 'on_open'})
    W.w('mgr-phone', 2650, 'person', person(pid('bob2'), 'Bob', 'Bob Two', 'user'))
    W.w('mgr-phone', 2660, 'person', person(Cc, 'carol', 'Carol C', 'user'))
    W.w('bob-phone', 2700, 'device_cert', {'device': W.peer('bob-tablet'), 'person': B, 'label': 'tablet'})
    W.w('bob-phone', 2710, 'device_cert', {'device': W.peer('evil'), 'person': A, 'label': 'x'})
    W.w('bob-tablet', 2800, 'private', R.private_body(secret, B, 'course_progress', {'course': 'hrsg', 'score': 7},
                                                       nonce=bytes(range(12))))
    W.w('bob-tablet', 2810, 'private', R.private_body(secret, A, 'course_progress', {}, nonce=bytes(12)))
    W.w('bob-tablet', 2850, 'person', person(B, 'bob', 'Bob Bobson', 'user', 'Technician'))
    W.w('bob-tablet', 2855, 'person', person(B, 'bob', 'Bob Bobson', 'admin'))
    W.w('bob-tablet', 2860, 'approve', {'entry': p1, 'edit': None})
    last_good = len(W.logs['bob-phone'].entries)
    p5 = W.w('bob-phone', 2900, 'equipment', {'kks': '11LAB70AA501', 'changes': {'area': 'stolen'}, 'base': {}})
    W.w('bob-phone', 2950, 'revoke', {'device': W.peer('bob-tablet'), 'last_seq': 0})
    W.w('ali-phone', 3000, 'approve', {'entry': p5, 'edit': None})
    W.w('ali-phone', 3100, 'revoke', {'device': W.peer('bob-phone'), 'last_seq': last_good})
    W.w('bob-tablet', 3150, 'link', {'proc': 'p12', 'step': 4, 'kks': '11LAB70AA501', 'on': True})
    W.w('mgr-laptop', 3160, 'link', {'proc': 'p12', 'step': 5, 'kks': '11LAB70AA501', 'on': True})
    W.w('mgr-laptop', 3165, 'tag_add', {'tag': rid('t2'), 'sheet': 'lp', 'bbox': [0, 0, 10, 10],
                                        'kks': None, 'suffix': '', 'isa': None, 'note': ''})
    W.w('mgr-laptop', 3170, 'tag_remove', {'tag': rid('t2')})
    W.w('mgr-phone', 3200, 'note', {'text': 'unknown type'})
    W.w('mgr-phone', 3210, 'equipment', {'kks': '11lab70', 'changes': {'area': 'x'}, 'base': {}})
    W.w('mgr-phone', 3220, 'setting', {'key': 'k', 'value': 1, 'extra': 2})
    W.w('mgr-phone', 3250, 'root', W.stmt({'kind': 'backup_key', 'key': P.key_string(W.key('backup'))}))
    W.w('mgr-phone', 3260, 'root', W.stmt({'kind': 'import', 'v1': '0' * 64, 'state': '0' * 64}))
    root2 = W.key('root-2')
    W.w('mgr-laptop', 3300, 'root', W.stmt({'kind': 'rotate', 'root': P.key_string(root2)}))
    W.w('mgr-laptop', 3400, 'root', W.stmt({'kind': 'manager', 'person': A}))
    W.w('mgr-laptop', 3500, 'root', W.stmt({'kind': 'device', 'device': W.peer('mgr-tablet'), 'person': M}, root2))
    W.w('mgr-tablet', 3600, 'setting', {'key': 'shared_note', 'value': {'text': 'ÜML ☃', 'n': [1, 2]}})
    W.w('ali-phone', 3700, 'equipment', {'kks': '11LAB70AA501', 'changes': {'floor': '9 m'}, 'base': {'floor': '3 m'}})
    return W.scenario(
        'one plant: identity, proposals, approvals, merge, revocation, rotation, backup key',
        ['impostor genesis for another root: bad_genesis', 'bob-phone entry before its cert: not_certified',
         'p1 approved by ali; p2 rejected first, the later approve is already_decided',
         'notes: manager value beats the admin write that did not see it (conflict kept=manager)',
         'custom and loc emptied → 11LBA10AA402 removed', 'tag_add approved with edit → suffix K, isa TE; a manager tag added then removed',
         'photo approve before its proposal: waits, applies', 'edit on a review proposal → rejected',
         'admin creating an admin / writing a setting: not_allowed', 'duplicate username (case-insensitive): username_taken',
         'private entry under own person counted, under another person not_allowed',
         'bob-phone revoked by ali after its tablet cert: later proposal, its approve and the phone\'s own revoke of the tablet do not count',
         'backup_key statement sets state.backup_key; an import statement outside a genesis is bad_body',
         'root rotation: a later statement signed by the old key is bad_root_sig; the new key certifies mgr-tablet',
         'floor 9 m by ali over her own 6 m with a stale base: conflict, new wins (both admin)'])


def stolen_manager_phone():
    W = World()
    M = pid('manager')
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M')
    W.w('mgr-phone', 1100, 'device_cert', {'device': W.peer('mgr-laptop'), 'person': M, 'label': 'laptop'})
    W.w('mgr-phone', 2000, 'revoke', {'device': W.peer('mgr-laptop'), 'last_seq': 0})
    W.w('mgr-phone', 2100, 'setting', {'key': 'photo_mode', 'value': 'thief'})
    W.w('mgr-laptop', 2500, 'revoke', {'device': W.peer('mgr-phone'), 'last_seq': 2})
    W.w('mgr-laptop', 2600, 'root', W.stmt({'kind': 'revoke', 'device': W.peer('mgr-phone'), 'last_seq': 2}))
    W.w('mgr-laptop', 2700, 'setting', {'key': 'photo_mode', 'value': 'on_open'})
    return W.scenario('stolen manager phone: a root-signed revoke outranks device revokes',
                      ['phone cut at 2; its revoke of the laptop and its setting are revoked',
                       'laptop entries all count; photo_mode = on_open'])


def fork_gaps_keys():
    W = World()
    M, B = pid('manager'), pid('bob')
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M')
    W.w('mgr-phone', 1100, 'person', person(B, 'bob', 'Bob User', 'user'))
    W.w('mgr-phone', 1200, 'device_cert', {'device': W.peer('bob-phone'), 'person': B, 'label': ''})
    W.w('mgr-phone', 1210, 'device_cert', {'device': W.peer('bad-key'), 'person': B, 'label': ''})
    W.w('bob-phone', 1300, 'link', {'proc': 'p1', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
    log = W.logs['bob-phone']
    W.w('bob-phone', 1400, 'link', {'proc': 'p1', 'step': 2, 'kks': '11LAB70AA501', 'on': True})
    fork = P.make_entry(W.key('bob-phone'), 2, P.entry_id(log.entries[0]), [T0 + 1400, 0], 'link',
                        {'proc': 'p1', 'step': 9, 'kks': '11LAB70AA501', 'on': True})
    W.w('bob-phone', 1500, 'link', {'proc': 'p1', 'step': 3, 'kks': '11LAB70AA501', 'on': True})
    lap = P.Log(W.key('mgr-laptop'))
    lap.append('setting', {'key': 'a', 'value': 1}, T0 + 1000)
    gap = lap.append('setting', {'key': 'b', 'value': 2}, T0 + 1100)
    bad = dict(W.logs['mgr-phone'].entries[1], sig=W.logs['mgr-phone'].entries[2]['sig'])   # a bad copy of a valid entry
    ml = W.logs['mgr-phone']
    forged = {'v': 2, 'peer': W.peer('mgr-phone'), 'seq': len(ml.entries) + 1, 'prev': P.entry_id(ml.entries[-1]),
              'hlc': [T0 + 1800, 0], 'type': 'setting', 'body': {'key': 'forged', 'value': 1},
              'sig': ml.entries[-1]['sig']}   # content no key signed: bad_sig
    high = dict(W.logs['mgr-phone'].entries[2], sig=P.high_s(W.logs['mgr-phone'].entries[2]['sig']))
    # a device whose seq-1 entry carries someone else's key: bad_key, its later entries can't be verified
    bk = W.key('bad-key')
    first = {'v': 2, 'peer': P.peer_id(bk), 'seq': 1, 'prev': None, 'hlc': [T0 + 1600, 0], 'type': 'setting',
             'body': {'key': 'x', 'value': 1}, 'key': P.key_string(W.key('mgr-phone'))}
    first['sig'] = P.sign(bk, P.signed_bytes(first))
    second = P.make_entry(bk, 2, P.entry_id(first), [T0 + 1700, 0], 'setting', {'key': 'y', 'value': 2})
    W.logs['mgr-laptop'] = lap
    W.logs['bad-key'] = P.Log(bk)
    return W.scenario('fork, gap, bad signature, high S, bad key',
                      ['bob-phone forked at seq 2: cut at 1, both seq 2 entries and seq 3 are fork evidence',
                       'mgr-laptop seq 2 without seq 1: chain_gap',
                       'copies of valid entries with a wrong or high-S signature share the valid entry\'s ID: dropped, '
                       'nothing reported (§3 copies)', 'a forged entry (content no key signed): bad_sig',
                       'bad-key: seq 1 whose key hashes to another peer ID: bad_key; its seq 2: chain_gap'],
                      extra=[fork, gap, bad, high, forged, first, second])


def withdraw_votes():
    W = World()
    M, B, D = pid('manager'), pid('bob'), pid('dana')
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M')
    W.w('mgr-phone', 1100, 'person', person(B, 'bob', 'Bob User', 'user'))
    W.w('mgr-phone', 1110, 'person', person(D, 'dana', 'Dana User', 'user'))
    W.w('mgr-phone', 1200, 'device_cert', {'device': W.peer('bob-phone'), 'person': B, 'label': ''})
    W.w('mgr-phone', 1210, 'device_cert', {'device': W.peer('dana-phone'), 'person': D, 'label': ''})
    ph = lambda n: {'photo': rid(n), 'kks': '11LAB70AA501', 'blob': hashlib.sha256(n.encode()).hexdigest(), 'caption': ''}
    a = W.w('bob-phone', 1300, 'photo', ph('a'))
    b = W.w('dana-phone', 1310, 'photo', ph('b'))
    W.w('dana-phone', 1400, 'vote', {'entry': a, 'on': True})
    W.w('bob-phone', 1410, 'vote', {'entry': b, 'on': True})
    W.w('bob-phone', 1420, 'vote', {'entry': b, 'on': False})
    W.w('dana-phone', 1500, 'withdraw', {'entry': a})
    W.w('bob-phone', 1510, 'withdraw', {'entry': a})
    W.w('mgr-phone', 1520, 'approve', {'entry': a, 'edit': None})
    W.w('mgr-phone', 1600, 'approve', {'entry': b, 'edit': None})
    W.w('mgr-phone', 1700, 'review', {'tag_id': 'lp:7', 'data': {'status': 'rejected'}, 'base': None})
    r = W.w('bob-phone', 1800, 'review', {'tag_id': 'lp:7', 'data': None, 'base': {'status': 'rejected'}})
    W.w('mgr-phone', 1900, 'approve', {'entry': r, 'edit': None})
    W.w('mgr-phone', 1950, 'device_cert', {'device': W.peer('bob-laptop'), 'person': B, 'label': 'laptop'})
    body = {'proc': 'p1', 'step': 1, 'kks': '11LAB70AA501', 'on': True}
    late = W.next_id('bob-phone', 2100, 'link', body)
    W.w('bob-laptop', 2000, 'withdraw', {'entry': late})
    assert W.w('bob-phone', 2100, 'link', body) == late
    return W.scenario('withdraw, votes, review removal',
                      ['photo a withdrawn by its author (another user can\'t); a later approve is already_decided',
                       'votes: dana on a; bob\'s vote on b switched off again → votes {a: [dana]} only',
                       'an approved user proposal with data null removes the review',
                       'a withdraw from the author\'s other device, earlier in the order, waits and applies'])


def pairs(d):
    return [[k, d[k]] for k in sorted(d)]


def import_state(M, extra_person=None):
    """The §21 pair form of a v1 state."""
    A, B = pid('ali'), pid('bob')
    persons = {M: {'username': 'hashim', 'full_name': 'Old Name', 'position': None, 'role': 'admin'},
               A: {'username': 'ali', 'full_name': 'Ali Admin', 'position': 'Shift Supervisor', 'role': 'admin'},
               B: {'username': 'bob', 'full_name': 'Bob User', 'position': None, 'role': 'user'}}
    if extra_person:
        persons.update(extra_person)
    return {'persons': pairs(persons),
            'settings': pairs({'photo_mode': 'on_open', 'relay': None}),
            'equipment': pairs({'11LAB70AA501': {'floor': '3 m', 'notes': 'near pump',
                                                 'custom': [{'k': 'Size', 'v': 'DN80'}]}}),
            'reviews': pairs({'hp:12': {'status': 'confirmed', 'kks': '11LAB90AA301'}}),
            'links': [['p12', 3, '11LAB70AA501']],
            'photos': pairs({rid('ph1'): {'kks': '11LAB70AA501', 'blob': hashlib.sha256(b'jxl bytes').hexdigest(),
                                          'caption': 'valve'}}),
            'added_tags': pairs({rid('t1'): {'sheet': 'hp', 'bbox': [1000, 2000, 1800, 2400], 'kks': '11HAH90CT103',
                                             'suffix': 'K', 'isa': 'TE', 'note': 'missed'}})}


def import_block(W, st, v1=None, state_hash=None):
    stmt = {'kind': 'import', 'v1': v1 or hashlib.sha256(b'v1 archive').hexdigest(),
            'state': state_hash or hashlib.sha256(P.canonical(st)).hexdigest()}
    return {'stmt': stmt, 'root_sig': R.sign_statement(W.root, stmt), 'state': st}


def imported_plant():
    W = World()
    M, A, B = pid('manager'), pid('ali'), pid('bob')
    W.genesis('mgr-laptop', 1000, M, 'hashim', 'Hashim M', 'I&C Maintenance Engineer',
              imp=import_block(W, import_state(M)))
    W.w('mgr-laptop', 1100, 'device_cert', {'device': W.peer('ali-phone'), 'person': A, 'label': 'phone'})
    W.w('mgr-laptop', 1110, 'device_cert', {'device': W.peer('bob-phone'), 'person': B, 'label': 'phone'})
    W.w('ali-phone', 1200, 'equipment', {'kks': '11LAB70AA501', 'changes': {'floor': '6 m'}, 'base': {'floor': '1 m'}})
    p = W.w('bob-phone', 1300, 'link', {'proc': 'p12', 'step': 3, 'kks': '11LAB70AA501', 'on': False})
    W.w('ali-phone', 1400, 'approve', {'entry': p, 'edit': None})
    W.w('mgr-laptop', 1500, 'person', person(pid('newbie'), 'Bob', 'Another Bob', 'user'))
    return W.scenario('a v2 plant made from a v1 import (§21)',
                      ['imported persons keep their roles; the manager takes the genesis name and position',
                       'imported settings, equipment, reviews, links, photos, added tags are the starting state',
                       'ali overwrites an imported floor with a stale base: conflict, new wins, kept_by null (imported values count as set by nobody)',
                       'bob\'s approved proposal removes an imported link',
                       'a new person with an imported username (case-insensitive): username_taken',
                       'state.imported = the v1 archive hash'])


def bad_imports():
    out = []
    for why, make in [
        ('import hash does not match the state', lambda W, M: import_block(W, import_state(M), state_hash='0' * 64)),
        ('imported person with the manager\'s username', lambda W, M: import_block(
            W, import_state(M, {pid('other'): {'username': 'HASHIM', 'full_name': 'Clash', 'position': None,
                                               'role': 'user'}}))),
        ('imported state with an empty equipment field', lambda W, M: import_block(
            W, {**import_state(M), 'equipment': [['11LAB70AA501', {'floor': ''}]]})),
        ('imported persons not sorted by key', lambda W, M: import_block(
            W, {**import_state(M), 'persons': list(reversed(import_state(M)['persons']))})),
        ('import signed by another key', lambda W, M: {**import_block(W, import_state(M)),
                                                        'root_sig': R.sign_statement(W.key('fake-root'),
                                                                                     import_block(W, import_state(M))['stmt'])}),
    ]:
        W = World()
        M = pid('manager')
        W.genesis('mgr-laptop', 1000, M, 'hashim', 'Hashim M', imp=make(W, M))
        W.w('mgr-laptop', 1100, 'setting', {'key': 'x', 'value': 1})
        out.append(W.scenario(why, ['the genesis is ignored (bad_genesis or bad_root_sig): no plant, every later entry not_certified']))
    return out


def replay_file():
    V = {'protocol': 2, 'note': NOTE}
    root = P.key_from_seed(seed('root'))
    stmt = {'kind': 'manager', 'person': pid('manager')}
    V['statement'] = {'root_seed_hex': seed('root').hex(), 'root_private_scalar_hex': private_scalar_hex(root),
                      'root': P.key_string(root), 'root_id': P.peer_id(root), 'stmt': stmt,
                      'signed_bytes_hex': (R.STMT_DOMAIN + P.canonical(stmt)).hex(),
                      'root_sig': R.sign_statement(root, stmt)}
    secret = seed('bob-person-secret')
    V['private'] = {'secret_hex': secret.hex(), 'person': pid('bob'), 'nonce_hex': bytes(range(12)).hex(),
                    'plaintext': {'type': 'course_progress', 'body': {'course': 'hrsg', 'score': 7}},
                    'aad_hex': (R.PRIVATE_DOMAIN + pid('bob').encode()).hex(),
                    'body': R.private_body(secret, pid('bob'), 'course_progress', {'course': 'hrsg', 'score': 7},
                                           nonce=bytes(range(12)))}
    V['scenarios'] = [main_scenario(), stolen_manager_phone(), fork_gaps_keys(), withdraw_votes(), imported_plant(),
                      *bad_imports()]
    return V


# ====================================================================== v2-malformed
BAD = [None, True, False, 0, -1, 7, 2 ** 53 - 1, '', 'x', 'A' * 90, 'Ü☃', [], ['x'], [1, 2, 3, 4], {}, {'a': 1},
       {'kind': 'manager'}]


def malformed_file():
    W = World()
    M, A, U = pid('manager'), pid('ali'), pid('bob')
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M')
    W.w('mgr-phone', 1010, 'person', person(A, 'ali', 'Ali Admin', 'admin'))
    W.w('mgr-phone', 1020, 'person', person(U, 'bob', 'Bob User', 'user'))
    W.w('mgr-phone', 1030, 'device_cert', {'device': W.peer('ali-phone'), 'person': A, 'label': 'phone'})
    W.w('mgr-phone', 1040, 'device_cert', {'device': W.peer('bob-phone'), 'person': U, 'label': 'phone'})
    W.w('mgr-phone', 1050, 'device_cert', {'device': W.peer('victim'), 'person': U, 'label': 'spare'})
    prop = W.w('bob-phone', 1100, 'link', {'proc': 'p', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
    root_stmt = {'kind': 'manager', 'person': M}
    templates = {
        'person': lambda n: person(pid(f'p{n}'), f'user{n}', 'Some Name', 'user'),
        'device_cert': lambda n: {'device': W.peer(f'dev{n}'), 'person': U, 'label': 'x'},
        'revoke': lambda n: {'device': W.peer('victim'), 'last_seq': 5},
        'setting': lambda n: {'key': 'k', 'value': 1},
        'equipment': lambda n: {'kks': '11LAB70AA501', 'changes': {'notes': f'n{n}'}, 'base': {}},
        'review': lambda n: {'tag_id': 'lp:1', 'data': {'status': 'rejected'}, 'base': None},
        'link': lambda n: {'proc': 'p', 'step': n, 'kks': '11LAB70AA501', 'on': True},
        'photo': lambda n: {'photo': rid(f'ph{n}'), 'kks': '11LAB70AA501', 'blob': hashlib.sha256(b'x').hexdigest(), 'caption': ''},
        'photo_delete': lambda n: {'photo': rid(f'ph{n}')},
        'tag_add': lambda n: {'tag': rid(f't{n}'), 'sheet': 'lp', 'bbox': [0, 0, 10, 10], 'kks': None, 'suffix': '', 'isa': None, 'note': ''},
        'tag_remove': lambda n: {'tag': rid(f't{n}')},
        'approve': lambda n: {'entry': prop, 'edit': None},
        'reject': lambda n: {'entry': prop, 'note': ''},
        'withdraw': lambda n: {'entry': prop},
        'vote': lambda n: {'entry': prop, 'on': True},
        'comment': lambda n: {'entry': prop, 'text': 'why'},
        'private': lambda n: {'person': U, 'nonce': 'A' * 16, 'ct': 'B' * 22},
        'root': lambda n: {'stmt': dict(root_stmt), 'root_sig': R.sign_statement(W.root, root_stmt)},
    }
    nested = {
        'equipment': [('changes', 'notes'), ('base', 'notes'), ('changes', 'custom')],
        'tag_add': [('bbox', 0), ('bbox', 3)],
        'approve': [('edit',)],
        'root': [('stmt', 'kind'), ('stmt', 'person')],
    }
    t, n = 2000, 0
    for dev in ('bob-phone', 'ali-phone'):
        for type_, make in templates.items():
            fields = [(f,) for f in make(0)] + nested.get(type_, [])
            for path in fields:
                for bad in BAD:
                    n += 1; t += 1
                    body = make(n)
                    target = body
                    for k in path[:-1]:
                        target = target[k]
                    if isinstance(target, list) and path[-1] >= len(target):
                        continue
                    target[path[-1]] = bad
                    W.w(dev, t, type_, body)
            n += 1; t += 1
            body = make(n); body.pop(next(iter(body)))
            W.w(dev, t, type_, body)
            n += 1; t += 1
            W.w(dev, t, type_, {**make(n), 'extra': 1})
        n += 1; t += 1
        W.w(dev, t, 'no_such_type', {})
    s = W.scenario('malformed bodies from a user and an admin', ['nothing crashes; every entry is applied or ignored with a reason'])
    return {'protocol': 2, 'note': NOTE, 'bad_values': BAD, 'scenarios': [s]}


# ====================================================================== v2-crypto
def crypto_file():
    V = {'protocol': 2, 'note': NOTE}
    joiner, answering = P.key_from_seed(seed('new-phone')), P.key_from_seed(seed('admin-laptop'))
    V['join_code'] = [{'joiner': P.peer_id(joiner), 'answering': P.peer_id(answering),
                       'code': C.join_code(P.peer_id(joiner), P.peer_id(answering))},
                      {'joiner': P.peer_id(answering), 'answering': P.peer_id(joiner),
                       'code': C.join_code(P.peer_id(answering), P.peer_id(joiner))}]
    req = C.join_request(joiner, 'dana', 'Dana User', None, 'phone', 1790000000)
    tampered = dict(req, username='mallory')
    V['join_request'] = {'valid': req, 'reject': [{'why': 'tampered', 'request': tampered},
                                                  {'why': 'device is not the key\'s peer ID',
                                                   'request': dict(req, device=P.peer_id(answering))}]}
    root = P.key_from_seed(seed('root'))
    room = C.relay_room(P.key_string(root))
    hello = C.relay_hello(joiner, room, 1790000000)
    V['relay'] = {'root': P.key_string(root), 'root_id': P.peer_id(root), 'room': room, 'hello': hello, 'now': 1790000100,
                  'reject': [{'why': 'too old', 'hello': hello, 'now': 1790000301},
                             {'why': 'another room', 'hello': C.relay_hello(joiner, '0' * 32, 1790000000),
                              'now': 1790000000}]}
    backup = P.key_from_seed(seed('backup'))
    eph = P.key_from_seed(seed('ecies-ephemeral'))
    sealed = C.ecies_seal(P.key_string(backup), 'backup', b'plant backup bytes \xe2\x98\x83', eph=eph,
                          nonce=bytes(range(12)))
    assert C.ecies_open(backup, sealed) == b'plant backup bytes \xe2\x98\x83'
    V['ecies'] = {'recipient_private_scalar_hex': private_scalar_hex(backup), 'recipient': P.key_string(backup),
                  'ephemeral_private_scalar_hex': private_scalar_hex(eph), 'purpose': 'backup',
                  'plaintext_hex': b'plant backup bytes \xe2\x98\x83'.hex(), 'sealed': sealed}
    pp = 'correct horse battery staple ocean lamp'
    sealed_pp = C.passphrase_seal(pp, bytes.fromhex(private_scalar_hex(root)), salt=bytes(range(16)),
                                  nonce=bytes(range(12)))
    assert C.passphrase_open(pp, sealed_pp) == bytes.fromhex(private_scalar_hex(root))
    V['root_backup'] = {'passphrase': pp, 'plaintext_hex': private_scalar_hex(root), 'sealed': sealed_pp}
    return V


FILES = {'v2-core.json': core, 'v2-replay.json': replay_file, 'v2-malformed.json': malformed_file,
         'v2-crypto.json': crypto_file}


if __name__ == '__main__':
    for name, build in FILES.items():
        text = dump(build())
        if '--write' in sys.argv:
            os.makedirs(DIR, exist_ok=True)
            with open(os.path.join(DIR, name), 'w', encoding='utf-8') as f:
                f.write(text)
        print(name, len(text) // 1024, 'KB')
