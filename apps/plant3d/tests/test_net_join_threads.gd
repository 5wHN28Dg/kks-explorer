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
	# a token forgotten before its write ran (the host ended the session right after the welcome) stays forgotten:
	# the write is held back by holding the mutex here (the main thread's own lock is recursive)
	s._token = PackedByteArray([9, 9, 9])
	Session._token_mutex.lock()
	s._save_token()
	Session.forget_session()
	Session._token_mutex.unlock()
	for id in s._save_jobs:
		WorkerThreadPool.wait_for_task_completion(id)
	s._save_jobs.clear()
	if FileAccess.file_exists(Session.SESSION_FILE):
		p.append("a token forgotten before its write came back on disk")
	s._token = PackedByteArray([1, 2, 3])
	s._save_token()
	tree.root.remove_child(s)             # (_exit_tree waits for the token's write)
	for what in ["addresses", "prepare", "public key", "token file"]:
		if Session.threads_seen.get(what, "") != "worker":
			p.append("%s made on a worker thread, not the main one (%s)" % [what, Session.threads_seen.get(what, "not seen")])
	if s._rsa_pem == "" or not s._rsa_pem.begins_with("-----BEGIN PUBLIC KEY"):
		p.append("the hello's public key is ready with the key (%s)" % s._rsa_pem.left(30))
	Session.forget_session()
	# the saved token read on the preparation thread reaches the hello, for its own code only
	for c in [["K3QX9F2MHT4C7PW5", "AQID"], ["XXXXXXXXXXXXXXXX", ""]]:
		var f := FileAccess.open(Session.SESSION_FILE, FileAccess.WRITE)
		f.store_string(JSON.stringify({"code": c[0], "token": "AQID"}))
		f.close()
		var s2 = Session.new()
		s2.bind_address = "127.0.0.1"
		s2.discovery_port = 1
		tree.root.add_child(s2)
		s2.join("K3QX9F2MHT4C7PW5")
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < 8000 and not s2._prep_ready():
			await tree.process_frame
		var got := Marshalls.raw_to_base64(s2._prep.get("token", PackedByteArray()))
		if got != c[1]:
			p.append("the token saved for %s gives a join of K3QX… the token '%s' (want '%s')" % [c[0], got, c[1]])
		tree.root.remove_child(s2)
		s2.free()
		Session.forget_session()
	Session.record_threads = false
	s.free()
	return p
