"""common.js's HTML sinks with hostile values (findings #16, #7), in Chromium, Firefox and WebKit: a value from the
local API or the plant must come out as text, never as markup.
  .venv/bin/python tests/web/test_common_sinks.py"""
import os, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EVIL = '<img src=x onerror="window.pwned=1"><b id=injected>x</b>'


class Sinks(unittest.TestCase):
    def page(self, p, name):
        b = getattr(p, name).launch()
        pg = b.new_page()
        pg.set_content('<!doctype html><html><body></body></html>')
        pg.add_script_tag(path=os.path.join(REPO, 'common.js'))
        return b, pg

    def test_join_code(self):
        """#16: the join code from /api/node/join-invite went into innerHTML unescaped"""
        with sync_playwright() as p:
            for name in ('chromium', 'firefox', 'webkit'):
                with self.subTest(engine=name):
                    b, pg = self.page(p, name)
                    pg.evaluate("""(evil) => {
                      K.api = async (path, body) => body ? {} : {state: 'confirm', code: '123' + evil};
                      K.joinWait({plant_name: 'P'});
                    }""", EVIL)
                    pg.wait_for_function("document.querySelector('#kov .code') && document.querySelector('#kov .code').style.display === ''")
                    pg.wait_for_timeout(300)
                    self.assertIsNone(pg.query_selector('#injected'))
                    self.assertFalse(pg.evaluate('!!window.pwned'))
                    self.assertIn('123 ' + EVIL[:5], pg.inner_text('#kov .code b'))
                    b.close()


if __name__ == '__main__':
    unittest.main()
