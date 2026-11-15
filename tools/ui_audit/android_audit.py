"""UI audit helpers for Walkdown Android on the emulator: screens (uiautomator dump + screencap) and the target checks
(T1 size, T2 overlap and destructive spacing) from the dump's bounds / density. Uses android/app2/e2e/adbui.py.
A library: import it from a Python shell with ANDROID_SERIAL=emulator-NNNN set (never a real phone), the app on
the screen to check, then check('screen-name'). Output in $KKS_AUDIT_OUT (default $TMPDIR/ui-audit-android)."""
import os, re, subprocess, sys, time, json
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, REPO + '/android/app2/e2e')
import adbui as ui  # noqa
OUT = os.environ.get('KKS_AUDIT_OUT', os.path.join(os.environ.get('TMPDIR', '/tmp'), 'ui-audit-android'))
os.makedirs(OUT, exist_ok=True)
DESTRUCTIVE = re.compile(r'^(Delete|Remove|Discard|Sign out|Leave|Reject|Revert|Restore|Withdraw|Refuse|Not a tag|Clear removed)\b', re.I)


def density():
    m = re.findall(r'(\d+)', ui.sh('wm', 'density'))
    return int(m[-1])


def bounds(n):
    return tuple(map(int, re.findall(r'\d+', n.get('bounds'))))


def shot(name):
    with open(os.path.join(OUT, name + '.png'), 'wb') as f:
        f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)


def targets(ns):
    t = []
    for n in ns:
        if n.get('package') != 'io.github.walkdown':
            continue
        if n.get('clickable') == 'true' or n.get('checkable') == 'true' or n.get('long-clickable') == 'true' or n.get('class', '').endswith('EditText'):
            if n.get('scrollable') == 'true':
                continue
            b = bounds(n)
            if b[2] <= b[0] or b[3] <= b[1]:
                continue
            lab = ui.label(n)
            if not lab:     # a clickable container: its children's texts
                kids = [ui.label(k) for k in n.iter('node') if ui.label(k)]
                lab = ' / '.join(kids)[:60]
            if re.search(r', (verified|needs checking|read automatically|proposed)', lab):
                continue      # a tag drawn on the sheet: exempt from T1/T2 (T4 covers it)
            t.append((lab, b, n.get('class', '').split('.')[-1]))
    return t


def check(name, save=True, quiet=False):
    """dump + shot + T1/T2 report for the current screen; returns (fails list, nodes)"""
    ns = ui.nodes()
    if save:
        shot(name)
        subprocess.run(ui.ADB + ['exec-out', 'cat', '/sdcard/kks-ui.xml'], stdout=open(os.path.join(OUT, name + '.xml'), 'w'))
    d = density() / 160
    W, H = map(int, re.findall(r'(\d+)x(\d+)', ui.sh('wm', 'size'))[-1])
    t = targets(ns)
    lines = []
    for lab, b, cls in t:
        w, h = (b[2] - b[0]) / d, (b[3] - b[1]) / d
        # cut by the screen edge (scrolled partly off) is not a size fail
        edge = b[1] <= 0 or b[3] >= H - 1 or b[0] <= 0 or b[2] >= W - 1
        if (w < 48 or h < 48):
            lines.append(f'T1 {"(at edge) " if edge else ""}{w:.0f}x{h:.0f}dp {cls} {lab!r} {b}')
    for i in range(len(t)):
        for j in range(i + 1, len(t)):
            a, b = t[i][1], t[j][1]
            ix = min(a[2], b[2]) - max(a[0], b[0]); iy = min(a[3], b[3]) - max(a[1], b[1])
            inside = (a[0] <= b[0] and a[1] <= b[1] and a[2] >= b[2] and a[3] >= b[3]) or (b[0] <= a[0] and b[1] <= a[1] and b[2] >= a[2] and b[3] >= a[3])
            if ix > 0 and iy > 0:
                lines.append(f'T2 overlap{" (nested)" if inside else ""}: {t[i][0]!r} {a} / {t[j][0]!r} {b}')
            else:
                if DESTRUCTIVE.match(t[i][0]) or DESTRUCTIVE.match(t[j][0]):
                    gap = max(-ix, -iy) / d
                    if gap < 8:
                        lines.append(f'T2 destructive gap {gap:.1f}dp: {t[i][0]!r} {a} / {t[j][0]!r} {b}')
    unnamed = [f'{n.get("class")} {n.get("bounds")}' for n in ns if n.get('package') == 'io.github.walkdown' and n.get('clickable') == 'true'
               and not ui.label(n) and not any(ui.label(k) for k in n.iter('node'))]
    for u in unnamed:
        lines.append('A2 unnamed clickable: ' + u)
    with open(os.path.join(OUT, name + '.txt'), 'w') as f:
        f.write(f'density {d * 160} size {W}x{H}\n' + '\n'.join(f'{l} {b} {c}' for l, b, c in t) + '\n---\n' + '\n'.join(lines) + '\n')
    if not quiet:
        print(f'== {name}: {len(t)} targets, {len(lines)} issues')
        for l in lines:
            print('  ', l)
    return lines, ns


def texts(ns=None):
    ns = ns or ui.nodes()
    return [(ui.label(n), n.get('bounds')) for n in ns if ui.label(n)]


def demo():
    ui.sh('settings', 'put', 'global', 'sysui_demo_allowed', '1')
    for c in (['enter'], ['clock', '-e', 'hhmm', '1200'], ['network', '-e', 'wifi', 'show', '-e', 'level', '4'],
              ['battery', '-e', 'level', '100', '-e', 'plugged', 'false'], ['notifications', '-e', 'visible', 'false']):
        ui.sh('am', 'broadcast', '-a', 'com.android.systemui.demo', '-e', 'command', *c)
