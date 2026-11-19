package kks.explorer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import kks.explorer.sync.PhotoQueue
import kks.explorer.ui.orientedBitmap

/** Debug builds only: queue a made-up photo without a camera (e2e test_photo_queue): kks, caption, floor extras;
 *  `--ez hold true` makes the queue's jobs wait (until false or the process ends), so a test sees them queued;
 *  `--ei fail_encodes N` makes the next N encodes fail as if out of memory (the photo must be kept and retried);
 *  `--ei side N` makes the picture N × 3N/4 px, written as a PNG and read back through the camera's own path
 *  (`orientedBitmap`: at most 2560 px, Lanczos), its left half 1-px black and white stripes (bilinear scaling turns
 *  them into bands; Lanczos into an even grey: test_photo_size).
 *  `adb shell am broadcast -a kks.explorer.DEBUG_PHOTO -p io.github.walkdown --es kks 11LAB70AA500 --es floor 2` */
class DebugPhotoReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.hasExtra("hold")) { PhotoQueue.holdForTest = intent.getBooleanExtra("hold", false); return }
        if (intent.hasExtra("fail_encodes")) { PhotoQueue.failEncodesForTest = intent.getIntExtra("fail_encodes", 0); return }
        val kks = intent.getStringExtra("kks") ?: return
        val side = intent.getIntExtra("side", 0)
        if (side > 0) {
            // made and scaled off the main thread (a 12 MP PNG and its Lanczos pass take a while on an emulator)
            val done = goAsync()
            kotlin.concurrent.thread { try { bigPhoto(ctx, intent, kks, side) } finally { done.finish() } }
            return
        }
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

    private fun bigPhoto(ctx: Context, intent: Intent, kks: String, side: Int) {
        val big = Bitmap.createBitmap(side, side * 3 / 4, Bitmap.Config.ARGB_8888)
        big.eraseColor(Color.rgb(90, 140, 200))
        val stripe = IntArray(side / 2) { if (it % 2 == 0) Color.BLACK else Color.WHITE }
        for (y in 0 until big.height) big.setPixels(stripe, 0, stripe.size, 0, y, stripe.size, 1)
        val png = java.io.ByteArrayOutputStream().also { big.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
        big.recycle()
        val bmp = orientedBitmap(png) ?: return
        PhotoQueue.add(ctx, bmp, kks, intent.getStringExtra("caption") ?: "", "", intent.getStringExtra("floor") ?: "")
    }
}
