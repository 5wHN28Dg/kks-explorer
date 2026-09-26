"""Submissions (proposed changes), approval, and the append-only revision log.

Users never edit live data: every change is a submission. Admin/manager submissions apply immediately when
`admins_apply_directly` is on; user submissions wait for an admin. Applying a submission writes the live tables and
appends one revision per changed entity (before/after), so every change is a restore point.

Conflicts: equipment edits carry the values the client saw (`base`) for the fields it changed. On apply, a field
whose live value moved away from `base` since then (and differs from the proposal) is a conflict; fields that don't
overlap merge automatically. Link add/remove, photo add and photo delete are idempotent and never conflict. A
conflicting submission stays in the queue flagged `conflict` until an admin forces or rejects it."""
import base64, json, re, time, uuid

EQ_FIELDS = ('area', 'floor', 'elev', 'near', 'loc', 'notes', 'custom')
KINDS = ('equipment', 'review', 'link', 'photo', 'photo_delete', 'tag_add', 'tag_remove')
ENTITIES = ('equipment', 'review', 'link', 'photo', 'added_tag')
SHEET_RE = re.compile(r'^[a-z0-9][a-z0-9-]{0,23}$')
TAG_RE = re.compile(r'^(\d{2}[A-Z]{3}\d{2}[A-Z]{2}\d{3})([A-Z0-9]{0,4})$')
KKS_RE = re.compile(r'^[0-9A-Z/]{3,24}$')
IMG_RE = re.compile(r'^data:image/(jpeg|jpg|png|webp);base64,(.+)$', re.S)


class Bad(Exception):
    """Invalid request (→ 400)."""


class Conflict(Exception):
    """Change would overwrite something that moved since the client saw it (→ 409)."""
    def __init__(self, detail):
        super().__init__(detail)
        self.detail = detail


def _j(v):
    return None if v is None else json.dumps(v, sort_keys=True)


def _default(field):
    return [] if field == 'custom' else ''


# ---------- live state per entity ----------
def get_state(c, entity, key):
    if entity == 'equipment':
        r = c.execute('SELECT data FROM equipment WHERE kks=?', (key,)).fetchone()
        return json.loads(r['data']) if r else None
    if entity == 'review':
        r = c.execute('SELECT data FROM reviews WHERE tag_id=?', (key,)).fetchone()
        return json.loads(r['data']) if r else None
    if entity == 'link':
        proc, step, kks = json.loads(key)
        r = c.execute('SELECT 1 FROM links WHERE proc=? AND step=? AND kks=?', (proc, step, kks)).fetchone()
        return True if r else None
    if entity == 'added_tag':
        r = c.execute('SELECT data FROM added_tags WHERE id=?', (key,)).fetchone()
        return json.loads(r['data']) if r else None
    if entity == 'photo':
        r = c.execute('SELECT * FROM photos WHERE id=?', (key,)).fetchone()
        return {k: r[k] for k in ('kks', 'file', 'caption', 'created')} if r else None
    raise Bad(f'unknown entity {entity}')


def _write_state(store, entity, key, value):
    now = int(time.time())
    if entity == 'equipment':
        if value is None: store.delete('equipment', kks=key)
        else: store.put('equipment', {'kks': key, 'data': json.dumps(value), 'updated': now})
    elif entity == 'review':
        if value is None: store.delete('reviews', tag_id=key)
        else: store.put('reviews', {'tag_id': key, 'data': json.dumps(value), 'updated': now})
    elif entity == 'link':
        proc, step, kks = json.loads(key)
        if value is None: store.delete('links', proc=proc, step=step, kks=kks)
        else: store.put('links', {'proc': proc, 'step': step, 'kks': kks})
    elif entity == 'added_tag':
        if value is None: store.delete('added_tags', id=key)
        else: store.put('added_tags', {'id': key, 'data': json.dumps(value)})
    elif entity == 'photo':
        # Photo files are never deleted from disk, so removing and restoring a photo row is lossless.
        if value is None: store.delete('photos', id=key)
        else: store.put('photos', {'id': key, **value})


def set_state(store, c, entity, key, value, actor, submission_id=None, note=''):
    """Write live state and append a revision. No-op (returns None) when nothing changes."""
    before = get_state(c, entity, key)
    if _j(before) == _j(value):
        return None
    _write_state(store, entity, key, value)
    return store.put('revisions', {'ts': int(time.time()), 'actor': actor, 'entity': entity, 'key': key,
                                   'before': _j(before), 'after': _j(value), 'submission_id': submission_id, 'note': note})


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
        return f'equipment:{k}', {'kks': k, 'changes': changes, 'base': {f: base.get(f, _default(f)) for f in changes}}
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
        magic = {b'\xff\xd8\xff': 'jpg', b'\x89PNG': 'png', b'RIFF': 'webp'}
        ext = next((e for sig, e in magic.items() if raw.startswith(sig)), None)
        if not ext: raise Bad('not an image')
        pid = uuid.uuid4().hex
        with open(f'{photos_dir}/{pid}.{ext}', 'wb') as f:
            f.write(raw)
        return f'photo:{k}', {'kks': k, 'photo_id': pid, 'file': f'{pid}.{ext}', 'caption': text(p.get('caption'), 500)}
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


# ---------- planning / applying ----------
def plan(c, kind, p, force=False):
    """Returns (ops, conflicts). ops = [(entity, key, new_value)]. Conflicts listed even when forced."""
    if kind == 'equipment':
        cur = get_state(c, 'equipment', p['kks']) or {}
        conflicts, new = [], dict(cur)
        for f, v in p['changes'].items():
            live, base = cur.get(f, _default(f)), p['base'].get(f, _default(f))
            if _j(live) == _j(v):
                continue  # already has the proposed value
            if _j(live) != _j(base):
                conflicts.append({'field': f, 'base': base, 'live': live, 'proposed': v})
                if not force: continue
            new[f] = v
        new = {f: v for f, v in new.items() if v not in ('', [])} or None
        return [('equipment', p['kks'], new)], conflicts
    if kind == 'review':
        cur = get_state(c, 'review', p['tag_id'])
        conflicts = []
        if _j(cur) != _j(p['base']) and _j(cur) != _j(p['data']):
            conflicts.append({'field': 'review', 'base': p['base'], 'live': cur, 'proposed': p['data']})
        return ([] if conflicts and not force else [('review', p['tag_id'], p['data'])]), conflicts
    if kind == 'link':
        key = json.dumps([p['proc'], p['step'], p['kks']])
        return [('link', key, True if p['on'] else None)], []
    if kind == 'photo':
        return [('photo', p['photo_id'], {'kks': p['kks'], 'file': p['file'], 'caption': p['caption'],
                                          'created': int(time.time())})], []
    if kind == 'photo_delete':
        return [('photo', p['photo_id'], None)], []
    if kind == 'tag_add':
        return [('added_tag', p['id'], {k: v for k, v in p.items() if k != 'id'})], []
    if kind == 'tag_remove':
        return [('added_tag', p['id'], None)], []
    raise Bad('bad kind')


def apply(store, c, sub, actor, force=False):
    """Apply a stored submission (row). Raises Conflict unless forced. Returns list of new revision numbers."""
    p = json.loads(sub['payload'])
    ops, conflicts = plan(c, sub['kind'], p, force)
    if conflicts and not force:
        raise Conflict(conflicts)
    note = 'forced over conflicting change' if conflicts else ''
    revs = [r for r in (set_state(store, c, e, k, v, actor, sub['id'], note) for e, k, v in ops) if r]
    return revs


def decide(store, c, sub, actor, status, note=''):
    row = dict(sub)
    row.update(status=status, decided_by=actor, decided_at=int(time.time()), note=note)
    store.put('submissions', row)


def submit(store, cfg, user, kind, payload, client_id):
    """Store a submission; apply it right away for admins. Returns dict for the client."""
    if client_id is not None and (not isinstance(client_id, str) or not re.fullmatch(r'[\w-]{8,64}', client_id)):
        raise Bad('bad client_id')
    c0 = store.conn()
    try:
        if client_id:
            old = c0.execute('SELECT id,status,note FROM submissions WHERE client_id=?', (client_id,)).fetchone()
            if old:  # offline replay of something already received
                return {'id': old['id'], 'status': old['status'], 'note': old['note'], 'duplicate': True}
    finally:
        c0.close()
    target, p = normalize(kind, payload, cfg['photos_dir'], cfg['max_upload_mb'] * 1024 * 1024)
    with store.write() as c:
        sid = store.put('submissions', {'client_id': client_id, 'user_id': user['id'], 'kind': kind, 'target': target,
                                        'payload': json.dumps(p), 'status': 'pending', 'created': int(time.time())})
        sub = c.execute('SELECT * FROM submissions WHERE id=?', (sid,)).fetchone()
        if user['role'] in ('admin', 'manager') and cfg['admins_apply_directly']:
            try:
                apply(store, c, sub, user['id'])
                decide(store, c, sub, user['id'], 'approved', 'applied directly')
                return {'id': sid, 'status': 'approved'}
            except Conflict as e:
                decide(store, c, sub, None, 'conflict', json.dumps(e.detail))
                return {'id': sid, 'status': 'conflict', 'conflicts': e.detail}
        _, conflicts = plan(c, kind, p)
        if conflicts:
            decide(store, c, sub, None, 'conflict', json.dumps(conflicts))
            return {'id': sid, 'status': 'conflict', 'conflicts': conflicts}
        return {'id': sid, 'status': 'pending'}


# ---------- revert / restore ----------
def revert(store, c, rev, actor, force=False):
    r = c.execute('SELECT * FROM revisions WHERE rev=?', (rev,)).fetchone()
    if not r or r['entity'] not in ENTITIES:
        raise Bad('no such revision')
    live = get_state(c, r['entity'], r['key'])
    if _j(live) != r['after'] and not force:
        raise Conflict([{'field': r['entity'], 'live': live, 'proposed': json.loads(r['before']) if r['before'] else None,
                         'note': 'changed again after this revision'}])
    return set_state(store, c, r['entity'], r['key'], json.loads(r['before']) if r['before'] else None, actor,
                     note=f'revert of rev {rev}')


def restore_to(store, c, rev, actor):
    """Put every data entity back to its state right after revision `rev` (0 = before any logged change)."""
    rows = c.execute('SELECT entity,key,before FROM revisions WHERE rev>? AND entity IN (%s) ORDER BY rev'
                     % ','.join('?' * len(ENTITIES)), (rev, *ENTITIES)).fetchall()
    first = {}
    for r in rows:
        first.setdefault((r['entity'], r['key']), r['before'])
    n = 0
    for (entity, key), before in first.items():
        if set_state(store, c, entity, key, json.loads(before) if before else None, actor, note=f'restore to rev {rev}'):
            n += 1
    return n
