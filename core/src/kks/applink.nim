## Links from other apps into Walkdown (docs/PLANT3D.md §6 "Links into Walkdown", decision 0057):
## `walkdown://kks/<code>` and `walkdown://course/<course>[/<page>]`. Every link is untrusted input: it is read
## strictly, and anything that is not exactly one of these forms reads as nothing (kind ""), so the app does nothing.
## A link only ever names a code or a course page; what the app does with it is to show that, never more.
## Used by the desktop apps directly and by Android through `/native/link` (android/nim/kks_jni.nim).

import model

const
  LinkScheme* = "walkdown"
  MaxLinkLen* = 128            ## longer links are not read at all (the longest valid one is 83 characters)

type AppLink* = object
  kind*: string                ## "kks", "course", or "" (not a link Walkdown opens)
  code*: string                ## kks: [0-9A-Z]{4,24}
  course*, page*: string       ## course: identifiers as in COURSES.md §1; page "" = where the learner left off

proc isCode*(s: string): bool =
  ## a code in a link, as in course links (COURSES.md §3): [0-9A-Z]{4,24}
  if s.len < 4 or s.len > 24: return false
  for c in s:
    if c notin {'0'..'9', 'A'..'Z'}: return false
  true

proc isIdent*(s: string): bool =
  ## a course or page identifier (COURSES.md §1): [a-z_][a-z0-9_]{0,31}
  if s.len < 1 or s.len > 32 or s[0] notin {'a'..'z', '_'}: return false
  for c in s:
    if c notin {'a'..'z', '0'..'9', '_'}: return false
  true

proc parseAppLink*(s: string): AppLink =
  ## The link `s` as given (no trimming, no decoding). The scheme is read case-insensitively (RFC 3986 §3.1), the
  ## rest exactly: no query, fragment, percent-encoding, empty or extra path segment, user or port.
  const prefix = LinkScheme & "://"
  if s.len > MaxLinkLen or s.len <= prefix.len: return
  for i in 0 ..< prefix.len:
    var c = s[i]
    if c in {'A'..'Z'}: c = char(ord(c) + 32)
    if c != prefix[i]: return
  var parts: seq[string] = @[""]
  for c in s[prefix.len .. ^1]:
    if c == '/': parts.add ""
    else: parts[^1].add c
  if parts.len == 2 and parts[0] == "kks" and isCode(parts[1]):
    return AppLink(kind: "kks", code: parts[1])
  if parts.len in 2..3 and parts[0] == "course" and isIdent(parts[1]) and (parts.len == 2 or isIdent(parts[2])):
    return AppLink(kind: "course", course: parts[1], page: (if parts.len == 3: parts[2] else: ""))

proc findCode*(m: Model, code: string): (bool, Tag) =
  ## the tag a code link opens: the first, in the drawings' order, whose code with its suffix is `code`; else the first
  ## whose code without the suffix is (a link to 11HAD70CT101 finds the tag printed 11HAD70CT101R). Unread tags never.
  if code.len == 0: return
  for t in m.tags:
    if t.full == code: return (true, t)
  for t in m.tags:
    if t.kks == code: return (true, t)
