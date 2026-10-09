#!/usr/bin/env python3
"""Draft a short description for every code on the drawings: what the equipment is, what it does, and where it sits
relative to what is drawn around it. The drafts go into the plant data's descriptions.json, which the apps show as
"Draft description (unchecked)" until a person confirms or rewrites it (the confirmation goes through the normal
proposal flow as the equipment's custom field "Description").

  python3 tools/draft_descriptions.py PLANT_DATA_DIR [--kks data/kks.json] [--out FILE] [--keep] [--state STATE.json]

PLANT_DATA_DIR holds sheets.json, tags.json and (optional) locations.json. --keep leaves existing entries in FILE
alone (only new codes get a draft). --state takes the plant's state as the apps see it (GET /api/state): the tags
people marked as missed (added_tags) are drafted too, and review decisions apply as in the apps (a corrected reading
gets the draft under its corrected code; a rejected one gets none). Without it, only tags.json's readings are used. Every draft names its basis, so a reviewer sees what each sentence rests on:
"KKS system + component kind (general knowledge)", "instrument letters", "drawing neighbours", "location list".

What the drafts can't know: the drawings say which equipment is drawn near which, not how the pipes connect (line
tracing is a later step), so "drawn next to" is a hint, not a statement about the process. The system and component
sentences are general combined-cycle knowledge, not this plant's documents. That is why every draft is unchecked.
"""
import argparse, json, math, os, re, sys

# What a KKS system does, for the standard (VGB) systems data/kks.json doesn't name (general knowledge). The systems
# kks.json names come from the plant's own documents and are used as they are, never overridden by a general meaning.
SYSTEM_ROLE = {
    'PAB': 'the circulating (main cooling) water piping, which carries cooling water to and from the condenser',
    'PAC': 'the circulating water pump system, which drives the main cooling water through the condenser',
    'PGB': 'the closed cooling water piping, which carries cooling water to the auxiliary coolers in a sealed loop',
    'PGC': 'the closed cooling water pump system, which circulates the closed-loop cooling water',
    'MAJ': 'the condenser evacuation (vacuum) system, which removes air and gases from the condenser',
    'MAL': 'the turbine drainage system, which drains condensate from the turbine and its steam lines',
    'MAW': 'the turbine sealing (gland) steam system, which seals the turbine shaft ends',
}

# What each component kind does (general knowledge).
COMPONENT_ROLE = {
    'AA': 'a valve: it opens, closes or throttles the flow in its line',
    'AB': 'an isolating element: it separates parts of the system, e.g. for maintenance',
    'AC': 'a heat exchanger: it transfers heat between two media',
    'AP': 'a pump: it moves the fluid and raises its pressure',
    'AT': 'cleaning or separating equipment (a filter, strainer or separator): it keeps dirt or water out of the flow',
    'BB': 'a vessel or tank: it stores fluid or separates phases',
    'BR': 'a piping or duct section',
    'HA': 'a main machine assembly',
    'CF': 'a flow measurement',
    'CL': 'a level measurement',
    'CP': 'a pressure measurement',
    'CT': 'a temperature measurement',
    'CY': 'a machine-condition measurement (e.g. vibration or bearing temperature)',
    'CS': 'a speed measurement',
    'CQ': 'an analysis measurement (water or steam chemistry)',
    'CG': 'a position measurement',
    'CE': 'an electrical measurement',
}

# a component kind in a few words, for "drawn next to …"
COMPONENT_SHORT = {'AA': 'valve', 'AB': 'isolating element', 'AC': 'heat exchanger', 'AP': 'pump', 'AT': 'filter or separator',
                   'BB': 'vessel or tank', 'BR': 'piping', 'HA': 'machine', 'CF': 'flow measurement', 'CL': 'level measurement',
                   'CP': 'pressure measurement', 'CT': 'temperature measurement', 'CY': 'machine-condition measurement',
                   'CS': 'speed measurement', 'CQ': 'analysis measurement', 'CG': 'position measurement',
                   'CE': 'electrical measurement'}
# the measurement a component kind is, and the ISA first letter that agrees with it
# (CY and CQ take several: on the drawings CY carries TISA, LISA and BVSA, CQ carries QI and A…)
COMPONENT_MEASURES = {'CF': 'F', 'CL': 'L', 'CP': 'P', 'CT': 'T', 'CS': 'S', 'CG': 'G'}
MAX_TEXT = 2000     # the core cuts a description there (DescriptionMax)

ISA_FUNCTION = {'I': 'indicated', 'A': 'alarmed', 'C': 'used for control', 'S': 'used for a switching action (e.g. a trip '
                'or interlock)', 'T': 'transmitted to the control system', 'R': 'recorded', 'Q': 'totalised',
                'E': ''}   # E: the sensing element (said in a sentence of its own)

KKS_RE = re.compile(r'^(\d\d)([A-Z]{3})(\d\d)([A-Z]{2})(\d{3})$')


def load(p, default=None):
    if not os.path.exists(p):
        if default is not None: return default
        sys.exit(f'{p} is missing')
    try:
        with open(p, encoding='utf-8') as f:
            return json.load(f)
    except (ValueError, UnicodeDecodeError) as e:
        sys.exit(f'{p} is not valid JSON: {e}')


def isa_first(isa):
    """the measured variable's letters: P, or PD / TD / … (a difference)"""
    return isa[:2] if len(isa) > 1 and isa[1] == 'D' else isa[:1]


def isa_words(isa, tables):
    if not isa: return ''
    first = isa_first(isa)
    names = tables.get('isa_first', {})
    what = (names.get(first) or (names.get(first[0], '') + ' difference' if len(first) == 2 and names.get(first[0]) else '')).lower()
    rest = isa[len(first):]
    acts = [ISA_FUNCTION[c] for c in rest if ISA_FUNCTION.get(c)]
    if not what and not acts and 'E' not in rest: return ''
    s = f'The instrument letters {isa} say it measures {what or "a process value"}'
    if acts: s += ' and is ' + (', '.join(acts[:-1]) + ' and ' + acts[-1] if len(acts) > 1 else acts[0])
    s += '.'
    if 'E' in rest: s += ' It is the sensing element.'
    return s


def an(word):
    return ('an ' if word[:1].lower() in 'aeiou' else 'a ') + word


def apply_state(tags, state):
    """tags.json + added tags, with review decisions on top (core model.nim merge/eff)"""
    state = state if isinstance(state, dict) else {}
    out = list(tags)
    for a in state.get('added_tags') or []:
        if isinstance(a, dict) and a.get('kks') and isinstance(a.get('bbox'), list) and len(a['bbox']) == 4:
            out.append({'id': 'u:' + str(a.get('id', '')), 'sheet': a.get('sheet', ''), 'kks': a['kks'],
                        'suffix': a.get('suffix') or '', 'isa': a.get('isa') or '', 'bbox': a['bbox']})
    reviews = state.get('reviews') or {}
    res = []
    for t in out:
        tid = t.get('id') if isinstance(t, dict) else None
        r = reviews.get(tid) if isinstance(reviews, dict) and isinstance(tid, str) else None
        if isinstance(r, dict):
            if r.get('status') == 'rejected': continue
            # a person's decision: the reading is checked now (core eff sets "confirmed")
            t = dict(t, kks=r.get('kks') or '', isa=r.get('isa') or '', suffix=r.get('suffix') or '', status='confirmed')
        res.append(t)
    return res


def box(t):
    b = t.get('bbox')
    return b if isinstance(b, list) and len(b) == 4 and all(isinstance(x, (int, float)) for x in b) else None


def nearest(tag, others, k=2, limit=400.0):
    """the closest other codes on the same sheet (box centres, level-0 px), within `limit` px"""
    bx = box(tag)
    if not bx: return []
    cx, cy = (bx[0] + bx[2]) / 2, (bx[1] + bx[3]) / 2
    out = []
    for o in others:
        b = box(o)
        if o is tag or not b or not o.get('kks') or o['kks'] == tag['kks']: continue
        d = math.hypot((b[0] + b[2]) / 2 - cx, (b[1] + b[3]) / 2 - cy)
        if d <= limit: out.append((d, o))
    out.sort(key=lambda x: x[0])
    seen, res = set(), []
    for _, o in out:
        code = o['kks'] + (o.get('suffix') or '')
        if code not in seen: seen.add(code); res.append(o)
        if len(res) == k: break
    return res


def describe(code, tag, sheet_name, tables, near, loc_desc):
    m = KKS_RE.match(tag['kks'])
    if not m: return None
    blk, sysc, fn, comp, _ = m.groups()
    basis, parts = [], []
    sys_name = tables.get('systems', {}).get(sysc, '')
    comp_name = tables.get('components', {}).get(comp, '')
    isa = str(tag.get('isa') or '')
    # the component kind and the instrument letters must agree (a CP read as TDIT: one of them is misread), else only
    # the code's own kind is said, and the letters' disagreement is named for the reviewer
    measures = COMPONENT_MEASURES.get(comp)
    letters_ok = bool(isa) and (measures is None and comp.startswith('C') or measures == isa_first(isa)[:1])
    role = COMPONENT_ROLE.get(comp)
    if role:
        parts.append(f'{code} is {role}.'); basis.append('component kind (general knowledge)')
    elif comp_name:
        parts.append(f'{code} is {an(comp_name.lower())}.'); basis.append('component kind')
    if sys_name:
        parts.append(f'It belongs to {sys_name if sys_name.lower().startswith("the ") else "the " + sys_name} '
                     f'(system {sysc}, section {sysc}{fn}).'); basis.append('KKS system name')
    elif SYSTEM_ROLE.get(sysc):
        parts.append(f'It belongs to {SYSTEM_ROLE[sysc]} (system {sysc}, section {sysc}{fn}).')
        basis.append('KKS system (general knowledge)')
    block = tables.get('blocks', {}).get(blk)
    if block: parts.append(f'Unit: {block}.')
    if isa and letters_ok:
        w = isa_words(isa, tables)
        if w: parts.append(w); basis.append('instrument letters')
    elif isa and comp.startswith('C'):
        parts.append(f'Its instrument letters {isa} don\'t match its code\'s kind: check the drawing.')
    if loc_desc:
        d = loc_desc if len(loc_desc) <= 300 else loc_desc[:297].rstrip() + '…'
        parts.append(f'The location list describes it as "{d}".'); basis.append('location list')
    if near:
        names = []
        for o in near:
            om = KKS_RE.match(o['kks'])
            kind = COMPONENT_SHORT.get(om.group(4), '') if om else ''
            names.append(o['kks'] + str(o.get('suffix') or '') + (f' ({kind})' if kind else ''))
        parts.append(f'On {sheet_name[:120]} it is drawn next to {" and ".join(names)}.'); basis.append('drawing neighbours')
    if not parts: return None
    text = ' '.join(parts)
    while len(text) > MAX_TEXT and len(parts) > 1:   # whole sentences go, never one cut in half
        parts.pop(); text = ' '.join(parts)
    return {'text': text[:MAX_TEXT], 'basis': ', '.join(basis)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('plant_data')
    ap.add_argument('--kks', default=os.path.join(os.path.dirname(__file__), '..', 'data', 'kks.json'))
    ap.add_argument('--out')
    ap.add_argument('--keep', action='store_true', help='leave existing drafts in --out as they are (those of codes no longer on the drawings go)')
    ap.add_argument('--state', help='the state as the apps see it (GET /api/state): added tags and review decisions')
    a = ap.parse_args(argv)
    pd = a.plant_data
    sheet_list, tags = load(os.path.join(pd, 'sheets.json')), load(os.path.join(pd, 'tags.json'))
    if not isinstance(sheet_list, list) or not isinstance(tags, list): sys.exit('sheets.json and tags.json must be lists')
    sheets = {s['id']: s for s in sheet_list if isinstance(s, dict) and isinstance(s.get('id'), str)}
    if a.state: tags = apply_state(tags, load(a.state))
    tables = load(a.kks)
    locs = {}
    ll = load(os.path.join(pd, 'locations.json'), {'entries': []})
    for e in (ll if isinstance(ll, list) else ll.get('entries', []) if isinstance(ll, dict) else []):   # either form, as the core reads it
        if isinstance(e, dict) and isinstance(e.get('desc'), str) and isinstance(e.get('kks'), str) and e['desc'].strip():
            locs.setdefault(e['kks'], e['desc'].strip())
    out = a.out or os.path.join(pd, 'descriptions.json')
    by_sheet = {}
    for t in tags:
        # a reading nobody has checked yet (status "review") gets no draft: it may not be a tag at all
        if not isinstance(t, dict) or not isinstance(t.get('kks'), str) or not t['kks'] or not isinstance(t.get('sheet'), str) \
                or not t['sheet']: continue
        if t.get('status') == 'review': continue
        t = dict(t, kks=clean(t['kks']), suffix=clean(str(t.get('suffix') or '')), isa=clean(str(t.get('isa') or '')))
        by_sheet.setdefault(t['sheet'], []).append(t)
    codes = {t['kks'] + t['suffix'] for ts in by_sheet.values() for t in ts}
    result = {}
    if a.keep:
        old = load(out, {})
        if not isinstance(old, dict): sys.exit(f'{out}: not a JSON object')
        result = {k: v for k, v in old.items() if k in codes}   # drafts of codes no longer drawn go
    n = 0
    for sid, ts in by_sheet.items():
        name = clean(str(sheets.get(sid, {}).get('name') or sid))
        for t in ts:
            code = t['kks'] + t['suffix']
            if code in result: continue
            d = describe(code, t, name, tables, nearest(t, ts), clean(locs.get(t['kks'][2:], '')))
            if d: result[code] = d; n += 1
    tmp = out + '.tmp'
    try:
        with open(tmp, 'w', encoding='utf-8') as f:
            json.dump(result, f, ensure_ascii=False, indent=1, sort_keys=True)
        os.replace(tmp, out)
    finally:
        if os.path.exists(tmp): os.remove(tmp)
    print(f'{out}: {n} new drafts, {len(result)} in all')


def clean(s):
    """text the core's strict reader takes: no lone surrogates (replaced)"""
    return s.encode('utf-8', 'replace').decode('utf-8')


if __name__ == '__main__':
    main()
