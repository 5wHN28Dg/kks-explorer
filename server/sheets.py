"""Adding and removing P&ID sheets from the app (Manage → Drawings).

The server stays standard-library only: the importer (import_sheet.py, which needs pymupdf/opencv/numpy) runs as a
separate process with the importer venv's Python. One import at a time (CPU-heavy, and it rewrites sheets.json and
tags.json). Before every change, sheets.json + tags.json are copied to backups/sheets-<time>/; a failed import puts
them back. Uploaded PDFs are kept in backups/sheet-sources/ (not under data/, so users can't download them) so a
sheet can be re-imported with a different rotation without uploading again."""
import json, os, re, shutil, subprocess, sys, threading, time

from server.config import BASE

SHEET_ID = re.compile(r'^[a-z0-9][a-z0-9-]{0,23}$')
DEPS = ('pymupdf', 'cv2', 'numpy')
REQUIREMENTS = os.path.join(BASE, 'requirements-import.txt')


def venv_python(cfg):
    """The importer's interpreter: config import_python, else .venv next to the app."""
    if cfg.get('import_python'):
        return cfg['import_python']
    for p in (os.path.join(BASE, '.venv', 'bin', 'python'), os.path.join(BASE, '.venv', 'Scripts', 'python.exe')):
        if os.path.exists(p):
            return p
    return None


def importer_status(cfg):
    py = venv_python(cfg)
    if not py:
        return {'available': False, 'python': None, 'error': 'No importer environment. On the server run: python3 app.py setup-importer'}
    try:
        r = subprocess.run([py, '-c', 'import ' + ','.join(DEPS)], capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as e:
        return {'available': False, 'python': py, 'error': str(e)}
    if r.returncode:
        return {'available': False, 'python': py, 'error': (r.stderr.strip().splitlines() or ['import failed'])[-1] +
                ' (run: python3 app.py setup-importer)'}
    return {'available': True, 'python': py, 'error': None}


def setup_importer():
    """CLI: create .venv and install the importer's packages into it (never system-wide)."""
    venv = os.path.join(BASE, '.venv')
    if not os.path.exists(venv):
        print(f'Creating {venv} ...')
        subprocess.run([sys.executable, '-m', 'venv', venv], check=True)
    py = os.path.join(venv, 'Scripts', 'python.exe') if os.name == 'nt' else os.path.join(venv, 'bin', 'python')
    print('Installing importer packages (pymupdf, opencv-python-headless, numpy) ...')
    subprocess.run([py, '-m', 'pip', 'install', '--upgrade', 'pip', '-q'], check=True)
    subprocess.run([py, '-m', 'pip', 'install', '-r', REQUIREMENTS], check=True)
    st = importer_status({})
    print('Importer ready.' if st['available'] else f'Something is still missing: {st["error"]}')


def sheet_summary(cfg):
    if not os.path.exists(os.path.join(cfg['plant_dir'], 'sheets.json')):
        return []
    sheets = json.load(open(os.path.join(cfg['plant_dir'], 'sheets.json')))
    tags = json.load(open(os.path.join(cfg['plant_dir'], 'tags.json')))
    count = {}
    for t in tags:
        c = count.setdefault(t['sheet'], {'auto': 0, 'verified': 0, 'review': 0})
        c[t['status']] = c.get(t['status'], 0) + 1
    src_dir = os.path.join(cfg['backup_dir'], 'sheet-sources')
    return [{**s, 'tags': count.get(s['id'], {}), 'has_source': os.path.exists(os.path.join(src_dir, s['id'] + '.pdf'))}
            for s in sheets]


class Importer:
    def __init__(self, cfg):
        self.cfg, self.lock, self.job = cfg, threading.Lock(), None
        self.src_dir = os.path.join(cfg['backup_dir'], 'sheet-sources')
        os.makedirs(self.src_dir, exist_ok=True)

    def _backup(self, why, sid):
        d = os.path.join(self.cfg['backup_dir'], f'sheets-{time.strftime("%Y%m%d-%H%M%S")}-{why}-{sid}')
        os.makedirs(d, exist_ok=True)
        for f in ('sheets.json', 'tags.json'):
            shutil.copy2(os.path.join(self.cfg['plant_dir'], f), d)
        for f in (sid + '.png', sid + '.svg.gz'):  # a replace re-renders these; keep the old ones to match the old tags
            if os.path.exists(os.path.join(self.cfg['plant_dir'], 'sheets', f)):
                shutil.copy2(os.path.join(self.cfg['plant_dir'], 'sheets', f), d)
        return d

    def _restore(self, d, sid):
        for f in ('sheets.json', 'tags.json', sid + '.png', sid + '.svg.gz'):
            src = os.path.join(d, f)
            dst = os.path.join(self.cfg['plant_dir'], '' if f.endswith('.json') else 'sheets', f)
            if os.path.exists(src):
                shutil.copy2(src, dst + '.tmp')
                os.replace(dst + '.tmp', dst)

    def busy(self):
        return bool(self.job and self.job['state'] == 'running')

    def start(self, user, sid, name, rotate, replace, pdf_bytes=None, on_done=None):
        """Start an import in the background. pdf_bytes=None re-imports from the stored source PDF."""
        if not SHEET_ID.match(sid or ''):
            raise ValueError('Sheet id: 1-24 lowercase letters, digits, dashes (start with a letter or digit).')
        current = {s['id']: s for s in json.load(open(os.path.join(self.cfg['plant_dir'], 'sheets.json')))}
        if not (name or '').strip() and replace and sid in current:
            name = current[sid]['name']  # re-import keeps the name
        if not (name or '').strip() or len(name) > 80:
            raise ValueError('Give the sheet a name (up to 80 characters).')
        if rotate not in ('auto', '0', '90', '180', '270'):
            raise ValueError('bad rotation')
        if sid in current and not replace:
            raise ValueError(f'A sheet with id "{sid}" exists. Pick another id, or choose to replace it.')
        src = os.path.join(self.src_dir, sid + '.pdf')
        if pdf_bytes is None and not os.path.exists(src):
            raise ValueError('No stored PDF for this sheet: upload it again.')
        if pdf_bytes is not None and not pdf_bytes.startswith(b'%PDF-'):
            raise ValueError('That file is not a PDF.')
        py = venv_python(self.cfg)
        if not py:
            raise ValueError(importer_status(self.cfg)['error'])
        with self.lock:
            if self.busy():
                raise ValueError('Another import is running. Wait for it to finish.')
            if pdf_bytes is not None:
                with open(src + '.tmp', 'wb') as f:
                    f.write(pdf_bytes)
                os.replace(src + '.tmp', src)
            self.job = {'id': int(time.time() * 1000), 'sheet': sid, 'name': name.strip(), 'rotate': rotate,
                        'by': user['username'], 'state': 'running', 'log': [], 'result': None, 'started': int(time.time())}
            job = self.job
        cmd = [py, '-u', os.path.join(BASE, 'import_sheet.py'), src, name.strip(), sid, '--rotate', rotate,
               '--data-dir', self.cfg['plant_dir']] + (['--replace'] if replace else [])
        threading.Thread(target=self._run, args=(job, cmd, on_done), daemon=True).start()
        return job

    def _run(self, job, cmd, on_done):
        backup = self._backup('import', job['sheet'])
        try:
            p = subprocess.Popen(cmd, cwd=BASE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in p.stdout:
                line = line.rstrip()
                if line.startswith('RESULT '):
                    job['result'] = json.loads(line[7:])
                elif line:
                    job['log'] = (job['log'] + [line])[-300:]
            p.wait(timeout=3600)
            ok = p.returncode == 0 and job['result']
        except Exception as e:  # noqa: BLE001 - anything here means the import failed; report it
            job['log'].append(f'Importer crashed: {e}')
            ok = False
        if not ok:
            self._restore(backup, job['sheet'])
            job['log'].append('Import failed; the sheet list and tags were left as they were before.')
        job['state'] = 'done' if ok else 'failed'
        job['finished'] = int(time.time())
        if on_done:
            on_done(job)

    def remove(self, sid):
        """Take a sheet out of the app. Its image and source PDF are kept (in backups) so nothing is lost."""
        with self.lock:
            if self.busy():
                raise ValueError('An import is running. Wait for it to finish.')
            sheets_p, tags_p = (os.path.join(self.cfg['plant_dir'], f) for f in ('sheets.json', 'tags.json'))
            sheets, tags = json.load(open(sheets_p)), json.load(open(tags_p))
            if not any(s['id'] == sid for s in sheets):
                raise ValueError('No such sheet.')
            if len(sheets) == 1:
                raise ValueError('That is the only sheet; add another before removing it.')
            backup = self._backup('remove', sid)  # includes the image and vector file
            for f in (sid + '.png', sid + '.svg.gz'):
                if os.path.exists(os.path.join(self.cfg['plant_dir'], 'sheets', f)):
                    os.remove(os.path.join(self.cfg['plant_dir'], 'sheets', f))
            n = sum(1 for t in tags if t['sheet'] == sid)
            for path, obj, kw in ((tags_p, [t for t in tags if t['sheet'] != sid], {}),
                                  (sheets_p, [s for s in sheets if s['id'] != sid], {'indent': 1})):
                with open(path + '.tmp', 'w') as f:
                    json.dump(obj, f, **kw)
                os.replace(path + '.tmp', path)
            return {'removed': sid, 'tags': n, 'backup': backup}

