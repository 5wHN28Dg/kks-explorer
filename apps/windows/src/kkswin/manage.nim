## Manage (R10–R14; the GNOME app's manage.nim): approvals, my proposals, history with revert and restore, people,
## devices (join requests, invites with a QR code, request files, bundles, removal), and the account (details, sync,
## the root key backup). Everything goes through the core's local API, like admin.html.

import std/[strutils, tables, times, sequtils, asyncdispatch, math, algorithm]
import kks/[json, api, node, extras, util]
import kksl/[dbstore, passphrase]
import kks/model
import proposals, histline
import appstate
import w32, ui, win, photos, about

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

proc openTag(w: Win, code, tag: string) =
  ## a proposal's code on the P&ID: its tag (tags.json with reviews, or a marked tag), else any tag with that code
  var id = tag
  if id.len == 0 or not w.m.tagById(id)[0]:
    id = ""
    for t in w.m.tags:
      if code.len > 0 and t.full == code:
        id = t.id
        break
  if id.len == 0:
    w.toast("That code is on no drawing")
    return
  w.selectTag(id, true)       # it shows the sheet itself, after asking whether to drop a selection

proc codeTitle(code, tag: string): string =
  if code.len > 0: code elif tag.len > 0: "Tag without a code" else: "Other"

proc openButton(w: Win, p: Page, code, tag: string) =
  ## the code's card opens its tag on the drawing
  if code.len == 0 and tag.len == 0: return
  p.buttons(("Open " & (if code.len > 0: code else: "this tag") & " on the drawing", proc () = w.openTag(code, tag)))

proc photoButton(w: Win, sub: JNode, specs: var seq[(string, proc ())]) =
  if sub["kind"].s == "photo" and sub.get("payload") != nil:
    let sha = s(sub["payload"], "file").split('.')[0]
    if sha.len > 0 and w.a.n.store.blobHas(sha):
      let data = w.a.n.store.blobGet(sha)
      let cap = s(sub["payload"], "caption")
      specs.add ("Show the photo", proc () = w.showPhoto(data, cap))

# Approvals, several at once (the user, 2026-11-15: "accept/deny multiple requests at once"): a tick per proposal and,
# at the top, Select all, how many are ticked, Approve selected and Reject selected (Reject asks once). The ticks are
# kept by id over the page's rebuilds (a sync rebuilds it); the ones no longer waiting are dropped.
var
  picked: seq[int64]                ## the ticked proposals' ids
  pickCompeting: seq[int64]       ## photos of one kind that compete for their code (Pick): never approved by the batch
  pickSubs: seq[JNode]              ## the waiting proposals as last drawn, oldest first
  pickChecks: seq[(int64, HWND)]    ## each one's tick
  pickAll, pickCount, pickOk, pickNo: HWND
  pickPage: Page                    ## their page (laid out again when a button's label grows with its count)
  pickWide = -1                     ## the length of the labels the page was last laid out for
  pickBusy = false                  ## a batch is running (one proposal per turn of the message loop)
  lastSaid = ""                     ## the last batch's result, on the page until the next batch (the status line is one line)
  lastSaidAt = 0.0                  ## when it was said

proc pickGone() =
  ## the bar's controls went with their page (another page was opened, or this one is being made again)
  if pickAll != nil and IsWindow(pickAll) == 0:
    pickAll = nil
    pickCount = nil
    pickOk = nil
    pickNo = nil
    pickPage = nil

proc pickShow() =
  let n = picked.len
  pickGone()
  if pickAll == nil: return
  SendMessageW(pickAll, BM_SETCHECK, WPARAM(ord(n > 0 and n == pickSubs.len)), 0)
  pickCount.setText(if n > 0: $n & " selected" else: "None selected")
  pickOk.setText("Approve selected" & (if n > 0: " (" & $n & ")" else: ""))
  pickNo.setText("Reject selected" & (if n > 0: " (" & $n & ")" else: ""))
  EnableWindow(pickOk, BOOL(n > 0 and not pickBusy))
  EnableWindow(pickNo, BOOL(n > 0 and not pickBusy))
  # A button is as wide as its label when the page is laid out ("(20)" was cut): laid out again when the count takes
  # more or fewer characters, not at every tick. The two buttons are a line each, so nothing under them moves; the
  # page and its controls are painted again all the same (a control laid over another's old place left pieces behind).
  let wide = (if n > 0: len($n) else: 0)
  if pickPage != nil and wide != pickWide:
    pickWide = wide
    pickPage.layout()
    RedrawWindow(pickPage.hwnd, nil, nil, RDW_INVALIDATE or RDW_ERASE or RDW_ALLCHILDREN)

proc runBatch(w: Win, action: string, chosen: seq[JNode])

proc decideMany(w: Win, action: string) =
  ## every ticked proposal, oldest first, each as its own button sends it (approve without force, reject). A held one
  ## (it clashes with the value as it is now) is not approved here: its own "Approve anyway" does that.
  var chosen: seq[JNode]
  for sub in pickSubs:
    if sub["id"].i in picked: chosen.add sub
  if chosen.len == 0:
    w.toast("Nothing selected")
    return
  if action == "reject":
    # one question, in a window of the app's own: the button names the action, Cancel has the focus, Escape cancels
    # (standard buttons a screen reader and UI Automation reach as anywhere else in the app)
    let what = if chosen.len == 1: "1 proposal" else: $chosen.len & " proposals"
    # The app's window takes no input while the question is open (as under any dialog), so the page isn't left with
    # the question open; whatever still gets through (another window of the app) meets the checks below: only what
    # was asked about and is still ticked is rejected, and one batch at a time.
    var hw: HWND
    let (h, p) = popup(w.hwnd, "Reject " & what & "?", 460, 220, proc () =
      EnableWindow(w.hwnd, 1)
      SetForegroundWindow(w.hwnd), escape = true)
    hw = h
    p.title("Reject " & what & "?")
    p.dim("Each one is rejected as its own Reject button does. The submitters see that it was rejected.")
    let ids = chosen.mapIt(it["id"].i)
    # (the app's window is enabled before the question goes: Windows would otherwise activate another app's)
    let bs = p.buttons(("Cancel", proc () =
                         EnableWindow(w.hwnd, 1)
                         DestroyWindow(hw)),
                       ("Reject " & what, proc () =
                         EnableWindow(w.hwnd, 1)
                         DestroyWindow(hw)
                         w.runBatch("reject", pickSubs.filterIt(it["id"].i in ids and it["id"].i in picked))))
    p.layout()
    EnableWindow(w.hwnd, 0)
    ShowWindow(h, SW_SHOW)
    SetFocus(bs[0])
    return
  w.runBatch(action, chosen)

proc runBatch(w: Win, action: string, chosen: seq[JNode]) =
  if chosen.len == 0: return
  if pickBusy: return
  pickBusy = true
  pickShow()       # (both buttons off while it runs; nothing if their page has gone)
  # one proposal per turn of the message loop, saying how far it got: the window stays live during a long batch
  var done, i = 0
  var held, competing, failed: seq[string]
  var step: proc ()
  step = proc () =
    if i < chosen.len:
      let sub = chosen[i]
      inc i
      let id = sub["id"].i
      if action == "approve" and sub["status"].s == "conflict":
        held.add "#" & $id
      elif action == "approve" and id in pickCompeting:
        competing.add "#" & $id
      else:
        pickGone()
        if pickCount != nil:
          pickCount.setText((if action == "approve": "Approving " else: "Rejecting ") & $i & " of " & $chosen.len & "…")
        try:
          discard w.a.call("POST", "/api/submissions/" & $id & "/" & action, newObj())
          inc done
          picked.keepItIf(it != id)
        except CatchableError as e:      # (anything else than the server's answer too: the batch must end and say so)
          failed.add "#" & $id & ": " & e.msg
      later(step)
      return
    pickBusy = false
    var msg = (if action == "approve": "Approved " else: "Rejected ") & $done & " of " & $chosen.len & "."
    if held.len > 0:
      msg.add " Not approved: " & held.join(", ") & (if held.len == 1: " clashes" else: " clash") &
              " with the value as it is now; decide " & (if held.len == 1: "it on its" else: "them on their") & " own."
    if competing.len > 0:
      msg.add " Not approved: " & competing.join(", ") & ": several photos of one kind compete for " &
              (if competing.len == 1: "its" else: "their") & " code; choose with “Use this one”."
    if failed.len > 0: msg.add " Not done: " & failed.join("; ") & "."
    lastSaid = msg
    lastSaidAt = epochTime()
    w.toast(msg)
    pickShow()          # (the bar as it is now, should the page wait for the keyboard to leave one of its fields)
    w.sideChanged()     # (not rebuildSide: the person may be typing on another page by now, #168)
  later(step)

proc approvals(w: Win, p: Page) =
  ## the user's "Approvals page clean-up" (2026-10-08): one card per code (or per tag without one), the proposals in it
  ## by kind (/api/submissions?group=code); "Use this one" and votes only where several photos of one kind compete
  ## (an equipment photo and a tag plate photo are not rivals), Approve and Reject otherwise; the submitter's full
  ## name; the code opens its tag on the drawing
  var groups: seq[JNode]
  try: groups = w.a.call("GET", "/api/submissions", nil, {"status": "open", "group": "code", "limit": "1000"}.toTable)["groups"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  pickChecks.setLen(0)
  pickSubs.setLen(0)
  pickAll = nil
  pickCount = nil
  pickOk = nil
  pickNo = nil
  pickPage = nil
  pickCompeting.setLen(0)
  for grp in groups:
    for k in grp["kinds"].elems:
      for sub in k["items"].elems:
        pickSubs.add sub
        if k.get("pick") != nil and k["pick"].kind == jBool and k["pick"].b: pickCompeting.add sub["id"].i
  pickSubs.sort(proc (a, b: JNode): int = cmp(a["created"].i, b["created"].i))
  var open: seq[int64]
  for sub in pickSubs: open.add sub["id"].i
  picked.keepItIf(it in open)
  if groups.len == 0:
    p.dim("Nothing waits for approval.")
    # (the batch that emptied the list: what it did, for the next two minutes; said once it went at the next sync's
    # rebuild, a second later, and kept for good it stood there stale)
    if w.isAdmin and lastSaid.len > 0 and epochTime() - lastSaidAt < 120: p.label(lastSaid)
    return
  p.dim("One card per tag. Approving applies the change and records it in History, where it can be reverted. " &
        "Tick several to approve or reject them at once.")
  if w.isAdmin:
    pickAll = p.check("Select all (" & $pickSubs.len & ")", false, proc (on: bool) =
      picked.setLen(0)
      if on:
        for sub in pickSubs: picked.add sub["id"].i
      for (_, cb) in pickChecks: SendMessageW(cb, BM_SETCHECK, WPARAM(ord(on)), 0)
      pickShow())
    pickCount = p.dim("None selected")
    # (a line each: side by side they took a second line when the count made them wider, and everything under
    # them, the tick just pressed too, moved down)
    pickOk = p.buttons(("Approve selected", proc () = w.decideMany("approve")))[0]
    pickNo = p.buttons(("Reject selected", proc () = w.decideMany("reject")))[0]
    pickPage = p
    pickWide = -1
    if lastSaid.len > 0: p.label(lastSaid)
    pickShow()
  for gi in 0 ..< groups.len:
    closureScope:
      let grp = groups[gi]
      let code = s(grp, "code")
      let tag = s(grp, "tag")
      p.title(codeTitle(code, tag))
      w.openButton(p, code, tag)
      let kinds = grp["kinds"].elems
      for ki in 0 ..< kinds.len:
        closureScope:
          let kd = kinds[ki]
          let pick = kd.get("pick") != nil and kd["pick"].kind == jBool and kd["pick"].b
          let items = kd["items"].elems
          let lab = s(kd, "label")
          p.label(lab & (if items.len > 1: " (" & $items.len & ")" else: ""))
          if pick:
            p.dim("Several proposed. “Use this one” approves it and rejects the other " & lab.toLowerAscii &
                  "s of this code; Add approves it and keeps the others. Votes are only a hint.")
          for ii in 0 ..< items.len:
            closureScope:
              let sub = items[ii]
              let id = sub["id"].i
              let conflict = sub["status"].s == "conflict"
              let votes = if sub.get("votes") != nil and sub["votes"].kind == jInt: sub["votes"].i else: 0
              let who = if s(sub, "by_name").len > 0: s(sub, "by_name") else: s(sub, "by")
              p.label(proposalTitle(sub))
              p.dim("#" & $id & " · by " & who & " · " & sub.at("created") &
                    (if pick: " · " & $votes & (if votes == 1: " vote" else: " votes") else: "") &
                    (if s(sub, "request_note").len > 0: " · note: " & s(sub, "request_note") else: ""))
              for (lab2, v) in proposalRows(sub): p.field(lab2, v, readonly = true)
              if conflict: p.field("Held", "It clashes with the current value or another proposal: " & s(sub, "note"), readonly = true)
              if w.isAdmin:
                let cb = p.check("Select #" & $id, id in picked, proc (on: bool) =
                  if on:
                    if id notin picked: picked.add id
                  else: picked.keepItIf(it != id)
                  pickShow())
                pickChecks.add (id, cb)
                p.space(2)      # (8 px between the tick and the row with Reject under it)
              var specs: seq[(string, proc ())]
              w.photoButton(sub, specs)
              if w.isAdmin:
                if pick:
                  specs.add ("Use this one", proc () =
                    if w.act(id, "pick", newObj(), "Photo chosen; the other " & lab.toLowerAscii & "s of this code were rejected"):
                      w.rebuildSide())
                  specs.add ("Add", proc () =
                    if w.act(id, "approve", newObj(), "Added"): w.rebuildSide())
                else:
                  specs.add ((if conflict: "Approve anyway" else: "Approve"), proc () =
                    if w.act(id, "approve", newObj(@[("force", newBool(conflict))]), "Approved"): w.rebuildSide())
                specs.add ("Reject", proc () =
                  if w.act(id, "reject", newObj(), "Rejected"): w.rebuildSide())
              if specs.len > 0: p.buttons(specs)
      p.space()

const StatusChoices = [("All", "all"), ("Waiting", "pending"), ("Held (clashes)", "conflict"), ("Approved", "approved"),
                       ("Rejected", "rejected"), ("Withdrawn", "withdrawn")]
const KindChoices = [("All kinds", "", ""), ("Equipment photos", "equipment_photo", ""), ("Tag plate photos", "plate_photo", ""),
                     ("Places and notes (any field)", "equipment", ""), ("Floor", "equipment", "floor"),
                     ("Notes", "equipment", "notes"), ("Other fields", "equipment", "custom"),
                     ("Procedure links", "link", ""), ("Tag readings", "review", ""), ("Marked tags", "tag_add", ""),
                     ("Removals", "photo_delete,tag_remove", "")]
var
  mineStatus, mineKind = 0      ## My proposals' filters, kept while the app runs
  focusFilter = ""              ## the filter just changed: its choice gets the focus back after the page is rebuilt

proc statusName(st: string): string =
  case st
  of "pending": "waiting for approval"
  of "conflict": "held: it clashes"
  else: st

proc myProposals(w: Win, p: Page) =
  ## the user's "My proposals: filters" (2026-10-08): status, kind and field, filtered by the core
  ## (/api/submissions?mine=1&status=…&kind=…&field=…), the list grouped by code; then others' photos to vote on
  p.label("Status")
  let st = p.chips(StatusChoices.mapIt(it[0]), mineStatus, proc (i: int) =
    mineStatus = i
    focusFilter = "status"
    w.rebuildSide())
  p.label("Kind")
  let kd = p.chips(KindChoices.mapIt(it[0]), mineKind, proc (i: int) =
    mineKind = i
    focusFilter = "kind"
    w.rebuildSide())
  if focusFilter == "status": later(proc () = SetFocus(st[mineStatus]))
  elif focusFilter == "kind": later(proc () = SetFocus(kd[mineKind]))
  focusFilter = ""
  let (_, kind, field) = KindChoices[mineKind]
  var q = {"status": StatusChoices[mineStatus][1], "mine": "1", "limit": "500"}.toTable
  if kind.len > 0: q["kind"] = kind
  if field.len > 0: q["field"] = field
  var subs: seq[JNode]
  try: subs = w.a.call("GET", "/api/submissions", nil, q)["submissions"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  if subs.len == 0:
    p.dim(if mineStatus == 0 and mineKind == 0: "You have proposed nothing yet." else: "None of your proposals match.")
  else:
    var order: seq[string]
    var per: Table[string, seq[JNode]]
    for x in subs:
      let key = if s(x, "code").len > 0: s(x, "code") else: "tag:" & s(x, "tag")
      if key notin per: order.add key
      per.mgetOrPut(key, @[]).add x
    p.dim($subs.len & (if subs.len == 1: " proposal" else: " proposals") & ", " & $order.len &
          (if order.len == 1: " code" else: " codes"))
    for key in order:
      let items = per[key]
      p.title(codeTitle(s(items[0], "code"), s(items[0], "tag")))
      w.openButton(p, s(items[0], "code"), s(items[0], "tag"))
      for i in 0 ..< items.len:
        closureScope:
          let sub = items[i]
          let id = sub["id"].i
          let stt = sub["status"].s
          p.label(proposalTitle(sub) & (if s(sub, "photo_kind") == "plate": " (tag plate)" else: ""))
          p.dim(statusName(stt) & " · " & sub.at("created") &
                (if s(sub, "note").len > 0 and stt != "conflict": " · " & s(sub, "note") else: ""))
          for (lab, v) in proposalRows(sub): p.field(lab, v, readonly = true)
          var specs: seq[(string, proc ())]
          w.photoButton(sub, specs)
          if stt in ["pending", "conflict"]:
            specs.add ("Withdraw", proc () =
              if ask(w.hwnd, "Withdraw this proposal?", "") and w.act(id, "withdraw", newObj(), "Withdrawn"): w.rebuildSide())
          if specs.len > 0: p.buttons(specs)
      p.space(6)
  # photos others proposed: members vote where several photos of one kind compete for a code
  var groups: seq[JNode]
  try: groups = w.a.call("GET", "/api/submissions", nil, {"status": "open", "kind": "photo", "group": "code"}.toTable)["groups"].elems
  except ApiError: return
  var cands: seq[JNode]
  for grp in groups:
    for k in grp["kinds"].elems:
      if k.get("pick") != nil and k["pick"].kind == jBool and k["pick"].b:
        for x in k["items"].elems:
          if not x["mine"].b: cands.add x
  if cands.len > 0:
    p.title("Photos to vote on")
    p.dim("Several photos of the same kind wait for these codes. Vote for the ones you find useful; an admin picks one.")
    for i in 0 ..< cands.len:
      closureScope:
        let sub = cands[i]
        let id = sub["id"].i
        let voted = sub.get("voted") != nil and sub["voted"].kind == jBool and sub["voted"].b
        p.label(s(sub, "code") & " · " & (if s(sub, "photo_kind") == "plate": "tag plate" else: "equipment") &
                " photo by " & s(sub, "by_name") & " · " & $(if sub.get("votes") != nil: sub["votes"].i else: 0) & " votes")
        p.buttons(((if voted: "Take back my vote" else: "Vote for this photo"), proc () =
          if w.act(id, "vote", newObj(), "Vote changed"): w.rebuildSide()))

proc leaderboard(w: Win, p: Page) =
  ## the user's "Leaderboard" (2026-10-08), /api/leaderboard, every member: a name and numbers per person, nothing
  ## else (the core leaves out IDs, usernames, roles)
  var d: JNode
  try: d = w.a.call("GET", "/api/leaderboard")
  except ApiError as e:
    p.dim(e.msg)
    return
  p.dim("Everyone's proposals and direct changes, counted from the whole plant log. Sorted by approved, then total.")
  let people = if d.get("people") != nil: d["people"].elems else: @[]
  if people.len == 0:
    p.dim("Nobody has proposed anything yet.")
    return
  proc num(n: JNode, k: string): int64 =
    if n != nil and n.get(k) != nil and n[k].kind == jInt: n[k].i else: 0
  proc fnum(n: JNode, k: string): float =
    if n == nil or n.get(k) == nil: return -1
    case n[k].kind
    of jFloat: n[k].f
    of jInt: float(n[k].i)
    else: -1
  let kinds = d.get("kinds")
  for x in people:
    let name = if s(x, "name").len > 0: s(x, "name") else: "?"
    p.title($num(x, "rank") & ". " & name)
    let rate = fnum(x, "approval_rate")
    p.label($num(x, "approved") & " approved · " & $num(x, "pending") & " waiting · " & $num(x, "rejected") &
            " rejected · " & $num(x, "total") & " in all" & (if rate >= 0: " · " & $int(round(rate * 100)) & " % approved" else: ""))
    if num(x, "direct") > 0: p.dim($num(x, "direct") & " made directly as an admin")
    if num(x, "withdrawn") > 0: p.dim($num(x, "withdrawn") & " withdrawn")
    if num(x, "decided") > 0: p.dim($num(x, "decided") & " decided as an approver")
    if num(x, "votes") > 0 or num(x, "comments") > 0:
      p.dim($num(x, "votes") & " votes · " & $num(x, "comments") & " comments")
    let ks = x.get("kinds")
    if kinds != nil and kinds.kind == jObj and ks != nil and ks.kind == jObj:
      for (k, lab) in kinds.fields:
        let c = ks.get(k)
        if num(c, "total") == 0: continue
        p.dim((if lab.isStr: lab.s else: k) & ": " & $num(c, "approved") & " approved of " & $num(c, "total") &
              (if num(c, "pending") > 0: ", " & $num(c, "pending") & " waiting" else: "") &
              (if num(c, "rejected") > 0: ", " & $num(c, "rejected") & " rejected" else: ""))
    if x.get("last") != nil and x["last"].kind == jInt and x["last"].i > 0: p.dim("Last: " & x.at("last"))

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
      p.label(isolatesAsEmbeddings(historyTitle(r)))   # GDI draws isolates as boxes
      p.dim(historyBy(r))
      if historyUndoable(r):
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

var showHidden = false     ## Devices and People: also the removed ones an admin hid (this run only)

proc hide(w: Win, body: JNode, done: string) =
  ## POST /api/hidden (the user, 2026-10-08: "Remove deleted users and devices"): display only, a setting of this
  ## device; the log and History keep everything. The leaderboard leaves out hidden people who are no longer active (core
  ## leaderboardWalk)
  try:
    let r = w.a.call("POST", "/api/hidden", body)
    let n = if r.get("changed") != nil and r["changed"].kind == jInt: r["changed"].i else: -1
    w.toast(if body.get("clear_removed") != nil: (if n == 0: "Nothing removed to clear" else: "Cleared " & $n & " removed")
            else: done)
    w.rebuildSide()
  except ApiError as e: w.toast(e.msg)

proc hiddenControls(w: Win, p: Page, nHidden: int) =
  ## "Clear removed" and "Show hidden (n)" (admins)
  var specs: seq[(string, proc ())]
  specs.add ("Clear removed", proc () = w.hide(newObj(@[("clear_removed", newBool(true))]), ""))
  if nHidden > 0 or showHidden:
    specs.add ((if showHidden: "Hide hidden" else: "Show hidden (" & $nHidden & ")"), proc () =
      showHidden = not showHidden
      w.rebuildSide())
  p.buttons(specs)
  p.dim("Clear removed hides removed devices and people with no active device from these lists; History keeps them.")

proc hiddenQuery(): Table[string, string] =
  if showHidden: {"show_hidden": "1"}.toTable else: initTable[string, string]()

proc people(w: Win, p: Page) =
  var users: seq[JNode]
  try: users = w.a.call("GET", "/api/users", nil, hiddenQuery())["users"].elems
  except ApiError as e:
    p.dim(e.msg)
    return
  var nHidden = 0
  try:
    for u in w.a.call("GET", "/api/users", nil, {"show_hidden": "1"}.toTable)["users"].elems:
      if u.get("hidden") != nil and u["hidden"].kind == jBool and u["hidden"].b: inc nHidden
  except ApiError: discard
  w.hiddenControls(p, nHidden)
  p.dim("Everyone who has an identity in this plant. People join with their devices (Devices); the join form asks " &
        "for their position.")
  let lp = toSeq(users)
  for i in 0 ..< lp.len:
    closureScope:
      let u = lp[i]
      let pid = s(u, "person")
      # removed: had devices and has none left (someone whose device hasn't joined yet was never removed)
      let removed = u.get("active") != nil and u["active"].kind == jBool and not u["active"].b and
                    u.get("devices") != nil and u["devices"].kind == jInt and u["devices"].i > 0
      let hidden = u.get("hidden") != nil and u["hidden"].kind == jBool and u["hidden"].b
      let name = s(u, "full_name") & " (" & s(u, "username") & ")"
      p.label(name & " · " & s(u, "role") & (if s(u, "position").len > 0: " · " & s(u, "position") else: "") &
              (if hidden: " · hidden" elif removed: " · removed" else: ""))
      if (removed or hidden) and pid.len > 0:
        p.buttons(((if hidden: "Show " & name & " again" else: "Hide " & name), proc () =
          w.hide(newObj(@[("ids", newArr(@[newStr(pid)])), ("hide", newBool(not hidden))]), if hidden: "Shown again" else: "Hidden")))
  # (The "Add a person" form that was here posted to POST /api/users, which only the server has: in the app it always
  # failed with "not found". As in the GNOME app, people join with their devices.)

proc positionNote(r: JNode): string =
  ## an invite's or join request's position, or why accepting it will fail (a new member without one)
  let req = r.get("request")
  if r.get("needs_position") != nil and r["needs_position"].kind == jBool and r["needs_position"].b:
    return ". No position (job title) given: a new member needs one, so ask them to send a new request with their position"
  if s(req, "position").len > 0: ", position " & s(req, "position") else: ""

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
                           s(req, "label") & positionNote(st) & (if not st["existing"].isNull: ". That username exists: it becomes their new device." else: "") &
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
  try: d = w.a.call("GET", "/api/devices", nil, if w.isAdmin: hiddenQuery() else: initTable[string, string]())
  except ApiError as e:
    p.dim(e.msg)
    return
  if w.isAdmin: w.hiddenControls(p, if d.get("hidden") != nil and d["hidden"].kind == jInt: int(d["hidden"].i) else: 0)
  proc rows(list: JNode, title: string) =
    if list == nil or list.kind != jArr: return
    p.title(title)
    let lp5 = toSeq(list.elems)
    for lp5i in 0 ..< lp5.len:
      closureScope:
        let x = lp5[lp5i]
        let dev = s(x, "device")
        let me = x["this_computer"].b
        let hidden = x.get("hidden") != nil and x["hidden"].kind == jBool and x["hidden"].b
        let devName = (if s(x, "label").len > 0: s(x, "label") else: "device") & " of " & s(x, "username")
        p.label((if s(x, "label").len > 0: s(x, "label") else: "device") & " · " & s(x, "username") &
                (if me: " (this device)" else: "") & "   " & dev[0 ..< min(16, dev.len)] & "…" & (if x["revoked"].b: " · removed" else: "") &
                (if hidden: " · hidden" else: ""))
        if x["revoked"].b and w.isAdmin:
          p.buttons(((if hidden: "Show " & devName & " again" else: "Hide " & devName), proc () =
            # a device is hidden by its own ID or its person's (Clear removed): showing it again clears both
            let ids = if hidden and s(x, "person").len > 0: @[newStr(dev), newStr(s(x, "person"))] else: @[newStr(dev)]
            w.hide(newObj(@[("ids", newArr(ids)), ("hide", newBool(not hidden))]), if hidden: "Shown again" else: "Hidden")))
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
          p.label(s(req, "full_name") & " (" & s(req, "username") & ") · " & s(req, "label") & " · code " & s(r, "code") & positionNote(r))
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

proc copyText(w: Win, text: string) =
  w.toast(if copyToClipboard(w.hwnd, text): "Copied" else: "The clipboard is busy: try again")

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
    of "Leaderboard": w.leaderboard(p)
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
  pages.add ("My proposals", "What you proposed, filtered and by code; photos to vote on")
  pages.add ("Leaderboard", "Who added what, and how much was approved")
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
  p.buttons(("About Walkdown…", proc () = openAbout(w.hwnd)))
  p.dim("Version, licences, the source of this version (also F1)")

proc liveManage*(): bool = managePage in ["Approvals", "My proposals", "Leaderboard", "History", "Devices", "Diagnostics"]
