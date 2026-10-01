import std/unittest
import kks/[json, util, pathstore]
import vectors

proc opOf(s: string): uint8 =
  case s
  of "M": OpMove
  of "L": OpLine
  of "C": OpCubic
  else: OpClose

proc fromModel(m: JNode): Drawing =
  result.width = uint32(m["width"].i)
  result.height = uint32(m["height"].i)
  for s in m["styles"].elems:
    var st = Style(kind: uint8(s["kind"].i), cap: uint8(s["cap"].i), join: uint8(s["join"].i),
                   width: uint32(s["width"].i))
    for k in 0 .. 2:
      st.stroke[k] = uint8(s["stroke"][k].i)
      st.fill[k] = uint8(s["fill"][k].i)
    result.styles.add st
  for p in m["paths"].elems:
    var path = Path(style: int(p["style"].i), cmdStart: result.ops.len, cmdCount: p["cmds"].len,
                    ptStart: result.xy.len div 2)
    for k in 0 .. 3: path.bbox[k] = p["bbox"][k].i
    for c in p["cmds"].elems:
      result.ops.add opOf(c[0].s)
      for k in 1 ..< c.len: result.xy.add c[k].i
    result.paths.add path
  for im in m["images"].elems:
    var x = Image(after: int(im["after"].i), data: unhex(im["data_hex"].s).toStr)
    for k in 0 .. 3: x.rect[k] = im["rect"][k].i
    result.images.add x

proc sameDrawing(a, b: Drawing): bool =
  a.width == b.width and a.height == b.height and a.styles == b.styles and a.paths == b.paths and
    a.ops == b.ops and a.xy == b.xy and a.images == b.images

suite "path store (pathstore-v1.json)":
  let V = loadVectors("pathstore-v1.json")

  test "decode both forms":
    for c in V["valid"].elems:
      let want = fromModel(c["model"])
      for key in ["file_hex", "file_deflated_hex"]:
        let d = decode(unhex(c[key].s).toStr)
        check sameDrawing(d, want)
        check d.gx == int(c["model"]["grid"][0].i) and d.gy == int(c["model"]["grid"][1].i)
        var cells: seq[seq[int32]]
        for cell in c["cells"].elems:
          var s: seq[int32]
          for x in cell.elems: s.add int32(x.i)
          cells.add s
        check d.cells == cells

  test "encode is canonical":
    for c in V["valid"].elems:
      let d = fromModel(c["model"])
      let g = c["model"]["grid"]
      check hex(encode(d, int(g[0].i), int(g[1].i), compress = false)) == c["file_hex"].s
      check sameDrawing(decode(encode(d, int(g[0].i), int(g[1].i))), d)

  test "rejects":
    for r in V["reject"].elems:
      var refused = false
      try: discard decode(unhex(r["file_hex"].s).toStr)
      except FormatError: refused = true
      check refused
      if not refused: echo "  accepted: ", r["why"].s

  test "grid rules":
    for g in V["choose_grid"].elems:
      check chooseGrid(g["width"].i, g["height"].i) == (int(g["grid"][0].i), int(g["grid"][1].i))
    for c in V["cell_range"].elems:
      let r = cellRange(c["v0"].i, c["v1"].i, c["size"].i, int(c["n"].i))
      var want: seq[int]
      for x in c["cells"].elems: want.add int(x.i)
      var got: seq[int]
      for i in r: got.add i
      check got == want

  test "zlib bomb is refused":
    let bomb = "KKP1\x01\x00\x01\x00" & deflateAll(newString(MaxBytes + 10), 9)
    expect FormatError: discard decode(bomb)
    expect FormatError: discard decode("KKP1\x01\x00\x01\x00\x78\x9c\x00")    # truncated stream
