## The GPU's first sight of the plant, before the first walkable frame (decision 0060's follow-up, 2026-10-23): on the
## Note 9 a view that first shows a part of the plant drew its first frames at two to four times its GPU time (the
## water treatment plant's hall turning west: 70 ms on the first lap, 37 ms on every later one; 120 ms once the phone was
## warm), with no pipeline compiled in them. So the start draws every area once beforehand into a small viewport of the
## same world: from points on a grid over each area's bounds (STEP metres apart, at eye height), looking each of four
## ways (four viewports, one point a frame), while the start's last pipelines compile. The pieces' visibility ranges are measured
## from whichever camera draws, so what a walker near those points sees is what gets drawn.
extends Node

const Plant = preload("res://app/plant.gd")

const STEP := 40.0          # metres between the grid's points
const EYE := 1.7
const FOV := 90.0           # four ways a point cover the whole circle

signal done

var points: Array = []      # the grid's points, in Godot's axes
var drawn := 0              # points drawn, each four ways (the tests)
var _vps: Array = []

## The grid's points over every area of the manifest.
static func points_for(manifest: Dictionary) -> Array:
	var out: Array = []
	for a in manifest.get("areas", []):
		var b: Array = a.bounds
		var x0 := float(b[0][0]); var y0 := float(b[0][1]); var x1 := float(b[1][0]); var y1 := float(b[1][1])
		var nx := maxi(1, ceili((x1 - x0) / STEP)); var ny := maxi(1, ceili((y1 - y0) / STEP))
		for i in nx:
			for j in ny:
				out.append(Plant.g(x0 + (i + 0.5) * (x1 - x0) / nx, y0 + (j + 0.5) * (y1 - y0) / ny, EYE))
	return out

## Draws the points, one a frame, each four ways into four viewports `size` pixels big that share `vp`'s 3D world and
## its LOD threshold.
func run(manifest: Dictionary, vp: Viewport, size: Vector2i) -> void:
	points = points_for(manifest)
	var cams: Array = []
	for k in 4:
		var sv := SubViewport.new()
		sv.size = size
		sv.world_3d = vp.find_world_3d()
		sv.mesh_lod_threshold = vp.mesh_lod_threshold
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.fov = FOV
		cam.far = 800.0
		cam.rotation = Vector3(0.0, k * PI * 0.5, 0.0)
		sv.add_child(cam)
		add_child(sv)
		cam.make_current()
		_vps.append(sv)
		cams.append(cam)
	var headless := DisplayServer.get_name() == "headless"
	for p in points:
		for cam in cams:
			(cam as Camera3D).position = p
		if headless:
			await get_tree().process_frame
		else:
			await RenderingServer.frame_post_draw
		drawn += 1
	for sv in _vps:
		(sv as Node).queue_free()
	_vps.clear()
	done.emit()
