## The Windows viewer's tile workers (kks_d2d.cpp) and closing a sheet: switching sheets closes the old one right after
## dropping its queued tiles, while a worker may still be rendering one of them. The sheet must outlive that tile (it
## used to be deleted at once, and the worker read freed memory), and it must still go once its tiles are done.
## Cross-built like the app (CI's windows-build puts it in out/plat, windows-test runs it); runs on Windows:
##   nim c --os:windows -d:mingw --cpu:amd64 --cc:clang -d:release --app:console -o:test_tiles.exe apps/windows/tests/test_tiles.nim
import std/[unittest, os, times]

{.compile("../src/kkswin/kks_d2d.cpp", "-std=c++17").}
{.passL: "-ljxl -ljxl_cms -lhwy -lbrotlidec -lbrotlienc -lbrotlicommon -ljxl_threads -lstdc++ -ld2d1 -lwindowscodecs -lole32 -luuid".}

proc d2dInit(): cint {.importc: "kks_d2d_init", cdecl.}
proc sheetOpen(flat: pointer, n: csize_t): pointer {.importc: "kks_sheet_open", cdecl.}
proc sheetClose(s: pointer) {.importc: "kks_sheet_close", cdecl.}
proc sheetsAlive(): cint {.importc: "kks_sheets_alive", cdecl.}
proc tileRequest(key: clonglong, s: pointer, tz, x0, y0: cfloat, size: cint, dark: cint) {.importc: "kks_tile_request", cdecl.}
proc jobsClear() {.importc: "kks_jobs_clear", cdecl.}
proc jobsQueued(): cint {.importc: "kks_jobs_queued", cdecl.}
proc jobDone(key: ptr clonglong, w, h: ptr cint, px: ptr pointer): cint {.importc: "kks_job_done", cdecl.}
proc cfree(p: pointer) {.importc: "kks_free", cdecl.}

proc busySheet(): string =
  ## a sheet in core views.flat's layout: 1000 × 1000 pt, one stroke style, 3000 polylines of 40 points across it (so
  ## a large tile takes a while to render), one grid cell holding every path
  const W = 64_000                    # quanta (1/64 pt)
  const nPaths = 3000
  const k = 40
  var o = "KKF1"
  proc u32(v: int) =
    let x = uint32(v and 0xFFFFFFFF)
    o.add char(x and 0xff); o.add char((x shr 8) and 0xff); o.add char((x shr 16) and 0xff); o.add char((x shr 24) and 0xff)
  for v in [W, W, 1, nPaths, 0, nPaths * k, nPaths * k * 2, 1, 1]: u32(v)
  o.add "\x01\x00\x00\x00"; u32(64); o.add "\x00\x00\x00\x00\x00\x00\x00\x00"     # style: stroke, 1 pt, black
  for i in 0 ..< nPaths:
    u32(0); u32(0); u32(0); u32(W); u32(W); u32(i * k); u32(k); u32(i * k)
  for i in 0 ..< nPaths:
    o.add '\0'
    for j in 1 ..< k: o.add '\1'
  while o.len mod 4 != 0: o.add '\0'
  var seed = 12345
  for i in 0 ..< nPaths * k * 2:
    seed = (seed * 1103515245 + 12345) and 0x7fffffff
    u32(seed mod W)
  u32(0); u32(nPaths)
  for i in 0 ..< nPaths: u32(i)
  o

proc waitDone(timeoutS = 30.0): (bool, int) =
  ## the next finished job: (it rendered, its width)
  let t0 = epochTime()
  var key: clonglong
  var w, h: cint
  var px: pointer
  while true:                         # at least once: timeoutS = 0 polls once
    if jobDone(addr key, addr w, addr h, addr px) == 1:
      if px != nil: cfree(px)
      return (true, int(w))
    if epochTime() - t0 >= timeoutS: return (false, 0)
    sleep(1)

proc waitGone(timeoutS = 30.0): bool =
  let t0 = epochTime()
  while epochTime() - t0 < timeoutS:
    if sheetsAlive() == 0: return true
    sleep(1)
  false

suite "closing a sheet while its tiles render":
  doAssert d2dInit() == 0
  let flat = busySheet()

  test "a tile being rendered keeps its closed sheet until it is done, then the sheet goes":
    var inFlight = 0
    for round in 0 ..< 12:
      let s = sheetOpen(unsafeAddr flat[0], csize_t(flat.len))
      check s != nil
      check sheetsAlive() == 1
      tileRequest(clonglong(round), s, 2, 0, 0, 2048, 0)        # the whole sheet at 2 px/pt
      let t0 = epochTime()
      while jobsQueued() > 0 and epochTime() - t0 < 10: discard  # a worker has taken it
      jobsClear()
      sheetClose(s)                   # what the viewer's setSheet does on a sheet switch
      # the worker hands its result over before it lets the sheet go: a sheet already gone means the tile is done
      if sheetsAlive() == 0:
        let (got, w) = waitDone(0)
        check got
        check w == 2048
      else:
        inc inFlight
        let (got, w) = waitDone()
        check got
        check w == 2048               # rendered from the sheet as it was, not from freed memory
      check waitGone()
    check inFlight > 0                # the case this is about happened at least once

  test "queued tiles dropped by jobsClear let their closed sheet go":
    let s = sheetOpen(unsafeAddr flat[0], csize_t(flat.len))
    for i in 0 ..< 64: tileRequest(clonglong(1000 + i), s, 8, cfloat(i), cfloat(i), 512, 0)
    jobsClear()
    sheetClose(s)
    check waitGone()
    while true:                       # the ones a worker had taken report as usual
      let (got, _) = waitDone(1)
      if not got: break
    check sheetsAlive() == 0
