## Reliable streams (docs/plant3d/MULTIPLAYER.md §2.3): over a simulated channel that loses, duplicates, delays and
## reorders messages and acknowledgements (a seeded generator), every message, fragmented ones included, is delivered
## once and in order; the window never passes 32; a message over the receiver's limit is not delivered.
extends RefCounted

const Stream = preload("res://net/stream.gd")
const Wire = preload("res://net/wire.gd")
const Crypt = preload("res://net/crypto.gd")

var fails := []


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails.append(what)


func run(_tree) -> Array:
	_lossy(0.0, 1)
	_lossy(0.2, 2)
	_lossy(0.4, 3)
	_limit()
	_rto()
	return fails


func _lossy(loss: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var tx := Stream.Sender.new()
	var rx := Stream.Receiver.new()
	var sent := []
	for i in 300:
		var n := 5 if i % 37 != 0 else 3000 + i * 7       # some longer than one packet: frag pieces
		var f := PackedByteArray()
		f.resize(n)
		for k in n:
			f[k] = (i * 31 + k) & 0xff
		var kind := Wire.Kind.COMMIT if i % 2 == 0 else Wire.Kind.INPUT
		tx.push(kind, f)
		sent.append([kind, f])
	var got := []
	var wire := []                      # [arrival time, seq, kind, fields] in flight to the receiver
	var back := []                      # [arrival time, cum, mask]
	var now := 0.0
	var max_flight := 0
	while now < 120.0 and (got.size() < sent.size() or tx.pending()):
		now += 0.01
		for m in tx.due(now):
			var ms = Wire.messages(m)
			for x in ms:
				if loss == 0.0:         # (a clean channel: in order, no copies; nothing may be sent twice)
					wire.append([now + 0.03, x["seq"], x["kind"], x["fields"]])
					continue
				if rng.randf() >= loss:
					wire.append([now + rng.randf_range(0.01, 0.08), x["seq"], x["kind"], x["fields"]])
				if rng.randf() < 0.05:
					wire.append([now + rng.randf_range(0.01, 0.15), x["seq"], x["kind"], x["fields"]])
		max_flight = maxi(max_flight, tx.flight.size())
		var keep := []
		for w in wire:
			if w[0] <= now:
				got.append_array(rx.take(w[1], w[2], w[3]))
			else:
				keep.append(w)
		wire = keep
		if rx.ack_due and fmod(now, 0.05) < 0.01:
			rx.ack_due = false
			if rng.randf() >= loss:
				var a := rx.ack()
				back.append([now + (0.03 if loss == 0.0 else rng.randf_range(0.01, 0.08)), a[0], a[1]])
		keep = []
		for b in back:
			if b[0] <= now:
				tx.on_ack(b[1], b[2], now)
			else:
				keep.append(b)
		back = keep
	_ok(got.size() == sent.size(), "loss %.1f: %d of %d delivered" % [loss, got.size(), sent.size()])
	for i in mini(got.size(), sent.size()):
		if got[i][0] != sent[i][0] or got[i][1] != sent[i][1]:
			_ok(false, "loss %.1f: message %d differs" % [loss, i])
			break
	_ok(max_flight <= Stream.MAX_WINDOW, "loss %.1f: at most 32 in flight (%d)" % [loss, max_flight])
	_ok(not tx.pending(), "loss %.1f: everything acknowledged" % loss)
	_ok((tx.resent > 0) == (loss > 0.0), "loss %.1f: messages sent again only when lost (%d)" % [loss, tx.resent])
	_ok(tx.rto >= Stream.RTO_MIN and tx.rto <= Stream.RTO_MAX, "loss %.1f: the timeout within its bounds" % loss)


func _limit() -> void:
	var tx := Stream.Sender.new()
	var rx := Stream.Receiver.new()
	rx.max_message = 4000
	var big := PackedByteArray()
	big.resize(6000)
	tx.push(Wire.Kind.ROSTER, big)
	tx.push(Wire.Kind.INPUT, PackedByteArray([1, 2, 3]))
	var got := []
	for m in tx.due(0.0):
		for x in Wire.messages(m):
			got.append_array(rx.take(x["seq"], x["kind"], x["fields"]))
	_ok(got.size() == 1 and got[0][0] == Wire.Kind.INPUT, "a message over the limit is not delivered, the next one is")
	_ok(rx.bad != "", "the receiver says why")
	# a piece that doesn't belong to the message being joined
	var rx2 := Stream.Receiver.new()
	var f := PackedByteArray([0, 1, 0, 1, 0, 3, Wire.Kind.ROSTER, 9])  # id 1, index 1 of 3: no index 0 before it
	_ok(rx2.take(1, Wire.Kind.FRAG, f).is_empty() and rx2.bad != "", "a piece out of its message is refused")


func _rto() -> void:
	var tx := Stream.Sender.new()
	tx.push(Wire.Kind.INPUT, PackedByteArray([1]))
	var first := tx.due(0.0)
	_ok(first.size() == 1, "sent once")
	_ok(tx.due(0.5).is_empty(), "not again before its timeout")
	_ok(tx.due(1.01).size() == 1, "again after its timeout")
	_ok(is_equal_approx(tx.rto, 2.0), "the timeout doubles (%.2f)" % tx.rto)
	for k in 5:
		tx.due(100.0 * (k + 1))
	_ok(tx.rto <= Stream.RTO_MAX, "the timeout stays at most 4 s")
