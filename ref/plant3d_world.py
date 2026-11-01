"""Walkdown Plant's realism base (docs/plant3d/REALISM.md §2.1, milestone RE1): a version 2 scenario's `world`, its
random streams by purpose and item id, and the clock values `world_hour` and `world_day`.

Test-only reference, as ref/plant3d.py: the app's engine (apps/plant3d/sim/world.gd) must agree with it bit for bit
on ref/vectors/plant3d-realism.json.

    stream(seed, tag, item)   -> the stream's first state (§2.1: s = mix32(mix32(seed ^ P) ^ FNV-1a(item)), 1 for 0)
    draw(s)                   -> (the next state, r of 24 bits): §17.5's generator, shared with the people's streams
    clock_values(c)           -> (world_hour, world_day) at the clock c in tenths of a clock second
"""
from ref.courses import need, keys
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
    """A version 2 scenario's `world` (§2.1). RE1 knows `seed` and `year_day`; `weather`, `age` and `changes` come
    with the milestones that define them (WX1, AG2, EN2) and are unknown keys until then."""
    w = s['world']
    where = f'{rel}.world'
    need(isinstance(w, dict), 'bad_type', f'{where}: an object')
    keys(w, (), ('seed', 'year_day'), where)
    need(b.plant.get('clock') is not None, 'bad_ref', f'{where}: the plant has no clock (the clock values read it)')
    if 'seed' in w:
        need(whole(w['seed']) and 0 <= w['seed'] < 2 ** 32, 'bad_number',
             f'{where}.seed: a whole number from 0 to 2^32 − 1')
    if 'year_day' in w:
        need(whole(w['year_day']) and 1 <= w['year_day'] <= 365, 'bad_number',
             f'{where}.year_day: a whole number from 1 to 365')


def world_seed(sc):
    """The world's seed: its own, else the staff's, else 1 (§2.1)."""
    w = sc.get('world', {})
    if 'seed' in w:
        return w['seed']
    return sc['staff']['seed'] if 'staff' in sc else 1


def names_in(x):
    """Whether any text in x (a parsed content file or part of one) is a clock value's name."""
    if isinstance(x, str):
        return x in NAMES
    if isinstance(x, dict):
        return any(names_in(v) for v in x.values())
    if isinstance(x, list):
        return any(names_in(v) for v in x)
    return False
