## The overview decode worker skips jobs queued for an older generation (another sheet, a dark-drawings switch):
## repeated toggling must not queue full level-0 decodes ahead of the current one (review finding on dark drawings).
include ../src/kksg/viewer

import std/[unittest, os]

suite "overview decode queue":
  test "jobs of an older generation are skipped, the current one is decoded":
    ensureWorker()
    liveGen.store(7)
    for _ in 0 ..< 3: jobs.send(DecodeJob(gen: 6, level: 0, dark: true, data: "not a jxl"))
    jobs.send(DecodeJob(gen: 7, level: 1, dark: true, data: "not a jxl"))
    var got: seq[int]
    let t0 = epochTime()
    while epochTime() - t0 < 2.0:
      let (ok, d) = results.tryRecv()
      if ok: got.add d.gen
      else: sleep(20)
    check got == @[7]

suite "levels kept over a dark-drawings switch":
  test "the other mode's levels sharper than the zoom wants are freed; the one on screen stays":
    let px = [byte 0, 0, 0]
    var t: seq[W]
    for k in 0 ..< 4:
      t.add textureFromRgb(px, 1, 1)
      g_object_ref(t[k])                 # ours, so a freed slot can still be checked
    let v = Viewer(stale: @[t[0], t[1], t[2], t[3]])
    v.dropSharperStale(2, t[1])          # zoom wants level 2; level 1 is on screen (nothing sharper of this mode)
    check v.stale[0] == nil              # the old level 0 (the big one) goes
    check v.stale[1] == t[1]             # on screen
    check v.stale[2] == t[2] and v.stale[3] == t[3]   # as blurry or blurrier: kept until this mode's arrive
    check cast[ptr UncheckedArray[cuint]](t[0])[2] == 1   # GObject.ref_count: only ours left
    for k in 0 ..< 4: g_object_unref(t[k])
