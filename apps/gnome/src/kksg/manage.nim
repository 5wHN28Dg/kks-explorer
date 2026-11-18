## Manage (R10–R14; admin.html): approvals, my proposals, history with revert and restore, people, devices (join
## requests, revoke), and the account. Everything goes through the core's local API, like admin.html.

import std/[strutils, tables, times, sequtils, asyncdispatch, math, algorithm]
import kks/[json, api, node, extras, util]
import kksl/[dbstore, privfile, passphrase]
import kks/model
import proposals, histline
import gtk, ui, appstate, win, photos, join

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc at(n: JNode, k: string): string =
  if n == nil or n.get(k) == nil or n[k].kind != jInt: return ""
  fromUnix(n[k].i).local.format("yyyy-MM-dd HH:mm")

proc refreshPage(w: Win, box: W, build: proc (box: W)) =
  box.clear()
  build(box)
  w.liveBuilt(box)     # (a live page rebuilt by its own action is up to date: the next sync needn't rebuild it)

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
  w.goToTag(t.sheet, id)

proc codeHeader(w: Win, code, tag: string, subtitle: string): W =
  ## a code's heading in Approvals and My proposals; the button opens it on the drawing
  let title = if code.len > 0: code else: "Tag " & tag
  result = group(title, subtitle)
  let open = iconButton("find-location-symbolic", "Open " & title & " on the drawing", proc () = w.openTag(code, tag))
  gtk_widget_add_css_class(open, "flat")
  adw_preferences_group_set_header_suffix(result, open)

proc photoButton(w: Win, g: W, sub: JNode) =
  if sub["kind"].s == "photo" and sub.get("payload") != nil:
    let file = s(sub["payload"], "file")
    let sha = file.split('.')[0]
    if sha.len > 0 and w.a.n.store.blobHas(sha):
      let data = w.a.n.store.blobGet(sha)
      let cap = s(sub["payload"], "caption")
      adw_preferences_group_add(g, button("Show the photo", "flat", proc () = w.showPhoto(data, cap)))

# Approvals, several at once (the user, 2026-11-15: "accept/deny multiple requests at once"): a tick per proposal, and
# under the page a bar with Select all, how many are ticked, Approve selected and Reject selected. The ticks are kept
# by id over the page's rebuilds (a sync rebuilds it under the person); the ones no longer waiting are dropped.
var
  picked: seq[int64]             ## the ticked proposals' ids
  pickCompeting: seq[int64]       ## photos of one kind that compete for their code (Pick): never approved by the batch
  pickSubs: seq[JNode]           ## the waiting proposals as last drawn, oldest first
  pickChecks: seq[(int64, W)]    ## each one's tick (in the page: not held)
  pickBar: W                     ## the bar under the Approvals page (its toolbar's bottom bar; not held)
  pickAll, pickCount, pickOk, pickNo: W
  pickSetting = false            ## Select all is setting the ticks: their own "toggled" leaves the bar alone meanwhile
  pickBusy = false
  lastSaid = ""                  ## the last batch's result, under the bar until the next batch

proc setText(b: W, t: string) =
  ## a button's text, in the wrapping label that is its child
  let l = gtk_button_get_child(b)
  if l != nil: gtk_label_set_text(l, t.cstring)
  setAccessibleLabel(b, t)      # (a child label doesn't name the button for assistive technologies)

proc wrapButton(t, css: string): W =
  ## a button whose label wraps (the side column is narrow, the counts grow)
  result = gtk_button_new()
  gtk_button_set_child(result, label(t, wrap = true, xalign = 0.5))
  setAccessibleLabel(result, t)
  for c in css.splitWhitespace: gtk_widget_add_css_class(result, c.cstring)

proc pickShow() =
  ## the bar as the ticks are now
  if pickBar == nil or pickAll == nil or pickOk == nil: return
  let n = picked.len
  pickSetting = true
  gtk_toggle_button_set_active(pickAll, cint(n > 0 and n == pickSubs.len))
  for (id, cb) in pickChecks:
    let on = id in picked
    gtk_toggle_button_set_active(cb, cint(on))
    let l = gtk_button_get_child(cb)
    if l != nil: gtk_label_set_text(l, (if on: "Selected" else: "Select").cstring)
  pickSetting = false
  gtk_label_set_text(pickCount, (if n > 0: $n & " selected" else: "None selected").cstring)
  pickOk.setText("Approve selected" & (if n > 0: " (" & $n & ")" else: ""))
  pickNo.setText("Reject selected" & (if n > 0: " (" & $n & ")" else: ""))
  for b in [pickOk, pickNo]: gtk_widget_set_sensitive(b, cint(n > 0 and not pickBusy))

proc decideMany(w: Win, action: string, again: proc (), only: seq[int64] = @[]) =
  ## every ticked proposal, oldest first, each as its own button sends it (approve without force, reject). A held one
  ## (it clashes with the value as it is now) is not approved here: its own "Approve anyway" does that.
  if pickBusy: return
  var done = 0
  var held, competing, failed: seq[string]
  var chosen: seq[JNode]
  for sub in pickSubs:      # (`only`: what was ticked when the question was asked, and still waits)
    if sub["id"].i in picked and (only.len == 0 or sub["id"].i in only): chosen.add sub
  if chosen.len == 0:
    w.toast("Nothing selected")
    return
  pickBusy = true
  let startBar = pickBar      # (the page the batch was started from: `again` rebuilds that one, and no other)
  pickShow()
  # one proposal per turn of the main loop, saying how far it got: the window stays live during a long batch
  var i = 0
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
        if pickCount != nil:
          gtk_label_set_text(pickCount, ((if action == "approve": "Approving " else: "Rejecting ") & $i & " of " &
                                         $chosen.len & "…").cstring)
        try:
          discard w.a.call("POST", "/api/submissions/" & $id & "/" & action, newObj())
          inc done
          picked.keepItIf(it != id)
        except CatchableError as e:      # (anything else than the server's answer too: the batch must end and say so)
          failed.add "#" & $id & ": " & e.msg
      idle(step)
      return
    pickBusy = false
    var msg = (if action == "approve": "Approved " else: "Rejected ") & $done & " of " & $chosen.len & "."
    if held.len > 0:
      msg.add " Not approved: " & held.join(", ") & (if held.len == 1: " clashes" else: " clash") &
              " with the value as it is now; decide " & (if held.len == 1: "it on its" else: "them on their") & " own."
    if competing.len > 0:
      msg.add " Not approved: " & competing.join(", ") & ": several photos of one kind compete for " &
              (if competing.len == 1: "its" else: "their") & " code; choose with “Pick this photo”."
    if failed.len > 0: msg.add " Not done: " & failed.join("; ") & "."
    lastSaid = msg
    w.toast(msg)
    if pickBar != nil and pickBar == startBar: again()   # (only while that page is still open: closed, or closed and
                                                          # opened again, its box is gone; the result shows there next)
    else: pickShow()
  idle(step)      # (the bar's own button ran this: the page and the bar are made again after it returned)

proc fillPickBar(w: Win, again: proc ()) =
  if pickBar == nil: return
  pickBar.clear()
  pickAll = nil        # (the bar's widgets are gone with it: a batch still running must not write to them)
  pickCount = nil
  pickOk = nil
  pickNo = nil
  if pickSubs.len == 0:
    gtk_widget_set_visible(pickBar, 0)
    return
  gtk_widget_set_visible(pickBar, 1)
  # toggle buttons, not check buttons: GTK 4 gives a check button no accessible action (AT-SPI can't press it)
  pickAll = gtk_toggle_button_new()
  gtk_button_set_child(pickAll, label("Select all (" & $pickSubs.len & ")", wrap = true, xalign = 0.5))
  setAccessibleLabel(pickAll, "Select all (" & $pickSubs.len & ")")
  pickAll.on("toggled", proc () =
    if pickSetting: return
    let on = gtk_toggle_button_get_active(pickAll) != 0
    picked.setLen(0)
    if on:
      for sub in pickSubs: picked.add sub["id"].i
    pickShow())
  pickCount = label("None selected", "dim-label")
  gtk_widget_set_hexpand(pickCount, 1)
  pickOk = wrapButton("Approve selected", "suggested-action")
  pickOk.onClick(proc () = w.decideMany("approve", again))
  pickNo = wrapButton("Reject selected", "destructive-action")
  pickNo.onClick(proc () =
    let n = picked.len
    if n == 0: return
    let asked = picked
    ask(w.window, "Reject " & (if n == 1: "1 proposal" else: $n & " proposals") & "?",
        "Each one is rejected as its own Reject button does. The submitters see that it was rejected.",
        "Reject " & (if n == 1: "1 proposal" else: $n & " proposals"), "Cancel", proc (yes: bool) =
          if yes: w.decideMany("reject", again, asked)))
  # two rows (the side column is narrow): Select all and the count, then the two actions, each half the width
  let top = hbox(12)
  top.add pickAll, pickCount
  let acts = hbox(12)
  gtk_box_set_homogeneous(acts, 1)
  acts.add pickOk, pickNo
  pickBar.add top, acts
  if lastSaid.len > 0: pickBar.add label(lastSaid, "dim-label", selectable = true)
  pickShow()

proc approvals(w: Win, box: W) =
  ## the user's "Approvals page clean-up": per code, then per kind (an equipment photo and a tag plate photo don't
  ## compete). Pick and votes only where several photos of one kind wait; Approve/Reject otherwise. Names in full.
  var groups: seq[JNode]
  pickChecks.setLen(0)
  pickSubs.setLen(0)
  let again = proc () = w.refreshPage(box, proc (b: W) = w.approvals(b))
  try: groups = w.a.call("GET", "/api/submissions", nil, {"status": "open", "group": "code", "limit": "1000"}.toTable)["groups"].elems
  except ApiError as e:
    box.add label(e.msg, "dim-label")
    w.fillPickBar(again)
    return
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
  w.fillPickBar(again)
  if groups.len == 0:
    box.add label("Nothing waits for approval.", "dim-label")
    return
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
              # a group of its own for each proposal (the kind's heading over the first): a group puts its buttons under
              # all its rows, and several proposals in one had their buttons in a stack below, away from what they decide
              let pg = if ii == 0: kg else: group("")
              let who = "#" & $id & " · by " & s(sub, "by_name") & " · " & sub.at("created") &
                        (if s(sub, "request_note").len > 0: " · note: " & s(sub, "request_note") else: "")
              adw_preferences_group_add(pg, row(proposalTitle(sub), who, selectable = true))
              for (lab, v) in proposalRows(sub): adw_preferences_group_add(pg, row(lab, v, selectable = true))
              if sub["status"].s == "conflict":
                adw_preferences_group_add(pg, row("Held", "It clashes with the current value or another proposal: " & s(sub, "note"), selectable = true))
              w.photoButton(pg, sub)
              let what = proposalTitle(sub) & " by " & s(sub, "by_name")
              let btns = hbox(8)
              gtk_widget_set_margin_top(btns, 6)
              gtk_widget_set_margin_bottom(btns, 10)
              if w.isAdmin:
                # "Select" on screen (a toggle button: GTK 4 gives a check button no accessible action), and which
                # one to a screen reader (a child label: GTK names a button after its own label, over the name set here)
                let cb = gtk_toggle_button_new()
                gtk_button_set_child(cb, label(if id in picked: "Selected" else: "Select", wrap = false))
                setAccessibleLabel(cb, "Select #" & $id & ", " & what)
                gtk_toggle_button_set_active(cb, cint(id in picked))
                cb.on("toggled", proc () =
                  if pickSetting: return
                  if gtk_toggle_button_get_active(cb) != 0:
                    if id notin picked: picked.add id
                  else: picked.keepItIf(it != id)
                  pickShow())
                pickChecks.add (id, cb)
                if pick:        # (a line of its own: with "Pick this photo", the votes and Reject the row was too wide)
                  let top = hbox(8)
                  gtk_widget_set_margin_top(top, 6)
                  top.add cb
                  adw_preferences_group_add(pg, top)
                else: btns.add cb
              if pick:
                let votes = if sub.get("votes") != nil and sub["votes"].kind == jInt: sub["votes"].i else: 0
                let others = items.len - 1
                let pb = button("Pick this photo", "suggested-action", proc () =
                  # the others of its kind are rejected with it, for good (#365): said, with how many, first
                  let kind = s(kd, "label").toLowerAscii
                  ask(w.window, "Reject the other " & (if others == 1: "photo?" else: $others & " photos?"),
                      "Picking #" & $id & (if s(grp, "code").len > 0: " for " & s(grp, "code") else: "") & " rejects the other " & (if others == 1: kind else: $others & " " & kind & "s") &
                      " proposed for it. The submitters see that " & (if others == 1: "it was" else: "they were") & " rejected; this can't be undone.",
                      "Pick and reject " & (if others == 1: "the other" else: "the other " & $others), "Cancel", proc (yes: bool) =
                    if yes and w.act(id, "pick", newObj(), "Photo chosen; the other " & kind & "s were rejected"): again()))
                setAccessibleDescription(pb, what & ", " & $votes & " votes")
                btns.add pb
                btns.add label($votes & (if votes == 1: " vote" else: " votes"), "dim-label")
              else:
                let ab = button(if sub["status"].s == "conflict": "Approve anyway" else: "Approve", "suggested-action", proc () =
                  if w.act(id, "approve", newObj(@[("force", newBool(sub["status"].s == "conflict"))]), "Approved"): again())
                setAccessibleDescription(ab, what)
                btns.add ab
              let rb = button("Reject", "destructive-action", proc () =
                # final: the core takes no other decision on it afterwards (#365)
                ask(w.window, "Reject " & proposalTitle(sub) & "?",
                    (if s(sub, "by_name").len > 0: s(sub, "by_name") & "'s proposal" else: "The proposal") & " is discarded; the submitter sees that it was rejected. This can't be undone.",
                    "Reject", "Cancel", proc (yes: bool) =
                  if yes and w.act(id, "reject", newObj(), "Rejected"): again()))
              setAccessibleDescription(rb, what)
              btns.add rb
              adw_preferences_group_add(pg, btns)
              box.add pg

const StatusChoices = [("All", "all"), ("Waiting", "pending"), ("Held (clashes)", "conflict"), ("Approved", "approved"),
                       ("Rejected", "rejected"), ("Withdrawn", "withdrawn")]
const KindChoices = [("All kinds", "", ""), ("Equipment photos", "equipment_photo", ""), ("Tag plate photos", "plate_photo", ""),
                     ("Places and notes (any field)", "equipment", ""), ("Floor", "equipment", "floor"),
                     ("Notes", "equipment", "notes"), ("Other fields", "equipment", "custom"),
                     ("Procedure links", "link", ""), ("Tag readings", "review", ""), ("Marked tags", "tag_add", ""),
                     ("Removals", "photo_delete,tag_remove", "")]
var mineStatus, mineKind = 0      ## My proposals' filters, kept while the app runs

proc chips(title: string, names: seq[string], selected: int, changed: proc (i: int)): W =
  ## one choice of several, as a row of toggle buttons (each named for a screen reader, its state "pressed")
  result = group(title)
  let wb = adw_wrap_box_new()
  adw_wrap_box_set_child_spacing(wb, 6)
  adw_wrap_box_set_line_spacing(wb, 6)
  var all: seq[W]
  for i in 0 ..< names.len:
    closureScope:
      let idx = i
      let t = gtk_toggle_button_new_with_label(names[i].cstring)
      gtk_widget_add_css_class(t, "pill")
      setAccessibleDescription(t, title & " filter")
      if i == selected: gtk_toggle_button_set_active(t, 1)
      all.add t
      t.onClick(proc () =
        for j, x in all: gtk_toggle_button_set_active(x, cint(j == idx))
        changed(idx))
      adw_wrap_box_append(wb, t)
  adw_preferences_group_add(result, wb)

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
            let list = hold(box)    # a sync can rebuild the page (and free this list) while the question is up
            confirm(w.window, "Withdraw this proposal?", proposalTitle(sub) & ": it is taken back before anyone decides it.", "Withdraw", true, proc () =
              if w.act(id, "withdraw", newObj(), "Withdrawn"):
                if list.shown: w.refreshPage(box, proc (b: W) = w.myList(b))
                else: w.refreshLive()))     # the page that replaced it, brought up to date
          setAccessibleDescription(wb, proposalTitle(sub))
          adw_preferences_group_add(g, wb)
    box.add g

proc myProposals(w: Win, box: W) =
  let list = vbox(12)
  box.add chips("Status", StatusChoices.mapIt(it[0]), mineStatus, proc (i: int) =
    mineStatus = i
    list.clear()
    w.myList(list))
  box.add chips("Kind", KindChoices.mapIt(it[0]), mineKind, proc (i: int) =
    mineKind = i
    list.clear()
    w.myList(list))
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
      let rw = row(historyTitle(r), historyBy(r), selectable = true)
      adw_preferences_row_set_title_selectable(rw, 1)    # the line holds the code: it can be copied
      if historyUndoable(r):
        let rev = button("Revert", "flat", proc () =
          confirm(w.window, "Revert this change?", "This writes a new change that undoes it; History keeps both.", "Revert", true, proc () =
            try:
              discard w.a.call("POST", "/api/revisions/" & (if hid.kind == jInt: $hid.i else: hid.s) & "/revert", newObj())
              w.toast("Reverted")
              w.refreshPage(box, proc (b: W) = w.history(b))
            except ApiError as e: w.toast(e.msg)))
        let rest = button("Restore", "flat", proc () =
          confirm(w.window, "Restore to just after this change?", "Every later change is undone by new changes.", "Restore", true, proc () =
            try:
              discard w.a.call("POST", "/api/restore", newObj(@[("hid", hid)]))
              w.toast("Restored")
              w.refreshPage(box, proc (b: W) = w.history(b))
            except ApiError as e: w.toast(e.msg)))
        # one above the other, 8 px apart: side by side they left the line about 55 px in the sidebar, and every
        # code broke inside itself (UI audit 2026-11, GNOME-3)
        let acts = vbox(8)
        acts.add(rev, rest)
        gtk_widget_set_valign(acts, GTK_ALIGN_CENTER)
        adw_action_row_add_suffix(rw, acts)
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
  # how many it hides, on the button (#365, B2), and Undo after: hiding is display only, so it is taken back by
  # showing the same ones again. Counted as the page is built: the lists as shown (hidden ones left out).
  var ids: seq[string]
  try:
    let all = w.a.call("GET", "/api/devices").get("all")
    if all != nil and all.kind == jArr:
      for x in all.elems:
        if x.get("revoked") != nil and x["revoked"].kind == jBool and x["revoked"].b and s(x, "device").len > 0: ids.add s(x, "device")
    for u in w.a.call("GET", "/api/users")["users"].elems:
      if u.get("active") != nil and u["active"].kind == jBool and not u["active"].b and
         u.get("devices") != nil and u["devices"].kind == jInt and u["devices"].i > 0 and s(u, "person").len > 0: ids.add s(u, "person")
  except ApiError, KeyError: discard
  let clear = button("Clear removed (" & $ids.len & ")", "", proc () =
    if ids.len == 0:
      w.toast("Nothing to clear: no removed device or person is listed")
      return
    try:
      discard w.a.call("POST", "/api/hidden", newObj(@[("clear_removed", newBool(true))]))
      again()
      w.toastUndo("Hid " & $ids.len & " removed " & (if ids.len == 1: "device or person" else: "devices and people"), proc () =
        var arr = newArr()
        for x in ids: arr.elems.add newStr(x)
        w.hide(newObj(@[("ids", arr), ("hide", newBool(false))]), "Shown again", again))
    except ApiError as e: w.toast(e.msg))
  setAccessibleDescription(clear, "Hide every removed device and every person with no active device from these lists")
  result.add clear
  if hiddenN > 0 or showHidden:
    let t = gtk_toggle_button_new_with_label((if showHidden: "Hide hidden" else: "Show hidden (" & $hiddenN & ")").cstring)
    gtk_toggle_button_set_active(t, cint(showHidden))
    setAccessibleDescription(t, if showHidden: "Leave the hidden " & what & " out again" else: "List the " & $hiddenN & " hidden " & what & " too")
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
      # removed: had devices and has none left (someone whose device hasn't joined yet was never removed)
      let removed = u.get("active") != nil and u["active"].kind == jBool and not u["active"].b and
                    u.get("devices") != nil and u["devices"].kind == jInt and u["devices"].i > 0
      let hidden = u.get("hidden") != nil and u["hidden"].kind == jBool and u["hidden"].b
      let name = s(u, "full_name") & " (" & s(u, "username") & ")"
      let rw = row(name, s(u, "role") & (if s(u, "position").len > 0: " · " & s(u, "position") else: "") &
                   (if hidden: " · hidden" elif removed: " · no active device" else: ""), selectable = true)
      if removed and pid.len > 0:
        let b = button(if hidden: "Unhide" else: "Hide", "flat", proc () =
          w.hide(newObj(@[("ids", newArr(@[newStr(pid)])), ("hide", newBool(not hidden))]), if hidden: "Shown again" else: "Hidden", again))
        setAccessibleDescription(b, (if hidden: "Show " else: "Hide ") & name & " in this list" & (if hidden: " again" else: ""))
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
          setAccessibleDescription(hb, (if hidden: "Show the removed device " else: "Hide the removed device ") & s(x, "label") & " of " & s(x, "username"))
          gtk_widget_set_valign(hb, GTK_ALIGN_CENTER)
          adw_action_row_add_suffix(rw, hb)
        if not x["revoked"].b and not x["this_computer"].b:
          let b = button("Remove", "flat destructive-action", proc () =
            confirm(w.window, "Remove this device?", "It stops receiving data, and wipes the plant from itself if it ever connects again.",
                    "Remove device", true, proc () =
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
      var bar: W = nil
      if tag == "approvals":         # Select all, Approve selected, Reject selected: under the list, always in view
        bar = vbox(8)
        margins(bar, 8)
        pickBar = bar
        let mine = bar
        bar.on("destroy", proc () =    # (the page was closed: nothing may use its widgets any more)
          if pickBar == mine:
            pickBar = nil
            pickAll = nil
            pickCount = nil
            pickOk = nil
            pickNo = nil
            pickChecks.setLen(0))
      build(b)
      w.setLive(if live: b else: nil, build)
      let tv = toolbarView(headerBar(adw_window_title_new(title.cstring, "")), scrolled(b))
      if bar != nil: adw_toolbar_view_add_bottom_bar(tv, bar)
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
