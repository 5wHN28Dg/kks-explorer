## Finding #26 (advisory GHSA-m2gr-gcrf-xc6m): the web listener takes only an address of this machine.
import std/unittest
import kksl/server

suite "web listener address":
  test "this machine's addresses are accepted":
    for a in ["127.0.0.1", "127.0.0.2", "127.255.255.255", "127.0.1.1", "localhost", "LOCALHOST", " 127.0.0.1 "]:
      check isLoopback(a)

  test "network addresses and malformed ones are refused":
    for a in ["", "0.0.0.0", "192.168.1.10", "::", "::1", "[::1]", "127.999.999.999", "127.0.0.256", "127.0.0",
              "127.0.0.1.5", "127..0.1", "127.0.0.01x", "128.0.0.1", "localhost.example.com", "127.0.0.1:80"]:
      check not isLoopback(a)
