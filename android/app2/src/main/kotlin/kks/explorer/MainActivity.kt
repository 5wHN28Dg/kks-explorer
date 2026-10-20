package kks.explorer

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import kks.explorer.sync.Sync
import kks.explorer.ui.AppLinks
import kks.explorer.ui.Root

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // a link that started Walkdown; not again when the activity is recreated, nor when the person reopens it
        // from Recents (its Intent is still the link's then)
        if (savedInstanceState == null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0) takeLink(intent)
        setContent { Root() }
    }

    /** a VIEW Intent sent to this activity itself while it is on top (LinkActivity queues links instead) */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        takeLink(intent)
    }

    /** a walkdown:// link (decision 0058): only its text is kept, for the main screen to ask the core what it opens */
    private fun takeLink(i: Intent?) {
        val data = i?.dataString ?: return
        if (i.action == Intent.ACTION_VIEW && data.length <= MAX_LINK) AppLinks.pending = data
    }

    /** The app follows the system's light or dark theme without restarting (uiMode is in the manifest's
     *  configChanges), so the system bars are set again here: they kept the icons of the theme the app was started in,
     *  white on white or dark on dark after the phone switched (2026-10-13). */
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        enableEdgeToEdge()
    }

    override fun onResume() {
        super.onResume()
        AppLinks.resumed = true
    }

    override fun onPause() {
        AppLinks.resumed = false
        super.onPause()
    }

    override fun onStart() {
        super.onStart()
        App.visible = true
        Sync.foreground(applicationContext, true)
    }

    override fun onStop() {
        App.visible = false
        Sync.foreground(applicationContext, false)
        kks.explorer.core.Core.saveState()      // the replayed state, for the next start
        super.onStop()
    }

    companion object {
        const val MAX_LINK = 128      // the core reads nothing longer (core/src/kks/applink.nim)
    }
}
