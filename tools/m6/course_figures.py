"""The 16 animated course figures in the declarative model (docs/COURSES.md §9), converted from the hand-written
JavaScript in the HTML courses. Proof that the model can express them (decision 0025), and the starting point for
the re-authoring. Formulas are sampled into tables here, as the build tool will do.

  python3 tools/m6/course_figures.py json OUT.json            all figures, validated
  python3 tools/m6/course_figures.py svg OUTDIR [id …]         SVG frames of our evaluation at the check states
  python3 tools/m6/course_figures.py harness OUTDIR SRC.html   the originals at the same states (HTML pages)"""
import json, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from ref import courses as K

PI = math.pi


# ---------------------------------------------------------------- helpers mirroring the JS ones

def _style(el, fill=None, stroke=None, sw=None, op=None, dash=None, cap=None, join=None, tf=None, rx=None):
    for k, v in (('fill', fill), ('stroke', stroke), ('stroke_width', sw), ('opacity', op), ('dash', dash),
                 ('cap', cap), ('join', join), ('transform', tf), ('rx', rx)):
        if v is not None:
            el[k] = v
    return el


def R(x, y, w, h, **k): return _style({'rect': [x, y, w, h]}, **k)
def C(cx, cy, r, **k): return _style({'circle': [cx, cy, r]}, **k)
def EL(cx, cy, rx, ry, **k): return _style({'ellipse': [cx, cy, rx, ry]}, **k)


def LN(x1, y1, x2, y2, arrow=False, **k):
    e = _style({'line': [x1, y1, x2, y2]}, **k)
    if arrow:
        e['arrow'] = True
    return e


def POLY(pts, closed=False, **k):
    e = _style({'poly': [list(p) for p in pts]}, **k)
    if closed:
        e['closed'] = True
    return e


def PATH(d, **k): return _style({'path': d if isinstance(d, list) else parse_d(d)}, **k)


def T(txt, x, y, anchor=None, size=None, font=None, weight=None, fill=None, **k):
    e = {'text': txt, 'at': [x, y]}
    for kk, v in (('anchor', anchor), ('size', size), ('font', font), ('weight', weight)):
        if v is not None and v != {'anchor': 'start', 'size': 12, 'font': 'body', 'weight': 400}[kk]:
            e[kk] = v
    if fill is not None and fill != 'ink':
        e['fill'] = fill
    return _style(e, **k)


def LAB(txt, x1, y1, x2, y2, anchor=None):
    e = {'label': txt, 'at': [x1, y1], 'to': [x2, y2]}
    if anchor == 'end':
        e['anchor'] = 'end'
    return e


def G(children, clip=None, **k):
    e = {'group': children}
    if clip is not None:
        e['clip'] = clip
    return _style(e, **k)


def FLOW(**k): return {'flow': k}


METAL = dict(fill='surface', stroke='ink', sw=2)
WATER = 'accent'


def hpipe(x1, x2, y1, y2):
    return [R(x1, y1 - 6, x2 - x1, 6, fill='muted'), R(x1, y2, x2 - x1, 6, fill='muted')]


def arrow(x1, y1, x2, y2, c, w=2): return LN(x1, y1, x2, y2, arrow=True, stroke=c, sw=w)


def parse_d(d):
    """Absolute and relative M/L/C/Z from the figures' SVG path strings."""
    import re
    toks = re.findall(r'[MLCZmlcz]|-?[\d.]+', d)
    out, i, cmd, cx, cy, sx, sy = [], 0, None, 0.0, 0.0, 0.0, 0.0
    while i < len(toks):
        if toks[i].isalpha():
            cmd = toks[i]
            i += 1
            if cmd in 'Zz':
                out.append(['Z'])
                cx, cy = sx, sy
                continue
        n = {'M': 2, 'L': 2, 'C': 6}[cmd.upper()]
        v = [float(x) for x in toks[i:i + n]]
        i += n
        if cmd.islower():
            v = [x + (cx if j % 2 == 0 else cy) for j, x in enumerate(v)]
        v = [int(x) if x == int(x) else x for x in v]
        out.append([cmd.upper()] + v)
        cx, cy = v[-2], v[-1]
        if cmd.upper() == 'M':
            sx, sy = cx, cy
            cmd = 'l' if cmd == 'm' else 'L'
    return out


def r4(x):
    x = round(x, 4)
    return int(x) if x == int(x) else x


def tab(of, fn, xs, step=False):
    n = {'of': of, 'table': [[r4(x), r4(fn(x))] for x in xs]}
    if step:
        n['step'] = True
    return n


def lin(a, b, n):
    return [a + (b - a) * i / (n - 1) for i in range(n)]


def steptab(of, pts):
    return {'of': of, 'table': [[r4(x), r4(y)] for x, y in pts], 'step': True}


def ease(x):
    return 0 if x < 0 else 1 if x > 1 else x * x * (3 - 2 * x)


def lerp(a, b, k): return a + (b - a) * k


def clamp(v, a, b): return max(a, min(b, v))


def ping(t):
    return 0 if t < 0.1 else ease((t - 0.1) / 0.35) if t < 0.45 else 1 if t < 0.6 else \
        1 - ease((t - 0.6) / 0.35) if t < 0.95 else 0


PING_X = sorted(set([0, 0.1] + lin(0.1, 0.45, 25) + [0.6] + lin(0.6, 0.95, 25) + [1]))
PING = {'of': 't', 'table': [[r4(x), r4(ping(x))] for x in PING_X]}


def hsl_hex(h, s, l):
    import colorsys
    r, g, b = colorsys.hls_to_rgb((h % 360) / 360, l / 100, s / 100)
    return '#%02x%02x%02x' % tuple(int(math.floor(c * 255 + 0.5)) for c in (r, g, b))


def ids_values(vals):
    return [[n, v] for n, v in vals]


# ---------------------------------------------------------------- the figures

F = {}


def fig(id, title, w, h, period, caption, alt, scene, values=(), slider=None, toggles=None, modes=None, status=None):
    f = {'title': title, 'caption': [caption], 'alt': alt, 'w': w, 'h': h, 'period': period,
         'values': [list(v) for v in values], 'scene': scene}
    if slider:
        f['slider'] = slider
    if toggles:
        f['toggles'] = toggles
    if modes:
        f['modes'] = modes
    if status is not None:
        f['status'] = status
    F[id] = f


def gate():
    V = [
        ('gy', tab('v', lambda f: 236 - 78 * f, [0, 1])),
        ('stem_y', tab('v', lambda f: 236 - 78 * f - 150, [0, 1])),
        ('lgy', tab('v', lambda f: 236 - 78 * f + 42, [0, 1])),
        ('lsy', tab('v', lambda f: min(236 - 78 * f - 10, 140), [0, 0.5, 1])),
        ('bottom', tab('v', lambda f: 236 - 78 * f + 84, [0, 1])),
        ('q100', tab('v', lambda f: 100 * (1 - (1 - f) ** 2.2), lin(0, 1, 41))),
        ('spd', tab('v', lambda f: 160 * (1 - (1 - f) ** 2.2), lin(0, 1, 41))),
        ('pop', steptab('v', [(0, .35), (0.01, .9)])),
        ('v100', {'product': ['v', 100]}),
    ]
    xs = lin(0, 1, 181)
    for n, fn in (('sx1', lambda f: 300 + 48 * math.cos(f * PI * 6)), ('sy1', lambda f: 106 + 10 * math.sin(f * PI * 6)),
                  ('sx2', lambda f: 300 - 48 * math.cos(f * PI * 6)), ('sy2', lambda f: 106 - 10 * math.sin(f * PI * 6))):
        V.append((n, tab('v', fn, xs)))
    bg = [R(20, 250, 600, 60, fill=WATER, op=.18), *hpipe(20, 240, 250, 310), *hpipe(360, 620, 250, 310),
          R(240, 218, 120, 124, rx=18, **METAL), R(254, 232, 92, 96, fill=WATER, op=.18),
          R(240, 250, 14, 60, fill=WATER, op=.18), R(346, 250, 14, 60, fill=WATER, op=.18),
          R(272, 150, 56, 70, **METAL), R(284, 158, 32, 64, fill='ground'),
          R(280, 244, 8, 72, fill='ink'), R(312, 244, 8, 72, fill='ink'),
          PATH('M272,150 L286,110 M328,150 L314,110', stroke='ink', sw=4)]
    ys = [256 + (i * 37) % 48 for i in range(30)]
    flow = FLOW(count=30, routes=[{'path': [['M', 20, 0], ['L', 620, 0]]}], lanes=[[0, y] for y in ys],
                speed='spd', opacity='pop', hide=[{'rect': [280, 0, 320, 'bottom'], 'when': 1}])
    scene = [G(bg), flow,
             R(297, 'stem_y', 6, 150, fill='ink'),
             R(286, 150, 10, 12, fill='alarm_fill', stroke='ink'), R(304, 150, 10, 12, fill='alarm_fill', stroke='ink'),
             R(288, 'gy', 24, 84, rx=3, fill='muted', stroke='ink', sw=1.5),
             EL(300, 106, 48, 10, stroke='act', sw=5),
             LN('sx1', 'sy1', 'sx2', 'sy2', stroke='act', sw=3),
             arrow(30, 234, 90, 234, 'accent'), T('Flow', 30, 226, fill='accent', weight=700),
             G([LAB('Handwheel', 348, 106, 440, 70), LAB('Stem (spindle), rises as it opens', 303, 'lsy', 440, 100),
                LAB('Gland packing (stem seal)', 314, 156, 440, 132), LAB('Bonnet (lid)', 328, 196, 440, 166),
                LAB('Gate (shut-off device)', 312, 'lgy', 440, 232), LAB('Seats', 320, 300, 440, 300),
                LAB('Body (casing)', 356, 334, 440, 348)])]
    fig('gate', 'Gate valve cutaway', 640, 400, 9,
        'Rising-stem gate valve. Drag the slider or press play. The gate slides straight across the flow and wedges '
        'between two seats; most of the flow returns in the first part of the stroke, which is why gate valves are for '
        'isolation, not throttling.',
        'Cutaway of a rising-stem gate valve in a pipe: handwheel, stem, packing, bonnet, a gate that slides down '
        'between two seats, and water flowing through.',
        scene, V, slider={'label': 'Opening', 'init': 0.35, 'drive': PING, 'text': '{v100}% open'},
        status='{v100}% open → about {q100}% of full flow')


def globe():
    route = parse_d('M20,280 L210,280 C250,282 262,330 300,322 C306,318 300,300 300,288 C300,262 322,262 350,262 '
                    'C380,262 390,280 420,280 L620,280')
    pts, segs, L = K.flatten(route, lambda r: r)
    acc, ks = 0.0, []
    for i, s in enumerate(segs):       # k where x crosses 215 and 390 (the channel)
        x0, x1 = pts[i][0], pts[i + 1][0]
        for xc in (215, 390):
            if (x0 - xc) * (x1 - xc) < 0:
                ks.append((acc + s * (xc - x0) / (x1 - x0)) / L)
        acc += s
    a, b = ks[0], ks[-1]
    V = [('py', tab('v', lambda f: 276 - 40 * f, [0, 1])), ('stem_y', tab('v', lambda f: 96 - 40 * f, [0, 1])),
         ('lpy', tab('v', lambda f: 284 - 40 * f, [0, 1])), ('spd', {'product': ['v', 150]}),
         ('pop', steptab('v', [(0, .3), (0.01, .9)])), ('v100', {'product': ['v', 100]})]
    xs = lin(0, 1, 121)
    for n, fn in (('sx1', lambda f: 300 + 48 * math.cos(f * PI * 4)), ('sy1', lambda f: 104 + 10 * math.sin(f * PI * 4)),
                  ('sx2', lambda f: 300 - 48 * math.cos(f * PI * 4)), ('sy2', lambda f: 104 - 10 * math.sin(f * PI * 4))):
        V.append((n, tab('v', fn, xs)))
    bg = [R(20, 250, 600, 60, fill=WATER, op=.18), *hpipe(20, 200, 250, 310), *hpipe(400, 620, 250, 310),
          EL(300, 280, 112, 80, **METAL), EL(300, 280, 98, 66, fill='surface'), EL(300, 280, 98, 66, fill=WATER, op=.18),
          PATH('M236,232 C250,236 262,292 278,292 M322,292 C338,292 352,318 372,330', stroke='ink', sw=9, cap='round'),
          R(262, 288, 18, 9, fill='ink'), R(320, 288, 18, 9, fill='ink'), R(274, 150, 52, 54, **METAL),
          PATH('M274,150 L286,110 M326,150 L314,110', stroke='ink', sw=4)]
    offs = [((i * 13) % 20) - 10 for i in range(34)]
    flow = FLOW(count=34, routes=[{'path': route}], lanes=[[0, o] for o in offs], speed='spd', opacity='pop',
                along={'lane': [[0, 1], [r4(a), 1], [r4(a), .35], [r4(b), .35], [r4(b), 1], [1, 1]]})
    scene = [G(bg), flow, R(297, 'stem_y', 6, 180, fill='ink'),
             R(286, 150, 10, 12, fill='alarm_fill', stroke='ink'), R(304, 150, 10, 12, fill='alarm_fill', stroke='ink'),
             R(272, 'py', 56, 16, rx=4, fill='muted', stroke='ink', sw=1.5), EL(300, 104, 48, 10, stroke='act', sw=5),
             LN('sx1', 'sy1', 'sx2', 'sy2', stroke='act', sw=3),
             arrow(30, 234, 90, 234, 'accent'), T('Flow', 30, 226, fill='accent', weight=700),
             G([LAB('Handwheel', 348, 104, 440, 64), LAB('Stem', 303, 130, 440, 94), LAB('Gland packing', 314, 156, 440, 124),
                LAB('Bonnet', 326, 182, 440, 154), LAB('Plug (disc)', 328, 'lpy', 450, 214), LAB('Seat', 266, 292, 200, 234, 'end'),
                LAB('Partition wall forces the S-path', 368, 326, 440, 378), LAB('Body', 200, 330, 150, 380, 'end')])]
    fig('globe', 'Globe valve cutaway', 640, 400, 9,
        'Globe valve. Flow is forced through an S-shaped path and up through a horizontal seat; the plug lifts off the '
        'seat. Flow rises steadily with lift, so globes throttle well, at the cost of a higher pressure drop than a '
        'gate valve.',
        'Cutaway of a globe valve: water takes an S-shaped path through a horizontal seat, and a plug lifts off it.',
        scene, V, slider={'label': 'Lift', 'init': 0.4, 'drive': PING, 'text': '{v100}% lift'},
        status='{v100}% lift → about {v100}% flow (roughly linear)')


def check():
    V = [('target', steptab('t', [(0, 62), (0.45, 0)])),
         ('ang', {'follow': 'target', 'rate': 3, 'rate_down': 9, 'init': 0}),
         ('nang', {'product': ['ang', -1]}),
         ('ldx', tab('ang', lambda a: 300 + 54 * math.sin(a * PI / 180), lin(0, 62, 32))),
         ('ldy', tab('ang', lambda a: 96 + 54 * math.cos(a * PI / 180), lin(0, 62, 32))),
         ('fwd', steptab('t', [(0, 1), (0.45, 0)])),
         ('back', steptab('t', [(0, 1), (0.55, 0)])),
         ('ax1', steptab('t', [(0, 30), (0.45, 110)])), ('ax2', steptab('t', [(0, 110), (0.45, 30)])),
         ('up_spd', steptab('t', [(0, 150), (0.45, 0)])),
         ('down_spd', steptab('t', [(0, 150), (0.45, -40), (0.55, -90)]))]
    ys = [126 + (i * 29) % 48 for i in range(30)]
    bg = [R(240, 70, 150, 140, rx=20, **METAL), R(20, 120, 600, 60, fill=WATER, op=.18),
          R(252, 82, 126, 116, fill=WATER, op=.18), *hpipe(20, 240, 120, 180), *hpipe(390, 620, 120, 180),
          PATH('M296,112 L304,128 M296,188 L304,172', stroke='ink', sw=7), C(300, 96, 6, fill='ink')]
    scene = [G(bg),
             FLOW(count=15, routes=[{'path': [['M', 20, 0], ['L', 312, 0]]}], lanes=[[0, y] for y in ys[::2]], speed='up_spd'),
             FLOW(count=15, routes=[{'path': [['M', 312, 0], ['L', 620, 0]]}], lanes=[[0, y] for y in ys[1::2]],
                  speed='down_spd', reverse='pile', pile=20),
             R(294, 96, 10, 86, rx=4, fill='act', tf=[{'rotate': ['nang', 300, 96]}]),
             LN('ax1', 230, 'ax2', 230, arrow=True, stroke='accent', sw=3),
             T([{'when': 'fwd', 'text': 'Forward flow'}, {'text': 'Reverse pressure'}], 30, 252, fill='accent', weight=700),
             G([LAB('Hinge pin', 300, 96, 430, 50), LAB('Disc (flap)', 'ldx', 'ldy', 430, 80), LAB('Seat', 302, 176, 430, 250),
                LAB('Cover (body)', 250, 76, 180, 40, 'end')])]
    fig('check', 'Swing check valve', 640, 300, 7,
        'Swing check (non-return) valve. Forward flow pushes the hinged disc open; when flow reverses, the disc swings '
        'back onto its seat and blocks the backflow. No operator or signal is involved.',
        'Swing check valve: a hinged disc swings open with forward flow and falls back onto its seat when the flow '
        'reverses.', scene, V,
        status=[{'when': 'fwd', 'text': 'Forward flow pushes the disc open'},
                {'when': 'back', 'text': 'Flow reverses: the disc swings back'},
                {'text': 'Disc on seat: reverse flow is blocked'}])


def quarter():
    xs = lin(0, 1, 91)
    s = lambda f: math.sin(f * PI / 2)
    V = [('a', {'product': ['v', 90]}), ('ball_rot', tab('v', lambda f: 90 - 90 * f, [0, 1])),
         ('dx1', tab('v', lambda f: 155 - 38 * s(f), xs)), ('dy1', tab('v', lambda f: 150 - 38 * math.cos(f * PI / 2), xs)),
         ('dx2', tab('v', lambda f: 155 + 38 * s(f), xs)), ('dy2', tab('v', lambda f: 150 + 38 * math.cos(f * PI / 2), xs)),
         ('qa', tab('v', lambda f: s(f) ** 1.6, xs)), ('qb', tab('v', lambda f: max(0, s(f)) ** 2.4, xs)),
         ('spa', {'product': ['qa', 140]}), ('spb', {'product': ['qb', 140]}),
         ('opa', steptab('qa', [(0, .3), (0.02, .9)])), ('opb', steptab('qb', [(0, .3), (0.02, .9)])),
         ('shut', steptab('a', [(0, 1), (60, 0)])),
         ('closed', steptab('a', [(0, 1), (2, 0)])), ('open', steptab('a', [(0, 0), (88.0001, 1)]))]
    bg = [R(20, 110, 270, 80, fill=WATER, op=.18), *hpipe(20, 290, 110, 190),
          R(350, 110, 270, 80, fill=WATER, op=.18), *hpipe(350, 620, 110, 190),
          T('Butterfly', 155, 60, 'middle', 16, 'display', 600), T('Ball', 485, 60, 'middle', 16, 'display', 600)]
    scene = [G(bg),
             FLOW(count=16, routes=[{'path': [['M', 20, 0], ['L', 290, 0]]}],
                  lanes=[[0, 116 + (i * 31) % 68] for i in range(16)], speed='spa', opacity='opa'),
             FLOW(count=16, routes=[{'path': [['M', 350, 0], ['L', 620, 0]]}],
                  lanes=[[0, 128 + (i * 23) % 44] for i in range(16)], speed='spb', opacity='opb',
                  hide=[{'rect': [427, 0, 543, 400], 'when': 'shut'}]),
             LN('dx1', 'dy1', 'dx2', 'dy2', stroke='act', sw=9, cap='round'), C(155, 150, 7, fill='ink'),
             G([C(485, 150, 58, fill='muted', stroke='ink', sw=2), R(427, 128, 116, 44, fill='surface'),
                R(427, 128, 116, 44, fill=WATER, op=.25)], tf=[{'rotate': ['ball_rot', 485, 150]}]),
             R(418, 104, 10, 92, fill='ink'), R(542, 104, 10, 92, fill='ink'),
             T('shaft', 170, 240, fill='muted'), T('seats', 560, 240, fill='muted')]
    fig('quarter', 'Butterfly and ball valves', 640, 300, 8,
        'Quarter-turn valves, seen in section along the pipe. Left: a butterfly disc turns on a shaft in the flow; it '
        'is never fully out of the stream. Right: a ball with a bore; at 90° the bore lines up with the pipe and '
        'the valve is fully open.',
        'Two quarter-turn valves in section: a butterfly disc turning on its shaft, and a ball whose bore lines up '
        'with the pipe when open.', scene, V,
        slider={'label': 'Turn', 'init': 0.5, 'drive': PING, 'text': '{a}° of 90°'},
        status=[{'when': 'closed', 'text': '{a}° turned: closed'}, {'when': 'open', 'text': '{a}° turned: fully open'},
                {'text': '{a}° turned: partly open'}])


def safety():
    P = lambda t: 85 + 15 * (t / 0.45) if t < 0.45 else 100 - 7 * ease((t - 0.45) / 0.25) if t < 0.7 else \
        93 + 2 * ((t - 0.7) / 0.3)
    cx0, cx1, cy0, cy1 = 470, 640, 70, 250
    py = lambda p: cy1 - (p - 80) / 25 * (cy1 - cy0)
    tx = sorted(set(lin(0, 0.45, 10) + lin(0.45, 0.7, 26) + lin(0.7, 1, 7)))
    V = [('open', steptab('t', [(0, 0), (0.45, 1), (0.7, 0)])),
         ('lift', {'follow': 'open', 'rate': 18, 'rate_down': 10, 'init': 0}),
         ('dy', tab('lift', lambda l: 236 - 20 * l, [0, 1])),
         ('ldy', tab('lift', lambda l: 243 - 20 * l, [0, 1])),
         ('p', tab('t', P, tx)), ('dotx', tab('t', lambda t: cx0 + t * (cx1 - cx0), [0, 1])),
         ('doty', tab('t', lambda t: py(P(t)), tx)), ('clipw', tab('t', lambda t: 6 + t * (cx1 - cx0), [0, 1])),
         ('blow', steptab('lift', [(0, 0), (0.3, 1)])), ('puff_op', {'product': ['blow', 1]}),
         ('ups_op', {'product': ['blow', .7]}),
         ('is_open', steptab('lift', [(0, 0), (0.5, 1)])), ('reseated', steptab('t', [(0, 0), (0.7, 1)]))]
    spring = []
    for i in range(13):
        name = f'sp{i}'
        V.append((name, tab('lift', lambda l, i=i: 102 + (236 - 20 * l - 2 - 102) * i / 12, [0, 1])))
        spring.append([190 if i in (0, 12) else (168 if i % 2 else 212), name])
    bg = [R(150, 250, 80, 150, fill='sunk', stroke='ink', sw=2),
          PATH('M110,180 L320,180 L320,200 L440,200 L440,260 L320,260 L320,320 L110,320 Z', fill='surface', stroke='ink', sw=2),
          PATH('M126,196 L304,196 L304,214 L440,214 L440,246 L304,246 L304,304 L126,304 Z', fill='sunk'),
          R(160, 250, 60, 150, fill='sunk'), R(150, 244, 14, 10, fill='ink'), R(216, 244, 14, 10, fill='ink'),
          R(150, 80, 80, 100, **METAL), R(176, 44, 28, 36, **METAL), R(184, 84, 12, 18, fill='muted', stroke='ink'),
          LN(204, 56, 262, 40, stroke='ink', sw=4, cap='round'),
          T('from vessel', 190, 414, 'middle', 11, fill='muted')]
    curve = [[r4(cx0 + t * (cx1 - cx0)), r4(py(P(t)))] for t in lin(0, 1, 81)]
    scene = [G(bg), POLY(spring, stroke='act', sw=3), LN(190, 60, 190, 'dy', stroke='ink', sw=4),
             R(156, 'dy', 68, 14, rx=3, fill='muted', stroke='ink', sw=1.5),
             FLOW(count=22, routes=[{'path': [['M', 230, 230], ['L', 460, 230]]}],
                  lanes=[[0, r4(math.sin(i * 1.7) * 12)] for i in range(22)], speed=207, r=1, fill='muted',
                  opacity='puff_op', along={'lane': [[0, 0], [1, 1]], 'r': [[0, 3], [1, 9]], 'opacity': [[0, .7], [1, 0]]}),
             FLOW(count=10, routes=[{'path': [['M', 172, 396], ['L', 172, 256]]}], lanes=[[(i % 4) * 12, 0] for i in range(4)],
                  speed=112, fill='muted', opacity='ups_op'),
             G([LAB('Cap', 178, 56, 130, 40, 'end'), LAB('Lifting lever (test)', 250, 44, 290, 30),
                LAB('Adjusting screw', 184, 94, 130, 90, 'end'), LAB('Spring', 170, 140, 130, 136, 'end'),
                LAB('Spindle', 190, 170, 130, 176, 'end'), LAB('Disc (valve plate)', 156, 'ldy', 100, 222, 'end'),
                LAB('Seat', 150, 250, 100, 262, 'end'), LAB('Outlet', 420, 230, 400, 290)]),
             LN(cx0, cy0, cx0, cy1, stroke='muted'), LN(cx0, cy1, cx1, cy1, stroke='muted'),
             LN(cx0, r4(py(100)), cx1, r4(py(100)), stroke='act', dash=[4, 3]),
             T('set 100%', cx1, r4(py(100) - 5), 'end', 11, fill='act'),
             LN(cx0, r4(py(93)), cx1, r4(py(93)), stroke='alarm', dash=[4, 3]),
             T('reseat 93%', cx1, r4(py(93) + 14), 'end', 11, fill='alarm'),
             T('Pressure under the disc', cx0, cy0 - 12, fill='muted'),
             T('time →', cx1, cy1 + 16, 'end', 11, fill='muted'),
             G([POLY(curve, stroke='accent', sw=2.5)], clip={'rect': [cx0 - 3, 0, 'clipw', 420]}),
             C('dotx', 'doty', 5, fill='accent')]
    fig('safety', 'Spring-loaded safety valve', 660, 420, 10,
        'Spring-loaded safety valve. Pressure under the disc rises until it overcomes the spring at the set pressure; '
        'the valve pops fully open, blows, and reseats only when pressure has fallen a few percent below set (the '
        'blowdown). The adjusting screw sets the spring force and so the set pressure.',
        'Spring-loaded safety valve beside a chart of the pressure under its disc: the disc lifts at the set '
        'pressure and reseats a few percent below it.', scene, V,
        status=[{'when': 'is_open', 'text': 'Pressure {p:1}% of set · OPEN, blowing to outlet'},
                {'when': 'reseated', 'text': 'Pressure {p:1}% of set · reseated below set (blowdown)'},
                {'text': 'Pressure {p:1}% of set · closed, spring holds the disc'}])


def trap():
    lev = lambda t: lerp(270, 196, ease(t / 0.55)) if t < 0.55 else lerp(196, 262, ease((t - 0.55) / 0.3)) if t < 0.85 \
        else lerp(262, 270, (t - 0.85) / 0.15)
    tx = sorted(set(lin(0, 0.55, 23) + lin(0.55, 0.85, 13) + [1]))
    fxf = lambda fy: 430 - math.sqrt(max(0, 150 ** 2 - (240 - fy) ** 2))
    V = [('lev', tab('t', lev, tx)), ('wh', tab('lev', lambda y: 286 - y, [0, 400])),
         ('fx', tab('lev', fxf, lin(190, 275, 35))),
         ('open', steptab('t', [(0, 0), (0.5000001, 1), (0.86, 0)])),
         ('plug_y', steptab('open', [(0, 256), (1, 238)])),
         ('drop_op', steptab('t', [(0, .9), (0.6, .25)])), ('out_op', {'product': ['open', .9]}),
         ('collect', steptab('t', [(0, 1), (0.5, 0)]))]
    wig = [[r4(462 + k * 158), r4(263 + math.sin(k * 20) * 4)] for k in lin(0, 1, 41)]
    wig_path = [['M'] + wig[0]] + [['L'] + p for p in wig[1:]]
    wl = K.flatten(wig_path, lambda r: r)[2]
    bg = [R(170, 60, 300, 240, rx=30, **METAL), R(184, 74, 272, 212, rx=20, fill='sunk'),
          R(20, 86, 164, 30, fill='sunk'), *hpipe(20, 170, 86, 116),
          R(456, 250, 164, 26, fill='sunk'), *hpipe(470, 620, 250, 276)]
    scene = [G(bg), R(184, 'lev', 272, 'wh', fill=WATER, op=.35),
             FLOW(count=8, routes=[{'path': [['M', 60, 104], ['L', 180, 104], ['L', 210, 'lev']]}], speed=140,
                  opacity='drop_op'),
             FLOW(count=10, routes=[{'path': [['M', 200, 0], ['L', 260, 0]]}],
                  lanes=[[(i * 53) % 240, 84 + (i * 17) % 90] for i in range(10)], speed=24, fill='muted', opacity=.5,
                  wrap_x=[200, 440]),
             FLOW(count=12, routes=[{'path': wig_path}], speed=r4(1.2 * wl), opacity='out_op'),
             LN('fx', 'lev', 430, 240, stroke='ink', sw=4), C(430, 240, 6, fill='ink'),
             C('fx', 'lev', 36, fill='surface', stroke='ink', sw=2),
             R(446, 'plug_y', 10, 16, fill='act'), R(456, 246, 6, 34, fill='ink'),
             G([LAB('Inlet: steam + condensate', 60, 100, 30, 40), LAB('Steam space', 250, 100, 250, 30),
                LAB('Float', 'fx', 'lev', 300, 320), LAB('Lever and pivot', 430, 240, 490, 190),
                LAB('Orifice + valve', 452, 262, 490, 225), LAB('Outlet: condensate only', 560, 262, 620, 310, 'end')])]
    fig('trap', 'Float steam trap', 640, 330, 9,
        'Float steam trap. Condensate collects in the body and lifts the float; the lever opens the outlet orifice and '
        'water drains out. When the water is gone the float drops and closes the orifice before steam can escape.',
        'Float steam trap: condensate lifts a float on a lever, which opens the outlet orifice until the water has '
        'drained.', scene, V,
        status=[{'when': 'open', 'text': 'Water level high: float up, orifice open, condensate drains'},
                {'when': 'collect', 'text': 'Condensate collecting; float rising; orifice closed'},
                {'text': 'Water gone: float down, orifice closed, steam held in'}])


def spiral(cx, cy, r0, r1, a0, n=24, twist=0.9):
    pts = []
    for j in range(n + 1):
        r = r0 + (r1 - r0) * j / n
        a = (a0 - (r - 30) * twist) * PI / 180
        pts.append([r4(cx + r * math.cos(a)), r4(cy + r * math.sin(a))])
    return [['M'] + pts[0]] + [['L'] + p for p in pts[1:]]


def pump():
    cx, cy = 250, 200
    d = []
    for a in range(0, 361, 5):
        r, rad = 128 + a / 360 * 34, (a - 90) * PI / 180
        d.append(['M' if a == 0 else 'L', r4(cx + r * math.cos(rad)), r4(cy + r * math.sin(rad))])
    vanes = []
    for k in range(6):
        vd = []
        for r in range(30, 113, 4):
            a = (k * 60 - (r - 30) * 0.9) * PI / 180
            vd.append(['M' if r == 30 else 'L', r4(cx + r * math.cos(a)), r4(cy + r * math.sin(a))])
        vanes.append(PATH(vd, stroke='ink', sw=6, cap='round'))
    V = [('rot', tab('t', lambda t: 360 * t, [0, 1])),
         ('bub_op', {'product': ['cav', 1]})]
    routes_in = [{'path': spiral(cx, cy, 30, 114, 30 + 60 * k)} for k in range(6)]
    L_in = K.flatten(routes_in[0]['path'], lambda r: r)[2]
    routes_b = [{'path': spiral(cx, cy, 34, 84, 42 + 60 * k)} for k in range(6)]
    L_b = K.flatten(routes_b[0]['path'], lambda r: r)[2]
    routes_out = []
    for k in range(6):
        pts = [[r4(cx + (120 + j / 8 * 22) * math.cos((k * 60 + j / 8 * 60) * PI / 180)),
                r4(cy + (120 + j / 8 * 22) * math.sin((k * 60 + j / 8 * 60) * PI / 180))] for j in range(9)]
        routes_out.append({'path': [['M'] + pts[0]] + [['L'] + p for p in pts[1:]]})
    L_out = K.flatten(routes_out[0]['path'], lambda r: r)[2]
    bg = [R(cx, cy - 163, 190, 36, fill='surface'),
          PATH(f'M{cx},{cy - 164} L{cx + 190},{cy - 164} L{cx + 190},{cy - 126} L{cx},{cy - 126}', stroke='ink', sw=2.5),
          PATH(d, fill='surface', stroke='ink', sw=2.5),
          C(cx, cy, 126, fill={'radial': [[0.15, 'accent', 0.05], [1, 'accent', 0.45]]})]
    bub = dict(count=14, routes=routes_b, speed=r4(0.6 * L_b), opacity='bub_op')
    imp = G([C(cx, cy, 112, stroke='muted', sw=2, dash=[3, 3]), *vanes,
             FLOW(count=30, routes=routes_in, speed=r4(0.55 * L_in)),
             FLOW(**bub, r=1, fill='surface', stroke='ink', stroke_width=1.2,
                  along={'r': [[0, 2], [0.55, 7], [0.55, 0], [1, 0]], 'opacity': [[0, 1], [0.55, 1], [0.55, 0], [1, 0]]}),
             FLOW(**bub, r=7, glyph='burst', stroke='act', stroke_width=2,
                  along={'opacity': [[0, 0], [0.55, 0], [0.55, 1], [0.7, 1], [0.7, 0], [1, 0]]})],
            tf=[{'rotate': ['rot', cx, cy]}])
    scene = [G(bg), imp,
             FLOW(count=8, routes=routes_out, speed=r4(L_out / 0.4545), along={'opacity': [[0, .9], [1, 0]]}),
             C(cx, cy, 28, fill='surface', stroke='ink', sw=2), C(cx, cy, 9, fill='ink'),
             G([LAB('Eye (suction, lowest pressure)', cx + 20, cy - 10, 440, 230),
                LAB('Impeller vanes', cx - 60, cy + 60, 440, 262), LAB('Volute casing', cx - 150, cy + 40, 440, 294),
                LAB('Discharge (highest pressure)', cx + 170, cy - 145, 470, 90)]),
             T('rotation', cx - 30, cy - 130, size=11, fill='muted'), arrow(cx - 40, cy - 122, cx + 10, cy - 124, 'muted', 1.5)]
    fig('pump', 'Centrifugal pump', 640, 380, 3,
        'Centrifugal pump seen along the shaft. Water enters at the eye in the centre, the spinning vanes throw it '
        'outwards, and the volute (the widening spiral casing) turns that speed into pressure at the discharge. Switch '
        'on cavitation to see vapour bubbles form where pressure is lowest, near the eye, and collapse against the '
        'vanes further out.',
        'Centrifugal pump seen along its shaft: water enters at the eye, the impeller vanes throw it outwards and the '
        'volute leads it to the discharge.', scene, V, toggles=[{'key': 'cav', 'label': 'Show cavitation', 'on': False}],
        status=[{'when': 'cav', 'text': 'Cavitation: pressure at the eye falls below vapour pressure; bubbles form, then '
                 'implode (red) as pressure rises, pitting the vanes'},
                {'text': 'Normal: water speeds up through the vanes; the volute turns speed into pressure'}])


def gear():
    def gpath(cx, cy):
        d = []
        for i in range(241):
            a = i / 240 * 2 * PI
            w = math.sin(10 * a)
            r = 40 + 10 * clamp(w * 2.2, -1, 1) * 0.5 + 5
            d.append(['M' if i == 0 else 'L', r4(cx + r * math.cos(a)), r4(cy + r * math.sin(a))])
        return d + [['Z']]
    na = lambda p: (-210 + p * 240) * PI / 180
    V = [('rot', tab('t', lambda t: 288 * t, [0, 1])), ('rot2', tab('t', lambda t: -288 * t + 18, [0, 1])),
         ('pr_target', {'select': 'blk', 'cases': [0.3, 0.95]}),
         ('pr', {'follow': 'pr_target', 'rate': 2, 'init': 0.3}),
         ('nx', tab('pr', lambda p: 240 + 17 * math.cos(na(p)), lin(0, 1, 41))),
         ('ny', tab('pr', lambda p: 40 + 17 * math.sin(na(p)), lin(0, 1, 41))),
         ('high', steptab('pr', [(0, 0), (0.8500001, 1)])), ('relief', {'product': ['blk', 'high']}),
         ('rv_y', steptab('relief', [(0, 150), (0.5, 140)])), ('bp_op', {'product': ['relief', .9]}),
         ('out_op', steptab('blk', [(0, .9), (0.5, 0)]))]
    arc = lambda c, s: [[r4(c + 53 * math.cos((90 + s * k * 180) * PI / 180)),
                         r4(160 + 53 * math.sin((90 + s * k * 180) * PI / 180) * 0.95)] for k in lin(0, 1, 37)]
    route = lambda pts: [['M'] + pts[0]] + [['L'] + p for p in pts[1:]]
    left, right = route(arc(275, 1)), route(arc(365, -1))
    La = K.flatten(left, lambda r: r)[2]
    bg = [R(200, 90, 240, 140, rx=70, **METAL), R(212, 100, 216, 120, rx=60, fill='sunk'),
          R(300, 220, 40, 90, fill='sunk', stroke='ink', sw=2), R(300, 10, 40, 90, fill='sunk', stroke='ink', sw=2),
          PATH('M340,40 L520,40 L520,280 L340,280', stroke='muted', sw=10)]
    scene = [G(bg), R(510, 'rv_y', 20, 16, fill='act'), T('relief valve', 540, 162, size=11, fill='muted'),
             R(296, 30, 48, 8, fill='ink', op='blk'),
             T('INLET', 320, 322, 'middle', 11, fill='muted'), T('OUTLET', 360, 20, size=11, fill='muted'),
             PATH(gpath(275, 160), fill='muted', stroke='ink', sw=1.5, tf=[{'rotate': ['rot', 275, 160]}]),
             PATH(gpath(365, 160), fill='muted', stroke='ink', sw=1.5, tf=[{'rotate': ['rot2', 365, 160]}]),
             C(275, 160, 6, fill='ink'), C(365, 160, 6, fill='ink'),
             FLOW(count=8, routes=[{'path': left}], speed=r4(La * 70 / 180)),
             FLOW(count=8, routes=[{'path': right}], speed=r4(La * 70 / 180)),
             FLOW(count=5, routes=[{'path': [['M', 312, 310], ['L', 312, 220]]}], lanes=[[(i % 3) * 8, 0] for i in range(3)],
                  speed=54, opacity=.9),
             FLOW(count=5, routes=[{'path': [['M', 312, 96], ['L', 312, 10]]}], lanes=[[(i % 3) * 8, 0] for i in range(3)],
                  speed=51.6, opacity='out_op'),
             FLOW(count=10, routes=[{'path': parse_d('M340,40 L520,40 L520,280 L340,280')}], speed=210, opacity='bp_op'),
             G([C(240, 40, 22, fill='surface', stroke='ink', sw=2), LN(240, 40, 'nx', 'ny', stroke='act', sw=2.5),
                LN(262, 40, 300, 50, stroke='muted', sw=3), T('outlet pressure', 150, 80, size=11, fill='muted')])]
    fig('gear', 'Gear pump (displacement)', 640, 330, 4,
        'Gear pump. Fluid is trapped between the gear teeth and the casing and carried round the outside from inlet to '
        'outlet; where the teeth mesh it is squeezed out. Every turn moves the same volume, so if the outlet is blocked '
        'pressure climbs until the relief valve opens.',
        'Gear pump: two meshing gears carry fluid round the casing from inlet to outlet, with a relief valve line back '
        'to the inlet.', scene, V, toggles=[{'key': 'blk', 'label': 'Close the outlet valve', 'on': False}],
        status=[{'when': 'relief', 'text': 'Outlet closed: pressure at relief setting, relief valve open, flow '
                 'circulates back to inlet'},
                {'when': 'blk', 'text': 'Outlet closed: pressure climbing fast'},
                {'text': 'Normal: each turn carries a fixed volume from inlet to outlet'}])


def gen():
    cx, cy = 160, 160
    cols, names = ['accent', 'act', 'ok'], ['L1', 'L2', 'L3']
    X0, X1, Y, A = 350, 660, 160, 80
    xs = lambda th: X0 + th / 720 * (X1 - X0)
    tx = lin(0, 1, 241)
    V = [('ang', {'of': 't', 'table': [[0, 0], [0.5, 360], [0.5, 0], [1, 360]]}),
         ('curx', tab('t', lambda t: xs(t * 720), [0, 1]))]
    for k, ph in enumerate((0, 120, 240)):
        V.append((f'v{k + 1}', tab('t', lambda t, ph=ph: math.cos((t * 720 - ph) * PI / 180), tx)))
        V.append((f'o{k + 1}', tab('t', lambda t, ph=ph: .25 + .75 * abs(math.cos((t * 720 - ph) * PI / 180)), tx)))
        V.append((f'y{k + 1}', tab('t', lambda t, ph=ph: Y - A * math.cos((t * 720 - ph) * PI / 180), tx)))
    bg = [C(cx, cy, 132, fill='surface', stroke='ink', sw=2), C(cx, cy, 98, fill='ground', stroke='ink', sw=2)]
    for k, ph in enumerate((0, 120, 240)):
        for off in (0, 180):
            a = (ph + off - 90) * PI / 180
            x, y = r4(cx + 108 * math.cos(a)), r4(cy + 108 * math.sin(a))
            bg.append(R(r4(x - 13), r4(y - 9), 26, 18, rx=3, fill=cols[k], op=f'o{k + 1}',
                        tf=[{'rotate': [ph + off, x, y]}]))
            if not off:
                bg.append(T(names[k], r4(cx + 148 * math.cos(a)), r4(cy + 148 * math.sin(a) + 5), 'middle', 14,
                            'display', 600, fill=cols[k]))
    scene = [G(bg),
             G([R(cx - 16, cy - 84, 32, 84, rx=6, fill='act'), R(cx - 16, cy, 32, 84, rx=6, fill='accent'),
                T('N', cx, cy - 58, 'middle', 16, weight=700, fill='#ffffff'),
                T('S', cx, cy + 70, 'middle', 16, weight=700, fill='#ffffff')], tf=[{'rotate': ['ang', cx, cy]}]),
             C(cx, cy, 8, fill='ink'), LN(X0, Y, X1, Y, stroke='muted')]
    for t in (0, 180, 360, 540, 720):
        scene += [LN(r4(xs(t)), Y - A - 6, r4(xs(t)), Y + A + 6, stroke='rule', dash=[2, 4]),
                  T(f'{t}°', r4(xs(t)), Y + A + 22, 'middle', 11, 'mono', fill='muted')]
    for k, ph in enumerate((0, 120, 240)):
        d = [['M' if t == 0 else 'L', r4(xs(t)), r4(Y - A * math.cos((t - ph) * PI / 180))] for t in range(0, 721, 6)]
        scene.append(PATH(d, stroke=cols[k], sw=2, op=.55))
    scene += [LN('curx', Y - A - 8, 'curx', Y + A + 8, stroke='ink', sw=1.5)]
    scene += [C('curx', f'y{k + 1}', 5, fill=cols[k]) for k in range(3)]
    scene += [T('rotor angle', (X0 + X1) / 2, 312, 'middle', 11, fill='muted'), T('coil voltage', X0, 30, size=11, fill='muted')]
    fig('gen', 'Three-phase generator', 680, 320, 4,
        'A 2-pole generator, slowed right down. The rotor is an electromagnet; as its north pole sweeps past each '
        'stator coil, that coil\'s voltage peaks. Three coils 120° apart give three voltages 120° apart. '
        'At 3000 rpm this happens 50 times a second: 50 Hz.',
        'A two-pole generator rotor turning inside three pairs of stator coils, beside the three phase voltages '
        'plotted against rotor angle.', scene, V,
        status='Rotor at {ang}° · L1 {v1:+2} · L2 {v2:+2} · L3 {v3:+2} (always sum to zero)')


def stage():
    # one particle's path through the bands, simulated once (the build tool's job)
    x, y, vx, t, pts, spd = 0.0, 24.0, 0.0, 0.0, [], []
    dt = 1 / 240
    while y <= 310:
        if y < 70: vy, tvx = 55, 0
        elif y < 130: vy, tvx = 90, 150
        elif y < 190: vy, tvx = 110, 150
        elif y < 250: vy, tvx = 80, -30
        else: vy, tvx = 60, -30
        vx += (tvx - vx) * min(1, dt * 6)
        pts.append((x, y))
        spd.append(math.hypot(vx, vy))
        x += vx * dt
        y += vy * dt
    keep = list(range(0, len(pts), 12)) + [len(pts) - 1]
    route = [['M', r4(pts[0][0]), r4(pts[0][1])]] + [['L', r4(pts[i][0]), r4(pts[i][1])] for i in keep[1:]]
    P, S, L = K.flatten(route, lambda r: r)
    acc, sp_t, r_t, fill_at = 0.0, [], [], None
    for j, i in enumerate(keep):
        k = acc / L
        sp_t.append([r4(k), r4(spd[i])])
        r_t.append([r4(k), r4(2.5 + 1.5 * clamp((pts[i][1] - 20) / 290, 0, 1))])
        if fill_at is None and (pts[i][1] - 20) / 290 >= .45:
            fill_at = k
        if j < len(S):
            acc += S[j]
    sp_t[-1][0] = 1
    r_t[-1][0] = 1
    V = [('off', {'of': 't', 'table': [[0, 0], [0.25, 56], [0.25, 0], [0.5, 56], [0.5, 0], [0.75, 56], [0.75, 0], [1, 56]]})]
    blades = [PATH([['M', 130 + i * 56 + 30, 192], ['C', 130 + i * 56 + 14, 206, 130 + i * 56 + 12, 230, 130 + i * 56 + 30, 248]],
                   stroke='act', sw=9, cap='round') for i in range(11)]
    bg = [R(150, 70, 490, 60, fill='sunk'), R(150, 190, 490, 60, fill='sunk')]
    bg += [PATH(f'M{x},72 C{x + 2},100 {x + 10},118 {x + 34},128', stroke='ink', sw=9, cap='round') for x in range(170, 640, 56)]
    scene = [G(bg), G([G(blades, tf=[{'translate': ['off', 0]}])], clip={'rect': [150, 180, 460, 80]}),
             R(150, 250, 490, 14, fill='muted'),
             FLOW(count=50, routes=[{'path': route}], lanes=[[150 + (i * 97) % 490, 0] for i in range(50)], speed=1, r=1,
                  wrap_x=[150, 640], along={'speed': sp_t, 'r': r_t, 'fill': [[0, 'act'], [r4(fill_at), 'accent']]}),
             T('Stationary vanes', 10, 96, size=15, font='display', weight=600),
             T('pressure → speed', 10, 114, fill='muted'),
             T('Moving blades', 10, 216, size=15, font='display', weight=600, fill='act'),
             T('speed → turning force', 10, 234, fill='muted'), T('rotor', 10, 262, fill='muted'),
             arrow(60, 290, 140, 290, 'act', 2.5), T('blade motion', 60, 312, size=11, fill='muted'),
             T('steam in (high pressure, slow)', 400, 20, 'middle', 11, fill='muted'),
             T('steam out (lower pressure)', 400, 324, 'middle', 11, fill='muted')]
    fig('stage', 'Turbine stage', 660, 330, 3,
        'One turbine stage, unrolled flat. The stationary vanes narrow and turn the flow, so the steam (or gas) speeds '
        'up while its pressure and temperature fall. The fast jet then hits the moving blades, which turn it back; that '
        'change of direction pushes the blades and turns the rotor.',
        'A turbine stage unrolled flat: steam passes a row of fixed vanes, speeds up and turns, then pushes a row of '
        'moving blades sideways.', scene, V,
        status='Particle colour: red = hot, high pressure · blue = cooler, lower pressure after doing work')


def circ():
    evf = lambda t: 0 if t < 0.2 else ease((t - 0.2) / 0.25) if t < 0.45 else 1 - ease((t - 0.45) / 0.45)
    tx = sorted(set([0, 0.2] + lin(0.2, 0.45, 16) + lin(0.45, 0.9, 19) + [1]))
    V = [('evt', tab('t', evf, tx)), ('ev', {'product': ['swell', 'evt']}),
         ('lev', tab('ev', lambda e: 88 - 18 * e, [0, 1])), ('wh', tab('lev', lambda y: 128 - y, [0, 200])),
         ('levm4', {'sum': ['lev', -4]}),
         ('sd', tab('ev', lambda e: (0.22 + 0.12 * e) * 262, [0, 1])),
         ('sh', tab('ev', lambda e: (0.22 + 0.12 * e) * 1.4 * 320, [0, 1])),
         ('sr', tab('ev', lambda e: (0.22 + 0.12 * e) * 1.2 * 256, [0, 1])),
         ('rb', tab('ev', lambda e: 4 + 3 * e, [0, 1])),
         ('mm', tab('ev', lambda e: -50 + 150 * e, [0, 1])), ('pr', tab('ev', lambda e: 12.44 - 0.3 * e, [0, 1])),
         ('early', steptab('t', [(0, 1), (0.2, 0)])), ('mid', steptab('t', [(0, 1), (0.45, 0)])),
         ('c1', {'product': ['swell', 'early']}), ('c2', {'product': ['swell', 'mid']})]
    bg = [R(250, 150, 380, 230, fill='act', op=.07), LN(250, 150, 250, 380, stroke='muted', dash=[5, 4]),
          T('GAS DUCT', 620, 168, 'end', 11, fill='act')]
    bg += [arrow(628, 200 + i * 45, 560, 200 + i * 45, 'act', 2) for i in range(4)]
    bg += [T('hot gas', 620, 372, 'end', 12, weight=700, fill='act'), R(100, 40, 380, 90, rx=44, **METAL),
           R(132, 120, 22, 270, fill='surface', stroke='ink', sw=2), R(132, 380, 360, 22, rx=6, fill='surface', stroke='ink', sw=2)]
    bg += [R(x - 8, 128, 16, 256, fill='surface', stroke='ink', sw=1.5) for x in (300, 350, 400, 450)]
    bg += [R(420, 10, 16, 34, fill='surface', stroke='ink', sw=1.5), T('steam to superheater', 444, 24, size=11, fill='muted'),
           R(40, 72, 62, 12, fill='surface', stroke='ink', sw=1.5), T('feedwater', 40, 64, size=11, fill='muted')]
    riser = [{'path': [['M', 300, 380], ['L', 300, 124]]}]
    tubes = [[0, 0], [50, 0], [100, 0], [150, 0]]
    scene = [G(bg),
             G([R(102, 'lev', 376, 'wh', fill=WATER, op=.35), LN(102, 'lev', 478, 'lev', stroke=WATER, sw=2)],
               clip={'rect': [102, 42, 376, 86], 'rx': 42}),
             R(102, 42, 376, 86, rx=42, stroke='ink', sw=2),
             FLOW(count=10, routes=[{'path': [['M', 143, 128], ['L', 143, 390]]}], speed='sd'),
             FLOW(count=8, routes=[{'path': [['M', 150, 391], ['L', 470, 391]]}], speed='sh'),
             FLOW(count=24, routes=riser, lanes=tubes, speed='sr', along={'opacity': [[0, 1], [0.25, 1], [1, .3]]}),
             FLOW(count=24, routes=riser, lanes=[[dx, -5] for dx, _ in tubes], speed='sr', r='rb', fill='surface',
                  stroke='ink', stroke_width=1,
                  along={'r': [[0, 0], [0.25, 0], [1, 1]], 'opacity': [[0, 0], [0.2875, 0], [0.2875, 1], [1, 1]]}),
             FLOW(count=8, routes=[{'path': [['M', 300 + j * 40, 'levm4'], ['L', 428, 20]]} for j in range(4)],
                  speed=70, fill='muted', opacity=.6),
             G([LAB('Drum', 250, 52, 330, 24), LAB('Downcomer', 143, 250, 124, 236, 'end'),
                LAB('Evaporator tubes (heated)', 300, 300, 270, 420), LAB('Bottom header', 200, 402, 170, 424, 'end')]),
             T('Level {mm:+0} mm', 500, 104, font='mono'), T('Pressure {pr:2} MPa', 500, 122, font='mono')]
    fig('circ', 'Natural circulation in a drum boiler', 640, 430, 12,
        'Natural circulation. Water falls down the unheated downcomer, is heated in the evaporator tubes in the gas '
        'path, partly boils, and the lighter steam-water mixture rises back to the drum. No pump drives it. Switch on '
        'the load step to see swell: pressure dips, more water flashes to steam, and the bubbles push the drum level up '
        'even though water is being used faster.',
        'A drum boiler: water falls down an unheated downcomer and rises, partly boiling, through heated evaporator '
        'tubes back to the drum.', scene, V, toggles=[{'key': 'swell', 'label': 'Load step (pressure dips)', 'on': False}],
        status=[{'when': 'c1', 'text': 'Steady load'},
                {'when': 'c2', 'text': 'Load up: pressure dips, water flashes, level SWELLS up'},
                {'when': 'swell', 'text': 'Pressure recovers; bubbles shrink; level settles back'},
                {'text': 'Steady circulation: down the downcomer, up the heated tubes'}])


def wall():
    x0, x1, y0, y1, N = 60, 260, 60, 280, 40
    P0, P1, Q0, Q1 = 340, 640, 40, 280
    px = lambda m: P0 + m / 125 * (P1 - P0)
    kpy = (Q1 - Q0) / 350
    brk = [(0, 1)] + [((k - 0.5) / 20, k) for k in range(2, 21)]
    qx = sorted(set([(j / 64) ** 2 for j in range(65)]))
    V = [('rate', steptab('v', brk)), ('inv_rate', steptab('v', [(x, 1 / k) for x, k in brk])),
         ('ti', tab('t', lambda t: 30 + 300 * t, [0, 1])), ('q', {'product': ['t', 'inv_rate']}),
         ('e', tab('q', lambda q: 1 - math.exp(-42.857142857 * q), qx)),
         ('dtw', {'product': ['rate', r4(0.125 * 0.125 / (2 * 1.1e-5) / 60), 'e']}),
         ('ndt', {'product': ['dtw', -1]}), ('to', {'sum': ['ti', 'ndt']}),
         ('y_ti', tab('ti', lambda T: Q1 - T * kpy, [0, 400])), ('y_to', tab('to', lambda T: Q1 - T * kpy, [-400, 400])),
         ('fast', steptab('rate', [(0, 0), (5.5, 1)]))]
    V += [('nhdt', {'product': ['dtw', -0.5]}), ('tmid', {'sum': ['ti', 'nhdt']}),
          ('ytext', tab('tmid', lambda T: Q1 - T * kpy + 4, [-400, 400]))]
    stops = [[T, hsl_hex(220 - 220 * clamp((T - 20) / 320, 0, 1), 70, 55 - 8 * clamp((T - 20) / 320, 0, 1))]
             for T in range(20, 341, 10)]
    strips = []
    for i in range(N):
        u = (i + .5) / N
        c = 2 * u - u * u
        V += [(f'd{i}', {'product': ['dtw', r4(-c)]}), (f'tw{i}', {'sum': ['ti', f'd{i}']})]
        strips.append(R(r4(x0 + i * (x1 - x0) / N), y0, r4((x1 - x0) / N + .5), y1 - y0,
                        fill={'of': f'tw{i}', 'stops': stops}))
    prof = []
    for m in range(0, 126, 5):
        u = m / 125
        c = 2 * u - u * u
        V += [(f'pd{m}', {'product': ['dtw', r4(c * kpy)]}), (f'py{m}', {'sum': ['y_ti', f'pd{m}']})]
        prof.append([r4(px(m)), f'py{m}'])
    scene = strips + [
        R(x0, y0, x1 - x0, y1 - y0, stroke='ink', sw=2), R(x1, y0, 22, y1 - y0, fill='sunk'),
        T('inside', x0, y0 - 10, fill='muted'), T('outside', x1, y0 - 10, 'end', fill='muted'),
        T('insulation', x1 + 26, y1 - 4, size=11, fill='muted', tf=[{'rotate': [-90, x1 + 26, y1 - 4]}]),
        T('125 mm HP drum wall', (x0 + x1) / 2, y1 + 22, 'middle'),
        LN(P0, Q0, P0, Q1, stroke='muted'), LN(P0, Q1, P1, Q1, stroke='muted')]
    for Tt in (0, 100, 200, 300):
        yy = r4(Q1 - Tt * kpy)
        scene += [LN(P0, yy, P1, yy, stroke='rule', dash=[2, 4]), T(str(Tt), P0 - 6, r4(yy + 4), 'end', 11, 'mono', fill='muted')]
    scene += [T(str(m), r4(px(m)), Q1 + 16, 'middle', 11, 'mono', fill='muted') for m in (0, 25, 50, 75, 100, 125)]
    scene += [T('mm from inside surface', (P0 + P1) / 2, Q1 + 34, 'middle', 11, fill='muted'),
              T('°C', P0 - 6, Q0 - 8, 'end', 11, fill='muted'),
              POLY(prof, stroke='act', sw=3),
              LN(r4(px(125) - 4), 'y_ti', r4(px(125) - 4), 'y_to', stroke='ink', sw=1.5, dash=[3, 3]),
              T('ΔT ≈ {dtw} °C', r4(px(125) - 10), 'ytext', 'end', font='mono', weight=700,
                fill={'of': 'dtw', 'steps': [[0, 'ink'], [50.0000001, 'act']]})]
    fig('wall', 'Heating a thick drum wall', 660, 340, 9,
        'Simplified one-dimensional estimate for a 125 mm steel wall heated from the inside and insulated outside '
        '(thermal diffusivity about 1.1×10⁻⁵ m²/s). The faster the inside heats, the bigger the '
        'temperature difference across the wall, and thermal stress grows with that difference. Real drums add nozzles '
        'and top-to-bottom differences.',
        'A section through a 125 mm drum wall, coloured by temperature, beside a chart of temperature across the wall '
        'while the inside heats.', scene, V,
        slider={'label': 'Heating rate', 'init': 0.25, 'text': '{rate} °C/min'},
        status=[{'when': 'fast', 'text': 'Heating at {rate} °C/min · inside {ti} °C · outside {to} °C '
                 '· across the wall ≈ {dtw} °C · faster than the HRSG manual\'s 5 °C/min drum limit'},
                {'text': 'Heating at {rate} °C/min · inside {ti} °C · outside {to} °C · across the '
                 'wall ≈ {dtw} °C'}])


def orifice():
    Y0, Y1, mid = 220, 280, 250
    xs = [180, 336, 520]
    fr = [0, 1, 0.35]              # share of the drop each column shows
    V = [('v100', {'product': ['v', 100]}), ('dp', tab('v', lambda q: 100 * q * q, lin(0, 1, 41))),
         ('spd', {'product': ['v', 140]})]
    for j, f in enumerate(fr):
        V.append((f'cy{j}', tab('v', lambda q, f=f: Y0 - (170 - f * 120 * q * q), lin(0, 1, 41))))
        V.append((f'ch{j}', tab('v', lambda q, f=f: 170 - f * 120 * q * q, lin(0, 1, 41))))
    V.append(('dpy', tab('v', lambda q: Y0 - (170 + 170 - 120 * q * q) / 2 + 4, lin(0, 1, 41))))
    sq = lambda x: (0.4 + 0.6 * abs(x - 312) / 60) if abs(x - 312) < 60 else 1
    kx = sorted(set(lin(0, 1, 61) + [(252 - 20) / 600, (312 - 20) / 600, (372 - 20) / 600]))
    bg = [R(20, Y0, 600, 60, fill=WATER, op=.18), *hpipe(20, 620, Y0, Y1),
          R(296, Y0, 8, 16, fill='ink'), R(296, Y1 - 16, 8, 16, fill='ink')]
    for j, x in enumerate(xs):
        bg += [R(x - 7, 40, 14, Y0 - 40, stroke='muted', sw=1.5), R(x - 5, f'cy{j}', 10, f'ch{j}', fill=WATER, op=.6)]
    bg += [T('upstream', 180, 32, 'middle', 11, fill='muted'), T('just after plate', 336, 32, 'middle', 11, fill='muted'),
           T('downstream', 520, 32, 'middle', 11, fill='muted')]
    scene = [G(bg),
             FLOW(count=40, routes=[{'path': [['M', 20, mid], ['L', 620, mid]]}],
                  lanes=[[0, (226 + (i * 31) % 48) - mid] for i in range(40)], speed='spd',
                  along={'speed': [[r4(k), r4(1 / sq(20 + 600 * k))] for k in kx],
                         'lane': [[r4(k), r4(sq(20 + 600 * k))] for k in kx]}),
             G([LAB('Orifice plate', 300, 238, 300, 316)]),
             LN(250, 50, 250, 'cy1', stroke='act', sw=2), T('DP', 244, 'dpy', 'end', weight=700, fill='act')]
    fig('orifice', 'Orifice flowmeter and Bernoulli', 640, 330, 8,
        'Flow through an orifice plate. In the narrow jet just after the plate the water speeds up and its pressure '
        'drops (Bernoulli); the columns show pressure at three points. The drop measured between the tappings rises '
        'with the square of flow, so at 25% flow the DP is only about 6% of full scale. Some pressure is never '
        'recovered: that is the meter\'s permanent loss.',
        'Water flowing through an orifice plate, with three pressure columns: before the plate, just after it, and '
        'downstream.', scene, V,
        slider={'label': 'Flow', 'init': 0.8,
                'drive': tab('t', lambda t: 0.15 + 0.85 * (0.5 - 0.5 * math.cos(t * 2 * PI)), lin(0, 1, 65)),
                'text': '{v100}% flow'},
        status='Flow {v100}% → DP {dp}% of full scale (DP ∝ flow²)')


def gauge():
    real = lambda t: -50 + 70 * math.sin(t * 2 * PI) + 15 * math.sin(t * 6 * PI)
    V = [('real', tab('t', real, lin(0, 1, 121))), ('blocked', steptab('mode', [(0, 0), (3, 1)])),
         ('frozen', {'hold': 'real', 'while': 'blocked'}),
         ('rp', {'sum': ['real', 120]}), ('rm', {'sum': ['real', -120]}),
         ('g', {'select': 'mode', 'cases': ['real', 'rp', 'rm', 'frozen']}),
         ('dy', tab('real', lambda r: 190 - r * 0.25, [-1000, 1000])),
         ('dh', tab('dy', lambda y: 312 - y, [-1000, 1000])),
         ('gy', tab('g', lambda g: 190 - g * 0.25, [-240, 240])),
         ('red_h', tab('gy', lambda y: y - 130, [130, 250])), ('green_h', tab('gy', lambda y: 250 - y, [130, 250])),
         ('nreal', {'product': ['real', -1]}), ('diff', {'sum': ['g', 'nreal']}),
         ('m_ok', steptab('mode', [(0, 1), (1, 0)])), ('m_steam', steptab('mode', [(0, 0), (1, 1), (2, 0)])),
         ('m_water', steptab('mode', [(0, 0), (2, 1), (3, 0)]))]
    bg = [R(40, 50, 230, 260, rx=110, **METAL),
          PATH('M270,110 L440,110 L440,130', stroke='muted', sw=8), PATH('M270,270 L440,270 L440,250', stroke='muted', sw=8),
          R(320, 100, 20, 20, fill='surface', stroke='ink'), R(320, 260, 20, 20, fill='surface', stroke='ink'),
          T('steam side', 360, 96, size=11, fill='muted'), T('water side', 360, 296, size=11, fill='muted'),
          R(424, 126, 32, 128, rx=4, fill='surface', stroke='ink', sw=2.5),
          T('Drum', 155, 40, 'middle', 15, 'display', 600), T('Gauge', 476, 140, size=15, font='display', weight=600)]
    scene = [G(bg), G([R(40, 'dy', 230, 'dh', fill=WATER, op=.35)], clip={'rect': [40, 50, 230, 260], 'rx': 110}),
             R(40, 50, 230, 260, rx=110, stroke='ink', sw=2),
             R(430, 130, 20, 'red_h', fill='act'), R(430, 'gy', 20, 'green_h', fill='ok'),
             FLOW(count=6, routes=[{'path': [['M', 330, 98], ['L', 330, 58]]}], lanes=[[(i - 3) * 3, 0] for i in range(6)],
                  speed=40, r=1, fill='muted', opacity='m_steam', along={'r': [[0, 2], [1, 7]], 'opacity': [[0, 1], [1, 0]]}),
             FLOW(count=6, routes=[{'path': [['M', 330, 282], ['L', 330, 322]]}], lanes=[[(i - 3) * 3, 0] for i in range(6)],
                  speed=40, opacity='m_water', along={'opacity': [[0, 1], [1, 0]]}),
             PATH('M372,262 L388,278 M388,262 L372,278', stroke='act', sw=4, op='blocked'),
             T('Real level  {real:+0} mm', 480, 170, size=13, font='mono'),
             T('Gauge reads {g:+0} mm', 480, 194, size=13, font='mono', weight=700,
               fill={'of': 'diff', 'steps': [[-1e6, 'act'], [-20, 'ok'], [20.0000001, 'act']]})]
    fig('gauge', 'Drum level gauge faults', 640, 360, 6,
        'A local bi-colour gauge connected to the drum by a steam line and a water line. Pick a fault: a leak on the '
        'steam side makes the gauge read high, a leak on the water side makes it read low, and a blocked connection '
        'freezes it while the real level keeps moving.',
        'A drum and a local bi-colour level gauge joined by a steam line and a water line, with the real and the '
        'gauge level side by side.', scene, V,
        modes=[{'key': 'ok', 'label': 'Normal'}, {'key': 'steam', 'label': 'Steam-side leak'},
               {'key': 'water', 'label': 'Water-side leak'}, {'key': 'block', 'label': 'Blocked connection'}],
        status=[{'when': 'm_ok', 'text': 'Normal: gauge follows the drum level'},
                {'when': 'm_steam', 'text': 'Steam-side leak: gauge reads HIGH'},
                {'when': 'm_water', 'text': 'Water-side leak: gauge reads LOW'},
                {'text': 'Blocked: gauge FROZEN while the real level moves'}])


def damper():
    xs = lin(0, 1, 46)
    V = [('bx', tab('v', lambda f: 400 + 100 * math.cos((180 - 90 * f) * PI / 180), xs)),
         ('by', tab('v', lambda f: 200 + 100 * math.sin(90 * f * PI / 180), xs)),
         ('hrsg_w', tab('v', lambda f: 1 - f, [0, 1])),
         ('at_hrsg', steptab('v', [(0, 1), (0.02, 0)])), ('at_bypass', steptab('v', [(0, 0), (0.9800001, 1)])),
         ('ends', {'sum': ['at_hrsg', 'at_bypass']}), ('v100', {'product': ['v', 100]})]
    ys = [(i * 29) % 76 for i in range(44)]
    scene = [G([PATH('M20,200 L300,200 L300,20 L400,20 L400,200 L640,200 L640,300 L20,300 Z', fill='sunk', stroke='ink', sw=2),
                T('from gas turbine', 30, 324, fill='muted'), T('to HRSG', 630, 324, 'end', fill='muted'),
                T('bypass stack', 410, 40, fill='muted')]),
             FLOW(count=44, routes=[{'path': [['M', 20, 212], ['L', 640, 212]], 'weight': 'hrsg_w', 'lanes': [[0, y] for y in ys]},
                                    {'path': [['M', 20, 212], ['L', 312, 212], ['L', 312, -46]], 'weight': 'v',
                                     'lanes': [[y, y] for y in ys]}],
                  speed=233, r=3.5, fill='act'),
             LN(400, 200, 'bx', 'by', stroke='ink', sw=10, cap='round'), C(400, 200, 8, fill='ink'),
             G([arrow(350, 150, 350, 188, 'accent', 3), arrow(330, 150, 330, 188, 'accent', 3),
                T('seal air', 320, 140, weight=700, fill='accent')], op='at_hrsg'),
             G([arrow(450, 230, 412, 230, 'accent', 3), arrow(450, 270, 412, 270, 'accent', 3),
                T('seal air', 456, 254, weight=700, fill='accent')], op='at_bypass'),
             T([{'when': 'ends', 'text': 'Seal air fan: running'}, {'text': 'Seal air fan: stopped (damper moving)'}],
               20, 40, font='mono')]
    fig('damper', 'Three-way (diverter) damper', 660, 360, 12,
        'Three-way damper. One blade on a hinge sends GT exhaust either into the HRSG or up the bypass stack. Seal air '
        'is blown into the side that is shut, so no gas leaks past the blade. Between the end positions both seal-air '
        'valves close and the seal fan stops. At Rumaila the damper strokes in about 60 s, or 30 s in an emergency.',
        'A three-way damper: one hinged blade sends gas turbine exhaust either on to the HRSG or up the bypass stack, '
        'with seal air on the shut side.', scene, V,
        slider={'label': 'Damper', 'init': 0, 'drive': PING,
                'text': [{'when': 'at_hrsg', 'text': 'Gas to HRSG'}, {'when': 'at_bypass', 'text': 'Gas to bypass stack'},
                         {'text': 'Moving {v100}%'}]},
        status=[{'when': 'at_hrsg', 'text': 'Blade closes the bypass: all gas goes through the HRSG; seal air on the bypass side'},
                {'when': 'at_bypass', 'text': 'Blade closes the HRSG inlet: gas goes up the bypass stack; seal air on the HRSG side'},
                {'text': 'Blade moving: gas splits between both paths'}])


def expand():
    PL, Kx = 394, 0.6
    V = [('temp', tab('v', lambda v: 20 + 520 * v, [0, 1])), ('dk', tab('v', lambda v: 520 * v, [0, 1])),
         ('dmm', tab('v', lambda v: 30 * 1.2e-5 * 520 * v * 1000, [0, 1])),
         ('px', tab('v', lambda v: 30 * 1.2e-5 * 520 * v * 1000 * Kx, [0, 1])),
         ('pw', {'sum': ['px', PL]}), ('ex', {'sum': ['px', 460]}), ('exl', {'sum': ['px', 454]}), ('exr', {'sum': ['px', 466]})]
    for x0 in (180, 290, 400):
        V.append((f's{x0}', tab('px', lambda p, x0=x0: x0 + (x0 - 66) / PL * p, [0, 200])))
    stops = [[r4(v), hsl_hex(220 - 215 * v, 40 + 30 * v, 55 - 5 * v)] for v in lin(0, 1, 11)]
    bg = [R(30, 100, 36, 80, fill='muted')] + [LN(30, 104 + i * 14, 66, 94 + i * 14, stroke='surface', sw=2) for i in range(6)]
    bg += [LN(20, 190, 640, 190, stroke='ink', sw=2)] + [R(x0 - 20, 169, 40, 21, fill='sunk', stroke='ink') for x0 in (180, 290, 400)]
    for mm in range(0, 201, 50):
        x = r4(460 + mm * 0.6)
        bg += [LN(x, 70, x, 82, stroke='ink'), T(str(mm), x, 64, 'middle', 10, 'mono', fill='muted')]
    bg += [LN(460, 82, 580, 82, stroke='ink'), T('mm', 590, 86, size=10, fill='muted'),
           T('Fixed point', 30, 216), T('Sliding supports', 290, 216, 'middle'), T('Expansion indicator', 460, 40)]
    sups = [G([R(-12, 146, 24, 12, fill='ink'), C(-6, 164, 5, fill='muted'), C(6, 164, 5, fill='muted')],
              tf=[{'translate': [f's{x0}', 0]}]) for x0 in (180, 290, 400)]
    scene = [G(bg), R(66, 120, 'pw', 26, rx=4, fill={'of': 'v', 'stops': stops}, stroke='ink'), *sups,
             PATH([['M', 'ex', 84], ['L', 'exl', 74], ['L', 'exr', 74], ['Z']], fill='act'),
             LN('ex', 120, 'ex', 86, stroke='act', sw=2)]
    fig('expand', 'Pipe thermal expansion', 660, 270, 10,
        'A 30 m steam pipe held by a fixed point (anchor) at the left and sliding supports elsewhere. As it heats, it '
        'grows away from the anchor; each support slides by an amount proportional to its distance from the anchor. '
        'The expansion indicator at the free end shows the total growth. Movement is drawn about 45 times larger than '
        'life.',
        'A steam pipe anchored at the left end on sliding supports, growing to the right as it heats, with an '
        'expansion indicator at the free end.', scene, V,
        slider={'label': 'Pipe temperature', 'init': 0.5, 'drive': PING, 'text': '{temp} °C'},
        status='{temp} °C: the pipe is {dmm} mm longer than cold (30 m × 1.2×10⁻⁵ /K × {dk} K)')


BUILDERS = [gate, globe, check, quarter, safety, trap, pump, gear, gen, stage, circ, wall, orifice, gauge, damper, expand]


def build():
    F.clear()
    for b in BUILDERS:
        b()
    for fid, f in F.items():
        K.check_figure(f, fid)
    return dict(F)


# ---------------------------------------------------------------- SVG of an evaluated frame (for eyeballing)

LIGHT = {'ground': '#E9EDEF', 'surface': '#F8FAFA', 'sunk': '#DDE3E6', 'ink': '#16222B', 'muted': '#56646E',
         'rule': '#C6CFD4', 'accent': '#1F5F8B', 'ok': '#2E7A4E', 'alarm': '#9A6412', 'alarm_fill': '#E8B04A',
         'act': '#B3261E'}
FONTS = {'body': 'Atkinson Hyperlegible, sans-serif', 'display': 'Barlow Semi Condensed, sans-serif',
         'mono': 'JetBrains Mono, monospace'}


def svg_frame(fig_, ev):
    defs, n = [], [0]

    def paint(p):
        if isinstance(p, dict):
            n[0] += 1
            gid = f'g{n[0]}'
            stops = ''.join(f'<stop offset="{o}" stop-color="{LIGHT.get(c, c)}" stop-opacity="{a}"/>' for o, c, a in p['radial'])
            defs.append(f'<radialGradient id="{gid}" cx=".5" cy=".5" r=".5">{stops}</radialGradient>')
            return f'url(#{gid})'
        return LIGHT.get(p, p)

    def common(e):
        a = f' fill="{paint(e.get("fill", "none"))}" stroke="{paint(e.get("stroke", "none"))}"'
        a += f' stroke-width="{e.get("stroke_width", 1)}" opacity="{e.get("opacity", 1)}"'
        if 'dash' in e:
            a += f' stroke-dasharray="{" ".join(map(str, e["dash"]))}"'
        a += f' stroke-linecap="{e.get("cap", "butt")}" stroke-linejoin="{e.get("join", "miter")}"'
        if 'transform' in e:
            a += ' transform="' + ' '.join(
                f'{k}({" ".join(str(x) for x in v)})' for st in e['transform'] for k, v in st.items()) + '"'
        return a

    def el(e):
        if 'rect' in e:
            x, y, w, h = e['rect']
            return f'<rect x="{x}" y="{y}" width="{max(0, w)}" height="{max(0, h)}" rx="{e.get("rx", 0)}"{common(e)}/>'
        if 'circle' in e:
            return '<circle cx="{}" cy="{}" r="{}"'.format(*e['circle']) + common(e) + '/>'
        if 'ellipse' in e:
            return '<ellipse cx="{}" cy="{}" rx="{}" ry="{}"'.format(*e['ellipse']) + common(e) + '/>'
        if 'line' in e:
            x1, y1, x2, y2 = e['line']
            out = f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}"{common(e)}/>'
            if e.get('arrow'):
                w = e.get('stroke_width', 1)
                L = math.hypot(x2 - x1, y2 - y1) or 1
                ux, uy = (x2 - x1) / L, (y2 - y1) / L
                tx, ty = x2 + 1.2 * w * ux, y2 + 1.2 * w * uy
                bx, by = tx - 6 * w * ux, ty - 6 * w * uy
                out += (f'<path d="M{tx},{ty} L{bx - 3 * w * uy},{by + 3 * w * ux} L{bx + 3 * w * uy},{by - 3 * w * ux} Z" '
                        f'fill="{paint(e.get("stroke", "ink"))}" opacity="{e.get("opacity", 1)}"/>')
            return out
        if 'poly' in e:
            tag = 'polygon' if e.get('closed') else 'polyline'
            return f'<{tag} points="{" ".join(f"{x},{y}" for x, y in e["poly"])}"{common(e)}/>'
        if 'path' in e:
            d = ' '.join(c[0] + ','.join(str(x) for x in c[1:]) for c in e['path'])
            return f'<path d="{d}"{common(e)}/>'
        if 'text' in e:
            e2 = dict(e)
            e2.setdefault('fill', 'ink')
            anchor = e.get('anchor', 'start')
            import html
            return (f'<text x="{e["at"][0]}" y="{e["at"][1]}" text-anchor="{anchor}" font-size="{e.get("size", 12)}" '
                    f'font-family="{FONTS[e.get("font", "body")]}" font-weight="{e.get("weight", 400)}"'
                    f'{common(e2)}>{html.escape(e["text"])}</text>')
        if 'label' in e:
            import html
            (x1, y1), (x2, y2), (ex, ey) = e['at'], e['to'], e['end']
            return (f'<g><line x1="{x1}" y1="{y1}" x2="{ex}" y2="{ey}" stroke="{LIGHT["muted"]}" stroke-width="1"/>'
                    f'<circle cx="{x1}" cy="{y1}" r="2.5" fill="{LIGHT["muted"]}"/>'
                    f'<text x="{x2}" y="{y2}" text-anchor="{e.get("anchor", "start")}" font-size="12.5" '
                    f'font-family="{FONTS["body"]}" fill="{LIGHT["ink"]}">{html.escape(e["label"])}</text></g>')
        if 'group' in e:
            clip = ''
            if 'clip' in e:
                n[0] += 1
                x, y, w, h = e['clip']['rect']
                defs.append(f'<clipPath id="c{n[0]}"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{e["clip"]["rx"]}"/></clipPath>')
                clip = f' clip-path="url(#c{n[0]})"'
            tf = ''
            if 'transform' in e:
                tf = ' transform="' + ' '.join(
                    f'{k}({" ".join(str(x) for x in v)})' for st in e['transform'] for k, v in st.items()) + '"'
            return f'<g opacity="{e.get("opacity", 1)}"{tf}{clip}>' + ''.join(el(c) for c in e['group']) + '</g>'
        if 'flow' in e:
            fl = e['flow']
            out = ''
            for x, y, r, op, fill in fl['particles']:
                if op <= 0:
                    continue
                if fl.get('glyph') == 'burst':
                    k = 5 * r / 7
                    out += (f'<path d="M{x - r},{y} L{x + r},{y} M{x},{y - r} L{x},{y + r} M{x - k},{y - k} L{x + k},{y + k}" '
                            f'stroke="{paint(fl.get("stroke", "none"))}" stroke-width="{fl.get("stroke_width", 1)}" opacity="{op}"/>')
                else:
                    out += (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{paint(fill)}" stroke="{paint(fl.get("stroke", "none"))}" '
                            f'stroke-width="{fl.get("stroke_width", 1)}" opacity="{op}"/>')
            return out
        return ''
    body = ''.join(el(e) for e in ev.scene())
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {fig_["w"]} {fig_["h"]}" width="{fig_["w"]}" '
            f'height="{fig_["h"]}" style="background:{LIGHT["surface"]}"><defs>{"".join(defs)}</defs>{body}</svg>')


# check states: (id, t, v or None, toggles, mode)
STATES = [('gate', 0.3, 0.35), ('gate', 0.0, 0.9), ('globe', 0.3, 0.4), ('check', 0.2, None), ('check', 0.7, None),
          ('quarter', 0.3, 0.5), ('quarter', 0, 0.2), ('safety', 0.3, None), ('safety', 0.55, None), ('trap', 0.3, None),
          ('trap', 0.7, None), ('pump', 0.2, None, {'cav': 1}), ('gear', 0.4, None, {'blk': 1}), ('gen', 0.3, None),
          ('stage', 0.3, None), ('circ', 0.35, None, {'swell': 1}), ('wall', 0.5, 0.25), ('wall', 0.8, 0.9),
          ('orifice', 0.3, 0.8), ('gauge', 0.3, None, {}, 1), ('damper', 0.3, 0.5), ('expand', 0.3, 0.5)]


def evaluate_state(f, st):
    fid, t, v = st[:3]
    tg = st[3] if len(st) > 3 else {}
    mode = st[4] if len(st) > 4 else 0
    ev = K.Figure(f)
    ev.t = t
    if v is not None:
        ev.v = v
    ev.toggles.update({k: float(x) for k, x in tg.items()})
    ev.mode = mode
    ev.first = True
    ev._step(0.0)
    for _ in range(200):              # as the harness: 10 s at this state (smoothing settles, particles move)
        ev._step(0.05)
    return ev


HARNESS = """<!doctype html><meta charset=utf-8><style>:root{--ground:#E9EDEF;--surface:#F8FAFA;--sunk:#DDE3E6;--ink:#16222B;
--muted:#56646E;--rule:#C6CFD4;--accent:#1F5F8B;--ok:#2E7A4E;--alarm:#9A6412;--alarm-fill:#E8B04A;--act:#B3261E;
--display:'Barlow Semi Condensed';--mono:'JetBrains Mono'}body{margin:0;background:var(--surface)}</style>
<div id=s></div><script>%s
const d = VIS.D[%r]; const NS='http://www.w3.org/2000/svg';
const svg=document.createElementNS(NS,'svg'); svg.setAttribute('viewBox',`0 0 ${d.w} ${d.h}`); svg.setAttribute('width',d.w);
svg.setAttribute('height',d.h); document.getElementById('s').appendChild(svg);
const st={t:%r,dt:0,v:%r,opts:%s,mode:%s}; const draw=d.init(svg,st);
for(let i=0;i<200;i++){ st.dt=0.05; draw(st); } st.dt=0; draw(st);
</script>"""


if __name__ == '__main__':
    cmd = sys.argv[1]
    figs = build()
    if cmd == 'json':
        with open(sys.argv[2], 'w', encoding='utf-8') as fh:
            json.dump(figs, fh, ensure_ascii=False, indent=1)
        print(len(figs), 'figures valid;', os.path.getsize(sys.argv[2]) // 1024, 'KB')
    elif cmd == 'svg':
        out = sys.argv[2]
        os.makedirs(out, exist_ok=True)
        only = set(sys.argv[3:])
        for i, st in enumerate(STATES):
            if only and st[0] not in only:
                continue
            ev = evaluate_state(figs[st[0]], st)
            with open(os.path.join(out, f'{i:02d}-{st[0]}-ours.svg'), 'w', encoding='utf-8') as fh:
                fh.write(svg_frame(figs[st[0]], ev))
            print(i, st[0], '|', ev.status(), '|', ev.slider_text())
    elif cmd == 'harness':
        out, src = sys.argv[2], sys.argv[3]
        text_ = open(src, encoding='utf-8').read()
        a = text_.index('const VIS = (')
        b = text_.index('})();', a) + 5
        vis = text_[a:b].replace('const VIS', 'var VIS')
        os.makedirs(out, exist_ok=True)
        for i, st in enumerate(STATES):
            fid, t, v = st[:3]
            if f"D.{fid} =" not in vis:
                continue
            tg = st[3] if len(st) > 3 else {}
            mode = st[4] if len(st) > 4 else 0
            modes = [m['key'] for m in figs[fid].get('modes', [])]
            opts = json.dumps({k: bool(x) for k, x in tg.items()})
            mode_key = modes[mode] if modes else None
            vv = v if v is not None else figs[fid].get('slider', {}).get('init', 0)
            with open(os.path.join(out, f'{i:02d}-{fid}-orig.html'), 'w', encoding='utf-8') as fh:
                fh.write(HARNESS % (vis, fid, t, vv, opts, json.dumps(mode_key)))
