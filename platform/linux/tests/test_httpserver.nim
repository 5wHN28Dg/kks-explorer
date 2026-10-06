## The HTTP server's limits that the e2e tests can't reach quickly (kksl/httpserver.nim).
import std/[asyncdispatch, asyncnet, net, strutils, unittest]
import kksl/httpserver

suite "httpserver":
  test "a handler past its deadline can't answer on a descriptor another client now has":
    let http = newAsyncHttpServer()
    http.responseTimeoutMs = 1000
    proc cb(req: Request) {.async, gcsafe.} =
      if req.url.path == "/slow":
        await sleepAsync(2000)                      # past the deadline: its connection is closed meanwhile
        try: await req.respond(Http200, "SECRET-FOR-FIRST-CLIENT")
        except IOError: discard
      else:
        await sleepAsync(900)                       # still waiting when the slow handler wakes up (t = 2.0 s)
        await req.respond(Http200, "second")
    asyncCheck http.serve(Port(0), cb, "127.0.0.1")
    waitFor sleepAsync(100)
    let port = http.getPort
    proc get(path: string): Future[string] {.async.} =
      let c = await asyncnet.dial("127.0.0.1", port)
      await c.send("GET " & path & " HTTP/1.1\r\nHost: x\r\nConnection: close\r\n\r\n")
      var all = ""
      while true:
        let b = await c.recv(4096)
        if b.len == 0: break
        all.add b
      c.close()
      result = all
    let first = get("/slow")
    waitFor sleepAsync(1500)                        # the first connection is closed by now; its fd is free
    let second = waitFor get("/next")
    check "SECRET" notin second
    check second.startsWith("HTTP/1.1 200") and second.endsWith("second")
    check "SECRET" notin waitFor first
    http.close()
