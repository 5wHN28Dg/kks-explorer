"""M5b: plant data (drawings, tag lists, ...) published by the manager as versions in the log and delivered by sync or
bundle (PROTOCOL.md §19). Real HTTP servers + real sync between separate databases."""
import gzip, json, os, sys, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import app
from server import plantdata
from tests import test_peer

PNG1 = b'\x89PNG\r\n\x1a\n' + b'one' * 100
PNG2 = b'\x89PNG\r\n\x1a\n' + b'two' * 100
PNG3 = b'\x89PNG\r\n\x1a\n' + b'three' * 100


def folder(path, png, sheets=None):
    os.makedirs(os.path.join(path, 'sheets'), exist_ok=True)
    with open(os.path.join(path, 'sheets.json'), 'w') as f:
        json.dump(sheets or [{'id': 's1', 'name': 'Sheet one', 'file': 'data/sheets/s1.png', 'vector': 'data/sheets/s1.svg'}], f)
    with open(os.path.join(path, 'tags.json'), 'w') as f:
        json.dump([{'id': 's1:1', 'sheet': 's1', 'kks': '11LAB70AA501'}], f)
    with open(os.path.join(path, 'sheets', 's1.png'), 'wb') as f:
        f.write(png)
    with open(os.path.join(path, 'sheets', 's1.svg.gz'), 'wb') as f:
        f.write(gzip.compress(b'<svg xmlns="http://www.w3.org/2000/svg"/>'))
    return path


class PlantDataTest(unittest.TestCase):
    site, server_with_users = test_peer.PeerTest.site, test_peer.PeerTest.server_with_users

    def setUp(self):
        test_peer.PeerTest.setUp(self)

    def tearDown(self):
        os.environ.pop('KKS_CONFIG', None)
        test_peer.PeerTest.tearDown(self)

    def publish(self, site, src=None):
        """The CLI, as the manager runs it on the server."""
        os.environ['KKS_CONFIG'] = os.path.join(os.path.dirname(site.cfg['db']), 'config.json')
        app.main(['publish-data'] + (['--from', src] if src else []))   # (another Engine on the same database)

    def test_publish_serve_sync_and_versions(self):
        srv, m, u = self.server_with_users()
        self.assertEqual(m.get('/data/sheets.json')[1], [])                   # before: the program's data/ (legacy)
        self.assertIsNone(m.get('/api/sync/status')[1]['plant_data']['version'])
        self.publish(srv, folder(os.path.join(self.tmp, 'src1'), PNG1))
        st = m.get('/api/sync/status')[1]['plant_data']
        self.assertEqual((st['version'], st['active'], st['files'], st['missing']), (1, 1, 4, 0))
        self.assertEqual(m.get('/data/sheets.json')[1][0]['id'], 's1')        # now from the published version
        s, png = m.req('GET', '/data/sheets/s1.png')
        self.assertEqual((s, png), (200, PNG1))
        self.assertEqual(m.req('GET', '/data/sheets/s1.svg')[0], 200)         # stored gzipped, served as .svg
        self.assertEqual(m.req('GET', '/data/nothing.json')[0], 404)
        self.publish(srv)                                                     # same files: no new version
        self.assertEqual(m.get('/api/sync/status')[1]['plant_data']['version'], 1)

        # a laptop joins and gets the drawings by sync
        lap = self.site('lap', 'peer')
        self.assertEqual(lap.client().post('/api/node/join-server', {'url': srv.url, 'username': 'usr', 'password': 'usr password!'})[0], 200)
        c = lap.client()
        self.assertEqual(c.get('/api/sync/status')[1]['plant_data']['active'], 1)
        self.assertEqual(c.req('GET', '/data/sheets/s1.png'), (200, PNG1))

        # version 2: the entry arrives without its files first -> the laptop keeps serving version 1, whole
        self.publish(srv, folder(os.path.join(self.tmp, 'src2'), PNG2))
        srv.E.refresh()
        lap.E.ingest(srv.E.entries_for(lap.E.vv()))
        st = c.get('/api/sync/status')[1]['plant_data']
        self.assertEqual((st['version'], st['active'], st['missing'], st['missing_bytes']), (2, 1, 1, len(PNG2)))
        self.assertEqual(c.req('GET', '/data/sheets/s1.png'), (200, PNG1))
        lap.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])
        self.assertEqual(c.get('/api/sync/status')[1]['plant_data']['active'], 2)
        self.assertEqual(c.req('GET', '/data/sheets/s1.png'), (200, PNG2))
        # the CLI writes while the server runs, and the next thing is a sync (no web request in between): the sync
        # listener picks the new version up itself (it once offered its stale view until some page asked)
        self.publish(srv, folder(os.path.join(self.tmp, 'src3'), PNG3))   # (files the server's memory never saw)
        lap.svc.sync_one('127.0.0.1', srv.cfg['sync_port'])
        self.assertEqual((c.get('/api/sync/status')[1]['plant_data']['active']), 3)

        # only the manager publishes (the laptop belongs to a user)
        with self.assertRaises(SystemExit):
            self.publish(lap, os.path.join(self.tmp, 'src1'))

        # a bundle carries the plant data (a device joining by file needs the drawings)
        s, raw = m.req('GET', '/api/bundle')
        self.assertEqual(s, 200)
        other = self.site('other', 'peer')
        got = other.E.import_bundle(raw)
        self.assertTrue(got['adopted'])
        self.assertEqual(plantdata.status(other.E)['active'], 3)
        with open(plantdata.file_for(other.E, other.cfg, 'sheets/s1.png'), 'rb') as f:
            self.assertEqual(f.read(), PNG3)

    def test_first_import_keeps_the_legacy_sheets(self):
        """A pre-M5b server kept its drawings in data/: the working folder starts from them, so the first publish
        carries every existing sheet instead of an empty plant."""
        srv, m, u = self.server_with_users()
        folder(srv.cfg['data_dir'], PNG1)
        plantdata.ensure_working(srv.E, srv.cfg)
        self.assertEqual(sorted(p for p, _ in plantdata.scan(srv.cfg['plant_dir'])),
                         ['sheets.json', 'sheets/s1.png', 'sheets/s1.svg.gz', 'tags.json'])
        self.publish(srv)
        self.assertEqual(m.req('GET', '/data/sheets/s1.png'), (200, PNG1))

    def test_bad_manifests_are_ignored(self):
        for v in (None, [], {'version': 0, 'files': []}, {'version': 1, 'files': [['../x', 'a' * 64, 1]]},
                  {'version': 1, 'files': [['a.json', 'A' * 64, 1]]}, {'version': 1, 'files': [['a.json', 'a' * 64, -1]]},
                  {'version': 1, 'files': [['a.json', 'a' * 64, 1], ['a.json', 'b' * 64, 1]]}, {'version': True, 'files': []}):
            self.assertIsNone(plantdata.manifest(v), v)
        self.assertEqual(plantdata.manifest({'version': 3, 'files': [['sheets/x.png', 'a' * 64, 5]]}),
                         {'version': 3, 'files': {'sheets/x.png': ('a' * 64, 5)}})


if __name__ == '__main__':
    unittest.main()
