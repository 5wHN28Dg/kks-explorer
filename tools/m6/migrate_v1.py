#!/usr/bin/env python3
"""v1 → v2 migration, step 1 of 2 (PROTOCOL-v2 §21): read a COPY of a v1 plant.db, verify its log completely under v1
rules, and write a migration package the Nim server imports (`kks-server import-v1 PACKAGE`).

  python3 tools/m6/migrate_v1.py export --db COPY.db --photos PHOTOS_DIR --out package.json
  python3 tools/m6/migrate_v1.py compare --package package.json --v2-state state.json

Never run it on the live plant.db: copy it first (the tool only reads, but a copy is the rule). The package holds the
plant's data (unencrypted) and password hashes: keep it with the same care as plant.db, and delete it after.

`compare` checks the imported state against v1's: persons (with roles; the manager's role is `manager` in both),
settings, equipment, reviews, links, photos, added tags. Devices, proposals and votes are not imported (§21)."""
import argparse, base64, hashlib, json, os, sqlite3, sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from peer import proto as P
from peer import replay as R


def canonical(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()


def pairs(d):
    return [[k, d[k]] for k in sorted(d)]


def load_v1(db):
    c = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
    c.row_factory = sqlite3.Row
    meta = {r['k']: r['v'] for r in c.execute('SELECT k, v FROM meta')}
    if meta.get('log_version') != '1':
        raise SystemExit('this database is not a v1 log database (meta log_version is not 1)')
    root = json.loads(meta['root_pub'])
    entries = [json.loads(r['data']) for r in c.execute('SELECT data FROM entries')]
    users = [dict(r) for r in c.execute('SELECT * FROM users')]
    blobs = {r['sha']: r['file'] for r in c.execute('SELECT * FROM blobs')} if 'blobs' in {
        r[0] for r in c.execute("SELECT name FROM sqlite_master WHERE type='table'")} else {}
    c.close()
    return root, entries, users, blobs


def export(args):
    root, entries, users, blobs = load_v1(args.db)
    # 1. verify under v1 rules (no trusted shortcut) and look for anything still open
    run, chain_ignored = R.replay_run(entries, root)
    if chain_ignored:
        raise SystemExit(f'{len(chain_ignored)} v1 entries do not verify: {sorted(set(chain_ignored.values()))}')
    pending = [e for e, st in run.proposals.items() if st == 'pending']
    if pending:
        raise SystemExit(f'{len(pending)} proposal(s) are still pending: decide them in v1 first (§21 step 1)')
    # 2. the archive hash: v1 entry IDs in v1 total order
    ordered = sorted(entries, key=P.order_key)
    h = hashlib.sha256(canonical([P.entry_id(e) for e in ordered])).hexdigest()
    # 3. the imported state (§21 pair form); the manager is imported as admin, the genesis makes them manager
    manager = run.manager
    persons = {pid: {'username': p['username'], 'full_name': p['full_name'], 'position': p['position'],
                     'role': 'admin' if pid == manager else p['role']} for pid, p in run.persons.items()}
    settings = {k: v for k, v in run.settings.items() if k != 'plant'}
    state = {'persons': pairs(persons), 'settings': pairs(settings), 'equipment': pairs(run.equipment),
             'reviews': pairs(run.reviews), 'links': [list(x) for x in sorted(run.links)],
             'photos': pairs({k: {'kks': v['kks'], 'blob': v['blob'], 'caption': v['caption']} for k, v in run.photos.items()}),
             'added_tags': pairs(run.tags)}
    mp = run.persons[manager]
    # accounts: carried with their v1 password hashes (scrypt; the server rehashes to Argon2id at the next login)
    accounts = [{k: u.get(k) for k in ('username', 'pw', 'active', 'created', 'full_name', 'position', 'person')}
                for u in users if u.get('person')]
    # blobs: every file the v1 node holds (photos, plant data)
    out_blobs = {}
    for sha, name in sorted(blobs.items()):
        path = os.path.join(args.photos, name)
        if not os.path.isfile(path):
            raise SystemExit(f'blob {sha} ({name}) is missing from {args.photos}')
        with open(path, 'rb') as f:
            data = f.read()
        if hashlib.sha256(data).hexdigest() != sha:
            raise SystemExit(f'blob {name} does not hash to {sha}')
        out_blobs[sha] = base64.b64encode(data).decode()
    pkg = {'kks_migration': 1, 'v1_hash': h, 'v1_entries': len(entries), 'plant': run.settings.get('plant') or 'Plant',
           'manager': {'person': manager, 'username': mp['username'], 'full_name': mp['full_name'], 'position': mp['position']},
           'import_state': state, 'accounts': accounts, 'blobs': out_blobs,
           'v1_state': {'persons': run.persons, 'manager': manager, 'settings': run.settings, 'equipment': run.equipment,
                        'reviews': run.reviews, 'links': [list(x) for x in sorted(run.links)], 'photos': run.photos,
                        'added_tags': run.tags}}
    with open(args.out, 'w', encoding='utf-8') as f:
        json.dump(pkg, f, ensure_ascii=False)
    os.chmod(args.out, 0o600)
    print(f'v1: {len(entries)} entries verified, archive hash {h[:16]}…; {len(persons)} persons, {len(run.equipment)} '
          f'equipment, {len(run.reviews)} reviews, {len(run.links)} links, {len(run.photos)} photos, {len(run.tags)} '
          f'added tags, {len(accounts)} accounts, {len(out_blobs)} blobs → {args.out}')


def compare(args):
    with open(args.package, encoding='utf-8') as f:
        v1 = json.load(f)['v1_state']
    with open(args.v2_state, encoding='utf-8') as f:
        v2 = json.load(f)
    bad = []
    for k in ('equipment', 'reviews', 'links', 'photos', 'added_tags'):
        if v1[k] != v2[k]:
            bad.append(k)
    pv1 = {p: {**v, 'role': 'manager' if p == v1['manager'] else v['role']} for p, v in v1['persons'].items()}
    pv2 = {p: {k: v[k] for k in ('username', 'full_name', 'position')} | {'role': 'manager' if p == v2['manager'] else v['role']}
           for p, v in v2['persons'].items()}
    pv1 = {p: {k: v[k] for k in ('username', 'full_name', 'position', 'role')} for p, v in pv1.items()}
    if pv1 != pv2:
        bad.append('persons')
    if v1['manager'] != v2['manager']:
        bad.append('manager')
    if v1['settings'] != v2['settings']:
        bad.append('settings')
    if bad:
        raise SystemExit('DIFFERENT: ' + ', '.join(bad))
    print('identical: persons (with roles), manager, settings, equipment, reviews, links, photos, added tags')


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    e = sub.add_parser('export')
    e.add_argument('--db', required=True)
    e.add_argument('--photos', required=True)
    e.add_argument('--out', required=True)
    c = sub.add_parser('compare')
    c.add_argument('--package', required=True)
    c.add_argument('--v2-state', required=True)
    a = ap.parse_args()
    export(a) if a.cmd == 'export' else compare(a)


if __name__ == '__main__':
    main()
