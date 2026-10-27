"""Third-party code that no lockfile can express (DEP-8, #4, #53) and the relay's deploy tool (#52):
- every hash or commit a build script pins is listed in pinned-sources.cdx.json, and every listed one is still
  pinned somewhere (the vulnerability scan and the release audit read that file, so it must not drift);
- each listed source has what DEP-8 asks for: name, version, URL, a SHA-256-or-stronger hash or a full commit,
  a license;
- wrangler is pinned exactly in relay/ and relay-plant/'s package.json and package-lock.json, with integrity hashes;
- the Windows toolchain is llvm-mingw alone (0053): Ubuntu's mingw-w64/GCC/binutils packages are neither fetched nor
  listed;
- the Windows zlib is built without its gz* file functions (#58; needs the llvm-mingw toolchain, else skipped).
  .venv/bin/python -m unittest tests.test_pinned_sources"""
import glob, json, os, re, shutil, subprocess, tempfile, unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
BOM = os.path.join(REPO, 'pinned-sources.cdx.json')
# the build scripts that fetch third-party sources and tools
SCRIPTS = ['platform/windows/*.sh', 'packaging/windows/*.sh', 'importer/fetch_mupdf.sh', 'android/nim/fetch_sqlite.sh',
           'platform/web/build-wasm.sh', 'android/app2/build.gradle.kts', 'apps/gnome/flatpak/*.yml',
           'apps/plant3d/voice/*.sh']
STRONG = {'SHA-256', 'SHA-384', 'SHA-512', 'SHA3-256', 'SHA3-384', 'SHA3-512', 'BLAKE2B-256', 'BLAKE2B-384',
          'BLAKE2B-512', 'BLAKE3'}


def script_pins():
    """-> {hash or commit: script} for every 64-hex hash and every full 40-hex commit the scripts pin"""
    pins = {}
    for pat in SCRIPTS:
        for f in sorted(glob.glob(os.path.join(REPO, pat))):
            rel = os.path.relpath(f, REPO)
            with open(f, encoding='utf-8') as fh:
                for line in fh:
                    if line.lstrip().startswith(('#', '//')):
                        continue
                    for h in re.findall(r'(?<![0-9a-f])([0-9a-f]{64}|[0-9a-f]{40})(?![0-9a-f])', line):
                        pins[h] = rel
    return pins


def bom_pins(bom):
    out = {}
    for c in bom['components']:
        hs = [h['content'] for r in c.get('externalReferences', []) for h in r.get('hashes', [])]
        hs += [h['content'] for h in c.get('hashes', [])]
        if re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', c.get('version', '')):
            hs.append(c['version'])
        for h in hs:
            out[h] = c['name']
    return out


class PinnedSources(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(BOM, encoding='utf-8') as f:
            cls.bom = json.load(f)

    def test_dep8_fields(self):
        self.assertEqual(self.bom['bomFormat'], 'CycloneDX')
        self.assertTrue(self.bom['components'])
        for c in self.bom['components']:
            with self.subTest(c.get('name')):
                self.assertTrue(c.get('name') and c.get('version'))
                self.assertTrue(c.get('licenses'))
                refs = c.get('externalReferences') or []
                self.assertTrue(any(r.get('url', '').startswith('https://') for r in refs))
                hashes = [h for r in refs for h in r.get('hashes', [])] + c.get('hashes', [])
                strong = [h for h in hashes if h.get('alg') in STRONG and re.fullmatch(r'[0-9a-f]{64,128}', h.get('content', ''))]
                self.assertTrue(strong or re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', c['version']), 'no pin')
                self.assertTrue(c.get('purl', '').startswith('pkg:'))

    def test_every_script_pin_listed(self):
        listed = bom_pins(self.bom)
        missing = {h: s for h, s in script_pins().items() if h not in listed}
        self.assertEqual(missing, {}, 'pinned in a build script but not in pinned-sources.cdx.json')

    def test_every_listed_pin_used(self):
        pins = script_pins()
        stale = {h: n for h, n in bom_pins(self.bom).items() if h not in pins}
        self.assertEqual(stale, {}, 'in pinned-sources.cdx.json but no build script pins it any more')

    def test_known_sources_listed(self):
        names = {c['name'] for c in self.bom['components']}
        for n in ('libjxl', 'highway', 'brotli', 'skcms', 'zxing-cpp', 'zlib', 'mupdf', 'sqlite-amalgamation', 'emsdk',
                  'nim', 'llvm-mingw', 'osslsigncode', 'godot-cpp', 'opus', 'speexdsp'):
            self.assertIn(n, names)

    def test_no_gcc_mingw_toolchain(self):
        """0053: both Windows architectures build with llvm-mingw; the GCC cross toolchain from Ubuntu's packages is
        gone from the list, the scripts and CI"""
        gnu = re.compile(r'mingw-w64-(x86-64|common|base)|gcc-mingw|g\+\+-mingw|binutils-mingw|x86_64-w64-mingw32-g(cc|\+\+)'
                         r'|-gcc-posix|\.windows\.gcc\.|KKS_MINGW_BIN|kksdev/mingw\b|kksdev/win64\b')
        self.assertEqual([c['name'] for c in self.bom['components'] if gnu.search(c['name'])], [])
        files = [f for pat in SCRIPTS + ['.github/workflows/*.yml', '**/config.nims', 'apps/windows/*.sh',
                                         'platform/windows/*.nims']
                 for f in glob.glob(os.path.join(REPO, pat), recursive=True)]
        self.assertFalse(os.path.exists(os.path.join(REPO, 'platform', 'windows', 'fetch-mingw.sh')))
        for f in sorted(set(files)):
            with open(f, encoding='utf-8') as fh:
                text = fh.read()
            self.assertIsNone(gnu.search(text), os.path.relpath(f, REPO))
            # a config.nims for Windows builds without the shared settings would fall back to Nim's default
            # x86_64-w64-mingw32-gcc from PATH
            if f.endswith('config.nims') and 'mingw' in text:
                self.assertRegex(text, r'include "[./]*(platform/windows/|windows/)?toolchain\.nims"', os.path.relpath(f, REPO))


class Relay(unittest.TestCase):
    def test_wrangler_pinned(self):
        for folder in ('relay', 'relay-plant'):   # Walkdown's relay and Walkdown Plant's
            with self.subTest(folder):
                with open(os.path.join(REPO, folder, 'package.json'), encoding='utf-8') as f:
                    pkg = json.load(f)
                ver = pkg['devDependencies']['wrangler']
                self.assertRegex(ver, r'^\d+\.\d+\.\d+$', 'an exact version, no range')
                with open(os.path.join(REPO, folder, 'package-lock.json'), encoding='utf-8') as f:
                    lock = json.load(f)
                self.assertEqual(lock['packages']['node_modules/wrangler']['version'], ver)
                for k, v in lock['packages'].items():
                    if k and not v.get('link'):
                        self.assertTrue(v.get('integrity', '').startswith('sha512-'), k)
                with open(os.path.join(REPO, folder, 'README.md'), encoding='utf-8') as f:
                    readme = f.read()
                self.assertIn('npm ci', readme)
                # the dependency scan reads the folder's own osv-scanner.toml (it does not look in parent folders)
                self.assertTrue(os.path.exists(os.path.join(REPO, folder, 'osv-scanner.toml')))


class VoiceSdkPin(unittest.TestCase):
    """The Flatpak SDK the Linux voice library is built in (decision 0069): one commit, named once in voice/build.sh
    (SDK_PIN), listed under that commit and its version in pinned-sources.cdx.json, and installed at exactly that
    commit on CI (plant3d-app.yml reads SDK_PIN from build.sh, and its build step names no other with
    WDP_SDK_COMMIT)."""

    def test_one_commit_everywhere(self):
        with open(os.path.join(REPO, 'apps', 'plant3d', 'voice', 'build.sh'), encoding='utf-8') as f:
            script = f.read()
        pins = re.findall(r'^SDK_PIN=([0-9a-f]{64})$', script, re.M)
        self.assertEqual(len(pins), 1, 'one SDK_PIN line in voice/build.sh')
        with open(BOM, encoding='utf-8') as f:
            sdk = [c for c in json.load(f)['components'] if c['name'] == 'org.freedesktop.Sdk']
        self.assertEqual(len(sdk), 1)
        hashes = [h['content'] for r in sdk[0]['externalReferences'] for h in r.get('hashes', [])]
        self.assertEqual(hashes, [pins[0]], "pinned-sources.cdx.json lists the SDK at build.sh's SDK_PIN")
        # the version beside the commit, in the BOM and in build.sh's comment, is the release that commit is
        self.assertTrue('(freedesktop-sdk-%s)' % sdk[0]['version'] in script,
                        "build.sh's comment names freedesktop-sdk-%s, the BOM's version" % sdk[0]['version'])
        self.assertIn('@%s?' % sdk[0]['version'], sdk[0]['purl'])
        with open(os.path.join(REPO, '.github', 'workflows', 'plant3d-app.yml'), encoding='utf-8') as f:
            wf = f.read()
        self.assertIn('flatpak update --user -y --noninteractive --commit="$(sed -n \'s/^SDK_PIN=//p\' '
                      'apps/plant3d/voice/build.sh)" org.freedesktop.Sdk//26.08', wf)
        self.assertNotIn('WDP_SDK_COMMIT', wf, 'CI builds at the pinned commit, never a named other one')


LLVM_MINGW = os.path.expanduser('~/.local/kksdev/llvm-mingw/bin')


@unittest.skipUnless(os.path.exists(os.path.join(LLVM_MINGW, 'x86_64-w64-mingw32-clang')), 'no llvm-mingw toolchain')
class WindowsZlib(unittest.TestCase):
    def test_no_gz_functions(self):
        d = tempfile.mkdtemp(prefix='kks-zlib-')
        try:
            os.makedirs(os.path.join(d, 'src', 'dl'))
            os.symlink(os.path.dirname(LLVM_MINGW), os.path.join(d, 'llvm-mingw'))   # (fetch-llvm-mingw.sh checks its version)
            cached = os.path.expanduser('~/.local/kksdev/src/dl/zlib.tar.gz')
            if os.path.exists(cached):   # (build-deps.sh checks its hash before use)
                shutil.copy(cached, os.path.join(d, 'src', 'dl'))
            env = dict(os.environ, KKS_DEV=d, KKS_WIN_LIBS='zlib')
            env.pop('KKS_WIN_ARCH', None)
            subprocess.run(['sh', os.path.join(REPO, 'platform', 'windows', 'build-deps.sh')], env=env, check=True,
                           stdout=subprocess.DEVNULL, timeout=600)
            members = subprocess.run([os.path.join(LLVM_MINGW, 'llvm-ar'), 't', os.path.join(d, 'winx64', 'lib', 'libz.a')],
                                     capture_output=True, text=True, check=True).stdout.split()
            self.assertIn('deflate.o', members)
            self.assertIn('inflate.o', members)
            self.assertEqual([m for m in members if m.startswith('gz')], [])
        finally:
            shutil.rmtree(d, ignore_errors=True)


if __name__ == '__main__':
    unittest.main()
