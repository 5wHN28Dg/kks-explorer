## The frame measurement's tools (decisions 0057, 0060): `probe=1` writes frames.csv, a line per frame with where its
## time went (app/frame_probe.gd), and `pipeline_save_mb` sets how often the pipeline cache is saved.
extends RefCounted

const FrameProbe = preload("res://app/frame_probe.gd")
const SAVE := "rendering/rendering_device/pipeline_cache/save_chunk_size_mb"

func run(tree: SceneTree) -> Array:
	var p: Array = []
	var was = ProjectSettings.get_setting(SAVE)
	var main: Node = (load("res://app/main.tscn") as PackedScene).instantiate()
	main.opts = {"pipeline_save_mb": "2"}
	tree.root.add_child(main)
	for i in 10:
		await tree.process_frame
	if absf(float(ProjectSettings.get_setting(SAVE)) - 2.0) > 1e-6:
		p.append("pipeline_save_mb=2 sets the cache's save interval (%s)" % str(ProjectSettings.get_setting(SAVE)))
	ProjectSettings.set_setting(SAVE, was)
	var probe = FrameProbe.new()
	probe.main = main
	main.add_child(probe)
	for i in 30:
		await tree.process_frame
	var dir := OS.get_user_data_dir().path_join("test-frame-probe")
	DirAccess.make_dir_recursive_absolute(dir)
	probe.write(dir)
	var rows := FileAccess.get_file_as_string(dir.path_join("frames.csv")).strip_edges().split("\n")
	var head := rows[0].split(",")
	for col in ["frame_ms", "phys_n", "proc_ms", "draw_ms", "gpu_ms", "sim_steps"]:
		if not col in head:
			p.append("frames.csv has the column %s" % col)
	if rows.size() < 25:
		p.append("frames.csv has a line per frame (%d lines for 30 frames)" % (rows.size() - 1))
	else:
		var bad := 0
		for i in range(1, rows.size()):
			var v := rows[i].split(",")
			if v.size() != head.size() or float(v[head.find("frame_ms")]) <= 0.0:
				bad += 1
		if bad > 0:
			p.append("every line of frames.csv is a whole frame with its time (%d are not)" % bad)
	DirAccess.remove_absolute(dir.path_join("frames.csv"))
	DirAccess.remove_absolute(dir)
	main.free()
	return p
