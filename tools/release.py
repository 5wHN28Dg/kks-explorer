#!/usr/bin/env python3
"""Make a signed release (M5b self-updates; the whole procedure: docs/RELEASES.md). Runs on the maintainer's machine
only: the release key never goes into the repository or CI.

  python3 tools/release.py VERSION DIR [--notes FILE]          write DIR/release.json + DIR/release.json.sig
  python3 tools/release.py VERSION DIR [--notes FILE] --publish  ... then create GitHub release vVERSION with the files
                                                                   (asks first; needs the gh CLI, logged in)
  python3 tools/release.py --new-key                           create the release key (once; back it up offline)

DIR holds the files to ship: KKS-Explorer-windows.zip, KKS-Explorer-linux.tar.gz (from the Desktop packages workflow)
and kks-explorer.apk (built and signed locally: docs/ANDROID_RELEASE.md). The key: $KKS_SIGNING/release-ed25519.key or
~/.config/kks-explorer/signing/release-ed25519.key (the hex Ed25519 seed)."""
import argparse, base64, hashlib, json, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from server import updates

# kks-explorer-2.apk: the new Android app, installed by the v1 app's bridge release (0.8.1, decision 0042)
FILES = ('KKS-Explorer-windows.zip', 'KKS-Explorer-linux.tar.gz', 'kks-explorer.apk', 'kks-explorer-2.apk')


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


def sign(manifest_bytes, key):
    return base64.urlsafe_b64encode(key.sign(updates.DOMAIN + manifest_bytes)).rstrip(b'=').decode()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('version', nargs='?')
    ap.add_argument('dir', nargs='?')
    ap.add_argument('--notes')
    ap.add_argument('--publish', action='store_true')
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
        print(f'Wrote {p}. Back it up offline. Pin its public key in server/updates.py and Updates.kt: {public_b64u(k)}')
        return
    if not (a.version and a.dir):
        ap.error('VERSION and DIR are required')
    if not updates.VERSION_RE.fullmatch(a.version):
        sys.exit('VERSION looks like 1.2.3')
    if updates.current() != a.version:
        sys.exit(f'The VERSION file says {updates.current()}, not {a.version}: bump it, commit, build, then release.')
    key = load_key()
    if public_b64u(key) != updates.RELEASE_PUB:
        sys.exit('This key is not the one pinned in server/updates.py (RELEASE_PUB): devices would refuse the release.')
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
    with open(os.path.join(a.dir, 'release.json.sig'), 'w') as f:
        f.write(sign(m, key) + '\n')
    updates.verify(m, open(os.path.join(a.dir, 'release.json.sig')).read())   # what the devices will check
    print(f'Signed release.json for {a.version}: {", ".join(files)}')
    if not a.publish:
        return
    if input(f'Create the public GitHub release v{a.version} with these files? [y/N] ').strip().lower() != 'y':
        return print('Not published.')
    cmd = ['gh', 'release', 'create', f'v{a.version}', '--repo', updates.REPO, '--title', f'KKS Explorer {a.version}',
           '--notes', notes or f'KKS Explorer {a.version}', *files.values(),
           os.path.join(a.dir, 'release.json'), os.path.join(a.dir, 'release.json.sig')]
    subprocess.run(cmd, check=True)


if __name__ == '__main__':
    main()
