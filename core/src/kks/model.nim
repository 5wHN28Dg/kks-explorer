## The plant as the screens see it (ports index.html's model: eff(), mergeTags(), decode(), refLoc(), search):
## plant-data files (sheets, tags, procedures, locations), the program's KKS tables, and the live state from the log.
## Pure logic, shared by every UI (GNOME, Android through views.nim, Windows). Tested in core/tests/test_model.nim.

import std/[strutils, tables, sets, algorithm, math]
import json

type
  Link* = object
    label*: string               ## an off-page connector's code ("C16"): the same code elsewhere continues the line
    bbox*: array[4, float]       ## level-0 px of its sheet
    conf*: float

  SheetInfo* = object
    id*, name*: string
    w*, h*: float               ## level-0 px
    scale*: float               ## level-0 px per point
    levels*: int
    rot*: int
    notes*: seq[string]
    links*: seq[Link]            ## sheets.json "links" (absent before 2026-10-07: none)
    raw*: JNode

  Tag* = object
    id*, sheet*: string
    kks*, suffix*, isa*: string  ## kks "" = unread
    kind*, status*: string       ## status: auto · verified · review · confirmed
    conf*: float
    bbox*: array[4, float]       ## level-0 px of its sheet
    read*: (string, string)
    note*, flag*: string
    added*: string               ## an added tag's id (R6)
    suggestion*: JNode

  Decoded* = object
    blk*, sys*, fn*, comp*, num*: string
    isa*: string                 ## the function letters in words

  Model* = ref object
    sheets*: seq[SheetInfo]
    baseTags*: seq[Tag]
    tags*: seq[Tag]              ## effective: reviews applied, rejected removed, added tags merged
    procs*: JNode
    kksTables*: JNode
    locations*: Table[string, seq[JNode]]   ## by KKS body (no unit prefix)
    state*: JNode                ## /api/state

proc full*(t: Tag): string = t.kks & t.suffix
proc bodyOf*(t: Tag): string = (if t.kks.len > 2: t.kks[2 .. ^1] else: "")

proc s(n: JNode, k: string, d = ""): string =
  let v = n.get(k)
  if v != nil and v.isStr: v.s else: d

proc f(n: JNode, k: string, d = 0.0): float =
  let v = n.get(k)
  if v != nil and v.isNum: v.num else: d

const
  MaxLinksPerSheet* = 500
  ## sheets.json is published data but read as untrusted: a P&ID has tens of connectors, and every connector is
  ## matched against every other with its label (views.linksView), so a sheet keeps at most this many
  MaxLinkLabel* = 16             ## a connector's code is a letter and a digit or two ("C16"); longer is not one
  MaxLinkSide* = 100.0           ## points: the circles are 10-36 pt across

proc linkBoxOk(b: array[4, float], scale: float): bool =
  ## finite, ordered, at most MaxLinkSide across, and finite in points: a huge or reversed box would cover the whole
  ## drawing (every click a connector) and an infinite one breaks the JSON and the view
  let sc = if scale > 0: scale else: 2.0
  for v in b:
    if classify(v) in {fcNan, fcInf, fcNegInf} or classify(v / sc) in {fcNan, fcInf, fcNegInf}: return false
  b[2] > b[0] and b[3] > b[1] and (b[2] - b[0]) / sc <= MaxLinkSide and (b[3] - b[1]) / sc <= MaxLinkSide

proc parseSheets*(j: JNode): seq[SheetInfo] =
  for x in j.elems:
    var si = SheetInfo(id: x.s("id"), name: x.s("name"), w: x.f("w"), h: x.f("h"), scale: x.f("scale", 2.0),
                       levels: int(x.f("levels")), rot: int(x.f("rot")), raw: x)
    if x.get("notes") != nil:
      for n in x["notes"].elems:
        if n.isStr: si.notes.add n.s
    let ls = x.get("links")
    if ls != nil and ls.kind == jArr:
      for l in ls.elems:
        if si.links.len >= MaxLinksPerSheet: break
        let b = if l.kind == jObj: l.get("bbox") else: nil
        if l.kind != jObj or l.s("label").len == 0 or l.s("label").len > MaxLinkLabel or b == nil or b.kind != jArr or b.elems.len != 4: continue
        var k = Link(label: l.s("label"), conf: l.f("conf", 1.0))
        var ok = true
        for i in 0 .. 3:
          if not b[i].isNum: ok = false
          else: k.bbox[i] = b[i].num
        if ok and linkBoxOk(k.bbox, si.scale): si.links.add k
    result.add si

proc parseTag(x: JNode): Tag =
  result = Tag(id: x.s("id"), sheet: x.s("sheet"), kks: x.s("kks"), suffix: x.s("suffix"), isa: x.s("isa"),
               kind: x.s("kind"), status: x.s("status"), conf: x.f("conf"), note: x.s("note"), flag: x.s("flag"),
               suggestion: x.get("suggestion"))
  let b = x.get("bbox")
  if b != nil and b.elems.len == 4:
    for i in 0 .. 3: result.bbox[i] = b[i].num
  let r = x.get("read")
  if r != nil and r.elems.len == 2: result.read = (r[0].s, r[1].s)

proc parseTags*(j: JNode): seq[Tag] =
  for x in j.elems: result.add parseTag(x)

proc buildLocations*(j: JNode): Table[string, seq[JNode]] =
  ## locations.json {source, note, entries: [{kks, level, cabinet, desc, …}]}: the list has no unit prefix, so it is
  ## keyed by the KKS without the 2-digit unit (index.html)
  let entries = if j.kind == jObj and j.get("entries") != nil and j["entries"].kind == jArr: j["entries"].elems
                elif j.kind == jArr: j.elems
                else: @[]
  for row in entries:
    result.mgetOrPut(row.s("kks"), @[]).add row

proc eff*(m: Model, t: Tag): (bool, Tag) =
  ## a person's review decision overrides the reader (index.html eff())
  result = (true, t)
  let reviews = if m.state != nil: m.state.get("reviews") else: nil
  let r = if reviews != nil: reviews.get(t.id) else: nil
  if r != nil and r.kind == jObj:
    if r.s("status") == "rejected": return (false, t)
    result[1].kks = r.s("kks")
    result[1].isa = r.s("isa")
    result[1].suffix = r.s("suffix")
    result[1].status = "confirmed"

proc merge*(m: Model) =
  ## TAGS = tags.json + added tags (mergeTags), then eff() on each
  var all = m.baseTags
  let added = if m.state != nil: m.state.get("added_tags") else: nil
  if added != nil:
    for a in added.elems:
      var t = Tag(id: "u:" & a.s("id"), sheet: a.s("sheet"), kks: a.s("kks"), suffix: a.s("suffix"), isa: a.s("isa"),
                  kind: a.s("kind"), conf: 1, note: a.s("note"), added: a.s("id"))
      t.status = if t.kks.len > 0: "verified" else: "review"
      let b = a.get("bbox")
      if b != nil and b.elems.len == 4:
        for i in 0 .. 3: t.bbox[i] = b[i].num
      all.add t
  m.tags.setLen(0)
  for t in all:
    let (ok, e) = m.eff(t)
    if ok: m.tags.add e

proc tagsOf*(m: Model, sheet: string): seq[Tag] =
  for t in m.tags:
    if t.sheet == sheet: result.add t

proc tagById*(m: Model, id: string): (bool, Tag) =
  for t in m.tags:
    if t.id == id: return (true, t)

proc sheetById*(m: Model, id: string): (bool, SheetInfo) =
  for s in m.sheets:
    if s.id == id: return (true, s)

proc table(m: Model, name: string): JNode =
  if m.kksTables != nil and m.kksTables.get(name) != nil: m.kksTables[name] else: newObj()

proc decode*(m: Model, t: Tag): (bool, Decoded) =
  ## KKS → its parts (R3); false when the code isn't a full equipment code
  let k = t.kks
  if not (k.len == 12 and k[0 .. 1].allCharsInSet(Digits) and k[2 .. 4].allCharsInSet(UppercaseLetters) and
          k[5 .. 6].allCharsInSet(Digits) and k[7 .. 8].allCharsInSet(UppercaseLetters) and k[9 .. 11].allCharsInSet(Digits)):
    return
  var d = Decoded(blk: k[0 .. 1], sys: k[2 .. 4], fn: k[5 .. 6], comp: k[7 .. 8], num: k[9 .. 11])
  if t.isa.len > 0:
    let first = if t.isa.startsWith("PD"): "PD" else: t.isa[0 .. 0]
    var words: seq[string]
    for c in t.isa[first.len .. ^1]:
      words.add m.table("isa_next").s($c, $c)
    d.isa = m.table("isa_first").s(first, first) & " — " & words.join(", ")
  (true, d)

proc blockName*(m: Model, b: string): string = m.table("blocks").s(b)
proc systemName*(m: Model, s: string): string = m.table("systems").s(s)
proc componentName*(m: Model, c: string): string = m.table("components").s(c)

proc kindName*(m: Model, t: Tag): string =
  let (ok, d) = m.decode(t)
  if not ok: return t.kind
  let n = m.componentName(d.comp)
  if n.len > 0: n else: "Component code " & d.comp

proc lvlName(l: string): string =
  ## index.html lvlName: "14 m" / "14.50m" → "14 m" / "14.5 m"; anything with "out" → "Outside HRSG"
  var x = l.strip
  if x.len >= 2 and x[^1] in {'m', 'M'}:
    let num = x[0 ..< x.len - 1].strip
    var ok = num.len > 0 and num[0] in Digits
    var dots = 0
    for c in num:
      if c == '.': inc dots
      elif c notin Digits: ok = false
    if ok and dots <= 1 and not num.endsWith("."):
      let v = parseFloat(num)
      return (if v == float(int64(v)): $int64(v) else: $v) & " m"
  if "out" in x.toLowerAscii: return "Outside HRSG"
  x

type RefLoc* = object
  rows*: seq[JNode]
  elev*, cabinet*: string

proc refLoc*(m: Model, body: string): RefLoc =
  ## the location list's value per field, or "" when the list contradicts itself
  result.rows = m.locations.getOrDefault(body)
  var elevs, cabs: HashSet[string]
  for r in result.rows:
    let e = lvlName(r.s("level"))
    if e.len > 0: elevs.incl e
    let c = r.s("cabinet")
    if c.len > 0: cabs.incl c
  if elevs.len == 1:
    for e in elevs: result.elev = e
  if cabs.len == 1:
    for c in cabs: result.cabinet = c

proc equipment*(m: Model, k: string): JNode =
  let eq = if m.state != nil: m.state.get("equipment") else: nil
  if eq != nil and eq.get(k) != nil: eq[k] else: newObj()

proc photosOf*(m: Model, k: string): seq[JNode] =
  let ph = if m.state != nil: m.state.get("photos") else: nil
  if ph != nil:
    for p in ph.elems:
      if p.s("kks") == k: result.add p

const PlateCaption* = "Tag plate"
  ## a photo of the equipment's tag plate is a photo whose caption starts with this (PROTOCOL-v2 §9: a convention)

proc photoCover*(m: Model, k: string): string =
  ## which photos a code has: "both", "equipment", "plate" or "none" (the drawings' photo coverage view)
  if k.len == 0: return "none"
  var equip, plate = false
  for p in m.photosOf(k):
    if p.s("caption").startsWith(PlateCaption): plate = true else: equip = true
  if equip and plate: "both" elif equip: "equipment" elif plate: "plate" else: "none"

proc photoCovers*(m: Model): Table[string, string] =
  ## photoCover for every code that has photos, in one pass (a code missing here has "none"); views that colour many
  ## codes use this: photoCover per code scans every photo each time
  var equip, plate: HashSet[string]
  let ph = if m.state != nil: m.state.get("photos") else: nil
  if ph != nil:
    for p in ph.elems:
      let k = p.s("kks")
      if k.len == 0: continue
      if p.s("caption").startsWith(PlateCaption): plate.incl k else: equip.incl k
  for k in equip: result[k] = (if k in plate: "both" else: "equipment")
  for k in plate:
    if k notin equip: result[k] = "plate"

proc procsOf*(m: Model, k: string): seq[string] =
  let links = if m.state != nil: m.state.get("links") else: nil
  if links != nil:
    for l in links.elems:
      if l.s("kks") == k and l.s("proc") notin result: result.add l.s("proc")

proc procById*(m: Model, id: string): JNode =
  if m.procs != nil:
    for p in m.procs.elems:
      if p.s("id") == id: return p

proc normCode(s: string): string =
  for c in s.toUpperAscii:
    if c in {'A' .. 'Z', '0' .. '9'}: result.add c

proc search*(m: Model, q: string, limit = 60): seq[Tag] =
  ## R2: KKS (full, partial, with or without the unit prefix, with suffixes) or description (component, system,
  ## equipment notes, the location list's description). Exact code matches first.
  let code = normCode(q)
  let words = q.toLowerAscii.splitWhitespace
  if code.len == 0 and words.len == 0: return
  var scored: seq[(int, int, Tag)]
  for i, t in m.tags:
    let f = t.full
    var score = 0
    if code.len >= 2:
      if f == code or (f.len > 2 and f[2 .. ^1] == code): score = 100
      elif f.startsWith(code) or (f.len > 2 and f[2 .. ^1].startsWith(code)): score = 60
      elif code in f: score = 40
    if score == 0 and words.len > 0:
      var hay = (m.kindName(t) & " " & m.systemName(if t.kks.len >= 5: t.kks[2 .. 4] else: "") & " " &
                 t.isa & " " & m.equipment(f).s("notes")).toLowerAscii
      for r in m.refLoc(t.bodyOf).rows: hay.add " " & r.s("desc").toLowerAscii
      var all = true
      for w in words:
        if w notin hay: all = false
      if all: score = 10
    if score > 0: scored.add((-score, i, t))
  scored.sort(proc (a, b: (int, int, Tag)): int = cmp((a[0], a[1]), (b[0], b[1])))
  for x in scored[0 ..< min(limit, scored.len)]: result.add x[2]
