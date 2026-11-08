## The manuals' figures (docs/plant3d/REALISM.md §6.2.1, milestone DC2): the Workshop's exploded and cut views of a
## part kind, rendered at build time. The build runs headless, where Godot has no rendering device (CI, and every build
## but a release), so this is a small software renderer of our own: the built Workshop scene's triangles
## (`built/workshop/<kind>.scn`, builder/workshop_build.gd) placed as the Workshop places them (the explode at s = 1,
## workshop/explode.gd; the kind's cutaway planes, workshop/views.gd `plane_of`), an orthographic camera, a depth
## buffer, flat shading by the plant's material colours, the cut faces (a back face seen through the cut) in one
## colour, and outlines where the depth or the component changes; drawn at twice the size and scaled down. The same
## picture on every build. Written as lossless WebP (`*.wfig`: the app decodes them itself, ui/manual_view.gd, so
## Godot's importer leaves them as they are).
##
##   godot --headless --path apps/plant3d --script res://builder/manual_figures.gd -- [--dir=res://built/manuals]
##
## Reads the figures' list from the manuals' index (`figures`: [{file, kind, view, w, h, yaw, pitch}]).
extends SceneTree

const Explode = preload("res://workshop/explode.gd")
const Views = preload("res://workshop/views.gd")
const SS := 2                                   # drawn at twice the size, then scaled down (smooth edges)
const BG := Color(1, 1, 1)
const CAP := Color(0.86, 0.42, 0.30)            # a face the cut shows (a back face seen through it)
const LINE := Color(0.13, 0.13, 0.15)
const MATS := "res://built/materials/%s.tres"

var _mat_colour := {}                           # material name -> Color


func _init() -> void:
	var dir := "res://built/manuals"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dir="):
			dir = a.substr(6)
	var f := FileAccess.open(dir.path_join("index.json"), FileAccess.READ)
	if f == null:
		printerr("manual_figures: no index in %s" % dir)
		quit(1)
		return
	var idx = JSON.parse_string(f.get_as_text())
	var n := 0
	var t0 := Time.get_ticks_msec()
	for fig in idx.get("figures", []):
		var t1 := Time.get_ticks_msec()
		var img := render(String(fig["kind"]), String(fig["view"]), int(fig["w"]), int(fig["h"]),
			float(fig.get("yaw", 35.0)), float(fig.get("pitch", 25.0)))
		if img == null:
			printerr("manual_figures: %s %s: no Workshop scene" % [fig["kind"], fig["view"]])
			quit(1)
			return
		var out := FileAccess.open(dir.path_join(String(fig["file"])), FileAccess.WRITE)
		out.store_buffer(img.save_webp_to_buffer(false))
		out.close()
		n += 1
		print("manual figure: %s (%d ms)" % [fig["file"], Time.get_ticks_msec() - t1])
	print("manuals: %d figures drawn in %d ms" % [n, Time.get_ticks_msec() - t0])
	quit(0)


## One figure: the kind's Workshop scene exploded ("exploded") or cut ("cut"), seen from `yaw` degrees round the
## vertical and `pitch` degrees above; w × h pixels. null when the kind has no Workshop scene.
func render(kind: String, view: String, w: int, h: int, yaw: float, pitch: float) -> Image:
	var path := "res://built/workshop/%s.scn" % kind
	if not ResourceLoader.exists(path):
		return null
	var root: Node3D = (load(path) as PackedScene).instantiate()
	var spec := Explode.spec_of(root)
	var off := Explode.offsets(spec, 1.0) if view == "exploded" else {}
	var foff := Explode.fastener_offsets(spec, 1.0) if view == "exploded" else {}
	var words: Dictionary = root.get_meta("workshop", {})
	var box: AABB = root.get_meta("box", AABB())
	var planes: Array = []
	var keep := {}
	if view == "cut":
		var cut: Dictionary = words.get("views", {}).get("cutaway", {})
		for q in cut.get("planes", []):
			planes.append(Views.plane_of(Views._v3(q.normal), float(q.offset), box))
		for k in cut.get("keep", []):
			keep[String(k)] = true
	# every triangle in the machine's frame: [a, b, c, normal, colour, owner index, cuttable]
	var tris: Array = []
	var owners := {}
	_collect(root, Transform3D.IDENTITY, "", "", off, foff, spec, tris, owners, keep)
	root.free()
	return _draw(tris, planes, w, h, yaw, pitch)


## `owner` the component or fastener group the meshes belong to (outlined apart); `host` the component whose `keep`
## (the cutaway's uncut parts) counts for them: a fastener group's host component, as the Workshop keeps it.
func _collect(n: Node, m: Transform3D, owner: String, host: String, off: Dictionary, foff: Dictionary,
		spec: Dictionary, tris: Array, owners: Dictionary, keep: Dictionary) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_add_mesh((c as MeshInstance3D).mesh, m, String(c.get_meta("mat", "")), owner, not keep.has(host), tris,
				owners)
		elif c is MultiMeshInstance3D:
			# a fastener group's items (the scene keeps no instance transforms: they come from the group's `items`)
			var g: Node3D = c.get_parent()
			var items: Array = g.get_meta("items", [])
			var fo: Array = foff.get(String(g.get_meta("id", "")), [])
			var mesh: Mesh = (c as MultiMeshInstance3D).multimesh.mesh if (c as MultiMeshInstance3D).multimesh != null else null
			for i in items.size():
				var t: Transform3D = items[i]
				if i < fo.size():
					t.origin += fo[i]
				_add_mesh(mesh, m * t, String(c.get_meta("mat", "")), owner + "#" + str(i), not keep.has(host), tris,
					owners)
		elif c is Node3D:
			var t: Transform3D = (c as Node3D).transform
			var id := owner
			var h := host
			if c.has_meta("explode"):
				id = String(c.get_meta("id"))
				h = id
				t.origin += off.get(id, Vector3.ZERO)
			elif c.has_meta("items"):
				id = String(c.get_meta("id"))   # (its host stays the component it hangs on)
			_collect(c, m * t, id, h, off, foff, spec, tris, owners, keep)


func _add_mesh(mesh: Mesh, m: Transform3D, mat: String, owner: String, cuttable: bool, tris: Array,
		owners: Dictionary) -> void:
	if mesh == null:
		return
	if not owners.has(owner):
		owners[owner] = owners.size() + 1
	var oi: int = owners[owner]
	var col := _colour(mat)
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var ix = a[Mesh.ARRAY_INDEX]
		var cols = a[Mesh.ARRAY_COLOR]
		var norms = a[Mesh.ARRAY_NORMAL]
		var count: int = ix.size() if ix != null and ix.size() > 0 else v.size()
		for i in range(0, count - 2, 3):
			var i0: int = ix[i] if ix != null and ix.size() > 0 else i
			var i1: int = ix[i + 1] if ix != null and ix.size() > 0 else i + 1
			var i2: int = ix[i + 2] if ix != null and ix.size() > 0 else i + 2
			var p0 := m * v[i0]
			var p1 := m * v[i1]
			var p2 := m * v[i2]
			var nn := (p1 - p0).cross(p2 - p0)
			if nn.length_squared() < 1e-18:
				continue
			var c := col
			if cols != null and cols.size() > i0:
				c = col * (cols[i0] as Color)
			# outward: the side the vertex normals point to (Godot's front faces wind clockwise, so the cross product
			# above points inward; the normals settle it where a mesh winds the other way)
			nn = -nn.normalized()
			if norms != null and norms.size() > i2:
				var vn: Vector3 = m.basis * ((norms[i0] as Vector3) + (norms[i1] as Vector3) + (norms[i2] as Vector3))
				if vn.dot(nn) < 0.0:
					nn = -nn
			tris.append([p0, p1, p2, nn, c, oi, cuttable])


## A material's colour: its tint, times its albedo texture's mean where it uses one.
func _colour(mat: String) -> Color:
	if _mat_colour.has(mat):
		return _mat_colour[mat]
	var c := Color(0.7, 0.7, 0.72)
	if mat != "" and ResourceLoader.exists(MATS % mat):
		var r = load(MATS % mat)
		if r is ShaderMaterial:
			var t = r.get_shader_parameter("tint")
			if t is Color:
				c = t
			if r.get_shader_parameter("use_albedo") == true:
				var tex = r.get_shader_parameter("albedo_tex")
				if tex is Texture2D:
					var img: Image = (tex as Texture2D).get_image()
					if img != null:
						if img.is_compressed():
							img.decompress()
						if not img.is_compressed():
							# the mean of a 32 × 32 copy (each texel of the copy itself a mean of its area)
							img.convert(Image.FORMAT_RGBA8)
							img.resize(32, 32, Image.INTERPOLATE_TRILINEAR)
							var sum := Color(0, 0, 0, 0)
							for y in 32:
								for x in 32:
									sum += img.get_pixel(x, y)
							c = c * (sum / 1024.0)
		elif r is StandardMaterial3D:
			c = (r as StandardMaterial3D).albedo_color
	c.a = 1.0
	_mat_colour[mat] = c
	return c


func _draw(tris: Array, planes: Array, w: int, h: int, yaw: float, pitch: float) -> Image:
	var W := w * SS
	var H := h * SS
	# the camera: looking along -fwd from the front right, above; right and up span the picture
	var b := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, deg_to_rad(-pitch))
	var right := b.x
	var up := b.y
	var fwd := b.z                                  # toward the viewer
	var light := (b * Vector3(-0.45, 0.75, 0.6)).normalized()
	# the picture's frame: every triangle's corners, with a margin
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for t in tris:
		for k in 3:
			var p: Vector3 = t[k]
			var q := Vector2(right.dot(p), up.dot(p))
			lo = lo.min(q)
			hi = hi.max(q)
	if tris.is_empty():
		lo = Vector2.ZERO
		hi = Vector2.ONE
	var span := hi - lo
	var scale := minf(W * 0.92 / maxf(span.x, 1e-6), H * 0.92 / maxf(span.y, 1e-6))
	var ox := W * 0.5 - (lo.x + hi.x) * 0.5 * scale
	var oy := H * 0.5 + (lo.y + hi.y) * 0.5 * scale
	var depth := PackedFloat32Array()
	depth.resize(W * H)
	depth.fill(-INF)
	var owner := PackedInt32Array()
	owner.resize(W * H)
	var rgb := PackedByteArray()
	rgb.resize(W * H * 3)
	for i in W * H:
		rgb[i * 3] = int(BG.r8)
		rgb[i * 3 + 1] = int(BG.g8)
		rgb[i * 3 + 2] = int(BG.b8)
	for t in tris:
		var p0: Vector3 = t[0]
		var p1: Vector3 = t[1]
		var p2: Vector3 = t[2]
		var n: Vector3 = t[3]
		var front := n.dot(fwd) > 0.0
		var cuttable: bool = t[6] and not planes.is_empty()
		if not front and not cuttable:
			continue                            # a back face: hidden behind its own front unless the cut opens it
		var col: Color
		if front:
			col = (t[4] as Color) * (0.42 + 0.58 * maxf(0.0, n.dot(light)))
			col.a = 1.0
		else:
			col = CAP
		var cr := int(clampf(col.r, 0.0, 1.0) * 255.0)
		var cg := int(clampf(col.g, 0.0, 1.0) * 255.0)
		var cb := int(clampf(col.b, 0.0, 1.0) * 255.0)
		var x0 := right.dot(p0) * scale + ox
		var y0 := oy - up.dot(p0) * scale
		var x1 := right.dot(p1) * scale + ox
		var y1 := oy - up.dot(p1) * scale
		var x2 := right.dot(p2) * scale + ox
		var y2 := oy - up.dot(p2) * scale
		var z0 := fwd.dot(p0)
		var z1 := fwd.dot(p1)
		var z2 := fwd.dot(p2)
		var area := (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
		if absf(area) < 1e-9:
			continue
		var minx := maxi(0, int(floorf(minf(x0, minf(x1, x2)))))
		var maxx := mini(W - 1, int(ceilf(maxf(x0, maxf(x1, x2)))))
		var miny := maxi(0, int(floorf(minf(y0, minf(y1, y2)))))
		var maxy := mini(H - 1, int(ceilf(maxf(y0, maxf(y1, y2)))))
		if minx > maxx or miny > maxy:
			continue
		var inv := 1.0 / area
		var oi: int = t[5]
		for py in range(miny, maxy + 1):
			var sy := py + 0.5
			var row := py * W
			for px in range(minx, maxx + 1):
				var sx := px + 0.5
				var w0 := ((x1 - sx) * (y2 - sy) - (x2 - sx) * (y1 - sy)) * inv
				var w1 := ((x2 - sx) * (y0 - sy) - (x0 - sx) * (y2 - sy)) * inv
				var w2 := 1.0 - w0 - w1
				if w0 < 0.0 or w1 < 0.0 or w2 < 0.0:
					continue
				var z := w0 * z0 + w1 * z1 + w2 * z2
				var k := row + px
				if z <= depth[k]:
					continue
				if cuttable:
					var wp := p0 * w0 + p1 * w1 + p2 * w2
					var away := true
					for pl in planes:
						if (pl[0] as Vector3).dot(wp) <= float(pl[1]):
							away = false
							break
					if away:
						continue
				depth[k] = z
				owner[k] = oi
				rgb[k * 3] = cr
				rgb[k * 3 + 1] = cg
				rgb[k * 3 + 2] = cb
	# outlines: where the owner changes, or the depth jumps (a part's own edge seen against itself)
	var jump := 0.02 * maxf(span.x, span.y)
	var lr := int(LINE.r8)
	var lg := int(LINE.g8)
	var lb := int(LINE.b8)
	var edge := PackedByteArray()
	edge.resize(W * H)
	for y in range(0, H - 1):
		var row := y * W
		for x in range(0, W - 1):
			var k := row + x
			var o := owner[k]
			var o1 := owner[k + 1]
			var o2 := owner[k + W]
			if o != o1 or o != o2:
				edge[k] = 1
			elif o != 0 and (absf(depth[k] - depth[k + 1]) > jump or absf(depth[k] - depth[k + W]) > jump):
				edge[k] = 1
	for k in W * H:
		if edge[k] == 1:
			rgb[k * 3] = lr
			rgb[k * 3 + 1] = lg
			rgb[k * 3 + 2] = lb
	var img := Image.create_from_data(W, H, false, Image.FORMAT_RGB8, rgb)
	img.resize(w, h, Image.INTERPOLATE_CUBIC)
	return img
