## Photos (R9): thumbnails, a zoomable view, delete, and adding one: pick a picture, annotate it (arrow, box, circle,
## four colours, undo; burned into the image), scale to at most 1600 px, compress as JPEG XL at distance 1.9
## (the user's choice 2026-09-27), propose it.

import std/[math, strutils, base64, os, sequtils, times]
import kks/[json, node]
import kksi/jxl
import gtk, ui, appstate, win

const MaxSide = 1600

proc s(n: JNode, k: string): string =
  if n != nil and n.get(k) != nil and n[k].isStr: n[k].s else: ""

proc photoBytes(w: Win, file: string): (bool, string) =
  ## the photo's blob (photos/<sha256>.<ext>); false while this device doesn't hold it yet (on-demand photos)
  let sha = file.split('.')[0]
  if w.a.n.store.blobHas(sha): (true, w.a.n.store.blobGet(sha)) else: (false, "")

proc textureOfPhoto*(data: string): W =
  try:
    let (iw, ih, _, px) = decodeRgba(data)
    textureFromRgb(px, iw, ih, alpha = true)
  except JxlError: nil

proc showPhoto*(w: Win, data, caption: string) =
  ## a dialog with the photo, fit to the window; + / − zoom, drag to pan when zoomed
  let tex = textureOfPhoto(data)
  if tex == nil:
    w.toast("This photo could not be shown")
    return
  let d = adw_dialog_new()
  adw_dialog_set_title(d, (if caption.len > 0: caption else: "Photo").cstring)
  adw_dialog_set_content_width(d, 1000)
  adw_dialog_set_content_height(d, 760)
  let pic = gtk_picture_new_for_paintable(tex)
  gtk_picture_set_content_fit(pic, GTK_CONTENT_FIT_CONTAIN)
  let sw = gtk_scrolled_window_new()
  gtk_scrolled_window_set_policy(sw, GTK_POLICY_AUTOMATIC, GTK_POLICY_AUTOMATIC)
  gtk_scrolled_window_set_child(sw, pic)
  gtk_widget_set_vexpand(sw, 1)
  var zoom = 1.0
  let iw = float(gdk_texture_get_width(tex))
  let ih = float(gdk_texture_get_height(tex))
  proc apply() =
    if zoom <= 1.0: gtk_widget_set_size_request(pic, -1, -1)
    else: gtk_widget_set_size_request(pic, cint(iw * zoom * 0.6), cint(ih * zoom * 0.6))
  let header = headerBar(adw_window_title_new((if caption.len > 0: caption else: "Photo").cstring, ""))
  adw_header_bar_pack_start(header, iconButton("zoom-out-symbolic", "Zoom out", proc () =
    zoom = max(1.0, zoom / 1.5)
    apply()))
  adw_header_bar_pack_start(header, iconButton("zoom-in-symbolic", "Zoom in", proc () =
    zoom = min(8.0, zoom * 1.5)
    apply()))
  let scroll = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
  scroll.onScroll(proc (dx, dy: float) =
    if (gtk_event_controller_get_current_event_state(scroll) and GDK_CONTROL_MASK) != 0:
      zoom = max(1.0, min(8.0, zoom * pow(1.0015, -dy * 80)))
      apply())
  gtk_widget_add_controller(sw, scroll)
  adw_dialog_set_child(d, toolbarView(header, sw))
  present(d, w.window)

# ---------------------------------------------------------------- annotation

type
  Shape = object
    kind: string           ## arrow · box · circle
    x0, y0, x1, y1: float  ## image px
    color: (float, float, float)
    size: float            ## × the base line width (thin 0.6, medium 1, thick 1.8)

const Colors = [("Red", (0.9, 0.1, 0.1)), ("Yellow", (1.0, 0.85, 0.0)), ("Blue", (0.1, 0.45, 1.0)), ("White", (1.0, 1.0, 1.0))]

proc drawShape(c: Cairo, s: Shape, lw: float) =
  cairo_set_source_rgb(c, s.color[0], s.color[1], s.color[2])
  cairo_set_line_width(c, lw)
  cairo_new_path(c)
  case s.kind
  of "box":
    cairo_rectangle(c, min(s.x0, s.x1), min(s.y0, s.y1), abs(s.x1 - s.x0), abs(s.y1 - s.y0))
  of "circle":
    let cx = (s.x0 + s.x1) / 2
    let cy = (s.y0 + s.y1) / 2
    let rx = max(1.0, abs(s.x1 - s.x0) / 2)
    let ry = max(1.0, abs(s.y1 - s.y0) / 2)
    cairo_save(c)
    cairo_translate(c, cx, cy)
    cairo_scale(c, rx, ry)
    cairo_arc(c, 0, 0, 1, 0, 2 * PI)
    cairo_restore(c)
  else:   # arrow: a line with a head at the end point
    cairo_move_to(c, s.x0, s.y0)
    cairo_line_to(c, s.x1, s.y1)
    let a = arctan2(s.y1 - s.y0, s.x1 - s.x0)
    let head = lw * 4.5
    cairo_move_to(c, s.x1, s.y1)
    cairo_line_to(c, s.x1 - head * cos(a - 0.45), s.y1 - head * sin(a - 0.45))
    cairo_move_to(c, s.x1, s.y1)
    cairo_line_to(c, s.x1 - head * cos(a + 0.45), s.y1 - head * sin(a + 0.45))
  cairo_stroke(c)

proc rgbaSurface(px: seq[byte], w, h: int): Surface =
  result = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, cint(w), cint(h))
  let d = cairo_image_surface_get_data(result)
  let stride = int(cairo_image_surface_get_stride(result))
  for y in 0 ..< h:
    for x in 0 ..< w:
      let o = (y * w + x) * 4
      let a = int(px[o + 3])
      let p = y * stride + x * 4
      d[p] = byte(int(px[o + 2]) * a div 255)
      d[p + 1] = byte(int(px[o + 1]) * a div 255)
      d[p + 2] = byte(int(px[o]) * a div 255)
      d[p + 3] = byte(a)
  cairo_surface_mark_dirty(result)

proc annotate*(w: Win, px: seq[byte], iw, ih: int, done: proc (rgb: seq[byte], w, h: int, caption, note: string)) =
  ## the editor: the picture scaled to MaxSide, shapes drawn on top, then flattened to RGB. Zoom: −/+/Fit, the wheel,
  ## two fingers (pinch, pan); pan also with the right button. While a finger draws, a loupe shows the area under it
  ## magnified, above the finger (touchscreens only: the drag's device says so).
  let sc = min(1.0, float(MaxSide) / float(max(iw, ih)))
  let ow = max(1, int(round(float(iw) * sc)))
  let oh = max(1, int(round(float(ih) * sc)))
  let src = rgbaSurface(px, iw, ih)
  let base = cairo_image_surface_create(CAIRO_FORMAT_RGB24, cint(ow), cint(oh))
  block:
    let c = cairo_create(base)
    cairo_set_source_rgb(c, 1, 1, 1)
    cairo_paint(c)
    cairo_scale(c, float(ow) / float(iw), float(oh) / float(ih))
    cairo_set_source_surface(c, src, 0, 0)
    cairo_paint(c)
    cairo_destroy(c)
  cairo_surface_destroy(src)
  var shapes: seq[Shape]
  var tool = "arrow"
  var color = Colors[0][1]
  var size = 1.0
  var cur: Shape
  var drawing = false
  let lw = max(4.0, float(max(ow, oh)) / 220)
  let area = gtk_drawing_area_new()
  gtk_widget_set_hexpand(area, 1)
  gtk_widget_set_vexpand(area, 1)
  var aw, ah = 1.0                       # the area's size
  var zoom = 1.0
  var cx = float(ow) / 2                 # the image point at the area's centre
  var cy = float(oh) / 2
  var fit = 1.0
  var touching = false                   # a finger draws: the loupe at (fx, fy)
  var fx, fy = 0.0
  var pinching = false
  proc sc0(): float = fit * zoom
  proc clampView() =
    let s = sc0()
    let hw = aw / 2 / s
    let hh = ah / 2 / s
    cx = (if hw * 2 >= float(ow): float(ow) / 2 else: clamp(cx, hw, float(ow) - hw))
    cy = (if hh * 2 >= float(oh): float(oh) / 2 else: clamp(cy, hh, float(oh) - hh))
  proc toImg(x, y: float): (float, float) = (cx + (x - aw / 2) / sc0(), cy + (y - ah / 2) / sc0())
  proc zoomAt(x, y, z: float) =
    let (ix, iy) = toImg(x, y)
    zoom = clamp(z, 1.0, 8.0)
    cx = ix - (x - aw / 2) / sc0()
    cy = iy - (y - ah / 2) / sc0()
    clampView()
    gtk_widget_queue_draw(area)
  proc scene(c: Cairo) =
    cairo_set_source_surface(c, base, 0, 0)
    cairo_paint(c)
    for s in shapes: drawShape(c, s, lw * s.size)
    if drawing: drawShape(c, cur, lw * cur.size)
  area.onDraw(proc (c: Cairo, w0, h0: int) =
    aw = float(w0)
    ah = float(h0)
    fit = min(aw / float(ow), ah / float(oh))
    clampView()
    let s = sc0()
    cairo_save(c)
    cairo_translate(c, aw / 2 - cx * s, ah / 2 - cy * s)
    cairo_scale(c, s, s)
    scene(c)
    cairo_restore(c)
    if touching and drawing:            # the loupe: 2.5× the view around the finger, a circle above it
      let r = 70.0
      let k = 2.5
      let lx = clamp(fx, r, aw - r)
      let ly = if fy - 40 - 2 * r >= 0: fy - 40 - r else: fy + 40 + r
      let (ix, iy) = toImg(fx, fy)
      cairo_save(c)
      cairo_new_path(c)
      cairo_arc(c, lx, ly, r, 0, 2 * PI)
      cairo_clip(c)
      cairo_set_source_rgb(c, 0, 0, 0)
      cairo_paint(c)
      cairo_translate(c, lx - ix * s * k, ly - iy * s * k)
      cairo_scale(c, s * k, s * k)
      scene(c)
      cairo_restore(c)
      cairo_set_source_rgb(c, 1.0, 0.48, 0.1)
      cairo_set_line_width(c, 1.5)
      cairo_move_to(c, lx - 10, ly)
      cairo_line_to(c, lx + 10, ly)
      cairo_move_to(c, lx, ly - 10)
      cairo_line_to(c, lx, ly + 10)
      cairo_stroke(c)
      cairo_set_line_width(c, 3)
      cairo_arc(c, lx, ly, r, 0, 2 * PI)
      cairo_stroke(c))
  # one finger or the left button draws
  let drag = gtk_gesture_drag_new()
  gtk_gesture_single_set_button(drag, 1)
  var sx, sy = 0.0                       # where the drag began (area px)
  drag.onXY("drag-begin", proc (x, y: float) =
    if pinching: return
    sx = x
    sy = y
    let dev = gtk_event_controller_get_current_event_device(drag)
    touching = dev != nil and gdk_device_get_source(dev) == GDK_SOURCE_TOUCHSCREEN
    fx = x
    fy = y
    let (ix, iy) = toImg(x, y)
    cur = Shape(kind: tool, x0: ix, y0: iy, x1: ix, y1: iy, color: color, size: size)
    drawing = true
    gtk_widget_queue_draw(area))
  drag.onXY("drag-update", proc (dx, dy: float) =
    if not drawing: return
    fx = sx + dx
    fy = sy + dy
    (cur.x1, cur.y1) = toImg(fx, fy)
    gtk_widget_queue_draw(area))
  drag.onXY("drag-end", proc (dx, dy: float) =
    if drawing:
      (cur.x1, cur.y1) = toImg(sx + dx, sy + dy)
      drawing = false
      if (abs(cur.x1 - cur.x0) + abs(cur.y1 - cur.y0)) * sc0() > 6: shapes.add cur
    touching = false
    pinching = false
    gtk_widget_queue_draw(area))
  gtk_widget_add_controller(area, drag)
  # two fingers: pinch to zoom, move to pan (the mark being drawn is dropped)
  let pinch = gtk_gesture_zoom_new()
  var z0 = 1.0
  var mx, my = 0.0
  pinch.onPtr("begin", proc (p: W) =
    pinching = true
    drawing = false
    touching = false
    z0 = zoom
    var x, y: cdouble
    discard gtk_gesture_get_bounding_box_center(pinch, addr x, addr y)
    mx = float(x)
    my = float(y))
  pinch.onScale(proc (scale: float) =
    var x, y: cdouble
    discard gtk_gesture_get_bounding_box_center(pinch, addr x, addr y)
    zoomAt(float(x), float(y), z0 * scale)
    cx -= (float(x) - mx) / sc0()
    cy -= (float(y) - my) / sc0()
    mx = float(x)
    my = float(y)
    clampView()
    gtk_widget_queue_draw(area))
  gtk_widget_add_controller(area, pinch)
  # the right button pans; the wheel zooms where the pointer is
  let pan = gtk_gesture_drag_new()
  gtk_gesture_single_set_button(pan, 3)
  var pcx, pcy = 0.0
  pan.onXY("drag-begin", proc (x, y: float) =
    pcx = cx
    pcy = cy)
  pan.onXY("drag-update", proc (dx, dy: float) =
    cx = pcx - dx / sc0()
    cy = pcy - dy / sc0()
    clampView()
    gtk_widget_queue_draw(area))
  gtk_widget_add_controller(area, pan)
  var px0, py0 = 0.0
  let motion = gtk_event_controller_motion_new()
  motion.onXY("motion", proc (x, y: float) =
    px0 = x
    py0 = y)
  gtk_widget_add_controller(area, motion)
  let wheel = gtk_event_controller_scroll_new(GTK_EVENT_CONTROLLER_SCROLL_BOTH_AXES)
  wheel.onScroll(proc (dx, dy: float) = zoomAt(px0, py0, zoom * exp(-dy * 0.15)))
  gtk_widget_add_controller(area, wheel)
  let d = adw_dialog_new()
  adw_dialog_set_title(d, "Add a photo")
  adw_dialog_set_content_width(d, 1000)
  adw_dialog_set_content_height(d, 780)
  let tools = hbox(4)
  var toolBtns: seq[W]
  let items1 = toSeq(["arrow", "box", "circle"])
  for i1 in 0 ..< items1.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let t = items1[i1]
      let b = gtk_toggle_button_new_with_label(t.capitalizeAscii.cstring)
      if t == tool: gtk_toggle_button_set_active(b, 1)
      let tt = t
      b.onClick(proc () =
        tool = tt
        for x in toolBtns: gtk_toggle_button_set_active(x, cint(x == b)))
      toolBtns.add b
      tools.add b
  tools.add gtk_separator_new(GTK_ORIENTATION_VERTICAL)
  let items2 = toSeq(Colors)
  for i2 in 0 ..< items2.len:
    closureScope:   # each pass gets its own copies of the captured variables
      let (name, rgb) = items2[i2]
      let col = rgb
      tools.add button(name, "flat", proc () = color = col)
  tools.add gtk_separator_new(GTK_ORIENTATION_VERTICAL)
  var sizeBtns: seq[W]
  let items3 = toSeq([("Thin", 0.6, "Thin lines"), ("Medium", 1.0, "Medium lines"), ("Thick", 1.8, "Thick lines")])
  for i3 in 0 ..< items3.len:
    closureScope:
      let (lab, f, desc) = items3[i3]
      let b = gtk_toggle_button_new_with_label(lab.cstring)
      setAccessibleLabel(b, desc)
      gtk_widget_set_tooltip_text(b, desc.cstring)
      if f == size: gtk_toggle_button_set_active(b, 1)
      let ff = f
      b.onClick(proc () =
        size = ff
        for x in sizeBtns: gtk_toggle_button_set_active(x, cint(x == b)))
      sizeBtns.add b
      tools.add b
  tools.add gtk_separator_new(GTK_ORIENTATION_VERTICAL)
  tools.add iconButton("zoom-out-symbolic", "Zoom out", proc () = zoomAt(aw / 2, ah / 2, zoom / 1.5))
  tools.add iconButton("zoom-in-symbolic", "Zoom in", proc () = zoomAt(aw / 2, ah / 2, zoom * 1.5))
  tools.add iconButton("zoom-fit-best-symbolic", "Fit the photo", proc () =
    zoom = 1.0
    clampView()
    gtk_widget_queue_draw(area))
  tools.add button("Undo", "flat", proc () =
    if shapes.len > 0:
      shapes.setLen(shapes.len - 1)
      gtk_widget_queue_draw(area))
  let caption = gtk_entry_new()
  gtk_entry_set_placeholder_text(caption, "Caption (optional)")
  setAccessibleLabel(caption, "Caption")
  gtk_widget_set_hexpand(caption, 1)
  let note = gtk_entry_new()
  gtk_entry_set_placeholder_text(note, "Note for the approver (optional)")
  setAccessibleLabel(note, "Note for the approver")
  gtk_widget_set_hexpand(note, 1)
  let body = vbox(8)
  margins(body, 12)
  body.add tools, area, caption
  if not w.isAdmin: body.add note
  let send = button("Add the photo", "suggested-action", proc () =
    # flatten: picture + shapes at full output size, then RGB rows
    let outS = cairo_image_surface_create(CAIRO_FORMAT_RGB24, cint(ow), cint(oh))
    let c = cairo_create(outS)
    cairo_set_source_surface(c, base, 0, 0)
    cairo_paint(c)
    for s in shapes: drawShape(c, s, lw * s.size)
    cairo_destroy(c)
    cairo_surface_flush(outS)
    let data = cairo_image_surface_get_data(outS)
    let stride = int(cairo_image_surface_get_stride(outS))
    var rgb = newSeq[byte](ow * oh * 3)
    for y in 0 ..< oh:
      for x in 0 ..< ow:
        let p = y * stride + x * 4
        rgb[(y * ow + x) * 3] = data[p + 2]
        rgb[(y * ow + x) * 3 + 1] = data[p + 1]
        rgb[(y * ow + x) * 3 + 2] = data[p]
    cairo_surface_destroy(outS)
    adw_dialog_close(d)
    done(rgb, ow, oh, text(caption).strip, text(note).strip))
  let header = headerBar(adw_window_title_new("Add a photo", "Draw to point things out"))
  adw_header_bar_pack_end(header, send)
  adw_dialog_set_child(d, toolbarView(header, body))
  present(d, w.window)

proc addPhoto*(w: Win, kks: string) =
  # tests: KKS_PHOTO_FILE names the picture instead of the file chooser (as KKS_CAMERA_FILE for the camera)
  let pick = proc (title: string, fn: proc (path: string)) =
    if getEnv("KKS_PHOTO_FILE").len > 0: fn(getEnv("KKS_PHOTO_FILE")) else: openFile(w.window, title, fn)
  pick("Choose a photo", proc (path: string) =
    if path.len == 0: return
    let (iw, ih, px) = loadImage(path)
    if iw == 0:
      w.toast("That file could not be read as a picture.")
      return
    w.annotate(px, iw, ih, proc (rgb: seq[byte], ow, oh: int, caption, note: string) =
      w.toast("Compressing…")
      idle(proc () =
        var jxlData: string
        try: jxlData = encodeLossy(rgb, ow, oh, 3, 1.9, 9)
        except JxlError as e:
          w.toast(e.msg)
          return
        discard w.submit("photo", newObj(@[("kks", newStr(kks)), ("caption", newStr(caption)),
                         ("dataUrl", newStr("data:image/jxl;base64," & encode(jxlData)))]), "photo of " & kks, note))))

proc photoSection*(w: Win, kks: string): W =
  result = group("Photos")
  let g = result
  let box = adw_wrap_box_new()
  adw_wrap_box_set_child_spacing(box, 8)
  adw_wrap_box_set_line_spacing(box, 8)
  var n = 0
  let ph = if w.m.state != nil: w.m.state.get("photos") else: nil
  if ph != nil:
    let items3 = toSeq(ph.elems.filterIt(s(it, "kks") == kks))
    for i3 in 0 ..< items3.len:
      closureScope:   # each pass gets its own copies of the captured variables
        let p = items3[i3]
        inc n
        let file = s(p, "file")
        let caption = s(p, "caption")
        let pid = s(p, "id")
        let (have, data) = w.photoBytes(file)
        let cell = vbox(2)
        if have:
          let tex = textureOfPhoto(data)
          let pic = gtk_picture_new_for_paintable(tex)
          gtk_picture_set_content_fit(pic, GTK_CONTENT_FIT_CONTAIN)
          gtk_widget_set_size_request(pic, 120, 90)
          let b = gtk_button_new()
          gtk_widget_add_css_class(b, "flat")
          gtk_button_set_child(b, pic)
          setAccessibleLabel(b, "Open photo" & (if caption.len > 0: ": " & caption else: ""))
          b.onClick(proc () = w.showPhoto(data, caption))
          cell.add b
        else:
          cell.add label("Not on this device yet (it arrives with the next sync)", "dim-label caption")
        let by = s(p, "by_name")
        let tsv = if p.get("submitted") != nil and p["submitted"].kind == jInt: p["submitted"] else: p.get("created")
        let dd = if tsv != nil and tsv.kind == jInt and tsv.i > 0: fromUnix(tsv.i).local.format("yyyy-MM-dd") else: ""
        if by.len > 0 or dd.len > 0:
          cell.add label((if by.len > 0: "by " & by else: "") & (if by.len > 0 and dd.len > 0: ", " else: "") & dd, "dim-label caption")
        let del = button("Delete", "flat caption", proc () =
          confirm(w.window, "Delete this photo?", "It is removed for everyone once approved.", "Delete", true, proc () =
            discard w.submit("photo_delete", newObj(@[("photo_id", newStr(pid))]), "delete a photo")))
        cell.add del
        adw_wrap_box_append(box, cell)
  if n > 0: adw_preferences_group_add(g, box)
  adw_preferences_group_add(g, button("+ Add photo", "", proc () = w.addPhoto(kks)))
