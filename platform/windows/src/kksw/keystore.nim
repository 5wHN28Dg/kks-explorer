## The storage key (decision 0020) on Windows: 32 random bytes sealed with DPAPI for the Windows account
## (CryptProtectData), in a file next to the database. KKS_STORAGE_KEY_FILE names a plain key file instead (tests).

import std/os


type
  DataBlob = object       ## DATA_BLOB (wincrypt.h): DWORD cbData; BYTE *pbData
    cbData: uint32
    pbData: ptr UncheckedArray[byte]

proc CryptProtectData(inp: ptr DataBlob, desc: WideCString, entropy: ptr DataBlob, reserved, prompt: pointer,
                      flags: uint32, outp: ptr DataBlob): int32 {.importc, stdcall, dynlib: "crypt32.dll".}
proc CryptUnprotectData(inp: ptr DataBlob, desc: pointer, entropy: ptr DataBlob, reserved, prompt: pointer,
                        flags: uint32, outp: ptr DataBlob): int32 {.importc, stdcall, dynlib: "crypt32.dll".}
proc LocalFree(p: pointer): pointer {.importc, stdcall, dynlib: "kernel32.dll", discardable.}

const CRYPTPROTECT_UI_FORBIDDEN = 0x1'u32

type KeyStoreError* = object of CatchableError

proc blob(s: string): DataBlob =
  DataBlob(cbData: uint32(s.len), pbData: cast[ptr UncheckedArray[byte]](if s.len > 0: unsafeAddr s[0] else: nil))

proc storageKey*(folder: string, newKey: proc (): seq[byte]): seq[byte] =
  ## The 32-byte key for this data folder: unsealed from storage.key.dpapi, or made and sealed on first use.
  let plain = getEnv("KKS_STORAGE_KEY_FILE")
  if plain.len > 0:
    if not fileExists(plain):
      let k = newKey()
      var s = newString(k.len)
      for i, b in k: s[i] = char(b)
      writeFile(plain, s)
    for c in readFile(plain): result.add byte(c)
    if result.len != 32: raise newException(KeyStoreError, plain & " must hold 32 bytes")
    return
  let f = folder / "storage.key.dpapi"
  if fileExists(f):
    let sealed = readFile(f)
    var inp = blob(sealed)
    var outp: DataBlob
    if CryptUnprotectData(addr inp, nil, nil, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, addr outp) == 0:
      raise newException(KeyStoreError, "the storage key can't be unsealed (another Windows account?)")
    for i in 0 ..< int(outp.cbData): result.add outp.pbData[i]
    LocalFree(outp.pbData)
    if result.len != 32: raise newException(KeyStoreError, "the sealed storage key is damaged")
    return
  result = newKey()
  var s = newString(result.len)
  for i, b in result: s[i] = char(b)
  var inp = blob(s)
  var outp: DataBlob
  if CryptProtectData(addr inp, newWideCString("Walkdown storage key"), nil, nil, nil, CRYPTPROTECT_UI_FORBIDDEN, addr outp) == 0:
    raise newException(KeyStoreError, "DPAPI could not seal the storage key")
  var sealed = newString(int(outp.cbData))
  if sealed.len > 0: copyMem(addr sealed[0], outp.pbData, sealed.len)
  LocalFree(outp.pbData)
  createDir(folder)
  writeFile(f, sealed)
