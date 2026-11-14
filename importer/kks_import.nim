## kks-import: add a P&ID to the plant data (decision 0026; the Nim successor of import_sheet.py).
##
##   kks-import DRAWING.pdf "Display name" [SHEET_ID] [--rotate auto|0|90|180|270] [--replace] [--data-dir DIR]
##   kks-import DRAWING.pdf "Display name" SHEET_ID --keep-tags [--data-dir DIR]
##     (the cutover: an existing v1 sheet gets its path store and pyramid; its tags and notes, hand-verified ones
##      included, stay exactly as they are; refused if the image size differs from the sheet's, as the boxes
##      would no longer line up)
##              [--glyphs fontlib.kgl] [--effort N] [--legend auto|hrsg|none] [--reader auto|glyphs|text] [--unit NN]
##   Options go before the positional arguments or anywhere among them; after `--` everything is positional (the
##   server passes the sheet name, which the manager types, after it).
##
## Reads page 1 of a vector (AutoCAD-plotted) PDF and writes into DIR (default plant-data/). The tags come from the
## page's text layer when it holds any (textlayer.nim; --reader text|glyphs forces one way), else from the glyph reader
## on the drawn strokes, unchanged. --unit NN completes text codes the drawing writes without their unit number.
##   sheets/<id>.pdf      the drawing as given (the source of record)
##   sheets/<id>.kkp      the grid-indexed path store (docs/PATHSTORE.md)
##   sheets/<id>.o<k>.jxl the overview pyramid (docs/PATHSTORE.md "Overview pyramid")
##   sheets.json, tags.json  this sheet's entry and its tags (other sheets kept)
## Each valve tag (component AA) gets an optional "symbol" field when its drawn symbol is found and the sheet carries
## the HRSG legend (valves.nim; --keep-tags refreshes it and leaves the rest of each tag alone). The sheet's entry
## gets its off-page connectors, "links" (connectors.nim), in both modes. The reading is the Python importer's,
## bit for bit (tests/diff_trace.nim). The last output line is `RESULT {json}` for the server.

import std/[os, strutils, times, parseopt, algorithm]
import kks/[json, pathstore]
import kksi/[mupdf, fontlib, reader, textlines, extract, kkp, jxl, connectors, valves, textlayer]

const
  RepoGlyphs = currentSourcePath().parentDir / "fontlib.kgl"
  OverviewMax = 6400.0   ## level 0's long side at most (px), and at most 2 px per point
  ThumbMax = 512         ## the last level's long side is at most this
  TextOverStrokes = 10   ## auto: the text layer's tags × this must reach the drawn strokes' text lines (textlines.score)

proc log(s: string) =
  stdout.writeLine s
  stdout.flushFile

proc die(s: string) {.noreturn.} =
  stderr.writeLine s
  quit 1

proc findGlyphs(given: string): string =
  for p in [given, getEnv("KKS_GLYPHS"), getAppDir() / "fontlib.kgl", getAppDir() / ".." / "share" / "kks-explorer" / "fontlib.kgl",
            RepoGlyphs]:
    if p.len > 0 and fileExists(p): return p
  die "The glyph library (fontlib.kgl) was not found: pass --glyphs PATH."

proc writeAtomic(path, data: string) =
  let tmp = path & ".tmp"
  writeFile(tmp, data)
  moveFile(tmp, path)

proc sheetId(name: string): string =
  var prevDash = false
  for c in name.toLowerAscii:
    if c in {'a' .. 'z', '0' .. '9'}:
      result.add c
      prevDash = false
    elif not prevDash and result.len > 0:
      result.add '-'
      prevDash = true
  result = result.strip(chars = {'-'})
  if result.len > 24: result = result[0 ..< 24]

proc validId(s: string): bool =
  s.len in 1 .. 24 and s[0] in {'a' .. 'z', '0' .. '9'} and s.allCharsInSet({'a' .. 'z', '0' .. '9', '-'})

proc autoCount(ts: seq[Tag]): int =
  for t in ts:
    if t.status == "auto": inc result

when defined(linux) and not defined(android):
  # glibc's malloc gives each thread that allocates its own arena, reserving 64 MB of address space apiece; libjxl's
  # encoder runs one thread per CPU, so on a 20-thread laptop the reservations alone came to about 1.3 GB. The server
  # runs the importer under an address-space limit (import_memory_mb, RLIMIT_AS), which counts reservations, not
  # memory used: the largest real sheet peaked at 3.2 GB of address space for 1.85 GB resident, and crashed under a
  # 2.5 GB limit. Two arenas: 1.96 GB of address space for the same 1.85 GB (2026-10-09), and the same output.
  proc mallopt(param, value: cint): cint {.importc, header: "<malloc.h>".}
  var M_ARENA_MAX {.importc, header: "<malloc.h>".}: cint
  discard mallopt(M_ARENA_MAX, 2)

proc main() =
  var args: seq[string]
  var rotate = "auto"
  var replace = false
  var keepTags = false
  var dataDir = getCurrentDir() / "plant-data"
  var glyphs = ""
  var effort = 7
  var legend = "auto"
  var tagReader = "auto"
  var unit = ""
  # "--": everything after it is a positional argument (issue #38; parseopt's remainingArgs skips the first one)
  var params = commandLineParams()
  var positional: seq[string]
  let cut = params.find("--")
  if cut >= 0:
    positional = params[cut + 1 .. ^1]
    params.setLen(cut)
  var p = initOptParser(params, shortNoVal = {'h'}, longNoVal = @["replace", "keep-tags", "help"])
  for kind, key, val in p.getopt():
    case kind
    of cmdArgument: args.add key
    of cmdLongOption, cmdShortOption:
      case key
      of "rotate": rotate = val
      of "replace": replace = true
      of "keep-tags": keepTags = true
      of "data-dir": dataDir = val
      of "glyphs": glyphs = val
      of "effort": effort = parseInt(val)
      of "legend": legend = val
      of "reader": tagReader = val
      of "unit": unit = val
      of "help", "h":
        echo "kks-import DRAWING.pdf \"Display name\" [SHEET_ID] [--rotate auto|0|90|180|270] [--replace] [--data-dir DIR] [--glyphs fontlib.kgl] [--effort 1-9] [--legend auto|hrsg|none] [--reader auto|glyphs|text] [--unit NN]"
        quit 0
      else: die "Unknown option --" & key
    of cmdEnd: discard
  args.add positional
  if args.len notin 2 .. 3: die "Usage: kks-import DRAWING.pdf \"Display name\" [SHEET_ID] [options]; --help for more."
  if rotate notin ["auto", "0", "90", "180", "270"]: die "--rotate must be auto, 0, 90, 180 or 270."
  if legend notin ["auto", "hrsg", "none"]: die "--legend must be auto, hrsg or none."
  if tagReader notin ["auto", "glyphs", "text"]: die "--reader must be auto, glyphs or text."
  if unit.len > 0 and not unit.full("DD"): die "--unit must be two digits (the unit number the drawing leaves out)."
  let src = args[0]
  let name = args[1]
  let sid = if args.len == 3: args[2] else: sheetId(name)
  if not validId(sid): die "Bad sheet id \"" & sid & "\": use 1-24 lowercase letters, digits, dashes."
  let sheetsPath = dataDir / "sheets.json"
  let tagsPath = dataDir / "tags.json"
  var sheets = if fileExists(sheetsPath): parseStrict(readFile(sheetsPath), 4096) else: newArr()
  var tags = if fileExists(tagsPath): parseStrict(readFile(tagsPath), 4096) else: newArr()
  var old: JNode = nil
  for s in sheets.elems:
    if s["id"].s == sid:
      old = s
      if not replace and not keepTags: die "Sheet id \"" & sid & "\" exists; pass a different id, or --replace."
  if keepTags:
    if old == nil: die "--keep-tags needs an existing sheet \"" & sid & "\" in " & sheetsPath
    if args.len != 3: die "--keep-tags needs the SHEET_ID"
    rotate = $old["rot"].i      # the v1 sheet's rotation: the same page its tags were read on
  init()
  let lib = loadGlyphLib(findGlyphs(glyphs))
  var rd = Reader(lib: lib)
  let t0 = epochTime()

  # The text layer first: a drawing whose tags are real text needs no glyph reading (and no orientation guess from
  # stroke lines, which such a drawing hardly has). A drawing without one takes the glyph reader's path, unchanged.
  # In auto mode the text wins only when its tags are not outnumbered by the drawn strokes' text lines (a stroke
  # drawing with a code in a stamp or a note stays with the glyph reader), and anything wrong with the text layer
  # (a limit, a font MuPDF can't read for text) leaves the drawing to the glyph reader as before.
  var textMode = false
  if keepTags and tagReader == "text": die "--keep-tags reads no tags: --reader text does not go with it."
  if not keepTags and tagReader != "glyphs":
    let d0 = rotatedCopy(src, if rotate == "auto": 0 else: parseInt(rotate))
    var n = 0
    var why = ""
    try:
      for t in textTags(d0, unit):
        if t.status == "auto": inc n
    except TextLimitError, MupdfError:
      why = getCurrentExceptionMsg()
    if why.len > 0:
      if tagReader == "text": die why
      log "The drawing's text layer was not read (" & why & "): reading the strokes."
    elif n == 0:
      if tagReader == "text": die "--reader text: the drawing's text layer holds no tags."
    elif tagReader == "text":
      textMode = true
    else:
      let (h, v) = score(loadPaths(d0))
      textMode = n * TextOverStrokes >= h + v
      if not textMode:
        log "The text layer holds " & $n & " tags, but the strokes draw " & $(h + v) &
            " lines of text: reading the strokes (--reader text reads the text layer)."
    d0.close()
    if textMode: log "Reading the tags from the drawing's text layer (" & $n & " found; --reader glyphs reads the strokes instead)."
  var rot: int
  if textMode and rotate == "auto":
    log "Finding orientation from the text..."
    var best = low(int)
    for extra in [0, 90, 180, 270]:
      let d = rotatedCopy(src, extra)
      let n = uprightScore(d)
      d.close()
      log "  " & align($extra, 3) & "°: " & $n & " (characters reading across or up, minus those reading back or down)"
      if n > best:
        best = n
        rot = extra
  elif rotate == "auto":
    log "Finding orientation..."
    var best = -1
    for extra in [0, 90, 180, 270]:
      let d = rotatedCopy(src, extra)
      let (h, _) = score(loadPaths(d))
      d.close()
      log "  " & align($extra, 3) & "°: " & $h & " text lines"
      if h > best:
        best = h
        rot = extra
  else:
    rot = parseInt(rotate)
    log "Rotation forced to " & $rot & "°."
  var doc = rotatedCopy(src, rot)
  var found: seq[Tag]
  if textMode:
    found = textTags(doc, unit)
  elif not keepTags:
    log "Extracting tags (this is the slow part)..."
    found = extract.extract(rd, doc, loadPaths(doc))
  # The text-line score can't tell upright from upside down, but the reader can (import_sheet.py).
  var nFound = 0
  for t in found:
    if t.status != "ignore": inc nFound
  if not keepTags and not textMode and rotate == "auto" and nFound >= 10 and float(autoCount(found)) < 0.25 * float(nFound):
    let flip = (rot + 180) mod 360
    log "Only " & $autoCount(found) & " of " & $nFound & " tags readable at " & $rot & "°: the sheet may be upside down. Trying " & $flip & "°..."
    let doc2 = rotatedCopy(src, flip)
    let found2 = extract.extract(rd, doc2, loadPaths(doc2))
    if autoCount(found2) > autoCount(found):
      log "Kept " & $flip & "°: " & $autoCount(found2) & " tags readable."
      doc.close()
      doc = doc2
      found = found2
      rot = flip
    else:
      log "Kept " & $rot & "°: " & $flip & "° was no better (" & $autoCount(found2) & " readable). This sheet just reads poorly."
      doc2.close()

  if keepTags:     # before anything is written: same page size as the v1 sheet, or the boxes won't line up
    let (pw0, ph0) = doc.pageSize
    let z0 = min(2.0, OverviewMax / max(float(pw0), float(ph0)))
    let (w, h) = (int(float(pw0) * z0), int(float(ph0) * z0))
    if abs(w - int(old["w"].i)) > 1 or abs(h - int(old["h"].i)) > 1:
      die "The new image would be " & $w & "x" & $h & " px, the v1 sheet is " & $old["w"].i & "x" & $old["h"].i &
          ": the tags' boxes would not line up. Nothing written."
  log "Finding the connectors to other sheets..."
  # on the page the tags were read on (no annotations); before anything is written, so a page past the connector
  # finder's limits (a crafted PDF) leaves the plant data as it was
  let links = try: findConnectors(doc, lib) except ConnectorLimitError as e: die e.msg
  createDir(dataDir / "sheets")
  log "Writing the path store..."
  let srcDoc = mupdf.open(src)
  let drawing = fromPdfPage(srcDoc, sheetExtra(rot, srcDoc.pageRotation), text = textMode)   # the overview's frame
  writeAtomic(dataDir / "sheets" / (sid & ".kkp"), encode(drawing))
  let notes = srcDoc.annotNotes()
  srcDoc.close()
  log "Rendering the overview pyramid..."
  # with the annotations, like the path store (the tags were read without them: markup isn't equipment)
  let baked = getTempDir() / ("kks-import-" & $getCurrentProcessId() & "-baked.pdf")
  if bakeAnnots(src, baked) > 0:
    doc.close()
    doc = rotatedCopy(baked, rot)
  removeFile(baked)
  let (pw, ph) = doc.pageSize
  let z = min(2.0, OverviewMax / max(float(pw), float(ph)))
  var levels = 0
  var w0, h0 = 0
  var scale = z
  while true:
    let pix = doc.renderRgb(scale)
    if levels == 0:
      w0 = pix.w
      h0 = pix.h
    writeAtomic(dataDir / "sheets" / (sid & ".o" & $levels & ".jxl"), encodeLossless(pix.data, pix.w, pix.h, 3, effort))
    inc levels
    if max(pix.w, pix.h) <= ThumbMax: break
    scale /= 2
  doc.close()
  copyFile(src, dataDir / "sheets" / (sid & ".pdf.tmp"))
  moveFile(dataDir / "sheets" / (sid & ".pdf.tmp"), dataDir / "sheets" / (sid & ".pdf"))
  # remove pyramid levels a previous import of this id left behind
  var k = levels
  while fileExists(dataDir / "sheets" / (sid & ".o" & $k & ".jxl")):
    removeFile(dataDir / "sheets" / (sid & ".o" & $k & ".jxl"))
    inc k

  # sheets.json and tags.json: bbox in level-0 pixels, as in v1
  var noteArr = newArr()
  for n in notes:
    let t = n.strip
    if t.len > 0: noteArr.elems.add newStr(t)
  if keepTags and old.get("notes") != nil: noteArr = old["notes"]   # the sheet's notes as they are
  let entry = newObj(@[("id", newStr(sid)), ("name", if keepTags: old["name"] else: newStr(name)), ("rot", newInt(rot)), ("w", newInt(w0)),
                       ("h", newInt(h0)), ("scale", newFloat(z)), ("levels", newInt(levels)), ("notes", noteArr)])
  var linkArr = newArr()    # off-page connectors: the same label on another sheet is where the line continues
  for c in links:
    var bb = newArr()
    for v in c.bbox: bb.elems.add newFloat(pyRoundTo(v * z, 1))
    linkArr.elems.add newObj(@[("label", newStr(c.label)), ("bbox", bb), ("conf", newFloat(c.conf))])
  entry["links"] = linkArr
  var newSheets = newArr()
  var placed = false
  for s in sheets.elems:                 # a re-made sheet keeps its place (the apps list sheets in this order)
    if s["id"].s != sid: newSheets.elems.add s
    elif not placed:
      newSheets.elems.add entry
      placed = true
  if not placed: newSheets.elems.add entry
  var newTags = newArr()
  for t in tags.elems:
    if t["sheet"].s != sid or keepTags: newTags.elems.add t
  var nAuto, nReview = 0
  for t in found:
    if t.status == "ignore": continue
    if t.status == "auto": inc nAuto else: inc nReview
    var bb = newArr()
    for v in t.bbox: bb.elems.add newFloat(pyRoundTo(v * z, 1))
    let it = t.interp
    newTags.elems.add newObj(@[
      ("id", newStr(sid & ":" & t.id)), ("sheet", newStr(sid)),
      ("kks", if it.hasKks: newStr(it.kks) else: newNull()), ("suffix", newStr(it.suffix)),
      ("isa", if it.hasIsa and not it.isaNull: newStr(it.isa) else: newNull()),
      ("kind", newStr(it.kind)), ("status", newStr(t.status)), ("conf", newFloat(t.conf)), ("bbox", bb),
      ("orient", newStr($t.orient)), ("read", newArr(@[newStr(t.top), newStr(t.bottom)])),
      ("note", newStr(it.note)), ("flag", newStr(t.flag)), ("suggestion", newNull())])
  # valve types from the drawn symbols: on this sheet's valve tags, a fresh "symbol" field or none
  let vs = annotate(newTags, sid, drawing, z, legend)
  if not vs.hasLegend: log "Valve types: no HRSG legend on this sheet, so no types (" & $vs.valves & " valve tags)."
  else: log "Valve types: " & $vs.typed & " of " & $vs.valves & " valve tags linked to their symbol and typed."
  writeAtomic(tagsPath, toText(newTags))
  writeAtomic(sheetsPath, toText(newSheets))
  log "Done: \"" & name & "\" added: " & $nAuto & " tags auto-read, " & $nReview & " in the review queue, " & $links.len & " connectors (" &
      formatFloat(epochTime() - t0, ffDecimal, 1) & " s)."
  log "RESULT " & toText(newObj(@[("id", newStr(sid)), ("name", newStr(name)), ("auto", newInt(nAuto)),
                                  ("review", newInt(nReview)), ("rotation", newInt(rot)), ("w", newInt(w0)),
                                  ("h", newInt(h0)), ("notes", newInt(noteArr.elems.len)), ("links", newInt(links.len)),
                                  ("reader", newStr(if keepTags: "none" elif textMode: "text" else: "glyphs"))]))

# Out of memory: one plain line and exit code 3 (the server explains its import_memory_mb limit when it sees that
# code). Nim's own allocator calls the hook; MuPDF reports a failed allocation as an error.
const ExitOutOfMemory = 3
var oomLine: cstring       # made before it is needed: the hook can't allocate
when defined(linux):
  type RLim {.importc: "struct rlimit", header: "<sys/resource.h>".} = object
    rlim_cur, rlim_max: uint64
  proc getrlimit(resource: cint, r: var RLim): cint {.importc, header: "<sys/resource.h>".}
  var RLIMIT_AS {.importc, header: "<sys/resource.h>".}: cint
  var RLIM_INFINITY {.importc, header: "<sys/resource.h>".}: uint64
proc limitText(): string =
  when defined(linux):
    var r: RLim
    if getrlimit(RLIMIT_AS, r) == 0 and r.rlim_cur != RLIM_INFINITY:
      return " (its address-space limit is " & $(r.rlim_cur div (1024 * 1024)) & " MB)"
  ""
let oomText = "The importer ran out of memory" & limitText() & ": the import stopped.\n"
oomLine = cstring(oomText)
proc c_write(fd: cint, buf: cstring, n: csize_t): int {.importc: "write", header: "<unistd.h>".}
proc c_exit(code: cint) {.importc: "_exit", header: "<unistd.h>", noreturn.}
proc onOutOfMemory() {.nimcall, tags: [], gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    discard c_write(2, oomLine, csize_t(oomLine.len))
  c_exit(ExitOutOfMemory)
outOfMemHook = onOutOfMemory

try:
  main()
except MupdfError as e:
  # "... failed (overflow)" is a size a crafted file asked for, not memory running out
  if ("malloc (" in e.msg or "calloc (" in e.msg or "realloc (" in e.msg) and "(overflow)" notin e.msg:
    stderr.write $oomLine
    stderr.writeLine "  (MuPDF: " & e.msg & ")"
    quit ExitOutOfMemory
  raise
except JxlOutOfMemory as e:
  stderr.write $oomLine
  stderr.writeLine "  (" & e.msg & ")"
  quit ExitOutOfMemory
