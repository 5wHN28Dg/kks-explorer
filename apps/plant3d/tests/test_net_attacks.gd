## A session against a player holding the code (key K) or a stranger replaying what they captured
## (docs/plant3d/MULTIPLAYER.md §1.3, §10; the adversarial review of MP2): a host and a victim player in this process
## over the loopback, and an attacker's socket sending packets sealed under K.
##   - a hello with the victim's incarnation (in every packet's clear header) gets no answer, and the victim's address
##     stays its own;
##   - the victim's rejoin token in a hello with a new incarnation, while the victim is alive, takes nothing over; the
##     welcome carries no token in the clear (it travels inside the RSA encryption);
##   - K packets with made-up senders don't grow the host's replay windows; K packets claiming the victim's slot from
##     another address are not taken or forwarded;
##   - hashes for steps the host never digested are not kept.
extends RefCounted

const Session = preload("res://net/session.gd")
const SimClock = preload("res://ui/sim_clock.gd")
const PlantModel = preload("res://sim/plant_model.gd")
const RunSave = preload("res://ui/run_save.gd")
const Code = preload("res://net/code.gd")
const Wire = preload("res://net/wire.gd")
const Crypt = preload("res://net/crypto.gd")

var p: Array = []
var nodes: Array = []


static func _port() -> int:
	var u := PacketPeerUDP.new()
	u.bind(0, "127.0.0.1")
	var n := u.get_local_port()
	u.close()
	return n


func _wait(tree: SceneTree, cond: Callable, seconds: float) -> bool:
	var t := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t < seconds * 1000.0:
		if cond.call():
			return true
		await tree.process_frame
	return cond.call()


func _session(tree: SceneTree, model, content: String, name: String):
	var c := SimClock.new()
	tree.root.add_child(c)
	c.model = model
	var s := Session.new()
	s.model = model
	s.clock = c
	s.content = content
	s.display_name = name
	s.bind_address = "127.0.0.1"
	tree.root.add_child(s)
	nodes.append_array([s, c])
	return s


func run(tree: SceneTree) -> Array:
	var dir := ProjectSettings.globalize_path("res://").path_join("../../data/plant3d").simplify_path()
	var model = PlantModel.from_dir(dir)
	if model.error != "":
		return ["the model: " + model.error]
	var content := RunSave.content_hash(dir)
	var code := Code.make()
	var keys := Code.keys(code)
	var host = _session(tree, model, content, "Host")
	host.discovery_port = _port()
	host.session_port = _port()
	var why: String = host.host("cold_iron", {}, code)
	var victim = _session(tree, model, content, "Victim")
	victim.discovery_port = host.discovery_port
	if why == "":
		why = victim.join(code, "127.0.0.1:%d" % host.discovery_port)
	var joined := func(): return victim.state == Session.State.LOBBY and host.peers.has(1) and host.peers[1].joined
	if why != "" or not await _wait(tree, joined, 20.0):
		return _end(["the victim did not join: %s (state %d)" % [why, victim.state]])
	var vp = host.peers[1]
	if host.peers[1].welcome.get_string_from_utf8().contains(Marshalls.raw_to_base64(victim._token)):
		p.append("the welcome carries the rejoin token in the clear")
	var atk := PacketPeerUDP.new()
	atk.bind(0, "127.0.0.1")
	var rsa := Crypt.crypto().generate_rsa(2048)
	var n := [1]
	var send_k := func(from: int, inc: int, msgs: Array):
		var plain := PackedByteArray()
		for m in msgs:
			plain.append_array(m)
		n[0] += 1
		atk.set_dest_address("127.0.0.1", host.session_port)
		atk.put_packet(Wire.seal(keys["K"], Wire.header(Wire.KEY_K, from, Wire.NOBODY, 1, inc, n[0]), plain))
	var hello := func(token):
		var hi := {"name": "Mallory", "rsa": rsa.save_to_string(true), "app": RunSave.app_version(), "content": content,
				"token": Marshalls.raw_to_base64(token) if token != null else null}
		return Wire.msg(Wire.Kind.HELLO, JSON.stringify(hi).to_utf8_buffer())
	var addr: Array = [vp.ip, vp.port]
	# 1. the victim's incarnation, another RSA key
	send_k.call(Wire.NOBODY, victim.incarnation, [hello.call(null)])
	await _wait(tree, func(): return atk.get_available_packet_count() > 0, 1.0)
	if atk.get_available_packet_count() > 0:
		p.append("a hello with the victim's incarnation was answered")
	if [vp.ip, vp.port] != addr:
		p.append("a hello with the victim's incarnation moved the victim's address")
	# 2. the victim's token, a new incarnation, the victim alive
	send_k.call(Wire.NOBODY, 0x1234567, [hello.call(victim._token)])
	await _wait(tree, func(): return atk.get_available_packet_count() > 0, 1.0)
	if atk.get_available_packet_count() > 0 or host.peers[1].inc != victim.incarnation or host.peers.size() != 1:
		p.append("the victim's token took its slot while the victim was alive")
	# 3. made-up senders: the replay table doesn't grow
	var r0: int = host._replay.size()
	for k in 200:
		send_k.call(1 + k % 7, 1000 + k, [Wire.msg(Wire.Kind.POS, Session.pos_fields(1, Vector3.ZERO, 0.0, 0.0, 0))])
	for i in 10:
		await tree.process_frame
	if host._replay.size() != r0:
		p.append("K packets from made-up senders grew the replay table from %d to %d" % [r0, host._replay.size()])
	# 4. the victim's slot and incarnation from another address
	var tok0: float = vp.fwd_tokens
	var rx0: float = vp.last_rx
	for k in 20:
		send_k.call(1, victim.incarnation, [Wire.msg(Wire.Kind.POS, Session.pos_fields(900 + k, Vector3.ZERO, 0.0, 0.0, 0))])
	await _wait(tree, func(): return host.positions.get(1, []).any(func(x): return x[5] >= 900), 1.0)
	if vp.fwd_tokens < tok0 - 0.5 or host.positions.get(1, []).any(func(x): return x[5] >= 900):
		p.append("K packets claiming the victim from another address were taken")
	# 5. hashes for steps the host never digested
	for k in 100:
		var f := Crypt.be32(7 + k * 13)
		f.append_array(Crypt.random_bytes(32))
		victim._send_p.push(Wire.Kind.HASH, f)
	victim._dirty = true
	await _wait(tree, func(): return host._reported.size() > 0 or victim._send_p.waiting() == 0, 3.0)
	await _wait(tree, func(): return host._reported.size() > 0, 0.5)
	if host._reported.size() > 0:
		p.append("hashes of steps the host never digested were kept (%d)" % host._reported.size())
	atk.close()
	if rx0 > vp.last_rx:
		p.append("(the victim's last packet time went back)")
	return _end(p)


func _end(out: Array) -> Array:
	for s in nodes:
		if s is Session and s.active():
			s.close()
		s.queue_free()
	return out
