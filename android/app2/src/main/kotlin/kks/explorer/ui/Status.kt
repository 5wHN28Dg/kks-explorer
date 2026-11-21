package kks.explorer.ui

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kks.explorer.v2.BuildConfig
import kks.explorer.core.Core
import kks.explorer.sync.Sync
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import androidx.lifecycle.repeatOnLifecycle

/** Switched changes waiting for the owner's check (the UI and UX policy's tier 2, its 8.5): off unless a release lists
 *  them in ON, a build for the check sets -PkksUx=name, or (debug builds) the DEBUG_UX broadcast turns them on. */
object Ux {
    val ON: List<String> = emptyList()
    fun on(ctx: Context, name: String): Boolean = name in ON || name in BuildConfig.KKS_UX.split(',') ||
        name in (ctx.getSharedPreferences("ux", Context.MODE_PRIVATE).getString("on", "") ?: "").split(',')
}

/** The offline state and the changes waiting to be sent (#372, PROTOCOL-v2 §15c): the same words as the desktop apps
 *  (apps/common/syncwords.nim; tests/test_sync_words.py keeps them equal). */
object SyncWords {
    const val OFFLINE_AFTER = 300L     // s without a successful sync with any device: offline
    @Volatile var offlineAfterForTest = 0L   // (debug builds' DEBUG_UX --el offline_after N: the e2e can't wait 5 minutes)
    const val OFFLINE = "Offline"
    const val ONLINE = "Online"
    const val LOOKING = "Looking for the plant's devices…"
    const val OFFLINE_HELP = "Changes are kept on this device and sent when it reaches another device of the plant."
    const val WAITING_SHOWN_AFTER = 15_000L   // ms a change waits while online before it is shown (and read out)
    fun waiting(n: Int): String = if (n <= 0) "" else if (n == 1) "1 change waiting to be sent" else "${"%,d".format(java.util.Locale.ENGLISH, n)} changes waiting to be sent"
    /** null before the first round has finished (still looking). Offline: the last finished round reached no device,
     *  and none synced with this one for 5 minutes (after a pause the state waits for a round that fails) */
    fun offline(nowMs: Long = System.currentTimeMillis()): Boolean? {
        if (Sync.lastRound == 0L) return null
        if (Sync.lastRoundReached) return false
        val last = Sync.peers.values.maxOfOrNull { it.lastOk } ?: 0L
        val after = if (offlineAfterForTest > 0) offlineAfterForTest else OFFLINE_AFTER
        return last == 0L || nowMs - last >= after * 1000
    }
    fun line(waiting: Int, offline: Boolean?): String {
        val w = waiting(waiting)
        val state = when { offline == null -> LOOKING; offline -> OFFLINE; else -> ONLINE }
        return if (w.isEmpty()) state else "$state · $w"
    }
}

/** One line under the top bar: online or offline, and how many changes wait to be sent; always there (nothing moves
 *  under the finger when it changes), read out when it changes. Offline in the text colour, online in the dimmer one. */
@Composable
fun SyncStateLine(modifier: Modifier = Modifier, indent: androidx.compose.ui.unit.Dp = 16.dp) {
    var waiting by remember { mutableIntStateOf(0) }
    var tick by remember { mutableIntStateOf(0) }
    var since by remember { mutableLongStateOf(0L) }
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(lifecycle) {
        // only while the screen is on view (no polling in the background)
        lifecycle.repeatOnLifecycle(androidx.lifecycle.Lifecycle.State.STARTED) {
            while (true) {
                waiting = withContext(Dispatchers.IO) {
                    try { Core.api("GET", "/native/waiting").json.optInt("waiting", 0) } catch (e: Exception) { 0 }
                }
                tick++
                delay(2000)
            }
        }
    }
    val offline = remember(tick) { SyncWords.offline() }
    // online, a change is shown once it has waited 15 s (each edit is sent within seconds: neither shown nor read out)
    val now = System.currentTimeMillis()
    if (waiting <= 0) since = 0L else if (since == 0L) since = now
    val shown = if (offline == true || (waiting > 0 && now - since >= SyncWords.WAITING_SHOWN_AFTER)) waiting else 0
    val text = SyncWords.line(shown, offline)   // (not "Syncing…": the line is read out when it changes)
    // two lines kept at a large font size: the count coming or going never moves the drawing under the finger
    val big = androidx.compose.ui.platform.LocalDensity.current.fontScale >= 1.3f
    Row(modifier.fillMaxWidth().padding(horizontal = indent, vertical = 4.dp).semantics { liveRegion = LiveRegionMode.Polite }) {
        Text(text, minLines = if (big) 2 else 1, style = MaterialTheme.typography.bodyMedium,
            color = if (offline == true) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
