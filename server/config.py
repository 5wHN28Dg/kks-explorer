"""Server settings. Defaults below; override in config.json (or the file named by $KKS_CONFIG).
Relative paths are resolved against the repository folder, so another plant can point data_dir/db/photos_dir
at its own data without touching the code."""
import json, os

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULTS = {
    'plant_name': 'KKS Explorer',      # shown on the login screen (public)
    'host': '0.0.0.0', 'port': 8420,
    'public_url': '',                  # e.g. https://kks.example.ts.net; used in printed setup/reset links
    'data_dir': 'data',                # sheets.json, tags.json, procedures.json, kks.json, locations.json, sheets/*.png
    'db': 'plant.db', 'photos_dir': 'photos', 'backup_dir': 'backups',
    'tls_cert': '', 'tls_key': '',     # serve HTTPS directly (otherwise put a TLS proxy / Tailscale serve in front)
    'secure_cookies': False,           # set true whenever users reach the app over HTTPS (proxy or tls_cert)
    'session_days': 30,
    'offline_days': 7,                 # cached plant data stays usable offline this long without re-authenticating
    'admins_apply_directly': True,     # admin/manager edits apply immediately (still logged and revertible)
    'snapshot_every': 200,             # full DB snapshot after this many journaled writes
    'snapshot_keep': 30,
    'max_upload_mb': 15,
    'max_pdf_mb': 80,                  # P&ID PDF upload limit (Manage → Drawings)
    'import_python': '',               # interpreter with pymupdf/opencv/numpy; empty = .venv next to the app
    'root_key': '',                    # plant root key file (docs/PROTOCOL.md §8); empty = root.key next to the db
}
PATH_KEYS = ('data_dir', 'db', 'photos_dir', 'backup_dir', 'tls_cert', 'tls_key', 'import_python', 'root_key')


def load(path=None):
    path = path or os.environ.get('KKS_CONFIG') or os.path.join(BASE, 'config.json')
    cfg = dict(DEFAULTS)
    if os.path.exists(path):
        with open(path) as f:
            user = json.load(f)
        unknown = set(user) - set(DEFAULTS) - {'_comment'}
        if unknown:
            raise SystemExit(f'{path}: unknown setting(s) {sorted(unknown)}')
        cfg.update(user)
    root = os.path.dirname(os.path.abspath(path)) if os.path.exists(path) else BASE
    for k in PATH_KEYS:
        if cfg[k] and not os.path.isabs(cfg[k]):
            cfg[k] = os.path.normpath(os.path.join(root, cfg[k]))
    cfg['config_path'] = path
    return cfg
