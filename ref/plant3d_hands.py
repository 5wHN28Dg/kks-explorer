"""Walkdown Plant's hands-on engine (docs/plant3d/REALISM.md §2.3–§2.7, settled in §2.13; milestone HW1): tools carried
(tools.json), hand actions and meters in the model, HART ops, hidden causes with works' cures, and the NPCs' slips.
Every piece is gated by its own key, so a plant without them steps exactly as before. The app's engine is
apps/plant3d/sim/hands.gd, bit for bit."""

import math

from ref.courses import need, keys, is_num, num, ident, lst

TOOLS_FORMAT = 'walkdown-plant-tools'
TOOL_KINDS = ('spanner', 'socket', 'screwdriver', 'hex_key', 'pliers', 'stripper', 'crimper', 'torque', 'meter',
              'communicator', 'calibrator', 'test_set', 'lifting', 'gas_detector')
METER_KINDS = ('meter', 'communicator', 'calibrator')      # the kinds with modes, read through (§2.5)
TOOL_PLACES = ('store', 'toolbox')
LIMITS = {'tools': 200, 'at': 16, 'modes': 16, 'carried': 12, 'hands': 2000, 'meters': 2000, 'causes': 16,
          'cures': 16, 'weight': 65536, 'minutes': 1440}
MINUTE = 600            # clock tenths in a clock minute


def short_id(x, where, hi=16):
    ident(x, where)
    need(len(x) <= hi, 'bad_id', f'{where}: an identifier of at most {hi} characters')
    return x


def text(x, where, hi=200):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1–{hi} characters')
    return x


def whole(x):
    return type(x) is int


# ---------------------------------------------------------------- tools.json (§2.3)

def check_tools(d, staff):
    """tools.json, checked against the staff's places: {'list', 'ix', 'at': per tool [(place index, count)]}."""
    w = 'tools.json'
    keys(d, ('format', 'version', 'tools'), (), w)
    need(d['format'] == TOOLS_FORMAT, 'bad_format', f'{w}: format must be "{TOOLS_FORMAT}"')
    need(whole(d['version']) and d['version'] == 1, 'bad_version', f'{w}: version must be 1')
    out = {'list': [], 'ix': {}, 'at': []}
    for i, t in enumerate(lst(d['tools'], f'{w}.tools', 1, LIMITS['tools'])):
        wt = f'{w}.tools[{i}]'
        keys(t, ('id', 'title', 'kind', 'at'), ('size', 'modes'), wt)
        ident(t['id'], f'{wt}.id')
        need(t['id'] not in out['ix'], 'dup_id', f'{wt}: tool {t["id"]} twice')
        text(t['title'], f'{wt}.title', 80)
        need(t['kind'] in TOOL_KINDS, 'bad_value', f'{wt}.kind: one of {TOOL_KINDS}')
        if 'size' in t:
            text(t['size'], f'{wt}.size', 16)
        if t['kind'] in METER_KINDS:
            need('modes' in t, 'missing_key', f'{wt}.modes: a {t["kind"]} lists its modes (REALISM.md §2.5)')
            for j, md in enumerate(lst(t['modes'], f'{wt}.modes', 1, LIMITS['modes'])):
                short_id(md, f'{wt}.modes[{j}]')
                need(md not in t['modes'][:j], 'dup_id', f'{wt}.modes: {md} twice')
        else:
            need('modes' not in t, 'unknown_key', f'{wt}.modes: only on a meter, communicator or calibrator')
        at = []
        for j, a in enumerate(lst(t['at'], f'{wt}.at', 1, LIMITS['at'])):
            wa = f'{wt}.at[{j}]'
            lst(a, wa, 2, 2)
            pi = staff.place_ref(a[0], wa)
            need(staff.places[pi]['kind'] in TOOL_PLACES, 'bad_value', f'{wa}: a place of kind store or toolbox')
            need(pi not in [x[0] for x in at], 'dup_id', f'{wa}: {a[0]} twice')
            need(whole(a[1]) and 1 <= a[1] <= 99, 'bad_number', f'{wa}: a count of 1 to 99')
            at.append((pi, a[1]))
        out['ix'][t['id']] = i
        out['list'].append(t)
        out['at'].append(at)
    return out


# ---------------------------------------------------------------- the model's hands and meters (§2.4, §2.5)

def check_hand(m, x, w):
    keys(x, ('kks', 'action', 'component'), ('tools', 'wrong', 'needs', 'set', 'input', 'range', 'minutes', 'work'), w)
    m.kks_ref(x['kks'], w)
    ident(x['action'], f'{w}.action')
    short_id(x['component'], f'{w}.component')
    key = (x['kks'], x['action'])
    need(key not in m.hand_keys, 'dup_id', f'{w}: {x["kks"]} already has a hand action {x["action"]!r}')
    if 'tools' in x:
        for i, t in enumerate(lst(x['tools'], f'{w}.tools', 1, 16)):
            ident(t, f'{w}.tools[{i}]')
            need(t not in x['tools'][:i], 'dup_id', f'{w}.tools: {t} twice')
    if 'wrong' in x:
        need(isinstance(x['wrong'], dict) and x['wrong'], 'bad_type', f'{w}.wrong: an object of tools and sentences')
        for t, s in x['wrong'].items():
            ident(t, f'{w}.wrong')
            need(t not in x.get('tools', []), 'bad_value', f'{w}.wrong.{t}: a tool that does it is not wrong')
            text(s, f'{w}.wrong.{t}')
    for i, nd in enumerate(lst(x.get('needs', []), f'{w}.needs', 0, 16)):
        lst(nd, f'{w}.needs[{i}]', 2, 2)
        m.cond(nd[0], f'{w}.needs[{i}]')
        text(nd[1], f'{w}.needs[{i}]')
    if 'set' in x:
        m.sets(x['set'], f'{w}.set')
    need(('input' in x) == ('range' in x), 'missing_key', f'{w}: an input state comes with its range')
    if 'input' in x:
        m.pending_set.append((x['input'], f'{w}.input'))
        lst(x['range'], f'{w}.range', 2, 2)
        num(x['range'][0], f'{w}.range')
        num(x['range'][1], f'{w}.range', x['range'][0])
    need('set' in x or 'input' in x, 'missing_key', f'{w}: a hand action writes a component state (set or input)')
    if 'minutes' in x:
        num(x['minutes'], f'{w}.minutes', 0, LIMITS['minutes'])
        need(x['minutes'] > 0, 'bad_number', f'{w}.minutes: above 0')
    need(isinstance(x.get('work', True), bool), 'bad_type', f'{w}.work: true or false')
    m.hand_keys[key] = x
    m.hands.append(x)


def check_meter(m, x, w):
    keys(x, ('id', 'kks', 'point', 'tool_kind', 'mode', 'value'), ('needs', 'else'), w)
    ident(x['id'], f'{w}.id')
    need(x['id'] not in m.meter_ix, 'dup_id', f'{w}: meter {x["id"]} twice')
    m.kks_ref(x['kks'], w)
    ident(x['point'], f'{w}.point')
    need(x['tool_kind'] in METER_KINDS, 'bad_value', f'{w}.tool_kind: one of {METER_KINDS}')
    short_id(x['mode'], f'{w}.mode')
    need(isinstance(x['value'], str), 'bad_ref', f'{w}.value: a value name')
    m.cond(x['value'], f'{w}.value')
    for i, nd in enumerate(lst(x.get('needs', []), f'{w}.needs', 0, 16)):
        m.cond(nd, f'{w}.needs[{i}]')
    if 'else' in x:
        if not is_num(x['else']):
            m.cond(x['else'], f'{w}.else')
    m.meter_ix[x['id']] = x
    m.meters.append(x)


def finish_model(m):
    """After every model file: what a hand action writes is a component state (never a command, never a code its
    work's isolation locks: REALISM.md §2.4)."""
    commands = {k for o in m.ops for k in o.get('set', {})} | {o['input'] for o in m.ops if 'input' in o}
    state_kks = {name: n.get('kks') for name, n, kind in m.values if kind == 'state'}
    for x in m.hands:
        w = f'hand action {x["kks"]} {x["action"]}'
        writes = list(x.get('set', {})) + ([x['input']] if 'input' in x else [])
        own = {pt['kks'] for wk in m.works if wk['kks'] == x['kks'] and 'isolation' in wk
               for iso in m.isolations if iso['id'] == wk['isolation'] for pt in iso['points']}
        for k in writes:
            need(k not in commands, 'locked_write', f'{w}: {k} is a command (an op writes it): a hand action writes '
                                                    f'component states only (REALISM.md §2.4)')
            need(state_kks.get(k) is None or state_kks.get(k) not in own, 'locked_write',
                 f'{w}: {k} is a state of {state_kks.get(k)}, which the isolation of a work on {x["kks"]} locks')
    for o in m.ops:
        if 'hart' in o:
            need(o['hart'] in m.states, 'bad_ref', f'op {o["kks"]} {o["do"]}.hart: {o["hart"]!r} is not a state')


def check_tool_refs(b, m):
    """With tools.json read: the hand actions' tools and the meters' modes name its tools."""
    tools = b.tools
    for x in m.hands:
        w = f'hand action {x["kks"]} {x["action"]}'
        for t in x.get('tools', []) + list(x.get('wrong', {})):
            need(tools is not None and t in tools['ix'], 'bad_ref', f'{w}: no tool {t!r} in tools.json')
    for x in m.meters:
        need(tools is not None and any(t['kind'] == x['tool_kind'] and x['mode'] in t['modes']
                                       for t in tools['list']), 'bad_ref',
             f'meter {x["id"]}: no {x["tool_kind"]} in tools.json has the mode {x["mode"]!r}')


def part_of(b, code):
    e = b.equipment.get(code)
    return e['part'] if e is not None else None


def check_components(b):
    """Each hand action's component is in its equipment's part kind's tree: the Workshop data file's components, or
    `body` for a kind without one (WORKSHOP.md §4.1)."""
    for x in b.model.hands:
        part = part_of(b, x['kks'])
        w = f'hand action {x["kks"]} {x["action"]}'
        need(part is not None, 'bad_ref', f'{w}: {x["kks"]} is no piece of equipment with a part kind')
        tree = b.workshop_tree[part] if part in b.workshop else {'body'}
        need(x['component'] in tree, 'bad_ref', f'{w}: {part} has no component {x["component"]!r}')


# ---------------------------------------------------------------- causes and cures (§2.6)

def check_causes(f, m, w):
    seen = []
    tot = 0
    for i, c in enumerate(lst(f['causes'], f'{w}.causes', 1, LIMITS['causes'])):
        wc = f'{w}.causes[{i}]'
        keys(c, ('id', 'weight', 'set', 'text'), ('repair',), wc)
        ident(c['id'], f'{wc}.id')
        need(c['id'] not in seen, 'dup_id', f'{wc}: cause {c["id"]} twice')
        seen.append(c['id'])
        if isinstance(c['weight'], str):
            m.cond(c['weight'], f'{wc}.weight')
        else:
            need(whole(c['weight']) and 0 <= c['weight'] <= LIMITS['weight'], 'bad_number',
                 f'{wc}.weight: a whole number 0–65536 or a value name')
            tot += c['weight']
        m.sets(c['set'], f'{wc}.set')
        if 'repair' in c:
            m.sets(c['repair'], f'{wc}.repair')
            need('repair' in f, 'missing_key', f'{wc}.repair: only for a fault with its own repair (it is made with '
                                               f'it)')
        text(c['text'], f'{wc}.text')
    need(tot <= LIMITS['weight'], 'bad_number', f'{w}.causes: the weights total at most 65536')
    # as the fault's own repair (§15.2): a cause's repair made as a work's own write writes no command of a code that
    # work's isolation locks (it would never be made: H.blocked)
    commands = {k for o in m.ops for k in o.get('set', {})} | {o['input'] for o in m.ops if 'input' in o}
    state_kks = {name: n.get('kks') for name, n, kind in m.values if kind == 'state'}
    for wk in m.works:
        if wk.get('repairs') != f['id'] or 'isolation' not in wk:
            continue
        own = {pt['kks'] for x in m.isolations if x['id'] == wk['isolation'] for pt in x['points']}
        for c in f['causes']:
            for k in c.get('repair', {}):
                need(k not in commands or state_kks.get(k) not in own, 'locked_write',
                     f'{w}: cause {c["id"]}.repair: {k} is a command of {state_kks.get(k)}, which work {wk["id"]}\'s '
                     f'own isolation locks')


def check_cures(m, x, w):
    """A work's cures (in Model.check_work): the causes of its fault it puts right."""
    need('repairs' in x, 'missing_key', f'{w}.repairs: a work that cures causes repairs their fault')
    for i, c in enumerate(lst(x['cures'], f'{w}.cures', 1, LIMITS['cures'])):
        ident(c, f'{w}.cures[{i}]')
        need(c not in x['cures'][:i], 'dup_id', f'{w}.cures: {c} twice')


def check_scenario_cures(s, m, rel):
    faults = {f['id']: f for f in s.get('faults', [])}
    for wk in m.works:
        if 'cures' in wk and wk['repairs'] in faults:
            ids = [c['id'] for c in faults[wk['repairs']].get('causes', [])]
            for c in wk['cures']:
                need(c in ids, 'bad_ref', f'{rel}: fault {wk["repairs"]} has no cause {c!r} (work {wk["id"]}.cures)')


# ---------------------------------------------------------------- the engine's state

def keyed(b, sc):
    """Whether a run has any of HW1's keys (its state, saves and digest part only then)."""
    m = b.model
    st = getattr(b, 'staff', None)        # (a bench model's bundle has neither: ref/plant3d_bench.py)
    return getattr(b, 'tools', None) is not None or bool(m.hands) or bool(m.meters) or any('cures' in w for w in m.works) or \
        any('causes' in f for f in sc.get('faults', [])) or \
        (st is not None and any('slip' in s for t in st.task_list for s in t['steps']))


def init(e, b, sc):
    from ref.plant3d_world import TAGS, stream, world_seed
    e.hw = keyed(b, sc)
    e.tools = getattr(b, 'tools', None)
    e.hands = b.model.hand_keys
    e.meters = b.model.meter_ix
    e.works_on = {}
    for w in b.model.works:
        e.works_on.setdefault(w['kks'], []).append(w)
    e.tool_n = [[c for _, c in at] for at in e.tools['at']] if e.tools is not None else []
    e.carried = {}
    e.busy = {}
    e.cause_of = {}
    seed = world_seed(sc)
    e.cause_s = {f['id']: stream(seed, TAGS['causes'], f['id']) for f in sc.get('faults', []) if 'causes' in f}
    e.slip_s = {}
    st = getattr(b, 'staff', None)
    if st is not None and any('slip' in s for t in st.task_list for s in t['steps']):
        e.slip_s = {p['id']: stream(seed, TAGS['slips'], p['id']) for p in st.people}


def copy_state(c, e):
    c.tool_n = [list(x) for x in e.tool_n]
    c.carried = {k: list(v) for k, v in e.carried.items()}
    c.busy = {k: list(v) for k, v in e.busy.items()}
    c.cause_of = dict(e.cause_of)
    c.cause_s = dict(e.cause_s)
    c.slip_s = dict(e.slip_s)


def person_of(e, person):
    """The staff's Person of a person id, or None."""
    sr = e.staff
    if sr is None or not isinstance(person, str) or person not in sr.st.person_ix:
        return None
    return sr.people[sr.st.person_ix[person]]


def carries_kind(e, pid, kind, mode=None):
    if e.tools is None:
        return False
    for t in e.carried.get(pid, ()):
        x = e.tools['list'][e.tools['ix'][t]]
        if x['kind'] == kind and (mode is None or mode in x.get('modes', ())):
            return True
    return False


# ---------------------------------------------------------------- tools carried (§2.3)

def tool(e, item, person, take, npc, tail=()):
    """A tool taken (take 1) or put back (0) by a person at their place: (result, reasons); its event made."""
    tools = e.tools
    if tools is None or not isinstance(item, str) or item not in tools['ix'] or type(take) is not int \
            or take not in (0, 1):
        e.ev('tool', item, take, person, 'unknown', [], *tail)
        return 'unknown'
    k = tools['ix'][item]
    p = person_of(e, person)
    why = []
    if p is None or e._authority(person, npc, None):
        why.append('authority')
    at = tools['at'][k]
    j = next((j for j, (pi, _) in enumerate(at) if p is not None and pi == p.pos), None)
    if j is None:
        why.append('where')
    have = e.carried.get(person, []) if p is not None else []
    if take:
        if j is not None and e.tool_n[k][j] <= 0:
            why.append('none_left')
        if item in have:
            why.append('carried')
        elif len(have) >= LIMITS['carried']:
            why.append('full')
    elif item not in have:
        why.append('not_carried')
    elif p is not None and person in e.busy and e.busy[person][2] == item:
        why.append('busy')          # (the tool of their hand action under way stays with it)
    if why:
        e.ev('tool', item, take, person, 'refused', why, *tail)
        return 'refused'
    if take:
        e.tool_n[k][j] -= 1
        e.carried[person] = have + [item]
    else:
        e.tool_n[k][j] += 1
        have = [t for t in have if t != item]
        if have:
            e.carried[person] = have
        else:
            del e.carried[person]
    e.ev('tool', item, take, person, 'done', [], *tail)
    return 'done'


# ---------------------------------------------------------------- hand actions (§2.4)

def hand_authority(e, x, person, npc):
    if x.get('work', True):
        for w in e.works_on.get(x['kks'], ()):
            if e.pstate[w['id']] == 5 and not e._authority(person, npc, 'accept', w['discipline'], True, w['id']):
                return False
        return True
    return e._authority(person, npc, 'operate_local')


def hart_permit(e, kks, isos, person, npc):
    """A HART op on a locked code (REALISM.md §2.15): the work on that code whose permit is accepted, which holds
    every isolation locking it (isos), and under which the person acts (its acceptor, or another with accept and its
    discipline while the acceptor is off duty), or None. A person is named: no permit is accepted by nobody."""
    if not isinstance(person, str):
        return None
    for w in e.works_on.get(kks, ()):
        if e.pstate[w['id']] == 5 and all(e.holder[i] == w['id'] for i in isos) \
                and not e._authority(person, npc, 'accept', w['discipline'], True, w['id']):
            return w['id']
    return None


def hand(e, item, npc, prev):
    """A hand action in step 1: 'start', 'done', 'refused' or 'unknown', its event made."""
    kks, action, tl, value, person = item
    x = e.hands.get((kks, action)) if isinstance(kks, str) and isinstance(action, str) else None
    if x is None:
        e.ev('hand', kks, action, tl, person, 'unknown', [])
        return 'unknown'
    why = []
    p = person_of(e, person)
    if p is None or hand_authority(e, x, person, npc):
        why.append('authority')
    if p is not None and p.pos not in e.staff.st.work_places.get(kks, ()):
        why.append('where')         # done at a work place of the code (REALISM.md §2.15)
    if p is not None and person in e.busy:
        why.append('busy')
    have = e.carried.get(person, ()) if p is not None else ()
    if tl is None:
        if 'tools' in x:
            why.append('tool')
    elif not isinstance(tl, str) or tl not in have:
        why.append('tool')
    elif tl not in x.get('tools', ()):
        why.append('wrong_tool')
    why += [nd[0] for nd in x.get('needs', []) if prev[e.ix[nd[0]]] < 0.5]
    if 'input' in x and not (is_num(value) and x['range'][0] <= value <= x['range'][1]):
        why.append('value')
    if why:
        e.ev('hand', kks, action, tl, person, 'refused', why)
        return 'refused'
    if 'minutes' in x:
        end = e.clock() + math.ceil(x['minutes'] * MINUTE)
        e.busy[person] = [kks, action, tl, float(value) if 'input' in x else None, end, place(p)]
        e.ev('hand', kks, action, tl, person, 'start', [])
        return 'start'
    write(e, x, value)
    e.ev('hand', kks, action, tl, person, 'done', [])
    return 'done'


def write(e, x, value):
    """A hand action's writes: its set, then its input; never skipped by a lock (§2.4)."""
    for k, v in x.get('set', {}).items():
        e.cur[e.ix[k]] = float(v)
    if 'input' in x:
        e.cur[e.ix[x['input']]] = float(value)


def end_hands(e, jumped):
    """Step 3, after the renewals: each busy person in staff order (§2.13)."""
    sr = e.staff
    if not e.busy or sr is None:
        return
    c = e.clock()
    for p in sr.people:
        b = e.busy.get(p.id)
        if b is None:
            continue
        kks, action, tl, value, end, at = b
        if jumped or place(p) != at:
            del e.busy[p.id]
            e.ev('hand', kks, action, tl, p.id, 'abandoned', [])
            result(e, p, 'abandoned')
        elif c >= end:
            del e.busy[p.id]
            write(e, e.hands[(kks, action)], value)
            e.ev('hand', kks, action, tl, p.id, 'done', [])
            result(e, p, 'done')


def place(p):
    """A person's place as the app's engine keeps it (-1: none, on a way or off site)."""
    return p.pos if p.pos is not None else -1


def result(e, p, r):
    """A timed hand action's end, for the NPC whose step waits on it (not a player's person)."""
    sr = e.staff
    if sr.slot_of(p.i) is None and p.cur is not None and p.cur['st'].get('hw'):
        p.result = r        # (only for the step that waits on it)


def abandon(e, p):
    """An NPC pre-empted (§17.3's pause) leaves their hand action, in step 9."""
    b = e.busy.pop(p.id, None)
    if b is not None:
        e.ev('hand', b[0], b[1], b[2], p.id, 'abandoned', [])


def slip(e, item):
    """An NPC's slip (§2.13), in step 1: its set written directly."""
    _, pid, task, step = item
    t = e.staff.st.tasks.get(task) if e.staff is not None and isinstance(task, str) else None
    if t is None or type(step) is not int or not 0 <= step < len(t['steps']) or 'slip' not in t['steps'][step]:
        return          # (the engine makes no other: nothing, no event)
    s = t['steps'][step]['slip']
    for k, v in s['set'].items():
        e.cur[e.ix[k]] = float(v)
    e.ev('slip', pid, task, step)


def slip_draw(e, p, cur, s):
    """When an NPC's hand step is done: one draw from their slip stream (REALISM.md §3.1)."""
    from ref.plant3d_world import draw
    e.slip_s[p.id], r = draw(e.slip_s[p.id])
    if (r * 1000) >> 24 < s['slip']['per_mille']:
        e.npc_queue.append(('slip', p.id, cur['task'], cur['step']))


def hand_holds(e, kks, action, value):
    """A hand action done earlier still holds: each state of its set has that value, its input the step's value."""
    x = e.hands.get((kks, action))
    if x is None:
        return False
    if any(e.cur[e.ix[k]] != float(v) for k, v in x.get('set', {}).items()):
        return False
    if 'input' in x and value is not None and e.cur[e.ix[x['input']]] != float(value):
        return False
    return True


# ---------------------------------------------------------------- meters (§2.5)

def shown(e, meter, vals):
    x = e.meters[meter]
    if all(vals[e.ix[nd]] >= 0.5 for nd in x.get('needs', [])):
        return vals[e.ix[x['value']]]
    el = x.get('else', 0)
    return float(el) if is_num(el) else vals[e.ix[el]]


def can_read(e, pid, meter):
    x = e.meters[meter]
    return carries_kind(e, pid, x['tool_kind'], x['mode'])


# ---------------------------------------------------------------- hidden causes (§2.6)

def draw_cause(e, fid, f, vals, named):
    """A fault with causes just made (step 3): the instructor's named cause (named: None for none), else one draw
    from its stream; the cause's set after the fault's, and its event."""
    from ref.plant3d_world import draw
    cs = f['causes']
    if named is not None:
        c = next(x for x in cs if x['id'] == named)
    else:
        ws = []
        for x in cs:
            wt = x['weight']
            if isinstance(wt, str):
                v = vals[e.ix[wt]]
                wt = 0 if not v >= 0 else LIMITS['weight'] if v >= LIMITS['weight'] else int(math.floor(v))
            ws.append(wt)
        tot = sum(ws)
        e.cause_s[fid], r = draw(e.cause_s[fid])
        c = cs[0]
        if tot > 0:
            y = (r * tot) >> 24
            acc = 0
            for x, wt in zip(cs, ws):
                acc += wt
                if acc > y:
                    c = x
                    break
    e.cause_of[fid] = c['id']
    e._set(c['set'])
    e.ev('cause', fid, c['id'])


def cause(e, fid):
    f = e.faults.get(fid)
    if f is None or 'causes' not in f:
        return None
    cid = e.cause_of.get(fid)
    return next((c for c in f['causes'] if c['id'] == cid), None)


def repair_writes(e, fid, f):
    """What a repair writes: the fault's repair, then its applied cause's (§2.6)."""
    c = cause(e, fid)
    out = dict(f['repair'])
    if c is not None and 'repair' in c:
        out.update(c['repair'])
    return out


def blocked(e, fid, f, wid):
    c = cause(e, fid)
    return e._blocked(f['repair'], wid) or (c is not None and 'repair' in c and e._blocked(c['repair'], wid))


def do_repair(e, fid, f, wid):
    e._set(f['repair'], wid)
    c = cause(e, fid)
    if c is not None and 'repair' in c:
        e._set(c['repair'], wid)


def cures(e, wid, fid):
    """Whether a work puts right its fault's applied cause (a work without cures cures every cause)."""
    w = e.works[wid]
    if 'cures' not in w or fid not in e.cause_of:
        return True
    return e.cause_of[fid] in w['cures']


# ---------------------------------------------------------------- the digest's part and the snapshot's (§2.8)

def digest_part(e):
    from ref.godot_variant import Packed, PACKED_INT64
    sr = e.staff
    people = [p.id for p in sr.people] if sr is not None else []
    counts = [c for x in e.tool_n for c in x]
    tix = e.tools['ix'] if e.tools is not None else {}
    carried = [Packed(PACKED_INT64, [tix[t] for t in e.carried.get(pid, [])]) for pid in people]
    busy = [list(e.busy[pid]) if pid in e.busy else None for pid in people]
    causes = [[e.cause_s[f['id']], e.cause_of.get(f['id'])] for f in e.sc.get('faults', []) if 'causes' in f]
    slips = [e.slip_s[pid] for pid in people] if e.slip_s else []
    return [Packed(PACKED_INT64, counts), carried, busy, causes, Packed(PACKED_INT64, slips)]


def snapshot_part(e, s):
    s['carried'] = {k: list(v) for k, v in sorted(e.carried.items())}
    s['busy'] = {k: [v[0], v[1], v[4]] for k, v in sorted(e.busy.items())}
    s['causes'] = dict(sorted(e.cause_of.items()))
