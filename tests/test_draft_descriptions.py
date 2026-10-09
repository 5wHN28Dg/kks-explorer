"""tools/draft_descriptions.py on a small synthetic plant (no plant data): what each draft says and rests on."""
import json, os, shutil, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import draft_descriptions as dd  # noqa: E402

REPO = os.path.join(os.path.dirname(__file__), '..')


class Drafts(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='kks-desc-')
        json.dump([{'id': 'a', 'name': 'Sheet A'}], open(os.path.join(self.d, 'sheets.json'), 'w'))
        json.dump([
            {'id': 'a:1', 'sheet': 'a', 'kks': '11LAB70AA501', 'suffix': '', 'isa': None, 'bbox': [100, 100, 140, 120]},
            {'id': 'a:2', 'sheet': 'a', 'kks': '11LAB70CP101', 'suffix': '', 'isa': 'PIA', 'bbox': [160, 100, 200, 120]},
            {'id': 'a:3', 'sheet': 'a', 'kks': '11HAD70CT101', 'suffix': 'R', 'isa': 'TIAC', 'bbox': [3000, 100, 3040, 120]},
            {'id': 'a:4', 'sheet': 'a', 'kks': '11LAB70', 'suffix': '', 'isa': None, 'bbox': [5000, 100, 5040, 120]},
            {'id': 'a:5', 'sheet': 'a', 'kks': None, 'suffix': '', 'isa': None, 'bbox': [6000, 100, 6040, 120]}],
            open(os.path.join(self.d, 'tags.json'), 'w'))
        json.dump({'entries': [{'kks': 'LAB70AA501', 'desc': 'feed control valve'}]}, open(os.path.join(self.d, 'locations.json'), 'w'))

    def tearDown(self):
        shutil.rmtree(self.d)

    def run_tool(self, *extra):
        dd.main([self.d, '--kks', os.path.join(REPO, 'data', 'kks.json'), *extra])
        return json.load(open(os.path.join(self.d, 'descriptions.json')))

    def test_drafts(self):
        d = self.run_tool()
        self.assertEqual(sorted(d), ['11HAD70CT101R', '11LAB70AA501', '11LAB70CP101'])   # unread and partial codes: none
        v = d['11LAB70AA501']
        self.assertIn('is a valve', v['text']); self.assertIn('the Feed water piping system', v['text'])   # kks.json's name
        self.assertIn('"feed control valve"', v['text']); self.assertIn('next to 11LAB70CP101', v['text'])
        self.assertIn('location list', v['basis']); self.assertIn('drawing neighbours', v['basis'])
        t = d['11HAD70CT101R']
        self.assertIn('measures temperature and is indicated, alarmed and used for control', t['text'])
        self.assertNotIn('next to', t['text'])          # nothing within reach on the sheet
        self.assertIn('instrument letters', t['basis'])

    def test_keep_leaves_existing_drafts(self):
        json.dump({'11LAB70AA501': {'text': 'hand edit', 'basis': 'a person'}}, open(os.path.join(self.d, 'descriptions.json'), 'w'))
        d = self.run_tool('--keep')
        self.assertEqual(d['11LAB70AA501']['text'], 'hand edit')
        self.assertIn('11LAB70CP101', d)

    def test_state_added_tags_and_reviews(self):
        # as the apps see it: a tag marked as missed gets a draft; a corrected reading gets it under the corrected
        # code (not the misread one); a rejected reading gets none
        st = os.path.join(self.d, 'state.json')
        json.dump({'added_tags': [{'id': 'm1', 'sheet': 'a', 'kks': '11LAB70AA502', 'suffix': '', 'bbox': [120, 130, 150, 150]}],
                   'reviews': {'a:2': {'status': 'confirmed', 'kks': '11LAB71CP101', 'suffix': '', 'isa': 'PI'},
                               'a:3': {'status': 'rejected'}}}, open(st, 'w'))
        d = self.run_tool('--state', st)
        self.assertEqual(sorted(d), ['11LAB70AA501', '11LAB70AA502', '11LAB71CP101'])

    def test_location_list_as_a_plain_array(self):
        # the core reads either {"entries": [...]} or a bare array
        json.dump([{'kks': 'LAB70AA501', 'desc': 'feed control valve'}], open(os.path.join(self.d, 'locations.json'), 'w'))
        self.assertIn('"feed control valve"', self.run_tool()['11LAB70AA501']['text'])

    def write_tags(self, tags):
        json.dump(tags, open(os.path.join(self.d, 'tags.json'), 'w'))

    def test_letters_kind_and_wording(self):
        self.write_tags([
            {'id': '1', 'sheet': 'a', 'kks': '11LAB70CP001', 'isa': 'TDIT', 'bbox': [0, 0, 10, 10]},       # disagree
            {'id': '2', 'sheet': 'a', 'kks': '11LAB70CT002', 'isa': 'TDIT', 'bbox': [900, 0, 910, 10]},    # a difference
            {'id': '3', 'sheet': 'a', 'kks': '11LAB70CT003', 'isa': 'TE', 'bbox': [1800, 0, 1810, 10]},    # the element
            {'id': '4', 'sheet': 'a', 'kks': '11LAB70AA004', 'isa': 'TE', 'bbox': [2700, 0, 2710, 10]},    # a valve
            {'id': '5', 'sheet': 'a', 'kks': '11LAB70AT005', 'bbox': [2750, 0, 2760, 10]}])
        d = self.run_tool()
        self.assertIn("don't match its code's kind", d['11LAB70CP001']['text'])
        self.assertNotIn('measures temperature', d['11LAB70CP001']['text'])
        self.assertIn('measures temperature difference and is indicated and transmitted', d['11LAB70CT002']['text'])
        self.assertIn('measures temperature. It is the sensing element.', d['11LAB70CT003']['text'])
        self.assertNotIn('instrument letters', d['11LAB70AA004']['text'])
        self.assertIn('next to 11LAB70AT005 (filter or separator).', d['11LAB70AA004']['text'])

    def test_unchecked_readings_odd_input_and_length(self):
        self.write_tags([
            {'id': '1', 'sheet': 'a', 'kks': '11LAB70AA001', 'status': 'review', 'bbox': [0, 0, 10, 10]},   # unchecked
            {'id': '2', 'sheet': 'a', 'kks': '11LAB70AA002', 'suffix': 5},                                 # no box
            {'id': '3', 'kks': '11LAB70AA003', 'bbox': [0, 0, 10, 10]},                                      # no sheet
            {'id': '4', 'sheet': 'a', 'kks': '11LAB70AA501', 'bbox': [0, 0, 10, 10]}])
        json.dump([{'id': 'a', 'name': 'H\ud800P'}], open(os.path.join(self.d, 'sheets.json'), 'w'))
        json.dump({'entries': [{'kks': 'LAB70AA501', 'desc': 'x' * 2500}]}, open(os.path.join(self.d, 'locations.json'), 'w'))
        d = self.run_tool()
        self.assertEqual(sorted(d), ['11LAB70AA0025', '11LAB70AA501'])
        self.assertLessEqual(len(d['11LAB70AA501']['text']), dd.MAX_TEXT)
        self.assertTrue(d['11LAB70AA501']['text'].endswith('.'))   # whole sentences only
        raw = open(os.path.join(self.d, 'descriptions.json'), encoding='utf-8').read()
        raw.encode('utf-8')   # no lone surrogate left
        self.assertFalse(os.path.exists(os.path.join(self.d, 'descriptions.json.tmp')))

    def test_keep_drops_codes_no_longer_drawn(self):
        json.dump({'11LAB70AA501': {'text': 'hand edit', 'basis': 'a person'}, '11XYZ99AA999': {'text': 'old', 'basis': 'x'}},
                  open(os.path.join(self.d, 'descriptions.json'), 'w'))
        d = self.run_tool('--keep')
        self.assertEqual(d['11LAB70AA501']['text'], 'hand edit')
        self.assertNotIn('11XYZ99AA999', d)


if __name__ == '__main__':
    unittest.main()
