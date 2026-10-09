// The Windows drawing viewer's native half (decisions 0016, 0033): sheets from the core's flat path-store layout
// (core views.flat, "KKF1", the same the Android renderer reads), tiles rendered by Direct2D into WIC bitmaps on
// worker threads, JPEG XL (overview pyramid, embedded images) decoded by libjxl, and a window render target that
// composites cached bitmaps and the tag rectangles. Plain C API for Nim.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d2d1.h>
#include <wincodec.h>
#include <jxl/decode.h>
#include <jxl/decode_cxx.h>
#include <atomic>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <mutex>
#include <new>
#include <string>
#include <thread>
#include <vector>
#include <cmath>
#include <algorithm>

template <class T> static void release(T *&p) { if (p) { p->Release(); p = nullptr; } }

static ID2D1Factory *g_d2d = nullptr;
static IWICImagingFactory *g_wic = nullptr;

extern "C" int kks_d2d_init(void) {
    if (g_d2d) return 0;
    if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) {}
    D2D1_FACTORY_OPTIONS o = {};
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_MULTI_THREADED, __uuidof(ID2D1Factory), &o, (void **)&g_d2d))) return 1;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&g_wic)))) return 2;
    return 0;
}

// ---------------------------------------------------------------- dark drawings

// A PDF reader's dark mode for the sheets: each colour's lightness inverted, its hue kept, squeezed into
// [DARK_LO, DARK_HI]; saturated line colours raised to 3:1 against the dark paper. A copy of apps/common/darkcolor.nim
// darkRgb (exact integer maths, as dark.js and DarkColor.kt): apps/windows/tests/test_dark.nim checks it against the
// Nim original on every 8-bit colour. Here so the worker threads transform tiles and overview levels themselves.
static const int DARK_LO = 18, DARK_HI = 237, RAISE_CHROMA = 48, RAISE_LIGHT = 306, RAISE_Y2 = 104040000;

static inline int dark_byte(int c, int mx, int mn) { return DARK_LO + ((c + 255 - mx - mn) * (DARK_HI - DARK_LO) + 127) / 255; }

extern "C" void kks_dark_rgb(int r, int g, int b, int *outR, int *outG, int *outB) {
    int mx = std::max(r, std::max(g, b)), mn = std::min(r, std::min(g, b));
    int r0 = dark_byte(r, mx, mn), g0 = dark_byte(g, mx, mn), b0 = dark_byte(b, mx, mn);
    int dr = r0, dg = g0, db = b0;
    if (mx - mn >= RAISE_CHROMA && mx + mn <= RAISE_LIGHT) {
        int k = 0;
        while (k < 16 && 2126 * dr * dr + 7152 * dg * dg + 722 * db * db < RAISE_Y2) {
            k++;
            dr = r0 + (DARK_HI - r0) * k / 16;
            dg = g0 + (DARK_HI - g0) * k / 16;
            db = b0 + (DARK_HI - b0) * k / 16;
        }
    }
    *outR = dr; *outG = dg; *outB = db;
}

static inline void dark_px(uint8_t &r, uint8_t &g, uint8_t &b) {
    int dr, dg, db;
    kks_dark_rgb(r, g, b, &dr, &dg, &db);
    r = (uint8_t)dr; g = (uint8_t)dg; b = (uint8_t)db;
}

// ---------------------------------------------------------------- JPEG XL → BGRA (premultiplied for D2D)

// The most pixels a picture may have (#37): 100 MP, as on Android and the web (jxl_jni.cpp, kks_wasm.cpp). Photos are
// made at most 2048 px wide and drawing images are far smaller, so anything bigger was crafted; its header must not
// make us allocate (100000 x 100000 would be 40 GB).
static const uint64_t MAX_PIXELS = 100000000ull;

// dark: the colours turned for dark drawings (straight RGB, before premultiplying; alpha untouched)
static bool jxl_bgra(const uint8_t *data, size_t n, std::vector<uint8_t> &out, int &w, int &h, bool dark = false) try {
    auto dec = JxlDecoderMake(nullptr);
    if (JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE) != JXL_DEC_SUCCESS) return false;
    JxlDecoderSetInput(dec.get(), data, n);
    JxlDecoderCloseInput(dec.get());
    JxlPixelFormat fmt = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    JxlBasicInfo info;
    for (;;) {
        JxlDecoderStatus s = JxlDecoderProcessInput(dec.get());
        if (s == JXL_DEC_ERROR || s == JXL_DEC_NEED_MORE_INPUT) return false;
        if (s == JXL_DEC_BASIC_INFO) {
            if (JxlDecoderGetBasicInfo(dec.get(), &info) != JXL_DEC_SUCCESS) return false;
            if (info.xsize == 0 || info.ysize == 0 || (uint64_t)info.xsize * info.ysize > MAX_PIXELS) return false;
            w = (int)info.xsize; h = (int)info.ysize;
        } else if (s == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t size = 0;
            if (JxlDecoderImageOutBufferSize(dec.get(), &fmt, &size) != JXL_DEC_SUCCESS || size != (size_t)w * h * 4) return false;
            out.resize(size);
            if (JxlDecoderSetImageOutBuffer(dec.get(), &fmt, out.data(), out.size()) != JXL_DEC_SUCCESS) return false;
        } else if (s == JXL_DEC_FULL_IMAGE) {
            // RGBA → premultiplied BGRA
            for (size_t i = 0; i < out.size(); i += 4) {
                uint8_t r = out[i], g = out[i + 1], b = out[i + 2], a = out[i + 3];
                if (dark) dark_px(r, g, b);
                out[i] = (uint8_t)(b * a / 255); out[i + 1] = (uint8_t)(g * a / 255); out[i + 2] = (uint8_t)(r * a / 255);
            }
        } else if (s == JXL_DEC_SUCCESS) return !out.empty();
    }
} catch (const std::bad_alloc &) {   // (an exception must not cross into Nim)
    return false;
}

// ---------------------------------------------------------------- a sheet in the flat layout

// A sheet is shared by its owner (the viewer, until kks_sheet_close) and every tile job for it, queued or being
// rendered: the last of them deletes it. A worker inside render_tile never reads a closed sheet's freed memory.
static std::atomic<int> g_sheets{0};      // sheets not yet deleted (tests: kks_sheets_alive)

struct Sheet {
    std::atomic<int> refs{1};
    Sheet() { g_sheets++; }
    ~Sheet() { g_sheets--; }
    std::vector<uint8_t> b;
    int width, height, nStyles, nPaths, nImages, nOps, nXY, gx, gy;
    size_t stylesAt, pathsAt, opsAt, xyAt, cellsAt, entriesAt;
    struct Img { int after, x0, y0, x1, y1; size_t at, len; };
    std::vector<Img> images;
    int32_t i32(size_t o) const { int32_t v; memcpy(&v, &b[o], 4); return v; }
};

extern "C" void *kks_sheet_open(const uint8_t *flat, size_t n) {
    if (n < 40 || memcmp(flat, "KKF1", 4) != 0) return nullptr;
    Sheet *s = new Sheet();
    s->b.assign(flat, flat + n);
    auto u = [&](int i) { return s->i32(4 + i * 4); };
    s->width = u(0); s->height = u(1); s->nStyles = u(2); s->nPaths = u(3); s->nImages = u(4); s->nOps = u(5); s->nXY = u(6);
    s->gx = u(7); s->gy = u(8);
    s->stylesAt = 40; s->pathsAt = s->stylesAt + (size_t)s->nStyles * 16; s->opsAt = s->pathsAt + (size_t)s->nPaths * 32;
    s->xyAt = s->opsAt + (((size_t)s->nOps + 3) & ~(size_t)3); s->cellsAt = s->xyAt + (size_t)s->nXY * 4;
    s->entriesAt = s->cellsAt + ((size_t)s->gx * s->gy + 1) * 4;
    size_t o = s->entriesAt + (size_t)s->i32(s->cellsAt + (size_t)s->gx * s->gy * 4) * 4;
    for (int i = 0; i < s->nImages && o + 24 <= n; i++) {
        Sheet::Img im = {s->i32(o), s->i32(o + 4), s->i32(o + 8), s->i32(o + 12), s->i32(o + 16), o + 24, (size_t)s->i32(o + 20)};
        s->images.push_back(im);
        o += 24 + ((im.len + 3) & ~(size_t)3);
    }
    return s;
}

static void sheet_unref(Sheet *s) { if (s && s->refs.fetch_sub(1) == 1) delete s; }

// the owner's reference: the sheet goes once its queued and running tiles are done too
extern "C" void kks_sheet_close(void *s) { sheet_unref((Sheet *)s); }
extern "C" int kks_sheets_alive(void) { return g_sheets.load(); }
extern "C" int kks_sheet_width(void *s) { return ((Sheet *)s)->width; }    // quanta (1/64 pt)
extern "C" int kks_sheet_height(void *s) { return ((Sheet *)s)->height; }

static void visible(const Sheet &s, int x0, int y0, int x1, int y1, std::vector<int> &out) {
    auto cell = [](int v, int size, int n) { int x = std::clamp(v, 0, std::max(0, size - 1));
                                             return std::min(n - 1, (int)(((long long)x * n) / std::max(1, size))); };
    std::vector<bool> seen((size_t)s.nPaths);
    for (int cy = cell(y0, s.height, s.gy); cy <= cell(y1, s.height, s.gy); cy++)
        for (int cx = cell(x0, s.width, s.gx); cx <= cell(x1, s.width, s.gx); cx++) {
            size_t c = (size_t)cy * s.gx + cx;
            int a = s.i32(s.cellsAt + c * 4), e = s.i32(s.cellsAt + (c + 1) * 4);
            for (int k = a; k < e; k++) seen[(size_t)s.i32(s.entriesAt + (size_t)k * 4)] = true;
        }
    for (int i = 0; i < s.nPaths; i++) if (seen[(size_t)i]) out.push_back(i);
}

// one tile: `size` px square at tz px/pt from (x0, y0) pt, white background → BGRA (premultiplied); dark: dark
// drawings (the dark paper, every path colour and embedded image turned)
static bool render_tile(const Sheet &s, float tz, float x0, float y0, int size, bool dark, std::vector<uint8_t> &out) {
    IWICBitmap *bmp = nullptr;
    ID2D1RenderTarget *rt = nullptr;
    if (FAILED(g_wic->CreateBitmap(size, size, GUID_WICPixelFormat32bppPBGRA, WICBitmapCacheOnLoad, &bmp))) return false;
    D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    if (FAILED(g_d2d->CreateWicBitmapRenderTarget(bmp, &p, &rt))) { release(bmp); return false; }
    float k = tz / 64.f;                         // px per quantum
    int qx0 = (int)std::floor(x0 * 64), qy0 = (int)std::floor(y0 * 64);
    int qx1 = (int)std::ceil((x0 + size / tz) * 64), qy1 = (int)std::ceil((y0 + size / tz) * 64);
    float px1 = 1.f / k;
    rt->BeginDraw();
    if (dark) rt->Clear(D2D1::ColorF(DARK_LO / 255.f, DARK_LO / 255.f, DARK_LO / 255.f, 1));
    else rt->Clear(D2D1::ColorF(1, 1, 1, 1));
    auto color = [&](size_t at) {
        uint8_t r = s.b[at], g = s.b[at + 1], b = s.b[at + 2];
        if (dark) dark_px(r, g, b);
        return D2D1::ColorF(r / 255.f, g / 255.f, b / 255.f, 1);
    };
    rt->SetTransform(D2D1::Matrix3x2F::Translation(-x0 * 64.f, -y0 * 64.f) * D2D1::Matrix3x2F::Scale(k, k));
    ID2D1SolidColorBrush *brush = nullptr;
    rt->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &brush);
    std::vector<Sheet::Img> imgs;
    for (auto &im : s.images) if (im.x1 >= qx0 && im.x0 <= qx1 && im.y1 >= qy0 && im.y0 <= qy1) imgs.push_back(im);
    std::sort(imgs.begin(), imgs.end(), [](const Sheet::Img &a, const Sheet::Img &b) { return a.after < b.after; });
    size_t ii = 0;
    auto drawImage = [&](const Sheet::Img &im) {
        std::vector<uint8_t> px; int w = 0, h = 0;
        if (!jxl_bgra(&s.b[im.at], im.len, px, w, h, dark)) return;
        ID2D1Bitmap *b = nullptr;
        if (SUCCEEDED(rt->CreateBitmap(D2D1::SizeU(w, h), px.data(), w * 4,
                D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED)), &b))) {
            rt->DrawBitmap(b, D2D1::RectF((float)im.x0, (float)im.y0, (float)im.x1, (float)im.y1));
            release(b);
        }
    };
    std::vector<int> paths;
    visible(s, qx0, qy0, qx1, qy1, paths);
    for (int i : paths) {
        while (ii < imgs.size() && imgs[ii].after <= i) drawImage(imgs[ii++]);
        size_t pa = s.pathsAt + (size_t)i * 32;
        if (s.i32(pa + 12) < qx0 || s.i32(pa + 4) > qx1 || s.i32(pa + 16) < qy0 || s.i32(pa + 8) > qy1) continue;
        size_t st = s.stylesAt + (size_t)s.i32(pa) * 16;
        int kind = s.b[st];
        int cmdStart = s.i32(pa + 20), cmdCount = s.i32(pa + 24), pt = s.i32(pa + 28);
        ID2D1PathGeometry *geo = nullptr;
        ID2D1GeometrySink *sink = nullptr;
        if (FAILED(g_d2d->CreatePathGeometry(&geo)) || FAILED(geo->Open(&sink))) { release(geo); continue; }
        sink->SetFillMode((kind & 4) ? D2D1_FILL_MODE_ALTERNATE : D2D1_FILL_MODE_WINDING);
        auto X = [&](int n) { return (float)s.i32(s.xyAt + ((size_t)pt * 2 + n) * 4); };
        bool open = false;
        D2D1_FIGURE_BEGIN fb = (kind & 2) ? D2D1_FIGURE_BEGIN_FILLED : D2D1_FIGURE_BEGIN_HOLLOW;
        D2D1_POINT_2F m = {0, 0};
        for (int j = 0; j < cmdCount; j++) {
            switch (s.b[s.opsAt + (size_t)cmdStart + j]) {
            case 0:
                if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
                m = D2D1::Point2F(X(0), X(1)); sink->BeginFigure(m, fb); open = true; pt += 1; break;
            case 1:
                if (!open) { sink->BeginFigure(m, fb); open = true; }
                sink->AddLine(D2D1::Point2F(X(0), X(1))); pt += 1; break;
            case 2:
                if (!open) { sink->BeginFigure(m, fb); open = true; }
                sink->AddBezier(D2D1::BezierSegment(D2D1::Point2F(X(0), X(1)), D2D1::Point2F(X(2), X(3)), D2D1::Point2F(X(4), X(5))));
                pt += 3; break;
            default:   // close: the next segment starts at the figure's start again
                if (open) { sink->EndFigure(D2D1_FIGURE_END_CLOSED); open = false; }
                break;
            }
        }
        if (open) sink->EndFigure(D2D1_FIGURE_END_OPEN);
        sink->Close();
        release(sink);
        if (kind & 2) {
            brush->SetColor(color(st + 11));
            rt->FillGeometry(geo, brush);
        }
        if (kind & 1) {
            float wq = (float)s.i32(st + 4);
            float sw = (kind & 8) ? px1 : std::max(wq, px1);
            D2D1_CAP_STYLE cap = s.b[st + 1] == 1 ? D2D1_CAP_STYLE_ROUND : s.b[st + 1] == 2 ? D2D1_CAP_STYLE_SQUARE : D2D1_CAP_STYLE_FLAT;
            D2D1_LINE_JOIN join = s.b[st + 2] == 1 ? D2D1_LINE_JOIN_ROUND : s.b[st + 2] == 2 ? D2D1_LINE_JOIN_BEVEL : D2D1_LINE_JOIN_MITER;
            ID2D1StrokeStyle *ss = nullptr;
            g_d2d->CreateStrokeStyle(D2D1::StrokeStyleProperties(cap, cap, cap, join, 10.f), nullptr, 0, &ss);
            brush->SetColor(color(st + 8));
            rt->DrawGeometry(geo, brush, sw, ss);
            release(ss);
        }
        release(geo);
    }
    while (ii < imgs.size()) drawImage(imgs[ii++]);
    release(brush);
    HRESULT hr = rt->EndDraw();
    release(rt);
    bool ok = SUCCEEDED(hr);
    if (ok) {
        out.resize((size_t)size * size * 4);
        WICRect r = {0, 0, size, size};
        ok = SUCCEEDED(bmp->CopyPixels(&r, size * 4, (UINT)out.size(), out.data()));
    }
    release(bmp);
    return ok;
}

// ---------------------------------------------------------------- the worker pool: tiles and JPEG XL decodes

struct Job { long long key; int kind; void *sheet; float tz, x0, y0; int size; bool dark; std::vector<uint8_t> data; };
struct Done { long long key; std::vector<uint8_t> px; int w, h; bool ok; };

static std::mutex g_mu;
static std::condition_variable g_cv;
static std::deque<Job> g_jobs;
static std::deque<Done> g_done;
static std::vector<std::thread> g_workers;
static std::atomic<int> g_gen{0};

static void worker() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    for (;;) {
        Job j;
        {
            std::unique_lock<std::mutex> l(g_mu);
            g_cv.wait(l, [] { return !g_jobs.empty(); });
            j = std::move(g_jobs.front());
            g_jobs.pop_front();
        }
        Done d{j.key, {}, 0, 0, false};
        if (j.kind == 0) { d.ok = render_tile(*(Sheet *)j.sheet, j.tz, j.x0, j.y0, j.size, j.dark, d.px); d.w = d.h = j.size; }
        else d.ok = jxl_bgra(j.data.data(), j.data.size(), d.px, d.w, d.h, j.dark);
        {
            std::lock_guard<std::mutex> l(g_mu);
            g_done.push_back(std::move(d));
        }
        if (j.kind == 0) sheet_unref((Sheet *)j.sheet);    // after the result is out: a sheet gone means its tiles are done
    }
}

static void start_workers() {
    if (!g_workers.empty()) return;
    unsigned n = std::max(2u, std::thread::hardware_concurrency() > 2 ? std::thread::hardware_concurrency() - 2 : 2u);
    for (unsigned i = 0; i < n; i++) { g_workers.emplace_back(worker); g_workers.back().detach(); }
}

// the job holds a reference to the sheet: the caller may close it at once (it drops results of an old generation by key)
extern "C" void kks_tile_request(long long key, void *sheet, float tz, float x0, float y0, int size, int dark) {
    start_workers();
    ((Sheet *)sheet)->refs++;
    std::lock_guard<std::mutex> l(g_mu);
    g_jobs.push_back(Job{key, 0, sheet, tz, x0, y0, size, dark != 0, {}});
    g_cv.notify_one();
}

// dark: decoded for dark drawings (an overview level)
extern "C" void kks_jxl_request(long long key, const uint8_t *data, size_t n, int dark) {
    start_workers();
    std::lock_guard<std::mutex> l(g_mu);
    g_jobs.push_back(Job{key, 1, nullptr, 0, 0, 0, 0, dark != 0, std::vector<uint8_t>(data, data + n)});
    g_cv.notify_one();
}

// the queued jobs go (their sheets' references with them); jobs already running finish and report as usual
extern "C" void kks_jobs_clear(void) {
    std::deque<Job> dropped;
    {
        std::lock_guard<std::mutex> l(g_mu);
        dropped.swap(g_jobs);
    }
    for (auto &j : dropped) if (j.kind == 0) sheet_unref((Sheet *)j.sheet);
}
extern "C" int kks_jobs_queued(void) { std::lock_guard<std::mutex> l(g_mu); return (int)g_jobs.size(); }

// a finished job: returns 1 and fills key/size/pixels (malloc'd, the caller frees with kks_free), else 0
extern "C" int kks_job_done(long long *key, int *w, int *h, uint8_t **px) {
    std::lock_guard<std::mutex> l(g_mu);
    if (g_done.empty()) return 0;
    Done d = std::move(g_done.front());
    g_done.pop_front();
    *key = d.key; *w = d.ok ? d.w : 0; *h = d.ok ? d.h : 0;
    *px = nullptr;
    if (d.ok) { *px = (uint8_t *)malloc(d.px.size()); memcpy(*px, d.px.data(), d.px.size()); }
    return 1;
}
extern "C" void kks_free(void *p) { free(p); }

// decode a JXL now (photos), BGRA premultiplied; 0 on failure
extern "C" uint8_t *kks_jxl_decode(const uint8_t *data, size_t n, int *w, int *h) {
    std::vector<uint8_t> px;
    if (!jxl_bgra(data, n, px, *w, *h)) return nullptr;
    uint8_t *o = (uint8_t *)malloc(px.size());
    memcpy(o, px.data(), px.size());
    return o;
}

// ---------------------------------------------------------------- the window's render target

struct View {
    HWND hwnd;
    ID2D1HwndRenderTarget *rt = nullptr;
    ID2D1SolidColorBrush *brush = nullptr;
    ID2D1StrokeStyle *dash = nullptr;
    std::vector<ID2D1Bitmap *> bitmaps;   // handle = index + 1
};

static bool ensure(View *v) {
    if (v->rt) return true;
    RECT r; GetClientRect(v->hwnd, &r);
    D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties();
    if (FAILED(g_d2d->CreateHwndRenderTarget(p, D2D1::HwndRenderTargetProperties(v->hwnd,
            D2D1::SizeU(std::max(1L, r.right - r.left), std::max(1L, r.bottom - r.top))), &v->rt))) return false;
    v->rt->SetDpi(96, 96);                 // we work in physical pixels
    v->rt->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &v->brush);
    float d[] = {4, 3};
    g_d2d->CreateStrokeStyle(D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_FLAT, D2D1_CAP_STYLE_FLAT, D2D1_CAP_STYLE_FLAT,
        D2D1_LINE_JOIN_MITER, 10.f, D2D1_DASH_STYLE_CUSTOM, 0), d, 2, &v->dash);
    return true;
}

static void drop_device(View *v) {
    for (auto &b : v->bitmaps) release(b);
    v->bitmaps.clear();
    release(v->brush); release(v->dash); release(v->rt);
}

extern "C" void *kks_view_new(HWND hwnd) { View *v = new View(); v->hwnd = hwnd; return v; }
extern "C" void kks_view_free(void *p) { View *v = (View *)p; drop_device(v); delete v; }
extern "C" void kks_view_resize(void *p, int w, int h) { View *v = (View *)p; if (v->rt) v->rt->Resize(D2D1::SizeU(w, h)); }

// upload pixels as a bitmap the view can draw; returns a handle (> 0), 0 on failure
extern "C" int kks_view_bitmap(void *p, const uint8_t *bgra, int w, int h) {
    View *v = (View *)p;
    if (!ensure(v)) return 0;
    ID2D1Bitmap *b = nullptr;
    if (FAILED(v->rt->CreateBitmap(D2D1::SizeU(w, h), bgra, w * 4,
            D2D1::BitmapProperties(D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED)), &b))) return 0;
    for (size_t i = 0; i < v->bitmaps.size(); i++) if (!v->bitmaps[i]) { v->bitmaps[i] = b; return (int)i + 1; }
    v->bitmaps.push_back(b);
    return (int)v->bitmaps.size();
}
extern "C" void kks_view_bitmap_free(void *p, int h) {
    View *v = (View *)p;
    if (h > 0 && (size_t)h <= v->bitmaps.size()) release(v->bitmaps[(size_t)h - 1]);
}
// after a lost device all bitmap handles are gone: the caller re-uploads
extern "C" int kks_view_begin(void *p, float r, float g, float b) {
    View *v = (View *)p;
    if (!ensure(v)) return 0;
    v->rt->BeginDraw();
    v->rt->Clear(D2D1::ColorF(r, g, b, 1));
    return 1;
}
extern "C" void kks_view_draw_bitmap(void *p, int h, float x0, float y0, float x1, float y1, int smooth) {
    View *v = (View *)p;
    if (h > 0 && (size_t)h <= v->bitmaps.size() && v->bitmaps[(size_t)h - 1])
        v->rt->DrawBitmap(v->bitmaps[(size_t)h - 1], D2D1::RectF(x0, y0, x1, y1), 1.f,
                          smooth ? D2D1_BITMAP_INTERPOLATION_MODE_LINEAR : D2D1_BITMAP_INTERPOLATION_MODE_NEAREST_NEIGHBOR);
}
// a clip rectangle until kks_view_unclip (the photo editor's loupe)
extern "C" void kks_view_clip(void *p, float x0, float y0, float x1, float y1) {
    ((View *)p)->rt->PushAxisAlignedClip(D2D1::RectF(x0, y0, x1, y1), D2D1_ANTIALIAS_MODE_ALIASED);
}
extern "C" void kks_view_unclip(void *p) { ((View *)p)->rt->PopAxisAlignedClip(); }
extern "C" void kks_view_rect(void *p, float x0, float y0, float x1, float y1, unsigned rgb, float alpha, int fill, float width, int dashed) {
    View *v = (View *)p;
    v->brush->SetColor(D2D1::ColorF(rgb, alpha));
    D2D1_RECT_F r = D2D1::RectF(x0, y0, x1, y1);
    if (fill) v->rt->FillRectangle(r, v->brush);
    else v->rt->DrawRectangle(r, v->brush, width, dashed ? v->dash : nullptr);
}
// returns 1, or 0 when the device was lost (the caller re-uploads its bitmaps)
extern "C" int kks_view_end(void *p) {
    View *v = (View *)p;
    HRESULT hr = v->rt->EndDraw();
    if (hr == D2DERR_RECREATE_TARGET) { drop_device(v); return 0; }
    return 1;
}

// ---------------------------------------------------------------- lines and ellipses (the photo annotation editor)

extern "C" void kks_view_line(void *p, float x0, float y0, float x1, float y1, unsigned rgb, float width) {
    View *v = (View *)p;
    v->brush->SetColor(D2D1::ColorF(rgb, 1));
    v->rt->DrawLine(D2D1::Point2F(x0, y0), D2D1::Point2F(x1, y1), v->brush, width);
}
extern "C" void kks_view_ellipse(void *p, float x0, float y0, float x1, float y1, unsigned rgb, float width) {
    View *v = (View *)p;
    v->brush->SetColor(D2D1::ColorF(rgb, 1));
    v->rt->DrawEllipse(D2D1::Ellipse(D2D1::Point2F((x0 + x1) / 2, (y0 + y1) / 2), std::fabs(x1 - x0) / 2, std::fabs(y1 - y0) / 2), v->brush, width);
}

// marks (kind 0 arrow, 1 box, 2 circle; rgb; x0, y0, x1, y1 in image px) burned into straight RGBA, in place
struct Mark { int kind; unsigned rgb; float x0, y0, x1, y1; float size; };   // size: × the base line width
extern "C" int kks_burn_marks(uint8_t *rgba, int w, int h, const Mark *marks, int n) {
    if (n == 0) return 0;
    if (kks_d2d_init() != 0) return 1;
    IWICBitmap *bmp = nullptr;
    // RGBA → premultiplied BGRA for the render target
    std::vector<uint8_t> px((size_t)w * h * 4);
    for (size_t i = 0; i < px.size(); i += 4) {
        uint8_t a = rgba[i + 3];
        px[i] = (uint8_t)(rgba[i + 2] * a / 255); px[i + 1] = (uint8_t)(rgba[i + 1] * a / 255); px[i + 2] = (uint8_t)(rgba[i] * a / 255); px[i + 3] = a;
    }
    if (FAILED(g_wic->CreateBitmapFromMemory(w, h, GUID_WICPixelFormat32bppPBGRA, w * 4, (UINT)px.size(), px.data(), &bmp))) return 2;
    ID2D1RenderTarget *rt = nullptr;
    D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_SOFTWARE,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    if (FAILED(g_d2d->CreateWicBitmapRenderTarget(bmp, &p, &rt))) { release(bmp); return 3; }
    ID2D1SolidColorBrush *br = nullptr;
    rt->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &br);
    ID2D1StrokeStyle *round = nullptr;
    g_d2d->CreateStrokeStyle(D2D1::StrokeStyleProperties(D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
                             D2D1_LINE_JOIN_ROUND), nullptr, 0, &round);
    float sw0 = std::max(3.f, w / 200.f);
    rt->BeginDraw();
    for (int i = 0; i < n; i++) {
        const Mark &m = marks[i];
        float sw = sw0 * (m.size > 0 ? m.size : 1.f);
        br->SetColor(D2D1::ColorF(m.rgb, 1));
        if (m.kind == 1) rt->DrawRectangle(D2D1::RectF(std::min(m.x0, m.x1), std::min(m.y0, m.y1), std::max(m.x0, m.x1), std::max(m.y0, m.y1)), br, sw);
        else if (m.kind == 2) rt->DrawEllipse(D2D1::Ellipse(D2D1::Point2F((m.x0 + m.x1) / 2, (m.y0 + m.y1) / 2),
                                                             std::fabs(m.x1 - m.x0) / 2, std::fabs(m.y1 - m.y0) / 2), br, sw);
        else {
            rt->DrawLine(D2D1::Point2F(m.x0, m.y0), D2D1::Point2F(m.x1, m.y1), br, sw, round);
            float a = std::atan2(m.y1 - m.y0, m.x1 - m.x0), head = sw * 5;
            for (float s : {-0.5f, 0.5f})
                rt->DrawLine(D2D1::Point2F(m.x1, m.y1), D2D1::Point2F(m.x1 - head * std::cos(a + s), m.y1 - head * std::sin(a + s)), br, sw, round);
        }
    }
    HRESULT hr = rt->EndDraw();
    release(round); release(br); release(rt);
    if (SUCCEEDED(hr)) {
        WICRect r = {0, 0, w, h};
        bmp->CopyPixels(&r, w * 4, (UINT)px.size(), px.data());
        for (size_t i = 0; i < px.size(); i += 4) {      // back to straight RGBA
            uint8_t a = px[i + 3];
            uint8_t b = px[i], g = px[i + 1], rr = px[i + 2];
            rgba[i] = a ? (uint8_t)std::min(255, rr * 255 / a) : 0; rgba[i + 1] = a ? (uint8_t)std::min(255, g * 255 / a) : 0;
            rgba[i + 2] = a ? (uint8_t)std::min(255, b * 255 / a) : 0; rgba[i + 3] = a;
        }
    }
    release(bmp);
    return SUCCEEDED(hr) ? 0 : 4;
}
