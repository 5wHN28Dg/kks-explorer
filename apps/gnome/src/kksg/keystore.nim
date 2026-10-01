## The storage key (decision 0020) in the GNOME keyring through libsecret (decision 0031). For tests and headless
## runs, KKS_STORAGE_KEY_FILE names a key file instead (development only, like the server's storage_key_file).
import std/[os, base64]
{.compile: "kks_secret.c".}
proc kks_secret_lookup(folder: cstring): cstring {.importc, cdecl.}
proc kks_secret_store(folder, text: cstring): cint {.importc, cdecl.}
proc kks_secret_error(): cstring {.importc, cdecl.}
proc free(p: pointer) {.importc, header: "<stdlib.h>".}

type KeyStoreError* = object of CatchableError

proc storageKey*(folder: string, newKey: proc (): seq[byte]): seq[byte] =
  ## The 32-byte key for this data folder: read it, or make and store one on first use.
  let f = getEnv("KKS_STORAGE_KEY_FILE")
  if f.len > 0:
    if not fileExists(f):
      let k = newKey()
      var s = newString(k.len)
      for i, b in k: s[i] = char(b)
      writeFile(f, s)
      setFilePermissions(f, {fpUserRead, fpUserWrite})
    let raw = readFile(f)
    if raw.len != 32: raise newException(KeyStoreError, f & " must hold 32 bytes")
    for c in raw: result.add byte(c)
    return
  let p = kks_secret_lookup(folder.cstring)
  if p == nil:
    let err = $kks_secret_error()
    if err.len > 0: raise newException(KeyStoreError, "the keyring is not available: " & err)
    let k = newKey()
    var s = newString(k.len)
    for i, b in k: s[i] = char(b)
    if kks_secret_store(folder.cstring, encode(s).cstring) == 0:
      raise newException(KeyStoreError, "could not store the key in the keyring: " & $kks_secret_error())
    return k
  let txt = $p
  free(p)
  let raw = decode(txt)
  if raw.len != 32: raise newException(KeyStoreError, "the keyring holds a damaged storage key")
  for c in raw: result.add byte(c)
