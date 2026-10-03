"""Self-updates from GitHub Releases (M5b, https://github.com/5wHN28Dg/kks-explorer/wiki/Releasing).

A release carries `release.json` = {"app": "kks-explorer", "version": "X.Y.Z", "notes": str, "files": {name: {"sha256",
"size"}}} and `release.json.sig` = base64url Ed25519 signature over b"kks-release-v1\n" + the exact bytes of
release.json, made with the maintainer's release key (kept offline, like the APK signing key). The public half is
pinned below, so a release counts only if that key signed it; GitHub (or whoever controls the account) can't push an
update on its own. Every downloaded file must match its hash in the signed manifest.

Checks at most once a day and only asks: nothing is installed without a click. A packaged desktop app downloads the
new version into the user folder and runs it from the next start on (desktop.py hands over to it); a server or
laptop running from source only shows that a new version exists (update it with git)."""
import base64, hashlib, io, json, os, re, shutil, sys, tarfile, threading, time, urllib.request, zipfile

from server.config import BASE

REPO = '5wHN28Dg/kks-explorer'
RELEASE_PUB = 'YBHkaex01_tOIIUiI8kZMAHCwUF-aHIGYJtR0jnENtM'   # base64url raw Ed25519 public key
DOMAIN = b'kks-release-v1\n'
DAY = 24 * 3600
ASSETS = {'win32': 'KKS-Explorer-windows.zip', 'linux': 'KKS-Explorer-linux.tar.gz'}
VERSION_RE = re.compile(r'\d{1,4}\.\d{1,4}\.\d{1,4}')


def current():
    try:
        with open(os.path.join(BASE, 'VERSION')) as f:
            return f.read().strip()
    except OSError:
        return '0.0.0'


def vtuple(v):
    return tuple(int(x) for x in v.split('.')) if isinstance(v, str) and VERSION_RE.fullmatch(v) else (0, 0, 0)


def frozen():
    return bool(getattr(sys, 'frozen', False))


def _b64u(s):
    return base64.urlsafe_b64decode(s + '=' * (-len(s) % 4))


def verify(manifest_bytes, sig_text, pub=RELEASE_PUB):
    """-> the manifest if the release key signed it, else raises ValueError."""
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
    from cryptography.exceptions import InvalidSignature
    try:
        Ed25519PublicKey.from_public_bytes(_b64u(pub)).verify(_b64u(sig_text.strip()), DOMAIN + manifest_bytes)
    except (InvalidSignature, ValueError) as e:
        raise ValueError('the release is not signed by the KKS Explorer release key') from e
    m = json.loads(manifest_bytes)
    if not (isinstance(m, dict) and m.get('app') == 'kks-explorer' and VERSION_RE.fullmatch(str(m.get('version')))
            and isinstance(m.get('files'), dict)):
        raise ValueError('not a KKS Explorer release manifest')
    for name, f in m['files'].items():
        if not (isinstance(f, dict) and re.fullmatch(r'[0-9a-f]{64}', str(f.get('sha256'))) and type(f.get('size')) is int):
            raise ValueError(f'bad entry for {name}')
    return m


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers={'User-Agent': 'kks-explorer-updater', 'Accept': 'application/octet-stream, application/json'})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def fetch_latest(api=None, pub=RELEASE_PUB):
    """The newest release: -> {'version', 'notes', 'files', 'urls': {asset name: download url}}. Raises on anything wrong."""
    api = api or f'https://api.github.com/repos/{REPO}/releases/latest'
    rel = json.loads(_get(api))
    urls = {a['name']: a['browser_download_url'] for a in rel.get('assets') or [] if 'name' in a}
    if 'release.json' not in urls or 'release.json.sig' not in urls:
        raise ValueError('the latest release has no signed manifest')
    m = verify(_get(urls['release.json']), _get(urls['release.json.sig']).decode(), pub)
    return {'version': m['version'], 'notes': str(m.get('notes') or '')[:4000], 'files': m['files'], 'urls': urls}


class Updater:
    """One per process. `home`: where a packaged app keeps downloaded versions (its user folder), else None."""
    def __init__(self, cfg, store, home=None, api=None, log=print, pub=RELEASE_PUB):
        self.cfg, self.store, self.home, self.api, self.log, self.pub = cfg, store, home, api, log, pub
        self.lock = threading.Lock()
        self.latest, self.error, self.busy = None, None, None
        saved = store.meta('update', None) or {}
        self.checked = saved.get('checked', 0)
        if saved.get('latest'):
            self.latest = saved['latest']

    # ---------- checking ----------
    def check(self):
        with self.lock:
            try:
                self.latest, self.error = fetch_latest(self.api, self.pub), None
            except Exception as e:   # noqa: BLE001 - offline, rate-limited, unsigned: all just "couldn't check"
                self.error = f'{type(e).__name__}: {e}'[:300]
            self.checked = int(time.time())
            with self.store.write():
                self.store.put('meta', {'k': 'update', 'v': json.dumps({'checked': self.checked, 'latest': self.latest})})
        return self.status()

    def start(self):
        """Background: check now if the last check is a day old, then daily. `update_check: false` turns it off."""
        if not self.cfg.get('update_check', True):
            return
        def loop():
            time.sleep(20)   # (not while the program is starting)
            while True:
                if time.time() - self.checked >= DAY:
                    self.check()
                time.sleep(3600)
        threading.Thread(target=loop, daemon=True).start()

    # ---------- state for the UI ----------
    def staged(self):
        r = self._ready()
        return r['version'] if r and vtuple(r['version']) > vtuple(current()) else None

    def status(self):
        lat = self.latest or {}
        available = vtuple(lat.get('version')) > vtuple(current())
        asset = ASSETS.get(sys.platform)
        return {'current': current(), 'latest': lat.get('version'), 'notes': lat.get('notes'), 'available': available,
                'checked': self.checked or None, 'error': self.error, 'auto': bool(self.cfg.get('update_check', True)),
                'how': 'install' if frozen() and self.home and asset else 'git',
                'can_install': available and frozen() and bool(self.home) and asset in (lat.get('files') or {}),
                'staged': self.staged(), 'busy': self.busy,
                'page': f'https://github.com/{REPO}/releases/tag/v{lat["version"]}' if lat.get('version') else None}

    # ---------- installing (packaged desktop app) ----------
    def versions_dir(self):
        return os.path.join(self.home, 'versions')

    def _ready(self):
        if not self.home:
            return None
        try:
            with open(os.path.join(self.versions_dir(), 'ready.json')) as f:
                r = json.load(f)
            return r if isinstance(r, dict) and VERSION_RE.fullmatch(str(r.get('version'))) else None
        except (OSError, ValueError):
            return None

    def install(self):
        """Download the latest version for this platform, check it against the signed manifest, unpack it next to the
        user's data. It runs from the next start. -> status"""
        st = self.status()
        if not st['can_install']:
            raise ValueError('No update to install here.' if not st['available'] else
                             'This copy runs from source: update it with git (git pull).')
        with self.lock:
            if self.busy:
                raise ValueError('An update is already downloading.')
            self.busy = 'downloading'
        try:
            lat = self.latest
            name = ASSETS[sys.platform]
            want = lat['files'][name]
            data = _get(lat['urls'][name], timeout=600)
            if len(data) != want['size'] or hashlib.sha256(data).hexdigest() != want['sha256']:
                raise ValueError('the download does not match the signed release (corrupted or tampered): not installed')
            self.busy = 'unpacking'
            dst = os.path.join(self.versions_dir(), lat['version'])
            tmp = dst + '.part'
            shutil.rmtree(tmp, ignore_errors=True)
            os.makedirs(tmp)
            unpack(name, data, tmp)
            exe = os.path.join(dst, 'KKS Explorer', 'KKS Explorer.exe' if sys.platform == 'win32' else 'KKS Explorer')
            if not os.path.isfile(os.path.join(tmp, os.path.relpath(exe, dst))):
                raise ValueError('the package has no program in it')
            shutil.rmtree(dst, ignore_errors=True)
            os.replace(tmp, dst)
            with open(os.path.join(self.versions_dir(), 'ready.json.tmp'), 'w') as f:
                json.dump({'version': lat['version'], 'exe': exe}, f)
            os.replace(os.path.join(self.versions_dir(), 'ready.json.tmp'), os.path.join(self.versions_dir(), 'ready.json'))
            self.log(f'update {lat["version"]} ready: it runs from the next start')
        finally:
            self.busy = None
        return self.status()


def unpack(name, data, dst):
    """Only the 'KKS Explorer/' folder, never outside dst (the archive is signed, but belt and braces)."""
    root = os.path.realpath(dst)
    def safe(member):
        p = os.path.realpath(os.path.join(dst, member))
        return member.startswith('KKS Explorer/') and p.startswith(root + os.sep)
    if name.endswith('.zip'):
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for info in z.infolist():
                if safe(info.filename):
                    z.extract(info, dst)
    else:
        with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as t:
            members = [m for m in t.getmembers() if safe(m.name) and (m.isfile() or m.isdir() or m.issym())]
            t.extractall(dst, members=members, filter='data')


def handoff(home, argv):
    """desktop.py, first thing on start: if a newer verified version is unpacked in the user folder, run that instead.
    -> True if it was started (the caller exits)."""
    try:
        with open(os.path.join(home, 'versions', 'ready.json')) as f:
            r = json.load(f)
    except (OSError, ValueError):
        return False
    if not frozen() or os.environ.get('KKS_HANDOFF') or vtuple(r.get('version')) <= vtuple(current()):
        return False
    exe = r.get('exe')
    if not isinstance(exe, str) or not os.path.isfile(exe):
        return False
    import subprocess
    subprocess.Popen([exe] + argv[1:], env={**os.environ, 'KKS_HANDOFF': '1'}, close_fds=True)
    return True


def cleanup(home):
    """Keep the running version and the newest one; remove older unpacked versions."""
    vd = os.path.join(home, 'versions')
    if not os.path.isdir(vd):
        return
    keep = {current()}
    try:
        with open(os.path.join(vd, 'ready.json')) as f:
            keep.add(json.load(f).get('version'))
    except (OSError, ValueError):
        pass
    for d in os.listdir(vd):
        if VERSION_RE.fullmatch(d.removesuffix('.part')) and (d not in keep or d.endswith('.part')):
            shutil.rmtree(os.path.join(vd, d), ignore_errors=True)
