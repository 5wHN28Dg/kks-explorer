"""The web pages carry no inline script (#18, #8): no <script> with a body, no on* handler attribute, no javascript:
URL. The Content-Security-Policy (script-src 'self', platform/linux/src/kksl/server.nim) would block any of them, so
one would show up as a broken page; this finds it before a browser does.
  .venv/bin/python -m unittest tests.test_web_inline"""
import glob, os, unittest
from html.parser import HTMLParser

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


class Inline(HTMLParser):
    def __init__(self):
        super().__init__()
        self.found, self.in_script = [], False

    def handle_starttag(self, tag, attrs):
        for k, v in attrs:
            if k.lower().startswith('on'):
                self.found.append(f'line {self.getpos()[0]}: <{tag} {k}=…>')
            if v and v.strip().lower().startswith('javascript:'):
                self.found.append(f'line {self.getpos()[0]}: <{tag} {k}="javascript:…">')
        if tag == 'script':
            self.in_script = True
            if not dict(attrs).get('src'):
                self.found.append(f'line {self.getpos()[0]}: <script> without src')

    def handle_endtag(self, tag):
        if tag == 'script':
            self.in_script = False

    def handle_data(self, data):
        if self.in_script and data.strip():
            self.found.append(f'line {self.getpos()[0]}: script body')


def inline_in(src):
    p = Inline()
    p.feed(src)
    p.close()
    return p.found


class NoInlineScript(unittest.TestCase):
    def test_pages(self):
        pages = sorted(glob.glob(os.path.join(REPO, '*.html')))
        self.assertIn(os.path.join(REPO, 'index.html'), pages)
        for f in pages:
            with open(f, encoding='utf-8') as fh:
                self.assertEqual(inline_in(fh.read()), [], os.path.basename(f))

    def test_finds_them(self):
        """the checker itself finds each kind"""
        self.assertEqual(len(inline_in('<button onclick="x()">a</button>')), 1)
        self.assertEqual(len(inline_in('<a href=" javascript:x()">a</a>')), 1)
        self.assertEqual(len(inline_in('<script>x()</script>')), 2)
        self.assertEqual(inline_in('<script src="a.js"></script><button>a</button>'), [])


if __name__ == '__main__':
    unittest.main()
