"""The monitoring file (data/plant3d/monitoring.json, format walkdown-plant-monitoring version 1; docs/plant3d/REALISM.md
§2.19, milestone AG3): condition monitoring's points as the app draws them (the collector's spectrum and zones, the
thermal camera's limits, the lab's report), checked against the plant's model. The engine never reads it."""
from ref.courses import need, keys, is_num, num, ident, lst

FORMAT = 'walkdown-plant-monitoring'
KINDS = ('vib', 'ir', 'oil')
LIMITS = {'points': 500, 'lines': 16, 'results': 16, 'sources': 32}


def _text(x, where, hi=120):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1 to {hi} characters')


def _limit_pair(alert, alarm, w):
    """alert before alarm: two numbers (high limits) or two [lo, hi] ranges, the alarm's around the alert's."""
    if is_num(alert):
        num(alarm, f'{w}.alarm')
        need(alert < alarm, 'bad_number', f'{w}: the alert limit below the alarm limit')
        return
    lst(alert, f'{w}.alert', 2, 2)
    lst(alarm, f'{w}.alarm', 2, 2)
    for k, x in (('alert', alert), ('alarm', alarm)):
        num(x[0], f'{w}.{k}')
        num(x[1], f'{w}.{k}', x[0])
    need(alarm[0] < alert[0] and alert[1] < alarm[1], 'bad_number', f'{w}: the alarm range around the alert range')


def _picture(pic, p, m, b, w):
    """The thermal camera's false-colour picture (REALISM.md §9.3): the equipment's own Workshop kind, every component
    of its tree at a model value in °C, the spot on a component at the meter's own value."""
    keys(pic, ('kind', 'spot', 'parts'), (), w)
    need(isinstance(pic['kind'], str) and isinstance(pic['spot'], str), 'bad_type', f'{w}: kind and spot are names')
    eq = m.p.equipment.get(p['code'])
    need(eq is not None and eq.get('part') == pic['kind'], 'bad_ref',
         f'{w}.kind: {pic["kind"]} is not the part kind of {p["code"]}')
    tree = b.workshop_tree.get(pic['kind'])
    need(tree is not None, 'bad_ref', f'{w}.kind: {pic["kind"]} has no Workshop data')
    need(isinstance(pic['parts'], dict) and set(pic['parts']) == set(tree), 'bad_ref',
         f'{w}.parts: every component of the {pic["kind"]} tree, and only those')
    units = {name: n.get('unit') for name, n, _ in m.values}
    for c, v in pic['parts'].items():
        need(isinstance(v, str), 'bad_ref', f'{w}.parts.{c}: a value\'s name')
        need(units.get(v) == '°C' or v == 'ambient_t' and v in m.ext, 'bad_ref',
             f'{w}.parts.{c}: {v!r} is no model value in °C (nor the air\'s, ambient_t)')
    need(pic['spot'] in tree, 'bad_ref', f'{w}.spot: no component {pic["spot"]!r}')
    need(pic['parts'][pic['spot']] == m.meter_ix[p['meter']]['value'], 'bad_ref',
         f'{w}.spot: the spot reads the meter\'s own value')


def check(d, b):
    """Check the monitoring file d against the checked bundle b (its model's values, meters and hand actions)."""
    w0 = 'monitoring.json'
    keys(d, ('format', 'version', 'sources', 'points'), (), w0)
    need(d['format'] == FORMAT, 'bad_value', f'{w0}.format: {FORMAT}')
    need(d['version'] == 1, 'bad_value', f'{w0}.version: 1')
    m = b.model
    kinds = {name: kind for name, n, kind in m.values}
    src = []
    for i, s in enumerate(lst(d['sources'], f'{w0}.sources', 1, LIMITS['sources'])):
        ws = f'{w0}.sources[{i}]'
        keys(s, ('id', 'cite', 'url'), (), ws)
        ident(s['id'], f'{ws}.id')
        need(s['id'] not in src, 'dup_id', f'{ws}: {s["id"]} twice')
        src.append(s['id'])
        _text(s['cite'], f'{ws}.cite', 400)
        need(isinstance(s['url'], str) and s['url'].startswith('https://'), 'bad_value', f'{ws}.url: https')

    def value(x, where):
        need(isinstance(x, str) and x in kinds, 'bad_ref', f'{where}: {x!r} is no value of the model')

    seen = set()
    for i, p in enumerate(lst(d['points'], f'{w0}.points', 1, LIMITS['points'])):
        w = f'{w0}.points[{i}]'
        need(isinstance(p, dict) and p.get('kind') in KINDS, 'bad_value', f'{w}.kind: one of {KINDS}')
        k = p['kind']
        need((p.get('code'), k) not in seen, 'dup_id', f'{w}: a second {k} point at {p.get("code")}')
        seen.add((p.get('code'), k))
        if k in ('vib', 'ir'):
            req = ('code', 'kind', 'title', 'meter') + (('rpm', 'group', 'zones', 'floor', 'lines') if k == 'vib'
                                                         else ('limits',))
            keys(p, req, ('tones',) if k == 'vib' else ('picture',), w)
            mt = m.meter_ix.get(p['meter'])
            need(mt is not None, 'bad_ref', f'{w}.meter: {p["meter"]} is no meter of the model')
            need(mt['kks'] == p['code'], 'bad_ref', f'{w}.meter: {p["meter"]} is at {mt["kks"]}, not {p["code"]}')
            need(mt['tool_kind'] == ('collector' if k == 'vib' else 'camera'), 'bad_ref',
                 f'{w}.meter: a {"collector" if k == "vib" else "camera"} meter')
        else:
            keys(p, ('code', 'kind', 'title', 'action', 'hours', 'results'), (), w)
            h = m.hand_keys.get((p['code'], p['action']))
            need(h is not None and 'samples' in h, 'bad_ref',
                 f'{w}.action: {p["action"]} is no sampling hand action at {p["code"]}')
            num(p['hours'], f'{w}.hours', 0, 8760)
        _text(p['title'], f'{w}.title')
        if k == 'vib':
            num(p['rpm'], f'{w}.rpm', 1, 100000)
            need(p['group'] in (1, 2), 'bad_value', f'{w}.group: ISO 20816-3 group 1 or 2')
            z = lst(p['zones'], f'{w}.zones', 3, 3)
            for j, x in enumerate(z):
                num(x, f'{w}.zones[{j}]', 0)
            need(z[0] < z[1] < z[2], 'bad_number', f'{w}.zones: the boundaries A/B, B/C, C/D in order')
            num(p['floor'], f'{w}.floor', 0, z[0])
            if 'tones' in p:
                need(isinstance(p['tones'], dict) and set(p['tones']) <= {'bpfo', 'bpfi', 'bsf', 'ftf'}, 'bad_value',
                     f'{w}.tones: the bearing defect orders')
                for t, x in p['tones'].items():
                    num(x, f'{w}.tones.{t}', 0)
            for j, ln in enumerate(lst(p['lines'], f'{w}.lines', 1, LIMITS['lines'])):
                wl = f'{w}.lines[{j}]'
                keys(ln, ('name', 'order'), ('value', 'share', 'by'), wl)
                _text(ln['name'], f'{wl}.name', 24)
                num(ln['order'], f'{wl}.order', 0)
                need(ln['order'] > 0, 'bad_number', f'{wl}.order: above 0')
                need('value' in ln or 'share' in ln, 'missing_key', f'{wl}: a value or a share of the overall')
                for kk in ('value', 'by'):
                    if kk in ln:
                        value(ln[kk], f'{wl}.{kk}')
                if 'share' in ln:
                    num(ln['share'], f'{wl}.share', 0, 1)
        elif k == 'ir':
            lim = lst(p['limits'], f'{w}.limits', 2, 2)
            num(lim[0], f'{w}.limits')
            num(lim[1], f'{w}.limits', lim[0])
            need(lim[0] < lim[1], 'bad_number', f'{w}.limits: the alert below the alarm')
            if 'picture' in p:
                _picture(p['picture'], p, m, b, f'{w}.picture')
        else:
            h = m.hand_keys[(p['code'], p['action'])]
            nodes = []
            for j, r in enumerate(lst(p['results'], f'{w}.results', 1, LIMITS['results'])):
                wr = f'{w}.results[{j}]'
                keys(r, ('node', 'title', 'unit', 'alert', 'alarm'), (), wr)
                need(kinds.get(r['node']) == 'sample', 'bad_ref', f'{wr}.node: {r["node"]} is no sample node')
                need(r['node'] in h['samples'], 'bad_ref', f'{wr}.node: {r["node"]} is not taken by {p["action"]}')
                need(r['node'] not in nodes, 'dup_id', f'{wr}.node: {r["node"]} twice')
                nodes.append(r['node'])
                _text(r['title'], f'{wr}.title', 40)
                need(isinstance(r['unit'], str) and len(r['unit']) <= 8, 'bad_type', f'{wr}.unit: text of 0 to 8')
                _limit_pair(r['alert'], r['alarm'], wr)
            need(set(nodes) == set(h['samples']), 'bad_ref', f'{w}.results: every sample node {p["action"]} takes')
            hrs = {n['hours'] for name, n, kind in m.values if name in nodes}
            need(hrs == {p['hours']}, 'bad_ref', f'{w}.hours: the sample nodes\' own hours')
    return d
