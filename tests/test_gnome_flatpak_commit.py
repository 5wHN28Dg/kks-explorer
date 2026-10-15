"""The Flatpak's About names the commit it was built from: Flatpak builds a copy of the source without .git, so
apps/gnome/flatpak/build.sh (and CI, .github/workflows/arm64.yml) hand the commit to the manifest's build in
apps/gnome/flatpak/buildinfo.flags, which the build passes to nim (platform/linux/src/kksl/buildinfo.nim)."""
import os, shutil, stat, subprocess, tempfile, unittest

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
