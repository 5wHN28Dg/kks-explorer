"""Walkdown Plant's packages (decision 0054 §8): the MSIX's folder (apps/plant3d/msix/make-msix.sh --layout: the
manifest filled from the certificate and the app's version, the walkdown-plant protocol after the end-of-options
marker as decision 0056 says, no network capability, the logos at their sizes) with a test certificate only, and the
Flatpak's AppStream release entry made from the app's version (apps/plant3d/flatpak/build.sh --metainfo).
  .venv/bin/python -m unittest tests.test_plant_packaging"""
import os, re, shutil, struct, subprocess, sys, tempfile, unittest
import xml.etree.ElementTree as ET

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
APP = os.path.join(REPO, 'apps', 'plant3d')
sys.path.insert(0, os.path.join(REPO, 'tools'))
import plant_release  # noqa: E402

NS = {'f': 'http://schemas.microsoft.com/appx/manifest/foundation/windows10',
      'uap': 'http://schemas.microsoft.com/appx/manifest/uap/windows10',
      'uap3': 'http://schemas.microsoft.com/appx/manifest/uap/windows10/3',
      'desktop': 'http://schemas.microsoft.com/appx/manifest/desktop/windows10',
      'rescap': 'http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities'}


def godot():
    """the pinned Godot if it is here (fetch_godot.sh puts it there); None otherwise"""
    p = os.path.expanduser('~/.local/kksdev/godot/Godot_v4.7.2-stable_linux.x86_64')
    return p if os.access(p, os.X_OK) else None


@unittest.skipUnless(godot() and shutil.which('openssl'), 'needs the pinned Godot (logos) and openssl')
class MsixLayout(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp()
        cert = os.path.join(cls.tmp, 'cert')
        subprocess.run(['sh', os.path.join(APP, 'msix', 'make-msix.sh'), '--test-cert', cert], check=True,
                       capture_output=True)
        exe = os.path.join(cls.tmp, 'WalkdownPlant.exe')
        with open(exe, 'wb') as f:
            f.write(b'MZ stand-in')
        cls.out = {}
        for arch in ('x86_64', 'aarch64'):
            d = os.path.join(cls.tmp, arch)
            r = subprocess.run(['sh', os.path.join(APP, 'msix', 'make-msix.sh'), '--layout', d,
                                os.path.join(cert, 'test.pfx')], capture_output=True, text=True,
                               env={**os.environ, 'PLANT_EXE': exe, 'KKS_WIN_ARCH': arch, 'GODOT': godot()})
            if r.returncode:
                raise AssertionError(r.stdout + r.stderr)
            cls.out[arch] = d

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp)

    def manifest(self, arch='x86_64'):
        return ET.parse(os.path.join(self.out[arch], 'AppxManifest.xml')).getroot()

    def test_identity_version_and_publisher(self):
        version = plant_release.app_version(REPO)[0]
        for arch, pa in (('x86_64', 'x64'), ('aarch64', 'arm64')):
            ident = self.manifest(arch).find('f:Identity', NS)
            self.assertEqual(ident.get('Name'), 'WalkdownPlant')
            self.assertEqual(ident.get('Version'), version + '.0')
            self.assertEqual(ident.get('ProcessorArchitecture'), pa)
            self.assertEqual(ident.get('Publisher'), 'CN=KKS Explorer Test')   # the test certificate, never the real one
            with open(os.path.join(self.out[arch], 'AppxManifest.xml')) as f:
                self.assertNotRegex(f.read(), r'@[A-Z]+@')

    def test_the_link_protocol_and_alias(self):
        app = self.manifest().find('f:Applications/f:Application', NS)
        self.assertEqual(app.get('Executable'), 'WalkdownPlant.exe')
        [proto] = app.findall('f:Extensions/uap3:Extension/uap3:Protocol', NS)
        self.assertEqual(proto.get('Name'), 'walkdown-plant')
        self.assertEqual(proto.get('Parameters'), '-- "%1"')     # after Godot's end of options (0056)
        [alias] = app.findall('f:Extensions/uap3:Extension/uap3:AppExecutionAlias/desktop:ExecutionAlias', NS)
        self.assertEqual(alias.get('Alias'), 'walkdown-plant.exe')

    def test_no_network_and_full_trust_only(self):
        caps = [c.get('Name') for c in self.manifest().find('f:Capabilities', NS)]
        self.assertEqual(caps, ['runFullTrust'])

    def test_the_files_and_logos(self):
        d = self.out['x86_64']
        self.assertEqual(sorted(os.listdir(d)), ['AppxManifest.xml', 'Assets', 'WalkdownPlant.exe'])
        for name, px in (('Square44x44Logo', 44), ('Square150x150Logo', 150), ('StoreLogo', 50)):
            with open(os.path.join(d, 'Assets', name + '.png'), 'rb') as f:
                head = f.read(24)
            self.assertEqual(head[:8], b'\x89PNG\r\n\x1a\n', name)
            self.assertEqual(struct.unpack('>II', head[16:24]), (px, px), name)
        # every logo the manifest names is there
        with open(os.path.join(d, 'AppxManifest.xml')) as f:
            refs = re.findall(r'Assets\\(\w+\.png)', f.read())
        self.assertEqual(len(refs), 3)
        for ref in refs:
            self.assertTrue(os.path.exists(os.path.join(d, 'Assets', ref)), ref)


class Exports(unittest.TestCase):
    def test_windows_presets_for_both_architectures(self):
        with open(os.path.join(APP, 'export_presets.cfg')) as f:
            s = f.read()
        presets = re.split(r'^\[preset\.\d+\]$', s, flags=re.M)[1:]
        win = {re.search(r'^name="(.*)"', p, re.M).group(1): p for p in presets if 'platform="Windows Desktop"' in p}
        self.assertEqual(sorted(win), ['Windows', 'Windows ARM64'])
        for name, arch, path in (('Windows', 'x86_64', 'export/windows/'), ('Windows ARM64', 'arm64', 'export/windows-arm64/')):
            self.assertIn(f'binary_format/architecture="{arch}"', win[name])
            self.assertIn('binary_format/embed_pck=true', win[name])   # one exe: the MSIX carries only it
            self.assertIn(f'export_path="{path}WalkdownPlant.exe"', win[name])
        # the packaging's own files never go into an export
        for p in presets:
            self.assertIn('msix/*', re.search(r'^exclude_filter="(.*)"', p, re.M).group(1))


class FlatpakMetainfo(unittest.TestCase):
    def test_the_release_entry_is_made_from_the_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, 'm.xml')
            subprocess.run(['sh', os.path.join(APP, 'flatpak', 'build.sh'), '--metainfo', out], check=True)
            root = ET.parse(out).getroot()
            [rel] = root.findall('releases/release')
            version = plant_release.app_version(REPO)[0]
            self.assertEqual(rel.get('version'), version)
            self.assertRegex(rel.get('date'), r'^\d{4}-\d{2}-\d{2}$')
            self.assertEqual(rel.find('url').text,
                             f'https://github.com/5wHN28Dg/kks-explorer/releases/tag/plant-v{version}')
            if shutil.which('appstreamcli'):
                subprocess.run(['appstreamcli', 'validate', '--no-net', out], check=True, capture_output=True)

    def test_a_bundle_needs_the_pck_of_this_commit_without_changes(self):
        """the bundle refuses (before flatpak-builder runs) a .pck of another commit or built with changes"""
        head = subprocess.run(['git', '-C', REPO, 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()
        with tempfile.TemporaryDirectory() as tmp:
            pck = os.path.join(tmp, 'p.pck')
            for commit, changes in (('f' * 40, 'false'), (head, 'true')):
                with open(pck, 'wb') as f:
                    f.write(b'GDPC\0' + ('{"format": "walkdown-plant-build", "commit": "%s", "changes": %s}' % (commit, changes)).encode())
                r = subprocess.run(['sh', os.path.join(APP, 'flatpak', 'build.sh'), '--bundle', os.path.join(tmp, 'o.flatpak'),
                                    os.path.join(tmp, 'b')], capture_output=True, text=True, env={**os.environ, 'PLANT_PCK': pck})
                self.assertEqual(r.returncode, 2, r.stderr)
                self.assertIn('was not built from %s without changes' % head, r.stderr)
                self.assertFalse(os.path.exists(os.path.join(tmp, 'o.flatpak')))

    def test_no_hand_written_release_and_the_manifest_takes_the_made_one(self):
        d = os.path.join(APP, 'flatpak')
        with open(os.path.join(d, 'io.github._5wHN28Dg.WalkdownPlant.metainfo.xml')) as f:
            self.assertNotIn('<release', f.read())
        with open(os.path.join(d, 'io.github._5wHN28Dg.WalkdownPlant.yml')) as f:
            self.assertIn('path: ../export/flatpak/io.github._5wHN28Dg.WalkdownPlant.metainfo.xml', f.read())


if __name__ == '__main__':
    unittest.main()
