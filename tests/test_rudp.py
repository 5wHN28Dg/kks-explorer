"""The reliable UDP stream (peer/rudp.py, PROTOCOL.md §18): hole punching on localhost, then bytes in order under
loss, duplication and reordering; a Noise sync session over it."""
import os, random, socket, sys, threading, time, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from peer import rudp


class Lossy:
    """Wraps a UDP socket: drops, duplicates and delays (so reorders) outgoing datagrams."""
    def __init__(self, sock, loss=0.1, dup=0.05, jitter=0.03, seed=1):
        self.s, self.loss, self.dup, self.jitter = sock, loss, dup, jitter
        self.rng = random.Random(seed)

    def sendto(self, data, addr):
        if self.rng.random() < self.loss:
            return len(data)
        for _ in range(2 if self.rng.random() < self.dup else 1):
            d = self.rng.random() * self.jitter
            threading.Timer(d, lambda: self._send(data, addr)).start() if d > 0.002 else self._send(data, addr)
        return len(data)

    def _send(self, data, addr):
        try:
            self.s.sendto(data, addr)
        except OSError:
            pass

    def __getattr__(self, k):
        return getattr(self.s, k)


def pair(loss=0.0, dup=0.0, jitter=0.0, dead=60.0):   # (a long stall limit: CI machines are busy)
    a, b = socket.socket(socket.AF_INET, socket.SOCK_DGRAM), socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    a.bind(('127.0.0.1', 0)); b.bind(('127.0.0.1', 0))
    sid = rudp.new_session()
    got = {}
    ta = threading.Thread(target=lambda: got.__setitem__('a', rudp.punch(a, sid, [b.getsockname()])))
    tb = threading.Thread(target=lambda: got.__setitem__('b', rudp.punch(b, sid, [a.getsockname()])))
    ta.start(); tb.start(); ta.join(); tb.join()
    assert got['a'] == b.getsockname() and got['b'] == a.getsockname(), got
    wa = Lossy(a, loss, dup, jitter, 1) if loss or dup or jitter else a
    wb = Lossy(b, loss, dup, jitter, 2) if loss or dup or jitter else b
    return rudp.Stream(wa, got['a'], sid, dead), rudp.Stream(wb, got['b'], sid, dead)


def read_exact(s, n):
    out = bytearray()
    while len(out) < n:
        chunk = s.recv(n - len(out))
        if not chunk:
            break
        out += chunk
    return bytes(out)


class RudpTest(unittest.TestCase):
    def transfer(self, loss, dup, jitter, size):
        x, y = pair(loss, dup, jitter)
        x.settimeout(60); y.settimeout(60)
        d1, d2 = os.urandom(size), os.urandom(size // 2)
        got = {}
        t = threading.Thread(target=lambda: got.__setitem__('y', read_exact(y, len(d1))))
        t.start()
        x.sendall(d1)
        y.sendall(d2)
        got['x'] = read_exact(x, len(d2))
        t.join(60)
        self.assertEqual(got['y'], d1)
        self.assertEqual(got['x'], d2)
        x.close()
        self.assertEqual(y.recv(10), b'')          # FIN: end of stream
        y.close()

    def test_clean(self):
        t0 = time.monotonic()
        self.transfer(0, 0, 0, 3_000_000)
        self.assertLess(time.monotonic() - t0, 20)

    def test_realistic_loss(self):   # ~2 % each way, some reordering: a poor mobile link
        t0 = time.monotonic()
        self.transfer(0.02, 0.01, 0.01, 2_000_000)
        print(f' [2 % loss: 3 MB in {time.monotonic() - t0:.1f} s]', end='')

    def test_loss_duplication_reordering(self):
        self.transfer(0.1, 0.05, 0.03, 200_000)

    def test_heavy_loss(self):   # 20 % each way: far worse than a bad mobile link
        self.transfer(0.2, 0.0, 0.01, 50_000)

    def test_wrong_session_is_ignored(self):
        a, b = socket.socket(socket.AF_INET, socket.SOCK_DGRAM), socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        a.bind(('127.0.0.1', 0)); b.bind(('127.0.0.1', 0))
        got = {}
        t = threading.Thread(target=lambda: got.__setitem__('a', rudp.punch(a, b'A' * 8, [b.getsockname()], timeout=1)))
        t.start()
        self.assertIsNone(rudp.punch(b, b'B' * 8, [a.getsockname()], timeout=1))
        t.join()
        self.assertIsNone(got['a'])

    def test_sync_session_over_it(self):
        """The Noise handshake (§15) runs over the stream as over TCP."""
        from peer import noise as N, sync as S
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        x, y = pair(0.05, 0.02, 0.01)
        ka, kb = Ed25519PrivateKey.generate(), Ed25519PrivateKey.generate()
        res = {}
        t = threading.Thread(target=lambda: res.__setitem__('b', S.handshake(y, kb, False)))
        t.start()
        sa = S.handshake(x, ka, True)
        t.join(10)
        sa.send({'t': 'hello', 'big': 'x' * 200_000})
        self.assertEqual(res['b'].recv()['big'], 'x' * 200_000)
        from peer import proto as P
        self.assertEqual(sa.remote, P.peer_id(kb))


if __name__ == '__main__':
    unittest.main()
