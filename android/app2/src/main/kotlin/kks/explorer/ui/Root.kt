package kks.explorer.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalContext
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
    val scheme = if (androidx.compose.foundation.isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()
    val ctx = LocalContext.current
    DisposableEffect(Unit) {
        val l: (String) -> Unit = { Changes.rev++ }
        Core.listeners.add(l)
        Sync.start(ctx.applicationContext)
        onDispose { Core.listeners.remove(l) }
    }
    MaterialTheme(colorScheme = scheme) {
        Surface(Modifier.fillMaxSize()) {
            var joined by remember { mutableStateOf(Sync.joined()) }
            if (joined) MainScreen() else SetupScreen { joined = true }
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

/** what the screens share: the open sheet and tag, the active procedure, link mode (R7) */
class Ui {
    var tab by mutableStateOf("drawings")
    var sheet by mutableStateOf("")
    var selected by mutableStateOf("")
    var coverage by mutableStateOf(false)                  // the drawings coloured by photos
    var dark by mutableStateOf(false)                      // dark drawings (remembered on this device: prefs "app")
    var focus by mutableStateOf<List<Float>?>(null)       // a tag to zoom to once its sheet is shown
    var activeProc by mutableStateOf("")
    var linkProc by mutableStateOf("")
    var linkStep by mutableIntStateOf(0)
    var floor by mutableStateOf("")
    var focusSeq by mutableIntStateOf(0)
    var fullView by mutableStateOf(false)                 // the drawing alone: no header, no search (more room)
    var focusCy by mutableFloatStateOf(0.22f)              // where the focus lands (a fraction of the height)
    var arrived by mutableStateOf<Triple<String, Float, Float>?>(null)   // the connector followed to: sheet, x0, y0

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
    val ui = remember { Ui().also { it.dark = ctx.getSharedPreferences("app", android.content.Context.MODE_PRIVATE).getBoolean("dark_drawings", false) } }
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
    var query by remember { mutableStateOf("") }
    var drawer by remember { mutableStateOf(false) }
    var floorMenu by remember { mutableStateOf(false) }
    var notesOpen by remember { mutableStateOf(false) }
    var systemsOpen by remember { mutableStateOf(false) }
    var view by remember { mutableStateOf<SheetView?>(null) }
    val current = list.firstOrNull { it.id == ui.sheet }
    val boxes = remember(ui.sheet, rev) { if (current != null) tagBoxes(current.id, current.scale) else emptyList() }
    var marking by remember { mutableStateOf(false) }
    var marked by remember { mutableStateOf<List<Float>?>(null) }
    LaunchedEffect(marking, view) { view?.marking = marking }
    // selecting tags: one photo, place or note for several codes (Select.kt)
    var selecting by remember { mutableStateOf(false) }
    var selection by remember { mutableStateOf<Set<String>>(emptySet()) }     // tag ids, on this sheet
    var multi by remember { mutableStateOf("") }                              // the open dialog: list, photo, place, note
    LaunchedEffect(ui.sheet) { selection = emptySet(); multi = "" }
    LaunchedEffect(selecting, view) { view?.selecting = selecting }
    LaunchedEffect(selection, view) { view?.selection = selection }
    val selectedTags = boxes.filter { it.id in selection }
    val selectedCodes = selectedTags.map { it.code }.distinct()
    val floors = remember(rev) { call("GET", "/native/floors").json }
    val linkedCodes = remember(ui.activeProc, rev) {
        if (ui.activeProc.isEmpty()) emptySet() else call("GET", "/native/proc", query = mapOf("id" to ui.activeProc)).json.optJSONArray("links").objects().map { it.getString("kks") }.toSet()
    }
    BackHandler(enabled = ui.selected.isNotEmpty() || drawer || ui.linkProc.isNotEmpty() || selecting) {
        when { drawer -> drawer = false; ui.selected.isNotEmpty() -> ui.selected = ""; selecting -> { selecting = false; selection = emptySet() }; else -> ui.linkProc = "" }
    }
    LaunchedEffect(ui.sheet, view) {
        val v = view ?: return@LaunchedEffect
        if (current != null) v.setSheet(current.id, current.scale, current.levels)
    }
    LaunchedEffect(boxes, view) { view?.tags = boxes }
    // the connectors (Links.kt): circles on the drawing, "Connectors on this sheet", a choice when there are several
    val links = remember(ui.sheet, rev) { if (current != null) linksOf(current.id) else emptyList() }
    val linkBoxes = remember(links) { links.map(::linkBox) }
    var connectorsOpen by remember { mutableStateOf(false) }
    var ask by remember { mutableStateOf<Follow.Ask?>(null) }
    LaunchedEffect(linkBoxes, ui.arrived, view) {
        val v = view ?: return@LaunchedEffect
        v.links = linkBoxes
        v.linkSel = ui.arrived?.takeIf { it.first == ui.sheet }?.let { a ->
            linkBoxes.indexOfFirst { Math.abs(it.x0 - a.second) < 0.01f && Math.abs(it.y0 - a.third) < 0.01f } } ?: -1
    }
    val say: (String) -> Unit = { m -> scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar(m) } }
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
    LaunchedEffect(ui.dark, view) { view?.dark = ui.dark }
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
                    DropdownMenuItem(text = { Text("Equipment by system") }, onClick = { systemsOpen = true; floorMenu = false })
                    if (current != null) DropdownMenuItem(text = { Text("Colour tags by photos" + if (ui.coverage) " ✓" else "") },
                        onClick = { ui.coverage = !ui.coverage; floorMenu = false })
                    // checkable: TalkBack says "Dark drawings, checkbox, checked"; the switch is instant (SheetView.dark)
                    if (current != null) DropdownMenuItem(text = { Text("Dark drawings") },
                        trailingIcon = { Checkbox(ui.dark, onCheckedChange = null, modifier = Modifier.clearAndSetSemantics {}) },
                        modifier = Modifier.semantics { role = androidx.compose.ui.semantics.Role.Checkbox
                            toggleableState = androidx.compose.ui.state.ToggleableState(ui.dark) },
                        onClick = {
                            ui.dark = !ui.dark; floorMenu = false
                            ctx.getSharedPreferences("app", android.content.Context.MODE_PRIVATE).edit().putBoolean("dark_drawings", ui.dark).apply()
                        })
                    if (current != null) DropdownMenuItem(text = { Text(if (marking) "Stop marking" else "Mark a missing tag") },
                        onClick = { marking = !marking; selecting = false; ui.selected = ""; floorMenu = false })
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
        if (systemsOpen) SystemsScreen(ui) { systemsOpen = false }
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
                    if (t == null || t.code.isEmpty()) scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar("This tag has no code yet: it can't be selected") }
                    else if (id in selection) selection = selection - id
                    else {
                        val (next, full) = addCapped(selection, listOf(id)) { i -> boxes.firstOrNull { it.id == i }?.code.orEmpty() }
                        selection = next
                        if (full) scope.launch { snack.currentSnackbarData?.dismiss(); snack.showSnackbar("At most $MAX_PICK tags at once: send these first") }
                    }
                }
                v.onBox = { ids ->
                    val hit = boxes.filter { it.id in ids }
                    val ok = hit.filter { it.code.isNotEmpty() }.map { it.id }
                    val (next, full) = addCapped(selection, ok) { i -> boxes.firstOrNull { it.id == i }?.code.orEmpty() }
                    selection = next
                    if (full) scope.launch { snack.showSnackbar("At most $MAX_PICK tags at once: send these first") }
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
                    } else ui.selected = id
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
            Column(Modifier.fillMaxWidth().padding(8.dp)) {
                if (marking) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Row(Modifier.padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Drag a box around the tag the app missed (two fingers move the drawing)", Modifier.weight(1f))
                        TextButton(onClick = { marking = false }) { Text("Cancel") }
                    }
                }
                if (selecting) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Text("Tap tags to select them. Hold, then drag, to add every tag in a box (one finger still moves the drawing).",
                        Modifier.padding(horizontal = 16.dp, vertical = 10.dp))
                }
                if (ui.linkProc.isNotEmpty()) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.tertiaryContainer)) {
                    Row(Modifier.padding(start = 16.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text("Tap tags to link them to step ${ui.linkStep} of ${ui.linkProc}", Modifier.weight(1f))
                        TextButton(onClick = { ui.tab = "procedures"; ui.linkProc = "" }) { Text("Done") }
                    }
                }
                if (!ui.fullView) OutlinedTextField(query, { query = it }, placeholder = { Text("Search KKS or description") }, singleLine = true,
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Search equipment by KKS code or description" },
                    colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = MaterialTheme.colorScheme.surface, unfocusedContainerColor = MaterialTheme.colorScheme.surface))
                if (!ui.fullView && query.trim().length >= 2) {
                    val res = remember(query, rev) { call("GET", "/native/search", query = mapOf("q" to query.trim())).json.optJSONArray("results").objects() }
                    Surface(tonalElevation = 3.dp, modifier = Modifier.fillMaxWidth().heightIn(max = 320.dp)) {
                        if (res.isEmpty()) Text("Nothing found", Modifier.padding(16.dp))
                        LazyColumn {
                            items(res) { r ->
                                ListItem(headlineContent = { Text(r.getString("code").ifEmpty { "(unread)" }) },
                                    supportingContent = { Text(r.getString("kind") + " · " + r.getString("sheet_name")) },
                                    modifier = Modifier.clickable { query = ""; ui.show(r.getString("id")) })
                            }
                        }
                    }
                }
            }
            if (drawer) Surface(tonalElevation = 6.dp, modifier = Modifier.fillMaxHeight().width(300.dp).align(Alignment.CenterStart)) {
                LazyColumn {
                    item { Text("Sheets", style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(16.dp)) }
                    items(list) { s ->
                        ListItem(headlineContent = { Text(s.name) }, supportingContent = { Text("${s.tags} tags" + if (s.review > 0) ", ${s.review} to review" else "") },
                            modifier = Modifier.clickable { ui.sheet = s.id; ui.selected = ""; drawer = false })
                    }
                }
            }
            if (selecting) SelectBar(selection.size, Modifier.align(Alignment.BottomCenter),
                onList = { multi = "list" }, onPhoto = {
                    val ids = selectedTags.map { it.id }
                    scope.launch {
                        val missing = withContext(Dispatchers.IO) { codesWithoutFloor(ids) }
                        if (missing.isEmpty()) multi = "photo"
                        else snack.showSnackbar("A photo needs each code's floor. No floor yet: " + missing.take(5).joinToString(", ") +
                            (if (missing.size > 5) " and ${missing.size - 5} more" else "") + ". Set it with Place for all first.")
                    }
                }, onPlace = { multi = "place" }, onNote = { multi = "note" },
                onDone = { selecting = false; selection = emptySet() })
            val sent: (String) -> Unit = { m ->
                if (m.startsWith("Sent for")) { selecting = false; selection = emptySet() }
                scope.launch { snack.showSnackbar(m) }
            }
            when (multi) {
                "list" -> SelectList(selectedTags, onUntick = { selection = selection - it }, onClose = { multi = "" })
                "photo" -> PhotoForAll(selectedCodes, sent) { multi = "" }
                "place" -> PlaceForAll(selectedTags.map { it.id }, selectedCodes, sent) { multi = "" }
                "note" -> NoteForAll(selectedCodes, sent) { multi = "" }
            }
            marked?.let { b ->
                MarkDialog(current!!, b, view, snack, onDone = { ok -> marked = null; if (ok) marking = false })
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
    val scope = rememberCoroutineScope()
    var code by remember { mutableStateOf("") }
    var isa by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    val crop = remember(b) { view?.crop(b[0], b[1], b[2], b[3], 500)?.asImageBitmap() }
    AlertDialog(onDismissRequest = { onDone(false) }, title = { Text("Mark a missing tag") }, text = {
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
    }) { Text("Propose") } }, dismissButton = { TextButton(onClick = { onDone(false) }) { Text("Cancel") } })
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
