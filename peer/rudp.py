"""A reliable byte stream over UDP, for syncing across the internet after NAT hole punching (M5, PROTOCOL.md §18).

Encryption and authentication are not done here: the sync runs its Noise handshake (§15) over this stream exactly as
over TCP. This layer only delivers bytes in order, once, and backs off when packets are lost. Twin of Rudp.kt.

Datagram = 1 byte type + 8 bytes session id + body (big-endian integers):
  PUNCH 1, PUNCH_ACK 2: empty body (hole punching: the first one seen fixes the other side's address)
  DATA 3:  seq u32, payload (≤ MSS bytes)
  ACK 4:   next u32 (every seq below it arrived), mask u32 (bit i: seq next+1+i arrived too)
  FIN 5:   seq u32 (no more data after it; acknowledged like DATA)
  PING 6:  empty (keeps the NAT mapping open while idle)
Sender: window starts at 8 packets, +1 per window acknowledged, halved on loss (min 2, max 256); retransmit after RTO
(RFC 6298 from measured round trips, 200 ms – 4 s, doubled on each timeout, capped at 4 s) or when 3 later packets
are acknowledged past a hole; a loss halves the window once per round of packets. A connection that makes no progress for `dead` seconds fails.
"""
import os, socket, struct, threading, time

PUNCH, PUNCH_ACK, DATA, ACK, FIN, PING = 1, 2, 3, 4, 5, 6
MSS = 1150                   # payload per datagram: 1 + 8 + 4 + 1150 < 1200, under any path MTU
HEAD = struct.Struct('!B8s')


class RudpError(OSError):
    pass


def punch(sock, session, candidates, timeout=4.0, interval=0.1):
    """Hole punching: send PUNCH to every candidate address until the other side is heard (and has heard us).
    sock: a bound UDP socket (the one the STUN request went out of). -> the other side's address, or None."""
    sock.settimeout(interval)
    end, peer, confirmed = time.monotonic() + timeout, None, False
    while time.monotonic() < end and not confirmed:
        for c in ([peer] if peer else candidates):
            try:
                sock.sendto(HEAD.pack(PUNCH, session), c)
            except OSError:
                pass
        t_next = time.monotonic() + interval
        while time.monotonic() < t_next:
            try:
                data, addr = sock.recvfrom(2048)
            except (socket.timeout, BlockingIOError):
                break
            except OSError:
                continue
            if len(data) < HEAD.size:
                continue
            typ, sid = HEAD.unpack_from(data)
            if sid != session:
                continue
            if typ == PUNCH:
                peer = peer or addr
                sock.sendto(HEAD.pack(PUNCH_ACK, session), addr)
            elif typ == PUNCH_ACK:
                peer, confirmed = peer or addr, True
            elif typ in (DATA, ACK, FIN, PING) and peer:   # the other side already started: it heard us
                confirmed = True
    if peer and not confirmed:   # we heard them; one more round so they hear our ack
        confirmed = True
    return peer if confirmed else None


class Stream:
    """A connected reliable stream over `sock` to `peer`. Socket-like: sendall, recv, settimeout, close."""

    def __init__(self, sock, peer, session, dead=15.0):
        self.sock, self.peer, self.session, self.dead = sock, peer, session, dead
        self.lock = threading.Condition()
        # sending
        self.next_seq, self.base = 0, 0          # next new seq; oldest unacknowledged
        self.unacked = {}                        # seq -> [payload, sent_at, retries, sacked]
        self.queue = bytearray()                 # bytes not yet packetized
        self.cwnd, self.ssthresh = 8.0, 256
        self.srtt, self.rttvar, self.rto = None, None, 0.5
        self.fin_seq = None
        self.recover = 0                         # losses below this seq belong to a window already halved for
        self.progress = time.monotonic()
        # receiving
        self.rnext, self.rbuf, self.inbox = 0, {}, bytearray()
        self.peer_fin = None
        self.error = None
        self.closed = False
        self.timeout = None
        self.last_rx = time.monotonic()
        self.last_tx = time.monotonic()
        sock.settimeout(0.05)
        self.reader = threading.Thread(target=self._loop, daemon=True)
        self.reader.start()

    # ---------- socket-like API (what peer/sync.py uses) ----------
    def settimeout(self, t):
        self.timeout = t

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()

    def sendall(self, data):
        with self.lock:
            if self.error:
                raise RudpError(self.error)
            if self.fin_seq is not None:
                raise RudpError('stream closed')
            self.queue += data
            self._pump()
            # back-pressure: don't let the queue grow without bound
            end = time.monotonic() + (self.timeout or 3600)
            while len(self.queue) > 4 * 1024 * 1024 and not self.error:
                if not self.lock.wait(max(0.0, end - time.monotonic())) and time.monotonic() >= end:
                    raise socket.timeout('send timed out')
            if self.error:
                raise RudpError(self.error)

    def recv(self, n):
        end = None if self.timeout is None else time.monotonic() + self.timeout
        with self.lock:
            while not self.inbox:
                if self.error:
                    raise RudpError(self.error)
                if self.peer_fin is not None and self.rnext > self.peer_fin:
                    return b''                                  # the other side closed: end of stream
                left = None if end is None else end - time.monotonic()
                if left is not None and left <= 0:
                    raise socket.timeout('timed out')
                self.lock.wait(0.2 if left is None else min(0.2, left))
            out = bytes(self.inbox[:n])
            del self.inbox[:n]
            return out

    def close(self):
        """Send FIN after everything queued, wait (briefly) until it is acknowledged, stop."""
        with self.lock:
            end = time.monotonic() + 30
            while self.queue and not self.error and time.monotonic() < end:   # FIN comes after the last byte
                self.lock.wait(0.1)
            if self.fin_seq is None and not self.error:
                self.fin_seq = self.next_seq
                self.unacked[self.fin_seq] = [b'', 0.0, 0, False]
                self.next_seq += 1
                self._send_data(self.fin_seq)
            end = time.monotonic() + 3
            while self.unacked and not self.error and time.monotonic() < end:
                self.lock.wait(0.1)
            self.closed = True
            self.lock.notify_all()
        try:
            self.sock.close()
        except OSError:
            pass

    # ---------- internals ----------
    def _raw(self, typ, body=b''):
        try:
            self.sock.sendto(HEAD.pack(typ, self.session) + body, self.peer)
            self.last_tx = time.monotonic()
        except OSError:
            pass

    def _send_data(self, seq):
        rec = self.unacked[seq]
        rec[1] = time.monotonic()
        if seq == self.fin_seq:
            self._raw(FIN, struct.pack('!I', seq))
        else:
            self._raw(DATA, struct.pack('!I', seq) + rec[0])

    def _pump(self):
        """Packetize queued bytes and send new packets while the window allows. Call with the lock held."""
        while self.queue and self.next_seq - self.base < int(self.cwnd):
            chunk = bytes(self.queue[:MSS])
            del self.queue[:MSS]
            self.unacked[self.next_seq] = [chunk, 0.0, 0, False]
            self._send_data(self.next_seq)
            self.next_seq += 1
        self.lock.notify_all()

    def _on_ack(self, nxt, mask):
        now = time.monotonic()
        newly = 0
        for seq in [s for s in self.unacked if s < nxt]:
            rec = self.unacked.pop(seq)
            newly += 1
            if rec[2] == 0 and rec[1]:   # Karn: measure only packets sent once
                self._sample(now - rec[1])
        for i in range(32):
            if mask >> i & 1:
                rec = self.unacked.get(nxt + 1 + i)
                if rec and not rec[3]:
                    rec[3] = True
                    if rec[2] == 0 and rec[1]:
                        self._sample(now - rec[1])
        if nxt > self.base:
            self.base = nxt
            self.progress = now
        if newly:
            self.cwnd = min(self.cwnd + (1.0 if self.cwnd < self.ssthresh else 1.0 / self.cwnd) * newly, 256.0)
        # holes with 3+ later packets acknowledged are lost: send them again now (fast retransmit), at most once a
        # round trip each
        later = 0
        for seq in sorted(self.unacked, reverse=True):
            rec = self.unacked[seq]
            if rec[3]:
                later += 1
            elif later >= 3 and rec[1] and now - rec[1] > (self.srtt or 0.1):
                self._lost(seq)
                rec[2] += 1
                self._send_data(seq)
        self._pump()
        self.lock.notify_all()

    def _lost(self, seq):
        """A loss: halve the window, once per round of packets (not again for losses from the same window)."""
        if seq >= self.recover:
            self.ssthresh = max(2, int(self.cwnd / 2))
            self.cwnd = float(self.ssthresh)
            self.recover = self.next_seq

    def _sample(self, r):
        if self.srtt is None:
            self.srtt, self.rttvar = r, r / 2
        else:
            self.rttvar = 0.75 * self.rttvar + 0.25 * abs(self.srtt - r)
            self.srtt = 0.875 * self.srtt + 0.125 * r
        self.rto = min(4.0, max(0.2, self.srtt + 4 * self.rttvar))

    def _on_data(self, seq, payload, fin=False):
        if fin:
            self.peer_fin = seq
        if seq >= self.rnext and seq not in self.rbuf:
            self.rbuf[seq] = payload
            while self.rnext in self.rbuf:
                self.inbox += self.rbuf.pop(self.rnext)
                self.rnext += 1
            self.lock.notify_all()
        mask = 0
        for i in range(32):
            if self.rnext + 1 + i in self.rbuf:
                mask |= 1 << i
        self._raw(ACK, struct.pack('!II', self.rnext, mask))

    def _timers(self):
        now = time.monotonic()
        for seq in sorted(self.unacked)[:int(self.cwnd) + 1]:
            rec = self.unacked[seq]
            if not rec[3] and rec[1] and now - rec[1] > min(4.0, self.rto * (2 ** min(rec[2], 4))):   # (backoff capped at 4 s)
                self._lost(seq)
                rec[2] += 1
                self._send_data(seq)
        if self.unacked and now - self.progress > self.dead:
            self.error = 'the other device stopped answering'
        if now - self.last_rx > self.dead and not self.closed:
            self.error = self.error or 'the other device stopped answering'
        if now - self.last_tx > 2.0 and not self.closed:
            self._raw(PING)
        self._pump()

    def _loop(self):
        while True:
            with self.lock:
                if self.closed or self.error:
                    self.lock.notify_all()
                    return
            try:
                data, addr = self.sock.recvfrom(2048)
            except (socket.timeout, BlockingIOError):
                data = None
            except OSError as e:
                with self.lock:
                    self.error = self.error or f'network: {e}'
                    self.lock.notify_all()
                return
            with self.lock:
                if data and len(data) >= HEAD.size and addr == self.peer:
                    typ, sid = HEAD.unpack_from(data)
                    if sid == self.session:
                        self.last_rx = time.monotonic()
                        body = data[HEAD.size:]
                        if typ == DATA and len(body) >= 4:
                            self._on_data(struct.unpack_from('!I', body)[0], body[4:])
                        elif typ == FIN and len(body) >= 4:
                            self._on_data(struct.unpack_from('!I', body)[0], b'', fin=True)
                        elif typ == ACK and len(body) >= 8:
                            self._on_ack(*struct.unpack_from('!II', body))
                        elif typ in (PUNCH, PUNCH_ACK):
                            self._raw(PUNCH_ACK)
                self._timers()


def new_session():
    return os.urandom(8)
