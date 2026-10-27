## Reliable streams (docs/plant3d/MULTIPLAYER.md §2.3): sequence numbers from 1 per stream, delivery in order,
## cumulative acknowledgements with a 32-bit mask of those after, at most 32 messages unacknowledged (a window that
## starts at 8, grows by one per acknowledged message and is halved once per window on a loss), fast retransmission
## after 3 later messages were acknowledged, and a retransmission timeout computed as RFC 6298 says, kept between
## 0.4 s and 4 s (Karn's rule: a message sent more than once gives no round-trip sample). A message longer than one
## packet goes as `frag` pieces, each a stream message of its own; the receiver joins them, at most `max_message`
## bytes for one message.
extends RefCounted

const Crypt = preload("res://net/crypto.gd")
const Wire = preload("res://net/wire.gd")

const MASK_BITS := 32
const MAX_WINDOW := 32
const START_WINDOW := 8
const RTO_MIN := 0.4
const RTO_MAX := 4.0
const FRAG_HEAD := 7            # message ID u16, index u16, count u16, the message's kind u8
## a piece's bytes: one reliable message per packet at most
const PIECE := Wire.MAX_PLAIN - Wire.REL_HEAD - FRAG_HEAD
const MAX_MESSAGE := 64 * 1024  # a reliable message (the snapshot's stream has its own limit)


class Sender:
	var stream := Wire.STREAM_MAIN
	var next_seq := 1
	var queue: Array = []           # [seq, message bytes] waiting for the window
	var flight := {}                # seq -> {m, t (last sent), n (times sent), fast}
	var cwnd := float(START_WINDOW)
	var srtt := -1.0
	var rttvar := 0.0
	var rto := 1.0
	var _halved_at := 0             # the highest sequence sent when the window was last halved
	var _msg_id := 0
	var sent := 0                   # messages sent, first times and again (tests)
	var resent := 0

	func _init(s := Wire.STREAM_MAIN) -> void:
		stream = s

	## Queues a message, cut into `frag` pieces when it is longer than one packet takes.
	func push(kind: int, fields: PackedByteArray) -> void:
		if fields.size() + Wire.REL_HEAD <= Wire.MAX_PLAIN:
			push_raw(next_seq, Wire.reliable_msg(kind, stream, next_seq, fields))
			return
		_msg_id = (_msg_id + 1) & 0xffff
		var count := (fields.size() + PIECE - 1) / PIECE
		for i in count:
			var f := PackedByteArray()
			f.resize(FRAG_HEAD)
			Crypt.put_u16(f, 0, _msg_id)
			Crypt.put_u16(f, 2, i)
			Crypt.put_u16(f, 4, count)
			f[6] = kind
			f.append_array(fields.slice(i * PIECE, mini((i + 1) * PIECE, fields.size())))
			push_raw(next_seq, Wire.reliable_msg(Wire.Kind.FRAG, stream, next_seq, f))

	## Queues a message already made with its sequence (the host's broadcast stream: one numbering for all, a sender
	## per player).
	func push_raw(seq: int, m: PackedByteArray) -> void:
		queue.append([seq, m])
		next_seq = seq + 1

	func pending() -> bool:
		return not queue.is_empty() or not flight.is_empty()

	func waiting() -> int:
		return queue.size() + flight.size()

	## The messages to send now: those whose timeout ran out, then new ones as the window allows.
	func due(now: float) -> Array:
		var out := []
		var lost := false
		var seqs := flight.keys()
		seqs.sort()
		for s in seqs:
			var f: Dictionary = flight[s]
			if f.fast or now - f.t >= rto:
				if not f.fast:
					lost = true
				f.fast = false
				f.t = now
				f.n += 1
				out.append(f.m)
				resent += 1
		if lost:
			rto = minf(rto * 2.0, RTO_MAX)
			_halve()
		while not queue.is_empty() and flight.size() < int(cwnd):
			var q: Array = queue.pop_front()
			flight[q[0]] = {"m": q[1], "t": now, "n": 1, "fast": false}
			out.append(q[1])
		sent += out.size()
		return out

	func _halve() -> void:
		var top := 0
		for s in flight:
			top = maxi(top, s)
		if top > _halved_at:
			cwnd = maxf(2.0, cwnd * 0.5)
			_halved_at = top

	## An acknowledgement: everything up to cum, and the mask's bits (bit i: cum + 2 + i).
	func on_ack(cum: int, mask: int, now: float) -> void:
		var acked := []
		for s in flight:
			if s <= cum or (s >= cum + 2 and s < cum + 2 + MASK_BITS and (mask >> (s - cum - 2)) & 1):
				acked.append(s)
		var top := 0
		for s in acked:
			var f: Dictionary = flight[s]
			if f.n == 1:
				_sample(now - f.t)
			flight.erase(s)
			cwnd = minf(cwnd + 1.0, MAX_WINDOW)
			top = maxi(top, s)
		# fast retransmit: a message with 3 later ones acknowledged
		if top > 0:
			for s in flight:
				if s < top and not flight[s].fast and flight[s].n == 1:
					var later := 0
					for a in acked:
						if a > s:
							later += 1
					if later >= 3 or (mask != 0 and _later_in_mask(s, cum, mask) >= 3):
						flight[s].fast = true
						_halve()

	func _later_in_mask(s: int, cum: int, mask: int) -> int:
		var n := 0
		for i in MASK_BITS:
			if (mask >> i) & 1 and cum + 2 + i > s:
				n += 1
		return n

	func _sample(r: float) -> void:
		if srtt < 0.0:
			srtt = r
			rttvar = r / 2.0
		else:
			rttvar = 0.75 * rttvar + 0.25 * absf(srtt - r)
			srtt = 0.875 * srtt + 0.125 * r
		rto = clampf(srtt + maxf(0.01, 4.0 * rttvar), RTO_MIN, RTO_MAX)


class Receiver:
	var expected := 1               # the next sequence to deliver
	var buf := {}                   # seq -> [kind, fields], ahead of expected
	var ack_due := false
	var max_message := MAX_MESSAGE
	var bad := ""                   # why the last piece was refused ("" when none)
	var _frag_id := -1
	var _frag_count := 0
	var _frag_kind := 0
	var _frag_parts: Array = []
	var _frag_bytes := 0

	## A reliable message received; returns the messages now delivered in order: [[kind, fields], …].
	func take(seq: int, kind: int, fields: PackedByteArray) -> Array:
		ack_due = true
		if seq < expected or seq >= expected + 2 * MASK_BITS or buf.has(seq):
			return []
		buf[seq] = [kind, fields]
		var out := []
		while buf.has(expected):
			var m: Array = buf[expected]
			buf.erase(expected)
			expected += 1
			if m[0] == Wire.Kind.FRAG:
				var whole = _piece(m[1])
				if whole != null:
					out.append(whole)
			else:
				out.append(m)
		return out

	## The acknowledgement: [cum, mask].
	func ack() -> Array:
		var cum := expected - 1
		var mask := 0
		for s in buf:
			var i: int = s - cum - 2
			if i >= 0 and i < MASK_BITS:
				mask |= 1 << i
		return [cum, mask]

	func _piece(f: PackedByteArray):
		if f.size() < FRAG_HEAD:
			bad = "a short piece"
			return null
		var id := Crypt.u16(f, 0)
		var i := Crypt.u16(f, 2)
		var count := Crypt.u16(f, 4)
		if i == 0:
			_frag_id = id
			_frag_count = count
			_frag_kind = f[6]
			_frag_parts = []
			_frag_bytes = 0
		elif id != _frag_id or i != _frag_parts.size() or count != _frag_count or f[6] != _frag_kind:
			bad = "a piece out of its message"
			_frag_id = -1
			return null
		if count == 0 or count * PIECE > max_message + PIECE:
			bad = "a message over its limit"
			_frag_id = -1
			return null
		var piece := f.slice(FRAG_HEAD)
		_frag_bytes += piece.size()
		if _frag_bytes > max_message:
			bad = "a message over its limit"
			_frag_id = -1
			return null
		_frag_parts.append(piece)
		if _frag_parts.size() < _frag_count:
			return null
		var whole := PackedByteArray()
		for p in _frag_parts:
			whole.append_array(p)
		_frag_id = -1
		_frag_parts = []
		return [_frag_kind, whole]


## An ack message's fields: stream u8, cum u32, mask u32.
static func ack_fields(stream: int, cum: int, mask: int) -> PackedByteArray:
	var f := PackedByteArray([stream, 0, 0, 0, 0, 0, 0, 0, 0])
	Crypt.put_u32(f, 1, cum)
	Crypt.put_u32(f, 5, mask)
	return f
