"""Join by invite (PROTOCOL.md §16), the inviting side: an admin shows a QR code (or a code to copy) naming this
device, its addresses, the plant's root and a one-time token. The new device connects to the sync port and sends its
signed join request with the token; the admin sees who asks and accepts or refuses; the new device then syncs.

Invites live in memory only: a restart cancels them (the admin makes a new one). One device per invite: the first one
that asks with a valid request keeps it (the admin sees its name and device label before accepting).

Without a code (a laptop with no camera): the new device picks an admin's device found on the Wi-Fi and asks without a
token. The request waits in the *lobby* until any admin here accepts or refuses it; both screens show the same
6-digit code (`node.join_code`) so each person can tell they are talking to the right device."""
import secrets, threading, time

from server import node as node_mod

TTL = 15 * 60


class Invites:
    def __init__(self):
        self.lock = threading.Lock()
        self.items = {}                    # token → {by, exp, state, request, device, seen}
        self.lobby = {}                    # device → {exp, state, request, full, seen}: asked without a token

    def _gc(self):
        now = time.time()
        for t in [t for t, v in self.items.items() if v['exp'] < now - 3600]:   # answer 'expired' for an hour, then forget
            del self.items[t]

    def create(self, by, root, plant, peer, addrs):
        """-> the invite (what the QR code carries)."""
        token = secrets.token_urlsafe(16)
        exp = int(time.time()) + TTL
        with self.lock:
            self._gc()
            self.items[token] = {'by': by, 'exp': exp, 'state': 'open', 'request': None, 'device': None, 'seen': 0}
        return {'kks_invite': 1, 'plant': plant, 'root': root, 'peer': peer, 'addrs': addrs, 'token': token, 'exp': exp}

    def status(self, token, by):
        with self.lock:
            v = self.items.get(token)
            if not v or v['by'] != by:
                return None
            state = 'expired' if v['exp'] < time.time() and v['state'] in ('open', 'asked') else v['state']
            return {'state': state, 'exp': v['exp'], 'request': v['request'], 'seen': v['seen']}

    def cancel(self, token, by):
        with self.lock:
            v = self.items.get(token)
            if v and v['by'] == by and v['state'] in ('open', 'asked'):
                v['state'] = 'cancelled'

    def take(self, token, by):
        """-> the pending request to decide on (the caller certifies it, then calls done())."""
        with self.lock:
            v = self.items.get(token)
            if not v or v['by'] != by:
                return None
            if v['exp'] < time.time() or v['state'] != 'asked':
                return None
            return v['request']

    def done(self, token, accepted):
        with self.lock:
            v = self.items.get(token)
            if v and v['state'] == 'asked':
                v['state'] = 'accepted' if accepted else 'refused'

    # ---------- the lobby (no token) ----------
    def lobby_list(self):
        with self.lock:
            now = time.time()
            return [{'device': d, 'request': v['request'], 'seen': v['seen'], 'exp': v['exp']}
                    for d, v in self.lobby.items() if v['state'] == 'asked' and v['exp'] >= now]

    def lobby_take(self, device):
        with self.lock:
            v = self.lobby.get(device)
            return v['full'] if v and v['state'] == 'asked' and v['exp'] >= time.time() else None

    def lobby_done(self, device, accepted):
        with self.lock:
            v = self.lobby.get(device)
            if v and v['state'] == 'asked':
                v['state'] = 'accepted' if accepted else 'refused'
                v['exp'] = time.time() + TTL   # (keep answering the device for a while)

    def _lobby_offer(self, remote, msg, ack):
        with self.lock:
            now = time.time()
            for d in [d for d, v in self.lobby.items() if v['exp'] < now]:
                del self.lobby[d]
            v = self.lobby.get(remote)
            if v and v['state'] in ('accepted', 'refused'):
                return ack(v['state'])
            if v:
                v['seen'] = int(now)
                return ack('waiting')
            if len(self.lobby) >= 50:
                return ack('used', 'too many devices are waiting here; try again later')
        try:
            req = node_mod.check_join_request(msg.get('request'))
        except node_mod.JoinError as e:
            return ack('bad', str(e))
        if req.get('device') != remote:
            return ack('bad', 'the join request is not from the device that sent it')
        with self.lock:
            self.lobby.setdefault(remote, {'exp': time.time() + TTL, 'state': 'asked', 'seen': int(time.time()), 'full': req,
                                           'request': {k: req.get(k) for k in ('device', 'username', 'full_name', 'position', 'label')}})
        return ack('waiting')

    # ---------- the sync listener's side ----------
    def offer(self, remote, msg):
        """A device asks with a token (or none: the lobby) and its join request. -> the join_ack message."""
        def ack(state, why=None):
            return {'t': 'join_ack', 'state': state, **({'why': why} if why else {})}
        token = msg.get('token')
        if token is None:
            return self._lobby_offer(remote, msg, ack)
        with self.lock:
            v = self.items.get(token) if isinstance(token, str) else None
            if not v or v['state'] == 'cancelled':
                return ack('unknown', 'this invite was cancelled or never existed here')
            if v['device'] not in (None, remote):
                return ack('used', 'another device is already using this invite')
            if v['state'] in ('accepted', 'refused'):
                return ack(v['state'])
            if v['exp'] < time.time():
                return ack('unknown', 'this invite has expired; ask for a new one')
            if v['state'] == 'asked':
                v['seen'] = int(time.time())
                return ack('waiting')
        try:
            req = node_mod.check_join_request(msg.get('request'))
        except node_mod.JoinError as e:
            return ack('bad', str(e))
        if req.get('device') != remote:
            return ack('bad', 'the join request is not from the device that sent it')
        with self.lock:
            if v['device'] not in (None, remote):
                return ack('used', 'another device is already using this invite')
            v.update(state='asked', device=remote, seen=int(time.time()),
                     request={k: req.get(k) for k in ('device', 'username', 'full_name', 'position', 'label')})
            v['full'] = req
        return ack('waiting')

    def full_request(self, token):
        with self.lock:
            v = self.items.get(token)
            return v and v.get('full')
