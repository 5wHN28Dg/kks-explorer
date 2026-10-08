package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kks.explorer.sync.PhotoQueue

/** Debug builds only: queue a made-up photo without a camera (e2e test_photo_queue): kks, caption, floor extras.
 *  `adb shell am broadcast -a kks.explorer.DEBUG_PHOTO -p io.github.walkdown --es kks 11LAB70AA501 --es floor 2` */
class DebugPhotoReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val kks = intent.getStringExtra("kks") ?: return
        val bmp = Bitmap.createBitmap(1600, 1200, Bitmap.Config.ARGB_8888)
        val c = Canvas(bmp)
        c.drawColor(Color.rgb((kks.hashCode() and 0xff), 120, 180))
        val p = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textSize = 120f }
        c.drawText(kks, 80f, 600f, p)
        // a little noise, so the encoder has real work (a flat picture encodes in no time)
        val r = java.util.Random(kks.hashCode().toLong())
        for (i in 0 until 4000) { p.color = r.nextInt() or 0xff000000.toInt(); c.drawCircle(r.nextFloat() * 1600, r.nextFloat() * 1200, 6f, p) }
        PhotoQueue.add(ctx, bmp, kks, intent.getStringExtra("caption") ?: "", "", intent.getStringExtra("floor") ?: "")
    }
}
