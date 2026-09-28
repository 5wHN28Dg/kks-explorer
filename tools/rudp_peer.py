"""Interop helper for the Kotlin tests (android/core RudpTest): the Python side of a hole-punched UDP stream.

    python3 tools/rudp_peer.py SESSION_HEX
prints its UDP port, reads the Kotlin side's address from stdin, punches, then: reads a 4-byte length + that many
bytes, answers with their SHA-256 + 300 000 bytes of seeded data (seed 7), and closes."""
import hashlib, os, random, socket, struct, sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peer import rudp

session = bytes.fromhex(sys.argv[1])
u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
u.bind(('127.0.0.1', 0))
print(u.getsockname()[1], flush=True)
host, _, port = sys.stdin.readline().strip().rpartition(':')
peer = rudp.punch(u, session, [(host, int(port))], timeout=8)
if not peer:
    print('punch failed', flush=True); sys.exit(1)
s = rudp.Stream(u, peer, session, dead=60)
s.settimeout(60)

def exact(n):
    out = bytearray()
    while len(out) < n:
        c = s.recv(n - len(out))
        if not c:
            raise SystemExit('eof')
        out += c
    return bytes(out)

data = exact(struct.unpack('!I', exact(4))[0])
s.sendall(hashlib.sha256(data).digest() + random.Random(7).randbytes(300_000))
s.close()
print('done', flush=True)
