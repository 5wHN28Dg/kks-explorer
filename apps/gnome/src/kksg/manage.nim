## Manage (R10–R14; admin.html): approvals, my proposals, history with revert and restore, people, devices (join
## requests, revoke), and the account. Everything goes through the core's local API, like admin.html.

import std/[strutils, tables, times, sequtils, asyncdispatch]
import kks/[json, api, node, extras, util]
import kksl/[dbstore, privfile, passphrase]
import kks/model
import proposals
import gtk, ui, appstate, win, photos, join

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc at(n: JNode, k: string): string =
  if n == nil or n.get(k) == nil or n[k].kind != jInt: return ""
  fromUnix(n[k].i).local.format("yyyy-MM-dd HH:mm")

proc refreshPage(w: Win, box: W, build: proc (box: W)) =
  box.clear()
  build(box)

proc act(w: Win, id: int64, action: string, body: JNode, done: string): bool =
  try:
    discard w.a.call("POST", "/api/submissions/" & $id & "/" & action, body)
    w.toast(done)
    true
  except ApiError as e:
    w.toast(e.msg)
    false

proc approvals(w: Win, box: W) =
  var subs: seq[JNode]
  try: subs = w.a.call("GET", "/api/submissions", nil, {"status": "open"}.toTable)["submissions"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let open = subs.filterIt(not it["mine"].b or w.isAdmin)
  if open.len == 0:
    box.add label("Nothing waits for approval.", "dim-label")
    return
  for i in 0 ..< open.len:
    closureScope:
      let sub = open[i]
      let id = sub["id"].i
      let g = group(proposalTitle(sub),
                    "by " & s(sub, "by_name") & " · " & sub.at("created") &
                    (if s(sub, "request_note").len > 0: " · note: " & s(sub, "request_note") else: ""))
      for (lab, v) in proposalRows(sub): adw_preferences_group_add(g, row(lab, v, selectable = true))
      if sub["status"].s == "conflict":
        adw_preferences_group_add(g, row("Held", "It clashes with the current value or another proposal: " & s(sub, "note"), selectable = true))
      if sub["kind"].s == "photo" and sub.get("payload") != nil:
        let file = s(sub["payload"], "file")
        let sha = file.split('.')[0]
        if w.a.n.store.blobHas(sha):
          let data = w.a.n.store.blobGet(sha)
          adw_preferences_group_add(g, button("Show the photo", "flat", proc () = w.showPhoto(data, s(sub["payload"], "caption"))))
      let btns = hbox(8)
      gtk_widget_set_margin_top(btns, 6)
      if w.isAdmin:
        btns.add button(if sub["status"].s == "conflict": "Approve anyway" else: "Approve", "suggested-action", proc () =
          if w.act(id, "approve", newObj(@[("force", newBool(sub["status"].s == "conflict"))]), "Approved"):
            w.refreshPage(box, proc (b: W) = w.approvals(b)))
        if sub["kind"].s == "photo":
          btns.add button("Pick this photo", "", proc () =
            if w.act(id, "pick", newObj(), "Photo chosen, others rejected"): w.refreshPage(box, proc (b: W) = w.approvals(b)))
        btns.add button("Reject", "destructive-action", proc () =
          if w.act(id, "reject", newObj(), "Rejected"): w.refreshPage(box, proc (b: W) = w.approvals(b)))
      adw_preferences_group_add(g, btns)
      box.add g

proc myProposals(w: Win, box: W) =
  var subs: seq[JNode]
  try: subs = w.a.call("GET", "/api/submissions", nil, {"status": "all", "limit": "200"}.toTable)["submissions"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let mine = subs.filterIt(it["mine"].b)
  if mine.len == 0: box.add label("You have proposed nothing yet.", "dim-label")
  for i in 0 ..< mine.len:
    closureScope:
      let sub = mine[i]
      let id = sub["id"].i
      let g = group(proposalTitle(sub), sub["status"].s & " · " & sub.at("created") &
                    (if s(sub, "note").len > 0: " · " & s(sub, "note") else: ""))
      for (lab, v) in proposalRows(sub): adw_preferences_group_add(g, row(lab, v, selectable = true))
      if sub["status"].s in ["pending", "conflict"]:
        adw_preferences_group_add(g, button("Withdraw", "", proc () =
          confirm(w.window, "Withdraw this proposal?", "", "Withdraw", true, proc () =
            if w.act(id, "withdraw", newObj(), "Withdrawn"): w.refreshPage(box, proc (b: W) = w.myProposals(b)))))
      box.add g
  # photos others proposed: members vote
  let photosOpen = subs.filterIt(not it["mine"].b and it["kind"].s == "photo" and it["status"].s in ["pending", "conflict"])
  if photosOpen.len > 0:
    let g = group("Photos waiting for approval", "Vote for the ones you find useful; an admin decides.")
    for i in 0 ..< photosOpen.len:
      closureScope:
        let sub = photosOpen[i]
        let id = sub["id"].i
        adw_preferences_group_add(g, navRow(s(sub, "target") & " · by " & s(sub, "by_name"),
          $(if sub.get("votes") != nil: sub["votes"].i else: 0) & " votes" & (if sub.get("voted") != nil and sub["voted"].b: " (yours)" else: ""),
          "Vote for this photo", proc () =
            if w.act(id, "vote", newObj(), "Vote changed"): w.refreshPage(box, proc (b: W) = w.myProposals(b))))
    box.add g

proc history(w: Win, box: W) =
  var revs: seq[JNode]
  try: revs = w.a.call("GET", "/api/revisions", nil, {"limit": "200"}.toTable)["revisions"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  if revs.len == 0: box.add label("No changes yet.", "dim-label")
  let g = group("Changes, newest first", "Revert undoes one change; Restore goes back to the state just after a change.")
  for i in 0 ..< revs.len:
    closureScope:
      let r = revs[i]
      let hid = r.get("hid")
      let title = "#" & (if r.get("n") != nil: toText(r["n"]) else: "") & " " & s(r, "summary") & s(r, "note")
      let sub = s(r, "by_name") & " · " & r.at("at") & (if s(r, "entity").len > 0: " · " & s(r, "entity") & " " & s(r, "key") else: "")
      let rw = row(title.strip, sub, selectable = true)
      if hid != nil and not hid.isNull:
        let rev = button("Revert", "flat", proc () =
          confirm(w.window, "Revert this change?", "This writes a new change that undoes it; History keeps both.", "Revert", true, proc () =
            try:
              discard w.a.call("POST", "/api/revisions/" & (if hid.kind == jInt: $hid.i else: hid.s) & "/revert", newObj())
              w.toast("Reverted")
              w.refreshPage(box, proc (b: W) = w.history(b))
            except ApiError as e: w.toast(e.msg)))
        gtk_widget_set_valign(rev, GTK_ALIGN_CENTER)
        adw_action_row_add_suffix(rw, rev)
        let rest = button("Restore", "flat", proc () =
          confirm(w.window, "Restore to just after this change?", "Every later change is undone by new changes.", "Restore", true, proc () =
            try:
              discard w.a.call("POST", "/api/restore", newObj(@[("hid", hid)]))
              w.toast("Restored")
              w.refreshPage(box, proc (b: W) = w.history(b))
            except ApiError as e: w.toast(e.msg)))
        gtk_widget_set_valign(rest, GTK_ALIGN_CENTER)
        adw_action_row_add_suffix(rw, rest)
      adw_preferences_group_add(g, rw)
  box.add g

proc people(w: Win, box: W) =
  var users: seq[JNode]
  try: users = w.a.call("GET", "/api/users")["users"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let g = group("People", "Everyone who has an identity in this plant. Devices are added under Devices.")
  for u in users:
    adw_preferences_group_add(g, row(s(u, "full_name") & " (" & s(u, "username") & ")",
      s(u, "role") & (if s(u, "position").len > 0: " · " & s(u, "position") else: ""), selectable = true))
  box.add g
  let add = group("Add a person", "For someone whose device will join later (by QR code, request file or nearby admin).")
  let un = entryRow("Username", "")
  let fn = entryRow("Full name", "")
  let pos = entryRow("Position (optional)", "")
  for r in [un, fn, pos]: adw_preferences_group_add(add, r)
  adw_preferences_group_add(add, button("Add", "", proc () =
    try:
      discard w.a.call("POST", "/api/users", newObj(@[("username", newStr(text(un).strip.toLowerAscii)),
        ("full_name", newStr(text(fn).strip)), ("position", newStr(text(pos).strip)), ("role", newStr("user"))]))
      w.toast("Added " & text(un).strip)
      w.refreshPage(box, proc (b: W) = w.people(b))
    except ApiError as e: w.toast(e.msg)))
  box.add add

proc devices(w: Win, box: W) =
  var d: JNode
  try: d = w.a.call("GET", "/api/devices")
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  proc devRows(list: JNode, title: string) =
    if list == nil or list.kind != jArr: return
    let g = group(title)
    for i in 0 ..< list.elems.len:
      closureScope:
        let x = list.elems[i]
        let dev = s(x, "device")
        let rw = row((if s(x, "label").len > 0: s(x, "label") else: "device") & " · " & s(x, "username") & (if x["this_computer"].b: " (this device)" else: ""),
                     dev[0 ..< min(16, dev.len)] & "…" & (if x["revoked"].b: " · removed" else: ""))
        if not x["revoked"].b and not x["this_computer"].b:
          let b = button("Remove", "flat destructive-action", proc () =
            confirm(w.window, "Remove this device?", "It stops receiving data, and wipes the plant from itself if it ever connects again.",
                    "Remove", true, proc () =
              try:
                discard w.a.call("POST", "/api/devices/revoke", newObj(@[("device", newStr(dev))]))
                w.toast("Removed")
                w.refreshPage(box, proc (b: W) = w.devices(b))
              except ApiError as e: w.toast(e.msg)))
          gtk_widget_set_valign(b, GTK_ALIGN_CENTER)
          adw_action_row_add_suffix(rw, b)
        adw_preferences_group_add(g, rw)
    box.add g
  devRows(d.get("mine"), "Your devices")
  if w.isAdmin:
    devRows(d.get("all"), "All devices")
    # devices asking an admin nearby (R13): accept after comparing the 6-digit code
    try:
      let reqs = w.a.call("GET", "/api/join-requests")["requests"].elems
      if reqs.len > 0:
        let g = group("Waiting to join", "Accept only if the code on the other device is the same.")
        for i in 0 ..< reqs.len:
          closureScope:
            let r = reqs[i]
            let dev = s(r, "device")
            let req = r["request"]
            let rw = row(s(req, "full_name") & " (" & s(req, "username") & ") · " & s(req, "label"), "code " & s(r, "code"))
            let choices = @[("Accept", "accept"), ("Refuse", "refuse")]
            for ci in 0 ..< choices.len:
              closureScope:
                let lab = choices[ci][0]
                let act = choices[ci][1]
                let b = button(lab, "flat", proc () =
                  try:
                    discard w.a.call("POST", "/api/join-requests/" & dev, newObj(@[("action", newStr(act)), ("existing_ok", newBool(true))]))
                    w.toast(if act == "accept": "Accepted" else: "Refused")
                    w.refreshPage(box, proc (b: W) = w.devices(b))
                  except ApiError as e: w.toast(e.msg))
                gtk_widget_set_valign(b, GTK_ALIGN_CENTER)
                adw_action_row_add_suffix(rw, b)
            adw_preferences_group_add(g, rw)
        box.add g
    except ApiError: discard
    let qrG = group("Add a device with a QR code", "The new device scans it, or you copy its text over.")
    adw_preferences_group_add(qrG, button("Show an invite…", "suggested-action", proc () = w.inviteDialog()))
    box.add qrG
    let imp = group("Add a device from a request file", "Someone made a join request (.kksjoin) on their device and sent it to you.")
    adw_preferences_group_add(imp, button("Open a join request…", "", proc () =
      openFile(w.window, "Open a join request", proc (path: string) =
        if path.len == 0: return
        try:
          let req = parseStrict(readFile(path))
          discard w.a.call("POST", "/api/devices/import-request", newObj(@[("request", req), ("existing_ok", newBool(true))]))
          w.toast("The device is certified; it joins with its next sync (or send it a bundle).")
          w.refreshPage(box, proc (b: W) = w.devices(b))
        except CatchableError as e: w.toast(e.msg))))
    adw_preferences_group_add(imp, button("Save a bundle for it…", "", proc () =
      saveFile(w.window, "Save a bundle", "plant.kksbundle", proc (path: string) =
        if path.len == 0: return
        try:
          let r = w.a.api.handle(w.a.me[1], "GET", "/api/bundle", initTable[string, string](), newObj(), nowMs())
          writeFile(path, r.bytes)
          w.toast("Saved. The bundle holds the plant's data unencrypted: hand it over directly.")
        except CatchableError as e: w.toast(e.msg))))
    box.add imp

proc account(w: Win, box: W) =
  let (_, me) = w.a.me
  let g = group("Your details")
  let fn = entryRow("Full name", me.fullName)
  let pos = entryRow("Position", if me.position.isStr: me.position.s else: "")
  adw_preferences_group_add(g, row("Username", me.username))
  adw_preferences_group_add(g, row("Role", me.role))
  adw_preferences_group_add(g, fn)
  adw_preferences_group_add(g, pos)
  adw_preferences_group_add(g, button("Save", "", proc () =
    try:
      discard w.a.call("POST", "/api/profile", newObj(@[("full_name", newStr(text(fn).strip)), ("position", newStr(text(pos).strip))]))
      w.toast("Saved")
    except ApiError as e: w.toast(e.msg)))
  box.add g
  let sg = group("Sync", "Devices on the same Wi-Fi find each other; others can be reached by address.")
  let snap = w.a.snapshot
  adw_preferences_group_add(sg, row("This device", w.a.n.device[0 ..< 16] & "… · sync port " &
    (if snap["port"].kind == jInt: $snap["port"].i else: "off"), selectable = true))
  let addr0 = entryRow("Sync with an address (host:port@device)", "")
  adw_preferences_group_add(sg, addr0)
  adw_preferences_group_add(sg, button("Sync now", "", proc () =
    let t = text(addr0).strip
    proc go() {.async.} =
      if t.len > 0:
        let at = t.rfind('@')
        let colon = t.rfind(':', last = max(0, at))
        if at < 0 or colon < 0:
          w.toast("Write it as host:port@device")
          return
        try:
          discard await w.a.syncOne(t[0 ..< colon], parseInt(t[colon + 1 ..< at]), t[at + 1 .. ^1])
          w.toast("Synced")
        except CatchableError as e: w.toast(e.msg)
      else:
        let n = await w.a.syncAll()
        w.toast(if n > 0: "Synced with " & $n & " device" & (if n == 1: "" else: "s") else: "No other device reached")
    asyncCheck go()))
  if w.a.me[1].role == "manager":
    # PROTOCOL-v2 §18: the plant's relay, a setting every device learns at its next sync
    let rv = w.a.n.run.settings.getOrDefault("relay")
    let relay = entryRow("Internet relay (wss://…), empty = off", if rv != nil and rv.isStr: rv.s else: "")
    adw_preferences_group_add(sg, relay)
    adw_preferences_group_add(sg, button("Save relay", "", proc () =
      try:
        discard w.a.call("POST", "/api/settings/relay", newObj(@[("url", newStr(text(relay).strip))]))
        w.toast(if text(relay).strip.len == 0: "Relay removed" else: "Relay saved: every device learns it at its next sync")
      except ApiError as e: w.toast(e.msg)))
  box.add sg

proc rootKeySection(w: Win): W =
  ## R14: the plant's authority has an offline backup the manager holds (PROTOCOL-v2 §20: PBKDF2 ≥ 600 000 + AES-GCM).
  ## The passphrase is generated (80 bits, decision 0023, issue #29) and shown once; the file is written 0600.
  let g = group("Root key", "The plant's root key signs the manager role and settles stolen devices. Keep an encrypted " &
                "copy offline (a USB stick in a drawer). Its passphrase is made for you: write it down and keep it apart.")
  let has = w.a.store.getRow("keys", "root") != nil
  adw_preferences_group_add(g, row("On this device", if has: "yes" else: "no (it is on another device of the manager)"))
  let pw1 = passwordRow("Passphrase of the backup to restore")
  if has:
    let shown = row("Passphrase of the backup just saved", "(save a backup to see it)", selectable = true)
    adw_preferences_group_add(g, shown)
    adw_preferences_group_add(g, button("Save an encrypted backup…", "", proc () =
      saveFile(w.window, "Save the root key backup", "root-key.kksroot", proc (path: string) =
        if path.len == 0: return
        let pass = w.a.p.newBackupPassphrase()
        let k = w.a.store.getRow("keys", "root")
        let plain = toText(k)
        var bytes: seq[byte]
        for c in plain: bytes.add byte(c)
        let sealed = w.a.p.passphraseSeal(pass, bytes)
        let doc = newObj(@[("kks_root_backup", newInt(2)), ("plant", newStr(w.a.plantName)), ("root", newStr(w.a.n.root)),
                           ("sealed", sealed)])
        try:
          writePrivate(path, toText(doc))
        except OSError as e:
          w.toast("Not saved: " & e.msg)
          return
        adw_action_row_set_subtitle(shown, pass.cstring)
        w.toast("Saved. Write down the passphrase shown above: it is not kept anywhere. Test the backup once with Restore."))))
  adw_preferences_group_add(g, pw1)
  adw_preferences_group_add(g, button("Restore from a backup…", "", proc () =
    openFile(w.window, "Open a root key backup", proc (path: string) =
      if path.len == 0: return
      try:
        let doc = parseStrict(readFile(path))
        if doc.get("root") == nil or doc["root"].s != w.a.n.root:
          w.toast("That backup belongs to another plant")
          return
        let plain = w.a.p.passphraseOpen(text(pw1), doc["sealed"])
        var txt = newString(plain.len)
        for i, b in plain: txt[i] = char(b)
        w.a.store.putRow("keys", "root", parseStrict(txt))
        w.toast("The root key is on this device now")
      except CatchableError:
        w.toast("Wrong passphrase, or not a root key backup"))))
  g

proc copyText(w: Win, text: string) =
  gdk_clipboard_set_text(gtk_widget_get_clipboard(w.window), text.cstring)
  w.toast("Copied")

proc diagnosticsGroup(w: Win): W =
  ## decision 0040: everyone sees whether reports are on; the manager switches them from their own device
  var d: JNode
  try: d = w.a.call("GET", "/api/diagnostics")
  except ApiError: return group("Diagnostics reports")
  let on = d["on"].kind == jBool and d["on"].b
  result = group("Diagnostics reports", if on: "On: this computer sends the manager short error reports (crashes, " &
                 "failed syncs, app errors). Never plant data or passwords." else: "Off: this computer sends no error reports.")
  if w.a.me[1].role == "manager" and d.get("can_switch") != nil and d["can_switch"].b:
    adw_preferences_group_add(result, button(if on: "Switch reports off" else: "Switch reports on", "", proc () =
      try:
        discard w.a.call("POST", "/api/diagnostics", newObj(@[("on", newBool(not on))]))
        w.toast(if on: "Reports off" else: "Reports on: every device learns it at its next sync. Reopen Account to see the new state.")
      except ApiError as e: w.toast(e.msg)))

proc diagnosticsReports(w: Win, box: W) =
  ## the manager's reports, newest first, each with Copy (for Claude); "Copy all" on top
  var d: JNode
  try: d = w.a.call("GET", "/api/diagnostics")
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let reports = if d.get("reports") != nil: d["reports"] else: newArr()
  if not (d["on"].kind == jBool and d["on"].b): box.add label("Reports are off (Account → Diagnostics reports).", "dim-label")
  if d.get("can_read") != nil and not d["can_read"].b:
    box.add label("This device holds no report key yet. Reports open on the device you switched them on from, and on " &
                  "your other devices after they synced with it.", "dim-label")
  if reports.len == 0:
    box.add label("No reports yet.", "dim-label")
    return
  box.add button("Copy all reports (for Claude)", "", proc () = w.copyText(toText(reports)))
  for r in reports.elems:
    let when0 = fromUnix(r["at"].i div 1000).local.format("yyyy-MM-dd HH:mm")
    let who = (if r["username"].s.len > 0: r["username"].s else: "?") & " · " & (if r["label"].s.len > 0: r["label"].s else: "device")
    let rep = r["report"]
    let g = group(who, when0 & (if rep.kind == jObj: " · " & rep["app"].s & " " & rep["version"].s & " · " & rep["platform"].s else: ""))
    if rep.kind != jObj:
      adw_preferences_group_add(g, row("Not readable here", "sealed to a report key this device doesn't hold"))
    else:
      for i, ev in rep["events"].elems:
        if i >= 30: break
        let n = if ev.get("n") != nil: ev["n"].i else: 1
        let first = ev["text"].s.splitLines()[0]
        adw_preferences_group_add(g, row(ev["kind"].s & (if n > 1: " ×" & $n else: "") & " · " &
                                         fromUnix(ev["at"].i div 1000).local.format("MM-dd HH:mm"), first, selectable = true))
    let rr = r
    adw_preferences_group_add(g, button("Copy", "", proc () = w.copyText(toText(rr))))
    box.add g

proc managePage*(w: Win): W =
  let box = vbox(12)
  margins(box, 8)
  let list = gtk_list_box_new()
  gtk_widget_add_css_class(list, "boxed-list")
  gtk_list_box_set_selection_mode(list, GTK_SELECTION_NONE)
  proc sub(title, subtitle, tag: string, build: proc (b: W), live = false) =
    list.gtk_list_box_append(navRow(title, subtitle, "Open " & title, proc () =
      let open = adw_navigation_view_find_page(w.sideNav, tag.cstring)
      if open != nil:                     # already in the stack (tags must be unique): go back to it
        adw_navigation_view_pop_to_page(w.sideNav, open)
        return
      let b = vbox(12)
      margins(b, 8)
      build(b)
      w.setLive(if live: b else: nil, build)
      let tv = toolbarView(headerBar(adw_window_title_new(title.cstring, "")), scrolled(b))
      adw_navigation_view_push(w.sideNav, adw_navigation_page_new_with_tag(tv, title.cstring, tag.cstring))))
  if w.isAdmin: sub("Approvals", "Proposals waiting for a decision", "approvals", proc (b: W) = w.approvals(b), live = true)
  sub("My proposals", "What you proposed, and photos to vote on", "mine", proc (b: W) = w.myProposals(b), live = true)
  if w.isAdmin:
    sub("History", "Every change, with revert and restore", "history", proc (b: W) = w.history(b), live = true)
    sub("People", "Accounts and roles", "people", proc (b: W) = w.people(b))
  sub("Devices", "Your devices" & (if w.isAdmin: ", all devices, joining" else: ""), "devices", proc (b: W) = w.devices(b), live = true)
  sub("Account", "Your details, sync" & (if w.a.me[1].role == "manager": ", root key" else: ""), "account", proc (b: W) =
    w.account(b)
    b.add w.diagnosticsGroup()
    if w.a.me[1].role == "manager": b.add w.rootKeySection())
  if w.a.me[1].role == "manager":
    sub("Diagnostics", "Error reports from the plant's devices", "diagnostics", proc (b: W) = w.diagnosticsReports(b), live = true)
  box.add list
  scrolled(box)
