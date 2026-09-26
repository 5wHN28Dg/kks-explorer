"""One-time move of a pre-log database (tables equipment, photos, reviews, links, added_tags, submissions, votes,
revisions) onto the signed log (M1, 2026-09-26).

- A copy of the old database is kept first: backups/plant-v1-<time>.db.
- Accounts become persons with custodial device keys; the manager signs the genesis with a new root key.
- History is rebuilt from the revision log with its original times and people: an approved user submission becomes
  the user's proposal + the admin's approval; an admin's change becomes the admin's entry; a revert/restore by an
  admin becomes that admin's entry. Open, rejected and withdrawn submissions and photo votes carry over. Submission
  numbers and client IDs stay the same (offline phones may still replay them).
- Before committing, the new log is replayed and compared with the old live tables; any difference aborts the whole
  migration (nothing is written, the server does not start) and says what differed."""
import hashlib, json, os, secrets, sqlite3, time

from peer import proto as P
from peer import replay as R
from server.engine import ENTITIES, default, payload_to_body
from server.store import KEYS

DATA_TABLES = ('equipment', 'photos', 'reviews', 'links', 'added_tags', 'submissions', 'votes')


class MigrationError(SystemExit):
    pass


def needed(E):
    """Only a database from before the log: accounts, but no log entries at all. (A node that got its plant by
    joining has log entries; it must never be "migrated" into a plant of its own.)"""
    if E.store.meta('log_version') is not None:
        return False
    c = E.store.conn()
    try:
        if c.execute('SELECT COUNT(*) FROM entries').fetchone()[0] or E.anchor is not None:
            return False
        return c.execute('SELECT COUNT(*) FROM users').fetchone()[0] > 0
    finally:
        c.close()


def _old_state(c):
    """The old live tables, in the replay's internal form."""
    return {
        'equipment': {r['kks']: json.loads(r['data']) for r in c.execute('SELECT * FROM equipment')},
        'reviews': {r['tag_id']: json.loads(r['data']) for r in c.execute('SELECT * FROM reviews')},
        'links': sorted((r['proc'], r['step'], r['kks']) for r in c.execute('SELECT * FROM links')),
        'photos': {r['id']: (r['kks'], r['caption'] or '') for r in c.execute('SELECT * FROM photos')},
        'added_tags': {r['id']: _tag_body(json.loads(r['data'])) for r in c.execute('SELECT * FROM added_tags')},
    }


def _tag_body(p):
    b = payload_to_body('tag_add', {'id': 'x', 'suffix': '', 'isa': None, 'note': '', **p})
    del b['tag']
    return b


def _new_state(run):
    return {'equipment': run.equipment, 'reviews': run.reviews, 'links': sorted(run.links),
            'photos': {k: (v['kks'], v['caption']) for k, v in run.photos.items()}, 'added_tags': run.tags}


def run(E):
    store, cfg = E.store, E.cfg
    stamp = time.strftime('%Y%m%d-%H%M%S')
    copy = os.path.join(cfg['backup_dir'], f'plant-v1-{stamp}.db')
    src, dst = store.conn(), sqlite3.connect(copy)
    src.backup(dst)
    dst.close()
    old = _old_state(src)
    src.close()
    blobs = {}   # photo file → sha

    def blob(file):
        if file not in blobs:
            try:
                with open(os.path.join(cfg['photos_dir'], file), 'rb') as f:
                    data = f.read()
            except OSError:
                raise MigrationError(f'migration: photo file {file} is missing from {cfg["photos_dir"]}; restore it first')
            blobs[file] = (hashlib.sha256(data).hexdigest(), len(data))
        return blobs[file][0]

    with E.tx() as c:
        users = [dict(r) for r in c.execute('SELECT * FROM users ORDER BY id')]
        by_id = {u['id']: u for u in users}
        mgr = next((u for u in users if u['role'] == 'manager'), None) or \
            next((u for u in users if u['role'] == 'admin'), users[0])
        mgr['role'] = 'manager'   # (only changes anything for a database that had lost its manager)
        revs = c.execute("SELECT * FROM revisions WHERE entity IN (%s) ORDER BY rev" % ','.join('?' * len(ENTITIES)),
                         ENTITIES).fetchall()
        subs = {s['id']: dict(s) for s in c.execute('SELECT * FROM submissions ORDER BY id')}
        times = [u['created'] for u in users if u['created']] + [r['ts'] for r in revs] + \
            [s['created'] for s in subs.values() if s['created']]
        wall0 = (min(times) - 1) * 1000 if times else int(time.time() * 1000)

        # identities
        for u in users:
            u['person'] = secrets.token_hex(16)
            u['log_role'] = 'admin' if u['role'] in ('manager', 'admin') else 'user'
            u['full_name'] = (u['full_name'] or u['username'])[:80]
        mgr['log_role'] = 'manager'
        mgr['device'] = E.genesis(c, mgr['person'], mgr['username'], mgr['full_name'], mgr['position'] or None,
                                  cfg['plant_name'], wall0)
        for u in users:
            if u is mgr:
                continue
            E.append(c, mgr['device'], 'person', {'person': u['person'], 'username': u['username'],
                                                   'full_name': u['full_name'], 'position': u['position'] or None,
                                                   'role': u['log_role']}, wall0)
            u['device'] = E.new_device(c, u['person'])
            E.append(c, mgr['device'], 'device_cert', {'device': u['device'], 'person': u['person'], 'label': 'server'}, wall0)

        def dev(uid, need_admin=False):
            u = by_id.get(uid)
            if not u or (need_admin and u['log_role'] == 'user'):
                return mgr['device']
            return u['device']

        def is_user(uid):
            return by_id.get(uid, {}).get('log_role') == 'user'

        def diff_body(r):
            """The change a revision made, as an entry body."""
            ent, key = r['entity'], r['key']
            before = json.loads(r['before']) if r['before'] else None
            after = json.loads(r['after']) if r['after'] else None
            if ent == 'equipment':
                b, a = before or {}, after or {}
                ch = {f: a.get(f, default(f)) for f in sorted(set(a) | set(b)) if a.get(f, default(f)) != b.get(f, default(f))}
                return ('equipment', {'kks': key, 'changes': ch, 'base': {f: b.get(f, default(f)) for f in ch}}) if ch else None
            if ent == 'review':
                return 'review', {'tag_id': key, 'data': after, 'base': before}
            if ent == 'link':
                proc, step, kks = json.loads(key)
                return 'link', {'proc': proc, 'step': step, 'kks': kks, 'on': after is not None}
            if ent == 'photo':
                if after is None:
                    return 'photo_delete', {'photo': key}
                return 'photo', {'photo': key, 'kks': after['kks'], 'blob': blob(after['file']), 'caption': after.get('caption') or ''}
            if after is None:
                return 'tag_remove', {'tag': key}
            return 'tag_add', {'tag': key, **_tag_body(after)}

        def sub_body(s):
            p = json.loads(s['payload'])
            if s['kind'] == 'photo':
                p['blob'] = blob(p['file'])
            return s['kind'], payload_to_body(s['kind'], p)

        # events on one timeline, in the order they happened
        events, used = [], set()
        for r in revs:
            s = subs.get(r['submission_id'])
            if s and is_user(s['user_id']):
                if s['id'] in used:
                    continue   # one change per submission
                used.add(s['id'])
                events.append((s['created'] or r['ts'], 'propose', s, diff_body(r)))
                events.append((r['ts'], 'approve', s, r))
            else:
                events.append((r['ts'], 'direct', s, r))
                if s:
                    used.add(s['id'])
        for s in subs.values():
            if s['id'] in used:
                continue
            if is_user(s['user_id']):
                events.append((s['created'], 'propose', s, sub_body(s)))
                if s['status'] in ('approved', 'rejected', 'withdrawn'):
                    events.append((s['decided_at'] or s['created'], s['status'], s, None))
            else:
                events.append((s['created'], 'held', s, None))
        events.sort(key=lambda ev: ev[0])   # stable: same second keeps the order above

        entry_of = {}   # old submission id → entry id
        for ts, kind, s, x in events:
            wall = ts * 1000
            if kind == 'propose':
                if x is None:
                    continue
                entry_of[s['id']] = E.append(c, dev(s['user_id']), x[0], x[1], wall)
            elif kind == 'approve':
                if s['id'] in entry_of:
                    eid = E.append(c, dev(x['actor'], True), 'approve', {'entry': entry_of[s['id']], 'edit': None}, wall)
                    E.note(eid, x['note'])
            elif kind == 'direct':
                b = diff_body(x)
                if b:
                    eid = E.append(c, dev(x['actor'], True), b[0], b[1], wall)
                    E.note(eid, x['note'])
                    if s:
                        entry_of.setdefault(s['id'], eid)
            elif kind in ('approved', 'rejected', 'withdrawn'):
                if s['id'] not in entry_of:
                    continue
                if kind == 'withdrawn':
                    E.append(c, dev(s['user_id']), 'withdraw', {'entry': entry_of[s['id']]}, wall)
                elif kind == 'rejected':
                    E.append(c, dev(s['decided_by'], True), 'reject', {'entry': entry_of[s['id']], 'note': (s['note'] or '')[:500]}, wall)
                else:   # approved but changed nothing (e.g. a link that was already there)
                    E.append(c, dev(s['decided_by'], True), 'approve', {'entry': entry_of[s['id']], 'edit': None}, wall)
        now = int(time.time() * 1000)
        for v in c.execute('SELECT * FROM votes').fetchall():
            s = subs.get(v['submission_id'])
            if s and s['id'] in entry_of and s['status'] in ('pending', 'conflict') and v['user_id'] in by_id:
                E.append(c, dev(v['user_id']), 'vote', {'entry': entry_of[s['id']], 'on': True}, now)
        for u in users:   # deactivated accounts: their key stops here
            if not u['active'] and u is not mgr:
                last = c.execute('SELECT MAX(seq) FROM entries WHERE peer=?', (u['device'],)).fetchone()[0] or 0
                E.append(c, mgr['device'], 'revoke', {'device': u['device'], 'last_seq': last}, now)

        # the server-local side
        for u in users:
            store.put('users', {k: u[k] for k in u if k not in ('log_role',)} | {'role': u['role']})
        for file, (sha, size) in blobs.items():
            store.put('blobs', {'sha': sha, 'file': file, 'size': size})
            E.blob_files[sha] = file
        for s in subs.values():
            row = {'id': s['id'], 'client_id': s['client_id'], 'user_id': s['user_id'], 'kind': s['kind'],
                   'created': s['created'], 'entry': entry_of.get(s['id'])}
            if not row['entry']:   # an admin's held change, or one that never changed anything
                k, b = sub_body(s)
                row.update(held=json.dumps({'kind': k, 'body': b}), status=s['status'], note=s['note'],
                           decided_at=s['decided_at'], decided_by=s['decided_by'])
            store.put('subs', row)
        for t in DATA_TABLES:   # journaled deletes, so a restore from backups doesn't bring them back
            for r in c.execute(f'SELECT * FROM {t}').fetchall():
                store.delete(t, **{k: r[k] for k in KEYS[t]})
        for r in revs:
            store.delete('revisions', rev=r['rev'])
        store.put('meta', {'k': 'log_version', 'v': '1'})

        # check before committing: the log must reproduce the old live data exactly
        check, ignored = R.replay_run(list(E.entries.values()) + E._pending, E.anchor)
        problems = [f'{P.entry_id(e)[:12]} {e["type"]}: {check.ignored[P.entry_id(e)]}' for e in E._pending
                    if P.entry_id(e) in check.ignored] + [f'{k}: {v}' for k, v in ignored.items()]
        new = _new_state(check)
        for part in old:
            if old[part] != new[part]:
                problems.append(f'{part} differs:\n    old {old[part]}\n    new {new[part]}')
        if problems:
            raise MigrationError('Migration to the signed log stopped; nothing was changed. The old database is also '
                                 f'copied to {copy}.\n  ' + '\n  '.join(problems))
    n = len(E.entries)
    print(f'  Moved plant data to the signed log: {n} entries. Old database kept as {copy}.\n'
          f'  New plant root key: {E.root_path}. Back it up: python3 app.py export-root-key')
