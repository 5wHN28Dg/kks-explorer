## The desktop apps open their store, replay the log and build the first model on a thread of their own while the
## window is made (apps/common/appstate.nim openAppInBackground, decision 0061): the app the main thread gets is the
## one a plain open gives, the thread does nothing only the running instance may do (a crash report, the change
## listener), a failure there reaches the main thread, and many opens in a row leave nothing behind that breaks.
import std/[os, unittest, strutils, tables]
import kks/[json, node, model]
import appstate, kksl/dbstore

let base = getTempDir() / "kks-background-open-test"
removeDir(base)
createDir(base)

proc plantFolder(name: string): string =
  ## a data folder holding a plant this device manages, a few edits, its store closed
  result = base / name
  createDir(result)
  putEnv("KKS_STORAGE_KEY_FILE", result / "key")
  let a = openApp(result)
  a.createPlant("Test plant", "boss", "The Manager", newNull())
  for i in 0 ..< 20:
    discard a.call("POST", "/api/submit", parseStrict("""{"kind":"equipment","payload":{"kks":"11LAB70AA5""" &
      $(10 + i) & """","changes":{"notes":"round """ & $i & """"},"base":{}}}"""))
  a.saveState()
  a.store.close()

suite "opening while the window is made":
  test "the app opened in the background is the one a plain open gives":
    let d = plantFolder("same")
    let plain = openApp(d)
    let want = toText(plain.call("GET", "/api/state"))
    plain.store.close()
    check openAppInBackground(d)
    let a = openedApp(d)
    check a.joined
    check a.n.stateFromSaved
    check toText(a.call("GET", "/api/state")) == want
    let m = a.takeModel("{}")                # built on the thread
    check m != nil and m.state != nil and toText(m.state) == want
    check a.firstModel == nil                # taken once
    a.store.close()

  test "a model built before a change is not used":
    let d = plantFolder("changed")
    check openAppInBackground(d)
    let a = openedApp(d)
    discard a.call("POST", "/api/submit", parseStrict(
      """{"kind":"equipment","payload":{"kks":"11LAB70AA599","changes":{"notes":"after"},"base":{}}}"""))
    let m = a.takeModel("{}")
    check toText(m.state).contains("11LAB70AA599")
    a.store.close()

  test "the thread leaves the crash report to the running instance":
    let d = plantFolder("crash")
    writeFile(d / "crash.txt", "SIGSEGV: Illegal storage access")
    check openAppInBackground(d)
    sleep(1500)                             # (the thread is done by now)
    check fileExists(d / "crash.txt")
    let a = openedApp(d)
    check not fileExists(d / "crash.txt")   # reported (§13a) by the instance that runs
    a.store.close()

  test "a folder without a store is opened the plain way":
    let d = base / "new"
    createDir(d)
    putEnv("KKS_STORAGE_KEY_FILE", d / "key")
    check not openAppInBackground(d)
    let a = openedApp(d)
    check not a.joined
    a.store.close()

  test "a failure on the thread reaches the main thread":
    let d = plantFolder("wrongkey")
    writeFile(d / "key", newString(32))    # another storage key: the store doesn't open
    check openAppInBackground(d)
    expect OpenError: discard openedApp(d)

  test "many opens in a row":
    let d = plantFolder("many")
    for i in 0 ..< 30:
      check openAppInBackground(d)
      let a = openedApp(d)
      check a.joined
      check a.n.entries.len > 20
      discard a.takeModel("{}")
      a.store.close()
    GC_fullCollect()
