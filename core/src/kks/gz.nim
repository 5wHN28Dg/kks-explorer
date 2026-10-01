## gzip through zlib (bundles, PROTOCOL-v2 §15 file sync). The core links zlib (decision 0029).

{.passL: "-lz".}
const H = "<zlib.h>"

type ZStream {.importc: "z_stream", header: H.} = object
  next_in {.importc: "next_in".}: ptr uint8
  avail_in {.importc: "avail_in".}: cuint
  next_out {.importc: "next_out".}: ptr uint8
  avail_out {.importc: "avail_out".}: cuint
  total_out {.importc: "total_out".}: culong

var
  Z_OK {.importc, header: H, nodecl.}: cint
  Z_STREAM_END {.importc, header: H, nodecl.}: cint
  Z_FINISH {.importc, header: H, nodecl.}: cint
  Z_NO_FLUSH {.importc, header: H, nodecl.}: cint
  Z_BUF_ERROR {.importc, header: H, nodecl.}: cint
  Z_DEFLATED {.importc, header: H, nodecl.}: cint
  Z_DEFAULT_STRATEGY {.importc, header: H, nodecl.}: cint

proc deflateInit2(s: ptr ZStream, level, meth, bits, mem, strategy: cint): cint {.importc, header: H.}
proc deflate(s: ptr ZStream, flush: cint): cint {.importc, header: H.}
proc deflateEnd(s: ptr ZStream): cint {.importc, header: H.}
proc deflateBound(s: ptr ZStream, n: culong): culong {.importc, header: H.}
proc inflateInit2(s: ptr ZStream, bits: cint): cint {.importc, header: H.}
proc inflate(s: ptr ZStream, flush: cint): cint {.importc, header: H.}
proc inflateEnd(s: ptr ZStream): cint {.importc, header: H.}

type GzError* = object of CatchableError

proc gzip*(data: string, level = 6): string =
  var s: ZStream
  if deflateInit2(addr s, cint(level), Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY) != Z_OK: raise newException(GzError, "gzip init")
  defer: discard deflateEnd(addr s)
  result = newString(int(deflateBound(addr s, culong(data.len))) + 32)
  s.next_in = if data.len > 0: cast[ptr uint8](unsafeAddr data[0]) else: nil
  s.avail_in = cuint(data.len)
  s.next_out = cast[ptr uint8](addr result[0])
  s.avail_out = cuint(result.len)
  if deflate(addr s, Z_FINISH) != Z_STREAM_END: raise newException(GzError, "gzip failed")
  result.setLen(int(s.total_out))

proc gunzip*(data: string, maxOut: int): string =
  ## One gzip stream, at most `maxOut` bytes out.
  var s: ZStream
  if inflateInit2(addr s, 31) != Z_OK: raise newException(GzError, "gunzip init")
  defer: discard inflateEnd(addr s)
  s.next_in = if data.len > 0: cast[ptr uint8](unsafeAddr data[0]) else: nil
  s.avail_in = cuint(data.len)
  result = newString(min(max(data.len * 4, 4096), maxOut + 1))
  while true:
    let have = int(s.total_out)
    if have >= result.len:
      if result.len > maxOut: raise newException(GzError, "too large")
      result.setLen(min(result.len * 2, maxOut + 1))
    s.next_out = cast[ptr uint8](addr result[have])
    s.avail_out = cuint(result.len - have)
    let r = inflate(addr s, Z_NO_FLUSH)
    if r == Z_STREAM_END: break
    if r == Z_BUF_ERROR and s.avail_in == 0: raise newException(GzError, "truncated")
    if r != Z_OK and r != Z_BUF_ERROR: raise newException(GzError, "not gzip")
  if int(s.total_out) > maxOut: raise newException(GzError, "too large")
  result.setLen(int(s.total_out))
