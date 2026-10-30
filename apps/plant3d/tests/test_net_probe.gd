## The session layer's measuring probe (mp_probe=1, the harness's --probe=1; MULTIPLAYER.md §14, MP2's follow-up):
## the thread's own time on a CPU and waiting for one, read from /proc/thread-self/schedstat, whose length is 0 (a
## read of the whole file gets nothing: it is read by line).
extends RefCounted

const Session = preload("res://net/session.gd")


func run(_tree: SceneTree) -> Array:
	var p: Array = []
	if not FileAccess.file_exists("/proc/thread-self/schedstat"):
		return p   # (no schedstat here: nothing to read)
	var a: PackedInt64Array = Session.sched_now()
	var x := 0
	for i in 200000:
		x += i
	var b: PackedInt64Array = Session.sched_now()
	if a.size() != 3 or b.size() != 3:
		p.append("sched_now() reads [run, wait, switches] (%s, %s)" % [str(a), str(b)])
	elif a[0] == 0 and a[2] == 0:
		return p   # (the kernel keeps no per-thread scheduler statistics here: "0 0 0", no data)
	elif b[0] < a[0] or b[1] < a[1] or b[2] < a[2]:
		p.append("the thread's counts never go down between two reads (%s, %s)" % [str(a), str(b)])
	return p
