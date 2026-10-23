#!/usr/bin/env python3
"""Make a Walkdown Plant release (decision 0054 §8; the whole procedure: the wiki's Releasing page and
apps/plant3d/README.md "Releasing"). Runs on the maintainer's machine only: the signing keys never go to CI.

  python3 tools/plant_release.py bump VERSION                  set the app's version (project.godot, the export
                                                                presets' Android version name and code)
  python3 tools/plant_release.py VERSION DIR [--notes FILE]    check everything and say what would be published
                                                                (a dry run: changes nothing, publishes nothing)
  python3 tools/plant_release.py VERSION DIR [--notes FILE] --publish [--yes]
                                                                ... then create the GitHub release plant-vVERSION
                                                                with DIR's files (asks first; gh CLI, logged in)

The release is a GitHub release of this repository tagged plant-vVERSION and published NOT as latest
(gh release create --latest=false): GitHub's latest release is what Walkdown's updater reads (sync/Updates.kt), so it
must stay Walkdown's. Nothing is published unless
- VERSION is the app's version (project.godot application/config/version, and the export presets agree);
- the checkout is clean and at a commit of origin/main (origin's tag plant-vVERSION, if it has one, names it); the
  release is created on that commit (gh --target);
- the packages were built from that commit without local changes: build.sh writes the commit and whether the
  checkout had changes into built/build_info.json, which the APK and the MSIX packages' WalkdownPlant.exe carry (the
  Flatpak bundle is compressed: not checked; build it from the same clean checkout);
- the MSIX packages are Walkdown's (publisher CN=Walkdown, never a test certificate), signed, of this version and for
  the architecture their name says (the manifest and the exe), windows-msix.cer is CN=Walkdown, and the APK is
  signed with the plant's key (CN=Walkdown Plant: never a debug or unsigned build; apksigner from the Android SDK);
- every package is within its size budget (the user, 2026-10-23): the APK at most 150 MB, the desktop packages
  (the MSIX packages, the Flatpak bundle) at most 300 MB;
- every CI run on the commit has finished and passed, the Walkdown Plant app workflow among them (a hard gate);
- GitHub's latest release is a Walkdown vX.Y.Z before, and still the same one after (if publishing made the plant's
  release latest after all, the Walkdown release is made latest again and the tool fails)."""
import argparse, glob, os, re, struct, subprocess, sys, zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import release  # noqa: E402  (the shared checks: checkout, CI, latest)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join('apps', 'plant3d')
VERSION_RE = re.compile(r'(\d{1,2})\.(\d{1,2})\.(\d{1,2})')   # the Android version code is a·10000 + b·100 + c

# walkdown-plant.apk: Android (arm64-v8a, the plant's own key); WalkdownPlant.msix and WalkdownPlant-arm64.msix with
# windows-msix.cer: Windows (CN=Walkdown, as Walkdown's; apps/plant3d/msix/make-msix.sh); walkdown-plant.flatpak:
# Linux (apps/plant3d/flatpak/build.sh --bundle)
FILES = ('walkdown-plant.apk', 'WalkdownPlant.msix', 'WalkdownPlant-arm64.msix', 'windows-msix.cer',
         'walkdown-plant.flatpak')
# where each package carries built/build_info.json: the APK as an asset, the MSIX packages inside the exe (the .pck
# is embedded)
BUILT_FROM = {'walkdown-plant.apk': re.compile(r'assets/(.*/)?built/build_info\.json'),
              'WalkdownPlant.msix': re.compile(r'WalkdownPlant\.exe'),
              'WalkdownPlant-arm64.msix': re.compile(r'WalkdownPlant\.exe')}

# the size budget per package (the user, 2026-10-23; decision 0054 §6): the APK at most 150 MB (past it, packs on
# demand, which need a network permission: the user's call); the desktop packages may grow to about 300 MB. Still
# compress wherever it costs nothing.
MB = 1_000_000
MAX_BYTES = {'walkdown-plant.apk': 150 * MB, 'WalkdownPlant.msix': 300 * MB, 'WalkdownPlant-arm64.msix': 300 * MB,
             'walkdown-plant.flatpak': 300 * MB}


def size_problems(files):
    """[the packages over their size budget] ({name: path})"""
    out = []
    for name, path in sorted(files.items()):
        limit = MAX_BYTES.get(name)
        if limit is not None and os.path.getsize(path) > limit:
            out.append(f'{name} is {os.path.getsize(path) / MB:.1f} MB, over its budget of {limit // MB} MB')
    return out


def tag(version):
    return f'plant-v{version}'


def version_code(version):
    a, b, c = (int(x) for x in VERSION_RE.fullmatch(version).groups())
    return a * 10000 + b * 100 + c


def app_version(root=None):
    """-> (project.godot's application/config/version, [what disagrees with it in the export presets])"""
    root = root or ROOT
    with open(os.path.join(root, APP, 'project.godot')) as f:
        m = re.search(r'^config/version="([^"]*)"$', f.read(), re.M)
    v = m.group(1) if m else ''
    out = [] if m else ['project.godot has no application/config/version']
    with open(os.path.join(root, APP, 'export_presets.cfg')) as f:
        presets = f.read()
    for name in re.findall(r'^version/name="([^"]*)"$', presets, re.M):
        if name != v:
            out.append(f'an export preset\'s version/name is {name}, not {v}')
    if VERSION_RE.fullmatch(v):
        for code in re.findall(r'^version/code=(\d+)$', presets, re.M):
            if int(code) != version_code(v):
                out.append(f'an export preset\'s version/code is {code}, not {version_code(v)} (for {v})')
    return v, out


def bump(version, root=None):
    """sets the version in project.godot and the export presets (Android's version name and code)"""
    if not VERSION_RE.fullmatch(version):
        raise SystemExit('VERSION looks like 1.2.3')
    root = root or ROOT
    p = os.path.join(root, APP, 'project.godot')
    with open(p) as f:
        s = f.read()
    s, n = re.subn(r'^config/version="[^"]*"$', f'config/version="{version}"', s, flags=re.M)
    if n != 1:
        raise SystemExit('project.godot: no application/config/version line to change')
    with open(p, 'w') as f:
        f.write(s)
    p = os.path.join(root, APP, 'export_presets.cfg')
    with open(p) as f:
        s = f.read()
    s = re.sub(r'^version/name="[^"]*"$', f'version/name="{version}"', s, flags=re.M)
    s = re.sub(r'^version/code=\d+$', f'version/code={version_code(version)}', s, flags=re.M)
    with open(p, 'w') as f:
        f.write(s)


MSIX_ARCH = {'WalkdownPlant.msix': 'x64', 'WalkdownPlant-arm64.msix': 'arm64'}
PE_MACHINE = {'x64': 0x8664, 'arm64': 0xAA64}
APK_SIGNER_DN = 'CN=Walkdown Plant'   # the plant's own key (0054), never a debug key or Walkdown's
PUBLISHER = 'CN=Walkdown'   # the certificate IT trusts (0043); never a test certificate's


def pe_machine(data):
    """the machine field of a Windows exe's PE header (None when it is not one)"""
    if data[:2] != b'MZ' or len(data) < 0x40:
        return None
    off = struct.unpack_from('<I', data, 0x3C)[0]
    if data[off:off + 4] != b'PE\0\0':
        return None
    return struct.unpack_from('<H', data, off + 4)[0]


def msix_problems(name, z, version=None):
    """[what is wrong with an MSIX]: Walkdown's publisher, the architecture its name says (the manifest's and the
    exe's), the version, a signature"""
    try:
        m = z.read('AppxManifest.xml').decode('utf-8', 'replace')
    except KeyError:
        return [f'{name}: has no AppxManifest.xml']
    ident = re.search(r'<Identity\b[^>]*>', m)
    ident = ident.group(0) if ident else ''
    pub = re.search(r'Publisher="([^"]*)"', ident)
    arch = re.search(r'ProcessorArchitecture="([^"]*)"', ident)
    out = []
    if not pub or pub.group(1) != PUBLISHER:
        out.append(f'{name}: publisher is {pub.group(1) if pub else "missing"}, not {PUBLISHER} (a test package?)')
    if not arch or arch.group(1) != MSIX_ARCH[name]:
        out.append(f'{name}: is for {arch.group(1) if arch else "no architecture"}, not {MSIX_ARCH[name]}')
    ver = re.search(r'Version="([^"]*)"', ident)
    if version and (not ver or ver.group(1) != version + '.0'):
        out.append(f'{name}: version {ver.group(1) if ver else "missing"}, not {version}.0')
    if 'AppxSignature.p7x' not in z.namelist():
        out.append(f'{name}: is not signed')
    try:
        machine = pe_machine(z.read('WalkdownPlant.exe'))
    except KeyError:
        machine = None
    if machine != PE_MACHINE[MSIX_ARCH[name]]:
        out.append(f'{name}: its WalkdownPlant.exe is not an {MSIX_ARCH[name]} program')
    return out


def apk_signer(path):
    """the APK's first signer's DN, by the Android SDK's apksigner (newest build-tools); None when it can't tell"""
    sdk = os.environ.get('ANDROID_HOME') or os.path.expanduser('~/Android/Sdk')
    tools = sorted((p for p in glob.glob(os.path.join(sdk, 'build-tools', '*', 'apksigner')) if '-rc' not in p),
                   key=lambda p: [int(x) for x in re.findall(r'\d+', os.path.basename(os.path.dirname(p)))])
    if not tools:
        return None
    r = subprocess.run([tools[-1], 'verify', '--print-certs', path], capture_output=True, text=True)
    m = re.search(r'^Signer #1 certificate DN: (.*)$', r.stdout, re.M) if r.returncode == 0 else None
    return m.group(1).strip() if m else None


def cert_problems(path):
    """[what is wrong with windows-msix.cer]: it must be Walkdown's certificate, not a test one"""
    from cryptography import x509
    try:
        with open(path, 'rb') as f:
            data = f.read()
        c = x509.load_der_x509_certificate(data) if not data.startswith(b'-----') else x509.load_pem_x509_certificate(data)
    except (OSError, ValueError) as e:
        return [f'windows-msix.cer: not readable ({e})']
    subject = c.subject.rfc4514_string()
    return [] if subject == PUBLISHER else [f'windows-msix.cer is {subject}, not {PUBLISHER}']


def artifact_problems(files, commit, version=None):
    """[what in the packages was not built from `commit` without changes, or is not what its name says] ({name: path})"""
    good = f'"commit": "{commit}", "changes": false'.encode()
    changed = f'"commit": "{commit}", "changes": true'.encode()
    out = []
    if 'windows-msix.cer' in files:
        out += cert_problems(files['windows-msix.cer'])
    if 'walkdown-plant.apk' in files:
        dn = apk_signer(files['walkdown-plant.apk'])
        if dn != APK_SIGNER_DN:
            out.append(f'walkdown-plant.apk is signed by {dn or "nobody apksigner could verify"}, not {APK_SIGNER_DN}')
    for name, path in sorted(files.items()):
        where = BUILT_FROM.get(name)
        if where is None:
            continue
        try:
            with zipfile.ZipFile(path) as z:
                parts = [n for n in z.namelist() if where.fullmatch(n)]
                data = [z.read(n) for n in parts]
                if name in MSIX_ARCH:
                    out += msix_problems(name, z, version)
        except (zipfile.BadZipFile, OSError) as e:
            out.append(f'{name}: not readable ({e})')
            continue
        if not parts:
            out.append(f'{name}: has no {where.pattern}')
        elif any(good in d for d in data):
            continue
        elif any(changed in d for d in data):
            out.append(f'{name} was built from {commit[:12]} with local changes')
        else:
            out.append(f'{name} was not built from the release commit {commit[:12]} (another commit, or unknown)')
    return out


def problems(version, files, root=None, remote='origin'):
    """-> (the release commit, [everything that stops the release]); runs every check, gh's included"""
    root = root or ROOT
    out = []
    v, disagree = app_version(root)
    out += disagree
    if v != version:
        out.append(f'the app\'s version (apps/plant3d/project.godot) is {v or "missing"}, not {version}: '
                   f'tools/plant_release.py bump {version}, commit, build, then release')
    commit, p = release.checkout_problems(root, version, remote, tag_name=tag(version))
    out += p
    if not p and not release.git(root, 'branch', '-r', '--contains', commit, f'{remote}/main').strip():
        out.append(f'commit {commit[:12]} is not on {remote}/main: release a merged commit')
    if not any(n in BUILT_FROM for n in files):
        out.append('nothing to release in DIR: no APK or MSIX package')
    out += artifact_problems(files, commit, version)
    out += size_problems(files)
    out += release.ci_problems(commit, required=('Walkdown Plant app',))
    out += release.latest_problems()
    return commit, out


def gh_command(version, commit, files, notes):
    return ['gh', 'release', 'create', tag(version), '--repo', release.updates.REPO, '--target', commit,
            '--latest=false', '--title', f'Walkdown Plant {version}',
            '--notes', notes or f'Walkdown Plant {version}', *files.values()]


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('version')
    ap.add_argument('dir', nargs='?')
    ap.add_argument('--notes')
    ap.add_argument('--publish', action='store_true', help='create the GitHub release (without it: a dry run)')
    ap.add_argument('--yes', action='store_true', help='publish without asking again')
    a = ap.parse_args(argv)
    if a.version == 'bump':
        if not a.dir:
            ap.error('bump VERSION')
        bump(a.dir)
        return print(f'The app\'s version is {a.dir}: commit it, then build the packages from that commit.')
    if not a.dir:
        ap.error('VERSION and DIR are required')
    if not VERSION_RE.fullmatch(a.version):
        sys.exit('VERSION looks like 1.2.3')
    files = {n: os.path.join(a.dir, n) for n in FILES if os.path.exists(os.path.join(a.dir, n))}
    missing = [n for n in FILES if n not in files]
    if missing:
        print('Missing (not in this release):', ', '.join(missing))
    commit, out = problems(a.version, files)
    if out:
        sys.exit('Not released: ' + '; '.join(out) + '.')
    notes = open(a.notes).read().strip() if a.notes else ''
    cmd = gh_command(a.version, commit, files, notes)
    before = release.latest_release()
    print(f'Ready: {tag(a.version)} on commit {commit}, not latest (latest stays {before}): {", ".join(files)}')
    if not a.publish:
        return print('Dry run: nothing published. Would run: ' + ' '.join(cmd[:9]) + ' …')
    if not a.yes and input(f'Create the public GitHub release {tag(a.version)} with these files? [y/N] ').strip().lower() != 'y':
        return print('Not published.')
    try:
        subprocess.run(cmd, check=True)
    finally:
        # even when gh failed half way (the release made, an upload failed): never leave Walkdown's updater reading
        # the plant's release
        after = release.latest_release()
        if after != before:
            subprocess.run(['gh', 'release', 'edit', before, '--repo', release.updates.REPO, '--latest'], check=True)
            sys.exit(f'GitHub made {after} the latest release; {before} was made latest again. Check both releases.')
    print(f'Published {tag(a.version)}; the latest release is still {after}.')


if __name__ == '__main__':
    main()
