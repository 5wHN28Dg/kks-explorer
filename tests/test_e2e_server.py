"""tests/e2e_server.py, the e2e suites' port picker and server start (issue #155). No server binary, no emulator:
the kernel's choice of ports is faked where the test must not depend on luck, and the "server" is a small script.
  .venv/bin/python -m unittest tests.test_e2e_server"""
import json, os, re, shutil, socket, stat, subprocess, sys, tempfile, unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2e_server  # noqa: E402

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SUITES = ('android/app2/e2e', 'platform/linux/e2e', 'apps/gnome/e2e', 'apps/windows/e2e', 'tests')


class Kernel:
    """a socket layer whose port 0 always gives the port released last, when it is free again: the worst case of
    what Linux does now and then (#155)"""

    def __init__(self):
        self.bound, self.last, self.next, self.open, self.fail_at = set(), None, 40000, 0, None

    def module(self):
        k = self

        class Socket:
            def __init__(self, *a):
                self.port = None
                k.open += 1

            def bind(self, addr):
                if k.fail_at is not None and len(k.bound) >= k.fail_at:
                    raise OSError('no ports left')
                if k.last is not None and k.last not in k.bound:
                    self.port = k.last
                else:
                    k.next += 1
                    self.port = k.next
                k.bound.add(self.port)

            def getsockname(self):
                return ('127.0.0.1', self.port)

            def close(self):
                if self.port in k.bound:
                    k.bound.discard(self.port)
                    k.last = self.port
                k.open -= 1
        return mock.Mock(socket=Socket)


class Ports(unittest.TestCase):
    def setUp(self):
        self.k = Kernel()
        p = mock.patch.object(e2e_server, 'socket', self.k.module())
        p.start()
        self.addCleanup(p.stop)

    def test_one_at_a_time_repeats(self):
        """what the suites did (`free_port(), free_port()`): under this kernel the same port both times"""
        self.assertEqual(e2e_server.free_port(), e2e_server.free_port())

    def test_together_they_differ(self):
        for n in (2, 3, 5):
            for _ in range(200):
                got = e2e_server.free_ports(n)
                self.assertEqual(len(set(got)), n, got)
                self.assertEqual((self.k.open, self.k.bound), (0, set()), 'every socket is closed again')

    def test_closed_when_a_bind_fails(self):
        self.k.fail_at = 1
        with self.assertRaises(OSError):
            e2e_server.free_ports(3)
        self.assertEqual((self.k.open, self.k.bound), (0, set()))


FAKE = r'''#!%s
"""a stand-in for `kks_server serve --config FILE`: what it does comes from the config's "fake" entry"""
import json, os, socket, sys, time
path = sys.argv[3]
cfg = json.load(open(path))
with open(os.path.join(os.path.dirname(path), 'starts'), 'a') as f:
    f.write('%%d %%d\n' %% (cfg['port'], cfg.get('sync_port', 0)))
how = cfg.get('fake', '')
on = 'Walkdown server on http://127.0.0.1:%%d' %% cfg['port']
if how == 'refused':
    sys.exit('the web pages are plain HTTP: address must be 127.0.0.1')
link = os.path.join(os.path.dirname(path), 'setup-link.txt')
open(link, 'w').write('http://127.0.0.1/#setup=TOKEN-%%d\n' %% cfg['port'])
print('No manager yet. The one-time link is in the setup link file: ' + link, flush=True)
if how == 'silent':
    time.sleep(60)
if how in ('late', 'never'):
    print(on, flush=True)
    time.sleep(0.4 if how == 'late' else 60)
if how == 'crash':
    print(on, flush=True)
    sys.exit('Error: unhandled exception: disk I/O error [DbError]')
socks = []
for i, p in enumerate((cfg['port'], cfg.get('sync_port', 0))):
    if not p: continue
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        s.bind(('127.0.0.1', p))
    except OSError:
        if i == 0: print(on, flush=True)     # the real one: the web port fails after the line, the sync port before
        print('oserrors.nim(92)         raiseOSError\nError: unhandled exception: Address already in use [OSError]', flush=True)
        sys.exit(1)
    s.listen()
    socks.append(s)
if how != 'late': print(on, flush=True)
if how == 'talks': print('said after the line', flush=True)
time.sleep(60)
'''


class Start(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix='kks-e2e-server-')
        self.addCleanup(shutil.rmtree, self.dir, ignore_errors=True)
        self.bin = os.path.join(self.dir, 'fake_server')
        with open(self.bin, 'w') as f:
            f.write(FAKE % sys.executable)
        os.chmod(self.bin, os.stat(self.bin).st_mode | stat.S_IXUSR)

    def hold(self):
        """a port another process took between the pick and the server's bind (here: this test, listening on it)"""
        s, port = e2e_server.taken_port()
        self.addCleanup(s.close)
        return port

    def started(self, proc):
        self.addCleanup(lambda: (proc.kill(), proc.wait(), proc.stdout.close()))
        return proc

    def starts(self):
        with open(os.path.join(self.dir, 'starts')) as f:
            return [tuple(int(x) for x in line.split()) for line in f]

    def picker(self, *first):
        """gives these picks first, then really free ports"""
        todo = list(first)
        return lambda n: todo.pop(0) if todo else e2e_server.free_ports(n)

    def test_up(self):
        cfg = {'sync_port': 0}
        proc, setup = e2e_server.start_server(self.bin, self.dir, cfg)
        self.started(proc)
        self.assertEqual(setup, f'TOKEN-{cfg["port"]}')
        self.assertEqual(cfg['sync_port'], 0, 'without sync the sync port stays as given')
        self.assertIn(cfg['port'], e2e_server.listening(proc.pid))
        with open(os.path.join(self.dir, 'config.json')) as f:
            self.assertEqual(json.load(f), cfg)
        self.assertIsNone(proc.poll())

    def test_two_ports(self):
        cfg = {}
        proc, _ = e2e_server.start_server(self.bin, self.dir, cfg, sync=True)
        self.started(proc)
        self.assertNotEqual(cfg['port'], cfg['sync_port'])
        self.assertLessEqual({cfg['port'], cfg['sync_port']}, e2e_server.listening(proc.pid))

    def test_taken_port_is_tried_again(self):
        """the web port taken in between (the server says "on", then exits), then the sync port (it exits before
        the line): each time new ports, and the third start is the one returned"""
        a, b, c = self.hold(), self.hold(), e2e_server.free_port()
        cfg = {}
        proc, setup = e2e_server.start_server(self.bin, self.dir, cfg, sync=True, pick=self.picker((a, c), (c, b)))
        self.started(proc)
        got = self.starts()
        self.assertEqual(got[:2], [(a, c), (c, b)])
        self.assertEqual(len(got), 3)
        self.assertEqual((cfg['port'], cfg['sync_port']), got[2])
        self.assertEqual(setup, f'TOKEN-{cfg["port"]}', "the token of the server that is up, not of one that exited")
        self.assertLessEqual(set(got[2]), e2e_server.listening(proc.pid))

    def test_taken_every_time(self):
        a = self.hold()
        with self.assertRaisesRegex(e2e_server.ServerStartError, r'taken 3 times in a row(.|\n)*Address already in use'):
            e2e_server.start_server(self.bin, self.dir, {'sync_port': 0}, attempts=3, pick=lambda n: (a,))
        self.assertEqual(len(self.starts()), 3)

    def test_another_failure_is_not_retried(self):
        """a server that exits for its own reasons fails the test with what it said: before the line, and after"""
        for how, said in (('refused', 'plain HTTP'), ('crash', 'disk I/O error')):
            with self.subTest(how):
                if os.path.exists(os.path.join(self.dir, 'starts')):
                    os.remove(os.path.join(self.dir, 'starts'))
                with self.assertRaises(e2e_server.ServerStartError) as e:
                    e2e_server.start_server(self.bin, self.dir, {'fake': how, 'sync_port': 0})
                self.assertIn(said, str(e.exception))
                self.assertIn('exit code 1', str(e.exception))
                self.assertEqual(len(self.starts()), 1, 'started once')

    def test_fixed_ports(self):
        """a restart keeps its address: the ports in the config are used, and a taken one is an error, not a move"""
        port = e2e_server.free_port()
        cfg = {'port': port, 'sync_port': 0}
        proc, _ = e2e_server.start_server(self.bin, self.dir, cfg, fixed=True)
        self.started(proc)
        self.assertEqual(cfg['port'], port)
        self.assertIn(port, e2e_server.listening(proc.pid))
        taken = self.hold()
        with self.assertRaisesRegex(e2e_server.ServerStartError, 'Address already in use'):
            e2e_server.start_server(self.bin, self.dir, {'port': taken, 'sync_port': 0}, fixed=True)
        self.assertEqual(self.starts(), [(port, 0), (taken, 0)])

    def test_waits_until_it_listens(self):
        """"server on" before the listener is there (the servers before 0.9 did): returned only once it listens"""
        cfg = {'fake': 'late', 'sync_port': 0}
        proc, _ = e2e_server.start_server(self.bin, self.dir, cfg)
        self.started(proc)
        self.assertIn(cfg['port'], e2e_server.listening(proc.pid))

    def test_silent_server(self):
        """no line and no exit: an error at the timeout, not a wait for ever; the process is not left running"""
        seen = []
        real = subprocess.Popen

        def popen(*a, **k):
            seen.append(real(*a, **k))
            return seen[-1]
        with self.assertRaisesRegex(e2e_server.ServerStartError, r'has not said it is on(.|\n)*setup link file'):
            e2e_server.start_server(self.bin, self.dir, {'fake': 'silent', 'sync_port': 0}, timeout=0.5, popen=popen)
        self.assertEqual(len(seen), 1)
        self.assertIsNotNone(seen[0].poll())

    def test_output_after_the_line_is_left(self):
        """what the server says after its "server on" line is still there for the test to read (test_server_http
        reads it at the end)"""
        proc, _ = e2e_server.start_server(self.bin, self.dir, {'fake': 'talks', 'sync_port': 0})
        self.started(proc)
        self.assertEqual(proc.stdout.readline(), 'said after the line\n')

    def test_never_listens(self):
        seen = []
        real = subprocess.Popen

        def popen(*a, **k):
            seen.append(real(*a, **k))
            return seen[-1]
        with self.assertRaisesRegex(e2e_server.ServerStartError, 'does not listen on'):
            e2e_server.start_server(self.bin, self.dir, {'fake': 'never', 'sync_port': 0}, timeout=0.5, popen=popen)
        self.assertEqual(len(seen), 1)
        self.assertIsNotNone(seen[0].poll(), 'the server that never came up is not left running')

    LISTENER = ('import socket, sys, time\n'
                'if sys.argv[2] == "broken": sys.exit("ModuleNotFoundError: No module named cryptography")\n'
                's = socket.create_server(("127.0.0.1", int(sys.argv[1])))\ntime.sleep(60)\n')

    def test_listener(self):
        """the relay twin's start: up when it listens; its port taken in between -> another port; another failure
        -> said, and not started again"""
        a = self.hold()
        tried = []

        def command(how):
            def argv(port):
                tried.append(port)
                return [sys.executable, '-c', self.LISTENER, str(port), how]
            return argv
        proc, port = e2e_server.start_listener(command('ok'), self.dir, pick=self.picker((a,)))
        self.addCleanup(lambda: (proc.kill(), proc.wait()))
        self.assertEqual(tried[0], a)
        self.assertNotEqual(port, a)
        self.assertIn(port, e2e_server.listening(proc.pid))
        del tried[:]
        with self.assertRaisesRegex(e2e_server.ServerStartError, 'No module named cryptography'):
            e2e_server.start_listener(command('broken'), self.dir)
        self.assertEqual(len(set(tried)), 1, 'one port, one start')
        with self.assertRaisesRegex(e2e_server.ServerStartError, 'taken 2 times in a row'):
            e2e_server.start_listener(command('ok'), self.dir, attempts=2, pick=lambda n: (a,))

    def test_listening_is_per_process(self):
        port = self.hold()
        self.assertIn(port, e2e_server.listening(os.getpid()))
        other = subprocess.Popen([sys.executable, '-c', 'import time; time.sleep(30)'])
        self.addCleanup(lambda: (other.kill(), other.wait()))
        self.assertNotIn(port, e2e_server.listening(other.pid))


class Suites(unittest.TestCase):
    def test_no_port_picker_of_their_own(self):
        """every e2e suite takes its ports from e2e_server: a copy of the old helper, or a port-0 bind read back and
        closed, would bring #155 back in that suite"""
        own = []
        for suite in SUITES:
            for root, _, files in os.walk(os.path.join(REPO, suite)):
                for name in files:
                    path = os.path.join(root, name)
                    if not name.endswith('.py') or os.path.samefile(path, e2e_server.__file__) or \
                       os.path.samefile(path, __file__):
                        continue
                    with open(path) as f:
                        text = f.read()
                    for n, line in enumerate(text.splitlines(), 1):
                        if re.search(r'def free_ports?\(|\.bind\(\([^)]*,\s*0\)\)', line) or \
                           len(re.findall(r'\bfree_port\(\)', line)) > 1:
                            own.append(f'{os.path.relpath(path, REPO)}:{n}: {line.strip()}')
        self.assertEqual(own, [])

    def test_two_ports_are_never_two_picks(self):
        """a server with a sync listener gets both ports from one start_server(sync=True): no suite writes a
        free_port() into a config's sync_port"""
        bad = []
        for suite in SUITES:
            for root, _, files in os.walk(os.path.join(REPO, suite)):
                for name in files:
                    path = os.path.join(root, name)
                    if not name.endswith('.py') or os.path.samefile(path, __file__):
                        continue
                    with open(path) as f:
                        for n, line in enumerate(f, 1):
                            if re.search(r"sync_port'\]?\s*[:=]\s*free_port", line):
                                bad.append(f'{os.path.relpath(path, REPO)}:{n}: {line.strip()}')
        self.assertEqual(bad, [])


if __name__ == '__main__':
    unittest.main()
