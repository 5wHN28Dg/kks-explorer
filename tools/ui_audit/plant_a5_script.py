"""A5 for a state an evidence script sets up: Walkdown Plant run by a SceneTree script (an apps/plant3d/tests/*_shots.gd
that holds its state with --hold=SECONDS), Godot's accessibility forced on, its AT-SPI tree read in the headless GNOME
session: each node's role, name, description and whether it has the focus. libatspi's cache is cleared before each walk (a held state is read as it is).
Run inside apps/gnome/e2e/headless.sh:
  python3 plant_a5_script.py GODOT_BINARY OUT.json res://tests/NAME.gd [SCRIPT ARGS…]
(repository root: $KKS_REPO or this file's place)"""
import json, os, subprocess, sys, time
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(REPO, 'apps', 'gnome', 'e2e'))
import atspi
from gi.repository import Atspi
G, OUT, SCRIPT, ARGS = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
# the accessibility switches below must reach headless.sh's private bus, never the desktop's
assert os.environ.get('XDG_CONFIG_HOME', '').endswith('/home/config'), 'run under apps/gnome/e2e/headless.sh'


def a11y(on):
    for prop in ('IsEnabled', 'ScreenReaderEnabled'):
        subprocess.run(['gdbus', 'call', '--session', '--dest', 'org.a11y.Bus', '--object-path', '/org/a11y/bus',
                        '--method', 'org.freedesktop.DBus.Properties.Set', 'org.a11y.Status', prop,
                        '<true>' if on else '<false>'])


d0 = Atspi.get_desktop(0)
before = {a.get_process_id() for a in [d0.get_child_at_index(i) for i in range(d0.get_child_count())] if a}
a11y(True)
log = open(OUT + '.log', 'w')
p = subprocess.Popen([G, '--path', os.path.join(REPO, 'apps', 'plant3d'), '--display-driver', 'wayland',
                      '--accessibility', 'always', '--resolution', '1600x900', '--script', SCRIPT, '--'] + ARGS,
                     stdout=log, stderr=subprocess.STDOUT)
res = {'apps': [], 'nodes': []}
try:
    t0 = time.time()
    while time.time() - t0 < 150 and p.poll() is None:
        time.sleep(5)
        d = Atspi.get_desktop(0)
        apps = [a for a in (d.get_child_at_index(i) for i in range(d.get_child_count()))
                if a and a.get_process_id() not in before]
        nodes = []
        for a in apps:
            try:
                a.clear_cache()     # each walk reads the tree as it is now, not libatspi's cached copy
            except Exception:
                pass
            for n in atspi.walk(a, maxdepth=40):
                try:
                    st = n.get_state_set()
                    nodes.append((n.get_role_name(), n.get_name() or '', n.get_description() or '',
                                  bool(st and st.contains(Atspi.StateType.FOCUSED))))
                except Exception:
                    pass
        if nodes:
            res['apps'] = [(a.get_name(), a.get_process_id(), a.get_child_count()) for a in apps]
            res['nodes'] = nodes
        if any(n[3] for n in nodes) and time.time() - t0 > 30:
            break
finally:
    a11y(False)
    p.terminate()
    try:
        p.wait(15)
    except subprocess.TimeoutExpired:
        p.kill()
json.dump(res, open(OUT, 'w'), indent=0, ensure_ascii=False)
print('apps', res['apps'], 'nodes', len(res['nodes']), 'focused', [n for n in res['nodes'] if n[3]])
