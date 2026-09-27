package kks.explorer

import android.view.ViewGroup
import android.webkit.WebView
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView

// ---------- look: the same dark chrome and orange accent as the web viewer ----------
private val scheme = darkColorScheme(
    primary = Color(0xFFFF7A1A), onPrimary = Color(0xFF1C2730), secondary = Color(0xFF4F9CFF),
    background = Color(0xFF1C2730), onBackground = Color(0xFFE9EEF2), surface = Color(0xFF1C2730), onSurface = Color(0xFFE9EEF2),
    surfaceVariant = Color(0xFF2F4352), onSurfaceVariant = Color(0xFF94A6B4), surfaceContainer = Color(0xFF243440),
    surfaceContainerHigh = Color(0xFF2F4352), secondaryContainer = Color(0xFF3A5061), onSecondaryContainer = Color(0xFFE9EEF2),
    error = Color(0xFFFF5A5A), outline = Color(0xFF3A5061))

/** Material icons (Apache 2.0) as paths, so the app doesn't need the 30 MB extended icon library for five icons. */
private fun icon(d: String) = ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
    .addPath(PathParser().parsePathString(d).toNodes(), fill = SolidColor(Color.Black)).build()

private val PID = icon("M22 11V3h-7v3H9V3H2v8h7V8h2v10h4v3h7v-8h-7v3h-2V8h2v3z")   // account_tree
private val SCHOOL = icon("M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3L1 9l11 6 9-4.91V17h2V9L12 3z")
private val PERSON = icon("M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z")
private val BACK = icon("M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z")
private val NEXT = icon("M10 6L8.59 7.41 13.17 12l-4.58 4.59L10 18l6-6z")

private val SECTIONS = mapOf("queue" to "Approvals", "mine" to "My submissions", "users" to "People", "history" to "History",
                             "devices" to "Devices & bundles", "account" to "Your details")

@Composable
fun Shell(a: MainActivity) {
    val s = a.state
    BackHandler {
        when {
            s.manage != null -> s.manage = null
            s.joined && s.tab != 0 -> s.tab = 0
            // the page first: a setup form goes back to the choices, an open panel or drawer closes; else leave
            else -> a.pidWeb.evaluateJavascript("(typeof K!=='undefined'&&K.back)?K.back():false") { r -> if (r != "true") a.finish() }
        }
    }
    MaterialTheme(colorScheme = scheme) {
        when {
            !s.joined -> Web(a.pidWeb, Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).imePadding())
            s.manage != null -> Manage(a)
            else -> NavigationSuiteScaffold(navigationSuiteItems = {
                item(selected = s.tab == 0, onClick = { s.tab = 0 }, icon = { Icon(PID, null) }, label = { Text("P&ID") })
                item(selected = s.tab == 1, onClick = { s.tab = 1 }, icon = { Icon(SCHOOL, null) }, label = { Text("Learning") })
                item(selected = s.tab == 2, onClick = { s.tab = 2; a.refresh() }, label = { Text("Account") }, icon = {
                    BadgedBox(badge = { if (s.queue > 0) Badge { Text("${s.queue}") } }) { Icon(PERSON, null) }
                })
            }) {
                val inset = Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal))
                when (s.tab) {
                    0 -> Web(a.pidWeb, inset.imePadding())
                    1 -> Learning(inset)
                    else -> Account(a, inset)
                }
            }
        }
    }
}

/** The one WebView instance, moved into whichever place shows it (so the viewer keeps its position). */
@Composable
private fun Web(web: WebView, modifier: Modifier) {
    AndroidView(factory = {
        (web.parent as? ViewGroup)?.removeView(web)
        // fill the slot: AndroidView defaults to wrap_content, and a WebView sized to its content whose page sizes
        // itself to the WebView collapses to 0 px (the sheet then never gets drawn)
        web.layoutParams = ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        web
    }, modifier = modifier)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Manage(a: MainActivity) {
    val s = a.state
    Scaffold(topBar = {
        TopAppBar(title = { Text(SECTIONS[s.manage] ?: "Manage") },
                  navigationIcon = { IconButton(onClick = { s.manage = null; a.refresh() }) { Icon(BACK, "Back") } })
    }) { pad -> Web(a.manageWeb, Modifier.fillMaxSize().padding(pad).imePadding()) }
}

@Composable
private fun Learning(modifier: Modifier) {
    Box(modifier.padding(24.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.widthIn(max = 480.dp)) {
            Icon(SCHOOL, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.height(16.dp))
            Text("Learning", style = MaterialTheme.typography.headlineSmall)
            Spacer(Modifier.height(8.dp))
            Text("The three courses (Power Plant Technology, Plant Foundations, HRSG) come here in the next update. " +
                 "Your progress will be private: only your own devices can read it.",
                 style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable () -> Unit) {
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}

private fun ago(at: Long?): String {
    if (at == null) return ""
    val s = System.currentTimeMillis() / 1000 - at
    return when { s < 60 -> "just now"; s < 3600 -> "${s / 60} min ago"; s < 86400 -> "${s / 3600} h ago"; else -> "${s / 86400} d ago" }
}

@Composable
private fun Account(a: MainActivity, modifier: Modifier) {
    val s = a.state
    var address by remember { mutableStateOf("") }
    val admin = s.role == "admin" || s.role == "manager"
    LazyColumn(modifier.padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        item { Spacer(Modifier.height(4.dp)) }
        item {
            Column {
                Text(s.fullName, style = MaterialTheme.typography.headlineSmall)
                Text("${s.username} · ${s.role}", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(s.plant, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            Section("Sync") {
                if (s.syncs.isEmpty()) Text("No syncs yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                for (x in s.syncs.take(5)) {
                    @Suppress("UNCHECKED_CAST") val r = x["result"] as Map<String, Any?>?
                    Text("${x["address"]} · ${ago(x["at"] as Long?)}", style = MaterialTheme.typography.bodyMedium)
                    Text(if (x["ok"] == true) "received ${r?.get("received")}, sent ${r?.get("sent")}" else "failed: ${x["error"]}",
                         style = MaterialTheme.typography.bodySmall,
                         color = if (x["ok"] == true) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error)
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { a.syncNow(null) }, enabled = !s.busy) { Text("Sync now") }
                    if (s.busy) CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                }
                OutlinedTextField(address, { address = it }, Modifier.fillMaxWidth(), singleLine = true,
                                  label = { Text("Or a device's address, e.g. 192.168.1.20") },
                                  keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
                TextButton(onClick = { a.syncNow(address.trim()) }, enabled = !s.busy && address.isNotBlank()) { Text("Sync with it") }
                s.message?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                Text(s.discovery + (s.syncPort?.let { " · this phone listens on port $it" } ?: ""),
                     style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item {
            Section("Manage") {
                val rows = buildList {
                    if (admin) add("queue")
                    add("mine")
                    if (admin) { add("users"); add("history") }
                    add("devices"); add("account")
                }
                rows.forEachIndexed { i, key ->
                    if (i > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                    ListItem(headlineContent = { Text(SECTIONS[key]!!) },
                             trailingContent = {
                                 Row(verticalAlignment = Alignment.CenterVertically) {
                                     if (key == "queue" && s.queue > 0) Badge { Text("${s.queue}") }
                                     Icon(NEXT, null)
                                 }
                             },
                             colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                             modifier = Modifier.fillMaxWidth().clickable { a.openManage(key) })
                }
            }
        }
        item {
            Section("This phone") {
                Text("Device ${s.device.take(12)}…", fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
                Text("Its key is protected by the Android Keystore. A lost phone: remove it from another of your devices " +
                     "(Devices & bundles) or ask an admin.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        item { Spacer(Modifier.height(16.dp)) }
    }
}
