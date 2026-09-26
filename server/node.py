"""Peer mode (a laptop that is one person's device): joining a plant.

- Through a server: the laptop sends its device ID with the person's username and password to the server's
  `/api/devices/enroll`; the server certifies the device for that person (signed by the person's own custodial key,
  PROTOCOL.md §10: a person's device may certify their other devices) and answers with the plant's root and sync
  port; the laptop then syncs with the server.
- Without a server: the laptop makes a *join request* (its device ID + who it is, signed with the device key); an admin
  imports it (Manage → Devices), which certifies the device, and hands back a bundle file; importing the bundle here
  finishes the join (the bundle names the plant)."""
import json, socket, time, urllib.error, urllib.request
from urllib.parse import urlparse

from peer import proto as P

JOIN_DOMAIN = b'kks-join-v1\n'


class JoinError(Exception):
    pass


def label():
    return (socket.gethostname() or 'laptop')[:80]


def join_via_server(E, svc, url, username, password):
    if E.anchor is not None and E.owner():
        raise JoinError('this laptop already belongs to a plant')
    dev = E.ensure_node_device()
    u = urlparse(url if '://' in url else 'http://' + url)
    if not u.hostname:
        raise JoinError('enter the server address, e.g. http://192.168.1.20:8420')
    base = f'{u.scheme}://{u.netloc}'
    req = urllib.request.Request(base + '/api/devices/enroll', method='POST',
                                 data=json.dumps({'username': username, 'password': password, 'device': dev,
                                                  'label': label()}).encode(),
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            answer = json.loads(r.read())
    except urllib.error.HTTPError as e:
        try:
            msg = json.loads(e.read()).get('error')
        except ValueError:
            msg = None
        raise JoinError(msg or f'the server answered {e.code}')
    except (urllib.error.URLError, OSError) as e:
        raise JoinError(f'cannot reach {base}: {getattr(e, "reason", e)}')
    if not answer.get('sync_port'):
        raise JoinError('that server does not accept devices (its sync_port is 0)')
    try:
        svc.sync_one(u.hostname, answer['sync_port'], adopt_root=None if E.anchor else answer['root'])
    except Exception as e:
        raise JoinError(f'the server certified this laptop, but syncing failed: {e}. Try "Sync now" later.')
    if not E.owner():
        raise JoinError('synced, but this laptop is not certified in what came back')
    svc.joined()
    return E.owner()


def join_request(E, username, full_name, position):
    """-> the request (a dict to save as a file). Signed by this laptop's key, so an admin knows who holds it."""
    dev = E.ensure_node_device()
    req = {'kks_join': 1, 'device': dev, 'username': username, 'full_name': full_name, 'position': position,
           'label': label(), 'created': int(time.time())}
    req['sig'] = P.b64u(E.keys[dev].sign(JOIN_DOMAIN + P.canonical(req)))
    return req


def check_join_request(req):
    """-> the request without its signature, or raises JoinError."""
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    if not isinstance(req, dict) or req.get('kks_join') != 1:
        raise JoinError('not a join request file')
    body = {k: v for k, v in req.items() if k != 'sig'}
    try:
        Ed25519PublicKey.from_public_bytes(P.unb64u(req['device'])).verify(P.unb64u(req['sig']),
                                                                           JOIN_DOMAIN + P.canonical(body))
    except (KeyError, ValueError, TypeError, InvalidSignature, P.ProtocolError):
        raise JoinError('the join request is damaged or was changed after it was made')
    return body
