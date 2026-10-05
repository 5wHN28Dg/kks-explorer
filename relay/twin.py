"""The internet relay (PROTOCOL-v2.md §18), in Python: the same protocol as relay/src/index.js (the Cloudflare
Worker that is deployed). Used by the tests; it could also run on any server (`python3 relay/twin.py PORT`).

It never sees plant data: devices meet here per plant ("room"), prove they hold their device key, exchange addresses
to try a direct connection (hole punching), and, if that fails, get a pipe that passes their end-to-end encrypted
sync bytes along unread."""
import base64, hashlib, json, re, socket, struct, sys, threading, time

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.utils import encode_dss_signature
from cryptography.hazmat.primitives import hashes
import hashlib

HELLO_DOMAIN2 = b'kks-relay-hello-v2\n'
PEER2_RE = re.compile(r'[A-Za-z0-9_-]{32}')
ROOM_RE, ID_RE = re.compile(r'[0-9a-f]{32}'), re.compile(r'[0-9a-f]{32}')
MAX_PEERS, PIPE_WAIT = 200, 30


def cand_ok(c):
    return isinstance(c, list) and len(c) <= 8 and all(isinstance(x, str) and len(x) <= 64 and ':' in x for x in c)


class Conn:
    """One server-side WebSocket."""
    def __init__(self, sock):
        self.sock, self.buf, self.lock, self.closed = sock, b'', threading.Lock(), False

    def _read(self, n):
        while len(self.buf) < n:
            part = self.sock.recv(65536)
            if not part:
                raise OSError('closed')
            self.buf += part
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        while True:
            b0, b1 = self._read(2)
            op, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = struct.unpack('!H', self._read(2))[0]
            elif n == 127:
                n = struct.unpack('!Q', self._read(8))[0]
            mask = self._read(4) if b1 & 0x80 else b'\0\0\0\0'
            data = self._read(n)
            data = bytes(b ^ mask[i % 4] for i, b in enumerate(data)) if n < 4096 else \
                (int.from_bytes(data, 'big') ^ int.from_bytes((mask * (n // 4 + 1))[:n], 'big')).to_bytes(n, 'big')
            if op == 9:
                self.send(10, data); continue
            if op == 10:
                continue
            if op == 8:
                raise OSError('closed')
            return op, data

    def send(self, op, data):
        n = len(data)
        head = bytes([0x80 | op]) + (bytes([n]) if n < 126 else bytes([126]) + struct.pack('!H', n) if n < 65536
                                     else bytes([127]) + struct.pack('!Q', n))
        with self.lock:
            if not self.closed:
                self.sock.sendall(head + data)

    def text(self, obj):
        self.send(1, json.dumps(obj).encode())

    def close(self):
        with self.lock:
            if self.closed:
                return
            self.closed = True
        try:
            self.sock.sendall(b'\x88\x02\x03\xe8')
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


class Relay:
    def __init__(self):
        self.lock = threading.Lock()
        self.rooms = {}      # room -> {peer: Conn}
        self.pipes = {}      # (room, id) -> {'a': Conn, 'b': Conn, 'at': t}

    # ---------- presence + signaling ----------
    def room(self, room, c):
        try:
            op, data = c.recv()
            m = json.loads(data)
            peer, ts, sig = m.get('peer'), m.get('ts'), m.get('sig')
            if m.get('t') != 'hello' or not isinstance(peer, str) or not PEER2_RE.fullmatch(peer) \
                    or not isinstance(ts, int) or abs(ts - time.time()) > 300 or not isinstance(sig, str) \
                    or not isinstance(m.get('key'), str):
                raise ValueError('bad hello')
            unb = lambda x: base64.urlsafe_b64decode(x + '=' * (-len(x) % 4))
            # PROTOCOL-v2 §18: P-256, ECDSA-SHA256 with r ‖ s, peer ID = first 24 bytes of SHA-256(key)
            raw = unb(m['key'])
            if hashlib.sha256(raw).digest()[:24] != unb(peer):
                raise ValueError('bad hello')
            r, s_ = int.from_bytes(unb(sig)[:32], 'big'), int.from_bytes(unb(sig)[32:], 'big')
            ec.EllipticCurvePublicKey.from_encoded_point(ec.SECP256R1(), raw).verify(
                encode_dss_signature(r, s_), HELLO_DOMAIN2 + room.encode() + b'\n' + str(ts).encode(), ec.ECDSA(hashes.SHA256()))
        except (OSError, ValueError, InvalidSignature, TypeError, KeyError):
            c.text({'t': 'error', 'why': 'bad hello'}); c.close(); return
        with self.lock:
            members = self.rooms.setdefault(room, {})
            old = members.get(peer)
            if len(members) >= MAX_PEERS and not old:
                c.text({'t': 'error', 'why': 'room full'}); c.close(); return
            members[peer] = c
            others = [p for p in members if p != peer]
        if old:
            old.close()
        c.text({'t': 'welcome', 'peers': others})
        self._tell(room, {'t': 'joined', 'peer': peer}, but=peer)
        try:
            while True:
                op, data = c.recv()
                if data == b'{"t":"ping"}':
                    c.send(1, b'{"t":"pong"}'); continue
                try:
                    m = json.loads(data)
                except ValueError:
                    continue
                t, to, cid = m.get('t'), m.get('to'), m.get('id')
                if t not in ('connect', 'accept', 'pipe', 'refuse') or not isinstance(to, str) or not isinstance(cid, str) \
                        or not ID_RE.fullmatch(cid) or ('cand' in m and not cand_ok(m['cand'])):
                    continue
                out = {'t': t, 'from': peer, 'id': cid, **({'cand': m['cand']} if 'cand' in m else {})}
                with self.lock:
                    target = self.rooms.get(room, {}).get(to)
                if target:
                    try:
                        target.text(out)
                    except OSError:
                        pass
                else:
                    c.text({'t': 'gone', 'id': cid, 'peer': to})
        except OSError:
            pass
        finally:
            with self.lock:
                if self.rooms.get(room, {}).get(peer) is c:
                    del self.rooms[room][peer]
                    gone = True
                else:
                    gone = False
            c.close()
            if gone:
                self._tell(room, {'t': 'left', 'peer': peer})

    def _tell(self, room, msg, but=None):
        with self.lock:
            targets = [c for p, c in self.rooms.get(room, {}).items() if p != but]
        for c in targets:
            try:
                c.text(msg)
            except OSError:
                pass

    # ---------- pipes: pass bytes between two devices that couldn't reach each other directly ----------
    def pipe(self, room, cid, side, c):
        key = (room, cid)
        with self.lock:
            p = self.pipes.setdefault(key, {'at': time.time()})
            if side in p:
                c.close(); return
            p[side] = c
            other = p.get('b' if side == 'a' else 'a')
        if not other:   # wait for the other side (it may still be trying to punch)
            end = time.time() + PIPE_WAIT
            while time.time() < end:
                with self.lock:
                    other = self.pipes.get(key, {}).get('b' if side == 'a' else 'a')
                if other or c.closed:
                    break
                time.sleep(0.05)
            if not other:
                with self.lock:
                    self.pipes.pop(key, None)
                c.close(); return
        try:
            while True:
                op, data = c.recv()
                if op == 2:
                    other.send(2, data)
        except OSError:
            pass
        finally:
            c.close(); other.close()
            with self.lock:
                self.pipes.pop(key, None)

    # ---------- HTTP upgrade ----------
    def handle(self, sock):
        try:
            sock.settimeout(None)
            head = b''
            while b'\r\n\r\n' not in head:
                part = sock.recv(4096)
                if not part:
                    return
                head += part
            head, rest = head.split(b'\r\n\r\n', 1)
            lines = head.decode(errors='replace').split('\r\n')
            path = lines[0].split(' ')[1] if len(lines[0].split(' ')) > 1 else ''
            hdr = {k.strip().lower(): v.strip() for k, _, v in (l.partition(':') for l in lines[1:])}
            key = hdr.get('sec-websocket-key')
            m1 = re.fullmatch(r'/v1/room/([0-9a-f]{32})', path)
            m2 = re.fullmatch(r'/v1/pipe/([0-9a-f]{32})/([0-9a-f]{32})/(a|b)', path)
            if not key or not (m1 or m2):
                sock.sendall(b'HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n'); sock.close(); return
            acc = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            sock.sendall(f'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                         f'Sec-WebSocket-Accept: {acc}\r\n\r\n'.encode())
            c = Conn(sock); c.buf = rest
            if m1:
                self.room(m1[1], c)
            else:
                self.pipe(m2[1], m2[2], m2[3], c)
        except OSError:
            pass

    def serve(self, host='127.0.0.1', port=0):
        """Listen in a background thread. -> the port."""
        self.srv = socket.create_server((host, port))
        port = self.srv.getsockname()[1]

        def loop():
            while True:
                try:
                    s, _ = self.srv.accept()
                except OSError:
                    return
                threading.Thread(target=self.handle, args=(s,), daemon=True).start()
        threading.Thread(target=loop, daemon=True).start()
        return port

    def stop(self):
        self.srv.close()


if __name__ == '__main__':
    r = Relay()
    print('relay on port', r.serve('0.0.0.0', int(sys.argv[1]) if len(sys.argv) > 1 else 8787))
    threading.Event().wait()
