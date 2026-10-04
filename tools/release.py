#!/usr/bin/env python3
"""Make a signed release (M5b self-updates; the whole procedure: https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing). Runs on the maintainer's machine
only: the release key never goes into the repository or CI.

  python3 tools/release.py VERSION DIR [--notes FILE]          write DIR/release.json + DIR/release.json.sig
  python3 tools/release.py VERSION DIR [--notes FILE] --publish  ... then create GitHub release vVERSION with the files
                                                                   (asks first; needs the gh CLI, logged in)
  python3 tools/release.py --new-key                           create the release key (once; back it up offline)

DIR holds the files to ship: KKS-Explorer-windows.zip, KKS-Explorer-linux.tar.gz (from the Desktop packages workflow)
and kks-explorer.apk (built and signed locally: https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing). The key: $KKS_SIGNING/release-ed25519.key or
~/.config/kks-explorer/signing/release-ed25519.key (the hex Ed25519 seed)."""
import argparse, base64, hashlib, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class updates:
    """what the devices check (v1's server/updates.py, removed with v1; the old app still verifies this signature)"""
    REPO = '5wHN28Dg/kks-explorer'
    RELEASE_PUB = 'YBHkaex01_tOIIUiI8kZMAHCwUF-aHIGYJtR0jnENtM'   # base64url raw Ed25519 public key
    DOMAIN = b'kks-release-v1\n'
    import re as _re
    VERSION_RE = _re.compile(r'\d{1,4}\.\d{1,4}\.\d{1,4}')

    @staticmethod
    def current():
        with open(os.path.join(ROOT, 'VERSION')) as f:
            return f.read().strip()

    @staticmethod
    def verify(manifest_bytes, sig_text):
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
        def b(s):
            return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))
        Ed25519PublicKey.from_public_bytes(b(updates.RELEASE_PUB)).verify(b(sig_text.strip()), updates.DOMAIN + manifest_bytes)


# The old app's bridge (decision 0042): while any phone is still on KKS Explorer, every release must carry it as
# kks-explorer.apk, or 0.8.0 phones see nothing to install. Its source was removed with v1; the built 0.9.0 bridge is
# kept here (or $KKS_BRIDGE_APK). Check who hasn't moved: kks-server v1-status (wiki: Server).
BRIDGE_APK = os.environ.get('KKS_BRIDGE_APK') or os.path.expanduser('~/kks-server/archive/kks-explorer-bridge-0.9.0.apk')

# kks-explorer.apk: the v1 app (since the cutover its bridge release, decision 0042); walkdown.apk: Walkdown for
# Android (it updates itself from this manifest, decision 0044); Walkdown.msix + windows-msix.cer, walkdown.flatpak:
# the laptops (installed by hand for now, 0043)
FILES = ('KKS-Explorer-windows.zip', 'KKS-Explorer-linux.tar.gz', 'kks-explorer.apk', 'walkdown.apk', 'Walkdown.msix',
         'Walkdown-arm64.msix', 'windows-msix.cer', 'walkdown.flatpak', 'walkdown-aarch64.flatpak')   # ARM64: decision 0047
# Walkdown checks a second signature, ECDSA P-256 (it carries no Ed25519): release.json.p256 = base64 of the DER
# signature over DOMAIN2 + release.json, by release-p256.pem in the signing folder; the public key is pinned in
# android/app2 (sync/Updates.kt) and here
DOMAIN2 = b'kks-release-v2\n'
RELEASE_P256_PUB = ('MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE5zNac3d7S/F5haZ7vi8BwMQ8Cv5Ee20FeaIKZO6CJIUYh21F1gjQe0XZI6yiV7wEsvBg'
                    'VptuyJe62eHcJ99p9A==')


def key_path():
    d = os.environ.get('KKS_SIGNING') or os.path.expanduser('~/.config/kks-explorer/signing')
    return os.path.join(d, 'release-ed25519.key')


def load_key(path=None):
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    with open(path or key_path()) as f:
        return Ed25519PrivateKey.from_private_bytes(bytes.fromhex(f.read().strip()))


def public_b64u(key):
    from cryptography.hazmat.primitives import serialization as s
    return base64.urlsafe_b64encode(key.public_key().public_bytes(s.Encoding.Raw, s.PublicFormat.Raw)).rstrip(b'=').decode()


def manifest(version, files, notes=''):
    """-> the exact bytes of release.json for {name: bytes or path}."""
    out = {}
    for name, v in sorted(files.items()):
        data = v if isinstance(v, bytes) else open(v, 'rb').read()
        out[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
    return json.dumps({'app': 'kks-explorer', 'version': version, 'notes': notes, 'files': out}, indent=1).encode()


def sign_p256(manifest_bytes, path=None):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    with open(path or os.path.join(os.path.dirname(key_path()), 'release-p256.pem'), 'rb') as f:
        k = serialization.load_pem_private_key(f.read(), None)
    sig = k.sign(DOMAIN2 + manifest_bytes, ec.ECDSA(hashes.SHA256()))
    pub = k.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
    if base64.b64encode(pub).decode() != RELEASE_P256_PUB:
        sys.exit('release-p256.pem is not the key pinned in Walkdown (RELEASE_P256_PUB): phones would refuse the release.')
    return base64.b64encode(sig).decode()


def sign(manifest_bytes, key):
    return base64.urlsafe_b64encode(key.sign(updates.DOMAIN + manifest_bytes)).rstrip(b'=').decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('version', nargs='?')
    ap.add_argument('dir', nargs='?')
    ap.add_argument('--notes')
    ap.add_argument('--publish', action='store_true')
    ap.add_argument('--yes', action='store_true', help='publish without asking again')
    ap.add_argument('--new-key', action='store_true')
    a = ap.parse_args()
    if a.new_key:
        from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
        from cryptography.hazmat.primitives import serialization as s
        p = key_path()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        k = Ed25519PrivateKey.generate()
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)   # never overwrites an existing key
        with os.fdopen(fd, 'w') as f:
            f.write(k.private_bytes(s.Encoding.Raw, s.PrivateFormat.Raw, s.NoEncryption()).hex() + '\n')
        print(f'Wrote {p}. Back it up offline. Pin its public key in tools/release.py (updates.RELEASE_PUB): {public_b64u(k)}')
        return
    if not (a.version and a.dir):
        ap.error('VERSION and DIR are required')
    if not updates.VERSION_RE.fullmatch(a.version):
        sys.exit('VERSION looks like 1.2.3')
    if updates.current() != a.version:
        sys.exit(f'The VERSION file says {updates.current()}, not {a.version}: bump it, commit, build, then release.')
    key = load_key()
    if public_b64u(key) != updates.RELEASE_PUB:
        sys.exit('This key is not the one pinned (updates.RELEASE_PUB): the old app would refuse the release.')
    files = {n: os.path.join(a.dir, n) for n in FILES if os.path.exists(os.path.join(a.dir, n))}
    if 'kks-explorer.apk' not in files and os.path.exists(BRIDGE_APK):
        # copied in under its release name: gh uploads a file under its own name, and 0.8.0 downloads exactly this one
        # (v0.9.1 first went out with the archive's file name and had to be fixed by hand)
        import shutil
        shutil.copyfile(BRIDGE_APK, os.path.join(a.dir, 'kks-explorer.apk'))
        files['kks-explorer.apk'] = os.path.join(a.dir, 'kks-explorer.apk')
        print(f'Attaching the bridge for phones still on KKS Explorer: {BRIDGE_APK}')
    missing = [n for n in FILES if n not in files]
    if missing:
        print('Missing (devices of that kind will not see this update):', ', '.join(missing))
    if not files:
        sys.exit('Nothing to release.')
    notes = open(a.notes).read().strip() if a.notes else ''
    m = manifest(a.version, files, notes)
    with open(os.path.join(a.dir, 'release.json'), 'wb') as f:
        f.write(m)
    with open(os.path.join(a.dir, 'release.json.sig'), 'w') as f:
        f.write(sign(m, key) + '\n')
    updates.verify(m, open(os.path.join(a.dir, 'release.json.sig')).read())   # what the devices will check
    with open(os.path.join(a.dir, 'release.json.p256'), 'w') as f:
        f.write(sign_p256(m) + '\n')
    print(f'Signed release.json for {a.version}: {", ".join(files)}')
    if not a.publish:
        return
    if not a.yes and input(f'Create the public GitHub release v{a.version} with these files? [y/N] ').strip().lower() != 'y':
        return print('Not published.')
    cmd = ['gh', 'release', 'create', f'v{a.version}', '--repo', updates.REPO, '--title', f'Walkdown {a.version}',
           '--notes', notes or f'Walkdown {a.version}', *files.values(),
           os.path.join(a.dir, 'release.json'), os.path.join(a.dir, 'release.json.sig'),
           os.path.join(a.dir, 'release.json.p256')]
    subprocess.run(cmd, check=True)


if __name__ == '__main__':
    main()
