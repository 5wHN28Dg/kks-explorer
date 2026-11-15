"""A5: Walkdown Plant with Godot's accessibility forced on, its AT-SPI tree read in the headless GNOME session.
Run inside apps/gnome/e2e/headless.sh: python3 plant_a5.py GODOT_BINARY OUT.json   (repository root: $KKS_REPO or this
file's place)"""
import json, os, subprocess, sys, time
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'apps', 'gnome', 'e2e'))
import atspi
from gi.repository import Atspi
G, OUT = sys.argv[1], sys.argv[2]
# the accessibility switches below must reach headless.sh's private bus, never the desktop's
assert os.environ.get('XDG_CONFIG_HOME', '').endswith('/home/config'), 'run under apps/gnome/e2e/headless.sh'
before = {a.get_process_id() for a in [Atspi.get_desktop(0).get_child_at_index(i) for i in range(Atspi.get_desktop(0).get_child_count())] if a}
subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.a11y.Bus', '--object-path', '/org/a11y/bus', '--method',
                'org.freedesktop.DBus.Properties.Set', 'org.a11y.Status', 'IsEnabled', '<true>'])
subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.a11y.Bus', '--object-path', '/org/a11y/bus', '--method',
                'org.freedesktop.DBus.Properties.Set', 'org.a11y.Status', 'ScreenReaderEnabled', '<true>'])
log = open(OUT + '.log', 'w')
p = subprocess.Popen([G, '--path', os.path.join(REPO, 'apps', 'plant3d'), '--display-driver', 'wayland',
                      '--accessibility', 'always', '--resolution', '1600x900', '--', '--quality=lean+vis', '--panels=card:30PAC10AP001'],
                     stdout=log, stderr=subprocess.STDOUT)
res = {'apps': [], 'nodes': []}
try:
    t0 = time.time()
    while time.time() - t0 < 150:
        time.sleep(5)
        d = Atspi.get_desktop(0)
        apps = []
        for i in range(d.get_child_count()):
            a = d.get_child_at_index(i)
            if a and a.get_process_id() not in before:
                apps.append(a)
        res['apps'] = [(a.get_name(), a.get_process_id(), a.get_child_count()) for a in apps]
        nodes = []
        for a in apps:
            for n in atspi.walk(a, maxdepth=40):
                try:
                    nodes.append((n.get_role_name(), n.get_name() or ''))
                except Exception:
                    pass
        res['nodes'] = nodes
        if len(nodes) > 30 and time.time() - t0 > 60:
            break
finally:
    for prop in ('IsEnabled', 'ScreenReaderEnabled'):
        subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.a11y.Bus', '--object-path', '/org/a11y/bus', '--method',
                        'org.freedesktop.DBus.Properties.Set', 'org.a11y.Status', prop, '<false>'])
    p.terminate()
    try:
        p.wait(15)
    except subprocess.TimeoutExpired:
        p.kill()
json.dump(res, open(OUT, 'w'), indent=0, ensure_ascii=False)
print('apps', res['apps'], 'nodes', len(res['nodes']))
