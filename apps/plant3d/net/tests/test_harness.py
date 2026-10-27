"""The multi-instance harness's runs (docs/plant3d/MULTIPLAYER.md §12, milestone MP2): headless players of the first
train on this machine's loopback, some through the network simulator; every player's state digests and event log
equal to each other and to one engine fed the host's commits.

    python3 -m unittest discover -s apps/plant3d/net/tests -v      (Godot from $GODOT or the pinned fetch)
Each case runs the model at SPEED times real time (the network's timers stay real), so 10 model minutes take 30 s.
Host migration and removal are MP3's; the relay is MP4's.
"""
import os
import random
import socket
import statistics
import struct
import sys
import time
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import Harness, CODE  # noqa: E402
from netsim import Impair  # noqa: E402

SPEED = 20
M = 60.0 / SPEED          # real seconds per model minute

OPS = [["op", "00QFA10AN001", "start", None, None], ["op", "00PGC10AP001", "start", None, None],
       ["op", "00PGB10AC001", "open", None, None], ["op", "30PAR10AA001", "auto", None, None],
       ["op", "00QFA10AN001", "stop", None, None], ["ack", "no_such_alarm"]]


def inputs(t0, t1, n, seed):
    rng = random.Random(seed)
    return [{"t": round(rng.uniform(t0, t1), 3), "do": "input", "item": rng.choice(OPS)} for _ in range(n)]


def ends(t_pause, quit_after=4.0, host=False):
    """The host pauses at t_pause (everyone then runs to the last commit), everyone quits after."""
    return ([{"t": t_pause, "do": "pause"}] if host else []) + [{"t": t_pause + quit_after, "do": "quit"}]


class Base(unittest.TestCase):
    scenario = 'cold_iron'

    def setUp(self):
        self.h = Harness(self.scenario, SPEED)

    def tearDown(self):
        self.h.close()

    def agree(self, res, replay=True, names=None, since=None):
        """Every player at the same last step with the same events and digests as the others (and one engine fed the
        host's commits)."""
        names = names or list(res)
        host = res['host']
        for n in names:
            r = res[n]
            self.assertIsNotNone(r, n)
            self.assertEqual(r['why_ended'], '', (n, r['why_ended']))
            self.assertEqual(r['step'], host['step'], n)
            self.assertEqual(r['digest'], host['digest'], n)
            self.assertEqual(r['events_sha'], host['events_sha'], n)
            for s, d in r['digests'].items():
                if s in host['digests'] and int(s) >= (since or {}).get(n, 0):
                    self.assertEqual(d, host['digests'][s], (n, s))
        for i in self.h.instances:
            self.assertEqual(i.script_errors(), [], i.name)
        if replay:
            rp = self.h.replay(host, host['step'])
            self.assertEqual(rp['digest'], host['digest'])
            self.assertEqual(rp['events_sha'], host['events_sha'])
            for s, d in rp['digests'].items():
                self.assertEqual(d, host['digests'].get(s, d), s)
        return host


class Players(Base):
    def run_players(self, n, minutes, link=None, ninth=False):
        t_end = 3 + minutes * M
        self.h.host([{"t": 2.5, "do": "start"}] + inputs(3, t_end, 20, 0) + ends(t_end, host=True))
        t0 = time.monotonic()
        for k in range(1, n):
            # (times on the host's clock: a player started later, on a busy machine, still makes its inputs before
            # the host's pause)
            off = time.monotonic() - t0
            self.h.join([dict(a, t=a['t'] - off) for a in inputs(4, t_end - 6, 20, k) + ends(t_end + 0.5)], f'p{k}',
                        link=link(k) if link else None)
        if ninth:
            time.sleep(8)
            self.h.join([{"t": 20, "do": "quit"}], 'ninth')      # a ninth player: the session is full (8 slots)
        res = self.h.wait_all(t_end + 120)
        if ninth:
            self.assertIn('full', res.pop('ninth')['why_ended'])
        host = self.agree(res)
        # every input reached its commit: none still sending
        for k in range(1, n):
            self.assertEqual(res[f'p{k}']['sending'], 0, f'p{k}')
            self.assertGreaterEqual(len(res[f'p{k}']['delays']), 15, f'p{k}')
        committed = sum(len(c[2]) for c in host['commits'])
        self.assertGreaterEqual(committed, 20 * n - 5)
        self.assertGreaterEqual(host['step'], minutes * 600 - 50)
        return res

    def test_two_players_ten_minutes(self):
        res = self.run_players(2, 10)
        self.assertIn(0, res['p1']['positions'])       # the host's position reached the player (§6.3)
        self.assertIn(1, res['host']['positions'])

    def test_three_players(self):
        res = self.run_players(3, 10)
        # a player's position forwarded by the host (§9.4)
        self.assertIn(res['p2']['slot'], res['p1']['positions'])
        self.assertIn(res['p1']['slot'], res['p2']['positions'])

    def test_eight_players(self):
        res = self.run_players(8, 10, ninth=True)
        pss = [r['pss_kb'] for r in res.values()]
        print(f'\n8 players: PSS per instance {min(pss) // 1024}-{max(pss) // 1024} MB')
        self.assertEqual(sorted(r['slot'] for r in res.values()), list(range(8)))


class Network(Base):
    def lossy(self, delay, jitter, loss):
        sim = self.h.netsim()
        links = [sim.link(k, Impair(delay / 2, jitter / 2, loss), Impair(delay / 2, jitter / 2, loss))
                 for k in range(1, 3)]
        sim.start()
        t_end = 3 + 5 * M
        self.h.host([{"t": 3.5, "do": "start"}] + inputs(4, t_end, 15, 0) + ends(t_end, quit_after=6, host=True))
        for k in range(1, 3):
            self.h.join(inputs(5, t_end, 15, k) + ends(t_end + 0.5, quit_after=6), f'p{k}', link=links[k - 1])
        res = self.h.wait_all(t_end + 120)
        self.agree(res)
        d = sorted(x for k in (1, 2) for x in res[f'p{k}']['delays'])
        med = statistics.median(d)
        p95 = d[int(len(d) * 0.95) - 1]
        print(f'\n{delay * 1000:.0f} ms ± {jitter * 1000:.0f}, {loss:.0%} loss: input to effect median {med:.3f} s, '
              f'p95 {p95:.3f} s ({len(d)} inputs; buffers {res["p1"]["buffer"]}, {res["p2"]["buffer"]} turns; '
              f'lost {sum(ln.counts["lost"] for ln in links)})')
        return med, p95

    def test_150ms_5pct(self):
        self.lossy(0.15, 0.05, 0.05)

    def test_400ms_15pct(self):
        self.lossy(0.40, 0.0, 0.15)


class Joins(Base):
    scenario = 'shift_cold'

    def test_late_join_and_rejoin_after_kill(self):
        t_end = 3 + 12 * M
        self.h.host([{"t": 2, "do": "claim", "person": "a_sup"}, {"t": 3, "do": "start"}]
                    + inputs(3, t_end, 10, 0) + ends(t_end, quit_after=6, host=True))
        t0 = time.monotonic()

        def since(t):           # a time on the host's clock, for an instance started now
            return t - (time.monotonic() - t0)
        p1 = self.h.join([{"t": 1.5, "do": "claim", "person": "a_ccr1"}] + inputs(4, t_end - 2, 10, 1)
                         + ends(since(t_end) + 0.5, quit_after=6), 'p1')
        # p2 joins at model minute 5
        time.sleep(3 + 5 * M)
        p2 = self.h.join(inputs(3, 10, 5, 2) + [{"t": 2, "do": "claim", "person": "a_fo_gt"}]
                         + ends(since(t_end) + 0.5, quit_after=6), 'p2')
        # p1 killed at minute 6, back 2 s later (a new process: a new incarnation, its token from its saved file)
        time.sleep(1 * M)
        p1.kill()
        time.sleep(2)
        p1.plan = inputs(4, 9, 5, 3) + ends(since(t_end) + 0.5, quit_after=6)
        p1.start()
        res = self.h.wait_all(120)
        self.agree(res)
        self.assertEqual(res['p1']['slot'], 1)                  # its old slot (§5.2)
        self.assertEqual(res['p2']['slot'], 2)
        self.assertEqual(res['p1']['sending'], 0)
        self.assertEqual(len(res['p1']['delays']), 5)           # its inputs work after the rejoin
        self.assertIn(0, res['p1']['positions'])
        tr = res['host']['trainees']
        self.assertTrue(all(t >= 0 for t in tr[:3]), tr)        # every claim became the slot's person
        self.assertEqual(len(set(tr[:3])), 3)
        self.assertGreater(res['p2']['load_ms'], 0)

    def test_two_joins_at_once_and_one_person_claimed_twice(self):
        t_end = 3 + 3 * M
        self.h.host([{"t": 3.5, "do": "start"}, {"t": 5, "do": "claim", "person": "a_fo_cw"}]
                    + ends(t_end, host=True))
        self.h.join([{"t": 1.5, "do": "claim", "person": "a_ccr1"}, {"t": 6, "do": "claim", "person": "a_fo_cw"}]
                    + ends(t_end + 0.5), 'p1')
        self.h.join([{"t": 1.6, "do": "claim", "person": "a_ccr1"}, {"t": 6, "do": "input", "item": ["role", "a_fo_cw"]}]
                    + ends(t_end + 0.5), 'p2')
        res = self.h.wait_all(120)
        self.agree(res)
        tr = res['host']['trainees']
        # the lobby: one of the two claims of a_ccr1 was taken (first come), the other player plays nobody; later the
        # host's claim of a_fo_cw came first: the others' are refused, the same on every screen (§6.1)
        self.assertEqual(sorted([tr[1] >= 0, tr[2] >= 0]), [False, True], tr)
        self.assertGreaterEqual(tr[0], 0, tr)

    def test_jump_vote_pause_by_a_player_and_away(self):
        t_end = 3 + 6 * M
        self.h.host([{"t": 2, "do": "claim", "person": "a_sup"}, {"t": 3, "do": "start"},
                     {"t": 3 + 2 * M, "do": "jump", "hhmm": "18:30"},
                     # the host's app in the background for 12 s (its main loop stopped: no packets at all), then back:
                     # its players wait for it (§7.5), it runs the session again
                     {"t": 3 + 4.5 * M, "do": "away", "freeze": 12}, {"t": 3 + 4.5 * M + 13, "do": "run"}]
                    + ends(t_end + 14, quit_after=5, host=True))
        self.h.join([{"t": 1.5, "do": "claim", "person": "a_ccr1"},
                     {"t": 3 + 1 * M, "do": "pause"}, {"t": 3 + 1 * M + 3, "do": "run"},
                     {"t": 3 + 2.2 * M, "do": "jump", "hhmm": "18:30"}] + ends(t_end + 14.5, quit_after=5), 'p1')
        res = self.h.wait_all(120)
        host = self.agree(res)
        jumps = [x for c in host['commits'] for x in c[2] if '"jump"' in x[2]]
        self.assertEqual(len(jumps), 1, jumps)                   # made once, by the host, when both had voted
        gaps = [b[4] - a[4] for a, b in zip(host['commits'], host['commits'][1:])]
        self.assertGreaterEqual(max(gaps), 2.5)                  # the player's pause stopped the commits


    def test_a_player_in_the_background(self):
        """§7.5: a player's app in the background for 12 s (its main loop stopped, as Android stops it) keeps its
        session and its person, and catches up when it is back."""
        t_end = 3 + 8 * M
        # the Wi-Fi asleep with the phone too (nothing waiting in the socket when the app is back): the link down from
        # just before the freeze until a second after it, through the network simulator
        sim = self.h.netsim()
        link = sim.link(9, Impair(outages=[(5.5, 19.5)]), Impair(outages=[(5.5, 19.5)]))
        sim.start()
        # (12 s at the harness's 20× is 2,400 steps to catch up: time enough before the end)
        self.h.host([{"t": 2, "do": "claim", "person": "a_sup"}, {"t": 3, "do": "start"}]
                    + ends(t_end, quit_after=20, host=True))
        self.h.join([{"t": 1.5, "do": "claim", "person": "a_ccr1"}, {"t": 6, "do": "away", "freeze": 12}]
                    + inputs(21, t_end - 3, 3, 4) + ends(t_end + 0.5, quit_after=20), 'p1', link=link)
        res = self.h.wait_all(120)
        self.agree(res)
        self.assertEqual(res['p1']['sending'], 0)
        self.assertGreaterEqual(res['host']['trainees'][1], 0)     # its person is still its own


    def test_the_host_gone_from_the_lobby(self):
        """A host killed while its players wait in the lobby: they notice (10 s without a packet) instead of waiting
        for ever."""
        host = self.h.host([{"t": 60, "do": "quit"}])
        self.h.join([{"t": 40, "do": "quit"}], 'p1')
        time.sleep(6)
        host.kill()
        res = self.h.wait_all(60)
        self.assertIn("can't be reached", res['p1']['why_ended'])


class Faults(Base):
    def test_desync_found_and_resynced(self):
        t_end = 3 + 4 * M
        self.h.host([{"t": 2.5, "do": "start"}] + ends(t_end, quit_after=6, host=True))
        self.h.join([{"t": 3 + 1 * M, "do": "desync", "value": 5}] + ends(t_end + 0.5, quit_after=6), 'p1')
        res = self.h.wait_all(120)
        # (its digests differ from the change until the snapshot replaced its state: within 50 steps and the
        # snapshot's way, §4)
        self.agree(res, since={'p1': 3 * 600})
        bad = [int(s) for s, d in res['p1']['digests'].items() if d != res['host']['digests'].get(s, d)]
        self.assertTrue(bad and max(bad) - min(bad) <= 150, bad)
        self.assertEqual(res['p1']['stats']['resyncs'], 1)
        self.assertEqual(res['host']['stats']['desyncs'], 1)
        self.assertTrue(res['p1']['report'].startswith('user://desync/'))

    def test_the_host_differs(self):
        """§4: when most players agree with each other against the host, the session ends ("the host's device
        differs") instead of resynchronising them to the host's state."""
        t_end = 3 + 4 * M
        self.h.host([{"t": 2.5, "do": "start"}, {"t": 3 + 1 * M, "do": "desync", "value": 5}]
                    + ends(t_end, quit_after=6, host=True))
        for k in (1, 2):
            self.h.join(ends(t_end + 0.5, quit_after=6), f'p{k}')
        res = self.h.wait_all(120)
        self.assertIn("host's device differs", res['host']['why_ended'])
        for k in (1, 2):
            self.assertEqual(res[f'p{k}']['stats']['resyncs'], 0)

    def test_fast_forward_at_the_slowest_cap(self):
        t_end = 3 + 4 * M
        self.h.host([{"t": 2.5, "do": "start"}, {"t": 4, "do": "fast"}] + ends(t_end, quit_after=6, host=True))
        self.h.join([{"t": 1, "do": "cap", "share": 0.02}, {"t": 4.5, "do": "fast"}] + ends(t_end + 0.5, quit_after=6),
                    'p1')
        self.h.join([{"t": 4.5, "do": "fast"}] + ends(t_end + 0.5, quit_after=6), 'p2')
        res = self.h.wait_all(120)
        host = self.agree(res)
        rates = sorted({c[3] for c in host['commits']})
        self.assertGreater(rates[-1], 1.0, rates)                # fast-forward ran
        # the slowest player's cap (from its measured step cost, which moves a little), not the host's own (60×)
        self.assertLessEqual(rates[-1], res['p1']['ff_cap'] * 1.25, (rates, res['p1']['ff_cap']))

    def test_floods_junk_replays_and_another_code(self):
        t_end = 3 + 3 * M
        self.h.host([{"t": 2.5, "do": "start"}] + ends(t_end, host=True))
        flood = [{"t": 5, "do": "input", "item": ["ack", "a%d" % k]} for k in range(60)]
        self.h.join(flood + ends(t_end + 0.5), 'p1')
        self.h.join([{"t": 30, "do": "quit"}], 'stranger', code='000000000000000C')   # (another session's code)
        # junk at the host's ports: random bytes, packets of our version with garbage, a replayed query
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        rng = random.Random(5)
        time.sleep(5)
        for k in range(300):
            n = rng.randrange(1, 1300)
            junk = bytes(rng.randrange(256) for _ in range(n))
            if k % 3 == 0:
                junk = bytes([1, rng.randrange(3), rng.randrange(256), 0]) + struct.pack('>HII', 1, 7, k) + junk
            s.sendto(junk, ('127.0.0.1', self.h.port))
            s.sendto(junk[:40], ('127.0.0.1', self.h.disc))
        s.close()
        res = self.h.wait_all(120)
        self.agree(res, names=['host', 'p1'])
        self.assertGreater(res['host']['stats']['dropped'], 0)   # the flood: at most 20 a turn (§10)
        self.assertLessEqual(len(res['p1']['delays']), 60)
        self.assertEqual(res['p1']['sending'], 0)                 # the inputs dropped were told: none left waiting
        self.assertIn('No session with that code', res['stranger']['why_ended'])


if __name__ == '__main__':
    unittest.main()
