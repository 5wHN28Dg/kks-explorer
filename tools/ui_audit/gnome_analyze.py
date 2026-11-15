"""Summarise gnome_audit.py's AT-SPI dumps: targets under 24 x 24 px (T3), unnamed controls (A2) and overlapping
targets (T2), per screen. Run: python3 gnome_analyze.py OUTDIR   (the OUTDIR gnome_audit.py wrote)"""
import json, glob, os, sys, collections
D = sys.argv[1]
TARGET = {'push button', 'button', 'toggle button', 'check box', 'radio button', 'entry', 'text', 'password text', 'link',
          'combo box', 'menu item', 'spin button', 'slider', 'switch', 'page tab', 'list item', 'menu button'}
small = collections.OrderedDict(); unnamed = collections.OrderedDict(); overlaps = collections.OrderedDict()
for f in sorted(glob.glob(os.path.join(D, '*.json'))):
    if 'keyboard' in f: continue
    rows = [r for r in json.load(open(f)) if 'role' in r and r.get('ext')]
    t = [r for r in rows if r['role'] in TARGET and ('FOCUSABLE' in r['states'] or r['actions'])]
    for r in t:
        x, y, w, h = r['ext']
        if w <= 0 or h <= 0: continue
        if (w < 24 or h < 24) and r['role'] != 'list item':
            small.setdefault((r['role'], r['name'][:50], w, h), []).append(os.path.basename(f)[:-5])
        if not r['name'].strip() and r['role'] not in ('list item', 'text', 'entry'):
            unnamed.setdefault((r['role'], tuple(r['ext'])), []).append(os.path.basename(f)[:-5])
    leaf = [r for r in t if r['role'] != 'list item' and r['ext'][2] > 0]
    for i, a in enumerate(leaf):
        for b in leaf[i+1:]:
            ax, ay, aw, ah = a['ext']; bx, by, bw, bh = b['ext']
            ix = min(ax+aw, bx+bw) - max(ax, bx); iy = min(ay+ah, by+bh) - max(ay, by)
            if ix > 0 and iy > 0 and not (ax >= bx and ay >= by and ax+aw <= bx+bw and ay+ah <= by+bh) and not (bx >= ax and by >= ay and bx+bw <= ax+aw and by+bh <= ay+ah):
                overlaps.setdefault((a['role'], a['name'][:30], b['role'], b['name'][:30]), []).append(os.path.basename(f)[:-5])
print('== targets under 24 px'); [print(k, v[:3], len(v)) for k, v in small.items()]
print('== unnamed'); [print(k, v[:3]) for k, v in unnamed.items()]
print('== partial overlaps'); [print(k, v[:3]) for k, v in overlaps.items()]
