extends RefCounted
## A procedure run in the model alone (docs/PLANT3D.md §8, decision 0054 §10), as ref/plant3d.py run_procedure: a
## trainee who does exactly what each step says, its ops at once (in order), then model steps until the step's `done`
## value is true (or one step when it has none).
##
##   var r := Procedure.run(model, "cold_start")
##   r.error    "" or why it stopped: an op refused, or a `done` that didn't come within limit_s of model time
##   r.engine   the engine where it stopped; r.engine.inputs are the inputs made, at the steps they took effect
##   r.log      [[step id, model step at which it ended], …]

const PlantEngine = preload("engine.gd")


## on_step: called with (step id, engine) after each step ends. until_step: stop before that step.
static func run(model, pid: String, limit_s: float = 3600, eng = null, until_step = null,
		on_step: Callable = Callable()) -> Dictionary:
	var pr: Dictionary = model.procedures[pid]
	var e = eng if eng != null else PlantEngine.new(model, pr["scenario"])
	var log := []
	for s in pr["steps"]:
		if until_step != null and s["id"] == until_step:
			break
		var start: int = e.step_no
		var n_ev: int = e.events.size()
		for d in s.get("do", []):
			e.op(d["kks"], d["do"], d.get("value"), d.get("trip"))
		e.step()
		var refused := []
		for k in range(n_ev, e.events.size()):
			var ev: Array = e.events[k]
			if ev[1] == "op" and ev[4] != "done":
				refused.append(ev)
		if not refused.is_empty():
			return {"engine": e, "log": log, "error": "step %s: refused %s" % [s["id"], str(refused)]}
		if s.has("done"):
			while not e.truth(s["done"]):
				if e.step_no - start >= limit_s * 10:
					return {"engine": e, "log": log,
							"error": "step %s: %s not true after %s s" % [s["id"], s["done"], str(limit_s)]}
				e.step()
		log.append([s["id"], e.step_no])
		if on_step.is_valid():
			on_step.call(s["id"], e)
	return {"engine": e, "log": log, "error": ""}
