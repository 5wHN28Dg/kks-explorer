"""tools/plant_release.py publishes a Walkdown Plant release (decision 0054 §8) only when Walkdown's own releases stay
GitHub's latest (Walkdown's updater reads releases/latest), only from a clean pushed checkout whose packages carry its
commit without local changes, only when CI on that commit is green, and only as plant-vVERSION with --latest=false.
Without --publish it is a dry run. gh is never really called: a fake answers (no release is ever made), and no real key
is used anywhere. The same CI and latest gates now guard tools/release.py (Walkdown), which passes --latest.
  .venv/bin/python -m unittest tests.test_plant_release"""
import io, json, os, re, shutil, subprocess, sys, tempfile, unittest, zipfile
from contextlib import redirect_stdout
from unittest import mock

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, os.path.join(REPO, 'tools'))
import plant_release  # noqa: E402
import release  # noqa: E402

GIT_ENV = {'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@example.org', 'GIT_COMMITTER_NAME': 't',
           'GIT_COMMITTER_EMAIL': 't@example.org', 'GIT_CONFIG_GLOBAL': os.devnull, 'GIT_CONFIG_NOSYSTEM': '1'}

PRESETS = '''[preset.0]
name="Android"
[preset.0.options]
version/code=10203
version/name="1.2.3"
[preset.1]
name="Windows"
'''


class FakeGh:
    """GitHub as gh shows it: the latest release, the CI runs on each commit; records what was asked"""

    def __init__(self):
        self.latest = 'v0.10.4'
        self.runs = {}            # commit -> [run]
        self.calls = []
        self.create_makes_latest = False
        self.create_fails = False

    def __call__(self, cmd):
        self.calls.append(cmd)
        ok = lambda out='': subprocess.CompletedProcess(cmd, 0, out, '')  # noqa: E731
        if cmd[1] == 'api' and cmd[2].endswith('/releases/latest'):
            if not self.latest:
                return subprocess.CompletedProcess(cmd, 1, '', 'gh: Not Found (HTTP 404)')
            return ok(self.latest + '\n')
        if cmd[1:3] == ['run', 'list']:
            return ok(json.dumps(self.runs.get(cmd[cmd.index('--commit') + 1], [])))
        if cmd[1:3] == ['release', 'create']:
            if self.create_makes_latest:
                self.latest = cmd[3]
            if self.create_fails:
                return subprocess.CompletedProcess(cmd, 1, '', 'upload failed')
            return ok()
        if cmd[1:3] == ['release', 'edit'] and '--latest' in cmd:
            self.latest = cmd[3]
            return ok()
        raise AssertionError(f'unexpected gh call {cmd}')

    def created(self):
        return [c for c in self.calls if c[1:3] == ['release', 'create']]


def pe(machine, tail=b''):
    """a stand-in Windows exe: the DOS header pointing at a PE header with this machine, then `tail`"""
    return b'MZ' + bytes(0x3A) + (0x40).to_bytes(4, 'little') + b'PE\0\0' + machine.to_bytes(2, 'little') + tail


def cert(cn):
    """a throwaway self-signed certificate (DER) with this CN: never a real key"""
    import datetime
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    k = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(x509.oid.NameOID.COMMON_NAME, cn)])
    now = datetime.datetime.now(datetime.timezone.utc)
    c = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(k.public_key())
         .serial_number(1).not_valid_before(now).not_valid_after(now + datetime.timedelta(days=1)).sign(k, hashes.SHA256()))
    return c.public_bytes(serialization.Encoding.DER)


def green(*names):
    return [{'workflowName': n, 'status': 'completed', 'conclusion': 'success', 'url': 'u'} for n in names]


class PlantRelease(unittest.TestCase):
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
        self.write('VERSION', '0.10.4\n')
        self.write('apps/plant3d/project.godot', '[application]\n\nconfig/name="Walkdown Plant"\nconfig/version="1.2.3"\n')
        self.write('apps/plant3d/export_presets.cfg', PRESETS)
        self.head = self.commit('1.2.3')
        self.git(self.repo, 'push', '-q', 'origin', 'HEAD:main')
        self.gh = FakeGh()
        self.apk_dn = 'CN=Walkdown Plant'
        self.gh.runs[self.head] = green('Tests', 'Policy', 'Walkdown Plant app')

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

    def packages(self, commit=None, changes=False, publisher='CN=Walkdown', arch='x64', machine=0x8664, signed=True,
                 cer='Walkdown'):
        """stand-ins for the APK and the MSIX: zips carrying build.sh's build_info.json where Godot puts it"""
        info = ('{"format": "walkdown-plant-build", "commit": "%s", "changes": %s}\n'
                % (commit or self.head, 'true' if changes else 'false')).encode()
        d = os.path.join(self.tmp, 'dist')
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d)
        with zipfile.ZipFile(os.path.join(d, 'walkdown-plant.apk'), 'w', zipfile.ZIP_DEFLATED) as z:
            z.writestr('AndroidManifest.xml', b'\0manifest')
            z.writestr('assets/built/build_info.json', info)
        with zipfile.ZipFile(os.path.join(d, 'WalkdownPlant.msix'), 'w') as z:
            z.writestr('AppxManifest.xml', ('<Package><Identity Name="WalkdownPlant" Publisher="%s" Version="1.2.3.0" '
                                            'ProcessorArchitecture="%s" /></Package>' % (publisher, arch)).encode())
            z.writestr('WalkdownPlant.exe', pe(machine, b'\0engine\0GDPC\0' + info + b'\0more'))
            if signed:
                z.writestr('AppxSignature.p7x', b'PKCX')
        with open(os.path.join(d, 'windows-msix.cer'), 'wb') as f:
            f.write(cert(cer))
        return d

    def run_main(self, args):
        """plant_release.py on the test repository with gh faked: -> (exit message or None, stdout)"""
        real_run = subprocess.run

        def run(cmd, *a, **kw):
            if cmd[0] == 'gh':
                r = self.gh(cmd)
                if kw.get('check') and r.returncode:
                    raise subprocess.CalledProcessError(r.returncode, cmd)
                return r
            return real_run(cmd, *a, **kw)
        out = io.StringIO()
        with mock.patch.object(plant_release, 'ROOT', self.repo), \
                mock.patch.object(plant_release, 'apk_signer', side_effect=lambda p: self.apk_dn), \
                mock.patch.object(subprocess, 'run', side_effect=run), redirect_stdout(out):
            try:
                plant_release.main(args)
            except SystemExit as e:
                return str(e.code), out.getvalue()
        return None, out.getvalue()

    def test_a_dry_run_checks_everything_and_publishes_nothing(self):
        err, out = self.run_main(['1.2.3', self.packages()])
        self.assertIsNone(err, err)
        self.assertIn('Dry run', out)
        self.assertEqual(self.gh.created(), [])
        # it did ask GitHub about CI on the release commit and about the latest release
        self.assertTrue(any(c[1:3] == ['run', 'list'] and self.head in c for c in self.gh.calls))
        self.assertTrue(any(c[1] == 'api' for c in self.gh.calls))
        self.assertIn('Missing (not in this release): WalkdownPlant-arm64.msix, walkdown-plant.flatpak', out)

    def test_publish_makes_plant_tag_not_latest_on_the_release_commit(self):
        err, out = self.run_main(['1.2.3', self.packages(), '--publish', '--yes'])
        self.assertIsNone(err, err)
        [cmd] = self.gh.created()
        self.assertEqual(cmd[3], 'plant-v1.2.3')
        self.assertIn('--latest=false', cmd)
        self.assertNotIn('--latest', cmd)
        self.assertEqual(cmd[cmd.index('--target') + 1], self.head)
        self.assertEqual(self.gh.latest, 'v0.10.4')
        self.assertIn('the latest release is still v0.10.4', out)

    def test_refuses_when_latest_is_not_a_walkdown_release(self):
        for latest in ('plant-v1.2.2', 'v1.2', 'nightly', ''):
            self.gh.latest = latest
            err, _ = self.run_main(['1.2.3', self.packages(), '--publish', '--yes'])
            self.assertIn('not a Walkdown vX.Y.Z', err or '', latest)
            self.assertEqual(self.gh.created(), [])

    def test_a_release_that_became_latest_is_undone(self):
        self.gh.create_makes_latest = True
        err, _ = self.run_main(['1.2.3', self.packages(), '--publish', '--yes'])
        self.assertIn('was made latest again', err or '')
        self.assertEqual(self.gh.latest, 'v0.10.4')
        self.assertEqual(self.gh.calls[-1][1:4], ['release', 'edit', 'v0.10.4'])

    def test_ci_must_be_green(self):
        d = self.packages()
        for runs, says in ((green('Tests')[:0], 'no CI run'),
                           ([{'workflowName': 'Tests', 'status': 'in_progress', 'conclusion': '', 'url': 'u'}],
                            'has not finished'),
                           (green('Policy') + [{'workflowName': 'Tests', 'status': 'completed',
                                                'conclusion': 'failure', 'url': 'https://x/1'}], 'is failure'),
                           ([{'workflowName': 'Tests', 'status': 'completed', 'conclusion': 'cancelled', 'url': 'u'}],
                            'is cancelled')):
            self.gh.runs[self.head] = runs
            err, _ = self.run_main(['1.2.3', d, '--publish', '--yes'])
            self.assertIn(says, err or '')
            self.assertEqual(self.gh.created(), [])
        # a job left out by its condition is fine
        self.gh.runs[self.head] = green('Walkdown Plant app') + [{'workflowName': 'X', 'status': 'completed',
                                                       'conclusion': 'skipped', 'url': 'u'}]
        self.assertIsNone(self.run_main(['1.2.3', d])[0])

    def test_ci_must_have_run_the_plants_workflow(self):
        """a tag push runs only Policy: green Policy alone is no proof"""
        self.gh.runs[self.head] = green('Policy')
        err, _ = self.run_main(['1.2.3', self.packages()])
        self.assertIn('CI Walkdown Plant app never ran', err)

    def test_a_commit_pushed_only_as_its_tag_is_refused(self):
        self.write('c.txt', 'c')
        local = self.commit('only tagged')
        self.git(self.repo, 'tag', 'plant-v1.2.3')
        self.git(self.repo, 'push', '-q', 'origin', 'plant-v1.2.3')
        self.gh.runs[local] = green('Policy', 'Walkdown Plant app')
        err, _ = self.run_main(['1.2.3', self.packages(commit=local)])
        self.assertIn('is not on origin/main', err)

    def test_msix_must_be_walkdowns_and_of_its_architecture(self):
        err, _ = self.run_main(['1.2.3', self.packages(publisher='CN=KKS Explorer Test')])
        self.assertIn('publisher is CN=KKS Explorer Test, not CN=Walkdown', err)
        d = self.packages()
        shutil.copy(os.path.join(d, 'WalkdownPlant.msix'), os.path.join(d, 'WalkdownPlant-arm64.msix'))
        err, _ = self.run_main(['1.2.3', d])
        self.assertIn('WalkdownPlant-arm64.msix: is for x64, not arm64', err)

    def test_packages_must_be_what_their_names_say(self):
        for kw, says in (({'machine': 0xAA64}, 'WalkdownPlant.exe is not an x64 program'),
                         ({'signed': False}, 'WalkdownPlant.msix: is not signed'),
                         ({'cer': 'KKS Explorer Test'}, 'windows-msix.cer is CN=KKS Explorer Test, not CN=Walkdown')):
            err, _ = self.run_main(['1.2.3', self.packages(**kw)])
            self.assertIn(says, err or '', kw)
        for dn in ('CN=Android Debug,O=Android,C=US', None):
            self.apk_dn = dn
            err, _ = self.run_main(['1.2.3', self.packages()])
            self.assertIn('walkdown-plant.apk is signed by', err or '')
            self.assertIn('not CN=Walkdown Plant', err)

    def test_a_dir_without_a_package_is_refused(self):
        d = self.packages()
        os.remove(os.path.join(d, 'walkdown-plant.apk'))
        os.remove(os.path.join(d, 'WalkdownPlant.msix'))
        self.assertIn('no APK or MSIX package', self.run_main(['1.2.3', d])[0])

    def test_packages_must_be_within_their_size_budget(self):
        # the user, 2026-10-23: the APK at most 150 MB, the desktop packages (MSIX, Flatpak) about 300 MB
        MB = 1_000_000
        self.assertEqual(plant_release.MAX_BYTES, {'walkdown-plant.apk': 150 * MB, 'WalkdownPlant.msix': 300 * MB,
                                                   'WalkdownPlant-arm64.msix': 300 * MB,
                                                   'walkdown-plant.flatpak': 300 * MB})
        self.assertEqual(set(plant_release.MAX_BYTES) | {'windows-msix.cer'}, set(plant_release.FILES))
        d = self.packages()
        apk, msix = (os.path.getsize(os.path.join(d, n)) for n in ('walkdown-plant.apk', 'WalkdownPlant.msix'))
        # at its budget it passes; one byte over, it is refused, and only the package over its own budget
        with mock.patch.dict(plant_release.MAX_BYTES, {'walkdown-plant.apk': apk, 'WalkdownPlant.msix': msix}):
            self.assertIsNone(self.run_main(['1.2.3', d])[0])
        with mock.patch.dict(plant_release.MAX_BYTES, {'walkdown-plant.apk': apk - 1, 'WalkdownPlant.msix': msix}):
            err, _ = self.run_main(['1.2.3', d])
        self.assertIn('walkdown-plant.apk is', err or '')
        self.assertIn('over its budget', err)
        self.assertNotIn('WalkdownPlant.msix is', err)
        with mock.patch.dict(plant_release.MAX_BYTES, {'WalkdownPlant.msix': msix - 1}):
            self.assertIn('WalkdownPlant.msix is', self.run_main(['1.2.3', d])[0] or '')
        # the real budgets: a desktop package of 200 MB passes where an APK of 200 MB would not
        big = {'walkdown-plant.flatpak': os.path.join(self.tmp, 'big')}
        with open(big['walkdown-plant.flatpak'], 'wb') as f:
            f.truncate(200 * MB)
        self.assertEqual(plant_release.size_problems(big), [])
        self.assertEqual(len(plant_release.size_problems({'walkdown-plant.apk': big['walkdown-plant.flatpak']})), 1)

    def test_a_failed_create_still_checks_latest(self):
        self.gh.create_makes_latest = self.gh.create_fails = True
        err, _ = self.run_main(['1.2.3', self.packages(), '--publish', '--yes'])
        self.assertIn('was made latest again', err or '')
        self.assertEqual(self.gh.latest, 'v0.10.4')

    def test_packages_of_another_commit_or_with_changes_are_refused(self):
        err, _ = self.run_main(['1.2.3', self.packages(commit='e' * 40)])
        self.assertIn('walkdown-plant.apk was not built from the release commit', err)
        self.assertIn('WalkdownPlant.msix was not built from the release commit', err)
        err, _ = self.run_main(['1.2.3', self.packages(changes=True)])
        self.assertIn('with local changes', err)
        d = self.packages()
        with zipfile.ZipFile(os.path.join(d, 'walkdown-plant.apk'), 'w') as z:
            z.writestr('assets/other.json', self.head)
        self.assertIn('has no assets/', self.run_main(['1.2.3', d])[0])

    def test_checkout_must_be_clean_and_pushed_and_the_tag_its_own(self):
        d = self.packages()
        self.write('stray.txt', 'x')
        self.assertIn('changes or new files', self.run_main(['1.2.3', d])[0])
        os.remove(os.path.join(self.repo, 'stray.txt'))
        # origin's plant-v1.2.3 on another commit
        self.write('b.txt', 'b')
        later = self.commit('later')
        self.git(self.repo, 'push', '-q', 'origin', 'HEAD:main')
        self.git(self.repo, 'tag', 'plant-v1.2.3', self.head)
        self.git(self.repo, 'push', '-q', 'origin', 'plant-v1.2.3')
        self.gh.runs[later] = green('Tests')
        err, _ = self.run_main(['1.2.3', self.packages(commit=later)])
        self.assertIn(f'tag plant-v1.2.3 names {self.head[:12]}', err)
        # an unpushed commit
        self.git(self.repo, 'checkout', '-q', '--detach', self.head)
        self.write('c.txt', 'c')
        local = self.commit('local')
        self.gh.runs[local] = green('Tests')
        self.git(self.repo, 'push', '-q', '--delete', 'origin', 'plant-v1.2.3')
        self.assertIn('not pushed', self.run_main(['1.2.3', self.packages(commit=local)])[0])

    def test_version_must_be_the_apps(self):
        err, _ = self.run_main(['1.2.4', self.packages()])
        self.assertIn("the app's version (apps/plant3d/project.godot) is 1.2.3, not 1.2.4", err)
        self.assertIn('VERSION looks like', self.run_main(['1.2', self.packages()])[0])
        # the export presets must agree with project.godot
        self.write('apps/plant3d/export_presets.cfg', PRESETS.replace('version/code=10203', 'version/code=1'))
        self.commit('code')
        self.git(self.repo, 'push', '-q', 'origin', 'HEAD:main')
        self.assertIn("version/code is 1, not 10203", plant_release.app_version(self.repo)[1][0])

    def test_bump_sets_every_version(self):
        plant_release.bump('2.0.11', self.repo)
        self.assertEqual(plant_release.app_version(self.repo), ('2.0.11', []))
        with open(os.path.join(self.repo, 'apps/plant3d/export_presets.cfg')) as f:
            self.assertIn('version/code=20011\n', f.read())
        with self.assertRaises(SystemExit):
            plant_release.bump('2.0', self.repo)


class ThisRepository(unittest.TestCase):
    def test_the_apps_versions_agree(self):
        v, out = plant_release.app_version(REPO)
        self.assertRegex(v, plant_release.VERSION_RE)
        self.assertEqual(out, [])

    def test_policy_runs_on_plant_tags_too(self):
        with open(os.path.join(REPO, '.github', 'workflows', 'policy.yml')) as f:
            tags = re.search(r"^\s+tags: \[(.*)\]", f.read(), re.M).group(1)
        self.assertIn("'v*'", tags)
        self.assertIn("'plant-v*'", tags)

    def test_no_workflow_releases_or_builds_on_any_tag_but_policy(self):
        """only policy.yml runs on tags: no workflow could publish a release, or make one latest, by itself"""
        d = os.path.join(REPO, '.github', 'workflows')
        for f in sorted(os.listdir(d)):
            with open(os.path.join(d, f)) as fh:
                s = fh.read()
            self.assertNotIn('gh release create', s, f)
            if f != 'policy.yml':
                self.assertNotRegex(s, r'^\s+tags:', f)


class WalkdownRelease(unittest.TestCase):
    """the gates tools/release.py shares (its own use of them: tests/test_release.py)"""

    def test_ci_and_latest_gates(self):
        gh = FakeGh()
        with mock.patch.object(subprocess, 'run', side_effect=lambda cmd, *a, **kw: gh(cmd)):
            self.assertEqual(release.latest_problems(), [])
            gh.latest = 'plant-v0.1.0'
            self.assertIn('not a Walkdown vX.Y.Z', release.latest_problems()[0])
            self.assertIn('no CI run', release.ci_problems('a' * 40)[0])
            gh.runs['a' * 40] = green('Tests')
            self.assertEqual(release.ci_problems('a' * 40), [])


if __name__ == '__main__':
    unittest.main()
