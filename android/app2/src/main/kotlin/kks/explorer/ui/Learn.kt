package kks.explorer.ui

import android.graphics.Bitmap
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.graphics.luminance
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.calculateCentroid
import androidx.compose.foundation.gestures.calculatePan
import androidx.compose.foundation.gestures.calculateZoom
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.input.pointer.positionChanged
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kks.explorer.Jxl
import kks.explorer.core.Core
import org.json.JSONArray
import org.json.JSONObject
import java.nio.ByteBuffer
import java.nio.ByteOrder

// The courses (docs/COURSES.md, decision 0036) in Compose: the Learning tab lists them; a course shows one page at a
// time with its contents in a bottom sheet. Text runs become AnnotatedStrings with LinkAnnotations; figures are the
// Nim core's evaluator and drawing rules, replayed from an op list on the platform canvas (kksa/figops.nim).

/** what a link does: another page, another course, equipment on the drawings, or a web page (handled by Compose) */
class Nav(val page: (String) -> Unit, val course: (String, String) -> Unit, val kks: (String) -> Unit)

private fun JSONArray.list(): List<Any> = (0 until length()).map { get(it) }

/** a run's text; `shown`: as it is laid out, its num runs with their no-break joins (for measuring) */
fun plain(r: JSONArray?, shown: Boolean = false): String {
    if (r == null) return ""
    val sb = StringBuilder()
    for (x in r.list()) when (x) {
        is String -> sb.append(x)
        is JSONObject -> sb.append(if (x.has("num")) x.getString("num").let { if (shown) unbroken(it) else it } else plain(
            x.optJSONArray("b") ?: x.optJSONArray("i") ?: x.optJSONArray("small") ?: x.optJSONArray("term") ?: x.optJSONArray("link"), shown))
    }
    return sb.toString()
}

const val WHOLE_RUN = 20
const val NBSP = '\u00A0'
const val WORD_JOINER = '\u2060'

/** A `num` run ("12.44 MPa.a": a number with its unit, docs/COURSES.md §3) is kept on one line; the same rule as
 *  apps/common/nobreak.nim (the user, 2026-10-13: "0.385" ended one line and "Ω per °C" began the next):
 *  - a run of up to WHOLE_RUN characters stays whole: every space becomes a no-break space;
 *  - a longer one is a formula or a phrase ("V at transmitter = supply − I × R"): only a number stays with the unit
 *    after it, and it may wrap at its other spaces;
 *  - never a break after a hyphen, a dash or a slash inside a run: a word joiner follows it.
 *  A run still wider than its line is broken where the line fills up, as any word too long for its line is; in a
 *  table its column is at least as wide as the run's widest unbreakable piece (TableView). */
fun unbroken(s: String): String {
    val cps = s.codePoints().toArray()
    val whole = cps.size <= WHOLE_RUN
    fun unitStart(c: Int) = Character.isLetter(c) || c == 0xB0 || c == '%'.code
    val sb = StringBuilder()
    for ((i, c) in cps.withIndex()) {
        val next = if (i + 1 < cps.size) cps[i + 1] else 0
        val prev = if (i > 0) cps[i - 1] else 0
        if (c == ' '.code) sb.append(if (whole || next == '%'.code || (prev in '0'.code..'9'.code && unitStart(next))) NBSP else ' ')
        else {
            if (c == 0x2014 && i > 0 && prev != ' '.code) sb.append(WORD_JOINER)     // (an em dash: before it too)
            sb.appendCodePoint(c)
            if ((c == '-'.code || c == 0x2010 || c == 0x2012 || c == 0x2013 || c == 0x2014 || c == '/'.code) && i + 1 < cps.size && next != ' '.code) sb.append(WORD_JOINER)
        }
    }
    return sb.toString()
}

/** The course colours with a meaning (docs/COURSES.md §9.3: accent for links, act / alarm / ok for states), light and
 *  dark. Until 2026-10-13 the light ones were used in both themes: dark red on dark grey for the very reading a
 *  scenario question hinges on. */
object CourseColors {
    private val light = mapOf("accent" to 0xFF1F5F8B, "act" to 0xFFB3261E, "alarm" to 0xFF9A6412, "ok" to 0xFF2E7A4E)
    private val dark = mapOf("accent" to 0xFF6DAFDC, "act" to 0xFFF0776B, "alarm" to 0xFFE4AE45, "ok" to 0xFF62C08A)
    var isDark by mutableStateOf(false)
    fun of(token: String): androidx.compose.ui.graphics.Color = androidx.compose.ui.graphics.Color((if (isDark) dark else light).getValue(token))
}

fun AnnotatedString.Builder.run(r: JSONArray, nav: Nav, gloss: Map<String, String>) {
    for (x in r.list()) {
        if (x is String) { append(x); continue }
        val o = x as JSONObject
        when {
            o.has("b") -> withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { run(o.getJSONArray("b"), nav, gloss) }
            o.has("i") -> withStyle(SpanStyle(fontStyle = FontStyle.Italic)) { run(o.getJSONArray("i"), nav, gloss) }
            o.has("small") -> withStyle(SpanStyle(fontSize = 0.85.em)) { run(o.getJSONArray("small"), nav, gloss) }
            o.has("num") -> withStyle(SpanStyle(fontFeatureSettings = "tnum")) { append(unbroken(o.getString("num"))) }   // even-width digits; a monospace face spread "691.5 kg/s" apart
            o.has("term") -> withStyle(SpanStyle(textDecoration = TextDecoration.Underline)) { run(o.getJSONArray("term"), nav, gloss) }
            o.has("link") -> {
                val to = o.getJSONObject("to")
                val link: LinkAnnotation = when {
                    to.has("url") -> LinkAnnotation.Url(to.getString("url"))
                    to.has("kks") -> LinkAnnotation.Clickable("kks") { nav.kks(to.getString("kks")) }
                    to.has("course") -> LinkAnnotation.Clickable("course") { nav.course(to.getString("course"), to.optString("page")) }
                    else -> LinkAnnotation.Clickable("page") { nav.page(to.getString("page")) }
                }
                withLink(link) { withStyle(SpanStyle(textDecoration = TextDecoration.Underline, color = CourseColors.of("accent"))) {
                    run(o.getJSONArray("link"), nav, gloss) } }
            }
        }
    }
}

@Composable
fun RunText(r: JSONArray, nav: Nav, gloss: Map<String, String> = emptyMap(), style: TextStyle = MaterialTheme.typography.bodyLarge,
            modifier: Modifier = Modifier) {
    val text = remember(r, nav, CourseColors.isDark) { buildAnnotatedString { run(r, nav, gloss) } }
    Text(text, style = style, modifier = modifier)
}

// ---------------------------------------------------------------- progress (§8): the v1 keys, JSON strings

class Progress(val course: String) {
    var solved by mutableStateOf(setOf<String>())
    var skip by mutableStateOf(setOf<String>())
    var last = ""
    var best = 0

    init {
        val d = call("GET", "/api/progress", query = mapOf("course" to course)).json.optJSONObject("data") ?: JSONObject()
        // members written as false were taken back (a module no longer skipped): the merge is a union (§17)
        fun obj(k: String): Set<String> = runCatching { JSONObject(d.optString(k, "{}")).let { o -> o.keys().asSequence().filter { o.optBoolean(it) }.toSet() } }.getOrDefault(emptySet())
        solved = obj("solved"); skip = obj("skip")
        last = runCatching { JSONArray("[" + d.optString("last", "\"\"") + "]").getString(0) }.getOrDefault("")
        best = d.optString("finalBest", "0").toIntOrNull() ?: 0
    }

    private fun save(k: String, v: String) {
        call("POST", "/api/progress", JSONObject().put("course", course).put("data", JSONObject().put(k, v)))
    }
    private fun objOf(s: Set<String>) = JSONObject().apply { s.sorted().forEach { put(it, true) } }.toString()
    fun solve(id: String) { if (id !in solved) { solved = solved + id; save("solved", objOf(solved)) } }
    fun saveSkip(s: Set<String>) {
        val o = JSONObject(objOf(s)).apply { (skip - s).forEach { put(it, false) } }
        skip = s; save("skip", o.toString())
    }
    fun saveLast(id: String) { if (id != last) { last = id; save("last", JSONObject.quote(id)) } }
    fun score(n: Int) { if (n > best) { best = n; save("finalBest", n.toString()) } }
}

fun moduleQs(m: JSONObject): List<JSONObject> = listOf(m.getJSONObject("warm")) + m.getJSONArray("practice").objects() +
    (m.optJSONObject("bridge")?.getJSONArray("questions").objects())

// ---------------------------------------------------------------- the list and a course

@Composable
fun Learning(ui: Ui, snack: SnackbarHostState) {
    var open by rememberSaveable { mutableStateOf("") }
    var openPage by rememberSaveable { mutableStateOf("") }
    var linkSeq by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(ui.courseSeq) {      // a walkdown://course/… link (Root.kt): that course, at that page
        val link = ui.courseLink ?: return@LaunchedEffect
        ui.courseLink = null
        if (link.first == open && link.second.isEmpty()) return@LaunchedEffect     // (that course, as it is)
        open = link.first
        openPage = link.second
        linkSeq++                       // (a new key every time, also after the process was restored)
    }
    if (open.isNotEmpty()) {
        BackHandler { open = "" }
        key(open, linkSeq) {     // (a link to the course already open moves it to the link's page)
            CourseScreen(open, openPage, onClose = { open = "" }, onCourse = { c, p -> openPage = p; open = c }, ui = ui)
        }
        return
    }
    val rev = Changes.rev
    val list = remember(rev) { call("GET", "/native/courses").json.optJSONArray("courses").objects() }
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), contentPadding = PaddingValues(vertical = 12.dp)) {
        item { Text("Learning", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { heading() }) }
        if (list.isEmpty()) item { Dim("No courses on this phone yet.") }
        items(list) { c ->
            val id = c.getString("id")
            val p = remember(rev, id) { Progress(id) }
            val qs = c.getJSONArray("questions").list().map { it as String }
            val n = qs.count { it in p.solved }
            Card(onClick = { openPage = ""; open = id }, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
                Column(Modifier.padding(16.dp)) {
                    Text(c.getString("title"), style = MaterialTheme.typography.titleMedium)
                    Dim(c.getString("short"))
                    Spacer(Modifier.height(8.dp))
                    LinearProgressIndicator(progress = { if (qs.isEmpty()) 0f else n / qs.size.toFloat() }, modifier = Modifier.fillMaxWidth())
                    Dim("$n of ${qs.size} questions solved")
                }
            }
        }
        item { Dim("Your progress is private: only you can read it, on your own devices that you paired. Not the manager, not the server.") }
        item { Pairing(rev) }
    }
}

/** "Your devices": pairing by code (PROTOCOL-v2 §17, decision 0062), so that progress follows the person */
@Composable
fun Pairing(rev: Int) {
    var again by remember { mutableIntStateOf(0) }
    var err by remember { mutableStateOf("") }
    val j = remember(rev, again) { runCatching { call("GET", "/api/pairing").json }.getOrNull() }
    Column(Modifier.fillMaxWidth().padding(top = 16.dp)) {
        Text("Your devices", style = MaterialTheme.typography.titleMedium, modifier = Modifier.semantics { heading() })
        val rows = j?.optJSONArray("devices").objects()
        when {
            j == null || !j.optBoolean("ready") -> Dim("To share your progress with your other devices, pair them here. This device is not ready to pair yet: it needs to sync first.")
            rows.isEmpty() -> Dim("No other device of yours can pair yet. Open Learning on it once it has synced.")
            else -> {
                Dim("Press Pair here and on the other device. After both have synced, each shows a code: confirm only when both show the same code. A device you don't recognise, or whose code differs, is not yours to pair.")
                rows.forEach { d ->
                    val label = d.optString("label").ifEmpty { "A device" }
                    val state = d.optString("state")
                    val code = d.optString("code")
                    val status = when (state) {
                        "paired" -> "Paired"
                        "compare" -> "Code $code: confirm only if the other device shows the same code"
                        "waiting" -> "Waiting for the other device: press Pair there too, and let both sync"
                        "asked" -> "That device asked to pair: press Pair here to compare codes"
                        else -> "Not paired"
                    }
                    fun act(body: JSONObject) {
                        err = call("POST", "/api/pairing", body.put("device", d.getString("device"))).error ?: ""
                        again++
                    }
                    Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                        Column(Modifier.padding(12.dp)) {
                            Text(label); Dim(status)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (state == "compare") Button(onClick = { act(JSONObject().put("action", "confirm").put("code", code)) },
                                    modifier = Modifier.semantics { contentDescription = "Codes match with $label" }) { Text("Codes match") }
                                if (state != "paired") OutlinedButton(onClick = { act(JSONObject().put("action", "start")) },
                                    modifier = Modifier.semantics { contentDescription = (if (state == "compare" || state == "waiting") "Start again with " else "Pair with ") + label }) {
                                    Text(if (state == "compare" || state == "waiting") "Start again" else "Pair")
                                }
                            }
                        }
                    }
                }
            }
        }
        if (err.isNotEmpty()) Dim(err)
        TextButton(onClick = { err = ""; again++ }) { Text("Check again") }
    }
}

class QState { var picked by mutableStateOf(listOf<Int>()); var chosen by mutableStateOf(listOf<Int>()); var checked by mutableStateOf(false) }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CourseScreen(id: String, startPage: String, onClose: () -> Unit, onCourse: (String, String) -> Unit, ui: Ui) {
    val doc = remember(id) { call("GET", "/native/course", query = mapOf("id" to id)).json.optJSONObject("course") }
    if (doc == null) { Dim("This course is not available."); return }
    val pages = remember(doc) { doc.getJSONArray("pages").objects() }
    val mods = remember(pages) { pages.filter { it.getString("kind") == "module" } }
    val gloss = remember(doc) { doc.getJSONArray("glossary").objects().associate { it.getString("term") to plain(it.getJSONArray("meaning")) } }
    val prog = remember(id) { Progress(id) }
    var pageId by rememberSaveable(id) { mutableStateOf(startPage.ifEmpty { prog.last.takeIf { l -> pages.any { it.getString("id") == l } } ?: pages[0].getString("id") }) }
    var contents by remember { mutableStateOf(false) }
    val page = pages.firstOrNull { it.getString("id") == pageId } ?: pages[0]
    LaunchedEffect(pageId) { prog.saveLast(pageId) }
    val nav = remember(id) { Nav(page = { pageId = it }, course = { c, p -> onCourse(c, p) }, kks = { k ->
        val hit = call("GET", "/native/search", query = mapOf("q" to k)).json.optJSONArray("results").objects().firstOrNull()
        if (hit != null) ui.show(hit.str("id"))
    }) }
    fun title(p: JSONObject) = if (p.getString("kind") == "module") p.getString("n") + " · " + p.getString("short") else plain(p.getJSONArray("title"))
    val done = mods.sumOf { m -> moduleQs(m).count { it.getString("id") in prog.solved } }
    val total = mods.sumOf { moduleQs(it).size }
    Column(Modifier.fillMaxSize()) {
        TopAppBar(title = { Column {
                Text(doc.getString("title"), style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text("$done of $total solved", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1) } },
            navigationIcon = { IconButton(onClick = onClose) { Icon(Glyphs.BACK, contentDescription = "Back") } },
            actions = { TextButton(onClick = { contents = true }) { Text("Contents") } })
        key(pageId) { PageView(doc, page, pages, mods, prog, gloss, nav, ::title) }
    }
    if (contents) ModalBottomSheet(onDismissRequest = { contents = false }) {
        LazyColumn(Modifier.fillMaxWidth().padding(bottom = 24.dp)) {
            items(pages) { p ->
                val pid = p.getString("id")
                val mark = if (p.getString("kind") == "module" && moduleQs(p).all { it.getString("id") in prog.solved }) "  ✓" else ""
                val skip = if (pid in prog.skip) "  · can skip" else ""
                ListItem(headlineContent = { Text(title(p) + mark + skip, fontWeight = if (pid == pageId) FontWeight.Bold else null) },
                    modifier = Modifier.fillMaxWidth().clickableRow { pageId = pid; contents = false })
            }
        }
    }
}

private fun Modifier.clickableRow(f: () -> Unit) = this.clickable(onClick = f)

// ---------------------------------------------------------------- one page

@Composable
fun PageView(doc: JSONObject, p: JSONObject, pages: List<JSONObject>, mods: List<JSONObject>, prog: Progress,
             gloss: Map<String, String>, nav: Nav, title: (JSONObject) -> String) {
    val qs = remember { mutableStateMapOf<String, QState>() }
    fun q(id: String) = qs.getOrPut(id) { QState() }
    val fullKey = rememberSaveable { mutableStateOf("") }
    val figs = remember { PageFigs(fullKey) }                  // this page's live figures, freed when it closes
    DisposableEffect(Unit) { onDispose { figs.runs.values.forEach { val fig = it.close(); if (fig >= 0) call("POST", "/native/fig-free", JSONObject().put("fig", fig)) } } }
    val kind = p.getString("kind")
    val recall = remember { if (kind == "module") mods.takeWhile { it !== p }.flatMap { m -> m.getJSONArray("practice").objects().filter { it.getString("type") != "order" } }.shuffled().take(2) else emptyList() }
    val items = remember {
        if (kind == "test" || kind == "placement") {
            val byId = mods.flatMap(::moduleQs).associateBy { it.getString("id") }
            var its = p.getJSONArray("items").objects().mapNotNull { it2 -> (it2.optJSONObject("q") ?: byId[it2.optString("ref")])?.let { it2.getString("module") to it } }
            if (kind == "test") { its = its.shuffled(); if (!p.isNull("draw")) its = its.take(p.getInt("draw")) }
            its
        } else emptyList()
    }
    val idx = pages.indexOf(p)
    val list = rememberLazyListState()
    val scrolling = remember(list) { derivedStateOf { list.isScrollInProgress } }
    CompositionLocalProvider(LocalScrolling provides scrolling) {
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), state = list, contentPadding = PaddingValues(vertical = 12.dp)) {
        fun blocks(bs: JSONArray, keyPrefix: String) {
            bs.objects().forEachIndexed { i, b -> item(key = "$keyPrefix/$i", contentType = blockType(b)) { Block(doc, b, nav, gloss, figs, "$keyPrefix/$i") } }
        }
        fun head(eyebrow: String, t: JSONArray) {
            item { Dim(eyebrow.uppercase()) }
            item { RunText(t, nav, gloss, MaterialTheme.typography.headlineSmall, Modifier.semantics { heading() }) }
        }
        fun section(t: String) = item { Text(t, style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(top = 18.dp, bottom = 4.dp).semantics { heading() }) }
        fun question(qq: JSONObject, label: String, suffix: String = "", once: Boolean = false, onAnswer: ((Boolean) -> Unit)? = null) =
            item(key = "q/" + qq.getString("id") + suffix, contentType = "question") { Question(qq, label, q(qq.getString("id") + suffix), prog, qq.getString("id") + suffix, once, onAnswer, nav, gloss) }
        when (kind) {
            "module" -> {
                head("Module " + p.getString("n"), p.getJSONArray("title"))
                if (p.getJSONArray("goals").length() > 0) item {
                    Card(Modifier.fillMaxWidth().padding(vertical = 6.dp)) { Column(Modifier.padding(12.dp)) {
                        Dim("AFTER THIS MODULE YOU CAN")
                        p.getJSONArray("goals").list().forEach { g -> RunText(JSONArray().put("• ").let { a -> (g as JSONArray).list().forEach { a.put(it) }; a }, nav, gloss) }
                    } }
                }
                if (recall.isNotEmpty()) { section("From earlier modules"); item { Dim("Two questions from what you have already covered. Answer from memory.") }
                    recall.forEach { question(it, "Recall", "_r") } }
                section("Guess first"); question(p.getJSONObject("warm"), "Before the lesson")
                section(if (p.getString("n") == "0") "About this course" else "The lesson")
                blocks(p.getJSONArray("body"), "body")
                if (!p.isNull("worked")) { section("Worked example"); item { Worked(p.getJSONObject("worked"), nav, gloss) } }
                if (p.getJSONArray("practice").length() > 0) { section("Practice"); item { Dim("Every wrong answer tells you why. Retry until each is right.") }
                    p.getJSONArray("practice").objects().forEach { question(it, "Practice") } }
                p.optJSONObject("bridge")?.let { b -> section(plain(b.getJSONArray("title")))
                    if (b.getJSONArray("intro").length() > 0) item { RunText(b.getJSONArray("intro"), nav, gloss) }
                    b.getJSONArray("questions").objects().forEach { question(it, "Bridge") } }
            }
            "placement" -> {
                head("Test", p.getJSONArray("title")); blocks(p.getJSONArray("intro"), "intro")
                items.forEachIndexed { i, (m, qq) -> question(qq, "Q${i + 1} · " + title(mods.first { it.getString("id") == m }), "_p", true) }
                section("Your plan")
                item {
                    val ans = items.mapNotNull { (m, qq) -> q(qq.getString("id") + "_p").picked.firstOrNull()?.let { m to qq.getJSONArray("options").getJSONObject(it).getBoolean("right") } }
                    if (ans.size < items.size) Dim("Answer all ${items.size} to see which modules to take.")
                    else {
                        val byMod = ans.groupBy({ it.first }, { it.second })
                        val skip = byMod.filter { e -> e.value.all { it } }.keys
                        LaunchedEffect(skip) { if (skip != prog.skip) prog.saveSkip(skip) }
                        Text("Take:", fontWeight = FontWeight.Bold)
                        mods.filter { it.getString("id") in byMod && it.getString("id") !in skip }.forEach { m -> TextButton(onClick = { nav.page(m.getString("id")) }) { Text(title(m)) } }
                        Text("Can skip: " + mods.filter { it.getString("id") in skip }.joinToString { title(it) }.ifEmpty { "none." })
                    }
                }
            }
            "test" -> {
                head("Test", p.getJSONArray("title")); blocks(p.getJSONArray("intro"), "intro")
                if (prog.best > 0) item { Dim("Your best so far: ${prog.best}") }
                items.forEachIndexed { i, (_, qq) -> question(qq, "Question ${i + 1} of ${items.size}", "_f", true) }
                section("Result")
                item {
                    val ans = items.mapNotNull { (m, qq) -> q(qq.getString("id") + "_f").picked.firstOrNull()?.let { m to qq.getJSONArray("options").getJSONObject(it).getBoolean("right") } }
                    val score = ans.count { it.second }
                    // (nothing answered yet: how many there are, as on GNOME; it said "0 / 0 right")
                    Text(if (ans.isEmpty()) "0 / ${items.size} answered" else "$score / ${ans.size} right" + if (ans.size == items.size) " · finished" else "", style = MaterialTheme.typography.titleMedium)
                    if (ans.size == items.size) {
                        LaunchedEffect(score) { prog.score(score) }
                        (if (score >= p.getInt("pass")) p.getJSONArray("on_pass") else p.getJSONArray("on_fail")).objects().forEach { b -> Block(doc, b, nav, gloss, figs, "result") }
                        val missed = ans.filter { !it.second }.map { it.first }.distinct()
                        if (missed.isNotEmpty()) { Text("Revisit:", fontWeight = FontWeight.Bold)
                            missed.forEach { m -> TextButton(onClick = { nav.page(m) }) { Text(title(mods.first { it.getString("id") == m })) } } }
                    }
                }
            }
            "vocab_drill" -> { head("Practice", p.getJSONArray("title")); blocks(p.getJSONArray("intro"), "intro"); item { Vocab(doc, mods, nav, title) } }
            "reading_drill" -> { head("Practice", p.getJSONArray("title")); blocks(p.getJSONArray("intro"), "intro"); item { Reading(p, nav, gloss) } }
            "glossary" -> {
                head("Reference", p.getJSONArray("title")); blocks(p.getJSONArray("intro"), "intro")
                for (m in mods) {
                    val rows = doc.getJSONArray("glossary").objects().filter { it.getString("module") == m.getString("id") }
                    if (rows.isNotEmpty()) { section(m.getString("n") + " · " + plain(m.getJSONArray("title")))
                        item { TableView(JSONObject().put("head", JSONArray().put(JSONArray().put("Term")).put(JSONArray().put("Meaning")))
                            .put("rows", JSONArray(rows.map { JSONArray().put(JSONArray().put(JSONObject().put("b", JSONArray().put(it.getString("term"))))).put(it.getJSONArray("meaning")) }))
                            .put("num", JSONArray()), nav, gloss) } }
                }
            }
            else -> { head(p.optString("eyebrow"), p.getJSONArray("title")); blocks(p.getJSONArray("intro"), "intro"); blocks(p.getJSONArray("body"), "page") }
        }
        item {
            // each button takes at most its share of the row and wraps its label there (two long titles left no gap
            // between the buttons, 2026-10-13); the arrow stays with the word next to it
            Row(Modifier.fillMaxWidth().padding(top = 24.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                if (idx > 0) OutlinedButton(onClick = { nav.page(pages[idx - 1].getString("id")) }, modifier = Modifier.weight(1f, fill = false).padding(end = 6.dp)) { Text("←\u00a0" + title(pages[idx - 1])) }
                else Spacer(Modifier)
                if (idx + 1 < pages.size) Button(onClick = { nav.page(pages[idx + 1].getString("id")) }, modifier = Modifier.weight(1f, fill = false).padding(start = 6.dp)) { Text(title(pages[idx + 1]) + "\u00a0→") }
            }
        }
    }
    // A figure enlarged over the whole screen. It is shown from here, not from its place in the list: turned on its
    // side the page shows other rows, the figure's own leaves the list, and the enlarged figure went with it.
    if (fullKey.value.isNotEmpty()) {
        val run = figs.runs[fullKey.value]
        if (run == null) SideEffect { fullKey.value = "" }     // (the app was restored: its figures are new)
        else FigureFull(doc, run) { fullKey.value = "" }
    }
    }
}

/** whether the course page is moving (figures show a still image meanwhile) */
val LocalScrolling = staticCompositionLocalOf<State<Boolean>> { mutableStateOf(false) }

// ---------------------------------------------------------------- blocks (§4)

private val BLOCK_TYPES = listOf("h", "p", "ul", "ol", "table", "callout", "cards", "chain", "figure", "image", "issues", "tool")
fun blockType(b: JSONObject): String = BLOCK_TYPES.firstOrNull { b.has(it) } ?: "other"

@Composable
fun Block(doc: JSONObject, b: JSONObject, nav: Nav, gloss: Map<String, String>, figs: PageFigs, key: String) {
    Box(Modifier.padding(vertical = 4.dp)) {
        when {
            b.has("h") -> Text(plain(b.getJSONArray("h")), style = if (b.getInt("level") == 2) MaterialTheme.typography.titleLarge else MaterialTheme.typography.titleMedium,
                modifier = Modifier.padding(top = 10.dp).semantics { heading() })
            b.has("p") -> RunText(b.getJSONArray("p"), nav, gloss)
            b.has("ul") || b.has("ol") -> Column {
                val items = (b.optJSONArray("ul") ?: b.getJSONArray("ol")).list()
                items.forEachIndexed { i, it -> Row { Text(if (b.has("ul")) "•  " else "${i + 1}.  "); RunText(it as JSONArray, nav, gloss) } }
            }
            b.has("table") -> TableView(b.getJSONObject("table"), nav, gloss)
            b.has("callout") -> Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
                Text(plain(b.getJSONArray("label")).uppercase(), style = MaterialTheme.typography.labelMedium,
                    color = if (b.getString("callout") == "flag") MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary)
                b.getJSONArray("body").objects().forEach { Block(doc, it, nav, gloss, figs, key) }
            } }
            b.has("cards") -> Column { b.getJSONArray("cards").list().forEach { c -> val cc = c as JSONArray
                Card(Modifier.fillMaxWidth().padding(vertical = 4.dp)) { Column(Modifier.padding(12.dp)) {
                    RunText(cc.getJSONArray(0), nav, gloss, MaterialTheme.typography.titleSmall); RunText(cc.getJSONArray(1), nav, gloss) } } } }
            b.has("chain") -> Text(b.getJSONArray("chain").list().joinToString("  →  ") { plain(it as JSONArray) }, fontWeight = FontWeight.Bold)
            b.has("figure") -> FigureView(doc, b.getString("figure"), figs, key)
            b.has("image") -> ImageView(b.getJSONObject("image"), nav, gloss)
            b.has("issues") -> Column { b.getJSONArray("issues").list().forEach { it2 -> val it = it2 as JSONArray
                val sev = it.getString(0)
                Text(buildAnnotatedString {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = when (sev) { "high" -> CourseColors.of("act"); "medium" -> CourseColors.of("alarm"); else -> CourseColors.of("ok") })) { append(sev.replaceFirstChar { c -> c.uppercase() } + " ") }
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { run(it.getJSONArray(1), nav, gloss); append(". ") }
                    run(it.getJSONArray(2), nav, gloss)
                }, modifier = Modifier.padding(vertical = 4.dp)) } }
            b.has("tool") -> KksTool(nav)
        }
    }
}

@Composable
fun TableView(t: JSONObject, nav: Nav, gloss: Map<String, String>) {
    val num = t.getJSONArray("num").list().map { (it as Number).toInt() }.toSet()
    val head = t.getJSONArray("head").list().map { it as JSONArray }
    val rows = t.getJSONArray("rows").list().map { r -> (r as JSONArray).list().map { it as JSONArray } }
    val headStyle = MaterialTheme.typography.labelLarge
    val body = MaterialTheme.typography.bodyMedium
    val numStyle = body.copy(fontFeatureSettings = "tnum", textAlign = TextAlign.Center)     // tabular figures, centered (the user's choice)
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val pad = 6.dp
    // each column as wide as its widest cell on one line (text columns at most 240 dp, then they wrap); a table
    // narrower than the screen gives the spare width to its text columns, a wider one scrolls sideways
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val avail = maxWidth - 16.dp
        val widths = remember(t, avail) {
            val natural = head.indices.map { i ->
                // (text cells are measured in bold: a cell may be bold, as every glossary term is, and bold is wider)
                val cells = listOf(head[i] to headStyle) + rows.mapNotNull { r -> r.getOrNull(i)?.let { it to (if (i in num) numStyle else body.copy(fontWeight = FontWeight.Bold)) } }
                val px = cells.maxOf { (c, st) -> measurer.measure(plain(c), st, softWrap = false, maxLines = 1).size.width }
                with(density) { px.toDp() } + pad * 2 + 1.dp
            }
            // a number column at its narrowest: its widest number, or its heading's longest word (the heading wraps)
            val narrow = head.indices.map { i ->
                if (i !in num) 0.dp else {
                    val cells = rows.mapNotNull { r -> r.getOrNull(i) }.maxOfOrNull { measurer.measure(plain(it), numStyle, softWrap = false, maxLines = 1).size.width } ?: 0
                    val word = plain(head[i]).split(' ').maxOf { measurer.measure(it, headStyle, softWrap = false, maxLines = 1).size.width }
                    with(density) { maxOf(cells, word).toDp() } + pad * 2 + 1.dp
                }
            }
            // a text column is never narrower than its longest word (a narrower one broke words in the middle:
            // "Photoelectri" / "c", found 2026-10-13)
            val word = head.indices.map { i ->
                if (i in num) 0.dp else {
                    // (measured in bold: a cell may hold bold words, and they are wider)
                    val cells = listOf(head[i] to headStyle) + rows.mapNotNull { r -> r.getOrNull(i)?.let { it to body.copy(fontWeight = FontWeight.Bold) } }
                    val px = cells.maxOf { (c, st) -> plain(c, shown = true).split(WORD_BREAK).maxOf { measurer.measure(it, st, softWrap = false, maxLines = 1).size.width } }
                    with(density) { px.toDp() } + pad * 2 + 1.dp
                }
            }
            tableWidths(natural, narrow, word, num, avail)
        }
        Column(Modifier.horizontalScroll(rememberScrollState()).background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(8.dp)).padding(8.dp)) {
            Row { head.forEachIndexed { i, h -> Box(Modifier.width(widths[i]).padding(horizontal = pad, vertical = 4.dp)) {
                RunText(h, nav, gloss, if (i in num) headStyle.copy(textAlign = TextAlign.Center) else headStyle, Modifier.fillMaxWidth()) } } }
            rows.forEach { r ->
                HorizontalDivider()
                Row { r.forEachIndexed { i, c -> if (i < widths.size) Box(Modifier.width(widths[i]).padding(horizontal = pad, vertical = 4.dp)) {
                    RunText(c, nav, gloss, if (i in num) numStyle else body, Modifier.fillMaxWidth()) } } }
            }
        }
    }
}

/** where a cell's text may wrap: at a space (not a no-break space), and after a hyphen or a slash that no digit
 *  and no word joiner follows ("CT-101" and "1/2" stay whole, and so does a num run's "kg/s": `unbroken`) */
private val WORD_BREAK = Regex(" |(?<=[-/])(?![\\d\u2060])")

/** The widths of a table's columns. `natural`: each column with its widest cell on one line; `narrow`: a number
 *  column at its narrowest (its widest number, or its heading's longest word); `word`: a text column's longest word.
 *  - A table that fits gives the spare width to its text columns.
 *  - One that doesn't: number columns go to their narrowest, and each text column keeps at least its longest word
 *    and 96 dp, or its natural width when that is less (a column of single letters stays that narrow, and its
 *    neighbours get the room); what is left over is shared in proportion to what each column still lacks.
 *  - When those least widths don't fit but the longest words alone do, the 96 dp is given up and the table fits.
 *  - When even the longest words don't fit, the table keeps the least widths of the second rule and scrolls sideways. */
fun tableWidths(natural: List<androidx.compose.ui.unit.Dp>, narrow: List<androidx.compose.ui.unit.Dp>, word: List<androidx.compose.ui.unit.Dp>,
                num: Set<Int>, avail: androidx.compose.ui.unit.Dp): List<androidx.compose.ui.unit.Dp> {
    fun sum(l: List<androidx.compose.ui.unit.Dp>) = l.fold(0.dp) { x, y -> x + y }
    var capped = natural.mapIndexed { i, w -> if (i in num) w else maxOf(minOf(w, 240.dp), minOf(w, word[i])) }
    val text = natural.indices.filter { it !in num }
    if (text.isEmpty()) return capped
    if (sum(capped) <= avail) { val extra = (avail - sum(capped)) / text.size; return capped.mapIndexed { i, w -> if (i in num) w else w + extra } }
    capped = capped.mapIndexed { i, w -> if (i in num) narrow[i] else w }
    if (sum(capped) <= avail) { val extra = (avail - sum(capped)) / text.size; return capped.mapIndexed { i, w -> if (i in num) w else w + extra } }
    var least = capped.mapIndexed { i, w -> if (i in num) w else minOf(w, maxOf(word[i], 96.dp)) }
    // 96 dp each is a wish, the longest word a must: when only the wish is in the way, the table still fits
    if (sum(least) > avail) least = capped.mapIndexed { i, w -> if (i in num) w else minOf(w, word[i]) }
    val spare = avail - sum(least)
    if (spare < 0.dp) return capped.mapIndexed { i, w -> if (i in num) w else minOf(w, maxOf(word[i], 96.dp)) }     // scrolls sideways, with readable columns
    val lack = capped.mapIndexed { i, w -> w - least[i] }
    val lacking = sum(lack)
    return least.mapIndexed { i, w -> if (lacking > 0.dp) w + spare * (lack[i] / lacking) else w }
}

/** decoded course pictures, kept while there is room (a page scrolled back must not decode again) */
private object CourseImages {
    private val cache = object : android.util.LruCache<String, Bitmap>(64 shl 20) { override fun sizeOf(k: String, v: Bitmap) = v.byteCount }
    private val aspects = java.util.concurrent.ConcurrentHashMap<String, Float>()
    fun get(file: String): Bitmap? = cache.get(file)
    fun aspect(file: String): Float? = aspects[file]
    fun load(ctx: android.content.Context, file: String): Bitmap? = cache.get(file) ?: run {
        val data = Core.file("courses/$file") ?: runCatching { ctx.assets.open("data/courses/$file").readBytes() }.getOrNull()
        data?.let { Jxl.bitmap(it) }?.also { it.prepareToDraw(); cache.put(file, it); aspects[file] = it.width / it.height.toFloat() }
    }
}

@Composable
fun ImageView(im: JSONObject, nav: Nav, gloss: Map<String, String>) {
    val ctx = LocalContext.current
    val file = im.getString("file")
    // decoded off the main thread (JPEG XL decoding takes a while on a phone); the space is kept meanwhile
    val bmp by produceState(CourseImages.get(file), file) { if (value == null) value = withContext(Dispatchers.IO) { CourseImages.load(ctx, file) } }
    var zoom by remember { mutableStateOf(false) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(file) { kotlinx.coroutines.delay(10_000); if (bmp == null) failed = true }
    Column {
        val b = bmp
        val aspect = b?.let { it.width / it.height.toFloat() } ?: CourseImages.aspect(file) ?: (4f / 3f)
        // the box the picture takes, computed here: full width, or 360 dp high and narrower for a tall picture.
        // (fillMaxWidth + heightIn + aspectRatio asked for a size outside the constraints; Compose then drew the
        // picture at its own size over the neighbours above and below, found on the Note 9 2026-10-02.)
        val box = Modifier.fillMaxWidth().wrapContentWidth(Alignment.CenterHorizontally).let { m ->
            m.then(Modifier.layout { measurable, c ->
                var bw = c.maxWidth.toFloat(); var bh = bw / aspect
                val cap = 360.dp.toPx()
                if (bh > cap) { bh = cap; bw = bh * aspect }
                val p = measurable.measure(androidx.compose.ui.unit.Constraints.fixed(bw.toInt(), bh.toInt()))
                layout(p.width, p.height) { p.place(0, 0) }
            })
        }
        if (b != null) {
            val img = remember(b) { b.asImageBitmap() }
            Image(img, contentDescription = im.getString("alt"), contentScale = ContentScale.Fit,
                modifier = box.clickable(onClickLabel = "Enlarge") { zoom = true })
            if (zoom) ZoomImage(img, im.getString("alt")) { zoom = false }
        } else if (failed) Dim("(picture not available: ${im.getString("alt")})")
        else Box(box.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(6.dp)))
        if (im.getJSONArray("caption").length() > 0) RunText(im.getJSONArray("caption"), nav, gloss, MaterialTheme.typography.bodySmall)
        if (im.getJSONArray("credit").length() > 0) RunText(im.getJSONArray("credit"), nav, gloss, MaterialTheme.typography.labelSmall)
    }
}

/** a picture full screen: pinch to zoom (1–8×), drag to pan, double-tap to zoom in or back out; Back or ✕ closes */
@Composable
fun ZoomImage(img: androidx.compose.ui.graphics.ImageBitmap, alt: String, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        FullScreenDialogWindow()
        var scale by remember { mutableFloatStateOf(1f) }
        var off by remember { mutableStateOf(Offset.Zero) }
        BoxWithConstraints(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.Black)) {
            val w = constraints.maxWidth.toFloat(); val h = constraints.maxHeight.toFloat()
            val c = Offset(w / 2, h / 2)
            fun clamp(o: Offset, s: Float) = Offset(o.x.coerceIn(-(s - 1) * w / 2, (s - 1) * w / 2), o.y.coerceIn(-(s - 1) * h / 2, (s - 1) * h / 2))
            // keep the point under the fingers where it is: off' = (p - c) - (p - c - off) · s'/s
            fun zoomAt(p: Offset, ns: Float) { val k = ns / scale; off = clamp((p - c) - (p - c - off) * k, ns); scale = ns }
            Image(img, contentDescription = alt, contentScale = ContentScale.Fit, modifier = Modifier.fillMaxSize()
                .pointerInput(Unit) { detectTapGestures(onDoubleTap = { p -> if (scale > 1.01f) { scale = 1f; off = Offset.Zero } else zoomAt(p, 3f) }) }
                .pointerInput(Unit) { detectTransformGestures { centroid, pan, z, _ ->
                    zoomAt(centroid, (scale * z).coerceIn(1f, 8f)); off = clamp(off + pan, scale) } }
                .graphicsLayer { scaleX = scale; scaleY = scale; translationX = off.x; translationY = off.y })
            IconButton(onClick = onClose, modifier = Modifier.align(Alignment.TopEnd).windowInsetsPadding(WindowInsets.safeDrawing).padding(8.dp)
                .background(androidx.compose.ui.graphics.Color(0x99000000), RoundedCornerShape(50))) {
                Icon(Glyphs.CLOSE, contentDescription = "Close", tint = androidx.compose.ui.graphics.Color.White)
            }
        }
    }
}

@Composable
fun Worked(w: JSONObject, nav: Nav, gloss: Map<String, String>) {
    var shown by remember { mutableIntStateOf(0) }
    val steps = w.getJSONArray("steps").list()
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
        RunText(w.getJSONArray("case"), nav, gloss, MaterialTheme.typography.titleSmall)
        for (k in 0 until shown) { val s = steps[k] as JSONArray
            Dim("Step ${k + 1} · " + plain(s.getJSONArray(0))); RunText(s.getJSONArray(1), nav, gloss) }
        if (shown < steps.size) OutlinedButton(onClick = { shown++ }) { Text("Predict the next step, then reveal it") } else Dim("All steps shown")
    } }
}

@Composable
fun KksTool(nav: Nav) {
    var code by remember { mutableStateOf("11 LAB 70 AA 501") }
    val tables = remember { call("GET", "/native/kks-tables").json }
    val raw = code.uppercase().replace(Regex("[\\s_.\\-]"), "")
    val m = Regex("^(\\d{2})([A-Z]{3})(\\d{2})([A-Z]{2})(\\d{3})([A-Z]?)$").matchEntire(raw)
    fun look(t: String, k: String) = tables.optJSONObject(t)?.optString(k)?.ifEmpty { null } ?: "not in the plant tables"
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp)) {
        OutlinedTextField(code, { code = it }, label = { Text("KKS code") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        if (m == null) Text("Can't read that code. Expected something like 11 LAB 70 AA 501.")
        else {
            val (u, s, sn, eq, en) = m.destructured
            Text("Unit $u: " + look("blocks", u)); Text("System $s: " + look("systems", s)); Text("System number $sn")
            Text("Equipment type $eq: " + look("components", eq)); Text("Equipment number $en")
            TextButton(onClick = { nav.kks(raw) }) { Text("Find $raw on the drawings") }
        }
    } }
}

// ---------------------------------------------------------------- questions (§5)

@Composable
fun Question(q: JSONObject, label: String, st: QState, prog: Progress, id: String, once: Boolean, onAnswer: ((Boolean) -> Unit)?, nav: Nav, gloss: Map<String, String>) {
    val type = q.getString("type")
    Card(Modifier.fillMaxWidth().padding(vertical = 6.dp).semantics(mergeDescendants = false) { contentDescription = plain(q.getJSONArray("q")) }) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            // (as written: in capitals a module's "4–20 mA" read "4–20 MA")
            Row { Text(label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(1f))
                if (q.getJSONArray("src").length() > 0) Dim(plain(q.getJSONArray("src"))) }
            if (type == "scenario") Column(Modifier.background(MaterialTheme.colorScheme.surfaceVariant, RoundedCornerShape(6.dp)).padding(8.dp).fillMaxWidth()) {
                q.getJSONArray("panel").objects().forEach { r -> Row { RunText(r.getJSONArray("name"), nav, gloss, MaterialTheme.typography.bodyMedium, Modifier.weight(1f))
                    Text(plain(r.getJSONArray("value")), fontFamily = FontFamily.Monospace, fontWeight = if (r.getString("state").isNotEmpty()) FontWeight.Bold else null,
                        color = when (r.getString("state")) { "alarm" -> CourseColors.of("alarm"); "act" -> CourseColors.of("act"); "ok" -> CourseColors.of("ok"); else -> androidx.compose.ui.graphics.Color.Unspecified }) } }
            }
            RunText(q.getJSONArray("q"), nav, gloss, MaterialTheme.typography.titleSmall)
            if (type == "order") {
                val steps = q.getJSONArray("steps").list().map { it as JSONArray }
                val order = remember { steps.indices.shuffled() }
                if (st.chosen.isNotEmpty()) Dim("Your order (tap a step to take it back):")
                st.chosen.forEachIndexed { k, i ->
                    val right = st.checked && i == k
                    OutlinedButton(onClick = { st.chosen = st.chosen - i; st.checked = false }, modifier = Modifier.fillMaxWidth()) {
                        Text("${k + 1}. " + plain(steps[i]) + if (st.checked) (if (right) "  ✓" else "  ✗") else "", modifier = Modifier.fillMaxWidth()) }
                }
                val pool = order.filter { it !in st.chosen }
                if (pool.isNotEmpty()) Dim("Steps to place:")
                pool.forEach { i -> OutlinedButton(onClick = { st.chosen = st.chosen + i; st.checked = false }, modifier = Modifier.fillMaxWidth()) { Text("· " + plain(steps[i]), modifier = Modifier.fillMaxWidth()) } }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { st.checked = true; if (st.chosen == steps.indices.toList()) prog.solve(id) }) { Text("Check order") }
                    OutlinedButton(onClick = { st.chosen = emptyList(); st.checked = false }) { Text("Start again") }
                }
                if (st.checked) Text(if (st.chosen.size < steps.size) "Not finished. Place all ${steps.size} steps first."
                    else if (st.chosen == steps.indices.toList()) "Right: all in the right order." else "${st.chosen.withIndex().count { it.index == it.value }} of ${steps.size} in the right place.",
                    fontWeight = FontWeight.Bold, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                return@Column
            }
            val opts = q.getJSONArray("options").objects()
            val locked = once && st.picked.isNotEmpty()
            opts.forEachIndexed { i, o ->
                val right = o.getBoolean("right")
                val mark = when { i in st.picked -> if (right) "  ✓" else "  ✗"; locked && right -> "  ✓ (the right answer)"; else -> "" }
                OutlinedButton(onClick = {
                    if (locked) return@OutlinedButton
                    val first = st.picked.isEmpty()
                    st.picked = st.picked + i
                    if (right) prog.solve(id)
                    if (first) onAnswer?.invoke(right)
                }, modifier = Modifier.fillMaxWidth()) {
                    Text(buildAnnotatedString { run(o.getJSONArray("text"), nav, gloss); append(mark) }, modifier = Modifier.fillMaxWidth())
                }
            }
            st.picked.lastOrNull()?.let { last ->
                val o = opts[last]
                Column(Modifier.semantics { liveRegion = LiveRegionMode.Polite }) {
                    Text(if (o.getBoolean("right")) "Right." else "Not quite.", fontWeight = FontWeight.Bold)
                    if (o.getJSONArray("why").length() > 0) RunText(o.getJSONArray("why"), nav, gloss)
                    if (locked && !o.getBoolean("right")) opts.firstOrNull { it.getBoolean("right") }?.let { r ->
                        Text("Correct answer: " + plain(r.getJSONArray("text")) + " " + plain(r.getJSONArray("why"))) }
                }
            }
        }
    }
}

// ---------------------------------------------------------------- drills (§7)

@Composable
fun Vocab(doc: JSONObject, mods: List<JSONObject>, nav: Nav, title: (JSONObject) -> String) {
    val g = remember { doc.getJSONArray("glossary").objects() }
    var round by remember { mutableIntStateOf(0) }
    var stats by remember { mutableStateOf(Triple(0, 0, 0)) }
    val cur = remember(round) { g.random() }
    val choices = remember(round) { (listOf(cur) + g.filter { it !== cur }.shuffled().take(3)).shuffled() }
    var picked by remember(round) { mutableIntStateOf(-1) }
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (stats.first > 0) Dim("${stats.second}/${stats.first} right · streak ${stats.third}")
        Dim("Module " + (mods.firstOrNull { it.getString("id") == cur.getString("module") }?.let(title) ?: ""))
        Text(cur.getString("term"), style = MaterialTheme.typography.headlineSmall, modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        choices.forEachIndexed { i, c ->
            val mark = if (picked < 0) "" else if (c === cur) "  ✓" else if (i == picked) "  ✗ (the meaning of ${c.getString("term")})" else ""
            OutlinedButton(onClick = { if (picked < 0) { picked = i; val ok = c === cur
                stats = Triple(stats.first + 1, stats.second + if (ok) 1 else 0, if (ok) stats.third + 1 else 0) } }, modifier = Modifier.fillMaxWidth()) {
                Text(plain(c.getJSONArray("meaning")) + mark, modifier = Modifier.fillMaxWidth()) }
        }
        Button(onClick = { round++ }) { Text("Next term") }
    } }
}

fun judge(d: JSONObject, v: Double): String {
    for (r in d.getJSONArray("rules").list()) { val a = r as JSONArray; val lim = a.getDouble(1)
        val hit = when (a.getString(0)) { ">=" -> v >= lim; ">" -> v > lim; "<=" -> v <= lim; else -> v < lim }
        if (hit) return a.getString(2) }
    return "ok"
}

fun readingText(v: Double, unit: String): String {
    var t = if (v == Math.rint(v) && Math.abs(v) < 1e15) v.toLong().toString() else v.toString()
    if (t.startsWith("-")) t = "−" + t.substring(1)
    if (v > 0 && unit == "mm") t = "+$t"
    return t
}

@Composable
fun Reading(p: JSONObject, nav: Nav, gloss: Map<String, String>) {
    val items = remember { p.getJSONArray("items").objects() }
    val cats = remember { items.map { it.getString("cat") }.distinct() }
    var on by remember { mutableStateOf(cats.toSet()) }
    var round by remember { mutableIntStateOf(0) }
    var stats by remember { mutableStateOf(Triple(0, 0, 0)) }
    val pool = items.filter { it.getString("cat") in on }
    val cur = remember(round, on) { pool.randomOrNull()?.let { d -> val v = d.getJSONArray("values").list().random().let { (it as Number).toDouble() }; Triple(d, v, judge(d, v)) } }
    var answer by remember(round, on) { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            cats.forEach { c -> FilterChip(selected = c in on, onClick = { on = if (c in on) on - c else on + c }, label = { Text(c) }) } }
        if (cur == null) { Text("Pick at least one topic."); return@Column }
        val (d, v, want) = cur
        Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (stats.first > 0) Dim("${stats.second}/${stats.first} right · streak ${stats.third}")
            RunText(d.getJSONArray("name"), nav, gloss, MaterialTheme.typography.bodyMedium)
            Text(readingText(v, d.getString("unit")) + " " + d.getString("unit"), style = MaterialTheme.typography.headlineMedium, fontFamily = FontFamily.Monospace,
                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
            if (d.getJSONArray("context").length() > 0) RunText(d.getJSONArray("context"), nav, gloss, MaterialTheme.typography.bodySmall)
            for ((a, t) in listOf("ok" to "Within limits (no alarm)", "alarm" to "Alarm (investigate, correct)", "act" to "Beyond limit (stop, hold, trip, don't start)")) {
                val mark = if (answer.isEmpty()) "" else if (a == want) "  ✓" else if (a == answer) "  ✗" else ""
                OutlinedButton(onClick = { if (answer.isEmpty()) { answer = a; val ok = a == want
                    stats = Triple(stats.first + 1, stats.second + if (ok) 1 else 0, if (ok) stats.third + 1 else 0) } }, modifier = Modifier.fillMaxWidth()) { Text(t + mark) }
            }
            if (answer.isNotEmpty()) { Text((if (answer == want) "Right: " else "Not quite: ") + mapOf("ok" to "within limits", "alarm" to "in alarm", "act" to "beyond the action limit")[want] + ".", fontWeight = FontWeight.Bold)
                RunText(d.getJSONArray("note"), nav, gloss) }
            Button(onClick = { round++ }) { Text("Next reading") }
        } }
    }
}

// ---------------------------------------------------------------- figures (§9)

private class Frame(val state: JSONObject, val ops: ByteBuffer)

private fun frame(id: Int, cmd: JSONObject): Frame? {
    val raw = Core.fig(id, cmd) ?: return null
    val bb = ByteBuffer.wrap(raw).order(ByteOrder.LITTLE_ENDIAN)
    val n = bb.int
    val st = JSONObject(String(raw, 4, n, Charsets.UTF_8))
    bb.position(4 + n)
    return Frame(st, bb.slice().order(ByteOrder.LITTLE_ENDIAN))
}

/** the course faces (§9.4) from the app's assets (TTF, vendor/fonts/ttf), the nearest weight; system faces if missing */
private object Faces {
    private val cache = HashMap<String, Typeface>()
    fun of(ctx: android.content.Context, role: Int, weight: Int): Typeface {
        val (fam, weights) = when (role) { 1 -> "BarlowSemiCondensed" to listOf(500, 600, 700); 2 -> "JetBrainsMono" to listOf(400, 600)
            else -> "AtkinsonHyperlegible" to listOf(400, 700) }
        val w = weights.minBy { Math.abs(it - weight) }
        return cache.getOrPut("$fam-$w") {
            runCatching { Typeface.createFromAsset(ctx.assets, "fonts/$fam-$w.ttf") }.getOrElse {
                Typeface.create(when (role) { 1 -> Typeface.create("sans-serif-condensed", Typeface.NORMAL); 2 -> Typeface.MONOSPACE; else -> Typeface.SANS_SERIF }, weight.coerceIn(1, 1000), false) }
        }
    }
}

/** replay kksa/figops.nim's ops on a platform canvas */
private fun replay(c: android.graphics.Canvas, ops: ByteBuffer, face: (Int, Int) -> Typeface) {
    val b = ops.duplicate().order(ByteOrder.LITTLE_ENDIAN)
    val path = Path()
    val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE; strokeMiter = 4f }
    val text = Paint(Paint.ANTI_ALIAS_FLAG)
    fun f() = b.float
    fun col(): Int { val r = f(); val g = f(); val bl = f(); val a = f()
        return android.graphics.Color.argb((a * 255).toInt().coerceIn(0, 255), (r * 255).toInt(), (g * 255).toInt(), (bl * 255).toInt()) }
    while (b.hasRemaining()) {
        when (b.get().toInt() and 0xff) {
            0 -> c.save()
            1 -> c.restore()
            2 -> c.translate(f(), f())
            3 -> c.rotate(Math.toDegrees(f().toDouble()).toFloat())
            4 -> c.scale(f(), f())
            5 -> c.saveLayerAlpha(null, (f() * 255).toInt().coerceIn(0, 255))
            6 -> c.restore()
            7 -> { val x = f(); val y = f(); val w = f(); val h = f(); val rx = f()
                val clip = Path(); clip.addRoundRect(RectF(x, y, x + w, y + h), rx, rx, Path.Direction.CW); c.clipPath(clip) }
            8 -> path.reset()
            9 -> path.moveTo(f(), f())
            10 -> path.lineTo(f(), f())
            11 -> path.cubicTo(f(), f(), f(), f(), f(), f())
            12 -> path.close()
            13 -> { val x = f(); val y = f(); val w = f(); val h = f(); val rx = minOf(f(), w / 2, h / 2).coerceAtLeast(0f)
                path.addRoundRect(RectF(x, y, x + w, y + h), rx, rx, Path.Direction.CW) }
            14 -> { val cx = f(); val cy = f(); val rx = f(); val ry = f(); path.addOval(RectF(cx - rx, cy - ry, cx + rx, cy + ry), Path.Direction.CW) }
            15 -> { fill.shader = null; fill.color = col(); c.drawPath(path, fill) }
            16 -> { val cx = f(); val cy = f(); val rad = f(); val n = b.get().toInt() and 0xff
                val pos = FloatArray(n); val cols = IntArray(n)
                for (i in 0 until n) { pos[i] = f(); cols[i] = col() }
                fill.shader = if (n >= 2) RadialGradient(cx, cy, rad, cols, pos, Shader.TileMode.CLAMP) else null
                if (n == 1) fill.color = cols[0]
                c.drawPath(path, fill); fill.shader = null }
            17 -> { stroke.color = col(); stroke.strokeWidth = f()
                stroke.strokeCap = when (b.get().toInt()) { 1 -> Paint.Cap.ROUND; 2 -> Paint.Cap.SQUARE; else -> Paint.Cap.BUTT }
                stroke.strokeJoin = when (b.get().toInt()) { 1 -> Paint.Join.ROUND; 2 -> Paint.Join.BEVEL; else -> Paint.Join.MITER }
                val n = b.get().toInt() and 0xff
                val d = FloatArray(n) { f() }
                stroke.pathEffect = if (n >= 2) DashPathEffect(if (n % 2 == 0) d else d + d, 0f) else null
                c.drawPath(path, stroke) }
            18 -> { val x = f(); val y = f(); val size = f(); val anchor = b.get().toInt(); val font = b.get().toInt()
                val weight = b.short.toInt() and 0xffff
                text.color = col(); text.textSize = size
                text.typeface = face(font, weight)
                text.textAlign = when (anchor) { 1 -> Paint.Align.CENTER; 2 -> Paint.Align.RIGHT; else -> Paint.Align.LEFT }
                val len = b.short.toInt() and 0xffff
                val bytes = ByteArray(len); b.get(bytes)
                c.drawText(String(bytes, Charsets.UTF_8), x, y, text) }
            else -> return
        }
    }
}

/** How a figure is looked at: at fit (scale 1, the whole figure in the middle of its box) or enlarged, and then which
 *  part is in the box. A point of the fitted figure at (x, y) from its own corner is drawn at (x, y) · scale + off.
 *  `box` is the box it is shown in and `fig` the figure's size at fit in it: the same in a page, where the box has the
 *  figure's shape; over the whole screen the box is all the room there is, and the enlarged figure fills it (a figure
 *  five times as wide as high was a strip there, and could only be enlarged inside the strip). */
class FigZoom {
    var scale by mutableFloatStateOf(1f)
    var off by mutableStateOf(Offset.Zero)
    var moving by mutableStateOf(false)       // fingers are changing it: no bitmap is made meanwhile
    val enlarged get() = scale > 1.01f
    /** along a side the figure does not fill it stands in the middle, along the other inside the box's edges */
    private fun clamp(o: Offset, s: Float, box: Size, fig: Size): Offset {
        fun one(v: Float, b: Float, f: Float) = if (f * s <= b) (b - f * s) / 2 else v.coerceIn(b - f * s, 0f)
        return Offset(one(o.x, box.width, fig.width), one(o.y, box.height, fig.height))
    }
    /** to scale `ns`, the point under `p` staying where it is */
    fun zoomAt(p: Offset, ns: Float, box: Size, fig: Size) { val k = ns / scale; off = clamp(p - (p - off) * k, ns, box, fig); scale = ns }
    /** moved by `d`: how far it went (not past its edges) */
    fun pan(d: Offset, box: Size, fig: Size): Offset { val was = off; off = clamp(off + d, scale, box, fig); return off - was }
    /** whether a finger's move by `d` is the figure's: one that is more sideways than up or down, one up or down
     *  that it can still follow, and any at all where it is no higher than its box (over the whole screen a wide
     *  figure is not, and nothing lies under it). Otherwise, at its upper or lower edge, the move is the page's. */
    fun takes(d: Offset, box: Size, fig: Size) = Math.abs(d.x) > Math.abs(d.y) || fig.height * scale <= box.height ||
        clamp(off + Offset(0f, d.y), scale, box, fig).y != off.y
    fun fit(box: Size, fig: Size) { scale = 1f; off = clamp(Offset.Zero, 1f, box, fig) }
    private var lastBox = Size.Zero
    private var lastFig = Size.Zero
    /** its box, when that is known or has changed (the phone turned): what was in the middle of the last one is in
     *  the middle of this one. (The last box is kept here: over the whole screen, upright and on its side are two
     *  canvases.) */
    fun rebox(box: Size, fig: Size) {
        val c = if (lastFig.width > 0f) (Offset(lastBox.width / 2, lastBox.height / 2) - off) * (fig.width / lastFig.width) else Offset(fig.width / 2, fig.height / 2) * scale
        off = clamp(Offset(box.width / 2, box.height / 2) - c, scale, box, fig)
        lastBox = box; lastFig = fig
    }
    companion object { const val MAX = 6f }
}

/** the zoom a double tap goes to: one view-box unit on one dp (the size the figure was drawn for, docs/COURSES.md
 *  §9.8), at least twice the fitted size */
private fun readableZoom(viewBoxPx: Float, boxPx: Float) = (viewBoxPx / boxPx).coerceIn(2f, FigZoom.MAX)

/** The figure's picture in a box of its shape, with the gestures that enlarge it (the user, 2026-10-13: a figure stays
 *  as wide as the phone, and can be zoomed into): pinch, drag while enlarged, double tap between fit and a readable
 *  size. At fit a one-finger drag is left to the page, so the page scrolls over a figure as over text; enlarged, a
 *  drag moves the figure, and one up or down a figure that is at its edge that way is the page's again.
 *  Two ways to draw (measured on the Note 9, 2026-10-02):
 *  - `live` (playing and the page still), or while fingers change the zoom: the vector ops straight on the canvas
 *    (the GPU path, smooth playback);
 *  - otherwise one bitmap of what the box shows, rasterized in the background. Drawing the vector ops while scrolling
 *    made the render thread re-rasterize every path on every frame (13.6 ms per frame against 4.5 ms for a plain
 *    list); rasterizing every animation frame on the CPU instead made playback stutter. */
@Composable
private fun FigureCanvas(f: JSONObject, ops: State<ByteBuffer?>, live: Boolean, zoom: FigZoom, modifier: Modifier, hidden: Boolean = false) {
    val ctx = LocalContext.current
    val w = f.getDouble("w").toFloat()
    val shape = w / f.getDouble("h").toFloat()
    /** the figure at fit in a box: as large as the box lets it be */
    fun figSize(b: androidx.compose.ui.unit.IntSize): Size { val fw = minOf(b.width.toFloat(), b.height * shape); return Size(fw, fw / shape) }
    fun boxSize(b: androidx.compose.ui.unit.IntSize) = Size(b.width.toFloat(), b.height.toFloat())
    val unit = with(LocalDensity.current) { 1.dp.toPx() }
    var px by remember { mutableStateOf(androidx.compose.ui.unit.IntSize.Zero) }
    val raster = remember { FigureRaster() }
    val rasterLock = remember { kotlinx.coroutines.sync.Mutex() }
    // (with the box's size: a bitmap made for another box, the phone turned since, would be stretched into this one)
    class Still(val ops: ByteBuffer, val size: androidx.compose.ui.unit.IntSize, val scale: Float, val off: Offset, val bitmap: Bitmap)
    val still = remember { mutableStateOf<Still?>(null) }
    fun shows(b: Still?, o: ByteBuffer) = b != null && b.ops === o && b.size == px && b.scale == zoom.scale && b.off == zoom.off
    val cur = ops.value
    val direct = live || zoom.moving
    // not drawn directly: make the bitmap of what is on screen (until it is ready, the ops are drawn directly)
    LaunchedEffect(direct, cur, px, zoom.scale, zoom.off, hidden) {
        if (direct || hidden || cur == null || px.width <= 0 || shows(still.value, cur)) return@LaunchedEffect
        val size = px; val sc = zoom.scale; val off = zoom.off
        // (one at a time: a cancelled effect's drawing still runs to its end, and the raster's buffers are not shared safely)
        val b = withContext(Dispatchers.Default) { rasterLock.withLock { raster.draw(cur, size, figSize(size).width / w * sc, off, still.value?.bitmap) { role, wt -> Faces.of(ctx, role, wt) } } } ?: return@LaunchedEffect
        still.value = Still(cur, size, sc, off, b)
    }
    Canvas(modifier.clipToBounds().onSizeChanged {
            // a new box (the phone turned): it shows the same part of the figure (`off` is in the box's pixels)
            px = it
            zoom.rebox(boxSize(it), figSize(it)) }
        // (keyed: a row of the list is used again for another figure, and its handlers must not keep the old one's zoom)
        .pointerInput(zoom, w, shape) { detectTapGestures(onDoubleTap = { p ->
            val fig = figSize(size)
            if (zoom.enlarged) zoom.fit(boxSize(size), fig) else zoom.zoomAt(p, readableZoom(w * unit, fig.width), boxSize(size), fig) }) }
        .pointerInput(zoom, w, shape) { awaitEachGesture {
            awaitFirstDown(requireUnconsumed = false)
            var drift = Offset.Zero; var dragging = false
            do {
                val ev = awaitPointerEvent()
                val fingers = ev.changes.count { it.pressed }
                if (fingers >= 2 || zoom.enlarged) {
                    val z = ev.calculateZoom(); val pan = ev.calculatePan()
                    // one finger moves the figure only once it has left the spot (the touch slop): a finger that
                    // rolls a little while tapping twice is still a double tap
                    if (fingers >= 2) dragging = true
                    else if (!dragging) { drift += pan; dragging = drift.getDistance() > viewConfiguration.touchSlop }
                    if (dragging && (z != 1f || pan != Offset.Zero)) {
                        val box = boxSize(size); val fig = figSize(size)
                        // one finger moving up or down a figure that is at its edge that way: the page's, and the
                        // figure stays as it is (moved sideways meanwhile, it was drawn anew at every step)
                        if (fingers >= 2 || zoom.takes(pan, box, fig)) {
                            if (fingers >= 2 && z != 1f) zoom.zoomAt(ev.calculateCentroid(useCurrent = false), (zoom.scale * z).coerceIn(1f, FigZoom.MAX), box, fig)
                            zoom.pan(pan, box, fig)
                            zoom.moving = true
                            ev.changes.forEach { if (it.positionChanged()) it.consume() }
                        }
                    }
                }
            } while (ev.changes.any { it.pressed })
            zoom.moving = false
            if (!zoom.enlarged) zoom.fit(boxSize(size), figSize(size))
        } }
        .semantics { contentDescription = f.getString("title") + ". " + f.getString("alt"); role = Role.Image
            if (zoom.enlarged) stateDescription = "Enlarged ${Math.round(zoom.scale * 100)} %"
            // without a pinch or a double tap (TalkBack, a switch): the same step as an action
            customActions = listOf(CustomAccessibilityAction(if (zoom.enlarged) "Fit the figure" else "Zoom into the figure") {
                val fig = figSize(px)
                if (zoom.enlarged) zoom.fit(boxSize(px), fig) else zoom.zoomAt(Offset(px.width / 2f, px.height / 2f), readableZoom(w * unit, fig.width), boxSize(px), fig); true }) }) {
        val o = ops.value ?: return@Canvas
        if (hidden) return@Canvas
        val sb = still.value
        val sc = zoom.scale; val off = zoom.off
        drawIntoCanvas { cv ->
            val nc = cv.nativeCanvas
            if (!direct && shows(sb, o)) nc.drawBitmap(sb!!.bitmap, null, android.graphics.Rect(0, 0, size.width.toInt(), size.height.toInt()), null)
            else { nc.save(); nc.translate(off.x, off.y); val k = figSize(px).width / w * sc; nc.scale(k, k); replay(nc, o) { role, wt -> Faces.of(ctx, role, wt) }; nc.restore() }
        }
    }
}

/** One figure of a page while the page is open: the core's figure (`id`), its last frame and state. It is kept by
 *  the page, not by the figure's row, so the figure enlarged over the whole screen goes on when its row has left the
 *  list. */
class FigRun(val fid: String) {
    var id by mutableIntStateOf(-1)
    private var asked = false
    private var closed = false
    /** true for the one caller that is to make it in the core (the row and the enlarged view both ask) */
    fun claim() = synchronized(this) { if (asked || closed) false else { asked = true; true } }
    /** the core's figure, made; false when the page closed meanwhile: the caller frees it */
    fun made(fig: Int) = synchronized(this) { if (closed) false else { id = fig; true } }
    /** the page closes: the core's figure to free (-1: none yet, `made` will say so to whoever is making it) */
    fun close(): Int = synchronized(this) { closed = true; id }
    val ops = mutableStateOf<ByteBuffer?>(null)        // read only while drawing
    var st by mutableStateOf<JSONObject?>(null)
    private var stText = ""
    // The core computes frames on its own thread; we wait for it off the main thread, so the page never waits.
    suspend fun step(cmd: JSONObject) {
        val fig = id
        if (fig < 0) return
        val fr = withContext(Dispatchers.Default) { frame(fig, cmd) } ?: return
        ops.value = fr.ops
        val t = fr.state.toString()
        if (t != stText) { stText = t; st = fr.state }
    }
    val playing get() = st?.optBoolean("playing") == true
}

/** A test holds back the making of figures in the core (DebugFigureReceiver, in debug builds only; otherwise never
 *  set): the core answers in a few ms, and what happens to a figure opened over the whole screen meanwhile could not
 *  be tested. Held for a minute at most. */
@Volatile var figNewHold = false

/** a page's figures by their place in it, and which one is enlarged over the whole screen ("" for none) */
class PageFigs(val full: MutableState<String>) { val runs = mutableMapOf<String, FigRun>() }

/** Makes the figure in the core if it is not there yet, and steps it frame by frame while it plays and `still` is
 *  false (the page is moving: frames stop and go on where they were). Called by whoever shows the figure, the row
 *  or the enlarged view, never both. Returns whether it is playing live. */
@Composable
private fun figureDriver(doc: JSONObject, run: FigRun, still: Boolean): Boolean {
    val ctx = LocalContext.current
    val f = doc.getJSONObject("figures").getJSONObject(run.fid)
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f     // the app's theme, not the system's
    val reduce = remember { Settings.Global.getFloat(ctx.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f }
    val animated = f.has("period")
    // Keyed on the figure's id too: whoever shows the figure when the core has made it draws its first frame. (The
    // one that asked may have left by then, its row scrolled away or the figure opened over the whole screen, and the
    // one showing it now found it asked for already: the figure stayed empty.)
    LaunchedEffect(dark, run.id) {
        if (run.id < 0) {
            // (not cancellable: a figure made in the core but not kept here would never be freed)
            if (run.claim()) withContext(Dispatchers.IO + kotlinx.coroutines.NonCancellable) {
                var waited = 0
                while (figNewHold && waited++ < 1200) Thread.sleep(50)
                val fig = call("POST", "/native/fig-new", JSONObject().put("course", doc.getString("id")).put("figure", run.fid).put("reduce", reduce)).json.optInt("fig")
                if (!run.made(fig)) call("POST", "/native/fig-free", JSONObject().put("fig", fig))
            }
            return@LaunchedEffect
        }
        run.step(JSONObject().put("dark", dark))
    }
    val live = animated && run.playing && !still
    if (animated) LaunchedEffect(run.id, live, dark) {
        if (run.id < 0 || !live) return@LaunchedEffect
        var last = 0L
        while (isActive) {
            val t = withFrameNanos { it }
            val dt = if (last == 0L) 0.0 else (t - last) / 1e9
            last = t
            run.step(JSONObject().put("tick", dt).put("dark", dark))
        }
    }
    return live
}

@Composable
fun FigureView(doc: JSONObject, fid: String, figs: PageFigs, key: String) {
    val f = doc.getJSONObject("figures").getJSONObject(fid)
    val w = f.getDouble("w").toFloat(); val h = f.getDouble("h").toFloat()
    val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
    val animated = f.has("period")
    val scope = rememberCoroutineScope()
    val scrolling by LocalScrolling.current
    val place = "$key#$fid"                                         // (a test's result blocks share one key)
    val run = remember(place) { figs.runs.getOrPut(place) { FigRun(fid) } }
    val zoom = remember(place) { FigZoom() }
    val full = figs.full.value == place                             // enlarged over the whole screen (FigureFull, which drives it then)
    val live = if (full) false else figureDriver(doc, run, scrolling)
    fun send(cmd: JSONObject) { scope.launch { run.step(cmd.put("tick", 0).put("dark", dark)) } }
    Card(Modifier.fillMaxWidth()) { Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(f.getString("title"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f)); if (animated) Dim("animated")
            IconButton(onClick = { figs.full.value = place }, modifier = Modifier.padding(start = 4.dp)) { Icon(Glyphs.FULLSCREEN, contentDescription = "Enlarge figure: " + f.getString("title")) }
        }
        // as wide as the page (never above 1:1), whatever the figure's width: on a phone it is not scrolled sideways
        // below 520 as docs/COURSES.md §9.8 has it, but fitted, and zoomed into where it is or over the whole screen
        FigureCanvas(f, run.ops, live, zoom, Modifier.widthIn(max = w.dp).fillMaxWidth().aspectRatio(w / h).align(Alignment.CenterHorizontally), hidden = full)
        val s = run.st
        if (animated && s != null) FigureControls(f, s, run.playing, ::send)
        if (f.getJSONArray("caption").length() > 0) Text(plain(f.getJSONArray("caption")), style = MaterialTheme.typography.bodySmall)
    } }
}

/** A figure over the whole screen: as large as the screen lets it be, upright or on its side (its controls then
 *  stand beside it), pinched and dragged like the one in the page. It is the same figure: it goes on playing, and its
 *  controls are the page's. Back or ✕ closes it. */
@Composable
private fun FigureFull(doc: JSONObject, run: FigRun, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        FullScreenDialogWindow()
        val f = doc.getJSONObject("figures").getJSONObject(run.fid)
        val zoom = remember { FigZoom() }
        val animated = f.has("period")
        val dark = MaterialTheme.colorScheme.surface.luminance() < 0.5f
        val scope = rememberCoroutineScope()
        val live = figureDriver(doc, run, still = false)
        val send: (JSONObject) -> Unit = { cmd -> scope.launch { run.step(cmd.put("tick", 0).put("dark", dark)) } }
        val st = run.st
        // the card's own colour under it: the figures' "surface" and "ground" shapes are drawn for it
        Surface(Modifier.fillMaxSize().semantics { paneTitle = f.getString("title") }, color = CardDefaults.cardColors().containerColor) {
            BoxWithConstraints(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(8.dp)) {
                val head: @Composable () -> Unit = { Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(f.getString("title"), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f).padding(start = 4.dp))
                    IconButton(onClick = onClose) { Icon(Glyphs.CLOSE, contentDescription = "Close figure") } } }
                val picture: @Composable (Modifier) -> Unit = { m -> Box(m, contentAlignment = Alignment.Center) {
                    FigureCanvas(f, run.ops, live, zoom, Modifier.fillMaxSize()) } }
                val controls: @Composable () -> Unit = { if (animated && st != null) FigureControls(f, st, run.playing, send) }
                val controlsMax = maxHeight * 0.45f
                // side by side only where there is the width for both (not in the upper half of a split screen, which
                // is wider than high but no wider than the phone)
                if (maxWidth > maxHeight && maxWidth >= 520.dp) Row(Modifier.fillMaxSize(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    picture(Modifier.weight(1f).fillMaxHeight())
                    Column(Modifier.width(if (animated) 300.dp else 160.dp).fillMaxHeight().verticalScroll(rememberScrollState())) { head(); controls() }
                } else Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    head()
                    picture(Modifier.weight(1f).fillMaxWidth())
                    Column(Modifier.heightIn(max = controlsMax).verticalScroll(rememberScrollState())) { controls() }
                }
            }
        }
    }
}

/** three bitmaps in turn: one on screen, one possibly still being uploaded by the render thread, one drawn into
 *  (never `keep`, the one on screen: drawings that were cancelled took turns too) */
private class FigureRaster {
    private val bufs = arrayOfNulls<Bitmap>(3)
    private var next = 0
    /** what a box of `size` shows of the figure: `k` pixels to a view-box unit, its corner at `off` */
    fun draw(ops: ByteBuffer, size: androidx.compose.ui.unit.IntSize, k: Float, off: Offset, keep: Bitmap?, face: (Int, Int) -> Typeface): Bitmap? {
        if (size.width <= 0 || size.height <= 0) return null
        var i = next
        if (keep != null && bufs[i] === keep) i = (i + 1) % bufs.size
        next = (i + 1) % bufs.size
        var b = bufs[i]
        if (b == null || b.width != size.width || b.height != size.height) {
            b = Bitmap.createBitmap(size.width, size.height, Bitmap.Config.ARGB_8888); bufs[i] = b
        }
        b.eraseColor(0)
        val c = android.graphics.Canvas(b)
        c.translate(off.x, off.y)
        c.scale(k, k)
        replay(c, ops, face)
        return b
    }
}

@Composable
private fun FigureControls(f: JSONObject, st: JSONObject, playing: Boolean, send: (JSONObject) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (!st.isNull("status")) Text(st.optString("status"), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { send(JSONObject().put("play", !playing)) }) { Text(if (playing) "Pause" else "Play") }
            f.optJSONObject("slider")?.let { s ->
                val text = st.optString("slider")
                Column(Modifier.weight(1f)) {
                    Text(s.getString("label") + ": " + text, style = MaterialTheme.typography.bodySmall)
                    Slider(st.optDouble("v").toFloat(), { send(JSONObject().put("slider", it.toDouble())) },
                        modifier = Modifier.semantics { contentDescription = s.getString("label"); stateDescription = text })
                }
            }
        }
        f.optJSONArray("toggles")?.objects()?.forEach { tg ->
            val k = tg.getString("key")
            Row(verticalAlignment = Alignment.CenterVertically) {
                Checkbox(st.optJSONObject("toggles")?.optBoolean(k) == true, { send(JSONObject().put("toggle", k)) })
                Text(tg.getString("label")) }
        }
        f.optJSONArray("modes")?.objects()?.forEachIndexed { i, m ->
            Row(verticalAlignment = Alignment.CenterVertically) {
                RadioButton(st.optInt("mode") == i, { send(JSONObject().put("mode", i)) }); Text(m.getString("label")) }
        }
    }
}
