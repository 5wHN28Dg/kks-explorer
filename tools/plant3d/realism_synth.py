"""A synthetic realism load for the first train (docs/plant3d/REALISM.md §11, milestone RE1): N model values shaped
like the realism content to come, appended to the last area's model file, to measure the model step before any of
that content is written. Never shipped: the bench reads it from a file (apps/plant3d/sim/tests/bench_realism.gd
--synth=LABEL:PATH; on a phone the app's `step=bench`, apps/plant3d/app/step_bench.gd, from its files folder).

    python3 tools/plant3d/realism_synth.py N [OUT]      (N: 600 is §11's plan; 1,000 with the new plant systems, J0)

The shares follow §11's split of the 600 and scale with N:
- wear items and their signs (5/12): per item a duty table of a running value, a clock-rate accumulator (`integrate`,
  as AG1's `wear` will be), three sign tables of the wear (vibration, noise, heat) and a threshold;
- component states and meters (4/12): component states that no node reads (a slot, no evaluation), and meters
  reading a state and a process value (`select` and `product`);
- weather, emissions and chemistry (3/12): diurnal tables of `world_hour` with their lags (the weather's ext values
  will be driven so), hourly sums and products (emissions corrected to 15 % O2) with a hold of the last hour, and
  chemistry lags.
Above 600 (J0's plant systems: fuel gas, the diesel, instrument air, fire water, the switchyard), the extra values
follow the first train's own mix of node kinds (comparisons, products, tables, sums, lags, logic).
Every node reads values of the joined model computed before it, so the stateless rule holds (§7.1); the result is
deterministic (no randomness: the same N gives the same file)."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, ROOT)
AREA = 'intake'         # the last area of plant.json with a model file: every value of the train is earlier


def sources(b):
    """The process values a wear item's duty and a meter read: the train's lags and integrators (running flows,
    temperatures, pressures, speeds), in model order."""
    return [name for name, n, kind in b.model.values if kind in ('lag', 'integrate', 'ramp')]


def make(n, b):
    src = sources(b)
    out = []

    def add(name, node):
        out.append([name, node])
        return name

    def s(i):
        return src[(i * 7) % len(src)]

    n_wear = n * 5 // 12 if n <= 600 else 250
    n_comp = n * 4 // 12 if n <= 600 else 200
    n_env = (n if n <= 600 else 600) - n_wear - n_comp
    i = 0
    while sum(1 for x in out if x[0].startswith('rw')) + 6 <= n_wear:
        duty = add(f'rw{i}_duty', {'of': s(i), 'table': [[0, 0], [1, 0.2], [50, 1], [1000, 2]]})
        wear = add(f'rw{i}_wear', {'integrate': duty, 'gain': 0.001, 'min': 0, 'max': 1})
        add(f'rw{i}_vib', {'of': wear, 'table': [[0, 1.2], [0.6, 2.8], [0.9, 7.1], [1, 11]]})
        add(f'rw{i}_noise', {'of': wear, 'table': [[0, 0], [0.7, 0], [1, 1]]})
        add(f'rw{i}_heat', {'of': wear, 'table': [[0, 0], [0.8, 0], [1, 25]]})
        add(f'rw{i}_fail', {'cmp': [wear, '>=', 0.95]})
        i += 1
    while len(out) < n_wear:
        add(f'rw_x{len(out)}', {'of': s(len(out)), 'table': [[0, 0], [100, 1]]})
    k = 0
    states = []
    while len(out) < n_wear + n_comp * 3 // 4:
        states.append(add(f'rc{k}', {'state': 0}))
        k += 1
    j = 0
    while len(out) < n_wear + n_comp:
        st = states[j % len(states)]
        if j % 2:
            add(f'rm{j}', {'select': st, 'cases': [s(j), 0]})
        else:
            add(f'rm{j}', {'product': [s(j), 0.004]})
        j += 1
    w = 0
    while len(out) < n_wear + n_comp + n_env:
        r = w % 5
        if r == 0:
            add(f're{w}', {'of': 'world_hour', 'table': [[0, 24], [6, 22], [14, 41], [24, 24]]})
        elif r == 1:
            add(f're{w}', {'lag': out[-1][0], 'tau': 1800})
        elif r == 2:
            add(f're{w}', {'product': [s(w), out[-1][0], 0.01]})
        elif r == 3:
            add(f're{w}', {'sum': [out[-1][0], out[-2][0], -1]})
        else:
            add(f're{w}', {'hold': out[-1][0], 'when': 'world_day'})
        w += 1
    # J0's plant systems: the first train's own mix
    mix = ['cmp', 'product', 'of', 'cmp', 'and', 'sum', 'lag', 'not', 'product', 'state', 'cmp', 'of']
    q = 0
    while len(out) < n:
        kind, a = mix[q % len(mix)], s(q + 3)
        prev = out[-1][0]
        node = {'cmp': {'cmp': [a, '>', 10]}, 'product': {'product': [a, 0.5]},
                'of': {'of': a, 'table': [[0, 0], [10, 1], [100, 3]]}, 'and': {'and': [prev, prev]},
                'sum': {'sum': [a, prev]}, 'lag': {'lag': a, 'tau': 5}, 'not': {'not': prev},
                'state': {'state': 0}}[kind]
        add(f'rp{q}', node)
        q += 1
    assert len(out) == n
    return out


def apply(files, vals):
    """files ({rel: parsed JSON}) with the synthetic values appended to the last area's model file and a `world` in
    every scenario (a version 1 scenario made version 2: its keys are all version 2's too)."""
    m = files[f'model/{AREA}.json']
    m['values'] = m['values'] + vals
    m['version'] = 2            # (the hold nodes: a version 1 model file's keys are all version 2's too)
    for rel, sc in files.items():
        if rel.startswith('scenarios/'):
            sc['version'] = 2
            sc.setdefault('world', {})
    return files


def main():
    from ref import plant3d as P
    n = int(sys.argv[1])
    b = P.check_dir(os.path.join(ROOT, 'data', 'plant3d'))
    vals = make(n, b)
    text = json.dumps({'area': AREA, 'values': vals}, separators=(',', ':')) + '\n'
    if len(sys.argv) > 2:
        with open(sys.argv[2], 'w', encoding='utf-8') as f:
            f.write(text)
    else:
        sys.stdout.write(text)


if __name__ == '__main__':
    main()
