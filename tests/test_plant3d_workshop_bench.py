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
        # the steam pressure dropped under a running turbine: no stage above the first while the flow follows
        e.op('valve_l', 'set', 40)
        for _ in range(40):
            e.step()
            self.assertLessEqual(max(e.v(f'p{k}') for k in range(1, 9)), e.v('p_first') + 1e-9)

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
        # rolled again without the breaker's trip reset: refused (a breaker trip left latched would not open the
        # breaker at the next trip on load)
        e.repair('rub')
        self.go(e, 400)
        e.op('brg_f_upper', 'reset', None, 'trip_vib')
        self.go(e, 1)
        self.assertEqual(e.v('turbine_state'), 0)
        e.op('rotor', 'roll')
        self.go(e, 1)
        self.assertEqual(e.v('turbine_state'), 0, 'Roll refused while the breaker trip is latched')
        e.op('bench', 'reset', None, 'trip_breaker')
        self.go(e, 1)
        e.op('rotor', 'roll')
        self.go(e, 1)
        self.assertEqual(e.v('turbine_state'), 1)

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


class GasTurbine(unittest.TestCase):
    """The gas turbine's bench (WORKSHOP.md §6.7, K5b): made from the plant's own gt1 model, started by the plant's
    sequence, the air's pressure and temperature rising through the compressor's stages and the gas's falling through
    the turbine's, tripped by the plant's own trips."""

    @classmethod
    def setUpClass(cls):
        cls.b = P.check_dir(DATA)
        cls.bench = cls.b.bench['gas_turbine']
        with open(os.path.join(DATA, 'model', 'gt1.json'), encoding='utf-8') as f:
            cls.gt = json.load(f)
        with open(os.path.join(DATA, 'workshop', 'bench', 'gas_turbine.json'), encoding='utf-8') as f:
            cls.text = f.read()
        cls.file = json.loads(cls.text)
        comps = list(json.loads(open(os.path.join(DATA, 'workshop', 'gas_turbine.json'), encoding='utf-8').read())
                     ['components'])
        # the same file with the plant's 480 s purge cut to 10 s (the vectors' short_purge): the run-up in a test's time
        cls.short = B.check(B.loads(G.short_purge(cls.text)), comps, 'bench', None)

    def go(self, e, seconds):
        for _ in range(round(seconds * 10)):
            e.step()

    def to_fsnl(self):
        e = self.short.engine()
        e.op('rotor', 'start')
        for _ in range(4000):
            e.step()
            if e.v('turbine_state') == 7:
                return e
        self.fail('never reached full speed no load')

    def test_the_sequence_is_the_plants(self):
        """The machine, its trips and the taken values are the plant's own, renamed: none written by hand."""
        plant = {m['id']: m for m in self.gt['machines']}['gt1_start']
        mine = {m['id']: m for m in self.file['machines']}['turbine']
        self.assertEqual([s['id'] for s in mine['states']], [s['id'] for s in plant['states']])
        self.assertEqual(mine['commands'], plant['commands'])
        for a, b in zip(mine['states'], plant['states']):
            self.assertEqual(a.get('say'), b.get('say'))
            self.assertEqual(a.get('next', []), [[c.replace('gt1_', '', 1), to] for c, to in b.get('next', [])])
            self.assertEqual(a.get('set', {}), {k.replace('gt1_', '', 1): v for k, v in b.get('set', {}).items()})
        pv = {n: d for n, d in self.gt['values']}
        mv = {n: d for n, d in self.file['values']}
        for n in ('gt1_speed', 'gt1_purge_done', 'gt1_flame', 'gt1_exh_t', 'gt1_cpd', 'gt1_os', 'gt1_spread_hh'):
            want = json.loads(json.dumps({k: v for k, v in pv[n].items() if k != 'kks'}).replace('"gt1_', '"'))
            self.assertEqual(mv[n[4:]], want, n)
        trips = {t['id'] for t in self.file['trips']}
        self.assertEqual(trips, {'trip_lube', 'trip_flame', 'trip_exh', 'trip_spread', 'trip_os', 'trip_vib',
                                 'trip_surge', 'trip_oil_temp', 'trip_breaker'})
        for v in self.file['values']:      # nothing of the realism programme's (the filter's and fouling's wear)
            self.assertFalse(set(v[1]) & {'wear', 'draw', 'count', 'sample'}, v[0])

    def test_a_change_to_the_plant_is_a_change_to_the_bench(self):
        sys.path.insert(0, os.path.join(REPO, 'tools', 'plant3d'))
        from workshop import gas_turbine as W
        gt = json.loads(json.dumps(self.gt))
        for v in gt['values']:
            if v[0] == 'gt1_purge_done':
                v[1]['cmp'][2] = 300
        made = W.bench([gt])
        self.assertEqual({n: d for n, d in made['values']}['purge_done']['cmp'][2], 300)
        self.assertEqual(made['bind'], self.file['bind'])

    def test_the_tool_refuses(self):
        sys.path.insert(0, os.path.join(REPO, 'tools', 'plant3d'))
        from workshop import gas_turbine as W, make_bench as M
        src = W.bench_source()
        src['before'] = [v for v in src['before'] if v[0] != 'ccw_ok']
        with self.assertRaisesRegex(ValueError, 'neither taken nor defined by the bench: ccw_ok'):
            M.make(src, [self.gt])
        src = W.bench_source()
        del src['at']['10MBM10CB001']
        with self.assertRaisesRegex(ValueError, '10MBM10CB001 has no place on the bench'):
            M.make(src, [self.gt])
        src = W.bench_source()
        src['before'].append(['flame', {'state': 0}])
        with self.assertRaisesRegex(ValueError, 'flame is taken from the plant and defined by the bench too'):
            M.make(src, [self.gt])
        src = W.bench_source()
        src['alarms'] = src['alarms'] + ['gt1_no_alarm']
        with self.assertRaisesRegex(ValueError, 'no alarm'):
            M.make(src, [self.gt])

    def test_cranked_and_purged_by_the_plants_sequence(self):
        e = self.bench.engine()
        e.op('rotor', 'start')
        self.go(e, 60)
        self.assertEqual(e.v('turbine_state'), 2)                 # the HRSG purge at the cranking speed
        self.assertAlmostEqual(e.v('rpm'), 750, delta=5)
        self.assertEqual(e.v('sfc_on'), 1)
        self.assertEqual(e.v('flame'), 0)
        self.go(e, 420)                                           # (the purge began at the cranking speed, at 49 s)
        self.assertEqual(e.v('turbine_state'), 2, 'the plant\'s purge is 480 s')
        self.go(e, 80)
        self.assertEqual(e.v('turbine_state'), 3)

    def test_fired_and_run_up(self):
        e = self.to_fsnl()
        self.assertEqual(e.v('flame'), 1)
        self.assertEqual(e.v('sfc_on'), 0)
        self.assertGreater(e.v('fuel_flow'), 1)
        # the air: the stages' pressure rising to the discharge's, each stage's temperature above the last
        ps = [e.v('p_amb')] + [e.v(f'c_p{k}') for k in range(1, 9)]
        ts = [e.v('ambient_t')] + [e.v(f'c_t{k}') for k in range(1, 9)]
        for a, b in zip(ps, ps[1:]):
            self.assertLess(a, b)
        for a, b in zip(ts, ts[1:]):
            self.assertLess(a, b)
        self.assertAlmostEqual(e.v('c_p8'), e.v('cpd'), 6)
        # NASA's compressor relation at the discharge: T/T0 = 1 + (r^(0.4/1.4) - 1) / 0.87 (to the table's points)
        r = e.v('cpd')
        want = (e.v('ambient_t') + 273.15) * (1 + (r ** (0.4 / 1.4) - 1) / 0.87) - 273.15
        self.assertAlmostEqual(e.v('c_t8'), want, delta=4)
        # the gas: hottest at the first nozzles, falling stage by stage to the plant's exhaust temperature
        self.go(e, 120)
        gs = [e.v('tit')] + [e.v(f't_t{k}') for k in range(1, 4)]
        ps = [e.v('cpd')] + [e.v(f't_p{k}') for k in range(1, 4)]
        for a, b in zip(gs, gs[1:]):
            self.assertGreater(a, b)
        for a, b in zip(ps, ps[1:]):
            self.assertGreater(a, b)
        self.assertAlmostEqual(e.v('t_p3'), 1.0, 6)
        self.assertAlmostEqual(e.v('t_t3'), e.v('exh_t'), 6)       # the last stage is the plant's exhaust
        self.assertGreater(e.v('tit'), e.v('c_t8') + 300)

    def test_flame_out_trips(self):
        e = self.to_fsnl()
        e.fault('flameout')
        self.go(e, 3)
        self.assertEqual(e.v('trip_flame_latched'), 1)
        self.assertEqual(e.v('turbine_state'), 10)                # TRIPPED: fuel off
        self.go(e, 10)
        self.assertEqual(e.v('fuel_flow'), 0)
        self.assertEqual(e.v('flame_v'), 0)                       # the flame drawn (and heard) no more

    def ordered(self, e, where):
        """The gas path in order: the turbine inlet no colder than the first stage, each stage no colder than the next,
        the last stage the plant's exhaust temperature; the inlet no colder than the compressor's discharge."""
        ts = [e.v('tit')] + [e.v(f't_t{k}') for k in range(1, 4)]
        for a, b in zip(ts, ts[1:]):
            self.assertGreaterEqual(a, b - 1e-9, where)
        self.assertGreaterEqual(e.v('t_t3'), e.v('exh_t') - 1e-9, where)
        self.assertGreaterEqual(e.v('tit'), e.v('c_t8') - 1e-9, where)
        self.ordered_p(e, where)

    def ordered_p(self, e, where):
        """The pressures in order along the path at any discharge pressure, a surge's below 1 bar too: from the
        bellmouth through the compressor's stages to the discharge (each between its neighbours, the last the
        discharge itself), and from the discharge through the turbine's stages back to the bellmouth's."""
        cp = [e.v('p_amb')] + [e.v(f'c_p{k}') for k in range(1, 9)]
        tp = [e.v('cpd')] + [e.v(f't_p{k}') for k in range(1, 4)]
        self.assertAlmostEqual(e.v('c_p8'), e.v('cpd'), 9, where)
        self.assertAlmostEqual(e.v('t_p3'), e.v('p_amb'), 9, where)
        for xs in (cp, tp):
            up = all(a <= b + 1e-9 for a, b in zip(xs, xs[1:]))
            down = all(a >= b - 1e-9 for a, b in zip(xs, xs[1:]))
            self.assertTrue(up or down, f'{where}: {xs}')

    def test_a_surge_below_full_speed_keeps_the_pressures_in_order(self):
        """(The adversarial review of K5b: a surge at standstill took the discharge under 1 bar, below the stage
        tables' first point.)"""
        for when, steps in (('standstill', 0), ('crank', 100), ('purge', 600)):
            e = self.bench.engine()
            if steps:
                e.op('rotor', 'start')
            for _ in range(steps):
                e.step()
            e.fault('surge')
            for _ in range(30):
                e.step()
                self.ordered_p(e, f'a surge at {when}, step {e.step_no}')
            if when == 'standstill':
                self.assertLess(e.v('cpd'), 0.6)
        e = self.short.engine()           # and while it coasts to the ignition speed
        e.op('rotor', 'start')
        while e.v('turbine_state') != 3:
            e.step()
        e.fault('surge')
        for _ in range(30):
            e.step()
            self.ordered_p(e, f'a surge while it coasts, step {e.step_no}')

    def test_a_speed_bias_below_zero_holds_the_sequence(self):
        """The plant's model gives the speed bias (±1 %) no permissive, and the sequence's speed thresholds have
        less margin than that (WORKSHOP.md §6.7): pinned here, so that a change to the plant's model shows."""
        e = self.bench.engine()            # cranking: the SFC's 25 % less 1 % never reaches the 24.5 % it waits for
        e.op('rotor', 'start')
        e.op('brg1_housing', 'set', -0.01)
        self.go(e, 120)
        self.assertEqual(e.v('turbine_state'), 1)
        self.assertAlmostEqual(e.v('speed'), 0.24, 6)
        e.op('brg1_housing', 'set', 0)
        self.go(e, 5)
        self.assertEqual(e.v('turbine_state'), 2, 'moved back, it goes on to the purge')
        for bias, parked in ((-0.01, True), (-0.005, False)):
            e = self.short.engine()        # the run-up: full speed less the bias, against the 99.5 % it waits for
            e.op('rotor', 'start')
            while e.v('turbine_state') != 6:
                e.step()
            e.op('brg1_housing', 'set', bias)
            self.go(e, 120)
            self.assertEqual(e.v('turbine_state'), 6 if parked else 7, bias)
            self.assertAlmostEqual(e.v('speed'), 1 + bias, 6)

    def test_the_stages_stay_in_order_through_ignition_and_a_flame_out(self):
        """In the transients too (the review of K5b: a 2 s lag on the flame against the exhaust's 60 s drew the
        buckets colder than the exhaust for a minute after a trip)."""
        e = self.short.engine()
        e.op('rotor', 'start')
        lit = None
        for _ in range(4000):
            e.step()
            self.ordered(e, f'step {e.step_no}')
            if lit is None and e.v('flame') == 1:
                lit = e.step_no
            if e.v('turbine_state') == 7:
                break
        self.assertIsNotNone(lit)
        e.fault('flameout')
        for _ in range(900):                # the trip and 90 s of the coast-down
            e.step()
            self.ordered(e, f'after the flame-out, step {e.step_no}')
        self.assertEqual(e.v('turbine_state'), 10)
        self.assertAlmostEqual(e.v('t_t3'), e.v('exh_t'), 6)

    def test_tripped_on_load_opens_the_breaker(self):
        e = self.to_fsnl()
        e.op('bench', 'start')
        e.op('brg1_housing', 'set', 0.001)
        for _ in range(3000):
            e.step()
            if e.step_no % 5 == 0:
                e.op('bench', 'close_breaker')
            if e.v('brk_cmd') >= 0.5:
                break
        self.assertEqual(e.v('brk_cmd'), 1, 'synchronised')
        self.assertEqual(e.v('turbine_state'), 8)
        e.op('brg1_housing', 'set', 0)
        self.go(e, 20)
        e.fault('rub')
        self.go(e, 4)
        self.assertEqual(e.v('trip_vib_latched'), 1)
        self.assertEqual(e.v('brk_cmd'), 0)

    def test_overspeed_by_the_governor(self):
        e = self.to_fsnl()
        e.fault('governor')
        self.go(e, 40)
        self.assertEqual(e.v('trip_os_latched'), 1)

    def test_the_spread_and_surge_trip(self):
        for fault, trip in (('tc_fault', 'trip_spread_latched'), ('surge', 'trip_surge_latched'),
                            ('oil_leak', 'trip_lube_latched')):
            e = self.to_fsnl()
            e.fault(fault)
            self.go(e, 8)
            self.assertEqual(e.v(trip), 1, fault)
            self.assertEqual(e.v('turbine_state'), 10, fault)

    def test_the_dc_pump_takes_over(self):
        e = self.to_fsnl()
        e.fault('lube_pump')
        self.go(e, 30)
        self.assertEqual(e.v('ldc_cmd'), 1)                       # started by the plant's interlock
        self.assertEqual(e.v('any_trip'), 0)
        self.assertGreater(e.v('lube_p'), 1.8)

    def test_every_binding_reads_a_value_and_names_a_component(self):
        names = {v[0] for v in self.file['values']} | {m['id'] + '_state' for m in self.file['machines']}
        comps = set(json.loads(open(os.path.join(DATA, 'workshop', 'gas_turbine.json'), encoding='utf-8').read())
                    ['components'])
        for x in self.file['bind']:
            for k in ('of', 'heat', 'pressure', 'show', 'by'):
                if k in x:
                    self.assertIn(x[k], names, x)
            if 'at' in x:
                self.assertIn(x['at'], comps | {'bench'}, x)


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
