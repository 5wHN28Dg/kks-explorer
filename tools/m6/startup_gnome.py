"""The GNOME app's startup (docs/m6/MEASUREMENTS.md): RUNS starts of the joined app, each quitting a few seconds after
its window is up, with KKS_TIMING=1; prints every run's timing lines and the median of each step. Run it inside the
private compositor, never on the desktop:

  apps/gnome/e2e/headless.sh python3 tools/m6/startup_gnome.py DATA RUNS APP [APP …]

DATA is a folder joined with apps/gnome/e2e/startup_join.nim (its storage key in DATA/key). Each APP gets a copy of
it, and the apps' starts take turns (A B A B …), so that a busy moment of the machine falls on all of them alike. One
start of each before the counted ones warms the file cache and lets the app write what it keeps for the next start."""
import os, re, shutil, statistics, subprocess, sys, tempfile

data, runs, apps = sys.argv[1], int(sys.argv[2]), sys.argv[3:]
work = tempfile.mkdtemp(prefix='kks-startup-')
shot = os.path.join(work, 'shot.png')
folders = []
for i, app in enumerate(apps):
    d = os.path.join(work, f'data{i}')
    shutil.copytree(data, d)
    folders.append(d)
steps = [dict() for _ in apps]
order = [[] for _ in apps]
for r in range(runs + 1):
    for i, app in enumerate(apps):
        env = dict(os.environ, KKS_DATA_DIR=folders[i], KKS_STORAGE_KEY_FILE=os.path.join(folders[i], 'key'),
                   KKS_TIMING='1', KKS_NO_MDNS='1', KKS_SYNC_PORT='0', KKS_SHOT=f'{shot},4,quit')
        out = subprocess.run([app], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                             timeout=60).stdout
        lines = [ln for ln in out.splitlines() if ln.startswith('timing:')]
        print(f'{app} run {r}{" (warm-up)" if r == 0 else ""}:', *lines, sep='\n  ', flush=True)
        if r == 0:
            continue
        seen = set()
        for ln in lines:            # (the first of each step: a later reload says some again)
            m = re.match(r'timing: (.*?) (\d+) ms after launch', ln)
            if m:
                name = re.sub(r' \(.*\)$', '', m[1]).strip()
                if name in seen:
                    continue
                seen.add(name)
                if name not in steps[i]:
                    order[i].append(name)
                steps[i].setdefault(name, []).append(int(m[2]))
for i, app in enumerate(apps):
    print(f'{app}: median of {runs} runs (min-max):')
    for name in order[i]:
        v = steps[i][name]
        print(f'  {name}: {statistics.median(v):.0f} ms ({min(v)}-{max(v)})')
shutil.rmtree(work, ignore_errors=True)
