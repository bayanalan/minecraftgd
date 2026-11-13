## MCNoise — Java-compatible ImprovedNoise / PerlinNoise / NormalNoise / BlendedNoise implementations.
## Why: deterministic seeded gradient noise matching the Java algorithms (permutation from Xoroshiro, octave
## seeding via md5 "octave_N" hashes, 1.0181268882175227 second-sampler factor). Source class D (recalled
## algorithm); parity with 26.3 output is UNVERIFIED (26.3 adds a new base_amplitude normalisation field).
## Hot path is hand-inlined (gradient dot products, wrap) because GDScript call overhead dominates.
## Contract: Normal.create / from_params; value(x,y,z) -> float. Immutable after construction (thread-safe).
class_name MCNoise

const WRAP := 33554432.0
const GX := [1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, -1.0, 0.0]
const GY := [1.0, 1.0, -1.0, -1.0, 0.0, 0.0, 0.0, 0.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0, 1.0, -1.0]
const GZ := [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, -1.0, -1.0, 1.0, 1.0, -1.0, -1.0, 0.0, 1.0, 0.0, -1.0]


static func wrap(d: float) -> float:
	return d - floorf(d / WRAP + 0.5) * WRAP


class Improved:
	var p := PackedInt32Array()
	var xo: float
	var yo: float
	var zo: float
	var gx := PackedFloat64Array(MCNoise.GX)
	var gy := PackedFloat64Array(MCNoise.GY)
	var gz := PackedFloat64Array(MCNoise.GZ)

	func _init(r) -> void:
		xo = r.next_double() * 256.0
		yo = r.next_double() * 256.0
		zo = r.next_double() * 256.0
		p.resize(512)
		for i in 256:
			p[i] = i
		for i in 256:
			var j: int = r.next_int_bound(256 - i)
			var b := p[i]
			p[i] = p[i + j]
			p[i + j] = b
		for i in 256:
			p[i + 256] = p[i]

	func noise(x: float, y: float, z: float, y_scale: float = 0.0, y_max: float = 0.0) -> float:
		var d := x + xo
		var e := y + yo
		var f := z + zo
		var fi := floorf(d)
		var fj := floorf(e)
		var fk := floorf(f)
		var a := int(fi)
		var b := int(fj)
		var c := int(fk)
		var dx := d - fi
		var dys := e - fj
		var dz := f - fk
		var dy := dys
		if y_scale != 0.0:
			var m := dys
			if y_max >= 0.0 and y_max < dys:
				m = y_max
			dy = dys - floorf(m / y_scale + 1.0e-7) * y_scale
		var pp := p
		var hh := pp[a & 255]
		var ii := pp[(a + 1) & 255]
		var jj := pp[(hh + b) & 255]
		var kk := pp[(hh + b + 1) & 255]
		var ll := pp[(ii + b) & 255]
		var mm := pp[(ii + b + 1) & 255]
		var dx1 := dx - 1.0
		var dy1 := dy - 1.0
		var dz1 := dz - 1.0
		var g := pp[(jj + c) & 255] & 15
		var n := gx[g] * dx + gy[g] * dy + gz[g] * dz
		g = pp[(ll + c) & 255] & 15
		var o := gx[g] * dx1 + gy[g] * dy + gz[g] * dz
		g = pp[(kk + c) & 255] & 15
		var q := gx[g] * dx + gy[g] * dy1 + gz[g] * dz
		g = pp[(mm + c) & 255] & 15
		var r := gx[g] * dx1 + gy[g] * dy1 + gz[g] * dz
		g = pp[(jj + c + 1) & 255] & 15
		var s := gx[g] * dx + gy[g] * dy + gz[g] * dz1
		g = pp[(ll + c + 1) & 255] & 15
		var t := gx[g] * dx1 + gy[g] * dy + gz[g] * dz1
		g = pp[(kk + c + 1) & 255] & 15
		var u := gx[g] * dx + gy[g] * dy1 + gz[g] * dz1
		g = pp[(mm + c + 1) & 255] & 15
		var v := gx[g] * dx1 + gy[g] * dy1 + gz[g] * dz1
		var sx := dx * dx * dx * (dx * (dx * 6.0 - 15.0) + 10.0)
		var sy := dys * dys * dys * (dys * (dys * 6.0 - 15.0) + 10.0)
		var sz := dz * dz * dz * (dz * (dz * 6.0 - 15.0) + 10.0)
		var a1 := n + sx * (o - n)
		var a2 := q + sx * (r - q)
		var b1 := s + sx * (t - s)
		var b2 := u + sx * (v - u)
		var c1 := a1 + sy * (a2 - a1)
		var c2 := b1 + sy * (b2 - b1)
		return c1 + sz * (c2 - c1)


class Perlin:
	var levels: Array = []          # Improved or null, index 0 = lowest frequency
	var amps := PackedFloat64Array()
	var input_factor: float
	var value_factor: float
	var first_octave: int
	var active: Array = []          # [Improved, amp*valueFactor/2^k, inputFactor*2^k] for non-null octaves

	static func create(r, first: int, amplitudes: PackedFloat64Array) -> Perlin:
		var pn := Perlin.new()
		pn.first_octave = first
		pn.amps = amplitudes
		var n := amplitudes.size()
		var pf = r.fork_positional()
		for k in n:
			if amplitudes[k] != 0.0:
				pn.levels.append(MCNoise.Improved.new(pf.from_hash("octave_" + str(first + k))))
			else:
				pn.levels.append(null)
		pn.input_factor = pow(2.0, first)
		pn.value_factor = pow(2.0, n - 1) / (pow(2.0, n) - 1.0)
		pn._prepare()
		return pn

	## Legacy construction used by BlendedNoise (octaves -first..0, sequential, skipping 262 calls per gap).
	static func create_legacy(r, first: int, amplitudes: PackedFloat64Array) -> Perlin:
		var pn := Perlin.new()
		pn.first_octave = first
		pn.amps = amplitudes
		var n := amplitudes.size()
		var j := -first
		pn.levels.resize(n)
		var imp = MCNoise.Improved.new(r)
		if j >= 0 and j < n and amplitudes[j] != 0.0:
			pn.levels[j] = imp
		for k in range(j - 1, -1, -1):
			if k < n:
				if amplitudes[k] != 0.0:
					pn.levels[k] = MCNoise.Improved.new(r)
				else:
					r.consume(262)
			else:
				r.consume(262)
		pn.input_factor = pow(2.0, -j)
		pn.value_factor = pow(2.0, n - 1) / (pow(2.0, n) - 1.0)
		pn._prepare()
		return pn

	func _prepare() -> void:
		active.clear()
		var e := input_factor
		var f := value_factor
		for k in levels.size():
			if levels[k] != null:
				active.append([levels[k], amps[k] * f, e])
			e *= 2.0
			f /= 2.0

	func value(x: float, y: float, z: float) -> float:
		var d := 0.0
		for oc in active:
			var e: float = oc[2]
			var ax := x * e
			var ay := y * e
			var az := z * e
			ax -= floorf(ax / MCNoise.WRAP + 0.5) * MCNoise.WRAP
			ay -= floorf(ay / MCNoise.WRAP + 0.5) * MCNoise.WRAP
			az -= floorf(az / MCNoise.WRAP + 0.5) * MCNoise.WRAP
			d += float(oc[1]) * (oc[0] as MCNoise.Improved).noise(ax, ay, az)
		return d

	## Octave i counted from the highest frequency (Java getOctaveNoise).
	func octave(i: int):
		return levels[levels.size() - 1 - i]

	func max_value() -> float:
		var d := 0.0
		var f := value_factor
		for k in levels.size():
			if levels[k] != null:
				d += absf(amps[k]) * 2.0 * f   # Java edgeValue(2.0): safe bound on |improved noise|
			f /= 2.0
		return d


class Normal:
	var gxs := PackedFloat64Array(MCNoise.GX)
	var gys := PackedFloat64Array(MCNoise.GY)
	var gzs := PackedFloat64Array(MCNoise.GZ)
	var a: Perlin
	var b: Perlin
	var value_factor: float
	var max_val: float

	static func create(r, first: int, amplitudes: PackedFloat64Array) -> Normal:
		var nn := Normal.new()
		nn.a = MCNoise.Perlin.create(r, first, amplitudes)
		nn.b = MCNoise.Perlin.create(r, first, amplitudes)
		var mn := 2147483647
		var mx := -2147483648
		for i in amplitudes.size():
			if amplitudes[i] != 0.0:
				mn = mini(mn, i)
				mx = maxi(mx, i)
		var dev := 0.1 * (1.0 + 1.0 / float(mx - mn + 1))
		nn.value_factor = 0.16666666666666666 / dev
		nn.max_val = (nn.a.max_value() + nn.b.max_value()) * nn.value_factor
		return nn

	## params from 26.3 worldgen/noise json (base_octave, octave_count, amplitude_modifiers) or legacy
	## (firstOctave, amplitudes). base_amplitude is recorded but the documented Java 1.18-1.21 normalisation is used.
	static func from_params(r, j: Dictionary) -> Normal:
		var first := int(j.get("base_octave", j.get("firstOctave", 0)))
		var count := int(j.get("octave_count", 1))
		var amps := PackedFloat64Array()
		if j.get("amplitudes") is Array:
			for v in j["amplitudes"]:
				amps.append(float(v))
		else:
			var mods: Array = j.get("amplitude_modifiers", []) if j.get("amplitude_modifiers") is Array else []
			for i in count:
				amps.append(float(mods[i]) if i < mods.size() else 1.0)
		return Normal.create(r, first, amps)

	# flattened octave tables (both Perlin samplers): one GDScript call per sample, no per-octave calls
	var o_perm: Array = []
	var o_off := PackedFloat64Array()   # xo, yo, zo per octave
	var o_in := PackedFloat64Array()    # input factor (includes 1.0181 for sampler b)
	var o_amp := PackedFloat64Array()   # amplitude * valueFactor/2^k * normal valueFactor
	var o_n := 0

	func _flatten() -> void:
		o_perm.clear()
		o_off = PackedFloat64Array()
		o_in = PackedFloat64Array()
		o_amp = PackedFloat64Array()
		for pi in 2:
			var pn: Perlin = a if pi == 0 else b
			for oc in pn.active:
				var imp: MCNoise.Improved = oc[0]
				o_perm.append(imp.p)
				o_off.append_array([imp.xo, imp.yo, imp.zo])
				o_in.append(float(oc[2]) * (1.0 if pi == 0 else 1.0181268882175227))
				o_amp.append(float(oc[1]) * value_factor)
		o_n = o_amp.size()

	func value(x: float, y: float, z: float) -> float:
		if o_n == 0:
			_flatten()
		var W := MCNoise.WRAP
		var GXS := gxs
		var GYS := gys
		var GZS := gzs
		var total := 0.0
		for k in o_n:
			var e := o_in[k]
			var ax := x * e
			var ay := y * e
			var az := z * e
			ax -= floorf(ax / W + 0.5) * W
			ay -= floorf(ay / W + 0.5) * W
			az -= floorf(az / W + 0.5) * W
			var d := ax + o_off[k * 3]
			var ee := ay + o_off[k * 3 + 1]
			var f := az + o_off[k * 3 + 2]
			var fi := floorf(d)
			var fj := floorf(ee)
			var fk := floorf(f)
			var ia := int(fi)
			var ib := int(fj)
			var ic := int(fk)
			var dx := d - fi
			var dy := ee - fj
			var dz := f - fk
			var pp: PackedInt32Array = o_perm[k]
			var hh := pp[ia & 255]
			var ii := pp[(ia + 1) & 255]
			var jj := pp[(hh + ib) & 255]
			var kk := pp[(hh + ib + 1) & 255]
			var ll := pp[(ii + ib) & 255]
			var mm := pp[(ii + ib + 1) & 255]
			var dx1 := dx - 1.0
			var dy1 := dy - 1.0
			var dz1 := dz - 1.0
			var g := pp[(jj + ic) & 255] & 15
			var n0 := GXS[g] * dx + GYS[g] * dy + GZS[g] * dz
			g = pp[(ll + ic) & 255] & 15
			var n1 := GXS[g] * dx1 + GYS[g] * dy + GZS[g] * dz
			g = pp[(kk + ic) & 255] & 15
			var n2 := GXS[g] * dx + GYS[g] * dy1 + GZS[g] * dz
			g = pp[(mm + ic) & 255] & 15
			var n3 := GXS[g] * dx1 + GYS[g] * dy1 + GZS[g] * dz
			g = pp[(jj + ic + 1) & 255] & 15
			var n4 := GXS[g] * dx + GYS[g] * dy + GZS[g] * dz1
			g = pp[(ll + ic + 1) & 255] & 15
			var n5 := GXS[g] * dx1 + GYS[g] * dy + GZS[g] * dz1
			g = pp[(kk + ic + 1) & 255] & 15
			var n6 := GXS[g] * dx + GYS[g] * dy1 + GZS[g] * dz1
			g = pp[(mm + ic + 1) & 255] & 15
			var n7 := GXS[g] * dx1 + GYS[g] * dy1 + GZS[g] * dz1
			var sx := dx * dx * dx * (dx * (dx * 6.0 - 15.0) + 10.0)
			var sy := dy * dy * dy * (dy * (dy * 6.0 - 15.0) + 10.0)
			var sz := dz * dz * dz * (dz * (dz * 6.0 - 15.0) + 10.0)
			var a1 := n0 + sx * (n1 - n0)
			var a2 := n2 + sx * (n3 - n2)
			var b1 := n4 + sx * (n5 - n4)
			var b2 := n6 + sx * (n7 - n6)
			var c1 := a1 + sy * (a2 - a1)
			var c2 := b1 + sy * (b2 - b1)
			total += o_amp[k] * (c1 + sz * (c2 - c1))
		return total

class Blended:
	var min_limit: Perlin
	var max_limit: Perlin
	var main: Perlin
	var xz_mul: float
	var y_mul: float
	var xz_factor: float
	var y_factor: float
	var smear: float
	var main_oct: Array = []
	var min_oct: Array = []
	var max_oct: Array = []

	static func create(r, xz_scale: float, y_scale: float, xz_factor: float, y_factor: float, smear_mult: float) -> Blended:
		var bn := Blended.new()
		var a16 := PackedFloat64Array()
		a16.resize(16)
		a16.fill(1.0)
		var a8 := PackedFloat64Array()
		a8.resize(8)
		a8.fill(1.0)
		bn.min_limit = MCNoise.Perlin.create_legacy(r, -15, a16)
		bn.max_limit = MCNoise.Perlin.create_legacy(r, -15, a16)
		bn.main = MCNoise.Perlin.create_legacy(r, -7, a8)
		bn.xz_mul = 684.412 * xz_scale
		bn.y_mul = 684.412 * y_scale
		bn.xz_factor = xz_factor
		bn.y_factor = y_factor
		bn.smear = smear_mult
		for p in 8:
			bn.main_oct.append(bn.main.octave(p))
		for p in 16:
			bn.min_oct.append(bn.min_limit.octave(p))
			bn.max_oct.append(bn.max_limit.octave(p))
		return bn

	func value(x: float, y: float, z: float) -> float:
		var d := x * xz_mul
		var e := y * y_mul
		var f := z * xz_mul
		var g := d / xz_factor
		var h := e / y_factor
		var i := f / xz_factor
		var j := y_mul * smear
		var k := j / y_factor
		var l := 0.0
		var m := 0.0
		var n := 0.0
		var o := 1.0
		var W := MCNoise.WRAP
		for p in 8:
			var nz: MCNoise.Improved = main_oct[p]
			if nz != null:
				var ax := g * o
				var ay := h * o
				var az := i * o
				n += nz.noise(ax - floorf(ax / W + 0.5) * W, ay - floorf(ay / W + 0.5) * W, az - floorf(az / W + 0.5) * W, k * o, h * o) / o
			o /= 2.0
		var q := (n / 10.0 + 1.0) / 2.0
		var hi := q >= 1.0
		var lo := q <= 0.0
		o = 1.0
		for r in 16:
			var sd := d * o
			var td := e * o
			var ud := f * o
			var s := sd - floorf(sd / W + 0.5) * W
			var t := td - floorf(td / W + 0.5) * W
			var u := ud - floorf(ud / W + 0.5) * W
			var v := j * o
			if not hi:
				var n1: MCNoise.Improved = min_oct[r]
				if n1 != null:
					l += n1.noise(s, t, u, v, td) / o
			if not lo:
				var n2: MCNoise.Improved = max_oct[r]
				if n2 != null:
					m += n2.noise(s, t, u, v, td) / o
			o /= 2.0
		var a := l / 512.0
		var b := m / 512.0
		var res: float
		if q < 0.0:
			res = a
		elif q > 1.0:
			res = b
		else:
			res = a + q * (b - a)
		return res / 128.0


## Java SimplexNoise (2D path only; xo/yo/zo consumed like Java).
class Simplex:
	var p := PackedInt32Array()
	const F2 := 0.3660254037844386
	const G2 := 0.21132486540518713

	func _init(r) -> void:
		r.next_double()
		r.next_double()
		r.next_double()
		p.resize(256)
		for i in 256:
			p[i] = i
		for i in 256:
			var j: int = r.next_int_bound(256 - i)
			var k := p[i]
			p[i] = p[j + i]
			p[j + i] = k

	func value2(d: float, e: float) -> float:
		var h := (d + e) * F2
		var i := floori(d + h)
		var j := floori(e + h)
		var k := (i + j) * G2
		var n := d - (i - k)
		var o := e - (j - k)
		var pp := 1 if n > o else 0
		var qq := 0 if n > o else 1
		var r := n - pp + G2
		var s := o - qq + G2
		var t := n - 1.0 + 2.0 * G2
		var u := o - 1.0 + 2.0 * G2
		var v := i & 255
		var w := j & 255
		var gi0 := p[(v + p[w & 255]) & 255] % 12
		var gi1 := p[(v + pp + p[(w + qq) & 255]) & 255] % 12
		var gi2 := p[(v + 1 + p[(w + 1) & 255]) & 255] % 12
		var tot := 0.0
		var c0 := 0.5 - n * n - o * o
		if c0 >= 0.0:
			c0 *= c0
			tot += c0 * c0 * (float(MCNoise.GX[gi0]) * n + float(MCNoise.GY[gi0]) * o)
		var c1 := 0.5 - r * r - s * s
		if c1 >= 0.0:
			c1 *= c1
			tot += c1 * c1 * (float(MCNoise.GX[gi1]) * r + float(MCNoise.GY[gi1]) * s)
		var c2 := 0.5 - t * t - u * u
		if c2 >= 0.0:
			c2 *= c2
			tot += c2 * c2 * (float(MCNoise.GX[gi2]) * t + float(MCNoise.GY[gi2]) * u)
		return 70.0 * tot


## Round a double to the nearest float32 (Java float arithmetic emulation).
static func f32(v: float) -> float:
	var a := PackedFloat32Array([v])
	return a[0]


## Java EndIslandDensityFunction: islandNoise = SimplexNoise(LegacyRandomSource(seed) after 17292 nextInt()).
static func end_simplex(world_seed: int) -> Simplex:
	var r := RandomSources.LegacyRandom.new(world_seed)
	r.consume(17292)
	return Simplex.new(r)


## Java EndIslandDensityFunction.getHeightValue (float32 arithmetic emulated). i, j = block / 8 (truncating).
static func end_height(sn: Simplex, i: int, j: int) -> float:
	var k := i / 2
	var l := j / 2
	var m := i % 2
	var n := j % 2
	var f := f32(100.0 - f32(f32(sqrt(f32(float(i * i + j * j)))) * 8.0))
	f = clampf(f, -100.0, 80.0)
	for o in range(-12, 13):
		var q := k + o
		for pz in range(-12, 13):
			var r := l + pz
			if q * q + r * r > 4096 and sn.value2(float(q), float(r)) < -0.8999999761581421:
				var g := f32(fmod(f32(f32(absf(q) * 3439.0) + f32(absf(r) * 147.0)), 13.0) + 9.0)
				var h := float(m - o * 2)
				var s := float(n - pz * 2)
				var t := f32(100.0 - f32(f32(sqrt(h * h + s * s)) * g))
				t = clampf(t, -100.0, 80.0)
				f = maxf(f, t)
	return f