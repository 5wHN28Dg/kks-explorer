#!/usr/bin/env python3
"""Re-read the tag boxes/bubbles of a sheet that is already in the app with the current reader, and merge the result
into plant-data/tags.json conservatively (then: app.py publish-data), keeping ids, hand-verified statuses and review decisions.

Used after a reader fix (e.g. the dropped-suffix fix, 2026-09-25) so existing sheets benefit without a re-import,
which would re-read everything and send hand-verified tags back to the review queue.

Rules (anything else is only reported, never changed):
  - auto/verified tag, same KKS, no suffix before, suffix now (conf >= 0.3)      -> suffix added
  - review tag that now reads as a full tag (conf >= 0.3)                         -> suggestion set (for triage)
Container ids are the detection pair index, which a reader change doesn't affect; boxes are also compared, and the
sheet is skipped if they don't line up (wrong source PDF or rotation).

  .venv/bin/python tools/reread_tags.py SHEET_ID source.pdf ROTATION [--apply]
Without --apply it only prints what would change."""
import json, os, sys, tempfile
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    apply = '--apply' in sys.argv
    sid, src, rot = args[0], args[1], int(args[2])
    from extractor.orient import rotated_copy
    from extractor.reader3 import read_sheet
    from extractor.extract_sheet import load_lib
    import pymupdf
    data = os.path.join(HERE, 'plant-data')   # the working copy; publish with app.py publish-data
    tags_p = os.path.join(data, 'tags.json')
    tags = json.load(open(tags_p))
    sheet = next(s for s in json.load(open(os.path.join(data, 'sheets.json'))) if s['id'] == sid)
    tmp = tempfile.mkdtemp(); pdf = os.path.join(tmp, 'r.pdf'); rotated_copy(src, pdf, rot)
    Z = sheet['w'] / pymupdf.open(pdf)[0].rect.width
    new = {f'{sid}:{t["id"]}': t for t in read_sheet(pdf, load_lib())[0]}
    mine = [t for t in tags if t['sheet'] == sid and t['id'] in new]
    off = [max(abs(a - b * Z) for a, b in zip(t['bbox'], new[t['id']]['bbox'])) for t in mine]
    if not mine or sorted(off)[len(off) // 2] > 3:
        sys.exit(f'{sid}: boxes do not line up with the stored tags (median offset {sorted(off)[len(off)//2] if off else "n/a"} px); '
                 'wrong PDF or rotation. Nothing changed.')
    changes, report = [], []
    for t in mine:
        n = new[t['id']]
        nk, ns = n.get('kks'), n.get('suffix') or ''
        if n['conf'] < 0.3 or not nk:
            if (nk or '') + ns != (t['kks'] or '') + (t['suffix'] or '') and t['status'] != 'review':
                report.append(f'  {t["id"]:<12} {t["status"]:<8} {(t["kks"] or "-") + t["suffix"]:<18} now reads {n["top"]}/{n["bottom"]} (conf {n["conf"]}): unchanged')
            continue
        if t['status'] in ('auto', 'verified') and t['kks'] == nk and not t['suffix'] and ns:
            changes.append((t, f'suffix {ns} added'))
            if apply:
                t['suffix'] = ns; t['read'] = [n['top'], n['bottom']]
                t['note'] = (t['note'] + '; ' if t['note'] else '') + f'suffix {ns} recovered by re-read 2026-09-25'
        elif t['status'] == 'review' and (nk + ns) != (t['kks'] or '') + (t['suffix'] or ''):
            changes.append((t, f'review suggestion {nk}{ns}'))
            if apply:
                t['suggestion'] = {'kks': nk + ns, 'isa': n.get('isa'), 'note': 'current reader reads it this way'}
        elif (nk + ns) != (t['kks'] or '') + (t['suffix'] or ''):
            report.append(f'  {t["id"]:<12} {t["status"]:<8} {(t["kks"] or "-") + t["suffix"]:<18} now reads {nk}{ns} (conf {n["conf"]}): unchanged, check')
    have = {t['id'] for t in mine}
    for i, n in new.items():  # confidently read now, but no stored tag: removed as a non-tag earlier?
        if i not in have and n.get('kks') and n['conf'] >= 0.3:
            report.append(f'  {i:<12} (none)   {"-":<18} now reads {n.get("isa") or ""} {n["kks"]}{n.get("suffix") or ""} (conf {n["conf"]}): no stored tag, check')
    print(f'{sid}: {len(mine)} container tags compared, {len(changes)} change(s){"" if apply else " (dry run)"}')
    for t, what in changes:
        print(f'  {t["id"]:<12} {t["status"]:<8} {(t["kks"] or "-") + (t["suffix"] if not apply else ""):<18} {what}')
    if report:
        print(' other differences (not applied):'); print('\n'.join(report))
    if apply and changes:
        with open(tags_p + '.tmp', 'w') as f:
            json.dump(tags, f)
        os.replace(tags_p + '.tmp', tags_p)


if __name__ == '__main__':
    main()
