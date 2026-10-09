package kks.explorer.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import org.json.JSONObject

/*
 * Links between drawings: the off-page connectors (C16, D2 …) on a sheet, each a hotspot on the drawing and a row in
 * "Connectors on this sheet" (named for TalkBack: "Connector C16, continues on Sheet B"). Following one opens where its
 * line continues: one target goes there, several ask which, none says so. Targets: core views.linksView through
 * /native/links (GNOME's links.nim, the web's index.js do the same).
 */

/** the sheet's connectors as the core gives them: label, box in points, targets */
fun linksOf(sheet: String): List<JSONObject> =
    call("GET", "/native/links", query = mapOf("sheet" to sheet)).json.optJSONArray("links").objects()

private fun targetName(t: JSONObject) = if (t.optBoolean("same_sheet")) "elsewhere on this sheet" else t.str("sheet_name")

fun whereText(l: JSONObject): String {
    val names = l.optJSONArray("targets").objects().map(::targetName).distinct()
    return if (names.isEmpty()) "the other end isn't on any drawing in the app" else "continues on " + names.joinToString(", ")
}

fun linkName(l: JSONObject) = "Connector " + l.str("label") + ", " + whereText(l)

fun linkBox(l: JSONObject) = SheetView.LinkBox(l.str("label"), l.optDouble("x0").toFloat(), l.optDouble("y0").toFloat(),
    l.optDouble("x1").toFloat(), l.optDouble("y1").toFloat(), linkName(l))

/** the choice's buttons, one per target: the sheet's name, numbered when one sheet has the code more than once */
fun targetLabels(ts: List<JSONObject>): List<String> {
    val names = ts.map(::targetName)
    return names.mapIndexed { i, n ->
        val all = names.count { it == n }
        if (all > 1) "$n (${names.take(i + 1).count { it == n }} of $all)" else n
    }
}

/** where a connector was followed to: the sheet and the target's box (points) */
data class LinkTarget(val label: String, val sheet: String, val sheetName: String, val box: List<Float>)

/** what following the connector `label` at (x0, y0) of `sheet` does: a message (gone, nowhere), one target, or a choice.
 *  Looked up again rather than kept: a sync in between can reorder the connectors. */
sealed class Follow {
    data class Say(val text: String) : Follow()
    data class Go(val target: LinkTarget) : Follow()
    data class Ask(val label: String, val targets: List<LinkTarget>, val labels: List<String>) : Follow()
}

fun follow(sheet: String, label: String, x0: Float, y0: Float): Follow {
    val l = linksOf(sheet).firstOrNull { it.str("label") == label && Math.abs(it.optDouble("x0") - x0) < 0.01 && Math.abs(it.optDouble("y0") - y0) < 0.01 }
        ?: return Follow.Say("Connector $label is no longer on this drawing")
    val ts = l.optJSONArray("targets").objects()
    val targets = ts.map { t -> LinkTarget(label, t.str("sheet"), t.str("sheet_name"),
        listOf("x0", "y0", "x1", "y1").map { t.optDouble(it).toFloat() }) }
    return when (targets.size) {
        0 -> Follow.Say("Connector $label: the other end isn't on any drawing in the app")
        1 -> Follow.Go(targets[0])
        else -> Follow.Ask(label, targets, targetLabels(ts))
    }
}

/** "Where does D2 continue?": one button per target, and Cancel */
@Composable
fun LinkChoice(ask: Follow.Ask, onGo: (LinkTarget) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Where does ${ask.label} continue?") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Dim("This connector's code appears in more than one place.")
            ask.targets.forEachIndexed { i, t -> TextButton(onClick = { onDismiss(); onGo(t) }) { Text(ask.labels[i]) } }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("Cancel") } })
}

/** "Connectors on this sheet": a row per connector, its code and where the line continues */
@Composable
fun ConnectorsDialog(sheetName: String, links: List<JSONObject>, onPick: (JSONObject) -> Unit, onDismiss: () -> Unit) {
    AlertDialog(onDismissRequest = onDismiss, title = { Text("Connectors on this sheet") }, text = {
        Column(Modifier.verticalScroll(rememberScrollState())) {
            if (links.isEmpty()) Dim("No connectors to other drawings on this sheet.")
            else {
                Dim("Where the lines of $sheetName continue (the circled codes on the drawing).")
                for (l in links) ListItem(headlineContent = { Text("Connector " + l.str("label")) },
                    supportingContent = { Text(whereText(l)) },
                    modifier = Modifier.clickable(onClickLabel = "Follow it") { onDismiss(); onPick(l) })
            }
        }
    }, confirmButton = { TextButton(onClick = onDismiss) { Text("Close") } })
}
