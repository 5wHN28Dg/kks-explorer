"""The stores in the first train's content (docs/plant3d/REALISM.md §7.2, §2.23, milestone WM2): stores.json's parts
numbered after the manuals' spare parts lists (§6.2), their levels, the condenser transmitters' look-alike pair, the
storekeeper's reorder content, and the day's storekeeper ordering a part that reaches its reorder point."""
import copy, json, os, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))
from ref import plant3d as P  # noqa: E402
from ref import plant3d_service as SV  # noqa: E402
import manuals  # noqa: E402
import train_stores as TS  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')


def load(rel):
    with open(os.path.join(DATA, rel), encoding='utf-8') as f:
        return json.load(f)


def cell_text(cell):
    return ''.join(r.get('t', r.get('text', '')) if isinstance(r, dict) else str(r) for r in cell)


class Content(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load('stores.json')
        cls.parts = cls.doc['parts']
        content = manuals.load_content()
        cls.shorts = {}
        cls.listed = set()          # every number of every manual's spare parts list (§6.2)
        for src in manuals.sources():
            m = src.MANUAL
            cls.shorts[m['short']] = m
            rows = manuals.parts_table(m, content, m['id'])['table']['rows']
            cls.listed |= {cell_text(r[0]) for r in rows}

    def test_the_file_is_what_the_tool_makes(self):
        self.assertEqual(self.doc, TS.stores())

    def test_numbers_unique_and_after_the_manuals(self):
        """§6.2's rule: WDP-, a manual's short code, the catalogue id in capitals with - for _; each number on that
        manual's spare parts list, or a complete unit (UNIT-…) of the manual's kind."""
        nums = [p['number'] for p in self.parts]
        self.assertEqual(len(nums), len(set(nums)))
        for row in TS.PARTS:
            pid, short, cid = row[:3]
            n = next(p['number'] for p in self.parts if p['id'] == pid)
            self.assertIn(short, self.shorts, pid)
            self.assertEqual(n, manuals.part_number(self.shorts[short], cid), pid)
            if cid.startswith('unit_'):
                self.assertNotIn(n, self.listed, pid)      # (a whole unit, not a part of one)
            else:
                self.assertIn(n, self.listed, f'{pid}: {n} is on no manual\'s spare parts list')

    def test_levels(self):
        """Palmer's min/max levels: 0 ≤ min ≤ reorder < max ≤ 9,999, the stock above the reorder point (nothing is
        ordered until someone draws), a lead time of 1 to 365 days; the store is the counter, not self-service."""
        self.assertEqual(self.doc['stores'], [{'id': 'main', 'title': 'Main store', 'place': 'store_counter',
                                               'self_service': False}])
        for p in self.parts:
            self.assertTrue(0 <= p['min'] <= p['reorder'] < p['max'] <= 9999, p['id'])
            self.assertTrue(p['reorder'] < p['stock'] <= p['max'], p['id'])
            self.assertTrue(1 <= p['lead_days'] <= 365, p['id'])
            self.assertLessEqual(len(p['id']), 22)

    def test_the_condenser_transmitters_look_alike(self):
        """The complete condenser transmitter (range 3: its 0–120 kPa(a) inside the sensor's limit) and one of
        another range, each listing the other, the sentence naming the range code."""
        by = {p['id']: p for p in self.parts}
        a3, a4 = by['pt_unit_a3'], by['pt_unit_a4']
        self.assertEqual(a3['class'], a4['class'])
        self.assertEqual([x['part'] for x in a3['looks_like']], ['pt_unit_a4'])
        self.assertEqual([x['part'] for x in a4['looks_like']], ['pt_unit_a3'])
        self.assertIn('range code', a3['looks_like'][0]['differs'])
        for p in self.parts:
            for x in p.get('looks_like', []):
                self.assertIn(x['part'], by)

    def test_reorder_content(self):
        """Each part has its `<part>_low` node, a reorder task by the storekeeper and its reaction; the storekeeper
        holds issue_parts and order_parts, the maintenance supervisors order_parts; all after DC3's content."""
        st = load('staff.json')
        names = {v[0]: v[1] for v in load('model/admin.json')['values']}
        tasks = {t['id']: t for t in st['tasks']}
        reacts = {r['on'].get('value'): r for r in st['reactions'] if 'value' in r['on']}
        for p in self.parts:
            self.assertEqual(names[p['id'] + '_low'], {'cmp': [p['id'] + '_have', '<=', p['reorder']]})
            self.assertEqual(reacts[p['id'] + '_low']['roles'], ['store'])
            self.assertEqual(tasks[reacts[p['id'] + '_low']['task']]['steps'][-1], {'order': p['id']})
        roles = {r['id']: r for r in st['roles']}
        self.assertTrue({'issue_parts', 'order_parts'} <= set(roles['store']['authority']))
        self.assertIn('order_parts', roles['maint_sup']['authority'])
        self.assertTrue(st['tasks'][-1]['id'].startswith('reorder_'))
        self.assertTrue(st['reactions'][-1]['task'].startswith('reorder_'))


class StorekeeperReorders(unittest.TestCase):
    """The day's storekeeper, at the counter on a Monday morning, orders a part drawn down to its reorder point."""

    def test_reorder(self):
        b = P.check_dir(DATA)
        sc = copy.deepcopy(b.scenarios['shift_cold'])
        sc['start'] = {'day': 1, 'time': '07:30'}
        e = P.Engine(b, sc)
        w = 'wo_cond_p2_fix'
        e.work_order(w, 'notify', None, ['reading'])
        e.step(2)
        e.work_order(w, 'plan', None, [2])
        e.step()
        e.issue('pt_flange_orings', 6, w, None)       # 12 on the shelf, the reorder point 6
        e.step()
        self.assertIn('issue', [x[1] for x in e.events[e.ev_mark:]])
        self.assertEqual(e.v('pt_flange_orings_low'), 1.0)
        while e.step_no < 2000 and not any(x[1] == 'order' for x in e.events[e.ev_mark:]):
            e.step()
        o = next(x for x in e.events[e.ev_mark:] if x[1] == 'order')
        self.assertEqual(o[2:], ['pt_flange_orings', 10, 'store1', 'done', [], 'PO-0001'])     # up to the max, 16
        e.step()
        self.assertEqual(e.v('pt_flange_orings_low'), 0.0)
        self.assertEqual(e.v('pt_flange_orings_due'), 10.0)


class ServiceFilePart(unittest.TestCase):
    """A service file's action may name the stores' part it fits (§2.23): an identifier, looked up by the model."""

    def test_part_key(self):
        s = load('service/pressure_transmitter.json')
        w = load('workshop/pressure_transmitter.json')
        tools = {t['id'] for t in load('tools.json')['tools']}
        s2 = copy.deepcopy(s)
        s2['actions'][0]['part'] = 'pt_unit_a3'
        SV.check(s2, w, tools, 'service/pressure_transmitter.json')
        s2['actions'][0]['part'] = 'PT unit'
        with self.assertRaises(P.FormatError):
            SV.check(s2, w, tools, 'service/pressure_transmitter.json')


if __name__ == '__main__':
    unittest.main()
