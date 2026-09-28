#!/usr/bin/env python3
"""Plant P&ID / KKS Explorer - server. Standard library + `cryptography` (the signed log, docs/PROTOCOL.md).

  python3 app.py                          run the server (settings: config.json, see config.example.json)
  python3 app.py users                    list accounts
  python3 app.py reset-manager --user X   make X the manager (break-glass; shell access only) + password link
  python3 app.py reset-password --user X  print a one-time password link for X
  python3 app.py backup                   take a full snapshot now
  python3 app.py restore [--seq N] [--out FILE]   rebuild the DB from backups into a NEW file
  python3 app.py check                    audit the deployment (remote access, cookies, backups); exit 1 on FAIL
  python3 app.py setup-importer           create .venv with the P&ID importer's packages (for Manage → Drawings)
  python3 app.py added-tags               print the tags users marked by hand on the drawings (JSON)
  python3 app.py export-root-key --out F  write the plant root key, encrypted with a passphrase, to F (keep it safe)
  python3 app.py import-root-key --file F put a root key backup back (e.g. on a new server)
  python3 app.py sync HOST[:PORT]          sync with another device now (it must be listening, default port 8421)

The app shell (index.html, admin.html, *.js) is public. Plant data (/data, /photos, /api) needs a login."""
import argparse, getpass, gzip, json, mimetypes, os, re, secrets, socket, ssl, sys, threading, time, traceback
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote, parse_qs

try:
    import cryptography  # noqa: F401  (the signed log needs Ed25519)
except ImportError:
    if __name__ == '__main__' and sys.argv[1:2] == ['setup-importer']:   # the command that installs it
        from server import sheets as _sheets
        _sheets.setup_importer()
        raise SystemExit(0)
    raise SystemExit('The server needs the "cryptography" package.\n'
                     '  Debian/Ubuntu: sudo apt install python3-cryptography\n'
                     '  or: python3 app.py setup-importer, then run the server with .venv/bin/python app.py')
from server import config as config_mod
from server.store import Store, restore
from server.auth import Auth, hash_password, password_problem, public_user, rank, person
from server import changes as ch
from server.engine import Engine, NoRootKey, tag_out
from peer import proto as proto_mod, sync as sync_mod
from server import node as node_mod
from server.syncsvc import SyncService, lan_addresses
from server.invites import Invites
from server import check as check_mod
from server import sheets as sheets_mod
from server import photos as photos_mod
from server import progress as progress_mod

BASE = config_mod.BASE
SHELL = {'/': 'index.html', '/index.html': 'index.html', '/admin.html': 'admin.html', '/common.js': 'common.js', '/qrcodegen.js': 'qrcodegen.js', '/course-bridge.js': 'course-bridge.js', '/learning.html': 'learning.html',
         '/sw.js': 'sw.js', '/manifest.webmanifest': 'manifest.webmanifest', '/icon.svg': 'icon.svg',
         '/icon-192.png': 'icon-192.png', '/icon-512.png': 'icon-512.png'}
COOKIE = 'kks_session'
mimetypes.add_type('image/jxl', '.jxl')
mimetypes.add_type('application/wasm', '.wasm')
mimetypes.add_type('text/javascript', '.js')
USERNAME_RE = re.compile(r'[A-Za-z0-9_.@-]{2,40}')  # ASCII: usernames go into the signed log (PROTOCOL.md §9a)


class HTTPError(Exception):
    def __init__(self, code, msg, extra=None):
        super().__init__(msg)
        self.code, self.msg, self.extra = code, msg, extra or {}


def P_id(E):
    """This node's device ID (what other devices see when it connects), or None before it has one."""
    try:
        return proto_mod.peer_id(E.identity())
    except Exception:
        return None


def users_map(c):
    """{user id: row, person ID: row}"""
    m = {}
    for r in c.execute('SELECT * FROM users'):
        m[r['id']] = r
        if r['person']:
            m[r['person']] = r
    return m


def person_body(E, pid, **upd):
    cur = E.run.persons[pid]
    return {'person': pid, 'username': cur['username'], 'full_name': upd.get('full_name', cur['full_name']),
            'position': upd.get('position', cur['position']), 'role': upd.get('role', cur['role'])}


def make_handler(cfg, store, auth, engine=None, svc=None):
    E = engine or Engine(store, cfg)
    svc = svc or SyncService(E, cfg, log=lambda *a: None)
    invites = E.invites = Invites()   # join by invite: QR codes this node shows (in memory)
    joining = {}                      # peer mode, not joined yet: the running join by invite ('job')
    PEER = cfg['mode'] == 'peer'
    LOCAL_HOSTS = {'localhost', '127.0.0.1', '[::1]', '::1'}
    importer = sheets_mod.Importer(cfg)
    importer_state = {'at': 0, 'status': None}

    def importer_status():  # starting the venv's Python to check imports takes ~1 s: cache it
        if time.time() - importer_state['at'] > 60 or not importer_state['status']['available']:
            importer_state.update(at=time.time(), status=sheets_mod.importer_status(cfg))
        return importer_state['status']

    def log_sheet(actor_id, sid, note):  # sheet changes live in data/*.json, not the DB: log them for History only
        with store.write():
            store.put('revisions', {'ts': int(time.time()), 'actor': actor_id, 'entity': 'sheet', 'key': sid,
                                    'before': None, 'after': None, 'submission_id': None, 'note': note})

    def link(path):
        return (cfg['public_url'] or f'http://localhost:{cfg["port"]}').rstrip('/') + path

    class H(BaseHTTPRequestHandler):
        server_version = 'KKSExplorer'
        sys_version = ''

        def log_message(self, *a):
            pass

        # ---------- responses ----------
        def _headers(self, code, ctype, length, extra=()):
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(length))
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Referrer-Policy', 'no-referrer')
            self.send_header('X-Frame-Options', 'DENY')
            if cfg['public_url'].startswith('https://'):
                self.send_header('Strict-Transport-Security', 'max-age=31536000')
            for k, v in extra:
                self.send_header(k, v)
            self.end_headers()

        def send(self, obj, code=200, extra=()):
            b = json.dumps(obj).encode()
            self._headers(code, 'application/json', len(b), [('Cache-Control', 'no-store'), *extra])
            self.wfile.write(b)

        def file(self, path, cache):
            extra = [('Cache-Control', cache)]
            if not os.path.isfile(path) and os.path.isfile(path + '.gz'):
                # sheet vectors are stored gzipped (data/sheets/<id>.svg.gz): send as-is to browsers that accept it
                with open(path + '.gz', 'rb') as f:
                    data = f.read()
                extra.append(('Vary', 'Accept-Encoding'))
                if 'gzip' in (self.headers.get('Accept-Encoding') or ''):
                    extra.append(('Content-Encoding', 'gzip'))
                else:
                    data = gzip.decompress(data)
            elif os.path.isfile(path):
                with open(path, 'rb') as f:
                    data = f.read()
            else:
                raise HTTPError(404, 'not found')
            ctype = 'application/manifest+json' if path.endswith('.webmanifest') else \
                mimetypes.guess_type(path)[0] or 'application/octet-stream'
            self._headers(200, ctype, len(data), extra)
            self.wfile.write(data)

        def cookie(self, raw, max_age):
            secure = '; Secure' if (cfg['secure_cookies'] or cfg['tls_cert']) else ''
            return ('Set-Cookie', f'{COOKIE}={raw}; Path=/; HttpOnly; SameSite=Strict; Max-Age={max_age}{secure}')

        # ---------- request helpers ----------
        def session_raw(self):
            c = SimpleCookie(self.headers.get('Cookie', ''))
            return c[COOKIE].value if COOKIE in c else None

        def user(self, need=None):
            u = E.owner() if PEER else auth.user_for_session(self.session_raw())
            if not u:
                raise HTTPError(401, 'login required')
            if need and rank(u['role']) < rank(need):
                raise HTTPError(403, f'{need} only')
            return u

        def body(self):
            n = int(self.headers.get('Content-Length') or 0)
            if n > cfg['max_upload_mb'] * 1024 * 1024 * 1.4 + 65536:
                raise HTTPError(413, 'request too large')
            try:
                d = json.loads(self.rfile.read(n) or b'{}')
            except ValueError:
                raise HTTPError(400, 'bad json')
            if not isinstance(d, dict):
                raise HTTPError(400, 'bad json')
            return d

        def ip(self):
            # Behind a proxy on this machine (Tailscale serve, cloudflared) every request comes from loopback; use the
            # address the proxy appended so login throttling stays per client. Only trusted from loopback.
            peer = self.client_address[0]
            fwd = self.headers.get('X-Forwarded-For')
            if fwd and peer in ('127.0.0.1', '::1'):
                return fwd.split(',')[-1].strip() or peer
            return peer

        # ---------- dispatch ----------
        def handle_errors(self, fn):
            try:
                fn()
            except HTTPError as e:
                self.send({'error': e.msg, **e.extra}, e.code)
            except ch.Conflict as e:
                self.send({'error': 'conflict', 'conflicts': e.detail}, 409)
            except ch.Bad as e:
                self.send({'error': str(e)}, 400)
            except ch.Denied as e:
                self.send({'error': str(e)}, 403)
            except ch.Gone as e:
                self.send({'error': str(e)}, 409)
            except ch.NotFound as e:
                self.send({'error': str(e)}, 404)
            except NoRootKey as e:
                self.send({'error': str(e)}, 409)
            except (BrokenPipeError, ConnectionResetError):
                pass
            except Exception:   # a bug: say so in the console, don't just drop the connection
                traceback.print_exc()
                self.send({'error': 'internal error (see the server console)'}, 500)

        def local_ok(self):
            """Peer mode has no password: only this machine may use it. The Host check stops DNS rebinding (a web
            page whose own name points at 127.0.0.1 would otherwise count as same-origin)."""
            if not PEER:
                return True
            host = (self.headers.get('Host') or '').rsplit(':', 1)[0]
            if self.client_address[0] in ('127.0.0.1', '::1') and host in LOCAL_HOSTS:
                return True
            self.send({'error': 'this app only answers on this computer'}, 403)
            return False

        def do_GET(self):
            if self.local_ok():
                self.handle_errors(self.get)

        def do_POST(self):
            if not self.local_ok():
                return
            # JSON-only API + same-origin check: a form on another site can't post here with the session cookie.
            origin = self.headers.get('Origin')
            allowed = {self.headers.get('Host'), self.headers.get('X-Forwarded-Host'), urlparse(cfg['public_url']).netloc} - {None, ''}
            if origin and urlparse(origin).netloc not in allowed:
                return self.send({'error': 'cross-origin request refused'}, 403)
            ctype = self.headers.get('Content-Type') or ''
            if urlparse(self.path).path == '/api/sheets/import' and ctype.startswith('application/pdf'):
                return self.handle_errors(self.post_pdf)  # raw PDF body; not a type a cross-site form can send
            if urlparse(self.path).path == '/api/bundle/import' and ctype.startswith(('application/gzip', 'application/octet-stream')):
                return self.handle_errors(self.post_bundle)
            if not ctype.startswith('application/json'):
                return self.send({'error': 'JSON only'}, 415)
            self.handle_errors(self.post)

        def get(self):
            u = urlparse(self.path)
            p, q = unquote(u.path), {k: v[0] for k, v in parse_qs(u.query).items()}
            if p in SHELL:
                return self.file(os.path.join(BASE, SHELL[p]), 'no-cache')
            if p.startswith('/vendor/'):   # public third-party code (vendor/jxl: the JXL decoder for browsers)
                full = os.path.realpath(os.path.join(BASE, p[1:]))
                if not full.startswith(os.path.join(os.path.realpath(BASE), 'vendor') + os.sep):
                    raise HTTPError(400, 'bad path')
                return self.file(full, 'no-cache')
            if p == '/api/config':
                c = store.conn()
                try:
                    has_manager = bool(auth.manager(c))
                finally:
                    c.close()
                out = {'plant_name': cfg['plant_name'], 'offline_days': cfg['offline_days'], 'mode': cfg['mode'],
                       'setup_needed': not has_manager and not PEER,
                       # how to send photos: they become JXL here; a local page sends lossless PNG, a remote one a
                       # near-lossless JPEG (less to upload); without a JXL encoder the JPEG is what gets kept
                       'photo_upload': ({'type': 'image/png'} if PEER else {'type': 'image/jpeg', 'q': 0.95}) | {'ms_per_mp': photos_mod.ms_per_mp}
                                       if photos_mod.AVAILABLE else {'type': 'image/jpeg', 'q': 0.85}}
                if PEER:
                    owner = E.owner()
                    out['node'] = {'joined': bool(owner), 'device': E.node_device(), 'has_plant': E.anchor is not None,
                                   'plant': E.run.settings.get('plant') if E.run else None,
                                   'removed': None if owner else store.meta('removed')}
                    if E.run and E.run.settings.get('plant'):
                        out['plant_name'] = E.run.settings['plant']
                return self.send(out)
            if p == '/api/token-info':
                c = store.conn()
                try:
                    t = auth.peek_token(q.get('kind', ''), q.get('token'), c)
                    if not t or q.get('kind') not in ('setup', 'reset'):
                        raise HTTPError(404, 'This link is invalid or has expired.')
                    usr = c.execute('SELECT username FROM users WHERE id=?', (t['user_id'],)).fetchone()
                    return self.send({'kind': t['kind'], 'username': usr['username'] if usr else None})
                finally:
                    c.close()

            if PEER and p == '/api/node/join-invite':   # the join by invite this laptop is running (before and after)
                return self.send(joining['job'].state() if joining.get('job') else {'state': None})
            if PEER and p == '/api/node/nearby' and not E.owner():   # admins' devices on this Wi-Fi a laptop may ask (§16)
                found = [f for f in svc.snapshot()['found'] if f.get('adm') and f.get('peer')]
                return self.send({'devices': [{k: f.get(k) for k in ('peer', 'host', 'port', 'plant', 'label')} for f in found],
                                  'discovery': svc.discovery})
            me = self.user()
            E.refresh()
            for prefix, root in (('/data/', cfg['data_dir']), ('/photos/', cfg['photos_dir'])):
                if p.startswith(prefix):
                    full = os.path.realpath(os.path.join(root, p[len(prefix):]))
                    if not full.startswith(os.path.realpath(root) + os.sep):
                        raise HTTPError(400, 'bad path')
                    if prefix == '/photos/':   # named by content hash: never changes. JXL as it is (common.js decodes it)
                        return self.file(full, 'private, max-age=31536000, immutable')
                    return self.file(full, 'private, no-cache')
            c = store.conn()
            try:
                return self.api_get(p, q, me, c)
            finally:
                c.close()

        def api_get(self, p, q, me, c):
            if p == '/api/me':
                t = store.meta('transfer', None, c)
                return self.send({'user': public_user(me), 'offline_days': cfg['offline_days'],
                                  'transfer_offer': bool(t and t['to'] == me['id'] and t['expires'] > time.time()),
                                  'transfer_pending': t if (t and me['role'] == 'manager' and t['expires'] > time.time()) else None})
            if p == '/api/state':
                users = users_map(c)
                with E.lock:
                    run, created = E.run, {}
                    for h in run.history:
                        if h['entity'] == 'photo' and h['before'] is None and h['after'] is not None:
                            created[h['key']] = E.ts(h['at'])
                    out = {'equipment': run.equipment, 'reviews': run.reviews,
                           'photos': sorted([{'id': k, 'kks': v['kks'], 'file': E.blob_files.get(v['blob']),
                                              'caption': v['caption'], 'created': created.get(k)} for k, v in run.photos.items()],
                                            key=lambda x: (x['created'] or 0, x['id'])),
                           'links': [{'proc': a, 'step': b, 'kks': k} for a, b, k in sorted(run.links)],
                           'added_tags': [tag_out(k, v) for k, v in run.tags.items()],
                           'rev': len(run.history)}
                    out = json.loads(json.dumps(out))   # a copy: the replay moves on after the lock is released
                opn = ch.list_subs(E, me, users, 'open', 10 ** 6)
                out['mine'] = [x for x in opn if x['mine']]
                if rank(me['role']) >= rank('admin'):
                    out['queue'] = len(opn)
                return self.send(out)
            if p == '/api/submissions':
                status = q.get('status', 'open')
                if status not in ('open', 'decided', 'all'):
                    raise HTTPError(400, 'bad status')
                limit = min(int(q.get('limit', 200)), 1000)
                return self.send({'submissions': ch.list_subs(E, me, users_map(c), status, limit)})
            if p == '/api/sheets':
                self.need(me, 'admin')
                return self.send({'sheets': sheets_mod.sheet_summary(cfg), 'importer': importer_status(),
                                  'job': importer.job})
            if p == '/api/sheets/job':
                self.need(me, 'admin')
                return self.send({'job': importer.job})
            if p == '/api/users':
                self.need(me, 'admin')
                rows = [public_user(r) for r in c.execute('SELECT * FROM users ORDER BY role DESC, username')]
                with E.lock:   # people who joined with their own devices and have no account on this server
                    have = {r['person'] for r in c.execute('SELECT person FROM users WHERE person IS NOT NULL')}
                    for pid, pr in sorted(E.run.persons.items(), key=lambda x: x[1]['username'].lower()):
                        if pid in have:
                            continue
                        devs = [d for d, v in E.run.devices.items() if v['person'] == pid]
                        rows.append({'id': None, 'person': pid, 'username': pr['username'], 'full_name': pr['full_name'],
                                     'position': pr['position'] or '', 'no_account': True, 'has_password': False,
                                     'role': 'manager' if E.run.manager == pid else pr['role'], 'created': None,
                                     'active': any(d not in E.run.cuts for d in devs), 'devices': len(devs)})
                return self.send({'users': rows})
            if p == '/api/devices':
                with E.lock:
                    run = E.run
                    def dev_out(d, v):
                        pr = run.persons.get(v['person'], {})
                        return {'device': d, 'label': v['label'], 'person': v['person'], 'username': pr.get('username'),
                                'revoked': d in run.cuts, 'this_computer': d == E.node_device() or (not PEER and d in E.keys)}
                    mine = [dev_out(d, v) for d, v in run.devices.items() if v['person'] == me['person']]
                    everyone = [dev_out(d, v) for d, v in run.devices.items()] if rank(me['role']) >= rank('admin') else None
                    names = {d: f'{run.persons.get(v["person"], {}).get("username", "?")} · {v["label"] or "device"}'
                             for d, v in run.devices.items()}
                snap = svc.snapshot()
                for st in snap['syncs'].values():
                    st['name'] = names.get(st.get('peer'))
                for f in snap['found']:
                    f['name'] = names.get(f.get('peer'))
                return self.send({'mine': mine, 'all': everyone, 'node': P_id(E), 'mode': cfg['mode'], 'sync': snap,
                                  'sync_port': cfg['sync_port']})
            if p == '/api/sync/status':   # polled by every page: reload when rev moves; the status line
                rev = store.meta('seq', 0, c)   # the write journal's sequence: moves with every stored change
                return self.send({'rev': rev, 'mode': cfg['mode'], **(svc.reach() if PEER else {}), 'internet': None})
            if p == '/api/progress':   # course progress (M4): private, only on a person's own devices
                if not PEER:
                    raise HTTPError(404, 'Course progress stays in this browser on a server.')
                got = progress_mod.load(E, me['person'])
                return self.send({'data': got.get(q['course'], {})} if q.get('course') else {'courses': got})
            if p == '/api/join-requests':   # devices on the Wi-Fi asking without an invite (§16)
                self.need(me, 'admin')
                here = proto_mod.peer_id(E.identity())
                rows = invites.lobby_list()
                for r in rows:
                    r['code'] = node_mod.join_code(r['device'], here)
                    r['existing'] = self.existing_person(r['request']['username'])
                return self.send({'requests': rows})
            m = re.fullmatch(r'/api/invites/([A-Za-z0-9_-]{16,40})', p)
            if m:
                self.need(me, 'admin')
                st = invites.status(m[1], me['id'])
                if not st:
                    raise HTTPError(404, 'no such invite')
                if st['request']:   # an existing person with that username: the admin confirms adding a device for them
                    st['existing'] = self.existing_person(st['request']['username'])
                return self.send(st)
            if p == '/api/bundle':
                self.need(me, 'admin')
                data = E.bundle(photos=q.get('photos') == '1')
                name = re.sub(r'[^\w.-]+', '-', (E.run.settings.get('plant') or 'plant'))[:40]
                self._headers(200, 'application/gzip', len(data), [
                    ('Cache-Control', 'no-store'),
                    ('Content-Disposition', f'attachment; filename="{name}-{time.strftime("%Y%m%d-%H%M")}.kksbundle"')])
                self.wfile.write(data)
                return
            if p == '/api/revisions':
                self.need(me, 'admin')
                before = int(q.get('before') or 2 ** 62)
                limit = min(int(q.get('limit', 100)), 500)
                with E.lock:
                    rows = [x for x in ch.history(E, c) if x[0] < before][-limit:][::-1]
                    return self.send({'revisions': ch.history_out(E, rows, users_map(c))})
            raise HTTPError(404, 'not found')

        def need(self, me, role):
            if rank(me['role']) < rank(role):
                raise HTTPError(403, f'{role} only')

        def sub_out(self, r, me, c, live=False):
            d = {k: r[k] for k in ('id', 'client_id', 'kind', 'target', 'status', 'created', 'decided_at', 'note')}
            d['payload'] = json.loads(r['payload'])
            u = c.execute('SELECT username, full_name FROM users WHERE id=?', (r['user_id'],)).fetchone()
            d['by'], d['mine'] = (u['username'] if u else '?'), r['user_id'] == me['id']
            d['by_name'] = (u['full_name'] if u else None) or d['by']
            if r['kind'] == 'photo':
                d['votes'] = c.execute('SELECT COUNT(*) FROM votes WHERE submission_id=?', (r['id'],)).fetchone()[0]
                d['voted'] = bool(c.execute('SELECT 1 FROM votes WHERE submission_id=? AND user_id=?', (r['id'], me['id'])).fetchone())
            if live and r['status'] in ('pending', 'conflict') and rank(me['role']) >= rank('admin'):
                ops, conflicts = ch.plan(c, r['kind'], d['payload'])
                d['conflicts'] = conflicts
                d['live'] = [{'entity': e, 'key': k, 'value': ch.get_state(c, e, k)} for e, k, _ in ops]
            return d

        def post(self):
            p = unquote(urlparse(self.path).path)
            d = self.body()
            if p == '/api/login':
                u, err = auth.login(d.get('username'), d.get('password'), self.ip())
                if not u:
                    raise HTTPError(401, err)
                raw = auth.create_session(u['id'])
                return self.send({'user': public_user(u)}, extra=[self.cookie(raw, cfg['session_days'] * 86400)])
            if p == '/api/logout':
                if self.session_raw():
                    auth.end_session(self.session_raw())
                return self.send({'ok': True}, extra=[self.cookie('', 0)])
            if p == '/api/setup':  # create the manager with the token printed on the server console
                if auth.throttled('ip:' + self.ip()):
                    raise HTTPError(429, 'Too many attempts.')
                name, pw = (d.get('username') or '').strip(), d.get('password')
                if not USERNAME_RE.fullmatch(name):
                    raise HTTPError(400, 'Username: 2-40 letters (a-z), digits, . _ - @')
                if password_problem(pw):
                    raise HTTPError(400, password_problem(pw))
                try:
                    full_name, position = person(d)
                except ValueError as e:
                    raise HTTPError(400, str(e))
                with E.tx() as c:
                    t = auth.peek_token('setup', d.get('token'), c)
                    if not t or auth.manager(c):
                        auth.record(False, 'ip:' + self.ip())
                        raise HTTPError(403, 'This setup link is invalid or already used.')
                    if c.execute('SELECT 1 FROM users WHERE username=?', (name,)).fetchone():
                        raise HTTPError(409, 'That username exists.')
                    pid = secrets.token_hex(16)
                    dev = E.genesis(c, pid, name, full_name, position, cfg['plant_name'])
                    uid = store.put('users', {'username': name, 'pw': hash_password(pw), 'role': 'manager', 'active': 1,
                                              'created': int(time.time()), 'full_name': full_name, 'position': position,
                                              'person': pid, 'device': dev})
                    store.put('meta', {'k': 'log_version', 'v': '1'})
                    auth.consume_token(d['token'])
                    self.log_user(c, uid, uid, 'created as manager (setup)')
                raw = auth.create_session(uid)
                return self.send({'ok': True}, extra=[self.cookie(raw, cfg['session_days'] * 86400)])
            if p == '/api/password-reset':  # set password with a one-time link (invite or reset)
                if auth.throttled('ip:' + self.ip()):
                    raise HTTPError(429, 'Too many attempts.')
                if password_problem(d.get('password')):
                    raise HTTPError(400, password_problem(d.get('password')))
                with store.write() as c:
                    t = auth.peek_token('reset', d.get('token'), c)
                    if not t:
                        auth.record(False, 'ip:' + self.ip())
                        raise HTTPError(403, 'This link is invalid or has expired.')
                    u = c.execute('SELECT * FROM users WHERE id=?', (t['user_id'],)).fetchone()
                    store.put('users', {**dict(u), 'pw': hash_password(d['password'])})
                    auth.consume_token(d['token'])
                    c.execute('DELETE FROM sessions WHERE user_id=?', (u['id'],))
                    self.log_user(c, u['id'], u['id'], 'password set via link')
                raw = auth.create_session(u['id'])
                return self.send({'ok': True}, extra=[self.cookie(raw, cfg['session_days'] * 86400)])

            if p == '/api/devices/enroll':   # a laptop joining with its owner's account (server mode)
                if PEER:
                    raise HTTPError(404, 'not found')
                if auth.throttled('ip:' + self.ip()):
                    raise HTTPError(429, 'Too many attempts.')
                u, err = auth.login(d.get('username'), d.get('password'), self.ip())
                if not u:
                    raise HTTPError(401, err)
                dev, lab = d.get('device'), str(d.get('label') or 'laptop')[:80]
                if not isinstance(dev, str) or not re.fullmatch(r'[A-Za-z0-9_-]{43}', dev):
                    raise HTTPError(400, 'bad device ID')
                with E.tx() as c:
                    have = E.run.devices.get(dev)
                    if have and have['person'] != u['person']:
                        raise HTTPError(409, 'That device belongs to someone else.')
                    if dev in E.run.cuts:
                        raise HTTPError(403, 'That device was removed; make a new one (reset the app on the laptop).')
                    if not have:
                        E.append(c, u['device'], 'device_cert', {'device': dev, 'person': u['person'], 'label': lab})
                        self.log_user(c, u['id'], u['id'], f'added a device: {lab}')
                return self.send({'root': E.anchor, 'plant': E.run.settings.get('plant'), 'sync_port': cfg['sync_port']})
            if PEER and not E.owner() and p.startswith('/api/node/'):
                return self.node_action(p.rsplit('/', 1)[1], d)

            me = self.user()
            E.refresh()
            if p == '/api/password':
                if not auth.login(me['username'], d.get('old'), self.ip())[0]:
                    raise HTTPError(403, 'Current password is wrong.')
                if password_problem(d.get('new')):
                    raise HTTPError(400, password_problem(d.get('new')))
                with store.write() as c:
                    store.put('users', {**dict(me), 'pw': hash_password(d['new'])})
                    c.execute('DELETE FROM sessions WHERE user_id=?', (me['id'],))
                    self.log_user(c, me['id'], me['id'], 'changed password')
                raw = auth.create_session(me['id'])
                return self.send({'ok': True}, extra=[self.cookie(raw, cfg['session_days'] * 86400)])
            if p == '/api/profile':  # your own full name and position
                try:
                    fn, pos = person(d)
                except ValueError as e:
                    raise HTTPError(400, str(e))
                with E.tx() as c:
                    if (fn, pos) != (me['full_name'], me['position']):
                        E.append(c, me['device'], 'person', person_body(E, me['person'], full_name=fn, position=pos))
                        store.put('users', {**dict(me), 'full_name': fn, 'position': pos})
                        self.log_user(c, me['id'], me['id'], f'details → {fn}' + (f', {pos}' if pos else ''))
                return self.send({'ok': True})
            if p == '/api/submit':
                return self.send(ch.submit(E, cfg, me, d.get('kind'), d.get('payload'), d.get('client_id'), d.get('note')))
            m = re.fullmatch(r'/api/submissions/(\d+)/(vote|withdraw|approve|reject|pick)', p)
            if m:
                return self.send(ch.act(E, cfg, me, int(m[1]), m[2], d))
            if p == '/api/sheets/reimport':  # same stored PDF, e.g. with a different rotation
                self.need(me, 'admin')
                return self.start_import(me, d.get('id'), d.get('name'), str(d.get('rotate', 'auto')), True, None)
            m = re.fullmatch(r'/api/sheets/([a-z0-9-]+)/remove', p)
            if m:
                self.need(me, 'admin')
                try:
                    r = importer.remove(m[1])
                except ValueError as e:
                    raise HTTPError(400, str(e))
                log_sheet(me['id'], m[1], f'sheet removed ({r["tags"]} tags); backup in {os.path.basename(r["backup"])}')
                return self.send({'ok': True, **r})
            if p == '/api/users':
                return self.create_user(me, d)
            m = re.fullmatch(r'/api/users/(\d+)(/reset)?', p)
            if m:
                return self.update_user(me, int(m[1]), d, bool(m[2]))
            m = re.fullmatch(r'/api/revisions/([\w-]+)/revert', p)
            if m:
                self.need(me, 'admin')
                with E.tx() as c:
                    n = ch.revert(E, c, me, int(m[1]) if m[1].isdigit() else m[1], bool(d.get('force')))
                return self.send({'ok': True, 'changed': n})
            if p == '/api/restore':
                self.need(me, 'admin')
                ref = d.get('hid', d.get('rev'))
                if not (ref == 0 or isinstance(ref, str) or isinstance(ref, int) and ref > 0) or isinstance(ref, bool):
                    raise HTTPError(400, 'hid (a History row) or rev 0 is required')
                with E.tx() as c:
                    n = ch.restore_to(E, c, me, ref)
                return self.send({'ok': True, 'changed': n})
            if p.startswith('/api/manager/'):
                return self.manager_action(me, p.rsplit('/', 1)[1], d)
            if p == '/api/devices/import-request':
                return self.import_request(me, d)
            if p == '/api/progress':
                if not PEER:
                    raise HTTPError(404, 'Course progress stays in this browser on a server.')
                try:
                    progress_mod.save(E, me, d.get('course'), d.get('data'))
                except progress_mod.Bad as e:
                    raise HTTPError(400, str(e))
                return self.send({'ok': True})
            if p == '/api/invites':   # join by invite: a QR code for a new device on the same network
                self.need(me, 'admin')
                if not getattr(svc, 'port', None):
                    raise HTTPError(409, 'Sync is off on this computer (sync_port 0), so devices cannot join through it.')
                inv = invites.create(me['id'], E.anchor, E.run.settings.get('plant') or cfg['plant_name'],
                                     proto_mod.peer_id(E.identity()), lan_addresses(svc.port))
                if not inv['addrs']:
                    raise HTTPError(409, 'This computer has no network address other devices could reach.')
                return self.send({'ok': True, 'invite': inv, 'code': json.dumps(inv, separators=(',', ':'))})
            m = re.fullmatch(r'/api/invites/([A-Za-z0-9_-]{16,40})', p)
            if m:
                return self.invite_action(me, m[1], d)
            m = re.fullmatch(r'/api/join-requests/([A-Za-z0-9_-]{43})', p)
            if m:
                return self.lobby_action(me, m[1], d)
            if p == '/api/devices/revoke':
                return self.revoke_device(me, d.get('device'))
            if p == '/api/sync/now':
                addr = (d.get('address') or '').strip()
                if addr:
                    host, _, port = addr.rpartition(':') if ':' in addr else (addr, '', '')
                    try:
                        _, st = svc.sync_one(host or addr, int(port or 8421))
                    except (ValueError, sync_mod.SyncError, OSError, NoRootKey) as e:
                        raise HTTPError(502, f'sync with {addr} failed: {e}')
                    return self.send({'ok': True, 'result': st})
                svc.sync_all()
                return self.send({'ok': True, 'sync': svc.snapshot()})
            m = re.fullmatch(r'/api/persons/([0-9a-f]{32})', p)
            if m:
                return self.update_person(me, m[1], d)
            raise HTTPError(404, 'not found')

        def post_bundle(self):
            n = int(self.headers.get('Content-Length') or 0)
            if n > 2 * 1024 ** 3:
                raise HTTPError(413, 'bundle too large')
            if not (PEER and not E.owner()):   # joining laptops may import without an account; everyone else signs in
                self.user()
            try:
                r = E.import_bundle(self.rfile.read(n))
            except ValueError as e:
                raise HTTPError(400, str(e))
            if PEER and E.owner():
                svc.joined()
            return self.send({'ok': True, **r, 'joined': bool(E.owner()) if PEER else None})

        def node_action(self, action, d):
            """Peer mode, before this laptop belongs to a plant: start one, or join one."""
            if action == 'new-plant':
                name = (d.get('username') or '').strip()
                if not USERNAME_RE.fullmatch(name):
                    raise HTTPError(400, 'Username: 2-40 letters (a-z), digits, . _ - @')
                try:
                    fn, pos = person(d)
                except ValueError as e:
                    raise HTTPError(400, str(e))
                if E.anchor is not None:
                    raise HTTPError(409, 'This laptop already holds a plant\'s data; it can only join that plant.')
                dev = E.ensure_node_device()
                with E.tx() as c:
                    E.genesis(c, secrets.token_hex(16), name, fn, pos, (d.get('plant') or cfg['plant_name'])[:80], device=dev)
                    store.put('meta', {'k': 'log_version', 'v': '1'})
                E.owner(); svc.joined()
                return self.send({'ok': True})
            if action == 'join-server':
                try:
                    node_mod.join_via_server(E, svc, (d.get('url') or '').strip(), d.get('username'), d.get('password'))
                except node_mod.JoinError as e:
                    raise HTTPError(400, str(e))
                return self.send({'ok': True})
            if action == 'join-invite':
                if d.get('cancel') or d.get('confirm'):
                    if joining.get('job'):
                        joining['job'].cancel() if d.get('cancel') else joining['job'].confirm()
                    return self.send({'ok': True})
                name = (d.get('username') or '').strip()
                if not USERNAME_RE.fullmatch(name):
                    raise HTTPError(400, 'Username: 2-40 letters (a-z), digits, . _ - @')
                try:
                    fn, pos = person(d)
                    inv = node_mod.parse_nearby(d['nearby']) if d.get('nearby') else node_mod.parse_invite(d.get('invite'))
                except (ValueError, node_mod.JoinError) as e:
                    raise HTTPError(400, str(e))
                if E.anchor is not None and inv['root'] and E.anchor != inv['root']:
                    raise HTTPError(409, 'This laptop holds another plant\'s data; that invite is for a different plant.')
                if joining.get('job'):
                    joining['job'].cancel()
                joining['job'] = node_mod.InviteJoin(E, svc, inv, name, fn, pos)
                return self.send({'ok': True, **joining['job'].state()})
            if action == 'join-request':
                name = (d.get('username') or '').strip()
                if not USERNAME_RE.fullmatch(name):
                    raise HTTPError(400, 'Username: 2-40 letters (a-z), digits, . _ - @')
                try:
                    fn, pos = person(d)
                except ValueError as e:
                    raise HTTPError(400, str(e))
                return self.send({'ok': True, 'request': node_mod.join_request(E, name, fn, pos)})
            raise HTTPError(404, 'not found')

        def import_request(self, me, d):
            """An admin certifies a laptop from its join request file (for a new person, or, confirmed, an existing one)."""
            self.need(me, 'admin')
            try:
                req = node_mod.check_join_request(d.get('request'))
            except node_mod.JoinError as e:
                raise HTTPError(400, str(e))
            name, pid = self.certify(me, req, d.get('existing_ok'))
            return self.send({'ok': True, 'username': name, 'person': pid})

        def certify(self, me, req, existing_ok):
            """A checked join request -> device_cert (+ a new person). -> (username, person)"""
            name = str(req.get('username') or '')
            if not USERNAME_RE.fullmatch(name):
                raise HTTPError(400, 'the request has an invalid username')
            try:
                fn, pos = person(req)
            except ValueError as e:
                raise HTTPError(400, str(e))
            with E.tx() as c:
                run = E.run
                have = run.devices.get(req['device'])
                pid = next((k for k, v in run.persons.items() if v['username'].lower() == name.lower()), None)
                if have and have['person'] != pid:
                    raise HTTPError(409, 'That laptop is already certified for someone else.')
                if pid and not existing_ok:
                    pr = run.persons[pid]
                    raise HTTPError(409, 'existing person', {'existing': {'username': pr['username'], 'full_name': pr['full_name'],
                                                                          'role': 'manager' if run.manager == pid else pr['role']}})
                if pid:
                    target = 'manager' if run.manager == pid else run.persons[pid]['role']
                    if not (me['role'] == 'manager' or pid == me['person'] or target == 'user'):
                        raise HTTPError(403, 'Only the manager can add devices for admins.')
                else:
                    if c.execute('SELECT 1 FROM users WHERE username=?', (name,)).fetchone():
                        raise HTTPError(409, 'That username exists.')
                    pid = secrets.token_hex(16)
                    E.append(c, me['device'], 'person', {'person': pid, 'username': name, 'full_name': fn, 'position': pos, 'role': 'user'})
                if not have:
                    E.append(c, me['device'], 'device_cert', {'device': req['device'], 'person': pid, 'label': str(req.get('label') or '')[:80]})
                store.put('revisions', {'ts': int(time.time()), 'actor': me['id'], 'entity': 'user', 'key': pid, 'before': None,
                                        'after': None, 'submission_id': None, 'note': f'certified a device for {name}: {req.get("label")}'})
            return name, pid

        def existing_person(self, username):
            with E.lock:
                pid = next((k for k, v in E.run.persons.items() if v['username'].lower() == str(username).lower()), None)
                pr = E.run.persons.get(pid)
                return pr and {'username': pr['username'], 'full_name': pr['full_name'],
                               'role': 'manager' if E.run.manager == pid else pr['role']}

        def lobby_action(self, me, device, d):
            self.need(me, 'admin')
            if d.get('action') not in ('accept', 'refuse'):
                raise HTTPError(400, 'bad action')
            req = invites.lobby_take(device)
            if not req:
                raise HTTPError(409, 'That device is no longer waiting (it gave up, or was decided already).')
            if d['action'] == 'refuse':
                invites.lobby_done(device, False)
                return self.send({'ok': True})
            name, pid = self.certify(me, req, d.get('existing_ok'))
            invites.lobby_done(device, True)
            return self.send({'ok': True, 'username': name, 'person': pid})

        def invite_action(self, me, token, d):
            """Join by invite, the admin's side: accept (certify the device that asked), refuse, or cancel."""
            self.need(me, 'admin')
            action = d.get('action')
            if action == 'cancel':
                invites.cancel(token, me['id'])
                return self.send({'ok': True})
            if action not in ('accept', 'refuse'):
                raise HTTPError(400, 'bad action')
            if not invites.take(token, me['id']):
                raise HTTPError(409, 'No device is waiting on this invite (it expired, or was decided already).')
            if action == 'refuse':
                invites.done(token, False)
                return self.send({'ok': True})
            name, pid = self.certify(me, invites.full_request(token), d.get('existing_ok'))
            invites.done(token, True)
            return self.send({'ok': True, 'username': name, 'person': pid})

        def revoke_device(self, me, dev):
            with E.tx() as c:
                v = E.run.devices.get(dev) if isinstance(dev, str) else None
                if not v:
                    raise HTTPError(404, 'no such device')
                target = 'manager' if E.run.manager == v['person'] else E.run.persons.get(v['person'], {}).get('role')
                if not (me['role'] == 'manager' or v['person'] == me['person'] or (me['role'] == 'admin' and target == 'user')):
                    raise HTTPError(403, 'not allowed for that device')
                if dev == me['device']:
                    raise HTTPError(400, 'This is the device you are using; remove it from another one.')
                if dev in E.run.cuts:
                    return self.send({'ok': True})
                last = c.execute('SELECT MAX(seq) FROM entries WHERE peer=?', (dev,)).fetchone()[0] or 0
                E.append(c, me['device'], 'revoke', {'device': dev, 'last_seq': last})
            return self.send({'ok': True})

        def update_person(self, me, pid, d):
            """Someone without an account here (joined with their own device): role, details, or remove all devices."""
            self.need(me, 'admin')
            with E.tx() as c:
                pr = E.run.persons.get(pid)
                if not pr:
                    raise HTTPError(404, 'no such person')
                target = 'manager' if E.run.manager == pid else pr['role']
                if target == 'manager' or (target == 'admin' and me['role'] != 'manager'):
                    raise HTTPError(403, 'not allowed for this person')
                upd = {}
                if 'role' in d and d['role'] != pr['role']:
                    if me['role'] != 'manager' or d['role'] not in ('user', 'admin'):
                        raise HTTPError(403, 'only the manager can promote or demote admins')
                    upd['role'] = d['role']
                if 'full_name' in d or 'position' in d:
                    try:
                        fn, pos = person({'full_name': d.get('full_name', pr['full_name']), 'position': d.get('position', pr['position'])})
                    except ValueError as e:
                        raise HTTPError(400, str(e))
                    upd.update(full_name=fn, position=pos)
                if upd:
                    E.append(c, me['device'], 'person', person_body(E, pid, **upd))
                if d.get('active') is False:
                    for dev, v in list(E.run.devices.items()):
                        if v['person'] == pid and dev not in E.run.cuts:
                            last = c.execute('SELECT MAX(seq) FROM entries WHERE peer=?', (dev,)).fetchone()[0] or 0
                            E.append(c, me['device'], 'revoke', {'device': dev, 'last_seq': last})
                elif d.get('active') is True:
                    raise HTTPError(400, 'To come back they join again with a new join request.')
            return self.send({'ok': True})

        def post_pdf(self):
            me = self.user('admin')
            q = {k: v[0] for k, v in parse_qs(urlparse(self.path).query).items()}
            n = int(self.headers.get('Content-Length') or 0)
            if n > cfg['max_pdf_mb'] * 1024 * 1024:
                raise HTTPError(413, f'PDF larger than {cfg["max_pdf_mb"]} MB (max_pdf_mb in config.json)')
            data = self.rfile.read(n)
            return self.start_import(me, q.get('id'), q.get('name'), q.get('rotate', 'auto'), q.get('replace') == '1', data)

        def start_import(self, me, sid, name, rotate, replace, data):
            def done(job):
                if job['state'] == 'done':
                    r = job['result']
                    log_sheet(me['id'], job['sheet'], f'sheet {"re-imported" if replace else "added"}: "{r["name"]}", '
                                                      f'{r["auto"]} tags auto-read, {r["review"]} to review, rotation {r["rotation"]}°')
            try:
                job = importer.start(me, (sid or '').strip(), name, rotate, replace, data, on_done=done)
            except ValueError as e:
                raise HTTPError(400, str(e))
            return self.send({'ok': True, 'job': job})

        def log_user(self, c, actor, uid, note):
            u = c.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
            after = {'username': u['username'], 'full_name': u['full_name'], 'position': u['position'], 'role': u['role'],
                     'active': bool(u['active'])} if u else None
            store.put('revisions', {'ts': int(time.time()), 'actor': actor, 'entity': 'user', 'key': str(uid),
                                    'before': None, 'after': json.dumps(after), 'submission_id': None, 'note': note})

        def create_user(self, me, d):
            self.need(me, 'admin')
            name, role = (d.get('username') or '').strip(), d.get('role', 'user')
            if not USERNAME_RE.fullmatch(name):
                raise HTTPError(400, 'Username: 2-40 letters (a-z), digits, . _ - @')
            if role not in ('user', 'admin'):
                raise HTTPError(400, 'role must be user or admin')
            if role == 'admin' and me['role'] != 'manager':
                raise HTTPError(403, 'only the manager can create admins')
            try:
                full_name, position = person(d)
            except ValueError as e:
                raise HTTPError(400, str(e))
            with E.tx() as c:
                if c.execute('SELECT 1 FROM users WHERE username=?', (name,)).fetchone() or \
                        any(x['username'].lower() == name.lower() for x in E.run.persons.values()):
                    raise HTTPError(409, 'That username exists.')
                pid = secrets.token_hex(16)
                E.append(c, me['device'], 'person', {'person': pid, 'username': name, 'full_name': full_name,
                                                     'position': position, 'role': role})
                dev = E.new_device(c, pid)
                E.append(c, me['device'], 'device_cert', {'device': dev, 'person': pid, 'label': 'server'})
                uid = store.put('users', {'username': name, 'pw': None, 'role': role, 'active': 1, 'created': int(time.time()),
                                          'full_name': full_name, 'position': position, 'person': pid, 'device': dev})
                self.log_user(c, me['id'], uid, f'created as {role}')
            raw = auth.make_token('reset', uid, 7 * 86400)
            return self.send({'ok': True, 'id': uid, 'link': link(f'/#reset={raw}'), 'expires_days': 7})

        def update_user(self, me, uid, d, reset):
            self.need(me, 'admin')
            with E.tx() as c:
                u = c.execute('SELECT * FROM users WHERE id=?', (uid,)).fetchone()
                if not u:
                    raise HTTPError(404, 'no such user')
                # admins manage users; only the manager manages admins; nobody manages the manager here
                if u['role'] == 'manager' or (u['role'] == 'admin' and me['role'] != 'manager'):
                    raise HTTPError(403, 'not allowed for this account')
                if reset:
                    pass
                else:
                    row, notes = dict(u), []
                    if 'role' in d and d['role'] != u['role']:
                        if me['role'] != 'manager' or d['role'] not in ('user', 'admin'):
                            raise HTTPError(403, 'only the manager can promote or demote admins')
                        row['role'] = d['role']; notes.append(f'role → {d["role"]}')
                    if 'full_name' in d or 'position' in d:
                        try:
                            fn, pos = person({'full_name': d.get('full_name', u['full_name']), 'position': d.get('position', u['position'])})
                        except ValueError as e:
                            raise HTTPError(400, str(e))
                        if (fn, pos) != (u['full_name'], u['position']):
                            row.update(full_name=fn, position=pos); notes.append(f'details → {fn}' + (f', {pos}' if pos else ''))
                    if 'active' in d and bool(d['active']) != bool(u['active']):
                        row['active'] = 1 if d['active'] else 0; notes.append('activated' if d['active'] else 'deactivated')
                    if notes:
                        if (row['role'], row['full_name'], row['position']) != (u['role'], u['full_name'], u['position']):
                            E.append(c, me['device'], 'person', person_body(E, u['person'], full_name=row['full_name'],
                                                                            position=row['position'], role=row['role']))
                        if u['active'] and not row['active']:   # all their keys stop here: this server's and their laptops'
                            for dev, v in list(E.run.devices.items()):
                                if v['person'] == u['person'] and dev not in E.run.cuts:
                                    last = c.execute('SELECT MAX(seq) FROM entries WHERE peer=?', (dev,)).fetchone()[0] or 0
                                    E.append(c, me['device'], 'revoke', {'device': dev, 'last_seq': last})
                        elif row['active'] and not u['active']:   # a new key; the old one stays cut
                            row['device'] = E.new_device(c, u['person'])
                            E.append(c, me['device'], 'device_cert', {'device': row['device'], 'person': u['person'], 'label': 'server'})
                        store.put('users', row)
                        if not row['active'] or row['role'] != u['role']:
                            c.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
                        self.log_user(c, me['id'], uid, ', '.join(notes))
            if reset:
                raw = auth.make_token('reset', uid, 3 * 86400)
                return self.send({'ok': True, 'link': link(f'/#reset={raw}'), 'expires_days': 3})
            return self.send({'ok': True})

        def manager_action(self, me, action, d):
            with E.tx() as c:
                t = store.meta('transfer', None, c)
                if action == 'transfer':
                    self.need(me, 'manager')
                    if not auth.login(me['username'], d.get('password'), self.ip())[0]:
                        raise HTTPError(403, 'Password is wrong.')
                    to = c.execute("SELECT * FROM users WHERE username=? AND role='admin' AND active=1",
                                   (d.get('username') or '',)).fetchone()
                    if not to:
                        raise HTTPError(400, 'The new manager must be an active admin.')
                    E.root_key()   # the handover is signed with the plant root key: fail now, not at "accept"
                    offer = {'from': me['id'], 'to': to['id'], 'to_name': to['username'], 'expires': int(time.time()) + 7 * 86400}
                    store.put('meta', {'k': 'transfer', 'v': json.dumps(offer)})
                    self.log_user(c, me['id'], to['id'], 'offered the manager role')
                    return self.send({'ok': True})
                if action == 'cancel':
                    self.need(me, 'manager')
                    store.delete('meta', k='transfer')
                    return self.send({'ok': True})
                if action in ('accept', 'decline'):
                    if not t or t['to'] != me['id'] or t['expires'] < time.time():
                        raise HTTPError(400, 'No manager transfer is waiting for you.')
                    store.delete('meta', k='transfer')
                    if action == 'decline':
                        self.log_user(c, me['id'], me['id'], 'declined the manager role')
                        return self.send({'ok': True})
                    old = c.execute('SELECT * FROM users WHERE id=?', (t['from'],)).fetchone()
                    if not old or old['role'] != 'manager' or me['role'] != 'admin':
                        raise HTTPError(409, 'The offer is no longer valid.')
                    E.root_statement(c, me['device'], {'kind': 'manager', 'person': me['person']})
                    store.put('users', {**dict(old), 'role': 'admin'})  # demote first: one-manager index
                    store.put('users', {**dict(me), 'role': 'manager'})
                    self.log_user(c, me['id'], old['id'], 'manager role handed over; now admin')
                    self.log_user(c, me['id'], me['id'], 'accepted the manager role')
                    return self.send({'ok': True})
            raise HTTPError(404, 'not found')

    return H


# ---------- CLI ----------
def find_user(store, name):
    c = store.conn()
    u = c.execute('SELECT * FROM users WHERE username=?', (name,)).fetchone()
    c.close()
    if not u:
        raise SystemExit(f'no user "{name}". Existing: ' + ', '.join(r['username'] for r in list_users(store)))
    return u


def list_users(store):
    c = store.conn()
    rows = c.execute('SELECT * FROM users ORDER BY role DESC, username').fetchall()
    c.close()
    return rows


def base_url(cfg):
    return (cfg['public_url'] or f'http://localhost:{cfg["port"]}').rstrip('/')


def cli_log(store, c, uid, note):
    store.put('revisions', {'ts': int(time.time()), 'actor': None, 'entity': 'user', 'key': str(uid), 'before': None,
                            'after': None, 'submission_id': None, 'note': note + ' (server console)'})


ON_READY = None   # set by desktop.py: called with the HTTP server once it listens


def main(argv=None):
    ap = argparse.ArgumentParser(description='KKS Explorer server')
    ap.add_argument('cmd', nargs='?', default='serve',
                    choices=['serve', 'users', 'reset-manager', 'reset-password', 'backup', 'restore', 'check', 'setup-importer',
                             'added-tags', 'export-root-key', 'import-root-key', 'sync'])
    ap.add_argument('target', nargs='?', help='for sync: HOST[:PORT]')
    ap.add_argument('--user')
    ap.add_argument('--file')
    ap.add_argument('--seq', type=int)
    ap.add_argument('--out')
    a = ap.parse_args(argv)
    cfg = config_mod.load()
    if a.cmd == 'restore':  # works on backups only; never touches the live DB
        out = a.out or os.path.join(os.path.dirname(cfg['db']), f'restored-{time.strftime("%Y%m%d-%H%M%S")}.db')
        s, last = restore(cfg, out, a.seq)
        print(f'Restored snapshot @{s} + journal → seq {last}\n  {out}\n'
              f'To use it: stop the server, move {cfg["db"]} (and its -wal/-shm files) aside, rename this file to it, start.')
        return
    os.makedirs(cfg['photos_dir'], exist_ok=True)
    if a.cmd == 'setup-importer':
        sheets_mod.setup_importer()
        return
    store = Store(cfg)
    auth = Auth(store, cfg)
    E = Engine(store, cfg)
    if a.cmd in ('export-root-key', 'import-root-key'):
        path = a.out if a.cmd == 'export-root-key' else a.file
        if not path:
            raise SystemExit('--out FILE is required' if a.cmd == 'export-root-key' else '--file FILE is required')
        pw = getpass.getpass('Passphrase: ')
        try:
            if a.cmd == 'export-root-key':
                if len(pw) < 12 or pw != getpass.getpass('Again: '):
                    raise SystemExit('Passphrases differ or are shorter than 12 characters.')
                E.root_key()
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, 'w') as f:
                    f.write(E.export_root(pw) + '\n')
                with store.write():
                    store.put('meta', {'k': 'root_backed_up', 'v': json.dumps(int(time.time()))})
                print(f'Wrote {path}. Keep it offline (USB stick, printed); without it and {E.root_path} nobody can '
                      f'hand over the manager role or certify devices by root.')
            else:
                with open(path) as f:
                    E.import_root(f.read(), pw)
                print(f'Root key restored to {E.root_path}.')
        except NoRootKey as e:
            raise SystemExit(str(e))
        except (ValueError, KeyError):
            raise SystemExit('Wrong passphrase or not a root key backup.')
        return
    if a.cmd == 'sync':
        if not a.target:
            raise SystemExit('usage: python3 app.py sync HOST[:PORT]')
        host, _, port = a.target.partition(':')
        try:
            remote, st = sync_mod.sync_with(E, host, int(port or 8421))
        except (sync_mod.SyncError, OSError, NoRootKey) as e:
            raise SystemExit(f'sync failed: {e}')
        print(f'synced with {remote[:12]}…: sent {st["sent"]} entries, received {st["received"]}, '
              f'photos {st["blobs_sent"]} sent / {st["blobs_received"]} received'
              + ('; the other device does not know this one (not certified there yet), so it sent nothing'
                 if st['they_denied'] else ''))
        return
    if a.cmd == 'users':
        for u in list_users(store):
            print(f'{u["username"]:<20} {u["full_name"] or "(no name)":<26} {u["position"] or "":<22} {u["role"]:<8} '
                  f'{"active" if u["active"] else "inactive":<9}'
                  f'{"" if u["pw"] else "(no password set)"}')
        return
    if a.cmd == 'check':
        findings = check_mod.run(cfg, store, auth)
        for level, msg in findings:
            print(f'{level:<5} {msg}')
        if any(level == 'FAIL' for level, _ in findings):
            raise SystemExit(1)
        return
    if a.cmd == 'added-tags':  # tags marked by hand in the app: where the extractor still fails
        print(json.dumps([tag_out(k, v) for k, v in E.run.tags.items()], indent=1))
        return
    if a.cmd == 'backup':
        print(store.snapshot())
        return
    if a.cmd in ('reset-manager', 'reset-password'):
        if not a.user:
            raise SystemExit('--user is required')
        u = find_user(store, a.user)
        if a.cmd == 'reset-manager':
            try:
                E.root_key()
            except NoRootKey as e:
                raise SystemExit(str(e))
            with E.tx() as c:
                old = auth.manager(c)
                carrier = old['device'] if old else u['device']
                row = {**dict(u), 'role': 'manager', 'active': 1}
                if not u['active']:   # its old key was revoked: a new one, certified by the root key
                    row['device'] = E.new_device(c, u['person'])
                    E.root_statement(c, carrier, {'kind': 'device', 'device': row['device'], 'person': u['person']})
                if E.run.persons[u['person']]['role'] == 'user' and old:   # so a later handover leaves them an admin
                    E.append(c, old['device'], 'person', person_body(E, u['person'], role='admin'))
                E.root_statement(c, carrier, {'kind': 'manager', 'person': u['person']})
                if old and old['id'] != u['id']:
                    store.put('users', {**dict(old), 'role': 'admin'})
                    cli_log(store, c, old['id'], 'manager role removed by reset-manager')
                store.put('users', row)
                store.delete('meta', k='transfer')
                cli_log(store, c, u['id'], 'made manager by reset-manager')
            print(f'{u["username"]} is now the manager' + (f'; {old["username"]} is now an admin.' if old and old['id'] != u['id'] else '.'))
        raw = auth.make_token('reset', u['id'], 86400)
        print(f'One-time password link for {u["username"]} (24 h):\n  {base_url(cfg)}/#reset={raw}')
        return

    # serve
    for level, msg in check_mod.run(cfg, store, auth):
        if level == 'FAIL' and 'manager' not in msg:
            print(f'  WARNING: {msg}')
    peer = cfg['mode'] == 'peer'
    if peer:
        cfg['host'] = '127.0.0.1'   # no password in peer mode: the web UI is for this computer only
    elif not auth.manager():
        raw = auth.make_token('setup', None, 86400)
        print(f'\n  No manager account yet. Open this one-time link to create it (valid 24 h, until used):\n'
              f'  {base_url(cfg)}/#setup={raw}\n')
    if os.path.exists(E.root_path) and not store.meta('root_backed_up'):
        print(f'  The plant root key is only in {E.root_path}. Back it up: python3 app.py export-root-key --out FILE')
    svc = SyncService(E, cfg)
    httpd = ThreadingHTTPServer((cfg['host'], cfg['port']), make_handler(cfg, store, auth, E, svc))
    if cfg['sync_port']:
        try:
            svc.listen(cfg['sync_host'] if peer else cfg['host'], cfg['sync_port'])
            svc.start_discovery()
            print(f'  Devices on this Wi-Fi: discovery {svc.discovery}')
        except OSError as e:   # e.g. another copy of the app already holds the port: work on, just without sync
            print(f'  WARNING: sync is off: port {cfg["sync_port"]} is not free ({e.strerror}).')
    scheme = 'http'
    if cfg['tls_cert']:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cfg['tls_cert'], cfg['tls_key'] or None)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        scheme = 'https'
    lan = '' if peer else f'  LAN:    {scheme}://{lan_ip()}:{cfg["port"]}\n'
    print(f'  {cfg["plant_name"]}{"  (this computer is a device: open it here only)" if peer else ""}\n'
          f'  Laptop: {scheme}://localhost:{cfg["port"]}\n{lan}'
          f'  Data: {cfg["db"]}, {cfg["photos_dir"]}/   Backups: {cfg["backup_dir"]}/\n  Ctrl+C to stop.\n')
    if ON_READY:   # the desktop launcher: it stops the server itself (Quit), then we take the snapshot below
        ON_READY(httpd)
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\nStopping.')
    print('Taking a snapshot.')
    store.snapshot()


def lan_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(('8.8.8.8', 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        return '127.0.0.1'


if __name__ == '__main__':
    main()
