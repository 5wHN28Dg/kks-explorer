"""Milestone HW2 (docs/plant3d/REALISM.md §2.16, §3): the first train's hands-on content. The service file and its
check, the hand actions, meters and HART ops the content tool makes from it, the loop each transmitter drives and
the job with a hidden cause, on the reference engine."""
import copy
import json
import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))

from ref import plant3d as P  # noqa: E402
from ref import plant3d_service as SV  # noqa: E402
from ref.courses import FormatError  # noqa: E402
import train_hands  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')
CP2, CP3 = '30MAG10CP002', '30MAG10CP003'


def files():
    return P.load_dir(DATA)


def jload(F, rel):
    return json.loads(F[rel].decode())


class ServiceFile(unittest.TestCase):
    """The service file is checked against its kind's Workshop data and tools.json (ref/plant3d_service.py)."""

    @classmethod
    def setUpClass(cls):
        cls.F = files()
        cls.s = jload(cls.F, 'service/pressure_transmitter.json')
        cls.ws = jload(cls.F, 'workshop/pressure_transmitter.json')
        cls.tools = {t['id'] for t in jload(cls.F, 'tools.json')['tools']}

    def code_of(self, change):
        s = copy.deepcopy(self.s)
        change(s)
        try:
            SV.check(s, self.ws, self.tools, 'service/pressure_transmitter.json')
        except FormatError as e:
            return e.code
        return None

    def test_valid(self):
        self.assertIsNone(self.code_of(lambda s: None))

    def test_rejects(self):
        def act(s, k, v):
            s['actions'][2][k] = v
        cases = [
            ('an alias of 9 characters', 'bad_id', lambda s: s['equipment'][0].update(alias='cpt2abcde')),
            ('a state of 7 characters', 'bad_id', lambda s: s['states'][0].__setitem__(1, 'offside')),
            ('a state of a component the tree lacks', 'bad_ref', lambda s: s['states'][0].__setitem__(0, 'lid')),
            ('an action on a component the tree lacks', 'bad_ref', lambda s: act(s, 'component', 'lid')),
            ('a tool tools.json lacks', 'bad_ref', lambda s: act(s, 'tools', ['sd_pz2'])),
            ('a wrong tool tools.json lacks', 'bad_ref', lambda s: act(s, 'wrong', {'sd_pz2': 'No'})),
            ('a need nothing makes', 'bad_ref', lambda s: act(s, 'needs', [['$_nothing', 'No']])),
            ('setting a value, not a state', 'bad_ref', lambda s: act(s, 'set', {'$_wired': 1})),
            ('an unknown key', 'unknown_key', lambda s: act(s, 'torque', 2)),
            ('an alias twice', 'dup_id', lambda s: s['equipment'][1].update(alias='cpt2')),
            ('a meter reading what nothing makes', 'bad_ref', lambda s: s['meters'][0].update(value='$_nope')),
            ('a source it doesn\'t list', 'bad_ref', lambda s: act(s, 'sources', ['nope'])),
        ]
        for why, code, change in cases:
            with self.subTest(why):
                self.assertEqual(self.code_of(change), code)
        with self.subTest('no tools.json'):
            with self.assertRaises(FormatError) as cm:
                SV.check(self.s, self.ws, None, 'service/pressure_transmitter.json')
            self.assertEqual(cm.exception.code, 'missing_key')

    def test_the_whole_plant_refuses_a_bad_service_file(self):
        F = dict(self.F)
        s = copy.deepcopy(self.s)
        s['states'][0][0] = 'lid'
        F['service/pressure_transmitter.json'] = json.dumps(s).encode()
        with self.assertRaises(FormatError) as cm:
            P.check_files(F)
        self.assertEqual(cm.exception.code, 'bad_ref')

    def test_hand_action_components_against_the_workshop_tree(self):
        """(A bug found in HW2: the check read the Workshop file's summary, a count, as its components, so a plant
        whose hand actions name a kind with Workshop data failed with a TypeError instead of being checked.) Every
        component the first train's hand actions name is accepted; one the tree lacks is refused bad_ref."""
        b = P.check_files(self.F)
        self.assertTrue(b.model.hands)
        F = dict(self.F)
        st = jload(F, 'model/st.json')
        st['hands'][0]['component'] = 'lid'
        F['model/st.json'] = json.dumps(st).encode()
        with self.assertRaises(FormatError) as cm:
            P.check_files(F)
        self.assertEqual(cm.exception.code, 'bad_ref')


class Generated(unittest.TestCase):
    """What the content tool makes from the service file (tools/plant3d/train_hands.py)."""

    @classmethod
    def setUpClass(cls):
        cls.F = files()
        cls.b = P.check_files(cls.F)
        cls.st = jload(cls.F, 'model/st.json')

    def test_each_transmitter_has_its_actions_meters_and_hart_op(self):
        s = jload(self.F, 'service/pressure_transmitter.json')
        for code, alias in ((CP2, 'cpt2'), (CP3, 'cpt3')):
            hands = [h for h in self.st['hands'] if h['kks'] == code]
            self.assertEqual([h['action'] for h in hands], [a['action'] for a in s['actions']])
            meters = [m['id'] for m in self.st['meters'] if m['kks'] == code]
            self.assertEqual(meters, [m['id'].replace('$_', alias + '_') for m in s['meters']])
            hart = [o for o in self.st['ops'] if o['kks'] == code and o['where'] == ['hart']]
            self.assertEqual(len(hart), 1)
            self.assertEqual(hart[0]['hart'], f'{alias}_terminal_block_hart')
            for h in hands:
                for name in h['set']:
                    self.assertTrue(name.startswith(alias + '_') and len(name) <= 32, name)

    def test_every_state_is_a_state_and_fits(self):
        values = dict((n, v) for n, v in self.st['values'])
        s = jload(self.F, 'service/pressure_transmitter.json')
        for alias in ('cpt2', 'cpt3'):
            for comp, state, _ in s['states']:
                name = f'{alias}_{comp}_{state}'
                self.assertIn('state', values[name])
                self.assertLessEqual(len(name), 32)

    def test_toolbox_is_a_place_of_the_staff(self):
        places = {p['id']: p for p in jload(self.F, 'staff.json')['places']}
        self.assertEqual(places['ic_toolbox']['kind'], 'toolbox')
        for t in jload(self.F, 'tools.json')['tools']:
            for place, _ in t['at']:
                self.assertIn(places[place]['kind'], ('toolbox', 'store'))

    def test_the_technician_may_use_the_communicator(self):
        roles = {r['id']: r for r in jload(self.F, 'staff.json')['roles']}
        self.assertIn('operate_hart', roles['ic_tech']['authority'])

    def test_the_job_is_done_by_hand(self):
        tasks = {t['id']: t for t in jload(self.F, 'staff.json')['tasks']}
        job = tasks['job_cond_p2_fix']
        self.assertEqual(job['work'], 'wo_cond_p2_fix')
        kinds = {k for s in job['steps'] for k in s}
        self.assertIn('hand', kinds)
        self.assertIn('tool', kinds)
        self.assertEqual(job['steps'][0], {'go': 'ic_toolbox'})
        works = {w['id']: w for w in self.st['works']}
        self.assertEqual(works['wo_cond_p2_fix']['repairs'], 'cond_p2_low')
        self.assertEqual(works['wo_cond_p2_fix']['task'], 'job_cond_p2_fix')


class Loop(unittest.TestCase):
    """The loop each transmitter drives (REALISM.md §2.16) on the reference engine: the control system receives the
    transmitter's own value while the loop is sound, the current's value when a wire is lifted or a terminal loose;
    the meters show what they should; the trim moves the PV."""

    @classmethod
    def setUpClass(cls):
        cls.b = P.check_files(files())

    def engine(self):
        return P.Engine(self.b, 'cold_iron')

    def val(self, e, name):
        return e.cur[self.b.model.index[name]]

    def put(self, e, **states):
        for k, v in states.items():
            e.cur[self.b.model.index[k]] = v

    def test_sound_loop_is_the_transmitters_own_value(self):
        e = self.engine()
        e.step(3)
        self.assertEqual(self.val(e, 'cond_p2_rx'), self.val(e, 'cond_p2_tx'))
        self.assertEqual(self.val(e, 'cond_p2'), self.val(e, 'cond_p2_tx'))
        ma = 4 + self.val(e, 'cond_p2_tx') * round(16 / 120, 12)
        self.assertAlmostEqual(self.val(e, 'cpt2_ma'), min(20.5, max(3.8, ma)), places=9)
        self.assertEqual(self.val(e, 'cpt2_ma'), self.val(e, 'cpt2_ma_tx'))

    def test_lifted_wire_and_loose_terminal(self):
        e = self.engine()
        e.step(2)
        tx = self.val(e, 'cond_p2_tx')
        self.put(e, cpt2_terminal_block_lift=1)
        e.step()
        self.assertEqual(self.val(e, 'cpt2_ma'), 0)
        self.assertAlmostEqual(self.val(e, 'cond_p2'), -30, places=9)
        self.put(e, cpt2_terminal_block_lift=0, cpt2_terminal_block_loose=1)
        e.step()
        self.assertAlmostEqual(self.val(e, 'cpt2_ma_tx') - self.val(e, 'cpt2_ma'), 0.3, places=9)
        self.assertAlmostEqual(self.val(e, 'cond_p2'), tx - 0.3 * 7.5, places=6)
        self.assertEqual(self.val(e, 'cond_p3'), self.val(e, 'cond_p3_tx'))   # (transmitter 3's loop is its own)

    def test_meters(self):
        from ref import plant3d_hands as H
        e = self.engine()
        e.step(2)
        self.assertEqual(H.shown(e, 'cpt2_dmm', e.cur), 0)          # not connected: its `else`
        self.put(e, cpt2_terminal_block_dmm=1, cpt2_terminal_block_hart=1, cpt2_cable_gland_clamp=1,
                 cpt2_terminal_block_clamp=1)
        e.step()
        self.assertEqual(H.shown(e, 'cpt2_dmm', e.cur), self.val(e, 'cpt2_ma'))
        self.assertEqual(H.shown(e, 'cpt2_clamp1', e.cur), self.val(e, 'cpt2_ma'))
        self.assertEqual(H.shown(e, 'cpt2_clamp2', e.cur), 0)       # round both wires: the currents cancel
        self.assertEqual(H.shown(e, 'cpt2_pv', e.cur), self.val(e, 'cond_p2_tx'))
        self.assertEqual(H.shown(e, 'cpt2_ao', e.cur), self.val(e, 'cpt2_ma_tx'))
        self.put(e, cpt2_terminal_block_lift=1)                      # no loop: the communicator finds no device
        e.step()
        self.assertEqual(H.shown(e, 'cpt2_pv', e.cur), 0)

    def test_causes_told_apart(self):
        """Every cause has a test that tells it from the other (REALISM.md §13): a drift shows in the HART PV against
        transmitter 1, with the multimeter's current equal to the one the transmitter sets; a loose terminal leaves
        the PV right and the multimeter's current below the transmitter's."""
        from ref import plant3d_hands as H
        seen = {}
        for cause, sets in (('drift', {'cond_p2_drift': -1.5}), ('loose', {'cpt2_terminal_block_loose': 1})):
            e = self.engine()
            e.step(2)
            self.put(e, cpt2_terminal_block_dmm=1, cpt2_terminal_block_hart=1, **sets)
            e.step()
            pv, p1 = H.shown(e, 'cpt2_pv', e.cur), self.val(e, 'cond_p1')
            dmm, ao = H.shown(e, 'cpt2_dmm', e.cur), H.shown(e, 'cpt2_ao', e.cur)
            seen[cause] = (round(pv - p1, 6), round(ao - dmm, 6))
            self.assertLess(self.val(e, 'cond_p2'), p1 - 1)            # the symptom: reads low against its partner
        self.assertEqual(seen['drift'], (-1.4, 0))
        self.assertEqual(seen['loose'], (0.1, 0.3))

    def test_the_trim_moves_the_pv(self):
        e = self.engine()
        e.step(2)
        self.put(e, cond_p2_drift=-1.5, cond_p2_trim=1.4)
        e.step()
        self.assertAlmostEqual(self.val(e, 'cond_p2_tx'), self.val(e, 'cond_p1'), places=9)

    def test_what_the_job_reads_and_the_causes_fixes(self):
        """REALISM.md §2.16: the technician's readings call for the terminals under the loose terminal only and for
        the trim under the drift only; either cause is fixed (`cpt2_sound`) only with the transmitter left sound: no
        sensor error beyond 0.3 kPa (the job's trim, or a trim to the tapping's true pressure), the terminals tight,
        the wires landed, the cover on. The other cause's fix alone, or the right fix with a wrong trim, is not."""
        def at(**states):
            e = self.engine()
            e.step(2)
            self.put(e, **states)
            e.step(2)
            return {k: self.val(e, k) for k in ('cpt2_loop_low', 'cpt2_pv_low', 'cpt2_sound')}
        self.assertEqual(at(), {'cpt2_loop_low': 0, 'cpt2_pv_low': 0, 'cpt2_sound': 1})
        self.assertEqual(at(cond_p2_drift=-1.5), {'cpt2_loop_low': 0, 'cpt2_pv_low': 1, 'cpt2_sound': 0})
        self.assertEqual(at(cpt2_terminal_block_loose=1), {'cpt2_loop_low': 1, 'cpt2_pv_low': 0, 'cpt2_sound': 0})
        for trim in (train_hands.TRIM, 1.4, 1.75):
            self.assertEqual(at(cond_p2_drift=-1.5, cond_p2_trim=trim)['cpt2_sound'], 1, trim)
        for trim in (0.5, 1.15, 1.85):
            self.assertEqual(at(cond_p2_drift=-1.5, cond_p2_trim=trim)['cpt2_sound'], 0, trim)
        # the loose terminal's fix with a wrong trim (the review's case), or either fix with the loop or cover left open
        for bad in ({'cond_p2_trim': -5}, {'cond_p2_trim': 1.5}, {'cpt2_terminal_block_lift': 1},
                    {'cpt2_cover_back_off': 1}):
            self.assertEqual(at(**bad)['cpt2_sound'], 0, bad)
        self.assertEqual(at(cond_p2_drift=-1.5, cond_p2_trim=1.5, cpt2_terminal_block_lift=1)['cpt2_sound'], 0)

    def test_the_jobs_choices_skip_to_after_their_fix(self):
        """Each `wait` that decides on a fix skips, on its `else`, to the step right after that fix."""
        steps = train_hands.job_steps()
        waits = [(i, s['wait']) for i, s in enumerate(steps) if 'wait' in s and 'else' in s['wait']]
        self.assertEqual([w['until'] for _, w in waits], ['cpt2_loop_low', 'cpt2_pv_low'])
        for (i, w), fix in zip(waits, ('hand', 'op')):
            self.assertIn(fix, steps[i + 1])
            self.assertEqual(w['else'], i + 2)
        self.assertEqual(steps[waits[0][0] + 1]['hand'], 'tighten_terms')
        self.assertEqual(steps[waits[1][0] + 1]['op']['value'], 1.5)
        self.assertEqual({c['id']: c['fixed'] for c in train_hands.FAULT['causes']},
                         {'drift': 'cpt2_sound', 'loose': 'cpt2_sound'})
        reads = [x for x in steps if 'read' in x]
        self.assertTrue(reads and all(x.get('tol') == train_hands.TOL for x in reads), reads)


class JobForks(unittest.TestCase):
    """REALISM.md §2.16 in the day's vectors (plant3d-v2.json, the forks npc_hands and npc_hands_drift): the NPC's
    job makes only the fix its readings call for, and its done repairs the fault."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v2.json'), encoding='utf-8') as f:
            cls.forks = {x['id']: x for x in json.load(f)['day']['forks']}

    def fixes(self, fork):
        ev = self.forks[fork]['events']
        hands = [x[3] for x in ev if x[1] == 'hand' and x[2] == CP2 and x[6] == 'done']
        trims = [x for x in ev if x[1] == 'op' and x[2] == CP2 and x[3] == 'set' and x[4] == 'done']
        return 'tighten_terms' in hands, len(trims), [x[0] for x in ev if x[1] == 'repair' and x[2] == 'cond_p2_low']

    def test_loose_terminal_tightened_not_trimmed(self):
        tightened, trims, repairs = self.fixes('npc_hands')
        self.assertEqual((tightened, trims, len(repairs)), (True, 0, 1))

    def test_drift_trimmed_not_tightened(self):
        tightened, trims, repairs = self.fixes('npc_hands_drift')
        self.assertEqual((tightened, trims, len(repairs)), (False, 1, 1))


class HiddenCauseJob(unittest.TestCase):
    """The fault with its two causes in every scenario of the first train, the work that repairs it."""

    def test_fault_in_every_train_scenario(self):
        F = files()
        for rel in sorted(F):
            if rel.startswith('scenarios/'):
                faults = {f['id']: f for f in jload(F, rel).get('faults', [])}
                if 'cond_p2_drift' in faults:
                    f = faults['cond_p2_low']
                    self.assertEqual([c['id'] for c in f['causes']], ['drift', 'loose'])
                    self.assertEqual(f['kks'], CP2)

    def test_instructors_cause_and_the_works_repair(self):
        """The instructor names the cause (no draw): its states are set; the trainer's repair writes the fault's and
        the cause's repair (REALISM.md §2.6)."""
        b = P.check_files(files())
        e = P.Engine(b, 'cold_iron')
        e.step()
        e.fault_cause('cond_p2_low', 'loose')
        e.step()
        ix = b.model.index
        self.assertEqual(e.cur[ix['cpt2_terminal_block_loose']], 1)
        self.assertEqual(e.cur[ix['cond_p2_low']], 1)
        self.assertIn(['cause', 'cond_p2_low', 'loose'], [x[1:4] for x in e.events if x[1] == 'cause'])
        e.repair('cond_p2_low')
        e.step()
        self.assertEqual(e.cur[ix['cpt2_terminal_block_loose']], 0)
        self.assertEqual(e.cur[ix['cond_p2_low']], 0)


if __name__ == '__main__':
    unittest.main()
