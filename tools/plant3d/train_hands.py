"""Hands-on work in the first train (docs/plant3d/REALISM.md §2.3–§2.6, §3; milestone HW2): the tools kept in the
maintenance workshop's I&C toolbox (tools.json), and, from each part kind's service file
(data/plant3d/service/<kind>.json, §2.4) joined with its Workshop data (data/plant3d/workshop/<kind>.json), the
component states, hand actions, meters and HART ops of every piece of equipment the service file names, under the
names `<alias>_<component>_<state>` (§2.4). The loop each transmitter drives (its current, what the control system
receives) is the model's own content (train_model.py); the transmitter's job with a hidden cause, its work and the
technician's task are here."""
import json, re

from service import pressure_transmitter as sv_pressure_transmitter  # noqa: E402
from workshop import pressure_transmitter as ws_pressure_transmitter  # noqa: E402

# the part kinds with a service file: (its service module, its Workshop module)
SERVICE = [(sv_pressure_transmitter, ws_pressure_transmitter)]

TOOLBOX = 'ic_toolbox'          # the I&C toolbox in the maintenance workshop (train_staff.py ANCHORS)
TOOLS = {'format': 'walkdown-plant-tools', 'version': 1, 'tools': [
    {'id': 'sd_term', 'title': 'Terminal screwdriver, 3 mm, insulated', 'kind': 'screwdriver', 'size': '3 mm',
     'at': [[TOOLBOX, 2]]},
    {'id': 'sd_flat8', 'title': 'Screwdriver, 8 mm flat blade', 'kind': 'screwdriver', 'size': '8 mm',
     'at': [[TOOLBOX, 1]]},
    {'id': 'spanner_17', 'title': 'Spanner, 17 mm', 'kind': 'spanner', 'size': '17 mm', 'at': [[TOOLBOX, 1]]},
    {'id': 'dmm', 'title': 'Multimeter', 'kind': 'meter', 'modes': ['ma_dc', 'v_dc', 'ohm'], 'at': [[TOOLBOX, 2]]},
    {'id': 'clamp', 'title': 'mA clamp meter', 'kind': 'meter', 'modes': ['ma_clamp'], 'at': [[TOOLBOX, 1]]},
    {'id': 'hart', 'title': 'HART communicator', 'kind': 'communicator', 'modes': ['hart'], 'at': [[TOOLBOX, 1]]}]}

ALIAS_MAX, STATE_MAX = 8, 6     # §2.4: 8 + 1 + 16 + 1 + 6 = 32, a value name's length
IDENT = re.compile(r'[a-z_][a-z0-9_]*\Z')


def kinds():
    """{part kind: its service file}, every kind with one."""
    return {sv.data()['part']: sv.data() for sv, _ in SERVICE}


def files():
    """{relative path: data} of the service files (data/plant3d/service/)."""
    return {f'service/{k}.json': v for k, v in kinds().items()}


def check(kind, s):
    """The service file's own rules (§2.4): its components in the kind's Workshop tree, aliases of at most 8 and states
    of at most 6 characters, every tool in tools.json, every `$` name one the file makes."""
    def need(ok, what):
        if not ok:
            raise SystemExit(f'service/{kind}.json: {what}')
    need(s.get('format') == 'walkdown-plant-service' and s.get('version') == 1, 'format walkdown-plant-service, 1')
    need(s.get('part') == kind, f'part {kind}')
    ws = next(w.data() for sv, w in SERVICE if sv.data()['part'] == kind)
    comps = set(ws['components']) | set(ws.get('fasteners', {}))
    tools = {t['id'] for t in TOOLS['tools']}
    srcs = {x['id'] for x in s['sources']}
    aliases = [e['alias'] for e in s['equipment']]
    need(len(set(aliases)) == len(aliases), 'an alias twice')
    for a in aliases:
        need(IDENT.match(a) and len(a) <= ALIAS_MAX, f'alias {a!r}: an identifier of at most {ALIAS_MAX} characters')
    made = {'hand_no'} | {c for c, _ in s.get('consts', [])}
    for comp, st, words in s['states']:
        need(comp in comps, f'state of {comp}: not a component of the Workshop\'s tree')
        need(IDENT.match(st) and len(st) <= STATE_MAX, f'state {st!r}: an identifier of at most {STATE_MAX} characters')
        need(0 < len(words) <= 200, f'state {comp}_{st}: its words')
        made.add(f'$_{comp}_{st}')
    for name, _ in s['values']:
        made.add(name)
    made |= {'$_ma', '$_ma_tx', '@_tx', '@_trim'}       # the loop's values (train_model.py)

    def names(x):
        return [n for n in (x if isinstance(x, list) else [x]) if isinstance(n, str)]
    for a in s['actions']:
        w = f'action {a["action"]}'
        need(a['component'] in comps, f'{w}: component {a["component"]} not in the Workshop\'s tree')
        need(0 < len(a['title']) <= 80, f'{w}: title')
        for t in a.get('tools', []) + list(a.get('wrong', {})):
            need(t in tools, f'{w}: tool {t} not in tools.json')
        for n, _ in a.get('needs', []):
            need(n in made, f'{w}: needs {n}, which nothing makes')
        for n in a['set']:
            need(n in made and n.startswith('$_'), f'{w}: sets {n}, not a component state')
        for x in a.get('sources', []):
            need(x in srcs, f'{w}: source {x}')
    for mt in s['meters']:
        for n in names(mt['value']) + mt.get('needs', []):
            need(n in made, f'meter {mt["id"]}: {n}, which nothing makes')
    for h in s['hart']:
        need(h['input'] in made and h['hart'] in made, f'HART op {h["do"]}: its input and its connection state')


def _sub(x, alias, loop):
    if isinstance(x, str):
        return x.replace('$_', alias + '_').replace('@_', loop + '_')
    if isinstance(x, list):
        return [_sub(v, alias, loop) for v in x]
    if isinstance(x, dict):
        return {_sub(k, alias, loop): _sub(v, alias, loop) for k, v in x.items()}
    return x


def equipment():
    """[(kind, service file, its equipment entry)] in file order."""
    out = []
    for kind, s in kinds().items():
        check(kind, s)
        out += [(kind, s, e) for e in s['equipment']]
    return out


def of(code):
    """(kind, service file, equipment entry) of a code, or None."""
    return next((x for x in equipment() if x[2]['kks'] == code), None)


def values(m, code):
    """The component states (all 0: home, on, landed) and the values the hand actions' needs read, for one piece of
    equipment; the consts once per model."""
    kind, s, e = of(code)
    a, loop = e['alias'], e['loop']
    for c, v in s.get('consts', []):
        if not any(n == c for n, _ in m.values):
            m.const(c, v)
    for comp, st, _ in s['states']:
        m.state(f'{a}_{comp}_{st}', 0)
    for name, node in s['values']:
        m.v(_sub(name, a, loop), _sub(node, a, loop))


def parts(m, code):
    """The hand actions, meters and HART ops of one piece of equipment into the model."""
    kind, s, e = of(code)
    a, loop = e['alias'], e['loop']
    for x in s['actions']:
        h = {'kks': code, 'action': x['action'], 'component': x['component']}
        for k in ('tools', 'wrong', 'needs', 'set', 'minutes'):
            if k in x:
                h[k] = _sub(x[k], a, loop)
        m.hands.append(h)
    for x in s['meters']:
        mt = {'id': _sub(x['id'], a, loop), 'kks': code}
        for k in ('point', 'tool_kind', 'mode', 'value', 'needs', 'else'):
            if k in x:
                mt[k] = _sub(x[k], a, loop)
        m.meters.append(mt)
    for x in s['hart']:
        m.op(code, x['do'], where=('hart',), input=_sub(x['input'], a, loop), range=x['range'],
             hart=_sub(x['hart'], a, loop))


# The job with a hidden cause (§2.6, §3.1–§3.2): transmitter 2 reads low against its partners, from a sensor that has
# drifted (a sensor trim through the communicator puts it right) or a loose signal terminal (its resistance takes the
# loop current down by 0.3 mA: tightening it puts it right). The two are told apart at the transmitter: the HART PV
# against the partners on the screens, and the loop current the multimeter or the clamp reads against the one the
# transmitter says it sets. HW3 adds the other three causes and the debrief's diagnosis tab.
FAULT = {'id': 'cond_p2_low', 'text': 'Condenser pressure transmitter 2 reads low against its partners',
         'kks': '30MAG10CP002', 'set': {'cond_p2_low': 1}, 'repair': {'cond_p2_low': 0},
         'causes': [{'id': 'drift', 'weight': 1, 'set': {'cond_p2_drift': -1.5},
                     'repair': {'cond_p2_drift': 0, 'cond_p2_trim': 0},
                     'text': 'The sensor has drifted 1.5 kPa low'},
                    {'id': 'loose', 'weight': 1, 'set': {'cpt2_terminal_block_loose': 1},
                     'repair': {'cpt2_terminal_block_loose': 0},
                     'text': 'A loose signal terminal: its contact resistance takes the loop current 0.3 mA down'}]}
WORK = ('wo_cond_p2_fix', '30MAG10CP002', 'Condenser pressure transmitter 2 reads low: find the cause and put it right',
        'inst', 'general', 'iso_cond_p2', 'cond_p2_low')
CP2 = '30MAG10CP002'


def job_steps():
    """The technician's own job (a task an NPC does, or a player playing the technician follows): the tools from the
    toolbox, the permit accepted at the transmitter, the cover off, the communicator and the multimeter on, both read,
    the terminals tightened and the trim set to no offset (the NPC's check of it), everything off, the display read
    and the cover on, the permit done and handed back, the tools put back.
    A need reads the values as the step before left them and a meter shows them so (REALISM.md §2.13), and a node
    made from a state follows that state's write a step later: so a minute's work (the readings settling) stands
    between the connections and their readings, and the cover waits until the terminals are clear."""
    def hand(action, tool=None, **kw):
        s = {'hand': action, 'kks': CP2}
        if tool:
            s['tool'] = tool
        s.update(kw)
        return s
    return [
        {'go': TOOLBOX}, {'tool': ['sd_term', 'dmm', 'hart']},
        {'go': {'kks': CP2}}, {'permit': {'work': '$', 'action': 'accept'}},
        hand('open_cover'), hand('connect_hart', 'hart'), hand('connect_dmm', 'dmm'), {'work': 1},
        {'read': CP2, 'via': 'cpt2_pv'}, {'read': CP2, 'via': 'cpt2_ao'}, {'read': CP2, 'via': 'cpt2_dmm'},
        hand('tighten_terms', 'sd_term', slip={'per_mille': 30, 'set': {'cpt2_terminal_block_loose': 1},
                                                'text': 'Left a signal terminal\'s screw short of tight'}),
        {'op': {'kks': CP2, 'do': 'set', 'where': 'hart', 'value': 0}}, {'work': 1},
        {'read': CP2, 'via': 'cpt2_dmm'}, hand('disconnect_dmm', 'dmm'), hand('disconnect_hart', 'hart'),
        {'wait': {'until': 'cpt2_clear', 'minutes': 1}}, {'read': CP2}, hand('close_cover'), {'permit': {'work': '$', 'action': 'done'}},
        {'permit': {'work': '$', 'action': 'return'}}, {'say': 'cal_done', 'to': 'shift_sup'},
        {'go': TOOLBOX}, {'tool': 'off'}]


def faults():
    return [json.loads(json.dumps(FAULT))]
