## Scanning an invite QR with the webcam (decision 0039): kks_camera.cpp reads grey frames through Media Foundation
## (or KKS_CAMERA_FILE in tests); each frame is shown and read with zxing-cpp (kks_qr.cpp).
import std/asyncdispatch
import w32, ui

{.compile("kks_camera.cpp", "-std=c++17").}
{.passL: "-lole32".}

type CCam = pointer
proc kks_cam_open(): CCam {.importc, cdecl.}
proc kks_cam_state(c: CCam): cint {.importc, cdecl.}
proc kks_cam_error(c: CCam): cstring {.importc, cdecl.}
proc kks_cam_frame(c: CCam, w, h: ptr cint): pointer {.importc, cdecl.}
proc kks_cam_preview(c: CCam, maxw: cint): pointer {.importc, cdecl.}
proc kks_cam_close(c: CCam) {.importc, cdecl.}
proc kks_qr_decode(gray: pointer, w, h: cint): cstring {.importc, cdecl.}
proc c_free(p: pointer) {.importc: "free", header: "<stdlib.h>".}

const
  STM_SETIMAGE = 0x0172'u32
  SS_BITMAP = 0x0E'u32

proc scanWindow*(owner: HWND, onText: proc (text: string)) =
  ## a window with the camera's picture; calls onText with the first QR code it reads, then closes
  var open = true
  let cam = kks_cam_open()
  let (hw, p) = popup(owner, "Scan the invite QR code", 560, 560, proc () =
    open = false
    kks_cam_close(cam))
  let (img, _) = control(p.hwnd, "STATIC", "Camera picture", SS_BITMAP)
  p.custom(img, 360)
  let status = p.label("Starting the camera…")
  p.buttons(("Cancel", proc () = PostMessageW(hw, WM_CLOSE, 0, 0)))
  p.layout()
  ShowWindow(hw, SW_SHOW)
  proc poll() {.async.} =
    var frames = 0
    while open:
      await sleepAsync(100)
      if not open: break
      case kks_cam_state(cam)
      of -1:
        status.setText($kks_cam_error(cam))
        break
      of 0: continue
      else: discard
      var w, h: cint
      let f = kks_cam_frame(cam, addr w, addr h)
      if f == nil: continue
      inc frames
      if frames == 1: status.setText("Hold the admin's QR code in front of the camera.")
      let hb = kks_cam_preview(cam, cint(px(480)))
      if hb != nil:
        let old = SendMessageW(img, STM_SETIMAGE, 0, cast[LPARAM](hb))
        if old != 0: DeleteObject(cast[HGDIOBJ](old))
      let t = kks_qr_decode(f, w, h)
      if t != nil:
        let text = $t
        c_free(t)
        PostMessageW(hw, WM_CLOSE, 0, 0)
        onText(text)
        break
  asyncCheck poll()
