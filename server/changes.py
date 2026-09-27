"""Submissions (proposed changes), approvals, History, revert and restore, on the signed log (server/engine.py).

Users never edit plant data directly: every change is a log entry. A user's entry is a *proposal* that counts once an
admin/manager approves it (docs/PROTOCOL.md §11). An admin/manager's own change counts at once
(`admins_apply_directly`); if it would overwrite something that moved since the client saw it, or when
`admins_apply_directly` is off, it is *held* on the server (table `subs`, not in the log) until an admin confirms it.

Conflicts: equipment edits carry the values the client saw (`base`). A field whose live value moved away from `base`
since then (and differs from the proposal) is a conflict; fields that don't overlap merge automatically. An admin
approving over a conflict must say so (`force`). A value set by the manager can only be overwritten by the manager
(replay keeps it otherwise, §12), so admins are told instead of silently losing.

The table `subs` maps submission numbers (what the UI shows) and `client_id`s (offline replay) to entries."""
import base64, hashlib, json, os, re, time, uuid

from peer import replay as R
from server import photos as photos_mod
from server.engine import ENTITIES, body_to_payload, default, payload_to_body, value_out

EQ_FIELDS = ('area', 'floor', 'elev', 'near', 'loc', 'notes', 'custom')
KINDS = ('equipment', 'review', 'link', 'photo', 'photo_delete', 'tag_add', 'tag_remove')
SHEET_RE = re.compile(r'^[a-z0-9][a-z0-9-]{0,23}$')
TAG_RE = re.compile(r'^(\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3})([A-Z0-9]{0,4})$')
KKS_RE = re.compile(r'^[0-9A-Z/]{3,24}$')
IMG_RE = re.compile(r'^data:image/(jpeg|jpg|png|webp|jxl);base64,(.+)$', re.S)
OPEN = ('pending', 'conflict')


class Bad(Exception):
    """Invalid request (→ 400)."""


class Denied(Exception):
    """Not allowed (→ 403)."""


class Gone(Exception):
    """Already decided / no longer possible (→ 409)."""


class NotFound(Exception):
    """(→ 404)"""


class Conflict(Exception):
    """Change would overwrite something that moved since the client saw it (→ 409)."""
    def __init__(self, detail):
        super().__init__(detail)
        self.detail = detail


# ---------- validating a submission ----------
def normalize(kind, p, photos_dir, max_bytes):
    """Validate client payload; returns (target, payload to store). Saves uploaded photo files."""
    if kind not in KINDS or not isinstance(p, dict):
        raise Bad('bad submission kind or payload')

    def kks(v):
        if not isinstance(v, str) or not KKS_RE.match(v):
            raise Bad('bad KKS')
        return v

    def text(v, n=4000):
        if v is None: return ''
        if not isinstance(v, str) or len(v) > n: raise Bad('bad text field')
        return v.strip()

    def fields(d):
        if not isinstance(d, dict) or set(d) - set(EQ_FIELDS): raise Bad('unknown equipment field')
        out = {}
        for f, v in d.items():
            if f == 'custom':
                if not isinstance(v, list) or len(v) > 100: raise Bad('bad custom fields')
                out[f] = [{'k': text(x.get('k'), 200), 'v': text(x.get('v'), 2000)} for x in v if isinstance(x, dict)]
            else:
                out[f] = text(v)
        return out

    if kind == 'equipment':
        k = kks(p.get('kks'))
        changes, base = fields(p.get('changes') or {}), fields(p.get('base') or {})
        if not changes: raise Bad('no changes')
        return f'equipment:{k}', {'kks': k, 'changes': changes, 'base': {f: base.get(f, default(f)) for f in changes}}
    if kind == 'review':
        tag = text(p.get('tag_id'), 64)
        d = p.get('data') or {}
        if not tag or d.get('status') not in ('confirmed', 'rejected'): raise Bad('bad review')
        data = {'status': d['status']}
        if d['status'] == 'confirmed':
            data.update(kks=kks(d.get('kks')), suffix=text(d.get('suffix'), 8), isa=text(d.get('isa'), 12) or None)
        base = p.get('base')
        return f'review:{tag}', {'tag_id': tag, 'data': data, 'base': base if isinstance(base, dict) else None}
    if kind == 'link':
        proc, k = text(p.get('proc'), 32), kks(p.get('kks'))
        try: step = int(p.get('step'))
        except (TypeError, ValueError): raise Bad('bad step')
        if not proc: raise Bad('bad procedure')
        return f'link:{proc}|{step}|{k}', {'proc': proc, 'step': step, 'kks': k, 'on': bool(p.get('on', True))}
    if kind == 'photo':
        k = kks(p.get('kks'))
        m = IMG_RE.match(p.get('dataUrl') or '')
        if not m: raise Bad('bad image')
        raw = base64.b64decode(m.group(2), validate=False)
        if len(raw) > max_bytes: raise Bad('image too large')
        ext = photos_mod.magic(raw)
        if not ext: raise Bad('not an image')
        try:
            raw, ext = photos_mod.to_jxl(raw, ext)   # kept as JPEG XL (server/photos.py)
        except ValueError as e:
            raise Bad(str(e))
        sha = hashlib.sha256(raw).hexdigest()   # stored by content: the log refers to photos by this hash
        path = f'{photos_dir}/{sha}.{ext}'
        if not os.path.exists(path):
            with open(path + '.part', 'wb') as f:
                f.write(raw)
            os.replace(path + '.part', path)
        return f'photo:{k}', {'kks': k, 'photo_id': uuid.uuid4().hex, 'file': f'{sha}.{ext}', 'blob': sha,
                              'size': len(raw), 'caption': text(p.get('caption'), 500)}
    if kind == 'tag_add':  # a tag the extractor missed, marked by hand on the drawing
        return f'tag_add:{p.get("sheet")}', tag_payload(p, text)
    if kind == 'tag_remove':
        tid = text(p.get('id'), 64)
        if not re.fullmatch(r'[0-9a-f]{32}', tid): raise Bad('bad tag id')
        return f'tag_remove:{tid}', {'id': tid}
    if kind == 'photo_delete':
        pid = text(p.get('photo_id'), 64)
        if not re.fullmatch(r'[0-9a-f]{32}', pid): raise Bad('bad photo id')
        return f'photo_delete:{pid}', {'photo_id': pid}


def tag_payload(p, text=None, keep_id=None):
    """Validate a hand-marked tag: sheet, box on the sheet image (px), code if readable (else it goes to review)."""
    text = text or (lambda v, n=4000: (v or '').strip()[:n])
    sheet = p.get('sheet')
    if not isinstance(sheet, str) or not SHEET_RE.match(sheet): raise Bad('bad sheet')
    bb = p.get('bbox')
    try:
        bb = [round(float(v), 1) for v in bb]
    except (TypeError, ValueError):
        raise Bad('bad box')
    if len(bb) != 4 or not (0 <= bb[0] < bb[2] <= 20000 and 0 <= bb[1] < bb[3] <= 20000) or bb[2] - bb[0] < 4 or bb[3] - bb[1] < 4:
        raise Bad('bad box')
    code = re.sub(r'\s', '', text(p.get('kks'), 32)).upper()
    isa = text(p.get('isa'), 12).upper() or None
    if isa and not re.fullmatch(r'[A-Z]{1,6}', isa): raise Bad('function letters: 1-6 letters, e.g. PI, TIAC')
    m = TAG_RE.match(code)
    if code and not m: raise Bad('That is not a valid KKS (e.g. 11LAB70AA501, suffix allowed)')
    return {'id': keep_id or p.get('id') or uuid.uuid4().hex, 'sheet': sheet, 'bbox': bb,
            'kks': m[1] if m else None, 'suffix': m[2] if m else '', 'isa': isa if m else isa,
            'kind': 'instrument' if isa else 'equipment', 'orient': 'v' if bb[3] - bb[1] > bb[2] - bb[0] else 'h',  # vertical tags: box taller than wide
            'note': text(p.get('note'), 500)}




# ---------- submissions ----------
def _conflicts_out(conflicts):
    return [{k: c[k] for k in ('field', 'base', 'live', 'proposed')} for c in conflicts]


def _manager_check(E, me, conflicts):
    if me['role'] != 'manager' and any(c['manager'] for c in conflicts):
        raise Denied('The value there was set or approved by the manager; only the manager can overwrite it.')


def _rebase(kind, body, E):
    """A forced change: its base becomes what is live now, so it overwrites knowingly and records no conflict."""
    if kind == 'equipment':
        cur = E.run.equipment.get(body['kks'], {})
        return {**body, 'base': {f: cur.get(f, default(f)) for f in body['changes']}}
    if kind == 'review':
        return {**body, 'base': E.run.reviews.get(body['tag_id'])}
    return body


def submit(E, cfg, user, kind, payload, client_id):
    """Store a submission as a log entry (or a held draft). Returns the dict the client expects."""
    if client_id is not None and (not isinstance(client_id, str) or not re.fullmatch(r'[\w-]{8,64}', client_id)):
        raise Bad('bad client_id')
    if client_id:
        c0 = E.store.conn()
        try:
            old = c0.execute('SELECT id FROM subs WHERE client_id=?', (client_id,)).fetchone()
        finally:
            c0.close()
        if old:  # offline replay of something already received
            with E.lock:
                r = sub_row(E, old['id'])
                st, note = sub_status(E, r)[:2]
            return {'id': old['id'], 'status': st, 'note': note, 'duplicate': True}
    _, p = normalize(kind, payload, cfg['photos_dir'], cfg['max_upload_mb'] * 1024 * 1024)
    body = payload_to_body(kind, p)
    try:
        R._check_data(kind, body)
    except R.Ignore:
        raise Bad('invalid change')
    admin = user['role'] in ('admin', 'manager')
    now = int(time.time())
    with E.tx() as c:
        if kind == 'photo':
            E.store.put('blobs', {'sha': p['blob'], 'file': p['file'], 'size': p['size']})
            E.blob_files[p['blob']] = p['file']
        _, conflicts = E.plan(kind, body)
        row = {'client_id': client_id, 'user_id': user['id'], 'kind': kind, 'created': now}
        if admin and (conflicts or not cfg['admins_apply_directly']):
            status = 'conflict' if conflicts else 'pending'
            sid = E.store.put('subs', {**row, 'held': json.dumps({'kind': kind, 'body': body}), 'status': status,
                                       'note': json.dumps(_conflicts_out(conflicts)) if conflicts else ''})
            return {'id': sid, 'status': status, **({'conflicts': _conflicts_out(conflicts)} if conflicts else {})}
        eid = E.append(c, user['device'], kind, body)
        sid = E.store.put('subs', {**row, 'entry': eid})
    if admin:
        return {'id': sid, 'status': 'approved'}
    return {'id': sid, 'status': 'conflict', 'conflicts': _conflicts_out(conflicts)} if conflicts else \
        {'id': sid, 'status': 'pending'}


def sub_row(E, sid):
    c = E.store.conn()
    try:
        return c.execute('SELECT * FROM subs WHERE id=?', (sid,)).fetchone()
    finally:
        c.close()


def sub_kind_body(E, r):
    if r['entry'] is None:
        h = json.loads(r['held'])
        return h['kind'], h['body']
    e = E.entry(r['entry'])
    return e['type'], e['body']


def sub_status(E, r):
    """-> (status, note, decided_at, decider person or None, conflicts). Call with E.lock held."""
    kind, body = sub_kind_body(E, r)
    if r['entry'] is None:
        conflicts = E.plan(kind, body)[1] if r['status'] in OPEN else []
        status = ('conflict' if conflicts else 'pending') if r['status'] in OPEN else r['status']
        return status, r['note'] or '', r['decided_at'], None, conflicts
    status, dec, note = E.status_of(r['entry'])
    conflicts = []
    if status == 'pending':
        conflicts = E.plan(kind, body)[1]
        status = 'conflict' if conflicts else 'pending'
    decider = E.person_of(E.entry(dec)['peer']) if dec else None
    if not note and dec:
        note = E.note_of(dec)
    return status, note, E.ts(dec) if dec else (E.ts(r['entry']) if status == 'approved' else None), decider, conflicts


def sub_out(E, r, me, users, live=False):
    """One submission as the UI expects it. `users` = {user id: row, person: row}. Call with E.lock held."""
    kind, body = sub_kind_body(E, r)
    status, note, decided_at, decider, conflicts = sub_status(E, r)
    u = users.get(r['user_id']) or (E.run.persons.get(r['person']) if r['person'] else None)   # (by sync: no account here)
    d = {'id': r['id'], 'client_id': r['client_id'], 'kind': kind, 'target': target_of(kind, body), 'status': status,
         'created': r['created'], 'decided_at': decided_at, 'note': note, 'payload': body_to_payload(E, kind, body),
         'by': u['username'] if u else '?', 'mine': r['user_id'] == me['id']}
    d['by_name'] = (u['full_name'] if u else None) or d['by']
    if kind == 'photo' and r['entry']:
        voters = E.run.votes.get(r['entry'], set())
        d['votes'], d['voted'] = len(voters), me['person'] in voters
    elif kind == 'photo':
        d['votes'], d['voted'] = 0, False
    if live and status in OPEN and me['role'] in ('admin', 'manager'):
        d['conflicts'] = _conflicts_out(conflicts)
        d['live'] = [{'entity': e, 'key': json.dumps(list(k)) if e == 'link' else k,
                      'value': value_out(E, e, k, E.get(e, k))} for e, k in E.plan(kind, body)[0]]
    return d


def target_of(kind, b):
    if kind == 'equipment': return f'equipment:{b["kks"]}'
    if kind == 'review': return f'review:{b["tag_id"]}'
    if kind == 'link': return f'link:{b["proc"]}|{b["step"]}|{b["kks"]}'
    if kind == 'photo': return f'photo:{b["kks"]}'
    if kind == 'photo_delete': return f'photo_delete:{b["photo"]}'
    if kind == 'tag_add': return f'tag_add:{b["sheet"]}'
    return f'tag_remove:{b["tag"]}'


def list_subs(E, me, users, status_filter, limit):
    """Newest first. Users see their own plus open photo proposals (to vote on them)."""
    admin = me['role'] in ('admin', 'manager')
    c = E.store.conn()
    try:
        rows = c.execute('SELECT * FROM subs ORDER BY id DESC').fetchall()
    finally:
        c.close()
    out = []
    with E.lock:
        for r in rows:
            st = sub_status(E, r)[0]
            if status_filter == 'open' and st not in OPEN: continue
            if status_filter == 'decided' and st in OPEN: continue
            if not admin and r['user_id'] != me['id'] and not (r['kind'] == 'photo' and st in OPEN): continue
            out.append(sub_out(E, r, me, users, live=True))
            if len(out) >= limit: break
    return out


def act(E, cfg, me, sid, action, d):
    """vote / withdraw / approve / pick / reject on submission `sid`."""
    with E.tx() as c:
        r = c.execute('SELECT * FROM subs WHERE id=?', (sid,)).fetchone()
        if not r:
            raise NotFound('no such submission')
        kind, body = sub_kind_body(E, r)
        status = sub_status(E, r)[0]
        open_ = status in OPEN
        if action == 'vote':
            if kind != 'photo' or not open_ or not r['entry']:
                raise Bad('only open photo proposals take votes')
            E.append(c, me['device'], 'vote', {'entry': r['entry'], 'on': me['person'] not in E.run.votes.get(r['entry'], set())})
            return {'ok': True}
        if action == 'withdraw':
            if r['user_id'] != me['id'] or not open_:
                raise Denied('can only withdraw your own open submission')
            if r['entry']:
                E.append(c, me['device'], 'withdraw', {'entry': r['entry']})
            else:
                E.store.put('subs', {**dict(r), 'status': 'withdrawn', 'decided_at': int(time.time()), 'decided_by': me['id']})
            return {'ok': True}
        if me['role'] not in ('admin', 'manager'):
            raise Denied('admin only')
        if not open_:
            raise Gone(f'already {status}')
        if action == 'reject':
            _decide_reject(E, c, me, r, (d.get('note') or '')[:500])
            return {'ok': True}
        edit = None
        if kind == 'tag_add' and isinstance(d.get('edit'), dict):  # admin corrects the code while approving
            fixed = tag_payload({**body_to_payload(E, kind, body), **{k: d['edit'].get(k) for k in ('kks', 'isa')}},
                                keep_id=body['tag'])
            edit = {'kks': fixed['kks'], 'suffix': fixed['suffix'], 'isa': fixed['isa']}
            body = {**body, **edit}
        _, conflicts = E.plan(kind, body)
        _manager_check(E, me, conflicts)
        if conflicts and not d.get('force'):
            raise Conflict(_conflicts_out(conflicts))
        note = 'forced over conflicting change' if conflicts else ''
        if r['entry']:
            eid = E.append(c, me['device'], 'approve', {'entry': r['entry'], 'edit': edit})
        else:   # a held admin change: now it goes into the log, by the admin who confirms it
            eid = E.append(c, me['device'], kind, _rebase(kind, body, E))
            E.store.put('subs', {**dict(r), 'entry': eid, 'held': None, 'status': None})
            u = c.execute('SELECT username FROM users WHERE id=?', (r['user_id'],)).fetchone()
            if r['user_id'] != me['id']:
                note = (note + '; ' if note else '') + f'proposed by {u["username"] if u else "?"}'
        E.note(eid, note)
        rejected = 0
        if action == 'pick':  # choose this photo, discard the other open photos for the same equipment
            for o in c.execute("SELECT * FROM subs WHERE kind='photo' AND id<>?", (sid,)).fetchall():
                ok, ob = sub_kind_body(E, o)
                if ob.get('kks') == body['kks'] and sub_status(E, o)[0] in OPEN:
                    _decide_reject(E, c, me, o, f'another photo was chosen (#{sid})')
                    rejected += 1
        return {'ok': True, 'rejected': rejected}


def _decide_reject(E, c, me, r, note):
    if r['entry']:
        E.append(c, me['device'], 'reject', {'entry': r['entry'], 'note': note})
    else:
        E.store.put('subs', {**dict(r), 'status': 'rejected', 'note': note, 'decided_at': int(time.time()),
                             'decided_by': me['id']})


# ---------- History (log changes + local account/sheet notes), revert, restore ----------
def history(E, c):
    """All changes, oldest first, numbered from 1: [(rev, dict)]. Call with E.lock held. The numbers are for reading
    only: entries from other devices with older clocks can arrive and shift them; `hid` (entry ID + position within
    that entry, or n<local rev>) stays the same and is what revert/restore use."""
    notes = {r['entry']: r['note'] for r in c.execute('SELECT * FROM entry_notes')}
    subs = {r['entry']: r['id'] for r in c.execute('SELECT id, entry FROM subs WHERE entry IS NOT NULL')}
    items, per_entry = [], {}
    for i, h in enumerate(E.run.history):
        at = E.entry(h['at'])
        k = per_entry[h['at']] = per_entry.get(h['at'], -1) + 1
        items.append(((at['hlc'][0] // 1000, 0, i), {'hid': f'{h["at"][:24]}-{k}',
            'ts': at['hlc'][0] // 1000, 'person': E.person_of(at['peer']), 'entity': h['entity'],
            'key': json.dumps(h['key']) if h['entity'] == 'link' else h['key'],
            'before': h['before'], 'after': h['after'], 'raw_key': h['key'],
            'submission_id': subs.get(h['source']), 'note': notes.get(h['at']) or notes.get(h['source']) or ''}))
    for r in c.execute("SELECT * FROM revisions WHERE entity IN ('user','sheet') ORDER BY rev"):
        items.append(((r['ts'], 1, r['rev']), {'hid': f'n{r["rev"]}', 'ts': r['ts'], 'actor': r['actor'], 'entity': r['entity'],
                                               'key': r['key'], 'before': None, 'after': None, 'raw_key': None,
                                               'submission_id': None, 'note': r['note']}))
    items.sort(key=lambda x: x[0])
    return [(n + 1, it) for n, (_, it) in enumerate(items)]


def history_out(E, rows, users):
    out = []
    for rev, it in rows:
        u = users.get(it['person']) if it.get('person') else users.get(it.get('actor'))
        log = it['entity'] in ENTITIES
        out.append({'rev': rev, 'hid': it['hid'], 'ts': it['ts'], 'actor': u['id'] if u else None,
                    'username': u['username'] if u else None, 'full_name': u['full_name'] if u else None,
                    'entity': it['entity'], 'key': it['key'],
                    'before': json.dumps(value_out(E, it['entity'], it['raw_key'], it['before'])) if log and it['before'] is not None else None,
                    'after': json.dumps(value_out(E, it['entity'], it['raw_key'], it['after'])) if log and it['after'] is not None else None,
                    'submission_id': it['submission_id'], 'note': it['note']})
    return out


def _put_back(E, c, me, targets, note):
    """Write entries setting each (entity, key) to its value. Checks everything before writing anything."""
    todo = []
    for entity, key, value in targets:
        tb = E.restore_body(entity, key, value)
        if not tb:
            continue
        kind, body = tb
        if me['role'] != 'manager':
            if kind == 'equipment' and any(E.manager_owned('equipment', key, f) for f in body['changes']) or \
                    kind == 'review' and E.manager_owned('review', key):
                raise Denied(f'{key}: set or approved by the manager; only the manager can change it back.')
        todo.append((kind, body))
    for kind, body in todo:
        E.note(E.append(c, me['device'], kind, body), note)
    return len(todo)


def _find(rows, ref):
    """A History row by its hid (or, for scripts, its current number). -> index into rows"""
    for i, (rev, it) in enumerate(rows):
        if it['hid'] == ref or (isinstance(ref, int) and rev == ref):
            return i
    raise Bad('no such revision')


def revert(E, c, me, ref, force=False):
    rows = history(E, c)
    i = _find(rows, ref)
    rev, it = rows[i]
    if it['entity'] not in ENTITIES:
        raise Bad('only data changes can be reverted')
    key = tuple(it['raw_key']) if it['entity'] == 'link' else it['raw_key']
    live = E.get(it['entity'], key)
    if live != it['after'] and not force:
        raise Conflict([{'field': it['entity'], 'live': value_out(E, it['entity'], key, live),
                         'proposed': value_out(E, it['entity'], key, it['before']), 'note': 'changed again after this revision'}])
    return _put_back(E, c, me, [(it['entity'], key, it['before'])], f'revert of rev {rev}')


def restore_to(E, c, me, ref):
    """Put every data entity back to its state right after History row `ref` (hid, or 0 = before any logged change)."""
    rows = history(E, c)
    start = 0 if ref == 0 else _find(rows, ref) + 1
    rev = rows[start - 1][0] if start else 0
    first = {}
    for n, it in rows[start:]:
        if it['entity'] in ENTITIES:
            key = tuple(it['raw_key']) if it['entity'] == 'link' else it['raw_key']
            first.setdefault((it['entity'], key), it['before'])
    return _put_back(E, c, me, [(e, k, v) for (e, k), v in first.items()], f'restore to rev {rev}')
