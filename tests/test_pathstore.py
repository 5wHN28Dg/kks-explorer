"""The .kkp path store (docs/PATHSTORE.md) against ref/vectors/pathstore-v1.json, using the test-only reference in
ref/pathstore.py. The Nim reader and the Nim importer must pass the same file."""
import json, os, sys, unittest, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from ref import make_pathstore_vectors as G, pathstore as K


def model(doc):
    return {'width': doc['width'], 'height': doc['height'], 'grid': list(doc['grid']),
            'styles': [{'kind': k, 'cap': c, 'join': j, 'width': w, 'stroke': list(s), 'fill': list(f)}
                       for k, c, j, w, s, f in doc['styles']],
            'paths': [{'style': p['style'], 'bbox': list(p['bbox']), 'cmds': [list(c) for c in p['cmds']]} for p in doc['paths']],
            'images': [{'after': i['after'], 'rect': list(i['rect']), 'data_hex': i['data'].hex()} for i in doc['images']]}


class PathStore(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(G.OUT, encoding='utf-8') as f:
            cls.V = json.load(f)

    def test_file_is_frozen(self):
        with open(G.OUT, encoding='utf-8') as f:
            self.assertEqual(f.read(), G.dump(G.build()))

    def test_decode_both_forms(self):
        for c in self.V['valid']:
            for key in ('file_hex', 'file_deflated_hex'):
                doc = K.decode(bytes.fromhex(c[key]))
                self.assertEqual(model(doc), c['model'], c['why'])
                self.assertEqual(doc['cells'], c['cells'], c['why'])

    def test_encode_is_canonical(self):
        for c in self.V['valid']:
            m = c['model']
            styles = [(s['kind'], s['cap'], s['join'], s['width'], tuple(s['stroke']), tuple(s['fill'])) for s in m['styles']]
            paths = [{'style': p['style'], 'bbox': tuple(p['bbox']), 'cmds': [tuple(x) for x in p['cmds']]} for p in m['paths']]
            images = [{'after': i['after'], 'rect': tuple(i['rect']), 'data': bytes.fromhex(i['data_hex'])} for i in m['images']]
            raw = K.encode(m['width'], m['height'], styles, paths, images, grid=tuple(m['grid']), compress=False)
            self.assertEqual(raw.hex(), c['file_hex'], c['why'])
            self.assertEqual(model(K.decode(K.encode(m['width'], m['height'], styles, paths, images,
                                                     grid=tuple(m['grid'])))), m, 'level-9 zlib round trip')

    def test_rejects(self):
        for r in self.V['reject']:
            with self.assertRaises(K.FormatError, msg=r['why']):
                K.decode(bytes.fromhex(r['file_hex']))

    def test_grid_rules(self):
        for g in self.V['choose_grid']:
            self.assertEqual(list(K.choose_grid(g['width'], g['height'])), g['grid'])
        for c in self.V['cell_range']:
            self.assertEqual(list(K.cell_range(c['v0'], c['v1'], c['size'], c['n'])), c['cells'])

    def test_zlib_bomb_is_refused(self):
        body = b'\x00' * (K.MAX_BYTES + 10)
        bomb = b'KKP1' + (1).to_bytes(2, 'little') + (1).to_bytes(2, 'little') + zlib.compress(body, 9)
        with self.assertRaises(K.FormatError):
            K.decode(bomb)


if __name__ == '__main__':
    unittest.main()
