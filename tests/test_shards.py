"""CI runs the Python tests in shards (tests/shards.py): each class it gives a shard of its own exists, and the shards
together are every test discovered, each once."""
import os, sys, unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shards  # noqa: E402


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


if __name__ == '__main__':
    unittest.main()
