package kks.explorer.ui

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import kks.explorer.Qr
import kks.explorer.sync.Sync
import kks.explorer.sync.SyncWorker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

/** R10–R14 (admin.html, the GNOME app's Manage): approvals, proposals, history, people, devices, account */
@Composable
fun Manage(snack: SnackbarHostState) {
    var page by remember { mutableStateOf("") }
    BackHandler(enabled = page.isNotEmpty()) { page = "" }
    val rev = Changes.rev
    val cfg = remember(rev) { Sync.config() }
    val admin = cfg.optBoolean("admin")
    val say: (String) -> Unit = { m -> Changes.rev++; kotlinx.coroutines.MainScope().launch { snack.showSnackbar(m) } }
    Column(Modifier.fillMaxSize()) {
        if (page.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { page = "" }) { Text("‹ Manage") }
        }
        Box(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            when (page) {
                "" -> Column {
                    Text("Manage", style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(vertical = 12.dp))
                    val pages = buildList {
                        if (admin) add(Triple("approvals", "Approvals", "Proposals waiting for a decision"))
                        add(Triple("mine", "My proposals", "What you proposed, and photos to vote on"))
                        if (admin) { add(Triple("history", "History", "Every change, with revert and restore")); add(Triple("people", "People", "Accounts and roles")) }
                        add(Triple("devices", "Devices", "Your devices" + if (admin) ", all devices, joining" else ""))
                        add(Triple("account", "Account", "Your details, sync"))
                    }
                    for ((id, title, sub) in pages) ListItem(headlineContent = { Text(title) }, supportingContent = { Text(sub) },
                        modifier = Modifier.fillMaxWidth().clickable { page = id })
                }
                "approvals" -> Approvals(rev, admin, say)
                "mine" -> MyProposals(rev, say)
                "history" -> History(rev, say)
                "people" -> People(rev, say)
                "devices" -> Devices(rev, admin, say)
                "account" -> Account(rev, say)
            }
        }
    }
}

private fun act(id: Long, action: String, body: JSONObject, done: String, say: (String) -> Unit) {
    val r = call("POST", "/api/submissions/$id/$action", body)
    say(r.error ?: done)
}

@Composable
private fun Approvals(rev: Int, admin: Boolean, say: (String) -> Unit) {
    val r = remember(rev) { call("GET", "/api/submissions", query = mapOf("status" to "open")) }
    if (!r.ok) { Dim(r.error!!); return }
    val open = r.json.optJSONArray("submissions").objects()
    if (open.isEmpty()) { Dim("Nothing waits for approval."); return }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items(open) { sub ->
            val id = sub.optLong("id")
            val conflict = sub.str("status") == "conflict"
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(sub.str("kind") + " · " + sub.str("target"), style = MaterialTheme.typography.titleSmall)
                    Dim("by " + sub.str("by_name") + " · " + whenText(sub.optLong("created")) +
                        sub.str("request_note").let { if (it.isNotEmpty()) " · note: $it" else "" })
                    SelectionContainer { Text(summary(sub.optJSONObject("payload"))) }
                    if (conflict) Text("Held: it clashes with the current value or another proposal. " + sub.str("note"), color = MaterialTheme.colorScheme.error)
                    sub.optJSONArray("live").objects().forEach { lv -> Dim("Now: " + lv.str("entity") + " " + lv.opt("key") + ": " + lv.opt("value")) }
                    if (sub.str("kind") == "photo") PhotoOf(sub.optJSONObject("payload")?.str("file").orEmpty())
                    if (admin) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { act(id, "approve", JSONObject().put("force", conflict), "Approved", say) }) { Text(if (conflict) "Approve anyway" else "Approve") }
                        if (sub.str("kind") == "photo") OutlinedButton(onClick = { act(id, "pick", JSONObject(), "Photo chosen, others rejected", say) }) { Text("Pick") }
                        OutlinedButton(onClick = { act(id, "reject", JSONObject(), "Rejected", say) }) { Text("Reject") }
                    }
                }
            }
        }
    }
}

@Composable
private fun MyProposals(rev: Int, say: (String) -> Unit) {
    val r = remember(rev) { call("GET", "/api/submissions", query = mapOf("status" to "all", "limit" to "200")) }
    if (!r.ok) { Dim(r.error!!); return }
    val subs = r.json.optJSONArray("submissions").objects()
    val mine = subs.filter { it.optBoolean("mine") }
    val photos = subs.filter { !it.optBoolean("mine") && it.str("kind") == "photo" && it.str("status") in setOf("pending", "conflict") }
    var withdraw by remember { mutableStateOf<Long?>(null) }
    withdraw?.let { id -> Confirm("Withdraw this proposal?", "", "Withdraw", { act(id, "withdraw", JSONObject(), "Withdrawn", say) }, { withdraw = null }) }
    LazyColumn(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (mine.isEmpty()) item { Dim("You have proposed nothing yet.") }
        items(mine) { sub ->
            Card(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(sub.str("kind") + " · " + sub.str("target"), style = MaterialTheme.typography.titleSmall)
                    Dim(sub.str("status") + " · " + whenText(sub.optLong("created")) + sub.str("note").let { if (it.isNotEmpty()) " · $it" else "" })
                    Text(summary(sub.optJSONObject("payload")))
                    if (sub.str("status") in setOf("pending", "conflict")) OutlinedButton(onClick = { withdraw = sub.optLong("id") }) { Text("Withdraw") }
                }
            }
        }
        if (photos.isNotEmpty()) item { Section("Photos waiting for approval", "Vote for the ones you find useful; an admin decides.") {} }
        items(photos) { sub ->
            ListItem(headlineContent = { Text(sub.str("target") + " · by " + sub.str("by_name")) },
                supportingContent = { Text("${sub.optInt("votes")} votes" + if (sub.optBoolean("voted")) " (yours)" else "") },
                trailingContent = { TextButton(onClick = { act(sub.optLong("id"), "vote", JSONObject(), "Vote changed", say) }) { Text(if (sub.optBoolean("voted")) "Unvote" else "Vote") } })
        }
    }
}

@Composable
private fun History(rev: Int, say: (String) -> Unit) {
    val r = remember(rev) { call("GET", "/api/revisions", query = mapOf("limit" to "200")) }
    if (!r.ok) { Dim(r.error!!); return }
    val revs = r.json.optJSONArray("revisions").objects()
    var ask by remember { mutableStateOf<Pair<String, Any>?>(null) }
    ask?.let { (what, hid) ->
        if (what == "revert") Confirm("Revert this change?", "This writes a new change that undoes it; History keeps both.", "Revert", {
            val res = call("POST", "/api/revisions/$hid/revert", JSONObject()); say(res.error ?: "Reverted")
        }, { ask = null })
        else Confirm("Restore to just after this change?", "Every later change is undone by new changes.", "Restore", {
            val res = call("POST", "/api/restore", JSONObject().put("hid", hid)); say(res.error ?: "Restored")
        }, { ask = null })
    }
    LazyColumn {
        item { Dim("Newest first. Revert undoes one change; Restore goes back to the state just after a change.") }
        if (revs.isEmpty()) item { Dim("No changes yet.") }
        items(revs) { x ->
            val hid = x.opt("hid")
            ListItem(headlineContent = { Text(("#" + x.str("n") + " " + x.str("summary") + x.str("note")).trim()) },
                supportingContent = { Text(x.str("by_name") + " · " + whenText(x.optLong("at")) + x.str("entity").let { if (it.isNotEmpty()) " · $it " + x.str("key") else "" }) },
                trailingContent = {
                    if (hid != null && hid != JSONObject.NULL) Row {
                        TextButton(onClick = { ask = "revert" to hid }) { Text("Revert") }
                        TextButton(onClick = { ask = "restore" to hid }) { Text("Restore") }
                    }
                })
        }
    }
}

@Composable
private fun People(rev: Int, say: (String) -> Unit) {
    val r = remember(rev) { call("GET", "/api/users") }
    var un by remember { mutableStateOf("") }
    var fn by remember { mutableStateOf("") }
    var pos by remember { mutableStateOf("") }
    Column(Modifier.verticalScroll(rememberScrollState())) {
        if (!r.ok) Dim(r.error!!)
        Section("People", "Everyone who has an identity in this plant. Devices are added under Devices.") {
            for (u in r.json.optJSONArray("users").objects())
                ListItem(headlineContent = { Text(u.str("full_name") + " (" + u.str("username") + ")") },
                    supportingContent = { Text(u.str("role") + u.str("position").let { if (it.isNotEmpty()) " · $it" else "" }) })
        }
        Section("Add a person", "For someone whose device will join later (by QR code, request file or nearby admin).") {
            OutlinedTextField(un, { un = it }, label = { Text("Username") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(fn, { fn = it }, label = { Text("Full name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(pos, { pos = it }, label = { Text("Position (optional)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Button(onClick = {
                val res = call("POST", "/api/users", JSONObject().put("username", un.trim().lowercase()).put("full_name", fn.trim()).put("position", pos.trim()).put("role", "user"))
                if (res.ok) { say("Added ${un.trim()}"); un = ""; fn = ""; pos = "" } else say(res.error!!)
            }) { Text("Add") }
        }
    }
}

@Composable
private fun Devices(rev: Int, admin: Boolean, say: (String) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val r = remember(rev) { call("GET", "/api/devices") }
    var poll by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(3000); poll++ } }      // join requests arrive without a log change
    val reqs = remember(rev, poll) { if (admin) call("GET", "/api/join-requests").json.optJSONArray("requests").objects() else emptyList() }
    var remove by remember { mutableStateOf<JSONObject?>(null) }
    var invite by remember { mutableStateOf(false) }
    remove?.let { d -> Confirm("Remove this device?", "It stops receiving data, and wipes the plant from itself if it ever connects again.", "Remove", {
        val res = call("POST", "/api/devices/revoke", JSONObject().put("device", d.str("device"))); say(res.error ?: "Removed")
    }, { remove = null }) }
    if (invite) { InviteDialog(say) { invite = false } }
    val openReq = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        val req = runCatching { JSONObject(ctx.contentResolver.openInputStream(uri)!!.use { it.readBytes() }.toString(Charsets.UTF_8)) }.getOrNull()
        if (req == null) { say("That is not a join request"); return@rememberLauncherForActivityResult }
        val res = call("POST", "/api/devices/import-request", JSONObject().put("request", req).put("existing_ok", true))
        say(res.error ?: "The device is certified; it joins with its next sync (or send it a bundle).")
    }
    val saveBundle = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/gzip")) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val msg = withContext(Dispatchers.IO) {
                val a = kks.explorer.core.Core.api("GET", "/api/bundle")
                if (a.status >= 400 || a.bytes == null) a.json.optString("error", "could not make a bundle")
                else { ctx.contentResolver.openOutputStream(uri)?.use { it.write(a.bytes) }; "Saved. The bundle holds the plant's data unencrypted: hand it over directly." }
            }
            say(msg)
        }
    }
    @Composable fun rows(list: List<JSONObject>) = list.forEach { x ->
        val dev = x.str("device")
        ListItem(headlineContent = { Text(x.str("label").ifEmpty { "device" } + " · " + x.str("username") + if (x.optBoolean("this_computer")) " (this phone)" else "") },
            supportingContent = { Text(dev.take(16) + "…" + if (x.optBoolean("revoked")) " · removed" else "") },
            trailingContent = { if (!x.optBoolean("revoked") && !x.optBoolean("this_computer")) TextButton(onClick = { remove = x }) { Text("Remove") } })
    }
    Column(Modifier.verticalScroll(rememberScrollState())) {
        if (!r.ok) Dim(r.error!!)
        Section("Your devices") { rows(r.json.optJSONArray("mine").objects()) }
        if (admin) {
            Section("All devices") { rows(r.json.optJSONArray("all").objects()) }
            if (reqs.isNotEmpty()) Section("Waiting to join", "Accept only if the code on the other device is the same.") {
                for (x in reqs) {
                    val q = x.optJSONObject("request") ?: JSONObject()
                    ListItem(headlineContent = { Text(q.str("full_name") + " (" + q.str("username") + ") · " + q.str("label")) },
                        supportingContent = { Text("code " + x.str("code"), fontFamily = FontFamily.Monospace) },
                        trailingContent = { Row {
                            for ((lab, a) in listOf("Accept" to "accept", "Refuse" to "refuse")) TextButton(onClick = {
                                val res = call("POST", "/api/join-requests/" + x.str("device"), JSONObject().put("action", a).put("existing_ok", true))
                                say(res.error ?: if (a == "accept") "Accepted" else "Refused")
                            }) { Text(lab) }
                        } })
                }
            }
            Section("Add a device with a QR code", "The new device scans it, or you copy its text over.") {
                Button(onClick = { invite = true }) { Text("Show an invite") }
            }
            Section("Add a device from a request file", "Someone made a join request (.kksjoin) on their device and sent it to you.") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { openReq.launch(arrayOf("*/*")) }) { Text("Open a join request…") }
                    OutlinedButton(onClick = { saveBundle.launch("plant.kksbundle") }) { Text("Save a bundle…") }
                }
            }
        }
    }
}

/** an invite as a QR code + text; the admin accepts the device that uses it (§16) */
@Composable
private fun InviteDialog(say: (String) -> Unit, onClose: () -> Unit) {
    val clip = LocalClipboardManager.current
    val made = remember { call("POST", "/api/invites", JSONObject()) }
    if (!made.ok) { LaunchedEffect(Unit) { say(made.error!!); onClose() }; return }
    val code = made.json.str("code")
    val token = made.json.optJSONObject("invite")?.str("token").orEmpty()
    val qr = remember(code) { Qr.bitmap(code, 6) }
    var state by remember { mutableStateOf<JSONObject?>(null) }
    var decided by remember { mutableStateOf("") }
    LaunchedEffect(token) {
        while (decided.isEmpty()) {
            val s = withContext(Dispatchers.IO) { call("GET", "/api/invites/$token") }
            if (!s.ok) break
            state = s.json
            if (s.json.str("state") in setOf("accepted", "refused", "expired")) break
            delay(2000)
        }
    }
    fun send(action: String) {
        val res = call("POST", "/api/invites/$token", JSONObject().put("action", action).put("existing_ok", true))
        decided = res.error ?: if (action == "accept") "Accepted: the device syncs now." else "Refused."
    }
    AlertDialog(onDismissRequest = {
        if (state?.str("state") !in setOf("accepted", "refused")) call("POST", "/api/invites/$token", JSONObject().put("action", "cancel"))
        onClose()
    }, title = { Text("Add a device") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (qr != null) Image(qr.asImageBitmap(), "QR code of the invite", Modifier.fillMaxWidth().aspectRatio(1f), filterQuality = FilterQuality.None)
            Dim("Scan this with the new phone, or copy the text to the new computer (Join with a code). Valid for 15 minutes, for one device.")
            SelectionContainer { Text(code, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall) }
            TextButton(onClick = { clip.setText(AnnotatedString(code)); say("Copied") }) { Text("Copy the text") }
            val st = state
            when {
                decided.isNotEmpty() -> Text(decided)
                st?.str("state") == "asked" -> {
                    val q = st.optJSONObject("request") ?: JSONObject()
                    Text("A device asks to join: ${q.str("full_name")} (${q.str("username")}), ${q.str("label")}" +
                        if (st.opt("existing") != null && st.opt("existing") != JSONObject.NULL) ". That username exists: it becomes their new device." else "")
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { send("accept") }) { Text("Accept") }
                        OutlinedButton(onClick = { send("refuse") }) { Text("Refuse") }
                    }
                }
                st?.str("state") == "expired" -> Text("Expired. Close this and make a new one.")
                else -> Text("Waiting for a device…")
            }
        }
    }, confirmButton = { TextButton(onClick = onClose) { Text("Close") } })
}

@Composable
private fun Account(rev: Int, say: (String) -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val me = remember(rev) { call("GET", "/api/me").json.optJSONObject("user") ?: JSONObject() }
    var fn by remember(me.str("full_name")) { mutableStateOf(me.str("full_name")) }
    var pos by remember(me.str("position")) { mutableStateOf(me.str("position")) }
    var addr by remember { mutableStateOf("") }
    var metered by remember { mutableStateOf(SyncWorker.metered(ctx)) }
    var relay by remember(rev) { mutableStateOf(Sync.config().optString("relay_url")) }
    var tick by remember { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { while (true) { delay(5000); tick++ } }
    Column(Modifier.verticalScroll(rememberScrollState())) {
        Section("Your details") {
            Text("${me.str("username")} · ${me.str("role")}")
            OutlinedTextField(fn, { fn = it }, label = { Text("Full name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(pos, { pos = it }, label = { Text("Position") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Button(onClick = { val r = call("POST", "/api/profile", JSONObject().put("full_name", fn.trim()).put("position", pos.trim())); say(r.error ?: "Saved") }) { Text("Save") }
        }
        Section("Sync", "Devices on the same Wi-Fi find each other; others can be reached by address.") {
            key(tick) {
                val last = Sync.peers.values.maxOfOrNull { it.lastOk } ?: 0L
                Text("This phone: ${Sync.device().take(16)}… · sync port ${if (Sync.port > 0) Sync.port else "off"}")
                Dim(if (Sync.syncing) "Syncing…" else if (last > 0) "Last sync ${whenText(last / 1000)}" else "Not synced yet")
                val st = kks.explorer.sync.Internet.state
                val on = kks.explorer.sync.Internet.online.size
                if (st != "off") Dim(if (st == "online") "Internet: on the relay, $on other device${if (on == 1) "" else "s"} online" else "Internet: $st")
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Sync on metered networks (mobile data)", Modifier.weight(1f))
                Switch(metered, { metered = it; SyncWorker.setMetered(ctx, it) })
            }
            if (me.str("role") == "manager") {
                // §18: the plant's relay, a setting every device learns at its next sync (the manager only)
                OutlinedTextField(relay, { relay = it }, label = { Text("Internet relay (wss://…), empty = off") }, singleLine = true, modifier = Modifier.fillMaxWidth())
                Button(onClick = {
                    val r = call("POST", "/api/settings/relay", JSONObject().put("url", relay.trim()))
                    if (r.error == null) kks.explorer.sync.Internet.restart()
                    say(r.error ?: if (relay.isBlank()) "Relay removed" else "Relay saved: every device learns it at its next sync")
                }) { Text("Save relay") }
            }
            OutlinedTextField(addr, { addr = it }, label = { Text("Sync with an address (host:port@device)") }, singleLine = true, modifier = Modifier.fillMaxWidth())
            Button(onClick = {
                val t = addr.trim()
                scope.launch {
                    val msg = withContext(Dispatchers.IO) {
                        if (t.isEmpty()) Sync.syncAll(ctx.applicationContext, wait = true).let { n -> if (n > 0) "Synced with $n device${if (n == 1) "" else "s"}" else "No other device reached" }
                        else {
                            val at = t.lastIndexOf('@'); val colon = t.lastIndexOf(':', maxOf(0, at))
                            if (at < 0 || colon < 0) "Write it as host:port@device"
                            else try {
                                kks.explorer.core.Net.syncWith(t.substring(0, colon), t.substring(colon + 1, at).toInt(), t.substring(at + 1))
                                Sync.remember(ctx, t.substring(0, colon), t.substring(colon + 1, at).toInt(), t.substring(at + 1)); "Synced"
                            } catch (e: Exception) { e.message ?: "failed" }
                        }
                    }
                    say(msg)
                }
            }) { Text("Sync now") }
        }
    }
}
