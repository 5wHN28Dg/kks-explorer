## The session's invite code (docs/plant3d/MULTIPLAYER.md §1.1, §1.3): 16 characters of Crockford's base32 alphabet
## (no I, L, O or U), shown in four groups (`K3QX-9F2M-HT4C-7PWD`): 15 random characters (75 bits) and a check
## character, the first 5 bits of SHA-256("wdp-code-v1\n" + the first 15 characters). Typing is forgiving as
## Crockford's decoding is: I and L read as 1, O as 0, lower case as upper case, dashes and spaces ignored.
##
## The keys (§1.3), by HKDF-SHA-256 with the salt "walkdown-plant-mp-v1" (net/crypto.gd) from S, the 75 random bits
## as 10 bytes (the 15 characters' 5-bit values one after the other, most significant bit first, then 5 zero bits):
##   room   16 bytes, info "room"    the relay room and the LAN query's ID
##   admit  32 bytes, info "admit"   the relay's admission token
##   K      32 bytes, info "group"   the session key
##   lan    32 bytes, HKDF(K, info "lan")   the LAN answer's MAC key
extends RefCounted

const Crypt = preload("res://net/crypto.gd")

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const CHECK_TAG := "wdp-code-v1\n"
const LINK_PREFIX := "walkdown-plant://join/"


## A new code (16 characters, no dashes).
static func make() -> String:
	var r := Crypt.random_bytes(10)
	var s := ""
	for k in 15:
		s += ALPHABET[_bits5(r, k * 5)]
	return s + check_char(s)


static func _bits5(b: PackedByteArray, at: int) -> int:
	var v := 0
	for k in 5:
		var bit := at + k
		v = (v << 1) | ((b[bit >> 3] >> (7 - (bit & 7))) & 1)
	return v


## The check character of the first 15 characters.
static func check_char(first15: String) -> String:
	var h := Crypt.sha256((CHECK_TAG + first15).to_utf8_buffer())
	return ALPHABET[h[0] >> 3]


## The code as typed, read forgivingly: 16 characters without dashes, or "" when it is not a code (a wrong length, a
## character outside the alphabet, or a check character that doesn't match: a typo).
static func normalize(text: String) -> String:
	var s := ""
	for ch in text.to_upper():
		if ch == "-" or ch == " ":
			continue
		if ch == "I" or ch == "L":
			ch = "1"
		elif ch == "O":
			ch = "0"
		if not ALPHABET.contains(ch):
			return ""
		s += ch
	if s.length() != 16 or check_char(s.substr(0, 15)) != s[15]:
		return ""
	return s


## In four groups for the screen.
static func pretty(code: String) -> String:
	return "%s-%s-%s-%s" % [code.substr(0, 4), code.substr(4, 4), code.substr(8, 4), code.substr(12, 4)]


static func link(code: String) -> String:
	return LINK_PREFIX + code


## S: the 75 random bits as 10 bytes.
static func ikm(code: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(10)
	var bit := 0
	for k in 15:
		var v := ALPHABET.find(code[k])
		for j in range(4, -1, -1):
			if (v >> j) & 1:
				out[bit >> 3] |= 1 << (7 - (bit & 7))
			bit += 1
	return out


## The session's keys from a normalized code.
static func keys(code: String) -> Dictionary:
	var s := ikm(code)
	var k := Crypt.derive(s, "group", 32)
	return {"room": Crypt.derive(s, "room", 16), "admit": Crypt.derive(s, "admit", 32), "K": k,
			"lan": Crypt.derive(k, "lan", 32)}
