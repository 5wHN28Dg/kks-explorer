## Photos (R6; the GNOME app's photos.nim): thumbnails with who took each, a zoomable viewer, delete, add from a file
## (WIC → upright, 1600 px → the annotation editor → the photo queue: JPEG XL d1.9 effort 9 on a worker thread →
## submit), the tag plate's photo, and the floor asked first when the code has none. Camera capture: see
## apps/windows/README.md.

import std/[base64, strutils, tables, math, sequtils, os, times, random, typedthreads]
import kks/json
import kks/model
import appstate
import kks/node
import kksl/dbstore
import w32, ui, win, annotate

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

proc takePhoto*(w: Win, send: proc (dataUrl, caption, note: string)) =
  ## one photo for several codes (multi.nim): a picture from a file, the annotation editor, JPEG XL; `send` gets its
  ## data URL. (One code's photos go through the queue below.)
  let (rgba, pw, ph) = w.pickPicture("Add a photo")
  if rgba.len == 0: return
  annotate(w.hwnd, rgba, pw, ph, proc (marked: seq[byte], caption, note: string) =
    w.toast("Compressing…")
    var n: csize_t
    let jxl = jxlEncode(unsafeAddr marked[0], cint(pw), cint(ph), Distance, Effort, addr n)
    if jxl == nil:
      w.toast("Could not compress the photo")
      return
    var data = newString(int(n))
    copyMem(addr data[0], jxl, int(n))
    cfree(jxl)
    send("data:image/jxl;base64," & encode(data), caption.strip, note.strip),
    askNote = not w.isAdmin)

# ---------------------------------------------------------------- the photo queue (the user, 2026-10-08: "background
# compression and a photo queue"; the GNOME app's queue). JPEG XL at effort 9 takes seconds: it runs on a worker
# thread, one photo after another in the order they were added, and goes on while the panel changes or closes. Each
# photo is proposed as soon as it is compressed, so they arrive in order. A photo that can't be compressed or sent is
# kept with its pixels (Photos not sent: Try again, Discard), never dropped; closing the window with photos still in
# the queue or not sent asks first (kks_explorer.nim). Before, the encoder ran in the editor's Send and froze the
# window meanwhile.

type
  EncJob = object
    id: int
    rgba: seq[byte]
    w, h: int
    fail: bool                 ## tests: KKS_TEST_ENCODE_FAIL makes the first n encodes fail
  EncDone = object
    id: int
    data: string
    err: string
  Queued = object
    id: int
    kks, caption, note, floor, clientId: string
    rgba: seq[byte]            ## kept until the photo is sent: Try again starts from it
    w, h: int
    data: string               ## the JPEG XL, once compressed
    why: string                ## what went wrong (Photos not sent)

var
  encJobs: Channel[EncJob]
  encDone: Channel[EncDone]
  encThread: Thread[void]
  encStarted = false
  queue: seq[Queued]           ## main thread only: waiting or being compressed, oldest first
  failed: seq[Queued]          ## main thread only: not sent, kept until sent or discarded
  nextId = 0
  polling = false
  failLeft = (try: max(0, parseInt(getEnv("KKS_TEST_ENCODE_FAIL", "0"))) except ValueError: 0)
  failWin: HWND
  refillFailed: proc ()

randomize()

proc encWorker() {.thread.} =
  while true:
    let j = encJobs.recv()
    var d = EncDone(id: j.id)
    try:
      if j.fail: d.err = "the encoder failed (a test)"
      else:
        var n: csize_t
        let p = jxlEncode(unsafeAddr j.rgba[0], cint(j.w), cint(j.h), Distance, Effort, addr n)
        if p == nil: d.err = "the JPEG XL encoder failed"
        else:
          d.data = newString(int(n))
          copyMem(addr d.data[0], p, int(n))
          cfree(p)
    except CatchableError, Defect:      # always answer: a dead worker would leave the queue waiting for ever
      d.err = getCurrentExceptionMsg()
    encDone.send(d)

proc queuedCount*(): int = queue.len           ## photos still being compressed or waiting
proc failedCount*(): int = failed.len          ## photos that were not sent (kept)

proc queuedFor*(kks: string): int =
  for q in queue:
    if q.kks == kks: inc result

proc failedFor*(kks: string): int =
  for q in failed:
    if q.kks == kks: inc result

proc queueText*(): string =
  if queue.len == 0: return ""
  "Compressing " & (if queue.len == 1: "1 photo" else: $queue.len & " photos") & " (" & queue[0].kks &
    (if queue.len > 1: ", then " & queue[1 .. ^1].mapIt(it.kks).join(", ") else: "") &
    "). They are sent in order; you can keep working."

proc showQueue(w: Win) =
  if w.queueLabel == nil: return
  w.queueLabel.setText(queueText())
  w.failedButton.setText("Photos not sent (" & $failed.len & ")…")
  if refillFailed != nil: refillFailed()
  w.relayout()

proc clientId(): string =
  ## the photo's client_id: a retry of a send that went through can't add it twice
  result = "wq" & $getTime().toUnix & "x"
  for _ in 0 ..< 12: result.add "0123456789abcdef"[rand(15)]

proc sendQueued(w: Win, q: var Queued): bool =
  var payload = newObj(@[("kks", newStr(q.kks)), ("caption", newStr(q.caption)),
                         ("dataUrl", newStr("data:image/jxl;base64," & encode(q.data)))])
  if q.floor.len > 0: payload["floor"] = newStr(q.floor)   # written first, only if the code still has no floor
  let (st, err) = w.trySubmit("photo", payload, "photo of " & q.kks, q.note, q.clientId)
  if st.len > 0: return true
  q.why = "Not sent: " & err
  false

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

proc pollQueue(w: Win) =
  var changed = false
  while true:
    let (got, d) = encDone.tryRecv()
    if not got: break
    var i = 0
    while i < queue.len and queue[i].id != d.id: inc i
    if i >= queue.len: continue
    var q = queue[i]
    queue.delete(i)
    changed = true
    if d.err.len > 0:
      q.why = "Could not be compressed: " & d.err
      failed.add q
      w.toast("The photo of " & q.kks & " could not be compressed (" & d.err & "). It is kept: Photos not sent…")
    else:
      q.data = d.data
      if not w.sendQueued(q):
        failed.add q
        w.toast("The photo of " & q.kks & " was not sent (" & q.why & "). It is kept: Photos not sent…")
  # the next poll first: an error in the screen updates below must not stop the queue
  polling = queue.len > 0
  if polling: discard afterMs(200, proc () = w.pollQueue())
  if changed:
    w.showQueue()
    w.panelQuiet()

proc enqueueJob(w: Win, q: Queued) =
  if not encStarted:
    encJobs.open()
    encDone.open()
    createThread(encThread, encWorker)
    encStarted = true
  queue.add q
  let fail = failLeft > 0
  if fail: dec failLeft
  encJobs.send(EncJob(id: q.id, rgba: q.rgba, w: q.w, h: q.h, fail: fail))
  if not polling:
    polling = true
    discard afterMs(200, proc () = w.pollQueue())
  w.showQueue()

proc enqueue(w: Win, rgba: seq[byte], pw, ph: int, kks, caption, note, floor: string) =
  inc nextId
  w.enqueueJob(Queued(id: nextId, kks: kks, caption: caption, note: note, floor: floor, clientId: clientId(),
                      rgba: rgba, w: pw, h: ph))
  w.toast("Photo of " & kks & " queued: it is compressed and sent in the background")
  w.panelQuiet()

proc retryFailed(w: Win, i: int) =
  if i < 0 or i >= failed.len: return
  var q = failed[i]
  failed.delete(i)
  q.why = ""
  if q.data.len > 0:          # compressed already: send it again
    if not w.sendQueued(q):
      failed.add q
      w.toast("The photo of " & q.kks & " was not sent again (" & q.why & ")")
    w.showQueue()
    w.panelQuiet()
  else: w.enqueueJob(q)

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
    if failed.len == 0:
      p.dim("Every photo was sent or discarded.")
    else:
      p.dim("These photos are kept on this computer until they are sent or you discard them. Closing Walkdown loses them.")
    for i in 0 ..< failed.len:
      closureScope:
        let q = failed[i]
        let id = q.id
        p.title("Photo of " & q.kks)
        if q.caption.len > 0: p.label(q.caption)
        p.dim(q.why)
        p.buttons(("Try again", proc () =
          var j = 0
          while j < failed.len and failed[j].id != id: inc j
          w.retryFailed(j)),
          ("Discard", proc () =
            if ask(h, "Discard this photo?", "It was never sent: it is lost."):
              var j = 0
              while j < failed.len and failed[j].id != id: inc j
              if j < failed.len: failed.delete(j)
              w.showQueue()
              w.panelQuiet()))
    p.buttons(("Close", proc () = DestroyWindow(h)))
    p.layout()
  refillFailed = fill
  fill()
  ShowWindow(h, SW_SHOW)

# ---------------------------------------------------------------- the floor first (the user, 2026-10-08)

proc floorOf(n: JNode): string =
  if n != nil and n.get("floor") != nil and n["floor"].isStr: n["floor"].s.strip else: ""

proc floorOpen(w: Win, kks: string, mine: seq[JNode]): bool =
  ## a floor for this code is on its way: with a queued or kept photo, or proposed by me and still open
  for l in [addr queue, addr failed]:       # (not `queue & failed`: that copies every photo's pixels)
    for q in l[]:
      if q.kks == kks and q.floor.len > 0: return true
  for sub in mine:
    let p = sub.get("payload")
    if sub["kind"].s == "equipment" and p != nil and s(p, "kks") == kks and p.get("changes") != nil and
       floorOf(p["changes"]).len > 0: return true

proc floorsMissing*(w: Win, codes: openArray[string]): seq[string] =
  ## the codes with no floor yet: none on the equipment (the loaded model, then the core itself: the model lags a
  ## change by a moment), none on its way
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
    if not w.floorOpen(k, mine): result.add k

proc floorKnown(w: Win, kks: string): bool = w.floorsMissing([kks]).len == 0

proc validFloor(f: string): bool = f == "10" or (f.len == 1 and f[0] in Digits)

proc askFloor(w: Win, kks: string, fn: proc (floor: string)) =
  ## a photo needs its floor: asked before the picture, sent with it (the core writes it first, as its own change)
  var hw: HWND
  let (h, p) = popup(w.hwnd, "Which floor is " & kks & " on?", 480, 330, escape = true)
  hw = h
  p.title("Which floor is " & kks & " on?")
  p.dim("A photo needs its floor, and this equipment has none yet. Enter the floor: a whole number from 0 (ground) " &
        "to 10. It is sent with the photo.")
  let e = p.field("Floor of " & kks & " (0–10)", "")
  let msg = p.label("")
  p.buttons(("Continue", proc () =
    let f = e.text.strip
    if not validFloor(f):
      msg.setText("Floor: a whole number from 0 to 10 (the height goes in Elevation).")
      return
    DestroyWindow(hw)
    fn(f)), ("Cancel", proc () = DestroyWindow(hw)))
  p.layout()
  ShowWindow(hw, SW_SHOW)
  SetFocus(e)

proc hasPlate(w: Win, kks: string): bool =
  ## the code has a tag plate photo, or one is on its way (queued, kept, or my proposal waiting for approval)
  for l in [addr queue, addr failed]:
    for q in l[]:
      if q.kks == kks and isPlate(q.caption): return true
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
      w.enqueue(marked, pw, ph, kks, if plate: plateCaption(caption) else: caption.strip, note.strip, floor)
      if offer:
        later(proc () =
          if askYesNo(w.hwnd, "And its tag plate?", "A photo of the metal plate with the KKS code helps the next " &
                      "person find this equipment. Add one now?"):
            w.addPhoto(kks, plate = true)),
      askNote = not w.isAdmin)
  if w.floorKnown(kks): go("")
  else: w.askFloor(kks, go)

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
