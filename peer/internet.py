"""Sync across the internet (M5, PROTOCOL.md §18): through the plant's relay, directly when the two networks allow.

- Presence: while enabled, the device keeps a WebSocket to its plant's room on the relay (address = the manager's
  plant setting `relay`), signed in with its device key; the relay tells it which devices of the plant are online.
- Connecting to another device: both open a UDP socket, learn their public address from a STUN server, swap
  addresses through the relay and try hole punching (peer/rudp.py). If that fails within a few seconds, both open a
  pipe on the relay that passes their bytes along. Either way the sync then runs its Noise handshake (§15) over it:
  the relay never sees plant data, only encrypted bytes.
Twin of Internet.kt."""
import json, os, queue, socket, struct, threading, time

from peer import proto as P
from peer import rudp, sync as S, ws as W
from peer.relay_server import HELLO_DOMAIN, room_of

STUN = [('stun.cloudflare.com', 3478), ('stun.l.google.com', 19302)]
PUNCH_TIMEOUT = 4.0


def stun(sock, servers=STUN, timeout=1.5):
    """Ask a STUN server (RFC 5389) which public address this UDP socket's packets come from. -> (ip, port) or None."""
    for host, port in servers:
        try:
            addr = socket.getaddrinfo(host, port, socket.AF_INET, socket.SOCK_DGRAM)[0][4]
        except OSError:
            continue
        tid = os.urandom(12)
        try:
            sock.settimeout(timeout)
            sock.sendto(struct.pack('!HHI', 1, 0, 0x2112A442) + tid, addr)
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                data, src = sock.recvfrom(2048)
                if src != addr or len(data) < 20 or data[8:20] != tid:
                    continue
                i, n = 20, struct.unpack('!H', data[2:4])[0]
                while i + 4 <= 20 + n:
                    at, al = struct.unpack('!HH', data[i:i + 4])
                    v = data[i + 4:i + 4 + al]
                    if at == 0x0020 and al >= 8 and v[1] == 1:   # XOR-MAPPED-ADDRESS, IPv4
                        port_ = struct.unpack('!H', v[2:4])[0] ^ 0x2112
                        ip = socket.inet_ntoa(struct.pack('!I', struct.unpack('!I', v[4:8])[0] ^ 0x2112A442))
                        return ip, port_
                    i += 4 + al + (-al % 4)
        except OSError:
            continue
    return None


def local_ips():
    from server.syncsvc import _lan_ips   # (all interfaces, without container/VPN bridges)
    return [ip for ip in _lan_ips() if not ip.startswith('127.')]


class Internet:
    """One device's link to its plant's relay. `node` = the sync node (Engine); `relay()` -> the relay address or
    None; `record(remote, address, ok, result, direction)` = the sync status list of syncsvc."""

    def __init__(self, node, relay, record, log=print, stun_servers=STUN, allowed=lambda: True, on_change=None):
        self.node, self.relay, self.record, self.log = node, relay, record, log
        self.stun_servers, self.allowed, self.on_change = stun_servers, allowed, on_change
        self.online = set()                  # devices of the plant on the relay now
        self.waiting = {}                    # connect id -> Queue of answers
        self.ws, self.state, self.lock = None, 'off', threading.Lock()
        self.running = False
        self.gen = 0                         # a stop() + start() leaves the old presence thread behind: it quits

    # ---------- presence ----------
    def start(self):
        with self.lock:
            if not self.running:
                self.running = True
                self.gen += 1
                threading.Thread(target=self._presence, args=(self.gen,), daemon=True).start()

    def stop(self):
        with self.lock:
            self.running = False
            self.gen += 1
        if self.ws:
            self.ws.close()

    def _room(self):
        url, root = self.relay(), self.node.root()
        return (url.rstrip('/'), room_of(root)) if url and root else (None, None)

    def _presence(self, gen):
        backoff = 2
        live = lambda: self.running and self.gen == gen
        while live():
            url, room = self._room()
            if not url or not self.allowed():
                self.state = 'off' if not url else 'paused (metered network)'
                time.sleep(5)
                continue
            try:
                ws = W.WebSocket(f'{url}/v1/room/{room}', timeout=20)
                key, ts = self.node.identity(), int(time.time())
                ws.send_text(json.dumps({'t': 'hello', 'peer': P.peer_id(key), 'ts': ts,
                                         'sig': P.b64u(key.sign(HELLO_DOMAIN + room.encode() + b'\n' + str(ts).encode()))}))
                if not live():
                    ws.close()
                    break
                self.ws, backoff = ws, 2
                ws.settimeout(25)
                while live():
                    try:
                        op, data = ws.recv()
                    except socket.timeout:
                        ws.send_text('{"t":"ping"}')   # keeps it open (and the relay asleep between messages)
                        continue
                    m = json.loads(data)
                    t = m.get('t')
                    if t == 'error':
                        raise W.WsError(m.get('why') or 'refused')
                    if t == 'welcome':
                        self.online = set(m.get('peers') or [])
                        self.state = 'connected'
                        self._changed()
                    elif t == 'joined':
                        self.online.add(m['peer']); self._changed()
                    elif t == 'left':
                        self.online.discard(m['peer']); self._changed()
                    elif t == 'connect':
                        threading.Thread(target=self._answer, args=(m,), daemon=True).start()
                    elif t in ('accept', 'gone', 'refuse'):
                        q = self.waiting.get(m.get('id'))
                        if q:
                            q.put(m)
            except (OSError, ValueError, KeyError) as e:
                self.state = f'not reachable ({e})'
            finally:
                if self.gen == gen:
                    self.online = set()
                    if self.ws:
                        self.ws.close()
                    self.ws = None
                    self._changed()
            if live():
                time.sleep(backoff)
                backoff = min(backoff * 2, 60)

    def _changed(self):
        if self.on_change:
            try:
                self.on_change()
            except Exception:
                pass

    def _send(self, msg):
        ws = self.ws
        if not ws:
            raise S.SyncError('not connected to the relay')
        ws.send_text(json.dumps(msg))

    # ---------- connecting ----------
    def _udp(self):
        """A UDP socket with its candidate addresses: public (STUN) + this device's own network addresses."""
        u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        u.bind(('0.0.0.0', 0))
        port = u.getsockname()[1]
        cand = [f'{ip}:{port}' for ip in local_ips()]
        pub = stun(u, self.stun_servers) if self.stun_servers else None
        if pub:
            cand.insert(0, f'{pub[0]}:{pub[1]}')
        return u, cand[:8]

    @staticmethod
    def _addrs(cand):
        out = []
        for c in cand or []:
            host, _, port = c.rpartition(':')
            try:
                out.append((host, int(port)))
            except ValueError:
                pass
        return out

    def connect(self, peer, timeout=10):
        """A connection to `peer`: direct if hole punching works, else through a relay pipe. -> (sock, how)"""
        url, room = self._room()
        cid = os.urandom(16).hex()
        q = self.waiting[cid] = queue.Queue()
        try:
            u, cand = self._udp()
            self._send({'t': 'connect', 'to': peer, 'id': cid, 'cand': cand})
            try:
                ans = q.get(timeout=timeout)
            except queue.Empty:
                u.close()
                raise S.SyncError('the other device did not answer through the relay')
            if ans['t'] != 'accept':
                u.close()
                raise S.SyncError('the other device is not on the relay' if ans['t'] == 'gone' else 'refused')
            return self._join(u, cid, ans.get('cand'), url, room, 'a')
        finally:
            self.waiting.pop(cid, None)

    def _join(self, u, cid, their, url, room, side):
        session = bytes.fromhex(cid)[:8]
        addr = rudp.punch(u, session, self._addrs(their), timeout=PUNCH_TIMEOUT) if their else None
        if addr:
            return rudp.Stream(u, addr, session), 'direct'
        u.close()
        return W.PipeSocket(W.WebSocket(f'{url}/v1/pipe/{room}/{cid}/{side}', timeout=20)), 'relay'

    def _answer(self, m):
        """Another device wants to connect: answer, meet it (directly or through a pipe), serve its sync."""
        peer, cid = m.get('from'), m.get('id')
        url, room = self._room()
        try:
            u, cand = self._udp()
            self._send({'t': 'accept', 'to': peer, 'id': cid, 'cand': cand})
            sock, how = self._join(u, cid, m.get('cand'), url, room, 'b')
        except OSError as e:
            self.record(None, f'internet {peer[:12]}', False, str(e), 'in')
            return
        try:
            remote, st = S.serve_one(self.node, sock, timeout=60)
            if 'join' not in st:
                self.record(remote, f'internet ({how})', True, st, 'in')
        except Exception as e:
            self.record(peer, f'internet ({how})', False, str(e), 'in')

    def sync(self, peer):
        """Sync with `peer` over the internet. -> (remote, stats); raises on failure (recorded)."""
        try:
            sock, how = self.connect(peer)
        except OSError as e:
            self.record(None, f'internet {peer[:12]}', False, str(e), 'out')
            raise
        try:
            with sock:
                remote, st = S.sync_over(self.node, sock, timeout=60, expect_peer=peer)
        except Exception as e:
            self.record(peer, f'internet ({how})', False, str(e), 'out')
            raise
        self.record(remote, f'internet ({how})', True, st, 'out')
        return remote, st

    def snapshot(self):
        return {'relay': self.relay(), 'state': self.state, 'online': sorted(self.online)}
