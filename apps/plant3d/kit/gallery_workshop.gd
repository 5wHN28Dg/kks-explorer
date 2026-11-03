## Pictures of the Workshop's kinds (docs/plant3d/WORKSHOP.md §10), to look at (not a test): each built Workshop scene
## (built/workshop/<part>.scn, after build.sh) in the Workshop's own light, assembled, half and fully taken apart
## (workshop/explode.gd), from the front right and above; K3: X-rayed, cut away, sectioned, and running from its bench
## model (each fault too), drawn by the Workshop's own views and bindings (workshop/views.gd, bench_view.gd) with its
## shaders (ws_lit, ws_cap, ws_xray, ws_flow), so a broken shader shows here. Needs a rendering device
## (tools/plant3d/bench/offscreen.sh):
##   godot --path apps/plant3d --script res://kit/gallery_workshop.gd -- --out=DIR [--parts=a,b]
extends SceneTree

const Explode = preload("res://workshop/explode.gd")
const WS = preload("res://workshop/workshop.gd")
const Views = preload("res://workshop/views.gd")
const BenchClock = preload("res://workshop/bench_clock.gd")
const BenchView = preload("res://workshop/bench_view.gd")

## What views.gd and bench_view.gd read of workshop/workshop.gd.
class WsStub:
	var words := {}
	var machine: Node3D
	var comps := {}
	var selected := ""
	var _mats := {}
	func _mat(name: String) -> Material:
		if not _mats.has(name):
			var p := "res://built/materials/%s.tres" % name
			_mats[name] = load(p) if ResourceLoader.exists(p) else null
		return _mats[name]
	func _ancestor_of(_a: String, _id: String) -> bool:
		return false

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var out: String = args.get("out", OS.get_user_data_dir().path_join("gallery_workshop"))
	DirAccess.make_dir_recursive_absolute(out)
	var parts: Array = String(args.get("parts", "")).split(",", false) if args.has("parts") else WS.kinds()
	root.size = Vector2i(1600, 900)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.30, 0.32, 0.34)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.80, 0.84)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50), deg_to_rad(35), 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.005
	root.add_child(cam)
	cam.current = true
	for part in parts:
		var path := "res://built/workshop/%s.scn" % part
		if not ResourceLoader.exists(path):
			print("gallery_workshop: no ", path)
			continue
		var m: Node3D = (load(path) as PackedScene).instantiate()
		root.add_child(m)
		_resolve(m)
		var spec := Explode.spec_of(m)
		var homes := {}
		_homes(m, homes)
		var box: AABB = m.get_meta("box")
		for s in [0.0, 0.5, 1.0]:
			var off := Explode.offsets(spec, s)
			for id in homes:
				var n: Node3D = homes[id][0]
				n.transform = Transform3D(homes[id][1].basis, homes[id][1].origin + off.get(id, Vector3.ZERO))
			var grown := box.grow(box.size.length() * 0.6 * s)
			var r := grown.size.length() * 0.5
			var dir := Vector3(0.8, 0.55, 1.0).normalized()
			cam.global_position = grown.get_center() + dir * (r / tan(deg_to_rad(20.0)) * 1.1)
			cam.look_at(grown.get_center(), Vector3.UP)
			for i in 6:
				await process_frame
			await RenderingServer.frame_post_draw
			var file := out.path_join("%s_%s.png" % [part, ["assembled", "half", "exploded"][int(s * 2)]])
			root.get_texture().get_image().save_png(file)
			print("gallery_workshop: ", file)
		for id in homes:
			homes[id][0].transform = homes[id][1]
		await _k3(m, homes, box, cam, out, part)
		m.queue_free()
		await process_frame
	quit()

## K3's pictures: the views and the run, through the Workshop's own code.
func _k3(m: Node3D, homes: Dictionary, box: AABB, cam: Camera3D, out: String, part: String) -> void:
	var ws := WsStub.new()
	ws.machine = m
	ws.words = m.get_meta("workshop", {})
	for id in homes:
		ws.comps[id] = homes[id][0]
	var v := Views.new()
	v.ws = ws
	v.machine_shown(m, ws.comps)
	var clock := BenchClock.new()
	var bv := BenchView.new()
	bv.ws = ws
	bv.clock = clock
	bv.views = v
	if String(ws.words.get("bench_text", "")) != "":
		if not clock.load_text(ws.words.bench_text, ws.comps.keys()):
			print("gallery_workshop: the bench can't run: ", clock.error)
	bv.setup(m)
	var dir := Vector3(0.8, 0.55, 1.0).normalized()
	var r := box.size.length() * 0.5
	var far := box.get_center() + dir * (r / tan(deg_to_rad(20.0)) * 1.1)
	var shots := [["xray", func(): v.set_xray(true)], ["cutaway", func(): v.set_xray(false); v.set_cut(true)],
		["section", func(): v.set_cut(false); v.set_section(true); v.set_section_axis(1); v.set_section_at(0.5)]]
	for sh in shots:
		sh[1].call()
		await _shot(cam, far, box.get_center(), out.path_join("%s_%s.png" % [part, sh[0]]))
	v.set_section(false)
	if not clock.loaded():
		return
	# running: each machine started (the first command its resting state takes: the transmitter's supply, the
	# turbine's Roll); the transmitter's pressure rising to 6 bar (the line still filling: the flow shows), cut away
	for mc in clock.m.machines:
		for o in clock.m.ops_ui:
			if o.get("machine") == mc.id and mc.commands.has(o.do) and String(mc.init) in Array(mc.commands[o.do].get("from", [])):
				clock.command(o.at, o.do)
				break
	var setop: Dictionary = {}
	for o in clock.m.ops_ui:
		if o.get("do") == "set":
			setop = o
	v.set_cut(true)
	var run := func(value: float, seconds: float):
		if not setop.is_empty():
			clock.op_set(setop.at, value)
		for i in roundi(seconds / clock.STEP):
			clock.tick(clock.STEP)
			bv.draw(clock.STEP)
	run.call(0.0, 1.0)
	run.call(6.0, 0.2)
	await _shot(cam, far, box.get_center(), out.path_join("%s_running.png" % part))
	run.call(6.0, 6.0)
	# K4b: a machine with a start-up sequence, run on (the turbine at its soak speed, its steam flowing), cut away in
	# the heat colours and then the pressure colours
	if clock.m.legends.has("heat"):
		run.call(6.0, 90.0)
		v.heat_on = true
		v.pressure_on = false
		run.call(6.0, 0.2)
		await _shot(cam, far, box.get_center(), out.path_join("%s_running_heat.png" % part))
		v.heat_on = false
		v.pressure_on = true
		run.call(6.0, 0.2)
		await _shot(cam, far, box.get_center(), out.path_join("%s_running_pressure.png" % part))
		v.set_cut(false)
		v.set_xray(true)
		run.call(6.0, 0.2)
		await _shot(cam, far, box.get_center(), out.path_join("%s_running_xray_flow.png" % part))
		v.set_xray(false)
		v.set_cut(true)
		v.heat_on = true
	# close to the face that shows a reading (the display), running and with each fault
	var face := box.get_center()
	for e in bv.labels:
		if e.lit != "":
			face = e.label.global_position
	var near := face + dir * r * 1.2
	v.set_cut(false)
	await _shot(cam, near, face, out.path_join("%s_running_display.png" % part))
	for f in clock.m.faults:
		clock.fault(f.id)
		run.call(8.0, 6.0)
		v.set_cut(true)
		await _shot(cam, far, box.get_center(), out.path_join("%s_fault_%s.png" % [part, f.id]))
		v.set_cut(false)
		await _shot(cam, near, face, out.path_join("%s_fault_%s_display.png" % [part, f.id]))
		clock.repair(f.id)
		run.call(6.0, 6.0)

func _shot(cam: Camera3D, at: Vector3, look: Vector3, file: String) -> void:
	cam.global_position = at
	cam.look_at(look, Vector3.UP)
	for i in 6:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(file)
	print("gallery_workshop: ", file)

func _resolve(n: Node) -> void:
	if (n is MeshInstance3D or n is MultiMeshInstance3D) and n.has_meta("mat"):
		var p := "res://built/materials/%s.tres" % n.get_meta("mat")
		if ResourceLoader.exists(p):
			n.material_override = load(p)
	if n.has_meta("items"):
		var items: Array = n.get_meta("items")
		for c in n.get_children():
			if c is MultiMeshInstance3D:
				c.multimesh.instance_count = items.size()
				for i in items.size():
					c.multimesh.set_instance_transform(i, items[i])
	for c in n.get_children():
		_resolve(c)

func _homes(n: Node, out: Dictionary) -> void:
	for c in n.get_children():
		if c.has_meta("explode"):
			out[c.get_meta("id")] = [c, c.transform]
		_homes(c, out)
