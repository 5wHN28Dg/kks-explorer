## The first screen (R13; the GNOME app's setup + join.nim): join through a server, with a code (an invite's text),
## by asking an admin nearby (mDNS, 6-digit code), with a file, or start a new plant.

import std/[sequtils, strutils, asyncdispatch, times]
import kks/json
import kksl/dbstore
import appstate
import w32, ui, win, camera

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

var setupPage* = ""
var setupConfirm*: proc ()     ## "Yes, the same code" (asking an admin nearby)

proc runJoin(w: Win, hosts: seq[(string, int)], peer: string, token: JNode, username, fullName: string,
             status: HWND, needCode: bool, confirmBtn: HWND, done: proc ()) {.async.} =
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
    status.setText("None of the device's addresses answered. Are you on the same network?")
    return
  status.setText(if needCode: "Code " & w.a.joinCode(peer) & ": tell the admin. Waiting for them to accept…"
                 else: "Waiting for the admin to accept…")
  while ack["state"].s == "waiting":
    await sleepAsync(2000)
    try: ack = await w.a.askJoin(host, port, peer, token, req)
    except CatchableError as e:
      status.setText("Lost the connection: " & e.msg)
      return
  if ack["state"].s != "accepted":
    status.setText("Not accepted: " & ack["state"].s & (if s(ack, "why").len > 0: " (" & s(ack, "why") & ")" else: ""))
    return
  let root = ack["root"].s
  proc finish() {.async.} =
    status.setText("Accepted. Syncing…")
    try: discard await w.a.syncOne(host, port, peer, adoptRoot = root)
    except CatchableError as e:
      status.setText("Accepted, but the first sync failed: " & e.msg & ". Try again.")
      return
    if w.a.joined:
      w.a.store.setMeta("sync_peers", toText(newArr(@[newStr(host & ":" & $port & "@" & peer)])))
      w.a.changed("joined")
      done()
    else: status.setText("Synced, but this device is not certified in what came back.")
  if needCode:
    # §16: sync only after the person confirmed the admin's screen shows the same code
    status.setText("Accepted. Does the admin's screen show " & w.a.joinCode(peer) & "? If yes, press the button below.")
    EnableWindow(confirmBtn, 1)
    ShowWindow(confirmBtn, SW_SHOW)
    setupConfirm = proc () = asyncCheck finish()
  else:
    await finish()

proc buildSetup*(w: Win, p: Page, done: proc ()) =
  p.clear()
  p.title("Walkdown")
  case setupPage
  of "":
    let removed = w.a.removedNote
    if removed.len > 0: p.label(removed & " Its plant data was deleted here.")
    p.label("This device does not belong to a plant yet.")
    const choices = [("Join through a server", "Username and password on the plant's server"),
                     ("Join with a code", "An admin shows a QR code; paste its text"),
                     ("Ask an admin on this network", "Compare a 6-digit code with an admin nearby"),
                     ("Join with a file", "A bundle an admin saved for you"),
                     ("Start a new plant", "You become its manager")]
    for ci in 0 ..< choices.len:
      closureScope:
        let title = choices[ci][0]
        let sub = choices[ci][1]
        p.buttons((title, proc () =
          setupPage = title
          w.buildSetup(p, done)))
        p.dim(sub)
  of "Join through a server":
    p.dim("The server's name or IP, with its sync port if it isn't 8421.")
    let url = p.field("Server address", "")
    let user = p.field("Username", "")
    let pw = p.field("Password", "", password = true)
    let status = p.label("")
    p.buttons(("Join", proc () =
      status.setText("Joining…")
      proc run() {.async.} =
        let err = await w.a.joinServer(url.text.strip, user.text.strip, pw.text)
        if err.len > 0: status.setText(err) else: done()
      asyncCheck run()))
  of "Join with a code":
    p.dim("An admin shows a QR code under Manage → Devices. Copy its text here.")
    let code = p.multiField("Invite text", "", 110)
    p.buttons(("Scan with the camera…", proc () =
      scanWindow(w.hwnd, proc (t: string) =
        code.setText(t)
        if not parseInvite(t)[0]: w.toast("That QR code is not an invite"))))
    let user = p.field("Your username", "")
    let fn = p.field("Your full name", "")
    let status = p.label("")
    p.buttons(("Join with this code", proc () =
      let (ok, inv) = parseInvite(code.text.replace("\r\n", "").replace("\n", ""))
      if not ok:
        status.setText("That is not an invite. Copy the whole text the admin's device shows.")
        return
      if user.text.strip.len < 2 or fn.text.strip.len == 0:
        status.setText("Fill in a username (2+ characters) and your full name.")
        return
      var hosts: seq[(string, int)]
      for a in inv["addrs"].elems: hosts.add serverAddress(a.s)
      asyncCheck w.runJoin(hosts, inv["peer"].s, inv["token"], user.text.strip.toLowerAscii, fn.text.strip, status, false, nil, done)))
  of "Ask an admin on this network":
    p.dim("Admins' devices nearby. You and the admin compare a 6-digit code.")
    let user = p.field("Your username", "")
    let fn = p.field("Your full name", "")
    let status = p.label("")
    let found = w.a.adminsNearby()
    if found.len == 0:
      p.dim(if w.a.mdns == nil: "Finding devices on this network is off." else: "No admin's device found yet. Press Look again in a moment.")
    var confirmBtn: HWND
    let lp1 = toSeq(found)
    for lp1i in 0 ..< lp1.len:
      closureScope:
        let f = lp1[lp1i]
        let ff = f
        var lab, plant, peer: string
        for (k, v) in ff.txt:
          if k == "label": lab = v
          if k == "plant": plant = v
          if k == "peer": peer = v
        p.buttons(("Ask " & lab & " · " & plant, proc () =
          if user.text.strip.len < 2 or fn.text.strip.len == 0:
            status.setText("Fill in a username (2+ characters) and your full name.")
            return
          asyncCheck w.runJoin(@[(ff.address, ff.port)], peer, newNull(), user.text.strip.toLowerAscii, fn.text.strip,
                               status, true, confirmBtn, done)))
    confirmBtn = p.buttons(("Yes, the admin shows the same code", proc () =
      if setupConfirm != nil: setupConfirm()))[0]
    ShowWindow(confirmBtn, SW_HIDE)
    p.buttons(("Look again", proc () = w.buildSetup(p, done)))
  of "Join with a file":
    p.dim("1. Make a join request and send it to an admin (it is signed by this device's key).")
    let user = p.field("Your username", "")
    let fn = p.field("Your full name", "")
    let status = p.label("")
    p.buttons(("Save a join request…", proc () =
      if user.text.strip.len < 2 or fn.text.strip.len == 0:
        status.setText("Fill in a username (2+ characters) and your full name.")
        return
      let path = saveFile(w.hwnd, "Save a join request", "Join requests|*.kksjoin", "join-" & user.text.strip.toLowerAscii & ".kksjoin", "kksjoin")
      if path.len > 0:
        writeFile(path, w.a.joinRequestFile(user.text.strip.toLowerAscii, fn.text.strip, newNull()))
        status.setText("Saved. Send it to an admin; they open it under Manage → Devices and send you a bundle back.")))
    p.dim("2. Open the bundle the admin saved for you. It holds the plant's data unencrypted: get it directly from the admin.")
    p.buttons(("Open a bundle…", proc () =
      let path = openFile(w.hwnd, "Open a KKS bundle", "Bundles|*.kksbundle|All files|*.*")
      if path.len == 0: return
      let err = w.a.importBundleFile(readFile(path))
      if err.len > 0: status.setText(err)
      elif w.a.joined: done()
      else: status.setText("The bundle was imported, but this device is not certified in it yet.")))
  of "Start a new plant":
    p.dim("You become its manager. This device holds the plant's root key: back it up afterwards (Manage → Account).")
    let plant = p.field("Plant name", "")
    let un = p.field("Your username", "")
    let fn = p.field("Your full name", "")
    let status = p.label("")
    p.buttons(("Create the plant", proc () =
      if plant.text.strip.len == 0 or un.text.strip.len < 2 or fn.text.strip.len == 0:
        status.setText("Fill in the plant name, a username (2+ characters) and your full name.")
        return
      try:
        w.a.createPlant(plant.text.strip, un.text.strip.toLowerAscii, fn.text.strip, newNull())
        done()
      except CatchableError as e: status.setText(e.msg)))
  else: discard
  if setupPage.len > 0:
    p.space()
    p.buttons(("Back", proc () =
      setupPage = ""
      w.buildSetup(p, done)))
  p.layout()
