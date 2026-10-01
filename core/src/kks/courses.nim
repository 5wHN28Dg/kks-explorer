## Course content format version 1 (docs/COURSES.md): validator and figure evaluator. A port of ref/courses.py;
## ref/vectors/courses-v1.json decides. Figures are evaluated on the JSON tree directly (they are small).

import std/[algorithm, math, sets, strutils, tables, unicode]
import json

const
  Phi* = 0.6180339887498949
  Tokens = ["ink", "muted", "rule", "accent", "act", "ok", "alarm", "alarm_fill", "surface", "sunk", "ground"]
  MaxFileBytes* = 8 shl 20
  MaxPages = 400
  MaxFigures = 64
  MaxValues = 256
  MaxElements = 2000
  MaxTable = 1024
  MaxParticles = 1000

type CourseError* = object of ValueError
  code*: string

proc need(c: bool, code: string, where = "") =
  if not c:
    let e = newException(CourseError, code & ": " & where)
    e.code = code
    raise e

# ---------------------------------------------------------------- helpers

proc isObj(n: JNode): bool = n != nil and n.kind == jObj
proc isArr(n: JNode): bool = n != nil and n.kind == jArr

proc keys(o: JNode, required: openArray[string], optional: openArray[string] = [], where = "") =
  need(isObj(o), "bad_type", where)
  for k in required: need(o.has(k), "missing_key", where & "." & k)
  for (k, _) in o.fields: need(k in required or k in optional, "unknown_key", where & "." & k)

proc oneKind(o: JNode, kinds: openArray[string], where: string): string =
  need(isObj(o), "bad_type", where)
  var found: seq[string]
  for k in kinds:
    if o.has(k): found.add k
  need(found.len == 1, "bad_kind", where)
  found[0]

proc isNumber(x: JNode): bool =
  x != nil and x.kind in {jInt, jFloat} and (x.kind == jInt or classify(x.f) in {fcNormal, fcSubnormal, fcZero, fcNegZero}) and
    abs(x.num) < 1e9

proc num(x: JNode, where: string, lo = NegInf, hi = Inf, integer = false): float =
  need(isNumber(x), "bad_number", where)
  if integer: need(x.kind == jInt or x.f == trunc(x.f), "bad_number", where)
  need(x.num >= lo, "bad_number", where)
  need(x.num <= hi, "bad_number", where)
  x.num

proc isIdent(s: string): bool =
  s.len in 1..32 and s[0] in {'a'..'z', '_'} and (block:
    var ok = true
    for c in s:
      if c notin {'a'..'z', '0'..'9', '_'}: ok = false
    ok)

proc ident(x: JNode, where: string): string =
  need(x != nil and x.kind == jStr and isIdent(x.s), "bad_id", where)
  x.s

proc text(x: JNode, where: string): string =
  need(x != nil and x.kind == jStr, "bad_type", where)
  x.s

proc lst(x: JNode, where: string, lo = 0, hi = high(int)): seq[JNode] =
  need(isArr(x), "bad_type", where)
  need(x.len >= lo and x.len <= hi, "bad_length", where)
  x.elems

proc numEq(x: JNode, vals: openArray[int]): bool =
  ## Python's `x in (2, 3)` for a JSON number (floats equal to an int count; booleans don't).
  x != nil and x.kind in {jInt, jFloat} and (block:
    var ok = false
    for v in vals:
      if x.num == float(v): ok = true
    ok)

proc strIn(x: JNode, vals: openArray[string]): bool = x != nil and x.kind == jStr and x.s in vals

proc isHexColour(s: string): bool =
  s.len == 7 and s[0] == '#' and (block:
    var ok = true
    for c in s[1 .. ^1]:
      if c notin {'0'..'9', 'a'..'f'}: ok = false
    ok)

# ---------------------------------------------------------------- templates

type Placeholder = object
  name: string
  decimals: int
  sign: bool

iterator tokens(s: string): (int, int, bool, Placeholder) =
  ## (start, length, isPlaceholder, placeholder); literal "{{"/"}}" come as length-2 non-placeholders; a stray
  ## brace comes as a placeholder with an empty name. Same alternation order as the reference's regex.
  var i = 0
  while i < s.len:
    if i + 1 < s.len and ((s[i] == '{' and s[i + 1] == '{') or (s[i] == '}' and s[i + 1] == '}')):
      yield (i, 2, false, Placeholder())
      i += 2
    elif s[i] == '{':
      var j = i + 1
      var ph = Placeholder()
      var ok = j < s.len and s[j] in {'a'..'z', '_'}
      if ok:
        while j < s.len and s[j] in {'a'..'z', '0'..'9', '_'}: inc j
        ph.name = s[i + 1 ..< j]
        ok = ph.name.len <= 32
      if ok and j < s.len and s[j] == ':':
        inc j
        if j < s.len and s[j] == '+':
          ph.sign = true
          inc j
        ok = j < s.len and s[j] in {'0'..'6'}
        if ok:
          ph.decimals = ord(s[j]) - ord('0')
          inc j
      ok = ok and j < s.len and s[j] == '}'
      if ok:
        yield (i, j + 1 - i, true, ph)
        i = j + 1
      else:
        yield (i, 1, true, Placeholder())
        inc i
    elif s[i] == '}':
      yield (i, 1, true, Placeholder())
      inc i
    else:
      inc i

proc checkTemplate(s: JNode, where: string, names: HashSet[string]) =
  need(s != nil and s.kind == jStr, "bad_type", where)
  for (_, _, isPh, ph) in tokens(s.s):
    if not isPh: continue
    need(ph.name.len > 0, "bad_template", where)
    need(ph.name in names, "bad_ref", where)

proc exactDecimal(x: float): (seq[int], int) =
  ## The exact decimal expansion of |x| (a double is a finite binary fraction): digits, and how many of them are
  ## after the decimal point.
  let bits = cast[uint64](abs(x))
  let expBits = int((bits shr 52) and 0x7FF)
  var mant = bits and ((1'u64 shl 52) - 1)
  var e: int                          # |x| = mant * 2^e
  if expBits == 0: e = -1074          # subnormal
  else:
    mant = mant or (1'u64 shl 52)
    e = expBits - 1075
  var digits: seq[int]                # little-endian decimal digits
  if mant == 0: digits = @[0]
  while mant > 0:
    digits.add int(mant mod 10)
    mant = mant div 10
  var frac = 0
  if e >= 0:
    for _ in 0 ..< e:
      var carry = 0
      for d in digits.mitems:
        let v = d * 2 + carry
        d = v mod 10
        carry = v div 10
      if carry > 0: digits.add carry
  else:
    for _ in 0 ..< -e:                # mant / 2^k = mant * 5^k / 10^k
      var carry = 0
      for d in digits.mitems:
        let v = d * 5 + carry
        d = v mod 10
        carry = v div 10
      while carry > 0:
        digits.add carry mod 10
        carry = carry div 10
    frac = -e
  while digits.len <= frac: digits.add 0
  var big: seq[int]
  for i in countdown(digits.high, 0): big.add digits[i]
  (big, frac)

proc fmtNumber*(x: float, decimals: int, sign: bool): string =
  ## The exact binary value rounded half away from zero; minus is U+2212; a rounded zero has no minus.
  var (ds, frac) = exactDecimal(x)
  while frac < decimals:
    ds.add 0
    inc frac
  let keep = ds.len - frac + decimals          # digits kept
  var kept = ds[0 ..< keep]
  if keep < ds.len and ds[keep] >= 5:          # half away from zero on the magnitude
    var i = kept.high
    while i >= 0:
      if kept[i] == 9:
        kept[i] = 0
        dec i
      else:
        inc kept[i]
        break
    if i < 0: kept.insert(1, 0)
  let intLen = kept.len - decimals
  var intPart = ""
  for d in kept[0 ..< intLen]: intPart.add char(ord('0') + d)
  intPart = intPart.strip(trailing = false, chars = {'0'})
  if intPart.len == 0: intPart = "0"
  var fracPart = ""
  for d in kept[intLen .. ^1]: fracPart.add char(ord('0') + d)
  var zero = true
  for d in kept:
    if d != 0: zero = false
  result = intPart
  if decimals > 0: result &= "." & fracPart
  if x < 0 and not zero: result = "−" & result
  elif sign: result = "+" & result

proc fillTemplate*(s: string, vals: Table[string, float]): string =
  var last = 0
  for (start, len, isPh, ph) in tokens(s):
    result.add s[last ..< start]
    if not isPh: result.add s[start]        # "{{" → "{", "}}" → "}"
    else: result.add fmtNumber(vals[ph.name], ph.decimals, ph.sign)
    last = start + len
  result.add s[last .. ^1]

# ---------------------------------------------------------------- course validation

type Course = object
  doc: JNode
  images: HashSet[string]
  checkImages: bool
  pageIds, moduleIds, questionIds, glossary: HashSet[string]
  links: seq[(JNode, string)]
  glossRefs, figureRefs, moduleRefs: seq[(JNode, string)]
  questionRefs: seq[(JNode, string, string)]        ## test items by reference: (module, question id, where)
  moduleQuestions: Table[string, HashSet[string]]   ## module id → its question ids (warm, practice, bridge)
  counts: OrderedTable[string, int]

proc run(c: var Course, r: JNode, where: string, allowEmpty = false)

proc target(c: var Course, t: JNode, where: string) =
  need(isObj(t) and t.len > 0, "bad_link", where)
  var ks: seq[string]
  for (k, _) in t.fields: ks.add k
  if (block:
      var sub = true
      for k in ks:
        if k notin ["course", "page"]: sub = false
      sub):
    for k in ks: discard ident(t[k], where)
  elif ks == @["kks"]:
    let v = t["kks"]
    need(v.kind == jStr and v.s.len in 4..24 and (block:
      var ok = true
      for ch in v.s:
        if ch notin {'0'..'9', 'A'..'Z'}: ok = false
      ok), "bad_link", where)
  elif ks == @["url"]:
    let v = t["url"]
    need(v.kind == jStr and v.s.startsWith("https://") and v.s.len > 8 and (block:
      var ok = true
      for r in v.s[8 .. ^1].runes:
        if r.isWhiteSpace or int(r) in {0x1C..0x1F, 0x85}: ok = false
      ok), "bad_link", where)
  else:
    need(false, "bad_link", where)
  c.links.add((t, where))

proc run(c: var Course, r: JNode, where: string, allowEmpty = false) =
  for item in lst(r, where, if allowEmpty: 0 else: 1):
    if item.kind == jStr: continue
    let k = oneKind(item, ["b", "i", "small", "num", "term", "link"], where)
    case k
    of "b", "i", "small":
      keys(item, [k], where = where)
      c.run(item[k], where)
    of "num":
      keys(item, ["num"], where = where)
      need(item["num"].kind == jStr and item["num"].s.len > 0, "bad_type", where)
    of "term":
      keys(item, ["term", "gloss"], where = where)
      c.run(item["term"], where)
      discard text(item["gloss"], where)
      c.glossRefs.add((item["gloss"], where))
    else:
      keys(item, ["link", "to"], where = where)
      c.run(item["link"], where)
      c.target(item["to"], where)

proc blocks(c: var Course, bs: JNode, where: string, only: openArray[string] = [])

proc isJxlName(s: string): bool =
  if not s.endsWith(".jxl") or s.contains(".."): return false
  let stem = s[0 ..< s.len - 4]
  stem.len in 1..64 and stem[0] in {'a'..'z', '0'..'9'} and (block:
    var ok = true
    for ch in stem:
      if ch notin {'a'..'z', '0'..'9', '.', '_', '-'}: ok = false
    ok)

proc blk(c: var Course, b: JNode, where: string, only: openArray[string]) =
  let k = oneKind(b, ["h", "p", "ul", "ol", "table", "callout", "cards", "chain", "figure", "image", "issues", "tool"],
                  where)
  need(only.len == 0 or k in only, "bad_kind", where & ": " & k & " not allowed here")
  c.counts["blocks"] = c.counts["blocks"] + 1
  let w = where & "." & k
  case k
  of "h":
    keys(b, ["h", "level"], where = w)
    need(numEq(b["level"], [2, 3]), "bad_value", w)
    c.run(b["h"], w)
  of "p":
    keys(b, ["p"], where = w)
    c.run(b["p"], w)
  of "ul", "ol":
    keys(b, [k], where = w)
    for r in lst(b[k], w, 1): c.run(r, w)
  of "table":
    keys(b, ["table"], where = w)
    let t = b["table"]
    keys(t, ["head", "rows", "num"], where = w)
    let n = lst(t["head"], w, 1).len
    for r in t["head"].elems: c.run(r, w, allowEmpty = true)
    for row in lst(t["rows"], w, 1):
      need(lst(row, w).len == n, "bad_length", w)
      for cell in row.elems: c.run(cell, w, allowEmpty = true)
    var seen: seq[float]
    for col in lst(t["num"], w):
      seen.add num(col, w, 0, float(n - 1), integer = true)
    for i in 0 ..< seen.len:
      for j in 0 ..< i: need(seen[i] != seen[j], "dup_id", w)
  of "callout":
    keys(b, ["callout", "label", "body"], where = w)
    need(strIn(b["callout"], ["why", "why_general", "at_plant", "flag", "note"]), "bad_value", w)
    c.run(b["label"], w)
    discard lst(b["body"], w, 1)
    c.blocks(b["body"], w, only = ["p", "ul", "ol", "table"])
  of "cards":
    keys(b, ["cards"], where = w)
    for card in lst(b["cards"], w, 1):
      discard lst(card, w, 2, 2)
      c.run(card[0], w)
      c.run(card[1], w)
  of "chain":
    keys(b, ["chain"], where = w)
    for r in lst(b["chain"], w, 2): c.run(r, w)
  of "figure":
    keys(b, ["figure"], where = w)
    discard ident(b["figure"], w)
    c.figureRefs.add((b["figure"], w))
  of "image":
    keys(b, ["image"], where = w)
    let im = b["image"]
    keys(im, ["file", "w", "h", "alt", "caption", "credit"], where = w)
    need(im["file"].kind == jStr and isJxlName(im["file"].s), "bad_value", w)
    need(not c.checkImages or im["file"].s in c.images, "bad_ref", w)
    discard num(im["w"], w, 1, 20000, integer = true)
    discard num(im["h"], w, 1, 20000, integer = true)
    need(im["alt"].kind == jStr and im["alt"].s.len > 0, "bad_value", w)
    c.run(im["caption"], w, allowEmpty = true)
    c.run(im["credit"], w, allowEmpty = true)
  of "issues":
    keys(b, ["issues"], where = w)
    for it in lst(b["issues"], w, 1):
      discard lst(it, w, 3, 3)
      need(strIn(it[0], ["high", "medium", "low"]), "bad_value", w)
      c.run(it[1], w)
      c.run(it[2], w)
  else:
    keys(b, ["tool"], where = w)
    need(strIn(b["tool"], ["kks_decoder"]), "bad_value", w)

proc blocks(c: var Course, bs: JNode, where: string, only: openArray[string] = []) =
  for b in lst(bs, where): c.blk(b, where, only)

proc question(c: var Course, q: JNode, where: string) =
  need(isObj(q), "bad_type", where)
  let typ = q.get("type")
  let t = if typ != nil and typ.kind == jStr: typ.s else: ""
  case t
  of "choice": keys(q, ["type", "id", "q", "src", "options"], where = where)
  of "order": keys(q, ["type", "id", "q", "src", "steps"], where = where)
  of "scenario": keys(q, ["type", "id", "q", "src", "panel", "options"], where = where)
  else: need(false, "bad_question", where)
  let qid = ident(q["id"], where)
  need(not (qid.len >= 2 and qid[^2] == '_' and qid[^1] in {'r', 'f', 'p'}), "bad_id", where & ": suffix")
  need(qid notin c.questionIds, "dup_id", qid)
  c.questionIds.incl qid
  c.counts["questions"] = c.counts["questions"] + 1
  c.run(q["q"], where)
  c.run(q["src"], where, allowEmpty = true)
  if t == "order":
    for s in lst(q["steps"], where, 3, 10): c.run(s, where)
    return
  if t == "scenario":
    for r in lst(q["panel"], where, 1, 10):
      keys(r, ["name", "value", "state"], where = where)
      c.run(r["name"], where)
      c.run(r["value"], where)
      need(strIn(r["state"], ["", "ok", "alarm", "act"]), "bad_value", where)
  var right = 0
  for o in lst(q["options"], where, 2, 6):
    keys(o, ["text", "right", "why"], where = where)
    c.run(o["text"], where)
    need(o["right"].kind == jBool, "bad_type", where)
    if o["right"].b: inc right
    c.run(o["why"], where, allowEmpty = true)
  need(right == 1, "bad_question", where & ": " & $right & " right options")

proc items(c: var Course, its: JNode, where: string, refs = false) =
  for it in lst(its, where, 1):
    if refs and isObj(it) and it.get("ref") != nil:
      keys(it, ["module", "ref"], where = where)
      c.questionRefs.add((it["module"], ident(it["ref"], where), where))
    else:
      keys(it, ["module", "q"], where = where)
      c.question(it["q"], where)
    c.moduleRefs.add((it["module"], where))

proc page(c: var Course, p: JNode) =
  let kindN = p.get("kind")
  let kind = if kindN != nil and kindN.kind == jStr: kindN.s else: ""
  let w = "page " & (if p["id"].kind == jStr: p["id"].s else: "")
  c.counts["pages"] = c.counts["pages"] + 1
  if kind == "module":
    keys(p, ["kind", "id", "n", "title", "short", "goals", "warm", "body", "worked", "practice"], ["bridge"], where = w)
    let before = c.questionIds
    c.counts["modules"] = c.counts["modules"] + 1
    discard text(p["n"], w)
    c.run(p["title"], w)
    discard text(p["short"], w)
    for g in lst(p["goals"], w): c.run(g, w)
    c.question(p["warm"], w)
    c.blocks(p["body"], w)
    if not p["worked"].isNull:
      keys(p["worked"], ["case", "steps"], where = w)
      c.run(p["worked"]["case"], w)
      for s in lst(p["worked"]["steps"], w, 1):
        discard lst(s, w, 2, 2)
        c.run(s[0], w)
        c.run(s[1], w)
    for q in lst(p["practice"], w): c.question(q, w)
    if p.get("bridge") != nil:
      let b = p["bridge"]
      keys(b, ["title", "intro", "questions"], where = w)
      c.run(b["title"], w)
      c.run(b["intro"], w, allowEmpty = true)
      for q in lst(b["questions"], w, 1): c.question(q, w)
    c.moduleQuestions[p["id"].s] = c.questionIds - before
    return
  const common = ["kind", "id", "title", "intro"]
  case kind
  of "placement":
    keys(p, @common & @["items"], where = w)
    c.items(p["items"], w)
  of "test":
    keys(p, @common & @["items", "draw", "pass", "on_pass", "on_fail"], where = w)
    c.items(p["items"], w, refs = true)
    let n = if p["draw"].isNull: float(p["items"].len)
            else: num(p["draw"], w, 1, float(p["items"].len), integer = true)
    discard num(p["pass"], w, 0, n, integer = true)
    c.blocks(p["on_pass"], w)
    c.blocks(p["on_fail"], w)
  of "vocab_drill", "glossary":
    keys(p, common, where = w)
    if kind == "vocab_drill": need(c.doc["glossary"].len >= 4, "bad_value", w & ": drill needs 4 terms")
  of "reading_drill":
    keys(p, @common & @["items"], where = w)
    for it in lst(p["items"], w, 1):
      keys(it, ["cat", "name", "unit", "context", "values", "rules", "note"], where = w)
      need(it["cat"].kind == jStr and it["cat"].s.len > 0, "bad_value", w)
      c.run(it["name"], w)
      discard text(it["unit"], w)
      c.run(it["context"], w, allowEmpty = true)
      for v in lst(it["values"], w, 1): discard num(v, w)
      for r in lst(it["rules"], w):
        discard lst(r, w, 3, 3)
        need(strIn(r[0], [">=", ">", "<=", "<"]), "bad_value", w)
        discard num(r[1], w)
        need(strIn(r[2], ["alarm", "act"]), "bad_value", w)
      c.run(it["note"], w, allowEmpty = true)
  of "page":
    keys(p, @common & @["eyebrow", "body"], where = w)
    discard text(p["eyebrow"], w)
    c.blocks(p["body"], w)
  else:
    need(false, "bad_kind", w)
  c.run(p["title"], w)
  c.blocks(p["intro"], w)

proc checkFigure*(f: JNode, where: string, c: ptr Course = nil)

proc checkCourse*(doc: JNode, imageFiles: HashSet[string], checkImages = true, size = -1):
    OrderedTable[string, int] =
  ## Raises CourseError (code = the rule, docs/COURSES.md §10). Returns the counts.
  if size >= 0: need(size <= MaxFileBytes, "limit", "file size")
  var c = Course(doc: doc, images: imageFiles, checkImages: checkImages)
  for k in ["pages", "modules", "questions", "figures", "blocks"]: c.counts[k] = 0
  let d = doc
  keys(d, ["format", "version", "id", "title", "short", "order", "figures", "glossary", "pages"], where = "course")
  need(strIn(d["format"], ["kks-course"]), "bad_format", "format")
  need(numEq(d["version"], [1]), "bad_version", "version")
  discard ident(d["id"], "id")
  discard text(d["title"], "title")
  discard text(d["short"], "short")
  discard num(d["order"], "order", 0, integer = true)
  need(isObj(d["figures"]), "bad_type", "figures")
  need(d["figures"].len <= MaxFigures, "limit", "figures")
  discard lst(d["pages"], "pages", 1, MaxPages)
  for p in d["pages"].elems:
    need(isObj(p) and p.has("id"), "missing_key", "page.id")
    let pid = ident(p["id"], "page.id")
    need(pid notin c.pageIds, "dup_id", pid)
    c.pageIds.incl pid
    if strIn(p.get("kind"), ["module"]): c.moduleIds.incl pid
  for i, g in lst(d["glossary"], "glossary"):
    keys(g, ["term", "meaning", "module"], where = "glossary[" & $i & "]")
    need(g["term"].kind == jStr and g["term"].s.len > 0, "bad_type", "term")
    need(g["term"].s notin c.glossary, "dup_id", g["term"].s)
    c.glossary.incl g["term"].s
    c.run(g["meaning"], "glossary.meaning")
    c.moduleRefs.add((g["module"], "glossary.module"))
  for p in d["pages"].elems: c.page(p)
  for (fid, f) in d["figures"].fields:
    need(isIdent(fid), "bad_id", "figure id")
    checkFigure(f, "figure " & fid, addr c)
    c.counts["figures"] = c.counts["figures"] + 1
  var used: HashSet[string]
  for (fid, where) in c.figureRefs:
    need(d["figures"].has(fid.s), "bad_ref", where)
    used.incl fid.s
  for (fid, _) in d["figures"].fields: need(fid in used, "unused_figure", "figures")
  for (term, where) in c.glossRefs: need(term.s in c.glossary, "bad_ref", where)
  for (m, where) in c.moduleRefs: need(m.kind == jStr and m.s in c.moduleIds, "bad_ref", where)
  for (m, qid, where) in c.questionRefs:
    need(qid in c.moduleQuestions.getOrDefault(m.s), "bad_ref", where)
  for (t, where) in c.links:
    if t.has("page") and not t.has("course"): need(t["page"].s in c.pageIds, "bad_ref", where)
  c.counts

proc summary*(doc: JNode): JNode =
  ## A checked course → its entry in a course list: id, title, short, order and the IDs of the module questions
  ## (warm-up, practice, bridge: the ones that make a module done, §6), for "n of m solved".
  var qs = newArr()
  for p in doc["pages"].elems:
    if p["kind"].s != "module": continue
    qs.elems.add p["warm"]["id"]
    for q in p["practice"].elems: qs.elems.add q["id"]
    let b = p.get("bridge")
    if b != nil:
      for q in b["questions"].elems: qs.elems.add q["id"]
  newObj(@[("id", doc["id"]), ("title", doc["title"]), ("short", doc["short"]), ("order", doc["order"]),
           ("questions", qs)])

proc pickCourses*(files: seq[(string, string)], images: HashSet[string]): (seq[JNode], seq[string]) =
  ## The courses among `files` (name, bytes) of one published version or the program's data: each a checked course
  ## named `<id>.json`, sorted by `order`. Files without `"format": "kks-course"` (v1's courses.json) are skipped;
  ## invalid courses are skipped and reported in the second result.
  var docs: seq[JNode]
  for (name, data) in files:
    if not name.endsWith(".json"): continue
    try:
      let doc = parseStrict(data)
      let f = doc.get("format")
      if f == nil or f.kind != jStr or f.s != "kks-course": continue
      discard checkCourse(doc, images, true, data.len)
      if name != doc["id"].s & ".json": raise newException(ValueError, "the file name differs from the course id")
      docs.add doc
    except CatchableError as e:
      result[1].add name & ": " & e.msg
  docs.sort(proc (x, y: JNode): int = cmp(x["order"].num, y["order"].num))
  result[0] = docs

proc judge*(item: JNode, value: float): string =
  ## Reading drill: the state of the first rule the value meets, else "ok".
  for r in item["rules"].elems:
    let lim = r[1].num
    let hit = case r[0].s
      of ">=": value >= lim
      of ">": value > lim
      of "<=": value <= lim
      else: value < lim
    if hit: return r[2].s
  "ok"

# ---------------------------------------------------------------- figure validation

proc checkTable(t: JNode, where: string, paint = false)

proc checkPaint(p: JNode, where: string, names: HashSet[string], plain = false, fill = true) =
  if p != nil and p.kind == jStr:
    need(p.s == "none" or p.s in Tokens or isHexColour(p.s), "bad_paint", where)
    return
  need(not plain, "bad_paint", where)
  need(isObj(p), "bad_paint", where)
  if p.has("radial"):
    need(fill, "bad_paint", where & ": gradient stroke")
    keys(p, ["radial"], where = where)
    var prev = -1.0
    for s in lst(p["radial"], where, 2, 16):
      discard lst(s, where, 3, 3)
      let o = num(s[0], where, 0, 1)
      need(o > prev, "bad_paint", where)
      prev = o
      checkPaint(s[1], where, names, plain = true)
      need(not strIn(s[1], ["none"]), "bad_paint", where)
      discard num(s[2], where, 0, 1)
  elif p.has("stops"):
    keys(p, ["of", "stops"], where = where)
    need(p["of"].kind == jStr and p["of"].s in names, "bad_ref", where)
    checkTable(p["stops"], where, paint = true)
    for s in p["stops"].elems: need(s[1].kind == jStr and isHexColour(s[1].s), "bad_paint", where & ": stops need #rrggbb")
  elif p.has("steps"):
    keys(p, ["of", "steps"], where = where)
    need(p["of"].kind == jStr and p["of"].s in names, "bad_ref", where)
    checkTable(p["steps"], where, paint = true)
  else:
    need(false, "bad_paint", where)

proc checkTable(t: JNode, where: string, paint = false) =
  var prev = NaN
  var runLen = 0
  for pt in lst(t, where, 1, MaxTable):
    discard lst(pt, where, 2, 2)
    let x = num(pt[0], where)
    if paint: checkPaint(pt[1], where, initHashSet[string](), plain = true)
    else: discard num(pt[1], where)
    if not prev.isNaN:
      need(x >= prev, "bad_table", where & ": x decreases")
      runLen = if x == prev: runLen + 1 else: 1
      need(runLen < 3, "bad_table", where & ": three points at one x")
    else:
      runLen = 1
    prev = x

proc checkRef(r: JNode, where: string, names: HashSet[string]) =
  if r != nil and r.kind == jStr: need(r.s in names, "bad_ref", where)
  else: discard num(r, where)

proc checkRefNode(r: JNode, where: string, names, later: HashSet[string], nameOnly = false) =
  if r != nil and r.kind == jStr:
    need(r.s in names, if r.s in later: "forward_ref" else: "bad_ref", where)
  else:
    need(not nameOnly, "bad_ref", where)
    discard num(r, where)

proc checkText(t: JNode, where: string, names: HashSet[string]) =
  if t != nil and t.kind == jStr:
    checkTemplate(t, where, names)
    return
  let cases = lst(t, where, 1)
  for i, cs in cases:
    let last = i == cases.high
    if last: keys(cs, ["text"], where = where)
    else: keys(cs, ["when", "text"], where = where)
    if not last: checkRef(cs["when"], where, names)
    checkTemplate(cs["text"], where, names)

proc checkNode(n: JNode, where: string, names, later: HashSet[string]) =
  let k = oneKind(n, ["table", "sum", "product", "select", "follow", "hold"], where)
  case k
  of "table":
    keys(n, ["of", "table"], ["step"], where = where)
    checkRefNode(n["of"], where, names, later, nameOnly = true)
    checkTable(n["table"], where)
    need(not n.has("step") or n["step"].kind == jBool, "bad_type", where)
  of "sum", "product":
    keys(n, [k], where = where)
    for r in lst(n[k], where, 1): checkRefNode(r, where, names, later)
  of "select":
    keys(n, ["select", "cases"], where = where)
    checkRefNode(n["select"], where, names, later, nameOnly = true)
    for r in lst(n["cases"], where, 1): checkRefNode(r, where, names, later)
  of "follow":
    keys(n, ["follow", "rate"], ["rate_down", "init"], where = where)
    checkRefNode(n["follow"], where, names, later, nameOnly = true)
    discard num(n["rate"], where, 1e-9)
    if n.has("rate_down"): discard num(n["rate_down"], where, 1e-9)
    if n.has("init"): discard num(n["init"], where)
  else:
    keys(n, ["hold", "while"], where = where)
    checkRefNode(n["hold"], where, names, later, nameOnly = true)
    checkRefNode(n["while"], where, names, later, nameOnly = true)

const Common = ["fill", "stroke", "stroke_width", "opacity", "dash", "cap", "join", "transform"]

proc checkCommon(e: JNode, where: string, names: HashSet[string]) =
  for p in ["fill", "stroke"]:
    if e.has(p): checkPaint(e[p], where, names, fill = p == "fill")
  for p in ["stroke_width", "opacity"]:
    if e.has(p): checkRef(e[p], where, names)
  if e.has("dash"):
    for d in lst(e["dash"], where, 1, 8): discard num(d, where, 0)
  need(not e.has("cap") or strIn(e["cap"], ["butt", "round", "square"]), "bad_value", where)
  need(not e.has("join") or strIn(e["join"], ["miter", "round", "bevel"]), "bad_value", where)
  if e.has("transform"):
    for st in lst(e["transform"], where, 0, 8):
      let k = oneKind(st, ["translate", "rotate", "scale"], where)
      keys(st, [k], where = where)
      let n = if k == "rotate": 3 else: 2
      for r in lst(st[k], where, n, n): checkRef(r, where, names)

proc checkPoints(pts: seq[JNode], where: string, names: HashSet[string], lo, hi: int) =
  need(pts.len >= lo and pts.len <= hi, "bad_length", where)
  for p in pts:
    for r in lst(p, where, 2, 2): checkRef(r, where, names)

proc checkPath(d: JNode, where: string, names: HashSet[string]) =
  for i, c in lst(d, where, 1, 5000):
    discard lst(c, where, 1)
    need(strIn(c[0], ["M", "L", "C", "Z"]), "bad_path", where)
    need(i > 0 or c[0].s == "M", "bad_path", where & ": first command")
    let want = case c[0].s
      of "M", "L": 3
      of "C": 7
      else: 1
    need(c.len == want, "bad_path", where)
    for r in c.elems[1 .. ^1]: checkRef(r, where, names)

proc checkFlow(fl: JNode, where: string, names: HashSet[string]) =
  keys(fl, ["count", "routes"], ["lanes", "speed", "r", "fill", "stroke", "stroke_width", "opacity", "glyph", "along",
                                 "hide", "reverse", "pile", "wrap_x"], where = where)
  discard num(fl["count"], where, 1, 200, integer = true)
  for rt in lst(fl["routes"], where, 1, 16):
    keys(rt, ["path"], ["weight", "lanes"], where = where)
    checkPath(rt["path"], where, names)
    var moves = 0
    var closes = 0
    for c in rt["path"].elems:
      if c[0].s == "M": inc moves
      if c[0].s == "Z": inc closes
    need(closes == 0 and moves == 1, "bad_path", where & ": a route is one open subpath")
    if rt.has("weight"): checkRef(rt["weight"], where, names)
    if rt.has("lanes"): checkPoints(lst(rt["lanes"], where), where, names, 1, 200)
  if fl.has("lanes"): checkPoints(lst(fl["lanes"], where), where, names, 1, 200)
  for p in ["speed", "r", "opacity", "stroke_width"]:
    if fl.has(p): checkRef(fl[p], where, names)
  for p in ["fill", "stroke"]:
    if fl.has(p): checkPaint(fl[p], where, names, plain = true)
  need(not fl.has("glyph") or strIn(fl["glyph"], ["dot", "burst"]), "bad_value", where)
  need(not fl.has("reverse") or strIn(fl["reverse"], ["wrap", "pile"]), "bad_value", where)
  if fl.has("pile"): discard num(fl["pile"], where, 0)
  if fl.has("wrap_x"):
    let wx = lst(fl["wrap_x"], where, 2, 2)
    let b = num(wx[1], where)
    let a = num(wx[0], where)
    need(b > a, "bad_value", where)
  if fl.has("along"):
    keys(fl["along"], [], ["speed", "r", "opacity", "lane", "fill"], where = where)
    for (k, t) in fl["along"].fields: checkTable(t, where & ".along." & k, paint = k == "fill")
  if fl.has("hide"):
    for h in lst(fl["hide"], where, 0, 8):
      keys(h, ["rect", "when"], where = where)
      for r in lst(h["rect"], where, 4, 4): checkRef(r, where, names)
      checkRef(h["when"], where, names)

proc checkElements(es: JNode, where: string, names: HashSet[string], isStatic: bool, elements, particles: var int) =
  for e in lst(es, where):
    inc elements
    let k = oneKind(e, ["rect", "circle", "ellipse", "line", "poly", "path", "text", "label", "group", "flow"], where)
    let w = where & "." & k
    if k == "flow":
      need(not isStatic, "static_inputs", w)
      keys(e, ["flow"], where = w)
      checkFlow(e["flow"], w, names)
      particles += int(e["flow"]["count"].num)
      continue
    if k == "label":
      keys(e, ["label", "at", "to"], ["anchor"], where = w)
      discard text(e["label"], w)
      checkPoints(@[e["at"]], w, names, 1, 1)
      checkPoints(@[e["to"]], w, names, 1, 1)
      need(not e.has("anchor") or strIn(e["anchor"], ["start", "end"]), "bad_value", w)
      continue
    let extra = case k
      of "rect": @["rx"]
      of "line": @["arrow"]
      of "poly": @["closed"]
      of "group": @["clip"]
      of "text": @["at", "anchor", "size", "font", "weight"]
      else: @[]
    let required = if k == "text": @[k, "at"] else: @[k]
    keys(e, required, @Common & extra, where = w)
    checkCommon(e, w, names)
    case k
    of "rect", "circle", "ellipse", "line":
      let n = if k == "circle": 3 else: 4
      for r in lst(e[k], w, n, n): checkRef(r, w, names)
      if e.has("rx"): checkRef(e["rx"], w, names)
      if e.has("arrow"): need(e["arrow"].kind == jBool, "bad_type", w)
    of "poly":
      checkPoints(lst(e["poly"], w), w, names, 2, 1024)
      need(not e.has("closed") or e["closed"].kind == jBool, "bad_type", w)
    of "path":
      checkPath(e["path"], w, names)
    of "text":
      checkText(e["text"], w, names)
      checkPoints(@[e["at"]], w, names, 1, 1)
      need(not e.has("anchor") or strIn(e["anchor"], ["start", "middle", "end"]), "bad_value", w)
      if e.has("size"): discard num(e["size"], w, 1, 200)
      need(not e.has("font") or strIn(e["font"], ["body", "display", "mono"]), "bad_value", w)
      need(not e.has("weight") or numEq(e["weight"], [400, 600, 700]), "bad_value", w)
    else:   # group
      if e.has("clip"):
        keys(e["clip"], ["rect"], ["rx"], where = w)
        for r in lst(e["clip"]["rect"], w, 4, 4): checkRef(r, w, names)
        if e["clip"].has("rx"): checkRef(e["clip"]["rx"], w, names)
      checkElements(e["group"], w, names, isStatic, elements, particles)

proc checkFigure*(f: JNode, where: string, c: ptr Course = nil) =
  keys(f, ["title", "caption", "alt", "w", "h", "scene"], ["period", "slider", "toggles", "modes", "values", "status"],
       where = where)
  discard text(f["title"], where)
  if c != nil: c[].run(f["caption"], where, allowEmpty = true)
  need(f["alt"].kind == jStr and f["alt"].s.len > 0, "bad_value", where & ".alt")
  discard num(f["w"], where, 1, 4000, integer = true)
  discard num(f["h"], where, 1, 4000, integer = true)
  let isStatic = not f.has("period")
  var names: HashSet[string]
  if isStatic:
    for k in ["slider", "toggles", "modes", "status"]: need(not f.has(k), "static_inputs", where & "." & k)
  else:
    discard num(f["period"], where, 1, 60)
    names = toHashSet(["t", "v", "mode"])
  if f.has("slider"):
    let s = f["slider"]
    keys(s, ["label", "init", "text"], ["drive"], where = where & ".slider")
    discard text(s["label"], where)
    discard num(s["init"], where, 0, 1)
    if s.has("drive"):
      let d = s["drive"]
      keys(d, ["of", "table"], where = where & ".drive")
      need(strIn(d["of"], ["t"]), "bad_drive", where)
      checkTable(d["table"], where & ".drive")
  if f.has("toggles"):
    need(isArr(f["toggles"]), "bad_type", where)
    for tg in f["toggles"].elems:
      keys(tg, ["key", "label", "on"], where = where & ".toggle")
      let k = ident(tg["key"], where)
      need(k notin names, "dup_id", k)
      names.incl k
      discard text(tg["label"], where)
      need(tg["on"].kind == jBool, "bad_type", where)
  if f.has("modes"):
    var seen: HashSet[string]
    for m in lst(f["modes"], where, 2, 8):
      keys(m, ["key", "label"], where = where & ".mode")
      let k = ident(m["key"], where)
      need(k notin seen, "dup_id", k)
      seen.incl k
      discard text(m["label"], where)
  let values = if f.has("values"): lst(f["values"], where, 0, MaxValues) else: @[]
  var later: HashSet[string]
  for pair in values:
    if isArr(pair) and pair.len == 2 and pair[0].kind == jStr: later.incl pair[0].s
  for pair in values:
    discard lst(pair, where, 2, 2)
    let name = ident(pair[0], where)
    need(name notin names and name notin ["t", "v", "mode"], "dup_id", name)
    checkNode(pair[1], where & ".values." & name, names, later)
    names.incl name
  if f.has("slider"):
    var withV = names
    withV.incl "v"
    checkText(f["slider"]["text"], where & ".slider.text", withV)
  if f.has("status"): checkText(f["status"], where & ".status", names)
  var elements, particles = 0
  checkElements(f["scene"], where & ".scene", names, isStatic, elements, particles)
  need(elements <= MaxElements, "limit", where)
  need(particles <= MaxParticles, "limit", where)

# ---------------------------------------------------------------- figure evaluation

proc tableAt*(t: JNode, u: float, step = false): float =
  if u < t[0][0].num: return t[0][1].num
  if step:
    result = t[0][1].num
    for pt in t.elems:
      if pt[0].num <= u: result = pt[1].num
      else: break
    return
  if u >= t[t.len - 1][0].num: return t[t.len - 1][1].num
  var i = 0
  for j in 0 ..< t.len:
    if t[j][0].num <= u: i = j
    else: break
  let x0 = t[i][0].num
  let y0 = t[i][1].num
  let x1 = t[i + 1][0].num
  let y1 = t[i + 1][1].num
  y0 + (y1 - y0) * (u - x0) / (x1 - x0)

proc paintStep(t: JNode, u: float): JNode =
  ## A step table whose y values are paints.
  result = t[0][1]
  if u < t[0][0].num: return
  for pt in t.elems:
    if pt[0].num <= u: result = pt[1]
    else: break

proc hexMix(a, b: string, f: float): string =
  result = "#"
  for i in [1, 3, 5]:
    let x = float(parseHexInt(a[i .. i + 1]))
    let y = float(parseHexInt(b[i .. i + 1]))
    result.add toHex(int(floor(x + (y - x) * f + 0.5)), 2).toLowerAscii

proc colourAt*(stops: JNode, u: float): string =
  if u < stops[0][0].num: return stops[0][1].s
  if u >= stops[stops.len - 1][0].num: return stops[stops.len - 1][1].s
  var i = 0
  for j in 0 ..< stops.len:
    if stops[j][0].num <= u: i = j
  hexMix(stops[i][1].s, stops[i + 1][1].s, (u - stops[i][0].num) / (stops[i + 1][0].num - stops[i][0].num))

proc frac*(x: float): float = x - floor(x)

type
  Particle* = object
    k*: float
    n*: int
    route*: int                ## -1 until chosen
    x*, y*, r*, opacity*: float
    fill*: JNode

  Figure* = ref object
    f*: JNode
    isStatic*: bool
    t*, v*: float
    toggles*: OrderedTable[string, float]
    mode*: int
    playing*: bool
    vals*: OrderedTable[string, float]
    follow: Table[string, float]
    hold: Table[string, (float, bool)]
    first: bool
    flows*: seq[(JNode, seq[Particle])]

proc flatten*(path: JNode, refv: proc (r: JNode): float): (seq[(float, float)], seq[float], float) =
  ## A route's polyline: M/L as they are, each cubic as 16 segments.
  var pts: seq[(float, float)]
  for c in path.elems:
    case c[0].s
    of "M", "L": pts.add (refv(c[1]), refv(c[2]))
    of "C":
      let (x0, y0) = pts[^1]
      let x1 = refv(c[1])
      let y1 = refv(c[2])
      let x2 = refv(c[3])
      let y2 = refv(c[4])
      let x3 = refv(c[5])
      let y3 = refv(c[6])
      for s in 1 .. 16:
        let t = s / 16
        let a = pow(1 - t, 3.0)
        let b = 3 * pow(1 - t, 2.0) * t
        let cc = 3 * (1 - t) * t * t
        let d = pow(t, 3.0)
        pts.add (a * x0 + b * x1 + cc * x2 + d * x3, a * y0 + b * y1 + cc * y2 + d * y3)
    else: discard
  var segs: seq[float]
  var total = 0.0
  for i in 0 ..< pts.len - 1:
    let s = hypot(pts[i + 1][0] - pts[i][0], pts[i + 1][1] - pts[i][1])
    segs.add s
    total += s
  (pts, segs, total)

proc pointAt*(pts: seq[(float, float)], segs: seq[float], dist0: float): (float, float) =
  var dist = dist0
  for i, s in segs:
    if dist <= s or i == segs.high:
      let f = if s == 0: 0.0 else: min(1.0, max(0.0, dist / s))
      return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * f, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * f)
    dist -= s
  pts[0]

proc refv*(fg: Figure, r: JNode): float =
  if r.kind == jStr: fg.vals[r.s] else: r.num

proc collect(fg: Figure, es: JNode) =
  for e in es.elems:
    if e.has("flow"):
      let fl = e["flow"]
      let n = int(fl["count"].num)
      var parts = newSeq[Particle](n)
      for i in 0 ..< n: parts[i] = Particle(k: i / n, route: -1)
      fg.flows.add((fl, parts))
    elif e.has("group"):
      fg.collect(e["group"])

proc choose*(fg: Figure, fl: JNode, i, n: int): int =
  let count = int(fl["count"].num)
  let u = frac(float(i + n * count) * Phi)
  var ws: seq[float]
  var total = 0.0
  for rt in fl["routes"].elems:
    let w = max(0.0, if rt.has("weight"): fg.refv(rt["weight"]) else: 1.0)
    ws.add w
    total += w
  if total <= 0: return 0
  var acc = 0.0
  for j, w in ws:
    acc += w
    if acc > u * total: return j
  ws.high

proc stepFlow(fg: Figure, fl: JNode, parts: var seq[Particle], dt: float) =
  var geo: seq[(seq[(float, float)], seq[float], float)]
  for rt in fl["routes"].elems: geo.add flatten(rt["path"], proc (r: JNode): float = fg.refv(r))
  let along = fl.get("along")
  proc alongAt(name: string, k: float): float =
    if along != nil and along.has(name): tableAt(along[name], k) else: 1.0
  let speed = if fl.has("speed"): fg.refv(fl["speed"]) else: 0.0
  let r0 = if fl.has("r"): fg.refv(fl["r"]) else: 3.0
  let op0 = if fl.has("opacity"): fg.refv(fl["opacity"]) else: 1.0
  let pile = if fl.has("pile"): fl["pile"].num else: 0.0
  let pileMode = strIn(fl.get("reverse"), ["pile"])
  var hides: seq[(array[4, float], float)]
  if fl.has("hide"):
    for h in fl["hide"].elems:
      var rect: array[4, float]
      for q in 0 .. 3: rect[q] = fg.refv(h["rect"][q])
      hides.add((rect, fg.refv(h["when"])))
  for i in 0 ..< parts.len:
    var p = parts[i]
    if p.route < 0: p.route = fg.choose(fl, i, 0)
    var L = geo[p.route][2]
    let m = alongAt("speed", p.k)
    let dk = if L == 0: 0.0 else: speed * m * dt / L
    var k = p.k + dk
    if pileMode and dk < 0:
      k = max(k, if L == 0: 0.0 else: min(1.0, pile * frac(float(i) * Phi) / L))
    if k >= 1:
      k -= floor(k)
      inc p.n
      p.route = fg.choose(fl, i, p.n)
    elif k < 0:
      k -= floor(k)
    p.k = k
    let (pts, segs, L2) = geo[p.route]
    var (x, y) = pointAt(pts, segs, k * L2)
    let rt = fl["routes"][p.route]
    let lanes = if rt.has("lanes"): rt["lanes"] elif fl.has("lanes"): fl["lanes"] else: nil
    var lx, ly = 0.0
    if lanes != nil:
      let lane = lanes[i mod lanes.len]
      lx = fg.refv(lane[0])
      ly = fg.refv(lane[1])
    let ls = alongAt("lane", k)
    x = x + lx * ls
    y = y + ly * ls
    if fl.has("wrap_x"):
      let a = fl["wrap_x"][0].num
      let b = fl["wrap_x"][1].num
      x = a + (x - a) - (b - a) * floor((x - a) / (b - a))
    p.x = x
    p.y = y
    p.r = r0 * alongAt("r", k)
    p.opacity = op0 * alongAt("opacity", k)
    for (rect, whenV) in hides:
      if whenV >= 0.5 and rect[0] <= x and x <= rect[2] and rect[1] <= y and y <= rect[3]: p.opacity = 0.0
    p.fill = if along != nil and along.has("fill"): paintStep(along["fill"], k)
             elif fl.has("fill"): fl["fill"] else: newStr("accent")
    parts[i] = p
    discard L

proc node(fg: Figure, name: string, n: JNode, dt: float): float =
  if n.has("table"): return tableAt(n["table"], fg.vals[n["of"].s], n.has("step") and n["step"].b)
  if n.has("sum"):
    result = 0.0
    for r in n["sum"].elems: result += fg.refv(r)
    return
  if n.has("product"):
    result = 1.0
    for r in n["product"].elems: result *= fg.refv(r)
    return
  if n.has("select"):
    let cs = n["cases"]
    let i = min(cs.len - 1, max(0, int(floor(fg.vals[n["select"].s]))))
    return fg.refv(cs[i])
  if n.has("follow"):
    let target = fg.vals[n["follow"].s]
    if fg.first: fg.follow[name] = if n.has("init"): n["init"].num else: target
    var o = fg.follow[name]
    let k = if target >= o: n["rate"].num elif n.has("rate_down"): n["rate_down"].num else: n["rate"].num
    o = o + (target - o) * min(1.0, dt * k)
    fg.follow[name] = o
    return o
  let x = fg.vals[n["hold"].s]
  let w = fg.vals[n["while"].s] >= 0.5
  let (held, prev) = fg.hold.getOrDefault(name, (x, false))
  let outV = if w and prev and not fg.first: held else: x
  fg.hold[name] = (outV, w)
  outV

proc step(fg: Figure, dt: float) =
  fg.vals.clear()
  if not fg.isStatic:
    fg.vals["t"] = fg.t
    fg.vals["v"] = fg.v
    fg.vals["mode"] = float(fg.mode)
    for k, v in fg.toggles: fg.vals[k] = v
  if fg.f.has("values"):
    for pair in fg.f["values"].elems:
      fg.vals[pair[0].s] = fg.node(pair[0].s, pair[1], dt)
  for i in 0 ..< fg.flows.len: fg.stepFlow(fg.flows[i][0], fg.flows[i][1], dt)
  fg.first = false

proc newFigure*(f: JNode, reduceMotion = false): Figure =
  result = Figure(f: f, isStatic: not f.has("period"), first: true)
  result.v = if f.has("slider"): f["slider"]["init"].num else: 0.0
  if f.has("toggles"):
    for tg in f["toggles"].elems: result.toggles[tg["key"].s] = if tg["on"].b: 1.0 else: 0.0
  result.playing = not reduceMotion and not result.isStatic
  result.collect(f["scene"])
  result.step(0.0)

proc hasDrive(fg: Figure): bool = fg.f.has("slider") and fg.f["slider"].has("drive")

proc setSlider*(fg: Figure, v: float) =
  fg.v = v
  if fg.hasDrive: fg.playing = false

proc toggle*(fg: Figure, key: string) =
  fg.toggles[key] = 1.0 - fg.toggles[key]
  fg.t = 0.0
  fg.playing = true

proc setMode*(fg: Figure, i: int) =
  fg.mode = i
  fg.playing = true

proc play*(fg: Figure) = fg.playing = true
proc pause*(fg: Figure) = fg.playing = false

proc tick*(fg: Figure, elapsed0: float) =
  if fg.isStatic: return
  let elapsed = min(0.05, elapsed0)
  var dt = 0.0
  if fg.playing:
    dt = elapsed
    fg.t = frac(fg.t + dt / fg.f["period"].num)
    if fg.hasDrive: fg.v = tableAt(fg.f["slider"]["drive"]["table"], fg.t)
  fg.step(dt)

proc valsTable(fg: Figure): Table[string, float] =
  for k, v in fg.vals: result[k] = v

proc textOf*(fg: Figure, t: JNode): string =
  if t.kind == jStr: return fillTemplate(t.s, fg.valsTable)
  for c in t.elems:
    if not c.has("when") or fg.refv(c["when"]) >= 0.5: return fillTemplate(c["text"].s, fg.valsTable)

proc paint(fg: Figure, p: JNode): JNode =
  if p.kind == jStr or p.has("radial"): return p
  if p.has("stops"): return newStr(colourAt(p["stops"], fg.vals[p["of"].s]))
  paintStep(p["steps"], fg.vals[p["of"].s])

proc leaderEnd*(label: string, at, to: (float, float), anchor: string): (float, float) =
  let (x1, y1) = at
  let (x2, y2) = to
  let w = 6.3 * float(label.runeLen)
  let left = if anchor == "end": x2 - w else: x2
  let right = left + w
  if x1 < left - 2: return (left - 4, y2 - 4)
  if x1 > right + 2: return (right + 4, y2 - 4)
  (x1, if y1 > y2: y2 + 4 else: y2 - 15)

proc numArr(fg: Figure, a: JNode): JNode =
  result = newArr()
  for x in a.elems: result.elems.add newFloat(fg.refv(x))

proc particles(fg: Figure, fl: JNode): JNode =
  result = newArr()
  for (f, parts) in fg.flows:
    if f == fl:
      for p in parts:
        result.elems.add newArr(@[newFloat(p.x), newFloat(p.y), newFloat(p.r), newFloat(p.opacity), p.fill])

proc resolve(fg: Figure, e: JNode): JNode =
  result = newObj()
  for (k, v) in e.fields:
    case k
    of "rect", "circle", "ellipse", "line", "at", "to": result.fields.add((k, fg.numArr(v)))
    of "poly":
      var a = newArr()
      for p in v.elems: a.elems.add fg.numArr(p)
      result.fields.add((k, a))
    of "path":
      var a = newArr()
      for c in v.elems:
        var cmd = newArr(@[c[0]])
        for x in c.elems[1 .. ^1]: cmd.elems.add newFloat(fg.refv(x))
        a.elems.add cmd
      result.fields.add((k, a))
    of "fill", "stroke": result.fields.add((k, fg.paint(v)))
    of "stroke_width", "opacity", "rx": result.fields.add((k, newFloat(fg.refv(v))))
    of "transform":
      var a = newArr()
      for st in v.elems:
        var o = newObj()
        for (kk, vv) in st.fields: o.fields.add((kk, fg.numArr(vv)))
        a.elems.add o
      result.fields.add((k, a))
    of "text": result.fields.add((k, newStr(fg.textOf(v))))
    of "clip":
      result.fields.add((k, newObj(@[("rect", fg.numArr(v["rect"])),
                                     ("rx", newFloat(if v.has("rx"): fg.refv(v["rx"]) else: 0.0))])))
    of "group":
      var a = newArr()
      for c in v.elems: a.elems.add fg.resolve(c)
      result.fields.add((k, a))
    of "flow":
      var o = newObj(@[("particles", fg.particles(v))])
      for kk in ["glyph", "stroke", "stroke_width"]:
        if v.has(kk): o.fields.add((kk, if kk == "stroke_width": newFloat(fg.refv(v[kk])) else: v[kk]))
      result.fields.add((k, o))
    else: result.fields.add((k, v))
  if e.has("label"):
    let at = result["at"]
    let to = result["to"]
    let (ex, ey) = leaderEnd(e["label"].s, (at[0].f, at[1].f), (to[0].f, to[1].f),
                             if e.has("anchor"): e["anchor"].s else: "start")
    result.fields.add(("end", newArr(@[newFloat(ex), newFloat(ey)])))

proc scene*(fg: Figure): JNode =
  ## The scene with every ref, paint, text and label resolved, and flows replaced by their particles.
  result = newArr()
  for e in fg.f["scene"].elems: result.elems.add fg.resolve(e)

proc status*(fg: Figure): JNode =
  if fg.f.has("status"): newStr(fg.textOf(fg.f["status"])) else: newNull()

proc sliderText*(fg: Figure): JNode =
  if fg.f.has("slider"): newStr(fg.textOf(fg.f["slider"]["text"])) else: newNull()
