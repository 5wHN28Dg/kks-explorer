"""Runs one shard of the Python tests (`unittest discover -s tests`), for CI's `python` jobs (.github/workflows/tests.yml),
which run the shards side by side. Every test discovered runs in exactly one shard: the slow Walkdown Plant vector
classes named in HEAVY have shards of their own, every other test (and any module that fails to load) is in shard 0.
  .venv/bin/python tests/shards.py N      (N from 0 to SHARDS - 1)
  .venv/bin/python tests/shards.py list   (each shard's test count)"""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SHARDS = 3
# from CI's logs (2026-10-23, the run cut off at its 20 minutes): format 1's vectors ~8 min (the cold start and its
# forks built, then replayed); format 2's ~7.5 min, with the cold start's timing ~8 min; shard 0 the rest ~4-7 min
HEAVY = {'test_plant3d.Vectors': 1, 'test_plant3d.Vectors2': 2, 'test_plant3d.ColdStart': 2}


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


def discover():
    return list(tests_of(unittest.TestLoader().discover(HERE, top_level_dir=HERE)))


def main(arg):
    tests = discover()
    if arg == 'list':
        for k in range(SHARDS):
            print(k, sum(1 for t in tests if shard_of(t) == k))
        return 0
    k = int(arg)
    if not 0 <= k < SHARDS:
        raise SystemExit(f'a shard from 0 to {SHARDS - 1}')
    suite = unittest.TestSuite(t for t in tests if shard_of(t) == k)
    print(f'shard {k} of {SHARDS}: {suite.countTestCases()} of {len(tests)} tests', flush=True)
    r = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if r.wasSuccessful() else 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ''))
