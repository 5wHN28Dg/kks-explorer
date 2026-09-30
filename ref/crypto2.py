"""Protocol v2 pieces outside the log (docs/PROTOCOL-v2.md §16, §18, §20). Test-only reference."""
import hashlib, os

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

from ref import proto2 as P

PBKDF2_MIN_ITER = 600_000


# ---------- §16 join ----------
def join_code(joiner_peer, answering_peer):
    d = hashlib.sha256(b'kks-join-code-v2\n' + joiner_peer.encode() + b'\n' + answering_peer.encode()).digest()
    return f'{int.from_bytes(d[:4], "big") % 1_000_000:06d}'


def join_request(device_key, username, full_name, position, label, created):
    req = {'kks_join': 2, 'device': P.peer_id(device_key), 'key': P.key_string(device_key), 'username': username,
           'full_name': full_name, 'position': position, 'label': label, 'created': created}
    req['sig'] = P.sign(device_key, b'kks-join-v2\n' + P.canonical(req))
    return req


def check_join_request(req):
    """True if the request is well formed and signed by its own key, whose peer ID is `device`."""
    try:
        rest = {k: v for k, v in req.items() if k != 'sig'}
        return (req.get('kks_join') == 2 and P.peer_id_of_key(req['key']) == req['device']
                and P.verify(req['key'], b'kks-join-v2\n' + P.canonical(rest), req['sig']))
    except (KeyError, ValueError, TypeError, P.ProtocolError):
        return False


# ---------- §18 relay ----------
def relay_room(root_key_str):
    return hashlib.sha256(b'kks-relay-room-v2\n' + P.peer_id_of_key(root_key_str).encode()).hexdigest()[:32]


def relay_hello(device_key, room, ts):
    return {'t': 'hello', 'peer': P.peer_id(device_key), 'key': P.key_string(device_key), 'ts': ts,
            'sig': P.sign(device_key, b'kks-relay-hello-v2\n' + room.encode() + b'\n' + str(ts).encode())}


def check_relay_hello(h, room, now, skew=300):
    try:
        return (P.peer_id_of_key(h['key']) == h['peer'] and abs(h['ts'] - now) <= skew
                and P.verify(h['key'], b'kks-relay-hello-v2\n' + room.encode() + b'\n' + str(h['ts']).encode(), h['sig']))
    except (KeyError, ValueError, TypeError):
        return False


# ---------- §20 encryption to a key ----------
def _raw(pub):
    return pub.public_bytes(serialization.Encoding.X962, serialization.PublicFormat.UncompressedPoint)


def ecies_seal(recipient_key_str, purpose, plaintext, eph=None, nonce=None):
    eph = eph or ec.generate_private_key(ec.SECP256R1())
    nonce = nonce or os.urandom(12)
    rpub = P.public_key(recipient_key_str)
    shared = eph.exchange(ec.ECDH(), rpub)
    k = HKDF(hashes.SHA256(), 32, _raw(eph.public_key()) + _raw(rpub),
             b'kks-ecies-v2\n' + purpose.encode()).derive(shared)
    ct = AESGCM(k).encrypt(nonce, plaintext, purpose.encode())
    return {'v': 2, 'purpose': purpose, 'epk': P.key_string(eph), 'nonce': P.b64u(nonce), 'ct': P.b64u(ct)}


def ecies_open(recipient_private, obj):
    epub = P.public_key(obj['epk'])
    shared = recipient_private.exchange(ec.ECDH(), epub)
    k = HKDF(hashes.SHA256(), 32, _raw(epub) + _raw(recipient_private.public_key()),
             b'kks-ecies-v2\n' + obj['purpose'].encode()).derive(shared)
    return AESGCM(k).decrypt(P.unb64u(obj['nonce']), P.unb64u(obj['ct']), obj['purpose'].encode())


def passphrase_seal(passphrase, plaintext, iterations=PBKDF2_MIN_ITER, salt=None, nonce=None):
    if iterations < PBKDF2_MIN_ITER:
        raise ValueError('at least 600000 iterations (docs/decisions/0023)')
    salt = salt or os.urandom(16)
    nonce = nonce or os.urandom(12)
    k = PBKDF2HMAC(hashes.SHA256(), 32, salt, iterations).derive(passphrase.encode('utf-8'))
    ct = AESGCM(k).encrypt(nonce, plaintext, b'kks-root-backup-v2\n')
    return {'v': 2, 'kdf': 'pbkdf2-sha256', 'iter': iterations, 'salt': P.b64u(salt), 'nonce': P.b64u(nonce),
            'ct': P.b64u(ct)}


def passphrase_open(passphrase, obj):
    k = PBKDF2HMAC(hashes.SHA256(), 32, P.unb64u(obj['salt']), obj['iter']).derive(passphrase.encode('utf-8'))
    return AESGCM(k).decrypt(P.unb64u(obj['nonce']), P.unb64u(obj['ct']), b'kks-root-backup-v2\n')
