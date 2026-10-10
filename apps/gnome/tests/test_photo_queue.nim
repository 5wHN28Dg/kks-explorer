## The photo queue on disk (apps/common/photoqueue.nim): photos survive the app ending, in their order, sealed in the
## store; sent and refused photos are removed, failed ones kept; damaged rows end a photo with a report; a wipe takes
## the queue with it.

import std/[unittest, os, base64, strutils]
import kks/[json, crypto]
import kks/provider_gnutls
import kksl/[dbstore, sqlite]
import photoqueue

let p = newGnuTlsProvider()
let dir = getTempDir() / "kks-photoqueue-test"
removeDir(dir)
createDir(dir)
let key = p.randomBytes(32)
var n = 0

proc fresh(): DbStore =
  inc n
  openDbStore(p, dir / ("q" & $n & ".db"), key)

proc reopen(s: DbStore): DbStore =
  let path = s.path
  s.close()
  openDbStore(p, path, key)

proc pic(w, h: int, v: byte): seq[byte] =
  result = newSeq[byte](w * h * 3)
  for i in 0 ..< result.len: result[i] = byte((i + int(v)) mod 251)

suite "photo queue on disk":
  test "photos come back after a restart, in their order, with their job and pixels":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(4, 3, 1), 4, 3, "11LAB70AA501", "first", "a note", "2", 1000)
    let b = q.add(p, pic(5, 2, 2), 5, 2, "11LAB70AA502", "second", "", "", 2000)
    discard q.add(p, pic(1, 1, 3), 1, 1, "11LAB70AA503", "third", "", "", 3000)
    check a.clientId.len == 32 and a.clientId != b.clientId
    s = s.reopen()                            # as after a crash: nothing in memory
    q = newPhotoQueue(s)
    check q.resume().len == 0
    check q.count == 3
    check q.items[0].kks == "11LAB70AA501" and q.items[0].caption == "first" and q.items[0].note == "a note"
    check q.items[0].floor == "2" and q.items[0].clientId == a.clientId
    check q.items[1].kks == "11LAB70AA502" and q.items[2].kks == "11LAB70AA503"
    var reports: seq[string]
    let (ok, it, px) = q.next(5000, reports)
    check ok and it.key == a.key and px == pic(4, 3, 1) and it.w == 4 and it.h == 3
    # one at a time: nothing more until it is finished
    check not q.next(5000, reports)[0]
    check q.finish(a.key, Sent, "", 5000) == ""
    let (ok2, it2, px2) = q.next(5000, reports)
    check ok2 and it2.key == b.key and px2 == pic(5, 2, 2)
    s.close()

  test "the rows are sealed: the pixels are not in the database file in clear":
    let s = fresh()
    let q = newPhotoQueue(s)
    var px = newSeq[byte](64 * 64 * 3)
    for i in 0 ..< px.len: px[i] = byte(i mod 7 + 65)     # "ABCDEFG…": easy to find in clear
    discard q.add(p, px, 64, 64, "11LAB70AA501", "a caption that must not show", "", "", 1)
    let path = s.path
    s.close()
    var all = readFile(path)
    if fileExists(path & "-wal"): all.add readFile(path & "-wal")
    var raw = newString(px.len)
    for i, c in px: raw[i] = char(c)
    check raw[0 ..< 300] notin all
    check encode(raw)[0 ..< 300] notin all
    check "a caption that must not show" notin all
    check "11LAB70AA501" notin all

  test "sent and refused photos are removed; a failure keeps the photo, moves it to the end and waits":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "A1", "", "", "", 1)
    let b = q.add(p, pic(2, 2, 2), 2, 2, "B1", "", "", "", 2)
    let c = q.add(p, pic(2, 2, 3), 2, 2, "C1", "", "", "", 3)
    var reports: seq[string]
    discard q.next(100, reports)
    let r = q.finish(a.key, Failed, "out of memory", 100)
    check "kept" in r and "A1" in r
    check q.items[^1].key == a.key and q.items[^1].tries == 1
    discard q.next(100, reports)                       # b goes next, a waits a minute
    check q.busy == b.key
    check "refused" in q.finish(b.key, Refused, "invalid change", 100)
    check q.next(100, reports)[1].key == c.key
    discard q.finish(c.key, Sent, "", 100)
    check not q.next(100 + RetryMs - 1, reports)[0]    # a still waits
    check q.next(100 + RetryMs, reports)[1].key == a.key
    s = s.reopen()
    q = newPhotoQueue(s)
    discard q.resume()
    check q.count == 1 and q.items[0].key == a.key     # only the failed one is left on disk
    s.close()

  test "after Tries failures in one run a photo waits for the next start, and is there then":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "A1", "", "", "", 1)
    var reports: seq[string]
    var now = 0'i64
    var last = ""
    for k in 1 .. Tries:
      let (ok, _, _) = q.next(now, reports)
      check ok
      last = q.finish(a.key, Failed, "no", now)
      now += RetryMs
    check "next starts" in last and q.count == 0
    s = s.reopen()
    q = newPhotoQueue(s)
    discard q.resume()
    check q.count == 1 and q.items[0].tries == 0
    s.close()

  test "a damaged picture or job ends that photo with a report; the others still go":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "A1", "", "", "", 1)
    let b = q.add(p, pic(2, 2, 2), 2, 2, "B1", "", "", "", 2)
    let c = q.add(p, pic(2, 2, 3), 2, 2, "C1", "", "", "", 3)
    # a's picture: a flipped byte (the seal no longer opens); b's job: the wrong size for its picture
    s.db.run("UPDATE rows SET v = substr(v, 1, 20) || x'00' || substr(v, 22) WHERE tbl=? AND k=?", t(PixelTable), t(a.key))
    s.putRow(JobTable, b.key, newObj(@[("v", newInt(1)), ("client_id", newStr(b.clientId)), ("kks", newStr("B1")),
             ("caption", newStr("")), ("note", newStr("")), ("floor", newStr("")), ("w", newInt(3)), ("h", newInt(2)),
             ("at", newInt(2))]))
    s = s.reopen()
    q = newPhotoQueue(s)
    check q.resume().len == 0
    var reports: seq[string]
    let (ok, it, _) = q.next(0, reports)
    check ok and it.key == c.key
    check reports.len == 2 and "A1" in reports[0] and "B1" in reports[1]
    discard q.finish(c.key, Sent, "", 0)
    # a job row that can't be opened at start: dropped with a report, its picture too
    let d = q.add(p, pic(2, 2, 4), 2, 2, "D1", "", "", "", 4)
    s.db.run("UPDATE rows SET v = x'00' || substr(v, 2) WHERE tbl=? AND k=?", t(JobTable), t(d.key))
    s = s.reopen()
    q = newPhotoQueue(s)
    let rs = q.resume()
    check rs.len == 1 and q.count == 0
    check s.getRow(PixelTable, d.key) == nil
    s.close()

  test "a removed device's wipe deletes the queue, and nothing is written after it":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "A1", "", "", "", 1)
    var reports: seq[string]
    discard q.next(0, reports)
    s.wipe("removed")
    q.wipe()
    check q.finish(a.key, Failed, "not joined", 0) == ""     # the in-flight photo can't come back
    check q.count == 0
    expect IOError: discard q.add(p, pic(2, 2, 1), 2, 2, "A1", "", "", "", 1)
    s = s.reopen()
    q = newPhotoQueue(s)
    discard q.resume()
    check q.count == 0
    var left = 0
    for r in s.db.rows("SELECT count(*) FROM rows WHERE tbl IN (?, ?)", t(JobTable), t(PixelTable)): left = int(r.colInt(0))
    check left == 0
    s.close()

  test "a store error is not damage: the photo is kept and tried again (reading it, and removing it once sent)":
    let s = fresh()
    let q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "A1", "", "", "", 1)
    var reports: seq[string]
    s.db.exec("ALTER TABLE rows RENAME TO rows_away")      # every read and write of a row now fails
    check not q.next(0, reports)[0]
    check reports.len == 1 and "kept" in reports[0] and q.count == 1
    s.db.exec("ALTER TABLE rows_away RENAME TO rows")
    check not q.next(RetryMs - 1, reports)[0]
    check q.next(RetryMs, reports)[1].key == a.key
    s.db.exec("ALTER TABLE rows RENAME TO rows_away")
    let r = q.finish(a.key, Sent, "", RetryMs)
    check "could not be updated" in r and q.count == 1 and q.busy == ""
    s.db.exec("ALTER TABLE rows_away RENAME TO rows")
    check q.next(2 * RetryMs, reports)[1].key == a.key      # sent again (kept once by the core: its client_id)
    check q.finish(a.key, Sent, "", 2 * RetryMs) == "" and q.count == 0
    check s.getRow(JobTable, a.key) == nil and s.getRow(PixelTable, a.key) == nil
    s.close()

  test "one photo of several codes keeps its codes, in order; a damaged code list is a damaged job":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "", "Both drains", "", "", 1, @["11LAC10AP001", "11LAC10AP003"])
    check a.kks == "11LAC10AP001" and a.codes == @["11LAC10AP001", "11LAC10AP003"]
    check a.clientId.len <= 56          # submit-many's prefix limit
    let b = q.add(p, pic(2, 2, 2), 2, 2, "11LAB70AA501", "", "", "", 2)
    s = s.reopen()
    q = newPhotoQueue(s)
    check q.resume().len == 0
    check q.items[0].codes == @["11LAC10AP001", "11LAC10AP003"] and q.items[0].kks == "11LAC10AP001"
    check q.items[1].codes.len == 0 and q.items[1].key == b.key
    # the floor asked before a photo of several codes (for the codes without one) is kept with the job
    let c = q.add(p, pic(2, 2, 3), 2, 2, "", "", "", "4", 3, @["11LAC10AP002", "11LAC10AP004"])
    check c.floor == "4"
    s = s.reopen()
    q = newPhotoQueue(s)
    check q.resume().len == 0
    check q.items[2].key == c.key and q.items[2].floor == "4" and q.items[2].codes == @["11LAC10AP002", "11LAC10AP004"]
    discard q.finish(c.key, Sent, "", 4)
    expect ValueError:
      var many: seq[string]
      for i in 0 .. 200: many.add "11LAC10AP" & align($i, 3, '0')
      discard q.add(p, pic(1, 1, 1), 1, 1, "", "", "", "", 3, many)
    var j = s.getRow(JobTable, a.key)
    j["codes"] = newArr()
    s.putRow(JobTable, a.key, j)
    s = s.reopen()
    q = newPhotoQueue(s)
    check q.resume().len == 1 and q.count == 1 and q.items[0].key == b.key
    s.close()

  test "a code list is version 2 (a version 1 job with codes is damaged); empty codes are refused when queued":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(1, 1, 1), 1, 1, "", "", "", "", 1, @["A1", "B1"])
    check s.getRow(JobTable, a.key)["v"].i == 2
    check s.getRow(JobTable, q.add(p, pic(1, 1, 1), 1, 1, "C1", "", "", "", 2).key)["v"].i == 1
    check a.name == "A1 and 1 more"
    expect ValueError: discard q.add(p, pic(1, 1, 1), 1, 1, "", "", "", "", 3, @["A1", ""])
    expect ValueError: discard q.add(p, pic(1, 1, 1), 1, 1, "", "", "", "", 3)
    var j = s.getRow(JobTable, a.key)
    j["v"] = newInt(1)
    s.putRow(JobTable, a.key, j)
    s = s.reopen()
    q = newPhotoQueue(s)
    check q.resume().len == 1 and q.count == 1 and q.items[0].kks == "C1"
    s.close()

  test "a caption or note the core would refuse is caught before queueing":
    check textProblem("", "") == ""
    check textProblem("é".repeat(500), "x".repeat(500)) == ""
    check "caption" in textProblem("é".repeat(501), "")
    check "note" in textProblem("", "x".repeat(501))

  test "a discarded photo leaves the store (never while it is being worked on); a floor taken over is kept on disk":
    var s = fresh()
    var q = newPhotoQueue(s)
    let a = q.add(p, pic(2, 2, 1), 2, 2, "A1", "first", "", "4", 1)
    let b = q.add(p, pic(2, 2, 2), 2, 2, "A1", "second", "", "", 2)
    let c = q.add(p, pic(2, 2, 3), 2, 2, "C1", "third", "", "", 3)
    var reports: seq[string]
    discard q.next(10, reports)
    check q.busy == a.key
    expect ValueError: q.forget(a.key)                 # its result would come back under a key reused later
    check q.count == 3
    discard q.finish(a.key, Failed, "the encoder", 10)
    q.forget(a.key)                                    # failed, waiting: it can go
    check q.count == 2 and q.items[0].key == b.key
    q.setFloor(b.key, "4")                             # the next photo of the code takes its floor over
    check q.items[0].floor == "4"
    s = s.reopen()
    q = newPhotoQueue(s)
    check q.resume().len == 0
    check q.count == 2 and q.items[0].key == b.key and q.items[0].floor == "4" and q.items[1].key == c.key
    s.close()

removeDir(dir)
