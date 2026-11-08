"""Work orders in the first train's content (docs/plant3d/REALISM.md §7.1, §2.20, milestone WM1): every work coded,
workorders.json's history agreeing with the ageing scenario's wear, and the staff carrying a notified order."""
import json, os, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))
from ref import plant3d as P  # noqa: E402
import train_ageing as A  # noqa: E402
import train_workorders as WO  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')


def load(rel):
    with open(os.path.join(DATA, rel), encoding='utf-8') as f:
        return json.load(f)


class Content(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load('workorders.json')
        cls.works = [w for n in sorted(os.listdir(os.path.join(DATA, 'model')))
                     for w in load(f'model/{n}').get('works', [])]

    def test_every_work_is_coded(self):
        modes = {m['id'] for m in self.doc['modes']}
        for w in self.works:
            self.assertIn('codes', w, w['id'])
            self.assertGreater(w['hours'], 0, w['id'])
            self.assertTrue(set(w.get('finds', [])) <= modes, w['id'])
            if 'repairs' in w and w['discipline'] != 'civil':
                # a work that repairs a failure names what is found (its finds) and codes a failure mode
                self.assertIn('finds', w, w['id'])
                self.assertIn(w['codes'][0], w['finds'], w['id'])

    def test_a_finding_on_a_code_reaches_one_work(self):
        """§7.1: a notification is matched to its work by the code and the kind found: on any code, each kind its
        works find goes to a work (the first written for it)."""
        by_code = {}
        for w in self.works:
            by_code.setdefault(w['kks'], []).append(w)
        for code, ws in by_code.items():
            for m in {m for w in ws for m in w.get('finds', [])}:
                self.assertTrue(any(m in w.get('finds', []) for w in ws), (code, m))

    def test_history_agrees_with_the_ageing_scenario(self):
        """Each wear item's last renewal in the history is as long ago as the ageing scenario's starting wear says
        (its months since the overhaul less its whole lives: train_ageing.apply)."""
        sc = load('scenarios/shift_aged.json')
        init = sc['init']
        duty = {f'{p[0]}_brg_wear': (p[1], p[10]) for p in A.PUMPS}
        duty.update({f'ct_fan{i}_gbx_wear': (f'30PAD10AN{i:03d}', A.FAN_DUTY) for i in A.FANS})
        duty.update({f'cw_{x}_act_wear': (f'30PAC10AA10{k}', 1) for x, k in A.VALVES})
        for wear, (code, d) in duty.items():
            if wear not in init:
                continue
            work = next(w['id'] for w in self.works if wear in w.get('renews', []) and
                        w['id'].endswith(('_brg', '_gbx', '_act')))
            last = min(h['ago'] for h in self.doc['history'] if h.get('work') == work)
            months = init[wear] / (A.HOURS_A_MONTH * d)
            self.assertAlmostEqual(last, months * WO.DAYS_A_MONTH, delta=2, msg=wear)

class StaffCarryAnOrder(unittest.TestCase):
    """The day's staff plan a notified order and ask for its permit (train_staff.WO_REACTIONS); a notification by
    nobody changes nothing in the day (no earlier run moves)."""

    def test_notified_order_is_planned_and_its_permit_asked(self):
        b = P.check_dir(DATA)
        e = P.Engine(b, 'shift_aged')
        e.work_order('wo_ccw_a_brg', 'notify', None, ['vibration'])
        seen = set()
        while e.step_no < 2400 and 'request' not in seen:
            e.step()
            for x in e.events[e.ev_mark:]:
                if x[1] == 'wo' and x[2] == 'wo_ccw_a_brg' and x[5] == 'done':
                    seen.add(x[3])
                if x[1] == 'permit' and x[2] == 'wo_ccw_a_brg' and x[3] == 'request' and x[5] == 'done':
                    seen.add('request')
        self.assertTrue({'notify', 'plan', 'schedule', 'request'} <= seen, seen)
        self.assertEqual(e.wo['wo_ccw_a_brg'], 3)
        self.assertEqual(e.wo_rec['wo_ccw_a_brg'][4], 3)        # planned normal by the supervisor


if __name__ == '__main__':
    unittest.main()
