"""NAT-7, Windows: the app's startup and steady memory (budgets.json native.windows; rules in docs/m6/MEASUREMENTS.md).
Runs on the Windows runner, with the measurement plant's server already running (in WSL: budgets.yml):
  python tools/budgets/windows_app.py Walkdown.exe uiadrive.exe SYNC_PORT OUT.json

Scenario: the app joins the plant through the server (uiadrive.exe drives its UI Automation tree, as the e2e tests
do), then closes. One warm-up start (not counted), then N starts (N = budgets.json native.windows.runs), each:
- startup: from spawning the process to the app's "first sheet" line in timing.log (KKS_TIMING: written when the first
  overview level is decoded and shown), timed outside the app by watching the file every 5 ms;
- memory: private bytes 15 s after the start, the sheet at fit (the rule's "private bytes after 15 s");
- then the window is asked to close (taskkill without /F), forced after 15 s."""
import ctypes, os, re, subprocess, sys, tempfile, time
from ctypes import wintypes

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import budgetlib  # noqa: E402

APP, DRIVER, SYNC_PORT, OUT = sys.argv[1:5]
APP, DRIVER = os.path.abspath(APP), os.path.abspath(DRIVER)
DATA = os.path.join(os.environ.get('RUNNER_TEMP', tempfile.gettempdir()), 'walkdown-budget')
LOGS = os.path.dirname(os.path.abspath(OUT))
AFTER = 15


class PMC(ctypes.Structure):
    _fields_ = [('cb', wintypes.DWORD), ('PageFaultCount', wintypes.DWORD), ('PeakWorkingSetSize', ctypes.c_size_t),
                ('WorkingSetSize', ctypes.c_size_t), ('QuotaPeakPagedPoolUsage', ctypes.c_size_t),
                ('QuotaPagedPoolUsage', ctypes.c_size_t), ('QuotaPeakNonPagedPoolUsage', ctypes.c_size_t),
                ('QuotaNonPagedPoolUsage', ctypes.c_size_t), ('PagefileUsage', ctypes.c_size_t),
                ('PeakPagefileUsage', ctypes.c_size_t), ('PrivateUsage', ctypes.c_size_t)]


def memory(pid):
    """(private bytes, working set) in MB, as Get-Process PrivateMemorySize64 / WorkingSet64"""
    k32, psapi = ctypes.WinDLL('kernel32', use_last_error=True), ctypes.WinDLL('psapi', use_last_error=True)
    k32.OpenProcess.restype = wintypes.HANDLE
    h = k32.OpenProcess(0x1000 | 0x0010, False, pid)     # PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ
    if not h:
        raise OSError(ctypes.get_last_error(), 'OpenProcess')
    try:
        c = PMC()
        c.cb = ctypes.sizeof(PMC)
        if not psapi.GetProcessMemoryInfo(wintypes.HANDLE(h), ctypes.byref(c), c.cb):
            raise OSError(ctypes.get_last_error(), 'GetProcessMemoryInfo')
        return c.PrivateUsage / budgetlib.MB, c.WorkingSetSize / budgetlib.MB
    finally:
        k32.CloseHandle(wintypes.HANDLE(h))


def start(**extra):
    env = dict(os.environ, KKS_DATA_DIR=DATA, **extra)
    err = open(os.path.join(LOGS, 'windows-app.log'), 'a')
    return subprocess.Popen([APP], env=env, stdout=err, stderr=err)


def close(p):
    subprocess.run(['taskkill', '/PID', str(p.pid)], capture_output=True)
    try:
        p.wait(15)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait(10)
    time.sleep(1)


def join():
    script = os.path.join(LOGS, 'join.uia')
    with open(script, 'w', encoding='utf-8') as f:
        f.write('\n'.join(['wait\tJoin through a server\t60', 'click\tJoin through a server',
                           f'set\tServer address\t127.0.0.1:{SYNC_PORT}', 'set\tUsername\tboss',
                           'set\tPassword\ta long password', 'click\tJoin', 'wait\t~Sample sheet\t90', 'sleep\t3000']) + '\n')
    p = start()
    try:
        r = subprocess.run([DRIVER, os.path.basename(APP), script, os.path.join(LOGS, 'join-uia.log')], timeout=300)
        if r.returncode != 0:
            print(open(os.path.join(LOGS, 'join-uia.log'), encoding='utf-8', errors='replace').read())
            raise SystemExit('the join through the server failed (join-uia.log, windows-app.log)')
    finally:
        close(p)


def timing_lines():
    try:
        with open(os.path.join(DATA, 'timing.log'), encoding='utf-8') as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def one_start(n):
    before = len(timing_lines())
    t0 = time.perf_counter()
    p = start(KKS_TIMING='1')
    try:
        while True:
            lines = timing_lines()
            if len(lines) > before:
                outside = (time.perf_counter() - t0) * 1000
                inside = int(re.search(r'first sheet (\d+) ms', lines[before])[1])
                break
            if time.perf_counter() - t0 > 60:
                raise SystemExit(f'start {n}: no "first sheet" in timing.log after 60 s')
            if p.poll() is not None:
                raise SystemExit(f'start {n}: the app exited ({p.returncode})')
            time.sleep(0.005)
        time.sleep(max(0.0, AFTER - (time.perf_counter() - t0)))
        private, ws = memory(p.pid)
    finally:
        close(p)
    print(f'start {n}: first sheet {outside:.0f} ms from spawn ({inside} ms inside), private {private:.1f} MB, '
          f'working set {ws:.1f} MB', flush=True)
    return round(outside), round(private, 1), round(ws, 1)


def main():
    runs = budgetlib.runs_for('native', 'windows')
    os.makedirs(DATA, exist_ok=True)
    join()
    one_start(0)
    starts, privs, wss = [], [], []
    for n in range(1, runs + 1):
        s, pv, ws = one_start(n)
        starts.append(s)
        privs.append(pv)
        wss.append(ws)
    budgetlib.write(OUT, {'native.windows.startupMs': (starts, 'ms'), 'native.windows.memoryMB': (privs, 'MB')},
                    working_set_mb=wss, where='CI ' + os.environ.get('ImageOS', 'local'))


main()
