## A course's `num` run ("12.44 MPa.a": a number with its unit, docs/COURSES.md §3) is kept on one line. The web
## does it with `white-space: nowrap`; the native renderers' text engines have no such span that still lets a run
## too long for its line break somewhere, so the run's own characters say where it must not break (the user,
## 2026-10-13: "0.385" stood at the end of one line and "Ω per °C" at the start of the next):
## - a run of up to `WholeRun` characters stays whole: every space in it becomes a no-break space;
## - a longer one is a formula or a phrase ("V at transmitter = supply − I × R"): kept whole it would leave half a
##   line empty on a phone, or not fit at all. Only a number stays with the unit after it ("100 K", "12 µm",
##   "DP %"); it may wrap at its other spaces;
## - never after a hyphen, a dash or a slash inside a run ("4–20 mA", "kg/s", "pk-pk"): a word joiner follows it.
## A run still wider than its line or table cell is broken by the text engine wherever it fills up, as any word too
## long for its line is: nothing overflows.

import std/unicode

const
  WholeRun* = 20            ## characters
  Nbsp* = " "
  WordJoiner* = "⁠"

proc unitStart(r: Rune): bool = r.isAlpha or r == Rune(0xB0) or r == Rune(ord('%'))     # a letter (µ, Ω too), ° or %

proc isDigit(r: Rune): bool = r.int32 >= ord('0') and r.int32 <= ord('9')

proc breaksAfter(r: Rune): bool =
  ## the characters of a run a line may end after (UAX #14: hyphens and dashes, the slash before a letter)
  r.int32 in [int32(ord('-')), 0x2010, 0x2012, 0x2013, 0x2014, int32(ord('/'))]

proc unbroken*(s: string): string =
  ## `s` (a num run's text) with its spaces and joins made unbreakable as the rules above say
  let rs = s.toRunes
  let whole = rs.len <= WholeRun
  for i, r in rs:
    let next = if i + 1 < rs.len: rs[i + 1] else: Rune(0)
    if r == Rune(ord(' ')):
      let prev = if i > 0: rs[i - 1] else: Rune(0)
      if whole or next == Rune(ord('%')) or (prev.isDigit and next.unitStart): result.add Nbsp
      else: result.add ' '
    else:
      if r == Rune(0x2014) and i > 0 and rs[i - 1] != Rune(ord(' ')): result.add WordJoiner    # (an em dash: before it too)
      result.add r.toUTF8
      if r.breaksAfter and i + 1 < rs.len and next != Rune(ord(' ')): result.add WordJoiner
