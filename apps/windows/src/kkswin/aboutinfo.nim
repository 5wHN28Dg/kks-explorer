## What the About window shows (about.nim), from the shared About content (data/about.json, format "walkdown-about"
## v1, made by tools/about.py) that kksl/buildinfo compiles in: Walkdown's name, licence and links, the third-party
## parts of the Windows app (`platforms.windows` set) each with its notice and the full text of its licences, and the
## course photos' credits. No Win32 here: tests/test_about.nim checks it on Windows and Linux alike.

import std/strutils
import kks/json
import kksl/buildinfo

type
  Link* = object
    text*, url*: string
  Part* = object
    id*, name*, version*, licenseName*, use*, url*: string
    system*: bool          ## the system's copy, not built into Walkdown (platforms.windows = "system")
    notice*: string        ## its copyright and licence notice ("" when about.json has none)
    detail*: string        ## what the window shows for it: what it is, the notice, every licence's full text (or
                           ## where to read one that about.json carries no text of)
  Photo* = object
    text*: string          ## the credit as the course writes it
    links*: seq[Link]      ## the links in it, in order
  About* = object
    name*, summary*, developer*, notice*: string
    license*: Link         ## Walkdown's own licence (text: its name)
    licenseText*: string   ## its full text ("" when about.json has none)
    homepage*, issues*, help*: string
    platformTitle*, platformNote*: string
    parts*: seq[Part]
    photos*: seq[Photo]

proc str(n: JNode, k: string): string =
  if n != nil and n.kind == jObj and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc obj(n: JNode, k: string): JNode =
  if n != nil and n.kind == jObj and n.get(k) != nil and n[k].kind == jObj: n[k] else: newObj()

proc arr(n: JNode, k: string): seq[JNode] =
  if n != nil and n.kind == jObj and n.get(k) != nil and n[k].kind == jArr: n[k].elems else: @[]

proc isWebLink*(url: string): bool =
  ## only https links from about.json are handed to the default browser (ShellExecute opens whatever a string names:
  ## a file, a program, another scheme): "https://" and a host, no spaces, quotes or control characters
  if not url.startsWith("https://") or url.len <= "https://".len or url.len > 2048: return false
  if url["https://".len] in {'/', '.', ':', '@', '\\'}: return false
  for c in url:
    if c <= ' ' or c in {'"', '<', '>', '\\', '^', '`', '{', '|', '}', '\x7f'}: return false
  true

proc versionText*(v: string): string =
  ## a part's version as people read it: a pinned commit shortened like the web's About ("commit 457c891775a7")
  if v.len == 40 and v.allCharsInSet(HexDigits): "commit " & v[0 ..< 12] else: v

proc row*(p: Part): string =
  ## its row in the list (its UI Automation name): "libjxl 0.12.0 · BSD 3-Clause License"
  result = p.name
  if p.system: result.add " (the system's copy)"
  elif p.version.len > 0: result.add " " & versionText(p.version)
  if p.licenseName.len > 0: result.add " · " & p.licenseName

proc parseAbout*(text: string, platform = "windows"): About =
  ## -> the About for `platform`'s parts. Raises ValueError (JsonError is one) when `text` is not the About content
  let d = parseStrict(text)
  if d.kind != jObj or d.str("format") != "walkdown-about" or d.get("version") == nil or not d["version"].isInt or
     d["version"].i != 1:
    raise newException(ValueError, "not the About content this program knows (walkdown-about v1)")
  result.name = d.str("name")
  result.summary = d.str("summary")
  result.developer = d.str("developer")
  result.notice = d.str("notice")
  let lic = d.obj("license")
  let licenses = d.obj("licenses")
  result.license = Link(text: lic.str("name"), url: lic.str("url"))
  result.licenseText = licenses.obj(lic.str("id")).str("text")
  let links = d.obj("links")
  result.homepage = links.str("homepage")
  result.issues = links.str("issues")
  result.help = links.str("help")
  let pl = d.obj("platforms").obj(platform)
  result.platformTitle = pl.str("title")
  result.platformNote = pl.str("note")
  for c in d.arr("components"):
    let on = c.obj("platforms").str(platform)
    if on.len == 0: continue
    var p = Part(id: c.str("id"), name: c.str("name"), version: c.str("version"), licenseName: c.str("license_name"),
                 use: c.str("use"), url: c.str("url"), system: on == "system", notice: c.str("notice").strip)
    var lines = @[p.row]
    if p.use.len > 0: lines.add p.use
    if p.url.len > 0: lines.add p.url
    var txt = lines.join("\n")
    if p.notice.len > 0: txt.add "\n\n" & p.notice
    for idn in c.arr("license_ids"):
      if not idn.isStr: continue
      let l = licenses.obj(idn.s)
      let name = if l.str("name").len > 0: l.str("name") else: idn.s
      let t = l.str("text").strip
      if t.len > 0: txt.add "\n\n" & name & ", the full text:\n\n" & t
      elif l.str("url").len > 0: txt.add "\n\n" & name & ": " & l.str("url")
      else: txt.add "\n\n" & name
    p.detail = txt
    result.parts.add p
  for ph in d.arr("photos"):
    var p = Photo(text: ph.str("text"))
    for l in ph.arr("links"): p.links.add Link(text: l.str("text"), url: l.str("url"))
    if p.text.len > 0: result.photos.add p

proc linkRow*(l: Link): string =
  ## a photo's link in its list: what it says and where it goes
  if l.text.len > 0 and l.text != l.url: l.text & " · " & l.url else: l.url

proc windowsName*(major, minor, build: int, cpu: string): string =
  ## "Windows 11 (10.0.26200), x64": Windows 11 still says 10.0, its builds start at 22000
  let name = if major == 10 and build >= 22000: "Windows 11" elif major == 10: "Windows 10" else: "Windows"
  name & " (" & $major & "." & $minor & "." & $build & "), " & cpu

proc supportDetails*(windows: string): string =
  ## what "Copy details" puts on the clipboard for a problem report
  versionLine("Walkdown") & "\n" & sourceLine() & "\n" & windows & "\n"
