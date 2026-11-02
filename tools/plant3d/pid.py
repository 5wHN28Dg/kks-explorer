#!/usr/bin/env python3
"""The generic plant's P&IDs (docs/plant3d/REALISM.md §6.1, §6.1.1; milestone DC1), made from the content alone: every
equipment item, valve, instrument and pipe of the process areas with its code, drawn with the symbols of ISO 10628-2
and ISA-5.1 (pid_symbols.py) in our own single-stroke lettering (pid_font.py). Nothing comes from any real plant's
drawings. The sheets are a view of the content (the app's, never the engine's): made at every build of the app, not
committed.

    python3 tools/plant3d/pid.py OUT_DIR        # writes index.json and a file per sheet (apps/plant3d/build.sh)
    python3 tools/plant3d/pid.py --check        # makes them and runs the checks only

Format `walkdown-plant-drawing` version 1 (REALISM.md §6.1.1): sheet millimetres, y down."""
import heapq, json, math, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import pid_font as F           # noqa: E402
import pid_symbols as S        # noqa: E402

DATA = os.path.join(ROOT, 'data', 'plant3d')
SHEET_W, SHEET_H = 841.0, 594.0        # A1 landscape
FRAME = (20.0, 10.0, 831.0, 584.0)     # ISO 5457: a 20 mm filing margin on the left, 10 mm elsewhere
TITLE = (646.0, 529.0, 831.0, 584.0)   # the title block (ISO 7200)
REVS = (646.0, 499.0, 831.0, 529.0)    # the revision table above it
LAYOUT = (80.0, 36.0, 772.0, 494.0)    # where equipment goes
CONN_L = 26.0                          # the left margin column's left edge: ends coming in
CONN_R = 825.0                         # the right margin column's right edge: ends going out
G = 2.5                                # the routing grid
TAG_H, NAME_H, CODE_H = 2.5, 2.5, 3.5
FAN = 8.0                              # from a symbol's edge to its nearest row of parts

# The sheets, in order (REALISM.md §6.1.1): a sheet takes the items of its areas, or of its areas' listed systems.
SHEETS = [
    {'id': 'legend', 'title': 'Legend and symbols'},
    {'id': 'gt1', 'title': 'Gas turbine 1: fuel gas, lube oil and generator', 'areas': ('gt1',)},
    {'id': 'hrsg1', 'title': 'HRSG 1: feedwater, drums and steam', 'areas': ('hrsg1',)},
    {'id': 'st', 'title': 'Steam turbine, condenser and condensate', 'areas': ('st',)},
    {'id': 'cw', 'title': 'Circulating water and cooling tower', 'areas': ('cw', 'ct')},
    {'id': 'bop', 'title': 'Auxiliary boiler, instrument air, demineralised and closed cooling water', 'areas': ('bop',)},
    {'id': 'intake', 'title': 'Raw water intake', 'areas': ('intake',)},
    {'id': 'wtp1', 'title': 'Water treatment: pretreatment and filtered water', 'areas': ('wtp',),
     'systems': ('GBD', 'GBB', 'GBR', 'GBL', 'GHA', 'GHB')},
    {'id': 'wtp2', 'title': 'Water treatment: reverse osmosis and demineralisation', 'areas': ('wtp',),
     'systems': ('GCB', 'GCH', 'GCK', 'GCF', 'GCL', 'GHC', 'QUG')},
    {'id': 'wtp3', 'title': 'Water treatment: chemicals, sludge and waste water', 'areas': ('wtp',),
     'systems': ('GBN', 'GCN', 'GCE', 'GCP', 'GNR', 'GBS')},
]
REV0 = ['0', 'First issue, generated from the content']


class LayoutError(Exception):
    pass


def number(i):
    return 'WDP-PID-%03d' % (i + 1)


# ================================================================ the content

class Item:
    def __init__(self, code, name, part, area, role, raw, parent=None, pipe=None):
        self.code, self.name, self.part, self.area, self.role, self.raw = code, name, part, area, role, raw
        self.parent, self.pipe = parent, pipe
        self.kind = S.kind_of(code, part)
        self.at = raw.get('at')


def load(data=DATA):
    """(plant.json, {area id: area}, model codes) from a content directory."""
    with open(os.path.join(data, 'plant.json'), encoding='utf-8') as f:
        plant = json.load(f)
    areas = {}
    for aid in plant['areas']:
        with open(os.path.join(data, 'areas', aid + '.json'), encoding='utf-8') as f:
            areas[aid] = json.load(f)
    codes = set()
    mdir = os.path.join(data, 'model')
    for n in sorted(os.listdir(mdir)) if os.path.isdir(mdir) else []:
        with open(os.path.join(mdir, n), encoding='utf-8') as f:
            _codes_in(json.load(f), codes)
    return plant, areas, codes


def _codes_in(x, out):
    if isinstance(x, dict):
        for k, v in x.items():
            if k == 'kks' and isinstance(v, str):
                out.add(v)
            else:
                _codes_in(v, out)
    elif isinstance(x, list):
        for v in x:
            _codes_in(v, out)


def items_of(areas):
    """Every equipment item, part, pipe and inline item of the areas: {code: Item}."""
    out = {}
    for aid, a in areas.items():
        for e in a.get('equipment', []):
            eq = out[e['kks']] = Item(e['kks'], e.get('name', ''), e['part'], aid, 'equipment', e)
            for c in e.get('parts', []):
                out[c['kks']] = Item(c['kks'], c.get('name', ''), c['part'], aid, 'part', c, parent=eq.code)
        for p in a.get('pipes', []):
            out[p['kks']] = Item(p['kks'], p.get('name', ''), 'pipe', aid, 'pipe', p)
            for kind in ('valves', 'parts'):
                for v in p.get(kind, []):
                    out[v['kks']] = Item(v['kks'], v.get('name', ''), v['part'], aid, 'inline', v, pipe=p['kks'])
    return out


def drawn(it, items):
    """Whether a P&ID shows the item (REALISM.md §6.1.1: not electrical equipment, control desks or lifting gear)."""
    if it.role == 'pipe':
        return True
    if it.kind in S.NOT_DRAWN:
        return False
    if it.parent is not None:
        return drawn(items[it.parent], items)
    return True


def sheet_of_item(it, items):
    """The sheet an item is drawn on (its home): a part goes with its equipment, an inline item with its pipe."""
    if it.parent is not None:
        return sheet_of_item(items[it.parent], items)
    if it.pipe is not None:
        return sheet_of_item(items[it.pipe], items)
    for s in SHEETS[1:]:
        if it.area in s['areas'] and ('systems' not in s or it.code[2:5] in s['systems']):
            return s['id']
    return None


# ================================================================ the sheet's primitives

def r2(v):
    return round(v + 0.0, 2) + 0.0


def text_box(x, y, h, t, angle, align):
    w = F.width(t, h)
    x0 = -(0.0, w / 2, w)[align]
    if angle == 0:
        return (x + x0, y - h, x + x0 + w, y + h * 0.17)
    return (x - h, y - (x0 + w), x + h * 0.17, y - x0)


class Sheet:
    def __init__(self, sid, num, title):
        self.id, self.number, self.title = sid, num, title
        self.lines, self.circles, self.fills, self.texts = [], [], [], []
        self.spots, self.links, self.revisions, self.clouds = [], [], [], []
        self.symbols = []          # (box, owner): symbols must not overlap each other
        self.inside = {}           # a code drawn inside another's symbol (an HRSG's heating surfaces) -> that code

    def line(self, pts, w, dash, owner):
        if len(pts) >= 2:
            self.lines.append((w, dash, [tuple(p) for p in pts], owner))

    def circle(self, x, y, r, w, owner):
        self.circles.append((w, x, y, r, owner))

    def fill(self, pts, owner):
        self.fills.append(([tuple(p) for p in pts], owner))

    def text(self, x, y, h, t, angle, align, owner):
        t = t.upper()
        bad = F.check(t)
        if bad:
            raise LayoutError(f'{self.id}: no glyph for {bad!r} in {t!r}')
        self.texts.append((x, y, h, angle, align, t, owner))

    def spot(self, code, box, home):
        self.spots.append((code, box, home))

    def data(self):
        return {
            'format': 'walkdown-plant-drawing', 'version': 1, 'id': self.id, 'number': self.number,
            'title': self.title, 'size': [SHEET_W, SHEET_H],
            'revisions': [list(r) for r in self.revisions],
            'lines': [[r2(w), r2(d), [r2(v) for p in pts for v in p]] for w, d, pts, _ in self.lines],
            'circles': [[r2(w), r2(x), r2(y), r2(r)] for w, x, y, r, _ in self.circles],
            'fills': [[r2(v) for p in pts for v in p] for pts, _ in self.fills],
            'texts': [[r2(x), r2(y), r2(h), a, al, t] for x, y, h, a, al, t, _ in self.texts],
            'spots': [[c, r2(b[0]), r2(b[1]), r2(b[2]), r2(b[3]), 1 if home else 0] for c, b, home in self.spots],
            'links': [[s, c, r2(b[0]), r2(b[1]), r2(b[2]), r2(b[3])] for s, c, b in self.links],
            'clouds': [[rv, r2(b[0]), r2(b[1]), r2(b[2]), r2(b[3])] for rv, b in self.clouds],
        }


def inflate(b, m):
    return (b[0] - m, b[1] - m, b[2] + m, b[3] + m)


def overlap(a, b):
    return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]


def union(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


# ================================================================ the routing grid

DX, DY = (1, 0, -1, 0), (0, 1, 0, -1)      # directions: +x, +y, -x, -y
H_RUN, V_RUN, NODE = 1, 2, 4


class Grid:
    def __init__(self):
        self.nx, self.ny = int(SHEET_W / G) + 1, int(SHEET_H / G) + 1
        self.blocked = bytearray(self.nx * self.ny)
        self.use = bytearray(self.nx * self.ny)
        self.run_of = {}           # cell -> the pipe running through it

    def cell(self, x, y):
        return int(round(x / G)), int(round(y / G))

    def at(self, i, j):
        return i * G, j * G

    def block(self, box, m=1.25):
        x0, y0, x1, y1 = inflate(box, m)
        for j in range(max(0, math.ceil(y0 / G)), min(self.ny - 1, math.floor(y1 / G)) + 1):
            for i in range(max(0, math.ceil(x0 / G)), min(self.nx - 1, math.floor(x1 / G)) + 1):
                self.blocked[j * self.nx + i] = 1

    def unblock(self, i, j):
        self.blocked[j * self.nx + i] = 0

    def block_segment(self, a, b, m=0.6):
        self.block((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])), m)

    def free_box(self, box, own=frozenset(), m=0.0):
        """No obstacle and no other pipe within the box (cells of `own` may be used)."""
        x0, y0, x1, y1 = inflate(box, m)
        for j in range(max(0, math.ceil(y0 / G)), min(self.ny - 1, math.floor(y1 / G)) + 1):
            for i in range(max(0, math.ceil(x0 / G)), min(self.nx - 1, math.floor(x1 / G)) + 1):
                k = j * self.nx + i
                if self.blocked[k] or (self.use[k] and k not in own):
                    return False
        return True

    def route(self, starts, goals, window=None):
        """The cheapest orthogonal path from a start (cell, direction leaving it) to a goal (cell: the directions it
        may be entered in), round obstacles, never along another pipe, crossing others only straight across.
        Returns [(cell index, direction)] or None."""
        nx, ny = self.nx, self.ny
        blocked, use = self.blocked, self.use
        BEND, CROSS, NEAR = 6.0, 14.0, 2.5
        gi = [(k % nx, k // nx) for k in goals]
        if window is None:
            xs = [k % nx for k, _ in starts] + [g[0] for g in gi]
            ys = [k // nx for k, _ in starts] + [g[1] for g in gi]
            window = (max(0, min(xs) - 40), max(0, min(ys) - 40), min(nx - 1, max(xs) + 40), min(ny - 1, max(ys) + 40))
        wx0, wy0, wx1, wy1 = window
        gx0, gy0 = min(g[0] for g in gi), min(g[1] for g in gi)
        gx1, gy1 = max(g[0] for g in gi), max(g[1] for g in gi)

        def h(i, j):
            return (gx0 - i if i < gx0 else i - gx1 if i > gx1 else 0) + (gy0 - j if j < gy0 else j - gy1 if j > gy1 else 0)

        best = {}
        came = {}
        pq = []
        for k, d in starts:
            s = k * 4 + d
            best[s] = 0.0
            came[s] = None
            heapq.heappush(pq, (h(k % nx, k // nx), 0.0, s))
        while pq:
            f, g, s = heapq.heappop(pq)
            if g > best.get(s, 1e18):
                continue
            k, d = divmod(s, 4)
            if k in goals and d in goals[k]:
                out = []
                while s is not None:
                    out.append(divmod(s, 4))
                    s = came[s]
                return out[::-1]
            i, j = k % nx, k // nx
            for nd in (d, (d + 1) % 4, (d + 3) % 4):
                if nd != d and use[k]:
                    continue                     # no bend in a cell another pipe uses
                ni, nj = i + DX[nd], j + DY[nd]
                if ni < wx0 or ni > wx1 or nj < wy0 or nj > wy1:
                    continue
                n = nj * nx + ni
                if blocked[n] and n not in goals:
                    continue
                u = use[n]
                horiz = nd % 2 == 0
                if u & NODE or (horiz and u & H_RUN) or (not horiz and u & V_RUN):
                    continue
                c = g + 1.0 + (BEND if nd != d else 0.0)
                if u:
                    c += CROSS
                if horiz:
                    if (nj > 0 and use[n - nx] & H_RUN) or (nj < ny - 1 and use[n + nx] & H_RUN):
                        c += NEAR
                else:
                    if (ni > 0 and use[n - 1] & V_RUN) or (ni < nx - 1 and use[n + 1] & V_RUN):
                        c += NEAR
                ns = n * 4 + nd
                if c < best.get(ns, 1e18):
                    best[ns] = c
                    came[ns] = s
                    heapq.heappush(pq, (c + h(ni, nj), c, ns))
        return None


# ================================================================ blocks: an equipment symbol with its parts and label

def wrap(text, n):
    words, lines, cur = text.split(), [], ''
    for w in words:
        if cur and len(cur) + 1 + len(w) > n:
            lines.append(cur)
            cur = w
        else:
            cur = (cur + ' ' + w) if cur else w
    if cur:
        lines.append(cur)
    return lines or ['']


def sat_size(it):
    """A part's drawing beside its equipment: (width, height, kind) where kind is 'bubble', 'valve' or 'equipment'."""
    if it.kind in S.INSTRUMENTS:
        w, h = S.bubble_size(it.code)
        return w, h, 'bubble'
    tw = F.width(it.code, 2.0)
    if it.kind in S.VALVES:
        up, down = S.VALVE_REACH.get(it.kind, (2.5, 2.5))
        return max(S.VALVE_L, tw), up + down + 3.0, 'valve'
    if it.kind in S.EQUIPMENT:
        _, w, h = S.EQUIPMENT[it.kind]
        return max(w, tw), h + 3.0, 'equipment'
    raise LayoutError(f'{it.code}: no symbol for part kind {it.kind!r}')


class Block:
    """One equipment item drawn as a unit: its symbol, its parts in rows above (instruments) and below (the rest), the
    heating surfaces it contains (an HRSG's), and its code and name under it."""

    def __init__(self, eq, parts, inside, items):
        self.eq, self.parts, self.inside = eq, parts, inside
        self.code = eq.code
        if eq.kind not in S.EQUIPMENT:
            raise LayoutError(f'{eq.code}: no symbol for part kind {eq.kind!r}')
        fn, w, h = S.EQUIPMENT[eq.kind]
        if eq.kind == 'hrsg':
            w = 24.0 + 16.0 * max(1, len(inside))
        self.sw, self.sh = float(w), float(h)
        self.top = [p for p in parts if p.kind in S.INSTRUMENTS]
        self.bottom = [p for p in parts if p.kind not in S.INSTRUMENTS]
        self.label = [eq.code] + wrap(eq.name.upper(), 24)
        self._measure()
        self.x = self.y = 0.0          # the symbol's centre once placed
        self.ports = {'L': [], 'R': []}

    def _rows(self, sats):
        if not sats:
            return [], 0.0, 0.0, 0.0
        sizes = [sat_size(s) for s in sats]
        pitch = max(s[0] for s in sizes) + 4.0
        rh = max(s[1] for s in sizes)
        per = len(sats) if len(sats) <= 4 else math.ceil(len(sats) / 2)
        rows = [sats[:per], sats[per:]] if len(sats) > per else [sats]
        width = per * pitch + (pitch / 2 if len(rows) > 1 else 0) - 4.0
        return rows, pitch, rh, width

    def _measure(self):
        self.trows, self.tpitch, self.trh, tw = self._rows(self.top)
        self.brows, self.bpitch, self.brh, bw = self._rows(self.bottom)
        lw = max(F.width(self.label[0], CODE_H), max(F.width(t, NAME_H) for t in self.label[1:]))
        self.w = max(self.sw, tw, bw, lw) + 2.0
        self.up = self.sh / 2 + (len(self.trows) * (self.trh + 3.0) + FAN if self.trows else 0.0)
        self.down = self.sh / 2 + (len(self.brows) * (self.brh + 3.0) + FAN if self.brows else 0.0) + \
            3.0 + CODE_H + 1.0 + (len(self.label) - 1) * (NAME_H + 1.2)
        if self.eq.kind == 'hrsg':
            self.up += 4.0

    @property
    def h(self):
        return self.up + self.down

    def box(self):
        return (self.x - self.w / 2, self.y - self.up, self.x + self.w / 2, self.y + self.down)

    def sym_box(self):
        return (self.x - self.sw / 2, self.y - self.sh / 2, self.x + self.sw / 2, self.y + self.sh / 2)

    def draw(self, sh, grid, homes):
        eq = self.eq
        fn = S.EQUIPMENT[eq.kind][0]
        pn = S.Pen(sh, self.x, self.y, eq.code)
        fn(pn, self.sw, self.sh)
        sb = self.sym_box()
        sh.symbols.append((sb, eq.code))
        grid.block(sb)
        spot = sb
        # the heating surfaces inside an HRSG's casing, in gas-flow order
        for k, m in enumerate(self.inside):
            mx = self.x - self.sw / 2 + 20.0 + 16.0 * k
            mp = S.Pen(sh, mx - 2.0, self.y - 12.0, m.code)
            S.EQUIPMENT['hrsg_module'][0](mp, 6.0, 44.0)
            sh.text(mx + 4.5, self.y + 10.0, 2.0, F_trim(m.name, 22), 90, 0, m.code)
            sh.text(mx - 1.0, self.y + 36.0, 2.0, m.code, 90, 0, m.code)
            mb = (mx - 5.5, self.y - 35.0, mx + 5.5, self.y + 37.0)
            sh.inside[m.code] = eq.code
            sh.spot(m.code, mb, True)
            homes.append(m.code)
        # parts above and below, joined to the symbol by fans of thin lines (none crossing another)
        for rows, pitch, rh, side in ((self.trows, self.tpitch, self.trh, -1), (self.brows, self.bpitch, self.brh, 1)):
            if not rows:
                continue
            per = len(rows[0])
            width = per * pitch + (pitch / 2 if len(rows) > 1 else 0) - 4.0
            x0 = self.x - width / 2 + (pitch - 4.0) / 2
            edge = self.y + side * self.sh / 2
            starts = []
            for r, row in enumerate(rows):
                cy = edge + side * (FAN + rh / 2 + r * (rh + 3.0))
                for c, it in enumerate(row):
                    cx = x0 + c * pitch + (pitch / 2 if r == 1 else 0.0)
                    b = self._sat(sh, grid, it, cx, cy, rh)
                    homes.append(it.code)
                    near = cy - side * rh / 2                   # the edge facing the symbol
                    # straight down (through the gaps of the row nearer the symbol), then all from one height to the
                    # symbol's edge in the same order: no two cross
                    starts.append((cx, edge + side * (FAN - 1.5), (cx, near)))
            starts.sort()
            n = len(starts)
            lo, hi = self.x - self.sw / 2 + 1.0, self.x + self.sw / 2 - 1.0
            for k, (sx, sy, via) in enumerate(starts):
                ex = (lo + hi) / 2 if n == 1 else lo + (hi - lo) * k / (n - 1)
                pts = simplify([via, (sx, sy), (ex, edge)])
                sh.line(pts, S.THIN, 0, eq.code + '#lead')
                for a, b2 in zip(pts, pts[1:]):
                    grid.block_segment(a, b2)
        # the code and name under everything
        y = self.y + self.down - (len(self.label) - 1) * (NAME_H + 1.2) - 1.0
        sh.text(self.x, y, CODE_H, self.label[0], 0, 1, eq.code)
        lb = text_box(self.x, y, CODE_H, self.label[0], 0, 1)
        for t in self.label[1:]:
            y += NAME_H + 1.2
            sh.text(self.x, y, NAME_H, t, 0, 1, eq.code)
            lb = union(lb, text_box(self.x, y, NAME_H, t, 0, 1))
        grid.block(lb, 1.8)
        sh.spot(eq.code, union(spot, lb), True)
        homes.append(eq.code)

    def _sat(self, sh, grid, it, cx, cy, rh):
        w, h, kind = sat_size(it)
        if kind == 'bubble':
            S.bubble(S.Pen(sh, cx, cy, it.code), it.code, S.isa_letters(it.code, it.kind))
            b = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
        else:
            sym_h = h - 3.0
            if kind == 'valve':
                up, down = S.VALVE_REACH.get(it.kind, (2.5, 2.5))
                vy = cy - h / 2 + up
                S.VALVES[it.kind](S.Pen(sh, cx, vy, it.code))
                sb = (cx - S.VALVE_L / 2, vy - up, cx + S.VALVE_L / 2, vy + down)
            else:
                fn, sw, shh = S.EQUIPMENT[it.kind]
                sy = cy - h / 2 + shh / 2
                fn(S.Pen(sh, cx, sy, it.code), sw, shh)
                sb = (cx - sw / 2, sy - shh / 2, cx + sw / 2, sy + shh / 2)
            ty = cy + h / 2
            sh.text(cx, ty, 2.0, it.code, 0, 1, it.code)
            b = union(sb, text_box(cx, ty, 2.0, it.code, 0, 1))
            sh.symbols.append((sb, it.code))
        sh.spot(it.code, b, True)
        grid.block(b, 1.0)
        return b


def F_trim(t, n):
    t = t.upper()
    return t if len(t) <= n else t[:n - 1].rstrip() + '.'


# ================================================================ the generator

class Gen:
    def __init__(self, plant, areas, sheet_index, items, sheets_meta, revisions=None, gap=(34.0, 18.0)):
        self.plant, self.areas, self.items = plant, areas, items
        self.si = sheet_index
        self.meta = sheets_meta[sheet_index]
        self.sheets_meta = sheets_meta
        self.sid = self.meta['id']
        self.home_of = {c: sheet_of_item(it, items) for c, it in items.items() if drawn(it, items)}
        self.revisions = revisions or [REV0]
        self.gap = gap
        self.media = plant.get('media', {})

    def sheet_number(self, sid):
        for i, s in enumerate(self.sheets_meta):
            if s['id'] == sid:
                return number(i)
        return '?'

    # -------------------------------------------------- what this sheet holds

    def collect(self):
        items = self.items
        here = [it for c, it in sorted(items.items()) if it.role == 'equipment' and self.home_of.get(c) == self.sid]
        # an HRSG's heating surfaces go inside its casing (in the same area), in gas-flow order: away from its stack
        containers = {it.area: it for it in here if it.kind == 'hrsg'}
        inside = {}
        for it in here:
            if it.kind == 'hrsg_module' and it.area in containers:
                inside.setdefault(containers[it.area].code, []).append(it)
        for c, mods in inside.items():
            area = items[c].area
            stacks = [it for it in here if it.kind == 'stack' and it.area == area]
            ref = stacks[0].raw['at'] if stacks else items[c].raw['at']
            mods.sort(key=lambda m: (-math.dist(m.raw['at'][:2], ref[:2]), m.code))
        contained = {m.code: c for c, mods in inside.items() for m in mods}
        self.contained = contained
        self.blocks = {}
        for it in here:
            if it.code in contained:
                continue
            parts = [items[p['kks']] for p in it.raw.get('parts', []) if drawn(items[p['kks']], items)]
            self.blocks[it.code] = Block(it, parts, inside.get(it.code, []), items)
        # pipes drawn here: this sheet's own, and others' ends on its equipment or pipes (stubs)
        self.pipes = []
        for c, it in sorted(items.items()):
            if it.role != 'pipe':
                continue
            p = it.raw
            home = self.home_of.get(c) == self.sid
            ends = [self.end(p, 'from', home), self.end(p, 'to', home)]
            if not home and all(e[0] == 'sheet' or e[0] == 'open' for e in ends):
                continue
            if not home:
                # a stub: the end away from this sheet continues on the pipe's own sheet
                far = self.home_of.get(c)
                for k in (0, 1):
                    if ends[k][0] in ('sheet', 'open'):
                        ends[k] = ('sheet', far, self.far_code(p, 'from' if k == 0 else 'to'))
            self.pipes.append({'code': c, 'raw': p, 'home': home, 'ends': ends, 'item': it})
        self.pipe_codes = {pp['code'] for pp in self.pipes}
        self._inline_split()

    def far_code(self, p, side):
        e = p.get(side, {})
        if 'kks' in e:
            return e['kks']
        if 'pipe' in e:
            return e['pipe']
        return p['kks']

    def block_of(self, code):
        if code in self.blocks:
            return code
        if code in self.contained:
            return self.contained[code]
        it = self.items.get(code)
        if it is not None and it.parent is not None:
            return self.block_of(it.parent)
        return None

    def end(self, p, side, home):
        e = p.get(side, {})
        if 'kks' in e:
            b = self.block_of(e['kks'])
            if b is not None:
                return ('block', b, e.get('nozzle', ''))
            far = self.home_of.get(self._owner(e['kks']))
            return ('sheet', far, e['kks']) if far else ('open', p.get('medium', ''))
        if 'pipe' in e:
            other = e['pipe']
            if self.home_of.get(other) == self.sid:
                return ('tee', other)
            far = self.home_of.get(other)
            return ('sheet', far, other) if far else ('open', p.get('medium', ''))
        return ('open', p.get('medium', ''))

    def _owner(self, code):
        it = self.items.get(code)
        while it is not None and it.parent is not None:
            it = self.items.get(it.parent)
        return it.code if it is not None else code

    def _inline_split(self):
        """Which inline items each drawn pipe carries: all of a pipe's own on its sheet, but those in the half of the
        pipe nearer an end on another sheet whose equipment shares the item's unit and system group (the first four
        characters: a turbine's stop valve) are drawn on that end's stub instead."""
        for pp in self.pipes:
            p = pp['raw']
            inl = [self.items[v['kks']] for k in ('valves', 'parts') for v in p.get(k, [])]
            mine = []
            for it in inl:
                moved_to = None
                for k, side in ((0, 'from'), (1, 'to')):
                    e = p.get(side, {})
                    if 'kks' not in e:
                        continue
                    near = (it.at or 0.5) < 0.5 if k == 0 else (it.at or 0.5) > 0.5
                    if near and e['kks'][:4] == it.code[:4]:
                        moved_to = self.home_of.get(self._owner(e['kks']))
                if (moved_to or self.home_of.get(pp['code'])) == self.sid:
                    mine.append(it)
            pp['inline'] = sorted(mine, key=lambda it: (it.at if it.at is not None else 0.5, it.code))

    # -------------------------------------------------- layout

    def resolve(self, end, side, depth=0):
        """The block an end leads to, through tees (for the columns): a tee's from-end leads from its header's source."""
        if end[0] == 'block':
            return end[1]
        if end[0] == 'tee' and depth < 8:
            for pp in self.pipes:
                if pp['code'] == end[1]:
                    return self.resolve(pp['ends'][0 if side == 'from' else 1], side, depth + 1)
        return None

    def family(self, code):
        it = self.items[code]
        return (it.kind, code[:-2]) if len(code) >= 12 else (it.kind, code)

    ROUND = ('pump_horizontal', 'pump_vertical', 'fan_axial', 'compressor_skid', 'vacuum_pump_skid', 'generator',
             'turning_gear', 'metering_pump')

    def layout(self):
        blocks = self.blocks
        # a symbol with several pipes on one side is drawn tall enough for them five millimetres apart (a valve's body
        # needs the room); a round one (a pump) keeps its size
        count = {}
        for pp in self.pipes:
            for k, e in enumerate(pp['ends']):
                if e[0] == 'block':
                    count[(e[1], k)] = count.get((e[1], k), 0) + 1
        for (bc, k), n in sorted(count.items()):
            b = blocks[bc]
            if b.eq.kind not in self.ROUND and b.sh < (n + 1) * 5.0 + 2.0:
                b.sh = (n + 1) * 5.0 + 2.0
                b._measure()
        edges = []
        for pp in self.pipes:
            a = self.resolve(pp['ends'][0], 'from')
            b = self.resolve(pp['ends'][1], 'to')
            if a and b and a != b:
                edges.append((a, b, pp['code']))
        connected = {x for e in edges for x in e[:2]}
        for pp in self.pipes:
            for e in pp['ends']:
                if e[0] == 'block':
                    connected.add(e[1])
        # families as one node
        fam = {}
        for c in sorted(blocks):
            fam.setdefault(self.family(c), []).append(c)
        node_of = {c: min(members) for members in fam.values() for c in members}
        members = {min(m): m for m in fam.values()}
        nodes = sorted({node_of[c] for c in connected})
        nedges = sorted({(node_of[a], node_of[b]) for a, b, _ in edges if node_of[a] != node_of[b]})
        # break cycles: a depth-first walk in code order; an edge back to a node on the walk is left out
        succ = {n: [] for n in nodes}
        for a, b in nedges:
            succ[a].append(b)
        state, keep = {}, []

        def walk(n):
            state[n] = 1
            for m in succ[n]:
                if state.get(m) == 1:
                    continue
                keep.append((n, m))
                if m not in state:
                    walk(m)
            state[n] = 2

        for n in nodes:
            if n not in state:
                walk(n)
        keep = sorted(set(keep))
        layer = {n: 0 for n in nodes}
        for _ in range(len(nodes) + 1):
            changed = False
            for a, b in keep:
                if layer[b] < layer[a] + 1:
                    layer[b] = layer[a] + 1
                    changed = True
            if not changed:
                break
        ncols = max(layer.values()) + 1 if layer else 0
        cols = [[n for n in nodes if layer[n] == k] for k in range(ncols)]
        nb = {n: set() for n in nodes}
        for a, b in nedges:
            nb[a].add(b)
            nb[b].add(a)
        for sweep in range(6):
            order = range(1, ncols) if sweep % 2 == 0 else range(ncols - 2, -1, -1)
            for k in order:
                ref = cols[k - 1] if sweep % 2 == 0 else cols[k + 1]
                pos = {n: i for i, n in enumerate(ref)}
                was = {n: i for i, n in enumerate(cols[k])}

                def bary(n, pos=pos, was=was):
                    ps = [pos[m] for m in nb[n] if m in pos]
                    return (sum(ps) / len(ps) if ps else was[n], n)
                cols[k].sort(key=bary)
        # columns' widths and the gaps between them
        def node_w(n):
            return max(blocks[c].w for c in members[n])

        def node_h(n):
            return sum(blocks[c].h for c in members[n]) + self.gap[1] * 0.6 * (len(members[n]) - 1)

        widths = [max(node_w(n) for n in col) for col in cols]
        gaps = []
        for k in range(ncols - 1):
            through = sum(1 for a, b in nedges if min(layer[a], layer[b]) <= k < max(layer[a], layer[b]))
            inl = max([sum(S.VALVE_L + 6 for _ in pp['inline']) for pp in self.pipes
                       if self._spans(pp, layer, node_of, k)] or [0])
            gaps.append(self.gap[0] + self.gap[0] / 7.0 * through + inl)
        total = sum(widths) + sum(gaps)
        x0, y0, x1, y1 = LAYOUT
        if total > x1 - x0:
            raise LayoutError(f'{self.sid}: the flow is {total:.0f} mm wide, the sheet has {x1 - x0:.0f}')
        x = x0 + (x1 - x0 - total) / 2
        colx = []
        for k in range(ncols):
            colx.append(x + widths[k] / 2)
            x += widths[k] + (gaps[k] if k < ncols - 1 else 0)
        heights = [sum(node_h(n) for n in col) + self.gap[1] * (len(col) - 1) for col in cols]
        top = y0 + G
        tallest = max(heights) if heights else 0.0
        cy = top + tallest / 2
        placed = {}
        for k, col in enumerate(cols):
            y = cy - heights[k] / 2
            for n in col:
                for c in members[n]:
                    b = blocks[c]
                    b.x = colx[k]
                    b.y = y + b.up
                    y += b.h + self.gap[1] * 0.6
                    placed[c] = b
                y += self.gap[1] - self.gap[1] * 0.6
        # straighten: a column's nodes move towards the mean height of their neighbours on the left, in order
        for k in range(1, ncols):
            col = cols[k]
            want = []
            for n in col:
                ys = [blocks[m].y for m in nb[n] if layer[m] < k]
                cur = blocks[members[n][0]].y
                want.append(sum(ys) / len(ys) if ys else cur)
            prev_bottom = y0 + G
            for n, wy in zip(col, want):
                ms = members[n]
                first = blocks[ms[0]]
                shift = wy - first.y
                lowest = min(blocks[c].y - blocks[c].up for c in ms)
                if lowest + shift < prev_bottom:
                    shift = prev_bottom - lowest
                for c in ms:
                    blocks[c].y += shift
                prev_bottom = max(blocks[c].y + blocks[c].down for c in ms) + self.gap[1]
        # the free blocks (no pipe on this sheet) in rows below, in their order across the plant
        free = sorted((c for c in blocks if c not in placed), key=lambda c: (
            self.items[c].raw['at'][0], self.items[c].raw['at'][1], c))
        bottom = max((b.y + b.down for b in placed.values()), default=y0 - self.gap[1])
        y = bottom + self.gap[1] + 4.0 if placed else y0
        x = x0
        row_h = 0.0
        for c in free:
            b = blocks[c]
            if x + b.w > x1 and x > x0:
                x = x0
                y += row_h + self.gap[1] * 0.8
                row_h = 0.0
            b.x = x + b.w / 2
            b.y = y + b.up
            x += b.w + 14.0
            row_h = max(row_h, b.h)
        for b in blocks.values():
            b.x = round(b.x / G) * G
            b.y = round(b.y / G) * G
            if b.y + b.down > y1 + 0.01 or b.y - b.up < y0 - 0.01:
                raise LayoutError(f'{self.sid}: {b.code} falls outside the sheet (the sheet is too full)')
        bl = sorted(blocks.values(), key=lambda b: b.code)
        for i, a in enumerate(bl):
            for b in bl[i + 1:]:
                if overlap(a.box(), b.box()):
                    raise LayoutError(f'{self.sid}: {a.code} and {b.code} overlap')

    def _spans(self, pp, layer, node_of, k):
        a = self.resolve(pp['ends'][0], 'from')
        b = self.resolve(pp['ends'][1], 'to')
        if not a or not b:
            return False
        la, lb = layer.get(node_of[a]), layer.get(node_of[b])
        return la is not None and lb is not None and min(la, lb) <= k < max(la, lb)

    # -------------------------------------------------- ports and margin connectors

    def assign_ports(self):
        """Each pipe end on a block gets a point on the symbol's side: ends going out on the right, coming in on the
        left, spread down the side in the order of the far ends' heights, on the grid."""
        want = {}
        for pp in self.pipes:
            for k, e in enumerate(pp['ends']):
                if e[0] != 'block':
                    continue
                side = 'R' if k == 0 else 'L'
                other = pp['ends'][1 - k]
                ob = self.resolve(other, 'to' if k == 0 else 'from')
                oy = self.blocks[ob].y if ob else self.blocks[e[1]].y + (-50 if other[0] == 'sheet' else 50)
                want.setdefault((e[1], side), []).append((oy, pp['code'], k))
        self.port = {}
        for (bc, side), lst in sorted(want.items()):
            b = self.blocks[bc]
            lst.sort()
            n = len(lst)
            # distinct rows of the grid along the side, two cells apart where the side is long enough
            rows = [r * G for r in range(int(math.ceil((b.y - b.sh / 2 + 1.0) / G)), int(math.floor((b.y + b.sh / 2 - 1.0) / G)) + 1)]
            step = 2 if (n - 1) * 2 + 1 <= len(rows) else 1
            if (n - 1) * step + 1 > len(rows):
                raise LayoutError(f'{self.sid}: {bc} has {n} pipes on one side, more than its symbol takes')
            first = (len(rows) - ((n - 1) * step + 1)) // 2
            ys = [rows[first + i * step] for i in range(n)]
            for (oy, pc, k), y in zip(lst, ys):
                ex = b.x + (b.sw / 2 if side == 'R' else -b.sw / 2)
                if b.eq.kind in self.ROUND:
                    r = b.sh / 2
                    dy = y - b.y
                    ex = b.x + (1 if side == 'R' else -1) * math.sqrt(max(0.0, r * r - dy * dy))
                self.port[(pc, k)] = (ex, y, side)

    def place_margins(self):
        """Ends on another sheet or open: in the margin columns, as near the height of what they connect as the slots
        allow. Off-sheet connectors are arrows naming the other sheet, with the far code under them."""
        self.margin = {}
        for side in ('L', 'R'):
            want = []
            for pp in self.pipes:
                for k, e in enumerate(pp['ends']):
                    if e[0] not in ('sheet', 'open') or (pp['code'], k) in self.local:
                        continue
                    if (k == 0) != (side == 'L'):
                        continue
                    other = pp['ends'][1 - k]
                    if other[0] == 'block':
                        y = self.port[(pp['code'], 1 - k)][1]
                    else:
                        ob = self.resolve(other, 'to' if k == 0 else 'from')
                        y = self.blocks[ob].y if ob else (LAYOUT[1] + LAYOUT[3]) / 2
                    want.append((y, pp['code'], k))
            want.sort()
            pitch = 18.0
            ys = []
            lo, hi = LAYOUT[1] + 4.0, (REVS[1] - 8.0) if side == 'R' else LAYOUT[3]
            for y, _, _ in want:
                y = max(lo, y)
                if ys and y < ys[-1] + pitch:
                    y = ys[-1] + pitch
                ys.append(y)
            if ys and ys[-1] > hi:
                shift = ys[-1] - hi
                ys = [y - shift for y in ys]
                for i in range(1, len(ys)):
                    ys[i] = max(ys[i], ys[i - 1] + pitch)
                if ys[0] < lo:
                    raise LayoutError(f'{self.sid}: too many ends in the {side} margin')
            for (_, pc, k), y in zip(want, ys):
                self.margin[(pc, k)] = (side, round(y / G) * G)

    def place_local_ends(self, sh, grid):
        """An open end whose other end is on a symbol here ends just beside that symbol (a short run with an arrow and
        its medium's name), not at the sheet's margin, where there is room for it and its inline items."""
        self.local, self.local_band = {}, {}
        for pp in self.pipes:
            for k in (0, 1):
                e, other = pp['ends'][k], pp['ends'][1 - k]
                if e[0] != 'open' or other[0] != 'block':
                    continue
                ex, ey, side = self.port[(pp['code'], 1 - k)]
                need = sum((S.VALVE_L + 3.0) if it.kind in S.VALVES else 5.0 for it in pp.get('inline', []))
                ls = max(16.0, need * 1.3 + 18.0)
                name = F_trim(self.media.get(e[1], {}).get('name', e[1].replace('_', ' ')).upper(), 15)
                tw = F.width(name, 2.0)
                if k == 1:          # going out: from the symbol's right to the open end
                    x0, x1 = ex, ex + ls
                    tb = (x1 + 1.5, ey - 1.3, x1 + 1.5 + tw, ey + 1.3)        # after the arrow, on the line
                else:               # coming in: from the open end to the symbol's left
                    x0, x1 = ex - ls, ex
                    tb = (x0 - 1.5 - tw, ey - 1.3, x0 - 1.5, ey + 1.3)
                run = (min(x0, x1) + (1.5 if k == 0 else 3.0), ey - 1.0, max(x0, x1) - (3.0 if k == 0 else 1.5), ey + 1.0)
                if not grid.free_box(run, m=0.0) or not grid.free_box(tb, m=0.6) or \
                        any(overlap(tb, t) for t in self.text_boxes) or tb[0] < LAYOUT[0] - 20 or tb[2] > LAYOUT[2] + 20:
                    continue
                owner = pp['code'] + '#end%d' % k
                sh.text(tb[0], ey + 1.0, 2.0, name, 0, 0, owner)
                if k == 1:
                    sh.fill([(x1, ey), (x1 - 3.0, ey - 1.3), (x1 - 3.0, ey + 1.3)], owner)
                else:
                    sh.fill([(x0 + 3.0, ey), (x0, ey - 1.3), (x0, ey + 1.3)], owner)
                grid.block(tb, 0.6)
                band = 4.0 if pp.get('inline') else 0.1
                # the run and the room its items need beside it, kept until it is drawn
                before = bytes(grid.blocked)
                grid.block((x0, ey - band, x1, ey + band), 0.1)
                self.local_band[(pp['code'], k)] = [c for c in range(len(before))
                                                     if grid.blocked[c] and not before[c]]
                self.text_boxes.append(tb)
                self.local[(pp['code'], k)] = [(x0, ey), (x1, ey)]

    def draw_margin(self, sh, grid, pp, k):
        side, y = self.margin[(pp['code'], k)]
        e = pp['ends'][k]
        owner = pp['code'] + '#end%d' % k
        if side == 'L':
            x0, x1 = CONN_L, CONN_L + 32.0
            tip = (x1, y)
        else:
            x0, x1 = CONN_R - 32.0, CONN_R
            tip = (x0, y)
        if e[0] == 'sheet':
            sheet, far = e[1], e[2]
            num = self.sheet_number(sheet)
            # an arrow pentagon pointing the way the flow goes (into the sheet on the left, out of it on the right)
            pts = [(x0, y - 3.5), (x1 - 4.0, y - 3.5), (x1, y), (x1 - 4.0, y + 3.5), (x0, y + 3.5), (x0, y - 3.5)]
            sh.line(pts, S.THIN * 2, 0, owner)
            sh.text((x0 + x1 - 4.0) / 2, y + 1.0, 2.0, num, 0, 1, owner)
            sh.text((x0 + x1) / 2, y + 7.6, 2.0, far, 0, 1, owner)
            word = 'FROM' if side == 'L' else 'TO'
            sh.text((x0 + x1) / 2, y - 4.8, 2.0, word, 0, 1, owner)
            b = (x0, y - 7.0, x1, y + 8.2)
            sh.links.append((sheet, far, b))
        else:
            name = self.media.get(e[1], {}).get('name', e[1].replace('_', ' ')).upper()
            name = F_trim(name, 15)
            sh.line([(x0, y), (x1, y)], S.THICK, 0, owner)
            ax = x1 if side == 'L' else x1
            sh.fill([(ax, y), (ax - 3.0, y - 1.3), (ax - 3.0, y + 1.3)], owner) if side == 'R' else \
                sh.fill([(x0 + 3.0, y), (x0, y - 1.3), (x0, y + 1.3)], owner)
            sh.text((x0 + x1) / 2, y - 1.6, 2.0, name, 0, 1, owner)
            sh.text((x0 + x1) / 2, y + 4.0, 2.0, 'CONTINUES' if side == 'R' else 'SUPPLY', 0, 1, owner)
            b = (x0, y - 4.0, x1, y + 4.6)
        grid.block(b, 1.0)
        return tip

    # -------------------------------------------------- routing one pipe

    def end_cells(self, grid, pp):
        """Each end of a pipe: ('pt', point, approach cell i, j, side) or ('tee', header). The approach cell is just
        clear of the symbol's (or connector's) inflated outline."""
        code = pp['code']
        ends = []
        for k in (0, 1):
            e = pp['ends'][k]
            if e[0] == 'block':
                ex, ey, side = self.port[(code, k)]
                i, j = grid.cell(ex, ey)
                if side == 'R':
                    i = int(math.floor((ex + 1.3) / G)) + 1
                else:
                    i = int(math.ceil((ex - 1.3) / G)) - 1
                ends.append(('pt', (ex, ey), i, j, side))
            elif e[0] in ('sheet', 'open'):
                tx, ty = self.margin_tip[(code, k)]
                i, j = grid.cell(tx, ty)
                side = self.margin[(code, k)][0]
                i = i + 1 if side == 'L' else i - 1
                ends.append(('pt', (tx, ty), i, j, 'R' if side == 'L' else 'L'))
            else:
                ends.append(('tee', e[1]))
        return ends

    def corridor_need(self, pp, k):
        """How many cells of straight run an end keeps: enough for the inline items in its half of the pipe (all of
        them when the other end is a tee) and the clearance at the end, at least three."""
        other = pp['ends'][1 - k]
        need = 8.0
        for it in pp.get('inline', []):
            at = it.at if it.at is not None else 0.5
            if other[0] == 'tee' or (at < 0.5) == (k == 0):
                need += (S.VALVE_L + 3.0) if it.kind in S.VALVES else 5.0
        return max(3, int(math.ceil(need / G)) + 1) if need > 8.0 else 3

    def corridor(self, grid, pp, k, end, reserve=False):
        """The cells an end's straight approach keeps (no other pipe may use them), outwards from its approach cell; cut
        short at an obstacle when first reserved."""
        key = (pp['code'], k)
        _, _, i, j, side = end
        o = 1 if side == 'R' else -1
        if reserve:
            n = 0
            for s in range(self.corridor_need(pp, k)):
                ci = i + o * s
                if s > 0 and not (0 <= ci < grid.nx and not grid.blocked[j * grid.nx + ci] and not grid.use[j * grid.nx + ci]):
                    break
                n += 1
            self.corr_n[key] = max(1, n)
        return [(i + o * s, j) for s in range(self.corr_n[key])]

    def route_pipe(self, sh, grid, pp, drawn_pipes):
        """Routes a pipe and puts its inline items, instruments, label and flow arrow on it."""
        code = pp['code']
        for k in (0, 1):
            if (code, k) in self.local:
                return self.route_local(sh, grid, pp, drawn_pipes, self.local[(code, k)])
        ends = self.end_cells(grid, pp)
        corr = [None, None]
        for k, e in enumerate(ends):
            if e[0] == 'pt':
                corr[k] = self.corridor(grid, pp, k, e)
                for ci, cj in corr[k]:
                    grid.unblock(ci, cj)
        # starts and goals: a from-end leaves its point going +x (it is on the right of a symbol or a left connector),
        # a to-end is entered going +x; a tee leaves or joins a straight run of its header at right angles
        nx = grid.nx
        starts, goals, pre, post = [], {}, None, None
        a, b = ends
        lead_in, lead_out = [], []
        if a[0] == 'pt':
            cs = [cj * nx + ci for ci, cj in corr[0]]
            starts = [(cs[-1], 0)]
            lead_in = [(c, 0) for c in cs[:-1]]
            pre = a[1]
        else:
            starts = [(k, d) for k, d in self.tee_cells(grid, drawn_pipes, a[1], True)]
            if b[0] == 'tee' and pp['inline']:
                # a pipe between two tees carries its items on a straight run out of its first tee
                m = self.corridor_need(pp, 0)
                walked = {}
                for k, d in starts:
                    cs, c = [k], k
                    for _ in range(m):
                        i, j = c % nx + DX[d], c // nx + DY[d]
                        if not (0 <= i < nx and 0 <= j < grid.ny):
                            break
                        c = j * nx + i
                        if grid.blocked[c] or grid.use[c]:
                            break
                        cs.append(c)
                    if len(cs) == m + 1:
                        walked[(cs[-1], d)] = cs
                if walked:
                    starts = sorted(walked)
                    self._walked = walked
        if b[0] == 'pt':
            cs = [cj * nx + ci for ci, cj in corr[1]]
            goals = {cs[-1]: {0, 1, 3}}        # into the corridor's outer cell from anywhere but its inside
            lead_out = [(c, 0) for c in reversed(cs[:-1])]
            post = b[1]
        else:
            for k, d in self.tee_cells(grid, drawn_pipes, b[1], False):
                goals.setdefault(k, set()).add(d)
        if not starts or not goals:
            raise LayoutError(f'{self.sid}: {code} has no room to join its header')
        path = grid.route(starts, goals) or grid.route(starts, goals, (0, 0, grid.nx - 1, grid.ny - 1))
        if path is None:
            raise LayoutError(f'{self.sid}: no way for {code}')
        if a[0] == 'tee' and getattr(self, '_walked', None):
            path = [(c, path[0][1]) for c in self._walked[(path[0][0], path[0][1])][:-1]] + path
        self._walked = None
        path = lead_in + path + lead_out
        cells = [k for k, _ in path]
        pts = [grid.at(k % nx, k // nx) for k in cells]
        tee_pts = []
        if a[0] == 'tee':
            # the path starts on the header's cell itself
            tee_pts.append(pts[0])
        if b[0] == 'tee':
            tee_pts.append(pts[-1])
        if pre is not None:
            pts = [pre] + pts
        if post is not None:
            pts = pts + [post]
        crossings = []
        for idx, (k, d) in enumerate(path):
            u = grid.use[k]
            horiz = d % 2 == 0
            first_or_last = idx == 0 or idx == len(path) - 1
            if u and not first_or_last:
                crossings.append(grid.at(k % nx, k // nx))
        # mark the cells: runs, bends and ends as nodes
        for idx, (k, d) in enumerate(path):
            nd = path[idx + 1][1] if idx + 1 < len(path) else d
            node = idx == 0 or idx == len(path) - 1 or nd != d
            if a[0] == 'tee' and idx == 0 or b[0] == 'tee' and idx == len(path) - 1:
                grid.use[k] |= NODE
                continue
            if grid.use[k] and not node:
                grid.use[k] |= H_RUN if d % 2 == 0 else V_RUN     # a crossing: neither way is free any more
                continue
            grid.use[k] |= (H_RUN if d % 2 == 0 else V_RUN) | (NODE if node else 0)
            if nd != d:
                grid.use[k] |= H_RUN | V_RUN
            grid.run_of[k] = code
        pts = simplify(pts)
        pp['pts'] = pts
        pp['cells'] = set(cells)
        pp['crossings'] = crossings
        pp['tees'] = tee_pts
        drawn_pipes[code] = pp
        self.place_on(sh, grid, pp)

    def route_local(self, sh, grid, pp, drawn_pipes, pts):
        """A pipe from a symbol to an open end beside it: one straight run."""
        nx = grid.nx
        (x0, y), (x1, _) = pts
        j = int(round(y / G))
        for k in (0, 1):
            for c in self.local_band.get((pp['code'], k), []):     # only what its reservation blocked
                grid.blocked[c] = 0
        cells = []
        for i in range(int(math.ceil(x0 / G)), int(math.floor(x1 / G)) + 1):
            k = j * nx + i
            grid.use[k] |= H_RUN | (NODE if i in (int(math.ceil(x0 / G)), int(math.floor(x1 / G))) else 0)
            grid.run_of[k] = pp['code']
            cells.append(k)
        pp['pts'], pp['cells'], pp['crossings'], pp['tees'] = list(pts), set(cells), [], []
        drawn_pipes[pp['code']] = pp
        self.place_on(sh, grid, pp)

    def tee_cells(self, grid, drawn_pipes, header, leaving):
        """Cells of a header's straight runs where a branch may join or leave at right angles: (cell, direction).
        Leaving: the direction the branch leaves in; joining: the direction it arrives in."""
        hp = drawn_pipes.get(header)
        if hp is None:
            raise LayoutError(f'{self.sid}: the header {header} is not drawn before its branch')
        nx = grid.nx
        out = []
        for (x0, y0), (x1, y1) in zip(hp['pts'], hp['pts'][1:]):
            if abs(y0 - y1) < 1e-6 and abs(x1 - x0) >= 4 * G:        # a horizontal run
                lo, hi = sorted((x0, x1))
                for i in range(int(math.ceil(lo / G)) + 2, int(math.floor(hi / G)) - 1):
                    j = int(round(y0 / G))
                    k = j * nx + i
                    if grid.use[k] & NODE or not grid.use[k] & H_RUN or grid.use[k] & V_RUN:
                        continue
                    if grid.run_of.get(k) != header:
                        continue
                    if any(grid.use[k + dd] & NODE for dd in (-1, 1, -2, 2)):
                        continue
                    out += [(k, 1), (k, 3)]
            elif abs(x0 - x1) < 1e-6 and abs(y1 - y0) >= 4 * G:      # a vertical run
                lo, hi = sorted((y0, y1))
                for j in range(int(math.ceil(lo / G)) + 2, int(math.floor(hi / G)) - 1):
                    i = int(round(x0 / G))
                    k = j * nx + i
                    if grid.use[k] & NODE or not grid.use[k] & V_RUN or grid.use[k] & H_RUN:
                        continue
                    if grid.run_of.get(k) != header:
                        continue
                    if any(grid.use[k + dd * nx] & NODE for dd in (-1, 1, -2, 2)):
                        continue
                    out += [(k, 0), (k, 2)]
        if leaving:
            return out
        # joining: arrive moving towards the header (the opposite of leaving it)
        return [(k, (d + 2) % 4) for k, d in out]

    # -------------------------------------------------- what a pipe carries

    def segments(self, pts):
        out, s = [], 0.0
        for a, b in zip(pts, pts[1:]):
            L = math.dist(a, b)
            out.append((a, b, s, L))
            s += L
        return out, s

    def place_on(self, sh, grid, pp):
        code, pts = pp['code'], pp['pts']
        segs, total = self.segments(pts)
        own = pp['cells']
        taken = []                       # (segment index, from, to) along runs already used
        for c in pp['crossings'] + pp['tees']:
            for si, (a, b, s0, L) in enumerate(segs):
                if point_on(c, a, b):
                    t = math.dist(a, c)
                    taken.append((si, t - 2.0, t + 2.0))
        for t in pp['tees']:
            sh.fill(diamond(t, 0.9), code)
        # inline items, in their order along the pipe
        last_s = 0.0
        for it in pp['inline']:
            if it.kind in S.VALVES or it.kind == 'flow_element':
                last_s = self._inline(sh, grid, pp, it, segs, total, taken, own, last_s)
            elif it.kind in S.INSTRUMENTS:
                last_s = self._tap(sh, grid, pp, it, segs, total, taken, own, last_s)
            else:
                raise LayoutError(f'{self.sid}: no way to draw {it.code} ({it.kind}) on a pipe')
        pp['segs'], pp['taken'] = segs, taken
        # the pipe as one line, broken where it crosses an earlier one
        w = S.THICK + (0.2 if (pp['raw'].get('dn') or 0) >= 300 else 0.0)
        for piece in break_at(pts, pp['crossings'], 1.3):
            sh.line(piece, w, 0, code)
        for a, b, s0, L in segs:
            sh.spot(code, inflate((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])), 1.5), False)

    def _free_spot(self, segs, total, taken, length, want, after, pred):
        """The point along the pipe nearest `want` (a distance along it) where `length` of straight run is free, at or
        after `after`: (segment index, distance along the segment) or None. `pred` checks the room beside the line."""
        best = None
        for si, (a, b, s0, L) in enumerate(segs):
            if L < length + 2.0:
                continue
            lo, hi = length / 2 + 1.0, L - length / 2 - 1.0
            if si == 0:
                lo = max(lo, 3.0 + length / 2)
            if si == len(segs) - 1:
                hi = min(hi, L - 3.0 - length / 2)
            t = lo
            while t <= hi + 1e-6:
                s = s0 + t
                if s - length / 2 >= max(after, 8.0) - 1e-6 and s + length / 2 <= total - 8.0 and not any(ts == si and t + length / 2 > f and t - length / 2 < e
                                                               for ts, f, e in taken):
                    cost = abs(s - want)
                    if (best is None or cost < best[0]) and pred(si, t):
                        best = (cost, si, t)
                t += G / 2
        return None if best is None else best[1:]

    def _want(self, pp, it, total):
        """Where along the drawn pipe an inline item would go: at its `at` on the pipe's own sheet; on a stub (the part
        of a pipe drawn beside its far end's equipment) spread evenly in their order."""
        if pp['home']:
            return (it.at if it.at is not None else 0.5) * total
        n = len(pp['inline'])
        return total * (pp['inline'].index(it) + 1) / (n + 1)

    def _inline(self, sh, grid, pp, it, segs, total, taken, own, after):
        kind = it.kind
        length = S.VALVE_L + 2.0 if kind != 'flow_element' else 3.0
        up, down = S.VALVE_REACH.get(kind, (2.5, 2.5)) if kind != 'flow_element' else (3.0, 3.0)
        is_fe = kind == 'flow_element'
        bw, bh = S.bubble_size(it.code) if is_fe else (0, 0)

        def rots(horiz, ux, uy):
            if kind == 'valve_check':
                return [(0 if ux > 0 else 180)] if horiz else [(270 if uy > 0 else 90)]
            return [0, 180] if horiz else [90, 270]

        def geo(si, t, rot):
            a, b, s0, L = segs[si]
            ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            cx, cy = a[0] + ux * t, a[1] + uy * t
            horiz = abs(uy) < 0.5
            box = {0: (cx - length / 2, cy - up, cx + length / 2, cy + down),
                   180: (cx - length / 2, cy - down, cx + length / 2, cy + up),
                   90: (cx - up, cy - length / 2, cx + down, cy + length / 2),
                   270: (cx - down, cy - length / 2, cx + up, cy + length / 2)}[rot]
            return cx, cy, ux, uy, horiz, box

        chosen = {}

        def ok(si, t):
            a, b, s0, L = segs[si]
            ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            horiz = abs(uy) < 0.5
            for rot in rots(horiz, ux, uy):
                cx, cy, ux, uy, horiz, box = geo(si, t, rot)
                if not grid.free_box(box, own, 0.3):
                    continue
                if is_fe and self._bubble_room(grid, cx, cy, horiz, bw, bh, own) is None:
                    continue
                chosen[(si, t)] = rot
                return True
            return False

        want = self._want(pp, it, total)
        got = self._free_spot(segs, total, taken, length, want, after, ok)
        if got is None:
            raise LayoutError(f'{self.sid}: no room for {it.code} on {pp["code"]}')
        si, t = got
        rot = chosen[(si, t)]
        cx, cy, ux, uy, horiz, box = geo(si, t, rot)
        if is_fe:
            S.orifice(S.Pen(sh, cx, cy, it.code, 0 if horiz else 90))
            bb = self._bubble_at(sh, grid, it, cx, cy, horiz, bw, bh, own)
            sh.spot(it.code, union(box, bb), True)
        else:
            S.VALVES[kind](S.Pen(sh, cx, cy, it.code, rot))
            sh.symbols.append((box, it.code))
            sh.spot(it.code, box, True)
        grid.block(box, 0.3)
        taken.append((si, t - length / 2, t + length / 2))
        self.homes.append(it.code)
        return segs[si][2] + t + length / 2

    def _bubble_room(self, grid, cx, cy, horiz, bw, bh, own):
        for off in (6.0 + bh / 2, -(6.0 + bh / 2), 11.0 + bh / 2, -(11.0 + bh / 2)):
            if horiz:
                bx, by = cx, cy - off
                box = (bx - bw / 2, by - bh / 2, bx + bw / 2, by + bh / 2)
                lead = (cx, cy - math.copysign(1.0, off) * 1.5, bx, by + math.copysign(1.0, off) * bh / 2)
            else:
                ww = bw
                bx, by = cx - math.copysign(1.0, off) * (abs(off) - bh / 2 + ww / 2), cy
                box = (bx - ww / 2, by - bh / 2, bx + ww / 2, by + bh / 2)
                lead = (cx - math.copysign(1.0, off) * 1.5, cy, bx + math.copysign(1.0, off) * ww / 2, by)
            lb = (min(lead[0], lead[2]), min(lead[1], lead[3]), max(lead[0], lead[2]), max(lead[1], lead[3]))
            if grid.free_box(box, own, 0.8) and grid.free_box(lb, own, 0.2):
                return bx, by, box, lead
        return None

    def _bubble_at(self, sh, grid, it, cx, cy, horiz, bw, bh, own):
        got = self._bubble_room(grid, cx, cy, horiz, bw, bh, own)
        bx, by, box, lead = got
        S.bubble(S.Pen(sh, bx, by, it.code), it.code, S.isa_letters(it.code, it.kind))
        sh.line([(lead[0], lead[1]), (lead[2], lead[3])], S.THIN, 0, it.code)
        grid.block(box, 0.8)
        grid.block_segment((lead[0], lead[1]), (lead[2], lead[3]), 0.3)
        return box

    def _tap(self, sh, grid, pp, it, segs, total, taken, own, after):
        bw, bh = S.bubble_size(it.code)

        def ok(si, t):
            a, b, s0, L = segs[si]
            ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            return self._bubble_room(grid, a[0] + ux * t, a[1] + uy * t, abs(uy) < 0.5, bw, bh, own) is not None

        want = self._want(pp, it, total)
        got = self._free_spot(segs, total, taken, 3.0, want, after, ok)
        if got is None:
            raise LayoutError(f'{self.sid}: no room for {it.code} on {pp["code"]}')
        si, t = got
        a, b, s0, L = segs[si]
        ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
        cx, cy = a[0] + ux * t, a[1] + uy * t
        box = self._bubble_at(sh, grid, it, cx, cy, abs(uy) < 0.5, bw, bh, own)
        sh.fill(diamond((cx, cy), 0.7), it.code)
        sh.spot(it.code, box, True)
        taken.append((si, t - 1.5, t + 1.5))
        self.homes.append(it.code)
        return s0 + t + 1.5

    def _label(self, sh, grid, pp, segs, taken, own):
        """The pipe's code, size and medium beside it: on its longest free run if the label fits there, else
        overhanging a shorter run's end, else one or two lines further out; the shortest form that fits."""
        p = pp['raw']
        med = self.media.get(p.get('medium', ''), {}).get('name', p.get('medium', '')).upper()
        dn = 'DN%d' % p['dn'] if p.get('dn') else ''
        tries = [[' '.join(x for x in (pp['code'], dn, med) if x)], [pp['code'], ' '.join(x for x in (dn, med) if x)],
                 [' '.join(x for x in (pp['code'], dn) if x)], [pp['code']]]
        h = 2.0
        order = sorted(range(len(segs)), key=lambda si: (-segs[si][3], si))
        for overhang, off in ((False, 1.6), (True, 1.6), (True, 4.0), (True, 8.0), (True, 12.0)):
            for lines in tries:
                wmax = max(F.width(t, h) for t in lines)
                hh = len(lines) * (h + 1.0)
                for si in order:
                    a, b, s0, L = segs[si]
                    if L < (4.0 if overhang else wmax + 4.0):
                        continue
                    horiz = abs(a[1] - b[1]) < 1e-6
                    lo, hi = sorted((a[0], b[0])) if horiz else sorted((a[1], b[1]))
                    if overhang:
                        lo, hi = lo - wmax + 3.0, hi + wmax - 3.0
                    c0 = (lo + hi) / 2
                    steps = [0.0]
                    k = 1
                    while k * G < (hi - lo) / 2:
                        steps += [k * G, -k * G]
                        k += 1
                    for st in steps:
                        for sidev in (-1, 1):
                            q0 = c0 + st - wmax / 2
                            if q0 < lo + 1.0 or q0 + wmax > hi - 1.0:
                                continue
                            if horiz:
                                y = a[1]
                                box = (q0, y - off - 0.4 - hh, q0 + wmax, y - off) if sidev < 0 else \
                                    (q0, y + off, q0 + wmax, y + off + 0.4 + hh)
                            else:
                                x = a[0]
                                box = (x - off - 0.4 - hh, q0, x - off, q0 + wmax) if sidev < 0 else \
                                    (x + off, q0, x + off + 0.4 + hh, q0 + wmax)
                            if box[0] < FRAME[0] + 2 or box[2] > FRAME[2] - 2 or box[1] < FRAME[1] + 2:
                                continue
                            if any(overlap(box, t) for t in self.text_boxes):
                                continue
                            if not grid.free_box(box, own, 0.2) or not self.clear(sh, box, pp['code']):
                                continue
                            if horiz:
                                for li, t in enumerate(lines):
                                    sh.text(box[0], box[1] + (li + 1) * (h + 1.0) - 0.6, h, t, 0, 0, pp['code'])
                            else:
                                for li, t in enumerate(lines):
                                    sh.text(box[0] + (li + 1) * (h + 1.0) - 0.6, box[3], h, t, 90, 0, pp['code'])
                            if off > 5.0:
                                # a leader from the label to its line
                                if horiz:
                                    lx = min(max((box[0] + box[2]) / 2, lo + wmax - 3.0 + 1.0), hi - wmax + 3.0 - 1.0)
                                    lead = [(lx, box[3] if sidev < 0 else box[1]), (lx, a[1])]
                                else:
                                    ly = min(max((box[1] + box[3]) / 2, lo + wmax - 3.0 + 1.0), hi - wmax + 3.0 - 1.0)
                                    lead = [(box[2] if sidev < 0 else box[0], ly), (a[0], ly)]
                                lb = (min(lead[0][0], lead[1][0]), min(lead[0][1], lead[1][1]),
                                      max(lead[0][0], lead[1][0]), max(lead[0][1], lead[1][1]))
                                if not grid.free_box(lb, own, 0.0):
                                    continue
                                sh.line(lead, S.THIN, 0, pp['code'])
                                grid.block_segment(*lead)
                            grid.block(box, 0.6)
                            self.text_boxes.append(box)
                            sh.spot(pp['code'], box, pp['home'])
                            if pp['home']:
                                self.homes.append(pp['code'])
                            return
        if self._label_far(sh, grid, pp, segs, own, tries[-1], h):
            return
        if pp['home']:
            raise LayoutError(f'{self.sid}: no room for the label of {pp["code"]}')
        # a stub (the pipe's label is on its own sheet): tapping its line still opens it (the segments' spots)

    def _label_far(self, sh, grid, pp, segs, own, lines, h):
        """The last resort for a short pipe's label: the nearest free place within 30 mm, with a leader to the pipe."""
        wmax = max(F.width(t, h) for t in lines)
        hh = len(lines) * (h + 1.0)
        best = None
        for si, (a, b, s0, L) in enumerate(segs):
            m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            for dy in range(-12, 13):
                for dx in range(-12, 13):
                    cx, cy = m[0] + dx * G, m[1] + dy * G
                    box = (cx - wmax / 2, cy - hh / 2, cx + wmax / 2, cy + hh / 2)
                    # the leader: from the box's edge nearest the segment's middle, straight to it
                    lx = min(max(m[0], box[0]), box[2])
                    ly = min(max(m[1], box[1]), box[3])
                    d = math.dist((lx, ly), m)
                    if d < 2.0 or (best is not None and d >= best[0]):
                        continue
                    if box[0] < FRAME[0] + 2 or box[2] > FRAME[2] - 2 or box[1] < FRAME[1] + 2 or box[3] > FRAME[3] - 2:
                        continue
                    if any(overlap(box, t) for t in self.text_boxes) or not grid.free_box(box, own, 0.3) or \
                            not self.clear(sh, box, pp['code']):
                        continue
                    lead = ((lx, ly), m)
                    if not self.clear_line(sh, lead, pp['code']):
                        continue
                    best = (d, box, lead)
        if best is None:
            return False
        _, box, lead = best
        for li, t in enumerate(lines):
            sh.text(box[0], box[1] + (li + 1) * (h + 1.0) - 0.6, h, t, 0, 0, pp['code'])
        sh.line(list(lead), S.THIN, 0, pp['code'])
        grid.block(box, 0.6)
        self.text_boxes.append(box)
        sh.spot(pp['code'], box, pp['home'])
        if pp['home']:
            self.homes.append(pp['code'])
        return True

    def clear_line(self, sh, seg, owner):
        """A leader crosses no text and no symbol (lines it may cross)."""
        for x, y, hgt, a, al, t, o in sh.texts:
            if seg_box(seg[0], seg[1], inflate(text_box(x, y, hgt, t, a, al), 0.3)):
                return False
        return not any(seg_box(seg[0], seg[1], s) for s, o in sh.symbols if o.split('#')[0] != owner)

    def clear(self, sh, box, owner):
        """Nothing drawn lies in the box: no symbol, no text and no line but the owner's own (the grid's cells only
        see what covers a cell's centre)."""
        b = inflate(box, 0.3)
        if any(overlap(b, s) for s, o in sh.symbols):
            return False
        for w, dash, pts, lo in sh.lines:
            if lo.split('#')[0] == owner:
                continue
            for q0, q1 in zip(pts, pts[1:]):
                if seg_box(q0, q1, b):
                    return False
        return True

    def _arrow(self, sh, grid, pp, segs, taken):
        order = sorted(range(len(segs)), key=lambda si: (-segs[si][3], si))
        for si in order:
            a, b, s0, L = segs[si]
            if L < 10.0:
                continue
            for frac in (0.5, 0.3, 0.7, 0.15, 0.85):
                t = L * frac
                if any(ts == si and t + 3.0 > f and t - 3.0 < e for ts, f, e in taken):
                    continue
                ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
                cx, cy = a[0] + ux * t, a[1] + uy * t
                px, py = -uy, ux
                tip = (cx + ux * 1.5, cy + uy * 1.5)
                sh.fill([tip, (cx - ux * 1.5 + px * 1.2, cy - uy * 1.5 + py * 1.2),
                         (cx - ux * 1.5 - px * 1.2, cy - uy * 1.5 - py * 1.2)], pp['code'])
                taken.append((si, t - 2.0, t + 2.0))
                return

    # -------------------------------------------------- the whole sheet

    def make(self):
        self.collect()
        for gap in ((34.0, 18.0), (44.0, 24.0), (26.0, 16.0), (56.0, 30.0), (20.0, 14.0), (16.0, 12.0)):
            self.gap = gap
            try:
                return self._make()
            except LayoutError as e:
                last = e
                for b in self.blocks.values():
                    b.ports = {'L': [], 'R': []}
        raise last

    def _make(self):
        sh = Sheet(self.sid, number(self.si), self.meta['title'])
        sh.revisions = [list(r) for r in self.revisions]
        grid = Grid()
        self.partial, self.grid = sh, grid       # what was drawn when a layout fails (to look at it)
        self.homes = []
        self.text_boxes = []
        frame(sh, grid, self)
        self.layout()
        self.assign_ports()
        for c in sorted(self.blocks):
            self.blocks[c].draw(sh, grid, self.homes)
        self.place_local_ends(sh, grid)
        self.place_margins()
        self.margin_tip = {}
        for pp in self.pipes:
            for k in (0, 1):
                if (pp['code'], k) in self.margin:
                    self.margin_tip[(pp['code'], k)] = self.draw_margin(sh, grid, pp, k)
        for t in sh.texts:
            self.text_boxes.append(text_box(*t[:2], t[2], t[5], t[3], t[4]))
        # headers before their branches, then in code order (a stub's own end is on a header here)
        order, done = [], set()
        pending = sorted(self.pipes, key=lambda pp: (0 if pp['home'] else 1, pp['code']))
        for _ in range(len(pending) + 1):
            rest = []
            for pp in pending:
                deps = [e[1] for e in pp['ends'] if e[0] == 'tee']
                if all(d in done for d in deps):
                    order.append(pp)
                    done.add(pp['code'])
                else:
                    rest.append(pp)
            pending = rest
            if not pending:
                break
        if pending:
            raise LayoutError(f'{self.sid}: pipes joining each other in a loop: {[pp["code"] for pp in pending]}')
        # every end's approach is kept clear of other pipes until its own is routed
        self.corr_n = {}
        for pp in order:
            if (pp['code'], 0) in self.local or (pp['code'], 1) in self.local:
                continue
            for k, e in enumerate(self.end_cells(grid, pp)):
                if e[0] == 'pt':
                    for ci, cj in self.corridor(grid, pp, k, e, reserve=True):
                        grid.blocked[cj * grid.nx + ci] = 1
        drawn_pipes = {}
        for pp in order:
            self.route_pipe(sh, grid, pp, drawn_pipes)
        # labels and flow arrows once every pipe is routed (a label placed early would stand in a later pipe's way)
        cuts = [c for pp in order for c in pp['crossings'] + pp['tees']]
        for pp in order:
            segs, taken = pp['segs'], pp['taken']
            for c in cuts:
                for si, (a, b, s0, L) in enumerate(segs):
                    if point_on(c, a, b):
                        t = math.dist(a, c)
                        taken.append((si, t - 2.0, t + 2.0))
        for pp in order:
            self._label(sh, grid, pp, pp['segs'], pp['taken'], pp['cells'])
        for pp in order:
            self._arrow(sh, grid, pp, pp['segs'], pp['taken'])
        check_sheet(sh)
        return sh


def simplify(pts):
    out = [pts[0]]
    for p in pts[1:]:
        if math.dist(p, out[-1]) < 1e-6:
            continue
        if len(out) >= 2:
            a, b = out[-2], out[-1]
            if abs((b[0] - a[0]) * (p[1] - b[1]) - (b[1] - a[1]) * (p[0] - b[0])) < 1e-6:
                out[-1] = p
                continue
        out.append(p)
    return out


def point_on(c, a, b):
    return abs(math.dist(a, c) + math.dist(c, b) - math.dist(a, b)) < 1e-6


def diamond(c, r):
    x, y = c
    return [(x - r, y), (x, y - r), (x + r, y), (x, y + r)]


def break_at(pts, cuts, gap):
    """The polyline in pieces, with a gap round each point where it crosses an earlier line."""
    pieces, cur = [], [pts[0]]
    for a, b in zip(pts, pts[1:]):
        L = math.dist(a, b)
        here = sorted((math.dist(a, c), c) for c in cuts if point_on(c, a, b) and 0 < math.dist(a, c) < L)
        for t, c in here:
            ux, uy = (b[0] - a[0]) / L, (b[1] - a[1]) / L
            cur.append((c[0] - ux * gap, c[1] - uy * gap))
            pieces.append(cur)
            cur = [(c[0] + ux * gap, c[1] + uy * gap)]
        cur.append(b)
    pieces.append(cur)
    return [simplify(p) for p in pieces if len(p) >= 2 and math.dist(p[0], p[-1]) > 1e-6]


# ================================================================ frame, title block, revisions

def frame(sh, grid, gen):
    o = '#frame'
    x0, y0, x1, y1 = FRAME
    sh.line([(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)], 0.7, 0, o)
    sh.line([(0, 0), (SHEET_W, 0), (SHEET_W, SHEET_H), (0, SHEET_H), (0, 0)], 0.25, 0, o)
    # the grid references along the frame (ISO 5457): columns 1-12, rows A-H
    for k in range(13):
        x = x0 + (x1 - x0) * k / 12
        sh.line([(x, y0), (x, y0 - 4)], 0.25, 0, o)
        sh.line([(x, y1), (x, y1 + 4)], 0.25, 0, o)
        if k < 12:
            cx = x + (x1 - x0) / 24
            sh.text(cx, y0 - 1.0, 2.5, str(k + 1), 0, 1, o)
            sh.text(cx, y1 + 3.5, 2.5, str(k + 1), 0, 1, o)
    for k in range(9):
        y = y0 + (y1 - y0) * k / 8
        sh.line([(x0, y), (x0 - 4, y)], 0.25, 0, o)
        sh.line([(x1, y), (x1 + 4, y)], 0.25, 0, o)
        if k < 8:
            cy = y + (y1 - y0) / 16 + 1.25
            sh.text(x0 - 2.0, cy, 2.5, 'ABCDEFGH'[k], 0, 1, o)
            sh.text(x1 + 5.0, cy, 2.5, 'ABCDEFGH'[k], 0, 1, o)
    # the sheet's title, large, top left (read at a glance when zoomed out)
    sh.text(x0 + 6.0, y0 + 12.0, 7.0, gen.meta['title'], 0, 0, o)
    title_block(sh, gen)
    grid.block((x0 + 4, y0 + 2, x0 + 6 + F.width(gen.meta['title'].upper(), 7.0) + 2, y0 + 14), 0.5)
    grid.block(REVS, 0.5)
    grid.block(TITLE, 0.5)
    # nothing routes through the frame's margins
    grid.block((0, 0, SHEET_W, y0 + 1), 0)
    grid.block((0, y1 - 1, SHEET_W, SHEET_H), 0)
    grid.block((0, 0, x0 + 1, SHEET_H), 0)
    grid.block((x1 - 1, 0, SHEET_W, SHEET_H), 0)


def title_block(sh, gen):
    o = '#title'
    x0, y0, x1, y1 = TITLE
    sh.line([(x0, y0), (x1, y0), (x1, y1), (x0, y1), (x0, y0)], 0.5, 0, o)
    rows = [y0 + 12, y0 + 24, y0 + 36, y0 + 46]
    for y in rows:
        sh.line([(x0, y), (x1, y)], 0.25, 0, o)
    sh.line([(x0 + 120, y0 + 36), (x0 + 120, y1)], 0.25, 0, o)
    sh.line([(x0 + 150, y0 + 36), (x0 + 150, y1)], 0.25, 0, o)
    plant = gen.plant.get('title', 'Generic plant').upper()
    sh.text(x0 + 3, y0 + 5.0, 2.0, 'PLANT', 0, 0, o)
    sh.text(x0 + 3, y0 + 10.5, 3.5, plant, 0, 0, o)
    sh.text(x0 + 3, y0 + 17.0, 2.0, 'TITLE', 0, 0, o)
    t = gen.meta['title'].upper()
    sh.text(x0 + 3, y0 + 22.5, 3.0 if F.width(t, 3.0) < 178 else 2.2, t, 0, 0, o)
    sh.text(x0 + 3, y0 + 29.0, 2.0, 'GENERATED FROM THE CONTENT BY WALKDOWN PLANT. NOT TO SCALE. NO REAL PLANT.', 0, 0, o)
    sh.text(x0 + 3, y0 + 33.5, 2.0, 'SYMBOLS AFTER ISO 10628-2 AND ISA-5.1. CODES AFTER THE KKS.', 0, 0, o)
    sh.text(x0 + 3, y0 + 40.0, 2.0, 'DRAWING NUMBER', 0, 0, o)
    sh.text(x0 + 3, y0 + 45.0, 4.0, number(gen.si), 0, 0, o)
    sh.text(x0 + 123, y0 + 40.0, 2.0, 'REV', 0, 0, o)
    sh.text(x0 + 135, y0 + 45.0, 4.0, gen.revisions[-1][0], 0, 1, o)
    sh.text(x0 + 153, y0 + 40.0, 2.0, 'SHEET', 0, 0, o)
    sh.text(x0 + 167, y0 + 45.0, 3.0, '%d OF %d' % (gen.si + 1, len(gen.sheets_meta)), 0, 1, o)
    sh.text(x0 + 3, y0 + 52.5, 2.0, 'A1 841 X 594 MM', 0, 0, o)
    # the revision table
    rx0, ry0, rx1, ry1 = REVS
    sh.line([(rx0, ry0), (rx1, ry0), (rx1, ry1), (rx0, ry1), (rx0, ry0)], 0.25, 0, o)
    sh.line([(rx0 + 14, ry0), (rx0 + 14, ry1)], 0.25, 0, o)
    sh.text(rx0 + 2, ry1 - 2.0, 2.0, 'REV', 0, 0, o)
    sh.text(rx0 + 16, ry1 - 2.0, 2.0, 'DESCRIPTION', 0, 0, o)
    sh.line([(rx0, ry1 - 5), (rx1, ry1 - 5)], 0.25, 0, o)
    y = ry1 - 7.5
    for rev, text in reversed(gen.revisions[-4:]):
        sh.text(rx0 + 7, y, 2.0, rev, 0, 1, o)
        sh.text(rx0 + 16, y, 2.0, F_trim(text, 76), 0, 0, o)
        y -= 5.5


# ================================================================ the legend sheet

ISA_FIRST = [('A', 'Analysis'), ('B', 'Burner, flame'), ('F', 'Flow'), ('L', 'Level'), ('P', 'Pressure'),
             ('S', 'Speed'), ('T', 'Temperature'), ('V', 'Vibration'), ('W', 'Weight, force'), ('Z', 'Position')]
ISA_AFTER = [('E', 'Element (sensor)'), ('G', 'Glass (sight gauge)'), ('I', 'Indicator'), ('T', 'Transmitter'),
             ('IT', 'Indicating transmitter (analyser)')]


def legend(gen, used):
    sh = Sheet(gen.sid, number(gen.si), gen.meta['title'])
    sh.revisions = [list(r) for r in gen.revisions]
    grid = Grid()
    frame(sh, grid, gen)
    o = '#legend'
    sh.text(40.0, 50.0, 4.0, 'EQUIPMENT', 0, 0, o)
    shown, row, cols = set(), [], []
    for kind in sorted(used):
        if kind not in S.EQUIPMENT:
            continue
        fn = S.EQUIPMENT[kind][0]
        if fn in shown:
            continue
        shown.add(fn)
        row.append(kind)
    # three columns of 130 mm: the symbol in a 64 mm cell, its name beside it in lines of 24 characters
    col_x = (40.0, 172.0, 304.0, 436.0)
    y = 60.0
    for r in range(0, len(row), 4):
        kinds = row[r:r + 4]
        sizes = []
        for kind in kinds:
            _, w, h = S.EQUIPMENT[kind]
            if kind == 'hrsg':
                w, h = 50.0, 30.0
            sizes.append((w, min(h, 36.0)))
        rh = max(s[1] for s in sizes) + 8.0
        for ci, kind in enumerate(kinds):
            fn = S.EQUIPMENT[kind][0]
            w, h = sizes[ci]
            cx, cy = col_x[ci] + 33.0, y + rh / 2
            fn(S.Pen(sh, cx, cy, o), w, h)
            lines = wrap(S.LEGEND.get(kind, kind.replace('_', ' ')).upper(), 24)
            ty = cy - (len(lines) - 1) * 2.0 + 1.2
            for t in lines:
                sh.text(col_x[ci] + 68.0, ty, 2.5, t, 0, 0, o)
                ty += 4.0
        y += rh
    # valves and inline items
    x0 = 590.0
    yy = 50.0
    sh.text(x0, yy, 4.0, 'VALVES AND INLINE ITEMS', 0, 0, o)
    yy += 12.0
    for kind in sorted(k for k in used if k in S.VALVES) + (['orifice'] if 'flow_element' in used else []):
        sh.line([(x0, yy), (x0 + 30, yy)], S.THICK, 0, o)
        pn = S.Pen(sh, x0 + 15, yy, o)
        (S.orifice if kind == 'orifice' else S.VALVES[kind])(pn)
        sh.text(x0 + 38, yy + 1.2, 2.5, S.LEGEND[kind], 0, 0, o)
        yy += 14.0
    # lines
    yy += 4.0
    sh.text(x0, yy, 4.0, 'LINES', 0, 0, o)
    yy += 10.0
    for w, text in ((S.THICK + 0.2, 'Process pipe DN 300 and over'), (S.THICK, 'Process pipe'),
                    (S.THIN, 'Instrument process connection')):
        sh.line([(x0, yy), (x0 + 30, yy)], w, 0, o)
        sh.text(x0 + 38, yy + 1.2, 2.5, text, 0, 0, o)
        yy += 8.0
    sh.line([(x0, yy), (x0 + 12, yy)], S.THICK, 0, o)
    sh.line([(x0 + 18, yy), (x0 + 30, yy)], S.THICK, 0, o)
    sh.line([(x0 + 15, yy - 6), (x0 + 15, yy + 6)], S.THICK, 0, o)
    sh.text(x0 + 38, yy + 1.2, 2.5, 'Pipes crossing (the later one broken)', 0, 0, o)
    yy += 12.0
    sh.line([(x0, yy), (x0 + 30, yy)], S.THICK, 0, o)
    sh.line([(x0 + 15, yy), (x0 + 15, yy + 8)], S.THICK, 0, o)
    sh.fill(diamond((x0 + 15, yy), 0.9), o)
    sh.text(x0 + 38, yy + 1.2, 2.5, 'Tee: a branch joining a pipe', 0, 0, o)
    yy += 14.0
    sh.line([(x0, yy), (x0 + 30, yy)], S.THICK, 0, o)
    sh.fill([(x0 + 16.5, yy), (x0 + 13.5, yy - 1.2), (x0 + 13.5, yy + 1.2)], o)
    sh.text(x0 + 38, yy + 1.2, 2.5, 'Direction of flow', 0, 0, o)
    yy += 12.0
    pts = [(x0, yy - 3.5), (x0 + 28, yy - 3.5), (x0 + 32, yy), (x0 + 28, yy + 3.5), (x0, yy + 3.5), (x0, yy - 3.5)]
    sh.line(pts, S.THIN * 2, 0, o)
    sh.text(x0 + 14, yy + 1.0, 2.0, 'WDP-PID-003', 0, 1, o)
    sh.text(x0 + 38, yy + 1.2, 2.5, 'Off-sheet connector: the sheet the pipe continues on,', 0, 0, o)
    sh.text(x0 + 38, yy + 5.7, 2.5, 'with the code at its far end (tap it to go there)', 0, 0, o)
    yy += 16.0
    sh.line([(x0, yy), (x0 + 30, yy)], S.THICK, 0, o)
    sh.fill([(x0 + 30, yy), (x0 + 27, yy - 1.3), (x0 + 27, yy + 1.3)], o)
    sh.text(x0 + 38, yy + 1.2, 2.5, 'Open end: the pipe continues beyond the plant drawn', 0, 0, o)
    # instruments
    yy += 14.0
    sh.text(x0, yy, 4.0, 'INSTRUMENTS (ISA-5.1)', 0, 0, o)
    yy += 14.0
    S.bubble(S.Pen(sh, x0 + 14, yy, o), '10HAD30CP001', 'PT')
    sh.text(x0 + 38, yy - 1.0, 2.5, 'Field-mounted instrument: its letters over its KKS code', 0, 0, o)
    sh.text(x0 + 38, yy + 3.5, 2.5, '(here a pressure transmitter, 10HAD30CP001)', 0, 0, o)
    yy += 14.0
    sh.text(x0, yy, 2.5, 'FIRST LETTER', 0, 0, o)
    sh.text(x0 + 70, yy, 2.5, 'SUCCEEDING LETTERS', 0, 0, o)
    yy += 6.0
    for i in range(max(len(ISA_FIRST), len(ISA_AFTER))):
        if i < len(ISA_FIRST):
            sh.text(x0, yy, 2.5, ISA_FIRST[i][0], 0, 0, o)
            sh.text(x0 + 8, yy, 2.5, ISA_FIRST[i][1], 0, 0, o)
        if i < len(ISA_AFTER):
            sh.text(x0 + 70, yy, 2.5, ISA_AFTER[i][0], 0, 0, o)
            sh.text(x0 + 80, yy, 2.5, ISA_AFTER[i][1], 0, 0, o)
        yy += 5.0
    # how a KKS code reads (from the plant's own key table)
    kk = gen.plant.get('kks', {})
    if y > 470.0:
        raise LayoutError(f'legend: the equipment symbols reach {y:.0f} mm')
    kx, ky = x0, yy + 12.0
    sh.text(kx, ky, 4.0, 'HOW A CODE READS (KKS)', 0, 0, o)
    ky += 12.0
    ex = '10LAC10AP001'
    parts = [('1', 'unit', kk.get('units', {}).get('1', '')), ('0', 'common to the unit', ''),
             ('LAC', 'system', kk.get('systems', {}).get('LAC', '')), ('10', 'system number', ''),
             ('AP', 'equipment', kk.get('equipment', {}).get('AP', '')), ('001', 'equipment number', '')]
    sh.text(kx, ky, 6.0, ' '.join(p[0] for p in parts), 0, 0, o)
    ky += 9.0
    for p in parts:
        sh.text(kx + 4.0, ky, 2.5, F_trim('%s: %s%s' % (p[0], p[1], (', ' + p[2]) if p[2] else ''), 80), 0, 0, o)
        ky += 5.0
    for t in ('A measurement has C and a letter in place of the equipment letters:',
              'CP pressure, CT temperature, CL level, CF flow, and so on.', 'The card of each code says it in words.'):
        ky += 5.0
        sh.text(kx + 4.0, ky, 2.5, t, 0, 0, o)
    if ky > REVS[1] - 4.0:
        raise LayoutError(f'legend: the code key reaches {ky:.0f} mm')
    return sh


# ================================================================ the set, its checks, revisions

def check_sheet(sh, d=None):
    """The content check's rules for one sheet (REALISM.md §6.1.1): symbols apart, texts clear of each other and of
    other owners' lines and symbols. Raises LayoutError."""
    tb = [(text_box(x, y, h, t, a, al), t, o) for x, y, h, a, al, t, o in sh.texts]
    for i, (a, ta, oa) in enumerate(tb):
        for b, tb2, ob in tb[i + 1:]:
            if overlap(inflate(a, -0.15), inflate(b, -0.15)):
                raise LayoutError(f'{sh.id}: the texts {ta!r} and {tb2!r} overlap')
    sy = sorted(sh.symbols, key=lambda s: s[1])
    for i, (a, oa) in enumerate(sy):
        for b, ob in sy[i + 1:]:
            if overlap(inflate(a, -0.1), inflate(b, -0.1)):
                raise LayoutError(f'{sh.id}: the symbols of {oa} and {ob} overlap')
    for box, t, o in tb:
        base = o.split('#')[0]
        for b, ob in sh.symbols:
            if ob.split('#')[0] != base and sh.inside.get(base) != ob and overlap(inflate(box, -0.2), b):
                raise LayoutError(f'{sh.id}: the text {t!r} lies on the symbol of {ob}')
        for w, dash, pts, lo in sh.lines:
            if lo.split('#')[0] == base or lo.startswith('#') and o.startswith('#'):
                continue
            for p, q in zip(pts, pts[1:]):
                if seg_box(p, q, inflate(box, -0.2)):
                    raise LayoutError(f'{sh.id}: a line of {lo} crosses the text {t!r}')


def seg_box(p, q, b):
    """Whether the segment pq passes through the box (Liang-Barsky)."""
    x0, y0, x1, y1 = b
    t0, t1 = 0.0, 1.0
    dx, dy = q[0] - p[0], q[1] - p[1]
    for pv, qv in ((-dx, p[0] - x0), (dx, x1 - p[0]), (-dy, p[1] - y0), (dy, y1 - p[1])):
        if abs(pv) < 1e-12:
            if qv < 0:
                return False
        else:
            t = qv / pv
            if pv < 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1:
                return False
    return True


def make(data=DATA, revisions=None, areas_override=None):
    """Every sheet: ({sheet id: Sheet}, index dict). `revisions` {sheet id: [[rev, text], …]} for a revised set."""
    plant, areas, model_codes = load(data)
    if areas_override is not None:
        areas = areas_override
    items = items_of(areas)
    revisions = revisions or {}
    sheets, used = {}, set()
    homes = {}
    for i, meta in enumerate(SHEETS):
        if i == 0:
            continue
        g = Gen(plant, areas, i, items, SHEETS, revisions.get(meta['id']))
        sh = g.make()
        check_sheet(sh)
        sheets[meta['id']] = sh
        for c, box, home in sh.spots:
            if home:
                if c in homes:
                    raise LayoutError(f'{c} has a home on {homes[c]} and on {meta["id"]}')
                homes[c] = meta['id']
        used |= {it.kind for it in items.values() if g.home_of.get(it.code) == meta['id']}
        used |= {it.kind for pp in g.pipes for it in pp.get('inline', [])}
    g0 = Gen(plant, areas, 0, items, SHEETS, revisions.get('legend'))
    leg = legend(g0, used)
    check_sheet(leg)
    sheets['legend'] = leg
    # every drawn code has exactly one home (REALISM.md §6.1.1), and every code of the model a P&ID shows is drawn
    want = {c for c, it in items.items() if drawn(it, items)}
    missing = sorted(want - set(homes))
    if missing:
        raise LayoutError(f'codes with no home on any sheet: {missing[:20]}')
    unassigned = sorted(c for c in want if sheet_of_item(items[c], items) is None)
    if unassigned:
        raise LayoutError(f'codes no sheet takes: {unassigned[:20]}')
    absent = sorted(c for c in model_codes if c in items and drawn(items[c], items) and c not in homes)
    if absent:
        raise LayoutError(f'model codes not drawn: {absent[:20]}')
    index = {
        'format': 'walkdown-plant-drawings', 'version': 1,
        'sheets': [{'id': m['id'], 'number': number(i), 'title': m['title'], 'file': m['id'] + '.json'}
                   for i, m in enumerate(SHEETS)],
        'home': dict(sorted(homes.items())),
        'lettering': {'advance': F.ADVANCE, 'cap': F.CAP, 'glyphs': F.table()},
    }
    return sheets, index


def revise(old, new, rev, text):
    """A later revision of a sheet (REALISM.md §6.1.1): `new` made from the changed content with the revision table
    [old's rows + (rev, text)], and a cloud round every hot spot that is new, gone or moved since `old`. Returns new."""
    def homes(sh):
        return {c: b for c, b, h in sh.spots if h}
    a, b = homes(old), homes(new)
    clouds = []
    for c in sorted(set(a) | set(b)):
        if c not in b:
            clouds.append((rev, inflate(a[c], 3.0)))
        elif c not in a or any(abs(p - q) > 0.5 for p, q in zip(a[c], b[c])):
            clouds.append((rev, inflate(b[c], 3.0)))
    new.clouds = list(old.clouds) + clouds
    return new


def dump(obj):
    """Readable, stable JSON: a top-level list's items one per line."""
    def one(x):
        return json.dumps(x, ensure_ascii=False, separators=(',', ':'))
    lines = ['{']
    items = list(obj.items())
    for i, (k, v) in enumerate(items):
        end = ',' if i < len(items) - 1 else ''
        if isinstance(v, list) and v and k in ('lines', 'circles', 'fills', 'texts', 'spots', 'links', 'clouds', 'sheets'):
            lines.append(f' {json.dumps(k)}: [')
            for j, x in enumerate(v):
                lines.append('  ' + one(x) + (',' if j < len(v) - 1 else ''))
            lines.append(' ]' + end)
        else:
            lines.append(f' {json.dumps(k)}: {one(v)}{end}')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def files(data=DATA):
    """{file name: text} of the whole set."""
    sheets, index = make(data)
    out = {'index.json': dump(index)}
    for sid, sh in sheets.items():
        out[sid + '.json'] = dump(sh.data())
    return out


def main(argv):
    if len(argv) == 2 and argv[1] == '--check':
        made = files()
        print('drawings: %d sheets, %d bytes' % (len(made) - 1, sum(len(v) for v in made.values())))
        return 0
    if len(argv) != 2:
        print(__doc__)
        return 2
    out = argv[1]
    os.makedirs(out, exist_ok=True)
    made = files()
    for n in os.listdir(out):
        if n.endswith('.json') and n not in made:
            os.remove(os.path.join(out, n))
    for n, text in made.items():
        with open(os.path.join(out, n), 'w', encoding='utf-8') as f:
            f.write(text)
    print('drawings: %d sheets into %s' % (len(made) - 1, out))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
