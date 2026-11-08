"""Milestone WX2 (docs/plant3d/REALISM.md §5.2, §5.7): the weather in the first train's model. The air's tables in
weather.json, the gas turbine's ambient, filter and fouling tables against their public sources, the faults the weather
makes with the works that repair them, the offline wash's procedure run in the reference engine, and the scenarios'
ages of the new items. What the plant does in the weather (a sandstorm with and without pulse cleaning, the washes, a
frosty night, a thunderstorm) is in plant3d-v1.json's forks `wx_*`, checked with every fork by tests/test_plant3d.py
and replayed by the GDScript engine."""
import json, os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))

from ref import plant3d as P  # noqa: E402
import train_weather as W  # noqa: E402
import train_wx as X  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')


def load(rel):
    with open(os.path.join(DATA, rel), encoding='utf-8') as f:
        return json.load(f)


def at(table, x):
    return P.table_at([[float(a), float(b)] for a, b in table], x)


class Air(unittest.TestCase):
    def test_air_appended_after_the_drawn_values(self):
        """WX3's seven driven values keep their places; the air's two follow, each with the same lag."""
        wx = load('weather.json')
        ids = [v['id'] for v in wx['values']]
        self.assertEqual(ids, ['wind', 'rain', 'dust', 'visibility', 'solar', 'lightning', 'wet', 'ambient_t',
                               'ambient_wb'])
        taus = {v['id']: v['tau'] for v in wx['values']}
        self.assertEqual(taus['ambient_t'], taus['ambient_wb'])

    def test_wet_bulb_never_above_dry_bulb(self):
        """Every kind's wet bulb at or below its dry bulb at every quarter hour (and both lag alike, so a change of
        kind keeps it so); summer's hot day at 06:00 within a kelvin of the cold start's 35/25."""
        for k in load('weather.json')['kinds']:
            t, wb = k['targets']['ambient_t'], k['targets']['ambient_wb']
            for q in range(97):
                self.assertLessEqual(at(wb, q / 4), at(t, q / 4) + 1e-9, (k['id'], q / 4))
        hot = W.K['hot']
        self.assertAlmostEqual(at(hot['ambient_t'], 6), 35, delta=1)
        self.assertAlmostEqual(at(hot['ambient_wb'], 6), 25, delta=1)

    def test_frost_only_on_cold_nights(self):
        """Only the cold clear night goes below 0 °C (the frozen line, ice on the fans): no kind of the hot months."""
        for k, d in W.K.items():
            low = min(at(d['ambient_t'], q / 4) for q in range(97))
            self.assertEqual(low < 0, k == 'cold_clear', k)


class GasTurbine(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        gt = load('model/gt1.json')
        cls.v = dict(gt['values'])

    def test_rating_at_35_and_the_slope_of_GER3567(self):
        """250 MW at 35 °C (FIRST-TRAIN), clean; between 25 and 45 °C the output falls 0.5-0.9 % of the ISO output a
        kelvin, and the heat rate rises (GER-3567's heavy-duty curve)."""
        out = self.v['gt1_amb_f']['table']
        self.assertEqual(at(out, 35), 1.0)
        iso = at(out, 15)
        for t in range(25, 45):
            fall = (at(out, t) - at(out, t + 1)) / iso
            self.assertTrue(0.005 <= fall <= 0.009, (t, fall))
            self.assertGreater(at(self.v['gt1_hr_amb']['table'], t + 1), at(self.v['gt1_hr_amb']['table'], t))
        self.assertEqual(self.v['gt1_cap']['product'][0], 250)

    def test_inlet_pressure_drop_costs_as_GER3567(self):
        """10 mbar more pressure drop: 1.42 % of output, 0.45 % of heat rate; nothing at the clean drop."""
        out, hr = self.v['gt1_dp_f']['table'], self.v['gt1_hr_dp']['table']
        self.assertEqual(at(out, X.DP_CLEAN), 1.0)
        self.assertEqual(at(hr, X.DP_CLEAN), 1.0)
        self.assertAlmostEqual(at(out, X.DP_CLEAN) - at(out, X.DP_CLEAN + 10), 0.0142, places=4)
        self.assertAlmostEqual(at(hr, X.DP_CLEAN + 10) - at(hr, X.DP_CLEAN), 0.0045, places=4)

    def test_filter_settings_in_order(self):
        """Clean < pulse on demand < alarm < runback; the runback clears below the alarm; a full sandstorm's cake at
        full flow passes the alarm before the media's residue alone does."""
        self.assertTrue(X.DP_CLEAN < X.PULSE_AT < X.DP_H < X.DP_HH)
        self.assertTrue(X.PULSE_AT < X.DP_RESET < X.DP_H)
        self.assertGreater(X.DP_CLEAN + at(X.CAKE, 60), X.DP_HH)
        self.assertLess(X.DP_CLEAN + at(X.RESIDUE, 150), X.PULSE_AT)

    def test_fouling_within_GER3620(self):
        """What online washes leave levels off near 3 %; offline fouling reaches 3-5 % in a year of firing; dust and
        damp air foul faster."""
        self.assertAlmostEqual(1 - at(X.FOUL_ON, 800), 0.027, delta=0.005)
        self.assertTrue(0.03 <= 1 - at(X.FOUL_OFF, 6000) <= 0.05)
        self.assertGreater(at(X.F_DUST, 8), at(X.F_DUST, 0.2))
        self.assertGreater(at(X.F_DAMP, 0), at(X.F_DAMP, 12))

    def test_load_fraction_of_the_days_base_load(self):
        """The load fraction (exhaust, HRSG, fuel) reads the day's base load: 1/MW by table within 0.06 %."""
        for c in range(100, 251):
            self.assertAlmostEqual(at(X.INV_CAP, c) * c, 1, delta=0.0006)


class Faults(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.models = [load(f'model/{n}') for n in sorted(os.listdir(os.path.join(DATA, 'model')))]
        cls.works = {w['id']: w for m in cls.models for w in m.get('works', [])}
        cls.cold = load('scenarios/cold_iron.json')

    def test_each_fault_has_its_work(self):
        """The frozen line, the junction box's water (two hidden causes), the lightning surge and the pulse
        system's failure: each a scenario fault repaired by exactly one isolated work, which the supervisor's generic
        fault reaction asks for."""
        faults = {f['id']: f for f in self.cold['faults']}
        for fid, wid in X.fault_work().items():
            self.assertIn(fid, faults)
            self.assertEqual(self.works[wid]['repairs'], fid)
            self.assertIn('isolation', self.works[wid])
            self.assertEqual(sum(w.get('repairs') == fid for w in self.works.values()), 1, fid)
        self.assertEqual([c['id'] for c in faults['ct_fan7_ingress']['causes']], ['water', 'electronics'])
        for fid in ('ct_lvl_frozen', 'ct_fan7_ingress', 'ct_fan9_surge'):
            self.assertIn('when', faults[fid])
        self.assertNotIn('when', faults['gt1_pulse'])        # the trainer's
        st = load('staff.json')
        listed = [r for r in st['reactions'] if r['on'].get('fault') and r.get('work') == '$']
        self.assertTrue(set(X.fault_work()) <= set(listed[0]['on']['fault']))

    def test_renewals(self):
        """The cartridges' change renews the residue and the cake; the cabinet's filters theirs; the junction box's
        repair the rain it has taken."""
        self.assertEqual(self.works['wo_gt1_filters']['renews'], ['gt1_filt_res', 'gt1_filt_cake'])
        self.assertEqual(self.works['wo_gen1_cab']['renews'], ['gen1_cab_filt'])
        self.assertEqual(self.works['wo_ct_fan7_cy']['renews'], ['ct_jb7_rain'])


class Procedure(unittest.TestCase):
    def test_offline_wash_from_cold_iron(self):
        """The procedure runs in the reference engine: the oil and turning gear, then the wash, which ends in half
        an hour of model time with the compressor's fouling gone; a start is refused meanwhile."""
        b = P.check_dir(DATA)
        e, log = P.run_procedure(b, 'gt_wash_offline')
        ids = [s for s, _ in log]
        self.assertEqual(ids[-2:], ['wash', 'wash_done'])
        n = dict(log)
        self.assertAlmostEqual((n['wash_done'] - n['wash']) / 10, X.WASH_OFF_S, delta=1)
        self.assertEqual(e.v('gt1_foul_off'), 0)


class Ages(unittest.TestCase):
    def test_new_items_start_at_their_age(self):
        """The hot restart (two months on) and the ageing scenario (30 months) start the filters' residue, the
        fouling and the cabinet's filters at their months less their renewals; the cold start at none."""
        cold = load('scenarios/cold_iron.json')['init']
        hot = load('scenarios/hot_restart.json')['init']
        for wear, per_month, every in X.AGE_ITEMS:
            self.assertNotIn(wear, cold)
            self.assertAlmostEqual(hot.get(wear, 0), round((2 * per_month) % every, 3), places=3)
            self.assertLess(hot.get(wear, 0), every)


if __name__ == '__main__':
    unittest.main()
