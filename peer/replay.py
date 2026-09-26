"""KKS Explorer sync protocol v1: replay (spec: docs/PROTOCOL.md §8–14).

replay(entries, root) -> state. Identity, authority, revocation, approvals, merge, private entries.
Deterministic: given the same entries in any order and the same trust anchor, every implementation must produce the
same canonical bytes (peer/vectors/v2-replay.json)."""
import json, os, re

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305

from peer import proto as P

STMT_DOMAIN = b'kks-root-v1\n'
PRIVATE_DOMAIN = b'kks-private-v1\n'
MAX_ROUNDS = 8

ID_RE = re.compile(r'^[0-9a-f]{32}$')
HEX64_RE = re.compile(r'^[0-9a-f]{64}$')
PEER_RE = re.compile(r'^[A-Za-z0-9_-]{43}$')
B64U_RE = re.compile(r'^[A-Za-z0-9_-]*$')
USER_RE = re.compile(r'^[A-Za-z0-9_.@-]{2,40}$')
KKS_RE = re.compile(r'^[0-9A-Z/]{3,24}$')
CODE_RE = re.compile(r'^[0-9]{2}[A-Z]{3}[0-9]{2}[A-Z]{2}[0-9]{3}$')
SUFFIX_RE = re.compile(r'^[A-Z0-9]{0,4}$')
ISA_RE = re.compile(r'^[A-Z]{1,6}$')
SHEET_RE = re.compile(r'^[a-z0-9][a-z0-9-]{0,23}$')
TAGID_RE = re.compile(r'^[A-Za-z0-9:_.-]{1,64}$')
STATE_KEY_RE = re.compile(r'^[\x20-\x7e]{1,64}$')

EQ_FIELDS = ('area', 'floor', 'elev', 'near', 'loc', 'notes', 'custom')
BODY = {
    'genesis': ('plant', 'root', 'manager', 'stmt_manager', 'stmt_device', 'sig_manager', 'sig_device'),
    'root': ('stmt', 'root_sig'),
    'person': ('person', 'username', 'full_name', 'position', 'role'),
    'device_cert': ('device', 'person', 'label'),
    'revoke': ('device', 'last_seq'),
    'setting': ('key', 'value'),
    'equipment': ('kks', 'changes', 'base'),
    'review': ('tag_id', 'data', 'base'),
    'link': ('proc', 'step', 'kks', 'on'),
    'photo': ('photo', 'kks', 'blob', 'caption'),
    'photo_delete': ('photo',),
    'tag_add': ('tag', 'sheet', 'bbox', 'kks', 'suffix', 'isa', 'note'),
    'tag_remove': ('tag',),
    'approve': ('entry', 'edit'),
    'reject': ('entry', 'note'),
    'withdraw': ('entry',),
    'vote': ('entry', 'on'),
    'private': ('person', 'nonce', 'ct'),
}
STMT = {'manager': ('kind', 'person'), 'device': ('kind', 'device', 'person'), 'rotate': ('kind', 'root'),
        'revoke': ('kind', 'device', 'last_seq')}
RANK = {'root': 0, 'manager': 1, 'admin': 2, 'user': 3}   # revocation priority (§10)


class Ignore(Exception):
    """A valid entry that changes nothing. str(self) is the reason code reported in state['ignored'] (§11)."""


def _need(cond, code='bad_body'):
    if not cond:
        raise Ignore(code)


def _text(v, lo=0, hi=4000):
    """A string of lo..hi Unicode code points."""
    return isinstance(v, str) and lo <= len(v) <= hi


def _match(regex, v):
    return isinstance(v, str) and regex.match(v) is not None


def _keys(obj, keys):
    _need(isinstance(obj, dict) and set(obj) == set(keys))


# ---------- §8 root statements ----------
def sign_statement(root_key, stmt):
    return P.b64u(root_key.sign(STMT_DOMAIN + P.canonical(stmt)))


def check_statement(root_pub, stmt, sig):
    _need(isinstance(stmt, dict) and stmt.get('kind') in STMT)
    _keys(stmt, STMT[stmt['kind']])
    _need(_match(B64U_RE, sig))
    try:
        Ed25519PublicKey.from_public_bytes(P.unb64u(root_pub)).verify(P.unb64u(sig), STMT_DOMAIN + P.canonical(stmt))
    except (InvalidSignature, ValueError):
        raise Ignore('bad_root_sig')


# ---------- §13 private entries ----------
def private_body(secret, person, type_, body, nonce=None):
    """Body of a `private` entry: {type, body} encrypted with the 32-byte person secret."""
    nonce = os.urandom(12) if nonce is None else nonce
    ct = ChaCha20Poly1305(secret).encrypt(nonce, P.canonical({'type': type_, 'body': body}), PRIVATE_DOMAIN + person.encode())
    return {'person': person, 'nonce': P.b64u(nonce), 'ct': P.b64u(ct)}


def private_open(secret, body):
    """-> {type, body}. Raises cryptography.exceptions.InvalidTag for a wrong key or tampered data."""
    pt = ChaCha20Poly1305(secret).decrypt(P.unb64u(body['nonce']), P.unb64u(body['ct']), PRIVATE_DOMAIN + body['person'].encode())
    return json.loads(pt)


# ---------- §4 chains, across devices ----------
def _chains(entries, trusted=None):
    """Keep each device's unbroken chain from seq 1. -> (usable entries, {entry id: code}, {device: fork cut}).
    `trusted` = {entry id: entry} already verified when they were stored (a host's own database): not re-checked."""
    ignored, by_peer, forks = {}, {}, {}
    for eid, e in (trusted.items() if trusted is not None else ((None, e) for e in entries)):
        if eid is None:
            try:
                P.verify_entry(e)
                eid = P.entry_id(e)
            except P.ProtocolError as err:
                try:
                    ignored[P.entry_id(e)] = err.code
                except (P.ProtocolError, TypeError, AttributeError):
                    pass   # can't even be hashed: nothing to report it under
                continue
        by_peer.setdefault(e['peer'], {}).setdefault(e['seq'], {})[eid] = e
    usable = []
    for peer, seqs in by_peer.items():
        prev, why = None, None
        for seq in range(1, max(seqs) + 1):
            cands = seqs.get(seq, {})
            if len(cands) > 1:            # fork: cut before it; both sides are only evidence
                forks[peer], why = seq - 1, 'fork'
                break
            if not cands:
                why = 'chain_gap'
                break
            (eid, e), = cands.items()
            if e['prev'] != prev:
                why = 'chain_prev'
                break
            usable.append(e)
            prev = eid
        if why:   # everything from the break on waits (gap, bad link) or is evidence (fork)
            for s, cands in seqs.items():
                for eid in cands:
                    if s >= seq:
                        ignored[eid] = why
    return usable, ignored, forks


# ---------- §10–12 one pass in total order ----------
class _Run:
    def __init__(self, root, cuts, accepted=None, ids=None):
        self.root, self.cuts, self.accepted = root, cuts, accepted
        self._ids = ids or {}   # id(entry) → entry ID, computed once per replay
        self.manager = None
        self.persons, self.devices, self.settings = {}, {}, {}
        self.equipment, self.eq_by, self.reviews, self.review_by = {}, {}, {}, {}
        self.links, self.photos, self.tags = set(), {}, {}
        self.proposals, self.pending, self.waiting, self.votes = {}, {}, {}, {}
        self.conflicts, self.private, self.ignored = [], {}, {}
        self.revokes = []   # (rank, order key, author peer, author seq, entry id, device, last_seq)
        # side output for hosts (not part of the state bytes): who decided what, and every applied change
        self.authors, self.decisions, self.history, self.at = {}, {}, [], None

    def role(self, person):
        if person == self.manager:
            return 'manager'
        return self.persons[person]['role'] if person in self.persons else None

    def run(self, ordered):
        for e in ordered:
            eid = self._ids.get(id(e)) or P.entry_id(e)
            try:
                if e['seq'] > self.cuts.get(e['peer'], P.MAX_INT):
                    raise Ignore('revoked')
                if e['type'] == 'genesis':
                    self.genesis(e)
                    continue
                dev = self.devices.get(e['peer'])
                _need(dev is not None, 'not_certified')
                _need(e['type'] in BODY, 'unknown_type')
                _keys(e['body'], BODY[e['type']])
                self.at = eid
                getattr(self, 't_' + e['type'])(e, eid, dev['person'], self.role(dev['person']))
            except Ignore as why:
                self.ignored[eid] = str(why)
        return self

    def _revoke(self, rank, e, eid, device, last_seq):
        self.revokes.append((rank, P.order_key(e), e['peer'], e['seq'], eid, device, last_seq))
        if self.accepted is not None and eid not in self.accepted:
            raise Ignore('overridden')

    # ----- identity -----
    def _person_fields(self, b):
        _need(_match(ID_RE, b['person']) and _match(USER_RE, b['username']))
        _need(_text(b['full_name'], 2, 80) and (b['position'] is None or _text(b['position'], 0, 80)))

    def genesis(self, e):
        b = e['body']
        _need(self.manager is None, 'second_genesis')
        _keys(b, BODY['genesis'])
        _need(_text(b['plant'], 1, 80))
        _need(b['root'] == self.root, 'bad_genesis')
        m = b['manager']
        _keys(m, ('person', 'username', 'full_name', 'position'))
        self._person_fields(m)
        _need(b['stmt_manager'] == {'kind': 'manager', 'person': m['person']}, 'bad_genesis')
        _need(b['stmt_device'] == {'kind': 'device', 'device': e['peer'], 'person': m['person']}, 'bad_genesis')
        check_statement(self.root, b['stmt_manager'], b['sig_manager'])
        check_statement(self.root, b['stmt_device'], b['sig_device'])
        # stored role 'admin': 'manager' comes from the manager statement, so after a handover they are an admin
        self.persons[m['person']] = {'username': m['username'], 'full_name': m['full_name'],
                                     'position': m['position'], 'role': 'admin'}
        self.manager = m['person']
        self.devices[e['peer']] = {'person': m['person'], 'label': ''}
        self.settings['plant'] = b['plant']

    def t_root(self, e, eid, author, role):   # the root signature is the authority, whoever carries it
        stmt = e['body']['stmt']
        check_statement(self.root, stmt, e['body']['root_sig'])
        kind = stmt['kind']
        if kind == 'manager':
            _need(stmt['person'] in self.persons)
            self.manager = stmt['person']
        elif kind == 'device':
            _need(_match(PEER_RE, stmt['device']) and stmt['person'] in self.persons)
            _need(self.devices.get(stmt['device'], {}).get('person', stmt['person']) == stmt['person'], 'not_allowed')
            self.devices.setdefault(stmt['device'], {'person': stmt['person'], 'label': ''})
        elif kind == 'rotate':
            _need(_match(PEER_RE, stmt['root']))
            self.root = stmt['root']
        else:   # revoke
            _need(_match(PEER_RE, stmt['device']) and type(stmt['last_seq']) is int and stmt['last_seq'] >= 0)
            self._revoke(RANK['root'], e, eid, stmt['device'], stmt['last_seq'])

    def t_person(self, e, eid, author, role):
        b = e['body']
        self._person_fields(b)
        _need(b['role'] in ('user', 'admin'))
        pid, cur = b['person'], self.persons.get(b['person'])
        if cur is None:
            _need(role == 'manager' or (role == 'admin' and b['role'] == 'user'), 'not_allowed')
            _need(all(p['username'].lower() != b['username'].lower() for p in self.persons.values()), 'username_taken')
            self.persons[pid] = {k: b[k] for k in ('username', 'full_name', 'position', 'role')}
            return
        _need(b['username'] == cur['username'])   # usernames never change
        if author == pid:                          # own details; own role can't change
            _need(b['role'] == cur['role'], 'not_allowed')
        else:
            target = self.role(pid)
            _need(target != 'manager', 'not_allowed')
            _need(role == 'manager' or (role == 'admin' and target == 'user' and b['role'] == 'user'), 'not_allowed')
        cur.update(full_name=b['full_name'], position=b['position'], role=b['role'])

    def t_device_cert(self, e, eid, author, role):
        b = e['body']
        _need(_match(PEER_RE, b['device']) and b['person'] in self.persons and _text(b['label'], 0, 80))
        _need(self.devices.get(b['device'], {}).get('person', b['person']) == b['person'], 'not_allowed')
        _need(role == 'manager' or author == b['person'] or (role == 'admin' and self.role(b['person']) == 'user'),
              'not_allowed')
        self.devices[b['device']] = {'person': b['person'], 'label': b['label']}

    def t_revoke(self, e, eid, author, role):
        b = e['body']
        target = self.devices.get(b['device'])
        _need(target is not None and type(b['last_seq']) is int and b['last_seq'] >= 0)
        _need(role == 'manager' or author == target['person'] or (role == 'admin' and self.role(target['person']) == 'user'),
              'not_allowed')
        self._revoke(RANK[role], e, eid, b['device'], b['last_seq'])

    def t_setting(self, e, eid, author, role):
        _need(_match(P.KEY_RE, e['body']['key']))
        _need(role == 'manager', 'not_allowed')
        self.settings[e['body']['key']] = e['body']['value']

    def t_private(self, e, eid, author, role):
        b = e['body']
        _need(_match(B64U_RE, b['nonce']) and len(b['nonce']) == 16)
        _need(_match(B64U_RE, b['ct']) and 22 <= len(b['ct']) <= 1_400_000)
        _need(b['person'] == author, 'not_allowed')
        self.private.setdefault(author, []).append(eid)

    # ----- data: self-approved or proposals -----
    def _data(self, e, eid, author, role):
        _check_data(e['type'], e['body'])
        if role in ('admin', 'manager'):
            self.apply(e['type'], e['body'], eid, role == 'manager')
            return
        self.proposals[eid] = 'pending'
        self.pending[eid] = e
        self.authors[eid] = author
        for d in self.waiting.pop(eid, []):   # decided before it came in the order: takes effect here, first valid wins
            try:
                _need(self.proposals[eid] == 'pending', 'already_decided')
                _need(d['verdict'] != 'withdrawn' or d['person'] == author, 'not_allowed')
                self.decide(eid, d)
            except Ignore as why:
                self.ignored[d['eid']] = str(why)

    t_equipment = t_review = t_link = t_photo = t_photo_delete = t_tag_add = t_tag_remove = _data

    def t_approve(self, e, eid, author, role):
        edit = e['body']['edit']
        if edit is not None:
            _keys(edit, ('kks', 'suffix', 'isa'))
        self._decision(e, eid, {'verdict': 'approved', 'manager': role == 'manager', 'edit': edit, 'note': ''}, role)

    def t_reject(self, e, eid, author, role):
        _need(_text(e['body']['note'], 0, 500))
        self._decision(e, eid, {'verdict': 'rejected', 'manager': role == 'manager', 'edit': None,
                                'note': e['body']['note']}, role)

    def t_withdraw(self, e, eid, author, role):
        self._decision(e, eid, {'verdict': 'withdrawn', 'manager': False, 'edit': None, 'note': '', 'person': author}, None)

    def t_vote(self, e, eid, author, role):
        _need(_match(HEX64_RE, e['body']['entry']) and isinstance(e['body']['on'], bool))
        voters = self.votes.setdefault(e['body']['entry'], set())
        if e['body']['on']:
            voters.add(author)
        else:
            voters.discard(author)

    def _decision(self, e, eid, d, role):
        target = e['body']['entry']
        _need(_match(HEX64_RE, target))
        if d['verdict'] != 'withdrawn':
            _need(role in ('admin', 'manager'), 'not_allowed')
        d['eid'] = eid
        state = self.proposals.get(target)
        if state is None:
            self.waiting.setdefault(target, []).append(d)
            return
        _need(state == 'pending', 'already_decided')
        _need(d['verdict'] != 'withdrawn' or d['person'] == self.authors[target], 'not_allowed')
        self.decide(target, d)

    def decide(self, target, d):
        e = self.pending.pop(target)
        body, verdict = e['body'], d['verdict']
        if d['edit'] is not None:   # only for tag_add, and the edited tag must still be valid; else it counts as rejected
            body = {**body, **d['edit']}
            try:
                _need(e['type'] == 'tag_add')
                _check_data('tag_add', body)
            except Ignore:
                verdict = 'rejected'
        self.proposals[target] = verdict
        self.decisions[target] = {'status': verdict, 'by': d['eid'], 'note': d['note']}
        if verdict == 'approved':
            self.apply(e['type'], body, target, d['manager'])

    # ----- §12 merge -----
    def _merge(self, entity, key, field, live, base, new, owner, by, by_manager):
        """True if the new value applies. Records a conflict when live is neither base nor new."""
        if live == base or live == new:
            return True
        owner_manager, owner_id = owner
        if owner_manager and not by_manager:
            self.conflicts.append({'entity': entity, 'key': key, 'field': field, 'kept': live, 'lost': new,
                                   'kept_by': owner_id, 'lost_by': by})
            return False
        self.conflicts.append({'entity': entity, 'key': key, 'field': field, 'kept': new, 'lost': live,
                               'kept_by': by, 'lost_by': owner_id})
        return True

    def _get(self, entity, key):
        if entity == 'equipment':
            v = self.equipment.get(key)
            return dict(v) if v else None
        if entity == 'review':
            return self.reviews.get(key)
        if entity == 'link':
            return True if key in self.links else None
        if entity == 'photo':
            return self.photos.get(key)
        return self.tags.get(key)

    def apply(self, t, b, by, by_manager):
        entity, key = {'equipment': ('equipment', b.get('kks')), 'review': ('review', b.get('tag_id')),
                       'link': ('link', (b.get('proc'), b.get('step'), b.get('kks'))),
                       'photo': ('photo', b.get('photo')), 'photo_delete': ('photo', b.get('photo')),
                       'tag_add': ('added_tag', b.get('tag')), 'tag_remove': ('added_tag', b.get('tag'))}[t]
        before = self._get(entity, key)
        self._apply(t, b, by, by_manager)
        after = self._get(entity, key)
        if before != after:
            self.history.append({'at': self.at, 'source': by, 'entity': entity,
                                 'key': list(key) if entity == 'link' else key, 'before': before, 'after': after})

    def _apply(self, t, b, by, by_manager):
        if t == 'equipment':
            k = b['kks']
            cur = self.equipment.setdefault(k, {})
            for f in sorted(b['changes']):
                v, empty = b['changes'][f], ([] if f == 'custom' else '')
                if self._merge('equipment', k, f, cur.get(f, empty), b['base'].get(f, empty), v,
                               self.eq_by.get((k, f), (False, None)), by, by_manager):
                    if v == empty:
                        cur.pop(f, None)
                    else:
                        cur[f] = v
                    self.eq_by[(k, f)] = (by_manager, by)
            if not cur:
                del self.equipment[k]
        elif t == 'review':
            k = b['tag_id']
            if self._merge('review', k, None, self.reviews.get(k), b['base'], b['data'],
                           self.review_by.get(k, (False, None)), by, by_manager):
                if b['data'] is None:
                    self.reviews.pop(k, None)
                else:
                    self.reviews[k] = b['data']
                self.review_by[k] = (by_manager, by)
        elif t == 'link':
            item = (b['proc'], b['step'], b['kks'])
            if b['on']:
                self.links.add(item)
            else:
                self.links.discard(item)
        elif t == 'photo':
            self.photos[b['photo']] = {k: b[k] for k in ('kks', 'blob', 'caption')}
        elif t == 'photo_delete':
            self.photos.pop(b['photo'], None)
        elif t == 'tag_add':
            self.tags[b['tag']] = {k: b[k] for k in ('sheet', 'bbox', 'kks', 'suffix', 'isa', 'note')}
        elif t == 'tag_remove':
            self.tags.pop(b['tag'], None)

    def state(self):
        return {
            'root': self.root, 'manager': self.manager, 'settings': self.settings, 'persons': self.persons,
            'devices': {d: {**v, 'cut': self.cuts.get(d)} for d, v in self.devices.items()},
            'equipment': self.equipment, 'reviews': self.reviews,
            'links': [list(x) for x in sorted(self.links)],
            'photos': self.photos, 'added_tags': self.tags,
            'proposals': self.proposals, 'conflicts': self.conflicts,
            'votes': {k: sorted(v) for k, v in self.votes.items() if v and k in self.proposals},
            'private': self.private, 'ignored': self.ignored,
        }


def _check_data(t, b):
    """Body rules for the data types (§9a). Writers normalize; replay only accepts or ignores."""
    if t == 'equipment':
        _need(_match(KKS_RE, b['kks']) and isinstance(b['changes'], dict) and b['changes'] and isinstance(b['base'], dict))
        for d in (b['changes'], b['base']):
            for f, v in d.items():
                _need(f in EQ_FIELDS)
                if f == 'custom':
                    _need(isinstance(v, list) and len(v) <= 100)
                    for x in v:
                        _keys(x, ('k', 'v'))
                        _need(_text(x['k'], 0, 200) and _text(x['v'], 0, 2000))
                else:
                    _need(_text(v))
    elif t == 'review':
        _need(_match(TAGID_RE, b['tag_id']) and (b['data'] is None or isinstance(b['data'], dict)) and (b['base'] is None or isinstance(b['base'], dict)))
    elif t == 'link':
        _need(_text(b['proc'], 1, 32) and type(b['step']) is int and b['step'] >= 0)
        _need(_match(KKS_RE, b['kks']) and isinstance(b['on'], bool))
    elif t == 'photo':
        _need(_match(ID_RE, b['photo']) and _match(HEX64_RE, b['blob']))
        _need(_match(KKS_RE, b['kks']) and _text(b['caption'], 0, 500))
    elif t == 'photo_delete':
        _need(_match(ID_RE, b['photo']))
    elif t == 'tag_remove':
        _need(_match(ID_RE, b['tag']))
    elif t == 'tag_add':
        _need(_match(ID_RE, b['tag']) and _match(SHEET_RE, b['sheet']))
        bb = b['bbox']
        _need(isinstance(bb, list) and len(bb) == 4 and all(type(v) is int for v in bb))
        _need(0 <= bb[0] < bb[2] <= 200000 and 0 <= bb[1] < bb[3] <= 200000)
        _need(b['kks'] is None or _match(CODE_RE, b['kks']))
        _need(_match(SUFFIX_RE, b['suffix']) and (b['isa'] is None or _match(ISA_RE, b['isa'])))
        _need(_text(b['note'], 0, 500))


def _state_keys(v):
    if isinstance(v, dict):
        for k, x in v.items():
            if not STATE_KEY_RE.match(k):
                raise P.ProtocolError('bad_encoding', f'state key {k!r}')
            _state_keys(x)
    elif isinstance(v, list):
        for x in v:
            _state_keys(x)


def state_bytes(state):
    """Canonical bytes of a replay state (§14): §1 rules, except object keys may be any printable ASCII (1–64 chars),
    because the state is keyed by KKS codes, peer IDs and entry IDs. Values all come from valid entries."""
    _state_keys(state)
    return json.dumps(state, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode('utf-8')


# ---------- §10 revocation cuts, then the final pass ----------
def _cuts(ordered, root, forks, ids=None):
    """Rounds: replay with the current cuts and collect the authorized revocations; accept them by priority
    (root statement, manager, admin, user; then total order), skipping one whose own entry is cut by a revocation
    accepted before it. Repeat until nothing changes, at most MAX_ROUNDS."""
    cuts, accepted = dict(forks), set()
    for _ in range(MAX_ROUNDS):
        run = _Run(root, cuts, ids=ids).run(ordered)
        new, acc = dict(forks), set()
        for rank, key, peer, seq, eid, device, last in sorted(run.revokes):
            if seq > new.get(peer, P.MAX_INT):
                continue
            new[device] = min(last, new.get(device, last))
            acc.add(eid)
        if new == cuts and acc == accepted:
            break
        cuts, accepted = new, acc
    return cuts, accepted


def replay_run(entries, root, trusted=None):
    """For hosts: -> (run, ignored by chain checks). The run holds the state plus side output (history, decisions,
    authors) and can take further entries with run.run([...]) as long as they sort after everything replayed and
    change no cuts (no `revoke`, no `root`). `trusted`: see _chains (then `entries` is not used)."""
    usable, chain_ignored, forks = _chains(entries, trusted)
    ids = {id(e): eid for eid, e in trusted.items()} if trusted is not None else {id(e): P.entry_id(e) for e in usable}
    ordered = sorted(usable, key=P.order_key)
    cuts, accepted = _cuts(ordered, root, forks, ids)
    return _Run(root, cuts, accepted, ids).run(ordered), chain_ignored


def replay(entries, root):
    """Replay `entries` (any order, any devices) from the trust anchor `root` (root public key, base64url). -> state."""
    run, chain_ignored = replay_run(entries, root)
    state = run.state()
    state['ignored'] = dict(sorted({**chain_ignored, **run.ignored}.items()))
    return state
