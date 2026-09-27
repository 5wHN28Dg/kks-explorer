package kks.explorer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer

/**
 * JPEG XL through libjxl (src/main/cpp): photos are stored as JXL at Butteraugli distance 1.0 (visually lossless, the
 * same setting as server/photos.py); the WebView can't show JXL, so it gets a JPEG made from it (cached).
 */
object Jxl {
    const val DISTANCE = 1.0f
    const val EFFORT = 7
    const val MAX_SIDE = 4096          // the page sends ≤ 1600 px; bigger is scaled down
    const val JPEG_QUALITY = 90

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

    fun toBitmap(jxl: ByteArray): Bitmap? {
        val dims = IntArray(2)
        val px = decodeRgba(jxl, dims) ?: return null
        return Bitmap.createBitmap(dims[0], dims[1], Bitmap.Config.ARGB_8888).apply { copyPixelsFromBuffer(ByteBuffer.wrap(px)) }
    }

    /** The JPEG for a JXL photo file, made once into cacheDir. */
    @Synchronized fun jpegFor(file: File, cacheDir: File): File? {
        val out = File(cacheDir, "photo-jpeg/${file.nameWithoutExtension}.jpg")
        if (out.exists()) return out
        val bmp = toBitmap(file.readBytes()) ?: return null
        out.parentFile!!.mkdirs()
        val tmp = File(out.path + ".part")
        tmp.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it) }
        tmp.renameTo(out)
        return out
    }

    fun jpegBytes(jxl: ByteArray): ByteArray? = toBitmap(jxl)?.let { b -> ByteArrayOutputStream().also { b.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, it) }.toByteArray() }
}
