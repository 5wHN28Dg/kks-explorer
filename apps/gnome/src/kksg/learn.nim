## The courses on GNOME (docs/COURSES.md, decision 0036): Learning in the sidebar lists them; a course opens in its own
## window, the rail on the left, the page on the right. Runs become Pango markup in which every course string is
## escaped; links carry our own URIs (page:, course:, kks:) or https. Page logic is apps/common/coursestate.nim.

import std/[math, strutils, tables, sets, sequtils, uri]
import kks/[json, courses, model]
import gtk, ui, win, photos, coursefig, coursestate, appstate

type CW = ref object       ## one course window
  w: Win
  c: Course
  window, rail, railList, scroller, pageBox, title: W
  pageId: string
  figs: seq[FigView]

proc openCourse*(w: Win, id: string, page = "")
proc show(cw: CW, id: string)

# ---------------------------------------------------------------- runs (§3)

proc linkUri(to: JNode): string =
  if to.get("url") != nil: return to["url"].s
  if to.get("kks") != nil: return "kks:" & to["kks"].s
  if to.get("course") != nil:
    return "course:" & to["course"].s & (if to.get("page") != nil: "#" & to["page"].s else: "")
  "page:" & to["page"].s

proc markup(cw: CW, r: JNode): string =
  for x in r.elems:
    if x.kind == jStr: result.add esc(x.s)
    elif x.get("b") != nil: result.add "<b>" & cw.markup(x["b"]) & "</b>"
    elif x.get("i") != nil: result.add "<i>" & cw.markup(x["i"]) & "</i>"
    elif x.get("small") != nil: result.add "<small>" & cw.markup(x["small"]) & "</small>"
    elif x.get("num") != nil: result.add "<span font_family=\"JetBrains Mono, monospace\">" & esc(x["num"].s) & "</span>"
    elif x.get("term") != nil: result.add "<u>" & cw.markup(x["term"]) & "</u>"
    elif x.get("link") != nil: result.add "<a href=\"" & esc(linkUri(x["to"])) & "\">" & cw.markup(x["link"]) & "</a>"

proc follow(cw: CW, uri: string): bool =
  ## our links; https ones return false so GTK opens them in the browser
  if uri.startsWith("page:"):
    let id = uri[5 .. ^1]
    idle(proc () = cw.show(id))
    return true
  if uri.startsWith("course:"):
    let rest = uri[7 .. ^1]
    let parts = rest.split('#', 1)
    idle(proc () = openCourse(cw.w, parts[0], if parts.len > 1: parts[1] else: ""))
    return true
  if uri.startsWith("kks:"):
    let code = uri[4 .. ^1]
    idle(proc () =
      for t in cw.w.m.tags:
        if t.full == code or t.kks == code:
          if t.sheet != cw.w.sheet: cw.w.showSheet(t.sheet)
          cw.w.selectTag(t.id, true)
          gtk_window_present(cw.w.window)
          return
      cw.w.toast(code & " is not on any sheet"))
    return true
  not uri.startsWith("https://")

proc rl(cw: CW, r: JNode, css = "", selectable = true): W =
  ## a run as a wrapping label
  result = gtk_label_new("")
  gtk_label_set_markup(result, cw.markup(r).cstring)
  gtk_label_set_xalign(result, 0)
  gtk_label_set_wrap(result, 1)
  gtk_label_set_wrap_mode(result, PANGO_WRAP_WORD_CHAR)
  if selectable: gtk_label_set_selectable(result, 1)
  for c in css.splitWhitespace: gtk_widget_add_css_class(result, c.cstring)
  result.onLink(proc (u: string): bool = cw.follow(u))

proc txt(s: string): JNode = newArr(@[newStr(s)])

proc heading(text: string, level: int, css: string): W =
  result = headingLabel(level)
  gtk_label_set_text(result, text.cstring)
  gtk_label_set_xalign(result, 0)
  gtk_label_set_wrap(result, 1)
  gtk_widget_add_css_class(result, css.cstring)

# ---------------------------------------------------------------- blocks (§4)

proc blocks(cw: CW, bs: JNode, box: W)

proc table(cw: CW, t: JNode): W =
  let g = gtk_grid_new()
  gtk_grid_set_row_spacing(g, 6)
  gtk_grid_set_column_spacing(g, 18)
  margins(g, 10)
  var num: HashSet[int]
  for i in t["num"].elems: num.incl int(i.num)
  for (ci, h) in t["head"].elems.pairs:
    let l = cw.rl(h, "heading", false)
    gtk_grid_attach(g, l, cint(ci), 0, 1, 1)
  for (ri, row) in t["rows"].elems.pairs:
    for (ci, cell) in row.elems.pairs:
      let l = cw.rl(cell, if ci in num: "monospace numeric" else: "")
      if ci in num: gtk_label_set_xalign(l, 1)
      gtk_grid_attach(g, l, cint(ci), cint(ri + 1), 1, 1)
  let frame = vbox(0)
  gtk_widget_add_css_class(frame, "card")
  let sc = gtk_scrolled_window_new()
  gtk_scrolled_window_set_policy(sc, GTK_POLICY_AUTOMATIC, GTK_POLICY_NEVER)
  gtk_scrolled_window_set_propagate_natural_height(sc, 1)
  gtk_scrolled_window_set_child(sc, g)
  frame.add sc
  frame

proc figure(cw: CW, id: string): W =
  let f = cw.c.doc["figures"][id]
  let v = figureWidget(f, cw.scroller)
  cw.figs.add v
  result = vbox(6)
  gtk_widget_add_css_class(result, "card")
  margins(v.box, 12)
  let head = hbox(8)
  head.add label(f["title"].s, "heading", wrap = true)
  if f.get("period") != nil:
    let t = label("animated", "dim-label caption", wrap = false)
    gtk_widget_set_hexpand(t, 1)
    gtk_label_set_xalign(t, 1)
    head.add t
  margins(head, 12)
  gtk_widget_set_margin_bottom(head, 0)
  result.add head, v.box
  if f["caption"].len > 0:
    let cap = cw.rl(f["caption"], "dim-label caption")
    margins(cap, 12)
    gtk_widget_set_margin_top(cap, 0)
    result.add cap

proc image(cw: CW, im: JNode): W =
  result = vbox(4)
  let (ok, data) = cw.w.a.courseImage(im["file"].s)
  let tex = if ok: textureOfPhoto(data) else: nil
  if tex != nil:
    let pic = gtk_picture_new()
    gtk_picture_set_paintable(pic, tex)
    gtk_picture_set_can_shrink(pic, 1)
    gtk_picture_set_content_fit(pic, 0)      # GTK_CONTENT_FIT_CONTAIN
    gtk_widget_set_size_request(pic, -1, cint(min(420, int(im["h"].num * 680 / im["w"].num))))
    setAccessibleLabel(pic, im["alt"].s)
    result.add pic
  else: result.add label("(picture not available: " & im["alt"].s & ")", "dim-label")
  if im["caption"].len > 0: result.add cw.rl(im["caption"], "dim-label caption")
  if im["credit"].len > 0: result.add cw.rl(im["credit"], "dim-label caption")

proc kksTool(cw: CW): W =
  let box = vbox(8)
  gtk_widget_add_css_class(box, "card")
  margins(box, 0)
  let inner = vbox(8)
  margins(inner, 12)
  let entry = gtk_entry_new()
  gtk_editable_set_text(entry, "11 LAB 70 AA 501")
  setAccessibleLabel(entry, "KKS code")
  let res = vbox(6)
  proc decode() =
    res.clear()
    let raw = entry.text.toUpperAscii.multiReplace((" ", ""), ("_", ""), (".", ""), ("-", ""))
    let ok = raw.len in 12..13 and raw[0 .. 1].allCharsInSet(Digits) and raw[2 .. 4].allCharsInSet(UppercaseLetters) and
             raw[5 .. 6].allCharsInSet(Digits) and raw[7 .. 8].allCharsInSet(UppercaseLetters) and raw[9 .. 11].allCharsInSet(Digits) and
             (raw.len == 12 or raw[12] in UppercaseLetters)
    if not ok:
      res.add label("Can't read that code. Expected something like 11 LAB 70 AA 501: unit digits, three system letters, " &
                    "two digits, two equipment letters, three digits.")
      return
    let T = cw.w.m.kksTables
    proc look(table, k: string): string =
      if T != nil and T.get(table) != nil and T[table].get(k) != nil: T[table][k].s else: "not in the plant tables"
    var rows = @[(raw[0 .. 1], "Unit", look("blocks", raw[0 .. 1])), (raw[2 .. 4], "System", look("systems", raw[2 .. 4])),
                 (raw[5 .. 6], "System number", "section " & raw[5 .. 6] & " of that system"),
                 (raw[7 .. 8], "Equipment type", look("components", raw[7 .. 8])), (raw[9 .. 11], "Equipment number", "item " & raw[9 .. 11])]
    if raw.len == 13: rows.add (raw[12 .. 12], "Suffix", "a letter after the number (a second element of the same item)")
    var t = newObj(@[("head", newArr(@[txt("Part"), txt("Is"), txt("Meaning")])), ("rows", newArr()), ("num", newArr())])
    for (a, b, c) in rows:
      t["rows"].elems.add newArr(@[newArr(@[newObj(@[("num", newStr(a))])]), txt(b), txt(c)])
    res.add cw.table(t)
    let code = raw
    res.add button("Find " & raw & " on the drawings", "", proc () = discard cw.follow("kks:" & code))
  entry.on("changed", decode)
  decode()
  inner.add label("KKS code", "heading"), entry, res
  box.add inner
  box

proc blk(cw: CW, b: JNode, box: W) =
  if b.get("h") != nil:
    let level = int(b["level"].num)
    let l = heading(plain(b["h"]), level, if level == 2: "title-2" else: "title-4")
    gtk_widget_set_margin_top(l, 12)
    box.add l
  elif b.get("p") != nil: box.add cw.rl(b["p"])
  elif b.get("ul") != nil or b.get("ol") != nil:
    let items = if b.get("ul") != nil: b["ul"] else: b["ol"]
    let lst = vbox(4)
    for (i, it) in items.elems.pairs:
      let row = hbox(8)
      let mark = label(if b.get("ul") != nil: "•" else: $(i + 1) & ".", "", wrap = false)
      gtk_widget_set_valign(mark, GTK_ALIGN_START)
      let l = cw.rl(it)
      gtk_widget_set_hexpand(l, 1)
      row.add mark, l
      lst.add row
    box.add lst
  elif b.get("table") != nil: box.add cw.table(b["table"])
  elif b.get("callout") != nil:
    let k = b["callout"].s
    let c = vbox(4)
    gtk_widget_add_css_class(c, "card")
    let inner = vbox(4)
    margins(inner, 12)
    inner.add label(plain(b["label"]), if k == "flag": "heading warning" else: "caption-heading accent")
    cw.blocks(b["body"], inner)
    c.add inner
    box.add c
  elif b.get("cards") != nil:
    let fb = adw_wrap_box_new()
    adw_wrap_box_set_child_spacing(fb, 10)
    adw_wrap_box_set_line_spacing(fb, 10)
    for card in b["cards"].elems:
      let c = vbox(2)
      gtk_widget_add_css_class(c, "card")
      gtk_widget_set_size_request(c, 220, -1)
      let inner = vbox(2)
      margins(inner, 10)
      inner.add cw.rl(card[0], "heading"), cw.rl(card[1])
      c.add inner
      adw_wrap_box_append(fb, c)
    box.add fb
  elif b.get("chain") != nil:
    let fb = adw_wrap_box_new()
    adw_wrap_box_set_child_spacing(fb, 6)
    for (i, r) in b["chain"].elems.pairs:
      if i > 0:
        let a = label("→", "dim-label", wrap = false)
        setAccessibleLabel(a, "then")
        adw_wrap_box_append(fb, a)
      let l = cw.rl(r, "card", false)
      margins(l, 0)
      adw_wrap_box_append(fb, l)
    box.add fb
  elif b.get("figure") != nil: box.add cw.figure(b["figure"].s)
  elif b.get("image") != nil: box.add cw.image(b["image"])
  elif b.get("issues") != nil:
    let lst = vbox(10)
    for it in b["issues"].elems:
      let sev = it[0].s
      let row = vbox(2)
      row.add label(sev.capitalizeAscii & " · " & plain(it[1]), "heading " & (case sev
        of "high": "error"
        of "medium": "warning"
        else: "success"))
      row.add cw.rl(it[2])
      lst.add row
    box.add lst
  elif b.get("tool") != nil: box.add cw.kksTool()

proc blocks(cw: CW, bs: JNode, box: W) =
  for b in bs.elems: cw.blk(b, box)

# ---------------------------------------------------------------- questions (§5)

type QOpts = object
  suffix: string
  label: string
  once: bool
  onAnswer: proc (ok: bool)

proc feedback(cw: CW, fb: W, ok: bool, head: string, why: JNode) =
  fb.clear()
  let l = label(head, "heading " & (if ok: "success" else: "error"))
  fb.add l
  if why != nil and why.len > 0: fb.add cw.rl(why)

proc question(cw: CW, q: JNode, o: QOpts): W =
  let id = q["id"].s & o.suffix
  let card = vbox(8)
  gtk_widget_add_css_class(card, "card")
  let box = vbox(8)
  margins(box, 14)
  card.add box
  let typ = q["type"].s
  let kind = hbox(8)
  let kl = label((if o.label.len > 0: o.label elif typ == "scenario": "Scenario" elif typ == "order": "Put in order" else: "Practice").toUpperAscii,
                 "caption-heading accent", wrap = false)
  gtk_widget_set_hexpand(kl, 1)
  kind.add kl
  if q["src"].len > 0: kind.add cw.rl(q["src"], "dim-label caption", false)
  box.add kind
  if typ == "scenario":
    let g = gtk_grid_new()
    gtk_grid_set_column_spacing(g, 18)
    gtk_grid_set_row_spacing(g, 4)
    for (i, r) in q["panel"].elems.pairs:
      gtk_grid_attach(g, cw.rl(r["name"], "dim-label", false), 0, cint(i), 1, 1)
      let st = r["state"].s
      gtk_grid_attach(g, cw.rl(r["value"], "monospace " & (case st
        of "alarm": "warning"
        of "act": "error"
        of "ok": "success"
        else: ""), false), 1, cint(i), 1, 1)
    box.add g
  let ql = cw.rl(q["q"], "heading")
  box.add ql
  setAccessibleLabel(card, plain(q["q"]))
  let fb = vbox(4)
  if typ == "order":
    let seqBox = vbox(4)
    let pool = vbox(4)
    let steps = q["steps"].elems
    let order = shuffled(toSeq(0 ..< steps.len))
    var chosen: seq[int]
    var draw: proc ()
    proc stepBtn(i, n: int): W =
      let b = gtk_button_new()
      gtk_button_set_child(b, label((if n > 0: $n & ". " else: "· ") & plain(steps[i])))
      b.onClick(proc () =
        if n > 0: chosen.keepItIf(it != i) else: chosen.add i
        fb.clear()
        draw())
      b
    draw = proc () =
      seqBox.clear()
      pool.clear()
      for k, i in chosen: seqBox.add stepBtn(i, k + 1)
      for i in order:
        if i notin chosen: pool.add stepBtn(i, 0)
    box.add label("Your order", "dim-label caption"), seqBox, label("Steps to place", "dim-label caption"), pool
    let row = hbox(8)
    row.add button("Check order", "suggested-action", proc () =
      if chosen.len < steps.len:
        cw.feedback(fb, false, "Not finished.", txt("Place all " & $steps.len & " steps first."))
        return
      var n = 0
      var c = gtk_widget_get_first_child(seqBox)
      for k, i in chosen:
        if i == k: inc n
        if c != nil:
          gtk_widget_add_css_class(c, if i == k: "success" else: "error")
          c = gtk_widget_get_next_sibling(c)
      if n == steps.len:
        cw.feedback(fb, true, "All in the right order.", nil)
        cw.c.markSolved(id)
      else:
        cw.feedback(fb, false, $n & " of " & $steps.len & " in the right place.",
                    txt("Red steps are out of position. Take a step back by pressing it, or start again.")))
    row.add button("Start again", "", proc () =
      chosen.setLen(0)
      fb.clear()
      draw())
    box.add row, fb
    draw()
    return card
  let optsBox = vbox(6)
  var first = true
  var btns: seq[W]
  let optList = q["options"].elems
  for i in 0 ..< optList.len:
    closureScope:
      let o2 = optList[i]
      let b = gtk_button_new()
      let l = cw.rl(o2["text"], "", false)
      gtk_button_set_child(b, l)
      btns.add b
      b.onClick(proc () =
        if o.once and not first: return
        for x in btns: gtk_widget_remove_css_class(x, "error")
        let right = o2["right"].b
        gtk_widget_add_css_class(b, if right: "success" else: "error")
        cw.feedback(fb, right, if right: "Right." else: "Not quite.", o2["why"])
        if o.once:
          if not right:
            for (j, x) in q["options"].elems.pairs:
              if x["right"].b:
                gtk_widget_add_css_class(btns[j], "success")
                fb.add label("Correct answer: " & plain(x["text"]) & " " & plain(x["why"]))
          for x in btns: gtk_widget_set_sensitive(x, 0)
        if first:
          first = false
          if o.onAnswer != nil: o.onAnswer(right)
        if right: cw.c.markSolved(id))
      optsBox.add b
  box.add optsBox, fb
  card

# ---------------------------------------------------------------- pages (§6, §7)

proc head(cw: CW, box: W, eyebrow: string, title: JNode) =
  box.add label(eyebrow.toUpperAscii, "caption-heading dim-label")
  box.add heading(plain(title), 1, "title-1")

proc section(box: W, text: string) =
  let l = heading(text, 2, "title-3")
  gtk_widget_set_margin_top(l, 16)
  box.add l

proc footer(cw: CW, p: JNode, box: W) =
  let i = cw.c.pages.find(p)
  let row = hbox(8)
  gtk_widget_set_margin_top(row, 24)
  if i > 0:
    let prv = cw.c.pages[i - 1]["id"].s
    row.add button("← " & cw.c.pageTitle(cw.c.pages[i - 1]), "", proc () = cw.show(prv))
  let sp = vbox(0)
  gtk_widget_set_hexpand(sp, 1)
  row.add sp
  if i + 1 < cw.c.pages.len:
    let nxt = cw.c.pages[i + 1]["id"].s
    row.add button(cw.c.pageTitle(cw.c.pages[i + 1]) & " →", "suggested-action", proc () = cw.show(nxt))
  box.add row

proc modulePage(cw: CW, m: JNode, box: W) =
  cw.head(box, "Module " & m["n"].s, m["title"])
  if m["goals"].len > 0:
    let g = vbox(4)
    gtk_widget_add_css_class(g, "card")
    let inner = vbox(4)
    margins(inner, 12)
    inner.add label("AFTER THIS MODULE YOU CAN", "caption-heading dim-label")
    for x in m["goals"].elems: inner.add cw.rl(newArr(@[newStr("• ")] & x.elems))
    g.add inner
    box.add g
  let recall = cw.c.recall(m)
  if recall.len > 0:
    section(box, "From earlier modules")
    box.add label("Two questions from what you have already covered. Answer from memory.")
    for q in recall: box.add cw.question(q, QOpts(suffix: "_r", label: "Recall"))
  section(box, "Guess first")
  box.add cw.question(m["warm"], QOpts(label: "Before the lesson"))
  section(box, if m["n"].s == "0": "About this course" else: "The lesson")
  cw.blocks(m["body"], box)
  if m["worked"].kind != jNull:
    section(box, "Worked example")
    let card = vbox(8)
    gtk_widget_add_css_class(card, "card")
    let inner = vbox(8)
    margins(inner, 14)
    inner.add cw.rl(m["worked"]["case"], "heading")
    let stepsBox = vbox(8)
    inner.add stepsBox
    var k = 0
    let steps = m["worked"]["steps"].elems
    var btn: W
    btn = button("Predict the next step, then reveal it", "", proc () =
      if k < steps.len:
        stepsBox.add label("Step " & $(k + 1) & " · " & plain(steps[k][0]), "dim-label caption")
        stepsBox.add cw.rl(steps[k][1])
        inc k
      if k >= steps.len:
        gtk_button_set_label(btn, "All steps shown")
        gtk_widget_set_sensitive(btn, 0))
    inner.add btn
    card.add inner
    box.add card
  if m["practice"].len > 0:
    section(box, "Practice")
    box.add label("Every wrong answer tells you why. Retry until each is right.")
    for q in m["practice"].elems: box.add cw.question(q, QOpts())
  if m.get("bridge") != nil:
    section(box, plain(m["bridge"]["title"]))
    if m["bridge"]["intro"].len > 0: box.add cw.rl(m["bridge"]["intro"])
    for q in m["bridge"]["questions"].elems: box.add cw.question(q, QOpts(label: "Bridge"))

proc placementPage(cw: CW, p: JNode, box: W) =
  cw.head(box, "Test", p["title"])
  cw.blocks(p["intro"], box)
  let items = cw.c.items(p)
  var answers: seq[(string, bool)]
  let plan = vbox(4)
  plan.add label("Answer all " & $items.len & " to see which modules to take.", "dim-label")
  for i in 0 ..< items.len:
    closureScope:
      let it = items[i]
      let mod0 = it.module
      let m = cw.c.module(mod0)
      let onAns = proc (ok: bool) =
        answers.add (mod0, ok)
        if answers.len < items.len: return
        let (take, skip) = cw.c.placementPlan(answers)
        cw.c.setSkip(skip)
        plan.clear()
        plan.add label("Take:", "heading")
        if take.len == 0: plan.add label("none.")
        for ti in 0 ..< take.len:
          closureScope:
            let id = take[ti]["id"].s
            plan.add button(cw.c.pageTitle(take[ti]), "flat", proc () = cw.show(id))
        var names: seq[string]
        for x in cw.c.mods:
          if x["id"].s in skip: names.add cw.c.pageTitle(x)
        plan.add label("Can skip: " & (if names.len > 0: names.join(", ") else: "none."))
      box.add cw.question(it.q, QOpts(suffix: "_p", once: true, label: "Q" & $(i + 1) & " · " & cw.c.pageTitle(m),
                                      onAnswer: onAns))
  section(box, "Your plan")
  box.add plan

proc testPage(cw: CW, p: JNode, box: W) =
  cw.head(box, "Test", p["title"])
  cw.blocks(p["intro"], box)
  if cw.c.finalBest > 0: box.add label("Your best so far: " & $cw.c.finalBest, "dim-label")
  let items = cw.c.items(p)
  var score, answered = 0
  var missed: seq[string]
  let scoreL = label("0 / " & $items.len & " answered", "title-3")
  let more = vbox(6)
  for i in 0 ..< items.len:
    closureScope:
      let it = items[i]
      let mod0 = it.module
      let onAns = proc (ok: bool) =
        inc answered
        if ok: inc score
        elif mod0 notin missed: missed.add mod0
        gtk_label_set_text(scoreL, ($score & " / " & $answered & " right" & (if answered == items.len: " · finished" else: "")).cstring)
        if answered < items.len: return
        cw.c.recordScore(score)
        more.clear()
        cw.blocks(if score >= int(p["pass"].num): p["on_pass"] else: p["on_fail"], more)
        if missed.len > 0:
          more.add label("Revisit:", "heading")
          for mi in 0 ..< missed.len:
            closureScope:
              let mid = missed[mi]
              more.add button(cw.c.pageTitle(cw.c.module(mid)), "flat", proc () = cw.show(mid))
      box.add cw.question(it.q, QOpts(suffix: "_f", once: true, label: "Question " & $(i + 1) & " of " & $items.len,
                                      onAnswer: onAns))
  section(box, "Result")
  box.add scoreL, more

proc vocabPage(cw: CW, p: JNode, box: W) =
  cw.head(box, "Practice", p["title"])
  cw.blocks(p["intro"], box)
  let G = cw.c.doc["glossary"].elems
  var n, ok, streak = 0
  let card = vbox(8)
  gtk_widget_add_css_class(card, "card")
  let inner = vbox(8)
  margins(inner, 14)
  card.add inner
  let stat = label("", "dim-label monospace")
  let modL = label("", "dim-label")
  let term = label("", "title-1")
  let opts = vbox(6)
  let fb = vbox(4)
  var next: proc ()
  next = proc () =
    let cur = pick(G)
    var done = false
    modL.gtk_label_set_text(("Module " & cw.c.pageTitle(cw.c.module(cur["module"].s))).cstring)
    term.gtk_label_set_text(cur["term"].s.cstring)
    fb.clear()
    opts.clear()
    var others = shuffled(G.filterIt(it["term"].s != cur["term"].s))
    others.setLen(min(3, others.len))
    let choices = shuffled(@[cur] & others)
    for gi in 0 ..< choices.len:
      closureScope:
        let g2 = choices[gi]
        let b = gtk_button_new()
        gtk_button_set_child(b, cw.rl(g2["meaning"], "", false))
        b.onClick(proc () =
          if done: return
          done = true
          let right = g2["term"].s == cur["term"].s
          inc n
          if right:
            inc ok
            inc streak
          else: streak = 0
          gtk_widget_add_css_class(b, if right: "success" else: "error")
          if right: cw.feedback(fb, true, "Right.", nil)
          else: cw.feedback(fb, false, "Not quite.", txt("You picked the meaning of " & g2["term"].s & ". " & cur["term"].s & ": " & plain(cur["meaning"])))
          stat.gtk_label_set_text(($ok & "/" & $n & " right · streak " & $streak).cstring))
        opts.add b
  inner.add stat, modL, term, opts, fb, button("Next term", "suggested-action", proc () = next())
  next()
  box.add card

proc readingPage(cw: CW, p: JNode, box: W) =
  cw.head(box, "Practice", p["title"])
  cw.blocks(p["intro"], box)
  var cats: seq[string]
  for it in p["items"].elems:
    if it["cat"].s notin cats: cats.add it["cat"].s
  var on = toHashSet(cats)
  var n, ok, streak = 0
  let chips = hbox(6)
  let card = vbox(8)
  gtk_widget_add_css_class(card, "card")
  let inner = vbox(8)
  margins(inner, 14)
  card.add inner
  let stat = label("", "dim-label monospace")
  let reading = vbox(4)
  let fb = vbox(4)
  let judgeRow = hbox(8)
  var cur: (JNode, float, string)
  var answered = false
  var next: proc ()
  const Lbl = {"ok": "within limits", "alarm": "in alarm", "act": "beyond the action limit"}.toTable
  var jbtns: seq[(string, W)]
  const Judge = [("ok", "Within limits"), ("alarm", "Alarm"), ("act", "Beyond limit")]
  for ji in 0 ..< Judge.len:
    closureScope:
      let (a2, t) = Judge[ji]
      let b = button(t, "", nil)
      gtk_widget_set_hexpand(b, 1)
      jbtns.add (a2, b)
      b.onClick(proc () =
        if cur[0] == nil or answered: return
        answered = true
        let right = a2 == cur[2]
        inc n
        if right:
          inc ok
          inc streak
        else: streak = 0
        gtk_widget_add_css_class(b, if right: "success" else: "error")
        if not right:
          for (k, x) in jbtns:
            if k == cur[2]: gtk_widget_add_css_class(x, "success")
        cw.feedback(fb, right, (if right: "Right: " else: "Not quite: ") & Lbl[cur[2]] & ".", cur[0]["note"])
        stat.gtk_label_set_text(($ok & "/" & $n & " right · streak " & $streak).cstring))
      judgeRow.add b
  next = proc () =
    for (_, b) in jbtns:
      gtk_widget_remove_css_class(b, "success")
      gtk_widget_remove_css_class(b, "error")
    fb.clear()
    reading.clear()
    answered = false
    let pool = p["items"].elems.filterIt(it["cat"].s in on)
    if pool.len == 0:
      cur = (nil, 0.0, "")
      reading.add label("Pick at least one topic.")
      return
    let d = pick(pool)
    let v = pick(d["values"].elems).num
    cur = (d, v, judge(d, v))
    reading.add cw.rl(d["name"], "dim-label", false)
    reading.add label(readingText(v, d["unit"].s) & " " & d["unit"].s, "title-1 monospace")
    if d["context"].len > 0: reading.add cw.rl(d["context"], "dim-label", false)
  for ci in 0 ..< cats.len:
    closureScope:
      let c2 = cats[ci]
      let t = gtk_toggle_button_new_with_label(c2.cstring)
      gtk_toggle_button_set_active(t, 1)
      t.on("toggled", proc () =
        if gtk_toggle_button_get_active(t) != 0: on.incl c2 else: on.excl c2
        next())
      chips.add t
  inner.add stat, reading, judgeRow, fb, button("Next reading", "suggested-action", proc () = next())
  box.add chips, card
  next()

proc glossaryPage(cw: CW, p: JNode, box: W) =
  cw.head(box, "Reference", p["title"])
  cw.blocks(p["intro"], box)
  for m in cw.c.mods:
    var rows = newArr()
    for g in cw.c.doc["glossary"].elems:
      if g["module"].s == m["id"].s:
        rows.elems.add newArr(@[newArr(@[newObj(@[("b", txt(g["term"].s))])]), g["meaning"]])
    if rows.len > 0:
      section(box, m["n"].s & " · " & plain(m["title"]))
      box.add cw.table(newObj(@[("head", newArr(@[txt("Term"), txt("Meaning")])), ("rows", rows), ("num", newArr())]))

# ---------------------------------------------------------------- the window

proc fillRail(cw: CW) =
  gtk_list_box_remove_all(cw.railList)
  let (done, total) = cw.c.progress
  for pi in 0 ..< cw.c.pages.len:
   closureScope:
    let p = cw.c.pages[pi]
    let id = p["id"].s
    var sub = ""
    if p["kind"].s == "module":
      sub = (if cw.c.done(p): "done" else: "") & (if id in cw.c.skip: (if cw.c.done(p): " · " else: "") & "can skip" else: "")
    let r = navRow(cw.c.pageTitle(p), sub, "Open " & cw.c.pageTitle(p), proc () = cw.show(id))
    if id == cw.pageId: gtk_widget_add_css_class(r, "accent")
    gtk_list_box_append(cw.railList, r)
  adw_window_title_set_subtitle(cw.title, ($done & " of " & $total & " solved").cstring)

proc show(cw: CW, id: string) =
  let p = cw.c.page(id)
  if p == nil: return
  cw.pageId = id
  cw.c.setLast(id)
  cw.figs.setLen(0)
  cw.pageBox.clear()
  case p["kind"].s
  of "module": cw.modulePage(p, cw.pageBox)
  of "placement": cw.placementPage(p, cw.pageBox)
  of "test": cw.testPage(p, cw.pageBox)
  of "vocab_drill": cw.vocabPage(p, cw.pageBox)
  of "reading_drill": cw.readingPage(p, cw.pageBox)
  of "glossary": cw.glossaryPage(p, cw.pageBox)
  else:
    cw.head(cw.pageBox, p["eyebrow"].s, p["title"])
    cw.blocks(p["intro"], cw.pageBox)
    cw.blocks(p["body"], cw.pageBox)
  cw.footer(p, cw.pageBox)
  gtk_adjustment_set_value(gtk_scrolled_window_get_vadjustment(cw.scroller), 0)
  gtk_window_set_title(cw.window, (cw.c.pageTitle(p) & " — " & cw.c.doc["title"].s).cstring)
  cw.fillRail()

var windows: Table[string, CW]

proc scrollToFigure*() =
  ## tests (AT-SPI can't scroll GTK 4 widgets): bring each course window's first animated figure on screen
  for _, cw in windows:
    for v in cw.figs:
      if not v.ev.isStatic:
        let y = yIn(v.area, cw.pageBox)
        if not y.isNaN: gtk_adjustment_set_value(gtk_scrolled_window_get_vadjustment(cw.scroller), y - 80)
        break

proc courseWindows*(): seq[(string, W)] =
  ## the open course windows (tests take screenshots of them)
  for id, cw in windows: result.add (id, cw.window)

proc openCourse*(w: Win, id: string, page = "") =
  if id in windows and windows[id].window != nil:
    let cw = windows[id]
    if page.len > 0: cw.show(page)
    gtk_window_present(cw.window)
    return
  loadCourseFonts()
  let c = openCourse(w.a, id)
  if c == nil:
    w.toast("That course is not available on this device")
    return
  let cw = CW(w: w, c: c)
  windows[id] = cw
  cw.window = adw_application_window_new(gtk_window_get_application(w.window))
  gtk_window_set_default_size(cw.window, 1180, 860)
  cw.window.on("close-request", proc () = windows.del id)
  let split = adw_navigation_split_view_new()
  adw_navigation_split_view_set_min_sidebar_width(split, 240)
  adw_navigation_split_view_set_max_sidebar_width(split, 300)
  cw.railList = gtk_list_box_new()
  gtk_widget_add_css_class(cw.railList, "navigation-sidebar")
  gtk_list_box_set_selection_mode(cw.railList, GTK_SELECTION_NONE)
  setAccessibleLabel(cw.railList, "Course contents")
  cw.title = adw_window_title_new(c.doc["title"].s.cstring, "")
  adw_navigation_split_view_set_sidebar(split, page(toolbarView(headerBar(cw.title), scrolled(cw.railList)), "Contents"))
  cw.pageBox = vbox(12)
  margins(cw.pageBox, 24)
  gtk_widget_set_size_request(cw.pageBox, 320, -1)
  let clamp = adw_clamp_new()
  adw_clamp_set_maximum_size(clamp, 780)
  adw_clamp_set_child(clamp, cw.pageBox)
  cw.scroller = scrolled(clamp)
  let ch = headerBar(adw_window_title_new(c.doc["short"].s.cstring, ""))
  adw_navigation_split_view_set_content(split, page(toolbarView(ch, cw.scroller), c.doc["title"].s))
  adw_application_window_set_content(cw.window, split)
  c.onProgress.add proc () = cw.fillRail()
  cw.show(if page.len > 0 and c.page(page) != nil: page else: c.startPage()["id"].s)
  gtk_window_present(cw.window)

proc learningPage*(w: Win): W =
  ## the sidebar's Learning page: the courses with their progress
  let box = vbox(12)
  margins(box, 12)
  let list = gtk_list_box_new()
  gtk_widget_add_css_class(list, "boxed-list")
  gtk_list_box_set_selection_mode(list, GTK_SELECTION_NONE)
  let cs = listCourses(w.a)
  if cs.len == 0: box.add label("No courses on this device yet.", "dim-label")
  for ci in 0 ..< cs.len:
    closureScope:
      let cr = cs[ci]
      let id = cr.id
      var n = 0
      var solved: HashSet[string]
      try:
        let d = w.a.call("GET", "/api/progress", nil, {"course": id}.toTable)["data"]
        if d.get("solved") != nil:
          let o = parseStrict(d["solved"].s)
          for (k, v) in o.fields:
            if v.kind == jBool and v.b: solved.incl k
      except CatchableError: discard
      for q in cr.questions:
        if q in solved: inc n
      list.gtk_list_box_append(navRow(cr.title, cr.short & " · " & $n & " of " & $cr.questions.len & " solved",
                                      "Open " & cr.title, proc () = w.openCourse(id)))
  box.add list
  box.add label("Your progress is private: only your own devices can read it.", "dim-label caption")
  scrolled(box)
