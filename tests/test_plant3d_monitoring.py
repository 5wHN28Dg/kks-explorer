"""Milestone AG3 (docs/plant3d/REALISM.md §9.3, §2.19): condition monitoring in the first train. The content
(tools/plant3d/train_monitoring.py): the tools at the store counter, the collector's and camera's meters, the pump
bearings' outer race tone seen before the overall leaves ISO 20816-3's zone A/B, the oil sampling points with their
sample nodes; the monitoring file and its check (ref/plant3d_monitoring.py); an oil sample taken in the reference
engine by a mechanical technician and its results 48 clock hours later with the lab's spread; the authority."""
import copy, json, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))

from ref import plant3d as P  # noqa: E402
from ref import plant3d_monitoring as MO  # noqa: E402
from ref.courses import FormatError, table_at  # noqa: E402
from ref.plant3d_world import TAGS, stream, world_seed  # noqa: E402
from ref.plant3d_staff import draw  # noqa: E402
import train_ageing as A  # noqa: E402
import train_monitoring as T  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')


def load(rel):
    with open(os.path.join(DATA, rel), encoding='utf-8') as f:
        return json.load(f)


class Content(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = P.load_dir(DATA)
        cls.b = P.check_files(cls.files)
        ms = [load(f'model/{n}') for n in os.listdir(os.path.join(DATA, 'model'))]
        cls.values = {k: n for m in ms for k, n in m.get('values', [])}
        cls.meters = {x['id']: x for m in ms for x in m.get('meters', [])}
        cls.hands = {(x['kks'], x['action']): x for m in ms for x in m.get('hands', [])}
        cls.mon = load('monitoring.json')

    def test_tools_at_the_store(self):
        tools = {t['id']: t for t in load('tools.json')['tools']}
        self.assertEqual(tools['vib_dc']['kind'], 'collector')
        self.assertEqual(tools['vib_dc']['modes'], ['vel'])
        self.assertEqual(tools['ir_cam']['kind'], 'camera')
        self.assertEqual(tools['ir_cam']['modes'], ['ir'])
        self.assertEqual(tools['oil_kit']['kind'], 'sampler')
        self.assertEqual(tools['oil_kit']['at'], [['store_counter', 2]])
        roles = {r['id']: r for r in load('staff.json')['roles']}
        self.assertIn('sample', roles['mech_tech']['authority'])

    def test_meters(self):
        """The collector at every pump's and fan's vibration probe (the probe's value), the camera at every pump
        motor (its bearing temperature)."""
        for p, code, cy, *_ in A.PUMPS:
            self.assertEqual(self.meters[f'{p}_vel'], {'id': f'{p}_vel', 'kks': cy, 'point': 'brg',
                                                       'tool_kind': 'collector', 'mode': 'vel', 'value': f'{p}_vib'})
            self.assertEqual(self.meters[f'{p}_ir']['kks'], code)
            self.assertEqual(self.meters[f'{p}_ir']['value'], f'{p}_brg_t')
            self.assertEqual(self.meters[f'{p}_ir']['tool_kind'], 'camera')
        for i in A.FANS:
            x = self.meters[f'ct_fan{i}_vel']
            self.assertEqual((x['kks'], x['value'], x['tool_kind']), (f'30PAD10CY{i:03d}', f'ct_fan{i}_vib', 'collector'))

    def test_tone_seen_before_zone_AB_is_left(self):
        """§4.2's order: the outer race tone is 0 below the bearing's P point and well above the spectrum's noise
        floor (4 times) by the time the overall leaves zone A/B; and it never carries more than the overall."""
        pf = A.KINDS['bearing']['pf']
        for p, *_r in A.PUMPS:
            group = _r[8]
            vib = self.values[f'{p}_vib_k']['table']
            tone = self.values[f'{p}_bt_k']['table']
            self.assertEqual(table_at(tone, -pf - 1), 0)
            ab = T.ZONE_LIMITS[group][0]
            x = -pf
            while table_at(vib, x) <= ab:
                x += 1
            self.assertGreater(x, -pf + 50, p)                              # zone A/B is left well after P
            self.assertGreaterEqual(table_at(tone, x), 4 * T.FLOOR, p)
            for y in range(-pf, 1, 50):
                self.assertLess(table_at(tone, y), table_at(vib, y), (p, y))
            self.assertEqual(self.values[f'{p}_bt']['product'][1], f'{p}_bt_k')    # times the running speed

    def test_oil_points(self):
        """Each oil point's sampling hand action (ten minutes, the kit, no permit) takes its four sample nodes, each
        with a small spread and the lab's 48 hours; the truth of the iron and the particles rises with the margin."""
        pts = T.oil_points()
        self.assertEqual(len(pts), 13)
        for p, code, kind, mgn, _, _ in pts:
            h = self.hands[(code, 'take_oil')]
            self.assertEqual((h['tools'], h['minutes'], h['work']), (['oil_kit'], 10, False))
            self.assertEqual(h['samples'], [f'{p}_lab_{k}' for k, _, _ in T.RESULTS])
            for nd in h['samples']:
                n = self.values[nd]
                self.assertEqual(n['hours'], 48)
                self.assertEqual(n['spread'][2], [0.5, 0])
            for k in ('fe', 'pc'):
                t = self.values[f'{p}_oil_{k}']
                self.assertEqual(t['of'], mgn)
                ys = [r[1] for r in t['table']]
                self.assertEqual(ys, sorted(ys))
            o = T.OIL[kind]
            self.assertEqual(self.values[f'{p}_lab_visc']['sample'], o['visc'])
            # a sound item's oil within the alert limits, one at its end beyond the alarm
            lim = o['limits']
            self.assertLess(o['fe'][0][1], lim['fe'][0])
            self.assertGreater(o['fe'][-1][1], lim['fe'][1])
            self.assertLess(o['pc'][0][1], lim['pc'][0])
            self.assertGreater(o['pc'][-1][1], lim['pc'][1])
            self.assertLess(lim['visc'][0][0], o['visc'] - o['spread']['visc'])
            self.assertGreater(lim['h2o'][0], o['water'] + o['spread']['h2o'])

    def test_monitoring_file(self):
        """Every pump and fan has its vibration point, every pump motor its camera point, every oil point its
        results; the file is made by the tool and passes its check."""
        self.assertEqual(self.mon, json.loads(json.dumps(T.monitoring())))
        kinds = [p['kind'] for p in self.mon['points']]
        self.assertEqual((kinds.count('vib'), kinds.count('ir'), kinds.count('oil')), (17, 7, 13))
        MO.check(self.mon, self.b)
        o = T.orders()
        self.assertAlmostEqual(o['bpfo'] + o['bpfi'], T.BALLS, places=2)
        self.assertAlmostEqual(o['ftf'] * T.BALLS, o['bpfo'], places=2)

    def test_thermal_picture(self):
        """The camera's picture (REALISM.md §9.3, K6): each pump's Workshop kind, the monitored bearing's housing and
        bearing at the meter's value (the spot), the frame and sound bearings at BRG_RISE over the air when running, what
        the water wets at the water's temperature; a running set's frame warmer than the air, its worn bearing the
        hottest."""
        for p in self.mon['points']:
            if p['kind'] != 'ir':
                continue
            pic = p['picture']
            meter = self.b.model.meter_ix[p['meter']]['value']
            self.assertEqual(pic['parts'][pic['spot']], meter)
            self.assertEqual(self.b.model.p.equipment[p['code']]['part'], pic['kind'])
            hot = [c for c, v in pic['parts'].items() if v == meter]
            self.assertEqual(len(hot), 2, f'{p["code"]}: the housing and its bearing')
            self.assertTrue(all(c.startswith(('end_shield', 'bearing')) for c in hot), hot)
            pre = meter[:-len('_brg_t')]
            self.assertEqual(self.values[f'{pre}_warm_rise']['product'][1], A.BRG_RISE)
            self.assertEqual(self.values[f'{pre}_warm_rl']['tau'], A.BRG_TAU)
            self.assertEqual(pic['parts']['motor'], f'{pre}_warm_t')

    def test_check_refuses(self):
        def bad(change, code):
            d = copy.deepcopy(self.mon)
            change(d)
            with self.assertRaises(FormatError) as cm:
                MO.check(d, self.b)
            self.assertEqual(cm.exception.code, code)
        vib = next(i for i, p in enumerate(self.mon['points']) if p['kind'] == 'vib')
        ir = next(i for i, p in enumerate(self.mon['points']) if p['kind'] == 'ir')
        oil = next(i for i, p in enumerate(self.mon['points']) if p['kind'] == 'oil')
        bad(lambda d: d.update(format='x'), 'bad_value')
        bad(lambda d: d['points'][vib].update(meter='nope'), 'bad_ref')
        bad(lambda d: d['points'][vib].update(meter=self.mon['points'][ir]['meter']), 'bad_ref')
        bad(lambda d: d['points'][vib].update(zones=[2, 1, 3]), 'bad_number')
        bad(lambda d: d['points'][vib]['lines'][0].update(value='no_value'), 'bad_ref')
        bad(lambda d: d['points'][vib]['lines'][0].pop('share'), 'missing_key')
        bad(lambda d: d['points'][ir].update(limits=[90, 80]), 'bad_number')
        # the camera's picture (REALISM.md §9.3): the code's own kind, every component of its tree at a °C value, the
        # spot at the meter's value
        bad(lambda d: d['points'][ir]['picture'].update(kind='motor'), 'bad_ref')
        bad(lambda d: d['points'][ir]['picture']['parts'].pop('fan'), 'bad_ref')
        bad(lambda d: d['points'][ir]['picture']['parts'].update(impeller_9='ambient_t'), 'bad_ref')
        bad(lambda d: d['points'][ir]['picture']['parts'].update(fan='cw_a_vib'), 'bad_ref')
        bad(lambda d: d['points'][ir]['picture'].update(spot='nowhere'), 'bad_ref')
        bad(lambda d: d['points'][ir]['picture'].update(spot='fan'), 'bad_ref')
        bad(lambda d: d['points'][ir]['picture'].update(colour='iron'), 'unknown_key')
        bad(lambda d: d['points'][oil].update(action='open_cover'), 'bad_ref')
        bad(lambda d: d['points'][oil]['results'][0].update(node='cw_a_oil_fe'), 'bad_ref')
        bad(lambda d: d['points'][oil]['results'][0].update(alert=40), 'bad_number')
        bad(lambda d: d['points'][oil]['results'][2].update(alarm=[62, 80]), 'bad_number')
        bad(lambda d: d['points'][oil]['results'].pop(), 'bad_ref')
        bad(lambda d: d['points'][oil].update(hours=24), 'bad_ref')
        bad(lambda d: d['points'].append(copy.deepcopy(d['points'][vib])), 'dup_id')
        files = dict(self.files)
        d = copy.deepcopy(self.mon)
        d['points'][vib]['meter'] = 'nope'
        files['monitoring.json'] = json.dumps(d).encode()
        with self.assertRaises(FormatError):
            P.check_files(files)

    def test_budget(self):
        """§11: the tones count against the wear signs (AG2's 183 of 250), the oil results against the chemistry
        share (150)."""
        tones, oil = T.values_added()
        self.assertEqual((tones, oil), (35, 78))
        self.assertLessEqual(183 + tones, 250)
        self.assertLessEqual(oil, 150)
        added = [f'{p[0]}_{k}' for p in A.PUMPS for k in ('bt', 'bt_k', 'warm_rise', 'warm_rl', 'warm_t')] + \
            [f'{p}_{k}' for p, *_ in T.oil_points() for k in ['oil_fe', 'oil_pc'] + [f'lab_{r}' for r, _, _ in T.RESULTS]]
        self.assertEqual(len(set(added)), tones + oil)
        for k in added:
            self.assertIn(k, self.values)


def _engine(trainee, sid='shift_cold'):
    files = P.load_dir(DATA)
    sc = json.loads(files[f'scenarios/{sid}.json'])
    sc['staff']['trainee'] = trainee
    files[f'scenarios/{sid}.json'] = json.dumps(sc).encode()
    return P.Engine(P.check_files(files), sid), sc


class OilSample(unittest.TestCase):
    def test_sample_results_after_48_clock_hours(self):
        """A mechanical technician takes the kit at the store counter and samples CW pump A's motor oil (ten clock
        minutes); each result is the truth at the action's end plus the spread of the node's own lab stream's first
        draw, and comes 48 clock hours later (two nights jumped), not before."""
        e, sc = _engine('mech1')
        e.arrive('store_counter')
        e.step()
        e.tool('oil_kit', 1, 'mech1')
        e.step()
        e.leave('store_counter')
        e.arrive('w_30pac10ap001')
        e.step()
        e.hand('30PAC10AP001', 'take_oil', 'oil_kit', None, 'mech1')
        e.step()
        self.assertIn([4, 'hand', '30PAC10AP001', 'take_oil', 'oil_kit', 'mech1', 'start', []], e.events)
        while not any(x[1] == 'hand' and x[6] == 'done' for x in e.events):
            e.step()
        done = e.step_no
        end = e.clock()
        seed = world_seed(sc)
        nodes = [f'cw_a_lab_{k}' for k, _, _ in T.RESULTS]
        truth = {'cw_a_lab_fe': e.v('cw_a_oil_fe'), 'cw_a_lab_pc': e.v('cw_a_oil_pc'), 'cw_a_lab_visc': 68.0,
                 'cw_a_lab_h2o': 60.0}
        want = {}
        for nd in nodes:
            _, r = draw(stream(seed, TAGS['lab'], nd))
            n = next(x for x in e.m.values if x[0] == nd)[1]
            want[nd] = truth[nd] + float(table_at(n['spread'], r / 16777216.0))
            self.assertEqual(e.lab_q[nd], [[end + 48 * 36000, want[nd]]], nd)
        self.assertNotEqual(want['cw_a_lab_fe'], truth['cw_a_lab_fe'])
        for t in ('05:30', '05:30', '05:30'):
            self.assertFalse(any(x[1] == 'lab' for x in e.events))
            e.task_ack()
            e.step()
            e.jump(t)
            e.step(3)
        self.assertGreater(e.clock(), end + 48 * 36000)
        labs = [x for x in e.events if x[1] == 'lab']
        self.assertEqual([x[2] for x in labs], nodes)
        for x in labs:
            self.assertEqual(x[3], want[x[2]])
            self.assertEqual(e.v(x[2]), want[x[2]])
            self.assertGreater(x[0], done)

    def test_authority(self):
        """An I&C technician (operate_local, no sample) is refused a sampling hand action; the mechanical
        technician (sample) is not."""
        st = load('staff.json')
        ic = next(p['id'] for p in st['people'] if p['role'] == 'ic_tech')
        e, _ = _engine(ic)
        e.arrive('store_counter')
        e.step()
        e.tool('oil_kit', 1, ic)
        e.step()
        e.leave('store_counter')
        e.arrive('w_30pac10ap001')
        e.step()
        e.hand('30PAC10AP001', 'take_oil', 'oil_kit', None, ic)
        e.step()
        ev = [x for x in e.events if x[1] == 'hand']
        self.assertEqual(ev[-1][6:], ['refused', ['authority']])


class App(unittest.TestCase):
    """The app draws the monitoring file (ui/monitoring_view.gd): build.sh copies it with the content the app reads,
    and the view reads it from there; its UI test is in an app shard (apps/plant3d/tests/test_ui_monitoring.gd)."""

    def test_build_copies_the_monitoring_file(self):
        with open(os.path.join(ROOT, 'apps', 'plant3d', 'build.sh'), encoding='utf-8') as f:
            sh = f.read()
        self.assertIn('cp "$ROOT/data/plant3d/monitoring.json" "$HERE/built/content/"', sh)
        with open(os.path.join(ROOT, 'apps', 'plant3d', 'ui', 'monitoring_view.gd'), encoding='utf-8') as f:
            self.assertIn('const FILE := "res://built/content/monitoring.json"', f.read())
        self.assertTrue(os.path.exists(os.path.join(ROOT, 'apps', 'plant3d', 'tests', 'test_ui_monitoring.gd')))


if __name__ == '__main__':
    unittest.main()

