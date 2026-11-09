"""The first train's discussions (data/plant3d/discussions.json, format walkdown-plant-discussion version 1;
docs/plant3d/REALISM.md §6.3, §6.3.1, milestone DC3): five short meetings where two people differ on a job's method,
order or isolation, put their evidence, and agree; the agreed outcome is the job the permit and the work order then
carry. Also what they need: the findings that start them (trainer's faults in every first-train scenario, a state
each), the outcome works and their isolations, the lead's, joiners' and outcome tasks, the reactions and messages.

Every line is our own, written as engineers talk on a site; the evidence follows the public sources of REALISM.md
§14 ([ISO20816-3], [Moubray], [R3051], [FCVH], [HSG250], [DOE-RCA], [ISA182], [MOC]) and the DC2 manuals' sections
(tools/plant3d/manual_texts). Nothing here is any real plant's.

Each discussion has three roles: the two who differ (the lead first: their task carries the `discuss` step) and the
role a trainee usually plays there (an engineer, a technician or the control room operator), so a trainee playing it
takes part. Between NPCs every point takes its default, so the NPCs' outcome is the same every time; the trainee's
picks and the readings when it ends can change it. Valve packing (cw_a_pack): the site's rule wins, every outcome
isolates."""

FORMAT = 'walkdown-plant-discussion'
TOOLBOX = 'ic_toolbox'
CP2 = '30MAG10CP002'

# ------------------------------------------------------------------------------------------------ the findings
# (fault id, model area, the states it sets, the code it is offered at, its text): a trainer's fault each (no `when`:
# nothing happens until the instructor, or a test, applies it), offered in every first-train scenario. The finding's
# own state has no code, so the outcome works may clear it on their done (a work's `set` writes no state of a code of
# its own isolation, PLANT3D §15.2).
FINDINGS = [
    ('cw_a_zone_c', 'cw', {'cw_a_zone_c': 1}, '30PAC10AP001',
     'CW pump A: the monthly vibration route reads 5.6 mm/s at the motor\'s drive-end bearing (zone C), up from 2.9'),
    ('cond_p2_again', 'st', {'cond_p2_drift': 1.2, 'cond_p2_seen': 1}, CP2,
     'Condenser pressure transmitter 2 reads 1.2 kPa above its partners again, a month after it was trimmed'),
    ('cw_a_gland', 'cw', {'cw_a_gland': 1}, '30PAC10AA101',
     'CW pump A discharge valve: water weeping from the stem\'s gland onto the motor base'),
    ('st_vib3_trip', 'st', {'st_trip_rep': 1}, '30MAD10CY003',
     'The night shift\'s report: the steam turbine tripped on bearing 3 vibration high-high; the restart is the '
     'day shift\'s decision'),
    ('ct_fan7_chatter', 'ct', {'ct_fan7_chat': 1}, '30PAD10AN007',
     'Cooling tower fan 7\'s vibration alarm came in and cleared fourteen times last shift'),
]
STATES = {'cw': ['cw_a_zone_c', 'cw_a_gland'], 'st': ['cond_p2_seen', 'st_trip_rep'], 'ct': ['ct_fan7_chat']}


def faults():
    """The findings as scenario faults (appended to the first train's list: no earlier fault's place moves)."""
    out = []
    for fid, _, sets, kks, text in FINDINGS:
        rep = {k: 0 for k in sets}
        if 'cond_p2_drift' in sets:
            rep['cond_p2_trim'] = 0     # (the trainer's repair puts the sensor and any trim back, as HW2's does)
        out.append({'id': fid, 'set': dict(sets), 'text': text, 'kks': kks, 'repair': rep})
    return out


# ------------------------------------------------------------------------------------------------ the works
# The outcome works: (area, id, code, title, discipline, isolation or None, its `set` on done). A work that runs on
# live plant (readings and grease on a running pump, a portable probe, a limit in the control system) has no
# isolation and repairs nothing; every repair or renewal isolates (PLANT3D §15.2).
ISOLATIONS = [
    ('st', 'iso_cond_p2_rm', 'Condenser pressure transmitter 2, removed to the bench',
     [(CP2, 'instrument', None, 'Root valve shut and tagged, the transmitter vented, its loop fuse pulled and tagged '
                                'at the marshalling cabinet')]),
    ('st', 'iso_st_vib3', 'Steam turbine bearing 3 vibration channel',
     [('30MAD10CY003', 'instrument', None, 'Bearing 3 channel inhibited in the protection, signed by the shift '
                                           'supervisor; the probe\'s cable parked and tagged at its junction box')]),
]
TRIM = -1.2         # the in-place or bench sensor trim that undoes cond_p2_again's drift
WORKS = [
    ('cw', 'wo_cw_a_watch', '30PAC10AP001', 'CW pump A: a vibration reading every shift and the bearings regreased, '
     'running', 'mech', None, {'cw_a_zone_c': 0}),
    ('st', 'wo_cond_p2_insitu', CP2, 'Condenser pressure transmitter 2: two-point trim in place, hand pump and '
     'reference gauge', 'inst', 'iso_cond_p2', {'cond_p2_trim': TRIM, 'cond_p2_seen': 0}),
    ('st', 'wo_cond_p2_bench', CP2, 'Condenser pressure transmitter 2: removed and checked at the I&C bench', 'inst', 'iso_cond_p2_rm', {'cond_p2_trim': TRIM, 'cond_p2_seen': 0}),
    ('cw', 'wo_cw_a_pack', '30PAC10AA101', 'CW pump A discharge valve: isolate now and repack the stem with new '
     'rings', 'mech', 'iso_cw_a', {'cw_a_gland': 0}),
    ('cw', 'wo_cw_a_pack_ll', '30PAC10AA101', 'CW pump A discharge valve: drip tray first, then isolate and fit '
     'live-loaded packing', 'mech', 'iso_cw_a', {'cw_a_gland': 0}),
    ('st', 'wo_st_vib3_rca', '30MAD10CY003', 'Steam turbine bearing 3 trip: probe gap and wiring checked before any '
     'restart', 'inst', 'iso_st_vib3', {'st_trip_rep': 0}),
    ('st', 'wo_st_vib3_watch', '30MAD10CY003', 'Steam turbine bearing 3: a portable probe beside the fixed one to '
     'watch the restart', 'mech', None, {'st_trip_rep': 0}),
    ('ct', 'wo_ct_fan7_alm', '30PAD10AN007', 'Cooling tower fan 7 vibration alarm: limit raised to 7.1 mm/s for seven '
     'days', 'inst', None, {'ct_fan7_chat': 0}),
]
# the works already there that an outcome uses, and the finding their done clears too
EXISTING = {'wo_cw_a_brg': {'cw_a_zone_c': 0}, 'wo_ct_fan7_cy': {'ct_fan7_chat': 0}}
WORK_IDS = [w[1] for w in WORKS]
# each new work's job kind (train_hse.job_of) and work order keys (train_workorders.OWN): (finds, codes, crew hours)
JSA = {'wo_cw_a_watch': 'running_checks', 'wo_cw_a_pack': 'valve_packing', 'wo_cw_a_pack_ll': 'valve_packing',
       'wo_st_vib3_rca': 'probe_check', 'wo_st_vib3_watch': 'running_checks', 'wo_ct_fan7_alm': 'alarm_change'}
HSE_JOBS = [
    ('running_checks', 'Readings and grease on a running machine', ['rotating', 'hot_surface', 'noise', 'slips']),
    ('valve_packing', 'A valve\'s stem packing renewed', ['stored_pressure', 'valve_stroke', 'manual', 'pinch',
                                                          'slips']),
    ('probe_check', 'A turbine vibration probe\'s gap and wiring checked', ['process_trip', 'elec_shock',
                                                                            'hot_surface', 'noise']),
    ('alarm_change', 'An alarm limit changed in the control system', ['process_trip']),
]
WO_KEYS = {
    'wo_cw_a_watch': (['vibration'], ['vibration', 'wear', 'inspection'], 1),
    'wo_cond_p2_insitu': (['reading'], ['reading', 'out_of_adjust', 'adjust'], 2),
    'wo_cond_p2_bench': (['reading'], ['reading', 'out_of_adjust', 'adjust'], 4),
    'wo_cw_a_pack': (['leak'], ['leak', 'wear', 'repair'], 3),
    'wo_cw_a_pack_ll': (['leak'], ['leak', 'wear', 'modify'], 5),
    'wo_st_vib3_rca': (['reading', 'vibration'], ['vibration', 'unknown', 'check'], 4),
    'wo_st_vib3_watch': (['vibration'], ['vibration', 'unknown', 'inspection'], 2),
    'wo_ct_fan7_alm': (['erratic'], ['erratic', 'faulty_signal', 'modify'], 1),
}


def model(m):
    """The findings' states, the isolations and the outcome works of this model's area, each after everything the
    area had (no earlier value, isolation or work moves)."""
    for s in STATES.get(m.area, []):
        m.state(s, 0)
    for area, iid, text, pts in ISOLATIONS:
        if area == m.area:
            m.isolation(iid, text, pts)
    for area, wid, kks, title, disc, iso, sets in WORKS:
        if area == m.area:
            m.work(wid, kks, title, disc, 'general', iso)
            m.works[-1]['set'] = dict(sets)
    for w in m.works:
        if w['id'] in EXISTING:
            w['set'] = dict(w.get('set', {}), **EXISTING[w['id']])


# ------------------------------------------------------------------------------------------------ the jobs
def _job(code, *body, tools=None):
    """A job's steps: (tools from the toolbox,) to the place, the permit accepted, the work, done and handed back."""
    pre = [{'go': TOOLBOX}, {'tool': tools}] if tools else []
    post = [{'go': TOOLBOX}, {'tool': 'off'}] if tools else []
    return pre + [{'go': {'kks': code}}, {'permit': {'work': '$', 'action': 'accept'}}] + list(body) + [
        {'permit': {'work': '$', 'action': 'done'}}, {'permit': {'work': '$', 'action': 'return'}},
        {'say': 'job_done', 'to': 'shift_sup'}] + post


def job_steps(wid):
    """The job steps of an outcome work (before train_staff's toolbox talk is put first), or None."""
    return {
        'wo_cw_a_watch': _job('30PAC10AP001', {'read': '30PAC10CY001', 'expect': [0, 7.1], 'tol': 0.1},
                              {'work': [10, 15], 'anim': 'inspect', 'tool': 'vib_dc'},
                              {'work': [10, 20], 'anim': 'wrench', 'tool': 'grease_gun'}),
        'wo_cond_p2_insitu': _job(CP2, {'work': [30, 45], 'anim': 'calibrate', 'tool': 'hand_pump'},
                                  tools=['hart', 'dmm']),
        'wo_cond_p2_bench': _job(CP2, {'work': [10, 15], 'anim': 'wrench', 'tool': 'spanner'},
                                 {'go': 'ws_cal'}, {'work': [45, 60], 'anim': 'calibrate', 'tool': 'deadweight'},
                                 {'go': {'kks': CP2}}, {'work': [15, 20], 'anim': 'wrench', 'tool': 'spanner'}),
        'wo_cw_a_pack': _job('30PAC10AA101', {'work': [40, 60], 'anim': 'wrench', 'tool': 'packing_hook'}),
        'wo_cw_a_pack_ll': _job('30PAC10AA101', {'work': [60, 90], 'anim': 'wrench', 'tool': 'torque_wrench'}),
        'wo_st_vib3_rca': _job('30MAD10CY003', {'work': [20, 30], 'anim': 'calibrate', 'tool': 'dmm'},
                               {'work': [10, 20], 'anim': 'inspect'}, tools=['dmm']),
        'wo_st_vib3_watch': _job('30MAD10CY003', {'work': [20, 40], 'anim': 'inspect', 'tool': 'vib_dc'}),
        'wo_ct_fan7_alm': [{'go': {'kind': 'desk', 'room': 'offices'}, 'else': 1},
                           {'permit': {'work': '$', 'action': 'accept'}}, {'work': [10, 15], 'anim': 'type'},
                           {'permit': {'work': '$', 'action': 'done'}}, {'permit': {'work': '$', 'action': 'return'}},
                           {'say': 'job_done', 'to': 'shift_sup'}],
    }.get(wid)


# ------------------------------------------------------------------------------------------------ the discussions
def _ev(eid, kind, text, **kw):
    return dict({'id': eid, 'kind': kind, 'text': text}, **kw)


def _l(role, text):
    return {'role': role, 'text': text}


def _opt(oid, text, lines, side=None, evidence=None):
    o = {'id': oid, 'text': text}
    if side:
        o['side'] = side
    if evidence:
        o['evidence'] = evidence
    o['lines'] = lines
    return o


DISCUSSIONS = [
    {'id': 'cw_a_vib', 'title': 'CW pump A\'s bearing in zone C: run it to the planned stop or stop it now',
     'topic': 'wo_cw_a_brg', 'room': 'meeting', 'roles': ['maint_sup', 'maint_mgr', 'mech_eng'],
     'evidence': [
         _ev('zone', 'standard', 'Zone C: not fit for long-term running. The machine may run for a limited time '
             'until there is a suitable chance to put it right.', cite='ISO20816-3'),
         _ev('pf', 'standard', 'Once a failure can be seen coming, the time left is the P-F interval: check more '
             'often than that, and act before it ends.', cite='Moubray'),
         _ev('man', 'manual', 'Pump manual, troubleshooting: vibration rising from worn bearings: read the spectrum, '
             'check the alignment and the feet, replace the bearings.', manual='pumps', section='troubleshooting'),
         _ev('temp', 'reading', 'Motor bearing temperature above 90 °C. The heat comes last, near the end of the '
             'bearing\'s life.', code='30PAC10AP001', value='cw_a_brg_t_h'),
         _ev('vib_d', 'reading', 'Vibration past 7.1 mm/s, the zone C/D boundary: damage from here on.',
             code='30PAC10CY001', value='cw_a_vib_h'),
         _ev('standby', 'rule', 'Site rule: a CW pump comes out for work only once the standby pump is running and '
             'proven.')],
     'positions': [
         {'role': 'maint_sup', 'claim': 'Stop it now and put C on duty. Zone C is borrowed time, and the bearing '
          'only gets worse.', 'evidence': ['zone', 'temp']},
         {'role': 'maint_mgr', 'claim': 'Run it to Saturday\'s stop with a reading every shift. The crew and the '
          'crane are booked for then.', 'evidence': ['pf', 'man']},
         {'role': 'mech_eng', 'claim': 'Let the readings decide: if it is still climbing or the heat has started, '
          'it comes out now.', 'evidence': ['vib_d', 'temp']}],
     'turns': [_l('maint_sup', 'A\'s motor bearing is in zone C, 5.6 at the drive end. I want it out today.'),
               _l('maint_mgr', 'Saturday is four days off and the job is planned for it. Will it get there?'),
               _l('mech_eng', 'Depends on the trend. Last month it read 2.9.')],
     'points': [
         {'id': 'trend', 'role': 'mech_eng', 'minutes': 10, 'default': 'read', 'options': [
             _opt('stop', 'Back stopping it now: the temperature is up as well',
                  [_l('$', 'The bearing temperature is up too. That\'s the end of the curve, not the start.'),
                   _l('maint_mgr', 'If the heat is in it, I won\'t argue.')], 'maint_sup', ['temp']),
             _opt('run', 'Back running it on: zone C allows a limited time, with a reading every shift',
                  [_l('$', 'Zone C gives us a limited time. With a reading every shift we\'ll see it coming.'),
                   _l('maint_sup', 'Every shift, and it stops the day it passes 7.1.')], 'maint_mgr', ['zone', 'pf']),
             _opt('read', 'Ask for a fresh spectrum and the readings before deciding',
                  [_l('$', 'Before we decide, let me look at the spectrum and the bearing temperature now.'),
                   _l('maint_mgr', 'Fine, but we decide today.')], evidence=['man'])]}],
     'minutes': 20,
     'agreements': [
         {'when': [{'value': 'cw_a_vib_h', 'is': True}],
          'outcome': {'task': 'dsc_cw_a_stop', 'text': 'Stop CW pump A now on the standby pump; its motor bearings '
                      'changed under permit today'},
          'lines': [_l('maint_mgr', 'Past 7.1, it\'s not a discussion. Stop it.')]},
         {'when': [{'value': 'cw_a_brg_t_h', 'is': True}],
          'outcome': {'task': 'dsc_cw_a_stop', 'text': 'Stop CW pump A now on the standby pump; its motor bearings '
                      'changed under permit today'},
          'lines': [_l('maint_mgr', 'Heat as well. Take it out.')]},
         {'when': [{'point': 'trend', 'option': 'stop'}],
          'outcome': {'task': 'dsc_cw_a_stop', 'text': 'Stop CW pump A now on the standby pump; its motor bearings '
                      'changed under permit today'},
          'lines': [_l('maint_mgr', 'All right. Out today, C on duty.')]},
         {'when': [],
          'outcome': {'task': 'dsc_cw_a_run', 'text': 'Run CW pump A to Saturday\'s stop: a reading every shift and '
                      'the bearings regreased running; the bearing change stays planned for the stop'},
          'lines': [_l('maint_sup', 'Every shift, then, and it stops the day it passes 7.1.')]}]},

    {'id': 'cond_p2_cal', 'title': 'Condenser pressure transmitter 2: calibrate it in place or at the bench',
     'topic': 'wo_cond_p2_cal', 'room': 'control_room', 'roles': ['ic_eng', 'shift_sup', 'ic_tech'],
     'evidence': [
         _ev('r3051', 'standard', 'A two-point sensor trim against a reference at least three times as accurate, '
             'checked at five points rising and falling.', cite='R3051'),
         _ev('man_cal', 'manual', 'Transmitter manual, calibration: an absolute transmitter\'s zero needs a vacuum '
             'reference; one that keeps needing a large trim is drifting: replace its sensor module.',
             manual='pressure_transmitter', section='calibration'),
         _ev('man_rep', 'manual', 'Transmitter manual: the sensor module and the electronics are changed at the '
             'workshop bench, the transmitter removed.', manual='pressure_transmitter', section='replacing'),
         _ev('trim', 'reading', 'Transmitter 2 within 0.3 kPa of the true pressure.', code=CP2,
             value='cond_p2_trim_ok'),
         _ev('oos', 'rule', 'Site rule: a trip transmitter is out of service for one shift at most, with the '
             'control room told and the trip vote watched.')],
     'positions': [
         {'role': 'ic_eng', 'claim': 'Take it to the bench. It needed a big trim last month too: that\'s drift, and '
          'the bench has a proper reference.', 'evidence': ['man_cal', 'man_rep']},
         {'role': 'shift_sup', 'claim': 'Do it in place. It\'s one of three on the vacuum trip: the shorter it\'s '
          'out, the better.', 'evidence': ['oos', 'r3051']},
         {'role': 'ic_tech', 'claim': 'Either works. In place is an hour with the hand pump; the bench is half a '
          'shift with the removal.', 'evidence': ['r3051']}],
     'turns': [_l('ic_eng', 'Transmitter 2 reads 1.2 kPa above the other two again, a month after its trim.'),
               _l('shift_sup', 'It\'s one of the trip transmitters. Whatever you do, keep it short.'),
               _l('ic_tech', 'I can trim it in place this morning, or take it to the bench.')],
     'points': [
         {'id': 'method', 'role': 'ic_tech', 'minutes': 10, 'default': 'bench', 'options': [
             _opt('bench', 'Back the bench: drift that comes back is the sensor, not the trim',
                  [_l('$', 'Trimming it again just hides the drift. On the bench we\'ll see if the sensor\'s going.'),
                   _l('shift_sup', 'Then it\'s back before the shift ends.')], 'ic_eng', ['man_cal']),
             _opt('place', 'Back calibrating in place: a two-point trim with the hand pump',
                  [_l('$', 'A two-point trim with the hand pump and the reference gauge will do, and it\'s back in '
                      'an hour.'),
                   _l('ic_eng', 'Then log the as-found. If it drifts again, it goes to the bench.')], 'shift_sup',
                  ['oos', 'r3051']),
             _opt('check', 'Check it in place first; the bench only if it is out of tolerance',
                  [_l('$', 'Let me check it in place first. If it\'s outside a quarter of a percent of span, it goes '
                      'to the bench.'),
                   _l('ic_eng', 'Fair. As-found on paper first.')], evidence=['trim'])]}],
     'minutes': 15,
     'agreements': [
         {'when': [{'point': 'method', 'option': 'place'}],
          'outcome': {'task': 'dsc_cp2_place', 'text': 'Calibrate transmitter 2 in place: a two-point trim with '
                      'the hand pump, as-found and as-left recorded'},
          'lines': [_l('ic_eng', 'In place, then. Record the as-found.')]},
         {'when': [{'point': 'method', 'option': 'check'}, {'value': 'cond_p2_trim_ok', 'is': True}],
          'outcome': {'task': 'dsc_cp2_place', 'text': 'Calibrate transmitter 2 in place: a two-point trim with '
                      'the hand pump, as-found and as-left recorded'},
          'lines': [_l('ic_eng', 'Within tolerance: in place is enough.')]},
         {'when': [],
          'outcome': {'task': 'dsc_cp2_bench', 'text': 'Take transmitter 2 to the I&C bench: removed, checked '
                      'against the dead-weight tester, refitted the same shift'},
          'lines': [_l('shift_sup', 'Bench it, but I want it back before the shift ends.')]}]},

    {'id': 'cw_a_pack', 'title': 'CW pump A discharge valve leaks at its gland: tighten it live or isolate and '
     'repack', 'topic': 'wo_cw_a_pack', 'room': 'workshop', 'roles': ['maint_sup', 'shift_sup', 'mech_tech'],
     'evidence': [
         _ev('fcvh', 'standard', 'The packing seals the stem against the line\'s pressure; it is renewed with the '
             'pressure off, unless the maker allows otherwise.', cite='FCVH'),
         _ev('man_m', 'manual', 'Valve manual: repacking under pressure only on a gate or globe valve with a '
             'backseat, never on trip duty. Otherwise isolate and depressurise first.', manual='valves',
             section='maintenance'),
         _ev('man_t', 'manual', 'Valve manual, troubleshooting: a leak at the stem is worn or loose packing: '
             'tighten the gland nuts evenly, or repack.', manual='valves', section='troubleshooting'),
         _ev('run', 'reading', 'CW pump A running: the gland is under the pump\'s pressure.', code='30PAC10AP001',
             value='cw_a_run'),
         _ev('ptw', 'standard', 'The permit names the isolations; the work starts only once they are in place.',
             cite='HSG250'),
         _ev('rule', 'rule', 'Site rule: no work on a pressure boundary, glands included, until it is isolated and '
             'proven at zero.')],
     'positions': [
         {'role': 'maint_sup', 'claim': 'It\'s a weep at two and a half bar of water. A flat on each gland nut and '
          'it\'s done in ten minutes.', 'evidence': ['man_t']},
         {'role': 'shift_sup', 'claim': 'It\'s a pressure boundary. Isolate it and repack it properly.',
          'evidence': ['rule', 'ptw', 'run']},
         {'role': 'mech_tech', 'claim': 'It\'s a butterfly, no backseat. If the gland is near the end of its '
          'travel, nipping it up won\'t hold.', 'evidence': ['man_m', 'fcvh']}],
     'turns': [_l('maint_sup', 'A\'s discharge valve is weeping at the gland. Not much, a few drops a minute.'),
               _l('shift_sup', 'Where is it going?'),
               _l('mech_tech', 'Onto the floor by the motor base for now.')],
     'points': [
         {'id': 'how', 'role': 'mech_tech', 'minutes': 10, 'default': 'isolate', 'options': [
             _opt('isolate', 'Back isolating it: a butterfly has no backseat',
                  [_l('$', 'No backseat on a butterfly. Isolate it and repack it.'),
                   _l('maint_sup', 'Fine. A out, C on.')], 'shift_sup', ['rule', 'man_m']),
             _opt('live', 'Back nipping the gland up live',
                  [_l('$', 'The gland nuts have travel left. A flat each would stop it.'),
                   _l('shift_sup', 'Not live. That\'s the site rule, however small the job looks.')], 'maint_sup',
                  ['man_t']),
             _opt('sealant', 'Propose a sealant injection, done live by a specialist',
                  [_l('$', 'Could a specialist inject sealant into the gland while it runs?'),
                   _l('shift_sup', 'Same rule. Nobody works on that gland under pressure.')], evidence=['fcvh'])]},
         {'id': 'when', 'role': 'maint_sup', 'minutes': 10, 'default': 'today', 'options': [
             _opt('today', 'Repack it today with new rings',
                  [_l('$', 'New rings today. It\'s an hour\'s job once it\'s isolated.')], 'shift_sup'),
             _opt('later', 'A drip tray now, then isolate it and fit live-loaded packing',
                  [_l('$', 'A tray under it now. Then we isolate it and fit live-loaded packing, so it won\'t need '
                      'nipping up again.')], 'maint_sup', ['fcvh'])]}],
     'minutes': 15,
     'agreements': [
         {'when': [{'point': 'when', 'option': 'later'}],
          'outcome': {'task': 'dsc_cwpk_later', 'text': 'A drip tray and the leak checked each round first; then '
                      'isolated and live-loaded packing fitted (spring washers on the gland studs)'},
          'lines': [_l('shift_sup', 'Tray now, isolate it for the live-loading. Nobody touches it live meanwhile.')]},
         {'when': [],
          'outcome': {'task': 'dsc_cwpk_now', 'text': 'Isolate CW pump A and its discharge valve now and repack the '
                      'stem with new rings'},
          'lines': [_l('shift_sup', 'Isolated, then repacked. Raise the permit.')]}]},

    {'id': 'st_trip', 'title': 'The steam turbine tripped on bearing 3 vibration: restart it or find the cause '
     'first', 'topic': 'wo_st_vib3_rca', 'room': 'control_room', 'roles': ['shift_sup', 'mech_eng', 'ccr_op'],
     'evidence': [
         _ev('rca', 'standard', 'Find the root cause before the event can repeat; gather the data while it is fresh, '
             'before anything is reset or restarted.', cite='DOE-RCA'),
         _ev('man_ts', 'manual', 'Turbine manual, troubleshooting: vibration that jumps suddenly can be a lost blade '
             'piece or a rub: do not restart before the cause is found.', manual='steam_turbine',
             section='troubleshooting'),
         _ev('man_op', 'manual', 'Turbine manual: after a trip the rotor coasts down and goes on turning gear.',
             manual='steam_turbine', section='operation'),
         _ev('v3', 'reading', 'Bearing 3 still above its alarm level.', code='30MAD10CY003', value='st_vib3_h'),
         _ev('clear', 'reading', 'No turbine trip still latched.', code='30MAD10CY001', value='st_trips_clear'),
         _ev('log', 'rule', 'Site rule: after a protection trip the restart waits until its cause is written in '
             'the shift log.')],
     'positions': [
         {'role': 'shift_sup', 'claim': 'Probe 3 spiked and the others stayed flat. It looks like the probe: '
          'restart and watch it.', 'evidence': ['man_op', 'clear']},
         {'role': 'mech_eng', 'claim': 'Not before we know. Pull the trends for all eight bearings and check probe '
          '3\'s gap first.', 'evidence': ['rca', 'man_ts', 'log']},
         {'role': 'ccr_op', 'claim': 'Dispatch wants a time back. The trends are on the screen if you want them.',
          'evidence': ['clear']}],
     'turns': [_l('shift_sup', 'The ST tripped on bearing 3 vibration high-high. GT and HRSG are holding on the '
                  'bypass.'),
               _l('mech_eng', 'Was it just probe 3, or did bearings 2 and 4 see it too?'),
               _l('ccr_op', 'Dispatch is asking for a time back.')],
     'points': [
         {'id': 'cause', 'role': 'ccr_op', 'minutes': 10, 'default': 'find', 'options': [
             _opt('restart', 'Back a restart: only one probe moved',
                  [_l('$', 'Only probe 3 moved. 2 and 4 stayed flat. It looks like the probe.'),
                   _l('mech_eng', 'Looks like isn\'t the same as is.')], 'shift_sup', ['clear']),
             _opt('find', 'Back finding the cause first',
                  [_l('$', 'If it is the bearing, a restart wrecks it. Check the probe first.'),
                   _l('shift_sup', 'All right, but quickly.')], 'mech_eng', ['rca', 'man_ts']),
             _opt('trend', 'Ask for the trends of all eight bearings before deciding',
                  [_l('$', 'I\'ll put all eight bearings\' trends up, the last hour before the trip.')],
                  evidence=['v3'])]}],
     'minutes': 20,
     'agreements': [
         {'when': [{'value': 'st_vib3_h', 'is': True}],
          'outcome': {'task': 'dsc_st_find', 'text': 'No restart: probe 3\'s gap and wiring checked and the trends '
                      'compared first, the cause written in the log'},
          'lines': [_l('shift_sup', 'Still high on turning gear. Nobody restarts it.')]},
         {'when': [{'point': 'cause', 'option': 'restart'}, {'value': 'st_trips_clear', 'is': True}],
          'outcome': {'task': 'dsc_st_restart', 'text': 'Reset the trip and restart, a portable probe on bearing 3 '
                      'and a hold at each speed step'},
          'lines': [_l('mech_eng', 'Restart, then, with a portable probe on 3 and a hold at every step.')]},
         {'when': [],
          'outcome': {'task': 'dsc_st_find', 'text': 'No restart: probe 3\'s gap and wiring checked and the trends '
                      'compared first, the cause written in the log'},
          'lines': [_l('shift_sup', 'Find it first. I\'ll tell dispatch.')]}]},

    {'id': 'ct_fan7_alarm', 'title': 'Cooling tower fan 7\'s vibration alarm keeps going off: change its limit now '
     'or through a change', 'topic': 'wo_ct_fan7_cy', 'room': 'control_room',
     'roles': ['shift_sup', 'ic_eng', 'ccr_op'],
     'evidence': [
         _ev('isa', 'standard', 'An alarm\'s limit comes from its rationalisation and is documented; changing it is '
             'a managed change with the reason recorded.', cite='ISA182'),
         _ev('moc', 'standard', 'A change to a protective setting is reviewed and approved before it is made, a '
             'temporary one too.', cite='MOC'),
         _ev('wet', 'reading', 'Fan 7\'s transmitter junction box found wet.', code='30PAD10CY007',
             value='ct_jb7_wet'),
         _ev('high', 'reading', 'Fan 7\'s vibration above 6.3 mm/s now.', code='30PAD10CY007',
             value='ct_fan7_vib_h'),
         _ev('rule', 'rule', 'Site rule: alarm limits change only through a change request signed by the I&C '
             'engineer and the operations manager.')],
     'positions': [
         {'role': 'shift_sup', 'claim': 'Raise it to 7.1 for now. The operators acknowledge it every ten minutes '
          'and it\'s hiding the real alarms.', 'evidence': ['high']},
         {'role': 'ic_eng', 'claim': 'Not without a change. The reading climbs when it rains: that\'s water in the '
          'junction box, not the fan.', 'evidence': ['isa', 'moc', 'wet', 'rule']},
         {'role': 'ccr_op', 'claim': 'It came in fourteen times last shift. Nobody looks at it any more.',
          'evidence': ['high']}],
     'turns': [_l('shift_sup', 'Fan 7\'s vibration alarm again. Fourteen times last night.'),
               _l('ic_eng', 'That\'s the one that climbs when it rains.'),
               _l('ccr_op', 'I\'ve stopped counting.')],
     'points': [
         {'id': 'limit', 'role': 'ccr_op', 'minutes': 10, 'default': 'change', 'options': [
             _opt('now', 'Back raising the limit now',
                  [_l('$', 'It\'s hiding the alarms that matter. Raise it now and do the paperwork after.'),
                   _l('ic_eng', 'Then it\'s a temporary change with a review date, written down.')], 'shift_sup',
                  ['high']),
             _opt('change', 'Back a change request and fixing the junction box',
                  [_l('$', 'If it\'s water in the box, a higher limit just hides a real rise later. Fix the box.'),
                   _l('shift_sup', 'Then fix it today.')], 'ic_eng', ['moc', 'wet']),
             _opt('shelve', 'Propose shelving it for this shift under the shelving rules while the change goes '
                  'through', [_l('$', 'Shelve it for this shift, logged, and fix the box meanwhile.'),
                              _l('ic_eng', 'Shelved for one shift, not suppressed.')], evidence=['isa'])]}],
     'minutes': 15,
     'agreements': [
         {'when': [{'value': 'ct_jb7_wet', 'is': True}],
          'outcome': {'task': 'dsc_ct7_change', 'text': 'Leave the limit; raise a change request, and dry and '
                      'reseal fan 7\'s junction box under permit'},
          'lines': [_l('shift_sup', 'Water in the box. Leave the limit and get the box fixed today.')]},
         {'when': [{'point': 'limit', 'option': 'now'}],
          'outcome': {'task': 'dsc_ct7_now', 'text': 'Raise fan 7\'s vibration alarm to 7.1 mm/s now as a '
                      'temporary change, reviewed in seven days'},
          'lines': [_l('ic_eng', 'Temporary, seven days, and I sign it.')]},
         {'when': [],
          'outcome': {'task': 'dsc_ct7_change', 'text': 'Leave the limit; raise a change request, and dry and '
                      'reseal fan 7\'s junction box under permit'},
          'lines': [_l('shift_sup', 'Leave the limit. Get the box fixed today.')]}]},
]

# what starts each discussion: its finding (the trainer's fault) to the lead's role; the steam turbine's also on its
# real trip on vibration (a running plant)
TRIGGERS = {'cw_a_vib': 'cw_a_zone_c', 'cond_p2_cal': 'cond_p2_again', 'cw_a_pack': 'cw_a_gland',
            'st_trip': 'st_vib3_trip', 'ct_fan7_alarm': 'ct_fan7_chatter'}
TRIP = {'st_trip': 'st_trip_vib'}


def discussions():
    """data/plant3d/discussions.json."""
    import copy
    return {'format': FORMAT, 'version': 1, 'discussions': copy.deepcopy(DISCUSSIONS)}


# ------------------------------------------------------------------------------------------------ the staff
MESSAGES = {
    'dsc_cw_swap': 'CW pump A: changed over to pump C at the desk for its bearings; see the CW screen',
    'dsc_cw_stop': 'CW pump A comes out today for its bearings: permit asked for',
    'dsc_cw_watch': 'CW pump A runs to the planned stop: a vibration reading every shift',
    'dsc_cp2_out': 'Condenser pressure transmitter 2 coming out for calibration: watch the vacuum trip vote',
    'dsc_cwpk': 'CW pump A discharge valve gland: isolated before anyone touches it, permit asked for',
    'dsc_tray': 'Drip tray under CW pump A\'s discharge valve; the leak noted in the log',
    'dsc_st_reset': 'Steam turbine trip reset at the desk, as far as it would go',
    'dsc_st_restart': 'Steam turbine restart agreed: a portable probe on bearing 3, a hold at each speed step',
    'dsc_st_hold': 'No restart of the steam turbine until the cause of its trip is found',
    'dsc_ct7_temp': 'Fan 7 vibration alarm limit raised to 7.1 mm/s: a temporary change, reviewed in seven days',
    'dsc_ct7_change': 'Fan 7 vibration alarm limit unchanged: a change request raised, the junction box to be fixed',
}


DOORS = {'meeting': 'meet_door', 'control_room': 'cr_door', 'workshop': 'ws_door'}


def _desk():
    return {'go': {'kind': 'desk', 'room': 'control_room'}}


def tasks():
    """The lead's, joiners' and outcome tasks (appended after every task before them: no index moves). The lead's
    task calls the joiners, then holds the meeting; nobody's discussion task is interrupted (a paused lead pauses
    the discussion, REALISM.md §6.3.1)."""
    T = []

    def task(tid, title, steps, **kw):
        T.append(dict({'id': tid, 'title': title, 'steps': steps, 'priority': 2}, **kw))
    for d in DISCUSSIONS:
        lead, joiners = d['roles'][0], d['roles'][1:]
        # to the room first, then the others called, then the discussion: its lead's step is the meeting (a seat
        # and at most 15 minutes' wait for a called person of each joining role, REALISM.md §6.3.1); a joiner who
        # arrives first waits there 15 minutes, and longer while the lead waits there for its people
        task(f'dsc_{d["id"]}', f'Meet about it: {d["title"][0].lower() + d["title"][1:]}',
             [{'go': DOORS[d['room']]}] + [{'call': {'role': r, 'task': f'dsc_{d["id"]}_{r}'}} for r in joiners] +
             [{'discuss': d['id']}],
             interruptible=False)
        for r in joiners:
            task(f'dsc_{d["id"]}_{r}', f'Join the meeting: {d["title"][0].lower() + d["title"][1:]}',
                 [{'discuss': d['id']}], interruptible=False)

    def ask(work, last):
        return [{'permit': {'work': work, 'action': 'request'}, 'else': last}]

    def outcome(tid, title, steps):
        """An agreement's outcome: it runs in place of the rest of the lead's task, for the lead's role alone."""
        task(tid, title, steps)
    # cw_a_vib
    outcome('dsc_cw_a_stop', 'CW pump A out today: change to C and ask for the bearings\' permit', [
        {'call': {'role': 'ccr_op', 'task': 'dsc_cw_swap'}}] + ask('wo_cw_a_brg', 2) + [
        {'say': 'dsc_cw_stop', 'to': 'shift_sup'}])
    task('dsc_cw_swap', 'Change from CW pump A to C at the desk', [
        _desk(), {'op': {'kks': '30PAC10AP003', 'do': 'start', 'where': 'screen'}, 'else': 3},
        {'op': {'kks': '30PAC10AP001', 'do': 'stop', 'where': 'screen'}},
        {'say': 'dsc_cw_swap', 'to': 'maint_sup'}])
    outcome('dsc_cw_a_run', 'CW pump A runs on: ask for the readings and grease job\'s permit',
         ask('wo_cw_a_watch', 1) + [{'say': 'dsc_cw_watch', 'to': 'shift_sup'}])
    # cond_p2_cal
    outcome('dsc_cp2_place', 'Transmitter 2 calibrated in place: ask for its permit', [
        {'say': 'dsc_cp2_out', 'to': 'ccr_op'}] + ask('wo_cond_p2_insitu', 2) + [{'work': 1}])
    outcome('dsc_cp2_bench', 'Transmitter 2 to the bench: ask for its permit', [
        {'say': 'dsc_cp2_out', 'to': 'ccr_op'}] + ask('wo_cond_p2_bench', 2) + [{'work': 1}])
    # cw_a_pack: both isolate
    outcome('dsc_cwpk_now', 'The gland repacked under isolation: change to C, ask for the permit', [
        {'call': {'role': 'ccr_op', 'task': 'dsc_cw_swap'}}] + ask('wo_cw_a_pack', 2) + [
        {'say': 'dsc_cwpk', 'to': 'shift_sup'}])
    outcome('dsc_cwpk_later', 'A drip tray first, then the live-loaded packing under isolation', [
        {'call': {'role': 'field_op', 'task': 'dsc_cw_tray'}}] + ask('wo_cw_a_pack_ll', 2) + [
        {'say': 'dsc_cwpk', 'to': 'shift_sup'}])
    task('dsc_cw_tray', 'Put a drip tray under CW pump A\'s discharge valve', [
        {'go': {'kks': '30PAC10AA101'}}, {'work': [5, 10], 'anim': 'inspect'}, {'say': 'dsc_tray', 'to': 'shift_sup'}])
    # st_trip
    outcome('dsc_st_restart', 'Restart agreed: reset the trip, ask for the portable probe\'s permit', [
        {'call': {'role': 'ccr_op', 'task': 'dsc_st_reset'}}] + ask('wo_st_vib3_watch', 2) + [
        {'say': 'dsc_st_restart', 'to': 'channel'}])
    task('dsc_st_reset', 'Reset the steam turbine\'s vibration trip at the desk', [
        _desk(), {'op': {'kks': '30MAD10CY001', 'do': 'reset', 'trip': 'st_trip_vib', 'where': 'screen'},
                  'else': 2}, {'say': 'dsc_st_reset', 'to': 'shift_sup'}])
    outcome('dsc_st_find', 'No restart before the cause: ask for the probe check\'s permit', [
        {'say': 'dsc_st_hold', 'to': 'channel'}] + ask('wo_st_vib3_rca', 2) + [{'work': 1}])
    # ct_fan7_alarm
    outcome('dsc_ct7_now', 'Fan 7\'s alarm limit raised now: ask for the temporary change\'s permit',
         ask('wo_ct_fan7_alm', 1) + [{'say': 'dsc_ct7_temp', 'to': 'channel'}])
    outcome('dsc_ct7_change', 'Fan 7\'s alarm through a change: ask for the junction box job\'s permit', [
        {'say': 'dsc_ct7_change', 'to': 'channel'}] + ask('wo_ct_fan7_cy', 2) + [{'work': 1}])
    return T


def reactions():
    """Each finding to the lead's role, and the steam turbine's vibration trip too (appended: no index moves)."""
    lead = {d['id']: d['roles'][0] for d in DISCUSSIONS}
    out = [{'on': {'fault': f}, 'roles': [lead[d]], 'task': f'dsc_{d}'} for d, f in TRIGGERS.items()]
    out += [{'on': {'trip': t}, 'roles': [lead[d]], 'task': f'dsc_{d}'} for d, t in TRIP.items()]
    return out
