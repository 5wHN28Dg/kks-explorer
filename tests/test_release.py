"""tools/release.py signs and publishes only the release commit, as built (the user, 2026-10-15): the checkout it runs
from is clean and at the commit, which origin holds (and its tag vVERSION, if any, names); the GitHub release is created
on that commit; the APK and the MSIX packages carry that commit (a build of another commit, or of an unknown one, is
refused). No real key: signing is replaced by a stub. Android Studio's files are ignored, so a checkout opened in it
still builds as clean.
  .venv/bin/python -m unittest tests.test_release"""
import io, json, os, shutil, subprocess, sys, tempfile, unittest, zipfile
from contextlib import redirect_stdout
from unittest import mock

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, os.path.join(REPO, 'tools'))
import release  # noqa: E402

GIT_ENV = {'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.org', 'GIT_COMMITTER_NAME': 't',
           'GIT_COMMITTER_EMAIL': 't@example.org', 'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1'}


class Release(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, self.tmp)
        env = mock.patch.dict(os.environ, GIT_ENV)
        env.start()
        self.addCleanup(env.stop)
        self.remote = os.path.join(self.tmp, 'remote.git')
        self.repo = os.path.join(self.tmp, 'repo')
        self.git(self.tmp, 'init', '-q', '--bare', '-b', 'main', self.remote)
        self.git(self.tmp, 'clone', '-q', self.remote, self.repo)
        shutil.copy(os.path.join(REPO, '.gitignore'), os.path.join(self.repo, '.gitignore'))
        self.write('VERSION', '1.2.3\n')
        self.head = self.commit('1.2.3')
        self.git(self.repo, 'push', '-q', 'origin', 'HEAD:main')

    def git(self, where, *args):
        return subprocess.run(['git', '-C', where, *args], check=True, capture_output=True, text=True).stdout.strip()

    def write(self, name, text):
        p = os.path.join(self.repo, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as f:
            f.write(text)

    def commit(self, msg):
        self.git(self.repo, 'add', '-A')
        self.git(self.repo, 'commit', '-qm', msg)
        return self.git(self.repo, 'rev-parse', 'HEAD')

    def package(self, name, inner, commit):
        """a stand-in for an APK or MSIX: a zip whose code (inner) names the commit it was built from"""
        d = os.path.join(self.tmp, 'dist')
        os.makedirs(d, exist_ok=True)
        with zipfile.ZipFile(os.path.join(d, name), 'w') as z:
            z.writestr('AndroidManifest.xml', b'\0manifest')
            z.writestr(inner, b'\0code\0' + commit.encode() + b'\0more')
        return os.path.join(d, name)

    def problems(self):
        return release.checkout_problems(self.repo, '1.2.3')

    def test_a_clean_pushed_checkout_is_released(self):
        self.assertEqual(self.problems(), (self.head, []))
        # what Android Studio and IntelliJ leave in a checkout doesn't count as a change
        self.write('.idea/workspace.xml', '<project/>')
        self.write('android/app2/app2.iml', '<module/>')
        self.assertEqual(self.problems(), (self.head, []))

    def test_gitignore_has_the_ide_files(self):
        r = subprocess.run(['git', '-C', REPO, 'check-ignore', '--no-index', '.idea/workspace.xml',
                            'android/app2/app2.iml', 'android/.idea/misc.xml'], capture_output=True, text=True)
        self.assertEqual(r.stdout.split(), ['.idea/workspace.xml', 'android/app2/app2.iml', 'android/.idea/misc.xml'])

    def test_changes_and_new_files_stop_it(self):
        self.write('notes.txt', 'new')
        head, out = self.problems()
        self.assertEqual(len(out), 1)
        self.assertIn('changes or new files', out[0])
        os.remove(os.path.join(self.repo, 'notes.txt'))
        self.write('VERSION', '1.2.4\n')
        self.assertIn('changes or new files', self.problems()[1][0])

    def test_an_unpushed_commit_stops_it(self):
        self.write('a.txt', 'a')
        head = self.commit('local only')
        h, out = self.problems()
        self.assertEqual(h, head)
        self.assertEqual(len(out), 1)
        self.assertIn('not pushed', out[0])
        # on another branch of origin is pushed too (a release branch)
        self.git(self.repo, 'push', '-q', 'origin', 'HEAD:refs/heads/release-1.2.3')
        self.assertEqual(self.problems(), (head, []))

    def test_a_tag_on_another_commit_stops_it(self):
        self.git(self.repo, 'tag', '-a', '-m', 'v', 'v1.2.3')     # annotated, on the release commit: fine
        self.git(self.repo, 'push', '-q', 'origin', 'v1.2.3')
        self.assertEqual(self.problems(), (self.head, []))
        self.write('b.txt', 'b')
        head = self.commit('later')
        self.git(self.repo, 'push', '-q', 'origin', 'HEAD:main')
        h, out = self.problems()
        self.assertEqual(len(out), 1)
        self.assertIn(f"tag v1.2.3 names {self.head[:12]}, not the release commit {head[:12]}", out[0])

    def test_packages_built_from_another_commit_are_refused(self):
        other = 'f' * 40
        good = {'walkdown.apk': self.package('walkdown.apk', 'classes2.dex', self.head),
                'Walkdown.msix': self.package('Walkdown.msix', 'Walkdown.exe', self.head),
                'walkdown.flatpak': os.path.join(self.tmp, 'not-checked.flatpak')}
        self.assertEqual(release.artifact_problems(good, self.head), [])
        out = release.artifact_problems({'walkdown.apk': self.package('walkdown.apk', 'classes.dex', other),
                                         'Walkdown-arm64.msix': self.package('Walkdown-arm64.msix', 'Walkdown.exe', other)},
                                        self.head)
        self.assertEqual(len(out), 2)
        self.assertTrue(all('was not built from the release commit' in p for p in out), out)
        # the commit in some other file of the package is not the program's
        out = release.artifact_problems({'walkdown.apk': self.package('walkdown.apk', 'assets/x.txt', self.head)}, self.head)
        self.assertEqual(len(out), 1)
        self.assertIn('has no classes', out[0])
        with open(os.path.join(self.tmp, 'bad.msix'), 'wb') as f:
            f.write(b'not a zip')
        self.assertIn('not readable', release.artifact_problems({'Walkdown.msix': os.path.join(self.tmp, 'bad.msix')}, self.head)[0])

    def run_main(self, files):
        """release.py VERSION DIR --publish --yes on this repository, signing with a stub (never a real key) and gh
        replaced: -> (exit message or None, the gh command or None)"""
        d = os.path.join(self.tmp, 'out')
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        for name, path in files.items():
            shutil.copy(path, os.path.join(d, name))
        seen = []
        real_run = subprocess.run

        def run(cmd, *a, **kw):
            if cmd[0] == 'gh':
                seen.append(cmd)
                return subprocess.CompletedProcess(cmd, 0)
            return real_run(cmd, *a, **kw)
        with mock.patch.object(release, 'ROOT', self.repo), \
                mock.patch.object(release, 'sign_p256', return_value='c2ln') as sign, \
                mock.patch.object(release, 'verify_p256'), \
                mock.patch.object(release.subprocess, 'run', side_effect=run), \
                mock.patch.dict(os.environ, {'KKS_SIGNING': os.path.join(self.tmp, 'no-keys-here')}), \
                redirect_stdout(io.StringIO()):
            try:
                release.main(['1.2.3', d, '--publish', '--yes'])
            except SystemExit as e:
                self.assertFalse(sign.called, 'signed before refusing')
                return str(e.code), None
        self.assertTrue(sign.called)
        with open(os.path.join(d, 'release.json')) as f:
            self.assertEqual(set(json.load(f)['files']), set(files))
        return None, seen[0] if seen else None

    def test_main_refuses_before_signing_and_publishes_on_the_release_commit(self):
        apk = self.package('walkdown.apk', 'classes.dex', self.head)
        err, gh = self.run_main({'walkdown.apk': apk})
        self.assertIsNone(err)
        self.assertIn('--target', gh)
        self.assertEqual(gh[gh.index('--target') + 1], self.head)
        self.assertEqual(gh[3:4], ['v1.2.3'])
        # a package of another commit
        err, _ = self.run_main({'walkdown.apk': self.package('walkdown.apk', 'classes.dex', 'e' * 40)})
        self.assertIn('was not built from the release commit', err)
        # a checkout with a new file in it
        self.write('stray.txt', 'x')
        err, _ = self.run_main({'walkdown.apk': apk})
        self.assertIn('changes or new files', err)


if __name__ == '__main__':
    unittest.main()
