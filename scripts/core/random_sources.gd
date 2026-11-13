## Java-compatible random sources: LegacyRandom (java.util.Random LCG), Xoroshiro128++ and positional factories.
## Why: deterministic, order-independent worldgen seeded like Java Edition (signed 64-bit overflow preserved).
## Contract: all methods are pure functions of their seed state; instances are NOT thread-shared.
## Invariants: GDScript int is int64 with wrapping arithmetic; unsigned shifts emulated with masks.
class_name RandomSources

const MASK48 := (1 << 48) - 1
const GOLDEN_RATIO_64 := -7046029254386353131  # 0x9E3779B97F4A7C15
const SILVER_RATIO_64 := 7640891576956012809   # 0x6A09E667F3BCC909


static func urshift(x: int, n: int) -> int:
	if n == 0:
		return x
	return (x >> n) & ((1 << (64 - n)) - 1)


static func rotl(x: int, k: int) -> int:
	return (x << k) | urshift(x, 64 - k)


static func mix_stafford13(z: int) -> int:
	z = (z ^ urshift(z, 30)) * -4658895280553007687  # 0xBF58476D1CE4E5B9
	z = (z ^ urshift(z, 27)) * -7723592293110705685  # 0x94D049BB133111EB
	return z ^ urshift(z, 31)


static func to_i32(v: int) -> int:
	v = v & 0xFFFFFFFF
	if v >= 0x80000000:
		v -= 0x100000000
	return v


## Mth.getSeed(x,y,z)
static func pos_seed(x: int, y: int, z: int) -> int:
	var l: int = (to_i32(x * 3129871)) ^ (z * 116129781) ^ y
	l = l * l * 42317861 + l * 11
	return l >> 16


## Java String.hashCode()
static func java_string_hash(s: String) -> int:
	var h := 0
	for i in s.length():
		h = to_i32(31 * h + s.unicode_at(i))
	return h


static func bytes_to_long(b: PackedByteArray, off: int) -> int:
	var v := 0
	for i in 8:
		v = (v << 8) | b[off + i]
	return v


class Xoroshiro:
	var lo: int
	var hi: int

	func _init(a: int = 0, b: int = 0) -> void:
		lo = a
		hi = b
		if lo == 0 and hi == 0:
			lo = RandomSources.GOLDEN_RATIO_64
			hi = RandomSources.SILVER_RATIO_64

	static func from_seed(seed: int) -> Xoroshiro:
		var l: int = seed ^ 7640891576956012809
		var h: int = l + -7046029254386353131
		l = (l ^ ((l >> 30) & 0x3FFFFFFFF)) * -4658895280553007687
		l = (l ^ ((l >> 27) & 0x1FFFFFFFFF)) * -7723592293110705685
		l = l ^ ((l >> 31) & 0x1FFFFFFFF)
		h = (h ^ ((h >> 30) & 0x3FFFFFFFF)) * -4658895280553007687
		h = (h ^ ((h >> 27) & 0x1FFFFFFFFF)) * -7723592293110705685
		h = h ^ ((h >> 31) & 0x1FFFFFFFF)
		return Xoroshiro.new(l, h)

	## Hot path: all helpers inlined (static calls through the global class contend across threads).
	func next_long() -> int:
		var l := lo
		var m := hi
		var s := l + m
		var n: int = ((s << 17) | ((s >> 47) & 0x1FFFF)) + l
		m ^= l
		lo = ((l << 49) | ((l >> 15) & 0x1FFFFFFFFFFFF)) ^ m ^ (m << 21)
		hi = (m << 28) | ((m >> 36) & 0xFFFFFFF)
		return n

	func next_int() -> int:
		var v := next_long() & 0xFFFFFFFF
		return v - 0x100000000 if v >= 0x80000000 else v

	func next_bits(bits: int) -> int:
		return (next_long() >> (64 - bits)) & ((1 << bits) - 1)

	func next_int_bound(bound: int) -> int:
		var l: int = next_long() & 0xFFFFFFFF
		var m: int = l * bound
		var n: int = m & 0xFFFFFFFF
		if n < bound:
			var i: int = ((~bound + 1) & 0xFFFFFFFF) % bound
			while n < i:
				l = next_long() & 0xFFFFFFFF
				m = l * bound
				n = m & 0xFFFFFFFF
		return m >> 32

	func next_double() -> float:
		return float(next_bits(53)) * 1.1102230246251565e-16

	func next_float() -> float:
		return float(next_bits(24)) * 5.9604645e-8

	func next_bool() -> bool:
		return (next_long() & 1) != 0

	func consume(n: int) -> void:
		for i in n:
			next_long()

	func fork_positional() -> XoroPositional:
		var a := next_long()
		var b := next_long()
		return XoroPositional.new(a, b)

	func range_int(a: int, b_inclusive: int) -> int:
		return a + next_int_bound(b_inclusive - a + 1)


class XoroPositional:
	var lo: int
	var hi: int

	func _init(a: int, b: int) -> void:
		lo = a
		hi = b

	func at(x: int, y: int, z: int) -> Xoroshiro:
		var t := (x * 3129871) & 0xFFFFFFFF
		if t >= 0x80000000:
			t -= 0x100000000
		var l: int = t ^ (z * 116129781) ^ y
		l = l * l * 42317861 + l * 11
		return Xoroshiro.new((l >> 16) ^ lo, hi)

	func from_hash(name: String) -> Xoroshiro:
		var md := name.md5_buffer()
		var a := RandomSources.bytes_to_long(md, 0)
		var b := RandomSources.bytes_to_long(md, 8)
		return Xoroshiro.new(a ^ lo, b ^ hi)


## java.util.Random compatible LCG (used by legacy feature/structure seeding).
class LegacyRandom:
	var seed: int

	func _init(s: int = 0) -> void:
		set_seed(s)

	func set_seed(s: int) -> void:
		seed = (s ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF

	func next(bits: int) -> int:
		seed = (seed * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
		var v := (seed >> (48 - bits)) & 0xFFFFFFFF
		return v - 0x100000000 if v >= 0x80000000 else v

	func next_int() -> int:
		return next(32)

	func next_int_bound(bound: int) -> int:
		if (bound & -bound) == bound:
			var pv := ((bound * next(31)) >> 31) & 0xFFFFFFFF
			return pv - 0x100000000 if pv >= 0x80000000 else pv
		var bits: int
		var val: int
		while true:
			bits = next(31)
			val = bits % bound
			if bits - val + (bound - 1) < 0x80000000:
				break
		return val

	func next_long() -> int:
		return (next(32) << 32) + next(32)

	func next_double() -> float:
		return float((next(26) << 27) + next(27)) * 1.1102230246251565e-16

	func next_float() -> float:
		return float(next(24)) / float(1 << 24)

	func next_bool() -> bool:
		return next(1) != 0

	func consume(n: int) -> void:
		for i in n:
			next(32)

	func range_int(a: int, b_inclusive: int) -> int:
		return a + next_int_bound(b_inclusive - a + 1)

	func fork_positional() -> LegacyPositional:
		return LegacyPositional.new(next_long())


## Java LegacyPositionalRandomFactory (used when noise settings set legacy_random_source: Nether, End).
class LegacyPositional:
	var seed: int

	func _init(s: int) -> void:
		seed = s

	func at(x: int, y: int, z: int) -> LegacyRandom:
		return LegacyRandom.new(RandomSources.pos_seed(x, y, z) ^ seed)

	func from_hash(name: String) -> LegacyRandom:
		return LegacyRandom.new(RandomSources.java_string_hash(name) ^ seed)


## Root positional factory for a world seed (RandomState): legacy LCG or Xoroshiro128++.
static func root_positional(world_seed: int, legacy: bool):
	if legacy:
		return LegacyRandom.new(world_seed).fork_positional()
	return Xoroshiro.from_seed(world_seed).fork_positional()


## Parses a world seed string like Java Edition: numeric -> long, otherwise String.hashCode().
static func parse_seed(text: String) -> int:
	var t := text.strip_edges()
	if t.is_empty():
		var r := RandomNumberGenerator.new()
		r.randomize()
		return (r.randi() << 32) ^ r.randi()
	if t.is_valid_int():
		# is_valid_int accepts values that may overflow; Java rejects >64-bit and falls back to hash.
		var digits := t.trim_prefix("-").trim_prefix("+")
		if digits.length() <= 19:
			var v := t.to_int()
			if str(v) == t or ("+" + str(v)) == t:
				return v
	return java_string_hash(t)
