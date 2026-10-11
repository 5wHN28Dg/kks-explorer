"""A web sign-in for someone who joined with the app, in all three engines. Such a person has devices of their own
and no account on the server (app_person.py makes them with the Python reference): before, they could not sign in
on the web as themselves, and a second username made them a second person.
1. Manage → Users: their row has "Web sign-in"; the admin confirms and gets a one-time password link; the person
   opens it, sets a password, and under My submissions sees what their phone sent.
2. Sign-up: a request under such a person's username says who that person is and offers "Approve as the same
   person" behind a confirmation that says what it grants; the requester then signs in as that person.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_signin.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server)."""
import json, os, re, shutil, subprocess, sys, tempfile, unittest, urllib.request
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client, CSP_WATCH, PageErrors
from app_person import AppPerson

PW = 'a long password'
CODE = 'team-7391-plant'
# a full name that is markup: it must show as text wherever the admin reads who the person is
NAME = 'Ali <b id=injected>H</b><img src=x onerror=pwned=1>'


class WebSignIn(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-web-signin-')
        self.port = free_port()
        cfg = {'address': '127.0.0.1', 'port': self.port, 'sync_port': 0, 'plant_name': 'Test plant', 'web_dir': REPO,
               'data_dir': os.path.join(REPO, 'data'), 'store': os.path.join(self.dir, 'server.db'),
               'storage_key_file': os.path.join(self.dir, 'storage.key'), 'plant_dir': os.path.join(self.dir, 'plant-data'),
               'backup_dir': os.path.join(self.dir, 'backups')}
        with open(os.path.join(self.dir, 'config.json'), 'w') as f: json.dump(cfg, f)
        self.server = subprocess.Popen([SERVER, 'serve', '--config', os.path.join(self.dir, 'config.json')], cwd=self.dir,
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        setup = None
        for _ in range(50):
            line = self.server.stdout.readline()
            if 'setup link file: ' in line:
                with open(line.split('setup link file: ', 1)[1].strip()) as f: setup = re.search(r'#setup=([A-Za-z0-9_-]+)', f.read())[1]
            if 'server on' in line: break
        self.base = 'http://127.0.0.1:%d' % self.port
        self.boss = Client(self.base)
        assert self.boss.req('POST', '/api/setup', {'token': setup, 'username': 'boss', 'password': PW, 'full_name': 'The Manager',
                                                    'position': 'Plant manager'}).get('ok')
        self.boss.req('POST', '/api/signup-code', {'code': CODE})

    def tearDown(self):
        self.server.terminate()
        self.server.wait(5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def admin(self, m, p, body=None, raw=None, headers=None):
        """the manager's client as app_person wants it: -> (status, JSON or bytes)"""
        data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
        h = {'Origin': self.base} | ({'Content-Type': 'application/json'} if body is not None else {}) | (headers or {})
        with self.boss.op.open(urllib.request.Request(self.base + p, data=data, method=m, headers=h)) as resp:
            b = resp.read()
            return resp.status, (json.loads(b) if resp.headers.get('Content-Type', '').startswith('application/json') else b)

    def users(self):
        return {x['username']: x for x in self.boss.req('GET', '/api/users')['users']}

    def mine(self, page, code):
        """My submissions in this page: the card of `code`"""
        page.goto(self.base + '/admin.html#mine')
        card = page.locator(f'#main .card.mine[data-code="{code}"]')
        expect(card).to_be_visible()
        return card

    def engine(self, name):
        # two people who joined with the app, each with a change their phone sent; neither has an account
        ali = AppPerson(self.admin, 'ali', NAME, 'Operator')
        ali.note('11LAB70AA501', 'seen from the phone')
        kim = AppPerson(self.admin, 'Kim', 'Kim Field', 'Technician')
        kim.note('11LAB70AA502', 'kim was here')
        self.assertEqual([(u['no_account'], u['devices']) for u in (self.users()['ali'], self.users()['Kim'])], [(True, 1)] * 2)
        with sync_playwright() as p:
            browser = p[name].launch()
            mctx = browser.new_context()
            mctx.add_init_script(CSP_WATCH)
            mctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': self.base})
            m = mctx.new_page()
            merr = PageErrors(m)
            said = []                                    # what each confirmation told the admin
            answer = {'ok': False}
            m.on('dialog', lambda d: (said.append(d.message), d.accept() if answer['ok'] else d.dismiss()))

            # ---- 1. the admin's Web sign-in
            m.goto(self.base + '/admin.html#users')
            row = m.locator('#main > table tr', has=m.locator('td.mono', has_text=re.compile('^ali$')))
            expect(row).to_contain_text('own device (1)')
            expect(row).to_contain_text(NAME)                                    # as text
            self.assertEqual((m.locator('#injected').count(), m.evaluate('window.pwned')), (0, None))
            self.assertEqual(row.get_by_role('button', name='Password link').count(), 0)
            # said first, and nothing happens when the admin says no
            row.get_by_role('button', name='Web sign-in').click()
            self.assertIn('a web sign-in?', said[-1])
            self.assertIn('as the same person', said[-1])
            m.wait_for_timeout(300)
            self.assertIs(self.users()['ali']['no_account'], True)
            self.assertEqual(m.locator('#main > .warn').count(), 0)
            answer['ok'] = True
            row.get_by_role('button', name='Web sign-in').click()
            expect(m.locator('#toast')).to_contain_text('Web sign-in created')
            expect(m.locator('#main > .warn')).to_contain_text('Password link for ali (valid 3 days, works once):')
            link = m.locator('#main > .warn .linkbox').text_content()
            self.assertIn('/#reset=', link)
            # the row is an account's now: one row, the same person
            row = m.locator('#main > table tr', has=m.locator('td.mono', has_text=re.compile('^ali$')))
            expect(row).to_have_count(1)
            expect(row).to_contain_text('link not used yet')
            for b in ('Password link', 'Deactivate', 'Edit details'):
                expect(row.get_by_role('button', name=b)).to_have_count(1)
            self.assertEqual(row.get_by_role('button', name='Web sign-in').count(), 0)
            acct = self.users()['ali']
            self.assertEqual((acct.get('no_account'), acct['person'], acct['has_password']), (None, ali.person, False))

            # ---- the person opens the link on their phone-sized browser, sets a password, and is themselves
            uctx = browser.new_context(viewport={'width': 390, 'height': 844})
            uctx.add_init_script(CSP_WATCH)
            u = uctx.new_page()
            uerr = PageErrors(u)
            u.goto(link.replace('http://localhost:', 'http://127.0.0.1:'))
            expect(u.locator('#kov h1')).to_have_text('Set your password')
            self.assertEqual(u.locator('#kov input[name=u]').input_value(), 'ali')
            for field in ('password', 'password2'):
                u.locator(f'#kov input[name={field}]').fill('ali web password')
            u.get_by_role('button', name='Save password').click()
            u.wait_for_function("() => typeof K !== 'undefined' && K.me && K.me.user.username === 'ali'")
            self.assertEqual(u.evaluate('K.me.user.person'), ali.person)
            uerr.leave()
            card = self.mine(u, '11LAB70AA501')                                  # what the phone sent is theirs
            expect(card).to_contain_text('seen from the phone')
            expect(card.get_by_role('button', name='Withdraw')).to_have_count(1)
            self.assertEqual(u.locator('#main .card.mine').count(), 1)           # and only theirs
            self.assertEqual(u.locator('#tabs button', has_text='Users').count(), 0)

            # ---- 2. a sign-up request under an app person's username (typed in another case), and one nobody has
            answer['ok'] = False
            for who, username, pw in (('K. Field', 'kim', 'kim chose this one'), ('New Person', 'zaid', 'zaid chose this one')):
                a = browser.new_context().new_page()
                a.goto(self.base + '/')
                a.locator('#signup').click()
                f = a.locator('#kov form')
                for field, v in (('code', CODE), ('full_name', who), ('position', 'Operator'), ('username', username),
                                 ('password', pw), ('password2', pw)):
                    f.locator(f'input[name={field}]').fill(v)
                f.get_by_role('button', name='Send the request').click()
                expect(a.locator('#kov h1')).to_have_text('Request sent')          # the same answer for both
                expect(a.locator('#kov .box p')).to_contain_text('An admin has to approve it')
                a.context.close()
            merr.leave(); m.reload()
            expect(m.locator('#signups h3')).to_have_text('Account requests (2)')
            req = m.locator('#signups tr[data-user=kim]')
            # who the username belongs to, plainly
            expect(req).to_contain_text('this is the username of Kim Field (Kim, Technician, user, 1 device), who uses the app and has no web sign-in')
            for b in ('Approve as the same person', 'Approve with another username', 'Reject'):
                expect(req.get_by_role('button', name=b)).to_have_count(1)
            plain = m.locator('#signups tr[data-user=zaid]')
            self.assertEqual((plain.get_by_role('button', name='Approve', exact=True).count(),
                              plain.get_by_role('button', name='Approve as the same person').count()), (1, 0))
            # the confirmation says what it grants; saying no changes nothing
            n = len(said)
            req.get_by_role('button', name='Approve as the same person').click()
            self.assertEqual(len(said), n + 1)
            for words in ('sent as “K. Field”', 'asks for the username of Kim Field (Kim, Technician, user, 1 device)',
                          'lets whoever sent it act as Kim Field', 'check with Kim Field that it is theirs'):
                self.assertIn(words, said[-1])
            m.wait_for_timeout(300)
            self.assertIs(self.users()['Kim']['no_account'], True)
            self.assertEqual(len(self.boss.req('GET', '/api/signups')['requests']), 2)
            answer['ok'] = True
            req.get_by_role('button', name='Approve as the same person').click()
            expect(m.locator('#toast')).to_contain_text('Approved: Kim can sign in on the web as the same person')
            expect(m.locator('#signups h3')).to_have_text('Account requests (1)')
            row = m.locator('#main > table tr', has=m.locator('td.mono', has_text=re.compile('^Kim$')))
            expect(row).to_have_count(1)
            expect(row).to_contain_text('active')
            expect(row).to_contain_text('Kim Field')                             # the person's own name, not the request's
            acct = self.users()['Kim']
            self.assertEqual((acct.get('no_account'), acct['person'], acct['has_password']), (None, kim.person, True))
            self.assertEqual(sorted(self.users()), ['Kim', 'ali', 'boss'])       # nobody became two
            # the plain request next to it is approved as ever: a new person
            plain.get_by_role('button', name='Approve', exact=True).click()
            expect(m.locator('#toast')).to_contain_text('Approved: zaid can sign in now')

            # ---- the requester signs in with what they typed and chose, and is Kim
            k = browser.new_context(viewport={'width': 390, 'height': 844}).new_page()
            kerr = PageErrors(k)
            k.goto(self.base + '/admin.html')
            k.locator('#kov input[name=username]').fill('kim')
            k.locator('#kov input[name=password]').fill('kim chose this one')
            k.get_by_role('button', name='Sign in').click()
            k.wait_for_function("() => typeof K !== 'undefined' && K.me && K.me.user.username === 'Kim'")
            self.assertEqual(k.evaluate('K.me.user.person'), kim.person)
            kerr.leave()
            expect(self.mine(k, '11LAB70AA502')).to_contain_text('kim was here')
            self.assertEqual(k.locator('#main .card.mine').count(), 1)

            # ---- Remove devices (as an admin's app does it) ends the web session too, and the list says so
            self.assertEqual(self.admin('POST', f'/api/persons/{ali.person}', {'active': False})[0], 200)
            self.assertEqual(u.evaluate("() => fetch('/api/me').then(r => r.status)"), 401)
            merr.leave(); m.reload()
            row = m.locator('#main > table tr', has=m.locator('td.mono', has_text=re.compile('^ali$')))
            expect(row).to_contain_text('deactivated')
            expect(row.get_by_role('button', name='Activate')).to_have_count(1)
            self.assertEqual((m.locator('#injected').count(), m.evaluate('window.pwned')), (0, None))
            self.assertEqual(list(merr), [])
            self.assertEqual(list(uerr), [])
            self.assertEqual(list(kerr), [])
            browser.close()

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
