// The invite as a QR code (decision 0019): zxing-cpp's C API, drawn into a GDI bitmap for a STATIC control.
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <cstring>
#include <cstdlib>
#include "ZXing/ZXingC.h"

// text → a black-on-white bitmap, `scale` pixels per module, quiet zone included; NULL on failure
extern "C" HBITMAP kks_qr_bitmap(const char *text, int scale, int *side) {
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
    int w = ZXing_Image_width(img), h = ZXing_Image_height(img);
    const uint8_t *m = ZXing_Image_data(img);
    int W = w * scale, H = h * scale;
    BITMAPINFO bi = {};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = W; bi.bmiHeader.biHeight = -H; bi.bmiHeader.biPlanes = 1; bi.bmiHeader.biBitCount = 32;
    void *bits = nullptr;
    HBITMAP hb = CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (hb) {
        uint32_t *d = (uint32_t *)bits;
        for (int y = 0; y < H; y++) for (int x = 0; x < W; x++)
            d[(size_t)y * W + x] = m[(size_t)(y / scale) * w + x / scale] < 128 ? 0xFF000000u : 0xFFFFFFFFu;
        *side = W;
    }
    ZXing_Image_delete(img);
    return hb;
}

// the text of the first QR code in a grey image (decision 0039), malloc'd; NULL when none was found
extern "C" char *kks_qr_decode(const unsigned char *gray, int w, int h) {
    ZXing_ImageView *iv = ZXing_ImageView_new(gray, w, h, ZXing_ImageFormat_Lum, 0, 0);
    if (!iv) return nullptr;
    ZXing_ReaderOptions *o = ZXing_ReaderOptions_new();
    ZXing_BarcodeFormat f = ZXing_BarcodeFormatFromString("QRCode");
    ZXing_ReaderOptions_setFormats(o, &f, 1);
    ZXing_ReaderOptions_setTryHarder(o, true);
    ZXing_ReaderOptions_setTryRotate(o, true);
    ZXing_ReaderOptions_setTryInvert(o, true);
    ZXing_Barcodes *bs = ZXing_ReadBarcodes(iv, o);
    char *out = nullptr;
    if (bs) {
        for (int i = 0; i < ZXing_Barcodes_size(bs) && !out; i++) {
            const ZXing_Barcode *b = ZXing_Barcodes_at(bs, i);
            if (ZXing_Barcode_isValid(b)) {
                char *t = ZXing_Barcode_text(b);
                if (t) { out = (char *)malloc(strlen(t) + 1); strcpy(out, t); ZXing_free(t); }
            }
        }
        ZXing_Barcodes_delete(bs);
    }
    ZXing_ReaderOptions_delete(o);
    ZXing_ImageView_delete(iv);
    return out;
}
