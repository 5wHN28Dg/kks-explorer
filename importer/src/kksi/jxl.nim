## Lossless JPEG XL through libjxl (decision 0019): the path store's images.
import std/os
const dev = getEnv("KKS_DEV", getHomeDir() & ".local/kksdev")
{.passC: "-I" & dev & "/root/usr/include".}
{.passL: "-l:libjxl.so.0.11 -l:libjxl_threads.so.0.11".}
{.compile: "kks_jxl.c".}

proc kks_jxl_encode(p: pointer, w, h, n, effort: cint, len: ptr csize_t): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_jxl_encode_d(p: pointer, w, h, n, effort: cint, distance: cfloat, len: ptr csize_t): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_jxl_decode(p: pointer, len: csize_t, w, h, alpha: ptr cint): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_jxl_out_of_memory(): cint {.importc, cdecl.}
proc free(p: pointer) {.importc, header: "<stdlib.h>".}

type
  JxlError* = object of CatchableError
  JxlOutOfMemory* = object of JxlError   ## an allocation failed (the importer runs under an address-space limit)

proc encodeFailed() {.noreturn.} =
  if kks_jxl_out_of_memory() != 0: raise newException(JxlOutOfMemory, "JPEG XL encoding ran out of memory")
  raise newException(JxlError, "JPEG XL encoding failed")

proc encodeLossless*(pixels: openArray[byte], w, h, n: int, effort = 9): string =
  var len: csize_t
  let p = kks_jxl_encode(unsafeAddr pixels[0], cint(w), cint(h), cint(n), cint(effort), addr len)
  if p == nil: encodeFailed()
  result = newString(int(len))
  if len > 0: copyMem(addr result[0], p, int(len))
  free(p)

proc encodeLossy*(pixels: openArray[byte], w, h, n: int, distance = 1.9, effort = 9): string =
  ## photos (R9): lossy JPEG XL at a Butteraugli distance
  var len: csize_t
  let p = kks_jxl_encode_d(unsafeAddr pixels[0], cint(w), cint(h), cint(n), cint(effort), cfloat(distance), addr len)
  if p == nil: encodeFailed()
  result = newString(int(len))
  if len > 0: copyMem(addr result[0], p, int(len))
  free(p)

proc decodeRgba*(data: string): (int, int, bool, seq[byte]) =
  var w, h, a: cint
  let p = kks_jxl_decode(unsafeAddr data[0], csize_t(data.len), addr w, addr h, addr a)
  if p == nil: raise newException(JxlError, "JPEG XL decoding failed")
  var px = newSeq[byte](int(w) * int(h) * 4)
  if px.len > 0: copyMem(addr px[0], p, px.len)
  free(p)
  (int(w), int(h), a != 0, px)
