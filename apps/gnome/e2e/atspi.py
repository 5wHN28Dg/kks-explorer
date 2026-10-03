"""Driving the GNOME app the way a screen-reader or keyboard user would: through its accessibility tree (AT-SPI)."""
import os, time
import gi
gi.require_version('Atspi', '2.0')
from gi.repository import Atspi


def app(name, timeout=15):
    t0 = time.time()
    while time.time() - t0 < timeout:
        desk = Atspi.get_desktop(0)
        for i in range(desk.get_child_count()):
            a = desk.get_child_at_index(i)
            if a and a.get_name() == name:
                return a
        time.sleep(0.3)
    raise AssertionError(f'application {name} not on the accessibility bus')


def walk(node, depth=0, maxdepth=60):
    yield node
    if depth >= maxdepth:
        return
    try:
        n = node.get_child_count()
    except Exception:
        return
    for i in range(n):
        c = node.get_child_at_index(i)
        if c is not None:
            yield from walk(c, depth + 1, maxdepth)


def find(root, role=None, name=None, contains=None, timeout=10, showing=True):
    t0 = time.time()
    while True:
        for n in walk(root):
            try:
                if role and n.get_role_name() != role:
                    continue
                nm = n.get_name() or ''
                if name is not None and nm != name:
                    continue
                if contains is not None and contains not in nm:
                    continue
                if showing and not n.get_state_set().contains(Atspi.StateType.SHOWING):
                    continue
                return n
            except Exception:
                continue
        if time.time() - t0 > timeout:
            raise AssertionError(f'no {role} named {name or contains!r}')
        time.sleep(0.3)


def find_all(root, role=None, contains=None):
    out = []
    for n in walk(root):
        try:
            if role and n.get_role_name() != role:
                continue
            if contains and contains not in (n.get_name() or ''):
                continue
            if n.get_state_set().contains(Atspi.StateType.SHOWING):
                out.append(n)
        except Exception:
            pass
    return out


def set_text(node, text):
    et = node.get_editable_text_iface()
    if et is None:   # an AdwEntryRow: the editable text is a child
        for c in walk(node):
            if c is not node and c.get_editable_text_iface() is not None:
                et = c.get_editable_text_iface(); node = c
                break
    n = node.get_text_iface().get_character_count() if node.get_text_iface() else 0
    if n:
        et.delete_text(0, n)
    et.insert_text(0, text, len(text.encode()))


def click(node):
    act = node.get_action_iface()
    for i in range(act.get_n_actions()):
        if act.get_action_name(i) in ('click', 'activate', 'press'):
            return act.do_action(i)
    return act.do_action(0)


def dump(root, maxdepth=25):
    for n in walk(root, maxdepth=maxdepth):
        try:
            print(n.get_role_name(), repr(n.get_name()))
        except Exception:
            pass


def family(pid):
    """pid and its descendants (`flatpak run` starts the app as a grandchild: flatpak-app.sh)"""
    kids = {}
    for d in os.listdir('/proc'):
        if d.isdigit():
            try:
                with open(f'/proc/{d}/stat') as f:
                    kids.setdefault(int(f.read().rsplit(')', 1)[1].split()[1]), []).append(int(d))
            except (OSError, IndexError, ValueError):
                pass
    out, todo = set(), [pid]
    while todo:
        p = todo.pop()
        out.add(p)
        todo += kids.get(p, [])
    return out


def apps_named(name):
    """every application called `name` on the accessibility bus now"""
    desk = Atspi.get_desktop(0)
    out = []
    for i in range(desk.get_child_count()):
        try:
            a = desk.get_child_at_index(i)
            if a and a.get_name() == name:
                out.append(a)
        except Exception:
            pass
    return out


def app_pids():
    """the process IDs the accessibility bus shows now"""
    desk = Atspi.get_desktop(0)
    out = set()
    for i in range(desk.get_child_count()):
        try:
            out.add(desk.get_child_at_index(i).get_process_id())
        except Exception:
            pass
    return out


def app_pid(pid, timeout=15, name=None, before=()):
    """the app started as `pid`. A Flatpak app shows the PID of its sandbox's accessibility proxy instead, which is not
    a descendant: then the new application called `name` that wasn't there `before` the start."""
    t0 = time.time()
    while time.time() - t0 < timeout:
        desk = Atspi.get_desktop(0)
        pids = family(pid)
        for i in range(desk.get_child_count()):
            a = desk.get_child_at_index(i)
            try:
                if a and (a.get_process_id() in pids or
                          (name and a.get_name() in ((name,) if isinstance(name, str) else name) and a.get_process_id() not in before)):
                    return a
            except Exception:
                pass
        time.sleep(0.3)
    raise AssertionError(f'no application with pid {pid} on the accessibility bus')
