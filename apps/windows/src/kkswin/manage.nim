## Manage (R10–R14; the GNOME app's manage.nim): approvals, my proposals, history with revert and restore, people,
## devices (join requests, invites with a QR code, request files, bundles, removal), and the account (details, sync,
## the root key backup). Everything goes through the core's local API, like admin.html.

import std/[strutils, tables, times, sequtils, asyncdispatch]
import kks/[json, api, node, extras, util]
import kksl/[dbstore, passphrase]
import kks/model
import proposals
import appstate
import w32, ui, win, photos

{.compile("kks_qr.cpp", "-std=c++17").}
{.passL: "-lZXing".}
proc qrBitmap(text: cstring, scale: cint, side: ptr cint): pointer {.importc: "kks_qr_bitmap", cdecl.}

const
  STM_SETIMAGE = 0x0172'u32
  SS_BITMAP = 0x0E'u32

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc at(n: JNode, k: string): string =
  if n == nil or n.get(k) == nil or n[k].kind != jInt: return ""
  fromUnix(n[k].i).local.format("yyyy-MM-dd HH:mm")

proc act(w: Win, id: int64, action: string, body: JNode, done: string): bool =
  try:
    discard w.a.call("POST", "/api/submissions/" & $id & "/" & action, body)
    w.toast(done)
    true
  except ApiError as e:
    w.toast(e.msg)
    false

var managePage* = ""     ## "" = the list of sections

proc approvals(w: Win, p: Page) =
  var subs: seq[JNode]
  try: subs = w.a.call("GET", "/api/submissions", nil, {"status": "open"}.toTable)["submissions"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  if subs.len == 0:
    p.dim("Nothing waits for approval.")
    return
  let lp1 = toSeq(subs)
  for lp1i in 0 ..< lp1.len:
    closureScope:
      let sub = lp1[lp1i]
      let id = sub["id"].i
      let conflict = sub["status"].s == "conflict"
      p.title(proposalTitle(sub))
      p.dim("by " & s(sub, "by_name") & " · " & sub.at("created") &
            (if s(sub, "request_note").len > 0: " · note: " & s(sub, "request_note") else: ""))
      for (lab, v) in proposalRows(sub): p.field(lab, v, readonly = true)
      if conflict: p.field("Held", "It clashes with the current value or another proposal: " & s(sub, "note"), readonly = true)
      var specs: seq[(string, proc ())]
      if sub["kind"].s == "photo" and sub.get("payload") != nil:
        let sha = s(sub["payload"], "file").split('.')[0]
        if w.a.n.store.blobHas(sha):
          let data = w.a.n.store.blobGet(sha)
          let cap = s(sub["payload"], "caption")
          specs.add ("Show the photo", proc () = w.showPhoto(data, cap))
      if w.isAdmin:
        specs.add ((if conflict: "Approve anyway" else: "Approve"), proc () =
          if w.act(id, "approve", newObj(@[("force", newBool(conflict))]), "Approved"): w.rebuildSide())
        if sub["kind"].s == "photo":
          specs.add ("Pick this photo", proc () =
            if w.act(id, "pick", newObj(), "Photo chosen, others rejected"): w.rebuildSide())
        specs.add ("Reject", proc () =
          if w.act(id, "reject", newObj(), "Rejected"): w.rebuildSide())
      p.buttons(specs)
      p.space()

proc myProposals(w: Win, p: Page) =
  var subs: seq[JNode]
  try: subs = w.a.call("GET", "/api/submissions", nil, {"status": "all", "limit": "200"}.toTable)["submissions"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  let mine = subs.filterIt(it["mine"].b)
  if mine.len == 0: p.dim("You have proposed nothing yet.")
  let lp2 = toSeq(mine)
  for lp2i in 0 ..< lp2.len:
    closureScope:
      let sub = lp2[lp2i]
      let id = sub["id"].i
      p.title(proposalTitle(sub))
      p.dim(sub["status"].s & " · " & sub.at("created") & (if s(sub, "note").len > 0: " · " & s(sub, "note") else: ""))
      for (lab, v) in proposalRows(sub): p.field(lab, v, readonly = true)
      if sub["status"].s in ["pending", "conflict"]:
        p.buttons(("Withdraw", proc () =
          if ask(w.hwnd, "Withdraw this proposal?", "") and w.act(id, "withdraw", newObj(), "Withdrawn"): w.rebuildSide()))
  let photosOpen = subs.filterIt(not it["mine"].b and it["kind"].s == "photo" and it["status"].s in ["pending", "conflict"])
  if photosOpen.len > 0:
    p.title("Photos waiting for approval")
    p.dim("Vote for the ones you find useful; an admin decides.")
    let lp3 = toSeq(photosOpen)
    for lp3i in 0 ..< lp3.len:
      closureScope:
        let sub = lp3[lp3i]
        let id = sub["id"].i
        let voted = sub.get("voted") != nil and sub["voted"].b
        p.label(s(sub, "target") & " · by " & s(sub, "by_name") & " · " & $(if sub.get("votes") != nil: sub["votes"].i else: 0) & " votes")
        p.buttons(((if voted: "Take back my vote" else: "Vote for this photo"), proc () =
          if w.act(id, "vote", newObj(), "Vote changed"): w.rebuildSide()))

proc history(w: Win, p: Page) =
  var revs: seq[JNode]
  try: revs = w.a.call("GET", "/api/revisions", nil, {"limit": "200"}.toTable)["revisions"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  p.dim("Newest first. Revert undoes one change; Restore goes back to the state just after a change.")
  if revs.len == 0: p.dim("No changes yet.")
  let lp4 = toSeq(revs)
  for lp4i in 0 ..< lp4.len:
    closureScope:
      let r = lp4[lp4i]
      let hid = r.get("hid")
      p.label(("#" & (if r.get("n") != nil: toText(r["n"]) else: "") & " " & s(r, "summary") & s(r, "note")).strip)
      p.dim(s(r, "by_name") & " · " & r.at("at") & (if s(r, "entity").len > 0: " · " & s(r, "entity") & " " & s(r, "key") else: ""))
      if hid != nil and not hid.isNull:
        let h = if hid.kind == jInt: $hid.i else: hid.s
        p.buttons(("Revert", proc () =
          if ask(w.hwnd, "Revert this change?", "This writes a new change that undoes it; History keeps both."):
            try:
              discard w.a.call("POST", "/api/revisions/" & h & "/revert", newObj())
              w.toast("Reverted")
              w.rebuildSide()
            except ApiError as e: w.toast(e.msg)),
          ("Restore", proc () =
            if ask(w.hwnd, "Restore to just after this change?", "Every later change is undone by new changes."):
              try:
                discard w.a.call("POST", "/api/restore", newObj(@[("hid", hid)]))
                w.toast("Restored")
                w.rebuildSide()
              except ApiError as e: w.toast(e.msg)))

proc people(w: Win, p: Page) =
  var users: seq[JNode]
  try: users = w.a.call("GET", "/api/users")["users"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  p.dim("Everyone who has an identity in this plant. Devices are added under Devices.")
  for u in users:
    p.label(s(u, "full_name") & " (" & s(u, "username") & ") · " & s(u, "role") &
            (if s(u, "position").len > 0: " · " & s(u, "position") else: ""))
  p.title("Add a person")
  p.dim("For someone whose device will join later (by QR code, request file or nearby admin).")
  let un = p.field("Username", "")
  let fn = p.field("Full name", "")
  let pos = p.field("Position (optional)", "")
  p.buttons(("Add", proc () =
    try:
      discard w.a.call("POST", "/api/users", newObj(@[("username", newStr(un.text.strip.toLowerAscii)),
        ("full_name", newStr(fn.text.strip)), ("position", newStr(pos.text.strip)), ("role", newStr("user"))]))
      w.toast("Added " & un.text.strip)
      w.rebuildSide()
    except ApiError as e: w.toast(e.msg)))

proc inviteWindow(w: Win) =
  var r: JNode
  try: r = w.a.call("POST", "/api/invites", newObj())
  except ApiError as e:
    w.toast(e.msg)
    return
  let code = r["code"].s
  let token = r["invite"]["token"].s
  var open = true
  var asked = false
  let (hw, p) = popup(w.hwnd, "Add a device with a QR code", 520, 820, proc () =
    open = false
    if not asked:
      try: discard w.a.call("POST", "/api/invites/" & token, newObj(@[("action", newStr("cancel"))]))
      except ApiError: discard)
  var side: cint
  let hb = qrBitmap(code.cstring, cint(px(6)), addr side)
  if hb != nil:
    let (img, _) = control(p.hwnd, "STATIC", "QR code of the invite", SS_BITMAP)
    SendMessageW(img, STM_SETIMAGE, 0, cast[LPARAM](hb))
    p.custom(img, int(side) * 96 div dpi)
  p.dim("Scan this with the new phone, or copy the text to the new computer (Join with a code). Valid for 15 minutes, for one device.")
  p.multiField("Invite text", code, 110, readonly = true)
  let status = p.label("Waiting for a device…")
  proc send(action: string) =
    try:
      discard w.a.call("POST", "/api/invites/" & token, newObj(@[("action", newStr(action)), ("existing_ok", newBool(true))]))
      status.setText(if action == "accept": "Accepted: the device syncs now." else: "Refused.")
    except ApiError as e: w.toast(e.msg)
  p.buttons(("Accept", proc () {.closure.} = send("accept")), ("Refuse", proc () {.closure.} = send("refuse")))
  p.layout()
  ShowWindow(hw, SW_SHOW)
  proc watch() {.async.} =
    while open:
      await sleepAsync(2000)
      if not open: break
      try:
        let st = w.a.call("GET", "/api/invites/" & token)
        case st["state"].s
        of "asked":
          if not asked:
            asked = true
            let req = st["request"]
            status.setText("A device asks to join: " & s(req, "full_name") & " (" & s(req, "username") & "), " &
                           s(req, "label") & (if not st["existing"].isNull: ". That username exists: it becomes their new device." else: "") &
                           ". Accept or Refuse below.")
        of "expired":
          status.setText("Expired. Close this and make a new one.")
          break
        of "accepted", "refused": break
        else: discard
      except ApiError: break
  asyncCheck watch()

proc devices(w: Win, p: Page) =
  var d: JNode
  try: d = w.a.call("GET", "/api/devices")
  except ApiError as e:
    p.dim(e.msg)
    return
  proc rows(list: JNode, title: string) =
    if list == nil or list.kind != jArr: return
    p.title(title)
    let lp5 = toSeq(list.elems)
    for lp5i in 0 ..< lp5.len:
      closureScope:
        let x = lp5[lp5i]
        let dev = s(x, "device")
        let me = x["this_computer"].b
        p.label((if s(x, "label").len > 0: s(x, "label") else: "device") & " · " & s(x, "username") &
                (if me: " (this device)" else: "") & "   " & dev[0 ..< min(16, dev.len)] & "…" & (if x["revoked"].b: " · removed" else: ""))
        if not x["revoked"].b and not me:
          p.buttons(("Remove " & (if s(x, "label").len > 0: s(x, "label") else: "device") & " of " & s(x, "username"), proc () =
            if ask(w.hwnd, "Remove this device?", "It stops receiving data, and wipes the plant from itself if it ever connects again."):
              try:
                discard w.a.call("POST", "/api/devices/revoke", newObj(@[("device", newStr(dev))]))
                w.toast("Removed")
                w.rebuildSide()
              except ApiError as e: w.toast(e.msg)))
  rows(d.get("mine"), "Your devices")
  if not w.isAdmin: return
  rows(d.get("all"), "All devices")
  try:
    let reqs = w.a.call("GET", "/api/join-requests")["requests"].elems
    if reqs.len > 0:
      p.title("Waiting to join")
      p.dim("Accept only if the code on the other device is the same.")
      let lp6 = toSeq(reqs)
      for lp6i in 0 ..< lp6.len:
        closureScope:
          let r = lp6[lp6i]
          let dev = s(r, "device")
          let req = r["request"]
          p.label(s(req, "full_name") & " (" & s(req, "username") & ") · " & s(req, "label") & " · code " & s(r, "code"))
          proc decide(act: string) =
            try:
              discard w.a.call("POST", "/api/join-requests/" & dev, newObj(@[("action", newStr(act)), ("existing_ok", newBool(true))]))
              w.toast(if act == "accept": "Accepted" else: "Refused")
              w.rebuildSide()
            except ApiError as e: w.toast(e.msg)
          p.buttons(("Accept " & s(req, "username"), proc () {.closure.} = decide("accept")), ("Refuse " & s(req, "username"), proc () {.closure.} = decide("refuse")))
  except ApiError: discard
  p.title("Add a device with a QR code")
  p.dim("The new device scans it, or you copy its text over.")
  p.buttons(("Show an invite…", proc () = w.inviteWindow()))
  p.title("Add a device from a request file")
  p.dim("Someone made a join request (.kksjoin) on their device and sent it to you.")
  p.buttons(("Open a join request…", proc () =
    let path = openFile(w.hwnd, "Open a join request", "Join requests|*.kksjoin|All files|*.*")
    if path.len == 0: return
    try:
      let req = parseStrict(readFile(path))
      discard w.a.call("POST", "/api/devices/import-request", newObj(@[("request", req), ("existing_ok", newBool(true))]))
      w.toast("The device is certified; it joins with its next sync (or send it a bundle).")
      w.rebuildSide()
    except CatchableError as e: w.toast(e.msg)),
    ("Save a bundle for it…", proc () =
      let path = saveFile(w.hwnd, "Save a bundle", "Bundles|*.kksbundle", "plant.kksbundle", "kksbundle")
      if path.len == 0: return
      try:
        let r = w.a.api.handle(w.a.me[1], "GET", "/api/bundle", initTable[string, string](), newObj(), nowMs())
        writeFile(path, r.bytes)
        w.toast("Saved. The bundle holds the plant's data unencrypted: hand it over directly.")
      except CatchableError as e: w.toast(e.msg)))

proc account(w: Win, p: Page) =
  let (_, me) = w.a.me
  p.title("Your details")
  p.field("Username", me.username, readonly = true)
  p.field("Role", me.role, readonly = true)
  let fn = p.field("Full name", me.fullName)
  let pos = p.field("Position", if me.position.isStr: me.position.s else: "")
  p.buttons(("Save", proc () =
    try:
      discard w.a.call("POST", "/api/profile", newObj(@[("full_name", newStr(fn.text.strip)), ("position", newStr(pos.text.strip))]))
      w.toast("Saved")
    except ApiError as e: w.toast(e.msg)))
  p.title("Sync")
  p.dim("Devices on the same network find each other; others can be reached by address.")
  let snap = w.a.snapshot
  p.field("This device", w.a.n.device[0 ..< 16] & "… · sync port " & (if snap["port"].kind == jInt: $snap["port"].i else: "off"), readonly = true)
  let addr0 = p.field("Sync with an address (host:port@device)", "")
  p.buttons(("Sync now", proc () =
    let t = addr0.text.strip
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
  if me.role != "manager": return
  # PROTOCOL-v2 §18: the plant's relay, a setting every device learns at its next sync
  let rv = w.a.n.run.settings.getOrDefault("relay")
  let relay = p.field("Internet relay (wss://…), empty = off", if rv != nil and rv.isStr: rv.s else: "")
  p.buttons(("Save relay", proc () =
    try:
      discard w.a.call("POST", "/api/settings/relay", newObj(@[("url", newStr(relay.text.strip))]))
      w.toast(if relay.text.strip.len == 0: "Relay removed" else: "Relay saved: every device learns it at its next sync")
    except ApiError as e: w.toast(e.msg)))
  p.title("Root key")
  p.dim("The plant's root key signs the manager role and settles stolen devices. Keep an encrypted copy offline (a USB " &
        "stick in a drawer). Its passphrase is made for you (80 bits, decision 0023, issue #29): write it down and keep " &
        "it apart.")
  let has = w.a.store.getRow("keys", "root") != nil
  p.field("On this device", if has: "yes" else: "no (it is on another device of the manager)", readonly = true)
  if has:
    let shown = p.field("Passphrase of the backup just saved", "", readonly = true)
    p.buttons(("Save an encrypted backup…", proc () =
      let path = saveFile(w.hwnd, "Save the root key backup", "Root key backups|*.kksroot", "root-key.kksroot", "kksroot")
      if path.len == 0: return
      try:
        let pass = w.a.p.newBackupPassphrase()
        let rk = toText(w.a.store.getRow("keys", "root"))
        let sealed = w.a.p.passphraseSeal(pass, rk.toBytes)
        writeFile(path, toText(newObj(@[("kks_root_backup", newInt(2)), ("plant", newStr(w.a.plantName)),
                                        ("root", newStr(w.a.n.root)), ("sealed", sealed)])))      # the GNOME app's format
        shown.setText(pass)
        w.toast("Saved. Write down the passphrase shown above: it is not kept anywhere. Test the backup once with Restore.")
      except CatchableError as e: w.toast(e.msg)))
  let pw1 = p.field("Passphrase of the backup to restore", "", password = true)
  p.buttons(("Restore from a backup…", proc () =
    let path = openFile(w.hwnd, "Open a root key backup", "Root key backups|*.kksroot|All files|*.*")
    if path.len == 0: return
    try:
      let doc = parseStrict(readFile(path))
      if doc.get("root") == nil or doc["root"].s != w.a.n.root:
        w.toast("That backup belongs to another plant")
        return
      let plain = w.a.p.passphraseOpen(pw1.text, doc["sealed"])
      var txt = newString(plain.len)
      for i, b in plain: txt[i] = char(b)
      w.a.store.putRow("keys", "root", parseStrict(txt))
      w.toast("The root key is on this device now")
    except CatchableError:
      w.toast("Wrong passphrase, or not a root key backup")))

proc GlobalAlloc(flags: UINT, n: csize_t): pointer {.importc, stdcall, header: "<windows.h>".}
proc GlobalLock(h: pointer): pointer {.importc, stdcall, header: "<windows.h>".}
proc GlobalUnlock(h: pointer): BOOL {.importc, stdcall, header: "<windows.h>", discardable.}
proc SetClipboardData(fmt: UINT, h: pointer): pointer {.importc, stdcall, header: "<windows.h>", discardable.}

proc copyText(w: Win, text: string) =
  ## text to the clipboard as CF_UNICODETEXT (the clipboard owns the memory after SetClipboardData)
  let wide = newWideCString(text)
  let bytes = (wide.len + 1) * 2
  if OpenClipboard(w.hwnd) == 0: return
  EmptyClipboard()
  let h = GlobalAlloc(0x0002, csize_t(bytes))      # GMEM_MOVEABLE
  if h != nil:
    copyMem(GlobalLock(h), cast[pointer](wide[0].addr), bytes)
    GlobalUnlock(h)
    SetClipboardData(13, h)                        # CF_UNICODETEXT
  CloseClipboard()
  w.toast("Copied")

proc diagnosticsSection(w: Win, p: Page) =
  ## decision 0040: everyone sees whether reports are on; the manager switches them from their own device
  var d: JNode
  try: d = w.a.call("GET", "/api/diagnostics")
  except ApiError: return
  let on = d["on"].kind == jBool and d["on"].b
  p.title("Diagnostics reports")
  p.dim(if on: "On: this computer sends the manager short error reports (crashes, failed syncs, app errors). Never plant data or passwords."
        else: "Off: this computer sends no error reports.")
  if w.a.me[1].role == "manager" and d.get("can_switch") != nil and d["can_switch"].b:
    let label = if on: "Switch reports off" else: "Switch reports on"
    p.buttons((label, proc () =
      try:
        discard w.a.call("POST", "/api/diagnostics", newObj(@[("on", newBool(not on))]))
        w.toast(if on: "Reports off" else: "Reports on: every device learns it at its next sync")
        w.rebuildSide()
      except ApiError as e: w.toast(e.msg)))

proc diagnosticsReports(w: Win, p: Page) =
  ## the manager's reports, newest first, each with Copy (for Claude); "Copy all" on top
  var d: JNode
  try: d = w.a.call("GET", "/api/diagnostics")
  except ApiError as e:
    p.dim(e.msg)
    return
  let reports = if d.get("reports") != nil: d["reports"] else: newArr()
  if not (d["on"].kind == jBool and d["on"].b): p.dim("Reports are off (Account → Diagnostics reports).")
  if d.get("can_read") != nil and not d["can_read"].b:
    p.dim("This device holds no report key yet. Reports open on the device you switched them on from, and on your " &
          "other devices after they synced with it.")
  if reports.len == 0:
    p.dim("No reports yet.")
    return
  let all = toText(reports)
  p.buttons(("Copy all reports (for Claude)", proc () = w.copyText(all)))
  let lp = reports.elems
  for i in 0 ..< lp.len:
    closureScope:
      let r = lp[i]
      let rep = r["report"]
      p.title((if r["username"].s.len > 0: r["username"].s else: "?") & " · " & (if r["label"].s.len > 0: r["label"].s else: "device") &
              " · " & fromUnix(r["at"].i div 1000).local.format("yyyy-MM-dd HH:mm"))
      if rep.kind != jObj: p.dim("Not readable here: sealed to a report key this device doesn't hold.")
      else:
        p.dim(rep["app"].s & " " & rep["version"].s & " · " & rep["platform"].s)
        for j, ev in rep["events"].elems:
          if j >= 30: break
          let n = if ev.get("n") != nil: ev["n"].i else: 1
          p.label(ev["kind"].s & (if n > 1: " ×" & $n else: "") & " · " & fromUnix(ev["at"].i div 1000).local.format("MM-dd HH:mm") &
                  " · " & ev["text"].s.splitLines()[0])
      let one = toText(r)
      p.buttons(("Copy", proc () = w.copyText(one)))

proc manageTab*(w: Win, p: Page) =
  if managePage.len > 0:
    p.buttons(("‹ Manage", proc () =
      managePage = ""
      w.rebuildSide()))
    p.title(managePage)
    case managePage
    of "Approvals": w.approvals(p)
    of "My proposals": w.myProposals(p)
    of "History": w.history(p)
    of "People": w.people(p)
    of "Devices": w.devices(p)
    of "Account":
      w.account(p)
      w.diagnosticsSection(p)
    of "Diagnostics": w.diagnosticsReports(p)
    else: discard
    return
  p.title("Manage")
  var pages: seq[(string, string)]
  if w.isAdmin: pages.add ("Approvals", "Proposals waiting for a decision")
  pages.add ("My proposals", "What you proposed, and photos to vote on")
  if w.isAdmin:
    pages.add ("History", "Every change, with revert and restore")
    pages.add ("People", "Accounts and roles")
  pages.add ("Devices", "Your devices" & (if w.isAdmin: ", all devices, joining" else: ""))
  pages.add ("Account", "Your details, sync" & (if w.a.me[1].role == "manager": ", root key" else: ""))
  if w.a.me[1].role == "manager": pages.add ("Diagnostics", "Error reports from the plant's devices")
  let lp7 = toSeq(pages)
  for lp7i in 0 ..< lp7.len:
    closureScope:
      let (title, sub) = lp7[lp7i]
      let t = title
      p.buttons((t, proc () =
        managePage = t
        w.rebuildSide()))
      p.dim(sub)

proc liveManage*(): bool = managePage in ["Approvals", "My proposals", "History", "Devices", "Diagnostics"]
