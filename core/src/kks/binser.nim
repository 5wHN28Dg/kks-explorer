## A compact binary form of in-memory values, for the saved replayed state (savedstate.nim, PROTOCOL-v2 §15b): what a
## replay computed, written so that reading it back is much cheaper than replaying. Not an exchange format: only the
## program that wrote it reads it back (savedstate checks that), so it carries no field names, only values in field
## order. The reader checks every length against what is left and raises SavedStateError on anything malformed.
##
##   bool        1 byte (0, 1)
##   integer     ZigZag, then LEB128
##   string      length (integer), bytes
##   float64     8 bytes, its IEEE bits little-endian
##   seq, table  count (integer), then the elements (a table: key, value; in its iteration order)
##   object      its fields in declaration order (tuples too)
##   JNode       a tag byte (0 nil, 1 null, 2 false, 3 true, 4 int, 5 big, 6 float, 7 string, 8 array, 9 object),
##               then its value (array: count, elements; object: count, then key, value per field)

import std/[tables, sets]
import json

type
  SavedStateError* = object of ValueError

  Writer* = object
    buf*: string

  Reader* = object
    data*: string
    pos*: int
    depth: int

const MaxNodeDepth = 4200     ## (JSON read by the core is at most 4096 deep)

proc bad(msg: string) {.noreturn.} = raise newException(SavedStateError, "saved state: " & msg)

# ---------------------------------------------------------------- writing

proc putUint(w: var Writer, x: uint64) =
  var v = x
  while v >= 0x80'u64:
    w.buf.add char((v and 0x7f) or 0x80)
    v = v shr 7
  w.buf.add char(v)

proc put*(w: var Writer, x: int64) =
  w.putUint((cast[uint64](x) shl 1) xor (if x < 0: high(uint64) else: 0'u64))   # ZigZag
proc put*(w: var Writer, x: int) = w.put(int64(x))
proc put*(w: var Writer, x: bool) = w.buf.add(if x: '\x01' else: '\x00')
proc put*(w: var Writer, x: string) =
  w.put(x.len)
  w.buf.add x
proc put*(w: var Writer, x: float64) =
  let b = cast[uint64](x)
  for i in 0 ..< 8: w.buf.add char((b shr (8 * i)) and 0xff)

proc put*(w: var Writer, n: JNode) =
  if n == nil:
    w.buf.add '\x00'
    return
  case n.kind
  of jNull: w.buf.add '\x01'
  of jBool: w.buf.add(if n.b: '\x03' else: '\x02')
  of jInt:
    w.buf.add '\x04'
    w.put(n.i)
  of jBig:
    w.buf.add '\x05'
    w.put(n.big)
  of jFloat:
    w.buf.add '\x06'
    w.put(n.f)
  of jStr:
    w.buf.add '\x07'
    w.put(n.s)
  of jArr:
    w.buf.add '\x08'
    w.put(n.elems.len)
    for e in n.elems: w.put(e)
  of jObj:
    w.buf.add '\x09'
    w.put(n.fields.len)
    for (k, v) in n.fields:
      w.put(k)
      w.put(v)

proc put*[T](w: var Writer, x: seq[T]) =
  w.put(x.len)
  for e in x: w.put(e)
proc put*[K, V](w: var Writer, x: Table[K, V]) =
  w.put(x.len)
  for k, v in x:
    w.put(k)
    w.put(v)
proc put*[K, V](w: var Writer, x: OrderedTable[K, V]) =
  w.put(x.len)
  for k, v in x:
    w.put(k)
    w.put(v)
proc put*[T](w: var Writer, x: HashSet[T]) =
  w.put(x.len)
  for e in x: w.put(e)
proc put*[T: tuple | object](w: var Writer, x: T) =
  for _, v in fieldPairs(x): w.put(v)

# ---------------------------------------------------------------- reading

proc getUint(r: var Reader): uint64 =
  var shift = 0
  while true:
    if r.pos >= r.data.len: bad("ends inside a number")
    let b = uint64(ord(r.data[r.pos]))
    inc r.pos
    if shift == 63 and b > 1: bad("number too large")
    result = result or ((b and 0x7f) shl shift)
    if b < 0x80: return
    shift += 7
    if shift > 63: bad("number too long")

proc get*(r: var Reader, x: var int64) =
  let u = r.getUint()
  x = cast[int64](u shr 1) xor -cast[int64](u and 1)
proc get*(r: var Reader, x: var int) =
  var v: int64
  r.get(v)
  x = int(v)
proc count(r: var Reader): int =
  ## a length or a count: never more than the bytes left (each element takes at least one byte)
  var v: int64
  r.get(v)
  if v < 0 or v > int64(r.data.len - r.pos): bad("count out of range")
  int(v)
proc get*(r: var Reader, x: var bool) =
  if r.pos >= r.data.len: bad("ends inside a bool")
  case r.data[r.pos]
  of '\x00': x = false
  of '\x01': x = true
  else: bad("not a bool")
  inc r.pos
proc get*(r: var Reader, x: var string) =
  let n = r.count()
  x = r.data[r.pos ..< r.pos + n]
  r.pos += n
proc get*(r: var Reader, x: var float64) =
  if r.pos + 8 > r.data.len: bad("ends inside a float")
  var b = 0'u64
  for i in 0 ..< 8: b = b or (uint64(ord(r.data[r.pos + i])) shl (8 * i))
  r.pos += 8
  x = cast[float64](b)

proc get*(r: var Reader, n: var JNode) =
  if r.pos >= r.data.len: bad("ends inside a value")
  let tag = r.data[r.pos]
  inc r.pos
  case tag
  of '\x00': n = nil
  of '\x01': n = newNull()
  of '\x02': n = newBool(false)
  of '\x03': n = newBool(true)
  of '\x04':
    var i: int64
    r.get(i)
    n = newInt(i)
  of '\x05':
    n = JNode(kind: jBig)
    r.get(n.big)
  of '\x06':
    var f: float64
    r.get(f)
    n = newFloat(f)
  of '\x07':
    n = JNode(kind: jStr)
    r.get(n.s)
  of '\x08', '\x09':
    inc r.depth
    if r.depth > MaxNodeDepth: bad("nested too deep")
    let c = r.count()
    if tag == '\x08':
      n = JNode(kind: jArr, elems: newSeq[JNode](c))
      for i in 0 ..< c: r.get(n.elems[i])
    else:
      n = JNode(kind: jObj, fields: newSeq[(string, JNode)](c))
      for i in 0 ..< c:
        r.get(n.fields[i][0])
        r.get(n.fields[i][1])
    dec r.depth
  else: bad("unknown value tag " & $ord(tag))

proc get*[T](r: var Reader, x: var seq[T]) =
  let c = r.count()
  x = newSeq[T](c)
  for i in 0 ..< c: r.get(x[i])
proc get*[K, V](r: var Reader, x: var Table[K, V]) =
  let c = r.count()
  x = initTable[K, V](c)
  for _ in 0 ..< c:
    var k: K
    var v: V
    r.get(k)
    r.get(v)
    if x.hasKeyOrPut(k, v): bad("a key twice")
proc get*[K, V](r: var Reader, x: var OrderedTable[K, V]) =
  let c = r.count()
  x = initOrderedTable[K, V](c)
  for _ in 0 ..< c:
    var k: K
    var v: V
    r.get(k)
    r.get(v)
    if x.hasKeyOrPut(k, v): bad("a key twice")
proc get*[T](r: var Reader, x: var HashSet[T]) =
  let c = r.count()
  x = initHashSet[T](c)
  for _ in 0 ..< c:
    var e: T
    r.get(e)
    if x.containsOrIncl(e): bad("an element twice")
proc get*[T: tuple | object](r: var Reader, x: var T) =
  for _, v in fieldPairs(x): r.get(v)

proc done*(r: Reader) =
  ## everything read: bytes left over mean it was not what we wrote
  if r.pos != r.data.len: bad("bytes left over")
