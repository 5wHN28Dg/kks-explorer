## A touchpad pinch starts with "begin" and a NULL event sequence. The viewer's handler for it once read that NULL as
## its own data and crashed (2026-10-07, the Flatpak on a trackpad). It opens a window, so it is not in `nim test`:
##   cd apps/gnome && nim c -d:release -o:/tmp/kksgnome/viewer_pinch e2e/viewer_pinch.nim
##   e2e/headless.sh /tmp/kksgnome/viewer_pinch
import kksg/[gtk, viewer]
proc gtk_widget_observe_controllers(w: W): pointer {.importc, header: "<gtk/gtk.h>".}
proc g_list_model_get_n_items(m: pointer): cuint {.importc, header: "<gio/gio.h>".}
proc g_list_model_get_item(m: pointer, i: cuint): W {.importc, header: "<gio/gio.h>".}
proc GTK_IS_GESTURE_ZOOM(p: W): bool {.importc, header: "<gtk/gtk.h>".}
proc g_signal_emit_by_name(inst: W, sig: cstring) {.importc, header: "<glib-object.h>", varargs.}

let app = adw_application_new("org.kks.PinchTest", 32)
var ok = false
app.on("activate", proc () =
  let v = newViewer()
  let w = adw_application_window_new(app)
  adw_application_window_set_content(w, v.widget)
  let ctl = gtk_widget_observe_controllers(v.widget)
  var zoom: W = nil
  for i in 0'u32 ..< g_list_model_get_n_items(ctl):
    let c = g_list_model_get_item(ctl, cuint(i))
    if GTK_IS_GESTURE_ZOOM(c): zoom = c
  doAssert zoom != nil, "the viewer has a zoom gesture"
  g_signal_emit_by_name(zoom, "begin", nil)     # what a touchpad pinch sends
  ok = true
  quit(0))
discard g_application_run(app, 0, nil)
doAssert ok
