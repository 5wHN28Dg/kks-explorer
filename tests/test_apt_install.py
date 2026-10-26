"""The CI jobs install their Ubuntu packages through .github/scripts/apt-install.sh, which bounds every phase in time
(a stalled mirror download once held gnome-e2e for its whole 40 minutes): run against a fake apt-get and sudo, a
stalled download is tried again and the install still happens; a download that stalls every time fails the step in
bounded time and installs nothing; and no workflow installs anything with apt-get directly. Playwright's browser
packages (playwright-deps.sh) come from `playwright install-deps --dry-run`, against a fake playwright: the packages
it lists are installed through apt-install.sh and must then show as installed; any other answer fails the step."""
import os, re, shutil, subprocess, tempfile, time, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCRIPT = os.path.join(REPO, '.github', 'scripts', 'apt-install.sh')
PW_SCRIPT = os.path.join(REPO, '.github', 'scripts', 'playwright-deps.sh')
WORKFLOWS = os.path.join(REPO, '.github', 'workflows')

# answers like apt-get; records each call; with --download-only it hangs (exec, so `timeout` ends it) while the
# count in $FAKE/stalls is above 0; an install fails when $FAKE/fail-install exists
FAKE_APT = r'''#!/bin/bash
echo "$*" >> "$FAKE/calls"
case " $* " in
  *" --download-only "*)
    n=$(cat "$FAKE/stalls")
    if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$FAKE/stalls"; exec sleep 100; fi ;;
  *" install "*)
    [ -e "$FAKE/fail-install" ] && exit 100 ;;
esac
exit 0
'''
FAKE_SUDO = '#!/bin/sh\nexec env "$@"\n'
# answers `install-deps --dry-run ENGINE` with $FAKE/pw<n> (its first line the exit code, the rest the output) on
# its n-th call, and records the calls
FAKE_PLAYWRIGHT = r'''#!/bin/bash
echo "$*" >> "$FAKE/pw-calls"
n=$(($(wc -l < "$FAKE/pw-calls")))
f="$FAKE/pw$n"; [ -e "$f" ] || f="$FAKE/pw-last"
tail -n +2 "$f"
exit "$(head -1 "$f")"
'''
MISSING = 'Missing system dependencies (3):\n  fonts-unifont\n  libmanette-0.2-0\n  xvfb\n'
ALL_IN = 'All system dependencies are installed.\n'


class AptInstall(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        bin_ = os.path.join(self.dir, 'bin')
        os.mkdir(bin_)
        for name, text in (('apt-get', FAKE_APT), ('sudo', FAKE_SUDO), ('playwright', FAKE_PLAYWRIGHT)):
            p = os.path.join(bin_, name)
            with open(p, 'w') as f:
                f.write(text)
            os.chmod(p, 0o755)
        self.env = dict(os.environ, FAKE=self.dir, PATH=bin_ + os.pathsep + os.environ['PATH'],
                        PLAYWRIGHT=os.path.join(bin_, 'playwright'),
                        APT_TRIES='3', APT_UPDATE_SECS='5', APT_DOWNLOAD_SECS='1', APT_INSTALL_SECS='5')

    def run_script(self, stalls, *pkgs):
        with open(os.path.join(self.dir, 'stalls'), 'w') as f:
            f.write(str(stalls))
        t0 = time.time()
        r = subprocess.run([SCRIPT, *pkgs], env=self.env, capture_output=True, text=True, timeout=60)
        with open(os.path.join(self.dir, 'calls')) as f:
            calls = f.read().splitlines()
        return r, calls, time.time() - t0

    def kinds(self, calls):
        return ['download' if '--download-only' in c else 'install' if ' install ' in f' {c} ' else 'update'
                for c in calls]

    def test_a_stalled_download_is_tried_again(self):
        r, calls, _ = self.run_script(2, 'ffmpeg', 'mutter')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'download', 'download', 'install'])
        self.assertIn('ffmpeg mutter', calls[-1])
        self.assertIn('--no-install-recommends', calls[-1])
        self.assertEqual(r.stdout.count('::warning::'), 2)

    def test_a_download_that_always_stalls_fails_in_bounded_time(self):
        r, calls, secs = self.run_script(99, 'ffmpeg')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'download', 'download'])   # nothing installed
        self.assertIn('::error::', r.stdout)
        self.assertLess(secs, 20)

    def test_a_failed_install_fails_the_step(self):
        open(os.path.join(self.dir, 'fail-install'), 'w').close()
        r, calls, _ = self.run_script(0, 'ffmpeg')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'install'])   # installing is not repeated

    def test_no_packages_is_an_error(self):
        r = subprocess.run([SCRIPT], env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(r.returncode, 2)

    def run_pw(self, *answers, last=None):
        """playwright-deps.sh webkit, the fake playwright answering (code, output) in turn, then `last`"""
        for i, (code, out) in enumerate(answers, 1):
            with open(os.path.join(self.dir, f'pw{i}'), 'w') as f:
                f.write(f'{code}\n{out}')
        with open(os.path.join(self.dir, 'pw-last'), 'w') as f:
            f.write('%d\n%s' % (last or answers[-1]))
        with open(os.path.join(self.dir, 'stalls'), 'w') as f:
            f.write('0')
        r = subprocess.run([PW_SCRIPT, 'webkit'], env=self.env, capture_output=True, text=True, timeout=60)
        calls = []
        if os.path.exists(os.path.join(self.dir, 'calls')):
            with open(os.path.join(self.dir, 'calls')) as f:
                calls = f.read().splitlines()
        with open(os.path.join(self.dir, 'pw-calls')) as f:
            pw = f.read().splitlines()
        return r, calls, pw

    def test_playwright_packages_go_through_the_script(self):
        r, calls, pw = self.run_pw((1, 'BEWARE: your OS is not officially supported\n' + MISSING), (0, ALL_IN))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(pw, ['install-deps --dry-run webkit'] * 2)    # the list, then the check
        self.assertEqual(self.kinds(calls), ['update', 'download', 'install'])
        self.assertTrue(calls[-1].endswith(' fonts-unifont libmanette-0.2-0 xvfb'), calls[-1])

    def test_playwright_with_everything_installed_installs_nothing(self):
        r, calls, pw = self.run_pw((0, ALL_IN))
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(calls, [])
        self.assertEqual(len(pw), 2)

    def test_playwright_packages_still_missing_fail_the_step(self):
        r, calls, _ = self.run_pw((1, MISSING), (1, 'Missing system dependencies (1):\n  xvfb\n'))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn('::error::still missing', r.stdout)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'install'])

    def test_an_answer_playwright_deps_does_not_know_fails_the_step(self):
        for answer in [(1, "Error: 'apt-get install -s' exited with code 100:\nE: Unable to locate package xvfb\n"),
                       (0, ''),                                          # silence is not "all installed"
                       (1, ALL_IN),                                      # nor is a failed run that says so
                       (0, MISSING),                                     # a list from a run that succeeded
                       (1, 'Missing system dependencies (4):\n  fonts-unifont\n  xvfb\n'),   # a list cut short
                       (1, 'Missing system dependencies (0):\n')]:
            with self.subTest(answer=answer):
                for name in os.listdir(self.dir):
                    if name.startswith('pw') or name == 'calls':
                        os.remove(os.path.join(self.dir, name))
                r, calls, _ = self.run_pw(answer)
                self.assertNotEqual(r.returncode, 0, r.stdout + r.stderr)
                self.assertIn('::error::', r.stderr)
                self.assertEqual(calls, [])                              # nothing installed

    def test_workflows_install_only_through_the_script(self):
        texts = {}
        for name in sorted(os.listdir(WORKFLOWS)):
            with open(os.path.join(WORKFLOWS, name), encoding='utf-8') as f:
                texts[name] = f.read().replace('\\\n', ' ')   # a command continued over lines is one line
        self.assertIn('tests.yml', texts)
        for name, text in texts.items():
            with self.subTest(workflow=name):
                self.assertEqual(re.findall(r'\bapt(?:-get)?[ \t]+(?:\S+[ \t]+)*?install\b', text), [])
                self.assertEqual(re.findall(r'--with-deps|\binstall-deps\b', text), [])
        self.assertGreaterEqual(texts['tests.yml'].count('.github/scripts/apt-install.sh '), 8)
        self.assertIn('.github/scripts/apt-install.sh libgnutls28-dev zlib1g-dev', texts['arm64.yml'])
        self.assertIn('.github/scripts/apt-install.sh flatpak', texts['plant3d-app.yml'])
        # the web jobs: the same browsers as before, their packages through playwright-deps.sh first
        web = texts['tests.yml']
        self.assertIn('engine: [chromium, firefox, webkit]', web)
        self.assertLess(web.index('.github/scripts/playwright-deps.sh ${{ matrix.engine }}'),
                        web.index('.venv/bin/playwright install ${{ matrix.engine }}'))

if __name__ == '__main__':
    unittest.main()
