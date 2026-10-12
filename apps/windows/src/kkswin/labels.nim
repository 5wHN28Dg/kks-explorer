## The text of a Win32 button (push button, check box, radio button). In a button's text "&" marks the next letter as
## its Alt shortcut and is not drawn: "5 · Strain gauges & RTDs" showed as "5 · Strain gauges  RTDs" with Alt+R
## pressing it (found 2026-10-13 in the fourth course). The app has no such shortcuts, so every "&" in a button's text
## is meant as the character and is doubled.
import std/strutils

proc buttonLabel*(text: string): string =
  ## `text` as the window text of a button that shows it literally
  text.replace("&", "&&")
