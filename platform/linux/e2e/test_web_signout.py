"""Ending web sign-ins at once (the user, 2026-10-12), in all three engines. A web sign-in renews while it is used, so
one on a lost phone or a shared computer would never end by itself.
1. Manage → Users: an account's row has "Sign out everywhere". The confirmation says what it does and what it leaves
   (the password, the devices with the app); saying no changes nothing. After yes, the person's two browsers are at the
   sign-in screen at their next request, by themselves; what the browser kept for offline use is gone, a change that
   was waiting to be sent is still there and is sent after they sign in again, with the password they had.
   Who sees the button: an admin on a user's row, the manager also on an admin's; nobody on the manager's or their own.
2. Account: "Sign out my other sessions" says how many sign-ins are open, asks for the account's password (the
   user, 2026-10-13: a stolen sign-in alone must not end the owner's), ends the others and says how many that were;
   this browser stays signed in, the manager's too. Without the password the browser asks for it; a wrong one is
   said, and nobody is signed out.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_signout.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server)."""
import os, re, shutil, sys, tempfile, unittest
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import start_server, Client, CSP_WATCH, PageErrors

PW = 'a long password'
KKS = '11LAB70AA501'
# a full name that is markup: the confirmation and the page show it as text
NAME = 'Ali <b id=injected>H</b><img src=x onerror=pwned=1>'
SIGNED_IN = "() => typeof K !== 'undefined' && K.me && K.me.user.username === '%s'"


class WebSignOut(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-web-signout-')
        cfg = {'address': '127.0.0.1', 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups')}
        self.server, setup = start_server(SERVER, self.dir, cfg)
        self.addCleanup(self.stop)               # (also when the rest of setUp fails: tearDown would not run)
        self.base = 'http://127.0.0.1:%d' % cfg['port']
        self.boss = Client(self.base)
        assert self.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': 'The Manager',
                                                    'position': 'Plant manager'}).get('ok')
        for name, full, role, pw in (('ali', NAME, 'user', True), ('sara', 'Sara Admin', 'admin', True),
                                     ('omar', 'Omar Admin', 'admin', True), ('zed', 'Zed New', 'user', False)):
            link = self.boss.req('POST', '/api/users', {'username': name, 'full_name': full, 'position': 'Operator', 'role': role})['link']
            if pw:     # (zed never opens the link: no password, so no sign-in to end)
                c = Client(self.base)
                assert c.req('POST', '/api/password-reset', {'token': link.split('#reset=')[1], 'password': PW}).get('ok')
                assert c.req('POST', '/api/logout', {}).get('ok')

    def stop(self):
        self.server.terminate()
        self.server.wait(5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def signed_in(self, browser, user, path, said=None, answer=None):
        """a browser of its own signed in as `user`, on `path` -> (page, its errors)"""
        ctx = browser.new_context(viewport={'width': 1300, 'height': 900})
        ctx.add_init_script(CSP_WATCH)
        r = ctx.request.post(self.base + '/api/login', data={'username': user, 'password': PW}, headers={'Origin': self.base})
        self.assertTrue(r.ok, r.text())
        page = ctx.new_page()
        errors = PageErrors(page)
        if said is not None:
            page.on('dialog', lambda d: (said.append(d.message), d.accept() if answer['ok'] else d.dismiss()))
        page.goto(self.base + path)
        page.wait_for_function(SIGNED_IN % user)
        return page, errors

    def row(self, page, username):
        return page.locator('#main > table tr', has=page.locator('td.mono', has_text=re.compile('^%s( |$)' % username)))

    def status(self, page):
        return page.evaluate("() => fetch('/api/me').then(r => r.status)")

    def sent(self):
        """the notes proposed for KKS that reached the server"""
        return [s['payload']['changes']['notes'] for s in self.boss.req('GET', '/api/submissions')['submissions']
                if s['payload'].get('kks') == KKS]

    def polls(self, page):
        """the check-ins this page makes from now on (/api/sync/status, every 15 s), as a list that fills"""
        seen = []
        page.on('request', lambda r: seen.append(r.url) if '/api/sync/status' in r.url else None)
        return seen

    def sign_in_screen(self, page):
        expect(page.locator('#kov h1')).to_have_text('Test plant', timeout=30000)
        expect(page.locator('#kov input[name=password]')).to_be_visible()

    def engine(self, name):
        with sync_playwright() as p:
            browser = p[name].launch()
            said, answer = [], {'ok': False}             # what each confirmation told the admin
            m, merr = self.signed_in(browser, 'boss', '/admin.html#users', said, answer)
            # ali in two browsers: one on the drawings with a change that could not be sent, one on Manage
            a1, a1err = self.signed_in(browser, 'ali', '/')
            a2, a2err = self.signed_in(browser, 'ali', '/admin.html#mine')
            # (the page's own fetch fails for /api/submit, as without a connection, for as long as this document lives:
            # page.route does not see the requests WebKit's service worker makes)
            self.assertEqual(a1.evaluate("""async k => { await caches.open('kks-data-test');
                const f = window.fetch;
                window.fetch = (u, o) => String(u).includes('/api/submit') ? Promise.reject(new TypeError('no connection')) : f(u, o);
                return (await K.submit('equipment', {kks: k, changes: {notes: 'written before the sign-out'}, base: {}})).status }""", KKS), 'queued')
            self.assertEqual(a1.evaluate("async () => [K.outbox.length, !!(await K.idb.get('me')), (await caches.keys()).includes('kks-data-test')]"),
                             [1, True, True])

            # ---- 1. Manage → Users: who has the button
            merr.leave(); m.reload()
            ali = self.row(m, 'ali')
            expect(ali).to_contain_text(NAME)
            expect(ali.get_by_role('button', name='Sign out everywhere')).to_have_count(1)
            expect(self.row(m, 'sara').get_by_role('button', name='Sign out everywhere')).to_have_count(1)   # the manager, for an admin
            expect(self.row(m, 'zed')).to_contain_text('link not used yet')
            for who in ('boss', 'zed'):                   # not the manager's own; not an account nobody can sign in to yet
                self.assertEqual(self.row(m, who).get_by_role('button', name='Sign out everywhere').count(), 0, who)
            expect(m.locator('#main')).to_contain_text('Sign out everywhere ends every web sign-in of an account at once')
            # said first, and nothing happens when the admin says no
            ali.get_by_role('button', name='Sign out everywhere').click()
            self.assertEqual(len(said), 1)
            for words in (f'Sign {NAME} (ali) out everywhere?', 'Every web sign-in of theirs ends now', 'They sign in again with their password',
                          'stays readable on it until then (at most 3 days)',
                          'does not change their password', 'does not remove their devices with the app'):
                self.assertIn(words, said[-1])
            m.wait_for_timeout(300)
            self.assertEqual((self.status(a1), self.status(a2)), (200, 200))
            self.assertEqual((m.locator('#injected').count(), m.evaluate('window.pwned')), (0, None))
            # yes: both end, and the admin is told how many
            answer['ok'] = True
            ali.get_by_role('button', name='Sign out everywhere').click()
            expect(m.locator('#toast')).to_have_text('ali: 2 web sign-ins ended')
            self.assertEqual(self.status(m), 200)
            # ali's pages are at the sign-in screen at their next request, by themselves: here the check-in every open
            # page makes (every 15 s)
            a1err.leave(); a2err.leave()
            self.sign_in_screen(a2)
            self.sign_in_screen(a1)
            # as on any sign-out: what the browser kept of the plant is gone, what waited to be sent is kept
            a1.wait_for_function("async () => !(await K.idb.get('me')) && !(await caches.keys()).includes('kks-data-test')")
            self.assertEqual(a1.evaluate("async () => (await K.idb.all()).map(i => i.payload.changes.notes)"), ['written before the sign-out'])
            self.assertEqual(self.sent(), [])                    # (not sent yet)
            # nobody was there: said so
            ali = self.row(m, 'ali')
            ali.get_by_role('button', name='Sign out everywhere').click()
            expect(m.locator('#toast')).to_have_text('ali was not signed in on the web')
            # the password is as it was: ali signs in again, and the change that waited is sent
            a1.locator('#kov input[name=username]').fill('ali')
            a1.locator('#kov input[name=password]').fill(PW)
            a1err.leave()
            a1.get_by_role('button', name='Sign in').click()
            a1.wait_for_function(SIGNED_IN % 'ali')
            a1.wait_for_function("() => K.online && K.outbox.length === 0", timeout=30000)
            self.assertEqual(self.sent(), ['written before the sign-out'])
            row = [u for u in self.boss.req('GET', '/api/users')['users'] if u['username'] == 'ali'][0]
            self.assertEqual((row['active'], row['has_password']), (True, True))

            # an admin: the button on a user's row only (not another admin's, the manager's or their own)
            s, serr = self.signed_in(browser, 'sara', '/admin.html#users')
            expect(self.row(s, 'ali').get_by_role('button', name='Sign out everywhere')).to_have_count(1)
            for who in ('omar', 'boss', 'sara'):
                expect(self.row(s, who)).to_have_count(1)
                self.assertEqual(self.row(s, who).get_by_role('button', name='Sign out everywhere').count(), 0, who)

            # ---- 2. Account: the other sessions of one's own
            a3, a3err = self.signed_in(browser, 'ali', '/admin.html#mine')
            a1err.leave(); a1.goto(self.base + '/admin.html#account')
            card = a1.locator('#sessions')
            expect(card.locator('#sessionCount')).to_have_text('Your account is signed in 2 times on the web: here and in 1 other browser or device.')
            expect(card).to_contain_text('This one stays. Your password and your devices with the app are unchanged.')
            expect(card).to_contain_text('It asks for your password')
            # the password is asked for, in a field password managers fill and no page shows
            field = card.locator('form input[name=password]')
            self.assertEqual([field.get_attribute(a) for a in ('type', 'autocomplete', 'aria-label')],
                             ['password', 'current-password', 'Your password'])
            self.assertEqual(field.input_value(), '')
            a1.evaluate("() => { window.sameDocument = true; window.asked = []; const f = window.fetch;"
                        " window.fetch = (u, o) => { if (String(u).includes('/api/sign-out-others')) asked.push(o.body); return f(u, o) } }")
            # without it nothing is sent: the browser points at the empty field
            card.get_by_role('button', name='Sign out my other sessions').click()
            self.assertEqual(field.evaluate('e => [e.validity.valueMissing, e.matches(":invalid")]'), [True, True])
            a1.wait_for_timeout(300)
            self.assertEqual((a1.evaluate('window.asked'), self.status(a3)), ([], 200))
            # a wrong one: said, the page stays as it is and nobody is signed out, this browser neither
            field.fill('not the password')
            card.get_by_role('button', name='Sign out my other sessions').click()
            expect(a1.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual(a1.evaluate('window.asked'), ['{"password":"not the password"}'])
            self.assertEqual((a1.evaluate('window.sameDocument'), self.status(a1), self.status(a3)), (True, 200, 200))
            expect(card.locator('#sessionCount')).to_have_text('Your account is signed in 2 times on the web: here and in 1 other browser or device.')
            # the right one, sent with Enter as with the button: the other ends, and the field is empty again
            field.fill(PW)
            field.press('Enter')
            expect(a1.locator('#toast')).to_have_text('Signed out 1 other session')
            expect(card.locator('form input[name=password]')).to_have_value('')
            expect(a1.locator('#sessionCount')).to_have_text('Your account is signed in on the web here only.')
            # the other browser, opened a moment ago, at its next request (a tab is opened): the sign-in screen
            a3err.leave()
            polls = self.polls(a3)
            a3.locator('#tabs button', has_text='Account').click()
            self.sign_in_screen(a3)
            self.assertEqual(polls, [])                  # (by the tab, not by the page's 15 s check-in)
            # a wrong password typed into a form is a 401 as well: that is said, and the page stays as it is
            form = a1.locator('#main form', has=a1.locator('input[name=old]'))
            form.locator('input[name=old]').fill('not the password')
            form.locator('input[name=new]').fill('a new long password')
            a1.evaluate("() => { window.sameDocument = true }")
            form.get_by_role('button', name='Change password').click()
            expect(a1.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual((a1.evaluate('window.sameDocument'), form.locator('input[name=new]').input_value(), self.status(a1)),
                             (True, 'a new long password', 200))
            # this browser carries on, also after a reload; and with nobody else there, it says so
            a1err.leave(); a1.reload()
            a1.wait_for_function(SIGNED_IN % 'ali')
            self.assertEqual(self.status(a1), 200)
            a1.locator('#sessions input[name=password]').fill(PW)
            a1.locator('#sessions').get_by_role('button', name='Sign out my other sessions').click()
            expect(a1.locator('#toast')).to_have_text('No other sessions: you are signed in here only')
            self.assertEqual((self.status(a1), self.status(s), self.status(m)), (200, 200, 200))   # nobody else's
            # the manager's own account: the same button, and the manager stays in
            b2, b2err = self.signed_in(browser, 'boss', '/admin.html#account')
            merr.leave(); m.goto(self.base + '/admin.html#account')
            # (boss is signed in three times: this browser, the one just opened, and the test's own client)
            expect(m.locator('#sessionCount')).to_have_text('Your account is signed in 3 times on the web: here and in 2 other browsers or devices.')
            m.locator('#sessions input[name=password]').fill(PW)
            m.locator('#sessions').get_by_role('button', name='Sign out my other sessions').click()
            expect(m.locator('#toast')).to_have_text('Signed out 2 other sessions')
            self.assertEqual(self.status(m), 200)
            # the other browser presses a button with the sign-in it no longer has: the sign-in screen, not an error
            b2err.leave()
            polls = self.polls(b2)
            b2.locator('#sessions input[name=password]').fill(PW)
            b2.locator('#sessions').get_by_role('button', name='Sign out my other sessions').click()
            self.sign_in_screen(b2)
            self.assertEqual(polls, [])
            merr.leave(); m.reload()
            m.wait_for_function(SIGNED_IN % 'boss')
            expect(m.locator('#who')).to_contain_text('manager')

            for e in (merr, a1err, a2err, a3err, serr, b2err):
                self.assertEqual(list(e), [])
            browser.close()

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
