## A History row (/api/revisions) in words, shared by the GNOME and Windows Manage pages (Android: Manage.kt History,
## the same rules). The row's line is the core's `summary` (api.historySummary, admin.html's wording). Before
## 2026-11-15 the pages read fields the API never sent (n, summary, by_name, at) and showed "#" and "added_tag <id>".
import std/[strutils, times, unicode]
import kks/json

proc str(n: JNode, k: string): string =
  if n == nil or n.kind != jObj or n.get(k) == nil or not n[k].isStr: "" else: n[k].s

proc historyTitle*(r: JNode): string =
  ## "#12 11LAB70AA501: notes leaks → fixed (a note)"
  let rev = if r.get("rev") != nil and r["rev"].isInt: "#" & $r["rev"].i & " " else: ""
  let note = r.str("note")
  let entity = r.str("entity")
  (rev & r.str("summary") & (if note.len > 0 and entity notin ["user", "sheet"]: " (\u2068" & note.replace('\n', ' ') & "\u2069)" else: "")).strutils.strip

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

proc isolatesAsEmbeddings*(s: string): string =
  ## For text drawn by Win32's GDI (static labels), which shows U+2068/U+2069 as boxes: each first-strong isolate
  ## becomes a right-to-left (U+202B) or left-to-right (U+202A) embedding by its first strong letter, and each pop
  ## of an isolate a pop of the embedding (U+202C), which GDI draws as nothing.
  let rs = toRunes(s)
  var i = 0
  while i < rs.len:
    let r = rs[i]
    if r == Rune(0x2068):
      var rtl = false
      var j = i + 1
      while j < rs.len and rs[j] != Rune(0x2069):
        let c = int(rs[j])
        if (c >= 0x0590 and c <= 0x08FF) or (c >= 0xFB1D and c <= 0xFDFF) or (c >= 0xFE70 and c <= 0xFEFF):
          rtl = true
          break
        if rs[j].isAlpha: break
        inc j
      result.add(if rtl: "‫" else: "‪")
    elif r == Rune(0x2069): result.add "‬"
    else: result.add $r
    inc i
