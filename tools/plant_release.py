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
- the checkout is clean and at a commit origin holds (a branch, or origin's tag plant-vVERSION; that tag, if origin
  has one, names it); the release is created on that commit (gh --target);
- the packages were built from that commit without local changes: build.sh writes the commit and whether the
  checkout had changes into built/build_info.json, which the APK and the MSIX packages' WalkdownPlant.exe carry (the
  Flatpak bundle is compressed: not checked; build it from the same clean checkout);
- every CI run on the commit has finished and passed (a hard gate);
- GitHub's latest release is a Walkdown vX.Y.Z before, and still the same one after (if publishing made the plant's
  release latest after all, the Walkdown release is made latest again and the tool fails)."""
import argparse, os, re, subprocess, sys, zipfile

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


def artifact_problems(files, commit):
    """[what in the packages was not built from `commit` without changes] ({name: path})"""
    good = f'"commit": "{commit}", "changes": false'.encode()
    changed = f'"commit": "{commit}", "changes": true'.encode()
    out = []
    for name, path in sorted(files.items()):
        where = BUILT_FROM.get(name)
        if where is None:
            continue
        try:
            with zipfile.ZipFile(path) as z:
                parts = [n for n in z.namelist() if where.fullmatch(n)]
                data = [z.read(n) for n in parts]
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
    if not files:
        out.append('nothing to release in DIR')
    out += artifact_problems(files, commit)
    out += release.ci_problems(commit)
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
    subprocess.run(cmd, check=True)
    after = release.latest_release()
    if after != before:
        # never leave Walkdown's updater reading the plant's release
        subprocess.run(['gh', 'release', 'edit', before, '--repo', release.updates.REPO, '--latest'], check=True)
        sys.exit(f'GitHub made {after} the latest release; {before} was made latest again. Check both releases.')
    print(f'Published {tag(a.version)}; the latest release is still {after}.')


if __name__ == '__main__':
    main()
