package kks.explorer.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.toggleableState
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.graphics.asImageBitmap
import kks.explorer.core.Core
import kks.explorer.sync.Sync
import kks.explorer.sync.Updates
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

@Composable
fun Root() {
    val dark = androidx.compose.foundation.isSystemInDarkTheme()
    val scheme = if (dark) darkColorScheme() else lightColorScheme()
    CourseColors.isDark = dark      // the course text's colours with a meaning (Learn.kt), for whoever draws course text
    val ctx = LocalContext.current
    DisposableEffect(Unit) {
        val l: (String) -> Unit = { Changes.rev++ }
        Core.listeners.add(l)
        onDispose { Core.listeners.remove(l) }
    }
    // the core opens on its own thread while this first frame is made (App.onCreate, decision 0061): the screen is
    // empty until it has, then the main screen or the setup comes. Sync starts after that.
    var joined by remember { mutableStateOf<Boolean?>(null) }   // (asked again after a rotation: the phone may have been removed since)
    LaunchedEffect(Unit) {
        joined = withContext(Dispatchers.IO) { Sync.joined() }
        Sync.start(ctx.applicationContext)
    }
    MaterialTheme(colorScheme = scheme) {
        Surface(Modifier.fillMaxSize()) {
            when (joined) {
                null -> {}
                true -> MainScreen()
                false -> {
                    // a link that came before the phone joined a plant opens nothing, now or later (decision 0058)
                    LaunchedEffect(AppLinks.pending) { AppLinks.pending = null }
                    SetupScreen { joined = true }
                }
            }
        }
    }
}

data class SheetInfo(val id: String, val name: String, val scale: Float, val levels: Int, val tags: Int, val review: Int, val notes: List<String>)

fun sheets(): List<SheetInfo> = call("GET", "/native/sheets").json.optJSONArray("sheets").objects().map {
    SheetInfo(it.getString("id"), it.getString("name"), it.optDouble("scale", 2.0).toFloat(), it.optInt("levels"), it.optInt("tags"), it.optInt("review"),
        it.optJSONArray("notes")?.let { a -> (0 until a.length()).map { i -> a.getString(i) } } ?: emptyList())
}

fun tagBoxes(sheet: String, scale: Float): List<SheetView.TagBox> = call("GET", "/native/tags", query = mapOf("sheet" to sheet)).json.optJSONArray("tags").objects().map {
    SheetView.TagBox(it.getString("id"), it.getDouble("x0").toFloat(), it.getDouble("y0").toFloat(), it.getDouble("x1").toFloat(),
        it.getDouble("y1").toFloat(), it.getString("status"), it.optString("code"), it.optString("photos", "none"))
} + call("GET", "/api/submissions", query = mapOf("status" to "open")).json.optJSONArray("submissions").objects()   // my proposed marks, dashed
    .filter { it.optBoolean("mine") && it.str("kind") == "tag_add" && it.optJSONObject("payload")?.str("sheet") == sheet }
    .mapNotNull { sub ->
        val b = sub.getJSONObject("payload").optJSONArray("bbox") ?: return@mapNotNull null
        SheetView.TagBox("pending:" + sub.optLong("id"), (b.getDouble(0) / scale).toFloat(), (b.getDouble(1) / scale).toFloat(),
            (b.getDouble(2) / scale).toFloat(), (b.getDouble(3) / scale).toFloat(), "pending", "")
    }

/** A walkdown:// link from another app (decision 0058), as MainActivity received it: the main screen asks the core
 *  what it opens (`/native/link`, core/src/kks/applink.nim) and shows that. Nothing else reads it. */
object AppLinks {
    var pending by mutableStateOf<String?>(null)
    /** MainActivity is in front: a link waits while the camera or a picker is open over it (its result goes to the
     *  panel that asked for it) */
    var resumed by mutableStateOf(false)
    /** screens holding something unfinished (a photo being marked up, a form being typed): a link waits for them */
    var holds by mutableIntStateOf(0)
}

/** while this is on screen, a link waits (AppLinks.holds) */
@Composable
fun HoldLinks() = DisposableEffect(Unit) {
    AppLinks.holds++
    onDispose { AppLinks.holds-- }
}

/** what the screens share: the open sheet and tag, the active procedure, link mode (R7) */
class Ui {
    var tab by mutableStateOf("drawings")
    var sheet by mutableStateOf("")
    var selected by mutableStateOf("")
    var coverage by mutableStateOf(false)                  // the drawings coloured by photos
    /** the Dark drawings setting: "follow" (the system's theme), "dark" or "light" (remembered on this device: prefs
     *  "app", [DARK_MODE_PREF]) */
    var darkMode by mutableStateOf("follow")
    var focus by mutableStateOf<List<Float>?>(null)       // a tag to zoom to once its sheet is shown
    var activeProc by mutableStateOf("")
    var linkProc by mutableStateOf("")
    var linkStep by mutableIntStateOf(0)
    var floor by mutableStateOf("")
    var focusSeq by mutableIntStateOf(0)
    var fullView by mutableStateOf(false)                 // the drawing alone: no header, no search (more room)
    var focusCy by mutableFloatStateOf(0.22f)              // where the focus lands (a fraction of the height)
    var arrived by mutableStateOf<Triple<String, Float, Float>?>(null)   // the connector followed to: sheet, x0, y0
    var courseLink by mutableStateOf<Pair<String, String>?>(null)    // a link's course and page, for Learning to open
    var courseSeq by mutableIntStateOf(0)
    // where the drawing was (SheetView.place): read when the screen's state is saved, kept while Drawings is not shown
    var placeNow: (() -> Pair<String, FloatArray>?)? = null
    var placeSheet = ""
    var place: FloatArray? = null

    companion object {
        /** #366 (G2 in docs/UI-UX-POLICY.md): what the screens share comes back after the phone is turned and after
         *  Android stopped the app in the background: the tab, the sheet and where on it, the open tag, the procedure,
         *  link mode, the floor, full view, colouring by photos */
        val Saver = androidx.compose.runtime.saveable.listSaver<Ui, Any>(save = { u ->
            val (ps, p) = u.placeNow?.invoke() ?: (u.placeSheet to u.place)
            listOf(u.tab, u.sheet, u.selected, u.activeProc, u.linkProc, u.linkStep, u.floor, u.fullView, u.coverage,
                   ps, p?.let { floatArrayOf(*it) } ?: FloatArray(0))
        }, restore = { l ->
            Ui().apply {
                tab = l[0] as String; sheet = l[1] as String; selected = l[2] as String; activeProc = l[3] as String
                linkProc = l[4] as String; linkStep = l[5] as Int; floor = l[6] as String; fullView = l[7] as Boolean
                coverage = l[8] as Boolean; placeSheet = l[9] as String; place = (l[10] as FloatArray).takeIf { it.size == 3 }
            }
        })
    }

    /** open where a connector's line continues: its sheet, centred on the connector (no panel in the way) */
    fun goLink(t: LinkTarget) {
        tab = "drawings"
        selected = ""
        sheet = t.sheet
        arrived = Triple(t.sheet, t.box[0], t.box[1])
        focus = t.box
        focusCy = 0.5f
        focusSeq++
    }

    /** show a tag on its drawing (from search, a procedure, the review queue, "appears on") */
    fun show(tagId: String) {
        val t = call("GET", "/native/tag", query = mapOf("id" to tagId)).json
        if (!t.has("sheet")) return
        tab = "drawings"
        selected = tagId
        sheet = t.getString("sheet")
        focus = t.optJSONArray("box")?.let { a -> (0 until 4).map { a.getDouble(it).toFloat() } }
        focusCy = 0.22f
        focusSeq++
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val ui = rememberSaveable(saver = Ui.Saver) { Ui() }
    remember(ui) { ui.darkMode = storedDarkMode(ctx.getSharedPreferences("app", android.content.Context.MODE_PRIVATE)) }
    val snack = remember { SnackbarHostState() }
    val rev = Changes.rev
    val admin = remember(rev) { Sync.config().optBoolean("admin") }
    val queue = remember(rev) { if (admin) call("GET", "/api/state").json.optInt("queue") else 0 }
    BackHandler(enabled = ui.tab != "drawings") { ui.tab = "drawings" }
    Scaffold(
        snackbarHost = { SnackbarHost(snack) },
        bottomBar = {
            NavigationBar {
                // one label size for all five, shrunk until the longest fits on one line (large font settings wrapped
                // "Procedures" on the Note 9)
                var labelScale by remember { mutableFloatStateOf(1f) }
                for ((id, label) in listOf("drawings" to "Drawings", "procedures" to "Procedures", "review" to "Review", "learning" to "Learning", "manage" to "Manage")) {
                    val glyph = when (id) { "drawings" -> Glyphs.DRAWINGS; "procedures" -> Glyphs.PROCEDURES; "review" -> Glyphs.REVIEW; "learning" -> Glyphs.LEARNING; else -> Glyphs.MANAGE }
                    NavigationBarItem(selected = ui.tab == id, onClick = { ui.tab = id },
                        label = { val st = MaterialTheme.typography.labelMedium
                            Text(label, maxLines = 1, softWrap = false, style = st.copy(fontSize = st.fontSize * labelScale),
                                onTextLayout = { if (it.didOverflowWidth && labelScale > 0.7f) labelScale -= 0.05f }) },
                        icon = {
                            if (id == "manage" && queue > 0) BadgedBox(badge = { Badge { Text("$queue") } }) { Icon(glyph, contentDescription = null) }
                            else Icon(glyph, contentDescription = null)
                        })
                }
            }
        }
    ) { pad ->
        // (the bottom bar's height, for the tag panel: it rises only by what the keyboard covers of it)
        CompositionLocalProvider(LocalBottomBars provides pad.calculateBottomPadding()) {
        Column(Modifier.padding(pad).fillMaxSize()) {
            UpdateBanner()
            PhotoQueueBar()
            Box(Modifier.weight(1f).fillMaxWidth()) {
            when (ui.tab) {
                "drawings" -> Drawings(ui, snack)
                "procedures" -> Procedures(ui, snack)
                "review" -> ReviewQueue(ui)
                "learning" -> Learning(ui, snack)
                "manage" -> Manage(snack, ui)
            }
            }
        }
        }
    }
    // a link from another app: a code opens its tag on its drawing (as a course's code link), a course opens on the
    // Learning tab; anything else does nothing (the core reads the link, strictly)
    val link = if (AppLinks.resumed && AppLinks.holds == 0) AppLinks.pending else null
    val waiting = AppLinks.resumed && AppLinks.holds > 0 && AppLinks.pending != null
    LaunchedEffect(waiting) {
        if (waiting) scope.launch { snack.showSnackbar("A link from another app opens once what is open here is sent or cancelled") }
    }
    LaunchedEffect(link) {
        if (link == null) return@LaunchedEffect
        AppLinks.pending = null       // (taken once: the same link again is a new request)
        val r = call("GET", "/native/link", query = mapOf("url" to link))
        if (!r.ok) return@LaunchedEffect
        when (r.json.str("kind")) {
            "kks" -> {
                val tag = r.json.str("tag")
                if (tag.isNotEmpty()) ui.show(tag)
                else {      // (in the screen's scope: this effect ends as soon as the link is cleared)
                    ui.tab = "drawings"
                    scope.launch { snack.showSnackbar(r.json.str("code") + " is not on any drawing") }
                }
            }
            "course" -> {
                ui.courseLink = r.json.str("course") to r.json.str("page")
                ui.courseSeq++
                ui.tab = "learning"
            }
        }
    }
    LaunchedEffect(Unit) { withContext(Dispatchers.IO) { runCatching { Updates.maybeCheck(ctx.applicationContext) } } }
    LaunchedEffect(Unit) {
        // first start after joining: one round right away, so the phone shows the plant without waiting
        withContext(Dispatchers.IO) { runCatching { Sync.syncAll(ctx.applicationContext) } }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun Drawings(ui: Ui, snack: SnackbarHostState) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val rev = Changes.rev
    val list = remember(rev) { sheets() }
    LaunchedEffect(list) { if (ui.sheet.isEmpty() || list.none { it.id == ui.sheet }) list.firstOrNull()?.let { ui.sheet = it.id } }
    // (saved: turning the phone or the app stopped in the background keeps them, #366)
    var query by rememberSaveable { mutableStateOf("") }
    var drawer by rememberSaveable { mutableStateOf(false) }
    var floorMenu by remember { mutableStateOf(false) }
    var notesOpen by remember { mutableStateOf(false) }
    var systemsOpen by remember { mutableStateOf(false) }
    var systemsOnly by remember { mutableStateOf<String?>(null) }       // from Coverage: one system
    var coverageOpen by remember { mutableStateOf(false) }
    var view by remember { mutableStateOf<SheetView?>(null) }
    // the drawings follow the system's theme until the person says always dark or always light (the user, 2026-11-16)
    val darkDrawings = darkNow(ui.darkMode, androidx.compose.foundation.isSystemInDarkTheme())
    var darkAsk by remember { mutableStateOf(false) }
    val current = list.firstOrNull { it.id == ui.sheet }
    val boxes = remember(ui.sheet, rev) { if (current != null) tagBoxes(current.id, current.scale) else emptyList() }
    var marking by rememberSaveable { mutableStateOf(false) }
    var marked by rememberSaveable { mutableStateOf<List<Float>?>(null) }
    LaunchedEffect(marking, view) { view?.marking = marking }
    // selecting tags: one photo, place or note for several codes (Select.kt)
    var selecting by rememberSaveable { mutableStateOf(false) }
    // the selection is codes, in the order picked: it lasts across drawings (tags in the same place can be on
    // different ones; the user, 2026-10-10), filled by taps and boxes here, by search and by typed codes (the List)
    var selection by rememberSaveable { mutableStateOf<Set<String>>(emptySet()) }
    var multi by rememberSaveable { mutableStateOf("") }                              // the open dialog: list, floor, photo, place, note
    var noFloor by rememberSaveable { mutableStateOf<List<String>>(emptyList()) }     // Photo for all: the codes its floor is asked for
    var multiFloor by rememberSaveable { mutableStateOf("") }                         // … and the floor chosen, sent with the photo
    // every code on a drawing with its sheets (null until read): typed codes are checked against it, the List shows it
    val places by produceState<Map<String, List<Drawn>>?>(null, rev, selecting) {
        value = if (selecting) withContext(Dispatchers.IO) { codeIndex() } else null
    }
    LaunchedEffect(selecting, view) { view?.selecting = selecting }
    LaunchedEffect(selection, boxes, view) { view?.selection = boxes.filter { it.code.isNotEmpty() && it.code in selection }.map { it.id }.toSet() }
    val selectedCodes = selection.toList()
    val floors = remember(rev) { call("GET", "/native/floors").json }
    val linkedCodes = remember(ui.activeProc, rev) {
        if (ui.activeProc.isEmpty()) emptySet() else call("GET", "/native/proc", query = mapOf("id" to ui.activeProc)).json.optJSONArray("links").objects().map { it.getString("kks") }.toSet()
    }
    // Back closes the top layer first (R2): the sheet list, the panel, marking, selecting, full view, link mode
    BackHandler(enabled = ui.selected.isNotEmpty() || drawer || ui.linkProc.isNotEmpty() || selecting || marking || ui.fullView) {
        when {
            drawer -> drawer = false
            ui.selected.isNotEmpty() -> ui.selected = ""
            marking -> marking = false
            selecting -> { selecting = false; selection = emptySet() }
            ui.fullView -> ui.fullView = false
            else -> ui.linkProc = ""
        }
    }
    // where on the drawing: read from the view when the state is saved, and kept here while another tab is shown
    DisposableEffect(view) {
        val v = view
        ui.placeNow = { v?.place() }
        onDispose {
            v?.place()?.let { (s, p) -> ui.placeSheet = s; ui.place = p }
            ui.placeNow = null
        }
    }
    LaunchedEffect(ui.sheet, view, current?.id) {
        val v = view ?: return@LaunchedEffect
        if (current != null) {
            v.restore = if (ui.placeSheet == current.id) ui.place else null
            ui.place = null; ui.placeSheet = ""
            v.setSheet(current.id, current.scale, current.levels)
        }
    }
    LaunchedEffect(boxes, view) { view?.tags = boxes }
    // the connectors (Links.kt): circles on the drawing, "Connectors on this sheet", a choice when there are several
    val links = remember(ui.sheet, rev) { if (current != null) linksOf(current.id) else emptyList() }
    val linkBoxes = remember(links) { links.map(::linkBox) }
    var connectorsOpen by remember { mutableStateOf(false) }
    var ask by remember { mutableStateOf<Follow.Ask?>(null) }
    // the connector arrived at stays bold only on the sheet it was followed to, until another sheet is opened
    LaunchedEffect(ui.sheet) { if (ui.arrived?.first != ui.sheet) ui.arrived = null }
    LaunchedEffect(linkBoxes, ui.arrived, view) {
        val v = view ?: return@LaunchedEffect
        v.links = linkBoxes
        v.linkSel = ui.arrived?.takeIf { it.first == ui.sheet }?.let { a ->
            linkBoxes.indexOfFirst { Math.abs(it.x0 - a.second) < 0.01f && Math.abs(it.y0 - a.third) < 0.01f } } ?: -1
    }
    val say: (String) -> Unit = { m -> scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar(m) } }
    // another tag or sheet while the panel holds typed text: asked first (#366, D3)
    var leaving by remember { mutableStateOf<(() -> Unit)?>(null) }
    val leavePanel = { then: () -> Unit -> if (ui.selected.isNotEmpty() && PanelDrafts.any()) leaving = then else then() }
    leaving?.let { then ->
        Confirm("Discard your edits?", "What you typed in the panel has not been saved.", "Discard", { PanelDrafts.drop(); then() },
            { leaving = null }, no = "Keep editing")
    }
    val capped = "At most $MAX_PICK tags at once: send these first"
    val toggleCode: (String) -> Unit = { code ->
        if (code in selection) selection = selection - code
        else { val (next, full) = addCapped(selection, listOf(code)); selection = next; if (full) say(capped) }
    }
    val goLink: (LinkTarget) -> Unit = { t ->
        if (sheets().none { it.id == t.sheet }) say("Connector ${t.label}: that drawing is no longer in the app")
        else { ui.goLink(t); say("Connector ${t.label} on ${t.sheetName.ifEmpty { t.sheet }}") }
    }
    val followLink: (String, String, Float, Float) -> Unit = { sh, label, x0, y0 ->
        when (val f = follow(sh, label, x0, y0)) {
            is Follow.Say -> say(f.text)
            is Follow.Go -> goLink(f.target)
            is Follow.Ask -> ask = f
        }
    }
    // the open panel's valve symbol, outlined on the drawing while the panel shows it
    val symbolBox = remember(ui.selected, ui.sheet, rev) {
        if (ui.selected.isEmpty()) null
        else call("GET", "/native/tag", query = mapOf("id" to ui.selected)).json.takeIf { it.str("sheet") == ui.sheet }
            ?.optJSONObject("valve_type")?.optJSONArray("box")?.takeIf { it.length() == 4 }?.let { a -> (0 until 4).map { a.getDouble(it).toFloat() } }
    }
    LaunchedEffect(symbolBox, view) { view?.symbolBox = symbolBox }
    LaunchedEffect(ui.selected, view) { view?.selected = ui.selected }
    LaunchedEffect(ui.coverage, view) { view?.coverage = ui.coverage }
    LaunchedEffect(darkDrawings, view) { view?.dark = darkDrawings }
    if (darkAsk) DarkDrawingsDialog(ui.darkMode, onPick = {
        ui.darkMode = it
        ctx.getSharedPreferences("app", android.content.Context.MODE_PRIVATE).edit().putString(DARK_MODE_PREF, it).apply()
    }, onClose = { darkAsk = false })
    LaunchedEffect(linkedCodes, boxes, view) { view?.highlight = boxes.filter { it.code in linkedCodes }.map { it.id }.toSet() }
    LaunchedEffect(ui.floor, floors, view) {
        view?.dimmed = if (ui.floor.isEmpty()) null else floors.optJSONArray(ui.floor)?.let { a -> (0 until a.length()).map { a.getString(it) }.toSet() } ?: emptySet()
    }
    LaunchedEffect(ui.focusSeq, view) {
        val v = view ?: return@LaunchedEffect
        val b = ui.focus ?: return@LaunchedEffect
        ui.focus = null
        val cy = ui.focusCy
        v.post { v.centerOn(b[0], b[1], b[2], b[3], cy = cy) }
    }
    Column(Modifier.fillMaxSize()) {
        // long sheet names wrap to two lines in a smaller style, then end in "…" (the full name is in Sheets)
        if (!ui.fullView) TopAppBar(title = { Text(current?.name ?: "Walkdown", maxLines = 2, style = MaterialTheme.typography.titleMedium,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis) }, actions = {
            TextButton(onClick = { drawer = !drawer }) { Text(if (drawer) "Close" else "Sheets") }
            TextButton(onClick = { scope.launch {
                val n = withContext(Dispatchers.IO) { Sync.syncAll(ctx.applicationContext, wait = true) }
                snack.showSnackbar(if (n > 0) "Synced with $n device${if (n == 1) "" else "s"}" else "No other device reached")
            } }) { Text("Sync") }
            Box {
                IconButton(onClick = { floorMenu = true }, modifier = Modifier.semantics { contentDescription = "More" }) { Text("⋮", style = MaterialTheme.typography.titleLarge) }
                DropdownMenu(floorMenu, { floorMenu = false }) {
                    DropdownMenuItem(text = { Text("Equipment by system") }, onClick = { systemsOnly = null; systemsOpen = true; floorMenu = false })
                    DropdownMenuItem(text = { Text("Coverage") }, onClick = { coverageOpen = true; floorMenu = false })
                    if (current != null) DropdownMenuItem(text = { Text("Colour tags by photos" + if (ui.coverage) " ✓" else "") },
                        onClick = { ui.coverage = !ui.coverage; floorMenu = false })
                    // a setting with three choices (its dialog); the item says the one in force
                    // (the choice on a line of its own under the name: beside it, "Dark drawings" broke mid-word at
                    // the largest text size, #401's UI/UX audit)
                    if (current != null) DropdownMenuItem(text = { Column {
                            Text("Dark drawings")
                            Text(darkModeLabel(ui.darkMode), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        } },
                        onClick = { darkAsk = true; floorMenu = false })
                    if (current != null) DropdownMenuItem(text = { Text(if (marking) "Stop marking" else "Mark a missing tag") },
                        onClick = { marking = !marking; selecting = false; selection = emptySet(); ui.selected = ""; floorMenu = false })
                    if (current != null) DropdownMenuItem(text = { Text(if (selecting) "Stop selecting" else "Select tags") },
                        onClick = { selecting = !selecting; selection = emptySet(); marking = false; ui.selected = ""; floorMenu = false })
                    if (current != null) DropdownMenuItem(text = { Text("Connectors on this sheet (${links.size})") },
                        onClick = { connectorsOpen = true; floorMenu = false })
                    if (current != null && current.notes.isNotEmpty()) DropdownMenuItem(text = { Text("Notes on this sheet (${current.notes.size})") },
                        onClick = { notesOpen = true; floorMenu = false })
                    if (floors.length() > 0) {
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("All floors" + if (ui.floor.isEmpty()) " ✓" else "") }, onClick = { ui.floor = ""; floorMenu = false })
                        for (f in floors.keys().asSequence().sortedBy { it.toIntOrNull() ?: 99 })
                            DropdownMenuItem(text = { Text("Floor $f" + if (ui.floor == f) " ✓" else "") }, onClick = { ui.floor = f; floorMenu = false })
                    }
                }
            }
        })
        if (systemsOpen) SystemsScreen(ui, systemsOnly) { systemsOpen = false }
        if (coverageOpen) CoverageScreen(
            onSheet = { id ->
                // false: the sheet is gone (a hand-marked tag can outlive it); the dashboard says so in its own window
                if (list.none { it.id == id }) false
                else { coverageOpen = false; ui.tab = "drawings"; ui.selected = ""; ui.sheet = id; ui.coverage = true; true }
            },
            onSystem = { sys -> coverageOpen = false; systemsOnly = sys; systemsOpen = true },
            onClose = { coverageOpen = false })
        if (connectorsOpen && current != null) ConnectorsDialog(current.name, links, onPick = { l ->
            followLink(current.id, l.str("label"), l.optDouble("x0").toFloat(), l.optDouble("y0").toFloat())
        }, onDismiss = { connectorsOpen = false })
        ask?.let { a -> LinkChoice(a, onGo = goLink, onDismiss = { ask = null }) }
        if (notesOpen && current != null) AlertDialog(onDismissRequest = { notesOpen = false }, title = { Text("Notes on ${current.name}") },
            text = { Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) { current.notes.forEach { Text(it) } } },
            confirmButton = { TextButton(onClick = { notesOpen = false }) { Text("Close") } })
        if (ui.floor.isNotEmpty()) Dim("  Showing floor ${ui.floor}: other tags are dimmed")
        if (ui.coverage) CoverageLegend()
        // clipped: zoomed in, the drawing used to draw over the header (the user's video, 2026-10-05); full screen is
        // a choice now (the button above Fit)
        Box(Modifier.fillMaxSize().clipToBounds()) {
            AndroidView(factory = { c -> SheetView(c).also { v -> view = v } }, modifier = Modifier.fillMaxSize(), update = { v ->
                v.onMark = { x0, y0, x1, y1 ->
                    val sc = current?.scale ?: 2f
                    if ((x1 - x0) * sc < 8 || (y1 - y0) * sc < 8) scope.launch { snack.showSnackbar("Box too small: drag across the whole tag") }
                    else marked = listOf(x0, y0, x1, y1)
                }
                v.onLink = { i -> v.links.getOrNull(i)?.let { l -> followLink(ui.sheet, l.label, l.x0, l.y0) } }
                v.onToggle = { id ->
                    val t = boxes.firstOrNull { it.id == id }
                    if (t == null || t.code.isEmpty()) say("This tag has no code yet: it can't be selected") else toggleCode(t.code)
                }
                v.onBox = { ids ->
                    val hit = boxes.filter { it.id in ids }
                    val ok = hit.filter { it.code.isNotEmpty() }
                    val (next, full) = addCapped(selection, ok.map { it.code })
                    selection = next
                    if (full) scope.launch { snack.showSnackbar(capped) }
                    else if (ok.size < hit.size) scope.launch { snack.showSnackbar("${hit.size - ok.size} tag(s) without a code left out") }
                }
                v.onTag = { id ->
                    if (ui.linkProc.isNotEmpty()) {
                        val code = boxes.firstOrNull { it.id == id }?.code.orEmpty()
                        if (code.isEmpty()) scope.launch { snack.showSnackbar("This tag has no code yet: check it first") }
                        else {
                            val (_, m) = submit("link", JSONObject().put("proc", ui.linkProc).put("step", ui.linkStep).put("kks", code).put("on", true))
                            scope.launch { snack.showSnackbar("$code → step ${ui.linkStep}: $m") }
                        }
                    } else if (id != ui.selected) leavePanel { ui.selected = id }
                }
            })
            if (list.isEmpty()) Card(Modifier.align(Alignment.Center).padding(24.dp)) {
                Text("Waiting for the drawings. They arrive with the next sync from a device that has them.", Modifier.padding(16.dp))
            }
            // the whole sheet again, centred (the web viewer's ⤢, GNOME's header button, the 0 key on desktops)
            if (current != null) Column(Modifier.align(Alignment.BottomEnd).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                SmallFloatingActionButton(onClick = { ui.fullView = !ui.fullView },
                    modifier = Modifier.semantics { contentDescription = if (ui.fullView) "Show the header and search" else "Full screen: the drawing only" }) {
                    Icon(if (ui.fullView) Glyphs.FULLSCREEN_EXIT else Glyphs.FULLSCREEN, contentDescription = null)
                }
                SmallFloatingActionButton(onClick = { view?.fit() }, modifier = Modifier.semantics { contentDescription = "Fit the sheet to the screen" }) {
                    Icon(Glyphs.FIT, contentDescription = null)
                }
            }
            // the search and its results end above the keyboard (by what it covers of the bottom bar), so the list
            // shrinks and the photo legend under it stays in view while typing (#401's UI/UX audit, R3)
            Column(Modifier.fillMaxWidth().consumeWindowInsets(PaddingValues(bottom = LocalBottomBars.current)).imePadding().padding(8.dp)) {
                if (marking) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Row(Modifier.padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Drag a box around the tag the app missed (two fingers move the drawing)", Modifier.weight(1f))
                        TextButton(onClick = { marking = false }) { Text("Cancel") }
                    }
                }
                if (selecting) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Text("Tap tags to select them. Hold, then drag, to add every tag in a box (one finger still moves the drawing). " +
                        "For tags on other drawings: search, open another sheet, or type codes in the List.",
                        Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                }
                if (ui.linkProc.isNotEmpty()) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Row(Modifier.padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Tap tags to link them to step ${ui.linkStep} of ${ui.linkProc}", Modifier.weight(1f))
                        TextButton(onClick = { ui.tab = "procedures"; ui.linkProc = "" }) { Text("Done") }
                    }
                }
                if (!ui.fullView) OutlinedTextField(query, { query = it }, placeholder = { Text("Search KKS or description") }, singleLine = true,
                    // while selecting, the results stay open to pick several: this closes them
                    trailingIcon = if (selecting && query.isNotEmpty()) ({
                        IconButton(onClick = { query = "" }) { Icon(Glyphs.CLOSE, contentDescription = "Clear the search") }
                    }) else null,
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Search equipment by KKS code or description" },
                    colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = MaterialTheme.colorScheme.surface, unfocusedContainerColor = MaterialTheme.colorScheme.surface))
                if (!ui.fullView && query.trim().length >= 2) {
                    val res = remember(query, rev) { call("GET", "/native/search", query = mapOf("q" to query.trim())).json.optJSONArray("results").objects() }
                    // the results scroll within 320 dp, or the room left on a low screen; what the photo marks mean
                    // stays in view under them (weighted, the list is measured after the legend: in landscape the
                    // legend was cut off below a 320 dp list, #401's UI/UX audit)
                    Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth().weight(1f, fill = false)) { BoxWithConstraints {
                    // the legend only where a result row (72 dp) and a two-line legend fit with it: on its side with the
                    // keyboard up the results keep what little room there is (#401's UI/UX audit, pass 2: the legend
                    // left them about 30 dp); each mark still says its state to TalkBack, and the legend is back with
                    // the keyboard down
                    val legendFits = maxHeight >= 128.dp * LocalDensity.current.fontScale
                    Column {
                        if (res.isEmpty()) Text("Nothing found", Modifier.padding(16.dp))
                        LazyColumn(Modifier.weight(1f, fill = false).heightIn(max = 320.dp)) {
                            items(res) { r ->
                                val code = r.getString("code")
                                // the code's photos, as a mark before it and in words for TalkBack
                                val photos = r.optString("photos").ifEmpty { "none" }
                                val mark: (@Composable () -> Unit)? = if (code.isEmpty()) null else { { PhotoMark(photos, named = true) } }
                                // while selecting, a result (on any drawing) adds its code or takes it out again; the
                                // mode and the drawing stay as they are
                                if (selecting) ListItem(headlineContent = { Text(code.ifEmpty { "(unread)" }) },
                                    supportingContent = { Text(r.getString("kind") + " · " + r.getString("sheet_name") + if (code.isEmpty()) " · no code: can't be selected" else "") },
                                    leadingContent = mark,
                                    trailingContent = { if (code.isNotEmpty()) Checkbox(code in selection, onCheckedChange = null) },
                                    modifier = Modifier.toggleable(value = code in selection, enabled = code.isNotEmpty(),
                                        role = androidx.compose.ui.semantics.Role.Checkbox, onValueChange = { toggleCode(code) }))
                                else ListItem(headlineContent = { Text(code.ifEmpty { "(unread)" }) },
                                    supportingContent = { Text(r.getString("kind") + " · " + r.getString("sheet_name")) },
                                    leadingContent = mark,
                                    modifier = Modifier.clickable { query = ""; ui.show(r.getString("id")) })
                            }
                        }
                        if (legendFits && res.any { it.optString("code").isNotEmpty() }) PhotoLegend()
                    } } }
                }
            }
            if (drawer) Surface(tonalElevation = 6.dp, modifier = Modifier.fillMaxHeight().width(300.dp).align(Alignment.CenterStart)) {
                LazyColumn {
                    item { Text("Sheets", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(16.dp)) }
                    items(list) { s ->
                        ListItem(headlineContent = { Text(s.name) }, supportingContent = { Text("${s.tags} tags" + if (s.review > 0) ", ${s.review} to review" else "") },
                            modifier = Modifier.clickable { drawer = false; leavePanel { ui.sheet = s.id; ui.selected = "" } })
                    }
                }
            }
            if (selecting) SelectBar(selection.size, Modifier.align(Alignment.BottomCenter),
                onList = { multi = "list" }, onPhoto = {
                    val codes = selectedCodes
                    scope.launch {
                        // the floor first, as for one photo of one tag: asked only when a code has none, sent with the photo
                        val missing = withContext(Dispatchers.IO) { codesWithoutFloor(codes) }
                        // the selection changed (or ended) while the floors were read: the answer is for other codes
                        if (!selecting || multi.isNotEmpty() || selection.toList() != codes || codes.isEmpty()) return@launch
                        multiFloor = queuedFloorFor(missing); noFloor = missing
                        multi = if (missing.isEmpty() || multiFloor.isNotEmpty()) "photo" else "floor"
                    }
                }, onPlace = { multi = "place" }, onNote = { multi = "note" },
                onDone = { selecting = false; selection = emptySet() })
            val sent: (String) -> Unit = { m ->
                if (m.startsWith("Sent for")) { selecting = false; selection = emptySet() }
                scope.launch { snack.showSnackbar(m) }
            }
            when (multi) {
                "list" -> SelectList(selectedCodes, places, onUntick = { selection = selection - it }, onAdd = { add ->
                    val (next, _) = addCapped(selection, add)
                    selection = next
                    add.filter { it !in next }
                }, onClose = { multi = "" })
                "floor" -> FloorForAll(noFloor, selectedCodes.size, onPick = { multiFloor = it; multi = "photo" }, onClose = { multi = "" })
                "photo" -> PhotoForAll(selectedCodes, multiFloor, noFloor, onSaid = say, onQueued = {
                    selecting = false; selection = emptySet()
                    say("Photo queued: it is compressed and sent in the background")
                }) { multi = "" }
                "place" -> PlaceForAll(selectedCodes, sent) { multi = "" }
                "note" -> NoteForAll(selectedCodes, sent) { multi = "" }
            }
            marked?.let { b ->
                // (current is null for a moment after the app was stopped with this open: the sheets are read again)
                current?.let { c -> MarkDialog(c, b, view, snack, onDone = { ok -> marked = null; if (ok) marking = false }) }
            }
            if (ui.selected.isNotEmpty()) TagPanel(ui.selected, rev, onClose = { ui.selected = "" },
                onGo = { id, _, _ -> ui.show(id) }, snack = snack, modifier = Modifier.align(Alignment.BottomCenter),
                link = if (ui.linkProc.isNotEmpty()) ui.linkProc to ui.linkStep else null)
        }
    }
}

@Composable
private fun ReviewQueue(ui: Ui) {
    val rev = Changes.rev
    val list = remember(rev) { call("GET", "/native/review").json.optJSONArray("tags").objects() }
    Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
        Text("Readings to check", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(vertical = 12.dp))
        if (list.isEmpty()) Dim("Nothing to check: every reading was confirmed or rejected.")
        LazyColumn {
            items(list) { t ->
                val read = t.optJSONArray("read")
                ListItem(headlineContent = { Text(t.str("suggestion").ifEmpty { "${read?.optString(0)} / ${read?.optString(1)}" }) },
                    supportingContent = { Text("${t.str("sheet_name")} · confidence ${(t.optDouble("conf") * 100).toInt()} %") },
                    modifier = Modifier.clickable { ui.show(t.getString("id")) })
            }
        }
    }
}

/** sent from the Drawings and Procedures screens (R7) */
fun linkSubmit(proc: String, step: Int, kks: String, on: Boolean) =
    submit("link", JSONObject().put("proc", proc).put("step", step).put("kks", kks).put("on", on))


/** R6: propose a tag the reader missed; the code is optional (without one it goes to the review queue) */
@Composable
private fun MarkDialog(sheet: SheetInfo, b: List<Float>, view: SheetView?, snack: SnackbarHostState, onDone: (Boolean) -> Unit) {
    HoldLinks()           // (a link waits: it would close this with what is typed or picked)
    val scope = rememberCoroutineScope()
    var code by rememberSaveable { mutableStateOf("") }
    var isa by rememberSaveable { mutableStateOf("") }
    var note by rememberSaveable { mutableStateOf("") }
    val crop = remember(b) { view?.crop(b[0], b[1], b[2], b[3], 500)?.asImageBitmap() }
    // what was typed is not dropped by Back or Cancel without asking (#366, D3); a tap outside does nothing
    var discarding by remember { mutableStateOf(false) }
    val leave = { if (code.isBlank() && isa.isBlank() && note.isBlank()) onDone(false) else discarding = true }
    if (discarding) Confirm("Discard the typed code?", "What you typed for this mark is not sent.", "Discard", { onDone(false) },
        { discarding = false }, no = "Keep editing")
    AlertDialog(onDismissRequest = leave, properties = androidx.compose.ui.window.DialogProperties(dismissOnClickOutside = false),
        title = { Text("Mark a missing tag") }, text = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (crop != null) androidx.compose.foundation.Image(crop, "The marked part of the drawing", Modifier.fillMaxWidth())
            Dim("Type the code if you can read it. If not, leave it empty: the mark goes to the review queue.")
            OutlinedTextField(code, { code = it }, label = { Text("KKS (with suffix, optional)") }, singleLine = true)
            OutlinedTextField(isa, { isa = it }, label = { Text("Function letters (instruments, optional)") }, singleLine = true)
            OutlinedTextField(note, { note = it }, label = { Text("Note (optional)") }, singleLine = true)
        }
    }, confirmButton = { TextButton(onClick = {
        fun r(v: Float) = JSONObject.wrap(Math.round(v * sheet.scale * 10) / 10.0)
        val bb = JSONArray().put(r(b[0])).put(r(b[1])).put(r(b[2])).put(r(b[3]))
        val k = code.trim().uppercase()
        val (ok, m) = submit("tag_add", JSONObject().put("sheet", sheet.id).put("bbox", bb).put("kks", k).put("isa", isa.trim().uppercase()).put("note", note.trim()))
        scope.launch { snack.showSnackbar(m) }
        onDone(ok)
    }) { Text("Propose") } }, dismissButton = { TextButton(onClick = leave) { Text("Cancel") } })
}

/** decision 0044: a newer Walkdown is out; one tap downloads, checks and hands it to Android's installer */
@Composable
fun UpdateBanner() {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    if (!Updates.available(ctx)) return
    Card(Modifier.fillMaxWidth().padding(8.dp), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(Updates.busy ?: Updates.error ?: "Walkdown ${Updates.latest?.version} is out.", Modifier.weight(1f))
            if (Updates.busy == null) TextButton(onClick = { scope.launch(Dispatchers.IO) { Updates.install(ctx.applicationContext) } }) { Text("Install") }
        }
    }
}

/** what the photo coverage colours mean (shown while they are on) */
@Composable
private fun CoverageLegend() {
    Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp).semantics(mergeDescendants = true) {},
        horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
        for ((k, lab) in listOf("both" to "Both", "equipment" to "Equipment", "plate" to "Tag plate", "none" to "None")) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(12.dp).background(androidx.compose.ui.graphics.Color(coverColor(k))))
                Spacer(Modifier.width(4.dp)); Text(lab, style = MaterialTheme.typography.labelMedium)
            }
        }
    }
}

/** The Dark drawings setting, the same three choices with the same words in every app: the drawings follow the
 *  system's theme, or are always dark, or always light. */
internal const val DARK_MODE_PREF = "dark_drawings_mode"
internal val DARK_MODES = listOf("follow" to "Follow theme", "dark" to "Always dark", "light" to "Always light")
internal fun darkModeLabel(mode: String) = DARK_MODES.firstOrNull { it.first == mode }?.second ?: DARK_MODES[0].second
internal fun darkNow(mode: String, systemDark: Boolean) = mode == "dark" || (mode != "light" && systemDark)
/** the stored choice; before it had three, a switch (`dark_drawings`: true = on, which stays "always dark"; false =
 *  turned off by the person, which stays "always light"; never touched stored nothing and follows the theme) */
internal fun storedDarkMode(p: android.content.SharedPreferences): String {
    val m = p.getString(DARK_MODE_PREF, null)
    return when {
        m != null && DARK_MODES.any { it.first == m } -> m
        !p.contains("dark_drawings") -> "follow"
        p.getBoolean("dark_drawings", false) -> "dark"
        else -> "light"
    }
}

@Composable
private fun DarkDrawingsDialog(mode: String, onPick: (String) -> Unit, onClose: () -> Unit) {
    AlertDialog(onDismissRequest = onClose, title = { Text("Dark drawings") },
        text = {
            // scrolls: at the largest text size on its side the three choices are taller than the screen (#401's
            // UI/UX audit, pass 2)
            Column(Modifier.verticalScroll(rememberScrollState())) {
                Text("Light lines on dark paper, like a PDF reader's dark mode. Remembered on this device.", style = MaterialTheme.typography.bodyMedium)
                Spacer(Modifier.height(8.dp))
                Column(Modifier.selectableGroup()) {
                    for ((m, label) in DARK_MODES) Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .selectable(selected = m == mode, role = androidx.compose.ui.semantics.Role.RadioButton, onClick = { onPick(m) }),
                        verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(selected = m == mode, onClick = null)
                        Spacer(Modifier.width(12.dp))
                        Text(label, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
        },
        confirmButton = { TextButton(onClick = onClose) { Text("Done") } })
}
