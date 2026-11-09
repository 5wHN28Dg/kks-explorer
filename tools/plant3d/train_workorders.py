"""Work orders for the first train and the water treatment plant (docs/plant3d/REALISM.md §7.1 and §2.20, milestone
WM1): workorders.json (the failure codes and every piece of equipment's past work orders) and each work's `finds`,
`codes` and `hours`.

The codes follow ISO 14224's structure in our own words: failure modes as the person who notices them names them
(its Table B.6 across the train's equipment classes: pumps, fans, valves, electric motors, instruments, filters,
water treatment vessels), failure mechanisms and causes (its Tables B.2 and B.3), maintenance activities (its Table
B.5). The kinds of maintenance are EN 13306's (corrective, preventive, condition-based). Planned hours are invented,
round and plausible crew hours (two technicians on a motor's bearings for a shift's half, one on a calibration),
from the practice of maintenance planning guides (Palmer: estimates in crew hours, a job's whole time on site).

The history is made from the wear items (train_ageing) and the plant's age: the AGED_MONTHS since the overhaul
(train_ageing.AGED_MONTHS: the ageing scenario's), with every item renewed at the overhaul, the preventive routines
at their intervals since, and each item's failures within the months as its duty and a life drawn from its own
Weibull table (the lives the engine draws for the ageing scenario's seed: the history agrees with its day) make them.
A new run starts from it (§7.1)."""

import train_ageing
import train_discussions

MODES = [
    ('vibration', 'Vibration'), ('noise', 'Abnormal noise'), ('overheating', 'Overheating'),
    ('leak', 'External leakage'), ('fail_start', 'Fails to start on demand'), ('spurious_stop', 'Spurious stop'),
    ('fail_function', 'Fails to function on demand'), ('reading', 'Abnormal instrument reading'),
    ('erratic', 'Erratic output'), ('param_dev', 'Parameter deviation'), ('plugged', 'Plugged or choked'),
    ('low_output', 'Low output'), ('structural', 'Structural deficiency'), ('minor', 'Minor in-service problem'),
    ('other', 'Other'),
]
CAUSES = [
    ('wear', 'Wear'), ('fatigue', 'Fatigue'), ('looseness', 'Looseness'), ('misalignment', 'Clearance or alignment'),
    ('corrosion', 'Corrosion'), ('erosion', 'Erosion'), ('breakage', 'Breakage'), ('overheating', 'Overheating'),
    ('contamination', 'Contamination'), ('blockage', 'Blockage'), ('out_of_adjust', 'Out of adjustment'),
    ('faulty_signal', 'Faulty signal'), ('control_failure', 'Control failure'), ('insulation', 'Insulation failure'),
    ('environment', 'External influence: weather'), ('surge', 'External influence: electrical surge'),
    ('lubrication', 'Lubrication'), ('operating_error', 'Operating error'), ('maint_error', 'Maintenance error'),
    ('expected', 'Expected wear and tear'), ('unknown', 'Unknown'),
]
ACTIONS = [
    ('replace', 'Replace'), ('repair', 'Repair'), ('modify', 'Modify'), ('adjust', 'Adjust'), ('refit', 'Refit'),
    ('check', 'Check'), ('service', 'Service'), ('test', 'Test'), ('inspection', 'Inspection'),
    ('overhaul', 'Overhaul'), ('combination', 'Combination'), ('other', 'Other'),
]

# (finds, codes [mode, cause, action], planned crew hours) by the work's id pattern; the first that matches
RULES = [
    ('_brg', (['vibration', 'noise', 'overheating'], ['vibration', 'wear', 'replace'], 8)),
    ('_gbx', (['vibration', 'noise'], ['vibration', 'wear', 'overhaul'], 16)),
    ('_act', (['fail_function', 'leak'], ['fail_function', 'wear', 'overhaul'], 6)),
    ('_rly', (['spurious_stop'], ['spurious_stop', 'control_failure', 'replace'], 3)),
    ('_ls', (['fail_start'], ['fail_start', 'faulty_signal', 'replace'], 2)),
    ('_cal', (['reading', 'erratic'], ['reading', 'out_of_adjust', 'adjust'], 2)),
    ('_resin', (['param_dev'], ['param_dev', 'breakage', 'replace'], 24)),
    ('_membranes', (['param_dev', 'low_output'], ['param_dev', 'contamination', 'replace'], 16)),
    ('wo_cart_', (['plugged', 'low_output'], ['plugged', 'blockage', 'replace'], 2)),
]
OWN = {
    'wo_ccw_a_motor': (['spurious_stop', 'overheating'], ['spurious_stop', 'looseness', 'repair'], 4),
    'wo_ccw_b_motor': (['spurious_stop', 'overheating'], ['spurious_stop', 'looseness', 'repair'], 4),
    'wo_ccw_b_ir': (None, [None, None, 'test'], 2),
    'wo_ct_fan3': (['vibration', 'noise'], ['vibration', 'wear', 'service'], 8),
    'wo_ct_fan4_pm': (None, [None, None, 'service'], 1),
    'wo_ct_lvl_thaw': (['reading'], ['reading', 'environment', 'modify'], 4),
    'wo_ct_fan7_cy': (['reading', 'erratic'], ['reading', 'contamination', 'repair'], 3),
    'wo_ct_fan9_cy': (['reading'], ['reading', 'surge', 'replace'], 3),
    'wo_cw_a_motor': (['vibration', 'noise', 'overheating'], ['vibration', 'wear', 'replace'], 8),
    'wo_cw_b_motor': (['vibration', 'noise', 'overheating'], ['vibration', 'wear', 'replace'], 8),
    'wo_cw_c_motor': (['vibration', 'noise', 'overheating'], ['vibration', 'wear', 'replace'], 8),
    'wo_paint_cw': (['structural'], [None, None, 'service'], 12),
    'wo_gt1_filters': (['param_dev'], ['param_dev', 'blockage', 'replace'], 12),
    'wo_gen1_cab': (['overheating'], ['overheating', 'blockage', 'replace'], 2),
    'wo_scaffold_hrsg': (None, [None, None, 'other'], 24),
    'wo_hrsg1_lift_drive': (['fail_function', 'noise'], ['fail_function', 'wear', 'repair'], 6),
    'wo_cond_p2_fix': (['reading', 'erratic'], ['reading', None, 'repair'], 3),
    **train_discussions.WO_KEYS,        # the discussions' outcome works (milestone DC3)
}


def keys_of(w):
    """A work's finds, codes and hours (REALISM.md §2.20)."""
    got = OWN.get(w['id']) or next((r for pat, r in RULES if pat in w['id']), None)
    if got is None:
        raise ValueError(f'work {w["id"]}: no work order codes (train_workorders.RULES or OWN)')
    finds, codes, hours = got
    out = {'codes': list(codes), 'hours': hours}
    if finds:
        out['finds'] = list(finds)
    return out


def apply(models):
    """Every work of the models gains its finds, codes and hours."""
    for m in models:
        for w in getattr(m, 'works', []):
            w.update(keys_of(w))


# ------------------------------------------------------------------------------------------------ the history
DAYS_A_MONTH = 365 / 12
# the preventive routines (kind, the codes' kks prefix or a work, the interval in months, action, hours, title)
PUMP_REGREASE = 3          # a large motor's bearings regreased every three months (the motor maker's interval)
FAN_OIL = 12               # a gear reducer's oil changed every year (CTI)
CAL = 12                   # an instrument's calibration checked every year
RELAY_TEST = 24            # protection relays tested every two years
CART = 3                   # cartridge filters changed every three months


def _ago(months):
    return max(1, round(months * DAYS_A_MONTH))


def history(models, months=None):
    """The past work orders of every piece of equipment with a wear item or a routine, newest last by `ago`: the
    overhaul's renewals, the preventive routines, and the failures each item's drawn lives give within the months."""
    months = train_ageing.AGED_MONTHS if months is None else months
    works = [w for m in models for w in getattr(m, 'works', [])]
    by_id = {w['id']: w for w in works}
    out = []

    def add(kks, ago, kind, codes, hours, title, work=None):
        e = {'kks': kks, 'ago': int(ago), 'kind': kind, 'mode': codes[0], 'cause': codes[1], 'action': codes[2],
             'hours': hours, 'title': title}
        if work is not None:
            e['work'] = work
        out.append(e)

    window = _ago(months)
    # the wear items' works: renewed at the overhaul, then their failures within the months (renewal by draws)
    duty = {f'{p[0]}_brg_wear': p[10] for p in train_ageing.PUMPS}
    duty.update({f'{p}_rly_wear': next(i[10] for i in train_ageing.PUMPS if i[0] == p) for p in train_ageing.RELAYS})
    duty.update({f'ct_fan{i}_gbx_wear': train_ageing.FAN_DUTY for i in train_ageing.FANS})
    duty.update({f'cw_{x}_act_wear': 1 for x, _ in train_ageing.VALVES})
    kinds = (('bearing', '_brg_'), ('relay', '_rly_'), ('gearbox', '_gbx_'), ('actuator', '_act_'))
    seen = set()
    for w in works:
        for wear in w.get('renews', []):
            if wear not in duty or wear in seen or not w['id'].endswith(('_brg', '_gbx', '_act', '_rly')):
                continue
            seen.add(wear)
            kind = next(k for k, pre in kinds if pre in wear)
            add(w['kks'], window, 'preventive', [None, None, 'overhaul' if kind != 'relay' else 'test'],
                w['hours'], f'Overhaul: {w["title"].split(": ", 1)[-1]}', w['id'])
            # its failures since: whole lives drawn for the ageing scenario's seed, as its age counts them
            # (train_ageing.apply: the months less every whole life passed), so the history agrees with that day
            life_h = train_ageing.life_of(train_ageing.AGED_SEED, wear.replace('_wear', '_life'))
            per = life_h / (train_ageing.HOURS_A_MONTH * duty[wear])     # months of duty a life lasts
            t = per
            while t < months - 0.5:
                add(w['kks'], _ago(months - t), 'corrective', w['codes'], w['hours'], w['title'], w['id'])
                t += per
    # the routines
    for p in train_ageing.PUMPS:
        for k in range(1, int(months // PUMP_REGREASE) + 1):
            add(p[1], _ago(months - k * PUMP_REGREASE), 'preventive', [None, None, 'service'], 1,
                f'{p[8]} motor: regrease the bearings')
    for i in train_ageing.FANS:
        code = f'30PAD10AN{i:03d}'
        for k in range(1, int(months // FAN_OIL) + 1):
            add(code, _ago(months - k * FAN_OIL), 'preventive', [None, None, 'service'], 3,
                f'Cooling tower fan {i}: change the gear reducer oil')
    for wid, w in by_id.items():
        if wid.endswith('_cal'):
            for k in range(1, int(months // CAL) + 1):
                add(w['kks'], _ago(months - k * CAL), 'preventive', [None, None, 'check'], w['hours'], w['title'], wid)
        if wid.endswith('_rly'):
            for k in range(1, int(months // RELAY_TEST) + 1):
                add(w['kks'], _ago(months - k * RELAY_TEST), 'preventive', [None, None, 'test'], 2,
                    w['title'].split(':')[0] + ': test the motor protection')
        if wid.startswith('wo_cart_'):
            for k in range(1, int(months // CART) + 1):
                add(w['kks'], _ago(months - k * CART), 'preventive', [None, None, 'replace'], w['hours'], w['title'],
                    wid)
    out.sort(key=lambda e: (-e['ago'], e['kks'], e['title']))
    return out


def workorders(models):
    """workorders.json (format walkdown-plant-workorders, version 1)."""
    return {'format': 'walkdown-plant-workorders', 'version': 1,
            'modes': [{'id': i, 'title': t} for i, t in MODES],
            'causes': [{'id': i, 'title': t} for i, t in CAUSES],
            'actions': [{'id': i, 'title': t} for i, t in ACTIONS],
            'history': history(models)}
