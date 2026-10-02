class_name QrEncoder
extends RefCounted
## Minimal QR Code (ISO/IEC 18004) encoder: byte mode, EC level L or M, versions 1-10.
## Enough for the local join URL (http://<lan-ip>:<port>/?k=<key>), fully offline.
## Verified module-for-module against an independent encoder (tests/integration/qr_crosscheck.mjs).

const ECL_L := 1   # format bits per spec
const ECL_M := 0

# [ec_codewords_per_block, g1_blocks, g1_data_per_block, g2_blocks, g2_data_per_block]
const BLOCKS_L := [
	[], [7, 1, 19, 0, 0], [10, 1, 34, 0, 0], [15, 1, 55, 0, 0], [20, 1, 80, 0, 0], [26, 1, 108, 0, 0],
	[18, 2, 68, 0, 0], [20, 2, 78, 0, 0], [24, 2, 97, 0, 0], [30, 2, 116, 0, 0], [18, 2, 68, 2, 69],
]
const BLOCKS_M := [
	[], [10, 1, 16, 0, 0], [16, 1, 28, 0, 0], [26, 1, 44, 0, 0], [18, 2, 32, 0, 0], [24, 2, 43, 0, 0],
	[16, 4, 27, 0, 0], [18, 4, 31, 0, 0], [22, 2, 38, 2, 39], [22, 3, 36, 2, 37], [26, 4, 43, 1, 44],
]
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]

var version := 0
var size := 0
var ecl := ECL_M
var mask := -1
var modules: Array = []      # [row][col] bool (true = dark)
var _is_function: Array = []

static var _exp: PackedInt32Array
static var _log: PackedInt32Array


static func encode(text: String, p_ecl: int = ECL_M, force_mask: int = -1) -> QrEncoder:
	var q := QrEncoder.new()
	q._encode(text.to_utf8_buffer(), p_ecl, force_mask)
	return q


func is_valid() -> bool:
	return version > 0


func _blocks() -> Array:
	return BLOCKS_L[version] if ecl == ECL_L else BLOCKS_M[version]


func _data_capacity(v: int) -> int:
	var b: Array = BLOCKS_L[v] if ecl == ECL_L else BLOCKS_M[v]
	return b[1] * b[2] + b[3] * b[4]


func _encode(data: PackedByteArray, p_ecl: int, force_mask: int) -> void:
	ecl = p_ecl
	_init_gf()
	for v in range(1, 11):
		var count_bits := 8 if v <= 9 else 16
		if 4 + count_bits + data.size() * 8 <= _data_capacity(v) * 8:
			version = v
			break
	if version == 0:
		push_error("QrEncoder: data too long (%d bytes)" % data.size())
		return
	size = version * 4 + 17
	# --- Bit stream ---
	var bits: Array[int] = []
	_put(bits, 0b0100, 4)
	_put(bits, data.size(), 8 if version <= 9 else 16)
	for byte in data:
		_put(bits, byte, 8)
	var cap_bits := _data_capacity(version) * 8
	_put(bits, 0, mini(4, cap_bits - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var codewords := PackedByteArray()
	for i in range(0, bits.size(), 8):
		var b := 0
		for j in 8:
			b = (b << 1) | bits[i + j]
		codewords.append(b)
	var pad := [0xEC, 0x11]
	var pi := 0
	while codewords.size() < _data_capacity(version):
		codewords.append(pad[pi % 2])
		pi += 1
	var all_codewords := _add_ec_and_interleave(codewords)
	# --- Matrix ---
	modules = []
	_is_function = []
	for y in size:
		var row: Array = []
		var frow: Array = []
		row.resize(size)
		frow.resize(size)
		row.fill(false)
		frow.fill(false)
		modules.append(row)
		_is_function.append(frow)
	_draw_function_patterns()
	_draw_codewords(all_codewords)
	if force_mask >= 0:
		mask = force_mask
	else:
		var best := -1
		var best_penalty := 1 << 30
		for m in 8:
			_apply_mask(m)
			_draw_format_bits(m)
			var p := _penalty()
			if p < best_penalty:
				best_penalty = p
				best = m
			_apply_mask(m)  # XOR undo
		mask = best
	_apply_mask(mask)
	_draw_format_bits(mask)
	_is_function = []


static func _put(bits: Array[int], val: int, n: int) -> void:
	for i in range(n - 1, -1, -1):
		bits.append((val >> i) & 1)


# --- Reed-Solomon over GF(256), primitive polynomial 0x11D ---------------

static func _init_gf() -> void:
	if _exp.size() == 512:
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11D
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]


static func _gf_mul(a: int, b: int) -> int:
	if a == 0 or b == 0:
		return 0
	return _exp[_log[a] + _log[b]]


static func _rs_generator(degree: int) -> PackedInt32Array:
	# Coefficients highest-first, leading 1 implied: g(x) = prod_{i<degree} (x - a^i)
	var g := PackedInt32Array([1])
	for i in degree:
		var next := PackedInt32Array()
		next.resize(g.size() + 1)
		for j in g.size():
			next[j] ^= g[j]
			next[j + 1] ^= _gf_mul(g[j], _exp[i])
		g = next
	return g


static func _rs_remainder(data: PackedByteArray, degree: int) -> PackedByteArray:
	var gen := _rs_generator(degree)
	var rem := PackedInt32Array()
	rem.resize(degree)
	rem.fill(0)
	for b in data:
		var factor: int = b ^ rem[0]
		for i in range(degree - 1):
			rem[i] = rem[i + 1]
		rem[degree - 1] = 0
		for i in degree:
			rem[i] ^= _gf_mul(gen[i + 1], factor)
	var out := PackedByteArray()
	for v in rem:
		out.append(v)
	return out


func _add_ec_and_interleave(data: PackedByteArray) -> PackedByteArray:
	var b := _blocks()
	var ec_len: int = b[0]
	var blocks: Array = []
	var ecs: Array = []
	var k := 0
	for gi in 2:
		var count: int = b[1] if gi == 0 else b[3]
		var dlen: int = b[2] if gi == 0 else b[4]
		for _n in count:
			var blk := data.slice(k, k + dlen)
			k += dlen
			blocks.append(blk)
			ecs.append(_rs_remainder(blk, ec_len))
	var out := PackedByteArray()
	var max_len := 0
	for blk in blocks:
		max_len = maxi(max_len, blk.size())
	for i in max_len:
		for blk in blocks:
			if i < blk.size():
				out.append(blk[i])
	for i in ec_len:
		for ec in ecs:
			out.append(ec[i])
	return out


# --- Matrix construction -----------------------------------------------------

func _set_fn(x: int, y: int, dark: bool) -> void:
	modules[y][x] = dark
	_is_function[y][x] = true


func _draw_function_patterns() -> void:
	for i in size:
		_set_fn(6, i, i % 2 == 0)
		_set_fn(i, 6, i % 2 == 0)
	_draw_finder(3, 3)
	_draw_finder(size - 4, 3)
	_draw_finder(3, size - 4)
	var pos: Array = ALIGN[version]
	var n := pos.size()
	for i in n:
		for j in n:
			if (i == 0 and j == 0) or (i == 0 and j == n - 1) or (i == n - 1 and j == 0):
				continue
			_draw_alignment(pos[i], pos[j])
	_draw_format_bits(0)  # reserve; real bits drawn after masking
	_draw_version()


func _draw_finder(cx: int, cy: int) -> void:
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var x := cx + dx
			var y := cy + dy
			if x < 0 or x >= size or y < 0 or y >= size:
				continue
			var dist := maxi(absi(dx), absi(dy))
			_set_fn(x, y, dist != 2 and dist != 4)


func _draw_alignment(cx: int, cy: int) -> void:
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			_set_fn(cx + dx, cy + dy, maxi(absi(dx), absi(dy)) != 1)


func _draw_format_bits(m: int) -> void:
	var data := (ecl << 3) | m
	var rem := data
	for _i in 10:
		rem = (rem << 1) ^ ((rem >> 9) * 0x537)
	var bits := ((data << 10) | rem) ^ 0x5412
	for i in range(0, 6):
		_set_fn(8, i, (bits >> i) & 1 == 1)
	_set_fn(8, 7, (bits >> 6) & 1 == 1)
	_set_fn(8, 8, (bits >> 7) & 1 == 1)
	_set_fn(7, 8, (bits >> 8) & 1 == 1)
	for i in range(9, 15):
		_set_fn(14 - i, 8, (bits >> i) & 1 == 1)
	for i in range(0, 8):
		_set_fn(size - 1 - i, 8, (bits >> i) & 1 == 1)
	for i in range(8, 15):
		_set_fn(8, size - 15 + i, (bits >> i) & 1 == 1)
	_set_fn(8, size - 8, true)  # dark module


func _draw_version() -> void:
	if version < 7:
		return
	var rem := version
	for _i in 12:
		rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
	var bits := (version << 12) | rem
	for i in 18:
		var bit := (bits >> i) & 1 == 1
		var a := size - 11 + i % 3
		var b := i / 3
		_set_fn(a, b, bit)
		_set_fn(b, a, bit)


func _draw_codewords(data: PackedByteArray) -> void:
	var i := 0
	var total := data.size() * 8
	var right := size - 1
	while right >= 1:
		if right == 6:
			right = 5
		for vert in size:
			for j in 2:
				var x := right - j
				var upward := ((right + 1) & 2) == 0
				var y := size - 1 - vert if upward else vert
				if not _is_function[y][x] and i < total:
					modules[y][x] = (data[i >> 3] >> (7 - (i & 7))) & 1 == 1
					i += 1
		right -= 2


func _apply_mask(m: int) -> void:
	for y in size:
		for x in size:
			if _is_function[y][x]:
				continue
			var invert := false
			match m:
				0: invert = (x + y) % 2 == 0
				1: invert = y % 2 == 0
				2: invert = x % 3 == 0
				3: invert = (x + y) % 3 == 0
				4: invert = (x / 3 + y / 2) % 2 == 0
				5: invert = x * y % 2 + x * y % 3 == 0
				6: invert = (x * y % 2 + x * y % 3) % 2 == 0
				7: invert = ((x + y) % 2 + x * y % 3) % 2 == 0
			if invert:
				modules[y][x] = not modules[y][x]


func _penalty() -> int:
	var result := 0
	var dark := 0
	for y in size:
		for x in size:
			if modules[y][x]:
				dark += 1
	# N1: runs of >=5 in rows/columns
	for axis in 2:
		for a in size:
			var run := 0
			var prev := false
			for b in size:
				var c: bool = modules[a][b] if axis == 0 else modules[b][a]
				if b > 0 and c == prev:
					run += 1
				else:
					if run >= 5:
						result += 3 + (run - 5)
					run = 1
				prev = c
			if run >= 5:
				result += 3 + (run - 5)
	# N2: 2x2 blocks
	for y in size - 1:
		for x in size - 1:
			var c: bool = modules[y][x]
			if c == modules[y][x + 1] and c == modules[y + 1][x] and c == modules[y + 1][x + 1]:
				result += 3
	# N3: finder-like 1:1:3:1:1 patterns with 4 light modules on one side
	var p1 := [true, false, true, true, true, false, true, false, false, false, false]
	var p2 := [false, false, false, false, true, false, true, true, true, false, true]
	for axis in 2:
		for a in size:
			for b in range(-4, size):
				var m1 := true
				var m2 := true
				for k in 11:
					var idx := b + k
					var c := false
					if idx >= 0 and idx < size:
						c = modules[a][idx] if axis == 0 else modules[idx][a]
					if c != p1[k]:
						m1 = false
					if c != p2[k]:
						m2 = false
				if m1:
					result += 40
				if m2:
					result += 40
	# N4: dark/light balance
	var total := size * size
	var k4 := int(ceil(absf(dark * 20.0 - total * 10.0) / total)) - 1
	result += maxi(0, k4) * 10
	return result


## Renders to an Image with a quiet zone (4 modules), `scale` px per module.
func to_image(scale: int = 8, dark := Color(0.05, 0.05, 0.08), light := Color(1, 1, 1)) -> Image:
	var quiet := 4
	var px := (size + quiet * 2) * scale
	var img := Image.create(px, px, false, Image.FORMAT_RGB8)
	img.fill(light)
	for y in size:
		for x in size:
			if modules[y][x]:
				img.fill_rect(Rect2i((x + quiet) * scale, (y + quiet) * scale, scale, scale), dark)
	return img


func to_strings() -> PackedStringArray:
	var out := PackedStringArray()
	for y in size:
		var s := ""
		for x in size:
			s += "1" if modules[y][x] else "0"
		out.append(s)
	return out
