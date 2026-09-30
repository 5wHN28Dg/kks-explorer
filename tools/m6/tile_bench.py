"""Tile-rendering benchmark: original PDF vs merged PDF (Poppler) vs merged/raw SVG (librsvg), same cairo target.
Throwaway investigation tool for docs/m6 (not product code)."""
import ctypes, ctypes.util, os, statistics, sys, time
import gi
gi.require_version('Rsvg', '2.0')
from gi.repository import Rsvg
import cairo

C = ctypes.CDLL('libcairo.so.2')
P = ctypes.CDLL('libpoppler-glib.so.8')
G = ctypes.CDLL('libgobject-2.0.so.0')
vp, dbl, i32 = ctypes.c_void_p, ctypes.c_double, ctypes.c_int
C.cairo_image_surface_create.restype = vp; C.cairo_image_surface_create.argtypes = [i32, i32, i32]
C.cairo_create.restype = vp; C.cairo_create.argtypes = [vp]
for f in ('cairo_translate', 'cairo_scale'):
    getattr(C, f).argtypes = [vp, dbl, dbl]
for f in ('cairo_destroy', 'cairo_surface_destroy', 'cairo_paint', 'cairo_surface_flush'):
    getattr(C, f).argtypes = [vp]
C.cairo_set_source_rgb.argtypes = [vp, dbl, dbl, dbl]
P.poppler_document_new_from_file.restype = vp; P.poppler_document_new_from_file.argtypes = [ctypes.c_char_p, ctypes.c_char_p, vp]
P.poppler_document_get_page.restype = vp; P.poppler_document_get_page.argtypes = [vp, i32]
P.poppler_page_get_size.argtypes = [vp, ctypes.POINTER(dbl), ctypes.POINTER(dbl)]
P.poppler_page_render.argtypes = [vp, vp]
G.g_object_unref.argtypes = [vp]
T = 512


def med(fn, n):
    ts = []
    for _ in range(n):
        t = time.perf_counter(); fn(); ts.append((time.perf_counter() - t) * 1000)
    return statistics.median(ts)


class Pdf:
    def __init__(self, path):
        t = time.perf_counter()
        self.doc = P.poppler_document_new_from_file(('file://' + os.path.abspath(path)).encode(), None, None)
        self.page = P.poppler_document_get_page(self.doc, 0)
        w, h = dbl(), dbl(); P.poppler_page_get_size(self.page, ctypes.byref(w), ctypes.byref(h))
        self.w, self.h = w.value, h.value
        self.load = (time.perf_counter() - t) * 1000

    def tile(self, scale, cx, cy, size=T):
        s = C.cairo_image_surface_create(0, size, size); cr = C.cairo_create(s)
        C.cairo_set_source_rgb(cr, 1, 1, 1); C.cairo_paint(cr)
        C.cairo_translate(cr, size / 2 - cx * scale, size / 2 - cy * scale); C.cairo_scale(cr, scale, scale)
        P.poppler_page_render(self.page, cr); C.cairo_surface_flush(s)
        C.cairo_destroy(cr); C.cairo_surface_destroy(s)


class Svg:
    def __init__(self, path):
        t = time.perf_counter()
        self.h_ = Rsvg.Handle.new_from_file(path)
        ok, w, h = self.h_.get_intrinsic_size_in_pixels()
        self.w, self.h = w, h
        self.load = (time.perf_counter() - t) * 1000

    def tile(self, scale, cx, cy, size=T):
        s = cairo.ImageSurface(cairo.FORMAT_RGB24, size, size); cr = cairo.Context(s)
        cr.set_source_rgb(1, 1, 1); cr.paint()
        vp_ = Rsvg.Rectangle(); vp_.x = size / 2 - cx * scale; vp_.y = size / 2 - cy * scale
        vp_.width = self.w * scale; vp_.height = self.h * scale
        self.h_.render_document(cr, vp_); s.flush()


def run(name, obj, fit_px=2000):
    fit = fit_px / obj.w
    out = {'load ms': obj.load}
    cx, cy = obj.w / 2, obj.h / 2
    out['full page @2000px'] = med(lambda: obj.tile(fit, cx, cy, size=fit_px), 3)
    for z in (1, 4, 16):
        out[f'tile {z}x'] = med(lambda: obj.tile(fit * z, cx, cy), 5)
    print(f'{name:16}', '  '.join(f'{k}: {v:8.1f}' for k, v in out.items()), flush=True)


if __name__ == '__main__':
    for s in sys.argv[1:]:
        run(f'{s} PDF orig', Pdf(f'{s}.pdf'))
        run(f'{s} PDF merged', Pdf(f'{s}-merged.pdf'))
        run(f'{s} SVG merged', Svg(f'{s}-merged.svg'))
        if os.path.exists(f'{s}-raw.svg'):
            run(f'{s} SVG raw', Svg(f'{s}-raw.svg'))
