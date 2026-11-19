"""UI audit walk of the GNOME app (pass 1, 2026-11): reuses apps/gnome/e2e/test_gnome.py's Plant fixture (server,
sample PDF imported, synthetic tags), joins, visits the screens and dumps the AT-SPI tree (role, name, states,
extents) and a screenshot of each, in one mode per app start: light, dark, high contrast, large text (1.25).
  headless.sh python3 gnome_audit.py APP SERVER IMPORTER OUTDIR [modes]"""
import json, os, shutil, signal, subprocess, sys, time
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
APP, SERVER, IMPORTER, OUT = sys.argv[1:5]
MODES = (sys.argv[5] if len(sys.argv) > 5 else 'light,dark,hc,large').split(',')
sys.argv = [sys.argv[0], APP, SERVER, IMPORTER]
sys.path.insert(0, os.path.join(REPO, 'apps', 'gnome', 'e2e'))
import test_gnome  # noqa: E402
import atspi  # noqa: E402
from gi.repository import Atspi, Gio, GLib  # noqa: E402
import unittest  # noqa: E402

os.makedirs(OUT, exist_ok=True)
STATES = ['FOCUSABLE', 'FOCUSED', 'SENSITIVE', 'ENABLED', 'SELECTABLE_TEXT', 'EDITABLE', 'CHECKED', 'PRESSED',
          'SELECTED', 'MODAL', 'IS_DEFAULT', 'SHOWING']


def dump(a, name):
    rows = []
    for n in atspi.walk(a, maxdepth=90):
        try:
            st = n.get_state_set()
            if not st.contains(Atspi.StateType.SHOWING):
                continue
            c = n.get_component_iface()
            e = c.get_extents(Atspi.CoordType.WINDOW) if c else None
            act = n.get_action_iface()
            acts = [act.get_action_name(i) for i in range(act.get_n_actions())] if act else []
            t = n.get_text_iface()
            txt = Atspi.Text.get_text(t, 0, min(200, t.get_character_count())) if t else None
            font = None
            if t and t.get_character_count() > 0:
                try:
                    at = Atspi.Text.get_text_attributes(t, 0)
                    at = at[0] if isinstance(at, tuple) else at
                    font = {k: at.get(k) for k in ('size', 'family-name', 'weight', 'fg-color', 'bg-color', 'direction') if at and k in at}
                except Exception as ex:
                    font = str(ex)[:60]
            rows.append({'role': n.get_role_name(), 'name': n.get_name() or '', 'desc': n.get_description() or '',
                         'states': [s for s in STATES if hasattr(Atspi.StateType, s) and st.contains(getattr(Atspi.StateType, s))],
                         'ext': [e.x, e.y, e.width, e.height] if e else None, 'actions': acts, 'text': txt, 'font': font})
        except Exception as ex:          # vanished while read
            rows.append({'error': str(ex)[:120]})
    with open(os.path.join(OUT, name + '.json'), 'w') as f:
        json.dump(rows, f, ensure_ascii=False, indent=0)
    return rows


class RD:
    """mutter's RemoteDesktop session: real key presses into the focused window (the headless session has no
    keyboard otherwise)"""
    def __init__(self):
        self.bus = Gio.bus_get_sync(Gio.BusType.SESSION)
        r = self.bus.call_sync('org.gnome.Mutter.RemoteDesktop', '/org/gnome/Mutter/RemoteDesktop',
                               'org.gnome.Mutter.RemoteDesktop', 'CreateSession', None, GLib.VariantType('(o)'),
                               0, 5000, None)
        self.path = r.unpack()[0]
        self.call('Start')

    def call(self, m, args=None):
        return self.bus.call_sync('org.gnome.Mutter.RemoteDesktop', self.path, 'org.gnome.Mutter.RemoteDesktop.Session',
                                  m, args, None, 0, 5000, None)

    def key(self, sym, mods=()):
        for m in mods:
            self.call('NotifyKeyboardKeysym', GLib.Variant('(ub)', (m, True)))
        self.call('NotifyKeyboardKeysym', GLib.Variant('(ub)', (sym, True)))
        self.call('NotifyKeyboardKeysym', GLib.Variant('(ub)', (sym, False)))
        for m in reversed(mods):
            self.call('NotifyKeyboardKeysym', GLib.Variant('(ub)', (m, False)))
        time.sleep(0.25)


TAB, RET, ESC, SHIFT, SPACE, DOWN = 0xff09, 0xff0d, 0xff1b, 0xffe1, 0x20, 0xff54


def focused(a):
    for n in atspi.walk(a, maxdepth=90):
        try:
            if n.get_state_set().contains(Atspi.StateType.FOCUSED):
                c = n.get_component_iface()
                e = c.get_extents(Atspi.CoordType.WINDOW) if c else None
                return f'{n.get_role_name()} {n.get_name()!r} {[e.x, e.y, e.width, e.height] if e else None}'
        except Exception:
            pass
    return None


class Audit(test_gnome.Plant):
    def shot(self, pid, path, name):
        if os.path.exists(path):
            os.remove(path)
        time.sleep(1.2)
        os.kill(pid, signal.SIGUSR1)
        for _ in range(40):
            time.sleep(0.25)
            if os.path.exists(path):
                break
        time.sleep(0.4)
        if os.path.exists(path):
            shutil.copy(path, os.path.join(OUT, name + '.png'))

    def step(self, a, pid, path, mode, name):
        self.shot(pid, path, f'{mode}-{name}')
        dump(a, f'{mode}-{name}')

    def visit(self, mode, extra):
        path = os.path.join(self.dir, f'shot-{mode}.png')
        a = self.start_app('audit', KKS_SHOT_ON_SIGNAL=path, KKS_SYNC_EVERY='600000', **extra)
        pid = self.apps[-1].pid
        if mode == MODES[0]:
            self.step(a, pid, path, mode, '00-setup')
            self.join(a)
        else:
            atspi.find(a, 'list item', contains='Sample sheet', timeout=30)
        time.sleep(2)
        self.step(a, pid, path, mode, '01-main')
        q = atspi.find(a, 'entry', contains='Search equipment')
        atspi.set_text(q, 'lab70aa500')
        time.sleep(1.5)
        self.step(a, pid, path, mode, '02-search-lower')
        atspi.set_text(q, '11 lab70 aa500')
        time.sleep(1.5)
        self.step(a, pid, path, mode, '02b-search-spaces')
        atspi.set_text(q, 'LAB70AA500')
        time.sleep(1.5)
        try:
            atspi.click(atspi.find(a, 'button', name='11LAB70AA500'))
            time.sleep(2)
            self.step(a, pid, path, mode, '03-panel')
            atspi.click(atspi.find(a, 'button', name='Edit'))
            time.sleep(1)
            atspi.set_text(atspi.find(a, 'text', name='Notes'), 'مضخة التغذية 11LAB70AA500 تعمل ' + mode)
            time.sleep(0.5)
            self.step(a, pid, path, mode, '04-edit')
            atspi.click(atspi.find(a, 'button', name='Save'))
            time.sleep(2)
            self.step(a, pid, path, mode, '04b-saved-arabic')
        except AssertionError as e:
            print(mode, 'panel:', e)
        for nav, page in (('Procedures', 'procs'), ('Equipment by system', 'systems'),
                          ('Coverage', 'coverage'), ('Learning', 'learning'),
                          ('Review queue', 'review'), ("Connectors on this sheet", 'links'),
                          ("Notes on this sheet", 'notes')):
            try:
                atspi.click_named(a, 'button', nav, timeout=8, maxdepth=90)
                time.sleep(1.5)
                self.step(a, pid, path, mode, f'10-{page}')
                atspi.click(atspi.find(a, 'button', name='Back', timeout=8))
                time.sleep(0.8)
            except AssertionError as e:
                print(mode, nav, e)
        try:
            atspi.click_named(a, 'button', 'Manage', timeout=8, maxdepth=90)
            time.sleep(1)
            self.step(a, pid, path, mode, '20-manage')
            for sub in ('Approvals', 'My proposals', 'History', 'People', 'Devices', 'Account'):
                try:
                    atspi.click_named(a, 'button', sub, timeout=8, maxdepth=90)
                    time.sleep(1.5)
                    self.step(a, pid, path, mode, f'21-{sub.replace(" ", "_")}')
                    atspi.click(atspi.find(a, 'button', name='Back', timeout=8))
                    time.sleep(0.8)
                except AssertionError as e:
                    print(mode, sub, e)
        except AssertionError as e:
            print(mode, 'manage', e)
        # keyboard only (first mode): Tab through the main window from the start, Escape on a page
        if mode == MODES[0]:
            try:
                rd = RD()
                order = []
                for _ in range(40):
                    rd.key(TAB)
                    order.append(focused(a))
                with open(os.path.join(OUT, f'{mode}-keyboard-tab-order.json'), 'w') as f:
                    json.dump(order, f, indent=0, ensure_ascii=False)
                self.shot(pid, path, f'{mode}-30-focus-visible')
                # Escape on a pushed page
                atspi.click_named(a, 'button', 'Coverage', timeout=8, maxdepth=90)
                time.sleep(1)
                rd.key(ESC)
                time.sleep(1)
                with open(os.path.join(OUT, f'{mode}-escape.txt'), 'w') as f:
                    f.write('after Escape on Coverage, Back button showing: %s\n' % bool(atspi.find_all(a, 'button', name='Back')))
                    f.write('focused: %s\n' % focused(a))
            except Exception as e:
                print('keyboard:', repr(e))
        p = self.apps.pop()
        p.terminate()
        p.wait(10)
        shutil.copy(f'/tmp/kks-gnome-e2e-audit.log', os.path.join(OUT, f'{mode}-app.log'))

    def test_audit(self):
        envs = {'light': {'ADW_DEBUG_COLOR_SCHEME': 'prefer-light'},
                'dark': {'ADW_DEBUG_COLOR_SCHEME': 'prefer-dark'},
                'hc': {'ADW_DEBUG_COLOR_SCHEME': 'prefer-light', 'ADW_DEBUG_HIGH_CONTRAST': '1'},
                'hcdark': {'ADW_DEBUG_COLOR_SCHEME': 'prefer-dark', 'ADW_DEBUG_HIGH_CONTRAST': '1'},
                'large': {'ADW_DEBUG_COLOR_SCHEME': 'prefer-light'},
                'noanim': {'ADW_DEBUG_COLOR_SCHEME': 'prefer-light'}}
        # gsettings below must reach headless.sh's private settings, never the desktop's
        assert os.environ.get('XDG_CONFIG_HOME', '').endswith('/home/config'), 'run under apps/gnome/e2e/headless.sh'
        for mode in MODES:
            if mode == 'large':
                subprocess.run(['gsettings', 'set', 'org.gnome.desktop.interface', 'text-scaling-factor', '1.25'])
                print('text-scaling-factor now', subprocess.run(['gsettings', 'get', 'org.gnome.desktop.interface',
                      'text-scaling-factor'], capture_output=True, text=True).stdout.strip())
            try:
                self.visit(mode, envs[mode])
            finally:
                if mode == 'large':
                    subprocess.run(['gsettings', 'reset', 'org.gnome.desktop.interface', 'text-scaling-factor'])


if __name__ == '__main__':
    unittest.main(argv=[sys.argv[0], 'Audit'], verbosity=2)
