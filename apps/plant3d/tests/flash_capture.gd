## The lightning's flash analysis (UI-UX-POLICY A10, issue #443): the rendered frames of a night thunderstorm, for
## tools/plant3d/flash_analysis.py. Not a test: it needs a display (the private one offscreen.sh gives).
##   tools/plant3d/bench/offscreen.sh godot --path apps/plant3d --script res://tests/flash_capture.gd -- --out=FILE
##     [--speed=60]     the plant's speed: 10 x speed model steps a second of real time (60: sim_clock.gd's FF_MAX)
##     [--seconds=60]   how long, after 3 s of warm-up
##     [--soft]         with the settings' Reduced motion on
##     [--movie]        for Godot's Movie Maker (add `--write-movie FILE.avi --fixed-fps 60` before --script; --fps=N if not 60): each
##                      frame is 1/fps of real time, the model stepped by it; nothing is read back (FILE is still
##                      written: a header only). The video is for IRIS (decision 0077, tools/plant3d/flash_iris.sh)
## The scenario cold_iron at 01:00, its weather fixed at the thunderstorm (full lightning), the trainee flying 30 m
## over where they start, looking down at the plant. Each frame, after it is drawn, the whole window scaled down to
## 160 x 90 by averaging (Image.resize, bilinear over halvings: mipmaps) is written as RGB8 after a header line; the
## real time of each frame is in FILE.times (microseconds).
extends SceneTree

const App = preload("res://tests/ui_app.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const WeatherView = preload("res://app/weather_view.gd")

const W := 160
const H := 90

var out := ""
var speed := 60.0
var seconds := 60.0
var soft := false
var movie := false
var fps := 60.0                 # --movie: the --fixed-fps given to Godot


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--speed="):
			speed = float(a.substr(8))
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
		elif a == "--soft":
			soft = true
		elif a == "--movie":
			movie = true
		elif a.begins_with("--fps="):
			fps = float(a.substr(6))
	if out == "":
		push_error("flash_capture: --out=FILE")
		quit(2)
		return
	_go.call_deferred()


func _go() -> void:
	var main: Node = App.start(self)
	var t_start := Time.get_ticks_msec()
	while (main.ui == null or main.weather == null or main.ui.clock == null) and Time.get_ticks_msec() - t_start < 120000:
		await process_frame                      # with a display the plant loads over several frames
	for i in 10:
		await process_frame
	var ui = main.ui
	if ui == null or main.weather == null:
		push_error("flash_capture: the app did not start with its weather view")
		quit(1)
		return
	var sc: Dictionary = ui.model.scenarios["cold_iron"].duplicate(true)
	sc["id"] = "storm_night"
	var st: Dictionary = ui.model.plant["clock"]["start"].duplicate()
	st["time"] = "01:00"
	sc["start"] = st
	if not WeatherView.fix(sc, ui.model.weather, "thunderstorm"):
		push_error("flash_capture: no thunderstorm")
		quit(1)
		return
	ui.model.scenarios["storm_night"] = sc
	ui.restart("storm_night", true)
	ui.clock.set_speed(SimClock.Speed.PAUSED)   # this script steps the model: 10 x speed steps a real second
	ui._setting("reduced_motion", soft)
	var pl = ui.player
	pl.set_mode(pl.Mode.FLY)
	pl.global_position += Vector3(0, 30, 0)
	pl.halt()
	pl.set_heading(pl.rotation.y, deg_to_rad(-25.0))
	pl.scripted = true
	for i in 180:                                # warm-up: pipelines, the weather's easing
		await process_frame
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_line("WDPFLASH %d %d speed=%s soft=%s" % [W, H, str(speed), str(soft)])
	var times := PackedStringArray()
	var t0 := Time.get_ticks_usec()
	var last := t0
	var acc := 0.0
	var lit0: int = int(main.weather.get("lit")) if main.weather.get("lit") != null else 0
	var fl0: int = main.weather.flashes
	var frame := 0
	while true:
		var now := Time.get_ticks_usec()
		if movie:
			# Movie Maker: every frame is 1/fps of the video's (the player's) time, whatever it took to draw
			if frame >= int(seconds * fps):
				break
			frame += 1
			acc += 10.0 * speed / fps
		else:
			if now - t0 > int(seconds * 1e6):
				break
			acc += float(now - last) / 1e6 * 10.0 * speed
		last = now
		acc = minf(acc, speed)        # at most a tenth of a real second's steps in one frame (the clock's own cap)
		var n := int(acc)
		acc -= n
		if n > 0:
			ui.clock.run_steps(n)
		if movie:
			await process_frame
			times.append(str(int(frame * 1e6 / fps)))
			continue
		await RenderingServer.frame_post_draw
		var img: Image = root.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(W, H, Image.INTERPOLATE_TRILINEAR)
		f.store_buffer(img.get_data())
		times.append(str(Time.get_ticks_usec() - t0))
	f.close()
	var tf := FileAccess.open(out + ".times", FileAccess.WRITE)
	tf.store_string("\n".join(times) + "\n")
	tf.close()
	var lit: int = (int(main.weather.get("lit")) if main.weather.get("lit") != null else 0) - lit0
	print("flash_capture: %d frames in %.1f s, the model's flashes %d, lit %d, step %d" % [times.size(), seconds,
			main.weather.flashes - fl0, lit, ui.clock.engine.step_no])
	quit(0)
