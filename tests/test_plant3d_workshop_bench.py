"""Walkdown Plant's Workshop bench models (docs/plant3d/WORKSHOP.md §6, milestone K3; ref/plant3d_bench.py): the
vector file is what ref/make_plant3d_bench_vectors.py makes, each valid file passes and each reject is refused with
its code, the committed transmitter's bench behaves as the 3051's manual says (4–20 mA over the range, NAMUR
saturation, a blocked impulse line holding, an open loop dead), and bench files are checked with the plant's content.
(The committed bench file being what tools/plant3d/make_content.py makes is test_plant3d's content check.)
  .venv/bin/python -m unittest tests.test_plant3d_workshop_bench"""
import json, os, subprocess, sys, unittest
from ref import plant3d as P
from ref import plant3d_bench as B
from ref import make_plant3d_bench_vectors as G
from ref.courses import FormatError

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DATA = os.path.join(REPO, 'data', 'plant3d')
VECTORS = os.path.join(REPO, 'ref', 'vectors', 'plant3d-bench-v1.json')


class BenchVectors(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(VECTORS, encoding='utf-8') as f:
            cls.V = json.load(f)

    def test_the_file_is_what_the_generator_makes(self):
        r = subprocess.run([sys.executable, os.path.join(REPO, 'ref', 'make_plant3d_bench_vectors.py')],
                           capture_output=True, text=True, cwd=REPO)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)

    def test_valid_and_reject(self):
        self.assertGreaterEqual(len(self.V['valid']), 2)
        for v in self.V['valid']:
            B.check(B.loads(v['bench']), v['components'], 'bench', None)
        self.assertGreaterEqual(len(self.V['reject']), 40)
        for r in self.V['reject']:
            with self.assertRaises(FormatError, msg=r['why']) as cm:
                B.check(B.loads(r['bench']), r['components'], 'bench', self.V['sounds'])
            self.assertEqual(cm.exception.code, r['code'], r['why'])

    def test_steps_replay(self):
        """The reference's run of each `steps` item, step by step, against the file (to its rounding)."""
        for s in self.V['steps']:
            states, events = G.run(s['bench'], s['components'], None, s['inputs'], len(s['states']) - 1)
            self.assertEqual(json.loads(G.dump(events)), s['events'], s['why'])
            self.assertEqual(json.loads(G.dump(states)), s['states'], s['why'])

    def test_every_committed_bench_has_a_run(self):
        parts = {json.loads(v['bench'])['part'] for v in self.V['steps']}
        for name in os.listdir(os.path.join(DATA, 'workshop', 'bench')):
            self.assertIn(name[:-5], parts)


class Turbine(unittest.TestCase):
    """The steam turbine's bench (WORKSHOP.md §6.3, K4b): made from the plant's own st model, its steam path's pressure
    and temperature falling stage by stage, the plant's start-up sequence and trips."""

    @classmethod
    def setUpClass(cls):
        cls.b = P.check_dir(DATA)
        cls.bench = cls.b.bench['steam_turbine']
        with open(os.path.join(DATA, 'model', 'st.json'), encoding='utf-8') as f:
            cls.st = json.load(f)
        with open(os.path.join(DATA, 'workshop', 'bench', 'steam_turbine.json'), encoding='utf-8') as f:
            cls.file = json.load(f)

    def go(self, e, seconds):
        for _ in range(round(seconds * 10)):
            e.step()

    def test_the_sequence_is_the_plants(self):
        """The machine, its trips and the taken values are the plant's own, renamed: none written by hand."""
        plant = {m['id']: m for m in self.st['machines']}['st_start']
        mine = {m['id']: m for m in self.file['machines']}['turbine']
        self.assertEqual([s['id'] for s in mine['states']], [s['id'] for s in plant['states']])
        self.assertEqual(mine['commands'], plant['commands'])
        for a, b in zip(mine['states'], plant['states']):
            self.assertEqual(a.get('say'), b.get('say'))
            self.assertEqual([c for c, _ in a.get('next', [])], [c.replace('st_', '', 1) for c, _ in b.get('next', [])])
        pv = {n: d for n, d in self.st['values']}
        mv = {n: d for n, d in self.file['values']}
        for n in ('st_speed', 'st_acc0', 'st_soak_done', 'st_vib_base', 'st_os'):
            want = json.loads(json.dumps({k: v for k, v in pv[n].items() if k != 'kks'}).replace('"st_', '"'))
            self.assertEqual(mv[n[3:]], want, n)
        trips = {t['id'] for t in self.file['trips']}
        self.assertEqual(trips, {'trip_lube', 'trip_os', 'trip_axial', 'trip_vib', 'trip_steam_t', 'trip_breaker'})

    def test_a_change_to_the_plant_is_a_change_to_the_bench(self):
        sys.path.insert(0, os.path.join(REPO, 'tools', 'plant3d'))
        from workshop import steam_turbine as W
        st = json.loads(json.dumps(self.st))
        for v in st['values']:
            if v[0] == 'st_soak_done':
                v[1]['cmp'][2] = 240
        made = W.bench([st])
        self.assertEqual({n: d for n, d in made['values']}['soak_done']['cmp'][2], 240)
        self.assertEqual(made['bind'], self.file['bind'])

    def test_the_tool_refuses(self):
        sys.path.insert(0, os.path.join(REPO, 'tools', 'plant3d'))
        from workshop import steam_turbine as W, make_bench as M
        src = W.bench_source()
        src['before'] = [v for v in src['before'] if v[0] != 'lube_p']
        with self.assertRaisesRegex(ValueError, 'neither taken nor defined by the bench: lube_p'):
            M.make(src, [self.st])
        src = W.bench_source()
        del src['at']['30MAD10CG001']
        with self.assertRaisesRegex(ValueError, '30MAD10CG001 has no place on the bench'):
            M.make(src, [self.st])
        src = W.bench_source()
        src['before'].append(['speed', {'state': 0}])
        with self.assertRaisesRegex(ValueError, 'speed is taken from the plant and defined by the bench too'):
            M.make(src, [self.st])
        src = W.bench_source()
        src['trips'] = src['trips'] + ['st_trip_none']
        with self.assertRaisesRegex(ValueError, 'no trip'):
            M.make(src, [self.st])

    def test_rolled_by_the_plants_sequence(self):
        e = self.bench.engine()
        e.op('rotor', 'roll')
        self.go(e, 90)
        self.assertEqual(e.v('turbine_state'), 2)                 # soaking at 800 rpm
        self.assertAlmostEqual(e.v('rpm'), 800, delta=5)
        self.assertGreater(e.v('stop_pos'), 0.99)                 # the stop valves wide open, the control valves throttling
        self.assertLess(e.v('ctrl_pos'), 0.1)

    def test_pressure_and_temperature_fall_along_the_path(self):
        e = self.bench.engine()
        e.op('rotor', 'roll')
        self.go(e, 120)
        ps = [e.v('p_first')] + [e.v(f'p{k}') for k in range(1, 9)]
        ts = [e.v('inlet_t')] + [e.v(f't{k}') for k in range(1, 9)]
        self.assertLess(e.v('p_first'), e.v('p_supply'))         # the control valves throttle
        for a, b in zip(ps, ps[1:]):
            self.assertGreater(a, b)
        for a, b in zip(ts, ts[1:]):
            self.assertGreater(a, b)
        # every stage's pressure in proportion to the flow: 90 bar after the control valves and 25 bar at the exhaust
        # (the cold reheat) at the full 70 kg/s
        f = e.v('flow') / 70
        self.assertAlmostEqual(e.v('p_first'), 90 * f, 6)
        self.assertAlmostEqual(e.v('p8'), 25 * f, 6)

    def test_tripped_on_load_opens_the_breaker(self):
        """A trip while on the grid: the plant's protection opens the breaker too, and the rotor coasts down."""
        e = self.bench.engine()
        e.op('rotor', 'roll')
        st = e.m.index
        for _ in range(9000):
            e.step()
            if e.v('spd95') >= 0.5 and e.v('exc_cmd') < 0.5:
                e.op('bench', 'start')
                e.op('pedestal_f', 'set', 0.002)
            if e.v('turbine_state') == 4 and e.step_no % 5 == 0:
                e.op('bench', 'close_breaker')
            if e.v('brk_cmd') >= 0.5:
                break
        self.assertEqual(e.v('brk_cmd'), 1, 'synchronised')
        e.op('pedestal_f', 'set', 0)
        self.go(e, 20)
        e.fault('rub')
        self.go(e, 4)
        self.assertEqual(e.v('trip_vib_latched'), 1)
        self.assertEqual(e.v('brk_cmd'), 0)
        self.go(e, 30)
        self.assertLess(e.v('rpm'), 2950)

    def test_overspeed_by_the_governor(self):
        e = self.bench.engine()
        e.op('rotor', 'roll')
        for _ in range(9000):
            e.step()
            if e.v('turbine_state') == 4:
                break
        e.fault('governor')
        self.go(e, 60)
        self.assertEqual(e.v('trip_os_latched'), 1)

    def test_thrust_wear_trips_and_is_renewed(self):
        e = self.bench.engine()
        e.op('rotor', 'roll')
        self.go(e, 10)
        e.fault('thrust_wear')
        self.go(e, 60)
        self.assertEqual(e.v('trip_axial_latched'), 1)
        e.repair('thrust_wear')
        self.go(e, 30)
        e.op('thrust_upper', 'reset', None, 'trip_axial')
        self.go(e, 1)
        self.assertEqual(e.v('trip_axial_latched'), 0)

    def test_tripped_by_a_rub(self):
        e = self.bench.engine()
        e.op('rotor', 'roll')
        self.go(e, 60)
        e.fault('rub')
        self.go(e, 4)
        self.assertEqual(e.v('trip_vib_latched'), 1)
        self.assertEqual(e.v('turbine_state'), 8)                 # TRIPPED: stop valves closed
        self.go(e, 1)
        self.assertLess(e.v('stop_pos'), 0.01)


class Transmitter(unittest.TestCase):
    """The transmitter's bench (WORKSHOP.md §6.4) as the sources say it behaves."""

    @classmethod
    def setUpClass(cls):
        cls.b = P.check_dir(DATA)
        cls.bench = cls.b.bench['pressure_transmitter']

    def go(self, e, seconds):
        for _ in range(round(seconds * 10)):
            e.step()

    def powered(self):
        e = self.bench.engine()
        e.op('terminal_block', 'start')
        self.go(e, 0.2)
        return e

    def test_four_to_twenty_milliamps_over_the_range(self):
        e = self.powered()
        for p, ma in ((0, 4.0), (2.5, 8.0), (5, 12.0), (10, 20.0)):
            e.op('process_flange', 'set', p)
            self.go(e, 8)
            self.assertAlmostEqual(e.v('loop_ma'), ma, 6, p)
            self.assertAlmostEqual(e.v('pv'), p, 6)
            self.assertAlmostEqual(e.v('x_dia'), p / 10, 6)     # the diaphragm's travel follows the pressure

    def test_damping_lags_the_output(self):
        """The output follows a step with the damping's time constant (0.4 s) after the line and the cell."""
        e = self.powered()
        e.op('process_flange', 'set', 10)
        self.go(e, 0.5)
        self.assertLess(e.v('loop_ma'), 16)
        self.go(e, 8)
        self.assertAlmostEqual(e.v('loop_ma'), 20, 4)

    def test_namur_saturation(self):
        e = self.powered()
        e.op('process_flange', 'set', 12)
        self.go(e, 8)
        self.assertEqual(e.v('loop_ma'), 20.5)
        self.assertEqual(e.astate['sat_high'], 'active_unack')
        self.assertGreater(e.v('x_dia'), 1.0)
        e.op('process_flange', 'set', -1)
        self.go(e, 8)
        self.assertEqual(e.v('loop_ma'), 3.8)
        self.assertEqual(e.astate['sat_low'], 'active_unack')

    def test_over_range_fault(self):
        e = self.powered()
        e.op('process_flange', 'set', 3)
        self.go(e, 5)
        e.fault('over_range')
        self.go(e, 5)
        self.assertEqual(e.v('loop_ma'), 20.5)
        e.repair('over_range')
        self.go(e, 8)
        self.assertAlmostEqual(e.v('loop_ma'), 4 + 16 * 0.3, 5)

    def test_blocked_impulse_line_holds(self):
        e = self.powered()
        e.op('process_flange', 'set', 6)
        self.go(e, 6)
        e.fault('impulse_blocked')
        self.go(e, 0.2)
        e.op('process_flange', 'set', 1)
        self.go(e, 6)
        self.assertAlmostEqual(e.v('pv'), 6, 4)                  # what was trapped
        self.assertAlmostEqual(e.v('flow_frac'), 0.0, 9)
        self.assertAlmostEqual(e.v('loop_ma'), 4 + 16 * 0.6, 4)
        e.repair('impulse_blocked')
        self.go(e, 6)
        self.assertAlmostEqual(e.v('pv'), 1, 4)

    def test_open_loop_dark(self):
        e = self.powered()
        e.op('process_flange', 'set', 5)
        self.go(e, 3)
        e.fault('loop_open')
        self.go(e, 0.3)
        self.assertEqual(e.v('loop_ma'), 0.0)
        self.assertEqual(e.v('lit'), 0.0)
        self.assertEqual(e.astate['loop_dead'], 'active_unack')

    def test_unpowered_is_dark_but_the_diaphragm_moves(self):
        e = self.bench.engine()
        e.op('process_flange', 'set', 5)
        self.go(e, 3)
        self.assertEqual(e.v('loop_ma'), 0.0)
        self.assertEqual(e.v('lit'), 0.0)
        self.assertAlmostEqual(e.v('x_dia'), 0.5, 4)

    def test_flow_runs_both_ways(self):
        e = self.powered()
        e.op('process_flange', 'set', 8)
        self.go(e, 0.2)
        self.assertGreater(e.v('flow_frac'), 0.1)               # into the transmitter while the pressure rises
        self.go(e, 6)
        e.op('process_flange', 'set', 0)
        self.go(e, 0.2)
        self.assertLess(e.v('flow_frac'), -0.1)                 # out while it falls

    def test_every_binding_reads_a_value_and_names_a_component(self):
        comps = set(json.loads(P.load_dir(DATA)['workshop/pressure_transmitter.json'])['components'])
        names = {v[0] for v in self.bench.b.model.values}
        for x in self.bench.bind:
            if 'flow' not in x:
                self.assertIn(x['at'], comps)
            for k in ('of', 'show', 'lit', 'pressure', 'heat', 'by'):
                if k in x:
                    self.assertIn(x[k], names, x)

    def test_bench_files_are_checked_with_the_plant(self):
        files = P.load_dir(DATA)
        d = json.loads(files['workshop/bench/pressure_transmitter.json'])
        d['bind'][0]['at'] = 'impeller'
        files['workshop/bench/pressure_transmitter.json'] = json.dumps(d).encode()
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'bad_ref')
        files = P.load_dir(DATA)
        files['workshop/bench/gadget.json'] = files['workshop/bench/pressure_transmitter.json']
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'bad_ref')


if __name__ == '__main__':
    unittest.main()
