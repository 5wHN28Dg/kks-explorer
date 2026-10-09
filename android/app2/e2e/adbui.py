"""Driving the Android app the way TalkBack sees it: through the accessibility tree (uiautomator dump), with adb."""
import re, subprocess, time, xml.etree.ElementTree as ET
import os
ADB = [os.path.expanduser('~/Android/Sdk/platform-tools/adb')]


def sh(*a):
    return subprocess.run(ADB + ['shell', *a], capture_output=True, text=True).stdout


def adb(*a):
    return subprocess.run(ADB + list(a), capture_output=True, text=True).stdout


def nodes():
    for _ in range(5):
        sh('uiautomator', 'dump', '/sdcard/kks-ui.xml')
        x = subprocess.run(ADB + ['exec-out', 'cat', '/sdcard/kks-ui.xml'], capture_output=True, text=True).stdout
        if '<' in x:
            return list(ET.fromstring(x[x.index('<'):]).iter('node'))
        time.sleep(0.5)
    return []


def label(n):
    return n.get('text') or n.get('content-desc') or ''


def system_ui_wait(ns):
    """taps Wait on "System UI isn't responding" (not the app's own: that must fail); True if it was there"""
    if not any("System UI isn't responding" in label(n) for n in ns):
        return False
    for n in ns:
        if label(n) == 'Wait':
            x, y = center(n)
            sh('input', 'tap', str(x), str(y))
    return True


def find(text, timeout=15, exact=False):
    end = time.time() + timeout
    waits = 0
    while True:
        ns = nodes()
        for n in ns:
            v = label(n)
            if (v == text) if exact else (text in v):
                return n
        # a slow emulator (CI's software GPU) shows "System UI isn't responding" over everything: wait it out
        if waits < 12 and system_ui_wait(ns):
            waits += 1
            end = max(end, time.time() + 5)
            time.sleep(1)
            continue
        if time.time() > end:
            raise AssertionError(f'not on screen: {text!r}')
        time.sleep(0.7)


def present(text, exact=False):
    return any(((label(n) == text) if exact else (text in label(n))) for n in nodes())


def fresh_app(pkg, activity='kks.explorer.MainActivity', timeout=15):
    """clear the app's data and start it, then wait until its window is on screen. `pm clear` returns before Android
    has finished with the cleared package: an app started at once had its new task removed and its process killed
    26 ms later ("remove task", "start not valid"), and the next test found the home screen (run 37903391890). So
    the app is started again until its own window shows."""
    sh('pm', 'clear', pkg)
    waits = 0
    for _ in range(4):
        sh('am', 'start', '-n', f'{pkg}/{activity}')
        end, seen = time.time() + timeout, 0
        while time.time() < end:
            ns = nodes()
            if waits < 12 and system_ui_wait(ns):
                waits += 1
                end = max(end, time.time() + 5)
            # in two dumps in a row (each takes about a second): not a window that is being taken away
            seen = seen + 1 if any(n.get('package') == pkg for n in ns) else 0
            if seen >= 2:
                return
            time.sleep(0.5)
    raise AssertionError(f'{pkg} did not come up after pm clear')


def center(n):
    a, b, c, d = map(int, re.findall(r'\d+', n.get('bounds')))
    return (a + c) // 2, (b + d) // 2


def tap(text, **kw):
    x, y = center(find(text, **kw))
    sh('input', 'tap', str(x), str(y))


def type_into(field, value, clear=False):
    """ASCII only: `adb shell input text` can't type other scripts. clear: empty the field first (Ctrl+A, Delete),
    else the text goes in where the cursor lands"""
    tap(field, exact=True)
    time.sleep(0.3)
    if clear:
        sh('input', 'keycombination', '113', '29')   # Ctrl+A
        sh('input', 'keyevent', '67')                # Delete
    sh('input', 'text', value.replace(' ', '%s'))
    hide_keyboard()


def keyboard_shown():
    return 'mInputShown=true' in sh('dumpsys', 'input_method')


def hide_keyboard():
    """Escape hides the keyboard on the emulator, not on the Honor 600 (MagicOS); Back does, but only send Back while
    the keyboard is up, or it navigates"""
    sh('input', 'keyevent', '111')
    time.sleep(0.3)
    for _ in range(3):
        if not keyboard_shown():
            return
        sh('input', 'keyevent', '4')
        time.sleep(0.4)


def scroll_to(text, exact=False, tries=8):
    """swipe the lower half up until text is on screen"""
    size = re.findall(r'(\d+)x(\d+)', sh('wm', 'size'))[-1]
    w, h = int(size[0]), int(size[1])
    for _ in range(tries):
        if present(text, exact):
            return
        sh('input', 'swipe', str(w // 2), str(int(h * 0.8)), str(w // 2), str(int(h * 0.5)), '300')
        time.sleep(0.5)
    find(text, timeout=2, exact=exact)


def debuggable(pkg):
    """True if the installed package is debuggable (adb run-as works): the debug build is, the rehearsal and the
    release are not. The package flag and run-as must agree, so a changed dumpsys format can't turn a debug build's
    run-as checks into skips."""
    flags = re.search(r'pkgFlags=\[([^\]]*)\]', sh('dumpsys', 'package', pkg))
    assert flags, f'{pkg} is not installed'
    flag = 'DEBUGGABLE' in flags[1].split()
    runas = subprocess.run(ADB + ['shell', 'run-as', pkg, 'true'], capture_output=True).returncode == 0
    assert flag == runas, f'{pkg}: dumpsys says debuggable={flag}, but run-as {"works" if runas else "fails"}'
    return flag
