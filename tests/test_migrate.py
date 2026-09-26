"""Moving a pre-log database onto the signed log (server/migrate_v1.py).

tests/fixtures/v1 was written by the old server code itself (tools/make_v1_fixture.py runs commit 2d5fbdc), so this
checks the migration against what the old code really stored, not against assumptions about it."""
import glob, json, os, shutil, sys, tempfile, threading, unittest
from http.server import ThreadingHTTPServer

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import app
from server import config as config_mod
from server.store import Store
from server.auth import Auth
from server.engine import Engine
from tests.test_server import Client

FIX = os.path.join(ROOT, 'tests', 'fixtures', 'v1')


class Migrate(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        os.makedirs(os.path.join(self.tmp, 'data'))
        for n in ('tags.json', 'sheets.json'):
            with open(os.path.join(self.tmp, 'data', n), 'w') as f:
                f.write('[]')
        shutil.copy(os.path.join(FIX, 'plant.db'), os.path.join(self.tmp, 'plant.db'))
        shutil.copytree(os.path.join(FIX, 'photos'), os.path.join(self.tmp, 'photos'))
        cfgp = os.path.join(self.tmp, 'config.json')
        with open(cfgp, 'w') as f:
            json.dump({'port': 0, 'data_dir': 'data', 'db': 'plant.db', 'photos_dir': 'photos', 'backup_dir': 'backups'}, f)
        self.cfg = config_mod.load(cfgp)
        self.store = Store(self.cfg)
        self.auth = Auth(self.store, self.cfg)
        self.E = Engine(self.store, self.cfg)          # migrates
        self.httpd = ThreadingHTTPServer(('127.0.0.1', 0), app.make_handler(self.cfg, self.store, self.auth, self.E))
        self.cfg['port'] = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown(); self.httpd.server_close()
        shutil.rmtree(self.tmp)

    def login(self, name, pw):
        c = Client(self.cfg['port'])
        s, r = c.post('/api/login', {'username': name, 'password': pw})
        self.assertEqual(s, 200, r)
        return c

    def test_everything_carries_over(self):
        E = self.E
        self.assertEqual(E.run.ignored, {})
        self.assertTrue(os.path.exists(E.root_path))
        self.assertEqual(len(glob.glob(os.path.join(self.cfg['backup_dir'], 'plant-v1-*.db'))), 1)
        m = self.login('boss', 'correct horse')             # passwords unchanged
        st = m.get('/api/state')[1]
        self.assertEqual(st['equipment'], {'11LAB70AA501': {'floor': '14 m', 'notes': 'm'},
                                           '11LBA10AA402': {'custom': [{'k': 'Size', 'v': 'DN50'}], 'loc': 'pump house'}})
        self.assertEqual(sorted(l['step'] for l in st['links']), [1, 3])
        self.assertEqual(st['reviews']['lp:7'], {'status': 'rejected'})
        self.assertEqual(sorted((t['sheet'], t['kks'], t['bbox'][0]) for t in st['added_tags']),
                         [('hp', '11LAB90CP501', 100.5), ('lp', None, 10.0)])
        ph, = st['photos']
        self.assertEqual((ph['id'], ph['caption']), ('ff6bb8550e6e47e2a602a8376aa62a11', 'from the stairs'))
        self.assertEqual(m.get('/photos/' + ph['file'])[0], 200)
        # submissions: same numbers, same outcomes
        subs = {s['id']: s for s in m.get('/api/submissions?status=all&limit=100')[1]['submissions']}
        self.assertEqual(sorted(subs), list(range(1, 23)))
        want = {2: 'approved', 4: 'approved', 12: 'approved', 13: 'approved', 14: 'rejected', 15: 'pending',
                16: 'withdrawn', 17: 'rejected', 18: 'approved', 20: 'pending', 22: 'conflict'}
        self.assertEqual({i: subs[i]['status'] for i in want}, want)
        self.assertEqual(subs[17]['note'], 'not this one')
        self.assertEqual(subs[15]['votes'], 1)
        self.assertEqual(subs[18]['payload']['kks'], '11LAB90CP501')
        # History keeps who did what and when; u1's change shows the admin who approved it
        revs = m.get('/api/revisions')[1]['revisions']
        self.assertEqual(len([r for r in revs if r['entity'] in ('equipment', 'review', 'link', 'photo', 'added_tag')]), 16)  # = old data revisions
        first = min((r for r in revs if r['submission_id'] == 2), key=lambda r: r['rev'])
        self.assertEqual(first['username'], 'adm')
        self.assertTrue(any(r['note'] == 'forced over conflicting change' for r in revs))
        # the deactivated account stays out; its key is revoked in the log
        self.assertEqual(Client(self.cfg['port']).post('/api/login', {'username': 'gone', 'password': 'gone password!'})[0], 401)
        gone = next(r for r in E.store.conn().execute("SELECT * FROM users WHERE username='gone'"))
        self.assertIn(gone['device'], E.run.cuts)

    def test_work_continues_after_migration(self):
        u2 = self.login('u2', 'u2 password!')
        dup = u2.post('/api/submit', {'kind': 'equipment', 'client_id': 'fixture-000002',
                                      'payload': {'kks': '11LBA10AA402', 'changes': {'near': 'tank'}, 'base': {}}})[1]
        self.assertEqual((dup['id'], dup['duplicate']), (20, True))   # an offline phone replaying its queue
        m = self.login('boss', 'correct horse')
        self.assertEqual(m.post('/api/submissions/20/approve')[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment']['11LBA10AA402']['near'], 'tank')
        self.assertEqual(m.post('/api/submissions/22/approve')[0], 409)             # the held admin change: still a conflict
        self.assertEqual(m.post('/api/submissions/22/approve', {'force': True})[0], 200)
        self.assertEqual(m.get('/api/state')[1]['equipment']['11LAB70AA501']['notes'], 'stale')
        self.assertEqual(m.post('/api/submissions/15/pick')[0], 200)
        self.assertEqual(len(m.get('/api/state')[1]['photos']), 2)
        # a second start does not migrate again, and replays to the same state
        E2 = Engine(self.store, self.cfg)
        self.assertEqual(E2.run.state(), self.E.run.state())

    def test_mismatch_aborts_and_changes_nothing(self):
        # a live table that doesn't match its own history (hand-edited DB): migration must refuse, not guess
        tmp = tempfile.mkdtemp()
        try:
            shutil.copy(os.path.join(FIX, 'plant.db'), os.path.join(tmp, 'plant.db'))
            shutil.copytree(os.path.join(FIX, 'photos'), os.path.join(tmp, 'photos'))
            import sqlite3
            c = sqlite3.connect(os.path.join(tmp, 'plant.db'))
            c.execute("UPDATE equipment SET data='{\"floor\": \"99 m\"}' WHERE kks='11LAB70AA501'"); c.commit(); c.close()
            cfg = dict(self.cfg, db=os.path.join(tmp, 'plant.db'), photos_dir=os.path.join(tmp, 'photos'),
                       backup_dir=os.path.join(tmp, 'backups'))
            st = Store(cfg)
            with self.assertRaises(SystemExit) as cm:
                Engine(st, cfg)
            self.assertIn('equipment differs', str(cm.exception))
            c = st.conn()
            self.assertEqual(c.execute('SELECT COUNT(*) FROM entries').fetchone()[0], 0)
            self.assertEqual(c.execute('SELECT COUNT(*) FROM submissions').fetchone()[0], 22)
            c.close()
            self.assertFalse(os.path.exists(os.path.join(tmp, 'root.key')))
        finally:
            shutil.rmtree(tmp)


if __name__ == '__main__':
    unittest.main()
