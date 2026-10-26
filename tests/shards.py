"""Runs one shard of a set of Python tests, for the CI jobs that run their shards side by side. Every test of the set
runs in exactly one shard (tests/test_shards.py checks). Three sets:
- `python` (.github/workflows/tests.yml): every test `unittest discover -s tests` finds; the slow Walkdown Plant tests
  and classes named in HEAVY have the shards given there, every other test (and any module that fails to load) is in
  shard 0;
- `content` (.github/workflows/plant3d-app.yml, the Walkdown Plant content tests): the modules in CONTENT_MODULES; the
  tests and classes named in CONTENT have the shards given there, every other test (and any module that fails to
  load) is in shard 0;
- `app` (.github/workflows/plant3d-app.yml, the Walkdown Plant app's Godot tests, apps/plant3d/tests/test_*.gd): the
  files named in APP have the shards given there, every other one is in shard 0. This one only names a shard's files:
  apps/plant3d/build.sh runs them (PLANT_TEST_SHARD=N; unset, every file).
  .venv/bin/python tests/shards.py N            (a `python` shard, N from 0 to SHARDS - 1)
  python3 tests/shards.py content N             (a `content` shard, N from 0 to CONTENT_SHARDS - 1)
  python3 tests/shards.py app N                 (an `app` shard's test files, comma-separated, N from 0 to APP_SHARDS - 1)
  .venv/bin/python tests/shards.py [content|app] list   (each shard's test count)"""
import os, sys, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SHARDS = 5
# a test's id or its class. Times from CI's log (2026-10-26, PR #268's run: each test's time up to the line that ends
# it; the job's limit is 30 minutes): shard 0 had grown to ~1440 s of tests (24.5 minutes of the job) and was cut off at
# 30 on a slower runner (#265), most of it the staff's forks (test_plant3d_staff). Keep each shard under half of the 30
# minutes; one test is never split across shards: a test that grows past ~12 minutes alone can only be made faster.
HEAVY = {
    # format 1's vectors: the train part made again (~257 s) and replayed (~209 s), the hot restart (~101 s), the cold
    # start with fast-forward (~53 s): ~620 s
    'test_plant3d.Vectors': 1,
    'test_plant3d.ColdStart': 1,
    # format 2's vectors but the day (~450 s: the water plant ~315 s, the train ~132 s) and the held job's PPE over a
    # night (~191 s): ~644 s
    'test_plant3d.Vectors2': 2,
    'test_plant3d_staff.FirstTrainStaff.test_ppe_on_before_a_held_job_and_for_the_supervisors': 2,
    # format 2's first train's day made again (~485 s)
    'test_plant3d.Vectors2.test_frozen_day': 3,
    # the staff's day's forks replayed (~583 s) and the day itself (~96 s): ~680 s
    'test_plant3d_staff.FirstTrainStaff.test_forks': 4,
    'test_plant3d_staff.FirstTrainStaff.test_day_replays': 4,
    # shard 0 the rest (~355 s): the staff's other tests, the water treatment model, the sounds, everything else
}

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
    # the held job's PPE over a night (CI, 2026-10-26: ~191 s; content shard 0 had reached 18.8 of the job's 40
    # minutes, shard 1 4.5)
    'test_plant3d_staff.FirstTrainStaff.test_ppe_on_before_a_held_job_and_for_the_supervisors': 1,
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
    # the staff's day's forks replayed (CI, 2026-10-26: ~583 s, the job up to 21.7 of its 40 minutes in shard 2 with
    # format 1's replays; shard 3 had taken 5)
    'test_plant3d_staff.FirstTrainStaff.test_forks': 3,
    # the first train's day made again (~118 s here, ~485 s on CI), the RO cleaning (~46 s); format 2's train forks
    # replayed (~69 s) in shard 2 (the job had reached 18.3 of its 40 minutes on CI)
    'test_plant3d.Vectors2.test_frozen_day': 4,
    'test_plant3d.Vectors2.test_frozen_wtp_cip': 4,
    'test_plant3d.Vectors2.test_train_forks_replay': 2,
    # shard 0 the rest: the water treatment model's tests (~140 s on CI, which share their procedure runs), the staff's
    # other tests (the day replayed ~96 s), the bench (~20 s, with Godot), the content and the validator
}

APP_DIR = os.path.join(os.path.dirname(HERE), 'apps', 'plant3d', 'tests')
APP_SHARDS = 4
# a test file's name (without .gd): its shard. All in one run they took 598 s of build.sh's 600 s on CI (2026-10-26)
# and were cut off now and then; 413 s on the laptop since three UI tests stopped rebuilding the Crew panel every round
# (from 592 s). Times on the laptop, 2026-10-26 (CI's runners took 1 to 1.6 times as long). Keep each shard well under
# half of the 600 s on CI; a file that makes its shard grow past ~150 s here goes to another one or to a shard of its own.
APP = {
    # the walking tests: every stair, ladder and route walked (~170 s; ~167 s on CI)
    'test_walk': 1,
    # the overnight jobs (~38 s), the route's frames (~27 s), maintenance (~25 s): ~90 s
    'test_ui_overnight': 2,
    'test_frames_route': 2,
    'test_ui_maintenance': 2,
    # the cold start through the screens and the panels (~15 s, ~14 s), the saved run (~13 s), the RO cleaning (~10 s),
    # the water plant's staff (~9 s), the mixed-bed regeneration (~9 s), the parts kit (~7 s), the water plant's start
    # (~6 s), the crew (~6 s): ~89 s
    'test_ui_screens_cold_start': 3,
    'test_ui_cold_start': 3,
    'test_run_save': 3,
    'test_ui_ro_cip': 3,
    'test_ui_wtp_staff': 3,
    'test_ui_mb_regen': 3,
    'test_kit': 3,
    'test_ui_wtp_start': 3,
    'test_ui_crew': 3,
    # shard 0 the rest (~64 s), in the job that also makes the exports
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
    return HEAVY.get(t.id(), HEAVY.get(name_of(t), 0))


def content_shard_of(t):
    return CONTENT.get(t.id(), CONTENT.get(name_of(t), 0))


def discover():
    return list(tests_of(unittest.TestLoader().discover(HERE, top_level_dir=HERE)))


def discover_content():
    if HERE not in sys.path:
        sys.path.insert(0, HERE)
    return list(tests_of(unittest.TestLoader().loadTestsFromNames(CONTENT_MODULES)))


def app_files():
    """Every app test file's name (without .gd), as tests/run_tests.gd finds them: test_*.gd."""
    return sorted(f[:-3] for f in os.listdir(APP_DIR) if f.startswith('test_') and f.endswith('.gd'))


def app_shard_of(name):
    return APP.get(name, 0)


def main(args):
    if args[:1] == ['app']:
        files, arg = app_files(), (args[1] if len(args) > 1 else '')
        if arg == 'list':
            for k in range(APP_SHARDS):
                print(k, sum(1 for f in files if app_shard_of(f) == k))
            return 0
        k = int(arg)
        if not 0 <= k < APP_SHARDS:
            raise SystemExit(f'a shard from 0 to {APP_SHARDS - 1}')
        mine = [f for f in files if app_shard_of(f) == k]
        if not mine:
            print(f'no test files in app shard {k}', file=sys.stderr)
            return 1
        print(','.join(mine))
        return 0
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
