"""Milestone DC3 (docs/plant3d/REALISM.md §6.3, §6.3.1): the first train's five discussions as content. The file is
what the generator makes, the five have their three roles, their evidence points at what exists (a DC2 manual's
section, a source key of §14, a value the model reads), every agreement's outcome changes the job (another work:
its method, isolation or tools), the valve packing isolates whatever is agreed, and each starts from a trigger in
the first train's scenarios."""
import json
import os
import re
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, 'tools', 'plant3d'))

from ref import plant3d as P  # noqa: E402
import make_content  # noqa: E402
import train_discussions as TD  # noqa: E402
from manual_texts import pressure_transmitter, valves, pumps, steam_turbine, control_valve, gas_turbine  # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')
IDS = ['cw_a_vib', 'cond_p2_cal', 'cw_a_pack', 'st_trip', 'ct_fan7_alarm']
MANUALS = {m.MANUAL['id']: {s['id'] for s in m.MANUAL['sections']}
           for m in (pressure_transmitter, valves, pumps, steam_turbine, control_valve, gas_turbine)}
STAFFED = ('shift_cold', 'shift_wtp', 'shift_aged')


def jload(F, rel):
    return json.loads(F[rel].decode())


def source_keys():
    """The keys of REALISM.md §14."""
    with open(os.path.join(ROOT, 'docs', 'plant3d', 'REALISM.md'), encoding='utf-8') as f:
        text = f.read()
    return set(re.findall(r'\[([A-Za-z0-9][A-Za-z0-9.-]*)\]', text[text.index('\n## 14. Sources'):]))


class Content(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.F = P.load_dir(DATA)
        cls.D = jload(cls.F, 'discussions.json')
        cls.by = {d['id']: d for d in cls.D['discussions']}
        cls.st = jload(cls.F, 'staff.json')
        cls.tasks = {t['id']: t for t in cls.st['tasks']}
        cls.works = {}
        cls.isos = {}
        cls.values = set()
        cls.codes = set()
        for rel in cls.F:
            if rel.startswith('model/'):
                m = jload(cls.F, rel)
                cls.works.update({w['id']: w for w in m.get('works', [])})
                cls.isos.update({x['id']: x for x in m.get('isolations', [])})
                cls.values.update(v[0] for v in m.get('values', []))
                cls.codes.update(v[1]['kks'] for v in m.get('values', []) if 'kks' in v[1])
                cls.codes.update(b['kks'] for b in m.get('bind', []) if 'kks' in b)

    def test_made_the_same_twice_and_on_disk(self):
        a, b = make_content.build(), make_content.build()
        self.assertEqual(a['discussions.json'], b['discussions.json'])
        self.assertEqual(a['discussions.json'].encode(), self.F['discussions.json'])
        self.assertEqual(a['staff.json'], b['staff.json'])

    def test_the_five_with_three_roles_lead_first(self):
        self.assertEqual(self.D['format'], 'walkdown-plant-discussion')
        self.assertEqual(self.D['version'], 1)
        self.assertEqual([d['id'] for d in self.D['discussions']], IDS)
        lead = {'cw_a_vib': 'maint_sup', 'cond_p2_cal': 'ic_eng', 'cw_a_pack': 'maint_sup', 'st_trip': 'shift_sup',
                'ct_fan7_alarm': 'shift_sup'}
        trainee = {'cw_a_vib': 'mech_eng', 'cond_p2_cal': 'ic_tech', 'cw_a_pack': 'mech_tech', 'st_trip': 'ccr_op',
                   'ct_fan7_alarm': 'ccr_op'}
        for d in self.D['discussions']:
            with self.subTest(d['id']):
                self.assertEqual(len(d['roles']), 3)
                self.assertEqual(len(set(d['roles'])), 3)
                self.assertEqual(d['roles'][0], lead[d['id']])
                self.assertEqual(d['roles'][2], trainee[d['id']])
                self.assertEqual([p['role'] for p in d['positions']], d['roles'])
                self.assertTrue(1 <= len(d['points']) <= 3)
                self.assertIn(d['topic'], self.works)

    def test_evidence_of_every_kind_points_at_what_exists(self):
        keys = source_keys()
        kinds = set()
        for d in self.D['discussions']:
            for v in d['evidence']:
                kinds.add(v['kind'])
                with self.subTest(d['id'], ev=v['id']):
                    self.assertTrue(1 <= len(v['text']) <= 200)
                    if v['kind'] == 'manual':
                        self.assertIn(v['section'], MANUALS[v['manual']])
                    elif v['kind'] == 'standard':
                        self.assertIn(v['cite'], keys)
                    elif v['kind'] == 'reading':
                        self.assertIn(v['value'], self.values)
                        self.assertIn(v['code'], self.codes)
            used = {e for p in d['positions'] for e in p['evidence']} | \
                {e for pt in d['points'] for o in pt['options'] for e in o.get('evidence', [])}
            self.assertLessEqual(used, {v['id'] for v in d['evidence']}, d['id'])
        self.assertEqual(kinds, {'manual', 'standard', 'reading', 'rule'})

    def test_spec_sources_cited(self):
        """Each discussion cites the sources §6.3.1 names for it."""
        want = {'cw_a_vib': {'ISO20816-3', 'Moubray'}, 'cond_p2_cal': {'R3051'}, 'cw_a_pack': {'FCVH'},
                'st_trip': {'DOE-RCA'}, 'ct_fan7_alarm': {'ISA182', 'MOC'}}
        manual = {'cond_p2_cal': 'pressure_transmitter', 'cw_a_pack': 'valves', 'st_trip': 'steam_turbine'}
        for did, cites in want.items():
            ev = self.by[did]['evidence']
            self.assertLessEqual(cites, {v['cite'] for v in ev if v['kind'] == 'standard'}, did)
            if did in manual:
                self.assertIn(manual[did], {v['manual'] for v in ev if v['kind'] == 'manual'}, did)

    def test_points_offer_a_side_a_reading_or_a_third_way(self):
        for d in self.D['discussions']:
            for pt in d['points']:
                with self.subTest(d['id'], point=pt['id']):
                    sides = {o.get('side') for o in pt['options']}
                    self.assertIn(pt['default'], [o['id'] for o in pt['options']])
                    self.assertTrue(sides & set(d['roles'][:2]))
            first = d['points'][0]
            self.assertTrue(any('side' not in o for o in first['options']), d['id'])   # a reading or a third way

    def outcome_works(self, task, seen=()):
        """The works an outcome task asks a permit for (through the tasks it calls too)."""
        out = []
        for s in self.tasks[task]['steps']:
            if 'permit' in s and s['permit']['action'] == 'request':
                out.append(s['permit']['work'])
            if 'call' in s and s['call']['task'] not in seen:
                out += self.outcome_works(s['call']['task'], seen + (task,))
        return out

    def method(self, wid):
        """What a work's job does: its isolation, its job's steps' work, tools and places."""
        w = self.works[wid]
        job = self.tasks[w['task']]['steps']
        return (w.get('isolation'), json.dumps([s for s in job if 'work' in s or 'tool' in s or 'go' in s]))

    def test_every_outcome_changes_the_job(self):
        for d in self.D['discussions']:
            with self.subTest(d['id']):
                tasks = []
                for a in d['agreements']:
                    t = a['outcome']['task']
                    self.assertIn(t, self.tasks)
                    if t not in tasks:
                        tasks.append(t)
                self.assertGreaterEqual(len(tasks), 2)
                works = {t: self.outcome_works(t) for t in tasks}
                for t, ws in works.items():
                    self.assertEqual(len(ws), 1, t)
                    self.assertIn(ws[0], self.works)
                methods = [self.method(ws[0]) for ws in works.values()]
                self.assertEqual(len(set(methods)), len(methods), works)
                self.assertEqual(len({ws[0] for ws in works.values()}), len(works))

    def test_the_valve_packing_isolates_in_every_outcome(self):
        d = self.by['cw_a_pack']
        for a in d['agreements']:
            for wid in self.outcome_works(a['outcome']['task']):
                iso = self.works[wid].get('isolation')
                self.assertIn(iso, self.isos, wid)
                kinds = {p['kind'] for p in self.isos[iso]['points']}
                self.assertEqual(kinds, {'electrical', 'mechanical'}, wid)
        # whatever the trainee argues (the live tightening, the sealant), an isolating outcome follows
        live = [a for a in d['agreements'] if not a['when'] or
                any(t.get('option') in ('live', 'sealant') for t in a['when'])]
        self.assertTrue(live)

    def test_every_repair_isolates_and_live_works_repair_nothing(self):
        for wid in TD.WORK_IDS:
            w = self.works[wid]
            with self.subTest(wid):
                if 'isolation' not in w:
                    self.assertNotIn('repairs', w)
                    self.assertNotIn('renews', w)
                    self.assertNotIn('isolate', w)
                else:
                    self.assertIn(w['isolate'], self.tasks)
                    self.assertIn(w['deisolate'], self.tasks)
                self.assertIn(w['task'], self.tasks)
                self.assertIn(w['assign'], self.tasks)
                self.assertIn('jsa', w)

    def test_lead_calls_the_joiners_and_nobody_is_interrupted(self):
        for d in self.D['discussions']:
            with self.subTest(d['id']):
                lead = self.tasks[f'dsc_{d["id"]}']
                self.assertIs(lead['interruptible'], False)
                self.assertEqual(lead['steps'][-1], {'discuss': d['id']})
                self.assertFalse(any('meet' in s for s in lead['steps']))     # (the discuss step is the meeting)
                called = [s['call'] for s in lead['steps'] if 'call' in s]
                self.assertEqual(lead['steps'][-1 - len(called):-1], [{'call': c} for c in called])
                self.assertEqual([c['role'] for c in called], d['roles'][1:])
                for c in called:
                    j = self.tasks[c['task']]
                    self.assertEqual(j['steps'], [{'discuss': d['id']}])
                    self.assertIs(j['interruptible'], False)

    def test_each_starts_from_a_trigger_in_the_staffed_scenarios(self):
        rs = self.st['reactions']
        for d in self.D['discussions']:
            with self.subTest(d['id']):
                mine = [r for r in rs if r['task'] == f'dsc_{d["id"]}']
                self.assertTrue(mine)
                self.assertTrue(all(r['roles'] == [d['roles'][0]] for r in mine))
                fault = TD.TRIGGERS[d['id']]
                self.assertIn({'fault': fault}, [r['on'] for r in mine])
                for sid in STAFFED:
                    sc = jload(self.F, f'scenarios/{sid}.json')
                    f = next(x for x in sc['faults'] if x['id'] == fault)
                    self.assertNotIn('when', f)      # the instructor's (or a test's): nothing starts by itself
        self.assertIn({'trip': 'st_trip_vib'}, [r['on'] for r in rs if r['task'] == 'dsc_st_trip'])

    def test_appended_after_everything_before(self):
        """The discussions' tasks and reactions come last, the findings last in every scenario's faults."""
        n = len(TD.tasks())
        self.assertEqual([t['id'] for t in self.st['tasks'][-n:]], [t['id'] for t in TD.tasks()])
        m = len(TD.reactions())
        self.assertEqual(self.st['reactions'][-m:], TD.reactions())
        for sid in STAFFED:
            sc = jload(self.F, f'scenarios/{sid}.json')
            self.assertEqual([f['id'] for f in sc['faults'][-len(TD.FINDINGS):]], [f[0] for f in TD.FINDINGS])


class NpcRun(unittest.TestCase):
    """On the reference engine: shift_cold, the gland's finding at 08:00 (the instructor's fault); the maintenance
    supervisor calls the shift supervisor and a mechanical technician to the workshop, the discussion runs between
    NPCs (mode npc, every point at its default) and agrees on the isolated repack, whose permit is asked for."""

    def test_the_gland_discussion_between_npcs(self):
        b = P.check_files(P.load_dir(DATA))
        e = P.Engine(b, 'shift_cold')
        tpm = e.staff.st.tpm
        e.step(180 * tpm)                   # 05:00 to 08:00 (day 1, a Monday)
        e.fault('cw_a_gland')
        k0 = len(e.events)
        for _ in range(120):
            e.step(tpm)
            if any(x[1] == 'permit' and x[2] == 'wo_cw_a_pack' for x in e.events[k0:]):
                break
        ev = e.events[k0:]
        start = next(x for x in ev if x[1] == 'discussion' and x[3] == 'start')
        self.assertEqual(start[2], 'cw_a_pack')
        self.assertEqual(start[-1], 'npc')
        lead, parts = start[4], start[5]
        self.assertEqual(len(parts), 3)
        self.assertNotIn(None, parts)       # all three met
        roles = {p.id: p.role for p in e.staff.people}
        self.assertEqual([roles[p] for p in parts], ['maint_sup', 'shift_sup', 'mech_tech'])
        self.assertEqual([x[2:5] for x in ev if x[1] == 'point'],
                         [['cw_a_pack', 'how', 'isolate'], ['cw_a_pack', 'when', 'today']])
        agreed = next(x for x in ev if x[1] == 'discussion' and x[3] == 'agreed')
        self.assertEqual(agreed[2:], ['cw_a_pack', 'agreed', 1, 'dsc_cwpk_now'])
        self.assertIn(['task', lead, 'dsc_cwpk_now', 'start'], [x[1:] for x in ev])
        req = next(x for x in ev if x[1] == 'permit' and x[2] == 'wo_cw_a_pack')
        self.assertEqual((req[3], req[5]), ('request', 'done'))
        self.assertEqual(roles[req[4]], 'maint_sup')


if __name__ == '__main__':
    unittest.main()
