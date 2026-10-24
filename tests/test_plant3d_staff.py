"""Walkdown Plant format 2's staff (docs/PLANT3D.md §16–§17, milestone S1) on the reference (ref/plant3d_staff.py):
the vectors' staff part (ref/vectors/plant3d-v2.json `staff`) is what the generator makes and replays from its
inputs; each reject is caught with its code; and the rules the vectors pin are checked by name (rosters across
midnight and day 0, slots, placement, routes and their tie rule, reservations, pre-emption, reactions and their
duplicates, the permit flow between NPCs, the trainee's inputs, jumps, fast-forward, the random streams).
  .venv/bin/python -m unittest tests.test_plant3d_staff"""
import json, os, sys, unittest

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
        """A seat taken by someone else: the person waits at the room's door and gives up after 15 clock minutes
        counted from their arrival there (the task abandoned)."""
        found = 0
        doors = ('office_door', 'cr_door', 'ws_door')
        for r in self.runs:
            ev = r['events']
            for e in ev:
                if e[1] == 'task' and e[4] == 'abandoned':
                    door = [m[5] for m in ev if m[1] == 'move' and m[2] == e[2] and m[4] in doors and m[5] <= e[0]]
                    if door and e[0] - max(door) == 150:     # 15 clock minutes at day_scale 60
                        found += 1
        self.assertGreater(found, 0)

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



    def test_the_trainee_lets_go_of_a_place(self):
        """A seat the trainee's go took is let go when they leave it or arrive elsewhere (others may take it)."""
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.role('a_fo1')
        e.step()
        sr = e.staff
        seat = None
        player = G.Trainee(walk=5)
        for _ in range(3000):
            player(e)
            e.step()
            held = [k for k, v in sr.holder.items() if v == sr.trainee and k == sr.t_at]
            if held:
                seat = held[0]
                break
        self.assertIsNotNone(seat, 'the trainee never held a place')
        e.leave(sr.st.places[seat]['id'])
        e.step()
        self.assertNotEqual(sr.holder.get(seat), sr.trainee)     # someone standing there may hold it now
        self.assertNotEqual(sr.people[sr.trainee].res, seat)

    def test_a_leave_of_an_unknown_place_does_nothing(self):
        """Away from every place, a `leave` naming no place keeps what the trainee holds (as GDScript does)."""
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.role('a_fo1')
        e.step()
        sr = e.staff
        tp = sr.people[sr.trainee]
        sr.t_at = tp.pos = None
        seat = next(i for i, q in enumerate(sr.st.places) if q['kind'] == 'seat' and i not in sr.holder)
        tp.occ = seat
        sr.holder[seat] = tp.i
        e.leave('no_such_place')
        e.step()
        self.assertEqual((tp.occ, sr.holder.get(seat)), (seat, tp.i))

    def test_a_person_standing_at_the_place_they_reserve_holds_it(self):
        """Someone already at a place they didn't hold, sent there, holds it (the reservation isn't dropped)."""
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.step()
        sr = e.staff
        p = next(q for q in sr.people if q.pos is not None and q.leg is None)
        sr.leave_place(p)
        sr.unreserve(p)
        here = next(i for i, q in enumerate(sr.st.places) if q['kind'] not in S.OPEN_KINDS and i not in sr.holder)
        p.pos = here                     # placed there while someone else held it, say
        self.assertEqual(sr.go(p, {'st': {}}, here), 'next')
        self.assertEqual((p.occ, sr.holder.get(here)), (here, p.i))

    def test_the_trainees_meeting_seat_is_theirs_again_after_a_pause(self):
        """A pause lets the trainee's meeting seat go; when the meeting is theirs again, so is the seat."""
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.role('a_fo1')
        e.step()
        sr = e.staff
        tp = sr.people[sr.trainee]
        sr.t_at = tp.pos = None
        sr.leave_place(tp)
        room = next(r for r in sr.st.rooms if sr.st.meet_place(r, sr.holder) is not None
                    and sr.st.places[sr.st.meet_place(r, sr.holder)]['kind'] in ('seat', 'desk', 'table'))
        m = {'room': room, 'with': [], 'minutes': 5}
        cur = {'st': {}, 'prio': 0, 'made': 0, 'order': 0}
        self.assertEqual(sr.meet(tp, cur, m, True), 'wait')
        seat = cur['st']['place']
        self.assertEqual(tp.res, seat)
        tp.cur = cur
        sr.pause(tp)
        sr.meet(tp, cur, m, True)
        self.assertEqual((tp.res, sr.holder.get(seat)), (seat, tp.i))

    def run_named(self, start):
        return next(r for r in self.runs if r['why'].startswith(start))['events']

    def test_actions_before_their_step(self):
        """§17.8 (the user, 2026-10-23): an op, lock or permit action of the trainee's made before its step is current
        counts when the step becomes current if it still holds (event early); one that no longer holds is made
        again; a done input counts for one step only."""
        ahead = self.run_named('actions before their step')
        early = [x[2:7] for x in ahead if x[1] == 'early']
        self.assertIn(['a_fo1', 'isolate_m', 1, 'op'], [x[:4] for x in early])
        self.assertIn(['a_fo1', 'isolate_m', 2, 'lock'], [x[:4] for x in early])
        made = {x[0] for x in ahead if x[1] in ('op', 'lock') and len(x) > 4 and 'a_fo1' in x}
        self.assertTrue(all(x[4] in made for x in early))
        # the lock was made before its step, and is still the field operator's when the job is done
        self.assertTrue(any(x[1] == 'task' and x[3] == 'isolate_m' and x[4] == 'done' for x in ahead))
        undo = self.run_named('an action before its step that no longer holds')
        self.assertFalse(any(x[1] == 'early' and x[3] == 'isolate_m' for x in undo))
        closes = [x[0] for x in undo if x[1] == 'op' and x[3] == 'close' and len(x) > 7 and x[7] == 'a_fo1']
        self.assertGreaterEqual(len(closes), 3)     # the open_valve task's, the one ahead, and the one made again
        self.assertTrue(any(x[1] == 'task' and x[3] == 'isolate_m' and x[4] == 'done' for x in undo))
        mech = self.run_named('a permit action before its step')
        acc = [x for x in mech if x[1] == 'permit' and x[3] == 'accept' and x[4] == 'mech1']
        self.assertEqual(len(acc), 1)
        self.assertIn(['mech1', 'job_pump', 2, 'permit', acc[0][0]], [x[2:7] for x in mech if x[1] == 'early'])

    def test_repairs_only_under_the_permit_by_its_acceptor(self):
        """§15.5 with staff (the user, 2026-10-23): a repair under the work's permit is the acceptor's, as its done; a
        played role without accept is refused, and so is an input naming another person."""
        fo = self.run_named('actions before their step')
        self.assertIn([1300, 'repair', 'f1', 'wo_pump', 'a_fo1', 'refused', ['authority']], fo)
        mech = self.run_named('a permit action before its step')
        self.assertIn([1100, 'repair', 'f1', 'wo_pump', 'a_fo1', 'refused', ['authority']], mech)
        self.assertIn([1101, 'repair', 'f1'], mech)
        self.assertEqual(sum(1 for x in mech if x[1] == 'repair' and len(x) == 3), 1)   # the done repairs nothing more
        for r in self.runs:      # the NPCs' repairs are their work's done, under the permit
            for x in r['events']:
                if x[1] == 'repair' and len(x) == 3 and x[0] != 1101:
                    self.assertTrue(any(y[0] == x[0] and y[1] == 'permit' and y[3] == 'done' and y[5] == 'done'
                                        for y in r['events']), (r['why'][:40], x))

    def test_a_kept_command_is_dropped_when_its_machine_is_commanded(self):
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.role('a_fo1')
        e.step()
        sr = e.staff
        sr.early = [['op', 1, 'K', 'start', 'local', 'm'], ['op', 1, 'K2', 'open', 'local', None], ['lock', 1, 'w', 0]]
        sr.drop_kept([[5, 'machine', 'm', 'a', 'b', 'next']], 'a_fo1')
        self.assertEqual(len(sr.early), 3)
        sr.drop_kept([[5, 'machine', 'm', 'b', 'c', 'command']], 'a_fo1')
        self.assertEqual(sr.early, [['op', 1, 'K2', 'open', 'local', None], ['lock', 1, 'w', 0]])
        # a point they locked again: an earlier unlock of theirs no longer holds (adversarial review); another
        # person's lock on it doesn't undo their unlock (locks are personal and stack, §15.1, 2026-10-24)
        sr.early = [['unlock', 1, 'w', 0], ['unlock', 1, 'w', 1], ['lock', 1, 'w', 0]]
        sr.drop_kept([[5, 'lock', 'w', 0, 'a_fo1', 'refused', ['state']]], 'a_fo1')
        sr.drop_kept([[5, 'lock', 'w', 0, 'a_elec', 'done', []]], 'a_fo1')
        self.assertEqual(len(sr.early), 3)
        sr.drop_kept([[5, 'lock', 'w', 0, 'a_fo1', 'done', []]], 'a_fo1')
        self.assertEqual(sr.early, [['unlock', 1, 'w', 1], ['lock', 1, 'w', 0]])

    def test_a_paused_step_is_looked_at_again(self):
        """A step paused by a pre-emption becomes current again when it resumes: its first look is made again."""
        b = P.check_files(files_of(self.V, self.runs[0]))
        e = P.Engine(b, 's1')
        e.role('a_fo1')
        e.step()
        sr = e.staff
        p = sr.people[sr.trainee]
        for _ in range(3000):
            if p.cur is not None:
                break
            e.step()
        self.assertIsNotNone(p.cur)
        st = p.cur['st']
        st['seen'] = True
        sr.pause(p)
        self.assertNotIn('seen', st)

    def test_personal_locks(self):
        """§15.1 (the user, 2026-10-23): only whoever placed a lock removes it; a supervisor's removal by authority
        names the reason and whose lock it was."""
        ev = self.run_named('personal locks')
        self.assertIn([600, 'unlock', 'wo_pump', 1, 'a_sup', 'refused', ['owner']], ev)
        self.assertIn([601, 'remove_lock', 'wo_pump', 1, 'a_sup', 'unknown', [], 'a_fo1', ''], ev)
        self.assertIn([601, 'remove_lock', 'wo_pump', 1, 'a_fo1', 'refused', ['authority'], 'a_fo1', 'Called away'], ev)
        self.assertIn([602, 'remove_lock', 'wo_pump', 1, 'a_sup', 'done', [], 'a_fo1',
                       'Locker went home sick; valve seen shut'], ev)
        self.assertIn([603, 'remove_lock', 'wo_pump', 1, 'a_sup', 'refused', ['unlocked'], None, 'Again'], ev)
        self.assertIn([604, 'lock', 'wo_pump', 1, 'a_sup', 'done', []], ev)
        self.assertIn([606, 'unlock', 'wo_pump', 1, 'a_sup', 'done', []], ev)
        # the NPCs unlock their own locks in every run
        for r in self.runs:
            self.assertFalse(any(x[1] == 'unlock' and x[5] == 'refused' and 'owner' in x[6] and x[4] != 'a_sup'
                                 for x in r['events']), r['why'])

    def lock_counts(self, ev, work='wo_pump'):
        """Each point's number of locks after every step of a run, from its lock, unlock and removal events."""
        held, out = {}, {}
        for x in ev:
            if x[1] in ('lock', 'unlock', 'remove_lock') and x[2] == work and x[5] == 'done':
                held[x[3]] = held.get(x[3], 0) + (1 if x[1] == 'lock' else -1)
                out[x[0]] = dict(held)
        return out

    def test_locks_handed_over_at_a_shift_change(self):
        """§15.1, §17.9 (the user, 2026-10-24): the incoming person's lock first, then the outgoing one's unlock; no
        step leaves a point of the open work unlocked; the new holders remove the isolation later."""
        ev = self.run_named('locks handed over at a shift change')
        self.assertIn([985, 'lock', 'wo_pump', 0, 'b_elec', 'done', []], ev)
        self.assertIn([986, 'unlock', 'wo_pump', 0, 'a_elec', 'done', []], ev)
        self.assertIn([1157, 'lock', 'wo_pump', 1, 'b_fo', 'done', []], ev)
        self.assertIn([1286, 'unlock', 'wo_pump', 1, 'a_fo2', 'done', []], ev)
        counts = self.lock_counts(ev)
        returned = next(x[0] for x in ev if x[1] == 'permit' and x[3] == 'return' and x[5] == 'done')
        for n, held in counts.items():
            if n < returned and n >= 142:
                self.assertEqual(sorted(held), [0, 1], n)
                self.assertTrue(all(v >= 1 for v in held.values()), (n, held))     # never unprotected
        self.assertEqual(max(max(h.values()) for h in counts.values()), 2)     # both locks on, for a while
        self.assertFalse(any(x[1] == 'permit' and x[3] == 'auto' and x[6] == [2] for x in ev))
        self.assertIn([1392, 'unlock', 'wo_pump', 1, 'b_fo', 'done', []], ev)     # by the new holders
        self.assertIn([1460, 'unlock', 'wo_pump', 0, 'b_elec', 'done', []], ev)
        self.assertIn([1461, 'permit', 'wo_pump', 'close', 'b_sup', 'done', []], ev)

    def test_nobody_takes_over(self):
        """§17.9: the outgoing person's wait runs out, they leave with the lock on, and the supervisor removes it by
        authority (lock_left, remove_locks), naming its owner; the issued permit is suspended back to approved."""
        ev = self.run_named('nobody takes over')
        self.assertFalse(any(x[1] == 'unlock' and x[4] == 'a_elec' for x in ev))
        left = next(x[0] for x in ev if x[1] == 'move' and x[2] == 'a_elec' and x[4] is None)
        start = next(x for x in ev if x[1] == 'task' and x[3] == 'remove_left')
        self.assertEqual(start[2:], ['b_sup', 'remove_left', 'start'])
        self.assertGreater(start[0], left)
        rm = [x for x in ev if x[1] == 'remove_lock']
        self.assertEqual(len(rm), 1)
        self.assertEqual(rm[0][2:], ['wo_pump', 0, 'b_sup', 'done', [], 'a_elec',
                                     'Removed by authority: its holder went off shift, nobody took over'])
        self.assertIn([rm[0][0], 'permit', 'wo_pump', 'auto', None, 'done', [2]], ev)
        self.assertIn([rm[0][0], 'say', 'b_sup', 'locks_removed', 'channel'], ev)

    def test_a_left_lock_is_given_again(self):
        """§17.9 (blind review): a removal that found no supervisor on duty is given again when someone comes on."""
        ev = self.run_named('nobody takes over and no supervisor')
        self.assertIn([1554, 'task', None, 'remove_left', 'unassigned'], ev)
        self.assertIn([1800, 'task', 'n_sup', 'remove_left', 'start'], ev)
        self.assertTrue(any(x[1] == 'remove_lock' and x[4] == 'n_sup' and x[5] == 'done' and x[7] == 'a_elec'
                            for x in ev))

    def test_crew_mates_are_not_post_mates(self):
        """§17.9 (blind review): two people of one post in one crew hand nothing over to each other."""
        F = G.staff_files(staff=G.handover_staff())
        F['staff.json']['people'].append({'id': 'a_fo3', 'role': 'field_op', 'roster': 'shift', 'crew': 'a',
                                          'call': 'Field 3 A'})
        e = P.Engine(G.check(F), 's1')
        sr = e.staff
        ix = sr.st.person_ix
        a1, a3 = sr.people[ix['a_fo1']], sr.people[ix['a_fo3']]
        self.assertFalse(sr.mate(a1, 'a_fo3'))
        self.assertFalse(sr.mate(a3, 'a_fo1'))
        self.assertTrue(sr.mate(a1, 'c_fo'))

    def test_a_returned_work_is_not_handed_over(self):
        """§17.9 (adversarial review): a work returned before the handover: nobody takes its locks over, the outgoing
        people unlock without waiting, and the permit is closed (no lock rotates to the next shift)."""
        ev = self.run_named('a work returned just before the shift change')
        self.assertFalse(any(x[1] == 'lock' and x[0] > 902 for x in ev))
        self.assertIn([954, 'unlock', 'wo_pump', 0, 'a_elec', 'done', []], ev)
        self.assertTrue(any(x[1] == 'unlock' and x[4] == 'a_fo2' and x[5] == 'done' for x in ev))
        self.assertTrue(any(x[1] == 'permit' and x[3] == 'auto' and x[6] == [8] for x in ev))

    def test_a_day_shift_job_overnight(self):
        """§17.10 (the user, 2026-10-24): an unfinished day-shift job is held at 16:00 with its lock on (no removal
        by authority, the permit still accepted), resumed at 07:00, and its technician unlocks their own lock."""
        run = next(r for r in self.runs if r['why'].startswith('a day-shift job overnight'))
        ev = run['events']
        held = next(x for x in ev if x[1] == 'task' and x[3] == 'job_gauge' and x[4] == 'held')
        self.assertEqual(held[2], 'ic1')
        self.assertTrue(any(x[1] == 'move' and x[2] == 'ic1' and x[4] is None and x[0] >= held[0] for x in ev))
        resumed = next(x for x in ev if x[1] == 'task' and x[3] == 'job_gauge' and x[4] == 'resumed')
        self.assertFalse(any(x[1] in ('remove_lock', 'unlock') and held[0] <= x[0] <= resumed[0] for x in ev))
        self.assertFalse(any(x[1] == 'task' and x[3] == 'remove_left' for x in ev))
        night = [s for s in run['states'] if held[0] < s['step'] < resumed[0]]
        self.assertTrue(night)
        for s in night:
            self.assertEqual(s['permits'].get('wo_gauge'), 5, s['step'])
            self.assertIn(['iso_gauge', 0], s['locked'])
        self.assertTrue(any(x[1] == 'unlock' and x[4] == 'ic1' and x[5] == 'done' and x[0] > resumed[0] for x in ev))
        self.assertTrue(any(x[1] == 'permit' and x[2] == 'wo_gauge' and x[3] == 'close' and x[5] == 'done' for x in ev))

    def test_the_trainee_hands_over(self):
        """§17.9: the trainee takes over a lock from the permit form (incoming), and gives one (outgoing)."""
        ev = self.run_named("the trainee as crew B's field operator")
        lock = next(x for x in ev if x[1] == 'lock' and x[4] == 'b_fo')
        unlock = next(x for x in ev if x[1] == 'unlock' and x[4] == 'a_fo2')
        self.assertLess(lock[0], unlock[0])
        self.assertIn([lock[0], 'task', 'b_fo', 'handover_take_f', 'done'], ev)
        ev = self.run_named("the trainee as crew A's field operator 2")
        lock = next(x for x in ev if x[1] == 'lock' and x[4] == 'b_fo')
        unlock = next(x for x in ev if x[1] == 'unlock' and x[4] == 'a_fo2')
        self.assertEqual(unlock[0], lock[0] + 1)            # theirs off once the incoming lock is on
        self.assertIn([unlock[0], 'task', 'a_fo2', 'handover_give_f', 'done'], ev)

    def test_a_free_radio_call_names_no_work(self):
        b = P.check_files(files_of(self.V, self.runs[4]))
        e = P.Engine(b, 's1')
        e.step(2)
        e.call('field_op', 'open_valve', 'wo_pump')
        e.call('field_op', 'open_valve')
        e.call('field_op', 'isolate_m')         # not one of the control room operator's requests
        e.step()
        calls = [x for x in e.events if x[1] == 'call' and x[2] == 'a_ccr']
        self.assertEqual([c[6] for c in calls], ['refused', 'done', 'refused'])


    def test_no_jump_while_npcs_inputs_wait(self):
        """A jump checked in step 1 before the NPCs' inputs of the step before are made would leave a permit they
        request with no task: it is refused while any is still to be made."""
        sc = json.loads(json.dumps(self.runs[5]['scenario']))
        b = P.check_files(files_of(self.V, dict(self.runs[5], scenario=sc)))
        e = P.Engine(b, 's1')
        e.step(1)
        e.task_ack()
        e.fault('f1')               # the supervisor (the trainee here) gets a task; an NPC's input is what we need:
        for _ in range(400):
            e.step()
            if e.npc_queue:
                break
        self.assertTrue(e.npc_queue, 'no NPC input to wait for')
        e.task_ack()
        e.jump('20:00')
        e.step()
        j = [x for x in e.events if x[1] == 'jump']
        self.assertEqual(j[-1][4], 'refused')


class FirstTrainStaff(unittest.TestCase):
    """The first train's staff content (tools/plant3d/train_staff.py, milestone S1) and its `day` vector: the day
    replays from the content; each run with a trainee or a fault does what it was made for; the rounds' ranges hold
    for the plant at rest and at base load (a reading out of range is a finding, not the normal state)."""

    @classmethod
    def setUpClass(cls):
        with open(G.OUT2, encoding='utf-8') as f:
            cls.day = json.load(f)['day']
        cls.b = P.check_dir(G.DATA)

    def test_a_suspended_job_is_offered_again(self):
        """§17.10 (a bug the locks review found): CW pump B's breaker lock removed by authority while its job is in
        progress suspends the permit; isolated and issued again, the job is offered to a technician again and the
        permit goes on to closed (before the fix the job's reaction stayed blocked and the permit stuck at issued)."""
        f = next(f for f in self.day['forks'] if f['id'] == 'job_suspended')
        ev = f['events']
        starts = [x for x in ev if x[1] == 'task' and x[3] == 'job_cw_b_motor' and x[4] == 'start']
        self.assertEqual(len(starts), 2)
        self.assertIn([15000, 'permit', 'wo_cw_b_motor', 'auto', None, 'done', [2]], ev)
        reissue = [x[0] for x in ev if x[1] == 'permit' and x[2] == 'wo_cw_b_motor' and x[3] == 'issue']
        self.assertEqual(len(reissue), 2)
        self.assertEqual(starts[1][0], reissue[1])
        self.assertEqual(f['end']['permits']['wo_cw_b_motor'], 9)

    def test_jobs_resume_next_duty(self):
        """§17.10: the content's jobs are held overnight at their duty's end, not left running."""
        jobs = [t for t in self.b.staff.tasks.values() if t['id'].startswith('job_')]
        self.assertTrue(jobs)
        self.assertTrue(all(t.get('resume') == 'next_duty' for t in jobs))

    def test_content(self):
        st = self.b.staff
        roles = {p['role'] for p in st.people}
        self.assertEqual(roles, {'shift_sup', 'ccr_op', 'field_op', 'elec_ap', 'mech_tech', 'elec_tech', 'ic_tech'})
        self.assertEqual(sum(1 for p in st.people if p['roster'] == 'shift'), 28)
        self.assertTrue(all(st.roles[r]['play'] for r in ('shift_sup', 'ccr_op', 'field_op', 'elec_ap')))
        self.assertEqual(self.b.plant['clock']['day_scale'], 6)
        self.assertIn('staff', self.b.scenarios['shift_cold'])
        for s in ('cold_iron', 'hot_restart'):
            self.assertNotIn('staff', self.b.scenarios[s])      # format 1's vectors run without people

    def test_day_replays(self):
        d = self.day
        e = P.Engine(self.b, d['scenario'])
        states = [plain(e.snapshot(values=False))]
        while e.step_no < d['until']:
            e.step()
            if e.step_no % d['every'] == 0:
                states.append(plain(e.snapshot(values=False)))
        self.assertIsNone(close(plain(e.events), d['events']))
        self.assertIsNone(close(states, d['states']))
        kinds = {x[1] for x in d['events']}
        for k in ('duty', 'task', 'move', 'read', 'say'):
            self.assertIn(k, kinds)
        self.assertFalse(any(x[1] == 'read' and x[5] == 'out_of_range' for x in d['events']),
                         'a normal day finds nothing out of range')

    def test_forks(self):
        for f in self.day['forks']:
            e = P.Engine(self.b, self.day['scenario'])
            inputs = sorted(f['inputs'], key=lambda x: x[0])
            j = 0
            while e.step_no < f['until']:
                while j < len(inputs) and inputs[j][0] == e.step_no + 1:
                    G.apply_staff(e, inputs[j])
                    j += 1
                e.step()
            self.assertIsNone(close(plain(e.events), f['events']), f['id'])
            x = f['expect']
            if 'trainee' in x:
                self.assertEqual(e.staff.people[e.staff.trainee].id, x['trainee'], f['id'])
            for k, v in x.get('end', {}).items():
                self.assertEqual(e.v(k), v, f['id'])
            for w, s in x.get('permits', {}).items():
                self.assertEqual(e.pstate[w], s, f['id'])
            for fid in x.get('repaired', []):
                self.assertIn([fid], [ev[2:] for ev in e.events if ev[1] == 'repair'], f['id'])
            for want in x.get('events', []):
                self.assertTrue(any(len(ev) > len(want) and all(w is None or ev[1 + i] == w
                                                                for i, w in enumerate(want)) for ev in e.events),
                                f'{f["id"]}: no event like {want}')

    def test_round_ranges_hold_at_rest_and_at_base_load(self):
        sys.path.insert(0, os.path.join(REPO, 'tools', 'plant3d'))
        import train_staff as T
        e0 = P.Engine(self.b, 'cold_iron')
        e1, _ = P.run_procedure(self.b, 'cold_start')
        for _, (title, reads) in T.ROUNDS.items():
            for code, (lo, hi), tol in reads:
                for e in (e0, e1):
                    v = e.shown(code, e.cur)
                    self.assertTrue(lo <= v <= hi, f'{code}: {v} outside [{lo}, {hi}] ({title})')


if __name__ == '__main__':
    unittest.main()
