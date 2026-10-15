## About Walkdown: a window of its own (Manage → About Walkdown…, F1 anywhere in the app, or the window's system menu,
## also on the setup screen) with what this build is (version, the commit it was built from, "with local changes" for a
## build that had some), what Walkdown is, its licence and links, the source of exactly this version (the AGPL's offer
## of the Corresponding Source), the free-software and no-warranty notice, the third-party parts of the Windows app
## with each one's notice and full licence texts, and the course photos' credits. The content is the shared
## data/about.json, compiled in (kksl/buildinfo, aboutinfo.nim). Links open in the default browser, https links only.
## Everything is a native control, so UI Automation and the keyboard come with it; Esc closes the window.

import std/strutils
import kksl/buildinfo
import w32, ui, aboutinfo

var aboutWindow: HWND          ## the open window (one at a time)

proc RtlGetVersion(info: pointer): int32 {.importc, stdcall, dynlib: "ntdll.dll".}

type OsVersionInfo = object    ## RTL_OSVERSIONINFOW
  size, major, minor, build, platform: uint32
  csd: array[128, uint16]

proc windowsLine*(): string =
  ## this Windows as "Windows 11 (10.0.26200), x64". RtlGetVersion: GetVersionEx answers what the manifest declares
  var v = OsVersionInfo(size: uint32(sizeof(OsVersionInfo)))
  if RtlGetVersion(addr v) != 0: return "Windows (version unknown)"
  windowsName(int(v.major), int(v.minor), int(v.build), when defined(arm64): "ARM64" else: "x64")

proc openLink(owner: HWND, url: string) =
  ## the default browser, for an https link only (aboutinfo.isWebLink): never a file, a program or another scheme
  if isWebLink(url):
    discard ShellExecuteW(owner, newWideCString("open"), newWideCString(url), nil, nil, 1)

var parsed: ref (About, string)
proc content(): (About, string) =
  ## the compiled-in About content, parsed when About first opens (tests/test_about.nim checks that it parses)
  if parsed == nil:
    parsed = new((About, string))
    try: parsed[] = (parseAbout(AboutJson), "")
    except ValueError as e: parsed[] = (About(name: "Walkdown"), e.msg)
  parsed[]

proc textWindow(owner: HWND, title, text: string) =
  ## a long text (a licence) in a window of its own, to read, scroll and copy from
  let (hw, p) = popup(owner, title, 640, 720, escape = true)
  p.dim("Esc closes this window.")
  p.label(title)                                     # (the static text just before it is its UI Automation name)
  let e = control(p.hwnd, "EDIT", "", WS_TABSTOP or WS_VSCROLL or ES_MULTILINE or ES_AUTOVSCROLL or ES_READONLY,
                  WS_EX_CLIENTEDGE)[0]
  SendMessageW(e, 0x00C5'u32, 4_000_000, 0)         # EM_SETLIMITTEXT: licences are longer than the default 32 K
  e.setText(text.replace("\r\n", "\n").replace("\n", "\r\n"))
  p.fill(e, 300)
  p.layout()
  ShowWindow(hw, SW_SHOW)
  SetFocus(e)

proc openAbout*(owner: HWND) =
  if aboutWindow != nil and IsWindow(aboutWindow) != 0:
    SetForegroundWindow(aboutWindow)
    return
  let (a, err) = content()
  let (hw, p) = popup(owner, "About Walkdown", 680, 780, proc () = aboutWindow = nil, escape = true)
  aboutWindow = hw
  p.title(a.name)
  if err.len > 0: p.label("The About content of this build can't be read: " & err)
  if a.summary.len > 0: p.label(a.summary)
  p.label(versionLine("Version"))       # "Version 0.10.3 (commit 0123456789ab, with local changes)"
  p.label("By " & a.developer & ". Licence: " & a.license.text & ".")
  p.dim(a.notice)
  p.dim("These buttons open pages in your web browser.")
  p.buttons(("Licence", proc () = openLink(hw, a.license.url)),
            ("Home page", proc () = openLink(hw, a.homepage)),
            ("Report a problem", proc () = openLink(hw, a.issues)),
            ("Help", proc () = openLink(hw, a.help)))
  if a.licenseText.len > 0:
    p.buttons(("Licence text…", proc () = textWindow(hw, a.license.text, a.licenseText)))
  p.label(sourceLine())
  let copied = p.dim("")
  p.buttons(("Source of this version", proc () = openLink(hw, SourceUrl)),
            ("Copy details", proc () =
              copied.setText(if copyToClipboard(hw, supportDetails(windowsLine())):
                               "Copied the version, the commit and this Windows version, for a problem report."
                             else: "The clipboard is busy: try again.")))

  p.space(8)
  p.title("Third-party software")
  p.dim((if a.platformTitle.len > 0: a.platformTitle & ": " else: "") & a.platformNote &
        " Pick a part to read its notice and licences below.")
  var rows: seq[string]
  for part in a.parts: rows.add part.row
  var detail: HWND
  let parts = p.list(rows, 190, onSelect = proc (i: int) =
    if i >= 0 and i < a.parts.len: detail.setText(a.parts[i].detail.replace("\n", "\r\n")))
  detail = p.multiField("Notice and licences of the selected part", "", 260, readonly = true)
  SendMessageW(detail, 0x00C5'u32, 4_000_000, 0)    # EM_SETLIMITTEXT
  p.buttons(("Open the selected part's home page", proc () =
    let i = int(SendMessageW(parts, LB_GETCURSEL, 0, 0))
    if i >= 0 and i < a.parts.len: openLink(hw, a.parts[i].url)))
  if a.parts.len > 0:
    SendMessageW(parts, LB_SETCURSEL, 0, 0)
    detail.setText(a.parts[0].detail.replace("\n", "\r\n"))

  p.space(8)
  p.title("Course photos")
  p.dim("The photos in the courses are by these authors, under these licences. Pick one for its links.")
  var photoRows: seq[string]
  for ph in a.photos: photoRows.add ph.text
  var links: HWND
  var shown: seq[Link]
  p.list(photoRows, 160, onSelect = proc (i: int) =
    shown = if i >= 0 and i < a.photos.len: a.photos[i].links else: @[]
    var r: seq[string]
    for l in shown: r.add linkRow(l)
    links.setRows(r))
  p.label("Links of the selected photo")
  links = p.list(@[], 70, onActivate = proc (i: int) =
    if i >= 0 and i < shown.len: openLink(hw, shown[i].url), openLabel = "Open the selected link")
  p.layout()
  ShowWindow(hw, SW_SHOW)
  SetFocus(parts)
