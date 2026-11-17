package kks.explorer

import android.graphics.Bitmap
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin

/**
 * Photo scaling with a separable Lanczos-3 filter (decision 0074). Android's own `createScaledBitmap` is bilinear: a
 * reduction by more than a little aliases fine detail (the small letters of a tag plate), and Lanczos measured +0.010
 * SSIM at the same size. Horizontal pass into an 8-bit buffer, then vertical, in fixed point; opaque ARGB only (a
 * photo has no transparency).
 */
object Resample {
    /** the longest side a stored photo may have (every client: web, GNOME, Windows, Android) */
    const val PHOTO_SIDE = 2560

    /** the size [w] × [h] fits in at most [side] px on the longer side; never enlarged */
    fun fit(w: Int, h: Int, side: Int = PHOTO_SIDE): Pair<Int, Int> {
        val m = max(w, h)
        if (m <= side) return w to h
        return max(1, (w.toLong() * side / m).toInt()) to max(1, (h.toLong() * side / m).toInt())
    }

    /** a small copy for a thumbnail, at most [maxH] px high: halved (each halving averages 2 × 2 pixels) while it is
     *  more than twice that, then scaled; [src] itself when it is small enough */
    fun thumbnail(src: Bitmap, maxH: Int): Bitmap {
        var b = src
        while (b.height > maxH * 2) b = Bitmap.createScaledBitmap(b, max(1, b.width / 2), b.height / 2, true).also { if (b !== src) b.recycle() }
        if (b.height <= maxH) return b
        return Bitmap.createScaledBitmap(b, max(1, (b.width.toLong() * maxH / b.height).toInt()), maxH, true).also { if (b !== src) b.recycle() }
    }

    private const val A = 3                // Lanczos-3
    private const val ONE = 1 shl 14       // weights in fixed point

    private fun lanczos(x: Double): Double {
        if (x == 0.0) return 1.0
        if (abs(x) >= A) return 0.0
        val px = PI * x
        return A * sin(px) * sin(px / A) / (px * px)
    }

    /** For each output index: the first input index and its integer weights (summing to ONE). */
    private class Taps(val first: IntArray, val n: Int, val w: IntArray)

    private fun taps(src: Int, dst: Int): Taps {
        val scale = dst.toDouble() / src
        val support = A / min(scale, 1.0)            // the kernel widens when reducing
        val n = ceil(support * 2).toInt() + 1
        val first = IntArray(dst)
        val w = IntArray(dst * n)
        val f = DoubleArray(n)
        for (i in 0 until dst) {
            val centre = (i + 0.5) / scale - 0.5
            val lo = floor(centre - support).toInt() + 1
            var sum = 0.0
            for (k in 0 until n) {
                val x = (lo + k - centre) * min(scale, 1.0)
                f[k] = lanczos(x); sum += f[k]
            }
            first[i] = lo
            var acc = 0
            var big = 0
            for (k in 0 until n) {
                val v = (f[k] / sum * ONE).roundToInt()
                w[i * n + k] = v; acc += v
                if (abs(v) > abs(w[i * n + big])) big = k
            }
            w[i * n + big] += ONE - acc                 // exact sum, so a flat area stays exactly flat
        }
        return Taps(first, n, w)
    }

    private fun clamp8(v: Int): Int = if (v < 0) 0 else if (v > 255 * ONE) 255 else (v + ONE / 2) shr 14

    /** [src] scaled to [dw] × [dh] (opaque ARGB_8888); [src] is left as it is */
    fun scale(src: Bitmap, dw: Int, dh: Int): Bitmap {
        val sw = src.width
        val sh = src.height
        if (sw == dw && sh == dh) return src
        val tx = taps(sw, dw)
        val ty = taps(sh, dh)
        // horizontal: each source row (read one at a time, so the source is never copied whole) into dw pixels
        val mid = IntArray(dw * sh)
        val row = IntArray(sw)
        for (y in 0 until sh) {
            src.getPixels(row, 0, sw, 0, y, sw, 1)
            val o = y * dw
            for (x in 0 until dw) {
                var r = 0; var g = 0; var b = 0
                val lo = tx.first[x]
                val wo = x * tx.n
                for (k in 0 until tx.n) {
                    val p = row[(lo + k).coerceIn(0, sw - 1)]
                    val wk = tx.w[wo + k]
                    r += (p shr 16 and 255) * wk; g += (p shr 8 and 255) * wk; b += (p and 255) * wk
                }
                mid[o + x] = (clamp8(r) shl 16) or (clamp8(g) shl 8) or clamp8(b)
            }
        }
        // vertical
        val out = IntArray(dw * dh)
        for (y in 0 until dh) {
            val lo = ty.first[y]
            val wo = y * ty.n
            val o = y * dw
            for (x in 0 until dw) {
                var r = 0; var g = 0; var b = 0
                for (k in 0 until ty.n) {
                    val p = mid[(lo + k).coerceIn(0, sh - 1) * dw + x]
                    val wk = ty.w[wo + k]
                    r += (p shr 16 and 255) * wk; g += (p shr 8 and 255) * wk; b += (p and 255) * wk
                }
                out[o + x] = (0xff shl 24) or (clamp8(r) shl 16) or (clamp8(g) shl 8) or clamp8(b)
            }
        }
        return Bitmap.createBitmap(out, dw, dh, Bitmap.Config.ARGB_8888)
    }
}
