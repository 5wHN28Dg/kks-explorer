## The site and the camp (docs/plant3d/SITE.md, docs/PLANT3D.md §18.6): planting by species, vehicles, the gates'
## barriers and booths, shade canopies, street lamps, kerbs, the sports court, porches, interior partitions and the
## furniture of the camp's rooms. Structures without codes: nothing here moves or is operated. Every surface is the
## plant's one lit shader (decision 0060): the colours are in the vertices of a few materials (`foliage` for planting,
## `matte` for fabric and plaster; the paint set for vehicles and furniture's steel; plain for glass and screens), so a
## cell's pieces of every colour are one draw call per material. Planting is left out of the lightmap's bake
## (builder/kit_place.gd UNBAKED): its leaves' area was most of the site's texels, and the bake ran out of memory.
##
## Planting (SITE.md §4: every plant has a purpose): date palms (shade on the walkways), tamarisk (the windbreak against
## the north-westerly shamal), oleander (dust hedges along roads), bougainvillea (on porches and walkway posts),
## saltbush and caper (low beds on bare ground by doors). Each is a few hundred triangles of opaque geometry (no
## cut-out leaves: an alpha-tested surface is pipelines of its own, 0057), the crown's shape in its triangles and its
## leaves' and flowers' colours in the vertices; Godot's generated LODs thin them with distance. The drip line along a
## row is a `detail` piece. `variant` (set by the builder, not content) varies a plant's shape: a row is not one plant
## copied.
extends RefCounted

## The species' usual height and spacing in a row (m): what a planting with height 0 or spacing 0 takes. Palms 8 m
## apart shade a walkway in a nearly continuous band at midday; a windbreak's tamarisks stand 2.5 m apart so their
## crowns close; a hedge's oleanders 1.2 m.
const SPECIES := {
	"date_palm": {"height": 7.0, "spacing": 8.0, "solid": [0.3, 2.0]},
	"tamarisk": {"height": 6.0, "spacing": 2.5, "solid": [0.45, 2.0]},
	"oleander": {"height": 2.2, "spacing": 1.2, "solid": [0.55, 1.8]},
	"bougainvillea": {"height": 2.8, "spacing": 3.0, "solid": [0.25, 1.5]},
	"saltbush": {"height": 1.0, "spacing": 1.2, "solid": [0.45, 0.8]},
	"caper": {"height": 0.5, "spacing": 1.4, "solid": [0.45, 0.45]},
	"dracaena": {"height": 1.6, "spacing": 1.0, "solid": [0.25, 0.5]},
}

## Leaf, bark and soil colours (sRGB, in the vertices): the grey-greens of plants of hot dry places, never a lawn's.
const FROND := Color(0.42, 0.50, 0.33)
const FROND_OLD := Color(0.56, 0.52, 0.34)
const BARK_PALM := Color(0.46, 0.38, 0.29)
const BARK := Color(0.38, 0.33, 0.28)
const TAMARISK := Color(0.46, 0.53, 0.43)
const OLEANDER := Color(0.20, 0.33, 0.17)
const OLEANDER_FLOWER := Color(0.88, 0.52, 0.62)
const BOUGAINVILLEA := Color(0.76, 0.17, 0.47)
const BOUGAINVILLEA_LEAF := Color(0.25, 0.40, 0.18)
const SALTBUSH := Color(0.63, 0.67, 0.60)
const CAPER := Color(0.36, 0.50, 0.28)
const CAPER_FLOWER := Color(0.93, 0.88, 0.90)
const SOIL := Color(0.50, 0.41, 0.31)
const SOIL_WET := Color(0.36, 0.29, 0.22)
## The drip hose, black polyethylene greyed by the dust: pure black, thinner than a pixel a few metres off, drew a hard
## dark line that broke into dashes as one walked (the Note 9, 2026-10-23: taken for a fault in the ground).
const HOSE := Color(0.20, 0.19, 0.17)
## A potted dracaena's leaves (Dracaena fragrans, the lobby's plant: glossy dark green straps) and its glazed pot.
const DRACAENA := Color(0.17, 0.32, 0.14)
const POT := Color(0.30, 0.29, 0.28)

## Vehicle paint (no white: the user's choice, 2026-10-21; muted, neutral fleet colours).
const VEHICLE := {"silver": Color(0.68, 0.69, 0.70), "grey": Color(0.42, 0.44, 0.45), "sand": Color(0.72, 0.64, 0.50),
	"blue": Color(0.22, 0.29, 0.42), "green": Color(0.29, 0.35, 0.28)}
const CARPET := {"green": Color(0.20, 0.36, 0.26), "red": Color(0.50, 0.14, 0.14), "blue": Color(0.17, 0.25, 0.42),
	"sand": Color(0.66, 0.58, 0.44)}
## Interior colours: plaster walls, the furniture's laminate and fabric, steel frames (light, sand and grey tones).
const PLASTER := Color(0.88, 0.86, 0.81)
const LAMINATE := Color(0.62, 0.52, 0.40)
const FABRIC := Color(0.36, 0.40, 0.44)
const LINEN := Color(0.86, 0.85, 0.80)
const BLANKET := Color(0.34, 0.37, 0.46)
const STEEL_GREY := Color(0.52, 0.54, 0.55)
const CERAMIC := Color(0.93, 0.93, 0.91)

## Selects material `name` for the next pieces and paints them `c` (in the vertices).
static func col(m, name: String, c: Color, cls := "form", size := 0.0) -> void:
	m.use(name, cls, size)
	m.colour = c

static func _rng(g, salt: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([int(g.p.get("variant", 0)), salt, String(g.p.get("species", ""))])
	return r

# ------------------------------------------------------------------ planting

static func species(g) -> Dictionary:
	return SPECIES.get(String(g.p.get("species", "date_palm")), SPECIES.date_palm)

static func height_of(g) -> float:
	var h := float(g.p.get("height", 0.0))
	return h if h > 0.0 else float(species(g).height)

## One plant (the builder places a row's plants one by one, each its own `variant`).
static func planting(_part: String, g) -> void:
	var m = g.m
	var h := height_of(g)
	match String(g.p.get("species", "date_palm")):
		"date_palm": _palm(m, g, h)
		"tamarisk": _tamarisk(m, g, h)
		"oleander": _shrub(m, g, h, 0.8, OLEANDER, OLEANDER_FLOWER, 0.08, 7, 4)
		"bougainvillea": _bougainvillea(m, g, h)
		"saltbush": _shrub(m, g, h, 1.2, SALTBUSH, SALTBUSH.lightened(0.15), 0.15, 6, 4)
		"caper": _shrub(m, g, h, 2.6, CAPER, CAPER_FLOWER, 0.08, 6, 3)
		"dracaena": _potted(m, g, h)
	var s: Array = species(g).solid
	g.solid_cyl(Vector3.ZERO, Vector3(0, 0, minf(float(s[1]), h)), float(s[0]))

## The basin a tree is watered in (drip-irrigated, SITE.md §4): a low ring of soil round its foot, the wet soil in it.
static func _basin(m, r: float) -> void:
	col(m, "foliage", SOIL)
	m.lathe(Vector3.ZERO, Vector3(0, 0, 1), [[r, 0.0], [r * 1.12, 0.1], [r * 1.3, 0.1], [r * 1.5, 0.0]], 10, false)
	col(m, "foliage", SOIL_WET)
	m.disk(Vector3(0, 0, 0.025), Vector3(0, 0, 1), r * 1.02, 10)   # 2.5 cm over the ground: nearer, they fight (tests/test_ground.gd)
	# the drip line's emitter loop round the trunk (detail)
	col(m, "foliage", HOSE, "detail", 0.02)
	m.torus(Vector3(0, 0, 0.03), Vector3(1, 0, 0), Vector3(0, 1, 0), r * 0.7, 0.01, TAU, 12, 4)

## A date palm: a trunk patterned by the old leaf bases, a crown of arching fronds (each a keeled strip, its leaflets
## standing up in a V from the rachis as a date palm's do) in three tiers, the lowest older and yellower.
static func _palm(m, g, h: float) -> void:
	var rng := _rng(g, 1)
	_basin(m, 1.0)
	var lean := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), 0).normalized() * rng.randf_range(0.0, 0.06)
	var top_z := h - 0.9
	var top := Vector3(lean.x * top_z, lean.y * top_z, top_z)
	var axis := top.normalized()
	# the trunk: leaf-base rings every 0.45 m (its silhouette's notches), widening a little to the crown
	col(m, "foliage", BARK_PALM)
	var prof: Array = []
	var n := maxi(4, int(top_z / 0.45))
	for i in n + 1:
		var t := top_z * i / n
		var r := lerpf(0.27, 0.22, float(i) / n)
		prof.append([r, t])
		if i < n:
			prof.append([r + 0.05, t + top_z / n * 0.55])
	prof.append([0.34, top_z + 0.25])
	prof.append([0.18, top_z + 0.55])
	m.lathe(Vector3.ZERO, axis, prof, 7, false)
	# the old leaf bases ("boots") standing out of the trunk in staggered rings, as a date palm's trunk shows them
	# (detail: up close, on the walkways they shade)
	col(m, "foliage", BARK_PALM.lightened(0.08), "detail", 0.12)
	var rings := int((top_z - 0.5) / 0.4)
	for i in rings:
		var z := 0.45 + i * 0.4
		var r := lerpf(0.27, 0.22, z / top_z) + 0.03
		var c := axis * (z / maxf(axis.z, 0.5))
		for k in 6:
			var a := TAU * (k + 0.5 * (i % 2)) / 6.0 + i * 0.13
			var rad := Vector3(cos(a), sin(a), 0)
			var side := Vector3(-sin(a), cos(a), 0)
			var p0 := c + rad * r
			# one face, out from the trunk (its back is against the trunk)
			_one_sided(m, p0 - side * 0.09, p0 + side * 0.09, p0 + side * 0.06 + rad * 0.11 + Vector3(0, 0, 0.2),
				p0 - side * 0.06 + rad * 0.11 + Vector3(0, 0, 0.2), rad)
	# the crown: 14 fronds by the golden angle, upper ones steep, lower ones drooping past horizontal
	var L := clampf(h * 0.42, 2.0, 3.8)
	var base := top + axis * 0.35
	for k in 14:
		var tier := float(k) / 13.0          # 0 the youngest (top) .. 1 the oldest
		var az := k * 2.39996 + rng.randf_range(-0.15, 0.15)
		var elev := lerpf(1.15, -0.25, tier) + rng.randf_range(-0.08, 0.08)
		var droop := lerpf(0.6, 1.3, tier)
		var c := FROND.lerp(FROND_OLD, tier * tier).lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.05)
		_frond(m, base, az, elev, droop, L * lerpf(0.85, 1.05, tier), 0.62, c)

## A frond from b along azimuth az (radians from north, clockwise), starting at elevation elev and arching down by
## droop over its length L; w its widest (the leaflets' span). Both faces drawn (a thin blade, the shader culls backs).
static func _frond(m, b: Vector3, az: float, elev: float, droop: float, L: float, w: float, c: Color) -> void:
	col(m, "foliage", c)
	var fwd := Vector3(sin(az), cos(az), 0)
	var side := Vector3(cos(az), -sin(az), 0)
	var segs := 4
	var p := b
	var rows: Array = []   # [left edge, rachis, right edge] per station
	for i in segs + 1:
		var t := float(i) / segs
		var a := elev - droop * t * t
		var along := fwd * cos(a) + Vector3(0, 0, 1) * sin(a)
		var up := (side.cross(along)).normalized()
		if up.z < 0:
			up = -up
		var half := w * 0.5 * pow(sin(PI * clampf(t * 1.1 + 0.05, 0.0, 1.0)), 0.6)
		rows.append([p - side * half + up * half * 0.55, p, p + side * half + up * half * 0.55])
		if i < segs:
			p += along * (L / segs)
	for i in segs:
		for s in 2:
			var a0: Vector3 = rows[i][s]
			var a1: Vector3 = rows[i][s + 1]
			var b0: Vector3 = rows[i + 1][s]
			var b1: Vector3 = rows[i + 1][s + 1]
			_two_sided(m, a0, a1, b1, b0)

## A quad a-b-c-d drawn from one side only: the side facing `out` (its back is against something).
static func _one_sided(m, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3) -> void:
	var nrm := (b - a).cross(d - a).normalized()
	var f0: int = m.cur.v.size()
	if nrm.dot(out) < 0.0:   # facing the other way: turned round
		nrm = -nrm
		for q in [a, d, c, b]:
			m._vert(q, nrm, Vector2(q.x + q.z, q.y))
	else:
		for q in [a, b, c, d]:
			m._vert(q, nrm, Vector2(q.x + q.z, q.y))
	m._quad(f0, f0 + 1, f0 + 2, f0 + 3)

## A quad a-b-c-d drawn from both sides (counter-clockwise from the first face's side).
static func _two_sided(m, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var nrm := (b - a).cross(d - a)
	if nrm.length() < 1e-8:
		nrm = (c - b).cross(a - b)
	nrm = nrm.normalized()
	var f0: int = m.cur.v.size()
	for q in [a, b, c, d]:
		m._vert(q, nrm, Vector2(q.x + q.z, q.y))
	m._quad(f0, f0 + 1, f0 + 2, f0 + 3)
	var f1: int = m.cur.v.size()
	for q in [a, b, c, d]:
		m._vert(q, -nrm, Vector2(q.x + q.z, q.y))
	m._quad(f1, f1 + 3, f1 + 2, f1 + 1)

## An ellipsoid of radii r round c, its surface jittered (a crown's lumps), each vertex's colour picked from `cols`
## by weight (leaves, flowers): [[Color, weight], …].
static func _blob(m, c: Vector3, r: Vector3, rng: RandomNumberGenerator, cols: Array, n_az := 8, n_el := 5, jit := 0.16) -> void:
	var total := 0.0
	for cw in cols:
		total += float(cw[1])
	var pick := func() -> Color:
		var x := rng.randf() * total
		for cw in cols:
			x -= float(cw[1])
			if x <= 0.0:
				return cw[0]
		return cols[0][0]
	var first: int = m.cur.v.size()
	var add := func(th: float, ph: float, k: float) -> void:
		var d := Vector3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
		m.colour = pick.call()
		m._vert(c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * k, Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized(),
			Vector2(ph * r.x, th * r.z))
	add.call(0.0, 0.0, 1.0)
	for j in range(1, n_el):
		var th := PI * j / n_el
		for i in n_az:
			add.call(th, TAU * (i + 0.5 * (j % 2)) / n_az, 1.0 + rng.randf_range(-jit, jit))
	add.call(PI, 0.0, 1.0)
	var bottom: int = m.cur.v.size() - 1
	for i in n_az:
		m._tri(first, first + 1 + i, first + 1 + (i + 1) % n_az)
	for j in range(n_el - 2):
		var r0 := first + 1 + j * n_az
		var r1 := r0 + n_az
		for i in n_az:
			var i1 := (i + 1) % n_az
			m._quad(r0 + i, r1 + i, r1 + i1, r0 + i1)
	var last := first + 1 + (n_el - 2) * n_az
	for i in n_az:
		m._tri(bottom, last + (i + 1) % n_az, last + i)

## A tamarisk (Tamarix aphylla, the region's windbreak tree): two or three stems, a dense rounded grey-green crown of
## overlapping lumps, low enough to stop the dust-laden wind at a fence (its feathery twigs are the lumps' colour).
static func _tamarisk(m, g, h: float) -> void:
	var rng := _rng(g, 2)
	col(m, "foliage", BARK)
	var stems := 2 + int(rng.randf() * 2.0)
	for i in stems:
		var a := TAU * i / stems + rng.randf()
		var top := Vector3(cos(a) * 0.5, sin(a) * 0.5, h * 0.38)
		m.cyl(Vector3(cos(a) * 0.08, sin(a) * 0.08, 0), top, 0.12, 0.08, 6, false)
	col(m, "foliage", TAMARISK)
	var w := h * 0.38
	for i in 4:
		var a := TAU * i / 4.0 + rng.randf() * 0.8
		var c := Vector3(cos(a) * w * 0.35, sin(a) * w * 0.35, h * rng.randf_range(0.55, 0.7))
		var cols := [[TAMARISK, 4.0], [TAMARISK.darkened(0.18), 2.0], [TAMARISK.lightened(0.12), 1.0]]
		_blob(m, c, Vector3(w * 0.75, w * 0.75, h * 0.3), rng, cols, 7, 4)

## A dense shrub: an oleander of a hedge, a saltbush or a caper (low and wide): a cluster of smaller lumps (one big
## lump read as a ball), leaves and a few flowers in the vertices' colours.
static func _shrub(m, g, h: float, wide: float, leaf: Color, flower: Color, flower_share: float, n_az: int, n_el: int) -> void:
	var rng := _rng(g, 3)
	col(m, "foliage", leaf)
	var cols := [[leaf, 1.0 - flower_share], [leaf.darkened(0.22), 0.35], [leaf.lightened(0.08), 0.2], [flower, flower_share]]
	var w := h * wide
	var lumps := 5 if h > 1.2 else 4
	for k in lumps:
		var a := TAU * k / lumps + rng.randf_range(-0.4, 0.4)
		var top := k == 0
		var r := w * (0.32 if top else rng.randf_range(0.26, 0.34))
		var c := Vector3(0, 0, h - r * 0.9) if top else Vector3(cos(a) * w * 0.26, sin(a) * w * 0.26, rng.randf_range(0.42, 0.6) * h)
		_blob(m, c, Vector3(r, r, minf(r * 1.1, h * 0.5)), rng, cols, n_az, n_el, 0.1)
	# the stems at the foot (seen under a hedge)
	col(m, "foliage", BARK, "detail", 0.05)
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf()
		m.cyl(Vector3(cos(a) * 0.06, sin(a) * 0.06, 0), Vector3(cos(a) * w * 0.15, sin(a) * w * 0.15, h * 0.4), 0.025, 0.018, 4, false)

## Bougainvillea trained up a porch's or a walkway's post (planted at the post): clusters of leaves and magenta bracts
## climbing it, thinner low down, a round head where it reaches the roof's edge.
static func _bougainvillea(m, g, h: float) -> void:
	var rng := _rng(g, 4)
	col(m, "foliage", BOUGAINVILLEA_LEAF)
	var cols := [[BOUGAINVILLEA_LEAF, 0.45], [BOUGAINVILLEA, 0.4], [BOUGAINVILLEA.darkened(0.2), 0.15]]
	var n := 4
	for k in n:
		var t := (k + 0.5) / n
		var r := lerpf(0.16, 0.3, t)
		var a := rng.randf() * TAU
		var c := Vector3(cos(a) * 0.06, sin(a) * 0.06, h * lerpf(0.2, 0.78, t))
		_blob(m, c, Vector3(r, r, h * 0.16), rng, cols, 6, 3, 0.25)
	_blob(m, Vector3(0, 0, h * 0.95), Vector3(0.6, 0.6, 0.3), rng, cols, 7, 3, 0.25)

## A dracaena in a glazed pot (indoors: the admin lobby's, SITE.md §4): three canes of different heights, each topped
## by a rosette of arching strap leaves; no basin and no drip line (watered by hand).
static func _potted(m, g, h: float) -> void:
	var rng := _rng(g, 11)
	col(m, "plain", POT)
	m.lathe(Vector3.ZERO, Vector3(0, 0, 1), [[0.17, 0.0], [0.22, 0.42], [0.23, 0.45]], 14, false)
	col(m, "foliage", SOIL.darkened(0.3))
	m.disk(Vector3(0, 0, 0.42), Vector3(0, 0, 1), 0.21, 14)
	for k in 3:
		var a := TAU * (k / 3.0 + rng.randf() * 0.1)
		var b := Vector3(cos(a), sin(a), 0) * 0.06 + Vector3(0, 0, 0.42)
		var top := b + Vector3(cos(a) * 0.05, sin(a) * 0.05, (h - 0.6) * (0.55 + 0.22 * k))
		col(m, "foliage", BARK)
		m.cyl(b, top, 0.025, 0.02, 5, false)
		var n := 9
		for j in n:
			var az := TAU * j / n + rng.randf() * 0.3
			_frond(m, top, az, deg_to_rad(35.0 + rng.randf() * 30.0), 0.25, 0.42 + rng.randf() * 0.12, 0.07,
				DRACAENA.lightened(rng.randf() * 0.12))

## The drip line along a row of plants (plant coordinates of the row's ends, in the part frame): a dusty black hose on
## the ground (detail).
static func drip_line(m, a: Vector3, b: Vector3) -> void:
	col(m, "foliage", HOSE, "detail", 0.02)
	m.cyl(a + Vector3(0, 0, 0.012), b + Vector3(0, 0, 0.012), 0.008, -1.0, 4, false)

# ------------------------------------------------------------------ vehicles and the gates

## A bus (12 m), a pickup (5.3 m) or an SUV (4.8 m), parked: the body in its paint, dark glass, tyres. Origin under the
## middle of the vehicle, yaw 0 facing north.
static func vehicle(_part: String, g) -> void:
	var m = g.m
	var kind := String(g.p.get("kind", "pickup"))
	var paint: Color = VEHICLE.get(String(g.p.get("colour", "silver")), VEHICLE.silver)
	paint.a = 0.1
	if kind == "ambulance":
		_ambulance(m, g)
		return
	var W := 2.5 if kind == "bus" else 1.9
	var L: float = {"bus": 12.0, "pickup": 5.3, "suv": 4.8}[kind]
	var wr := 0.5 if kind == "bus" else 0.38
	# tyres and the dark underside
	col(m, "rubber", Color(0.05, 0.05, 0.05))
	var axles: Array = [-L * 0.32, L * 0.3] if kind == "bus" else [-L * 0.3, L * 0.31]
	for y in axles:
		for sx: float in [-1.0, 1.0]:
			m.cyl(Vector3(sx * (W * 0.5 - 0.25), y, wr), Vector3(sx * (W * 0.5 - 0.02), y, wr), wr, -1.0, 10)
	col(m, "paint_darkgrey", Color(0.15, 0.15, 0.16))
	m.box_lh(Vector3(-W * 0.45, -L * 0.48, wr * 0.6), Vector3(W * 0.45, L * 0.48, wr * 1.2))
	col(m, "paint_white", paint)
	var glass := Color(0.10, 0.12, 0.14)
	if kind == "bus":
		m.box_lh(Vector3(-W * 0.5, -L * 0.5, 0.6), Vector3(W * 0.5, L * 0.5, 3.1))
		col(m, "glass", glass)
		for sx: float in [-1.0, 1.0]:
			m.box_lh(Vector3(sx * W * 0.5 - 0.01, -L * 0.42, 1.75), Vector3(sx * W * 0.5 + 0.01 * sx, L * 0.36, 2.75))
		m.box_lh(Vector3(-W * 0.45, L * 0.5, 1.3), Vector3(W * 0.45, L * 0.5 + 0.02, 2.8))
		col(m, "paint_darkgrey", Color(0.25, 0.26, 0.27))
		m.box_lh(Vector3(W * 0.5, L * 0.38, 0.4), Vector3(W * 0.5 + 0.02, L * 0.46, 2.7))   # the door
	else:
		var cab0 := -0.2 if kind == "pickup" else -L * 0.42
		var cab1 := L * 0.18
		m.box_lh(Vector3(-W * 0.5, -L * 0.5, 0.55), Vector3(W * 0.5, L * 0.5, 1.15))
		m.hexa([Vector3(-W * 0.47, cab0, 1.15), Vector3(W * 0.47, cab0, 1.15), Vector3(W * 0.47, cab1, 1.15),
			Vector3(-W * 0.47, cab1, 1.15), Vector3(-W * 0.42, cab0 + 0.1, 1.85), Vector3(W * 0.42, cab0 + 0.1, 1.85),
			Vector3(W * 0.42, cab1 - 0.55, 1.85), Vector3(-W * 0.42, cab1 - 0.55, 1.85)])
		col(m, "glass", glass)
		for sx: float in [-1.0, 1.0]:
			m.box_lh(Vector3(sx * W * 0.45 - 0.01, cab0 + 0.25, 1.22), Vector3(sx * W * 0.45 + 0.01, cab1 - 0.7, 1.75))
		m.box_lh(Vector3(-W * 0.38, cab1 - 0.45, 1.25), Vector3(W * 0.38, cab1 - 0.2, 1.75))
		if kind == "pickup":
			col(m, "paint_darkgrey", Color(0.12, 0.12, 0.12))
			m.box_lh(Vector3(-W * 0.44, -L * 0.48, 1.0), Vector3(W * 0.44, cab0 - 0.08, 1.16))   # the open bed
	# lamps (detail)
	col(m, "plain", Color(0.9, 0.9, 0.85), "detail", 0.15)
	for sx: float in [-1.0, 1.0]:
		m.box(Vector3(sx * W * 0.36, L * 0.5 + 0.01, 0.95 if kind != "bus" else 0.9), Vector3(0.25, 0.03, 0.12))
	col(m, "plain", Color(0.7, 0.08, 0.06), "detail", 0.12)
	for sx: float in [-1.0, 1.0]:
		m.box(Vector3(sx * W * 0.42, -L * 0.5 - 0.01, 1.0), Vector3(0.18, 0.03, 0.2))
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 3.1 if kind == "bus" else 1.85))

## The camp's ambulance (parked by the first-aid point, SITE.md §3): a high-roofed van 5.4 m long, its body pale (as
## ambulances are everywhere; the fleet's own colours stay muted), a red band along its sides and back, the blue
## light bar over the cab (off while parked), the rear doors' windows. Origin under its middle, facing +y.
const AMBULANCE := Color(0.88, 0.88, 0.85, 0.1)
static func _ambulance(m, g) -> void:
	var W := 2.0
	var L := 5.4
	var wr := 0.36
	col(m, "rubber", Color(0.05, 0.05, 0.05))
	for y: float in [-L * 0.3, L * 0.3]:
		for sx: float in [-1.0, 1.0]:
			m.cyl(Vector3(sx * (W * 0.5 - 0.25), y, wr), Vector3(sx * (W * 0.5 - 0.02), y, wr), wr, -1.0, 10)
	col(m, "paint_darkgrey", Color(0.15, 0.15, 0.16))
	m.box_lh(Vector3(-W * 0.45, -L * 0.48, wr * 0.6), Vector3(W * 0.45, L * 0.48, wr * 1.3))
	col(m, "paint_white", AMBULANCE)
	var cab := L * 0.5 - 1.5   # the box ends and the cab begins
	m.box_lh(Vector3(-W * 0.5, -L * 0.5, 0.5), Vector3(W * 0.5, cab, 2.5))
	m.box_lh(Vector3(-W * 0.5, cab, 0.5), Vector3(W * 0.5, L * 0.5, 1.15))
	m.hexa([Vector3(-W * 0.5, cab, 1.15), Vector3(W * 0.5, cab, 1.15), Vector3(W * 0.48, L * 0.5 - 0.05, 1.15),
		Vector3(-W * 0.48, L * 0.5 - 0.05, 1.15), Vector3(-W * 0.48, cab, 2.3), Vector3(W * 0.48, cab, 2.3),
		Vector3(W * 0.45, cab + 0.75, 2.2), Vector3(-W * 0.45, cab + 0.75, 2.2)])
	col(m, "glass", Color(0.10, 0.12, 0.14))
	# the windscreen, on the cab's slope (1 cm proud of it)
	var a0 := Vector3(0, cab + 0.75, 2.2).lerp(Vector3(0, L * 0.5 - 0.05, 1.15), 0.08)
	var a1 := Vector3(0, cab + 0.75, 2.2).lerp(Vector3(0, L * 0.5 - 0.05, 1.15), 0.72)
	var nrm := (a1 - a0).cross(Vector3(1, 0, 0)).normalized() * -0.015
	_two_sided(m, Vector3(-W * 0.43, a0.y, a0.z) + nrm, Vector3(W * 0.43, a0.y, a0.z) + nrm,
		Vector3(W * 0.45, a1.y, a1.z) + nrm, Vector3(-W * 0.45, a1.y, a1.z) + nrm)
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * W * 0.5 - 0.01, cab + 0.1, 1.3), Vector3(sx * W * 0.5 + 0.01, cab + 0.95, 1.95))
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * 0.45 - 0.3, -L * 0.5 - 0.015, 1.6), Vector3(sx * 0.45 + 0.3, -L * 0.5, 2.1))
	col(m, "paint_red", Color(0.72, 0.09, 0.07, 0.15))
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(minf(sx * W * 0.5, sx * (W * 0.5 + 0.015)), -L * 0.5 - 0.015, 1.0),
			Vector3(maxf(sx * W * 0.5, sx * (W * 0.5 + 0.015)), L * 0.5 - 0.1, 1.2))   # 1.5 cm proud: no depth fight
	m.box_lh(Vector3(-W * 0.5 - 0.015, -L * 0.5 - 0.015, 1.0), Vector3(W * 0.5 + 0.015, -L * 0.5, 1.2))
	col(m, "plain", Color(0.15, 0.30, 0.75))
	m.box_lh(Vector3(-W * 0.42, cab - 0.25, 2.5), Vector3(W * 0.42, cab + 0.05, 2.62))   # the light bar
	col(m, "plain", Color(0.9, 0.9, 0.85), "detail", 0.15)
	for sx: float in [-1.0, 1.0]:
		m.box(Vector3(sx * W * 0.36, L * 0.5 + 0.01, 0.95), Vector3(0.25, 0.03, 0.12))
	col(m, "plain", Color(0.7, 0.08, 0.06), "detail", 0.12)
	for sx: float in [-1.0, 1.0]:
		m.box(Vector3(sx * W * 0.46, -L * 0.5 - 0.01, 1.2), Vector3(0.1, 0.03, 0.4))
	g.solid_box(Vector3(-W * 0.5, -L * 0.5, 0), Vector3(W * 0.5, L * 0.5, 2.6))

## A gate's barrier: its post with the counterweight, the arm in red and white bands across `width` (raised when
## `open`), and a rest post at its tip. Origin at the hinge post's foot; the arm runs along +x.
static func barrier(_part: String, g) -> void:
	var m = g.m
	var w: float = g.num("width", 4.0)
	col(m, "paint_yellow", Color(0.92, 0.70, 0.08, 0.5))
	m.box_lh(Vector3(-0.2, -0.2, 0), Vector3(0.2, 0.2, 1.05))
	col(m, "paint_darkgrey", Color(0.25, 0.25, 0.26, 0.3))
	m.box_lh(Vector3(-0.6, -0.1, 0.85), Vector3(-0.2, 0.1, 1.05))   # the counterweight
	var raised: bool = g.p.get("open", false)
	var n := maxi(4, int(w / 0.5))
	for i in n:
		col(m, "paint_red" if i % 2 == 0 else "paint_white", Color(0.75, 0.08, 0.06, 0.3) if i % 2 == 0 else Color(0.92, 0.92, 0.90, 0.3))
		var t0 := 0.2 + (w - 0.2) * i / n
		var t1 := 0.2 + (w - 0.2) * (i + 1) / n
		if raised:
			m.box_lh(Vector3(-0.04, -0.03, 1.0 + t0), Vector3(0.04, 0.03, 1.0 + t1))
		else:
			m.box_lh(Vector3(t0, -0.04, 0.95), Vector3(t1, 0.04, 1.03))
	if not raised:
		col(m, "paint_darkgrey", Color(0.3, 0.3, 0.3, 0.3))
		m.box_lh(Vector3(w - 0.05, -0.05, 0), Vector3(w + 0.05, 0.05, 0.92))
	g.solid_box(Vector3(-0.2, -0.2, 0), Vector3(0.2, 0.2, 1.05))
	if not raised:
		g.solid_box(Vector3(0.2, -0.05, 0.9), Vector3(w + 0.05, 0.05, 1.05))

## A guard booth: a small prefabricated cabin with windows all round, an overhanging flat roof and a door on its south
## side (yaw turns it). Origin at its floor's centre.
static func guard_booth(_part: String, g) -> void:
	var m = g.m
	var w: float = g.num("width", 2.2)
	var d: float = g.num("depth", 2.2)
	col(m, "concrete", Color(1, 1, 1))
	m.box_lh(Vector3(-w * 0.5 - 0.1, -d * 0.5 - 0.1, 0), Vector3(w * 0.5 + 0.1, d * 0.5 + 0.1, 0.12))
	col(m, "paint_white", Color(0.84, 0.81, 0.73, 0.15))
	m.box_lh(Vector3(-w * 0.5, -d * 0.5, 0.12), Vector3(w * 0.5, d * 0.5, 1.0))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		m.box_lh(Vector3(c.x * w * 0.5 - 0.06, c.y * d * 0.5 - 0.06, 1.0), Vector3(c.x * w * 0.5 + 0.06, c.y * d * 0.5 + 0.06, 2.4))
	m.box_lh(Vector3(-w * 0.5 - 0.3, -d * 0.5 - 0.3, 2.4), Vector3(w * 0.5 + 0.3, d * 0.5 + 0.3, 2.6))
	col(m, "window_glass", Color(1, 1, 1))
	m.box_lh(Vector3(-w * 0.5 + 0.04, -d * 0.5 + 0.04, 1.0), Vector3(w * 0.5 - 0.04, d * 0.5 - 0.04, 2.4))
	col(m, "paint_darkgrey", Color(0.32, 0.33, 0.34, 0.3))
	m.box_lh(Vector3(-0.4, -d * 0.5 - 0.03, 0.12), Vector3(0.4, -d * 0.5, 2.25))   # the door
	g.solid_box(Vector3(-w * 0.5, -d * 0.5, 0), Vector3(w * 0.5, d * 0.5, 2.6))

## A shade canopy (over parking and walkways): galvanised posts every 5 m or so along both long sides, beams, and a
## sand-coloured shade sheet sloping a little to one side. Origin at the middle of its footprint; length along y.
static func canopy(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 10.0)
	var w: float = g.num("width", 5.0)
	var h: float = g.num("height", 3.0)
	if String(g.p.get("kind", "sheet")) == "sail":
		_sail(m, g, L, w, h)
		return
	var n := maxi(1, int(ceil(L / 5.5)))
	col(m, "galvanised", Color(0.85, 0.87, 0.88))
	for i in n + 1:
		var y := -L * 0.5 + L * i / n
		for sx: float in ([-1.0, 1.0] if w > 3.0 else [0.0]):
			var x := sx * (w * 0.5 - 0.15)
			m.cyl(Vector3(x, y, 0), Vector3(x, y, h + (0.25 if sx < 0 else 0.0)), 0.06, -1.0, 8)
			g.solid_cyl(Vector3(x, y, 0), Vector3(x, y, h), 0.08)
		m.box_lh(Vector3(-w * 0.5, y - 0.05, h - 0.05), Vector3(w * 0.5, y + 0.05, h + 0.08))
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * (w * 0.5 - 0.15) - 0.05, -L * 0.5, h), Vector3(sx * (w * 0.5 - 0.15) + 0.05, L * 0.5, h + 0.1))
	col(m, "matte", Color(0.83, 0.78, 0.66))
	var hi := h + 0.35
	var a := Vector3(-w * 0.5 - 0.2, -L * 0.5 - 0.2, hi)
	var b := Vector3(w * 0.5 + 0.2, -L * 0.5 - 0.2, h + 0.1)
	var c := Vector3(w * 0.5 + 0.2, L * 0.5 + 0.2, h + 0.1)
	var d := Vector3(-w * 0.5 - 0.2, L * 0.5 + 0.2, hi)
	_two_sided(m, a, b, c, d)

## A car park's shade sails (`kind` sail): steel posts along the -x side every bay (about 5.5 m: two cars), from each
## an arched arm across the width, and between two arms a white tensioned fabric vault, sagging a little between
## them. Origin at the middle of its footprint; length along y.
const SAIL := Color(0.93, 0.93, 0.90)
static func _sail(m, g, L: float, w: float, h: float) -> void:
	var n := maxi(1, int(ceil(L / 5.5)))
	var NA := 6
	var rise := 1.0
	var xp := -w * 0.5 + 0.25
	var arc := func(t: float) -> Vector2:   # across the width, t 0..1: (x, z) of the arm
		return Vector2(lerpf(xp, w * 0.5, t), h + rise * sin(PI * (0.15 + 0.85 * t)) - 0.25 * t)
	for i in n + 1:
		var y := -L * 0.5 + L * i / n
		col(m, "galvanised", Color(0.85, 0.87, 0.88))
		var top: Vector2 = arc.call(0.0)
		m.cyl(Vector3(xp, y, 0), Vector3(xp, y, top.y), 0.09, -1.0, 8)
		g.solid_cyl(Vector3(xp, y, 0), Vector3(xp, y, h), 0.1)
		for k in NA:
			var a: Vector2 = arc.call(float(k) / NA)
			var b: Vector2 = arc.call(float(k + 1) / NA)
			m.cyl(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), 0.05, -1.0, 6, false)
		var st: Vector2 = arc.call(0.35)
		m.cyl(Vector3(xp, y, h - 1.0), Vector3(st.x, y, st.y), 0.04, -1.0, 6, false)   # its strut
	col(m, "matte", SAIL)
	var NY := 3
	for i in n:
		var y0 := -L * 0.5 + L * i / n + 0.08
		var y1 := -L * 0.5 + L * (i + 1) / n - 0.08
		for k in NA:
			for j in NY:
				var q := []
				for c in [[k, j], [k + 1, j], [k + 1, j + 1], [k, j + 1]]:
					var a: Vector2 = arc.call(float(c[0]) / NA)
					var v := float(c[1]) / NY
					var sag := 0.18 * sin(PI * v) * sin(PI * float(c[0]) / NA)
					q.append(Vector3(a.x, lerpf(y0, y1, v), a.y + 0.04 - sag))
				_two_sided(m, q[0], q[1], q[2], q[3])

## A street lamp: a tapered galvanised pole on a concrete foot, its arm(s) and the lantern (off by day).
static func lamp_post(_part: String, g) -> void:
	var m = g.m
	var h: float = g.num("height", 8.0)
	col(m, "concrete", Color(1, 1, 1))
	m.cyl(Vector3.ZERO, Vector3(0, 0, 0.35), 0.25, 0.22, 8)
	col(m, "galvanised", Color(0.85, 0.87, 0.88))
	m.cyl(Vector3(0, 0, 0.35), Vector3(0, 0, h), 0.08, 0.05, 8)
	var arms := int(g.num("arms", 1))
	for k in arms:
		var s := 1.0 if k == 0 else -1.0
		m.cyl(Vector3(0, 0, h - 0.1), Vector3(0, s * 1.4, h + 0.15), 0.035, -1.0, 6, false)
		col(m, "paint_darkgrey", Color(0.3, 0.31, 0.32, 0.2))
		m.box(Vector3(0, s * 1.55, h + 0.12), Vector3(0.28, 0.6, 0.12))
		col(m, "lamp_off", Color(1, 1, 1))
		m.box(Vector3(0, s * 1.55, h + 0.05), Vector3(0.22, 0.5, 0.03))
		col(m, "galvanised", Color(0.85, 0.87, 0.88))
	g.solid_cyl(Vector3.ZERO, Vector3(0, 0, h), 0.12)

## A kerb along `route` (relative to the origin): 15 cm high, 15 wide, painted in yellow and white stripes 1 m long
## when `painted` (the site's and the camp's roads, as such sites paint them), else bare concrete. Drawn only: a walker steps over it.
static func kerb(_part: String, g) -> void:
	var m = g.m
	var route: Array = g.p.get("route", [])
	var painted: bool = g.p.get("painted", true)
	for i in range(route.size() - 1):
		var a := Vector3(float(route[i][0]), float(route[i][1]), 0)
		var b := Vector3(float(route[i + 1][0]), float(route[i + 1][1]), 0)
		var L := a.distance_to(b)
		if L < 0.05:
			continue
		var d := (b - a) / L
		var bs := Basis(Vector3(d.y, -d.x, 0), d, Vector3(0, 0, 1))
		var n := maxi(1, int(round(L))) if painted else 1
		for k in n:
			if painted:
				col(m, "paint_white", Color(0.92, 0.70, 0.08, 0.3) if k % 2 == 0 else Color(0.90, 0.90, 0.87, 0.3))
			else:
				col(m, "concrete", Color(1, 1, 1))
			var c := a + d * (L * (k + 0.5) / n)
			m.box(c + Vector3(0, 0, 0.075), Vector3(0.15, L / n, 0.15), bs)

## A marked pedestrian crossing: white stripes 0.5 m wide every metre across a road `width` wide, each `length` long
## along the road (y), painted 2 cm proud of it (drawn only: closer, it fought the road in a phone's depth buffer,
## tests/test_ground.gd). Origin at its centre.
static func crossing(_part: String, g) -> void:
	var m = g.m
	var w: float = g.num("width", 7.0)
	var L: float = g.num("length", 3.0)
	col(m, "plain", Color(0.90, 0.90, 0.88))
	var n := int(floor(w))
	for k in n:
		var x := -w * 0.5 + (w - n) * 0.5 + k + 0.25
		m.box_lh(Vector3(x, -L * 0.5, 0.0), Vector3(x + 0.5, L * 0.5, 0.02))

## A pillar fire hydrant by a road (red: fire equipment is red whatever the plant's colours): its foot flange, the
## barrel, two hose outlets with chained caps either side, the pumper outlet in front (+y), the bonnet and its
## operating nut. Origin at its foot.
const FIRE_RED := Color(0.72, 0.09, 0.07, 0.35)
static func hydrant(_part: String, g) -> void:
	var m = g.m
	# one material (the paint's, its colours in the vertices) and a `detail` piece: drawn within its size's range, as
	# small things are, wherever it stands (no far view need parent it), casting no shadow
	col(m, "paint_white", Color(0.62, 0.61, 0.58, 0.4), "detail", 0.9)   # its concrete collar
	m.cyl(Vector3(0, 0, -0.05), Vector3(0, 0, 0.06), 0.32, -1.0, 10)
	col(m, "paint_red", FIRE_RED, "detail", 0.9)
	m.cyl(Vector3(0, 0, 0.06), Vector3(0, 0, 0.12), 0.17, -1.0, 12)
	m.cyl(Vector3(0, 0, 0.12), Vector3(0, 0, 0.72), 0.11, -1.0, 12, false)
	m.cyl(Vector3(0, 0, 0.72), Vector3(0, 0, 0.76), 0.14, -1.0, 12)
	m.dish(Vector3(0, 0, 0.76), Vector3(0, 0, 1), 0.13, 0.09, 12, 3)
	m.cyl(Vector3(0, 0, 0.84), Vector3(0, 0, 0.9), 0.03, -1.0, 6)   # the operating nut
	for sx: float in [-1.0, 1.0]:
		m.cyl(Vector3(sx * 0.08, 0, 0.55), Vector3(sx * 0.2, 0, 0.55), 0.045, -1.0, 10)
		m.cyl(Vector3(sx * 0.2, 0, 0.55), Vector3(sx * 0.23, 0, 0.55), 0.055, -1.0, 10)
	m.cyl(Vector3(0, 0.08, 0.42), Vector3(0, 0.2, 0.42), 0.06, -1.0, 10)
	m.cyl(Vector3(0, 0.2, 0.42), Vector3(0, 0.24, 0.42), 0.075, -1.0, 10)
	g.solid_cyl(Vector3.ZERO, Vector3(0, 0, 0.9), 0.16)

## A bollard post (`height`): a red steel tube on its buried foot, a white retroreflective band near its top (a hydrant's
## or a cabinet's guard against vehicles, a road's edge). Origin at its foot.
static func bollard(_part: String, g) -> void:
	var m = g.m
	var h: float = g.num("height", 1.2)
	col(m, "paint_red", FIRE_RED, "detail", h)   # (a detail piece, as the hydrant)
	m.cyl(Vector3.ZERO, Vector3(0, 0, h - 0.18), 0.05, -1.0, 10, false)
	col(m, "paint_white", Color(0.92, 0.92, 0.90, 0.2), "detail", h)
	m.cyl(Vector3(0, 0, h - 0.18), Vector3(0, 0, h - 0.08), 0.051, -1.0, 10, false)
	col(m, "paint_red", FIRE_RED, "detail", h)
	m.cyl(Vector3(0, 0, h - 0.08), Vector3(0, 0, h), 0.05, -1.0, 10)
	g.solid_cyl(Vector3.ZERO, Vector3(0, 0, h), 0.06)

## A steel skip bin (a wheeled refuse container, about 2.5 m³): its body narrower at the foot, a rolled rim, two lid
## flaps (one propped open), the lifting trunnions either side and four castors. Painted grey, dusty. Origin at its
## foot's centre; its long side along x.
static func skip_bin(_part: String, g) -> void:
	var m = g.m
	var steel := Color(0.56, 0.58, 0.58, 0.35)   # painted grey steel, knocked about
	col(m, "rubber", Color(0.05, 0.05, 0.05))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		m.cyl(Vector3(c.x * 0.62, c.y * 0.42 - 0.04, 0.09), Vector3(c.x * 0.62, c.y * 0.42 + 0.04, 0.09), 0.09, -1.0, 8)
	col(m, "paint_white", steel)
	m.hexa([Vector3(-0.72, -0.5, 0.2), Vector3(0.72, -0.5, 0.2), Vector3(0.72, 0.5, 0.2), Vector3(-0.72, 0.5, 0.2),
		Vector3(-0.9, -0.62, 1.3), Vector3(0.9, -0.62, 1.3), Vector3(0.9, 0.62, 1.3), Vector3(-0.9, 0.62, 1.3)])
	for sy: float in [-1.0, 1.0]:
		m.box_lh(Vector3(-0.92, sy * 0.62 - 0.03, 1.24), Vector3(0.92, sy * 0.62 + 0.03, 1.33))   # the rim
	for sx: float in [-1.0, 1.0]:
		m.cyl(Vector3(sx * 0.85, 0, 1.05), Vector3(sx * 1.0, 0, 1.05), 0.05, -1.0, 8)   # the trunnions
	col(m, "paint_white", steel.darkened(0.12))
	m.box_lh(Vector3(-0.9, -0.62, 1.33), Vector3(0.0, 0.62, 1.36))   # one flap shut
	m.box(Vector3(0.45, 0.72, 1.62), Vector3(0.9, 0.03, 0.62))     # the other propped open against the back
	g.solid_box(Vector3(-0.92, -0.64, 0), Vector3(0.92, 0.64, 1.36))

## A telecom mast (`height`): a square lattice tower tapering from a tenth of its height at the foot to 1 m, its legs
## on concrete pads, horizontals at every 3 m section and one diagonal across each face of each section (alternating),
## the antenna platform at the top with three panel antennas and two microwave dishes, the aviation lamp. Galvanised.
## Origin at the middle of its foot.
static func mast(_part: String, g) -> void:
	var m = g.m
	var h: float = g.num("height", 30)
	var b0 := maxf(1.5, h * 0.1) * 0.5
	var b1 := 0.5
	var n := maxi(3, int(round(h / 3.0)))
	var half := func(z: float) -> float: return lerpf(b0, b1, z / h)
	var corner := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	col(m, "concrete", Color(1, 1, 1))
	for c: Vector2 in corner:
		m.box_lh(Vector3(c.x * b0 - 0.35, c.y * b0 - 0.35, 0), Vector3(c.x * b0 + 0.35, c.y * b0 + 0.35, 0.3))
	col(m, "galvanised", Color(0.80, 0.82, 0.83))
	for i in n:
		var z0 := h * i / n
		var z1 := h * (i + 1) / n
		var a0: float = half.call(z0)
		var a1: float = half.call(z1)
		for k in 4:
			var c: Vector2 = corner[k]
			var d: Vector2 = corner[(k + 1) % 4]
			m.cyl(Vector3(c.x * a0, c.y * a0, z0), Vector3(c.x * a1, c.y * a1, z1), 0.06 if i < n / 2 else 0.045, -1.0, 6, false)
	for i in n:
		var z0 := h * i / n
		var z1 := h * (i + 1) / n
		var a0: float = half.call(z0)
		var a1: float = half.call(z1)
		col(m, "galvanised", Color(0.80, 0.82, 0.83), "detail", 0.3)
		for k in 4:
			var c: Vector2 = corner[k]
			var d: Vector2 = corner[(k + 1) % 4]
			m.cyl(Vector3(c.x * a1, c.y * a1, z1), Vector3(d.x * a1, d.y * a1, z1), 0.025, -1.0, 4, false)
			var lo := c if (i + k) % 2 == 0 else d
			var hi := d if (i + k) % 2 == 0 else c
			m.cyl(Vector3(lo.x * a0, lo.y * a0, z0), Vector3(hi.x * a1, hi.y * a1, z1), 0.025, -1.0, 4, false)
	# the antenna platform and its rail, the panel antennas on their pipes, two dishes, the aviation lamp
	col(m, "galvanised", Color(0.80, 0.82, 0.83))
	var zp := h - 2.5
	m.box_lh(Vector3(-1.2, -1.2, zp - 0.08), Vector3(1.2, 1.2, zp))
	for k in 3:
		var a := TAU * k / 3.0 + 0.3
		var p := Vector3(cos(a), sin(a), 0) * 1.05
		m.cyl(p + Vector3(0, 0, zp), p + Vector3(0, 0, h + 0.3), 0.04, -1.0, 6, false)
		col(m, "plain", Color(0.86, 0.86, 0.84))
		m.box(p * (1.15 / 1.05) + Vector3(0, 0, h - 0.6), Vector3(0.12, 0.3, 1.4), Basis(Vector3(0, 0, 1), a))   # on its pipe, facing out
		col(m, "galvanised", Color(0.80, 0.82, 0.83))
	col(m, "plain", Color(0.86, 0.86, 0.84))
	for k in 2:
		var a := PI * k   # off the middle of a face (+x, -x), clear of the corner legs
		var dirv := Vector3(cos(a), sin(a), 0)
		var zd := h - 6.0 - 1.5 * k
		var hw: float = half.call(zd)
		var c := dirv * (hw + 0.32) + Vector3(0, 0, zd)   # its back drum against the tower's face
		m.dish(c, dirv, 0.45, 0.18, 14, 3)
		m.cyl(c - dirv * 0.05, c - dirv * 0.3, 0.2, -1.0, 10)
	col(m, "plain", Color(0.75, 0.08, 0.05), "detail", 0.2)
	m.cyl(Vector3(0, 0, h + 0.3), Vector3(0, 0, h + 0.5), 0.08, -1.0, 8)
	g.solid_box(Vector3(-b0 - 0.35, -b0 - 0.35, 0), Vector3(b0 + 0.35, b0 + 0.35, 3.0))   # its foot, legs and bracing

## A split air conditioner's outdoor unit on its wall brackets, under a window (the camp's blocks, the offices): the
## casing, the fan's grille on the front (+y, away from the wall at the origin), the coil's grille at its side, the
## insulated pipes up the wall to the room. Origin on the wall's face below the unit's middle, at the unit's foot.
static func ac_unit(_part: String, g) -> void:
	var m = g.m
	# one material (matte, the colours in the vertices): 136 of them stand in the camp and the offices, and each material
	# would be a draw call per cell; the grilles 1.5 cm proud of the casing (closer, they fight in a phone's depth buffer)
	col(m, "matte", Color(0.30, 0.31, 0.32))
	for sx: float in [-1.0, 1.0]:   # the brackets
		m.box_lh(Vector3(sx * 0.3 - 0.02, 0.0, -0.04), Vector3(sx * 0.3 + 0.02, 0.4, 0.0))
		m.box_lh(Vector3(sx * 0.3 - 0.02, 0.0, -0.2), Vector3(sx * 0.3 + 0.02, 0.03, 0.0))
	col(m, "matte", Color(0.87, 0.87, 0.84))
	m.box_lh(Vector3(-0.42, 0.06, 0.0), Vector3(0.42, 0.36, 0.58))
	col(m, "matte", Color(0.18, 0.18, 0.19))
	m.cyl(Vector3(-0.1, 0.36, 0.29), Vector3(-0.1, 0.375, 0.29), 0.21, -1.0, 16)
	col(m, "matte", Color(0.55, 0.56, 0.56))
	m.box_lh(Vector3(0.42, 0.08, 0.06), Vector3(0.435, 0.33, 0.52))
	col(m, "matte", Color(0.82, 0.82, 0.79))
	m.cyl(Vector3(0.36, 0.06, 0.4), Vector3(0.36, 0.03, 0.4), 0.025, -1.0, 6, false)
	m.cyl(Vector3(0.36, 0.03, 0.4), Vector3(0.36, 0.03, 1.0), 0.025, -1.0, 6, false)
	g.solid_box(Vector3(-0.42, 0.0, -0.05), Vector3(0.42, 0.36, 0.58))

## A sports court (`length` along y): its surface with the lines, a chain-link fence round it (posts, rails; the mesh
## itself is a `detail` grid) with a gate gap in the middle of its east side, and a floodlight mast at each corner.
## Origin at the court's centre. Its layers (the surround, the playing area, the lines) stand COURT_STEP apart: closer,
## they fought in a phone's depth buffer (tests/test_ground.gd).
const COURT_STEP := 0.02
static func court(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 28.0)
	var w: float = g.num("width", 15.0)
	var fh: float = g.num("fence", 4.0)
	col(m, "matte", Color(0.30, 0.42, 0.36))
	m.box_lh(Vector3(-w * 0.5, -L * 0.5, 0), Vector3(w * 0.5, L * 0.5, COURT_STEP))
	col(m, "matte", Color(0.55, 0.30, 0.24))
	m.box_lh(Vector3(-w * 0.5 + 1.5, -L * 0.5 + 1.5, COURT_STEP), Vector3(w * 0.5 - 1.5, L * 0.5 - 1.5, COURT_STEP * 2.0))
	col(m, "plain", Color(0.92, 0.92, 0.9))
	var lw := 0.06
	var x0 := -w * 0.5 + 1.5
	var x1 := w * 0.5 - 1.5
	var y0 := -L * 0.5 + 1.5
	var y1 := L * 0.5 - 1.5
	# the centre line stops at the centre circle and goes on inside it (the circle's ring and the line would overlap)
	var rc := 1.8
	# (the side lines and the centre line stop at the lines they meet: no line over another)
	for seg in [[Vector2(x0, y0), Vector2(x1, y0)], [Vector2(x1, y0 + lw * 2.0), Vector2(x1, y1 - lw * 2.0)],
			[Vector2(x1, y1), Vector2(x0, y1)], [Vector2(x0, y1 - lw * 2.0), Vector2(x0, y0 + lw * 2.0)],
			[Vector2(x0 + lw * 2.0, 0), Vector2(-rc - lw * 3.0, 0)],
			[Vector2(-rc + lw, 0), Vector2(rc - lw, 0)], [Vector2(rc + lw * 3.0, 0), Vector2(x1 - lw * 2.0, 0)]]:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		m.box_lh(Vector3(minf(a.x, b.x) - lw, minf(a.y, b.y) - lw, COURT_STEP * 2.0),
			Vector3(maxf(a.x, b.x) + lw, maxf(a.y, b.y) + lw, COURT_STEP * 3.0))
	m.ring(Vector3(0, 0, COURT_STEP * 3.0), Vector3(0, 0, 1), rc, rc + lw * 2.0, 24)
	# the fence: posts every 3 m, top and bottom rails, the gate gap (2 m) in the east side
	var corners := [Vector2(-w * 0.5, -L * 0.5), Vector2(w * 0.5, -L * 0.5), Vector2(w * 0.5, L * 0.5), Vector2(-w * 0.5, L * 0.5)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var gap: Array = [-1.0, 1.0] if i == 1 else []
		_chain_fence(m, g, a, b, fh, gap)
	# floodlights at the corners
	for c in corners:
		var p := Vector3(c.x * 1.04, c.y * 1.02, 0)
		col(m, "galvanised", Color(0.85, 0.87, 0.88))
		m.cyl(p, p + Vector3(0, 0, 9), 0.1, 0.07, 8)
		g.solid_cyl(p, p + Vector3(0, 0, 9), 0.12)
		col(m, "paint_darkgrey", Color(0.3, 0.3, 0.32, 0.2))
		var inward := -Vector3(c.x, c.y, 0).normalized()
		m.box(p + Vector3(0, 0, 9.1) + inward * 0.3, Vector3(0.7, 0.7, 0.35))
		col(m, "lamp_off", Color(1, 1, 1))
		m.box(p + Vector3(0, 0, 8.92) + inward * 0.3, Vector3(0.6, 0.6, 0.02))

## A chain-link fence from a to b (plan), fh high; `gap` [t0, t1] metres round its middle left open (a gate).
static func _chain_fence(m, g, a: Vector2, b: Vector2, fh: float, gap: Array) -> void:
	var L := a.distance_to(b)
	var d := (b - a) / L
	var mid := L * 0.5
	var pieces: Array = [[0.0, L]] if gap.is_empty() else [[0.0, mid + float(gap[0])], [mid + float(gap[1]), L]]
	for pc in pieces:
		var t0: float = pc[0]
		var t1: float = pc[1]
		var p0 := a + d * t0
		var p1 := a + d * t1
		col(m, "galvanised", Color(0.85, 0.87, 0.88))
		var n := maxi(1, int(ceil((t1 - t0) / 3.0)))
		for k in n + 1:
			var p := p0.lerp(p1, float(k) / n)
			m.cyl(Vector3(p.x, p.y, 0), Vector3(p.x, p.y, fh), 0.03, -1.0, 6, false)
		for z: float in [0.08, fh * 0.5, fh]:
			m.cyl(Vector3(p0.x, p0.y, z), Vector3(p1.x, p1.y, z), 0.022, -1.0, 6, false)
		# the mesh: a grid of wires 0.5 m apart (detail: from afar the posts and rails remain)
		col(m, "galvanised", Color(0.80, 0.82, 0.83), "detail", 0.25)
		var nv := int((t1 - t0) / 0.5)
		for k in nv:
			var p := p0.lerp(p1, (k + 0.5) / nv)
			m.box(Vector3(p.x, p.y, fh * 0.5), Vector3(0.012, 0.012, fh - 0.1))
		var nh := int(fh / 0.5)
		var bs := Basis(Vector3(d.y, -d.x, 0), Vector3(d.x, d.y, 0), Vector3(0, 0, 1))
		for k in nh:
			var c := (p0 + p1) * 0.5
			m.box(Vector3(c.x, c.y, 0.1 + (fh - 0.2) * (k + 0.5) / nh), Vector3(0.012, t1 - t0, 0.012), bs)
		var mid_p := (p0 + p1) * 0.5
		g.solid_obox(Vector3(mid_p.x, mid_p.y, fh * 0.5), Vector3(0.1, t1 - t0, fh), bs)

## A porch along a building's front (`length` along x, `depth` out along +y, origin at the middle of the wall's foot):
## a concrete slab flush with the ground, posts along the front edge, a sloping sheet roof with its fascia.
static func porch(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 40.0)
	var d: float = g.num("depth", 2.5)
	var h: float = g.num("height", 2.8)
	col(m, "concrete", Color(1, 1, 1))
	m.box_lh(Vector3(-L * 0.5, 0, 0), Vector3(L * 0.5, d, 0.03))
	col(m, "paint_white", Color(0.78, 0.75, 0.68, 0.2))
	var n := maxi(1, int(ceil(L / 3.2)))
	for i in n + 1:
		var x := -L * 0.5 + 0.1 + (L - 0.2) * i / n
		m.box_lh(Vector3(x - 0.05, d - 0.15, 0.03), Vector3(x + 0.05, d - 0.05, h))
		g.solid_box(Vector3(x - 0.06, d - 0.16, 0), Vector3(x + 0.06, d - 0.04, h))
	m.box_lh(Vector3(-L * 0.5, d - 0.2, h - 0.2), Vector3(L * 0.5, d, h))   # the fascia beam
	col(m, "sheeting", Color(0.74, 0.72, 0.68))
	var a := Vector3(-L * 0.5, -0.05, h + 0.25)
	var b := Vector3(L * 0.5, -0.05, h + 0.25)
	m.hexa([a, b, Vector3(L * 0.5, d + 0.15, h - 0.02), Vector3(-L * 0.5, d + 0.15, h - 0.02),
		a + Vector3(0, 0, 0.05), b + Vector3(0, 0, 0.05), Vector3(L * 0.5, d + 0.15, h + 0.03), Vector3(-L * 0.5, d + 0.15, h + 0.03)])

# ------------------------------------------------------------------ interiors

## Interior partitions (`walls` from a to b, relative to the origin; 0.1 m thick plaster on studs), up to `height`, cut
## at their door openings (to the door's height, a lintel over it) and window openings (sill 0.9 m). Every piece is
## solid.
static func room(_part: String, g) -> void:
	var m = g.m
	var h: float = g.num("height", 2.9)
	var openings: Array = g.p.get("openings", [])
	col(m, "matte", PLASTER)
	for w in g.p.get("walls", []):
		var a := Vector2(float(w.a[0]), float(w.a[1]))
		var b := Vector2(float(w.b[0]), float(w.b[1]))
		var L := a.distance_to(b)
		if L < 0.05:
			continue
		var d := (b - a) / L
		var cuts: Array = []   # [t0, t1, z0, z1]
		for o in openings:
			var p := Vector2(float(o.at[0]), float(o.at[1]))
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) > 0.06:
				continue
			var t := (p - a).dot(d)
			var ow := float(o.get("width", 0.9)) * 0.5
			if o.kind == "door":
				cuts.append([t - ow, t + ow, 0.0, float(o.get("height", 2.1))])
			elif o.kind == "door_closed":
				# a room nobody shows (PLANT3D.md §18.5): its door leaf, shut, the wall whole behind it
				var c := a + d * t
				var bs := Basis(Vector3(d.y, -d.x, 0), Vector3(d.x, d.y, 0), Vector3(0, 0, 1))
				col(m, "paint_white", Color(0.55, 0.45, 0.34, 0.3))
				m.box(Vector3(c.x, c.y, float(o.get("height", 2.1)) * 0.5), Vector3(0.16, ow * 2.0, float(o.get("height", 2.1))), bs)
				col(m, "plain_metal", Color(0.75, 0.75, 0.76), "detail", 0.03)
				for sgn: float in [-1.0, 1.0]:
					m.box(Vector3(c.x, c.y, 1.0) + Vector3(d.y, -d.x, 0) * 0.09 * sgn + Vector3(d.x, d.y, 0) * (ow - 0.12), Vector3(0.03, 0.12, 0.03), bs)
				col(m, "matte", PLASTER)
			else:
				cuts.append([t - ow, t + ow, 0.9, 0.9 + float(o.get("height", 1.2))])
		cuts.sort_custom(func(x, y): return x[0] < y[0])
		var t := 0.0
		for c in cuts:
			_wall_piece(m, g, a, d, t, c[0], 0.0, h)
			_wall_piece(m, g, a, d, c[0], c[1], 0.0, c[2])
			_wall_piece(m, g, a, d, c[0], c[1], c[3], h)
			t = c[1]
		_wall_piece(m, g, a, d, t, L, 0.0, h)

static func _wall_piece(m, g, a: Vector2, d: Vector2, t0: float, t1: float, z0: float, z1: float) -> void:
	if t1 - t0 < 0.01 or z1 - z0 < 0.01:
		return
	var c := a + d * ((t0 + t1) * 0.5)
	var bs := Basis(Vector3(d.y, -d.x, 0), Vector3(d.x, d.y, 0), Vector3(0, 0, 1))
	var s := Vector3(0.1, t1 - t0, z1 - z0)
	var cc := Vector3(c.x, c.y, (z0 + z1) * 0.5)
	m.box(cc, s, bs)
	g.solid_obox(cc, s, bs)

## A single bed (`width` across x, `length` along y, its head at -y): a steel frame, the mattress, a blanket and a
## pillow.
static func bed(_part: String, g) -> void:
	var m = g.m
	var w: float = g.num("width", 0.9)
	var L: float = g.num("length", 2.0)
	col(m, "paint_white", Color(0.30, 0.32, 0.34, 0.2))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		m.box_lh(Vector3(c.x * w * 0.5 - 0.03 * (c.x + 1), c.y * L * 0.5 - 0.03 * (c.y + 1), 0),
			Vector3(c.x * w * 0.5 - 0.03 * (c.x - 1), c.y * L * 0.5 - 0.03 * (c.y - 1), 0.42 if c.y > 0 else 0.85))
	m.box_lh(Vector3(-w * 0.5, -L * 0.5, 0.25), Vector3(w * 0.5, L * 0.5, 0.32))
	m.box_lh(Vector3(-w * 0.5, -L * 0.5, 0.55), Vector3(w * 0.5, -L * 0.5 + 0.04, 0.85))   # the headboard
	col(m, "matte", LINEN)
	m.box_lh(Vector3(-w * 0.48, -L * 0.48, 0.32), Vector3(w * 0.48, L * 0.48, 0.5))
	col(m, "matte", BLANKET)
	m.box_lh(Vector3(-w * 0.5, -L * 0.1, 0.48), Vector3(w * 0.5, L * 0.48, 0.53))
	col(m, "matte", LINEN.lightened(0.05))
	m.box_lh(Vector3(-w * 0.35, -L * 0.46, 0.5), Vector3(w * 0.35, -L * 0.3, 0.62))
	g.solid_box(Vector3(-w * 0.5, -L * 0.5, 0), Vector3(w * 0.5, L * 0.5, 0.55))

## A wardrobe or a locker (`width` along x, 0.6 m deep, its doors facing +y).
static func locker(_part: String, g) -> void:
	var m = g.m
	var w: float = g.num("width", 1.0)
	var h: float = g.num("height", 2.0)
	col(m, "paint_white", Color(0.74, 0.74, 0.72, 0.2))
	m.box_lh(Vector3(-w * 0.5, -0.3, 0), Vector3(w * 0.5, 0.3, h))
	var n := maxi(1, int(round(w / 0.5)))
	col(m, "paint_white", Color(0.30, 0.31, 0.32, 0.4), "detail", 0.03)
	for i in n:
		var x := -w * 0.5 + w * (i + 0.5) / n
		m.box(Vector3(x - 0.004, 0.302, h * 0.5), Vector3(0.006, 0.004, h - 0.06))
		m.box(Vector3(x + w * 0.35 / n, 0.31, h * 0.52), Vector3(0.02, 0.02, 0.12))
	g.solid_box(Vector3(-w * 0.5, -0.3, 0), Vector3(w * 0.5, 0.3, h))

## A desk (`width` along x, `depth` along y, the sitter on the -y side), 0.75 m high, with a drawer unit.
static func desk(_part: String, g) -> void:
	var m = g.m
	var w: float = g.num("width", 1.2)
	var d: float = g.num("depth", 0.6)
	col(m, "matte", LAMINATE)
	m.box_lh(Vector3(-w * 0.5, -d * 0.5, 0.72), Vector3(w * 0.5, d * 0.5, 0.75))
	col(m, "paint_white", Color(0.45, 0.46, 0.47, 0.2))
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * w * 0.5 - 0.03 - 0.03 * sx, -d * 0.45, 0), Vector3(sx * w * 0.5 + 0.03 - 0.03 * sx, d * 0.45, 0.72))
	m.box_lh(Vector3(w * 0.5 - 0.45, -d * 0.45, 0.05), Vector3(w * 0.5 - 0.06, d * 0.45, 0.7))
	g.solid_box(Vector3(-w * 0.5, -d * 0.5, 0), Vector3(w * 0.5, d * 0.5, 0.75))

## A chair (facing +y): an office chair on its five-star base, or a dining chair of steel tube and a moulded seat.
static func chair(_part: String, g) -> void:
	var m = g.m
	if String(g.p.get("kind", "dining")) == "office":
		col(m, "paint_white", Color(0.12, 0.12, 0.13, 0.3))
		for k in 5:
			var a := TAU * k / 5.0
			m.cyl(Vector3(0, 0, 0.08), Vector3(cos(a) * 0.3, sin(a) * 0.3, 0.05), 0.02, -1.0, 4, false)
		m.cyl(Vector3(0, 0, 0.08), Vector3(0, 0, 0.42), 0.025, -1.0, 6)
		col(m, "matte", FABRIC)
		m.box_lh(Vector3(-0.24, -0.22, 0.42), Vector3(0.24, 0.24, 0.5))
		m.box_lh(Vector3(-0.22, -0.26, 0.55), Vector3(0.22, -0.2, 1.05))
	else:
		col(m, "paint_white", Color(0.40, 0.41, 0.42, 0.3))
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			m.cyl(Vector3(c.x * 0.2, c.y * 0.2, 0), Vector3(c.x * 0.2, c.y * 0.2, 0.45 if c.y > 0 else 0.9), 0.012, -1.0, 4, false)
		col(m, "matte", Color(0.55, 0.47, 0.37))
		m.box_lh(Vector3(-0.22, -0.22, 0.44), Vector3(0.22, 0.22, 0.47))
		m.box_lh(Vector3(-0.21, -0.23, 0.62), Vector3(0.21, -0.2, 0.88))
	g.solid_box(Vector3(-0.25, -0.25, 0), Vector3(0.25, 0.25, 0.5))

## A table (`length` along y, `width` along x, `height`): a laminate top on four steel legs.
static func table(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 1.8)
	var w: float = g.num("width", 0.9)
	var h: float = g.num("height", 0.75)
	if String(g.p.get("kind", "steel")) == "wood":
		_wood_table(m, g, L, w, h)
		return
	col(m, "matte", LAMINATE.lightened(0.15))
	m.box_lh(Vector3(-w * 0.5, -L * 0.5, h - 0.03), Vector3(w * 0.5, L * 0.5, h))
	col(m, "paint_white", Color(0.40, 0.41, 0.42, 0.3))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := Vector3(c.x * (w * 0.5 - 0.06), c.y * (L * 0.5 - 0.06), 0)
		m.box_lh(p - Vector3(0.02, 0.02, 0), p + Vector3(0.02, 0.02, h - 0.03))
	g.solid_box(Vector3(-w * 0.5, -L * 0.5, 0), Vector3(w * 0.5, L * 0.5, h))

## A wooden side table (`kind` wood: the lobby's): a carved top (an inset panel of a lighter tone), its apron and four
## turned legs, dark varnished hardwood.
const WOOD := Color(0.36, 0.22, 0.13)
static func _wood_table(m, g, L: float, w: float, h: float) -> void:
	col(m, "plain", WOOD)
	m.box_lh(Vector3(-w * 0.5, -L * 0.5, h - 0.04), Vector3(w * 0.5, L * 0.5, h))
	m.box_lh(Vector3(-w * 0.5 + 0.04, -L * 0.5 + 0.04, h - 0.12), Vector3(w * 0.5 - 0.04, L * 0.5 - 0.04, h - 0.04))
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var p := Vector3(c.x * (w * 0.5 - 0.07), c.y * (L * 0.5 - 0.07), 0)
		m.lathe(p, Vector3(0, 0, 1), [[0.025, 0.0], [0.035, 0.12], [0.022, 0.3], [0.04, 0.42], [0.025, 0.55],
			[0.03, h - 0.12]], 6, false)
	col(m, "plain", WOOD.lightened(0.18), "detail", 0.1)
	m.box_lh(Vector3(-w * 0.5 + 0.08, -L * 0.5 + 0.08, h), Vector3(w * 0.5 - 0.08, L * 0.5 - 0.08, h + 0.004))
	g.solid_box(Vector3(-w * 0.5, -L * 0.5, 0), Vector3(w * 0.5, L * 0.5, h))

## A bench (`length` along x): an outdoor or gym bench, slats on two steel frames.
static func bench(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 2.0)
	col(m, "matte", Color(0.50, 0.40, 0.30))
	for k in 3:
		m.box_lh(Vector3(-L * 0.5, -0.2 + k * 0.14, 0.42), Vector3(L * 0.5, -0.09 + k * 0.14, 0.46))
	col(m, "paint_white", Color(0.25, 0.26, 0.27, 0.3))
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * (L * 0.5 - 0.2) - 0.03, -0.2, 0), Vector3(sx * (L * 0.5 - 0.2) + 0.03, 0.2, 0.42))
	g.solid_box(Vector3(-L * 0.5, -0.2, 0), Vector3(L * 0.5, 0.2, 0.46))

## A counter (`length` along x, `depth` along y, its front at +y), 0.9 m high: a serving counter with its sneeze
## guard, a kitchen worktop, a range (its hobs and hood), a sink, a washbasin vanity, a reception desk or a workbench
## (the workshops' and the calibration bench).
static func counter(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 3.0)
	var d: float = g.num("depth", 0.7)
	var kind := String(g.p.get("kind", "kitchen"))
	var top := 0.9 if kind != "workbench" else 0.85
	var body := Color(0.80, 0.80, 0.78, 0.15) if kind in ["kitchen", "range", "sink", "serving"] else Color(0.62, 0.55, 0.45, 0.15)
	if kind == "workbench":
		col(m, "paint_white", Color(0.24, 0.36, 0.50, 0.4))
		for sx: float in [-1.0, 1.0]:
			m.box_lh(Vector3(sx * (L * 0.5 - 0.05) - 0.04, -d * 0.45, 0), Vector3(sx * (L * 0.5 - 0.05) + 0.04, d * 0.45, top - 0.05))
		m.box_lh(Vector3(-L * 0.5, -d * 0.5, 0.15), Vector3(L * 0.5, d * 0.5, 0.18))
		col(m, "matte", Color(0.56, 0.44, 0.30))
		m.box_lh(Vector3(-L * 0.5, -d * 0.5, top - 0.05), Vector3(L * 0.5, d * 0.5, top))
		col(m, "paint_white", Color(0.30, 0.42, 0.55, 0.4))
		m.box_lh(Vector3(-L * 0.5, -d * 0.5, top), Vector3(L * 0.5, -d * 0.5 + 0.03, top + 0.9))   # a tool board
		col(m, "paint_white", Color(0.75, 0.40, 0.08, 0.3), "detail", 0.15)
		for k in int(L / 0.6):
			m.box(Vector3(-L * 0.5 + 0.3 + k * 0.6, -d * 0.5 + 0.15, top + 0.08), Vector3(0.3, 0.2, 0.16))
	else:
		col(m, "paint_white", body)
		m.box_lh(Vector3(-L * 0.5, -d * 0.5, 0), Vector3(L * 0.5, d * 0.5, top - 0.04))
		col(m, "chrome" if kind in ["kitchen", "range", "sink", "serving"] else "matte",
			Color(0.80, 0.81, 0.83) if kind in ["kitchen", "range", "sink", "serving"] else LAMINATE.lightened(0.2))
		m.box_lh(Vector3(-L * 0.5, -d * 0.5, top - 0.04), Vector3(L * 0.5, d * 0.5, top))
	match kind:
		"serving":
			col(m, "glass", Color(0.55, 0.62, 0.64))
			m.box_lh(Vector3(-L * 0.5, d * 0.1, top + 0.35), Vector3(L * 0.5, d * 0.45, top + 0.37))
			col(m, "chrome", Color(0.80, 0.81, 0.83))
			for k in int(L / 1.0) + 1:
				var x := -L * 0.5 + L * k / maxf(1.0, float(int(L / 1.0)))
				m.cyl(Vector3(x, d * 0.3, top), Vector3(x, d * 0.3, top + 0.37), 0.012, -1.0, 6)
			col(m, "dark", Color(0.03, 0.03, 0.03))
			for k in int(L / 0.6):
				m.box_lh(Vector3(-L * 0.5 + 0.1 + k * 0.6, -d * 0.4, top - 0.01), Vector3(-L * 0.5 + 0.6 + k * 0.6, d * 0.0, top + 0.005))
		"range":
			col(m, "dark", Color(0.03, 0.03, 0.03))
			for k in int(L / 0.45):
				m.disk(Vector3(-L * 0.5 + 0.25 + k * 0.45, -d * 0.1, top + 0.005), Vector3(0, 0, 1), 0.15, 12)
			col(m, "chrome", Color(0.70, 0.71, 0.73))
			m.hexa([Vector3(-L * 0.5, -d * 0.5, 1.9), Vector3(L * 0.5, -d * 0.5, 1.9), Vector3(L * 0.5, d * 0.5, 1.9),
				Vector3(-L * 0.5, d * 0.5, 1.9), Vector3(-L * 0.4, -d * 0.5, 2.3), Vector3(L * 0.4, -d * 0.5, 2.3),
				Vector3(L * 0.4, d * 0.0, 2.3), Vector3(-L * 0.4, d * 0.0, 2.3)])
		"sink":
			col(m, "dark", Color(0.12, 0.12, 0.13))
			for k in maxi(1, int(L / 0.9)):
				m.box_lh(Vector3(-L * 0.5 + 0.15 + k * 0.9, -d * 0.3, top - 0.005), Vector3(-L * 0.5 + 0.75 + k * 0.9, d * 0.3, top + 0.002))
		"basin":
			col(m, "plain", CERAMIC)
			for k in maxi(1, int(L / 0.8)):
				m.cyl(Vector3(-L * 0.5 + 0.4 + k * 0.8, 0, top - 0.1), Vector3(-L * 0.5 + 0.4 + k * 0.8, 0, top + 0.02), 0.2, 0.22, 12)
			col(m, "plain_metal", Color(0.8, 0.8, 0.82))
			m.box_lh(Vector3(-L * 0.5, -d * 0.5, top + 0.2), Vector3(L * 0.5, -d * 0.5 + 0.01, top + 0.9))   # the mirror
	g.solid_box(Vector3(-L * 0.5, -d * 0.5, 0), Vector3(L * 0.5, d * 0.5, top))

## Shelving (`length` along x, 0.4 m deep): a store's steel shelves with boxes, or a prayer room's shoe rack.
static func shelf(_part: String, g) -> void:
	var m = g.m
	var L: float = g.num("length", 1.2)
	var h: float = g.num("height", 1.8)
	var shoes := String(g.p.get("kind", "store")) == "shoes"
	var dep := 0.35 if shoes else 0.45
	_shelf_mat(m, shoes)
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * L * 0.5 - 0.02 - 0.02 * sx, -dep * 0.5, 0), Vector3(sx * L * 0.5 + 0.02 - 0.02 * sx, dep * 0.5, h))
	var n := maxi(2, int(h / (0.3 if shoes else 0.45)))
	var rng := _rng(g, 7)
	for k in n:
		var z := 0.06 + (h - 0.08) * k / (n - 1)
		_shelf_mat(m, shoes)
		m.box_lh(Vector3(-L * 0.5, -dep * 0.5, z - 0.02), Vector3(L * 0.5, dep * 0.5, z))
		if k < n - 1:
			var x := -L * 0.5 + 0.08
			while x < L * 0.5 - 0.25:
				var bw := rng.randf_range(0.18, 0.4) if not shoes else 0.28
				if rng.randf() < 0.8:
					col(m, "matte", Color(rng.randf_range(0.2, 0.6), rng.randf_range(0.2, 0.5), rng.randf_range(0.15, 0.45)) if shoes else Color(0.66, 0.55, 0.40), "detail", 0.1)
					m.box_lh(Vector3(x, -dep * 0.4, z), Vector3(minf(x + bw - 0.04, L * 0.5 - 0.04), dep * 0.35, z + (0.1 if shoes else 0.3)))
				x += bw
	g.solid_box(Vector3(-L * 0.5, -dep * 0.5, 0), Vector3(L * 0.5, dep * 0.5, h))

static func _shelf_mat(m, shoes: bool) -> void:
	if shoes:
		col(m, "matte", LAMINATE)
	else:
		col(m, "galvanised", Color(0.85, 0.87, 0.88))

## A washing machine or a tumble dryer (0.6 m square, its door facing +y).
static func washer(_part: String, g) -> void:
	var m = g.m
	col(m, "plain", CERAMIC)
	m.box_lh(Vector3(-0.3, -0.3, 0), Vector3(0.3, 0.3, 0.85))
	col(m, "glass", Color(0.18, 0.2, 0.22))
	m.cyl(Vector3(0, 0.3, 0.42), Vector3(0, 0.33, 0.42), 0.17, 0.15, 14)
	col(m, "plain", Color(0.30, 0.32, 0.34), "detail", 0.05)
	m.box(Vector3(0, 0.305, 0.78), Vector3(0.5, 0.01, 0.08))
	g.solid_box(Vector3(-0.3, -0.3, 0), Vector3(0.3, 0.3, 0.85))

## Gym equipment (facing +y): a rack of dumbbells, a treadmill, an exercise bike or a weight bench.
static func gym_rack(_part: String, g) -> void:
	var m = g.m
	var kind := String(g.p.get("kind", "weights"))
	match kind:
		"weights":
			col(m, "paint_white", Color(0.12, 0.12, 0.13, 0.4))
			for sx: float in [-1.0, 1.0]:
				m.box_lh(Vector3(sx * 0.8 - 0.04, -0.3, 0), Vector3(sx * 0.8 + 0.04, 0.3, 0.9))
			for z: float in [0.35, 0.7]:
				m.box_lh(Vector3(-0.8, -0.25, z - 0.03), Vector3(0.8, 0.25, z))
				col(m, "steel_dark", Color(0.45, 0.45, 0.47))
				for k in 7:
					var x := -0.66 + k * 0.22
					m.cyl(Vector3(x - 0.06, 0, z + 0.07), Vector3(x + 0.06, 0, z + 0.07), 0.06, -1.0, 8)
				col(m, "paint_white", Color(0.12, 0.12, 0.13, 0.4))
			g.solid_box(Vector3(-0.85, -0.3, 0), Vector3(0.85, 0.3, 0.9))
		"treadmill":
			col(m, "rubber", Color(0.06, 0.06, 0.06))
			m.box_lh(Vector3(-0.4, -0.9, 0), Vector3(0.4, 0.9, 0.22))
			col(m, "paint_white", Color(0.20, 0.21, 0.22, 0.3))
			for sx: float in [-1.0, 1.0]:
				m.box_lh(Vector3(sx * 0.38 - 0.03, 0.7, 0.2), Vector3(sx * 0.38 + 0.03, 0.8, 1.3))
			m.box_lh(Vector3(-0.42, 0.65, 1.2), Vector3(0.42, 0.85, 1.4))
			g.solid_box(Vector3(-0.42, -0.9, 0), Vector3(0.42, 0.9, 1.4))
		"bike":
			col(m, "paint_white", Color(0.20, 0.21, 0.22, 0.3))
			m.box_lh(Vector3(-0.2, -0.5, 0), Vector3(0.2, 0.5, 0.06))
			m.cyl(Vector3(0, -0.2, 0.06), Vector3(0, -0.25, 0.95), 0.04, -1.0, 6)
			m.cyl(Vector3(0, 0.35, 0.06), Vector3(0, 0.3, 1.15), 0.04, -1.0, 6)
			m.cyl(Vector3(0, 0.2, 0.45), Vector3(0, 0.2, 0.45), 0.2, -1.0, 12)
			col(m, "matte", Color(0.12, 0.12, 0.13))
			m.box_lh(Vector3(-0.12, -0.38, 0.95), Vector3(0.12, -0.12, 1.02))
			m.box_lh(Vector3(-0.25, 0.25, 1.12), Vector3(0.25, 0.35, 1.18))
			g.solid_box(Vector3(-0.25, -0.5, 0), Vector3(0.25, 0.5, 1.15))
		_:
			col(m, "paint_white", Color(0.20, 0.21, 0.22, 0.3))
			m.box_lh(Vector3(-0.05, -0.6, 0), Vector3(0.05, 0.6, 0.38))
			col(m, "matte", Color(0.12, 0.12, 0.13))
			m.box_lh(Vector3(-0.15, -0.6, 0.38), Vector3(0.15, 0.6, 0.46))
			col(m, "paint_white", Color(0.20, 0.21, 0.22, 0.3))
			for sx: float in [-1.0, 1.0]:
				m.box_lh(Vector3(sx * 0.55 - 0.03, -0.75, 0), Vector3(sx * 0.55 + 0.03, -0.65, 1.2))
			col(m, "chrome", Color(0.80, 0.81, 0.83))
			m.cyl(Vector3(-0.8, -0.7, 1.1), Vector3(0.8, -0.7, 1.1), 0.015, -1.0, 6)
			g.solid_box(Vector3(-0.6, -0.75, 0), Vector3(0.6, 0.6, 0.5))

const LEATHER := Color(0.36, 0.24, 0.16)
## A sofa (`seats` wide, facing +y): its base, seat and back cushions and arms.
static func sofa(_part: String, g) -> void:
	var m = g.m
	var w := 0.65 * int(g.num("seats", 3)) + 0.3
	if String(g.p.get("cover", "fabric")) == "leather":
		col(m, "plain", LEATHER)   # brown leather, satin (the lobby's)
	else:
		col(m, "matte", FABRIC.lightened(0.1))
	m.box_lh(Vector3(-w * 0.5, -0.45, 0.1), Vector3(w * 0.5, 0.45, 0.42))
	m.box_lh(Vector3(-w * 0.5, -0.45, 0.42), Vector3(w * 0.5, -0.22, 0.85))
	for sx: float in [-1.0, 1.0]:
		m.box_lh(Vector3(sx * w * 0.5 - 0.15 - 0.15 * sx, -0.45, 0.42), Vector3(sx * w * 0.5 + 0.15 - 0.15 * sx, 0.45, 0.62))
	col(m, "paint_white", Color(0.12, 0.12, 0.13, 0.2))
	m.box_lh(Vector3(-w * 0.5 + 0.05, -0.4, 0), Vector3(w * 0.5 - 0.05, 0.4, 0.1))
	g.solid_box(Vector3(-w * 0.5, -0.45, 0), Vector3(w * 0.5, 0.45, 0.85))

## A wall screen (a television or a display), `size` across its diagonal, its centre `mount` metres up, facing +y
## from the wall at the origin.
static func screen(_part: String, g) -> void:
	var m = g.m
	var s: float = g.num("size", 1.4)
	var z: float = g.num("mount", 1.5)
	var w := s * 0.87
	var h := s * 0.49
	col(m, "plain", Color(0.05, 0.05, 0.06))
	m.box_lh(Vector3(-w * 0.5, 0.02, z - h * 0.5), Vector3(w * 0.5, 0.07, z + h * 0.5))
	col(m, "glass", Color(0.08, 0.10, 0.12))
	m.box_lh(Vector3(-w * 0.48, 0.07, z - h * 0.47), Vector3(w * 0.48, 0.075, z + h * 0.47))

## A carpet laid over a floor's `outline` (relative to the origin), 1 cm thick, in a plain colour with a border.
static func carpet(_part: String, g) -> void:
	var m = g.m
	var c: Color = CARPET.get(String(g.p.get("colour", "green")), CARPET.green)
	var pts: Array = []
	for q in g.p.get("outline", []):
		pts.append(Vector3(float(q[0]), float(q[1]), 0.02))   # 2 cm on the floor: nearer, they fight (tests/test_ground.gd)
	if pts.size() < 3:
		return
	col(m, "matte", c)
	m.poly(pts, Vector3(0, 0, 1))
	if not g.p.get("rows", true):
		return   # an office's carpet: plain
	# the prayer rows: a band every 1.2 m across the room (lighter), in the carpet's own geometry
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	col(m, "matte", c.lightened(0.18))
	var y := lo.y + 1.2
	while y < hi.y - 0.2:
		m.box_lh(Vector3(lo.x + 0.15, y - 0.04, 0.02), Vector3(hi.x - 0.15, y + 0.04, 0.04))
		y += 1.2

## Sanitary ware: a WC, a shower tray with its glass screen, a washbasin, or an ablution row (a bench, taps and a
## channel along a wall), facing +y from the wall at the origin.
static func sanitary(_part: String, g) -> void:
	var m = g.m
	match String(g.p.get("kind", "wc")):
		"wc":
			col(m, "plain", CERAMIC)
			m.cyl(Vector3(0, 0.35, 0), Vector3(0, 0.38, 0.42), 0.2, 0.22, 12)
			m.box_lh(Vector3(-0.2, 0.02, 0.4), Vector3(0.2, 0.2, 0.85))
			g.solid_box(Vector3(-0.22, 0.0, 0), Vector3(0.22, 0.6, 0.45))
		"shower":
			col(m, "plain", CERAMIC)
			m.box_lh(Vector3(-0.45, 0.0, 0), Vector3(0.45, 0.9, 0.05))
			col(m, "plain_metal", Color(0.8, 0.8, 0.82))
			m.cyl(Vector3(0, 0.03, 1.2), Vector3(0, 0.03, 2.0), 0.012, -1.0, 6)
			m.cyl(Vector3(0, 0.03, 2.0), Vector3(0, 0.2, 2.05), 0.06, -1.0, 8)
			col(m, "glass", Color(0.55, 0.62, 0.64))
			m.box_lh(Vector3(0.44, 0.0, 0.05), Vector3(0.46, 0.9, 2.0))
			g.solid_box(Vector3(0.43, 0.0, 0), Vector3(0.47, 0.9, 2.0))
		"basin":
			col(m, "plain", CERAMIC)
			m.cyl(Vector3(0, 0.25, 0.65), Vector3(0, 0.25, 0.85), 0.18, 0.24, 12)
			m.cyl(Vector3(0, 0.15, 0), Vector3(0, 0.15, 0.65), 0.08, -1.0, 8)
			g.solid_box(Vector3(-0.25, 0.0, 0), Vector3(0.25, 0.5, 0.85))
		_:
			# an ablution row: a low bench to sit on, a tiled upstand with taps, a drain channel
			col(m, "plain", CERAMIC.darkened(0.08))
			m.box_lh(Vector3(-1.5, 0.0, 0), Vector3(1.5, 0.25, 0.9))
			col(m, "dark", Color(0.1, 0.1, 0.1))
			m.box_lh(Vector3(-1.5, 0.25, 0.0), Vector3(1.5, 0.45, 0.02))
			col(m, "plain", CERAMIC)
			m.box_lh(Vector3(-1.5, 0.75, 0), Vector3(1.5, 1.05, 0.35))
			col(m, "plain_metal", Color(0.8, 0.8, 0.82), "detail", 0.04)
			for k in 5:
				m.cyl(Vector3(-1.2 + k * 0.6, 0.2, 0.75), Vector3(-1.2 + k * 0.6, 0.32, 0.72), 0.015, -1.0, 6)
			g.solid_box(Vector3(-1.5, 0.0, 0), Vector3(1.5, 0.25, 0.9))
			g.solid_box(Vector3(-1.5, 0.75, 0), Vector3(1.5, 1.05, 0.35))
