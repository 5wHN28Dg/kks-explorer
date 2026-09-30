"""GTK 4 / GSK tile benchmark (docs/decisions/0015): grid-indexed paths as GSK render nodes, rendered off-screen by the
GL, Vulkan and Cairo renderers. Needs <sheet>.paths.pkl from grid_bench.py (extraction pass). Throwaway tool.
Times: 'record' = building the node tree (Python-side, CPU), 'render' = renderer.render_texture + download (GPU work
plus reading back 512x512 pixels, so the frame is really finished)."""
import pickle, statistics, sys, time
import gi
gi.require_version('Gtk', '4.0'); gi.require_version('Gsk', '4.0'); gi.require_version('Gdk', '4.0')
from gi.repository import Gdk, Gsk, Gtk, Graphene

import os
T, N, RUNS = int(os.environ.get("TILE", 512)), 32, 5


def gsk_paths(paths):
    out = []
    for bbox, lw, col, fill, segs in paths:
        b = Gsk.PathBuilder.new()
        last = None
        for sg in segs:
            t = sg[0]
            if t == 're':
                r = Graphene.Rect(); r.init(*sg[1:]); b.add_rect(r); last = None; continue
            if (sg[1], sg[2]) != last:
                b.move_to(sg[1], sg[2])
            if t == 'l':
                b.line_to(sg[3], sg[4]); last = (sg[3], sg[4])
            elif t == 'c':
                b.cubic_to(*sg[3:9]); last = (sg[7], sg[8])
            else:
                b.line_to(sg[3], sg[4]); b.line_to(sg[5], sg[6]); b.line_to(sg[7], sg[8]); b.close(); last = None
        if fill:
            b.close()
        c = Gdk.RGBA(); c.red, c.green, c.blue, c.alpha = *col, 1
        f = None
        if fill:
            f = Gdk.RGBA(); f.red, f.green, f.blue, f.alpha = *fill, 1
        out.append((b.to_path(), lw, c, f))
    return out


def index(w, h, paths):
    cw, ch = w / N, h / N
    grid = {}
    for i, p in enumerate(paths):
        x0, y0, x1, y1 = p[0]
        for gx in range(max(0, int(x0 // cw)), min(N - 1, int(x1 // cw)) + 1):
            for gy in range(max(0, int(y0 // ch)), min(N - 1, int(y1 // ch)) + 1):
                grid.setdefault((gx, gy), []).append(i)
    return cw, ch, grid


def node(w, h, gp, idx, scale, cx, cy):
    cw, ch, grid = idx
    s = Gtk.Snapshot.new()
    white = Gdk.RGBA(); white.red = white.green = white.blue = white.alpha = 1
    r = Graphene.Rect(); r.init(0, 0, T, T); s.append_color(white, r)
    ox, oy = cx - T / 2 / scale, cy - T / 2 / scale
    s.scale(scale, scale)
    p = Graphene.Point(); p.x, p.y = -ox, -oy; s.translate(p)
    minw = 1 / scale
    strokes = {}
    seen = set()
    for gx in range(max(0, int(ox // cw)), min(N - 1, int((ox + T / scale) // cw)) + 1):
        for gy in range(max(0, int(oy // ch)), min(N - 1, int((oy + T / scale) // ch)) + 1):
            for i in grid.get((gx, gy), ()):
                if i in seen:
                    continue
                seen.add(i)
                path, lw, col, fill = gp[i]
                if fill:
                    s.append_fill(path, Gsk.FillRule.WINDING, fill)
                wdt = max(lw, minw)
                st = strokes.get(wdt) or strokes.setdefault(wdt, Gsk.Stroke.new(wdt))
                s.append_stroke(path, st, col)
    return s.to_node(), len(seen)


def main():
    Gtk.init()
    disp = Gdk.Display.get_default()
    renderers = []
    for name in ('GLRenderer', 'VulkanRenderer', 'CairoRenderer'):
        rdr = getattr(Gsk, name).new()
        try:
            rdr.realize_for_display(disp)
            renderers.append((name, rdr))
        except Exception as e:
            print(name, 'unavailable:', e)
    vp = Graphene.Rect(); vp.init(0, 0, T, T)
    for sname in sys.argv[1:]:
        w, h, paths, _ = pickle.load(open(f'{sname}.paths.pkl', 'rb'))
        t = time.perf_counter(); gp = gsk_paths(paths); t_build = (time.perf_counter() - t) * 1000
        idx = index(w, h, paths)
        print(f'{sname}: {len(paths)} paths, GskPath objects built in {t_build:.0f} ms (Python, at load)', flush=True)
        fit = 2000 / w
        for rname, rdr in renderers:
            out = []
            for z in (1, 4, 16):
                rec, ren = [], []
                for k in range(RUNS + 2):   # 2 warm-up frames
                    t0 = time.perf_counter()
                    nd, n = node(w, h, gp, idx, fit * z, w / 2, h / 2)
                    t1 = time.perf_counter()
                    tex = rdr.render_texture(nd, vp)
                    Gdk.TextureDownloader.new(tex).download_bytes()
                    t2 = time.perf_counter()
                    if k >= 2:
                        rec.append((t1 - t0) * 1000); ren.append((t2 - t1) * 1000)
                    if k == 2 and z == 4:
                        tex.save_to_png(f'{sname}-{rname}-4x.png')
                out.append(f'{z:2}x render {statistics.median(ren):6.1f} ms (record {statistics.median(rec):5.1f}, {n} paths)')
            print(f'  {rname:15}', ' | '.join(out), flush=True)
        for _, rdr in renderers:
            pass
    for _, rdr in renderers:
        rdr.unrealize()


if __name__ == '__main__':
    main()
