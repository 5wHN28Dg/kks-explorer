"""Walkdown Plant content format 1 (docs/PLANT3D.md): the reference validator and the reference behaviour-model engine.

Test-only reference, like ref/courses.py: the product is the Godot app (apps/plant3d, decision 0054), whose content build
and model evaluator must agree with this on ref/vectors/plant3d-v1.json.

    check_dir(path)            -> Bundle      (raises FormatError(code, where) on the first broken rule)
    check_files({rel: bytes})  -> Bundle
    Engine(bundle, scenario)   -> the model at step 0; queue operations, then .step()
"""
import math, os, re
from ref import sjson
from ref.courses import FormatError, need, keys, is_num, num, ident, text, lst, check_table, table_at, Course

STEP = 0.1
ID_RE = re.compile(r'[a-z_][a-z0-9_]{0,31}')
L = '[A-HJ-NP-Z]'
KKS_RE = re.compile(rf'([0-9])([0-9])({L}{{3}})([0-9]{{2}})(?:({L}{{2}})([0-9]{{3}})({L})?)?')
LINK_CODE = re.compile(r'[0-9A-Z]{4,24}')
HEX = re.compile(r'#[0-9a-f]{6}')
MAX = {'bytes': 16 << 20, 'equipment': 4000, 'pipes': 2000, 'structures': 2000, 'points': 256, 'values': 4000,
       'alarms': 500, 'machines': 64, 'steps': 200, 'table': 1024,
       'isolations': 64, 'iso_points': 16, 'works': 128}     # the last three: format 2 (§14)
ISO_KINDS = ('electrical', 'mechanical', 'process', 'instrument')                 # §15.1
DISCIPLINES = ('mech', 'elec', 'inst', 'chem', 'civil')                          # §15.2
PERMIT_KINDS = ('general', 'electrical', 'hot', 'confined')
# a permit's states (§15.3) and the actions that move it: the states each is taken in, and where it goes
PERMIT_STATES = ('none', 'requested', 'approved', 'isolated', 'issued', 'accepted', 'done', 'returned', 'deisolated',
                 'closed', 'cancelled')
PERMIT_ACTIONS = {'request': ((0, 9, 10), 1), 'approve': ((1,), 2), 'issue': ((3,), 4), 'accept': ((4,), 5),
                  'done': ((5,), 6), 'return': ((6,), 7), 'close': ((8,), 9), 'cancel': ((1, 2, 3), 10)}
GROUPS = ('water', 'steam', 'air', 'gas', 'oil', 'chemicals', 'flue_gas')
OP_DO = ('open', 'close', 'stop_travel', 'start', 'stop', 'close_breaker', 'open_breaker', 'set', 'reset',
         'acknowledge')
DIRS = {'n': (0, 1, 0), 's': (0, -1, 0), 'e': (1, 0, 0), 'w': (-1, 0, 0), 'up': (0, 0, 1), 'down': (0, 0, -1)}
WALKABLE = ('platform', 'floor', 'grating', 'road', 'stair', 'ladder')
SURFACES = ('platform', 'floor', 'grating', 'road')     # an outline at the part's height
# structure parts the content build draws itself (apps/plant3d/builder/plant_builder.gd STRUCTURES, less `door`)
BUILDER_STRUCTURES = ('building', 'floor', 'platform', 'grating', 'road', 'stair', 'ladder', 'pit', 'slab', 'fence',
                      'pipe_rack', 'wall', 'handrail', 'column', 'beam', 'trench')
STAIR = {'rise': (0.15, 0.20), 'going': 0.25, 'step_rule': (0.60, 0.66), 'flight': 3.6}
TOL = 0.05          # metres: a stair's or ladder's end meets a surface within this height and plan distance
BLOCKS = ('h', 'p', 'ul', 'ol', 'table', 'callout', 'cards', 'chain')
SIGN_SYMBOLS = ('M003',)   # safety signs' symbols the app draws (ISO 7010; PLANT3D.md §5)
FORMATS = {'plant': 'walkdown-plant', 'area': 'walkdown-plant-area', 'model': 'walkdown-plant-model',
           'scenario': 'walkdown-plant-scenario', 'procedure': 'walkdown-plant-procedure',
           'sounds': 'walkdown-plant-sounds', 'kit': 'walkdown-plant-kit', 'screens': 'walkdown-plant-screens'}
# the beginning of a code (§7.11): unit, F0 and the system letters at least, then as far as the grammar of §6 goes
PREFIX_RE = re.compile(rf'[0-9]{{2}}{L}{{3}}(?:[0-9](?:[0-9](?:{L}(?:{L}(?:[0-9](?:[0-9](?:[0-9]{L}?)?)?)?)?)?)?)?')


# ---------------------------------------------------------------- small checks

def fmt(d, kind, where, top=1):
    """The format name and version: 1, or up to `top` (2: plant.json, and the area, model, scenario and procedure
    files of a version 2 plant, §14)."""
    need(d.get('format') == FORMATS[kind], 'bad_format', f'{where}: format must be "{FORMATS[kind]}"')
    v = d.get('version')
    # a whole number (1.0 is 1, as format 1 always took it), not a boolean
    need(isinstance(v, (int, float)) and not isinstance(v, bool) and v in range(1, top + 1), 'bad_version',
         f'{where}: version must be {" or ".join(str(x) for x in range(1, top + 1))}')
    return int(v)


def time(x, where, lo=0.0, positive=False):
    """A time in content: a multiple of the model step (§1)."""
    num(x, where, lo)
    need(not positive or x > 0, 'bad_number', f'{where}: must be > 0')
    need(abs(x * 10 - round(x * 10)) < 1e-6, 'bad_time', f'{where}: {x} s is not a multiple of 0.1 s')
    return x


def xyz(p, where, n=3):
    lst(p, where, n, n)
    for c in p:
        num(c, where)
    return p


def capped(x, where, key):
    """A list under one of the format's limits (§1): over it is `limit`."""
    lst(x, where)
    need(len(x) <= MAX[key], 'limit', f'{where}: over {MAX[key]} ({len(x)})')
    return x


def name_text(x, where, hi=80):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1–{hi} characters')
    return x


def flag(x, where):
    need(isinstance(x, bool), 'bad_type', f'{where}: true or false')
    return x


def steps(t):
    """A time in seconds as a count of 0.1 s steps (§7.1): rounded half up, never truncated."""
    return math.floor(t / STEP + 0.5)


def kks_parts(code):
    m = KKS_RE.fullmatch(code) if isinstance(code, str) else None
    return m.groups() if m else None


def in_rect(p, b, tol=1e-9):
    (x0, y0), (x1, y1) = b
    return x0 - tol <= p[0] <= x1 + tol and y0 - tol <= p[1] <= y1 + tol


def in_poly(p, poly, tol=0.0):
    """Point in polygon, or within `tol` of its boundary."""
    x, y = p[0], p[1]
    inside = False
    n = len(poly)
    for i in range(n):
        (ax, ay), (bx, by) = poly[i], poly[(i + 1) % n]
        if (ay > y) != (by > y):
            if x < ax + (y - ay) * (bx - ax) / (by - ay):
                inside = not inside
        if tol and seg_dist((x, y), (ax, ay), (bx, by)) <= tol:
            return True
    return inside


def seg_dist(p, a, b):
    """Distance from p to segment ab (2D or 3D)."""
    d = [bb - aa for aa, bb in zip(a, b)]
    w = [pp - aa for aa, pp in zip(a, p)]
    dd = sum(c * c for c in d)
    t = 0.0 if dd == 0 else max(0.0, min(1.0, sum(x * y for x, y in zip(w, d)) / dd))
    return math.dist(p, [aa + t * c for aa, c in zip(a, d)])


def rot(v, yaw):
    """Part frame (x right, y forward, z up) to plant frame, yaw degrees clockwise from north."""
    r = math.radians(yaw)
    c, s = math.cos(r), math.sin(r)
    return (v[0] * c + v[1] * s, -v[0] * s + v[1] * c, v[2])


# ---------------------------------------------------------------- the kit (data/plant3d/kit.json, PLANT3D §9)

PARAM_TYPES = ('num', 'int', 'enum', 'bool', 'text', 'pair', 'xy', 'xyz', 'polygon', 'polygons', 'path', 'records')


def check_param_spec(s, where):
    need(isinstance(s, dict) and s.get('type') in PARAM_TYPES, 'bad_kind', f'{where}: type is one of {PARAM_TYPES}')
    t = s['type']
    opt = {'num': ('min', 'max', 'default'), 'int': ('min', 'max', 'default'), 'enum': ('values', 'default'),
           'bool': ('default',), 'text': ('max', 'default'), 'records': ('fields', 'max')}.get(t, ('default',))
    keys(s, ('type',), opt, where)
    if t in ('num', 'int'):
        need('min' in s and 'max' in s, 'missing_key', f'{where}: min and max')
        num(s['min'], where, integer=t == 'int')
        num(s['max'], where, s['min'], integer=t == 'int')
    if t == 'enum':
        need('values' in s, 'missing_key', f'{where}.values')
        for v in lst(s['values'], where, 1):
            ident(v, where)
    if t == 'records':
        need('fields' in s and 'max' in s, 'missing_key', f'{where}: fields and max')
        need(isinstance(s['fields'], dict) and s['fields'], 'bad_type', f'{where}.fields')
        for k, f in s['fields'].items():
            ident(k, where)
            check_param_spec(f, f'{where}.{k}')
            need(f['type'] != 'records', 'bad_kind', f'{where}.{k}: records one level deep')
        num(s['max'], where, 1, integer=True)
    if t == 'text':
        num(s.get('max', 80), where, 1, integer=True)
    if 'default' in s:
        param_value(s, s['default'], f'{where}.default')


def param_value(s, v, where):
    t = s['type']
    if t == 'num':
        num(v, where, s['min'], s['max'])
    elif t == 'int':
        num(v, where, s['min'], s['max'], integer=True)
    elif t == 'enum':
        need(v in s['values'], 'bad_value', f'{where}: one of {s["values"]}')
    elif t == 'bool':
        flag(v, where)
    elif t == 'text':
        name_text(v, where, s.get('max', 80))
    elif t == 'pair':
        xyz(v, where, 2)
        need(v[0] <= v[1], 'bad_value', f'{where}: [low, high]')
    elif t == 'xy':
        xyz(v, where, 2)
    elif t == 'xyz':
        xyz(v, where)
    elif t == 'polygon':
        for p in lst(v, where, 3, 256):
            xyz(p, where, 2)
    elif t == 'polygons':
        for poly in lst(v, where, 0, 64):
            param_value({'type': 'polygon'}, poly, where)
    elif t == 'path':
        for p in lst(v, where, 2, 256):
            xyz(p, where)
    elif t == 'records':
        for i, r in enumerate(lst(v, where, 1, s['max'])):
            w = f'{where}[{i}]'
            need(isinstance(r, dict), 'bad_type', w)
            for k in r:
                need(k in s['fields'], 'unknown_key', f'{w}.{k}')
            for k, f in s['fields'].items():
                if k in r:
                    param_value(f, r[k], f'{w}.{k}')
                else:
                    need('default' in f, 'missing_key', f'{w}.{k}')


def check_kit(kit, where='kit.json'):
    keys(kit, ('format', 'version', 'dn_od_mm', 'parts'), (), where)
    fmt(kit, 'kit', where)
    prev = 0
    for row in lst(kit['dn_od_mm'], f'{where}.dn_od_mm', 1, 200):
        xyz(row, f'{where}.dn_od_mm', 2)
        need(row[0] > prev and row[1] > row[0] * 0.9, 'bad_table', f'{where}.dn_od_mm: DN rising, OD near DN')
        prev = row[0]
    need(isinstance(kit['parts'], dict) and kit['parts'], 'bad_type', f'{where}.parts')
    for pid, p in kit['parts'].items():
        w = f'{where}: part {pid}'
        ident(pid, w)
        keys(p, ('group', 'params'), ('nozzles', 'anim', 'plates', 'inline', 'walkable'), w)
        ident(p['group'], w)
        need(isinstance(p['params'], dict), 'bad_type', f'{w}.params')
        for k, s in p['params'].items():
            ident(k, w)
            check_param_spec(s, f'{w}.params.{k}')
        need(isinstance(p.get('nozzles', {}), dict), 'bad_type', f'{w}.nozzles')
        for nid, nz in p.get('nozzles', {}).items():
            ident(nid, w)
            keys(nz, ('at', 'dir'), (), f'{w}.nozzles.{nid}')
            need(nz['dir'] in DIRS, 'bad_value', f'{w}.nozzles.{nid}.dir: one of {list(DIRS)}')
            for c in lst(nz['at'], f'{w}.nozzles.{nid}.at', 3, 3):
                if not is_num(c):
                    lst(c, f'{w}.nozzles.{nid}.at', 3, 3)
                    need(c[0] in p['params'] and p['params'][c[0]]['type'] in ('num', 'int'), 'bad_ref',
                         f'{w}.nozzles.{nid}.at: {c[0]!r} is not a number parameter of the part')
                    num(c[1], w)
                    num(c[2], w)
        for a in lst(p.get('anim', []), f'{w}.anim'):
            ident(a, w)
        for a in lst(p.get('plates', []), f'{w}.plates'):
            ident(a, w)
        flag(p.get('inline', False), w)
        flag(p.get('walkable', False), w)
        need(p.get('walkable', False) == (pid in WALKABLE), 'bad_value', f'{w}: walkable parts are {WALKABLE}')
    return kit


def params_of(kit, part, given, where):
    """The part's parameters with defaults filled in; unknown or out-of-range parameters are invalid."""
    need(isinstance(part, str) and part in kit['parts'], 'bad_ref', f'{where}: no kit part {part!r}')
    spec = kit['parts'][part]['params']
    given = {} if given is None else given
    need(isinstance(given, dict), 'bad_type', f'{where}.params')
    out = {}
    for k, v in given.items():
        need(k in spec, 'unknown_key', f'{where}.params.{k}: not a parameter of {part}')
        param_value(spec[k], v, f'{where}.params.{k}')
        out[k] = v
    for k, s in spec.items():
        if k not in out:
            need('default' in s, 'missing_key', f'{where}.params.{k}: {part} needs it')
            out[k] = s['default']
    return out


def nozzle_at(kit, eq, nozzle, where):
    """A nozzle's position and outward direction in plant coordinates."""
    part = kit['parts'][eq['part']]
    need(nozzle in part.get('nozzles', {}), 'bad_ref', f'{where}: {eq["kks"]} ({eq["part"]}) has no nozzle {nozzle!r}')
    need(not eq.get('tilt'), 'unsupported', f'{where}: a pipe can\'t end on a tilted part ({eq["kks"]})')
    nz = part['nozzles'][nozzle]
    local = [c if is_num(c) else eq['params'][c[0]] * c[1] + c[2] for c in nz['at']]
    off = rot(local, eq['yaw'])
    return [eq['at'][i] + off[i] for i in range(3)], rot(DIRS[nz['dir']], eq['yaw'])


# ---------------------------------------------------------------- the whole plant

class Bundle:
    """A checked plant: everything the engine and the tests need, with the counts."""

    def __init__(self):
        self.plant = self.kit = self.sounds = self.screens = None
        self.version = 1                           # plant.json's (§14)
        self.screen_of = {}                        # code shown on the screens -> (screen id, group id) (§7.11)
        self.areas, self.models = [], []          # in plant.json order
        self.scenarios, self.procedures = {}, {}
        self.equipment = {}                        # code -> {kks, part, params, at, yaw, area, ...}
        self.pipes = {}                            # code -> {route, ...}
        self.structures = {}                       # id -> structure
        self.surfaces = []                         # (kind, z, polygon) walkable outlines; pits: ('pit', z, poly)
        self.counts = {}


def load_dir(path):
    """{relative path: bytes} for every file under a plant directory."""
    out = {}
    for root, _, names in os.walk(path):
        for n in names:
            full = os.path.join(root, n)
            with open(full, 'rb') as f:
                out[os.path.relpath(full, path).replace(os.sep, '/')] = f.read()
    return out


def check_dir(path):
    return check_files(load_dir(path))


def parse(files, rel):
    data = files[rel]
    need(len(data) <= MAX['bytes'], 'limit', f'{rel}: over 16 MiB')
    try:
        return sjson.loads(data)
    except sjson.StrictError as e:
        raise FormatError('bad_json', f'{rel}: {e}')


def check_files(files):
    """Check a plant given as {relative path: bytes} (the layout of PLANT3D's file table)."""
    b = Bundle()
    for rel in files:
        need(rel in ('plant.json', 'kit.json', 'sounds.json', 'screens.json') or re.fullmatch(
            r'(areas|model|procedures|scenarios)/[a-z_][a-z0-9_]{0,31}\.json|sounds/[a-z0-9][a-z0-9._-]{0,63}\.ogg', rel),
            'unknown_key', f'{rel}: not a file of the format')
    for rel in ('plant.json', 'kit.json', 'sounds.json'):
        need(rel in files, 'missing_key', f'{rel} is missing')
    b.kit = check_kit(parse(files, 'kit.json'))
    Plant(b, files).check()
    return b


class Plant:
    def __init__(self, b, files):
        self.b, self.files = b, files
        self.codes = {}                  # code -> where it is defined
        self.equipment = b.equipment
        self.ladders, self.stairs = [], []
        self.junctions = []              # (pipe code, other pipe code, point, where)
        self.sound_refs = []             # (value name, where) read by synth sounds

    def check(self):
        b, files = self.b, self.files
        self.check_plant(parse(files, 'plant.json'))
        self.check_sounds(parse(files, 'sounds.json'))
        p = b.plant
        rects = []
        for aid in p['areas']:
            rel = f'areas/{aid}.json'
            need(rel in files, 'missing_key', f'{rel} is missing (plant.json lists area {aid!r})')
            a = parse(files, rel)
            self.check_area(a, aid, rel)
            for other, r, other_inside in rects:
                (ax0, ay0), (ax1, ay1) = a['bounds']
                (bx0, by0), (bx1, by1) = r
                apart = ax1 <= bx0 or bx1 <= ax0 or ay1 <= by0 or by1 <= ay0
                # an interior lies inside the area holding its building (§18.5), and overlaps nothing else
                inside = 'load' in a and not other_inside and bx0 <= ax0 and ax1 <= bx1 and by0 <= ay0 and ay1 <= by1
                held = other_inside and 'load' not in a and ax0 <= bx0 and bx1 <= ax1 and ay0 <= by0 and by1 <= ay1
                need(apart or inside or held, 'area_overlap', f'{rel}: bounds overlap area {other!r}')
            rects.append((aid, a['bounds'], 'load' in a))
            b.areas.append(a)
        # an interior lies inside one area (its building's), not out on ground of no area (§18.5)
        for aid, r, ins in rects:
            if ins:
                (ax0, ay0), (ax1, ay1) = r
                need(any(not o_ins and bx0 <= ax0 and ax1 <= bx1 and by0 <= ay0 and ay1 <= by1
                         for _, ((bx0, by0), (bx1, by1)), o_ins in rects), 'area_overlap',
                     f'areas/{aid}.json: an interior lies inside the area holding its building')
        for rel in files:
            if rel.startswith('areas/'):
                need(rel[6:-5] in p['areas'], 'bad_ref', f'{rel}: area not listed in plant.json')
        self.check_routes()
        self.check_access()
        m = Model(b, self)
        for aid in p['areas']:
            rel = f'model/{aid}.json'
            if rel in files:
                m.add(parse(files, rel), aid, rel)
        for rel in files:
            if rel.startswith('model/'):
                need(rel[6:-5] in p['areas'], 'bad_ref', f'{rel}: area not listed in plant.json')
        m.finish()
        for rel in sorted(files):
            if rel.startswith('scenarios/'):
                s = parse(files, rel)
                check_scenario(s, m, rel)
                need(s['id'] == rel[10:-5], 'bad_id', f'{rel}: id must be the file name')
                b.scenarios[s['id']] = s
        for rel in sorted(files):
            if rel.startswith('procedures/'):
                pr = parse(files, rel)
                check_procedure(pr, m, b, rel)
                need(pr['id'] == rel[11:-5], 'bad_id', f'{rel}: id must be the file name')
                b.procedures[pr['id']] = pr
        b.model = m
        if 'screens.json' in files:
            check_screens(parse(files, 'screens.json'), m, b)
        c = b.counts
        c.update(areas=len(b.areas), codes=len(self.codes), equipment=len(self.equipment), pipes=len(b.pipes),
                 structures=len(b.structures), stairs=len(self.stairs), ladders=len(self.ladders),
                 signs=sum(len(a['signs']) for a in b.areas), values=len(m.values), ops=len(m.ops),
                 interlocks=len(m.interlocks), machines=len(m.machines), alarms=len(m.alarms), trips=len(m.trips),
                 bindings=len(m.bind), scenarios=len(b.scenarios),
                 procedures=sum(1 for x in b.procedures.values() if x['kind'] == 'procedure'),
                 tours=sum(1 for x in b.procedures.values() if x['kind'] == 'tour'),
                 sounds=len(b.sounds['sounds']), screens=len(b.screens['screens']) if b.screens else 0)
        if b.version == 2:
            c.update(isolations=len(m.isolations), works=len(m.works))

    # --- plant.json
    def check_plant(self, p):
        w = 'plant.json'
        keys(p, ('format', 'version', 'id', 'title', 'frequency_hz', 'kks', 'media', 'areas', 'ext', 'start'), (), w)
        self.b.version = fmt(p, 'plant', w, 2)
        ident(p['id'], f'{w}.id')
        name_text(p['title'], f'{w}.title')
        need(p['frequency_hz'] in (50, 60) and not isinstance(p['frequency_hz'], bool), 'bad_value',
             f'{w}.frequency_hz: 50 or 60')
        k = p['kks']
        keys(k, ('units', 'systems', 'equipment', 'measurements', 'source'), (), f'{w}.kks')
        for t, pat in (('units', r'[0-9]'), ('systems', rf'{L}{{3}}'), ('equipment', rf'{L}{{2}}'),
                       ('measurements', rf'C{L}')):
            need(isinstance(k[t], dict), 'bad_type', f'{w}.kks.{t}')
            for code, meaning in k[t].items():
                need(re.fullmatch(pat, code) is not None, 'bad_kks', f'{w}.kks.{t}: {code!r} is not a key of this level')
                name_text(meaning, f'{w}.kks.{t}.{code}')
        for code in k['equipment']:
            need(not code.startswith('C'), 'bad_kks', f'{w}.kks.equipment: {code} is a measurement (C…) code')
        name_text(k['source'], f'{w}.kks.source', 400)
        need(isinstance(p['media'], dict) and p['media'], 'bad_type', f'{w}.media')
        for mid, m in p['media'].items():
            ident(mid, f'{w}.media')
            keys(m, ('group', 'band'), ('name',), f'{w}.media.{mid}')
            if 'name' in m:
                name_text(m['name'], f'{w}.media.{mid}.name', 40)
            need(m['group'] in GROUPS, 'bad_value', f'{w}.media.{mid}.group: one of {GROUPS}')
            need(isinstance(m['band'], str) and HEX.fullmatch(m['band']), 'bad_value', f'{w}.media.{mid}.band: #rrggbb')
        seen = set()
        for a in lst(p['areas'], f'{w}.areas', 1, 64):
            ident(a, f'{w}.areas')
            need(a not in seen, 'dup_id', f'{w}.areas: {a} twice')
            seen.add(a)
        for e in lst(p['ext'], f'{w}.ext', 0, 64):
            ident(e, f'{w}.ext')
        need(len(set(p['ext'])) == len(p['ext']), 'dup_id', f'{w}.ext')
        keys(p['start'], ('at', 'yaw'), (), f'{w}.start')
        xyz(p['start']['at'], f'{w}.start.at')
        num(p['start']['yaw'], f'{w}.start.yaw', 0, 360)
        self.b.plant = p

    def code(self, c, where, unique=True):
        """A plant code: valid grammar (§6), letters in the plant's tables, unique."""
        g = kks_parts(c)
        need(g is not None, 'bad_kks', f'{where}: {c!r} is not a KKS code of format 1 (§6 grammar)')
        unit, f0, sys_, fn, a12, an, a3 = g
        t = self.b.plant['kks']
        need(unit in t['units'], 'bad_kks', f'{where}: {c}: unit {unit} not in the plant\'s key')
        need(sys_ in t['systems'], 'bad_kks', f'{where}: {c}: system {sys_} not in the plant\'s key')
        if a12:
            table = t['measurements'] if a12.startswith('C') else t['equipment']
            need(a12 in table, 'bad_kks', f'{where}: {c}: {a12} not in the plant\'s key')
        if unique:
            need(c not in self.codes, 'dup_id', f'{where}: {c} is already used at {self.codes.get(c)}')
            self.codes[c] = where
        return c

    # --- sounds.json
    def check_sounds(self, s):
        w = 'sounds.json'
        keys(s, ('format', 'version', 'sounds'), (), w)
        fmt(s, 'sounds', w)
        seen = set()
        for i, x in enumerate(lst(s['sounds'], f'{w}.sounds', 0, 256)):
            wi = f'{w}: sound {x.get("id", i) if isinstance(x, dict) else i}'
            need(isinstance(x, dict) and x.get('kind') in ('loop', 'once', 'synth'), 'bad_kind', f'{wi}: kind')
            if x['kind'] == 'synth':
                keys(x, ('id', 'kind'), ('tones', 'noise', 'made'), wi)
                need('tones' in x or 'noise' in x, 'missing_key', f'{wi}: tones or noise')
                for t in lst(x.get('tones', []), wi, 0, 8):
                    keys(t, ('hz',), ('gain',), wi)
                    if is_num(t['hz']):
                        num(t['hz'], wi, 1, 20000)
                    else:
                        keys(t['hz'], ('of', 'table'), (), wi)
                        self.sound_refs.append((t['hz']['of'], wi))
                        check_table(t['hz']['table'], wi)
                    num(t.get('gain', 1), wi, 0, 1)
                if 'noise' in x:
                    keys(x['noise'], ('colour', 'band'), ('gain',), wi)
                    need(x['noise']['colour'] in ('white', 'pink', 'brown'), 'bad_value', f'{wi}: noise colour')
                    param_value({'type': 'pair'}, x['noise']['band'], f'{wi}.noise.band')
                    num(x['noise'].get('gain', 1), wi, 0, 1)
            else:
                keys(x, ('id', 'kind', 'file', 'licence', 'source', 'made'), ('uploader', 'date'), wi)
                need(x['licence'] == 'CC0-1.0', 'bad_value', f'{wi}: recorded clips are CC0-1.0 only (0054)')
                need(isinstance(x['source'], str) and re.fullmatch(r'https://\S+', x['source']), 'bad_link', wi)
                need(f'sounds/{x["file"]}' in self.files, 'bad_ref', f'{wi}: sounds/{x["file"]} is missing')
                text(x['made'], wi)
            ident(x['id'], wi)
            need(x['id'] not in seen, 'dup_id', wi)
            seen.add(x['id'])
        self.b.sounds = s

    # --- areas
    def check_area(self, a, aid, rel):
        # the version first: a version 2 key in an area a version 1 plant lists is a version error (§14)
        av = fmt(a, 'area', rel, self.b.version)
        keys(a, ('format', 'version', 'id', 'title', 'bounds', 'pack', 'equipment', 'pipes', 'structures', 'signs'),
             ('load',) if av == 2 else (), rel)
        if 'load' in a:
            # an interior (§18.5): a scene of its own, loaded near its building's doors; its shell is in the area
            # holding it, and it holds no equipment or pipes (nothing with a code to find while it is not loaded)
            need(a['load'] == 'inside', 'bad_value', f'{rel}.load: "inside"')
            need(not a['equipment'] and not a['pipes'], 'bad_kind', f'{rel}: an interior holds no equipment or pipes')
            # and only what the app shows unbaked in the instanced pieces' format (§18.6): the kit's site parts and
            # doors, none of the builder's own structures (a floor, a wall, a stair… would be a pipeline of its own)
            for s in a['structures'] if isinstance(a['structures'], list) else []:
                need(not isinstance(s, dict) or s.get('part') not in BUILDER_STRUCTURES, 'bad_kind',
                     f'{rel}: structure {s.get("id") if isinstance(s, dict) else s}: an interior holds the kit\'s site '
                     f'parts and doors only, not a {s.get("part") if isinstance(s, dict) else s}')
        need(a['id'] == aid, 'bad_id', f'{rel}: id must be {aid!r}')
        name_text(a['title'], f'{rel}.title')
        lst(a['bounds'], f'{rel}.bounds', 2, 2)
        for p in a['bounds']:
            xyz(p, f'{rel}.bounds', 2)
        (x0, y0), (x1, y1) = a['bounds']
        need(x0 < x1 and y0 < y1, 'bad_value', f'{rel}.bounds: [[x0, y0], [x1, y1]] with x0 < x1, y0 < y1')
        ident(a['pack'], f'{rel}.pack')
        bounds = a['bounds']
        for i, e in enumerate(capped(a['equipment'], f'{rel}.equipment', 'equipment')):
            self.check_equipment(e, aid, bounds, f'{rel}: equipment {e.get("kks", i) if isinstance(e, dict) else i}')
        for i, p in enumerate(capped(a['pipes'], f'{rel}.pipes', 'pipes')):
            self.check_pipe(p, aid, bounds, f'{rel}: pipe {p.get("kks", i) if isinstance(p, dict) else i}')
        for i, s in enumerate(capped(a['structures'], f'{rel}.structures', 'structures')):
            self.check_structure(s, aid, bounds, f'{rel}: structure {s.get("id", i) if isinstance(s, dict) else i}')
        for i, s in enumerate(lst(a['signs'], f'{rel}.signs', 0, 2000)):
            w = f'{rel}: sign {i}'
            keys(s, ('text', 'at', 'yaw'), ('size', 'symbol'), w)
            need(s.get('symbol', 'M003') in SIGN_SYMBOLS, 'bad_value', f'{w}: the symbol {s.get("symbol")!r} is none of {SIGN_SYMBOLS}')
            name_text(s['text'], w)
            xyz(s['at'], w)
            num(s['yaw'], w, 0, 360)
            num(s.get('size', 0.3), w, 0.05, 2)
            need(in_rect(s['at'], bounds), 'outside_area', f'{w}: {s["at"][:2]} is outside the area {bounds}')

    def check_equipment(self, e, aid, bounds, w, parent=None):
        keys(e, ('kks', 'name', 'part', 'at'), ('yaw', 'tilt', 'params', 'plate', 'parts'), w)
        self.code(e['kks'], w)
        name_text(e['name'], f'{w}.name')
        params = params_of(self.b.kit, e['part'], e.get('params'), w)
        part = self.b.kit['parts'][e['part']]
        need(not part.get('walkable'), 'bad_kind', f'{w}: {e["part"]} is a structure part (§5)')
        xyz(e['at'], f'{w}.at')
        yaw = num(e.get('yaw', 0), f'{w}.yaw', 0, 360)
        if 'tilt' in e:
            xyz(e['tilt'], f'{w}.tilt', 2)
        plate = e.get('plate', 'none')
        need(plate == 'none' or plate in part.get('plates', []), 'bad_ref',
             f'{w}.plate: {plate!r} is not a plate point of {e["part"]} ({part.get("plates", [])})')
        if parent is None:
            at, yaw_abs = list(e['at']), yaw
        else:
            off = rot(e['at'], parent['yaw'])
            at = [parent['at'][i] + off[i] for i in range(3)]
            yaw_abs = (parent['yaw'] + yaw) % 360
        need(in_rect(at, bounds), 'outside_area', f'{w}: at {[round(c, 2) for c in at[:2]]} is outside the area '
                                                     f'{bounds}')
        self.equipment[e['kks']] = {'kks': e['kks'], 'part': e['part'], 'params': params, 'at': at, 'yaw': yaw_abs,
                                    'tilt': e.get('tilt'), 'area': aid, 'name': e['name']}
        if 'parts' in e:
            need(parent is None, 'bad_kind', f'{w}.parts: one level only')
            for i, c in enumerate(lst(e['parts'], f'{w}.parts', 0, 64)):
                self.check_equipment(c, aid, bounds, f'{w}: part {c.get("kks", i) if isinstance(c, dict) else i}',
                                     parent=self.equipment[e['kks']])

    def check_pipe(self, p, aid, bounds, w):
        keys(p, ('kks', 'name', 'medium', 'dn', 'from', 'points', 'to'),
             ('od_mm', 'insulation_mm', 'buried', 'valves', 'parts', 'arrows', 'bend'), w)
        self.code(p['kks'], w)
        name_text(p['name'], f'{w}.name')
        need(p['medium'] in self.b.plant['media'], 'bad_ref', f'{w}.medium: {p["medium"]!r} is not in plant.json media')
        num(p['dn'], f'{w}.dn', 6, 4000, integer=True)
        if 'od_mm' in p:
            od = num(p['od_mm'], f'{w}.od_mm', p['dn'] * 0.9, p['dn'] * 1.5)
        else:
            table = dict((int(r[0]), r[1]) for r in self.b.kit['dn_od_mm'])
            need(p['dn'] in table, 'bad_value', f'{w}.dn: DN {p["dn"]} is not in the kit\'s DN table; give od_mm')
            od = table[p['dn']]
        num(p.get('insulation_mm', 0), f'{w}.insulation_mm', 0, 1000)
        num(p.get('arrows', 0), f'{w}.arrows', 0, 1000)
        bend = p.get('bend', '1.5d')
        need(bend in ('1.5d', '3d', '5d'), 'bad_value', f'{w}.bend: 1.5d, 3d or 5d')
        lst(p['points'], f'{w}.points')
        need(len(p['points']) + 2 <= MAX['points'], 'limit', f'{w}: over {MAX["points"]} route points')
        pts = [xyz(q, f'{w}.points') for q in p['points']]
        ends = []
        for side in ('from', 'to'):
            e = p[side]
            ws = f'{w}.{side}'
            need(isinstance(e, dict), 'bad_type', ws)
            if 'nozzle' in e:
                keys(e, ('kks', 'nozzle'), (), ws)
                ends.append(('nozzle', e, ws))
            elif 'pipe' in e:
                keys(e, ('pipe', 'at'), (), ws)
                xyz(e['at'], ws)
                ends.append(('pipe', e, ws))
            else:
                keys(e, ('at',), (), ws)
                xyz(e['at'], ws)
                need(e['at'][2] <= 0, 'bad_route', f'{ws}: a free pipe end lies at or below ground (z ≤ 0); above '
                                                   f'ground a pipe ends on a nozzle or on another pipe')
                ends.append(('free', e, ws))
        nseg = len(pts) + 1
        buried = p.get('buried', [])
        for r in lst(buried, f'{w}.buried', 0, 64):
            lst(r, f'{w}.buried', 2, 2)
            num(r[0], f'{w}.buried', 0, nseg - 1, integer=True)
            num(r[1], f'{w}.buried', r[0], nseg - 1, integer=True)
        entry = {'kks': p['kks'], 'area': aid, 'bounds': bounds, 'od': od, 'bend': float(bend[:-1]), 'points': pts,
                 'ends': ends, 'where': w}
        self.b.pipes[p['kks']] = entry
        for kind in ('valves', 'parts'):
            for i, v in enumerate(lst(p.get(kind, []), f'{w}.{kind}', 0, 64)):
                wv = f'{w}: {kind[:-1]} {v.get("kks", i) if isinstance(v, dict) else i}'
                keys(v, ('kks', 'part', 'at'), ('params', 'name', 'side', 'plate'), wv)
                self.code(v['kks'], wv)
                params = params_of(self.b.kit, v['part'], v.get('params'), wv)
                kp = self.b.kit['parts'][v['part']]
                need(kp.get('inline'), 'bad_kind', f'{wv}: {v["part"]} is not an inline part')
                num(v['at'], f'{wv}.at', 0, 1)
                if 'name' in v:
                    name_text(v['name'], wv)
                if kind == 'parts':
                    need(v.get('side') in ('top', 'bottom', 'left', 'right'), 'bad_value',
                         f'{wv}.side: top, bottom, left or right')
                else:
                    need('side' not in v, 'unknown_key', f'{wv}.side')
                plate = v.get('plate', 'none')
                need(plate == 'none' or plate in kp.get('plates', []), 'bad_ref', f'{wv}.plate')
                self.equipment[v['kks']] = {'kks': v['kks'], 'part': v['part'], 'params': params, 'at': None,
                                            'yaw': 0, 'area': aid, 'pipe': p['kks'], 'name': v.get('name', p['name'])}

    def check_routes(self):
        """Pipe ends on nozzles or other pipes, bends that fit, the from end inside its area (§4)."""
        for code, e in self.b.pipes.items():
            w = e['where']
            route, dirs = [], [None, None]
            for i, (kind, end, ws) in enumerate(e['ends']):
                if kind == 'nozzle':
                    need(end['kks'] in self.equipment and self.equipment[end['kks']]['at'] is not None, 'bad_ref',
                         f'{ws}: no equipment {end["kks"]!r} to end on')
                    pos, d = nozzle_at(self.b.kit, self.equipment[end['kks']], end['nozzle'], ws)
                    dirs[i] = d
                else:
                    pos = list(end['at'])
                    if kind == 'pipe':
                        self.junctions.append((code, end['pipe'], pos, ws))
                route.append(pos)
            full = [route[0]] + e['points'] + [route[1]]
            e['route'] = full
            need(in_rect(full[0], e['bounds']), 'outside_area', f'{w}: its from end {[round(c, 2) for c in full[0]]} '
                                                                f'is outside its area (pipes belong to their from end)')
            for i in range(len(full) - 1):
                need(math.dist(full[i], full[i + 1]) > 1e-6, 'bad_route', f'{w}: points {i} and {i + 1} coincide')
            # a pipe leaves and enters a nozzle along the nozzle's direction
            for i, d in enumerate(dirs):
                if d is None:
                    continue
                a, bpt = (full[0], full[1]) if i == 0 else (full[-1], full[-2])
                seg = [bpt[k] - a[k] for k in range(3)]
                ln = math.sqrt(sum(c * c for c in seg))
                need(sum(seg[k] * d[k] for k in range(3)) / ln > math.cos(math.radians(1)), 'bad_route',
                     f'{w}: the route {"leaves" if i == 0 else "enters"} nozzle '
                     f'{e["ends"][i][1]["nozzle"]!r} of {e["ends"][i][1]["kks"]} at an angle; it must run along '
                     f'the nozzle\'s direction {tuple(round(c, 3) for c in d)}')
            # bends: tangent length R·tan(θ/2) at every corner, R = factor × outside diameter
            r = e['bend'] * e['od'] / 1000
            tan = [0.0] * len(full)
            for i in range(1, len(full) - 1):
                u = [full[i][k] - full[i - 1][k] for k in range(3)]
                v = [full[i + 1][k] - full[i][k] for k in range(3)]
                c = sum(x * y for x, y in zip(u, v)) / (math.hypot(*u) * math.hypot(*v))
                theta = math.acos(max(-1.0, min(1.0, c)))
                need(theta < math.radians(179), 'bad_route', f'{w}: the route turns back on itself at point {i}')
                tan[i] = r * math.tan(theta / 2)
            for i in range(len(full) - 1):
                need_len = tan[i] + tan[i + 1]
                have = math.dist(full[i], full[i + 1])
                need(have + 1e-9 >= need_len, 'bad_route',
                     f'{w}: segment {i} is {have:.2f} m, its bends need {need_len:.2f} m (bend radius {r:.2f} m)')
        for code, other, pos, ws in self.junctions:
            need(other in self.b.pipes and other != code, 'bad_ref', f'{ws}: no other pipe {other!r} to join')
            ro = self.b.pipes[other]['route']
            d = min(seg_dist(pos, ro[i], ro[i + 1]) for i in range(len(ro) - 1))
            need(d <= 0.01, 'bad_route', f'{ws}: the junction point is {d:.2f} m off pipe {other}\'s route')

    # --- structures (§5)
    def check_structure(self, s, aid, bounds, w):
        keys(s, ('id', 'part'), ('at', 'yaw', 'params', 'kks'), w)
        ident(s['id'], f'{w}.id')
        need(s['id'] not in self.b.structures, 'dup_id', f'{w}: id {s["id"]} is already used')
        if 'kks' in s:
            self.code(s['kks'], w)
        need(isinstance(s['part'], str) and s['part'] in self.b.kit['parts'], 'bad_ref', f'{w}: no kit part {s["part"]!r}')
        kp = self.b.kit['parts'][s['part']]
        need(kp['group'] == 'structures', 'bad_kind', f'{w}: {s["part"]} is not a structure part')
        params = params_of(self.b.kit, s['part'], s.get('params'), w)
        num(s.get('yaw', 0), f'{w}.yaw', 0, 360)
        part = s['part']
        if part in ('stair', 'ladder'):
            need('at' not in s, 'unknown_key', f'{w}.at: a {part} is placed by foot and top')
            foot = params['foot']
            need(in_rect(foot, bounds), 'outside_area', f'{w}: foot {foot[:2]} is outside the area {bounds}')
            if part == 'stair':
                need(in_rect(params['top'], bounds), 'outside_area', f'{w}: top {params["top"][:2]} is outside the '
                                                                     f'area {bounds}')
                self.stairs.append((s['id'], params, w))
            else:
                self.ladders.append((s['id'], params, w))
        else:
            need('at' in s, 'missing_key', f'{w}.at')
            at = xyz(s['at'], f'{w}.at')
            yaw = s.get('yaw', 0)
            pts = [at]
            if 'outline' in params:
                poly = [rot([q[0], q[1], 0], yaw)[:2] for q in params['outline']]
                poly = [(at[0] + q[0], at[1] + q[1]) for q in poly]
                pts = poly
                if part in SURFACES:
                    holes = [[(at[0] + rq[0], at[1] + rq[1]) for rq in (rot([q[0], q[1], 0], yaw)[:2] for q in o)]
                             for o in params.get('openings', [])]
                    self.b.surfaces.append((part, at[2], poly, holes))
                elif part == 'pit':
                    self.b.surfaces.append(('pit', at[2], poly, []))
                    self.b.surfaces.append(('floor', at[2] - params['depth'], poly, []))
            # a route (a fence, a wall, a row of plants, a kerb) and partitions lie in the area too
            for q in params.get('route', []) if isinstance(params.get('route'), list) else []:
                r = rot([q[0], q[1], 0], yaw)
                pts.append((at[0] + r[0], at[1] + r[1]))
            for wall in params.get('walls', []) if part == 'room' else []:
                for end in ('a', 'b'):
                    r = rot([wall[end][0], wall[end][1], 0], yaw)
                    pts.append((at[0] + r[0], at[1] + r[1]))
            for q in pts:
                need(in_rect(q, bounds), 'outside_area', f'{w}: {[round(c, 2) for c in q[:2]]} is outside the area '
                                                         f'{bounds}')
        if part == 'building' and params.get('crane', 0):
            # an overhead crane (§5) runs in a rectangular metal-clad hall (its sides along the plant's axes once
            # turned), its rail 6 m up or more, the trolley's top (2.65 m over the rail) 5 cm under the roof steel: the
            # trusses' bottom (spans of 18 m and more, a sixteenth of the span, 1.2 to 3 m) or the rafters' (a fortieth,
            # 0.4 to 1 m), under the liner (3 cm) and the purlins (0.2 m), as apps/plant3d/builder/plant_builder.gd
            o = [rot([q[0], q[1], 0], s.get('yaw', 0))[:2] for q in params['outline']]
            rect = len(o) == 4 and all(abs(o[i][0] - o[(i + 1) % 4][0]) < 1e-6 or abs(o[i][1] - o[(i + 1) % 4][1]) < 1e-6
                                       for i in range(4))
            span = min(max(q[0] for q in o) - min(q[0] for q in o), max(q[1] for q in o) - min(q[1] for q in o))
            steel = min(max(span / 16, 1.2), 3.0) if span >= 18 else min(max(span / 40, 0.4), 1.0)
            need(params['cladding'] == 'metal' and rect and params['crane'] >= 6 and
                 params['crane'] + 0.15 + 1.6 + 0.9 <= params['height'] - 0.03 - 0.2 - steel - 0.05,
                 'bad_value', f'{w}.params.crane: a rectangular metal-clad hall, the rail 6 m up or more, the trolley '
                              f'clear of the roof steel')
        self.b.structures[s['id']] = {'id': s['id'], 'part': part, 'params': params, 'area': aid}

    def walkable(self, p):
        """Is there a walkable surface at point p (within TOL)? The ground (z = 0) is, except over a pit."""
        for kind, z, poly, holes in self.b.surfaces:
            if kind != 'pit' and abs(p[2] - z) <= TOL and in_poly(p, poly, TOL) and \
                    not any(in_poly(p, h) for h in holes):
                return True
        if abs(p[2]) <= TOL:
            return not any(k == 'pit' and in_poly(p, poly) for k, z, poly, h in self.b.surfaces)
        return False

    def check_access(self):
        """Stairs and ladders (§5): their ends meet walkable surfaces; stair flights fit the step rules."""
        for sid, prm, w in self.stairs:
            foot, top = prm['foot'], prm['top']
            h = top[2] - foot[2]
            need(h > 0, 'bad_stair', f'{w}: the top must be above the foot')
            need(self.walkable(foot), 'not_walkable', f'{w}: the foot {foot} meets no walkable surface')
            need(self.walkable(top), 'not_walkable', f'{w}: the top {top} meets no walkable surface')
            dx, dy = abs(top[0] - foot[0]), abs(top[1] - foot[1])
            width = prm['width']
            flights = math.ceil(h / STAIR['flight'] - 1e-9)
            ok, tried = False, []
            for n in range(math.ceil(h / STAIR['rise'][1] - 1e-9), math.floor(h / STAIR['rise'][0] + 1e-9) + 1):
                rise = h / n
                per = math.ceil(n / flights - 1e-9)
                if prm['layout'] == 'straight':
                    run = math.hypot(dx, dy)
                    treads = n - flights
                    going = (run - (flights - 1) * width) / treads if treads else 1.0
                else:
                    if min(dx, dy) < 2 * width - 1e-9:
                        break
                    going = (max(dx, dy) - 2 * width) / (per - 1) if per > 1 else 1.0
                g2 = going + 2 * rise
                tried.append((n, round(rise, 3), round(going, 3)))
                if going >= STAIR['going'] - 1e-9 and STAIR['step_rule'][0] - 1e-9 <= g2 <= STAIR['step_rule'][1] + 1e-9:
                    ok = True
                    break
            need(ok, 'bad_stair',
                 f'{w}: no step count fits a rise of {h:.2f} m in {dx:.2f} × {dy:.2f} m ({prm["layout"]}, width '
                 f'{width} m): rise 0.15–0.20 m, going ≥ 0.25 m, going + 2 × rise 0.60–0.66 m, flights ≤ 3.6 m '
                 f'(EN ISO 14122-3); tried (steps, rise, going) {tried[:4]}')
        for sid, prm, w in self.ladders:
            foot = prm['foot']
            need(prm['top'] > foot[2] + 0.5, 'bad_stair', f'{w}: the top must be above the foot')
            need(self.walkable(foot), 'not_walkable', f'{w}: the foot {foot} meets no walkable surface')
            r = math.radians(prm['facing'])
            exit_ = (foot[0] + 0.4 * math.sin(r), foot[1] + 0.4 * math.cos(r), prm['top'])
            need(self.walkable(exit_), 'not_walkable',
                 f'{w}: stepping off the top at {[round(c, 2) for c in exit_]} meets no walkable surface')


# ---------------------------------------------------------------- the behaviour model (§7)

STATELESS = ('const', 'state', 'of', 'sum', 'product', 'min', 'max', 'diff', 'select', 'cmp', 'and', 'or', 'not')
STATEFUL = ('lag', 'ramp', 'integrate', 'latch', 'delay', 'timer', 'wrap', 'hold')
NODE = {
    'const': (('const',), ()), 'state': (('state',), ()), 'of': (('of', 'table'), ('step',)),
    'sum': (('sum',), ()), 'product': (('product',), ()), 'min': (('min',), ()), 'max': (('max',), ()),
    'diff': (('diff',), ()), 'select': (('select', 'cases'), ()), 'cmp': (('cmp',), ()),
    'and': (('and',), ()), 'or': (('or',), ()), 'not': (('not',), ()),
    'lag': (('lag', 'tau'), ('tau_down', 'init')), 'ramp': (('ramp', 'rate'), ('rate_down', 'init')),
    'integrate': (('integrate', 'gain', 'min', 'max'), ('init',)), 'latch': (('latch', 'reset'), ('init',)),
    'delay': (('delay', 'on'), ('off', 'init')), 'timer': (('timer',), ()), 'wrap': (('wrap', 'period'), ('init',)),
    'hold': (('hold', 'when'), ('init',)),         # format 2 (§15.4)
}
CMP = ('>=', '>', '<=', '<')


def v1_hold(n, where):
    """A `hold` key where format 1 is read (§15.4): refused with format 1's code, which had no hold node: beside
    another node kind it is that kind's unknown key, alone it is no node kind."""
    if isinstance(n, dict) and 'hold' in n:
        other = any(k in n for k in STATEFUL + STATELESS if k != 'hold')
        need(False, 'unknown_key' if other else 'bad_kind', f'{where}: the hold node is format 2 (a version 2 model '
                                                             f'file, §15.4)')


def node_kind(n, where):
    need(isinstance(n, dict), 'bad_type', where)
    st = [k for k in STATEFUL if k in n]
    if len(st) == 1:
        return st[0]
    found = [k for k in STATELESS if k in n]
    need(len(found) == 1 and not st, 'bad_kind', f'{where}: exactly one node kind')
    return found[0]


def node_refs(n, kind):
    """The refs a node reads, in order."""
    if kind in ('const', 'state'):
        return []
    if kind in ('sum', 'product', 'min', 'max', 'and', 'or', 'diff'):
        return list(n[kind])
    if kind == 'select':
        return [n['select']] + list(n['cases'])
    if kind == 'cmp':
        return [n['cmp'][0], n['cmp'][2]]
    if kind == 'latch':
        return [n['latch'], n['reset']]
    if kind == 'hold':
        return [n['hold'], n['when']]
    return [n[kind]]


class Model:
    """The joined model of all areas, checked (§7)."""

    def __init__(self, b, plant):
        self.b, self.p = b, plant
        self.values = []            # [(name, node, kind)]
        self.index = {}             # name -> position in values
        self.ext = list(b.plant['ext'])
        self.ops, self.interlocks, self.machines, self.alarms, self.trips, self.bind = [], [], [], [], [], []
        self.op_keys = {}
        self.pending = []           # (ref, where) read by conditions: resolved in finish()
        self.pending_set = []
        self.states = set()
        self.machine_targets, self.machine_cmds, self.trip_refs = [], [], []
        self.isolations, self.works = [], []     # format 2 (§15)
        self.iso_codes, self.work_isos = [], []  # (code, where), (isolation id, where): resolved in finish()
        self.version = 1                         # of the model file being added

    def kept(self):
        """The values the engine keeps for permits and isolations (§15.1, §15.3), in slot order."""
        return [x['id'] + s for x in self.isolations for s in ('_locked', '_complete')] + \
            [w['id'] + '_permit' for w in self.works]

    def known(self):
        """Names any condition may read: values, ext, machine states, trip latches, and the permits' and isolations'
        values (format 2)."""
        return set(self.index) | set(self.ext) | {m['id'] + '_state' for m in self.machines} | \
            {t['id'] + '_latched' for t in self.trips} | set(self.kept())

    def add(self, d, aid, rel):
        v2 = ('isolations', 'works')
        keys(d, ('format', 'version', 'area'), ('values', 'ops', 'interlocks', 'machines', 'alarms', 'trips', 'bind')
             + v2, rel)                  # first, so a format 1 file keeps format 1's error codes
        self.version = fmt(d, 'model', rel, self.b.version)
        for k in v2:
            need(self.version == 2 or k not in d, 'unknown_key', f'{rel}.{k}: only in a version 2 model file')
        need(d['area'] == aid, 'bad_id', f'{rel}: area must be {aid!r}')
        self.rel = rel
        for i, pair in enumerate(capped(d.get('values', []), f'{rel}.values', 'values')):
            lst(pair, f'{rel}.values[{i}]', 2, 2)
            name = ident(pair[0], f'{rel}.values[{i}]')
            w = f'{rel}: value {name}'
            need(name not in self.known(), 'dup_id', f'{w}: name already used (a value, an ext value, a machine\'s '
                 f'state or a trip\'s latch, §7.1)')
            kind = self.check_node(pair[1], w)
            self.index[name] = len(self.values)
            self.values.append((name, pair[1], kind))
            if kind == 'state':
                self.states.add(name)
        need(len(self.values) <= MAX['values'], 'limit', f'{rel}: the joined model has over {MAX["values"]} values')
        need(len(self.machines) + len(d.get('machines', [])) <= MAX['machines'], 'limit', f'{rel}: over '
             f'{MAX["machines"]} machines')
        for i, m in enumerate(capped(d.get('machines', []), f'{rel}.machines', 'machines')):
            self.check_machine(m, f'{rel}: machine {m.get("id", i) if isinstance(m, dict) else i}')
        for i, t in enumerate(lst(d.get('trips', []), f'{rel}.trips', 0, 500)):
            self.check_trip(t, f'{rel}: trip {t.get("id", i) if isinstance(t, dict) else i}')
        for i, o in enumerate(lst(d.get('ops', []), f'{rel}.ops', 0, 4000)):
            self.check_op(o, f'{rel}: op {i} ({o.get("kks", "?")} {o.get("do", "?")})' if isinstance(o, dict) else rel)
        for i, x in enumerate(lst(d.get('interlocks', []), f'{rel}.interlocks', 0, 1000)):
            w = f'{rel}: interlock {x.get("id", i) if isinstance(x, dict) else i}'
            keys(x, ('id', 'when', 'do'), ('kks', 'text'), w)
            ident(x['id'], w)
            need(x['id'] not in {y['id'] for y in self.interlocks}, 'dup_id', w)
            if 'kks' in x:
                self.kks_ref(x['kks'], w)
            if 'text' in x:
                name_text(x['text'], w, 200)
            self.cond(x['when'], f'{w}.when')
            self.actions(x['do'], f'{w}.do')
            self.interlocks.append(x)
        for i, a in enumerate(capped(d.get('alarms', []), f'{rel}.alarms', 'alarms')):
            self.check_alarm(a, f'{rel}: alarm {a.get("id", i) if isinstance(a, dict) else i}')
        need(len(self.alarms) <= MAX['alarms'], 'limit', f'{rel}: the joined model has over {MAX["alarms"]} alarms')
        for i, x in enumerate(lst(d.get('bind', []), f'{rel}.bind', 0, 8000)):
            self.check_bind(x, f'{rel}: binding {i}')
        for i, x in enumerate(lst(d.get('isolations', []), f'{rel}.isolations')):
            self.check_isolation(x, f'{rel}: isolation {x.get("id", i) if isinstance(x, dict) else i}')
        need(len(self.isolations) <= MAX['isolations'], 'limit', f'{rel}: the joined model has over '
             f'{MAX["isolations"]} isolations')
        for i, x in enumerate(lst(d.get('works', []), f'{rel}.works')):
            self.check_work(x, f'{rel}: work {x.get("id", i) if isinstance(x, dict) else i}')
        need(len(self.works) <= MAX['works'], 'limit', f'{rel}: the joined model has over {MAX["works"]} works')

    def check_isolation(self, x, w):
        """§15.1: the points made safe and locked for a work."""
        keys(x, ('id', 'text', 'points'), (), w)
        need(isinstance(x['id'], str) and ID_RE.fullmatch(x['id']) and len(x['id']) <= 22, 'bad_id',
             f'{w}: id of at most 22 characters')
        need(x['id'] not in {y['id'] for y in self.isolations}, 'dup_id', w)
        name_text(x['text'], f'{w}.text', 200)
        lst(x['points'], f'{w}.points', 1)
        need(len(x['points']) <= MAX['iso_points'], 'limit', f'{w}: over {MAX["iso_points"]} points')
        seen = set()
        for i, pt in enumerate(x['points']):
            wp = f'{w}.points[{i}]'
            keys(pt, ('kks', 'kind', 'how'), ('safe',), wp)
            self.kks_ref(pt['kks'], wp)
            need(pt['kks'] not in seen, 'dup_id', f'{wp}: {pt["kks"]} twice in one isolation')
            seen.add(pt['kks'])
            need(pt['kind'] in ISO_KINDS, 'bad_value', f'{wp}.kind: one of {ISO_KINDS}')
            name_text(pt['how'], f'{wp}.how', 200)
            if 'safe' in pt:
                self.cond(pt['safe'], f'{wp}.safe')
            self.iso_codes.append((pt['kks'], wp))
        self.isolations.append(x)

    def check_work(self, x, w):
        """§15.2: a job on equipment that needs a permit."""
        keys(x, ('id', 'kks', 'title', 'discipline', 'permit'), ('isolation', 'repairs', 'set', 'task'), w)
        need(isinstance(x['id'], str) and ID_RE.fullmatch(x['id']) and len(x['id']) <= 22, 'bad_id',
             f'{w}: id of at most 22 characters')
        need(x['id'] not in {y['id'] for y in self.works}, 'dup_id', w)
        self.kks_ref(x['kks'], w)
        name_text(x['title'], f'{w}.title', 120)
        need(x['discipline'] in DISCIPLINES, 'bad_value', f'{w}.discipline: one of {DISCIPLINES}')
        need(x['permit'] in PERMIT_KINDS, 'bad_value', f'{w}.permit: one of {PERMIT_KINDS}')
        if 'isolation' in x:
            self.work_isos.append((ident(x['isolation'], f'{w}.isolation'), f'{w}.isolation'))
        if 'repairs' in x:
            ident(x['repairs'], f'{w}.repairs')
            need(x['repairs'] not in {y.get('repairs') for y in self.works}, 'dup_id',
                 f'{w}.repairs: another work already repairs {x["repairs"]} (one work per fault)')
        if 'set' in x:
            need(isinstance(x['set'], dict), 'bad_type', f'{w}.set: an object of state names and numbers')
            for k, v in x['set'].items():
                self.pending_set.append((k, f'{w}.set'))
                num(v, f'{w}.set.{k}')
        if 'task' in x:
            ident(x['task'], f'{w}.task')       # a task of staff.json once the plant has one (§16, milestone S1)
        self.works.append(x)

    def kks_ref(self, c, where):
        need(isinstance(c, str) and c in self.p.codes, 'bad_ref', f'{where}: no equipment {c!r} in the plant')

    def ref(self, r, where, stateless):
        """A ref: a number, or a value name (earlier only for stateless nodes, §7.1)."""
        if is_num(r):
            return
        need(isinstance(r, str) and ID_RE.fullmatch(r), 'bad_ref', f'{where}: {r!r} is not a number or value name')
        if stateless:
            ok = r in self.index or r in self.ext
            if not ok:
                self.pending.append((r, where, True))
        else:
            self.pending.append((r, where, False))

    def cond(self, r, where):
        need(isinstance(r, str), 'bad_ref', f'{where}: a value name')
        self.pending.append((r, where, False))

    def check_node(self, n, w):
        if self.version == 1:
            v1_hold(n, w)
        kind = node_kind(n, w)
        req, opt = NODE[kind]
        keys(n, req, opt + ('unit', 'kks'), w)
        if 'unit' in n:
            name_text(n['unit'], f'{w}.unit', 16)
        if 'kks' in n:
            self.kks_ref(n['kks'], f'{w}.kks')
        stateless = kind in STATELESS
        if kind in ('const', 'state'):
            num(n[kind], w)
        elif kind == 'of':
            check_table(n['table'], f'{w}.table')
            if 'step' in n:
                flag(n['step'], w)
        elif kind in ('sum', 'product', 'min', 'max', 'and', 'or'):
            lst(n[kind], w, 1, 64)
        elif kind == 'diff':
            lst(n[kind], w, 2, 2)
        elif kind == 'select':
            lst(n['cases'], w, 1, 64)
        elif kind == 'cmp':
            lst(n['cmp'], w, 3, 3)
            need(n['cmp'][1] in CMP, 'bad_value', f'{w}: comparison is one of {CMP}')
        elif kind == 'lag':
            time(n['tau'], f'{w}.tau', positive=True)
            if 'tau_down' in n:
                time(n['tau_down'], f'{w}.tau_down', positive=True)
        elif kind == 'ramp':
            num(n['rate'], w, 0)
            need(n['rate'] > 0, 'bad_number', f'{w}.rate > 0')
            if 'rate_down' in n:
                num(n['rate_down'], w, 0)
                need(n['rate_down'] > 0, 'bad_number', f'{w}.rate_down > 0')
        elif kind == 'integrate':
            num(n['gain'], w)
            num(n['min'], w)
            num(n['max'], w, n['min'])
        elif kind == 'delay':
            time(n['on'], f'{w}.on')
            time(n.get('off', 0), f'{w}.off')
        elif kind == 'wrap':
            num(n['period'], w, 0)
            need(n['period'] > 0, 'bad_number', f'{w}.period > 0')
        if 'init' in n:
            num(n['init'], f'{w}.init')
            if kind in ('latch', 'delay'):
                need(n['init'] in (0, 1), 'bad_value', f'{w}.init: 0 or 1')
            if kind == 'integrate':
                need(n['min'] <= n['init'] <= n['max'], 'bad_value', f'{w}.init within min and max')
            if kind == 'wrap':
                need(0 <= n['init'] < n['period'], 'bad_value', f'{w}.init within [0, period)')
        if kind == 'hold':
            # §15.4: the input as this step computed it (an earlier value), `when` as the previous step left it
            self.ref(n['hold'], w, True)
            self.ref(n['when'], w, False)
            return kind
        for r in node_refs(n, kind):
            self.ref(r, w, stateless)
        return kind

    def sets(self, s, where):
        need(isinstance(s, dict) and s, 'bad_type', f'{where}: an object of state names and numbers')
        for k, v in s.items():
            self.pending_set.append((k, where))
            num(v, f'{where}.{k}')

    def actions(self, acts, where):
        for i, a in enumerate(lst(acts, where, 1, 32)):
            w = f'{where}[{i}]'
            need(isinstance(a, dict), 'bad_type', w)
            if 'machine' in a:
                keys(a, ('machine', 'to'), (), w)
                self.machine_targets.append((a['machine'], a['to'], w))
            else:
                keys(a, ('set',), (), w)
                self.sets(a['set'], w)

    def check_machine(self, m, w):
        keys(m, ('id', 'kks', 'init', 'commands', 'states'), (), w)
        need(isinstance(m['id'], str) and ID_RE.fullmatch(m['id']) and len(m['id']) <= 26, 'bad_id',
             f'{w}: id of at most 26 characters')
        need(m['id'] not in {x['id'] for x in self.machines}, 'dup_id', w)
        need(m['id'] + '_state' not in self.index and m['id'] + '_state' not in self.ext, 'dup_id', f'{w}: a value or ext value is named {m["id"]}_state')
        self.kks_ref(m['kks'], w)
        ids = []
        for i, s in enumerate(lst(m['states'], f'{w}.states', 1, 64)):
            ws = f'{w}: state {s.get("id", i) if isinstance(s, dict) else i}'
            keys(s, ('id',), ('set', 'next', 'watch', 'say'), ws)
            ident(s['id'], ws)
            need(s['id'] not in ids, 'dup_id', ws)
            ids.append(s['id'])
            if 'set' in s:
                self.sets(s['set'], ws)
            for nx in lst(s.get('next', []), f'{ws}.next', 0, 16):
                lst(nx, f'{ws}.next', 2, 2)
                self.cond(nx[0], f'{ws}.next')
            flag(s.get('watch', True), ws)
            if 'say' in s:
                name_text(s['say'], ws, 200)
        for s in m['states']:
            for nx in s.get('next', []):
                need(nx[1] in ids, 'bad_ref', f'{w}: next state {nx[1]!r} is not a state')
        need(m['init'] in ids, 'bad_ref', f'{w}.init: {m["init"]!r} is not a state')
        need(isinstance(m['commands'], dict), 'bad_type', f'{w}.commands')
        for c, spec in m['commands'].items():
            wc = f'{w}.commands.{c}'
            ident(c, wc)
            keys(spec, ('from', 'to'), (), wc)
            need(spec['to'] in ids, 'bad_ref', f'{wc}.to: not a state')
            if spec['from'] != '*':
                for f in lst(spec['from'], f'{wc}.from', 1):
                    need(f in ids, 'bad_ref', f'{wc}.from: {f!r} is not a state')
        m['_ids'] = ids
        self.machines.append(m)

    def check_trip(self, t, w):
        keys(t, ('id', 'kks', 'text', 'when', 'do'), ('isa', 'delay', 'first_out'), w)
        need(isinstance(t['id'], str) and ID_RE.fullmatch(t['id']) and len(t['id']) <= 24, 'bad_id',
             f'{w}: id of at most 24 characters')
        need(t['id'] not in {x['id'] for x in self.trips}, 'dup_id', w)
        need(t['id'] + '_latched' not in self.index and t['id'] + '_latched' not in self.ext, 'dup_id', f'{w}: a value or ext value is named {t["id"]}_latched')
        self.kks_ref(t['kks'], w)
        name_text(t['text'], w, 120)
        if 'isa' in t:
            need(isinstance(t['isa'], str) and re.fullmatch(r'[A-Z]{1,6}', t['isa']), 'bad_value', f'{w}.isa')
        self.cond(t['when'], f'{w}.when')
        time(t.get('delay', 0), f'{w}.delay')
        self.actions(t['do'], f'{w}.do')
        if 'first_out' in t:
            ident(t['first_out'], f'{w}.first_out')
        self.trips.append(t)

    def check_op(self, o, w):
        keys(o, ('kks', 'do', 'where'), ('set', 'needs', 'machine', 'input', 'range', 'trip'), w)
        self.kks_ref(o['kks'], w)
        do = o['do']
        if 'machine' in o:
            self.machine_cmds.append((o['machine'], do, w))
            need('input' not in o and 'trip' not in o, 'unknown_key', f'{w}: a machine command takes no input or trip')
        else:
            need(do in OP_DO, 'bad_value', f'{w}.do: one of {OP_DO}, or a machine command with "machine"')
            if do == 'set':
                need('input' in o and 'range' in o, 'missing_key', f'{w}: a set op names its input state and range')
                self.pending_set.append((o['input'], f'{w}.input'))
                param_value({'type': 'pair'}, o['range'], f'{w}.range')
            else:
                need('input' not in o and 'range' not in o, 'unknown_key', f'{w}: input/range only on set ops')
            if do == 'reset':
                need('trip' in o, 'missing_key', f'{w}.trip')
                self.trip_refs.append((o['trip'], w))
            else:
                need('trip' not in o, 'unknown_key', f'{w}.trip')
            if do not in ('set', 'reset'):
                need('set' in o, 'missing_key', f'{w}.set')
        if 'set' in o:
            self.sets(o['set'], f'{w}.set')
        for i, nd in enumerate(lst(o.get('needs', []), f'{w}.needs', 0, 16)):
            lst(nd, f'{w}.needs[{i}]', 2, 2)
            self.cond(nd[0], f'{w}.needs[{i}]')
            name_text(nd[1], f'{w}.needs[{i}]', 200)
        for x in lst(o['where'], f'{w}.where', 1, 2):
            need(x in ('local', 'screen'), 'bad_value', f'{w}.where: local or screen')
        need(len(set(o['where'])) == len(o['where']), 'dup_id', f'{w}.where')
        key = (o['kks'], do, o.get('trip'))
        need(key not in self.op_keys, 'dup_id', f'{w}: {o["kks"]} already has a {do!r} op')
        self.op_keys[key] = o
        self.ops.append(o)

    def check_alarm(self, a, w):
        keys(a, ('id', 'kks', 'text', 'when', 'priority', 'where'), ('isa', 'clear', 'delay', 'suppress'), w)
        ident(a['id'], w)
        need(a['id'] not in {x['id'] for x in self.alarms}, 'dup_id', w)
        self.kks_ref(a['kks'], w)
        self.kks_ref(a['where'], f'{w}.where')
        name_text(a['text'], w, 120)
        if 'isa' in a:
            need(isinstance(a['isa'], str) and re.fullmatch(r'[A-Z]{1,6}', a['isa']), 'bad_value', f'{w}.isa')
        for k in ('when', 'clear', 'suppress'):
            if k in a:
                self.cond(a[k], f'{w}.{k}')
        time(a.get('delay', 0), f'{w}.delay')
        need(a['priority'] in (1, 2, 3) and not isinstance(a['priority'], bool), 'bad_value', f'{w}.priority: 1, 2 or 3')
        self.alarms.append(a)

    def check_bind(self, x, w):
        need(isinstance(x, dict) and 'kks' in x, 'missing_key', f'{w}.kks')
        kinds = [k for k in ('anim', 'show', 'sound', 'lamp', 'shake') if k in x]
        need(len(kinds) == 1, 'bad_kind', f'{w}: exactly one of anim, show, sound, lamp, shake')
        k = kinds[0]
        self.kks_ref(x['kks'], w)
        eq = self.p.equipment.get(x['kks'])
        if k == 'anim':
            keys(x, ('kks', 'anim', 'of'), ('scale',), w)
            chans = self.b.kit['parts'][eq['part']].get('anim', []) if eq else []
            need(x['anim'] in chans, 'bad_ref', f'{w}: {x["kks"]} ({eq and eq["part"]}) has no anim channel '
                                                f'{x["anim"]!r} ({chans})')
            self.cond(x['of'], f'{w}.of')
            num(x.get('scale', 1), w)
        elif k == 'show':
            keys(x, ('kks', 'show'), (), w)
            self.cond(x['show'], f'{w}.show')
        elif k == 'sound':
            keys(x, ('kks', 'sound'), ('gain', 'pitch'), w)
            need(x['sound'] in {s['id'] for s in self.b.sounds['sounds']}, 'bad_ref',
                 f'{w}: no sound {x["sound"]!r} in sounds.json')
            for g in ('gain', 'pitch'):
                if g in x:
                    keys(x[g], ('of', 'table'), (), f'{w}.{g}')
                    self.cond(x[g]['of'], f'{w}.{g}.of')
                    check_table(x[g]['table'], f'{w}.{g}.table')
        elif k == 'lamp':
            keys(x, ('kks', 'lamp', 'of'), (), w)
            need(x['lamp'] in ('running', 'stopped', 'open', 'closed', 'fault', 'beacon'), 'bad_value', f'{w}.lamp')
            self.cond(x['of'], f'{w}.of')
        else:
            keys(x, ('kks', 'shake'), ('scale',), w)
            self.cond(x['shake'], f'{w}.shake')
            num(x.get('scale', 1), w, 0)
        self.bind.append(x)

    def finish(self):
        known = self.known()
        for r, where, stateless in self.pending:
            if stateless:
                need(r in known, 'bad_ref', f'{where}: no value {r!r}')
                need(r not in self.index, 'forward_ref',
                     f'{where}: {r!r} is read before it is computed (a stateless node reads earlier values only)')
            else:
                need(r in known, 'bad_ref', f'{where}: no value {r!r}')
        for k, where in self.pending_set:
            need(k in self.states, 'bad_ref', f'{where}: {k!r} is not a state value (only states are set)')
        machines = {m['id']: m for m in self.machines}
        for mid, to, w in self.machine_targets:
            need(mid in machines, 'bad_ref', f'{w}: no machine {mid!r}')
            need(to in machines[mid]['_ids'], 'bad_ref', f'{w}: machine {mid} has no state {to!r}')
        for mid, cmd, w in self.machine_cmds:
            need(mid in machines, 'bad_ref', f'{w}: no machine {mid!r}')
            need(cmd in machines[mid]['commands'], 'bad_ref', f'{w}: machine {mid} has no command {cmd!r}')
        trips = {t['id'] for t in self.trips}
        for t, w in self.trip_refs:
            need(t in trips, 'bad_ref', f'{w}: no trip {t!r}')
        for name, sw in self.p.sound_refs:
            need(name in known, 'bad_ref', f'{sw}: no value {name!r}')
        # format 2 (§15): an isolation's point locks something; a work's isolation exists; the kept values' names
        locks = {n.get('kks') for _, n, kind in self.values if kind == 'state'} | {a['kks'] for a in self.alarms}
        for c, where in self.iso_codes:
            need(c in locks, 'bad_ref', f'{where}: {c} is the code of no state or alarm of the model (a lock must do '
                                        f'something)')
        isos = {x['id'] for x in self.isolations}
        for i, where in self.work_isos:
            need(i in isos, 'bad_ref', f'{where}: no isolation {i!r}')
        # no restarts under lock (§15.2): a work's set writes no state of a code of its own isolation
        state_kks = {name: n.get('kks') for name, n, kind in self.values if kind == 'state'}
        for w in self.works:
            if 'isolation' not in w:
                continue
            own = {pt['kks'] for x in self.isolations if x['id'] == w['isolation'] for pt in x['points']}
            for k in w.get('set', {}):
                need(state_kks.get(k) not in own, 'locked_write',
                     f'work {w["id"]}.set: {k} is a state of {state_kks.get(k)}, which its own isolation locks '
                     f'(a work never restarts its own locked-out equipment; what it puts right is a fault it repairs)')
        for name in self.kept():
            need(name not in self.index and name not in self.ext, 'dup_id',
                 f'{name}: a value or ext value has the name of a permit\'s or isolation\'s value (§15)')


# ---------------------------------------------------------------- the control room screens (screens.json, §7.11)

def screen_items(m):
    """{code: [what the model has for it]}: every code the screens show (§7.11), in the model's order."""
    out = {}

    def add(code, why):
        if isinstance(code, str):
            out.setdefault(code, [])
            if why not in out[code]:
                out[code].append(why)
    for name, node, _ in m.values:
        if 'unit' in node and 'kks' in node:
            add(node['kks'], 'value')
    for x in m.bind:
        if 'show' in x:
            add(x['kks'], 'value')
        elif 'lamp' in x:
            add(x['kks'], 'lamp')
        elif x.get('anim') in ('stem', 'disc', 'blades'):
            add(x['kks'], 'position')
    for o in m.ops:
        add(o['kks'], 'op')
    for mc in m.machines:
        if 'kks' in mc:
            add(mc['kks'], 'machine')
    for a in m.alarms:
        add(a.get('kks', a.get('where')), 'alarm')
    for t in m.trips:
        if 'kks' in t:
            add(t['kks'], 'trip')
    return out


def owner(code, prefixes):
    """The longest of the prefixes the code begins with, or None."""
    best = None
    for p in prefixes:
        if code.startswith(p) and (best is None or len(p) > len(best)):
            best = p
    return best


def check_screens(s, m, b):
    w = 'screens.json'
    keys(s, ('format', 'version', 'overview', 'screens'), ('left_out',), w)
    version = fmt(s, 'screens', w, b.version)
    units = {name: node for name, node, _ in m.values if 'unit' in node}
    desk_codes = {c for c, e in b.equipment.items() if e['part'] == 'operator_desk'}

    def desks(x, where):
        """Format 2 (§14): the operator desks a screen is reached from (default: every desk)."""
        if 'desks' not in x:
            return
        need(version == 2, 'unknown_key', f'{where}.desks: only in a version 2 screens.json')
        ds = lst(x['desks'], f'{where}.desks', 1, 16)
        for c in ds:
            need(isinstance(c, str) and c in desk_codes, 'bad_ref', f'{where}.desks: {c!r} is no operator desk of '
                 f'the plant')
        need(len(set(ds)) == len(ds), 'dup_id', f'{where}.desks: a desk twice')

    def shown_value(v, where):
        need(isinstance(v, str) and v in units, 'bad_ref', f'{where}: {v!r} is no value with a unit')

    ov = s['overview']
    keys(ov, ('title', 'short', 'key'), ('desks',), f'{w}.overview')
    desks(ov, f'{w}.overview')
    name_text(ov['title'], f'{w}.overview.title')
    name_text(ov['short'], f'{w}.overview.short', 16)
    for v in lst(ov['key'], f'{w}.overview.key', 1, 12):
        shown_value(v, f'{w}.overview.key')
    need(len(set(ov['key'])) == len(ov['key']), 'dup_id', f'{w}.overview.key: a value twice')
    prefixes = {}                         # prefix -> (screen id, group id), or (None, index) for left_out
    extras = set()
    seen_screens = set()
    for i, sc in enumerate(lst(s['screens'], f'{w}.screens', 1, 16)):
        ws = f'{w}: screen {sc.get("id", i) if isinstance(sc, dict) else i}'
        keys(sc, ('id', 'short', 'title', 'groups'), ('lines', 'trend', 'desks'), ws)
        desks(sc, ws)
        ident(sc['id'], ws)
        need(sc['id'] not in seen_screens and sc['id'] != 'overview', 'dup_id', f'{ws}: id used twice (or "overview")')
        seen_screens.add(sc['id'])
        name_text(sc['title'], f'{ws}.title')
        name_text(sc['short'], f'{ws}.short', 16)
        gids, cells = set(), set()
        for j, gr in enumerate(lst(sc['groups'], f'{ws}.groups', 1, 16)):
            wg = f'{ws}: group {gr.get("id", j) if isinstance(gr, dict) else j}'
            keys(gr, ('id', 'title', 'at', 'codes'), ('extra',), wg)
            ident(gr['id'], wg)
            need(gr['id'] not in gids, 'dup_id', f'{wg}: id used twice on the screen')
            gids.add(gr['id'])
            name_text(gr['title'], f'{wg}.title')
            lst(gr['at'], f'{wg}.at', 2, 2)
            for c in gr['at']:
                num(c, f'{wg}.at', 0, 7)
                need(isinstance(c, int) and not isinstance(c, bool), 'bad_type', f'{wg}.at: whole numbers')
            need(tuple(gr['at']) not in cells, 'dup_id', f'{wg}.at: another group of the screen stands there')
            cells.add(tuple(gr['at']))
            for p in lst(gr['codes'], f'{wg}.codes', 1, 16):
                need(isinstance(p, str) and PREFIX_RE.fullmatch(p), 'bad_kks', f'{wg}.codes: {p!r} is not the '
                     f'beginning of a code (unit, F0 and the system letters at least)')
                need(p not in prefixes, 'dup_id', f'{wg}.codes: {p} is already placed')
                prefixes[p] = (sc['id'], gr['id'])
            for v in lst(gr.get('extra', []), f'{wg}.extra', 0, 16):
                shown_value(v, f'{wg}.extra')
                need('kks' not in units[v], 'bad_ref', f'{wg}.extra: {v} has a code: it is shown by its code')
                need(v not in extras, 'dup_id', f'{wg}.extra: {v} is shown twice')
                extras.add(v)
        for j, x in enumerate(lst(sc.get('lines', []), f'{ws}.lines', 0, 32)):
            wl = f'{ws}: line {j}'
            keys(x, ('from', 'to'), ('medium',), wl)
            need(x['from'] in gids and x['to'] in gids and x['from'] != x['to'], 'bad_ref',
                 f'{wl}: from and to are two groups of the screen')
            if 'medium' in x:
                need(x['medium'] in b.plant['media'], 'bad_ref', f'{wl}: no medium {x["medium"]!r} in plant.json')
        tr = lst(sc.get('trend', []), f'{ws}.trend', 0, 6)
        for v in tr:
            shown_value(v, f'{ws}.trend')
        need(len(set(tr)) == len(tr), 'dup_id', f'{ws}.trend: a value twice')
    for j, x in enumerate(lst(s.get('left_out', []), f'{w}.left_out', 0, 64)):
        wl = f'{w}: left_out {j}'
        keys(x, ('codes', 'why'), (), wl)
        name_text(x['why'], f'{wl}.why', 200)
        for p in lst(x['codes'], f'{wl}.codes', 1, 16):
            need(isinstance(p, str) and PREFIX_RE.fullmatch(p), 'bad_kks', f'{wl}.codes: {p!r} is not the beginning '
                 f'of a code')
            need(p not in prefixes, 'dup_id', f'{wl}.codes: {p} is already placed')
            prefixes[p] = (None, j)
    used = set()
    on_screen_ops = {o['kks'] for o in m.ops if 'screen' in o['where']}
    for code, why in screen_items(m).items():
        p = owner(code, prefixes)
        need(p is not None, 'unplaced', f'{w}: {code} is on no screen and not left out (§7.11)')
        if prefixes[p][0] is None:
            # what only the screens work, or an alarm (counted on the screens' tabs, acknowledged there), needs a screen
            need(code not in on_screen_ops and 'alarm' not in why, 'bad_ref',
                 f'{w}: left_out {prefixes[p][1]} leaves out {code}, which has an alarm or an operation from the '
                 f'screens (§7.11)')
        used.add(prefixes[p])
        if prefixes[p][0] is not None:
            b.screen_of[code] = prefixes[p]
    for sc in s['screens']:
        for gr in sc['groups']:
            need((sc['id'], gr['id']) in used or gr.get('extra'), 'bad_ref',
                 f'{w}: screen {sc["id"]} group {gr["id"]} shows nothing (no code of the model begins with its codes)')
    for j, _ in enumerate(s.get('left_out', [])):
        need((None, j) in used, 'bad_ref', f'{w}: left_out {j} leaves out nothing')
    b.screens = s


def check_scenario(s, m, rel):
    keys(s, ('format', 'version', 'id', 'title', 'init'), ('latched', 'faults'), rel)
    fmt(s, 'scenario', rel, m.b.version)
    ident(s['id'], rel)
    name_text(s['title'], rel)
    need(isinstance(s['init'], dict), 'bad_type', f'{rel}.init')
    for k, v in s['init'].items():
        num(v, f'{rel}.init.{k}')
        kind = m.values[m.index[k]][2] if k in m.index else None
        ok = k in m.ext or kind in ('state',) + STATEFUL and kind != 'timer'
        need(ok, 'bad_ref', f'{rel}.init.{k}: not a state, stateful value (other than a timer) or ext value')
        n = m.values[m.index[k]][1] if k in m.index else None
        if kind in ('latch', 'delay'):
            need(v in (0, 1), 'bad_value', f'{rel}.init.{k}: 0 or 1')
        elif kind == 'integrate':
            need(n['min'] <= v <= n['max'], 'bad_value', f'{rel}.init.{k}: within min and max')
        elif kind == 'wrap':
            need(0 <= v < n['period'], 'bad_value', f'{rel}.init.{k}: within [0, period)')
    for e in m.ext:
        need(e in s['init'], 'missing_key', f'{rel}.init: the scenario sets every ext value ({e})')
    trips = {t['id'] for t in m.trips}
    for i, t in enumerate(lst(s.get('latched', []), f'{rel}.latched')):
        need(t in trips, 'bad_ref', f'{rel}.latched: no trip {t!r}')
        need(t not in s['latched'][:i], 'dup_id', f'{rel}.latched: {t} twice')
    seen = set()
    for i, f in enumerate(lst(s.get('faults', []), f'{rel}.faults', 0, 256)):
        w = f'{rel}: fault {f.get("id", i) if isinstance(f, dict) else i}'
        keys(f, ('id', 'set', 'text'), ('when', 'repair', 'kks'), w)
        ident(f['id'], w)
        need(f['id'] not in seen, 'dup_id', w)
        seen.add(f['id'])
        name_text(f['text'], w, 200)
        m.pending, m.pending_set = [], []
        m.sets(f['set'], f'{w}.set')
        if 'repair' in f:
            m.sets(f['repair'], f'{w}.repair')
            # no restarts under lock (§15.2): a repair made as a work's own write (its done, or the trainee's under its
            # permit, §15.5) writes no command (a state an op sets) of a code of that work's own isolation
            commands = {k for o in m.ops for k in o.get('set', {})} | {o['input'] for o in m.ops if 'input' in o}
            state_kks = {name: n.get('kks') for name, n, kind in m.values if kind == 'state'}
            for wk in m.works:
                if wk.get('repairs') != f['id'] or 'isolation' not in wk:
                    continue
                own = {pt['kks'] for x in m.isolations if x['id'] == wk['isolation'] for pt in x['points']}
                for k in f['repair']:
                    need(k not in commands or state_kks.get(k) not in own, 'locked_write',
                         f'{w}.repair: {k} is a command of {state_kks.get(k)}, which work {wk["id"]}\'s own isolation '
                         f'locks (a repair writes the fault\'s states, never a command)')
        if 'kks' in f:
            m.kks_ref(f['kks'], f'{w}.kks')
        if 'when' in f:
            if isinstance(f['when'], str):
                m.cond(f['when'], f'{w}.when')
            else:
                if m.b.version == 1:
                    v1_hold(f['when'], f'{w}.when')
                kind = node_kind(f['when'], f'{w}.when')
                need(kind in STATELESS and kind not in ('const', 'state'), 'bad_kind',
                     f'{w}.when: a value name or a stateless node')
                keys(f['when'], NODE[kind][0], NODE[kind][1], f'{w}.when')
                m.check_node(f['when'], f'{w}.when')
                m.pending = [(r, wh, False) for r, wh, _ in m.pending]
        m.finish()


class PlantText(Course):
    """Runs and blocks of COURSES.md §3–§4 inside procedures: only kks links (to this plant's codes), course links
    and https links; no glossary, no figures, images, questions or tools (PLANT3D §8)."""

    def __init__(self, codes):
        super().__init__({})
        self.codes = codes

    def target(self, t, where):
        need(isinstance(t, dict) and t, 'bad_link', where)
        ks = set(t)
        if ks == {'kks'}:
            need(t['kks'] in self.codes, 'bad_link', f'{where}: no equipment {t["kks"]!r} in the plant')
        elif ks in ({'course'}, {'course', 'page'}):
            for k in ks:
                ident(t[k], where)
        elif ks == {'url'}:
            need(isinstance(t['url'], str) and re.fullmatch(r'https://[^\s]+', t['url']), 'bad_link', where)
        else:
            raise FormatError('bad_link', f'{where}: a link goes to kks, course or url')

    def check_terms(self):
        need(not self.gloss_refs, 'bad_ref', 'procedures have no glossary')


def check_procedure(pr, m, b, rel):
    keys(pr, ('format', 'version', 'id', 'title', 'kind', 'steps'), ('scenario', 'intro'), rel)
    fmt(pr, 'procedure', rel, b.version)
    ident(pr['id'], rel)
    name_text(pr['title'], rel)
    need(pr['kind'] in ('procedure', 'tour'), 'bad_value', f'{rel}.kind: procedure or tour')
    tour = pr['kind'] == 'tour'
    if not tour:
        need('scenario' in pr, 'missing_key', f'{rel}.scenario: a procedure starts from a scenario')
    if 'scenario' in pr:
        need(pr['scenario'] in b.scenarios, 'bad_ref', f'{rel}.scenario: no scenario {pr["scenario"]!r}')
    tx = PlantText(m.p.codes)
    if 'intro' in pr:
        tx.blocks(pr['intro'], f'{rel}.intro', BLOCKS)
    ids = set()
    known = m.known()
    need(isinstance(pr['steps'], list) and pr['steps'], 'bad_length', f'{rel}.steps: at least one step')
    for i, s in enumerate(capped(pr['steps'], f'{rel}.steps', 'steps')):
        w = f'{rel}: step {s.get("id", i) if isinstance(s, dict) else i}'
        keys(s, ('id', 'text', 'at', 'go'), ('do', 'ordered', 'done', 'why'), w)
        ident(s['id'], w)
        need(s['id'] not in ids, 'dup_id', w)
        ids.add(s['id'])
        tx.run(s['text'], f'{w}.text')
        for c in lst(s['at'], f'{w}.at', 0 if not tour else 1, 32):
            need(c in m.p.codes, 'bad_ref', f'{w}.at: no equipment {c!r} in the plant')
        need(s['go'] in ('walk', 'fly', 'none'), 'bad_value', f'{w}.go: walk, fly or none')
        if tour:
            for k in ('do', 'done', 'ordered'):
                need(k not in s, 'unknown_key', f'{w}.{k}: a tour step has no {k}')
        for j, d in enumerate(lst(s.get('do', []), f'{w}.do', 0, 32)):
            wd = f'{w}.do[{j}]'
            keys(d, ('kks', 'do'), ('value', 'trip'), wd)
            op = m.op_keys.get((d['kks'], d['do'], d.get('trip')))
            need(op is not None, 'bad_ref', f'{wd}: the model has no op {d["do"]!r} on {d["kks"]}')
            if d['do'] == 'set' and 'machine' not in op:
                need('value' in d, 'missing_key', f'{wd}.value')
                num(d['value'], wd, op['range'][0], op['range'][1])
            else:
                need('value' not in d, 'unknown_key', f'{wd}.value')
        if 'ordered' in s:
            flag(s['ordered'], w)
        if 'done' in s:
            need(s['done'] in known, 'bad_ref', f'{w}.done: no value {s["done"]!r}')
        if 'why' in s:
            tx.blocks(s['why'], f'{w}.why', BLOCKS)
    tx.check_terms()


# ---------------------------------------------------------------- the engine (§7.10)

class Engine:
    """Steps the joined model of a checked bundle exactly as PLANT3D §7.10 says.

    Trainee inputs are queued and take effect in step 1 of the next step, in the order made:
        op(kks, do, value=None, trip=None), ack(alarm), shelve(alarm, seconds), unshelve(alarm), fault(id),
        repair(id)
    (fault: a scenario fault without `when`, pressed by the trainer; applied in step 3; repair: a fault's repair,
    applied in step 3 after the faults, §7.8; in a version 2 plant the trainer's). Format 2 (§15, free mode: person
    None):
        permit(work, action, person=None), lock(work, point, person=None), unlock(work, point, person=None),
        repair_under(fault, work, person=None)
    (permit actions handled in step 1; locks and unlocks noted in step 1 and made at the start of step 3, §17.1; the
    trainee's repair under a permit checked in step 1 and made in step 3, §15.5). lock_effects(work, point) answers
    what a lock would do (§15.6) without changing the run.
    """

    def __init__(self, b, scenario):
        m = b.model
        self.m = m
        sc = b.scenarios[scenario] if isinstance(scenario, str) else scenario
        self.sc = sc
        names = [v[0] for v in m.values] + list(m.ext) + [x['id'] + '_state' for x in m.machines] + \
            [t['id'] + '_latched' for t in m.trips] + m.kept()
        # format 2 (§15): permits and isolations
        self.v2 = b.version == 2
        self.isos = {x['id']: x for x in m.isolations}
        self.works = {w['id']: w for w in m.works}
        self.pstate = {w['id']: 0 for w in m.works}     # §15.3's states
        self.ptw = {}                                   # work -> its permit's number, from its last request
        self.ptw_count = 0
        self.acceptor = {}                              # work -> who accepted its permit (None in free mode)
        self.holder = {x['id']: None for x in m.isolations}     # the work holding each isolation (§15.1)
        self.locks = {}                                 # (isolation id, point index) -> who locked it
        self.code_locks = {}                            # code -> its locked points, of every isolation
        self.names = names
        self.ix = {n: i for i, n in enumerate(names)}
        self.n = len(names)
        self.machines = m.machines
        self.mstate = {}
        self.trips = m.trips
        self.latched = {t['id']: False for t in m.trips}
        self.trip_count = {t['id']: 0 for t in m.trips}
        self.first_out = {}
        self.alarms = m.alarms
        self.astate = {a['id']: 'normal' for a in m.alarms}
        self.acount = {a['id']: 0 for a in m.alarms}
        self.shelved = {}
        self.il_prev = {x['id']: False for x in m.interlocks}
        self.faults = {f['id']: f for f in sc.get('faults', [])}
        self.fault_cond = {}
        self.faults_done = set()
        self.faults_fixed = set()       # applied and repaired since (§7.8)
        self.queue = []
        self.events = []
        self.step_no = 0
        self.watch = {}
        self.state_kks = {self.ix[name]: n['kks'] for name, n, kind in m.values if kind == 'state' and 'kks' in n}
        self._compile()
        for fid, f in self.faults.items():
            if isinstance(f.get('when'), dict):
                self.fault_cond[fid] = self._node(-1, f['when'], node_kind(f['when'], fid))
        self._step0()

    def clone(self):
        """An independent copy at the same step (forks of a run: one cold start, many trip tests)."""
        c = type(self).__new__(type(self))
        c.__dict__.update(self.__dict__)
        c._compile()
        for k, v in self.mem.items():
            c.mem[k][:] = v
        c.fault_cond = {fid: c._node(-1, self.faults[fid]['when'], node_kind(self.faults[fid]['when'], fid))
                        for fid in self.fault_cond}
        for k in ('cur', 'events', 'queue'):
            setattr(c, k, list(getattr(self, k)))
        for k in ('mstate', 'latched', 'trip_count', 'first_out', 'astate', 'acount', 'shelved', 'il_prev',
                  'pstate', 'ptw', 'acceptor', 'holder', 'locks', 'code_locks'):
            setattr(c, k, dict(getattr(self, k)))
        c.faults_done = set(self.faults_done)
        c.faults_fixed = set(self.faults_fixed)
        return c

    # --- compile nodes to closures over (cur, prev, mem)
    def _r(self, r):
        if is_num(r):
            c = float(r)
            return lambda cur, prev: c
        i = self.ix[r]
        return lambda cur, prev, i=i: cur[i]

    def _p(self, r):
        """A stateful node's input: the previous step's value."""
        if is_num(r):
            c = float(r)
            return lambda cur, prev: c
        i = self.ix[r]
        return lambda cur, prev, i=i: prev[i]

    def _compile(self):
        self.prog = []          # (index, fn(cur, prev) -> value) for stateless and stateful nodes
        self.init = [0.0] * self.n
        self.mem = {}
        self.hold0 = {}         # holds without an init (their own or the scenario's): their input at step 0 (§15.4)
        for i, (name, n, kind) in enumerate(self.m.values):
            fn = self._node(i, n, kind)
            if kind == 'state':
                self.init[i] = float(n['state'])
            elif kind in STATEFUL:
                self.init[i] = float(n.get('init', 0))
            if kind == 'hold' and 'init' not in n and name not in self.sc['init']:
                self.hold0[i] = self._r(n['hold'])
            if fn is not None:
                self.prog.append((i, fn, kind in STATEFUL))

    def _node(self, i, n, kind):
        R = self._r
        if kind == 'const':
            c = float(n['const'])
            return lambda cur, prev: c
        if kind == 'state':
            return None
        if kind == 'of':
            f, t, st = R(n['of']), [[float(a), float(b)] for a, b in n['table']], bool(n.get('step'))
            return lambda cur, prev: table_at(t, f(cur, prev), st)
        if kind in ('sum', 'product', 'min', 'max', 'and', 'or'):
            fs = [R(r) for r in n[kind]]
            if kind == 'sum':
                def g(cur, prev):
                    s = 0.0
                    for f in fs:
                        s = s + f(cur, prev)
                    return s
            elif kind == 'product':
                def g(cur, prev):
                    s = 1.0
                    for f in fs:
                        s = s * f(cur, prev)
                    return s
            elif kind == 'min':
                def g(cur, prev):
                    return min(f(cur, prev) for f in fs)
            elif kind == 'max':
                def g(cur, prev):
                    return max(f(cur, prev) for f in fs)
            elif kind == 'and':
                def g(cur, prev):
                    return 1.0 if all(f(cur, prev) >= 0.5 for f in fs) else 0.0
            else:
                def g(cur, prev):
                    return 1.0 if any(f(cur, prev) >= 0.5 for f in fs) else 0.0
            return g
        if kind == 'diff':
            a, b = R(n['diff'][0]), R(n['diff'][1])
            return lambda cur, prev: a(cur, prev) - b(cur, prev)
        if kind == 'select':
            s, cs = R(n['select']), [R(r) for r in n['cases']]
            k = len(cs)
            return lambda cur, prev: cs[min(max(math.floor(s(cur, prev)), 0), k - 1)](cur, prev)
        if kind == 'cmp':
            a, op, b = R(n['cmp'][0]), n['cmp'][1], R(n['cmp'][2])
            if op == '>=':
                return lambda cur, prev: 1.0 if a(cur, prev) >= b(cur, prev) else 0.0
            if op == '>':
                return lambda cur, prev: 1.0 if a(cur, prev) > b(cur, prev) else 0.0
            if op == '<=':
                return lambda cur, prev: 1.0 if a(cur, prev) <= b(cur, prev) else 0.0
            return lambda cur, prev: 1.0 if a(cur, prev) < b(cur, prev) else 0.0
        if kind == 'not':
            a = R(n['not'])
            return lambda cur, prev: 0.0 if a(cur, prev) >= 0.5 else 1.0
        P = self._p
        if kind == 'lag':
            u = P(n['lag'])
            up = 1 - math.exp(-STEP / n['tau'])
            dn = 1 - math.exp(-STEP / n.get('tau_down', n['tau']))
            def g(cur, prev):
                x, y = u(cur, prev), prev[i]
                return y + (x - y) * (up if x >= y else dn)
            return g
        if kind == 'ramp':
            u = P(n['ramp'])
            ru, rd = n['rate'] * STEP, n.get('rate_down', n['rate']) * STEP
            def g(cur, prev):
                x, y = u(cur, prev), prev[i]
                if x >= y:
                    return min(x, y + ru)
                return max(x, y - rd)
            return g
        if kind == 'integrate':
            u, gain, lo, hi = P(n['integrate']), n['gain'], n['min'], n['max']
            return lambda cur, prev: min(max(prev[i] + gain * u(cur, prev) * STEP, lo), hi)
        if kind == 'latch':
            s, r = P(n['latch']), P(n['reset'])
            return lambda cur, prev: 0.0 if r(cur, prev) >= 0.5 else (1.0 if s(cur, prev) >= 0.5 else prev[i])
        if kind == 'delay':
            u = P(n['delay'])
            n_on, n_off = steps(n['on']), steps(n.get('off', 0))
            self.mem[i] = [0, 0]
            mem = self.mem[i]
            def g(cur, prev):
                y = prev[i]
                if u(cur, prev) >= 0.5:
                    mem[0] += 1
                    mem[1] = 0
                    if y < 0.5 and mem[0] >= n_on:
                        y = 1.0
                else:
                    mem[1] += 1
                    mem[0] = 0
                    if y >= 0.5 and mem[1] >= n_off:
                        y = 0.0
                return y
            return g
        if kind == 'timer':
            u = P(n['timer'])
            self.mem[i] = [0]
            mem = self.mem[i]
            def g(cur, prev):
                if u(cur, prev) >= 0.5:
                    mem[0] += 1
                else:
                    mem[0] = 0
                return mem[0] / 10      # 0.1 × count, as count / 10 so every reader gets the same double
            return g
        if kind == 'hold':
            # §15.4: the input as this step computed it while `when` (as the previous step left it) is false
            u, wh = R(n['hold']), P(n['when'])
            return lambda cur, prev: prev[i] if wh(cur, prev) >= 0.5 else u(cur, prev)
        if kind == 'wrap':
            u, per = P(n['wrap']), float(n['period'])
            def g(cur, prev):
                x = prev[i] + u(cur, prev) * STEP
                return x - per * math.floor(x / per)
            return g
        raise AssertionError(kind)

    # --- step 0
    def _step0(self):
        cur = list(self.init)
        sc = self.sc
        self.cur = cur
        for mc in self.machines:
            self.mstate[mc['id']] = mc['_ids'].index(mc['init'])
            cur[self.ix[mc['id'] + '_state']] = float(self.mstate[mc['id']])
            st = mc['states'][self.mstate[mc['id']]]
            for k, v in st.get('set', {}).items():
                cur[self.ix[k]] = float(v)
        for k, v in sc['init'].items():
            cur[self.ix[k]] = float(v)
        for t in sc.get('latched', []):
            self.latched[t] = True
            cur[self.ix[t + '_latched']] = 1.0
        prev = list(cur)
        for i, fn, stateful in self.prog:
            if not stateful:
                cur[i] = fn(cur, prev)
            elif i in self.hold0:
                cur[i] = self.hold0[i](cur, prev)

    # --- trainee inputs
    def op(self, kks, do, value=None, trip=None):
        self.queue.append(('op', kks, do, value, trip))

    def ack(self, alarm):
        self.queue.append(('ack', alarm))

    def shelve(self, alarm, seconds):
        self.queue.append(('shelve', alarm, seconds))

    def unshelve(self, alarm):
        self.queue.append(('unshelve', alarm))

    def fault(self, fid):
        self.queue.append(('fault', fid))

    def repair(self, fid):
        self.queue.append(('repair', fid))

    def repair_under(self, fid, work, person=None):
        self.queue.append(('repair', fid, work, person))

    def permit(self, work, action, person=None):
        self.queue.append(('permit', work, action, person))

    def lock(self, work, point, person=None):
        self.queue.append(('lock', work, point, person))

    def unlock(self, work, point, person=None):
        self.queue.append(('unlock', work, point, person))

    def v(self, name):
        return self.cur[self.ix[name]]

    def truth(self, name, vals=None):
        return (vals or self.cur)[self.ix[name]] >= 0.5

    def ev(self, *e):
        self.events.append([self.step_no] + list(e))

    def _set(self, s, work=None):
        for k, v in s.items():
            self._write(self.ix[k], float(v), work)

    def _skips(self, i, work=None):
        """Whether a write to a state is skipped: its code is locked (§15.1), and not by isolations all held by the
        work whose own `done` writes it."""
        c = self.state_kks.get(i)
        return c is not None and bool(self.code_locks.get(c)) and (
            work is None or any(self.holder[iso] != work for iso, p in self.locks
                                if self.isos[iso]['points'][p]['kks'] == c))

    def _blocked(self, s, work=None):
        """Whether any write of a fault's `set` or `repair` would be skipped: such a fault or repair is not made at all
        (§15.1), so it is neither applied nor repaired without acting."""
        return bool(self.code_locks) and any(self._skips(self.ix[k], work) for k in s)

    def _write(self, i, x, work=None):
        """A write to a state, skipped while its code is locked (§15.1); a work's own `done` writes (work) are made
        when every isolation locking the code is held by that work."""
        if not self._skips(i, work):
            self.cur[i] = x

    def locking(self, code):
        """The isolations (in model order) with a locked point on this code."""
        if not self.code_locks.get(code):
            return []
        return [x['id'] for x in self.m.isolations
                if any((x['id'], p) in self.locks for p, pt in enumerate(x['points']) if pt['kks'] == code)]

    def n_locked(self, iso):
        return sum(1 for p in range(len(self.isos[iso]['points'])) if (iso, p) in self.locks)

    def _permit(self, work, action, person, dones):
        """A permit action (§15.3), in step 1."""
        if not (isinstance(work, str) and work in self.works and isinstance(action, str)
                and action in PERMIT_ACTIONS):
            self.ev('permit', work, action, person, 'unknown', [])
            return
        w = self.works[work]
        iso = w.get('isolation')
        frm, to = PERMIT_ACTIONS[action]
        why = []
        if person is not None:
            why.append('authority')     # no staff in the plant: free mode, person null (§17.1)
        if self.pstate[work] not in frm:
            why.append('state')
        if action == 'request' and iso is not None and self.holder[iso] is not None:
            why.append('iso_busy')
        if why:
            self.ev('permit', work, action, person, 'refused', why)
            return
        self.pstate[work] = to
        self.cur[self.ix[work + '_permit']] = float(to)
        if action == 'request':
            self.ptw_count += 1
            self.ptw[work] = f'PTW-{self.ptw_count:04d}'
            self.acceptor.pop(work, None)
            if iso is not None:
                self.holder[iso] = work
        elif action == 'accept':
            self.acceptor[work] = person
        elif action == 'done':
            dones.append(work)
        elif action in ('cancel', 'close') and iso is not None and self.n_locked(iso) == 0:
            self.holder[iso] = None
        self.ev('permit', work, action, person, 'done', [])

    def _lock(self, kind, work, point, person, vals):
        """A lock or unlock (§15.1), at the start of step 3."""
        w = self.works.get(work) if isinstance(work, str) else None
        iso = w.get('isolation') if w else None
        if iso is None or not (isinstance(point, int) and not isinstance(point, bool)
                               and 0 <= point < len(self.isos[iso]['points'])):
            self.ev(kind, work, point, person, 'unknown', [])
            return
        pt = self.isos[iso]['points'][point]
        key = (iso, point)
        why = []
        if person is not None:
            why.append('authority')
        if self.pstate[work] not in ((2, 3) if kind == 'lock' else (2, 3, 7, 10)) or self.holder[iso] != work:
            why.append('state')
        if kind == 'lock':
            if key in self.locks:
                why.append('locked')
            if 'safe' in pt and vals[self.ix[pt['safe']]] < 0.5:
                why.append(pt['safe'])
        elif key not in self.locks:
            why.append('unlocked')
        if why:
            self.ev(kind, work, point, person, 'refused', why)
            return
        if kind == 'lock':
            self.locks[key] = person
            self.code_locks[pt['kks']] = self.code_locks.get(pt['kks'], 0) + 1
        else:
            del self.locks[key]
            self.code_locks[pt['kks']] -= 1
        k = self.n_locked(iso)
        self.cur[self.ix[iso + '_locked']] = float(k)
        self.cur[self.ix[iso + '_complete']] = 1.0 if k == len(self.isos[iso]['points']) else 0.0
        if kind == 'unlock' and self.pstate[work] == 10 and k == 0:
            self.holder[iso] = None     # a cancelled work lets its isolation go with its last lock
        self.ev(kind, work, point, person, 'done', [])

    def _repair_under(self, fid, work, person):
        """The trainee's repair under a permit (§15.5), in step 1: True when it is noted for step 3."""
        w = self.works.get(work) if isinstance(work, str) else None
        f = self.faults.get(fid) if isinstance(fid, str) else None
        if w is None or f is None or 'repair' not in f or w.get('repairs') != fid:
            self.ev('repair', fid, work, person, 'unknown', [])
            return False
        why = []
        if person is not None:
            why.append('authority')     # no staff in the plant: free mode, person null (§17.1)
        if self.pstate[work] != 5:
            why.append('state')
        if why:
            self.ev('repair', fid, work, person, 'refused', why)
            return False
        return True

    def lock_effects(self, work, point, horizon=100):
        """What a lock would do (§15.6): the trips and priority 1 alarms that come within `horizon` steps with the lock
        made after the inputs already queued, and not without it."""
        a, b = self.clone(), self.clone()
        a.queue.append(('lock', work, point, None))
        na, nb = len(a.events), len(b.events)
        a.step(horizon)
        b.step(horizon)
        ea, eb = a.events[na:], b.events[nb:]
        lock = ([None] + [e[5] for e in ea if e[0] == self.step_no + 1 and e[1] in ('lock', 'unlock')])[-1]

        def tripped(evs):
            return {e[2] for e in evs if e[1] == 'trip'}

        def raised(evs):
            return {e[2] for e in evs if e[1] == 'alarm' and e[3] == 'active_unack'}
        ta, tb, ra, rb = tripped(ea), tripped(eb), raised(ea), raised(eb)
        return {'lock': lock, 'trips': [t['id'] for t in self.trips if t['id'] in ta and t['id'] not in tb],
                'alarms': [x['id'] for x in self.alarms if x['priority'] == 1 and x['id'] in ra and x['id'] not in rb]}

    def _enter(self, mc, to, cause):
        old = self.mstate[mc['id']]
        new = mc['_ids'].index(to)
        self.mstate[mc['id']] = new
        self.cur[self.ix[mc['id'] + '_state']] = float(new)
        self.ev('machine', mc['id'], mc['_ids'][old], to, cause)
        self._set(mc['states'][new].get('set', {}))

    def _actions(self, acts, moved):
        for a in acts:
            if 'set' in a:
                self._set(a['set'])
            else:
                mc = next(x for x in self.machines if x['id'] == a['machine'])
                self._enter(mc, a['to'], 'action')
                moved.add(mc['id'])

    def step(self, n=1):
        for _ in range(n):
            self._step()

    def _step(self):
        m = self.m
        self.step_no += 1
        prev = list(self.cur)
        self.prev = prev
        cur = self.cur
        moved = set()
        pressed = []
        asked = []
        under = {}          # fault -> the work under whose permit the trainee repairs it (§15.5)
        noted = []          # locks and unlocks, made in step 3 (§17.1)
        dones = []          # works whose permit went to done: their repairs and set in step 3
        # 1. the trainee's inputs, in the order made
        q, self.queue = self.queue, []
        for item in q:
            kind = item[0]
            if kind == 'op':
                self._op(item[1:], prev, moved)
            elif kind == 'permit':
                self._permit(item[1], item[2], item[3], dones)
            elif kind in ('lock', 'unlock'):
                noted.append(item)
            elif kind in ('ack', 'shelve', 'unshelve') and item[1] not in self.astate:
                continue        # an alarm the model doesn't have: nothing happens, no event (§7.10)
            elif kind == 'ack':
                a = item[1]
                if self.astate[a] == 'active_unack':
                    self.astate[a] = 'active_ack'
                    self.ev('alarm', a, 'active_ack')
                elif self.astate[a] == 'cleared_unack':
                    self.astate[a] = 'normal'
                    self.ev('alarm', a, 'normal')
            elif kind == 'shelve':
                if not (is_num(item[2]) and 0 < item[2] < 1e6):
                    continue    # a shelving time outside (0, 10⁶) s does nothing (§7.6)
                self.shelved[item[1]] = self.step_no + steps(item[2])
                self.ev('shelve', item[1], item[2])
            elif kind == 'unshelve':
                if self.shelved.pop(item[1], None) is not None:
                    self.ev('unshelve', item[1])
            elif kind == 'fault':
                pressed.append(item[1])
            elif kind == 'repair' and len(item) > 2:
                if self._repair_under(item[1], item[2], item[3]):
                    under[item[1]] = item[2]
            elif kind == 'repair':
                asked.append(item[1])
        # first-out records clear when no trip of the group is latched
        for g in list(self.first_out):
            if not any(self.latched[t['id']] for t in self.trips if t.get('first_out') == g):
                del self.first_out[g]
        # 2. values, in order
        for i, fn, stateful in self.prog:
            cur[i] = fn(cur, prev)
        vals = list(cur)          # conditions in steps 3–7 read the values as step 2 left them
        # 3. the locks and unlocks noted in step 1, in the order made; the permits' automatic moves (§15.3)
        for kind, work, point, person in noted:
            self._lock(kind, work, point, person, vals)
        for w in self.m.works:
            wid, iso = w['id'], w.get('isolation')
            k = self.n_locked(iso) if iso is not None else 0
            done = iso is None or k == len(self.isos[iso]['points'])
            st, new = self.pstate[wid], None
            if st == 2 and done:
                new = 3
            elif st == 3 and not done:
                new = 2
            elif st == 7 and k == 0:
                new = 8
            if new is not None:
                self.pstate[wid] = new
                cur[self.ix[wid + '_permit']] = float(new)
                self.ev('permit', wid, 'auto', None, 'done', [new])
        # then the faults
        for fid, f in self.faults.items():
            # applied once; a repaired trainer's fault can be pressed again (§7.8)
            if fid in self.faults_done and not (fid in self.faults_fixed and 'when' not in f):
                continue
            if 'when' in f:
                w = f['when']
                hit = vals[self.ix[w]] >= 0.5 if isinstance(w, str) else self.fault_cond[fid](vals, vals) >= 0.5
            else:
                hit = fid in pressed
            if hit and not self._blocked(f['set']):
                self.faults_done.add(fid)
                self.faults_fixed.discard(fid)
                self._set(f['set'])
                self.ev('fault', fid)
        # then the repairs asked, in the scenario's order: a fault applied and not repaired since, with a `repair`; one
        # under a permit (§15.5) writes as its work
        for fid, f in self.faults.items():
            wid = under.get(fid)
            if (fid in asked or wid is not None) and 'repair' in f and fid in self.faults_done \
                    and fid not in self.faults_fixed and not self._blocked(f['repair'], wid):
                self.faults_fixed.add(fid)
                self._set(f['repair'], wid)
                self.ev('repair', fid)
        # then the works whose permit went to done, in the order of their `done`: the fault they repair, their set
        for wid in dones:
            w = self.works[wid]
            fid = w.get('repairs')
            f = self.faults.get(fid)
            if f is not None and 'repair' in f and fid in self.faults_done and fid not in self.faults_fixed \
                    and not self._blocked(f['repair'], wid):
                self.faults_fixed.add(fid)
                self._set(f['repair'], wid)
                self.ev('repair', fid)
            self._set(w.get('set', {}), wid)
        # 4. interlocks on a rising edge
        for x in m.interlocks:
            now = vals[self.ix[x['when']]] >= 0.5
            if now and not self.il_prev[x['id']]:
                self.ev('interlock', x['id'])
                self._actions(x['do'], moved)
            self.il_prev[x['id']] = now
        # 5. machines: at most one move each, by the first true next
        for mc in self.machines:
            if mc['id'] in moved:
                continue
            st = mc['states'][self.mstate[mc['id']]]
            for c, to in st.get('next', []):
                if vals[self.ix[c]] >= 0.5:
                    self._enter(mc, to, 'next')
                    moved.add(mc['id'])
                    break
        # 6. trips
        for t in self.trips:
            tid = t['id']
            if self.latched[tid]:
                continue
            if vals[self.ix[t['when']]] >= 0.5:
                self.trip_count[tid] += 1
            else:
                self.trip_count[tid] = 0
            if self.trip_count[tid] >= max(1, steps(t.get('delay', 0))):
                self.latched[tid] = True
                cur[self.ix[tid + '_latched']] = 1.0
                g = t.get('first_out')
                # first out: no other trip of its group is latched (also one a scenario started latched, §7.5)
                first = bool(g) and not any(self.latched[x['id']] for x in self.trips
                                            if x.get('first_out') == g and x['id'] != tid)
                if first:
                    self.first_out[g] = tid
                self.ev('trip', tid, first)
                self._actions(t['do'], set())
        # 7. alarms
        for a in self.alarms:
            aid = a['id']
            sup = 'suppress' in a and vals[self.ix[a['suppress']]] >= 0.5 or bool(self.code_locks.get(a['kks']))
            if aid in self.shelved and self.shelved[aid] <= self.step_no:
                del self.shelved[aid]
                self.ev('unshelve', aid)
            if sup or aid in self.shelved:
                self.acount[aid] = 0
                continue
            on = vals[self.ix[a['when']]] >= 0.5
            self.acount[aid] = self.acount[aid] + 1 if on else 0
            active = self.acount[aid] >= max(1, steps(a.get('delay', 0)))
            clear = vals[self.ix[a['clear']]] >= 0.5 if 'clear' in a else not on
            s = self.astate[aid]
            new = s
            if s == 'normal' and active:
                new = 'active_unack'
            elif s == 'active_unack' and clear:
                new = 'cleared_unack'
            elif s == 'active_ack' and clear:
                new = 'normal'
            elif s == 'cleared_unack' and active:
                new = 'active_unack'
            if new != s:
                self.astate[aid] = new
                self.ev('alarm', aid, new)

    def _op(self, item, prev, moved):
        kks, do, value, trip = item
        o = self.m.op_keys.get((kks, do, trip))
        if o is None:
            self.ev('op', kks, do, 'unknown', [])
            return
        failed = [nd[0] for nd in o.get('needs', []) if prev[self.ix[nd[0]]] < 0.5]
        if 'machine' in o:
            mc = next(x for x in self.machines if x['id'] == o['machine'])
            spec = mc['commands'][do]
            here = mc['_ids'][self.mstate[mc['id']]]
            if spec['from'] != '*' and here not in spec['from']:
                failed.append(f'{mc["id"]}_state')
        if do == 'reset' and 'machine' not in o:
            t = next(x for x in self.trips if x['id'] == trip)
            if not self.latched[trip]:
                failed.append(f'{trip}_latched')
            elif prev[self.ix[t['when']]] >= 0.5:
                failed.append(t['when'])
        if do == 'set' and 'machine' not in o:
            if value is None or not (o['range'][0] <= value <= o['range'][1]):
                failed.append(o['input'])
        failed += [x + '_locked' for x in self.locking(kks)]       # a locked code refuses every op (§15.1)
        if failed:
            self.ev('op', kks, do, 'refused', failed)
            return
        self.ev('op', kks, do, 'done', [])
        if do == 'set' and 'machine' not in o:
            self._write(self.ix[o['input']], float(value))
        if do == 'reset' and 'machine' not in o:
            self.latched[trip] = False
            self.trip_count[trip] = 0
            self.cur[self.ix[trip + '_latched']] = 0.0
        self._set(o.get('set', {}))
        if 'machine' in o:
            mc = next(x for x in self.machines if x['id'] == o['machine'])
            self._enter(mc, mc['commands'][do]['to'], 'command')
            moved.add(mc['id'])

    # --- what the vectors compare (§12)
    def fast_forward(self):
        """§7.9: no unacknowledged alarm, no active priority 1 alarm, no machine in a watched state."""
        for a in self.alarms:
            s = self.astate[a['id']]
            if a['id'] in self.shelved:
                continue
            if s in ('active_unack', 'cleared_unack'):
                return False
            if a['priority'] == 1 and s in ('active_unack', 'active_ack'):
                return False
        for mc in self.machines:
            if mc['states'][self.mstate[mc['id']]].get('watch', True):
                return False
        return True

    def snapshot(self, values=True):
        s = {'step': self.step_no,
             'machines': {mc['id']: mc['_ids'][self.mstate[mc['id']]] for mc in self.machines},
             'tripped': sorted(t for t, v in self.latched.items() if v),
             'first_out': dict(sorted(self.first_out.items())),
             'alarms': {a: s for a, s in self.astate.items() if s != 'normal'},
             'shelved': sorted(self.shelved),
             'fast_forward': self.fast_forward()}
        if self.v2:
            s['permits'] = {w['id']: self.pstate[w['id']] for w in self.m.works if self.pstate[w['id']]}
            s['ptw'] = {w['id']: self.ptw[w['id']] for w in self.m.works if w['id'] in self.ptw}
            s['locked'] = [[x['id'], p] for x in self.m.isolations for p in range(len(x['points']))
                           if (x['id'], p) in self.locks]
        if values:
            s['values'] = {n: self.cur[i] for i, n in enumerate(self.names)}
        return s


# ---------------------------------------------------------------- procedures in the model alone (0054 §10)

class Recorder(Engine):
    """An engine that records every trainee input with the step it takes effect in (the vectors' `input`)."""

    def __init__(self, b, scenario):
        super().__init__(b, scenario)
        self.inputs = []

    def _q(self, item):
        self.inputs.append([self.step_no + 1] + list(item))
        self.queue.append(item)

    def op(self, kks, do, value=None, trip=None):
        self._q(('op', kks, do, value, trip))

    def ack(self, alarm):
        self._q(('ack', alarm))

    def shelve(self, alarm, seconds):
        self._q(('shelve', alarm, seconds))

    def unshelve(self, alarm):
        self._q(('unshelve', alarm))

    def fault(self, fid):
        self._q(('fault', fid))

    def repair(self, fid):
        self._q(('repair', fid))

    def repair_under(self, fid, work, person=None):
        self._q(('repair', fid, work, person))

    def permit(self, work, action, person=None):
        self._q(('permit', work, action, person))

    def lock(self, work, point, person=None):
        self._q(('lock', work, point, person))

    def unlock(self, work, point, person=None):
        self._q(('unlock', work, point, person))

    def clone(self):
        c = super().clone()
        c.inputs = list(self.inputs)
        return c


def run_procedure(b, pid, limit_s=3600, eng=None, until_step=None, on_step=None):
    """Runs a procedure as a trainee who does exactly what each step says: its ops at once (in order), then model
    steps until the step's `done` value is true (or one step when it has none). Returns (engine, log) where log
    lists (step id, model step at which it ended). Raises AssertionError when a step's op is refused or its `done`
    doesn't come within limit_s seconds of model time."""
    pr = b.procedures[pid]
    e = eng or Recorder(b, pr['scenario'])
    log = []
    for s in pr['steps']:
        if until_step is not None and s['id'] == until_step:
            break
        start = e.step_no
        n_ev = len(e.events)
        for d in s.get('do', []):
            e.op(d['kks'], d['do'], d.get('value'), d.get('trip'))
        e.step()
        refused = [ev for ev in e.events[n_ev:] if ev[1] == 'op' and ev[4] != 'done']
        assert not refused, f'step {s["id"]}: refused {refused}'
        if 'done' in s:
            while not e.truth(s['done']):
                assert e.step_no - start < limit_s * 10, f'step {s["id"]}: {s["done"]} not true after {limit_s} s'
                e.step()
        log.append((s['id'], e.step_no))
        if on_step:
            on_step(s['id'], e)
    return e, log


# ---------------------------------------------------------------- links into the plant (§6)

def decode(code, kks):
    """A code's decoding from the plant's tables (§6): each level's name, or None when its letters are not in the
    plant's key ("not in this plant's key")."""
    g = kks_parts(code)
    eq = None
    if g[4]:
        eq = kks['equipment'].get(g[4], kks['measurements'].get(g[4]))
    return {'unit': kks['units'].get(g[0]), 'system': kks['systems'].get(g[2]),
            'equipment': eq if g[4] else None}


def read_link(url, b):
    """What a link opens in Walkdown Plant (§6). Returns one of
        {'open': 'kks', 'code', 'match', 'decode'}   match: 'exact', 'without_a3' (the A3 letter dropped),
                                                       'same_kind' (same system and equipment letters),
                                                       'same_equipment' (same equipment letters), or
                                                       'decode' (no equipment of that kind: code is the one asked)
        {'open': 'procedure', 'id', 'step'}             step None for the first step
        {'open': 'start'}                               anything else: the app's start, with a short message
    `decode` is always the decoding of the code asked (after cutting it to the grammar)."""
    start = {'open': 'start'}
    if not isinstance(url, str) or not url.startswith('walkdown-plant://'):
        return start
    path = url[len('walkdown-plant://'):].split('/')
    if len(path) == 2 and path[0] == 'kks' and LINK_CODE.fullmatch(path[1]):
        raw = path[1]
        asked = next((raw[:n] for n in range(len(raw), 0, -1) if KKS_RE.fullmatch(raw[:n])), None)
        if asked is None:
            return start
        codes = b.model.p.codes
        out = {'open': 'kks', 'code': asked, 'match': 'exact', 'decode': decode(asked, b.plant['kks'])}
        if asked in codes:
            return out
        g = kks_parts(asked)
        if g[6] and asked[:-1] in codes:
            return dict(out, code=asked[:-1], match='without_a3')
        # a code the plant doesn't have: the lowest code (in code order) of the same kind
        same = sorted(c for c in codes if kks_parts(c)[2] == g[2] and kks_parts(c)[4] == g[4])
        if same:
            return dict(out, code=same[0], match='same_kind')
        if g[4]:
            same = sorted(c for c in codes if kks_parts(c)[4] == g[4])
            if same:
                return dict(out, code=same[0], match='same_equipment')
        return dict(out, match='decode')
    if len(path) in (2, 3) and path[0] == 'procedure' and path[1] in b.procedures:
        steps = [s['id'] for s in b.procedures[path[1]]['steps']]
        if len(path) == 2:
            return {'open': 'procedure', 'id': path[1], 'step': None}
        if path[2] in steps:
            return {'open': 'procedure', 'id': path[1], 'step': path[2]}
    return start
