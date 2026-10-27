"""A network simulator for the multi-instance harness (docs/plant3d/MULTIPLAYER.md §12 "Network simulation"): a UDP
proxy between a joiner and the host, one link per joiner, with latency, jitter, loss, duplication (reordering follows
from the jitter) and outages per direction, its random decisions from a seed.

    sim = NetSim(host_disc_port, host_sess_port)
    link = sim.link(seed=1, up=Impair(delay=0.15, jitter=0.05, loss=0.05), down=Impair(...))
    # the joiner: --addr=127.0.0.1:<link.disc_port> --via=127.0.0.1:<link.sess_port>
    sim.start(); ...; sim.stop()

Up is joiner -> host, down host -> joiner. An outage is (start, end) in seconds since sim.start().
"""
import heapq
import random
import selectors
import socket
import threading
import time
from dataclasses import dataclass, field


@dataclass
class Impair:
    delay: float = 0.0
    jitter: float = 0.0
    loss: float = 0.0
    dup: float = 0.0
    outages: list = field(default_factory=list)


def _udp():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(('127.0.0.1', 0))
    s.setblocking(False)
    return s


class Link:
    def __init__(self, sim, seed, up, down):
        self.sim, self.up, self.down = sim, up, down
        self.rng = random.Random(seed)
        self.disc_in, self.sess_in = _udp(), _udp()      # the joiner talks to these
        self.disc_up, self.sess_up = _udp(), _udp()      # the host sees these
        self.disc_port = self.disc_in.getsockname()[1]
        self.sess_port = self.sess_in.getsockname()[1]
        self.joiner = {}                                 # in socket -> the joiner's address
        self.counts = {'up': 0, 'down': 0, 'lost': 0, 'dup': 0}

    def _fate(self, imp, now):
        """The delays this packet arrives after ([] when it is lost)."""
        t = now - self.sim.t0
        if any(a <= t < b for a, b in imp.outages) or self.rng.random() < imp.loss:
            self.counts['lost'] += 1
            return []
        d = [max(0.0, imp.delay + self.rng.uniform(-imp.jitter, imp.jitter))]
        if self.rng.random() < imp.dup:
            self.counts['dup'] += 1
            d.append(max(0.0, imp.delay + self.rng.uniform(-imp.jitter, imp.jitter)))
        return d


class NetSim:
    def __init__(self, host_disc_port, host_sess_port, host_ip='127.0.0.1'):
        self.host_disc = (host_ip, host_disc_port)
        self.host_sess = (host_ip, host_sess_port)
        self.links = []
        self.sel = selectors.DefaultSelector()
        self.queue = []                                  # (time, n, socket, bytes, address)
        self.n = 0
        self.t0 = time.monotonic()
        self.stop_flag = False
        self.thread = None
        self.lock = threading.Lock()

    def link(self, seed=1, up=None, down=None):
        ln = Link(self, seed, up or Impair(), down or Impair())
        for s, kind in ((ln.disc_in, 'in'), (ln.sess_in, 'in'), (ln.disc_up, 'up'), (ln.sess_up, 'up')):
            self.sel.register(s, selectors.EVENT_READ, (ln, s, kind))
        self.links.append(ln)
        return ln

    def _send_later(self, delays, sock, data, addr):
        now = time.monotonic()
        for d in delays:
            self.n += 1
            heapq.heappush(self.queue, (now + d, self.n, sock, data, addr))

    def _loop(self):
        while not self.stop_flag:
            timeout = 0.002
            if self.queue:
                timeout = max(0.0, min(timeout, self.queue[0][0] - time.monotonic()))
            for key, _ in self.sel.select(timeout):
                ln, s, kind = key.data
                try:
                    data, addr = s.recvfrom(65536)
                except OSError:
                    continue
                now = time.monotonic()
                if kind == 'in':
                    ln.joiner[s] = addr
                    ln.counts['up'] += 1
                    up = ln.disc_up if s is ln.disc_in else ln.sess_up
                    dest = self.host_disc if s is ln.disc_in else self.host_sess
                    self._send_later(ln._fate(ln.up, now), up, data, dest)
                else:
                    ln.counts['down'] += 1
                    back = ln.disc_in if s is ln.disc_up else ln.sess_in
                    if back in ln.joiner:
                        self._send_later(ln._fate(ln.down, now), back, data, ln.joiner[back])
            now = time.monotonic()
            while self.queue and self.queue[0][0] <= now:
                _, _, sock, data, addr = heapq.heappop(self.queue)
                try:
                    sock.sendto(data, addr)
                except OSError:
                    pass

    def start(self):
        self.t0 = time.monotonic()
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def stop(self):
        self.stop_flag = True
        if self.thread:
            self.thread.join(5)
        for ln in self.links:
            for s in (ln.disc_in, ln.sess_in, ln.disc_up, ln.sess_up):
                s.close()
