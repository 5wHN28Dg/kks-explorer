#!/usr/bin/env python3
"""Plant P&ID / KKS Explorer - server. Standard library only.

  python3 app.py                          run the server (settings: config.json, see config.example.json)
  python3 app.py users                    list accounts
  python3 app.py reset-manager --user X   make X the manager (break-glass; shell access only) + password link
  python3 app.py reset-password --user X  print a one-time password link for X
  python3 app.py backup                   take a full snapshot now
  python3 app.py restore [--seq N] [--out FILE]   rebuild the DB from backups into a NEW file
  python3 app.py check                    audit the deployment (remote access, cookies, backups); exit 1 on FAIL
  python3 app.py setup-importer           create .venv with the P&ID importer's packages (for Manage → Drawings)
  python3 app.py added-tags               print the tags users marked by hand on the drawings (JSON)

The app shell (index.html, admin.html, *.js) is public. Plant data (/data, /photos, /api) needs a login."""
import argparse, gzip, json, mimetypes, os, re, socket, ssl, time
from http.cookies import SimpleCookie
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, unquote, parse_qs

from server import config as config_mod
from server.store import Store, restore
from server.auth import Auth, hash_password, password_problem, public_user, rank, person
from server import changes as ch
from server import check as check_mod
from server import sheets as sheets_mod

BASE = config_mod.BASE
SHELL = {'/': 'index.html', '/index.html': 'index.html', '/admin.html': 'admin.html', '/common.js': 'common.js',
         '/sw.js': 'sw.js', '/manifest.webmanifest': 'manifest.webmanifest', '/icon.svg': 'icon.svg',
         '/icon-192.png': 'icon-192.png', '/icon-512.png': 'icon-512.png'}
COOKIE = 'kks_session'


class HTTPError(Exception):
    def __init__(self, code, msg, extra=None):
        super().__init__(msg)
        self.code, self.msg, self.extra = code, msg, extra or {}


def make_handler(cfg, store, auth):
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
            u = auth.user_for_session(self.session_raw())
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
            except (BrokenPipeError, ConnectionResetError):
                pass

        def do_GET(self):
            self.handle_errors(self.get)

        def do_POST(self):
            # JSON-only API + same-origin check: a form on another site can't post here with the session cookie.
            origin = self.headers.get('Origin')
            allowed = {self.headers.get('Host'), self.headers.get('X-Forwarded-Host'), urlparse(cfg['public_url']).netloc} - {None, ''}
            if origin and urlparse(origin).netloc not in allowed:
                return self.send({'error': 'cross-origin request refused'}, 403)
            ctype = self.headers.get('Content-Type') or ''
            if urlparse(self.path).path == '/api/sheets/import' and ctype.startswith('application/pdf'):
                return self.handle_errors(self.post_pdf)  # raw PDF body; not a type a cross-site form can send
            if not ctype.startswith('application/json'):
                return self.send({'error': 'JSON only'}, 415)
            self.handle_errors(self.post)

        def get(self):
            u = urlparse(self.path)
            p, q = unquote(u.path), {k: v[0] for k, v in parse_qs(u.query).items()}
            if p in SHELL:
                return self.file(os.path.join(BASE, SHELL[p]), 'no-cache')
            if p == '/api/config':
                c = store.conn()
                try:
                    has_manager = bool(auth.manager(c))
                finally:
                    c.close()
                return self.send({'plant_name': cfg['plant_name'], 'offline_days': cfg['offline_days'],
                                  'setup_needed': not has_manager})
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

            me = self.user()
            for prefix, root in (('/data/', cfg['data_dir']), ('/photos/', cfg['photos_dir'])):
                if p.startswith(prefix):
                    full = os.path.realpath(os.path.join(root, p[len(prefix):]))
                    if not full.startswith(os.path.realpath(root) + os.sep):
                        raise HTTPError(400, 'bad path')
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
                out = {'equipment': {r['kks']: json.loads(r['data']) for r in c.execute('SELECT * FROM equipment')},
                       'reviews': {r['tag_id']: json.loads(r['data']) for r in c.execute('SELECT * FROM reviews')},
                       'photos': [dict(r) for r in c.execute('SELECT * FROM photos ORDER BY created')],
                       'links': [dict(r) for r in c.execute('SELECT * FROM links')],
                       'added_tags': [{'id': r['id'], **json.loads(r['data'])} for r in c.execute('SELECT * FROM added_tags')],
                       'rev': c.execute('SELECT COALESCE(MAX(rev),0) FROM revisions').fetchone()[0],
                       'mine': [self.sub_out(r, me, c) for r in c.execute(
                           "SELECT * FROM submissions WHERE user_id=? AND status IN ('pending','conflict') ORDER BY id",
                           (me['id'],))]}
                if rank(me['role']) >= rank('admin'):
                    out['queue'] = c.execute("SELECT COUNT(*) FROM submissions WHERE status IN ('pending','conflict')").fetchone()[0]
                return self.send(out)
            if p == '/api/submissions':
                status = q.get('status', 'open')
                where = {'open': "status IN ('pending','conflict')", 'decided': "status IN ('approved','rejected','withdrawn')",
                         'all': '1'}.get(status)
                if not where:
                    raise HTTPError(400, 'bad status')
                limit = min(int(q.get('limit', 200)), 1000)
                if rank(me['role']) >= rank('admin'):
                    rows = c.execute(f'SELECT * FROM submissions WHERE {where} ORDER BY id DESC LIMIT ?', (limit,))
                else:  # own submissions + open photo proposals (so users can vote on them)
                    rows = c.execute(f"SELECT * FROM submissions WHERE {where} AND (user_id=? OR (kind='photo' AND "
                                     f"status IN ('pending','conflict'))) ORDER BY id DESC LIMIT ?", (me['id'], limit))
                return self.send({'submissions': [self.sub_out(r, me, c, live=True) for r in rows.fetchall()]})
            if p == '/api/sheets':
                self.need(me, 'admin')
                return self.send({'sheets': sheets_mod.sheet_summary(cfg), 'importer': importer_status(),
                                  'job': importer.job})
            if p == '/api/sheets/job':
                self.need(me, 'admin')
                return self.send({'job': importer.job})
            if p == '/api/users':
                self.need(me, 'admin')
                return self.send({'users': [public_user(r) for r in c.execute('SELECT * FROM users ORDER BY role DESC, username')]})
            if p == '/api/revisions':
                self.need(me, 'admin')
                before = int(q.get('before') or 2 ** 62)
                rows = c.execute('SELECT r.*, u.username, u.full_name FROM revisions r LEFT JOIN users u ON u.id=r.actor '
                                 'WHERE rev<? ORDER BY rev DESC LIMIT ?', (before, min(int(q.get('limit', 100)), 500)))
                return self.send({'revisions': [dict(r) for r in rows]})
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
                if not re.fullmatch(r'[\w.@-]{2,40}', name):
                    raise HTTPError(400, 'Username: 2-40 letters, digits, . _ - @')
                if password_problem(pw):
                    raise HTTPError(400, password_problem(pw))
                try:
                    full_name, position = person(d)
                except ValueError as e:
                    raise HTTPError(400, str(e))
                with store.write() as c:
                    t = auth.peek_token('setup', d.get('token'), c)
                    if not t or auth.manager(c):
                        auth.record(False, 'ip:' + self.ip())
                        raise HTTPError(403, 'This setup link is invalid or already used.')
                    if c.execute('SELECT 1 FROM users WHERE username=?', (name,)).fetchone():
                        raise HTTPError(409, 'That username exists.')
                    uid = store.put('users', {'username': name, 'pw': hash_password(pw), 'role': 'manager', 'active': 1,
                                              'created': int(time.time()), 'full_name': full_name, 'position': position})
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

            me = self.user()
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
                with store.write() as c:
                    if (fn, pos) != (me['full_name'], me['position']):
                        store.put('users', {**dict(me), 'full_name': fn, 'position': pos})
                        self.log_user(c, me['id'], me['id'], f'details → {fn}' + (f', {pos}' if pos else ''))
                return self.send({'ok': True})
            if p == '/api/submit':
                return self.send(ch.submit(store, cfg, me, d.get('kind'), d.get('payload'), d.get('client_id')))
            m = re.fullmatch(r'/api/submissions/(\d+)/(vote|withdraw|approve|reject|pick)', p)
            if m:
                return self.submission_action(me, int(m[1]), m[2], d)
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
            m = re.fullmatch(r'/api/revisions/(\d+)/revert', p)
            if m:
                self.need(me, 'admin')
                with store.write() as c:
                    rev = ch.revert(store, c, int(m[1]), me['id'], bool(d.get('force')))
                return self.send({'ok': True, 'rev': rev})
            if p == '/api/restore':
                self.need(me, 'admin')
                with store.write() as c:
                    if not isinstance(d.get('rev'), int) or d['rev'] < 0:
                        raise HTTPError(400, 'rev (0 or a revision number) is required')
                    n = ch.restore_to(store, c, d['rev'], me['id'])
                return self.send({'ok': True, 'changed': n})
            if p.startswith('/api/manager/'):
                return self.manager_action(me, p.rsplit('/', 1)[1], d)
            raise HTTPError(404, 'not found')

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

        def submission_action(self, me, sid, action, d):
            with store.write() as c:
                sub = c.execute('SELECT * FROM submissions WHERE id=?', (sid,)).fetchone()
                if not sub:
                    raise HTTPError(404, 'no such submission')
                open_ = sub['status'] in ('pending', 'conflict')
                if action == 'vote':
                    if sub['kind'] != 'photo' or not open_:
                        raise HTTPError(400, 'only open photo proposals take votes')
                    if c.execute('SELECT 1 FROM votes WHERE submission_id=? AND user_id=?', (sid, me['id'])).fetchone():
                        store.delete('votes', submission_id=sid, user_id=me['id'])
                    else:
                        store.put('votes', {'submission_id': sid, 'user_id': me['id']})
                    return self.send({'ok': True})
                if action == 'withdraw':
                    if sub['user_id'] != me['id'] or not open_:
                        raise HTTPError(403, 'can only withdraw your own open submission')
                    ch.decide(store, c, sub, me['id'], 'withdrawn')
                    return self.send({'ok': True})
                self.need(me, 'admin')
                if not open_:
                    raise HTTPError(409, f'already {sub["status"]}')
                if action == 'reject':
                    ch.decide(store, c, sub, me['id'], 'rejected', (d.get('note') or '')[:500])
                    return self.send({'ok': True})
                if sub['kind'] == 'tag_add' and isinstance(d.get('edit'), dict):  # admin corrects the code while approving
                    old = json.loads(sub['payload'])
                    fixed = ch.tag_payload({**old, **{k: d['edit'].get(k) for k in ('kks', 'isa')}}, keep_id=old['id'])
                    store.put('submissions', {**dict(sub), 'payload': json.dumps(fixed)})
                    sub = c.execute('SELECT * FROM submissions WHERE id=?', (sid,)).fetchone()
                revs = ch.apply(store, c, sub, me['id'], force=bool(d.get('force')))
                ch.decide(store, c, sub, me['id'], 'approved', 'forced over conflict' if d.get('force') else '')
                rejected = 0
                if action == 'pick':  # choose this photo, discard the other open photos for the same equipment
                    for o in c.execute("SELECT * FROM submissions WHERE target=? AND id<>? AND status IN ('pending','conflict')",
                                       (sub['target'], sid)).fetchall():
                        ch.decide(store, c, o, me['id'], 'rejected', f'another photo was chosen (#{sid})')
                        rejected += 1
                return self.send({'ok': True, 'revs': revs, 'rejected': rejected})

        def create_user(self, me, d):
            self.need(me, 'admin')
            name, role = (d.get('username') or '').strip(), d.get('role', 'user')
            if not re.fullmatch(r'[\w.@-]{2,40}', name):
                raise HTTPError(400, 'Username: 2-40 letters, digits, . _ - @')
            if role not in ('user', 'admin'):
                raise HTTPError(400, 'role must be user or admin')
            if role == 'admin' and me['role'] != 'manager':
                raise HTTPError(403, 'only the manager can create admins')
            try:
                full_name, position = person(d)
            except ValueError as e:
                raise HTTPError(400, str(e))
            with store.write() as c:
                if c.execute('SELECT 1 FROM users WHERE username=?', (name,)).fetchone():
                    raise HTTPError(409, 'That username exists.')
                uid = store.put('users', {'username': name, 'pw': None, 'role': role, 'active': 1, 'created': int(time.time()),
                                          'full_name': full_name, 'position': position})
                self.log_user(c, me['id'], uid, f'created as {role}')
            raw = auth.make_token('reset', uid, 7 * 86400)
            return self.send({'ok': True, 'id': uid, 'link': link(f'/#reset={raw}'), 'expires_days': 7})

        def update_user(self, me, uid, d, reset):
            self.need(me, 'admin')
            with store.write() as c:
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
                        store.put('users', row)
                        if not row['active'] or row['role'] != u['role']:
                            c.execute('DELETE FROM sessions WHERE user_id=?', (uid,))
                        self.log_user(c, me['id'], uid, ', '.join(notes))
            if reset:
                raw = auth.make_token('reset', uid, 3 * 86400)
                return self.send({'ok': True, 'link': link(f'/#reset={raw}'), 'expires_days': 3})
            return self.send({'ok': True})

        def manager_action(self, me, action, d):
            with store.write() as c:
                t = store.meta('transfer', None, c)
                if action == 'transfer':
                    self.need(me, 'manager')
                    if not auth.login(me['username'], d.get('password'), self.ip())[0]:
                        raise HTTPError(403, 'Password is wrong.')
                    to = c.execute("SELECT * FROM users WHERE username=? AND role='admin' AND active=1",
                                   (d.get('username') or '',)).fetchone()
                    if not to:
                        raise HTTPError(400, 'The new manager must be an active admin.')
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


def main(argv=None):
    ap = argparse.ArgumentParser(description='KKS Explorer server')
    ap.add_argument('cmd', nargs='?', default='serve',
                    choices=['serve', 'users', 'reset-manager', 'reset-password', 'backup', 'restore', 'check', 'setup-importer',
                             'added-tags'])
    ap.add_argument('--user')
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
        c = store.conn()
        rows = [{'id': r['id'], **json.loads(r['data'])} for r in c.execute('SELECT * FROM added_tags')]
        c.close()
        print(json.dumps(rows, indent=1))
        return
    if a.cmd == 'backup':
        print(store.snapshot())
        return
    if a.cmd in ('reset-manager', 'reset-password'):
        if not a.user:
            raise SystemExit('--user is required')
        u = find_user(store, a.user)
        if a.cmd == 'reset-manager':
            with store.write() as c:
                old = auth.manager(c)
                if old and old['id'] != u['id']:
                    store.put('users', {**dict(old), 'role': 'admin'})
                    cli_log(store, c, old['id'], 'manager role removed by reset-manager')
                store.put('users', {**dict(u), 'role': 'manager', 'active': 1})
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
    if not auth.manager():
        raw = auth.make_token('setup', None, 86400)
        print(f'\n  No manager account yet. Open this one-time link to create it (valid 24 h, until used):\n'
              f'  {base_url(cfg)}/#setup={raw}\n')
    httpd = ThreadingHTTPServer((cfg['host'], cfg['port']), make_handler(cfg, store, auth))
    scheme = 'http'
    if cfg['tls_cert']:
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.load_cert_chain(cfg['tls_cert'], cfg['tls_key'] or None)
        httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
        scheme = 'https'
    print(f'  {cfg["plant_name"]}\n  Laptop: {scheme}://localhost:{cfg["port"]}\n  LAN:    {scheme}://{lan_ip()}:{cfg["port"]}\n'
          f'  Data: {cfg["db"]}, {cfg["photos_dir"]}/   Backups: {cfg["backup_dir"]}/\n  Ctrl+C to stop.\n')
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print('\nStopping; taking a snapshot.')
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
