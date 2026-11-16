"""The web pages for the user's requests of 2026-11-15, in Chromium, Firefox and WebKit, against the Nim server with the
synthetic sample sheet:
  1. the tag panel's Copy button puts the KKS code on the clipboard and says "Copied": with the Clipboard API, and
     without it (Safari on a plain-http page) through the old execCommand way;
  2. the panel's heading (the code, Copy, Close) stays in view while the panel scrolls, on a desktop and on a phone;
  3. Approvals: proposals ticked one by one or all at once, then "Approve selected" or "Reject selected" (Reject asks
     once, with one reason for all); a held one (it clashes) is not approved by the batch;
  4. account requests (sign-up) the same way: Approve selected approves the plain ones only.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_batch.py [unittest arguments]
$KKS_SERVER and $KKS_IMPORTER name the builds (default /tmp/kkslinux, /tmp/kksimp)."""
import os, re, shutil, sys, tempfile, time, unittest
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
IMPORTER = os.environ.get('KKS_IMPORTER', '/tmp/kksimp/kks_import')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import start_server, Client

PW = 'a long password'
CODE = 'team-7391-plant'
# the page's clipboard writes, kept where the test can read them (in every engine: only Chromium lets a page read the
# real clipboard back); the Clipboard API itself still runs
SPY = """(() => {
  window.__copied = [];
  const spy = () => { const c = navigator.clipboard; if (!c || !c.writeText || c.__spied) return;
    const w = c.writeText.bind(c); c.writeText = t => { window.__copied.push(['api', t]); return w(t) }; c.__spied = true };
  spy();
  const ex = document.execCommand.bind(document);
  document.execCommand = (cmd, ...a) => { if (cmd === 'copy') { const e = document.activeElement;
      window.__copied.push(['exec', e && 'value' in e ? e.value.slice(e.selectionStart, e.selectionEnd) : String(getSelection())]) }
    return ex(cmd, ...a) };
})()"""
# no Clipboard API (as Safari on a plain-http page): only the old way is left
NO_API = "Object.defineProperty(Navigator.prototype, 'clipboard', {get: () => undefined, configurable: true})"


class WebBatch(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-web-batch-')
        cfg = {'address': '127.0.0.1', 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups'), 'importer': IMPORTER,
               'glyphs': os.path.join(REPO, 'importer', 'fontlib.kgl')}
        self.server, setup = start_server(SERVER, self.dir, cfg)
        self.base = 'http://127.0.0.1:%d' % cfg['port']
        boss = self.boss = Client(self.base)
        assert boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': 'The Boss',
                                               'position': 'Plant manager'}).get('ok')
        with open(os.path.join(REPO, 'importer', 'tests', 'vectors', 'kkp-sample.pdf'), 'rb') as f: pdf = f.read()
        assert boss.req('POST', '/api/sheets/import?id=sample&name=Sample', raw=pdf, ctype='application/pdf').get('ok')
        for _ in range(300):
            job = boss.req('GET', '/api/sheets/job')['job']
            if job['state'] != 'running': break
            time.sleep(0.2)
        assert job['state'] == 'done', job['log']
        link = boss.req('POST', '/api/users', {'username': 'tom', 'full_name': 'Tom Smith', 'position': 'Technician', 'role': 'user'})['link']
        self.tom = Client(self.base)
        assert self.tom.req('POST', '/api/password-reset', {'token': link.split('#reset=')[1], 'password': PW}).get('ok')

    def tearDown(self):
        self.server.terminate()
        self.server.wait(5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def tag(self, code, n):
        """a tag for `code` marked on the sample sheet (so /?kks=code opens it)"""
        x = 100 + 40 * n
        r = self.boss.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [x, 500, x + 30, 520],
                                                                                'kks': code, 'isa': '', 'note': ''}})
        self.assertEqual(r['status'], 'approved', r)

    def context(self, browser, user='boss', viewport=(1300, 900), scripts=()):
        ctx = browser.new_context(viewport={'width': viewport[0], 'height': viewport[1]}, service_workers='block')
        for s in scripts: ctx.add_init_script(s)
        r = ctx.request.post(self.base + '/api/login', data={'username': user, 'password': PW}, headers={'Origin': self.base})
        self.assertTrue(r.ok, r.text())
        page = ctx.new_page()
        errors = []
        page.on('pageerror', lambda e: errors.append(str(e)))
        return ctx, page, errors

    def open_panel(self, page, code):
        page.goto(self.base + '/?kks=' + code)
        page.wait_for_function("k => typeof selTag !== 'undefined' && selTag && full(selTag) === k", arg=code, timeout=30000)

    def subs(self, q='status=all'):
        return {s['id']: s for s in self.boss.req('GET', '/api/submissions?' + q)['submissions']}

    # ---------------------------------------------------------------- 1, 2: the panel
    def panel(self, browser, name):
        code = '11LAB71AA501'
        self.tag(code, 1)
        # enough in the panel that it scrolls: notes and many custom fields
        r = self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': code, 'base': {}, 'changes': {
            'notes': 'A long note.\n' * 30, 'custom': [{'k': 'Field %d' % i, 'v': 'value %d' % i} for i in range(25)]}}})
        self.assertEqual(r['status'], 'approved', r)
        # the Clipboard API (127.0.0.1 is a secure context)
        ctx, page, errors = self.context(browser, scripts=[SPY])
        if name == 'chromium': ctx.grant_permissions(['clipboard-read', 'clipboard-write'], origin=self.base)
        self.open_panel(page, code)
        head = page.locator('#panel .phead')
        copy = head.get_by_role('button', name='Copy ' + code)
        expect(copy).to_have_text('Copy')
        # the code is text that can be selected (not only copied with the button)
        self.assertNotEqual(page.evaluate("getComputedStyle(document.querySelector('#panel .phead .kks')).userSelect"), 'none')
        copy.click()
        expect(copy).to_have_text('Copied')
        expect(page.locator('#toast')).to_have_text('Copied ' + code)
        self.assertEqual(page.evaluate('window.__copied'), [['api', code]])
        if name == 'chromium': self.assertEqual(page.evaluate('navigator.clipboard.readText()'), code)
        expect(copy).to_have_text('Copy', timeout=5000)     # back after a moment
        # 2. scrolled to the bottom, the heading is still at the top of the panel, its Close button the element there
        for vp in ((1300, 600), (390, 700)):
            page.set_viewport_size({'width': vp[0], 'height': vp[1]})
            page.wait_for_timeout(200)
            self.assertGreater(page.evaluate("(P => P.scrollHeight - P.clientHeight)(document.querySelector('#panel'))"), 300, vp)
            page.evaluate("document.querySelector('#panel').scrollTop = 1e6")
            page.wait_for_timeout(200)
            self.assertGreater(page.evaluate("document.querySelector('#panel').scrollTop"), 300, vp)
            for sel in ('#panel .phead .x', '#panel .phead .copy'):
                hit = page.evaluate("""s => { const b = document.querySelector(s), r = b.getBoundingClientRect(),
                    P = document.querySelector('#panel').getBoundingClientRect();
                    const at = document.elementFromPoint(r.left + r.width / 2, r.top + r.height / 2);
                    return {inside: r.top >= P.top - 1 && r.bottom <= P.bottom + 1 && r.width > 0, hit: at === b || b.contains(at)} }""", sel)
                self.assertEqual(hit, {'inside': True, 'hit': True}, (name, vp, sel))
            # a touch target large enough to hit with a finger
            box = page.locator('#panel .phead .x').bounding_box()
            self.assertGreaterEqual(min(box['width'], box['height']), 40, (vp, box))
            page.locator('#panel .phead .x').click()
            expect(page.locator('#panel')).to_be_hidden()
            if vp[0] == 1300: self.open_panel(page, code)
        self.assertEqual(errors, [])
        ctx.close()
        # 1b. without the Clipboard API (Safari on plain http): the old way, inside the click
        ctx, page, errors = self.context(browser, scripts=[NO_API, SPY])
        if name == 'chromium': ctx.grant_permissions(['clipboard-read', 'clipboard-write'], origin=self.base)
        self.open_panel(page, code)
        self.assertIsNone(page.evaluate('navigator.clipboard'))
        copy = page.locator('#panel .phead').get_by_role('button', name='Copy ' + code)
        copy.click()
        expect(copy).to_have_text('Copied')
        self.assertEqual(page.evaluate('window.__copied'), [['exec', code]])
        self.assertEqual(page.locator('textarea[aria-hidden=true]').count(), 0)    # the helper is gone again
        self.assertEqual(errors, [])
        ctx.close()

    # ---------------------------------------------------------------- 3: approvals, several at once
    def approvals(self, browser):
        codes = ['11LAB72AA50%d' % i for i in range(1, 5)]
        for i, c in enumerate(codes): self.tag(c, 3 + i)
        ids = []
        for c in codes:
            r = self.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'near': 'by ' + c}, 'base': {}}})
            self.assertEqual(r['status'], 'pending', r)
            ids.append(r['id'])
        # a held one: tom saw notes "old" while the manager changed them since
        c = codes[0]
        self.assertEqual(self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'notes': 'old'}, 'base': {}}})['status'], 'approved')
        r = self.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'notes': 'tom'}, 'base': {'notes': 'old'}}})
        held = r['id']
        self.assertEqual(self.boss.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'notes': 'boss'}, 'base': {'notes': 'old'}}})['status'], 'approved')
        self.assertEqual(self.subs('status=open')[held]['status'], 'conflict')
        # two photos of one kind for one code compete: only "Use this one" chooses between them, never the batch
        import base64
        photo = lambda t: 'data:image/jxl;base64,' + base64.b64encode(b'\xff\x0a' + t.encode() * 8).decode()
        rivals = [self.tom.req('POST', '/api/submit', {'kind': 'photo', 'payload': {'kks': codes[3], 'caption': t, 'dataUrl': photo(t)}})['id']
                  for t in ('front', 'side')]
        ctx, page, errors = self.context(browser)
        asked = []
        answer = lambda d: (asked.append((d.type, d.message)), d.accept('Not needed'))
        page.on('dialog', answer)
        page.goto(self.base + '/admin.html#queue')
        bar = page.locator('#pickbar')
        expect(bar).to_be_visible()
        ok, no = bar.get_by_role('button', name='Approve selected'), bar.get_by_role('button', name='Reject selected')
        expect(ok).to_be_disabled(); expect(no).to_be_disabled()
        expect(page.locator('#pickN')).to_have_text('None selected')
        # tick two one by one, and the held one
        for i in (ids[1], ids[2], held, *rivals):
            page.locator(f'#main label.pick input[data-id="{i}"]').check()
        expect(page.locator('#pickN')).to_have_text('5 selected')
        expect(ok).to_have_text('Approve selected (5)')
        self.assertTrue(page.evaluate("document.querySelector('#pickAll').indeterminate"))
        ok.click()
        expect(page.locator('#toast')).to_contain_text('Approved 2 of 5.')
        expect(page.locator('#toast')).to_contain_text(f'#{held} clashes')
        expect(page.locator('#toast')).to_contain_text(re.compile(rf'#({rivals[0]}|{rivals[1]}), #({rivals[0]}|{rivals[1]}): several photos of one kind compete'))
        S = self.subs()
        self.assertEqual([S[i]['status'] for i in (ids[1], ids[2])], ['approved', 'approved'])
        self.assertEqual(S[held]['status'], 'conflict')
        self.assertEqual(S[ids[0]]['status'], 'pending')
        self.assertEqual([S[i]['status'] for i in rivals], ['pending', 'pending'])
        self.assertEqual(asked, [])                         # approving asks nothing
        # the held one is still ticked (it is still waiting); Select all ticks the rest
        expect(page.locator(f'#main label.pick input[data-id="{held}"]')).to_be_checked()
        page.locator('#pickAll').check()
        n = len(self.subs('status=open'))
        expect(page.locator('#pickN')).to_have_text(f'{n} selected')
        self.assertTrue(all(c.is_checked() for c in page.locator('#main label.pick input').all()))
        # Select all off, then on again; Reject selected asks once, with one reason for all
        page.locator('#pickAll').uncheck()
        expect(page.locator('#pickN')).to_have_text('None selected')
        page.locator('#pickAll').check()
        no.click()
        # the page's own question: the button names the action, the focus starts on Cancel, an optional reason
        ask = page.locator('dialog.ask')
        expect(ask).to_be_visible()
        expect(ask.locator('#askT')).to_have_text(f'Reject {n} proposals?')
        expect(ask.locator('#askYes')).to_have_text(f'Reject {n} proposals')
        self.assertEqual(page.evaluate('document.activeElement.id'), 'askNo')
        ask.locator('#askNote').fill('Not needed')
        ask.locator('#askYes').click()
        expect(page.locator('#main')).to_contain_text('Nothing waiting for approval.')
        self.assertEqual(asked, [])                         # no browser dialog
        S = self.subs()
        self.assertEqual({S[i]['status'] for i in (ids[0], ids[3], held, *rivals)}, {'rejected'})
        self.assertEqual({S[i].get('note') for i in (ids[0], ids[3], held, *rivals)}, {'Not needed'})
        # cancelled: nothing happens
        fresh = ['11LAB72AA51%d' % i for i in range(1, 5)]       # (codes nothing was approved for: nothing to clash with)
        for i, c in enumerate(fresh): self.tag(c, 8 + i)
        r = self.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': fresh[3], 'changes': {'near': 'again'}, 'base': {}}})
        page.reload()
        page.locator('#pickAll').check()
        no.click()
        expect(page.locator('dialog.ask')).to_be_visible()
        page.keyboard.press('Escape')
        expect(page.locator('dialog.ask')).to_have_count(0)
        page.wait_for_timeout(300)
        self.assertIn(self.subs()[r['id']]['status'], ('pending', 'conflict'))      # still waiting
        # another tab opened while a batch runs (the bar is gone): the batch goes on to its end and says its result
        # (it stopped without a word at the next proposal, its count line being gone)
        more = [self.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'near': 'later'}, 'base': {}}})['id']
                for c in fresh[:2]]
        page.reload()
        page.locator('#pickAll').check()
        expect(ok).to_have_text('Approve selected (3)')
        slow = lambda route: (time.sleep(0.7), route.continue_())
        page.route('**/api/submissions/*/approve', slow)
        ok.click()
        page.evaluate("location.hash='#mine'")
        expect(page.locator('#pickbar')).to_have_count(0)
        expect(page.locator('#toast')).to_contain_text('Approved 3 of 3.', timeout=15000)
        page.unroute('**/api/submissions/*/approve', slow)
        S = self.subs()
        self.assertEqual({S[i]['status'] for i in (r['id'], *more)}, {'approved'})
        # a marked tag whose code the admin corrected in its field, approved by a batch during which the page is made
        # again (a sync does that): it is saved with the corrected code (the field was read when its turn came, by
        # then holding the code as proposed again)
        first = self.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': fresh[2], 'changes': {'near': 'once more'}, 'base': {}}})['id']
        time.sleep(1.1)       # (the marked tag is the newer one: the second one sent, after the page was made again)
        mark = self.tom.req('POST', '/api/submit', {'kind': 'tag_add', 'payload': {'sheet': 'sample', 'bbox': [900, 700, 930, 720],
                                                                                 'kks': '11LAB72AA590', 'isa': '', 'note': ''}})['id']
        page.evaluate("location.hash='#queue'")      # (no reload: WebKit logs a request cut off by one as a page error)
        expect(page.locator(f'#ek-{mark}')).to_be_visible()
        page.locator(f'#ek-{mark}').fill('11lab72aa591')
        page.locator('#pickAll').check()
        expect(ok).to_have_text('Approve selected (2)')
        page.route('**/api/submissions/*/approve', slow)
        # (the page is made again from inside the page, while the first approval is on its way: the handler above
        # holds this script up meanwhile)
        page.evaluate("() => { document.querySelector('#pickOk').click(); setTimeout(rebuild, 100) }")
        expect(page.locator('#toast')).to_contain_text('Approved 2 of 2.', timeout=15000)
        page.unroute('**/api/submissions/*/approve', slow)
        S = self.subs()
        self.assertEqual([S[first]['status'], S[mark]['status']], ['approved', 'approved'])
        saved = [t['kks'] for t in self.boss.req('GET', '/api/state')['added_tags'] if t['kks'].startswith('11LAB72AA59')]
        self.assertEqual(saved, ['11LAB72AA591'])
        # one of the ticked ones is decided elsewhere and the page made again while the batch runs: it is not sent,
        # and the result names it
        more = ['11LAB72AA52%d' % i for i in range(1, 5)]
        for i, c in enumerate(more): self.tag(c, 12 + i)
        sub = lambda c: self.tom.req('POST', '/api/submit', {'kind': 'equipment', 'payload': {'kks': c, 'changes': {'near': 'last'}, 'base': {}}})['id']
        a1 = sub(more[0]); time.sleep(1.1); a2 = sub(more[1])
        page.evaluate('rebuild()')
        expect(page.locator(f'#main label.pick input[data-id="{a2}"]')).to_be_visible()
        page.locator('#pickAll').check()
        expect(ok).to_have_text('Approve selected (2)')
        self.boss.req('POST', f'/api/submissions/{a2}/reject', {})
        page.route('**/api/submissions/*/approve', slow)
        page.evaluate("() => { document.querySelector('#pickOk').click(); setTimeout(rebuild, 100) }")
        expect(page.locator('#toast')).to_contain_text('Approved 1 of 2.', timeout=15000)
        expect(page.locator('#toast')).to_contain_text(f'No longer waiting or no longer ticked: #{a2}.')
        page.unroute('**/api/submissions/*/approve', slow)
        self.assertEqual(self.subs()[a1]['status'], 'approved')
        # the server answers "sign in" in the middle of a batch: it stops there and says how far it got (it ended
        # without a word, its buttons left off); still signed in, the page is made again with what is left
        b1 = sub(more[2]); time.sleep(1.1); b2 = sub(more[3])
        page.evaluate('rebuild()')
        expect(page.locator(f'#main label.pick input[data-id="{b2}"]')).to_be_visible()
        page.locator('#pickAll').check()
        expect(ok).to_have_text('Approve selected (2)')
        page.route(f'**/api/submissions/{b2}/approve', lambda route: route.fulfill(status=401, content_type='application/json', body='{"error":"sign in"}'))
        ok.click()
        expect(page.locator('#toast')).to_contain_text('Approved 1 of 2.', timeout=15000)
        expect(page.locator('#toast')).to_contain_text('Stopped there:')
        page.unroute(f'**/api/submissions/{b2}/approve')
        expect(ok).to_have_text('Approve selected (1)')
        expect(ok).to_be_enabled()
        S = self.subs()
        self.assertEqual([S[b1]['status'], S[b2]['status']], ['approved', 'pending'])
        self.boss.req('POST', f'/api/submissions/{b2}/reject', {})
        self.assertEqual(errors, [])
        ctx.close()

    # ---------------------------------------------------------------- 4: account requests, several at once
    def signups(self, browser):
        self.assertTrue(self.boss.req('POST', '/api/signup-code', {'code': CODE}).get('ok'))
        anon = Client(self.base)
        for u in ('ann', 'bob', 'cat', 'boss'):     # boss: a username somebody has
            r = anon.req('POST', '/api/signup', {'code': CODE, 'full_name': 'Person ' + u, 'position': 'Operator', 'username': u,
                                                 'password': PW + ' ' + u, 'password2': PW + ' ' + u})
            self.assertTrue(r.get('ok'), r)
        ctx, page, errors = self.context(browser)
        asked = []
        page.on('dialog', lambda d: (asked.append(d.message), d.accept()))
        page.goto(self.base + '/admin.html#users')
        expect(page.locator('#signups h3')).to_have_text('Account requests (4)')
        ok = page.locator('#signups').get_by_role('button', name='Approve selected')
        expect(ok).to_be_disabled()
        for u in ('ann', 'boss'):
            page.locator(f'#signups tr[data-user={u}] input.supick').check()
        expect(page.locator('#suN')).to_have_text('2 selected')
        page.evaluate('rebuild()')                         # what a sync does: the ticks stay
        expect(page.locator('#suN')).to_have_text('2 selected')
        expect(page.locator('#signups tr[data-user=ann] input.supick')).to_be_checked()
        ok.click()
        expect(page.locator('#toast')).to_contain_text('Approved 1 of 2.')
        expect(page.locator('#toast')).to_contain_text('Not approved: boss')
        self.assertEqual(asked, [])
        expect(page.locator('#signups h3')).to_have_text('Account requests (3)')
        users = [u['username'] for u in self.boss.req('GET', '/api/users')['users']]
        self.assertIn('ann', users)
        # the rest: all, rejected after one question
        page.locator('#suAll').check()
        expect(page.locator('#suN')).to_have_text('3 selected')
        page.locator('#signups').get_by_role('button', name='Reject selected').click()
        expect(page.locator('dialog.ask #askT')).to_have_text('Reject 3 requests?')
        page.locator('dialog.ask').get_by_role('button', name='Reject 3 requests').click()
        expect(page.locator('#signups')).to_contain_text('Nobody is waiting.')
        self.assertEqual(asked, [])
        self.assertEqual(self.boss.req('GET', '/api/signups')['requests'], [])
        # one request alone has no ticks: its heading has as many columns as its row (an empty first one moved
        # "Name" over the username)
        self.assertTrue(anon.req('POST', '/api/signup', {'code': CODE, 'full_name': 'Person dan', 'position': 'Operator', 'username': 'dan',
                                                         'password': PW + ' dan', 'password2': PW + ' dan'}).get('ok'))
        page.reload()
        expect(page.locator('#signups h3')).to_have_text('Account requests (1)')
        expect(page.locator('#signups input.supick')).to_have_count(0)
        self.assertEqual(page.locator('#signups table tr').first.locator('th').count(), page.locator('#signups tr[data-user=dan] td').count())
        expect(page.locator('#signups th').first).to_have_text('Name')
        self.assertEqual(errors, [])
        ctx.close()

    def run_engine(self, name):
        with sync_playwright() as p:
            browser = getattr(p, name).launch()
            try:
                self.panel(browser, name)
                self.approvals(browser)
                self.signups(browser)
            finally:
                browser.close()

    def test_chromium(self): self.run_engine('chromium')
    def test_firefox(self): self.run_engine('firefox')
    def test_webkit(self): self.run_engine('webkit')


if __name__ == '__main__':
    unittest.main()
