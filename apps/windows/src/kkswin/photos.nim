## Photos (R6; the GNOME app's photos.nim): thumbnails, a zoomable viewer, delete, add from a file (WIC → upright,
## 1600 px → the annotation editor → JPEG XL d1.9 effort 9 → submit). Camera capture: see apps/windows/README.md.

import std/[base64, strutils, tables, math, sequtils, os]
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

# ---------------------------------------------------------------- the panel section

proc takePhoto*(w: Win, send: proc (dataUrl, caption, note: string)) =
  ## a picture from a file: upright, at most 1600 px, then the annotation editor, then JPEG XL; `send` gets its data URL
  # KKS_TEST_PHOTO: the end-to-end test's picture instead of the file dialog's answer
  let path = if getEnv("KKS_TEST_PHOTO").len > 0: getEnv("KKS_TEST_PHOTO")
             else: openFile(w.hwnd, "Add a photo", "Pictures|*.jpg;*.jpeg;*.png;*.heic;*.webp;*.bmp;*.tif;*.tiff|All files|*.*")
  if path.len == 0: return
  var iw, ih: cint
  let px = imageLoad(newWideCString(path), 1600, addr iw, addr ih)
  if px == nil:
    w.toast("Windows can't read that picture")
    return
  var rgba = newSeq[byte](int(iw) * int(ih) * 4)
  copyMem(addr rgba[0], px, rgba.len)
  cfree(px)
  let (pw, ph) = (int(iw), int(ih))
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

proc addPhoto(w: Win, kks: string) =
  w.takePhoto(proc (dataUrl, caption, note: string) =
    discard w.submit("photo", newObj(@[("kks", newStr(kks)), ("caption", newStr(caption)), ("dataUrl", newStr(dataUrl))]),
                     "photo of " & kks, note)
    w.rebuildPanel())

proc photoSection*(w: Win, p: Page, kks: string) =
  p.title("Photos")
  let ph = if w.m.state != nil: w.m.state.get("photos") else: nil
  if ph != nil:
    let items = ph.elems.filterIt(s(it, "kks") == kks)
    let lp1 = toSeq(0 ..< items.len)
    for lp1i in 0 ..< lp1.len:
      closureScope:
        let i = lp1[lp1i]
        let item = items[i]
        let file = s(item, "file")
        let caption = s(item, "caption")
        let pid = s(item, "id")
        let (have, data) = w.photoBytes(file)
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
          discard p.buttons(("Open photo" & (if caption.len > 0: ": " & caption else: ""), proc () = w.showPhoto(data, caption)),
                    ("Delete", proc () =
                      if ask(w.hwnd, "Delete this photo?", "It is removed for everyone once approved."):
                        discard w.submit("photo_delete", newObj(@[("photo_id", newStr(pid))]), "delete a photo")))
        else:
          discard p.dim("A photo not on this device yet (it arrives with the next sync)" & (if caption.len > 0: ": " & caption else: ""))
  p.buttons(("Add a photo from a file…", proc () = w.addPhoto(kks)))
