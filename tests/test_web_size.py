"""tools/web_size.py: the web client's download size against the committed baseline."""
import io, json, os, shutil, sys, tempfile, unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import web_size  # noqa: E402


def quiet(argv):
    with redirect_stdout(io.StringIO()) as out:
        code = web_size.main(argv)
    return code, out.getvalue()


class WebSize(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix='kks-websize-')
        os.makedirs(os.path.join(self.d, 'vendor', 'kks'))
        os.makedirs(os.path.join(self.d, 'vendor', 'fonts'))
        self.write('sw.js', "const SHELL_FILES = ['/', '/index.html', '/common.js', '/vendor/kks/kks-simd-dec.wasm'];\n")
        self.write('index.html', 'x' * 100)
        self.write('common.js', 'y' * 50)
        self.write('vendor/kks/kks-simd-dec.wasm', 'w' * 30)
        self.write('vendor/kks/kks.wasm', 'e' * 70)
        self.write('vendor/fonts/a.woff2', 'f' * 20)
        self.write('vendor/fonts/README.md', 'not shipped')

    def tearDown(self):
        shutil.rmtree(self.d)

    def write(self, p, s):
        with open(os.path.join(self.d, p), 'w') as f:
            f.write(s)

    def test_groups(self):
        m = web_size.measure(self.d)
        self.assertEqual(sorted(m['shell']['files']), ['common.js', 'index.html', 'sw.js', 'vendor/kks/kks-simd-dec.wasm'])
        self.assertEqual(sorted(m['on demand']['files']), ['vendor/fonts/a.woff2', 'vendor/kks/kks.wasm'])
        self.assertEqual(m['on demand']['total'], 90)

    def test_unchanged_passes_and_growth_fails(self):
        self.assertEqual(quiet(['--repo', self.d, '--update'])[0], 0)
        self.assertEqual(quiet(['--repo', self.d])[0], 0)
        self.write('common.js', 'y' * 51)
        code, out = quiet(['--repo', self.d])
        self.assertEqual(code, 1)
        self.assertIn('common.js', out)
        self.assertIn('+1', out)

    def test_shrinking_also_needs_the_baseline(self):
        quiet(['--repo', self.d, '--update'])
        self.write('index.html', 'x' * 10)
        self.assertEqual(quiet(['--repo', self.d])[0], 1)

    def test_a_new_shell_file_is_counted(self):
        quiet(['--repo', self.d, '--update'])
        self.write('tiles.js', 't' * 5)
        self.write('sw.js', "const SHELL_FILES = ['/', '/index.html', '/common.js', '/tiles.js', '/vendor/kks/kks-simd-dec.wasm'];\n")
        code, out = quiet(['--repo', self.d])
        self.assertEqual(code, 1)
        self.assertIn('tiles.js', out)

    def test_a_listed_file_that_is_missing_stops(self):
        os.remove(os.path.join(self.d, 'common.js'))
        with self.assertRaises(SystemExit):
            web_size.measure(self.d)

    def test_the_repository_matches_its_baseline(self):
        repo = os.path.join(os.path.dirname(__file__), '..')
        base = json.load(open(os.path.join(repo, 'web-size.json')))
        self.assertEqual(web_size.diff(base, web_size.measure(repo)), [],
                         'web-size.json is out of date: python3 tools/web_size.py --update')


if __name__ == '__main__':
    unittest.main()
