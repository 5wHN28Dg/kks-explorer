import std/[os, times]
import kksg/[gtk, kkprender]
proc cairo_surface_write_to_png(s: Surface, f: cstring): cint {.importc, header: "<cairo.h>".}
let s = newSheet(readFile(paramStr(1)))
echo "sheet ", s.widthPt, " x ", s.heightPt, " pt, ", s.d.paths.len, " paths"
var t = epochTime()
let whole = s.renderTile(1000.0 / s.widthPt, 0, 0, 1000, int(1000 * s.heightPt / s.widthPt))
echo "whole at ", 1000.0 / s.widthPt, " px/pt: ", int((epochTime() - t) * 1000), " ms"
discard cairo_surface_write_to_png(whole, "/tmp/kkp_whole.png")
t = epochTime()
let tile = s.renderTile(8.0, s.widthPt * 0.45, s.heightPt * 0.45, 512, 512)
echo "512 tile at 8 px/pt: ", int((epochTime() - t) * 1000), " ms"
discard cairo_surface_write_to_png(tile, "/tmp/kkp_tile.png")
