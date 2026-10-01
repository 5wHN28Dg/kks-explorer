// Photos on Windows (decisions 0018, 0033): read a picture with WIC (JPEG, PNG, … whatever Windows decodes), turned
// upright by its EXIF orientation and scaled to at most `maxSide`; encode JPEG XL with libjxl at the photo settings
// (distance 1.9, effort 9, the same as every client); make a GDI bitmap for a thumbnail.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <wincodec.h>
#include <propvarutil.h>
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include <jxl/thread_parallel_runner.h>
#include <jxl/thread_parallel_runner_cxx.h>
#include <cstring>
#include <vector>
#include <thread>

template <class T> static void release(T *&p) { if (p) { p->Release(); p = nullptr; } }

// path (UTF-16) → RGBA, w, h (malloc'd; free with kks_free). NULL if Windows can't read it.
extern "C" unsigned char *kks_image_load(const wchar_t *path, int maxSide, int *w, int *h) {
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
    IWICImagingFactory *f = nullptr;
    if (FAILED(CoCreateInstance(CLSID_WICImagingFactory, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&f)))) return nullptr;
    IWICBitmapDecoder *dec = nullptr;
    IWICBitmapFrameDecode *frame = nullptr;
    IWICBitmapSource *src = nullptr;
    unsigned char *out = nullptr;
    if (SUCCEEDED(f->CreateDecoderFromFilename(path, nullptr, GENERIC_READ, WICDecodeMetadataCacheOnDemand, &dec)) &&
        SUCCEEDED(dec->GetFrame(0, &frame))) {
        // EXIF orientation (1 = upright, 3 = 180°, 6 = 90° cw, 8 = 270° cw)
        int orient = 1;
        IWICMetadataQueryReader *q = nullptr;
        if (SUCCEEDED(frame->GetMetadataQueryReader(&q))) {
            PROPVARIANT v; PropVariantInit(&v);
            if (SUCCEEDED(q->GetMetadataByName(L"/app1/ifd/{ushort=274}", &v)) && v.vt == VT_UI2) orient = v.uiVal;
            PropVariantClear(&v);
            release(q);
        }
        src = frame; src->AddRef();
        UINT sw = 0, sh = 0;
        src->GetSize(&sw, &sh);
        UINT side = sw > sh ? sw : sh;
        if (maxSide > 0 && side > (UINT)maxSide) {
            IWICBitmapScaler *sc = nullptr;
            if (SUCCEEDED(f->CreateBitmapScaler(&sc)) &&
                SUCCEEDED(sc->Initialize(src, sw * maxSide / side, sh * maxSide / side, WICBitmapInterpolationModeFant))) {
                release(src); src = sc;
            } else release(sc);
        }
        WICBitmapTransformOptions t = orient == 3 ? WICBitmapTransformRotate180 : orient == 6 ? WICBitmapTransformRotate90 :
                                      orient == 8 ? WICBitmapTransformRotate270 : WICBitmapTransformRotate0;
        if (t != WICBitmapTransformRotate0) {
            IWICBitmapFlipRotator *r = nullptr;
            if (SUCCEEDED(f->CreateBitmapFlipRotator(&r)) && SUCCEEDED(r->Initialize(src, t))) { release(src); src = r; }
            else release(r);
        }
        IWICFormatConverter *conv = nullptr;
        if (SUCCEEDED(f->CreateFormatConverter(&conv)) &&
            SUCCEEDED(conv->Initialize(src, GUID_WICPixelFormat32bppRGBA, WICBitmapDitherTypeNone, nullptr, 0, WICBitmapPaletteTypeCustom))) {
            UINT cw = 0, ch = 0;
            conv->GetSize(&cw, &ch);
            out = (unsigned char *)malloc((size_t)cw * ch * 4);
            if (FAILED(conv->CopyPixels(nullptr, cw * 4, cw * ch * 4, out))) { free(out); out = nullptr; }
            else { *w = (int)cw; *h = (int)ch; }
        }
        release(conv);
    }
    release(src); release(frame); release(dec); release(f);
    return out;
}

// RGBA → JPEG XL (lossy, distance, effort); malloc'd bytes, length in *n; NULL on failure
extern "C" unsigned char *kks_jxl_encode(const unsigned char *rgba, int w, int h, float distance, int effort, size_t *n) {
    auto enc = JxlEncoderMake(nullptr);
    auto runner = JxlThreadParallelRunnerMake(nullptr, JxlThreadParallelRunnerDefaultNumWorkerThreads());
    if (JxlEncoderSetParallelRunner(enc.get(), JxlThreadParallelRunner, runner.get()) != JXL_ENC_SUCCESS) return nullptr;
    JxlBasicInfo info;
    JxlEncoderInitBasicInfo(&info);
    info.xsize = (uint32_t)w; info.ysize = (uint32_t)h;
    info.bits_per_sample = 8; info.num_color_channels = 3;
    info.alpha_bits = 8; info.num_extra_channels = 1;
    info.uses_original_profile = JXL_FALSE;
    if (JxlEncoderSetBasicInfo(enc.get(), &info) != JXL_ENC_SUCCESS) return nullptr;
    JxlColorEncoding ce;
    JxlColorEncodingSetToSRGB(&ce, JXL_FALSE);
    if (JxlEncoderSetColorEncoding(enc.get(), &ce) != JXL_ENC_SUCCESS) return nullptr;
    JxlEncoderFrameSettings *fs = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    JxlEncoderSetFrameDistance(fs, distance);
    JxlEncoderFrameSettingsSetOption(fs, JXL_ENC_FRAME_SETTING_EFFORT, effort);
    JxlPixelFormat fmt = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    if (JxlEncoderAddImageFrame(fs, &fmt, rgba, (size_t)w * h * 4) != JXL_ENC_SUCCESS) return nullptr;
    JxlEncoderCloseInput(enc.get());
    std::vector<uint8_t> out(1 << 16);
    uint8_t *next = out.data();
    size_t avail = out.size();
    for (;;) {
        JxlEncoderStatus s = JxlEncoderProcessOutput(enc.get(), &next, &avail);
        if (s == JXL_ENC_SUCCESS) break;
        if (s != JXL_ENC_NEED_MORE_OUTPUT) return nullptr;
        size_t off = (size_t)(next - out.data());
        out.resize(out.size() * 2);
        next = out.data() + off;
        avail = out.size() - off;
    }
    *n = (size_t)(next - out.data());
    unsigned char *r = (unsigned char *)malloc(*n);
    memcpy(r, out.data(), *n);
    return r;
}

// premultiplied BGRA → a 24-bit GDI bitmap no larger than maxW × maxH, on white (thumbnails in STATIC controls)
extern "C" HBITMAP kks_thumb(const unsigned char *bgra, int w, int h, int maxW, int maxH, int *tw, int *th) {
    double s = (double)maxW / w < (double)maxH / h ? (double)maxW / w : (double)maxH / h;
    if (s > 1) s = 1;
    int W = (int)(w * s) > 0 ? (int)(w * s) : 1, H = (int)(h * s) > 0 ? (int)(h * s) : 1;
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = -H; bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32;
    void *bits = nullptr;
    HBITMAP hb = CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!hb) return nullptr;
    unsigned char *d = (unsigned char *)bits;
    for (int y = 0; y < H; y++) for (int x = 0; x < W; x++) {   // nearest sample, alpha over white
        const unsigned char *p = bgra + ((size_t)(y * h / H) * w + (size_t)(x * w / W)) * 4;
        unsigned a = p[3];
        unsigned char *o = d + ((size_t)y * W + x) * 4;
        o[0] = (unsigned char)(p[0] + (255 - a)); o[1] = (unsigned char)(p[1] + (255 - a)); o[2] = (unsigned char)(p[2] + (255 - a)); o[3] = 255;
    }
    *tw = W; *th = H;
    return hb;
}
