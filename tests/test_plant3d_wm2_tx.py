"""Milestone WM2 (docs/plant3d/REALISM.md §2.23–§2.24): replacing condenser pressure transmitter 2 (HW3's leftover).
The sixth hidden cause, the failed sensor module (the output at NAMUR NE 43's low alarm current, HART reporting a
sensor failure), weighed by a value at 0 in every earlier scenario; put right only by a new transmitter whose range is
set from the data sheet; the job that finds it, has the storekeeper issue the spare against the work order, replaces
it and makes the loop check; the service file's diagnosis data; the day's forks (plant3d-v2.json) with the spare on
the shelf and without it (the look-alike refused, the spare ordered and delivered across jumps)."""
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
import train_hands  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')
CP2 = '30MAG10CP002'
CAUSES = ('drift', 'loose', 'blocked', 'passing', 'wet', 'failed')
NEW = {'cpt2_sensor_module_fail': 0, 'cpt2_flange_bolts_off': 0, 'cpt2_electronics_urv': 120}


def files():
    return P.load_dir(DATA)


class Failed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.F = files()
        cls.b = P.check_files(cls.F)
        cls.ix = cls.b.model.index

    def val(self, e, name):
        return e.cur[self.ix[name]]

    def put(self, e, **states):
        for k, v in states.items():
            e.cur[self.ix[k]] = v

    def made(self, **more):
        """The cold plant with the condenser at 40 kPa(a), the communicator and the multimeter on, the cover off, the
        sensor failed (and `more`), after three steps."""
        e = P.Engine(self.b, 'cold_iron')
        e.step(2)
        e.cur[self.ix['cond_p']] = 40
        st = dict(cpt2_terminal_block_dmm=1, cpt2_terminal_block_hart=1, cpt2_cover_back_off=1,
                  cpt2_sensor_module_fail=1)
        st.update(more)
        self.put(e, **st)
        e.step(3)
        return e

    def test_the_low_alarm_current_and_the_status(self):
        """The output at 3.6 mA (NE 43: at most 3.6), the AO and the multimeter read it, the screen shows what it
        stands for (far below range), HART's status says the sensor failed; the job's decision sees it."""
        e = self.made()
        self.assertEqual(self.val(e, 'cpt2_ma_tx'), 3.6)
        self.assertEqual(H.shown(e, 'cpt2_ao', e.cur), 3.6)
        self.assertEqual(H.shown(e, 'cpt2_dmm', e.cur), 3.6)
        self.assertEqual(H.shown(e, 'cpt2_status', e.cur), 1)
        self.assertAlmostEqual(self.val(e, 'cond_p2'), -3.0, places=9)
        self.assertEqual((self.val(e, 'cpt2_failed_seen'), self.val(e, 'cpt2_alive')), (1, 0))
        # a sound transmitter: status 0, alive
        e = self.made(cpt2_sensor_module_fail=0)
        self.assertEqual(H.shown(e, 'cpt2_status', e.cur), 0)
        self.assertEqual(self.val(e, 'cpt2_alive'), 1)

    def test_only_a_new_transmitter_with_its_range_cures_it(self):
        fixes = {'trim': {'cond_p2_trim': 1.5}, 'tighten': {'cpt2_terminal_block_loose': 0},
                 'blow': {'cpt2_manifold_block': 0}, 'shut_test': {'cpt2_manifold_pass': 0},
                 'dry': {'cpt2_terminal_block_wet': 0, 'cpt2_cable_gland_worn': 0}}
        for name, fix in fixes.items():
            e = self.made(cpt2_cover_back_off=0, cpt2_terminal_block_dmm=0, cpt2_terminal_block_hart=0, **fix)
            e.step(2)
            self.assertEqual(self.val(e, 'cpt2_sound'), 0, name)
        e = self.made(cpt2_cover_back_off=0, cpt2_terminal_block_dmm=0, cpt2_terminal_block_hart=0, **NEW)
        e.step(2)
        self.assertEqual(self.val(e, 'cpt2_sound'), 1)
        # the new one as the factory ships it (its range the sensor's limit, 248 kPa): not sound, and the screen
        # reads the condenser low by the ratio of the spans
        e = self.made(cpt2_cover_back_off=0, cpt2_terminal_block_dmm=0, cpt2_terminal_block_hart=0,
                      **dict(NEW, cpt2_electronics_urv=248))
        e.step(2)
        self.assertEqual(self.val(e, 'cpt2_sound'), 0)
        self.assertAlmostEqual(self.val(e, 'cond_p2'), self.val(e, 'cond_p2_tx') * 120 / 248, places=6)
        # unbolted: not sound
        e = self.made(cpt2_cover_back_off=0, cpt2_terminal_block_dmm=0, cpt2_terminal_block_hart=0,
                      **dict(NEW, cpt2_flange_bolts_off=1))
        e.step(2)
        self.assertEqual(self.val(e, 'cpt2_sound'), 0)

    def test_the_range_set_reads_true(self):
        """A new transmitter with the data sheet's range (120 kPa) shows the condenser's pressure as the
        commissioned one does (to rounding); the old one's 0 is the data sheet's (every earlier value: that node)."""
        e = self.made(**NEW)
        self.assertAlmostEqual(self.val(e, 'cond_p2'), self.val(e, 'cond_p2_tx'), places=6)
        self.assertEqual(self.val(e, 'cpt2_rng_ok'), 1)
        vals = {x[0]: x[1] for x in self.b.model.values}
        self.assertEqual(vals['cpt2_ma_s2'], {'select': 'cpt2_rng_on', 'cases': ['cpt2_ma_s', 'cpt2_ma_sf']})

    def test_the_hand_actions(self):
        """The removal's needs in order, the fitting's part, the range's input."""
        hands = {(h['kks'], h['action']): h for h in self.b.model.hands}
        rm, fit, rng = hands[(CP2, 'remove_tx')], hands[(CP2, 'fit_tx')], hands[(CP2, 'set_range')]
        self.assertEqual([n for n, _ in rm['needs']], ['cpt2_terminal_block_lift', 'cpt2_no_leads',
                                                       'cpt2_manifold_shut', 'cpt2_drain_vents_open'])
        self.assertEqual(fit['part'], train_hands.SPARE)
        self.assertEqual(fit['set']['cpt2_electronics_urv'], 248)
        self.assertEqual((rng['input'], rng['range']), ('cpt2_electronics_urv', [1, 248]))
        stores = json.loads(self.F['stores.json'].decode())
        a3 = next(p for p in stores['parts'] if p['id'] == train_hands.SPARE)
        self.assertEqual([x['part'] for x in a3['looks_like']], [train_hands.LOOKALIKE])


class Weights(unittest.TestCase):
    def test_draws(self):
        F = files()
        b = P.check_files(F)
        from ref.plant3d_world import draw, stream, TAGS, world_seed
        for rel in sorted(F):
            if not rel.startswith('scenarios/') or 'cond_p2_low' not in F[rel].decode():
                continue
            sid = rel.split('/')[1][:-5]
            e = P.Engine(b, sid)
            w = e.cur[b.model.index[train_hands.W_FAIL]]
            self.assertEqual(w, 1 if sid in ('shift_fail', 'shift_nospare') else 0, sid)
        for sid in ('shift_fail', 'shift_nospare'):
            sc = json.loads(F[f'scenarios/{sid}.json'].decode())
            _, r = draw(stream(world_seed(sc), TAGS['causes'], 'cond_p2_low'))
            self.assertEqual(CAUSES[(r * 6) >> 24], 'failed', sid)
        self.assertEqual(json.loads(F['scenarios/shift_nospare.json'].decode())['stock'], {train_hands.SPARE: 0})


class Diagnosis(unittest.TestCase):
    def test_cause_test_fix_part(self):
        F = files()
        s = json.loads(F['service/pressure_transmitter.json'].decode())
        ws = json.loads(F['workshop/pressure_transmitter.json'].decode())
        tools = {t['id'] for t in json.loads(F['tools.json'].decode())['tools']}
        SV.check(s, ws, tools, 'service/pressure_transmitter.json')     # every cause shown and fixed
        self.assertEqual([c['id'] for c in s['causes']], list(CAUSES))
        self.assertEqual([x[1] for x in s['fixes'] if 'failed' in x[1]], [['failed']])
        self.assertEqual([x[0] for x in s['fixes'] if 'failed' in x[1]], ['fit_tx'])
        self.assertIn(['fit_tx', train_hands.SPARE, 'A complete pressure transmitter, range 3 (WDP-PT-UNIT-A3)'],
                      s['parts'])
        self.assertEqual(sorted(t['meter'] for t in s['tests'] if 'failed' in t['shows']), ['$_ao', '$_status'])


class Job(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tasks = {t['id']: t for t in json.loads(files()['staff.json'].decode())['tasks']}

    def test_lengths_and_the_way_to_the_replacement(self):
        main = self.tasks['job_cond_p2_fix']['steps']
        self.assertEqual(len(main), 64)
        # the decision after the readings: alive goes on at once, else to the last step, the replacement's choice
        i = next(k for k, s in enumerate(main) if s.get('wait', {}).get('until') == 'cpt2_alive')
        self.assertEqual(main[i]['wait']['else'], len(main) - 1)
        self.assertEqual(main[-1], {'choose': [[1, train_hands.TX]]})
        self.assertEqual(main[-2], {'choose': [[1, train_hands.END]]})       # the job's end, never into the last
        for t in (train_hands.TX, train_hands.FIT, train_hands.END, train_hands.ISSUE):
            self.assertLessEqual(len(self.tasks[t]['steps']), 64, t)
            self.assertEqual(self.tasks[t]['work'], 'wo_cond_p2_fix', t)

    def test_order(self):
        tx = self.tasks[train_hands.TX]['steps']
        order = [s.get('hand') or next(iter(s)) for s in tx]
        first = order.index
        self.assertLess(first('call'), first('remove_tx'))
        for a, b in (('disconnect_dmm', 'lift_wires'), ('lift_wires', 'shut_block'), ('shut_block', 'crack_vent'),
                     ('crack_vent', 'remove_tx'), ('remove_tx', 'fit_tx')):
            self.assertLess(first(a), first(b), (a, b))
        # held for parts: the fitting's else waits for a spare on the shelf and calls the storekeeper again
        fit = tx[first('fit_tx')]
        self.assertEqual(tx[fit['else']], {'say': 'held_for_parts', 'to': 'maint_sup'})
        self.assertEqual(tx[fit['else'] + 1], {'wait': {'until': 'cpt2_spare_shelf'}})
        fs = self.tasks[train_hands.FIT]['steps']
        hands = [s.get('hand') for s in fs]
        self.assertLess(hands.index('set_range'), hands.index('loop_test'))
        self.assertEqual(next(s for s in fs if s.get('hand') == 'set_range')['value'], 120)
        self.assertEqual([s['value'] for s in fs if s.get('hand') == 'loop_test'], list(train_hands.LOOP_CHECK))
        iss = self.tasks[train_hands.ISSUE]['steps']
        self.assertEqual(iss[1], {'issue': train_hands.SPARE, 'qty': 1, 'for': '$', 'else': 2})
        self.assertEqual(iss[-1], {'order': train_hands.SPARE})
        # only the storekeeper issues (the validator's authority rule): the issue task is called for the store role
        self.assertTrue(all(s['call']['role'] == 'store' for s in tx if 'call' in s))


class Forks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v2.json'), encoding='utf-8') as f:
            cls.forks = {x['id']: x for x in json.load(f)['day']['forks']}

    def hands(self, fork, how='done'):
        return [x[3] for x in self.forks[fork]['events'] if x[1] == 'hand' and x[2] == CP2 and x[6] == how]

    def test_failed(self):
        ev = self.forks['npc_hands_failed']['events']
        self.assertIn(['cause', 'cond_p2_low', 'failed'], [x[1:] for x in ev])
        h = self.hands('npc_hands_failed')
        for a in ('remove_tx', 'fit_tx', 'land_wires', 'open_block', 'set_range'):
            self.assertIn(a, h)
        self.assertLess(h.index('remove_tx'), h.index('fit_tx'))
        self.assertLess(h.index('set_range'), h.index('loop_test'))
        issues = [x[1:] for x in ev if x[1] == 'issue']
        self.assertEqual(issues, [['issue', 'pt_unit_a3', 1, 'wo_cond_p2_fix', 'store1', 'done', []]])
        self.assertEqual(len([x for x in ev if x[1] == 'repair' and x[2] == 'cond_p2_low']), 1)
        first = next(i for i, x in enumerate(ev) if x[1] == 'hand' and x[3] == 'loop_test')
        loop = [x[4] for x in ev[first:] if x[1] == 'read' and x[3] == CP2 and x[4] in (0, 30, 60, 90, 120)]
        self.assertEqual(loop, [0, 30, 60, 90, 120])

    def test_nospare(self):
        ev = self.forks['npc_hands_nospare']['events']
        self.assertIn(['wrong_part'], [x[7] for x in ev if x[1] == 'hand' and x[3] == 'fit_tx' and x[6] == 'refused'])
        self.assertTrue(any(x[1] == 'delivery' and x[3] == 'pt_unit_a3' for x in ev))
        self.assertEqual(self.hands('npc_hands_nospare').count('fit_tx'), 1)
        self.assertEqual(len([x for x in ev if x[1] == 'repair' and x[2] == 'cond_p2_low']), 1)


if __name__ == '__main__':
    unittest.main()
