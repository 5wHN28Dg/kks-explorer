"""`python3 app.py check`: audit a deployment. Each finding is (level, message); level is OK, INFO, WARN or FAIL.
Remote access model (see docs/REMOTE_ACCESS.md): the server listens on 127.0.0.1 only, cloudflared forwards to it,
and Cloudflare Access (plus cloudflared's own token check) stands in front. Anything else weakens that."""
import os, time
from urllib.parse import urlparse

LOOPBACK = ('127.0.0.1', '::1', 'localhost')
CLOUDFLARED_CONFIGS = ('/etc/cloudflared/config.yml', os.path.expanduser('~/.cloudflared/config.yml'))


def run(cfg, store, auth):
    out = []
    add = lambda level, msg: out.append((level, msg))
    url = urlparse(cfg['public_url'] or '')
    https = url.scheme == 'https'

    # ---- how the server is reached ----
    if not cfg['public_url']:
        add('INFO', 'public_url not set: local/LAN use only (offline mode needs HTTPS or localhost).')
    elif not https:
        add('WARN', f'public_url {cfg["public_url"]} is not HTTPS: offline mode and Secure cookies will not work.')
    if https and cfg['host'] not in LOOPBACK:
        add('FAIL', f'host is {cfg["host"]}: anyone on the LAN reaches the server over plain http, bypassing Cloudflare '
                    'Access. Set "host": "127.0.0.1" so the tunnel is the only way in.')
    elif cfg['host'] in LOOPBACK:
        add('OK', f'server listens on {cfg["host"]} only.')
    else:
        add('INFO', f'server listens on {cfg["host"]} (LAN) over plain http.')
    if https and not (cfg['secure_cookies'] or cfg['tls_cert']):
        add('FAIL', 'secure_cookies is false while public_url is HTTPS: set "secure_cookies": true.')
    elif https:
        add('OK', 'session cookie is Secure; HSTS is sent.')

    # ---- cloudflared ----
    found = [p for p in CLOUDFLARED_CONFIGS if os.path.exists(p)]
    for p in found:
        try:
            text = open(p).read()
        except OSError as e:
            add('WARN', f'{p}: cannot read ({e.strerror}); run check with sudo to verify it.')
            continue
        port = str(cfg['port'])
        if f'127.0.0.1:{port}' in text or f'localhost:{port}' in text:
            add('OK', f'{p}: forwards to this server (port {port}).')
        else:
            add('WARN', f'{p}: no ingress to 127.0.0.1:{port} found.')
        if 'access:' in text and 'required: true' in text and 'audTag' in text:
            add('OK', f'{p}: cloudflared rejects requests without a valid Access token.')
        else:
            add('FAIL', f'{p}: originRequest.access (required: true, teamName, audTag) missing. Without it, a mistake in '
                        'the Access policy in the Cloudflare dashboard would expose the login page to the internet.')
        if url.hostname and url.hostname not in text:
            add('WARN', f'{p}: hostname {url.hostname} (public_url) not found in the ingress rules.')
    if https and not found:
        add('INFO', 'no cloudflared config at ' + ' or '.join(CLOUDFLARED_CONFIGS) + ' (fine if the tunnel runs elsewhere).')

    # ---- accounts ----
    c = store.conn()
    try:
        if not auth.manager(c):
            add('FAIL', 'no manager account: start the server and open the setup link it prints.')
        else:
            add('OK', 'manager account exists.')
        n = c.execute('SELECT COUNT(*) FROM users WHERE pw IS NULL AND active=1').fetchone()[0]
        if n:
            add('INFO', f'{n} account(s) created but the password link not used yet.')
    finally:
        c.close()

    # ---- data ----
    for f in ('sheets.json', 'tags.json', 'procedures.json', 'kks.json'):
        if not os.path.exists(os.path.join(cfg['data_dir'], f)):
            add('FAIL' if f in ('sheets.json', 'tags.json') else 'WARN', f'{cfg["data_dir"]}/{f} missing.')
    if not os.access(cfg['photos_dir'], os.W_OK):
        add('FAIL', f'photos_dir {cfg["photos_dir"]} is not writable.')

    # ---- backups ----
    snaps = store.snapshots()
    if not snaps:
        add('FAIL', 'no snapshot in backup_dir.')
    else:
        age = (time.time() - os.path.getmtime(snaps[-1][1])) / 86400
        add('OK' if age < 7 else 'WARN', f'latest snapshot {age:.1f} days old ({len(snaps)} kept).')
    same = os.stat(cfg['backup_dir']).st_dev == os.stat(os.path.dirname(cfg['db'])).st_dev
    if same:
        add('WARN', 'backups are on the same disk as the database: copy backup_dir and photos_dir to another machine '
                    'regularly (see README, "History, restore and backups").')
    return out
