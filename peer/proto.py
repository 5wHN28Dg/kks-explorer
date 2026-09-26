"""KKS Explorer sync protocol v1, reference implementation (spec: docs/PROTOCOL.md).

Canonical encoding, Ed25519 keys and peer IDs, signed log entries, chain checks, hybrid logical clock, total order.
The Kotlin implementation must reproduce peer/vectors/v1.json exactly; so must this file (tests/test_protocol.py)."""
import base64, hashlib, json, re

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

VERSION = 1
DOMAIN = b'kks-log-v1\n'
KEY_RE = re.compile(r'^[a-z_][a-z0-9_]{0,31}$')
MAX_INT = 2 ** 53 - 1
SKEW_MS = 86_400_000
FIELDS = ('v', 'peer', 'seq', 'prev', 'hlc', 'type', 'body', 'sig')


class ProtocolError(ValueError):
    """Rejected input. `code` is one of the error codes in docs/PROTOCOL.md §7."""
    def __init__(self, code, msg=''):
        super().__init__(f'{code}: {msg}' if msg else code)
        self.code = code


# ---------- §1 canonical encoding ----------
def _check(v, where='value'):
    if isinstance(v, bool) or v is None:
        return
    if isinstance(v, int):
        if not -MAX_INT <= v <= MAX_INT:
            raise ProtocolError('bad_encoding', f'integer out of range at {where}')
        return
    if isinstance(v, float):
        raise ProtocolError('bad_encoding', f'float at {where}')
    if isinstance(v, str):
        try:
            v.encode('utf-8')
        except UnicodeEncodeError:
            raise ProtocolError('bad_encoding', f'unpaired surrogate at {where}')
        return
    if isinstance(v, (list, tuple)):
        for i, x in enumerate(v):
            _check(x, f'{where}[{i}]')
        return
    if isinstance(v, dict):
        for k, x in v.items():
            if not isinstance(k, str) or not KEY_RE.match(k):
                raise ProtocolError('bad_encoding', f'bad key {k!r} at {where}')
            _check(x, f'{where}.{k}')
        return
    raise ProtocolError('bad_encoding', f'unsupported type {type(v).__name__} at {where}')


def canonical(obj):
    """Canonical JSON bytes (docs/PROTOCOL.md §1). Python's json with these options matches the spec's string
    escaping (short escapes for \\b\\f\\n\\r\\t, \\u00xx lowercase for other controls, no escaping of non-ASCII)."""
    _check(obj)
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


# ---------- §2 keys ----------
def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


def unb64u(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def key_from_seed(seed):
    """Ed25519 private key from a 32-byte seed (vectors use fixed seeds; devices use os.urandom)."""
    return Ed25519PrivateKey.from_private_bytes(seed)


def peer_id(private_key):
    raw = private_key.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return b64u(raw)


# ---------- §3 entries ----------
def signed_bytes(entry):
    return DOMAIN + canonical({k: v for k, v in entry.items() if k != 'sig'})


def entry_id(entry):
    return hashlib.sha256(canonical(entry)).hexdigest()


def make_entry(private_key, seq, prev, hlc, type_, body):
    e = {'v': VERSION, 'peer': peer_id(private_key), 'seq': seq, 'prev': prev, 'hlc': list(hlc), 'type': type_, 'body': body}
    check_fields(e, signed=False)
    e['sig'] = b64u(private_key.sign(signed_bytes(e)))
    return e


def check_fields(e, signed=True):
    want = FIELDS if signed else FIELDS[:-1]
    if not isinstance(e, dict) or set(e) != set(want):
        raise ProtocolError('bad_fields', 'field set')
    _check(e)
    if e['v'] != VERSION or type(e['v']) is not int:
        raise ProtocolError('bad_version')
    if not isinstance(e['peer'], str) or len(e['peer']) != 43:
        raise ProtocolError('bad_fields', 'peer')
    if type(e['seq']) is not int or e['seq'] < 1:
        raise ProtocolError('bad_seq')
    if e['seq'] == 1:
        if e['prev'] is not None:
            raise ProtocolError('bad_prev', 'seq 1 must have prev null')
    elif not (isinstance(e['prev'], str) and re.fullmatch(r'[0-9a-f]{64}', e['prev'])):
        raise ProtocolError('bad_prev')
    h = e['hlc']
    if not (isinstance(h, list) and len(h) == 2 and all(type(x) is int and x >= 0 for x in h)):
        raise ProtocolError('bad_fields', 'hlc')
    if not (isinstance(e['type'], str) and KEY_RE.match(e['type'])):
        raise ProtocolError('bad_fields', 'type')
    if not isinstance(e['body'], dict):
        raise ProtocolError('bad_fields', 'body')
    if signed and not isinstance(e['sig'], str):
        raise ProtocolError('bad_fields', 'sig')


def verify_entry(e):
    """Raise ProtocolError unless e is a valid, correctly signed entry."""
    check_fields(e)
    try:
        pub = Ed25519PublicKey.from_public_bytes(unb64u(e['peer']))
        pub.verify(unb64u(e['sig']), signed_bytes(e))
    except (InvalidSignature, ValueError):
        raise ProtocolError('bad_sig')


# ---------- §4 chains ----------
def verify_chain(entries):
    """Entries of ONE device, any order. Valid = contiguous from seq 1 with matching prev links. Returns them sorted."""
    by_seq = {}
    for e in entries:
        verify_entry(e)
        if e['seq'] in by_seq and entry_id(by_seq[e['seq']]) != entry_id(e):
            raise ProtocolError('fork', f'seq {e["seq"]}')
        by_seq[e['seq']] = e
    if len({e['peer'] for e in entries}) > 1:
        raise ProtocolError('bad_fields', 'entries from more than one device')
    chain = [by_seq[s] for s in sorted(by_seq)]
    for i, e in enumerate(chain):
        if e['seq'] != i + 1:
            raise ProtocolError('chain_gap', f'missing seq {i + 1}')
        if i and e['prev'] != entry_id(chain[i - 1]):
            raise ProtocolError('chain_prev', f'seq {e["seq"]}')
    return chain


# ---------- §5 hybrid logical clock ----------
class HLC:
    def __init__(self, l=0, c=0):
        self.l, self.c = l, c

    def now(self, wall):
        """Clock value for a new local entry."""
        if wall > self.l:
            self.l, self.c = wall, 0
        else:
            self.c += 1
        return [self.l, self.c]

    def recv(self, remote, wall):
        """Update on receiving an entry stamped `remote` = [l', c']."""
        rl, rc = remote
        if rl > wall + SKEW_MS:
            return [self.l, self.c]   # a device with a wrong date must not drag everyone's clock forward
        L = max(self.l, rl, wall)
        if L == self.l == rl:
            c = max(self.c, rc) + 1
        elif L == self.l:
            c = self.c + 1
        elif L == rl:
            c = rc + 1
        else:
            c = 0
        self.l, self.c = L, c
        return [self.l, self.c]


# ---------- §6 total order ----------
def order_key(e):
    return (e['hlc'][0], e['hlc'][1], e['peer'], e['seq'])


# ---------- a device's own log (in memory; storage comes with M1) ----------
class Log:
    def __init__(self, private_key):
        self.key, self.entries, self.clock = private_key, [], HLC()

    def append(self, type_, body, wall):
        prev = entry_id(self.entries[-1]) if self.entries else None
        e = make_entry(self.key, len(self.entries) + 1, prev, self.clock.now(wall), type_, body)
        self.entries.append(e)
        return e
