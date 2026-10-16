"""The first train's behaviour model (docs/plant3d/FIRST-TRAIN.md §4–§5 → docs/PLANT3D.md §7): values with lags,
permissives, interlocks, start sequences, trips with first-out and the alarms, one file per area.

Faked and reduced (R6): the direction, order of magnitude and time scale of every effect a trainee can cause, not
the plant's physics. Every number is invented, round and plausible for the class of machine (FIRST-TRAIN §2)."""

PSAT = [[10, 1.23], [20, 2.34], [25, 3.17], [30, 4.25], [35, 5.63], [40, 7.38], [45, 9.59], [50, 12.35],
        [55, 15.76], [60, 19.95], [65, 25.0], [70, 31.2], [80, 47.4], [90, 70.1], [100, 101.3]]   # °C → kPa(a)
STEAM = [[100, 1.01], [120, 1.99], [140, 3.61], [160, 6.18], [180, 10.0], [200, 15.5], [212, 20.0], [234, 30.0],
         [250, 39.7], [264, 50.0], [276, 60.0], [295, 80.0], [311, 100.0], [325, 120.0], [330, 128.0]]  # °C → bar


def inv(points):
    return [[y, x] for x, y in points]


class M:
    """One area's model file, built in order."""

    def __init__(self, area):
        self.area = area
        self.values, self.ops, self.interlocks, self.machines = [], [], [], []
        self.alarms, self.trips, self.bind = [], [], []

    def v(self, name, node, unit=None, kks=None):
        node = dict(node)
        if unit:
            node['unit'] = unit
        if kks:
            node['kks'] = kks
        self.values.append([name, node])
        return name

    # value shortcuts
    def state(self, name, init=0, kks=None, unit=None):
        return self.v(name, {'state': init}, unit, kks)

    def const(self, name, c, unit=None, kks=None):
        return self.v(name, {'const': c}, unit, kks)

    def tab(self, name, of, table, unit=None, kks=None, step=False):
        n = {'of': of, 'table': table}
        if step:
            n['step'] = True
        return self.v(name, n, unit, kks)

    def sum(self, name, refs, unit=None, kks=None):
        return self.v(name, {'sum': list(refs)}, unit, kks)

    def prod(self, name, refs, unit=None, kks=None):
        return self.v(name, {'product': list(refs)}, unit, kks)

    def min(self, name, refs, unit=None, kks=None):
        return self.v(name, {'min': list(refs)}, unit, kks)

    def max(self, name, refs, unit=None, kks=None):
        return self.v(name, {'max': list(refs)}, unit, kks)

    def diff(self, name, a, b, unit=None, kks=None):
        return self.v(name, {'diff': [a, b]}, unit, kks)

    def sel(self, name, s, cases, unit=None, kks=None):
        return self.v(name, {'select': s, 'cases': list(cases)}, unit, kks)

    def cmp(self, name, a, op, b, kks=None):
        return self.v(name, {'cmp': [a, op, b]}, None, kks)

    def AND(self, name, refs):
        return self.v(name, {'and': list(refs)})

    def OR(self, name, refs):
        return self.v(name, {'or': list(refs)})

    def NOT(self, name, ref):
        return self.v(name, {'not': ref})

    def eq(self, name, ref, k):
        """1 while ref == k (a machine's state index)."""
        a = self.cmp(f'{name}_ge', ref, '>=', k)
        b = self.cmp(f'{name}_le', ref, '<=', k)
        return self.AND(name, [a, b])

    def lag(self, name, ref, tau, tau_down=None, init=None, unit=None, kks=None):
        n = {'lag': ref, 'tau': tau}
        if tau_down is not None:
            n['tau_down'] = tau_down
        if init is not None:
            n['init'] = init
        return self.v(name, n, unit, kks)

    def ramp(self, name, ref, rate, rate_down=None, init=None, unit=None, kks=None):
        n = {'ramp': ref, 'rate': rate}
        if rate_down is not None:
            n['rate_down'] = rate_down
        if init is not None:
            n['init'] = init
        return self.v(name, n, unit, kks)

    def integ(self, name, ref, gain, lo, hi, init=None, unit=None, kks=None):
        n = {'integrate': ref, 'gain': gain, 'min': lo, 'max': hi}
        if init is not None:
            n['init'] = init
        return self.v(name, n, unit, kks)

    def latch(self, name, s, r):
        return self.v(name, {'latch': s, 'reset': r})

    def delay(self, name, ref, on, off=None):
        n = {'delay': ref, 'on': on}
        if off is not None:
            n['off'] = off
        return self.v(name, n)

    def timer(self, name, ref):
        return self.v(name, {'timer': ref}, 's')

    def wrap(self, name, ref, period, init=0, unit=None):
        return self.v(name, {'wrap': ref, 'period': period, 'init': init}, unit)

    # behaviour
    def op(self, kks, do, set_=None, needs=(), where=('local', 'screen'), **kw):
        o = {'kks': kks, 'do': do}
        o.update(kw)
        if set_:
            o['set'] = set_
        if needs:
            o['needs'] = [list(n) for n in needs]
        o['where'] = list(where)
        self.ops.append(o)

    def interlock(self, iid, when, do, kks=None, text=None):
        x = {'id': iid, 'when': when, 'do': do}
        if kks:
            x['kks'] = kks
        if text:
            x['text'] = text
        self.interlocks.append(x)

    def trip(self, tid, kks, text, when, do, isa=None, delay=None, first_out=None):
        t = {'id': tid, 'kks': kks, 'text': text, 'when': when, 'do': do}
        if isa:
            t['isa'] = isa
        if delay:
            t['delay'] = delay
        if first_out:
            t['first_out'] = first_out
        self.trips.append(t)
        self.op(kks, 'reset', trip=tid, where=('screen',))

    def alarm(self, aid, kks, text, when, priority, where=None, isa=None, clear=None, delay=None, suppress=None):
        a = {'id': aid, 'kks': kks, 'text': text, 'when': when, 'priority': priority, 'where': where or kks}
        if isa:
            a['isa'] = isa
        if clear:
            a['clear'] = clear
        if delay:
            a['delay'] = delay
        if suppress:
            a['suppress'] = suppress
        self.alarms.append(a)

    def b(self, **kw):
        self.bind.append(kw)

    def file(self):
        d = {'format': 'walkdown-plant-model', 'version': 1, 'area': self.area}
        for k in ('values', 'ops', 'interlocks', 'machines', 'alarms', 'trips', 'bind'):
            if getattr(self, k):
                d[k] = getattr(self, k)
        return d

    # common pieces
    def drive(self, name, kks, fault=True, init=0):
        """A motor drive: run command (a state), optional motor fault (a state), running = command and no fault."""
        self.state(f'{name}_cmd', init, kks)
        if fault:
            self.state(f'{name}_fault', 0, kks)
        return name

    def drive_values(self, name, fault=True):
        if fault:
            self.NOT(f'{name}_ok', f'{name}_fault')
            return self.AND(f'{name}_run', [f'{name}_cmd', f'{name}_ok'])
        return self.AND(f'{name}_run', [f'{name}_cmd'])

    def start_stop(self, kks, name, needs=(), where=('local', 'screen'), extra_start=None, ok=True):
        s = {f'{name}_cmd': 1}
        if extra_start:
            s.update(extra_start)
        n = list(needs)
        if ok:
            n.append((f'{name}_ok', 'The motor has a fault: it needs repair before a start'))
        self.op(kks, 'start', s, n, where)
        self.op(kks, 'stop', {f'{name}_cmd': 0}, (), where)

    def valve_ops(self, kks, cmd, needs=(), where=('local', 'screen'), setop=True):
        self.op(kks, 'open', {cmd: 1}, needs, where)
        self.op(kks, 'close', {cmd: 0}, (), where)
        if setop:
            self.op(kks, 'set', None, needs, where, input=cmd, range=[0, 1])

    def mov(self, name, travel, init=0, unit=None, kks=None):
        """A motor-operated valve that can stick (state {name}_stuck): its position integrates toward the command at
        1/travel per second, proportionally inside the last few percent so it settles without overshoot."""
        w = max(0.02, 0.5 / travel)
        pos = self.integ(f'{name}_pos', f'{name}_mv', 1 / travel, 0, 1, init, unit, kks)
        self.diff(f'{name}_err', f'{name}_cmd', pos)
        self.tab(f'{name}_dir', f'{name}_err', [[-w, -1], [w, 1]])
        self.NOT(f'{name}_free', f'{name}_stuck')
        self.prod(f'{name}_mv', [f'{name}_dir', f'{name}_free'])
        return pos

    def ctrl_machine(self, mid, kks, init='manual', needs=(), say_auto=None):
        self.machines.append({'id': mid, 'kks': kks, 'init': init,
                              'commands': {'auto': {'from': ['manual'], 'to': 'auto'},
                                           'manual': {'from': ['auto'], 'to': 'manual'}},
                              'states': [{'id': 'manual', 'watch': False},
                                         {'id': 'auto', 'watch': False, **({'say': say_auto} if say_auto else {})}]})
        self.op(kks, 'auto', None, needs, ('screen',), machine=mid)
        self.op(kks, 'manual', None, (), ('screen',), machine=mid)

    def lube(self, p, codes, ac, dc, stillref, low=1.8, ll=1.2):
        """Lube oil: AC and DC pumps, header pressure lag τ 3 s, three transmitters (2 out of 3 for the trip),
        alarms suppressed by design until the pressure is first established after a start (FIRST-TRAIN §4)."""
        self.drive_values(f'{p}_lac')
        self.drive_values(f'{p}_ldc')
        self.prod(f'{p}_ldc_q', [f'{p}_ldc_run', 0.85])
        self.max(f'{p}_lsup', [f'{p}_lac_run', f'{p}_ldc_q'])
        self.tab(f'{p}_lp_sp0', f'{p}_lsup', [[0, 0], [1, 2.5]])
        self.tab(f'{p}_lp_leakf', f'{p}_oil_leak', [[0, 1], [1, 0.3]])
        self.prod(f'{p}_lp_sp', [f'{p}_lp_sp0', f'{p}_lp_leakf'])
        lp = self.lag(f'{p}_lube_p', f'{p}_lp_sp', 3, unit='bar')
        for k, off in zip((1, 2, 3), (0, 0.01, -0.01)):
            self.sum(f'{p}_lp_{k}', [lp, off], 'bar', codes[k - 1])
            self.cmp(f'{p}_lp_{k}_l', f'{p}_lp_{k}', '<', low)
            self.cmp(f'{p}_lp_{k}_ll', f'{p}_lp_{k}', '<', ll)
        self.sum(f'{p}_lp_llv', [f'{p}_lp_{k}_ll' for k in (1, 2, 3)])
        self.cmp(f'{p}_lp_ll', f'{p}_lp_llv', '>=', 2)
        self.cmp(f'{p}_lube_ok', lp, '>=', low)
        self.cmp(f'{p}_lp_norm', lp, '>=', 2.0)
        self.cmp(f'{p}_pumps_off', f'{p}_lsup', '<', 0.5)
        self.AND(f'{p}_lube_off', [f'{p}_pumps_off', stillref])
        self.latch(f'{p}_lube_est', f'{p}_lp_norm', f'{p}_lube_off')
        self.NOT(f'{p}_lube_sup', f'{p}_lube_est')
        self.cmp(f'{p}_lp_low', lp, '<', low)
        self.AND(f'{p}_dc_auto_c', [f'{p}_lube_est', f'{p}_lp_low'])
        self.interlock(f'{p}_dc_auto', f'{p}_dc_auto_c', [{'set': {f'{p}_ldc_cmd': 1}}], dc,
                       'Lube oil pressure low while the oil system is in service: the DC emergency pump starts')
        self.start_stop(ac, f'{p}_lac')
        self.start_stop(dc, f'{p}_ldc')
        for k in (1, 2, 3):
            self.alarm(f'{p}_lp{k}_low', codes[k - 1], f'{"GT 1" if p == "gt1" else "Steam turbine"} lube oil '
                       f'pressure low ({k})', f'{p}_lp_{k}_l', 2, isa='PAL', suppress=f'{p}_lube_sup')
            self.alarm(f'{p}_lp{k}_ll', codes[k - 1], f'{"GT 1" if p == "gt1" else "Steam turbine"} lube oil '
                       f'pressure low-low ({k})', f'{p}_lp_{k}_ll', 1, isa='PALL', suppress=f'{p}_lube_sup')

    def sync(self, p, exc_kks, brk_kks, bias_kks, at_fsnl, speed, label):
        """Excitation, synchroscope and the sync-check relay: ±10°, ±0.1 Hz, ±5 % voltage (FIRST-TRAIN §4 #14)."""
        self.prod(f'{p}_v_sp', [f'{p}_exc_cmd', speed])
        self.lag(f'{p}_v', f'{p}_v_sp', 2, unit='pu')
        self.prod(f'{p}_f', [speed, 50], 'Hz')
        self.diff(f'{p}_slip', f'{p}_f', 'grid_frequency', 'Hz')
        self.prod(f'{p}_slip_deg', [f'{p}_slip', 360])
        self.wrap(f'{p}_phase', f'{p}_slip_deg', 360, 140, '°')
        self.tab(f'{p}_ph', f'{p}_phase', [[0, 0], [180, 180], [180, -180], [360, 0]], '°')
        self.tab(f'{p}_ph_abs', f'{p}_ph', [[-180, 180], [0, 0], [180, 180]])
        self.cmp(f'{p}_ph_ok', f'{p}_ph_abs', '<=', 10)
        self.tab(f'{p}_slip_abs', f'{p}_slip', [[-1, 1], [0, 0], [1, 1]])
        self.cmp(f'{p}_slip_ok', f'{p}_slip_abs', '<=', 0.1)
        self.tab(f'{p}_v_dev', f'{p}_v', [[0, 1], [1, 0], [2, 1]])
        self.cmp(f'{p}_v_ok', f'{p}_v_dev', '<=', 0.05)
        self.AND(f'{p}_sync_ok', [f'{p}_ph_ok', f'{p}_slip_ok', f'{p}_v_ok'])
        self.cmp(f'{p}_spd95', speed, '>=', 0.95)
        self.op(exc_kks, 'start', {f'{p}_exc_cmd': 1},
                [(f'{p}_spd95', f'{label} below 95 % speed: excitation would overflux the generator')], ('screen',))
        self.NOT(f'{p}_brk_open', f'{p}_brk_cmd')
        self.op(exc_kks, 'stop', {f'{p}_exc_cmd': 0},
                [(f'{p}_brk_open', 'The generator breaker is closed: open it first')], ('screen',))
        self.op(brk_kks, 'close_breaker', {f'{p}_brk_cmd': 1},
                [(at_fsnl, f'{label} not at full speed no load'), (f'{p}_exc_cmd', 'Excitation off'),
                 (f'{p}_ph_ok', 'Sync check: phase angle outside ±10°'),
                 (f'{p}_slip_ok', 'Sync check: frequency difference over 0.1 Hz'),
                 (f'{p}_v_ok', 'Sync check: voltage difference over 5 %')], ('screen',))
        self.op(brk_kks, 'open_breaker', {f'{p}_brk_cmd': 0}, (), ('screen',))
        self.op(bias_kks, 'set', None, (), ('screen',), input=f'{p}_bias', range=[-0.01, 0.01])


# ================================================================ bop (common: air, closed cooling water, aux steam)

def bop():
    m = M('bop')
    m.drive('ia_a', '00QFA10AN001', fault=False)
    m.drive('ia_b', '00QFA10AN002', fault=False)
    m.drive('ccw_a', '00PGC10AP001')
    m.drive('ccw_b', '00PGC10AP002')
    m.state('ccw_cooler', 0, '00PGB10AC001')
    m.drive('aux', '00QHA10', fault=False)
    m.sum('ia_n', ['ia_a_cmd', 'ia_b_cmd'])
    m.tab('ia_p_sp', 'ia_n', [[0, 0], [1, 7], [2, 7.5]])
    m.ramp('ia_p', 'ia_p_sp', 0.12, 0.02, 0, 'bar', '00QFB10CP001')
    m.cmp('ia_ok', 'ia_p', '>=', 4)
    m.cmp('ia_low', 'ia_p', '<', 5)
    m.cmp('ia_p_norm', 'ia_p', '>=', 6.5)
    m.cmp('ia_off', 'ia_n', '<', 0.5)
    m.latch('ia_est', 'ia_p_norm', 'ia_off')
    m.NOT('ia_sup', 'ia_est')
    for x in ('a', 'b'):
        m.drive_values(f'ccw_{x}')
        m.AND(f'ccw_{x}_trip_c', [f'ccw_{x}_cmd', f'ccw_{x}_fault'])
    m.sum('ccw_n', ['ccw_a_run', 'ccw_b_run'])
    m.tab('ccw_flow_sp', 'ccw_n', [[0, 0], [1, 1], [2, 1.15]])
    m.lag('ccw_flow', 'ccw_flow_sp', 5, unit='pu')
    m.cmp('ccw_flow_ok', 'ccw_flow', '>=', 0.8)
    m.AND('ccw_ok', ['ccw_flow_ok', 'ccw_cooler'])
    m.AND('aux_run', ['aux_cmd', 'ia_ok'])
    m.prod('aux_p_sp', ['aux_run', 12])
    m.ramp('aux_p', 'aux_p_sp', 0.02, 0.005, 0, 'bar', '00QHA10CP001')
    m.cmp('aux_ok', 'aux_p', '>=', 10)
    m.start_stop('00QFA10AN001', 'ia_a', ok=False)
    m.start_stop('00QFA10AN002', 'ia_b', ok=False)
    m.start_stop('00PGC10AP001', 'ccw_a')
    m.start_stop('00PGC10AP002', 'ccw_b')
    m.op('00PGB10AC001', 'open', {'ccw_cooler': 1}, (), ('local',))
    m.op('00PGB10AC001', 'close', {'ccw_cooler': 0}, (), ('local',))
    m.op('00QHA10', 'start', {'aux_cmd': 1},
         [('ia_ok', 'Instrument air below 4 bar: the burner\'s air-operated valves can\'t move')])
    m.op('00QHA10', 'stop', {'aux_cmd': 0})
    for x, other, code in (('a', 'b', '00PGC10AP001'), ('b', 'a', '00PGC10AP002')):
        m.trip(f'ccw_{x}_trip', code, f'Closed cooling water pump {x.upper()} motor trip', f'ccw_{x}_trip_c',
               [{'set': {f'ccw_{x}_cmd': 0}}], delay=0.5, first_out='ccw')
        m.interlock(f'ccw_{other}_auto', f'ccw_{x}_trip_latched', [{'set': {f'ccw_{other}_cmd': 1}}],
                    f'00PGC10AP00{"12"[x == "a"]}', f'Pump {x.upper()} tripped: the standby pump starts')
        m.alarm(f'ccw_{x}_tripped', code, f'Closed cooling water pump {x.upper()} tripped', f'ccw_{x}_trip_latched', 2)
    m.alarm('ia_p_low', '00QFB10CP001', 'Instrument air header pressure low', 'ia_low', 1, isa='PAL',
            suppress='ia_sup')
    for x, code in (('a', '00QFA10AN001'), ('b', '00QFA10AN002')):
        m.b(kks=code, anim='shaft', of=f'ia_{x}_cmd', scale=25)
        m.b(kks=code, sound='motor_small', gain={'of': f'ia_{x}_cmd', 'table': [[0, 0], [1, 0.8]]})
        m.b(kks=code, lamp='running', of=f'ia_{x}_cmd')
    for x, code in (('a', '00PGC10AP001'), ('b', '00PGC10AP002')):
        m.b(kks=code, anim='shaft', of=f'ccw_{x}_run', scale=24.7)
        m.b(kks=code, sound='motor_small', gain={'of': f'ccw_{x}_run', 'table': [[0, 0], [1, 0.7]]})
        m.b(kks=code, lamp='running', of=f'ccw_{x}_run')
    m.b(kks='00QFB10CP001', show='ia_p')
    m.b(kks='00QHA10CP001', show='aux_p')
    m.b(kks='00QHA10', sound='burner', gain={'of': 'aux_run', 'table': [[0, 0], [1, 1]]})
    m.b(kks='00QHA10', lamp='running', of='aux_run')
    return m


# ================================================================ ct (cooling tower)

def ct():
    m = M('ct')
    for i in range(1, 11):
        m.state(f'ct_fan{i}_cmd', 0, f'30PAD10AN{i:03d}')
        m.state(f'ct_fan{i}_vfault', 0, f'30PAD10AN{i:03d}')
    m.state('ct_mk_cmd', 0, '30PAR10AA001')
    m.state('ct_drain_open', 0, '30PAD10BB001')
    for i in range(1, 11):
        m.lag(f'ct_fan{i}_spd', f'ct_fan{i}_cmd', 8, unit='pu')
        m.tab(f'ct_fan{i}_vft', f'ct_fan{i}_vfault', [[0, 2.5], [1, 15]])
        m.prod(f'ct_fan{i}_vt', [f'ct_fan{i}_spd', f'ct_fan{i}_vft'])
        m.lag(f'ct_fan{i}_vib', f'ct_fan{i}_vt', 2, unit='mm/s', kks=f'30PAD10CY{i:03d}')
        m.cmp(f'ct_fan{i}_hh', f'ct_fan{i}_vib', '>', 10)
    m.sum('ct_fans_n', [f'ct_fan{i}_cmd' for i in range(1, 11)])
    m.tab('ct_inv_cap', 'ct_fans_n', [[n, round(1 / (20 + 46 * n), 6)] for n in range(11)])
    m.lag('ct_heat', 'cond_heat_mw', 30, unit='MW')
    m.prod('ct_ratio', ['ct_heat', 'ct_inv_cap'])
    m.tab('ct_approach', 'ct_ratio', [[0, 2], [0.5, 3.5], [1, 5], [2, 9], [4, 15], [10, 25]], 'K')
    m.sum('ct_cold_sp', ['ambient_wb', 'ct_approach'])
    m.lag('cw_cold_t', 'ct_cold_sp', 300, init=28, unit='°C', kks='30PAD10')
    m.prod('ct_evap', ['ct_heat', 1.5], 'm³/h')
    m.prod('ct_bd', ['ct_evap', 0.33], 'm³/h')
    m.prod('ct_leak', ['ct_drain_open', 20000], 'm³/h')
    m.sum('ct_out', ['ct_evap', 'ct_bd', 'ct_leak'], 'm³/h')
    m.cmp('ct_mk_auto', 'ct_mk_ctrl_state', '>=', 1)
    m.NOT('ct_mk_man', 'ct_mk_auto')
    m.integ('ct_basin_level', 'ct_net', 1 / (3600 * 2560), -2, 0.5, 0, 'm', '30PAD10CL001')
    m.tab('ct_mk_auto_pos', 'ct_basin_level', [[-0.3, 1], [0, 0]])
    m.sel('ct_mk_tgt', 'ct_mk_auto', ['ct_mk_cmd', 'ct_mk_auto_pos'])
    m.ramp('ct_mk_pos', 'ct_mk_tgt', 0.02, unit='pu', kks='30PAR10AA001')
    m.prod('ct_mk_flow', ['ct_mk_pos', 800], 'm³/h')
    m.diff('ct_net', 'ct_mk_flow', 'ct_out', 'm³/h')
    m.cmp('ct_l', 'ct_basin_level', '<', -0.3)
    m.cmp('ct_ll', 'ct_basin_level', '<', -0.6)
    m.NOT('cw_basin_ok', 'ct_ll')
    m.cmp('ct_level_ok', 'ct_basin_level', '>=', -0.2)
    m.cmp('ct_fans_5', 'ct_fans_n', '>=', 5)
    m.ctrl_machine('ct_mk_ctrl', '30PAR10AA001', say_auto='Makeup in automatic: holds the basin level')
    m.op('30PAR10AA001', 'set', None, [('ct_mk_man', 'The makeup valve is in automatic')], ('screen',),
         input='ct_mk_cmd', range=[0, 1])
    for i in range(1, 11):
        code = f'30PAD10AN{i:03d}'
        m.op(code, 'start', {f'ct_fan{i}_cmd': 1})
        m.op(code, 'stop', {f'ct_fan{i}_cmd': 0})
        m.alarm(f'ct_fan{i}_vib_hh', f'30PAD10CY{i:03d}', f'Cooling tower fan {i} vibration high-high',
                f'ct_fan{i}_hh', 2, code, 'VAHH')
        m.trip(f'ct_fan{i}_trip_vib', f'30PAD10CY{i:03d}', f'Cooling tower fan {i} vibration high-high',
               f'ct_fan{i}_hh', [{'set': {f'ct_fan{i}_cmd': 0}}], 'VAHH', 1, 'ct_fans')
        m.b(kks=code, anim='shaft', of=f'ct_fan{i}_spd', scale=2)
        m.b(kks=code, sound='fan_large', gain={'of': f'ct_fan{i}_spd', 'table': [[0, 0], [1, 1]]},
            pitch={'of': f'ct_fan{i}_spd', 'table': [[0, 0.5], [1, 1]]})
        m.b(kks=code, shake=f'ct_fan{i}_vib', scale=0.05)
        m.b(kks=f'30PAD10CY{i:03d}', show=f'ct_fan{i}_vib')
    m.alarm('ct_basin_low', '30PAD10CL001', 'Cooling tower basin level low', 'ct_l', 2, isa='LAL')
    m.alarm('ct_basin_ll', '30PAD10CL001', 'Cooling tower basin level low-low', 'ct_ll', 1, isa='LALL')
    m.b(kks='30PAD10CL001', show='ct_basin_level')
    m.b(kks='30PAR10AA001', anim='stem', of='ct_mk_pos')
    m.b(kks='30PAD10', sound='water_rain', gain={'of': 'cw_flow', 'table': [[0, 0], [30000, 1]]})
    return m


# ================================================================ cw (circulating water pumps)

def cw():
    m = M('cw')
    pumps = (('a', 1), ('b', 2), ('c', 3))
    for x, n in pumps:
        m.drive(f'cw_{x}', f'30PAC10AP00{n}')
        m.state(f'cw_{x}_v_cmd', 0, f'30PAC10AA10{n}')
        m.state(f'cw_{x}_v_stuck', 0, f'30PAC10AA10{n}')
    for k in (1, 2, 3, 4):
        m.state(f'cw_vent{k}', 0, f'30PAB10AA40{k}')
    for x, n in pumps:
        m.drive_values(f'cw_{x}')
        m.lag(f'cw_{x}_spd', f'cw_{x}_run', 3, unit='pu')
        m.timer(f'cw_{x}_rt', f'cw_{x}_run')
        m.mov(f'cw_{x}_v', 60, kks=f'30PAC10AA10{n}', unit='pu')
        m.cmp(f'cw_{x}_v_ge', f'cw_{x}_v_pos', '>=', 0.10)
        m.cmp(f'cw_{x}_v_le', f'cw_{x}_v_pos', '<=', 0.20)
        m.AND(f'cw_{x}_vstart', [f'cw_{x}_v_ge', f'cw_{x}_v_le'])
        m.cmp(f'cw_{x}_vfull', f'cw_{x}_v_pos', '>=', 0.99)
        m.tab(f'cw_{x}_vq', f'cw_{x}_v_pos', [[0, 0], [0.15, 1500], [0.5, 11000], [1, 15000]])
        m.prod(f'cw_{x}_pot', [f'cw_{x}_spd', f'cw_{x}_vq'], 'm³/h')
        m.tab(f'cw_{x}_dpc', f'cw_{x}_v_pos', [[0, 2.9], [1, 2.2]])
        m.prod(f'cw_{x}_dp', [f'cw_{x}_spd', f'cw_{x}_dpc'], 'bar', f'30PAC10CP50{n}')
        m.tab(f'cw_{x}_inr', f'cw_{x}_rt', [[0, 0], [0.1, 840], [4, 840], [4.5, 0]])
        m.tab(f'cw_{x}_ld', f'cw_{x}_pot', [[0, 60], [15000, 140]])
        m.max(f'cw_{x}_amax', [f'cw_{x}_inr', f'cw_{x}_ld'])
        m.prod(f'cw_{x}_amps', [f'cw_{x}_run', f'cw_{x}_amax'], 'A', f'30PAC10AP00{n}')
        m.cmp(f'cw_{x}_rt120', f'cw_{x}_rt', '>=', 120)
        m.cmp(f'cw_{x}_vno', f'cw_{x}_v_pos', '<', 0.95)
        m.AND(f'cw_{x}_late', [f'cw_{x}_rt120', f'cw_{x}_vno'])
        m.AND(f'cw_{x}_ol_c', [f'cw_{x}_cmd', f'cw_{x}_fault'])
        m.AND(f'cw_{x}_ll_c', [f'cw_{x}_run', 'ct_ll'])
        m.NOT(f'cw_{x}_nrun', f'cw_{x}_run')
        m.delay(f'cw_{x}_was', f'cw_{x}_run', 0.1, 0.1)
        m.AND(f'cw_{x}_fell', [f'cw_{x}_nrun', f'cw_{x}_was'])
        m.OR(f'cw_{x}_tripped', [f'cw_{x}_trip_ol_latched', f'cw_{x}_trip_ll_latched', f'cw_{x}_trip_valve_latched'])
        m.NOT(f'cw_{x}_trips_clear', f'cw_{x}_tripped')
    m.sum('cw_pot', [f'cw_{x}_pot' for x, _ in pumps])
    m.tab('cw_flow_sp', 'cw_pot', [[0, 0], [15000, 15000], [30000, 29000], [45000, 40000]])
    m.lag('cw_flow', 'cw_flow_sp', 10, unit='m³/h', kks='30PAB10CF001')
    m.cmp('cw_flow_on', 'cw_flow', '>=', 5000)
    m.sum('cw_vents', [f'cw_vent{k}' for k in (1, 2, 3, 4)])
    m.tab('cw_wb_cap', 'cw_vents', [[0, 0.75], [1, 1]])
    m.integ('cw_wb_fill', 'cw_wb_rate', 1, 0, 1, 0, 'pu')
    m.cmp('cw_wb_below', 'cw_wb_fill', '<', 'cw_wb_cap')
    m.prod('cw_wb_rate', ['cw_flow', 'cw_wb_below', round(1 / (15000 * 120), 12)])
    m.cmp('cw_wb_full', 'cw_wb_fill', '>=', 0.999)
    m.tab('cw_wb_eff', 'cw_wb_fill', [[0, 0], [0.75, 0.7], [1, 1]])
    m.prod('cw_flow_eff', ['cw_flow', 'cw_wb_eff'], 'm³/h')
    m.cmp('cw_vents_closed', 'cw_vents', '<', 0.5)
    m.cmp('st_run_ge', 'st_start_state', '>=', 1)
    m.cmp('st_run_le', 'st_start_state', '<=', 6)
    m.AND('st_running', ['st_run_ge', 'st_run_le'])
    m.cmp('cw_flow_lo', 'cw_flow', '<', 10000)
    m.AND('cw_flow_low', ['cw_flow_lo', 'st_running'])
    for x, n in pumps:
        L = x.upper()
        ap, aa = f'30PAC10AP00{n}', f'30PAC10AA10{n}'
        m.start_stop(ap, f'cw_{x}', [('cw_basin_ok', 'Cooling tower basin level low-low'),
                                     (f'cw_{x}_vstart', f'Discharge valve {aa} not at its start position (10–20 %)'),
                                     (f'cw_{x}_trips_clear', 'A pump trip is latched: reset it first')])
        m.valve_ops(aa, f'cw_{x}_v_cmd')
        m.interlock(f'cw_{x}_v_close', f'cw_{x}_fell', [{'set': {f'cw_{x}_v_cmd': 0}}], aa,
                    f'Pump {L} stopped: its discharge valve closes')
        m.trip(f'cw_{x}_trip_ol', ap, f'CW pump {L} motor overload', f'cw_{x}_ol_c',
               [{'set': {f'cw_{x}_cmd': 0}}], delay=0.5, first_out=f'cw_{x}')
        m.trip(f'cw_{x}_trip_ll', '30PAD10CL001', f'CW pump {L}: basin level low-low', f'cw_{x}_ll_c',
               [{'set': {f'cw_{x}_cmd': 0}}], 'LALL', 1, f'cw_{x}')
        m.trip(f'cw_{x}_trip_valve', aa, f'CW pump {L}: discharge valve not open 120 s after the start',
               f'cw_{x}_late', [{'set': {f'cw_{x}_cmd': 0}}], 'ZAL', None, f'cw_{x}')
        m.alarm(f'cw_{x}_tripped', ap, f'CW pump {L} tripped', f'cw_{x}_tripped', 1)
        m.alarm(f'cw_{x}_valve_late', aa, f'CW pump {L} discharge valve not open 120 s after start', f'cw_{x}_late',
                1, isa='ZAL')
        m.b(kks=ap, anim='shaft', of=f'cw_{x}_spd', scale=8.25)
        m.b(kks=ap, sound='motor_large', gain={'of': f'cw_{x}_spd', 'table': [[0, 0], [1, 1]]},
            pitch={'of': f'cw_{x}_spd', 'table': [[0, 0.5], [1, 1]]})
        m.b(kks=ap, lamp='running', of=f'cw_{x}_run')
        m.b(kks=ap, show=f'cw_{x}_amps')
        m.b(kks=aa, anim='disc', of=f'cw_{x}_v_pos')
        m.b(kks=aa, sound='valve_motor', gain={'of': f'cw_{x}_v_mv', 'table': [[-1, 1], [0, 0], [1, 1]]})
        m.b(kks=f'30PAC10CP50{n}', show=f'cw_{x}_dp')
    for k in (1, 2, 3, 4):
        m.op(f'30PAB10AA40{k}', 'open', {f'cw_vent{k}': 1}, (), ('local',))
        m.op(f'30PAB10AA40{k}', 'close', {f'cw_vent{k}': 0}, (), ('local',))
        m.b(kks=f'30PAB10AA40{k}', anim='disc', of=f'cw_vent{k}')
    m.alarm('cw_flow_low', '30PAB10CF001', 'CW flow low', 'cw_flow_low', 1, isa='FAL')
    m.b(kks='30PAB10CF001', show='cw_flow')
    return m


# ================================================================ gt1 (gas turbine 1 and generator 1)

GT_STATES = ['standstill', 'crank', 'purge', 'coast', 'ignite', 'accel', 'accel_sfc_off', 'fsnl', 'loaded',
             'coastdown', 'trip']
ST_STATES = ['standstill', 'roll', 'soak', 'accel', 'fsnl', 'loaded', 'hold', 'coastdown', 'trip']
TC_OFF = [-4, 2, -1, 5, 0, -3, 3, -5, 1, 4, -2, 0]
GT_TRIPS = ['gt1_trip_lube', 'gt1_trip_flame', 'gt1_trip_exh', 'gt1_trip_spread', 'gt1_trip_os', 'gt1_trip_vib',
            'gt1_trip_surge', 'gt1_trip_drum_hh', 'gt1_trip_drum_ll']


def gt1():
    m = M('gt1')
    for name, code in (('gt1_lac', '10MBV10AP001'), ('gt1_ldc', '10MBV10AP002')):
        m.drive(name, code)
    m.state('gt1_oil_leak', 0, '10MBV10AP001')
    m.state('gt1_tg_cmd', 0, '10MBK10AE001')
    m.state('gt1_sfc_on', 0, '10MBJ10')
    m.state('gt1_fuel_on', 0, '10MBP10AA201')
    m.state('gt1_ign', 0, '10MBA10')
    m.state('gt1_speed_sp', 0, '10MBA10')
    m.state('gt1_bias', 0, '10MBY10CS001')
    m.state('gt1_load_sp', 20, '10MKA10', 'MW')
    m.state('gt1_exc_cmd', 0, '10MKC10')
    m.state('gt1_brk_cmd', 0, '10BAC10')
    for f, code in (('gt1_gov_fault', '10MBA10'), ('gt1_fuel_fault', '10MBP10AA001'), ('gt1_tc_fault', '10MBR10CT007'),
                    ('gt1_flameout', '10MBM10CB001'), ('gt1_surge', '10MBA10'), ('gt1_vib_fault', '10MBD10CY002'),
                    ('gt1_gas_low', '10MBP10CP001'), ('gt1_stator_fault', '10MKA10')):
        m.state(f, 0, code)
    m.ramp('gt1_speed', 'gt1_tgt', 0.005, 0.003, 0, 'pu', '10MBA10')
    m.cmp('gt1_still', 'gt1_speed', '<', 0.01)
    m.lube('gt1', ['10MBV10CP001', '10MBV10CP002', '10MBV10CP003'], '10MBV10AP001', '10MBV10AP002', 'gt1_still')
    m.NOT('gt1_lube_trip_clear', 'gt1_trip_lube_latched')
    # turning gear and speed
    m.cmp('gt1_slow', 'gt1_speed', '<', 0.05)
    m.AND('gt1_tg_run', ['gt1_tg_cmd', 'gt1_lube_ok', 'gt1_slow'])
    m.prod('gt1_tg_spd', ['gt1_tg_run', 0.002])
    m.OR('gt1_driven', ['gt1_sfc_on', 'gt1_fuel_on'])
    m.prod('gt1_gov', ['gt1_gov_fault', 0.15])
    m.sum('gt1_sp_eff', ['gt1_speed_sp', 'gt1_bias', 'gt1_gov'])
    m.sel('gt1_free_tgt', 'gt1_driven', ['gt1_tg_spd', 'gt1_sp_eff'])
    m.prod('gt1_grid_pu', ['grid_frequency', 0.02])
    m.sel('gt1_tgt', 'gt1_brk_cmd', ['gt1_free_tgt', 'gt1_grid_pu'])
    m.prod('gt1_rpm', ['gt1_speed', 3000], 'rpm', '10MBY10CS001')
    m.cmp('gt1_os', 'gt1_speed', '>', 1.1)
    # the start sequence's conditions
    for i, s in enumerate(GT_STATES):
        if s in ('purge', 'ignite', 'fsnl', 'loaded'):
            m.eq(f'gt1_in_{s}', 'gt1_start_state', i)
    m.timer('gt1_purge_t', 'gt1_in_purge')
    m.cmp('gt1_purge_done', 'gt1_purge_t', '>=', 480)
    m.cmp('gt1_at_crank', 'gt1_speed', '>=', 0.245)
    m.cmp('gt1_at_coast', 'gt1_speed', '<=', 0.155)
    m.cmp('gt1_at_sfc_off', 'gt1_speed', '>=', 0.7)
    m.cmp('gt1_at_full', 'gt1_speed', '>=', 0.995)
    m.cmp('gt1_fired_ge', 'gt1_start_state', '>=', 5)
    m.cmp('gt1_fired_le', 'gt1_start_state', '<=', 8)
    m.AND('gt1_fired', ['gt1_fired_ge', 'gt1_fired_le'])
    m.tab('gt1_gas_p', 'gt1_gas_low', [[0, 32], [1, 20]], 'bar', '10MBP10CP001')
    m.cmp('gt1_gas_ok', 'gt1_gas_p', '>=', 25)
    m.NOT('gt1_gas_lo', 'gt1_gas_ok')
    # flame
    m.AND('gt1_fi', ['gt1_fuel_on', 'gt1_ign', 'gt1_gas_ok'])
    m.delay('gt1_lit', 'gt1_fi', 2)
    m.NOT('gt1_nofuel', 'gt1_fuel_on')
    m.OR('gt1_flame_rst', ['gt1_nofuel', 'gt1_flameout'])
    m.latch('gt1_flame', 'gt1_lit', 'gt1_flame_rst')
    m.NOT('gt1_noflame', 'gt1_flame')
    m.AND('gt1_flame_lost', ['gt1_fired', 'gt1_noflame'])
    # fuel and load
    m.prod('gt1_mw_tgt', ['gt1_brk_cmd', 'gt1_load_sp'])
    m.ramp('gt1_mw', 'gt1_mw_tgt', 0.2, 2, 0, 'MW', '10MKA10')
    m.tab('gt1_lf', 'gt1_mw', [[0, 0], [250, 1]])
    m.tab('gt1_fuel_acc', 'gt1_speed', [[0.15, 0.12], [1, 0.25]])
    m.tab('gt1_fuel_ld', 'gt1_mw', [[0, 0.25], [250, 1]])
    m.sel('gt1_fuel_dem', 'gt1_brk_cmd', ['gt1_fuel_acc', 'gt1_fuel_ld'])
    m.prod('gt1_fuel', ['gt1_fuel_on', 'gt1_fuel_dem'], 'pu')
    m.ramp('gt1_fuel_v', 'gt1_fuel', 0.2, unit='pu', kks='10MBP10AA001')
    m.ramp('gt1_stop_v', 'gt1_fuel_on', 2, unit='pu', kks='10MBP10AA201')
    # exhaust
    m.tab('gt1_exh_spd', 'gt1_speed', [[0, 0], [0.15, 250], [1, 380]])
    m.tab('gt1_exh_ld', 'gt1_lf', [[0, 0], [0.08, 40], [0.2, 100], [0.5, 220], [1, 220]])
    m.prod('gt1_exh_flt', ['gt1_fuel_fault', 80])
    m.sum('gt1_exh_fired', ['gt1_exh_spd', 'gt1_exh_ld', 'gt1_exh_flt'])
    m.sel('gt1_exh_tgt', 'gt1_flame', ['ambient_t', 'gt1_exh_fired'])
    m.lag('gt1_exh_t', 'gt1_exh_tgt', 20, 60, 35, '°C', '10MBR10')
    m.prod('gt1_tc7_err', ['gt1_tc_fault', -80])
    for k in range(1, 13):
        refs = ['gt1_exh_t', TC_OFF[k - 1]] + (['gt1_tc7_err'] if k == 7 else [])
        m.sum(f'gt1_tc{k}', refs, '°C', f'10MBR10CT{k:03d}')
        m.cmp(f'gt1_tc{k}_h', f'gt1_tc{k}', '>', 620)
        m.cmp(f'gt1_tc{k}_hh', f'gt1_tc{k}', '>', 640)
        m.diff(f'gt1_tc{k}_d', f'gt1_tc{k}', 'gt1_exh_t')
        m.tab(f'gt1_tc{k}_da', f'gt1_tc{k}_d', [[-100, 100], [0, 0], [100, 100]], 'K')
        m.cmp(f'gt1_tc{k}_dev', f'gt1_tc{k}_da', '>', 30)
    m.max('gt1_tc_max', [f'gt1_tc{k}' for k in range(1, 13)])
    m.min('gt1_tc_min', [f'gt1_tc{k}' for k in range(1, 13)])
    m.diff('gt1_spread', 'gt1_tc_max', 'gt1_tc_min', 'K', '10MBR10')
    m.cmp('gt1_spread_hh', 'gt1_spread', '>', 60)
    m.cmp('gt1_exh_hh', 'gt1_exh_t', '>', 640)
    m.tab('gt1_flow_spd', 'gt1_speed', [[0, 0], [1, 430]])
    m.tab('gt1_flow_ld', 'gt1_lf', [[0, 0], [0.5, 100], [1, 190]])
    m.sum('gt1_exh_flow', ['gt1_flow_spd', 'gt1_flow_ld'], 'kg/s')
    m.diff('gt1_exh_dt', 'gt1_exh_t', 90)
    m.max('gt1_exh_dtp', ['gt1_exh_dt', 0])
    m.prod('gt1_heat_mw', ['gt1_exh_flow', 'gt1_exh_dtp', 0.0011], 'MW')
    # compressor surge: a fast fall of compressor discharge pressure
    m.tab('gt1_cpd_b', 'gt1_speed', [[0, 1], [1, 11]])
    m.tab('gt1_cpd_l', 'gt1_lf', [[0, 0], [1, 4]])
    m.sum('gt1_cpd_s', ['gt1_cpd_b', 'gt1_cpd_l'])
    m.tab('gt1_cpd_f', 'gt1_surge', [[0, 1], [1, 0.5]])
    m.prod('gt1_cpd_t', ['gt1_cpd_s', 'gt1_cpd_f'])
    m.lag('gt1_cpd', 'gt1_cpd_t', 0.5, unit='bar', kks='10MBA10')
    m.lag('gt1_cpd_slow', 'gt1_cpd', 5)
    m.diff('gt1_cpd_drop', 'gt1_cpd_slow', 'gt1_cpd')
    m.cmp('gt1_surge_c', 'gt1_cpd_drop', '>', 1.5)
    # vibration
    m.tab('gt1_vib_b', 'gt1_speed', [[0, 0.5], [0.3, 2], [0.45, 4.5], [0.6, 3], [1, 2.5]])
    m.prod('gt1_vib_f', ['gt1_vib_fault', 30])
    for k, off in zip((1, 2, 3, 4), (0, 0.3, 0.6, -0.2)):
        m.sum(f'gt1_vib{k}', ['gt1_vib_b', off] + (['gt1_vib_f'] if k == 2 else []), 'mm/s', f'10MBD10CY00{k}')
        m.cmp(f'gt1_vib{k}_h', f'gt1_vib{k}', '>', 12)
        m.cmp(f'gt1_vib{k}_hh', f'gt1_vib{k}', '>', 25)
    m.OR('gt1_vib_hh', [f'gt1_vib{k}_hh' for k in (1, 2, 3, 4)])
    # generator stator temperatures
    m.tab('gt1_st_rise', 'gt1_mw', [[0, 10], [250, 70]])
    m.prod('gt1_st_f', ['gt1_stator_fault', 50])
    m.sum('gt1_st_tgt', ['ambient_t', 'gt1_st_rise', 'gt1_st_f'])
    m.lag('gt1_stator_t', 'gt1_st_tgt', 600, init=35, unit='°C')
    for k in range(1, 7):
        m.sum(f'gt1_st{k}', ['gt1_stator_t', (0, 1, -1, 2, -2, 0.5)[k - 1]], '°C', f'10MKA10CT00{k}')
        m.cmp(f'gt1_st{k}_h', f'gt1_st{k}', '>', 120)
    # wheel space and the turning gear alarm
    m.tab('gt1_ws_tgt', 'gt1_exh_t', [[0, 30], [600, 420]])
    m.lag('gt1_ws', 'gt1_ws_tgt', 300, 3600, 35, '°C', '10MBA10')
    m.cmp('gt1_ws_hot', 'gt1_ws', '>', 150)
    m.NOT('gt1_tg_nrun', 'gt1_tg_run')
    m.AND('gt1_tg_alarm_c', ['gt1_ws_hot', 'gt1_tg_nrun', 'gt1_still'])
    # generator 1
    m.sync('gt1', '10MKC10', '10BAC10', '10MBY10CS001', 'gt1_in_fsnl', 'gt1_speed', 'GT 1')
    m.OR('gt1_any_trip', [f'{t}_latched' for t in GT_TRIPS])
    m.NOT('gt1_trips_clear', 'gt1_any_trip')
    m.AND('gen1_prot_c', ['gt1_any_trip', 'gt1_brk_cmd'])
    m.cmp('gt1_at_base', 'gt1_mw', '>=', 249)
    # the start sequence (FIRST-TRAIN §4 #13)
    stop = {'gt1_sfc_on': 0, 'gt1_fuel_on': 0, 'gt1_ign': 0, 'gt1_speed_sp': 0, 'gt1_bias': 0}
    m.machines.append({'id': 'gt1_start', 'kks': '10MBA10', 'init': 'standstill',
        'commands': {'start': {'from': ['standstill'], 'to': 'crank'},
                     'stop': {'from': ['crank', 'purge', 'coast', 'ignite', 'accel', 'accel_sfc_off', 'fsnl'],
                              'to': 'coastdown'}},
        'states': [
            {'id': 'standstill', 'set': stop, 'watch': False},
            {'id': 'crank', 'set': {'gt1_sfc_on': 1, 'gt1_speed_sp': 0.25}, 'next': [['gt1_at_crank', 'purge']],
             'say': 'Cranking: the static frequency converter drives the generator as a motor'},
            {'id': 'purge', 'next': [['gt1_purge_done', 'coast']], 'watch': False,
             'say': 'HRSG purge: five volume changes of air through the gas path'},
            {'id': 'coast', 'set': {'gt1_sfc_on': 0, 'gt1_speed_sp': 0.15}, 'next': [['gt1_at_coast', 'ignite']],
             'say': 'Coasting down to ignition speed'},
            {'id': 'ignite', 'set': {'gt1_sfc_on': 1, 'gt1_ign': 1, 'gt1_fuel_on': 1}, 'next': [['gt1_flame', 'accel']],
             'say': 'Ignition: fuel gas and igniters on'},
            {'id': 'accel', 'set': {'gt1_ign': 0, 'gt1_speed_sp': 1}, 'next': [['gt1_at_sfc_off', 'accel_sfc_off']],
             'say': 'Flame detected: accelerating with the SFC'},
            {'id': 'accel_sfc_off', 'set': {'gt1_sfc_on': 0}, 'next': [['gt1_at_full', 'fsnl']],
             'say': 'SFC off at 70 % speed: the turbine accelerates on its own'},
            {'id': 'fsnl', 'next': [['gt1_brk_cmd', 'loaded']], 'watch': False,
             'say': 'Full speed no load: ready to synchronise'},
            {'id': 'loaded', 'next': [['gt1_brk_open', 'fsnl']], 'watch': False, 'say': 'On the grid'},
            {'id': 'coastdown', 'set': stop, 'next': [['gt1_still', 'standstill']], 'say': 'Stopping: fuel off'},
            {'id': 'trip', 'set': stop, 'next': [['gt1_still', 'standstill']], 'say': 'TRIPPED: fuel off'}]})
    m.op('10MBA10', 'start', None, [
        ('gt1_lube_ok', 'Lube oil pressure below 1.8 bar'), ('gt1_tg_run', 'Turning gear not running'),
        ('gt1_gas_ok', 'Fuel gas pressure below 25 bar'), ('ccw_ok', 'Closed cooling water not in service'),
        ('gt1_trips_clear', 'A GT trip is latched: reset it first'),
        ('hp_lvl_ok', 'HP drum level outside ±150 mm'), ('fw_avail', 'No feedwater pump running')],
        ('screen',), machine='gt1_start')
    m.op('10MBA10', 'stop', None, (), ('screen',), machine='gt1_start')
    m.op('10MKA10', 'set', None, (), ('screen',), input='gt1_load_sp', range=[10, 250])
    m.op('10MBK10AE001', 'start', {'gt1_tg_cmd': 1}, [('gt1_lube_ok', 'Lube oil pressure below 1.8 bar')])
    m.op('10MBK10AE001', 'stop', {'gt1_tg_cmd': 0})
    # trips: each forces the start sequence to "trip"; the generator protection then opens the breaker
    to_trip = [{'machine': 'gt1_start', 'to': 'trip'}]
    m.trip('gt1_trip_lube', '10MBV10CP001', 'GT 1 lube oil pressure low-low', 'gt1_lp_ll', to_trip, 'PALL', 1, 'gt1')
    m.trip('gt1_trip_flame', '10MBM10CB001', 'GT 1 flame failure', 'gt1_flame_lost', to_trip, 'BAL', 1, 'gt1')
    m.trip('gt1_trip_exh', '10MBR10CT001', 'GT 1 exhaust temperature high-high', 'gt1_exh_hh', to_trip, 'TAHH', 1,
           'gt1')
    m.trip('gt1_trip_spread', '10MBR10CT002', 'GT 1 exhaust temperature spread high-high', 'gt1_spread_hh', to_trip,
           'TDAHH', 3, 'gt1')
    m.trip('gt1_trip_os', '10MBY10CS001', 'GT 1 overspeed', 'gt1_os', to_trip, 'SAHH', None, 'gt1')
    m.trip('gt1_trip_vib', '10MBD10CY001', 'GT 1 bearing vibration high-high', 'gt1_vib_hh', to_trip, 'VAHH', 2, 'gt1')
    m.trip('gt1_trip_surge', '10MBA10', 'GT 1 compressor surge', 'gt1_surge_c', to_trip, 'PDAHH', 0.2, 'gt1')
    m.trip('gt1_trip_drum_hh', '10HAD30CL001', 'HRSG 1 HP drum level high-high', 'hp_lvl_hh', to_trip, 'LAHH', 1,
           'gt1')
    m.trip('gt1_trip_drum_ll', '10HAD30CL002', 'HRSG 1 HP drum level low-low', 'hp_lvl_ll', to_trip, 'LALL', 1, 'gt1')
    m.trip('gen1_trip_prot', '10BAC10', 'Generator 1 breaker opened by protection (GT tripped)', 'gen1_prot_c',
           [{'set': {'gt1_brk_cmd': 0}}], None, None, 'gt1')
    # alarms (FIRST-TRAIN §5)
    m.alarm('gt1_tg_hot', '10MBK10AE001', 'GT 1 turning gear not running with the rotor hot', 'gt1_tg_alarm_c', 2)
    m.alarm('gt1_gas_low', '10MBP10CP001', 'Fuel gas pressure low (start blocked)', 'gt1_gas_lo', 2, isa='PAL')
    for k in (1, 2):
        m.alarm(f'gt1_flame{k}_fail', f'10MBM10CB00{k}', f'GT 1 flame failure ({k})', 'gt1_flame_lost', 1, isa='BAL')
    for k in range(1, 13):
        m.alarm(f'gt1_tc{k}_h', f'10MBR10CT{k:03d}', f'GT 1 exhaust temperature high ({k})', f'gt1_tc{k}_h', 2,
                isa='TAH')
        m.alarm(f'gt1_tc{k}_hh', f'10MBR10CT{k:03d}', f'GT 1 exhaust temperature high-high ({k})', f'gt1_tc{k}_hh', 1,
                isa='TAHH')
        m.alarm(f'gt1_tc{k}_dev', f'10MBR10CT{k:03d}', f'GT 1 exhaust temperature spread high: thermocouple {k} '
                f'over 30 K from the mean', f'gt1_tc{k}_dev', 2, isa='TDAH')
    for k in (1, 2, 3):
        m.alarm(f'gt1_os{k}', f'10MBY10CS00{k}', f'GT 1 overspeed ({k})', 'gt1_os', 1, isa='SAHH')
    for k in (1, 2, 3, 4):
        m.alarm(f'gt1_vib{k}_h', f'10MBD10CY00{k}', f'GT 1 bearing vibration high ({k})', f'gt1_vib{k}_h', 2,
                isa='VAH')
        m.alarm(f'gt1_vib{k}_hh', f'10MBD10CY00{k}', f'GT 1 bearing vibration high-high ({k})', f'gt1_vib{k}_hh', 1,
                isa='VAHH')
    for k in range(1, 7):
        m.alarm(f'gt1_st{k}_h', f'10MKA10CT00{k}', f'Generator 1 stator winding temperature high ({k})',
                f'gt1_st{k}_h', 2, isa='TAH')
    m.alarm('gen1_brk_trip', '10BAC10', 'Generator 1 breaker tripped by protection', 'gen1_trip_prot_latched', 1)
    # what is seen and heard
    m.b(kks='10MBA10', anim='shaft', of='gt1_speed', scale=50)
    m.b(kks='10MBA10', sound='gt_whine', gain={'of': 'gt1_speed', 'table': [[0, 0], [0.1, 0.3], [1, 1]]},
        pitch={'of': 'gt1_speed', 'table': [[0, 0.1], [1, 1]]})
    m.b(kks='10MBA10', sound='combustion', gain={'of': 'gt1_fuel', 'table': [[0, 0], [1, 1]]})
    m.b(kks='10MBA10', shake='gt1_vib1', scale=0.02)
    m.b(kks='10MKA10', anim='shaft', of='gt1_speed', scale=50)
    m.b(kks='10MKA10', sound='gen_hum', gain={'of': 'gt1_v', 'table': [[0, 0], [1, 1]]})
    m.b(kks='10MBJ10', sound='sfc_whine', gain={'of': 'gt1_sfc_on', 'table': [[0, 0], [1, 1]]})
    m.b(kks='10MBK10AE001', anim='shaft', of='gt1_tg_spd', scale=50)
    m.b(kks='10MBK10AE001', sound='turning_gear', gain={'of': 'gt1_tg_run', 'table': [[0, 0], [1, 1]]})
    m.b(kks='10BAC10', anim='contacts', of='gt1_brk_cmd')
    m.b(kks='10BAC10', lamp='closed', of='gt1_brk_cmd')
    m.b(kks='10BAC10', sound='breaker', gain={'of': 'gt1_brk_cmd', 'table': [[0, 1], [1, 1]]})
    m.b(kks='10MBP10AA201', anim='disc', of='gt1_stop_v')
    m.b(kks='10MBP10AA001', anim='stem', of='gt1_fuel_v')
    m.b(kks='10MBP10CP001', show='gt1_gas_p')
    m.b(kks='10MBR10', sound='exhaust_rumble', gain={'of': 'gt1_heat_mw', 'table': [[0, 0], [350, 1]]})
    for k in (1, 2, 3):
        m.b(kks=f'10MBV10CP00{k}', show=f'gt1_lp_{k}')
        m.b(kks=f'10MBY10CS00{k}', show='gt1_rpm')
    for k in (1, 2):
        m.b(kks=f'10MBM10CB00{k}', lamp='running', of='gt1_flame')
    for k in range(1, 13):
        m.b(kks=f'10MBR10CT{k:03d}', show=f'gt1_tc{k}')
    for k in (1, 2, 3, 4):
        m.b(kks=f'10MBD10CY00{k}', show=f'gt1_vib{k}')
    for k in range(1, 7):
        m.b(kks=f'10MKA10CT00{k}', show=f'gt1_st{k}')
    for x, code in (('lac', '10MBV10AP001'), ('ldc', '10MBV10AP002')):
        m.b(kks=code, anim='shaft', of=f'gt1_{x}_run', scale=49)
        m.b(kks=code, sound='motor_small', gain={'of': f'gt1_{x}_run', 'table': [[0, 0], [1, 0.6]]})
        m.b(kks=code, lamp='running', of=f'gt1_{x}_run')
    return m


# ================================================================ trafo1 (what the transformers sound like)

def trafo1():
    m = M('trafo1')
    m.b(kks='10BAT10', sound='transformer_hum', gain={'of': 'gt1_mw', 'table': [[0, 0.4], [250, 1]]})
    m.b(kks='30BAT10', sound='transformer_hum', gain={'of': 'st_mw', 'table': [[0, 0.4], [135, 1]]})
    m.b(kks='10BBT10', sound='transformer_hum', gain={'of': 'ccw_n', 'table': [[0, 0.3], [2, 0.5]]})
    return m


# ================================================================ hrsg1

def hrsg1():
    m = M('hrsg1')
    for x, n in (('a', 1), ('b', 2)):
        m.drive(f'fw_{x}', f'10LAC10AP00{n}')
    m.state('fw_recirc_fault', 0, '10LAC10AP001')
    m.state('hp_fwv_cmd', 0, '10LAB30AA001')
    m.state('hp_fwv_fail_open', 0, '10LAB30AA001')
    m.state('hp_fwv_fail_closed', 0, '10LAB30AA001')
    for k in (1, 2, 3, 4):
        m.state(f'hp_drn{k}', 0, f'10HAN30AA40{k}')
    m.state('hp_vent_cmd', 0, '10HAN30AA001')
    m.state('hp_spray_stuck', 0, '10LAE30AA001')
    for x in ('a', 'b'):
        m.drive_values(f'fw_{x}')
        m.lag(f'fw_{x}_spd', f'fw_{x}_run', 2, unit='pu')
    m.sum('fw_n', ['fw_a_run', 'fw_b_run'])
    m.cmp('fw_avail', 'fw_n', '>=', 0.5)
    m.tab('fw_cap', 'fw_n', [[0, 0], [1, 90], [2, 100]], 'kg/s')
    # HP drum: water temperature rises at a rate the exhaust heat allows, up to the saturation temperature of the
    # pressure the bypass (or the sliding pressure of a loaded turbine) holds; pressure from the saturation table
    m.cmp('hp_byp_hp_auto', 'hp_byp_ctrl_state', '>=', 1)
    m.cmp('hp_byp_lp_auto', 'lp_byp_ctrl_state', '>=', 1)
    m.AND('hp_byp_on', ['hp_byp_hp_auto', 'hp_byp_lp_auto'])
    m.eq('hp_st_loaded', 'st_start_state', ST_STATES.index('loaded'))
    m.OR('hp_slide', ['hp_byp_on', 'hp_st_loaded'])
    m.tab('hp_p_auto', 'gt1_lf', [[0, 50], [1, 120]], 'bar')
    m.sel('hp_p_tgt', 'hp_slide', [128, 'hp_p_auto'], 'bar')
    m.tab('hp_t_tgt', 'hp_p_tgt', inv(STEAM), '°C')
    m.integ('hp_tw', 'hp_rate', 1, 20, 330, 35, '°C', '10HAD30BB001')
    m.diff('hp_head', 'hp_t_tgt', 'hp_tw', 'K')
    m.tab('hp_hf', 'hp_head', [[-20, -1], [0, 0], [3, 1]])
    m.tab('hp_rmax', 'gt1_heat_mw', [[0, 0], [100, 0.033], [160, 0.058], [250, 0.085], [350, 0.11]])
    m.tab('hp_rboost', 'hp_tw', [[99, 3], [100, 1]])
    m.prod('hp_rate', ['hp_rmax', 'hp_hf', 'hp_rboost'], 'K/s')
    m.max('hp_tsat', ['hp_tw', 100], '°C')
    m.tab('hp_p', 'hp_tsat', STEAM, 'bar', '10HAD30CP001')
    m.lag('hp_tsat_slow', 'hp_tsat', 60, init=100)
    m.diff('hp_warm_rate', 'hp_tsat', 'hp_tsat_slow', 'K/min')
    m.cmp('hp_warm_fast', 'hp_warm_rate', '>', 4)
    m.cmp('hp_p_10', 'hp_p', '>=', 10)
    # steam made, feed, level with swell and shrink
    m.tab('hp_gen_tgt', 'gt1_heat_mw', [[0, 0], [100, 4], [160, 12], [350, 70]])
    m.lag('hp_gen', 'hp_gen_tgt', 300, unit='kg/s')
    m.lag('hp_hfast', 'gt1_heat_mw', 60)
    m.lag('hp_hslow', 'gt1_heat_mw', 600)
    m.diff('hp_hd', 'hp_hfast', 'hp_hslow')
    m.prod('hp_swell', ['hp_hd', 1.0], 'mm')
    m.integ('hp_mass', 'hp_mnet', 0.053, -800, 800, -100, 'mm')
    m.sum('hp_lvl', ['hp_mass', 'hp_swell'], 'mm', '10HAD30CL501')
    m.prod('hp_lvl_ff', ['hp_gen', round(1 / 90, 9)])
    m.tab('hp_lvl_fb', 'hp_lvl', [[-200, 0.5], [0, 0], [200, -0.5]])
    m.sum('hp_lvl_sum', ['hp_lvl_ff', 'hp_lvl_fb'])
    m.tab('hp_fwv_auto', 'hp_lvl_sum', [[0, 0], [1, 1]])
    m.cmp('hp_lvl_auto', 'hp_lvl_ctrl_state', '>=', 1)
    m.sel('hp_fwv_tgt', 'hp_lvl_auto', ['hp_fwv_cmd', 'hp_fwv_auto'])
    m.NOT('hp_fwv_nc', 'hp_fwv_fail_closed')
    m.min('hp_fwv_t2', ['hp_fwv_tgt', 'hp_fwv_nc'])
    m.max('hp_fwv_t3', ['hp_fwv_t2', 'hp_fwv_fail_open'])
    m.ramp('hp_fwv_pos', 'hp_fwv_t3', 0.05, unit='pu', kks='10LAB30AA001')
    m.prod('hp_feed', ['hp_fwv_pos', 'fw_cap'], 'kg/s')
    m.diff('hp_mnet', 'hp_feed', 'hp_gen')
    for k, off in zip((1, 2, 3), (0, 2, -2)):
        m.sum(f'hp_l{k}', ['hp_lvl', off], 'mm', f'10HAD30CL00{k}')
        for tag, op, lim in (('h', '>', 150), ('hh', '>', 250), ('l', '<', -150), ('ll', '<', -300)):
            m.cmp(f'hp_l{k}_{tag}', f'hp_l{k}', op, lim)
    m.sum('hp_hh_v', [f'hp_l{k}_hh' for k in (1, 2, 3)])
    m.cmp('hp_lvl_hh', 'hp_hh_v', '>=', 2)
    m.sum('hp_ll_v', [f'hp_l{k}_ll' for k in (1, 2, 3)])
    m.cmp('hp_lvl_ll', 'hp_ll_v', '>=', 2)
    m.cmp('hp_lvl_ge', 'hp_lvl', '>=', -150)
    m.cmp('hp_lvl_le', 'hp_lvl', '<=', 150)
    m.AND('hp_lvl_ok', ['hp_lvl_ge', 'hp_lvl_le'])
    # feedwater pumps: minimum flow through the automatic recirculation
    m.tab('fw_share', 'fw_n', [[1, round(1 / 90, 9)], [2, round(1 / 180, 9)]])
    m.prod('fw_q', ['hp_feed', 'fw_share'])
    m.NOT('fw_rc_ok', 'fw_recirc_fault')
    m.prod('fw_rc', ['fw_rc_ok', 0.3])
    m.max('fw_qq', ['fw_q', 'fw_rc'])
    for x, n in (('a', 1), ('b', 2)):
        m.prod(f'fw_{x}_q', [f'fw_{x}_run', 'fw_qq'], 'pu', f'10LAC10CF00{n}')
        m.cmp(f'fw_{x}_qlo', f'fw_{x}_q', '<', 0.15)
        m.AND(f'fw_{x}_low', [f'fw_{x}_run', f'fw_{x}_qlo'])
    # LP drum (feedwater storage with the deaerator): fed by the condensate pumps (st), drawn by the feed pumps
    m.prod('lp_gen', ['hp_gen', 0.15], 'kg/s')
    m.sum('lp_out', ['hp_feed', 'lp_gen'], 'kg/s')
    m.lag('lp_in', 'cep_hrsg', 1, unit='kg/s')
    m.diff('lp_net', 'lp_in', 'lp_out')
    m.integ('lp_lvl', 'lp_net', 0.02, -800, 400, -50, 'mm', '10HAD10CL001')
    m.tab('lp_dem_fb', 'lp_lvl', [[-300, 60], [0, 0], [300, -60]])
    m.sum('lp_dem', ['lp_out', 'lp_dem_fb'])
    m.max('lp_dem_p', ['lp_dem', 0], 'kg/s')
    m.cmp('lp_l', 'lp_lvl', '<', -200)
    m.cmp('lp_lvl_ok', 'lp_lvl', '>=', -300)
    # HP steam: superheater drains, start-up vent, spray limited for matching to the HP casing
    m.sum('hp_drn_n', [f'hp_drn{k}' for k in (1, 2, 3, 4)])
    m.prod('hp_drn_frac', ['hp_drn_n', 0.25])
    m.cmp('hp_drains_open', 'hp_drn_n', '>=', 4)
    m.ramp('hp_vent_pos', 'hp_vent_cmd', 0.05, unit='pu', kks='10HAN30AA001')
    m.cmp('hp_vent_ok', 'hp_vent_pos', '>=', 0.95)
    m.AND('hp_drains_vent_open', ['hp_drains_open', 'hp_vent_ok'])
    m.cmp('hp_drn_shut', 'hp_drn_n', '<', 0.5)
    m.cmp('hp_vent_shut', 'hp_vent_pos', '<', 0.01)
    m.AND('hp_drains_closed', ['hp_drn_shut', 'hp_vent_shut'])
    m.tab('hp_shw_k', 'hp_gen', [[0, 0], [2, 1]])
    m.prod('hp_shw_rate', ['hp_drn_frac', 'hp_shw_k', -0.01])
    m.integ('hp_shw', 'hp_shw_rate', 1, 0, 1, 1, 'pu')
    m.prod('hp_drain_loss', ['hp_drn_frac', 3], 'kg/s')
    m.prod('hp_vent_loss', ['hp_vent_pos', 5], 'kg/s')
    m.sum('hp_losses', ['hp_drain_loss', 'hp_vent_loss'])
    m.diff('hp_net0', 'hp_gen', 'hp_losses')
    m.max('hp_steam_net', ['hp_net0', 0], 'kg/s')
    m.diff('hp_sh_raw', 'gt1_exh_t', 20)
    m.max('hp_sh_t0', ['hp_sh_raw', 'hp_tw'])
    m.lag('hp_casing_seen', 'st_casing_t', 1)
    m.sum('hp_lim_c', ['hp_casing_seen', 300])
    m.min('hp_sp_lim', [560, 'hp_lim_c'])
    m.min('hp_sh_lim', ['hp_sh_t0', 'hp_sp_lim'])
    m.cmp('hp_spray_auto', 'hp_spray_ctrl_state', '>=', 1)
    m.sel('hp_sh_t1', 'hp_spray_auto', ['hp_sh_t0', 'hp_sh_lim'])
    m.prod('hp_shw_red', ['hp_shw', 250])
    m.diff('hp_sh_t2', 'hp_sh_t1', 'hp_shw_red')
    m.max('hp_sh_t3', ['hp_sh_t2', 'hp_tw'])
    m.prod('hp_spray_err', ['hp_spray_stuck', 300])
    m.diff('hp_sh_t4', 'hp_sh_t3', 'hp_spray_err')
    m.lag('hp_steam_t', 'hp_sh_t4', 120, init=35, unit='°C', kks='10LBA30CT001')
    m.cmp('hp_steam_th', 'hp_steam_t', '>', 575)
    # operations
    for x, n in (('a', 1), ('b', 2)):
        m.start_stop(f'10LAC10AP00{n}', f'fw_{x}', [('lp_lvl_ok', 'LP drum (pump suction) level below −300 mm')])
    m.ctrl_machine('hp_lvl_ctrl', '10LAB30AA001', 'auto', say_auto='HP drum level control in automatic')
    m.NOT('hp_lvl_man', 'hp_lvl_auto')
    m.op('10LAB30AA001', 'set', None, [('hp_lvl_man', 'The feedwater control valve is in automatic')], ('screen',),
         input='hp_fwv_cmd', range=[0, 1])
    for k in (1, 2, 3, 4):
        m.op(f'10HAN30AA40{k}', 'open', {f'hp_drn{k}': 1})
        m.op(f'10HAN30AA40{k}', 'close', {f'hp_drn{k}': 0})
    m.valve_ops('10HAN30AA001', 'hp_vent_cmd')
    m.ctrl_machine('hp_spray_ctrl', '10LAE30AA001', 'auto',
                   say_auto='HP steam temperature control in automatic, matched to the HP casing')
    # alarms
    for k in (1, 2, 3):
        c = f'10HAD30CL00{k}'
        m.alarm(f'hp_l{k}_h', c, f'HP drum level high ({k})', f'hp_l{k}_h', 2, isa='LAH')
        m.alarm(f'hp_l{k}_hh', c, f'HP drum level high-high ({k})', f'hp_l{k}_hh', 1, isa='LAHH')
        m.alarm(f'hp_l{k}_l', c, f'HP drum level low ({k})', f'hp_l{k}_l', 2, isa='LAL')
        m.alarm(f'hp_l{k}_ll', c, f'HP drum level low-low ({k})', f'hp_l{k}_ll', 1, isa='LALL')
    m.alarm('lp_lvl_low', '10HAD10CL001', 'LP drum level low', 'lp_l', 2, isa='LAL')
    m.alarm('hp_warm_fast', '10HAD30CP001', 'HP drum warming too fast', 'hp_warm_fast', 3)
    for x, n in (('a', 1), ('b', 2)):
        m.alarm(f'fw_{x}_flow_low', f'10LAC10CF00{n}', f'Feedwater pump {x.upper()} flow below minimum',
                f'fw_{x}_low', 2, f'10LAC10AP00{n}', 'FAL', delay=10)
    m.alarm('hp_steam_t_high', '10LBA30CT001', 'HP steam temperature high', 'hp_steam_th', 2, isa='TAH')
    # what is seen and heard
    for x, n in (('a', 1), ('b', 2)):
        c = f'10LAC10AP00{n}'
        m.b(kks=c, anim='shaft', of=f'fw_{x}_spd', scale=49)
        m.b(kks=c, sound='motor_large', gain={'of': f'fw_{x}_spd', 'table': [[0, 0], [1, 0.9]]},
            pitch={'of': f'fw_{x}_spd', 'table': [[0, 0.5], [1, 1.6]]})
        m.b(kks=c, lamp='running', of=f'fw_{x}_run')
        m.b(kks=f'10LAC10CF00{n}', show=f'fw_{x}_q')
    m.b(kks='10HAD30CL501', show='hp_lvl')
    m.b(kks='10HAD30CL501', anim='level', of='hp_lvl')
    for k in (1, 2, 3):
        m.b(kks=f'10HAD30CL00{k}', show=f'hp_l{k}')
    m.b(kks='10HAD30CP001', show='hp_p')
    m.b(kks='10HAD10CL001', show='lp_lvl')
    m.b(kks='10LAB30AA001', anim='stem', of='hp_fwv_pos')
    for k in (1, 2, 3, 4):
        m.b(kks=f'10HAN30AA40{k}', anim='stem', of=f'hp_drn{k}')
    m.b(kks='10HAN30AA001', anim='stem', of='hp_vent_pos')
    m.b(kks='10HAN30BS001', sound='steam_vent', gain={'of': 'hp_vent_loss', 'table': [[0, 0], [5, 1]]})
    m.b(kks='10LBA30CT001', show='hp_steam_t')
    m.b(kks='10HNA10', sound='exhaust_rumble', gain={'of': 'gt1_heat_mw', 'table': [[0, 0], [350, 0.7]]})
    return m


# ================================================================ st (steam turbine, condenser, condensate)

ST_TRIPS = ['st_trip_lube', 'st_trip_cond_p', 'st_trip_os', 'st_trip_axial', 'st_trip_vib', 'st_trip_steam_t']
VIB_F = [0.8, 0.9, 1.0, 1.1, 0.95, 0.85, 0.7, 0.75]


def st():
    m = M('st')
    for name, code in (('st_lac', '30MAV10AP001'), ('st_ldc', '30MAV10AP002')):
        m.drive(name, code)
    m.state('st_oil_leak', 0, '30MAV10AP001')
    m.drive('st_jack', '30MAV20AP001', fault=False)
    m.state('st_tg_cmd', 0, '30MAK10AE001')
    m.state('st_gland_cmd', 0, '30MAW10AA001')
    m.drive('vac_a', '30MAJ10AP001', fault=False)
    m.drive('vac_b', '30MAJ10AP002', fault=False)
    m.drive('cep_a', '30LCB10AP001')
    m.drive('cep_b', '30LCB10AP002')
    m.state('cep_mf_cmd', 0, '30LCA10AA001')
    m.state('hw_mk_fail', 0, '30MAG10BB001')
    m.state('hw_leak', 0, '30MAG10BB001')
    m.state('st_speed_sp', 0, '30MAA10')
    m.state('st_adm', 0, '30MAA10AA201')
    m.state('st_bias', 0, '30MAY10CS001')
    m.state('st_exc_cmd', 0, '30MKC10')
    m.state('st_brk_cmd', 0, '30BAC10')
    for f, code in (('st_gov_fault', '30MAA10'), ('st_thrust_fault', '30MAD10CG001'), ('st_vib_fault', '30MAD10CY003')):
        m.state(f, 0, code)
    # turbine speed: integrates toward its target (held in the state "hold"), up 13.5 rpm/s, down 9 rpm/s
    m.integ('st_speed', 'st_acc', 1, 0, 1.3, 0, 'pu', '30MAA10')
    # condenser pressure first: it is a lag of a target computed further down (stateful nodes read the previous step)
    m.lag('cond_p', 'cond_p_tgt', 30, 150, 101.3, 'kPa(a)', '30MAG10AC001')
    for k, off in zip((1, 2, 3), (0, 0.1, -0.1)):
        m.sum(f'cond_p{k}', ['cond_p', off], 'kPa(a)', f'30MAG10CP00{k}')
        m.cmp(f'cond_p{k}_h', f'cond_p{k}', '>', 15)
        m.cmp(f'cond_p{k}_hc', f'cond_p{k}', '<', 13)
        m.cmp(f'cond_p{k}_hh', f'cond_p{k}', '>', 25)
        m.cmp(f'cond_p{k}_hhc', f'cond_p{k}', '<', 23)
    m.sum('cond_hh_v', [f'cond_p{k}_hh' for k in (1, 2, 3)])
    m.cmp('cond_hh', 'cond_hh_v', '>=', 2)
    m.NOT('cond_p_ok', 'cond_hh')
    m.cmp('st_vac_ok', 'cond_p', '<', 12)
    m.NOT('st_cond_trip_clear', 'st_trip_cond_p_latched')
    # lube oil, jacking oil, turning gear, eccentricity, gland steam (FIRST-TRAIN §4 #7, #10)
    m.cmp('st_still', 'st_speed', '<', 0.01)
    m.lube('st', ['30MAV10CP001', '30MAV10CP002', '30MAV10CP003'], '30MAV10AP001', '30MAV10AP002', 'st_still')
    m.NOT('st_lube_trip_clear', 'st_trip_lube_latched')
    m.AND('st_jack_run', ['st_jack_cmd', 'st_lube_ok'])
    m.prod('st_jack_sp', ['st_jack_run', 140])
    m.lag('st_jack_p', 'st_jack_sp', 3, unit='bar', kks='30MAV20AP001')
    m.cmp('st_jack_ok', 'st_jack_p', '>=', 80)
    m.cmp('st_slow', 'st_speed', '<', 0.05)
    m.AND('st_tg_run', ['st_tg_cmd', 'st_lube_ok', 'st_jack_ok', 'st_slow'])
    m.prod('st_tg_spd', ['st_tg_run', 0.0013])
    m.NOT('st_tg_nrun', 'st_tg_run')
    m.integ('st_tg_time', 'st_tg_run', 1, 0, 7200, 0, 's')
    m.tab('st_ecc0', 'st_tg_time', [[0, 120], [600, 60], [1200, 32], [1800, 28]], 'µm')
    m.ramp('st_gland_pos', 'st_gland_cmd', 0.1, unit='pu', kks='30MAW10AA001')
    m.cmp('st_gland_open', 'st_gland_pos', '>=', 0.5)
    m.AND('st_gland_on', ['st_gland_open', 'aux_ok'])
    m.AND('st_bow_c', ['st_gland_on', 'st_tg_nrun', 'st_still'])
    m.integ('st_bow', 'st_bow_c', 0.5, 0, 500, 0, 'µm')
    m.sum('st_ecc', ['st_ecc0', 'st_bow'], 'µm', '30MAA10')
    m.cmp('st_ecc_ok', 'st_ecc', '<=', 40)
    # vacuum (FIRST-TRAIN §4 #11)
    m.sum('vac_n', ['vac_a_cmd', 'vac_b_cmd'])
    m.tab('vac_floor_g', 'vac_n', [[0, 101.3], [1, 7.5], [2, 7]])
    m.tab('vac_floor_ng', 'vac_n', [[0, 101.3], [1, 45], [2, 30]])
    m.sel('cond_floor', 'st_gland_on', ['vac_floor_ng', 'vac_floor_g'], 'kPa(a)')
    m.cmp('vac_none', 'vac_n', '<', 0.5)
    m.AND('cond_off', ['vac_none', 'st_still'])
    m.latch('cond_est', 'cond_p1_hc', 'cond_off')
    m.NOT('cond_sup', 'cond_est')
    # condensate extraction pumps (FIRST-TRAIN §4 #6)
    for x in ('a', 'b'):
        m.drive_values(f'cep_{x}')
        m.lag(f'cep_{x}_spd', f'cep_{x}_run', 2, unit='pu')
    m.sum('cep_n', ['cep_a_run', 'cep_b_run'])
    m.cmp('cep_any', 'cep_n', '>=', 0.5)
    m.tab('cep_cap', 'cep_n', [[0, 0], [1, 110], [2, 180]], 'kg/s')
    m.min('cep_hrsg', ['lp_dem_p', 'cep_cap'], 'kg/s')
    m.ramp('cep_mf_pos', 'cep_mf_cmd', 0.05, unit='pu', kks='30LCA10AA001')
    m.cmp('cep_mf_open', 'cep_mf_pos', '>=', 0.9)
    m.cmp('cep_lowout', 'cep_hrsg', '<', 5)
    for x in ('a', 'b'):
        m.AND(f'cep_{x}_onmin', [f'cep_{x}_run', 'cep_lowout'])
    # steam to the turbine and the bypass
    m.AND('byp_permit', ['cond_p_ok', 'cw_flow_on', 'cep_any'])
    m.NOT('byp_block', 'byp_permit')
    m.OR('byp_any_auto', ['hp_byp_hp_auto', 'hp_byp_lp_auto'])
    m.AND('byp_block_c', ['byp_block', 'byp_any_auto'])
    m.AND('byp_auto', ['hp_byp_on', 'byp_permit'])
    for i, s in enumerate(ST_STATES):
        if s in ('soak', 'fsnl', 'loaded', 'hold'):
            m.eq(f'st_in_{s}', 'st_start_state', i)
    m.NOT('st_nhold', 'st_in_hold')
    m.tab('st_roll_flow', 'st_speed', [[0, 0], [1, 6]])
    m.prod('st_flow_a', ['st_adm', 'st_roll_flow'])
    m.prod('st_flow_l', ['st_in_loaded', 'hp_steam_net'])
    m.max('st_flow_t', ['st_flow_a', 'st_flow_l'])
    m.min('st_flow_t2', ['st_flow_t', 'hp_steam_net'])
    m.ramp('st_flow', 'st_flow_t2', 0.5, 20, 0, 'kg/s')
    m.diff('byp_rest', 'hp_steam_net', 'st_flow')
    m.max('byp_rest_p', ['byp_rest', 0])
    m.prod('byp_flow', ['byp_auto', 'byp_rest_p'], 'kg/s')
    m.tab('hp_byp_pos', 'byp_flow', [[0, 0], [70, 1]], 'pu', '30MAN10AA001')
    m.tab('lp_byp_pos', 'byp_flow', [[0, 0], [60, 1]], 'pu', '30MAN20AA001')
    m.cmp('hp_byp_wide', 'hp_byp_pos', '>', 0.9)
    m.cmp('hp_byp_shut', 'hp_byp_pos', '<', 0.05)
    m.sum('cond_steam0', ['byp_flow', 'st_flow'])
    m.prod('cond_steam', ['cond_steam0', 1.15], 'kg/s')
    m.prod('cond_heat_mw', ['cond_steam', 2.7], 'MW')
    # condenser pressure target and the CW return temperature (FIRST-TRAIN §2, §4 #20)
    m.tab('cw_inv', 'cw_flow_eff', [[q, round(859.2 / q, 6)] for q in
                                     (500, 1000, 2000, 3000, 5000, 7500, 10000, 15000, 20000, 25000, 30000, 40000)])
    m.prod('cond_dt', ['cond_heat_mw', 'cw_inv'], 'K')
    m.min('cond_dt_c', ['cond_dt', 60])
    m.tab('cond_ttd', 'cond_heat_mw', [[0, 0], [220, 4]], 'K')
    m.sum('cond_t', ['cw_cold_t', 'cond_dt_c', 'cond_ttd'], '°C')
    m.tab('cond_psat', 'cond_t', PSAT, 'kPa(a)')
    m.max('cond_p_tgt', ['cond_floor', 'cond_psat'], 'kPa(a)')
    m.sum('cw_ret_t', ['cw_cold_t', 'cond_dt_c'], '°C', '30PAB20BR010')
    m.cmp('cw_ret_h', 'cw_ret_t', '>', 48)
    # hotwell (FIRST-TRAIN §4 #6)
    m.integ('hw_lvl', 'hw_net', 0.033, -800, 600, 0, 'mm', '30MAG10CL001')
    m.NOT('hw_mk_ok', 'hw_mk_fail')
    m.tab('hw_mk_p', 'hw_lvl', [[-100, 25], [0, 0]])
    m.prod('hw_mk', ['hw_mk_ok', 'hw_mk_p'], 'kg/s')
    m.prod('hw_leak_q', ['hw_leak', 40])
    m.tab('hw_spill', 'hw_lvl', [[50, 0], [150, 20]], 'kg/s')
    m.sum('hw_in', ['cond_steam', 'hw_mk'])
    m.sum('hw_out', ['cep_hrsg', 'hw_leak_q', 'hw_spill'])
    m.diff('hw_net', 'hw_in', 'hw_out')
    m.cmp('hw_h', 'hw_lvl', '>', 200)
    m.cmp('hw_l', 'hw_lvl', '<', -200)
    m.cmp('hw_ll', 'hw_lvl', '<', -400)
    m.cmp('hw_ok', 'hw_lvl', '>', -300)
    m.AND('cep_ll_c', ['hw_ll', 'cep_any'])
    m.prod('st_gov', ['st_gov_fault', 0.15])
    m.sum('st_sp_eff', ['st_speed_sp', 'st_bias', 'st_gov'])
    m.sel('st_free', 'st_adm', ['st_tg_spd', 'st_sp_eff'])
    m.sel('st_tgt', 'st_brk_cmd', ['st_free', 'gt1_grid_pu'])
    m.diff('st_err', 'st_tgt', 'st_speed')
    m.tab('st_acc0', 'st_err', [[-0.01, -0.003], [0, 0], [0.01, 0.0045]])
    m.prod('st_acc', ['st_acc0', 'st_nhold'])
    m.prod('st_rpm', ['st_speed', 3000], 'rpm', '30MAY10CS001')
    m.cmp('st_os', 'st_speed', '>', 1.1)
    m.cmp('st_at_800', 'st_speed', '>=', 0.26)
    m.cmp('st_at_3000', 'st_speed', '>=', 0.995)
    m.timer('st_soak_t', 'st_in_soak')
    m.cmp('st_soak_done', 'st_soak_t', '>=', 300)
    m.cmp('st_band_lo', 'st_rpm', '>=', 1600)
    m.cmp('st_band_hi', 'st_rpm', '<=', 1900)
    m.AND('st_inband', ['st_band_lo', 'st_band_hi'])
    m.timer('st_band_t', 'st_inband')
    m.tab('st_vib_base', 'st_rpm', [[0, 10], [1400, 30], [1600, 70], [1750, 100], [1900, 70], [2100, 30],
                                    [3000, 25]], 'µm')
    m.tab('st_vib_hold', 'st_band_t', [[0, 0], [45, 0], [200, 200]], 'µm')
    m.prod('st_vib_f', ['st_vib_fault', 300])
    m.sum('st_vib', ['st_vib_base', 'st_vib_hold', 'st_vib_f'], 'µm')
    for k in range(1, 9):
        m.prod(f'st_vib{k}', ['st_vib', VIB_F[k - 1]], 'µm', f'30MAD10CY00{k}')
        m.cmp(f'st_vib{k}_h', f'st_vib{k}', '>', 125)
        m.cmp(f'st_vib{k}_hh', f'st_vib{k}', '>', 250)
    m.OR('st_vib_hh', [f'st_vib{k}_hh' for k in range(1, 9)])
    m.integ('st_ax_w', 'st_thrust_fault', 0.02, 0, 2, 0, 'mm')
    m.sum('st_axial', ['st_ax_w', 0.2], 'mm', '30MAD10CG001')
    m.cmp('st_axial_hh', 'st_axial', '>', 1.0)
    # steam at the turbine: superheat, matching to the HP casing (FIRST-TRAIN §4 #18)
    m.lag('st_inlet_t', 'hp_steam_t', 60, init=35, unit='°C', kks='30MAA10CT001')
    m.diff('st_superheat', 'st_inlet_t', 'hp_tsat', 'K')
    m.cmp('st_sh_ok', 'st_superheat', '>=', 50)
    m.NOT('st_sh_low', 'st_sh_ok')
    m.cmp('st_sh_wet', 'st_superheat', '<', 20)
    m.AND('st_wet_c', ['st_adm', 'st_sh_wet'])
    m.diff('st_cas_hot', 'st_inlet_t', 30)
    m.sel('st_cas_tgt', 'st_adm', ['ambient_t', 'st_cas_hot'])
    m.lag('st_casing_t', 'st_cas_tgt', 900, 7200, 35, '°C', '30MAA10')
    m.diff('st_mismatch', 'st_inlet_t', 'st_casing_t', 'K')
    m.cmp('st_match', 'st_mismatch', '<=', 320)
    m.cmp('st_p_ok', 'hp_p', '>=', 40)
    m.cmp('st_run_ge2', 'st_start_state', '>=', 1)
    m.cmp('st_run_le2', 'st_start_state', '<=', 6)
    m.AND('st_rolling', ['st_run_ge2', 'st_run_le2'])
    m.AND('st_sh_alarm_c', ['st_rolling', 'st_sh_low'])
    m.OR('st_any_trip', [f'{t}_latched' for t in ST_TRIPS])
    m.NOT('st_trips_clear', 'st_any_trip')
    m.AND('st_roll_ready', ['st_trips_clear', 'st_tg_run', 'st_ecc_ok', 'st_sh_ok', 'st_match', 'st_vac_ok',
                            'st_p_ok', 'st_lube_ok'])
    # steam turbine generator
    m.sync('st', '30MKC10', '30BAC10', '30MAY10CS001', 'st_in_fsnl', 'st_speed', 'Steam turbine')
    m.tab('st_mw_sp', 'st_flow', [[0, 0], [70, 135]])
    m.prod('st_mw_t', ['st_brk_cmd', 'st_mw_sp'])
    m.ramp('st_mw', 'st_mw_t', 2, 10, 0, 'MW', '30MKA10')
    m.AND('gen3_prot_c', ['st_any_trip', 'st_brk_cmd'])
    m.cmp('st_mw_120', 'st_mw', '>=', 120)
    m.AND('plant_at_load', ['st_mw_120', 'hp_byp_shut', 'gt1_at_base'])
    # the steam turbine's start (FIRST-TRAIN §4 #18)
    stop = {'st_adm': 0, 'st_speed_sp': 0, 'st_bias': 0}
    m.machines.append({'id': 'st_start', 'kks': '30MAA10', 'init': 'standstill',
        'commands': {'roll': {'from': ['standstill'], 'to': 'roll'}, 'hold': {'from': ['accel'], 'to': 'hold'},
                     'continue': {'from': ['hold'], 'to': 'accel'},
                     'stop': {'from': ['roll', 'soak', 'accel', 'fsnl', 'hold'], 'to': 'coastdown'}},
        'states': [
            {'id': 'standstill', 'set': stop, 'watch': False},
            {'id': 'roll', 'set': {'st_adm': 1, 'st_speed_sp': 0.2667}, 'next': [['st_at_800', 'soak']],
             'say': 'Stop valves open: rolling to 800 rpm'},
            {'id': 'soak', 'next': [['st_soak_done', 'accel']], 'watch': False, 'say': 'Holding at 800 rpm to warm'},
            {'id': 'accel', 'set': {'st_speed_sp': 1}, 'next': [['st_at_3000', 'fsnl']],
             'say': 'Accelerating through the critical speeds (1,600–1,900 rpm) to 3,000 rpm'},
            {'id': 'fsnl', 'next': [['st_brk_cmd', 'loaded']], 'watch': False,
             'say': 'Full speed no load: ready to synchronise'},
            {'id': 'loaded', 'next': [['st_brk_open', 'fsnl']], 'watch': False,
             'say': 'On the grid: inlet pressure control, the bypass closes'},
            {'id': 'hold', 'say': 'Speed held'},
            {'id': 'coastdown', 'set': stop, 'next': [['st_still', 'standstill']], 'say': 'Stopping: stop valves closed'},
            {'id': 'trip', 'set': stop, 'next': [['st_still', 'standstill']], 'say': 'TRIPPED: stop valves closed'}]})
    m.op('30MAA10', 'roll', None, [
        ('st_trips_clear', 'A turbine trip is latched: reset it first'), ('st_lube_ok', 'Lube oil pressure low'),
        ('st_tg_run', 'Turning gear not running'),
        ('st_ecc_ok', 'Rotor eccentricity over 40 µm: more time on the turning gear'),
        ('st_vac_ok', 'Condenser pressure over 12 kPa(a)'), ('st_p_ok', 'HP steam pressure below 40 bar'),
        ('st_sh_ok', 'HP steam superheat below 50 K'),
        ('st_match', 'Steam more than 320 K hotter than the HP casing')], ('screen',), machine='st_start')
    for c in ('hold', 'continue', 'stop'):
        m.op('30MAA10', c, None, (), ('screen',), machine='st_start')
    m.start_stop('30MAV20AP001', 'st_jack', [('st_lube_ok', 'Lube oil pressure low: the jacking pump draws on it')],
                 ok=False)
    m.op('30MAK10AE001', 'start', {'st_tg_cmd': 1}, [('st_lube_ok', 'Lube oil pressure below 1.8 bar'),
                                                     ('st_jack_ok', 'Jacking oil pressure below 80 bar')])
    m.op('30MAK10AE001', 'stop', {'st_tg_cmd': 0})
    m.op('30MAW10AA001', 'open', {'st_gland_cmd': 1},
         [('st_tg_run', 'Turning gear not running: steam on a stopped rotor bows it'),
          ('aux_ok', 'Auxiliary steam below 10 bar')])
    m.op('30MAW10AA001', 'close', {'st_gland_cmd': 0})
    for x, n in (('a', 1), ('b', 2)):
        m.start_stop(f'30MAJ10AP00{n}', f'vac_{x}', [('ccw_ok', 'Closed cooling water not in service: the seal '
                                                               'water cooler needs it')], ok=False)
        m.start_stop(f'30LCB10AP00{n}', f'cep_{x}', [('hw_ok', 'Hotwell level too low'),
                                                     ('cep_mf_open', 'Minimum flow valve 30LCA10AA001 not open')])
    m.valve_ops('30LCA10AA001', 'cep_mf_cmd', setop=False)
    perm = [('byp_permit', 'Bypass blocked: condenser pressure over 25 kPa, no circulating water or no condensate '
                           'pump')]
    m.ctrl_machine('hp_byp_ctrl', '30MAN10AA001', needs=perm, say_auto='HP bypass in automatic: holds the pressure')
    m.ctrl_machine('lp_byp_ctrl', '30MAN20AA001', needs=perm, say_auto='LP bypass in automatic')
    m.interlock('byp_blocked', 'byp_block_c', [{'machine': 'hp_byp_ctrl', 'to': 'manual'},
                                               {'machine': 'lp_byp_ctrl', 'to': 'manual'}], '30MAN10AA001',
                'Condenser pressure high-high, no CW flow or no condensate pump: the bypass closes')
    # trips (FIRST-TRAIN §4)
    to_trip = [{'machine': 'st_start', 'to': 'trip'}]
    m.trip('st_trip_lube', '30MAV10CP001', 'Steam turbine lube oil pressure low-low', 'st_lp_ll', to_trip, 'PALL', 1,
           'st')
    m.trip('st_trip_cond_p', '30MAG10CP001', 'Condenser pressure high-high', 'cond_hh', to_trip, 'PAHH', 1, 'st')
    m.trip('st_trip_os', '30MAY10CS001', 'Steam turbine overspeed', 'st_os', to_trip, 'SAHH', None, 'st')
    m.trip('st_trip_axial', '30MAD10CG001', 'Steam turbine axial displacement high-high', 'st_axial_hh', to_trip,
           'ZAHH', 0.5, 'st')
    m.trip('st_trip_vib', '30MAD10CY001', 'Steam turbine bearing vibration high-high', 'st_vib_hh', to_trip, 'VAHH',
           2, 'st')
    m.trip('st_trip_steam_t', '30MAA10CT001', 'HP steam temperature low (wet steam)', 'st_wet_c', to_trip, 'TALL', 5,
           'st')
    m.trip('gen3_trip_prot', '30BAC10', 'Steam turbine generator breaker opened by protection', 'gen3_prot_c',
           [{'set': {'st_brk_cmd': 0}}], None, None, 'st')
    m.trip('cep_trip_hw', '30MAG10CL001', 'Hotwell level low-low: condensate pumps stopped', 'cep_ll_c',
           [{'set': {'cep_a_cmd': 0, 'cep_b_cmd': 0}}], 'LALL', 1, 'cep')
    # alarms (FIRST-TRAIN §5)
    for k in (1, 2, 3):
        c = f'30MAG10CP00{k}'
        m.alarm(f'cond_p{k}_h', c, f'Condenser pressure high ({k})', f'cond_p{k}_h', 2, isa='PAH',
                clear=f'cond_p{k}_hc', suppress='cond_sup')
        m.alarm(f'cond_p{k}_hh', c, f'Condenser pressure high-high ({k})', f'cond_p{k}_hh', 1, isa='PAHH',
                clear=f'cond_p{k}_hhc', suppress='cond_sup')
    m.alarm('hw_high', '30MAG10CL001', 'Hotwell level high', 'hw_h', 2, isa='LAH')
    m.alarm('hw_low', '30MAG10CL001', 'Hotwell level low', 'hw_l', 2, isa='LAL')
    m.alarm('hw_ll', '30MAG10CL001', 'Hotwell level low-low (condensate pumps trip)', 'hw_ll', 1, isa='LALL')
    m.alarm('st_tg_gland', '30MAK10AE001', 'Steam turbine turning gear stopped with gland steam on', 'st_bow_c', 1)
    for k in range(1, 9):
        c = f'30MAD10CY00{k}'
        m.alarm(f'st_vib{k}_h', c, f'Steam turbine bearing vibration high ({k})', f'st_vib{k}_h', 2, isa='VAH')
        m.alarm(f'st_vib{k}_hh', c, f'Steam turbine bearing vibration high-high ({k})', f'st_vib{k}_hh', 1,
                isa='VAHH')
    for k in (1, 2, 3):
        m.alarm(f'st_os{k}', f'30MAY10CS00{k}', f'Steam turbine overspeed ({k})', 'st_os', 1, isa='SAHH')
    m.alarm('st_sh_low', '30MAA10CT001', 'HP steam superheat too low to roll', 'st_sh_alarm_c', 3, isa='TAL')
    m.alarm('hp_byp_open_long', '30MAN10AA001', 'HP bypass wide open for over 30 min', 'hp_byp_wide', 3, isa='ZAH',
            delay=1800)
    for x, n in (('a', 1), ('b', 2)):
        m.alarm(f'cep_{x}_minflow', f'30LCB10AP00{n}', f'Condensate pump {x.upper()} on minimum flow too long',
                f'cep_{x}_onmin', 3, delay=1800)
    m.alarm('cw_ret_high', '30PAB20BR010', 'CW return temperature high', 'cw_ret_h', 2, isa='TAH')
    # what is seen and heard
    for c in ('30MAA10', '30MAB10', '30MKA10'):
        m.b(kks=c, anim='shaft', of='st_speed', scale=50)
    m.b(kks='30MAA10', sound='steam_rush', gain={'of': 'st_flow', 'table': [[0, 0], [70, 1]]})
    m.b(kks='30MAB10', sound='turbine_hum', gain={'of': 'st_speed', 'table': [[0, 0], [1, 1]]},
        pitch={'of': 'st_speed', 'table': [[0, 0.1], [1, 1]]})
    m.b(kks='30MAB10', shake='st_vib3', scale=0.002)
    m.b(kks='30MKA10', sound='gen_hum', gain={'of': 'st_v', 'table': [[0, 0], [1, 1]]})
    m.b(kks='30MAK10AE001', anim='shaft', of='st_tg_spd', scale=50)
    m.b(kks='30MAK10AE001', sound='turning_gear', gain={'of': 'st_tg_run', 'table': [[0, 0], [1, 1]]})
    m.b(kks='30BAC10', anim='contacts', of='st_brk_cmd')
    m.b(kks='30BAC10', lamp='closed', of='st_brk_cmd')
    m.b(kks='30MAW10AA001', anim='stem', of='st_gland_pos')
    m.b(kks='30MAN10AA001', anim='stem', of='hp_byp_pos')
    m.b(kks='30MAN20AA001', anim='stem', of='lp_byp_pos')
    m.b(kks='30MAN20AA001', sound='steam_vent', gain={'of': 'byp_flow', 'table': [[0, 0], [70, 1]]})
    m.b(kks='30LCA10AA001', anim='stem', of='cep_mf_pos')
    m.b(kks='30MAA10AA201', anim='stem', of='st_adm')
    m.b(kks='30MAA10AA001', anim='stem', of='st_flow_a')
    m.b(kks='30MAA10CT001', show='st_inlet_t')
    for k in (1, 2, 3):
        m.b(kks=f'30MAG10CP00{k}', show=f'cond_p{k}')
        m.b(kks=f'30MAV10CP00{k}', show=f'st_lp_{k}')
        m.b(kks=f'30MAY10CS00{k}', show='st_rpm')
    for k in range(1, 9):
        m.b(kks=f'30MAD10CY00{k}', show=f'st_vib{k}')
    m.b(kks='30MAD10CG001', show='st_axial')
    m.b(kks='30MAG10CL001', show='hw_lvl')
    for x, c in (('a', '30MAJ10AP001'), ('b', '30MAJ10AP002')):
        m.b(kks=c, anim='shaft', of=f'vac_{x}_cmd', scale=10)
        m.b(kks=c, sound='liquid_ring', gain={'of': f'vac_{x}_cmd', 'table': [[0, 0], [1, 1]]})
        m.b(kks=c, lamp='running', of=f'vac_{x}_cmd')
    for x, c in (('a', '30LCB10AP001'), ('b', '30LCB10AP002')):
        m.b(kks=c, anim='shaft', of=f'cep_{x}_spd', scale=24.7)
        m.b(kks=c, sound='motor_small', gain={'of': f'cep_{x}_spd', 'table': [[0, 0], [1, 0.8]]})
        m.b(kks=c, lamp='running', of=f'cep_{x}_run')
    for x, c in (('lac', '30MAV10AP001'), ('ldc', '30MAV10AP002')):
        m.b(kks=c, anim='shaft', of=f'st_{x}_run', scale=49)
        m.b(kks=c, lamp='running', of=f'st_{x}_run')
    m.b(kks='30MAV20AP001', lamp='running', of='st_jack_run')
    return m


def models():
    """In plant.json's area order (control has no behaviour; the rack carries no equipment)."""
    return [bop(), ct(), cw(), gt1(), trafo1(), hrsg1(), st()]
