#!/usr/bin/env python3
"""Add a P&ID to the explorer (also used by Manage → Drawings in the app).
Usage:  .venv/bin/python import_sheet.py path/to/drawing.pdf "Display name" [sheet_id] [--rotate auto|0|90|180|270]
        [--replace] [--data-dir DIR]
Setup:  python3 app.py setup-importer   (creates .venv with pymupdf, opencv-python-headless, numpy)
Works on vector AutoCAD-plotted P&IDs (not scans). Takes about a minute per sheet on a multi-core machine.
Only the first page is read. The last output line is `RESULT {json}` for the app."""
import argparse, json, os, re, sys, tempfile, time
HERE = os.path.dirname(os.path.abspath(__file__))


def write_json(path, obj, **kw):
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(obj, f, **kw)
    os.replace(tmp, path)  # atomic: the app never reads a half-written file


def main():
    ap = argparse.ArgumentParser(description='Add a P&ID sheet')
    ap.add_argument('pdf'); ap.add_argument('name'); ap.add_argument('sheet_id', nargs='?')
    ap.add_argument('--rotate', default='auto', choices=['auto', '0', '90', '180', '270'],
                    help='auto picks the orientation with most horizontal text; it cannot tell upright from upside down')
    ap.add_argument('--replace', action='store_true', help='replace an existing sheet with the same id')
    ap.add_argument('--data-dir', default=os.path.join(HERE, 'data'))
    a = ap.parse_args()
    from extractor.orient import rotated_copy, score
    from extractor.extract_sheet import extract, render_image
    import pymupdf
    log = lambda m: print(m, flush=True)

    sid = a.sheet_id or re.sub(r'[^a-z0-9]+', '-', a.name.lower()).strip('-')[:24]
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,23}', sid):
        sys.exit(f'Bad sheet id "{sid}": use 1-24 lowercase letters, digits, dashes.')
    sheets_p, tags_p = os.path.join(a.data_dir, 'sheets.json'), os.path.join(a.data_dir, 'tags.json')
    sheets, tags = json.load(open(sheets_p)), json.load(open(tags_p))
    if any(s['id'] == sid for s in sheets) and not a.replace:
        sys.exit(f'Sheet id "{sid}" exists; pass a different id, or --replace.')
    src = pymupdf.open(a.pdf)
    if src.page_count > 1:
        log(f'Note: the PDF has {src.page_count} pages; only page 1 is read.')

    tmp = tempfile.mkdtemp()
    if a.rotate == 'auto':
        log('Finding orientation...')
        best = None
        for extra in (0, 90, 180, 270):
            dst = os.path.join(tmp, f'r{extra}.pdf'); rotated_copy(a.pdf, dst, extra); h = score(dst)[0]
            log(f'  {extra:>3}°: {h} text lines')
            if best is None or h > best[0]: best = (h, dst, extra)
        pdf, rot = best[1], best[2]
    else:
        rot = int(a.rotate); pdf = os.path.join(tmp, f'r{rot}.pdf'); rotated_copy(a.pdf, pdf, rot)
        log(f'Rotation forced to {rot}°.')
    log('Extracting tags (this is the slow part)...')
    T, size = extract(pdf, log=lambda m: log('  ' + m))
    # The text-line score can't tell upright from upside down, but the reader can: upside-down text reads as
    # garbage, so almost nothing gets auto-read. If that happens with auto orientation, try the flip, keep the better.
    auto = lambda T: sum(t['status'] == 'auto' for t in T)
    found = sum(t['status'] != 'ignore' for t in T)
    if a.rotate == 'auto' and found >= 10 and auto(T) < 0.25 * found:
        flip = (rot + 180) % 360
        log(f'Only {auto(T)} of {found} tags readable at {rot}°: the sheet may be upside down. Trying {flip}°...')
        pdf2 = os.path.join(tmp, f'r{flip}.pdf'); rotated_copy(a.pdf, pdf2, flip)
        T2, _ = extract(pdf2, log=lambda m: log('  ' + m))
        if auto(T2) > auto(T):
            log(f'Kept {flip}°: {auto(T2)} tags readable.'); T, pdf, rot = T2, pdf2, flip
        else:
            log(f'Kept {rot}°: {flip}° was no better ({auto(T2)} readable). This sheet just reads poorly.')
    p = pymupdf.open(pdf)[0]; Z = min(2.0, 6400 / max(p.rect.width, p.rect.height))
    os.makedirs(os.path.join(a.data_dir, 'sheets'), exist_ok=True)
    log('Rendering the sheet image...')
    w, h = render_image(pdf, os.path.join(a.data_dir, 'sheets', f'{sid}.png'), zoom=Z)
    notes = [t for t in ((an.info.get('content') or '').strip() for an in src[0].annots()) if t]

    # ?v= changes on every import, so browsers and the offline cache fetch a re-imported image
    sheet = dict(id=sid, name=a.name, file=f'data/sheets/{sid}.png?v={int(time.time())}', w=w, h=h, notes=notes)
    sheets = [s for s in sheets if s['id'] != sid]; sheets.append(sheet)
    tags = [t for t in tags if t['sheet'] != sid]
    n = {'auto': 0, 'review': 0}
    for t in T:
        if t['status'] == 'ignore': continue
        n[t['status']] += 1
        tags.append(dict(id=f"{sid}:{t['id']}", sheet=sid, kks=t.get('kks'), suffix=t.get('suffix') or '', isa=t.get('isa'),
                         kind=t['kind'], status=t['status'], conf=float(t['conf']), bbox=[round(v * Z, 1) for v in t['bbox']],
                         orient=t['orient'], read=[t['top'], t['bottom']], note=t.get('note', ''), flag=t.get('flag', ''),
                         suggestion=None))
    write_json(tags_p, tags)
    write_json(sheets_p, sheets, indent=1)
    log(f'Done: "{a.name}" added: {n["auto"]} tags auto-read, {n["review"]} in the review queue. Reload the page.')
    print('RESULT ' + json.dumps({'id': sid, 'name': a.name, 'auto': n['auto'], 'review': n['review'], 'rotation': rot,
                                  'w': w, 'h': h, 'notes': len(notes)}), flush=True)


if __name__ == '__main__':
    main()
