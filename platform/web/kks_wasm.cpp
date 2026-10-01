// The browser client's native helpers in WebAssembly (decision 0037): JPEG XL (libjxl) decode and encode, QR codes
// (zxing-cpp) read and write. A plain C API over the module's memory; vendor/kks/kks.js wraps it.
// The same calls as android/app2/src/main/cpp/{jxl_jni,qr_jni}.cpp, without threads.
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
#include <jxl/decode.h>
#include <jxl/decode_cxx.h>
#ifndef KKS_DECODE_ONLY
#include <jxl/encode.h>
#include <jxl/encode_cxx.h>
#include "ZXingC.h"
#endif

static uint8_t *copyOut(const uint8_t *p, size_t n) {
    uint8_t *o = (uint8_t *)malloc(n ? n : 1);
    if (o && n) memcpy(o, p, n);
    return o;
}

extern "C" {

void *kks_malloc(size_t n) { return malloc(n); }
void kks_free(void *p) { free(p); }

// JPEG XL → RGBA (8 bits, straight alpha); wh[0..1] = width, height; NULL on failure (the caller frees)
uint8_t *kks_jxl_decode(const uint8_t *data, size_t n, uint32_t *wh) {
    auto dec = JxlDecoderMake(nullptr);
    if (JxlDecoderSubscribeEvents(dec.get(), JXL_DEC_BASIC_INFO | JXL_DEC_FULL_IMAGE) != JXL_DEC_SUCCESS) return nullptr;
    JxlDecoderSetInput(dec.get(), data, n);
    JxlDecoderCloseInput(dec.get());
    JxlBasicInfo info;
    JxlPixelFormat fmt = {4, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    std::vector<uint8_t> px;
    for (;;) {
        JxlDecoderStatus st = JxlDecoderProcessInput(dec.get());
        if (st == JXL_DEC_BASIC_INFO) {
            if (JxlDecoderGetBasicInfo(dec.get(), &info) != JXL_DEC_SUCCESS) return nullptr;
            if ((uint64_t)info.xsize * info.ysize > 100000000ull) return nullptr;
        } else if (st == JXL_DEC_NEED_IMAGE_OUT_BUFFER) {
            size_t size = 0;
            if (JxlDecoderImageOutBufferSize(dec.get(), &fmt, &size) != JXL_DEC_SUCCESS) return nullptr;
            px.resize(size);
            if (JxlDecoderSetImageOutBuffer(dec.get(), &fmt, px.data(), px.size()) != JXL_DEC_SUCCESS) return nullptr;
        } else if (st == JXL_DEC_FULL_IMAGE) {
            continue;
        } else if (st == JXL_DEC_SUCCESS) {
            break;
        } else {
            return nullptr;
        }
    }
    if (px.empty()) return nullptr;
    wh[0] = info.xsize;
    wh[1] = info.ysize;
    return copyOut(px.data(), px.size());
}

#ifndef KKS_DECODE_ONLY   // the decode-only module (photos and drawings in browsers without JPEG XL) stops here

// RGBA (alpha ignored: photos are opaque) → a lossy JXL codestream at `distance`, `effort`; *outlen; NULL on failure
uint8_t *kks_jxl_encode(const uint8_t *rgba, int w, int h, float distance, int effort, size_t *outlen) {
    if (w <= 0 || h <= 0) return nullptr;
    const size_t px = (size_t)w * (size_t)h;
    std::vector<uint8_t> rgb(px * 3);
    for (size_t i = 0; i < px; i++) { rgb[3 * i] = rgba[4 * i]; rgb[3 * i + 1] = rgba[4 * i + 1]; rgb[3 * i + 2] = rgba[4 * i + 2]; }
    auto enc = JxlEncoderMake(nullptr);
    JxlBasicInfo info;
    JxlEncoderInitBasicInfo(&info);
    info.xsize = (uint32_t)w;
    info.ysize = (uint32_t)h;
    info.bits_per_sample = 8;
    info.num_color_channels = 3;
    info.alpha_bits = 0;
    info.uses_original_profile = JXL_FALSE;
    if (JxlEncoderSetBasicInfo(enc.get(), &info) != JXL_ENC_SUCCESS) return nullptr;
    JxlColorEncoding color;
    JxlColorEncodingSetToSRGB(&color, JXL_FALSE);
    if (JxlEncoderSetColorEncoding(enc.get(), &color) != JXL_ENC_SUCCESS) return nullptr;
    JxlEncoderFrameSettings *fs = JxlEncoderFrameSettingsCreate(enc.get(), nullptr);
    if (JxlEncoderSetFrameDistance(fs, distance) != JXL_ENC_SUCCESS) return nullptr;
    JxlEncoderFrameSettingsSetOption(fs, JXL_ENC_FRAME_SETTING_EFFORT, effort);
    JxlPixelFormat fmt = {3, JXL_TYPE_UINT8, JXL_NATIVE_ENDIAN, 0};
    if (JxlEncoderAddImageFrame(fs, &fmt, rgb.data(), rgb.size()) != JXL_ENC_SUCCESS) return nullptr;
    JxlEncoderCloseInput(enc.get());
    std::vector<uint8_t> out(64 * 1024);
    uint8_t *next = out.data();
    size_t avail = out.size();
    JxlEncoderStatus st;
    while ((st = JxlEncoderProcessOutput(enc.get(), &next, &avail)) == JXL_ENC_NEED_MORE_OUTPUT) {
        size_t used = next - out.data();
        out.resize(out.size() * 2);
        next = out.data() + used;
        avail = out.size() - used;
    }
    if (st != JXL_ENC_SUCCESS) return nullptr;
    *outlen = next - out.data();
    return copyOut(out.data(), *outlen);
}

// a grayscale frame → the UTF-8 text of the first QR code (NUL-terminated, the caller frees), or NULL
char *kks_qr_read(const uint8_t *lum, int w, int h) {
    ZXing_ImageView *iv = ZXing_ImageView_new(lum, w, h, ZXing_ImageFormat_Lum, w, 1);
    if (!iv) return nullptr;
    ZXing_ReaderOptions *ro = ZXing_ReaderOptions_new();
    ZXing_BarcodeFormat f = ZXing_BarcodeFormatFromString("QRCode");
    ZXing_ReaderOptions_setFormats(ro, &f, 1);
    ZXing_ReaderOptions_setTryHarder(ro, true);
    ZXing_ReaderOptions_setTryRotate(ro, true);
    ZXing_ReaderOptions_setMaxNumberOfSymbols(ro, 1);
    ZXing_Barcodes *bs = ZXing_ReadBarcodes(iv, ro);
    char *out = nullptr;
    if (bs && ZXing_Barcodes_size(bs) > 0) {
        const ZXing_Barcode *b = ZXing_Barcodes_at(bs, 0);
        if (ZXing_Barcode_isValid(b)) {
            char *s = ZXing_Barcode_text(b);
            if (s) { out = strdup(s); ZXing_free(s); }
        }
    }
    if (bs) ZXing_Barcodes_delete(bs);
    ZXing_ReaderOptions_delete(ro);
    ZXing_ImageView_delete(iv);
    return out;
}

// text → QR modules, 1 byte each (0 dark, 255 light), quiet zone included; *side; NULL on failure (EC level M)
uint8_t *kks_qr_write(const char *text, int *side) {
    ZXing_CreatorOptions *co = ZXing_CreatorOptions_new(ZXing_BarcodeFormatFromString("QRCode"));
    ZXing_CreatorOptions_setOptions(co, "ecLevel=M");
    ZXing_Barcode *bc = ZXing_CreateBarcodeFromText(text, (int)strlen(text), co);
    ZXing_CreatorOptions_delete(co);
    if (!bc) return nullptr;
    ZXing_WriterOptions *wo = ZXing_WriterOptions_new();
    ZXing_WriterOptions_setScale(wo, 1);
    ZXing_WriterOptions_setAddQuietZones(wo, true);
    ZXing_Image *img = ZXing_WriteBarcodeToImage(bc, wo);
    ZXing_WriterOptions_delete(wo);
    ZXing_Barcode_delete(bc);
    if (!img) return nullptr;
    uint8_t *out = nullptr;
    int w = ZXing_Image_width(img), h = ZXing_Image_height(img);
    if (ZXing_Image_format(img) == ZXing_ImageFormat_Lum && w == h) {
        out = copyOut(ZXing_Image_data(img), (size_t)w * h);
        *side = w;
    }
    ZXing_Image_delete(img);
    return out;
}

#endif
}
