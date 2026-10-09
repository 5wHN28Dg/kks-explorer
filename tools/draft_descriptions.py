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

# What each KKS system does in a combined-cycle plant with a heat-recovery steam generator (general knowledge).
SYSTEM_ROLE = {
    'LAA': 'the deaerator system, which removes dissolved oxygen and other gases from the feedwater and holds a reserve '
           'of it for the feed pumps',
    'LAB': 'the feedwater piping, which carries water from the feed pumps through the economisers to the drums',
    'LAE': 'the HP spray (attemperation) system, which injects feedwater into the HP steam to hold its temperature',
    'LAF': 'the IP spray (attemperation) system, which injects water into the reheat steam to hold its temperature',
    'LAW': 'the closed cooling water system, which cools auxiliary equipment in a sealed water loop',
    'LAX': 'the industrial cooling water system, which supplies cooling water to auxiliary coolers',
    'LBA': 'the main (HP) steam piping, which carries superheated steam from the HRSG to the HP turbine',
    'LBB': 'the hot reheat piping, which carries reheated steam from the HRSG to the IP turbine',
    'LBC': 'the cold reheat piping, which returns steam from the HP turbine exhaust to the HRSG reheater',
    'LBG': 'the auxiliary steam piping, which supplies steam for start-up, sealing and heating',
    'LCA': 'the main condensate piping, which carries condensate from the condenser to the HRSG',
    'LCB': 'the main condensate pump system, which lifts condensate from the condenser hotwell',
    'LCC': 'the condensate heating system, which preheats condensate before the deaerator or drums',
    'LCE': 'the condensate desuperheating spray system, which uses condensate to cool steam (e.g. bypass steam)',
    'LCP': 'the standby condensate system, which stores and supplies condensate',
    'LCQ': 'the boiler blowdown system, which drains water from the drums to control dissolved solids',
    'HAC': 'the economiser, which heats feedwater with exhaust gas before it enters the drum',
    'HAD': 'the evaporator system (drum and evaporator tubes), where water is turned into saturated steam',
    'HAH': 'the superheater, which heats saturated steam from the drum above its saturation temperature',
    'HAJ': 'the reheater, which reheats steam returned from the HP turbine',
    'HAN': 'the pressure-system drains and vents, which empty and vent the HRSG pressure parts',
    'HNA': 'the gas duct system, which carries the gas turbine exhaust through the HRSG',
    'HNE': 'the stack, which releases the cooled exhaust gas',
    'MAA': 'the HP turbine',
    'MAB': 'the IP turbine',
    'MAC': 'the LP turbine',
    'MAG': 'the condensing system, which condenses the turbine exhaust steam back to water',
    'MAP': 'the LP turbine bypass, which routes steam around the turbine to the condenser during start-up and trips',
    'QCA': 'the hydrazine dosing system, which removes residual oxygen from the water',
    'QCC': 'the phosphate dosing system, which conditions the drum water',
    'QCD': 'the ammonia dosing system, which controls the water pH',
    'QJF': 'the nitrogen protection system, which blankets idle pressure parts with nitrogen against corrosion',
    'QUA': 'the feedwater sampling system, which takes water samples for chemical analysis',
    'QUB': 'the steam sampling system, which takes steam samples for chemical analysis',
    # standard KKS (VGB) systems on the unit's balance-of-plant drawings, not in data/kks.json
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
    'CY': 'a vibration measurement',
    'CS': 'a speed measurement',
    'CQ': 'an analysis measurement (water or steam chemistry)',
    'CG': 'a position measurement',
    'CE': 'an electrical measurement',
}

ISA_FUNCTION = {'I': 'indicated', 'A': 'alarmed', 'C': 'used for control', 'S': 'used for a switching action (e.g. a trip '
                'or interlock)', 'T': 'transmitted to the control system', 'R': 'recorded', 'Q': 'totalised',
                'E': 'the sensing element'}

KKS_RE = re.compile(r'^(\d\d)([A-Z]{3})(\d\d)([A-Z]{2})(\d{3})$')


def load(p, default=None):
    if not os.path.exists(p):
        if default is not None: return default
        sys.exit(f'{p} is missing')
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def isa_words(isa, tables):
    if not isa: return ''
    first = 'PD' if isa.startswith('PD') else isa[0]
    what = tables.get('isa_first', {}).get(first, '').lower()
    acts = [ISA_FUNCTION[c] for c in isa[len(first):] if c in ISA_FUNCTION]
    if not what and not acts: return ''
    s = f'The instrument letters {isa} say it measures {what or "a process value"}'
    if acts: s += ', ' + (', '.join(acts[:-1]) + ' and ' + acts[-1] if len(acts) > 1 else acts[0])
    return s + '.'


def apply_state(tags, state):
    """tags.json + added tags, with review decisions on top (core model.nim merge/eff)"""
    out = list(tags)
    for a in (state or {}).get('added_tags') or []:
        if isinstance(a, dict) and a.get('kks') and isinstance(a.get('bbox'), list) and len(a['bbox']) == 4:
            out.append({'id': 'u:' + str(a.get('id', '')), 'sheet': a.get('sheet', ''), 'kks': a['kks'],
                        'suffix': a.get('suffix') or '', 'isa': a.get('isa') or '', 'bbox': a['bbox']})
    reviews = (state or {}).get('reviews') or {}
    res = []
    for t in out:
        r = reviews.get(t.get('id')) if isinstance(reviews, dict) else None
        if isinstance(r, dict):
            if r.get('status') == 'rejected': continue
            t = dict(t, kks=r.get('kks') or '', isa=r.get('isa') or '', suffix=r.get('suffix') or '')
        res.append(t)
    return res


def nearest(tag, others, k=2, limit=400.0):
    """the closest other codes on the same sheet (box centres, level-0 px), within `limit` px"""
    bx = tag['bbox']; cx, cy = (bx[0] + bx[2]) / 2, (bx[1] + bx[3]) / 2
    out = []
    for o in others:
        if o is tag or not o.get('kks') or o['kks'] == tag['kks']: continue
        b = o['bbox']; d = math.hypot((b[0] + b[2]) / 2 - cx, (b[1] + b[3]) / 2 - cy)
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
    basis, parts = [], []
    if not m:
        return None
    blk, sysc, fn, comp, _ = m.groups()
    sys_name = tables.get('systems', {}).get(sysc, '')
    comp_name = tables.get('components', {}).get(comp, '')
    role = COMPONENT_ROLE.get(comp)
    sys_role = SYSTEM_ROLE.get(sysc)
    if role:
        parts.append(f'{code} is {role}.')
        basis.append('component kind (general knowledge)')
    elif comp_name:
        parts.append(f'{code} is a {comp_name.lower()}.')
        basis.append('component kind')
    if sys_role:
        parts.append(f'It belongs to {sys_role} (system {sysc}, section {sysc}{fn}).')
        basis.append('KKS system (general knowledge)')
    elif sys_name:
        parts.append(f'It belongs to the {sys_name.lower()} (system {sysc}, section {sysc}{fn}).')
        basis.append('KKS system name')
    block = tables.get('blocks', {}).get(blk)
    if block: parts.append(f'Unit: {block}.')
    w = isa_words(tag.get('isa') or '', tables)
    if w:
        parts.append(w); basis.append('instrument letters')
    if loc_desc:
        parts.append(f'The location list describes it as "{loc_desc}".'); basis.append('location list')
    if near:
        names = []
        for o in near:
            om = KKS_RE.match(o['kks'])
            kind = COMPONENT_ROLE.get(om.group(4), '').split(':')[0] if om else ''
            names.append(o['kks'] + (o.get('suffix') or '') + (f' ({kind.replace("a ", "", 1).replace("an ", "", 1)})' if kind else ''))
        parts.append(f'On {sheet_name} it is drawn next to {" and ".join(names)}.')
        basis.append('drawing neighbours')
    if not parts: return None
    return {'text': ' '.join(parts), 'basis': ', '.join(basis)}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('plant_data')
    ap.add_argument('--kks', default=os.path.join(os.path.dirname(__file__), '..', 'data', 'kks.json'))
    ap.add_argument('--out')
    ap.add_argument('--keep', action='store_true', help='leave existing drafts in --out as they are')
    ap.add_argument('--state', help='the state as the apps see it (GET /api/state): added tags and review decisions')
    a = ap.parse_args(argv)
    pd = a.plant_data
    sheets = {s['id']: s for s in load(os.path.join(pd, 'sheets.json'))}
    tags = load(os.path.join(pd, 'tags.json'))
    if a.state: tags = apply_state(tags, load(a.state))
    tables = load(a.kks)
    locs = {}
    ll = load(os.path.join(pd, 'locations.json'), {'entries': []})
    for e in (ll if isinstance(ll, list) else ll.get('entries', [])):   # either form, as the core reads it
        if isinstance(e, dict) and e.get('desc') and e.get('kks'): locs.setdefault(e['kks'], e['desc'])
    out = a.out or os.path.join(pd, 'descriptions.json')
    result = load(out, {}) if a.keep else {}
    by_sheet = {}
    for t in tags:
        if t.get('kks'): by_sheet.setdefault(t['sheet'], []).append(t)
    n = 0
    for sid, ts in by_sheet.items():
        name = sheets.get(sid, {}).get('name', sid)
        for t in ts:
            code = t['kks'] + (t.get('suffix') or '')
            if code in result: continue
            d = describe(code, t, name, tables, nearest(t, ts), locs.get(t['kks'][2:]))
            if d: result[code] = d; n += 1
    with open(out + '.tmp', 'w', encoding='utf-8') as f:
        json.dump(result, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(out + '.tmp', out)
    print(f'{out}: {n} new drafts, {len(result)} in all')


if __name__ == '__main__':
    main()
