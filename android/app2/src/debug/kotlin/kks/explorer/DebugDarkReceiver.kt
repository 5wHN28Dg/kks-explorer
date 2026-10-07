package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kks.explorer.ui.DarkColor
import kks.explorer.ui.PAPER_DARK
import kks.explorer.ui.markerColor
import org.json.JSONObject

/** Debug builds only: the dark drawings colour check on the device, no test library needed.
 *  `run-as io.github.walkdown sh -c 'cat > files/dark-vectors.json'` < tests/web/dark-vectors.json, then
 *  `adb shell am broadcast -a kks.explorer.DEBUG_DARK -p io.github.walkdown`: files/dark-check.txt says "ok N" or
 *  lists the failures. Checks DarkColor against the Nim function's output (all three forms), and that every tag and
 *  coverage colour reaches 3:1 against the dark paper (WCAG non-text contrast). */
class DebugDarkReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val bad = ArrayList<String>()
        var n = 0
        val v = JSONObject(ctx.filesDir.resolve("dark-vectors.json").readText())
        if (v.getInt("lo") != DarkColor.LO || v.getInt("hi") != DarkColor.HI) bad.add("lo/hi ${v.getInt("lo")}/${v.getInt("hi")}")
        val rows = v.getJSONArray("rgb")
        val px = ByteArray(rows.length() * 4)
        val ints = IntArray(rows.length())
        for (i in 0 until rows.length()) {
            val a = rows.getJSONArray(i)
            val (r, g, b) = Triple(a.getInt(0), a.getInt(1), a.getInt(2))
            val want = (0xFF shl 24) or (a.getInt(3) shl 16) or (a.getInt(4) shl 8) or a.getInt(5)
            val got = DarkColor.rgb(r, g, b)
            if (got != want) bad.add("rgb($r,$g,$b) = ${Integer.toHexString(got)}, want ${Integer.toHexString(want)}")
            px[i * 4] = r.toByte(); px[i * 4 + 1] = g.toByte(); px[i * 4 + 2] = b.toByte(); px[i * 4 + 3] = (i % 256).toByte()
            ints[i] = ((i % 256) shl 24) or (r shl 16) or (g shl 8) or b
            n++
        }
        DarkColor.rgbaBytes(px)
        DarkColor.argbInts(ints)
        for (i in 0 until rows.length()) {
            val a = rows.getJSONArray(i)
            val got = listOf(px[i * 4].toInt() and 255, px[i * 4 + 1].toInt() and 255, px[i * 4 + 2].toInt() and 255)
            if (got != listOf(a.getInt(3), a.getInt(4), a.getInt(5)) || (px[i * 4 + 3].toInt() and 255) != i % 256) bad.add("rgbaBytes row $i: $got")
            val want = ((i % 256) shl 24) or (a.getInt(3) shl 16) or (a.getInt(4) shl 8) or a.getInt(5)
            if (ints[i] != want) bad.add("argbInts row $i")
        }
        if (PAPER_DARK != (0xFF121212).toInt()) bad.add("paper ${Integer.toHexString(PAPER_DARK)}")
        for (st in listOf("auto", "verified", "review", "pending")) {
            val c = DarkColor.contrast(markerColor(st, "", false, true), PAPER_DARK)
            if (c < 3.0) bad.add("tag $st: contrast $c")
            n++
        }
        for (ph in listOf("both", "equipment", "plate", "none")) {
            val c = DarkColor.contrast(markerColor("auto", ph, true, true), PAPER_DARK)
            if (c < 3.0) bad.add("coverage $ph: contrast $c")
            n++
        }
        if (markerColor("auto", "", false, false) != android.graphics.Color.rgb(26, 102, 230)) bad.add("light mode changed")
        val out = if (bad.isEmpty()) "ok $n" else bad.joinToString("\n")
        ctx.filesDir.resolve("dark-check.txt").writeText(out)
        android.util.Log.i("KKSDark", out)
    }
}
