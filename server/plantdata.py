"""Plant data (drawings, tag lists, procedures, location list) delivered by the log (M5b, PROTOCOL.md §19).

The manager publishes a version as a `setting` entry, key `plant_data`, value
    {"version": n, "files": [[path, sha256 hex, size], ...]}
and every file travels as a blob by sync or bundle. A device serves the newest version whose files it holds completely
(never a mix of a new tag list with an old image). Paths not in the manifest fall back to the program's own data/
folder (KKS tables, courses). The manager's working copy, where the sheet importer writes, is `plant_dir`."""
import hashlib, json, os, re

PATH_RE = re.compile(r'(sheets/)?[a-z0-9][a-z0-9._-]{0,63}')
SHA_RE = re.compile(r'[0-9a-f]{64}')
ROOT_FILES = ('sheets.json', 'tags.json', 'procedures.json', 'locations.json')
MAX_FILES = 2000


def manifest(value):
    """A `plant_data` setting value -> {'version', 'files': {path: (sha, size)}}, or None if it isn't one."""
    if not isinstance(value, dict) or type(value.get('version')) is not int or value['version'] < 1:
        return None
    files = value.get('files')
    if not isinstance(files, list) or len(files) > MAX_FILES:
        return None
    out = {}
    for f in files:
        if not (isinstance(f, list) and len(f) == 3 and isinstance(f[0], str) and PATH_RE.fullmatch(f[0])
                and '..' not in f[0] and isinstance(f[1], str) and SHA_RE.fullmatch(f[1])
                and type(f[2]) is int and f[2] >= 0) or f[0] in out:
            return None
        out[f[0]] = (f[1], f[2])
    return {'version': value['version'], 'files': out}


def latest(E):
    return manifest(E.run.settings.get('plant_data')) if E.run else None


def wants(E):
    """Blobs of the latest version this node doesn't hold yet."""
    m = latest(E)
    return set() if not m else {sha for sha, _ in m['files'].values() if sha not in E.blob_files}


def active(E):
    """The version to serve: the latest if complete, else the last complete one this node served (meta)."""
    m = latest(E)
    if m and all(sha in E.blob_files for sha, _ in m['files'].values()):
        stored = E.store.meta('plant_data_active', None)
        if not stored or stored.get('version') != m['version'] or stored.get('files') != _plain(m):
            with E.store.write():
                E.store.put('meta', {'k': 'plant_data_active', 'v': json.dumps({'version': m['version'], 'files': _plain(m)})})
        return m
    stored = E.store.meta('plant_data_active', None)
    m = manifest(stored and {'version': stored.get('version'), 'files': stored.get('files')})
    if m and all(sha in E.blob_files for sha, _ in m['files'].values()):
        return m
    return None


def _plain(m):
    return [[p, sha, size] for p, (sha, size) in sorted(m['files'].items())]


def status(E):
    m, a = latest(E), active(E)
    missing = wants(E)
    return {'version': m['version'] if m else None, 'active': a['version'] if a else None,
            'files': len(m['files']) if m else 0, 'missing': len(missing),
            'missing_bytes': sum({sha: size for sha, size in (m['files'].values() if m else []) if sha in missing}.values())}


def file_for(E, cfg, path):
    """Filesystem path of plant file `path` in the active version, or None."""
    a = active(E)
    if not a or path not in a['files']:
        return None
    name = E.blob_files.get(a['files'][path][0])
    return os.path.join(cfg['photos_dir'], name) if name else None


def scan(folder):
    """The plant files in a working folder -> [(path, full path)]."""
    out = [(f, os.path.join(folder, f)) for f in ROOT_FILES if os.path.isfile(os.path.join(folder, f))]
    sd = os.path.join(folder, 'sheets')
    if os.path.isdir(sd):
        out += [(f'sheets/{f}', os.path.join(sd, f)) for f in sorted(os.listdir(sd))
                if PATH_RE.fullmatch(f'sheets/{f}') and os.path.isfile(os.path.join(sd, f))]
    return out


def publish(E, device, folder):
    """Make a new version from `folder` (the manager's device signs it). -> the new version number, or None when the
    files are the same as the latest version's."""
    files = scan(folder)
    if not any(p == 'sheets.json' for p, _ in files):
        raise ValueError(f'{folder} has no sheets.json')
    if len(files) > MAX_FILES:
        raise ValueError('too many files')
    listing = []
    for path, full in files:
        with open(full, 'rb') as f:
            data = f.read()
        sha = hashlib.sha256(data).hexdigest()
        E.blob_keep(sha, data)
        listing.append([path, sha, len(data)])
    m = latest(E)
    if m and _plain(m) == sorted(listing):
        return None
    version = (m['version'] if m else 0) + 1
    with E.tx() as c:
        E.append(c, device, 'setting', {'key': 'plant_data', 'value': {'version': version, 'files': sorted(listing)}})
    return version


def materialize(E, cfg, folder):
    """Write the active version into an empty working folder (a manager's device that got the data by sync, before
    its first import). -> number of files written."""
    a = active(E)
    if not a or os.path.exists(os.path.join(folder, 'sheets.json')):
        return 0
    os.makedirs(os.path.join(folder, 'sheets'), exist_ok=True)
    for path, (sha, _) in a['files'].items():
        with open(os.path.join(cfg['photos_dir'], E.blob_files[sha]), 'rb') as f:
            data = f.read()
        dst = os.path.join(folder, path)
        with open(dst + '.tmp', 'wb') as f:
            f.write(data)
        os.replace(dst + '.tmp', dst)
    return len(a['files'])


def ensure_working(E, cfg):
    """The importer's working folder exists: from the active version, else from the plant files a pre-M5b install kept
    in data_dir (so the first publish carries the existing sheets), else an empty plant."""
    folder = cfg['plant_dir']
    if materialize(E, cfg, folder) or os.path.exists(os.path.join(folder, 'sheets.json')):
        return
    os.makedirs(os.path.join(folder, 'sheets'), exist_ok=True)
    legacy = scan(cfg['data_dir'])
    if any(p == 'sheets.json' for p, _ in legacy):
        import shutil
        for path, full in legacy:
            shutil.copy2(full, os.path.join(folder, path))
        return
    for f in ('sheets.json', 'tags.json'):
        p = os.path.join(folder, f)
        if not os.path.exists(p):
            with open(p, 'w') as fh:
                json.dump([], fh)
