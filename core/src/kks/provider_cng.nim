## The crypto provider on Windows: CNG (decisions 0029, 0033), through a small C file (kks_cng.c) because CNG speaks in
## key blobs and cipher-info structs. Keys in a key storage provider are named by `handle`: "ncrypt:sw:<name>" (the
## Microsoft Software KSP) or "ncrypt:tpm:<name>" (the Platform Crypto Provider). Windows 10 or later.

import std/strutils
import crypto

{.compile: "kks_cng.c".}
{.passL: "-lbcrypt -lncrypt".}

proc c_sha256(d: pointer, n: culong, o: pointer): cint {.importc: "kks_sha256", cdecl.}
proc c_hmac(k: pointer, kn: culong, d: pointer, n: culong, o: pointer): cint {.importc: "kks_hmac_sha256", cdecl.}
proc c_pbkdf2(pw: pointer, pn: culong, s: pointer, sn: culong, iter: culonglong, o: pointer, on: culong): cint
  {.importc: "kks_pbkdf2_sha256", cdecl.}
proc c_random(o: pointer, n: culong): cint {.importc: "kks_random", cdecl.}
proc c_valid(pub: pointer): cint {.importc: "kks_p256_valid", cdecl.}
proc c_generate(pub, d: pointer): cint {.importc: "kks_p256_generate", cdecl.}
proc c_sign(pub, d, m: pointer, n: culong, sig: pointer): cint {.importc: "kks_p256_sign", cdecl.}
proc c_verify(pub, m: pointer, n: culong, sig: pointer): cint {.importc: "kks_p256_verify", cdecl.}
proc c_ecdh(pub, d, peer, o: pointer): cint {.importc: "kks_p256_ecdh", cdecl.}
proc c_seal(k, nonce, p: pointer, n: culong, aad: pointer, an: culong, o: pointer): cint {.importc: "kks_gcm_seal", cdecl.}
proc c_open(k, nonce, s: pointer, n: culong, aad: pointer, an: culong, o: pointer): cint {.importc: "kks_gcm_open", cdecl.}
proc c_nkey(prov: cint, name: WideCString, pub: pointer): cint {.importc: "kks_ncrypt_key", cdecl.}
proc c_nsign(prov: cint, name: WideCString, m: pointer, n: culong, sig: pointer): cint {.importc: "kks_ncrypt_sign", cdecl.}
proc c_ndelete(prov: cint, name: WideCString): cint {.importc: "kks_ncrypt_delete", cdecl.}

type CngProvider* = ref object of Provider

proc newCngProvider*(): CngProvider = CngProvider()

template adr(a: openArray[byte]): pointer =
  (if a.len == 0: nil else: unsafeAddr a[0])

proc fail(what: string) {.raises: [CryptoError].} = raise newException(CryptoError, "CNG " & what)

method sha256*(p: CngProvider, data: openArray[byte]): Digest =
  if c_sha256(adr(data), culong(data.len), addr result[0]) != 0: fail("sha256")

method hmacSha256*(p: CngProvider, key, data: openArray[byte]): Digest =
  if c_hmac(adr(key), culong(key.len), adr(data), culong(data.len), addr result[0]) != 0: fail("hmac")

method pbkdf2Sha256*(p: CngProvider, password, salt: openArray[byte], iterations, length: int): seq[byte] =
  result = newSeq[byte](length)
  if c_pbkdf2(adr(password), culong(password.len), adr(salt), culong(salt.len), culonglong(iterations),
              addr result[0], culong(length)) != 0: fail("pbkdf2")

method p256Valid*(p: CngProvider, pub: openArray[byte]): bool =
  # our own curve check first: CNG's import check is undocumented (and wine's accepts any point)
  p256OnCurve(pub) and c_valid(adr(pub)) == 1

method p256Generate*(p: CngProvider): PrivateKey =
  result.pub = newSeq[byte](65)
  result.scalar = newSeq[byte](32)
  if c_generate(addr result.pub[0], addr result.scalar[0]) != 0: fail("generate")

proc keyRef(handle: string): (cint, string) {.raises: [CryptoError].} =
  ## "ncrypt:sw:<name>" / "ncrypt:tpm:<name>" → (provider, name)
  let parts = handle.split(':', 2)
  if parts.len != 3 or parts[0] != "ncrypt" or parts[1] notin ["sw", "tpm"] or parts[2].len == 0:
    raise newException(CryptoError, "not a CNG key handle: " & handle)
  (cint(if parts[1] == "tpm": 1 else: 0), parts[2])

method p256Sign*(p: CngProvider, key: PrivateKey, msg: openArray[byte]): array[64, byte] =
  if key.scalar.len == 0 and key.handle.len > 0:
    let (prov, name) = keyRef(key.handle)
    if c_nsign(prov, newWideCString(name), adr(msg), culong(msg.len), addr result[0]) != 0: fail("sign (key store)")
    return
  if key.scalar.len != 32 or key.pub.len != 65: raise newException(CryptoError, "private key needs the scalar and the public point")
  if c_sign(unsafeAddr key.pub[0], unsafeAddr key.scalar[0], adr(msg), culong(msg.len), addr result[0]) != 0: fail("sign")

method p256Verify*(p: CngProvider, pub, msg: openArray[byte], sig: array[64, byte]): bool =
  if pub.len != 65 or pub[0] != 4: return false
  var s = sig
  c_verify(adr(pub), adr(msg), culong(msg.len), addr s[0]) == 1

method p256Ecdh*(p: CngProvider, key: PrivateKey, peerPub: openArray[byte]): Digest =
  if not p256OnCurve(peerPub): raise newException(CryptoError, "not a P-256 point")
  if key.scalar.len != 32 or key.pub.len != 65: raise newException(CryptoError, "ECDH needs the scalar")
  if c_ecdh(unsafeAddr key.pub[0], unsafeAddr key.scalar[0], adr(peerPub), addr result[0]) != 0: fail("ecdh")

method aesGcmSeal*(p: CngProvider, key, nonce, plain, aad: openArray[byte]): seq[byte] =
  if key.len != 32 or nonce.len != 12: raise newException(CryptoError, "AES-256-GCM key/nonce size")
  result = newSeq[byte](plain.len + 16)
  if c_seal(adr(key), adr(nonce), adr(plain), culong(plain.len), adr(aad), culong(aad.len), addr result[0]) != 0:
    fail("encrypt")

method aesGcmOpen*(p: CngProvider, key, nonce, sealed, aad: openArray[byte]): seq[byte] =
  if key.len != 32 or nonce.len != 12 or sealed.len < 16: raise newException(CryptoError, "AES-256-GCM sizes")
  result = newSeq[byte](max(1, sealed.len - 16))
  if c_open(adr(key), adr(nonce), adr(sealed), culong(sealed.len), adr(aad), culong(aad.len), addr result[0]) != 0:
    raise newException(CryptoError, "AES-GCM: authentication failed")
  result.setLen(sealed.len - 16)

method randomBytes*(p: CngProvider, n: int): seq[byte] =
  result = newSeq[byte](n)
  if n > 0 and c_random(addr result[0], culong(n)) != 0: fail("random")

# ---------------------------------------------------------------- the device key in a key store

proc storeKey*(p: CngProvider, tpm: bool, name: string): PrivateKey {.raises: [CryptoError].} =
  ## The named non-exportable P-256 key (made if missing) as a PrivateKey the provider signs with by handle.
  result.pub = newSeq[byte](65)
  let rc = c_nkey(cint(if tpm: 1 else: 0), newWideCString(name), addr result.pub[0])
  if rc != 0: raise newException(CryptoError, "CNG key store (" & (if tpm: "TPM" else: "software") & "): " & $rc)
  result.handle = "ncrypt:" & (if tpm: "tpm" else: "sw") & ":" & name

proc deleteStoreKey*(p: CngProvider, handle: string): bool =
  ## a removed device forgets its key (§15)
  try:
    let (prov, name) = keyRef(handle)
    c_ndelete(prov, newWideCString(name)) == 0
  except CryptoError: false
