"""The Flatpak's About names the commit it was built from: Flatpak builds a copy of the source without .git, so
apps/gnome/flatpak/build.sh (and CI, .github/workflows/arm64.yml) hand the commit to the manifest's build in
apps/gnome/flatpak/buildinfo.flags, which the build passes to nim (platform/linux/src/kksl/buildinfo.nim)."""
import os, shutil, signal, stat, subprocess, tempfile, time, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
FLATPAK = os.path.join(REPO, 'apps', 'gnome', 'flatpak')
FLAGS = os.path.join(FLATPAK, 'buildinfo.flags')


def read(*p):
    with open(os.path.join(REPO, *p)) as f:
        return f.read()


class FlatpakCommit(unittest.TestCase):
    def test_build_sh_hands_the_commit_to_the_builder_and_removes_it_after(self):
        if not os.path.isdir(os.path.join(REPO, '.git')) and not os.path.isfile(os.path.join(REPO, '.git')):
            self.skipTest('not a git checkout')
        head = subprocess.run(['git', '-C', REPO, 'rev-parse', 'HEAD'], capture_output=True, text=True, check=True).stdout.strip()
        dirty = 'true' if subprocess.run(['git', '-C', REPO, 'status', '--porcelain', '--', '.'], capture_output=True,
                                         text=True, check=True).stdout.strip() else 'false'
        self.assertFalse(os.path.exists(FLAGS), 'a buildinfo.flags is left from an earlier build')
        d = tempfile.mkdtemp()
        try:
            out = os.path.join(d, 'seen')
            fake = os.path.join(d, 'flatpak')   # what the builder would read: the flags file, and its arguments
            with open(fake, 'w') as f:
                f.write(f'#!/bin/sh\n{{ cat "{FLAGS}" 2>/dev/null || echo none; echo "$@"; }} > "{out}"\n')
            os.chmod(fake, os.stat(fake).st_mode | stat.S_IEXEC)
            subprocess.run([os.path.join(FLATPAK, 'build.sh'), '--user', '--force-clean', 'build'], check=True,
                           env=dict(os.environ, PATH=d + os.pathsep + os.environ['PATH']))
            flags, args = open(out).read().splitlines()
            self.assertEqual(flags, f'-d:kksCommit={head} -d:kksDirty={dirty}')
            self.assertEqual(args, 'run org.flatpak.Builder --user --force-clean build '
                                   + os.path.join(FLATPAK, 'io.github._5wHN28Dg.walkdown.yml'))
            self.assertFalse(os.path.exists(FLAGS), 'build.sh left buildinfo.flags behind')
        finally:
            shutil.rmtree(d)

    def mini(self, d, git=True):
        """a small copy of the repository's layout with build.sh in it (a git repository with one commit, or not)"""
        root = os.path.join(d, 'repo with space')
        os.makedirs(os.path.join(root, 'apps', 'gnome', 'flatpak'))
        shutil.copy(os.path.join(FLATPAK, 'build.sh'), os.path.join(root, 'apps', 'gnome', 'flatpak', 'build.sh'))
        with open(os.path.join(root, '.gitignore'), 'w') as f:
            f.write('apps/gnome/flatpak/buildinfo.flags\n')
        if git:
            env = dict(os.environ, GIT_AUTHOR_NAME='t', GIT_AUTHOR_EMAIL='t@e.org', GIT_COMMITTER_NAME='t',
                       GIT_COMMITTER_EMAIL='t@e.org')
            for c in (['init', '-q'], ['add', '-A'], ['commit', '-qm', 'one']):
                subprocess.run(['git', '-C', root] + c, check=True, env=env, capture_output=True)
        return root

    def run_build(self, root, d, extra_path=None, sleep=0, kill_after=None):
        """build.sh with a fake flatpak that records the flags file: → (flags or 'none', exit code)"""
        out = os.path.join(d, 'seen')
        bindir = os.path.join(d, 'bin')
        os.makedirs(bindir, exist_ok=True)
        flags = os.path.join(root, 'apps', 'gnome', 'flatpak', 'buildinfo.flags')
        with open(os.path.join(bindir, 'flatpak'), 'w') as f:
            f.write(f'#!/bin/sh\n{{ cat "{flags}" 2>/dev/null || echo none; }} > "{out}"\nsleep {sleep}\n')
        os.chmod(os.path.join(bindir, 'flatpak'), 0o755)
        path = os.pathsep.join(([extra_path] if extra_path else []) + [bindir, os.environ['PATH']])
        p = subprocess.Popen([os.path.join(root, 'apps', 'gnome', 'flatpak', 'build.sh'), 'build'],
                             env=dict(os.environ, PATH=path, CDPATH='/'))
        if kill_after is not None:
            time.sleep(kill_after)
            p.send_signal(signal.SIGTERM)
        rc = p.wait(30)
        self.assertFalse(os.path.exists(flags), 'build.sh left buildinfo.flags behind')
        return open(out).read().strip(), rc

    def test_local_changes_and_no_git(self):
        d = tempfile.mkdtemp()
        try:
            root = self.mini(d)
            head = subprocess.run(['git', '-C', root, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
            self.assertEqual(self.run_build(root, d), (f'-d:kksCommit={head} -d:kksDirty=false', 0))
            with open(os.path.join(root, 'new.txt'), 'w') as f:       # a new file the commit doesn't hold
                f.write('x')
            self.assertEqual(self.run_build(root, d), (f'-d:kksCommit={head} -d:kksDirty=true', 0))
            os.remove(os.path.join(root, 'new.txt'))
            # a git whose status fails can't say the checkout is clean
            fake = os.path.join(d, 'fakegit')
            os.makedirs(fake)
            real = shutil.which('git')
            with open(os.path.join(fake, 'git'), 'w') as f:
                f.write(f'#!/bin/sh\nfor a in "$@"; do [ "$a" = status ] && exit 128; done\nexec "{real}" "$@"\n')
            os.chmod(os.path.join(fake, 'git'), 0o755)
            self.assertEqual(self.run_build(root, d, extra_path=fake), (f'-d:kksCommit={head} -d:kksDirty=true', 0))
        finally:
            shutil.rmtree(d)
        d = tempfile.mkdtemp()
        try:                       # not a git checkout: no file, the app says "commit unknown"
            self.assertEqual(self.run_build(self.mini(d, git=False), d), ('none', 0))
        finally:
            shutil.rmtree(d)

    def test_an_interrupted_build_leaves_no_flags(self):
        # dash runs no EXIT trap for a signal: the file was left, and a later build of another commit named this one
        d = tempfile.mkdtemp()
        try:
            root = self.mini(d)
            flags, rc = self.run_build(root, d, sleep=2, kill_after=0.7)
            self.assertTrue(flags.startswith('-d:kksCommit='))
            self.assertNotEqual(rc, 0)
        finally:
            shutil.rmtree(d)

    def test_the_manifest_and_ci_use_it(self):
        manifest = read('apps', 'gnome', 'flatpak', 'io.github._5wHN28Dg.walkdown.yml')
        self.assertIn('nim c -d:release -d:flatpak $(cat flatpak/buildinfo.flags 2>/dev/null) -o:/app/bin/walkdown', manifest)
        ci = read('.github', 'workflows', 'arm64.yml')
        job = ci[ci.index('flatpak-arm64:'):]
        write = job.index('-d:kksCommit=$GITHUB_SHA -d:kksDirty=false" > apps/gnome/flatpak/buildinfo.flags')
        self.assertLess(write, job.index('flatpak/flatpak-github-actions/flatpak-builder@'))
        # never committed (a stale one would name the wrong commit)
        self.assertIn('apps/gnome/flatpak/buildinfo.flags', read('.gitignore').splitlines())

    def test_a_builds_own_files_do_not_make_the_next_build_count_as_changed(self):
        # build.sh counts untracked files as local changes: the builder's state, output and bundle must be ignored
        # (the README's command builds with --state-dir=state into build/ in the repository's root)
        for p in ('.flatpak-builder/cache/x', 'state/cache/x', 'build/files/x', 'build-flatpak/x', 'walkdown.flatpak',
                  'walkdown-aarch64.flatpak', 'apps/gnome/flatpak/buildinfo.flags'):
            r = subprocess.run(['git', '-C', REPO, 'check-ignore', '-q', '--no-index', p])
            self.assertEqual(r.returncode, 0, p + ' is not ignored')


if __name__ == '__main__':
    unittest.main()
