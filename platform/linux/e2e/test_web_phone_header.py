"""index.html's phone header (#367; the 'phone-header' switch until the owner's check) in all three engines, against the
Nim server with test_web_systems.py's synthetic plant:
  - switched off (the default), the header is exactly main's: the same controls in the same order, no More;
  - switched on, at every phone size (320 and 412 px wide, a phone turned sideways, 200 % zoom of a laptop and of a
    phone) search, the sheet, Review and More are at least 48 x 48 CSS px, don't overlap, nothing is wider than the
    window, and the sync state shows; every other control is in More's menu, each 48 px tall, reachable in the window
    (the menu scrolls); on a wide window the header is the desktop's again;
  - the menu with the keyboard alone (Enter or the down arrow opens it on its first item, the arrows, Home and End move,
    Escape closes it with the focus back on More) and to a screen reader (More says whether it is open; the menu is a
    named group of the same buttons and links);
  - a choice closes the menu; a drawer opened from it gives the focus back to More when it closes; a tap outside closes;
  - the approvals waiting are counted on More when Account is in its menu.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_phone_header.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server); screenshots go to $KKS_SHOTS (default /tmp/kks-web-shots)."""
import os, sys, unittest
from playwright.sync_api import sync_playwright

sys.path.insert(0, os.path.dirname(__file__))
import test_web_systems as tws   # (not its class by name: unittest would run its tests here too)
from test_web_systems import SHOTS
from test_web_v2 import CSP_WATCH

# the header's controls on main, in order (the switch off, and any window wider than a phone with it on)
DESKTOP = ['brand', 'search', 'sysBtn', 'covBtn', 'sheetSel', 'floorSel', 'procBtn', 'revBtn', 'linksBtn', 'notesBtn',
           'syncStatus', 'learnBtn', 'aboutBtn', 'manageBtn']
MENU = ['sysBtn', 'covBtn', 'floorSel', 'procBtn', 'linksBtn', 'notesBtn', 'learnBtn', 'aboutBtn', 'manageBtn']
ORDER = """[...document.querySelector('header').children].map(e => e.id || e.className)
  .concat([...document.querySelectorAll('#moreMenu > *')].map(e => 'menu:' + e.id))"""
# (width, height, device scale): a 320 px phone, the Note 9, the Note 9 sideways, a laptop at 200 % zoom, the Note 9 at
# 200 % zoom (CSS px: the layout of a zoomed page is the layout of a window that size)
SIZES = [('320', 320, 640, 2), ('412', 412, 846, 2.625), ('landscape', 846, 412, 2.625), ('laptop-200', 640, 400, 2),
         ('412-200', 206, 423, 5.25)]
BOX = "id => { const r = document.getElementById(id).getBoundingClientRect(); return [r.left, r.top, r.width, r.height] }"
FOCUSED = "document.activeElement && (document.activeElement.id || document.activeElement.tagName)"


class WebPhoneHeader(tws.WebSystems):
    """the server and plant of test_web_systems (its setUpClass), these tests instead of its own"""

    def page_at(self, browser, w, h, scale, switch):
        ctx = browser.new_context(viewport={'width': w, 'height': h}, device_scale_factor=scale)
        ctx.add_init_script(CSP_WATCH)
        r = ctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': 'a long password'},
                             headers={'Origin': self.base})
        self.assertTrue(r.ok, r.text())
        page = ctx.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        page.goto(self.base + ('/?ux=phone-header' if switch else '/'))
        page.wait_for_function("() => typeof TAGS !== 'undefined' && TAGS.length === 8 && typeof cur !== 'undefined' && cur", timeout=30000)
        return ctx, page, errors

    def check_size(self, page, label, w, h):
        """the phone header at this size: what stays, its sizes, nothing overlapping or wider than the window"""
        order = page.evaluate(ORDER)
        self.assertEqual(order, ['brand', 'search', 'sheetSel', 'revBtn', 'moreBtn', 'syncStatus', 'moreMenu']
                         + ['menu:' + i for i in MENU], label)
        self.assertTrue(page.evaluate("document.querySelector('header').classList.contains('phonehead')"), label)
        self.assertFalse(page.is_visible('.brand'), label)
        boxes = {i: page.evaluate(BOX, i) for i in ('q', 'sheetSel', 'revBtn', 'moreBtn')}
        for i, (x, y, bw, bh) in boxes.items():
            self.assertGreaterEqual(bh, 48, f'{label}: {i} {bw}x{bh}')
            self.assertGreaterEqual(bw, 48, f'{label}: {i} {bw}x{bh}')
            self.assertGreaterEqual(x, 0, f'{label}: {i} starts left of the window')
            self.assertLessEqual(x + bw, w + 0.5, f'{label}: {i} ends right of the window')
        ids = list(boxes)
        for a in range(len(ids)):
            for b in range(a + 1, len(ids)):
                (ax, ay, aw, ah), (bx, by, bw, bh) = boxes[ids[a]], boxes[ids[b]]
                apart = ax + aw <= bx or bx + bw <= ax or ay + ah <= by or by + bh <= ay
                self.assertTrue(apart, f'{label}: {ids[a]} and {ids[b]} overlap')
        self.assertLessEqual(page.evaluate("document.documentElement.scrollWidth"), w, label + ': wider than the window')
        self.assertIn('Online', page.text_content('#syncStatus'))
        self.assertTrue(page.is_visible('#syncStatus'), label)
        sx, sy, sw, sh = page.evaluate(BOX, 'syncStatus')
        self.assertLessEqual(sx + sw, w + 0.5, label)
        # the header leaves most of the window to the drawing
        hh = page.evaluate("document.querySelector('header').getBoundingClientRect().height")
        self.assertLess(hh, h * (0.5 if h < 500 else 0.25), f'{label}: header {hh} px of {h}')
        page.screenshot(path=os.path.join(SHOTS, f'phone-header-{label}.png'))
        # the menu: every item 48 px tall and as wide as the menu, inside the window or reached by scrolling the menu
        page.click('#moreBtn')
        self.assertEqual(page.get_attribute('#moreBtn', 'aria-expanded'), 'true')
        self.assertTrue(page.is_visible('#moreMenu'), label)
        page.screenshot(path=os.path.join(SHOTS, f'phone-header-{label}-menu.png'))
        mx, my, mw, mh = page.evaluate(BOX, 'moreMenu')
        self.assertGreaterEqual(mx, 0, label)
        self.assertLessEqual(mx + mw, w + 0.5, label)
        self.assertLessEqual(my + mh, h + 0.5, label + ': the menu runs off the window')
        for i in MENU:
            page.evaluate("id => document.getElementById(id).scrollIntoView({block: 'nearest'})", i)
            x, y, iw, ih = page.evaluate(BOX, i)
            self.assertGreaterEqual(ih, 48, f'{label}: {i} {iw}x{ih} in the menu')
            self.assertGreaterEqual(iw, 48, f'{label}: {i} {iw}x{ih} in the menu')
            self.assertTrue(my - 0.5 <= y and y + ih <= my + mh + 0.5, f'{label}: {i} can not be scrolled into the menu')
            self.assertTrue(0 <= y and y + ih <= h + 0.5, f'{label}: {i} outside the window')
        page.click('#moreBtn')
        self.assertFalse(page.is_visible('#moreMenu'), label)
        self.assertEqual(page.get_attribute('#moreBtn', 'aria-expanded'), 'false')

    def keyboard(self, page, label):
        """the menu with the keyboard alone, and what a screen reader is told"""
        more = page.get_by_role('button', name='More', exact=True)
        self.assertEqual(more.get_attribute('aria-controls'), 'moreMenu')
        page.focus('#moreBtn')
        page.keyboard.press('Enter')
        self.assertEqual(more.get_attribute('aria-expanded'), 'true')
        self.assertEqual(page.evaluate(FOCUSED), 'sysBtn', label)
        group = page.get_by_role('group', name='More')
        for name in ('Systems', 'Coverage', 'Procedures', 'Connectors', 'Sheet notes', 'About'):
            self.assertEqual(group.get_by_role('button', name=name, exact=True).count(), 1, f'{label}: {name}')
        self.assertEqual(group.get_by_role('link', name='Learning', exact=True).count(), 1, label)
        self.assertEqual(group.get_by_role('link').count(), 2, label + ': Learning and the account (named by who is signed in)')
        self.assertEqual(page.evaluate("document.getElementById('manageBtn').parentElement.id"), 'moreMenu')
        self.assertEqual(group.get_by_role('combobox').count(), 1, label + ': the floors')
        page.keyboard.press('ArrowDown')
        self.assertEqual(page.evaluate(FOCUSED), 'covBtn')
        page.keyboard.press('ArrowDown')
        self.assertEqual(page.evaluate(FOCUSED), 'floorSel')
        page.keyboard.press('Tab')   # (the select keeps its arrows; Tab moves on)
        self.assertEqual(page.evaluate(FOCUSED), 'procBtn')
        page.keyboard.press('End')
        self.assertEqual(page.evaluate(FOCUSED), 'manageBtn')
        page.keyboard.press('ArrowDown')
        self.assertEqual(page.evaluate(FOCUSED), 'sysBtn', label + ': the arrows go round')
        page.keyboard.press('ArrowUp')
        self.assertEqual(page.evaluate(FOCUSED), 'manageBtn')
        page.keyboard.press('Home')
        self.assertEqual(page.evaluate(FOCUSED), 'sysBtn')
        page.keyboard.press('Escape')
        self.assertFalse(page.is_visible('#moreMenu'), label)
        self.assertEqual(more.get_attribute('aria-expanded'), 'false')
        self.assertEqual(page.evaluate(FOCUSED), 'moreBtn', label + ': Escape keeps the focus on More')
        page.keyboard.press('ArrowDown')
        self.assertEqual(page.evaluate(FOCUSED), 'sysBtn', label + ': the down arrow on More opens it')
        page.keyboard.press('Escape')
        # a choice by keyboard: Systems opens its drawer, the menu closes; closing the drawer gives the focus to More
        page.keyboard.press('Enter')
        page.keyboard.press('Enter')
        page.wait_for_function("() => document.getElementById('sysDrawer').classList.contains('open')")
        self.assertFalse(page.is_visible('#moreMenu'), label)
        self.assertEqual(page.evaluate(FOCUSED), 'sysQ')
        self.assertEqual(page.get_attribute('#sysBtn', 'aria-expanded'), 'true')
        page.click('#sysDrawer [data-close]')
        self.assertEqual(page.evaluate(FOCUSED), 'moreBtn', label + ': the drawer gave the focus back to a hidden button')
        # Procedures moves no focus of its own: it comes back to More, not to the hidden button or the page
        page.keyboard.press('Enter')
        page.keyboard.press('End')
        for _ in range(6):
            if page.evaluate(FOCUSED) == 'procBtn': break
            page.keyboard.press('ArrowUp')
        self.assertEqual(page.evaluate(FOCUSED), 'procBtn')
        page.keyboard.press('Enter')
        page.wait_for_function("() => document.getElementById('procDrawer').classList.contains('open')")
        page.wait_for_function("() => document.activeElement.id === 'moreBtn'")
        self.assertFalse(page.is_visible('#moreMenu'), label)
        page.click('#procDrawer [data-close]')
        # Tab out of the open menu closes it
        page.click('#moreBtn')
        page.focus('#manageBtn')
        page.keyboard.press('Tab')
        self.assertFalse(page.is_visible('#moreMenu'), label + ': Tab out of the menu left it open')
        # a tap outside closes it and changes nothing else
        page.click('#moreBtn')
        page.mouse.click(5, page.viewport_size['height'] - 5)
        self.assertFalse(page.is_visible('#moreMenu'), label)
        # Android's Back (K.back) closes the menu first
        page.click('#moreBtn')
        self.assertTrue(page.evaluate("K.back()"))
        self.assertFalse(page.is_visible('#moreMenu'), label)

    def queue_count(self, page, label):
        """the approvals waiting (Account's count) show on More while Account is in its menu"""
        page.evaluate("STATE.queue = 3; updateQueueBadge()")
        self.assertEqual(page.get_attribute('#moreBtn', 'aria-label'), 'More, 3 waiting for approval')
        self.assertEqual(page.text_content('#moreBtn .count'), '3')
        self.assertTrue(page.is_visible('#moreBtn .count'), label)
        x, y, bw, bh = page.evaluate(BOX, 'moreBtn')
        self.assertGreaterEqual(min(bw, bh), 48)
        page.screenshot(path=os.path.join(SHOTS, f'phone-header-{label}-queue.png'))
        page.evaluate("STATE.queue = 0; updateQueueBadge()")
        self.assertEqual(page.get_attribute('#moreBtn', 'aria-label'), 'More')
        self.assertFalse(page.is_visible('#moreBtn .count'), label)

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            # switched off: main's header at a phone's size and on a desktop
            for w, h in ((412, 846), (1200, 800)):
                ctx, page, errors = self.page_at(browser, w, h, 1, False)
                self.assertEqual(page.evaluate(ORDER), DESKTOP, f'{name} off {w}')
                self.assertEqual(page.locator('#moreBtn').count(), 0)
                self.assertFalse(page.evaluate("document.querySelector('header').classList.contains('phonehead')"))
                page.screenshot(path=os.path.join(SHOTS, f'phone-header-off-{w}-{name}.png'))
                ctx.close()
                self.assertEqual(errors, [], name)
            # switched on: every phone size
            for label, w, h, scale in SIZES:
                ctx, page, errors = self.page_at(browser, w, h, scale, True)
                self.check_size(page, f'{label}-{name}', w, h)
                if label == '412':
                    self.keyboard(page, f'{label}-{name}')
                    self.queue_count(page, f'{label}-{name}')
                    # turned to a wide window: the desktop's header, each control back in its place; and back again
                    page.set_viewport_size({'width': 1200, 'height': 800})
                    page.wait_for_function("() => !document.querySelector('header').classList.contains('phonehead')")
                    self.assertEqual(page.evaluate(ORDER), DESKTOP, name)
                    page.set_viewport_size({'width': 412, 'height': 846})
                    page.wait_for_function("() => document.querySelector('header').classList.contains('phonehead')")
                    self.check_size(page, f'{label}-again-{name}', 412, 846)
                    # the switch stays on in this browser after a reload without ?ux=, and goes with ?ux=
                    page.goto(self.base + '/')
                    page.wait_for_function("() => typeof cur !== 'undefined' && cur", timeout=30000)
                    self.assertEqual(page.locator('#moreBtn').count(), 1, name)
                    self.assertEqual(page.evaluate("location.search"), '')
                    page.goto(self.base + '/?ux=')
                    page.wait_for_function("() => typeof cur !== 'undefined' && cur", timeout=30000)
                    self.assertEqual(page.locator('#moreBtn').count(), 0, name)
                ctx.close()
                self.assertEqual(errors, [], f'{label}-{name}')
            # switched on, a desktop window: main's header
            ctx, page, errors = self.page_at(browser, 1200, 800, 1, True)
            self.assertEqual(page.evaluate(ORDER), DESKTOP, name)
            self.assertEqual(page.locator('#moreBtn').count(), 0)
            ctx.close()
            browser.close()
            self.assertEqual(errors, [], name)

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
