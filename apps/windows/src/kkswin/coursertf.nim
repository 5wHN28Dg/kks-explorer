## The courses' text as RTF for the Windows app's read-only RichEdit controls (learn.nim): runs (docs/COURSES.md §3),
## blocks (§4), a worked example's steps and a scenario's panel of readings. Every course string is escaped (`\`,
## `{`, `}`, non-ASCII as \uN). Nothing of Windows here, so tests/test_coursertf.nim checks what it writes.

import std/[strutils, sets, unicode]
import kks/json

proc plainRun(r: JNode): string =
  for x in r.elems:
    if x.kind == jStr: result.add x.s
    elif x.get("num") != nil: result.add x["num"].s
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
    elif x.get("num") != nil: f.rtf.add "{\\f1 " & rtfEsc(x["num"].s) & "}"     # the mono face at the text's own size (at 10 pt in 11 pt text a capital V stood as low as a small letter)
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
