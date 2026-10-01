## Protocol v2 §1–7 (docs/PROTOCOL-v2.md): keys and peer IDs, signed log entries, chains, the hybrid logical clock
## and the total order. A check-for-check port of ref/proto2.py; the vectors in ref/vectors/v2-core.json decide.

import std/algorithm
import json, crypto, util

const
  Version* = 2
  Domain* = "kks-log-v2\n"
  SkewMs* = 86_400_000'i64
  BaseFields = ["v", "peer", "seq", "prev", "hlc", "type", "body"]

type ProtocolError* = object of CatchableError
  code*: string

proc perr*(code: string, msg = ""): ref ProtocolError =
  result = newException(ProtocolError, if msg.len > 0: code & ": " & msg else: code)
  result.code = code

# ---------------------------------------------------------------- patterns

proc isB64uOf(s: string, n: int): bool =
  if s.len != n: return false
  for c in s:
    if c notin {'A'..'Z', 'a'..'z', '0'..'9', '-', '_'}: return false
  true

proc isPeer*(s: string): bool = isB64uOf(s, 32)
proc isHex64*(s: string): bool =
  if s.len != 64: return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}: return false
  true

# ---------------------------------------------------------------- §1

proc canon*(n: JNode): string =
  ## Canonical JSON, or bad_encoding.
  try: canonical(n)
  except CanonicalError as e: raise perr("bad_encoding", e.msg)

# ---------------------------------------------------------------- §2

proc keyString*(pub: openArray[byte]): string = b64u(pub)

proc peerIdOfKey*(p: Provider, keyStr: string): string =
  let d = p.sha256(unb64u(keyStr))
  b64u(d.toOpenArray(0, 23))

proc peerId*(p: Provider, key: PrivateKey): string = p.peerIdOfKey(keyString(key.pub))

proc publicKey*(p: Provider, keyStr: string): seq[byte] =
  ## The 65 key bytes; raises ValueError unless keyStr is a valid uncompressed P-256 point (§2).
  if not isB64uOf(keyStr, 87): raise newException(ValueError, "key string")
  result = unb64u(keyStr)
  if result.len != 65 or result[0] != 4: raise newException(ValueError, "not an uncompressed point")
  if not p.p256Valid(result): raise newException(ValueError, "not on the curve")

proc sign*(p: Provider, key: PrivateKey, data: string): string =
  ## 64-byte r ‖ s, low-S, base64url.
  b64u(lowS(p.p256Sign(key, data.toBytes)))

proc verify*(p: Provider, keyStr, data, sig: string): bool =
  try:
    if not isB64uOf(sig, 86): return false
    let raw = unb64u(sig)
    if raw.len != 64: return false
    var s: array[64, byte]
    for i in 0 ..< 64: s[i] = raw[i]
    if not sigInRange(s): return false
    let pub = p.publicKey(keyStr)
    p.p256Verify(pub, data.toBytes, s)
  except ValueError:
    false

# ---------------------------------------------------------------- §3

proc unsignedCopy*(e: JNode): JNode =
  result = newObj()
  for (k, v) in e.fields:
    if k != "sig": result.fields.add((k, v))

proc signedBytes*(e: JNode): string = Domain & canon(unsignedCopy(e))

proc entryId*(p: Provider, e: JNode): string = hex(p.sha256(canon(unsignedCopy(e)).toBytes))

proc isIntKind(n: JNode): bool = n != nil and n.kind == jInt

proc checkFields*(e: JNode, signed = true) =
  if e == nil or e.kind != jObj: raise perr("bad_fields", "not an object")
  var want = @BaseFields
  if signed: want.add "sig"
  let sq = e.get("seq")
  if isIntKind(sq) and sq.i == 1: want.add "key"
  if e.len != want.len: raise perr("bad_fields", "field set")
  for w in want:
    if not e.has(w): raise perr("bad_fields", "field set")
  discard canon(e)
  let v = e["v"]
  if not isIntKind(v) or v.i != Version: raise perr("bad_version")
  if not (e["peer"].isStr and isPeer(e["peer"].s)): raise perr("bad_fields", "peer")
  if not isIntKind(e["seq"]) or e["seq"].i < 1: raise perr("bad_seq")
  let prev = e["prev"]
  if e["seq"].i == 1:
    if not prev.isNull: raise perr("bad_prev", "seq 1 must have prev null")
  elif not (prev.isStr and isHex64(prev.s)): raise perr("bad_prev")
  let h = e["hlc"]
  if not (h.kind == jArr and h.len == 2 and isIntKind(h[0]) and h[0].i >= 0 and isIntKind(h[1]) and h[1].i >= 0):
    raise perr("bad_fields", "hlc")
  if not (e["type"].isStr and keyOk(e["type"].s)): raise perr("bad_fields", "type")
  if e["body"].kind != jObj: raise perr("bad_fields", "body")
  if signed and not e["sig"].isStr: raise perr("bad_fields", "sig")
  if e["seq"].i == 1 and not e["key"].isStr: raise perr("bad_fields", "key")

proc checkKey*(p: Provider, e: JNode) =
  try: discard p.publicKey(e["key"].s)
  except ValueError: raise perr("bad_key", "not a valid P-256 key")
  if p.peerIdOfKey(e["key"].s) != e["peer"].s: raise perr("bad_key", "peer is not the key's peer ID")

proc makeEntry*(p: Provider, key: PrivateKey, seq: int64, prev: string, hlc: (int64, int64), typ: string,
                body: JNode): JNode =
  result = newObj(@[("v", newInt(Version)), ("peer", newStr(p.peerId(key))), ("seq", newInt(seq)),
                  ("prev", if prev.len == 0: newNull() else: newStr(prev)),
                  ("hlc", newArr(@[newInt(hlc[0]), newInt(hlc[1])])), ("type", newStr(typ)), ("body", body)])
  if seq == 1: result["key"] = newStr(keyString(key.pub))
  checkFields(result, signed = false)
  result["sig"] = newStr(p.sign(key, signedBytes(result)))

proc verifyEntry*(p: Provider, e: JNode, chainKey = "") =
  ## Raises ProtocolError unless e is valid and correctly signed. Seq 1 carries its own key; later entries need
  ## `chainKey` (the device's seq-1 key).
  checkFields(e)
  var key = chainKey
  if e["seq"].i == 1:
    p.checkKey(e)
    key = e["key"].s
  if key.len == 0: raise perr("chain_gap", "no seq-1 entry to verify against")
  if not p.verify(key, signedBytes(e), e["sig"].s): raise perr("bad_sig")

# ---------------------------------------------------------------- §4

proc verifyChain*(p: Provider, entries: seq[JNode]): seq[JNode] =
  ## Entries of ONE device, any order. Returns them sorted by seq.
  for e in entries: checkFields(e)
  for e in entries:
    if e["peer"].s != entries[0]["peer"].s: raise perr("bad_fields", "entries from more than one device")
  var firstIds: seq[string]
  var first: JNode
  for e in entries:
    if e["seq"].i == 1:
      let id = p.entryId(e)
      if id notin firstIds:
        firstIds.add id
        p.checkKey(e)
        if first == nil: first = e
  if firstIds.len > 1: raise perr("fork", "seq 1")
  let key = if first != nil: first["key"].s else: ""
  var bySeq: seq[(int64, JNode)]
  for e in entries:
    p.verifyEntry(e, key)
    var dup = false
    for (s, other) in bySeq:
      if s == e["seq"].i:
        dup = true
        if p.entryId(other) != p.entryId(e): raise perr("fork", "seq " & $s)
    if not dup: bySeq.add((e["seq"].i, e))
  bySeq.sort(proc (a, b: (int64, JNode)): int = cmp(a[0], b[0]))
  for i, (s, e) in bySeq:
    if s != int64(i + 1): raise perr("chain_gap", "missing seq " & $(i + 1))
    if i > 0 and e["prev"].s != p.entryId(bySeq[i - 1][1]): raise perr("chain_prev", "seq " & $s)
    result.add e

# ---------------------------------------------------------------- §5

type Hlc* = object
  l*, c*: int64

proc now*(h: var Hlc, wall: int64): (int64, int64) =
  if wall > h.l:
    h.l = wall
    h.c = 0
  else:
    inc h.c
  (h.l, h.c)

proc recv*(h: var Hlc, remote: (int64, int64), wall: int64): (int64, int64) =
  let (rl, rc) = remote
  if rl > wall + SkewMs: return (h.l, h.c)
  let L = max(max(h.l, rl), wall)
  var c: int64
  if L == h.l and L == rl: c = max(h.c, rc) + 1
  elif L == h.l: c = h.c + 1
  elif L == rl: c = rc + 1
  else: c = 0
  h.l = L
  h.c = c
  (h.l, h.c)

# ---------------------------------------------------------------- §6

proc orderCmp*(a, b: JNode): int =
  ## (hlc[0], hlc[1], peer, seq); peers compare by code point (ASCII).
  result = cmp(a["hlc"][0].i, b["hlc"][0].i)
  if result == 0: result = cmp(a["hlc"][1].i, b["hlc"][1].i)
  if result == 0: result = cmp(a["peer"].s, b["peer"].s)
  if result == 0: result = cmp(a["seq"].i, b["seq"].i)

proc privateKeyFromHex*(scalarHex, keyStr: string): PrivateKey =
  PrivateKey(scalar: unhex(scalarHex), pub: unb64u(keyStr))

export ProtocolError
