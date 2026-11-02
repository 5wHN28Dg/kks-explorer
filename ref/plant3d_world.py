"""Walkdown Plant's realism base (docs/plant3d/REALISM.md §2.1, milestone RE1): a version 2 scenario's `world`, its
random streams by purpose and item id, and the clock values `world_hour` and `world_day`.

Test-only reference, as ref/plant3d.py: the app's engine (apps/plant3d/sim/world.gd) must agree with it bit for bit
on ref/vectors/plant3d-realism.json.

    stream(seed, tag, item)   -> the stream's first state (§2.1: s = mix32(mix32(seed ^ P) ^ FNV-1a(item)), 1 for 0)
    draw(s)                   -> (the next state, r of 24 bits): §17.5's generator, shared with the people's streams
    clock_values(c)           -> (world_hour, world_day) at the clock c in tenths of a clock second
"""
from ref.courses import need, keys, lst, ident, is_num, check_table
from ref.plant3d_staff import mix32, mul32, draw  # noqa: F401  (draw: the one generator, §17.5)

# the purpose tags (§2.1): each purpose's streams are its own, so adding one purpose's items moves no other's draws
TAGS = {'draw': 0x44524157, 'causes': 0x43415553, 'weather': 0x57454154, 'stores': 0x53544f52, 'lab': 0x4c414253,
        'slips': 0x534c4950}
# the clock values (§2.1): engine-kept values after every other slot, only in a scenario with `world`
NAMES = ('world_hour', 'world_day')
DAY = 864000            # tenths of a clock second in a day
HOUR = 36000


def fnv1a(text):
    """FNV-1a, 32 bits, over the UTF-8 bytes of an item's id."""
    h = 2166136261
    for c in text.encode('utf-8'):
        h = mul32(h ^ c, 16777619)
    return h


def stream(seed, tag, item):
    s = mix32(mix32(seed ^ tag) ^ fnv1a(item))
    return s or 1


def clock_values(c):
    """world_hour, (C mod 864,000) / 36,000 in doubles, and world_day, C div 864,000 (§2.1); C is never negative."""
    return float(c % DAY) / float(HOUR), float(c // DAY)


def whole(x):
    return isinstance(x, int) and not isinstance(x, bool)


def check_world(s, b, rel):
    """A version 2 scenario's `world` (§2.1). RE1 knows `seed` and `year_day`, WX1 `weather` (§5.1); `age` and
    `changes` come with the milestones that define them (AG2, EN2) and are unknown keys until then."""
    w = s['world']
    where = f'{rel}.world'
    need(isinstance(w, dict), 'bad_type', f'{where}: an object')
    keys(w, (), ('seed', 'year_day', 'weather'), where)
    need(b.plant.get('clock') is not None, 'bad_ref', f'{where}: the plant has no clock (the clock values read it)')
    if 'seed' in w:
        need(whole(w['seed']) and 0 <= w['seed'] < 2 ** 32, 'bad_number',
             f'{where}.seed: a whole number from 0 to 2^32 − 1')
    if 'year_day' in w:
        need(whole(w['year_day']) and 1 <= w['year_day'] <= 365, 'bad_number',
             f'{where}.year_day: a whole number from 1 to 365')
    if 'weather' in w:
        check_world_weather(w['weather'], s, b, rel)


def world_seed(sc):
    """The world's seed: its own, else the staff's, else 1 (§2.1)."""
    w = sc.get('world', {})
    if 'seed' in w:
        return w['seed']
    return sc['staff']['seed'] if 'staff' in sc else 1


def names_in(x, names=NAMES):
    """Whether any text in x (a parsed content file or part of one) is one of `names` (the clock values')."""
    if isinstance(x, str):
        return x in names
    if isinstance(x, dict):
        return any(names_in(v, names) for v in x.values())
    if isinstance(x, list):
        return any(names_in(v, names) for v in x)
    return False


# ---------------------------------------------------------------- the weather (§5.1, milestone WX1)

WX_NAME = 'world_wx'     # the weather kind's index: an engine-kept value after the clock values, with world.weather
WX_LIMITS = {'kinds': 16, 'values': 16, 'seasons': 12, 'rows': 256, 'script': 256}


def check_weather(d, b, m):
    """weather.json (format `walkdown-plant-weather`, §5.1): the kinds, each with a diurnal table over world_hour per
    driven `ext` value; the driven values with their lag (tau, clock minutes); the seasons by day of the year, each
    with its start kind and its hourly transitions [from, to, weight]. Returns it."""
    from ref.plant3d import fmt
    where = 'weather.json'
    keys(d, ('format', 'version', 'kinds', 'values', 'seasons'), (), where)
    fmt(d, 'weather', where)
    vals = lst(d['values'], f'{where}.values', 1, WX_LIMITS['values'])
    vids = []
    for i, v in enumerate(vals):
        w = f'{where}.values[{i}]'
        keys(v, ('id', 'tau'), (), w)
        ident(v['id'], w)
        need(v['id'] not in vids, 'dup_id', f'{w}: {v["id"]} twice')
        need(v['id'] in m.ext, 'bad_ref', f'{w}: {v["id"]} is not an ext value of plant.json (the weather drives ext '
                                          f'values)')
        need(is_num(v['tau']) and v['tau'] > 0, 'bad_number', f'{w}.tau: clock minutes, above 0')
        vids.append(v['id'])
    kinds = lst(d['kinds'], f'{where}.kinds', 1, WX_LIMITS['kinds'])
    kids = []
    for i, k in enumerate(kinds):
        w = f'{where}.kinds[{i}]'
        keys(k, ('id', 'targets'), (), w)
        ident(k['id'], w)
        need(k['id'] not in kids, 'dup_id', f'{w}: {k["id"]} twice')
        kids.append(k['id'])
        need(isinstance(k['targets'], dict), 'bad_type', f'{w}.targets: an object of a table per driven value')
        for vid in k['targets']:
            need(vid in vids, 'bad_ref', f'{w}.targets.{vid}: not a value of weather.json\'s values')
        for vid in vids:
            need(vid in k['targets'], 'missing_key', f'{w}.targets.{vid}: every kind gives every driven value')
            t = k['targets'][vid]
            check_table(t, f'{w}.targets.{vid}')
            need(t[0][0] == 0 and t[-1][0] == 24, 'bad_table', f'{w}.targets.{vid}: a table over world_hour from 0 to 24')
    seasons = lst(d['seasons'], f'{where}.seasons', 1, WX_LIMITS['seasons'])
    sids, owner = [], {}
    for i, s in enumerate(seasons):
        w = f'{where}.seasons[{i}]'
        keys(s, ('id', 'days', 'start', 'hourly'), (), w)
        ident(s['id'], w)
        need(s['id'] not in sids, 'dup_id', f'{w}: {s["id"]} twice')
        sids.append(s['id'])
        days = lst(s['days'], f'{w}.days', 2, 2)
        for x in days:
            need(whole(x) and 1 <= x <= 365, 'bad_number', f'{w}.days: days of the year, 1 to 365')
        for day in season_days(days):
            need(day not in owner, 'bad_value', f'{w}.days: day {day} is in season {owner.get(day)} too')
            owner[day] = s['id']
        need(s['start'] in kids, 'bad_ref', f'{w}.start: no kind {s["start"]!r}')
        rows = lst(s['hourly'], f'{w}.hourly', 1, WX_LIMITS['rows'])
        pairs, total = set(), {}
        for j, r in enumerate(rows):
            wr = f'{w}.hourly[{j}]'
            lst(r, wr, 3, 3)
            need(r[0] in kids and r[1] in kids, 'bad_ref', f'{wr}: [from, to, weight] of kinds')
            need(whole(r[2]) and r[2] >= 0, 'bad_number', f'{wr}: a whole weight, 0 or more')
            need((r[0], r[1]) not in pairs, 'dup_id', f'{wr}: {r[0]} to {r[1]} twice')
            pairs.add((r[0], r[1]))
            total[r[0]] = total.get(r[0], 0) + r[2]
        for k in kids:
            need(total.get(k, 0) >= 1, 'bad_value', f'{w}.hourly: kind {k} has no way on (a weight above 0 from it)')
            need(total[k] <= 65536, 'limit', f'{w}.hourly: the weights from {k} total over 2^16 (PLANT3D §17.5)')
    for day in range(1, 366):
        need(day in owner, 'bad_value', f'{where}.seasons: day {day} of the year is in no season')
    return d


def season_days(days):
    """The days of the year a season's [first, last] covers (first > last runs over the year's end)."""
    a, z = days
    return list(range(a, z + 1)) if a <= z else list(range(a, 366)) + list(range(1, z + 1))


def year_day_of(year_day, c):
    """The day of the year at the clock c (§5.1): (year_day − 1 + world_day − 1) mod 365 + 1."""
    return (year_day - 1 + c // DAY - 1) % 365 + 1


def check_world_weather(x, s, b, rel):
    """A scenario's world.weather (§5.1): {"season": id} (seeded, the season of the scenario's start day), {"fixed":
    kind} or {"script": [[day, "HH:MM", kind], …]} (in time order, the first at or before the scenario's start)."""
    from ref.plant3d_staff import start_tenths, check_start
    where = f'{rel}.world.weather'
    need(isinstance(x, dict), 'bad_type', f'{where}: an object')
    keys(x, (), ('season', 'fixed', 'script'), where)
    need(len(x) == 1, 'bad_value', f'{where}: one of season, fixed or script')
    wx = b.weather
    need(wx is not None, 'bad_ref', f'{where}: the plant has no weather.json')
    kids = [k['id'] for k in wx['kinds']]
    start = start_tenths(s.get('start', b.plant['clock']['start']))
    if 'season' in x:
        se = next((q for q in wx['seasons'] if q['id'] == x['season']), None)
        need(se is not None, 'bad_ref', f'{where}.season: no season {x["season"]!r}')
        doy = year_day_of(s['world'].get('year_day', 1), start)
        need(doy in season_days(se['days']), 'bad_value', f'{where}.season: the scenario starts on day {doy} of the '
                                                           f'year, which is not in season {x["season"]}')
    elif 'fixed' in x:
        need(x['fixed'] in kids, 'bad_ref', f'{where}.fixed: no kind {x["fixed"]!r}')
    else:
        last = None
        for i, e in enumerate(lst(x['script'], f'{where}.script', 1, WX_LIMITS['script'])):
            w = f'{where}.script[{i}]'
            lst(e, w, 3, 3)
            check_start({'day': e[0], 'time': e[1]}, w)
            need(e[2] in kids, 'bad_ref', f'{w}: no kind {e[2]!r}')
            t = start_tenths({'day': e[0], 'time': e[1]})
            need(last is None or t > last, 'bad_value', f'{w}: after the entry before it')
            last = t
            if i == 0:
                need(t <= start, 'bad_value', f'{w}: the first entry is at or before the scenario\'s start')


def build_weather(sc, b, ix, seed):
    """The weather as the engine runs it (§5.1), for a scenario with world.weather: the kinds, the driven values'
    slots and lag factors 1 − e^(−0.1 × day_scale / (60 × tau)) (computed once), the targets per kind, each day's
    season, the hourly rows per season and kind, the mode and its script, and the state at step 0 (kind, stream)."""
    from ref.plant3d_staff import start_tenths
    from ref.plant3d import STEP
    import math
    d = b.weather
    w = sc['world']['weather']
    ds = b.plant['clock']['day_scale']
    kids = [k['id'] for k in d['kinds']]
    vids = [v['id'] for v in d['values']]
    season_of = [None] * 366
    rows = []
    for si, s in enumerate(d['seasons']):
        for day in season_days(s['days']):
            season_of[day] = si
        per = []
        for k in kids:
            tos = [kids.index(r[1]) for r in s['hourly'] if r[0] == k]
            ws = [r[2] for r in s['hourly'] if r[0] == k]
            per.append((tos, ws, sum(ws)))
        rows.append(per)
    start = start_tenths(sc.get('start', b.plant['clock']['start']))
    script = []
    if 'season' in w:
        mode, k0 = 'season', kids.index(next(s for s in d['seasons'] if s['id'] == w['season'])['start'])
    elif 'fixed' in w:
        mode, k0 = 'fixed', kids.index(w['fixed'])
    else:
        mode = 'script'
        script = [(start_tenths({'day': e[0], 'time': e[1]}), kids.index(e[2])) for e in w['script']]
        k0 = [k for t, k in script if t <= start][-1]
    return {'kinds': kids, 'mode': mode, 'script': script, 'season_of': season_of, 'rows': rows,
            'year_day': sc['world'].get('year_day', 1), 'slot': ix[WX_NAME],
            'values': [(ix[v['id']], 1 - math.exp(-STEP * ds / (60 * v['tau']))) for v in d['values']],
            'targets': [[[[float(x), float(y)] for x, y in k['targets'][v]] for v in vids] for k in d['kinds']],
            'k0': k0, 's0': stream(seed, TAGS['weather'], 'weather')}


def weather_step(e, gap, k_before):
    """Step 1w's weather (§5.1) on the engine e, after the clock values: one draw per whole hour the clock passed
    since the step before (seeded weather), the script's entries passed (scripted), then each driven value's lag
    toward its kind's target at world_hour (in a jump's step, the target itself), world_wx the kind; the event
    [n, "weather", from, to] when the kind differs from the step before's (k_before)."""
    from ref.courses import table_at
    wx, cur = e.wx, e.cur
    c1 = e.clock()
    c0 = c1 - e.ds - gap
    k = e.wx_kind
    if wx['mode'] == 'season':
        for h in range(c0 // HOUR + 1, c1 // HOUR + 1):
            e.wx_s, r = draw(e.wx_s)
            tos, ws, total = wx['rows'][wx['season_of'][year_day_of(wx['year_day'], h * HOUR)]][k]
            x, acc = (r * total) >> 24, 0
            for to, wt in zip(tos, ws):
                acc += wt
                if acc > x:
                    k = to
                    break
    elif wx['mode'] == 'script':
        for t, kk in wx['script']:
            if c0 < t <= c1:
                k = kk
    e.wx_kind = k
    hour = cur[e.ix['world_hour']]
    for (slot, f), t in zip(wx['values'], wx['targets'][k]):
        target = float(table_at(t, hour))
        if gap > 0:
            cur[slot] = target
        else:
            y = cur[slot]
            cur[slot] = y + (target - y) * f
    cur[wx['slot']] = float(k)
    if k != k_before:
        e.ev('weather', wx['kinds'][k_before], wx['kinds'][k])
