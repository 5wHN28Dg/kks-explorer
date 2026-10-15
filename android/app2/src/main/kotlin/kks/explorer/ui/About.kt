package kks.explorer.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.unit.dp
import kks.explorer.v2.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject

/*
 * About Walkdown (the user, 2026-10-15; the web's K.aboutView, the GNOME and Windows apps show the same): what the app
 * is, its version and the commit it was built from with a link to exactly that source (the AGPL's offer), the licence
 * and its notice, the third-party parts built into the app with their licences and notices (each licence's full text a
 * tap away: the BSD, MIT and OFL terms ask for that), and the course photos' credits. The content is data/about.json
 * (format "walkdown-about" 1, made by tools/about.py), packed into the APK as an asset; the version and commit are
 * the build's own (BuildConfig, from build.gradle.kts). Links open in the browser, https only.
 */

object About {
    val version: String get() = BuildConfig.VERSION_NAME
    val commit: String get() = BuildConfig.KKS_COMMIT          // "" when the build didn't know it
    val modified: Boolean get() = BuildConfig.KKS_MODIFIED     // the build had changes the commit doesn't hold

    /** about.json from the APK, or null (missing or not the format this screen knows) */
    fun load(ctx: Context): JSONObject? = runCatching {
        JSONObject(ctx.assets.open("data/about.json").use { it.readBytes() }.toString(Charsets.UTF_8))
    }.getOrNull()?.takeIf { it.optString("format") == "walkdown-about" && it.optInt("version") == 1 }

    /** "Version 0.10.3 (commit 0123456789ab, with local changes)": the same words as the Nim programs' --version */
    fun versionLine(): String = "Version $version " +
        if (commit.isEmpty()) "(commit unknown)" else "(commit ${commit.take(12)}${if (modified) ", with local changes" else ""})"

    /** what "Copy details" puts on the clipboard, for a problem report */
    fun details(): String = listOf("Walkdown $version",
        "Commit: " + commit.ifEmpty { "unknown" } + if (modified) " (with local changes)" else "",
        "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
        "Device: ${Build.MANUFACTURER} ${Build.MODEL}").joinToString("\n")
}

/** an https link with a host, or null: about.json's links are the only ones this screen opens, and nothing else */
fun httpsUri(url: String): Uri? =
    runCatching { Uri.parse(url) }.getOrNull()?.takeIf { it.scheme == "https" && !it.host.isNullOrEmpty() }

fun openLink(ctx: Context, url: String) {
    val u = httpsUri(url) ?: return
    try {
        ctx.startActivity(Intent(Intent.ACTION_VIEW, u).addCategory(Intent.CATEGORY_BROWSABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    } catch (e: ActivityNotFoundException) {
        Toast.makeText(ctx, "No browser on this phone to open $url", Toast.LENGTH_LONG).show()
    }
}

/** a licence or notice as paragraphs that fit the screen: the files wrap their lines at 80 columns for a terminal, and
 *  some draw rules of dashes or equals signs, which mean nothing once the lines flow */
fun paragraphs(text: String): List<String> = text.replace("\r\n", "\n").split(Regex("\n[ \t]*\n"))
    .map { p -> p.lines().map { it.trim() }.filter { it.isNotEmpty() && !rule.matches(it) }.joinToString(" ") }
    .filter { it.isNotEmpty() }

private val rule = Regex("[-=_*~]{3,}")

private fun JSONObject.strings(k: String): List<String> = optJSONArray(k)?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList()

/** a third-party part's version as shown: a commit is shortened, the system's copy says so */
private fun partVersion(c: JSONObject): String = when {
    c.optJSONObject("platforms")?.str("android") == "system" -> "the system's copy"
    Regex("[0-9a-f]{40}").matches(c.str("version")) -> "commit " + c.str("version").take(12)
    else -> c.str("version")
}

/** the parts built into the Android app (or taken from Android itself), in about.json's order */
fun androidParts(d: JSONObject): List<JSONObject> =
    d.optJSONArray("components").objects().filter { it.optJSONObject("platforms")?.str("android").orEmpty().isNotEmpty() }

/** every licence the app is under or carries a part under: Walkdown's own first */
fun androidLicences(d: JSONObject): List<String> {
    val own = d.optJSONObject("license")?.str("id").orEmpty()
    return (listOf(own) + androidParts(d).flatMap { it.strings("license_ids") }.distinct().sorted()).filter { it.isNotEmpty() }.distinct()
}

@Composable
private fun Heading(text: String, top: Int = 16) =
    Text(text, style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = top.dp, bottom = 4.dp).semantics { heading() })

/** a row that opens a link in the browser: its title, and the address underneath (so it can be read before going) */
@Composable
private fun LinkRow(title: String, url: String) {
    val ctx = LocalContext.current
    val ok = httpsUri(url) != null
    ListItem(headlineContent = { Text(title) },
        supportingContent = { Text(url, color = if (ok) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant) },
        modifier = Modifier.fillMaxWidth().then(if (ok) Modifier.clickable(onClickLabel = "Open in the browser", role = Role.Button) { openLink(ctx, url) } else Modifier))
}

/** a row that opens a page of this screen (a part's notice, a licence's text) */
@Composable
private fun PageRow(title: String, sub: String, action: String, onOpen: () -> Unit) =
    ListItem(headlineContent = { Text(title) }, supportingContent = if (sub.isNotEmpty()) ({ Text(sub) }) else null,
        modifier = Modifier.fillMaxWidth().clickable(onClickLabel = action, role = Role.Button, onClick = onOpen))

private fun LazyListScope.longText(key: String, text: String) {
    items(paragraphs(text).withIndex().toList(), key = { "$key:${it.index}" }) { (_, p) ->
        Text(p, style = MaterialTheme.typography.bodyMedium, modifier = Modifier.padding(vertical = 4.dp))
    }
}

/** the About screen: Manage → About Walkdown, and the first screen's "About Walkdown" before the phone joins a plant */
@Composable
fun AboutScreen() {
    val ctx = LocalContext.current
    var loaded by remember { mutableStateOf(false) }
    var d by remember { mutableStateOf<JSONObject?>(null) }
    LaunchedEffect(Unit) { d = withContext(Dispatchers.IO) { About.load(ctx.applicationContext) }; loaded = true }
    // a page over the main one: ("part", component id) or ("licence", licence id)
    var page by remember { mutableStateOf<Pair<String, String>?>(null) }
    BackHandler(enabled = page != null) { page = null }
    val about = d
    if (about == null) {
        Column(Modifier.padding(vertical = 12.dp)) {
            Text("Walkdown", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            Text(About.versionLine())
            if (loaded) Dim("This app's About content is missing.")
        }
        return
    }
    when (page?.first) {
        "part" -> PartPage(about, page!!.second) { page = null }
        "licence" -> LicencePage(about, page!!.second) { page = null }
        else -> AboutMain(about) { page = it }
    }
}

@Composable
private fun AboutMain(d: JSONObject, open: (Pair<String, String>) -> Unit) {
    val ctx = LocalContext.current
    val clip = LocalClipboardManager.current
    val lic = d.optJSONObject("license") ?: JSONObject()
    val links = d.optJSONObject("links") ?: JSONObject()
    val source = d.optJSONObject("source") ?: JSONObject()
    val licences = d.optJSONObject("licenses") ?: JSONObject()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(vertical = 12.dp)) {
                Text("About ${d.str("name")}", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
                Text(d.str("summary"), style = MaterialTheme.typography.bodyLarge)
                SelectionContainer { Text(About.versionLine()) }
                Text("By ${d.str("developer")}")
                OutlinedButton(onClick = {
                    clip.setText(AnnotatedString(About.details()))
                    // (Android 13 and later say it themselves)
                    if (Build.VERSION.SDK_INT < 33) Toast.makeText(ctx, "Copied", Toast.LENGTH_SHORT).show()
                }) { Text("Copy details") }
            }
        }
        item {
            LinkRow("Licence: " + lic.str("name"), lic.str("url"))
            if (licences.optJSONObject(lic.str("id"))?.str("text").orEmpty().isNotEmpty())
                PageRow("Full text of the licence", "", "Show the licence") { open("licence" to lic.str("id")) }
            Dim(d.str("notice"))
        }
        item {
            Heading("Source of this version")
            val commit = About.commit
            when {
                commit.isEmpty() -> {
                    Dim("This build doesn't know the commit it was made from.")
                    LinkRow("Source code", source.str("repository"))
                }
                else -> {
                    if (About.modified) Dim("This build has local changes that are not published: the link is the commit it started from.")
                    LinkRow(if (About.modified) "Source of the commit this build started from" else "Source of this version",
                        source.str("commit_url").replace("{commit}", commit))
                }
            }
        }
        item {
            Heading("Links")
            LinkRow("Home page", links.str("homepage"))
            LinkRow("Report a problem", links.str("issues"))
            LinkRow("Help", links.str("help"))
        }
        item {
            Heading("Third-party software")
            Dim(d.optJSONObject("platforms")?.optJSONObject("android")?.str("note").orEmpty() +
                " Tap one for its copyright notice and licence.")
        }
        items(androidParts(d), key = { "part:" + it.str("id") }) { c ->
            PageRow(c.str("name") + partVersion(c).let { if (it.isEmpty()) "" else " · $it" },
                c.str("license_name") + c.str("use").let { if (it.isEmpty()) "" else "\n$it" }, "Show its licence") {
                open("part" to c.str("id"))
            }
        }
        item { Heading("Licences") }
        items(androidLicences(d), key = { "licence:$it" }) { id ->
            val l = licences.optJSONObject(id) ?: JSONObject()
            if (l.str("text").isNotEmpty()) PageRow(l.str("name").ifEmpty { id }, "", "Show the licence") { open("licence" to id) }
            else if (l.str("url").isNotEmpty()) LinkRow(l.str("name").ifEmpty { id }, l.str("url"))
            else ListItem(headlineContent = { Text(l.str("name").ifEmpty { id }) },
                supportingContent = { Text("Its terms are in the notices of the parts under it.") })
        }
        item { Heading("Course photos") }
        items(d.optJSONArray("photos").objects(), key = { "photo:" + it.str("file") }) { p ->
            Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Text(p.str("text"))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (l in p.optJSONArray("links").objects()) if (httpsUri(l.str("url")) != null)
                        TextButton(onClick = { openLink(ctx, l.str("url")) }, contentPadding = PaddingValues(horizontal = 8.dp)) {
                            Text(l.str("text"))
                        }
                }
            }
        }
    }
}

@Composable
private fun BackRow(onBack: () -> Unit) = TextButton(onClick = onBack) { Text("‹ About Walkdown") }

/** one third-party part: what it is, its notice (copyright and terms), and the full text of each licence it names */
@Composable
private fun PartPage(d: JSONObject, id: String, onBack: () -> Unit) {
    val c = d.optJSONArray("components").objects().firstOrNull { it.str("id") == id }
        ?: run { LaunchedEffect(id) { onBack() }; return }     // (not during composition)
    val licences = d.optJSONObject("licenses") ?: JSONObject()
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            BackRow(onBack)
            Text(c.str("name"), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            partVersion(c).let { if (it.isNotEmpty()) Text(if (it.startsWith("the ") || it.startsWith("commit")) it.replaceFirstChar(Char::uppercase) else "Version $it") }
            if (c.str("use").isNotEmpty()) Dim(c.str("use"))
            Text("Licence: " + c.str("license_name"))
            LinkRow("Project page", c.str("url"))
        }
        if (c.str("notice").isNotEmpty()) {
            item { Heading("Copyright and licence notice") }
            longText("notice", c.str("notice"))
        }
        for (lid in c.strings("license_ids")) {
            val l = licences.optJSONObject(lid) ?: continue
            item(key = "head:$lid") { Heading(l.str("name").ifEmpty { lid }) }
            if (l.str("text").isNotEmpty()) longText(lid, l.str("text"))
            else item(key = "link:$lid") {
                if (c.str("notice").isEmpty()) LinkRow("The licence", l.str("url"))
                else Dim("Its terms are in the notice above.")
            }
        }
    }
}

/** one licence's full text */
@Composable
private fun LicencePage(d: JSONObject, id: String, onBack: () -> Unit) {
    val l = d.optJSONObject("licenses")?.optJSONObject(id) ?: run { LaunchedEffect(id) { onBack() }; return }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            BackRow(onBack)
            Text(l.str("name").ifEmpty { id }, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() })
            if (l.str("url").isNotEmpty()) LinkRow("This licence on the web", l.str("url"))
        }
        longText(id, l.str("text"))
    }
}
