extends RefCounted
## The behaviour model's engine (docs/PLANT3D.md §7): steps the joined model of a plant exactly as §7.10 says, with
## the same double-precision arithmetic as the reference (ref/plant3d.py Engine), so the two agree bit for bit on
## ref/vectors/plant3d-v1.json (apps/plant3d/sim/tests).
##
## Trainee inputs are queued and take effect in step 1 of the next step, in the order made:
##   op(kks, do, value, trip), ack(alarm), shelve(alarm, seconds), unshelve(alarm), fault(id), repair(id)
## (fault: a scenario fault without `when`, pressed by the trainer; applied in step 3; repair: a fault's repair,
## applied in step 3 after the faults, §7.8). Format 2 (§15, free mode: person null): permit(work, action, person),
## lock(work, point, person), unlock(work, point, person), repair_under(fault, work, person): permit actions in step 1,
## locks and unlocks noted in step 1 and made at the start of step 3 (§17.1), the trainee's repair under a permit
## checked in step 1 and made in step 3 (§15.5; in a version 2 plant repair(id) is the trainer's). lock_effects(work,
## point) answers what a lock would do (§15.6) without changing the run. Every input is also kept in
## `inputs` as [the step it takes effect in, kind, …], the vectors' input form.
##
## A session run (docs/PLANT3D.md §17.13, docs/plant3d/MULTIPLAYER.md §3.3: `new(model, scenario, true)`) has up to
## SLOTS players: every input names its slot (the methods' `slot` argument, the input form's last element) and is
## handled for the person that slot plays. A single-player run's inputs have no slot (its trainee is slot 0's).
## digest() is the state digest of PLANT3D.md §17.14 (MULTIPLAYER.md §4).
##
## Arithmetic notes (what makes it bit-exact, each mirrored from the reference):
## - every value is a float (IEEE 754 double); content numbers are read correctly rounded (json_strict.gd);
## - sum and product fold left from 0.0 and 1.0; min and max keep the first of equal values (Python's min/max), so
##   -0.0 and 0.0 come out as the reference's; a lag's factor 1 − exp(−0.1/τ) and a ramp's rate × 0.1 are computed
##   once per node;
## - a time t counts floor(t / 0.1 + 0.5) steps; a timer is count / 10.0.

const PlantModel = preload("plant_model.gd")
const Staff = preload("staff.gd")

const STEP := 0.1
const SLOTS := 8                    # a session run's slots, 0 to 7 (§17.13)

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
var _fast = null                        # the program as straight-line GDScript (_gen_fast), or null: _run
static var _interpret_only := false    # tests: step with _run alone (tests/run_vectors.gd --interpreter=1)

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
var _auto_faults := PackedInt32Array()  # the faults with a `when` (not the trainer's), in scenario order
var _all_faults := PackedInt32Array()   # every fault, in scenario order
var _tr_when := PackedInt32Array()      # per trip: its `when` slot, and the steps it needs
var _tr_need := PackedInt64Array()
var _al_when := PackedInt32Array()      # per alarm: its `when`, `clear` and `suppress` slots (-1: none)
var _al_clear := PackedInt32Array()
var _al_sup := PackedInt32Array()
var _al_need := PackedInt64Array()      # per alarm: the steps it needs
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
var lockers := {}            # Vector2i(isolation, point) -> who locked it: the persons, in the order placed
var code_locks := {}         # code -> its locked points, of every isolation (none: not in it)
var _lift_ix := {}           # format 2's lifts (§20.3): id -> position in the model's lifts
var _load_slot := PackedInt32Array()    # per lift: the slot of its <id>_load
var riders: Array = []       # per lift: its riders in boarding order (a person id, or a slot for a null person)
var lift_quiet := PackedInt64Array()    # per lift: the step of its last board or alight done
var queue: Array = []
var events: Array = []
var inputs: Array = []
var step_no := 0
var timing := false                 # when set, every step's time in microseconds goes to step_us (tests/bench_step.gd)
var step_us := PackedInt64Array()
var staff_us := PackedInt64Array()    # with timing: step 9's own time in each step

# format 2's clock and staff (§16–§17): built from the content and the scenario (shared by clones, not saved)
var _sm = null                      # sim/staff.gd: the plant's staff.json when the scenario has `staff`, else null
var _S := 0                         # the clock at step 0, in tenths of a clock second (§16.1)
var _ds := 0                        # day_scale
var _absent := {}                   # person index -> true
var _fixed_trainee := false         # the scenario names the trainee
var _show := {}                     # code -> its show binding's value name or number
var _fault_kks := {}                # scenario fault id -> its code or null
var _npc_pending := 0               # the NPCs' inputs in this step's step 1 (set every step)
var _npc_evs := {}                  # this step's events of NPC inputs whose person a slot took in step 1 (§17.13)
# the staff's state (§17; saved with the run, copied by clone): st_ for the run, sp_ per person in file order
var J := 0                          # the jumps made, in tenths of a clock second
var npc_queue: Array = []           # the NPCs' inputs made in step 9, for the next step's step 1
var ev_mark := 0                    # where this step's events begin
var st_order := 0                   # task instances made
var st_session := false             # a session run (§17.13): every input with its slot
var st_players := PackedInt32Array()    # per slot: the person it plays, -1 for none (a single-player run: slot 0)
var st_acks := PackedInt32Array()   # per slot: tasks given to its person since their last task_ack (§17.6)
var st_t_from := PackedInt32Array() # per slot: the place its person last left (a release puts them back), -1
var st_t_in: Array = []             # the players' inputs for step 9: [slot, input], in the order made
var st_jumped: Array = []           # [old clock, new clock] of a jump in this step
var st_holder := {}                 # place -> the person reserving or occupying it
var st_given := {}                  # reaction source -> instances of it still queued or current
var st_vprev: Array = []            # per reaction on a value: its truth after the previous step
var st_next1 := 0                   # the clock at which phase 1 next has something to do (staff.gd _phase1)
var st_kept: Array = []             # per slot: its person's done actions no step took yet (§17.8): [kind, step, …]
var st_pending: Array = []          # offers for a permit nobody was on duty to take (§17.10), staff.gd offer()
var st_left := {}                   # people off site with a lock at the last phase 2 (§17.9): index -> true
var sp_on := PackedByteArray()
var sp_duty: Array = []             # [start, end] or []
var sp_duties: Array = []           # the duties planned ahead
var sp_planned := PackedInt64Array()
var sp_slots: Array = []            # [time, duty start, slot, repetition, task, duty]
var sp_pos := PackedInt32Array()    # place, -1 off site or on a way
var sp_leg: Array = []              # [from, to, depart, arrive] or []
var sp_cur: Array = []              # the current task instance or null
var sp_queue: Array = []
var sp_res := PackedInt32Array()    # a place reserved, -1
var sp_occ := PackedInt32Array()    # a place occupied, -1
var sp_result: Array = []           # an NPC's input's outcome, read in step 9
var sp_rng := PackedInt64Array()
var sp_wake := PackedInt64Array()   # the step a person's next turn can change anything (staff.gd turn)
var sp_held: Array = []             # a job held overnight (§17.10), or null
var sp_worn := PackedInt32Array()   # the PPE items worn: a bit per item of staff.gd PPE (§17.11)
var sp_acts: Array = []             # per person: an Array per act kind (staff.gd ACT_KINDS), null or [zone or work, start, stopped]
var sp_zin := PackedInt64Array()    # the trainee's zones from their zone inputs: a bit per zone (file order)
var sp_ride: Array = []             # a ride (§20.4): [staff lift, a, b, 0 waiting / 1 aboard, wait start, destination] or []
var sp_stairs: Array = []           # the stairs walked instead of a ride: [destination, place, …, b], or empty
var sp_lin := PackedInt64Array()    # the step of a person's last lift input
var st_made := {}                   # `seen` reactions made, once per act (§16.7): source key -> true
var _touched := PackedByteArray()   # people whose acts may have changed in this step's step 9 (staff.gd: scratch)
var _in_slot := 0                   # the slot of the player's input being handled (step 1, and its locks in step 3)


func _init(model = null, scenario = null, session := false) -> void:
	st_players.resize(SLOTS)
	st_players.fill(-1)
	st_acks.resize(SLOTS)
	st_t_from.resize(SLOTS)
	st_t_from.fill(-1)
	for k in SLOTS:
		st_kept.append([])
	if model == null:
		return          # clone() fills the rest
	st_session = session
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
	for k in m.lifts.size():
		_lift_ix[m.lifts[k]["id"]] = k
		_load_slot.append(ix[m.lifts[k]["id"] + "_load"])
		riders.append([])
	lift_quiet.resize(m.lifts.size())
	for x in m.bind:
		if x.has("show") and not _show.has(x["kks"]):
			_show[x["kks"]] = x["show"]
	for f in sc.get("faults", []):
		_fault_kks[f["id"]] = f.get("kks")
	var clock = m.plant.get("clock")
	if clock != null:
		_ds = int(clock["day_scale"])
		var st: Dictionary = sc.get("start", clock["start"])
		_S = (int(st["day"]) * 1440 + Staff.hhmm(st["time"])) * 600
	if m.staff != null and sc.has("staff"):
		_sm = m.staff
		_sm.init_run(self, sc)


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
	for k in _faults.size():
		_all_faults.append(k)
		if _faults[k][1] != 2:
			_auto_faults.append(k)
	for t in _tr:
		_tr_when.append(t[1])
		_tr_need.append(t[2])
	for a in _al:
		_al_when.append(a[1])
		_al_clear.append(a[2])
		_al_sup.append(a[3])
		_al_need.append(a[4])
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
	_gen_fast()


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

func _q(item: Array, slot = null) -> void:
	if st_session:
		if slot == null:
			push_error("engine: a session run's input names its slot: " + str(item))
			return
		item = item + [slot]
	elif slot != null:
		push_error("engine: a single-player run's inputs have no slot: " + str(item))
		return
	inputs.append([step_no + 1] + item)
	queue.append(item)


## An op; with `where` it is a version 2 op (§17.1), made at `where` by `person`.
func op(kks, do, value = null, trip = null, where = null, person = null, slot = null) -> void:
	if where == null and person == null:
		_q(["op", kks, do, value, trip], slot)
	else:
		_q(["op", kks, do, value, trip, where, person], slot)


func ack(alarm, slot = null) -> void:
	_q(["ack", alarm], slot)


func shelve(alarm, seconds, slot = null) -> void:
	_q(["shelve", alarm, seconds], slot)


func unshelve(alarm, slot = null) -> void:
	_q(["unshelve", alarm], slot)


func fault(fid, slot = null) -> void:
	_q(["fault", fid], slot)


func repair(fid, slot = null) -> void:
	_q(["repair", fid], slot)


## The trainee's repair under a work's permit (§15.5): checked in step 1, made in step 3 with the trainer's repairs.
func repair_under(fid, work, person = null, slot = null) -> void:
	_q(["repair", fid, work, person], slot)


func permit(work, action, person = null, slot = null) -> void:
	_q(["permit", work, action, person], slot)


func lock(work, point, person = null, slot = null) -> void:
	_q(["lock", work, point, person], slot)


func unlock(work, point, person = null, slot = null) -> void:
	_q(["unlock", work, point, person], slot)


## The compiled op of a code, do and trip (staff.gd: the trainee's actions before their step), null for none.
func op_entry(kks, do, trip):
	var key = PlantModel.op_key(kks, do, trip)
	return _ops.get(key) if key != null else null


## A lock removal by authority (§15.1): another person's lock taken off by a supervisor, with the reason; with
## `named`, the lock of `owner` (else the point's earliest).
func remove_lock(work, point, person, reason, owner = null, named := false, slot = null) -> void:
	if named:
		_q(["remove_lock", work, point, person, reason, owner], slot)
	else:
		_q(["remove_lock", work, point, person, reason], slot)


# format 2's trainee inputs for the staff (§17.6)
## The person (null in free mode) has stepped into the lift's cab (§20.3).
func board(lift, person = null, slot = null) -> void:
	_q(["board", lift, person], slot)


## The person has stepped out of the lift's cab (§20.3).
func alight(lift, person = null, slot = null) -> void:
	_q(["alight", lift, person], slot)


func role(person, slot = null) -> void:
	_q(["role", person], slot)


## A session run's player's person handed to the NPCs (§17.13); the host makes it.
func release(slot) -> void:
	_q(["release"], slot)


func task_ack(slot = null) -> void:
	_q(["task_ack"], slot)


func arrive(place, slot = null) -> void:
	_q(["arrive", place], slot)


func leave(place, slot = null) -> void:
	_q(["leave", place], slot)


func read(code, value, slot = null) -> void:
	_q(["read", code, value], slot)


func say(message, to, slot = null) -> void:
	_q(["say", message, to], slot)


func pick(index, slot = null) -> void:
	_q(["pick", index], slot)


func radio_call(role_id, task, work = null, slot = null) -> void:
	_q(["call", role_id, task, work], slot)


func jump(hhmm, slot = null) -> void:
	_q(["jump", hhmm], slot)


## The trainee puts a PPE item on (1) or takes it off (0), at a locker (§17.6, §17.11).
func ppe(item, on, slot = null) -> void:
	_q(["ppe", item, on], slot)


## The trainee entered ("in") or left ("out") a zone (§16.2).
func zone(zone_id, how, slot = null) -> void:
	_q(["zone", zone_id, how], slot)


## The trainee stops an unsafe act of that person's (§16.7, §17.11).
func stop_act(person, slot = null) -> void:
	_q(["stop", person], slot)


# ---------------------------------------------------------------- the players (§17.13)

## The person slot plays, -1 for none (a single-player run's trainee is slot 0's).
func trainee(slot: int = 0) -> int:
	return st_players[slot] if slot >= 0 and slot < SLOTS else -1


## The slot playing person pi, -1 for an NPC.
func slot_of(pi: int) -> int:
	return st_players.find(pi) if pi >= 0 else -1


## The tasks given to slot's person since their last task_ack (0 without one); slot -1: every player's together.
func unacked(slot: int = 0) -> int:
	if slot == -1:
		var t := 0
		for k in SLOTS:
			if st_players[k] != -1:
				t += st_acks[k]
		return t
	return st_acks[slot] if slot >= 0 and slot < SLOTS and st_players[slot] != -1 else 0


## The place slot's person is at, -1 between places, off site or without one.
func t_at(slot: int = 0) -> int:
	var pi := trainee(slot)
	return sp_pos[pi] if pi != -1 else -1


## The plant clock in tenths of a clock second (§16.1): C(n) = S + n × day_scale + J.
func clock() -> int:
	return _S + step_no * _ds + J


## The value a code's `show` binding shows, in the given values.
func shown(code, vals: PackedFloat64Array) -> float:
	var r = _show[code]
	if typeof(r) == TYPE_STRING:
		return vals[ix[r]]
	return float(r)


func fault_code(fid):
	return _fault_kks.get(fid)


## Queues an input in the vectors' form [step, kind, …] (a session run's: [step, kind, …, slot]; the step is not
## checked here).
func apply_input(item: Array) -> void:
	var slot = null
	if st_session:
		slot = item[-1] if item.size() > 2 else null
		item = item.slice(0, -1)
		if slot == null:
			push_error("engine: a session run's input names its slot: " + str(item))
			return
	match item[1]:
		"op":
			if item.size() == 8:
				op(item[2], item[3], item[4], item[5], item[6], item[7], slot)
			else:
				op(item[2], item[3], item[4], item[5], null, null, slot)
		"ack":
			ack(item[2], slot)
		"shelve":
			shelve(item[2], item[3], slot)
		"unshelve":
			unshelve(item[2], slot)
		"fault":
			fault(item[2], slot)
		"repair":
			if item.size() > 3:
				repair_under(item[2], item[3], item[4], slot)
			else:
				repair(item[2], slot)
		"permit":
			permit(item[2], item[3], item[4], slot)
		"lock":
			lock(item[2], item[3], item[4], slot)
		"unlock":
			unlock(item[2], item[3], item[4], slot)
		"remove_lock":
			if item.size() > 6:
				remove_lock(item[2], item[3], item[4], item[5], item[6], true, slot)
			else:
				remove_lock(item[2], item[3], item[4], item[5], null, false, slot)
		"role", "arrive", "leave", "pick", "jump":
			_q([item[1], item[2]], slot)
		"release", "task_ack":
			_q([item[1]], slot)
		"read", "say", "ppe", "zone":
			_q([item[1], item[2], item[3]], slot)
		"stop":
			_q(["stop", item[2]], slot)
		"board", "alight":
			_q([item[1], item[2], item[3]], slot)
		"call":
			radio_call(item[2], item[3], item[4] if item.size() > 4 else null, slot)
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
	if not _skips(i, work):
		cur[i] = x


## Whether a write to a state is skipped: its code is locked (§15.1), and not by isolations all held by the work whose
## own `done` writes it.
func _skips(i: int, work: int = -1) -> bool:
	if code_locks.is_empty():
		return false
	var c = _state_kks.get(i)
	if c == null or not code_locks.has(c):
		return false
	if work == -1:
		return true
	for k in _iso.size():
		if holder[k] == work:
			continue
		var pts: Array = _iso[k][1]
		var off: int = _iso[k][4]
		for p in pts.size():
			if lockbits[off + p] and pts[p][0] == c:
				return true
	return false


## Whether any write of a fault's set or repair would be skipped: such a fault or repair is not made at all (§15.1).
func _blocked(s: Array, work: int = -1) -> bool:
	if code_locks.is_empty():
		return false
	var slots: PackedInt32Array = s[0]
	for k in slots.size():
		if _skips(slots[k], work):
			return true
	return false


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


## Whether an input by `person` lacks authority (§17.1): without staff any person is refused (free mode, person
## null); with staff, a trainee playing a person must name themself, free mode (no trainee person) skips the checks
## for inputs naming no person, and a person's role must have the authority (and for `accept`, the work's
## discipline; `done` and `return` are the acceptor's, or another's with `accept` and the discipline while the
## acceptor is off duty or absent).
func _authority(person, npc: bool, need: String, discipline = null, by_acceptor := false, work = null,
		slot: int = -1) -> bool:
	if _sm == null:
		return person != null
	var tr: int = st_players[_in_slot if slot == -1 else slot]     # the input's player's person (§17.13)
	if person == null:
		return not npc and tr != -1
	if typeof(person) != TYPE_STRING or not _sm.person_ix.has(person):
		return true
	var pi: int = _sm.person_ix[person]
	if not npc and (tr == -1 or pi != tr):
		return true
	var rid: String = _sm.people[pi]["role"]
	if need != "" and not _sm.auth[rid].has(need):     # ("": a rider's, §20.3)
		return true
	if discipline != null and _sm.roles[rid]["discipline"] != discipline:
		return true
	if by_acceptor:
		var acc = acceptor.get(work)
		if acc != null and acc != person:
			var qi: int = _sm.person_ix[acc]
			if sp_on[qi] and not _absent.has(qi):
				return true
	return false


## A board or alight input (§20.3), in step 1: done, refused or unknown, with its event at once.
func _ride(kind: String, lift, person, npc: bool) -> String:
	var k: int = _lift_ix.get(lift, -1) if typeof(lift) == TYPE_STRING else -1
	if k == -1:
		_ev([kind, lift, person, "unknown", []] + ([null if npc else _in_slot] if st_session else []))
		return "unknown"
	var why := []
	if _authority(person, npc, ""):
		why.append("authority")
	var who = _in_slot if person == null else person
	var rs: Array = riders[k]
	var at := -1
	for j in rs.size():
		if Staff._same(who, rs[j]):
			at = j
			break
	if kind == "board":
		var on := false
		for x in riders:
			for r in x:
				if Staff._same(who, r):
					on = true
		if on:
			why.append("aboard")
	elif at == -1:
		why.append("not_aboard")
	var tail := ([null if npc else _in_slot] if st_session else [])
	if not why.is_empty():
		_ev([kind, lift, person, "refused", why] + tail)
		return "refused"
	if kind == "board":
		rs.append(who)
	else:
		rs.remove_at(at)
	lift_quiet[k] = step_no
	cur[_load_slot[k]] = float(m.lifts[k]["person_kg"]) * rs.size()
	_ev([kind, lift, person, "done", []] + tail)
	return "done"


## A permit action (§15.3), in step 1; its outcome.
func _permit(work, action, person, dones: Array, npc := false) -> String:
	if typeof(work) != TYPE_STRING or not m.work_ix.has(work) or typeof(action) != TYPE_STRING \
			or not PERMIT_ACTIONS.has(action):
		_ev(["permit", work, action, person, "unknown", []])
		return "unknown"
	var wi: int = m.work_ix[work]
	var iso: int = _wk[wi][1]
	var spec: Array = PERMIT_ACTIONS[action]
	var why := []
	var acc_action: bool = action == "accept" or action == "done" or action == "return"
	if _authority(person, npc, Staff.PERMIT_AUTH[action], m.works[wi]["discipline"] if acc_action else null,
			action == "done" or action == "return", work):
		why.append("authority")
	if not spec[0].has(pstate[wi]):
		why.append("state")
	if action == "request" and iso != -1 and holder[iso] != -1:
		why.append("iso_busy")
	if not why.is_empty():
		_ev(["permit", work, action, person, "refused", why])
		return "refused"
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
	return "done"


## The trainee's repair under a permit (§15.5), in step 1: true when it is noted for step 3.
func _repair_under(fid, work, person) -> bool:
	var wi: int = m.work_ix.get(work, -1) if typeof(work) == TYPE_STRING else -1
	var fk: int = _fault_ix.get(fid, -1) if typeof(fid) == TYPE_STRING else -1
	if wi == -1 or fk == -1 or _faults[fk][4] == null or typeof(_wk[wi][3]) != TYPE_STRING or _wk[wi][3] != fid:
		_ev(["repair", fid, work, person, "unknown", []])
		return false
	var why := []
	# who may: as the permit's `done` (§15.3, §17.1): the acceptor, or another with `accept` and the work's discipline
	# while they are off duty; without staff, free mode only (person null)
	if _authority(person, false, "accept", m.works[wi]["discipline"], true, work):
		why.append("authority")
	if pstate[wi] != 5:
		why.append("state")
	var k: int = _wk[wi][1]
	if k == -1 or _n_locked(k) < _iso[k][1].size():
		why.append("isolation")     # a repair needs the isolation in place (2026-10-24)
	if not why.is_empty():
		_ev(["repair", fid, work, person, "refused", why])
		return false
	return true


## What a lock would do (§15.6): the trips and priority 1 alarms that come within `horizon` steps with the lock made
## after the inputs already queued, and not without it. Changes nothing in this run.
func lock_effects(work, point, horizon: int = 100, person = null, slot: int = 0) -> Dictionary:
	var a = clone()
	var b = clone()
	a.queue.append(["lock", work, point, person, slot] if st_session else ["lock", work, point, person])
	var na: int = a.events.size()
	var nb: int = b.events.size()
	a.step(horizon)
	b.step(horizon)
	var lock = null
	var ta := {}
	var ra := {}
	for k in range(na, a.events.size()):
		var e: Array = a.events[k]
		if e[0] == step_no + 1 and (e[1] == "lock" or e[1] == "unlock"):
			lock = e[5]
		elif e[1] == "trip":
			ta[e[2]] = true
		elif e[1] == "alarm" and e[3] == "active_unack":
			ra[e[2]] = true
	for k in range(nb, b.events.size()):
		var e: Array = b.events[k]
		if e[1] == "trip":
			ta.erase(e[2])
		elif e[1] == "alarm" and e[3] == "active_unack":
			ra.erase(e[2])
	var trips := []
	for t in m.trips:
		if ta.has(t["id"]):
			trips.append(t["id"])
	var alarms := []
	for x in m.alarms:
		if x["priority"] == 1 and ra.has(x["id"]):
			alarms.append(x["id"])
	return {"lock": lock, "trips": trips, "alarms": alarms}


## The same person (or both null): what an input names is compared with a person id so, whatever its type.
static func _same_person(a, b) -> bool:
	return typeof(a) == typeof(b) and a == b


## Whether a point's locks (an Array of persons) hold one of this person's.
static func _holds(held: Array, person) -> bool:
	for x in held:
		if _same_person(x, person):
			return true
	return false


## A lock, unlock or removal by authority (§15.1), at the start of step 3; its outcome. A point holds the personal
## locks of one or more people, in the order placed (a handover's).
func _lock(kind: String, work, point, person, vals: PackedFloat64Array, npc := false, reason = null,
		named := false, owner = null) -> String:
	var wi: int = m.work_ix.get(work, -1) if typeof(work) == TYPE_STRING else -1
	var k: int = _wk[wi][1] if wi != -1 else -1
	var valid: bool = k != -1 and typeof(point) == TYPE_INT and point >= 0 and point < _iso[k][1].size()
	var key := Vector2i(k, point) if valid else Vector2i(-1, -1)
	var held: Array = lockers.get(key, []) if valid else []
	var tail := []
	if kind == "remove_lock":           # whose lock it was, and why it was removed
		tail = [owner if named else (held[0] if not held.is_empty() else null), reason]
	if not valid or (kind == "remove_lock" and not (typeof(reason) == TYPE_STRING and reason.length() >= 1 \
			and reason.length() <= 200)):
		_ev([kind, work, point, person, "unknown", []] + tail)
		return "unknown"
	var pt: Array = _iso[k][1][point]
	var bit: int = _iso[k][4] + point
	var st := pstate[wi]
	var mine := _holds(held, person)
	var why := []
	if _authority(person, npc, "remove_lock" if kind == "remove_lock" else
			"lock_" + m.isolations[k]["points"][point]["kind"]):
		why.append("authority")
	var ok := false
	if kind == "lock":
		ok = st == 2 or st == 3 or not held.is_empty()   # an added lock (a handover's) at any state that holds it
	elif kind == "unlock":
		ok = st == 2 or st == 3 or st == 7 or st == 10
		if not ok and (st == 4 or st == 5 or st == 6):
			for x in held:
				if not _same_person(x, person):
					ok = true           # a lock of another person stays (a handover's second half)
					break
	else:
		ok = (st >= 2 and st <= 7) or st == 10
	if not ok or holder[k] != wi:
		why.append("state")
	if kind == "lock":
		if mine:
			why.append("locked")
		if held.is_empty() and pt[1] != -1 and vals[pt[1]] < 0.5:
			why.append(names[pt[1]])
	elif held.is_empty():
		why.append("unlocked")
	elif kind == "unlock" and not mine:
		why.append("owner")             # a personal lock is removed only by whoever placed it
	elif kind == "remove_lock" and named and not _holds(held, owner):
		why.append("unlocked")          # the person named holds no lock here
	if not why.is_empty():
		_ev([kind, work, point, person, "refused", why] + tail)
		return "refused"
	if kind == "lock":
		if held.is_empty():
			lockbits[bit] = 1
			code_locks[pt[0]] = code_locks.get(pt[0], 0) + 1
		lockers[key] = held + [person]
	else:
		var who = person if kind == "unlock" else (owner if named else held[0])
		var rest := held.duplicate()
		for j in rest.size():
			if _same_person(rest[j], who):
				rest.remove_at(j)
				break
		if not rest.is_empty():
			lockers[key] = rest
		else:
			lockers.erase(key)
			lockbits[bit] = 0
			code_locks[pt[0]] -= 1
			if code_locks[pt[0]] == 0:
				code_locks.erase(pt[0])
	var c := _n_locked(k)
	cur[_iso[k][2]] = float(c)
	cur[_iso[k][3]] = 1.0 if c == _iso[k][1].size() else 0.0
	if kind != "lock" and st == 10 and c == 0:
		holder[k] = -1      # a cancelled work lets its isolation go with its last lock
	_ev([kind, work, point, person, "done", []] + tail)
	return "done"


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


# ---------------------------------------------------------------- the program as straight-line GDScript

## The program of step 2 written out as GDScript, one statement or a few per node, with every slot and argument as
## a number in the code, so a step runs no dispatch on the node's kind and reads no _ia or _prog_* entry: the same
## operations on the same doubles in the same order as _run (which stays the reference here: step 0, faults' `when`
## nodes, and every step when this could not be compiled). The script depends on the model alone (the main program's
## slots, constants and memory are laid out before any scenario's), so engines of one model share it.
func _gen_fast() -> void:
	if _interpret_only:
		return
	var src := _fast_source()
	var cache: Dictionary = m.get_meta(&"engine_fast", {}) if m is Object else {}
	if cache.has(src):
		_fast = cache[src]      # (null: it did not compile, once is enough)
		return
	var s := GDScript.new()
	s.source_code = src
	if s.reload() == OK:
		_fast = s
	else:
		push_error("engine: the straight-line program did not compile; stepping with the interpreter")
	if m is Object:
		cache[src] = _fast
		m.set_meta(&"engine_fast", cache)


const _FAST_CHUNK := 128        # nodes per generated function (one call per chunk and step)
# past these, a node is a loop (a list's refs) or a call (a table) rather than one expression or an if chain per row:
# Godot's parser and compiler recurse into a long expression or chain (content allows 1024 rows, and lists as long)
const _FAST_TERMS := 16
const _FAST_ROWS := 16
const _FAST_ARGS := "c: PackedFloat64Array, pv: PackedFloat64Array, fa: PackedFloat64Array, ia: PackedInt32Array, mem: PackedInt64Array"


func _fast_source() -> String:
	var out := PackedStringArray(["extends RefCounted", "# generated by engine.gd _fast_source()", "", "const STEP := 0.1", "",
			_FAST_TABLE])
	var calls := PackedStringArray()
	var p := 0
	var fn := 0
	while p < _nprog:
		out.append("static func r%d(%s) -> void:" % [fn, _FAST_ARGS])
		out.append("\tvar x := 0.0\n\tvar y := 0.0\n\tvar s := 0.0\n\tvar u := 0.0\n\tvar w := 0")
		var p1 := mini(p + _FAST_CHUNK, _nprog)
		for q in range(p, p1):
			out.append(_fast_node(q))
		out.append("\tpass\n")
		calls.append("\tr%d(c, pv, fa, ia, mem)" % fn)
		p = p1
		fn += 1
	out.append("static func run(%s) -> void:" % _FAST_ARGS)
	calls.append("\tpass")
	out.append_array(calls)
	return "\n".join(out) + "\n"


## One node's statements (each line starts with a tab), as _run evaluates it in a step (not step 0).
func _fast_node(p: int) -> String:
	var kind := _prog_kind[p]
	var o := _prog_out[p]
	var a := _prog_a[p]
	var na := _prog_na[p]
	var f := _prog_f[p]
	var r := func(k: int) -> int: return _ia[a + k]
	match kind:
		K_GE, K_GT, K_LE, K_LT:
			var op: String = {K_GE: ">=", K_GT: ">", K_LE: "<=", K_LT: "<"}[kind]
			return "\tc[%d] = 1.0 if c[%d] %s c[%d] else 0.0" % [o, r.call(0), op, r.call(1)]
		K_OF:
			return _fast_table(o, r.call(0), _ia[a + 1], _ia[a + 2] == 1, f)
		K_PRODUCT, K_SUM, K_AND, K_OR when na > _FAST_TERMS:
			# _run's loop over the refs, as it is
			var body: String = {K_PRODUCT: "\t\ts = s * c[ia[k]]", K_SUM: "\t\ts = s + c[ia[k]]",
					K_AND: "\t\tif not c[ia[k]] >= 0.5:\n\t\t\ts = 0.0\n\t\t\tbreak",
					K_OR: "\t\tif c[ia[k]] >= 0.5:\n\t\t\ts = 1.0\n\t\t\tbreak"}[kind]
			var s0: String = {K_PRODUCT: "1.0", K_SUM: "0.0", K_AND: "1.0", K_OR: "0.0"}[kind]
			return "\ts = %s\n\tfor k in range(%d, %d):\n%s\n\tc[%d] = s" % [s0, a, a + na, body, o]
		K_PRODUCT, K_SUM:
			var e := "1.0" if kind == K_PRODUCT else "0.0"
			var sym := " * " if kind == K_PRODUCT else " + "
			for k in na:
				e += sym + "c[%d]" % r.call(k)
			return "\tc[%d] = %s" % [o, e]
		K_AND, K_OR:
			var terms := PackedStringArray()
			for k in na:
				terms.append("c[%d] >= 0.5" % r.call(k))
			var cond := " and ".join(terms) if kind == K_AND else " or ".join(terms)
			if na == 0:
				cond = "true" if kind == K_AND else "false"
			return "\tc[%d] = 1.0 if (%s) else 0.0" % [o, cond]
		K_NOT:
			return "\tc[%d] = 0.0 if c[%d] >= 0.5 else 1.0" % [o, r.call(0)]
		K_DIFF:
			return "\tc[%d] = c[%d] - c[%d]" % [o, r.call(0), r.call(1)]
		K_MAX, K_MIN when na > _FAST_TERMS:
			var cmp := ">" if kind == K_MAX else "<"
			return "\ts = c[%d]\n\tfor k in range(%d, %d):\n\t\tx = c[ia[k]]\n\t\tif x %s s:\n\t\t\ts = x\n\tc[%d] = s" % [
					r.call(0), a + 1, a + na, cmp, o]
		K_MAX, K_MIN:
			var lines := PackedStringArray(["\ts = c[%d]" % r.call(0)])
			for k in range(1, na):
				lines.append("\tx = c[%d]" % r.call(k))
				lines.append("\tif x %s s:\n\t\ts = x" % (">" if kind == K_MAX else "<"))
			lines.append("\tc[%d] = s" % o)
			return "\n".join(lines)
		K_SELECT:
			var cases := na - 1
			return ("\tx = c[%d]\n\tw = 0\n\tif x >= %d:\n\t\tw = %d\n\telif x >= 0.0:\n\t\tw = int(floor(x))\n"
					+ "\tc[%d] = c[ia[%d + w]]") % [r.call(0), cases, cases - 1, o, a + 1]
		K_CONST:
			return "\tc[%d] = fa[%d]" % [o, f]
		K_HOLD:
			return "\tif pv[%d] >= 0.5:\n\t\tc[%d] = pv[%d]\n\telse:\n\t\tc[%d] = c[%d]" % [r.call(1), o, o, o, r.call(0)]
		K_LAG:
			return "\tx = pv[%d]\n\ty = pv[%d]\n\tc[%d] = y + (x - y) * (fa[%d] if x >= y else fa[%d])" % [r.call(0), o, o,
					f, f + 1]
		K_INTEGRATE:
			return ("\ty = pv[%d] + fa[%d] * pv[%d] * STEP\n\tif fa[%d] > y:\n\t\ty = fa[%d]\n\tif fa[%d] < y:\n\t\ty = fa[%d]\n"
					+ "\tc[%d] = y") % [o, f, r.call(0), f + 1, f + 1, f + 2, f + 2, o]
		K_RAMP:
			return ("\tx = pv[%d]\n\ty = pv[%d]\n\tif x >= y:\n\t\ts = y + fa[%d]\n\t\tc[%d] = s if s < x else x\n\telse:\n"
					+ "\t\ts = y - fa[%d]\n\t\tc[%d] = s if s > x else x") % [r.call(0), o, f, o, f + 1, o]
		K_TIMER:
			var sl: int = r.call(1)
			return "\tif pv[%d] >= 0.5:\n\t\tmem[%d] += 1\n\telse:\n\t\tmem[%d] = 0\n\tc[%d] = float(mem[%d]) / 10.0" % [
					r.call(0), sl, sl, o, sl]
		K_LATCH:
			return "\tif pv[%d] >= 0.5:\n\t\tc[%d] = 0.0\n\telif pv[%d] >= 0.5:\n\t\tc[%d] = 1.0\n\telse:\n\t\tc[%d] = pv[%d]" % [
					r.call(1), o, r.call(0), o, o, o]
		K_DELAY:
			var sl: int = r.call(1)
			return ("\ty = pv[%d]\n\tif pv[%d] >= 0.5:\n\t\tmem[%d] += 1\n\t\tmem[%d] = 0\n\t\tif y < 0.5 and mem[%d] >= fa[%d]:\n"
					+ "\t\t\ty = 1.0\n\telse:\n\t\tmem[%d] += 1\n\t\tmem[%d] = 0\n\t\tif y >= 0.5 and mem[%d] >= fa[%d]:\n"
					+ "\t\t\ty = 0.0\n\tc[%d] = y") % [o, r.call(0), sl, sl + 1, sl, f, sl + 1, sl, sl + 1, f + 1, o]
		K_WRAP:
			return "\tx = pv[%d] + pv[%d] * STEP\n\ts = fa[%d]\n\tc[%d] = x - s * floor(x / s)" % [o, r.call(0), f, o]
	push_error("engine: unknown node kind %d" % kind)
	return "\tpass"


## A K_OF node: _table unrolled (its loop's every turn is one test here; the same comparisons and arithmetic), or a
## call of the generated script's copy of _table past _FAST_ROWS rows, and for a single row (where _table, given NaN,
## reads past the table: the copy does the same).
func _fast_table(o: int, src: int, cnt: int, step_table: bool, f: int) -> String:
	if cnt > _FAST_ROWS or cnt < 2:
		return "\tc[%d] = table(fa, %d, %d, %s, c[%d])" % [o, f, cnt, "true" if step_table else "false", src]
	var lines := PackedStringArray(["\tu = c[%d]" % src, "\tif u < fa[%d]:" % f, "\t\tc[%d] = fa[%d]" % [o, f + 1]])
	if step_table:
		# y = the y of the last row of the leading run with x <= u (the loop breaks at the first x > u)
		for j in range(1, cnt):
			lines.append("\telif not (fa[%d] <= u):" % (f + 2 * j))
			lines.append("\t\tc[%d] = fa[%d]" % [o, f + 2 * (j - 1) + 1])
		lines.append("\telse:")
		lines.append("\t\tc[%d] = fa[%d]" % [o, f + 2 * (cnt - 1) + 1])
		return "\n".join(lines)
	var last := f + 2 * (cnt - 1)
	lines.append("\telif u >= fa[%d]:" % last)
	lines.append("\t\tc[%d] = fa[%d]" % [o, last + 1])
	# i = the last row of the leading run with x <= u; row 0 always counts (u >= x0 here, or u is NaN and the loop
	# stops at row 0 with i = 0); i = cnt - 1 would need u >= the last x, taken above
	for j in range(1, cnt):
		var i := j - 1
		var x0 := f + 2 * i
		lines.append("\telif not (fa[%d] <= u):" % (f + 2 * j))
		lines.append("\t\tc[%d] = fa[%d] + (fa[%d] - fa[%d]) * (u - fa[%d]) / (fa[%d] - fa[%d])" % [o, x0 + 1, x0 + 3,
				x0 + 1, x0, x0 + 2, x0])
	return "\n".join(lines)


## _table, in the generated script (its arguments as numbers there).
const _FAST_TABLE := """static func table(fa: PackedFloat64Array, f: int, cnt: int, step_table: bool, u: float) -> float:
	if u < fa[f]:
		return fa[f + 1]
	if step_table:
		var y := fa[f + 1]
		for j in cnt:
			if fa[f + 2 * j] <= u:
				y = fa[f + 2 * j + 1]
			else:
				break
		return y
	if u >= fa[f + 2 * (cnt - 1)]:
		return fa[f + 2 * (cnt - 1) + 1]
	var i := 0
	for j in cnt:
		if fa[f + 2 * j] <= u:
			i = j
		else:
			break
	var x0 := fa[f + 2 * i]
	var y0 := fa[f + 2 * i + 1]
	var x1 := fa[f + 2 * i + 2]
	var y1 := fa[f + 2 * i + 3]
	return y0 + (y1 - y0) * (u - x0) / (x1 - x0)
"""


## An NPC's input applied: its result is the NPC's, unless a slot took the person in this step's step 1 (§17.13): then
## the input is applied all the same, but nobody waits on it and its events are no step of the player's.
func _npc_result(pid, r: String, k0: int) -> void:
	var pi: int = _sm.person_ix[pid]
	if st_session and st_players.has(pi):
		for k in range(k0, events.size()):
			_npc_evs[k] = true
	else:
		sp_result[pi] = r


func _step() -> void:
	step_no += 1
	ev_mark = events.size()
	prev = cur.duplicate()
	var moved := {}
	var pressed := []
	var asked := []
	var under := {}         # fault -> the work (its index) under whose permit the trainee repairs it (§15.5)
	var noted := []         # locks and unlocks, made in step 3 (§17.1)
	var dones := []         # works whose permit went to done: their repairs and set in step 3
	# 1. the trainee's inputs, in the order made, then the NPCs' made in the previous step's step 9 (§17.1)
	var q := queue
	queue = []
	var nt := q.size()
	_npc_pending = npc_queue.size()     # a jump waits for the NPCs' inputs of the step before (§17.8)
	_npc_evs = {}
	if not npc_queue.is_empty():
		q = q + npc_queue
		npc_queue = []
	for qi in q.size():
		var item: Array = q[qi]
		var npc := qi >= nt
		var slot := 0
		if st_session and not npc:
			# a session run's input: its slot last (§17.13); one without a slot does nothing, with no event
			var sl = item[-1] if item.size() > 1 else null
			if typeof(sl) != TYPE_INT or sl < 0 or sl >= SLOTS:
				continue
			slot = sl
			item = item.slice(0, -1)
		_in_slot = slot
		var kind: String = item[0]
		if kind == "op":
			var k0 := events.size()
			var r := _op(item, moved, npc)
			if npc:
				_npc_result(item[6], r, k0)
			continue
		if kind == "permit":
			var k0 := events.size()
			var r := _permit(item[1], item[2], item[3], dones, npc)
			if npc:
				_npc_result(item[3], r, k0)
			continue
		if kind == "lock" or kind == "unlock" or kind == "remove_lock":
			noted.append([item, npc, slot])
			continue
		if kind == "board" or kind == "alight":
			_ride(kind, item[1], item[2], npc)
			continue
		if kind == "release" and not st_session:
			continue        # (a session run's input: a single-player run has no slots)
		if kind == "role" or kind == "task_ack" or kind == "arrive" or kind == "leave" or kind == "read" \
				or kind == "say" or kind == "pick" or kind == "call" or kind == "jump" or kind == "ppe" \
				or kind == "zone" or kind == "stop" or kind == "release":
			if _sm != null:
				_sm.t_input(self, item, slot)
			elif kind == "role":
				_ev(["role", item[1], "refused", slot] if st_session else ["role", item[1], "refused"])
			elif kind == "release":
				_ev(["release", null, "refused", slot])
			elif kind == "jump":
				_ev(["jump", clock(), null, "refused"])
			continue
		var ai = _al_ix.get(item[1], -1) if typeof(item[1]) == TYPE_STRING else -1
		if kind == "fault":
			if _v2:
				_ev(["instructor", "fault", item[1]])
			pressed.append(item[1])
		elif kind == "repair" and item.size() > 2:
			if _repair_under(item[1], item[2], item[3]):
				under[item[1]] = m.work_ix[item[2]]
		elif kind == "repair":
			if _v2:
				_ev(["instructor", "repair", item[1]])
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
	if _fast != null:
		_fast.run(cur, prev, _fa, _ia, mem)
	else:
		_run(0, _nprog, cur, prev, false)
	var vals := cur.duplicate()     # conditions in steps 3–7 read the values as step 2 left them
	# 3. the locks and unlocks noted in step 1, in the order made; the permits' automatic moves (§15.3)
	for nd in noted:
		var item: Array = nd[0]
		_in_slot = nd[2]
		var k0 := events.size()
		var r := _lock(item[0], item[1], item[2], item[3], vals, nd[1], item[4] if item.size() > 4 else null,
				item.size() > 5, item[5] if item.size() > 5 else null)
		if nd[1]:
			_npc_result(item[3], r, k0)
	for wi in _wk.size():
		var st := pstate[wi]
		if st < 2 or st > 7 or st == 6:
			continue                # (the levels below move only these: skipped for the step's cost)
		var k: int = _wk[wi][1]
		var c := _n_locked(k) if k != -1 else 0
		var whole: bool = k == -1 or c == _iso[k][1].size()
		var nw := -1
		if st == 2 and whole:
			nw = 3
		elif (st == 3 or st == 4 or st == 5) and not whole:
			nw = 2          # (4, 5: a lock removed by authority suspends the work, §15.3)
		elif st == 7 and c == 0:
			nw = 8
		if nw != -1:
			pstate[wi] = nw
			cur[_wk[wi][2]] = float(nw)
			_ev(["permit", _wk[wi][0], "auto", null, "done", [nw]])
	# then the faults (a trainer's fault is hit only when pressed: with none pressed, only the others are looked at)
	for fk in (_all_faults if not pressed.is_empty() else _auto_faults):
		var fl: Array = _faults[fk]
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
		if hit and not _blocked(fl[3]):
			faults_done[fid] = true
			faults_fixed.erase(fid)
			_apply_set(fl[3])
			_ev(["fault", fid])
	# then the repairs asked, in the scenario's order: a fault applied and not repaired since, with a `repair`; one
	# under a permit (§15.5) writes as its work
	for fl in (_faults if not (asked.is_empty() and under.is_empty()) else []):
		var fid: String = fl[0]
		var wu: int = under.get(fid, -1)
		if wu != -1 and pstate[wu] != 5:
			wu = -1         # suspended in this step's step 3 (§15.5): not made under the permit
			if not asked.has(fid):
				continue
		if fl[4] != null and (wu != -1 or asked.has(fid)) and faults_done.has(fid) and not faults_fixed.has(fid) \
				and not _blocked(fl[4], wu):
			faults_fixed[fid] = true
			_apply_set(fl[4], wu)
			_ev(["repair", fid])
	# then the works whose permit went to done, in the order of their `done`: the fault they repair, their set
	for wi in dones:
		var fid = _wk[wi][3]
		var fk: int = _fault_ix.get(fid, -1) if typeof(fid) == TYPE_STRING else -1
		var wk: int = _wk[wi][1]
		var whole: bool = wk == -1 or _n_locked(wk) == _iso[wk][1].size()
		if fk != -1 and _faults[fk][4] != null and faults_done.has(fid) and not faults_fixed.has(fid) \
				and whole and not _blocked(_faults[fk][4], wi):
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
		if vals[_tr_when[k]] >= 0.5:
			trip_count[k] += 1
		else:
			trip_count[k] = 0
		if trip_count[k] >= _tr_need[k]:
			var t: Array = _tr[k]
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
	var any_lock := not code_locks.is_empty()
	for k in _al.size():
		var sp := _al_sup[k]
		var sup: bool = (sp != -1 and vals[sp] >= 0.5) or (any_lock and code_locks.has(_al[k][6]))
		var sh := shelved[k]
		if sh != -1 and sh <= step_no:
			shelved[k] = -1
			sh = -1
			_ev(["unshelve", _al[k][0]])
		if sup or sh != -1:
			acount[k] = 0
			continue
		var on := vals[_al_when[k]] >= 0.5
		var s: String = astate[k]
		if not on:
			acount[k] = 0
			if s == "normal":
				continue            # (not active: it stays normal; skipped for the step's cost)
		else:
			acount[k] += 1
		var active: bool = acount[k] >= _al_need[k]
		var cl := _al_clear[k]
		var clear: bool = vals[cl] >= 0.5 if cl != -1 else not on
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
			_ev(["alarm", _al[k][0], nw])
	# 9. the staff (§17): they read this step's values and events and write nothing but next step's inputs
	if _sm != null:
		if timing:
			var t9 := Time.get_ticks_usec()
			_sm.step(self)
			staff_us.append(Time.get_ticks_usec() - t9)
		else:
			_sm.step(self)


func _op(item: Array, moved: Dictionary, npc := false) -> String:
	var kks = item[1]
	var do = item[2]
	var value = item[3]
	var trip = item[4]
	var v2 := item.size() == 7          # a version 2 op: where it is made and by whom (§17.1)
	var tail := [item[5], item[6]] if v2 else []
	var key = PlantModel.op_key(kks, do, trip)
	if key == null or not _ops.has(key):
		_ev(["op", kks, do, "unknown", []] + tail)
		return "unknown"
	var c: Dictionary = _ops[key]
	var o: Dictionary = c["o"]
	var failed := []
	if v2:
		var where = item[5]
		if typeof(where) != TYPE_STRING or not o["where"].has(where):
			failed.append("where")
		elif _authority(item[6], npc, "operate_" + where):
			failed.append("authority")
	elif _sm != null and st_players[_in_slot] != -1 and not npc:
		failed.append("authority")      # a trainee playing a person names where and who (§17.1)
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
		_ev(["op", kks, do, "refused", failed] + tail)
		return "refused"
	_ev(["op", kks, do, "done", []] + tail)
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
	return "done"


# ---------------------------------------------------------------- what the vectors compare (§12)

## An alarm suppressed now: by design (its `suppress` value, §7.6) or because its code is locked (§15.1).
func alarm_suppressed(k: int) -> bool:
	var a = _al[k]
	return (a[3] != -1 and cur[a[3]] >= 0.5) or code_locks.has(a[6])


## The isolations' ids locking a code now, in model order (§15.1).
func isolations_locking(code) -> Array:
	return _locking(code).map(func(x): return String(x).trim_suffix("_locked"))


## §7.9, and with a trainee's person no task given to them since their last task_ack (§17.6); in a session run, none
## given to any player's person since their own (§17.13).
func fast_forward() -> bool:
	return ff_model() and (_sm == null or unacked(-1) == 0)


## §7.9: no unacknowledged alarm, no active priority 1 alarm, no machine in a watched state.
func ff_model() -> bool:
	for k in _al.size():
		var s: String = astate[k]
		if s == "normal" or shelved[k] != -1:
			continue            # (a normal alarm blocks nothing: looked at first for the cost, called every step)
		if s == "active_unack" or s == "cleared_unack":
			return false
		if _al[k][5] == 1 and s == "active_ack":
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
		if not m.lifts.is_empty():
			var rd := {}
			for k in m.lifts.size():
				rd[m.lifts[k]["id"]] = riders[k].duplicate()
			s["riders"] = rd
	if _sm != null:
		s["clock"] = clock()
		s["people"] = _sm.snap(self)
		var wa: Array = _sm.snap_acts(self)
		s["worn"] = wa[0]
		s["acts"] = wa[1]
		s["vehicles"] = {}
		s["unacked"] = unacked(-1)
		if st_session:
			var pl := []
			for k in SLOTS:
				if st_players[k] != -1:
					pl.append([k, _sm.people[st_players[k]]["id"], st_acks[k]])
			s["players"] = pl
	if with_values:
		var vals := {}
		for i in n:
			vals[names[i]] = cur[i]
		s["values"] = vals
	return s


# ---------------------------------------------------------------- the state digest (§17.14)

const DIGEST_TAG := "wdp-digest-1\n"

## The state digest of docs/PLANT3D.md §17.14 (docs/plant3d/MULTIPLAYER.md §4): SHA-256 over the tag, the values'
## doubles and the Variant encoding (var_to_bytes) of digest_tree(). Two engines of one model that will go on the same
## way from here have the same digest, on every platform; the reference (ref/plant3d.py state_digest) makes the same.
func digest() -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(DIGEST_TAG.to_ascii_buffer())
	ctx.update(cur.slice(0, n).to_byte_array())
	ctx.update(var_to_bytes(digest_tree()))
	return ctx.finish()


## What the digest covers besides the values (§17.14): every part of the state that the next steps read, in a form
## of its own (sorted where the engine keeps a Dictionary); not the logs (events, inputs), the inputs still queued,
## the previous step's values, the constants, nor what an implementation may keep differently (a task step's own
## progress, the staff step's wake-ups and its next phase 1, the derived locks per code and lockbits).
func digest_tree() -> Array:
	var fo := []
	var groups: Array = first_out.keys()
	groups.sort()
	for g in groups:
		fo.append([g, first_out[g]])
	var fd: Array = faults_done.keys()
	fd.sort()
	var ff: Array = faults_fixed.keys()
	ff.sort()
	var lk := []
	for k in _iso.size():
		for p in _iso[k][1].size():
			if lockbits[_iso[k][4] + p]:
				lk.append([k, p, lockers[Vector2i(k, p)]])
	var tree := [step_no, mem, mstate, latched, trip_count, fo, "|".join(astate), acount, shelved, il_prev, fd, ff,
			pstate, _sorted_pairs(ptw), ptw_count, _sorted_pairs(acceptor), holder, lk, _digest_staff()]
	if not m.lifts.is_empty():          # each lift's riders and quiet step (§20.4), with lifts only
		tree.append(riders)
		tree.append(lift_quiet)
	return tree


func _digest_staff():
	if _sm == null:
		return null
	var np: int = sp_on.size()
	var slots := PackedInt32Array()
	slots.resize(np)
	var insts := []         # every task instance: [person, 0 current / 1 queued / 2 held, …], person by person
	for pi in np:
		slots[pi] = sp_slots[pi].size()
		if sp_cur[pi] != null:
			insts.append(_digest_inst(pi, 0, sp_cur[pi]))
		for x in sp_queue[pi]:
			insts.append(_digest_inst(pi, 1, x))
		for x in sp_held[pi]:
			insts.append(_digest_inst(pi, 2, x))
	var left := PackedInt32Array(st_left.keys())
	left.sort()
	var mk: Array = st_made.keys()
	mk.sort()
	var made := []
	for k in mk:
		made.append([k.x, k.y, k.z, k.w])
	var legs: Array = sp_leg
	if _sm.has_lifts:                   # a ride in the person's way field (§20.4)
		legs = []
		for pi in np:
			var rd: Array = sp_ride[pi]
			legs.append(sp_leg[pi] if rd.is_empty() else ["lift", _sm.lifts[rd[0]][0], rd[1], rd[2], rd[3], rd[4],
					sp_lin[pi]])
	var tree := [J, st_order, st_session, st_players, st_acks, st_t_from, st_kept, _sorted_pairs(st_holder),
			_sorted_pairs(st_given), st_vprev, st_pending, left, made, npc_queue, sp_on, sp_duty, sp_duties, sp_planned,
			slots, sp_pos, legs, insts, sp_res, sp_occ, sp_result, sp_rng, sp_worn, sp_acts, sp_zin]
	if _sm.has_lifts:
		tree.append(sp_stairs)          # the stairs being walked instead of a ride
	return tree


## A task instance in the digest: its person, where it is (0 current, 1 queued, 2 held) and everything but its step's
## own progress ("st").
static func _digest_inst(pi: int, where: int, x: Dictionary) -> Array:
	return [pi, where, x["task"], x["prio"], x["made"], x["order"], x["step"], x["work"], x["code"], x["alarm"],
			x["src"], x["idle"], x["started"], x["int"], x["owner"], x["act"], x.get("orig")]


static func _sorted_pairs(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	var out := []
	for k in keys:
		out.append([k, d[k]])
	return out


## The values in slot order (declared, ext, machine states, trip latches), as doubles.
func value_array() -> PackedFloat64Array:
	return cur.slice(0, n)


## An independent copy at the same step (forks of a run: one cold start, many trip tests).
func clone():
	var c = get_script().new()
	for k in ["m", "sc", "names", "ix", "n", "_prog_kind", "_prog_out", "_prog_a", "_prog_na", "_prog_f", "_ia",
			"_fa", "_nprog", "_fast", "_fault_nodes", "_scratch", "_init_vals", "_nmem", "_il", "_mc", "_mc_ix", "_tr", "_tr_ix", "_al", "_al_ix",
			"_faults", "_fault_ix", "_auto_faults", "_all_faults", "_tr_when", "_tr_need", "_al_when", "_al_clear",
			"_al_sup", "_al_need", "_ops", "_iso", "_wk", "_state_kks", "_v2", "step_no", "ptw_count",
			"_sm", "_S", "_ds", "_absent", "_fixed_trainee", "_show", "_fault_kks", "J", "ev_mark", "st_order",
			"st_session", "st_next1", "_lift_ix", "_load_slot"]:
		c.set(k, get(k))
	for k in ["cur", "prev", "mem", "mstate", "latched", "trip_count", "acount", "shelved", "il_prev", "pstate", "holder",
			"lockbits", "st_players", "st_acks", "st_t_from", "sp_on", "sp_planned", "sp_pos", "sp_res", "sp_occ", "sp_rng", "sp_wake", "sp_worn",
			"sp_zin", "lift_quiet", "sp_lin"]:
		c.set(k, get(k).duplicate())        # packed arrays: a copy of their own
	for k in ["first_out", "astate", "faults_done", "faults_fixed", "queue", "events", "inputs", "ptw", "acceptor",
			"lockers", "code_locks", "npc_queue", "st_t_in", "st_jumped", "st_holder", "st_given", "st_vprev", "st_kept",
			"st_left", "st_pending", "st_made",
			"sp_duty", "sp_duties", "sp_slots", "sp_leg", "sp_cur", "sp_queue", "sp_result", "sp_held", "sp_acts",
			"riders", "sp_ride", "sp_stairs"]:
		c.set(k, get(k).duplicate(true))
	return c
