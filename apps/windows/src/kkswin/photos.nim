## Photos (R6; the GNOME app's photos.nim): thumbnails with who took each, a zoomable viewer, delete, add from a file
## (WIC → upright, 1600 px → the annotation editor → the photo queue: JPEG XL d1.9 effort 9 on a worker thread →
## submit), the tag plate's photo, and the floor asked first when the code has none. Camera capture: see
## apps/windows/README.md.

import std/[base64, strutils, tables, math, sequtils, os, times, typedthreads]
from std/unicode import runeLen
import kks/json
import kks/model
import appstate
import kks/node
import kksl/dbstore
import w32, ui, win, annotate, photoqueue
from kks/api import ApiError

{.compile("kks_img.cpp", "-std=c++17").}
{.passL: "-ljxl_threads -lpropsys".}

proc imageLoad(path: WideCString, maxSide: cint, w, h: ptr cint): pointer {.importc: "kks_image_load", cdecl.}
proc jxlEncode(rgba: pointer, w, h: cint, distance: cfloat, effort: cint, n: ptr csize_t): pointer {.importc: "kks_jxl_encode", cdecl.}
proc thumb(bgra: pointer, w, h, mw, mh: cint, tw, th: ptr cint): pointer {.importc: "kks_thumb", cdecl.}
proc jxlDecode(data: pointer, n: csize_t, w, h: ptr cint): pointer {.importc: "kks_jxl_decode", cdecl.}
proc cfree(p: pointer) {.importc: "kks_free", cdecl.}
proc viewNew(h: HWND): pointer {.importc: "kks_view_new", cdecl.}
proc viewFree(v: pointer) {.importc: "kks_view_free", cdecl.}
proc viewResize(v: pointer, w, h: cint) {.importc: "kks_view_resize", cdecl.}
proc viewBitmap(v: pointer, bgra: pointer, w, h: cint): cint {.importc: "kks_view_bitmap", cdecl.}
proc viewBegin(v: pointer, r, g, b: cfloat): cint {.importc: "kks_view_begin", cdecl.}
proc viewDrawBitmap(v: pointer, h: cint, x0, y0, x1, y1: cfloat, smooth: cint) {.importc: "kks_view_draw_bitmap", cdecl.}
proc viewEnd(v: pointer): cint {.importc: "kks_view_end", cdecl.}

const
  STM_SETIMAGE = 0x0172'u32
  SS_BITMAP = 0x0E'u32
  IMAGE_BITMAP = 0
  Distance = 1.9
  Effort = 9

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc photoBytes(w: Win, file: string): (bool, string) =
  let sha = file.split('.')[0]
  if w.a.n.store.blobHas(sha): (true, w.a.n.store.blobGet(sha)) else: (false, "")

# ---------------------------------------------------------------- the viewer window

type PhotoWin = ref object
  hwnd: HWND
  v: pointer
  px: seq[byte]
  w, h: int
  bmp: cint
  z, ox, oy: float
  drag: bool
  lx, ly: int

var photoWins = initTable[HWND, PhotoWin]()

proc fitPhoto(p: PhotoWin) =
  var r: RECT
  GetClientRect(p.hwnd, addr r)
  p.z = min(float(r.right) / float(p.w), float(r.bottom) / float(p.h))
  p.ox = (float(r.right) - float(p.w) * p.z) / 2
  p.oy = (float(r.bottom) - float(p.h) * p.z) / 2

proc photoProc(h: HWND, m: UINT, wp: WPARAM, lp: LPARAM): LRESULT {.stdcall.} =
  let p = photoWins.getOrDefault(h)
  if p == nil: return DefWindowProcW(h, m, wp, lp)
  case m
  of WM_PAINT:
    var ps: PAINTSTRUCT
    discard BeginPaint(h, addr ps)
    if viewBegin(p.v, 0, 0, 0) != 0:
      if p.bmp == 0: p.bmp = viewBitmap(p.v, addr p.px[0], cint(p.w), cint(p.h))
      viewDrawBitmap(p.v, p.bmp, cfloat(p.ox), cfloat(p.oy), cfloat(p.ox + float(p.w) * p.z), cfloat(p.oy + float(p.h) * p.z), 1)
      if viewEnd(p.v) == 0: p.bmp = 0
    EndPaint(h, addr ps)
    return 0
  of WM_ERASEBKGND: return 1
  of WM_SIZE:
    viewResize(p.v, cint(loword(lp)), cint(hiword(lp)))
    p.fitPhoto()
    InvalidateRect(h, nil, 0)
    return 0
  of WM_MOUSEWHEEL:
    var pt = POINT(x: sloword(lp), y: shiword(lp))
    ScreenToClient(h, addr pt)
    let f = pow(1.25, float(shiword(int(wp))) / 120)
    let nz = clamp(p.z * f, 0.05, 8.0)
    p.ox = float(pt.x) - (float(pt.x) - p.ox) * nz / p.z
    p.oy = float(pt.y) - (float(pt.y) - p.oy) * nz / p.z
    p.z = nz
    InvalidateRect(h, nil, 0)
    return 0
  of WM_LBUTTONDOWN:
    p.drag = true
    p.lx = sloword(lp)
    p.ly = shiword(lp)
    SetCapture(h)
    return 0
  of WM_MOUSEMOVE:
    if p.drag:
      p.ox += float(sloword(lp) - p.lx)
      p.oy += float(shiword(lp) - p.ly)
      p.lx = sloword(lp)
      p.ly = shiword(lp)
      InvalidateRect(h, nil, 0)
    return 0
  of WM_LBUTTONUP:
    p.drag = false
    ReleaseCapture()
    return 0
  of WM_KEYDOWN:
    if int(wp) == VK_ESCAPE: DestroyWindow(h)
    return 0
  of WM_DESTROY:
    viewFree(p.v)
    photoWins.del h
    return 0
  else: discard
  DefWindowProcW(h, m, wp, lp)

var photoClassDone = false

proc showPhoto*(w: Win, data, caption: string) =
  var iw, ih: cint
  let pix = jxlDecode(unsafeAddr data[0], csize_t(data.len), addr iw, addr ih)
  if pix == nil:
    w.toast("This photo can't be decoded")
    return
  if not photoClassDone:
    let clsName = newWideCString("KKSPhoto")   # must outlive RegisterClassExW
    var wc = WNDCLASSEXW(cbSize: UINT(sizeof(WNDCLASSEXW)), lpfnWndProc: photoProc, hInstance: hinst,
                         hCursor: LoadCursorW(nil, IDC_ARROW), lpszClassName: clsName)
    discard RegisterClassExW(addr wc)
    photoClassDone = true
  let p = PhotoWin(w: int(iw), h: int(ih), z: 1)
  p.px = newSeq[byte](int(iw) * int(ih) * 4)
  copyMem(addr p.px[0], pix, p.px.len)
  cfree(pix)
  p.hwnd = CreateWindowExW(0, newWideCString("KKSPhoto"), newWideCString(if caption.len > 0: caption else: "Photo"),
                           WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, px(1000), px(750), w.hwnd, nil, hinst, nil)
  p.v = viewNew(p.hwnd)
  photoWins[p.hwnd] = p
  ShowWindow(p.hwnd, SW_SHOW)

# ---------------------------------------------------------------- picking a picture

proc pickPicture(w: Win, title: string): (seq[byte], int, int) =
  ## a picture from a file, upright and at most 1600 px (RGBA); empty when none was chosen or Windows can't read it
  # KKS_TEST_PHOTO: the end-to-end test's picture instead of the file dialog's answer
  let path = if getEnv("KKS_TEST_PHOTO").len > 0: getEnv("KKS_TEST_PHOTO")
             else: openFile(w.hwnd, title, "Pictures|*.jpg;*.jpeg;*.png;*.heic;*.webp;*.bmp;*.tif;*.tiff|All files|*.*")
  if path.len == 0: return
  var iw, ih: cint
  let px = imageLoad(newWideCString(path), 1600, addr iw, addr ih)
  if px == nil:
    w.toast("Windows can't read that picture")
    return
  var rgba = newSeq[byte](int(iw) * int(ih) * 4)
  copyMem(addr rgba[0], px, rgba.len)
  cfree(px)
  (rgba, int(iw), int(ih))

proc photoForCodes*(w: Win, codes: seq[string], floor: string, queued: proc ())

# ---------------------------------------------------------------- the photo queue, kept on disk (the user, 2026-10-08:
# "background compression and a photo queue"; since 2026-10-09 kept on disk like Android's, decision 0049, and the
# GNOME app's: apps/common/photoqueue.nim). Each photo (its pixels and its job: code or codes, caption, note, floor,
# client_id) is written to the device's own store first, as sealed rows (AES-256-GCM under the store's key, which
# DPAPI protects: platform/windows/src/kksw/keystore.nim), then compressed (JPEG XL at effort 9 takes seconds) on a
# worker thread, one photo after another in the order they were added, and proposed as soon as it is compressed, so
# they arrive in order. It is removed only once the core accepted it (or it was a repeat: the client_id) or refused it.
# A failure (the encoder, the core throwing) keeps it: it is tried again a minute later, 5 times in a run; then it
# waits for the next start. A crash, a kill or a logout loses nothing: the next start sends what is left, in order.
# Photos that failed show under "Photos not sent" (Try again, Discard). A removed device's wipe deletes the queue.

type
  EncJob = object
    key, clientId: string       ## the result is matched on both: a key can be taken again after a discard
    rgb: seq[byte]
    w, h: int
    fail: bool                 ## tests: KKS_TEST_ENCODE_FAIL makes the first n encodes fail
  EncDone = object
    key, clientId: string
    data: string
    err: string

var
  encJobs: Channel[EncJob]
  encDone: Channel[EncDone]
  encThread: Thread[void]
  encStarted = false
  pq: PhotoQueue               ## main thread only (the store's thread); nil until the main screen first shows
  parked: seq[QueuedPhoto]     ## main thread only: failed too often in this run; kept on disk, sent at the next start
  whyOf = initTable[string, string]()   ## a photo's last failure (Photos not sent), by its key
  wipedAll = false             ## the device was removed: nothing more is written or sent
  polling = false
  failLeft = (try: max(0, parseInt(getEnv("KKS_TEST_ENCODE_FAIL", "0"))) except ValueError: 0)
  retryWait = (try: max(0, parseInt(getEnv("KKS_TEST_RETRY_MS", $RetryMs))) except ValueError: RetryMs)
    ## tests: a failed photo's wait before it is tried again
  failWin: HWND
  refillFailed: proc ()

proc encWorker() {.thread.} =
  while true:
    let j = encJobs.recv()
    var d = EncDone(key: j.key, clientId: j.clientId)
    try:
      if j.fail: d.err = "the encoder failed (a test)"
      else:
        var rgba = newSeq[byte](j.w * j.h * 4)      # the queue keeps RGB; the encoder takes RGBA (opaque)
        for i in 0 ..< j.w * j.h:
          rgba[4 * i] = j.rgb[3 * i]
          rgba[4 * i + 1] = j.rgb[3 * i + 1]
          rgba[4 * i + 2] = j.rgb[3 * i + 2]
          rgba[4 * i + 3] = 255
        var n: csize_t
        let p = jxlEncode(addr rgba[0], cint(j.w), cint(j.h), Distance, Effort, addr n)
        if p == nil: d.err = "the JPEG XL encoder failed"
        else:
          d.data = newString(int(n))
          copyMem(addr d.data[0], p, int(n))
          cfree(p)
    except CatchableError, Defect:      # always answer: a dead worker would leave the queue waiting for ever
      d.err = getCurrentExceptionMsg()
    encDone.send(d)

proc codesOf(q: QueuedPhoto): seq[string] = (if q.codes.len > 0: q.codes else: @[q.kks])

proc nameOf(q: QueuedPhoto): string = q.name   ## its code, or the first of several "and N more"

iterator kept(): QueuedPhoto =
  ## every photo not sent yet: in the queue (waiting, being compressed, waiting for a retry), then the parked ones
  if pq != nil:
    for q in pq.items: yield q
  for q in parked: yield q

proc failed(q: QueuedPhoto): bool = q.tries > 0 or q.key in whyOf

proc queuedCount*(): int =
  ## photos waiting or being compressed (not failed)
  for q in kept():
    if not q.failed: inc result

proc failedCount*(): int =
  ## photos that failed in this run (Photos not sent): tried again by themselves, kept until sent or discarded
  for q in kept():
    if q.failed: inc result

proc queuedFor*(kks: string): int =
  for q in kept():
    if not q.failed and kks in q.codesOf: inc result

proc failedFor*(kks: string): int =
  for q in kept():
    if q.failed and kks in q.codesOf: inc result

proc queueText*(): string =
  var names: seq[string]
  for q in kept():
    if not q.failed: names.add q.nameOf
  if names.len == 0: return ""
  "Compressing " & (if names.len == 1: "1 photo" else: $names.len & " photos") & " (" & names[0] &
    (if names.len > 1: ", then " & names[1 .. ^1].join(", ") else: "") & "). They are sent in order; you can keep working."

proc showQueue(w: Win) =
  if w.queueLabel == nil: return
  w.queueLabel.setText(queueText())
  w.failedButton.setText("Photos not sent (" & $failedCount() & ")…")
  if refillFailed != nil: refillFailed()
  w.relayout()

proc GetCurrentProcess(): pointer {.importc, stdcall, header: "<windows.h>".}
proc TerminateProcess(p: pointer, code: cuint): BOOL {.importc, stdcall, header: "<windows.h>".}

proc submitOne(w: Win, q: var QueuedPhoto, data: string) =
  ## one code's photo through the core (§9 submit with the photo's client_id). Raises ApiError when the core refuses it
  if q.floor.len == 0:
    # the floor was asked with an earlier photo of this code that is kept (not sent; its own, or one for several
    # codes): it goes with this one too, or a photo would arrive without it (the core writes a floor only while the
    # code has none)
    block find:
      for f in kept():
        if f.key != q.key and q.kks in f.codesOf and f.floor.len > 0:
          q.floor = f.floor
          break find
  var payload = newObj(@[("kks", newStr(q.kks)), ("caption", newStr(q.caption)),
                         ("dataUrl", newStr("data:image/jxl;base64," & encode(data)))])
  if q.floor.len > 0: payload["floor"] = newStr(q.floor)   # written first, only if the code still has no floor
  var body = newObj(@[("kind", newStr("photo")), ("payload", payload), ("client_id", newStr(q.clientId))])
  if q.note.strip.len > 0: body["note"] = newStr(q.note.strip)
  let r = w.a.call("POST", "/api/submit", body)
  let what = "photo of " & q.kks
  case (if r.get("status") != nil and r["status"].isStr: r["status"].s else: "pending")
  of "approved": w.toast("Saved: " & what)
  of "conflict": w.toast("Held: it clashes with a pending change (see Approvals)")
  else: w.toast("Sent for approval: " & what)

proc submitMany(w: Win, q: QueuedPhoto, data: string) =
  ## one photo of several codes ("Photo for all", multi.nim): one /api/submit-many, the job's client_id as the prefix
  ## (a resend after a crash skips the codes already sent). Raises ApiError when the core refuses it.
  ## The floor asked before the photo goes in the payload: the core writes it, before the photo, for each code that
  ## has no floor and no floor proposal of this person still open (as it does for one photo); the others keep theirs.
  var arr = newArr()
  for k in q.codes: arr.elems.add newStr(k)
  var payload = newObj(@[("caption", newStr(q.caption)), ("dataUrl", newStr("data:image/jxl;base64," & encode(data)))])
  if q.floor.len > 0: payload["floor"] = newStr(q.floor)
  var body = newObj(@[("kind", newStr("photo")), ("kks", arr), ("client_id", newStr(q.clientId)), ("payload", payload)])
  if q.note.strip.len > 0: body["note"] = newStr(q.note.strip)
  let r = w.a.call("POST", "/api/submit-many", body)
  var pending, held, floorSet, floorWaits, floorHeld = 0
  if r.get("results") != nil:
    for x in r["results"].elems:
      case s(x, "status")
      of "approved": discard
      of "conflict": inc held
      else: inc pending
      # this code's floor (the result's "floor"): {"status": "unchanged"} when it kept its own
      let f = x.get("floor")
      # (a resend's answer for a proposal since rejected or withdrawn is not counted)
      if f != nil and f.kind == jObj:
        case s(f, "status")
        of "approved": inc floorSet
        of "pending": inc floorWaits
        of "conflict": inc floorHeld
        else: discard
  var msg = "Photo sent for " & (if q.codes.len == 1: "1 code" else: $q.codes.len & " codes")
  if pending > 0: msg.add " · " & $pending & " await approval"
  if held > 0: msg.add " · " & $held & " held (they clash with pending changes)"
  if pending == 0 and held == 0: msg.add " · saved"
  if floorSet > 0: msg.add " · floor " & q.floor & " saved for " & $floorSet
  if floorWaits > 0: msg.add " · floor " & q.floor & " proposed for " & $floorWaits & " (awaits approval)"
  if floorHeld > 0: msg.add " · floor " & q.floor & " held for " & $floorHeld & " (it clashes with pending changes)"
  w.toast(msg)

proc GetClassNameW(h: HWND, buf: WideCString, n: cint): cint {.importc, stdcall, header: "<windows.h>".}

proc typingIn(f: HWND): bool =
  ## the keyboard is in a text field (a rebuild would lose what is being typed)
  if f == nil: return false
  var buf = newWideCString("", 32)
  let n = GetClassNameW(f, buf, 32)
  n > 0 and ($buf).toLowerAscii == "edit"

proc panelQuiet(w: Win) =
  ## the open panel shows the queue per code: rebuilt, but never under a field being typed in
  let f = GetFocus()
  if w.selected.len > 0 and not w.picking and (f == nil or GetParent(f) != w.panel.hwnd or not typingIn(f)):
    w.rebuildPanel()

proc floorAfterDiscard(w: Win, gone: QueuedPhoto)

proc received(w: Win, d: EncDone) =
  ## one photo compressed (or not): send it, then remove it, keep it for a retry, or report a refusal
  if pq == nil or pq.wiped: return
  var it: QueuedPhoto
  var found = false
  for q in pq.items:
    if q.key == d.key and q.clientId == d.clientId:
      it = q
      found = true
  if not found: return          # not the photo it was compressed for (discarded meanwhile)
  var outcome = Sent
  var why = ""
  if d.err.len > 0:
    (outcome, why) = (Failed, "could not be compressed: " & d.err)
  else:
    try:
      if it.codes.len > 0: w.submitMany(it, d.data) else: w.submitOne(it, d.data)
      # tests: the app dies after the core took the photo, before the queue forgot it (the resend must not add it twice)
      if getEnv("KKS_TEST_PHOTO_DIE_AFTER_SEND").len > 0: discard TerminateProcess(GetCurrentProcess(), 9)
    except ApiError as e:
      if e.status >= 400: (outcome, why) = (Refused, e.msg)
      else: (outcome, why) = (Failed, "not sent: " & e.msg)
    except CatchableError as e:
      (outcome, why) = (Failed, "not sent: " & e.msg)
  let now = nowMs()
  var r: string
  try: r = pq.finish(d.key, outcome, why, now)
  except CatchableError as e:          # the store: the photo stays queued (a resend is kept once, by its client_id)
    r = "Photo of " & it.nameOf & ": the queue could not be updated (" & e.msg & ")"
  if outcome == Failed:
    whyOf[d.key] = why
    var still = false
    for q in pq.items.mitems:
      if q.key == d.key:
        still = true
        q.readyAt = now + retryWait
    if not still:               # its tries in this run are used up: kept on disk, tried again at the next start
      parked.add it
  else:
    whyOf.del d.key
    # a refused photo may have carried the floor its code was asked for: another photo of the code takes it over
    if outcome == Refused: w.floorAfterDiscard(it)
  if r.len > 0: w.toast(r)

proc startNext(w: Win) =
  ## start compressing the next photo (the first one not waiting for a retry), if none is being worked on
  if pq == nil or pq.wiped: return
  if not encStarted:
    encJobs.open()
    encDone.open()
    createThread(encThread, encWorker)
    encStarted = true
  # tests: KKS_TEST_PHOTO_HOLD keeps the photos queued without compressing them (the app is killed with photos queued)
  if getEnv("KKS_TEST_PHOTO_HOLD").len > 0: return
  var reports: seq[string]
  let (ok, it, px) = pq.next(nowMs(), reports)
  for r in reports: w.toast(r)
  if ok:
    let fail = failLeft > 0
    if fail: dec failLeft
    encJobs.send(EncJob(key: it.key, clientId: it.clientId, rgb: px, w: it.w, h: it.h, fail: fail))

proc pollQueue(w: Win) =
  var changed = false
  try:
    if pq != nil and not pq.wiped:
      while true:
        let (got, d) = encDone.tryRecv()
        if not got: break
        changed = true
        w.received(d)
      w.startNext()
  finally:
    # the next poll whatever happened above (a store error, a screen update): an error must not stop the queue
    polling = pq != nil and not pq.wiped and pq.count > 0
    if polling: discard afterMs(200, proc () = w.pollQueue())
  if changed:
    w.showQueue()
    w.panelQuiet()

proc pump(w: Win) =
  ## start the next photo, and keep one timer going while photos are queued (results, retries that come due)
  w.startNext()
  if polling or pq == nil or pq.wiped or pq.count == 0: return
  polling = true
  discard afterMs(200, proc () = w.pollQueue())

proc resumePhotos*(w: Win) =
  ## once, when the main screen first shows: the photos left from before (a crash, a kill, a logout) go first, in
  ## their order
  if pq != nil or wipedAll: return
  pq = newPhotoQueue(w.a.store)
  var reports: seq[string]
  try: reports = pq.resume()
  except CatchableError as e: reports.add "The queued photos could not be read: " & e.msg
  for r in reports: w.toast(r)
  if pq.count > 0:
    w.toast("Sending " & (if pq.count == 1: "1 photo" else: $pq.count & " photos") & " kept from before")
  w.pump()
  w.showQueue()

proc photosWiped*(s: DbStore) =
  ## a removed device: the store's wipe deleted the queued photos; nothing more is compressed, written or sent
  wipedAll = true
  if pq == nil: pq = newPhotoQueue(s)
  pq.wipe()
  parked.setLen(0)
  whyOf.clear()

proc enqueue(w: Win, rgba: seq[byte], pw, ph: int, kks, caption, note, floor: string, codes: seq[string] = @[]): bool =
  ## keep the photo on disk and queue it; false (and said) when it couldn't be kept
  let what = if codes.len > 0: $codes.len & " codes" else: kks
  if wipedAll:
    w.toast("This device was removed from the plant: the photo of " & what & " was not added")
    return false
  w.resumePhotos()
  var rgb = newSeq[byte](pw * ph * 3)
  for i in 0 ..< pw * ph:
    rgb[3 * i] = rgba[4 * i]
    rgb[3 * i + 1] = rgba[4 * i + 1]
    rgb[3 * i + 2] = rgba[4 * i + 2]
  # never over the core's limits: such a photo would be refused (the editor caps them already)
  try: discard pq.add(w.a.p, rgb, pw, ph, kks, capText(caption, MaxCaption), capText(note, MaxNote), floor, nowMs(), codes)
  except CatchableError as e:
    w.toast("The photo of " & what & " could not be kept for sending (" & e.msg & "). It was not added.")
    return false
  w.toast("Photo of " & what & " queued: it is compressed and sent in the background")
  w.pump()
  w.showQueue()
  w.panelQuiet()
  true

proc floorKnown(w: Win, kks: string): bool
proc floorsMissing*(w: Win, codes: openArray[string], queued = true): seq[string]

proc floorAfterDiscard(w: Win, gone: QueuedPhoto) =
  ## a discarded photo may have carried the floor its code was asked for (the floor first; a photo for several codes:
  ## the floor of those that had none): another photo of the code still waiting takes it over (on disk too); with
  ## none, the person is told, and the next photo of the code asks again
  if gone.floor.len == 0: return
  var check: seq[string]
  for code in gone.codesOf:
    block one:
      for q in kept():                    # another kept photo already carries a floor for it
        if q.key != gone.key and code in q.codesOf and q.floor.len > 0: break one
      for q in kept():                    # a photo of this code alone takes the floor over
        if q.key != gone.key and q.codes.len == 0 and q.kks == code:
          try:
            pq.setFloor(q.key, gone.floor)
            for p in parked.mitems:
              if p.key == q.key: p.floor = gone.floor
            break one
          except CatchableError as e: w.toast("The floor could not be kept with the next photo: " & e.msg)
      check.add code
  if check.len == 0: return
  let lost = w.floorsMissing(check)
  if lost.len == 1:
    w.toast("The floor of " & lost[0] & " (" & gone.floor & ") was to be sent with that photo: it was not saved. " &
            "The next photo of " & lost[0] & " asks for it again.")
  elif lost.len > 1:
    w.toast("The floor (" & gone.floor & ") of " & lost[0 ..< min(5, lost.len)].join(", ") &
            (if lost.len > 5: " and " & $(lost.len - 5) & " more" else: "") &
            " was to be sent with that photo: it was not saved. Their next photo asks for it again.")

proc retryNow(w: Win, key: string) =
  ## Try again: at once, with a fresh count of tries
  if pq == nil or pq.wiped: return
  whyOf.del key
  var i = 0
  while i < parked.len:
    if parked[i].key == key:
      var q = parked[i]
      parked.delete(i)
      q.tries = 0
      q.readyAt = 0
      pq.items.add q
      break
    inc i
  for q in pq.items.mitems:
    if q.key == key:
      q.tries = 0
      q.readyAt = 0
  w.pump()
  w.showQueue()
  w.panelQuiet()

proc discardPhoto(w: Win, key, clientId: string) =
  ## by key and client_id: while the question was open the photo may have been sent and its key taken by a new one
  if pq == nil or pq.wiped: return
  var gone: QueuedPhoto
  var found = false
  for q in kept():
    if q.key == key and q.clientId == clientId:
      gone = q
      found = true
  if not found: return
  if pq.busy == key:
    w.toast("That photo is being tried again right now: discard it once that try has ended")
    return
  try: pq.forget(key)
  except CatchableError as e:
    w.toast("The photo could not be discarded: " & e.msg)
    return
  whyOf.del key
  for i in countdown(parked.high, 0):
    if parked[i].key == key: parked.delete(i)
  w.floorAfterDiscard(gone)
  w.showQueue()
  w.panelQuiet()

proc failedWindow*(w: Win) =
  ## the photos that were not sent: each with why, Try again and Discard
  if failWin != nil and IsWindow(failWin) != 0:
    SetForegroundWindow(failWin)
    return
  let (h, p) = popup(w.hwnd, "Photos not sent", 520, 440, proc () =
    failWin = nil
    refillFailed = nil, escape = true)
  failWin = h
  proc fill() =
    p.clear()
    var items: seq[QueuedPhoto]
    for q in kept():
      if q.failed: items.add q
    if items.len == 0:
      p.dim("Every photo was sent or discarded.")
    else:
      p.dim("These photos are kept on this computer until they are sent or you discard them. They are tried again " &
            "by themselves, and when Walkdown next starts.")
    for i in 0 ..< items.len:
      closureScope:
        let q = items[i]
        let key = q.key
        let cid = q.clientId
        p.title("Photo of " & q.nameOf)
        if q.caption.len > 0: p.label(q.caption)
        p.dim(whyOf.getOrDefault(key, "Not sent").capitalizeAscii)
        p.buttons(("Try again", proc () = w.retryNow(key)),
          ("Discard", proc () =
            if ask(h, "Discard this photo?", "It was never sent: it is lost."): w.discardPhoto(key, cid)))
    p.buttons(("Close", proc () = DestroyWindow(h)))
    p.layout()
  refillFailed = fill
  fill()
  ShowWindow(h, SW_SHOW)

# ---------------------------------------------------------------- the floor first (the user, 2026-10-08)

proc floorOf(n: JNode): string =
  if n != nil and n.get("floor") != nil and n["floor"].isStr: n["floor"].s.strip else: ""

proc floorOpen(w: Win, kks: string, mine: seq[JNode], queued: bool): bool =
  ## a floor for this code is on its way: with a queued or kept photo (if `queued`), or proposed by me and still open
  if queued:
    for q in kept():
      if kks in q.codesOf and q.floor.len > 0: return true
  for sub in mine:
    let p = sub.get("payload")
    if sub["kind"].s == "equipment" and p != nil and s(p, "kks") == kks and p.get("changes") != nil and
       floorOf(p["changes"]).len > 0: return true

proc floorsMissing*(w: Win, codes: openArray[string], queued = true): seq[string] =
  ## the codes with no floor yet: none on the equipment (the loaded model, then the core itself: the model lags a
  ## change by a moment), none on its way. `queued` = false: a floor riding on a queued or kept photo doesn't count
  ## (Photo for all: its photo goes without a floor of its own, and a kept photo may be discarded with its floor)
  var st: JNode = nil
  var mine: seq[JNode]
  var mineRead = false
  for k in codes:
    if floorOf(w.m.equipment(k)).len > 0: continue
    if st == nil:
      try: st = w.a.call("GET", "/api/state")["equipment"]
      except CatchableError: st = newObj()
    if floorOf(st.get(k)).len > 0: continue
    if not mineRead:
      mine = w.myOpen()
      mineRead = true
    if not w.floorOpen(k, mine, queued): result.add k

proc floorKnown(w: Win, kks: string): bool = w.floorsMissing([kks]).len == 0

proc validFloor(f: string): bool = f == "10" or (f.len == 1 and f[0] in Digits)

proc askFloorWith(w: Win, title, text, fieldName: string, height: int, fn: proc (floor: string),
                  cancelled: proc () = nil, closed: proc () = nil): HWND =
  ## the floor's window: `fn` gets a valid floor (the window is gone by then); `cancelled`: it closed without one
  ## (Cancel, Escape, its close box, or closed from outside); `closed`: it closed, either way (before `fn`)
  var hw: HWND
  var answered = false
  let (h, p) = popup(w.hwnd, title, 480, height, proc () =
    if closed != nil: closed()
    if not answered and cancelled != nil: later(cancelled), escape = true)
  hw = h
  p.title(title)
  p.dim(text)
  let e = p.field(fieldName, "")
  let msg = p.label("")
  p.buttons(("Continue", proc () =
    let f = e.text.strip
    if not validFloor(f):
      msg.setText("Floor: a whole number from 0 to 10 (the height goes in Elevation).")
      return
    answered = true
    DestroyWindow(hw)
    fn(f)), ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)
  SetFocus(e)
  hw

proc askFloor(w: Win, kks: string, fn: proc (floor: string), cancelled: proc () = nil) =
  ## a photo needs its floor: asked before the picture, sent with it (the core writes it first, as its own change).
  ## `cancelled`: the window closed without a floor (Cancel, Escape, its close box)
  discard w.askFloorWith("Which floor is " & kks & " on?",
    "A photo needs its floor, and this equipment has none yet. Enter the floor: a whole number from 0 (ground) " &
    "to 10. It is sent with the photo.", "Floor of " & kks & " (0–10)", 330, fn, cancelled)

proc askFloors*(w: Win, missing: seq[string], total: int, fn: proc (floor: string), cancelled: proc () = nil,
                closed: proc () = nil): HWND =
  ## one photo for `total` codes, of which `missing` have no floor: asked once, before the picture, as for one code
  ## (the user, 2026-10-10: a member can't set the floors first, a floor needs approval before it counts). The floor
  ## goes with the photo and the core writes it for the codes that still have none; the others keep theirs
  let n = missing.len
  let names = missing[0 ..< min(20, n)].join(", ") & (if n > 20: " and " & $(n - 20) & " more" else: "")
  let text =
    if n == 1 and total == 1:
      "A photo needs its floor, and " & missing[0] & " has none yet. "
    elif n == total:
      "A photo needs its floor, and the " & $total & " selected codes have none yet: " & names & ". "
    else:
      "A photo needs its floor, and " & $n & " of the " & $total & " selected codes " &
      (if n == 1: "has" else: "have") & " none yet: " & names & ". "
  let rest = total - n
  w.askFloorWith(if n == 1: "Which floor is " & missing[0] & " on?" else: "Which floor are these " & $n & " codes on?",
    text & "Enter " & (if n == 1: "its" else: "their") & " floor: a whole number from 0 (ground) to 10. " &
    "It is sent with the photo" &
    (if rest == 0: "." elif rest == 1: ", for " & (if n == 1: "this code" else: "these codes") & " only: the other code keeps its floor."
     else: ", for " & (if n == 1: "this code" else: "these codes") & " only: the other " & $rest & " keep their floors."),
    "Floor of the codes without one (0–10)", 340 + 6 * min(20, n), fn, cancelled, closed)

proc hasPlate(w: Win, kks: string): bool =
  ## the code has a tag plate photo, or one is on its way (queued, kept, or my proposal waiting for approval)
  for q in kept():
    if kks in q.codesOf and isPlate(q.caption): return true
  for sub in w.myOpen():
    let pl = sub.get("payload")
    if sub["kind"].s == "photo" and pl != nil and s(pl, "kks") == kks and isPlate(s(pl, "caption")): return true
  let ph = if w.m.state != nil: w.m.state.get("photos") else: nil
  if ph != nil:
    for p in ph.elems:
      if s(p, "kks") == kks and isPlate(s(p, "caption")): return true

proc plateCaption(extra: string): string =
  ## a tag plate photo's caption starts with "Tag plate" (PROTOCOL-v2 §9)
  if extra.strip.len == 0: PlateCaption else: PlateCaption & " · " & extra.strip

proc addPhoto*(w: Win, kks: string, plate = false) =
  ## an equipment photo, or (plate) a photo of its tag plate, through the queue. The floor first when the code has
  ## none. After an equipment photo of a code with no tag plate photo, the app offers one (as Android and GNOME do).
  proc go(floor: string) =
    let (rgba, pw, ph) = w.pickPicture(if plate: "Choose a photo of the tag plate" else: "Add a photo")
    if rgba.len == 0: return
    annotate(w.hwnd, rgba, pw, ph, proc (marked: seq[byte], caption, note: string) =
      let offer = not plate and not w.hasPlate(kks)
      let cap = if plate: plateCaption(caption) else: caption.strip
      if floor.len == 0 and not w.floorKnown(kks):
        # the photo that was to carry the floor was discarded while this editor was open: ask now. Without an answer
        # the photo still goes (the marks are never lost), without a floor
        let n = note.strip
        w.askFloor(kks, proc (f: string) = discard w.enqueue(marked, pw, ph, kks, cap, n, f),
                   proc () = discard w.enqueue(marked, pw, ph, kks, cap, n, ""))
        return
      discard w.enqueue(marked, pw, ph, kks, cap, note.strip, floor)
      if offer:
        later(proc () =
          if askYesNo(w.hwnd, "And its tag plate?", "A photo of the metal plate with the KKS code helps the next " &
                      "person find this equipment. Add one now?"):
            w.addPhoto(kks, plate = true)),
      askNote = not w.isAdmin,
      captionMax = if plate: MaxCaption - (PlateCaption & " · ").runeLen else: MaxCaption)
  if w.floorKnown(kks): go("")
  else: w.askFloor(kks, go)

proc photoForCodes*(w: Win, codes: seq[string], floor: string, queued: proc ()) =
  ## one picture for several codes ("Photo for all", multi.nim): from a file, marked up in the editor, then queued like
  ## any photo (kept on disk, compressed on the worker thread, sent with submit-many); `queued` runs once it is.
  ## `floor`: asked before (askFloors) for the codes that have none; "" when every code's floor was known
  let (rgba, pw, ph) = w.pickPicture("Add a photo")
  if rgba.len == 0: return
  annotate(w.hwnd, rgba, pw, ph, proc (marked: seq[byte], caption, note: string) =
    if w.enqueue(marked, pw, ph, codes[0], caption.strip, note.strip, floor, codes): queued(),
    askNote = not w.isAdmin)

# ---------------------------------------------------------------- the panel section

proc credit*(p: JNode): string =
  ## who took a photo and when ("by Ali User, 2026-10-08"): when it was sent, else when it took effect
  let by = s(p, "by_name")
  let tsv = if p.get("submitted") != nil and p["submitted"].kind == jInt and p["submitted"].i > 0: p["submitted"] else: p.get("created")
  let d = if tsv != nil and tsv.kind == jInt and tsv.i > 0: fromUnix(tsv.i).local.format("yyyy-MM-dd") else: ""
  (if by.len > 0: "by " & by else: "") & (if by.len > 0 and d.len > 0: ", " else: "") & d

proc photoSection*(w: Win, p: Page, kks: string) =
  p.title("Photos")
  let ph = if w.m.state != nil: w.m.state.get("photos") else: nil
  if ph != nil:
    # the tag plate first: it is how the equipment is recognised in the field
    let items = ph.elems.filterIt(s(it, "kks") == kks and isPlate(s(it, "caption"))) &
                ph.elems.filterIt(s(it, "kks") == kks and not isPlate(s(it, "caption")))
    let lp1 = toSeq(0 ..< items.len)
    for lp1i in 0 ..< lp1.len:
      closureScope:
        let i = lp1[lp1i]
        let item = items[i]
        let file = s(item, "file")
        let caption = s(item, "caption")
        let pid = s(item, "id")
        let who = credit(item)
        let (have, data) = w.photoBytes(file)
        if isPlate(caption): p.label("Tag plate")
        if have:
          var iw, ih: cint
          let pix = jxlDecode(unsafeAddr data[0], csize_t(data.len), addr iw, addr ih)
          if pix != nil:
            var tw, th: cint
            let hb = thumb(pix, iw, ih, px(260), px(180), addr tw, addr th)
            cfree(pix)
            let (img, _) = control(p.hwnd, "STATIC", caption, SS_BITMAP)
            SendMessageW(img, STM_SETIMAGE, IMAGE_BITMAP, cast[LPARAM](hb))
            p.custom(img, int(th) * 96 div dpi)
          if who.len > 0: p.dim(who)
          discard p.buttons(("Open photo" & (if caption.len > 0: ": " & caption else: ""), proc () = w.showPhoto(data, caption)),
                    ("Delete", proc () =
                      if ask(w.hwnd, "Delete this photo?", "It is removed for everyone once approved."):
                        discard w.submit("photo_delete", newObj(@[("photo_id", newStr(pid))]), "delete a photo")))
        else:
          discard p.dim("A photo not on this device yet (it arrives with the next sync)" & (if caption.len > 0: ": " & caption else: "") &
                        (if who.len > 0: " · " & who else: ""))
  let q = queuedFor(kks)
  if q > 0:
    p.dim((if q == 1: "1 photo" else: $q & " photos") & " of this equipment being compressed; sent when ready.")
  let f = failedFor(kks)
  if f > 0:
    p.dim((if f == 1: "1 photo" else: $f & " photos") & " of this equipment not sent: see Photos not sent below the drawing.")
  p.buttons(("Add a photo from a file…", proc () = w.addPhoto(kks)),
            ((if w.hasPlate(kks): "New tag plate photo from a file…" else: "Tag plate photo from a file…"), proc () =
              w.addPhoto(kks, plate = true)))
