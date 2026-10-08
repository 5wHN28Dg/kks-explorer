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
        self.assertIn('is a valve', v['text']); self.assertIn('feedwater piping', v['text'])
        self.assertIn('"feed control valve"', v['text']); self.assertIn('next to 11LAB70CP101', v['text'])
        self.assertIn('location list', v['basis']); self.assertIn('drawing neighbours', v['basis'])
        t = d['11HAD70CT101R']
        self.assertIn('temperature, indicated, alarmed and used for control', t['text'])
        self.assertNotIn('next to', t['text'])          # nothing within reach on the sheet
        self.assertIn('instrument letters', t['basis'])

    def test_keep_leaves_existing_drafts(self):
        json.dump({'11LAB70AA501': {'text': 'hand edit', 'basis': 'a person'}}, open(os.path.join(self.d, 'descriptions.json'), 'w'))
        d = self.run_tool('--keep')
        self.assertEqual(d['11LAB70AA501']['text'], 'hand edit')
        self.assertIn('11LAB70CP101', d)


if __name__ == '__main__':
    unittest.main()
