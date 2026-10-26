"""The CI jobs install their Ubuntu packages through .github/scripts/apt-install.sh, which bounds every phase in time
(a stalled mirror download once held gnome-e2e for its whole 40 minutes): run against a fake apt-get and sudo, a
stalled download is tried again and the install still happens; a download that stalls every time fails the step in
bounded time and installs nothing; and no workflow installs anything with apt-get directly. Playwright's browser
packages (playwright-deps.sh) come from `playwright install-deps --dry-run`, against a fake playwright: the packages
it lists are installed through apt-install.sh and must then show as installed; any other answer fails the step.
After a failed attempt the next starts with another mirror of the runner's list (2026-10-26: Azure's mirror trickled
at 10 to 60 kB/s through all three attempts) after a pause that doubles. The archives are cached across runs
(APT_DEB_CACHE, .github/actions/apt-cache): a cached archive is used only when its SHA-256 is the one apt's lists give,
what a failed run got is kept, and only checked archives are saved (apt-cache-key.sh). Every job that installs
packages restores that cache before and saves it after. tools/download.sh tries a failed download again."""
import fnmatch, hashlib, os, re, shutil, subprocess, tempfile, textwrap, time, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SCRIPT = os.path.join(REPO, '.github', 'scripts', 'apt-install.sh')
PW_SCRIPT = os.path.join(REPO, '.github', 'scripts', 'playwright-deps.sh')
KEY_SCRIPT = os.path.join(REPO, '.github', 'scripts', 'apt-cache-key.sh')
DOWNLOAD = os.path.join(REPO, 'tools', 'download.sh')
VOICE = os.path.join(REPO, 'apps', 'plant3d', 'voice', 'build.sh')
WORKFLOWS = os.path.join(REPO, '.github', 'workflows')

# answers like apt-get; records each call; with --download-only it hangs (exec, so `timeout` ends it) while the
# count in $FAKE/stalls is above 0; an install fails when $FAKE/fail-install exists
# With --print-uris it prints $FAKE/uris (failing when $FAKE/fail-uris exists); a download records the first mirror
# of $APT_MIRROR_LIST and what apt's archive folder held when it began ("have ..."), copies $FAKE/partial/* there
# before a stall, and $FAKE/pool/* there when it succeeds.
FAKE_APT = r'''#!/bin/bash
case " $* " in
  *" --print-uris "*)
    [ -e "$FAKE/fail-uris" ] && exit 100
    [ -e "$FAKE/uris" ] && cat "$FAKE/uris"
    exit 0 ;;
esac
echo "$*" >> "$FAKE/calls"
case " $* " in
  *" --download-only "*)
    [ -f "$APT_MIRROR_LIST" ] && echo "mirror $(head -1 "$APT_MIRROR_LIST" | cut -f1)" >> "$FAKE/log"
    [ -n "${APT_ARCHIVES:-}" ] && echo "have $(cd "$APT_ARCHIVES" && ls | tr '\n' ' ')" >> "$FAKE/log"
    n=$(cat "$FAKE/stalls")
    if [ "$n" -gt 0 ]; then
      echo $((n - 1)) > "$FAKE/stalls"
      [ -d "$FAKE/partial" ] && cp "$FAKE/partial/"* "$APT_ARCHIVES/"
      exec sleep 100
    fi
    [ -d "$FAKE/pool" ] && cp "$FAKE/pool/"* "$APT_ARCHIVES/"
    ;;
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
        self.bin = bin_ = os.path.join(self.dir, 'bin')
        os.mkdir(bin_)
        for name, text in (('apt-get', FAKE_APT), ('sudo', FAKE_SUDO), ('playwright', FAKE_PLAYWRIGHT)):
            p = os.path.join(bin_, name)
            with open(p, 'w') as f:
                f.write(text)
            os.chmod(p, 0o755)
        self.env = dict(os.environ, FAKE=self.dir, PATH=bin_ + os.pathsep + os.environ['PATH'],
                        PLAYWRIGHT=os.path.join(bin_, 'playwright'),
                        APT_TRIES='3', APT_UPDATE_SECS='5', APT_DOWNLOAD_SECS='1', APT_INSTALL_SECS='5',
                        APT_BACKOFF_SECS='0', APT_MIRROR_LIST=os.path.join(self.dir, 'no-mirror-list'))
        self.env.pop('APT_DEB_CACHE', None)
        self.env.pop('APT_ARCHIVES', None)

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

    def test_the_update_can_be_skipped(self):
        self.env['APT_SKIP_UPDATE'] = '1'
        r, calls, _ = self.run_script(1, 'xvfb')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.kinds(calls), ['download', 'download', 'install'])

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
        self.assertEqual(self.kinds(calls), ['download', 'install'])     # the job's apt step updated the lists
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
        self.assertEqual(self.kinds(calls), ['download', 'install'])

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

    # --- another mirror after a failed attempt, a pause that doubles ---

    RUNNER_MIRRORS = ('http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\n'
                      'https://archive.ubuntu.com/ubuntu/\tpriority:2\n'
                      'https://security.ubuntu.com/ubuntu/\tpriority:3\n')

    def mirror_list(self, text=RUNNER_MIRRORS):
        p = os.path.join(self.dir, 'apt-mirrors.txt')
        with open(p, 'w') as f:
            f.write(text)
        self.env['APT_MIRROR_LIST'] = p
        return p

    def log(self):
        p = os.path.join(self.dir, 'log')
        if not os.path.exists(p):
            return []
        with open(p) as f:
            return f.read().splitlines()

    def test_a_failed_attempt_starts_the_next_on_another_mirror(self):
        p = self.mirror_list()
        r, calls, _ = self.run_script(2, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        # Azure's, then archive.ubuntu.com, then (security.ubuntu.com passed over) Azure's again
        self.assertEqual([l for l in self.log() if l.startswith('mirror ')],
                         ['mirror http://azure.archive.ubuntu.com/ubuntu/', 'mirror https://archive.ubuntu.com/ubuntu/',
                          'mirror http://azure.archive.ubuntu.com/ubuntu/'])
        self.assertIn('the next attempt starts with mirror https://archive.ubuntu.com/ubuntu/', r.stdout)
        with open(p) as f:   # every mirror still there, numbered in the order that worked
            self.assertEqual(f.read(), self.RUNNER_MIRRORS)

    def test_the_mirror_that_worked_stays_first(self):
        p = self.mirror_list()
        r, _, _ = self.run_script(1, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(p) as f:
            self.assertEqual(f.read(), 'https://archive.ubuntu.com/ubuntu/\tpriority:1\n'
                                       'https://security.ubuntu.com/ubuntu/\tpriority:2\n'
                                       'http://azure.archive.ubuntu.com/ubuntu/\tpriority:3\n')

    def test_a_failed_update_also_moves_on(self):
        p = self.mirror_list()
        os.remove(os.path.join(self.bin, 'apt-get'))
        with open(os.path.join(self.bin, 'apt-get'), 'w') as f:   # the first update fails, everything else works
            f.write('#!/bin/bash\necho "$*" >> "$FAKE/calls"\n'
                    'case " $* " in *" update "*) [ -e "$FAKE/updated" ] || { touch "$FAKE/updated"; exit 100; } ;; esac\n')
        os.chmod(os.path.join(self.bin, 'apt-get'), 0o755)
        r, calls, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.kinds(calls), ['update', 'update', 'download', 'install'])
        with open(p) as f:
            self.assertTrue(f.read().startswith('https://archive.ubuntu.com/'))

    def test_one_mirror_or_none_changes_nothing(self):
        p = self.mirror_list('http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\n')
        r, _, _ = self.run_script(1, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(p) as f:
            self.assertEqual(f.read(), 'http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\n')
        self.assertNotIn('starts with mirror', r.stdout)

    def test_the_pause_between_attempts_doubles(self):
        self.env['APT_BACKOFF_SECS'] = '1'
        r, calls, secs = self.run_script(2, 'ffmpeg')   # two 1 s stalls, pauses of 1 s and 2 s
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'download', 'download', 'install'])
        self.assertGreaterEqual(secs, 5)

    # --- the archive cache ---

    def debs(self, folder, **files):
        """writes the archives (name -> bytes) into $FAKE/<folder>; returns name -> SHA-256"""
        d = os.path.join(self.dir, folder)
        os.makedirs(d, exist_ok=True)
        out = {}
        for name, data in files.items():
            name = name.replace('__', '_') + '.deb'
            with open(os.path.join(d, name), 'wb') as f:
                f.write(data)
            out[name] = hashlib.sha256(data).hexdigest()
        return out

    def cache_setup(self, uris):
        self.cache = os.path.join(self.dir, 'cache')
        self.archives = os.path.join(self.dir, 'archives')
        os.makedirs(self.archives, exist_ok=True)
        self.env['APT_DEB_CACHE'] = self.cache
        self.env['APT_ARCHIVES'] = self.archives
        with open(os.path.join(self.dir, 'uris'), 'w') as f:
            for name, sha in uris.items():
                f.write(f"'mirror+file:/etc/apt/apt-mirrors.txt/pool/main/x/{name}' {name} 3 SHA256:{sha}\n")

    def fresh_runner(self):
        """a new run: apt's archive folder empty, the log and calls cleared (the cache folder stays)"""
        shutil.rmtree(self.archives)
        os.makedirs(self.archives)
        for n in ('log', 'calls'):
            if os.path.exists(os.path.join(self.dir, n)):
                os.remove(os.path.join(self.dir, n))

    def key(self):
        r = subprocess.run([KEY_SCRIPT, self.cache], capture_output=True, text=True, timeout=30)
        self.assertEqual(r.returncode, 0, r.stderr)
        return r.stdout.strip()

    def test_archives_are_cached_and_used_by_the_next_run(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1', libx__2=b'lx2')
        self.cache_setup(pool)
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('apt cache: 2 archive(s) needed, 0 from the cache', r.stdout)
        self.assertEqual(sorted(os.listdir(self.cache)), ['.used', 'ffmpeg_1.deb', 'libx_2.deb'])
        k1 = self.key()
        self.assertRegex(k1, r'^[0-9a-f]{32}$')
        # the next run: both in apt's folder before its download begins, none fetched
        shutil.rmtree(os.path.join(self.dir, 'pool'))
        self.fresh_runner()
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('apt cache: 2 archive(s) needed, 2 from the cache', r.stdout)
        self.assertIn('have ffmpeg_1.deb libx_2.deb ', self.log())
        self.assertEqual(self.key(), k1)          # the same contents: the same key (saved only once)

    def test_a_cached_archive_with_another_hash_is_never_used(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1')
        self.cache_setup(pool)
        os.makedirs(self.cache)
        with open(os.path.join(self.cache, 'ffmpeg_1.deb'), 'wb') as f:
            f.write(b'BAD')                       # the same size, other bytes: apt alone would take it
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('::warning::apt cache: ffmpeg_1.deb is not the archive', r.stdout)
        self.assertIn('have ', self.log())       # apt's folder was empty when the download began
        with open(os.path.join(self.cache, 'ffmpeg_1.deb'), 'rb') as f:
            self.assertEqual(f.read(), b'ff1')   # replaced by the downloaded one, which matches

    def test_a_downloaded_archive_with_another_hash_is_not_cached(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1')
        self.cache_setup({'ffmpeg_1.deb': hashlib.sha256(b'other').hexdigest()})
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertFalse(os.path.exists(os.path.join(self.cache, 'ffmpeg_1.deb')))
        self.assertEqual(self.key(), '')          # nothing to save

    def test_a_failed_run_keeps_what_it_got(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1', libx__2=b'lx2')
        self.debs('partial', libx__2=b'lx2')
        self.cache_setup(pool)
        r, calls, _ = self.run_script(99, 'ffmpeg')
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'download', 'download'])
        self.assertEqual(sorted(os.listdir(self.cache)), ['.used', 'libx_2.deb'])
        self.assertNotEqual(self.key(), '')

    def test_lines_without_a_sha256_or_with_a_path_are_not_cached(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1')
        self.cache_setup({})
        with open(os.path.join(self.dir, 'uris'), 'w') as f:
            f.write("'http://x/pool/ffmpeg_1.deb' ffmpeg_1.deb 3 MD5Sum:0123456789abcdef0123456789abcdef\n"
                    "'http://x/pool/a.deb' ../a.deb 3 SHA256:%s\n" % ('0' * 64))
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(r.stdout.count('apt cache: not cached'), 2)
        self.assertEqual(self.key(), '')

    def test_when_apt_cannot_list_the_archives_it_installs_without_the_cache(self):
        self.debs('pool', ffmpeg__1=b'ff1')
        self.cache_setup({})
        open(os.path.join(self.dir, 'fail-uris'), 'w').close()
        r, calls, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn('the cache is not used this time', r.stdout)
        self.assertEqual(self.kinds(calls), ['update', 'download', 'install'])

    def test_only_what_was_checked_and_used_is_saved(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1')
        self.cache_setup(pool)
        os.makedirs(self.cache)
        for name in ('stale_0.deb', 'x.deb.part', 'notes.txt'):   # from an older cache, or not archives at all
            with open(os.path.join(self.cache, name), 'w') as f:
                f.write('x')
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        k = self.key()
        self.assertEqual(sorted(os.listdir(self.cache)), ['ffmpeg_1.deb'])
        self.assertRegex(k, r'^[0-9a-f]{32}$')
        # other contents, another key
        with open(os.path.join(self.cache, '.used'), 'w') as f:
            f.write('ffmpeg_1.deb\n')
        with open(os.path.join(self.cache, 'ffmpeg_1.deb'), 'wb') as f:
            f.write(b'ff2')
        self.assertNotEqual(self.key(), k)

    def test_the_cache_key_of_an_empty_or_missing_folder_is_empty(self):
        self.cache = os.path.join(self.dir, 'nothing')
        self.assertEqual(self.key(), '')
        os.makedirs(self.cache)
        self.assertEqual(self.key(), '')

    def action_step(self, marker, env):
        """runs the apt-cache action's step that contains `marker` as the runner would (bash -e), with `env`; returns
        the result and what it wrote to $GITHUB_OUTPUT and $GITHUB_ENV"""
        with open(os.path.join(REPO, '.github', 'actions', 'apt-cache', 'action.yml'), encoding='utf-8') as f:
            action = f.read()
        steps = action.split('\n    - ')
        step = next(st for st in steps if marker in st)
        script = textwrap.dedent(step[step.index('      run: |\n') + len('      run: |\n'):])
        out, genv = os.path.join(self.dir, 'gh-out'), os.path.join(self.dir, 'gh-env')
        for p in (out, genv):
            open(p, 'w').close()
        e = dict(os.environ, GITHUB_OUTPUT=out, GITHUB_ENV=genv, HOME=self.dir,
                 GITHUB_ACTION_PATH=os.path.join(REPO, '.github', 'actions', 'apt-cache'), **env)
        r = subprocess.run(['bash', '-e', '-c', script], env=e, capture_output=True, text=True, timeout=30)
        res = {}
        for p in (out, genv):
            with open(p) as f:
                res.update(l.split('=', 1) for l in f.read().splitlines() if '=' in l)
        return r, step, res

    def poisoned_cache(self):
        d = os.path.join(self.dir, '.cache', 'apt-debs')
        os.makedirs(os.path.join(d, '.used'))                 # a folder where a list was
        os.makedirs(os.path.join(d, 'ro'))
        os.chmod(os.path.join(d, 'ro'), 0o555)                # a folder that cannot simply be emptied
        victim = os.path.join(self.dir, 'victim')
        with open(victim, 'w') as f:
            f.write('mine')
        os.symlink(victim, os.path.join(d, 'ffmpeg_1.deb.part'))   # a link where a download is written
        os.symlink(victim, os.path.join(d, 'libx_2.deb'))
        with open(os.path.join(d, 'ok_1.deb'), 'w') as f:
            f.write('x')
        return d, victim

    def test_a_restored_cache_keeps_only_its_regular_archives(self):
        d, victim = self.poisoned_cache()
        r, _, res = self.action_step('steps.restore.outputs.cache-matched-key',
                                     {'DIR': os.path.join(self.dir, '.cache', 'apt-debs'), 'MATCHED': 'apt-debs-x-'})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(os.listdir(d), ['ok_1.deb'])
        with open(victim) as f:
            self.assertEqual(f.read(), 'mine')
        self.assertEqual(res['APT_DEB_CACHE'], d)
        self.assertIn('apt-debs-x-: 1 archive(s)', r.stdout)

    def test_a_download_is_never_written_through_a_link_in_the_cache(self):
        pool = self.debs('pool', ffmpeg__1=b'ff1')
        self.cache_setup(pool)
        os.makedirs(self.cache)
        victim = os.path.join(self.dir, 'victim')
        with open(victim, 'w') as f:
            f.write('mine')
        os.symlink(victim, os.path.join(self.cache, 'ffmpeg_1.deb.part'))
        r, _, _ = self.run_script(0, 'ffmpeg')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        with open(victim) as f:
            self.assertEqual(f.read(), 'mine')
        self.assertFalse(os.path.islink(os.path.join(self.cache, 'ffmpeg_1.deb')))

    def test_the_key_script_empties_a_folder_it_cannot_write(self):
        self.cache = os.path.join(self.dir, 'c')
        os.makedirs(os.path.join(self.cache, 'ro'))
        open(os.path.join(self.cache, 'ro', 'x.deb'), 'w').close()
        os.chmod(os.path.join(self.cache, 'ro'), 0o555)
        self.assertEqual(self.key(), '')
        self.assertEqual(os.listdir(self.cache), [])

    def save_key(self, event, restored, contents=b'ff1'):
        d = os.path.join(self.dir, '.cache', 'apt-debs')
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, 'ffmpeg_1.deb'), 'wb') as f:
            f.write(contents)
        with open(os.path.join(d, '.used'), 'w') as f:
            f.write('ffmpeg_1.deb\n')
        r, _, res = self.action_step('id: key', {'DIR': d, 'PREFIX': 'apt-debs-u-x-core-', 'GITHUB_EVENT_NAME': event,
                                                 'APT_DEB_CACHE_RESTORED': restored})
        self.assertEqual(r.returncode, 0, r.stderr)
        return res.get('key', '')

    def test_when_the_cache_is_saved(self):
        self.assertRegex(self.save_key('push', ''), r'^apt-debs-u-x-core-[0-9a-f]{32}$')            # main, new
        self.assertRegex(self.save_key('push', 'apt-debs-u-x-core-old'), r'-[0-9a-f]{32}$')          # main, changed
        self.assertRegex(self.save_key('pull_request', ''), r'-[0-9a-f]{32}$')   # a pull request with nothing to start from
        self.assertEqual(self.save_key('pull_request', 'apt-debs-u-x-core-old'), '')   # a pull request's changes: not saved
        same = self.save_key('push', '')
        self.assertEqual(self.save_key('push', same), '')                                            # unchanged

    def test_the_cache_name_reaches_the_key(self):
        """the action's first step, run as on a runner: each job's name is in its cache key (os-release's NAME, read
        in the same shell, once made every job's prefix end in -Ubuntu-, one cache for all)"""
        with open(os.path.join(REPO, '.github', 'actions', 'apt-cache', 'action.yml'), encoding='utf-8') as f:
            action = f.read()
        step = action[action.index('    - id: where\n'):]
        step = step[:step.index('\n    - ', 1)]
        script = textwrap.dedent(step[step.index('      run: |\n') + len('      run: |\n'):])
        out = os.path.join(self.dir, 'out')
        open(out, 'w').close()
        env = dict(os.environ, GITHUB_OUTPUT=out, MODE='restore', HOME=self.dir,
                   **{k: 'gnome-e2e' for k in re.findall(r'^\s+(\w+): \$\{\{ inputs\.name \}\}', step, re.M)})
        r = subprocess.run(['bash', '-e', '-c', script], env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(out) as f:
            lines = dict(l.split('=', 1) for l in f.read().splitlines())
        self.assertRegex(lines['prefix'], r'^apt-debs-[a-z0-9.]+-[0-9.]+-[a-z0-9_]+-gnome-e2e-$')
        self.assertEqual(lines['dir'], os.path.join(self.dir, '.cache', 'apt-debs'))

    # --- tools/download.sh ---

    def run_download(self, fails):
        """tools/download.sh against a fake curl that fails `fails` times (as curl did on downloads.xiph.org)"""
        with open(os.path.join(self.dir, 'curl-fails'), 'w') as f:
            f.write(str(fails))
        with open(os.path.join(self.bin, 'curl'), 'w') as f:
            f.write('#!/bin/bash\necho "$*" >> "$FAKE/curl-calls"\n'
                    'n=$(cat "$FAKE/curl-fails")\n'
                    'while [ $# -gt 0 ]; do [ "$1" = -o ] && out=$2; shift; done\n'
                    'if [ "$n" -gt 0 ]; then echo $((n - 1)) > "$FAKE/curl-fails"; echo part > "$out";\n'
                    '  echo "curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL" >&2; exit 35; fi\n'
                    'echo whole > "$out"\n')
        os.chmod(os.path.join(self.bin, 'curl'), 0o755)
        out = os.path.join(self.dir, 'opus.tar.gz')
        env = dict(self.env, DOWNLOAD_BACKOFF_SECS='1')
        t0 = time.time()
        r = subprocess.run(['sh', DOWNLOAD, 'https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz', out],
                           env=env, capture_output=True, text=True, timeout=60)
        with open(os.path.join(self.dir, 'curl-calls')) as f:
            calls = f.read().splitlines()
        return r, calls, out, time.time() - t0

    def test_a_failed_download_is_tried_again(self):
        r, calls, out, secs = self.run_download(2)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(calls), 3)
        self.assertGreaterEqual(secs, 3)          # pauses of 1 s and 2 s
        with open(out) as f:
            self.assertEqual(f.read(), 'whole\n')
        self.assertFalse(os.path.exists(out + '.part'))
        self.assertIn('--connect-timeout', calls[0])
        self.assertIn('-sSfL', calls[0].split())  # an HTTP error is a failure, not a file

    def test_a_download_that_always_fails_fails_and_leaves_nothing(self):
        r, calls, out, _ = self.run_download(99)
        self.assertEqual(r.returncode, 1)
        self.assertEqual(len(calls), 5)
        self.assertFalse(os.path.exists(out))
        self.assertFalse(os.path.exists(out + '.part'))

    def test_the_voice_sources_are_cached_and_still_checked(self):
        with open(VOICE, encoding='utf-8') as f:
            build = f.read()
        fetches = re.findall(r'^fetch (\S+) (https://\S+) ([0-9a-f]{64})$', build, re.M)
        self.assertEqual(len(fetches), 3)
        self.assertIn('tools/download.sh', build)
        self.assertIn('[ "$got" = "$3" ]', build)   # the SHA-256 check after every fetch, cached or not
        with open(os.path.join(WORKFLOWS, 'plant3d-app.yml'), encoding='utf-8') as f:
            wf = f.read()
        key_step = "grep -E '^fetch ' apps/plant3d/voice/build.sh | sha256sum"
        jobs = split_jobs(wf)
        for job in ('plant3d', 'app-tests', 'voice'):
            text = jobs[job]
            with self.subTest(job=job):
                self.assertIn(key_step, text)
                globs = re.findall(r'~/\.local/kksdev/src/dl/(\S+)', text.split('key: ${{ steps.voice-src.outputs.key }}')[0])
                for name, _, _ in fetches:
                    self.assertTrue(any(fnmatch.fnmatch(name, g) for g in globs), (name, globs))
                self.assertLess(text.index('steps.voice-src.outputs.key'), text.index('WDP_JOBS=4'))   # before the build

    def test_every_job_that_installs_packages_restores_and_saves_the_cache(self):
        n, names = 0, {}
        for wf in sorted(os.listdir(WORKFLOWS)):
            with open(os.path.join(WORKFLOWS, wf), encoding='utf-8') as f:
                text = f.read()
            for job, body in split_jobs(text).items():
                calls = [m.start() for m in re.finditer(r'\.github/scripts/(?:apt-install|playwright-deps)\.sh ', body)]
                if not calls:
                    continue
                n += 1
                with self.subTest(workflow=wf, job=job):
                    restore = re.search(r"- uses: \./\.github/actions/apt-cache[^\n]*\n\s+id: apt-cache\n"
                                        r"(?:\s+if: [^\n]+\n)?\s+with: \{name: ('[^']+'|[\w-]+), mode: restore\}", body)
                    save = re.search(r"- uses: \./\.github/actions/apt-cache[^\n]*\n"
                                     r"\s+if: always\(\) && steps\.apt-cache\.outcome == 'success'[^\n]*\n"
                                     r"\s+with: \{name: ('[^']+'|[\w-]+), mode: save\}", body)
                    self.assertIsNotNone(restore)
                    self.assertIsNotNone(save)
                    self.assertEqual(restore.group(1), save.group(1))
                    self.assertLess(restore.end(), calls[0])
                    self.assertGreater(save.start(), calls[-1])
                    installs = re.findall(r'\.github/scripts/(?:apt-install|playwright-deps)\.sh [^\n]*', body)
                    names.setdefault(restore.group(1), set()).add(tuple(installs))
        self.assertGreaterEqual(n, 10)   # tests.yml's eight, arm64's linux-arm64, plant3d-app's voice
        # a cache name is shared only by jobs that install the same packages (else each would replace the other's)
        for name, sets in names.items():
            self.assertEqual(len(sets), 1, (name, sets))
        self.assertIn('apt-nim', names)


def split_jobs(text):
    """a workflow's jobs: name -> its text"""
    body = text[text.index('\njobs:\n'):]
    parts = re.split(r'^  ([A-Za-z0-9_-]+):\n', body, flags=re.M)
    return dict(zip(parts[1::2], parts[2::2]))


if __name__ == '__main__':
    unittest.main()
