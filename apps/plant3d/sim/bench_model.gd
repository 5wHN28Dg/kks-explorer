extends "plant_model.gd"
## A Workshop bench model (docs/plant3d/WORKSHOP.md §6, milestone K3), read into the shape plant_model.gd gives, so
## sim/engine.gd steps it unchanged: the bench file's `at` (a component of the kind's Workshop tree, or `bench`) is
## written into the engine's `kks` field of its ops, machines, trips, alarms, interlocks, faults and show bindings,
## so the engine finds an op by (at, do, trip) exactly as a plant op by (kks, do, trip). Its one scenario, `bench`,
## is the file's `start` with its faults (the trainer's, pressed from the bench panel).
##
## Not the validator (ref/plant3d_bench.py is, and the content build runs it): the loader refuses what it can't run
## (not strict JSON, another format, an `at` that is no component, a name no value has) and says where.
##
##   var m := BenchModel.from_text(text, ["manifold", "process_flange", …])
##   if m.error != "": …
##   var e := Engine.new(m, "bench")
##
## Besides the model: `units` (value -> unit), `readouts`, `binds` (the bench's bindings as written, with `at`),
## `legends`, `faults` (the trainer's: id, text, at), `ops_ui` (each op as written: at, do, title, input, range),
## `mirror` (the live mirror's entries, §6.5).

const FORMAT := "walkdown-plant-bench"
const AT_BENCH := "bench"
const SCENARIO := "bench"       # the one scenario: the file's start and its faults

var part := ""
var units := {}
var readouts: Array = []
var binds: Array = []
var legends := {}
var faults: Array = []
var ops_ui: Array = []
var mirror: Array = []          # the live mirror's entries as written (WORKSHOP.md §6.5; workshop/mirror.gd)


static func from_text(text: String, comps: Array):
	var m = new()
	var r: Dictionary = JsonStrict.parse_text(text)
	if not r.ok:
		m._fail("bench: not strict JSON (%s)" % r.error)
		return m
	if typeof(r.value) != TYPE_DICTIONARY:
		m._fail("bench: not an object")
		return m
	m._load_bench(r.value, comps)
	return m


func _at(x: Dictionary, where: String, codes: Dictionary) -> Dictionary:
	var y := x.duplicate(true)
	if y.has("at"):
		if not codes.has(y["at"]):
			_fail("%s: no component %s" % [where, str(y["at"])])
		y["kks"] = y["at"]
		y.erase("at")
	return y


func _load_bench(d: Dictionary, comps: Array) -> void:
	if d.get("format") != FORMAT or d.get("version") != 1:
		_fail("bench: not %s version 1" % FORMAT)
		return
	part = str(d.get("part", ""))
	version = 2                 # format 2's hold (§15.4) and the trainer's events; nothing else of format 2 is here
	plant = {}
	var codes := {AT_BENCH: true}
	for c in comps:
		codes[c] = true
	var model := {"area": AT_BENCH, "values": d.get("values", [])}
	for v in d.get("values", []):
		if typeof(v[1]) == TYPE_DICTIONARY and v[1].has("unit"):
			units[v[0]] = v[1]["unit"]
	var ops := []
	for o in d.get("ops", []):
		ops_ui.append(o)
		var y := _at(o, "op", codes)
		y.erase("title")
		y["where"] = ["local"]
		ops.append(y)
	model["ops"] = ops
	for k in ["machines", "trips", "alarms", "interlocks"]:
		var out := []
		for x in d.get(k, []):
			out.append(_at(x, k, codes))
		model[k] = out
	_add_model(model, "bench")
	if error != "":
		return
	for x in d.get("bind", []):
		binds.append(x)
		if x.has("at") and not codes.has(x["at"]):
			_fail("binding: no component %s" % str(x["at"]))
		if x.has("show"):
			bind.append({"kks": x["at"], "show": x["show"]})
		for k in ["of", "show", "lit", "by", "heat", "pressure"]:
			if x.has(k):
				_need(x[k], "binding")
	var fl := []
	for f in d.get("faults", []):
		var y := _at(f, "fault " + str(f.get("id")), codes)
		fl.append(y)
		faults.append({"id": f["id"], "text": f["text"], "at": f.get("at", ""), "repair": f.has("repair")})
		_check_set(y.get("set", {}), "fault " + str(f["id"]))
		_check_set(y.get("repair", {}), "fault " + str(f["id"]))
	for k in d.get("readouts", []):
		_need(k, "readout")
		readouts.append(k)
	legends = d.get("legends", {})
	for x in d.get("mirror", []):
		if typeof(x) != TYPE_DICTIONARY or typeof(x.get("from")) != TYPE_DICTIONARY or typeof(x.get("value")) != TYPE_STRING:
			_fail("mirror: an entry is {value, from}")
			return
		mirror.append(x)
	var start: Dictionary = d.get("start", {})
	for k in start:
		if not index.has(k):
			_fail("start: no value %s" % k)
	_finish()
	if _reads_world or _reads_wx:
		_fail("bench: a bench has no clock values")
	scenarios[SCENARIO] = {"id": SCENARIO, "title": "The bench", "init": start, "faults": fl}


## A legend's colour at x ({unit, table: [[x, "#rrggbb"], …]}, piecewise linear, held at the ends).
static func legend_colour(lg: Dictionary, x: float) -> Color:
	var t: Array = lg.get("table", [])
	if t.is_empty():
		return Color.WHITE
	if x <= float(t[0][0]):
		return Color(String(t[0][1]))
	for i in range(1, t.size()):
		if x <= float(t[i][0]):
			var f := (x - float(t[i - 1][0])) / maxf(float(t[i][0]) - float(t[i - 1][0]), 1e-9)
			return Color(String(t[i - 1][1])).lerp(Color(String(t[i][1])), f)
	return Color(String(t[t.size() - 1][1]))
