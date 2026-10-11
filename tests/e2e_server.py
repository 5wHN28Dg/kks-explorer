"""Ports and server starts for the end-to-end suites (android/app2/e2e, platform/linux/e2e, apps/gnome/e2e,
apps/windows/e2e): the one copy of what each of them had as `free_port()` and a start loop of its own.

Issue #155: `free_port()` bound port 0, read the number and closed the socket, and the suites called it twice in a
row for the web port and the sync port. The kernel sometimes gives the second call the port the first just released,
and a server told to use one port for both exits at start (about 1 start in 150). So:
- `free_ports(n)` holds every socket until all n numbers are read: they differ;
- `start_server` picks the ports, starts the server and waits until that process itself listens on them. A server
  that exits because a port was taken between the pick and its bind (by any other process on the machine) is started
  again on new ports; one that exits for any other reason fails the test with its output.

Imported by path (`sys.path.insert(0, <repo>/tests)`); Linux only, like the server."""
import json, os, re, select, socket, subprocess, time

TAKEN = 'Address already in use'      # what the server's unhandled OSError says when a port of its own is not free


class ServerStartError(AssertionError):
    pass


def free_ports(n):
    """n TCP ports free on 127.0.0.1 right now, all different: each stays bound until the last is picked."""
    held = []
    try:
        for _ in range(n):
            s = socket.socket()
            held.append(s)
            s.bind(('127.0.0.1', 0))
        return tuple(s.getsockname()[1] for s in held)
    finally:
        for s in held:
            s.close()


def free_port():
    """one free port. For two or more that must differ use free_ports(n): two calls of this can return the same."""
    return free_ports(1)[0]


def taken_port():
    """-> (a socket listening on 127.0.0.1, its port): a port that is not free, for the tests of a taken one. Close
    the socket to release it."""
    s = socket.socket()
    s.bind(('127.0.0.1', 0))
    s.listen()
    return s, s.getsockname()[1]


def listening(pid):
    """the TCP ports this process listens on now (/proc/net/tcp and tcp6, matched to the process's own sockets)"""
    mine = set()
    try:
        fds = os.listdir(f'/proc/{pid}/fd')
    except OSError:
        return set()
    for fd in fds:
        try:
            m = re.fullmatch(r'socket:\[(\d+)\]', os.readlink(f'/proc/{pid}/fd/{fd}'))
        except OSError:
            continue
        if m:
            mine.add(m[1])
    out = set()
    for table in ('/proc/net/tcp', '/proc/net/tcp6'):
        try:
            with open(table) as f:
                rows = f.read().splitlines()[1:]
        except OSError:
            continue
        for row in rows:
            c = row.split()
            if len(c) > 9 and c[3] == '0A' and c[9] in mine:        # 0A: TCP_LISTEN
                out.add(int(c[1].rsplit(':', 1)[1], 16))
    return out


def _setup_token(line):
    if 'setup link file: ' in line:          # the link is in a 0600 file (#69)
        with open(line.split('setup link file: ', 1)[1].strip()) as f:
            line = f.read()
    m = re.search(r'#setup=([A-Za-z0-9_-]+)', line)
    return m[1] if m else None


def _line(proc, deadline):
    """the next line of the process's output ('' at its end), or ServerStartError at the deadline. Read byte by byte
    from the pipe itself, so nothing after the line is taken and `proc.stdout` reads on from there."""
    fd, got = proc.stdout.fileno(), b''
    while not got.endswith(b'\n'):
        left = deadline - time.time()       # (checked for every byte: a server that never stops talking ends here too)
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            raise ServerStartError(got.decode(errors='replace'))
        b = os.read(fd, 1)
        if not b:
            break
        got += b
    return got.decode(errors='replace')


def _start_once(binary, folder, cfg, timeout, popen=subprocess.Popen, listening=listening):
    """-> (process, setup token, None) when it is up, (None, None, its output) when it has exited"""
    path = os.path.join(folder, 'config.json')
    with open(path, 'w') as f:
        json.dump(cfg, f)
    proc = popen([binary, 'serve', '--config', path], cwd=folder, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                 text=True)
    out, setup, t0 = [], None, time.time()
    try:
        while True:
            try:
                line = _line(proc, t0 + timeout)
            except ServerStartError as e:
                raise ServerStartError(f'after {timeout} s the server has not said it is on, and has not exited:\n'
                                       + ''.join(out) + str(e)) from None
            if not line:                     # its output ended: it is exiting
                break
            out.append(line)
            setup = _setup_token(line) or setup
            if 'server on' in line:
                break
        # "server on" is said before a taken port ends the process (at its first poll), so the line alone is not
        # "up": wait until this process holds its ports, or is gone
        want = {p for p in (cfg['port'], cfg.get('sync_port', 0)) if p}
        # one port for both: the sync listener has it, the web listener's failure ends the process at its first poll.
        # Never "up", although the process listens on all it was given for a moment
        doomed = cfg['port'] == cfg.get('sync_port', 0)
        while out and 'server on' in out[-1]:
            if proc.poll() is not None:
                break
            if not doomed and want <= listening(proc.pid):
                return proc, setup, None
            if time.time() - t0 > timeout:
                raise ServerStartError(f'the server said it was on, and after {timeout} s it does not listen on '
                                       f'{sorted(want)} (it listens on {sorted(listening(proc.pid))}):\n' + ''.join(out))
            time.sleep(0.01)
        try:
            proc.wait(timeout)
        except subprocess.TimeoutExpired:
            raise ServerStartError('the server closed its output without saying it was on, and did not exit:\n'
                                   + ''.join(out))
        out.append(proc.stdout.read())
        proc.stdout.close()
        return None, None, ''.join(out) + f'(exit code {proc.returncode})'
    except BaseException:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        proc.stdout.close()
        raise


def start_server(binary, folder, cfg, sync=False, fixed=False, attempts=5, timeout=30, pick=free_ports, **hooks):
    """Start `binary serve` on `folder`/config.json, written here from `cfg` -> (the process, the setup token or None).
    The process has stdout and stderr on one text pipe (`.stdout`), read up to its "server on" line.

    - not `fixed`: cfg['port'], and cfg['sync_port'] with `sync`, are picked here (read them from cfg afterwards).
      Without `sync` cfg['sync_port'] is left as given (0 = no sync listener). A server that exits saying a port was
      taken is started again on new ports, `attempts` times in all;
    - `fixed`: the ports already in cfg are used (a restart on the address a browser or a phone already knows): one
      attempt.
    A server that exits for any other reason, or stays without listening, raises ServerStartError with its output."""
    said = []
    for _ in range(1 if fixed else attempts):
        if not fixed:
            if sync:
                cfg['port'], cfg['sync_port'] = pick(2)
            else:
                cfg['port'], = pick(1)
        proc, setup, out = _start_once(binary, folder, cfg, timeout, **hooks)
        if proc is not None:
            return proc, setup
        if fixed or TAKEN not in out:
            raise ServerStartError(f'the server exited at start (port {cfg["port"]}, sync port {cfg.get("sync_port")}):\n{out}')
        said.append(out)
    raise ServerStartError(f'the server found its ports taken {attempts} times in a row; the last time:\n{said[-1]}')


def start_listener(command, folder, attempts=5, timeout=30, pick=free_ports):
    """Start a program that listens on the one port its command line names (the relay twin): `command(port)` is its
    argv -> (the process, the port), once that process listens on it. Its output goes to `folder`/listener.log. As
    with start_server: an exit that says the port was taken is tried again on another port, any other exit raises
    ServerStartError with what it said."""
    said, argv = '', None
    for _ in range(attempts):
        port, = pick(1)
        with open(os.path.join(folder, 'listener.log'), 'w+') as log:
            argv = command(port)
            proc = subprocess.Popen(argv, stdout=log, stderr=subprocess.STDOUT)
            t0 = time.time()
            try:
                while proc.poll() is None:
                    if port in listening(proc.pid):
                        return proc, port
                    if time.time() - t0 > timeout:
                        raise ServerStartError(f'{argv} does not listen on {port} after {timeout} s')
                    time.sleep(0.01)
            except BaseException:
                proc.kill()
                proc.wait()
                raise
            log.seek(0)
            said = log.read() + f'(exit code {proc.returncode})'
        if TAKEN not in said:
            raise ServerStartError(f'{argv} exited at start:\n{said}')
    raise ServerStartError(f'{argv} found its port taken {attempts} times in a row; the last time:\n{said}')
