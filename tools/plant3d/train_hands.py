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
    {'id': 'spanner_24', 'title': 'Spanner, 24 mm (an M20 cable gland)', 'kind': 'spanner', 'size': '24 mm',
     'at': [[TOOLBOX, 1]]},
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
    made |= {'$_ma', '$_ma_tx', '@_tx', '@_trim', '$_ohm_v'}      # the loop's values (train_model.py)

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
        for n in a.get('set', {}):
            need(n in made and n.startswith('$_'), f'{w}: sets {n}, not a component state')
        if 'input' in a:
            need(a['input'] in made and a['input'].startswith('$_') and len(a.get('range', ())) == 2,
                 f'{w}: input {a["input"]}, a component state with its range')
        for x in a.get('sources', []):
            need(x in srcs, f'{w}: source {x}')
    for mt in s['meters']:
        for n in names(mt['value']) + mt.get('needs', []):
            need(n in made, f'meter {mt["id"]}: {n}, which nothing makes')
    for h in s['hart']:
        need(h['input'] in made and h['hart'] in made, f'HART op {h["do"]}: its input and its connection state')
        for n, _ in h.get('needs', []):
            need(n in made, f'HART op {h["do"]}: needs {n}, which nothing makes')
    loops = [e['loop'] for e in s['equipment']]
    need(len(set(loops)) == len(loops), 'a loop twice (two pieces would share its @_ names)')
    if kind == 'pressure_transmitter':      # the job's causes are the kind's (the diagnosis tab's words, HW3)
        known = {c['id'] for c in s.get('causes', [])}
        need({c['id'] for c in FAULT['causes']} <= known, f'the fault {FAULT["id"]}\'s causes not all in causes')


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
        for k in ('tools', 'wrong', 'needs', 'set', 'input', 'range', 'minutes'):
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
        m.op(code, x['do'], needs=_sub(x.get('needs', []), a, loop), where=('hart',), input=_sub(x['input'], a, loop),
             range=x['range'], hart=_sub(x['hart'], a, loop))


# The job with hidden causes (§2.6, §3.1–§3.2; milestones HW2 and HW3, REALISM.md §2.16, §2.22): transmitter 2 reads
# apart from its partners, from one of five causes, each with its true effect on this absolute transmitter on a vacuum
# condenser (the user's decision, 2026-11-10): a sensor drifted low (a sensor trim through the communicator puts it
# right); a loose signal terminal (its resistance takes the loop current down by 0.3 mA: tightening it); a blocked
# impulse line (the reading holds what was trapped in the line: venting the flange shows it, blowing the line through
# clears it); the manifold's test/vent valve passing (air leaks in: 2 kPa high; shutting it firmly); water past a worn
# cable gland in the terminal side (a leak to earth past the control system: the screen low and jumping while the
# transmitter's own current is right; drying it and a new gland seal). Drift and the loose terminal weigh 1 each as in
# HW2; the three of HW3 weigh by a value (`cpt2_w_*`, 0 unless a scenario sets it), so every earlier scenario draws
# what it drew before (the shift_tx scenario sets them to 1: five causes, equally likely).
W_NEW = ('cpt2_w_block', 'cpt2_w_pass', 'cpt2_w_wet')
FAULT = {'id': 'cond_p2_low', 'text': 'Condenser pressure transmitter 2 reads apart from its partners',
         'kks': '30MAG10CP002', 'set': {'cond_p2_low': 1}, 'repair': {'cond_p2_low': 0},
         'causes': [{'id': 'drift', 'weight': 1, 'set': {'cond_p2_drift': -1.5},
                     'repair': {'cond_p2_drift': 0, 'cond_p2_trim': 0}, 'fixed': 'cpt2_sound',
                     'text': 'The sensor has drifted 1.5 kPa low'},
                    {'id': 'loose', 'weight': 1, 'set': {'cpt2_terminal_block_loose': 1},
                     'repair': {'cpt2_terminal_block_loose': 0}, 'fixed': 'cpt2_sound',
                     'text': 'A loose signal terminal: its contact resistance takes the loop current 0.3 mA down'},
                    {'id': 'blocked', 'weight': W_NEW[0], 'set': {'cpt2_manifold_block': 1},
                     'repair': {'cpt2_manifold_block': 0}, 'fixed': 'cpt2_sound',
                     'text': 'The impulse line is blocked at the manifold: the reading holds what was trapped in it'},
                    {'id': 'passing', 'weight': W_NEW[1], 'set': {'cpt2_manifold_pass': 1},
                     'repair': {'cpt2_manifold_pass': 0}, 'fixed': 'cpt2_sound',
                     'text': "The manifold's test/vent valve is passing: air leaks in and the reading is 2 kPa high"},
                    {'id': 'wet', 'weight': W_NEW[2],
                     'set': {'cpt2_terminal_block_wet': 1, 'cpt2_cable_gland_worn': 1},
                     'repair': {'cpt2_terminal_block_wet': 0, 'cpt2_cable_gland_worn': 0}, 'fixed': 'cpt2_sound',
                     'text': "Water past the cable gland's worn seal in the terminal side: a leak to earth takes "
                             '0.6–1.0 mA, jumping, past the control system'}]}
WORK = ('wo_cond_p2_fix', '30MAG10CP002', 'Condenser pressure transmitter 2 reads apart: find the cause and put it right',
        'inst', 'general', 'iso_cond_p2', 'cond_p2_low')
CP2 = '30MAG10CP002'
# The trim a two-point check gives under the drift (REALISM.md §2.16): the drift undone (the tap offsets are real
# pressure differences, not sensor error)
TRIM = -FAULT['causes'][0]['set']['cond_p2_drift']
# kPa (0.25 % of span), mA, kPa against the partners' mean (0.5: the drift's 1.35 still shows with a partner's own
# calibration drift of -1.2 kPa, the S2 fault, applied at the same time); kPa above the partners after the vent test
# that says the line held the air (a clear line falls back to the process within the minute)
ERR_TOL, MA_TOL, PV_TOL, STUCK = 0.3, 0.15, 0.5, 5
TOL = 0.01      # a reading written down to two decimals (the screens show two) is a reading of the value
LOOP_CHECK = (4, 8, 12, 16, 20)     # mA, the loop check's points (IEC 62382; the manual's commissioning section)


def fault_values(m):
    """The values the job's cures and its technician read (REALISM.md §2.16, §2.22): whether the transmitter is left
    sound (the sensor's error within tolerance, the terminals tight and dry, the gland sealed, the line clear, the
    manifold's valve shut, the vent shut, no loop test left on), and what the technician sees at the transmitter (the
    loop current below the AO the transmitter says it sets; the PV apart from its partners' mean on the screens; the
    PV left near the air's after the vent test)."""
    for w in W_NEW:
        m.state(w, 0)
    m.sum('cond_p2_err', ['cond_p2_drift', 'cond_p2_trim'], 'kPa')
    m.cmp('cond_p2_err_lo', 'cond_p2_err', '>', -ERR_TOL)
    m.cmp('cond_p2_err_hi', 'cond_p2_err', '<', ERR_TOL)
    m.AND('cond_p2_trim_ok', ['cond_p2_err_lo', 'cond_p2_err_hi'])
    m.NOT('cpt2_tight', 'cpt2_terminal_block_loose')
    m.NOT('cpt2_cover_on', 'cpt2_cover_back_off')
    m.NOT('cpt2_dry', 'cpt2_terminal_block_wet')
    m.NOT('cpt2_sealed', 'cpt2_cable_gland_worn')
    m.NOT('cpt2_line_ok', 'cpt2_manifold_block')
    m.NOT('cpt2_valve_ok', 'cpt2_manifold_pass')
    # any cause is put right only with the transmitter left sound: no sensor error beyond the tolerance (a trim made
    # under a loose terminal is one), the terminals tight, the wires landed and the cover back on (HW2); the terminal
    # side dry with the gland sealed, the line clear, the manifold's valve and the flange's vent shut, no loop test
    # holding the output (HW3)
    m.NOT('cpt2_lt_off', 'cpt2_lt_on')
    m.AND('cpt2_sound', ['cond_p2_trim_ok', 'cpt2_tight', 'cpt2_wired', 'cpt2_cover_on', 'cpt2_dry', 'cpt2_sealed',
                         'cpt2_line_ok', 'cpt2_valve_ok', 'cpt2_shut', 'cpt2_open', 'cpt2_lt_off'])
    m.diff('cpt2_ma_short', 'cpt2_ma_tx', 'cpt2_ma', 'mA')
    m.cmp('cpt2_loop_low', 'cpt2_ma_short', '>', MA_TOL)
    m.sum('cpt2_partners', ['cond_p1', 'cond_p3'])
    m.prod('cpt2_ref', ['cpt2_partners', 0.5], 'kPa(a)')
    m.diff('cpt2_pv_dev', 'cond_p2_tx', 'cpt2_ref', 'kPa')
    m.cmp('cpt2_pv_low', 'cpt2_pv_dev', '<', -PV_TOL)
    # (HW3) the new decisions read transmitter 2 against transmitter 1 alone (its tap 0.1 kPa below): transmitter 3
    # ages (AG2) and may stand 1.5 kPa off, which would move the partners' mean past the tolerance (the adversarial
    # review's finding); the trim's decision stays HW2's
    m.diff('cpt2_dev1_r', 'cond_p2_tx', 'cond_p1', 'kPa')
    m.diff('cpt2_dev1', 'cpt2_dev1_r', 0.1, 'kPa')
    m.cmp('cpt2_pv_high', 'cpt2_dev1', '>', PV_TOL)
    m.cmp('cpt2_pv_lo1', 'cpt2_dev1', '<', -PV_TOL)
    m.OR('cpt2_pv_apart', ['cpt2_pv_lo1', 'cpt2_pv_high'])
    m.cmp('cpt2_vent_held', 'cpt2_dev1', '>', STUCK)


def job_steps():
    """The technician's own job (a task an NPC does, or a player playing the technician follows): the tools from the
    toolbox, the permit accepted at the transmitter, the cover off, the communicator and the multimeter on, both read,
    then the tests and fixes the readings call for, each `wait` skipping its block to its `else` when the reading
    doesn't call for it (REALISM.md §2.16, §2.22): water seen in the terminal side (the wires lifted, the terminal side
    dried, the gland given a new seal insert and the wires landed, the communicator's and meter's leads left on); the loop current low against the AO (the terminals tightened);
    the PV apart from the partners (the vent test: the manifold's block valve shut, the flange's vent cracked and
    shut again, the block valve opened; a PV left near the air's means a blocked line, blown through); the PV high (the manifold's test/vent valve shut firmly); the PV low (the
    sensor trim). Then the loop check with the control room (the output held at 4, 8, 12, 16 and 20 mA by the
    communicator's loop test, the screen's value read back over the radio at each), everything off, the display read
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
    steps, skips = [], []

    def skip_unless(until, label):
        steps.append({'wait': {'until': until, 'minutes': 1, 'else': label}})
        skips.append(steps[-1]['wait'])

    def label(name):
        for w in skips:
            if w['else'] == name:
                w['else'] = len(steps)
    steps += [
        {'go': TOOLBOX}, {'tool': ['sd_term', 'dmm', 'hart', 'spanner_17', 'spanner_24']},
        {'go': {'kks': CP2}}, {'permit': {'work': '$', 'action': 'accept'}},
        hand('open_cover'), hand('connect_hart', 'hart'), hand('connect_dmm', 'dmm'), {'work': 1},
        {'read': CP2, 'via': 'cpt2_pv', 'tol': TOL}, {'read': CP2, 'via': 'cpt2_ao', 'tol': TOL},
        {'read': CP2, 'via': 'cpt2_dmm', 'tol': TOL}]
    skip_unless('cpt2_terminal_block_wet', 'wet')
    steps += [hand('lift_wires', 'sd_term'), hand('dry_terms'), hand('reseal_gland', 'spanner_24'),
              hand('land_wires', 'sd_term'), {'work': 1}]
    label('wet')
    skip_unless('cpt2_loop_low', 'loose')
    steps.append(hand('tighten_terms', 'sd_term', slip={'per_mille': 30, 'set': {'cpt2_terminal_block_loose': 1},
                                                         'text': 'Left a signal terminal\'s screw short of tight'}))
    label('loose')
    skip_unless('cpt2_pv_apart', 'apart')
    steps += [hand('shut_block'), hand('crack_vent', 'spanner_17'), {'work': 1}, hand('close_vent', 'spanner_17'),
              {'work': 1}, hand('open_block'), {'work': 1}]
    skip_unless('cpt2_vent_held', 'held')
    steps += [hand('blow_line', 'spanner_17'), {'work': 1}]
    label('held')
    label('apart')
    skip_unless('cpt2_pv_high', 'high')
    steps.append(hand('shut_test'))
    label('high')
    skip_unless('cpt2_pv_lo1', 'low')
    steps.append({'op': {'kks': CP2, 'do': 'set', 'where': 'hart', 'value': TRIM}})
    label('low')
    for ma in LOOP_CHECK:
        steps += [hand('loop_test', 'hart', value=ma), {'work': 1}, {'read': CP2, 'tol': TOL}]
    steps += [hand('end_loop_test', 'hart'), {'work': 1},
              {'read': CP2, 'via': 'cpt2_dmm', 'tol': TOL}, hand('disconnect_dmm', 'dmm'), hand('disconnect_hart', 'hart'),
              {'wait': {'until': 'cpt2_clear', 'minutes': 1}}, {'read': CP2, 'tol': TOL}, hand('close_cover'),
              {'permit': {'work': '$', 'action': 'done'}},
              {'permit': {'work': '$', 'action': 'return'}}, {'say': 'cal_done', 'to': 'shift_sup'},
              {'go': TOOLBOX}, {'tool': 'off'}]
    assert all(isinstance(w['else'], int) for w in skips)
    return steps


TX_SEED = 3


def vac_scenario(base):
    """`shift_vac` (milestone HW3): the day shift of `base` (shift_cold) with the condenser being evacuated (both
    vacuum pumps on from the start, closed cooling water pump A cooling their seal water), the HW3 weights set to 1:
    the trainer's day for the transmitter's five causes (a blocked line or a passing manifold valve shows only under
    vacuum, the blocked line only while the process moves). The trainer makes the fault and may name its cause."""
    s = json.loads(json.dumps(base))
    s['id'] = 'shift_vac'
    s['title'] = 'Day shift, the condenser being evacuated (choose a role)'
    s['init'] = dict(s['init'], vac_a_cmd=1, vac_b_cmd=1, ccw_a_cmd=1, **{w: 1 for w in W_NEW})
    return s


def scenario(base):
    """`shift_tx` (milestone HW3): shift_vac (above) in which condenser pressure transmitter 2 reads apart from its
    partners from the moment the condenser passes 60 kPa(a) on its way down (so a blocked line holds a reading the
    process then leaves), its cause drawn from all five."""
    s = vac_scenario(base)
    s['id'] = 'shift_tx'
    s['title'] = 'Day shift: a condenser pressure transmitter reads apart (choose a role)'
    # its world's seed draws the blocked line (the cause that needs the process to move to show itself; a fault made
    # by its `when` takes no instructor's cause). In the other scenarios the trainer makes the fault and may name any
    # of the five; drawn there, it is drift or the loose terminal as before HW3 (shift_vac: any of the five)
    s['world'] = dict(s['world'], seed=TX_SEED)
    for f in s['faults']:
        if f['id'] == FAULT['id']:
            f['when'] = {'cmp': ['cond_p', '<', 60]}
    return s


def faults():
    return [json.loads(json.dumps(FAULT))]
