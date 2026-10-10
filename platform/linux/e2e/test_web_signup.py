"""Sign-up with the plant's code in the browser, in all three engines (the user, 2026-10-10): the manager sets the code
in Manage → Users; a person asks for an account from the sign-in screen (a wrong code first), is told the request was
sent, and that it waits when signing in; the Users tab shows the request and its count; the manager approves; the
person signs in. Then a request that is rejected, a name somebody has, and sign-up switched off again.
  /path/to/venv-with-playwright/bin/python platform/linux/e2e/test_web_signup.py [unittest arguments]
$KKS_SERVER names the build (default /tmp/kkslinux/kks_server)."""
import json, os, re, shutil, subprocess, sys, tempfile, time, unittest
from playwright.sync_api import sync_playwright, expect

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
SERVER = os.environ.get('KKS_SERVER', '/tmp/kkslinux/kks_server')
sys.path.insert(0, os.path.dirname(__file__))
from test_web_v2 import free_port, Client, CSP_WATCH, PageErrors

PW = 'a long password'
CODE = 'team-7391-plant'
# a full name that is markup: it must show as text in the manager's list
NAME = 'Ali <b id=injected>H</b><img src=x onerror=pwned=1>'


class WebSignup(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-web-signup-')
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

    def tearDown(self):
        self.server.terminate()
        self.server.wait(5)
        shutil.rmtree(self.dir, ignore_errors=True)

    def request(self, page, code, name, username, password=PW):
        """fill and send the sign-up form (reached from the sign-in screen)"""
        f = page.locator('#kov form')
        for field, v in (('code', code), ('full_name', name), ('position', 'Operator'), ('username', username),
                         ('password', password), ('password2', password)):
            f.locator(f'input[name={field}]').fill(v)
        f.get_by_role('button', name='Send the request').click()

    def engine(self, name):
        with sync_playwright() as p:
            browser = p[name].launch()
            # ---- the manager's browser, and a person's (a phone-sized one, no session)
            mctx = browser.new_context()
            mctx.add_init_script(CSP_WATCH)
            mctx.request.post(self.base + '/api/login', data={'username': 'boss', 'password': PW}, headers={'Origin': self.base})
            m = mctx.new_page()
            merr = PageErrors(m)
            m.on('dialog', lambda d: d.accept('ali2') if d.type == 'prompt' else d.accept())
            uctx = browser.new_context(viewport={'width': 390, 'height': 844})
            uctx.add_init_script(CSP_WATCH)
            u = uctx.new_page()
            uerr = PageErrors(u)

            # sign-up is off: the sign-in screen offers nothing; Manage says so
            u.goto(self.base + '/')
            expect(u.locator('#kov form input[name=username]')).to_be_visible()
            self.assertEqual(u.locator('#signup').count(), 0)
            m.goto(self.base + '/admin.html#users')
            expect(m.locator('#signupState')).to_contain_text('Sign-up is off')
            expect(m.locator('#signups')).to_contain_text('Nobody is waiting, and sign-up is off.')
            expect(m.locator('#un')).to_be_hidden()
            # the manager sets the code: the field is emptied again, and nothing on the page repeats it
            m.locator('#signupCode input[name=code]').fill(CODE)
            m.get_by_role('button', name='Switch sign-up on').click()
            expect(m.locator('#signupState')).to_contain_text('Sign-up is on')
            self.assertEqual(m.locator('#signupCode input[name=code]').input_value(), '')
            self.assertNotIn(CODE, m.content())

            # ---- a person asks for an account
            uerr.leave(); u.reload()
            u.locator('#signup').click()
            expect(u.locator('#kov h1')).to_have_text('Request an account')
            # typed as it is on a phone: neither the code nor the username is capitalised or corrected
            for field in ('code', 'username'):
                self.assertEqual(u.locator(f'#kov input[name={field}]').get_attribute('autocapitalize'), 'none')
            self.assertEqual(u.locator('#kov input[name=password]').get_attribute('autocomplete'), 'new-password')
            # Back and again; a wrong code, passwords that differ, a short one: each said in the form, which stays
            u.locator('#kov button.back').click()
            expect(u.locator('#kov h1')).to_have_text('Test plant')
            u.locator('#signup').click()
            self.request(u, 'not-the-code', NAME, 'ali')
            expect(u.locator('#kov .err')).to_have_text('The request was not accepted. Check the sign-up code with your manager, or try again later.')
            u.locator('#kov input[name=password2]').fill('another password')
            u.locator('#kov input[name=code]').fill(CODE)
            u.get_by_role('button', name='Send the request').click()
            expect(u.locator('#kov .err')).to_have_text('Passwords differ.')
            self.request(u, CODE, NAME, 'ali', 'short')
            expect(u.locator('#kov .err')).to_contain_text('at least 10 characters')
            self.assertEqual(self.boss.req('GET', '/api/signups')['requests'], [])
            self.request(u, CODE, NAME, 'ali')
            expect(u.locator('#kov h1')).to_have_text('Request sent')
            expect(u.locator('#kov .box p')).to_contain_text('An admin has to approve it')
            # signing in before approval says so (and a wrong password says only that it is wrong)
            u.get_by_role('button', name='Back to sign in').click()
            u.locator('#kov input[name=username]').fill('ali')
            u.locator('#kov input[name=password]').fill('not his password')
            u.get_by_role('button', name='Sign in').click()
            expect(u.locator('#kov .err')).to_have_text('Wrong username or password.')
            u.locator('#kov input[name=password]').fill(PW)
            u.get_by_role('button', name='Sign in').click()
            expect(u.locator('#kov .err')).to_have_text("Your account request is waiting for an admin's approval.")
            # a second person asks for the manager's username: told the same as anyone
            u.locator('#signup').click()
            self.request(u, CODE, 'Second Person', 'boss', 'second password 1')
            expect(u.locator('#kov h1')).to_have_text('Request sent')
            u.get_by_role('button', name='Back to sign in').click()
            u.locator('#signup').click()
            self.request(u, CODE, 'Third Person', 'zaid', 'third password 1')
            expect(u.locator('#kov h1')).to_have_text('Request sent')

            # ---- the manager: the Users tab counts the requests on every page, and lists them
            m.goto(self.base + '/admin.html#account')
            expect(m.locator('#un')).to_have_text('3')
            m.locator('#tabs button', has_text='Users').click()
            expect(m.locator('#signups h3')).to_have_text('Account requests (3)')
            expect(m.locator('#un')).to_have_text('3')
            row = m.locator('#signups tr[data-user=ali]')
            expect(row).to_contain_text(NAME)                       # as text
            expect(row).to_contain_text('Operator')
            self.assertEqual(m.locator('#injected').count(), 0)
            self.assertIsNone(m.evaluate('window.pwned'))
            expect(m.locator('#signups tr[data-user=boss]')).to_contain_text('this username exists already')
            # approve: the account is there, the request is not
            row.get_by_role('button', name='Approve').click()
            expect(m.locator('#toast')).to_contain_text('Approved: ali can sign in now')
            expect(m.locator('#signups h3')).to_have_text('Account requests (2)')
            expect(m.locator('#un')).to_have_text('2')
            users = {x['username']: x for x in self.boss.req('GET', '/api/users')['users']}
            self.assertEqual((users['ali']['role'], users['ali']['active'], users['ali']['has_password'], users['ali']['full_name']),
                             ('user', True, True, NAME))
            # the name somebody has: approved under another one (the prompt answers "ali2")
            m.locator('#signups tr[data-user=boss]').get_by_role('button', name='Approve').click()
            expect(m.locator('#toast')).to_contain_text('Approved: ali2 can sign in now')
            # reject (a confirm): the request is deleted
            m.locator('#signups tr[data-user=zaid]').get_by_role('button', name='Reject').click()
            expect(m.locator('#signups')).to_contain_text('Nobody is waiting.')
            expect(m.locator('#un')).to_be_hidden()
            self.assertEqual(sorted(x['username'] for x in self.boss.req('GET', '/api/users')['users']), ['ali', 'ali2', 'boss'])

            # ---- the person signs in with the password they chose
            uerr.leave(); u.goto(self.base + '/admin.html')
            u.locator('#kov input[name=username]').fill('ali')
            u.locator('#kov input[name=password]').fill(PW)
            u.get_by_role('button', name='Sign in').click()
            u.wait_for_function("() => typeof K !== 'undefined' && K.me && K.me.user.username === 'ali'")
            expect(u.locator('#who')).to_contain_text('user')
            self.assertEqual(u.locator('#tabs button', has_text='Users').count(), 0)      # not an admin: no Users tab
            self.assertEqual(u.evaluate("() => fetch('/api/signups').then(r => r.status)"), 403)
            # the rejected one: as if they had never asked
            c3 = browser.new_context()
            self.assertEqual(c3.request.post(self.base + '/api/login', data={'username': 'zaid', 'password': 'third password 1'},
                                             headers={'Origin': self.base}).status, 401)
            self.assertEqual(c3.request.post(self.base + '/api/login', data={'username': 'ali2', 'password': 'second password 1'},
                                             headers={'Origin': self.base}).status, 200)

            # ---- sign-up switched off again: the sign-in screen stops offering it
            m.get_by_role('button', name='Switch sign-up off').click()
            expect(m.locator('#signupState')).to_contain_text('Sign-up is off')
            a = browser.new_context().new_page()
            a.goto(self.base + '/')
            expect(a.locator('#kov form input[name=username]')).to_be_visible()
            self.assertEqual(a.locator('#signup').count(), 0)
            self.assertEqual(list(merr), [])
            self.assertEqual(list(uerr), [])
            browser.close()

    def test_chromium(self): self.engine('chromium')
    def test_firefox(self): self.engine('firefox')
    def test_webkit(self): self.engine('webkit')


if __name__ == '__main__':
    unittest.main()
