// QR codes through zxing-cpp's C API (decision 0019): draw an invite, read one from a camera frame.
#include <jni.h>
#include <cstring>
#include "ZXingC.h"

static ZXing_BarcodeFormat qrFormat() { return ZXing_BarcodeFormatFromString("QRCode"); }

// text -> grayscale modules (1 byte per module, quiet zone included); dims[0..1] = width, height; null on failure
extern "C" JNIEXPORT jbyteArray JNICALL
Java_kks_explorer_Qr_encode(JNIEnv* env, jclass, jbyteArray text, jintArray dims) {
    jsize n = env->GetArrayLength(text);
    jbyte* t = env->GetByteArrayElements(text, nullptr);
    ZXing_CreatorOptions* co = ZXing_CreatorOptions_new(qrFormat());
    ZXing_CreatorOptions_setOptions(co, "ecLevel=M");
    ZXing_Barcode* bc = ZXing_CreateBarcodeFromText(reinterpret_cast<const char*>(t), n, co);
    env->ReleaseByteArrayElements(text, t, JNI_ABORT);
    ZXing_CreatorOptions_delete(co);
    if (!bc) return nullptr;
    ZXing_WriterOptions* wo = ZXing_WriterOptions_new();
    ZXing_WriterOptions_setScale(wo, 1);
    ZXing_WriterOptions_setAddQuietZones(wo, true);
    ZXing_Image* img = ZXing_WriteBarcodeToImage(bc, wo);
    ZXing_WriterOptions_delete(wo);
    ZXing_Barcode_delete(bc);
    if (!img) return nullptr;
    jint wh[2] = {ZXing_Image_width(img), ZXing_Image_height(img)};
    jbyteArray out = nullptr;
    if (ZXing_Image_format(img) == ZXing_ImageFormat_Lum) {
        out = env->NewByteArray(wh[0] * wh[1]);
        env->SetByteArrayRegion(out, 0, wh[0] * wh[1], reinterpret_cast<const jbyte*>(ZXing_Image_data(img)));
        env->SetIntArrayRegion(dims, 0, 2, wh);
    }
    ZXing_Image_delete(img);
    return out;
}

// a grayscale frame (the camera's Y plane) -> the text of the first QR code in it, or null
extern "C" JNIEXPORT jbyteArray JNICALL
Java_kks_explorer_Qr_decode(JNIEnv* env, jclass, jbyteArray gray, jint w, jint h, jint stride) {
    jbyte* px = env->GetByteArrayElements(gray, nullptr);
    ZXing_ImageView* iv = ZXing_ImageView_new(reinterpret_cast<const uint8_t*>(px), w, h, ZXing_ImageFormat_Lum, stride, 1);
    ZXing_ReaderOptions* ro = ZXing_ReaderOptions_new();
    ZXing_BarcodeFormat f = qrFormat();
    ZXing_ReaderOptions_setFormats(ro, &f, 1);
    ZXing_ReaderOptions_setTryHarder(ro, true);
    ZXing_ReaderOptions_setTryRotate(ro, true);
    ZXing_ReaderOptions_setMaxNumberOfSymbols(ro, 1);
    ZXing_Barcodes* bs = iv ? ZXing_ReadBarcodes(iv, ro) : nullptr;
    jbyteArray out = nullptr;
    if (bs && ZXing_Barcodes_size(bs) > 0) {
        const ZXing_Barcode* b = ZXing_Barcodes_at(bs, 0);
        if (ZXing_Barcode_isValid(b)) {
            char* s = ZXing_Barcode_text(b);
            if (s) {
                jsize len = static_cast<jsize>(strlen(s));
                out = env->NewByteArray(len);
                env->SetByteArrayRegion(out, 0, len, reinterpret_cast<const jbyte*>(s));
                ZXing_free(s);
            }
        }
    }
    if (bs) ZXing_Barcodes_delete(bs);
    ZXing_ReaderOptions_delete(ro);
    if (iv) ZXing_ImageView_delete(iv);
    env->ReleaseByteArrayElements(gray, px, JNI_ABORT);
    return out;
}
