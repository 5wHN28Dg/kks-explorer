"""Grid-indexed vector drawing: paths extracted once, bucketed by bounding box, each tile draws only its paths.
Same cairo image target as bench.py. Throwaway investigation tool."""
import pickle, statistics, sys, time
try:
    import cairo
except ImportError:
    cairo = None

import os
T = int(os.environ.get("TILE", 512))


def load(path):
    import pymupdf
    page = pymupdf.open(path)[0]
    paths = []
    for d in page.get_drawings():
        segs = []
        for it in d['items']:
            if it[0] == 'l':
                segs.append(('l', it[1].x, it[1].y, it[2].x, it[2].y))
            elif it[0] == 'c':
                segs.append(('c', it[1].x, it[1].y, it[2].x, it[2].y, it[3].x, it[3].y, it[4].x, it[4].y))
            elif it[0] == 're':
                r = it[1]; segs.append(('re', r.x0, r.y0, r.width, r.height))
            elif it[0] == 'qu':
                q = it[1]; segs.append(('qu', q.ul.x, q.ul.y, q.ur.x, q.ur.y, q.lr.x, q.lr.y, q.ll.x, q.ll.y))
        r = d['rect']
        paths.append(((r.x0, r.y0, r.x1, r.y1), d.get('width') or 0.5, d.get('color') or (0, 0, 0), d.get('fill'), segs))
    return page.rect.width, page.rect.height, paths


def index(w, h, paths, n=32):
    cw, ch = w / n, h / n
    grid = {}
    for i, p in enumerate(paths):
        x0, y0, x1, y1 = p[0]
        for gx in range(max(0, int(x0 // cw)), min(n - 1, int(x1 // cw)) + 1):
            for gy in range(max(0, int(y0 // ch)), min(n - 1, int(y1 // ch)) + 1):
                grid.setdefault((gx, gy), []).append(i)
    return cw, ch, grid


def draw(cr, p):
    _, lw, col, fill, segs = p
    for s in segs:
        if s[0] == 'l':
            cr.move_to(s[1], s[2]); cr.line_to(s[3], s[4])
        elif s[0] == 'c':
            cr.move_to(s[1], s[2]); cr.curve_to(*s[3:])
        elif s[0] == 're':
            cr.rectangle(*s[1:])
        else:
            cr.move_to(s[1], s[2]); cr.line_to(s[3], s[4]); cr.line_to(s[5], s[6]); cr.line_to(s[7], s[8]); cr.close_path()
    if fill:
        cr.set_source_rgb(*fill); cr.fill_preserve()
    cr.set_source_rgb(*col); cr.set_line_width(max(lw, 0.1)); cr.stroke()


def tile(w, h, paths, idx, scale, cx, cy, size=T):
    cw, ch, grid = idx
    s = cairo.ImageSurface(cairo.FORMAT_RGB24, size, size); cr = cairo.Context(s)
    cr.set_source_rgb(1, 1, 1); cr.paint()
    ox, oy = cx - size / 2 / scale, cy - size / 2 / scale
    x1, y1 = ox + size / scale, oy + size / scale
    cr.translate(-ox * scale, -oy * scale); cr.scale(scale, scale)
    seen = set()
    for gx in range(max(0, int(ox // cw)), min(len(range(32)) - 1, int(x1 // cw)) + 1):
        for gy in range(max(0, int(oy // ch)), min(31, int(y1 // ch)) + 1):
            for i in grid.get((gx, gy), ()):
                if i not in seen:
                    seen.add(i); draw(cr, paths[i])
    s.flush()
    return len(seen)


def med(fn, n):
    ts = []
    for _ in range(n):
        t = time.perf_counter(); r = fn(); ts.append((time.perf_counter() - t) * 1000)
    return statistics.median(ts), r


if __name__ == '__main__':
    for s in sys.argv[1:]:
        if cairo is None:   # extraction pass (.venv with PyMuPDF)
            t = time.perf_counter(); w, h, paths = load(f'{s}.pdf'); t_ex = (time.perf_counter() - t) * 1000
            pickle.dump((w, h, paths, t_ex), open(f'{s}.paths.pkl', 'wb')); print(s, 'extracted', len(paths)); continue
        w, h, paths, t_ex = pickle.load(open(f'{s}.paths.pkl', 'rb'))
        t = time.perf_counter(); idx = index(w, h, paths); t_ix = (time.perf_counter() - t) * 1000
        fit = 2000 / w
        out = [f'extract {t_ex:.0f} ms (one-time import)', f'index {t_ix:.0f} ms', f'{len(paths)} paths']
        for z in (1, 4, 16):
            ms, n = med(lambda: tile(w, h, paths, idx, fit * z, w / 2, h / 2), 5)
            out.append(f'tile {z}x: {ms:.1f} ms ({n} paths)')
        print(f'{s:8}', ' | '.join(out), flush=True)
