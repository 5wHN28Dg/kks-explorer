## mDNS on Windows through the DNS-SD API (decisions 0021, 0033): the same interface as platform/linux/src/kksl/mdns.nim
## (announce, browse, pump, found). Results arrive on Windows' thread pool and are delivered by `pump` on the loop.

import std/[strutils, times]

{.compile: "kks_dnssd.c".}
{.passL: "-ldnsapi".}

proc c_next(): cstring {.importc: "kks_dnssd_next", cdecl.}
proc c_browse(): cint {.importc: "kks_dnssd_browse", cdecl.}
proc c_announce(name: cstring, port: cushort, n: cint, keys, values: ptr cstring): cint {.importc: "kks_dnssd_announce", cdecl.}
proc free(p: pointer) {.importc, header: "<stdlib.h>".}

const ServiceType* = "_kks._tcp"

type
  Found* = object
    name*, host*, address*: string
    port*: int
    txt*: seq[(string, string)]

  MdnsError* = object of CatchableError

  Mdns* = ref object
    onFound*: proc (f: Found)
    onGone*: proc (name: string)
    found*: seq[Found]
    lastBrowse: float

proc newMdns*(): Mdns = Mdns()

proc announce*(m: Mdns, name: string, port: int, txt: seq[(string, string)]) =
  var keys, values: seq[cstring]
  for (k, v) in txt:
    keys.add k.cstring
    values.add v.cstring
  let r = c_announce(name.cstring, cushort(port), cint(txt.len), (if keys.len > 0: addr keys[0] else: nil),
                     (if values.len > 0: addr values[0] else: nil))
  if r != 0: raise newException(MdnsError, "DnsServiceRegister: " & $r)

proc browse*(m: Mdns) =
  let r = c_browse()
  if r != 0: raise newException(MdnsError, "DnsServiceBrowse: " & $r)
  m.lastBrowse = epochTime()

proc pump*(m: Mdns) =
  ## Deliver what the DNS-SD callbacks found; browse again every minute (an answer can be missed).
  while true:
    let p = c_next()
    if p == nil: break
    let parts = ($p).split('\t')
    free(p)
    if parts.len < 5: continue
    var f = Found(name: parts[0].replace("._kks._tcp.local", ""), host: parts[1], address: parts[2],
                  port: (try: parseInt(parts[3]) except ValueError: 0))
    if parts[4].len > 0:
      for kv in parts[4].split('\x1f'):
        let i = kv.find('=')
        if i > 0: f.txt.add (kv[0 ..< i], kv[i + 1 .. ^1])
    if f.address.len == 0 or f.port == 0: continue
    var kept: seq[Found]
    for x in m.found:
      if x.name != f.name: kept.add x
    kept.add f
    m.found = kept
    if m.onFound != nil: m.onFound(f)
  if m.lastBrowse > 0 and epochTime() - m.lastBrowse > 60:
    try: m.browse() except MdnsError: discard
