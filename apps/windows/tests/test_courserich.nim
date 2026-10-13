## What RichEdit does with the courses' RTF (coursertf.nim) in the control the app makes for it (ui.nim `rich`):
## a number stays on one line with its unit, the minus sign is the run's own font's, a link is found, and a run too
## long for its table cell is broken, not cut off. Measured in the real control: where each character stands
## (EM_POSFROMCHAR) at many widths, and the font each has (EM_GETCHARFORMAT).
## Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it); runs on Windows:
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_courserich.exe apps/windows/tests/test_courserich.nim
import std/[unittest, strutils, unicode, sets, sequtils]
import kks/json
import kkswin/[w32, ui, coursertf]

const
  H = "<windows.h>"
  RH = "<richedit.h>"
type
  POINTL {.importc, header: H.} = object
    x, y: int32
  CHARRANGE {.importc, header: RH.} = object
    cpMin, cpMax: int32
  TEXTRANGEW {.importc, header: RH.} = object
    chrg: CHARRANGE
    lpstrText: pointer
  GETTEXTLENGTHEX {.importc, header: RH.} = object
    flags, codepage: uint32
  CHARFORMAT2W {.importc, header: RH.} = object
    cbSize, dwMask, dwEffects: uint32
    szFaceName: array[32, uint16]
  HDC = pointer
var
  EM_EXSETSEL {.importc, header: RH, nodecl.}: UINT
  EM_GETCHARFORMAT {.importc, header: RH, nodecl.}: UINT
  EM_POSFROMCHAR {.importc, header: RH, nodecl.}: UINT
  EM_GETTEXTRANGE {.importc, header: RH, nodecl.}: UINT
  EM_GETTEXTLENGTHEX {.importc, header: RH, nodecl.}: UINT
  SCF_SELECTION {.importc, header: RH, nodecl.}: WPARAM
  CFE_LINK {.importc, header: RH, nodecl.}: uint32
proc GetDC(h: HWND): HDC {.importc, stdcall, header: H.}
proc ReleaseDC(h: HWND, dc: HDC): int32 {.importc, stdcall, header: H, discardable.}
proc CreateFontW(h, w, esc, orient, weight: int32, italic, underline, strike, charset, outPrec, clipPrec, quality,
                 pitch: uint32, face: WideCString): pointer {.importc, stdcall, header: H.}
proc SelectObject(dc: HDC, o: pointer): pointer {.importc, stdcall, header: H, discardable.}
proc DeleteObject(o: pointer): int32 {.importc, stdcall, header: H, discardable.}
proc GetGlyphIndicesW(dc: HDC, s: WideCString, n: int32, glyphs: ptr uint16, flags: uint32): uint32 {.importc, stdcall, header: H.}

hinst = GetModuleHandleW(nil)
makeFonts(96)
let main = CreateWindowExW(0, newWideCString("STATIC"), newWideCString("rich test"), WS_OVERLAPPEDWINDOW, 0, 0, 900, 700,
                           nil, nil, hinst, nil)
doAssert main != nil
let page = newPage(main)
const Tall = 30000       # the control is as tall as its text at any width: all of it is laid out

type Rich = object
  h: HWND
  text: seq[uint16]

proc show(rtf: string, links: seq[(string, string)] = @[]): Rich =
  ## the text in the app's control (ui.nim `rich`), as the course window makes it
  page.clear()
  result.h = page.rich(RtfHead & rtf & "}", links)
  MoveWindow(result.h, 0, 0, 700, Tall, 0)
  var gl = GETTEXTLENGTHEX(flags: 0, codepage: 1200)
  let n = int(SendMessageW(result.h, EM_GETTEXTLENGTHEX, cast[WPARAM](addr gl), 0))
  result.text = newSeq[uint16](n + 2)
  var tr = TEXTRANGEW(chrg: CHARRANGE(cpMin: 0, cpMax: int32(n)), lpstrText: addr result.text[0])
  SendMessageW(result.h, EM_GETTEXTRANGE, 0, cast[LPARAM](addr tr))
  result.text.setLen(n)

proc utf16(s: string): seq[uint16] =
  for r in s.runes:
    doAssert r.int32 < 0x10000
    result.add uint16(r.int32)

proc find(r: Rich, s: string, start = 0): int =
  ## where `s` stands in the control's text, from `start`; -1 when it does not
  let w = utf16(s)
  for i in start .. r.text.len - w.len:
    if r.text[i ..< i + w.len] == w: return i
  -1

proc pos(r: Rich, i: int): (int, int) =
  var p: POINTL
  SendMessageW(r.h, EM_POSFROMCHAR, cast[WPARAM](addr p), i)
  (int(p.x), int(p.y))

proc format(r: Rich, i: int): (string, uint32) =
  ## the font's name and the effects of character i
  var cr = CHARRANGE(cpMin: int32(i), cpMax: int32(i + 1))
  SendMessageW(r.h, EM_EXSETSEL, 0, cast[LPARAM](addr cr))
  var cf: CHARFORMAT2W
  zeroMem(addr cf, sizeof(cf))
  cf.cbSize = uint32(sizeof(cf))
  SendMessageW(r.h, EM_GETCHARFORMAT, SCF_SELECTION, cast[LPARAM](addr cf))
  for u in cf.szFaceName:
    if u == 0: break
    result[0].add char(u)
  result[1] = cf.dwEffects

proc pieces(num: string): seq[string] =
  ## what of a num run must stand on one line: the control's text of it, cut at the spaces a line may end at
  numRun(num, rtf = false).split(' ')

proc brokenAt(r: Rich, at: int, piece: string): string =
  ## "" when the piece at `at` stands on one line, else where it is broken
  let w = utf16(piece)
  let y = r.pos(at)[1]
  for k in 1 ..< w.len:
    if r.pos(at + k)[1] != y:
      return $Rune(w[k - 1]) & " | " & $Rune(w[k]) & " (U+" & toHex(int(w[k - 1]), 4) & ", U+" & toHex(int(w[k]), 4) & ")"

proc paragraphs(nums: seq[string]): string =
  for n in nums:
    var f = Flow()
    f.para(parseStrict("""["Some filler words in front of it, and a few more of them here, ", {"num": """ & toText(newStr(n)) &
                       """}, " then the words after it that fill the line up to its end."]"""))
    result.add f.rtf

proc wrapsOnlyAtItsSpaces(nums: seq[string], widths: Slice[int]): seq[string] =
  ## every num run in a paragraph of its own, at every width: the breaks found inside what must stay whole
  let r = show(paragraphs(nums))
  var at: seq[(int, string)]
  var from0 = 0
  for n in nums:
    for p in pieces(n):
      let i = r.find(p, from0)
      doAssert i >= 0, "not in the control: " & p
      at.add (i, p)
      from0 = i + p.runeLen
  var seen: HashSet[string]
  for w in countdown(widths.b, widths.a, 2):
    MoveWindow(r.h, 0, 0, int32(w), Tall, 0)
    for (i, p) in at:
      let b = r.brokenAt(i, p)
      if b.len > 0 and not seen.containsOrIncl(p & b): result.add "\"" & p & "\" at " & b & ", " & $w & " px wide"

proc courseNums(): seq[string] =
  ## every num run of the courses that ship
  const docs = [staticRead("../../../data/courses/ppt.json"), staticRead("../../../data/courses/fnd.json"),
                staticRead("../../../data/courses/hrsg.json"), staticRead("../../../data/courses/inc.json")]
  var res: seq[string]
  proc walk(n: JNode) =
    case n.kind
    of jObj:
      if n.get("num") != nil and n["num"].kind == jStr:
        if n["num"].s notin res: res.add n["num"].s
      else:
        for (_, v) in n.fields: walk(v)
    of jArr:
      for v in n.elems: walk(v)
    else: discard
  for d in docs: walk(parseStrict(d))
  res

suite "the courses' text in RichEdit":
  test "a number stays on one line with its unit, at every width":
    # up to 20 characters: whole. It was "0.385" at the end of a line and "Ω per °C" on the next, and "°" / "C"
    let whole = @["0.385 Ω per °C", "4–20 mA", "200 °C", "pk-pk = 2 × pk", "12 × 10⁻⁶ /°C", "A–B", "5 %", "0.1–0.3 MPa/min"]
    check wrapsOnlyAtItsSpaces(whole, 260 .. 700) == newSeq[string]()
    # longer: wraps at its spaces, but a number keeps its unit
    let long = @["V at transmitter = supply − I × R", "1 mm per metre per 100 K", "error % = (measured − ideal) ÷ span × 100"]
    check wrapsOnlyAtItsSpaces(long, 200 .. 700) == newSeq[string]()
    # and it does wrap inside the long ones (or the check above would say nothing)
    let r = show(paragraphs(long))
    var wrapped = false
    for w in countdown(700, 200, 2):
      MoveWindow(r.h, 0, 0, int32(w), Tall, 0)
      let i = r.find("V at transmitter")
      if r.pos(i)[1] != r.pos(i + "V at transmitter = supply − I × ".runeLen)[1]: wrapped = true
    check wrapped

  test "every number of the courses that ship stays whole":
    let nums = courseNums()
    check nums.len > 100
    check wrapsOnlyAtItsSpaces(nums, 300 .. 700) == newSeq[string]()

  test "the minus sign, the arrows and the operators are drawn in their run's own font":
    # RichEdit's font binding took them from Cambria Math: a minus as long as a dash, and wider than Consolas's cell
    var f = Flow()
    f.para(parseStrict("""["The drop is supply − I × R → about √2 ≈ 1.4 ≤ 2 ≥ 1 ↑ ↓, ", {"num": "M−M = supply − I ≈ √2 ≤ 3"}, "."]"""))
    let r = show(f.rtf)
    let numAt = r.find("M−M")
    check numAt > 0
    for i, u in r.text:
      if u in [0x2212'u16, 0x2192, 0x221A, 0x2248, 0x2264, 0x2265, 0x2191, 0x2193]:
        checkpoint "U+" & toHex(int(u), 4) & " at " & $i
        check r.format(i)[0] == (if i >= numAt: "Consolas" else: "Segoe UI")
    # in the mono face the minus is as wide as every other character
    check r.pos(numAt + 2)[0] - r.pos(numAt + 1)[0] == r.pos(numAt + 1)[0] - r.pos(numAt)[0]

  test "Consolas has every character the courses' numbers use":
    # (with no font binding a character Consolas lacks would be an empty box)
    var chars: seq[uint16]
    for n in courseNums():
      for u in utf16(numRun(n, rtf = false)):
        if u > 126 and u notin chars: chars.add u
    check chars.len > 10
    let dc = GetDC(main)
    let font = CreateFontW(-15, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, newWideCString("Consolas"))
    let old = SelectObject(dc, font)
    var glyphs = newSeq[uint16](chars.len + 1)
    chars.add 0
    check GetGlyphIndicesW(dc, cast[WideCString](addr chars[0]), int32(chars.len - 1), addr glyphs[0], 1) == uint32(chars.len - 1)
    for i in 0 ..< chars.len - 1:
      checkpoint "U+" & toHex(int(chars[i]), 4)
      check glyphs[i] != 0xFFFF'u16          # GGI_MARK_NONEXISTING_GLYPHS
    SelectObject(dc, old)
    DeleteObject(font)
    ReleaseDC(main, dc)

  test "a link with a number in it is found":
    var f = Flow()
    f.para(parseStrict("""["See ", {"link": ["the ", {"num": "4–20 mA"}, " loop"], "to": {"page": "ma"}}, " for more."]"""))
    let r = show(f.rtf, f.links)
    let i = r.find("the 4–20")
    check i > 0
    check (r.format(i + 2)[1] and CFE_LINK) != 0 and (r.format(i + 10)[1] and CFE_LINK) != 0
    check (r.format(1)[1] and CFE_LINK) == 0

  test "a run too long for its table cell is broken where the cell is full, not cut off":
    # five columns of 1920 twips (128 px at 96 dpi); the run needs about 180 px
    var f = Flow()
    f.tableRtf(parseStrict("""{"head": ["a", "b", "c", "d", "e"], "num": [], "rows": [["one", [{"num": "12.5 µm per metre"}], "three", "four", "five"]]}""".replace("\"one\"", "[\"one\"]").replace("\"three\", \"four\", \"five\"", "[\"three\"], [\"four\"], [\"five\"]").replace("[\"a\", \"b\", \"c\", \"d\", \"e\"]", "[[\"a\"], [\"b\"], [\"c\"], [\"d\"], [\"e\"]]")))
    let r = show(f.rtf)
    let i = r.find("12.5")
    let n = "12.5 µm per metre".runeLen
    check i > 0
    let left = r.pos(i)[0]
    var ys: HashSet[int]
    for k in 0 ..< n:
      let (x, y) = r.pos(i + k)
      ys.incl y
      check x >= left and x < left + 128        # every character stands inside its cell
    check ys.len == 2                           # on two lines
    check r.pos(r.find("three"))[0] >= left + 120
