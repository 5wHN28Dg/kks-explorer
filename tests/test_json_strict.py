"""Strict JSON reading (PROTOCOL-v2 §1, decision 0029) against ref/vectors/v2-json.json. The Nim core runs the same
file with its own hand-written reader (core/tests/test_json.nim)."""
import json, os, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from ref import make_json_vectors as G, sjson as S


class StrictJson(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.V = json.load(f)

    def test_file_is_frozen(self):
        with open(G.OUT, encoding='utf-8') as f:
            self.assertEqual(f.read(), G.dump(G.build()))

    def test_accept(self):
        for c in self.V['accept']:
            self.assertEqual(S.typed(S.loads(bytes.fromhex(c['hex']))), c['value'], c['why'])

    def test_reject(self):
        for c in self.V['reject']:
            with self.assertRaises(S.StrictError, msg=c['why']):
                S.loads(bytes.fromhex(c['hex']))


if __name__ == '__main__':
    unittest.main()
