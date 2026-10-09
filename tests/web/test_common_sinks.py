"""common.js's builders with hostile values (findings #16, #7), in Chromium, Firefox and WebKit: a value from the
local API or the plant must come out as text, never as markup, and no script of it may run. Also K.h's refusals and
K.safeUrl (WEB-10: javascript: and data: URLs are rejected).
  .venv/bin/python tests/web/test_common_sinks.py"""
import os, unittest
from playwright.sync_api import sync_playwright

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
# markup that would add an element and run script if it were parsed: an <img> with onerror, a closed attribute and a
# <script>, quotes of both kinds
EVIL = '<img src=x onerror="window.pwned=1"><b id=injected>x</b>"><script>window.pwned=2</script>\'"'
# all three, or the one a CI job installed ($KKS_ENGINE)
ENGINES = tuple(os.environ['KKS_ENGINE'].split(',')) if os.environ.get('KKS_ENGINE') else ('chromium', 'firefox', 'webkit')
ORIGIN = 'http://kks.test'   # a page with an http origin (K.safeUrl resolves relative URLs against it)


class Sinks(unittest.TestCase):
    def page(self, p, name):
        b = getattr(p, name).launch()
        pg = b.new_page()
        pg.route(ORIGIN + '/**', lambda r: r.fulfill(status=200, content_type='text/html',
                                                     body='<!doctype html><html><body><span id="syncStatus"></span></body></html>'))
        pg.goto(ORIGIN + '/page')
        pg.add_script_tag(path=os.path.join(REPO, 'common.js'))
        pg.evaluate('window.pwned = 0')
        return b, pg

    def clean(self, pg, where):
        """nothing of EVIL became an element, and none of its script ran"""
        pg.wait_for_timeout(300)   # (an <img onerror> fires once the image has failed to load)
        self.assertIsNone(pg.query_selector('#injected'), where)
        self.assertFalse(pg.evaluate("[...document.scripts].some(s => s.textContent.includes('pwned'))"), where)
        self.assertEqual(pg.evaluate('window.pwned'), 0, where)

    def each(self, fn):
        with sync_playwright() as p:
            for name in ENGINES:
                with self.subTest(engine=name):
                    b, pg = self.page(p, name)
                    try:
                        fn(pg)
                    finally:
                        b.close()

    def test_join_code(self):
        """#16: the join code from /api/node/join-invite went into innerHTML unescaped"""
        def run(pg):
            pg.evaluate("""(evil) => {
              K.api = async (path, body) => body ? {} : {state: 'confirm', code: '123' + evil};
              K.joinWait({plant_name: evil});
            }""", EVIL)
            pg.wait_for_function("document.querySelector('#kov .code') && document.querySelector('#kov .code').style.display === ''")
            self.clean(pg, 'joinWait')
            self.assertIn('123 ' + EVIL[:5], pg.inner_text('#kov .code b'))
            self.assertEqual(pg.text_content('#kov h1'), 'Joining ' + EVIL)
        self.each(run)

    def test_h(self):
        """K.h: strings become text nodes, handlers are functions only, URL attributes and code elements are refused"""
        def run(pg):
            r = pg.evaluate("""(evil) => {
              const out = {};
              const el = K.h('div', {class: 'c', title: evil, 'data-x': evil, hidden: false, 'aria-label': null},
                                 evil, 0, null, undefined, false, [evil, [K.h('i', null, evil)]]);
              document.body.append(el);
              out.html = el.childNodes.length; out.text = el.textContent; out.title = el.getAttribute('title');
              out.hasHidden = el.hasAttribute('hidden'); out.hasLabel = el.hasAttribute('aria-label');
              let clicked = 0; const b = K.h('button', {onclick: () => clicked++}, 'go'); b.click(); out.clicked = clicked; out.nullHandler = K.h('button', {onclick: null}, 'x').localName;
              out.bool = K.h('input', {readonly: true}).hasAttribute('readonly');
              const refused = [];
              const tries = {
                onclickString: () => K.h('button', {onclick: 'window.pwned=3'}),
                href: () => K.h('a', {href: 'javascript:window.pwned=4'}),
                HREF: () => K.h('a', {HREF: 'javascript:window.pwned=4'}),
                formaction: () => K.h('button', {formaction: 'javascript:window.pwned=4'}),
                action: () => K.h('form', {action: 'javascript:window.pwned=4'}),
                srcdoc: () => K.h('div', {srcdoc: evil}),
                iframeSrc: () => K.h('iframe', {}),
                script: () => K.h('script', null, 'window.pwned=5'),
                scriptSrc: () => K.h('div', {src: 'x.js'}),
                object: () => K.h('object', {}),
                svgUse: () => K.svg('use', {}),
                svgHref: () => K.svg('a', {'xlink:href': 'javascript:window.pwned=4'}),
              };
              for (const [k, f] of Object.entries(tries)) { try { f(); } catch (e) { if (e instanceof TypeError) refused.push(k) } }
              out.refused = refused;
              const img = K.h('img', {src: 'data:image/gif;base64,R0lGODlhAQABAAAAACw=', alt: evil});
              out.imgSrc = img.getAttribute('src').slice(0, 10); out.imgAlt = img.alt;
              const svg = K.svg('svg', {viewBox: '0 0 2 2'}, K.svg('path', {d: 'M0,0h1v1h-1z'}));
              out.svgNs = svg.namespaceURI; out.viewBox = svg.getAttribute('viewBox'); out.pathNs = svg.firstChild.namespaceURI;
              return out;
            }""", EVIL)
            self.clean(pg, 'K.h')
            self.assertEqual(r['text'], EVIL + '0' + EVIL + EVIL)
            self.assertEqual(r['title'], EVIL)
            self.assertFalse(r['hasHidden'])
            self.assertFalse(r['hasLabel'])
            self.assertEqual(r['clicked'], 1)
            self.assertEqual(r['nullHandler'], 'button')   # an absent handler is skipped, like any absent attribute
            self.assertTrue(r['bool'])
            self.assertEqual(r['refused'], ['onclickString', 'href', 'HREF', 'formaction', 'action', 'srcdoc', 'iframeSrc',
                                            'script', 'scriptSrc', 'object', 'svgUse', 'svgHref'])
            self.assertEqual(r['imgSrc'], 'data:image')
            self.assertEqual(r['imgAlt'], EVIL)
            self.assertEqual(r['svgNs'], 'http://www.w3.org/2000/svg')
            self.assertEqual(r['pathNs'], 'http://www.w3.org/2000/svg')
            self.assertEqual(r['viewBox'], '0 0 2 2')
        self.each(run)

    def test_safe_url(self):
        """K.safeUrl (WEB-10): only http and https; javascript: and data: in any spelling become about:blank"""
        def run(pg):
            got = pg.evaluate("""() => [
              'javascript:window.pwned=6', 'JavaScript:window.pwned=6', ' javascript:window.pwned=6', 'java\\tscript:window.pwned=6',
              '\\u0000javascript:window.pwned=6', 'data:text/html,<script>window.pwned=7</script>', 'DATA:text/html;base64,PHNjcmlwdD4=',
              'vbscript:x', 'blob:http://kks.test/1', 'file:///etc/passwd', 'http://[', null,
              'https://github.com/x/releases/tag/v1', 'http://192.168.1.20:8420/', '/?sheet=a%20b', '/course.html?c=ppt', 'admin.html#queue',
            ].map(u => K.safeUrl(u))""")
            self.assertEqual(got[:12], ['about:blank'] * 12)
            self.assertEqual(got[12:], ['https://github.com/x/releases/tag/v1', 'http://192.168.1.20:8420/', '/?sheet=a%20b',
                                        '/course.html?c=ppt', 'admin.html#queue'])
            # a link built with it does not run anything when followed
            pg.evaluate("""() => { const a = K.h('a', {id: 'lnk'}, 'x'); a.href = K.safeUrl('javascript:window.pwned=8'); document.body.append(a) }""")
            self.assertEqual(pg.get_attribute('#lnk', 'href'), 'about:blank')
            self.clean(pg, 'safeUrl')
        self.each(run)

    def test_form_and_box(self):
        """K.form (title, text, labels, a read-only value, the button) and K.box"""
        def run(pg):
            pg.evaluate("""(evil) => { window.sent = null;
              K.form(evil, evil, [{name: 'u', label: evil, value: evil}, {name: 'p', label: evil, optional: true}], evil, v => { window.sent = v }, () => { window.back = 1 }) }""", EVIL)
            self.clean(pg, 'K.form')
            self.assertEqual(pg.text_content('#kov h1'), EVIL)
            self.assertEqual(pg.text_content('#kov p'), EVIL)
            self.assertEqual(pg.get_attribute('#kov input[name=u]', 'placeholder'), EVIL)
            self.assertEqual(pg.input_value('#kov input[name=u]'), EVIL)
            self.assertIsNotNone(pg.get_attribute('#kov input[name=u]', 'readonly'))
            self.assertIsNotNone(pg.get_attribute('#kov input[name=u]', 'required'))
            self.assertIsNone(pg.get_attribute('#kov input[name=p]', 'required'))
            self.assertEqual(pg.text_content('#kov form > button:not(.back)'), EVIL)
            # keyboard: the focus starts in the first field that can be typed into; Tab to the submit button, Enter sends
            self.assertEqual(pg.evaluate('document.activeElement.name'), 'p')
            pg.keyboard.type('typed')
            pg.keyboard.press('Tab')
            self.assertEqual(pg.evaluate('document.activeElement.textContent'), EVIL)
            pg.keyboard.press('Enter')
            pg.wait_for_function('window.sent')
            self.assertEqual(pg.evaluate('window.sent'), {'u': EVIL, 'p': 'typed'})
            pg.keyboard.press('Escape')
            self.assertEqual(pg.evaluate('window.back'), 1)
            pg.evaluate("(evil) => K.box(evil, evil, evil, () => { window.boxed = 1 })", EVIL)
            self.clean(pg, 'K.box')
            self.assertEqual(pg.text_content('#kov .box h1'), EVIL)
            self.assertEqual(pg.text_content('#kov .box p'), EVIL)
            pg.click('#kov .box button')
            self.assertEqual(pg.evaluate('window.boxed'), 1)
        self.each(run)

    def test_join_screens(self):
        """the join screen (who removed the device, a note, the device id) and the list of admins on the Wi-Fi"""
        def run(pg):
            pg.evaluate("""(evil) => K.joinScreen({app: false, node: {removed: {plant: evil, by: evil}, has_plant: false, device: evil}}, evil)""", EVIL)
            self.clean(pg, 'joinScreen')
            self.assertIn(f'removed from {EVIL} by {EVIL}.', pg.text_content('#kov .box .err'))
            self.assertEqual(pg.text_content('#kov .box div.err >> nth=1'), EVIL)
            self.assertEqual(pg.text_content('#kov .box p >> nth=-1'), 'Device ' + EVIL[:12] + '…')
            self.assertEqual(pg.locator('#kov .box button[data-a]').count(), 6)
            pg.evaluate("""(evil) => { K.api = async () => ({devices: [{plant: evil, label: evil, host: 'h'}], discovery: evil});
              K.pickNearby({}, {}) }""", EVIL)
            pg.wait_for_selector('#kov .list button[data-i="0"]')
            self.clean(pg, 'pickNearby')
            self.assertEqual(pg.text_content('#kov .list button'), f'{EVIL} — {EVIL}')
            pg.evaluate("""(evil) => { K.api = async () => ({devices: [], discovery: evil}) }""", EVIL)
            pg.wait_for_selector('#kov .list p', timeout=5000)
            self.clean(pg, 'pickNearby (none)')
            self.assertIn(f'(finding devices: {EVIL}).', pg.text_content('#kov .list p'))
        self.each(run)

    def test_status_progress_ask(self):
        """the status line (peer, signed out, online), the progress bar and the question box"""
        def run(pg):
            pg.evaluate("""() => { K.cfg = {mode: 'peer'}; K.syncStatus = {reachable: 2, last_sync: 0, internet: true}; K.renderStatus() }""")
            self.assertEqual(pg.text_content('#syncStatus'), '● 2 devices reachable · synced never · Internet ✓')
            pg.evaluate("""() => { K.cfg = {}; K.reauth = true; K.outbox = [1, 2]; K.renderStatus() }""")
            self.assertEqual(pg.text_content('#syncStatus'), '● Sign in again · 2 queued')
            self.assertEqual(pg.get_attribute('#syncStatus a', 'href'), '/page')
            pg.evaluate("""() => { K.reauth = false; K.online = false; K.outbox = []; K.renderStatus() }""")
            self.assertEqual(pg.text_content('#syncStatus'), '● Offline')
            pg.evaluate("(evil) => { window.bar = K.progress(evil, 1000) }", EVIL)
            self.clean(pg, 'K.progress')
            self.assertIn(EVIL, pg.text_content('body'))
            pg.evaluate("window.bar.done()")
            pg.evaluate("(evil) => { window.asked = K.ask(evil, evil, true, evil).then(v => window.answer = v) }", EVIL)
            self.clean(pg, 'K.ask')
            box = "[...document.body.children].pop()"
            self.assertEqual(pg.evaluate(f"{box}.querySelector(':scope > div > div').textContent"), EVIL)
            self.assertEqual(pg.evaluate(f"{box}.querySelectorAll(':scope > div > div')[1].textContent"), EVIL)
            self.assertEqual(pg.text_content('button[data-v="1"]'), EVIL)
            self.assertEqual(pg.evaluate("document.activeElement.className"), 'note')
            pg.keyboard.type(EVIL)
            pg.keyboard.press('Tab')
            pg.keyboard.press('Tab')
            self.assertEqual(pg.evaluate('document.activeElement.dataset.v'), '1')
            pg.keyboard.press('Enter')
            pg.wait_for_function('window.answer')
            self.assertEqual(pg.evaluate('window.answer'), {'note': EVIL.strip()})
            self.clean(pg, 'K.ask answered')
        self.each(run)


if __name__ == '__main__':
    unittest.main()
