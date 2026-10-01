## The courses on Windows (docs/COURSES.md, decision 0036): the Learning tab lists them; a course opens in its own
## window with the rail (a list) on the left and the page on the right. Text runs become RTF in read-only RichEdit
## controls (every course string escaped: `\`, `{`, `}`, non-ASCII as \uN), links found and marked in reading order.
## The page is rebuilt from its state after each answer (the scroll position and the focused control are kept), so
## the questions need no incremental widget updates. Page logic: apps/common/coursestate.nim.

import std/[strutils, tables, sets, sequtils, unicode, math]
import kks/[json, courses, model]
import appstate, coursestate
import w32, ui, win, coursefig, photos

proc viewNew(h: HWND): pointer {.importc: "kks_view_new", cdecl.}
proc viewFree(v: pointer) {.importc: "kks_view_free", cdecl.}
proc viewResize(v: pointer, w, h: cint) {.importc: "kks_view_resize", cdecl.}
proc viewBitmap(v: pointer, bgra: pointer, w, h: cint): cint {.importc: "kks_view_bitmap", cdecl.}
proc viewBegin(v: pointer, r, g, b: cfloat): cint {.importc: "kks_view_begin", cdecl.}
proc viewDrawBitmap(v: pointer, h: cint, x0, y0, x1, y1: cfloat, smooth: cint) {.importc: "kks_view_draw_bitmap", cdecl.}
proc viewEnd(v: pointer): cint {.importc: "kks_view_end", cdecl.}
proc jxlDecode(data: pointer, n: csize_t, w, h: ptr cint): pointer {.importc: "kks_jxl_decode", cdecl.}
proc cfree(p: pointer) {.importc: "kks_free", cdecl.}

# ---------------------------------------------------------------- RTF from runs and blocks

const RtfHead = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0\\fswiss Segoe UI;}{\\f1\\fmodern Consolas;}}" &
                "{\\colortbl;\\red22\\green34\\blue43;\\red31\\green95\\blue139;\\red86\\green100\\blue110;" &
                "\\red179\\green38\\blue30;\\red46\\green122\\blue78;\\red154\\green100\\blue18;}\\f0\\fs22\\cf1 "
  ## colours: 1 ink, 2 accent, 3 muted, 4 act, 5 ok, 6 alarm

proc rtfEsc*(s: string): string =
  for r in s.runes:
    let c = int(r)
    if c == ord('\\') or c == ord('{') or c == ord('}'): result.add "\\" & char(c)
    elif c == 10: result.add "\\line "
    elif c < 128: result.add char(c)
    elif c < 0x10000: result.add "\\u" & $(if c > 32767: c - 65536 else: c) & "?"
    else:
      let v = c - 0x10000
      for u in [0xD800 + (v shr 10), 0xDC00 + (v and 0x3FF)]: result.add "\\u" & $(u - 65536) & "?"

proc linkTarget(to: JNode): string =
  if to.get("url") != nil: return to["url"].s
  if to.get("kks") != nil: return "kks:" & to["kks"].s
  if to.get("course") != nil:
    return "course:" & to["course"].s & (if to.get("page") != nil: "#" & to["page"].s else: "")
  "page:" & to["page"].s

type Flow = object
  rtf: string
  links: seq[(string, string)]

proc runRtf(f: var Flow, r: JNode) =
  for x in r.elems:
    if x.kind == jStr: f.rtf.add rtfEsc(x.s)
    elif x.get("b") != nil:
      f.rtf.add "{\\b "
      f.runRtf(x["b"])
      f.rtf.add "}"
    elif x.get("i") != nil:
      f.rtf.add "{\\i "
      f.runRtf(x["i"])
      f.rtf.add "}"
    elif x.get("small") != nil:
      f.rtf.add "{\\fs19\\cf3 "
      f.runRtf(x["small"])
      f.rtf.add "}"
    elif x.get("num") != nil: f.rtf.add "{\\f1\\fs20 " & rtfEsc(x["num"].s) & "}"
    elif x.get("term") != nil:
      f.rtf.add "{\\ul "
      f.runRtf(x["term"])
      f.rtf.add "}"
    elif x.get("link") != nil:
      f.links.add (plain(x["link"]), linkTarget(x["to"]))
      f.rtf.add "{\\cf2 "
      f.runRtf(x["link"])
      f.rtf.add "}"

proc para(f: var Flow, r: JNode, fmt = "\\sa120") =
  f.rtf.add "\\pard" & fmt & " "
  f.runRtf(r)
  f.rtf.add "\\par\n"

proc rowRtf(f: var Flow, cells: seq[JNode], n, w: int, num: HashSet[int], head: bool) =
  f.rtf.add "\\trowd\\trgaph100\\trleft0"
  for i in 0 ..< n: f.rtf.add "\\clbrdrb\\brdrs\\brdrw10\\cellx" & $(w * (i + 1))
  f.rtf.add "\n"
  for i, c in cells:
    f.rtf.add "\\pard\\intbl" & (if i in num and not head: "\\qr" else: "") & (if head: "{\\b\\cf3 " else: "{")
    f.runRtf(c)
    f.rtf.add "}\\cell "
  f.rtf.add "\\row\n"

proc tableRtf(f: var Flow, t: JNode) =
  let n = max(1, t["head"].len)
  let w = 9600 div n
  var num: HashSet[int]
  for i in t["num"].elems: num.incl int(i.num)
  f.rowRtf(t["head"].elems, n, w, num, true)
  for r in t["rows"].elems: f.rowRtf(r.elems, n, w, num, false)
  f.rtf.add "\\pard\\sa120\\par\n"

proc blockRtf(f: var Flow, b: JNode) =
  if b.get("h") != nil:
    f.rtf.add "\\pard\\sb200\\sa80{\\b\\fs" & (if b["level"].num == 2: "30" else: "26") & " "
    f.runRtf(b["h"])
    f.rtf.add "}\\par\n"
  elif b.get("p") != nil: f.para(b["p"])
  elif b.get("ul") != nil or b.get("ol") != nil:
    let items = if b.get("ul") != nil: b["ul"] else: b["ol"]
    for i, it in items.elems:
      f.rtf.add "\\pard\\fi-300\\li400\\sa60\\tx400 " & (if b.get("ul") != nil: "\\u8226?" else: $(i + 1) & ".") & "\\tab "
      f.runRtf(it)
      f.rtf.add "\\par\n"
  elif b.get("table") != nil: f.tableRtf(b["table"])
  elif b.get("callout") != nil:
    let k = b["callout"].s
    f.rtf.add "\\pard\\li300\\sb80\\sa40{\\b\\cf" & (if k == "flag": "6" else: "2") & " "
    f.runRtf(b["label"])
    f.rtf.add "}\\par\n"
    for x in b["body"].elems:
      if x.get("p") != nil: f.para(x["p"], "\\li300\\sa80")
      else: f.blockRtf(x)
  elif b.get("cards") != nil:
    for c in b["cards"].elems:
      f.rtf.add "\\pard\\li200\\sa20{\\b "
      f.runRtf(c[0])
      f.rtf.add "}\\par\n"
      f.para(c[1], "\\li200\\sa100")
  elif b.get("chain") != nil:
    f.rtf.add "\\pard\\sa120 "
    for i, r in b["chain"].elems:
      if i > 0: f.rtf.add " {\\cf3 \\u8594?} "
      f.rtf.add "{\\b "
      f.runRtf(r)
      f.rtf.add "}"
    f.rtf.add "\\par\n"
  elif b.get("issues") != nil:
    for it in b["issues"].elems:
      let sev = it[0].s
      f.rtf.add "\\pard\\sa100{\\b\\cf" & (case sev
        of "high": "4"
        of "medium": "6"
        else: "5") & " " & rtfEsc(sev.capitalizeAscii) & "} {\\b "
      f.runRtf(it[1])
      f.rtf.add ".} "
      f.runRtf(it[2])
      f.rtf.add "\\par\n"

# ---------------------------------------------------------------- the course window

type
  QState = object
    picked: seq[int]          ## options picked, in order
    chosen: seq[int]          ## order questions: steps placed
    checked: bool
  CW = ref object
    w: Win
    c: Course
    hwnd, rail, railGo: HWND
    page: Page
    pageId: string
    q: Table[string, QState]  ## by question id with its suffix
    worked: int
    recall: seq[JNode]
    items: seq[Item]          ## the test or placement as drawn when the page opened
    figs: Table[string, Figure]
    drill: (JNode, float, string)
    drillCats: HashSet[string]
    drillAnswer: string
    vocab: (JNode, seq[JNode])
    vocabPick: int
    stats: (int, int, int)    ## drills: answered, right, streak
    focusKey: string
    keys: Table[string, HWND]

var courseWins = initTable[HWND, CW]()
var openById = initTable[string, CW]()

proc show(cw: CW, id: string, keepScroll = false)
proc openCourseWindow*(w: Win, id: string, page = "")

proc follow(cw: CW, target: string) =
  if target.startsWith("page:"): cw.show(target[5 .. ^1])
  elif target.startsWith("course:"):
    let parts = target[7 .. ^1].split('#', 1)
    openCourseWindow(cw.w, parts[0], if parts.len > 1: parts[1] else: "")
  elif target.startsWith("kks:"):
    let code = target[4 .. ^1]
    for t in cw.w.m.tags:
      if t.full == code or t.kks == code:
        cw.w.showSheet(t.sheet)
        cw.w.selectTag(t.id, true)
        discard SetForegroundWindow(cw.w.hwnd)
        return
    cw.w.toast(code & " is not on any sheet")
  elif target.startsWith("https://"):
    discard ShellExecuteW(nil, newWideCString("open"), newWideCString(target), nil, nil, 1)

proc rebuild(cw: CW) = cw.show(cw.pageId, keepScroll = true)

proc key(cw: CW, k: string, h: HWND) = cw.keys[k] = h

proc flowOut(cw: CW, f: var Flow) =
  if f.rtf.len > 0:
    cw.page.rich(RtfHead & f.rtf & "}", f.links)
    f = Flow()

# ---- pictures inside the page
type Pic = ref object
  hwnd: HWND
  v: pointer
  px: seq[byte]
  w, h: int
  bmp: cint
var pics = initTable[HWND, Pic]()
var picClass = false
proc picProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  let p = pics.getOrDefault(h)
  if p == nil: return DefWindowProcW(h, m, wp, lp)
  case m
  of WM_PAINT:
    var ps: PAINTSTRUCT
    discard BeginPaint(h, addr ps)
    var r: RECT
    GetClientRect(h, addr r)
    if viewBegin(p.v, 0.97, 0.98, 0.98) != 0:
      if p.bmp == 0: p.bmp = viewBitmap(p.v, addr p.px[0], cint(p.w), cint(p.h))
      viewDrawBitmap(p.v, p.bmp, 0, 0, cfloat(r.right), cfloat(r.bottom), 1)
      if viewEnd(p.v) == 0: p.bmp = 0
    EndPaint(h, addr ps)
    return 0
  of WM_ERASEBKGND: return 1
  of WM_SIZE:
    viewResize(p.v, cint(loword(lp)), cint(hiword(lp)))
    InvalidateRect(h, nil, 0)
    return 0
  of WM_DESTROY:
    viewFree(p.v)
    pics.del h
    return 0
  else: discard
  DefWindowProcW(h, m, wp, lp)

proc picture(cw: CW, im: JNode) =
  let (ok, data) = cw.w.a.courseImage(im["file"].s)
  var iw, ih: cint
  let px = if ok and data.len > 0: jxlDecode(unsafeAddr data[0], csize_t(data.len), addr iw, addr ih) else: nil
  if px == nil:
    cw.page.dim("(picture not available: " & im["alt"].s & ")")
    return
  if not picClass:
    let cls = newWideCString("KKSPicture")
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: picProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), lpszClassName: cls)
    discard RegisterClassExW(addr wc)
    picClass = true
  let p = Pic(w: int(iw), h: int(ih))
  p.px = newSeq[byte](p.w * p.h * 4)
  copyMem(addr p.px[0], px, p.px.len)
  cfree(px)
  p.hwnd = CreateWindowExW(0, newWideCString("KKSPicture"), newWideCString(im["alt"].s), WS_CHILD or WS_VISIBLE,
                           0, 0, 10, 10, cw.page.hwnd, nil, hinst, nil)
  p.v = viewNew(p.hwnd)
  pics[p.hwnd] = p
  # at most 680 DIPs wide and 420 tall
  let s = min(680.0 / float(p.w), 420.0 / float(p.h))
  cw.page.aspect(p.hwnd, int(float(p.w) * s), int(float(p.h) * s))
  var f = Flow()
  if im["caption"].len > 0: f.para(im["caption"], "\\sa20\\fs19\\cf3")
  if im["credit"].len > 0: f.para(im["credit"], "\\sa100\\fs17\\cf3")
  cw.flowOut(f)

# ---- figures
proc figure(cw: CW, id: string, n: int) =
  let f = cw.c.doc["figures"][id]
  let k = cw.pageId & "/" & id & "/" & $n
  cw.page.label(f["title"].s)
  let v = figureView(cw.page.hwnd, f, cw.figs.getOrDefault(k))
  cw.figs[k] = v.ev
  cw.page.aspect(v.hwnd, int(f["w"].num), int(f["h"].num))
  if not v.ev.isStatic:
    v.status = cw.page.dim("")
    let st = v.ev.status()
    if st.kind == jStr: v.status.setText(st.s)
    let ev = v.ev
    let playLabel = if ev.playing: "Pause" else: "Play"
    let btns = cw.page.buttons(@[(playLabel, proc () =
      if ev.playing: ev.pause() else: ev.play()
      cw.focusKey = k & "/play"
      cw.rebuild())])
    cw.key(k & "/play", btns[0])
    if f.get("slider") != nil:
      let sl = cw.page.slider(f["slider"]["label"].s, ev.v, proc (x: float) =
        ev.setSlider(x)
        ev.tick(0)
        InvalidateRect(v.hwnd, nil, 0))
      v.slider = sl
      v.sliderOut = cw.page.dim(ev.sliderText().s)
    if f.get("toggles") != nil:
      let tgs = f["toggles"].elems
      for ti in 0 ..< tgs.len:
        closureScope:
          let kk = tgs[ti]["key"].s
          cw.page.check(tgs[ti]["label"].s, ev.toggles.getOrDefault(kk) >= 0.5, proc (on: bool) =
            ev.toggle(kk)
            InvalidateRect(v.hwnd, nil, 0))
    if f.get("modes") != nil:
      cw.page.radios(f["modes"].elems.mapIt(it["label"].s), ev.mode, proc (i: int) =
        ev.setMode(i)
        InvalidateRect(v.hwnd, nil, 0))
    v.onTick = proc () =
      let s = ev.status()
      if s.kind == jStr and v.status != nil: v.status.setText(s.s)
      if v.slider != nil:
        SendMessageW(v.slider, TBM_SETPOS, 1, LPARAM(int(ev.v * 1000)))
        v.sliderOut.setText(ev.sliderText().s)
  if f["caption"].len > 0:
    var fl = Flow()
    fl.para(f["caption"], "\\sa100\\fs19\\cf3")
    cw.flowOut(fl)

proc kksTool(cw: CW) =
  let e = cw.page.field("KKS code", "11 LAB 70 AA 501")
  let T = cw.w.m.kksTables
  proc look(table, k: string): string =
    if T != nil and T.get(table) != nil and T[table].get(k) != nil: T[table][k].s else: "not in the plant tables"
  let res = cw.page.label("Type a code, then Decode.")
  cw.page.buttons(("Decode", proc () =
    let raw = e.text.toUpperAscii.multiReplace((" ", ""), ("_", ""), (".", ""), ("-", ""))
    if raw.len < 12 or not (raw[0 .. 1].allCharsInSet(Digits) and raw[2 .. 4].allCharsInSet(UppercaseLetters) and
                            raw[5 .. 6].allCharsInSet(Digits) and raw[7 .. 8].allCharsInSet(UppercaseLetters) and
                            raw[9 .. 11].allCharsInSet(Digits)):
      res.setText("Can't read that code. Expected something like 11 LAB 70 AA 501.")
    else:
      res.setText("Unit " & raw[0 .. 1] & ": " & look("blocks", raw[0 .. 1]) & "\nSystem " & raw[2 .. 4] & ": " &
                  look("systems", raw[2 .. 4]) & "\nSystem number " & raw[5 .. 6] & "\nEquipment type " & raw[7 .. 8] &
                  ": " & look("components", raw[7 .. 8]) & "\nEquipment number " & raw[9 .. 11])
    cw.page.layout()), ("Find on the drawings", proc () =
    cw.follow("kks:" & e.text.toUpperAscii.replace(" ", ""))))

proc blocks(cw: CW, bs: JNode) =
  var f = Flow()
  var n = 0
  for b in bs.elems:
    if b.get("figure") != nil:
      cw.flowOut(f)
      cw.figure(b["figure"].s, n)
      inc n
    elif b.get("image") != nil:
      cw.flowOut(f)
      cw.picture(b["image"])
    elif b.get("tool") != nil:
      cw.flowOut(f)
      cw.kksTool()
    else: f.blockRtf(b)
  cw.flowOut(f)

# ---- questions
type QOpts = object
  suffix, label: string
  once: bool
  onAnswer: proc (ok: bool)

proc question(cw: CW, q: JNode, o: QOpts) =
  let id = q["id"].s & o.suffix
  var st = cw.q.getOrDefault(id)
  let typ = q["type"].s
  cw.page.dim((if o.label.len > 0: o.label elif typ == "scenario": "Scenario" elif typ == "order": "Put in order" else: "Practice").toUpperAscii &
              (if q["src"].len > 0: "   " & plain(q["src"]) else: ""))
  var f = Flow()
  if typ == "scenario":
    for r in q["panel"].elems:
      f.rtf.add "\\pard\\li200\\sa20{\\cf3 "
      f.runRtf(r["name"])
      f.rtf.add "}\\tab {\\f1\\b" & (case r["state"].s
        of "alarm": "\\cf6"
        of "act": "\\cf4"
        of "ok": "\\cf5"
        else: "") & " "
      f.runRtf(r["value"])
      f.rtf.add "}\\par\n"
  f.rtf.add "\\pard\\sa80{\\b "
  f.runRtf(q["q"])
  f.rtf.add "}\\par\n"
  cw.flowOut(f)
  if typ == "order":
    let steps = q["steps"].elems
    var order = toSeq(0 ..< steps.len)
    # a fixed shuffle per question (the page is rebuilt often)
    var h = 0
    for ch in id: h = h * 31 + ord(ch)
    for i in countdown(order.high, 1):
      h = (h * 1103515245 + 12345) and 0x7fffffff
      swap(order[i], order[h mod (i + 1)])
    proc takeBack(ii: int): proc () =
      result = proc () =
        var s2 = cw.q.getOrDefault(id)
        s2.chosen.keepItIf(it != ii)
        s2.checked = false
        cw.q[id] = s2
        cw.focusKey = id & "/pool"
        cw.rebuild()
    proc place(ii: int): proc () =
      result = proc () =
        var s2 = cw.q.getOrDefault(id)
        s2.chosen.add ii
        s2.checked = false
        cw.q[id] = s2
        cw.focusKey = id & "/pool"
        cw.rebuild()
    var specs: seq[(string, proc ())]
    for k, i in st.chosen:
      specs.add ($(k + 1) & ". " & plain(steps[i]) & (if st.checked: (if i == k: "  (right place)" else: "  (wrong place)") else: ""), takeBack(i))
    if specs.len > 0:
      cw.page.dim("Your order (press a step to take it back):")
      cw.page.tallButtons(specs)
    var pool: seq[(string, proc ())]
    for i in order:
      if i notin st.chosen: pool.add ("· " & plain(steps[i]), place(i))
    if pool.len > 0:
      cw.page.dim("Steps to place:")
      let bs = cw.page.tallButtons(pool)
      cw.key(id & "/pool", bs[0])
    let bs = cw.page.buttons(("Check order", proc () =
      var s2 = cw.q.getOrDefault(id)
      s2.checked = true
      cw.q[id] = s2
      if s2.chosen.len == steps.len and toSeq(0 ..< steps.len) == s2.chosen: cw.c.markSolved(id)
      cw.focusKey = id & "/check"
      cw.rebuild()), ("Start again", proc () =
      cw.q[id] = QState()
      cw.rebuild()))
    cw.key(id & "/check", bs[0])
    if st.checked:
      if st.chosen.len < steps.len: cw.page.label("Not finished. Place all " & $steps.len & " steps first.")
      else:
        var good = 0
        for k, i in st.chosen:
          if i == k: inc good
        cw.page.label(if good == steps.len: "Right: all in the right order." else: $good & " of " & $steps.len & " in the right place.")
    cw.page.space(14)
    return
  let opts = q["options"].elems
  let locked = o.once and st.picked.len > 0
  proc pickOpt(ii: int): proc () =
    result = proc () =
      var s2 = cw.q.getOrDefault(id)
      if o.once and s2.picked.len > 0: return
      let first = s2.picked.len == 0
      s2.picked.add ii
      cw.q[id] = s2
      let right = opts[ii]["right"].b
      if right: cw.c.markSolved(id)
      if first and o.onAnswer != nil: o.onAnswer(right)
      cw.focusKey = id & "/" & $ii
      cw.rebuild()
  var specs: seq[(string, proc ())]
  for i, opt in opts:
    var mark = ""
    if i in st.picked: mark = if opt["right"].b: "  ✓ right" else: "  ✗ not quite"
    elif locked and opt["right"].b: mark = "  ✓ the right answer"
    specs.add (plain(opt["text"]) & mark, pickOpt(i))
  let bs = cw.page.tallButtons(specs)
  for i, b in bs: cw.key(id & "/" & $i, b)
  if st.picked.len > 0:
    let last = opts[st.picked[^1]]
    var fb = Flow()
    fb.rtf.add "\\pard\\sa60{\\b\\cf" & (if last["right"].b: "5 Right." else: "4 Not quite.") & "} "
    fb.runRtf(last["why"])
    fb.rtf.add "\\par\n"
    if locked and not last["right"].b:
      for x in opts:
        if x["right"].b:
          fb.rtf.add "\\pard\\sa60{\\b\\cf5 Correct answer:} "
          fb.runRtf(x["text"])
          fb.rtf.add " "
          fb.runRtf(x["why"])
          fb.rtf.add "\\par\n"
    cw.flowOut(fb)
  cw.page.space(14)

# ---- pages
proc head(cw: CW, eyebrow: string, title: JNode) =
  cw.page.dim(eyebrow.toUpperAscii)
  cw.page.title(plain(title))

proc section(cw: CW, text: string) =
  cw.page.space(10)
  cw.page.title(text)

proc modulePage(cw: CW, m: JNode) =
  cw.head("Module " & m["n"].s, m["title"])
  if m["goals"].len > 0:
    var f = Flow()
    f.rtf.add "\\pard\\sa40{\\b\\fs19\\cf3 AFTER THIS MODULE YOU CAN}\\par\n"
    for g in m["goals"].elems:
      f.rtf.add "\\pard\\fi-300\\li400\\sa40\\tx400 \\u8226?\\tab "
      f.runRtf(g)
      f.rtf.add "\\par\n"
    cw.flowOut(f)
  if cw.recall.len > 0:
    cw.section("From earlier modules")
    cw.page.label("Two questions from what you have already covered. Answer from memory.")
    for q in cw.recall: cw.question(q, QOpts(suffix: "_r", label: "Recall"))
  cw.section("Guess first")
  cw.question(m["warm"], QOpts(label: "Before the lesson"))
  cw.section(if m["n"].s == "0": "About this course" else: "The lesson")
  cw.blocks(m["body"])
  if m["worked"].kind != jNull:
    cw.section("Worked example")
    var f = Flow()
    f.para(m["worked"]["case"], "\\sa80\\b")
    for k in 0 ..< min(cw.worked, m["worked"]["steps"].len):
      let s = m["worked"]["steps"][k]
      f.rtf.add "\\pard\\sa20{\\fs19\\cf3 Step " & $(k + 1) & " \\u183? "
      f.runRtf(s[0])
      f.rtf.add "}\\par\n"
      f.para(s[1])
    cw.flowOut(f)
    let total = m["worked"]["steps"].len
    if cw.worked < total:
      let bs = cw.page.buttons(("Predict the next step, then reveal it", proc () =
        inc cw.worked
        cw.focusKey = "worked"
        cw.rebuild()))
      cw.key("worked", bs[0])
    else: cw.page.dim("All steps shown")
  if m["practice"].len > 0:
    cw.section("Practice")
    cw.page.label("Every wrong answer tells you why. Retry until each is right.")
    for q in m["practice"].elems: cw.question(q, QOpts())
  if m.get("bridge") != nil:
    cw.section(plain(m["bridge"]["title"]))
    if m["bridge"]["intro"].len > 0: cw.page.label(plain(m["bridge"]["intro"]))
    for q in m["bridge"]["questions"].elems: cw.question(q, QOpts(label: "Bridge"))

proc answersOf(cw: CW, suffix: string): seq[(Item, bool)] =
  for it in cw.items:
    let st = cw.q.getOrDefault(it.q["id"].s & suffix)
    if st.picked.len > 0: result.add (it, it.q["options"][st.picked[0]]["right"].b)

proc placementPage(cw: CW, p: JNode) =
  cw.head("Test", p["title"])
  cw.blocks(p["intro"])
  for i, it in cw.items:
    cw.question(it.q, QOpts(suffix: "_p", once: true, label: "Q" & $(i + 1) & " · " & cw.c.pageTitle(cw.c.module(it.module))))
  cw.section("Your plan")
  let ans = cw.answersOf("_p")
  if ans.len < cw.items.len:
    cw.page.dim("Answer all " & $cw.items.len & " to see which modules to take.")
    return
  let (take, skip) = cw.c.placementPlan(ans.mapIt((it[0].module, it[1])))
  if skip != cw.c.skip: cw.c.setSkip(skip)
  cw.page.label("Take:")
  proc go(id: string): proc () =
    result = proc () = cw.show(id)
  var specs: seq[(string, proc ())]
  for m in take: specs.add (cw.c.pageTitle(m), go(m["id"].s))
  if specs.len > 0: discard cw.page.buttons(specs) else: discard cw.page.dim("none.")
  var names: seq[string]
  for m in cw.c.mods:
    if m["id"].s in skip: names.add cw.c.pageTitle(m)
  cw.page.label("Can skip: " & (if names.len > 0: names.join(", ") else: "none."))

proc testPage(cw: CW, p: JNode) =
  cw.head("Test", p["title"])
  cw.blocks(p["intro"])
  if cw.c.finalBest > 0: cw.page.dim("Your best so far: " & $cw.c.finalBest)
  for i, it in cw.items:
    cw.question(it.q, QOpts(suffix: "_f", once: true, label: "Question " & $(i + 1) & " of " & $cw.items.len))
  cw.section("Result")
  let ans = cw.answersOf("_f")
  let score = ans.countIt(it[1])
  cw.page.label($score & " / " & $ans.len & " right" & (if ans.len == cw.items.len: " · finished" else: ""))
  if ans.len == cw.items.len:
    cw.c.recordScore(score)
    cw.blocks(if score >= int(p["pass"].num): p["on_pass"] else: p["on_fail"])
    var missed: seq[string]
    for (it, ok) in ans:
      if not ok and it.module notin missed: missed.add it.module
    if missed.len > 0:
      cw.page.label("Revisit:")
      proc go(id: string): proc () =
        result = proc () = cw.show(id)
      var specs: seq[(string, proc ())]
      for id in missed: specs.add (cw.c.pageTitle(cw.c.module(id)), go(id))
      cw.page.buttons(specs)

proc vocabPage(cw: CW, p: JNode) =
  cw.head("Practice", p["title"])
  cw.blocks(p["intro"])
  let G = cw.c.doc["glossary"].elems
  if cw.vocab[0] == nil:
    let cur = pick(G)
    var others = shuffled(G.filterIt(it["term"].s != cur["term"].s))
    others.setLen(min(3, others.len))
    cw.vocab = (cur, shuffled(@[cur] & others))
    cw.vocabPick = -1
  let (cur, choices) = cw.vocab
  let (n, ok, streak) = cw.stats
  if n > 0: cw.page.dim($ok & "/" & $n & " right · streak " & $streak)
  cw.page.dim("Module " & cw.c.pageTitle(cw.c.module(cur["module"].s)))
  cw.page.title(cur["term"].s)
  proc choose(ii: int): proc () =
    result = proc () =
      if cw.vocabPick >= 0: return
      cw.vocabPick = ii
      let right = choices[ii] == cur
      cw.stats = (cw.stats[0] + 1, cw.stats[1] + ord(right), if right: cw.stats[2] + 1 else: 0)
      cw.focusKey = "vocab/" & $ii
      cw.rebuild()
  var specs: seq[(string, proc ())]
  for i, g in choices:
    var mark = ""
    if cw.vocabPick >= 0:
      if g == cur: mark = "  ✓ right"
      elif i == cw.vocabPick: mark = "  ✗ the meaning of " & g["term"].s
    specs.add (plain(g["meaning"]) & mark, choose(i))
  let bs = cw.page.tallButtons(specs)
  for i, b in bs: cw.key("vocab/" & $i, b)
  let nb = cw.page.buttons(("Next term", proc () =
    cw.vocab = (nil, @[])
    cw.focusKey = "vocab/next"
    cw.rebuild()))
  cw.key("vocab/next", nb[0])

proc readingPage(cw: CW, p: JNode) =
  cw.head("Practice", p["title"])
  cw.blocks(p["intro"])
  var cats: seq[string]
  for it in p["items"].elems:
    if it["cat"].s notin cats: cats.add it["cat"].s
  if cw.drillCats.len == 0 and cw.drill[0] == nil: cw.drillCats = toHashSet(cats)
  proc toggleCat(cc: string): proc (on: bool) =
    result = proc (on: bool) =
      if on: cw.drillCats.incl cc else: cw.drillCats.excl cc
      cw.drill = (nil, 0.0, "")
      cw.rebuild()
  for c in cats: cw.page.check(c, c in cw.drillCats, toggleCat(c))
  let pool = p["items"].elems.filterIt(it["cat"].s in cw.drillCats)
  if pool.len == 0:
    cw.page.label("Pick at least one topic.")
    return
  if cw.drill[0] == nil:
    let d = pick(pool)
    let v = pick(d["values"].elems).num
    cw.drill = (d, v, judge(d, v))
    cw.drillAnswer = ""
  let (d, v, want) = cw.drill
  let (n, ok, streak) = cw.stats
  if n > 0: cw.page.dim($ok & "/" & $n & " right · streak " & $streak)
  cw.page.dim(plain(d["name"]))
  cw.page.title(readingText(v, d["unit"].s) & " " & d["unit"].s)
  if d["context"].len > 0: cw.page.dim(plain(d["context"]))
  const Lbl = {"ok": "within limits", "alarm": "in alarm", "act": "beyond the action limit"}.toTable
  proc answer(aa: string): proc () =
    result = proc () =
      if cw.drillAnswer.len > 0: return
      cw.drillAnswer = aa
      let right = aa == want
      cw.stats = (cw.stats[0] + 1, cw.stats[1] + ord(right), if right: cw.stats[2] + 1 else: 0)
      cw.focusKey = "drill/" & aa
      cw.rebuild()
  var specs: seq[(string, proc ())]
  for (a, t) in [("ok", "Within limits (no alarm)"), ("alarm", "Alarm (investigate, correct)"), ("act", "Beyond limit (stop, hold, trip, don't start)")]:
    var mark = ""
    if cw.drillAnswer.len > 0:
      if a == want: mark = "  ✓"
      elif a == cw.drillAnswer: mark = "  ✗"
    specs.add (t & mark, answer(a))
  let bs = cw.page.tallButtons(specs)
  for i, a in ["ok", "alarm", "act"]: cw.key("drill/" & a, bs[i])
  if cw.drillAnswer.len > 0:
    var f = Flow()
    f.rtf.add "\\pard\\sa60{\\b\\cf" & (if cw.drillAnswer == want: "5 Right: " else: "4 Not quite: ") & rtfEsc(Lbl[want]) & ".} "
    f.runRtf(d["note"])
    f.rtf.add "\\par\n"
    cw.flowOut(f)
  let nb = cw.page.buttons(("Next reading", proc () =
    cw.drill = (nil, 0.0, "")
    cw.focusKey = "drill/next"
    cw.rebuild()))
  cw.key("drill/next", nb[0])

proc glossaryPage(cw: CW, p: JNode) =
  cw.head("Reference", p["title"])
  cw.blocks(p["intro"])
  for m in cw.c.mods:
    var rows = newArr()
    for g in cw.c.doc["glossary"].elems:
      if g["module"].s == m["id"].s:
        rows.elems.add newArr(@[newArr(@[newObj(@[("b", newArr(@[newStr(g["term"].s)]))])]), g["meaning"]])
    if rows.len > 0:
      cw.section(m["n"].s & " · " & plain(m["title"]))
      var f = Flow()
      f.tableRtf(newObj(@[("head", newArr(@[newArr(@[newStr("Term")]), newArr(@[newStr("Meaning")])])), ("rows", rows),
                          ("num", newArr())]))
      cw.flowOut(f)

proc fillRail(cw: CW) =
  var rows: seq[string]
  for p in cw.c.pages:
    let id = p["id"].s
    var t = cw.c.pageTitle(p)
    if p["kind"].s == "module":
      if cw.c.done(p): t.add "  ✓"
      if id in cw.c.skip: t.add "  (can skip)"
    rows.add t
  setRows(cw.rail, rows)
  let i = cw.c.pages.mapIt(it["id"].s).find(cw.pageId)
  if i >= 0: SendMessageW(cw.rail, LB_SETCURSEL, WPARAM(i), 0)
  let (done, total) = cw.c.progress
  cw.hwnd.setText(cw.c.doc["title"].s & " — " & $done & " of " & $total & " solved")

proc show(cw: CW, id: string, keepScroll = false) =
  let p = cw.c.page(id)
  if p == nil: return
  let fresh = id != cw.pageId or not keepScroll
  if fresh:
    cw.q.clear()
    cw.worked = 0
    cw.figs.clear()
    cw.drill = (nil, 0.0, "")
    cw.vocab = (nil, @[])
    cw.stats = (0, 0, 0)
    case p["kind"].s
    of "module": cw.recall = cw.c.recall(p)
    of "placement", "test": cw.items = cw.c.items(p)
    else: discard
  let scroll = if fresh: 0 else: cw.page.scroll
  cw.pageId = id
  cw.c.setLast(id)
  cw.keys.clear()
  cw.page.clear()
  case p["kind"].s
  of "module": cw.modulePage(p)
  of "placement": cw.placementPage(p)
  of "test": cw.testPage(p)
  of "vocab_drill": cw.vocabPage(p)
  of "reading_drill": cw.readingPage(p)
  of "glossary": cw.glossaryPage(p)
  else:
    cw.head(p["eyebrow"].s, p["title"])
    cw.blocks(p["intro"])
    cw.blocks(p["body"])
  # previous / next
  let i = cw.c.pages.find(p)
  var nav: seq[(string, proc ())]
  if i > 0:
    let prv = cw.c.pages[i - 1]["id"].s
    nav.add ("← " & cw.c.pageTitle(cw.c.pages[i - 1]), proc () = cw.show(prv))
  if i + 1 < cw.c.pages.len:
    let nxt = cw.c.pages[i + 1]["id"].s
    nav.add (cw.c.pageTitle(cw.c.pages[i + 1]) & " →", proc () = cw.show(nxt))
  cw.page.space(16)
  cw.page.buttons(nav)
  cw.page.layout()
  if scroll > 0: cw.page.scrollTo(scroll)
  if cw.focusKey.len > 0 and cw.focusKey in cw.keys: SetFocus(cw.keys[cw.focusKey])
  cw.focusKey = ""
  cw.fillRail()

proc courseProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  let cw = courseWins.getOrDefault(h)
  try:
    case m
    of WM_SIZE:
      if cw != nil:
        let rw = px(260)
        MoveWindow(cw.rail, 0, 0, rw, int32(hiword(lp)) - px(40), 1)
        MoveWindow(cw.railGo, px(4), int32(hiword(lp)) - px(36), rw - px(8), px(32), 1)
        MoveWindow(cw.page.hwnd, rw, 0, int32(loword(lp)) - rw, int32(hiword(lp)), 1)
      return 0
    of WM_COMMAND:
      if dispatchCommand(wp, lp): return 0
    of WM_DESTROY:
      if cw != nil:
        courseWins.del h
        openById.del cw.c.id
      return 0
    else: discard
  except CatchableError as e: report(e)
  DefWindowProcW(h, m, wp, lp)

var courseClass = false

proc openCourseWindow*(w: Win, id: string, page = "") =
  if id in openById:
    let cw = openById[id]
    if page.len > 0: cw.show(page)
    discard SetForegroundWindow(cw.hwnd)
    return
  let c = openCourse(w.a, id)
  if c == nil:
    w.toast("That course is not available on this device")
    return
  if not courseClass:
    let cls = newWideCString("KKSCourse")
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: courseProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), hbrBackground: GetSysColorBrush(COLOR_WINDOW),
                         lpszClassName: cls)
    discard RegisterClassExW(addr wc)
    courseClass = true
  let cw = CW(w: w, c: c)
  cw.hwnd = CreateWindowExW(WS_EX_CONTROLPARENT, newWideCString("KKSCourse"), newWideCString(c.doc["title"].s),
                            WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, px(1180), px(860), nil, nil, hinst, nil)
  # never taller or wider than the work area (small laptop screens)
  var wa: RECT
  SystemParametersInfoW(0x0030, 0, addr wa, 0)         # SPI_GETWORKAREA
  MoveWindow(cw.hwnd, wa.left + 20, wa.top + 10, min(px(1180), wa.right - wa.left - 40), min(px(860), wa.bottom - wa.top - 20), 0)
  courseWins[cw.hwnd] = cw
  openById[id] = cw
  cw.page = newPage(cw.hwnd)
  let pages = c.pages
  let (rl, rid) = control(cw.hwnd, "LISTBOX", "Course contents", WS_TABSTOP or WS_VSCROLL or LBS_NOTIFY or LBS_NOINTEGRALHEIGHT, WS_EX_CLIENTEDGE)
  cw.rail = rl
  proc go(i: int) =
    if i >= 0 and i < pages.len and pages[i]["id"].s != cw.pageId: cw.show(pages[i]["id"].s)
  onSelectList(rid, go)
  onActivateList(rid, go)
  # a list item has no Invoke for UI Automation: a button opens the selected page (as in the main window)
  let (gb, gid) = control(cw.hwnd, "BUTTON", "Open the selected page", WS_TABSTOP or BS_PUSHBUTTON)
  cw.railGo = gb
  onClick(gid, proc () = go(int(SendMessageW(cw.rail, LB_GETCURSEL, 0, 0))))
  ui.onLink = proc (target: string) =
    for _, x in courseWins:
      if GetForegroundWindow() == x.hwnd:
        x.follow(target)
        return
    cw.follow(target)
  c.onProgress.add proc () = cw.fillRail()
  var r: RECT
  GetClientRect(cw.hwnd, addr r)
  SendMessageW(cw.hwnd, WM_SIZE, 0, LPARAM(int(r.right) or (int(r.bottom) shl 16)))
  cw.show(if page.len > 0 and c.page(page) != nil: page else: c.startPage()["id"].s)
  ShowWindow(cw.hwnd, SW_SHOW)

proc learningTab*(w: Win, p: Page) =
  ## the side's Learning tab: the courses with their progress
  let cs = listCourses(w.a)
  if cs.len == 0:
    p.dim("No courses on this device yet.")
    return
  var rows: seq[string]
  for cr in cs:
    var n = 0
    try:
      let d = w.a.call("GET", "/api/progress", nil, {"course": cr.id}.toTable)["data"]
      if d.get("solved") != nil:
        let o = parseStrict(d["solved"].s)
        for q in cr.questions:
          if o.get(q) != nil: inc n
    except CatchableError: discard
    rows.add cr.title & " — " & $n & " of " & $cr.questions.len & " solved"
  p.list(rows, 26 * cs.len + 8, onActivate = (proc (i: int) = w.openCourseWindow(cs[i].id)), openLabel = "Open the course")
  p.dim("Your progress is private: only your own devices can read it.")
