#!/usr/bin/env python3
"""Walkdown Plant's MSIX in a Windows VM (decision 0054 §4, §8): install the (test-signed) package, start the app
through its alias and walk the frames route on each rendering driver (Direct3D 12 and Vulkan: frame times in a VM
without a GPU only say that it runs, not how fast), then open walkdown-plant:// links through the shell (a cold
start; the link must arrive after `--`, decision 0056) and check what the app made of them. Leaves the VM as it was:
the package and the test certificate are removed at the end.

  python3 apps/plant3d/msix/test_msix_vm.py VM_IP PACKAGE.msix CERT.cer [--seconds 30]

Hold ~/kks-work/build/vm.lock while the VM runs (one VM or emulator machine-wide). The VM: OpenSSH with
~/.ssh/kks_vm, user kks, logged on to its desktop (apps/windows/e2e/vm)."""
import argparse, base64, functools, os, re, subprocess, sys, time

print = functools.partial(print, flush=True)  # noqa: A001  (progress as it happens)

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SSH = ['-i', os.path.expanduser('~/.ssh/kks_vm'), '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
       '-o', 'LogLevel=ERROR', '-o', 'BatchMode=yes']
VM = ''


def vm(cmd, timeout=300):
    try:
        r = subprocess.run(['ssh', *SSH, 'kks@' + VM, 'powershell -NoProfile -Command -'], input=cmd,
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return ''
    return r.stdout


def lower():
    """the app below normal priority: a VM without a GPU renders on its CPUs, and the app took them all (SSH timed
    out); waits up to a minute for it to start"""
    for _ in range(30):
        if vm("$p = Get-Process WalkdownPlant -ErrorAction SilentlyContinue; if ($p) { $p | ForEach-Object { "
              "$_.PriorityClass = 'BelowNormal' }; 'ok' }", 60).strip():
            return
        time.sleep(2)


def put(*paths):
    subprocess.run(['scp', '-q', *SSH, *paths, f'kks@{VM}:C:/plant/'], check=True)


def desktop(exe, args='', name='plantapp'):
    """starts exe in the logged-on user's desktop session (runapp.ps1: a scheduled task)"""
    b64 = base64.b64encode(args.encode()).decode()
    vm(f'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\plant\\runapp.ps1 -Exe "{exe}" '
       f'{"-ArgB64 " + b64 if args else ""} -Name {name}')


def stop():
    vm('Get-Process WalkdownPlant -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1')


def msix(args):
    vm('Remove-Item C:\\plant\\msix.log -ErrorAction SilentlyContinue')
    desktop('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File C:\\plant\\vm-msix.ps1 ' + args, 'plantmsix')
    for _ in range(90):
        time.sleep(2)
        out = vm('Get-Content C:\\plant\\msix.log -ErrorAction SilentlyContinue').strip()
        if out:
            return out
    return 'no answer from vm-msix.ps1'


def godot_log():
    """the app's own log (Godot's file log in user://logs; an MSIX app's AppData is under its package's LocalCache)"""
    return vm('$f = Get-ChildItem -Recurse -Filter godot.log -ErrorAction SilentlyContinue '
              '"$env:LOCALAPPDATA\\Packages\\WalkdownPlant_*\\LocalCache", "$env:APPDATA\\Godot\\app_userdata\\Walkdown Plant" '
              '| Sort-Object LastWriteTime | Select-Object -Last 1; if ($f) { Get-Content $f.FullName -Raw }')


def frames(driver, seconds):
    """the frames route on one driver; -> (the RESULT line or None, the renderer line, how long until it quit)"""
    stop()
    out = f'C:\\plant\\out-{driver}'
    vm(f'Remove-Item -Recurse -Force {out} -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force {out} | Out-Null')
    t0 = time.time()
    alias = vm('Join-Path $env:LOCALAPPDATA Microsoft\\WindowsApps\\walkdown-plant.exe').strip()
    desktop(alias, f'--rendering-driver {driver} -- --walk=frames --seconds={seconds} --quality=full '
            f'--out={out}')
    lower()
    end = time.time() + seconds + 600
    res = ''
    while time.time() < end:
        time.sleep(5)
        res = vm(f'Get-Content {out}\\result.txt -Raw -ErrorAction SilentlyContinue')
        if 'RESULT' in res:
            break
    took = time.time() - t0
    log = godot_log()
    stop()
    result = next((ln for ln in res.splitlines() if ln.startswith('RESULT')), None)
    api = next((ln.strip() for ln in log.splitlines() if re.match(r'\s*(Vulkan|D3D12|OpenGL)', ln.strip())), '?')
    return result, api, took, log


def main():
    global VM
    ap = argparse.ArgumentParser()
    ap.add_argument('vm')
    ap.add_argument('msix')
    ap.add_argument('cer')
    ap.add_argument('--seconds', type=int, default=30)
    ap.add_argument('--links-only', action='store_true', help='skip the frames walks')
    a = ap.parse_args()
    VM = a.vm
    failed = []
    vm('New-Item -ItemType Directory -Force C:\\plant | Out-Null')
    put(a.msix, a.cer, os.path.join(HERE, 'vm-msix.ps1'), os.path.join(REPO, 'apps', 'windows', 'e2e', 'runapp.ps1'))
    cer = os.path.basename(a.cer)
    vm(f'Import-Certificate -FilePath C:\\plant\\{cer} -CertStoreLocation Cert:\\LocalMachine\\TrustedPeople | Out-Null')
    try:
        out = msix('-Add C:\\plant\\' + os.path.basename(a.msix))
        print('install:', out)
        if not out.startswith('ok WalkdownPlant_'):
            raise SystemExit('the MSIX did not install')
        print('Windows:', vm('(Get-CimInstance Win32_OperatingSystem).Caption + " " + '
                             '(Get-ItemProperty "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion").DisplayVersion').strip())
        print('display adapter:', vm('(Get-CimInstance Win32_VideoController).Name').strip())
        # 1. started through the alias, on each driver
        for driver in () if a.links_only else ('d3d12', 'vulkan'):
            result, api, took, log = frames(driver, a.seconds)
            print(f'{driver}: {api}; {result or "no RESULT"} ({took:.0f} s to the end)')
            if result is None:
                failed.append(f'{driver}: the frames walk gave no result')
                print('\n'.join(log.splitlines()[-25:]))
        # 2. links through the shell: a cold start each, the URI after --
        for link, want in (('walkdown-plant://kks/30PAC10AP001', '"open":"kks"'),
                           ('walkdown-plant://procedure/cold_start', '"open":"procedure"'),
                           ('walkdown-plant://kks/NOT-A-CODE', '"open":"start"')):
            stop()
            vm('Get-ChildItem -Recurse -Filter godot.log -ErrorAction SilentlyContinue '
               '"$env:LOCALAPPDATA\\Packages\\WalkdownPlant_*\\LocalCache" | Remove-Item -Force -ErrorAction SilentlyContinue')
            desktop('explorer.exe', link, 'plantlink')
            lower()
            cmdline = ''
            for _ in range(60):
                time.sleep(3)
                cmdline = vm("(Get-CimInstance Win32_Process -Filter \"Name='WalkdownPlant.exe'\").CommandLine").strip()
                if cmdline:
                    break
            # the release build writes its log out when it ends: give it time to load and take the link, then close
            # its window as a person would, and read the log
            time.sleep(60)
            # (from the desktop session: SSH's session can't reach the window)
            desktop('powershell.exe', '-NoProfile -Command "Get-Process WalkdownPlant | ForEach-Object { '
                    '$_.CloseMainWindow() }"', 'plantclose')
            vm('Wait-Process WalkdownPlant -Timeout 90 -ErrorAction SilentlyContinue')
            line = next((ln for ln in godot_log().splitlines() if ln.startswith('plant: link ')), None)
            print(f'{link}: command line {cmdline!r}; {line}')
            if not re.search(r' -- "walkdown-plant://[^"]*"$', cmdline):   # (the shell may normalise the URI)
                failed.append(f'{link}: not passed after -- ({cmdline!r})')
            if not line or want not in line:
                failed.append(f'{link}: the app did not open it as {want} ({line})')
        stop()
    finally:
        stop()
        print('remove:', msix('-Remove'))
        vm(f'$t = (New-Object Security.Cryptography.X509Certificates.X509Certificate2 C:\\plant\\{cer}).Thumbprint; '
           f'Remove-Item Cert:\\LocalMachine\\TrustedPeople\\$t; Unregister-ScheduledTask -TaskName plant* -Confirm:$false '
           f'-ErrorAction SilentlyContinue; Remove-Item -Recurse -Force C:\\plant -ErrorAction SilentlyContinue')
    print('FAILED: ' + '; '.join(failed) if failed else 'PASSED')
    sys.exit(1 if failed else 0)


if __name__ == '__main__':
    main()
