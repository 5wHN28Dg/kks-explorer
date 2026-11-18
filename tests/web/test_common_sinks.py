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
            self.assertIn('123' + EVIL[:5], pg.inner_text('#kov .code b'))
            self.assertEqual(pg.text_content('#kov h1'), 'Joining ' + EVIL)
        self.each(run)

    def test_join_code_copies_whole(self):
        """G14: the join code reads as two groups (123 456) but copies as one (123456): the gap is a margin"""
        def run(pg):
            pg.evaluate("""() => { K.api = async (path, body) => body ? {} : {state: 'confirm', code: '123456'}; K.joinWait({}) }""")
            pg.wait_for_function("document.querySelector('#kov .code') && document.querySelector('#kov .code').style.display === ''")
            got = pg.evaluate("""() => { const b = document.querySelector('#kov .code b'), r = document.createRange();
              r.selectNodeContents(b); getSelection().removeAllRanges(); getSelection().addRange(r);
              const [x, y] = b.children; return [getSelection().toString(), y.getBoundingClientRect().left - x.getBoundingClientRect().right] }""")
            self.assertEqual(got[0], '123456')
            self.assertGreater(got[1], 4)   # still apart on screen
        self.each(run)

    def test_user_text(self):
        """G15: text someone wrote takes its own direction, and a KKS code in Arabic text keeps its characters in order
        (a plain element of the same text splits "11" from "LAB70AA501": the measure below sees that)"""
        NOTE = 'مضخة التغذية 11LAB70AA501 تعمل'
        def run(pg):
            got = pg.evaluate("""(note) => {
              // the code's characters side by side, left to right, in the order they are written?
              const inOrder = (el, code = '11LAB70AA501') => { const xs = [];
                const w = document.createTreeWalker(el, NodeFilter.SHOW_TEXT); let n, all = [];
                while ((n = w.nextNode())) for (let i = 0; i < n.data.length; i++) all.push([n, i]);
                const text = all.map(([n, i]) => n.data[i]).join(''), at = text.indexOf(code);
                for (let j = at; j < at + code.length; j++) { const r = document.createRange(); r.setStart(all[j][0], all[j][1]);
                  r.setEnd(all[j][0], all[j][1] + 1); const q = r.getBoundingClientRect(); xs.push([q.left, q.right]) }
                return xs.every(([l], j) => j === 0 || Math.abs(l - xs[j - 1][1]) <= 2) };   // (WebKit rounds each box out by a pixel)
              const box = K.h('div', {style: 'width:600px;font:16px sans-serif'}); document.body.append(box);
              const plain = K.h('div', null, note), block = K.userText(note, 'div', {class: 'n'}),
                    inline = K.h('div', null, 'Note: ', K.userText(note)), mixed = K.h('div', null, K.userText('Pump مضخة 11LAB70AA501 ok')),
                    spaced = K.userText('مضخة 11 LAB70 AA501 تعمل', 'div');
              box.append(plain, block, inline, mixed, spaced);
              const field = K.h('textarea'), line = K.h('input'), pw = K.h('input', {type: 'password'}), ltr = K.h('input', {dir: 'ltr'});
              field.value = note; line.value = note; box.append(field, line);
              return {plain: inOrder(plain), block: inOrder(block), inline: inOrder(inline), mixed: inOrder(mixed), spaced: inOrder(spaced, '11 LAB70 AA501'),
                      blockDir: block.getAttribute('dir'), blockClass: block.className, blockRtl: block.matches(':dir(rtl)'),
                      text: block.textContent, fields: [field.getAttribute('dir'), line.getAttribute('dir'), pw.getAttribute('dir'), ltr.getAttribute('dir')],
                      fieldRtl: [field.matches(':dir(rtl)'), line.matches(':dir(rtl)')]} }""", NOTE)
            self.assertFalse(got['plain'], 'the measure sees the split in a plain element')
            self.assertTrue(got['block'] and got['inline'] and got['mixed'] and got['spaced'], got)
            self.assertEqual((got['blockDir'], got['blockClass'], got['blockRtl'], got['text']), ('auto', 'n', True, NOTE))
            self.assertEqual(got['fields'], ['auto', 'auto', None, 'ltr'])
            self.assertEqual(got['fieldRtl'], [True, True])
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
        """the status line (peer, signed out, online), the progress bar, the question box and the Undo bar"""
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
            pg.evaluate("(evil) => { window.asked = K.confirm(evil, evil, evil, {note: evil}).then(v => window.answer = v) }", EVIL)
            self.clean(pg, 'K.confirm')
            d = 'dialog.kconfirm'
            self.assertEqual(pg.text_content(d + ' h2'), EVIL)
            self.assertEqual(pg.text_content(d + ' p'), EVIL)
            self.assertEqual(pg.text_content(d + ' .kq-yes'), EVIL)
            self.assertEqual(pg.get_attribute(d + ' input.note', 'placeholder'), EVIL)
            pg.fill(d + ' input.note', EVIL)
            pg.click(d + ' .kq-yes')
            pg.wait_for_function('window.answer')
            self.assertEqual(pg.evaluate('window.answer'), {'note': EVIL.strip()})
            self.clean(pg, 'K.confirm answered')
            pg.evaluate("(evil) => K.undo(evil, () => {})", EVIL)
            self.clean(pg, 'K.undo')
            self.assertIn(EVIL, pg.text_content('#kundo'))
        self.each(run)


    def test_confirm_safe_default(self):
        """#365 (D1, D2 in docs/UI-UX-POLICY.md): a question before a destructive action is the page's own modal dialog,
        not the browser's confirm(): its role and name, the action named on its button and styled as destructive, the
        focus on Cancel (so Enter keeps), Escape keeps, and the focus back where it was"""
        def run(pg):
            pg.evaluate("""() => { const b = document.createElement('button'); b.id = 'opener'; b.textContent = 'Delete';
              document.body.append(b); b.focus(); window.browserAsked = 0; window.confirm = () => { browserAsked++; return true } }""")
            ask = "() => { window.answer = undefined; K.confirm('Delete this photo?', 'It is removed for everyone.', 'Delete photo').then(v => window.answer = v) }"
            pg.evaluate(ask)
            d = pg.locator('dialog.kconfirm')
            self.assertTrue(d.is_visible())
            self.assertEqual(pg.evaluate("document.querySelector('dialog.kconfirm').matches(':modal')"), True)
            self.assertEqual(d.get_attribute('role'), 'alertdialog')
            self.assertEqual(pg.get_by_role('alertdialog', name='Delete this photo?').count(), 1)
            names = pg.evaluate("[...document.querySelectorAll('dialog.kconfirm button')].map(b => b.textContent)")
            self.assertEqual(names, ['Cancel', 'Delete photo'])
            self.assertEqual(pg.evaluate('document.activeElement.textContent'), 'Cancel')
            yes = pg.evaluate("getComputedStyle(document.querySelector('.kq-yes')).color")
            self.assertEqual(yes, 'rgb(255, 138, 128)')               # a red, not the accent
            # Enter presses the focused Cancel: kept, focus back on the opener
            pg.keyboard.press('Enter')
            pg.wait_for_function('window.answer !== undefined')
            self.assertIsNone(pg.evaluate('window.answer'))
            self.assertEqual(pg.evaluate('document.activeElement.id'), 'opener')
            self.assertEqual(d.count(), 0)
            # Escape keeps
            pg.evaluate(ask)
            pg.keyboard.press('Escape')
            pg.wait_for_function('window.answer !== undefined')
            self.assertIsNone(pg.evaluate('window.answer'))
            # Tab stays inside the dialog (the page under it is inert)
            pg.evaluate(ask)
            for _ in range(4):
                pg.keyboard.press('Tab')
                self.assertTrue(pg.evaluate("document.querySelector('dialog.kconfirm').contains(document.activeElement) || document.activeElement === document.body"))
            # the named action confirms
            pg.click('dialog.kconfirm .kq-yes')
            pg.wait_for_function('window.answer !== undefined')
            self.assertEqual(pg.evaluate('window.answer'), {'note': ''})
            self.assertEqual(pg.evaluate('browserAsked'), 0)
            # a note typed and then cancelled is offered again (draft)
            pg.evaluate("() => { window.answer = undefined; K.confirm('Reject?', '', 'Reject', {note: 'Reason', draft: 'r'}).then(v => window.answer = v) }")
            pg.fill('dialog.kconfirm input.note', 'typed')
            pg.keyboard.press('Escape')
            pg.wait_for_function('window.answer !== undefined')
            pg.evaluate("() => { window.answer = undefined; K.confirm('Reject?', '', 'Reject', {note: 'Reason', draft: 'r'}).then(v => window.answer = v) }")
            self.assertEqual(pg.input_value('dialog.kconfirm input.note'), 'typed')
            pg.click('dialog.kconfirm .kq-yes')
            pg.wait_for_function('window.answer !== undefined')
            self.assertEqual(pg.evaluate('window.answer'), {'note': 'typed'})
        self.each(run)

    def test_undo_bar(self):
        """#365 (D1): Undo shows for at least 4 s, as a status the screen reader reads, and runs its action once"""
        def run(pg):
            pg.evaluate("() => { window.undone = 0; window.t0 = Date.now(); K.undo('Unlinked 11LAB70AA501 from step 2', () => undone++, 1000) }")
            bar = pg.locator('#kundo')
            self.assertEqual(bar.get_attribute('role'), 'status')
            self.assertIn('Unlinked 11LAB70AA501 from step 2', bar.text_content())
            pg.wait_for_timeout(3000)
            self.assertTrue(bar.is_visible())                        # (asked for 1 s: 4 s at least)
            pg.get_by_role('button', name='Undo').click()
            self.assertEqual((pg.evaluate('undone'), bar.count()), (1, 0))
            pg.evaluate("() => K.undo('again', () => undone++, 4000)")
            pg.wait_for_function("!document.getElementById('kundo')", timeout=8000)
            self.assertGreaterEqual(pg.evaluate('Date.now() - t0'), 3000 + 4000 - 50)
            self.assertEqual(pg.evaluate('undone'), 1)
        self.each(run)

    def test_no_browser_confirm(self):
        """#365 (D2): no page asks with the browser's confirm(), which can't name its buttons and confirms on Enter"""
        import re
        for f in ('index.js', 'admin.js', 'common.js', 'learning.js', 'course.js', 'course-bridge.js', 'tiles.js'):
            with open(os.path.join(REPO, f), encoding='utf-8') as fh: src = fh.read()
            src = re.sub(r'//[^\n]*', '', src)                     # (comments may name it)
            self.assertIsNone(re.search(r'(?<![.\w])confirm\(', src), f)

if __name__ == '__main__':
    unittest.main()
