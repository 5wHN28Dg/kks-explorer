"""#371: the clients say errors in the same words (X1): the sentence table and the terse texts' sentences in the web's
common.js, the desktop apps' errwords.nim and Android's Errors.kt hold the same entries, word for word.
  .venv/bin/python -m unittest tests.test_error_words"""
import os, re, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def read(p):
    with open(os.path.join(REPO, p), encoding='utf-8') as f:
        return f.read()


def block(src, start, end):
    i = src.index(start)
    return src[i:src.index(end, i)]


def pairs(text):
    """("key", "sentence") or 'key': "sentence" pairs, in any of the three languages' quoting"""
    q = r'''(?:"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)')'''
    out = {}
    for m in re.finditer(r'(?:' + q + r'|\b([a-z_]+))\s*(?:,|:|to)\s*' + q, text):
        k = next(g for g in m.groups()[:3] if g is not None)
        v = m.group(4) if m.group(4) is not None else m.group(5)
        out[k.replace('\\', '')] = v.replace('\\', '')
    return out


class ErrorWords(unittest.TestCase):
    def test_same_words(self):
        js, nim, kt = read('common.js'), read('apps/common/errwords.nim'), read('android/app2/src/main/kotlin/kks/explorer/ui/Errors.kt')
        words = [pairs(block(js, 'K.errorWords = {', '};')), pairs(block(nim, 'const ErrorWords*', ']')),
                 pairs(block(kt, 'val words = mapOf(', ')\n'))]
        terse = [pairs(block(js, 'K.errorTerse = {', '};')), pairs(block(nim, 'const ErrorTerse*', ']')),
                 pairs(block(kt, 'val terse = mapOf(', ')\n'))]
        self.assertEqual(len(words[0]), 9, words[0])
        self.assertEqual(words[0], words[1])
        self.assertEqual(words[0], words[2])
        self.assertEqual(len(terse[0]), 3, terse[0])
        self.assertEqual(terse[0], terse[1])
        self.assertEqual(terse[0], terse[2])
        for s in list(words[0].values()) + list(terse[0].values()):
            self.assertRegex(s, r'^[A-Z].*[.]$')
        # the join's own sentences, desktop and Android
        for name_nim, name_kt in (('LostJoin', 'LOST_JOIN'), ('FirstSyncFailed', 'FIRST_SYNC_FAILED')):
            a = re.search(name_nim + r'\* = "([^"]*)"', nim).group(1)
            b = re.search(name_kt + r' = "([^"]*)"', kt).group(1)
            self.assertEqual(a, b, name_nim)


if __name__ == '__main__':
    unittest.main()
