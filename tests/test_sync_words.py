"""The offline state and the changes waiting to be sent (#372) say the same on every client: the desktop apps'
apps/common/syncwords.nim and Android's ui/Status.kt hold the same sentences and the same five minutes."""
import os, re, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def read(*p):
    with open(os.path.join(REPO, *p), encoding='utf-8') as f:
        return f.read()


class SyncWords(unittest.TestCase):
    def test_same_words(self):
        nim = read('apps', 'common', 'syncwords.nim')
        kt = read('android', 'app2', 'src', 'main', 'kotlin', 'kks', 'explorer', 'ui', 'Status.kt')
        for s in ('"1 change waiting to be sent"', ' changes waiting to be sent"', '"Offline"',
                  '"Changes are kept on this device and sent when it reaches another device of the plant."'):
            self.assertIn(s, nim, s)
            self.assertIn(s, kt, s)
        self.assertEqual(re.search(r'OfflineAfter\* = (\d+)', nim).group(1), re.search(r'OFFLINE_AFTER = (\d+)L', kt).group(1))

    def test_switch_name(self):
        # the same switch name on every client (the owner turns it on in one place per client at release)
        for path in (('apps', 'gnome', 'kks_explorer.nim'), ('apps', 'windows', 'kks_explorer.nim'),
                     ('android', 'app2', 'src', 'main', 'kotlin', 'kks', 'explorer', 'ui', 'Root.kt')):
            self.assertIn('"offline-state"', read(*path), path)


if __name__ == '__main__':
    unittest.main()
