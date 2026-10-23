"""Walkdown Plant format 2's staff (docs/PLANT3D.md §16–§17, milestone S1): the reference validator of staff.json
and the reference staff step (step 9).

Test-only reference, like ref/plant3d.py, whose Engine runs it: the app's engine (apps/plant3d/sim/staff.gd) must
agree with it bit for bit on ref/vectors/plant3d-v2.json.

What milestone S1 builds (PLANT3D.md §17.8 "As built for S1"): the clock, rosters and duties, duty routines, the
walking network and its `next` table, place reservations, queues and pre-emption, reactions to alarms, trips, faults,
values and permits, the task steps go, work, read, op, permit, lock, unlock, say, wait, call, meet, choose and ack,
the trainee's person and inputs, jumps, fast-forward and the random streams. Zones, PPE, unsafe acts and `stop`
come with S2; vehicles, `ride`, `sleep`, homes and off-duty routines with S4: their keys are refused until then
(`unknown_key`), so no content can rely on behaviour the engines don't have.
"""
import copy, heapq, math, re
from ref.courses import need, keys, is_num, num, ident, lst

STAFF_FORMAT = 'walkdown-plant-staff'
MAX = {'people': 200, 'roles': 48, 'places': 2000, 'points': 500, 'ways': 6000, 'tasks': 400, 'task_steps': 64,
       'reactions': 128, 'rosters': 16, 'routines': 64, 'queue': 32}
PLACE_KINDS = ('desk', 'seat', 'bed', 'table', 'work', 'door', 'stop', 'locker', 'store', 'counter', 'point', 'muster',
               'depot')
OPEN_KINDS = ('point', 'door', 'stop', 'muster', 'counter', 'depot', 'work')    # hold anyone (§16.2)
POSES = ('stand', 'sit', 'lie', 'kneel')
WALK_MODES = ('walk', 'stair', 'ladder')
ROLE_DISCIPLINES = ('ops', 'inst', 'mech', 'elec', 'chem', 'civil', 'hse', 'mgmt', 'security', 'transport', 'camp')
AUTHORITIES = ('operate_screen', 'operate_local', 'request', 'approve', 'issue', 'accept', 'lock_electrical',
               'lock_mechanical', 'lock_process', 'lock_instrument', 'stop_work', 'sample', 'drive')
PPE = ('helmet', 'boots', 'glasses', 'gloves', 'ear', 'harness', 'face_shield', 'apron', 'vest')
WEEK = ('mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun')
# who may make each permit action (§15.3): done and return are the acceptor's (or another with accept and the
# work's discipline while the acceptor is off duty or absent)
PERMIT_AUTH = {'request': 'request', 'approve': 'approve', 'issue': 'issue', 'accept': 'accept', 'done': 'accept',
               'return': 'accept', 'close': 'issue', 'cancel': 'approve'}
STATE_NAMES = ('none', 'requested', 'approved', 'isolated', 'issued', 'accepted', 'done', 'returned', 'deisolated',
               'closed', 'cancelled')
STEP_KINDS = ('go', 'work', 'read', 'op', 'permit', 'lock', 'unlock', 'say', 'wait', 'call', 'meet', 'choose', 'ack')
LATER = {'ppe': 'S2', 'stop': 'S2', 'ride': 'S4', 'sleep': 'S4'}
HHMM = re.compile(r'([01][0-9]|2[0-3]):([0-5][0-9])')
OFFSET = re.compile(r'(start|end)([+-])([0-9]|1[0-2]):([0-5][0-9])')
DUR = re.compile(r'([0-9]|1[0-9]|2[0-4]):([0-5][0-9])')
DAY = 864000            # tenths of a clock second in a day
MINUTE = 600
WAIT_PLACE = 15         # clock minutes a person waits for a taken place, or for a meeting's people (§16.2, §16.6)


# ---------------------------------------------------------------- random numbers (§17.5)

def mul32(a, b):
    return (a * b) & 0xFFFFFFFF


def mix32(x):
    x ^= x >> 16
    x = mul32(x, 0x7feb352d)
    x ^= x >> 15
    x = mul32(x, 0x846ca68b)
    x ^= x >> 16
    return x


def seed_of(seed, i):
    s = mix32(seed ^ mul32(i + 1, 0x9e3779b9))
    return s or 1


def draw(s):
    """One draw: (new state, r of 24 bits)."""
    s ^= (s << 13) & 0xFFFFFFFF
    s ^= s >> 17
    s ^= (s << 5) & 0xFFFFFFFF
    return s, s >> 8


# ---------------------------------------------------------------- the clock (§16.1)

def hhmm(x, where):
    m = HHMM.fullmatch(x) if isinstance(x, str) else None
    need(m is not None, 'bad_clock', f'{where}: a clock time HH:MM')
    return int(m.group(1)) * 60 + int(m.group(2))


def check_clock(c, where):
    """plant.json's `clock`: {day_scale, start: {day, time}, week}."""
    keys(c, ('day_scale', 'start', 'week'), (), where)
    ds = c['day_scale']
    need(isinstance(ds, int) and not isinstance(ds, bool) and 1 <= ds <= 60 and 60 % ds == 0, 'bad_clock',
         f'{where}.day_scale: a whole number that divides 60')
    check_start(c['start'], f'{where}.start')
    w = lst(c['week'], f'{where}.week', 7, 7)
    need(sorted(w) == sorted(WEEK), 'bad_value', f'{where}.week: the seven days {WEEK}, day 1\'s first')
    return c


def check_start(s, where):
    keys(s, ('day', 'time'), (), where)
    need(isinstance(s['day'], int) and not isinstance(s['day'], bool) and 1 <= s['day'] <= 100000, 'bad_number',
         f'{where}.day: a whole number from 1')
    hhmm(s['time'], f'{where}.time')
    return s


def start_tenths(s):
    return (s['day'] * 1440 + hhmm(s['time'], '')) * MINUTE


def show_clock(t):
    """Tenths of a clock second as (day, 'HH:MM:SS')."""
    d, r = divmod(t, DAY)
    s = r // 10
    return d, f'{s // 3600:02d}:{s // 60 % 60:02d}:{s % 60:02d}'


# ---------------------------------------------------------------- the walking network (§16.2)

def way_steps(metres, speed):
    """A way's time in steps: ⌈metres × 10 / speed − 1e-9⌉, at least 1."""
    return max(1, math.ceil(metres * 10 / speed - 1e-9))


def next_table(npts, adj):
    """For each point i and destination j, the point after i on the quickest route (by steps) from i to j; of equal
    ones, the one whose list of point indices from i is lowest (§16.2). adj[i]: [(j, steps)]. -1 for i = j and for
    a destination not reached."""
    table = []
    for src in range(npts):
        best = {}
        heap = [(0, (src,))]
        while heap:
            cost, path = heapq.heappop(heap)
            u = path[-1]
            if u in best:
                continue
            best[u] = path
            for v, w in adj[u]:
                if v not in best:
                    heapq.heappush(heap, (cost + w, path + (v,)))
        table.append([best[j][1] if j in best and j != src else -1 for j in range(npts)])
    return table


# ---------------------------------------------------------------- the validator

class Staff:
    """A checked staff.json with everything the step needs, built once (the engine's state is in StaffRun)."""

    def __init__(self, d, b, m):
        self.d, self.b, self.m = d, b, m
        w = 'staff.json'
        for k, ms in (('zones', 'S2'), ('vehicles', 'S4'), ('put_right', 'S2')):
            need(k not in d, 'unknown_key', f'{w}.{k}: not before milestone {ms} (PLANT3D.md §17.8)')
        keys(d, ('format', 'version', 'origin', 'gate', 'speeds', 'places', 'ways', 'next', 'roles', 'rosters',
                 'people', 'routines', 'tasks', 'messages'), ('reactions',), w)
        need(d['format'] == STAFF_FORMAT, 'bad_format', f'{w}: format must be "{STAFF_FORMAT}"')
        need(d['version'] == 1 and not isinstance(d['version'], bool), 'bad_version', f'{w}: version must be 1')
        clock = b.plant.get('clock')
        need(clock is not None, 'missing_key', 'plant.json.clock: a plant with staff.json has a clock (§16.1)')
        self.ds = clock['day_scale']
        self.tpm = MINUTE // self.ds              # steps in a clock minute
        self.week = clock['week']
        self.check_speeds(d['speeds'])
        self.check_places(d['places'])
        self.check_ways(d['ways'])
        self.check_next(d['next'])
        self.origin = self.place_ref(d['origin'], f'{w}.origin')
        self.gate = self.place_ref(d['gate'], f'{w}.gate')
        need(self.places[self.gate]['kind'] in ('door', 'point', 'muster'), 'bad_value',
             f'{w}.gate: a door, point or muster place')
        self.check_reach()
        self.messages = d['messages']
        need(isinstance(self.messages, dict), 'bad_type', f'{w}.messages')
        for k, v in self.messages.items():
            ident(k, f'{w}.messages')
            need(isinstance(v, str) and 1 <= len(v) <= 200, 'bad_type', f'{w}.messages.{k}: text of 1–200 characters')
        self.check_roles(d['roles'])
        self.check_rosters(d['rosters'])
        self.check_people(d['people'])
        self.tasks = {}
        self.task_ix = {}
        tl = lst(d['tasks'], f'{w}.tasks')
        need(len(tl) <= MAX['tasks'], 'limit', f'{w}.tasks: over {MAX["tasks"]}')
        for i, t in enumerate(tl):
            need(isinstance(t, dict), 'bad_type', f'{w}.tasks[{i}]')
            ident(t.get('id'), f'{w}.tasks[{i}].id')
            need(t['id'] not in self.tasks, 'dup_id', f'{w}: task {t["id"]} twice')
            self.task_ix[t['id']] = i
            self.tasks[t['id']] = t
        self.task_list = tl
        self.check_routines(d['routines'])
        for t in tl:
            self.check_task(t)
        self.check_reactions(d.get('reactions', []))
        self.check_task_refs()
        self.check_authority()
        for x in m.works:
            if 'task' in x:
                need(x['task'] in self.tasks, 'bad_ref', f'work {x["id"]}.task: no task {x["task"]!r} in staff.json')
            else:
                need(False, 'missing_key', f'work {x["id"]}.task: works of a plant with staff.json name their task '
                                           f'(§15.2)')

    # --- speeds, places, ways, next
    def check_speeds(self, s):
        w = 'staff.json.speeds'
        keys(s, ('walk', 'stair', 'ladder'), ('drive',), w)
        for k, v in s.items():
            num(v, f'{w}.{k}', 0.01, 100)
        self.speeds = s

    def check_places(self, pl):
        w = 'staff.json.places'
        lst(pl, w)
        need(len(pl) <= MAX['places'], 'limit', f'{w}: over {MAX["places"]}')
        self.places, self.pix = [], {}
        self.points = []            # place indices of the points, in place order
        self.point_no = {}          # place index -> point number
        self.rooms = {}             # room -> [place indices]
        self.work_at = {}           # code -> its work place (the first)
        for i, p in enumerate(pl):
            wp = f'{w}[{i}]'
            for k, ms in (('zones', 'S2'), ('depot', 'S4')):
                need(not isinstance(p, dict) or k not in p, 'unknown_key', f'{wp}.{k}: not before milestone {ms}')
            keys(p, ('id', 'at', 'kind'), ('room', 'yaw', 'pose', 'kks'), wp)
            ident(p['id'], f'{wp}.id')
            need(p['id'] not in self.pix, 'dup_id', f'{wp}: place {p["id"]} twice')
            lst(p['at'], f'{wp}.at', 3, 3)
            for c in p['at']:
                num(c, f'{wp}.at')
            need(p['kind'] in PLACE_KINDS, 'bad_value', f'{wp}.kind: one of {PLACE_KINDS}')
            if 'room' in p:
                ident(p['room'], f'{wp}.room')
                self.rooms.setdefault(p['room'], []).append(i)
            num(p.get('yaw', 0), f'{wp}.yaw', 0, 360)
            need(p.get('pose', 'stand') in POSES, 'bad_value', f'{wp}.pose: one of {POSES}')
            if p['kind'] == 'work':
                need('kks' in p, 'missing_key', f'{wp}.kks: a work place names its equipment')
                self.m.kks_ref(p['kks'], f'{wp}.kks')
                self.work_at.setdefault(p['kks'], i)
            else:
                need('kks' not in p, 'unknown_key', f'{wp}.kks: only on a work place')
            if p['kind'] == 'point':
                self.point_no[i] = len(self.points)
                self.points.append(i)
            self.pix[p['id']] = i
            self.places.append(p)
        need(len(self.points) <= MAX['points'], 'limit', f'{w}: over {MAX["points"]} points')
        need(self.points, 'bad_ref', f'{w}: the walking network has no point')
        self.door = {r: next((i for i in ix if self.places[i]['kind'] == 'door'), None) for r, ix in self.rooms.items()}

    def place_ref(self, x, where):
        need(isinstance(x, str) and x in self.pix, 'bad_ref', f'{where}: no place {x!r}')
        return self.pix[x]

    def check_ways(self, ways):
        w = 'staff.json.ways'
        lst(ways, w)
        need(len(ways) <= MAX['ways'], 'limit', f'{w}: over {MAX["ways"]}')
        self.ways = {}                              # (a, b) -> steps, both directions
        self.adj = [[] for _ in self.points]        # point number -> [(point number, steps)]
        self.stub = {}                              # non-point place -> (its point, steps)
        for i, x in enumerate(ways):
            wi = f'{w}[{i}]'
            lst(x, wi, 4, 4)
            a, b = self.place_ref(x[0], f'{wi}[0]'), self.place_ref(x[1], f'{wi}[1]')
            need(a != b, 'bad_ref', f'{wi}: a way joins two places')
            metres = num(x[2], f'{wi}[2]', 0, 1e5)
            need(metres > 0, 'bad_number', f'{wi}[2]: metres > 0')
            need(x[3] != 'drive', 'unknown_key', f'{wi}[3]: drive ways come with vehicles (milestone S4)')
            need(x[3] in WALK_MODES, 'bad_value', f'{wi}[3]: one of {WALK_MODES}')
            pa, pb = self.places[a]['at'], self.places[b]['at']
            need(metres + 1e-9 >= math.dist(pa, pb), 'bad_way',
                 f'{wi}: {metres} m is shorter than the straight line between its places ({math.dist(pa, pb):.3f} m)')
            key = (min(a, b), max(a, b))
            need(key not in self.ways, 'dup_id', f'{wi}: a second way between {x[0]} and {x[1]}')
            st = way_steps(metres, self.speeds[x[3]])
            self.ways[key] = st
            ia, ib = a in self.point_no, b in self.point_no
            if ia and ib:
                self.adj[self.point_no[a]].append((self.point_no[b], st))
                self.adj[self.point_no[b]].append((self.point_no[a], st))
            else:
                need(ia or ib, 'bad_ref', f'{wi}: a way joins a point to a point or a place to its point')
                p, q = (b, a) if ia else (a, b)
                need(p not in self.stub, 'bad_ref', f'{wi}: {self.places[p]["id"]} has a second way (a place other '
                                                    f'than a point has exactly one, to a point)')
                self.stub[p] = (q, st)
        for i, p in enumerate(self.places):
            need(i in self.point_no or i in self.stub, 'bad_ref', f'staff.json: place {p["id"]} has no way to a point')

    def check_next(self, nx):
        w = 'staff.json.next'
        n = len(self.points)
        lst(nx, w, n, n)
        for i, row in enumerate(nx):
            lst(row, f'{w}[{i}]', n, n)
            for x in row:
                need(isinstance(x, int) and not isinstance(x, bool), 'bad_number', f'{w}[{i}]: point indexes')
        want = next_table(n, self.adj)
        for i in range(n):
            for j in range(n):
                need(nx[i][j] == want[i][j], 'bad_ref', f'{w}[{i}][{j}]: {nx[i][j]}, the route\'s rule gives '
                                                        f'{want[i][j]} (§16.2)')
        self.next = nx

    def check_reach(self):
        o = self.origin
        start = self.point_no[o] if o in self.point_no else self.point_no[self.stub[o][0]]
        for j, pi in enumerate(self.points):
            need(j == start or self.next[start][j] >= 0, 'unreachable',
                 f'staff.json: place {self.places[pi]["id"]} is not reached on foot from {self.places[o]["id"]}')

    # --- roles, rosters, people
    def check_roles(self, roles):
        w = 'staff.json.roles'
        lst(roles, w, 1)
        need(len(roles) <= MAX['roles'], 'limit', f'{w}: over {MAX["roles"]}')
        self.roles, self.role_ix = {}, {}
        for i, r in enumerate(roles):
            wr = f'{w}[{i}]'
            need(not isinstance(r, dict) or 'off' not in r, 'unknown_key', f'{wr}.off: off-duty routines come with '
                                                                           f'milestone S4')
            keys(r, ('id', 'title', 'discipline', 'authority', 'routine', 'play'), ('look', 'ppe'), wr)
            ident(r['id'], f'{wr}.id')
            need(r['id'] not in self.roles, 'dup_id', f'{wr}: role {r["id"]} twice')
            need(isinstance(r['title'], str) and 1 <= len(r['title']) <= 60, 'bad_type', f'{wr}.title')
            need(r['discipline'] in ROLE_DISCIPLINES, 'bad_value', f'{wr}.discipline: one of {ROLE_DISCIPLINES}')
            for a in lst(r['authority'], f'{wr}.authority', 0, len(AUTHORITIES)):
                need(a in AUTHORITIES, 'bad_value', f'{wr}.authority: {a!r} is not one of {AUTHORITIES}')
            need(len(set(r['authority'])) == len(r['authority']), 'dup_id', f'{wr}.authority')
            for a in lst(r.get('ppe', []), f'{wr}.ppe', 0, len(PPE)):
                need(a in PPE, 'bad_value', f'{wr}.ppe: one of {PPE}')
            if 'look' in r:
                ident(r['look'], f'{wr}.look')
            ident(r['routine'], f'{wr}.routine')
            need(isinstance(r['play'], bool), 'bad_type', f'{wr}.play: true or false')
            self.role_ix[r['id']] = i
            self.roles[r['id']] = r
        self.role_list = roles

    def check_rosters(self, rosters):
        w = 'staff.json.rosters'
        lst(rosters, w, 1)
        need(len(rosters) <= MAX['rosters'], 'limit', f'{w}: over {MAX["rosters"]}')
        self.rosters = {}
        for i, r in enumerate(rosters):
            wr = f'{w}[{i}]'
            need(isinstance(r, dict), 'bad_type', wr)
            if r.get('kind') == 'rotation':
                keys(r, ('id', 'kind', 'cycle', 'crews', 'hours'), (), wr)
                lst(r['cycle'], f'{wr}.cycle', 1, 64)
                need(isinstance(r['crews'], dict) and r['crews'], 'bad_type', f'{wr}.crews')
                for c, off in r['crews'].items():
                    ident(c, f'{wr}.crews')
                    need(isinstance(off, int) and not isinstance(off, bool) and 0 <= off < len(r['cycle']),
                         'bad_number', f'{wr}.crews.{c}: a position in the cycle')
                need(isinstance(r['hours'], dict), 'bad_type', f'{wr}.hours')
                for code, h in r['hours'].items():
                    lst(h, f'{wr}.hours.{code}', 2, 2)
                    hhmm(h[0], f'{wr}.hours.{code}')
                    hhmm(h[1], f'{wr}.hours.{code}')
                for code in r['cycle']:
                    need(isinstance(code, str) and 1 <= len(code) <= 8, 'bad_type', f'{wr}.cycle')
            else:
                keys(r, ('id', 'kind', 'days', 'hours'), (), wr)
                need(r['kind'] == 'days', 'bad_value', f'{wr}.kind: rotation or days')
                for x in lst(r['days'], f'{wr}.days', 1, 7):
                    need(x in WEEK, 'bad_value', f'{wr}.days: of {WEEK}')
                need(len(set(r['days'])) == len(r['days']), 'dup_id', f'{wr}.days')
                lst(r['hours'], f'{wr}.hours', 2, 2)
                hhmm(r['hours'][0], f'{wr}.hours')
                hhmm(r['hours'][1], f'{wr}.hours')
            ident(r['id'], f'{wr}.id')
            need(r['id'] not in self.rosters, 'dup_id', f'{wr}: roster {r["id"]} twice')
            self.rosters[r['id']] = r

    def check_people(self, people):
        w = 'staff.json.people'
        lst(people, w, 1)
        need(len(people) <= MAX['people'], 'limit', f'{w}: over {MAX["people"]}')
        self.people, self.person_ix = people, {}
        for i, p in enumerate(people):
            wp = f'{w}[{i}]'
            need(not isinstance(p, dict) or 'home' not in p, 'unknown_key', f'{wp}.home: homes come with the camp '
                                                                           f'(milestone S4)')
            keys(p, ('id', 'role', 'roster', 'call'), ('crew', 'routine'), wp)
            ident(p['id'], f'{wp}.id')
            need(p['id'] not in self.person_ix and p['id'] not in self.roles, 'dup_id',
                 f'{wp}: {p["id"]} is already a person or a role')
            need(p['role'] in self.roles, 'bad_ref', f'{wp}.role: no role {p["role"]!r}')
            need(p['roster'] in self.rosters, 'bad_ref', f'{wp}.roster: no roster {p["roster"]!r}')
            ro = self.rosters[p['roster']]
            if ro['kind'] == 'rotation':
                need(p.get('crew') in ro['crews'], 'bad_ref', f'{wp}.crew: one of {list(ro["crews"])}')
            else:
                need('crew' not in p, 'unknown_key', f'{wp}.crew: only in a rotation')
            need(isinstance(p['call'], str) and 1 <= len(p['call']) <= 32, 'bad_type', f'{wp}.call: 1–32 characters')
            self.person_ix[p['id']] = i

    # --- routines and tasks
    def at_ref(self, x, where, until=False):
        """A slot's `at` (or `until`): ('start' | 'end', signed minutes) or ('clock', minutes)."""
        m = OFFSET.fullmatch(x) if isinstance(x, str) else None
        if m:
            mins = int(m.group(3)) * 60 + int(m.group(4))
            need(mins <= 720, 'bad_clock', f'{where}: at most ±12:00')
            return (m.group(1), mins if m.group(2) == '+' else -mins)
        return ('clock', hhmm(x, where))

    def check_routines(self, routines):
        w = 'staff.json.routines'
        lst(routines, w, 1)
        need(len(routines) <= MAX['routines'], 'limit', f'{w}: over {MAX["routines"]}')
        self.routines = {}
        for i, r in enumerate(routines):
            wr = f'{w}[{i}]'
            keys(r, ('id', 'slots', 'idle'), (), wr)
            ident(r['id'], f'{wr}.id')
            need(r['id'] not in self.routines, 'dup_id', f'{wr}: routine {r["id"]} twice')
            need(r['idle'] in self.tasks, 'bad_ref', f'{wr}.idle: no task {r["idle"]!r}')
            slots = []
            for k, s in enumerate(lst(r['slots'], f'{wr}.slots', 0, 64)):
                ws = f'{wr}.slots[{k}]'
                keys(s, ('at', 'task'), ('every', 'until'), ws)
                need(s['task'] in self.tasks, 'bad_ref', f'{ws}.task: no task {s["task"]!r}')
                at = self.at_ref(s['at'], f'{ws}.at')
                every = until = None
                if 'every' in s or 'until' in s:
                    need('every' in s and 'until' in s, 'missing_key', f'{ws}: every and until go together')
                    mm = DUR.fullmatch(s['every']) if isinstance(s['every'], str) else None
                    need(mm is not None, 'bad_clock', f'{ws}.every: H:MM')
                    every = int(mm.group(1)) * 60 + int(mm.group(2))
                    need(0 < every <= 1440, 'bad_clock', f'{ws}.every: more than 0:00, at most 24:00')
                    until = self.at_ref(s['until'], f'{ws}.until')
                slots.append((at, every, until, s['task']))
            self.routines[r['id']] = {'slots': slots, 'idle': r['idle']}
        for rid, r in self.roles.items():
            need(r['routine'] in self.routines, 'bad_ref', f'staff.json: role {rid}.routine: no routine '
                                                         f'{r["routine"]!r}')
        for p in self.people:
            if 'routine' in p:
                need(p['routine'] in self.routines, 'bad_ref', f'staff.json: person {p["id"]}.routine: no routine '
                                                              f'{p["routine"]!r}')

    def routine_of(self, i):
        """A person's routine: their own `routine` (§17.8), else their role's."""
        p = self.people[i]
        return self.routines[p.get('routine', self.roles[p['role']]['routine'])]

    def work_ref(self, x, where, dollar=True):
        need(isinstance(x, str) and (x == '$' and dollar or x in {w['id'] for w in self.m.works}), 'bad_ref',
             f'{where}: no work {x!r}')
        return x

    def check_task(self, t):
        w = f'staff.json: task {t["id"]}'
        keys(t, ('id', 'title', 'steps'), ('priority', 'interruptible', 'work'), w)
        need(isinstance(t['title'], str) and 1 <= len(t['title']) <= 120, 'bad_type', f'{w}.title')
        pr = t.get('priority', 3)
        need(isinstance(pr, int) and not isinstance(pr, bool) and 1 <= pr <= 5, 'bad_number', f'{w}.priority: 1–5')
        need(isinstance(t.get('interruptible', True), bool), 'bad_type', f'{w}.interruptible')
        if 'work' in t:
            self.work_ref(t['work'], f'{w}.work', False)
        steps = lst(t['steps'], f'{w}.steps', 1, MAX['task_steps'])
        desk = False
        for i, s in enumerate(steps):
            ws = f'{w}.steps[{i}]'
            need(isinstance(s, dict), 'bad_type', ws)
            for k, ms in LATER.items():
                need(k not in s, 'unknown_key', f'{ws}.{k}: not before milestone {ms} (PLANT3D.md §17.8)')
            need('unsafe' not in s, 'unknown_key', f'{ws}.unsafe: unsafe acts come with milestone S2')
            kinds = [k for k in STEP_KINDS if k in s]
            need(len(kinds) == 1, 'bad_kind', f'{ws}: exactly one of {STEP_KINDS}')
            k = kinds[0]
            x = s[k]
            if k == 'go':
                keys(s, ('go',), ('else',), ws)
                p = self.go_target(x, ws)
                if p is not None:
                    desk = desk or self.places[p]['kind'] == 'desk'
                elif isinstance(x, dict) and x.get('kind') == 'desk':
                    desk = True
            elif k == 'work':
                keys(s, ('work',), ('anim', 'tool'), ws)
                self.minutes(x, f'{ws}.work')
                for a in ('anim', 'tool'):
                    if a in s:
                        ident(s[a], f'{ws}.{a}')
            elif k == 'read':
                keys(s, ('read',), ('expect', 'tol', 'test'), ws)
                need(isinstance(x, str) and x in self.m_show(), 'bad_ref', f'{ws}.read: {x!r} has no show binding')
                if 'expect' in s:
                    lst(s['expect'], f'{ws}.expect', 2, 2)
                    num(s['expect'][0], f'{ws}.expect')
                    num(s['expect'][1], f'{ws}.expect', s['expect'][0])
                num(s.get('tol', 0), f'{ws}.tol', 0)
                need(s.get('test', 'gas') == 'gas', 'bad_value', f'{ws}.test: gas')
            elif k == 'op':
                keys(s, ('op',), ('else',), ws)
                keys(x, ('kks', 'do', 'where'), ('value', 'trip'), f'{ws}.op')
                o = self.m.op_keys.get((x['kks'], x['do'], x.get('trip')))
                need(o is not None, 'bad_ref', f'{ws}.op: no op {x["do"]!r} on {x["kks"]!r}')
                need(x['where'] in o['where'], 'bad_value', f'{ws}.op.where: one of the op\'s own {o["where"]}')
                need(x['where'] != 'screen' or desk, 'bad_ref', f'{ws}.op: a screen op comes after a go to a desk')
                if 'value' in x:
                    num(x['value'], f'{ws}.op.value')
            elif k == 'permit':
                keys(s, ('permit',), ('else',), ws)
                keys(x, ('work', 'action'), (), f'{ws}.permit')
                self.work_ref(x['work'], f'{ws}.permit.work')
                need(x['action'] in PERMIT_AUTH, 'bad_value', f'{ws}.permit.action: one of {list(PERMIT_AUTH)}')
            elif k in ('lock', 'unlock'):
                keys(s, (k,), ('else',), ws)
                keys(x, ('work', 'point'), (), f'{ws}.{k}')
                self.work_ref(x['work'], f'{ws}.{k}.work')
                pt = x['point']
                need(pt == 'all' or isinstance(pt, int) and not isinstance(pt, bool) and 0 <= pt < 16, 'bad_value',
                     f'{ws}.{k}.point: a point index or "all"')
            elif k == 'say':
                keys(s, ('say', 'to'), (), ws)
                need(x in self.messages, 'bad_ref', f'{ws}.say: no message {x!r}')
                to = s['to']
                need(to == 'channel' or to in self.roles or to in self.person_ix, 'bad_ref',
                     f'{ws}.to: a role, a person or "channel"')
            elif k == 'wait':
                keys(s, ('wait',), (), ws)
                need(isinstance(x, dict), 'bad_type', f'{ws}.wait')
                if 'until' in x:
                    keys(x, ('until',), ('minutes', 'else'), f'{ws}.wait')
                    self.m.cond(x['until'], f'{ws}.wait.until')
                else:
                    keys(x, ('permit',), ('minutes', 'else'), f'{ws}.wait')
                    lst(x['permit'], f'{ws}.wait.permit', 2, 2)
                    self.work_ref(x['permit'][0], f'{ws}.wait.permit')
                    need(x['permit'][1] in STATE_NAMES[1:10], 'bad_value', f'{ws}.wait.permit: a state requested '
                                                                           f'to closed')
                if 'minutes' in x:
                    self.minutes(x['minutes'], f'{ws}.wait.minutes', 1)
                if 'else' in x:
                    self.else_ref(x['else'], i, len(steps), f'{ws}.wait.else')
            elif k == 'call':
                keys(s, ('call',), (), ws)
                keys(x, ('role', 'task'), ('work',), f'{ws}.call')
                need(x['role'] in self.roles, 'bad_ref', f'{ws}.call.role: no role {x["role"]!r}')
                need(x['task'] in self.tasks, 'bad_ref', f'{ws}.call.task: no task {x["task"]!r}')
                if 'work' in x:
                    self.work_ref(x['work'], f'{ws}.call.work')
            elif k == 'meet':
                keys(s, ('meet',), (), ws)
                keys(x, ('room', 'with', 'minutes'), (), f'{ws}.meet')
                need(x['room'] in self.rooms, 'bad_ref', f'{ws}.meet.room: no room {x["room"]!r}')
                need(self.door.get(x['room']) is not None, 'bad_ref', f'{ws}.meet.room: room {x["room"]!r} has no door')
                for r in lst(x['with'], f'{ws}.meet.with', 0, 8):
                    need(r in self.roles, 'bad_ref', f'{ws}.meet.with: no role {r!r}')
                self.minutes(x['minutes'], f'{ws}.meet.minutes')
            elif k == 'choose':
                keys(s, ('choose',), (), ws)
                tot = 0
                for c in lst(x, f'{ws}.choose', 1, 16):
                    lst(c, f'{ws}.choose', 2, 2)
                    need(isinstance(c[0], int) and not isinstance(c[0], bool) and c[0] >= 1, 'bad_number',
                         f'{ws}.choose: weights are whole numbers ≥ 1')
                    need(c[1] in self.tasks, 'bad_ref', f'{ws}.choose: no task {c[1]!r}')
                    tot += c[0]
                need(tot <= 65536, 'bad_number', f'{ws}.choose: weights total at most 65536')
            elif k == 'ack':
                keys(s, ('ack',), (), ws)
                need(x == '$', 'bad_value', f'{ws}.ack: "$" (the alarm the task was given for)')
            if 'else' in s:
                self.else_ref(s['else'], i, len(steps), f'{ws}.else')
        self.m.finish()

    def m_show(self):
        if not hasattr(self, '_show'):
            self._show = {}
            for x in self.m.bind:
                if 'show' in x:
                    self._show.setdefault(x['kks'], x['show'])
        return self._show

    def minutes(self, x, where, lo=0):
        if isinstance(x, list):
            lst(x, where, 2, 2)
            for v in x:
                need(isinstance(v, int) and not isinstance(v, bool) and lo <= v <= 1440, 'bad_number', where)
            need(x[0] <= x[1], 'bad_number', f'{where}: [min, max]')
        else:
            need(isinstance(x, int) and not isinstance(x, bool) and lo <= x <= 1440, 'bad_number',
                 f'{where}: whole clock minutes')

    def else_ref(self, x, i, n, where):
        need(isinstance(x, int) and not isinstance(x, bool) and i < x < n, 'bad_ref',
             f'{where}: a later step of the task (an index)')

    def go_target(self, x, where):
        """A go's target: a place index, or None for {"kks": "$"} and {"kind", "room"}."""
        if isinstance(x, str):
            need(x != 'home', 'unknown_key', f'{where}.go: "home" comes with the camp (milestone S4)')
            return self.place_ref(x, f'{where}.go')
        need(isinstance(x, dict), 'bad_type', f'{where}.go')
        if 'kks' in x:
            keys(x, ('kks',), (), f'{where}.go')
            if x['kks'] == '$':
                return None
            need(x['kks'] in self.work_at, 'bad_ref', f'{where}.go: {x["kks"]!r} has no work place')
            return self.work_at[x['kks']]
        keys(x, ('kind', 'room'), (), f'{where}.go')
        need(x['kind'] in PLACE_KINDS, 'bad_value', f'{where}.go.kind')
        need(any(self.places[i]['kind'] == x['kind'] for i in self.rooms.get(x['room'], [])), 'bad_ref',
             f'{where}.go: no {x["kind"]} in room {x["room"]!r}')
        return None

    def meet_place(self, room, taken):
        """A meeting's place: the room's first free seat, desk or table in place order, else its door."""
        for i in self.rooms.get(room, []):
            if self.places[i]['kind'] in ('seat', 'desk', 'table') and i not in taken:
                return i
        return self.door.get(room)

    def check_reactions(self, rs):
        w = 'staff.json.reactions'
        lst(rs, w)
        need(len(rs) <= MAX['reactions'], 'limit', f'{w}: over {MAX["reactions"]}')
        self.reactions = rs
        values = self.m.known()
        trips = {t['id'] for t in self.m.trips}
        for i, r in enumerate(rs):
            wr = f'{w}[{i}]'
            need(not isinstance(r, dict) or 'seen' not in r, 'unknown_key', f'{wr}.seen: with unsafe acts (S2)')
            keys(r, ('on', 'roles', 'task'), ('priority', 'work'), wr)
            on = r['on']
            need(isinstance(on, dict) and len(on) == 1, 'bad_kind', f'{wr}.on: one of alarm, trip, fault, value, '
                                                                   f'permit')
            k, v = next(iter(on.items()))
            need(k != 'unsafe', 'unknown_key', f'{wr}.on.unsafe: unsafe acts come with milestone S2')
            if k == 'alarm':
                need(v in (1, 2, 3) and not isinstance(v, bool), 'bad_value', f'{wr}.on.alarm: 1, 2 or 3')
            elif k == 'trip':
                need(v == '*' or v in trips, 'bad_ref', f'{wr}.on.trip: "*" or a trip')
            elif k == 'fault':
                ident(v, f'{wr}.on.fault')
            elif k == 'value':
                need(v in values, 'bad_ref', f'{wr}.on.value: no value {v!r}')
            elif k == 'permit':
                need(v in STATE_NAMES[1:], 'bad_value', f'{wr}.on.permit: a permit state from requested')
            else:
                need(False, 'bad_kind', f'{wr}.on: one of alarm, trip, fault, value, permit')
            for ro in lst(r['roles'], f'{wr}.roles', 1, 16):
                need(ro in self.roles, 'bad_ref', f'{wr}.roles: no role {ro!r}')
            need(r['task'] in self.tasks, 'bad_ref', f'{wr}.task: no task {r["task"]!r}')
            if 'priority' in r:
                need(r['priority'] in (1, 2, 3, 4, 5) and not isinstance(r['priority'], bool), 'bad_number',
                     f'{wr}.priority: 1–5')
            if 'work' in r:
                self.work_ref(r['work'], f'{wr}.work', False)

    def check_task_refs(self):
        """No task reaches itself through choose or call; idle tasks take time (so no one loops within a step)."""
        def edges(t):
            for s in t['steps']:
                if 'choose' in s:
                    for _, x in s['choose']:
                        yield x
                if 'call' in s:
                    yield s['call']['task']
        state = {}

        def visit(tid, path):
            if state.get(tid) == 2:
                return
            need(state.get(tid) != 1, 'bad_ref', f'staff.json: task {tid} reaches itself ({" → ".join(path)})')
            state[tid] = 1
            for x in edges(self.tasks[tid]):
                visit(x, path + [x])
            state[tid] = 2
        for tid in self.tasks:
            visit(tid, [tid])
        for rid, r in self.routines.items():
            t = self.tasks[r['idle']]
            need(any(('work' in s and (s['work'][0] if isinstance(s['work'], list) else s['work']) >= 1)
                     or 'wait' in s or 'meet' in s for s in t['steps']), 'bad_ref',
                 f'staff.json: routine {rid}\'s idle task {r["idle"]} has no step that takes time')

    def check_authority(self):
        """Each step of a task can be done by every role that may run it (`authority`): the roles whose routine
        names it, the reactions' roles and the calls' roles, and through `choose` the same roles."""
        runs = {t: set() for t in self.tasks}
        works = {t: set() for t in self.tasks}       # the works "$" can be in a task
        for rid, r in self.roles.items():
            ro = self.routines[r['routine']]
            for s in ro['slots']:
                runs[s[3]].add(rid)
            runs[ro['idle']].add(rid)
        for i, p in enumerate(self.people):
            ro = self.routine_of(i)
            for s in ro['slots']:
                runs[s[3]].add(p['role'])
            runs[ro['idle']].add(p['role'])
        for r in self.reactions:
            for ro in r['roles']:
                runs[r['task']].add(ro)
            if 'work' in r:
                works[r['task']].add(r['work'])
            elif 'permit' in r['on']:
                works[r['task']].update(w['id'] for w in self.m.works)
        for t in self.tasks.values():
            if 'work' in t:
                works[t['id']].add(t['work'])
        for w in self.m.works:
            if w.get('task') in works:
                works[w['task']].add(w['id'])
        changed = True
        while changed:
            changed = False
            for t in self.tasks.values():
                for s in t['steps']:
                    targets = []
                    if 'choose' in s:
                        targets = [(x, runs[t['id']], works[t['id']]) for _, x in s['choose']]
                    if 'call' in s:
                        c = s['call']
                        wk = works[t['id']] if c.get('work', '$') == '$' else {c['work']}
                        if 'work' not in c:
                            wk = works[t['id']]
                        targets = [(c['task'], {c['role']}, wk)]
                    for x, rs, wk in targets:
                        if not rs <= runs[x] or not wk <= works[x]:
                            runs[x] |= rs
                            works[x] |= wk
                            changed = True
        wmap = {w['id']: w for w in self.m.works}
        isos = {x['id']: x for x in self.m.isolations}
        self.callable = set()
        for t in self.tasks.values():
            for s in t['steps']:
                if 'call' in s:
                    self.callable.add((s['call']['role'], s['call']['task']))
        for tid, t in self.tasks.items():
            for i, s in enumerate(t['steps']):
                ws = f'staff.json: task {tid}.steps[{i}]'
                for rid in sorted(runs[tid]):
                    auth = self.roles[rid]['authority']
                    if 'op' in s:
                        a = 'operate_screen' if s['op']['where'] == 'screen' else 'operate_local'
                        need(a in auth, 'authority', f'{ws}: role {rid} lacks {a}')
                    if 'permit' in s:
                        a = PERMIT_AUTH[s['permit']['action']]
                        need(a in auth, 'authority', f'{ws}: role {rid} lacks {a}')
                        if a == 'accept':
                            for wid in self.step_works(s['permit']['work'], works[tid]):
                                need(wmap[wid]['discipline'] == self.roles[rid]['discipline'], 'authority',
                                     f'{ws}: role {rid} is not of work {wid}\'s discipline')
                    for k in ('lock', 'unlock'):
                        if k in s:
                            for wid in self.step_works(s[k]['work'], works[tid]):
                                iso = wmap[wid].get('isolation')
                                need(iso is not None, 'bad_ref', f'{ws}: work {wid} has no isolation')
                                pts = isos[iso]['points']
                                pt = s[k]['point']
                                need(pt == 'all' or pt < len(pts), 'bad_ref', f'{ws}: no point {pt} in {iso}')
                                for p in (pts if pt == 'all' else [pts[pt]]):
                                    need(f'lock_{p["kind"]}' in auth, 'authority',
                                         f'{ws}: role {rid} lacks lock_{p["kind"]}')
                for k in ('permit', 'lock', 'unlock'):
                    if k in s and s[k]['work'] == '$':
                        need(works[tid], 'bad_ref', f'{ws}: "$" but no work is ever given to task {tid}')
                if 'wait' in s and 'permit' in s['wait'] and s['wait']['permit'][0] == '$':
                    need(works[tid], 'bad_ref', f'{ws}: "$" but no work is ever given to task {tid}')
        self.runs = runs

    def step_works(self, w, given):
        return sorted(given) if w == '$' else [w]


def check_scenario_staff(s, b, rel):
    """A scenario's `staff` and `start` (§14)."""
    st = b.staff
    if 'start' in s:
        check_start(s['start'], f'{rel}.start')
    if 'staff' not in s:
        return
    need(st is not None, 'bad_ref', f'{rel}.staff: the plant has no staff.json')
    x = s['staff']
    keys(x, ('seed',), ('trainee', 'absent'), f'{rel}.staff')
    need(isinstance(x['seed'], int) and not isinstance(x['seed'], bool) and 0 <= x['seed'] < 2 ** 32, 'bad_number',
         f'{rel}.staff.seed: a whole number from 0 to 2^32 − 1')
    absent = lst(x.get('absent', []), f'{rel}.staff.absent')
    for a in absent:
        need(a in st.person_ix, 'bad_ref', f'{rel}.staff.absent: no person {a!r}')
    need(len(set(absent)) == len(absent), 'dup_id', f'{rel}.staff.absent')
    t = x.get('trainee')
    if t is not None:
        need(t in st.person_ix, 'bad_ref', f'{rel}.staff.trainee: no person {t!r}')
        need(st.roles[st.people[st.person_ix[t]]['role']]['play'], 'bad_ref', f'{rel}.staff.trainee: a role that '
                                                                            f'is not played')
        need(t not in absent, 'bad_ref', f'{rel}.staff.trainee: absent')


# ---------------------------------------------------------------- the staff step (§17)

class Person:
    __slots__ = ('i', 'id', 'role', 'auth', 'rng', 'on', 'duty', 'duties', 'planned', 'slots', 'pos', 'leg',
                 'cur', 'queue', 'res', 'occ', 'pending', 'result')



class StaffRun:
    """The staff's state in a run, stepped by the engine's step 9 (§17). The engine calls `place(clock)` at step 0,
    `inputs(...)` in step 1 and `step()` as step 9; NPCs' inputs go to engine.npc_queue for the next step."""

    def __init__(self, e, st, scen):
        self.e, self.st = e, st
        x = scen['staff']
        self.seed = x['seed']
        self.absent = set(x.get('absent', []))
        self.trainee = st.person_ix[x['trainee']] if x.get('trainee') is not None else None
        self.fixed_trainee = self.trainee is not None
        self.people = []
        for i, p in enumerate(st.people):
            q = Person()
            q.i, q.id, q.role = i, p['id'], p['role']
            q.auth = st.roles[p['role']]['authority']
            q.rng = seed_of(self.seed, i)
            q.on, q.duty, q.duties, q.planned, q.slots = False, None, [], None, []
            q.pos, q.leg, q.cur, q.queue, q.res, q.occ, q.pending, q.result = None, None, None, [], None, None, \
                None, None
            self.people.append(q)
        self.order = 0                  # instances made, for the queue's order
        self.unacked = 0
        self.t_at = None                # the trainee's place (arrive/leave)
        self.t_in = []                  # the trainee's inputs for step 9: (kind, …)
        self.jumped = None              # (old clock, new clock) of a jump in this step
        self.holder = {}                # reserved or occupied place -> person index
        self.given = {}                 # (reaction index, source) -> instance count still queued or current
        self.vprev = [e.truth(r['on']['value']) if 'value' in r['on'] else None for r in st.reactions]

    def copy(self, e):
        """An independent copy for a clone of the engine (the content is shared)."""
        return copy.deepcopy(self, {id(self.e): e, id(self.st): self.st})

    # --- the clock and duties
    def clock(self):
        return self.e.clock()

    def duty_on_day(self, p, d):
        """The person's duty that belongs to day d: (start, end) in tenths, or None."""
        st = self.st
        pp = st.people[p.i]
        ro = st.rosters[pp['roster']]
        if ro['kind'] == 'rotation':
            code = ro['cycle'][(d - 1 + ro['crews'][pp['crew']]) % len(ro['cycle'])]
            h = ro['hours'].get(code)
        else:
            h = ro['hours'] if st.week[(d - 1) % 7] in ro['days'] else None
        if h is None:
            return None
        a, b = hhmm(h[0], ''), hhmm(h[1], '')
        s = (d * 1440 + a) * MINUTE
        e = (d * 1440 + b) * MINUTE
        if e <= s:
            e += DAY
        return (s, e)

    def slot_times(self, p, duty):
        """The slots of a duty: [(time, slot index, repetition, task)] in time order, then slot order."""
        r = self.st.routine_of(p.i)
        out = []

        def resolve(at):
            if at[0] == 'start':
                return duty[0] + at[1] * MINUTE
            if at[0] == 'end':
                return duty[1] + at[1] * MINUTE
            t = (duty[0] // DAY) * DAY + at[1] * MINUTE
            return t if t >= duty[0] else t + DAY
        for k, (at, every, until, task) in enumerate(r['slots']):
            t = resolve(at)
            if every is None:
                out.append((t, k, 0, task))
            else:
                u = resolve(until)
                n = 0
                while t <= u:
                    out.append((t, k, n, task))
                    t += every * MINUTE
                    n += 1
        out.sort(key=lambda x: (x[0], x[1], x[2]))
        return out

    def plan(self, p, upto):
        """Plans the duties of days up to `upto` (and their slots)."""
        d0 = p.planned + 1
        for d in range(d0, upto + 1):
            du = self.duty_on_day(p, d)
            if du is not None:
                p.duties.append(du)
                for t, k, n, task in self.slot_times(p, du):
                    p.slots.append((t, du[0], k, n, task, du))
        p.slots.sort(key=lambda x: x[:4])
        p.planned = upto

    def place_all(self, c, old=None):
        """Placement (§17.2): at step 0 and after a jump, at clock c."""
        st = self.st
        day = c // DAY
        self.holder = {}
        self.given = {}
        for p in self.people:
            p.duties, p.slots, p.planned = [], [], day - 3
            p.cur, p.queue, p.leg, p.res, p.occ, p.pending, p.result = None, [], None, None, None, None, None
            p.pos = None
            p.on, p.duty = False, None
            if p.id in self.absent:
                continue
            self.plan(p, day + 1)
            for du in p.duties:
                if du[0] <= c < du[1]:
                    p.on, p.duty = True, du
            p.duties = [du for du in p.duties if du[1] > c and du is not p.duty]
            pick = None
            for s in p.slots:
                if s[0] <= c and p.duty is not None and s[5] == p.duty and s[0] >= p.duty[0]:
                    pick = s
            if old is not None:
                for s in p.slots:
                    if old < s[0] < c:
                        self.e.ev('task', p.id, s[4], 'skipped')
            p.slots = [s for s in p.slots if s[0] > c]
            if not p.on:
                continue
            if pick is not None:
                task = pick[4]
            else:
                task = None
            place = self.first_place(task) if task is not None else None
            idle = st.routine_of(p.i)['idle']
            if place is None:
                place = self.first_place(idle)
            if place is None:
                place = st.origin
            p.pos = place
            if st.places[place]['kind'] not in OPEN_KINDS and place not in self.holder:
                self.holder[place] = p.i
                p.occ = place
            if task is not None:
                self.give(p, task, st.tasks[task].get('priority', 3), None, None, None, None, count=False)
        if self.trainee is not None:
            self.t_at = self.people[self.trainee].pos

    def first_place(self, tid):
        st = self.st
        for s in st.tasks[tid]['steps']:
            if 'go' in s:
                x = s['go']
                if isinstance(x, str):
                    return st.pix[x]
                if 'kks' in x:
                    if x['kks'] == '$':
                        continue
                    return st.work_at[x['kks']]
                return self.free_of(x['kind'], x['room'], None)
            if 'meet' in s:
                return st.meet_place(s['meet']['room'], self.holder)
        return None

    def free_of(self, kind, room, who):
        st = self.st
        first = None
        for i in st.rooms.get(room, []):
            if st.places[i]['kind'] == kind:
                if first is None:
                    first = i
                if kind in OPEN_KINDS or self.holder.get(i, who) == who:
                    return i
        return None

    # --- giving tasks (§17.3)
    def give(self, p, tid, prio, made_by, work, code, alarm, count=True):
        """Queues an instance of task tid for person p; returns False (event unassigned) when the queue is full."""
        if len(p.queue) + (1 if p.cur is not None and not p.cur['idle'] else 0) >= MAX['queue']:
            self.e.ev('task', None, tid, 'unassigned')
            return False
        t = self.st.tasks[tid]
        if work is None and t.get('work') is not None:
            work = t['work']
        inst = {'task': tid, 'prio': prio, 'made': self.e.step_no, 'order': self.order, 'step': 0, 'st': {},
                'work': work, 'code': code, 'alarm': alarm, 'src': made_by, 'idle': False, 'started': False,
                'int': t.get('interruptible', True)}
        self.order += 1
        p.queue.append(inst)
        p.queue.sort(key=lambda q: (q['prio'], q['made'], q['order']))
        if made_by is not None:
            self.given[made_by] = self.given.get(made_by, 0) + 1
        if count and p.i == self.trainee:
            self.unacked += 1
        return True

    def assign(self, roles, tid, prio, made_by, work, code, alarm):
        """Who gets a task (§17.3): the first free on-duty person of its roles (roles in order, then index), else the
        first on-duty one, else nobody."""
        cands = []
        for r in roles:
            for p in self.people:
                if p.role == r and p.on and p.id not in self.absent:
                    cands.append(p)
        if not cands:
            self.e.ev('task', None, tid, 'unassigned')
            return
        for p in cands:
            c = p.cur
            if c is None or c['idle'] or (c['prio'] > prio and c['int']):
                return self.give(p, tid, prio, made_by, work, code, alarm)
        self.give(cands[0], tid, prio, made_by, work, code, alarm)

    def release(self, inst):
        if inst['src'] is not None:
            self.given[inst['src']] -= 1
            if not self.given[inst['src']]:
                del self.given[inst['src']]

    # --- step 1: the trainee's inputs for step 9 (and role, task_ack and jump, handled here)
    def t_input(self, item):
        kind = item[0]
        e = self.e
        if kind == 'role':
            pid = item[1]
            st = self.st
            ok = (e.step_no == 1 and not self.fixed_trainee and self.trainee is None and isinstance(pid, str)
                  and pid in st.person_ix and pid not in self.absent
                  and st.roles[st.people[st.person_ix[pid]]['role']]['play'])
            e.ev('role', pid, 'done' if ok else 'refused')
            if ok:
                self.trainee = st.person_ix[pid]
                self.t_at = self.people[self.trainee].pos
            return
        if kind == 'task_ack':
            self.unacked = 0
            e.ev('task_ack')
            return
        if kind == 'jump':
            self.jump(item[1])
            return
        self.t_in.append(item)

    def jump(self, to):
        e = self.e
        old = e.clock()
        m = HHMM.fullmatch(to) if isinstance(to, str) else None
        if m is None:
            e.ev('jump', old, None, 'refused')
            return
        t = (old // DAY) * DAY + (int(m.group(1)) * 60 + int(m.group(2))) * MINUTE
        while t <= old:
            t += DAY
        ok = self.trainee is None or self.unacked == 0
        ok = ok and e.ff_model() and not any(1 <= s <= 7 for s in e.pstate.values()) and self.jumped is None
        if ok:
            e.J += t - old
            self.jumped = (old, t)
        e.ev('jump', old, t, 'done' if ok else 'refused')

    # --- step 9
    def step(self):
        e = self.e
        n = e.step_no
        c = e.clock()
        st = self.st
        tin, self.t_in = self.t_in, []
        if self.jumped is not None:
            old, new = self.jumped
            self.jumped = None
            for p in self.people:
                for inst in ([p.cur] if p.cur is not None else []) + p.queue:
                    e.ev('task', p.id, inst['task'], 'skipped')
            self.place_all(new, old)
            jump_step = True
        else:
            jump_step = False
        if self.trainee is not None:
            for item in tin:
                tp = self.people[self.trainee]
                if item[0] == 'arrive' and isinstance(item[1], str) and item[1] in st.pix:
                    self.t_at = st.pix[item[1]]
                    tp.pos = self.t_at
                    if tp.occ != self.t_at:
                        self.leave_place(tp)        # a place held is let go when the trainee is elsewhere
                    if tp.res == self.t_at:
                        tp.occ, tp.res = tp.res, None
                elif item[0] == 'leave' and isinstance(item[1], str) and st.pix.get(item[1]) == self.t_at:
                    self.t_at = None
                    tp.pos = None
                    self.leave_place(tp)
        # 1. duties, then slots
        day = c // DAY
        for p in self.people:
            if p.id in self.absent:
                continue
            if p.planned < day + 1:
                self.plan(p, day + 1)
            if p.on and c >= p.duty[1]:
                p.on, p.duty = False, None
                e.ev('duty', p.id, 'off')
            if not p.on:
                while p.duties and p.duties[0][1] <= c:
                    p.duties.pop(0)
                if p.duties and p.duties[0][0] <= c:
                    p.on, p.duty = True, p.duties.pop(0)
                    e.ev('duty', p.id, 'on')
        for p in self.people:
            if p.id in self.absent:
                continue
            while p.slots and p.slots[0][0] <= c:
                s = p.slots.pop(0)
                self.give(p, s[4], st.tasks[s[4]].get('priority', 3), None, None, None, None)
        # 2. reactions
        self.react(n)
        # 4. people
        if not jump_step:
            for p in self.people:
                if p.id in self.absent:
                    continue
                if p.i == self.trainee:
                    self.trainee_turn(p, tin)
                else:
                    self.turn(p)
        for i, r in enumerate(st.reactions):
            if 'value' in r['on']:
                self.vprev[i] = e.truth(r['on']['value'])

    def react(self, n):
        e = self.e
        st = self.st
        evs = [x for x in e.events[e.ev_mark:] if x[0] == n]
        for ri, r in enumerate(st.reactions):
            k, v = next(iter(r['on'].items()))
            prio = r.get('priority', st.tasks[r['task']].get('priority', 3))
            hits = []
            if k == 'value':
                now = e.truth(v)
                if now and self.vprev[ri] is False:
                    hits.append((('value', v), None, None, None))
            else:
                for x in evs:
                    if k == 'alarm' and x[1] == 'alarm' and x[3] == 'active_unack':
                        a = e.alarm_of[x[2]]
                        if a['priority'] <= v:
                            hits.append((('alarm', x[2]), None, a['where'], x[2]))
                    elif k == 'trip' and x[1] == 'trip' and (v == '*' or v == x[2]):
                        hits.append((('trip', x[2]), None, None, None))
                    elif k == 'fault' and x[1] == 'fault' and x[2] == v:
                        hits.append((('fault', v), None, e.faults[v].get('kks'), None))
                    elif k == 'permit' and x[1] == 'permit' and x[5] == 'done':
                        new = x[6][0] if x[3] == 'auto' else PERMIT_TO[x[3]]
                        if STATE_NAMES[new] == v and ('work' not in r or r['work'] == x[2]):
                            hits.append((('permit', x[2]), x[2], e.works[x[2]]['kks'], None))
            for src, work, code, alarm in hits:
                key = (ri,) + src
                if key in self.given:
                    continue
                w = r.get('work', work)
                if code is None and w is not None:
                    code = e.works[w]['kks']
                self.assign(r['roles'], r['task'], prio, key, w, code, alarm)

    # --- a person's turn (phase 4)
    def select(self, p):
        """Starts, resumes or pre-empts the current task; ends the idle task when anything is queued. Returns the
        current instance, or None."""
        e = self.e
        cur = p.cur
        if cur is not None and cur['idle'] and (p.queue or not p.on):
            e.ev('task', p.id, cur['task'], 'done')
            p.cur = cur = None
        if cur is not None and p.queue and cur['int'] and p.queue[0]['prio'] < cur['prio'] \
                and not cur['st'].get('busy'):
            self.pause(p)
            cur = None
        if cur is None and p.queue:
            cur = p.cur = p.queue.pop(0)
            if not cur['started']:
                cur['started'] = True
                e.ev('task', p.id, cur['task'], 'start')
            if p.pos is None and p.i != self.trainee:
                p.pos = self.st.gate
                e.ev('move', p.id, None, self.st.places[p.pos]['id'], e.step_no)
        if cur is None and p.on:
            idle = self.st.routine_of(p.i)['idle']
            cur = p.cur = {'task': idle, 'prio': 6, 'made': e.step_no, 'order': self.order, 'step': 0, 'st': {},
                           'work': None, 'code': None, 'alarm': None, 'src': None, 'idle': True, 'started': True,
                           'int': True}
            self.order += 1
            e.ev('task', p.id, idle, 'start')
            if p.pos is None and p.i != self.trainee:
                p.pos = self.st.gate
                e.ev('move', p.id, None, self.st.places[p.pos]['id'], e.step_no)
        if cur is None and not p.on and p.pos is not None and p.i != self.trainee:
            self.leave_place(p)
            e.ev('move', p.id, self.st.places[p.pos]['id'], None, e.step_no)
            p.pos = None
        return cur

    def pause(self, p):
        cur = p.cur
        st = cur['st']
        for k in ('dest', 'waiting', 'wait_since', 'target', 'meet_since'):
            st.pop(k, None)
        self.unreserve(p)
        p.queue.append(cur)
        p.queue.sort(key=lambda q: (q['prio'], q['made'], q['order']))
        p.cur = None

    def finish(self, p, how):
        cur = p.cur
        self.e.ev('task', p.id, cur['task'], how)
        self.release(cur)
        self.unreserve(p)
        p.cur = None

    def unreserve(self, p):
        if p.res is not None:
            if self.holder.get(p.res) == p.i:
                del self.holder[p.res]
            p.res = None

    def leave_place(self, p):
        if p.occ is not None:
            if self.holder.get(p.occ) == p.i:
                del self.holder[p.occ]
            p.occ = None

    def turn(self, p):
        e = self.e
        n = e.step_no
        if p.leg is not None:
            if p.leg[3] > n:
                return
            p.pos = p.leg[1]
            p.leg = None
            if p.pos == p.res:
                p.occ, p.res = p.pos, None
        for _ in range(64):
            cur = self.select(p)
            if cur is None:
                return
            r = self.run(p, cur)
            if r == 'wait':
                return
            self.advance(p, r)

    def advance(self, p, r):
        cur = p.cur
        steps = self.st.tasks[cur['task']]['steps']
        if r == 'next':
            nxt = cur['step'] + 1
        elif r == 'fail':
            s = steps[cur['step']]
            el = s.get('else', s['wait'].get('else') if 'wait' in s else None)
            if el is None:
                self.finish(p, 'abandoned')
                return
            nxt = el
        else:               # ('task', tid): choose
            self.e.ev('task', p.id, cur['task'], 'done')
            self.release(cur)
            cur['task'] = r[1]
            cur['src'] = None
            cur['step'] = 0
            cur['st'] = {}
            self.unreserve(p)
            self.e.ev('task', p.id, r[1], 'start')
            return
        self.unreserve(p)
        if nxt >= len(steps):
            self.finish(p, 'done')
            return
        cur['step'] = nxt
        cur['st'] = {}

    def resolve(self, p, cur, x):
        """A go's target place: (place, taken) or (None, False) when there is none."""
        st = self.st
        if isinstance(x, str):
            i = st.pix[x]
        elif 'kks' in x:
            code = cur['code'] if x['kks'] == '$' else x['kks']
            i = st.work_at.get(code) if code is not None else None
            if i is None:
                return None, False
        else:
            i = self.free_of(x['kind'], x['room'], p.i)
            if i is None:
                first = next(j for j in st.rooms[x['room']] if st.places[j]['kind'] == x['kind'])
                return first, True
            return i, False
        return i, st.places[i]['kind'] not in OPEN_KINDS and self.holder.get(i, p.i) != p.i

    def hop(self, a, b):
        """The next place on the route from a to b (§16.2), or None at b."""
        st = self.st
        if a == b:
            return None
        if a not in st.point_no:
            return st.stub[a][0]
        pb = b if b in st.point_no else st.stub[b][0]
        if a == pb:
            return b
        return st.points[st.next[st.point_no[a]][st.point_no[pb]]]

    def walk(self, p, dest):
        """Moves p one way towards dest; True when there."""
        if p.pos == dest:
            return True
        e = self.e
        st = self.st
        nx = self.hop(p.pos, dest)
        steps = st.ways[(min(p.pos, nx), max(p.pos, nx))]
        self.leave_place(p)
        p.leg = (p.pos, nx, e.step_no, e.step_no + steps)
        e.ev('move', p.id, st.places[p.pos]['id'], st.places[nx]['id'], e.step_no + steps)
        p.pos = None
        return False

    def go(self, p, cur, x, tsec='go'):
        """A go (also a lock's and a meeting's walk): 'next' on arrival, 'wait' on the way, 'fail' without a place
        or after waiting 15 clock minutes for a taken one."""
        e = self.e
        st = self.st
        s = cur['st']
        if 'dest' not in s:
            i, taken = (x, self.taken(x, p)) if isinstance(x, int) else self.resolve(p, cur, x)
            if i is None:
                return 'fail'
            s['target'] = i
            if taken:
                room = st.places[i].get('room')
                w = st.door.get(room) if room is not None else None
                if w is None or w == i:
                    w = self.before(p.pos, i)
                s['dest'] = w
                s['waiting'] = True
            else:
                s['dest'] = i
                self.reserve(p, i)
        if s.get('waiting') and p.pos == s['dest']:
            if 'wait_since' not in s:
                s['wait_since'] = e.step_no         # the 15 minutes count from the arrival where they wait
            i = s['target']
            if not isinstance(x, int) and not isinstance(x, str) and 'kind' in x:
                j = self.free_of(x['kind'], x['room'], p.i)
                if j is not None:
                    i = s['target'] = j
            if not self.taken(i, p):
                s['dest'] = i
                s['waiting'] = False
                self.reserve(p, i)
            elif e.step_no - s['wait_since'] >= WAIT_PLACE * st.tpm:
                return 'fail'
            else:
                return 'wait'
        if self.walk(p, s['dest']):
            return 'wait' if s.get('waiting') else 'next'
        return 'wait'

    def before(self, a, b):
        """The last place before b on the route from a to b (a itself when b is next)."""
        x = a
        while True:
            nx = self.hop(x, b)
            if nx == b or nx is None:
                return x
            x = nx

    def taken(self, i, p):
        return self.st.places[i]['kind'] not in OPEN_KINDS and self.holder.get(i, p.i) != p.i

    def reserve(self, p, i):
        if self.st.places[i]['kind'] in OPEN_KINDS or p.occ == i:
            return
        self.unreserve(p)
        p.res = i
        self.holder[i] = p.i

    def mins(self, p, cur, x):
        if isinstance(x, list):
            p.rng, r = draw(p.rng)
            return x[0] + ((r * (x[1] - x[0] + 1)) >> 24)
        return x

    def run(self, p, cur):
        """Runs the current step for an NPC: 'next', 'wait', 'fail' or ('task', id)."""
        e = self.e
        st = self.st
        n = e.step_no
        s = st.tasks[cur['task']]['steps'][cur['step']]
        x = cur['st']
        if 'go' in s:
            return self.go(p, cur, s['go'])
        if 'work' in s:
            if 'left' not in x:
                x['left'] = self.mins(p, cur, s['work']) * st.tpm
                x['last'] = n
            elif x['last'] < n:
                x['left'] -= 1
                x['last'] = n
            return 'next' if x['left'] <= 0 else 'wait'
        if 'read' in s:
            code = s['read']
            v = e.shown(code, e.prev)
            ex = s.get('expect')
            ok = ex is None or ex[0] <= v <= ex[1]
            e.ev('read', p.id, code, v, 'ok' if ok else 'out_of_range')
            return 'next'
        if 'meet' in s:
            return self.meet(p, cur, s['meet'], False)
        if 'say' in s:
            self.say(p, s['say'], s['to'])
            return 'next'
        if 'wait' in s:
            return self.wait(p, cur, s['wait'])
        if 'call' in s:
            c = s['call']
            w = c.get('work', '$')
            w = cur['work'] if w == '$' else w
            e.ev('call', p.id, c['role'], c['task'], w, 'done')
            self.assign([c['role']], c['task'], st.tasks[c['task']].get('priority', 3), None, w, cur['code'],
                        cur['alarm'])
            return 'next'
        if 'choose' in s:
            tot = sum(w for w, _ in s['choose'])
            p.rng, r = draw(p.rng)
            y = (r * tot) >> 24
            acc = 0
            for w, t in s['choose']:
                acc += w
                if acc > y:
                    return ('task', t)
        if 'ack' in s:
            a = cur['alarm']
            if a is not None and e.astate.get(a) in ('active_unack', 'cleared_unack'):
                e.npc_queue.append(('ack', a))
            return 'next'
        if 'op' in s or 'permit' in s:
            if not x.get('busy'):
                if 'op' in s:
                    o = s['op']
                    e.npc_queue.append(('op', o['kks'], o['do'], o.get('value'), o.get('trip'), o['where'], p.id))
                else:
                    w = cur['work'] if s['permit']['work'] == '$' else s['permit']['work']
                    e.npc_queue.append(('permit', w, s['permit']['action'], p.id))
                x['busy'] = True
                p.result = None
                return 'wait'
            if p.result is None:
                return 'wait'
            r, p.result = p.result, None
            x['busy'] = False
            return 'next' if r == 'done' else 'fail'
        if 'lock' in s or 'unlock' in s:
            k = 'lock' if 'lock' in s else 'unlock'
            w = cur['work'] if s[k]['work'] == '$' else s[k]['work']
            iso = e.isos[e.works[w]['isolation']] if w in e.works and e.works[w].get('isolation') else None
            if iso is None:
                return 'fail'
            pts = list(range(len(iso['points']))) if s[k]['point'] == 'all' else [s[k]['point']]
            i = x.get('i', 0)
            if i >= len(pts):
                return 'next'
            if not x.get('busy'):
                wp = st.work_at.get(iso['points'][pts[i]]['kks'])
                if wp is not None:
                    r = self.go(p, cur, wp)
                    if r != 'next':
                        return r
                x.pop('dest', None)
                e.npc_queue.append((k, w, pts[i], p.id))
                x['busy'] = True
                p.result = None
                return 'wait'
            if p.result is None:
                return 'wait'
            r, p.result = p.result, None
            x['busy'] = False
            if r != 'done':
                return 'fail'
            x['i'] = i + 1
            return 'next' if i + 1 >= len(pts) else self.run(p, cur)
        raise AssertionError(s)

    def say(self, p, msg, to):
        e = self.e
        e.ev('say', p.id, msg, to)
        t = self.trainee
        if t is not None and t != p.i and (to == self.people[t].id or to == self.people[t].role):
            self.unacked += 1

    def wait(self, p, cur, w):
        e = self.e
        x = cur['st']
        if 'from' not in x:
            x['from'] = e.step_no
        if 'until' in w:
            ok = e.truth(w['until'])
            gone = False
        else:
            wid = cur['work'] if w['permit'][0] == '$' else w['permit'][0]
            sv = e.pstate.get(wid, 0)
            want = STATE_NAMES.index(w['permit'][1])
            gone = sv == 10
            ok = not gone and want <= sv <= 9
        if ok:
            return 'next'
        if gone or ('minutes' in w and e.step_no - x['from'] >= w['minutes'] * self.st.tpm):
            return 'fail'
        return 'wait'

    def meet(self, p, cur, m, trainee):
        e = self.e
        st = self.st
        x = cur['st']
        if 'place' not in x:
            x['place'] = st.meet_place(m['room'], {k: v for k, v in self.holder.items() if v != p.i})
            if trainee and x['place'] is not None and not self.taken(x['place'], p):
                self.reserve(p, x['place'])     # the trainee's seat at the meeting is theirs, as an NPC's
        if not trainee:
            r = self.go(p, cur, x['place'])
            if r != 'next':
                return r
            x.pop('dest', None)
        elif self.t_at != x['place']:
            return 'wait'
        if 'meet_since' not in x and not x.get('met'):
            x['meet_since'] = e.step_no
        if not x.get('met'):
            room = set(st.rooms[m['room']])
            here = [q for q in self.people if q.i != p.i and q.on and q.pos in room]
            if all(any(q.role == r for q in here) for r in m['with']) or \
                    e.step_no - x['meet_since'] >= WAIT_PLACE * st.tpm:
                x['met'] = True
                x['left'] = m['minutes'] * st.tpm
                x['last'] = e.step_no
            else:
                return 'wait'
        elif x['last'] < e.step_no:
            if not trainee or self.t_at == x['place']:
                x['left'] -= 1
            x['last'] = e.step_no
        return 'next' if x['left'] <= 0 else 'wait'

    # --- the trainee's person (§17.4): every step waits for its input
    def trainee_turn(self, p, tin):
        e = self.e
        st = self.st
        n = e.step_no
        used = [False] * len(tin)
        mine = [x for x in e.events[e.ev_mark:] if x[0] == n]
        self.trainee_steps(p, tin, used, mine)
        # then the radio inputs no step of theirs took: free messages and calls (requests, §18.7)
        for k, item in enumerate(tin):
            if used[k]:
                continue
            if item[0] == 'say' and isinstance(item[1], str) and item[1] in st.messages and isinstance(item[2], str) and \
                    (item[2] == 'channel' or item[2] in st.roles or item[2] in st.person_ix):
                self.say(p, item[1], item[2])
            elif item[0] == 'call':
                ok = isinstance(item[1], str) and isinstance(item[2], str) and (item[1], item[2]) in st.callable \
                    and item[3] is None       # a request names no work: the called task's own, if any
                e.ev('call', p.id, item[1], item[2], item[3], 'done' if ok else 'refused')
                if ok:
                    self.assign([item[1]], item[2], st.tasks[item[2]].get('priority', 3), None, None, None, None)

    def trainee_steps(self, p, tin, used, mine):
        e = self.e
        st = self.st
        n = e.step_no
        for _ in range(64):
            cur = self.select(p)
            if cur is None:
                return
            s = st.tasks[cur['task']]['steps'][cur['step']]
            x = cur['st']
            r = 'wait'
            if 'go' in s:
                if 'dest' not in x:
                    i, taken = self.resolve(p, cur, s['go'])
                    if i is None:
                        r = 'fail'
                    else:
                        x['dest'] = i
                        if not taken:
                            self.reserve(p, i)
                if r != 'fail' and self.t_at == x['dest']:
                    r = 'next'
                    if p.res == self.t_at:
                        p.occ, p.res = p.res, None
            elif 'work' in s:
                if 'left' not in x:
                    x['left'] = self.mins(p, cur, s['work']) * st.tpm
                    x['last'] = n
                    x['place'] = self.t_at
                elif x['last'] < n:
                    if self.t_at == x['place']:
                        x['left'] -= 1
                    x['last'] = n
                r = 'next' if x['left'] <= 0 else 'wait'
            elif 'read' in s:
                for k, item in enumerate(tin):
                    if not used[k] and item[0] == 'read' and item[1] == s['read'] and is_num(item[2]):
                        used[k] = True
                        v = e.shown(s['read'], e.prev)
                        ex = s.get('expect')
                        if abs(item[2] - v) > s.get('tol', 0):
                            how = 'misread'
                        else:
                            how = 'ok' if ex is None or ex[0] <= v <= ex[1] else 'out_of_range'
                        e.ev('read', p.id, s['read'], item[2], how)
                        r = 'next'
                        break
            elif 'meet' in s:
                r = self.meet(p, cur, s['meet'], True)
            elif 'say' in s:
                for k, item in enumerate(tin):
                    if not used[k] and item[0] == 'say' and item[1] == s['say'] and item[2] == s['to']:
                        used[k] = True
                        self.say(p, s['say'], s['to'])
                        r = 'next'
                        break
            elif 'wait' in s:
                r = self.wait(p, cur, s['wait'])
            elif 'call' in s:
                c = s['call']
                for k, item in enumerate(tin):
                    if not used[k] and item[0] == 'call' and item[1] == c['role'] and item[2] == c['task']:
                        used[k] = True
                        w = c.get('work', '$')
                        w = cur['work'] if w == '$' else w
                        e.ev('call', p.id, c['role'], c['task'], w, 'done')
                        self.assign([c['role']], c['task'], st.tasks[c['task']].get('priority', 3), None, w,
                                    cur['code'], cur['alarm'])
                        r = 'next'
                        break
            elif 'choose' in s:
                for k, item in enumerate(tin):
                    if not used[k] and item[0] == 'pick':
                        used[k] = True
                        if isinstance(item[1], int) and not isinstance(item[1], bool) and \
                                0 <= item[1] < len(s['choose']):
                            r = ('task', s['choose'][item[1]][1])
                            break
            elif 'ack' in s:
                a = cur['alarm']
                if a is None or e.astate.get(a) not in ('active_unack', 'cleared_unack'):
                    r = 'next'
            elif 'op' in s:
                o = s['op']
                if any(y[1] == 'op' and y[2] == o['kks'] and y[3] == o['do'] and y[4] == 'done' and len(y) > 7
                       and y[6] == o['where'] and y[7] == p.id for y in mine):
                    r = 'next'
            elif 'permit' in s:
                w = cur['work'] if s['permit']['work'] == '$' else s['permit']['work']
                if any(y[1] == 'permit' and y[2] == w and y[3] == s['permit']['action'] and y[4] == p.id
                       and y[5] == 'done' for y in mine):
                    r = 'next'
            elif 'lock' in s or 'unlock' in s:
                k = 'lock' if 'lock' in s else 'unlock'
                w = cur['work'] if s[k]['work'] == '$' else s[k]['work']
                iso = e.works[w].get('isolation') if w in e.works else None
                if iso is None:
                    r = 'fail'
                else:
                    npts = len(e.isos[iso]['points'])
                    pts = list(range(npts)) if s[k]['point'] == 'all' else [s[k]['point']]
                    got = x.setdefault('got', [])
                    for y in mine:
                        if y[1] == k and y[2] == w and y[4] == p.id and y[5] == 'done' and y[3] in pts \
                                and y[3] not in got:
                            got.append(y[3])
                    if len(got) == len(pts):
                        r = 'next'
            if r == 'wait':
                return
            self.advance(p, r)

    # --- the snapshot's part (§17.7)
    def snap(self):
        st = self.st
        out = {}
        for p in self.people:
            if p.leg is not None:
                where = ['way', st.places[p.leg[0]]['id'], st.places[p.leg[1]]['id'], p.leg[2], p.leg[3]]
            else:
                where = st.places[p.pos]['id'] if p.pos is not None else None
            out[p.id] = [where, p.cur['task'] if p.cur is not None else None,
                         p.cur['step'] if p.cur is not None else None]
        return out


PERMIT_TO = {'request': 1, 'approve': 2, 'issue': 4, 'accept': 5, 'done': 6, 'return': 7, 'close': 9, 'cancel': 10}
