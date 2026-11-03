## A measured run's fixed weather (app/main.gd `weather=KIND`, app/step_bench.gd) and the tables' lookup, apart from
## app/weather_view.gd so that scripts run outside the app's project (sim/tests/bench_realism.gd, whose res:// is the
## repository) can use them: no res:// preloads here.
extends RefCounted

## A measured walk's weather (app/main.gd `weather=KIND`): the scenario's weather fixed at that kind, and the driven
## values at its targets for the scenario's start hour (else they would take the lags' minutes to get there). False
## (nothing changed) for a scenario without weather or a kind weather.json lacks.
static func fix(sc: Dictionary, wx: Dictionary, kind: String) -> bool:
	if not sc.has("world") or not (sc.world is Dictionary) or not sc.world.has("weather"):
		return false
	var k: Dictionary = {}
	for x in wx.get("kinds", []):
		if x.get("id", "") == kind:
			k = x
	if k.is_empty():
		return false
	var hm := String(sc.get("start", {}).get("time", "06:00")).split(":")
	var hour := float(hm[0]) + (float(hm[1]) / 60.0 if hm.size() > 1 else 0.0)
	sc.world.weather = {"fixed": kind}
	for v in k.get("targets", {}):
		if sc.get("init", {}).has(v):
			sc.init[v] = table_at(k.targets[v], hour)
	return true

## The value of a table [[x, y], …] at x (linear between its points).
static func table_at(t: Array, x: float) -> float:
	if t.is_empty():
		return 0.0
	if x <= float(t[0][0]):
		return float(t[0][1])
	for i in range(1, t.size()):
		if x <= float(t[i][0]):
			var a: Array = t[i - 1]
			var b: Array = t[i]
			var span := float(b[0]) - float(a[0])
			return float(b[1]) if span <= 0.0 else lerpf(float(a[1]), float(b[1]), (x - float(a[0])) / span)
	return float(t[-1][1])
