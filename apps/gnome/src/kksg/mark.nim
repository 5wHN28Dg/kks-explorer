## Marking a tag the reader missed (R6): drag a box on the drawing, type the code if it can be read, propose it.
## Marks survive re-imports (they live in the log, not in tags.json).

import std/[math, strutils]
import kks/json
import kks/model
import gtk, ui, appstate, viewer, win, kkprender

proc markDialog*(w: Win, x0, y0, x1, y1: float) =
  let (ok, si) = w.m.sheetById(w.sheet)
  let sc = if ok and si.scale > 0: si.scale else: 2.0
  if (x1 - x0) * sc < 8 or (y1 - y0) * sc < 8:
    w.toast("Box too small: drag across the whole tag")
    return
  let d = adw_dialog_new()
  adw_dialog_set_title(d, "Mark a missing tag")
  adw_dialog_set_content_width(d, 480)
  let body = vbox(10)
  margins(body, 12)
  if w.v.sheet != nil:          # a crop of the drawing under the box
    let pad = 6.0
    let zoom = min(440.0 / (x1 - x0 + 2 * pad), 140.0 / (y1 - y0 + 2 * pad))
    let tw = int(ceil((x1 - x0 + 2 * pad) * zoom))
    let th = int(ceil((y1 - y0 + 2 * pad) * zoom))
    let surf = w.v.sheet.renderTile(zoom, x0 - pad, y0 - pad, tw, th)
    let pic = gtk_picture_new_for_paintable(textureOf(surf))
    cairo_surface_destroy(surf)
    gtk_widget_set_size_request(pic, cint(tw), cint(th))
    setAccessibleLabel(pic, "The marked part of the drawing")
    body.add pic
  body.add label("Type the code if you can read it. If not, leave it empty: the mark goes to the review queue.", "dim-label")
  let g = group("")
  let code = entryRow("KKS (with suffix, optional)", "")
  let isa = entryRow("Function letters (instruments, optional)", "")
  let note = entryRow("Note (optional)", "")
  for r in [code, isa, note]: adw_preferences_group_add(g, r)
  body.add g
  let sheet = w.sheet
  let send = button("Propose", "suggested-action", proc () =
    let bb = newArr(@[newFloat(round(x0 * sc * 10) / 10), newFloat(round(y0 * sc * 10) / 10),
                      newFloat(round(x1 * sc * 10) / 10), newFloat(round(y1 * sc * 10) / 10)])
    let k = text(code).strip.toUpperAscii
    let r = w.submit("tag_add", newObj(@[("sheet", newStr(sheet)), ("bbox", bb), ("kks", newStr(k)),
                     ("isa", newStr(text(isa).strip.toUpperAscii)), ("note", newStr(text(note).strip))]),
                     if k.len > 0: k else: "an unread tag")
    if r.len > 0:
      adw_dialog_close(d)
      w.v.marking = false
      w.setBanner("", "", nil)
      w.loadModel()
      w.v.tags = w.tagBoxes(sheet)
      gtk_widget_queue_draw(w.v.widget))
  let header = headerBar(adw_window_title_new("Mark a missing tag", si.name.cstring))
  adw_header_bar_pack_end(header, send)
  adw_dialog_set_child(d, toolbarView(header, body))
  present(d, w.window)

proc startMarking*(w: Win) =
  w.v.marking = true
  w.closePanel()
  w.setBanner("Drag a box around the tag the app missed", "Cancel", proc () =
    w.v.marking = false
    w.v.mark = (0.0, 0.0, 0.0, 0.0)
    w.setBanner("", "", nil)
    gtk_widget_queue_draw(w.v.widget))
  gtk_widget_set_cursor_from_name(w.v.widget, "crosshair")
