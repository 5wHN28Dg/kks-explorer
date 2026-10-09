## Photos (R9): thumbnails, a zoomable view, delete, and adding one: pick a picture, annotate it (arrow, box, circle,
## four colours, undo; burned into the image), scale to at most 1600 px, compress as JPEG XL at distance 1.9
## (the user's choice 2026-09-27), propose it.

import std/[math, strutils, base64, os, sequtils, times, typedthreads, posix]
import kks/[json, node, model, api]
import kksi/jxl
import gtk, ui, appstate, win, photoqueue

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

proc annotate*(w: Win, px: seq[byte], iw, ih: int, done: proc (rgb: seq[byte], w, h: int, caption, note: string),
               plate = false) =
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
  adw_dialog_set_title(d, if plate: "Add a tag plate photo" else: "Add a photo")
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
  let header = headerBar(adw_window_title_new(if plate: "Add a tag plate photo" else: "Add a photo",
                                              if plate: "The metal plate with the KKS code" else: "Draw to point things out"))
  adw_header_bar_pack_end(header, send)
  adw_dialog_set_child(d, toolbarView(header, body))
  present(d, w.window)

# ---------------------------------------------------------------- the photo queue (the user: "background compression
# and a photo queue"). JPEG XL at effort 9 takes seconds: it runs on a worker thread, one photo after another in the
# order they were added, and keeps going when the panel or the editor closes. Each photo is proposed as soon as it is
# compressed, so they arrive in order. Before 2026-10-08 it ran on the main thread, freezing the window meanwhile.
# Since 2026-10-09 each photo is kept on disk first (apps/common/photoqueue.nim: sealed rows in the device's store)
# and removed only once the core accepted or refused it: a crash, an OOM kill or a logout no longer loses it, the next
# start sends it (with the same client_id, so a photo sent just before the crash is kept once).

type
  EncJob = object
    key: string
    rgb: seq[byte]
    w, h: int
  EncDone = object
    key: string
    data: string
    err: string

var
  encJobs: Channel[EncJob]
  encDone: Channel[EncDone]
  encThread: Thread[void]
  encStarted = false
  pq: PhotoQueue                 ## main thread only (the store's thread); nil until the main screen first shows
  polling = false

proc encWorker() {.thread.} =
  while true:
    let j = encJobs.recv()
    var d = EncDone(key: j.key)
    try: d.data = encodeLossy(j.rgb, j.w, j.h, 3, 1.9, 9)
    except CatchableError, Defect:      # always answer: a dead worker would leave the queue waiting for ever
      d.err = getCurrentExceptionMsg()
    encDone.send(d)

iterator queued(): QueuedPhoto =
  if pq != nil:
    for q in pq.items: yield q

proc queueText(): string =
  if pq == nil or pq.count == 0: return ""
  let items = pq.items
  "Compressing " & (if items.len == 1: "1 photo" else: $items.len & " photos") & " (" & items[0].kks &
    (if items.len > 1: ", then " & items[1 .. ^1].mapIt(it.kks).join(", ") else: "") &
    "). They are sent in order; you can keep working."

proc showQueue(w: Win) =
  if w.queueLabel == nil: return
  let t = queueText()
  gtk_label_set_text(w.queueLabel, t.cstring)
  gtk_widget_set_visible(w.queueBar, cint(t.len > 0))

proc queuedCount*(): int =   ## photos still being compressed or waiting (kept on disk: the next start sends them)
  if pq == nil: 0 else: pq.count

proc queuedFor*(kks: string): int =
  for q in queued():
    if q.kks == kks: inc result

proc sendPhoto(w: Win, q: QueuedPhoto, jxlData: string) =
  ## raises ApiError when the core refuses it
  var payload = newObj(@[("kks", newStr(q.kks)), ("caption", newStr(q.caption)),
                         ("dataUrl", newStr("data:image/jxl;base64," & encode(jxlData)))])
  if q.floor.len > 0: payload["floor"] = newStr(q.floor)   # written first, only if the code still has no floor
  # one transaction: the core writes the entry, its note and the submission row (the one with the client_id) as
  # separate rows; a kill between them would leave the photo without its client_id, and the resend would add it again
  w.a.store.transaction(proc () =
    discard w.trySubmit("photo", payload, "photo of " & q.kks, q.note, q.clientId))

proc received(w: Win, d: EncDone) =
  ## one photo compressed (or not): send it, then remove it, keep it for a retry, or report a refusal
  if pq.wiped: return
  var it: QueuedPhoto
  var found = false
  for q in pq.items:
    if q.key == d.key:
      it = q
      found = true
  if not found: return
  var outcome = Sent
  var why = ""
  if d.err.len > 0:
    outcome = Failed
    why = "it could not be compressed: " & d.err
  else:
    try:
      w.sendPhoto(it, d.data)
      # tests: the app dies after the core took the photo, before the queue forgot it (the resend must not add it twice)
      if getEnv("KKS_TEST_PHOTO_DIE_AFTER_SEND").len > 0: discard posix.kill(getpid(), SIGKILL)
    except ApiError as e:
      if e.status >= 400: (outcome, why) = (Refused, e.msg)
      else: (outcome, why) = (Failed, e.msg)
    except CatchableError as e:
      (outcome, why) = (Failed, e.msg)
  try:
    let r = pq.finish(d.key, outcome, why, nowMs())
    if r.len > 0: w.toast(r)
  except CatchableError as e:          # the store: the photo stays queued (a resend is kept once, by its client_id)
    w.toast("Photo of " & it.kks & ": the queue could not be updated (" & e.msg & ")")

proc startNext(w: Win) =
  ## start compressing the next photo (the first one not waiting for a retry), if none is being worked on
  if pq == nil or pq.wiped: return
  if not encStarted:
    encJobs.open()
    encDone.open()
    createThread(encThread, encWorker)
    encStarted = true
  # tests: KKS_TEST_PHOTO_HOLD keeps the photos queued without compressing them (the app is killed with photos queued)
  if getEnv("KKS_TEST_PHOTO_HOLD").len == 0:
    var reports: seq[string]
    let (ok, it, px) = pq.next(nowMs(), reports)
    for r in reports: w.toast(r)
    if ok: encJobs.send(EncJob(key: it.key, rgb: px, w: it.w, h: it.h))
  w.showQueue()

proc pump(w: Win) =
  ## start the next photo, and keep one timer going while photos are queued (results, retries that come due)
  w.startNext()
  if polling or pq == nil or pq.count == 0 or pq.wiped: return
  polling = true
  timeout(200, proc (): bool =
    var done = false
    while true:
      let (got, d) = encDone.tryRecv()
      if not got: break
      w.received(d)
      done = true
    if done and w.selected.len > 0: w.rebuildPanel()   # its "being compressed" line
    w.startNext()
    polling = pq.count > 0 and not pq.wiped
    polling)

proc resumePhotos*(w: Win) =
  ## once, when the main screen first shows: the photos left from before (a crash, a kill, a logout) go first, in
  ## their order
  if pq != nil: return
  pq = newPhotoQueue(w.a.store)
  var reports: seq[string]
  try: reports = pq.resume()
  except CatchableError as e: reports.add "The queued photos could not be read: " & e.msg
  for r in reports: w.toast(r)
  w.pump()

proc photosWiped*(w: Win) =
  ## a removed device: the store's wipe deleted the queued photos; nothing more is compressed or sent
  if pq == nil: pq = newPhotoQueue(w.a.store)
  pq.wipe()

proc enqueue(w: Win, rgb: seq[byte], ow, oh: int, kks, caption, note, floor: string) =
  w.resumePhotos()
  try: discard pq.add(w.a.p, rgb, ow, oh, kks, caption, note, floor, nowMs())
  except CatchableError as e:
    w.toast("The photo of " & kks & " could not be kept for sending (" & e.msg & "). It was not added.")
    return
  w.pump()
  if w.selected.len > 0: idle(proc () = w.rebuildPanel())   # not inside the click (an AT-SPI action)

proc floorKnown(w: Win, kks: string): bool =
  ## the code has a floor, I proposed one that is still open, or a queued photo carries one
  let e = w.m.equipment(kks)
  if s(e, "floor").strip.len > 0: return true
  # the loaded model lags a change by a moment (a photo just sent with its floor): ask the core itself
  try:
    let eq = w.a.call("GET", "/api/state")["equipment"].get(kks)
    if s(eq, "floor").strip.len > 0: return true
  except ApiError: discard
  for q in queued():
    if q.kks == kks and q.floor.len > 0: return true
  for sub in w.myOpen():
    let p = sub.get("payload")
    if sub["kind"].s == "equipment" and p != nil and s(p, "kks") == kks and p.get("changes") != nil and
       s(p["changes"], "floor").strip.len > 0: return true

proc floorsMissing*(w: Win, codes: openArray[string]): seq[string] =
  ## the codes with no floor yet (as floorKnown, but the core's state is read once for all of them)
  var st: JNode = nil
  for k in codes:
    if s(w.m.equipment(k), "floor").strip.len > 0: continue
    if st == nil:
      try: st = w.a.call("GET", "/api/state")["equipment"]
      except ApiError: st = newObj()
    if s(st.get(k), "floor").strip.len > 0: continue
    var known = false
    for q in queued():
      if q.kks == k and q.floor.len > 0: known = true
    if not known:
      for sub in w.myOpen():
        let p = sub.get("payload")
        if sub["kind"].s == "equipment" and p != nil and s(p, "kks") == k and p.get("changes") != nil and
           s(p["changes"], "floor").strip.len > 0: known = true
    if not known: result.add k

proc askFloor(w: Win, kks: string, fn: proc (floor: string)) =
  ## the user's rule: a photo needs its floor. Asked before the picture, sent with it.
  let d = adw_alert_dialog_new(("Which floor is " & kks & " on?").cstring,
    "A photo needs its floor, and this equipment has none yet. Enter the floor: a whole number from 0 (ground) to 10. It is sent with the photo.".cstring)
  let e = gtk_entry_new()
  gtk_entry_set_placeholder_text(e, "Floor, 0 to 10")
  setAccessibleLabel(e, "Floor of " & kks)
  adw_alert_dialog_set_extra_child(d, e)
  adw_alert_dialog_add_response(d, "cancel", "Cancel")
  adw_alert_dialog_add_response(d, "yes", "Continue")
  adw_alert_dialog_set_response_appearance(d, "yes", ADW_RESPONSE_SUGGESTED)
  adw_alert_dialog_set_default_response(d, "yes")
  adw_alert_dialog_set_close_response(d, "cancel")
  d.onResponse(proc (id: string) =
    if id != "yes": return
    let f = text(e).strip
    if not (f == "10" or (f.len == 1 and f[0] in Digits)):
      w.toast("Floor: a whole number from 0 to 10 (the height goes in Elevation). The photo was not added.")
      return
    fn(f))
  present(d, w.window)

proc hasPlate(w: Win, kks: string): bool =
  ## the code has a tag plate photo, or one is on its way
  for q in queued():
    if q.kks == kks and isPlate(q.caption): return true
  let ph = if w.m.state != nil: w.m.state.get("photos") else: nil
  if ph != nil:
    for p in ph.elems:
      if s(p, "kks") == kks and isPlate(s(p, "caption")): return true

proc plateCaption(extra: string): string =
  ## a tag plate photo's caption starts with "Tag plate" (PROTOCOL-v2 §9, as on Android)
  if extra.strip.len == 0: PlateCaption else: PlateCaption & " · " & extra.strip

proc addPhoto*(w: Win, kks: string, plate = false) =
  ## an equipment photo, or (plate) a photo of its tag plate. After an equipment photo of a code with no tag plate
  ## photo, the app offers one (as Android does).
  # tests: KKS_PHOTO_FILE names the picture instead of the file chooser (as KKS_CAMERA_FILE for the camera)
  let pick = proc (title: string, fn: proc (path: string)) =
    if getEnv("KKS_PHOTO_FILE").len > 0: fn(getEnv("KKS_PHOTO_FILE")) else: openFile(w.window, title, fn)
  proc go(floor: string) =
    pick(if plate: "Choose a photo of the tag plate" else: "Choose a photo", proc (path: string) =
      if path.len == 0: return
      let (iw, ih, px) = loadImage(path)
      if iw == 0:
        w.toast("That file could not be read as a picture.")
        return
      w.annotate(px, iw, ih, proc (rgb: seq[byte], ow, oh: int, caption, note: string) =
        let offer = not plate and not w.hasPlate(kks)
        w.enqueue(rgb, ow, oh, kks, if plate: plateCaption(caption) else: caption, note, floor)
        if offer:
          let d = adw_alert_dialog_new("And its tag plate?",
            "A photo of the metal plate with the KKS code helps the next person find this equipment.")
          adw_alert_dialog_add_response(d, "no", "Not now")
          adw_alert_dialog_add_response(d, "yes", "Add it")
          adw_alert_dialog_set_response_appearance(d, "yes", ADW_RESPONSE_SUGGESTED)
          adw_alert_dialog_set_default_response(d, "yes")
          adw_alert_dialog_set_close_response(d, "no")
          d.onResponse(proc (id: string) =
            if id == "yes": w.addPhoto(kks, plate = true))
          present(d, w.window), plate = plate))
  if w.floorKnown(kks): go("")
  else: w.askFloor(kks, go)

proc takePhoto*(w: Win, send: proc (dataUrl, caption, note: string)) =
  ## a picture from a file, marked up in the editor, compressed to JPEG XL: `send` gets its data URL (a photo of
  ## several codes at once, multi.nim; one code's photos go through the queue above)
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
        send("data:image/jxl;base64," & encode(jxlData), caption, note))))


proc photoSection*(w: Win, kks: string): W =
  result = group("Photos")
  let g = result
  let box = adw_wrap_box_new()
  adw_wrap_box_set_child_spacing(box, 8)
  adw_wrap_box_set_line_spacing(box, 8)
  var n = 0
  let ph = if w.m.state != nil: w.m.state.get("photos") else: nil
  if ph != nil:
    # the tag plate first: it is how the equipment is recognised in the field
    let items3 = ph.elems.filterIt(s(it, "kks") == kks and isPlate(s(it, "caption"))) &
                 ph.elems.filterIt(s(it, "kks") == kks and not isPlate(s(it, "caption")))
    for i3 in 0 ..< items3.len:
      closureScope:   # each pass gets its own copies of the captured variables
        let p = items3[i3]
        inc n
        let file = s(p, "file")
        let caption = s(p, "caption")
        let pid = s(p, "id")
        let (have, data) = w.photoBytes(file)
        let cell = vbox(2)
        if isPlate(caption): cell.add label("Tag plate", "caption-heading")
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
  let q = queuedFor(kks)
  if q > 0:
    adw_preferences_group_add(g, label((if q == 1: "1 photo" else: $q & " photos") & " of this equipment being compressed; " &
                                       "sent when ready.", "dim-label"))
  let btns = hbox(8)
  btns.add button("+ Add photo", "", proc () = w.addPhoto(kks))
  btns.add button(if w.hasPlate(kks): "+ New tag plate photo" else: "+ Tag plate photo", "", proc () = w.addPhoto(kks, plate = true))
  adw_preferences_group_add(g, btns)
