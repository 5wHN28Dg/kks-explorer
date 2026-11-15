"""Summarise plant_audit.gd's Control dumps: input targets under 24 px (desk_*) or 48 dp (phone_*, dp = canvas px x
0.457, the policy's factor), font sizes under the floor, and overlapping targets. Run: python3 plant_analyze.py OUTDIR"""
import json, glob, os, sys, collections
D = sys.argv[1]
INPUT = {'Button', 'CheckBox', 'CheckButton', 'OptionButton', 'MenuButton', 'LineEdit', 'TextEdit', 'HSlider', 'VSlider',
         'SpinBox', 'LinkButton', 'TextureButton', 'ColorPickerButton', 'TabBar', 'ItemList', 'Tree'}
for kind, f_dp in (('desk', None), ('phone', 0.457)):
    small = collections.OrderedDict(); fonts = collections.Counter(); low_font = collections.OrderedDict(); overlaps = collections.OrderedDict()
    canv = None
    for f in sorted(glob.glob(os.path.join(D, kind + '_*.json'))):
        j = json.load(open(f)); canv = (j['canvas'], j['window']); scr = os.path.basename(f)[len(kind) + 1:-5]
        ins = [c for c in j['controls'] if c['cls'] in INPUT and not c.get('disabled')]
        for c in ins:
            w, h = c['rect'][2], c['rect'][3]
            if f_dp: w, h = w * f_dp, h * f_dp; lim = 48
            else: lim = 24
            if w < lim - 0.01 or h < lim - 0.01:
                small.setdefault((c['cls'], c.get('text', '')[:28], round(w), round(h)), []).append(scr)
        for c in j['controls']:
            if 'font_size' in c and c.get('text', '').strip():
                fs = c['font_size'] * (f_dp if f_dp else 1)
                fonts[round(fs, 1)] += 1
                if (f_dp and fs < 12) or (not f_dp and fs < 13):
                    low_font.setdefault((c['cls'], c['text'][:40], round(fs, 1)), []).append(scr)
        for i, a in enumerate(ins):
            for b in ins[i+1:]:
                ax, ay, aw, ah = a['rect']; bx, by, bw, bh = b['rect']
                if min(ax+aw, bx+bw) - max(ax, bx) > 0.5 and min(ay+ah, by+bh) - max(ay, by) > 0.5:
                    overlaps.setdefault((a.get('text', '')[:20], b.get('text', '')[:20]), []).append(scr)
    print('=====', kind, 'canvas/window', canv)
    print('-- targets under', 48 if f_dp else 24, '(dp)' if f_dp else '(px)', len(small))
    for k, v in list(small.items())[:45]: print(' ', k, v[:3], len(v))
    print('-- font sizes', sorted(fonts.items()))
    print('-- text under limit', len(low_font))
    for k, v in list(low_font.items())[:25]: print(' ', k, v[:2])
    print('-- overlapping inputs', len(overlaps))
    for k, v in list(overlaps.items())[:15]: print(' ', k, v[:3])
