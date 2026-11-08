"""Work orders (docs/plant3d/REALISM.md §7.1 and §2.20, milestone WM1): workorders.json (its failure codes and the
content's history), the works' keys finds, codes and hours, the value <work>_wo, the input
[n, "wo", work, action, person, data], the move to in progress by itself, an NPC's write-up of their job, each work
order's record and the run's history, the snapshot's and the digest's parts. The app's engine follows it bit for bit
(apps/plant3d/sim/workorders.gd)."""
from ref.courses import need, keys, is_num, num, ident, lst

FORMAT = 'walkdown-plant-workorders'
LISTS = ('modes', 'causes', 'actions')
STATES = ('none', 'notified', 'planned', 'scheduled', 'in_progress', 'complete', 'closed', 'cancelled')
# action -> (the states it is made from, the state it moves to), and who may make it (§2.20)
ACTIONS = {'notify': ((0, 6, 7), 1), 'plan': ((1,), 2), 'schedule': ((2,), 3), 'complete': ((4,), 5),
           'close': ((5,), 6), 'cancel': ((1, 2, 3, 4), 7)}
AUTH = {'notify': None, 'plan': 'plan_work', 'schedule': 'plan_work', 'complete': 'accept', 'close': 'close_work',
        'cancel': 'close_work'}
KINDS = ('corrective', 'preventive', 'condition')     # the content history's kinds of maintenance (EN 13306)
LIMITS = {'list': 64, 'history': 4096, 'finds': 8, 'works': 512, 'title': 120, 'comment': 120, 'ago': 18250,
          'hours': 10000, 'days_ahead': 365}
DAY = 864000            # a clock day in tenths of a clock second (§16.1)
LIVE = (0, 9, 10)       # permit states that are not live: none, closed, cancelled
DONE = (6, 7, 8, 9)     # permit states past the work: done, returned, deisolated, closed
# a record's fields: number, clocks of the six moves (notified, planned, scheduled, started, completed, ended),
# notifier, mode named, priority, day, completer, codes (mode, cause, action), comment, the work
T_NOTIFY, T_PLAN, T_SCHEDULE, T_START, T_COMPLETE, T_END = range(6)


def _text(x, where, hi):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1 to {hi} characters')


def check_work_keys(x, w):
    """A work's finds, codes and hours (§2.20), their shapes; their ids are looked up in the file by check()."""
    if 'finds' in x:
        f = lst(x['finds'], f'{w}.finds', 1, LIMITS['finds'])
        for i, mode in enumerate(f):
            ident(mode, f'{w}.finds[{i}]')
            need(mode not in f[:i], 'dup_id', f'{w}.finds: {mode} twice')
    if 'codes' in x:
        c = lst(x['codes'], f'{w}.codes', 3, 3)
        for i in (0, 1):
            if c[i] is not None:
                ident(c[i], f'{w}.codes[{i}]')
        ident(c[2], f'{w}.codes[2]')
    if 'hours' in x:
        num(x['hours'], f'{w}.hours', 0, LIMITS['hours'])
        need(x['hours'] > 0, 'bad_number', f'{w}.hours: above 0')


def no_file(m):
    """A plant without workorders.json: a work naming finds, codes or hours is bad_ref (they are its file's)."""
    for x in m.works:
        for k in ('finds', 'codes', 'hours'):
            need(k not in x, 'bad_ref', f'work {x["id"]}.{k}: the plant has no workorders.json (REALISM.md §2.20)')


def check(d, b, m):
    """Check workorders.json d against the model m (its works and codes); returns {list: [ids]} for the engine."""
    w0 = 'workorders.json'
    need(b.version == 2, 'unknown_key', f'{w0}: only in a version 2 plant (REALISM.md §2.20)')
    keys(d, ('format', 'version') + LISTS, ('history',), w0)
    need(d['format'] == FORMAT, 'bad_format', f'{w0}: format must be "{FORMAT}"')
    need(d['version'] == 1 and not isinstance(d['version'], bool), 'bad_version', f'{w0}: version must be 1')
    ids = {}
    for k in LISTS:
        ids[k] = []
        for i, e in enumerate(lst(d[k], f'{w0}.{k}', 1, LIMITS['list'])):
            we = f'{w0}.{k}[{i}]'
            keys(e, ('id', 'title'), (), we)
            ident(e['id'], f'{we}.id')
            need(len(e['id']) <= 22, 'bad_id', f'{we}.id: at most 22 characters')
            need(e['id'] not in ids[k], 'dup_id', f'{we}: {e["id"]} twice')
            ids[k].append(e['id'])
            _text(e['title'], f'{we}.title', LIMITS['title'])

    def code(c, k, where, nullable):
        if c is None and nullable:
            return
        need(isinstance(c, str) and c in ids[k], 'bad_ref', f'{where}: {c!r} is not one of {k}')

    for x in m.works:
        w = f'work {x["id"]}'
        for i, mode in enumerate(x.get('finds', ())):
            code(mode, 'modes', f'{w}.finds[{i}]', False)
        if 'codes' in x:
            code(x['codes'][0], 'modes', f'{w}.codes[0]', True)
            code(x['codes'][1], 'causes', f'{w}.codes[1]', True)
            code(x['codes'][2], 'actions', f'{w}.codes[2]', False)
    works = {x['id']: x for x in m.works}
    codes = set(b.equipment) | set(b.pipes)
    for i, h in enumerate(lst(d.get('history', []), f'{w0}.history', 0, LIMITS['history'])):
        w = f'{w0}.history[{i}]'
        keys(h, ('kks', 'ago', 'kind', 'mode', 'cause', 'action', 'hours', 'title'), ('work',), w)
        need(isinstance(h['kks'], str) and h['kks'] in codes, 'bad_ref', f'{w}.kks: no equipment or pipe {h["kks"]!r}')
        if 'work' in h:
            need(isinstance(h['work'], str) and h['work'] in works, 'bad_ref', f'{w}.work: no work {h["work"]!r}')
            need(works[h['work']]['kks'] == h['kks'], 'bad_ref', f'{w}.work: {h["work"]} is a work on '
                                                                 f'{works[h["work"]]["kks"]}, not {h["kks"]}')
        num(h['ago'], f'{w}.ago', 1, LIMITS['ago'], integer=True)
        need(h['kind'] in KINDS, 'bad_value', f'{w}.kind: one of {KINDS}')
        code(h['mode'], 'modes', f'{w}.mode', True)
        code(h['cause'], 'causes', f'{w}.cause', True)
        code(h['action'], 'actions', f'{w}.action', False)
        num(h['hours'], f'{w}.hours', 0, LIMITS['hours'])
        need(h['hours'] > 0, 'bad_number', f'{w}.hours: above 0')
        _text(h['title'], f'{w}.title', LIMITS['title'])
    return ids


# ---------------------------------------------------------------- the engine's part

def new_record(e, work):
    return [e.wo_no.get(work, ''), [-1] * 6, None, None, 0, -1, None, [None, None, None], '', work]


def init(e, b, m):
    """The work order state of a fresh engine (only in a plant with workorders.json)."""
    e.wo_ids = b.wo_ids
    e.wo = {w['id']: 0 for w in m.works} if e.wo_ids is not None else {}
    e.wo_no = {}            # work -> its current work order's number
    e.wo_rec = {}           # work -> its current work order's record
    e.wo_count = 0
    e.wo_history = []       # the run's closed and cancelled work orders, in that order (records)
    e.wo_npc_done = []      # (work, person): this step's NPC dones, for step 3's write-up


def copy_state(c, e):
    c.wo = dict(e.wo)
    c.wo_no = dict(e.wo_no)
    c.wo_rec = {k: _copy_rec(r) for k, r in e.wo_rec.items()}
    c.wo_history = [_copy_rec(r) for r in e.wo_history]
    c.wo_npc_done = list(e.wo_npc_done)


def _copy_rec(r):
    return [r[0], list(r[1]), r[2], r[3], r[4], r[5], r[6], list(r[7]), r[8], r[9]]


def _whole(x):
    """A whole number as the inputs give it (3 or 3.0; not a boolean)."""
    return is_num(x) and float(x).is_integer()


def _data_ok(e, w, action, data):
    """Whether the data are as §2.20's table says for the action."""
    ids = e.wo_ids
    if action == 'notify':
        return len(data) == 1 and (data[0] is None or isinstance(data[0], str) and data[0] in ids['modes'])
    if action == 'plan':
        return len(data) == 1 and _whole(data[0]) and 1 <= data[0] <= 4
    if action == 'schedule':
        today = e.clock() // DAY
        return len(data) == 1 and _whole(data[0]) and today <= data[0] <= today + LIMITS['days_ahead']
    if action == 'complete':
        return (len(data) == 4 and (data[0] is None or isinstance(data[0], str) and data[0] in ids['modes'])
                and (data[1] is None or isinstance(data[1], str) and data[1] in ids['causes'])
                and isinstance(data[2], str) and data[2] in ids['actions']
                and isinstance(data[3], str) and len(data[3]) <= LIMITS['comment'])
    return len(data) == 0


def wo_input(e, item, npc=False):
    """[n, "wo", work, action, person, data] in step 1 (§2.20); returns 'done', 'refused' or 'unknown'."""
    work, action, person, data = (list(item) + [None] * 4)[1:5]
    if npc and data is None and e.wo_ids is not None and work in e.works and action in ACTIONS:
        data = npc_data(e, e.works[work], action)      # an NPC's step without data: the defaults, now
    if not (e.wo_ids is not None and isinstance(work, str) and work in e.works and isinstance(action, str)
            and action in ACTIONS and isinstance(data, list)):
        e.ev('wo', work, action, person, 'unknown', [])
        return 'unknown'
    w = e.works[work]
    frm, to = ACTIONS[action]
    st = e.wo[work]
    ps = e.pstate[work]
    why = []
    if e._authority(person, npc, AUTH[action], w['discipline'] if action == 'complete' else None):
        why.append('authority')
    if st not in frm:
        why.append('state')
    if action == 'complete' and ps not in DONE or action in ('close', 'cancel') and ps not in LIVE:
        why.append('permit')
    if not _data_ok(e, w, action, data):
        why.append('data')
    if why:
        e.ev('wo', work, action, person, 'refused', why)
        return 'refused'
    _move(e, work, action, person, data, to)
    e.ev('wo', work, action, person, 'done', [])
    return 'done'


def _move(e, work, action, person, data, to):
    c = e.clock()
    if action == 'notify':
        e.wo_count += 1
        e.wo_no[work] = f'WO-{e.wo_count:04d}'
        r = e.wo_rec[work] = new_record(e, work)
        r[1][T_NOTIFY] = c
        r[2], r[3] = person, data[0]
    else:
        r = e.wo_rec[work]
        if action == 'plan':
            r[1][T_PLAN] = c
            r[4] = int(data[0])
        elif action == 'schedule':
            r[1][T_SCHEDULE] = c
            r[5] = int(data[0])
        elif action == 'complete':
            r[1][T_COMPLETE] = c
            r[6] = person
            r[7] = [data[0], data[1], data[2]]
            r[8] = data[3]
        else:       # close, cancel
            r[1][T_END] = c
            e.wo_history.append(_copy_rec(r))
    e.wo[work] = to
    e.cur[e.ix[work + '_wo']] = float(to)


def note_done(e, work, person, npc):
    """A permit's done made in step 1: an NPC's is noted for step 3's write-up (§2.20)."""
    if npc and e.wo_ids is not None:
        e.wo_npc_done.append((work, person))


def step3(e):
    """Step 3, after the permits' automatic moves (§2.20): work orders whose permit is accepted or done go to in
    progress, in model order; then each NPC's done of this step, in the order made, writes up its work order."""
    if e.wo_ids is None:
        return
    c = e.clock()
    for w in e.m.works:
        wid = w['id']
        if e.wo[wid] in (1, 2, 3) and e.pstate[wid] in (5, 6):
            e.wo[wid] = 4
            e.wo_rec[wid][1][T_START] = c
            e.cur[e.ix[wid + '_wo']] = 4.0
            e.ev('wo', wid, 'auto', None, 'done', [4])
    done, e.wo_npc_done = e.wo_npc_done, []
    for wid, person in done:
        w = e.works[wid]
        if e.wo[wid] == 4 and 'codes' in w:
            _move(e, wid, 'complete', person, list(w['codes']) + [''], 5)
            e.ev('wo', wid, 'complete', person, 'done', [])


def npc_data(e, w, action):
    """The data an NPC's wo step sends without its own (§2.20)."""
    if action == 'notify':
        return [w['finds'][0] if w.get('finds') else None]
    if action == 'plan':
        return [3]
    if action == 'schedule':
        return [e.clock() // DAY]
    if action == 'complete':
        return list(w['codes']) + ['']
    return []


def _rec_out(r):
    return {'no': r[0], 'clocks': list(r[1]), 'by': r[2], 'mode': r[3], 'priority': r[4], 'day': r[5],
            'completer': r[6], 'codes': list(r[7]), 'comment': r[8], 'work': r[9]}


def snapshot_part(e, s):
    s['wo'] = {wid: dict(_rec_out(e.wo_rec[wid]), state=e.wo[wid]) for wid in e.works if wid in e.wo_rec}
    s['wo_history'] = [_rec_out(r) for r in e.wo_history]


def _rec_tree(r):
    from ref.godot_variant import Packed, PACKED_INT64
    return [r[0], Packed(PACKED_INT64, r[1]), r[2], r[3], r[4], r[5], r[6], list(r[7]), r[8], r[9]]


def digest_part(e):
    """The digest's work order part (§2.20): the counter, each work's state and record in model order (an empty
    list for a work never notified), the history."""
    from ref.godot_variant import Packed, PACKED_INT32
    m = e.m
    return [e.wo_count, Packed(PACKED_INT32, [e.wo[w['id']] for w in m.works]),
            [_rec_tree(e.wo_rec[w['id']]) if w['id'] in e.wo_rec else [] for w in m.works],
            [_rec_tree(r) for r in e.wo_history]]
