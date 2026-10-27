## The session's cryptography (docs/plant3d/MULTIPLAYER.md §1.3, decision 0068), from Godot's own primitives only:
## - HKDF-SHA-256 (RFC 5869) on `Crypto.hmac_digest`;
## - the AEAD AEAD_AES_128_CBC_HMAC_SHA_256 of RFC 7518 §5.2.2 ("A128CBC-HS256"): the 32-byte key's first half is the
##   MAC key, its second half the AES-128 key; a random 16-byte IV per message, PKCS#7 padding; the tag is the first 16
##   bytes of HMAC-SHA-256 over AAD ‖ IV ‖ ciphertext ‖ the AAD's length in bits as a 64-bit big-endian number.
##   A sealed body is IV ‖ ciphertext ‖ tag (RFC 7518 B.1 is its test vector: tests/test_net_crypto.gd).
## Big-endian helpers for the wire formats are here too.
extends RefCounted

const SALT := "walkdown-plant-mp-v1"
const IV_LEN := 16
const TAG_LEN := 16
const OVERHEAD := IV_LEN + TAG_LEN      # plus 1–16 bytes of padding

static var _c: Crypto


static func crypto() -> Crypto:
	if _c == null:
		_c = Crypto.new()
	return _c


static func random_bytes(n: int) -> PackedByteArray:
	return crypto().generate_random_bytes(n)


static func hmac(key: PackedByteArray, msg: PackedByteArray) -> PackedByteArray:
	if key.is_empty():
		key = PackedByteArray()
		key.resize(32)              # (RFC 2104: a key is padded with zeros; mbedTLS refuses an empty one)
	return crypto().hmac_digest(HashingContext.HASH_SHA256, key, msg)


static func sha256(b: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish()


## Whether a and b are the same bytes, in time that doesn't depend on where they differ.
static func same(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.size() != b.size() or a.is_empty():
		return a.size() == b.size() and a.is_empty()
	return crypto().constant_time_compare(a, b)


## HKDF-SHA-256 (RFC 5869): `length` bytes from the input key material, a salt and an info.
static func hkdf(ikm: PackedByteArray, salt: PackedByteArray, info: PackedByteArray, length: int) -> PackedByteArray:
	var prk := hmac(salt, ikm)          # (an empty salt is HashLen zeros: hmac() pads it so)
	var out := PackedByteArray()
	var t := PackedByteArray()
	var i := 1
	while out.size() < length:
		var m := t.duplicate()
		m.append_array(info)
		m.append(i)
		t = hmac(prk, m)
		out.append_array(t)
		i += 1
	return out.slice(0, length)


## HKDF with the session's salt and a text info (MULTIPLAYER.md §1.3).
static func derive(ikm: PackedByteArray, info: String, length: int) -> PackedByteArray:
	return hkdf(ikm, SALT.to_utf8_buffer(), info.to_utf8_buffer(), length)


# ------------------------------------------------------------------ the AEAD

static func _tag(mac_key: PackedByteArray, aad: PackedByteArray, iv: PackedByteArray, ct: PackedByteArray) -> PackedByteArray:
	var m := aad.duplicate()
	m.append_array(iv)
	m.append_array(ct)
	var al := PackedByteArray()
	al.resize(8)
	put_u64(al, 0, aad.size() * 8)
	m.append_array(al)
	return hmac(mac_key, m).slice(0, TAG_LEN)


## Seals plain under the 32-byte key with aad: IV ‖ ciphertext ‖ tag. `iv` is for the test vector only (random when
## empty).
static func seal(key: PackedByteArray, aad: PackedByteArray, plain: PackedByteArray, iv := PackedByteArray()) -> PackedByteArray:
	assert(key.size() == 32)
	if iv.is_empty():
		iv = random_bytes(IV_LEN)
	var pad := 16 - plain.size() % 16
	var p := plain.duplicate()
	for k in pad:
		p.append(pad)
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_ENCRYPT, key.slice(16, 32), iv)
	var ct := aes.update(p)
	aes.finish()
	var out := iv.duplicate()
	out.append_array(ct)
	out.append_array(_tag(key.slice(0, 16), aad, iv, ct))
	return out


## The plain text of a sealed body, or null when its tag, size or padding is wrong.
static func open(key: PackedByteArray, aad: PackedByteArray, body: PackedByteArray):
	if key.size() != 32 or body.size() < OVERHEAD + 16 or (body.size() - OVERHEAD) % 16 != 0:
		return null
	var iv := body.slice(0, IV_LEN)
	var ct := body.slice(IV_LEN, body.size() - TAG_LEN)
	if not same(_tag(key.slice(0, 16), aad, iv, ct), body.slice(body.size() - TAG_LEN)):
		return null
	var aes := AESContext.new()
	aes.start(AESContext.MODE_CBC_DECRYPT, key.slice(16, 32), iv)
	var p := aes.update(ct)
	aes.finish()
	var pad := p[p.size() - 1]
	if pad < 1 or pad > 16:
		return null
	for k in pad:
		if p[p.size() - 1 - k] != pad:
			return null
	return p.slice(0, p.size() - pad)


# ------------------------------------------------------------------ big-endian numbers (the wire's)

static func put_u16(b: PackedByteArray, at: int, v: int) -> void:
	b[at] = (v >> 8) & 0xff
	b[at + 1] = v & 0xff


static func put_u32(b: PackedByteArray, at: int, v: int) -> void:
	for k in 4:
		b[at + k] = (v >> (24 - 8 * k)) & 0xff


static func put_u64(b: PackedByteArray, at: int, v: int) -> void:
	for k in 8:
		b[at + k] = (v >> (56 - 8 * k)) & 0xff


static func u16(b: PackedByteArray, at: int) -> int:
	return (b[at] << 8) | b[at + 1]


static func u32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func be16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	put_u16(b, 0, v)
	return b


static func be32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	put_u32(b, 0, v)
	return b
