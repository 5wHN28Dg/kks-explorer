"""The way back in after a forgotten password (#449; the UI and UX policy's "access can be recovered", S9): every
sign-in form says it, in the same words, and what it says is what the server does.
- the web's sign-in screen (common.js K.signIn), and each app's "Join through a server" form (Android Setup.kt
  ServerJoin, GNOME kks_explorer.nim setupScreen, Windows setup.nim) show the sentence;
- it is one plain sentence, with the details behind "How?" (the owner, 2026-11-22, on #462: "Shorten");
- the four copies are word for word the same, the sentence and the details;
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
        how = {'web': literal(self.web, r'K\.forgotPasswordHow = '),
               'apps': literal(self.nim, r'const ForgotPasswordHow\* = '),
               'android': literal(self.kt, r'const val FORGOT_PASSWORD_HOW = ')}
        self.assertEqual(len(set(how.values())), 1, how)
        label = {'apps': literal(self.nim, r'const ForgotPasswordHowLabel\* = '),
                 'android': literal(self.kt, r'const val FORGOT_HOW = ')}
        self.assertEqual(set(label.values()), {'How?'}, label)
        self.assertIn("K.h('summary', null, 'How?')", self.web)
        self.assertEqual(literal(self.nim, r'const ForgotPasswordHideLabel\* = '), literal(self.kt, r'const val FORGOT_HOW_HIDE = '))

    def test_one_plain_sentence(self):
        """the line itself is one short sentence after the question (the owner's "Shorten", #462): who to ask, and for
        what; the rest is behind "How?" """
        s = literal(self.nim, r'const ForgotPassword\* = ')
        rest = s[len('Forgot your password? '):]
        self.assertTrue(rest.endswith('.'), rest)
        self.assertNotIn('. ', rest)
        self.assertNotIn('(', rest)
        self.assertLessEqual(len(rest.split()), 12, rest)
        self.assertNotIn('kks-server', s)

    def test_on_every_sign_in_form(self):
        web = body(self.web, 'K.signIn = ', 'K.signUp = ')
        gnome = body(self.gnome, 'proc setupScreen(', '# a new plant')
        win = body(self.win, 'of "Join through a server":', 'of "Join with a code":')
        kt = body(self.kt, 'private fun ServerJoin(', '\n}\n')
        self.assertIn('K.forgotPassword', web)
        self.assertIn('ForgotPassword', gnome)
        self.assertIn('ForgotPassword', win)
        self.assertIn('FORGOT_PASSWORD', kt)
        # ... each with its "How?" that shows the details: a disclosure (web <details>, GNOME GtkExpander, Android a
        # button that expands and collapses), a button that shows and hides them on Windows
        self.assertIn("K.h('details', {id: 'forgotHow'}, K.h('summary', null, 'How?'), K.h('p', null, K.forgotPasswordHow))", web)
        self.assertIn('gtk_expander_new(ForgotPasswordHowLabel.cstring)', gnome)
        self.assertIn('gtk_expander_set_child(how, label(ForgotPasswordHow', gnome)
        self.assertIn('how.setLabel(if shown: "" else: ForgotPasswordHow)', win)
        self.assertIn('if (how) androidx.compose.foundation.text.selection.SelectionContainer { Dim(FORGOT_PASSWORD_HOW) }', kt)
        self.assertIn('collapse { how = false; true } else expand { how = true; true }', kt)

    def test_command_can_be_copied(self):
        """the details name a command to run: on Android and GNOME they can be selected and copied (the web's is plain
        text, selectable anyway; Windows' static text can't be, tracked as an issue)"""
        self.assertIn('SelectionContainer { Dim(FORGOT_PASSWORD_HOW) }', body(self.kt, 'private fun ServerJoin(', '\n}\n'))
        self.assertIn('label(ForgotPasswordHow, "dim-label", selectable = true)', body(self.gnome, 'proc setupScreen(', '# a new plant'))

    def test_link_not_valid(self):
        """a password link that is used or out of date: the screen says who makes a new one, in the line's words, and
        leads back to sign in"""
        src = body(self.web, "if (h.get('reset'))", 'try {')
        self.assertIn("K.box('Link not valid', `${info.error} Ask your plant's manager for a new one (an admin can also make one for a member).`, 'Back to sign in', done)", src)
        self.assertNotIn('Ask an admin', src)

    def test_not_before_setup(self):
        """before the server has a manager there is nobody to ask: the web's sign-in screen leaves the line out, and its
        "How?\""""
        web = body(self.web, 'K.signIn = ', 'K.signUp = ')
        self.assertIn("cfg?.setup_needed ? null : K.h('p', {id: 'forgotPw'}", web)
        self.assertIn("cfg?.setup_needed ? null : K.h('details', {id: 'forgotHow'}", web)

    def test_what_it_says_is_true(self):
        line = literal(self.nim, r'const ForgotPassword\* = ')
        how = literal(self.nim, r'const ForgotPasswordHow\* = ')
        self.assertEqual(line, "Forgot your password? Ask your plant's manager for a password link.")
        self.assertIn('Use the link within 3 days', how)   # (the link's time is checked again when the password is saved)
        self.assertIn('kks-server reset-password --user NAME', how)
        server = read('platform', 'linux', 'src', 'kksl', 'server.nim')
        # Users → Password link (admin.html) and the command both make a reset token of 3 days
        self.assertIn("ghost('Password link'", read('admin.js'))
        web = body(server, 'proc updateUser*(', '  var newRole')
        self.assertIn('makeToken("reset", uid, 3 * 86400)', web)
        # ... but not for the manager's own account: that one comes from the server's command line
        self.assertIn('if role == "manager"', web)
        self.assertIn('If you are the manager, whoever runs the plant\'s server makes the link', how)
        # ... and an admin's own only from the manager: so the line sends people to the manager, and the details say an
        # admin can make one only for a member
        self.assertIn('(role == "admin" and me.role != "manager")', web)
        self.assertIn('An admin can also make a password link for a member.', how)
        self.assertNotIn('manager or an admin', line + how)
        cmd = body(server, 'of "reset-password":', 'of "web-sign-in":')
        self.assertIn('usage: kks-server reset-password --user NAME', cmd)
        self.assertIn('makeToken("reset", u["id"].i, 3 * 86400)', cmd)
        self.assertIn('within 3 days', cmd)


if __name__ == '__main__':
    unittest.main()
