extends RefCounted
## The behaviour model's engine (docs/PLANT3D.md §7): steps the joined model of a plant exactly as §7.10 says, with
## the same double-precision arithmetic as the reference (ref/plant3d.py Engine), so the two agree bit for bit on
## ref/vectors/plant3d-v1.json (apps/plant3d/sim/tests).
##
## Trainee inputs are queued and take effect in step 1 of the next step, in the order made:
##   op(kks, do, value, trip), ack(alarm), shelve(alarm, seconds), unshelve(alarm), fault(id), repair(id)
## (fault: a scenario fault without `when`, pressed by the trainer; applied in step 3; repair: a fault's repair,
## applied in step 3 after the faults, §7.8). Format 2 (§15, free mode: person null): permit(work, action, person),
## lock(work, point, person), unlock(work, point, person): permit actions in step 1, locks and unlocks noted in step 1
## and made at the start of step 3 (§17.1). Every input is also kept in
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

# node kinds, the commonest first (the evaluator tests them in this order)
enum {K_GE, K_GT, K_LE, K_LT, K_OF, K_PRODUCT, K_AND, K_SUM, K_NOT, K_DIFF, K_MAX, K_SELECT, K_OR, K_MIN, K_CONST,
		K_HOLD, K_LAG, K_INTEGRATE, K_RAMP, K_TIMER, K_LATCH, K_DELAY, K_WRAP}
const FIRST_STATEFUL := K_LAG
# a permit's actions (§15.3): the states each is taken in, and where it goes
const PERMIT_ACTIONS := {"request": [[0, 9, 10], 1], "approve": [[1], 2], "issue": [[3], 4], "accept": [[4], 5],
		"done": [[5], 6], "return": [[6], 7], "close": [[8], 9], "cancel": [[1, 2, 3], 10]}

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
var _fault_nodes := PackedInt32Array()  # program entries of faults' `when` nodes (evaluated on their own)
var _scratch := 0                       # the slot a fault's `when` node writes

# compiled conditions and actions
var _il: Array = []          # [id, when slot, actions]
var _mc: Array = []          # [id, state slot, ids, states: [[set, next: [[slot, to]...], watch]...], commands]
var _mc_ix := {}             # machine id -> position
var _tr: Array = []          # [id, when slot, count needed, group, actions, latched slot]
var _tr_ix := {}
var _al: Array = []          # [id, when slot, clear slot or -1, suppress slot or -1, count needed, priority]
var _al_ix := {}
var _faults: Array = []      # [id, kind 0 name / 1 node / 2 trainer, slot or node, set, repair set or null]
var _fault_ix := {}          # fault id -> position in _faults
var _ops := {}               # op key -> compiled op
var _iso: Array = []         # format 2: [id, points [[code, safe slot or -1]...], locked slot, complete slot,
							 #   its first bit in lockbits]
var _wk: Array = []          # [id, isolation index or -1, permit slot, repairs (fault id) or null, set]
var _state_kks := {}         # state slot -> its code (states with a kks)
var _v2 := false              # a version 2 plant (§14): its snapshots have permits, ptw and locked

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
var faults_fixed := {}       # faults applied and repaired since (§7.8)
var pstate := PackedInt32Array()    # per work: its permit's state (§15.3)
var ptw := {}                # work id -> its permit's number, from its last request
var ptw_count := 0
var acceptor := {}           # work id -> who accepted its permit (null in free mode)
var holder := PackedInt32Array()    # per isolation: the work holding it, -1 for none (§15.1)
var lockbits := PackedByteArray()  # 1 for each locked point, every isolation's points one after the other
var lockers := {}            # Vector2i(isolation, point) -> who locked it
var code_locks := {}         # code -> its locked points, of every isolation (none: not in it)
var queue: Array = []
var events: Array = []
var inputs: Array = []
var step_no := 0
var timing := false                 # when set, every step's time in microseconds goes to step_us (tests/bench_step.gd)
var step_us := PackedInt64Array()


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
	names.append_array(PackedStringArray(m.kept()))
	_v2 = m.version == 2
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
			# the step counts as floats: content allows times up to 1e9 s (1e10 steps), past 32-bit refs; a count
			# compares exactly with them below 2^53
			return _emit(K_DELAY, i, [_ref(nd["delay"]), slot], [float(steps(nd["on"])), float(steps(nd.get("off", 0)))])
		"timer":
			var slot := _nmem
			_nmem += 1
			return _emit(K_TIMER, i, [_ref(nd["timer"]), slot], [])
		"wrap":
			return _emit(K_WRAP, i, [_ref(nd["wrap"])], [float(nd["period"])])
		"hold":
			# §15.4: without an init (its own or the scenario's) it takes its input at step 0
			var free := 1 if not nd.has("init") and not sc["init"].has(names[i]) else 0
			return _emit(K_HOLD, i, [_ref(nd["hold"]), _ref(nd["when"]), free], [])
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
				ix[a["suppress"]] if a.has("suppress") else -1, maxi(1, steps(a.get("delay", 0))), a["priority"],
				a["kks"]])
	for f in sc.get("faults", []):
		_fault_ix[f["id"]] = _faults.size()
		var fs := _sets(f["set"])
		var rs = _sets(f["repair"]) if f.has("repair") else null
		if not f.has("when"):
			_faults.append([f["id"], 2, -1, fs, rs])
		elif typeof(f["when"]) == TYPE_STRING:
			_faults.append([f["id"], 0, ix[f["when"]], fs, rs])
		else:
			var kind := PlantModel.node_kind(f["when"])
			var fp := _node(-1, f["when"], kind)
			_fault_nodes.append(fp)
			_faults.append([f["id"], 1, fp, fs, rs])
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
	# format 2: isolations and works (§15)
	for i in m.values.size():
		var v = m.values[i]
		if v[2] == "state" and v[1].has("kks"):
			_state_kks[i] = v[1]["kks"]
	for x in m.isolations:
		var pts := []
		for pt in x["points"]:
			pts.append([pt["kks"], ix[pt["safe"]] if pt.has("safe") else -1])
		var off: int = 0 if _iso.is_empty() else _iso[-1][4] + _iso[-1][1].size()
		_iso.append([x["id"], pts, ix[x["id"] + "_locked"], ix[x["id"] + "_complete"], off])
	for w in m.works:
		_wk.append([w["id"], m.isolation_ix[w["isolation"]] if w.has("isolation") else -1, ix[w["id"] + "_permit"],
				w.get("repairs"), _sets(w.get("set", {}))])
	# the constants live after the values, in cur and prev alike
	_init_vals.append_array(PackedFloat64Array(_consts))
	_scratch = _init_vals.size()
	_init_vals.append(0.0)
	for fp in _fault_nodes:
		_prog_out[fp] = _scratch
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
	pstate.resize(_wk.size())
	holder.resize(_iso.size())
	holder.fill(-1)
	lockbits.resize(0 if _iso.is_empty() else _iso[-1][4] + _iso[-1][1].size())
	prev = cur.duplicate()
	_run(0, _nprog, cur, prev, true)


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


func repair(fid) -> void:
	_q(["repair", fid])


func permit(work, action, person = null) -> void:
	_q(["permit", work, action, person])


func lock(work, point, person = null) -> void:
	_q(["lock", work, point, person])


func unlock(work, point, person = null) -> void:
	_q(["unlock", work, point, person])


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
		"repair":
			repair(item[2])
		"permit":
			permit(item[2], item[3], item[4])
		"lock":
			lock(item[2], item[3], item[4])
		"unlock":
			unlock(item[2], item[3], item[4])
		_:
			push_error("engine: unknown input " + str(item))


func v(name: String) -> float:
	return cur[ix[name]]


func truth(name: String) -> bool:
	return cur[ix[name]] >= 0.5


func _ev(e: Array) -> void:
	events.append([step_no] + e)


func _apply_set(s: Array, work: int = -1) -> void:
	var slots: PackedInt32Array = s[0]
	var vals: PackedFloat64Array = s[1]
	if code_locks.is_empty():
		for k in slots.size():
			cur[slots[k]] = vals[k]
		return
	for k in slots.size():
		_write(slots[k], vals[k], work)


## A write to a state, skipped while its code is locked (§15.1); a work's own `done` writes (work: its index) are made
## when every isolation locking the code is held by that work.
func _write(i: int, x: float, work: int = -1) -> void:
	if not code_locks.is_empty():
		var c = _state_kks.get(i)
		if c != null and code_locks.has(c):
			if work == -1:
				return
			for k in _iso.size():
				if holder[k] == work:
					continue
				var pts: Array = _iso[k][1]
				var off: int = _iso[k][4]
				for p in pts.size():
					if lockbits[off + p] and pts[p][0] == c:
						return
	cur[i] = x


## The isolations (in model order) with a locked point on this code, as their `<id>_locked` names.
func _locking(code) -> Array:
	var out := []
	if not code_locks.has(code):
		return out
	for k in _iso.size():
		var pts: Array = _iso[k][1]
		var off: int = _iso[k][4]
		for p in pts.size():
			if lockbits[off + p] and pts[p][0] == code:
				out.append(_iso[k][0] + "_locked")
				break
	return out


func _n_locked(k: int) -> int:
	var c := 0
	var off: int = _iso[k][4]
	for p in _iso[k][1].size():
		c += lockbits[off + p]
	return c


## A permit action (§15.3), in step 1.
func _permit(work, action, person, dones: Array) -> void:
	if typeof(work) != TYPE_STRING or not m.work_ix.has(work) or typeof(action) != TYPE_STRING \
			or not PERMIT_ACTIONS.has(action):
		_ev(["permit", work, action, person, "unknown", []])
		return
	var wi: int = m.work_ix[work]
	var iso: int = _wk[wi][1]
	var spec: Array = PERMIT_ACTIONS[action]
	var why := []
	if person != null:
		why.append("authority")     # no staff in the plant: free mode, person null (§17.1)
	if not spec[0].has(pstate[wi]):
		why.append("state")
	if action == "request" and iso != -1 and holder[iso] != -1:
		why.append("iso_busy")
	if not why.is_empty():
		_ev(["permit", work, action, person, "refused", why])
		return
	pstate[wi] = spec[1]
	cur[_wk[wi][2]] = float(spec[1])
	if action == "request":
		ptw_count += 1
		ptw[work] = "PTW-%04d" % ptw_count
		acceptor.erase(work)
		if iso != -1:
			holder[iso] = wi
	elif action == "accept":
		acceptor[work] = person
	elif action == "done":
		dones.append(wi)
	elif (action == "cancel" or action == "close") and iso != -1 and _n_locked(iso) == 0:
		holder[iso] = -1
	_ev(["permit", work, action, person, "done", []])


## A lock or unlock (§15.1), at the start of step 3.
func _lock(kind: String, work, point, person, vals: PackedFloat64Array) -> void:
	var wi: int = m.work_ix.get(work, -1) if typeof(work) == TYPE_STRING else -1
	var k: int = _wk[wi][1] if wi != -1 else -1
	if k == -1 or typeof(point) != TYPE_INT or point < 0 or point >= _iso[k][1].size():
		_ev([kind, work, point, person, "unknown", []])
		return
	var pt: Array = _iso[k][1][point]
	var bit: int = _iso[k][4] + point
	var why := []
	if person != null:
		why.append("authority")
	var st := pstate[wi]
	var ok := (st == 2 or st == 3) if kind == "lock" else (st == 2 or st == 3 or st == 7 or st == 10)
	if not ok or holder[k] != wi:
		why.append("state")
	if kind == "lock":
		if lockbits[bit]:
			why.append("locked")
		if pt[1] != -1 and vals[pt[1]] < 0.5:
			why.append(names[pt[1]])
	elif not lockbits[bit]:
		why.append("unlocked")
	if not why.is_empty():
		_ev([kind, work, point, person, "refused", why])
		return
	if kind == "lock":
		lockbits[bit] = 1
		lockers[Vector2i(k, point)] = person
		code_locks[pt[0]] = code_locks.get(pt[0], 0) + 1
	else:
		lockbits[bit] = 0
		lockers.erase(Vector2i(k, point))
		code_locks[pt[0]] -= 1
		if code_locks[pt[0]] == 0:
			code_locks.erase(pt[0])
	var c := _n_locked(k)
	cur[_iso[k][2]] = float(c)
	cur[_iso[k][3]] = 1.0 if c == _iso[k][1].size() else 0.0
	if kind == "unlock" and st == 10 and c == 0:
		holder[k] = -1      # a cancelled work lets its isolation go with its last lock
	_ev([kind, work, point, person, "done", []])


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
	if timing:
		for _k in count:
			var t0 := Time.get_ticks_usec()
			_step()
			step_us.append(Time.get_ticks_usec() - t0)
		return
	for _k in count:
		_step()


## Evaluates program entries p0 … p1 − 1 into c: stateless nodes read c (this step's values), stateful ones pv (the
## previous step's); stateless_only skips the stateful ones (step 0). The one evaluator of every node, inlined for
## speed: GDScript calls and Variant arrays cost more than the arithmetic.
func _run(p0: int, p1: int, c: PackedFloat64Array, pv: PackedFloat64Array, stateless_only: bool) -> void:
	var kinds := _prog_kind
	var outs := _prog_out
	var pa := _prog_a
	var pn := _prog_na
	var pf := _prog_f
	var ia := _ia
	var fa := _fa
	for p in range(p0, p1):
		var kind := kinds[p]
		var a := pa[p]
		if kind == K_GE:
			c[outs[p]] = 1.0 if c[ia[a]] >= c[ia[a + 1]] else 0.0
		elif kind == K_GT:
			c[outs[p]] = 1.0 if c[ia[a]] > c[ia[a + 1]] else 0.0
		elif kind == K_LE:
			c[outs[p]] = 1.0 if c[ia[a]] <= c[ia[a + 1]] else 0.0
		elif kind == K_LT:
			c[outs[p]] = 1.0 if c[ia[a]] < c[ia[a + 1]] else 0.0
		elif kind == K_OF:
			c[outs[p]] = _table(p, c[ia[a]])
		elif kind == K_PRODUCT:
			var s := 1.0
			for k in range(a, a + pn[p]):
				s = s * c[ia[k]]
			c[outs[p]] = s
		elif kind == K_AND:
			var r := 1.0
			for k in range(a, a + pn[p]):
				if not c[ia[k]] >= 0.5:
					r = 0.0
					break
			c[outs[p]] = r
		elif kind == K_SUM:
			var s := 0.0
			for k in range(a, a + pn[p]):
				s = s + c[ia[k]]
			c[outs[p]] = s
		elif kind == K_NOT:
			c[outs[p]] = 0.0 if c[ia[a]] >= 0.5 else 1.0
		elif kind == K_DIFF:
			c[outs[p]] = c[ia[a]] - c[ia[a + 1]]
		elif kind == K_MAX:
			var s := c[ia[a]]
			for k in range(a + 1, a + pn[p]):
				var x := c[ia[k]]
				if x > s:
					s = x
			c[outs[p]] = s
		elif kind == K_SELECT:
			var x := c[ia[a]]
			var cases := pn[p] - 1
			var w := 0
			if x >= cases:
				w = cases - 1
			elif x >= 0.0:
				w = int(floor(x))
			c[outs[p]] = c[ia[a + 1 + w]]
		elif kind == K_OR:
			var r := 0.0
			for k in range(a, a + pn[p]):
				if c[ia[k]] >= 0.5:
					r = 1.0
					break
			c[outs[p]] = r
		elif kind == K_MIN:
			var s := c[ia[a]]
			for k in range(a + 1, a + pn[p]):
				var x := c[ia[k]]
				if x < s:
					s = x
			c[outs[p]] = s
		elif kind == K_CONST:
			c[outs[p]] = fa[pf[p]]
		elif kind == K_HOLD:
			# §15.4: the input as this step computed it while `when`, as the previous step left it, is false
			var i := outs[p]
			if stateless_only:
				if ia[a + 2] == 1:
					c[i] = c[ia[a]]
			elif pv[ia[a + 1]] >= 0.5:
				c[i] = pv[i]
			else:
				c[i] = c[ia[a]]
		elif stateless_only:
			continue
		elif kind == K_LAG:
			var i := outs[p]
			var f := pf[p]
			var x := pv[ia[a]]
			var y := pv[i]
			c[i] = y + (x - y) * (fa[f] if x >= y else fa[f + 1])
		elif kind == K_INTEGRATE:
			var i := outs[p]
			var f := pf[p]
			var y := pv[i] + fa[f] * pv[ia[a]] * STEP
			if fa[f + 1] > y:
				y = fa[f + 1]
			if fa[f + 2] < y:
				y = fa[f + 2]
			c[i] = y
		elif kind == K_RAMP:
			var i := outs[p]
			var f := pf[p]
			var x := pv[ia[a]]
			var y := pv[i]
			if x >= y:
				var up := y + fa[f]
				c[i] = up if up < x else x
			else:
				var dn := y - fa[f + 1]
				c[i] = dn if dn > x else x
		elif kind == K_TIMER:
			var slot := ia[a + 1]
			if pv[ia[a]] >= 0.5:
				mem[slot] += 1
			else:
				mem[slot] = 0
			c[outs[p]] = float(mem[slot]) / 10.0
		elif kind == K_LATCH:
			var i := outs[p]
			if pv[ia[a + 1]] >= 0.5:
				c[i] = 0.0
			elif pv[ia[a]] >= 0.5:
				c[i] = 1.0
			else:
				c[i] = pv[i]
		elif kind == K_DELAY:
			var i := outs[p]
			var slot := ia[a + 1]
			var f := pf[p]
			var y := pv[i]
			if pv[ia[a]] >= 0.5:
				mem[slot] += 1
				mem[slot + 1] = 0
				if y < 0.5 and mem[slot] >= fa[f]:
					y = 1.0
			else:
				mem[slot + 1] += 1
				mem[slot] = 0
				if y >= 0.5 and mem[slot + 1] >= fa[f + 1]:
					y = 0.0
			c[i] = y
		elif kind == K_WRAP:
			var i := outs[p]
			var x := pv[i] + pv[ia[a]] * STEP
			var per := fa[pf[p]]
			c[i] = x - per * floor(x / per)
		else:
			push_error("engine: unknown node kind %d" % kind)


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
	var asked := []
	var noted := []         # locks and unlocks, made in step 3 (§17.1)
	var dones := []         # works whose permit went to done: their repairs and set in step 3
	# 1. the trainee's inputs, in the order made
	var q := queue
	queue = []
	for item in q:
		var kind: String = item[0]
		if kind == "op":
			_op(item, moved)
			continue
		if kind == "permit":
			_permit(item[1], item[2], item[3], dones)
			continue
		if kind == "lock" or kind == "unlock":
			noted.append(item)
			continue
		var ai = _al_ix.get(item[1], -1) if typeof(item[1]) == TYPE_STRING else -1
		if kind == "fault":
			pressed.append(item[1])
		elif kind == "repair":
			asked.append(item[1])
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
	_run(0, _nprog, cur, prev, false)
	var vals := cur.duplicate()     # conditions in steps 3–7 read the values as step 2 left them
	# 3. the locks and unlocks noted in step 1, in the order made; the permits' automatic moves (§15.3)
	for item in noted:
		_lock(item[0], item[1], item[2], item[3], vals)
	for wi in _wk.size():
		var k: int = _wk[wi][1]
		var c := _n_locked(k) if k != -1 else 0
		var whole: bool = k == -1 or c == _iso[k][1].size()
		var st := pstate[wi]
		var nw := -1
		if st == 2 and whole:
			nw = 3
		elif st == 3 and not whole:
			nw = 2
		elif st == 7 and c == 0:
			nw = 8
		if nw != -1:
			pstate[wi] = nw
			cur[_wk[wi][2]] = float(nw)
			_ev(["permit", _wk[wi][0], "auto", null, "done", [nw]])
	# then the faults
	for fl in _faults:
		var fid: String = fl[0]
		# applied once; a repaired trainer's fault can be pressed again (§7.8)
		if faults_done.has(fid) and not (faults_fixed.has(fid) and fl[1] == 2):
			continue
		var hit := false
		match fl[1]:
			0:
				hit = vals[fl[2]] >= 0.5
			1:
				_run(fl[2], fl[2] + 1, vals, vals, true)
				hit = vals[_scratch] >= 0.5
			2:
				hit = pressed.has(fid)
		if hit:
			faults_done[fid] = true
			faults_fixed.erase(fid)
			_apply_set(fl[3])
			_ev(["fault", fid])
	# then the repairs asked, in the scenario's order: a fault applied and not repaired since, with a `repair`
	for fl in _faults:
		var fid: String = fl[0]
		if fl[4] != null and asked.has(fid) and faults_done.has(fid) and not faults_fixed.has(fid):
			faults_fixed[fid] = true
			_apply_set(fl[4])
			_ev(["repair", fid])
	# then the works whose permit went to done, in the order of their `done`: the fault they repair, their set
	for wi in dones:
		var fid = _wk[wi][3]
		var fk: int = _fault_ix.get(fid, -1) if typeof(fid) == TYPE_STRING else -1
		if fk != -1 and _faults[fk][4] != null and faults_done.has(fid) and not faults_fixed.has(fid):
			faults_fixed[fid] = true
			_apply_set(_faults[fk][4], wi)
			_ev(["repair", fid])
		_apply_set(_wk[wi][4], wi)
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
		var sup: bool = a[3] != -1 and vals[a[3]] >= 0.5 or code_locks.has(a[6])
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
	failed.append_array(_locking(kks))         # a locked code refuses every op (§15.1)
	if not failed.is_empty():
		_ev(["op", kks, do, "refused", failed])
		return
	_ev(["op", kks, do, "done", []])
	if mi == -1 and do == "set":
		_write(c["input"], float(value))
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

## An alarm suppressed now: by design (its `suppress` value, §7.6) or because its code is locked (§15.1).
func alarm_suppressed(k: int) -> bool:
	var a = _al[k]
	return (a[3] != -1 and cur[a[3]] >= 0.5) or code_locks.has(a[6])


## The isolations' ids locking a code now, in model order (§15.1).
func isolations_locking(code) -> Array:
	return _locking(code).map(func(x): return String(x).trim_suffix("_locked"))


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
	if _v2:
		var pm := {}
		var nums := {}
		for wi in _wk.size():
			if pstate[wi] != 0:
				pm[_wk[wi][0]] = pstate[wi]
		for wi in _wk.size():
			if ptw.has(_wk[wi][0]):
				nums[_wk[wi][0]] = ptw[_wk[wi][0]]
		var lk := []
		for k in _iso.size():
			for p in _iso[k][1].size():
				if lockbits[_iso[k][4] + p]:
					lk.append([_iso[k][0], p])
		s["permits"] = pm
		s["ptw"] = nums
		s["locked"] = lk
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
			"_fa", "_nprog", "_fault_nodes", "_scratch", "_init_vals", "_nmem", "_il", "_mc", "_mc_ix", "_tr", "_tr_ix", "_al", "_al_ix",
			"_faults", "_fault_ix", "_ops", "_iso", "_wk", "_state_kks", "_v2", "step_no", "ptw_count"]:
		c.set(k, get(k))
	for k in ["cur", "prev", "mem", "mstate", "latched", "trip_count", "acount", "shelved", "il_prev", "pstate", "holder",
			"lockbits"]:
		c.set(k, get(k).duplicate())        # packed arrays: a copy of their own
	for k in ["first_out", "astate", "faults_done", "faults_fixed", "queue", "events", "inputs", "ptw", "acceptor",
			"lockers", "code_locks"]:
		c.set(k, get(k).duplicate(true))
	return c
