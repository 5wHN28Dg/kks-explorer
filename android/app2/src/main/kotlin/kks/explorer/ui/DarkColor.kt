package kks.explorer.ui

/**
 * Dark drawings (a PDF reader's dark mode for the P&IDs), the Android copy of apps/common/darkcolor.nim (and dark.js):
 * each colour's lightness is inverted while its hue stays, then squeezed into [LO, HI], so black lines become a soft
 * white, white paper #121212 and red markup stays red. Closed form c' = c + 255 - (max + min) (exact in HSL).
 * Integer maths, the same numbers as the desktop apps and the web: DebugDarkReceiver checks them on the device against
 * tests/web/dark-vectors.json (the Nim function's output).
 *
 * Kotlin rather than a JNI call into the Nim function: it is ten lines of integer maths, applied to millions of pixels
 * per overview level; one JNI call per pixel would cost more than the maths, and a buffer-wide JNI call would copy the
 * pixels across twice. The vectors keep the two copies equal.
 */
object DarkColor {
    const val LO = 18          // #121212: what white paper becomes (the dark background)
    const val HI = 237         // what black lines become
    private const val SPAN = HI - LO

    /** the dark-mode colour of an 8-bit RGB colour, as an opaque ARGB int */
    fun rgb(r: Int, g: Int, b: Int): Int {
        val k = 255 - maxOf(r, g, b) - minOf(r, g, b)
        return (0xFF shl 24) or ((LO + ((r + k) * SPAN + 127) / 255) shl 16) or
            ((LO + ((g + k) * SPAN + 127) / 255) shl 8) or (LO + ((b + k) * SPAN + 127) / 255)
    }

    /** the same for an ARGB colour; alpha untouched */
    fun argb(c: Int): Int = (c and 0xFF000000.toInt()) or (rgb((c shr 16) and 255, (c shr 8) and 255, c and 255) and 0xFFFFFF)

    /** in place over packed RGBA bytes (libjxl's output: straight alpha, alpha untouched) */
    fun rgbaBytes(px: ByteArray) {
        var i = 0
        val n = px.size
        while (i + 2 < n) {
            val r = px[i].toInt() and 255; val g = px[i + 1].toInt() and 255; val b = px[i + 2].toInt() and 255
            val k = 255 - maxOf(r, g, b) - minOf(r, g, b)
            px[i] = (LO + ((r + k) * SPAN + 127) / 255).toByte()
            px[i + 1] = (LO + ((g + k) * SPAN + 127) / 255).toByte()
            px[i + 2] = (LO + ((b + k) * SPAN + 127) / 255).toByte()
            i += 4
        }
    }

    /** in place over a Bitmap's pixels (getPixels: ARGB ints) */
    fun argbInts(px: IntArray) { for (i in px.indices) px[i] = argb(px[i]) }

    /** a marker colour (tag outlines, selection) raised toward white so it stays readable on the dark sheet
     *  (darkcolor.lightenForDark, amount 0.35, rounded to 8 bits) */
    fun lighten(c: Int, amount: Float = 0.35f): Int {
        fun ch(v: Int) = Math.round(v + (255 - v) * amount)
        return (c and 0xFF000000.toInt()) or (ch((c shr 16) and 255) shl 16) or (ch((c shr 8) and 255) shl 8) or ch(c and 255)
    }

    /** WCAG contrast ratio of two opaque colours */
    fun contrast(a: Int, b: Int): Double {
        fun lin(v: Int): Double { val c = v / 255.0; return if (c <= 0.03928) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4) }
        fun lum(c: Int) = 0.2126 * lin((c shr 16) and 255) + 0.7152 * lin((c shr 8) and 255) + 0.0722 * lin(c and 255)
        val la = lum(a); val lb = lum(b)
        return (maxOf(la, lb) + 0.05) / (minOf(la, lb) + 0.05)
    }
}
