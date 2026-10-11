"""For the server's tests: a person who joined with the app. They have a device of their own (a key made here with
the Python reference, ref/), certified by an admin from its join request as "Add a computer from a join request"
does, and no account on the server. What the device writes reaches the server as a bundle file (Import a bundle),
so no sync connection is needed. Needs the `cryptography` package (.venv, requirements-dev.txt)."""
import gzip, json, os, sys, time

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..')))
from ref import crypto2, proto2   # noqa: E402


class AppPerson:
    def __init__(self, admin, username, full_name, position='Technician', label='phone'):
        """`admin(method, path, body=None, raw=None, headers=None) -> (status, body)`: an admin's signed-in client"""
        self.admin, self.username = admin, username
        self.key = proto2.key_from_seed(os.urandom(32))
        self.device = proto2.peer_id(self.key)
        self.log = proto2.Log(self.key)
        st, r = admin('POST', '/api/devices/import-request',
                      {'request': crypto2.join_request(self.key, username, full_name, position, label, int(time.time()))})
        assert st == 200, (st, r)
        self.person = r['person']

    def write(self, type_, body):
        """one entry by the device, a moment after the server's clock (it must come after its certificate, §10)"""
        e = self.log.append(type_, body, int(time.time() * 1000) + 2000)
        st, raw = self.admin('GET', '/api/bundle')
        assert st == 200, st
        root = json.loads(gzip.decompress(raw))['root']
        bundle = gzip.compress(json.dumps({'kks_bundle': 2, 'root': root, 'plant': None, 'created': int(time.time()),
                                           'entries': [e], 'blobs': {}}).encode())
        st, r = self.admin('POST', '/api/bundle/import', raw=bundle, headers={'Content-Type': 'application/gzip'})
        assert st == 200 and r['entries'] == 1, (st, r)
        return e

    def note(self, kks, text):
        """a proposal as the app's "Place and notes" makes it"""
        return self.write('equipment', {'kks': kks, 'changes': {'notes': text}, 'base': {}})
