## The server's own backups, encrypted with a key derived from the root key backup's passphrase (decision 0051,
## issue #28). `export-root-key` derives the key and keeps it sealed; `backup` encrypts with it; `open-backup` derives it
## again from the passphrase on any machine.

import kks/[json, crypto, util]

const
  BackupDomain = "kks-server-backup-v2\n"
  BackupIter* = 600_000
  MaxIter = 10 * BackupIter   ## a file can't make open-backup run for hours

proc aad(root: string, created: int64, salt: string, iter: int64): seq[byte] =
  ## the header is authenticated too: changing root, created, salt or iter fails the open
  toBytes(BackupDomain & root & "\n" & $created & "\n" & salt & "\n" & $iter)

proc deriveBackupKey*(p: Provider, passphrase: string, salt: seq[byte], iter = BackupIter): seq[byte] =
  p.pbkdf2Sha256(passphrase.toBytes, salt, iter, 32)

proc newBackupKeyRow*(p: Provider, passphrase: string): JNode =
  ## what the server keeps (sealed): the key, and the salt and count that make it again from the passphrase
  let salt = p.randomBytes(16)
  newObj(@[("salt", newStr(b64u(salt))), ("iter", newInt(BackupIter)),
           ("key", newStr(hex(p.deriveBackupKey(passphrase, salt))))])

proc sealBackup*(p: Provider, row: JNode, root: string, created: int64, bundle: string): string =
  let nonce = p.randomBytes(12)
  let ct = p.aesGcmSeal(unhex(row["key"].s), nonce, bundle.toBytes, aad(root, created, row["salt"].s, row["iter"].i))
  toText(newObj(@[("kks_server_backup", newInt(2)), ("root", newStr(root)), ("created", newInt(created)),
                  ("kdf", newStr("pbkdf2-sha256")), ("iter", row["iter"]), ("salt", row["salt"]),
                  ("nonce", newStr(b64u(nonce))), ("ct", newStr(b64u(ct)))]))

proc openBackup*(p: Provider, passphrase, text: string): string =
  ## -> the bundle; raises ValueError for anything that isn't a server backup, CryptoError for a wrong passphrase
  var d: JNode
  try: d = parseStrict(text)
  except JsonError: raise newException(ValueError, "not a Walkdown server backup")
  proc str(k: string): bool = d.get(k) != nil and d[k].isStr
  if d.kind != jObj or d.get("kks_server_backup") == nil or d["kks_server_backup"].kind != jInt or
     d["kks_server_backup"].i != 2 or not str("kdf") or d["kdf"].s != "pbkdf2-sha256" or not str("root") or
     d.get("created") == nil or d["created"].kind != jInt or d.get("iter") == nil or d["iter"].kind != jInt or
     d["iter"].i < BackupIter or d["iter"].i > MaxIter or not str("salt") or not str("nonce") or not str("ct"):
    raise newException(ValueError, "not a Walkdown server backup")
  var salt, nonce, ct: seq[byte]
  try:
    salt = unb64u(d["salt"].s)
    nonce = unb64u(d["nonce"].s)
    ct = unb64u(d["ct"].s)
  except CatchableError: raise newException(ValueError, "not a Walkdown server backup")
  if salt.len != 16 or nonce.len != 12: raise newException(ValueError, "not a Walkdown server backup")
  let k = p.deriveBackupKey(passphrase, salt, int(d["iter"].i))
  p.aesGcmOpen(k, nonce, ct, aad(d["root"].s, d["created"].i, d["salt"].s, d["iter"].i)).toStr
