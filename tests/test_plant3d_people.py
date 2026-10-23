"""Walkdown Plant's people (milestone A1, decision 0063): the committed KayKit files are the pinned archive's (each
file's SHA-256 in apps/plant3d/people/kaykit/SOURCE.json), CC0 by the licence file that came with them, nothing else
lies beside them unpinned, and the About list names them."""
import hashlib
import json
import os
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
KAYKIT = os.path.join(REPO, 'apps', 'plant3d', 'people', 'kaykit')


def source():
    with open(os.path.join(KAYKIT, 'SOURCE.json'), encoding='utf-8') as f:
        return json.load(f)


class KayKitFiles(unittest.TestCase):
    def test_checksums(self):
        s = source()
        self.assertRegex(s['archive_sha256'], r'^[0-9a-f]{64}$')
        self.assertEqual(s['version'], '1.1')
        for f in s['files']:
            with open(os.path.join(KAYKIT, f['file']), 'rb') as fh:
                self.assertEqual(hashlib.sha256(fh.read()).hexdigest(), f['sha256'], f['file'])
            self.assertTrue(f['member'].endswith(f['file']), f)

    def test_nothing_unpinned(self):
        pinned = {f['file'] for f in source()['files']} | {'SOURCE.json', '.gdignore'}
        self.assertEqual(set(os.listdir(KAYKIT)) - pinned, set())

    def test_licence_is_cc0(self):
        s = source()
        self.assertEqual(s['license'], 'CC0-1.0')
        with open(os.path.join(KAYKIT, 'License.txt'), encoding='utf-8') as f:
            text = f.read()
        self.assertIn('Creative Commons Zero, CC0', text)
        self.assertIn('creativecommons.org/publicdomain/zero/1.0', text)
        self.assertIn('Character Animations (1.1)', text)

    def test_about_lists_them(self):
        with open(os.path.join(REPO, 'apps', 'plant3d', 'about.json'), encoding='utf-8') as f:
            about = json.load(f)
        a = [x for x in about['assets'] if x['id'] == 'kaykit-character-animations']
        self.assertEqual(len(a), 1)
        self.assertEqual(a[0]['license'], 'CC0-1.0')
        self.assertIn('people/kaykit/SOURCE.json', a[0]['pinned_by'])
        self.assertEqual(a[0]['url'], source()['page'])

    def test_not_imported_by_godot(self):
        # read by the build (GLTFDocument), never imported into the project nor exported in the packages
        self.assertTrue(os.path.exists(os.path.join(KAYKIT, '.gdignore')))


if __name__ == '__main__':
    unittest.main()
