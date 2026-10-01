## Strict JSON (PROTOCOL-v2 §1, decision 0029): a reader that refuses anything two implementations could read
## differently, and the canonical writer. Pure Nim, no I/O.

import std/[algorithm, math, parseutils, strutils]

type
  JKind* = enum
    jNull, jBool, jInt, jBig, jFloat, jStr, jArr, jObj

  JNode* = ref object
    case kind*: JKind
    of jNull: discard
    of jBool: b*: bool
    of jInt: i*: int64
    of jBig: big*: string          ## the integer's decimal text (outside ±(2^63 − 1))
    of jFloat: f*: float64
    of jStr: s*: string            ## UTF-8
    of jArr: elems*: seq[JNode]
    of jObj: fields*: seq[(string, JNode)]   ## input order; keys unique

  JsonError* = object of ValueError

const MaxDepth* = 128

# ---------------------------------------------------------------- construction and access

proc newNull*(): JNode = JNode(kind: jNull)
proc newBool*(b: bool): JNode = JNode(kind: jBool, b: b)
proc newInt*(i: int64): JNode = JNode(kind: jInt, i: i)
proc newFloat*(f: float64): JNode = JNode(kind: jFloat, f: f)
proc newStr*(s: string): JNode = JNode(kind: jStr, s: s)
proc newArr*(elems: seq[JNode] = @[]): JNode = JNode(kind: jArr, elems: elems)
proc newObj*(fields: seq[(string, JNode)] = @[]): JNode = JNode(kind: jObj, fields: fields)

proc has*(n: JNode, key: string): bool =
  if n.kind == jObj:
    for (k, _) in n.fields:
      if k == key: return true

proc get*(n: JNode, key: string): JNode =
  ## The value of `key`, or nil when absent (or when n is not an object).
  if n != nil and n.kind == jObj:
    for (k, v) in n.fields:
      if k == key: return v

proc `[]`*(n: JNode, key: string): JNode =
  result = n.get(key)
  if result == nil: raise newException(KeyError, "no key " & key)

proc `[]`*(n: JNode, i: int): JNode = n.elems[i]

proc `[]=`*(n: JNode, key: string, v: JNode) =
  for f in n.fields.mitems:
    if f[0] == key:
      f[1] = v
      return
  n.fields.add((key, v))

proc del*(n: JNode, key: string) =
  for i in 0 ..< n.fields.len:
    if n.fields[i][0] == key:
      n.fields.delete(i)
      return

proc len*(n: JNode): int =
  case n.kind
  of jArr: n.elems.len
  of jObj: n.fields.len
  of jStr: n.s.len
  else: 0

proc isNull*(n: JNode): bool = n == nil or n.kind == jNull
proc isStr*(n: JNode): bool = n != nil and n.kind == jStr
proc isInt*(n: JNode): bool = n != nil and n.kind == jInt
proc isNum*(n: JNode): bool = n != nil and n.kind in {jInt, jFloat}
proc num*(n: JNode): float64 =
  ## Integer or float as a float (courses use both).
  if n.kind == jInt: float64(n.i) else: n.f

proc copy*(n: JNode): JNode =
  if n == nil: return nil
  case n.kind
  of jArr:
    result = newArr()
    for e in n.elems: result.elems.add(copy(e))
  of jObj:
    result = newObj()
    for (k, v) in n.fields: result.fields.add((k, copy(v)))
  else:
    result = JNode()
    result[] = n[]

proc `==`*(a, b: JNode): bool =
  ## Structural equality; objects compare as key sets (order-free); an integer never equals a float.
  if a.isNil or b.isNil: return a.isNil and b.isNil
  if a.kind != b.kind: return false
  case a.kind
  of jNull: true
  of jBool: a.b == b.b
  of jInt: a.i == b.i
  of jBig: a.big == b.big
  of jFloat: a.f == b.f
  of jStr: a.s == b.s
  of jArr:
    if a.elems.len != b.elems.len: return false
    for i in 0 ..< a.elems.len:
      if a.elems[i] != b.elems[i]: return false
    true
  of jObj:
    if a.fields.len != b.fields.len: return false
    for (k, v) in a.fields:
      let w = b.get(k)
      if w == nil or w != v: return false
    true

# ---------------------------------------------------------------- strict reader

type Reader = object
  s: string
  p: int
  maxDepth: int

proc fail(r: Reader, msg: string) {.noreturn.} =
  raise newException(JsonError, msg & " at byte " & $r.p)

proc ws(r: var Reader) =
  while r.p < r.s.len and r.s[r.p] in {' ', '\t', '\n', '\r'}: inc r.p

proc expectWord(r: var Reader, w: string) =
  if r.s.continuesWith(w, r.p): r.p += w.len
  else: r.fail("bad literal")

proc addUtf8(res: var string, cp: int) =
  if cp < 0x80: res.add char(cp)
  elif cp < 0x800:
    res.add char(0xC0 or (cp shr 6)); res.add char(0x80 or (cp and 0x3F))
  elif cp < 0x10000:
    res.add char(0xE0 or (cp shr 12)); res.add char(0x80 or ((cp shr 6) and 0x3F)); res.add char(0x80 or (cp and 0x3F))
  else:
    res.add char(0xF0 or (cp shr 18)); res.add char(0x80 or ((cp shr 12) and 0x3F))
    res.add char(0x80 or ((cp shr 6) and 0x3F)); res.add char(0x80 or (cp and 0x3F))

proc hex4(r: var Reader): int =
  if r.p + 4 > r.s.len: r.fail("short \\u escape")
  result = 0
  for k in 0 ..< 4:
    let c = r.s[r.p + k]
    let d = case c
      of '0'..'9': ord(c) - ord('0')
      of 'a'..'f': ord(c) - ord('a') + 10
      of 'A'..'F': ord(c) - ord('A') + 10
      else: r.fail("bad \\u escape")
    result = result * 16 + d
  r.p += 4

proc utf8Char(r: var Reader, res: var string) =
  ## One raw multi-byte UTF-8 character: well-formed, shortest form, no surrogates, ≤ U+10FFFF.
  let b0 = ord(r.s[r.p])
  var n, cp, lo: int
  if b0 >= 0xC2 and b0 <= 0xDF: (n, cp, lo) = (1, b0 and 0x1F, 0x80)
  elif b0 >= 0xE0 and b0 <= 0xEF: (n, cp, lo) = (2, b0 and 0x0F, 0x800)
  elif b0 >= 0xF0 and b0 <= 0xF4: (n, cp, lo) = (3, b0 and 0x07, 0x10000)
  else: r.fail("not UTF-8")
  if r.p + n >= r.s.len: r.fail("truncated UTF-8")
  for k in 1 .. n:
    let b = ord(r.s[r.p + k])
    if (b and 0xC0) != 0x80: r.fail("not UTF-8")
    cp = (cp shl 6) or (b and 0x3F)
  if cp < lo or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF): r.fail("not UTF-8")
  res.add r.s[r.p .. r.p + n]
  r.p += n + 1

proc str(r: var Reader): string =
  inc r.p   # opening quote
  while true:
    if r.p >= r.s.len: r.fail("unclosed string")
    let c = r.s[r.p]
    if c == '"':
      inc r.p
      return
    elif c == '\\':
      inc r.p
      if r.p >= r.s.len: r.fail("unclosed string")
      let e = r.s[r.p]
      inc r.p
      case e
      of '"': result.add '"'
      of '\\': result.add '\\'
      of '/': result.add '/'
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'u':
        var cp = r.hex4()
        if cp >= 0xDC00 and cp <= 0xDFFF: r.fail("unpaired surrogate")
        if cp >= 0xD800 and cp <= 0xDBFF:
          if not r.s.continuesWith("\\u", r.p): r.fail("unpaired surrogate")
          r.p += 2
          let lo = r.hex4()
          if lo < 0xDC00 or lo > 0xDFFF: r.fail("unpaired surrogate")
          cp = 0x10000 + ((cp - 0xD800) shl 10) + (lo - 0xDC00)
        result.addUtf8(cp)
      else: r.fail("bad escape")
    elif ord(c) < 0x20: r.fail("raw control character")
    elif ord(c) < 0x80:
      result.add c
      inc r.p
    else:
      r.utf8Char(result)

proc number(r: var Reader): JNode =
  let start = r.p
  if r.s[r.p] == '-': inc r.p
  if r.p >= r.s.len or r.s[r.p] notin Digits: r.fail("bad number")
  if r.s[r.p] == '0':
    inc r.p
    if r.p < r.s.len and r.s[r.p] in Digits: r.fail("leading zero")
  else:
    while r.p < r.s.len and r.s[r.p] in Digits: inc r.p
  var isFloat = false
  if r.p < r.s.len and r.s[r.p] == '.':
    isFloat = true
    inc r.p
    if r.p >= r.s.len or r.s[r.p] notin Digits: r.fail("bad fraction")
    while r.p < r.s.len and r.s[r.p] in Digits: inc r.p
  if r.p < r.s.len and r.s[r.p] in {'e', 'E'}:
    isFloat = true
    inc r.p
    if r.p < r.s.len and r.s[r.p] in {'+', '-'}: inc r.p
    if r.p >= r.s.len or r.s[r.p] notin Digits: r.fail("bad exponent")
    while r.p < r.s.len and r.s[r.p] in Digits: inc r.p
  let text = r.s[start ..< r.p]
  if isFloat:
    var f: float64
    if parseBiggestFloat(text, f) != text.len: r.fail("bad number")
    return newFloat(f)
  var v: BiggestInt
  var ok = false
  try:
    ok = parseBiggestInt(text, v) == text.len
  except ValueError:
    ok = false
  if ok and v != low(int64):
    return newInt(v)
  return JNode(kind: jBig, big: text)

proc value(r: var Reader, depth: int): JNode

proc container(r: var Reader, depth: int, isObj: bool): JNode =
  if depth + 1 > r.maxDepth: r.fail("too deep")
  inc r.p
  result = if isObj: newObj() else: newArr()
  r.ws()
  let close = if isObj: '}' else: ']'
  if r.p < r.s.len and r.s[r.p] == close:
    inc r.p
    return
  while true:
    r.ws()
    if isObj:
      if r.p >= r.s.len or r.s[r.p] != '"': r.fail("expected a key")
      let k = r.str()
      for (kk, _) in result.fields:
        if kk == k: r.fail("duplicate key")
      r.ws()
      if r.p >= r.s.len or r.s[r.p] != ':': r.fail("expected ':'")
      inc r.p
      r.ws()
      result.fields.add((k, r.value(depth + 1)))
    else:
      r.ws()
      result.elems.add(r.value(depth + 1))
    r.ws()
    if r.p >= r.s.len: r.fail("unclosed container")
    if r.s[r.p] == ',':
      inc r.p
      continue
    if r.s[r.p] == close:
      inc r.p
      return
    r.fail("expected ',' or close")

proc value(r: var Reader, depth: int): JNode =
  if r.p >= r.s.len: r.fail("expected a value")
  case r.s[r.p]
  of '{': r.container(depth, true)
  of '[': r.container(depth, false)
  of '"': newStr(r.str())
  of 't': r.expectWord("true"); newBool(true)
  of 'f': r.expectWord("false"); newBool(false)
  of 'n': r.expectWord("null"); newNull()
  of '-', '0'..'9': r.number()
  else: r.fail("unexpected character")

proc parseStrict*(data: string, maxDepth = MaxDepth): JNode =
  ## Reads one JSON value from UTF-8 bytes with the strict rules of PROTOCOL-v2 §1. Raises JsonError.
  ## `maxDepth` above 128 is only for local files such as test vectors.
  if data.len >= 3 and data[0] == '\xEF' and data[1] == '\xBB' and data[2] == '\xBF':
    raise newException(JsonError, "byte-order mark")
  var r = Reader(s: data, p: 0, maxDepth: maxDepth)
  r.ws()
  result = r.value(0)
  r.ws()
  if r.p != r.s.len: r.fail("bytes after the value")

# ---------------------------------------------------------------- writers

proc escapeInto(res: var string, s: string) =
  res.add '"'
  for c in s:
    case c
    of '"': res.add "\\\""
    of '\\': res.add "\\\\"
    of '\b': res.add "\\b"
    of '\f': res.add "\\f"
    of '\n': res.add "\\n"
    of '\r': res.add "\\r"
    of '\t': res.add "\\t"
    of '\0'..'\x07', '\x0B', '\x0E'..'\x1F':
      res.add "\\u00"
      res.add toHex(ord(c), 2).toLowerAscii
    else: res.add c
  res.add '"'

proc keyOk*(k: string): bool =
  ## Canonical keys: [a-z_][a-z0-9_]{0,31}.
  if k.len < 1 or k.len > 32: return false
  if k[0] notin {'a'..'z', '_'}: return false
  for c in k:
    if c notin {'a'..'z', '0'..'9', '_'}: return false
  true

const MaxInt53* = 9007199254740991'i64

type CanonicalError* = object of ValueError

proc canonInto(res: var string, n: JNode, where: string) =
  case n.kind
  of jNull: res.add "null"
  of jBool: res.add(if n.b: "true" else: "false")
  of jInt:
    if n.i > MaxInt53 or n.i < -MaxInt53:
      raise newException(CanonicalError, "integer out of range at " & where)
    res.add $n.i
  of jBig: raise newException(CanonicalError, "integer out of range at " & where)
  of jFloat: raise newException(CanonicalError, "float at " & where)
  of jStr: res.escapeInto(n.s)
  of jArr:
    res.add '['
    for i, e in n.elems:
      if i > 0: res.add ','
      res.canonInto(e, where & "[" & $i & "]")
    res.add ']'
  of jObj:
    var keys: seq[string]
    for (k, _) in n.fields:
      if not keyOk(k): raise newException(CanonicalError, "bad key " & k & " at " & where)
      keys.add k
    keys.sort(system.cmp)   # ASCII keys: byte order = code point order
    res.add '{'
    for i, k in keys:
      if i > 0: res.add ','
      res.escapeInto(k)
      res.add ':'
      res.canonInto(n.get(k), where & "." & k)
    res.add '}'

proc canonical*(n: JNode): string =
  ## Canonical JSON bytes (PROTOCOL-v2 §1). Raises CanonicalError for anything §1 can't carry.
  result.canonInto(n, "value")

proc checkCanonical*(n: JNode): bool =
  try:
    discard canonical(n)
    true
  except CanonicalError:
    false

proc floatText(f: float64): string =
  ## Shortest round-trip text for a finite float (Nim's `$` is shortest round-trip).
  if f == trunc(f) and abs(f) < 1e15: $int64(f) & ".0" else: $f

proc toText*(n: JNode): string =
  ## Plain JSON (floats allowed, key order kept), for files that aren't canonical (courses, figures).
  case n.kind
  of jNull: "null"
  of jBool: (if n.b: "true" else: "false")
  of jInt: $n.i
  of jBig: n.big
  of jFloat: floatText(n.f)
  of jStr:
    var s = ""
    s.escapeInto(n.s)
    s
  of jArr:
    var s = "["
    for i, e in n.elems:
      if i > 0: s.add ','
      s.add toText(e)
    s & "]"
  of jObj:
    var s = "{"
    for i, (k, v) in n.fields:
      if i > 0: s.add ','
      s.escapeInto(k)
      s.add ':'
      s.add toText(v)
    s & "}"

proc `$`*(n: JNode): string = toText(n)
