## What the screens show, as JSON (R2–R7), on top of model.nim: one place for the logic, every UI renders it (Android
## through JNI, later Windows). GNOME uses model.nim directly.

import std/[strutils, tables, sets, math, algorithm]
import json, model, pathstore

proc S(s: string): JNode = newStr(s)
proc F(f: float): JNode = newFloat(f)
proc I(i: int): JNode = newInt(i)
proc O(fields: varargs[(string, JNode)]): JNode = newObj(@fields)
proc str(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc sheetsView*(m: Model): JNode =
  result = newArr()
  for si in m.sheets:
    var n, review = 0
    for t in m.tagsOf(si.id):
      inc n
      if t.status == "review": inc review
    var notes = newArr()
    for x in si.notes: notes.elems.add S(x)
    result.elems.add O(("id", S(si.id)), ("name", S(si.name)), ("w", F(si.w)), ("h", F(si.h)), ("scale", F(si.scale)),
                       ("levels", I(si.levels)), ("tags", I(n)), ("review", I(review)), ("notes", notes))

proc scaleOf(m: Model, sheet: string): float =
  let (ok, si) = m.sheetById(sheet)
  if ok and si.scale > 0: si.scale else: 2.0

proc tagsView*(m: Model, sheet: string): JNode =
  ## the sheet's tags, boxes in points
  result = newArr()
  let s = m.scaleOf(sheet)
  let covers = m.photoCovers
  for t in m.tagsOf(sheet):
    result.elems.add O(("id", S(t.id)), ("code", S(t.full)), ("isa", S(t.isa)),
                       ("status", S(if t.status == "confirmed": "verified" else: t.status)),
                       ("x0", F(t.bbox[0] / s)), ("y0", F(t.bbox[1] / s)), ("x1", F(t.bbox[2] / s)), ("y1", F(t.bbox[3] / s)),
                       ("photos", S(covers.getOrDefault(t.full, "none"))))

proc searchView*(m: Model, q: string): JNode =
  result = newArr()
  for t in m.search(q):
    let (ok, si) = m.sheetById(t.sheet)
    result.elems.add O(("id", S(t.id)), ("sheet", S(t.sheet)), ("sheet_name", S(if ok: si.name else: t.sheet)),
                       ("code", S(t.full)), ("kind", S(m.kindName(t))))

proc tagView*(m: Model, id: string): JNode =
  ## everything the equipment panel shows (index.html select())
  let (ok, t) = m.tagById(id)
  if not ok: return newNull()
  let k = t.full
  result = O(("id", S(t.id)), ("sheet", S(t.sheet)), ("code", S(k)), ("kks", S(t.kks)), ("suffix", S(t.suffix)),
             ("isa", S(t.isa)), ("status", S(t.status)), ("conf", F(t.conf)), ("read", newArr(@[S(t.read[0]), S(t.read[1])])),
             ("note", S(t.note)), ("flag", S(t.flag)), ("added", S(t.added)), ("kind", S(m.kindName(t))),
             ("suggestion", if t.suggestion == nil: newNull() else: t.suggestion))
  let (okD, d) = m.decode(t)
  result["decoded"] = if not okD: newNull() else:
    O(("blk", S(d.blk)), ("blk_name", S(m.blockName(d.blk))), ("sys", S(d.sys)), ("sys_name", S(m.systemName(d.sys))),
      ("fn", S(d.fn)), ("comp", S(d.comp)), ("comp_name", S(m.componentName(d.comp))), ("num", S(d.num)), ("isa", S(d.isa)))
  result["reading"] = S(case t.status
    of "confirmed": "confirmed by a person"
    of "verified": "checked by eye against the drawing"
    else: "automatic, " & $int(round(t.conf * 100)) & " % confidence")
  let rl = m.refLoc(t.bodyOf)
  var rows = newArr()
  for r in rl.rows:
    rows.elems.add O(("desc", S(r.str("desc"))), ("level", S(r.str("level"))), ("cabinet", S(r.str("cabinet"))),
                     ("direction", S(r.str("direction"))))
  result["location_list"] = rows
  result["list_elev"] = S(rl.elev)
  result["equipment"] = if k.len > 0: m.equipment(k) else: newObj()
  var photos = newArr()
  if k.len > 0:
    for p in m.photosOf(k): photos.elems.add p
  result["photos"] = photos
  var procs = newArr()
  if k.len > 0:
    for p in m.procsOf(k):
      let pr = m.procById(p)
      procs.elems.add O(("id", S(p)), ("title", S(pr.str("title"))))
  result["procedures"] = procs
  var where = newArr()
  var seen: HashSet[string]
  if k.len > 0:
    for x in m.tags:
      if x.full == k and x.sheet notin seen:
        seen.incl x.sheet
        let (okS, si) = m.sheetById(x.sheet)
        where.elems.add O(("tag", S(x.id)), ("sheet", S(x.sheet)), ("sheet_name", S(if okS: si.name else: x.sheet)))
  result["appears_on"] = where
  let s = m.scaleOf(t.sheet)
  result["box"] = newArr(@[F(t.bbox[0] / s), F(t.bbox[1] / s), F(t.bbox[2] / s), F(t.bbox[3] / s)])
  # the valve type: confirmed, or from the drawing's symbol (its box in points, to highlight it); null = neither
  let vt = m.valveTypeOf(t)
  if vt != nil and t.symbol != nil and vt["status"].s == "drawing":
    let b = t.symbol.get("bbox")
    if b != nil and b.kind == jArr and b.elems.len == 4 and b[0].finiteNum and b[1].finiteNum and b[2].finiteNum and
       b[3].finiteNum:
      vt["box"] = newArr(@[F(b[0].num / s), F(b[1].num / s), F(b[2].num / s), F(b[3].num / s)])
  result["valve_type"] = if vt == nil: newNull() else: vt

proc reviewView*(m: Model): JNode =
  ## readings to confirm or correct, not yet decided
  result = newArr()
  let reviews = if m.state != nil: m.state.get("reviews") else: nil
  for t in m.tags:
    if t.status == "review" and (reviews == nil or reviews.get(t.id) == nil):
      let (ok, si) = m.sheetById(t.sheet)
      result.elems.add O(("id", S(t.id)), ("sheet", S(t.sheet)), ("sheet_name", S(if ok: si.name else: t.sheet)),
                         ("read", newArr(@[S(t.read[0]), S(t.read[1])])), ("conf", F(t.conf)),
                         ("suggestion", if t.suggestion != nil and t.suggestion.get("kks") != nil: t.suggestion["kks"] else: newNull()))

proc procsView*(m: Model): JNode =
  result = newArr()
  if m.procs == nil: return
  var counts = initCountTable[string]()
  if m.state != nil and m.state.get("links") != nil:
    for l in m.state["links"].elems: counts.inc l["proc"].s
  for p in m.procs.elems:
    var path: seq[JNode]
    for x in p["path"].elems: path.add x
    result.elems.add O(("id", S(p.str("id"))), ("title", S(p.str("title"))), ("path", newArr(path)),
                       ("steps", I(p["steps"].elems.len)), ("linked", I(counts[p.str("id")])))

proc procView*(m: Model, id: string): JNode =
  let p = m.procById(id)
  if p == nil: return newNull()
  result = p.copy
  var links = newArr()
  if m.state != nil and m.state.get("links") != nil:
    for l in m.state["links"].elems:
      if l["proc"].s == id:
        var tagId = ""
        for t in m.tags:
          if t.full == l["kks"].s:
            tagId = t.id
            break
        links.elems.add O(("step", l["step"]), ("kks", l["kks"]), ("tag", S(tagId)))
  result["links"] = links

proc floorsView*(m: Model): JNode =
  ## floors in use, with the tags on each (R5 floor filter)
  var byFloor = initOrderedTable[string, seq[JNode]]()
  for t in m.tags:
    let e = m.equipment(t.full)
    let f = e.str("floor").strip
    if f.len > 0: byFloor.mgetOrPut(f, @[]).add S(t.id)
  result = newObj()
  for f, ids in byFloor: result[f] = newArr(ids)

# ---------------------------------------------------------------- the path store, flat for a platform renderer

proc flat*(d: Drawing): string =
  ## A decoded .kkp in a fixed little-endian layout (no varints, no zlib) for a renderer outside Nim (Android):
  ## "KKF1", u32 width, height, nStyles, nPaths, nImages, nOps, nXY, gx, gy;
  ## styles 16 B each (kind, cap, join, 0, u32 width, stroke rgb, fill rgb, 0, 0);
  ## paths 32 B each (u32 style, i32 bbox×4, u32 cmdStart, cmdCount, ptStart);
  ## ops (nOps bytes, padded to 4); xy (nXY i32); cell offsets (gx·gy+1 u32) then cell entries (u32 path indices);
  ## images (u32 after, i32 rect×4, u32 length, the JPEG XL bytes padded to 4).
  var o = newStringOfCap(64 + d.paths.len * 32 + d.xy.len * 4 + d.ops.len)
  proc u32(v: int) =
    let x = uint32(v and 0xFFFFFFFF)
    o.add char(x and 0xff); o.add char((x shr 8) and 0xff); o.add char((x shr 16) and 0xff); o.add char((x shr 24) and 0xff)
  proc pad4() =
    while o.len mod 4 != 0: o.add '\0'
  o.add "KKF1"
  for v in [int(d.width), int(d.height), d.styles.len, d.paths.len, d.images.len, d.ops.len, d.xy.len, d.gx, d.gy]: u32(v)
  for st in d.styles:
    o.add char(st.kind); o.add char(st.cap); o.add char(st.join); o.add '\0'
    u32(int(st.width))
    for c in st.stroke: o.add char(c)
    for c in st.fill: o.add char(c)
    o.add '\0'; o.add '\0'
  for p in d.paths:
    u32(p.style)
    for v in p.bbox: u32(int(v))
    u32(p.cmdStart); u32(p.cmdCount); u32(p.ptStart)
  for op in d.ops: o.add char(op)
  pad4()
  for v in d.xy: u32(int(v))
  var off = 0
  for c in d.cells:
    u32(off)
    off += c.len
  u32(off)
  for c in d.cells:
    for i in c: u32(int(i))
  for im in d.images:
    u32(im.after)
    for v in im.rect: u32(int(v))
    u32(im.data.len)
    o.add im.data
    pad4()
  o

proc systemsView*(m: Model, q = ""): JNode =
  ## Every code on the drawings once, grouped block → system → subsystem (the system number, e.g. LAB 70) →
  ## component kind, each opening the first tag that shows it. `q` keeps the codes whose code, names, subsystem or
  ## location-list description contain every word of it. Codes that don't decode are listed under "other".
  type Item = object
    code, tag, sheet, desc: string
    count: int
  var items = initOrderedTable[string, Item]()
  var dec = initTable[string, Decoded]()
  var other: seq[string]
  for t in m.tags:
    let k = t.full
    if t.kks.len == 0: continue
    if k in items:
      inc items[k].count
      continue
    var desc = ""
    for r in m.refLoc(t.bodyOf).rows:
      if r.str("desc").len > 0:
        desc = r.str("desc")
        break
    items[k] = Item(code: k, tag: t.id, sheet: t.sheet, desc: desc, count: 1)
    let (ok, d) = m.decode(t)
    if ok: dec[k] = d
    else: other.add k
  let words = q.toLowerAscii.splitWhitespace
  proc keep(k: string): bool =
    if words.len == 0: return true
    var hay = k & " " & items[k].desc
    if k in dec:
      let d = dec[k]
      hay.add " " & d.blk & " " & m.blockName(d.blk) & " " & d.sys & " " & m.systemName(d.sys) & " " & d.sys & d.fn &
              " " & d.comp & " " & m.componentName(d.comp) & " " & d.isa
    hay = hay.toLowerAscii
    for w in words:
      if w notin hay: return false
    true
  let covers = m.photoCovers
  proc item(k: string): JNode =
    let it = items[k]
    let (ok, si) = m.sheetById(it.sheet)
    O(("code", S(k)), ("tag", S(it.tag)), ("sheet", S(it.sheet)), ("sheet_name", S(if ok: si.name else: it.sheet)),
      ("desc", S(it.desc)), ("count", I(it.count)), ("photos", S(covers.getOrDefault(k, "none"))))
  # block → system → subsystem → kind → codes, every level sorted by its code
  var tree = initTable[string, Table[string, Table[string, Table[string, seq[string]]]]]()
  var total = 0
  for k, d in dec:
    if not keep(k): continue
    inc total
    tree.mgetOrPut(d.blk, initTable[string, Table[string, Table[string, seq[string]]]]()).mgetOrPut(d.sys,
      initTable[string, Table[string, seq[string]]]()).mgetOrPut(d.fn, initTable[string, seq[string]]()).mgetOrPut(
      d.comp, @[]).add k
  proc sortedKeys[T](t: Table[string, T]): seq[string] =
    for k in t.keys: result.add k
    result.sort()
  var blocks = newArr()
  for b in tree.sortedKeys:
    var systems = newArr()
    for s in tree[b].sortedKeys:
      var subs = newArr()
      var sysCount = 0
      for f in tree[b][s].sortedKeys:
        var kinds = newArr()
        var subCount = 0
        for c in tree[b][s][f].sortedKeys:
          var codes = tree[b][s][f][c]
          codes.sort()
          var arr = newArr()
          for k in codes: arr.elems.add item(k)
          subCount += codes.len
          kinds.elems.add O(("comp", S(c)), ("comp_name", S(m.componentName(c))), ("count", I(codes.len)), ("items", arr))
        sysCount += subCount
        subs.elems.add O(("fn", S(f)), ("code", S(s & f)), ("count", I(subCount)), ("kinds", kinds))
      systems.elems.add O(("sys", S(s)), ("sys_name", S(m.systemName(s))), ("count", I(sysCount)), ("subsystems", subs))
    blocks.elems.add O(("blk", S(b)), ("blk_name", S(m.blockName(b))), ("systems", systems))
  var rest = newArr()
  other.sort()
  for k in other:
    if keep(k):
      inc total
      rest.elems.add item(k)
  O(("blocks", blocks), ("other", rest), ("total", I(total)))
