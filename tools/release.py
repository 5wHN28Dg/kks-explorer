#!/usr/bin/env python3
"""Make a signed release (decision 0044; the whole procedure: https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing).
Runs on the maintainer's machine only: the release key never goes into the repository or CI.

  python3 tools/release.py VERSION DIR [--notes FILE]          write DIR/release.json + DIR/release.json.p256
  python3 tools/release.py VERSION DIR [--notes FILE] --publish  ... then create GitHub release vVERSION with the files
                                                                   (asks first; needs the gh CLI, logged in)
  python3 tools/release.py --new-key                           create the release key (once; back it up offline)

DIR holds the files to ship (FILES below). The key: $KKS_SIGNING/release-p256.pem or
~/.config/kks-explorer/signing/release-p256.pem (an unencrypted PEM P-256 private key)."""
import argparse, base64, hashlib, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


class updates:
    """what the devices check"""
    REPO = '5wHN28Dg/kks-explorer'
    import re as _re
    VERSION_RE = _re.compile(r'\d{1,4}\.\d{1,4}\.\d{1,4}')

    @staticmethod
    def current():
        with open(os.path.join(ROOT, 'VERSION')) as f:
            return f.read().strip()


# walkdown.apk: Walkdown for Android (it updates itself from this manifest, decision 0044); Walkdown.msix +
# windows-msix.cer, walkdown.flatpak: the laptops (installed by hand for now, 0043). The old app's files
# (kks-explorer.apk, its bridge, the v1 desktop packages) and its Ed25519 signature were retired on 2026-10-05
# (decision 0048).
FILES = ('walkdown.apk', 'Walkdown.msix', 'Walkdown-arm64.msix', 'windows-msix.cer', 'walkdown.flatpak',
         'walkdown-aarch64.flatpak')   # ARM64: decision 0047
# Walkdown checks an ECDSA P-256 signature: release.json.p256 = base64 of the DER signature over DOMAIN2 +
# release.json, by release-p256.pem in the signing folder; the public key is pinned in android/app2 (sync/Updates.kt)
# and here
DOMAIN2 = b'kks-release-v2\n'
RELEASE_P256_PUB = ('MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE5zNac3d7S/F5haZ7vi8BwMQ8Cv5Ee20FeaIKZO6CJIUYh21F1gjQe0XZI6yiV7wEsvBg'
                    'VptuyJe62eHcJ99p9A==')


def key_path():
    d = os.environ.get('KKS_SIGNING') or os.path.expanduser('~/.config/kks-explorer/signing')
    return os.path.join(d, 'release-p256.pem')


def manifest(version, files, notes=''):
    """-> the exact bytes of release.json for {name: bytes or path}."""
    out = {}
    for name, v in sorted(files.items()):
        data = v if isinstance(v, bytes) else open(v, 'rb').read()
        out[name] = {'sha256': hashlib.sha256(data).hexdigest(), 'size': len(data)}
    return json.dumps({'app': 'kks-explorer', 'version': version, 'notes': notes, 'files': out}, indent=1).encode()


def public_der_b64(key):
    from cryptography.hazmat.primitives import serialization
    return base64.b64encode(key.public_key().public_bytes(serialization.Encoding.DER,
                                                          serialization.PublicFormat.SubjectPublicKeyInfo)).decode()


def sign_p256(manifest_bytes, path=None):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    with open(path or key_path(), 'rb') as f:
        k = serialization.load_pem_private_key(f.read(), None)
    if public_der_b64(k) != RELEASE_P256_PUB:
        sys.exit('release-p256.pem is not the key pinned in Walkdown (RELEASE_P256_PUB): phones would refuse the release.')
    return base64.b64encode(k.sign(DOMAIN2 + manifest_bytes, ec.ECDSA(hashes.SHA256()))).decode()


def verify_p256(manifest_bytes, sig_b64, pub_b64=RELEASE_P256_PUB):
    """what Walkdown checks (sync/Updates.kt); raises InvalidSignature"""
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    pub = serialization.load_der_public_key(base64.b64decode(pub_b64))
    pub.verify(base64.b64decode(sig_b64.strip()), DOMAIN2 + manifest_bytes, ec.ECDSA(hashes.SHA256()))


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
        from cryptography.hazmat.primitives import serialization as s
        from cryptography.hazmat.primitives.asymmetric import ec
        p = key_path()
        os.makedirs(os.path.dirname(p), exist_ok=True)
        k = ec.generate_private_key(ec.SECP256R1())
        fd = os.open(p, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)   # never overwrites an existing key
        with os.fdopen(fd, 'wb') as f:
            f.write(k.private_bytes(s.Encoding.PEM, s.PrivateFormat.PKCS8, s.NoEncryption()))
        print(f'Wrote {p}. Back it up offline. Pin its public key in tools/release.py (RELEASE_P256_PUB) and in '
              f'android/app2 sync/Updates.kt: {public_der_b64(k)}')
        return
    if not (a.version and a.dir):
        ap.error('VERSION and DIR are required')
    if not updates.VERSION_RE.fullmatch(a.version):
        sys.exit('VERSION looks like 1.2.3')
    if updates.current() != a.version:
        sys.exit(f'The VERSION file says {updates.current()}, not {a.version}: bump it, commit, build, then release.')
    files = {n: os.path.join(a.dir, n) for n in FILES if os.path.exists(os.path.join(a.dir, n))}
    missing = [n for n in FILES if n not in files]
    if missing:
        print('Missing (devices of that kind will not see this update):', ', '.join(missing))
    if not files:
        sys.exit('Nothing to release.')
    notes = open(a.notes).read().strip() if a.notes else ''
    m = manifest(a.version, files, notes)
    with open(os.path.join(a.dir, 'release.json'), 'wb') as f:
        f.write(m)
    with open(os.path.join(a.dir, 'release.json.p256'), 'w') as f:
        f.write(sign_p256(m) + '\n')
    verify_p256(m, open(os.path.join(a.dir, 'release.json.p256')).read())   # what the devices will check
    print(f'Signed release.json for {a.version}: {", ".join(files)}')
    if not a.publish:
        return
    if not a.yes and input(f'Create the public GitHub release v{a.version} with these files? [y/N] ').strip().lower() != 'y':
        return print('Not published.')
    cmd = ['gh', 'release', 'create', f'v{a.version}', '--repo', updates.REPO, '--title', f'Walkdown {a.version}',
           '--notes', notes or f'Walkdown {a.version}', *files.values(),
           os.path.join(a.dir, 'release.json'), os.path.join(a.dir, 'release.json.p256')]
    subprocess.run(cmd, check=True)


if __name__ == '__main__':
    main()
