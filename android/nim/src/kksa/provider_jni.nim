## The crypto provider on Android (decisions 0029, 0032): JCA through JNI. One callback, `NativeCrypto.call(op, …)` in
## Kotlin; the device key is an AndroidKeyStore key (PrivateKey.handle "ks:<alias>"), other keys are scalars.
import kks/crypto

proc kks_jc_call(op: cint, a: pointer, alen: cint, b: pointer, blen: cint, c: pointer, clen: cint, d: pointer,
                 dlen: cint, n1, n2: cint, outlen: ptr cint): ptr UncheckedArray[byte] {.importc, cdecl.}
proc free(p: pointer) {.importc, header: "<stdlib.h>".}

type JniProvider* = ref object of Provider

const
  OpSha256 = 1
  OpHmac = 2
  OpPbkdf2 = 3
  OpValid = 4
  OpGenerate = 5
  OpSign = 6
  OpVerify = 7
  OpEcdh = 8
  OpSeal = 9
  OpOpen = 10
  OpRandom = 11

proc pt(x: openArray[byte]): pointer = (if x.len > 0: unsafeAddr x[0] else: nil)

proc jcall(op: int, a: openArray[byte] = [], b: openArray[byte] = [], c: openArray[byte] = [], d: openArray[byte] = [],
           n1 = 0, n2 = 0): (bool, seq[byte]) =
  var n: cint
  let r = kks_jc_call(cint(op), pt(a), cint(a.len), pt(b), cint(b.len), pt(c), cint(c.len), pt(d), cint(d.len),
                      cint(n1), cint(n2), addr n)
  if r == nil: return (false, @[])
  var s = newSeq[byte](int(n))
  if n > 0: copyMem(addr s[0], r, int(n))
  free(r)
  (true, s)

proc need(r: (bool, seq[byte]), what: string): seq[byte] {.raises: [CryptoError].} =
  if not r[0]: raise newException(CryptoError, what & " failed (Java)")
  r[1]

proc toBytes(s: string): seq[byte] =
  result = newSeq[byte](s.len)
  for i, c in s: result[i] = byte(c)

method sha256*(p: JniProvider, data: openArray[byte]): Digest {.raises: [CryptoError].} =
  let r = need(jcall(OpSha256, data), "SHA-256")
  for i in 0 .. 31: result[i] = r[i]
method hmacSha256*(p: JniProvider, key, data: openArray[byte]): Digest {.raises: [CryptoError].} =
  let r = need(jcall(OpHmac, key, data), "HMAC-SHA256")
  for i in 0 .. 31: result[i] = r[i]
method pbkdf2Sha256*(p: JniProvider, password, salt: openArray[byte], iterations, length: int): seq[byte] {.raises: [CryptoError].} =
  need(jcall(OpPbkdf2, password, salt, n1 = iterations, n2 = length), "PBKDF2")
method p256Valid*(p: JniProvider, pub: openArray[byte]): bool {.raises: [].} =
  try:
    let r = jcall(OpValid, pub)
    r[0] and r[1].len == 1 and r[1][0] == 1
  except Exception: false
method p256Generate*(p: JniProvider): PrivateKey {.raises: [CryptoError].} =
  let r = need(jcall(OpGenerate), "P-256 key generation")
  PrivateKey(scalar: r[0 ..< 32], pub: r[32 ..< 97])
method p256Sign*(p: JniProvider, key: PrivateKey, msg: openArray[byte]): array[64, byte] {.raises: [CryptoError].} =
  let r = need(jcall(OpSign, key.scalar, toBytes(key.handle), msg), "ECDSA signing")
  for i in 0 .. 63: result[i] = r[i]
method p256Verify*(p: JniProvider, pub, msg: openArray[byte], sig: array[64, byte]): bool {.raises: [].} =
  try:
    let r = jcall(OpVerify, pub, msg, sig)
    r[0] and r[1].len == 1 and r[1][0] == 1
  except Exception: false
method p256Ecdh*(p: JniProvider, key: PrivateKey, peerPub: openArray[byte]): Digest {.raises: [CryptoError].} =
  let r = need(jcall(OpEcdh, key.scalar, toBytes(key.handle), peerPub), "ECDH")
  for i in 0 .. 31: result[i] = r[i]
method aesGcmSeal*(p: JniProvider, key: openArray[byte], nonce: openArray[byte], plain, aad: openArray[byte]): seq[byte] {.raises: [CryptoError].} =
  need(jcall(OpSeal, key, nonce, plain, aad), "AES-GCM sealing")
method aesGcmOpen*(p: JniProvider, key: openArray[byte], nonce: openArray[byte], sealed, aad: openArray[byte]): seq[byte] {.raises: [CryptoError].} =
  need(jcall(OpOpen, key, nonce, sealed, aad), "AES-GCM opening")
method randomBytes*(p: JniProvider, n: int): seq[byte] {.raises: [CryptoError].} =
  need(jcall(OpRandom, n1 = n), "random bytes")
