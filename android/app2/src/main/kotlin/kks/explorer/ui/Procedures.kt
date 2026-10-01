package kks.explorer.ui

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.launch

/** R7: the operation manual's procedures, their steps, and the equipment linked to each step */
@Composable
fun Procedures(ui: Ui, snack: SnackbarHostState) {
    val rev = Changes.rev
    BackHandler(enabled = ui.activeProc.isNotEmpty()) { ui.activeProc = "" }
    if (ui.activeProc.isNotEmpty()) { ProcedureDetail(ui, ui.activeProc, rev, snack); return }
    var q by remember { mutableStateOf("") }
    val all = remember(rev) { call("GET", "/native/procs").json.optJSONArray("procs").objects() }
    val shown = remember(all, q) {
        val query = q.trim().lowercase()
        if (query.isEmpty()) all else all.filter { p ->
            (p.str("id") + " " + p.str("title") + " " + p.optJSONArray("path")?.toString().orEmpty()).lowercase().contains(query)
        }
    }
    Column(Modifier.fillMaxSize()) {
        OutlinedTextField(q, { q = it }, placeholder = { Text("Search procedures") }, singleLine = true,
            modifier = Modifier.fillMaxWidth().padding(8.dp).semantics { contentDescription = "Search procedures" })
        if (all.isEmpty()) Dim("No procedures yet: they come with the plant data.")
        LazyColumn {
            var last = ""
            for (p in shown) {
                val chapter = p.optJSONArray("path")?.optString(0)?.ifEmpty { null } ?: p.str("title")
                if (chapter != last) {
                    last = chapter
                    item(key = "h:$chapter:${p.str("id")}") { Text(chapter, style = MaterialTheme.typography.titleSmall, modifier = Modifier.padding(start = 16.dp, top = 12.dp)) }
                }
                item(key = p.str("id")) {
                    ListItem(headlineContent = { Text(p.str("id") + "  " + p.str("title")) },
                        supportingContent = { Text("${p.optInt("steps")} steps" + if (p.optInt("linked") > 0) " · ${p.optInt("linked")} linked" else "") },
                        modifier = Modifier.clickable { ui.activeProc = p.str("id") })
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ProcedureDetail(ui: Ui, id: String, rev: Int, snack: SnackbarHostState) {
    val scope = rememberCoroutineScope()
    val p = remember(id, rev) { call("GET", "/native/proc", query = mapOf("id" to id)).json }
    val links = p.optJSONArray("links").objects()
    LazyColumn(Modifier.fillMaxSize().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        item {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(p.str("id") + "  " + p.str("title"), style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f).padding(top = 12.dp))
                TextButton(onClick = { ui.activeProc = "" }) { Text("Back") }
            }
            val path = p.optJSONArray("path")?.let { a -> (0 until a.length()).joinToString(" › ") { a.getString(it) } }.orEmpty()
            Dim(path + " · manual page " + p.optInt("page").let { if (it > 0) "$it" else "?" })
            if (links.isEmpty()) Dim("No equipment linked yet. The manual names equipment by description, not KKS: choose “Link equipment” on a step, then tap the matching tags on the drawing.")
            else TextButton(onClick = { ui.tab = "drawings" }) { Text("Show the linked equipment on the drawings") }
            if (p.str("intro").isNotEmpty()) Text(p.str("intro"))
        }
        items(p.optJSONArray("steps").objects()) { st ->
            val n = st.optInt("n")
            Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("$n)  " + st.str("text"))
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (l in links.filter { it.optInt("step") == n }) {
                        val k = l.getString("kks")
                        InputChip(selected = false, onClick = {
                            if (l.str("tag").isNotEmpty()) ui.show(l.getString("tag")) else scope.launch { snack.showSnackbar("$k is not on any sheet") }
                        }, label = { Text(k) }, trailingIcon = {
                            Text("✕", Modifier.clickable {
                                val (_, m) = linkSubmit(id, n, k, false)
                                scope.launch { snack.showSnackbar("Unlink $k: $m") }
                            }.semantics { contentDescription = "Unlink $k from step $n" })
                        })
                    }
                    AssistChip(onClick = { ui.linkProc = id; ui.linkStep = n; ui.tab = "drawings" }, label = { Text("+ Link equipment") })
                }
            }
        }
    }
}
