package kks.explorer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * JPEG XL through libjxl (src/main/cpp): photos are stored as JXL at distance 1.9, effort 9 (the same settings as
 * server/photos.py). The WebView can't show JXL, so the app decodes it and hands the page the pixels as a BMP (no
 * lossy re-encoding, nothing cached on disk).
 */
object Jxl {
    const val DISTANCE = 1.9f
    const val EFFORT = 9
    const val MAX_SIDE = 4096          // the page sends ≤ 1600 px; bigger is scaled down

    init { System.loadLibrary("kksjxl") }

    @JvmStatic private external fun encodeRgba(rgba: ByteArray, width: Int, height: Int, distance: Float, effort: Int): ByteArray?
    @JvmStatic private external fun decodeRgba(data: ByteArray, dims: IntArray): ByteArray?

    /** A PNG / JPEG / WebP -> JXL (orientation applied, metadata dropped). Throws if it can't be read. */
    fun fromImage(bytes: ByteArray): ByteArray {
        var bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inPreferredConfig = Bitmap.Config.ARGB_8888 })
            ?: throw IllegalArgumentException("unreadable image")
        val turn = runCatching {
            when (ExifInterface(bytes.inputStream()).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90; ExifInterface.ORIENTATION_ROTATE_180 -> 180
                ExifInterface.ORIENTATION_ROTATE_270 -> 270; else -> 0
            }
        }.getOrDefault(0)
        if (turn != 0) bmp = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, Matrix().apply { postRotate(turn.toFloat()) }, true)
        val side = maxOf(bmp.width, bmp.height)
        if (side > MAX_SIDE) bmp = Bitmap.createScaledBitmap(bmp, bmp.width * MAX_SIDE / side, bmp.height * MAX_SIDE / side, true)
        if (bmp.config != Bitmap.Config.ARGB_8888) bmp = bmp.copy(Bitmap.Config.ARGB_8888, false)
        val buf = ByteBuffer.allocate(bmp.byteCount)
        bmp.copyPixelsToBuffer(buf)        // memory order R, G, B, A
        return encodeRgba(buf.array(), bmp.width, bmp.height, DISTANCE, EFFORT) ?: throw IllegalStateException("JPEG XL encoding failed")
    }

    /** A JXL file -> a 24-bit BMP of its pixels (for the WebView), or null if it can't be decoded. */
    fun toBmp(jxl: ByteArray): ByteArray? {
        val dims = IntArray(2)
        val px = decodeRgba(jxl, dims) ?: return null
        val (w, h) = dims[0] to dims[1]
        val row = (w * 3 + 3) and 3.inv()
        val out = ByteArray(54 + row * h)
        val b = ByteBuffer.wrap(out).order(ByteOrder.LITTLE_ENDIAN)
        b.put('B'.code.toByte()).put('M'.code.toByte()).putInt(out.size).putInt(0).putInt(54)
        b.putInt(40).putInt(w).putInt(h).putShort(1).putShort(24).putInt(0).putInt(row * h).putInt(2835).putInt(2835).putInt(0).putInt(0)
        for (y in 0 until h) {                 // bottom-up rows, BGR
            var o = 54 + (h - 1 - y) * row
            var s = y * w * 4
            for (x in 0 until w) { out[o++] = px[s + 2]; out[o++] = px[s + 1]; out[o++] = px[s]; s += 4 }
        }
        return out
    }
}
