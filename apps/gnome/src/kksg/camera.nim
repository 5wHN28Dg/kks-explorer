## Scanning an invite QR with the webcam (decision 0039): kks_camera.c gets grey frames (camera portal → PipeWire →
## GStreamer, or v4l2src, or KKS_CAMERA_FILE in tests); each frame is shown and read with zxing-cpp.
import gtk, ui, qr

{.compile: "kks_camera.c".}
{.passC: staticExec("pkg-config --cflags gstreamer-1.0 gstreamer-app-1.0 gio-unix-2.0").}
{.passL: "-l:libgstreamer-1.0.so.0 -l:libgstapp-1.0.so.0".}

type CCam = pointer
proc kks_cam_open(): CCam {.importc, cdecl.}
proc kks_cam_state(c: CCam): cint {.importc, cdecl.}
proc kks_cam_error(c: CCam): cstring {.importc, cdecl.}
proc kks_cam_frame(c: CCam, w, h: ptr cint): ptr UncheckedArray[byte] {.importc, cdecl.}
proc kks_cam_close(c: CCam) {.importc, cdecl.}
var GDK_MEMORY_G8 {.importc, header: "<adwaita.h>", nodecl.}: cint

proc scanDialog*(parent: W, onText: proc (text: string)) =
  ## a dialog with the camera's picture; calls onText with the first QR code it reads, then closes
  let d = adw_dialog_new()
  adw_dialog_set_title(d, "Scan the invite QR code")
  adw_dialog_set_content_width(d, 560)
  let body = vbox(10)
  margins(body, 16)
  let pic = gtk_picture_new()
  gtk_widget_set_size_request(pic, 480, 360)
  setAccessibleLabel(pic, "Camera picture")
  body.add pic
  let status = label("Starting the camera…", "dim-label")
  body.add status
  body.add button("Cancel", "", proc () = discard adw_dialog_close(d))
  adw_dialog_set_child(d, body)
  let cam = kks_cam_open()
  var open = true
  var frames = 0
  d.on("closed", proc () =
    open = false
    kks_cam_close(cam))
  timeout(100, proc (): bool =
    if not open: return false
    case kks_cam_state(cam)
    of -1:
      gtk_label_set_text(status, kks_cam_error(cam))
      return false
    of 0:
      gtk_label_set_text(status, "Waiting for permission to use the camera…")
      return true
    else: discard
    var w, h: cint
    let f = kks_cam_frame(cam, addr w, addr h)
    if f == nil: return true
    inc frames
    if frames == 1: gtk_label_set_text(status, "Hold the admin's QR code in front of the camera.")
    let b = g_bytes_new(f, csize_t(int(w) * int(h)))
    let tex = gdk_memory_texture_new(w, h, GDK_MEMORY_G8, b, csize_t(w))
    g_bytes_unref(b)
    gtk_picture_set_paintable(pic, tex)
    g_object_unref(tex)
    let text = qrFromGray(f, int(w), int(h))
    if text.len > 0:
      open = false
      discard adw_dialog_close(d)
      onText(text)
      return false
    true)
  present(d, parent)
