package kks.explorer.ui

import android.net.Uri
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import kks.explorer.App
import kks.explorer.sync.Discovery
import kks.explorer.sync.Migrate
import kks.explorer.sync.Sync
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** R13: the ways a phone joins a plant (no new plants on phones: the root key stays on a computer, PROTOCOL-v2 §10) */
@Composable
fun SetupScreen(onJoined: () -> Unit) {
    val ctx = LocalContext.current
    var page by remember { mutableStateOf("") }
    BackHandler(enabled = page.isNotEmpty()) { page = "" }
    Column(Modifier.safeDrawingPadding().padding(20.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("KKS Explorer", style = MaterialTheme.typography.headlineMedium)
        when (page) {
            "" -> {
                val removed = App.removedNote(ctx)
                if (removed.isNotEmpty()) Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.errorContainer)) {
                    Text("$removed Its plant data was deleted from this phone.", Modifier.padding(16.dp))
                }
                MoveFromOldApp(onJoined)
                Text("This phone does not belong to a plant yet.", style = MaterialTheme.typography.bodyLarge)
                for ((id, title, sub) in listOf(
                    Triple("server", "Join through a server", "Username and password on the plant's server"),
                    Triple("code", "Join with a code", "An admin shows a QR code; scan it or paste its text"),
                    Triple("nearby", "Ask an admin on this Wi-Fi", "Compare a 6-digit code with an admin nearby"),
                    Triple("file", "Join with a file", "A bundle an admin saved for you"))) {
                    ListItem(headlineContent = { Text(title) }, supportingContent = { Text(sub) },
                        modifier = Modifier.fillMaxWidth().clickable { page = id })
                }
            }
            "server" -> ServerJoin(onJoined)
            "code" -> CodeJoin(onJoined)
            "nearby" -> NearbyJoin(onJoined)
            "file" -> FileJoin(onJoined)
        }
        if (page.isNotEmpty()) TextButton(onClick = { page = "" }) { Text("Back") }
    }
}

/** decision 0042: the old app (its bridge release) is on this phone with a plant: move from it by itself, once, at the first start */
@Composable
private fun MoveFromOldApp(onJoined: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var old by remember { mutableStateOf<org.json.JSONObject?>(null) }
    var busy by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    var tries by remember { mutableStateOf(0) }
    LaunchedEffect(Unit) {
        old = withContext(Dispatchers.IO) { if (Migrate.oldAppPresent(ctx)) Migrate.info(ctx) else null }
    }
    val inf = old ?: return
    LaunchedEffect(tries) {
        busy = true
        val err = withContext(Dispatchers.IO) { Migrate.run(ctx.applicationContext) { s -> scope.launch { msg = s } } }
        busy = false
        if (err.isEmpty()) onJoined() else msg = err
    }
    Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.secondaryContainer)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Moving from the old app", style = MaterialTheme.typography.titleMedium)
            Text("${inf.optString("name").ifEmpty { "Your" }} account, plant ${inf.optString("plant")}: this phone joins by itself, " +
                 "and your changes that haven't reached the server yet come along.", style = MaterialTheme.typography.bodyMedium)
            if (busy) Row(verticalAlignment = androidx.compose.ui.Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp); Text(msg)
            } else if (msg.isNotEmpty()) {
                Text(msg, color = MaterialTheme.colorScheme.error)
                Button(onClick = { tries++ }) { Text("Try again") }
            }
        }
    }
}

@Composable
private fun ServerJoin(onJoined: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var url by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var pw by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf("") }
    Text("Join through the plant's server", style = MaterialTheme.typography.titleMedium)
    Dim("The server's name or IP, with its sync port if it isn't 8421.")
    OutlinedTextField(url, { url = it }, label = { Text("Server address") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri))
    OutlinedTextField(user, { user = it }, label = { Text("Username") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(pw, { pw = it }, label = { Text("Password") }, singleLine = true, modifier = Modifier.fillMaxWidth(),
        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password))
    Button(enabled = !busy, onClick = {
        busy = true; msg = "Joining…"
        scope.launch {
            val err = withContext(Dispatchers.IO) { Sync.joinServer(ctx.applicationContext, url.trim(), user.trim(), pw) }
            busy = false
            if (err.isEmpty()) onJoined() else msg = err
        }
    }) { Text("Join") }
    if (msg.isNotEmpty()) Text(msg)
}

/** asks until the admin decides; in the lobby the person confirms the code before the first sync (§16) */
@Composable
private fun JoinProgress(join: Sync.Join, needCode: Boolean, onJoined: () -> Unit, onGiveUp: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var status by remember(join) { mutableStateOf("Asking…") }
    var accepted by remember(join) { mutableStateOf(false) }
    var done by remember(join) { mutableStateOf(false) }
    var cancelled by remember(join) { mutableStateOf(false) }
    fun finish() {
        status = "Accepted. Syncing…"
        scope.launch {
            val err = withContext(Dispatchers.IO) { join.finish(ctx.applicationContext) }
            if (err.isEmpty()) onJoined() else status = err
        }
    }
    LaunchedEffect(join) {
        val ack = withContext(Dispatchers.IO) { join.await({ s -> scope.launch { status = s } }, { cancelled }) }
        done = true
        when (ack.optString("state")) {
            "accepted" -> if (needCode) { accepted = true; status = "Accepted. Does the admin's screen show ${withContext(Dispatchers.IO) { join.code }}?" } else finish()
            "cancelled" -> {}
            else -> status = "Not accepted: " + ack.optString("state") + ack.optString("why").let { if (it.isNotEmpty()) " ($it)" else "" }
        }
    }
    Text(status, style = MaterialTheme.typography.bodyLarge)
    if (accepted) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Button(onClick = { accepted = false; finish() }) { Text("Yes, the same code") }
        OutlinedButton(onClick = { accepted = false; status = "Not joined: the codes differ. Ask the admin to refuse the request."; }) { Text("No") }
    }
    if (!done) OutlinedButton(onClick = { cancelled = true; onGiveUp() }) { Text("Stop asking") }
}

@Composable
private fun NameFields(username: MutableState<String>, fullName: MutableState<String>) {
    OutlinedTextField(username.value, { username.value = it }, label = { Text("Your username") }, singleLine = true, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(fullName.value, { fullName.value = it }, label = { Text("Your full name") }, singleLine = true, modifier = Modifier.fillMaxWidth())
}

private fun namesOk(u: String, f: String) = u.trim().length >= 2 && f.trim().isNotEmpty()

@Composable
private fun CodeJoin(onJoined: () -> Unit) {
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf("") }
    val username = remember { mutableStateOf("") }
    val fullName = remember { mutableStateOf("") }
    var join by remember { mutableStateOf<Sync.Join?>(null) }
    var msg by remember { mutableStateOf("") }
    val scan = rememberLauncherForActivityResult(ScanQr.Contract()) { r -> if (r != null) text = r }
    Text("Join with a code", style = MaterialTheme.typography.titleMedium)
    Dim("An admin shows a QR code under Manage → Devices. Scan it, or paste its text.")
    val j = join
    if (j != null) { JoinProgress(j, needCode = false, onJoined = onJoined, onGiveUp = { join = null }); return }
    OutlinedButton(onClick = { scan.launch(Unit) }) { Text("Scan the QR code") }
    OutlinedTextField(text, { text = it }, label = { Text("Invite text") }, modifier = Modifier.fillMaxWidth(), minLines = 2)
    NameFields(username, fullName)
    Button(onClick = {
        val inv = Sync.parseInvite(text)
        when {
            inv == null -> msg = "That is not an invite. Copy the whole text the admin's device shows."
            !namesOk(username.value, fullName.value) -> msg = "Fill in a username (2+ characters) and your full name."
            else -> scope.launch {
                msg = ""
                join = withContext(Dispatchers.IO) { Sync.inviteJoin(inv, username.value.trim().lowercase(), fullName.value.trim()) }
            }
        }
    }) { Text("Join with this code") }
    if (msg.isNotEmpty()) Text(msg, color = MaterialTheme.colorScheme.error)
}

@Composable
private fun NearbyJoin(onJoined: () -> Unit) {
    val scope = rememberCoroutineScope()
    val username = remember { mutableStateOf("") }
    val fullName = remember { mutableStateOf("") }
    var found by remember { mutableStateOf(listOf<Discovery.Found>()) }
    var join by remember { mutableStateOf<Sync.Join?>(null) }
    var msg by remember { mutableStateOf("") }
    LaunchedEffect(Unit) { while (true) { found = withContext(Dispatchers.IO) { Sync.adminsNearby() }; delay(2000) } }
    Text("Ask an admin on this Wi-Fi", style = MaterialTheme.typography.titleMedium)
    Dim("Admins' devices nearby. You and the admin compare a 6-digit code.")
    val j = join
    if (j != null) { JoinProgress(j, needCode = true, onJoined = onJoined, onGiveUp = { join = null }); return }
    NameFields(username, fullName)
    if (found.isEmpty()) Dim("No admin's device found yet. The admin's device must be on the same Wi-Fi with KKS Explorer open.")
    for (f in found) ListItem(headlineContent = { Text("Ask ${f.label}") }, supportingContent = { Text("${f.plant} · ${f.host}") },
        modifier = Modifier.fillMaxWidth().clickable {
            if (!namesOk(username.value, fullName.value)) { msg = "Fill in a username (2+ characters) and your full name."; return@clickable }
            scope.launch { msg = ""; join = withContext(Dispatchers.IO) { Sync.lobbyJoin(f, username.value.trim().lowercase(), fullName.value.trim()) } }
        })
    if (msg.isNotEmpty()) Text(msg, color = MaterialTheme.colorScheme.error)
}

@Composable
private fun FileJoin(onJoined: () -> Unit) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var msg by remember { mutableStateOf("") }
    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        msg = "Reading the bundle…"
        scope.launch {
            val err = withContext(Dispatchers.IO) {
                val raw = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                if (raw == null) "Could not read that file" else Sync.importBundle(ctx.applicationContext, raw)
            }
            if (err.isEmpty()) onJoined() else msg = err
        }
    }
    val username = remember { mutableStateOf("") }
    val fullName = remember { mutableStateOf("") }
    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            msg = withContext(Dispatchers.IO) {
                val req = call("POST", "/native/join-request", org.json.JSONObject().put("username", username.value.trim().lowercase()).put("full_name", fullName.value.trim())).json
                ctx.contentResolver.openOutputStream(uri)?.use { it.write(req.toString().toByteArray()) }
                "Saved. Send it to an admin; they open it under Manage → Devices and send you a bundle back."
            }
        }
    }
    Text("Join with a file", style = MaterialTheme.typography.titleMedium)
    Dim("1. Make a join request and send it to an admin (it is signed by this phone's key).")
    NameFields(username, fullName)
    OutlinedButton(onClick = {
        if (!namesOk(username.value, fullName.value)) msg = "Fill in a username (2+ characters) and your full name."
        else save.launch("join-${username.value.trim().lowercase()}.kksjoin")
    }) { Text("Save a join request…") }
    Dim("2. Open the bundle the admin saved for you. It holds the plant's data unencrypted: get it directly from the admin.")
    Button(onClick = { open.launch(arrayOf("*/*")) }) { Text("Open a bundle…") }
    if (msg.isNotEmpty()) Text(msg)
}
