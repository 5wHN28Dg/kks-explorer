"""Milestone HW3 (docs/plant3d/REALISM.md §2.22, §3.1–§3.2): condenser pressure transmitter 2's five hidden causes on
the reference engine: each with its true effect (drift low, loose terminal low, blocked line frozen, passing manifold
valve high, water in the terminal side low and jumping), the tests that tell them apart, each cured only by its own
fix, the loop test and the loop check, the value weights that keep every earlier scenario's draw, the service file's
diagnosis data and the day's forks in which the technician finds and fixes each new cause."""
import copy
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))

from ref import plant3d as P  # noqa: E402
from ref import plant3d_hands as H  # noqa: E402
from ref import plant3d_service as SV  # noqa: E402
from ref.courses import FormatError  # noqa: E402
import train_hands  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')
CP2 = '30MAG10CP002'
CAUSES = ('drift', 'loose', 'blocked', 'passing', 'wet')


def files():
    return P.load_dir(DATA)


class Causes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.b = P.check_files(files())
        cls.ix = cls.b.model.index
        cls.f = {c['id']: c for c in train_hands.FAULT['causes']}

    def engine(self, sid='cold_iron'):
        return P.Engine(self.b, sid)

    def val(self, e, name):
        return e.cur[self.ix[name]]

    def put(self, e, **states):
        for k, v in states.items():
            e.cur[self.ix[k]] = v

    def made(self, cause, steps=3, **more):
        """A cold plant with the cause's states written and the communicator and the multimeter on (the job's
        connections), after `steps` steps."""
        e = self.engine()
        e.step(2)
        st = dict(cpt2_terminal_block_dmm=1, cpt2_terminal_block_hart=1, cpt2_cover_back_off=1)
        st.update(self.f[cause]['set'] if cause else {})
        st.update(more)
        self.put(e, **st)
        e.step(steps)
        return e

    def signature(self, e):
        """What the tests show: the PV against transmitter 1 (rounded), the multimeter's current against the output
        the transmitter reports, the screen against the PV, water seen, and the ohms to earth with the leads on."""
        pv, p1 = H.shown(e, 'cpt2_pv', e.cur), self.val(e, 'cond_p1')
        dmm, ao = H.shown(e, 'cpt2_dmm', e.cur), H.shown(e, 'cpt2_ao', e.cur)
        return (round(pv - p1, 1), round(ao - dmm, 2), round(self.val(e, 'cond_p2') - pv, 1) < -1,
                self.val(e, 'cpt2_terminal_block_wet'))

    def test_each_cause_its_own_effect(self):
        """REALISM.md §2.22 (the user's option A): drift low, a loose terminal low through the current, a passing
        manifold valve 2 kPa high, water low on the screen with the current right at the transmitter."""
        sig = {c: self.signature(self.made(c)) for c in CAUSES}
        self.assertEqual(sig['drift'], (-1.4, 0, False, 0))
        self.assertEqual(sig['loose'], (0.1, 0.3, True, 0))
        self.assertEqual(sig['passing'], (2.1, 0, False, 0))
        self.assertEqual(sig['wet'][:2], (0.1, 0))
        self.assertTrue(sig['wet'][2] and sig['wet'][3])
        self.assertEqual(len({sig[c] for c in ('drift', 'loose', 'passing', 'wet')}), 4)

    def test_blocked_line_holds_and_the_vent_test(self):
        """A blocked line holds what was in it while the process moves; vented and shut again it keeps the air's
        pressure (a clear line goes back to the process); blown through it follows the process again."""
        e = self.engine()
        e.step(2)
        self.put(e, cpt2_manifold_block=1)
        e.step(2)
        held = self.val(e, 'cond_p2_tx')
        e.cur[self.ix['cond_p']] -= 40           # the condenser evacuated meanwhile
        e.step(2)
        self.assertEqual(self.val(e, 'cond_p2_tx'), held)
        self.assertLess(self.val(e, 'cond_p1'), held - 30)
        for vent in (1, 0):
            self.put(e, cpt2_drain_vents_open=vent)
            e.step(2)
            self.assertAlmostEqual(self.val(e, 'cond_p2_tx'), 101.3, places=6)   # the air's
        self.assertEqual(self.val(e, 'cpt2_vent_held'), 1)
        self.put(e, cpt2_manifold_block=0)
        e.step(2)
        self.assertAlmostEqual(self.val(e, 'cond_p2_tx'), self.val(e, 'cond_p1') + 0.1, places=6)
        # the same test on a clear line: it goes back to the process
        e = self.engine()
        e.step(2)
        e.cur[self.ix['cond_p']] -= 40
        self.put(e, cpt2_drain_vents_open=1)
        e.step(2)
        self.put(e, cpt2_drain_vents_open=0)
        e.step(2)
        self.assertAlmostEqual(self.val(e, 'cond_p2_tx'), self.val(e, 'cond_p1') + 0.1, places=6)
        self.assertEqual(self.val(e, 'cpt2_vent_held'), 0)

    def test_water_low_and_jumping_and_the_ohms(self):
        e = self.made('wet', 1)
        lows = set()
        for _ in range(80):                      # 8 s: the wobble's 7 s cycle
            e.step()
            leak = (self.val(e, 'cond_p2_tx') - self.val(e, 'cond_p2')) / 7.5
            self.assertTrue(0.6 - 1e-9 <= leak <= 1.0 + 1e-9, leak)
            lows.add(round(leak, 2))
        self.assertGreater(len(lows), 10)        # it jumps
        self.assertEqual(H.shown(e, 'cpt2_ohm', e.cur), 1e8)    # the leads not on: OL
        self.put(e, cpt2_terminal_block_lift=1, cpt2_terminal_block_ohm=1)
        e.step(2)
        self.assertEqual(H.shown(e, 'cpt2_ohm', e.cur), 40)
        self.put(e, cpt2_terminal_block_wet=0)
        e.step(2)
        self.assertEqual(H.shown(e, 'cpt2_ohm', e.cur), 1e8)

    def test_each_cure_needs_its_own_fix(self):
        """A cause is cured (`cpt2_sound`) only when its own fix is made and the transmitter left sound; another
        cause's fix leaves it."""
        fixes = {'drift': {'cond_p2_trim': 1.5}, 'loose': {'cpt2_terminal_block_loose': 0},
                 'blocked': {'cpt2_manifold_block': 0}, 'passing': {'cpt2_manifold_pass': 0},
                 'wet': {'cpt2_terminal_block_wet': 0, 'cpt2_cable_gland_worn': 0}}
        for cause in CAUSES:
            for other, fix in fixes.items():
                e = self.made(cause, 2, cpt2_cover_back_off=0, cpt2_terminal_block_dmm=0, cpt2_terminal_block_hart=0)
                self.put(e, **fix)
                e.step(2)
                self.assertEqual(self.val(e, 'cpt2_sound'), 1 if other == cause else 0, (cause, other))
        # half the water's fix (dried, the gland's seal not renewed), a vent left open, a loop test left on
        for bad in ({'cpt2_terminal_block_wet': 0}, {'cpt2_cable_gland_worn': 0}):
            e = self.made('wet', 2, cpt2_cover_back_off=0)
            self.put(e, **bad)
            e.step(2)
            self.assertEqual(self.val(e, 'cpt2_sound'), 0, bad)
        for bad in ({'cpt2_drain_vents_open': 1}, {'cpt2_electronics_lt': 12}):
            e = self.engine()
            e.step(2)
            self.put(e, **bad)
            e.step(2)
            self.assertEqual(self.val(e, 'cpt2_sound'), 0, bad)

    def test_loop_test_and_the_screen_under_isolation(self):
        """The loop test holds the output at the current typed in: the multimeter and the AO read it, and the screen
        shows the value it stands for, even with the transmitter isolated (its last reading otherwise)."""
        vals = {x[0]: x[1] for x in self.b.model.values}
        self.assertEqual((vals['cpt2_shown']['hold'], vals['cpt2_shown']['when']), ('cond_p2_rx', 'iso_cond_p2_complete'))
        self.assertEqual(vals['cond_p2']['select'], 'cpt2_lt_on')   # the loop test's value past the isolation's hold
        self.assertEqual(vals['cond_p2']['cases'], ['cpt2_shown', 'cond_p2_rx'])
        e = self.engine()
        e.step(2)
        for ma, kpa in ((4, 0), (8, 30), (12, 60), (16, 90), (20, 120)):
            self.put(e, cpt2_electronics_lt=ma)
            e.step(2)
            self.assertEqual(self.val(e, 'cpt2_ma'), ma)
            self.assertAlmostEqual(self.val(e, 'cond_p2'), kpa, places=9)
        self.put(e, cpt2_electronics_lt=0)
        e.step(2)
        self.assertEqual(self.val(e, 'cpt2_ma_tx'), self.val(e, 'cpt2_ma_n'))


class Weights(unittest.TestCase):
    """The three new causes weigh by a value: 0 in every scenario but shift_tx, so every earlier scenario's draw is
    what it was (the draw's total stays 2); shift_tx's seed draws the blocked line, made once the condenser is under
    60 kPa(a)."""

    def test_draws(self):
        F = files()
        b = P.check_files(F)
        for rel in sorted(F):
            if not rel.startswith('scenarios/') or 'cond_p2_low' not in F[rel].decode():
                continue
            sid = rel.split('/')[1][:-5]
            e = P.Engine(b, sid)
            ws = [e.cur[b.model.index[w]] for w in train_hands.W_NEW]
            self.assertEqual(ws, [1, 1, 1] if sid == 'shift_tx' else [0, 0, 0], sid)
        sc = json.loads(F['scenarios/shift_tx.json'].decode())
        f = next(x for x in sc['faults'] if x['id'] == 'cond_p2_low')
        self.assertEqual(f['when'], {'cmp': ['cond_p', '<', 60]})
        from ref.plant3d_world import draw, stream, TAGS, world_seed
        _, r = draw(stream(world_seed(sc), TAGS['causes'], 'cond_p2_low'))
        self.assertEqual(CAUSES[(r * 5) >> 24], 'blocked')


class Diagnosis(unittest.TestCase):
    """The service file's diagnosis data (REALISM.md §2.22) and its check's refusals."""

    @classmethod
    def setUpClass(cls):
        F = files()
        cls.s = json.loads(F['service/pressure_transmitter.json'].decode())
        cls.ws = json.loads(F['workshop/pressure_transmitter.json'].decode())
        cls.tools = {t['id'] for t in json.loads(F['tools.json'].decode())['tools']}

    def check(self, s):
        return SV.check(s, self.ws, self.tools, 'service/pressure_transmitter.json')

    def test_every_cause_told_apart_and_fixed(self):
        self.check(self.s)
        self.assertEqual([c['id'] for c in self.s['causes']], list(CAUSES))
        # every two causes are told apart by a test that shows one and not the other (REALISM.md §13)
        for a in CAUSES:
            for b in CAUSES:
                if a < b:
                    self.assertTrue(any((a in t['shows']) != (b in t['shows']) for t in self.s['tests']), (a, b))

    def test_rejects(self):
        def bad(change, code):
            s = copy.deepcopy(self.s)
            change(s)
            with self.assertRaises(FormatError) as cm:
                self.check(s)
            self.assertEqual(cm.exception.code, code)
        bad(lambda s: s['causes'][0].update(component='nope'), 'bad_ref')
        bad(lambda s: s['tests'][0].update(shows=list(CAUSES)), 'bad_ref')       # a test showing all tells nothing
        bad(lambda s: s['tests'][0].update(shows=['nope']), 'bad_ref')
        bad(lambda s: s['tests'][0].update(action='open_cover'), 'missing_key')  # an action and a meter
        bad(lambda s: s['fixes'].append(['nope', ['wet']]), 'bad_ref')
        bad(lambda s: s.update(fixes=[x for x in s['fixes'] if x[0] != 'blow_line']), 'bad_ref')   # blocked unfixed
        bad(lambda s: s['causes'].append(dict(s['causes'][0])), 'dup_id')
        bad(lambda s: s['actions'][-1].pop('set'), 'missing_key')                 # neither set nor input
        bad(lambda s: next(a for a in s['actions'] if a['action'] == 'loop_test').pop('range'), 'missing_key')


class Job(unittest.TestCase):
    def test_steps_fit_with_the_talk(self):
        tasks = {t['id']: t for t in json.loads(files()['staff.json'].decode())['tasks']}
        steps = tasks['job_cond_p2_fix']['steps']
        self.assertLessEqual(len(steps), 64)
        lt = [s.get('value') for s in steps if s.get('hand') == 'loop_test']
        self.assertEqual(lt, list(train_hands.LOOP_CHECK))


class JobForks(unittest.TestCase):
    """The day's vectors (plant3d-v2.json): the technician makes only the tests and the fix its readings call for,
    and each new cause is cured."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v2.json'), encoding='utf-8') as f:
            cls.forks = {x['id']: x for x in json.load(f)['day']['forks']}

    def done(self, fork):
        ev = self.forks[fork]['events']
        hands = [x[3] for x in ev if x[1] == 'hand' and x[2] == CP2 and x[6] == 'done']
        trims = [x for x in ev if x[1] == 'op' and x[2] == CP2 and x[3] == 'set' and x[4] == 'done']
        repairs = [x for x in ev if x[1] == 'repair' and x[2] == 'cond_p2_low']
        loop = [x[4] for x in ev if x[1] == 'read' and x[3] == CP2 and x[4] in (0, 30, 60, 90, 120)]
        return set(hands), len(trims), len(repairs), loop

    def test_blocked(self):
        hands, trims, repairs, loop = self.done('npc_hands_blocked')
        self.assertTrue({'crack_vent', 'close_vent', 'blow_line'} <= hands)
        self.assertFalse({'shut_test', 'reseal_gland', 'tighten_terms'} & hands)
        self.assertEqual((trims, repairs, loop), (0, 1, [0, 30, 60, 90, 120]))

    def test_passing(self):
        hands, trims, repairs, loop = self.done('npc_hands_passing')
        self.assertTrue({'crack_vent', 'close_vent', 'shut_test'} <= hands)
        self.assertFalse({'blow_line', 'reseal_gland', 'tighten_terms'} & hands)
        self.assertEqual((trims, repairs, loop), (0, 1, [0, 30, 60, 90, 120]))

    def test_wet(self):
        hands, trims, repairs, loop = self.done('npc_hands_wet')
        self.assertTrue({'dry_terms', 'lift_wires', 'reseal_gland', 'land_wires'} <= hands)
        self.assertFalse({'crack_vent', 'blow_line', 'shut_test', 'tighten_terms'} & hands)
        self.assertEqual((trims, repairs, loop), (0, 1, [0, 30, 60, 90, 120]))


if __name__ == '__main__':
    unittest.main()
