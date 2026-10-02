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


def find(text, timeout=15, exact=False):
    end = time.time() + timeout
    while True:
        for n in nodes():
            v = label(n)
            if (v == text) if exact else (text in v):
                return n
        if time.time() > end:
            raise AssertionError(f'not on screen: {text!r}')
        time.sleep(0.7)


def present(text, exact=False):
    return any(((label(n) == text) if exact else (text in label(n))) for n in nodes())


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
