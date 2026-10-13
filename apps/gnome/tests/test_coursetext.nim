## A course's `num` run stays on one line (docs/COURSES.md §3; apps/common/nobreak.nim): the rule itself, and the
## markup the GNOME app makes of a run, laid out by Pango at every width the way a course label wraps it.
import std/[unittest, strutils, unicode]
import kks/json
import kksg/coursetext
import nobreak

const HP = "<pango/pangocairo.h>"
type P = pointer
proc pango_cairo_font_map_get_default(): P {.importc, header: HP.}
proc pango_font_map_create_context(m: P): P {.importc, header: HP.}
proc pango_layout_new(ctx: P): P {.importc, header: HP.}
proc pango_layout_set_markup(l: P, s: cstring, n: cint) {.importc, header: HP.}
proc pango_layout_set_width(l: P, w: cint) {.importc, header: HP.}
proc pango_layout_set_wrap(l: P, mode: cint) {.importc, header: HP.}
proc pango_layout_get_text(l: P): cstring {.importc, header: HP.}
proc pango_layout_get_line_count(l: P): cint {.importc, header: HP.}
proc pango_layout_get_pixel_size(l: P, w, h: ptr cint) {.importc, header: HP.}
proc pango_layout_get_line_readonly(l: P, i: cint): P {.importc, header: HP.}
proc lineStart(line: P): cint {.importc: "KKS_LINE_START", header: HP.}
{.emit: "#define KKS_LINE_START(l) (((PangoLayoutLine *)(l))->start_index)".}
proc g_object_unref(o: P) {.importc, header: HP.}
const PANGO_WRAP_WORD_CHAR = 2.cint       # what a course label uses (learn.nim `rl`)

proc lines(markupText: string, px: int): tuple[text: string, starts: seq[int], width: int] =
  ## where each line starts (byte offsets into the laid-out text) at this width, and how wide the result is
  let ctx = pango_font_map_create_context(pango_cairo_font_map_get_default())
  let l = pango_layout_new(ctx)
  pango_layout_set_wrap(l, PANGO_WRAP_WORD_CHAR)
  pango_layout_set_width(l, cint(px * 1024))
  pango_layout_set_markup(l, markupText.cstring, -1)
  result.text = $pango_layout_get_text(l)
  for i in 0 ..< pango_layout_get_line_count(l):
    result.starts.add int(lineStart(pango_layout_get_line_readonly(l, i)))
  var w, h: cint
  pango_layout_get_pixel_size(l, addr w, addr h)
  result.width = int(w)
  g_object_unref(l)
  g_object_unref(ctx)

proc run(parts: varargs[string]): JNode =
  ## a run: plain strings, and "#…" for a num
  result = newArr()
  for p in parts:
    result.elems.add (if p.startsWith("#"): newObj(@[("num", newStr(p[1 .. ^1]))]) else: newStr(p))

proc show(s: string): string = s.replace(Nbsp, "~").replace(WordJoiner, "|")

suite "a num run stays on one line":
  test "the rule: a short run whole, a long one only number with unit, never after a dash or a slash":
    check show(unbroken("0.385 Ω per °C")) == "0.385~Ω~per~°C"
    check show(unbroken("4–20 mA")) == "4–|20~mA"
    check show(unbroken("kg/s = t/h ÷ 3.6")) == "kg/|s~=~t/|h~÷~3.6"
    check show(unbroken("pk-pk = 2 × pk")) == "pk-|pk~=~2~×~pk"
    check show(unbroken("−250")) == "−250"
    check show(unbroken("12.44 MPa.a")) == "12.44~MPa.a"
    check "rpm = f × 60 ÷ teeth".runeLen == WholeRun
    check show(unbroken("rpm = f × 60 ÷ teeth")) == "rpm~=~f~×~60~÷~teeth"
    # longer than that: a formula or a phrase
    check show(unbroken("V at transmitter = supply − I × R")) == "V at transmitter = supply − I × R"
    check show(unbroken("1 mm per metre per 100 K")) == "1~mm per metre per 100~K"
    check show(unbroken("12 µm per metre per °C")) == "12~µm per metre per °C"
    check show(unbroken("flow % = 100 × √(DP % ÷ 100)")) == "flow~% = 100 × √(DP~% ÷ 100)"
    check show(unbroken("0.04 + 0.02 = 0.06 mA")) == "0.04 + 0.02 = 0.06~mA"
    check show(unbroken("41.4–50.6 mm²/s is the band here")) == "41.4–|50.6~mm²/|s is the band here"
    check unbroken("") == ""

  test "laid out: no line starts inside a short run, at any width it fits":
    for num in ["0.385 Ω per °C", "4–20 mA", "kg/s = t/h ÷ 3.6", "12.44 MPa.a", "pk-pk = 2 × pk"]:
      let m = markup(run("A platinum RTD changes by about ", "#" & num, " near room temperature, which a bridge circuit reads."))
      let alone = lines(markup(run("#" & num)), 4000).width
      var broke = 0
      for px in countup(alone + 2, 900, 3):
        let (text, starts, _) = lines(m, px)
        let a = text.find(unbroken(num))
        check a > 0
        for st in starts:
          if st > a and st < a + unbroken(num).len: inc broke
      check broke == 0
    # (what this guards: with the run's text as written, some widths put the unit on the next line)
    let plainM = "A platinum RTD changes by about <span font_family=\"JetBrains Mono, monospace\">0.385 Ω per °C</span> near room temperature."
    var broke = 0
    for px in countup(140, 900, 3):
      let (text, starts, _) = lines(plainM, px)
      let a = text.find("0.385")
      for st in starts:
        if st > a and st < a + "0.385 Ω per °C".len: inc broke
    check broke > 0

  test "a long run wraps at its spaces, but a number keeps its unit":
    let num = "1 mm per metre per 100 K"
    let m = markup(run("Steel grows by about ", "#" & num, " of warming."))
    var inside = 0
    for px in countup(60, 600, 3):
      let (text, starts, _) = lines(m, px)
      let u = unbroken(num)
      let a = text.find(u)
      for st in starts:
        if st > a and st < a + u.len:
          inc inside
          # never between "1" and "mm", nor between "100" and "K" (while those fit)
          if px > 90: check text[st ..< min(text.len, st + 2)] notin ["mm", "K "]
    check inside > 0

  test "a run wider than its cell is broken where the line fills up: nothing overflows":
    let m = markup(run("#0.385 Ω per °C"))
    let alone = lines(m, 4000).width
    let (_, starts, width) = lines(m, alone div 2)
    check starts.len > 1
    check width <= alone div 2 + 2
