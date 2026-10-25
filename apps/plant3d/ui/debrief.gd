## The debrief (docs/PLANT3D.md §7.6 and §8): what happened in a run, read from the engine's event list. Every
## operation (done, refused, or not one of the plant's), alarm change (raised, acknowledged, cleared, shelved and
## back), trip (with its group's first out), trainer's fault and its repair, interlock and sequence step, permit to
## work's step and isolation's lock (PLANT3D §15), in order
## with its model time; with a procedure, the steps as they ended, and each operation made outside its step marked
## as a deviation with the step it was made in and the one it belongs to. The run is the procedure's (from when it
## began) or, with none, the plant's since it (re)started. Pure data: ui/debrief_panel.gd shows it.
extends RefCounted

const W = preload("res://ui/widgets.gd")
const Permits = preload("res://ui/permits.gd")

## Why the trainee's repair under a permit was refused (PLANT3D §15.5).
const REPAIR_WHY := {"state": "its permit to work was not accepted", "authority": "not this person's to do",
		"isolation": "its isolation was not in place"}
const ALARM_WORDS := {
	"normal>active_unack": "raised", "cleared_unack>active_unack": "raised again",
	"active_unack>active_ack": "acknowledged", "cleared_unack>normal": "acknowledged after it cleared",
	"active_unack>cleared_unack": "cleared, not yet acknowledged", "active_ack>normal": "cleared",
}


## {entries: [{step, kind, text, code, dev, prio}], summary: {…}, title}. `kind`: op, alarm, shelve, unshelve, trip,
## fault, repair, interlock, machine, permit, lock, unlock, remove_lock (a lock removed by authority), early (the
## trainee's action made before its task step, counted when the step came: out of order, a deviation), instructor
## (an instructor's input, PLANT3D §15.5: the fault or repair it made, if any, is marked too), step (a procedure step
## that ended), start (the procedure began). `dev` is ""
## or the deviation in words; `prio` an alarm's or trip's priority (0 otherwise).
static func collect(engine, info, tracker) -> Dictionary:
	var m = info.m
	var proc: Dictionary = tracker.proc if tracker != null else {}
	var from := 0
	var from_step := 0
	var to: int = engine.events.size()
	if not proc.is_empty():
		from = tracker.ev_from
		from_step = tracker.begin_step
		if tracker.ev_to != -1:
			to = mini(to, tracker.ev_to)     # the procedure's run ends where it was finished or stopped
	var alarm_by := {}
	for a in m.alarms:
		alarm_by[a["id"]] = a
	var devs := {}
	if tracker != null:
		for d in tracker.deviations:
			if d.size() > 4 and int(d[2]) >= 0:
				devs[int(d[2])] = d
	var sm := {"ops": 0, "refused": 0, "deviations": 0, "raised": 0, "prio": {1: 0, 2: 0, 3: 0}, "acked": 0,
			"shelved": 0, "trips": 0, "first_out": PackedStringArray(), "faults": 0, "repairs": 0, "permits": {},
			"locks": 0, "unlocks": 0, "permit_refused": 0, "by_authority": 0, "early": 0, "instructor": 0,
			"instructor_run": instructor_count(engine), "unsafe": 0, "stopped": 0, "stopped_me": 0}
	var by_instructor := {}             # "fault|id" or "repair|id" -> the step of the instructor's input
	var state := {}                     # alarm id -> its state (from step 0: the run may begin later)
	var inputs: Array = engine.inputs
	var in_i := 0
	var out: Array = []
	var evs: Array = engine.events
	var then := Permits.replay(engine)    # each permit event's number and state as they were
	var locked := {}                       # code -> points locked on it, as the events go (an interlock's skipped writes)
	for i in to:
		var ev: Array = evs[i]
		var inp := []
		if ev[1] == "op":               # the op events of a step come in the order their inputs were made
			while in_i < inputs.size():
				var c: Array = inputs[in_i]
				in_i += 1
				if c[1] == "op" and c[0] == ev[0]:
					inp = c
					break
		var prev: String = state.get(ev[2], "normal") if ev[1] == "alarm" else ""
		if ev[1] == "alarm":
			state[ev[2]] = ev[3]
		if (ev[1] == "lock" or ev[1] == "unlock" or ev[1] == "remove_lock") and ev[5] == "done" \
				and typeof(ev[2]) == TYPE_STRING \
				and m.work_ix.has(ev[2]) and m.works[m.work_ix[ev[2]]].has("isolation"):
			var pts: Array = m.isolations[m.isolation_ix[m.works[m.work_ix[ev[2]]]["isolation"]]]["points"]
			var lc: String = pts[int(ev[3])]["kks"]
			locked[lc] = locked.get(lc, 0) + (1 if ev[1] == "lock" else -1)
		if i < from:
			continue
		var e := {"step": int(ev[0]), "kind": str(ev[1]), "text": "", "code": "", "dev": "", "prio": 0}
		match ev[1]:
			"op":
				e.code = str(ev[2])
				var o = m.op_keys.get(m.op_key(ev[2], ev[3], inp[5] if inp.size() > 5 else null))
				var what: String = info.op_label(o) if o != null else str(ev[3])
				if o != null and inp.size() > 4 and inp[4] != null and o["do"] == "set":
					what += " to " + value_text(o, inp[4])
				match ev[4]:
					"done":
						e.text = "%s %s" % [ev[2], what]
						sm.ops += 1
					"refused":
						var why := PackedStringArray()
						for f in ev[5]:
							why.append(refusal(info, o, String(f), engine))
						e.text = "%s %s: refused (%s)" % [ev[2], what, "; ".join(why)]
						sm.refused += 1
					_:
						e.text = "%s %s: not an operation of this plant" % [str(ev[2]), str(ev[3])]
				if devs.has(i):
					e.dev = deviation_text(devs[i], proc)
					sm.deviations += 1
			"alarm":
				var a: Dictionary = alarm_by.get(ev[2], {})
				e.code = String(a.get("kks", a.get("where", "")))
				e.prio = int(a.get("priority", 3))
				var how: String = ALARM_WORDS.get(prev + ">" + str(ev[3]), str(ev[3]).replace("_", " "))
				e.text = "Alarm %s: %s" % [how, _alarm_name(a, ev[2])]
				if how.begins_with("raised"):
					sm.raised += 1
					sm.prio[e.prio] = sm.prio.get(e.prio, 0) + 1
				elif how.begins_with("acknowledged"):
					sm.acked += 1
			"shelve":
				var a: Dictionary = alarm_by.get(ev[2], {})
				e.code = String(a.get("kks", a.get("where", "")))
				e.text = "Alarm shelved for %s: %s" % [W.model_time(int(round(float(ev[3]) * 10.0))), _alarm_name(a, ev[2])]
				sm.shelved += 1
			"unshelve":
				var a: Dictionary = alarm_by.get(ev[2], {})
				e.code = String(a.get("kks", a.get("where", "")))
				e.text = "Alarm back from the shelf: %s" % _alarm_name(a, ev[2])
			"trip":
				var t = m.trip_by_id(ev[2])
				e.code = String(t.get("kks", "")) if t != null else ""
				e.prio = 1
				var name: String = t.get("text", ev[2]) if t != null else str(ev[2])
				e.text = "TRIP: %s%s" % [name, " (first out)" if ev[3] else ""]
				sm.trips += 1
				if ev[3]:
					sm.first_out.append(name)
			"instructor":
				# instructor mode is open to anyone, but every action of it is visible (the user, 2026-10-24)
				e.code = fault_kks(m, str(ev[3]), engine.sc)
				e.text = "By the instructor: %s %s" % ["fault pressed:" if ev[2] == "fault" else "repair asked:",
						fault_text(m, str(ev[3]), engine.sc)]
				by_instructor[str(ev[2]) + "|" + str(ev[3])] = int(ev[0])
				sm.instructor += 1
			"fault":
				e.text = "Fault: %s" % fault_text(m, str(ev[2]), engine.sc)
				e.code = fault_kks(m, str(ev[2]), engine.sc)
				if by_instructor.get("fault|" + str(ev[2]), -1) == int(ev[0]):
					e.text += " (by the instructor)"
				sm.faults += 1
			"repair":
				e.code = fault_kks(m, str(ev[2]), engine.sc)
				if ev.size() >= 7 and ev[6] is Array:     # the trainee's repair under a permit, refused or unknown (§15.5)
					e.text = "Repair not made: %s (%s)" % [fault_text(m, str(ev[2]), engine.sc),
							"; ".join(ev[6].map(func(x): return REPAIR_WHY.get(x, str(x)))) if ev[5] == "refused"
							else "not a repair of that permit's work"]
				else:
					e.text = "Repaired: %s" % fault_text(m, str(ev[2]), engine.sc)
					if by_instructor.get("repair|" + str(ev[2]), -1) == int(ev[0]):
						e.text += " (by the instructor)"
					sm.repairs += 1
			"interlock":
				var il := {}
				for x in m.interlocks:
					if x["id"] == ev[2]:
						il = x
				e.code = String(il.get("kks", ""))
				e.text = "Interlock: %s" % il.get("text", ev[2])
				# its writes to a locked-out code were skipped (§15.1): the standby pump didn't start
				var skipped := PackedStringArray()
				for d in il.get("do", []):
					for name in (d.get("set", {}) as Dictionary):
						var c = engine._state_kks.get(engine.ix.get(name, -1))
						if c != null and locked.get(c, 0) > 0 and not skipped.has(c):
							skipped.append(c)
				if not skipped.is_empty():
					e.text += " (not carried out on %s: locked out)" % ", ".join(skipped)
			"unsafe", "safe", "stop":
				# milestone S2: unsafe acts (PLANT3D §16.7) and work stopped (§17.11), everyone's: whose they were,
				# and the trainee's own counted
				var sm_ = engine._sm
				var me_id: String = sm_.people[engine.st_trainee]["id"] if sm_ != null and engine.st_trainee != -1 else ""
				e.text = safety_text(sm_, ev)
				if ev[1] == "unsafe" and ev[2] == me_id:
					e.dev = "your unsafe act"
					sm.unsafe += 1
				elif ev[1] == "stop" and ev[6] == "done" and ev[2] == me_id:
					sm.stopped += 1
				elif ev[1] == "stop" and ev[6] == "done" and ev[3] == me_id:
					sm.stopped_me += 1
			"task":
				# the trainee's own tasks (PLANT3D §18.7: the debrief's role tab): given, done, abandoned, skipped
				var sm_ = engine._sm
				if sm_ == null or engine.st_trainee == -1 or ev[2] != sm_.people[engine.st_trainee]["id"]:
					continue
				var tt = sm_.tasks[ev[3]]["title"] if sm_.tasks.has(ev[3]) else str(ev[3])
				e.text = "Your task %s: %s" % [{"start": "begun", "done": "done", "abandoned": "ABANDONED",
						"skipped": "skipped", "held": "held to your next duty", "resumed": "resumed"}.get(ev[4], ev[4]), tt]
			"early":
				# §17.8: an action of the trainee's made before its task step, counted when the step came
				var sm_ = engine._sm
				var tt = sm_.tasks[ev[3]]["title"] if sm_ != null and sm_.tasks.has(ev[3]) else str(ev[3])
				e.text = "%s, step %d: done before its step (made at %s)" % [tt, int(ev[4]) + 1,
						W.model_time(int(ev[6]))]
				e.dev = "done out of order: before its step was current"
				sm.early += 1
			"permit", "lock", "unlock", "remove_lock":
				var wid = ev[2]
				var wd: Dictionary = m.works[m.work_ix[wid]] if typeof(wid) == TYPE_STRING and m.work_ix.has(wid) else {}
				e.code = String(wd.get("kks", ""))
				e.text = Permits.event_text(engine, ev, then.get(i, []))
				if ev[5] != "done":
					sm.permit_refused += 1
				elif ev[1] == "lock":
					sm.locks += 1
				elif ev[1] == "unlock":
					sm.unlocks += 1
				elif ev[1] == "remove_lock":
					sm.unlocks += 1
					sm.by_authority += 1
				if ev[1] == "permit" and ev[5] == "done" and not wd.is_empty():
					sm.permits[wid] = int(ev[6][0]) if ev[3] == "auto" else Permits.ACTIONS_TO.get(ev[3], 0)
			"machine":
				var mi: int = info.machine_index(ev[2])
				var say := ""
				if mi >= 0:
					var k: int = m.machines[mi]["_ids"].find(ev[4])
					if k >= 0:
						say = m.machines[mi]["states"][k].get("say", "")
				e.text = say if say != "" else "%s: %s" % [str(ev[2]).replace("_", " "), str(ev[4]).replace("_", " ")]
			_:
				e.text = " ".join(ev.slice(1).map(func(x): return str(x)))
		out.append(e)
	var steps: Array = proc.get("steps", [])
	if not proc.is_empty():
		out.push_front({"step": from_step, "kind": "start", "text": "Began: %s" % proc.get("title", proc.get("id", "")),
				"code": "", "dev": "", "prio": 0})
		# each step that ended, after the events of the model step it ended in
		var j := 0
		for lg in tracker.log:
			var k := -1
			for s in steps.size():
				if steps[s]["id"] == lg[0]:
					k = s
			var se := {"step": int(lg[1]), "kind": "step", "code": "", "dev": "", "prio": 0,
					"text": "Step %d of %d done: %s" % [k + 1, steps.size(), step_name(steps[k]) if k >= 0 else lg[0]]}
			while j < out.size() and out[j].step <= se.step:
				j += 1
			out.insert(j, se)
			j += 1
		if tracker.stopped:
			out.append({"step": tracker.end_step, "kind": "start", "code": "", "dev": "", "prio": 0,
					"text": "Stopped at step %d of %d" % [tracker.stopped_at + 1, steps.size()]})
	var end: int = engine.step_no
	if not proc.is_empty() and tracker.end_step != -1:
		end = tracker.end_step
	sm["time"] = maxi(0, end - from_step)
	sm["steps_done"] = tracker.log.size() if not proc.is_empty() else 0
	sm["steps"] = steps.size()
	sm["finished"] = tracker != null and tracker.finished()
	sm["stopped"] = tracker != null and tracker.stopped
	sm["began_at"] = tracker.begin_index if not proc.is_empty() else 0
	var title := ("Debrief: " + String(proc.get("title", ""))) if not proc.is_empty() else "Events since the plant started"
	if sm.instructor_run > 0:
		title += " · instructor mode used"
	return {"entries": out, "summary": sm, "title": title, "procedure": not proc.is_empty()}


## The instructor's actions in the whole run (their `instructor` events, PLANT3D §15.5): a run with any used
## instructor mode, and says so.
static func instructor_count(engine) -> int:
	var n := 0
	for ev in engine.events:
		if ev[1] == "instructor":
			n += 1
	return n


## The line that opens the debrief of a run that used instructor mode ("" for none).
static func instructor_line(n: int) -> String:
	if n == 0:
		return ""
	return "This run used instructor mode: %d instructor action%s (marked below)" % [n, "" if n == 1 else "s"]


static func _alarm_name(a: Dictionary, id) -> String:
	if a.is_empty():
		return String(id)
	return "%s %s %s" % [a.get("isa", "—"), a.get("kks", a.get("where", "")), a.get("text", id)]


## A set value as the trainee typed it: per cent for a 0–1 command, the number otherwise.
static func value_text(o: Dictionary, v) -> String:
	if typeof(v) not in [TYPE_INT, TYPE_FLOAT]:
		return str(v)
	if o.get("range", []) == [0, 1]:
		return "%s %%" % str(snappedf(float(v) * 100.0, 0.01)).trim_suffix(".0")
	return str(v)


## Why an op was refused, as it stood then (a permissive's sentence; a sequence's state is not kept, so no state).
static func refusal(info, o, failed: String, engine) -> String:
	if o == null:
		return failed
	if o.has("machine") and failed == o["machine"] + "_state":
		return "the sequence was not at a state that takes \"%s\"" % o["do"]
	return info.failed_text(o, failed, engine)


## The equipment a fault is repaired at ("" when the content names none): the run's scenario's first.
static func fault_kks(m, fid: String, run_sc := {}) -> String:
	for sc in [run_sc] + m.scenarios.values():
		for f in sc.get("faults", []):
			if f.get("id", "") == fid:
				return String(f.get("kks", ""))
	return ""


static func fault_text(m, fid: String, run_sc := {}) -> String:
	for sc in [run_sc] + m.scenarios.values():
		for f in sc.get("faults", []):
			if f.get("id", "") == fid:
				return String(f.get("text", fid))
	return fid


## A procedure step in a few words: the start of its text, as plain text.
static func step_name(s: Dictionary) -> String:
	var t := plain(s.get("text", [])).strip_edges()
	return t if t.length() <= 70 else t.left(67).strip_edges() + "…"


static func plain(r) -> String:
	if typeof(r) == TYPE_STRING:
		return r
	if typeof(r) == TYPE_DICTIONARY:
		for k in ["b", "i", "small", "term", "link"]:
			if r.has(k):
				return plain(r[k])
		return String(r.get("num", ""))
	if typeof(r) != TYPE_ARRAY:
		return ""
	var out := ""
	for it in r:
		out += plain(it)
	return out


## A deviation in words: the step it was made in and the one it belongs to (tracker.deviations' row).
static func deviation_text(d: Array, proc: Dictionary) -> String:
	var steps: Array = proc.get("steps", [])
	var made: int = int(d[3])
	var home: int = int(d[4])
	var n := steps.size()
	if home >= 0 and home != made and home < n:
		return "DEVIATION in step %d of %d: this belongs to step %d (%s)" % [made + 1, n, home + 1, step_name(steps[home])]
	if home == made and made >= 0:
		return "DEVIATION in step %d of %d: %s" % [made + 1, n, d[1]]
	return "DEVIATION in step %d of %d: no step of the procedure asks for it" % [made + 1, n]


## The summary in a few lines.
static func summary_lines(d: Dictionary) -> PackedStringArray:
	var sm: Dictionary = d.summary
	var out := PackedStringArray()
	if sm.get("instructor_run", 0) > 0:
		out.append(instructor_line(sm.instructor_run))
	out.append("Time: %s of plant time" % W.model_time(sm.time))
	if d.procedure:
		out.append("Steps: %d of %d done%s%s" % [sm.steps_done, sm.steps,
				(" (began at step %d)" % (sm.began_at + 1)) if sm.began_at > 0 else "",
				"" if sm.finished else (", then stopped" if sm.stopped else " so far")])
	out.append("Operations: %d done%s; %d outside their step" % [sm.ops,
			(", %d refused" % sm.refused) if sm.refused > 0 else "", sm.deviations] if d.procedure else
			"Operations: %d done%s" % [sm.ops, (", %d refused" % sm.refused) if sm.refused > 0 else ""])
	if sm.raised == 0:
		out.append("Alarms: none raised%s%s" % [(", %d acknowledged" % sm.acked) if sm.acked > 0 else "",
				(", %d shelved" % sm.shelved) if sm.shelved > 0 else ""])
	else:
		var by := PackedStringArray()
		for p in [1, 2, 3]:
			if sm.prio.get(p, 0) > 0:
				by.append("priority %d: %d" % [p, sm.prio[p]])
		out.append("Alarms: %d raised (%s), %d acknowledged%s" % [sm.raised, ", ".join(by), sm.acked,
				(", %d shelved" % sm.shelved) if sm.shelved > 0 else ""])
	if sm.trips == 0:
		out.append("Trips: none")
	else:
		out.append("Trips: %d%s" % [sm.trips, (" (first out: %s)" % ", ".join(sm.first_out)) if not sm.first_out.is_empty() else ""])
	if sm.faults > 0:
		out.append("Trainer's faults: %d" % sm.faults)
	if sm.repairs > 0:
		out.append("Repairs: %d" % sm.repairs)
	if not sm.permits.is_empty():
		var by := PackedStringArray()
		for wid in sm.permits:
			by.append("%s %s" % [wid, Permits.STATE_WORDS[sm.permits[wid]].to_lower()])
		out.append("Permits to work: %d (%s); locks made %d, removed %d%s%s" % [sm.permits.size(), ", ".join(by),
				sm.locks, sm.unlocks, (" (%d by authority)" % sm.by_authority) if sm.by_authority > 0 else "",
				(", %d refused" % sm.permit_refused) if sm.permit_refused > 0 else ""])
	elif sm.permit_refused > 0:
		out.append("Permits to work: %d refused" % sm.permit_refused)
	if sm.get("unsafe", 0) > 0 or sm.get("stopped", 0) > 0 or sm.get("stopped_me", 0) > 0:
		out.append("Safety: your unsafe acts %d%s; work you stopped %d" % [sm.unsafe,
				(" (%d stopped by HSE)" % sm.stopped_me) if sm.stopped_me > 0 else "", sm.stopped])
	if sm.early > 0:
		out.append("Done out of order: %d (made before their task step, counted when it came)" % sm.early)
	return out


## An unsafe act's start or end, or work stopped (PLANT3D §16.7, §17.11), in words.
static func safety_text(sm, ev: Array) -> String:
	var who := func(pid) -> String:
		return sm.people[sm.person_ix[pid]]["call"] if sm != null and sm.person_ix.has(pid) else str(pid)
	var what := func(kind, det) -> String:
		match kind:
			"ppe": return "without all the PPE of %s" % str(det)
			"permit": return "working before the permit of %s was accepted" % str(det)
			_: return "a shortcut" + (" on %s" % str(det) if det != null else "")
	match ev[1]:
		"unsafe":
			return "Unsafe act: %s, %s" % [who.call(ev[2]), what.call(ev[3], ev[4])]
		"safe":
			return "Unsafe act ended: %s, %s" % [who.call(ev[2]), what.call(ev[3], ev[4])]
	if ev[6] == "done":
		return "Work stopped by %s: %s, %s" % [who.call(ev[2]), who.call(ev[3]), what.call(ev[4], ev[5])]
	return "Stop refused (%s): %s by %s" % [", ".join(ev[7].map(func(x): return {"authority": "no authority to stop "
			+ "work", "no_act": "no unsafe act going on"}.get(x, str(x)))), who.call(ev[3]), who.call(ev[2])]
