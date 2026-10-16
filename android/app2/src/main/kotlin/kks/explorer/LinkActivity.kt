package kks.explorer

import android.app.Activity
import android.content.Intent
import android.os.Bundle

/** Links from other apps (walkdown://…, decision 0057): the only activity with the scheme's intent filter. It has no
 *  window: it hands the link to Walkdown's own task and finishes. A VIEW Intent from another app (Walkdown Plant's
 *  `OS.shell_open` sets no NEW_TASK) would otherwise start a second MainActivity in the caller's task; and
 *  `singleTask` on MainActivity would clear the camera above it whenever the launcher icon brings Walkdown back.
 *  Only the link's text goes on, as the data of a VIEW Intent: no extras, no flags of the caller's. What the link
 *  opens is read by the core (MainActivity → AppLinks). */
class LinkActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val data = intent?.dataString
        if (savedInstanceState == null && intent?.action == Intent.ACTION_VIEW && data != null && data.length <= MainActivity.MAX_LINK) {
            startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(data), this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        }
        finish()
    }
}
