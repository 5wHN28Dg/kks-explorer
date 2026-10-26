"""The CI jobs install their Ubuntu packages through .github/scripts/apt-install.sh, which bounds every phase in time
(a stalled mirror download once held gnome-e2e for its whole 40 minutes): run against a fake apt-get and sudo, a
stalled download is tried again and the install still happens; a download that stalls every time fails the step in
bounded time and installs nothing; and tests.yml installs nothing with apt-get directly."""
import os, re, shutil, subprocess, tempfile, time, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCRIPT = os.path.join(REPO, '.github', 'scripts', 'apt-install.sh')
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


class AptInstall(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.dir)
        bin_ = os.path.join(self.dir, 'bin')
        os.mkdir(bin_)
        for name, text in (('apt-get', FAKE_APT), ('sudo', FAKE_SUDO)):
            p = os.path.join(bin_, name)
            with open(p, 'w') as f:
                f.write(text)
            os.chmod(p, 0o755)
        self.env = dict(os.environ, FAKE=self.dir, PATH=bin_ + os.pathsep + os.environ['PATH'],
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

    def test_tests_yml_installs_only_through_the_script(self):
        with open(os.path.join(WORKFLOWS, 'tests.yml'), encoding='utf-8') as f:
            text = f.read()
        self.assertEqual(re.findall(r'apt-get[ \t]+(?:\S+[ \t]+)*?install', text), [])
        self.assertGreaterEqual(text.count('.github/scripts/apt-install.sh '), 8)


if __name__ == '__main__':
    unittest.main()
