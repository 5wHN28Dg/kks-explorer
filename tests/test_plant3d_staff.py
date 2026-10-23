"""Walkdown Plant format 2's staff (docs/PLANT3D.md §16–§17, milestone S1) on the reference (ref/plant3d_staff.py):
the vectors' staff part (ref/vectors/plant3d-v2.json `staff`) is what the generator makes and replays from its
inputs; each reject is caught with its code; and the rules the vectors pin are checked by name (rosters across
midnight and day 0, slots, placement, routes and their tie rule, reservations, pre-emption, reactions and their
duplicates, the permit flow between NPCs, the trainee's inputs, jumps, fast-forward, the random streams).
  .venv/bin/python -m unittest tests.test_plant3d_staff"""
import copy, json, os, sys, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, REPO)
from ref import plant3d as P  # noqa: E402
from ref import plant3d_staff as S  # noqa: E402
from ref import make_plant3d_vectors as G  # noqa: E402
from tests.test_plant3d import close, plain  # noqa: E402


def files_of(V, run=None):
    F = {k: t.encode() for k, t in V['staff']['files'].items()}
    if run is not None:
        F['scenarios/s1.json'] = json.dumps(run['scenario']).encode()
        if run['staff'] is not None:
            F['staff.json'] = json.dumps(run['staff']).encode()
    return F


def replay(V, run):
    b = P.check_files(files_of(V, run))
    e = P.Engine(b, 's1')
    states = [plain(e.snapshot())]
    inputs = run['inputs']
    i = 0
    while e.step_no < run['until']:
        while i < len(inputs) and inputs[i][0] == e.step_no + 1:
            G.apply_staff(e, inputs[i])
            i += 1
        e.step()
        if e.step_no % run['every'] == 0 or e.step_no == run['until']:
            states.append(plain(e.snapshot()))
    return e, states


class StaffVectors(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(G.OUT2, encoding='utf-8') as f:
            cls.V = json.load(f)
        cls.runs = cls.V['staff']['runs']
        cls.ev = [e for r in cls.runs for e in r['events']]

    def test_part_is_what_the_generator_makes(self):
        st = self.V['staff']
        self.assertEqual(json.loads(G.dump(st['runs'])), st['runs'], 'run python3 ref/make_plant3d_vectors.py --write')
        self.assertEqual(json.loads(G.dump(G.build_rejects_staff())), st['reject'])
        self.assertEqual({k: json.loads(v) for k, v in st['files'].items()},
                         {k: json.loads(json.dumps(v)) for k, v in G.staff_files().items()})

    def test_runs_replay(self):
        for run in self.runs:
            e, states = replay(self.V, run)
            d = close(plain(e.events), run['events'])
            self.assertIsNone(d, f'{run["why"][:60]}: {d}')
            d = close(states, run['states'])
            self.assertIsNone(d, d)

    def test_valid_counts(self):
        b = P.check_files(files_of(self.V))
        self.assertEqual(b.counts, self.V['staff']['counts'])
        self.assertEqual((b.counts['people'], b.counts['points']), (10, 6))

    def test_each_reject_is_caught_with_its_code(self):
        codes = set()
        for r in self.V['staff']['reject']:
            files = files_of(self.V)
            for k, t in r['change'].items():
                if t is None:
                    files.pop(k)
                else:
                    files[k] = t.encode()
            with self.assertRaises(P.FormatError, msg=r['why']) as cm:
                P.check_files(files)
            self.assertEqual(cm.exception.code, r['code'], f'{r["why"]}: {cm.exception}')
            codes.add(r['code'])
        # every new error code of format 2's staff (§14), and the ones the staff file shares with format 1
        for c in ('bad_clock', 'unreachable', 'bad_way', 'authority', 'unknown_key', 'missing_key', 'bad_ref',
                  'bad_value', 'dup_id', 'bad_length', 'limit', 'bad_number', 'bad_kind', 'bad_type'):
            self.assertIn(c, codes)

    def test_every_task_step_kind_and_outcome_is_pinned(self):
        kinds = {e[1] for e in self.ev}
        for k in ('duty', 'task', 'move', 'read', 'say', 'call', 'permit', 'lock', 'unlock', 'op', 'role', 'jump',
                  'task_ack', 'alarm', 'trip', 'fault', 'repair'):
            self.assertIn(k, kinds)
        outcomes = {e[4] for e in self.ev if e[1] == 'task'}
        self.assertEqual(outcomes, {'start', 'done', 'abandoned', 'skipped', 'unassigned'})
        reads = {e[5] for e in self.ev if e[1] == 'read'}
        self.assertEqual(reads, {'ok', 'out_of_range', 'misread'})
        npc_ops = [e for e in self.ev if e[1] == 'op' and len(e) == 8 and e[7] not in ('a_ccr',)]
        self.assertTrue(any(e[6] == 'local' for e in npc_ops) and any(e[6] == 'screen' for e in npc_ops))
        # the permit flow between NPCs: every action by its role, the automatic moves, the done's repair
        acts = {(e[3], e[4]) for e in self.runs[0]['events'] if e[1] == 'permit' and e[5] == 'done'}
        for a in (('request', 'a_sup'), ('approve', 'a_sup'), ('issue', 'a_sup'), ('accept', 'mech1'),
                  ('done', 'mech1'), ('return', 'mech1'), ('close', 'a_sup'), ('auto', None)):
            self.assertIn(a, acts)
        locks = {(e[1], e[2], e[3], e[4]) for e in self.runs[0]['events'] if e[1] in ('lock', 'unlock') and
                 e[5] == 'done'}
        self.assertTrue({('lock', 'wo_pump', 0, 'a_elec'), ('lock', 'wo_pump', 1, 'a_fo1'),
                         ('unlock', 'wo_pump', 0, 'a_elec'), ('lock', 'wo_valve', 0, 'a_fo1'),
                         ('lock', 'wo_valve', 1, 'a_fo1')} <= locks, locks)
        self.assertIn([1357, 'repair', 'f1'], self.runs[0]['events'])

    def test_rosters_cross_midnight_and_day_0(self):
        """Crew C worked day 0's night (18:00 to 06:00 on day 1): on at step 0 as a level, off at 06:00; crew A on."""
        r = self.runs[0]
        ppl = r['states'][0]['people']
        self.assertEqual(ppl['c_ccr'][0], 'desk_a')
        self.assertIsNone(ppl['a_ccr'][0])
        duty = [e for e in r['events'] if e[1] == 'duty']
        self.assertIn([300, 'duty', 'c_ccr', 'off'], duty)
        self.assertIn([300, 'duty', 'a_ccr', 'on'], duty)
        self.assertIn([900, 'duty', 'mech1', 'on'], duty)       # days: Monday 07:00
        self.assertEqual(r['states'][0]['clock'], (1 * 1440 + 5 * 60 + 30) * 600)
        # slots before the duty's start are made all the same: the handover at start-0:15 (05:45, step 150)
        self.assertIn([150, 'task', 'a_ccr', 'handover_take', 'start'], r['events'])

    def test_the_next_table_tie(self):
        """p1 to p5: through p2 or p3 in 154 steps each; the lower list of point indexes ([1, 2, 5]) wins."""
        st = P.check_files(files_of(self.V)).staff
        self.assertEqual(st.next[1][5], 2)
        self.assertEqual(st.next[5][1], 2)
        self.assertEqual(st.next[3][2], 1)

    def test_people_come_from_the_gate_and_leave_by_it(self):
        ev = self.runs[0]['events']
        self.assertIn([150, 'move', 'a_ccr', None, 'gate', 150], ev)
        gone = [e for e in ev if e[1] == 'move' and e[2] == 'c_ccr' and e[4] is None]
        self.assertEqual(len(gone), 1)

    def test_reaction_duplicates_and_who_gets_a_task(self):
        ev = self.runs[0]['events']
        # the alarm is answered by the on-duty control room operator; the trip, with no supervisor on duty yet, by
        # the next role listed (the control room operator)
        self.assertIn([94, 'task', 'c_ccr', 'answer_alarm', 'start'], ev)
        self.assertIn([98, 'task', 'c_ccr', 'trip_call', 'start'], ev)
        # nobody on duty for a call: unassigned
        self.assertTrue(any(e[1] == 'task' and e[2] is None and e[4] == 'unassigned' for e in self.runs[6]['events']))

    def test_the_trainee(self):
        fo = self.runs[3]['events']
        self.assertIn([1, 'role', 'a_fo1', 'done'], fo)
        self.assertIn([1, 'role', 'a_fo2', 'refused'], fo)
        self.assertIn([3, 'role', 'a_fo2', 'refused'], fo)
        self.assertTrue(any(e[1] == 'read' and e[2] == 'a_fo1' and e[5] == 'misread' for e in fo))
        self.assertTrue(any(e[1] == 'op' and e[7] == 'a_fo1' and e[4] == 'done' for e in fo if len(e) == 8))
        self.assertTrue(any(e[1] == 'say' and e[2] == 'a_fo1' and e[3] == 'alarm_checked' for e in fo))
        ccr = self.runs[4]['events']
        refused = [e[2:8] for e in ccr if e[1] == 'op' and e[4] == 'refused']
        self.assertIn(['10LAB10AA001', 'open', 'refused', ['where'], 'screen', 'a_ccr'], refused)
        self.assertIn(['10LAC10AP001', 'stop', 'refused', ['authority'], 'local', 'a_ccr'], refused)
        self.assertIn(['10LAC10AP001', 'stop', 'refused', ['where'], 'screen', 'a_fo1'], refused)
        self.assertIn([32, 'op', '10LAC10AP001', 'stop', 'refused', ['authority']], ccr)
        self.assertIn([33, 'permit', 'wo_pump', 'approve', 'a_ccr', 'refused', ['authority', 'state']], ccr)
        self.assertIn([35, 'call', 'a_ccr', 'field_op', 'check_pump', None, 'refused'], ccr)
        self.assertIn([35, 'call', 'a_ccr', 'field_op', 'open_valve', None, 'done'], ccr)
        self.assertTrue(any(e[1] == 'op' and e[2] == '10LAC10AP001' and e[3] == 'start' and e[4] == 'done' and
                            e[7] == 'a_ccr' for e in ccr if len(e) == 8))
        # fast-forward stops while a task given to the trainee waits for task_ack
        st = self.runs[3]['states']
        self.assertTrue(any(s['unacked'] > 0 and not s['fast_forward'] for s in st))

    def test_jumps(self):
        ev = self.runs[5]['events']
        jumps = [e for e in ev if e[1] == 'jump']
        self.assertEqual([j[4] for j in jumps], ['refused', 'refused', 'done', 'refused', 'done', 'refused'])
        self.assertTrue(any(e[1] == 'task' and e[4] == 'skipped' for e in ev))
        n = jumps[2][0]
        # duties are levels after a jump: no duty events in the jump's step
        self.assertFalse(any(e[1] == 'duty' and e[0] == n for e in ev))

    def test_streams(self):
        """§17.5: per-person streams; a person added at the end of the file changes no one else's seed."""
        self.assertEqual(S.mix32(0), 0)
        self.assertEqual(S.mul32(0xFFFFFFFF, 0xFFFFFFFF), 1)
        s = [S.seed_of(1, i) for i in range(10)]
        self.assertEqual(len(set(s)), 10)
        st, r = S.draw(1)
        self.assertEqual((st, r), (270369, 1056))
        # the GDScript product never passes 2^63: the halves' formula equals the exact product mod 2^32
        for a, b in ((0xFFFFFFFF, 0xFFFFFFFF), (0x9e3779b9, 0x7feb352d), (123456789, 987654321)):
            g = ((a * (b & 0xFFFF)) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF
            self.assertEqual(g, S.mul32(a, b))
            self.assertLess(a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16), 2 ** 63)
        base = P.check_files(files_of(self.V, self.runs[0]))
        more = P.check_files(files_of(self.V, self.runs[2]))
        e1, e2 = P.Engine(base, 's1'), P.Engine(more, 's1')
        self.assertEqual([p.rng for p in e1.staff.people], [p.rng for p in e2.staff.people][:10])

    def test_waiting_for_a_taken_place(self):
        """The supervisor's seat taken by a field operator: the supervisor waits at the office's door, and gives up
        after 15 clock minutes (the idle task abandoned)."""
        ev = self.runs[0]['events']
        self.assertTrue(any(e[1] == 'task' and e[2] == 'a_sup' and e[3] == 'idle_sup' and e[4] == 'abandoned'
                            for r in self.runs for e in r['events']))

    def test_clone_is_independent(self):
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.step(400)
        c = e.clone()
        c.step(200)
        e.step(200)
        self.assertEqual(plain(c.snapshot()), plain(e.snapshot()))
        self.assertEqual(c.events, e.events)
        self.assertIsNot(c.staff.people[0], e.staff.people[0])


if __name__ == '__main__':
    unittest.main()
