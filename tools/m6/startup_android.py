"""The Android app's cold start (docs/m6/MEASUREMENTS.md): for each APK, install it fresh, join the plant of
tools/m6/startup_data.py through the server, then RUNS cold starts (force-stopped, `am start -W`): TotalTime to the
first frame, and the app's own KKSTime lines (core open, first sheet drawn after process start). Medians per APK.

  ANDROID_SERIAL=emulator-5554 python3 tools/m6/startup_android.py SYNC_ADDRESS RUNS APK [APK …]

SYNC_ADDRESS as the phone reaches the server's sync port (the emulator: 10.0.2.2:PORT). Emulator only: it uninstalls
and clears the app. KKS_ROUNDS=n: the APKs take turns n times (each turn a fresh install and join), so that the
emulator's drift over a session falls on all of them alike; the medians are over every turn's starts."""
import os, re, statistics, subprocess, sys, time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'android', 'app2', 'e2e'))
import adbui as ui  # noqa: E402

PKG = 'io.github.walkdown'
ACT = PKG + '/kks.explorer.MainActivity'
assert os.environ.get('ANDROID_SERIAL', '').startswith('emulator-'), 'ANDROID_SERIAL=emulator-…: never a phone'
addr, runs, apks = sys.argv[1], int(sys.argv[2]), sys.argv[3:]


def cold_start():
    ui.sh('am', 'force-stop', PKG)
    time.sleep(2)
    ui.adb('logcat', '-c')
    out = ui.sh('am', 'start', '-W', '-n', ACT)
    m = re.search(r'TotalTime: (\d+)', out)
    if not m:                               # (am start said no time: the start is left out, and said)
        print('no TotalTime:', out.strip(), flush=True)
        return {}
    total = int(m[1])
    times = {'TotalTime (first frame)': total}
    for _ in range(40):                     # until the first sheet is on screen
        time.sleep(0.5)
        log = ui.adb('logcat', '-d', '-s', 'KKSTime:I')
        m = re.search(r'first sheet (\d+) ms after process start', log)
        if m:
            times['first sheet drawn'] = int(m[1])
            c = re.search(r'core open \+ replay (\d+) ms(?: \(([^)]*)\))?(?:, (\d+) ms after process start)?', log)
            if c:
                times['core open + replay'] = int(c[1])
                if c[3]:
                    times['core open done'] = int(c[3])
                if c[2]:
                    times['how: ' + c[2]] = 1
            break
    return times


got = {apk: {} for apk in apks}
for turn in range(int(os.environ.get('KKS_ROUNDS', '1'))):
    for apk in apks:
        subprocess.run(ui.ADB + ['uninstall', PKG], capture_output=True)
        r = subprocess.run(ui.ADB + ['install', '-t', apk], capture_output=True, text=True)
        assert 'Success' in r.stdout, r.stdout + r.stderr
        ui.sh('am', 'start', '-W', '-n', ACT)
        ui.tap('Join through a server', exact=True)
        ui.type_into('Server address', addr)
        ui.type_into('Username', 'boss')
        ui.type_into('Password', 'a long password')
        ui.tap('Join', exact=True)
        ui.find('Sheet 1', timeout=120)
        time.sleep(10)                          # (the photos, the first sync round)
        cold_start()                            # warm-up: the file cache, and whatever the app keeps for the next start
        for i in range(runs):
            t = cold_start()
            print(apk, 'turn', turn + 1, 'run', i + 1, t, flush=True)
            for k, v in t.items():
                got[apk].setdefault(k, []).append(v)
        ui.sh('am', 'force-stop', PKG)
for apk in apks:
    n = len(got[apk].get('TotalTime (first frame)', []))
    print(f'{apk}: median of {n} cold starts (min-max):')
    for k, v in got[apk].items():
        if k.startswith('how: '):
            print(f'  {k}: {len(v)} of {n}')
        else:
            print(f'  {k}: {statistics.median(v):.0f} ms ({min(v)}-{max(v)})')
