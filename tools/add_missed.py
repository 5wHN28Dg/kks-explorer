#!/usr/bin/env python3
"""Run the current extractor on a sheet that is already in the app and ADD the tags it finds that don't overlap
any existing tag. Existing tags (ids, hand-verified values, user review decisions keyed by id) are never touched.
Used after detector fixes (2026-09-25: hull area test in reader2.detect, divider-less bubbles in reader3).
  .venv/bin/python tools/add_missed.py SHEET_ID source.pdf [--apply]
Without --apply: prints the candidates and writes a contact sheet (/tmp/added_<id>.png) for checking by eye.
Added tags get ids <sheet>:x<n> and status auto (conf >= 0.3) or review, like a normal import."""
import json, os, sys, tempfile
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)


def main():
    sid, src = sys.argv[1], sys.argv[2]; apply = '--apply' in sys.argv
    import cv2, numpy as np, pymupdf
    from extractor.orient import rotated_copy
    from extractor.extract_sheet import extract
    data = os.path.join(HERE, 'plant-data'); tags_p = os.path.join(data, 'tags.json')   # the working copy (then: app.py publish-data)
    sheet = next(s for s in json.load(open(os.path.join(data, 'sheets.json'))) if s['id'] == sid)
    tags = json.load(open(tags_p)); mine = [t for t in tags if t['sheet'] == sid]
    tmp = tempfile.mkdtemp(); pdf = os.path.join(tmp, 'r.pdf'); rotated_copy(src, pdf, sheet.get('rot', 0))
    page = pymupdf.open(pdf)[0]; Z = sheet['w'] / page.rect.width
    T, _ = extract(pdf, log=lambda m: None)
    over = lambda b, q: b[0] < q[2] and b[2] > q[0] and b[1] < q[3] and b[3] > q[1]
    # tags users marked by hand in the app live in plant.db: don't propose those again
    marked = []
    try:
        import sqlite3
        db = sqlite3.connect(f'file:{os.path.join(HERE, "plant.db")}?mode=ro', uri=True)
        marked = [{'bbox': json.loads(d)['bbox']} for (d,) in db.execute('SELECT data FROM added_tags')
                  if json.loads(d)['sheet'] == sid]
    except Exception:  # noqa: BLE001 - no DB or no table yet
        pass
    new = []
    for t in T:
        if t['status'] == 'ignore' or not t.get('kks'): continue
        bb = [round(v * Z, 1) for v in t['bbox']]
        if any(over(bb, q['bbox']) for q in mine + marked) or any(over(bb, q['bbox']) for q in new): continue
        new.append(dict(id=None, sheet=sid, kks=t['kks'], suffix=t.get('suffix') or '', isa=t.get('isa'), kind=t['kind'],
                        status=t['status'], conf=float(t['conf']), bbox=bb, orient=t['orient'], read=[t['top'], t['bottom']],
                        note='added by detector fix 2026-09-25', flag='', suggestion=None))
    print(f'{sid}: {len(mine)} existing tags; {len(new)} new, not overlapping any existing tag')
    for i, t in enumerate(new):
        print(f'  [{i}] {t["status"]:<6} {t["isa"] or "":<6} {t["kks"]}{t["suffix"]:<6} conf {t["conf"]}')
    tiles = []
    for i, t in enumerate(new):
        x0, y0, x1, y1 = [v / Z for v in t['bbox']]
        pix = page.get_pixmap(clip=pymupdf.Rect(x0 - 3, y0 - 3, x1 + 3, y1 + 3), dpi=250, colorspace=pymupdf.csGRAY)
        im = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width).copy()
        if t['orient'] == 'v': im = cv2.rotate(im, cv2.ROTATE_90_CLOCKWISE)
        s = min(100 / im.shape[0], 330 / im.shape[1]); im = cv2.resize(im, (max(1, int(im.shape[1] * s)), max(1, int(im.shape[0] * s))))
        tile = np.full((130, 340), 255, np.uint8); tile[:im.shape[0], :im.shape[1]] = im
        cv2.putText(tile, f'{i} {t["isa"] or ""} {t["kks"]}{t["suffix"]}', (3, 124), cv2.FONT_HERSHEY_SIMPLEX, 0.47, 0, 1)
        tiles.append(tile)
    if tiles:
        while len(tiles) % 4: tiles.append(np.full_like(tiles[0], 255))
        cv2.imwrite(f'/tmp/added_{sid}.png', np.vstack([np.hstack(tiles[i:i + 4]) for i in range(0, len(tiles), 4)]))
        print(f'contact sheet: /tmp/added_{sid}.png')
    json.dump(new, open(f'/tmp/added_{sid}.json', 'w'))
    if apply and new:
        start = 1 + max([int(t['id'].split(':x')[1]) for t in mine if ':x' in t['id']] or [-1])  # continue numbering
        for i, t in enumerate(new): t['id'] = f'{sid}:x{start + i}'
        assert not {t['id'] for t in new} & {t['id'] for t in tags}, 'id clash'
        tags += new
        with open(tags_p + '.tmp', 'w') as f:
            json.dump(tags, f)
        os.replace(tags_p + '.tmp', tags_p)
        print(f'added {len(new)} tags to {sid}')


if __name__ == '__main__':
    main()
