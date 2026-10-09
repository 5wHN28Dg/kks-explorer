## The desktop apps' photo queue, kept on disk (the user's rule: a photo is never lost; Android's queue does the same,
## decision 0049). Shared so the Windows app can follow; the GNOME app drives it from photos.nim. Each photo is written
## here before it is compressed and removed only once the core accepted or refused it, so a crash, an OOM kill or a
## logout leaves it in the store, and the next start sends it.
##
## Where and how it is kept: in the device's own store (`kks.db` in the app's data folder), as two sealed local rows
## (dbstore `putRow`: AES-256-GCM under the store's storage key, which lives in the platform key store; the associated
## data names the table and the key, so rows can't be swapped). Nothing new to protect: the same key and the same
## rows the app already uses for its own records. A removed device's wipe (§15) deletes every row, the queue with them.
##
## The format (version 1), one photo:
## - table `photo_queue`, key = a 12-digit decimal sequence number (`000000000001`): the job, a JSON object
##   `{"v": 1, "client_id": "<32 hex>", "kks", "caption", "note", "floor": strings, "w", "h": ints, "at": ms}`
## - table `photo_queue_px`, the same key: a JSON string, standard base64 (padded) of w × h × 3 bytes, the annotated
##   picture's RGB rows top to bottom, exactly what the JPEG XL encoder takes.
## Both rows are written in one transaction and removed in one, so a crash leaves both or neither. The queue's order is
## the key order (the order the photos were added). `client_id` goes with the submission (§9 submit), so a photo sent
## just before a crash and sent again after it is kept once (the core returns the first submission).
##
## Outcomes: sent (accepted, or a duplicate) and refused (the core said no, status 400 and up) end a photo; any other
## failure (the encoder, the core throwing, not joined) keeps it: it goes to the end of the queue and is tried again a
## minute later; after `Tries` failures in one run it waits for the next start. A job or picture row that can't be
## read (damaged, or the wrong size) ends that photo with a report.

import std/[base64, strutils]
import kks/[json, crypto, util]
import kksl/[dbstore, sqlite]

const
  JobTable* = "photo_queue"
  PixelTable* = "photo_queue_px"
  Tries* = 5               ## transient failures in one run before a photo waits for the next start
  RetryMs* = 60_000        ## a failed photo's wait before the next try

type
  QueuedPhoto* = object
    key*: string           ## its rows' key: the queue's order
    clientId*: string
    kks*, caption*, note*, floor*: string
    w*, h*: int
    at*: int64             ## ms, when it was added
    tries*: int            ## transient failures in this run (not stored)
    readyAt*: int64        ## a retried photo waits until then (ms; not stored)
  Outcome* = enum Sent, Refused, Failed
  PhotoQueue* = ref object
    store*: DbStore
    items*: seq[QueuedPhoto]   ## waiting or being compressed, in the order they go
    busy*: string              ## the key being compressed or sent ("" = none)
    wiped*: bool               ## the device was removed: nothing is written any more

proc newPhotoQueue*(s: DbStore): PhotoQueue = PhotoQueue(store: s)

proc remove(q: PhotoQueue, key: string) =
  q.store.transaction(proc () =
    q.store.delRow(JobTable, key)
    q.store.delRow(PixelTable, key))

proc drop(q: PhotoQueue, key: string) =
  for i in 0 ..< q.items.len:
    if q.items[i].key == key:
      q.items.delete(i)
      return

proc keys(q: PhotoQueue, tbl: string): seq[string] =
  for r in q.store.db.rows("SELECT k FROM rows WHERE tbl=? ORDER BY k", t(tbl)): result.add r.colText(0)

proc str(j: JNode, k: string): string =
  let v = j.get(k)
  if v == nil or not v.isStr: raise newException(ValueError, "the job's " & k & " is missing")
  v.s

proc int0(j: JNode, k: string): int64 =
  let v = j.get(k)
  if v == nil or v.kind != jInt: raise newException(ValueError, "the job's " & k & " is missing")
  v.i

proc parseJob(key: string, j: JNode): QueuedPhoto =
  if j == nil or j.kind != jObj or int0(j, "v") != 1: raise newException(ValueError, "not a version 1 job")
  result = QueuedPhoto(key: key, clientId: str(j, "client_id"), kks: str(j, "kks"), caption: str(j, "caption"),
                       note: str(j, "note"), floor: str(j, "floor"), w: int(int0(j, "w")), h: int(int0(j, "h")),
                       at: int0(j, "at"))
  if result.kks.len == 0 or result.w <= 0 or result.h <= 0 or
     not (result.clientId.len in 8..64 and result.clientId.allCharsInSet({'A'..'Z', 'a'..'z', '0'..'9', '_', '-'})):
    raise newException(ValueError, "a damaged job")

proc resume*(q: PhotoQueue): seq[string] =
  ## at start: the photos left from before (a crash, a kill, a logout, or tries used up), in their order. Returns the
  ## reports of the ones that can't be read (dropped).
  q.items.setLen(0)
  q.busy = ""
  var known: seq[string]
  for key in q.keys(JobTable):
    try:
      q.items.add parseJob(key, q.store.getRow(JobTable, key))
      known.add key
    except CryptoError, ValueError:       # damaged (the seal, the JSON, a field); a store error is raised instead
      result.add "A queued photo could not be read and was dropped (" & getCurrentExceptionMsg() & ")"
      q.remove(key)
  for key in q.keys(PixelTable):          # a picture without its job (not written that way, but never kept for ever)
    if key notin known: q.store.delRow(PixelTable, key)

proc add*(q: PhotoQueue, p: Provider, rgb: openArray[byte], w, h: int, kks, caption, note, floor: string,
          now: int64): QueuedPhoto =
  ## keep one photo (its pixels and its job) and put it at the end of the queue. Raises when it can't be written:
  ## then nothing is kept.
  if q.wiped: raise newException(IOError, "this device was removed from the plant")
  if w <= 0 or h <= 0 or rgb.len != w * h * 3: raise newException(ValueError, "the picture's size doesn't match")
  var last = 0
  for r in q.store.db.rows("SELECT max(k) FROM rows WHERE tbl=?", t(JobTable)):
    let s = r.colText(0)
    if s.len > 0: last = parseInt(s)
  let key = align($(last + 1), 12, '0')
  result = QueuedPhoto(key: key, clientId: hex(p.randomBytes(16)), kks: kks, caption: caption, note: note,
                       floor: floor, w: w, h: h, at: now)
  var raw = newString(rgb.len)
  if rgb.len > 0: copyMem(addr raw[0], unsafeAddr rgb[0], rgb.len)
  let job = newObj(@[("v", newInt(1)), ("client_id", newStr(result.clientId)), ("kks", newStr(kks)),
                     ("caption", newStr(caption)), ("note", newStr(note)), ("floor", newStr(floor)),
                     ("w", newInt(w)), ("h", newInt(h)), ("at", newInt(now))])
  let px = newStr(encode(raw))
  q.store.transaction(proc () =
    q.store.putRow(PixelTable, key, px)
    q.store.putRow(JobTable, key, job))
  q.items.add result

proc pixels(q: PhotoQueue, it: QueuedPhoto): seq[byte] =
  let j = q.store.getRow(PixelTable, it.key)
  if j == nil or not j.isStr: raise newException(ValueError, "its picture is missing")
  let raw = decode(j.s)
  if raw.len != it.w * it.h * 3: raise newException(ValueError, "its picture is damaged")
  result = newSeq[byte](raw.len)
  if raw.len > 0: copyMem(addr result[0], unsafeAddr raw[0], raw.len)

proc next*(q: PhotoQueue, now: int64, reports: var seq[string]): (bool, QueuedPhoto, seq[byte]) =
  ## the next photo to compress and its pixels (the first one not waiting for a retry), or false. A photo whose rows
  ## can't be read is dropped here, with a report.
  if q.wiped or q.busy.len > 0: return
  var i = 0
  while i < q.items.len:
    let it = q.items[i]
    if it.readyAt > now:
      inc i
      continue
    try:
      let px = q.pixels(it)
      q.busy = it.key
      return (true, it, px)
    except CryptoError, ValueError:       # damaged (the seal, base64, the size): it won't get better
      reports.add "Photo of " & it.kks & " could not be read and was dropped (" & getCurrentExceptionMsg() & ")"
      q.remove(it.key)
      q.items.delete(i)
    except CatchableError as e:           # the store itself (I/O, busy): kept, tried again in a minute
      reports.add "Photo of " & it.kks & " could not be read now (" & e.msg & "). It is kept and tried again in a minute."
      q.items[i].readyAt = now + RetryMs
      inc i

proc finish*(q: PhotoQueue, key: string, outcome: Outcome, why: string, now: int64): string =
  ## what became of the photo being worked on; returns a report for the person ("" when there is nothing to say)
  if q.busy == key: q.busy = ""
  if q.wiped: return ""
  var i = 0
  while i < q.items.len and q.items[i].key != key: inc i
  if i == q.items.len: return ""
  var it = q.items[i]
  case outcome
  of Sent, Refused:
    try: q.remove(key)
    except CatchableError as e:          # kept: tried again in a minute (a resend is kept once, by its client_id)
      q.items[i].readyAt = now + RetryMs
      return "Photo of " & it.kks & ": the queue could not be updated (" & e.msg & "). It is tried again in a minute."
    q.drop(key)
    if outcome == Refused: result = "Photo of " & it.kks & " was refused: " & why
  of Failed:
    q.items.delete(i)
    inc it.tries
    if it.tries < Tries:
      it.readyAt = now + RetryMs
      q.items.add it                    # to the end: the photos after it still go
      result = "Photo of " & it.kks & " was not sent (" & why & "). It is kept and tried again in a minute."
    else:
      result = "Photo of " & it.kks & " was not sent (" & why & "). It is kept and tried again when the app next starts."

proc wipe*(q: PhotoQueue) =
  ## a removed device: the store's wipe deleted the rows; forget the photos in memory and write nothing more
  q.wiped = true
  q.items.setLen(0)
  q.busy = ""

proc count*(q: PhotoQueue): int = q.items.len
