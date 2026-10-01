## The crypto provider interface (decision 0029) and what stays in the core: low-S, HKDF, signature forms.
## Each platform supplies a provider (GnuTLS on GNOME/Linux, CNG on Windows, Java through JNI on Android).

type
  Digest* = array[32, byte]

  PrivateKey* = object
    ## A P-256 private key. `pub` is the 65-byte uncompressed point. `scalar` is empty when the key lives in a
    ## platform key store; the provider then signs by `handle`.
    scalar*: seq[byte]
    pub*: seq[byte]
    handle*: string

  CryptoError* = object of CatchableError

  Provider* = ref object of RootObj

method sha256*(p: Provider, data: openArray[byte]): Digest {.base, raises: [CryptoError].} =
  raise newException(CryptoError, "not implemented")
method hmacSha256*(p: Provider, key, data: openArray[byte]): Digest {.base, raises: [CryptoError].} =
  raise newException(CryptoError, "not implemented")
method pbkdf2Sha256*(p: Provider, password, salt: openArray[byte], iterations, length: int): seq[byte]
    {.base, raises: [CryptoError].} =
  raise newException(CryptoError, "not implemented")
method p256Valid*(p: Provider, pub: openArray[byte]): bool {.base, raises: [].} =
  ## True if `pub` is a 65-byte uncompressed point on P-256 (not the point at infinity).
  false
method p256Generate*(p: Provider): PrivateKey {.base, raises: [CryptoError].} =
  raise newException(CryptoError, "not implemented")
method p256Sign*(p: Provider, key: PrivateKey, msg: openArray[byte]): array[64, byte] {.base, raises: [CryptoError].} =
  ## ECDSA-SHA256 over msg, as r ‖ s (either s; the core normalizes).
  raise newException(CryptoError, "not implemented")
method p256Verify*(p: Provider, pub, msg: openArray[byte], sig: array[64, byte]): bool {.base, raises: [].} =
  false
method p256Ecdh*(p: Provider, key: PrivateKey, peerPub: openArray[byte]): Digest {.base, raises: [CryptoError].} =
  ## The x coordinate of key·peerPub.
  raise newException(CryptoError, "not implemented")
method aesGcmSeal*(p: Provider, key: openArray[byte], nonce: openArray[byte], plain, aad: openArray[byte]): seq[byte]
    {.base, raises: [CryptoError].} =
  ## AES-256-GCM: ciphertext ‖ 16-byte tag.
  raise newException(CryptoError, "not implemented")
method aesGcmOpen*(p: Provider, key: openArray[byte], nonce: openArray[byte], sealed, aad: openArray[byte]):
    seq[byte] {.base, raises: [CryptoError].} =
  ## Raises CryptoError when the tag doesn't verify.
  raise newException(CryptoError, "not implemented")
method randomBytes*(p: Provider, n: int): seq[byte] {.base, raises: [CryptoError].} =
  raise newException(CryptoError, "not implemented")

# ---------------------------------------------------------------- in the core

const
  N* = [0xFF'u8, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        0xBC, 0xE6, 0xFA, 0xAD, 0xA7, 0x17, 0x9E, 0x84, 0xF3, 0xB9, 0xCA, 0xC2, 0xFC, 0x63, 0x25, 0x51]
    ## The P-256 group order, big-endian.

proc cmp256(a, b: openArray[byte]): int =
  for i in 0 ..< 32:
    if a[i] != b[i]: return (if a[i] < b[i]: -1 else: 1)
  0

proc sub256(a, b: openArray[byte]): array[32, byte] =
  var borrow = 0
  for i in countdown(31, 0):
    var d = int(a[i]) - int(b[i]) - borrow
    borrow = 0
    if d < 0:
      d += 256
      borrow = 1
    result[i] = byte(d)

proc halfN(): array[32, byte] =
  ## floor(n / 2)
  var carry = 0
  for i in 0 ..< 32:
    let v = carry * 256 + int(N[i])
    result[i] = byte(v div 2)
    carry = v mod 2

const HalfN* = halfN()

proc isZero(a: openArray[byte]): bool =
  for x in a:
    if x != 0: return false
  true

proc lowS*(sig: array[64, byte]): array[64, byte] =
  ## s ← n − s when s > n/2 (PROTOCOL-v2 §2).
  result = sig
  if cmp256(sig.toOpenArray(32, 63), HalfN) > 0:
    let s = sub256(N, sig.toOpenArray(32, 63))
    for i in 0 ..< 32: result[32 + i] = s[i]

proc sigInRange*(sig: array[64, byte]): bool =
  ## 1 ≤ r < n and 1 ≤ s ≤ n/2.
  not isZero(sig.toOpenArray(0, 31)) and cmp256(sig.toOpenArray(0, 31), N) < 0 and
    not isZero(sig.toOpenArray(32, 63)) and cmp256(sig.toOpenArray(32, 63), HalfN) <= 0

proc highS*(sig: array[64, byte]): array[64, byte] =
  ## n − s (for tests: a valid ECDSA signature that §2 refuses).
  result = sig
  let s = sub256(N, sig.toOpenArray(32, 63))
  for i in 0 ..< 32: result[32 + i] = s[i]

proc hkdfSha256*(p: Provider, ikm, salt, info: openArray[byte], length: int): seq[byte] =
  ## RFC 5869 over the provider's HMAC.
  var s = @salt
  if s.len == 0: s = newSeq[byte](32)
  let prk = p.hmacSha256(s, ikm)
  var t: seq[byte]
  var i = 1'u8
  while result.len < length:
    var m = t
    m.add info
    m.add i
    let blk = p.hmacSha256(prk, m)
    t = @blk
    result.add t
    inc i
  result.setLen(length)

# ---------------------------------------------------------------- DER ↔ r ‖ s (for providers that speak DER)

proc derToRs*(der: openArray[byte]): array[64, byte] =
  ## ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER } → 64 bytes.
  var p = 0
  proc need(c: bool) =
    if not c: raise newException(CryptoError, "bad DER signature")
  need(der.len >= 8 and der[0] == 0x30)
  p = 2
  if der[1] >= 0x80: p = 2 + int(der[1] and 0x7F)
  for part in 0 .. 1:
    need(p + 2 <= der.len and der[p] == 0x02)
    let n = int(der[p + 1])
    p += 2
    need(p + n <= der.len and n >= 1)
    var start = p
    var len = n
    while len > 32 and der[start] == 0:
      inc start
      dec len
    need(len <= 32)
    for i in 0 ..< len: result[part * 32 + 32 - len + i] = der[start + i]
    p += n

proc rsToDer*(sig: array[64, byte]): seq[byte] =
  proc int32(b: openArray[byte]): seq[byte] =
    var i = 0
    while i < 31 and b[i] == 0: inc i
    result = @(b[i .. ^1])
    if (result[0] and 0x80) != 0: result.insert(0'u8, 0)
  let r = int32(sig.toOpenArray(0, 31))
  let s = int32(sig.toOpenArray(32, 63))
  result = @[0x30'u8, byte(4 + r.len + s.len), 0x02, byte(r.len)] & r & @[0x02'u8, byte(s.len)] & s

# ---------------------------------------------------------------- P-256 point check (for providers that don't validate)

type U256 = array[8, uint32]        ## little-endian 32-bit limbs

const
  P256P: U256 = [0xFFFFFFFF'u32, 0xFFFFFFFF'u32, 0xFFFFFFFF'u32, 0, 0, 0, 1, 0xFFFFFFFF'u32]
  P256B: U256 = [0x27D2604B'u32, 0x3BCE3C3E'u32, 0xCC53B0F6'u32, 0x651D06B0'u32, 0x769886BC'u32, 0xB3EBBD55'u32,
                 0xAA3A93E7'u32, 0x5AC635D8'u32]

proc fromBe(b: openArray[byte]): U256 =
  for i in 0 ..< 8:
    let o = 28 - i * 4
    result[i] = (uint32(b[o]) shl 24) or (uint32(b[o + 1]) shl 16) or (uint32(b[o + 2]) shl 8) or uint32(b[o + 3])

proc geq(a, b: U256): bool =
  for i in countdown(7, 0):
    if a[i] != b[i]: return a[i] > b[i]
  true

proc subU(a: var U256, b: U256) =
  var borrow = 0'i64
  for i in 0 ..< 8:
    var d = int64(a[i]) - int64(b[i]) - borrow
    borrow = 0
    if d < 0:
      d += 0x1_0000_0000
      borrow = 1
    a[i] = uint32(d)

proc addMod(a, b: U256): U256 =
  ## (a + b) mod p, for a, b < p
  var carry = 0'u64
  var extra = false
  for i in 0 ..< 8:
    let s = uint64(a[i]) + uint64(b[i]) + carry
    result[i] = uint32(s and 0xFFFFFFFF'u64)
    carry = s shr 32
  extra = carry != 0
  if extra or geq(result, P256P): subU(result, P256P)

proc mulMod(a, b: U256): U256 =
  ## (a · b) mod p by double-and-add over the bits of b (slow, fine for a validity check)
  for i in countdown(255, 0):
    result = addMod(result, result)
    if ((b[i div 32] shr uint32(i mod 32)) and 1) == 1: result = addMod(result, a)

proc p256OnCurve*(pub: openArray[byte]): bool =
  ## 65-byte uncompressed point with x, y < p and y² = x³ − 3x + b (mod p). The point at infinity has no such form.
  if pub.len != 65 or pub[0] != 4: return false
  let x = fromBe(pub.toOpenArray(1, 32))
  let y = fromBe(pub.toOpenArray(33, 64))
  if geq(x, P256P) or geq(y, P256P): return false
  let lhs = mulMod(y, y)
  var three: U256
  three = addMod(addMod(x, x), x)
  var rhs = mulMod(mulMod(x, x), x)
  # rhs − 3x mod p
  if geq(rhs, three): subU(rhs, three)
  else:
    var t = P256P
    subU(t, three)
    rhs = addMod(rhs, t)
  rhs = addMod(rhs, P256B)
  lhs == rhs
