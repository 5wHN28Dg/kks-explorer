"""Walkdown Plant's Workshop data files (docs/plant3d/WORKSHOP.md §4, milestone K1a; ref/plant3d_workshop.py): the
committed files pass and are what tools/plant3d/make_content.py makes (test_plant3d's own check), the data-only fixture
kind passes, and each rule refuses what it should (strict JSON, keys, ids of at most 16 characters, lengths, sealing,
fastener joins, sources cited and used, the assembly placing everything once in an order that passes its needs, the
views, the plant's content check refusing a file named for another part).
  .venv/bin/python -m unittest tests.test_plant3d_workshop"""
import copy, json, os, unittest
from ref import plant3d as P
from ref import plant3d_workshop as W
from ref.courses import FormatError

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DATA = os.path.join(REPO, 'data', 'plant3d')
FIXTURE = os.path.join(REPO, 'apps', 'plant3d', 'tests', 'fixtures', 'workshop_gadget.json')


class WorkshopData(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.files = P.load_dir(DATA)
        cls.b = P.check_files(cls.files)
        with open(FIXTURE, 'rb') as f:
            cls.fixture = W.loads(f.read())

    def refused(self, w, code, kit=True):
        with self.assertRaises(FormatError) as cm:
            W.check(w, self.b.kit if kit else None, 'w', parts={'test_gadget'})
        self.assertEqual(cm.exception.code, code, str(cm.exception))
        return str(cm.exception)

    def test_the_transmitter_passes(self):
        w = self.b.workshop['pressure_transmitter']
        self.assertEqual(w['components'], 14)
        self.assertEqual(w['fasteners'], 2)
        for c, d in json.loads(self.files['workshop/pressure_transmitter.json'])['components'].items():
            self.assertLessEqual(len(c), 16, c)
            self.assertTrue(d['sources'], c)

    def test_the_fixture_kind_passes(self):
        s = W.check(self.fixture, None, 'fixture', parts={'test_gadget'})
        self.assertEqual((s['components'], s['fasteners'], s['steps']), (3, 1, 4))
        # without being named as a fixture's kind it is no part
        with self.assertRaises(FormatError) as cm:
            W.check(self.fixture, self.b.kit, 'fixture')
        self.assertEqual(cm.exception.code, 'bad_ref')

    def test_strict_json(self):
        with self.assertRaises(FormatError) as cm:
            W.loads(b'{"format": "walkdown-plant-workshop", "format": 1}')
        self.assertEqual(cm.exception.code, 'bad_json')

    def test_keys_and_format(self):
        w = copy.deepcopy(self.fixture)
        w['torque'] = {}
        self.refused(w, 'unknown_key')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['torque_nm'] = 12     # torque and tools belong to the service file (§4.4)
        self.refused(w, 'unknown_key')
        w = copy.deepcopy(self.fixture)
        w['version'] = 2
        self.refused(w, 'bad_version')
        w = copy.deepcopy(self.fixture)
        del w['components']
        self.refused(w, 'missing_key')

    def test_ids_of_at_most_16(self):
        w = copy.deepcopy(self.fixture)
        w['components']['a_very_long_name_x'] = w['components'].pop('core')     # 18 characters
        self.refused(w, 'bad_id')
        w = copy.deepcopy(self.fixture)
        w['components']['abcdefghijklmnop'] = w['components'].pop('core')       # 16: fine, if nothing refers to core
        w['assembly'] = [s for s in w['assembly'] if s['place'] != 'core']
        w['assembly'][1]['needs'] = [['base', 'a', 'b']]
        w['assembly'].append({'place': 'abcdefghijklmnop', 'text': ['x'], 'sources': ['fixture']})
        W.check(w, None, 'w', parts={'test_gadget'})

    def test_texts_and_sealing(self):
        w = copy.deepcopy(self.fixture)
        w['components']['base']['name'] = 'x' * 61
        self.refused(w, 'bad_type')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['does'] = ''
        self.refused(w, 'bad_type')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sealed'] = True
        self.refused(w, 'missing_key')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sealed_why'] = 'Never opened.'
        self.refused(w, 'unknown_key')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sealed'] = False
        self.refused(w, 'bad_value')

    def test_fasteners(self):
        w = copy.deepcopy(self.fixture)
        w['fasteners']['lid_screws']['joins'] = ['lid']
        self.refused(w, 'bad_length')
        w = copy.deepcopy(self.fixture)
        w['fasteners']['lid_screws']['joins'] = ['lid', 'nothing']
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['fasteners']['base'] = w['fasteners'].pop('lid_screws')
        self.refused(w, 'dup_id')

    def test_sources(self):
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sources'] = []
        self.refused(w, 'bad_length')
        w = copy.deepcopy(self.fixture)
        w['components']['base']['sources'] = ['nowhere']
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['sources'].append({'id': 'spare', 'cite': 'Cited by nothing', 'url': 'https://example.org/spare'})
        self.refused(w, 'unused')
        w = copy.deepcopy(self.fixture)
        w['sources'][0]['url'] = 'http://example.org/'
        self.refused(w, 'bad_link')
        w = copy.deepcopy(self.fixture)
        w['assembly'][0]['sources'] = []
        self.refused(w, 'bad_length')

    def test_assembly(self):
        w = copy.deepcopy(self.fixture)
        w['assembly'] = w['assembly'][:-1]             # the screws never placed
        self.refused(w, 'missing')
        w = copy.deepcopy(self.fixture)
        w['assembly'].append(copy.deepcopy(w['assembly'][0]))
        self.refused(w, 'dup_id')
        w = copy.deepcopy(self.fixture)
        w['assembly'][1], w['assembly'][2] = w['assembly'][2], w['assembly'][1]   # the lid before the core it needs
        self.refused(w, 'bad_order')
        w = copy.deepcopy(self.fixture)
        w['assembly'][2]['needs'][0] = ['ghost', 'a', 'b']
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['assembly'][2]['needs'][0] = ['core', 'only one sentence']
        self.refused(w, 'bad_length')
        w = copy.deepcopy(self.fixture)
        w['assembly'][0]['text'] = 'not a run'
        self.refused(w, 'bad_type')

    def test_views(self):
        w = copy.deepcopy(self.fixture)
        w['views'] = {'xray_all': ['lid'], 'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}], 'keep': ['core']},
                      'run_exploded': {'allowed': ['lid'], 'why': 'Only the lid may be off while it runs.'}}
        W.check(w, None, 'w', parts={'test_gadget'})
        w['views']['cutaway']['planes'][0]['normal'] = [1, 1, 0]
        self.refused(w, 'bad_number')
        w = copy.deepcopy(self.fixture)
        w['views'] = {'xray_all': ['ghost']}
        self.refused(w, 'bad_ref')
        w = copy.deepcopy(self.fixture)
        w['views'] = {'cutaway': {'planes': [{'normal': [1, 0, 0], 'offset': 0}] * 3}}
        self.refused(w, 'bad_length')

    def test_the_content_check_reads_them(self):
        files = dict(self.files)
        files['workshop/pump_horizontal.json'] = files['workshop/pressure_transmitter.json']
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'bad_ref')
        files = dict(self.files)
        w = json.loads(files['workshop/pressure_transmitter.json'])
        w['params'] = {'no_such_param': 1}
        files['workshop/pressure_transmitter.json'] = json.dumps(w).encode()
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'unknown_key')
        files = dict(self.files)
        files['workshop/bench/x.json'] = b'{}'      # bench models come with K3
        with self.assertRaises(FormatError) as cm:
            P.check_files(files)
        self.assertEqual(cm.exception.code, 'unknown_key')


if __name__ == '__main__':
    unittest.main()
