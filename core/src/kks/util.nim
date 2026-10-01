## Byte helpers: hex and base64url (RFC 4648 §5, no padding).

import std/strutils

proc toBytes*(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

proc toStr*(b: openArray[byte]): string =
  result = newString(b.len)
  for i, x in b: result[i] = char(x)

proc hex*(b: openArray[byte]): string =
  result = newStringOfCap(b.len * 2)
  for x in b: result.add toHex(int(x), 2).toLowerAscii

proc hex*(s: string): string = hex(s.toBytes)

proc unhex*(s: string): seq[byte] =
  if s.len mod 2 != 0: raise newException(ValueError, "odd hex length")
  result = newSeq[byte](s.len div 2)
  for i in 0 ..< result.len: result[i] = byte(parseHexInt(s[2*i .. 2*i+1]))

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

proc b64u*(b: openArray[byte]): string =
  var i = 0
  while i + 2 < b.len:
    let n = (int(b[i]) shl 16) or (int(b[i+1]) shl 8) or int(b[i+2])
    result.add B64[(n shr 18) and 63]; result.add B64[(n shr 12) and 63]
    result.add B64[(n shr 6) and 63]; result.add B64[n and 63]
    i += 3
  let rest = b.len - i
  if rest == 1:
    let n = int(b[i]) shl 16
    result.add B64[(n shr 18) and 63]; result.add B64[(n shr 12) and 63]
  elif rest == 2:
    let n = (int(b[i]) shl 16) or (int(b[i+1]) shl 8)
    result.add B64[(n shr 18) and 63]; result.add B64[(n shr 12) and 63]; result.add B64[(n shr 6) and 63]

proc unb64u*(s: string): seq[byte] =
  ## Strict: alphabet only, no padding, no impossible length, unused bits zero.
  if s.len mod 4 == 1: raise newException(ValueError, "not base64url")
  var acc, bits = 0
  for c in s:
    let v = B64.find(c)
    if v < 0: raise newException(ValueError, "not base64url")
    acc = (acc shl 6) or v
    bits += 6
    if bits >= 8:
      bits -= 8
      result.add byte((acc shr bits) and 0xFF)
  if (acc and ((1 shl bits) - 1)) != 0: raise newException(ValueError, "non-zero padding bits")
