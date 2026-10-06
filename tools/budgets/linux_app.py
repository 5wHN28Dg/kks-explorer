"""NAT-7, Linux: the GNOME app's startup and steady memory (budgets.json native.linux; rules in docs/m6/MEASUREMENTS.md).
Runs inside apps/gnome/e2e/headless.sh (a private mutter; the join goes through AT-SPI):
  apps/gnome/e2e/headless.sh python3 tools/budgets/linux_app.py APP SERVER IMPORTER OUT.json [--no-mdns]

Scenario: the app joins the measurement plant (plant.py: the sample sheet, one tag) through the server, then quits.
One warm-up start (not counted: it fills the file cache), then N starts (N = budgets.json native.linux.runs), each:
- startup: from spawning the process to the app's "timing: first sheet drawn" line (KKS_TIMING; written when GTK
  snapshots the first overview level), measured outside the app, so loading and linking count too;
- memory: VmRSS 10 s after that line, the sheet at fit (as on the laptop baseline), the server still running;
- then SIGTERM."""
import os, re, signal, subprocess, sys, threading, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'apps', 'gnome', 'e2e'))
import budgetlib, plant  # noqa: E402
import atspi  # noqa: E402

APP, SERVER, IMPORTER, OUT = sys.argv[1:5]
MDNS = '--no-mdns' not in sys.argv
SETTLE = 10


def env_for(d, **extra):
    e = dict(os.environ, KKS_DATA_DIR=d, KKS_STORAGE_KEY_FILE=os.path.join(d, 'key'),
             KKS_SYNC_PORT=str(plant.free_port()), **extra)
    if not MDNS:
        e['KKS_NO_MDNS'] = '1'
    return e


def join(p, d):
    before = atspi.app_pids()
    log = open(os.path.join(d, 'join.log'), 'w')
    proc = subprocess.Popen([APP], env=env_for(d), stdout=log, stderr=subprocess.STDOUT)
    try:
        a = atspi.app_pid(proc.pid, name=('walkdown', 'kks_explorer'), before=before, timeout=60)
        atspi.click(atspi.find(a, 'button', name='Join through a server', timeout=30))
        atspi.set_text(atspi.find(a, 'text', name='Server address'), f'127.0.0.1:{p.sync_port}')
        atspi.set_text(atspi.find(a, 'text', name='Username'), plant.USER)
        atspi.set_text(atspi.find(a, 'password text', name='Password'), plant.PASSWORD)
        atspi.click(atspi.find(a, 'button', name='Join'))
        atspi.find(a, 'list item', contains='Sample sheet', timeout=60)
        time.sleep(3)     # let the first sync finish writing (photos, settings)
    finally:
        proc.send_signal(signal.SIGTERM)
        proc.wait(20)


def one_start(d, n):
    log = open(os.path.join(d, f'start-{n}.log'), 'w')
    got = threading.Event()
    seen = {}
    t0 = time.monotonic()
    proc = subprocess.Popen([APP], env=env_for(d, KKS_TIMING='1'), stdout=subprocess.DEVNULL,
                            stderr=subprocess.PIPE, text=True)

    def read():
        for line in proc.stderr:
            log.write(line)
            log.flush()
            m = re.search(r'timing: first sheet drawn (\d+) ms', line)
            if m and not got.is_set():
                seen['outside'] = (time.monotonic() - t0) * 1000
                seen['inside'] = int(m[1])
                got.set()
    threading.Thread(target=read, daemon=True).start()
    try:
        if not got.wait(60):
            raise SystemExit(f'start {n}: no "first sheet drawn" in 60 s (see {log.name})')
        time.sleep(SETTLE)
        if proc.poll() is not None:
            raise SystemExit(f'start {n}: the app exited ({proc.returncode})')
        mem = plant.rss_mb(proc.pid)
    finally:
        proc.send_signal(signal.SIGTERM)
        try:
            proc.wait(20)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(5)
    print(f'start {n}: first sheet {seen["outside"]:.0f} ms from spawn ({seen["inside"]} ms inside), '
          f'VmRSS {mem:.1f} MB', flush=True)
    return round(seen['outside']), round(mem, 1)


def main():
    runs = budgetlib.runs_for('native', 'linux')
    p = plant.Plant(SERVER, IMPORTER, log=os.path.join(os.path.dirname(os.path.abspath(OUT)), 'linux-server.log')).start()
    try:
        d = os.path.join(p.dir, 'device')
        os.makedirs(d)
        join(p, d)
        one_start(d, 0)       # warm-up: not counted
        starts, mems = [], []
        for n in range(1, runs + 1):
            s, m = one_start(d, n)
            starts.append(s)
            mems.append(m)
    finally:
        p.stop()
    budgetlib.write(OUT, {'native.linux.startupMs': (starts, 'ms'), 'native.linux.memoryMB': (mems, 'MB')},
                    where='CI ' + os.environ.get('ImageOS', 'local') + ', headless mutter', mdns=MDNS)


main()
