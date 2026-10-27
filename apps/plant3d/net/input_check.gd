## Which inputs a session takes (docs/plant3d/MULTIPLAYER.md §3.3, §7.3, §10, §12; settled in MP2):
##
## - **Their form.** An input from the network is strict JSON text of at most 512 bytes (sim/json_strict.gd): an
##   array whose first element is a kind the app makes, with that kind's number of elements and each of the types
##   the app's own input path makes (ui/inputs.gd). Anything else is dropped by the host before a commit, and an input
##   in a commit that fails this check is skipped by every player alike (a commit made by a host of another build, or
##   forged on a LAN, §1.3): the engines never see a kind that is not a text or a length that is not its kind's (the
##   GDScript engine stops halfway through a step on those, §12), and every player skips the same inputs.
## - **Who may make it.** Any slot may play nobody (free mode, §6.1). The trainer's inputs, a fault, a repair without a
##   permit and a lock removed by authority naming no person (PLANT3D.md §15.5), are taken from the host's slot and
##   the instructor seats only (§7.3); `release` and `jump` are the host's alone (the jump is voted, §7.2). Everything
##   else is left to the engine's own rules (§17.13: a slot's person, authority, free mode).
extends RefCounted

const JsonStrict = preload("res://sim/json_strict.gd")

const MAX_BYTES := 512
const PER_TURN := 20            # inputs taken from one player for one turn (§10)
const PER_TURN_BYTES := 1024

# types: s a text, n a number, i an integer, z null, b a boolean
const FORMS := {
	"op": [["s", "s", "zbn", "zs"], ["s", "s", "zbn", "zs", "zs", "zs"]],
	"ack": [["s"]], "shelve": [["s", "n"]], "unshelve": [["s"]],
	"fault": [["s"]], "repair": [["s"], ["s", "s", "zs"]],
	"permit": [["s", "s", "zs"]], "lock": [["s", "i", "zs"]], "unlock": [["s", "i", "zs"]],
	"remove_lock": [["s", "i", "zs", "s", "zs"]],
	"role": [["s"]], "release": [[]], "task_ack": [[]], "arrive": [["s"]], "leave": [["s"]], "read": [["s", "n"]],
	"say": [["s", "s"]], "pick": [["i"]], "call": [["s", "s", "zs"]], "jump": [["s"]], "ppe": [["s", "i"]],
	"zone": [["s", "s"]], "stop": [["s"]],
}


static func _fits(x, t: String) -> bool:
	match typeof(x):
		TYPE_STRING: return t.contains("s")
		TYPE_INT: return t.contains("i") or t.contains("n")
		TYPE_FLOAT: return t.contains("n") and is_finite(x)
		TYPE_NIL: return t.contains("z")
		TYPE_BOOL: return t.contains("b")
	return false


## Whether an input ([kind, …], without step and slot) has a form the app makes.
static func form_ok(item) -> bool:
	if typeof(item) != TYPE_ARRAY or item.is_empty() or typeof(item[0]) != TYPE_STRING or not FORMS.has(item[0]):
		return false
	for f in FORMS[item[0]]:
		if f.size() == item.size() - 1:
			var ok := true
			for k in f.size():
				if not _fits(item[k + 1], f[k]):
					ok = false
					break
			if ok:
				return true
	return false


## The input in a text, or null when the text is not a well-formed input.
static func parse(text: PackedByteArray):
	if text.size() > MAX_BYTES:
		return null
	var r := JsonStrict.parse(text)
	if not r.get("ok", false) or not form_ok(r["value"]):
		return null
	return r["value"]


## The text of an input made here (what the commit carries and every player parses).
static func text(item: Array) -> PackedByteArray:
	return JSON.stringify(item, "", false, true).to_utf8_buffer()


## Whether the trainer's powers are needed for this input.
static func trainer_only(item: Array) -> bool:
	match item[0]:
		"fault":
			return true
		"repair":
			return item.size() == 2
		"remove_lock":
			return item[3] == null
	return false


## Whether the host takes this input from `slot` (`instructors`: the slots named instructor, the host's included).
static func allowed(item: Array, slot: int, host_slot: int, instructors: Dictionary) -> bool:
	if item[0] == "release" or item[0] == "jump":
		return slot == host_slot
	if trainer_only(item):
		return slot == host_slot or instructors.has(slot)
	return true
