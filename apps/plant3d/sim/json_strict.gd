extends RefCounted
## Strict JSON reading for the plant's content (docs/PLANT3D.md §1), as ref/sjson.py reads it: UTF-8 only, no
## byte-order mark, no duplicate keys, trailing commas, leading zeros, NaN or Infinity, control characters or unpaired
## surrogates in strings, no bytes after the value, at most 128 levels deep. One difference: an escaped U+0000 is
## refused (ref/sjson.py accepts it), as a Godot String can't hold it; no content needs it. A U+FEFF in a string is kept.
##
## Numbers are read as Python reads them, which Godot's JSON parser does not do:
## - an integer token (no fraction, no exponent) within ±(2^63 − 1) is an int ("-0" is the int 0); a longer one is a
##   float (Python keeps it as a big integer; no content number is that large);
## - every other number is the IEEE double nearest to its decimal value, ties to even (correctly rounded, like
##   Python's float()). Godot's own JSON.parse_string and String.to_float are off by one or two units in the last place
##   for some 17-digit numbers (0.016666666666666666 in the first train's model is one), so they are not used.
##
##   var r := JsonStrict.parse(bytes)     # {"ok": true, "value": v} or {"ok": false, "error": "…"}

const MAX_DEPTH := 128
const INT_MAX_TEXT := "9223372036854775807"
const BASE := 16777216          # bignum limbs of 24 bits
const MAX_DOUBLE := 1.7976931348623157e308

var _b: PackedByteArray
var _p := 0
var _n := 0
var _err := ""
var _max_depth := MAX_DEPTH


## max_depth: 128 for content (ref/sjson.py); a test reading a vector file that holds 128-deep values gives more.
static func parse(data: PackedByteArray, max_depth: int = MAX_DEPTH) -> Dictionary:
	var r = new()
	r._max_depth = max_depth
	return r._run(data)


static func parse_text(text: String, max_depth: int = MAX_DEPTH) -> Dictionary:
	return parse(text.to_utf8_buffer(), max_depth)


func _run(data: PackedByteArray) -> Dictionary:
	_b = data
	_n = data.size()
	_p = 0
	if _n >= 3 and data[0] == 0xEF and data[1] == 0xBB and data[2] == 0xBF:
		return {"ok": false, "error": "byte-order mark"}
	var bad := _check_utf8()
	if bad != "":
		return {"ok": false, "error": bad}
	_ws()
	var v = _value(0)
	if _err != "":
		return {"ok": false, "error": "%s at byte %d" % [_err, _p]}
	_ws()
	if _p != _n:
		return {"ok": false, "error": "extra data at byte %d" % _p}
	return {"ok": true, "value": v}


func _check_utf8() -> String:
	var i := 0
	var b := _b
	var n := _n
	while i < n:
		var c: int = b[i]
		if c < 0x80:
			i += 1
			continue
		var need := 0
		var cp := 0
		var lo := 0
		if c >= 0xC2 and c <= 0xDF:
			need = 1
			cp = c & 0x1F
			lo = 0x80
		elif c >= 0xE0 and c <= 0xEF:
			need = 2
			cp = c & 0x0F
			lo = 0x800
		elif c >= 0xF0 and c <= 0xF4:
			need = 3
			cp = c & 0x07
			lo = 0x10000
		else:
			return "not UTF-8"
		if i + need >= n:
			return "not UTF-8"      # truncated
		for k in range(1, need + 1):
			var cc: int = b[i + k]
			if (cc & 0xC0) != 0x80:
				return "not UTF-8"
			cp = (cp << 6) | (cc & 0x3F)
		if cp < lo or cp > 0x10FFFF or (cp >= 0xD800 and cp <= 0xDFFF):
			return "not UTF-8"
		i += need + 1
	return ""


func _ws() -> void:
	while _p < _n:
		var c: int = _b[_p]
		if c == 0x20 or c == 0x0A or c == 0x0D or c == 0x09:
			_p += 1
		else:
			return


func _fail(msg: String):
	if _err == "":
		_err = msg
	return null


func _value(depth: int):
	if _p >= _n:
		return _fail("unexpected end")
	var c: int = _b[_p]
	if c == 0x7B:   # {
		return _object(depth + 1)
	if c == 0x5B:   # [
		return _array(depth + 1)
	if c == 0x22:   # "
		return _string()
	if c == 0x2D or (c >= 0x30 and c <= 0x39):
		return _number()
	if _word("true"):
		return true
	if _word("false"):
		return false
	if _word("null"):
		return null
	return _fail("unexpected character")


func _word(w: String) -> bool:
	var l := w.length()
	if _p + l > _n:
		return false
	for k in l:
		if _b[_p + k] != w.unicode_at(k):
			return false
	_p += l
	return true


func _object(depth: int):
	if depth > _max_depth:
		return _fail("too deep")
	_p += 1
	var d := {}
	_ws()
	if _p < _n and _b[_p] == 0x7D:
		_p += 1
		return d
	while true:
		_ws()
		if _p >= _n or _b[_p] != 0x22:
			return _fail("expected a key")
		var k = _string()
		if _err != "":
			return null
		if d.has(k):
			return _fail("duplicate key")
		_ws()
		if _p >= _n or _b[_p] != 0x3A:
			return _fail("expected ':'")
		_p += 1
		_ws()
		var v = _value(depth)
		if _err != "":
			return null
		d[k] = v
		_ws()
		if _p >= _n:
			return _fail("unclosed object")
		var c: int = _b[_p]
		_p += 1
		if c == 0x7D:
			return d
		if c != 0x2C:
			return _fail("expected ',' or '}'")
	return null


func _array(depth: int):
	if depth > _max_depth:
		return _fail("too deep")
	_p += 1
	var a := []
	_ws()
	if _p < _n and _b[_p] == 0x5D:
		_p += 1
		return a
	while true:
		_ws()
		var v = _value(depth)
		if _err != "":
			return null
		a.append(v)
		_ws()
		if _p >= _n:
			return _fail("unclosed array")
		var c: int = _b[_p]
		_p += 1
		if c == 0x5D:
			return a
		if c != 0x2C:
			return _fail("expected ',' or ']'")
	return null


func _hex4(at: int) -> int:
	if at + 4 > _n:
		return -1
	var v := 0
	for k in 4:
		var c: int = _b[at + k]
		var d := -1
		if c >= 0x30 and c <= 0x39:
			d = c - 0x30
		elif c >= 0x61 and c <= 0x66:
			d = c - 0x61 + 10
		elif c >= 0x41 and c <= 0x46:
			d = c - 0x41 + 10
		if d < 0:
			return -1
		v = v * 16 + d
	return v


## Bytes a … b − 1 (valid UTF-8) as text. get_string_from_utf8 drops a leading U+FEFF as a byte-order mark: it is
## a character here, kept as Python keeps it.
func _utf8(a: int, b: int) -> String:
	var lead := ""
	while a + 3 <= b and _b[a] == 0xEF and _b[a + 1] == 0xBB and _b[a + 2] == 0xBF:
		lead += String.chr(0xFEFF)
		a += 3
	if a >= b:
		return lead
	return lead + _b.slice(a, b).get_string_from_utf8()


func _string():
	_p += 1
	var out := ""
	var run := _p
	while true:
		if _p >= _n:
			return _fail("unclosed string")
		var c: int = _b[_p]
		if c == 0x22:
			if _p > run:
				out += _utf8(run, _p)
			_p += 1
			return out
		if c < 0x20:
			return _fail("control character in a string")
		if c != 0x5C:
			_p += 1
			continue
		if _p > run:
			out += _utf8(run, _p)
		if _p + 1 >= _n:
			return _fail("unclosed string")
		var e: int = _b[_p + 1]
		_p += 2
		match e:
			0x22: out += "\""
			0x5C: out += "\\"
			0x2F: out += "/"
			0x62: out += String.chr(8)
			0x66: out += String.chr(12)
			0x6E: out += "\n"
			0x72: out += "\r"
			0x74: out += "\t"
			0x75:
				var u := _hex4(_p)
				if u < 0:
					return _fail("bad \\u escape")
				_p += 4
				if u >= 0xD800 and u <= 0xDBFF:
					# a high surrogate must be followed by an escaped low one
					if _p + 1 < _n and _b[_p] == 0x5C and _b[_p + 1] == 0x75:
						var lo := _hex4(_p + 2)
						if lo >= 0xDC00 and lo <= 0xDFFF:
							_p += 6
							out += String.chr(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00))
						else:
							return _fail("unpaired surrogate")
					else:
						return _fail("unpaired surrogate")
				elif u >= 0xDC00 and u <= 0xDFFF:
					return _fail("unpaired surrogate")
				elif u == 0:
					return _fail("an escaped NUL (a Godot String can't hold it)")
				else:
					out += String.chr(u)
			_:
				return _fail("bad escape")
		run = _p
	return null


func _digits_from(at: int) -> int:
	var q := at
	while q < _n and _b[q] >= 0x30 and _b[q] <= 0x39:
		q += 1
	return q


func _number():
	var start := _p
	var neg := false
	if _b[_p] == 0x2D:
		neg = true
		_p += 1
	if _p >= _n:
		return _fail("bad number")
	var int_start := _p
	if _b[_p] == 0x30:
		_p += 1
	elif _b[_p] >= 0x31 and _b[_p] <= 0x39:
		_p = _digits_from(_p)
	else:
		return _fail("bad number")
	var int_part := _b.slice(int_start, _p).get_string_from_ascii()
	var frac := ""
	var is_float := false
	var exp10 := 0
	if _p < _n and _b[_p] == 0x2E:
		var f0 := _p + 1
		var f1 := _digits_from(f0)
		if f1 == f0:
			return _fail("bad number")
		frac = _b.slice(f0, f1).get_string_from_ascii()
		_p = f1
		is_float = true
	if _p < _n and (_b[_p] == 0x65 or _b[_p] == 0x45):
		var q := _p + 1
		var eneg := false
		if q < _n and (_b[q] == 0x2B or _b[q] == 0x2D):
			eneg = _b[q] == 0x2D
			q += 1
		var e1 := _digits_from(q)
		if e1 == q:
			return _fail("bad number")
		var et := _b.slice(q, e1).get_string_from_ascii().lstrip("0")
		var ev := 0
		if et.length() > 9:
			ev = 1000000000
		elif et != "":
			ev = et.to_int()
		exp10 = -ev if eneg else ev
		_p = e1
		is_float = true
	if not is_float:
		if int_part.length() < 19 or (int_part.length() == 19 and int_part <= INT_MAX_TEXT):
			var iv := int_part.to_int()
			return -iv if neg else iv
	return decimal_to_float(neg, int_part + frac, exp10 - frac.length())


# ---------------------------------------------------------------- correctly rounded decimal → double

static var _p10 := PackedFloat64Array()


static func _pow10_table() -> PackedFloat64Array:
	if _p10.is_empty():
		var x := 1.0
		for k in 23:
			_p10.append(x)
			x *= 10.0          # exact up to 1e22
	return _p10


## The double nearest to (−1 if neg) × digits × 10^exp10, ties to even. digits: decimal digits, any length.
static func decimal_to_float(neg: bool, digits: String, exp10: int) -> float:
	var ds := digits.lstrip("0")
	var trimmed := ds.rstrip("0")
	exp10 += ds.length() - trimmed.length()
	ds = trimmed
	var x := 0.0
	if ds == "":
		x = 0.0
	elif ds.length() <= 15 and exp10 >= -22 and exp10 <= 22:
		# exact integer and exact power of ten: one IEEE operation, correctly rounded (Clinger's fast path)
		var t := _pow10_table()
		var m := float(ds.to_int())
		x = m * t[exp10] if exp10 >= 0 else m / t[-exp10]
	else:
		var mag := ds.length() + exp10       # value in [10^(mag-1), 10^mag)
		if mag > 310:
			x = INF
		elif mag < -324:
			x = 0.0
		else:
			x = _slow(ds, exp10)
	return -x if neg else x


static func _slow(ds: String, exp10: int) -> float:
	# a close first guess from the leading 17 digits, then exact comparisons with the halfway points
	var lead := ds.substr(0, 17)
	var e := exp10 + ds.length() - lead.length()
	var x := float(lead.to_int())
	var e1 := e / 2
	var e2 := e - e1
	x = x * pow(10.0, e1) * pow(10.0, e2)
	if is_inf(x) or x > MAX_DOUBLE:
		x = MAX_DOUBLE
	if is_nan(x) or x < 0.0:
		x = 0.0
	var big_n := _big_from_digits(ds)
	for _iter in 4096:
		var mk := _mk(x)
		var m: int = mk[0]
		var k: int = mk[1]
		var c := _cmp(big_n, exp10, 2 * m + 1, k - 1)
		if c > 0 or (c == 0 and (m & 1) == 1):
			if x == MAX_DOUBLE:
				return INF
			x = _next(x, 1)
			continue
		if x > 0.0:
			var lm := 2 * m - 1
			var lk := k - 1
			if (m == (1 << 52)) and _biased_exp(x) > 1:
				lm = 4 * m - 1
				lk = k - 2
			c = _cmp(big_n, exp10, lm, lk)
			if c < 0 or (c == 0 and (m & 1) == 1):
				x = _next(x, -1)
				continue
		return x
	push_error("JsonStrict: number did not converge: %s e%d" % [ds, exp10])
	return x


static func _bits(x: float) -> int:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, x)
	return b.decode_s64(0)


static func _from_bits(v: int) -> float:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_s64(0, v)
	return b.decode_double(0)


static func _biased_exp(x: float) -> int:
	return (_bits(x) >> 52) & 0x7FF


static func _mk(x: float) -> Array:
	var bits := _bits(x)
	var be := (bits >> 52) & 0x7FF
	var f := bits & ((1 << 52) - 1)
	if be == 0:
		return [f, -1074]
	return [f | (1 << 52), be - 1075]


static func _next(x: float, dir: int) -> float:
	return _from_bits(_bits(x) + dir)


static func _big_from_digits(ds: String) -> Array:
	var a := [0]
	var i := 0
	var l := ds.length()
	var first := l % 7
	if first == 0:
		first = 7
	while i < l:
		var take := first if i == 0 else 7
		var chunk := ds.substr(i, take).to_int()
		var f := 1
		for _k in take:
			f *= 10
		_mul_add(a, f, chunk)
		i += take
	return a


static func _mul_add(a: Array, f: int, add: int) -> void:
	var carry := add
	for i in a.size():
		var v: int = a[i] * f + carry
		a[i] = v % BASE
		carry = v / BASE
	while carry > 0:
		a.append(carry % BASE)
		carry /= BASE


static func _mul_pow10(a: Array, e: int) -> void:
	while e >= 7:
		_mul_add(a, 10000000, 0)
		e -= 7
	if e > 0:
		var f := 1
		for _k in e:
			f *= 10
		_mul_add(a, f, 0)


static func _shl(a: Array, s: int) -> void:
	while s >= 24:
		a.push_front(0)
		s -= 24
	if s > 0:
		_mul_add(a, 1 << s, 0)


static func _big_cmp(a: Array, b: Array) -> int:
	var la := a.size()
	while la > 1 and a[la - 1] == 0:
		la -= 1
	var lb := b.size()
	while lb > 1 and b[lb - 1] == 0:
		lb -= 1
	if la != lb:
		return 1 if la > lb else -1
	for i in range(la - 1, -1, -1):
		if a[i] != b[i]:
			return 1 if a[i] > b[i] else -1
	return 0


## Compares n × 10^e10 with m × 2^e2 exactly (n a bignum, m ≥ 0 an int below 2^62).
static func _cmp(n: Array, e10: int, m: int, e2: int) -> int:
	var l := n.duplicate()
	var r := [0]
	_mul_add(r, 1, m)
	if e10 >= 0:
		_mul_pow10(l, e10)
	else:
		_mul_pow10(r, -e10)
	if e2 >= 0:
		_shl(r, e2)
	else:
		_shl(l, -e2)
	return _big_cmp(l, r)
