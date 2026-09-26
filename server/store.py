"""SQLite storage, write journal and backups.

Every write to a durable table goes through Store.put()/Store.delete() inside Store.write(). Each write is also
appended to backups/journal-<seq>.jsonl after the transaction commits: an incremental backup of every change.
Full snapshots (sqlite backup API) are taken at startup, every `snapshot_every` writes, and on demand.
restore() = newest snapshot at or before the target + replay of the journal up to the target seq, into a NEW file.
Sessions are not journaled (losing them only means logging in again)."""
import glob, json, os, re, sqlite3, threading, time
from contextlib import contextmanager

SCHEMA = """
CREATE TABLE IF NOT EXISTS equipment(kks TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER);
CREATE TABLE IF NOT EXISTS photos(id TEXT PRIMARY KEY, kks TEXT, file TEXT, caption TEXT, created INTEGER);
CREATE TABLE IF NOT EXISTS reviews(tag_id TEXT PRIMARY KEY, data TEXT NOT NULL, updated INTEGER);
CREATE TABLE IF NOT EXISTS links(proc TEXT, step INTEGER, kks TEXT, PRIMARY KEY(proc,step,kks));
CREATE TABLE IF NOT EXISTS added_tags(id TEXT PRIMARY KEY, data TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS users(id INTEGER PRIMARY KEY, username TEXT NOT NULL UNIQUE COLLATE NOCASE, pw TEXT,
  role TEXT NOT NULL CHECK(role IN ('manager','admin','user')), active INTEGER NOT NULL DEFAULT 1, created INTEGER,
  full_name TEXT, position TEXT);
CREATE UNIQUE INDEX IF NOT EXISTS one_manager ON users(role) WHERE role='manager';
CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, user_id INTEGER NOT NULL, created INTEGER, expires INTEGER);
CREATE TABLE IF NOT EXISTS tokens(token TEXT PRIMARY KEY, kind TEXT NOT NULL, user_id INTEGER, expires INTEGER);
CREATE TABLE IF NOT EXISTS submissions(id INTEGER PRIMARY KEY, client_id TEXT UNIQUE, user_id INTEGER, kind TEXT,
  target TEXT, payload TEXT, status TEXT, created INTEGER, decided_by INTEGER, decided_at INTEGER, note TEXT);
CREATE INDEX IF NOT EXISTS sub_status ON submissions(status, target);
CREATE TABLE IF NOT EXISTS votes(submission_id INTEGER, user_id INTEGER, PRIMARY KEY(submission_id, user_id));
CREATE TABLE IF NOT EXISTS revisions(rev INTEGER PRIMARY KEY AUTOINCREMENT, ts INTEGER, actor INTEGER, entity TEXT,
  key TEXT, before TEXT, after TEXT, submission_id INTEGER, note TEXT);
CREATE INDEX IF NOT EXISTS rev_key ON revisions(entity, key);
CREATE TABLE IF NOT EXISTS meta(k TEXT PRIMARY KEY, v TEXT);
-- v2 (M1, 2026-09-26): plant data lives in signed log entries (docs/PROTOCOL.md); the tables above that held live
-- data (equipment, photos, reviews, links, added_tags, submissions, votes, data revisions) are only read once, to
-- migrate an older database. `revisions` keeps the local account/sheet notes.
CREATE TABLE IF NOT EXISTS entries(id TEXT PRIMARY KEY, peer TEXT NOT NULL, seq INTEGER NOT NULL, hlc0 INTEGER,
  hlc1 INTEGER, type TEXT, data TEXT NOT NULL, received INTEGER, UNIQUE(peer, seq));
CREATE TABLE IF NOT EXISTS custodial(device TEXT PRIMARY KEY, person TEXT NOT NULL, seed TEXT NOT NULL, created INTEGER);
CREATE TABLE IF NOT EXISTS subs(id INTEGER PRIMARY KEY, client_id TEXT UNIQUE, entry TEXT, user_id INTEGER,
  kind TEXT, held TEXT, status TEXT, note TEXT, created INTEGER, decided_at INTEGER, decided_by INTEGER);
CREATE INDEX IF NOT EXISTS subs_entry ON subs(entry);
CREATE TABLE IF NOT EXISTS blobs(sha TEXT PRIMARY KEY, file TEXT NOT NULL, size INTEGER);
CREATE TABLE IF NOT EXISTS entry_notes(entry TEXT PRIMARY KEY, note TEXT);
-- M2: a second, different entry for a (peer, seq) we already hold = proof of a cloned/misbehaving key (§4)
CREATE TABLE IF NOT EXISTS evidence(id TEXT PRIMARY KEY, peer TEXT NOT NULL, seq INTEGER NOT NULL, data TEXT NOT NULL);
"""
KEYS = {  # primary-key columns of every journaled table
    'equipment': ('kks',), 'photos': ('id',), 'reviews': ('tag_id',), 'links': ('proc', 'step', 'kks'), 'added_tags': ('id',),
    'users': ('id',), 'tokens': ('token',), 'submissions': ('id',), 'votes': ('submission_id', 'user_id'),
    'revisions': ('rev',), 'meta': ('k',),
    'entries': ('id',), 'custodial': ('device',), 'subs': ('id',), 'blobs': ('sha',), 'entry_notes': ('entry',),
    'evidence': ('id',),
}
NOT_JOURNALED = {'sessions'}
COLUMNS_ADDED = [('users', 'full_name', 'TEXT'), ('users', 'position', 'TEXT'),  # 2026-09-26
                 ('users', 'person', 'TEXT'), ('users', 'device', 'TEXT'),    # v2 log: person ID, custodial device
                 ('subs', 'person', 'TEXT')]                                  # M2: proposals that came by sync


def migrate(c):
    """Add columns introduced after a database was created. Also run on restored snapshots before the journal
    replay, since newer journal rows carry these columns."""
    for table, col, typ in COLUMNS_ADDED:
        if col not in [r[1] for r in c.execute(f'PRAGMA table_info({table})')]:
            c.execute(f'ALTER TABLE {table} ADD COLUMN {col} {typ}')


def connect(path):
    c = sqlite3.connect(path, timeout=15, isolation_level=None)
    c.row_factory = sqlite3.Row
    c.execute('PRAGMA foreign_keys=ON')
    return c


class Store:
    def __init__(self, cfg):
        self.cfg, self.path, self.bdir = cfg, cfg['db'], cfg['backup_dir']
        self.lock = threading.RLock()
        self._pending = None
        os.makedirs(self.bdir, exist_ok=True)
        c = connect(self.path)
        c.execute('PRAGMA journal_mode=WAL')
        c.executescript(SCHEMA)
        migrate(c)
        c.close()
        self._since_snapshot = 0
        # If the process died between a commit and its journal append, the journal has a gap: snapshot to cover it.
        if self.meta('seq', 0) != self._journal_tail() or not self.snapshots():
            self.snapshot()

    # ---- reads ----
    def conn(self):
        return connect(self.path)

    def meta(self, k, default=None, c=None):
        own = c is None
        c = c or self.conn()
        try:
            r = c.execute('SELECT v FROM meta WHERE k=?', (k,)).fetchone()
            return json.loads(r['v']) if r else default
        finally:
            if own: c.close()

    # ---- writes ----
    @contextmanager
    def write(self):
        """Serialized write transaction. Yields a connection; use put()/delete() for journaled tables."""
        with self.lock:
            c = self.conn()
            c.execute('BEGIN IMMEDIATE')
            self._pending, self._c = [], c
            try:
                yield c
                c.execute('COMMIT')
            except BaseException:
                c.execute('ROLLBACK')
                self._pending = None
                raise
            finally:
                ops, self._pending = self._pending, None
                c.close()
            if ops:
                self._append(ops)

    def _next_seq(self):
        c = self._c
        seq = self.meta('seq', 0, c) + 1
        c.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('seq', json.dumps(seq)))
        return seq

    def put(self, table, row):
        """Insert or replace a full row. Returns lastrowid."""
        assert self._pending is not None, 'put() outside write()'
        cols = list(row)
        cur = self._c.execute(f'INSERT OR REPLACE INTO {table}({",".join(cols)}) VALUES({",".join("?" * len(cols))})',
                              [row[k] for k in cols])
        if table not in NOT_JOURNALED:
            full = dict(row)
            if table in ('submissions', 'revisions', 'users', 'subs') and KEYS[table][0] not in full:
                full[KEYS[table][0]] = cur.lastrowid
            self._pending.append({'seq': self._next_seq(), 't': table, 'row': full})
        return cur.lastrowid

    def delete(self, table, **key):
        assert self._pending is not None, 'delete() outside write()'
        where = ' AND '.join(f'{k}=?' for k in key)
        n = self._c.execute(f'DELETE FROM {table} WHERE {where}', list(key.values())).rowcount
        if n and table not in NOT_JOURNALED:
            self._pending.append({'seq': self._next_seq(), 't': table, 'del': key})
        return n

    # ---- journal + snapshots ----
    def _journal_files(self):
        return sorted(glob.glob(os.path.join(self.bdir, 'journal-*.jsonl')),
                      key=lambda p: int(re.search(r'journal-(\d+)', p)[1]))

    def _journal_tail(self):
        files = self._journal_files()
        if not files:
            return self.snapshots()[-1][0] if self.snapshots() else 0
        last = 0
        with open(files[-1]) as f:
            for line in f:
                if line.strip():
                    last = json.loads(line)['seq']
        return last or int(re.search(r'journal-(\d+)', files[-1])[1])

    def _append(self, ops):
        files = self._journal_files()
        path = files[-1] if files else os.path.join(self.bdir, f'journal-{ops[0]["seq"] - 1}.jsonl')
        with open(path, 'a') as f:
            for op in ops:
                f.write(json.dumps(op, separators=(',', ':')) + '\n')
            f.flush()
            os.fsync(f.fileno())
        self._since_snapshot += len(ops)
        if self._since_snapshot >= self.cfg['snapshot_every']:
            self.snapshot()

    def snapshots(self):
        out = []
        for p in glob.glob(os.path.join(self.bdir, 'snap-*.db')):
            m = re.search(r'snap-(\d+)-', p)
            if m: out.append((int(m[1]), p))
        return sorted(out)

    def snapshot(self):
        """Full copy of the DB; starts a new journal file. Returns the snapshot path."""
        with self.lock:
            src = self.conn()
            seq = self.meta('seq', 0, src)
            path = os.path.join(self.bdir, f'snap-{seq:09d}-{time.strftime("%Y%m%d-%H%M%S")}.db')
            if not any(s == seq for s, _ in self.snapshots()):
                dst = sqlite3.connect(path)
                src.backup(dst)
                dst.execute('DELETE FROM sessions')
                dst.commit(); dst.close()
            src.close()
            open(os.path.join(self.bdir, f'journal-{seq}.jsonl'), 'a').close()
            self._since_snapshot = 0
            self._prune()
            return path

    def _prune(self):
        snaps = self.snapshots()
        keep = max(1, self.cfg['snapshot_keep'])
        for _, p in snaps[:-keep]:
            os.remove(p)
        oldest = self.snapshots()[0][0]
        files = self._journal_files()
        for i, p in enumerate(files):  # a journal is needed if it (or the next one) covers seqs after the oldest snapshot
            nxt = int(re.search(r'journal-(\d+)', files[i + 1])[1]) if i + 1 < len(files) else None
            if nxt is not None and nxt <= oldest:
                os.remove(p)


def restore(cfg, out, to_seq=None):
    """Rebuild a database from snapshot + journal into `out` (must not exist). Returns (snapshot seq, final seq)."""
    if os.path.exists(out):
        raise SystemExit(f'{out} exists; choose another --out')
    bdir = cfg['backup_dir']
    snaps = sorted((int(re.search(r'snap-(\d+)-', p)[1]), p) for p in glob.glob(os.path.join(bdir, 'snap-*.db')))
    if to_seq is not None:
        snaps = [s for s in snaps if s[0] <= to_seq]
    if not snaps:
        raise SystemExit('no snapshot at or before that point')
    base_seq, snap = snaps[-1]
    src, dst = sqlite3.connect(snap), sqlite3.connect(out)
    src.backup(dst); src.close()
    dst.executescript(SCHEMA)  # snapshots from before a table existed
    migrate(dst)
    dst.row_factory = sqlite3.Row
    last = base_seq
    for p in sorted(glob.glob(os.path.join(bdir, 'journal-*.jsonl')), key=lambda p: int(re.search(r'journal-(\d+)', p)[1])):
        with open(p) as f:
            for line in f:
                if not line.strip(): continue
                op = json.loads(line)
                if op['seq'] <= last: continue
                if to_seq is not None and op['seq'] > to_seq: break
                if op['seq'] != last + 1:
                    raise SystemExit(f'journal gap after seq {last} (next is {op["seq"]}); restored up to {last} only')
                t = op['t']
                if 'row' in op:
                    cols = list(op['row'])
                    dst.execute(f'INSERT OR REPLACE INTO {t}({",".join(cols)}) VALUES({",".join("?" * len(cols))})',
                                [op['row'][k] for k in cols])
                else:
                    dst.execute(f'DELETE FROM {t} WHERE ' + ' AND '.join(f'{k}=?' for k in op['del']), list(op['del'].values()))
                last = op['seq']
    dst.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', ('seq', json.dumps(last)))
    dst.commit(); dst.close()
    return base_seq, last
