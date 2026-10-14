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
3. Devices: "Remove" on a device of one's own opens a small form that asks for the password too (a stolen sign-in
   alone must not cut the owner's phone off); Cancel puts the button back. A wrong password is said and removes
   nothing; the right one removes it, once. An admin removes a member's device as before, after the confirmation.
4. Devices, adding one of one's own (test_add_*, the user, 2026-10-14: a stolen sign-in of an admin must not give its
   holder a device of that person): "Import join request" with a request in the admin's own name, accepting a device
   waiting on the Wi-Fi or a QR invite that is the admin's own: a form asks for the password, the same way; Cancel
   leaves it. An admin adding a member's device: as before, no password.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_signout.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server)."""
import json, os, re, shutil, sys, tempfile, time, unittest
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import start_server, Client, CSP_WATCH, PageErrors
from app_person import crypto2, proto2      # (the Python reference, ref/)

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

    def signed_in(self, browser, user, path, said=None, answer=None, **more):
        """a browser of its own signed in as `user`, on `path` -> (page, its errors)"""
        ctx = browser.new_context(viewport={'width': 1300, 'height': 900}, **more)
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

    def phone(self, admin, username, label, **more):
        """a device of their own for that account, certified from its join request -> its ID (`more`: the password,
        for a device of the certifying account's own person)"""
        key = proto2.key_from_seed(os.urandom(32))
        r = admin.req('POST', '/api/devices/import-request', {'existing_ok': True, 'request': crypto2.join_request(
            key, username, 'Somebody', 'Operator', label, int(time.time())), **more})
        assert r.get('ok'), r
        return proto2.peer_id(key)

    def removed(self, admin):
        return {d['device'] for d in admin.req('GET', '/api/devices?show_hidden=1')['all'] if d['revoked']}

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
            # (the service worker deletes every cache not its own when it moves in, at the end of which it takes the
            # page: the test's cache is made after that, or it can be gone by the check below)
            a1.wait_for_function("() => navigator.serviceWorker.controller")
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
            # (the page's list of what waits is empty for a moment after a sign-in, before it is read from the browser's
            # store: waiting for that list alone ended too early in Firefox. So first until the change has arrived.)
            for _ in range(60):
                if self.sent(): break
                a1.wait_for_timeout(500)
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
            expect(field).to_have_attribute('type', 'password')
            expect(field).to_have_attribute('autocomplete', 'current-password')
            expect(field).to_have_attribute('aria-label', 'Your password')
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
            field.press('Enter')                         # (Enter sends it, as the button does below)
            expect(a1.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual(a1.evaluate('window.asked'), ['{"password":"not the password"}'])
            self.assertEqual((a1.evaluate('window.sameDocument'), self.status(a1), self.status(a3)), (True, 200, 200))
            expect(card.locator('#sessionCount')).to_have_text('Your account is signed in 2 times on the web: here and in 1 other browser or device.')
            # the right one, sent twice in a row (two presses before the first is answered): it goes once, the other ends, and the field is empty again
            field.fill(PW)
            a1.evaluate("""() => { const i = document.querySelector('#sessions form input[name=password]');   // (twice, at once)
                for (const n of [1, 2]) i.form.requestSubmit() }""")
            expect(a1.locator('#toast')).to_have_text('Signed out 1 other session')
            expect(card.locator('form input[name=password]')).to_have_value('')
            expect(a1.locator('#sessionCount')).to_have_text('Your account is signed in on the web here only.')
            # the other browser, opened a moment ago, at its next request (a tab is opened): the sign-in screen
            a3err.leave()
            polls = self.polls(a3)
            a3.locator('#tabs button', has_text='Account').click()
            self.sign_in_screen(a3)
            self.assertEqual(polls, [])                  # (by the tab, not by the page's 15 s check-in)
            # (the two presses: the wrong password and this one went, so it was sent once, and said once)
            self.assertEqual(a1.evaluate('window.asked.length'), 2)
            expect(a1.locator('#toast')).to_have_text('Signed out 1 other session')
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
            b2.locator('#sessions input[name=password]').fill(PW)     # (typed already: see below)
            m.locator('#sessions input[name=password]').fill(PW)
            m.locator('#sessions').get_by_role('button', name='Sign out my other sessions').click()
            expect(m.locator('#toast')).to_have_text('Signed out 2 other sessions')
            self.assertEqual(self.status(m), 200)
            # the other browser presses a button with the sign-in it no longer has: the sign-in screen, not an error
            b2err.leave()
            polls = self.polls(b2)
            b2.locator('#sessions').get_by_role('button', name='Sign out my other sessions').click()
            self.sign_in_screen(b2)
            self.assertEqual(polls, [])
            merr.leave(); m.reload()
            m.wait_for_function(SIGNED_IN % 'boss')
            expect(m.locator('#who')).to_contain_text('manager')

            # ---- 3. Devices: one's own device goes only with the password
            admin = Client(self.base)                    # (the test's first client was one of the manager's other sessions)
            admin.req('POST', '/api/login', {'username': 'boss', 'password': PW})     # (raises when refused)
            phone, tablet, bphone = self.phone(admin, 'ali', 'phone'), self.phone(admin, 'ali', 'tablet'), self.phone(admin, 'boss', 'handheld', password=PW)
            a1err.leave(); a1.goto(self.base + '/admin.html#devices')
            mine = a1.locator('#main .card', has=a1.locator('h3', has_text='Your devices'))
            row = mine.locator('tr', has_text='phone')
            expect(row).to_have_count(1)
            expect(mine.locator('tr', has_text='tablet')).to_contain_text('active')
            # the key this web sign-in itself uses (held by the server): shown as such, with no Remove (the server
            # refuses it: "This is the device you are using"), no form, nothing to press
            signin = mine.locator('tr', has_text='(your web sign-in)')
            expect(signin).to_have_count(1)
            expect(signin).to_contain_text('active')
            self.assertEqual(signin.locator('button, input').count(), 0)
            a1.evaluate("() => { window.sameDocument = true; window.asked = []; window.confirmed = 0; const f = window.fetch;"
                        " window.confirm = () => { confirmed++; return true };"
                        " window.fetch = (u, o) => { if (String(u).includes('/api/devices/revoke')) asked.push(o.body); return f(u, o) } }")
            # the button opens the form in its place, with the field ready to type in; Cancel puts the button back
            self.assertEqual(row.locator('input').count(), 0)
            row.get_by_role('button', name='Remove', exact=True).click()
            field = row.locator('form input[name=password]')
            expect(field).to_be_focused()
            expect(field).to_have_attribute('type', 'password')
            expect(field).to_have_attribute('autocomplete', 'current-password')
            expect(field).to_have_attribute('aria-label', 'Your password')
            expect(row).to_contain_text('It stops syncing; what it already holds stays on it.')
            self.assertEqual(row.get_by_role('button', name='Remove', exact=True).count(), 0)
            field.fill(PW)
            row.get_by_role('button', name='Cancel').click()
            expect(row.get_by_role('button', name='Remove', exact=True)).to_have_count(1)
            self.assertEqual(row.locator('input').count(), 0)
            # without the password nothing is sent; a wrong one is said, the page stays and nothing is removed
            row.get_by_role('button', name='Remove', exact=True).click()
            self.assertEqual(field.input_value(), '')
            row.get_by_role('button', name='Remove this device').click()
            self.assertEqual(field.evaluate('e => e.validity.valueMissing'), True)
            field.fill('not the password')
            field.press('Enter')
            expect(a1.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual(a1.evaluate('[window.sameDocument, window.asked.length, window.confirmed]'), [True, 1, 0])
            self.assertEqual((self.status(a1), self.removed(admin), field.input_value()), (200, set(), 'not the password'))
            # a change elsewhere (here: another device of ali's is added) does not rebuild the page under the password
            # being typed, which would close the form; it is taken in once the person has left the form
            self.phone(admin, 'ali', 'watch')
            a1.evaluate("() => K.listeners.forEach(f => f('synced'))")
            a1.wait_for_timeout(1500)
            self.assertEqual((field.input_value(), mine.locator('tr', has_text='watch').count()), ('not the password', 0))
            row.get_by_role('button', name='Remove this device').focus()      # (Tab to the button: still in the form)
            a1.wait_for_timeout(1500)
            self.assertEqual((field.input_value(), mine.locator('tr', has_text='watch').count()), ('not the password', 0))
            a1.evaluate('() => document.activeElement.blur()')
            expect(mine.locator('tr', has_text='watch')).to_have_count(1)
            expect(row.get_by_role('button', name='Remove', exact=True)).to_have_count(1)
            self.assertEqual((row.locator('input').count(), a1.evaluate('window.sameDocument')), (0, True))
            row.get_by_role('button', name='Remove', exact=True).click()
            # the right one, pressed twice before the first is answered: removed, sent once
            field.fill(PW)
            a1.evaluate("""() => { const i = document.querySelector('#main form input[name=password]');
                for (const n of [1, 2]) i.form.requestSubmit() }""")
            expect(a1.locator('#toast')).to_have_text('Device removed')
            expect(mine.locator('tr', has_text='phone')).to_contain_text('removed')
            self.assertEqual(mine.locator('tr', has_text='phone').locator('button, input').count(), 0)
            expect(mine.locator('tr', has_text='tablet')).to_contain_text('active')
            self.assertEqual((a1.evaluate('window.asked.length'), self.removed(admin), self.status(a1)), (2, {phone}, 200))
            # the manager: a member's device as before (the confirmation, no password); their own with the password
            merr.leave(); m.goto(self.base + '/admin.html#devices')
            other = m.locator('#allDevices tr', has_text='tablet')
            expect(other).to_contain_text('ali')
            n = len(said)
            other.get_by_role('button', name='Remove', exact=True).click()
            expect(m.locator('#toast')).to_have_text('Device removed')
            self.assertEqual((len(said), said[-1][:19], m.locator('#main input[name=password]').count()), (n + 1, 'Remove this device?', 0))
            own = m.locator('#main .card', has=m.locator('h3', has_text='Your devices')).locator('tr', has_text='handheld')
            own.get_by_role('button', name='Remove', exact=True).click()
            self.assertEqual(len(said), n + 1)                        # (no confirmation: the form asks)
            own.locator('input[name=password]').fill(PW)
            own.get_by_role('button', name='Remove this device').click()
            expect(m.locator('#toast')).to_have_text('Device removed')
            expect(m.locator('#main .card', has=m.locator('h3', has_text='Your devices')).locator('tr', has_text='handheld')).to_contain_text('removed')
            self.assertEqual((self.removed(admin), self.status(m)), ({phone, tablet, bphone}, 200))

            for e in (merr, a1err, a2err, a3err, serr, b2err):
                self.assertEqual(list(e), [])
            browser.close()

    def own_add(self, name):
        with sync_playwright() as p:
            browser = p[name].launch()
            said = []
            # (no service worker: WebKit's requests through one bypass the stand-in answers of 4b and 4c)
            page, errors = self.signed_in(browser, 'sara', '/admin.html#devices', said, {'ok': True}, service_workers='block')
            card = page.locator('#main .card', has=page.locator('h3', has_text='Add a computer from a join request'))
            expect(card).to_be_visible()
            page.evaluate("""() => { window.sameDocument = true; window.asked = []; const f = window.fetch;
                window.fetch = (u, o) => { if (o && o.method === 'POST' && /import-request|join-requests\\/|invites\\//.test(String(u)))
                  asked.push([String(u).replace(/^.*\\/api\\//, ''), JSON.parse(o.body)]); return f(u, o) } }""")
            def mine():
                return {d['device'] for d in self.sara.req('GET', '/api/devices')['mine']}
            self.sara = Client(self.base)
            self.sara.req('POST', '/api/login', {'username': 'sara', 'password': PW})
            before = mine()
            def join_file(username, label):
                key = proto2.key_from_seed(os.urandom(32))
                req = crypto2.join_request(key, username, 'Somebody', 'Operator', label, int(time.time()))
                card.locator('input[type=file]').set_input_files(files=[{'name': label + '.kksjoin', 'mimeType': 'application/json',
                                                                          'buffer': json.dumps(req).encode()}])
                return proto2.peer_id(key)

            # ---- 4a. a join request in one's own name (another case of the username): the form, nothing sent yet
            laptop = join_file('SARA', 'laptop')
            field = card.locator('form input[name=password]')
            expect(field).to_be_focused()
            expect(field).to_have_attribute('type', 'password')
            expect(field).to_have_attribute('autocomplete', 'current-password')
            expect(field).to_have_attribute('aria-label', 'Your password')
            expect(card).to_contain_text('This adds a device of your own.')
            self.assertEqual((page.evaluate('window.asked'), said), ([], []))
            # Cancel: the form goes, nothing sent
            card.get_by_role('button', name='Cancel').click()
            expect(card.locator('form')).to_have_count(0)
            # again (the same file chosen again): empty, nothing is sent; wrong: said, the page stays, nothing added
            laptop = join_file('SARA', 'laptop')
            card.get_by_role('button', name='Add this device').click()
            self.assertEqual(field.evaluate('e => e.validity.valueMissing'), True)
            field.fill('not the password')
            field.press('Enter')
            expect(page.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual((page.evaluate('[window.sameDocument, window.asked.length]'), field.input_value()), ([True, 1], 'not the password'))
            self.assertEqual(page.evaluate('window.asked[0][1].password'), 'not the password')
            self.assertEqual((mine(), self.status(page)), (before, 200))
            # a change elsewhere does not rebuild the page under the password being typed
            self.phone(self.boss, 'ali', 'watch')
            page.evaluate("() => K.listeners.forEach(f => f('synced'))")
            page.wait_for_timeout(1500)
            self.assertEqual(field.input_value(), 'not the password')
            # the right one, pressed twice before the first is answered: added, sent once
            field.fill(PW)
            page.evaluate("""() => { const i = document.querySelector('#joinOwn form input[name=password]');
                for (const n of [1, 2]) i.form.requestSubmit() }""")
            expect(page.locator('#toast')).to_have_text('Certified a device of yours. Now give it a bundle.')
            mycard = page.locator('#main .card', has=page.locator('h3', has_text='Your devices'))
            expect(mycard.locator('tr', has_text='laptop')).to_contain_text('active')
            self.assertEqual((page.evaluate('window.asked.length'), mine() - before, said), (2, {laptop}, []))
            self.assertEqual(page.evaluate('window.asked[1]'), ['devices/import-request', {'request': page.evaluate('window.asked[1][1].request'),
                                                                                           'existing_ok': True, 'password': PW}])
            # a member's (somebody else's): as before, the confirmation and no password
            n = len(page.evaluate('window.asked'))
            alis = join_file('ali', 'tablet')
            expect(page.locator('#toast')).to_have_text('Certified a device for ali. Now give them a bundle.')
            self.assertEqual(len(said), 1)
            self.assertIn('already exists. Add this computer as another device of theirs?', said[0])
            self.assertEqual([x[1].get('password') for x in page.evaluate('window.asked')[n:]], [None, None])
            self.assertIn(alis, {d['device'] for d in self.boss.req('GET', '/api/devices')['all']})
            self.assertEqual(page.locator('#main input[type=password]').count(), 0)

            # ---- 4b. a device waiting on the Wi-Fi in one's own name, beside a member's (the list and the answers are
            # stand-ins: no device can ask on the Wi-Fi here; the server's check is in test_server_http.py)
            lobby = {'requests': [
                {'device': 'dev-own', 'code': '123456', 'request': {'full_name': 'Sara Admin', 'username': 'sara', 'label': 'phone'},
                 'existing': {'username': 'sara', 'full_name': 'Sara Admin', 'role': 'admin'}, 'needs_position': False},
                {'device': 'dev-ali', 'code': '654321', 'request': {'full_name': 'Ali', 'username': 'ali', 'label': 'phone'},
                 'existing': {'username': 'ali', 'full_name': 'Ali', 'role': 'user'}, 'needs_position': False}]}
            def answer(r):
                if r.request.method == 'GET':
                    return r.fulfill(status=200, content_type='application/json', body=json.dumps(lobby))
                b = json.loads(r.request.post_data)
                if r.request.url.endswith('dev-own') and b.get('password') != PW:
                    return r.fulfill(status=401, content_type='application/json', body='{"error":"Wrong username or password."}')
                lobby['requests'] = [q for q in lobby['requests'] if not r.request.url.endswith(q['device'])]
                r.fulfill(status=200, content_type='application/json', body=json.dumps({'ok': True, 'username': 'sara' if 'own' in r.request.url else 'ali'}))
            page.route(re.compile(r'.*/api/join-requests.*'), answer)
            page.locator('#tabs button', has_text='Account').click()
            page.wait_for_selector('#main input[name=full_name]')
            page.locator('#tabs button', has_text='Devices').click()
            page.evaluate("() => { window.asked = [] }")
            own = page.locator('#lobby > div', has_text='123 456')
            expect(own).to_have_count(1)
            # a change elsewhere whose rebuild of the page began just before the form was opened (its answer slow)
            # does not close the form either: it is dropped and comes again once the form is left
            page.evaluate("""() => { window.slow = true; const f = window.fetch;
                window.fetch = (u, o) => window.slow && /\\/api\\/devices(\\?|$)/.test(String(u)) ? new Promise(r => setTimeout(r, 1500)).then(() => f(u, o)) : f(u, o);
                K.listeners.forEach(f => f('synced')) }""")
            own.get_by_role('button', name='Accept').click()
            field = own.locator('form input[name=password]')
            expect(field).to_be_focused()
            page.wait_for_timeout(2500)
            expect(field).to_be_focused()
            page.evaluate("() => { window.slow = false }")
            expect(field).to_have_attribute('autocomplete', 'current-password')
            self.assertEqual(page.evaluate('window.asked'), [])
            # another device asking meanwhile does not rebuild the list under the form
            field.fill('not the password')
            lobby['requests'].append({'device': 'dev-3', 'code': '111222', 'request': {'full_name': 'Third', 'username': 'third', 'label': 'x'},
                                      'existing': None, 'needs_position': False})
            page.wait_for_timeout(4500)
            self.assertEqual((field.input_value(), page.locator('#lobby', has_text='111 222').count()), ('not the password', 0))
            field.press('Enter')
            expect(page.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual(field.input_value(), 'not the password')
            field.fill(PW)
            own.get_by_role('button', name='Accept').click()
            expect(page.locator('#toast')).to_have_text('Accepted sara: their device gets the plant over the Wi-Fi now')
            expect(page.locator('#lobby')).to_contain_text('111 222')
            expect(page.locator('#lobby')).not_to_contain_text('123 456')
            page.locator('#lobby > div', has_text='654 321').get_by_role('button', name='Accept').click()
            expect(page.locator('#toast')).to_have_text('Accepted ali: their device gets the plant over the Wi-Fi now')
            self.assertEqual(page.evaluate('window.asked'), [
                ['join-requests/dev-own', {'action': 'accept', 'existing_ok': True, 'password': 'not the password'}],
                ['join-requests/dev-own', {'action': 'accept', 'existing_ok': True, 'password': PW}],
                ['join-requests/dev-ali', {'action': 'accept', 'existing_ok': True}]])
            # Cancel puts the buttons back
            lobby['requests'].append(dict(lobby['requests'][0], device='dev-own2', code='333444',
                                          existing={'username': 'sara', 'full_name': 'Sara Admin', 'role': 'admin'}))
            own2 = page.locator('#lobby > div', has_text='333 444')
            own2.get_by_role('button', name='Accept').click()
            own2.get_by_role('button', name='Cancel').click()
            expect(own2.locator('input')).to_have_count(0)
            expect(own2.get_by_role('button', name='Accept')).to_have_count(1)
            expect(own2.get_by_role('button', name='Refuse')).to_have_count(1)

            # ---- 4c. a QR invite answered by a device of one's own (stand-ins again: no sync port here)
            inv = {'state': 'asked', 'request': {'full_name': 'Sara Admin', 'username': 'sara', 'label': 'tablet', 'device': 'dev-qr'},
                   'existing': {'username': 'sara', 'full_name': 'Sara Admin', 'role': 'admin'}, 'needs_position': False, 'exp': 0, 'seen': 0}
            def invite(r):
                if r.request.method == 'GET':
                    return r.fulfill(status=200, content_type='application/json', body=json.dumps(inv))
                if r.request.url.endswith('/api/invites'):
                    return r.fulfill(status=200, content_type='application/json', body=json.dumps(
                        {'ok': True, 'invite': {'token': 'tok1', 'plant': 'Test plant', 'addrs': ['127.0.0.1:8421']}, 'code': 'kks_invite test'}))
                if json.loads(r.request.post_data).get('password') != PW:
                    return r.fulfill(status=401, content_type='application/json', body='{"error":"Wrong username or password."}')
                inv['state'] = 'accepted'
                r.fulfill(status=200, content_type='application/json', body='{"ok":true}')
            page.route(re.compile(r'.*/api/invites.*'), invite)
            page.get_by_role('button', name='Show QR code').click()
            box = page.locator('#invstate')
            expect(box).to_contain_text('wants to join')
            box.get_by_role('button', name='Accept').click()
            field = box.locator('form input[name=password]')
            expect(field).to_be_focused()
            page.wait_for_timeout(2000)                  # (the invite is asked again meanwhile: the form stays)
            box.get_by_role('button', name='Accept').click()
            self.assertEqual(field.evaluate('e => e.validity.valueMissing'), True)
            field.fill('a guess')
            field.press('Enter')
            expect(page.locator('#toast')).to_have_text('Wrong username or password.')
            self.assertEqual(field.input_value(), 'a guess')
            field.fill(PW)
            field.press('Enter')
            expect(box).to_contain_text('Accepted Sara Admin')
            self.assertEqual([x for x in page.evaluate('window.asked') if x[0].startswith('invites/')], [
                ['invites/tok1', {'action': 'accept', 'existing_ok': True, 'password': 'a guess'}],
                ['invites/tok1', {'action': 'accept', 'existing_ok': True, 'password': PW}]])
            self.assertEqual(list(errors), [])
            browser.close()

    def test_add_chromium(self): self.own_add('chromium')
    def test_add_firefox(self): self.own_add('firefox')
    def test_add_webkit(self): self.own_add('webkit')

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
