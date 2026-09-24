"""Accounts, sessions and one-time tokens.

Roles: exactly one manager (enforced by a unique index), any number of admins and users.
- The manager is created only through the setup token printed on the server console, by a manager transfer the new
  manager accepts, or by the `reset-manager` CLI command. Nothing reachable over the network can create one otherwise.
- Tokens (setup / password reset) and session ids are stored as SHA-256 hashes, so a leaked DB copy can't be replayed."""
import hashlib, hmac, secrets, threading, time

ROLES = ('user', 'admin', 'manager')
MIN_PASSWORD = 10


def rank(role):
    return ROLES.index(role)


def _h(raw):
    return hashlib.sha256(raw.encode()).hexdigest()


def hash_password(pw):
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(pw.encode(), salt=salt, n=2 ** 14, r=8, p=1, dklen=32)
    return f'scrypt$16384$8$1${salt.hex()}${dk.hex()}'


def check_password(pw, stored):
    if not stored:
        hashlib.scrypt(b'x', salt=b'0' * 16, n=2 ** 14, r=8, p=1, dklen=32)  # same cost as a real check
        return False
    _, n, r, p, salt, dk = stored.split('$')
    got = hashlib.scrypt(pw.encode(), salt=bytes.fromhex(salt), n=int(n), r=int(r), p=int(p), dklen=len(dk) // 2)
    return hmac.compare_digest(got.hex(), dk)


def password_problem(pw):
    if not isinstance(pw, str) or len(pw) < MIN_PASSWORD:
        return f'Password must be at least {MIN_PASSWORD} characters.'
    return None


def public_user(u):
    return {'id': u['id'], 'username': u['username'], 'role': u['role'], 'active': bool(u['active']),
            'has_password': bool(u['pw']), 'created': u['created']}


class Auth:
    def __init__(self, store, cfg):
        self.store, self.cfg = store, cfg
        self._fails, self._flock = {}, threading.Lock()

    # ---- sessions ----
    def create_session(self, user_id):
        raw = secrets.token_urlsafe(32)
        now = int(time.time())
        with self.store.write() as c:
            c.execute('DELETE FROM sessions WHERE expires<?', (now,))
            self.store.put('sessions', {'token': _h(raw), 'user_id': user_id, 'created': now,
                                        'expires': now + self.cfg['session_days'] * 86400})
        return raw

    def user_for_session(self, raw):
        if not raw:
            return None
        c = self.store.conn()
        try:
            return c.execute('SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token=? AND s.expires>? '
                             'AND u.active=1 AND u.pw IS NOT NULL', (_h(raw), int(time.time()))).fetchone()
        finally:
            c.close()

    def end_session(self, raw):
        with self.store.write():
            self.store.delete('sessions', token=_h(raw))

    def end_all_sessions(self, user_id):
        with self.store.write():
            self.store.delete('sessions', user_id=user_id)

    # ---- login throttling (in memory; per username and per IP) ----
    def throttled(self, *keys):
        now = time.time()
        with self._flock:
            return max((self._fails.get(k, (0, 0))[1] - now for k in keys), default=0) > 0

    def record(self, ok, *keys):
        with self._flock:
            for k in keys:
                if ok:
                    self._fails.pop(k, None)
                else:
                    n = self._fails.get(k, (0, 0))[0] + 1
                    self._fails[k] = (n, time.time() + (min(900, 15 * 2 ** (n - 5)) if n >= 5 else 0))

    def login(self, username, password, ip):
        keys = ('u:' + (username or '').lower(), 'ip:' + ip)
        if self.throttled(*keys):
            return None, 'Too many failed attempts. Wait a few minutes.'
        c = self.store.conn()
        u = c.execute('SELECT * FROM users WHERE username=?', (username or '',)).fetchone()
        c.close()
        ok = bool(u) and check_password(password or '', u['pw']) and u['active']
        if not u:
            check_password('x', None)
        self.record(ok, *keys)
        return (u, None) if ok else (None, 'Wrong username or password.')

    # ---- one-time tokens: setup (create the manager) and password reset / invite ----
    def make_token(self, kind, user_id, ttl):
        raw = secrets.token_urlsafe(24)
        with self.store.write() as c:
            if kind == 'setup':
                c.execute("DELETE FROM tokens WHERE kind='setup'")
            else:
                c.execute('DELETE FROM tokens WHERE kind=? AND user_id=?', (kind, user_id))
            self.store.put('tokens', {'token': _h(raw), 'kind': kind, 'user_id': user_id, 'expires': int(time.time()) + ttl})
        return raw

    def peek_token(self, kind, raw, c):
        return c.execute('SELECT * FROM tokens WHERE token=? AND kind=? AND expires>?',
                         (_h(raw or ''), kind, int(time.time()))).fetchone()

    def consume_token(self, raw):
        self.store.delete('tokens', token=_h(raw))

    def manager(self, c=None):
        own = c is None
        c = c or self.store.conn()
        try:
            return c.execute("SELECT * FROM users WHERE role='manager'").fetchone()
        finally:
            if own: c.close()
