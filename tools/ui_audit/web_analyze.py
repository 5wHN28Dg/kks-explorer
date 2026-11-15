"""Summarise audit_web.py's data: python3 web_analyze.py RUNDIR [engine] -> per screen the fails by rule."""
import json, os, re, sys, glob, collections
RUN = sys.argv[1]; ENG = sys.argv[2] if len(sys.argv) > 2 else None
out = []
summary = collections.defaultdict(lambda: collections.defaultdict(set))
for fn in sorted(glob.glob(os.path.join(RUN, 'data', '*.json'))):
    if fn.endswith('-probes.json'): continue
    r = json.load(open(fn)); m = r.get('m')
    if ENG and r['engine'] != ENG: continue
    key = f"{r['engine']}/{r['layout']}/{r['scheme']}/{r['state']}"
    if not m: out.append(f'{key}: ERROR {r.get("err")}'); continue
    phone = m['iw'] < 600; lines = []
    if r['layout'] in ('phone', 'desk'):
        lim = 48 if phone else 24
        inview = lambda t: t['x'] + t['w'] / 2 >= 0 and t['y'] + t['h'] / 2 >= 0 and t['x'] + t['w'] / 2 < m['iw'] and t['y'] + t['h'] / 2 < m['ih']
        live = [t for t in m['targets'] if t.get('hit', True) or not inview(t)]
        small = [t for t in live if (t['w'] < lim or t['h'] < lim) and not t['inline'] and not t['onDrawing'] and not (t.get('tabindex') == '-1' and not t.get('pointer'))]
        if small:
            lines.append(f'  T{"1" if phone else "3"} small targets ({len(small)}/{len(m["targets"])}): ' + '; '.join(
                f"{t['name'][:22]!r}<{t['tag']}> {t['w']:.0f}x{t['h']:.0f}" for t in small[:14]))
            summary['T1' if phone else 'T3'][r['state']].add(r['engine'])
        if m['overlaps']:
            lines.append(f'  T2 overlaps ({len(m["overlaps"])}): ' + '; '.join(f'{a} / {b} {x}x{y}' for a, b, x, y in m['overlaps'][:6]))
            summary['T2'][r['state']].add(r['engine'])
        nonfocus = [t for t in live if not t['focusable'] and not t['onDrawing'] and t.get('pointer') and t['tag'] not in ('label', 'a', 'summary', 'input')]
        if nonfocus:
            lines.append(f'  A1 clickable, not focusable ({len(nonfocus)}): ' + '; '.join(f"{t['name'][:22]!r}<{t['tag']}.{t['cls'][:12]}>" for t in nonfocus[:8]))
            summary['A1'][r['state']].add(r['engine'])
    low = [t for t in m['texts'] if not t['disabled'] and not t['hasImg'] and t['ratio'] < (3 if t['large'] else 4.5)]
    if low:
        lines.append(f'  K1 low contrast ({len(low)}): ' + '; '.join(f"{t['t'][:20]!r} {t['ratio']} {t['color']} on {t['bg']} {t['fs']}px" for t in low[:8]))
        summary['K1'][r['state']].add(r['engine'])
    if phone:
        codes = [t for t in m['texts'] if t['code'] and not t['disabled'] and t['ratio'] < 7]
        if codes:
            lines.append(f'  K2 codes under 7:1 ({len(codes)}): ' + '; '.join(f"{t['t'][:20]!r} {t['ratio']}" for t in codes[:6]))
            summary['K2'][r['state']].add(r['engine'])
        tiny = [t for t in m['texts'] if t['fs'] < 12]
        body = [t for t in m['texts'] if 12 <= t['fs'] < 14]
        if tiny:
            lines.append(f'  S1 text under 12px ({len(tiny)}): ' + '; '.join(f"{t['t'][:18]!r} {t['fs']}" for t in tiny[:8])); summary['S1<12'][r['state']].add(r['engine'])
        if body:
            lines.append(f'  S1 text 12-14px ({len(body)}): ' + '; '.join(f"{t['t'][:18]!r} {t['fs']}" for t in body[:8])); summary['S1<14'][r['state']].add(r['engine'])
    else:
        tiny = [t for t in m['texts'] if t['fs'] < 11]
        if tiny: lines.append(f'  S1 desk text under 11px: ' + '; '.join(f"{t['t'][:18]!r} {t['fs']}" for t in tiny[:6])); summary['S1desk'][r['state']].add(r['engine'])
        bodyfs = collections.Counter(t['fs'] for t in m['texts'])
        lines.append(f'  font sizes: {dict(bodyfs.most_common(5))}')
    f16 = [f for f in m['fields'] if f['fs'] < 16]
    if f16 and phone:
        lines.append(f'  S1 fields under 16px ({len(f16)}): ' + '; '.join(f"{f['name'][:20]!r} {f['fs']}" for f in f16[:5])); summary['S1field'][r['state']].add(r['engine'])
    nolab = [f for f in m['fields'] if not f['hasLabel']]
    if nolab: lines.append(f'  A2 fields without label: ' + '; '.join(f"{f['name'][:20]!r}" for f in nolab[:5])); summary['A2field'][r['state']].add(r['engine'])
    ell = [t for t in m['texts'] if t['ellipsis']]
    if ell: lines.append(f'  S3 ellipsised: ' + '; '.join(repr(t['t'][:30]) for t in ell[:5])); summary['S3'][r['state']].add(r['engine'])
    sel = [t for t in m['texts'] if t['code'] and t['userSelect'] == 'none']
    if sel: lines.append(f'  C1 codes not selectable: ' + '; '.join(repr(t['t'][:20]) for t in sel[:5])); summary['C1'][r['state']].add(r['engine'])
    if r['layout'] in ('zoom200', 'w320') and (m['hScroll'] or m['wide']):
        lines.append(f'  S2/L2 horizontal overflow: scrollWidth {m["scrollWidth"]} > {m["iw"]}; ' + '; '.join(m['wide'][:6])); summary['S2'][r['state']].add(r['engine'])
    a = r.get('aria', '')
    unnamed = [l.strip() for l in a.splitlines() if re.match(r'\s*- (button|link|textbox|combobox|checkbox|img|spinbutton)( \[|:|$)', l)]
    if unnamed: lines.append(f'  A2 unnamed in ARIA snapshot ({len(unnamed)}): ' + '; '.join(unnamed[:6])); summary['A2'][r['state']].add(r['engine'])
    if lines: out.append(key + f'  ({len(m["targets"])} targets)\n' + '\n'.join(lines))
print('\n'.join(out))
print('\n==== summary: rule -> state -> engines')
for rule, d in sorted(summary.items()):
    print(rule, {k: sorted(v) for k, v in d.items()})
