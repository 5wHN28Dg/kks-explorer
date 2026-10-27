## The join's slow parts run off the main thread (MP2's follow-up, MULTIPLAYER.md §14): on the Note 9 the device's
## addresses for the LAN query took 6 ms of a frame, the hello's public key and saved token 2 ms, the rejoin token's
## file at the welcome 1.5 ms, against the session layer's 2 ms a frame. Here: a join with no address (a LAN query to
## the broadcast addresses) and the token's save, with the threads they ran on recorded.
extends RefCounted

const Session = preload("res://net/session.gd")


func run(tree: SceneTree) -> Array:
	var p: Array = []
	Session.record_threads = true
	Session.threads_seen.clear()
	Session._proc_rsa = null              # (a key made earlier in this process would be reused: make one here)
	var s = Session.new()
	s.bind_address = "127.0.0.1"
	s.discovery_port = 1                  # (no host anywhere: the query goes unanswered)
	tree.root.add_child(s)
	var why: String = s.join("K3QX9F2MHT4C7PW5")
	if why != "":
		p.append("join: " + why)
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 8000 and not (s._prep_ready() and s._query_t >= 0.0 and s._key_ready()):
		await tree.process_frame
	if s._query_t < 0.0:
		p.append("the LAN query went out once the addresses were there")
	s._token = PackedByteArray([1, 2, 3])
	s._save_token()
	tree.root.remove_child(s)             # (_exit_tree waits for the token's write)
	for what in ["addresses", "prepare", "public key", "token file"]:
		if Session.threads_seen.get(what, "") != "worker":
			p.append("%s made on a worker thread, not the main one (%s)" % [what, Session.threads_seen.get(what, "not seen")])
	if s._rsa_pem == "" or not s._rsa_pem.begins_with("-----BEGIN PUBLIC KEY"):
		p.append("the hello's public key is ready with the key (%s)" % s._rsa_pem.left(30))
	Session.forget_session()
	Session.record_threads = false
	s.free()
	return p
