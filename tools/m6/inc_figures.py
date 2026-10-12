"""The figures of the Instrumentation and control course (course id `inc`) in the declarative model
(docs/COURSES.md §9). They are drawn here, not converted from anything: the course's text source only names each
figure and gives its title and caption, and tools/m6/convert_courses.py attaches the drawing by id.

  python3 tools/m6/inc_figures.py svg OUTDIR      one SVG per figure (animated ones at a few states), for eyeballing

Static figures have no `period`. The animated ones use a slider or the clock, like the 16 in course_figures.py."""
import math, os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref import courses as K
from course_figures import R, C, EL, LN, POLY, PATH, T, LAB, G, FLOW, PING, tab, lin, r4, steptab, arrow

PI = math.pi
F = {}


def put(fid, w, h, alt, scene, period=None, values=(), slider=None, status=None):
    """title and caption come from the course text (convert_courses.py); the ones here are placeholders"""
    f = {'title': fid, 'caption': [fid], 'alt': alt, 'w': w, 'h': h}
    if period:
        f['period'] = period
        f['values'] = [list(v) for v in values]
        if slider:
            f['slider'] = slider
        if status is not None:
            f['status'] = status
    f['scene'] = scene
    F[fid] = f


def box(x, y, w, h, title, sub=None, stroke='ink'):
    cx, cy = x + w / 2, y + h / 2
    out = [R(x, y, w, h, rx=5, fill='surface', stroke=stroke, sw=1.5),
           T(title, cx, cy + (-3 if sub else 5), 'middle', 15, 'display', 600)]
    if sub:
        out.append(T(sub, cx, cy + 14, 'middle', 11, fill='muted'))
    return out


def pts(fn, xs):
    return [[r4(x), r4(fn(x))] for x in xs]


# ---------------------------------------------------------------- 1: the loop

def loop():
    s = []
    s += box(30, 44, 150, 84, 'Steam drum', 'the process: level')
    s += box(245, 54, 140, 64, 'Transmitter (LT)', 'sensor + electronics')
    s += box(455, 44, 160, 84, 'Controller (DCS)', 'compares PV with SP')
    s += box(455, 214, 160, 64, 'Positioner', 'signal → air')
    s += box(245, 214, 140, 64, 'Control valve', 'final element')
    s += [arrow(180, 86, 241, 86, 'ink'), arrow(385, 86, 451, 86, 'accent'), T('4–20 mA', 418, 76, 'middle', 11.5, 'mono', fill='accent'),
          T('PV', 418, 104, 'middle', 11.5, fill='muted'),
          arrow(535, 128, 535, 210, 'accent'), T('4–20 mA', 545, 166, size=11.5, font='mono', fill='accent'),
          T('output', 545, 182, size=11.5, fill='muted'),
          arrow(455, 246, 389, 246, 'ink'), T('air', 422, 236, 'middle', 11.5, fill='muted'),
          PATH([['M', 245, 246], ['L', 105, 246], ['L', 105, 134]], stroke='ink', sw=2), arrow(105, 140, 105, 132, 'ink'),
          T('feedwater', 115, 236, size=11.5, fill='muted'),
          arrow(535, 14, 535, 40, 'act'), T('SP (setpoint)', 545, 26, size=11.5, fill='act')]
    put('loop', 640, 300, 'Block diagram of a drum level control loop: steam drum, level transmitter, controller in the '
        'DCS, positioner and feedwater control valve, joined in a ring by a 4 to 20 mA measurement signal, a 4 to 20 mA '
        'output signal, air and feedwater.', s)


# ---------------------------------------------------------------- 2: zero error, span error, hysteresis

def calerr():
    s = []
    names = ['Zero error', 'Span error', 'Hysteresis']
    for i, name in enumerate(names):
        x0, y0, w, h = 50 + i * 205, 210, 150, 150          # origin (bottom left) and size of the plot
        X = lambda f: x0 + f * w
        Y = lambda f: y0 - f * h
        s += [T(name, x0 + w / 2, 34, 'middle', 15, 'display', 600),
              LN(x0, y0, x0 + w, y0, stroke='muted'), LN(x0, y0, x0, y0 - h, stroke='muted'),
              T('0%', x0, y0 + 16, 'middle', 10.5, 'mono', fill='muted'), T('100%', x0 + w, y0 + 16, 'middle', 10.5, 'mono', fill='muted'),
              T('4', x0 - 6, y0 + 4, 'end', 10.5, 'mono', fill='muted'), T('20', x0 - 6, y0 - h + 4, 'end', 10.5, 'mono', fill='muted'),
              LN(X(0), Y(0), X(1), Y(1), stroke='muted', sw=2, dash=[5, 4])]
        if i == 0:
            s += [LN(X(0), Y(0.14), X(0.86), Y(1), stroke='act', sw=2.5),
                  LN(X(0.5), Y(0.5), X(0.5), Y(0.64), stroke='ink'), T('same everywhere', X(0.40), Y(0.10), size=11)]
        elif i == 1:
            s += [LN(X(0), Y(0), X(1), Y(0.8), stroke='act', sw=2.5),
                  LN(X(1), Y(1), X(1), Y(0.8), stroke='ink'), T('largest at the top', X(0.36), Y(0.10), size=11)]
        else:
            up = [[r4(X(k / 24)), r4(Y(k / 24 - 0.09 * math.sin(PI * k / 24)))] for k in range(25)]
            dn = [[r4(X(k / 24)), r4(Y(k / 24 + 0.09 * math.sin(PI * k / 24)))] for k in range(25)]
            s += [POLY(up, stroke='act', sw=2.5), POLY(dn, stroke='accent', sw=2.5),
                  T('falling', X(0.30), Y(0.56), 'end', 11, fill='accent'), T('rising', X(0.66), Y(0.44), size=11, fill='act')]
    s += [T('input', 125, 244, 'middle', 11, fill='muted'), T('output, mA', 14, 140, 'middle', 11, fill='muted',
                                                                tf=[{'rotate': [-90, 14, 140]}]),
          LN(470, 244, 500, 244, stroke='muted', sw=2, dash=[5, 4]), T('ideal', 506, 248, size=11, fill='muted'),
          LN(560, 244, 590, 244, stroke='act', sw=2.5), T('actual', 596, 248, size=11, fill='muted')]
    put('calerr', 660, 262, 'Three small charts of transmitter output against input. In the first the actual line is '
        'parallel to the ideal line and above it (zero error). In the second it starts at the right point and falls '
        'away towards the top (span error). In the third the rising and falling readings form a loop around the ideal '
        'line (hysteresis).', s)


# ---------------------------------------------------------------- 3 and 15: the two-wire loop and where to measure

def circuit(points):
    L, Rt, Tp, B = 110, 530, 70, 232
    s = [PATH([['M', L, 122], ['L', L, Tp], ['L', Rt, Tp], ['L', Rt, 118]], stroke='ink', sw=2),
         PATH([['M', Rt, 186], ['L', Rt, B], ['L', 372, B]], stroke='ink', sw=2),
         PATH([['M', 268, B], ['L', L, B], ['L', L, 186]], stroke='ink', sw=2)]
    s += box(60, 122, 100, 64, '24 V DC', 'supply')
    s += box(470, 118, 120, 68, 'Transmitter', 'two-wire')
    s += [T('+', 98, 112, 'middle', 14, 'mono', 600), T('−', 98, 204, 'middle', 14, 'mono', 600),
          T('+', 518, 108, 'middle', 14, 'mono', 600), T('−', 518, 204, 'middle', 14, 'mono', 600),
          arrow(250, Tp, 300, Tp, 'accent'), T('I', 276, 58, 'middle', 13, 'mono', 600, fill='accent'),
          R(268, B - 12, 104, 24, fill='surface', stroke='ink', sw=1.5), T('250 Ω', 320, B + 5, 'middle', 12, 'mono'),
          R(238, B - 36, 164, 62, rx=6, stroke='muted', dash=[4, 4]), T('DCS input card', 320, B - 42, 'middle', 11, fill='muted')]
    if not points:
        # meter A in series in the top wire, meter V across the resistor
        s += [R(370, Tp - 4, 60, 8, fill='surface'), C(400, Tp, 20, fill='surface', stroke='accent', sw=2),
              T('A', 400, Tp + 5, 'middle', 14, 'mono', 600, fill='accent'),
              T('in series: 4–20 mA', 400, 40, 'middle', 11.5, fill='accent'),
              PATH([['M', 262, B], ['L', 262, 292], ['L', 300, 292]], stroke='act', sw=1.5),
              PATH([['M', 378, B], ['L', 378, 292], ['L', 340, 292]], stroke='act', sw=1.5),
              C(262, B, 3, fill='act'), C(378, B, 3, fill='act'),
              C(320, 292, 20, fill='surface', stroke='act', sw=2), T('V', 320, 297, 'middle', 14, 'mono', 600, fill='act'),
              T('across the resistor: 1–5 V', 400, 296, size=11.5, fill='act')]
    else:
        s += [R(290, Tp - 13, 60, 26, rx=4, fill='surface', stroke='ink', sw=1.5), T('junction box', 320, Tp - 20, 'middle', 11, fill='muted')]
        s = [e for e in s if e.get('text') != 'I' and not e.get('arrow')]     # the junction box takes the arrow's place
        for n, x, y, lab, lx, ly, anc in ((1, 110, 70, 'supply: 24 V', 128, 92, 'start'),
                                          (2, 320, 282, 'across the resistor: 1–5 V', 338, 286, 'start'),
                                          (3, 530, 70, 'at the transmitter', 512, 92, 'end'),
                                          (4, 530, 232, 'current: 4–20 mA', 512, 254, 'end')):
            s += [C(x, y, 11, fill='accent'), T(str(n), x, y + 4.5, 'middle', 13, 'mono', 600, fill='surface'),
                  T(lab, lx, ly, anc, 11.5)]
    return s


def meterconn():
    put('meterconn', 640, 324, 'Circuit of a two-wire loop: a 24 volt supply, a transmitter and the 250 ohm resistor of '
        'the DCS input card in one ring. An ammeter is drawn in series in the ring. A voltmeter is drawn across the '
        'resistor.', circuit(False))


def faultpts():
    put('faultpts', 640, 310, 'The two-wire loop with a junction box, and four numbered test points: 1 at the supply, 2 '
        'across the input resistor, 3 at the transmitter terminals, 4 for the current at the transmitter.', circuit(True))


# ---------------------------------------------------------------- 4: one value, four signals (slider)

def scale():
    X0, W = 130, 440
    rows = [('Percent', ['0', '25', '50', '75', '100'], '%'), ('Range', ['0', '50', '100', '150', '200'], '°C'),
            ('Current', ['4', '8', '12', '16', '20'], 'mA'), ('Across 250 Ω', ['1', '2', '3', '4', '5'], 'V'),
            ('Air signal', ['3', '6', '9', '12', '15'], 'psi')]
    V = [('pct', {'product': ['v', 100]}), ('degc', {'product': ['v', 200]}), ('ma', tab('v', lambda v: 4 + 16 * v, [0, 1])),
         ('volt', tab('v', lambda v: 1 + 4 * v, [0, 1])), ('psi', tab('v', lambda v: 3 + 12 * v, [0, 1])),
         ('bw', {'product': ['v', W]}), ('cx', {'sum': ['bw', X0]})]
    s = []
    for i, (name, ticks, unit) in enumerate(rows):
        y = 50 + i * 50
        s += [T(name, 20, y + 5, size=12.5, weight=600), R(X0, y - 9, W, 18, fill='sunk'), R(X0, y - 9, 'bw', 18, fill='accent', op=.35),
              T(unit, X0 + W + 14, y + 5, size=12, font='mono', fill='muted')]
        for k, tk in enumerate(ticks):
            x = X0 + W * k / 4
            s += [LN(x, y + 9, x, y + 15, stroke='muted'), T(tk, x, y + 28, 'middle', 11, 'mono', fill='muted')]
    s += [LN('cx', 30, 'cx', 272, stroke='act', sw=2), C('cx', 30, 4, fill='act')]
    put('scale', 640, 290, 'Five bars one under the other: percent, degrees Celsius for a 0 to 200 range, milliamps from '
        '4 to 20, volts from 1 to 5 and psi from 3 to 15. One vertical cursor crosses all five at the same position.', s,
        period=14, values=V, slider={'label': 'Measurement', 'init': 0.5, 'drive': PING, 'text': '{pct}%'},
        status='{pct}% = {degc} °C = {ma:2} mA = {volt:2} V across 250 Ω = {psi:1} psi')


# ---------------------------------------------------------------- 5: the bridge

def wbridge():
    top, right, bot, left = (300, 50), (430, 170), (300, 290), (170, 170)
    s = [PATH([['M', *top], ['L', *right], ['L', *bot], ['L', *left], ['Z']], stroke='ink', sw=2),
         PATH([['M', *top], ['L', 300, 24], ['L', 70, 24], ['L', 70, 138]], stroke='ink', sw=2),
         PATH([['M', *bot], ['L', 300, 316], ['L', 70, 316], ['L', 70, 202]], stroke='ink', sw=2)]
    s += box(25, 138, 90, 64, 'Vex', 'excitation')
    arms = [(top, left, 'R1', False), (top, right, 'Gauge', True), (left, bot, 'R3', False), (right, bot, 'R4', False)]
    for (a, b, name, active) in arms:
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        ang = math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))
        s.append(R(mx - 30, my - 10, 60, 20, fill='surface', stroke='act' if active else 'ink', sw=2.5 if active else 1.5,
                   tf=[{'rotate': [r4(ang), mx, my]}]))
        dx = -46 if mx < 300 else 46
        dy = -14 if my < 170 else 22
        s.append(T(name, mx + dx, my + dy, 'end' if mx < 300 else 'start', 12.5, weight=600 if active else 400,
                   fill='act' if active else 'ink'))
    s += [LN(left[0], 170, 270, 170, stroke='accent', sw=2), LN(330, 170, right[0], 170, stroke='accent', sw=2),
          C(300, 170, 30, fill='surface', stroke='accent', sw=2), T('mV', 300, 175, 'middle', 14, 'mono', 600, fill='accent'),
          C(*left, 4, fill='ink'), C(*right, 4, fill='ink'), C(*top, 4, fill='ink'), C(*bot, 4, fill='ink'),
          T('output', 300, 216, 'middle', 11.5, fill='accent'),
          T('changes when stretched', 411, 112, size=11.5, fill='act'),
          T('Balanced: all four equal, output 0', 458, 276, size=11.5, fill='muted'),
          T('Gauge changes: output moves', 458, 294, size=11.5, fill='muted')]
    put('wbridge', 660, 340, 'A Wheatstone bridge: four resistors in a diamond, one of them a strain gauge. The '
        'excitation supply is connected to the top and bottom corners. A millivolt meter is connected between the left '
        'and right corners.', s)


# ---------------------------------------------------------------- 6: the LVDT (slider)

def lvdt():
    V = [('pos', tab('v', lambda v: 2 * v - 1, [0, 1])), ('mm', {'product': ['pos', 25]}),
         ('s1', tab('pos', lambda p: 1.5 - 1.2 * p, [-1, 1])), ('s2', tab('pos', lambda p: 1.5 + 1.2 * p, [-1, 1])),
         ('out', {'product': ['pos', 2.4]}),
         ('cx', tab('pos', lambda p: 230 + 60 * p, [-1, 1])), ('rodx', {'sum': ['cx', 180]}),
         ('rodw', tab('pos', lambda p: 600 - (410 + 60 * p), [-1, 1])),
         ('b1', tab('pos', lambda p: (1.5 - 1.2 * p) * 70, [-1, 1])), ('b2', tab('pos', lambda p: (1.5 + 1.2 * p) * 70, [-1, 1])),
         ('ox', tab('pos', lambda p: 320 + min(0, p) * 168, [-1, 0, 1])), ('ow', tab('pos', lambda p: abs(p) * 168, [-1, 0, 1]))]
    coils = [(140, 'Secondary 1', 'muted'), (270, 'Primary', 'accent'), (400, 'Secondary 2', 'muted')]
    s = [R(120, 96, 400, 60, fill='ground', stroke='ink', sw=1.5)]
    for x, name, c in coils:
        s += [R(x, 76, 100, 20, fill=c, op=.8), R(x, 156, 100, 20, fill=c, op=.8)]
        s += [LN(x + 10 * k, 76, x + 10 * k, 96, stroke='surface') for k in range(1, 10)]
        s += [LN(x + 10 * k, 156, x + 10 * k, 176, stroke='surface') for k in range(1, 10)]
        s.append(T(name, x + 50, 66, 'middle', 12, weight=600 if c == 'accent' else 400, fill='accent' if c == 'accent' else 'ink'))
    s += [T('AC supply', 320, 50, 'middle', 11, fill='accent'),
          R('rodx', 121, 'rodw', 10, fill='muted'), R('cx', 112, 180, 28, rx=3, fill='ink', op=.75),
          T('Iron core', 150, 200, size=12), LN(150, 190, 'cx', 142, stroke='muted'),
          T('to the stem', 560, 112, 'middle', 11, fill='muted'),
          LN(320, 92, 320, 160, stroke='act', dash=[3, 3]), T('centre (null)', 326, 200, size=11, fill='act'),
          T('Secondary 1', 20, 244, size=12), R(130, 232, 'b1', 14, fill='muted'),
          T('Secondary 2', 20, 272, size=12), R(130, 260, 'b2', 14, fill='muted'),
          T('Output', 20, 306, size=12, weight=600), LN(152, 299, 488, 299, stroke='rule', sw=2), R('ox', 290, 'ow', 18, fill='act'),
          LN(320, 284, 320, 314, stroke='ink', sw=1.5), T('−', 140, 304, 'end', 14, 'mono'), T('+', 500, 304, size=14, font='mono')]
    put('lvdt', 640, 330, 'Cutaway of an LVDT: a tube with a primary coil in the middle and a secondary coil on each side, '
        'and an iron core that slides inside. Bars below show the voltage of each secondary and their difference, which '
        'is zero when the core is centred.', s, period=12, values=V,
        slider={'label': 'Core position', 'init': 0.5,
                'drive': tab('t', lambda t: 0.5 + 0.5 * math.sin(2 * PI * t), lin(0, 1, 65)), 'text': '{mm:+1} mm'},
        status='Core {mm:+1} mm from centre: secondary 1 {s1:2} V, secondary 2 {s2:2} V, difference {out:+2} V')


# ---------------------------------------------------------------- 7 and 8: filter and dead band (computed traces)

def noise(k):
    return 0.6 * math.sin(k * 1.9) + 0.45 * math.sin(k * 3.7 + 1.0) + 0.35 * math.sin(k * 7.3 + 2.0)


def lowpass():
    n = 240
    X = lambda k: 60 + k * 540 / (n - 1)
    Y = lambda v: 210 - v * 170
    base = lambda k: 0.25 + 0.5 / (1 + math.exp(-(k - 95) / 9.0))
    raw = [base(k) + 0.07 * noise(k) for k in range(n)]
    filt, y = [], raw[0]
    for v in raw:
        y += (v - y) * 0.07
        filt.append(y)
    s = [LN(60, 210, 600, 210, stroke='muted'), LN(60, 40, 60, 210, stroke='muted'),
         T('time', 330, 232, 'middle', 11.5, fill='muted'),
         T('signal', 34, 125, 'middle', 11.5, fill='muted', tf=[{'rotate': [-90, 34, 125]}]),
         POLY([[r4(X(k)), r4(Y(v))] for k, v in enumerate(raw)], stroke='muted', sw=1),
         POLY([[r4(X(k)), r4(Y(v))] for k, v in enumerate(filt)], stroke='accent', sw=3),
         LN(410, 232, 440, 232, stroke='muted'), T('raw', 446, 236, size=11.5, fill='muted'),
         LN(490, 232, 520, 232, stroke='accent', sw=3), T('filtered', 526, 236, size=11.5, fill='muted'),
         T('the filtered signal follows late', 322, 150, size=11.5), LN(318, 146, 296, 128, stroke='ink')]
    put('lowpass', 640, 246, 'A chart of a signal against time. A thin noisy line rises from a low to a high value. A '
        'thick smooth line follows it without the noise, a little later.', s)


def deadband():
    n = 220
    X = lambda k: 70 + k * 450 / (n - 1)
    Y = lambda v: 150 - (v - 0.7) * 600
    sig = [0.785 + 0.085 * math.sin((k - 40) * PI / 150) + 0.012 * noise(k) for k in range(n)]
    on, off = 0.80, 0.77
    single = [1 if v >= on else 0 for v in sig]
    db, st = [], 0
    for v in sig:
        st = 1 if v >= on else 0 if v <= off else st
        db.append(st)

    def steps(bits, y0):
        p = [[r4(X(0)), y0 - 18 * bits[0]]]
        for k in range(1, n):
            if bits[k] != bits[k - 1]:
                p += [[r4(X(k)), y0 - 18 * bits[k - 1]], [r4(X(k)), y0 - 18 * bits[k]]]
        p.append([r4(X(n - 1)), y0 - 18 * bits[-1]])
        return p
    s = [LN(70, 30, 70, 160, stroke='muted'), LN(70, 160, 520, 160, stroke='muted'),
         LN(70, Y(on), 520, Y(on), stroke='act', dash=[6, 4]), T('on: 80%', 526, Y(on) + 4, size=11, font='mono', fill='act'),
         LN(70, Y(off), 520, Y(off), stroke='accent', dash=[6, 4]), T('off: 77%', 526, Y(off) + 4, size=11, font='mono', fill='accent'),
         POLY([[r4(X(k)), r4(Y(v))] for k, v in enumerate(sig)], stroke='ink', sw=1.5),
         T('level signal', 76, 26, size=11.5, fill='muted'),
         T('One threshold', 64, 206, 'end', 11.5), POLY(steps(single, 210), stroke='act', sw=2),
         T('With dead band', 64, 256, 'end', 11.5), POLY(steps(db, 260), stroke='accent', sw=2.5),
         T('chatters', 526, 206, size=11, fill='act'), T('one clean switch', 526, 256, size=11, fill='accent')]
    put('deadband', 700, 280, 'Top: a noisy level signal rises through two dashed lines at 80 and 77 percent and later '
        'falls back through them. Middle: the output of a switch with a single threshold flips many times at each '
        'crossing. Bottom: the output of a switch with a dead band changes once on the way up and once on the way down.',
        [G(s, tf=[{'translate': [44, 0]}])])


# ---------------------------------------------------------------- 9: toothed wheel and pickup (rotates)

def pickup():
    cx, cy, r0, r1, nt = 150, 150, 78, 96, 12
    wheel = []
    for k in range(nt):
        a0 = 2 * PI * k / nt
        for da, r in ((-0.11, r0), (-0.08, r1), (0.08, r1), (0.11, r0)):
            wheel.append([r4(cx + r * math.cos(a0 + da)), r4(cy + r * math.sin(a0 + da))])
        for j in range(1, 4):                                  # the root between two teeth, on the circle
            a = a0 + 0.11 + (2 * PI / nt - 0.22) * j / 4
            wheel.append([r4(cx + r0 * math.cos(a)), r4(cy + r0 * math.sin(a))])
    V = [('ang', tab('t', lambda t: 360 * t / nt * 3, [0, 1]))]      # three tooth pitches per loop: seamless
    s = [G([POLY(wheel, closed=True, fill='sunk', stroke='ink', sw=2), C(cx, cy, 16, fill='surface', stroke='ink', sw=1.5),
            LN(cx, cy - 16, cx, cy - r0 + 8, stroke='muted', sw=1)], tf=[{'rotate': ['ang', cx, cy]}]),
         R(254, 138, 70, 24, rx=3, fill='surface', stroke='ink', sw=2), R(250, 143, 8, 14, fill='ink'),
         PATH([['M', 324, 150], ['C', 350, 150, 350, 120, 380, 120]], stroke='ink', sw=2),
         LAB('Pickup', 290, 138, 300, 100), LAB('Gap, about 1 mm', 248, 164, 256, 200),
         LAB('Toothed wheel', 150, 250, 100, 280)]
    # traces: raw pickup signal and shaped pulses
    X0, X1, per = 400, 650, 50
    raw = [[r4(x), r4(110 - 26 * math.sin(2 * PI * (x - X0) / per) * (1 + 0.15 * math.sin((x - X0) * 0.9)))] for x in lin(X0, X1, 126)]
    sq = [[X0, 214]]
    for k in range(int((X1 - X0) / per)):
        x = X0 + k * per
        sq += [[x, 214], [x, 184], [x + per / 2, 184], [x + per / 2, 214], [x + per, 214]]
    s += [T('Raw signal of a magnetic pickup', X0, 66, size=11.5, fill='muted'), LN(X0, 110, X1, 110, stroke='rule'),
          POLY(raw, stroke='ink', sw=1.5),
          T('After shaping: one clean pulse per tooth', X0, 170, size=11.5, fill='muted'), POLY(sq, stroke='accent', sw=2.5),
          LN(X0, 232, X0 + per, 232, stroke='muted'), LN(X0, 227, X0, 237, stroke='muted'), LN(X0 + per, 227, X0 + per, 237, stroke='muted'),
          T('one tooth', X0 + per / 2, 250, 'middle', 11, fill='muted')]
    put('pickup', 680, 300, 'A toothed wheel turning in front of a pickup with a small gap. Beside it two traces: the '
        'rounded raw signal of a magnetic pickup, and square pulses after shaping, one per tooth.', s, period=6, values=V,
        status='Each passing tooth makes one pulse: frequency = teeth × rpm ÷ 60')


# ---------------------------------------------------------------- 10: I/P converter (slider)

def ipconv():
    PX, PY = 320, 172                                          # pivot
    V = [('ma', tab('v', lambda v: 4 + 16 * v, [0, 1])), ('psi', tab('v', lambda v: 3 + 12 * v, [0, 1])),
         ('bar', tab('v', lambda v: 0.2 + 0.8 * v, [0, 1])),
         ('yr', tab('v', lambda v: PY + 4 - 8 * v, [0, 1])),            # right end of the flapper (x = 520)
         ('yl', tab('v', lambda v: PY - (4 - 8 * v) * 1.2, [0, 1])),    # left end (x = 80)
         ('bt', tab('v', lambda v: PY - (4 - 8 * v) * 1.0 + 4, [0, 1])),  # top of the bellows (x = 120)
         ('bh', tab('v', lambda v: 240 - (PY - (4 - 8 * v) * 1.0 + 4), [0, 1])),
         ('leak', tab('v', lambda v: 0.95 - 0.8 * v, [0, 1])), ('lspd', tab('v', lambda v: 70 - 45 * v, [0, 1])),
         ('gh', {'product': ['v', 84]}), ('gy', tab('v', lambda v: 150 - 84 * v, [0, 1]))]
    air = dict(stroke='accent', sw=3)
    s = [
        # air: supply → relay; supply → restriction → nozzle; nozzle pressure → relay; relay → output and bellows
        PATH([['M', 610, 296], ['L', 500, 296]], **air), PATH([['M', 580, 296], ['L', 580, 96], ['L', 500, 96], ['L', 500, 120]], **air),
        PATH([['M', 580, 236], ['L', 450, 236], ['L', 450, 272]], **air),
        PATH([['M', 400, 296], ['L', 44, 296]], **air), arrow(52, 296, 40, 296, 'accent', 3),
        PATH([['M', 120, 296], ['L', 120, 240]], **air),
        R(572, 258, 16, 16, fill='surface', stroke='ink', sw=1.5), LN(576, 266, 584, 266, stroke='accent', sw=1.5),
        R(400, 272, 100, 48, rx=5, fill='surface', stroke='ink', sw=1.5), T('Relay', 450, 301, 'middle', 14, 'display', 600),
        # nozzle
        R(492, 120, 16, 40, fill='surface', stroke='ink', sw=1.5), R(497, 120, 6, 40, fill='accent', op=.5),
        FLOW(count=10, routes=[{'path': [['M', 500, 163], ['L', 452, 166]]}, {'path': [['M', 500, 163], ['L', 548, 160]]}],
             speed='lspd', r=2.2, opacity='leak', along={'opacity': [[0, 1], [1, 0]]}),
        # bellows, coil, pivot, flapper
        R(100, 'bt', 40, 'bh', fill='surface', stroke='ink', sw=1.5),
        *[LN(100, y, 140, y, stroke='muted') for y in (200, 210, 220, 230)],
        R(180, 196, 44, 48, fill='alarm_fill', stroke='ink', sw=1.5), *[LN(180, y, 224, y, stroke='ink', op=.5) for y in (206, 216, 226, 236)],
        PATH([['M', 192, 244], ['L', 192, 262]], stroke='ink', sw=1.5), PATH([['M', 212, 244], ['L', 212, 262]], stroke='ink', sw=1.5),
        T('4–20 mA', 202, 278, 'middle', 11.5, 'mono', fill='ink'),
        PATH([['M', PX, PY + 3], ['L', PX - 14, 204], ['L', PX + 14, 204], ['Z']], fill='muted', stroke='ink'),
        LN(80, 'yl', 520, 'yr', stroke='ink', sw=6, cap='round'), C(PX, PY, 5, fill='surface', stroke='ink', sw=1.5),
        # output gauge
        R(30, 66, 22, 84, fill='sunk', stroke='ink'), R(30, 'gy', 22, 'gh', fill='accent', op=.7),
        T('15', 58, 72, size=10.5, font='mono', fill='muted'), T('3', 58, 152, size=10.5, font='mono', fill='muted'),
        T('Output, psi', 20, 54, size=11.5, fill='muted'),
        T('Supply air, 20 psi', 606, 318, 'end', 11.5, fill='muted'), T('To the valve', 48, 318, size=11.5, fill='muted'),
        G([LAB('Nozzle', 508, 130, 540, 60), LAB('Flapper', 400, 168, 380, 130), LAB('Pivot', 326, 198, 340, 226),
           LAB('Coil', 202, 200, 232, 150, None), LAB('Feedback bellows', 106, 214, 150, 120),
           LAB('Restriction', 572, 266, 474, 258)])]
    put('ipconv', 640, 330, 'Diagram of an I/P converter. A flapper beam on a pivot has a coil and a feedback bellows under '
        'its left end and a nozzle above its right end. Supply air reaches the nozzle through a restriction; the pressure '
        'behind the nozzle controls a relay whose output goes to the valve and back to the bellows.', s, period=12, values=V,
        slider={'label': 'Input current', 'init': 0.5, 'drive': PING, 'text': '{ma:1} mA'},
        status='{ma:1} mA in → {psi:1} psi out ({bar:2} bar)')


# ---------------------------------------------------------------- 11: peak, peak-to-peak, RMS

def vibwave():
    X0, X1, YC, A = 70, 400, 140, 90
    wave = [[r4(x), r4(YC - A * math.sin(2 * PI * (x - X0) / (X1 - X0)))] for x in lin(X0, X1, 81)]
    xc, xt = X0 + (X1 - X0) / 4, X0 + 3 * (X1 - X0) / 4
    s = [LN(X0 - 20, YC, X1 + 230, YC, stroke='muted'), T('rest position', X1 + 36, YC + 16, size=11, fill='muted'),
         POLY(wave, stroke='accent', sw=3),
         LN(X0, YC - A, X1 + 210, YC - A, stroke='rule', dash=[3, 4]), LN(xt, YC + A, X1 + 210, YC + A, stroke='rule', dash=[3, 4]),
         LN(X0, r4(YC - 0.707 * A), X1 + 30, r4(YC - 0.707 * A), stroke='ok', sw=1.5, dash=[6, 4]),
         T('RMS = 0.707 × peak', X1 + 36, r4(YC - 0.707 * A) + 4, size=11.5, fill='ok'),
         arrow(xc, YC, xc, YC - A + 3, 'ink', 1.5), arrow(xc, YC - A, xc, YC - 3, 'ink', 1.5),
         T('peak', xc - 8, YC - A / 2 + 10, 'end', 12, weight=600),
         arrow(X1 + 200, YC + A, X1 + 200, YC - A + 3, 'act', 1.5), arrow(X1 + 200, YC - A, X1 + 200, YC + A - 3, 'act', 1.5),
         T('peak-to-peak', X1 + 192, YC + 40, 'end', 12, weight=600, fill='act'), T('= 2 × peak', X1 + 192, YC + 56, 'end', 11.5, fill='act'),
         T('one turn of the shaft', (X0 + X1) / 2, 262, 'middle', 11.5, fill='muted'),
         LN(X0, 246, X1, 246, stroke='muted'), LN(X0, 241, X0, 251, stroke='muted'), LN(X1, 241, X1, 251, stroke='muted')]
    put('vibwave', 640, 276, 'One cycle of a sine wave around a centre line, with three measures marked: peak from the '
        'centre to the top, peak-to-peak from the bottom to the top, and RMS as a dashed line at 0.707 of the peak.', s)


# ---------------------------------------------------------------- 12: displacement, velocity, acceleration against frequency

def dva():
    X0, X1, YB, YT = 90, 560, 230, 50
    lx = lambda f: X0 + (math.log10(f) - 1) / 2 * (X1 - X0)       # 10 … 1000 Hz
    ymid = (YB + YT) / 2
    s = [LN(X0, YB, X1, YB, stroke='muted'), LN(X0, YT - 10, X0, YB, stroke='muted')]
    for f, rpm in ((10, '600'), (100, '6000'), (1000, '60 000')):
        s += [LN(lx(f), YB, lx(f), YB + 5, stroke='muted'), T(f'{f} Hz', lx(f), YB + 20, 'middle', 11, 'mono', fill='muted'),
              T(f'{rpm} rpm', lx(f), YB + 35, 'middle', 10.5, 'mono', fill='muted'),
              LN(lx(f), YT - 10, lx(f), YB, stroke='rule', dash=[2, 4])]
    s += [LN(X0, YB - 20, X1, YT + 20, stroke='act', sw=2.5), LN(X0, YT + 20, X1, YB - 20, stroke='accent', sw=2.5),
          LN(X0, ymid, X1, ymid, stroke='ink', sw=2.5),
          T('Displacement', X0 + 8, YT - 6, size=12.5, weight=600, fill='accent'), T('Acceleration', X1 - 8, YT - 6, 'end', 12.5, weight=600, fill='act'),
          T('Velocity: 5 mm/s peak', (X0 + X1) / 2, YT + 10, 'middle', 12, weight=600), LN((X0 + X1) / 2, YT + 16, (X0 + X1) / 2, ymid - 4, stroke='ink'),
          T('159 µm', X0 + 8, YT + 10, size=11, font='mono', fill='accent'), T('1.6 µm', X1 + 8, YB - 16, size=11, font='mono', fill='accent'),
          T('16 µm', lx(100) + 10, ymid + 22, size=11, font='mono', fill='accent'),
          T('0.03 g', X0 + 8, YB - 5, size=11, font='mono', fill='act'), T('3.2 g', X1 + 8, YT + 24, size=11, font='mono', fill='act'),
          T('0.32 g', lx(100) + 10, ymid + 38, size=11, font='mono', fill='act'),
          T('larger', 60, YT + 4, 'middle', 11, fill='muted'), T('smaller', 60, YB - 4, 'middle', 11, fill='muted'),
          T('Displacement in µm peak-to-peak, acceleration in g peak', (X0 + X1) / 2, YB + 56, 'middle', 11, fill='muted')]
    put('dva', 660, 296, 'Chart against frequency from 10 to 1000 hertz. Velocity is a level line. Displacement falls '
        'from 159 micrometres at 10 hertz to 1.6 micrometres at 1000 hertz. Acceleration rises from 0.03 g to 3.2 g.', s)


# ---------------------------------------------------------------- 13: proximity probe, gap and voltage (slider)

def gapvolt(g):
    """a typical 8 mm probe system: linear 7.87 V/mm from 0.25 to 2.25 mm, bending off outside it"""
    table = [(0, 0.6), (0.1, 1.0), (0.25, 2.0), (2.25, 2.0 + 7.87 * 2.0), (2.5, 19.3), (2.75, 20.4), (3.0, 21.0)]
    for (g0, v0), (g1, v1) in zip(table, table[1:]):
        if g <= g1:
            return v0 + (v1 - v0) * (g - g0) / (g1 - g0)
    return table[-1][1]


def probe():
    MM = 44                                                    # px per mm in the cutaway
    TIP = 196
    CX0, CX1, CYB, CYT = 456, 650, 250, 50                     # chart
    gx = lambda g: CX0 + g / 3 * (CX1 - CX0)
    vy = lambda v: CYB - v / 24 * (CYB - CYT)
    gs = sorted(set(lin(0, 3, 31) + [0.25, 2.25]))
    V = [('gap', {'product': ['v', 3]}), ('volt', {'of': 'gap', 'table': [[r4(g), r4(gapvolt(g))] for g in gs]}),
         ('nv', {'product': ['volt', -1]}), ('inlin', steptab('gap', [(0, 0), (0.25, 1), (2.2501, 0)])),
         ('sx', tab('gap', lambda g: TIP + g * MM, [0, 3])), ('sw', tab('gap', lambda g: 400 - (TIP + g * MM), [0, 3])), ('shc', tab('gap', lambda g: (400 + TIP + g * MM) / 2, [0, 3])),
         ('ex', tab('gap', lambda g: TIP + g * MM + 7, [0, 3])), ('eop', tab('gap', lambda g: max(0.08, 1 - g / 2.6), [0, 2.6, 3])),
         ('px', tab('gap', gx, [0, 3])), ('py', {'of': 'gap', 'table': [[r4(g), r4(vy(gapvolt(g)))] for g in gs]})]
    s = [
        # probe: threaded body, tip with the coil, cable
        R(60, 128, 110, 44, fill='surface', stroke='ink', sw=2), *[LN(x, 128, x, 172, stroke='muted') for x in range(70, 170, 10)],
        R(170, 134, 26, 32, rx=3, fill='sunk', stroke='ink', sw=2), R(184, 138, 8, 24, fill='accent'),
        PATH([['M', 60, 150], ['C', 30, 150, 40, 210, 20, 222]], stroke='ink', sw=3),
        # shaft surface, moving with the gap
        R('sx', 60, 'sw', 180, fill='sunk', stroke='ink', sw=2),
        EL('ex', 150, 4, 30, stroke='act', sw=2, op='eop'), EL('ex', 150, 2, 16, stroke='act', sw=2, op='eop'),
        LN(TIP, 246, TIP, 264, stroke='ink'), LN('sx', 246, 'sx', 264, stroke='ink'), LN(TIP, 255, 'sx', 255, stroke='ink'),
        T('gap', TIP, 282, size=12, weight=600),
        T('Shaft', 'shc', 84, 'middle', 13, 'display', 600),
        G([LAB('Probe tip with coil', 188, 138, 60, 70), LAB('Cable to the driver', 34, 196, 30, 244),
           LAB('Eddy currents', 'ex', 122, 216, 40)]),
        # chart
        R(gx(0.25), CYT, gx(2.25) - gx(0.25), CYB - CYT, fill='ok', op=.14),
        T('linear range', gx(1.25), CYT + 16, 'middle', 11.5, fill='ok'),
        LN(CX0, CYB, CX1, CYB, stroke='muted'), LN(CX0, CYT, CX0, CYB, stroke='muted'),
        *[e for g in (0, 1, 2, 3) for e in (LN(gx(g), CYB, gx(g), CYB + 5, stroke='muted'),
                                            T(str(g), gx(g), CYB + 19, 'middle', 11, 'mono', fill='muted'))],
        *[e for v in (0, 10, 20) for e in (LN(CX0 - 5, vy(v), CX0, vy(v), stroke='muted'),
                                           T(('−' if v else '') + str(v), CX0 - 8, vy(v) + 4, 'end', 11, 'mono', fill='muted'))],
        T('gap, mm', (CX0 + CX1) / 2, CYB + 38, 'middle', 11.5, fill='muted'), T('output, V DC', CX0 - 4, CYT - 12, size=11.5, fill='muted'),
        POLY([[r4(gx(g)), r4(vy(gapvolt(g)))] for g in gs], stroke='accent', sw=2.5),
        LN('px', CYB, 'px', 'py', stroke='act', dash=[3, 3]), LN(CX0, 'py', 'px', 'py', stroke='act', dash=[3, 3]),
        C('px', 'py', 5.5, fill='act')]
    put('probe', 680, 300, 'Left: an eddy-current probe facing a shaft surface across a gap that changes. Right: a chart '
        'of the output voltage against the gap, a straight line between about 0.25 and 2.25 millimetres that bends off '
        'at both ends, with a dot at the present gap.', s, period=12, values=V,
        slider={'label': 'Gap', 'init': 0.42, 'drive': PING, 'text': '{gap:2} mm'},
        status=[{'when': 'inlin', 'text': 'Gap {gap:2} mm → {nv:1} V: inside the linear range'},
                {'text': 'Gap {gap:2} mm → {nv:1} V: outside the linear range, do not trust it'}])


# ---------------------------------------------------------------- 14: two probes at 90 degrees

def xyprobes():
    cx, cy = 230, 190
    s = [C(cx, cy, 130, fill='surface', stroke='ink', sw=2), C(cx, cy, 84, fill='accent', op=.18), C(cx, cy, 84, stroke='ink', sw=1.5),
         C(cx, cy, 72, fill='sunk', stroke='ink', sw=2), C(cx, cy, 3, fill='ink'),
         R(cx - 150, cy + 112, 300, 26, fill='surface', stroke='ink', sw=2)]
    for sign, name in ((-1, 'Y probe'), (1, 'X probe')):
        ang = sign * 45
        s.append(G([R(cx - 9, cy - 150, 18, 72, fill='surface', stroke='ink', sw=2), R(cx - 6, cy - 84, 12, 8, fill='accent'),
                    LN(cx, cy - 150, cx, cy - 172, stroke='ink', sw=3)], tf=[{'rotate': [ang, cx, cy]}]))
        tx = cx + sign * 150
        s.append(T(name, tx, cy - 130, 'start' if sign > 0 else 'end', 13, 'display', 600))
    r = 44
    a0, a1 = math.radians(-135), math.radians(-45)
    arc = [[r4(cx + r * math.cos(a)), r4(cy + r * math.sin(a))] for a in lin(a0, a1, 13)]
    s += [LN(cx, cy, r4(cx - 62 * math.sin(PI / 4)), r4(cy - 62 * math.cos(PI / 4)), stroke='muted', dash=[3, 3]),
          LN(cx, cy, r4(cx + 62 * math.sin(PI / 4)), r4(cy - 62 * math.cos(PI / 4)), stroke='muted', dash=[3, 3]),
          POLY(arc, stroke='act', sw=1.5), T('90°', cx, cy - 50, 'middle', 12, 'mono', 600, fill='act'),
          T('Shaft', cx, cy + 30, 'middle', 13, 'display', 600),
          G([LAB('Oil film', cx + 55, cy + 55, 420, 290), LAB('Bearing housing', cx + 100, cy + 60, 420, 250),
             LAB('Probe tip, about 1.25 mm from the shaft', cx + 56, cy - 56, 420, 190)])]
    put('xyprobes', 680, 340, 'End view of a sleeve bearing: a shaft inside a bearing housing with an oil film between '
        'them. Two probes pass through the housing towards the shaft, 45 degrees to the left and to the right of the '
        'top, 90 degrees apart.', s)


BUILDERS = [loop, calerr, meterconn, scale, wbridge, lvdt, lowpass, deadband, pickup, ipconv, vibwave, dva, probe,
            xyprobes, faultpts]


def build():
    F.clear()
    for b in BUILDERS:
        b()
    for fid, f in F.items():
        K.check_figure(f, fid)
    return dict(F)


# states for eyeballing: (id, t, slider or None)
STATES = [('scale', 0.2, 0.3), ('lvdt', 0, 0.5), ('lvdt', 0, 0.9), ('lvdt', 0, 0.1), ('pickup', 0.3, None),
          ('ipconv', 0, 0.0), ('ipconv', 0, 1.0), ('probe', 0, 0.42), ('probe', 0, 0.02), ('probe', 0, 0.95)]


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == 'svg':
        import course_figures as CF
        figs = build()
        os.makedirs(sys.argv[2], exist_ok=True)
        todo = [(fid, 0, None) for fid, f in figs.items() if 'period' not in f] + STATES
        for st in todo:
            f = figs[st[0]]
            if 'period' in f:
                ev = CF.evaluate_state(f, st)
                name = '%s-%s.svg' % (st[0], str(st[2]).replace('.', '_'))
            else:
                ev = K.Figure(dict(f, period=1, values=[]))     # the evaluator wants a clock; a static scene has no refs
                ev._step(0.0)
                name = st[0] + '.svg'
            with open(os.path.join(sys.argv[2], name), 'w') as out:
                out.write(CF.svg_frame(f, ev))
            print(name)
    else:
        sys.exit(__doc__)
