## The reliable-UDP stream (core/src/kks/rudp.nim) between two ends over a simulated link: delay, deterministic loss.
import std/[unittest, random, strutils]
import kks/rudp

proc transfer(loss: float, size: int, seed = 7, dead = 60.0): (bool, float) =
  ## A sends `size` bytes to B and B sends size/4 back, both finish; -> (both received everything, simulated seconds)
  var rng = initRand(seed)
  let sess = "ABCDEFGH"
  var now = 0.0
  let a = newRudp(sess, now, dead)
  let b = newRudp(sess, now, dead)
  var msgA = newString(size)
  for i in 0 ..< size: msgA[i] = char(rng.rand(255))
  let msgB = msgA[0 ..< size div 4]
  a.write(msgA, now); b.write(msgB, now)
  var gotA, gotB = ""
  var inflight: seq[(float, bool, string)]       # (arrival time, to b?, datagram)
  let delay = 0.03
  while now < 600:
    now += 0.005
    for d in a.takeOut():
      if rng.rand(1.0) >= loss: inflight.add((now + delay, true, d))
    for d in b.takeOut():
      if rng.rand(1.0) >= loss: inflight.add((now + delay, false, d))
    var keep: seq[(float, bool, string)]
    for (t, toB, d) in inflight:
      if t <= now:
        if toB: b.feed(d, now) else: a.feed(d, now)
      else: keep.add((t, toB, d))
    inflight = keep
    gotB.add b.read(); gotA.add a.read()
    if a.queued == 0: a.finish(now)
    if b.queued == 0: b.finish(now)
    a.tick(now); b.tick(now)
    if a.error.len > 0 or b.error.len > 0:
      echo "  FAIL at ", now, ": a.err=", a.error, " b.err=", b.error, " got ", gotB.len, "/", msgA.len, " and ", gotA.len, "/", msgB.len,
           " a.fin=", a.finished, " b.fin=", b.finished, " a.ended=", a.ended, " b.ended=", b.ended, " a.queued=", a.queued, " b.queued=", b.queued
      return (false, now)
    if a.finished and b.finished and a.ended and b.ended: break
  (gotB == msgA and gotA == msgB, now)

suite "rudp (PROTOCOL-v2 §18)":
  test "clean link, 3 MB":
    let (ok, t) = transfer(0.0, 3_000_000)
    check ok
    echo "  3 MB clean: ", formatFloat(t, ffDecimal, 1), " s simulated"
  # the cases of v1's tests/test_rudp.py (sizes and the 60 s stall limit), both directions at once
  for (loss, size) in [(0.02, 2_000_000), (0.10, 200_000), (0.20, 50_000)]:
    test "loss " & $int(loss * 100) & " %, " & $(size div 1000) & " kB":
      let (ok, t) = transfer(loss, size)
      check ok
      echo "  ", size div 1000, " kB at ", int(loss * 100), " % loss: ", formatFloat(t, ffDecimal, 1), " s simulated"
  test "a packet of the wrong session is ignored":
    let r = newRudp("ABCDEFGH", 0.0)
    r.feed(packet(Data, "XXXXXXXX", "\0\0\0\0hello"), 0.1)
    check r.read() == ""
  test "out-of-order data beyond the receive window is dropped (issue #36)":
    let r = newRudp("ABCDEFGH", 0.0)
    for s in 1'u32 .. 5000'u32:          # seq 0 never arrives: everything else would wait in the buffer
      r.feed(packet(Data, "ABCDEFGH", char(s shr 24) & char((s shr 16) and 255) & char((s shr 8) and 255) & char(s and 255) & "x"), 0.1)
    check r.buffered == int(RecvWindow) - 1
    discard r.takeOut()
    r.feed(packet(Data, "ABCDEFGH", "\0\0\0\0y"), 0.2)     # the hole fills: the window's contents come out in order
    check r.read() == "y" & "x".repeat(int(RecvWindow) - 1)
    check r.buffered == 0
