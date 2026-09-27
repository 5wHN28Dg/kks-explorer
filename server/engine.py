"""Plant data on the signed log (docs/ARCHITECTURE.md M1, docs/PROTOCOL.md).

The server is a peer that signs on behalf of people who use it through a browser: every account has a *custodial*
device key here (table `custodial`), and every change is a log entry signed with it (table `entries`, journaled like
everything else). What the API shows is the replay of the log (peer/replay.py), kept in memory and advanced
entry by entry; anything that can move a revocation cut (`revoke`, `root`) or an entry from another process
(CLI commands) triggers a full replay.

The plant root key (docs/PROTOCOL.md §8) is a separate file, `root_key` in config (default: root.key next to the DB),
readable only by the server's user. It is needed to create the plant (genesis) and to change who the manager is.
It is not in plant.db or the backups: back it up yourself (`python3 app.py export-root-key`)."""
import hashlib, json, os, secrets, time
from contextlib import contextmanager

from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

from peer import proto as P
from peer import replay as R

TYPES_FULL_REPLAY = ('revoke', 'root')
ENTITIES = ('equipment', 'review', 'link', 'photo', 'added_tag')


class NoRootKey(Exception):
    """The root key file is missing or unreadable."""


def root_path(cfg):
    return cfg.get('root_key') or os.path.join(os.path.dirname(os.path.abspath(cfg['db'])), 'root.key')


def default(field):
    return [] if field == 'custom' else ''


class Engine:
    def __init__(self, store, cfg):
        self.store, self.cfg = store, cfg
        self.lock = store.lock           # one lock for DB writes and the in-memory replay: no lock-order problems
        self.root_path = root_path(cfg)
        self._pending = None
        self.keys, self.entries, self.blob_files = {}, {}, {}
        self.clock = P.HLC()
        self.anchor = None
        self.run, self.chain_ignored, self.last = None, {}, None
        self.listeners = []   # called after new entries (own or received): auto-sync, UI
        self.invites = None   # server.invites.Invites, set by the HTTP handler (join by invite, PROTOCOL.md §16)
        with self.lock:
            self._load()
            from server import migrate_v1
            if migrate_v1.needed(self):
                migrate_v1.run(self)

    # ---------- loading / replay ----------
    def _load(self):
        c = self.store.conn()
        try:
            self.anchor = self.store.meta('root_pub', None, c)
            for r in c.execute('SELECT device, seed FROM custodial'):
                self.keys.setdefault(r['device'], P.key_from_seed(bytes.fromhex(r['seed'])))
            for r in c.execute('SELECT sha, file FROM blobs'):
                self.blob_files[r['sha']] = r['file']
            have = set(self.entries)
            for r in c.execute('SELECT id, data FROM entries UNION ALL SELECT id, data FROM evidence'):
                if r['id'] not in have:
                    self.entries[r['id']] = json.loads(r['data'])
        finally:
            c.close()
        for e in self.entries.values():
            if e['peer'] in self.keys and (e['hlc'][0], e['hlc'][1]) > (self.clock.l, self.clock.c):
                self.clock.l, self.clock.c = e['hlc']
        self.rebuild()

    def rebuild(self):
        # own database: every entry was verified or signed here when it was stored
        self.run, self.chain_ignored = R.replay_run(None, self.anchor, trusted=self.entries)
        self.last = max((P.order_key(e) for e in self.entries.values()), default=None)

    def refresh(self):
        """Pick up entries written by another process (CLI) since we last looked."""
        with self.lock:
            c = self.store.conn()
            try:
                n = c.execute('SELECT (SELECT COUNT(*) FROM entries) + (SELECT COUNT(*) FROM evidence)').fetchone()[0]
            finally:
                c.close()
            if n != len(self.entries):
                self._load()

    def _absorb(self, new):
        for e in new:
            self.entries[P.entry_id(e)] = e
        new.sort(key=P.order_key)
        if self.run is None or any(e['type'] in TYPES_FULL_REPLAY for e in new) or \
                (self.last is not None and P.order_key(new[0]) <= self.last):
            self.rebuild()
        else:
            self.run.run(new)
            self.last = P.order_key(new[-1])
        bad = [self.run.ignored[P.entry_id(e)] for e in new if P.entry_id(e) in self.run.ignored]
        if bad:   # the API checks permissions before writing; this means a bug, so make it loud
            raise RuntimeError(f'server wrote entries the replay ignores: {bad}')

    # ---------- writing ----------
    @contextmanager
    def tx(self):
        """A store.write() transaction whose log entries join the replay after the commit."""
        with self.lock:
            self._pending, self._after, self._undo = [], [], []
            try:
                with self.store.write() as c:
                    yield c
                new, after = self._pending, self._after
            except BaseException:
                for fn in self._undo:
                    fn()
                raise
            finally:
                self._pending = self._after = self._undo = None
            for fn in after:
                fn()
            if new:
                self._absorb(new)
                self._changed('local')

    def append(self, c, device, type_, body, wall_ms=None):
        """Sign and store one entry by a custodial device. Returns its entry ID."""
        assert self._pending is not None, 'append() outside tx()'
        last = c.execute('SELECT id, seq FROM entries WHERE peer=? ORDER BY seq DESC LIMIT 1', (device,)).fetchone()
        hlc = self.clock.now(int(time.time() * 1000) if wall_ms is None else wall_ms)
        e = P.make_entry(self.keys[device], last['seq'] + 1 if last else 1, last['id'] if last else None, hlc, type_, body)
        eid = P.entry_id(e)
        self.store.put('entries', {'id': eid, 'peer': device, 'seq': e['seq'], 'hlc0': hlc[0], 'hlc1': hlc[1],
                                   'type': type_, 'data': P.canonical(e).decode(), 'received': int(time.time())})
        self._pending.append(e)
        return eid

    def new_device(self, c, person):
        seed = secrets.token_bytes(32)
        key = P.key_from_seed(seed)
        dev = P.peer_id(key)
        self.store.put('custodial', {'device': dev, 'person': person, 'seed': seed.hex(), 'created': int(time.time())})
        self.keys[dev] = key
        return dev

    def note_of(self, eid):
        c = self.store.conn()
        try:
            r = c.execute('SELECT note FROM entry_notes WHERE entry=?', (eid,)).fetchone()
            return r['note'] if r else ''
        finally:
            c.close()

    def note(self, eid, text):
        if text:
            self.store.put('entry_notes', {'entry': eid, 'note': text[:500]})

    # ---------- root key ----------
    def root_key(self):
        try:
            with open(self.root_path) as f:
                key = P.key_from_seed(bytes.fromhex(f.read().strip()))
        except (OSError, ValueError):
            raise NoRootKey(f'The plant root key ({self.root_path}) is missing. Restore it from your backup '
                            f'(python3 app.py import-root-key FILE).')
        if P.peer_id(key) != self.current_root():
            raise NoRootKey(f'{self.root_path} holds a different key than this plant\'s root key.')
        return key

    def current_root(self):
        return self.run.root if self.run and self.run.manager else self.anchor

    def create_root(self):
        if os.path.exists(self.root_path):
            raise NoRootKey(f'{self.root_path} already exists; move it away first if you really mean a new plant.')
        seed, tmp = secrets.token_bytes(32), self.root_path + '.new'
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(seed.hex() + '\n')
            f.flush()
            os.fsync(f.fileno())
        self._after.append(lambda: os.replace(tmp, self.root_path))   # only once the genesis is committed
        self._undo.append(lambda: os.path.exists(tmp) and os.remove(tmp))
        return P.key_from_seed(seed)

    def genesis(self, c, person, username, full_name, position, plant, wall_ms=None, device=None):
        """First entry of a new plant: creates the root key and the manager's device (a new custodial key, or
        `device`: this laptop's own key in peer mode)."""
        if self.anchor is not None or self.entries:
            raise ValueError('this node already belongs to a plant; a second genesis would split it off')
        root = self.create_root()
        self.anchor = P.peer_id(root)
        self.store.put('meta', {'k': 'root_pub', 'v': json.dumps(self.anchor)})
        self.store.put('meta', {'k': 'log_version', 'v': '1'})
        dev = device or self.new_device(c, person)
        sm = {'kind': 'manager', 'person': person}
        sd = {'kind': 'device', 'device': dev, 'person': person}
        self.append(c, dev, 'genesis', {
            'plant': plant[:80] or 'Plant', 'root': self.anchor,
            'manager': {'person': person, 'username': username, 'full_name': full_name, 'position': position},
            'stmt_manager': sm, 'stmt_device': sd,
            'sig_manager': R.sign_statement(root, sm), 'sig_device': R.sign_statement(root, sd)}, wall_ms)
        self.run = None   # next absorb replays from scratch with the new anchor
        return dev

    def root_statement(self, c, carrier, stmt):
        key = self.root_key()
        return self.append(c, carrier, 'root', {'stmt': stmt, 'root_sig': R.sign_statement(key, stmt)})

    def export_root(self, passphrase):
        """The root key encrypted with a passphrase (scrypt + ChaCha20-Poly1305), as a JSON text for a backup."""
        seed = bytes.fromhex(open(self.root_path).read().strip())
        salt, nonce = secrets.token_bytes(16), secrets.token_bytes(12)
        k = hashlib.scrypt(passphrase.encode(), salt=salt, n=2 ** 15, r=8, p=1, maxmem=64 * 2 ** 20, dklen=32)
        ct = ChaCha20Poly1305(k).encrypt(nonce, seed, b'kks-root-backup-v1')
        return json.dumps({'kks_root_backup': 1, 'root': P.peer_id(P.key_from_seed(seed)), 'salt': salt.hex(),
                           'nonce': nonce.hex(), 'ct': ct.hex(), 'kdf': 'scrypt n=32768 r=8 p=1'}, indent=1)

    def import_root(self, text, passphrase):
        d = json.loads(text)
        k = hashlib.scrypt(passphrase.encode(), salt=bytes.fromhex(d['salt']), n=2 ** 15, r=8, p=1,
                           maxmem=64 * 2 ** 20, dklen=32)
        seed = ChaCha20Poly1305(k).decrypt(bytes.fromhex(d['nonce']), bytes.fromhex(d['ct']), b'kks-root-backup-v1')
        if P.peer_id(P.key_from_seed(seed)) != self.current_root():
            raise NoRootKey('That backup is the root key of a different plant (or an older, rotated key).')
        fd = os.open(self.root_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as f:
            f.write(seed.hex() + '\n')

    def _changed(self, why):
        for fn in list(self.listeners):
            try:
                fn(why)
            except Exception:   # a listener must never break a write
                pass

    # ---------- this node's own device (peer mode: the laptop owner's key) ----------
    def node_device(self):
        return self.store.meta('node_device')

    def ensure_node_device(self):
        """The key this laptop signs with, created on first use (before it belongs to any plant)."""
        with self.lock:
            dev = self.node_device()
            if dev:
                return dev
            with self.store.write():
                seed = secrets.token_bytes(32)
                dev = P.peer_id(P.key_from_seed(seed))
                self.store.put('custodial', {'device': dev, 'person': '', 'seed': seed.hex(), 'created': int(time.time())})
                self.store.put('meta', {'k': 'node_device', 'v': json.dumps(dev)})
            self.keys[dev] = P.key_from_seed(seed)
            return dev

    def owner(self):
        """Peer mode: the account row of this laptop's owner, created/updated from the log once the node's device is
        certified (by a server enrolment, a bundle or a sync). None while the laptop has not joined a plant."""
        dev = self.node_device()
        with self.lock:
            d = self.run.devices.get(dev) if dev and self.run else None
            if not d or dev in self.run.cuts or d['person'] not in self.run.persons:
                return None
            p = self.run.persons[d['person']]
            role = 'manager' if self.run.manager == d['person'] else p['role']
            c = self.store.conn()
            try:
                u = c.execute('SELECT * FROM users WHERE device=?', (dev,)).fetchone()
            finally:
                c.close()
            row = {'username': p['username'], 'pw': None, 'role': role, 'active': 1, 'full_name': p['full_name'],
                   'position': p['position'], 'person': d['person'], 'device': dev}
            if u is None or any(u[k] != v for k, v in row.items()):
                with self.store.write() as c:
                    if role == 'manager':   # one manager row: someone else's stale row gives way
                        c.execute("UPDATE users SET role='admin' WHERE role='manager' AND device<>?", (dev,))
                    if u is None:
                        c.execute('DELETE FROM users WHERE username=? COLLATE NOCASE', (p['username'],))
                    self.store.put('users', {**(dict(u) if u else {'created': int(time.time())}), **row})
                    self.store.put('custodial', {'device': dev, 'person': d['person'], 'seed': c.execute(
                        'SELECT seed FROM custodial WHERE device=?', (dev,)).fetchone()[0], 'created': int(time.time())})
                c = self.store.conn()
                try:
                    u = c.execute('SELECT * FROM users WHERE device=?', (dev,)).fetchone()
                finally:
                    c.close()
            return u

    # ---------- bundles: the log (+ photos) in one file, for USB / messaging / joining ----------
    def bundle(self, photos=False):
        """gzip'd JSON of every entry (+ photo bytes if asked). Holds plant data unencrypted: admins only."""
        import base64, gzip
        with self.lock:
            out = {'kks_bundle': 1, 'root': self.anchor, 'plant': self.run.settings.get('plant') if self.run else None,
                   'created': int(time.time()), 'entries': self.entries_for({})}
            if photos:
                out['blobs'] = {}
                for sha in sorted({v['blob'] for v in self.run.photos.values()}):
                    data = self.blob_get(sha)
                    if data is not None:
                        out['blobs'][sha] = base64.b64encode(data).decode()
        return gzip.compress(json.dumps(out, separators=(',', ':')).encode(), 6)

    def import_bundle(self, raw):
        """-> {'entries': new, 'photos': new, 'adopted': bool}. A node with no plant yet takes the bundle's plant:
        whoever imports a file has chosen to trust whoever gave it to them."""
        import base64, gzip
        try:
            d = json.loads(gzip.decompress(raw))
            assert isinstance(d, dict) and d.get('kks_bundle') == 1 and isinstance(d.get('entries'), list)
        except Exception:
            raise ValueError('not a KKS Explorer bundle')
        adopted = False
        if self.anchor is None:
            if not isinstance(d.get('root'), str) or len(d['root']) != 43:
                raise ValueError('the bundle names no plant')
            self.adopt(d['root'])
            adopted = True
        elif d.get('root') != self.anchor:
            raise ValueError('this bundle is from a different plant')
        n = self.ingest(d['entries'])
        got = 0
        for sha, b64 in (d.get('blobs') or {}).items():
            try:
                if self.blob_put(sha, base64.b64decode(b64, validate=True)):
                    got += 1
            except (ValueError, TypeError):
                pass
        return {'entries': n, 'photos': got, 'adopted': adopted}

    # ---------- as a sync node (peer/sync.py, docs/PROTOCOL.md §15) ----------
    def identity(self):
        """The key this node proves itself with: the manager's custodial device if it's here, else an admin's,
        else any valid one. It only authenticates connections; it signs no entries by itself."""
        dev = self.node_device()
        if dev and dev in self.keys:   # peer mode: always this laptop's own key
            return self.keys[dev]
        with self.lock:
            c = self.store.conn()
            try:
                rows = c.execute("SELECT device, role FROM users WHERE device IS NOT NULL AND active=1 "
                                 "ORDER BY role='manager' DESC, role='admin' DESC, id").fetchall()
            finally:
                c.close()
            for r in rows:
                if r['device'] in self.keys and r['device'] in self.run.devices and r['device'] not in self.run.cuts:
                    return self.keys[r['device']]
            for dev, key in self.keys.items():   # e.g. a new device not certified yet: the other side decides
                if dev not in (self.run.cuts if self.run else {}):
                    return key
        raise NoRootKey('this node has no usable device key to connect with')

    def root(self):
        return self.anchor

    def adopt(self, root):
        with self.lock:
            if self.anchor is not None:
                raise ValueError('this node already belongs to a plant')
            with self.store.write():
                self.store.put('meta', {'k': 'root_pub', 'v': json.dumps(root)})
                self.store.put('meta', {'k': 'log_version', 'v': '1'})
            self.anchor = root
            self.rebuild()

    def vv(self):
        """{device: [last seq, ID of that entry]}: the ID lets two copies of one key be told apart (§15)."""
        c = self.store.conn()
        try:
            return {r[0]: [r[1], r[2]] for r in c.execute(
                'SELECT e.peer, e.seq, e.id FROM entries e JOIN (SELECT peer, MAX(seq) AS s FROM entries GROUP BY peer) m '
                'ON e.peer=m.peer AND e.seq=m.s')}
        finally:
            c.close()

    def entries_for(self, vv):
        """What the other side lacks by its version vector; the whole chain of a device whose entry at their last seq
        differs from ours (a fork: they will find where it splits); all fork evidence."""
        c = self.store.conn()
        try:
            ids = {(r[0], r[1]): r[2] for r in c.execute('SELECT peer, seq, id FROM entries')}
            out = []
            for r in c.execute('SELECT peer, seq, data FROM entries ORDER BY peer, seq'):
                have = vv.get(r['peer'])
                seq, head = (have if isinstance(have, list) and len(have) == 2 else (0, None))
                if not isinstance(seq, int) or r['seq'] > seq or ids.get((r['peer'], seq), head) != head:
                    out.append(json.loads(r['data']))
            out += [json.loads(r['data']) for r in c.execute('SELECT data FROM evidence')]
            return out
        finally:
            c.close()

    def join_offer(self, remote, msg):
        if not self.invites:
            return {'t': 'join_ack', 'state': 'unknown'}
        return self.invites.offer(remote, msg)

    def may_read(self, peer):
        """Only a certified, unrevoked device of a known person receives plant data."""
        with self.lock:
            d = self.run.devices.get(peer) if self.run else None
            return bool(d) and peer not in self.run.cuts and d['person'] in self.run.persons

    def ingest(self, entries):
        """Store entries from another peer: signature checked, each device's chain continued in order (entries whose
        predecessor we lack are skipped: the next sync brings them), a second different entry for a (peer, seq) we
        hold is kept as fork evidence. Then replay. -> number of new entries."""
        good = {}
        for e in entries if isinstance(entries, list) else []:
            try:
                P.verify_entry(e)
            except P.ProtocolError:
                continue
            good.setdefault(e['peer'], []).append((e['seq'], P.entry_id(e), e))
        with self.lock:
            # only devices certified once this batch is counted get stored (a stranger's entries are not kept); a
            # device's cert may arrive in the same batch as its entries, so relaying still works
            trial, _ = R.replay_run(None, self.anchor, trusted={**self.entries, **{eid: e for lst in good.values() for _, eid, e in lst}})
            good = {peer: lst for peer, lst in good.items() if peer in trial.devices}
            new = []
            with self.store.write() as c:
                for peer, lst in good.items():
                    last = c.execute('SELECT id, seq FROM entries WHERE peer=? ORDER BY seq DESC LIMIT 1', (peer,)).fetchone()
                    last_seq, last_id = (last['seq'], last['id']) if last else (0, None)
                    for seq, eid, e in sorted(lst, key=lambda x: x[0]):
                        if eid in self.entries:
                            continue
                        row = {'id': eid, 'peer': peer, 'seq': seq, 'data': P.canonical(e).decode()}
                        if seq <= last_seq:   # we hold a different entry there: a fork
                            self.store.put('evidence', row)
                        elif seq == last_seq + 1 and e['prev'] == last_id:
                            self.store.put('entries', {**row, 'hlc0': e['hlc'][0], 'hlc1': e['hlc'][1],
                                                       'type': e['type'], 'received': int(time.time())})
                            last_seq, last_id = seq, eid
                        else:
                            continue
                        new.append((eid, e))
            if not new:
                return 0
            wall = int(time.time() * 1000)
            for eid, e in new:
                self.entries[eid] = e
                self.clock.recv(e['hlc'], wall)
            self.rebuild()
            self._after_ingest()
        self._changed('received')
        return len(new)

    def _after_ingest(self):
        """Keep the server-local tables in step with what arrived: a submission row for every proposal (so it shows
        in Approvals), and the account mirror (role, deactivated) for people changed on another device."""
        run = self.run
        with self.store.write() as c:
            known = {r[0] for r in c.execute('SELECT entry FROM subs WHERE entry IS NOT NULL')}
            by_person = {r['person']: r for r in c.execute('SELECT * FROM users WHERE person IS NOT NULL')}
            for eid in run.proposals:
                if eid not in known:
                    e = self.entries[eid]
                    person = run.authors.get(eid)
                    u = by_person.get(person)
                    self.store.put('subs', {'entry': eid, 'user_id': u['id'] if u else None, 'person': person,
                                            'kind': e['type'], 'created': e['hlc'][0] // 1000})
            want = {}
            for pid, u in by_person.items():
                if pid not in run.persons:
                    continue
                role = 'manager' if run.manager == pid else run.persons[pid]['role']
                active = 1 if u['active'] and u['device'] not in run.cuts else 0
                p = run.persons[pid]
                if (role, active, p['full_name'], p['position']) != (u['role'], u['active'], u['full_name'], u['position']):
                    want[pid] = {**dict(u), 'role': role, 'active': active, 'full_name': p['full_name'], 'position': p['position']}
            for row in sorted(want.values(), key=lambda r: r['role'] == 'manager'):   # demote before promoting
                self.store.put('users', row)
                if not row['active'] or row['role'] != by_person[row['person']]['role']:
                    self.store.delete('sessions', user_id=row['id'])

    def blob_wants(self):
        with self.lock:
            shas = {v['blob'] for v in self.run.photos.values()}
            shas |= {self.entries[e]['body']['blob'] for e, st in self.run.proposals.items()
                     if st == 'pending' and self.entries[e]['type'] == 'photo'}
            return sorted(shas - set(self.blob_files))

    def blob_get(self, sha):
        f = self.blob_files.get(sha)
        if not f:
            return None
        try:
            with open(os.path.join(self.cfg['photos_dir'], f), 'rb') as fh:
                return fh.read()
        except OSError:
            return None

    def blob_put(self, sha, data):
        """Accept only blobs we asked for (referenced by the log) whose bytes match their hash."""
        if not isinstance(sha, str) or sha not in self.blob_wants() or hashlib.sha256(data).hexdigest() != sha:
            return False
        ext = next((x for sig, x in ((b'\xff\xd8\xff', 'jpg'), (b'\x89PNG', 'png'), (b'RIFF', 'webp'),
                                     (b'\xff\x0a', 'jxl'), (b'\x00\x00\x00\x0cJXL', 'jxl')) if data.startswith(sig)), 'bin')
        name = f'{sha}.{ext}'
        path = os.path.join(self.cfg['photos_dir'], name)
        os.makedirs(self.cfg['photos_dir'], exist_ok=True)
        with open(path + '.part', 'wb') as f:
            f.write(data)
        os.replace(path + '.part', path)
        with self.lock:
            with self.store.write():
                self.store.put('blobs', {'sha': sha, 'file': name, 'size': len(data)})
            self.blob_files[sha] = name
        return True

    # ---------- reading ----------
    def entry(self, eid):
        return self.entries.get(eid)

    def person_of(self, device):
        d = self.run.devices.get(device) if self.run else None
        return d['person'] if d else None

    def ts(self, eid):
        e = self.entries.get(eid)
        return e['hlc'][0] // 1000 if e else None

    def status_of(self, eid):
        """(status, decision entry or None, note) of an entry written for a submission."""
        run = self.run
        if eid in run.ignored or eid in self.chain_ignored:
            return 'rejected', None, 'not counted: ' + (run.ignored.get(eid) or self.chain_ignored[eid])
        if eid in run.proposals:
            d = run.decisions.get(eid)
            return run.proposals[eid], d and d['by'], d['note'] if d else ''
        return 'approved', None, 'applied directly'

    def get(self, entity, key):
        return self.run._get(entity, tuple(key) if entity == 'link' else key)

    def manager_owned(self, entity, key, field=None):
        if entity == 'equipment':
            return self.run.eq_by.get((key, field), (False, None))[0]
        if entity == 'review':
            return self.run.review_by.get(key, (False, None))[0]
        return False

    # ---------- conflicts (as the old server showed them) ----------
    def plan(self, type_, body):
        """-> (targets [(entity, key)], conflicts [{field, base, live, proposed, manager}]) against the live state."""
        if type_ == 'equipment':
            cur = self.run.equipment.get(body['kks'], {})
            out = []
            for f, v in body['changes'].items():
                live, base = cur.get(f, default(f)), body['base'].get(f, default(f))
                if live != v and live != base:
                    out.append({'field': f, 'base': base, 'live': live, 'proposed': v,
                                'manager': self.manager_owned('equipment', body['kks'], f)})
            return [('equipment', body['kks'])], out
        if type_ == 'review':
            live = self.run.reviews.get(body['tag_id'])
            out = [] if live in (body['base'], body['data']) else \
                [{'field': 'review', 'base': body['base'], 'live': live, 'proposed': body['data'],
                  'manager': self.manager_owned('review', body['tag_id'])}]
            return [('review', body['tag_id'])], out
        if type_ == 'link':
            return [('link', (body['proc'], body['step'], body['kks']))], []
        if type_ in ('photo', 'photo_delete'):
            return [('photo', body['photo'])], []
        return [('added_tag', body['tag'])], []

    # ---------- entry that puts an entity back to a value (revert / restore) ----------
    def restore_body(self, entity, key, value):
        """(type, body) setting entity `key` to `value` (internal replay form; None = absent), or None if equal."""
        cur = self.get(entity, key)
        if cur == value:
            return None
        if entity == 'equipment':
            cur, value = cur or {}, value or {}
            fields = sorted(set(cur) | set(value))
            changes = {f: value.get(f, default(f)) for f in fields if value.get(f, default(f)) != cur.get(f, default(f))}
            return 'equipment', {'kks': key, 'changes': changes, 'base': {f: cur.get(f, default(f)) for f in changes}}
        if entity == 'review':
            return 'review', {'tag_id': key, 'data': value, 'base': cur}
        if entity == 'link':
            proc, step, kks = key
            return 'link', {'proc': proc, 'step': step, 'kks': kks, 'on': bool(value)}
        if entity == 'photo':
            return ('photo_delete', {'photo': key}) if value is None else ('photo', {'photo': key, **value})
        return ('tag_remove', {'tag': key}) if value is None else ('tag_add', {'tag': key, **value})


# ---------- API shapes (what the web UI has always used) ↔ entry bodies ----------
def tag_out(tid, t):
    bb = [v / 10 for v in t['bbox']]
    return {'id': tid, 'sheet': t['sheet'], 'bbox': bb, 'kks': t['kks'], 'suffix': t['suffix'], 'isa': t['isa'],
            'kind': 'instrument' if t['isa'] else 'equipment',
            'orient': 'v' if bb[3] - bb[1] > bb[2] - bb[0] else 'h', 'note': t['note']}


def payload_to_body(kind, p):
    """Validated client payload (server/changes.normalize) → entry body."""
    if kind == 'photo':
        return {'photo': p['photo_id'], 'kks': p['kks'], 'blob': p['blob'], 'caption': p['caption']}
    if kind == 'photo_delete':
        return {'photo': p['photo_id']}
    if kind == 'tag_add':
        return {'tag': p['id'], 'sheet': p['sheet'], 'bbox': [int(round(v * 10)) for v in p['bbox']],
                'kks': p['kks'], 'suffix': p['suffix'], 'isa': p['isa'], 'note': p['note']}
    if kind == 'tag_remove':
        return {'tag': p['id']}
    return dict(p)


def body_to_payload(engine, kind, b):
    if kind == 'photo':
        return {'photo_id': b['photo'], 'kks': b['kks'], 'file': engine.blob_files.get(b['blob']), 'caption': b['caption']}
    if kind == 'photo_delete':
        return {'photo_id': b['photo']}
    if kind == 'tag_add':
        return tag_out(b['tag'], b)
    if kind == 'tag_remove':
        return {'id': b['tag']}
    return dict(b)


def value_out(engine, entity, key, v):
    """Internal replay value → the shape History has always shown."""
    if v is None:
        return None
    if entity == 'photo':
        return {'kks': v['kks'], 'file': engine.blob_files.get(v['blob']), 'caption': v['caption']}
    if entity == 'added_tag':
        out = tag_out(key, v)
        del out['id']
        return out
    return v
