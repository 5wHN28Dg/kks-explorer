"""The Windows app's startup in a VM (docs/m6/MEASUREMENTS.md): copies the exes, the join tool
(apps/windows/e2e/startup_join.nim) and apps/windows/e2e/startup.ps1 into the VM, which joins a data folder for each
exe to the plant of tools/m6/startup_data.py and starts the exes in turns; prints the timing lines and the median
of each step per exe.

  python3 tools/m6/startup_windows.py VM_IP SYNC_ADDRESS RUNS JOIN.exe NAME=APP.exe [NAME=APP.exe …]

SYNC_ADDRESS as the VM reaches the server's sync port (libvirt's host: 192.168.122.1:PORT). Each NAME is the file
name the exe gets in the VM (its data folder is C:\\kks\\sd-NAME)."""
import base64, os, re, shutil, statistics, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
E2E = os.path.join(REPO, 'apps', 'windows', 'e2e')
vm_ip, sync, runs, join = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
exes = [a.split('=', 1) for a in sys.argv[5:]]
SSH = ['-i', os.path.expanduser('~/.ssh/kks_vm'), '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
       '-o', 'LogLevel=ERROR', '-o', 'BatchMode=yes']


def vm(cmd):
    return subprocess.run(['ssh'] + SSH + ['kks@' + vm_ip, cmd], capture_output=True, text=True, timeout=120,
                          errors='replace').stdout


tmp = tempfile.mkdtemp(prefix='kks-startup-win-')
files = [os.path.join(E2E, 'startup.ps1'), os.path.join(E2E, 'runapp.ps1')]
shutil.copy(join, os.path.join(tmp, 'startup_join.exe'))
files.append(os.path.join(tmp, 'startup_join.exe'))
for name, path in exes:
    shutil.copy(path, os.path.join(tmp, name + '.exe'))
    files.append(os.path.join(tmp, name + '.exe'))
vm('New-Item -ItemType Directory C:\\kks -Force | Out-Null; Remove-Item C:\\kks\\startup.log -ErrorAction SilentlyContinue')
subprocess.run(['scp', '-q'] + SSH + files + ['kks@%s:C:/kks/' % vm_ip], check=True, timeout=600)
shutil.rmtree(tmp)
args = '-NoProfile -ExecutionPolicy Bypass -File C:\\kks\\startup.ps1 -Server %s -Exes %s -Runs %d' % (
    sync, ','.join('C:\\kks\\%s.exe' % n for n, _ in exes), runs)
vm('powershell -NoProfile -ExecutionPolicy Bypass -File C:\\kks\\runapp.ps1 -Exe powershell.exe -ArgB64 %s -Name kksstartup'
   % base64.b64encode(args.encode()).decode())
log = ''
for _ in range(600):
    time.sleep(5)
    log = vm('Get-Content C:\\kks\\startup.log -ErrorAction SilentlyContinue')
    if '13:00:00 done' in log:
        break
print(log)
for block in log.split('== ')[1:]:
    name = block.splitlines()[0].strip()
    steps, order, run = {}, [], 0
    seen = set()
    for ln in block.splitlines()[1:]:
        if ln.startswith('end of run'):
            run += 1
            seen = set()
            continue
        if run == 0:                 # the warm-up start
            continue
        m = re.match(r'(?:timing: )?(.*?) (\d+) ms after (?:launch|start)', ln.strip())
        if m:
            k = re.sub(r' \(.*\)$', '', m[1]).strip()
            if k in seen:
                continue
            seen.add(k)
            if k not in steps:
                order.append(k)
            steps.setdefault(k, []).append(int(m[2]))
    print(f'{name}: median of {run - 1} starts (min-max):')
    for k in order:
        v = steps[k]
        print(f'  {k}: {statistics.median(v):.0f} ms ({min(v)}-{max(v)})')
