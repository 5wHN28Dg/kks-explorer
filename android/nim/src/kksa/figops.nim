## Course figures for the Android app (decision 0036): the core's evaluator and apps/common/figdraw.nim's drawing
## rules, recorded as a compact list of drawing operations that Kotlin replays on an android.graphics.Canvas each
## frame (no JSON per frame). Little-endian; every number a float32 unless noted.
##   0 save · 1 restore · 2 translate x y · 3 rotate rad · 4 scale x y · 5 pushOpacity a · 6 popOpacity
##   7 clipRoundRect x y w h rx · 8 begin · 9 moveTo x y · 10 lineTo x y · 11 curveTo x1 y1 x2 y2 x y · 12 close
##   13 roundRect x y w h rx · 14 ellipse cx cy rx ry · 15 fill r g b a
##   16 fillRadial cx cy rad n:u8 then n × (offset r g b a)
##   17 stroke r g b a width cap:u8 join:u8 n:u8 then n dashes
##   18 text x y size anchor:u8 font:u8 weight:u16 r g b a len:u16 utf8

import std/tables
import kks/[json, courses]
import figdraw

type Rec = ref object
  buf: string

proc u8(r: Rec, v: int) = r.buf.add char(v and 0xff)
proc u16(r: Rec, v: int) =
  r.buf.add char(v and 0xff)
  r.buf.add char((v shr 8) and 0xff)
proc f32(r: Rec, v: float) =
  var x = float32(v)
  var b: array[4, char]
  copyMem(addr b[0], addr x, 4)
  for c in b: r.buf.add c
proc op(r: Rec, code: int, args: varargs[float]) =
  r.u8(code)
  for a in args: r.f32(a)

proc recorder*(r: Rec): Backend =
  var b: Backend
  b.save = proc () = r.op(0)
  b.restore = proc () = r.op(1)
  b.translate = proc (x, y: float) = r.op(2, x, y)
  b.rotate = proc (a: float) = r.op(3, a)
  b.scale = proc (x, y: float) = r.op(4, x, y)
  b.pushOpacity = proc (a: float) = r.op(5, a)
  b.popOpacity = proc () = r.op(6)
  b.clipRoundRect = proc (x, y, w, h, rx: float) = r.op(7, x, y, w, h, rx)
  b.begin = proc () = r.op(8)
  b.moveTo = proc (x, y: float) = r.op(9, x, y)
  b.lineTo = proc (x, y: float) = r.op(10, x, y)
  b.curveTo = proc (x1, y1, x2, y2, x, y: float) = r.op(11, x1, y1, x2, y2, x, y)
  b.close = proc () = r.op(12)
  b.roundRect = proc (x, y, w, h, rx: float) = r.op(13, x, y, w, h, rx)
  b.ellipse = proc (cx, cy, rx, ry: float) = r.op(14, cx, cy, rx, ry)
  b.fill = proc (p: Paint) =
    if p.radial:
      r.op(16, p.cx, p.cy, p.rad)
      r.u8(p.stops.len)
      for (o, c) in p.stops:
        for v in [o, c.r, c.g, c.b, c.a]: r.f32(v)
    else: r.op(15, p.c.r, p.c.g, p.c.b, p.c.a)
  b.stroke = proc (c: Rgba, w: float, cap, join: string, dash: seq[float]) =
    r.op(17, c.r, c.g, c.b, c.a, w)
    r.u8(case cap
      of "round": 1
      of "square": 2
      else: 0)
    r.u8(case join
      of "round": 1
      of "bevel": 2
      else: 0)
    r.u8(dash.len)
    for d in dash: r.f32(d)
  b.text = proc (s: string, x, y: float, anchor, font: string, size: float, weight: int, c: Rgba) =
    r.op(18, x, y, size)
    r.u8(case anchor
      of "middle": 1
      of "end": 2
      else: 0)
    r.u8(case font
      of "display": 1
      of "mono": 2
      else: 0)
    r.u16(weight)
    for v in [c.r, c.g, c.b, c.a]: r.f32(v)
    let t = if s.len > 65535: s[0 ..< 65535] else: s
    r.u16(t.len)
    r.buf.add t
  b

var
  figs: Table[int, Figure]
  nextFig = 1

proc figNew*(f: JNode, reduceMotion: bool): int =
  result = nextFig
  inc nextFig
  figs[result] = newFigure(f, reduceMotion)

proc figFree*(id: int) = figs.del id

proc figFrame*(id: int, cmd: JNode): string =
  ## apply cmd {tick?: s, slider?: v, toggle?: key, mode?: i, play?: bool, dark: bool}, then the frame:
  ## u32 length of a JSON state {playing, v, mode, status, slider}, the JSON, the ops
  let fg = figs.getOrDefault(id)
  if fg == nil: return ""
  if cmd.get("slider") != nil: fg.setSlider(cmd["slider"].num)
  if cmd.get("toggle") != nil: fg.toggle(cmd["toggle"].s)
  if cmd.get("mode") != nil: fg.setMode(int(cmd["mode"].num))
  if cmd.get("play") != nil:
    if cmd["play"].b: fg.play() else: fg.pause()
  if cmd.get("tick") != nil: fg.tick(cmd["tick"].num)
  let r = Rec()
  recorder(r).draw(fg.scene(), cmd.get("dark") != nil and cmd["dark"].b)
  var toggles = newObj()
  for k, v in fg.toggles: toggles[k] = newBool(v >= 0.5)
  let st = toText(newObj(@[("playing", newBool(fg.playing)), ("v", newFloat(fg.v)), ("mode", newInt(fg.mode)),
                           ("toggles", toggles), ("status", fg.status()), ("slider", fg.sliderText())]))
  let n = st.len
  result = newString(4)
  result[0] = char(n and 0xff)
  result[1] = char((n shr 8) and 0xff)
  result[2] = char((n shr 16) and 0xff)
  result[3] = char((n shr 24) and 0xff)
  result.add st
  result.add r.buf
