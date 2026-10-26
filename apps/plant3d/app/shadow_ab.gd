## What each group of the sun's shadow casters costs the GPU, measured in one walk (`shadow_ab=` with probe=1; decision
## 0057, "The shadow casters"): the groups' casting is switched off in turn, PERIOD s each, round and round
## ("all on", then each group off alone), so that every state is measured at nearly the same places of the route; each
## switch is an event in frames.csv (`shadow_ab+1`: the state is the number of switches so far modulo the groups + 1).
## A group is node names containing any of its words: `shadow_ab=kerbs+terrain,lamp_+roof_steel,Body` (Body: the
## people's skinned avatars; `*` every caster; `!sun` the sun's shadow itself off, `!split2` its two cascades
## instead of four: what the shadow costs beside its casters). tools/plant3d/bench/shadow_ab.py turns the walk into each group's GPU cycles a frame.
## A measurement only: never in an ordinary start (main.gd reads it from the command line or the phone's walk.txt).
extends Node

const PERIOD := 2.0

var groups: Array = []      # Array of PackedStringArray
var roots: Array = []       # the nodes whose casters are switched (the plant, the people)
var sun: DirectionalLight3D
var switches := 0           # counted by frame_probe.gd (an event per switch)
var _t := 0.0
var _saved := {}            # node -> its own casting setting
var _sun_on := true         # the sun's own shadow settings (the tier's, fx_off=…), restored in every state
var _sun_mode := DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS


func setup(spec: String, under: Array, the_sun: DirectionalLight3D = null) -> void:
	sun = the_sun
	if sun != null:
		_sun_on = sun.shadow_enabled
		_sun_mode = sun.directional_shadow_mode
	for g in spec.split(",", false):
		groups.append(g.split("+", false))
	roots = under


func state() -> int:
	return switches % (groups.size() + 1)


func _process(delta: float) -> void:
	if groups.is_empty():
		return
	_t += delta
	if _t < PERIOD:
		return
	_t = 0.0
	switches += 1
	_apply(state())


## State 0: every caster as built; state k: group k's casters off, the rest as built.
func _apply(s: int) -> void:
	for n in _saved:
		if is_instance_valid(n):
			(n as GeometryInstance3D).cast_shadow = _saved[n]
	_saved.clear()
	if sun != null:
		sun.shadow_enabled = _sun_on
		sun.directional_shadow_mode = _sun_mode
	if s == 0:
		return
	var words: PackedStringArray = groups[s - 1]
	if sun != null and "!sun" in words:
		sun.shadow_enabled = false
		return
	if sun != null and "!split2" in words:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		return
	var stack: Array = roots.filter(func(r): return r != null and is_instance_valid(r))
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var g := n as GeometryInstance3D
		if g == null or g.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			continue
		var nm := String(g.name)
		for w in words:
			if w == "*" or nm.contains(w):
				_saved[g] = g.cast_shadow
				g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				break
