## The crypto provider on GNOME/Linux: GnuTLS ≥ 3.8.2 (decision 0029). Hand-written bindings; the `header` pragma
## makes the C compiler check them against the installed headers.

import crypto

{.passL: "-lgnutls".}

const
  HG = "<gnutls/gnutls.h>"
  HC = "<gnutls/crypto.h>"
  HA = "<gnutls/abstract.h>"

type
  Datum {.importc: "gnutls_datum_t", header: HG.} = object
    data {.importc: "data".}: ptr UncheckedArray[byte]
    size {.importc: "size".}: cuint
  PrivKeyT {.importc: "gnutls_privkey_t", header: HA.} = pointer
  PubKeyT {.importc: "gnutls_pubkey_t", header: HA.} = pointer
  AeadT {.importc: "gnutls_aead_cipher_hd_t", header: HC.} = pointer
  CurveT {.importc: "gnutls_ecc_curve_t", header: HG.} = cint

var
  DIG_SHA256 {.importc: "GNUTLS_DIG_SHA256", header: HG, nodecl.}: cint
  MAC_SHA256 {.importc: "GNUTLS_MAC_SHA256", header: HG, nodecl.}: cint
  CURVE_P256 {.importc: "GNUTLS_ECC_CURVE_SECP256R1", header: HG, nodecl.}: cint
  SIGN_ECDSA_SHA256 {.importc: "GNUTLS_SIGN_ECDSA_SHA256", header: HG, nodecl.}: cint
  PK_ECDSA {.importc: "GNUTLS_PK_ECDSA", header: HG, nodecl.}: cint
  CURVE_ED25519 {.importc: "GNUTLS_ECC_CURVE_ED25519", header: HG, nodecl.}: cint
  SIGN_ED25519 {.importc: "GNUTLS_SIGN_EDDSA_ED25519", header: HG, nodecl.}: cint
  CIPHER_AES_256_GCM {.importc: "GNUTLS_CIPHER_AES_256_GCM", header: HG, nodecl.}: cint
  RND_RANDOM {.importc: "GNUTLS_RND_RANDOM", header: HC, nodecl.}: cint
  EXPORT_NO_LEADING_ZERO {.importc: "GNUTLS_EXPORT_FLAG_NO_LZ", header: HA, nodecl.}: cuint

proc hash_fast(alg: cint, text: pointer, len: csize_t, digest: pointer): cint
  {.importc: "gnutls_hash_fast", header: HC.}
proc hmac_fast(alg: cint, key: pointer, keylen: csize_t, text: pointer, len: csize_t, digest: pointer): cint
  {.importc: "gnutls_hmac_fast", header: HC.}
proc pbkdf2(mac: cint, key, salt: ptr Datum, iter: cuint, output: pointer, length: csize_t): cint
  {.importc: "gnutls_pbkdf2", header: HC.}
proc rnd(level: cint, data: pointer, len: csize_t): cint {.importc: "gnutls_rnd", header: HC.}
proc curveToBits(c: cint): cuint {.importc: "GNUTLS_CURVE_TO_BITS", header: HG.}
proc gfree(p: pointer) {.importc: "(gnutls_free)", header: HG.}

proc privkey_init(k: ptr PrivKeyT): cint {.importc: "gnutls_privkey_init", header: HA.}
proc privkey_deinit(k: PrivKeyT) {.importc: "gnutls_privkey_deinit", header: HA.}
proc privkey_import_ecc_raw(k: PrivKeyT, curve: cint, x, y, d: ptr Datum): cint
  {.importc: "gnutls_privkey_import_ecc_raw", header: HA.}
proc privkey_generate2(k: PrivKeyT, algo: cint, bits: cuint, flags: cuint, data: pointer, n: cuint): cint
  {.importc: "gnutls_privkey_generate2", header: HA.}
proc privkey_export_ecc_raw2(k: PrivKeyT, curve: ptr CurveT, x, y, d: ptr Datum, flags: cuint): cint
  {.importc: "gnutls_privkey_export_ecc_raw2", header: HA.}
proc privkey_sign_data(k: PrivKeyT, hash: cint, flags: cuint, data: ptr Datum, sig: ptr Datum): cint
  {.importc: "gnutls_privkey_sign_data", header: HA.}
proc privkey_derive_secret(k: PrivKeyT, pub: PubKeyT, nonce: ptr Datum, secret: ptr Datum, flags: cuint): cint
  {.importc: "gnutls_privkey_derive_secret", header: HA.}
proc pubkey_init(k: ptr PubKeyT): cint {.importc: "gnutls_pubkey_init", header: HA.}
proc pubkey_deinit(k: PubKeyT) {.importc: "gnutls_pubkey_deinit", header: HA.}
proc pubkey_import_ecc_raw(k: PubKeyT, curve: cint, x, y: ptr Datum): cint
  {.importc: "gnutls_pubkey_import_ecc_raw", header: HA.}
proc pubkey_verify_params(k: PubKeyT): cint {.importc: "gnutls_pubkey_verify_params", header: HA.}
proc pubkey_verify_data2(k: PubKeyT, algo: cint, flags: cuint, data, sig: ptr Datum): cint
  {.importc: "gnutls_pubkey_verify_data2", header: HA.}
proc aead_init(h: ptr AeadT, cipher: cint, key: ptr Datum): cint {.importc: "gnutls_aead_cipher_init", header: HC.}
proc aead_deinit(h: AeadT) {.importc: "gnutls_aead_cipher_deinit", header: HC.}
proc aead_encrypt(h: AeadT, nonce: pointer, nlen: csize_t, auth: pointer, alen: csize_t, tag: csize_t,
                  ptext: pointer, plen: csize_t, ctext: pointer, clen: ptr csize_t): cint
  {.importc: "gnutls_aead_cipher_encrypt", header: HC.}
proc aead_decrypt(h: AeadT, nonce: pointer, nlen: csize_t, auth: pointer, alen: csize_t, tag: csize_t,
                  ctext: pointer, clen: csize_t, ptext: pointer, plen: ptr csize_t): cint
  {.importc: "gnutls_aead_cipher_decrypt", header: HC.}

type GnuTlsProvider* = ref object of Provider

proc newGnuTlsProvider*(): GnuTlsProvider = GnuTlsProvider()

template adr(a: openArray[byte]): pointer =
  (if a.len == 0: nil else: unsafeAddr a[0])

proc datum(a: openArray[byte]): Datum =
  Datum(data: cast[ptr UncheckedArray[byte]](adr(a)), size: cuint(a.len))

proc fail(what: string, code: cint) {.raises: [CryptoError].} =
  raise newException(CryptoError, "gnutls " & what & ": " & $code)

proc takeDatum(d: var Datum): seq[byte] =
  result = newSeq[byte](d.size)
  for i in 0 ..< int(d.size): result[i] = d.data[i]
  gfree(d.data)

method sha256*(p: GnuTlsProvider, data: openArray[byte]): Digest =
  let r = hash_fast(DIG_SHA256, adr(data), csize_t(data.len), addr result[0])
  if r < 0: fail("hash", r)

method hmacSha256*(p: GnuTlsProvider, key, data: openArray[byte]): Digest =
  let r = hmac_fast(MAC_SHA256, adr(key), csize_t(key.len), adr(data), csize_t(data.len), addr result[0])
  if r < 0: fail("hmac", r)

method pbkdf2Sha256*(p: GnuTlsProvider, password, salt: openArray[byte], iterations, length: int): seq[byte] =
  var k = datum(password)
  var s = datum(salt)
  result = newSeq[byte](length)
  let r = pbkdf2(MAC_SHA256, addr k, addr s, cuint(iterations), addr result[0], csize_t(length))
  if r < 0: fail("pbkdf2", r)

proc importPub(pub: openArray[byte], k: var PubKeyT): bool =
  if pub.len != 65 or pub[0] != 4: return false
  if pubkey_init(addr k) < 0: return false
  var x = datum(pub.toOpenArray(1, 32))
  var y = datum(pub.toOpenArray(33, 64))
  if pubkey_import_ecc_raw(k, CURVE_P256, addr x, addr y) < 0 or pubkey_verify_params(k) < 0:
    pubkey_deinit(k)
    return false
  true

method p256Valid*(p: GnuTlsProvider, pub: openArray[byte]): bool =
  var k: PubKeyT
  if not importPub(pub, k): return false
  pubkey_deinit(k)
  true

proc importPriv(key: PrivateKey): PrivKeyT {.raises: [CryptoError].} =
  if key.scalar.len != 32 or key.pub.len != 65:
    raise newException(CryptoError, "private key needs the scalar and the public point")
  if privkey_init(addr result) < 0: fail("privkey_init", -1)
  var x = datum(key.pub.toOpenArray(1, 32))
  var y = datum(key.pub.toOpenArray(33, 64))
  var d = datum(key.scalar)
  let r = privkey_import_ecc_raw(result, CURVE_P256, addr x, addr y, addr d)
  if r < 0:
    privkey_deinit(result)
    fail("import private key", r)

proc pad32(b: seq[byte]): seq[byte] =
  result = newSeq[byte](32 - min(32, b.len))
  result.add b[max(0, b.len - 32) .. ^1]

method p256Generate*(p: GnuTlsProvider): PrivateKey =
  var k: PrivKeyT
  if privkey_init(addr k) < 0: fail("privkey_init", -1)
  defer: privkey_deinit(k)
  var r = privkey_generate2(k, PK_ECDSA, curveToBits(CURVE_P256), 0, nil, 0)
  if r < 0: fail("generate", r)
  var curve: CurveT
  var x, y, d: Datum
  r = privkey_export_ecc_raw2(k, addr curve, addr x, addr y, addr d, EXPORT_NO_LEADING_ZERO)
  if r < 0: fail("export", r)
  result.pub = @[4'u8] & pad32(takeDatum(x)) & pad32(takeDatum(y))
  result.scalar = pad32(takeDatum(d))

method p256Sign*(p: GnuTlsProvider, key: PrivateKey, msg: openArray[byte]): array[64, byte] =
  let k = importPriv(key)
  defer: privkey_deinit(k)
  var m = datum(msg)
  var sig: Datum
  let r = privkey_sign_data(k, DIG_SHA256, 0, addr m, addr sig)
  if r < 0: fail("sign", r)
  derToRs(takeDatum(sig))

method p256Verify*(p: GnuTlsProvider, pub, msg: openArray[byte], sig: array[64, byte]): bool =
  var k: PubKeyT
  if not importPub(pub, k): return false
  defer: pubkey_deinit(k)
  let der = rsToDer(sig)
  var m = datum(msg)
  var s = datum(der)
  pubkey_verify_data2(k, SIGN_ECDSA_SHA256, 0, addr m, addr s) >= 0

method p256Ecdh*(p: GnuTlsProvider, key: PrivateKey, peerPub: openArray[byte]): Digest =
  var pk: PubKeyT
  if not importPub(peerPub, pk): raise newException(CryptoError, "not a P-256 point")
  defer: pubkey_deinit(pk)
  let k = importPriv(key)
  defer: privkey_deinit(k)
  var secret: Datum
  let r = privkey_derive_secret(k, pk, nil, addr secret, 0)
  if r < 0: fail("derive", r)
  let s = pad32(takeDatum(secret))
  for i in 0 ..< 32: result[i] = s[i]

method aesGcmSeal*(p: GnuTlsProvider, key, nonce, plain, aad: openArray[byte]): seq[byte] =
  if key.len != 32 or nonce.len != 12: raise newException(CryptoError, "AES-256-GCM key/nonce size")
  var kd = datum(key)
  var h: AeadT
  var r = aead_init(addr h, CIPHER_AES_256_GCM, addr kd)
  if r < 0: fail("aead_init", r)
  defer: aead_deinit(h)
  result = newSeq[byte](plain.len + 16)
  var outLen = csize_t(result.len)
  r = aead_encrypt(h, adr(nonce), 12, adr(aad), csize_t(aad.len), 16, adr(plain), csize_t(plain.len),
                   addr result[0], addr outLen)
  if r < 0: fail("encrypt", r)
  result.setLen(int(outLen))

method aesGcmOpen*(p: GnuTlsProvider, key, nonce, sealed, aad: openArray[byte]): seq[byte] =
  if key.len != 32 or nonce.len != 12 or sealed.len < 16:
    raise newException(CryptoError, "AES-256-GCM sizes")
  var kd = datum(key)
  var h: AeadT
  var r = aead_init(addr h, CIPHER_AES_256_GCM, addr kd)
  if r < 0: fail("aead_init", r)
  defer: aead_deinit(h)
  result = newSeq[byte](max(1, sealed.len))
  var outLen = csize_t(result.len)
  r = aead_decrypt(h, adr(nonce), 12, adr(aad), csize_t(aad.len), 16, adr(sealed), csize_t(sealed.len),
                   addr result[0], addr outLen)
  if r < 0: raise newException(CryptoError, "AES-GCM: authentication failed")
  result.setLen(int(outLen))

method randomBytes*(p: GnuTlsProvider, n: int): seq[byte] =
  result = newSeq[byte](n)
  if n > 0:
    let r = rnd(RND_RANDOM, addr result[0], csize_t(n))
    if r < 0: fail("rnd", r)

proc ed25519Verify*(pub, sig, msg: openArray[byte]): bool =
  ## Ed25519 (RFC 8032) for the v1 keys of PROTOCOL-v2 §21a only; not part of the provider interface: only the server
  ## checks v1 signatures (decision 0042)
  if pub.len != 32 or sig.len != 64: return false
  var k: PubKeyT
  if pubkey_init(addr k) < 0: return false
  defer: pubkey_deinit(k)
  var x = datum(pub)
  if pubkey_import_ecc_raw(k, CURVE_ED25519, addr x, nil) < 0: return false
  var d = datum(msg)
  var sd = datum(sig)
  pubkey_verify_data2(k, SIGN_ED25519, 0, addr d, addr sd) >= 0
