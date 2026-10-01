// A course figure's drawing backend on Windows (decision 0036): Direct2D for shapes, DirectWrite for text, the C API
// apps/common/figdraw.nim's Backend calls. The course faces (vendored WOFF2) are unpacked by DirectWrite
// (IDWriteFactory5::UnpackFontFile, Windows 10 1703+) into an in-memory font collection; without them the system faces
// stand in (Segoe UI, Arial Narrow, Consolas).
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d2d1.h>
#include <dwrite_3.h>
#include <cmath>
#include <string>
#include <vector>
#include <algorithm>

template <class T> static void rel(T *&p) { if (p) { p->Release(); p = nullptr; } }

static ID2D1Factory *g_f = nullptr;
static IDWriteFactory *g_dw = nullptr;
static IDWriteFontCollection *g_fonts = nullptr;   // the course faces, or null (system collection)
static bool g_faces = false;

extern "C" int kks_fig_init(void) {
    if (g_f) return 0;
    D2D1_FACTORY_OPTIONS o = {};
    if (FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, __uuidof(ID2D1Factory), &o, (void **)&g_f))) return 1;
    if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory), (IUnknown **)&g_dw))) return 2;
    return 0;
}

// the course faces from WOFF2 files: 1 when DirectWrite took them, 0 otherwise (system faces then)
extern "C" int kks_fig_fonts(const unsigned char **data, const size_t *sizes, int n) {
    if (kks_fig_init() != 0) return 0;
    IDWriteFactory5 *f5 = nullptr;
    if (FAILED(g_dw->QueryInterface(__uuidof(IDWriteFactory5), (void **)&f5))) return 0;
    IDWriteInMemoryFontFileLoader *loader = nullptr;
    IDWriteFontSetBuilder1 *b = nullptr;
    int added = 0;
    if (SUCCEEDED(f5->CreateInMemoryFontFileLoader(&loader)) && SUCCEEDED(f5->RegisterFontFileLoader(loader)) &&
        SUCCEEDED(f5->CreateFontSetBuilder(&b))) {
        for (int i = 0; i < n; i++) {
            IDWriteFontFileStream *s = nullptr;
            if (FAILED(f5->UnpackFontFile(DWRITE_CONTAINER_TYPE_WOFF2, data[i], (UINT32)sizes[i], &s))) continue;
            UINT64 size = 0;
            const void *frag = nullptr;
            void *ctx = nullptr;
            IDWriteFontFile *file = nullptr;
            if (SUCCEEDED(s->GetFileSize(&size)) && SUCCEEDED(s->ReadFileFragment(&frag, 0, size, &ctx))) {
                if (SUCCEEDED(loader->CreateInMemoryFontFileReference(f5, frag, (UINT32)size, nullptr, &file))) {
                    if (SUCCEEDED(b->AddFontFile(file))) added++;
                    rel(file);
                }
                s->ReleaseFileFragment(ctx);
            }
            rel(s);
        }
        IDWriteFontSet *set = nullptr;
        IDWriteFontCollection1 *col = nullptr;
        if (added > 0 && SUCCEEDED(b->CreateFontSet(&set)) && SUCCEEDED(f5->CreateFontCollectionFromFontSet(set, &col))) {
            g_fonts = col;
            g_faces = true;
        }
        rel(set);
    }
    rel(b);
    rel(f5);
    return g_faces ? 1 : 0;
}

struct Fig {
    HWND hwnd;
    ID2D1HwndRenderTarget *rt = nullptr;
    ID2D1SolidColorBrush *brush = nullptr;
    std::vector<D2D1_MATRIX_3X2_F> saved;
    std::vector<int> layersAt;        // layers pushed since each save
    int layers = 0;
    std::vector<int> layerKinds;      // 0 opacity, 1 clip
    ID2D1PathGeometry *geo = nullptr;
    ID2D1GeometrySink *sink = nullptr;
    bool open = false;
    D2D1_POINT_2F start{0, 0}, cur{0, 0};
};

static bool ensure(Fig *f) {
    if (f->rt) return true;
    RECT r; GetClientRect(f->hwnd, &r);
    D2D1_RENDER_TARGET_PROPERTIES p = D2D1::RenderTargetProperties();
    if (FAILED(g_f->CreateHwndRenderTarget(p, D2D1::HwndRenderTargetProperties(f->hwnd,
            D2D1::SizeU(std::max(1L, r.right - r.left), std::max(1L, r.bottom - r.top))), &f->rt))) return false;
    f->rt->SetDpi(96, 96);
    f->rt->SetAntialiasMode(D2D1_ANTIALIAS_MODE_PER_PRIMITIVE);
    f->rt->CreateSolidColorBrush(D2D1::ColorF(0, 0, 0, 1), &f->brush);
    return true;
}

static void endPath(Fig *f) {
    if (f->sink) {
        if (f->open) f->sink->EndFigure(D2D1_FIGURE_END_OPEN);
        f->open = false;
        f->sink->Close();
        rel(f->sink);
    }
}

extern "C" void *kks_fig_new(HWND h) { kks_fig_init(); Fig *f = new Fig(); f->hwnd = h; return f; }
extern "C" void kks_fig_free(void *p) {
    Fig *f = (Fig *)p;
    endPath(f); rel(f->geo); rel(f->brush); rel(f->rt);
    delete f;
}
extern "C" void kks_fig_resize(void *p, int w, int h) { Fig *f = (Fig *)p; if (f->rt) f->rt->Resize(D2D1::SizeU(w, h)); }

// begin a frame: clear to the background, then draw in figure units (scale, offset)
extern "C" int kks_fig_begin(void *p, float r, float g, float b, float scale, float ox) {
    Fig *f = (Fig *)p;
    if (!ensure(f)) return 0;
    f->rt->BeginDraw();
    f->rt->Clear(D2D1::ColorF(r, g, b, 1));
    f->rt->SetTransform(D2D1::Matrix3x2F::Scale(scale, scale) * D2D1::Matrix3x2F::Translation(ox, 0));
    f->saved.clear(); f->layersAt.clear(); f->layers = 0; f->layerKinds.clear();
    return 1;
}
extern "C" int kks_fig_end(void *p) {
    Fig *f = (Fig *)p;
    endPath(f); rel(f->geo);
    while (f->layers > 0) { f->rt->PopLayer(); f->layers--; }
    HRESULT hr = f->rt->EndDraw();
    if (hr == D2DERR_RECREATE_TARGET) { rel(f->brush); rel(f->rt); return 0; }
    return 1;
}

extern "C" void kks_fig_save(void *p) {
    Fig *f = (Fig *)p;
    D2D1_MATRIX_3X2_F m; f->rt->GetTransform(&m);
    f->saved.push_back(m);
    f->layersAt.push_back(f->layers);
}
extern "C" void kks_fig_restore(void *p) {
    Fig *f = (Fig *)p;
    if (f->saved.empty()) return;
    int keep = f->layersAt.back();
    while (f->layers > keep) {
        if (f->layerKinds.back() == 1) f->rt->PopAxisAlignedClip(); else f->rt->PopLayer();
        f->layerKinds.pop_back(); f->layers--;
    }
    f->rt->SetTransform(f->saved.back());
    f->saved.pop_back(); f->layersAt.pop_back();
}
static void premul(Fig *f, const D2D1_MATRIX_3X2_F &m) {
    D2D1_MATRIX_3X2_F cur; f->rt->GetTransform(&cur);
    f->rt->SetTransform(m * cur);
}
extern "C" void kks_fig_translate(void *p, float x, float y) { premul((Fig *)p, D2D1::Matrix3x2F::Translation(x, y)); }
extern "C" void kks_fig_rotate(void *p, float rad) { premul((Fig *)p, D2D1::Matrix3x2F::Rotation(rad * 180.f / 3.14159265358979f)); }
extern "C" void kks_fig_scale(void *p, float x, float y) { premul((Fig *)p, D2D1::Matrix3x2F::Scale(x, y)); }

extern "C" void kks_fig_push_opacity(void *p, float a) {
    Fig *f = (Fig *)p;
    ID2D1Layer *l = nullptr;
    if (FAILED(f->rt->CreateLayer(&l))) return;
    f->rt->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), nullptr, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE,
                                           D2D1::IdentityMatrix(), a), l);
    rel(l);
    f->layers++; f->layerKinds.push_back(0);
}
extern "C" void kks_fig_pop_opacity(void *p) {
    Fig *f = (Fig *)p;
    if (f->layers > 0 && f->layerKinds.back() == 0) { f->rt->PopLayer(); f->layers--; f->layerKinds.pop_back(); }
}
extern "C" void kks_fig_clip_round_rect(void *p, float x, float y, float w, float h, float rx) {
    Fig *f = (Fig *)p;
    rx = std::max(0.f, std::min(rx, std::min(w / 2, h / 2)));
    ID2D1RoundedRectangleGeometry *g = nullptr;
    if (FAILED(g_f->CreateRoundedRectangleGeometry(D2D1::RoundedRect(D2D1::RectF(x, y, x + w, y + h), rx, rx), &g))) return;
    ID2D1Layer *l = nullptr;
    if (SUCCEEDED(f->rt->CreateLayer(&l))) {
        D2D1_MATRIX_3X2_F m; f->rt->GetTransform(&m);
        f->rt->PushLayer(D2D1::LayerParameters(D2D1::InfiniteRect(), g, D2D1_ANTIALIAS_MODE_PER_PRIMITIVE, D2D1::IdentityMatrix(), 1.f), l);
        f->layers++; f->layerKinds.push_back(2);
        rel(l);
    }
    rel(g);
}

// ---- one path at a time: begin, then move/line/curve/close, round rects and ellipses; fill and stroke reuse it
static void ensureSink(Fig *f) {
    if (f->sink) return;
    rel(f->geo);
    g_f->CreatePathGeometry(&f->geo);
    f->geo->Open(&f->sink);
    f->sink->SetFillMode(D2D1_FILL_MODE_WINDING);   // SVG's nonzero
}
static void openAt(Fig *f, D2D1_POINT_2F pt) {
    ensureSink(f);
    if (f->open) f->sink->EndFigure(D2D1_FIGURE_END_OPEN);
    f->sink->BeginFigure(pt, D2D1_FIGURE_BEGIN_FILLED);
    f->open = true;
    f->start = f->cur = pt;
}
extern "C" void kks_fig_begin_path(void *p) { Fig *f = (Fig *)p; endPath(f); rel(f->geo); }
extern "C" void kks_fig_move_to(void *p, float x, float y) { openAt((Fig *)p, D2D1::Point2F(x, y)); }
extern "C" void kks_fig_line_to(void *p, float x, float y) {
    Fig *f = (Fig *)p;
    if (!f->open) openAt(f, f->cur);           // after a close, a segment continues from the move point
    f->sink->AddLine(D2D1::Point2F(x, y));
    f->cur = D2D1::Point2F(x, y);
}
extern "C" void kks_fig_curve_to(void *p, float x1, float y1, float x2, float y2, float x, float y) {
    Fig *f = (Fig *)p;
    if (!f->open) openAt(f, f->cur);
    f->sink->AddBezier(D2D1::BezierSegment(D2D1::Point2F(x1, y1), D2D1::Point2F(x2, y2), D2D1::Point2F(x, y)));
    f->cur = D2D1::Point2F(x, y);
}
extern "C" void kks_fig_close(void *p) {
    Fig *f = (Fig *)p;
    if (f->open) { f->sink->EndFigure(D2D1_FIGURE_END_CLOSED); f->open = false; f->cur = f->start; }
}
extern "C" void kks_fig_round_rect(void *p, float x, float y, float w, float h, float rx) {
    Fig *f = (Fig *)p;
    rx = std::max(0.f, std::min(rx, std::min(w / 2, h / 2)));
    openAt(f, D2D1::Point2F(x + rx, y));
    auto arc = [&](float ex, float ey) {
        if (rx > 0) f->sink->AddArc(D2D1::ArcSegment(D2D1::Point2F(ex, ey), D2D1::SizeF(rx, rx), 0,
                                    D2D1_SWEEP_DIRECTION_CLOCKWISE, D2D1_ARC_SIZE_SMALL));
    };
    f->sink->AddLine(D2D1::Point2F(x + w - rx, y)); arc(x + w, y + rx);
    f->sink->AddLine(D2D1::Point2F(x + w, y + h - rx)); arc(x + w - rx, y + h);
    f->sink->AddLine(D2D1::Point2F(x + rx, y + h)); arc(x, y + h - rx);
    f->sink->AddLine(D2D1::Point2F(x, y + rx)); arc(x + rx, y);
    f->sink->EndFigure(D2D1_FIGURE_END_CLOSED); f->open = false;
}
extern "C" void kks_fig_ellipse(void *p, float cx, float cy, float rx, float ry) {
    Fig *f = (Fig *)p;
    if (rx <= 0 || ry <= 0) return;
    openAt(f, D2D1::Point2F(cx + rx, cy));
    f->sink->AddArc(D2D1::ArcSegment(D2D1::Point2F(cx - rx, cy), D2D1::SizeF(rx, ry), 0, D2D1_SWEEP_DIRECTION_CLOCKWISE, D2D1_ARC_SIZE_SMALL));
    f->sink->AddArc(D2D1::ArcSegment(D2D1::Point2F(cx + rx, cy), D2D1::SizeF(rx, ry), 0, D2D1_SWEEP_DIRECTION_CLOCKWISE, D2D1_ARC_SIZE_SMALL));
    f->sink->EndFigure(D2D1_FIGURE_END_CLOSED); f->open = false;
}
static ID2D1PathGeometry *geometry(Fig *f) { endPath(f); return f->geo; }

extern "C" void kks_fig_fill(void *p, float r, float g, float b, float a) {
    Fig *f = (Fig *)p;
    ID2D1PathGeometry *geo = geometry(f);
    if (!geo) return;
    f->brush->SetColor(D2D1::ColorF(r, g, b, a));
    f->rt->FillGeometry(geo, f->brush);
}
// a radial gradient fill: centre, radius, stops (offset, r, g, b, a) × n
extern "C" void kks_fig_fill_radial(void *p, float cx, float cy, float rad, const float *stops, int n) {
    Fig *f = (Fig *)p;
    ID2D1PathGeometry *geo = geometry(f);
    if (!geo || n < 1) return;
    std::vector<D2D1_GRADIENT_STOP> st((size_t)n);
    for (int i = 0; i < n; i++)
        st[(size_t)i] = D2D1::GradientStop(stops[i * 5], D2D1::ColorF(stops[i * 5 + 1], stops[i * 5 + 2], stops[i * 5 + 3], stops[i * 5 + 4]));
    ID2D1GradientStopCollection *c = nullptr;
    ID2D1RadialGradientBrush *br = nullptr;
    if (SUCCEEDED(f->rt->CreateGradientStopCollection(st.data(), (UINT32)n, &c)) &&
        SUCCEEDED(f->rt->CreateRadialGradientBrush(D2D1::RadialGradientBrushProperties(D2D1::Point2F(cx, cy), D2D1::Point2F(0, 0), rad, rad), c, &br)))
        f->rt->FillGeometry(geo, br);
    rel(br); rel(c);
}
extern "C" void kks_fig_stroke(void *p, float r, float g, float b, float a, float width, int cap, int join,
                               const float *dash, int ndash) {
    Fig *f = (Fig *)p;
    ID2D1PathGeometry *geo = geometry(f);
    if (!geo) return;
    D2D1_CAP_STYLE cs = cap == 1 ? D2D1_CAP_STYLE_ROUND : cap == 2 ? D2D1_CAP_STYLE_SQUARE : D2D1_CAP_STYLE_FLAT;
    D2D1_LINE_JOIN js = join == 1 ? D2D1_LINE_JOIN_ROUND : join == 2 ? D2D1_LINE_JOIN_BEVEL : D2D1_LINE_JOIN_MITER_OR_BEVEL;
    std::vector<float> d;
    for (int i = 0; i < ndash; i++) d.push_back(width > 0 ? dash[i] / width : dash[i]);   // D2D dashes are in stroke widths
    ID2D1StrokeStyle *ss = nullptr;
    g_f->CreateStrokeStyle(D2D1::StrokeStyleProperties(cs, cs, cs, js, 4.f, ndash ? D2D1_DASH_STYLE_CUSTOM : D2D1_DASH_STYLE_SOLID, 0),
                           ndash ? d.data() : nullptr, (UINT32)ndash, &ss);
    f->brush->SetColor(D2D1::ColorF(r, g, b, a));
    f->rt->DrawGeometry(geo, f->brush, width, ss);
    rel(ss);
}

// text: UTF-8, baseline at (x, y), anchor 0 start / 1 middle / 2 end, role 0 body / 1 display / 2 mono
extern "C" void kks_fig_text(void *p, const char *utf8, float x, float y, int anchor, int role, float size, int weight,
                             float r, float g, float b, float a) {
    Fig *f = (Fig *)p;
    int n = MultiByteToWideChar(CP_UTF8, 0, utf8, -1, nullptr, 0);
    if (n <= 1) return;
    std::wstring w((size_t)n - 1, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, utf8, -1, &w[0], n);
    const wchar_t *fam = role == 1 ? (g_faces ? L"Barlow Semi Condensed" : L"Arial Narrow")
                       : role == 2 ? (g_faces ? L"JetBrains Mono" : L"Consolas")
                       : (g_faces ? L"Atkinson Hyperlegible" : L"Segoe UI");
    IDWriteTextFormat *tf = nullptr;
    if (FAILED(g_dw->CreateTextFormat(fam, g_faces ? g_fonts : nullptr, (DWRITE_FONT_WEIGHT)weight, DWRITE_FONT_STYLE_NORMAL,
                                      DWRITE_FONT_STRETCH_NORMAL, size, L"en-us", &tf))) return;
    tf->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
    IDWriteTextLayout *tl = nullptr;
    if (SUCCEEDED(g_dw->CreateTextLayout(w.c_str(), (UINT32)w.size(), tf, 100000.f, 1000.f, &tl))) {
        DWRITE_TEXT_METRICS m; tl->GetMetrics(&m);
        DWRITE_LINE_METRICS lm; UINT32 lines = 0;
        tl->GetLineMetrics(&lm, 1, &lines);
        float x0 = anchor == 1 ? x - m.width / 2 : anchor == 2 ? x - m.width : x;
        f->brush->SetColor(D2D1::ColorF(r, g, b, a));
        f->rt->DrawTextLayout(D2D1::Point2F(x0 - m.left, y - lm.baseline), tl, f->brush, D2D1_DRAW_TEXT_OPTIONS_NONE);
        rel(tl);
    }
    rel(tf);
}
