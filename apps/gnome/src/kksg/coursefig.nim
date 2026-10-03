## A course figure on GNOME (decision 0036): the core's evaluator (`courses.Figure`), drawn with Cairo and Pango through
## apps/common/figdraw.nim on a GtkDrawingArea exposed as an image; the frame clock drives it while it is on screen
## (§9.6); native controls below (play/pause, a GtkScale, check buttons, a radio group).

import std/[math, os]
import kks/[json, courses]
import gtk, ui, figdraw

const Faces = {"body": "Atkinson Hyperlegible, Cantarell, sans-serif",
               "display": "Barlow Semi Condensed, sans-serif", "mono": "JetBrains Mono, monospace"}

var fontsLoaded = false
proc loadCourseFonts*() =
  ## the course faces (vendored WOFF2, decision 0011) as application fonts for Pango (fontconfig reads WOFF2)
  if fontsLoaded: return
  fontsLoaded = true
  for base in [getAppDir() / "vendor" / "fonts", getAppDir() / ".." / "share" / "walkdown" / "vendor" / "fonts",
               currentSourcePath().parentDir.parentDir.parentDir.parentDir.parentDir / "vendor" / "fonts"]:
    if dirExists(base):
      for f in walkFiles(base / "*.woff2"): discard addAppFont(f)
      return

proc face(role: string): string =
  for (k, v) in Faces:
    if k == role: return v
  Faces[0][1]

proc cairoBackend(c: Cairo): Backend =
  var b: Backend
  b.save = proc () = cairo_save(c)
  b.restore = proc () = cairo_restore(c)
  b.translate = proc (x, y: float) = cairo_translate(c, x, y)
  b.rotate = proc (a: float) = cairo_rotate(c, a)
  b.scale = proc (x, y: float) = cairo_scale(c, x, y)
  var alphas: seq[float]
  b.pushOpacity = proc (a: float) =
    alphas.add a
    cairo_push_group(c)
  b.popOpacity = proc () =
    cairo_pop_group_to_source(c)
    cairo_paint_with_alpha(c, alphas.pop())
  proc rr(x, y, w, h, rx0: float) =
    let rx = max(0.0, min(rx0, min(w / 2, h / 2)))
    if rx == 0:
      cairo_rectangle(c, x, y, w, h)
      return
    cairo_new_sub_path(c)
    cairo_arc(c, x + w - rx, y + rx, rx, -PI / 2, 0)
    cairo_arc(c, x + w - rx, y + h - rx, rx, 0, PI / 2)
    cairo_arc(c, x + rx, y + h - rx, rx, PI / 2, PI)
    cairo_arc(c, x + rx, y + rx, rx, PI, 3 * PI / 2)
    cairo_close_path(c)
  b.clipRoundRect = proc (x, y, w, h, rx: float) =
    cairo_new_path(c)
    rr(x, y, w, h, rx)
    cairo_clip(c)
  b.begin = proc () = cairo_new_path(c)
  b.moveTo = proc (x, y: float) = cairo_move_to(c, x, y)
  b.lineTo = proc (x, y: float) = cairo_line_to(c, x, y)
  b.curveTo = proc (x1, y1, x2, y2, x, y: float) = cairo_curve_to(c, x1, y1, x2, y2, x, y)
  b.close = proc () = cairo_close_path(c)
  b.roundRect = proc (x, y, w, h, rx: float) = rr(x, y, w, h, rx)
  b.ellipse = proc (cx, cy, rx, ry: float) =
    if rx <= 0 or ry <= 0: return
    cairo_save(c)
    cairo_translate(c, cx, cy)
    cairo_scale(c, rx, ry)
    cairo_new_sub_path(c)
    cairo_arc(c, 0, 0, 1, 0, 2 * PI)
    cairo_restore(c)
  b.fill = proc (p: Paint) =
    if p.radial:
      let pat = cairo_pattern_create_radial(p.cx, p.cy, 0, p.cx, p.cy, p.rad)
      for (off, col) in p.stops: cairo_pattern_add_color_stop_rgba(pat, off, col.r, col.g, col.b, col.a)
      cairo_set_source(c, pat)
      cairo_fill_preserve(c)
      cairo_pattern_destroy(pat)
    else:
      cairo_set_source_rgba(c, p.c.r, p.c.g, p.c.b, p.c.a)
      cairo_fill_preserve(c)
  b.stroke = proc (col: Rgba, width: float, cap, join: string, dash: seq[float]) =
    cairo_set_source_rgba(c, col.r, col.g, col.b, col.a)
    cairo_set_line_width(c, width)
    cairo_set_line_cap(c, case cap
      of "round": CAIRO_LINE_CAP_ROUND
      of "square": CAIRO_LINE_CAP_SQUARE
      else: CAIRO_LINE_CAP_BUTT)
    cairo_set_line_join(c, case join
      of "round": CAIRO_LINE_JOIN_ROUND
      of "bevel": CAIRO_LINE_JOIN_BEVEL
      else: CAIRO_LINE_JOIN_MITER)
    cairo_set_miter_limit(c, 4)
    if dash.len > 0:
      var d = dash
      cairo_set_dash(c, addr d[0], cint(d.len), 0)
    else: cairo_set_dash(c, nil, 0, 0)
    cairo_stroke_preserve(c)
  b.text = proc (s: string, x, y: float, anchor, font: string, size: float, weight: int, col: Rgba) =
    let l = pango_cairo_create_layout(c)
    let fd = pango_font_description_from_string((face(font) & (if weight >= 700: " Bold" elif weight >= 600: " Semi-Bold" else: "")).cstring)
    pango_font_description_set_absolute_size(fd, size * float(PANGO_SCALE))
    pango_layout_set_font_description(l, fd)
    pango_font_description_free(fd)
    pango_layout_set_text(l, s.cstring, -1)
    var w, h: cint
    pango_layout_get_size(l, addr w, addr h)
    let tw = float(w) / float(PANGO_SCALE)
    let x0 = case anchor
      of "middle": x - tw / 2
      of "end": x - tw
      else: x
    cairo_set_source_rgba(c, col.r, col.g, col.b, col.a)
    cairo_move_to(c, x0, y - float(pango_layout_get_baseline(l)) / float(PANGO_SCALE))
    pango_cairo_show_layout(c, l)
    g_object_unref(l)
    cairo_new_path(c)
  b

type FigView* = ref object
  ev*: Figure
  f*: JNode
  area*, box*, status*, playBtn*, slider*, sliderOut*: W
  scroller*: W              ## the scrolled window it sits in (off screen = frozen)
  lastUs: int64
  updating: bool

proc dark(): bool = adw_style_manager_get_dark(adw_style_manager_get_default()) != 0

proc sync(v: FigView) =
  if v.playBtn != nil: gtk_button_set_label(v.playBtn, if v.ev.playing: "Pause" else: "Play")
  if v.slider != nil:
    v.updating = true
    gtk_range_set_value(v.slider, v.ev.v)
    v.updating = false
    let t = v.ev.sliderText()
    if t.kind == jStr:
      gtk_label_set_text(v.sliderOut, t.s.cstring)
      setAccessibleDescription(v.slider, t.s)
  let s = v.ev.status()
  if s.kind == jStr and v.status != nil: gtk_label_set_text(v.status, s.s.cstring)

proc onScreen(v: FigView): bool =
  if v.scroller == nil: return true
  let y = yIn(v.area, v.scroller)
  if y.isNaN: return false
  y + float(gtk_widget_get_height(v.area)) > 0 and y < float(gtk_widget_get_height(v.scroller))

proc figureWidget*(f: JNode, scroller: W): FigView =
  ## the figure with its title, controls, status and caption is built by the caller around `box`
  let v = FigView(f: f, ev: newFigure(f, reduceMotion = not animationsEnabled()), scroller: scroller)
  let fw = f["w"].num
  let fh = f["h"].num
  v.area = imageArea()
  setAccessibleLabel(v.area, f["title"].s)
  setAccessibleDescription(v.area, f["alt"].s)
  gtk_drawing_area_set_content_width(v.area, cint(min(fw, 520.0)))
  gtk_drawing_area_set_content_height(v.area, cint(fh * min(fw, 520.0) / fw))
  gtk_widget_set_hexpand(v.area, 1)
  v.area.onDraw(proc (c: Cairo, w, h: int) =
    # §9.8: scaled to the width, never above 1:1; the height follows the width
    let s = min(1.0, float(w) / fw)
    let want = cint(round(fh * s))
    if want != cint(h):
      idle(proc () = gtk_drawing_area_set_content_height(v.area, want))
    cairo_save(c)
    cairo_translate(c, (float(w) - fw * s) / 2, 0)
    cairo_scale(c, s, s)
    cairoBackend(c).draw(v.ev.scene(), dark())
    cairo_restore(c))
  v.box = vbox(6)
  v.box.add v.area
  if v.ev.isStatic: return v
  v.status = label("", "monospace")
  setAccessibleLabel(v.status, "Status")
  let ctrl = hbox(10)
  v.playBtn = button("Pause", "", proc () =
    if v.ev.playing: v.ev.pause() else: v.ev.play()
    v.sync()
    gtk_widget_queue_draw(v.area))
  ctrl.add v.playBtn
  if f.get("slider") != nil:
    v.slider = gtk_scale_new_with_range(GTK_ORIENTATION_HORIZONTAL, 0, 1, 0.001)
    gtk_scale_set_draw_value(v.slider, 0)
    gtk_widget_set_hexpand(v.slider, 1)
    setAccessibleLabel(v.slider, f["slider"]["label"].s)
    v.sliderOut = label("", "monospace")
    v.slider.on("value-changed", proc () =
      if v.updating: return
      v.ev.setSlider(gtk_range_get_value(v.slider))
      v.ev.tick(0)
      v.sync()
      gtk_widget_queue_draw(v.area))
    ctrl.add label(f["slider"]["label"].s, "dim-label", wrap = false), v.slider, v.sliderOut
  if f.get("toggles") != nil:
    let tgs = f["toggles"].elems
    for ti in 0 ..< tgs.len:
      closureScope:
        let key = tgs[ti]["key"].s
        let cb = gtk_check_button_new_with_label(tgs[ti]["label"].s.cstring)
        gtk_check_button_set_active(cb, cint(tgs[ti]["on"].b))
        cb.on("toggled", proc () =
          v.ev.toggle(key)
          v.sync()
          gtk_widget_queue_draw(v.area))
        ctrl.add cb
  if f.get("modes") != nil:
    let ms = f["modes"].elems
    var first: W = nil
    for mi in 0 ..< ms.len:
      closureScope:
        let idx = mi
        let r = gtk_check_button_new_with_label(ms[mi]["label"].s.cstring)
        if first == nil:
          first = r
          gtk_check_button_set_active(r, 1)
        else: gtk_check_button_set_group(r, first)
        r.on("toggled", proc () =
          if gtk_check_button_get_active(r) != 0:
            v.ev.setMode(idx)
            v.sync()
            gtk_widget_queue_draw(v.area))
        ctrl.add r
  v.box.add v.status, ctrl
  v.sync()
  v.area.onTick(proc (us: int64): bool =
    let el = if v.lastUs == 0: 0.0 else: float(us - v.lastUs) / 1e6
    v.lastUs = us
    if v.ev.playing and v.onScreen:
      v.ev.tick(el)
      v.sync()
      gtk_widget_queue_draw(v.area)
    elif not v.onScreen: v.lastUs = 0
    true)
  v
