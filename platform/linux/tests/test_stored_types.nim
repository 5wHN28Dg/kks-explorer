## How the server types stored content (photos, plant-data files): from the bytes for photos, an allowlist for /data/,
## always sandboxed (2026-10-06, the photo XSS fix).
import std/unittest
import kksl/server

suite "stored content types":
  test "a photo's type comes from its bytes":
    check photoType("\xff\x0a" & "<html>") == ("image/jxl", true)
    check photoType("\x00\x00\x00\x0cJXL \r\n\x87\n") == ("image/jxl", true)
    check photoType("\xff\xd8\xff\xe0") == ("image/jpeg", true)
    check photoType("\x89PNG\r\n") == ("image/png", true)
    check photoType("RIFF....WEBP") == ("image/webp", true)

  test "anything else is a download":
    check photoType("<html><script>1</script>") == ("application/octet-stream", false)
    check photoType("") == ("application/octet-stream", false)

  test "/data/: the page types sandboxed, everything else a sandboxed download":
    for f in ["sheets.json", "sheets/a.kkp", "sheets/a.o0.jxl", "courses/x.woff2", "a.png"]:
      let (_, extra) = dataType(f)
      check ("Content-Security-Policy", "default-src 'none'; sandbox") in extra
      check ("Content-Disposition", "attachment") notin extra
    for f in ["courses/evil.html", "x.svg", "x.js", "x.xml", "x", "sheets/a.pdf"]:
      let (t, extra) = dataType(f)
      check t in ["application/octet-stream", "application/pdf"]
      check ("Content-Disposition", "attachment") in extra
      check ("Content-Security-Policy", "default-src 'none'; sandbox") in extra

  test "/data/: a compressed page is gzip bytes, never a page":
    let (t, extra) = dataType("courses/page.html.gz")
    check t == "application/gzip"
    check ("Content-Security-Policy", "default-src 'none'; sandbox") in extra
