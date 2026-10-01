"""Measure the .kkp path store (docs/PATHSTORE.md) on real sheets. Investigation tool; outputs stay in the work folder
(plant data: never commit them).

  .venv/bin/python tools/m6/pathstore_measure.py encode WORK sheet.pdf[:rot] ...   (PyMuPDF: .kkp + MuPDF tiles)
  python3          tools/m6/pathstore_measure.py compare WORK                       (Cairo: decode, draw, compare)"""
import glob, gzip, io, json, os, statistics, sys, time
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
from ref import pathstore as K

T = 512
ZOOMS = (1, 4, 16)


def spots(w, h):
    return [(0.5, 0.5), (0.3, 0.6), (0.7, 0.3), (0.9, 0.9)]


def encode_cmd(work, specs):
    import pymupdf
    from PIL import Image

    import pillow_jxl  # noqa: F401  (registers the JXL format with Pillow)

    def jxl(im):
        b = io.BytesIO()
        im.save(b, 'JXL', lossless=True, effort=9)
        return b.getvalue()
    os.makedirs(work, exist_ok=True)
    for spec in specs:
        path, _, rot = spec.partition(':')
        name = os.path.splitext(os.path.basename(path))[0][:12].replace(' ', '_')
        page = pymupdf.open(path)[0]
        t = time.perf_counter()
        w, h, styles, paths, images = K.from_pdf_page(page, int(rot or 0), jxl_encode=jxl)
        data = K.encode(w, h, styles, paths, images)
        te = time.perf_counter() - t
        open(os.path.join(work, name + '.kkp'), 'wb').write(data)
        for k, im in enumerate(images):   # (the system Python can't read JXL: hand the pixels over as PNG)
            Image.open(io.BytesIO(im['data'])).save(os.path.join(work, f'{name}-img{k}.png'))
        t = time.perf_counter()
        doc = K.decode(data)
        td = time.perf_counter() - t
        pdf = os.path.getsize(path)
        info = {'sheet': name, 'rot': int(rot or 0), 'pdf_kb': pdf // 1024, 'kkp_kb': len(data) // 1024,
                'kkp_raw_kb': len(K.encode(w, h, styles, paths, images, compress=False)) // 1024, 'paths': len(paths), 'styles': len(styles),
                'images': len(images), 'image_kb': sum(len(i['data']) for i in images) // 1024,
                'grid': doc['grid'], 'encode_s': round(te, 2), 'decode_py_s': round(td, 2)}
        # MuPDF reference tiles at the same scales (fit = 2000 px across)
        fit = 2000 / (w / K.Q)
        mat = page.rotation_matrix * pymupdf.Matrix(int(rot or 0))
        r = page.rect * pymupdf.Matrix(int(rot or 0))
        refs = []
        for z in ZOOMS:
            for fx, fy in spots(w, h):
                s = fit * z
                cx, cy = fx * w / K.Q, fy * h / K.Q        # display-orientation points
                # get_pixmap renders the page as displayed (its own rotation applied); clip is in display points
                clip = pymupdf.Rect(cx - T / 2 / s, cy - T / 2 / s, cx + T / 2 / s, cy + T / 2 / s) + (r.x0, r.y0, r.x0, r.y0)
                pix = page.get_pixmap(matrix=pymupdf.Matrix(s, s), clip=clip, colorspace=pymupdf.csGRAY, alpha=False)
                fn = f'{name}-ref-{z}-{fx}-{fy}.png'
                pix.save(os.path.join(work, fn))
                refs.append({'zoom': z, 'fx': fx, 'fy': fy, 'file': fn, 'size': [pix.width, pix.height],
                             'origin_px': [pix.x - r.x0 * s, pix.y - r.y0 * s], 'scale': s})
        info['refs'] = refs
        json.dump(info, open(os.path.join(work, name + '.json'), 'w'), indent=1)
        print(json.dumps({k: v for k, v in info.items() if k != 'refs'}))


def compare_cmd(work):
    import cairo
    from PIL import Image, ImageChops, ImageStat
    for jf in sorted(glob.glob(os.path.join(work, '*.json'))):
        info = json.load(open(jf))
        doc = K.decode(open(os.path.join(work, info['sheet'] + '.kkp'), 'rb').read())
        w, h = doc['width'], doc['height']
        gx, gy = doc['grid']
        fit = 2000 / (w / K.Q)
        imgs = []
        for k, im in enumerate(doc['images']):
            pil = Image.open(os.path.join(work, f"{info['sheet']}-img{k}.png")).convert('RGBA')
            buf = bytearray(pil.tobytes('raw', 'BGRa'))
            surf = cairo.ImageSurface.create_for_data(buf, cairo.FORMAT_ARGB32, pil.width, pil.height)
            imgs.append((im, surf, buf))
        results, times = [], {z: [] for z in ZOOMS}
        for ref in info['refs']:
            s = fit * ref['zoom'] / K.Q                         # device px per quantum
            cx, cy = ref['fx'] * w, ref['fy'] * h
            ow, oh = ref['size']
            ox, oy = (ref['origin_px'][0] / ref['scale'] * K.Q, ref['origin_px'][1] / ref['scale'] * K.Q)   # MuPDF's whole-pixel origin
            t0 = time.perf_counter()
            surf = cairo.ImageSurface(cairo.FORMAT_RGB24, ow, oh)
            cr = cairo.Context(surf)
            cr.set_source_rgb(1, 1, 1); cr.paint()
            cr.scale(s, s); cr.translate(-ox, -oy)
            x1, y1 = ox + ow / s, oy + oh / s
            ids = set()
            for cyi in K.cell_range(int(oy), int(y1), h, gy):
                for cxi in K.cell_range(int(ox), int(x1), w, gx):
                    ids.update(doc['cells'][cyi * gx + cxi])
            order = sorted(ids)
            one_px = 1 / s
            ii = 0
            pending = sorted(range(len(imgs)), key=lambda k: imgs[k][0]['after'])

            def draw_images_upto(n):
                nonlocal ii
                while ii < len(pending) and imgs[pending[ii]][0]['after'] <= n:
                    im, isurf, _ = imgs[pending[ii]]
                    ax0, ay0, ax1, ay1 = im['rect']
                    if ax1 >= ox and ax0 <= x1 and ay1 >= oy and ay0 <= y1:
                        cr.save(); cr.translate(ax0, ay0)
                        cr.scale((ax1 - ax0) / isurf.get_width(), (ay1 - ay0) / isurf.get_height())
                        cr.set_source_surface(isurf, 0, 0); cr.paint(); cr.restore()
                    ii += 1
            for i in order:
                draw_images_upto(i)
                p = doc['paths'][i]
                bx0, by0, bx1, by1 = p['bbox']
                if bx1 < ox or bx0 > x1 or by1 < oy or by0 > y1:
                    continue
                kind, cap, join, sw, stroke, fill = doc['styles'][p['style']]
                for c in p['cmds']:
                    if c[0] == 'M':
                        cr.move_to(c[1], c[2])
                    elif c[0] == 'L':
                        cr.line_to(c[1], c[2])
                    elif c[0] == 'C':
                        cr.curve_to(*c[1:])
                    else:
                        cr.close_path()
                if kind & K.FILL:
                    cr.set_fill_rule(cairo.FILL_RULE_EVEN_ODD if kind & K.EVENODD else cairo.FILL_RULE_WINDING)
                    cr.set_source_rgb(*(v / 255 for v in fill))
                    cr.fill_preserve() if kind & K.STROKE else cr.fill()
                if kind & K.STROKE:
                    cr.set_source_rgb(*(v / 255 for v in stroke))
                    cr.set_line_width(one_px if kind & K.HAIRLINE else (sw if os.environ.get('MUPDF_THIN') else max(sw, one_px)))
                    cr.set_line_cap([cairo.LINE_CAP_BUTT, cairo.LINE_CAP_ROUND, cairo.LINE_CAP_SQUARE][cap])
                    cr.set_line_join([cairo.LINE_JOIN_MITER, cairo.LINE_JOIN_ROUND, cairo.LINE_JOIN_BEVEL][join])
                    cr.stroke()
            draw_images_upto(len(doc['paths']))
            surf.flush()
            times[ref['zoom']].append((time.perf_counter() - t0) * 1000)
            got = Image.frombuffer('RGBX', (ow, oh), bytes(surf.get_data()), 'raw', 'BGRX', surf.get_stride(), 1).convert('L')
            want = Image.open(os.path.join(work, ref['file'])).convert('L')
            d = ImageChops.difference(got, want)
            big = sum(1 for v in d.get_flattened_data() if v > 64) / (ow * oh)
            ink = sum(1 for v in want.get_flattened_data() if v < 128) / (ow * oh)
            results.append((ref['zoom'], ImageStat.Stat(d).mean[0], big, ink))
            if True:
                got.save(os.path.join(work, f"{info['sheet']}-got-{ref['zoom']}-{ref['fx']}-{ref['fy']}.png"))
        by = {z: [r for r in results if r[0] == z] for z in ZOOMS}
        print(info['sheet'], ' | '.join(
            f"{z}x: diff>64 max {100 * max(r[2] for r in by[z]):.2f}% (ink {100 * statistics.mean(r[3] for r in by[z]):.1f}%), "
            f"py draw {statistics.median(times[z]):.0f} ms" for z in ZOOMS))


if __name__ == '__main__':
    if sys.argv[1] == 'encode':
        encode_cmd(sys.argv[2], sys.argv[3:])
    else:
        compare_cmd(sys.argv[2])
