## Manage (R10–R14; admin.html): approvals, my proposals, history with revert and restore, people, devices (join
## requests, revoke), and the account. Everything goes through the core's local API, like admin.html.

import std/[strutils, tables, times, sequtils, asyncdispatch, math]
import kks/[json, api, node, extras, util]
import kksl/dbstore
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
  let (_, t) = w.m.tagById(id)
  if t.sheet != w.sheet: w.showSheet(t.sheet)
  w.selectTag(id, true)

proc codeHeader(w: Win, code, tag: string, subtitle: string): W =
  ## a code's heading in Approvals and My proposals; the button opens it on the drawing
  let title = if code.len > 0: code else: "Tag " & tag
  result = group(title, subtitle)
  let open = button("Show on the drawing", "flat")
  setAccessibleLabel(open, "Open " & title & " on the drawing")
  gtk_widget_set_tooltip_text(open, ("Open " & title & " on the drawing").cstring)
  open.onClick(proc () = w.openTag(code, tag))
  adw_preferences_group_set_header_suffix(result, open)

proc photoButton(w: Win, g: W, sub: JNode) =
  if sub["kind"].s == "photo" and sub.get("payload") != nil:
    let file = s(sub["payload"], "file")
    let sha = file.split('.')[0]
    if sha.len > 0 and w.a.n.store.blobHas(sha):
      let data = w.a.n.store.blobGet(sha)
      let cap = s(sub["payload"], "caption")
      adw_preferences_group_add(g, button("Show the photo", "flat", proc () = w.showPhoto(data, cap)))

proc approvals(w: Win, box: W) =
  ## the user's "Approvals page clean-up": per code, then per kind (an equipment photo and a tag plate photo don't
  ## compete). Pick and votes only where several photos of one kind wait; Approve/Reject otherwise. Names in full.
  var groups: seq[JNode]
  try: groups = w.a.call("GET", "/api/submissions", nil, {"status": "open", "group": "code"}.toTable)["groups"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  if groups.len == 0:
    box.add label("Nothing waits for approval.", "dim-label")
    return
  let again = proc () = w.refreshPage(box, proc (b: W) = w.approvals(b))
  for gi in 0 ..< groups.len:
    closureScope:
      let grp = groups[gi]
      var n = 0
      for k in grp["kinds"].elems: n += k["items"].len
      box.add w.codeHeader(s(grp, "code"), s(grp, "tag"), $n & (if n == 1: " proposal" else: " proposals"))
      for ki in 0 ..< grp["kinds"].elems.len:
        closureScope:
          let kd = grp["kinds"].elems[ki]
          let pick = kd["pick"].kind == jBool and kd["pick"].b
          let items = kd["items"].elems
          let kg = group(s(kd, "label") & (if items.len > 1: " (" & $items.len & ")" else: ""),
                         if pick: "Several photos of this kind: pick the one to keep (the others of this kind are rejected), " &
                                  "or reject them one by one." else: "")
          for ii in 0 ..< items.len:
            closureScope:
              let sub = items[ii]
              let id = sub["id"].i
              let who = "by " & s(sub, "by_name") & " · " & sub.at("created") &
                        (if s(sub, "request_note").len > 0: " · note: " & s(sub, "request_note") else: "")
              adw_preferences_group_add(kg, row(proposalTitle(sub), who, selectable = true))
              for (lab, v) in proposalRows(sub): adw_preferences_group_add(kg, row(lab, v, selectable = true))
              if sub["status"].s == "conflict":
                adw_preferences_group_add(kg, row("Held", "It clashes with the current value or another proposal: " & s(sub, "note"), selectable = true))
              w.photoButton(kg, sub)
              let what = proposalTitle(sub) & " by " & s(sub, "by_name")
              let btns = hbox(8)
              gtk_widget_set_margin_top(btns, 6)
              gtk_widget_set_margin_bottom(btns, 10)
              if pick:
                let votes = if sub.get("votes") != nil and sub["votes"].kind == jInt: sub["votes"].i else: 0
                let pb = button("Pick this photo", "suggested-action", proc () =
                  if w.act(id, "pick", newObj(), "Photo chosen; the other " & s(kd, "label").toLowerAscii & "s were rejected"): again())
                setAccessibleDescription(pb, what & ", " & $votes & " votes")
                btns.add pb
                btns.add label($votes & (if votes == 1: " vote" else: " votes"), "dim-label")
              else:
                let ab = button(if sub["status"].s == "conflict": "Approve anyway" else: "Approve", "suggested-action", proc () =
                  if w.act(id, "approve", newObj(@[("force", newBool(sub["status"].s == "conflict"))]), "Approved"): again())
                setAccessibleDescription(ab, what)
                btns.add ab
              let rb = button("Reject", "destructive-action", proc () =
                if w.act(id, "reject", newObj(), "Rejected"): again())
              setAccessibleDescription(rb, what)
              btns.add rb
              adw_preferences_group_add(kg, btns)
          box.add kg

const StatusChoices = [("All", "all"), ("Waiting", "pending"), ("Held (clashes)", "conflict"), ("Approved", "approved"),
                       ("Rejected", "rejected"), ("Withdrawn", "withdrawn")]
const KindChoices = [("All kinds", "", ""), ("Equipment photos", "equipment_photo", ""), ("Tag plate photos", "plate_photo", ""),
                     ("Places and notes (any field)", "equipment", ""), ("Floor", "equipment", "floor"),
                     ("Notes", "equipment", "notes"), ("Other fields", "equipment", "custom"),
                     ("Procedure links", "link", ""), ("Tag readings", "review", ""), ("Marked tags", "tag_add", ""),
                     ("Removals", "photo_delete,tag_remove", "")]
var mineStatus, mineKind = 0      ## My proposals' filters, kept while the app runs

proc combo(title: string, names: seq[string], selected: int, changed: proc (i: int)): W =
  result = adw_combo_row_new()
  adw_preferences_row_set_title(result, title.cstring)
  let arr = allocCStringArray(names)
  adw_combo_row_set_model(result, gtk_string_list_new(arr))
  deallocCStringArray(arr)
  adw_combo_row_set_selected(result, cuint(selected))
  let c = result
  result.onPtr("notify::selected", proc (p: W) = changed(int(adw_combo_row_get_selected(c))))

proc myList(w: Win, box: W) =
  ## my proposals with the filters applied (server-side: status, kind, field), grouped by code
  let (_, kind, field) = KindChoices[mineKind]
  var q = {"status": StatusChoices[mineStatus][1], "mine": "1", "limit": "500"}.toTable
  if kind.len > 0: q["kind"] = kind
  if field.len > 0: q["field"] = field
  var subs: seq[JNode]
  try: subs = w.a.call("GET", "/api/submissions", nil, q)["submissions"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  if subs.len == 0:
    box.add label(if mineStatus == 0 and mineKind == 0: "You have proposed nothing yet." else: "None of your proposals match.", "dim-label")
    return
  var order: seq[string]
  var per: Table[string, seq[JNode]]
  for x in subs:
    let key = if s(x, "code").len > 0: s(x, "code") else: "tag:" & s(x, "tag")
    if key notin per: order.add key
    per.mgetOrPut(key, @[]).add x
  box.add label($subs.len & (if subs.len == 1: " proposal" else: " proposals") & ", " & $order.len &
                (if order.len == 1: " code" else: " codes"), "dim-label")
  for key in order:
    let items = per[key]
    let g = w.codeHeader(s(items[0], "code"), s(items[0], "tag"), "")
    for i in 0 ..< items.len:
      closureScope:
        let sub = items[i]
        let id = sub["id"].i
        let st = sub["status"].s
        let stName = case st
          of "pending": "waiting for approval"
          of "conflict": "held: it clashes"
          else: st
        adw_preferences_group_add(g, row(proposalTitle(sub), stName & " · " & sub.at("created") &
                                         (if s(sub, "note").len > 0 and st != "conflict": " · " & s(sub, "note") else: ""), selectable = true))
        for (lab, v) in proposalRows(sub): adw_preferences_group_add(g, row(lab, v, selectable = true))
        if st in ["pending", "conflict"]:
          let wb = button("Withdraw", "", proc () =
            confirm(w.window, "Withdraw this proposal?", "", "Withdraw", true, proc () =
              if w.act(id, "withdraw", newObj(), "Withdrawn"): w.refreshPage(box, proc (b: W) = w.myList(b))))
          setAccessibleDescription(wb, proposalTitle(sub))
          adw_preferences_group_add(g, wb)
    box.add g

proc myProposals(w: Win, box: W) =
  let filters = group("Show")
  let list = vbox(12)
  adw_preferences_group_add(filters, combo("Status", StatusChoices.mapIt(it[0]), mineStatus, proc (i: int) =
    mineStatus = i
    list.clear()
    w.myList(list)))
  adw_preferences_group_add(filters, combo("Kind", KindChoices.mapIt(it[0]), mineKind, proc (i: int) =
    mineKind = i
    list.clear()
    w.myList(list)))
  box.add filters
  w.myList(list)
  box.add list
  # photos others proposed: members vote where several photos of one kind compete for a code
  var groups: seq[JNode]
  try: groups = w.a.call("GET", "/api/submissions", nil, {"status": "open", "kind": "photo", "group": "code"}.toTable)["groups"].elems
  except ApiError: return
  var cands: seq[JNode]
  for grp in groups:
    for kd in grp["kinds"].elems:
      if kd["pick"].kind == jBool and kd["pick"].b:
        for x in kd["items"].elems:
          if not x["mine"].b: cands.add x
  if cands.len > 0:
    let g = group("Photos to vote on", "Several photos of the same kind wait for these codes. Vote for the ones you find useful; an admin picks one.")
    for i in 0 ..< cands.len:
      closureScope:
        let sub = cands[i]
        let id = sub["id"].i
        adw_preferences_group_add(g, navRow(s(sub, "code") & " · " & (if s(sub, "photo_kind") == "plate": "tag plate" else: "equipment") &
                                            " photo by " & s(sub, "by_name"),
          $(if sub.get("votes") != nil: sub["votes"].i else: 0) & " votes" & (if sub.get("voted") != nil and sub["voted"].b: " (yours)" else: ""),
          "Vote for this photo by " & s(sub, "by_name"), proc () =
            if w.act(id, "vote", newObj(), "Vote changed"): w.refreshPage(box, proc (b: W) = w.myProposals(b))))
    box.add g

proc leaderboard*(w: Win, box: W) =
  ## the user's "Leaderboard": members by approved contributions, what each contributed, approvals and rejections,
  ## the ratio, the last contribution (GET /api/leaderboard, every member)
  var d: JNode
  try: d = w.a.call("GET", "/api/leaderboard")
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let people = d["people"].elems
  if people.len == 0:
    box.add label("Nobody yet.", "dim-label")
    return
  proc num(n: JNode, k: string): int64 =
    if n != nil and n.get(k) != nil and n[k].kind == jInt: n[k].i else: 0
  let g = group("Members by approved contributions", "Counted from the whole plant's history. Ratio = approved per rejected.")
  for p in people:
    let name = if s(p, "name").len > 0: s(p, "name") elif s(p, "full_name").len > 0: s(p, "full_name") else: "?"
    let rate = p.get("approval_rate")
    let ratio = p.get("ratio")
    var parts = @[$num(p, "approved") & " approved", $num(p, "rejected") & " rejected"]
    if num(p, "pending") > 0: parts.add $num(p, "pending") & " waiting"
    if num(p, "withdrawn") > 0: parts.add $num(p, "withdrawn") & " withdrawn"
    parts.add(if ratio != nil and ratio.kind == jFloat: "ratio " & formatFloat(ratio.f, ffDecimal, 1)
              elif num(p, "approved") > 0: "no rejections" else: "")
    if rate != nil and rate.kind == jFloat: parts.add $int(round(rate.f * 100)) & " % approved"
    parts.add(if p.get("last") != nil and p["last"].kind == jInt: "last " & p.at("last")[0 ..< 10] else: "nothing yet")
    let ex = adw_expander_row_new()
    adw_preferences_row_set_use_markup(ex, 0)
    adw_preferences_row_set_title(ex, ("#" & $num(p, "rank") & "  " & name).cstring)
    adw_expander_row_set_subtitle(ex, parts.filterIt(it.len > 0).join(" · ").cstring)
    var hasAny = false
    let kinds = p.get("kinds")
    if kinds != nil and kinds.kind == jObj:
      for (k, lab) in d["kinds"].fields:
        let c = kinds.get(k)
        if num(c, "total") == 0: continue
        hasAny = true
        var bits = @[$num(c, "approved") & " approved"]
        if num(c, "rejected") > 0: bits.add $num(c, "rejected") & " rejected"
        if num(c, "pending") > 0: bits.add $num(c, "pending") & " waiting"
        if num(c, "withdrawn") > 0: bits.add $num(c, "withdrawn") & " withdrawn"
        adw_expander_row_add_row(ex, row(lab.s & ": " & $num(c, "total"), bits.join(" · ")))
    if num(p, "decided") > 0 or num(p, "votes") > 0:
      hasAny = true
      adw_expander_row_add_row(ex, row("Reviewing", $num(p, "decided") & " decisions · " & $num(p, "votes") & " votes"))
    if not hasAny: adw_expander_row_add_row(ex, row("No contributions yet", ""))
    adw_preferences_group_add(g, ex)
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

var showHidden = false     ## Devices and People: also the removed ones an admin hid (this run only)

proc hide(w: Win, body: JNode, done: string, again: proc ()) =
  ## POST /api/hidden: display only, the log and History keep everything
  try:
    let r = w.a.call("POST", "/api/hidden", body)
    w.toast(done & (if r.get("changed") != nil and r["changed"].kind == jInt and r["changed"].i == 0: " (nothing to change)" else: ""))
    again()
  except ApiError as e: w.toast(e.msg)

proc hiddenControls(w: Win, box: W, hiddenN: int, what: string, again: proc ()): W =
  ## "Clear removed" and "Show hidden (n)"
  result = hbox(8)
  let clear = button("Clear removed", "", proc () =
    w.hide(newObj(@[("clear_removed", newBool(true))]), "Removed devices and people hidden", again))
  setAccessibleDescription(clear, "Hide every removed device and every person with no active device from these lists")
  result.add clear
  if hiddenN > 0 or showHidden:
    let t = gtk_toggle_button_new_with_label((if showHidden: "Hide hidden" else: "Show hidden (" & $hiddenN & ")").cstring)
    gtk_toggle_button_set_active(t, cint(showHidden))
    setAccessibleLabel(t, if showHidden: "Hide the hidden " & what else: "Show the " & $hiddenN & " hidden " & what)
    t.onClick(proc () =
      showHidden = not showHidden
      again())
    result.add t

proc people(w: Win, box: W) =
  var users: seq[JNode]
  try: users = w.a.call("GET", "/api/users", nil, if showHidden: {"show_hidden": "1"}.toTable else: initTable[string, string]())["users"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let again = proc () = w.refreshPage(box, proc (b: W) = w.people(b))
  var nHidden = 0
  if not showHidden:
    try:
      for u in w.a.call("GET", "/api/users", nil, {"show_hidden": "1"}.toTable)["users"].elems:
        if u.get("hidden") != nil and u["hidden"].kind == jBool and u["hidden"].b: inc nHidden
    except ApiError: discard
  box.add w.hiddenControls(box, nHidden, "people", again)
  let g = group("People", "Everyone who has an identity in this plant. Devices are added under Devices. People whose " &
                "devices were all removed can be hidden here (History keeps them).")
  for i in 0 ..< users.len:
    closureScope:
      let u = users[i]
      let pid = s(u, "person")
      let removed = u.get("active") != nil and u["active"].kind == jBool and not u["active"].b
      let hidden = u.get("hidden") != nil and u["hidden"].kind == jBool and u["hidden"].b
      let name = s(u, "full_name") & " (" & s(u, "username") & ")"
      let rw = row(name, s(u, "role") & (if s(u, "position").len > 0: " · " & s(u, "position") else: "") &
                   (if hidden: " · hidden" elif removed: " · no active device" else: ""), selectable = true)
      if removed and pid.len > 0:
        let b = button(if hidden: "Unhide" else: "Hide", "flat", proc () =
          w.hide(newObj(@[("ids", newArr(@[newStr(pid)])), ("hide", newBool(not hidden))]), if hidden: "Shown again" else: "Hidden", again))
        setAccessibleLabel(b, (if hidden: "Unhide " else: "Hide ") & name)
        gtk_widget_set_valign(b, GTK_ALIGN_CENTER)
        adw_action_row_add_suffix(rw, b)
      adw_preferences_group_add(g, rw)
  box.add g
  # People join with their devices (invite, nearby admin, request file); the join form asks for their position.
  # (The "Add a person" form that was here posted to POST /api/users, which only the server has: on a laptop it always
  # failed with "not found".)

proc devices(w: Win, box: W) =
  var d: JNode
  try: d = w.a.call("GET", "/api/devices", nil, if showHidden: {"show_hidden": "1"}.toTable else: initTable[string, string]())
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    return
  let again = proc () = w.refreshPage(box, proc (b: W) = w.devices(b))
  if w.isAdmin:
    box.add w.hiddenControls(box, if d.get("hidden") != nil and d["hidden"].kind == jInt: int(d["hidden"].i) else: 0, "devices", again)
  proc devRows(list: JNode, title: string) =
    if list == nil or list.kind != jArr: return
    let g = group(title)
    for i in 0 ..< list.elems.len:
      closureScope:
        let x = list.elems[i]
        let dev = s(x, "device")
        let rw = row((if s(x, "label").len > 0: s(x, "label") else: "device") & " · " & s(x, "username") & (if x["this_computer"].b: " (this device)" else: ""),
                     dev[0 ..< min(16, dev.len)] & "…" & (if x["revoked"].b: " · removed" else: "") &
                     (if x.get("hidden") != nil and x["hidden"].kind == jBool and x["hidden"].b: " · hidden" else: ""))
        if x["revoked"].b and w.isAdmin:
          let hidden = x.get("hidden") != nil and x["hidden"].kind == jBool and x["hidden"].b
          let hb = button(if hidden: "Unhide" else: "Hide", "flat", proc () =
            w.hide(newObj(@[("ids", newArr(@[newStr(dev)])), ("hide", newBool(not hidden))]), if hidden: "Shown again" else: "Hidden", again))
          setAccessibleLabel(hb, (if hidden: "Unhide the removed device " else: "Hide the removed device ") & s(x, "label") & " of " & s(x, "username"))
          gtk_widget_set_valign(hb, GTK_ALIGN_CENTER)
          adw_action_row_add_suffix(rw, hb)
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
            let rw = row(s(req, "full_name") & " (" & s(req, "username") & ") · " & s(req, "label"), "code " & s(r, "code") & positionNote(r))
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
  ## R14: the plant's authority has an offline backup the manager holds (PROTOCOL-v2 §20: PBKDF2 ≥ 600 000 + AES-GCM)
  let g = group("Root key", "The plant's root key signs the manager role and settles stolen devices. Keep an encrypted " &
                "copy offline (a USB stick in a drawer), protected by a passphrase only you know.")
  let has = w.a.store.getRow("keys", "root") != nil
  adw_preferences_group_add(g, row("On this device", if has: "yes" else: "no (it is on another device of the manager)"))
  let pw1 = passwordRow("Passphrase (12 characters or more)")
  let pw2 = passwordRow("The passphrase again")
  adw_preferences_group_add(g, pw1)
  adw_preferences_group_add(g, pw2)
  if has:
    adw_preferences_group_add(g, button("Save an encrypted backup…", "", proc () =
      let p1 = text(pw1)
      if p1.len < 12:
        w.toast("Use a passphrase of 12 characters or more")
        return
      if p1 != text(pw2):
        w.toast("The two passphrases differ")
        return
      saveFile(w.window, "Save the root key backup", "root-key.kksroot", proc (path: string) =
        if path.len == 0: return
        let k = w.a.store.getRow("keys", "root")
        let plain = toText(k)
        var bytes: seq[byte]
        for c in plain: bytes.add byte(c)
        let sealed = w.a.p.passphraseSeal(p1, bytes)
        let doc = newObj(@[("kks_root_backup", newInt(2)), ("plant", newStr(w.a.plantName)), ("root", newStr(w.a.n.root)),
                           ("sealed", sealed)])
        writeFile(path, toText(doc))
        w.toast("Saved. Test it once with Restore on another device, then store it offline."))))
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
  sub("My proposals", "What you proposed, filtered and by code; photos to vote on", "mine", proc (b: W) = w.myProposals(b), live = true)
  sub("Leaderboard", "Members by approved contributions", "leaderboard", proc (b: W) = w.leaderboard(b), live = true)
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
