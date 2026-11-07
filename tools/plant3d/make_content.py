#!/usr/bin/env python3
"""Write the first train (docs/plant3d/FIRST-TRAIN.md), the water treatment plant (WATER-TREATMENT.md), the site beyond them (docs/plant3d/SITE.md) and the kit's interface to data/plant3d/ in the layout of
docs/PLANT3D.md, then check it with the reference validator (ref/plant3d.py).

    python3 tools/plant3d/make_content.py          # check that data/plant3d matches what this makes
    python3 tools/plant3d/make_content.py --write  # write it

The files are generated so that repeated pieces (twelve thermocouples, ten fans, three pumps) stay consistent; the
tests check that the committed files are exactly what this script makes."""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
sys.path.insert(0, ROOT)
import kit, train_hands, train_weather, train_areas, train_hoists, train_lift, train_model, train_content, train_screens, train_staff, site_areas, wtp_areas, wtp_content, wtp_model  # noqa: E402
from workshop import pressure_transmitter as ws_pressure_transmitter  # noqa: E402
from workshop import steam_turbine as ws_steam_turbine  # noqa: E402
from workshop import gas_turbine as ws_gas_turbine  # noqa: E402

# the part kinds with Workshop data (docs/plant3d/WORKSHOP.md §4): each a module of tools/plant3d/workshop/
WORKSHOP = [ws_pressure_transmitter, ws_steam_turbine, ws_gas_turbine]

OUT = os.path.join(ROOT, 'data', 'plant3d')


def dump(obj):
    """Readable, stable JSON: top-level keys on their own lines, list items one per line."""
    def one(x):
        return json.dumps(x, ensure_ascii=False, separators=(', ', ': '))
    lines = ['{']
    items = list(obj.items())
    for i, (k, v) in enumerate(items):
        end = ',' if i < len(items) - 1 else ''
        if isinstance(v, list) and v:
            lines.append(f' {json.dumps(k)}: [')
            for j, x in enumerate(v):
                lines.append('  ' + one(x) + (',' if j < len(v) - 1 else ''))
            lines.append(' ]' + end)
        elif isinstance(v, dict) and v and k in ('parts', 'kks', 'media', 'init'):
            lines.append(f' {json.dumps(k)}: {{')
            sub = list(v.items())
            for j, (kk, vv) in enumerate(sub):
                lines.append(f'  {json.dumps(kk, ensure_ascii=False)}: {one(vv)}' + (',' if j < len(sub) - 1 else ''))
            lines.append(' }' + end)
        else:
            lines.append(f' {json.dumps(k)}: {one(v)}{end}')
    lines.append('}')
    return '\n'.join(lines) + '\n'


def codes(areas):
    out = []
    for a in areas:
        for e in a['equipment']:
            out.append(e['kks'])
            out += [c['kks'] for c in e.get('parts', [])]
        for p in a['pipes']:
            out.append(p['kks'])
            out += [v['kks'] for v in p.get('valves', []) + p.get('parts', [])]
        out += [s['kks'] for s in a['structures'] if 'kks' in s]
    return out


AIR = ('ia_ok', 'Instrument air below 4 bar: an air-operated valve can\'t move')


def air_operated(areas):
    """The codes of the pneumatic valves of the areas (the part's `actuator`, or its default)."""
    parts = kit.kit()['parts']
    out = set()
    for a in areas:
        items = list(a['equipment'])
        for e in a['equipment']:
            items += e.get('parts', [])
        for p in a['pipes']:
            items += p.get('valves', []) + p.get('parts', [])
        for it in items:
            spec = parts.get(it.get('part'), {}).get('params', {}).get('actuator')
            if spec and it.get('params', {}).get('actuator', spec.get('default')) == 'pneumatic':
                out.add(it['kks'])
    return out


def add_air_permissives(areas, models):
    """FIRST-TRAIN §4 #1: a pneumatic valve refuses to move below 4 bar of instrument air: the ops that move one
    (open, set, auto) need `ia_ok`."""
    pneumatic = air_operated(areas)
    for m in models:
        for o in m.ops:
            if o['kks'] in pneumatic and o['do'] in ('open', 'set', 'auto'):
                o['needs'] = list(o.get('needs', [])) + [list(AIR)]


def _with_world(sc, world):
    """A version 2 scenario with its `world` after its `start` (REALISM.md §2.1), or last without one."""
    out = {}
    for k, v in sc.items():
        out[k] = v
        if k == 'start':
            out['world'] = world
    out.setdefault('world', world)
    return out


def build():
    """{relative path: text} for everything under data/plant3d."""
    areas = site_areas.add_to_train(train_areas.areas()) + wtp_areas.areas() + site_areas.areas()
    by_id = {a['id']: a for a in areas}
    by_id['hrsg1']['equipment'] += train_hoists.hrsg1_equipment()     # the hoists (PLANT3D §20.5)
    by_id['hrsg1']['signs'] += train_hoists.hrsg1_signs()
    by_id['st']['equipment'] += train_hoists.st_equipment()
    by_id['hrsg1']['equipment'] += train_lift.equipment()          # the service lift (PLANT3D §20.2)
    by_id['hrsg1']['structures'] += train_lift.structures()
    plant = train_content.plant(codes(areas), [a['id'] for a in areas])
    plant['clock'] = train_staff.CLOCK          # format 2's plant clock (§16.1): the staff's day
    files = {'kit.json': kit.kit(), 'plant.json': plant,
             'sounds.json': train_content.sounds(), 'screens.json': train_screens.screens()}
    for a in areas:
        files[f'areas/{a["id"]}.json'] = a
    models = train_model.models() + wtp_model.models()
    for m in models:
        {'hrsg1': train_hoists.roof_hoist, 'st': train_hoists.crane}.get(m.area, lambda _m: None)(m)
        if m.area == 'hrsg1':
            train_lift.model(m)
    add_air_permissives(areas, models)
    jobs = train_staff.works_tasks(models)      # with staff.json every work names its task (§15.2)
    for m in models:
        for w in getattr(m, 'works', []):
            w['task'] = jobs[w['id']]
    for m in models:
        files[f'model/{m.area}.json'] = m.file()
    state_kks = {v[0]: v[1]['kks'] for m in models for v in m.values if 'state' in v[1] and 'kks' in v[1]}
    for s in train_content.scenarios(state_kks):
        files[f'scenarios/{s["id"]}.json'] = s
    files['scenarios/shift_cold.json'] = train_staff.scenario(files['scenarios/cold_iron.json'])
    files['scenarios/shift_wtp.json'] = train_staff.scenario_wtp(files['scenarios/cold_iron.json'])
    for sid, world in train_weather.FREE_PLAY.items():     # free play's weather (REALISM.md §5.1, §5.5)
        files[f'scenarios/{sid}.json'] = _with_world(files[f'scenarios/{sid}.json'], world)
    files['weather.json'] = train_weather.weather()
    files['staff.json'] = train_staff.staff(models, train_staff.load_layout())
    for p in [train_content.cold_start(), train_content.hot_restart()] + train_content.tours() + \
            wtp_content.procedures() + site_areas.tours() + train_hoists.procedures():
        files[f'procedures/{p["id"]}.json'] = p
    files['tools.json'] = train_hands.TOOLS      # the tools carried (REALISM.md §2.3, milestone HW2)
    files.update(train_hands.files())           # the service files (§2.4) the hand actions are made from
    for w in WORKSHOP:
        d = w.data()
        files[f'workshop/{d["part"]}.json'] = d
        if hasattr(w, 'bench_source'):  # its bench made from the plant's own content (WORKSHOP.md §6.3)
            files[f'workshop/bench/{d["part"]}.json'] = w.bench([m.file() for m in models])
        elif hasattr(w, 'bench'):       # its bench model (WORKSHOP.md §6)
            files[f'workshop/bench/{d["part"]}.json'] = w.bench()
    return {k: dump(v) for k, v in sorted(files.items())}


def main():
    from ref import plant3d
    made = build()
    b = plant3d.check_files({k: v.encode() for k, v in made.items()})
    if '--write' in sys.argv:
        for rel, text in made.items():
            path = os.path.join(OUT, rel)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, 'w', encoding='utf-8') as f:
                f.write(text)
        print(f'wrote {len(made)} files to data/plant3d: {b.counts}')
        return 0
    on_disk = plant3d.load_dir(OUT) if os.path.isdir(OUT) else {}
    stale = sorted(set(made) ^ set(on_disk) | {k for k in made if on_disk.get(k) != made[k].encode()})
    if stale:
        print('data/plant3d differs from what make_content.py makes:', stale)
        return 1
    print(f'data/plant3d is up to date: {b.counts}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
