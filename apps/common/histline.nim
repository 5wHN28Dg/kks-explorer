## A History row (/api/revisions) in words, shared by the GNOME and Windows Manage pages (Android: Manage.kt History,
## the same rules). The row's line is the core's `summary` (api.historySummary, admin.html's wording). Before
## 2026-11-15 the pages read fields the API never sent (n, summary, by_name, at) and showed "#" and "added_tag <id>".
import std/[strutils, times]
import kks/json

proc str(n: JNode, k: string): string =
  if n == nil or n.kind != jObj or n.get(k) == nil or not n[k].isStr: "" else: n[k].s

proc historyTitle*(r: JNode): string =
  ## "#12 11LAB70AA501: notes leaks → fixed (a note)"
  let rev = if r.get("rev") != nil and r["rev"].isInt: "#" & $r["rev"].i & " " else: ""
  let note = r.str("note")
  let entity = r.str("entity")
  (rev & r.str("summary") & (if note.len > 0 and entity notin ["user", "sheet"]: " (" & note & ")" else: "")).strip

proc historyBy*(r: JNode): string =
  ## "The Manager · 2026-11-15 14:05": who (full name, else username, else the server's console) and when
  let who = if r.str("full_name").len > 0: r.str("full_name") elif r.str("username").len > 0: r.str("username")
            else: "server console"
  let ts = r.get("ts")
  who & (if ts != nil and ts.isInt and ts.i > 0: " · " & fromUnix(ts.i).local.format("yyyy-MM-dd HH:mm") else: "")

proc historyUndoable*(r: JNode): bool =
  ## Revert and Restore are offered as admin.html offers them: not for accounts and drawings (today's core records
  ## no such rows; the check keeps the apps in step with admin.html if it does)
  let hid = r.get("hid")
  hid != nil and not hid.isNull and r.str("entity") notin ["user", "sheet"]
