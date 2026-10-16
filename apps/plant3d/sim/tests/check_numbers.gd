extends SceneTree
## Reads a corpus of JSON number tokens with the IEEE bits Python's float() gives them (lines "token hexbits") and
## checks JsonStrict reads each one to the same bits. Prints "NUMBERS checked=N bad=M" and the first mismatches.
##   godot --headless --script apps/plant3d/sim/tests/check_numbers.gd -- CORPUS
const JsonStrict = preload("../json_strict.gd")


func _init() -> void:
	quit(1)         # stays the exit code if a script error stops this function
	var args := OS.get_cmdline_user_args()
	var lines := FileAccess.get_file_as_string(args[0]).split("\n", false)
	var bad := 0
	for line in lines:
		var parts := line.split(" ")
		var r := JsonStrict.parse_text("[" + parts[0] + "]")
		var got := "error"
		if r.ok:
			var v = r.value[0]
			var b := PackedByteArray()
			b.resize(8)
			b.encode_double(0, float(v))
			b.reverse()
			got = b.hex_encode()
		if got != parts[1]:
			bad += 1
			if bad <= 20:
				print("MISMATCH ", parts[0], " got ", got, " want ", parts[1])
	print("NUMBERS checked=%d bad=%d" % [lines.size(), bad])
	quit(1 if bad else 0)
