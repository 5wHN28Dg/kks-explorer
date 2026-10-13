package kks.explorer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import kks.explorer.sync.Sync
import kks.explorer.ui.Root

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent { Root() }
    }

    /** The app follows the system's light or dark theme without restarting (uiMode is in the manifest's
     *  configChanges), so the system bars are set again here: they kept the icons of the theme the app was started in,
     *  white on white or dark on dark after the phone switched (2026-10-13). */
    override fun onConfigurationChanged(newConfig: android.content.res.Configuration) {
        super.onConfigurationChanged(newConfig)
        enableEdgeToEdge()
    }

    override fun onStart() {
        super.onStart()
        App.visible = true
        Sync.foreground(applicationContext, true)
    }

    override fun onStop() {
        App.visible = false
        Sync.foreground(applicationContext, false)
        super.onStop()
    }
}
