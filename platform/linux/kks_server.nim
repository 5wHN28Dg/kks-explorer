## kks-server: the always-on peer for browser clients (M6, decisions 0026, 0030).
##   kks-server [serve] [--config F]
##   kks-server users | reset-password --user NAME | reset-manager --user NAME | setup-link
##   kks-server publish-data DIR | backup --out FILE
##   kks-server v1-status                    which old-app phones have moved (decision 0042)
##   kks-server export-root-key --out FILE   (passphrase in $KKS_ROOT_PASSPHRASE, 12+ characters): the plant root key,
##     sealed with the passphrase (decision 0023), the same file the apps' "Restore from a backup" reads
## The storage key (decision 0020) comes from systemd-creds: LoadCredentialEncrypted=kks-storage-key:… in the unit
## ($CREDENTIALS_DIRECTORY/kks-storage-key). For development, `storage_key_file` in the config (created if missing).

import std/[asyncdispatch, os, posix, strutils, tables, times]
import kks/[json, util, crypto, node, replay, plantdata, bundle, provider_gnutls, extras]
import kksl/[server, dbstore]

proc storageKey(cfgPath: string, p: Provider): seq[byte] =
  let credDir = getEnv("CREDENTIALS_DIRECTORY")
  if credDir.len > 0 and fileExists(credDir / "kks-storage-key"):
    let raw = readFile(credDir / "kks-storage-key")
    if raw.len != 32: quit "the kks-storage-key credential must be 32 bytes"
    return raw.toBytes
  var keyFile = ""
  if cfgPath.len > 0 and fileExists(cfgPath):
    let j = parseStrict(readFile(cfgPath))
    if j.get("storage_key_file") != nil and j["storage_key_file"].isStr: keyFile = j["storage_key_file"].s
  if keyFile.len == 0: quit "no storage key: run under systemd with LoadCredentialEncrypted=kks-storage-key, or set storage_key_file in the config (development)"
  if not fileExists(keyFile):
    stderr.writeLine "warning: creating a storage key file at " & keyFile & " (development only; production seals it with systemd-creds)"
    createDir(parentDir(keyFile))
    writeFile(keyFile, p.randomBytes(32).toStr)
    discard chmod(keyFile.cstring, 0o600)
  let raw = readFile(keyFile)
  if raw.len != 32: quit "the storage key file must be 32 bytes"
  raw.toBytes

proc main() =
  var cfgPath = getEnv("KKS_CONFIG", "config-server.json")
  var cmd = "serve"
  var args: Table[string, string]
  var rest: seq[string]
  var i = 1
  while i <= paramCount():
    let a = paramStr(i)
    if a.startsWith("--") and i < paramCount():
      args[a[2 .. ^1]] = paramStr(i + 1)
      inc i
    elif cmd == "serve" and i == 1: cmd = a
    else: rest.add a
    inc i
  if "config" in args: cfgPath = args["config"]
  var cfg = loadConfig(cfgPath)
  let here = getAppDir()
  if cfg.webDir.len == 0: cfg.webDir = here / "web"
  if cfg.dataDir.len == 0: cfg.dataDir = here / "data"
  if cfg.storePath.len == 0: cfg.storePath = "kks-server.db"
  let p = newGnuTlsProvider()
  let s = openServer(cfg, p, storageKey(cfgPath, p))
  case cmd
  of "serve":
    let l = s.setupLink()
    if l.len > 0: echo "No manager yet. Open this link once to create the manager (valid 7 days):\n  ", l
    echo "Walkdown server on http://", cfg.address, ":", cfg.port, (if cfg.syncPort > 0: ", sync port " & $cfg.syncPort else: "")
    asyncCheck s.serve()
    runForever()
  of "setup-link":
    let l = s.setupLink()
    echo(if l.len > 0: l else: "The plant has a manager; use reset-manager to change it.")
  of "users":
    for (_, u) in s.store.allRows("users"):
      echo u["id"].i, "  ", u["username"].s.alignLeft(20), " ", (if s.n.run != nil: s.n.run.role(u["person"].s) else: "?").alignLeft(8),
           " ", (if u["active"].b: "active" else: "inactive"), "  ", u["full_name"].s
  of "publish-data":
    if rest.len != 1: quit "usage: kks-server publish-data DIR"
    var v: int
    try: v = s.publishDir(rest[0])
    except ValueError as e: quit e.msg
    echo(if v == 0: "Unchanged: the files equal the latest version." else: "Published plant data version " & $v & ".")
  of "v1-status":
    # decision 0042: which old-app (KKS Explorer) phones have moved to Walkdown, and which haven't yet
    let w = s.v1Waiting()
    var moved = 0
    for (_, _) in s.store.allRows("v1_moved"): inc moved
    echo "moved to Walkdown: ", moved, "; still on the old app: ", w.elems.len
    for x in w.elems: echo "  ", x["name"].s, "  (old device ", x["v1_device"].s[0 ..< 8], "…)"
  of "export-root-key":
    if "out" notin args: quit "usage: KKS_ROOT_PASSPHRASE=… kks-server export-root-key --out FILE"
    let pass = getEnv("KKS_ROOT_PASSPHRASE")
    if pass.len < 12: quit "set KKS_ROOT_PASSPHRASE to a passphrase of 12 characters or more"
    let k = s.store.getRow("keys", "root")
    if k == nil: quit "this server holds no root key"
    let sealed = p.passphraseSeal(pass, toText(k).toBytes)
    let doc = newObj(@[("kks_root_backup", newInt(2)), ("plant", s.n.run.settings.getOrDefault("plant")),
                       ("root", newStr(s.n.root)), ("sealed", sealed)])
    # check it opens before calling it a backup
    if p.passphraseOpen(pass, doc["sealed"]).toStr != toText(k): quit "the sealed copy did not open again: not written"
    writeFile(args["out"], toText(doc))
    discard chmod(args["out"].cstring, 0o600)
    echo "Wrote ", args["out"], ": the plant root key, sealed with the passphrase. Keep both offline, apart if you can."
  of "backup":
    if "out" notin args: quit "usage: kks-server backup --out FILE"
    writeFile(args["out"], s.n.bundle(photos = true, now = int64(epochTime() * 1000)))
    echo "Wrote ", args["out"], " (a bundle: unencrypted plant data; keep it safe)"
  else:
    quit "unknown command " & cmd
  s.store.close()

main()
