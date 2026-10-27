## The session's cryptography and wire formats (docs/plant3d/MULTIPLAYER.md §1.3, §2.1, §12 "The crypto"): RFC 5869's
## HKDF test cases, RFC 7518 Appendix B.1's AEAD vector, the invite code (its check character, forgiving typing, its
## keys against an independent Python computation of the same rules), the replay window, the packets and messages.
extends RefCounted

const Crypt = preload("res://net/crypto.gd")
const Code = preload("res://net/code.gd")
const Wire = preload("res://net/wire.gd")

var fails := []


func _ok(cond: bool, what: String) -> void:
	if not cond:
		fails.append(what)


static func _h(s: String) -> PackedByteArray:
	return s.replace(" ", "").replace("\n", "").replace("\t", "").hex_decode()


func run(_tree) -> Array:
	_hkdf()
	_aead()
	_code()
	_replay()
	_packets()
	return fails


func _hkdf() -> void:
	# RFC 5869 Appendix A.1–A.3 (SHA-256)
	_ok(Crypt.hkdf(_h("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), _h("000102030405060708090a0b0c"),
			_h("f0f1f2f3f4f5f6f7f8f9"), 42).hex_encode() == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
			"HKDF case 1")
	var ikm := PackedByteArray()
	var salt := PackedByteArray()
	var info := PackedByteArray()
	for i in 80:
		ikm.append(i)
		salt.append(0x60 + i)
		info.append(0xb0 + i)
	_ok(Crypt.hkdf(ikm, salt, info, 82).hex_encode() == "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71cc30c58179ec3e87c14c01d5c1f3434f1d87",
			"HKDF case 2")
	_ok(Crypt.hkdf(_h("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), PackedByteArray(), PackedByteArray(), 42).hex_encode() \
			== "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8", "HKDF case 3")


func _aead() -> void:
	# RFC 7518 Appendix B.1: AEAD_AES_128_CBC_HMAC_SHA_256
	var k := _h("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
	var p := "A cipher system must not be required to be secret, and it must be able to fall into the hands of the enemy without inconvenience".to_utf8_buffer()
	var iv := _h("1af38c2dc2b96ffdd866940923 41bc04")
	var a := "The second principle of Auguste Kerckhoffs".to_utf8_buffer()
	var e := _h("""c80edfa32ddf39d5ef00c0b468834279a2e46a1b8049f792f76bfe54b903a9c9a94ac9b47ad2655c5f10f9aef71427e2fc6f9b3f399a221489f16362c703233609d45ac69864e3321cf82935ac4096c86e133314c54019e8ca7980dfa4b9cf1b384c486f3a54c51078158ee5d79de59fbd34d848b3d69550a676463444
			27ade54b8851ffb598f7f80074b9473c82e2db""")
	var t := _h("652c3fa36b0a7c5b3219fab3a30bc1c4")
	var sealed := Crypt.seal(k, a, p, iv)
	var want := iv.duplicate()
	want.append_array(e)
	want.append_array(t)
	_ok(sealed == want, "AEAD: RFC 7518 B.1 (got %s)" % sealed.hex_encode().left(64))
	_ok(Crypt.open(k, a, sealed) == p, "AEAD: opens its own")
	var bad := sealed.duplicate()
	bad[bad.size() - 1] ^= 1
	_ok(Crypt.open(k, a, bad) == null, "AEAD: a changed tag is refused")
	bad = sealed.duplicate()
	bad[20] ^= 1
	_ok(Crypt.open(k, a, bad) == null, "AEAD: a changed ciphertext is refused")
	var a2 := a.duplicate()
	a2[0] ^= 1
	_ok(Crypt.open(k, a2, sealed) == null, "AEAD: another AAD is refused")
	_ok(Crypt.open(k, a, sealed.slice(0, sealed.size() - 1)) == null, "AEAD: a short body is refused")
	# every length of plain text, random IVs
	for n in [0, 1, 15, 16, 17, 1000]:
		var pl := Crypt.random_bytes(n) if n > 0 else PackedByteArray()
		var s := Crypt.seal(k, a, pl)
		_ok(s.size() == 32 + (n / 16 + 1) * 16, "AEAD: the size of %d bytes sealed" % n)
		var o = Crypt.open(k, a, s)
		_ok(o != null and o == pl, "AEAD: %d bytes round trip" % n)


func _code() -> void:
	# an independent computation of the same rules (Python's hashlib and hmac): the check character and the keys
	var c := "K3QX9F2MHT4C7PW5"
	_ok(Code.check_char("K3QX9F2MHT4C7PW") == "5", "code: the check character")
	_ok(Code.normalize(c) == c, "code: a good code")
	_ok(Code.normalize("k3qx-9f2m-ht4c-7pw5") == c, "code: lower case and dashes")
	_ok(Code.normalize(" K3QX 9F2M HT4C 7PW5 ") == c, "code: spaces")
	_ok(Code.normalize("K3QX9F2MHT4C7PWS") == "", "code: a wrong check character")
	_ok(Code.normalize("K3QX9F2MHT4C7PW") == "", "code: one short")
	_ok(Code.normalize("K3QX9F2MHT4C7PW55") == "", "code: one too many")
	_ok(Code.normalize("U3QX9F2MHT4C7PW5") == "", "code: U is not in the alphabet")
	_ok(Code.pretty(c) == "K3QX-9F2M-HT4C-7PW5", "code: its groups")
	# I and L read as 1, O as 0: a code holding 1 and 0 typed with I, L and O
	var c10 := "10ABCDEFGH10JKM"
	c10 += Code.check_char(c10)
	_ok(Code.normalize("IOABCDEFGHLOJKM" + c10[15]) == c10, "code: I, L and O read as 1, 1 and 0")
	_ok(Code.ikm(c).hex_encode() == "98efd4bc548e88c3db80", "code: its 75 bits")
	var k := Code.keys(c)
	_ok(k["room"].hex_encode() == "4dfe9cccf641ff820bcb37c6bd86ebb0", "code: room")
	_ok(k["admit"].hex_encode() == "f5c8b719fc6c952f13693269af398bfb3f73f497d812285b1201ca89b875b151", "code: admit")
	_ok(k["K"].hex_encode() == "eba2e8f6a4b6e223a4a6a6ded62bde895f6fade162461a768ee013d29bea408d", "code: K")
	_ok(k["lan"].hex_encode() == "b69cded1561bf1978dc155a3dedfd2b76acd481ae8531d20975fa01ad32f86c0", "code: the LAN key")
	# made codes: valid, distinct; a single typo is caught (all but about one in 32)
	var seen := {}
	var caught := 0
	var typos := 0
	for i in 200:
		var m := Code.make()
		_ok(m.length() == 16 and Code.normalize(m) == m, "code: a made code is valid (%s)" % m)
		seen[m] = true
		var at := i % 15
		var ch := Code.ALPHABET[(Code.ALPHABET.find(m[at]) + 1 + i % 31) % 32]
		var typo := m.substr(0, at) + ch + m.substr(at + 1)
		typos += 1
		if Code.normalize(typo) == "":
			caught += 1
	_ok(seen.size() == 200, "code: made codes differ")
	_ok(caught >= typos * 0.9, "code: typos caught (%d of %d)" % [caught, typos])
	_ok(Code.link(c) == "walkdown-plant://join/K3QX9F2MHT4C7PW5", "code: its link")


func _replay() -> void:
	var r := Wire.Replay.new()
	_ok(not r.fresh(0), "replay: 0 is never a number")
	_ok(r.fresh(1), "replay: the first")
	r.record(1)
	_ok(not r.fresh(1), "replay: seen")
	r.record(300)
	_ok(r.fresh(299) and r.fresh(45), "replay: within the window, unseen")
	_ok(not r.fresh(44), "replay: 256 below the highest")
	r.record(299)
	_ok(not r.fresh(299) and not r.fresh(300), "replay: seen within the window")
	r.record(1000)
	_ok(r.fresh(800) and not r.fresh(744), "replay: the window moves")


func _packets() -> void:
	var key := Crypt.random_bytes(32)
	var head := Wire.header(Wire.KEY_P, 3, 0, 1, 0xdeadbeef, 77)
	var body := Wire.reliable_msg(Wire.Kind.INPUT, Wire.STREAM_MAIN, 5, "abc".to_utf8_buffer())
	body.append_array(Wire.msg(Wire.Kind.ACK, PackedByteArray([1, 2, 3])))
	var pk := Wire.seal(key, head, body)
	var h := Wire.read_header(pk)
	_ok(h == {"key": 1, "from": 3, "to": 0, "epoch": 1, "inc": 0xdeadbeef, "number": 77}, "packet: its header (%s)" % str(h))
	var plain = Wire.open(key, pk)
	_ok(plain == body, "packet: opens")
	var ms = Wire.messages(plain)
	_ok(ms != null and ms.size() == 2 and ms[0]["kind"] == Wire.Kind.INPUT and ms[0]["seq"] == 5 \
			and ms[0]["fields"] == "abc".to_utf8_buffer() and not ms[1]["reliable"] and ms[1]["fields"].size() == 3,
			"packet: its messages")
	var moved := pk.duplicate()
	moved[2] = 4                                # another `from` on the same body: the header is the AAD
	_ok(Wire.open(key, moved) == null, "packet: a header moved onto another body is refused")
	_ok(Wire.open(Crypt.random_bytes(32), pk) == null, "packet: another key is refused")
	_ok(Wire.messages(body.slice(0, body.size() - 1)) == null, "messages: cut short")
	_ok(Wire.messages(PackedByteArray([99, 0, 0])) == null, "messages: an unknown kind")
	_ok(Wire.messages(PackedByteArray([Wire.Kind.INPUT, 0, 2, 0, 0])) == null, "messages: a reliable one without its sequence")
	_ok(Wire.read_header(PackedByteArray([2]) + pk.slice(1)).is_empty(), "packet: another version")
