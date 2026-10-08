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
