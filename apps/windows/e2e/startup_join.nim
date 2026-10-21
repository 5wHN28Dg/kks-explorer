## Joins a data folder to a plant through its server, without a window: the Windows app's own openApp and joinServer
## (apps/common/appstate.nim), so the folder is what the app itself would have after "Join through a server". For the
## startup measurements (docs/m6/MEASUREMENTS.md, tools/m6/startup_data.py, e2e/measure.ps1), in the VM:
##   startup_join.exe HOST:PORT USER PASSWORD      (KKS_DATA_DIR names the folder)
## It is a GUI program (the app's config): it says nothing; the exit code is 0 when joined, and on failure the reason
## is in startup_join.txt in the data folder.
import std/[asyncdispatch, os]
import appstate, kksl/dbstore

let a = openApp()
let args = commandLineParams()
if args.len != 3: quit 2
let err = waitFor a.joinServer(args[0], args[1], args[2])
writeFile(dataDir() / "startup_join.txt", if err.len > 0: "join failed: " & err else: "joined")
a.store.close()
quit(if err.len > 0: 1 else: 0)
