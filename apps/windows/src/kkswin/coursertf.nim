## The courses' text as RTF for the Windows app's read-only RichEdit controls (learn.nim): runs (docs/COURSES.md §3),
## blocks (§4), a worked example's steps and a scenario's panel of readings. Every course string is escaped (`\`,
## `{`, `}`, non-ASCII as \uN). Nothing of Windows here, so tests/test_coursertf.nim checks what it writes.

import std/[strutils, sets, unicode]
import kks/json
import nobreak

proc rtfEsc*(s: string): string

# A `num` run stays on one line with its unit (§3; apps/common/nobreak.nim says which of its spaces may wrap).
# RichEdit has no unbreakable span, and measured in Windows 11's (2026-10-13) it breaks a line in more places than
# after a space: after ° or % before a letter ("200 °" / "C"), after a hyphen or dash before a letter, before a
# superscript minus; and without advanced typography (ui.nim `rich` turns it on) between a digit and a no-break
# space. A word joiner (U+2060) or U+FEFF does not help: a line ends before either, and U+2060 is drawn a character
# wide in Consolas. What does hold two characters together is a no-break space between them, so where a break could
# come it is one of 1 pt: a pixel wide, nothing to see. The text copied out of the control has a no-break space
# there ("200 °C" is 200, nbsp, °, nbsp, C).
const
  NoBreakSpace = "\\~"
  Joiner = "{\\fs2\\~}"

proc isDigit(r: Rune): bool = r.int32 >= ord('0') and r.int32 <= ord('9')
proc isWord(r: Rune): bool =
  ## a letter (Latin, Greek, Cyrillic: a line may end between two ideographs), a digit, or a raised 2 or 3 (m³, mm²)
  (r.int32 < 0x500 and r.isAlpha) or r.isDigit or r.int32 in [0xB2'i32, 0xB3]

proc sticks(a, b: Rune): bool =
  ## RichEdit never ends a line between these two. Only pairs that were measured (tests/test_courserich.nim lays
  ## out every number of the courses at every width); anything else gets a joiner.
  let (x, y) = (a.int32, b.int32)
  if b.isCombining: return true                                           # a mark stays on its letter
  if a.isWord and b.isWord: return true                                   # 100K, 20mA, µm
  if a.isDigit and y in [int32(ord('.')), ord(','), ord('%')]: return true
  if x in [int32(ord('.')), ord(',')] and b.isDigit: return true          # 0.385
  if (a.isWord and y == ord('.')) or (x == ord('.') and b.isWord): return true        # MPa.a, 11MBY10CS901.XQ01
  if (a.isWord and y == ord('/')) or (x == ord('/') and b.isWord): return true        # kg/s, 1/2
  if x in [int32(ord('-')), 0x2013] and b.isDigit: return true                        # 4–20
  if a.isWord and y in [int32(ord('-')), 0x2013]: return true                         # pk-pk (the joiner follows the hyphen)
  (x == ord('(') and b.isWord) or (a.isWord and y == ord(')'))                        # (mA − 4)

proc numRun*(s: string, rtf = true): string =
  ## a num run's text as RTF, or (`rtf = false`) as the control then holds it: what a search in the control finds
  var rs: seq[Rune]
  for r in unbroken(s).runes:
    if r != Rune(0x2060): rs.add r             # the rule's word joiners: the pairs above and the joiner do that here
  proc space(r: Rune): bool = r == Rune(32) or r == Rune(0xA0) or r == Rune(10)
  for i, r in rs:
    if r == Rune(0xA0): result.add (if rtf: NoBreakSpace else: Nbsp)
    else: result.add (if rtf: rtfEsc($r) else: $r)
    if i + 1 < rs.len and not space(r) and not space(rs[i + 1]) and not sticks(r, rs[i + 1]):
      result.add (if rtf: Joiner else: Nbsp)

proc plainRun(r: JNode): string =
  ## a run as the control holds it (a link is found by its text)
  for x in r.elems:
    if x.kind == jStr: result.add x.s
    elif x.get("num") != nil: result.add numRun(x["num"].s, rtf = false)
    else:
      for k in ["b", "i", "small", "term", "link"]:
        if x.get(k) != nil: result.add plainRun(x[k])

const RtfHead* = "{\\rtf1\\ansi\\deff0{\\fonttbl{\\f0\\fswiss Segoe UI;}{\\f1\\fmodern Consolas;}}" &
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

proc linkTarget*(to: JNode): string =
  if to.get("url") != nil: return to["url"].s
  if to.get("kks") != nil: return "kks:" & to["kks"].s
  if to.get("course") != nil:
    return "course:" & to["course"].s & (if to.get("page") != nil: "#" & to["page"].s else: "")
  "page:" & to["page"].s

type Flow* = object
  rtf*: string
  links*: seq[(string, string)]   ## (the link's text, its target), in reading order

proc runRtf*(f: var Flow, r: JNode) =
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
    elif x.get("num") != nil: f.rtf.add "{\\f1 " & numRun(x["num"].s) & "}"     # the mono face at the text's own size (at 10 pt in 11 pt text a capital V stood as low as a small letter)
    elif x.get("term") != nil:
      f.rtf.add "{\\ul "
      f.runRtf(x["term"])
      f.rtf.add "}"
    elif x.get("link") != nil:
      f.links.add (plainRun(x["link"]), linkTarget(x["to"]))
      f.rtf.add "{\\cf2 "
      f.runRtf(x["link"])
      f.rtf.add "}"

proc para*(f: var Flow, r: JNode, fmt = "\\sa120") =
  f.rtf.add "\\pard" & fmt & " "
  f.runRtf(r)
  f.rtf.add "\\par\n"

proc rowRtf*(f: var Flow, cells: seq[JNode], n, w: int, num: HashSet[int], head: bool) =
  f.rtf.add "\\trowd\\trgaph100\\trleft0"
  for i in 0 ..< n: f.rtf.add "\\clbrdrb\\brdrs\\brdrw10\\cellx" & $(w * (i + 1))
  f.rtf.add "\n"
  for i, c in cells:
    # (A number column's cell is not kept on one line as the other apps do it: the columns here are of one fixed
    # width, so a cell that fits is on one line already, and one that does not would be cut where the column is full.)
    f.rtf.add "\\pard\\intbl" & (if i in num and not head: "\\qr" else: "") & (if head: "{\\b\\cf3 " else: "{")
    f.runRtf(c)
    f.rtf.add "}\\cell "
  f.rtf.add "\\row\n"

proc tableRtf*(f: var Flow, t: JNode) =
  let n = max(1, t["head"].len)
  let w = 9600 div n
  var num: HashSet[int]
  for i in t["num"].elems: num.incl int(i.num)
  f.rowRtf(t["head"].elems, n, w, num, true)
  for r in t["rows"].elems: f.rowRtf(r.elems, n, w, num, false)
  f.rtf.add "\\pard\\sa120\\par\n"

proc blockRtf*(f: var Flow, b: JNode) =
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

proc workedRtf*(f: var Flow, worked: JNode, shown: int) =
  ## a worked example: its case in bold, then the first `shown` steps, each under its small heading. The bold is a
  ## group of its own: as a paragraph format ("\\pard\\sa80\\b") it stayed on, and every step's text was bold too
  ## (found 2026-10-13).
  f.rtf.add "\\pard\\sa80{\\b "
  f.runRtf(worked["case"])
  f.rtf.add "}\\par\n"
  for k in 0 ..< min(shown, worked["steps"].len):
    let s = worked["steps"][k]
    f.rtf.add "\\pard\\sa20{\\fs19\\cf3 Step " & $(k + 1) & " \\u183? "
    f.runRtf(s[0])
    f.rtf.add "}\\par\n"
    f.para(s[1])

proc panelRtf*(f: var Flow, panel: JNode) =
  ## a scenario's readings: the names in one column and the values in the next, at a tab stop wider than the longest
  ## name (with a bare tab each value started wherever its name ended)
  var longest = 0
  for r in panel.elems: longest = max(longest, plainRun(r["name"]).runeLen)
  let stop = 200 + min(6000, 600 + longest * 130)      # twips: about 6.5 pt for a character of the 11 pt face
  for r in panel.elems:
    f.rtf.add "\\pard\\li200\\sa20\\tx" & $stop & "{\\cf3 "
    f.runRtf(r["name"])
    f.rtf.add "}\\tab {\\f1\\b" & (case r["state"].s
      of "alarm": "\\cf6"
      of "act": "\\cf4"
      of "ok": "\\cf5"
      else: "") & " "
    f.runRtf(r["value"])
    f.rtf.add "}\\par\n"

# ---------------------------------------------------------------- lines that are not RTF (learn.nim's labels)

proc questionHeading*(label, typ, src: string): string =
  ## the small line over a question, as written: upper-cased it read "Q7 · 4 · 4–20 MA" (found 2026-10-13)
  (if label.len > 0: label elif typ == "scenario": "Scenario" elif typ == "order": "Put in order" else: "Practice") &
    (if src.len > 0: "   " & src else: "")

proc testResult*(score, answered, total: int): string =
  ## a test's Result line, in the GNOME app's words (apps/gnome/src/kksg/learn.nim testPage): untouched it says how
  ## many questions there are (it said "0 / 0 right"), then how many of the answered ones were right
  if answered == 0: "0 / " & $total & " answered"
  else: $score & " / " & $answered & " right" & (if answered == total: " · finished" else: "")
