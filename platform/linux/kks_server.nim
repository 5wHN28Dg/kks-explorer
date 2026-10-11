## kks-server: the always-on peer for browser clients (M6, decisions 0026, 0030).
##   kks-server [serve] [--config F]
##   kks-server users | reset-password --user NAME | reset-manager --user NAME | setup-link
##   kks-server publish-data DIR | set-plant-name NAME | submit-file FILE.json
##   kks-server web-sign-in --user NAME: a web account for someone who joined with the app and has none (the same
##     person), and the one-time link with which they set their password (as Manage → Users → Web sign-in)
##   kks-server set-signup-code CODE: the code people need to ask for an account in the browser ("" = sign-up off);
##     an admin then approves or rejects each request in Manage → Users. CODE "-" reads the code from standard input
##     (one line), which keeps it out of the process list and the shell's history
##   kks-server backup --out FILE: the plant (log and photos), encrypted with a key from the last export-root-key's
##     passphrase (decision 0051); kks-server open-backup --in FILE --out BUNDLE --passphrase-file F opens it anywhere
##     (publish-data, set-plant-name, set-signup-code, submit-file, reset-password, reset-manager and web-sign-in run inside the server when it runs: its control
##     socket next to the store, decision 0045)
##   kks-server export-root-key --out FILE [--passphrase-out FILE]: the plant root key, sealed with a generated
##     passphrase (80 bits, decision 0023, issue #29) that is printed, or written to --passphrase-out; the same file
##     the apps' "Restore from a backup" reads. Both files 0600.
## The storage key (decision 0020) comes from systemd-creds: LoadCredentialEncrypted=kks-storage-key:… in the unit
## ($CREDENTIALS_DIRECTORY/kks-storage-key). For development, `storage_key_file` in the config (created if missing).

import std/[asyncdispatch, nativesockets, net, os, posix, strutils, tables, times]
import kks/[json, util, crypto, node, replay, plantdata, bundle, provider_gnutls, extras]
import kksl/[server, dbstore, privfile, passphrase, serverbackup]

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
    writePrivate(keyFile, p.randomBytes(32).toStr)
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
  var cfg: Config
  try: cfg = loadConfig(cfgPath)
  except ValueError as e: quit("config " & cfgPath & ": " & e.msg)
  let here = getAppDir()
  if cfg.webDir.len == 0: cfg.webDir = here / "web"
  if cfg.dataDir.len == 0: cfg.dataDir = here / "data"
  if cfg.storePath.len == 0: cfg.storePath = "kks-server.db"
  if cmd in ["reset-password", "reset-manager", "web-sign-in"]:        # --user NAME
    if "user" notin args: quit "usage: kks-server " & cmd & " --user NAME"
    rest = @[args["user"]]
  if cmd == "set-signup-code" and rest == @["-"]:
    rest = @[try: stdin.readLine() except EOFError: ""]
  if cmd in ["publish-data", "set-plant-name", "set-signup-code", "reset-password", "reset-manager", "web-sign-in", "submit-file"]:
    # a running server does it itself (see server.control); else this process, with the server stopped
    block forward:
      let c = newSocket(nativesockets.AF_UNIX, nativesockets.SOCK_STREAM, nativesockets.IPPROTO_IP)
      try: c.connectUnix(controlPath(cfg))
      except OSError:                                  # no server running (or a socket it left behind)
        c.close()
        break forward
      block:
        var a = newArr()
        for x in rest: a.elems.add newStr(x)
        c.send(toText(newObj(@[("cmd", newStr(cmd)), ("args", a)])) & "\n")
        let r = parseStrict(c.recvLine(timeout = 600_000))
        c.close()
        if not r["ok"].b: quit r["out"].s
        echo r["out"].s
        return
  let p = newGnuTlsProvider()
  if cmd == "open-backup":   # decision 0051: no store needed, any machine with this program and the passphrase
    if "in" notin args or "out" notin args or "passphrase-file" notin args:
      quit "usage: kks-server open-backup --in BACKUP --out BUNDLE --passphrase-file FILE"
    var bundle: string
    try: bundle = p.openBackup(readFile(args["passphrase-file"]).strip, readFile(args["in"]))
    except ValueError as e: quit e.msg
    except CatchableError: quit "that passphrase doesn't open this backup (it opens with the passphrase of the root key export made before it)"
    writePrivate(args["out"], bundle)
    echo "Wrote ", args["out"], ": the plant as a bundle (import it in Manage → Import a bundle)"
    return
  let s = openServer(cfg, p, storageKey(cfgPath, p))
  case cmd
  of "serve":
    # issue #69: the one-time link goes to a 0600 file, not to stdout (the journal, under systemd)
    let linkFile = setupLinkPath(cfg)
    let l = s.setupLink()
    if l.len > 0:
      writePrivate(linkFile, l & "\n")
      echo "No manager yet. The one-time link that creates the manager (valid 7 days) is in the setup link file: ", linkFile
    elif fileExists(linkFile): removeFile(linkFile)
    asyncCheck s.serve()   # listening once this returns: the HTTP listener opens before serve's first await (a port
                           # already taken fails at the first poll, as before)
    # said only now: whoever waits for this line (the e2e tests, a service manager's log) may connect at once. Before,
    # it came before mDNS and the listeners were set up, and a connection right after it was refused (GNOME e2e flake)
    echo "Walkdown server on http://", cfg.address, ":", cfg.port, (if cfg.syncPort > 0: ", sync port " & $cfg.syncPort else: "")
    runForever()
  of "setup-link":
    let l = s.setupLink()
    echo(if l.len > 0: l else: "The plant has a manager; use reset-manager to change it.")
  of "users":
    for (_, u) in s.store.allRows("users"):
      echo u["id"].i, "  ", u["username"].s.alignLeft(20), " ", (if s.n.run != nil: s.n.run.role(u["person"].s) else: "?").alignLeft(8),
           " ", (if u["active"].b: "active" else: "inactive"), "  ", u["full_name"].s
  of "publish-data", "set-plant-name", "set-signup-code", "reset-password", "reset-manager", "web-sign-in", "submit-file":
    try: echo s.control(cmd, rest)
    except ValueError as e: quit e.msg
  of "export-root-key":
    if "out" notin args: quit "usage: kks-server export-root-key --out FILE [--passphrase-out FILE]"
    if existsEnv("KKS_ROOT_PASSPHRASE"):
      quit "KKS_ROOT_PASSPHRASE is not read any more: the passphrase is generated (decision 0023, issue #29)"
    let pass = p.newBackupPassphrase()
    let k = s.store.getRow("keys", "root")
    if k == nil: quit "this server holds no root key"
    let sealed = p.passphraseSeal(pass, toText(k).toBytes)
    let doc = newObj(@[("kks_root_backup", newInt(2)), ("plant", s.n.run.settings.getOrDefault("plant")),
                       ("root", newStr(s.n.root)), ("sealed", sealed)])
    # check it opens before calling it a backup
    if p.passphraseOpen(pass, doc["sealed"]).toStr != toText(k): quit "the sealed copy did not open again: not written"
    if "passphrase-out" in args:
      if absolutePath(args["passphrase-out"]) == absolutePath(args["out"]): quit "--out and --passphrase-out must differ"
      writePrivate(args["passphrase-out"], pass & "\n")   # first: a backup is never written without its passphrase
    writePrivate(args["out"], toText(doc))
    s.store.putRow("keys", "backup", p.newBackupKeyRow(pass))   # the server backups' key from now on (decision 0051)
    if "passphrase-out" in args:
      echo "Wrote ", args["out"], ": the plant root key, sealed with the passphrase in ", args["passphrase-out"], "."
    else:
      echo "Wrote ", args["out"], ": the plant root key, sealed with this passphrase (write it down; it is not kept):"
      echo "  ", pass
    echo "Keep both offline, apart if you can. Server backups made from now on open with this passphrase (open-backup)."
  of "backup":
    if "out" notin args: quit "usage: kks-server backup --out FILE"
    let row = s.store.getRow("keys", "backup")
    if row == nil:
      quit "no backup key yet: run export-root-key first (backups are encrypted with a key from its passphrase, decision 0051)"
    let now = int64(epochTime() * 1000)
    writePrivate(args["out"], p.sealBackup(row, s.n.root, now div 1000, s.n.bundle(photos = true, now = now)))
    echo "Wrote ", args["out"], " (encrypted: it opens with the passphrase of the last root key export, kks-server open-backup)"
  else:
    quit "unknown command " & cmd
  s.store.close()

main()
