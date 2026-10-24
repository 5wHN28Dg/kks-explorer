## Permits to work and isolations (docs/PLANT3D.md §15) in words: what the permit form (ui/permit_panel.gd), the
## cards, the screens and the debrief say about them, read from the engine (sim/engine.gd keeps their state). Pure
## data, no nodes.
##
## Free mode (no staff yet, §17.1): the trainee does every step of a permit, as each role in turn; the form names the
## role whose step it is.
extends RefCounted

const W = preload("res://ui/widgets.gd")

const STATE_WORDS := ["No permit", "Requested", "Approved", "Isolated", "Issued", "Accepted: work may start",
		"Work done", "Returned", "De-isolated", "Closed", "Cancelled"]
const SHORT := ["", "REQUESTED", "APPROVED", "ISOLATED", "ISSUED", "ACCEPTED", "DONE", "RETURNED", "DE-ISOLATED",
		"CLOSED", "CANCELLED"]
# the actions in the order the form offers them, each with the states it is taken in (§15.3)
const ACTIONS := [["request", [0, 9, 10]], ["approve", [1]], ["issue", [3]], ["accept", [4]], ["done", [5]],
		["return", [6]], ["close", [8]], ["cancel", [1, 2, 3]]]
const ACTIONS_TO := {"request": 1, "approve": 2, "issue": 4, "accept": 5, "done": 6, "return": 7, "close": 9,
		"cancel": 10}
const ACTION_WORDS := {"request": "Request the permit", "approve": "Approve", "issue": "Issue the permit",
		"accept": "Accept the permit", "done": "Work done", "return": "Hand the permit back",
		"close": "Close the permit", "cancel": "Cancel the permit", "auto": "Moved by itself"}
const DONE_WORDS := {"request": "requested", "approve": "approved", "issue": "issued", "accept": "accepted",
		"done": "work done", "return": "handed back", "close": "closed", "cancel": "cancelled"}
const DISCIPLINES := {"mech": "mechanical", "elec": "electrical", "inst": "instrument (I&C)", "chem": "chemistry",
		"civil": "civil"}
const PERMIT_KINDS := {"general": "General permit to work", "electrical": "Electrical permit to work",
		"hot": "Hot work permit", "confined": "Confined space entry permit"}
const KIND_WORDS := {"electrical": "electrical", "mechanical": "mechanical", "process": "process",
		"instrument": "instrument"}
# who does each step on site (STAFF.md §1): free mode plays them in turn
const TECH := {"mech": "mechanical technician", "elec": "electrical technician", "inst": "I&C technician",
		"chem": "chemist", "civil": "contractor supervisor"}
const LOCKER := {"electrical": "electrical authorised person", "mechanical": "field operator",
		"process": "field operator", "instrument": "I&C technician"}


## The role whose step an action is (free mode plays each in turn).
static func role_of(action: String, work: Dictionary) -> String:
	match action:
		"approve", "issue", "close", "cancel":
			return "shift supervisor"
		"request":
			return "maintenance supervisor" if work.get("discipline", "") != "civil" else "contractor supervisor"
	return TECH.get(work.get("discipline", ""), "technician")


static func work_index(e, wid: String) -> int:
	return e.m.work_ix.get(wid, -1)


static func state_of(e, wid: String) -> int:
	var wi := work_index(e, wid)
	return e.pstate[wi] if wi >= 0 else 0


static func number_of(e, wid: String) -> String:
	return String(e.ptw.get(wid, ""))


## The isolation of a work (its dictionary) or {}.
static func isolation_of(e, work: Dictionary) -> Dictionary:
	if not work.has("isolation"):
		return {}
	return e.m.isolations[e.m.isolation_ix[work["isolation"]]]


static func point_locked(e, iso_id: String, p: int) -> bool:
	var k: int = e.m.isolation_ix[iso_id]
	return e.lockbits[e._iso[k][4] + p] == 1


## [[isolation id, point index, work id holding it or "", its permit number]] for every locked point on a code.
static func locks_on(e, code: String) -> Array:
	var out := []
	if not e.code_locks.has(code):
		return out
	for k in e.m.isolations.size():
		var x: Dictionary = e.m.isolations[k]
		for p in x["points"].size():
			if x["points"][p]["kks"] == code and e.lockbits[e._iso[k][4] + p] == 1:
				var h: int = e.holder[k]
				var wid: String = e.m.works[h]["id"] if h >= 0 else ""
				out.append([x["id"], p, wid, number_of(e, wid) if wid != "" else ""])
	return out


## The words a screen or card shows for a locked code: "ISOLATED PTW-0002" (an instrument), "LOCKED OUT PTW-0001";
## "" when nothing locks it.
static func lock_text(e, code: String) -> String:
	var ls := locks_on(e, code)
	if ls.is_empty():
		return ""
	var nums := PackedStringArray()
	var instrument := true
	for l in ls:
		if l[3] != "" and not nums.has(l[3]):
			nums.append(l[3])
		var x: Dictionary = e.m.isolations[e.m.isolation_ix[l[0]]]
		if x["points"][l[1]]["kind"] != "instrument":
			instrument = false
	return ("ISOLATED" if instrument else "LOCKED OUT") + ((" " + ", ".join(nums)) if not nums.is_empty() else "")


## The works on a piece of equipment: those of its code and those whose isolation has a point on it.
static func works_at(e, code: String) -> Array:
	var out := []
	for w in e.m.works:
		if w["kks"] == code:
			out.append(w)
			continue
		var x := isolation_of(e, w)
		for pt in x.get("points", []):
			if pt["kks"] == code:
				out.append(w)
				break
	return out


## The work whose permit repairs a fault (PLANT3D §15.5): its `repairs` names it; {} when none does.
static func work_repairing(e, fid: String) -> Dictionary:
	for w in e.m.works:
		if w.get("repairs", "") == fid:
			return w
	return {}


## A refusal's reason (a word of §17.7, or a `safe` value's name) in words.
static func reason_text(e, work: Dictionary, why: String, point := -1, state := -1) -> String:
	match why:
		"state":
			var st: int = state if state >= 0 else state_of(e, work["id"])
			return "not at this point of the permit (it is %s)" % STATE_WORDS[st].to_lower()
		"iso_busy":
			var x := isolation_of(e, work)
			var k: int = e.m.isolation_ix.get(x.get("id", ""), -1)
			var h: int = e.holder[k] if k >= 0 else -1
			if h >= 0 and e.m.works[h]["id"] != work["id"]:
				return "its isolation is held by another permit (%s, %s)" % [number_of(e, e.m.works[h]["id"]),
						e.m.works[h]["title"]]
			return "its isolation still has points locked: remove them first"
		"authority":
			return "that is not your role's to do"
		"locked":
			return "it is locked already"
		"unlocked":
			return "it is not locked"
		"owner":
			return "it is another person's lock: only whoever placed it removes it (a supervisor may, by authority)"
	var x := isolation_of(e, work)
	if point >= 0 and point < x.get("points", []).size():
		return "not safe to lock yet: %s" % String(x["points"][point]["how"]).to_lower()
	return why


## How each permit, lock or unlock event found its work (the engine keeps only the present): replays the run's events
## from the start, where every permit is at 0 and numbers start at PTW-0001 (sim/engine.gd). {event index: [the work's
## permit number then ("" before its first request), its permit state just before the event]}.
static func replay(e) -> Dictionary:
	var out := {}
	var st := {}
	var nums := {}
	var count := 0
	for i in e.events.size():
		var ev: Array = e.events[i]
		if not is_permit_event(ev):
			continue
		var wid := str(ev[2])
		var before: int = st.get(wid, 0)
		if ev[1] == "permit" and ev[5] == "done":
			if ev[3] == "auto":
				st[wid] = int(ev[6][0])
			elif ACTIONS_TO.has(ev[3]):
				st[wid] = ACTIONS_TO[ev[3]]
				if ev[3] == "request":
					count += 1
					nums[wid] = "PTW-%04d" % count
		out[i] = [nums.get(wid, ""), before]
	return out


## A permit, lock, unlock or lock removal by authority event (§17.7).
static func is_permit_event(ev: Array) -> bool:
	return ev[1] == "permit" or ev[1] == "lock" or ev[1] == "unlock" or ev[1] == "remove_lock"


## A person's call sign (the staff's), "you" for the trainee in free mode (null), else what was named.
static func person_words(e, pid) -> String:
	if pid == null:
		return "you"
	if e._sm != null and typeof(pid) == TYPE_STRING and e._sm.person_ix.has(pid):
		return e._sm.people[e._sm.person_ix[pid]]["call"]
	return str(pid)


## An event of a permit, lock or unlock (§17.7) in words, for the form's history and the debrief. `ctx` is the event's
## entry of replay() (its number and state then); without it the present ones are used.
static func event_text(e, ev: Array, ctx := []) -> String:
	var wid = ev[2]
	var num: String = ctx[0] if not ctx.is_empty() else number_of(e, str(wid))
	var then: int = ctx[1] if not ctx.is_empty() else -1
	var w: Dictionary = e.m.works[e.m.work_ix[wid]] if typeof(wid) == TYPE_STRING and e.m.work_ix.has(wid) else {}
	if ev[1] == "permit":
		var title: String = w.get("title", str(wid))
		if ev[3] == "auto":
			return "Permit %s %s: %s" % [num, title, STATE_WORDS[int(ev[6][0])].to_lower()]
		var what: String = DONE_WORDS.get(ev[3], str(ev[3]))
		match ev[5]:
			"done":
				return "Permit %s: %s%s" % [title, what, (" (%s)" % num) if ev[3] == "request" else ""]
			"refused":
				var why := PackedStringArray()
				for r in ev[6]:
					why.append(reason_text(e, w, String(r), -1, then) if not w.is_empty() else String(r))
				return "Permit %s: %s refused (%s)" % [title, ACTION_WORDS.get(ev[3], str(ev[3])).to_lower(), "; ".join(why)]
		return "Permit %s %s: not a permit action of this plant" % [str(wid), str(ev[3])]
	# lock, unlock
	var x := isolation_of(e, w) if not w.is_empty() else {}
	var p: int = int(ev[3]) if typeof(ev[3]) == TYPE_INT else -1
	var pts: Array = x.get("points", [])
	var where: String = pts[p]["kks"] if p >= 0 and p < pts.size() else str(ev[3])
	if ev[1] == "remove_lock":
		match ev[5]:
			"done":
				return "Lock removed by authority by %s: %s (%s), locked by %s. Reason: %s" % [
						person_words(e, ev[4]), where, w.get("title", str(wid)), person_words(e, ev[7]), str(ev[8])]
			"refused":
				var why := PackedStringArray()
				for r in ev[6]:
					why.append(reason_text(e, w, String(r), p, then))
				return "Lock removal by authority %s refused: %s" % [where, "; ".join(why)]
		return "Lock removal by authority %s: not a point of this plant, or no reason given" % where
	var verb := "Locked and tagged" if ev[1] == "lock" else "Lock removed"
	match ev[5]:
		"done":
			return "%s: %s (%s), by %s" % [verb, where, w.get("title", str(wid)), person_words(e, ev[4])]
		"refused":
			var why := PackedStringArray()
			for r in ev[6]:
				why.append(reason_text(e, w, String(r), p, then))
			return "%s %s refused: %s" % ["Lock" if ev[1] == "lock" else "Unlock", where, "; ".join(why)]
	return "%s %s: not a point of this plant" % [ev[1].capitalize(), where]


## Every event of one work (its permit, its locks), in order: [[step, text, refused]].
static func history(e, wid: String) -> Array:
	var out := []
	var ctx := replay(e)
	for i in e.events.size():
		var ev: Array = e.events[i]
		if is_permit_event(ev) and typeof(ev[2]) == TYPE_STRING and ev[2] == wid:
			out.append([int(ev[0]), event_text(e, ev, ctx[i]), ev[5] != "done"])
	return out
