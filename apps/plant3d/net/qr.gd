## A QR code encoder (ISO/IEC 18004) for the session's invite link (docs/plant3d/MULTIPLAYER.md §1.1): byte mode,
## error correction level M, versions 1 to 10, the mask with the lowest penalty. Godot has no QR class; the link a phone's
## camera app reads is walkdown-plant://join/<code> (38 bytes: version 3).
##   QR.encode("text") -> {"size": n, "modules": PackedByteArray (n × n, 1 dark), "version", "mask"} or {} when too long
## tests/test_net_qr.gd checks it against matrices made by an independent encoder (segno) for the same version and mask.
extends RefCounted

const ECC_M := [-1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26]        # error correction codewords per block (M)
const BLOCKS_M := [-1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5]               # blocks (M)
const MAX_VERSION := 10


static func _raw_modules(ver: int) -> int:
	var r := (16 * ver + 128) * ver + 64
	if ver >= 2:
		var na := ver / 7 + 2
		r -= (25 * na - 10) * na - 55
		if ver >= 7:
			r -= 36
	return r


static func _data_codewords(ver: int) -> int:
	return _raw_modules(ver) / 8 - ECC_M[ver] * BLOCKS_M[ver]


## The code, or {} when the text is too long. `force_mask` (0–7) and `force_version` for the tests.
static func encode(text: String, force_mask := -1, force_version := -1) -> Dictionary:
	var data := text.to_utf8_buffer()
	var ver := -1
	for v in range(1, MAX_VERSION + 1):
		var cc_bits := 8 if v <= 9 else 16
		if 4 + cc_bits + data.size() * 8 <= _data_codewords(v) * 8 and (force_version == -1 or v == force_version):
			ver = v
			break
	if ver == -1:
		return {}
	# the bit stream: byte mode, the count, the bytes, a terminator, padding
	var bits := []
	_put(bits, 4, 4)
	_put(bits, data.size(), 8 if ver <= 9 else 16)
	for b in data:
		_put(bits, b, 8)
	var cap := _data_codewords(ver) * 8
	_put(bits, 0, mini(4, cap - bits.size()))
	_put(bits, 0, (8 - bits.size() % 8) % 8)
	var pad := 0xEC
	while bits.size() < cap:
		_put(bits, pad, 8)
		pad = 0x11 if pad == 0xEC else 0xEC
	var cw := PackedByteArray()
	cw.resize(bits.size() / 8)
	for i in bits.size():
		cw[i >> 3] |= bits[i] << (7 - (i & 7))
	var all := _with_ecc(cw, ver)
	var size := ver * 4 + 17
	var m := PackedByteArray()
	m.resize(size * size)
	var fn := PackedByteArray()          # function modules (not data)
	fn.resize(size * size)
	_function_patterns(m, fn, size, ver)
	_place(m, fn, size, all)
	var best := -1
	var best_pen := 1 << 62
	var best_m: PackedByteArray
	for mask in 8:
		if force_mask != -1 and mask != force_mask:
			continue
		var t := m.duplicate()
		_apply_mask(t, fn, size, mask)
		_format_bits(t, fn, size, mask)
		var pen := _penalty(t, size)
		if pen < best_pen:
			best_pen = pen
			best = mask
			best_m = t
	return {"size": size, "modules": best_m, "version": ver, "mask": best}


static func _put(bits: Array, v: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((v >> i) & 1)


# ------------------------------------------------------------------ Reed-Solomon over GF(256), x^8+x^4+x^3+x^2+1

static func _mul(x: int, y: int) -> int:
	var z := 0
	for i in range(7, -1, -1):
		z = (z << 1) ^ ((z >> 7) * 0x11D)
		z ^= ((y >> i) & 1) * x
	return z & 0xff


static func _divisor(degree: int) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(degree)
	r[degree - 1] = 1
	var root := 1
	for i in degree:
		for j in degree:
			r[j] = _mul(r[j], root)
			if j + 1 < degree:
				r[j] ^= r[j + 1]
		root = _mul(root, 0x02)
	return r


static func _remainder(data: PackedByteArray, div: PackedByteArray) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(div.size())
	for b in data:
		var f := b ^ r[0]
		r = r.slice(1)
		r.append(0)
		for i in div.size():
			r[i] ^= _mul(div[i], f)
	return r


static func _with_ecc(data: PackedByteArray, ver: int) -> PackedByteArray:
	var nb: int = BLOCKS_M[ver]
	var ecl: int = ECC_M[ver]
	var raw := _raw_modules(ver) / 8
	var short_n := nb - raw % nb
	var short_len := raw / nb
	var div := _divisor(ecl)
	var blocks := []
	var k := 0
	for i in nb:
		var n := short_len - ecl + (0 if i < short_n else 1)
		var dat := data.slice(k, k + n)
		k += n
		var ec := _remainder(dat, div)
		if i < short_n:
			dat.append(0)           # (a placeholder so that every block is as long; skipped when interleaving)
		dat.append_array(ec)
		blocks.append(dat)
	var out := PackedByteArray()
	for i in blocks[0].size():
		for j in blocks.size():
			if i != short_len - ecl or j >= short_n:
				out.append(blocks[j][i])
	return out


# ------------------------------------------------------------------ the matrix

static func _mod(m: PackedByteArray, fn: PackedByteArray, size: int, x: int, y: int, dark: bool) -> void:
	m[y * size + x] = 1 if dark else 0
	fn[y * size + x] = 1


static func _function_patterns(m: PackedByteArray, fn: PackedByteArray, size: int, ver: int) -> void:
	for i in size:
		_mod(m, fn, size, 6, i, i % 2 == 0)
		_mod(m, fn, size, i, 6, i % 2 == 0)
	for c in [[3, 3], [size - 4, 3], [3, size - 4]]:
		for dy in range(-4, 5):
			for dx in range(-4, 5):
				var x: int = c[0] + dx
				var y: int = c[1] + dy
				if x >= 0 and x < size and y >= 0 and y < size:
					var d := maxi(absi(dx), absi(dy))
					_mod(m, fn, size, x, y, d != 2 and d != 4)
	var al := _alignment_positions(ver)
	var na := al.size()
	for i in na:
		for j in na:
			if (i == 0 and j == 0) or (i == 0 and j == na - 1) or (i == na - 1 and j == 0):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					_mod(m, fn, size, al[i] + dx, al[j] + dy, maxi(absi(dx), absi(dy)) != 1)
	_format_bits(m, fn, size, 0)        # (reserves the format areas; written again with the mask)
	if ver >= 7:
		var rem := ver
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var bits := (ver << 12) | rem
		for i in 18:
			var bit := ((bits >> i) & 1) == 1
			var a := size - 11 + i % 3
			var b := i / 3
			_mod(m, fn, size, a, b, bit)
			_mod(m, fn, size, b, a, bit)


static func _alignment_positions(ver: int) -> Array:
	if ver == 1:
		return []
	var na := ver / 7 + 2
	var step := (ver * 8 + na * 3 + 5) / (na * 4 - 4) * 2
	var out := [6]
	var pos := ver * 4 + 17 - 7
	var rest := []
	for i in na - 1:
		rest.push_front(pos)
		pos -= step
	out.append_array(rest)
	return out


static func _format_bits(m: PackedByteArray, fn: PackedByteArray, size: int, mask: int) -> void:
	var data := (0 << 3) | mask          # error correction level M is 0b00
	var rem := data
	for i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_mod(m, fn, size, 8, i, ((bits >> i) & 1) == 1)
	_mod(m, fn, size, 8, 7, ((bits >> 6) & 1) == 1)
	_mod(m, fn, size, 8, 8, ((bits >> 7) & 1) == 1)
	_mod(m, fn, size, 7, 8, ((bits >> 8) & 1) == 1)
	for i in range(9, 15):
		_mod(m, fn, size, 14 - i, 8, ((bits >> i) & 1) == 1)
	for i in range(0, 8):
		_mod(m, fn, size, size - 1 - i, 8, ((bits >> i) & 1) == 1)
	for i in range(8, 15):
		_mod(m, fn, size, 8, size - 15 + i, ((bits >> i) & 1) == 1)
	_mod(m, fn, size, 8, size - 8, true)      # the dark module


static func _place(m: PackedByteArray, fn: PackedByteArray, size: int, data: PackedByteArray) -> void:
	var i := 0
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if fn[y * size + x] == 0 and i < data.size() * 8:
					m[y * size + x] = (data[i >> 3] >> (7 - (i & 7))) & 1
					i += 1
		right -= 2


static func _apply_mask(m: PackedByteArray, fn: PackedByteArray, size: int, mask: int) -> void:
	for y in size:
		for x in size:
			if fn[y * size + x] == 1:
				continue
			var inv := false
			match mask:
				0: inv = (x + y) % 2 == 0
				1: inv = y % 2 == 0
				2: inv = x % 3 == 0
				3: inv = (x + y) % 3 == 0
				4: inv = (x / 3 + y / 2) % 2 == 0
				5: inv = x * y % 2 + x * y % 3 == 0
				6: inv = (x * y % 2 + x * y % 3) % 2 == 0
				7: inv = ((x + y) % 2 + x * y % 3) % 2 == 0
			if inv:
				m[y * size + x] ^= 1


static func _penalty(m: PackedByteArray, size: int) -> int:
	var p := 0
	# runs of 5 or more of one colour, and the finder-like patterns, in rows and columns
	for pass_ in 2:
		for a in size:
			var run_col := 0            # (light before the first module, as the border is)
			var run := 0
			var hist := [0, 0, 0, 0, 0, 0, 0]
			for b in size:
				var c: int = m[a * size + b] if pass_ == 0 else m[b * size + a]
				if c == run_col:
					run += 1
					if run == 5:
						p += 3
					elif run > 5:
						p += 1
				else:
					_hist_add(hist, run, size)
					if run_col == 0:
						p += _finder_count(hist) * 40
					run_col = c
					run = 1
			p += _finder_terminate(hist, run_col, run, size) * 40
	# 2×2 blocks of one colour
	for y in size - 1:
		for x in size - 1:
			var c: int = m[y * size + x]
			if c == m[y * size + x + 1] and c == m[(y + 1) * size + x] and c == m[(y + 1) * size + x + 1]:
				p += 3
	# the balance of dark and light
	var dark := 0
	for v in m:
		dark += v
	var total := size * size
	var k := (absi(dark * 20 - total * 10) + total - 1) / total - 1
	p += k * 10
	return p


static func _hist_add(hist: Array, run: int, size: int) -> void:
	if hist[0] == 0:
		run += size             # (the light border counts as light before the first module)
	hist.pop_back()
	hist.push_front(run)


static func _finder_count(h: Array) -> int:
	var n: int = h[1]
	var core: bool = n > 0 and h[2] == n and h[3] == n * 3 and h[4] == n and h[5] == n
	return (1 if core and h[0] >= n * 4 and h[6] >= n else 0) + (1 if core and h[6] >= n * 4 and h[0] >= n else 0)


static func _finder_terminate(hist: Array, run_col: int, run: int, size: int) -> int:
	if run_col == 1:
		_hist_add(hist, run, size)
		run = 0
	run += size
	_hist_add(hist, run, size)
	return _finder_count(hist)


## The code as an image: `scale` pixels a module, a light border of 4 modules.
static func image(q: Dictionary, scale := 6) -> Image:
	var n: int = q["size"]
	var w := (n + 8) * scale
	var img := Image.create(w, w, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	for y in n:
		for x in n:
			if q["modules"][y * n + x] == 1:
				img.fill_rect(Rect2i((x + 4) * scale, (y + 4) * scale, scale, scale), Color.BLACK)
	return img
