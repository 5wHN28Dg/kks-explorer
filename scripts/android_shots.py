"""Evidence for #449 on the emulator: Setup → Join through a server, default, dark, and font scale 2.0 (scrolled to the line)."""
import os, subprocess, sys, time
sys.path.insert(0, os.path.expanduser('~/kks-work/forgot-password/android/app2/e2e'))
import adbui as ui
apk, out = sys.argv[1], sys.argv[2]; os.makedirs(out, exist_ok=True)
assert os.environ['ANDROID_SERIAL'].startswith('emulator-')
PKG = 'io.github.walkdown'
subprocess.run(ui.ADB + ['uninstall', PKG], capture_output=True)
assert 'Success' in subprocess.run(ui.ADB + ['install', '-t', apk], capture_output=True, text=True).stdout
def shot(name):
    time.sleep(2)
    with open(os.path.join(out, name + '.png'), 'wb') as f:
        f.write(subprocess.run(ui.ADB + ['exec-out', 'screencap', '-p'], capture_output=True).stdout)
for mode, scale in (('no', '1.0'), ('yes', '1.0'), ('no', '2.0'), ('yes', '2.0')):
    ui.sh('cmd', 'uimode', 'night', mode); ui.sh('settings', 'put', 'system', 'font_scale', scale)
    ui.fresh_app(PKG); time.sleep(3)
    ui.tap('Join through a server', exact=True)
    ui.scroll_to("Forgot your password?")
    shot(f'android-join-server-{"dark" if mode == "yes" else "light"}-font{scale}')
ui.sh('cmd', 'uimode', 'night', 'no'); ui.sh('settings', 'put', 'system', 'font_scale', '1.0')
