"""KKS Explorer sync protocol v2, reference implementation (spec: docs/PROTOCOL-v2.md §1–7).

Test-only: it generates and cross-checks the v2 vectors (ref/vectors/). The product implementation is the Nim core
(docs/decisions/0027). Canonical encoding, P-256 keys and peer IDs, signed log entries, chain checks, hybrid logical
clock, total order."""
import base64, hashlib, json, re

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature, encode_dss_signature

VERSION = 2
DOMAIN = b'kks-log-v2\n'
KEY_RE = re.compile(r'^[a-z_][a-z0-9_]{0,31}$')
PEER_RE = re.compile(r'^[A-Za-z0-9_-]{32}$')
KEYSTR_RE = re.compile(r'^[A-Za-z0-9_-]{87}$')
SIG_RE = re.compile(r'^[A-Za-z0-9_-]{86}$')
HEX64_RE = re.compile(r'^[0-9a-f]{64}$')
MAX_INT = 2 ** 53 - 1
SKEW_MS = 86_400_000
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551   # P-256 group order
BASE = ('v', 'peer', 'seq', 'prev', 'hlc', 'type', 'body')


class ProtocolError(ValueError):
    """Rejected input. `code` is one of the error codes in docs/PROTOCOL-v2.md §7."""
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
            if not isinstance(k, str) or not KEY_RE.fullmatch(k):
                raise ProtocolError('bad_encoding', f'bad key {k!r} at {where}')
            _check(x, f'{where}.{k}')
        return
    raise ProtocolError('bad_encoding', f'unsupported type {type(v).__name__} at {where}')


def canonical(obj):
    """Canonical JSON bytes (§1)."""
    _check(obj)
    return json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


def b64u(b):
    return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


def unb64u(s):
    if not re.fullmatch(r'[A-Za-z0-9_-]*', s) or len(s) % 4 == 1:
        raise ValueError('not base64url')
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


# ---------- §2 keys, signatures, peer IDs ----------
def key_from_seed(seed):
    """P-256 private key from 32 seed bytes (vectors use fixed seeds; devices generate keys in their key store)."""
    d = int.from_bytes(hashlib.sha256(b'kks-ref-seed\n' + seed).digest(), 'big') % (N - 1) + 1
    return ec.derive_private_key(d, ec.SECP256R1())


def key_string(private_or_public):
    pub = private_or_public.public_key() if hasattr(private_or_public, 'public_key') else private_or_public
    return b64u(pub.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint))


def peer_id_of_key(key_str):
    raw = unb64u(key_str)
    return b64u(hashlib.sha256(raw).digest()[:24])


def peer_id(private_key):
    return peer_id_of_key(key_string(private_key))


def public_key(key_str):
    """-> public key object. Raises ValueError unless key_str is a valid uncompressed P-256 point (§2)."""
    if not isinstance(key_str, str) or not KEYSTR_RE.fullmatch(key_str):
        raise ValueError('key string')
    raw = unb64u(key_str)
    if len(raw) != 65 or raw[0] != 4:
        raise ValueError('not an uncompressed point')
    return ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw)   # checks the point is on the curve


def sign(private_key, data):
    """64-byte r‖s, low-S (§2), base64url. Deterministic (RFC 6979) so vector files regenerate identically; the
    protocol doesn't require it."""
    r, s = decode_dss_signature(private_key.sign(data, ec.ECDSA(hashes.SHA256(), deterministic_signing=True)))
    if s > N // 2:
        s = N - s
    return b64u(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))


def verify(key_str, data, sig):
    """True if sig (§2 form, low-S) is a valid signature by key_str over data."""
    try:
        if not isinstance(sig, str) or not SIG_RE.fullmatch(sig):
            return False
        raw = unb64u(sig)
        r, s = int.from_bytes(raw[:32], 'big'), int.from_bytes(raw[32:], 'big')
        if not (1 <= r < N and 1 <= s <= N // 2):
            return False
        public_key(key_str).verify(encode_dss_signature(r, s), data, ec.ECDSA(hashes.SHA256()))
        return True
    except (InvalidSignature, ValueError):
        return False


def high_s(sig):
    """The same signature with s replaced by n − s (valid ECDSA, but not allowed here; for vectors)."""
    raw = unb64u(sig)
    s = int.from_bytes(raw[32:], 'big')
    return b64u(raw[:32] + (N - s).to_bytes(32, 'big'))


# ---------- §3 entries ----------
def unsigned(entry):
    return {k: v for k, v in entry.items() if k != 'sig'}


def signed_bytes(entry):
    return DOMAIN + canonical(unsigned(entry))


def entry_id(entry):
    return hashlib.sha256(canonical(unsigned(entry))).hexdigest()


def make_entry(private_key, seq, prev, hlc, type_, body):
    e = {'v': VERSION, 'peer': peer_id(private_key), 'seq': seq, 'prev': prev, 'hlc': list(hlc), 'type': type_,
         'body': body}
    if seq == 1:
        e['key'] = key_string(private_key)
    check_fields(e, signed=False)
    e['sig'] = sign(private_key, signed_bytes(e))
    return e


def check_fields(e, signed=True):
    if not isinstance(e, dict):
        raise ProtocolError('bad_fields', 'not an object')
    want = set(BASE) | ({'sig'} if signed else set())
    if isinstance(e.get('seq'), int) and not isinstance(e.get('seq'), bool) and e.get('seq') == 1:
        want.add('key')
    if set(e) != want:
        raise ProtocolError('bad_fields', 'field set')
    _check(e)
    if type(e['v']) is not int or e['v'] != VERSION:
        raise ProtocolError('bad_version')
    if not (isinstance(e['peer'], str) and PEER_RE.fullmatch(e['peer'])):
        raise ProtocolError('bad_fields', 'peer')
    if type(e['seq']) is not int or e['seq'] < 1:
        raise ProtocolError('bad_seq')
    if e['seq'] == 1:
        if e['prev'] is not None:
            raise ProtocolError('bad_prev', 'seq 1 must have prev null')
    elif not (isinstance(e['prev'], str) and HEX64_RE.fullmatch(e['prev'])):
        raise ProtocolError('bad_prev')
    h = e['hlc']
    if not (isinstance(h, list) and len(h) == 2 and all(type(x) is int and x >= 0 for x in h)):
        raise ProtocolError('bad_fields', 'hlc')
    if not (isinstance(e['type'], str) and KEY_RE.fullmatch(e['type'])):
        raise ProtocolError('bad_fields', 'type')
    if not isinstance(e['body'], dict):
        raise ProtocolError('bad_fields', 'body')
    if signed and not isinstance(e['sig'], str):
        raise ProtocolError('bad_fields', 'sig')
    if e['seq'] == 1 and not isinstance(e['key'], str):
        raise ProtocolError('bad_fields', 'key')


def check_key(e):
    """§3 key check for a seq-1 entry (fields already checked)."""
    try:
        public_key(e['key'])
    except ValueError:
        raise ProtocolError('bad_key', 'not a valid P-256 key')
    if peer_id_of_key(e['key']) != e['peer']:
        raise ProtocolError('bad_key', 'peer is not the key\'s peer ID')


def verify_entry(e, chain_key=None):
    """Raise ProtocolError unless e is valid and correctly signed. For seq 1 the key comes from e itself; for later
    entries `chain_key` (the key of the device's seq-1 entry) is required."""
    check_fields(e)
    if e['seq'] == 1:
        check_key(e)
        chain_key = e['key']
    if chain_key is None:
        raise ProtocolError('chain_gap', 'no seq-1 entry to verify against')
    if not verify(chain_key, signed_bytes(e), e['sig']):
        raise ProtocolError('bad_sig')


# ---------- §4 chains ----------
def verify_chain(entries):
    """Entries of ONE device, any order. Valid = contiguous from seq 1 with matching prev links, all verifying against
    the seq-1 key. Returns them sorted."""
    for e in entries:
        check_fields(e)
    if len({e['peer'] for e in entries}) > 1:
        raise ProtocolError('bad_fields', 'entries from more than one device')
    firsts = {entry_id(e): e for e in entries if e['seq'] == 1}
    for e in firsts.values():
        check_key(e)
    if len(firsts) > 1:
        raise ProtocolError('fork', 'seq 1')
    key = next(iter(firsts.values()))['key'] if firsts else None
    by_seq = {}
    for e in entries:
        verify_entry(e, key)
        if e['seq'] in by_seq and entry_id(by_seq[e['seq']]) != entry_id(e):
            raise ProtocolError('fork', f'seq {e["seq"]}')
        by_seq[e['seq']] = e
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
        if wall > self.l:
            self.l, self.c = wall, 0
        else:
            self.c += 1
        return [self.l, self.c]

    def recv(self, remote, wall):
        rl, rc = remote
        if rl > wall + SKEW_MS:
            return [self.l, self.c]
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


class Log:
    """A device's own log, in memory (for generating vectors)."""
    def __init__(self, private_key):
        self.key, self.entries, self.clock = private_key, [], HLC()

    def append(self, type_, body, wall):
        prev = entry_id(self.entries[-1]) if self.entries else None
        e = make_entry(self.key, len(self.entries) + 1, prev, self.clock.now(wall), type_, body)
        self.entries.append(e)
        return e
