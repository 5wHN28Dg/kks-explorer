## A course's inline text (a run, docs/COURSES.md §3) as Pango markup: every course string is escaped; links carry our
## own URIs (page:, course:, kks:) or https. No widgets here, so tests/test_coursetext.nim lays the markup out.

import kks/json
import nobreak

proc esc(s: string): string =
  for c in s:
    case c
    of '&': result.add "&amp;"
    of '<': result.add "&lt;"
    of '>': result.add "&gt;"
    of '"': result.add "&quot;"
    of '\'': result.add "&#39;"
    else: result.add c

proc linkUri*(to: JNode): string =
  if to.get("url") != nil: return to["url"].s
  if to.get("kks") != nil: return "kks:" & to["kks"].s
  if to.get("course") != nil:
    return "course:" & to["course"].s & (if to.get("page") != nil: "#" & to["page"].s else: "")
  "page:" & to["page"].s

proc markup*(r: JNode): string =
  for x in r.elems:
    if x.kind == jStr: result.add esc(x.s)
    elif x.get("b") != nil: result.add "<b>" & markup(x["b"]) & "</b>"
    elif x.get("i") != nil: result.add "<i>" & markup(x["i"]) & "</i>"
    elif x.get("small") != nil: result.add "<small>" & markup(x["small"]) & "</small>"
    # a number with its unit: the mono face, and on one line (nobreak.nim says how, and what a long run does)
    elif x.get("num") != nil: result.add "<span font_family=\"JetBrains Mono, monospace\">" & esc(unbroken(x["num"].s)) & "</span>"
    elif x.get("term") != nil: result.add "<u>" & markup(x["term"]) & "</u>"
    elif x.get("link") != nil: result.add "<a href=\"" & esc(linkUri(x["to"])) & "\">" & markup(x["link"]) & "</a>"
