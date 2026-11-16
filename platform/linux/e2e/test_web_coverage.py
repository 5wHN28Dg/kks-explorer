"""index.html's Coverage drawer (systems.js KSys.coverageView, a port of core views.coverageView) in all three engines,
against the Nim server with test_web_systems.py's synthetic plant: the totals, the rows per sheet and per system with
their photo bars and words, following a sync (not under the focus: when the focus leaves), a sheet row opening that
sheet coloured by photos, a system row opening Equipment by system on that system, and the keyboard.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_coverage.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (default /tmp/kks-web-shots)."""
import os, re, sys, unittest
from playwright.sync_api import sync_playwright

sys.path.insert(0, os.path.dirname(__file__))
import test_web_systems as tws   # (not its class by name: unittest would run its tests here too)
from test_web_systems import Client, SHOTS

FOCUSED = "(() => { const e = document.activeElement; return e.tagName + ':' + e.textContent.replace(/\\s+/g, ' ').trim() })()"
SYNCED = "K.listeners.forEach(f => f('synced'))"   # what K.watchChanges does when the server's rev moves


class WebCoverage(tws.WebSystems):
    """the server and plant of test_web_systems (its setUpClass), these tests instead of its own"""
    def edit(self, kks, field, value):
        boss = Client(self.base)
        boss.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'})
        r = boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': kks, 'changes': {field: value}, 'base': {field: ''}}})
        self.assertEqual(r.get('status'), 'approved', r)

    def text(self, page, sel):
        return re.sub(r'\s+', ' ', page.text_content(sel)).strip()

    def search_marks(self, page, name):
        """each search result shows its code's photo coverage: a mark with the coverage colour and a shape of its own
        (none a ring, equipment only a half disc, tag plate only a square, both a disc), the same in words for screen
        readers, and a last line saying what the marks mean (not a result)"""
        page.evaluate("""STATE.photos = [{id: 'p1', kks: '11LAB70AA503', caption: 'the valve'},
            {id: 'p2', kks: '11LAB70AA504', caption: 'Tag plate'}, {id: 'p3', kks: '11LAB71AP001', caption: ''},
            {id: 'p4', kks: '11LAB71AP001', caption: 'Tag plate · north side'}]""")
        page.fill('#q', 'LAB7')
        page.wait_for_function("() => document.querySelectorAll('#results .res[id^=res-]').length >= 5")
        got = page.evaluate("""[...document.querySelectorAll('#results .res[id^=res-]')].map(r => {
            const m = r.querySelector('.pmark'), c = m && getComputedStyle(m);
            return [r.querySelector('.k').firstChild === m ? r.querySelector('.k').childNodes[1].textContent : r.querySelector('.k').textContent.trim(),
                    m ? m.className : '', m ? m.getAttribute('aria-hidden') : '', r.querySelector('.vh')?.textContent || '',
                    c ? [c.borderTopLeftRadius, c.backgroundImage !== 'none', c.backgroundColor !== 'rgba(0, 0, 0, 0)', c.boxShadow !== 'none'].join() : '']})""")
        by = {}
        for code, cls, hidden, words, look in got:
            if cls: self.assertEqual(hidden, 'true', code)
            by.setdefault(code, (cls, words, look))
        self.assertEqual(by['11LAB70AA501'][:2], ('pmark p-none', ' · no photos'), name)
        self.assertEqual(by['11LAB70AA503'][:2], ('pmark p-equipment', ' · equipment photo only'), name)
        self.assertEqual(by['11LAB70AA504'][:2], ('pmark p-plate', ' · tag plate photo only'), name)
        self.assertEqual(by['11LAB71AP001'][:2], ('pmark p-both', ' · equipment and tag plate photos'), name)
        # four shapes, told apart without colour: (corner radius, half fill, filled), each with the outline
        looks = {k: by[k][2] for k in ('11LAB70AA501', '11LAB70AA503', '11LAB70AA504', '11LAB71AP001')}
        self.assertEqual(len(set(looks.values())), 4, looks)
        self.assertTrue(all(v.endswith('true') for v in looks.values()), looks)
        self.assertEqual(looks['11LAB70AA501'].split(',')[1:3], ['false', 'false'], looks)   # the ring: nothing inside
        self.assertEqual(looks['11LAB70AA503'].split(',')[1], 'true', looks)                 # half filled
        self.assertNotEqual(looks['11LAB70AA504'].split(',')[0], looks['11LAB71AP001'].split(',')[0], looks)  # square, disc
        # what the marks mean: the last line, which the keyboard can't land on or pick
        legend = page.locator('#results #resLegend')
        self.assertEqual(re.sub(r'\s+', ' ', legend.text_content()),
                         'Photos:no photosequipment photo onlytag plate photo onlyequipment and tag plate photos')
        self.assertEqual(legend.get_attribute('aria-disabled'), 'true')
        self.assertEqual(legend.locator('.pmark').count(), 4)
        page.focus('#q')
        for _ in range(70): page.keyboard.press('ArrowDown')
        self.assertRegex(page.get_attribute('#q', 'aria-activedescendant'), r'^res-\d+$')
        self.assertEqual(legend.get_attribute('aria-selected'), 'false')
        page.screenshot(path=os.path.join(SHOTS, 'search-photos-' + name + '.png'))
        legend.click()                       # not a result: nothing opens, the list stays
        self.assertTrue(page.is_visible('#results'))
        # a result without a code has no mark; nothing found has no legend
        page.fill('#q', 'zzzz')
        page.wait_for_function("() => document.querySelector('#results').textContent.includes('No match')")
        self.assertEqual(page.locator('#results .pmark').count(), 0)
        page.keyboard.press('Escape')

    def run_engine(self, name):
        # each engine starts from the fixture's places: AA501 in the location list; earlier engines' edits are undone
        boss = Client(self.base)
        boss.req('POST', '/api/login', {'username': 'boss', 'password': 'a long password'})
        eq = boss.req('GET', '/api/state').get('equipment', {})
        for k, e in eq.items():
            for f in ('floor', 'area'):
                if e.get(f):
                    r = boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': k, 'changes': {f: ''}, 'base': {f: e[f]}}})
                    self.assertEqual(r.get('status'), 'approved', r)
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            ctx = browser.new_context(viewport={'width': 1200, 'height': 800})
            r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                                 headers={'Origin': self.base})
            self.assertTrue(r.ok, r.text())
            page = ctx.new_page()
            errors = []
            page.on('pageerror', lambda e: errors.append(str(e)))
            page.goto(self.base + '/')
            page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length === 8 && typeof cur !== 'undefined' && cur", timeout=30000)
            btn = page.get_by_role('button', name='Coverage', exact=True)
            self.assertEqual(btn.get_attribute('aria-expanded'), 'false')
            btn.click()
            self.assertEqual(btn.get_attribute('aria-expanded'), 'true')
            self.assertEqual(page.evaluate("document.activeElement.id"), 'covTitle')
            body = self.text(page, '#covBody')
            # 8 tags (a hand-added one among them); 7 codes; a:4 verified + the added tag; AA501 in the location list
            for part in ('7 codes on the drawings, in 8 tags', 'Checked by a person2 of 8 tags (25 %)',
                         'Known place1 of 7 codes (14 %)', 'both 0 · equipment only 0 · tag plate only 0 · none 7',
                         'Readings to review0', 'Missed tags marked1'):
                self.assertIn(part, body, name)
            rows = page.locator('#covBody .covrow')
            names = [re.sub(r'\s+', ' ', x).strip() for x in rows.all_text_contents()]
            self.assertEqual(len(names), 2 + 4, names)
            self.assertTrue(names[0].startswith('Sheet A6 codes · 33 % of tags checked · 17 % placed · 1 marked'), names[0])
            self.assertTrue(names[1].startswith('Sheet B2 codes · 0 % of tags checked · 50 % placed'), names[1])
            self.assertIn("Codes that don't decode1 code", names[2])
            self.assertIn('HAD', names[3])
            self.assertIn('LAB', names[4])
            self.assertIn('4 codes · 50 % of codes checked · 25 % placed', names[4])
            self.assertIn('LBA', names[5])
            # the bar's words for screen readers; the bar itself is hidden from them
            self.assertIn('photos: 0 equipment and tag plate, 0 equipment only, 0 tag plate only, 2 none', names[1])
            self.assertEqual(page.evaluate("[...document.querySelectorAll('#covBody .covbar')].every(b => b.getAttribute('aria-hidden') === 'true')"), True)
            self.assertEqual(page.evaluate("document.querySelector('#covBody .covrow .covbar span').className"), 'p-none')
            page.screenshot(path=os.path.join(SHOTS, 'coverage-' + name + '.png'))
            # a sync with the focus outside the drawer: new numbers at once
            page.focus('#q')
            self.edit('11LAB71AP001', 'floor', '2')
            page.evaluate(SYNCED)
            page.wait_for_function("() => document.getElementById('covTotals').textContent.includes('2 of 7 codes (29 %)')", timeout=15000)
            # with the focus inside: nothing moves under it; when the focus leaves, the drawer catches up
            page.locator('#covBody .covrow').first.focus()
            self.edit('11LAB70AA503', 'area', 'pump house')
            page.evaluate(SYNCED)
            page.wait_for_timeout(1500)
            self.assertIn('2 of 7 codes', self.text(page, '#covTotals'))
            self.assertTrue(page.evaluate("document.activeElement.classList.contains('covrow')"))
            page.focus('#q')
            page.wait_for_function("() => document.getElementById('covTotals').textContent.includes('3 of 7 codes (43 %)')", timeout=15000)
            # the focus on the drawer's heading (where opening it puts the focus): the numbers follow at once
            page.focus('#covTitle')
            self.edit('11LAB70AA504', 'area', 'pump house')
            page.evaluate(SYNCED)
            page.wait_for_function("() => document.getElementById('covTotals').textContent.includes('4 of 7 codes (57 %)')", timeout=15000)
            self.assertEqual(page.evaluate("document.activeElement.id"), 'covTitle')
            # keyboard: from the heading, past the close button, to the first sheet row; Enter opens Sheet A coloured
            page.focus('#covTitle')
            page.keyboard.press('Tab')
            self.assertEqual(page.evaluate("document.activeElement.getAttribute('aria-label')"), 'Close coverage')
            page.keyboard.press('Tab')
            if page.evaluate("document.activeElement.id") == 'covBody':
                page.keyboard.press('Tab')   # Firefox stops on a scrolling container (keyboard scrolling) first
            self.assertTrue(page.evaluate(FOCUSED).startswith('BUTTON:Sheet A'), page.evaluate(FOCUSED))
            # a sheet row: that sheet, coloured by photos
            page.locator('#covBody .covrow', has_text='Sheet B').click()
            page.wait_for_function("() => cur.id === 'b' && document.body.classList.contains('cover')", timeout=15000)
            self.assertEqual(page.get_attribute('#zcover', 'aria-pressed'), 'true')
            page.wait_for_function("() => document.querySelectorAll('#layer .hs.p-none').length === 2")
            # a system row: Equipment by system on that system, every level open; "Show all systems" leaves it
            page.locator('#covBody .covrow').nth(4).click()   # LAB
            self.assertTrue(page.is_visible('#sysDrawer'))
            self.assertFalse(page.is_visible('#covDrawer'))
            self.assertEqual(btn.get_attribute('aria-expanded'), 'false')
            self.assertEqual(page.get_attribute('#sysBtn', 'aria-expanded'), 'true')
            self.assertEqual(page.text_content('#sysCount'), '4 codes in system LAB')
            codes = page.evaluate("[...document.querySelectorAll('#sysBody .sysrow .mono')].map(e => e.textContent)")
            self.assertEqual(codes, ['11LAB70AA501', '11LAB70AA503', '11LAB70AA504', '11LAB71AP001'])
            self.assertTrue(page.evaluate("[...document.querySelectorAll('#sysBody details')].every(d => d.open)"))
            page.get_by_role('button', name='Show all systems').click()
            self.assertEqual(page.text_content('#sysCount'), '7 codes')
            self.assertEqual(page.evaluate("document.activeElement.id"), 'sysQ')
            # the codes that don't decode
            btn.click()
            page.locator('#covBody .covrow', has_text="Codes that don't decode").click()
            self.assertEqual(page.text_content('#sysCount'), "1 code that doesn't decode")
            self.assertEqual(page.evaluate("[...document.querySelectorAll('#sysBody .sysrow .mono')].map(e => e.textContent)"), ['11LAB70'])
            # typing a search covers every system again
            page.fill('#sysQ', 'lab')
            page.wait_for_function("() => document.getElementById('sysCount').textContent === '5 codes match'")
            # closing returns the focus to the drawer's button
            btn.click()
            page.click('#covDrawer [data-close]')
            self.assertFalse(page.is_visible('#covDrawer'))
            self.assertEqual(page.evaluate("document.activeElement.id"), 'covBtn')
            self.assertEqual(btn.get_attribute('aria-expanded'), 'false')
            self.search_marks(page, name)
            browser.close()
            self.assertEqual(errors, [], name)


if __name__ == '__main__':
    unittest.main()
