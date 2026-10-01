## The courses (docs/COURSES.md) as the native apps show them, shared by GNOME and Windows: the course list, one
## course's pages, its progress (private entries through the local API, §8: the v1 keys `last`, `skip`, `solved`,
## `finalBest`, each a JSON string) and the page logic every renderer needs (module done, recall, test draw,
## placement plan, drill judging). No widgets here; each app draws with its own toolkit.

import std/[algorithm, random, sequtils, sets, strutils, tables]
import kks/[json, api, courses]
import appstate

type
  CourseRef* = object
    id*, title*, short*: string
    questions*: seq[string]
  Course* = ref object
    a*: App
    doc*: JNode
    id*: string
    pages*: seq[JNode]
    mods*: seq[JNode]
    gloss*: Table[string, JNode]
    images*: HashSet[string]
    solved*: HashSet[string]
    skip*: HashSet[string]
    last*: string
    finalBest*: int
    onProgress*: seq[proc ()]
  Item* = object                 ## a test or placement question with its module
    module*: string
    q*: JNode

var rng = initRand()

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].kind == jStr: n[k].s else: ""

proc listCourses*(a: App): seq[CourseRef] =
  let (files, images) = a.courseFiles
  let (docs, bad) = pickCourses(files, images)
  for b in bad: stderr.writeLine "course refused: " & b
  for d in docs:
    let sm = summary(d)
    var r = CourseRef(id: d["id"].s, title: d["title"].s, short: d["short"].s)
    for q in sm["questions"].elems: r.questions.add q.s
    result.add r

# ---------------------------------------------------------------- progress

proc loadProgress(c: Course) =
  var data = newObj()
  try: data = c.a.call("GET", "/api/progress", nil, {"course": c.id}.toTable)["data"]
  except ApiError: discard
  proc val(k: string): JNode =
    if data.get(k) != nil and data[k].kind == jStr:
      try: return parseStrict(data[k].s)
      except CatchableError: discard
  let sv = val("solved")
  if sv != nil and sv.kind == jObj:
    for (k, v) in sv.fields:
      if v.kind == jBool and v.b: c.solved.incl k
  let sk = val("skip")
  if sk != nil and sk.kind == jObj:
    for (k, v) in sk.fields:
      if v.kind == jBool and v.b: c.skip.incl k
  let l = val("last")
  if l != nil and l.kind == jStr: c.last = l.s
  let fb = val("finalBest")
  if fb != nil and fb.kind in {jInt, jFloat}: c.finalBest = int(fb.num)

proc save(c: Course, key: string, v: JNode) =
  try: discard c.a.call("POST", "/api/progress", newObj(@[("course", newStr(c.id)),
                        ("data", newObj(@[(key, newStr(toText(v)))]))]))
  except ApiError as e: stderr.writeLine "progress not saved: " & e.msg
  for f in c.onProgress: f()

proc setObj(keys: HashSet[string]): JNode =
  var ks = toSeq(keys)
  ks.sort()
  result = newObj()
  for k in ks: result[k] = newBool(true)

proc markSolved*(c: Course, qid: string) =
  if qid in c.solved: return
  c.solved.incl qid
  c.save("solved", setObj(c.solved))

proc setSkip*(c: Course, mods: HashSet[string]) =
  c.skip = mods
  c.save("skip", setObj(mods))

proc setLast*(c: Course, pageId: string) =
  if c.last == pageId: return
  c.last = pageId
  try: discard c.a.call("POST", "/api/progress", newObj(@[("course", newStr(c.id)),
                        ("data", newObj(@[("last", newStr(toText(newStr(pageId))))]))]))
  except ApiError: discard

proc recordScore*(c: Course, score: int) =
  if score > c.finalBest:
    c.finalBest = score
    c.save("finalBest", newInt(score))

# ---------------------------------------------------------------- opening a course

proc openCourse*(a: App, id: string): Course =
  ## nil when the course is not (or no longer) available
  let (files, images) = a.courseFiles
  let (docs, _) = pickCourses(files, images)
  for d in docs:
    if d["id"].s == id:
      result = Course(a: a, doc: d, id: id, images: images)
      for p in d["pages"].elems:
        result.pages.add p
        if p["kind"].s == "module": result.mods.add p
      for g in d["glossary"].elems: result.gloss[g["term"].s] = g
      result.loadProgress()
      return

proc page*(c: Course, id: string): JNode =
  for p in c.pages:
    if p["id"].s == id: return p

proc startPage*(c: Course): JNode =
  result = c.page(c.last)
  if result == nil: result = c.pages[0]

proc module*(c: Course, id: string): JNode =
  for m in c.mods:
    if m["id"].s == id: return m

# ---------------------------------------------------------------- text

proc plain*(r: JNode): string =
  ## a run as plain text (titles, accessible names)
  if r == nil: return
  for x in r.elems:
    if x.kind == jStr: result.add x.s
    elif x.get("num") != nil: result.add x["num"].s
    else:
      for k in ["b", "i", "small", "term", "link"]:
        if x.get(k) != nil:
          result.add plain(x[k])
          break

proc pageTitle*(c: Course, p: JNode): string =
  if p["kind"].s == "module": p["n"].s & " · " & p["short"].s else: plain(p["title"])

# ---------------------------------------------------------------- modules (§6)

proc moduleQs*(m: JNode): seq[JNode] =
  result.add m["warm"]
  for q in m["practice"].elems: result.add q
  let b = m.get("bridge")
  if b != nil:
    for q in b["questions"].elems: result.add q

proc done*(c: Course, m: JNode): bool =
  for q in moduleQs(m):
    if q["id"].s notin c.solved: return false
  true

proc progress*(c: Course): (int, int) =
  for m in c.mods:
    for q in moduleQs(m):
      inc result[1]
      if q["id"].s in c.solved: inc result[0]

proc recall*(c: Course, m: JNode): seq[JNode] =
  ## 2 questions drawn from the practice of the modules before (choice and scenario only)
  var pool: seq[JNode]
  for x in c.mods:
    if x["id"].s == m["id"].s: break
    for q in x["practice"].elems:
      if q["type"].s != "order": pool.add q
  rng.shuffle(pool)
  pool[0 ..< min(2, pool.len)]

proc shuffled*[T](xs: seq[T]): seq[T] =
  result = xs
  rng.shuffle(result)

# ---------------------------------------------------------------- tests and placement (§7)

proc items*(c: Course, p: JNode): seq[Item] =
  ## a placement's items in file order; a test's drawn at random (`draw`), references resolved
  var byId: Table[string, JNode]
  for m in c.mods:
    for q in moduleQs(m): byId[q["id"].s] = q
  for it in p["items"].elems:
    let q = if it.get("q") != nil: it["q"] else: byId.getOrDefault(it["ref"].s)
    if q != nil: result.add Item(module: it["module"].s, q: q)
  if p["kind"].s == "test":
    rng.shuffle(result)
    if p["draw"].kind != jNull: result.setLen(min(result.len, int(p["draw"].num)))

proc placementPlan*(c: Course, answers: seq[(string, bool)]): (seq[JNode], HashSet[string]) =
  ## (modules to take, modules that may be skipped): a module whose items were all right may be skipped
  var n, ok: Table[string, int]
  for (m, right) in answers:
    n.mgetOrPut(m, 0).inc
    if right: ok.mgetOrPut(m, 0).inc
  for m in c.mods:
    let id = m["id"].s
    if id in n:
      if ok.getOrDefault(id) == n[id]: result[1].incl id
      else: result[0].add m

# ---------------------------------------------------------------- drills

proc readingText*(v: float, unit: string): string =
  ## §7: minus is U+2212; values in mm above 0 get a +
  var t = if v == float(int(v)) and abs(v) < 1e15: $int(v) else: $v
  if t.startsWith("-"): t = "−" & t[1 .. ^1]
  if v > 0 and unit == "mm": t = "+" & t
  t

proc pick*[T](xs: seq[T]): T = xs[rng.rand(xs.len - 1)]
