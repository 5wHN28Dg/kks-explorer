# The WebSocket client's checks on the relay address (#15): wss:// only, ws:// to this machine; a bad port is an error.
import std/[unittest, asyncdispatch]
import kksl/ws

proc refused(url: string): bool =
  try:
    discard waitFor wsConnect(url, 2_000)
    false
  except WsError:
    true

suite "relay address":
  test "ws:// to another host is refused before connecting":
    for u in ["ws://relay.example.dev", "ws://10.0.0.5:8787", "ws://127.0.0.1.nip.io", "ws://localhost.evil.dev",
              "ws://127.0.0.1@evil.dev", "WS://127.0.0.1", "http://127.0.0.1"]:
      check refused(u)

  test "a port out of range is an error, not a crash":
    for u in ["ws://127.0.0.1:99999", "ws://127.0.0.1:0", "ws://127.0.0.1:x"]:
      check refused(u)
