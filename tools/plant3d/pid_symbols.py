"""The symbols of the generated P&IDs (docs/plant3d/REALISM.md §6.1.1): equipment and valves after ISO 10628-2,
instruments after ISA-5.1, each drawn by a function of the kit part kind it stands for. Sizes in sheet millimetres;
a symbol is drawn about its centre. Nothing here is copied from any drawing: the shapes are the standards' generic
ones, drawn in our own proportions."""
import math

THICK = 0.5         # an equipment outline
THIN = 0.25         # details inside a symbol, instrument connections
TAG_H = 2.5         # an instrument's letters
CODE_H = 2.0        # the code under them


class Pen:
    """Draws into a sheet (pid.Sheet) about a centre, turned by 0 or 90 degrees (inline items on vertical runs), for one
    owner (the hot spot the strokes belong to)."""

    def __init__(self, sheet, cx, cy, owner, rot=0):
        self.s, self.cx, self.cy, self.owner, self.rot = sheet, cx, cy, owner, rot

    def p(self, x, y):
        # turned counter-clockwise on the sheet (y down): +x goes to -y at 90 degrees
        if self.rot == 90:
            x, y = y, -x
        elif self.rot == 180:
            x, y = -x, -y
        elif self.rot == 270:
            x, y = -y, x
        return (self.cx + x, self.cy + y)

    def line(self, pts, w=THIN, dash=0):
        self.s.line([self.p(x, y) for x, y in pts], w, dash, self.owner)

    def poly(self, pts, w=THIN):
        self.line(list(pts) + [pts[0]], w)

    def fill(self, pts):
        self.s.fill([self.p(x, y) for x, y in pts], self.owner)

    def circle(self, x, y, r, w=THIN):
        px, py = self.p(x, y)
        self.s.circle(px, py, r, w, self.owner)

    def arc(self, x, y, r, a0, a1, w=THIN, n=10):
        """An arc from angle a0 to a1 (degrees, 0 to the right, 90 down: y grows downwards)."""
        pts = [(x + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
                y + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]
        self.line(pts, w)

    def text(self, x, y, h, t, align=1):
        px, py = self.p(x, y)
        self.s.text(px, py, h, t, 0, align, self.owner)


# ---------------------------------------------------------------- valves (inline: 8 mm along the pipe)

VALVE_L = 8.0


def _bowtie(pn, w=THIN):
    pn.poly([(-4, -2.5), (4, 2.5), (4, -2.5), (-4, 2.5)], w)


def valve_gate(pn):
    _bowtie(pn)


def valve_globe(pn):
    _bowtie(pn)
    pn.fill([(-0.8, -0.8), (0.8, -0.8), (0.8, 0.8), (-0.8, 0.8)])


def valve_ball(pn):
    _bowtie(pn)
    pn.circle(0, 0, 1.4)


def valve_butterfly(pn):
    pn.line([(-4, -2.5), (-4, 2.5)])
    pn.line([(4, -2.5), (4, 2.5)])
    pn.line([(-2.5, 2.5), (2.5, -2.5)])
    pn.circle(0, 0, 0.7)


def valve_check(pn):
    pn.poly([(-4, -2.5), (0, 0), (-4, 2.5)])
    pn.fill([(0, 0), (4, -2.5), (4, 2.5)])
    pn.line([(4, -3.5), (4, 3.5)])


def valve_control(pn):
    _bowtie(pn)
    pn.line([(0, 0), (0, -5)])
    pn.arc(0, -5, 3, 180, 360, n=8)
    pn.line([(-3, -5), (3, -5)])


def valve_safety(pn):
    """An angle safety valve on a branch: the inlet from below (the pipe), the outlet to the right, a spring above."""
    pn.poly([(-2.5, 4), (2.5, 4), (0, 0)])
    pn.poly([(0, 0), (4, -2.5), (4, 2.5)])
    pn.line([(0, 0), (0, -2), (-1.5, -2.6), (1.5, -3.4), (-1.5, -4.2), (1.5, -5), (0, -5.6), (0, -6.5)])


VALVES = {'valve_gate': valve_gate, 'valve_globe': valve_globe, 'valve_ball': valve_ball,
          'valve_butterfly': valve_butterfly, 'valve_check': valve_check, 'valve_control': valve_control,
          'valve_safety': valve_safety}
# how far a valve reaches either side of its pipe (above, below), for the space it takes
VALVE_REACH = {'valve_control': (8.5, 2.5), 'valve_safety': (7.0, 4.5), 'valve_check': (3.5, 3.5)}


def orifice(pn):
    """A flow element's orifice plate across the pipe."""
    pn.line([(-0.8, -3), (-0.8, 3)], THICK)
    pn.line([(0.8, -3), (0.8, 3)], THICK)


# ---------------------------------------------------------------- instruments (ISA-5.1 field bubbles)

# ISA first letter from the KKS measurement letters (the code's 8th and 9th characters)
FIRST = {'CP': 'P', 'CT': 'T', 'CL': 'L', 'CF': 'F', 'CS': 'S', 'CY': 'V', 'CG': 'Z', 'CB': 'B', 'CQ': 'A',
         'CW': 'W'}
# ISA succeeding letters from the kit part
AFTER = {'pressure_transmitter': 'T', 'level_transmitter': 'T', 'temperature_element': 'E', 'flow_element': 'E',
         'vibration_probe': 'E', 'speed_probe': 'E', 'flame_detector': 'E', 'pressure_gauge': 'I',
         'level_glass': 'G', 'local_panel': 'IT'}
INSTRUMENTS = set(AFTER)


def isa_letters(code, kind):
    """The ISA letters of an instrument: 'PT', 'TE', 'AIT', … (a gas test point, CQ without a transmitter's name, is
    an analysis test point 'AP')."""
    first = FIRST.get(code[7:9], 'X')
    after = AFTER.get(kind, 'X')
    return first + after


def bubble_size(code):
    from pid_font import width
    tw = width(code, CODE_H)
    return (max(10.0, tw + 5.0), 10.0)


def bubble(pn, code, letters):
    w, h = bubble_size(code)
    r = h / 2
    a = w / 2 - r
    pn.arc(-a, 0, r, 90, 270, n=10)
    pn.arc(a, 0, r, -90, 90, n=10)
    if a > 0:
        pn.line([(-a, -r), (a, -r)])
        pn.line([(-a, r), (a, r)])
    pn.text(0, -0.6, TAG_H, letters)
    pn.text(0, 3.4, CODE_H, code)


# ---------------------------------------------------------------- equipment (about the centre; sizes in SIZE)

def _rect(pn, w, h, lw=THICK):
    pn.poly([(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)], lw)


def _vessel_v(pn, w, h, lw=THICK):
    """A vertical vessel with dished heads."""
    r = w / 2
    k = min(r * 0.5, h * 0.15)
    pn.line([(-r, -h / 2 + k), (-r, h / 2 - k)], lw)
    pn.line([(r, -h / 2 + k), (r, h / 2 - k)], lw)
    pn.line(_ellipse(0, -h / 2 + k, r, k, 180, 360), lw)
    pn.line(_ellipse(0, h / 2 - k, r, k, 0, 180), lw)


def _vessel_h(pn, w, h, lw=THICK):
    """A horizontal vessel (a drum) with dished ends."""
    r = h / 2
    k = min(r * 0.5, w * 0.15)
    pn.line([(-w / 2 + k, -r), (w / 2 - k, -r)], lw)
    pn.line([(-w / 2 + k, r), (w / 2 - k, r)], lw)
    pn.line(_ellipse(-w / 2 + k, 0, k, r, 90, 270), lw)
    pn.line(_ellipse(w / 2 - k, 0, k, r, -90, 90), lw)


def _ellipse(x, y, rx, ry, a0, a1, n=10):
    return [(x + rx * math.cos(math.radians(a0 + (a1 - a0) * i / n)),
             y + ry * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]


def _zigzag(pn, x0, x1, y0, y1, n, vertical=True, lw=THIN):
    pts = []
    for i in range(n + 1):
        t = i / n
        if vertical:
            pts.append((x0 if i % 2 == 0 else x1, y0 + (y1 - y0) * t))
        else:
            pts.append((x0 + (x1 - x0) * t, y0 if i % 2 == 0 else y1))
    pn.line(pts, lw)


def _motor(pn, x, y, r=3.0):
    pn.circle(x, y, r)
    pn.text(x, y + 1.0, 2.0, 'M')


def pump(pn, w, h):
    r = h / 2
    pn.circle(0, 0, r, THICK)
    pn.poly([(-r * 0.55, -r * 0.75), (r * 0.95, 0), (-r * 0.55, r * 0.75)])


def metering_pump(pn, w, h):
    r = h / 2
    pn.circle(0, 0, r, THICK)
    pn.poly([(-r * 0.55, -r * 0.75), (r * 0.95, 0), (-r * 0.55, r * 0.75)])
    pn.line([(-r * 0.8, r * 0.8), (r * 0.8, -r * 0.8)])
    pn.fill([(r * 0.8, -r * 0.8), (r * 0.25, -r * 0.65), (r * 0.65, -r * 0.25)])


def fan(pn, w, h):
    r = h / 2
    pn.circle(0, 0, r, THICK)
    pn.line([(-r * 0.7, -r * 0.7), (r * 0.7, r * 0.7)])
    pn.line([(-r * 0.7, r * 0.7), (r * 0.7, -r * 0.7)])
    pn.circle(0, 0, r * 0.18)


def compressor(pn, w, h):
    r = h / 2
    pn.circle(0, 0, r, THICK)
    pn.line([(-r * 0.6, -r * 0.8), (r * 0.6, -r * 0.4)])
    pn.line([(-r * 0.6, r * 0.8), (r * 0.6, r * 0.4)])


def vacuum_pump(pn, w, h):
    compressor(pn, w, h)
    pn.text(0, h / 2 - 1.2, 2.0, 'V')


def tank_vertical(pn, w, h):
    _vessel_v(pn, w, h)


def chemical_tank(pn, w, h):
    _vessel_v(pn, w, h)
    pn.line([(-w / 2, -h * 0.1), (w / 2, -h * 0.1)], THIN, 1.0)


def drum(pn, w, h):
    _vessel_h(pn, w, h)
    pn.line([(-w / 2 + h * 0.3, h * 0.05), (w / 2 - h * 0.3, h * 0.05)], THIN, 1.0)     # its water level


def vessel_horizontal(pn, w, h):
    _vessel_h(pn, w, h)


def basin(pn, w, h):
    pn.line([(-w / 2, -h / 2), (-w / 2, h / 2), (w / 2, h / 2), (w / 2, -h / 2)], THICK)
    _water(pn, -w / 2 + 1, w / 2 - 1, -h * 0.15)


def _water(pn, x0, x1, y):
    n = max(2, int((x1 - x0) / 3))
    pts = [(x0 + (x1 - x0) * i / n, y + (0.5 if i % 2 else 0)) for i in range(n + 1)]
    pn.line(pts, THIN)


def clarifier(pn, w, h):
    pn.line([(-w / 2, -h / 2), (-w / 2, h * 0.15), (0, h / 2), (w / 2, h * 0.15), (w / 2, -h / 2)], THICK)
    _water(pn, -w / 2 + 1, w / 2 - 1, -h * 0.3)
    pn.line([(0, -h / 2 - 2), (0, h * 0.35)])
    pn.line([(-w * 0.35, h * 0.1), (0, h * 0.35), (w * 0.35, h * 0.1)])


def thickener(pn, w, h):
    clarifier(pn, w, h)


def dosing_skid(pn, w, h):
    _vessel_v(pn, w, h)
    pn.line([(-w / 2, -h * 0.15), (w / 2, -h * 0.15)], THIN, 1.0)


def ion_exchanger(pn, w, h):
    _vessel_v(pn, w, h)
    pn.line([(-w / 2, -h * 0.2), (w / 2, -h * 0.2)], THIN, 1.0)
    pn.line([(-w / 2, h * 0.25), (w / 2, h * 0.25)], THIN, 1.0)
    pn.text(0, h * 0.1, 2.0, 'MB')


def degasser(pn, w, h):
    _vessel_v(pn, w, h)
    y0, y1 = -h * 0.3, h * 0.05
    pn.line([(-w / 2, y0), (w / 2, y1)])
    pn.line([(-w / 2, y1), (w / 2, y0)])
    pn.line([(-w / 2, y0), (w / 2, y0)])
    pn.line([(-w / 2, y1), (w / 2, y1)])


def cartridge(pn, w, h):
    _vessel_v(pn, w, h)
    pn.line([(0, -h * 0.3), (0, h * 0.3)], THIN, 1.0)


def _filter_box(pn, w, h, lw=THICK):
    _rect(pn, w, h, lw)
    pn.line([(-w / 2, h / 2), (w / 2, -h / 2)], THIN, 1.0)


def filter_house(pn, w, h):
    _filter_box(pn, w, h)
    for i in range(3):
        y = -h / 2 + h * (i + 1) / 4
        pn.line([(-w / 2 - 2, y - 1), (-w / 2, y)])


def filter_bank(pn, w, h):
    _rect(pn, w, h)
    n = 6
    for i in range(1, n):
        x = -w / 2 + w * i / n
        pn.line([(x, -h / 2), (x, h / 2)], THIN)
    pn.line([(-w / 2, h * 0.2), (w / 2, h * 0.2)], THIN, 1.0)


def filter_cell(pn, w, h):
    _filter_box(pn, w, h, THIN)


def filter_press(pn, w, h):
    _rect(pn, w, h)
    for i in range(1, 8):
        x = -w / 2 + w * i / 8
        pn.line([(x, -h / 2 + 1), (x, h / 2 - 1)], THIN)


def ro_train(pn, w, h):
    _rect(pn, w, h)
    pn.line([(-w / 2, h / 2), (w / 2, -h / 2)], THIN)


def bar_screen(pn, w, h):
    _rect(pn, w, h)
    for i in range(1, 6):
        x = -w / 2 + w * i / 6
        pn.line([(x - 1, -h / 2), (x + 1, h / 2)], THIN)


def screen_band(pn, w, h):
    _rect(pn, w, h)
    pn.line(_ellipse(0, 0, w * 0.3, h * 0.35, 0, 360, 16), THIN)


def plate_hx(pn, w, h):
    _rect(pn, w, h)
    _zigzag(pn, -w / 2 + 1.5, w / 2 - 1.5, -h / 2 + 2, h / 2 - 2, 6, True)


def condenser(pn, w, h):
    body = h * 0.72
    _vessel_h(pn, w, body)
    pn.line([(-w / 2 + body * 0.3, body / 2), (-w * 0.2, h / 2), (w * 0.2, h / 2), (w / 2 - body * 0.3, body / 2)], THICK)
    _zigzag(pn, -w / 2 + body * 0.4, w / 2 - body * 0.4, -body * 0.15, body * 0.15, 10, False)


def hrsg_module(pn, w, h):
    _zigzag(pn, -w / 2, w / 2, -h / 2, h / 2, 10, True, THICK)


def package_boiler(pn, w, h):
    _rect(pn, w, h)
    pn.poly([(-w / 2 + 2, h * 0.15), (-w / 2 + 2, h * 0.35), (-w * 0.05, h * 0.25)])
    pn.line([(w * 0.25, -h / 2), (w * 0.25, -h / 2 - 3), (w * 0.4, -h / 2 - 3), (w * 0.4, -h / 2)])


def cooling_tower(pn, w, h):
    pn.poly([(-w / 2, h / 2), (-w * 0.35, -h / 2), (w * 0.35, -h / 2), (w / 2, h / 2)], THICK)
    _water(pn, -w * 0.4, w * 0.4, h * 0.35)
    for x in (-w * 0.17, w * 0.17):
        pn.line([(x - 3, -h / 2 - 1.5), (x + 3, -h / 2 - 1.5)])
        pn.line([(x, -h / 2), (x, -h / 2 - 1.5)])


def stack(pn, w, h):
    pn.poly([(-w / 2, h / 2), (-w * 0.3, -h / 2), (w * 0.3, -h / 2), (w / 2, h / 2)], THICK)


def duct(pn, w, h):
    pn.poly([(-w / 2, -h * 0.3), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h * 0.3)], THICK)


def silencer(pn, w, h):
    _rect(pn, w, h)
    _zigzag(pn, -w / 2 + 1, w / 2 - 1, -h / 2 + 1.5, h / 2 - 1.5, 6, True)


def steam_turbine(pn, w, h):
    pn.poly([(-w / 2, -h * 0.25), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h * 0.25)], THICK)
    pn.line([(-w / 2 + 1, 0), (w / 2 - 1, 0)], THIN, 1.5)     # the shaft, inside the casing (the pipes come to its sides)


def gas_turbine(pn, w, h):
    c = w * 0.38
    pn.poly([(-w / 2, -h / 2), (-w / 2 + c, -h * 0.22), (-w / 2 + c, h * 0.22), (-w / 2, h / 2)], THICK)
    pn.poly([(w / 2 - c, -h * 0.22), (w / 2, -h / 2), (w / 2, h / 2), (w / 2 - c, h * 0.22)], THICK)
    _rect_at(pn, 0, -h * 0.3, w - 2 * c - 2, h * 0.24)
    pn.line([(-w / 2 + c, 0), (w / 2 - c, 0)], THICK)
    pn.text(0, -h * 0.3 + 1, 2.0, 'CC')


def _rect_at(pn, x, y, w, h, lw=THIN):
    pn.poly([(x - w / 2, y - h / 2), (x + w / 2, y - h / 2), (x + w / 2, y + h / 2), (x - w / 2, y + h / 2)], lw)


def generator(pn, w, h):
    pn.circle(0, 0, h / 2, THICK)
    pn.text(0, 2.2, 6.0, 'G')


def turning_gear(pn, w, h):
    _motor(pn, 0, 0, h / 2)


def agitator(pn, w, h):
    _motor(pn, 0, -h / 2 + 3)
    pn.line([(0, -h / 2 + 6), (0, h / 2 - 1)])
    pn.line([(-w / 2 + 1, h / 2 - 2), (w / 2 - 1, h / 2)])
    pn.line([(-w / 2 + 1, h / 2), (w / 2 - 1, h / 2 - 2)])


def heater(pn, w, h):
    _rect(pn, w, h, THIN)
    _zigzag(pn, -w / 2 + 1, w / 2 - 1, -h / 2 + 1, h / 2 - 1, 6, False)


def panel_box(pn, w, h):
    _rect(pn, w, h)
    pn.line([(-w / 2, -h / 2 + 3), (w / 2, -h / 2 + 3)], THIN)


def hrsg(pn, w, h):
    """The HRSG's casing: the gas path from the inlet duct on the left to the outlet on the right (its heating surfaces
    are drawn inside it, pid.py)."""
    d = 12.0
    pn.poly([(-w / 2, -h * 0.3), (-w / 2 + d, -h / 2), (w / 2 - d, -h / 2), (w / 2, -h * 0.35),
             (w / 2, h * 0.35), (w / 2 - d, h / 2), (-w / 2 + d, h / 2), (-w / 2, h * 0.3)], THICK)
    pn.line([(-w / 2 + d, -h / 2), (-w / 2 + d, h / 2)], THIN, 1.5)
    pn.line([(w / 2 - d, -h / 2), (w / 2 - d, h / 2)], THIN, 1.5)


# kind -> (drawing function, width, height): the size of the symbol itself, without its labels
EQUIPMENT = {
    'pump_horizontal': (pump, 12, 12), 'pump_vertical': (pump, 12, 12), 'metering_pump': (metering_pump, 9, 9),
    'fan_axial': (fan, 11, 11), 'compressor_skid': (compressor, 12, 12), 'vacuum_pump_skid': (vacuum_pump, 12, 12),
    'tank_vertical': (tank_vertical, 18, 30), 'chemical_tank': (chemical_tank, 14, 22), 'drum': (drum, 44, 14),
    'vessel_horizontal': (vessel_horizontal, 22, 9), 'basin': (basin, 40, 16), 'clarifier': (clarifier, 36, 18),
    'thickener': (thickener, 30, 16), 'dosing_skid': (dosing_skid, 14, 20), 'ion_exchanger': (ion_exchanger, 16, 30),
    'degasser': (degasser, 14, 36), 'cartridge_housing': (cartridge, 10, 20), 'filter_house': (filter_house, 26, 24),
    'filter_bank': (filter_bank, 60, 22), 'filter_press': (filter_press, 30, 14), 'ro_train': (ro_train, 40, 12),
    'bar_screen': (bar_screen, 22, 14), 'screen_band': (screen_band, 18, 14), 'plate_hx': (plate_hx, 14, 24),
    'condenser': (condenser, 64, 30), 'hrsg_module': (hrsg_module, 8, 44), 'package_boiler': (package_boiler, 30, 22),
    'cooling_tower': (cooling_tower, 50, 34), 'stack': (stack, 14, 50), 'duct': (duct, 40, 22),
    'silencer': (silencer, 10, 18), 'steam_turbine': (steam_turbine, 34, 26), 'gas_turbine': (gas_turbine, 64, 26),
    'generator': (generator, 20, 20), 'turning_gear': (turning_gear, 10, 10), 'agitator': (agitator, 12, 24),
    'sample_panel': (panel_box, 22, 14), 'lab_bench': (panel_box, 26, 12), 'hrsg': (hrsg, 0, 96),
    # satellites by their code's letters (a part whose kind is a placeholder in the kit: the filter bank's cells are
    # drawn as signs in 3D, the CIP tank's heater as a junction box)
    'filter_cell': (filter_cell, 8, 10), 'heater': (heater, 10, 6),
}

# what a P&ID doesn't show (ISO 10628 practice; REALISM.md §6.1.1): electrical equipment, control desks, lifting gear
NOT_DRAWN = {'breaker', 'transformer', 'switchgear_row', 'cabinet', 'sfc', 'operator_desk', 'hoist_unit',
             'monorail_hoist', 'overhead_crane', 'service_lift', 'lift_unit', 'lift_gate', 'lift_call'}


def kind_of(code, part):
    """The symbol a part is drawn with: its kit part, but for the placeholders the kit draws in 3D (a sign standing
    for a filter cell, a junction box for an immersion heater), which the code's equipment letters name."""
    letters = code[7:9] if len(code) >= 9 else ''
    if part == 'sign' and letters == 'AT':
        return 'filter_cell'
    if part == 'junction_box' and letters == 'AH':
        return 'heater'
    return part


# what each symbol is called on the legend sheet
LEGEND = {
    'pump_horizontal': 'Centrifugal pump', 'metering_pump': 'Metering (dosing) pump', 'fan_axial': 'Fan',
    'compressor_skid': 'Compressor or blower', 'vacuum_pump_skid': 'Vacuum pump', 'tank_vertical': 'Vertical tank',
    'chemical_tank': 'Chemical storage tank', 'drum': 'Drum (horizontal vessel)', 'vessel_horizontal': 'Horizontal vessel',
    'basin': 'Open basin or pit', 'clarifier': 'Clarifier or thickener', 'dosing_skid': 'Day tank of a dosing skid',
    'ion_exchanger': 'Ion exchanger (mixed bed)', 'degasser': 'Degasser tower (packed)', 'cartridge_housing': 'Cartridge filter',
    'filter_house': 'Air intake filter house', 'filter_bank': 'Gravity filter bank', 'filter_cell': 'Filter',
    'filter_press': 'Filter press', 'ro_train': 'Membrane (reverse osmosis)', 'bar_screen': 'Bar screen',
    'screen_band': 'Band screen', 'plate_hx': 'Plate heat exchanger', 'condenser': 'Surface condenser with hotwell',
    'hrsg_module': 'Heating surface (coil)', 'package_boiler': 'Fired package boiler', 'cooling_tower': 'Cooling tower',
    'stack': 'Stack', 'duct': 'Duct (diffuser)', 'silencer': 'Silencer', 'steam_turbine': 'Steam turbine',
    'gas_turbine': 'Gas turbine (compressor, combustor, turbine)', 'generator': 'Generator', 'turning_gear': 'Electric motor (turning gear)',
    'agitator': 'Agitator', 'sample_panel': 'Panel or package unit', 'lab_bench': 'Panel or package unit',
    'pump_vertical': 'Centrifugal pump', 'thickener': 'Clarifier or thickener', 'heater': 'Electric heater', 'hrsg': 'HRSG casing (gas path)',
    'valve_gate': 'Gate valve', 'valve_globe': 'Globe valve', 'valve_ball': 'Ball valve', 'valve_butterfly': 'Butterfly valve',
    'valve_check': 'Check valve (flow to the right)', 'valve_control': 'Control valve with actuator',
    'valve_safety': 'Safety valve (spring loaded)', 'orifice': 'Orifice plate (flow element)',
}
