"""The way back in after a forgotten password (#449; the UI and UX policy's "access can be recovered", S9): every
sign-in form says it, in the same words, and what it says is what the server does.
- the web's sign-in screen (common.js K.signIn), and each app's "Join through a server" form (Android Setup.kt
  ServerJoin, GNOME kks_explorer.nim setupScreen, Windows setup.nim) show the sentence;
- the four copies are word for word the same;
- its claims hold: an admin's Users → Password link and the server's `reset-password` command make a one-time link
  that lasts 3 days.
The end-to-end tests check that the line is on screen: test_web_signup.py (web), test_app2.py's join (Android),
test_gnome.py's join (GNOME).
  .venv/bin/python -m unittest tests.test_forgot_password"""
import os, re, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def read(*p):
    with open(os.path.join(REPO, *p), encoding='utf-8') as f:
        return f.read()


def literal(src, pattern):
    """the string literal after `pattern` (a regex ending just before its opening quote), unescaped"""
    m = re.search(pattern + r'"((?:[^"\\]|\\.)*)"', src)
    assert m, pattern
    return re.sub(r'\\(.)', r'\1', m.group(1))


def body(src, start, end):
    """the text from the first `start` to the next `end` after it"""
    i = src.index(start)
    return src[i:src.index(end, i + len(start))]


class ForgotPassword(unittest.TestCase):
    def setUp(self):
        self.web = read('common.js')
        self.nim = read('apps', 'common', 'appstate.nim')
        self.kt = read('android', 'app2', 'src', 'main', 'kotlin', 'kks', 'explorer', 'ui', 'Setup.kt')
        self.gnome = read('apps', 'gnome', 'kks_explorer.nim')
        self.win = read('apps', 'windows', 'src', 'kkswin', 'setup.nim')

    def test_same_words_everywhere(self):
        words = {'web': literal(self.web, r'K\.forgotPassword = '),
                 'apps': literal(self.nim, r'const ForgotPassword\* = '),
                 'android': literal(self.kt, r'const val FORGOT_PASSWORD = ')}
        self.assertEqual(len(set(words.values())), 1, words)
        self.assertTrue(words['web'].startswith('Forgot your password? '), words['web'])

    def test_on_every_sign_in_form(self):
        self.assertIn('K.forgotPassword', body(self.web, 'K.signIn = ', 'K.signUp = '))
        self.assertIn('ForgotPassword', body(self.gnome, 'proc setupScreen(', '# a new plant'))
        self.assertIn('ForgotPassword', body(self.win, 'of "Join through a server":', 'of "Join with a code":'))
        self.assertIn('FORGOT_PASSWORD', body(self.kt, 'private fun ServerJoin(', '\n}\n'))

    def test_command_can_be_copied(self):
        """the line names a command to run: on Android and GNOME it can be selected and copied (the web's is plain text,
        selectable anyway; Windows' static text can't be, tracked as an issue)"""
        self.assertIn('SelectionContainer { Dim(FORGOT_PASSWORD) }', body(self.kt, 'private fun ServerJoin(', '\n}\n'))
        self.assertIn('label(ForgotPassword, "dim-label", selectable = true)', body(self.gnome, 'proc setupScreen(', '# a new plant'))

    def test_not_before_setup(self):
        """before the server has a manager there is nobody to ask: the web's sign-in screen leaves the line out"""
        self.assertIn("cfg?.setup_needed ? null : K.h('p', {id: 'forgotPw'}", body(self.web, 'K.signIn = ', 'K.signUp = '))

    def test_what_it_says_is_true(self):
        s = literal(self.nim, r'const ForgotPassword\* = ')
        self.assertIn('password link', s)
        self.assertIn('3 days', s)
        self.assertIn('kks-server reset-password --user NAME', s)
        server = read('platform', 'linux', 'src', 'kksl', 'server.nim')
        # Users → Password link (admin.html) and the command both make a reset token of 3 days
        self.assertIn("ghost('Password link'", read('admin.js'))
        web = body(server, 'proc updateUser*(', '  var newRole')
        self.assertIn('makeToken("reset", uid, 3 * 86400)', web)
        # ... but not for the manager's own account: that one comes from the server's command line
        self.assertIn('if role == "manager"', web)
        # ... and an admin's own only from the manager: so the line sends people to the manager first, and to an
        # admin only for a member
        self.assertIn('(role == "admin" and me.role != "manager")', web)
        self.assertIn("Ask your plant's manager for a password link (an admin can also make one for a member)", s)
        self.assertNotIn('manager or an admin', s)
        cmd = body(server, 'of "reset-password":', 'of "web-sign-in":')
        self.assertIn('usage: kks-server reset-password --user NAME', cmd)
        self.assertIn('makeToken("reset", u["id"].i, 3 * 86400)', cmd)
        self.assertIn('within 3 days', cmd)


if __name__ == '__main__':
    unittest.main()
