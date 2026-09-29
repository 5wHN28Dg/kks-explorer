"""Sync between two peers (docs/PROTOCOL.md §15): a Noise XX connection authenticated by device keys, then an exchange
of the log entries (and photo blobs) each side lacks. Transport-independent: works on any socket-like object with
sendall()/recv() (TCP on the same Wi-Fi now; later anything that carries bytes).

A node is anything with these methods (server/engine.Engine implements them; the Kotlin core will too):
    identity() -> Ed25519 private key          root() -> trust anchor or None     adopt(root)
    vv() -> {peer: [last seq, entry ID]}       entries_for(vv) -> [entry]         ingest([entry]) -> number new
    may_read(peer) -> bool                     blob_wants() -> [sha]
    blob_get(sha) -> bytes or None             blob_put(sha, bytes) -> bool
"""
import base64, hashlib, hmac, json, socket, struct

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

from peer import noise as N
from peer import proto as P

VERSION = 1
PROLOGUE = b'kks-sync-v1'
STATIC_DOMAIN = b'kks-noise-static-v1\n'
CHUNK = 65000                 # plaintext bytes per transport message (Noise limit 65535 incl. 16-byte tag)
MAX_MESSAGE = 64 * 2 ** 20    # one application message (a batch of entries, one photo)
TIMEOUT = 30


class SyncError(Exception):
    pass


def static_key(identity):
    """The X25519 key a device uses in Noise, derived from its Ed25519 seed (so there is nothing extra to store)."""
    seed = identity.private_bytes(serialization.Encoding.Raw, serialization.PrivateFormat.Raw,
                                  serialization.NoEncryption())
    return N.x25519(hmac.new(seed, b'kks-noise-static-v1', hashlib.sha256).digest())


def _static_pub(priv):
    return priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)


def identity_payload(identity, static_priv):
    sig = identity.sign(STATIC_DOMAIN + _static_pub(static_priv))
    return P.canonical({'peer': P.peer_id(identity), 'sig': P.b64u(sig)})


def check_identity(payload, remote_static):
    """-> peer ID of the device that owns `remote_static`."""
    try:
        d = json.loads(payload)
        Ed25519PublicKey.from_public_bytes(P.unb64u(d['peer'])).verify(P.unb64u(d['sig']), STATIC_DOMAIN + remote_static)
        if len(d['peer']) != 43:
            raise ValueError
        return d['peer']
    except (ValueError, KeyError, TypeError, InvalidSignature):
        raise SyncError('the other side did not prove its device key')


# ---------- framing ----------
def _recv_exact(sock, n):
    buf = b''
    while len(buf) < n:
        part = sock.recv(n - len(buf))
        if not part:
            raise SyncError('connection closed')
        buf += part
    return buf


def _send_frame(sock, data):
    sock.sendall(struct.pack('>H', len(data)) + data)


def _recv_frame(sock):
    return _recv_exact(sock, struct.unpack('>H', _recv_exact(sock, 2))[0])


class Session:
    """An established, encrypted connection. send()/recv() whole JSON messages."""
    def __init__(self, sock, send_cipher, recv_cipher, remote):
        self.sock, self.tx, self.rx, self.remote = sock, send_cipher, recv_cipher, remote

    def send(self, obj):
        data = json.dumps(obj, separators=(',', ':')).encode()
        for i in range(0, max(len(data), 1), CHUNK):
            part = data[i:i + CHUNK]
            more = b'\x01' if i + CHUNK < len(data) else b'\x00'
            _send_frame(self.sock, self.tx.encrypt(b'', more + part))

    def recv(self):
        data = b''
        while True:
            pt = self.rx.decrypt(b'', _recv_frame(self.sock))
            data += pt[1:]
            if len(data) > MAX_MESSAGE:
                raise SyncError('message too large')
            if pt[:1] == b'\x00':
                break
        try:
            obj = json.loads(data)
        except ValueError:
            raise SyncError('bad message')
        if not isinstance(obj, dict) or not isinstance(obj.get('t'), str):
            raise SyncError('bad message')
        if obj['t'] == 'error':
            raise SyncError('the other side stopped: ' + str(obj.get('why'))[:200])
        return obj

    def expect(self, t):
        obj = self.recv()
        if obj['t'] != t:
            raise SyncError(f'expected {t}, got {obj["t"]}')
        return obj


def handshake(sock, identity, initiator):
    """Noise XX; each side's payload proves its device key owns its Noise static key. -> Session."""
    s = static_key(identity)
    hs = N.Handshake(initiator, s, PROLOGUE)
    try:
        if initiator:
            _send_frame(sock, hs.write(b''))
            remote = check_identity(hs.read(_recv_frame(sock)), hs.rs)
            _send_frame(sock, hs.write(identity_payload(identity, s)))
        else:
            hs.read(_recv_frame(sock))
            _send_frame(sock, hs.write(identity_payload(identity, s)))
            remote = check_identity(hs.read(_recv_frame(sock)), hs.rs)
    except N.NoiseError as e:
        raise SyncError(f'handshake failed: {e}')
    tx, rx = hs.split()
    return Session(sock, tx, rx, remote)


# ---------- the exchange ----------
def exchange(ses, node, initiator, adopt_root=None, first=None):
    """Run one sync over an established session. The initiator speaks first at every step.
    adopt_root: a node with no plant yet accepts the other side's plant only if its root equals this value.
    first: the initiator's first message, if the responder already read it (serve_one).
    -> {'sent', 'received', 'blobs_sent', 'blobs_received', 'denied' (we sent nothing), 'they_denied'}"""
    def turn(mine, t):
        nonlocal first
        if initiator:
            ses.send(mine)
            return ses.expect(t)
        theirs, first = (first, None) if first is not None else (ses.expect(t), None)
        if theirs['t'] != t:
            raise SyncError(f'expected {t}, got {theirs["t"]}')
        ses.send(mine)
        return theirs

    root = node.root()
    hello = turn({'t': 'hello', 'v': VERSION, 'root': root, 'vv': node.vv()}, 'hello')
    if hello.get('v') != VERSION:
        raise SyncError(f'protocol version {hello.get("v")} (this device speaks {VERSION})')
    theirs = hello.get('root')
    if root is None:
        if theirs is None or theirs != adopt_root:
            raise SyncError('this device has no plant yet and the other side\'s plant was not the expected one')
        node.adopt(theirs)
    elif theirs is not None and theirs != root:
        raise SyncError('the other device belongs to a different plant')
    stats = _zero()
    vv = hello.get('vv') if isinstance(hello.get('vv'), dict) else {}

    def offer():
        if not node.may_read(ses.remote):
            stats['denied'] = True
            why = getattr(node, 'revocation_of', lambda d: None)(ses.remote)   # a removed device: show it the proof
            return {'t': 'entries', 'entries': [], 'denied': True, **({'revoked': why} if why else {})}
        out = node.entries_for(vv)
        stats['sent'] = len(out)
        return {'t': 'entries', 'entries': out}

    # entries: the responder decides what to send only after taking in the initiator's (its cert may be among them)
    if initiator:
        ses.send(offer())
        got = ses.expect('entries')
        stats['received'] = node.ingest(got.get('entries') or [])
    else:
        got = ses.expect('entries')
        stats['received'] = node.ingest(got.get('entries') or [])
        ses.send(offer())
    stats['they_denied'] = got.get('denied') is True
    if got.get('revoked') and getattr(node, 'accept_revocation', lambda e: False)(got['revoked']):
        raise SyncError('this device was removed from the plant; its plant data has been deleted here')
    their_want = turn({'t': 'want', 'blobs': node.blob_wants()}, 'want').get('blobs') or []

    def send_blobs():
        if node.may_read(ses.remote):
            for sha in their_want[:10000]:
                data = node.blob_get(sha) if isinstance(sha, str) else None
                if data is not None:
                    ses.send({'t': 'blob', 'sha': sha, 'data': base64.b64encode(data).decode()})
                    stats['blobs_sent'] += 1
        ses.send({'t': 'blobs_end'})

    def recv_blobs():
        while True:
            m = ses.recv()
            if m['t'] == 'blobs_end':
                return
            if m['t'] != 'blob':
                raise SyncError('expected blob')
            try:
                data = base64.b64decode(m['data'], validate=True)
            except (ValueError, KeyError, TypeError):
                raise SyncError('bad blob')
            if node.blob_put(m.get('sha'), data):
                stats['blobs_received'] += 1

    if initiator:
        send_blobs(); recv_blobs()
    else:
        recv_blobs(); send_blobs()
    turn({'t': 'bye'}, 'bye')
    return stats


def _zero():
    return {'sent': 0, 'received': 0, 'blobs_sent': 0, 'blobs_received': 0, 'denied': False, 'they_denied': False}


# ---------- TCP ----------
def sync_with(node, host, port, adopt_root=None, timeout=TIMEOUT):
    """Connect to a peer, sync, close. -> (remote peer ID, stats)"""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        return sync_over(node, sock, adopt_root, timeout)


def _fresh(node):
    """A node whose database another process also writes (server/engine.py: the CLI, e.g. `app.py publish-data`)
    picks those entries and blobs up before a session, or it would offer a stale view until some web request came."""
    if hasattr(node, 'refresh'):
        node.refresh()


def sync_over(node, sock, adopt_root=None, timeout=TIMEOUT, expect_peer=None):
    """Sync as the initiator over an open connection: TCP, a UDP stream after hole punching (peer/rudp.py) or a
    relay pipe (peer/ws.py). expect_peer: stop unless the other side is that device. -> (remote, stats)"""
    _fresh(node)
    sock.settimeout(timeout)
    ses = handshake(sock, node.identity(), True)
    if expect_peer and ses.remote != expect_peer:
        raise SyncError('a different device answered')
    return ses.remote, exchange(ses, node, True, adopt_root)


def serve_one(node, sock, timeout=TIMEOUT):
    """Handle one incoming connection (call from the listener's thread). -> (remote, stats); errors propagate.
    A connection may instead carry one join-by-invite question (PROTOCOL.md §16): stats then has 'join' = the answer."""
    _fresh(node)
    sock.settimeout(timeout)
    try:
        ses = handshake(sock, node.identity(), False)
        try:
            first = ses.recv()
            if first['t'] == 'secrets':   # §17: two devices of one person swap their person secrets
                offer = getattr(node, 'secrets_offer', None)
                ses.send(offer(ses.remote, first) if offer else {'t': 'secrets', 'secrets': []})
                return ses.remote, {**_zero(), 'join': 'secrets'}
            if first['t'] == 'join':
                offer = getattr(node, 'join_offer', None)
                ack = offer(ses.remote, first) if offer else {'t': 'join_ack', 'state': 'unknown'}
                ses.send(ack)
                return ses.remote, {**_zero(), 'join': ack['state']}
            return ses.remote, exchange(ses, node, False, first=first)
        except SyncError as e:
            try:
                ses.send({'t': 'error', 'why': str(e)})
            except OSError:
                pass
            raise
    finally:
        sock.close()


def join_ask(identity, host, port, expect_peer, token, request, timeout=TIMEOUT):
    """Join by invite (PROTOCOL.md §16): ask the inviting device whether this device's join request was accepted.
    The other end must be the device named in the invite (or picked on the Wi-Fi; token None: ask without one).
    -> (state: waiting | accepted | refused | used | unknown | bad, why, the answer message)"""
    with socket.create_connection((host, port), timeout=timeout) as sock:
        sock.settimeout(timeout)
        ses = handshake(sock, identity, True)
        if ses.remote != expect_peer:
            raise SyncError('a different device answered at that address (not the one that showed the invite)')
        ses.send({'t': 'join', 'token': token, 'request': request})
        ack = ses.expect('join_ack')
        state = ack.get('state')
        if state not in ('waiting', 'accepted', 'refused', 'used', 'unknown', 'bad'):
            raise SyncError('bad join answer')
        return state, str(ack.get('why') or '')[:200], ack


def secrets_swap(identity, host, port, expect_peer, person, mine, timeout=TIMEOUT, sock=None):
    """§17: give another device of the same person our person secrets and get theirs. The other end must be that
    device (checked here) and checks the same about us. sock: an open connection to use instead of TCP to host:port.
    -> their secrets (bytes)"""
    sock = sock or socket.create_connection((host, port), timeout=timeout)
    with sock:
        sock.settimeout(timeout)
        ses = handshake(sock, identity, True)
        if ses.remote != expect_peer:
            raise SyncError('a different device answered')
        ses.send({'t': 'secrets', 'person': person, 'secrets': [P.b64u(s) for s in mine]})
        got = ses.expect('secrets').get('secrets')
        out = []
        for s in (got if isinstance(got, list) else [])[:16]:
            try:
                b = P.unb64u(s)
            except (P.ProtocolError, TypeError, ValueError):
                continue
            if len(b) == 32:
                out.append(b)
        return out
