#!/usr/bin/env python3
"""Create the sharp-zoom vector file (plant-data/sheets/<id>.svg.gz) for a sheet that is already in the app (then: app.py publish-data).

The source PDF is tried at 0/90/180/270 degrees; the rotation whose rendering matches the existing sheet image is
used, so the vector layer lines up exactly with the tag hotspots. Refuses if nothing matches well.
  .venv/bin/python tools/make_vectors.py SHEET_ID path/to/source.pdf
New imports (import_sheet.py / Manage → Drawings) create the vector file themselves."""
import json, os, sys, tempfile, time
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, HERE)


def main():
    sid, src = sys.argv[1], sys.argv[2]
    import cv2, numpy as np, pymupdf
    from extractor.orient import rotated_copy
    from extractor.svgopt import sheet_svg
    data = os.path.join(HERE, 'plant-data'); sp = os.path.join(data, 'sheets.json')   # the working copy (then: app.py publish-data)
    sheets = json.load(open(sp)); sheet = next(s for s in sheets if s['id'] == sid)
    png = cv2.imread(os.path.join(data, 'sheets', f'{sid}.png'), cv2.IMREAD_GRAYSCALE)
    small = lambda im: cv2.resize(im, (800, round(800 * im.shape[0] / im.shape[1])), interpolation=cv2.INTER_AREA)
    ref = small(png).astype(np.float32)
    tmp = tempfile.mkdtemp(); best = None; tried = []
    for rot in (0, 90, 180, 270):
        pdf = os.path.join(tmp, f'r{rot}.pdf'); rotated_copy(src, pdf, rot)
        page = pymupdf.open(pdf)[0]
        if abs(page.rect.width / page.rect.height - png.shape[1] / png.shape[0]) > 0.01:
            continue
        pix = page.get_pixmap(matrix=pymupdf.Matrix(800 / page.rect.width, 800 / page.rect.width), colorspace=pymupdf.csGRAY)
        im = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width)
        im = cv2.resize(im, (ref.shape[1], ref.shape[0])).astype(np.float32)
        err = float(np.mean(np.abs(im - ref)))
        print(f'  {rot:>3}°: mean difference {err:.2f}')
        tried.append((err, rot, pdf))
        if best is None or err < best[0]: best = (err, rot, pdf)
    errs = sorted(e for e, _, _ in tried)
    if not best or (len(errs) > 1 and errs[0] > 0.75 * errs[1]):
        sys.exit(f'{sid}: no rotation of {src} clearly matches the sheet image; nothing written.')
    err, rot, pdf = best
    # Alignment check at 2400 px wide: the shift between the sheet image and the PDF rendering must be ~0.
    page = pymupdf.open(pdf)[0]; W = 2400
    pix = page.get_pixmap(matrix=pymupdf.Matrix(W / page.rect.width, W / page.rect.width), colorspace=pymupdf.csGRAY)
    im = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width).astype(np.float32)
    ref2 = cv2.resize(png, (im.shape[1], im.shape[0]), interpolation=cv2.INTER_AREA).astype(np.float32)
    (dx, dy), resp = cv2.phaseCorrelate(255 - ref2, 255 - im)
    shift = (dx * png.shape[1] / W, dy * png.shape[1] / W)  # in sheet-image pixels
    print(f'  alignment: shift {shift[0]:+.2f}, {shift[1]:+.2f} sheet px (correlation {resp:.2f})')
    if abs(shift[0]) > 2 or abs(shift[1]) > 2:
        sys.exit(f'{sid}: the PDF rendering is offset from the sheet image; nothing written.')
    out = os.path.join(data, 'sheets', f'{sid}.svg.gz')
    size = sheet_svg(pdf, out)
    sheet['vector'] = f'data/sheets/{sid}.svg?v={int(time.time())}'; sheet['rot'] = rot
    with open(sp + '.tmp', 'w') as f:
        json.dump(sheets, f, indent=1)
    os.replace(sp + '.tmp', sp)
    print(f'{sid}: rotation {rot}° (difference {err:.2f}), vector {size/1e6:.1f} MB raw, {os.path.getsize(out)/1e6:.2f} MB gzip')


if __name__ == '__main__':
    main()
