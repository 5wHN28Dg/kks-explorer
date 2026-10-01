import std/[unittest, os, times, strutils]
import kksl/mdns

suite "mDNS through Avahi (needs avahi-daemon on the system bus)":
  test "announce one service, find it by browsing":
    let a = newMdns()
    let name = "kks-test-" & $getCurrentProcessId()
    a.announce(name, 18499, @[("peer", "TESTPEERID"), ("v", "2")])
    let b = newMdns()
    var got: Found
    b.onFound = proc (f: Found) =
      if f.name == name: got = f
    b.browse()
    let t0 = epochTime()
    while got.name.len == 0 and epochTime() - t0 < 10:
      b.pump()
      sleep(50)
    check got.name == name
    check got.port == 18499
    check ("peer", "TESTPEERID") in got.txt
    echo "  found ", got.name, " at ", got.address, ":", got.port, " in ", int((epochTime() - t0) * 1000), " ms"
