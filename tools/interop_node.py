#!/usr/bin/env python3
"""A real Python node (server/engine.py) for cross-implementation tests (android/core: InteropTest). It makes a
plant in a temporary folder, certifies the device whose Ed25519 seed it is given, adds a link and a photo, listens
for sync on 127.0.0.1, and then obeys one command per line on stdin, answering one JSON line on stdout:
  state                  the replay state (state bytes, as text)
  sync PORT              connect to 127.0.0.1:PORT and sync (this side initiates)
  approve ENTRY_ID       the manager approves a proposal
  has_blob SHA           whether a photo blob arrived
  quit
  .venv/bin/python tools/interop_node.py --device-seed HEX"""
import argparse, hashlib, json, os, secrets, shutil, sys, tempfile, threading
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from peer import proto as P, replay as R, sync as S
from server import config as config_mod
from server.engine import Engine
from server.store import Store
from server.syncsvc import SyncService


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--device-seed', required=True)
    a = ap.parse_args()
    tmp = tempfile.mkdtemp(prefix='kks-interop-')
    try:
        cfg = dict(config_mod.load(os.path.join(tmp, 'none.json')), db=os.path.join(tmp, 'plant.db'),
                   photos_dir=os.path.join(tmp, 'photos'), backup_dir=os.path.join(tmp, 'backups'),
                   root_key=os.path.join(tmp, 'root.key'), discovery=False)
        os.makedirs(cfg['photos_dir'])
        E = Engine(Store(cfg), cfg)
        M, K = secrets.token_hex(16), secrets.token_hex(16)
        kdev = P.peer_id(P.key_from_seed(bytes.fromhex(a.device_seed)))
        with E.tx() as c:
            mdev = E.genesis(c, M, 'boss', 'Boss Person', None, 'Interop plant')
            E.store.put('users', {'username': 'boss', 'pw': None, 'role': 'manager', 'active': 1, 'created': 0,
                                  'full_name': 'Boss Person', 'position': None, 'person': M, 'device': mdev})
        data = b'\xff\xd8\xff\xe0' + os.urandom(2000)
        sha = hashlib.sha256(data).hexdigest()
        with open(os.path.join(cfg['photos_dir'], sha + '.jpg'), 'wb') as f:
            f.write(data)
        with E.tx() as c:
            E.append(c, mdev, 'person', {'person': K, 'username': 'kotlin', 'full_name': 'Kotlin Device', 'position': 'ÜML ☃', 'role': 'user'})
            E.append(c, mdev, 'device_cert', {'device': kdev, 'person': K, 'label': 'phone'})
            E.append(c, mdev, 'link', {'proc': '3.6.1', 'step': 1, 'kks': '11LAB70AA501', 'on': True})
            E.append(c, mdev, 'equipment', {'kks': '11LAB70AA501', 'changes': {'notes': 'Ünïcode ☃ 😀', 'custom': [{'k': 'Size', 'v': 'DN50'}]}, 'base': {}})
            E.store.put('blobs', {'sha': sha, 'file': sha + '.jpg', 'size': len(data)})
            E.blob_files[sha] = sha + '.jpg'
            E.append(c, mdev, 'photo', {'photo': secrets.token_hex(16), 'kks': '11LAB70AA501', 'blob': sha, 'caption': 'valve'})
        svc = SyncService(E, cfg, log=lambda *x: None)
        port = svc.listen('127.0.0.1', 0)
        print(json.dumps({'port': port, 'root': E.anchor, 'person': K, 'photo_sha': sha}), flush=True)
        for line in sys.stdin:
            cmd = line.split()
            if not cmd:
                continue
            try:
                if cmd[0] == 'state':
                    with E.lock:
                        st = E.run.state()
                        st['ignored'] = dict(sorted({**E.chain_ignored, **E.run.ignored}.items()))
                        out = {'state': R.state_bytes(st).decode()}
                elif cmd[0] == 'sync':
                    remote, stats = S.sync_with(E, '127.0.0.1', int(cmd[1]))
                    out = {'remote': remote, **stats}
                elif cmd[0] == 'approve':
                    with E.tx() as c:
                        E.append(c, mdev, 'approve', {'entry': cmd[1], 'edit': None})
                    out = {'ok': True}
                elif cmd[0] == 'has_blob':
                    out = {'has': E.blob_get(cmd[1]) is not None}
                elif cmd[0] == 'quit':
                    break
                else:
                    out = {'error': 'unknown command'}
            except Exception as e:
                out = {'error': f'{type(e).__name__}: {e}'}
            print(json.dumps(out), flush=True)
        svc.srv.close()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    main()
