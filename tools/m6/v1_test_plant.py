#!/usr/bin/env python3
"""A small v1 plant for testing the move of v1 devices (PROTOCOL-v2 §21a; platform/linux/tests/test_migrate.nim).

  python3 tools/m6/v1_test_plant.py make OUTDIR
      OUTDIR/v1/plant.db, photos/, root.key: a v1 plant made with the v1 server code (accounts boss and tom, password
      "a long password"; tom's phone, an approved proposal, a removed device of ann);
      OUTDIR/phone.json: the phone's v1 seed and what a bridge would hand over: entries the phone wrote after the
      plant's last sync (a photo proposal with a request note), never seen by the server.
  python3 tools/m6/v1_test_plant.py proof --seed HEX --v1-root R --v2-root R2 --device D --key K --label L
      prints the §21a migration proof signed by that v1 device key."""
import argparse, base64, hashlib, json, os, secrets, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, ROOT)
from peer import proto as P
from server import auth
from server import config as config_mod
from server.engine import Engine
from server.store import Store


def make(out):
    d = os.path.join(out, 'v1')
    os.makedirs(os.path.join(d, 'photos'), exist_ok=True)
    cfg = dict(config_mod.load(os.path.join(out, 'none.json')), db=os.path.join(d, 'plant.db'),
               photos_dir=os.path.join(d, 'photos'), backup_dir=os.path.join(d, 'backups'), root_key=os.path.join(d, 'root.key'))
    store = Store(cfg)
    E = Engine(store, cfg)
    boss, tom, ann = secrets.token_hex(16), secrets.token_hex(16), secrets.token_hex(16)
    with E.tx() as c:
        mdev = E.genesis(c, boss, 'boss', 'Boss Person', None, 'Test plant')
    with E.tx():
        store.put('users', {'username': 'boss', 'pw': auth.hash_password('a long password'), 'role': 'manager', 'active': 1,
                            'created': 0, 'full_name': 'Boss Person', 'position': None, 'person': boss, 'device': mdev})
    with E.tx() as c:
        for pid, name, full in ((tom, 'tom', 'Tom Teammate'), (ann, 'ann', 'Ann Teammate')):
            E.append(c, mdev, 'person', {'person': pid, 'username': name, 'full_name': full, 'position': None, 'role': 'user'})
        phone = E.new_device(c, tom)          # tom's phone: its key signs here only to build the test log
        E.append(c, mdev, 'device_cert', {'device': phone, 'person': tom, 'label': 'Tom phone'})
        lost = E.new_device(c, ann)
        E.append(c, mdev, 'device_cert', {'device': lost, 'person': ann, 'label': 'Ann old phone'})
        E.append(c, mdev, 'revoke', {'device': lost, 'last_seq': 0})
        # tom's account (the emulator rehearsal joins a real phone with it; this server's key for him = `phone`)
        store.put('users', {'username': 'tom', 'pw': auth.hash_password('a long password'), 'role': 'user', 'active': 1,
                            'created': 0, 'full_name': 'Tom Teammate', 'position': None, 'person': tom, 'device': phone})
        prop = E.append(c, phone, 'link', {'proc': '3.6.1', 'step': 2, 'kks': '11LAB70AA501', 'on': True})
        E.append(c, mdev, 'approve', {'entry': prop, 'edit': None})
        E.append(c, mdev, 'equipment', {'kks': '11LAB70AA501', 'changes': {'notes': 'checked'}, 'base': {}})
    # what the phone wrote after its last sync with the v1 server: a photo with a note for the approver
    seed = store.conn().execute('SELECT seed FROM custodial WHERE device=?', (phone,)).fetchone()['seed']
    key = P.key_from_seed(bytes.fromhex(seed))
    last = store.conn().execute('SELECT id, seq FROM entries WHERE peer=? ORDER BY seq DESC LIMIT 1', (phone,)).fetchone()
    photo = b'\xff\x0a' + secrets.token_bytes(200)          # a JPEG XL codestream signature; content does not matter here
    sha = hashlib.sha256(photo).hexdigest()
    now = int(time.time() * 1000)
    e1 = P.make_entry(key, last['seq'] + 1, last['id'], [now, 0], 'photo',
                      {'photo': secrets.token_hex(16), 'kks': '11LAB70AA501', 'blob': sha, 'caption': 'Pump nameplate — ü'})
    e2 = P.make_entry(key, last['seq'] + 2, P.entry_id(e1), [now, 1], 'comment', {'entry': P.entry_id(e1), 'text': 'Taken today'})
    with open(os.path.join(out, 'phone.json'), 'w', encoding='utf-8') as f:
        json.dump({'seed': seed, 'v1_device': phone, 'person': tom, 'lost': lost, 'v1_root': E.current_root(),
                   'handover': [{'v1': P.entry_id(e1), 'type': 'photo', 'body': e1['body'], 'note': 'Taken today'}],
                   'entries': [e1, e2], 'blobs': {sha: base64.b64encode(photo).decode()}}, f, ensure_ascii=False)
    print(json.dumps({'v1_root': E.current_root(), 'phone': phone, 'person': tom}))


def proof(a):
    key = P.key_from_seed(bytes.fromhex(a.seed))
    p = {'kks_migrate': 1, 'v1_root': a.v1_root, 'v1_device': P.peer_id(key), 'v2_root': a.v2_root, 'device': a.device,
         'key': a.key, 'label': a.label, 'created': int(time.time())}
    p['sig'] = P.b64u(key.sign(b'kks-migrate-v1\n' + P.canonical(p)))
    print(json.dumps(p, ensure_ascii=False))


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    m = sub.add_parser('make')
    m.add_argument('out')
    p = sub.add_parser('proof')
    for k in ('seed', 'v1-root', 'v2-root', 'device', 'key', 'label'):
        p.add_argument('--' + k, required=True)
    a = ap.parse_args()
    make(a.out) if a.cmd == 'make' else proof(a)


if __name__ == '__main__':
    main()
