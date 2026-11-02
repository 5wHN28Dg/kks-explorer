"""Walkdown Plant's Workshop data (docs/plant3d/WORKSHOP.md §4, milestone K1a): the reference validator of a part
kind's Workshop data file, `data/plant3d/workshop/<part>.json`.

The data file holds what is words, order and choice (names, what each component does, materials as text, sealing,
the fastener groups' names and what they join, the assembly order and its sentences, the views, the sources); the
kit's generator holds the geometry (components' pivots, boxes, explode, fasteners' positions). The content build
(apps/plant3d/builder/workshop_build.gd) joins the two and refuses a kind whose halves disagree; this file checks the
data file alone: strict JSON, keys, identifiers, lengths, references, the assembly's integrity and the sources.
"""
import re
from ref import sjson
from ref.courses import FormatError, ID, need, keys, num, lst

FORMAT = 'walkdown-plant-workshop'
VERSION = 1
CID = re.compile(r'[a-z_][a-z0-9_]{0,15}')      # component and fastener group ids (§4.1: at most 16 characters)
SID = re.compile(r'[a-z_][a-z0-9_]{0,31}')      # source ids
MAX = {'components': 200, 'fasteners': 64, 'sources': 64, 'steps': 400, 'needs': 16, 'planes': 2}
FASTENER_KINDS = ('bolt', 'stud_nut', 'screw', 'cap_screw', 'threaded_cover', 'clamp', 'gland', 'pin', 'circlip', 'key')


def cid(x, where):
    need(isinstance(x, str) and CID.fullmatch(x) is not None, 'bad_id', f'{where}: an identifier of at most 16 characters')
    return x


def words(x, where, hi):
    need(isinstance(x, str) and 1 <= len(x) <= hi and x == x.strip(), 'bad_type', f'{where}: text of 1–{hi} characters')
    return x


def loads(data, where='workshop'):
    try:
        return sjson.loads(data)
    except sjson.StrictError as e:
        raise FormatError('bad_json', f'{where}: {e}')


def check(w, kit=None, where='workshop', parts=None):
    """Checks one Workshop data file (parsed). `kit` is the checked kit.json (its parts and parameters), or None to
    check against `parts` only (a test fixture's kind, which kit.json doesn't have). Returns a summary:
    {part, components, fasteners, steps, sources}."""
    from ref import plant3d as P
    from ref.plant3d import PlantText
    keys(w, ('format', 'version', 'part', 'sources', 'components'), ('params', 'fasteners', 'assembly', 'views'), where)
    need(w['format'] == FORMAT, 'bad_format', f'{where}.format: {FORMAT}')
    need(w['version'] == VERSION and type(w['version']) is int, 'bad_version', f'{where}.version: {VERSION}')
    part = w['part']
    need(isinstance(part, str) and ID.fullmatch(part) is not None, 'bad_id', f'{where}.part')
    if kit is not None and part in kit['parts']:
        if 'params' in w:    # else the builder takes the plant's first instance of the kind (WORKSHOP.md §5)
            P.params_of(kit, part, w['params'], where)
        need(kit['parts'][part]['group'] != 'structures', 'bad_ref', f'{where}.part: {part} is a structure')
    else:
        need(parts is not None and part in parts, 'bad_ref', f'{where}.part: no kit part {part!r}')
        need(isinstance(w.get('params', {}), dict), 'bad_type', f'{where}.params')
    # sources: {id, cite, url}, each referred to at least once
    srcs = {}
    for i, s in enumerate(lst(w['sources'], f'{where}.sources', 1, MAX['sources'])):
        sw = f'{where}.sources[{i}]'
        keys(s, ('id', 'cite', 'url'), (), sw)
        need(isinstance(s['id'], str) and SID.fullmatch(s['id']) is not None, 'bad_id', f'{sw}.id')
        need(s['id'] not in srcs, 'dup_id', f'{sw}.id: {s["id"]}')
        words(s['cite'], f'{sw}.cite', 300)
        need(isinstance(s['url'], str) and re.fullmatch(r'https://[^\s]+', s['url']) is not None, 'bad_link',
             f'{sw}.url: an https address')
        srcs[s['id']] = 0

    def cite(lst_, sw):
        for x in lst(lst_, sw, 1, 16):
            need(x in srcs, 'bad_ref', f'{sw}: no source {x!r}')
            srcs[x] += 1

    comps = w['components']
    need(isinstance(comps, dict) and 1 <= len(comps) <= MAX['components'], 'bad_length',
         f'{where}.components: 1–{MAX["components"]}')
    for c, d in comps.items():
        cw = f'{where}.components.{c}'
        cid(c, cw)
        keys(d, ('name', 'does', 'material', 'sources'), ('sealed', 'sealed_why'), cw)
        words(d['name'], f'{cw}.name', 60)
        words(d['does'], f'{cw}.does', 300)
        words(d['material'], f'{cw}.material', 80)
        cite(d['sources'], f'{cw}.sources')
        if 'sealed' in d:
            need(d['sealed'] is True, 'bad_value', f'{cw}.sealed: true, or leave it out')
            need('sealed_why' in d, 'missing_key', f'{cw}.sealed_why: why it never comes apart')
            words(d['sealed_why'], f'{cw}.sealed_why', 300)
        else:
            need('sealed_why' not in d, 'unknown_key', f'{cw}.sealed_why: only for a sealed component')
    fast = w.get('fasteners', {})
    need(isinstance(fast, dict) and len(fast) <= MAX['fasteners'], 'bad_length', f'{where}.fasteners')
    for g, d in fast.items():
        gw = f'{where}.fasteners.{g}'
        cid(g, gw)
        need(g not in comps, 'dup_id', f'{gw}: a component has that id')
        keys(d, ('name', 'joins', 'sources'), (), gw)
        words(d['name'], f'{gw}.name', 60)
        joins = lst(d['joins'], f'{gw}.joins', 2, 16)
        need(len(set(joins)) == len(joins), 'dup_id', f'{gw}.joins')
        for j in joins:
            need(j in comps, 'bad_ref', f'{gw}.joins: no component {j!r}')
        cite(d['sources'], f'{gw}.sources')
    steps = 0
    if 'assembly' in w:
        steps = _assembly(w['assembly'], comps, fast, cite, PlantText(set()), f'{where}.assembly')
    if 'views' in w:
        _views(w['views'], comps, f'{where}.views')
    for s, n in srcs.items():
        need(n > 0, 'unused', f'{where}.sources: {s} is cited nowhere')
    return {'part': part, 'components': len(comps), 'fasteners': len(fast), 'steps': steps, 'sources': len(srcs)}


def _assembly(a, comps, fast, cite, tx, where):
    """§4.6: one step per component or fastener group, each placed once, every need an existing component placed
    before the step that needs it (the guided order passes its own needs)."""
    placed = []
    for i, s in enumerate(lst(a, where, 1, MAX['steps'])):
        sw = f'{where}[{i}]'
        keys(s, ('place', 'text', 'sources'), ('why', 'needs'), sw)
        p = s['place']
        need(isinstance(p, str) and (p in comps or p in fast), 'bad_ref', f'{sw}.place: no component or group {p!r}')
        need(p not in placed, 'dup_id', f'{sw}.place: {p} is placed twice')
        tx.run(s['text'], f'{sw}.text')
        if 'why' in s:
            tx.run(s['why'], f'{sw}.why')
        for k, n in enumerate(lst(s.get('needs', []), f'{sw}.needs', 0, MAX['needs'])):
            nw = f'{sw}.needs[{k}]'
            lst(n, nw, 3, 3)
            need(isinstance(n[0], str) and n[0] in comps, 'bad_ref', f'{nw}: no component {n[0]!r}')
            need(n[0] != p, 'bad_ref', f'{nw}: a step needs another component')
            need(n[0] in placed, 'bad_order', f'{nw}: {n[0]} is placed after the step that needs it')
            words(n[1], f'{nw}: the sentence for placing too early', 300)
            words(n[2], f'{nw}: the sentence for removing too early', 300)
        cite(s['sources'], f'{sw}.sources')
        placed.append(p)
    for c in list(comps) + list(fast):
        need(c in placed, 'missing', f'{where}: {c} is never placed')
    return len(placed)


def _views(v, comps, where):
    keys(v, (), ('xray_all', 'cutaway', 'run_exploded'), where)
    for c in lst(v.get('xray_all', []), f'{where}.xray_all', 0, MAX['components']):
        need(c in comps, 'bad_ref', f'{where}.xray_all: no component {c!r}')
    if 'cutaway' in v:
        cw = f'{where}.cutaway'
        keys(v['cutaway'], ('planes',), ('keep',), cw)
        for i, pl in enumerate(lst(v['cutaway']['planes'], f'{cw}.planes', 1, MAX['planes'])):
            pw = f'{cw}.planes[{i}]'
            keys(pl, ('normal', 'offset'), (), pw)
            n = lst(pl['normal'], f'{pw}.normal', 3, 3)
            for x in n:
                num(x, f'{pw}.normal', -1, 1)
            need(abs(sum(x * x for x in n) - 1.0) < 1e-6, 'bad_number', f'{pw}.normal: a unit vector')
            num(pl['offset'], f'{pw}.offset', -0.5, 0.5)
        for c in lst(v['cutaway'].get('keep', []), f'{cw}.keep', 0, MAX['components']):
            need(c in comps, 'bad_ref', f'{cw}.keep: no component {c!r}')
    if 'run_exploded' in v:
        r = v['run_exploded']
        rw = f'{where}.run_exploded'
        if r is not True:
            keys(r, ('allowed', 'why'), (), rw)
            for c in lst(r['allowed'], f'{rw}.allowed', 0, MAX['components']):
                need(c in comps, 'bad_ref', f'{rw}.allowed: no component {c!r}')
            words(r['why'], f'{rw}.why', 300)
