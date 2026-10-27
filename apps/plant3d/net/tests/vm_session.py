#!/usr/bin/env python3
"""A Windows VM in a LAN session (docs/plant3d/MULTIPLAYER.md §9.3, §12 "Devices", milestone MP2): the (test-signed)
MSIX installed, the app started through its alias in the logged-on desktop with the frames walk joined to a session
this machine hosts (`mp=CODE@HOST:PORT`, an input every 2 s), a screenshot of the VM's screen once the app has its
socket (does Windows ask the firewall question for a full-trust MSIX with privateNetworkClientServer?), the inbound
firewall rules before and after, and the walk's SESSION lines. Leaves the VM as it was: the package, its firewall rules
and the test certificate are removed at the end.

  python3 apps/plant3d/net/tests/vm_session.py VM_IP PACKAGE.msix CERT.cer CODE HOST:PORT OUT_DIR [--seconds 90]
      [--domain kks-win11]

The host is started by the caller (instance.gd as host, bound to every interface). Hold ~/kks-work/build/vm.lock
while the VM runs (one VM or emulator machine-wide). The VM: OpenSSH with ~/.ssh/kks_vm, user kks, logged on to its
desktop (apps/windows/e2e/vm)."""
import argparse, base64, functools, os, subprocess, time

print = functools.partial(print, flush=True)  # noqa: A001

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..'))
SSH = ['-i', os.path.expanduser('~/.ssh/kks_vm'), '-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null',
       '-o', 'LogLevel=ERROR', '-o', 'BatchMode=yes']
VM = ''
RULES = ("Get-NetFirewallRule -Direction Inbound -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "
         "'Walkdown|Godot' -or $_.Description -match 'Walkdown' } | ForEach-Object { $_.Name + ' | ' + $_.DisplayName + "
         "' | ' + $_.Action + ' | ' + $_.Profile + ' | ' + $_.Enabled }")


def vm(cmd, timeout=300):
    try:
        r = subprocess.run(['ssh', *SSH, 'kks@' + VM, 'powershell -NoProfile -Command -'], input=cmd,
                           capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return ''
    return r.stdout


def desktop(exe, args='', name='plantmp'):
    b64 = base64.b64encode(args.encode()).decode()
    vm(f'powershell -NoProfile -ExecutionPolicy Bypass -File C:\\plant\\runapp.ps1 -Exe "{exe}" '
       f'{"-ArgB64 " + b64 if args else ""} -Name {name}')


def msix(args):
    vm('Remove-Item C:\\plant\\msix.log -ErrorAction SilentlyContinue')
    desktop('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -File C:\\plant\\vm-msix.ps1 ' + args, 'plantmsix')
    for _ in range(90):
        time.sleep(2)
        out = vm('Get-Content C:\\plant\\msix.log -ErrorAction SilentlyContinue').strip()
        if out:
            return out
    return 'no answer from vm-msix.ps1'


def main():
    global VM
    ap = argparse.ArgumentParser()
    for a in ('vm', 'msix', 'cer', 'code', 'host', 'out'):
        ap.add_argument(a)
    ap.add_argument('--seconds', type=int, default=90)
    ap.add_argument('--domain', default='kks-win11')
    a = ap.parse_args()
    VM = a.vm
    os.makedirs(a.out, exist_ok=True)
    vm('New-Item -ItemType Directory -Force C:\\plant | Out-Null')
    subprocess.run(['scp', '-q', *SSH, a.msix, a.cer, os.path.join(REPO, 'apps', 'plant3d', 'msix', 'vm-msix.ps1'),
                    os.path.join(REPO, 'apps', 'windows', 'e2e', 'runapp.ps1'), f'kks@{VM}:C:/plant/'], check=True)
    cer = os.path.basename(a.cer)
    vm(f'Import-Certificate -FilePath C:\\plant\\{cer} -CertStoreLocation Cert:\\LocalMachine\\TrustedPeople | Out-Null')
    before = ''
    try:
        out = msix('-Add C:\\plant\\' + os.path.basename(a.msix))
        print('install:', out)
        if not out.startswith('ok WalkdownPlant_'):
            raise SystemExit('the MSIX did not install')
        print('Windows:', vm('(Get-CimInstance Win32_OperatingSystem).Caption + " " + '
                             '(Get-ItemProperty "HKLM:\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion").DisplayVersion').strip())
        before = vm(RULES).strip()
        print('firewall rules before:', before or '(none)')
        print('firewall profile:', vm('(Get-NetConnectionProfile | ForEach-Object { $_.InterfaceAlias + "=" + $_.NetworkCategory }) -join ", "').strip())
        outdir = 'C:\\plant\\out-mp'
        vm(f'Remove-Item -Recurse -Force {outdir} -ErrorAction SilentlyContinue; New-Item -ItemType Directory -Force {outdir} | Out-Null')
        alias = vm('Join-Path $env:LOCALAPPDATA Microsoft\\WindowsApps\\walkdown-plant.exe').strip()
        desktop(alias, f'--rendering-driver d3d12 -- --walk=frames --seconds={a.seconds} --quality=lean+vis '
                       f'--mp={a.code}@{a.host} --mp_inputs=2 --out={outdir}')
        # the app below normal priority (a VM without a GPU renders on its CPUs)
        for _ in range(30):
            if vm("$p = Get-Process WalkdownPlant -ErrorAction SilentlyContinue; if ($p) { $p | ForEach-Object { "
                  "$_.PriorityClass = 'BelowNormal' }; 'ok' }", 60).strip():
                break
            time.sleep(2)
        # once it has its socket: the screen (a firewall question would be on it)
        for k, wait in enumerate((25, 20)):
            time.sleep(wait)
            png = os.path.join(a.out, f'screen-{k}.png')
            subprocess.run(['virsh', 'screenshot', a.domain, png], capture_output=True)
            print('screenshot:', png if os.path.exists(png) else 'none')
        print('UDP endpoints of the app:', vm("Get-NetUDPEndpoint -OwningProcess (Get-Process WalkdownPlant).Id "
                                               "-ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress + ':' + "
                                               "$_.LocalPort } | Select-Object -First 8").strip().replace('\n', ' '))
        res = ''
        end = time.time() + a.seconds + 600
        while time.time() < end:
            time.sleep(5)
            res = vm(f'Get-Content {outdir}\\result.txt -Raw -ErrorAction SilentlyContinue')
            if 'RESULT' in res:
                break
        with open(os.path.join(a.out, 'result.txt'), 'w') as f:
            f.write(res)
        for ln in res.splitlines():
            if ln.startswith(('SESSION', 'RESULT')):
                print(ln)
        after = vm(RULES).strip()
        print('firewall rules after:', after or '(none)')
        # the rules this run made (a prompt answered, or Windows' own for the package) go again
        old = {ln.split(' | ')[0] for ln in before.splitlines() if ln.strip()}
        for ln in after.splitlines():
            name = ln.split(' | ')[0].strip()
            if name and name not in old:
                vm(f"Remove-NetFirewallRule -Name '{name}' -ErrorAction SilentlyContinue")
    finally:
        vm('Get-Process WalkdownPlant -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1')
        print('remove:', msix('-Remove'))
        vm('Get-ChildItem Cert:\\LocalMachine\\TrustedPeople | Where-Object { $_.Subject -match "Walkdown" } | Remove-Item')


if __name__ == '__main__':
    main()
