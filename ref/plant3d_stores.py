"""The stores (docs/plant3d/REALISM.md §7.2 and §2.23, milestone WM2): stores.json (the stores and the parts' catalogue),
the values <part>_stock and <part>_due, a scenario's `stock`, the inputs [n, "issue", part, qty, work, person] and
[n, "order", part, qty, person], the deliveries of step 3, the fitting check of a hand action naming a `part`, each
work's issued parts, and the snapshot's and the digest's parts. The jump to a date and §7.4's rule for it are in
ref/plant3d_staff.py (StaffRun.jump); the NPCs' issue and order steps there too. The app's engine follows this bit for
bit (apps/plant3d/sim/, ported after it): every rule below names its §."""
import re

from ref.courses import need, keys, is_num, num, ident, lst

FORMAT = 'walkdown-plant-stores'
LIMITS = {'stores': 8, 'parts': 512, 'id': 22, 'number': 40, 'class': 40, 'title': 120, 'level': 9999,
          'lead_days': 365, 'looks_like': 8, 'differs': 200, 'qty': 9999, 'pending': 8, 'jump_days': 30}
# §2.23: the generic catalogue number of §6.2: WDP- and capitals or digits in groups joined by single hyphens
NUMBER = re.compile(r'WDP(-[A-Z0-9]+)+\Z')
DAY = 864000            # a clock day in tenths of a clock second (§16.1)
WO_OPEN = (2, 3, 4)     # §2.23: parts are issued against a work order planned, scheduled or in progress ([Palmer])
# the order of an issue's reasons (§2.23), every one that applies
ISSUE_REASONS = ('authority', 'where', 'storekeeper', 'qty', 'stock', 'work')
ORDER_REASONS = ('authority', 'qty', 'pending')


def _text(x, where, hi):
    need(isinstance(x, str) and 1 <= len(x) <= hi, 'bad_type', f'{where}: text of 1 to {hi} characters')


def _level(x, where):
    """A stock level of the file: a whole number from 0 to 9,999 (§2.23)."""
    num(x, where, 0, LIMITS['level'], integer=True)
    return int(x)


def check(d, b):
    """stores.json (§2.23), its own rules; the stores' places are checked against the staff by check_places. Returns
    what the engine reads: {'stores', 'store_ix', 'parts', 'ix', 'looked_by'}."""
    w0 = 'stores.json'
    need(b.version == 2, 'unknown_key', f'{w0}: only in a version 2 plant (REALISM.md §2.23)')
    keys(d, ('format', 'version', 'stores', 'parts'), (), w0)
    need(d['format'] == FORMAT, 'bad_format', f'{w0}: format must be "{FORMAT}"')
    need(d['version'] == 1 and not isinstance(d['version'], bool), 'bad_version', f'{w0}: version must be 1')
    store_ix = {}
    for i, s in enumerate(lst(d['stores'], f'{w0}.stores', 1, LIMITS['stores'])):
        ws = f'{w0}.stores[{i}]'
        keys(s, ('id', 'title', 'place', 'self_service'), (), ws)
        ident(s['id'], f'{ws}.id')
        need(len(s['id']) <= LIMITS['id'], 'bad_id', f'{ws}.id: at most {LIMITS["id"]} characters')
        need(s['id'] not in store_ix, 'dup_id', f'{ws}: store {s["id"]} twice')
        _text(s['title'], f'{ws}.title', LIMITS['title'])
        ident(s['place'], f'{ws}.place')
        need(isinstance(s['self_service'], bool), 'bad_type', f'{ws}.self_service: true or false')
        store_ix[s['id']] = i
    ext = set(b.plant.get('ext', ()))
    ix, numbers = {}, set()
    parts = lst(d['parts'], f'{w0}.parts', 1, LIMITS['parts'])
    for i, p in enumerate(parts):
        wp = f'{w0}.parts[{i}]'
        keys(p, ('id', 'number', 'title', 'class', 'store', 'stock', 'min', 'reorder', 'max', 'lead_days'),
             ('looks_like',), wp)
        ident(p['id'], f'{wp}.id')
        need(len(p['id']) <= LIMITS['id'], 'bad_id', f'{wp}.id: at most {LIMITS["id"]} characters')
        need(p['id'] not in ix, 'dup_id', f'{wp}: part {p["id"]} twice')
        for v in (p['id'] + '_stock', p['id'] + '_due'):
            need(v not in ext, 'dup_id', f'{wp}: {v} is already an ext value (REALISM.md §2.23)')
        need(isinstance(p['number'], str) and len(p['number']) <= LIMITS['number']
             and NUMBER.match(p['number']) is not None, 'bad_value',
             f'{wp}.number: a catalogue number WDP-… of at most {LIMITS["number"]} characters (REALISM.md §6.2)')
        need(p['number'] not in numbers, 'dup_id', f'{wp}.number: {p["number"]} twice')
        numbers.add(p['number'])
        _text(p['title'], f'{wp}.title', LIMITS['title'])
        _text(p['class'], f'{wp}.class', LIMITS['class'])
        need(isinstance(p['store'], str) and p['store'] in store_ix, 'bad_ref', f'{wp}.store: no store {p["store"]!r}')
        lv = [_level(p[k], f'{wp}.{k}') for k in ('stock', 'min', 'reorder', 'max')]
        need(lv[1] <= lv[2] < lv[3], 'bad_number', f'{wp}: 0 ≤ min ≤ reorder < max ≤ 9,999')
        need(lv[0] <= lv[3], 'bad_number', f'{wp}.stock: at most max')
        num(p['lead_days'], f'{wp}.lead_days', 1, LIMITS['lead_days'], integer=True)
        ix[p['id']] = i
    looked_by = {p['id']: [] for p in parts}      # part -> the parts that list it in looks_like, in file order
    for i, p in enumerate(parts):
        if 'looks_like' not in p:
            continue
        wl = f'{w0}.parts[{i}].looks_like'
        seen = []
        for j, x in enumerate(lst(p['looks_like'], wl, 1, LIMITS['looks_like'])):
            wx = f'{wl}[{j}]'
            keys(x, ('part', 'differs'), (), wx)
            need(isinstance(x['part'], str) and x['part'] in ix, 'bad_ref', f'{wx}.part: no part {x["part"]!r}')
            need(x['part'] != p['id'], 'bad_ref', f'{wx}.part: not the part itself')
            need(x['part'] not in seen, 'dup_id', f'{wx}.part: {x["part"]} twice')
            seen.append(x['part'])
            _text(x['differs'], f'{wx}.differs', LIMITS['differs'])
            looked_by[x['part']].append(p['id'])
    return {'stores': d['stores'], 'store_ix': store_ix, 'parts': parts, 'ix': ix, 'looked_by': looked_by}


def part_ids(stores):
    return [p['id'] for p in stores['parts']] if stores is not None else []


def kept(stores):
    """The engine-kept values (§2.23), after the work orders': per part in the file's order, <part>_stock then
    <part>_due."""
    return [p + s for p in part_ids(stores) for s in ('_stock', '_due')]


def check_places(b):
    """With staff (§2.23): each store's place is a staff place."""
    if b.stores is None or b.staff is None:
        return
    for i, s in enumerate(b.stores['stores']):
        b.staff.place_ref(s['place'], f'stores.json.stores[{i}].place')


def check_scenario(s, b, rel):
    """A scenario's `stock` (§2.23): {part: a whole number from 0 to the part's max}."""
    if 'stock' not in s:
        return
    st = b.stores
    need(st is not None, 'bad_ref', f'{rel}.stock: the plant has no stores.json (REALISM.md §2.23)')
    need(isinstance(s['stock'], dict), 'bad_type', f'{rel}.stock: an object of parts and counts')
    for k, v in s['stock'].items():
        need(k in st['ix'], 'bad_ref', f'{rel}.stock.{k}: no part {k!r} in stores.json')
        num(v, f'{rel}.stock.{k}', 0, st['parts'][st['ix'][k]]['max'], integer=True)


def check_hand_part(m, x, w):
    """A hand action's `part` (§2.23): a part of stores.json."""
    st = getattr(m.b, 'stores', None)
    need(st is not None, 'bad_ref', f'{w}.part: the plant has no stores.json (REALISM.md §2.23)')
    need(isinstance(x['part'], str) and x['part'] in st['ix'], 'bad_ref', f'{w}.part: no part {x["part"]!r} in '
                                                                           f'stores.json')


# ---------------------------------------------------------------- the engine's part

def init(e, b, sc):
    """The stores' state of a fresh engine (only in a plant with stores.json): the shelf per part (the file's stock,
    or the scenario's `stock`), on order per part, the purchase order counter, the pending orders and each work's
    issued parts."""
    st = e.stores = getattr(b, 'stores', None)
    if st is None:
        return
    given = sc.get('stock', {})
    e.stock = [int(given.get(p['id'], p['stock'])) for p in st['parts']]
    e.due = [0] * len(st['parts'])
    e.po_count = 0
    # pending orders in the order made: [number, part, qty, by, ordered clock, due clock]
    e.orders = []
    # work -> {part: count} of the parts issued against it and not yet fitted (§2.23)
    e.issued = {}


def step0(e):
    """Step 0's slots of the stores' values (§2.23)."""
    for k, p in enumerate(e.stores['parts']):
        _write(e, k, p['id'])


def _write(e, k, part):
    e.cur[e.ix[part + '_stock']] = float(e.stock[k])
    e.cur[e.ix[part + '_due']] = float(e.due[k])


def copy_state(c, e):
    if e.stores is None:
        return
    c.stock = list(e.stock)
    c.due = list(e.due)
    c.orders = [list(o) for o in e.orders]
    c.issued = {w: dict(v) for w, v in e.issued.items()}


def _qty_ok(q):
    """§2.23: a whole number from 1 to 9,999 (3 or 3.0; not a boolean)."""
    return is_num(q) and float(q).is_integer() and 1 <= q <= LIMITS['qty']


def keeper_at(e, place):
    """§2.23: someone on duty at the place whose role holds issue_parts (the person themself counts)."""
    sr = e.staff
    for p in sr.people:
        if p.on and p.pos == place and 'issue_parts' in sr.st.roles[p.role]['authority']:
            return True
    return False


def issue(e, item, npc=False):
    """[n, "issue", part, qty, work, person] in step 1 (§2.23); returns 'done', 'refused' or 'unknown', its event
    [n, "issue", part, qty, work, person, result, [reasons]] made at once."""
    from ref.plant3d_hands import person_of
    part, qty, work, person = (list(item) + [None] * 4)[1:5]
    st = e.stores
    if not (st is not None and isinstance(part, str) and part in st['ix'] and isinstance(work, str)
            and work in e.works):
        e.ev('issue', part, qty, work, person, 'unknown', [])
        return 'unknown'
    k = st['ix'][part]
    store = st['stores'][st['store_ix'][st['parts'][k]['store']]]
    why = []
    if e._authority(person, npc, None):         # the person check every input has (§17.1)
        why.append('authority')
    sr = e.staff
    if sr is not None and person is not None:   # (free mode, person null: neither where nor storekeeper)
        place = sr.st.pix[store['place']]
        p = person_of(e, person)
        if p is not None and p.pos != place:
            why.append('where')
        if not store['self_service'] and not keeper_at(e, place):
            why.append('storekeeper')
    if not _qty_ok(qty):
        why.append('qty')
    elif qty > e.stock[k]:                      # (only for a quantity that is one)
        why.append('stock')
    if e.wo_ids is not None and e.wo[work] not in WO_OPEN:
        why.append('work')
    if why:
        e.ev('issue', part, qty, work, person, 'refused', why)
        return 'refused'
    q = int(qty)
    e.stock[k] -= q
    _write(e, k, part)
    held = e.issued.setdefault(work, {})
    held[part] = held.get(part, 0) + q
    e.ev('issue', part, qty, work, person, 'done', [])
    return 'done'


def order_qty(e, part):
    """An NPC's order step without a qty (§2.23): up to the part's max, max - stock - due, when the input is made."""
    st = e.stores
    k = st['ix'][part]
    return st['parts'][k]['max'] - e.stock[k] - e.due[k]


def order(e, item, npc=False):
    """[n, "order", part, qty, person] in step 1 (§2.23); its event [n, "order", part, qty, person, result,
    [reasons], number] at once (number null unless done)."""
    part, qty, person = (list(item) + [None] * 3)[1:4]
    st = e.stores
    if not (st is not None and isinstance(part, str) and part in st['ix']):
        e.ev('order', part, qty, person, 'unknown', [], None)
        return 'unknown'
    if npc and qty is None:
        qty = order_qty(e, part)
    k = st['ix'][part]
    why = []
    if e._authority(person, npc, 'order_parts'):
        why.append('authority')
    if not _qty_ok(qty):
        why.append('qty')
    if sum(1 for o in e.orders if o[1] == part) >= LIMITS['pending']:
        why.append('pending')
    if why:
        e.ev('order', part, qty, person, 'refused', why, None)
        return 'refused'
    q = int(qty)
    e.po_count += 1
    no = f'PO-{e.po_count:04d}'
    c = e.clock()
    e.orders.append([no, part, q, person, c, c + st['parts'][k]['lead_days'] * DAY])
    e.due[k] += q
    _write(e, k, part)
    e.ev('order', part, qty, person, 'done', [], no)
    return 'done'


def deliveries(e):
    """Step 3, after the hand actions whose minutes end (§2.7, §2.23): every pending order whose due clock is reached,
    in the order made: the shelf up by its qty, on order down by it, the event [n, "delivery", number, part, qty]."""
    if not e.orders:
        return
    c = e.clock()
    keep = []
    for o in e.orders:
        if c >= o[5]:
            k = e.stores['ix'][o[1]]
            e.stock[k] += o[2]
            e.due[k] -= o[2]
            _write(e, k, o[1])
            e.ev('delivery', o[0], o[1], o[2])
        else:
            keep.append(o)
    e.orders = keep


# ---------------------------------------------------------------- fitting a part (§2.23, the look-alike's lesson)

def fit_work(e, kks):
    """The work a fitting is made under: the first work on the code, in model order, whose permit is accepted."""
    for w in e.works_on.get(kks, ()):
        if e.pstate[w['id']] == 5:
            return w['id']
    return None


def fit_reasons(e, x):
    """After `value` (§2.23): `part` when that work holds none of the action's part (or there is no such work);
    `wrong_part` instead when it holds none but holds a part that lists it in `looks_like`; else nothing."""
    part = x['part']
    w = fit_work(e, x['kks'])
    held = e.issued.get(w, {}) if w is not None else {}
    if held.get(part, 0) >= 1:
        return []
    if any(held.get(q, 0) >= 1 for q in e.stores['looked_by'][part]):
        return ['wrong_part']
    return ['part']


def fit_take(e, x):
    """The part taken from the work's issued parts when the action starts (or is done at once): returns the work."""
    w = fit_work(e, x['kks'])
    held = e.issued[w]
    held[x['part']] -= 1
    if not held[x['part']]:
        del held[x['part']]
        if not held:
            del e.issued[w]
    return w


def fit_back(e, work, part):
    """An abandoned fitting gives its part back to the work it was taken from (§2.23)."""
    held = e.issued.setdefault(work, {})
    held[part] = held.get(part, 0) + 1


# ---------------------------------------------------------------- the snapshot's and the digest's parts (§2.23)

def _issued_of(e, wid):
    held = e.issued.get(wid, {})
    return [(p['id'], held[p['id']]) for p in e.stores['parts'] if p['id'] in held]


def snapshot_part(e, s):
    st = e.stores
    s['stores'] = {'po': e.po_count,
                   'stock': {p['id']: e.stock[k] for k, p in enumerate(st['parts'])},
                   'due': {p['id']: e.due[k] for k, p in enumerate(st['parts']) if e.due[k]},
                   'orders': [list(o) for o in e.orders],
                   'issued': {w['id']: dict(_issued_of(e, w['id'])) for w in e.m.works if w['id'] in e.issued}}


def digest_part(e):
    """The digest's stores part (§2.23), after the work orders': [the PO counter, the stock per part, on order per
    part (the file's order), the pending orders [number, part, qty, by, ordered, due] in the order made, per work in
    model order the issued parts as (part index, count) pairs in the file's order]."""
    from ref.godot_variant import Packed, PACKED_INT64
    st = e.stores
    return [e.po_count, Packed(PACKED_INT64, e.stock), Packed(PACKED_INT64, e.due),
            [list(o) for o in e.orders],
            [Packed(PACKED_INT64, [v for part, n in _issued_of(e, w['id']) for v in (st['ix'][part], n)])
             for w in e.m.works]]
