"""Person secrets between a person's own devices and course progress (docs/PROTOCOL-v2.md §13, §17; decision 0062).
Test-only reference: the pairing code, the sealed share, which secret writes, and how progress values merge."""
import hashlib, json, math

from ref import proto2 as P
from ref import crypto2 as C

SHARE_PURPOSE = 'kks-person-secret'
MAX_SECRETS = 32
MAX_LISTED = 64
MAX_PROOFS = 16


def pair_commit(dev, to, box, nonce):
    """§17: a pair_commit's value: the hash of the nonce the device will reveal, bound to both devices and its box key"""
    return hashlib.sha256(('kks-pair-commit-v1\n' + dev + '\n' + to + '\n' + box + '\n' + nonce).encode()).hexdigest()


def pair_code(dev_a, box_a, nonce_a, dev_b, box_b, nonce_b):
    """§17: the same 6 digits on both devices; the IDs sorted by code point, each followed by its box key and its
    revealed nonce (each committed before the other's was seen, so neither side can steer the code)."""
    (x, kx, nx), (y, ky, ny) = sorted([(dev_a, box_a, nonce_a), (dev_b, box_b, nonce_b)])
    d = hashlib.sha256(('kks-pair-code-v2\n' + x + '\n' + kx + '\n' + nx + '\n' + y + '\n' + ky + '\n' + ny).encode()).digest()
    return f'{int.from_bytes(d[:4], "big") % 1_000_000:06d}'


def write_secret(secrets, retired=()):
    """The secret a device writes with: one not retired by a rotation first, then the largest `made`; equal: the
    lowest SHA-256 hex. secrets = [(k, made)]; retired = SHA-256 hex strings."""
    return min(secrets, key=lambda s: (hashlib.sha256(s[0]).hexdigest() in retired, -s[1],
                                       hashlib.sha256(s[0]).hexdigest()))[0]


def share_plain(person, sender, to, secrets, holders=(), removed=(), retired=()):
    """secrets = [(k, made)] in write order, at most 32; holders: device IDs, at most 64; removed: the revoke entries of
    removed holders, the latest 16; retired: the
    sender's retired SHA-256 hex, of which the share lists those among the secrets it sends."""
    ordered = sorted(secrets, key=lambda s: (hashlib.sha256(s[0]).hexdigest() in retired, -s[1],
                                             hashlib.sha256(s[0]).hexdigest()))[:MAX_SECRETS]
    return {'person': person, 'from': sender, 'to': to,
            'secrets': [{'k': P.b64u(k), 'made': made} for k, made in ordered],
            'holders': list(holders)[:MAX_LISTED], 'removed': list(removed)[-MAX_PROOFS:],
            'retired': [h for h in (hashlib.sha256(k).hexdigest() for k, _ in ordered) if h in retired]}


def share_seal(box_key_str, plain, eph=None, nonce=None):
    return C.ecies_seal(box_key_str, SHARE_PURPOSE, P.canonical(plain), eph=eph, nonce=nonce)


def share_take(box_private, sealed, author, me, person):
    """What a share gives this device: (secrets, holders, removed, retired), or None when it gives nothing (§17 "Taking a share
    in"). The caller has already checked that the entry is valid and its author is in this device's paired set."""
    try:
        if sealed.get('purpose') != SHARE_PURPOSE:
            return None
        o = json.loads(C.ecies_open(box_private, sealed))
    except Exception:
        return None
    if not isinstance(o, dict) or set(o) != {'person', 'from', 'to', 'secrets', 'holders', 'removed', 'retired'}:
        return None
    if o['person'] != person or o['from'] != author or o['to'] != me:
        return None
    if not all(isinstance(o[k], list) for k in ('secrets', 'holders', 'removed', 'retired')):
        return None
    got = []
    for s in o['secrets'][:MAX_SECRETS]:
        if not isinstance(s, dict) or set(s) != {'k', 'made'}:
            return None
        made = s['made']
        if type(made) is not int or made < 0 or made > P.MAX_INT or not isinstance(s['k'], str):
            return None
        try:
            k = P.unb64u(s['k'])
        except Exception:
            return None
        if len(k) != 32:
            return None
        got.append((k, made))
    holders = o['holders'][:MAX_LISTED]
    if not all(isinstance(x, str) and P.PEER_RE.fullmatch(x) for x in holders):
        return None
    removed = o['removed'][:MAX_PROOFS]          # revoke entries; the receiver checks each against its own log
    if not all(isinstance(x, dict) for x in removed):
        return None
    lists = [holders, removed]
    retired = o['retired'][:MAX_LISTED]
    if not all(isinstance(x, str) and P.HEX64_RE.fullmatch(x) for x in retired):
        return None
    return got, lists[0], lists[1], retired


def merge_value(key, old, new):
    """Two saved strings of one progress key (COURSES §8, PROTOCOL §17): objects → union (the later's keys win),
    "…Best" numbers → the larger (equal: the later), otherwise (or either not JSON) the later. old None = unset."""
    if old is None:
        return new
    try:
        a, b = _strict(old), _strict(new)
    except ValueError:
        return new
    if isinstance(a, dict) and isinstance(b, dict):
        return json.dumps({**a, **b}, ensure_ascii=False, separators=(',', ':'))
    if key.endswith('Best') and _num(a) and _num(b):
        return old if a > b else new
    return new


def _num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _dup_check(pairs):
    keys = [k for k, _ in pairs]
    if len(keys) != len(set(keys)):
        raise ValueError('duplicate key')
    return dict(pairs)


def _strict(text):
    def bad_const(c):
        raise ValueError(c)
    v = json.loads(text, object_pairs_hook=_dup_check, parse_constant=bad_const)
    if isinstance(v, float) and not math.isfinite(v):
        raise ValueError('not finite')
    return v


def fold(values):
    """[(key, value), …] in replay order → {key: merged value}."""
    out = {}
    for k, v in values:
        out[k] = merge_value(k, out.get(k), v)
    return out
