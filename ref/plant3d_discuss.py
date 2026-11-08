"""Walkdown Plant's discussions (docs/plant3d/REALISM.md §6.3, settled in §6.3.1; milestone DC3): discussions.json,
the task step `discuss`, the input `discuss` and the discussions' state. Gated by the plant's discussions.json, so a
plant without it steps exactly as before. The app's engine must agree with it bit for bit on the realism vectors'
`discuss` part."""
import re

from ref.courses import need, keys, ident, lst

DISCUSS_FORMAT = 'walkdown-plant-discussion'
LIMITS = {'discussions': 64, 'id': 24, 'title': 120, 'text': 200, 'evidence': 16, 'turns': 16, 'points': 8,
          'options': (2, 4), 'lines': (1, 4), 'point_minutes': 30, 'minutes': 120, 'agreements': 8, 'terms': 16}
EVIDENCE = {'manual': ('manual', 'section'), 'standard': ('cite',), 'reading': ('code', 'value'), 'rule': ()}
CITE = re.compile(r'[A-Za-z0-9][A-Za-z0-9.-]{0,23}')     # a key of REALISM.md §14's form (the content's test reads
                                                        # §14 itself)
MODES = ('npc', 'open')
JOIN_WAIT = 15          # clock minutes: a meeting's wait for its people, a joiner's for a discussion (§16.6, §6.3.1)


def _text(x, where, hi=LIMITS['text']):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1–{hi} characters')


def _id(x, where):
    ident(x, where)
    need(len(x) <= LIMITS['id'], 'bad_id', f'{where}: an identifier of at most {LIMITS["id"]} characters')
    return x


def _minutes(x, where, hi):
    need(type(x) is int and 1 <= x <= hi, 'bad_number', f'{where}: whole clock minutes, 1–{hi}')


def _ids_of(x, ix, where, what, lo=0, hi=LIMITS['evidence']):
    lst(x, where, lo, hi)
    for j, y in enumerate(x):
        need(isinstance(y, str) and y in ix, 'bad_ref', f'{where}[{j}]: no {what} {y!r}')
        need(y not in x[:j], 'dup_id', f'{where}: {y} twice')


def _lines(x, roles, where, dollar):
    lo, hi = LIMITS['lines']
    for j, ln in enumerate(lst(x, where, lo, hi)):
        keys(ln, ('role', 'text'), (), f'{where}[{j}]')
        need(ln['role'] in roles or dollar and ln['role'] == '$', 'bad_ref',
             f'{where}[{j}].role: a role of the discussion' + (' or "$"' if dollar else ''))
        _text(ln['text'], f'{where}[{j}].text')


def check(d, st, m):
    """discussions.json (format walkdown-plant-discussion version 1, REALISM.md §6.3.1), against staff.json's rooms,
    roles and tasks (st) and the model (m): {'list': [discussion], 'ix': id -> index}; each discussion gets '_opt'
    (per point: option id -> index) and '_pix' (point id -> index)."""
    w = 'discussions.json'
    keys(d, ('format', 'version', 'discussions'), (), w)
    need(d['format'] == DISCUSS_FORMAT, 'bad_format', f'{w}: format must be "{DISCUSS_FORMAT}"')
    need(type(d['version']) is int and d['version'] == 1, 'bad_version', f'{w}: version must be 1')
    works = {x['id'] for x in m.works}
    out, ix = [], {}
    for i, x in enumerate(lst(d['discussions'], f'{w}.discussions', 1, LIMITS['discussions'])):
        wd = f'{w}.discussions[{i}]'
        keys(x, ('id', 'title', 'room', 'roles', 'evidence', 'positions', 'turns', 'points', 'minutes', 'agreements'),
             ('topic',), wd)
        _id(x['id'], f'{wd}.id')
        need(x['id'] not in ix, 'dup_id', f'{wd}: discussion {x["id"]} twice')
        _text(x['title'], f'{wd}.title', LIMITS['title'])
        if 'topic' in x:
            need(isinstance(x['topic'], str) and x['topic'] in works, 'bad_ref', f'{wd}.topic: no work {x["topic"]!r}')
        need(isinstance(x['room'], str) and x['room'] in st.rooms, 'bad_ref', f'{wd}.room: no room {x["room"]!r}')
        need(st.door.get(x['room']) is not None, 'bad_ref', f'{wd}.room: room {x["room"]!r} has no door')
        roles = lst(x['roles'], f'{wd}.roles', 2, 3)
        for j, r in enumerate(roles):
            need(isinstance(r, str) and r in st.roles, 'bad_ref', f'{wd}.roles[{j}]: no role {r!r}')
            need(r not in roles[:j], 'dup_id', f'{wd}.roles: {r} twice')
        ev_ix = {}
        for j, v in enumerate(lst(x['evidence'], f'{wd}.evidence', 1, LIMITS['evidence'])):
            we = f'{wd}.evidence[{j}]'
            need(isinstance(v, dict), 'bad_type', we)
            need('kind' in v, 'missing_key', f'{we}.kind')
            need(isinstance(v['kind'], str) and v['kind'] in EVIDENCE, 'bad_value', f'{we}.kind: one of {list(EVIDENCE)}')
            keys(v, ('id', 'kind', 'text') + EVIDENCE[v['kind']], (), we)
            _id(v['id'], f'{we}.id')
            need(v['id'] not in ev_ix, 'dup_id', f'{we}: evidence {v["id"]} twice')
            _text(v['text'], f'{we}.text')
            if v['kind'] == 'manual':       # (the section is the manuals' generator's to check, not the engine's)
                ident(v['manual'], f'{we}.manual')
                ident(v['section'], f'{we}.section')
            elif v['kind'] == 'standard':
                need(isinstance(v['cite'], str) and CITE.fullmatch(v['cite']) is not None, 'bad_id',
                     f'{we}.cite: a source key of REALISM.md §14')
            elif v['kind'] == 'reading':
                m.kks_ref(v['code'], f'{we}.code')
                m.cond(v['value'], f'{we}.value')
            ev_ix[v['id']] = j
        seen = []
        for j, pos in enumerate(lst(x['positions'], f'{wd}.positions', 1, 3)):
            wp = f'{wd}.positions[{j}]'
            keys(pos, ('role', 'claim', 'evidence'), (), wp)
            need(pos['role'] in roles, 'bad_ref', f'{wp}.role: a role of the discussion')
            need(pos['role'] not in seen, 'dup_id', f'{wp}: role {pos["role"]} twice')
            seen.append(pos['role'])
            _text(pos['claim'], f'{wp}.claim')
            _ids_of(pos['evidence'], ev_ix, f'{wp}.evidence', 'evidence')
        for r in roles:
            need(r in seen, 'bad_ref', f'{wd}.positions: no position for role {r}')
        for j, t in enumerate(lst(x['turns'], f'{wd}.turns', 1, LIMITS['turns'])):
            keys(t, ('role', 'text'), (), f'{wd}.turns[{j}]')
            need(t['role'] in roles, 'bad_ref', f'{wd}.turns[{j}].role: a role of the discussion')
            _text(t['text'], f'{wd}.turns[{j}].text')
        pix, opts = {}, []
        for j, pt in enumerate(lst(x['points'], f'{wd}.points', 1, LIMITS['points'])):
            wp = f'{wd}.points[{j}]'
            keys(pt, ('id', 'minutes', 'options', 'default'), ('role',), wp)
            _id(pt['id'], f'{wp}.id')
            need(pt['id'] not in pix, 'dup_id', f'{wp}: point {pt["id"]} twice')
            if 'role' in pt:
                need(pt['role'] in roles, 'bad_ref', f'{wp}.role: a role of the discussion')
            _minutes(pt['minutes'], f'{wp}.minutes', LIMITS['point_minutes'])
            oix = {}
            lo, hi = LIMITS['options']
            for k, o in enumerate(lst(pt['options'], f'{wp}.options', lo, hi)):
                wo = f'{wp}.options[{k}]'
                keys(o, ('id', 'text', 'lines'), ('side', 'evidence'), wo)
                _id(o['id'], f'{wo}.id')
                need(o['id'] not in oix, 'dup_id', f'{wo}: option {o["id"]} twice')
                _text(o['text'], f'{wo}.text')
                if 'side' in o:
                    need(o['side'] in roles, 'bad_ref', f'{wo}.side: a role of the discussion')
                if 'evidence' in o:
                    _ids_of(o['evidence'], ev_ix, f'{wo}.evidence', 'evidence')
                _lines(o['lines'], roles, f'{wo}.lines', True)
                oix[o['id']] = k
            need(isinstance(pt['default'], str) and pt['default'] in oix, 'bad_ref',
                 f'{wp}.default: no option {pt["default"]!r}')
            pix[pt['id']] = j
            opts.append(oix)
        _minutes(x['minutes'], f'{wd}.minutes', LIMITS['minutes'])
        ags = lst(x['agreements'], f'{wd}.agreements', 1, LIMITS['agreements'])
        for j, a in enumerate(ags):
            wa = f'{wd}.agreements[{j}]'
            keys(a, ('when', 'outcome', 'lines'), (), wa)
            for k, t in enumerate(lst(a['when'], f'{wa}.when', 0, LIMITS['terms'])):
                wt = f'{wa}.when[{k}]'
                need(isinstance(t, dict), 'bad_type', wt)
                if 'point' in t:
                    keys(t, ('point', 'option'), (), wt)
                    need(isinstance(t['point'], str) and t['point'] in pix, 'bad_ref', f'{wt}.point: no point '
                                                                                       f'{t["point"]!r}')
                    need(isinstance(t['option'], str) and t['option'] in opts[pix[t['point']]], 'bad_ref',
                         f'{wt}.option: no option {t["option"]!r} of point {t["point"]}')
                else:
                    keys(t, ('value', 'is'), (), wt)
                    m.cond(t['value'], f'{wt}.value')
                    need(isinstance(t['is'], bool), 'bad_type', f'{wt}.is: true or false')
            need(j < len(ags) - 1 or not a['when'], 'bad_ref',
                 f'{wa}.when: the last agreement has no terms')
            keys(a['outcome'], ('text',), ('task',), f'{wa}.outcome')
            _text(a['outcome']['text'], f'{wa}.outcome.text')
            if 'task' in a['outcome']:
                need(isinstance(a['outcome']['task'], str) and a['outcome']['task'] in st.tasks, 'bad_ref',
                     f'{wa}.outcome.task: no task {a["outcome"]["task"]!r}')
            _lines(a['lines'], roles, f'{wa}.lines', False)
        x['_pix'], x['_opt'] = pix, opts
        ix[x['id']] = i
        out.append(x)
    return {'list': out, 'ix': ix}


def outcomes(st, s):
    """The outcome tasks a `discuss` step may run in place of the rest of its task (§6.3.1), in file order."""
    d = st.discuss['list'][st.discuss['ix'][s['discuss']]]
    return [a['outcome']['task'] for a in d['agreements'] if 'task' in a['outcome']]


# ---------------------------------------------------------------- the engine (§6.3.1)

def _inst(sr, di):
    """The discussion's live or last instance, or None."""
    return sr.disc.get(di)


def _live(sr, d, x):
    """Whether the instance is live: started, no agreement yet, and its lead still has a task at a step of this
    discussion (current, queued or held: a task skipped by a jump, abandoned or stopped leaves it behind, not live)."""
    if x is None or x['agreed'] >= 0:
        return False
    q = sr.people[x['lead']]
    for inst in ([q.cur] if q.cur is not None else []) + q.queue + q.held:
        steps = sr.st.tasks[inst['task']]['steps']
        if inst['step'] < len(steps) and steps[inst['step']].get('discuss') == d['id']:
            return True
    return False


def step(sr, p, cur, did, trainee):
    """A `discuss` step's turn for person p: the lead's (the discussion's first role) or a joiner's. Returns 'next',
    'wait', a go's result or ('task', id) as `choose` does."""
    st = sr.st
    di = st.discuss['ix'][did]
    d = st.discuss['list'][di]
    if p.role == d['roles'][0]:
        return _lead(sr, p, cur, di, d, trainee)
    return _join(sr, p, cur, di, d, trainee)


def _gather(sr, p, cur, room, roles, trainee):
    """A meet's seating and wait (PLANT3D.md §16.6, StaffRun.meet's first half): None once met (the joining roles in
    the room, or 15 clock minutes waited), else what the turn returns."""
    e, st = sr.e, sr.st
    x = cur['st']
    if 'place' not in x:
        x['place'] = st.meet_place(room, {k: v for k, v in sr.holder.items() if v != p.i})
    if trainee and 'seat' not in x:
        x['seat'] = True
        if x['place'] is not None and not sr.taken(x['place'], p):
            sr.reserve(p, x['place'])
    if not trainee:
        r = sr.go(p, cur, x['place'])
        if r != 'next':
            return r
        x.pop('dest', None)
    elif p.pos != x['place']:
        return 'wait'
    if 'meet_since' not in x:
        x['meet_since'] = e.step_no
    here = set(st.rooms[room])
    here = [q for q in sr.people if q.i != p.i and q.on and q.pos in here]
    if all(any(q.role == r for q in here) for r in roles) or e.step_no - x['meet_since'] >= JOIN_WAIT * st.tpm:
        return None
    return 'wait'


def _lead(sr, p, cur, di, d, trainee):
    e, st = sr.e, sr.st
    n = e.step_no
    x = _inst(sr, di)
    if _live(sr, d, x) and x['lead'] != p.i:
        return 'wait'               # another discussion of the same id is live: the step waits
    if not _live(sr, d, x):
        r = _gather(sr, p, cur, d['room'], d['roles'][1:], trainee)
        if r is not None:
            return r
        room = set(st.rooms[d['room']])
        parts = [p.i] + [next((q.i for q in sr.people if q.i != p.i and q.on and q.pos in room and q.role == r), -1)
                         for r in d['roles'][1:]]
        mode = 1 if any(i >= 0 and sr.slot_of(i) is not None for i in parts) else 0
        npts = len(d['points'])
        x = sr.disc[di] = {'count': (x['count'] if x is not None else 0) + 1, 'lead': p.i, 'parts': parts,
                           'mode': mode, 'start': n, 'point': 0, 'since': n, 'opt': [-1] * npts, 'by': [-1] * npts,
                           'agreed': -1}
        e.ev('discussion', d['id'], 'start', p.id, [sr.people[i].id if i >= 0 else None for i in parts],
             MODES[mode])
        return 'wait'
    pts = d['points']
    if x['mode'] == 0:
        if n - x['start'] < d['minutes'] * st.tpm:
            return 'wait'
        for k, pt in enumerate(pts):
            _take(sr, d, x, k, d['_opt'][k][pt['default']], -1)
        x['point'] = len(pts)
    else:
        while x['point'] < len(pts):
            k = x['point']
            if x['opt'][k] < 0:
                if n - x['since'] < pts[k]['minutes'] * st.tpm:
                    return 'wait'
                _take(sr, d, x, k, d['_opt'][k][pts[k]['default']], -1)
            x['point'] = k + 1
            x['since'] = n
    return _end(sr, d, x)


def _take(sr, d, x, k, oi, who):
    x['opt'][k], x['by'][k] = oi, who
    pt = d['points'][k]
    sr.e.ev('point', d['id'], pt['id'], pt['options'][oi]['id'], sr.people[who].id if who >= 0 else None)


def _holds(sr, d, x, t):
    if 'point' in t:
        k = d['_pix'][t['point']]
        return x['opt'][k] == d['_opt'][k][t['option']]
    return sr.e.truth(t['value']) == t['is']


def _end(sr, d, x):
    """The first agreement whose terms all hold (the last has none): its event, then the lead's step ends."""
    j = next(j for j, a in enumerate(d['agreements']) if all(_holds(sr, d, x, t) for t in a['when']))
    task = d['agreements'][j]['outcome'].get('task')
    x['agreed'] = j
    sr.e.ev('discussion', d['id'], 'agreed', j, task)
    return ('task', task) if task is not None else 'next'


def _join(sr, p, cur, di, d, trainee):
    """A joiner's step: to the room (an NPC to the meeting's first free seat, as a meet), then done when the
    discussion it takes part in ends, or after 15 clock minutes in the room without one."""
    e, st = sr.e, sr.st
    n = e.step_no
    c = cur['st']
    if 'place' not in c:
        c['place'] = st.meet_place(d['room'], {k: v for k, v in sr.holder.items() if v != p.i})
    if not trainee and 'arr' not in c:
        r = sr.go(p, cur, c['place'])
        if r != 'next':
            return r
        c.pop('dest', None)
    x = _inst(sr, di)
    if 'arr' not in c:
        if p.pos is None or p.pos not in st.rooms[d['room']]:
            return 'wait'
        c['arr'] = n
        c['cnt'] = 0 if x is None else x['count'] - (1 if _live(sr, d, x) else 0)     # (those ended before it came)
    mine = x is not None and x['count'] > c['cnt'] and p.i in x['parts']
    if mine and not _live(sr, d, x):
        return 'next'
    if not mine and n - c['arr'] >= JOIN_WAIT * st.tpm:
        return 'next'
    return 'wait'


def t_discuss(sr, tp, item):
    """A player's `[discuss, id, point, option]` in step 1 (§6.3.1), for their person tp (None in free mode): its
    event, and the point taken when done."""
    e, st = sr.e, sr.st
    did, point, option = (list(item[1:4]) + [None] * 3)[:3]
    D = st.discuss
    di = D['ix'].get(did) if D is not None and isinstance(did, str) else None
    d = D['list'][di] if di is not None else None
    k = d['_pix'].get(point) if d is not None and isinstance(point, str) else None
    oi = d['_opt'][k].get(option) if k is not None and isinstance(option, str) else None
    why = []
    if oi is None:
        why.append('unknown')
    else:
        x = _inst(sr, di)
        if tp is None or _live(sr, d, x) and tp.i not in x['parts']:
            why.append('authority')
        if not _live(sr, d, x) or x['mode'] != 1 or x['point'] != k or x['opt'][k] >= 0:
            why.append('state')
    who = tp.id if tp is not None else None
    e.ev('discuss', who, did, point, option, 'refused' if why else 'done', why)
    if not why:
        _take(sr, d, x, k, oi, tp.i)


def digest_part(sr):
    """Per discussion in file order: [] before its first start, else [count, lead, participants (-1 for a role with
    nobody), mode (0 npc, 1 open), start step, current point, the step it began, options taken (-1 none), their
    takers (-1 none or the default), the agreement reached (-1 while live)]."""
    from ref.godot_variant import Packed, PACKED_INT32
    out = []
    for di in range(len(sr.st.discuss['list'])):
        x = sr.disc.get(di)
        out.append([] if x is None else [
            x['count'], x['lead'], Packed(PACKED_INT32, x['parts']), x['mode'], x['start'], x['point'], x['since'],
            Packed(PACKED_INT32, x['opt']), Packed(PACKED_INT32, x['by']), x['agreed']])
    return out


def snapshot_part(sr):
    """{id: {...}} for each discussion started at least once."""
    out = {}
    ids = lambda i: sr.people[i].id if i >= 0 else None
    for di, d in enumerate(sr.st.discuss['list']):
        x = sr.disc.get(di)
        if x is None:
            continue
        out[d['id']] = {'count': x['count'], 'lead': ids(x['lead']), 'participants': [ids(i) for i in x['parts']],
                        'mode': MODES[x['mode']], 'start': x['start'], 'point': x['point'], 'since': x['since'],
                        'taken': [[d['points'][k]['options'][o]['id'], ids(x['by'][k])] if o >= 0 else None
                                  for k, o in enumerate(x['opt'])],
                        'agreed': x['agreed'] if x['agreed'] >= 0 else None}
    return out
