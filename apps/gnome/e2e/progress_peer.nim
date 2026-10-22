## A second device of the same person, without a window, for the course-progress e2e (PROTOCOL-v2 §17, decision
## 0062): the apps' own openApp, joinServer, syncAll and local API (apps/common/appstate.nim), so it pairs and syncs
## exactly as an app would. Each command syncs once with the server first (which also runs the §17 upkeep).
##   cd apps/gnome && nim c -d:release -o:OUT/progress_peer e2e/progress_peer.nim
##   KKS_DATA_DIR=D KKS_STORAGE_KEY_FILE=D/key OUT/progress_peer join HOST:PORT USER PASSWORD
##   … device                      this device's ID
##   … pairing                     the pairing list (JSON: ready, devices with their state and code)
##   … pair DEVICE                 press Pair for DEVICE (a new commitment, §17)
##   … confirm DEVICE CODE         the codes match: confirm the pairing
##   … save COURSE KEY VALUE       save one progress value (VALUE is the JSON text)
##   … progress COURSE             this person's progress in COURSE as this device reads it (JSON)
import std/[asyncdispatch, os, tables]
import appstate, kks/[json, node], kksl/dbstore

let args = commandLineParams()
if args.len == 0: quit "usage: progress_peer join|device|pairing|pair|save|progress …"
let a = openApp()
proc sync() =
  ## twice: what the first round's §17 upkeep wrote (a reveal, a share) goes out in the second
  discard waitFor a.syncAll()
  discard waitFor a.syncAll()
case args[0]
of "join":
  if args.len != 4: quit "usage: progress_peer join HOST:PORT USER PASSWORD"
  let err = waitFor a.joinServer(args[1], args[2], args[3])
  if err.len > 0: quit "join failed: " & err
  sync()
  echo "joined"
of "device": echo a.n.device
of "pairing":
  sync()
  echo toText(a.call("GET", "/api/pairing"))
of "pair", "confirm":
  sync()
  var body = newObj(@[("action", newStr(if args[0] == "pair": "start" else: "confirm")), ("device", newStr(args[1]))])
  if args[0] == "confirm": body["code"] = newStr(args[2])
  echo toText(a.call("POST", "/api/pairing", body))
  sync()
of "save":
  sync()
  discard a.call("POST", "/api/progress", newObj(@[("course", newStr(args[1])),
                                                    ("data", newObj(@[(args[2], newStr(args[3]))]))]))
  sync()
  echo "saved"
of "progress":
  sync()
  echo toText(a.call("GET", "/api/progress", nil, {"course": args[1]}.toTable)["data"])
else: quit "unknown command " & args[0]
a.store.close()
