"""Course progress (M4, docs/ARCHITECTURE.md §8): private to the person, readable only by their own devices.

- Each person has one or more 32-byte *person secrets* (PROTOCOL.md §13). The first device that needs one makes it;
  a person's devices swap them over the sync port (`secrets` session, §17), so all of them end up knowing all of
  them. New entries are written with the secret whose SHA-256 sorts first, so a person's devices converge on one.
- Progress is a `private` entry {type: course_progress, body: {course, items: [[key, value], …]}}: the values are
  the course's own localStorage strings (JSON text; floats included, which canonical JSON can't carry as numbers),
  as pairs because course keys like `finalBest` aren't valid canonical object keys (§1).
- Reading: every private entry of the person, in replay order, decrypted with any known secret, merged per key:
  two JSON objects → union (later keys win), `…Best` numbers → the larger, anything else → the later value.
- Peer mode only (a person's own laptop or phone). On a server nobody's secret is held, so browsers keep course
  progress only in their own localStorage.
"""
import hashlib, json, os, re, time

from peer import replay as R

COURSE_RE = re.compile(r'[a-z]{1,16}')
KEY_RE = re.compile(r'[A-Za-z0-9_.-]{1,64}')
MAX_VALUE, MAX_TOTAL = 200_000, 600_000


class Bad(ValueError):
    pass


def _sha(secret):
    return hashlib.sha256(secret).hexdigest()


def secrets_of(E, person):
    """-> this person's secrets known here, the one to write with first."""
    c = E.store.conn()
    try:
        rows = c.execute('SELECT sha, secret FROM person_secrets WHERE person=? ORDER BY sha', (person,)).fetchall()
    finally:
        c.close()
    return [bytes.fromhex(r['secret']) for r in rows]


def add_secrets(E, person, secrets):
    """Store secrets learned from another device of the person. -> how many were new."""
    have = {_sha(s) for s in secrets_of(E, person)}
    new = [s for s in secrets if isinstance(s, bytes) and len(s) == 32 and _sha(s) not in have]
    if new:
        with E.store.write():
            for s in new:
                E.store.put('person_secrets', {'sha': _sha(s), 'person': person, 'secret': s.hex(), 'created': int(time.time())})
    return len(new)


def ensure_secret(E, person):
    got = secrets_of(E, person)
    if got:
        return got[0]
    add_secrets(E, person, [os.urandom(32)])
    return secrets_of(E, person)[0]


def check(course, data):
    if not isinstance(course, str) or not COURSE_RE.fullmatch(course):
        raise Bad('bad course')
    if not isinstance(data, dict) or not data:
        raise Bad('nothing to save')
    total = 0
    for k, v in data.items():
        if not KEY_RE.fullmatch(k) or not isinstance(v, str) or len(v) > MAX_VALUE:
            raise Bad('bad progress value')
        total += len(v)
    if total > MAX_TOTAL:
        raise Bad('too much at once')
    return {'course': course, 'items': [[k, data[k]] for k in sorted(data)]}


def save(E, owner, course, data):
    """Append one private course_progress entry by this device for its owner."""
    body = check(course, data)
    secret = ensure_secret(E, owner['person'])
    with E.tx() as c:
        E.append(c, owner['device'], 'private', R.private_body(secret, owner['person'], 'course_progress', body))


def merge(key, old, new):
    """Two localStorage strings of the same key -> the merged string (see the module doc)."""
    if old is None:
        return new
    try:
        a, b = json.loads(old), json.loads(new)
    except ValueError:
        return new
    if isinstance(a, dict) and isinstance(b, dict):
        return json.dumps({**a, **b}, separators=(',', ':'))
    if key.endswith('Best') and isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        return old if a > b else new
    return new


def load(E, person):
    """-> {course: {key: localStorage string}} from this person's private entries this device can read."""
    keys = secrets_of(E, person)
    out = {}
    with E.lock:
        ids = list(E.run.private.get(person, [])) if E.run else []
        entries = [E.entries[i] for i in ids if i in E.entries]
    for e in entries:
        opened = None
        for k in keys:
            try:
                opened = R.private_open(k, e['body'])
                break
            except Exception:
                continue
        if not opened or opened.get('type') != 'course_progress':
            continue
        b = opened.get('body') or {}
        try:
            course, data = b['course'], {k: v for k, v in b['items']}
            check(course, data)
        except (KeyError, TypeError, ValueError):
            continue
        cur = out.setdefault(course, {})
        for k, v in data.items():
            cur[k] = merge(k, cur.get(k), v)
    return out
