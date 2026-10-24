"""Runs one shard of a set of Python tests, for the CI jobs that run their shards side by side. Every test of the set
runs in exactly one shard (tests/test_shards.py checks). Two sets:
- `python` (.github/workflows/tests.yml): every test `unittest discover -s tests` finds; the slow Walkdown Plant vector
  classes named in HEAVY have shards of their own, every other test (and any module that fails to load) is in shard 0;
- `content` (.github/workflows/plant3d-app.yml, the Walkdown Plant content tests): the modules in CONTENT_MODULES; the
  tests and classes named in CONTENT have the shards given there, every other test (and any module that fails to
  load) is in shard 0.
  .venv/bin/python tests/shards.py N            (a `python` shard, N from 0 to SHARDS - 1)
  python3 tests/shards.py content N             (a `content` shard, N from 0 to CONTENT_SHARDS - 1)
  .venv/bin/python tests/shards.py [content] list   (each shard's test count)"""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SHARDS = 3
# from CI's logs (2026-10-23, the run cut off at its 20 minutes): format 1's vectors ~8 min (the cold start and its
# forks built, then replayed), ColdStart's ~0.75 min with it; format 2's ~7.5 min before W3's two runs (more since);
# shard 0 the rest
HEAVY = {'test_plant3d.Vectors': 1, 'test_plant3d.ColdStart': 1, 'test_plant3d.Vectors2': 2}

CONTENT_MODULES = ('test_plant3d', 'test_plant3d_staff', 'test_plant3d_bench')
CONTENT_SHARDS = 5
# a test's id or its class; times measured on the laptop, 2026-10-24 (CI's runners took about 1.45 times as long):
# test_plant3d took 27 of its job's 40 minutes on CI as one part, ~18.5 min here. Each shard ~4-5 min here; keep each
# well under half of the job's 40 minutes on CI, and give a part that grows past ~5 min here a shard of its own.
CONTENT = {
    # format 1's train part made again (the cold start, its snapshots replayed, 77 forks): ~245 s; the cold start
    # run again with fast-forward: ~48 s
    'test_plant3d.Vectors.test_frozen_train': 1,
    'test_plant3d.ColdStart': 1,
    # the hot restart made again (~68 s); format 1's train (~110 s) and hot restart (~45 s) replayed; format 2's
    # train part made again (the cold start and the permit forks, ~64 s)
    'test_plant3d.Vectors.test_frozen_hot': 2,
    'test_plant3d.Vectors.test_train_replay': 2,
    'test_plant3d.Vectors.test_hot_replay': 2,
    'test_plant3d.Vectors2.test_frozen_train': 2,
    # the water treatment plant's start made again (~116 s) and replayed (~132 s); its regeneration made (~38 s)
    'test_plant3d.Vectors2.test_frozen_wtp': 3,
    'test_plant3d.Vectors2.test_wtp_replays': 3,
    'test_plant3d.Vectors2.test_frozen_wtp_regen': 3,
    # the first train's day made again (~118 s), the RO cleaning (~46 s), format 2's train forks replayed (~69 s)
    'test_plant3d.Vectors2.test_frozen_day': 4,
    'test_plant3d.Vectors2.test_frozen_wtp_cip': 4,
    'test_plant3d.Vectors2.test_train_forks_replay': 4,
    # shard 0 the rest (~5 min): the water treatment model's tests (~140 s, which share their procedure runs), the staff
    # (~125 s), the bench (~20 s, with Godot), the content and the validator
}


def tests_of(suite):
    for t in suite:
        if isinstance(t, unittest.TestSuite):
            yield from tests_of(t)
        else:
            yield t


def name_of(t):
    return f'{type(t).__module__}.{type(t).__qualname__}'


def shard_of(t):
    return HEAVY.get(name_of(t), 0)


def content_shard_of(t):
    return CONTENT.get(t.id(), CONTENT.get(name_of(t), 0))


def discover():
    return list(tests_of(unittest.TestLoader().discover(HERE, top_level_dir=HERE)))


def discover_content():
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    return list(tests_of(unittest.TestLoader().loadTestsFromNames(CONTENT_MODULES)))


def main(args):
    if args[:1] == ['content']:
        tests, of, n, args = discover_content(), content_shard_of, CONTENT_SHARDS, args[1:]
    else:
        tests, of, n = discover(), shard_of, SHARDS
    arg = args[0] if args else ''
    if arg == 'list':
        for k in range(n):
            print(k, sum(1 for t in tests if of(t) == k))
        return 0
    k = int(arg)
    if not 0 <= k < n:
        raise SystemExit(f'a shard from 0 to {n - 1}')
    suite = unittest.TestSuite(t for t in tests if of(t) == k)
    print(f'shard {k} of {n}: {suite.countTestCases()} of {len(tests)} tests', flush=True)
    if not suite.countTestCases():
        print('no tests in this shard')     # as unittest: a run of nothing is not a pass
        return 1
    r = unittest.TextTestRunner(verbosity=2, warnings='default').run(suite)
    return 0 if r.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
