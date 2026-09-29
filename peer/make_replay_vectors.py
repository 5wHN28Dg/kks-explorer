#!/usr/bin/env python3
"""Generate peer/vectors/v2-replay.json: replay vectors for protocol v1 §8–14 (docs/PROTOCOL.md).

Deterministic (fixed seeds, fixed clocks, fixed nonces). FROZEN once committed, like v1.json: regenerating must give
identical bytes (tests/test_protocol.py). Each scenario = entries (sorted by entry ID, so an implementation has to
order them itself) + the expected state; `expect` says in words what the scenario checks.
  .venv/bin/python peer/make_replay_vectors.py [--write]"""
import hashlib, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peer import proto as P
from peer import replay as R
from peer.make_vectors import dump, seed

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'v2-replay.json')
T0 = 1790000000000


def pid(name):
    return hashlib.sha256(b'kks-vector-person:' + name.encode()).hexdigest()[:32]


def rid(name):   # photo / tag ids
    return hashlib.sha256(b'kks-vector-id:' + name.encode()).hexdigest()[:32]


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

    def stmt(self, stmt, key=None):
        return {'stmt': stmt, 'root_sig': R.sign_statement(key or self.root, stmt)}

    def genesis(self, dev, t, person, username, full_name, position=None, root=None):
        sm = {'kind': 'manager', 'person': person}
        sd = {'kind': 'device', 'device': self.peer(dev), 'person': person}
        return self.w(dev, t, 'genesis', {
            'plant': 'Test plant', 'root': P.peer_id(root or self.root),
            'manager': {'person': person, 'username': username, 'full_name': full_name, 'position': position},
            'stmt_manager': sm, 'stmt_device': sd,
            'sig_manager': R.sign_statement(root or self.root, sm), 'sig_device': R.sign_statement(root or self.root, sd)})

    def scenario(self, why, expect, extra=()):
        entries = sorted(self.entries + list(extra), key=P.entry_id)
        return {'why': why, 'expect': expect, 'root': P.peer_id(self.root),
                'devices': {n: self.peer(n) for n in sorted(self.logs)},
                'entries': entries, 'state': R.replay(entries, P.peer_id(self.root))}


def person(p, username, full_name, role, position=None):
    return {'person': p, 'username': username, 'full_name': full_name, 'position': position, 'role': role}


def main_scenario():
    W = World()
    M, A, B, C = pid('manager'), pid('ali'), pid('bob'), pid('carol')
    secret = seed('bob-person-secret')

    # an impostor's genesis for a different root key
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
    W.w('mgr-laptop', 1800, 'approve', {'entry': p2, 'edit': None})                       # already_decided

    W.w('ali-phone', 1900, 'equipment', {'kks': '11LAB70AA501', 'changes': {'floor': '6 m'}, 'base': {'floor': '3 m'}})
    W.w('mgr-laptop', 2000, 'equipment', {'kks': '11LAB70AA501', 'changes': {'notes': 'manager note'}, 'base': {'notes': ''}})
    W.w('ali-phone', 2100, 'equipment', {'kks': '11LAB70AA501', 'changes': {'notes': 'admin note'}, 'base': {'notes': 'near pump'}})
    W.w('ali-phone', 2150, 'equipment', {'kks': '11LBA10AA402', 'changes': {'custom': [{'k': 'Size', 'v': 'DN50'}], 'loc': 'x'}, 'base': {}})
    W.w('ali-phone', 2160, 'equipment', {'kks': '11LBA10AA402', 'changes': {'custom': [], 'loc': ''}, 'base': {'custom': [{'k': 'Size', 'v': 'DN50'}], 'loc': 'x'}})

    p3 = W.w('bob-phone', 2200, 'tag_add', {'tag': rid('t1'), 'sheet': 'hp', 'bbox': [1000, 2000, 1800, 2400],
                                            'kks': '11HAH90CT103', 'suffix': '', 'isa': 'TI', 'note': 'missed'})
    W.w('mgr-laptop', 2300, 'approve', {'entry': p3, 'edit': {'kks': '11HAH90CT103', 'suffix': 'K', 'isa': 'TE'}})
    photo = {'photo': rid('ph1'), 'kks': '11LAB70AA501', 'blob': hashlib.sha256(b'jxl bytes').hexdigest(), 'caption': 'valve'}
    # approve comes before the proposal in the order (bob's clock is behind): waits, applies at the proposal
    p4_id = P.entry_id(P.make_entry(W.key('bob-phone'), len(W.logs['bob-phone'].entries) + 1,
                                    P.entry_id(W.logs['bob-phone'].entries[-1]),
                                    [T0 + 2400, 0], 'photo', photo))
    W.w('ali-phone', 2350, 'approve', {'entry': p4_id, 'edit': None})
    assert W.w('bob-phone', 2400, 'photo', photo) == p4_id
    p6 = W.w('bob-phone', 2410, 'review', {'tag_id': 'hp:12', 'data': {'status': 'confirmed', 'kks': '11LAB90AA301'}, 'base': None})
    W.w('ali-phone', 2420, 'approve', {'entry': p6, 'edit': {'kks': '11LAB90AA301', 'suffix': '', 'isa': None}})  # edit on non-tag → rejected

    W.w('ali-phone', 2500, 'person', person(C, 'carol', 'Carol C', 'admin'))                # admin can't create admins
    W.w('ali-phone', 2510, 'setting', {'key': 'photo_mode', 'value': 'all'})                # only the manager
    W.w('mgr-phone', 2600, 'setting', {'key': 'photo_mode', 'value': 'on_open'})
    W.w('mgr-phone', 2650, 'person', person(pid('bob2'), 'Bob', 'Bob Two', 'user'))         # username_taken
    W.w('mgr-phone', 2660, 'person', person(C, 'carol', 'Carol C', 'user'))

    W.w('bob-phone', 2700, 'device_cert', {'device': W.peer('bob-tablet'), 'person': B, 'label': 'tablet'})
    W.w('bob-phone', 2710, 'device_cert', {'device': W.peer('evil'), 'person': A, 'label': 'x'})   # not_allowed
    W.w('bob-tablet', 2800, 'private', R.private_body(secret, B, 'course_progress', {'course': 'hrsg', 'score': 7},
                                                       nonce=bytes(range(12))))
    W.w('bob-tablet', 2810, 'private', R.private_body(secret, A, 'course_progress', {}, nonce=bytes(12)))  # not_allowed
    W.w('bob-tablet', 2850, 'person', person(B, 'bob', 'Bob Bobson', 'user', 'Technician'))  # own details
    W.w('bob-tablet', 2855, 'person', person(B, 'bob', 'Bob Bobson', 'admin'))                # own role: not_allowed
    W.w('bob-tablet', 2860, 'approve', {'entry': p1, 'edit': None})                          # users don't approve

    # bob's phone is stolen after its current last entry; later entries never count, approved or not
    last_good = len(W.logs['bob-phone'].entries)
    p5 = W.w('bob-phone', 2900, 'equipment', {'kks': '11LAB70AA501', 'changes': {'area': 'stolen'}, 'base': {}})
    W.w('bob-phone', 2950, 'revoke', {'device': W.peer('bob-tablet'), 'last_seq': 0})         # user rank, loses
    W.w('ali-phone', 3000, 'approve', {'entry': p5, 'edit': None})
    W.w('ali-phone', 3100, 'revoke', {'device': W.peer('bob-phone'), 'last_seq': last_good})
    W.w('bob-tablet', 3150, 'link', {'proc': 'p12', 'step': 4, 'kks': '11LAB70AA501', 'on': True})
    W.w('mgr-laptop', 3160, 'link', {'proc': 'p12', 'step': 5, 'kks': '11LAB70AA501', 'on': True})
    W.w('mgr-laptop', 3165, 'tag_add', {'tag': rid('t2'), 'sheet': 'lp', 'bbox': [0, 0, 10, 10],
                                        'kks': None, 'suffix': '', 'isa': None, 'note': ''})
    W.w('mgr-laptop', 3170, 'tag_remove', {'tag': rid('t2')})

    W.w('mgr-phone', 3200, 'note', {'text': 'unknown type'})
    W.w('mgr-phone', 3210, 'equipment', {'kks': '11lab70', 'changes': {'area': 'x'}, 'base': {}})   # bad_body
    W.w('mgr-phone', 3220, 'setting', {'key': 'k', 'value': 1, 'extra': 2})                          # bad_body

    root2 = W.key('root-2')
    W.w('mgr-laptop', 3300, 'root', W.stmt({'kind': 'rotate', 'root': P.peer_id(root2)}))
    W.w('mgr-laptop', 3400, 'root', W.stmt({'kind': 'manager', 'person': A}))                 # old key: bad_root_sig
    W.w('mgr-laptop', 3500, 'root', W.stmt({'kind': 'device', 'device': W.peer('mgr-tablet'), 'person': M}, root2))
    W.w('mgr-tablet', 3600, 'setting', {'key': 'shared_note', 'value': {'text': 'ÜML ☃', 'n': [1, 2]}})
    W.w('ali-phone', 3700, 'equipment', {'kks': '11LAB70AA501', 'changes': {'floor': '9 m'}, 'base': {'floor': '3 m'}})  # admin over admin: new wins
    return W.scenario(
        'one plant: identity, proposals, approvals, merge, revocation, rotation',
        ['impostor genesis for another root: bad_genesis', 'bob-phone entry before its cert: not_certified',
         'p1 approved by ali; p2 rejected first, the later approve is already_decided',
         'notes: manager value beats the admin write that did not see it (conflict kept=manager)',
         'custom and loc emptied → 11LBA10AA402 removed', 'tag_add approved with edit → suffix K, isa TE; a manager tag added then removed',
         'photo approve before its proposal: waits, applies', 'edit on a review proposal → rejected',
         'admin creating an admin / writing a setting: not_allowed', 'duplicate username (case-insensitive): username_taken',
         'private entry under own person counted, under another person not_allowed',
         'bob-phone revoked by ali after its tablet cert: later proposal, its approve and the phone\'s own revoke of the tablet do not count',
         'root rotation: a later statement signed by the old key is bad_root_sig; the new key certifies mgr-tablet',
         'floor 9 m by ali over her own 6 m with a stale base: conflict, new wins (both admin)'])


def stolen_manager_phone():
    W = World()
    M = pid('manager')
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M')
    W.w('mgr-phone', 1100, 'device_cert', {'device': W.peer('mgr-laptop'), 'person': M, 'label': 'laptop'})
    # phone stolen after seq 2; the thief revokes the laptop first and changes a setting
    W.w('mgr-phone', 2000, 'revoke', {'device': W.peer('mgr-laptop'), 'last_seq': 0})
    W.w('mgr-phone', 2100, 'setting', {'key': 'photo_mode', 'value': 'thief'})
    W.w('mgr-laptop', 2500, 'revoke', {'device': W.peer('mgr-phone'), 'last_seq': 2})      # same rank, later: loses alone
    W.w('mgr-laptop', 2600, 'root', W.stmt({'kind': 'revoke', 'device': W.peer('mgr-phone'), 'last_seq': 2}))
    W.w('mgr-laptop', 2700, 'setting', {'key': 'photo_mode', 'value': 'on_open'})
    return W.scenario('stolen manager phone: a root-signed revoke outranks device revokes',
                      ['phone cut at 2; its revoke of the laptop and its setting are revoked',
                       'laptop entries all count; photo_mode = on_open'])


def fork_and_gaps():
    W = World()
    M, B = pid('manager'), pid('bob')
    W.genesis('mgr-phone', 1000, M, 'hashim', 'Hashim M')
    W.w('mgr-phone', 1100, 'person', person(B, 'bob', 'Bob User', 'user'))
    W.w('mgr-phone', 1200, 'device_cert', {'device': W.peer('bob-phone'), 'person': B, 'label': ''})
    W.w('bob-phone', 1300, 'link', {'proc': 'p1', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
    log = W.logs['bob-phone']
    W.w('bob-phone', 1400, 'link', {'proc': 'p1', 'step': 2, 'kks': '11LAB70AA501', 'on': True})
    fork = P.make_entry(W.key('bob-phone'), 2, P.entry_id(log.entries[0]), [T0 + 1400, 0], 'link',
                        {'proc': 'p1', 'step': 9, 'kks': '11LAB70AA501', 'on': True})
    W.w('bob-phone', 1500, 'link', {'proc': 'p1', 'step': 3, 'kks': '11LAB70AA501', 'on': True})
    # mgr-laptop: seq 2 present but seq 1 missing → waits (chain_gap)
    lap = P.Log(W.key('mgr-laptop'))
    lap.append('setting', {'key': 'a', 'value': 1}, T0 + 1000)
    gap = lap.append('setting', {'key': 'b', 'value': 2}, T0 + 1100)
    bad = dict(W.logs['mgr-phone'].entries[1], sig=W.logs['mgr-phone'].entries[2]['sig'])  # bad_sig
    W.logs['mgr-laptop'] = lap
    return W.scenario('fork, gap, bad signature',
                      ['bob-phone forked at seq 2: cut at 1, both seq 2 entries and seq 3 are fork evidence',
                       'mgr-laptop seq 2 without seq 1: chain_gap', 'entry with a wrong signature: bad_sig'],
                      extra=[fork, gap, bad])


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
    W.w('bob-phone', 1420, 'vote', {'entry': b, 'on': False})                              # changed their mind
    W.w('dana-phone', 1500, 'withdraw', {'entry': a})                                      # not hers: not_allowed
    W.w('bob-phone', 1510, 'withdraw', {'entry': a})
    W.w('mgr-phone', 1520, 'approve', {'entry': a, 'edit': None})                          # already_decided
    W.w('mgr-phone', 1600, 'approve', {'entry': b, 'edit': None})
    W.w('mgr-phone', 1700, 'review', {'tag_id': 'lp:7', 'data': {'status': 'rejected'}, 'base': None})
    r = W.w('bob-phone', 1800, 'review', {'tag_id': 'lp:7', 'data': None, 'base': {'status': 'rejected'}})
    W.w('mgr-phone', 1900, 'approve', {'entry': r, 'edit': None})
    # a withdraw written before its proposal in the order (other device, clock behind) waits for it
    W.w('mgr-phone', 1950, 'device_cert', {'device': W.peer('bob-laptop'), 'person': B, 'label': 'laptop'})
    late = P.make_entry(W.key('bob-phone'), len(W.logs['bob-phone'].entries) + 1,
                        P.entry_id(W.logs['bob-phone'].entries[-1]), [T0 + 2100, 0], 'link',
                        {'proc': 'p1', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
    W.w('bob-laptop', 2000, 'withdraw', {'entry': P.entry_id(late)})
    assert W.w('bob-phone', 2100, 'link', late['body']) == P.entry_id(late)
    return W.scenario('withdraw, votes, review removal',
                      ['photo a withdrawn by its author (another user can\'t); a later approve is already_decided',
                       'votes: dana on a; bob\'s vote on b switched off again → votes {a: [dana]} only',
                       'an approved user proposal with data null removes the review',
                       'a withdraw from the author\'s other device, earlier in the order, waits and applies'])


def build():
    V = {'protocol': 1, 'note': 'Replay vectors (docs/PROTOCOL.md §8–14). Reproduce every value exactly.'}
    root = P.key_from_seed(seed('root'))
    stmt = {'kind': 'manager', 'person': pid('manager')}
    V['statement'] = {'root_seed_hex': seed('root').hex(), 'root': P.peer_id(root), 'stmt': stmt,
                      'signed_bytes_hex': (R.STMT_DOMAIN + P.canonical(stmt)).hex(), 'root_sig': R.sign_statement(root, stmt)}
    secret = seed('bob-person-secret')
    V['private'] = {'secret_hex': secret.hex(), 'person': pid('bob'), 'nonce_hex': bytes(range(12)).hex(),
                    'plaintext': {'type': 'course_progress', 'body': {'course': 'hrsg', 'score': 7}},
                    'aad_hex': (R.PRIVATE_DOMAIN + pid('bob').encode()).hex(),
                    'body': R.private_body(secret, pid('bob'), 'course_progress', {'course': 'hrsg', 'score': 7},
                                           nonce=bytes(range(12)))}
    V['scenarios'] = [main_scenario(), stolen_manager_phone(), fork_and_gaps(), withdraw_votes()]
    return V


if __name__ == '__main__':
    text = dump(build())
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
        print('wrote', OUT)
    else:
        print(text[:3000])
