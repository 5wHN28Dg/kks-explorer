"""Walkdown Plant's multiplayer relay (docs/plant3d/MULTIPLAYER.md §9.1, relay-plant/): admission, forwarding, the
limits, room expiry and abusive clients, against the Python twin (relay-plant/twin.py) and, with
KKS_PLANT_RELAY_WORKERD=1, the same tests against the real Worker in workerd (`wrangler dev`, the pinned wrangler in
relay-plant/node_modules: `cd relay-plant && npm ci --ignore-scripts` first).
  .venv/bin/python -m unittest tests.test_plant_relay
  KKS_PLANT_RELAY_WORKERD=1 .venv/bin/python -m unittest tests.test_plant_relay"""
import json, os, re, signal, socket, subprocess, sys, tempfile, threading, time, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..'))
RELAY = os.path.join(REPO, 'relay-plant')
sys.path.insert(0, RELAY)
sys.path.insert(0, HERE)
import twin  # noqa: E402
from twin import Client, unframe  # noqa: E402
import e2e_server  # noqa: E402

# the timings the tests run with (the limits themselves are the spec's); one set per server
MAIN = {'idle': 3000, 'empty': 3000, 'hello': 2000, 'joins': 1000}
SHORT = {'maxAge': 4000}
CAPS = {'daily': 3, 'joins': 5}
QUIET = {'idle': 3000, 'quiet': 1500}
WORKERD = os.environ.get('KKS_PLANT_RELAY_WORKERD') == '1'


class Twin:
    def __init__(self, limits):
        self.relay = twin.Relay(limits, trust_ip_header=True)
        self.url = f'ws://127.0.0.1:{self.relay.serve()}'

    def stop(self):
        self.relay.stop()


class Workerd:
    """`wrangler dev` on a free port, with the test timings in RELAY_LIMITS."""
    def __init__(self, limits):
        wrangler = os.path.join(RELAY, 'node_modules', '.bin', 'wrangler')
        if not os.path.exists(wrangler):
            raise unittest.SkipTest('no relay-plant/node_modules: cd relay-plant && npm ci --ignore-scripts')
        self.dir = tempfile.mkdtemp(prefix='plant-relay-')
        for attempt in range(5):
            port = e2e_server.free_port()
            self.log = open(os.path.join(self.dir, 'wrangler.log'), 'w+')
            # its own state folder, so no room of an earlier run is still there
            self.proc = subprocess.Popen(
                [wrangler, 'dev', '--port', str(port), '--ip', '127.0.0.1', '--persist-to', os.path.join(self.dir, 'state'),
                 '--var', 'RELAY_LIMITS:' + json.dumps(limits, separators=(',', ':')), '--log-level', 'warn'],
                cwd=RELAY, stdout=self.log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                env=dict(os.environ, WRANGLER_SEND_METRICS='false', CI='1'), start_new_session=True)
            t0 = time.time()
            while time.time() - t0 < 60 and self.proc.poll() is None:
                try:
                    with socket.create_connection(('127.0.0.1', port), timeout=1) as s:
                        s.sendall(b'GET / HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n')
                        if s.recv(64).startswith(b'HTTP/1.1 404'):
                            self.url = f'ws://127.0.0.1:{port}'
                            return
                except OSError:
                    pass
                time.sleep(0.2)
            self.stop()
        self.log.seek(0)
        raise RuntimeError('wrangler dev did not start:\n' + self.log.read()[-3000:])

    def stop(self):
        try:
            os.killpg(self.proc.pid, signal.SIGTERM)
            self.proc.wait(10)
        except (OSError, subprocess.TimeoutExpired):
            try:
                os.killpg(self.proc.pid, signal.SIGKILL)
            except OSError:
                pass
            self.proc.wait()
        self.log.close()


def rnd_room():
    return os.urandom(16).hex()


def rnd_ip():
    return '10.%d.%d.%d' % tuple(os.urandom(3))


class Base:
    SERVER = None   # Twin or Workerd
    LIMITS = MAIN

    @classmethod
    def setUpClass(cls):
        cls.server = cls.SERVER(cls.LIMITS)

    @classmethod
    def tearDownClass(cls):
        cls.server.stop()

    def setUp(self):
        self.open = []

    def tearDown(self):
        for c in self.open:
            c.close()

    def client(self, room, ip=None, **kw):
        c = Client(self.server.url, room, headers={'CF-Connecting-IP': ip or rnd_ip()}, **kw)
        self.open.append(c)
        return c

    def session(self, n=1):
        """A new room with n members: -> (room, admit, [clients]); the first is the host (relay ID 1)."""
        room, admit = rnd_room(), os.urandom(32)
        out = []
        for i in range(n):
            c = self.client(room)
            w = c.hello(admit, i == 0)
            self.assertEqual(w['t'], 'welcome', w)
            for o in out:
                self.assertEqual(o.json(), {'t': 'joined', 'id': w['id']})
            out.append(c)
        return room, admit, out

    def refused(self, c, why, timeout=5):
        self.assertEqual(c.json(timeout), {'t': 'error', 'why': why})
        self.assertClosed(c)

    def assertClosed(self, c, timeout=5):
        t0 = time.time()
        while True:
            try:
                c.recv(max(0.1, timeout - (time.time() - t0)))
            except (ConnectionResetError, OSError) as e:
                if isinstance(e, TimeoutError):
                    self.fail('not closed')
                return
            if time.time() - t0 > timeout:
                self.fail('not closed')

    def nothing(self, c, wait=0.5):
        """Nothing binary arrives within `wait` s (text such as `slow` is allowed)."""
        t0 = time.time()
        while True:
            left = wait - (time.time() - t0)
            if left <= 0:
                return
            try:
                op, data = c.recv(left)
            except TimeoutError:
                return
            self.assertNotEqual(op, 2, f'unexpected binary message {data[:40]!r}')

    def ping_for(self, cs, secs):
        """Every client in cs sends the text ping every 0.3 s for secs seconds; -> (client, its first other message),
        or None."""
        t0 = time.time()
        while time.time() - t0 < secs:
            for c in cs:
                c.text(b'{"t":"ping"}')
            for c in cs:
                while True:
                    try:
                        m = c.json(0.3)
                    except TimeoutError:
                        break
                    if m != {'t': 'pong'}:
                        return c, m
        return None


class Behaviour(Base):
    # ---------- admission ----------
    def test_create_and_join(self):
        room, admit = rnd_room(), os.urandom(32)
        h = self.client(room)
        self.assertEqual(h.hello(admit, True), {'t': 'welcome', 'id': 1, 'peers': [], 'host': 1})
        j = self.client(room)
        self.assertEqual(j.hello(admit, False), {'t': 'welcome', 'id': 2, 'peers': [1], 'host': 1})
        self.assertEqual(h.json(), {'t': 'joined', 'id': 2})
        k = self.client(room)
        w = k.hello(admit, False)
        self.assertEqual((w['id'], sorted(w['peers']), w['host']), (3, [1, 2], 1))

    def test_create_twice(self):
        room, admit, _ = self.session(1)
        self.refused(self._hello(room, os.urandom(32), True), 'exists')
        self.refused(self._hello(room, admit, True), 'exists')

    def _hello(self, room, admit, create, ip=None):
        c = self.client(room, ip)
        c.text({'t': 'hello', 'admit': twin.base64.urlsafe_b64encode(admit).decode().rstrip('='), 'create': create})
        return c

    def test_messages_right_after_the_hello(self):
        # a client that sends before its welcome arrived (a packet, a host claim) keeps its place: what it sent
        # before it was admitted is dropped, never taken for a second hello
        room, admit = rnd_room(), os.urandom(32)
        h = self.client(room)
        a = twin.base64.urlsafe_b64encode(admit).decode().rstrip('=')
        h.text({'t': 'hello', 'admit': a, 'create': True})
        h.packets(0, b'early')
        h.text({'t': 'host'})
        self.assertEqual(h.json(), {'t': 'welcome', 'id': 1, 'peers': [], 'host': 1})
        j = self.client(room)
        j.text({'t': 'hello', 'admit': a, 'create': False})
        j.packets(1, b'early too')
        self.assertEqual(j.json(), {'t': 'welcome', 'id': 2, 'peers': [1], 'host': 1})
        self.assertEqual(h.json(), {'t': 'joined', 'id': 2})
        j.packets(1, b'later')
        while True:
            who, ps = unframe(h.binary())
            if ps == [b'later']:
                self.assertEqual(who, 2)
                break

    def test_no_such_session(self):
        self.refused(self._hello(rnd_room(), os.urandom(32), False), 'no such session')

    def test_bad_admit(self):
        room, admit, (h,) = self.session(1)
        wrong = bytearray(admit)
        wrong[31] ^= 1
        self.refused(self._hello(room, bytes(wrong), False), 'bad admit')
        self.nothing(h, 0.3)   # the members hear nothing of it

    def test_bad_hellos(self):
        room, admit, _ = self.session(1)
        a = twin.base64.urlsafe_b64encode(admit).decode().rstrip('=')
        for bad in [b'not json', b'[]', b'{"t":"hello"}', json.dumps({'t': 'hello', 'admit': a}).encode(),
                    json.dumps({'t': 'hello', 'admit': a, 'create': 0}).encode(),
                    json.dumps({'t': 'hello', 'admit': a, 'create': False, 'x': 1}).encode(),
                    json.dumps({'t': 'hello', 'admit': a[:-1], 'create': False}).encode(),
                    json.dumps({'t': 'hello', 'admit': a + 'A', 'create': False}).encode(),
                    json.dumps({'t': 'hello', 'admit': a, 'create': False, 'pad': 'x' * 600}).encode(),
                    json.dumps({'t': 'join', 'admit': a, 'create': False}).encode()]:
            c = self.client(room)
            c.text(bad)
            self.refused(c, 'bad hello')
        c = self.client(room)
        c.send(b'\0\0\0\1x')   # binary before the hello
        self.refused(c, 'bad hello')

    def test_admit_is_the_hash_only(self):
        # another room's admit doesn't open this one, nor does the right admit open another room
        _, admit1, _ = self.session(1)
        room2, _, _ = self.session(1)
        self.refused(self._hello(room2, admit1, False), 'bad admit')

    def test_full_and_ids_never_reused(self):
        room, admit, cs = self.session(12)
        self.refused(self._hello(room, admit, False), 'full')
        cs[5].close()
        self.open.remove(cs[5])
        self.assertEqual(cs[0].json(), {'t': 'left', 'id': 6})
        c = self.client(room)
        w = c.hello(admit, False)
        self.assertEqual(w['id'], 13)
        self.assertNotIn(6, w['peers'])
        self.assertEqual(len(w['peers']), 11)

    def test_ids_past_255(self):
        room, admit, (h,) = self.session(1)
        last = None
        for i in range(2, 300):
            c = Client(self.server.url, room, headers={'CF-Connecting-IP': rnd_ip()})
            w = c.hello(admit, False)
            self.assertEqual(w.get('id'), i, w)
            self.assertEqual(h.json(), {'t': 'joined', 'id': i})
            if i < 299:
                h.packets(0, b'keep')   # binary traffic: else the room is idle (3 s here) before 300 joins
                c.close()
                self.assertEqual(h.json(), {'t': 'left', 'id': i})
            else:
                last = c
                self.open.append(c)
        # forwarding to and from an ID above 255
        last.packets(1, b'from 299')
        self.assertEqual(unframe(h.binary()), (299, [b'from 299']))
        h.packets(299, b'to 299')
        self.assertEqual(unframe(last.binary()), (1, [b'to 299']))

    def test_create_race(self):
        room, admit = rnd_room(), os.urandom(32)
        cs = [self.client(room) for _ in range(4)]
        out = [None] * 4

        def go(i):
            out[i] = cs[i].hello(admit, True)
        ts = [threading.Thread(target=go, args=(i,)) for i in range(4)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        self.assertEqual(sorted(m['t'] for m in out), ['error', 'error', 'error', 'welcome'], out)
        self.assertTrue(all(m == {'t': 'error', 'why': 'exists'} for m in out if m['t'] == 'error'))
        self.assertEqual([m for m in out if m['t'] == 'welcome'][0]['id'], 1)

    def test_last_place_race(self):
        room, admit, cs = self.session(10)
        js = [self.client(room) for _ in range(3)]
        out = [None] * 3

        def go(i):
            out[i] = js[i].hello(admit, False)
        ts = [threading.Thread(target=go, args=(i,)) for i in range(3)]
        for t in ts:
            t.start()
        for t in ts:
            t.join()
        self.assertEqual(sorted(m['t'] for m in out), ['error', 'welcome', 'welcome'], out)
        self.assertIn({'t': 'error', 'why': 'full'}, out)

    def test_failed_hellos_per_room(self):
        room, admit, _ = self.session(1)
        for i in range(30):
            self.refused(self._hello(room, os.urandom(32), False), 'bad admit')
        # the 31st in the minute is refused unread, even with the right admit
        self.refused(self._hello(room, admit, False), 'limit')
        # a room that doesn't exist (yet) can be asked any number of times: players retry a new room after a
        # removal (§2.4), and its host can still create it
        room3, admit3 = rnd_room(), os.urandom(32)
        for i in range(35):
            self.refused(self._hello(room3, admit3, False), 'no such session')
        self.assertEqual(self.client(room3).hello(admit3, True)['id'], 1)
        # another room is not affected
        room2, admit2, _ = self.session(1)
        self.assertEqual(self.client(room2).hello(admit2, False)['t'], 'welcome')

    def test_ip_creates(self):
        ip = rnd_ip()
        for i in range(10):
            self.assertEqual(self._hello(rnd_room(), os.urandom(32), True, ip).json()['t'], 'welcome')
        self.refused(self._hello(rnd_room(), os.urandom(32), True, ip), 'limit')
        self.assertEqual(self._hello(rnd_room(), os.urandom(32), True).json()['t'], 'welcome')
        # an IPv6 client counts by its /64
        prefix = '2001:db8:%x:%x' % tuple(os.urandom(2))
        for i in range(10):
            self.assertEqual(self._hello(rnd_room(), os.urandom(32), True, f'{prefix}::{i + 1:x}').json()['t'], 'welcome')
        self.refused(self._hello(rnd_room(), os.urandom(32), True, f'{prefix}::beef'), 'limit')
        # also when `::` stands for zeros of the prefix itself (2001:db8:x:0::/64 written 2001:db8:x::1)
        prefix = '2001:db8:%x' % (int.from_bytes(os.urandom(2), 'big') | 1)
        for i in range(10):
            self.assertEqual(self._hello(rnd_room(), os.urandom(32), True, f'{prefix}::{i + 1:x}').json()['t'], 'welcome')
        self.refused(self._hello(rnd_room(), os.urandom(32), True, f'{prefix}:0:1:2:3:4'), 'limit')

    def test_hello_timeout(self):
        room, admit, _ = self.session(1)
        c = self.client(room)
        time.sleep(MAIN['hello'] / 1000 + 0.5)
        self.client(room)   # the next connection closes a socket that stayed silent (there is no timer per socket)
        self.refused(c, 'no hello', timeout=4)

    def test_waiting_sockets_capped(self):
        room = rnd_room()
        for _ in range(12):
            self.client(room)
        time.sleep(0.3)
        with self.assertRaises(ConnectionRefusedError) as e:
            self.client(room)
        self.assertEqual(e.exception.args[0], 429)

    def test_not_a_room(self):
        for path in [b'/', b'/v1/room/ABC', b'/v1/room/' + b'0' * 31, b'/v1/room/' + b'0' * 32 + b'/x']:
            self.assertEqual(self.http(b'GET ' + path + b' HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n'), 404, path)
        self.assertEqual(self.http(b'GET /v1/room/' + b'0' * 32 + b' HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n'), 426)

    def http(self, req):
        host, port = self.server.url[5:].split(':')
        with socket.create_connection((host, int(port)), timeout=10) as s:
            s.sendall(req)
            return int(s.recv(64).split(b' ')[1])

    # ---------- forwarding ----------
    def test_broadcast_and_direct(self):
        _, _, (a, b, c) = self.session(3)
        b.packets(0, b'p1', b'second packet')
        for r in (a, c):
            self.assertEqual(unframe(r.binary()), (2, [b'p1', b'second packet']))
        self.nothing(b, 0.3)
        a.packets(3, b'only c')
        self.assertEqual(unframe(c.binary()), (1, [b'only c']))
        self.nothing(b, 0.3)
        # to itself or to nobody: dropped
        a.packets(1, b'self')
        a.packets(77, b'nobody')
        self.nothing(b, 0.3)
        self.nothing(c, 0.1)

    def test_packets_pass_unread(self):
        _, _, (a, b) = self.session(2)
        p = os.urandom(65000)
        a.packets(2, p)
        self.assertEqual(unframe(b.binary()), (1, [p]))
        many = [os.urandom(n) for n in (1, 14, 300, 1200)]
        b.packets(0, *many)
        self.assertEqual(unframe(a.binary()), (2, many))

    def test_bad_framing_dropped(self):
        _, _, (a, b) = self.session(2)
        for bad in [b'', b'\0', b'\0\x02', b'\0\x02\0\0', b'\0\x02\0\x00x', b'\0\x02\0\x05abc', b'\0\x02\0\x01ab',
                    b'\0\x02\0\x01a\0']:
            a.send(bad)
        a.text(b'not json')
        a.packets(2, b'good')
        self.assertEqual(unframe(b.binary()), (1, [b'good']))
        self.nothing(b, 0.3)

    def test_message_size(self):
        _, _, (a, b) = self.session(2)
        ok = b'\0\x02' + b'\xff\xfc' + os.urandom(65532)
        self.assertEqual(len(ok), 65536)
        a.send(ok + b'x')   # 65,537 bytes: dropped
        self.assertEqual(a.json(), {'t': 'slow'})
        a.send(ok)
        self.assertEqual(b.binary(), b'\0\x01' + ok[2:])

    def test_host_claim_and_leaving(self):
        room, admit, (h, a, b) = self.session(3)
        b.text({'t': 'host'})
        for c in (h, a, b):
            self.assertEqual(c.json(), {'t': 'host', 'id': 3})
        c = self.client(room)
        self.assertEqual(c.hello(admit, False)['host'], 3)
        for x in (h, a, b):
            x.json()   # joined
        b.close()
        self.open.remove(b)
        for x in (h, a, c):
            self.assertEqual(x.json(), {'t': 'left', 'id': 3})
        d = self.client(room)
        self.assertIsNone(d.hello(admit, False)['host'])

    def test_ping(self):
        room, admit = rnd_room(), os.urandom(32)
        c = self.client(room)
        c.text(b'{"t":"ping"}')
        self.assertEqual(c.json(), {'t': 'pong'})
        self.assertEqual(c.hello(admit, True)['t'], 'welcome')
        c.text(b'{"t":"ping"}')
        self.assertEqual(c.json(), {'t': 'pong'})

    # ---------- limits ----------
    def test_slowed_not_cut(self):
        _, _, (a, b) = self.session(2)
        for i in range(300):
            b.packets(1, i.to_bytes(2, 'big'))
        got = self.count(a, 1.5)
        self.assertLess(got, 300)
        self.assertGreaterEqual(got, 200)
        self.assertEqual(b.json(), {'t': 'slow'})
        # still a member: once the bucket has refilled, messages pass again
        time.sleep(1.5)
        b.packets(1, b'again')
        while True:
            m = a.binary()
            if unframe(m)[1] == [b'again']:
                break

    def count(self, c, wait):
        n, t0 = 0, time.time()
        while True:
            left = wait - (time.time() - t0)
            if left <= 0:
                return n
            try:
                op, _ = c.recv(left)
            except TimeoutError:
                return n
            n += op == 2

    def test_flood_is_cut(self):
        _, _, (h, a, b) = self.session(3)
        msg = b'\0\x01\0\x01x'
        for i in range(1900):   # more than 3 x 60 a second over 10 s, at once
            try:
                b.send(msg)
            except OSError:
                break
        t0 = time.time()
        while True:
            m = b.json(10)   # (a close before the `limit` error fails here)
            if m == {'t': 'error', 'why': 'limit'}:
                self.assertClosed(b)
                break
            self.assertEqual(m, {'t': 'slow'})
            self.assertLess(time.time() - t0, 10)
        # everyone else hears that it left
        self.assertEqual(a.json(), {'t': 'left', 'id': 3})

    def test_busy_host_slowed_not_cut(self):
        _, _, (h, a) = self.session(2)
        for i in range(1900):   # the host's limits are twice a player's: slowed, but still in
            h.send(b'\0\x02\0\x01x')
        self.assertEqual(h.json(), {'t': 'slow'})
        time.sleep(0.5)
        h.text(b'{"t":"ping"}')
        while h.json() != {'t': 'pong'}:
            pass

    def test_bytes_per_second(self):
        _, _, (a, b) = self.session(2)
        big = b'\0\x01\xff\xfc' + os.urandom(65532)
        for i in range(24):   # 1.5 MiB at once: the bucket holds 1 MiB
            b.send(big)
        got = self.count(a, 2)
        self.assertLess(got, 24)
        self.assertGreaterEqual(got, 15)

    def test_long_text_ignored(self):
        _, _, (a, b) = self.session(2)
        b.text(json.dumps({'t': 'host', 'pad': 'x' * 600}).encode())
        b.text(b'{"t":"ping"}')
        self.assertEqual(b.json(), {'t': 'pong'})   # no host notice before it
        self.nothing(a, 0.3)

    # ---------- room expiry ----------
    def test_idle_room_closed_and_deleted(self):
        room, admit, (a, b) = self.session(2)
        t0 = time.time()
        # traffic keeps it open past the idle time
        while time.time() - t0 < MAIN['idle'] / 1000 + 1:
            a.packets(2, b'x')
            self.assertEqual(unframe(b.binary()), (1, [b'x']))
            time.sleep(0.3)
        # then nothing at all from anyone: closed, and the room is gone
        self.assertEqual(a.json(MAIN['idle'] / 1000 + 6), {'t': 'error', 'why': 'idle'})
        self.assertEqual(b.json(5), {'t': 'error', 'why': 'idle'})
        self.refused(self._hello(room, admit, False), 'no such session')
        # and the code's room can be made again
        self.assertEqual(self.client(room).hello(admit, True)['id'], 1)

    def test_paused_room_kept_open_by_pings(self):
        # a paused session sends no binary message, only the text ping (answered without waking the Worker's room):
        # that keeps the room open past the idle time (MULTIPLAYER.md §9.1)
        room, admit, (a, b) = self.session(2)
        self.assertIsNone(self.ping_for([a, b], MAIN['idle'] / 1000 * 2 + 2))
        c = self.client(room)
        self.assertEqual(c.hello(admit, False)['id'], 3)

    def test_empty_room_deleted(self):
        room, admit, (a,) = self.session(1)
        a.close()
        self.open.remove(a)
        time.sleep(0.5)
        b = self.client(room)   # back within the time: still there
        self.assertEqual(b.hello(admit, False)['id'], 2)
        b.close()
        self.open.remove(b)
        time.sleep(MAIN['empty'] / 1000 + 2)
        self.refused(self._hello(room, admit, False), 'no such session')


class Short(Base):
    LIMITS = SHORT

    def test_room_expires(self):
        room, admit, (a, b) = self.session(2)
        t0 = time.time()
        while True:   # busy all the time, and still closed at its maximum age
            a.packets(2, b'x')
            op, data = b.recv(10)
            if op == 1:
                self.assertEqual(json.loads(data), {'t': 'error', 'why': 'expired'})
                break
            self.assertLess(time.time() - t0, SHORT['maxAge'] / 1000 + 5)
            time.sleep(0.1)
        self.assertGreaterEqual(time.time() - t0, SHORT['maxAge'] / 1000 - 1)
        c = self.client(room)
        c.text({'t': 'hello', 'admit': twin.base64.urlsafe_b64encode(admit).decode().rstrip('='), 'create': False})
        self.refused(c, 'no such session')


class Caps(Base):
    LIMITS = CAPS

    def test_rooms_a_day_and_joins_a_minute(self):
        room, admit, cs = self.session(3)
        for _ in range(2):
            self.client(rnd_room()).hello(os.urandom(32), True)
        c = self.client(rnd_room())
        self.assertEqual(c.hello(os.urandom(32), True), {'t': 'error', 'why': 'limit'})   # the day's 4th room
        for _ in range(2):   # joins 4 and 5 of the minute
            self.assertEqual(self.client(room).hello(admit, False)['t'], 'welcome')
        self.assertEqual(self.client(room).hello(admit, False), {'t': 'error', 'why': 'limit'})


class Quiet(Base):
    LIMITS = QUIET

    def test_quiet_member_closed(self):
        # a member that sends nothing, not even a ping (a device gone without closing its socket), is closed while
        # the others ping on, and they hear it left (a paused host's loss, §5.3)
        room, admit, (a, b, c) = self.session(3)
        t0 = time.time()
        got = self.ping_for([a, c], QUIET['idle'] / 1000 + QUIET['quiet'] / 1000 + 4)
        self.assertIsNotNone(got, 'the silent member was not closed')
        self.assertEqual(got[1], {'t': 'left', 'id': 2})
        self.assertGreaterEqual(time.time() - t0, QUIET['quiet'] / 1000 - 0.5)
        self.refused(b, 'quiet')
        other = c if got[0] is a else a
        while True:
            m = other.json()
            if m != {'t': 'pong'}:
                break
        self.assertEqual(m, {'t': 'left', 'id': 2})
        self.assertIsNone(self.ping_for([a, c], 1))   # the room stays open for the others


class TwinRelay(Behaviour, unittest.TestCase):
    SERVER = Twin


class TwinShort(Short, unittest.TestCase):
    SERVER = Twin


class TwinCaps(Caps, unittest.TestCase):
    SERVER = Twin


class TwinQuiet(Quiet, unittest.TestCase):
    SERVER = Twin


@unittest.skipUnless(WORKERD, 'KKS_PLANT_RELAY_WORKERD=1 runs these against wrangler dev')
class WorkerdRelay(Behaviour, unittest.TestCase):
    SERVER = Workerd


@unittest.skipUnless(WORKERD, 'KKS_PLANT_RELAY_WORKERD=1 runs these against wrangler dev')
class WorkerdShort(Short, unittest.TestCase):
    SERVER = Workerd


@unittest.skipUnless(WORKERD, 'KKS_PLANT_RELAY_WORKERD=1 runs these against wrangler dev')
class WorkerdCaps(Caps, unittest.TestCase):
    SERVER = Workerd


@unittest.skipUnless(WORKERD, 'KKS_PLANT_RELAY_WORKERD=1 runs these against wrangler dev')
class WorkerdQuiet(Quiet, unittest.TestCase):
    SERVER = Workerd


class Deploy(unittest.TestCase):
    """relay-plant/deploy.py deploys only on the Workers Free plan, and fails closed."""
    def setUp(self):
        import importlib
        self.d = importlib.import_module('deploy')

    def test_plans(self):
        self.assertEqual(self.d.paid_plans([]), [])
        self.assertEqual(self.d.paid_plans([{'rate_plan': {'id': 'free'}, 'price': 0}]), [])
        self.assertEqual(self.d.paid_plans([{'rate_plan': {'id': 'workers_free'}, 'price': 0.0}]), [])
        for paid in [{'rate_plan': {'id': 'workers_paid'}, 'scope': 'account', 'price': 5},
                     {'rate_plan': {'id': 'workers_paid'}, 'price': 0},
                     {'rate_plan': {'id': 'pro'}, 'price': 25},
                     {'rate_plan': {'id': 'something_new'}},          # no price: not understood
                     {'rate_plan': {'id': 'x'}, 'price': '0'}, {'rate_plan': {'id': 'enterprise'}, 'price': 0}, 'junk']:
            self.assertEqual(len(self.d.paid_plans([paid])), 1, paid)

    def check(self, answer):
        from unittest import mock
        import io

        def urlopen(req, timeout):
            if isinstance(answer, Exception):
                raise answer
            return io.BytesIO(json.dumps(answer).encode())
        with mock.patch.object(self.d.urllib.request, 'urlopen', urlopen):
            self.d.check_free('0' * 32, 'token')

    def test_fails_closed(self):
        for answer in [OSError('no network'), {'success': False, 'errors': [{'code': 10000}], 'result': None},
                       {'success': True, 'result': None}, {'success': True, 'result': [{'rate_plan': {'id': 'workers_paid'}, 'price': 5}]},
                       {'success': True, 'result': [{'rate_plan': {'id': 'unknown'}}]}]:
            with self.assertRaises(SystemExit, msg=answer):
                self.check(answer)
        self.check({'success': True, 'result': [{'rate_plan': {'id': 'free'}, 'price': 0}]})
        # an empty list shows no plan at all: not evidence of the free plan, so nothing is deployed
        with self.assertRaises(SystemExit):
            self.check({'success': True, 'result': []})

    def test_config_has_no_vars(self):
        self.d.config_ok()

    def test_url_file_outside_the_repo(self):
        out = subprocess.run([sys.executable, os.path.join(RELAY, 'deploy.py'), '--smoke', '--url-file',
                              os.path.join(REPO, 'relay-plant', 'url.txt')], capture_output=True, text=True)
        self.assertEqual(out.returncode, 1)
        self.assertIn('outside the repository', out.stderr)


class NoUrl(unittest.TestCase):
    """The deployed relay's address is never in the repository: only the placeholder form in the docs."""
    def test_no_workers_dev_address(self):
        out = subprocess.run(['git', 'grep', '-niIE', r'[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev', '--', '.'],
                             cwd=REPO, capture_output=True, text=True).stdout
        # (the placeholder `example`, as in `wss://kks-relay.example.workers.dev`, is not an address)
        bad = [l for l in out.splitlines()
               if any(sub != 'example' for sub in re.findall(r'[a-z0-9-]+\.([a-z0-9-]+)\.workers\.dev', l.lower()))]
        self.assertEqual(bad, [])


if __name__ == '__main__':
    unittest.main()
