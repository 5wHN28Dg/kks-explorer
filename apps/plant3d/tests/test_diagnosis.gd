## The debrief's diagnosis review (ui/diagnosis.gd; docs/plant3d/REALISM.md §2.22, milestone HW3) on a made-up run:
## the cause stays hidden until a repair is made (a refused or unknown repair request is not one: the adversarial
## review's finding); a test pointing to the cause alone finds it; the vent test counts only after a vent; a fix
## of another cause is said to be one; a part used for another cause is not needed.
extends RefCounted

const Diagnosis = preload("res://ui/diagnosis.gd")
const PT2 := "30MAG10CP002"


class FakeModel:
	var scenarios := {"s": {"faults": [{"id": "cond_p2_low", "kks": "30MAG10CP002", "text": "Transmitter 2 reads apart"}]}}


class FakeEngine:
	var events: Array = []
	var inputs: Array = []
	var m = FakeModel.new()


func _service() -> Dictionary:
	return {"causes": [{"id": "blocked", "title": "A blocked impulse line", "component": "manifold", "found": "Sludge",
			"bench": "impulse_blocked"}, {"id": "wet", "title": "Water in the terminal side", "component": "cable_gland",
			"found": "Cracked seal"}],
		"tests": [{"action": "open_block", "title": "The vent test", "shows": ["blocked"]},
			{"action": "open_cover", "title": "Looked in", "shows": ["wet"]}],
		"fixes": [["blow_line", ["blocked"]], ["reseal_gland", ["wet"]]],
		"parts": [["reseal_gland", "gland_seal", "A cable gland seal insert"]],
		"actions": [{"action": "blow_line", "title": "Blow it through"}, {"action": "reseal_gland", "title": "Reseal"}]}


func run(_tree: SceneTree) -> Array:
	var p: Array = []
	var jobs := {PT2: {"kind": "pressure_transmitter", "alias": "cpt2", "loop": "cond_p2", "service": _service()}}
	var e := FakeEngine.new()
	e.events = [[10, "fault", "cond_p2_low"], [10, "cause", "cond_p2_low", "blocked"],
		[20, "hand", PT2, "open_cover", null, "ic1", "done", []],
		[30, "hand", PT2, "open_block", null, "ic1", "done", []],      # no vent before it: not the vent test
		[40, "hand", PT2, "reseal_gland", "spanner_24", "ic1", "done", []],
		[50, "repair", "cond_p2_low", "wo_cond_p2_fix", "ic1", "refused", ["isolation"]]]
	var r: Dictionary = Diagnosis.review(e, jobs, e.events.size())[0]
	if r.repaired != -1 or Diagnosis.shown(r, false):
		p.append("a refused repair request counted as put right: the cause would show (%d)" % r.repaired)
	var ls := Diagnosis.lines(r, func(n): return str(n), 100.0)
	if "\n".join(ls).contains("blocked") or not "\n".join(ls).contains("Under investigation"):
		p.append("before the repair the lines say: %s" % "\n".join(ls))
	if r.rows.size() != 2 or r.rows[0].verdict != "ruled out water in the terminal side" or r.rows[1].right:
		p.append("the rows: %s" % str(r.rows))
	if r.parts.size() != 1 or r.parts[0].needed:
		p.append("the gland seal used for a blocked line counted as needed: %s" % str(r.parts))
	e.events += [[60, "hand", PT2, "crack_vent", "spanner_17", "ic1", "done", []],
		[70, "hand", PT2, "open_block", null, "ic1", "done", []],
		[80, "hand", PT2, "blow_line", "spanner_17", "ic1", "done", []], [90, "repair", "cond_p2_low"]]
	r = Diagnosis.review(e, jobs, e.events.size())[0]
	if r.repaired != 90 or r.found_at != 70:
		p.append("after the vent test and the repair: repaired %d, found %d (70, 90 wanted)" % [r.repaired, r.found_at])
	ls = Diagnosis.lines(r, func(n): return str(n), 100.0)
	var t := "\n".join(ls)
	for want in ["The cause: A blocked impulse line. Sludge", "The vent test (ic1): pointed to the cause",
			"Blow it through (ic1): the cause's fix", "Found 1 min after", "Put right."]:
		if not t.contains(want):
			p.append("the lines lack \"%s\": %s" % [want, t])
	return p
