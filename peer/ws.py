"""A small WebSocket client (RFC 6455) on the standard library, for the internet relay (M5, PROTOCOL.md §18).

Only what the relay needs: text and binary messages, ping/pong, close; TLS for wss://. `PipeSocket` makes a relay
pipe look like a socket (sendall / recv / settimeout / close), so the sync (peer/sync.py) runs over it unchanged.
Twin of WsClient.kt."""
import base64, os, socket, ssl, struct, threading
from urllib.parse import urlparse

TEXT, BINARY, CLOSE, PING, PONG = 1, 2, 8, 9, 10


class WsError(OSError):
    pass


class WebSocket:
    def __init__(self, url, timeout=15, headers=None):
        u = urlparse(url)
        if u.scheme not in ('ws', 'wss'):
            raise WsError('not a ws:// or wss:// address')
        port = u.port or (443 if u.scheme == 'wss' else 80)
        raw = socket.create_connection((u.hostname, port), timeout=timeout)
        self.sock = ssl.create_default_context().wrap_socket(raw, server_hostname=u.hostname) if u.scheme == 'wss' else raw
        self.sock.settimeout(timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        path = (u.path or '/') + (f'?{u.query}' if u.query else '')
        extra = ''.join(f'{k}: {v}\r\n' for k, v in (headers or {}).items())
        self.sock.sendall((f'GET {path} HTTP/1.1\r\nHost: {u.netloc}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                           f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n{extra}\r\n').encode())
        head = b''
        while b'\r\n\r\n' not in head:
            part = self.sock.recv(4096)
            if not part:
                raise WsError('the relay closed the connection during the handshake')
            head += part
            if len(head) > 16384:
                raise WsError('bad handshake')
        head, self.buf = head.split(b'\r\n\r\n', 1)
        status = head.split(b'\r\n', 1)[0]
        if b' 101 ' not in status + b' ':
            raise WsError('the relay refused: ' + status.decode(errors='replace'))
        self.send_lock = threading.Lock()
        self.closed = False

    def settimeout(self, t):
        self.sock.settimeout(t)

    def _send(self, op, data):
        mask = os.urandom(4)
        n = len(data)
        head = bytes([0x80 | op]) + (bytes([0x80 | n]) if n < 126 else bytes([0x80 | 126]) + struct.pack('!H', n)
                                     if n < 65536 else bytes([0x80 | 127]) + struct.pack('!Q', n))
        body = bytes(b ^ mask[i % 4] for i, b in enumerate(data)) if n < 4096 else _xor(data, mask)
        with self.send_lock:
            if self.closed:
                raise WsError('closed')
            self.sock.sendall(head + mask + body)

    def send_text(self, s):
        self._send(TEXT, s.encode())

    def send_binary(self, b):
        self._send(BINARY, bytes(b))

    def _read(self, n):
        while len(self.buf) < n:
            part = self.sock.recv(max(65536, n - len(self.buf)))
            if not part:
                raise WsError('the relay closed the connection')
            self.buf += part
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def recv(self):
        """-> (TEXT | BINARY, payload). Answers pings; raises WsError when closed. Fragments are joined."""
        parts, op0 = [], None
        while True:
            b0, b1 = self._read(2)
            op, n = b0 & 0x0F, b1 & 0x7F
            if n == 126:
                n = struct.unpack('!H', self._read(2))[0]
            elif n == 127:
                n = struct.unpack('!Q', self._read(8))[0]
            mask = self._read(4) if b1 & 0x80 else None
            data = self._read(n)
            if mask:
                data = _xor(data, mask)
            if op == PING:
                self._send(PONG, data)
                continue
            if op == PONG:
                continue
            if op == CLOSE:
                self.closed = True
                raise WsError('the relay closed the connection')
            if op != 0:
                op0 = op
            parts.append(data)
            if b0 & 0x80:
                return op0, b''.join(parts)

    def ping(self):
        self._send(PING, b'')

    def close(self):
        try:
            self._send(CLOSE, struct.pack('!H', 1000))
        except OSError:
            pass
        self.closed = True
        try:
            self.sock.close()
        except OSError:
            pass


def _xor(data, mask):
    n = len(data)
    m = (mask * (n // 4 + 1))[:n]
    return (int.from_bytes(data, 'big') ^ int.from_bytes(m, 'big')).to_bytes(n, 'big') if n else b''


class PipeSocket:
    """A relay pipe (§18) as a socket: the sync's framed Noise bytes go out as binary messages."""

    def __init__(self, ws):
        self.ws, self.pending = ws, b''

    def settimeout(self, t):
        self.ws.settimeout(t)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def sendall(self, data):
        self.ws.send_binary(data)

    def recv(self, n):
        while not self.pending:
            try:
                op, data = self.ws.recv()
            except WsError:
                return b''
            except socket.timeout:
                raise
            if op == BINARY:
                self.pending = data
        out, self.pending = self.pending[:n], self.pending[n:]
        return out

    def close(self):
        self.ws.close()
