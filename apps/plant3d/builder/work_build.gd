## Equipment with jobs (docs/plant3d/REALISM.md §3.3, §2.16; milestone HW2): the codes the service files name
## (data/plant3d/service/<kind>.json) are built outside their 12 m cells, each as its own meshes under its equipment
## node (`builder/kit_place.gd` `unmerged`), so that the work view can hide it; and each gets a work scene,
## `built/work/<code>.scn`: its Workshop component scene made with that very instance's parameters and context
## (WORKSHOP.md §5: "workshop_scene(part, params, ctx) per equipment"), with the mounting the Workshop leaves out (a
## free-standing transmitter's stand pipe: `only("plant", [])`) under `mounting`, so that the work view hides the plant
## piece and shows this in its place, the plant's materials resolved by name.
extends RefCounted

const Kit = preload("res://kit/kit.gd")
const WorkshopBuild = preload("res://builder/workshop_build.gd")

const PER_CELL := 2         # at most this many pieces with jobs in one 12 m cell (REALISM.md §11)
const CELL := 12.0
const EXTRA_DRAWS := 12     # and at most this many more draw calls in any view of the plant
const WORK_DRAWS := 30      # the work scene's own (§11: the component scene ≤ 30 draw calls, ≤ 30,000 triangles)
const WORK_TRIS := 30000


## {code: {kind, alias, loop, actions: [service actions]}} from the service files under `data_dir/service`.
static func jobs(data_dir: String) -> Dictionary:
	var out := {}
	var dir := data_dir.path_join("service")
	if not DirAccess.dir_exists_absolute(dir):
		return out
	var files := Array(DirAccess.get_files_at(dir))
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var s = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(f)))
		if not s is Dictionary:
			continue
		for e in s.get("equipment", []):
			out[String(e.kks)] = {"kind": String(s.part), "alias": String(e.alias), "loop": String(e.loop),
				"actions": s.get("actions", [])}
	return out


## The work scenes of every code with a job, after the plant's build: {made: [codes], draws: {code: n}, tris: {}, errors}.
## `kp`: the plant's builder's parts placement (its params, contexts and transforms per code).
static func build_all(out_dir: String, data_dir: String, kp) -> Dictionary:
	var out := {"made": [], "draws": {}, "tris": {}, "errors": []}
	var J: Dictionary = kp.jobs
	if J.is_empty():
		return out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for kks in J:
		var j: Dictionary = J[kks]
		if not kp.unmerged_of.has(kks):
			out.errors.append("service/%s.json: %s is not a piece of equipment the plant builds" % [j.kind, kks])
			continue
		var path := data_dir.path_join("workshop").path_join(j.kind + ".json")
		var data = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
		if not data is Dictionary:
			out.errors.append("service/%s.json: no Workshop data workshop/%s.json" % [j.kind, j.kind])
			continue
		var u: Dictionary = kp.unmerged_of[kks]
		var res := Kit.make(j.kind, u.params, u.ctx, 1.0, true)
		var errs: Array = WorkshopBuild.join(res, data)
		if not errs.is_empty():
			for e in errs:
				out.errors.append("work %s: %s" % [kks, e])
			continue
		# every action's anchors are its component's (the generator's anchors: WORKSHOP.md §4.1)
		var anchors := {}
		for c in res.components:
			anchors[c.id] = c.anchors
		for a in j.actions:
			for an in a.get("anchors", []):
				if not anchors.get(a.component, {}).has(an):
					out.errors.append("service/%s.json: action %s: the component %s has no anchor %s" % [j.kind,
						a.action, a.component, an])
		var root := WorkshopBuild._nodes(j.kind, res, data)
		root.name = kks
		root.set_meta("kks", kks)
		root.set_meta("alias", j.alias)
		root.set_meta("xform", u.xf)
		# the mounting the Workshop leaves out (a stand-in that nothing replaces), merged per material
		var m := Node3D.new()
		m.name = "mounting"
		root.add_child(m)
		var per := {}
		for si in res.get("standins", []):
			if not si.replaced_by.is_empty():
				continue
			for k in si.layers:
				var L: Dictionary = si.layers[k]
				if not per.has(L.mat):
					per[L.mat] = []
				per[L.mat].append([L.mesh.surface_get_arrays(0), Vector3.ZERO])
		for mat in per:
			var mi := MeshInstance3D.new()
			mi.name = "mesh_" + mat
			mi.mesh = WorkshopBuild._merged(per[mat], Vector3.ZERO, "mounting|" + mat)
			mi.set_meta("mat", mat)
			m.add_child(mi)
		var draws := 0
		var tris := 0
		var stack: Array = [root]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			stack.append_array(n.get_children())
			if n is MeshInstance3D:
				draws += 1
				tris += _tris((n as MeshInstance3D).mesh)
			elif n is MultiMeshInstance3D:
				draws += 1
				var items: Array = n.get_parent().get_meta("items", [])
				tris += _tris((n as MultiMeshInstance3D).multimesh.mesh) * items.size()
		if draws > WORK_DRAWS or tris > WORK_TRIS:
			out.errors.append("work %s: %d draw calls and %d triangles, over the work view's %d and %d (REALISM.md §11)" % [
				kks, draws, tris, WORK_DRAWS, WORK_TRIS])
		root.set_meta("draws", draws)
		root.set_meta("tris", tris)
		for c in root.get_children():
			WorkshopBuild._own(root, c)
		var ps := PackedScene.new()
		var e := ps.pack(root)
		root.free()
		if e != OK:
			out.errors.append("work %s: pack: error %d" % [kks, e])
			continue
		e = ResourceSaver.save(ps, out_dir.path_join(kks + ".scn"), ResourceSaver.FLAG_COMPRESS)
		if e != OK:
			out.errors.append("work %s: save: error %d" % [kks, e])
			continue
		out.made.append(kks)
		out.draws[kks] = draws
		out.tris[kks] = tris
	# REALISM.md §11: at most 2 pieces with jobs in a 12 m cell, and their draw calls together within 12 (a view can
	# hold every one of them when they stand in one or two cells: counted over all)
	var cells := {}
	var all_draws := 0
	for kks in kp.unmerged_of:
		var u: Dictionary = kp.unmerged_of[kks]
		var o: Vector3 = u.xf.origin
		var k := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
		cells[k] = int(cells.get(k, 0)) + 1
		all_draws += int(u.draws)
	for k in cells:
		if cells[k] > PER_CELL:
			out.errors.append("%d pieces with jobs in the 12 m cell %s: at most %d (REALISM.md §11)" % [cells[k], str(k), PER_CELL])
	if all_draws > EXTRA_DRAWS:
		out.errors.append("the pieces with jobs draw %d calls, over the %d more a view may have (REALISM.md §11)" % [
			all_draws, EXTRA_DRAWS])
	out["plant_draws"] = all_draws
	out["cells"] = cells.size()
	return out


static func _tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	var n := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3 if a[Mesh.ARRAY_INDEX] != null \
			else (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n
