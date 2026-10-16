extends RefCounted
## The behaviour model's engine (docs/PLANT3D.md §7): steps the joined model of a plant exactly as §7.10 says, with
## the same double-precision arithmetic as the reference (ref/plant3d.py Engine), so the two agree bit for bit on
## ref/vectors/plant3d-v1.json (apps/plant3d/sim/tests).
##
## Trainee inputs are queued and take effect in step 1 of the next step, in the order made:
##   op(kks, do, value, trip), ack(alarm), shelve(alarm, seconds), unshelve(alarm), fault(id)
## (fault: a scenario fault without `when`, pressed by the trainer; applied in step 3). Every input is also kept in
## `inputs` as [the step it takes effect in, kind, …], the vectors' input form.
##
## Arithmetic notes (what makes it bit-exact, each mirrored from the reference):
## - every value is a float (IEEE 754 double); content numbers are read correctly rounded (json_strict.gd);
## - sum and product fold left from 0.0 and 1.0; min and max keep the first of equal values (Python's min/max), so
##   -0.0 and 0.0 come out as the reference's; a lag's factor 1 − exp(−0.1/τ) and a ramp's rate × 0.1 are computed
##   once per node;
## - a time t counts floor(t / 0.1 + 0.5) steps; a timer is count / 10.0.

const PlantModel = preload("plant_model.gd")

const STEP := 0.1

enum {K_CONST, K_OF, K_SUM, K_PRODUCT, K_MIN, K_MAX, K_AND, K_OR, K_DIFF, K_SELECT, K_GE, K_GT, K_LE, K_LT, K_NOT,
		K_LAG, K_RAMP, K_INTEGRATE, K_LATCH, K_DELAY, K_TIMER, K_WRAP}
const FIRST_STATEFUL := K_LAG

var m                               # PlantModel
var sc: Dictionary                  # the scenario
var names: PackedStringArray        # every value: declared, ext, <machine>_state, <trip>_latched
var ix := {}                        # name -> slot
var n := 0                          # value slots; constants follow them in cur and prev

# the compiled program (shared by clones: never changed after _compile)
var _prog_kind := PackedInt32Array()
var _prog_out := PackedInt32Array()
var _prog_a := PackedInt32Array()       # start in _ia
var _prog_na := PackedInt32Array()
var _prog_f := PackedInt32Array()       # start in _fa
var _ia := PackedInt32Array()           # refs (slots) and integer arguments
var _fa := PackedFloat64Array()         # float arguments (tables, factors)
var _nprog := 0
var _init_vals := PackedFloat64Array()
var _nmem := 0
var _fault_node := {}                   # fault id -> program entry of its `when` node (evaluated on its own)

# compiled conditions and actions
var _il: Array = []          # [id, when slot, actions]
var _mc: Array = []          # [id, state slot, ids, states: [[set, next: [[slot, to]...], watch]...], commands]
var _mc_ix := {}             # machine id -> position
var _tr: Array = []          # [id, when slot, count needed, group, actions, latched slot]
var _tr_ix := {}
var _al: Array = []          # [id, when slot, clear slot or -1, suppress slot or -1, count needed, priority]
var _al_ix := {}
var _faults: Array = []      # [id, kind 0 name / 1 node / 2 trainer, slot or node, set]
var _ops := {}               # op key -> compiled op

# the state (copied by clone)
var cur := PackedFloat64Array()
var prev := PackedFloat64Array()
var mem := PackedInt64Array()
var mstate := PackedInt32Array()
var latched := PackedByteArray()
var trip_count := PackedInt64Array()
var first_out := {}
var astate: Array = []       # per alarm: "normal", "active_unack", "active_ack", "cleared_unack"
var acount := PackedInt64Array()
var shelved := PackedInt64Array()   # per alarm: the step its shelf ends, -1 when not shelved
var il_prev := PackedByteArray()
var faults_done := {}
var queue: Array = []
var events: Array = []
var inputs: Array = []
var step_no := 0


func _init(model = null, scenario = null) -> void:
	if model == null:
		return          # clone() fills the rest
	m = model
	sc = m.scenarios[scenario] if typeof(scenario) == TYPE_STRING else scenario
	for v in m.values:
		names.append(v[0])
	for e in m.ext:
		names.append(e)
	for mc in m.machines:
		names.append(mc["id"] + "_state")
	for t in m.trips:
		names.append(t["id"] + "_latched")
	n = names.size()
	for i in n:
		ix[names[i]] = i
	_compile()
	_step0()


# ---------------------------------------------------------------- compiling

var _consts: Array = []


func _ref(r) -> int:
	if typeof(r) == TYPE_STRING:
		return ix[r]
	_consts.append(float(r))
	return n + _consts.size() - 1


static func steps(t) -> int:
	return floori(float(t) / STEP + 0.5)


func _emit(kind: int, out: int, refs: Array, fargs: Array) -> int:
	_prog_kind.append(kind)
	_prog_out.append(out)
	_prog_a.append(_ia.size())
	_prog_na.append(refs.size())
	_prog_f.append(_fa.size())
	_ia.append_array(PackedInt32Array(refs))
	_fa.append_array(PackedFloat64Array(fargs))
	return _prog_kind.size() - 1


## One node; returns its program entry, or -1 for a state (it has none).
func _node(i: int, nd: Dictionary, kind: String) -> int:
	match kind:
		"const":
			return _emit(K_CONST, i, [], [float(nd["const"])])
		"state":
			return -1
		"of":
			var fl := []
			for row in nd["table"]:
				fl.append(float(row[0]))
				fl.append(float(row[1]))
			var st := 1 if nd.get("step", false) else 0
			return _emit(K_OF, i, [_ref(nd["of"]), nd["table"].size(), st], fl)
		"sum", "product", "min", "max", "and", "or":
			var refs := []
			for r in nd[kind]:
				refs.append(_ref(r))
			var k: int = {"sum": K_SUM, "product": K_PRODUCT, "min": K_MIN, "max": K_MAX, "and": K_AND, "or": K_OR}[kind]
			return _emit(k, i, refs, [])
		"diff":
			return _emit(K_DIFF, i, [_ref(nd["diff"][0]), _ref(nd["diff"][1])], [])
		"select":
			var refs := [_ref(nd["select"])]
			for r in nd["cases"]:
				refs.append(_ref(r))
			return _emit(K_SELECT, i, refs, [])
		"cmp":
			var k: int = {">=": K_GE, ">": K_GT, "<=": K_LE, "<": K_LT}[nd["cmp"][1]]
			return _emit(k, i, [_ref(nd["cmp"][0]), _ref(nd["cmp"][2])], [])
		"not":
			return _emit(K_NOT, i, [_ref(nd["not"])], [])
		"lag":
			var up := 1 - exp(-STEP / float(nd["tau"]))
			var dn := 1 - exp(-STEP / float(nd.get("tau_down", nd["tau"])))
			return _emit(K_LAG, i, [_ref(nd["lag"])], [up, dn])
		"ramp":
			var ru := float(nd["rate"]) * STEP
			var rd := float(nd.get("rate_down", nd["rate"])) * STEP
			return _emit(K_RAMP, i, [_ref(nd["ramp"])], [ru, rd])
		"integrate":
			return _emit(K_INTEGRATE, i, [_ref(nd["integrate"])],
					[float(nd["gain"]), float(nd["min"]), float(nd["max"])])
		"latch":
			return _emit(K_LATCH, i, [_ref(nd["latch"]), _ref(nd["reset"])], [])
		"delay":
			var slot := _nmem
			_nmem += 2
			return _emit(K_DELAY, i, [_ref(nd["delay"]), steps(nd["on"]), steps(nd.get("off", 0)), slot], [])
		"timer":
			var slot := _nmem
			_nmem += 1
			return _emit(K_TIMER, i, [_ref(nd["timer"]), slot], [])
		"wrap":
			return _emit(K_WRAP, i, [_ref(nd["wrap"])], [float(nd["period"])])
	push_error("engine: unknown node kind " + kind)
	return -1


func _sets(s: Dictionary) -> Array:
	var slots := PackedInt32Array()
	var vals := PackedFloat64Array()
	for k in s:
		slots.append(ix[k])
		vals.append(float(s[k]))
	return [slots, vals]


func _actions(acts: Array) -> Array:
	var out := []
	for a in acts:
		if a.has("set"):
			out.append([0, _sets(a["set"])])
		else:
			var mi: int = _mc_ix[a["machine"]]
			out.append([1, mi, _mc[mi][2].find(a["to"])])
	return out


func _compile() -> void:
	_init_vals.resize(n)
	for i in m.values.size():
		var v = m.values[i]
		var kind: String = v[2]
		if kind == "state":
			_init_vals[i] = float(v[1]["state"])
		elif PlantModel.STATEFUL.has(kind):
			_init_vals[i] = float(v[1].get("init", 0))
		_node(i, v[1], kind)
	_nprog = _prog_kind.size()
	for k in m.machines.size():
		var mc = m.machines[k]
		_mc_ix[mc["id"]] = k
	for k in m.machines.size():
		var mc = m.machines[k]
		var states := []
		for s in mc["states"]:
			var nexts := []
			for nx in s.get("next", []):
				nexts.append([ix[nx[0]], mc["_ids"].find(nx[1])])
			states.append([_sets(s.get("set", {})), nexts, s.get("watch", true)])
		_mc.append([mc["id"], ix[mc["id"] + "_state"], mc["_ids"], states, mc["commands"]])
	for x in m.interlocks:
		_il.append([x["id"], ix[x["when"]], _actions(x["do"])])
	for k in m.trips.size():
		var t = m.trips[k]
		_tr_ix[t["id"]] = k
		var g = t.get("first_out")
		_tr.append([t["id"], ix[t["when"]], maxi(1, steps(t.get("delay", 0))), g if g != null else "",
				_actions(t["do"]), ix[t["id"] + "_latched"]])
	for k in m.alarms.size():
		var a = m.alarms[k]
		_al_ix[a["id"]] = k
		_al.append([a["id"], ix[a["when"]], ix[a["clear"]] if a.has("clear") else -1,
				ix[a["suppress"]] if a.has("suppress") else -1, maxi(1, steps(a.get("delay", 0))), a["priority"]])
	for f in sc.get("faults", []):
		var fs := _sets(f["set"])
		if not f.has("when"):
			_faults.append([f["id"], 2, -1, fs])
		elif typeof(f["when"]) == TYPE_STRING:
			_faults.append([f["id"], 0, ix[f["when"]], fs])
		else:
			var kind := PlantModel.node_kind(f["when"])
			_faults.append([f["id"], 1, _node(-1, f["when"], kind), fs])
	for key in m.op_keys:
		var o = m.op_keys[key]
		var needs := PackedInt32Array()
		var need_names := []
		for nd in o.get("needs", []):
			needs.append(ix[nd[0]])
			need_names.append(nd[0])
		var c := {"o": o, "needs": needs, "need_names": need_names, "set": _sets(o.get("set", {})), "mi": -1}
		if o.has("machine"):
			c["mi"] = _mc_ix[o["machine"]]
		elif o["do"] == "reset":
			c["ti"] = _tr_ix[o["trip"]]
		elif o["do"] == "set":
			c["input"] = ix[o["input"]]
		_ops[key] = c
	# the constants live after the values, in cur and prev alike
	_init_vals.append_array(PackedFloat64Array(_consts))
	mem.resize(_nmem)


# ---------------------------------------------------------------- step 0 (§7.1)

func _step0() -> void:
	cur = _init_vals.duplicate()
	mstate.resize(_mc.size())
	for k in _mc.size():
		var mc = _mc[k]
		var si: int = mc[2].find(m.machines[k]["init"])
		mstate[k] = si
		cur[mc[1]] = float(si)
		_apply_set(mc[3][si][0])
	var init: Dictionary = sc["init"]
	for k in init:
		cur[ix[k]] = float(init[k])
	latched.resize(_tr.size())
	trip_count.resize(_tr.size())
	for t in sc.get("latched", []):
		var ti: int = _tr_ix[t]
		latched[ti] = 1
		cur[_tr[ti][5]] = 1.0
	astate.resize(_al.size())
	astate.fill("normal")
	acount.resize(_al.size())
	shelved.resize(_al.size())
	shelved.fill(-1)
	il_prev.resize(_il.size())
	prev = cur.duplicate()
	for p in _nprog:
		if _prog_kind[p] < FIRST_STATEFUL:
			cur[_prog_out[p]] = _stateless(p, cur)


# ---------------------------------------------------------------- trainee inputs

func _q(item: Array) -> void:
	inputs.append([step_no + 1] + item)
	queue.append(item)


func op(kks, do, value = null, trip = null) -> void:
	_q(["op", kks, do, value, trip])


func ack(alarm) -> void:
	_q(["ack", alarm])


func shelve(alarm, seconds) -> void:
	_q(["shelve", alarm, seconds])


func unshelve(alarm) -> void:
	_q(["unshelve", alarm])


func fault(fid) -> void:
	_q(["fault", fid])


## Queues an input in the vectors' form [step, kind, …] (the step is not checked here).
func apply_input(item: Array) -> void:
	match item[1]:
		"op":
			op(item[2], item[3], item[4], item[5])
		"ack":
			ack(item[2])
		"shelve":
			shelve(item[2], item[3])
		"unshelve":
			unshelve(item[2])
		"fault":
			fault(item[2])
		_:
			push_error("engine: unknown input " + str(item))


func v(name: String) -> float:
	return cur[ix[name]]


func truth(name: String) -> bool:
	return cur[ix[name]] >= 0.5


func _ev(e: Array) -> void:
	events.append([step_no] + e)


func _apply_set(s: Array) -> void:
	var slots: PackedInt32Array = s[0]
	var vals: PackedFloat64Array = s[1]
	for k in slots.size():
		cur[slots[k]] = vals[k]


func _enter(mi: int, to: int, cause: String) -> void:
	var mc = _mc[mi]
	var old := mstate[mi]
	mstate[mi] = to
	cur[mc[1]] = float(to)
	_ev(["machine", mc[0], mc[2][old], mc[2][to], cause])
	_apply_set(mc[3][to][0])


func _do_actions(acts: Array, moved: Dictionary) -> void:
	for a in acts:
		if a[0] == 0:
			_apply_set(a[1])
		else:
			_enter(a[1], a[2], "action")
			moved[a[1]] = true


# ---------------------------------------------------------------- the step (§7.10)

func step(count: int = 1) -> void:
	for _k in count:
		_step()


## A stateless node read from `vals` (the current step's values, or step 2's for a fault's condition).
func _stateless(p: int, vals: PackedFloat64Array) -> float:
	var a := _prog_a[p]
	match _prog_kind[p]:
		K_GE:
			return 1.0 if vals[_ia[a]] >= vals[_ia[a + 1]] else 0.0
		K_GT:
			return 1.0 if vals[_ia[a]] > vals[_ia[a + 1]] else 0.0
		K_LE:
			return 1.0 if vals[_ia[a]] <= vals[_ia[a + 1]] else 0.0
		K_LT:
			return 1.0 if vals[_ia[a]] < vals[_ia[a + 1]] else 0.0
		K_PRODUCT:
			var s := 1.0
			for k in range(a, a + _prog_na[p]):
				s = s * vals[_ia[k]]
			return s
		K_SUM:
			var s := 0.0
			for k in range(a, a + _prog_na[p]):
				s = s + vals[_ia[k]]
			return s
		K_AND:
			for k in range(a, a + _prog_na[p]):
				if not vals[_ia[k]] >= 0.5:
					return 0.0
			return 1.0
		K_OR:
			for k in range(a, a + _prog_na[p]):
				if vals[_ia[k]] >= 0.5:
					return 1.0
			return 0.0
		K_NOT:
			return 0.0 if vals[_ia[a]] >= 0.5 else 1.0
		K_OF:
			return _table(p, vals[_ia[a]])
		K_DIFF:
			return vals[_ia[a]] - vals[_ia[a + 1]]
		K_MIN:
			var s := vals[_ia[a]]
			for k in range(a + 1, a + _prog_na[p]):
				var x := vals[_ia[k]]
				if x < s:
					s = x
			return s
		K_MAX:
			var s := vals[_ia[a]]
			for k in range(a + 1, a + _prog_na[p]):
				var x := vals[_ia[k]]
				if x > s:
					s = x
			return s
		K_SELECT:
			var x := vals[_ia[a]]
			var cases := _prog_na[p] - 1
			var c := 0
			if x >= cases:
				c = cases - 1
			elif x >= 0.0:
				c = int(floor(x))
			return vals[_ia[a + 1 + c]]
		K_CONST:
			return _fa[_prog_f[p]]
	push_error("engine: not a stateless node")
	return 0.0


## COURSES.md §9.2 tables, as ref/courses.py table_at.
func _table(p: int, u: float) -> float:
	var cnt := _ia[_prog_a[p] + 1]
	var step_table := _ia[_prog_a[p] + 2] == 1
	var f := _prog_f[p]
	if u < _fa[f]:
		return _fa[f + 1]
	if step_table:
		var y := _fa[f + 1]
		for j in cnt:
			if _fa[f + 2 * j] <= u:
				y = _fa[f + 2 * j + 1]
			else:
				break
		return y
	if u >= _fa[f + 2 * (cnt - 1)]:
		return _fa[f + 2 * (cnt - 1) + 1]
	var i := 0
	for j in cnt:
		if _fa[f + 2 * j] <= u:
			i = j
		else:
			break
	var x0 := _fa[f + 2 * i]
	var y0 := _fa[f + 2 * i + 1]
	var x1 := _fa[f + 2 * i + 2]
	var y1 := _fa[f + 2 * i + 3]
	return y0 + (y1 - y0) * (u - x0) / (x1 - x0)


func _step() -> void:
	step_no += 1
	prev = cur.duplicate()
	var moved := {}
	var pressed := []
	# 1. the trainee's inputs, in the order made
	var q := queue
	queue = []
	for item in q:
		var kind: String = item[0]
		if kind == "op":
			_op(item, moved)
			continue
		var ai = _al_ix.get(item[1], -1) if typeof(item[1]) == TYPE_STRING else -1
		if kind == "fault":
			pressed.append(item[1])
		elif ai == -1:
			continue        # an alarm the model doesn't have: nothing happens, no event (§7.10)
		elif kind == "ack":
			if astate[ai] == "active_unack":
				astate[ai] = "active_ack"
				_ev(["alarm", item[1], "active_ack"])
			elif astate[ai] == "cleared_unack":
				astate[ai] = "normal"
				_ev(["alarm", item[1], "normal"])
		elif kind == "shelve":
			var t = item[2]
			if not (PlantModel.is_num(t) and t > 0 and t < 1e6):
				continue    # a shelving time outside (0, 10⁶) s does nothing (§7.6)
			shelved[ai] = step_no + steps(t)
			_ev(["shelve", item[1], t])
		elif kind == "unshelve":
			if shelved[ai] != -1:
				shelved[ai] = -1
				_ev(["unshelve", item[1]])
	# first-out records clear when no trip of the group is latched
	for g in first_out.keys():
		var any := false
		for k in _tr.size():
			if latched[k] and _tr[k][3] == g:
				any = true
				break
		if not any:
			first_out.erase(g)
	# 2. values, in order (stateful nodes read the previous step's values)
	var c := cur
	var pv := prev
	for p in _nprog:
		var kind := _prog_kind[p]
		var i := _prog_out[p]
		if kind < FIRST_STATEFUL:
			c[i] = _stateless(p, c)
			continue
		var a := _prog_a[p]
		var f := _prog_f[p]
		match kind:
			K_LAG:
				var x := pv[_ia[a]]
				var y := pv[i]
				c[i] = y + (x - y) * (_fa[f] if x >= y else _fa[f + 1])
			K_RAMP:
				var x := pv[_ia[a]]
				var y := pv[i]
				if x >= y:
					var up := y + _fa[f]
					c[i] = up if up < x else x
				else:
					var dn := y - _fa[f + 1]
					c[i] = dn if dn > x else x
			K_INTEGRATE:
				var y := pv[i] + _fa[f] * pv[_ia[a]] * STEP
				if _fa[f + 1] > y:
					y = _fa[f + 1]
				if _fa[f + 2] < y:
					y = _fa[f + 2]
				c[i] = y
			K_LATCH:
				if pv[_ia[a + 1]] >= 0.5:
					c[i] = 0.0
				elif pv[_ia[a]] >= 0.5:
					c[i] = 1.0
				else:
					c[i] = pv[i]
			K_DELAY:
				var slot := _ia[a + 3]
				var y := pv[i]
				if pv[_ia[a]] >= 0.5:
					mem[slot] += 1
					mem[slot + 1] = 0
					if y < 0.5 and mem[slot] >= _ia[a + 1]:
						y = 1.0
				else:
					mem[slot + 1] += 1
					mem[slot] = 0
					if y >= 0.5 and mem[slot + 1] >= _ia[a + 2]:
						y = 0.0
				c[i] = y
			K_TIMER:
				var slot := _ia[a + 1]
				if pv[_ia[a]] >= 0.5:
					mem[slot] += 1
				else:
					mem[slot] = 0
				c[i] = float(mem[slot]) / 10.0
			K_WRAP:
				var x := pv[i] + pv[_ia[a]] * STEP
				var per := _fa[f]
				c[i] = x - per * floor(x / per)
	cur = c
	var vals := cur.duplicate()     # conditions in steps 3–7 read the values as step 2 left them
	# 3. faults
	for fl in _faults:
		var fid: String = fl[0]
		if faults_done.has(fid):
			continue
		var hit := false
		match fl[1]:
			0:
				hit = vals[fl[2]] >= 0.5
			1:
				hit = _stateless(fl[2], vals) >= 0.5
			2:
				hit = pressed.has(fid)
		if hit:
			faults_done[fid] = true
			_apply_set(fl[3])
			_ev(["fault", fid])
	# 4. interlocks on a rising edge
	for k in _il.size():
		var x = _il[k]
		var now := vals[x[1]] >= 0.5
		if now and not il_prev[k]:
			_ev(["interlock", x[0]])
			_do_actions(x[2], moved)
		il_prev[k] = 1 if now else 0
	# 5. machines: at most one move each, by the first true next
	for mi in _mc.size():
		if moved.has(mi):
			continue
		for nx in _mc[mi][3][mstate[mi]][1]:
			if vals[nx[0]] >= 0.5:
				_enter(mi, nx[1], "next")
				moved[mi] = true
				break
	# 6. trips
	for k in _tr.size():
		if latched[k]:
			continue
		var t = _tr[k]
		if vals[t[1]] >= 0.5:
			trip_count[k] += 1
		else:
			trip_count[k] = 0
		if trip_count[k] >= t[2]:
			latched[k] = 1
			cur[t[5]] = 1.0
			var g: String = t[3]
			# first out: no other trip of its group is latched (also one a scenario started latched, §7.5)
			var first := g != ""
			if first:
				for j in _tr.size():
					if j != k and latched[j] and _tr[j][3] == g:
						first = false
						break
			if first:
				first_out[g] = t[0]
			_ev(["trip", t[0], first])
			_do_actions(t[4], {})
	# 7. alarms
	for k in _al.size():
		var a = _al[k]
		var sup: bool = a[3] != -1 and vals[a[3]] >= 0.5
		if shelved[k] != -1 and shelved[k] <= step_no:
			shelved[k] = -1
			_ev(["unshelve", a[0]])
		if sup or shelved[k] != -1:
			acount[k] = 0
			continue
		var on := vals[a[1]] >= 0.5
		acount[k] = acount[k] + 1 if on else 0
		var active: bool = acount[k] >= a[4]
		var clear: bool = vals[a[2]] >= 0.5 if a[2] != -1 else not on
		var s: String = astate[k]
		var nw := s
		if s == "normal" and active:
			nw = "active_unack"
		elif s == "active_unack" and clear:
			nw = "cleared_unack"
		elif s == "active_ack" and clear:
			nw = "normal"
		elif s == "cleared_unack" and active:
			nw = "active_unack"
		if nw != s:
			astate[k] = nw
			_ev(["alarm", a[0], nw])


func _op(item: Array, moved: Dictionary) -> void:
	var kks = item[1]
	var do = item[2]
	var value = item[3]
	var trip = item[4]
	var key = PlantModel.op_key(kks, do, trip)
	if key == null or not _ops.has(key):
		_ev(["op", kks, do, "unknown", []])
		return
	var c: Dictionary = _ops[key]
	var o: Dictionary = c["o"]
	var failed := []
	var needs: PackedInt32Array = c["needs"]
	for k in needs.size():
		if prev[needs[k]] < 0.5:
			failed.append(c["need_names"][k])
	var mi: int = c["mi"]
	if mi != -1:
		var spec: Dictionary = _mc[mi][4][do]
		var here: String = _mc[mi][2][mstate[mi]]
		if typeof(spec["from"]) != TYPE_STRING or spec["from"] != "*":
			if not spec["from"].has(here):
				failed.append(_mc[mi][0] + "_state")
	elif do == "reset":
		var ti: int = c["ti"]
		if not latched[ti]:
			failed.append(trip + "_latched")
		elif prev[_tr[ti][1]] >= 0.5:
			failed.append(m.trips[ti]["when"])
	elif do == "set":
		var t := typeof(value)
		if t == TYPE_BOOL:
			value = 1 if value else 0           # Python reads a bool as the int 0 or 1
			t = TYPE_INT
		if not (t == TYPE_INT or t == TYPE_FLOAT) or not (o["range"][0] <= value and value <= o["range"][1]):
			failed.append(o["input"])
	if not failed.is_empty():
		_ev(["op", kks, do, "refused", failed])
		return
	_ev(["op", kks, do, "done", []])
	if mi == -1 and do == "set":
		cur[c["input"]] = float(value)
	if mi == -1 and do == "reset":
		var ti: int = c["ti"]
		latched[ti] = 0
		trip_count[ti] = 0
		cur[_tr[ti][5]] = 0.0
	_apply_set(c["set"])
	if mi != -1:
		var to: int = _mc[mi][2].find(_mc[mi][4][do]["to"])
		_enter(mi, to, "command")
		moved[mi] = true


# ---------------------------------------------------------------- what the vectors compare (§12)

## §7.9: no unacknowledged alarm, no active priority 1 alarm, no machine in a watched state.
func fast_forward() -> bool:
	for k in _al.size():
		if shelved[k] != -1:
			continue
		var s: String = astate[k]
		if s == "active_unack" or s == "cleared_unack":
			return false
		if _al[k][5] == 1 and (s == "active_unack" or s == "active_ack"):
			return false
	for mi in _mc.size():
		if _mc[mi][3][mstate[mi]][2]:
			return false
	return true


func snapshot(with_values: bool = true) -> Dictionary:
	var machines := {}
	for mi in _mc.size():
		machines[_mc[mi][0]] = _mc[mi][2][mstate[mi]]
	var tripped := []
	for k in _tr.size():
		if latched[k]:
			tripped.append(_tr[k][0])
	tripped.sort()
	var fo := {}
	var groups := first_out.keys()
	groups.sort()
	for g in groups:
		fo[g] = first_out[g]
	var al := {}
	for k in _al.size():
		if astate[k] != "normal":
			al[_al[k][0]] = astate[k]
	var sh := []
	for k in _al.size():
		if shelved[k] != -1:
			sh.append(_al[k][0])
	sh.sort()
	var s := {"step": step_no, "machines": machines, "tripped": tripped, "first_out": fo, "alarms": al,
			"shelved": sh, "fast_forward": fast_forward()}
	if with_values:
		var vals := {}
		for i in n:
			vals[names[i]] = cur[i]
		s["values"] = vals
	return s


## The values in slot order (declared, ext, machine states, trip latches), as doubles.
func value_array() -> PackedFloat64Array:
	return cur.slice(0, n)


## An independent copy at the same step (forks of a run: one cold start, many trip tests).
func clone():
	var c = get_script().new()
	for k in ["m", "sc", "names", "ix", "n", "_prog_kind", "_prog_out", "_prog_a", "_prog_na", "_prog_f", "_ia",
			"_fa", "_nprog", "_init_vals", "_nmem", "_il", "_mc", "_mc_ix", "_tr", "_tr_ix", "_al", "_al_ix",
			"_faults", "_ops", "step_no"]:
		c.set(k, get(k))
	for k in ["cur", "prev", "mem", "mstate", "latched", "trip_count", "acount", "shelved", "il_prev"]:
		c.set(k, get(k).duplicate())        # packed arrays: a copy of their own
	for k in ["first_out", "astate", "faults_done", "queue", "events", "inputs"]:
		c.set(k, get(k).duplicate(true))
	return c
