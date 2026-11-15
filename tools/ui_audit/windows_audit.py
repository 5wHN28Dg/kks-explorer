"""UI audit helpers for Walkdown Windows in kks-win11: uiadrive scripts (test_windows.ui), a UIA dump with rectangles
(uiadump.ps1), virsh screenshots, and the T3/T2/A2 checks from the dump.
A library, used from a Python shell with KKS_VM_IP (the VM's address, `virsh domifaddr`) and optionally KKS_VM (the
libvirt domain, default kks-win11) set; uiadrive in the VM must be built with uiadrive-rects.patch applied. Output in
$KKS_AUDIT_OUT (default $TMPDIR/ui-audit-windows)."""
import base64, os, re, subprocess, sys, time
VMIP = os.environ['KKS_VM_IP']          # the Windows VM's address (virsh domifaddr)
REPO = os.environ.get('KKS_REPO') or os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.argv = ['x', VMIP]
sys.path.insert(0, REPO + '/apps/windows/e2e')
import test_windows as tw  # noqa
OUT = os.environ.get('KKS_AUDIT_OUT', os.path.join(os.environ.get('TMPDIR', '/tmp'), 'ui-audit-windows'))
os.makedirs(OUT, exist_ok=True)
DESTRUCTIVE = re.compile(r'^(Delete|Remove|Discard|Sign out|Leave|Reject|Revert|Restore|Withdraw|Refuse|Not a tag|Clear removed)\b', re.I)
vm = tw.vm


def run(name, lines, **kw):
    ok, log = tw.ui(name + '.uia', lines, **kw)
    if not ok:
        print('SCRIPT FAILED', name, log[-1500:])
    return ok, log


def shot(name):
    p = os.path.join(OUT, name + '.ppm')
    subprocess.run(['virsh', 'screenshot', os.environ.get('KKS_VM', 'kks-win11'), p], capture_output=True)
    from PIL import Image
    Image.open(p).save(os.path.join(OUT, name + '.png'))
    os.remove(p)


def dump(tag):
    """uiadrive (a copy with rectangles, uiadrive-rects.cpp) dumps every element of the app's windows"""
    ok, log = run('dump-' + tag, ['dump'])
    out = os.path.join(OUT, 'dump-%s.tsv' % tag)
    rows = ['dpi\t96']
    for l in log.splitlines():
        i = l.find('RECT\t')
        if i >= 0:
            f = l[i + 5:].split('\t')
            rows.append('\t'.join(f))
    with open(out, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(rows) + '\n')
    return out


def check(tag, quiet=False):
    """shot + dump + T3 (24 logical px) / T2 overlap and destructive gap / A2 unnamed for the current screen"""
    shot(tag)
    path = dump(tag)
    rows = open(path, encoding='utf-8-sig').read().splitlines()
    dpi = int(rows[0].split('\t')[1]) if rows and rows[0].startswith('dpi') else 96
    s = dpi / 96
    els = []
    for r in rows[1:]:
        f = r.split('\t')
        if f[0] == 'WINDOW' or len(f) < 6:
            continue
        typ, name, rect, focus, off = f[0].replace('ControlType.', ''), f[1], f[2], f[3], f[4]
        x, y, w, h = map(int, rect.split(','))
        if off == 'True' or w <= 0 or h <= 0:
            continue
        els.append((typ, name, (x, y, x + w, y + h), focus))
    targets = [e for e in els if e[0] in ('Button', 'CheckBox', 'RadioButton', 'Edit', 'ComboBox', 'ListItem', 'Hyperlink', 'MenuItem', 'TabItem', 'Slider', 'TreeItem')]
    issues = []
    for typ, name, b, _ in targets:
        w, h = (b[2] - b[0]) / s, (b[3] - b[1]) / s
        if w < 24 or h < 24:
            issues.append(f'T3 {w:.0f}x{h:.0f}px {typ} {name!r} {b}')
    for i in range(len(targets)):
        for j in range(i + 1, len(targets)):
            a, b = targets[i][2], targets[j][2]
            ix = min(a[2], b[2]) - max(a[0], b[0]); iy = min(a[3], b[3]) - max(a[1], b[1])
            if ix > 0 and iy > 0:
                if targets[i][0] == 'ListItem' or targets[j][0] == 'ListItem':
                    continue
                issues.append(f'T2 overlap: {targets[i][1]!r} {a} / {targets[j][1]!r} {b}')
            elif DESTRUCTIVE.match(targets[i][1]) or DESTRUCTIVE.match(targets[j][1]):
                gap = max(-ix, -iy) / s
                if gap < 8 and max(-ix, -iy) < 200:
                    issues.append(f'T2 destructive gap {gap:.0f}px: {targets[i][1]!r} {a} / {targets[j][1]!r} {b}')
    for typ, name, b, focus in els:
        if typ in ('Button', 'CheckBox', 'RadioButton', 'Edit', 'ComboBox', 'List', 'Tree', 'Slider') and not name.strip():
            issues.append(f'A2 unnamed {typ} {b}')
    with open(os.path.join(OUT, tag + '.issues.txt'), 'w') as f:
        f.write(f'dpi {dpi}\n' + '\n'.join(issues) + '\n')
    if not quiet:
        print(f'== {tag}: {len(targets)} targets, {len(issues)} issues (dpi {dpi})')
        for l in issues[:40]:
            print('  ', l)
    return els, issues
