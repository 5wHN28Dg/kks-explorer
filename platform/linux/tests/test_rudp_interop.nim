## Nim's reliable UDP (core rudp.nim + kksl/udp.nim) against v1's Python implementation (peer/rudp.py, through
## tools/rudp_peer.py, the helper the Kotlin RudpTest uses): the same wire format, so all three interoperate.
import std/[unittest, asyncdispatch, os, osproc, strutils]
import std/streams except Stream
import kksl/[udp, net]
import kks/[crypto, util]
import plat

let repo = currentSourcePath().parentDir / ".." / ".." / ".."
let P = testProvider()

proc exact(st: net.Stream, n: int): Future[string] {.async.} =
  var got = ""
  while got.len < n:
    let c = await st.read()
    if c.len == 0: raise newException(IOError, "eof after " & $got.len)
    got.add c
  return got[0 ..< n]

suite "rudp interop with v1's Python":
  test "punch, 1 MB up, its SHA-256 + 300 kB back, close":
    let py = if fileExists(repo / ".venv/bin/python"): repo / ".venv/bin/python" else: "python3"
    let session = "INTEROP1"
    let p = startProcess(py, repo, ["tools/rudp_peer.py", toHex(session)], options = {})
    let theirPort = parseInt(p.outputStream.readLine().strip)
    let u = newUdp()
    p.inputStream.writeLine("127.0.0.1:" & $u.port)
    p.inputStream.flush()
    let (h, port) = waitFor u.punch(session, @["127.0.0.1:" & $theirPort], timeout = 8000)
    check port == theirPort
    let st = u.rudpStream(h, port, session, dead = 60)
    var data = newString(1_000_000)
    for i in 0 ..< data.len: data[i] = char((i * 7 + 3) and 0xff)
    let n = data.len
    let lenBE = char(n shr 24) & char((n shr 16) and 0xff) & char((n shr 8) and 0xff) & char(n and 0xff)
    waitFor st.write(lenBE & data)
    let back = waitFor exact(st, 32 + 300_000)
    check back[0 ..< 32] == P.sha256(data.toOpenArrayByte(0, data.len - 1)).toStr
    st.close()
    check p.outputStream.readLine().strip == "done"
    discard p.waitForExit()
    p.close()
