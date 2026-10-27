## Packets and messages (docs/plant3d/MULTIPLAYER.md §2.1, §2.2), as built:
##
## A packet is a 14-byte header and a sealed body (net/crypto.gd; the header is the AEAD's AAD):
##   version u8 (1) · key u8 (0 K, 1 P, 2 none) · from u8 (a slot, 255 before it has one) · to u8 (a slot, 255 all)
##   · epoch u16 · incarnation u32 · number u32
## (every number big-endian). The body's plain text is one or more messages, each
##   kind u8 · length u16 (of what follows) · [stream u8 · sequence u32, for a reliable kind] · fields
## A packet holds messages of one key, and reliable and unreliable messages never share one (§2.3).
extends RefCounted

const Crypt = preload("res://net/crypto.gd")

const VERSION := 1
const HEAD := 14
const KEY_K := 0
const KEY_P := 1
const KEY_NONE := 2
const NOBODY := 255             # `from` before a slot; `to` everyone
const MAX_UDP := 1200           # a packet on UDP (§2.1)
## the most plain text a UDP packet's body carries (the header, the IV, the tag and a whole block of padding off)
const MAX_PLAIN := MAX_UDP - HEAD - Crypt.OVERHEAD - 16
const REL_HEAD := 8             # kind, length, stream, sequence
const UNREL_HEAD := 3

enum Kind { HELLO = 1, WELCOME, REFUSE, KEY, ROSTER, INPUT, COMMIT, HASH, SNAP, CONTROL, POS, VOICE, TALK, PING,
		PONG, ACK, FRAG, LAST, NEWHOST, REMOVE, REKEY, BYE }

## the reliable kinds (the rest are never sent again). hello, welcome and refuse are answered or repeated, never
## carried by a stream: a joiner has no slot, so no stream, until its welcome (as built)
const RELIABLE := {Kind.KEY: true, Kind.ROSTER: true, Kind.INPUT: true, Kind.COMMIT: true, Kind.HASH: true,
		Kind.SNAP: true, Kind.CONTROL: true, Kind.TALK: true, Kind.FRAG: true, Kind.LAST: true, Kind.NEWHOST: true,
		Kind.REMOVE: true, Kind.REKEY: true, Kind.BYE: true}

## the streams of one pair of ends (as built: a byte in every reliable message)
const STREAM_MAIN := 0          # player ↔ host under P; the host's broadcast stream under K
const STREAM_SNAP := 1          # the snapshot, host → player under P (§2.3)


static func header(key: int, from: int, to: int, epoch: int, incarnation: int, number: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(HEAD)
	h[0] = VERSION
	h[1] = key
	h[2] = from
	h[3] = to
	Crypt.put_u16(h, 4, epoch)
	Crypt.put_u32(h, 6, incarnation)
	Crypt.put_u32(h, 10, number)
	return h


## The header's fields, or {} when it isn't one of ours.
static func read_header(p: PackedByteArray) -> Dictionary:
	if p.size() < HEAD + Crypt.OVERHEAD + 16 or p[0] != VERSION or p[1] > KEY_NONE:
		return {}
	return {"key": p[1], "from": p[2], "to": p[3], "epoch": Crypt.u16(p, 4), "inc": Crypt.u32(p, 6),
			"number": Crypt.u32(p, 10)}


static func seal(key32: PackedByteArray, head: PackedByteArray, plain: PackedByteArray) -> PackedByteArray:
	var out := head.duplicate()
	out.append_array(Crypt.seal(key32, head, plain))
	return out


## The plain text of a packet under key32, or null.
static func open(key32: PackedByteArray, p: PackedByteArray):
	return Crypt.open(key32, p.slice(0, HEAD), p.slice(HEAD))


# ------------------------------------------------------------------ messages

static func reliable_msg(kind: int, stream: int, seq: int, fields: PackedByteArray) -> PackedByteArray:
	var m := PackedByteArray([kind, 0, 0, stream, 0, 0, 0, 0])
	Crypt.put_u16(m, 1, fields.size() + 5)
	Crypt.put_u32(m, 4, seq)
	m.append_array(fields)
	return m


static func msg(kind: int, fields: PackedByteArray) -> PackedByteArray:
	var m := PackedByteArray([kind, 0, 0])
	Crypt.put_u16(m, 1, fields.size())
	m.append_array(fields)
	return m


## The messages of a body: [{kind, reliable, stream, seq, fields}, …], or null when it doesn't parse (a length past
## the end, an unknown kind, a reliable message too short for its stream and sequence).
static func messages(plain: PackedByteArray):
	var out := []
	var at := 0
	while at < plain.size():
		if at + UNREL_HEAD > plain.size():
			return null
		var kind := plain[at]
		var n := Crypt.u16(plain, at + 1)
		var end := at + UNREL_HEAD + n
		if kind < Kind.HELLO or kind > Kind.BYE or end > plain.size():
			return null
		if RELIABLE.has(kind):
			if n < 5:
				return null
			out.append({"kind": kind, "reliable": true, "stream": plain[at + 3], "seq": Crypt.u32(plain, at + 4),
					"fields": plain.slice(at + REL_HEAD, end)})
		else:
			out.append({"kind": kind, "reliable": false, "fields": plain.slice(at + UNREL_HEAD, end)})
		at = end
	return out


# ------------------------------------------------------------------ the replay window (§1.3)

## Per (sender, incarnation, key): a number seen, or one more than 256 below the highest seen, is dropped.
class Replay:
	const SIZE := 256
	var highest := 0
	var seen := PackedInt64Array()

	func _init() -> void:
		seen.resize(SIZE)
		seen.fill(-1)

	## Whether n is new (not yet recorded).
	func fresh(n: int) -> bool:
		if n <= 0:
			return false
		if n > highest:
			return true
		if highest - n >= SIZE:
			return false
		return seen[n % SIZE] != n

	func record(n: int) -> void:
		seen[n % SIZE] = n
		highest = maxi(highest, n)
