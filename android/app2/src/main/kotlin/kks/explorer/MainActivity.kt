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
