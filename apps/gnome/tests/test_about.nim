## The About dialog's content (about.nim): every part the Linux app ships or uses is on the legal page with the
## licence text it asks for, every course photo is credited, and every string AdwAboutDialog reads as markup is
## valid markup that shows the text as written.
import std/[strutils, unittest]
import kks/json
import kksl/buildinfo
import kksg/[gtk, about]

proc pango_parse_markup(markup: cstring, length: cint, accel: uint32, attrs: pointer, text: ptr cstring,
                        accelChar: pointer, error: ptr ptr GError): cint {.importc, header: "<pango/pango.h>".}

proc shown(markup: string): string =
  ## the text a markup label shows; fails the test when the markup does not parse. (GtkLabel takes its links,
  ## <a href="…">, out of the markup before Pango reads the rest: so does this.)
  var m = ""
  var i = 0
  while i < markup.len:
    if markup.continuesWith("<a href=\"", i):
      let q = markup.find('"', i + 9)
      check q > 0 and markup.continuesWith("\">", q)
      i = q + 2
    elif markup.continuesWith("</a>", i): i += 4
    else:
      m.add markup[i]
      inc i
  var t: cstring
  var e: ptr GError
  if pango_parse_markup(m.cstring, -1, 0, nil, addr t, nil, addr e) == 0:
    checkpoint "bad markup: " & (if e != nil: $e.message else: "") & "\n" & markup[0 ..< min(300, markup.len)]
    if e != nil: g_error_free(e)
    fail()
    return ""
  result = $t
  g_free(t)

let d = parseStrict(AboutJson)
let a = about()

proc section(name: string): Legal =
  for l in a.legal:
    if l.title == name or l.title.startsWith(name & " "): return l
  checkpoint "no legal section for " & name
  fail()

suite "about":
  test "the version line, the source link and the main page's strings":
    check a.version == versionLine("").strip
    check a.version.startsWith(Version & " (commit ")
    check a.sourceUrl == SourceUrl
    check a.name == "Walkdown"
    check a.website == d["links"]["homepage"].s and a.issues == d["links"]["issues"].s and a.help == d["links"]["help"].s
    check shown(a.copyright) == "© " & d["developer"].s
    check shown(a.sourceTitle).startsWith("Source")

  test "every part of the Linux app has a legal section with its licence, and only those":
    var n = 0
    for c in d["components"].elems:
      let how = c["platforms"].get("gnome")
      if how == nil:
        for l in a.legal: check not (l.title == c["name"].s or l.title.startsWith(c["name"].s & " "))
        continue
      inc n
      let l = section(c["name"].s)
      let lic = shown(l.license)
      let cr = shown(l.copyright)
      check lic.startsWith("Licence: " & c["license_name"].s)
      # the notice (a copyright line, or the licence file with its copyright) is shown as written
      let notice = if c["notice"].isStr: c["notice"].s.strip(leading = false) else: ""
      if notice.len > 0: check notice in cr or notice in lic
      # and the full text of every licence about.json carries a text for
      for id in c["license_ids"].elems:
        let t = d["licenses"][id.s].get("text")
        if t.isStr: check t.s.strip(leading = false) in lic
      # a part that comes with the app ships its licence: a notice or the licence's text (SQLite's blessing is
      # public domain)
      if how.s == "bundled" and c["license"].s != "blessing":
        var hasText = notice.len > 300 or "\n\n" in notice
        for id in c["license_ids"].elems: hasText = hasText or d["licenses"][id.s].get("text").isStr
        check hasText
      # bundled parts name their version; the system's are whatever version the system has
      if how.s == "bundled" and c["version"].isStr: check c["version"].s in l.title
      if how.s == "system": check "system's copy" in cr
      check l.license.count("<a href=") == c["license_ids"].len
    check n >= 10
    check a.legal.len == n + 1      # and the note saying what they are
    check shown(a.legal[0].copyright) == d["platforms"]["gnome"]["note"].s

  test "the licences that need their text shipped are on the page: the fonts' OFL, the BSD, MIT and zlib notices":
    let ofl = d["licenses"]["OFL-1.1"]["text"].s.strip(leading = false)
    for font in ["Atkinson Hyperlegible", "Barlow Semi Condensed", "JetBrains Mono"]:
      check ofl in shown(section(font).license)
      check "Copyright" in shown(section(font).copyright)
    check "Redistributions in binary form must reproduce" in shown(section("libjxl").license)
    check "Permission is hereby granted" in shown(section("Nim standard library").license)
    check "Jean-loup Gailly" in shown(section("zlib").license)
    check "Apache License" in shown(section("ZXing-C++").license)

  test "every course photo is credited, each with one link at its end":
    check a.photos.len == d["photos"].len
    for i, p in a.photos:
      check '<' notin p and '>' notin p
      let at = p.find("http")
      if at >= 0:
        check p.count("http") == 1
        check ' ' notin p[at .. ^1]
      # the credit's words are kept (a URL inside a credit loses only its scheme)
      check d["photos"][i]["text"].s.multiReplace(("https://", ""), ("http://", "")) in p
    check "Didier Duforest, CC BY-SA 4.0, via Wikimedia Commons https://commons.wikimedia.org/wiki/File:Edna_reflex_water_gages_141-R.jpg" in a.photos[0]
    check "CC BY-SA 4.0 https://creativecommons.org/licenses/by-sa/4.0" in a.photoLicences
    # each licence once (about.json writes CC BY-SA 3.0's address with and without a / at its end)
    var names: seq[string]
    for l in a.photoLicences:
      check l.rsplit(' ', 1)[0] notin names
      names.add l.rsplit(' ', 1)[0]
    check "CC BY-SA 3.0" in names and "CC0" in names

  test "names and texts with & and < are shown as written":
    let t = aboutFrom("""{"name": "W", "summary": "s", "developer": "A & B <x>", "links": {}, "licenses":
      {"MIT": {"name": "M & I", "url": "https://e.org/?a=1&b=\"2\"", "text": null}},
      "platforms": {"gnome": {"title": "t", "note": "n < m & o"}},
      "components": [{"id": "c", "name": "C & D", "version": "1", "license": "MIT", "license_name": "M & I",
        "license_ids": ["MIT"], "use": "x <y>", "platforms": {"gnome": "bundled"}, "notice": "Copyright <a> & b"}],
      "photos": [{"file": "f", "text": "Photo: P <p@q.r>, http://x.org, CC", "links":
        [{"text": "CC", "url": "https://creativecommons.org/x"}, {"text": "Page", "url": "https://p.org/a"}]}]}""")
    check shown(t.copyright) == "© A & B <x>"
    check shown(t.legal[0].copyright) == "n < m & o"
    check t.legal[1].title == "C & D 1"
    check shown(t.legal[1].copyright) == "Copyright <a> & b\nX <y>. Comes with Walkdown."
    check shown(t.legal[1].license) == "Licence: M & I (MIT)"
    check "href=\"https://e.org/?a=1&amp;b=&quot;2&quot;\"" in t.legal[1].license
    check t.photos == @["Photo: P ‹p@q.r›, x.org, CC https://p.org/a"]
    check t.photoLicences == @["CC https://creativecommons.org/x"]

  test "the debugging information names the version and the toolkit":
    let info = debugInfo(nil)
    check info.startsWith(versionLine("Walkdown") & "\n")
    check "GTK: 4." in info and "libadwaita: 1." in info and "System: " in info

  test "the dialog's code is compiled here too (it needs a display to run: the e2e opens it)":
    let build = aboutDialog
    check build != nil
