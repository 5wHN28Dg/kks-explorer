"""Walkdown Plant's multiplayer relay (docs/plant3d/MULTIPLAYER.md §9.1) in Python: the same protocol and limits as
relay-plant/src/index.js, the Cloudflare Worker that is deployed. Used by the tests and by the app's session harness;
it could also run on any server (`python3 relay-plant/twin.py PORT`, behind a TLS proxy for wss://).

It never sees K, P or the invite code: a room is admitted by SHA-256(admit), and the packets are passed on unread.
`Client` is a small WebSocket client for the tests and the harness."""
import base64, hashlib, hmac, ipaddress, json, os, re, socket, struct, sys, threading, time

ROOM_RE = re.compile(r'/v1/room/([0-9a-f]{32})')
ADMIT_RE = re.compile(r'[A-Za-z0-9_-]{43}')
MAX_FRAME = 1 << 20   # Cloudflare's largest WebSocket message; anything above is cut off
ID_BLOCK = 16


def address_key(ip):
    """The rate limiting key of a client address: an IPv6 address by its /64, IPv4 as it is (as in src/index.js)."""
    if ':' not in ip:
        return ip
    try:
        return str(ipaddress.IPv6Network(ip + '/64', strict=False))
    except ValueError:
        return ip

# MULTIPLAYER.md §9.1 (the same names and values as LIMITS in src/index.js)
LIMITS = {
    'members': 12, 'pending': 12, 'message': 65536, 'text': 512,
    'rate': 60, 'hostRate': 120, 'burst': 200, 'hostBurst': 400,
    'bytes': 256 * 1024, 'byteBurst': 1 << 20, 'cut': 3, 'window': 10000,
    'idle': 600000, 'quiet': 120000, 'empty': 600000, 'maxAge': 86400000, 'hello': 10000,
    'failed': 30, 'joins': 60, 'daily': 200,
    'ipCreates': 10,      # the Worker's rate limiting binding: rooms created per client address per minute
}


def now_ms():
    return time.time() * 1000


class Bucket:
    def __init__(self, size, now):
        self.v, self.at = size, now

    def take(self, n, now, rate, size):
        self.v = min(size, self.v + (now - self.at) * rate / 1000)
        self.at = now
        if self.v < n:
            return False
        self.v -= n
        return True


class Window:
    def __init__(self):
        self.slots = {}

    def add(self, now, msgs, size, window):
        s = int(now // 1000)
        cur = self.slots.setdefault(s, [0, 0])
        cur[0] += msgs
        cur[1] += size
        for k in [k for k in self.slots if k <= s - window / 1000]:
            del self.slots[k]
        return sum(v[0] for v in self.slots.values()), sum(v[1] for v in self.slots.values())


class Conn:
    """One server-side WebSocket."""
    def __init__(self, sock, rest=b''):
        self.sock, self.buf, self.lock, self.closed = sock, rest, threading.Lock(), False
        self.id = 0            # relay ID once admitted
        self.host = False
        self.gone = False
        self.at = now_ms()
        self.la = self.at      # the last message or ping once admitted (the Worker: `la` and the auto-response time)
        self.ip = ''
        self.room = None       # the Room once admitted

    def _read(self, n):
        while len(self.buf) < n:
            part = self.sock.recv(65536)
            if not part:
                raise OSError('closed')
            self.buf += part
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        """-> (opcode, data) of the next whole text (1) or binary (2) message."""
        op0, parts, total = None, [], 0
        while True:
            b0, b1 = self._read(2)
            op, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = struct.unpack('!H', self._read(2))[0]
            elif n == 127:
                n = struct.unpack('!Q', self._read(8))[0]
            if n > MAX_FRAME or total + n > MAX_FRAME:
                raise OSError('too big')
            mask = self._read(4) if b1 & 0x80 else b'\0\0\0\0'
            data = _unmask(self._read(n), mask)
            if op == 9:
                self.send(10, data); continue
            if op == 10:
                continue
            if op == 8:
                raise OSError('closed')
            if op in (1, 2):
                op0, parts, total = op, [data], n
            elif op == 0 and op0 is not None:
                parts.append(data); total += n
            else:
                raise OSError('bad frame')
            if b0 & 0x80:
                return op0, b''.join(parts)

    def send(self, op, data):
        with self.lock:
            if not self.closed:
                self.sock.sendall(_frame(op, data, None))

    def text(self, obj):
        try:
            self.send(1, json.dumps(obj, separators=(',', ':')).encode())
        except OSError:
            pass

    def close(self, code=1000, reason=''):
        with self.lock:
            if self.closed:
                return
            self.closed = True
        try:
            self.sock.sendall(_frame(8, struct.pack('!H', code) + reason.encode()[:120], None))
        except OSError:
            pass
        try:
            self.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


def _unmask(data, mask):
    n = len(data)
    if not n:
        return data
    return (int.from_bytes(data, 'big') ^ int.from_bytes((mask * (n // 4 + 1))[:n], 'big')).to_bytes(n, 'big')


def _frame(op, data, mask):
    n = len(data)
    m = 0x80 if mask else 0
    head = bytes([0x80 | op]) + (bytes([m | n]) if n < 126 else bytes([m | 126]) + struct.pack('!H', n) if n < 65536
                                 else bytes([m | 127]) + struct.pack('!Q', n))
    return head + (mask + _unmask(data, mask) if mask else data)


class Room:
    def __init__(self, admit_hash, created):
        self.admit, self.created = admit_hash, created
        self.next_id, self.id_floor = 1, 1 + ID_BLOCK
        self.empty_since = None
        self.alarm = 0           # when the Worker's alarm would next run (the quiet check runs only then)
        self.last_active = 0     # the last message of a member that has left (the others' are in their Conn)
        self.sockets = []        # every Conn of the room, admitted or not
        self.flow = {}           # relay ID -> [msgs bucket, bytes bucket, Window, slow_at]

    def members(self, except_=None):
        return [c for c in self.sockets if c.id and not c.gone and c is not except_]


class Relay:
    def __init__(self, limits=None, clock=now_ms, trust_ip_header=False):
        """trust_ip_header: take the client's address from CF-Connecting-IP, as Cloudflare sets it (tests only: a
        client can write any header to the twin)."""
        self.L = dict(LIMITS, **(limits or {}))
        self.trust_ip_header = trust_ip_header
        self.clock = clock
        self.lock = threading.Lock()
        self.rooms = {}          # room name -> Room (one Durable Object with its row)
        self.waiting = {}        # room name -> [Conn] not yet said hello (the Durable Object exists for them too)
        self.failed = {}         # room name -> [times]
        self.joined = {}         # room name -> [times]
        self.day = [None, 0]     # the Daily object
        self.ip_creates = {}     # address -> [times]
        self.stopping = False

    # ---------- the Durable Object's handlers ----------
    def _refuse(self, c, why):
        """An error, then the socket is closed; a member that is closed (`limit`) leaves as if it had closed itself.
        Called with the lock held."""
        c.text({'t': 'error', 'why': why})
        self._leave(c)
        c.close(1008, why)

    def _tell(self, room, obj, except_=None):
        for c in room.members(except_):
            c.text(obj)

    def accept(self, name, c):
        """-> False when too many sockets wait for their hello (HTTP 429)."""
        now = self.clock()
        with self.lock:
            w = self.waiting.setdefault(name, [])
            for o in list(w):
                if now - o.at > self.L['hello']:
                    w.remove(o); self._refuse(o, 'no hello')
            if len(w) >= self.L['pending']:
                return False
            c.at = now
            w.append(c)
            return True

    def hello(self, name, c, op, data):
        now = self.clock()
        L = self.L
        with self.lock:
            if c in self.waiting.get(name, []):
                self.waiting[name].remove(c)
            if c.gone:
                return False
            f = self.failed[name] = [t for t in self.failed.get(name, []) if now - t < 60000]
            j = self.joined[name] = [t for t in self.joined.get(name, []) if now - t < 60000]
            if len(f) >= L['failed']:
                self._refuse(c, 'limit'); return False

            def fail(why):
                f.append(now); self._refuse(c, why); return False
            if op != 1 or len(data) > L['text']:
                return fail('bad hello')
            try:
                m = json.loads(data.decode('utf-8'))
            except (ValueError, UnicodeDecodeError):
                return fail('bad hello')
            if not isinstance(m, dict) or m.get('t') != 'hello' or not isinstance(m.get('admit'), str) \
                    or not ADMIT_RE.fullmatch(m['admit']) or not isinstance(m.get('create'), bool) or len(m) != 3:
                return fail('bad hello')
            raw = base64.urlsafe_b64decode(m['admit'] + '=')
            if len(raw) != 32:
                return fail('bad hello')
            h = hashlib.sha256(raw).digest()
            room = self.rooms.get(name)
            if m['create']:
                if room:
                    self._refuse(c, 'exists'); return False
                if not self._may_create(c.ip, now):
                    self._refuse(c, 'limit'); return False
                room = self.rooms[name] = Room(h, now)
                return self._admit(name, room, c, now, True)
            if not room or now - room.created >= L['maxAge']:
                self._refuse(c, 'no such session'); return False   # (not counted: retries after a removal, §2.4)
            if not hmac.compare_digest(room.admit, h):
                return fail('bad admit')
            if len(room.members()) >= L['members']:
                self._refuse(c, 'full'); return False
            if len(j) >= L['joins']:
                self._refuse(c, 'limit'); return False
            if room.next_id > 65535:
                self._refuse(c, 'full'); return False
            if room.next_id >= room.id_floor:
                room.id_floor = min(room.next_id + ID_BLOCK, 65536)
            return self._admit(name, room, c, now, False)

    def _admit(self, name, room, c, now, creator):
        others = room.members()
        c.id, c.host, c.la = room.next_id, creator, now
        room.next_id += 1
        room.sockets.append(c)
        c.room = room
        room.empty_since = None
        self.joined.setdefault(name, []).append(now)
        host = next((o.id for o in others if o.host), None)
        c.text({'t': 'welcome', 'id': c.id, 'peers': [o.id for o in others], 'host': c.id if creator else host})
        self._tell(room, {'t': 'joined', 'id': c.id}, c)
        return True

    def _may_create(self, ip, now):
        ip = address_key(ip) if ip else ip
        if ip:
            t = self.ip_creates[ip] = [x for x in self.ip_creates.get(ip, []) if now - x < 60000]
            if len(t) >= self.L['ipCreates']:
                return False
            t.append(now)
        day = time.strftime('%Y-%m-%d', time.gmtime(now / 1000))
        if self.day[0] != day:
            self.day = [day, 0]
        if self.day[1] >= self.L['daily']:
            return False
        self.day[1] += 1
        return True

    def message(self, name, c, op, data):
        now = self.clock()
        L = self.L
        with self.lock:
            room = self.rooms.get(name)
            if not room or c.gone or c not in room.sockets:
                return
            size = len(data)
            rate = L['hostRate'] if c.host else L['rate']
            fl = room.flow.get(c.id)
            if not fl:
                fl = room.flow[c.id] = [Bucket(L['burst'], now), Bucket(L['byteBurst'], now), Window(), -1e18]
            m, b = fl[2].add(now, 1, size, L['window'])
            if m > L['cut'] * rate * L['window'] / 1000 or b > L['cut'] * L['bytes'] * L['window'] / 1000:
                self._refuse(c, 'limit'); return
            if size > L['message'] or not fl[0].take(1, now, rate, L['hostBurst'] if c.host else L['burst']) \
                    or not fl[1].take(size, now, L['bytes'], L['byteBurst']):
                if now - fl[3] >= 1000:
                    fl[3] = now
                    c.text({'t': 'slow'})
                return
            c.la = now
            if op == 1:
                if size > L['text']:
                    return
                try:
                    m = json.loads(data.decode('utf-8'))
                except (ValueError, UnicodeDecodeError):
                    return
                if isinstance(m, dict) and m.get('t') == 'ping':
                    c.text({'t': 'pong'})
                elif isinstance(m, dict) and m.get('t') == 'host' and not c.host:
                    for o in room.members(c):
                        o.host = False
                    c.host = True
                    self._tell(room, {'t': 'host', 'id': c.id})
                return
            if len(data) < 5:
                return
            i = 2
            while i < len(data):
                if i + 2 > len(data):
                    return
                n = struct.unpack_from('!H', data, i)[0]
                if n == 0 or i + 2 + n > len(data):
                    return
                i += 2 + n
            to = struct.unpack_from('!H', data)[0]
            if to == c.id:
                return
            out = struct.pack('!H', c.id) + data[2:]
            targets = [o for o in room.members(c) if to == 0 or o.id == to]
        for o in targets:
            try:
                o.send(2, out)
            except OSError:
                pass

    def _leave(self, c):
        if c.gone:
            return
        c.gone = True
        for w in self.waiting.values():
            if c in w:
                w.remove(c)
        room = c.room
        if room is None or c not in room.sockets:
            return
        room.sockets.remove(c)
        room.flow.pop(c.id, None)
        room.last_active = max(room.last_active, c.la)
        self._tell(room, {'t': 'left', 'id': c.id})
        if not room.members():
            room.empty_since = self.clock()

    def gone(self, name, c):
        with self.lock:
            self._leave(c)
        c.close()

    def tick(self):
        """The Durable Objects' alarms and hello timeouts (called every 50 ms by serve(), or by a test)."""
        now = self.clock()
        L = self.L
        with self.lock:
            for w in self.waiting.values():
                for o in list(w):
                    if now - o.at > L['hello']:
                        w.remove(o); self._refuse(o, 'no hello')
            for name, room in list(self.rooms.items()):
                if now >= room.created + L['maxAge']:
                    why = 'expired'
                elif room.members():
                    # a member silent past `quiet` is closed (the Worker does it at its alarm), unless every member
                    # is: then the idle rule decides
                    last = max([room.created, room.last_active] + [o.la for o in room.members()])
                    if now >= (room.alarm or room.created + min(L['idle'], L['empty'], L['maxAge'])):
                        quiet = [o for o in room.members() if now - o.la >= L['quiet']]
                        if len(quiet) < len(room.members()):
                            for o in quiet:
                                self._refuse(o, 'quiet')
                        room.alarm = min(room.created + L['maxAge'], last + L['idle'])
                    why = 'idle' if now >= last + L['idle'] else None
                else:
                    why = 'idle' if now >= (room.empty_since or room.created) + L['empty'] else None
                if not why:
                    continue
                for o in room.sockets:
                    o.gone = True
                    o.text({'t': 'error', 'why': why})
                    o.close(1000, why)
                del self.rooms[name]

    # ---------- HTTP upgrade ----------
    def handle(self, sock, addr):
        c = None
        name = None
        try:
            sock.settimeout(None)
            head = b''
            while b'\r\n\r\n' not in head:
                part = sock.recv(4096)
                if not part or len(head) > 16384:
                    sock.close(); return
                head += part
            head, rest = head.split(b'\r\n\r\n', 1)
            lines = head.decode(errors='replace').split('\r\n')
            req = lines[0].split(' ')
            path = req[1] if len(req) > 1 else ''
            hdr = {k.strip().lower(): v.strip() for k, _, v in (l.partition(':') for l in lines[1:])}
            key = hdr.get('sec-websocket-key')
            m = ROOM_RE.fullmatch(path)
            if not m:
                sock.sendall(b'HTTP/1.1 404 Not Found\r\nContent-Length: 21\r\n\r\nWalkdown Plant relay\n'); sock.close(); return
            if req[0] != 'GET' or hdr.get('upgrade', '').lower() != 'websocket' or not key:
                sock.sendall(b'HTTP/1.1 426 Upgrade Required\r\nContent-Length: 0\r\n\r\n'); sock.close(); return
            name = m[1]
            c = Conn(sock, rest)
            c.ip = hdr.get('cf-connecting-ip', addr[0]) if self.trust_ip_header else addr[0]
            if not self.accept(name, c):
                sock.sendall(b'HTTP/1.1 429 Too Many Requests\r\nContent-Length: 0\r\n\r\n'); sock.close(); return
            acc = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest()).decode()
            sock.sendall(f'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                         f'Sec-WebSocket-Accept: {acc}\r\n\r\n'.encode())
            op, data = c.recv()
            if data == b'{"t":"ping"}':      # the auto-response answers before any hello too
                c.send(1, b'{"t":"pong"}')
                op, data = c.recv()
                while data == b'{"t":"ping"}':
                    c.send(1, b'{"t":"pong"}'); op, data = c.recv()
            if not self.hello(name, c, op, data):
                return
            while True:
                op, data = c.recv()
                if op == 1 and data == b'{"t":"ping"}':   # (the auto-response: no limits, but it counts as activity)
                    c.la = self.clock()
                    c.send(1, b'{"t":"pong"}'); continue
                self.message(name, c, op, data)
        except OSError:
            pass
        finally:
            if c is not None and name is not None:
                self.gone(name, c)
            else:
                try:
                    sock.close()
                except OSError:
                    pass

    def serve(self, host='127.0.0.1', port=0):
        """Listen in a background thread. -> the port."""
        self.srv = socket.create_server((host, port))
        port = self.srv.getsockname()[1]

        def loop():
            while True:
                try:
                    s, addr = self.srv.accept()
                except OSError:
                    return
                threading.Thread(target=self.handle, args=(s, addr), daemon=True).start()

        def ticker():
            while not self.stopping:
                time.sleep(0.05)
                self.tick()
        threading.Thread(target=loop, daemon=True).start()
        threading.Thread(target=ticker, daemon=True).start()
        return port

    def stop(self):
        self.stopping = True
        self.srv.close()
        with self.lock:
            conns = [c for r in self.rooms.values() for c in r.sockets] + [c for w in self.waiting.values() for c in w]
        for c in conns:
            c.close(1001, 'stopping')


class Client:
    """A WebSocket client for the relay (tests and the session harness). `url` is ws://host:port or wss://host."""
    def __init__(self, url, room, headers=None, timeout=10):
        import ssl, urllib.parse
        u = urllib.parse.urlsplit(url)
        port = u.port or (443 if u.scheme == 'wss' else 80)
        s = socket.create_connection((u.hostname, port), timeout=timeout)
        if u.scheme == 'wss':
            ctx = ssl.create_default_context()
            ctx.minimum_version = ssl.TLSVersion.TLSv1_2   # (Cloudflare offers 1.2 and 1.3)
            s = ctx.wrap_socket(s, server_hostname=u.hostname)
        key = base64.b64encode(os.urandom(16)).decode()
        extra = ''.join(f'{k}: {v}\r\n' for k, v in (headers or {}).items())
        host = u.hostname if not u.port else f'{u.hostname}:{u.port}'
        s.sendall(f'GET /v1/room/{room} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                  f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n{extra}\r\n'.encode())
        head = b''
        while b'\r\n\r\n' not in head:
            part = s.recv(4096)
            if not part:
                raise OSError('closed during the upgrade')
            head += part
        head, rest = head.split(b'\r\n\r\n', 1)
        self.status = int(head.split(b' ')[1])
        if self.status != 101:
            s.close()
            raise ConnectionRefusedError(self.status)
        self.sock, self.buf, self.closed, self.close_reason = s, rest, False, None
        self.lock = threading.Lock()

    def _read(self, n):
        while len(self.buf) < n:
            part = self.sock.recv(65536)
            if not part:
                raise OSError('closed')
            self.buf += part
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self, timeout=5):
        """-> (opcode, data), or raises TimeoutError; a close raises ConnectionResetError (reason in close_reason)."""
        self.sock.settimeout(timeout)
        try:
            while True:
                b0, b1 = self._read(2)
                op, n = b0 & 0x0F, b1 & 0x7F
                if n == 126:
                    n = struct.unpack('!H', self._read(2))[0]
                elif n == 127:
                    n = struct.unpack('!Q', self._read(8))[0]
                data = self._read(n)
                if op == 9:
                    self._send(10, data); continue
                if op == 10:
                    continue
                if op == 8:
                    self.closed = True
                    self.close_reason = (struct.unpack('!H', data[:2])[0] if len(data) >= 2 else None, data[2:].decode(errors='replace'))
                    raise ConnectionResetError(self.close_reason)
                return op, data
        except socket.timeout:
            raise TimeoutError('nothing received')

    def json(self, timeout=5):
        """The next text message, parsed (binary messages before it are skipped)."""
        while True:
            op, data = self.recv(timeout)
            if op == 1:
                return json.loads(data)

    def binary(self, timeout=5):
        """The next binary message (text messages before it are skipped)."""
        while True:
            op, data = self.recv(timeout)
            if op == 2:
                return data

    def _send(self, op, data):
        with self.lock:
            self.sock.sendall(_frame(op, data, os.urandom(4)))

    def text(self, obj):
        self._send(1, obj if isinstance(obj, bytes) else json.dumps(obj, separators=(',', ':')).encode())

    def send(self, data):
        self._send(2, data)

    def hello(self, admit, create):
        self.text({'t': 'hello', 'admit': base64.urlsafe_b64encode(admit).decode().rstrip('='), 'create': create})
        return self.json()

    def packets(self, to, *packets):
        """Sends one relay message: `to` and the packets, each with its 2-byte length."""
        self.send(struct.pack('!H', to) + b''.join(struct.pack('!H', len(p)) + p for p in packets))

    def close(self):
        try:
            self._send(8, struct.pack('!H', 1000))
        except OSError:
            pass
        try:
            self.sock.close()
        except OSError:
            pass


def unframe(msg):
    """A relay message -> (from or to, [packets])."""
    who, i, out = struct.unpack_from('!H', msg)[0], 2, []
    while i < len(msg):
        n = struct.unpack_from('!H', msg, i)[0]
        out.append(msg[i + 2:i + 2 + n])
        i += 2 + n
    return who, out


if __name__ == '__main__':
    r = Relay()
    print('relay on port', r.serve('0.0.0.0', int(sys.argv[1]) if len(sys.argv) > 1 else 8787), flush=True)
    threading.Event().wait()
