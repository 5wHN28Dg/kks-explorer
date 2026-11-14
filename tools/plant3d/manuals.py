#!/usr/bin/env python3
"""The generic plant's equipment manuals (docs/plant3d/REALISM.md §6.2, §6.2.1; milestone DC2): written for the kit's
part kinds in our own words (tools/plant3d/manual_texts/<id>.py), completed from the content (the kit's parameters, every
code of the manual's kinds, the Workshop trees, the service files' actions, the scenarios' hidden causes) and checked.
A view of the content, as the P&IDs are: made at every build of the app, never committed. The figures are drawn
afterwards by the app's build (apps/plant3d/builder/manual_figures.gd) from the index's `figures`.

    python3 tools/plant3d/manuals.py OUT_DIR     # writes index.json and a file per manual (apps/plant3d/build.sh)
    python3 tools/plant3d/manuals.py --check     # makes them and runs the checks only

Formats `walkdown-plant-manual` and `walkdown-plant-manuals`, version 1 (REALISM.md §6.2.1)."""
import importlib, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import pid  # noqa: E402  (the content's items: every code with its part kind and parameters)

DATA = os.path.join(ROOT, 'data', 'plant3d')
ORDER = ['pressure_transmitter', 'control_valve', 'valves', 'pumps', 'steam_turbine', 'gas_turbine']
REQUIRED = ['description', 'specifications', 'installation', 'commissioning', 'operation', 'maintenance',
            'troubleshooting', 'parts', 'safety']
CALLOUTS = ('warning', 'caution', 'note')
VIEWS = ('exploded', 'cut')
FIG_W, FIG_H = 960, 600
ID = re.compile(r'^[a-z][a-z0-9_]{0,31}$')
KKS = re.compile(r'^[0-9A-Z]{4,24}$')


class ManualError(Exception):
    pass


def fail(where, what):
    raise ManualError('%s: %s' % (where, what))


# ================================================================ inline markup -> COURSES.md runs

_LINK = re.compile(r'\[([^\]]+)\]\(([^)\s]+)\)')


def run(text, where):
    """COURSES.md §3 run from the markup (manual_blocks.py): never empty."""
    if not isinstance(text, str) or not text.strip():
        fail(where, 'an empty text')
    out = _inline(text, where)
    if not out:
        fail(where, 'an empty text')
    return out


def _inline(text, where):
    out, buf, i = [], [], 0

    def flush():
        if buf:
            out.append(''.join(buf))
            buf.clear()
    while i < len(text):
        ch = text[i]
        if ch == '\\' and i + 1 < len(text):
            buf.append(text[i + 1])
            i += 2
            continue
        if text.startswith('**', i):
            j = text.find('**', i + 2)
            if j < 0:
                fail(where, 'an unclosed ** in %r' % text)
            flush()
            out.append({'b': _nonempty(_inline(text[i + 2:j], where), text, where)})
            i = j + 2
            continue
        if ch in '*~`':
            j = text.find(ch, i + 1)
            if j < 0:
                fail(where, 'an unclosed %s in %r' % (ch, text))
            flush()
            inner = text[i + 1:j]
            if ch == '*' and (inner.startswith('*') or text[j + 1:j + 2] == '*'):
                fail(where, 'emphasis holding strong (not in a run) in %r' % text)
            if ch == '`':
                if not inner.strip():
                    fail(where, 'an empty number in %r' % text)
                out.append({'num': inner})
            else:
                out.append({'i' if ch == '*' else 'small': _nonempty(_inline(inner, where), text, where)})
            i = j + 1
            continue
        if ch == '[':
            m = _LINK.match(text, i)
            if not m:
                fail(where, 'a [ that is no link in %r' % text)
            flush()
            out.append({'link': _nonempty(_inline(m.group(1), where), text, where), 'to': target(m.group(2), where)})
            i = m.end()
            continue
        buf.append(ch)
        i += 1
    flush()
    return out


def _nonempty(r, text, where):
    if not ''.join(x if isinstance(x, str) else 'x' for x in r).strip():
        fail(where, 'an empty text inside markup in %r' % text)
    return r


def target(t, where):
    if t.startswith('#'):
        return {'section': t[1:]}
    kind, _, rest = t.partition(':')
    if kind == 'manual':
        m, _, s = rest.partition('#')
        return {'manual': m, 'section': s} if s else {'manual': m}
    if kind == 'kks':
        return {'kks': rest}
    if kind == 'work':
        return {'work': rest}
    if kind == 'workshop':
        k, _, place = rest.partition('/')
        return {'workshop': k, 'place': place}
    fail(where, 'an unknown link target %r' % t)


def walk_blocks(x, fn):
    """Calls fn(block) for every dict inside sections and blocks, nested."""
    if isinstance(x, list):
        for v in x:
            walk_blocks(v, fn)
    elif isinstance(x, dict):
        fn(x)
        for v in x.values():
            walk_blocks(v, fn)


def walk_runs(x, fn):
    """Calls fn(item) for every run item inside a block or run, nested."""
    if isinstance(x, list):
        for v in x:
            walk_runs(v, fn)
    elif isinstance(x, dict):
        if 'to' in x:
            fn(x)
        for k, v in x.items():
            if k != 'to':
                walk_runs(v, fn)


# ================================================================ the content

def load_content(data=DATA):
    plant, areas, _codes = pid.load(data)
    items = pid.items_of(areas)
    with open(os.path.join(data, 'kit.json'), encoding='utf-8') as f:
        kit = json.load(f)['parts']
    workshop, service = {}, {}
    wdir, sdir = os.path.join(data, 'workshop'), os.path.join(data, 'service')
    for n in sorted(os.listdir(wdir)):
        if n.endswith('.json'):
            with open(os.path.join(wdir, n), encoding='utf-8') as f:
                w = json.load(f)
            workshop[w['part']] = w
    for n in sorted(os.listdir(sdir)) if os.path.isdir(sdir) else []:
        if n.endswith('.json'):
            with open(os.path.join(sdir, n), encoding='utf-8') as f:
                s = json.load(f)
            service[s['part']] = s
    causes = {}                                        # part kind -> {cause id}
    scen = os.path.join(data, 'scenarios')
    for n in sorted(x for x in os.listdir(scen) if x.endswith('.json')):
        with open(os.path.join(scen, n), encoding='utf-8') as f:
            sc = json.load(f)
        for fault in sc.get('faults', []):
            it = items.get(fault.get('kks', ''))
            for c in fault.get('causes', []):
                if it is not None:
                    causes.setdefault(it.part, set()).add(c['id'])
    return {'items': items, 'kit': kit, 'workshop': workshop, 'service': service, 'causes': causes}


# ================================================================ the units' own parameters

def _num(v):
    return ('%g' % v) if isinstance(v, (int, float)) else str(v)


def unit_rows(item, labels):
    """[[label, value]] of a code's own parameters, in the kit's order."""
    p = item.raw.get('params', {})
    rows = []
    if 'range' in p:
        lo, hi = p['range']
        rows.append([labels.get('range', 'Calibrated range'), '%s to %s %s' % (_num(lo), _num(hi), p.get('unit', ''))])
    for k, v in p.items():
        if k in ('range', 'unit') or k not in labels:
            continue
        lab = labels[k]
        if isinstance(v, list):
            v = ', '.join(x.get('kind', '?').upper() if isinstance(x, dict) else _num(x) for x in v)
        elif isinstance(v, str) and re.match(r'^pn[0-9]+$', v):
            v = 'PN ' + v[2:]
        lab, fmt = lab if isinstance(lab, (list, tuple)) else (lab, '{}')
        rows.append([lab, fmt.format(_num(v))])
    return rows


# ================================================================ one manual

def make_manual(src, content, all_ids):
    m = src.MANUAL
    mid = m['id']
    where = 'manual %s' % mid
    if not ID.match(mid):
        fail(where, 'a bad id')
    kinds = list(m['kinds'])
    for k in kinds:
        if k not in content['kit']:
            fail(where, 'no kit part kind %r' % k)
    sources = {s['id']: s for s in m['sources']}
    sec_ids = [s['id'] for s in m['sections']]
    if len(set(sec_ids)) != len(sec_ids):
        fail(where, 'a section id given twice')
    for r in REQUIRED:
        if r not in sec_ids:
            fail(where, 'no %s section' % r)
    figures = []
    fig_ids = {}
    for f in m.get('figures', []):
        if len(f) not in (3, 5):
            fail(where, 'a figure is (kind, view, caption[, yaw, pitch]): %r' % (f,))
        kind, view, caption = f[0], f[1], f[2]
        yaw, pitch = (f[3], f[4]) if len(f) == 5 else (35, 25)
        if kind not in kinds or view not in VIEWS:
            fail(where, 'a figure of %s %s' % (kind, view))
        if (kind, view) in fig_ids:
            fail(where, 'figure %s %s listed twice' % (kind, view))
        w = content['workshop'].get(kind)
        if w is None or (view == 'cut' and not w.get('views', {}).get('cutaway', {}).get('planes')):
            fig_ids[(kind, view)] = None               # (its figures come with its Workshop scene and cutaway)
            continue
        fid = '%s-%s' % (kind, view)
        fig_ids[(kind, view)] = fid
        figures.append({'id': fid, 'kind': kind, 'view': view, 'caption': run(caption, where + ' figure ' + fid),
                        'file': fid + '.wfig', 'w': FIG_W, 'h': FIG_H, 'yaw': yaw, 'pitch': pitch})
    used_src = set()
    sections = []
    for s in m['sections']:
        sw = '%s section %s' % (where, s['id'])
        if not ID.match(s['id']):
            fail(sw, 'a bad id')
        for sid in s['src']:
            if sid not in sources:
                fail(sw, 'cites %r, which the manual does not list' % sid)
            used_src.add(sid)
        blocks = []
        for b in s['blocks']:
            out = block(b, sw, m, content, fig_ids)
            if out is not None:
                blocks.extend(out if isinstance(out, list) else [out])
        if not blocks:
            fail(sw, 'no blocks')
        sections.append({'id': s['id'], 'title': run(s['title'], sw), 'blocks': blocks, 'src': list(s['src'])})
    placed = set()
    walk_blocks(sections, lambda b: placed.add(b['figure']) if 'figure' in b else None)
    for f in figures:
        if f['id'] not in placed:
            fail(where, 'figure %s is listed but no section shows it' % f['id'])
    for sid in sources:
        if sid not in used_src:
            fail(where, 'lists source %r, which no section cites' % sid)
    for s in m['sources']:
        if not s.get('cite', '').strip():
            fail(where, 'source %r without a citation' % s['id'])
    out = {'format': 'walkdown-plant-manual', 'version': 1, 'id': mid, 'number': m['number'], 'title': m['title'],
           'short': m['short'], 'kinds': kinds,
           **({'kind_tags': m['kind_tags']} if len(m['kinds']) > 1 else {}),
           'sources': [{k: s[k] for k in ('id', 'cite', 'url') if k in s} for s in m['sources']],
           'figures': figures, 'sections': sections}
    check_links(out, content, all_ids)
    return out


def block(b, where, m, content, fig_ids):
    if 'h' in b:
        return {'h': run(b['h'], where), 'level': 3}
    if 'p' in b:
        return {'p': run(b['p'], where)}
    for k in ('ul', 'ol'):
        if k in b:
            if not b[k]:
                fail(where, 'an empty list')
            return {k: [run(x, where) for x in b[k]]}
    if 'table' in b:
        t = b['table']
        head = [run(h, where) for h in t['head']]
        rows = []
        for r in t['rows']:
            if len(r) != len(head):
                fail(where, 'a table row of %d cells under %d heads' % (len(r), len(head)))
            rows.append([run(c, where) for c in r])
        return {'table': {'head': head, 'rows': rows, 'num': list(t.get('num', []))}}
    if 'callout' in b:
        if b['callout'] not in CALLOUTS:
            fail(where, 'a callout of kind %r' % b['callout'])
        body = []
        for x in b['body']:
            y = block(x, where, m, content, fig_ids)
            if not isinstance(y, dict) or not any(k in y for k in ('p', 'ul', 'ol', 'table')):
                fail(where, 'a callout holding more than text, lists and tables')
            body.append(y)
        return {'callout': b['callout'], 'label': run(b['label'], where), 'body': body}
    if 'figure' in b:
        kind, view = b['figure']
        if kind not in m['kinds']:
            fail(where, 'a figure of %s, not a kind of this manual' % kind)
        if (kind, view) not in fig_ids:
            fail(where, 'a figure %s %s the manual does not list' % (kind, view))
        if fig_ids[(kind, view)] is None:
            return None                                # (no Workshop scene, or no cutaway, yet)
        return {'figure': fig_ids[(kind, view)]}
    if 'trouble' in b:
        rows = []
        known = set()
        for k in m['kinds']:
            known |= content['causes'].get(k, set())
        ids = [r['id'] for r in b['trouble'] if 'id' in r]
        if len(set(ids)) != len(ids):
            fail(where, 'a troubleshooting cause id twice')
        for r in b['trouble']:
            row = {'symptom': run(r['symptom'], where), 'cause': run(r['cause'], where),
                   'remedy': run(r['remedy'], where)}
            if 'id' in r:
                if r['id'] not in known:
                    fail(where, 'troubleshooting cause %r: no fault of the manual\'s kinds has it' % r['id'])
                row['id'] = r['id']
            rows.append(row)
        if not rows:
            fail(where, 'an empty troubleshooting table')
        return {'trouble': rows}
    if b.get('unit') is True:
        return {'unit': True}
    if b.get('series') is True:
        return series_table(m, content, where)
    if b.get('parts') is True:
        return parts_table(m, content, where)
    fail(where, 'an unknown block %r' % list(b))


def series_table(m, content, where):
    """The kit parameters' ranges for the manual's kinds."""
    rows = []
    labels = m.get('params', {})
    for k in m['kinds']:
        for name, p in content['kit'][k].get('params', {}).items():
            if name not in labels and name != 'range':
                continue
            lab = labels.get(name, 'Calibrated range')
            lab, fmt = lab if isinstance(lab, (list, tuple)) else (lab, '{}')
            t = p.get('type')
            if t in ('num', 'int'):
                rng = '%s to %s' % (fmt.format(_num(p['min'])), fmt.format(_num(p['max'])))
            elif t == 'enum':
                rng = ', '.join(('PN ' + v[2:]) if re.match(r'^pn[0-9]+$', v) else str(v) for v in p['values'])
            elif t == 'pair':
                rng = 'any span, set at calibration'
            else:
                rng = 'as ordered'
            dflt = _num(p['default']) if 'default' in p else '—'
            if re.match(r'^pn[0-9]+$', dflt):
                dflt = 'PN ' + dflt[2:]
            elif t in ('num', 'int'):
                dflt = fmt.format(dflt)
            rows.append([m['kind_names'][k], lab, rng, dflt])
    if not rows:
        fail(where, 'no kit parameters to list')
    return {'table': {'head': [['Kind'], ['Parameter'], ['What the generic kit allows'], ['Kit default']],
                      'rows': [[run(_esc(c), where) for c in r] for r in rows], 'num': []}}


def _esc(s):
    """The content's words as plain text in the markup."""
    return re.sub(r'([*~`\[\]\\])', r'\\\1', s)


def part_number(m, pid_):
    return 'WDP-%s-%s' % (m['short'], pid_.upper().replace('_', '-'))


def parts_table(m, content, where):
    """Spare parts: the Workshop tree's components and fastener groups (not the insides that come with a sealed
    part: the manual's `comes_with`), then the manual's consumables."""
    rows = []
    comes = m.get('comes_with', {})
    tree_ids = set()
    matched = set()   # comes_with's parts some kind's tree has (in a manual of several kinds, one kind's alone may)
    trees = 0
    for k in m['kinds']:
        w = content['workshop'].get(k)
        if w is None:
            continue
        trees += 1
        # a manual of several kinds numbers each kind's tree apart (`kind_tags`): their components share ids
        tag = m['kind_tags'][k] + '-' if len(m['kinds']) > 1 else ''
        for c, parent in comes.items():
            if (c in w['components']) != (parent in w['components']):
                fail(where, 'comes_with %s -> %s: not both components of %s' % (c, parent, k))
            if c in w['components']:
                matched.add(c)
        # and this kind's own (`comes_with_kinds`: in a manual of several kinds, parts that come with a sealed part
        # of one kind, whose ids another kind's tree uses for parts of its own)
        ck = dict(comes)
        for c, parent in m.get('comes_with_kinds', {}).get(k, {}).items():
            if c not in w['components'] or parent not in w['components']:
                fail(where, 'comes_with_kinds %s: %s -> %s not both components of it' % (k, c, parent))
            ck[c] = parent
        for cid, c in w['components'].items():
            if cid in ck:
                continue
            inside = [x for x, p in ck.items() if p == cid]
            note = c.get('material', '')
            if inside:
                names = [w['components'][x]['name'][0].lower() + w['components'][x]['name'][1:] for x in inside]
                names = ', '.join(names[:-1]) + ' and ' + names[-1] if len(names) > 1 else names[0]
                note = (note + '; ' if note else '') + 'comes with its ' + names
            rows.append([part_number(m, tag + cid), c['name'], '1', note or '—'])
            tree_ids.add(tag + cid)
        for gid, g in w.get('fasteners', {}).items():
            rows.append([part_number(m, tag + gid), g['name'], '1 set' if g['name'][:1].isdigit() else '1',
                         'Replace when damaged or stretched'])
            tree_ids.add(tag + gid)
    if trees and set(comes) - matched:
        fail(where, 'comes_with %s: no kind of this manual has them' % ', '.join(sorted(set(comes) - matched)))
    for cid, name, qty, note in m.get('consumables', []):
        if cid in tree_ids:
            continue                                   # (the Workshop tree's own row for that part stands)
        rows.append([part_number(m, cid), name, qty, note])
    if not rows:
        fail(where, 'no spare parts')
    nums = [r[0] for r in rows]
    if len(set(nums)) != len(nums):
        fail(where, 'a part number twice')
    return {'table': {'head': [['Part number'], ['Part'], ['Qty'], ['Material, notes']],
                      'rows': [[run(_esc(c), where) for c in r] for r in rows], 'num': []}}


def check_links(man, content, all_ids):
    where = 'manual %s' % man['id']
    secs = {s['id'] for s in man['sections']}

    def one(item):
        t = item['to']
        if 'section' in t and 'manual' not in t:
            if t['section'] not in secs:
                fail(where, 'a link to section %r, which it does not have' % t['section'])
        elif 'manual' in t:
            if t['manual'] not in all_ids:
                fail(where, 'a link to manual %r, which does not exist' % t['manual'])
            if 'section' in t and t['section'] not in all_ids[t['manual']]:
                fail(where, 'a link to %s#%s, which does not exist' % (t['manual'], t['section']))
        elif 'kks' in t:
            if not KKS.match(t['kks']) or t['kks'] not in content['items']:
                fail(where, 'a link to code %r, which is not in the plant' % t['kks'])
        elif 'work' in t:
            acts = set()
            for k in man['kinds']:
                acts |= {a['action'] for a in content['service'].get(k, {}).get('actions', [])}
            if t['work'] not in acts:
                fail(where, 'a link to work action %r, which no service file of its kinds has' % t['work'])
        elif 'workshop' in t:
            if t['workshop'] not in man['kinds']:
                fail(where, 'a link to the Workshop of %r, not a kind of this manual' % t['workshop'])
            w = content['workshop'].get(t['workshop'])
            if w is None:
                fail(where, 'a link to the Workshop of %r, which has no Workshop data' % t['workshop'])
            if t['place'] not in {a['place'] for a in w['assembly']}:
                fail(where, 'a link to Workshop step %s/%s, which no guided step places' % (t['workshop'], t['place']))
        else:
            fail(where, 'a link target %r' % t)
    walk_runs(man['sections'], one)
    walk_runs([f['caption'] for f in man['figures']], one)


# ================================================================ the set

def sources():
    have = sorted(n[:-3] for n in os.listdir(os.path.join(HERE, 'manual_texts'))
                  if n.endswith('.py') and not n.startswith('_'))
    if have != sorted(ORDER):
        fail('manual_texts', 'the text files %s are not the ORDER %s' % (have, ORDER))
    out = []
    for mid in ORDER:
        s = importlib.import_module('manual_texts.' + mid)
        if s.MANUAL.get('id') != mid:
            fail('manual_texts/%s.py' % mid, 'holds manual %r' % s.MANUAL.get('id'))
        out.append(s)
    return out


def make(data=DATA):
    """(index, {manual id: manual}) made and checked."""
    content = load_content(data)
    srcs = sources()
    all_ids = {s.MANUAL['id']: {x['id'] for x in s.MANUAL['sections']} for s in srcs}
    manuals, kinds, units, work, wshop, figs = {}, {}, {}, {}, {}, []
    for i, s in enumerate(srcs):
        try:
            man = make_manual(s, content, all_ids)
        except (KeyError, IndexError, TypeError, ValueError) as e:
            raise ManualError('manual %s: malformed (%s: %s)' % (s.MANUAL.get('id'), type(e).__name__, e))
        if man['number'] != 'WDP-MAN-%03d' % (i + 1):
            fail('manual %s' % man['id'], 'numbered %s, not in order' % man['number'])
        manuals[man['id']] = man
        for k in man['kinds']:
            if k in kinds:
                fail('manual %s' % man['id'], 'kind %s already has manual %s' % (k, kinds[k]))
            kinds[k] = man['id']
        labels = s.MANUAL.get('params', {})
        for code in sorted(content['items']):
            it = content['items'][code]
            if it.part in man['kinds']:
                units[code] = {'manual': man['id'], 'kind': s.MANUAL['kind_names'][it.part],
                               'rows': unit_rows(it, labels)}

        # the reverse links: an action or a Workshop step opens the section that links it among the most others of
        # its kind (the procedure that walks through them), the first such section on a tie
        per = []
        for sec in man['sections']:
            got = {'work': [], 'workshop': []}
            walk_runs(sec['blocks'], lambda item, got=got: (
                got['work'].append(item['to']['work']) if 'work' in item['to'] else
                got['workshop'].append('%s:%s' % (item['to']['workshop'], item['to']['place']))
                if 'workshop' in item['to'] else None))
            per.append((sec['id'], got))
        for key, out in (('work', work), ('workshop', wshop)):
            best = {}
            for sid, got in per:
                for x in got[key]:
                    if x not in best or len(set(got[key])) > best[x][1]:
                        best[x] = (sid, len(set(got[key])))
            for x, (sid, _n) in best.items():
                if key == 'work':
                    for k in man['kinds']:
                        out['%s:%s' % (k, x)] = [man['id'], sid]
                else:
                    out[x] = [man['id'], sid]
        for f in man['figures']:
            figs.append({k: f[k] for k in ('file', 'kind', 'view', 'w', 'h', 'yaw', 'pitch')})
    index = {'format': 'walkdown-plant-manuals', 'version': 1,
             'manuals': [{'id': m['id'], 'number': m['number'], 'title': m['title'], 'short': m['short'],
                          'kinds': m['kinds'], 'file': m['id'] + '.json'} for m in manuals.values()],
             'kinds': kinds, 'units': units, 'work': work, 'workshop': wshop, 'figures': figs}
    return index, manuals


def dump(obj):
    return json.dumps(obj, ensure_ascii=False, sort_keys=False, separators=(',', ':')) + '\n'


def files(data=DATA):
    """{file name: text} of the whole set."""
    index, manuals = make(data)
    out = {'index.json': dump(index)}
    for mid, m in manuals.items():
        out[mid + '.json'] = dump(m)
    return out


def main(argv):
    if len(argv) != 2:
        print(__doc__)
        return 2
    try:
        fs = files()
    except ManualError as e:
        print('manuals: %s' % e, file=sys.stderr)
        return 1
    if argv[1] == '--check':
        print('manuals: %d checked' % (len(fs) - 1))
        return 0
    out = argv[1]
    os.makedirs(out, exist_ok=True)
    for n in os.listdir(out):                          # (a manual or figure no longer made goes)
        if n.endswith(('.json', '.wfig')):
            os.remove(os.path.join(out, n))
    size = 0
    for n, text in fs.items():
        with open(os.path.join(out, n), 'w', encoding='utf-8') as f:
            f.write(text)
        size += len(text.encode('utf-8'))
    idx = json.loads(fs['index.json'])
    print('manuals: %d manuals, %d figures to draw, %d codes with a manual, %d KB of JSON' % (
        len(fs) - 1, len(idx['figures']), len(idx['units']), (size + 1023) // 1024))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
