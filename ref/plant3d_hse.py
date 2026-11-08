"""Walkdown Plant's job safety analyses and toolbox talks (docs/plant3d/REALISM.md §8.1, settled in §8.6; milestone HS1):
the hazard library (hse.json), a work's `jsa`, the `jsa` and `talk` inputs, the issue refused without a JSA, and the
talk's attendance. Gated by the plant's hse.json, so a plant without it steps exactly as before. The app's engine is
apps/plant3d/sim/hse.gd, bit for bit."""

from ref.courses import need, keys, ident, lst

HSE_FORMAT = 'walkdown-plant-hse'
LIMITS = {'controls': 200, 'hazards': 200, 'jobs': 100, 'answers': 16, 'job_hazards': 32, 'id': 24, 'title': 120,
          'source': 200, 'jsa_hazards': 32, 'jsa_controls': 64, 'points': 32}
JSA_STATES = (0, 1, 2, 3, 9, 10)    # a JSA is made before its permit is issued (§8.6)
TALK_STATES = (1, 2, 3, 4, 5)       # a talk is given for an open permit before its work is done


def _text(x, where, hi):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1–{hi} characters')


def _items(d, key, w, extra, refs=None):
    """A list of {id, title, [extra], [source]}: returns (list, id -> index)."""
    out, ix = [], {}
    for i, x in enumerate(lst(d[key], f'{w}.{key}', 1, LIMITS[key])):
        wx = f'{w}.{key}[{i}]'
        keys(x, ('id', 'title') + ((extra,) if extra else ()), ('source',), wx)
        ident(x['id'], f'{wx}.id')
        need(len(x['id']) <= LIMITS['id'], 'bad_id', f'{wx}.id: an identifier of at most {LIMITS["id"]} characters')
        need(x['id'] not in ix, 'dup_id', f'{wx}: {x["id"]} twice')
        _text(x['title'], f'{wx}.title', LIMITS['title'])
        if 'source' in x:
            _text(x['source'], f'{wx}.source', LIMITS['source'])
        if extra:
            hi = LIMITS['answers'] if key == 'hazards' else LIMITS['job_hazards']
            for j, r in enumerate(lst(x[extra], f'{wx}.{extra}', 1, hi)):
                need(isinstance(r, str) and r in refs, 'bad_ref', f'{wx}.{extra}[{j}]: no {extra[:-1]} {r!r}')
                need(r not in x[extra][:j], 'dup_id', f'{wx}.{extra}: {r} twice')
        ix[x['id']] = i
        out.append(x)
    return out, ix


def check(d):
    """hse.json (format walkdown-plant-hse version 1, REALISM.md §8.6): {'controls', 'hazards', 'jobs' (lists),
    'control_ix', 'hazard_ix', 'job_ix' (id -> index), 'own': job id -> (hazard ids, control ids)}."""
    w = 'hse.json'
    keys(d, ('format', 'version', 'controls', 'hazards', 'jobs'), (), w)
    need(d['format'] == HSE_FORMAT, 'bad_format', f'{w}: format must be "{HSE_FORMAT}"')
    need(type(d['version']) is int and d['version'] == 1, 'bad_version', f'{w}: version must be 1')
    controls, cix = _items(d, 'controls', w, None)
    hazards, hix = _items(d, 'hazards', w, 'controls', cix)
    jobs, jix = _items(d, 'jobs', w, 'hazards', hix)
    own = {}
    for j in jobs:
        cs = []
        for h in j['hazards']:
            for c in hazards[hix[h]]['controls']:
                if c not in cs:
                    cs.append(c)
        own[j['id']] = (list(j['hazards']), cs)
    return {'controls': controls, 'hazards': hazards, 'jobs': jobs, 'control_ix': cix, 'hazard_ix': hix,
            'job_ix': jix, 'own': own}


def check_works(b, m, has_file):
    """Each work's `jsa` names a job kind of hse.json (§8.6)."""
    for x in m.works:
        if 'jsa' in x:
            w = f'work {x["id"]}.jsa'
            ident(x['jsa'], w)
            need(has_file, 'bad_ref', f'{w}: a job kind of hse.json, and the plant has none (REALISM.md §8.6)')
            need(x['jsa'] in b.hse['job_ix'], 'bad_ref', f'{w}: no job {x["jsa"]!r} in hse.json')


# ---------------------------------------------------------------- the engine (§8.6)

def init(e, b):
    e.hse = getattr(b, 'hse', None)
    e.jsa_of = {}          # work -> [hazard ids, control ids, person]: its JSA
    e.talked = {}       # work -> sorted person indices who attended its toolbox talks


def copy_state(c, e):
    c.jsa_of = {k: [list(v[0]), list(v[1]), v[2]] for k, v in e.jsa_of.items()}
    c.talked = {k: list(v) for k, v in e.talked.items()}


def _ids(x, ix, lo, hi):
    """Whether x is a list of lo–hi ids of ix without repeats."""
    if not isinstance(x, list) or not lo <= len(x) <= hi:
        return False
    seen = set()
    for y in x:
        if not isinstance(y, str) or y not in ix or y in seen:
            return False
        seen.add(y)
    return True


def _work(e, work):
    """The work's model entry when it is a work with `jsa` of a plant with hse.json, else None."""
    if e.hse is None or not isinstance(work, str) or work not in e.works:
        return None
    w = e.works[work]
    return w if 'jsa' in w else None


def jsa(e, item, npc):
    """`[jsa, work, hazards, controls, person]`, in step 1: its result, its event made."""
    work, hz, cs, person = item[1], item[2], item[3], item[4]
    w = _work(e, work)
    if w is None or not _ids(hz, e.hse['hazard_ix'], 1, LIMITS['jsa_hazards']) or \
            not _ids(cs, e.hse['control_ix'], 0, LIMITS['jsa_controls']):
        e.ev('jsa', work, hz, cs, person, 'unknown', [])
        return 'unknown'
    why = []
    if e._authority(person, npc, 'jsa'):
        why.append('authority')
    if e.pstate[work] not in JSA_STATES:
        why.append('state')
    if why:
        e.ev('jsa', work, hz, cs, person, 'refused', why)
        return 'refused'
    e.jsa_of[work] = [list(hz), list(cs), person]
    e.ev('jsa', work, hz, cs, person, 'done', [])
    return 'done'


def attendees(e, person):
    """The people at the giver's talk (§8.6), in people order: the giver and everyone else on duty at a place of the
    room of the giver's place; at a place of no room, at that same place; the giver at no place, the giver alone."""
    sr = e.staff
    if sr is None or not isinstance(person, str) or person not in sr.st.person_ix:
        return []           # (a scenario without staff, or free mode: nobody)
    g = sr.people[sr.st.person_ix[person]]
    if g.pos is None:
        return [g.i]
    room = sr.st.places[g.pos].get('room')
    where = set(sr.st.rooms[room]) if room is not None else {g.pos}
    return [q.i for q in sr.people if q.i == g.i or q.on and q.pos is not None and q.pos in where]


def talk(e, item, npc):
    """`[talk, work, points, person]`, in step 1: its result, its event made."""
    work, pts, person = item[1], item[2], item[3]
    w = _work(e, work)
    if w is None or not _ids(pts, e.hse['hazard_ix'], 1, LIMITS['points']):
        e.ev('talk', work, pts, person, 'unknown', [], [])
        return 'unknown'
    why = []
    if e._authority(person, npc, 'jsa'):
        why.append('authority')
    if e.pstate[work] not in TALK_STATES:
        why.append('state')
    if work not in e.jsa_of:
        why.append('jsa')
    if why:
        e.ev('talk', work, pts, person, 'refused', why, [])
        return 'refused'
    came = attendees(e, person)
    att = sorted(set(e.talked.get(work, [])) | set(came))
    if att:                 # (free mode's talk: attended by nobody)
        e.talked[work] = att
    sr = e.staff
    e.ev('talk', work, pts, person, 'done', [], [sr.people[i].id for i in came])
    return 'done'


def issue_refused(e, work):
    """Whether an issue lacks its JSA (§8.6: refused `jsa`)."""
    return e.hse is not None and 'jsa' in e.works[work] and work not in e.jsa_of


def cleared(e, work):
    """A close or cancel of the work's permit ends its JSA and the talk's attendance."""
    e.jsa_of.pop(work, None)
    e.talked.pop(work, None)


def own(e, work):
    """The work's own list (§8.6): (hazard ids, control ids); empty lists for anything but a work with `jsa` (an NPC
    step's task without a work: its input is then `unknown`, as a permit step's is)."""
    if _work(e, work) is None:
        return ([], [])
    return e.hse['own'][e.works[work]['jsa']]


def digest_part(e):
    """Per work with `jsa`, in model order: [has a JSA, hazard indices, control indices, person index or -1,
    attendees' indices]."""
    from ref.godot_variant import Packed, PACKED_INT32
    sr = e.staff
    out = []
    for w in e.m.works:
        if 'jsa' not in w:
            continue
        j = e.jsa_of.get(w['id'])
        pi = -1
        if j is not None and sr is not None and isinstance(j[2], str) and j[2] in sr.st.person_ix:
            pi = sr.st.person_ix[j[2]]
        out.append([1 if j is not None else 0,
                    Packed(PACKED_INT32, [e.hse['hazard_ix'][h] for h in j[0]] if j else []),
                    Packed(PACKED_INT32, [e.hse['control_ix'][c] for c in j[1]] if j else []),
                    pi, Packed(PACKED_INT32, e.talked.get(w['id'], []))])
    return out


def snapshot_part(e, s):
    sr = e.staff
    out = {}
    for w in e.m.works:
        wid = w['id']
        if wid not in e.jsa_of and wid not in e.talked:
            continue
        x = {}
        if wid in e.jsa_of:
            x['jsa'] = [list(e.jsa_of[wid][0]), list(e.jsa_of[wid][1]), e.jsa_of[wid][2]]
        if wid in e.talked:
            x['talk'] = [sr.people[i].id for i in e.talked[wid]]
        out[wid] = x
    if out:                 # (only once a work has a JSA or attendance: earlier snapshots stay as they were)
        s['hse'] = out
