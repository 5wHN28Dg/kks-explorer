## Failed-attempt throttling for the server's password and token checks (issue #39).
##
## - A key (a source: "ip:…" or "tls:<peer>", or an account at one source) is blocked after `FreeFails` failures, for
##   15 s, doubling per further failure up to 15 minutes, until a success clears it.
## - The account is counted per source, so failures from one place don't lock its owner out everywhere.
## - Under pressure (`GlobalCap` failures in `Window` seconds, from anywhere), any source or account with a failure in
##   that window is refused until the pressure drops: one password sprayed over many accounts, or many sources (peer
##   IDs are free to make) on one account, gets one guess each. Real users who mistype during an attack wait too.
## IPv6 sources are counted per /64 (one host usually has the whole prefix).

import std/[deques, net, strutils, tables]

const
  FreeFails* = 5
  Window* = 900.0
  GlobalCap* = 50
  MaxKeys = 100_000      ## entries kept; older idle ones are dropped first

type Throttle* = object
  fails: Table[string, tuple[n: int, until, last: float]]
  recent: Deque[float]   ## times of the failures in the last Window

proc sourceKey*(address: string): string =
  ## "ip:<address>", an IPv6 address cut to its /64 (IPv4-mapped ones read as IPv4)
  try:
    let a = parseIpAddress(address)
    if a.family == IpAddressFamily.IPv6:
      var mapped = true
      for i in 0 .. 9:
        if a.address_v6[i] != 0: mapped = false
      if mapped and a.address_v6[10] == 0xff and a.address_v6[11] == 0xff:
        return "ip:" & $a.address_v6[12] & "." & $a.address_v6[13] & "." & $a.address_v6[14] & "." & $a.address_v6[15]
      var h = ""
      for i in 0 .. 7: h.add toHex(a.address_v6[i], 2).toLowerAscii
      return "ip:" & h & "::/64"
    return "ip:" & $a
  except ValueError:
    return "ip:" & address

proc prune(t: var Throttle, now: float) =
  while t.recent.len > 0 and t.recent.peekFirst < now - Window: discard t.recent.popFirst
  if t.fails.len > MaxKeys:
    var old: seq[string]
    for k, v in t.fails:
      if v.until < now and v.last < now - Window: old.add k
    for k in old: t.fails.del k

proc underPressure*(t: var Throttle, now: float): bool =
  t.prune(now)
  t.recent.len >= GlobalCap

proc blocked*(t: var Throttle, keys: openArray[string], now: float, watch: openArray[string] = []): bool =
  ## `keys` block on their own failures; `watch` keys (an account as a whole) only under pressure
  for k in keys:
    if k in t.fails and t.fails[k].until > now: return true
  if t.underPressure(now):
    for k in keys:
      if k in t.fails and t.fails[k].last >= now - Window: return true
    for k in watch:
      if k in t.fails and t.fails[k].last >= now - Window: return true
  false

proc record*(t: var Throttle, ok: bool, keys: openArray[string], now: float, watch: openArray[string] = []) =
  for k in @keys & @watch:
    if ok: t.fails.del k
    else:
      let n = t.fails.getOrDefault(k).n + 1
      t.fails[k] = (n, now + (if n >= FreeFails: float(min(900, 15 * (1 shl min(n - FreeFails, 10)))) else: 0.0), now)
  if not ok:
    t.recent.addLast now
    t.prune(now)
