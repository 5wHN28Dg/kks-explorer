## The About window's content (apps/windows/src/kkswin/aboutinfo.nim) from this build's data/about.json: the Windows
## app's parts with their notices and full licence texts, the photo credits, which links may reach the browser, the
## Windows version line. Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it):
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_about.exe apps/windows/tests/test_about.nim
## Nothing in it is Win32, so it runs on Linux too (without apps/windows/config.nims, which links the app's resources):
##   cd apps/windows && nim c -r --skipParentCfg:on --path:src --path:../../core/src --path:../../platform/linux/src tests/test_about.nim
import std/[unittest, strutils]
import kks/json
import kksl/buildinfo
import kkswin/aboutinfo

let a = parseAbout(AboutJson)
let raw = parseStrict(AboutJson)

proc part(id: string): Part =
  for p in a.parts:
    if p.id == id: return p
  raise newException(KeyError, "no part " & id)

suite "about content":
  test "Walkdown itself":
    check a.name == "Walkdown"
    check a.summary.len > 0
    check a.license.text == "GNU Affero General Public License v3.0 or later"
    check isWebLink(a.license.url)
    check "GNU AFFERO GENERAL PUBLIC LICENSE" in a.licenseText
    check "ABSOLUTELY NO WARRANTY" in a.notice
    for l in [a.homepage, a.issues, a.help]: check isWebLink(l)
    check a.platformTitle == "The Windows app"

  test "exactly the parts whose platforms.windows is set, in about.json's order":
    var want: seq[string]
    for c in raw["components"].elems:
      if c["platforms"].get("windows") != nil: want.add c["id"].s
    var got: seq[string]
    for p in a.parts: got.add p.id
    check got == want
    check "libjxl" in got and "mingw-w64" in got and "jetbrains-mono" in got
    check "mupdf" notin got and "gtk" notin got and "compose" notin got     # the server's, GNOME's, Android's

  test "a part's row and what is shown for it":
    let j = part("libjxl")
    check j.row == "libjxl 0.12.0 · BSD 3-Clause License"
    check j.detail.startsWith(j.row & "\nJPEG XL photos\nhttps://github.com/libjxl/libjxl\n\n")
    check j.notice.len > 0 and j.notice in j.detail                       # its BSD notice, as the licence asks
    check part("highway").row.startsWith("Highway commit 457c891775a7 · ")   # a pinned commit, shortened
    check "Apache License 2.0, the full text:" in part("zxing-cpp").detail   # no notice: the licence's own text

  test "every licence's full text is reachable: from the licence or the part's notice":
    for p in a.parts:
      var c: JNode
      for x in raw["components"].elems:
        if x["id"].s == p.id: c = x
      for idn in c["license_ids"].elems:
        let l = raw["licenses"][idn.s]
        if l["text"].isStr: check l["text"].s.strip in p.detail
        else: check (l["url"].s in p.detail)
      if c.get("notice") != nil and c["notice"].isStr: check c["notice"].s.strip in p.detail

  test "the fonts show their copyright and the whole OFL; BSD and MIT parts their notice":
    for id in ["atkinson-hyperlegible", "barlow-semi-condensed", "jetbrains-mono"]:
      let f = part(id)
      check "Copyright" in f.notice
      check "SIL OPEN FONT LICENSE Version 1.1" in f.detail
      check "PERMISSION & CONDITIONS" in f.detail
    for id in ["libjxl", "skcms", "libzueci", "brotli", "zlib", "nim"]:
      check part(id).notice.len > 100

  test "photo credits with their links":
    check a.photos.len == raw["photos"].elems.len
    var found = false
    for ph in a.photos:
      if ph.text == "Photo: Didier Duforest, CC BY-SA 4.0, via Wikimedia Commons":
        found = true
        check ph.links.len == 2
        check linkRow(ph.links[0]) == "CC BY-SA 4.0 · https://creativecommons.org/licenses/by-sa/4.0"
        check isWebLink(ph.links[1].url)
    check found
    for ph in a.photos:
      for l in ph.links: check isWebLink(l.url)

  test "only https links reach the browser":
    check isWebLink("https://github.com/5wHN28Dg/kks-explorer/tree/0123456789abcdef0123456789abcdef01234567")
    for bad in ["http://example.org", "file:///C:/Windows/System32/calc.exe", "C:\\Windows\\System32\\calc.exe",
                "javascript:alert(1)", "https://", "https:///x", "https://a b", "https://x\"y", "https://x\ny",
                "HTTPS://example.org", " https://example.org", "https://x|calc", "ms-settings:", "https://\\\\host\\share",
                "https://" & repeat('a', 2050)]:
      check not isWebLink(bad)

  test "the content this program knows, and nothing else":
    expect ValueError: discard parseAbout("{}")
    expect ValueError: discard parseAbout("""{"format":"walkdown-about","version":2}""")
    expect ValueError: discard parseAbout("[1,2")
    # a v1 file without the optional parts still opens
    let m = parseAbout("""{"format":"walkdown-about","version":1,"name":"W","components":[{"id":"x","platforms":{"windows":"system"},"license_ids":["Q"]}],"licenses":{}}""")
    check m.name == "W" and m.parts.len == 1
    check m.parts[0].system and m.parts[0].row == " (the system's copy)"
    check m.parts[0].detail.endsWith("\n\nQ")

  test "the version and the Windows line":
    check versionText("0.12.0") == "0.12.0"
    check versionText("457c891775a7397bdb0376bb1031e6e027af1c48") == "commit 457c891775a7"
    check windowsName(10, 0, 26200, "x64") == "Windows 11 (10.0.26200), x64"
    check windowsName(10, 0, 19045, "x64") == "Windows 10 (10.0.19045), x64"
    check windowsName(6, 3, 9600, "ARM64") == "Windows (6.3.9600), ARM64"
    # built from a git checkout (CI, here): the commit is known even without -d:kksCommit, on a Windows target too
    # (buildinfo's paths followed the target's separators there: git ran on "\home\…" and found nothing)
    check Commit.len == 40
    check SourceUrl == "https://github.com/5wHN28Dg/kks-explorer/tree/" & Commit
    let d = supportDetails("Windows 11 (10.0.26200), x64")
    check d.startsWith("Walkdown " & Version & " (commit ")
    check SourceUrl in d and "Windows 11 (10.0.26200), x64" in d
