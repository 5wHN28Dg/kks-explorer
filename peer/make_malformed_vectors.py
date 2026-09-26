#!/usr/bin/env python3
"""Generate peer/vectors/v4-malformed.json: every entry type with every field replaced by every kind of wrong value
(and missing/extra fields, and nested fields), written by a user's and an admin's device, then the replayed state.
Two implementations must agree on each one, and neither may crash: a certified device writing garbage must only
get its entries ignored (in 2026-09 three such bodies crashed the Python replay). FROZEN once committed.
  .venv/bin/python peer/make_malformed_vectors.py [--write]"""
import hashlib, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peer import proto as P
from peer import replay as R
from peer.make_replay_vectors import World, person, pid, rid
from peer.make_vectors import dump

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'vectors', 'v4-malformed.json')
BAD = [None, True, False, 0, -1, 7, 2 ** 53 - 1, '', 'x', 'A' * 90, 'Ü☃', [], ['x'], [1, 2, 3, 4], {}, {'a': 1},
       {'kind': 'manager'}]


def build():
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
        'private': lambda n: {'person': U, 'nonce': 'A' * 16, 'ct': 'B' * 22},
        'root': lambda n: {'stmt': dict(root_stmt), 'root_sig': R.sign_statement(W.root, root_stmt)},
    }
    nested = {   # (type, path to a nested field)
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
            body = make(n); body.pop(next(iter(body)))                  # a field missing
            W.w(dev, t, type_, body)
            n += 1; t += 1
            W.w(dev, t, type_, {**make(n), 'extra': 1})                  # a field too many
        n += 1; t += 1
        W.w(dev, t, 'no_such_type', {})
    s = W.scenario('malformed bodies from a user and an admin', ['nothing crashes; every entry is applied or ignored with a reason'])
    return {'protocol': 1, 'note': 'Malformed entry bodies (docs/PROTOCOL.md §9a, §11). Reproduce the state exactly.',
            'bad_values': BAD, 'scenarios': [s]}


if __name__ == '__main__':
    V = build()
    text = dump(V)
    st = V['scenarios'][0]['state']
    print(f'{len(V["scenarios"][0]["entries"])} entries; ignored {len(st["ignored"])}; reasons',
          sorted({r for r in st['ignored'].values()}))
    if '--write' in sys.argv:
        with open(OUT, 'w', encoding='utf-8') as f:
            f.write(text)
        print('wrote', OUT, len(text) // 1024, 'KB')
