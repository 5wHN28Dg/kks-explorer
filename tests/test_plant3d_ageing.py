"""Milestone AG2 (docs/plant3d/REALISM.md §4, §2.18): the first train ages. The wear items' content
(tools/plant3d/train_ageing.py), the claim that keeps every earlier run's values (no sign before an item's P point
within the runs of the scenarios that teach operating), the ageing scenario's seed and months, an item failing on its
own in the reference engine with its signs before, and the generic reactions (PLANT3D §16.7) standing for the very
reactions they replace."""
import copy, json, math, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))

from ref import plant3d as P  # noqa: E402
from ref import plant3d_staff as S  # noqa: E402
from ref.plant3d_world import world_seed  # noqa: E402
import train_ageing as A  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')
# the longest clock time any run of the vectors covers from a scenario's start: the day (24 h) with its evening
# jump's night, with room to spare
RUN_HOURS = 30


def load(rel):
    with open(os.path.join(DATA, rel), encoding='utf-8') as f:
        return json.load(f)


def models():
    out = {}
    for name in os.listdir(os.path.join(DATA, 'model')):
        out[name[:-5]] = load(f'model/{name}')
    return out


class Content(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = models()
        cls.values = {k: n for m in cls.models.values() for k, n in m.get('values', [])}
        cls.works = {w['id']: w for m in cls.models.values() for w in m.get('works', [])}
        cls.cold = load('scenarios/cold_iron.json')

    def test_every_item_wears_fails_and_is_renewed(self):
        """Each item's wear is a wear node with a drawn life; each failure is a scenario fault with its `when`,
        repaired and renewed by exactly one work, which the supervisor's generic fault reaction asks for."""
        faults = {f['id']: f for f in self.cold['faults']}
        renewed = {n for w in self.works.values() for n in w.get('renews', [])}
        for wear, life, _ in A.items():
            self.assertIn('wear', self.values[wear], wear)
            self.assertIn(wear, renewed, f'{wear}: no work renews it')
            if life:
                self.assertIn('draw', self.values[life], life)
        for fid, wid in A.fault_work().items():
            self.assertIn('when', faults[fid], fid)
            self.assertEqual(self.works[wid]['repairs'], fid)
            self.assertIn('isolation', self.works[wid])
            self.assertTrue(set(self.works[wid]['renews']) & {w for w, _, _ in A.items()}, wid)
        st = load('staff.json')
        listed = [r for r in st['reactions'] if r['on'].get('fault') and r.get('work') == '$']
        self.assertTrue(any(set(A.fault_work()) <= set(r['on']['fault']) for r in listed))

    def test_the_drawn_and_the_worn_are_not_shown(self):
        """A trainee is never told a failure is coming (§4.3): wear, lives and margins carry no code, so no screen
        or card shows them; the signs do (vibration, bearing temperature, torque)."""
        for wear, life, _ in A.items():
            for n in (wear, life):
                if n:
                    self.assertNotIn('kks', self.values[n], n)
        for p in A.PUMPS:
            self.assertEqual(self.values[f'{p[0]}_vib']['kks'], p[2])
            self.assertEqual(self.values[f'{p[0]}_brg_t']['kks'], p[1])

    def test_life_tables(self):
        """Inverse Weibull tables, rising, never below the kind's floor, the floor above the P-F interval."""
        for kind, k in A.KINDS.items():
            t = A.life_table(kind)
            self.assertEqual([r[0] for r in t], A.ROWS)
            ys = [r[1] for r in t]
            self.assertEqual(ys, sorted(ys), kind)
            self.assertGreaterEqual(ys[0], k['floor'])
            self.assertGreater(k['floor'], k['pf'], kind)
            # the median as the Weibull's: eta (ln 2)^(1/beta)
            self.assertAlmostEqual(t[A.ROWS.index(0.5)][1], max(k['floor'], k['eta'] * math.log(2) ** (1 / k['beta'])),
                                   delta=1)

    def test_signs_feeding_earlier_values_wait_for_P(self):
        """The fans' gear reducers and transmitter 3's drift feed values the train had before AG2: 0 until the P
        point (a year for the drift), so a run that never reaches it keeps those values bit for bit."""
        for i in A.FANS:
            t = self.values[f'ct_fan{i}_gbx_x']['table']
            self.assertEqual(t[0], [-A.KINDS['gearbox']['pf'], 0])
            self.assertEqual(self.values[f'ct_fan{i}_vt']['product'][1], f'ct_fan{i}_vfs')
        self.assertEqual(self.values['cond_p3_age_mag']['table'][0], [A.DRIFT_FROM, 0])
        self.assertIn('cond_p3_age', self.values['cond_p3_tx']['sum'])

    def test_earlier_scenarios_reach_no_P_point_in_their_runs(self):
        """Every scenario but the ageing one starts each item (its age by its duty) below its P point by more than
        the training rate's wear over RUN_HOURS at full duty, for its own seed's drawn lives: so no sign, alarm or
        failure of an item comes in any of the vectors' runs, whose earlier values stay as they were."""
        for name in sorted(os.listdir(os.path.join(DATA, 'scenarios'))):
            sc = load(f'scenarios/{name}')
            if sc['id'] == 'shift_aged':
                continue
            seed = world_seed(sc)
            rate = sc['init']['age_rate']
            for wear, life, _ in A.items():
                start = sc['init'].get(wear, 0)
                if life:
                    kind = next(k for k, pre in (('bearing', '_brg_'), ('relay', '_rly_'), ('gearbox', '_gbx_'),
                                                 ('actuator', '_act_')) if pre in life)
                    p_point = A.life_of(seed, life) - A.KINDS[kind]['pf']
                else:
                    p_point = A.DRIFT_FROM
                self.assertLess(start + rate * RUN_HOURS, p_point, f'{sc["id"]}: {wear}')

    def test_ageing_scenario(self):
        """shift_aged: 30 months, its seed's lives; closed cooling water pump A (running) within its P-F interval
        and failing within the day shift's first hours at the training rate; nothing else shows a sign at the start or
        fails in the day's first 20 clock hours."""
        sc = load('scenarios/shift_aged.json')
        self.assertEqual(sc['world']['age'], {'months': A.AGED_MONTHS})
        self.assertEqual(sc['init']['age_rate'], A.RATES['shift_aged'])
        self.assertEqual(sc['init']['ccw_a_cmd'], 1)
        seed = world_seed(sc)
        left = {}
        for wear, life, duty in A.items():
            if life:
                left[wear] = A.life_of(seed, life) - sc['init'].get(wear, 0)
                self.assertGreater(left[wear], 0, wear)        # an item past its life was renewed meanwhile
        hours = left['ccw_a_brg_wear'] / sc['init']['age_rate']
        self.assertLess(left['ccw_a_brg_wear'], A.KINDS['bearing']['pf'])
        self.assertTrue(2 < hours < 5, hours)
        for wear, x in left.items():
            if wear != 'ccw_a_brg_wear':
                kind = next(k for k, pre in (('bearing', '_brg_'), ('relay', '_rly_'), ('gearbox', '_gbx_'),
                                             ('actuator', '_act_')) if pre in wear)
                # no sign at the start; an item that wears by the calendar (the others stand still) fails no sooner
                # than 20 clock hours on (CW valve B's actuator shows its torque from about 14:30, a sign of its own)
                self.assertGreater(x, A.KINDS[kind]['pf'], wear)
                if kind == 'actuator':
                    self.assertGreater(x, sc['init']['age_rate'] * 20, wear)

    def test_age_renews_what_failed(self):
        """apply(): months by duty, less every whole life the months passed (renewed meanwhile)."""
        sc = {'id': 'x', 'init': {}, 'world': {'seed': 663}}
        A.AGES['x'] = 30
        try:
            A.apply(sc)
        finally:
            del A.AGES['x']
        self.assertEqual(sc['world']['age'], {'months': 30})
        self.assertEqual(sc['init']['age_rate'], A.RATE)
        for wear, life, duty in A.items():
            h = 30 * A.HOURS_A_MONTH * duty
            if life:
                h = math.fmod(h, A.life_of(663, life))
            self.assertAlmostEqual(sc['init'].get(wear, 0), round(h, 3), places=3)


class FailsOnItsOwn(unittest.TestCase):
    def test_bearing_signs_then_failure(self):
        """The ageing scenario with pump A's bearing 75 h of wear from its end (15 clock minutes at 300): its
        vibration rises past the zone C/D alarm, its noise and heat with it, then the fault comes by itself, the
        motor trips and the standby starts."""
        files = P.load_dir(DATA)
        sc = json.loads(files['scenarios/shift_aged.json'])
        life = A.life_of(world_seed(sc), 'ccw_a_brg_life')
        sc['init']['ccw_a_brg_wear'] = life - 75
        files['scenarios/shift_aged.json'] = json.dumps(sc).encode()
        e = P.Engine(P.check_files(files), 'shift_aged')
        vib0 = None
        made = None
        while e.step_no < 3000 and made is None:
            e.step()
            if e.step_no == 10:
                vib0 = e.v('ccw_a_vib')
            if any(x[1] == 'fault' and x[2] == 'ccw_a_brg' for x in e.events):
                made = e.step_no
        self.assertIsNotNone(made, 'the bearing never failed')
        self.assertGreater(vib0, A.ZONES[2]['cd'] * 0.75)
        ev = e.events
        self.assertTrue(any(x[1] == 'alarm' and x[2] == 'ccw_a_vib_high' and x[3] == 'active_unack' for x in ev))
        # 75 h at 300 an hour of clock, 0.6 clock seconds a step: 1500 steps
        self.assertAlmostEqual(made, 1500, delta=3)
        for _ in range(20):
            e.step()
        self.assertEqual(e.v('ccw_a_fault'), 1)
        self.assertTrue(any(x[1] == 'trip' and x[2] == 'ccw_a_trip' for x in e.events))
        self.assertTrue(any(x[1] == 'interlock' and x[2] == 'ccw_b_auto' for x in e.events))


class LateSigns(unittest.TestCase):
    def test_heat_alarm_before_the_failure(self):
        """The last of the bearing's signs, its heat, raises the 90 °C advisory alarm before the failure at the
        training rate 300 with the scenario's own air (the review's finding: the housing's lag kept it under 90)."""
        files = P.load_dir(DATA)
        sc = json.loads(files['scenarios/shift_aged.json'])
        sc['init']['ccw_a_brg_wear'] = A.life_of(world_seed(sc), 'ccw_a_brg_life') - 950
        files['scenarios/shift_aged.json'] = json.dumps(sc).encode()
        e = P.Engine(P.check_files(files), 'shift_aged')
        while e.step_no < 20000 and not any(x[1] == 'fault' and x[2] == 'ccw_a_brg' for x in e.events):
            e.step()
        heat = [x[0] for x in e.events if x[1] == 'alarm' and x[2] == 'ccw_a_brg_t_high' and x[3] == 'active_unack']
        made = next(x[0] for x in e.events if x[1] == 'fault' and x[2] == 'ccw_a_brg')
        self.assertTrue(heat and heat[0] < made, (heat, made))

    def test_staff_isolate_a_pump_whose_valve_actuator_failed(self):
        """A CW pump's protection trips by itself while its discharge valve's actuator has failed with the valve open:
        the field operator's lock task closes the valve by its handwheel (the motor's close does nothing) before the
        lock, so the permit is issued (the review's finding: the lock was refused and the job left for good)."""
        files = P.load_dir(DATA)
        sc = json.loads(files['scenarios/shift_aged.json'])
        sc['init'].update({'cw_a_v_cmd': 1, 'cw_a_v_pos': 1, 'cw_a_v_stuck': 1,
                           'cw_a_rly_wear': A.life_of(world_seed(sc), 'cw_a_rly_life') + 1})
        files['scenarios/shift_aged.json'] = json.dumps(sc).encode()
        e = P.Engine(P.check_files(files), 'shift_aged')
        while e.step_no < 30000 and e.pstate.get('wo_cw_a_rly', 0) < 4:
            e.step()
        ev = e.events
        self.assertTrue(any(x[1] == 'fault' and x[2] == 'cw_a_rly' for x in ev))
        self.assertTrue(any(x[1] == 'op' and x[2] == '30PAC10AA101' and x[3] == 'hand_close' and x[4] == 'done'
                            for x in ev), [x for x in ev if x[1] == 'op'][:10])
        self.assertGreaterEqual(e.pstate['wo_cw_a_rly'], 4, 'the permit was never issued')
        self.assertLessEqual(e.v('cw_a_v_pos'), 0.005)


class FanGearbox(unittest.TestCase):
    def test_gear_reducer_fails_before_the_trip(self):
        """A fan whose gear reducer is 50 h of wear from its end (10 clock minutes at 300): its vibration crosses the
        advisory 6.3 mm/s but stays under the fan's 10 mm/s trip until the gear reducer fails by itself, which trips
        the fan (the review's finding: a gear's vibration that reached the trip first stopped the fan, and its wear,
        before the failure could come)."""
        files = P.load_dir(DATA)
        sc = json.loads(files['scenarios/shift_aged.json'])
        sc['init']['ct_fan1_cmd'] = 1
        sc['init']['ct_fan1_gbx_wear'] = A.life_of(world_seed(sc), 'ct_fan1_gbx_life') - 50
        files['scenarios/shift_aged.json'] = json.dumps(sc).encode()
        e = P.Engine(P.check_files(files), 'shift_aged')
        made = None
        top = 0
        while e.step_no < 2000 and made is None:
            e.step()
            if any(x[1] == 'fault' and x[2] == 'ct_fan1_gbx' for x in e.events):
                made = e.step_no
            else:
                top = max(top, e.v('ct_fan1_vib'))
        self.assertIsNotNone(made, 'the gear reducer never failed')
        self.assertAlmostEqual(made, 1000, delta=3)
        self.assertTrue(6.3 < top < 10, top)
        self.assertFalse(any(x[1] == 'trip' and x[0] < made for x in e.events))
        self.assertTrue(any(x[1] == 'alarm' and x[2] == 'ct_fan1_vib_high' for x in e.events))
        for _ in range(100):
            e.step()
        self.assertTrue(any(x[1] == 'trip' and x[2] == 'ct_fan1_trip_vib' for x in e.events))


class GenericReactions(unittest.TestCase):
    def test_expansion(self):
        """A permit reaction giving a work's task stands for one per work naming it (the works' order), a list of
        faults with "work": "$" for one per fault with the work that repairs it; the rest stand for themselves."""
        works = [{'id': 'w1', 'repairs': 'f2', 'deisolate': 'd1'}, {'id': 'w2'}, {'id': 'w3', 'repairs': 'f1',
                                                                                 'deisolate': 'd3'}]
        rs = [{'on': {'alarm': 1}, 'roles': ['a'], 'task': 't'},
              {'on': {'fault': ['f1', 'f2']}, 'roles': ['s'], 'task': 'req', 'work': '$'},
              {'on': {'permit': 'returned'}, 'roles': ['s'], 'task': '$deisolate', 'priority': 2}]
        self.assertEqual(S.expand_reactions(rs, works), [
            rs[0],
            {'on': {'fault': 'f1'}, 'roles': ['s'], 'task': 'req', 'work': 'w3'},
            {'on': {'fault': 'f2'}, 'roles': ['s'], 'task': 'req', 'work': 'w1'},
            {'on': {'permit': 'returned'}, 'roles': ['s'], 'task': 'd1', 'work': 'w1', 'priority': 2},
            {'on': {'permit': 'returned'}, 'roles': ['s'], 'task': 'd3', 'work': 'w3', 'priority': 2}])

    def test_generic_run_is_the_first_run(self):
        """The vectors' staff run written generically (the last of plant3d-v2.json's staff runs) gives every input,
        event, state and digest of the first run, which writes the same reactions one by one."""
        with open(os.path.join(ROOT, 'ref', 'vectors', 'plant3d-v2.json'), encoding='utf-8') as f:
            runs = json.load(f)['staff']['runs']
        first, generic = runs[0], runs[-1]
        self.assertIn('generically', generic['why'])
        for k in ('inputs', 'until', 'events', 'states', 'digests'):
            self.assertEqual(first[k], generic[k], k)
        self.assertNotEqual(first['staff'], generic['staff'])

    def test_content_reactions_written_once(self):
        """The shipped staff file gives the permit's tasks by state once for every work, and asks for the permits
        of the faults' works in one reaction for the train and one for the water treatment plant."""
        st = load('staff.json')
        gen = [r for r in st['reactions'] if r['task'].startswith('$')]
        self.assertEqual(sorted(r['task'] for r in gen), ['$assign', '$deisolate', '$isolate'])
        self.assertFalse([r for r in st['reactions'] if 'permit' in r['on'] and r.get('work') and
                          r['task'].split('_')[0] in ('isolate', 'deisolate', 'assign')])
        self.assertEqual(len([r for r in st['reactions'] if r.get('work') == '$']), 2)
        self.assertLessEqual(len(st['tasks']), S.MAX['tasks'])
        self.assertEqual(S.MAX['tasks'], 800)


if __name__ == '__main__':
    unittest.main()
