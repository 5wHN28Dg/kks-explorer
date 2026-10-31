"""The first train's service lift (docs/PLANT3D.md §20.1, §20.2; decision 0071): a rack-and-pinion lift beside HRSG 1's
stair tower, its landings at grade, at the tower's landing at +16.7 m and at the roof landing (+30 m), made by the content
tool's lift (tools/plant3d/lift_model.py) with the first train's codes, and what the app draws it with: the mast and the
cab (`service_lift`), the landing gates (`lift_gate`), the call stations (`lift_call`), and the drive, the cab's panel
and the load cell riding on the cab (`lift_unit`, drawn by the cab); the bridges from the tower's landings to the gates;
the main switch (the isolation's point) and the drive's repair under a permit; the lift's group on HRSG 1's screen.

Everything is generic and typical (0071's findings): a car of 1.0 × 1.2 m rated 500 kg (6 people at 75 kg), 0.6 m/s,
powered landing gates that open in 2 s; nothing comes from a real plant."""
import lift_model as LM

LIFT = 'hrsg1_lift'
KKS = '10SNB10'
# HRSG 1's stair tower (train_areas.hrsg1: foot [95, 46, 0], top [102, 50, 30], 1.2 m wide, nine flights of 30/9 m):
# its landings at the east end (x 100.8-102) are the even flights' tops; the fifth flight's, at 5 × 30/9 m, is the
# landing between (the same number the builder's stair layout makes: apps/plant3d/builder/geom.gd stair_layout)
TOWER_DZ = 30 / 9
ZS = [0, TOWER_DZ * 5, 30]
# the cab's floor centre in plan (the part's origin, at grade): east of the tower, its gate facing west (the part's −x)
AT = [103.8, 48.0, 0]
CAB = {'depth': 1.0, 'width': 1.2, 'height': 2.3}       # inside: along x (gate to back), along y, floor to roof
GATE_X = 103.22          # the landing gates' leaves, 8 cm in front of the cab's gate (x 103.26-103.3)
MAST_TOP = 33.6         # the mast's top: over the cab's roof rail at the top landing
SPEED = 0.6              # m/s (frequency-controlled, 0071)
RATED_KG = 500
WORKS = True             # the drive's repair under a permit (milestone LIFTS L3: its job in staff.json)
LANDING_NAMES = ['grade', '+16.7 m (the stair tower\'s landing)', '+30 m (the roof)']


def codes():
    return LM.lift_model(LIFT, KKS, ZS)['codes']


def equipment():
    """HRSG 1's lift as equipment: the lift (mast and cab) with the units riding on its cab, each landing's gate and
    call station."""
    c = codes()
    x0, y0, _ = AT
    units = [{'kks': c['drive'], 'name': 'Service lift: drive', 'part': 'lift_unit', 'at': [0.62, 0, 1.2],
              'params': {'kind': 'drive'}},
             {'kks': c['panel'], 'name': 'Service lift: cab control panel', 'part': 'lift_unit',
              'at': [0.2, 0.55, 1.25], 'params': {'kind': 'panel'}},
             {'kks': c['load'], 'name': 'Service lift: load cell', 'part': 'lift_unit', 'at': [0, 0, -0.1],
              'params': {'kind': 'load_cell'}}]
    out = [{'kks': KKS, 'name': 'HRSG 1 service lift', 'part': 'service_lift', 'at': list(AT),
            'params': {'mast': MAST_TOP}, 'plate': 'mast', 'parts': units}]
    for i, z in enumerate(ZS):
        out.append({'kks': c['gates'][i], 'name': f'Service lift: landing gate at {LANDING_NAMES[i]}',
                    'part': 'lift_gate', 'at': [GATE_X, y0, z]})
        out.append({'kks': c['calls'][i], 'name': f'Service lift: call station at {LANDING_NAMES[i]}',
                    'part': 'lift_call', 'at': [GATE_X - 0.06, round(y0 - 0.7, 6), z]})
    return out


def structures():
    """The bridges from the stair tower's landing at +16.7 m and from the roof landing to the gates (the grade's gate
    stands on the ground)."""
    z = ZS[1]
    half = CAB['width'] / 2
    return [{'id': 'hrsg1_lift_bridge_mid', 'part': 'platform', 'at': [102, AT[1] - half, z],
             'params': {'outline': [[0, 0], [round(GATE_X - 102, 6), 0], [round(GATE_X - 102, 6), CAB['width']], [0, CAB['width']]],
                        'deck': 'grating'}},
            {'id': 'hrsg1_lift_bridge_top', 'part': 'platform', 'at': [103, AT[1] - half, ZS[2]],
             'params': {'outline': [[0, 0], [round(GATE_X - 103, 6), 0], [round(GATE_X - 103, 6), CAB['width']], [0, CAB['width']]],
                        'deck': 'grating'}}]


def model(m):
    """The lift's values, ops, alarm, `lifts` entry and view bindings in HRSG 1's model (M of train_model), its main
    switch and the drive's repair under a permit."""
    lm = LM.lift_model(LIFT, KKS, ZS, rated_kg=RATED_KG, speed=SPEED)
    c = lm['codes']
    m.values += lm['values']
    m.ops += lm['ops']
    m.alarms += lm['alarms']
    m.lifts = [lm['lift']]
    L = LIFT
    # the main switch on the drive's panel at grade: off, the lift is not ready (the isolation's point)
    m.op(c['drive'], 'stop', {f'{L}_main': 0}, where=('local',))
    m.op(c['drive'], 'start', {f'{L}_main': 1}, where=('local',))
    m.NOT(f'{L}_main_off', f'{L}_main')
    m.isolation(f'iso_{L}', 'HRSG 1 service lift: main switch',
                [(c['drive'], 'electrical', f'{L}_main_off', 'Main switch off, locked and tagged')])
    if WORKS:
        m.work(f'wo_{L}_drive', c['drive'], 'HRSG 1 service lift: drive repair', 'mech', 'general', f'iso_{L}',
               f'{L}_drive')
    # the load cell's reading (the engine's load, §20.1, with its unit and code: on the screen and the cell's card)
    m.sum(f'{L}_load_kg', [f'{L}_load'], 'kg', c['load'])
    # what the view and the sounds read: the cab travelling, each gate's leaf moving
    m.AND(f'{L}_still', [f'{L}_u_ge', f'{L}_u_le'])
    m.NOT(f'{L}_moving', f'{L}_still')
    for i in range(len(ZS)):
        m.AND(f'{L}_gate{i}_at_open', [f'{L}_open{i}', f'{L}_gate{i}_cmd'])
        m.AND(f'{L}_gate{i}_at_shut', [f'{L}_gate{i}_closed', f'{L}_gate{i}_down'])
        m.OR(f'{L}_gate{i}_rest', [f'{L}_gate{i}_at_open', f'{L}_gate{i}_at_shut'])
        m.NOT(f'{L}_gate{i}_moving', f'{L}_gate{i}_rest')
        m.b(kks=c['gates'][i], anim='leaf', of=f'{L}_gate{i}_pos')
        m.b(kks=c['gates'][i], sound='door_roller', gain={'of': f'{L}_gate{i}_moving', 'table': [[0, 0], [1, 0.5]]})
    m.b(kks=c['drive'], sound='motor_small', gain={'of': f'{L}_moving', 'table': [[0, 0], [1, 0.7]]})
    m.b(kks=c['load'], sound='horn_p3', gain={'of': f'{L}_over', 'table': [[0, 0], [1, 0.5]]})
    m.b(kks=c['panel'], show=f'{L}_z')
    return lm


def faults():
    """The lift's scenario faults (§20.1): the drive's (repaired under the work's permit) and landing 0's gate switch."""
    return LM.lift_model(LIFT, KKS, ZS)['faults']


def screen_groups():
    """{screen id: [group]} for train_screens: the lift's group on HRSG 1's screen (§20.2), with the load the engine
    keeps read by its load cell."""
    return {'hrsg': [{'id': 'lift', 'title': 'Service lift', 'at': [3, 0], 'codes': [KKS]}]}
