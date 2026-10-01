package kks.explorer

import android.graphics.Bitmap

/** QR codes through zxing-cpp (decision 0019; src/main/cpp/qr_jni.cpp) */
object Qr {
    init { System.loadLibrary("kksqr") }

    @JvmStatic private external fun encode(text: ByteArray, dims: IntArray): ByteArray?
    @JvmStatic private external fun decode(gray: ByteArray, width: Int, height: Int, stride: Int): ByteArray?

    /** the QR code of text as a bitmap, each module `scale` pixels (black on white, quiet zone included) */
    fun bitmap(text: String, scale: Int = 8): Bitmap? {
        val dims = IntArray(2)
        val m = encode(text.toByteArray(Charsets.UTF_8), dims) ?: return null
        val (w, h) = dims[0] to dims[1]
        val px = IntArray(w * scale * h * scale)
        for (y in 0 until h * scale) for (x in 0 until w * scale)
            px[y * w * scale + x] = if ((m[(y / scale) * w + x / scale].toInt() and 0xff) < 128) 0xff000000.toInt() else -1
        return Bitmap.createBitmap(px, w * scale, h * scale, Bitmap.Config.ARGB_8888)
    }

    /** the text of a QR code in a grayscale frame, or null */
    fun read(gray: ByteArray, width: Int, height: Int, stride: Int = width): String? = decode(gray, width, height, stride)?.toString(Charsets.UTF_8)
}
