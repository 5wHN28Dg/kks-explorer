## Argon2id password hashes through OpenSSL ≥ 3.2 (decision 0023: m = 64 MiB, t = 3, p = 1; issue #40), stored in the PHC
## string format `$argon2id$v=19$m=65536,t=3,p=1$<salt>$<hash>` (standard base64, no padding). Server only. Hashes
## made with other parameters (19 MiB, t = 2 before #40; v1's scrypt) still verify and are replaced at the next login.

import std/[base64, strutils]

{.passL: "-lcrypto".}
const
  HP = "<openssl/params.h>"
  HK = "<openssl/kdf.h>"
  MemKiB* = 65536'u32
  Iter* = 3'u32
  Lanes* = 1'u32

type
  OsslParam {.importc: "OSSL_PARAM", header: HP.} = object
  Kdf {.importc: "EVP_KDF", header: HK, incompleteStruct.} = object
  KdfCtx {.importc: "EVP_KDF_CTX", header: HK, incompleteStruct.} = object
  Argon2Error* = object of CatchableError

proc OSSL_PARAM_construct_octet_string(key: cstring, buf: pointer, n: csize_t): OsslParam {.importc, header: HP.}
proc OSSL_PARAM_construct_uint32(key: cstring, v: ptr uint32): OsslParam {.importc, header: HP.}
proc OSSL_PARAM_construct_end(): OsslParam {.importc, header: HP.}
proc EVP_KDF_fetch(ctx: pointer, alg: cstring, props: cstring): ptr Kdf {.importc, header: HK.}
proc EVP_KDF_free(k: ptr Kdf) {.importc, header: HK.}
proc EVP_KDF_CTX_new(k: ptr Kdf): ptr KdfCtx {.importc, header: HK.}
proc EVP_KDF_CTX_free(c: ptr KdfCtx) {.importc, header: HK.}
proc EVP_KDF_derive(c: ptr KdfCtx, key: pointer, n: csize_t, params: ptr OsslParam): cint {.importc, header: HK.}

proc derive*(password, salt: string, mem = MemKiB, iter = Iter, lanes = Lanes, outLen = 32): string =
  let kdf = EVP_KDF_fetch(nil, "ARGON2ID", nil)
  if kdf == nil: raise newException(Argon2Error, "this OpenSSL has no Argon2id (needs 3.2 or newer)")
  defer: EVP_KDF_free(kdf)
  let ctx = EVP_KDF_CTX_new(kdf)
  defer: EVP_KDF_CTX_free(ctx)
  var m = mem
  var t = iter
  var l = lanes
  var threads = 1'u32
  var pw = password
  var sl = salt
  var params = [
    OSSL_PARAM_construct_octet_string("pass", (if pw.len > 0: addr pw[0] else: nil), csize_t(pw.len)),
    OSSL_PARAM_construct_octet_string("salt", addr sl[0], csize_t(sl.len)),
    OSSL_PARAM_construct_uint32("iter", addr t),
    OSSL_PARAM_construct_uint32("lanes", addr l),
    OSSL_PARAM_construct_uint32("memcost", addr m),
    OSSL_PARAM_construct_uint32("threads", addr threads),
    OSSL_PARAM_construct_end()]
  result = newString(outLen)
  if EVP_KDF_derive(ctx, addr result[0], csize_t(outLen), addr params[0]) != 1:
    raise newException(Argon2Error, "argon2id failed")

proc OSSL_PARAM_construct_uint64(key: cstring, v: ptr uint64): OsslParam {.importc, header: HP.}

proc scrypt*(password, salt: string, n: uint64, r, p: uint32, outLen: int): string =
  ## v1 password hashes (Python's hashlib.scrypt) are checked once, then replaced by Argon2id at that login.
  let kdf = EVP_KDF_fetch(nil, "SCRYPT", nil)
  if kdf == nil: raise newException(Argon2Error, "this OpenSSL has no scrypt")
  defer: EVP_KDF_free(kdf)
  let ctx = EVP_KDF_CTX_new(kdf)
  defer: EVP_KDF_CTX_free(ctx)
  var nn = n
  var rr = r
  var pp = p
  var pw = password
  var sl = salt
  var params = [
    OSSL_PARAM_construct_octet_string("pass", (if pw.len > 0: addr pw[0] else: nil), csize_t(pw.len)),
    OSSL_PARAM_construct_octet_string("salt", addr sl[0], csize_t(sl.len)),
    OSSL_PARAM_construct_uint64("n", addr nn),
    OSSL_PARAM_construct_uint32("r", addr rr),
    OSSL_PARAM_construct_uint32("p", addr pp),
    OSSL_PARAM_construct_end()]
  result = newString(outLen)
  if EVP_KDF_derive(ctx, addr result[0], csize_t(outLen), addr params[0]) != 1:
    raise newException(Argon2Error, "scrypt failed")

proc isLegacy*(stored: string): bool = stored.startsWith("scrypt$")

proc needsRehash*(stored: string): bool =
  ## not an Argon2id hash with today's parameters: replace it once the password is known (at a login)
  let parts = stored.split('$')
  stored.isLegacy or parts.len != 6 or parts[1] != "argon2id" or
    parts[3] != "m=" & $MemKiB & ",t=" & $Iter & ",p=" & $Lanes

proc b64(s: string): string = encode(s).strip(leading = false, chars = {'='})

proc hashPassword*(password, salt: string): string =
  ## `salt`: 16 random bytes from the caller's provider.
  "$argon2id$v=19$m=" & $MemKiB & ",t=" & $Iter & ",p=" & $Lanes & "$" & b64(salt) & "$" & b64(derive(password, salt))

proc checkPassword*(password, stored: string): bool =
  ## Constant-time compare; an empty `stored` costs the same as a real check.
  if stored.len == 0:
    discard derive("x", "0123456789abcdef")
    return false
  if stored.isLegacy:   # scrypt$N$r$p$salt-hex$dk-hex (v1)
    let f = stored.split('$')
    if f.len != 6: return false
    var salt, want = ""
    try:
      for i in countup(0, f[4].len - 2, 2): salt.add char(parseHexInt(f[4][i .. i + 1]))
      for i in countup(0, f[5].len - 2, 2): want.add char(parseHexInt(f[5][i .. i + 1]))
    except ValueError: return false
    let got = scrypt(password, salt, uint64(parseBiggestUInt(f[1])), uint32(parseUInt(f[2])), uint32(parseUInt(f[3])), want.len)
    var diff = 0
    for i in 0 ..< want.len: diff = diff or (ord(got[i]) xor ord(want[i]))
    return diff == 0
  let parts = stored.split('$')   # "", "argon2id", "v=19", "m=..,t=..,p=..", salt, hash
  if parts.len != 6 or parts[1] != "argon2id": return false
  var m, t, p = 0'u32
  for kv in parts[3].split(','):
    let x = kv.split('=')
    if x.len != 2: return false
    let v = uint32(parseUInt(x[1]))
    case x[0]
    of "m": m = v
    of "t": t = v
    of "p": p = v
    else: return false
  proc unb64(s: string): string = decode(s & repeat('=', (4 - s.len mod 4) mod 4))
  let salt = unb64(parts[4])
  let want = unb64(parts[5])
  let got = derive(password, salt, m, t, p, want.len)
  var diff = 0
  for i in 0 ..< want.len: diff = diff or (ord(got[i]) xor ord(want[i]))
  diff == 0 and got.len == want.len
