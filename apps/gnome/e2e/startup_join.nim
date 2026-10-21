## Joins a data folder to a plant through its server, without a window: the GNOME app's own openApp and joinServer
## (apps/common/appstate.nim), so the folder is what the app itself would have after "Join through a server". For the
## startup measurements (docs/m6/MEASUREMENTS.md, tools/m6/startup_data.py):
##   cd apps/gnome && nim c -d:release -o:OUT/startup_join e2e/startup_join.nim
##   KKS_DATA_DIR=D KKS_STORAGE_KEY_FILE=D/key OUT/startup_join 127.0.0.1:PORT USER PASSWORD
## then the app on D (KKS_TIMING=1).
import std/[asyncdispatch, os]
import appstate, kksl/dbstore

let a = openApp()
let args = commandLineParams()
if args.len == 3:
  let err = waitFor a.joinServer(args[0], args[1], args[2])
  if err.len > 0:
    stderr.writeLine "join failed: " & err
    quit 1
  echo "joined"
else:
  quit "usage: startup_join HOST:PORT USER PASSWORD"
a.store.close()
