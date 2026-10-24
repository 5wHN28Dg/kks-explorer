"""CI runs Python tests in shards (tests/shards.py): the `python` jobs of tests.yml every test discovered, the `content`
jobs of plant3d-app.yml the Walkdown Plant content tests. For each set: every test or class it gives a shard of its own
exists, the shards together are every test of the set, each once, no shard is empty, and the workflow's matrix runs
every shard."""
import os, re, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shards  # noqa: E402

WORKFLOWS = os.path.join(os.path.dirname(shards.HERE), '.github', 'workflows')


def matrix(workflow, key):
    """The values of `key:` in the workflow's matrix (a one-line list)."""
    with open(os.path.join(WORKFLOWS, workflow), encoding='utf-8') as f:
        text = f.read()
    m = re.findall(rf'^\s+{key}: \[([^\]]*)\]\s*$', text, re.M)
    return text, [[x.strip() for x in v.split(',')] for v in m]


class Shards(unittest.TestCase):
    def test_every_test_runs_once(self):
        tests = shards.discover()
        names = {shards.name_of(t) for t in tests}
        for cls, k in shards.HEAVY.items():
            self.assertIn(cls, names, f'{cls} (shard {k}) is not a test class any more: update tests/shards.py')
            self.assertTrue(0 < k < shards.SHARDS)
        per = [sum(1 for t in tests if shards.shard_of(t) == k) for k in range(shards.SHARDS)]
        self.assertEqual(sum(per), len(tests))
        self.assertTrue(all(per), per)
        self.assertIn('test_shards.Shards', names)

    def test_every_content_test_runs_once(self):
        tests = shards.discover_content()
        ids = [t.id() for t in tests]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertFalse([i for i in ids if '_FailedTest' in i], 'a content module failed to load')
        names = {shards.name_of(t) for t in tests}
        for key, k in shards.CONTENT.items():
            self.assertTrue(key in ids or key in names,
                            f'{key} (content shard {k}) is not a test or a test class: update tests/shards.py')
            self.assertTrue(0 < k < shards.CONTENT_SHARDS)
        self.assertEqual({t.__module__ for t in map(type, tests)}, set(shards.CONTENT_MODULES))
        per = [sum(1 for t in tests if shards.content_shard_of(t) == k) for k in range(shards.CONTENT_SHARDS)]
        self.assertEqual(sum(per), len(tests))
        self.assertTrue(all(per), per)
        # the vectors' parts each have a test (tests/test_plant3d.py frozen_parts): a part added to the generator gets
        # a test in shard 0 until it is given a shard
        self.assertIn('test_plant3d.Vectors.test_frozen_train', ids)
        self.assertIn('test_plant3d.Vectors2.test_frozen_day', ids)

    def test_the_workflows_run_every_shard(self):
        text, m = matrix('tests.yml', 'shard')
        self.assertEqual(m, [[str(k) for k in range(shards.SHARDS)]])
        self.assertIn('tests/shards.py ${{ matrix.shard }}', text)
        text, m = matrix('plant3d-app.yml', 'shard')
        self.assertEqual(m, [[str(k) for k in range(shards.CONTENT_SHARDS)]])
        self.assertIn('tests/shards.py content ${{ matrix.shard }}', text)
        content = text[text.index('\n  content:\n'):text.index('\n  plant3d:\n')]
        self.assertNotIn('-m unittest', content, 'the content tests run in their shards alone')


if __name__ == '__main__':
    unittest.main()
