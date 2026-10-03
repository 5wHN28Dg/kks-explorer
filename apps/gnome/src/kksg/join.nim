## Adding devices (R13, PROTOCOL-v2 §16): an admin shows an invite (QR code + text); a new device joins with it, or
## asks an admin on the same Wi-Fi and both compare a 6-digit code.

import std/[asyncdispatch, strutils, tables]
import kks/[json, api]
import kksl/[mdns, dbstore]
import gtk, ui, appstate, win, qr, camera

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

# ---------------------------------------------------------------- the admin's side

proc inviteDialog*(w: Win) =
  var r: JNode
  try: r = w.a.call("POST", "/api/invites", newObj())
  except ApiError as e:
    w.toast(e.msg)
    return
  let code = r["code"].s
  let token = r["invite"]["token"].s
  let d = adw_dialog_new()
  adw_dialog_set_title(d, "Add a device with a QR code")
  adw_dialog_set_content_width(d, 460)
  let body = vbox(10)
  margins(body, 16)
  let tex = qrTexture(code)
  if tex != nil:
    let pic = gtk_picture_new_for_paintable(tex)
    gtk_widget_set_size_request(pic, 320, 320)
    setAccessibleLabel(pic, "QR code of the invite")
    body.add pic
  body.add label("Scan this with the new phone, or copy the text to the new computer (Join with a code). " &
                 "Valid for 15 minutes, for one device.", "dim-label")
  let txt = label(code, "monospace caption", selectable = true)
  body.add txt
  body.add button("Copy the text", "", proc () =
    gdk_clipboard_set_text(gtk_widget_get_clipboard(txt), code.cstring)
    w.toast("Copied"))
  let status = label("Waiting for a device…", "heading")
  body.add status
  let decide = hbox(8)
  gtk_widget_set_visible(decide, 0)
  var asked = false
  proc send(action: string) =
    try:
      discard w.a.call("POST", "/api/invites/" & token, newObj(@[("action", newStr(action)), ("existing_ok", newBool(true))]))
      gtk_label_set_text(status, (if action == "accept": "Accepted: the device syncs now." else: "Refused.").cstring)
      gtk_widget_set_visible(decide, 0)
    except ApiError as e: w.toast(e.msg)
  decide.add button("Accept", "suggested-action", proc () = send("accept"))
  decide.add button("Refuse", "destructive-action", proc () = send("refuse"))
  body.add decide
  var open = true
  d.on("closed", proc () =
    open = false
    if not asked:
      try: discard w.a.call("POST", "/api/invites/" & token, newObj(@[("action", newStr("cancel"))]))
      except ApiError: discard)
  timeout(2000, proc (): bool =
    if not open: return false
    try:
      let st = w.a.call("GET", "/api/invites/" & token)
      case st["state"].s
      of "asked":
        if not asked:
          asked = true
          let req = st["request"]
          gtk_label_set_text(status, ("A device asks to join: " & s(req, "full_name") & " (" & s(req, "username") & "), " &
                                      s(req, "label") & (if not st["existing"].isNull: ". That username exists: it becomes their new device." else: "")).cstring)
          gtk_widget_set_visible(decide, 1)
      of "expired":
        gtk_label_set_text(status, "Expired. Close this and make a new one.")
        return false
      of "accepted", "refused": return false
      else: discard
    except ApiError: return false
    true)
  let sc = scrolled(body)
  gtk_scrolled_window_set_propagate_natural_height(sc, 1)
  adw_dialog_set_content_height(d, 720)
  adw_dialog_set_child(d, toolbarView(headerBar(adw_window_title_new("Add a device", "")), sc))
  present(d, w.window)

# ---------------------------------------------------------------- the new device's side

proc runJoin(w: Win, hosts: seq[(string, int)], peer: string, token: JNode, username, fullName: string,
             status: W, needCode: bool, done: proc ()) {.async.} =
  ## ask until accepted (§16: every 2 s while waiting), then sync adopting the root
  let req = parseStrict(w.a.joinRequestFile(username, fullName, newNull()))
  var host = ""
  var port = 0
  var ack: JNode
  for (h, p) in hosts:
    try:
      ack = await w.a.askJoin(h, p, peer, token, req)
      host = h
      port = p
      break
    except CatchableError: discard
  if ack == nil:
    gtk_label_set_text(status, "None of the device's addresses answered. Are you on the same network?")
    return
  if needCode:
    gtk_label_set_text(status, ("Code " & w.a.joinCode(peer) & ": tell the admin. Waiting for them to accept…").cstring)
  else:
    gtk_label_set_text(status, "Waiting for the admin to accept…")
  while ack["state"].s == "waiting":
    await sleepAsync(2000)
    try: ack = await w.a.askJoin(host, port, peer, token, req)
    except CatchableError as e:
      gtk_label_set_text(status, ("Lost the connection: " & e.msg).cstring)
      return
  if ack["state"].s != "accepted":
    gtk_label_set_text(status, ("Not accepted: " & ack["state"].s & (if s(ack, "why").len > 0: " (" & s(ack, "why") & ")" else: "")).cstring)
    return
  proc finish() {.async.} =
    gtk_label_set_text(status, "Accepted. Syncing…")
    try:
      discard await w.a.syncOne(host, port, peer, adoptRoot = ack["root"].s)
    except CatchableError as e:
      gtk_label_set_text(status, ("Accepted, but the first sync failed: " & e.msg & ". Try again.").cstring)
      return
    if w.a.joined:
      w.a.store.setMeta("sync_peers", toText(newArr(@[newStr(host & ":" & $port & "@" & peer)])))
      w.a.changed("joined")
      done()
    else: gtk_label_set_text(status, "Synced, but this device is not certified in what came back.")
  if needCode:
    # §16: sync only after the person confirmed the admin's screen shows the same code
    gtk_label_set_text(status, ("Accepted. Does the admin's screen show " & w.a.joinCode(peer) & "?").cstring)
    let yes = button("Yes, the same code", "suggested-action", proc () = asyncCheck finish())
    let grp = gtk_widget_get_parent(status)
    if grp != nil: gtk_box_append(grp, yes)
  else:
    await finish()

proc joinGroups*(w: Win, done: proc ()): seq[W] =
  ## the setup screen's two extra ways in
  let g = group("Join with a code", "An admin shows a QR code under Manage → Devices. Paste its text here, or open a picture of the code.")
  let code = entryRow("Invite text", "")
  let user = entryRow("Your username", "")
  let full = entryRow("Your full name", "")
  for r in [code, user, full]: adw_preferences_group_add(g, r)
  let status = label("", "dim-label")
  let btns = hbox(8)
  btns.add button("Scan with the camera…", "", proc () =
    scanDialog(w.window, proc (t: string) =
      gtk_editable_set_text(code, t.cstring)
      if parseInvite(t)[0]: w.toast("Invite read") else: w.toast("That QR code is not an invite")))
  btns.add button("Open a picture of the code…", "", proc () =
    openFile(w.window, "Open a picture of the QR code", proc (path: string) =
      if path.len == 0: return
      let t = qrFromPicture(path)
      if t.len == 0: w.toast("No QR code found in that picture")
      else: gtk_editable_set_text(code, t.cstring)))
  btns.add button("Join with this code", "suggested-action", proc () =
    let (ok, inv) = parseInvite(text(code))
    if not ok:
      w.toast("That is not an invite (copy the whole text)")
      return
    let un = text(user).strip.toLowerAscii
    if un.len < 2 or text(full).strip.len == 0:
      w.toast("Fill in your username and full name")
      return
    var hosts: seq[(string, int)]
    for a in inv["addrs"].elems:
      let i = a.s.rfind(':')
      if i > 0: hosts.add((a.s[0 ..< i], parseInt(a.s[i + 1 .. ^1])))
    asyncCheck w.runJoin(hosts, inv["peer"].s, inv["token"], un, text(full).strip, status, false, done))
  adw_preferences_group_add(g, btns)
  adw_preferences_group_add(g, status)
  result.add g
  # ask an admin nearby (mDNS)
  let g2 = group("Ask an admin on this Wi-Fi", "Admins' devices nearby. You and the admin compare a 6-digit code.")
  let user2 = entryRow("Your username", "")
  let full2 = entryRow("Your full name", "")
  adw_preferences_group_add(g2, user2)
  adw_preferences_group_add(g2, full2)
  let list = vbox(4)
  let status2 = label("", "dim-label")
  proc fill() =
    list.clear()
    let found = w.a.adminsNearby()
    if found.len == 0:
      list.add label(if w.a.mdns == nil: "Finding devices on this network is off." else: "No admin's device found yet.", "dim-label")
    for i in 0 ..< found.len:
      closureScope:
        let f = found[i]
        var peer, plant, lab = ""
        for (k, v) in f.txt:
          if k == "peer": peer = v
          if k == "plant": plant = v
          if k == "label": lab = v
        list.add navRow(lab & " · " & plant, f.address, "Ask " & lab, proc () =
          let un = text(user2).strip.toLowerAscii
          if un.len < 2 or text(full2).strip.len == 0:
            w.toast("Fill in your username and full name")
            return
          asyncCheck w.runJoin(@[(f.address, f.port)], peer, newNull(), un, text(full2).strip, status2, true, done))
  adw_preferences_group_add(g2, list)
  adw_preferences_group_add(g2, button("Look again", "flat", fill))
  adw_preferences_group_add(g2, status2)
  fill()
  result.add g2
