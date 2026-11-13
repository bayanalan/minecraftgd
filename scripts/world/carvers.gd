## Carvers — Java CaveWorldCarver / CanyonWorldCarver re-implementation (source D) driven by the installed 26.3
## worldgen/carver JSON (count, thickness, floor_level, radius multipliers, canyon shape). For a chunk, every
## chunk within 8 chunks may start carvers (LegacyRandom setLargeFeatureSeed(seed+index, x, z)); carving writes
## only inside the target chunk, through the aquifer (density 0) and lava below lava_level (-56 default).
## Source-chunk carver biome = noise biome at (minBlockX, 0, minBlockZ) (shared cache).
## Contract: Carvers.new(gen).carve(col, cx, cz, aquifer) mutates the column array in place.
class_name Carvers
extends RefCounted

const RANGE := 8


var gen: VanillaGenerator
var carvers: Dictionary = {}       # name -> config dict
var biome_carvers: Array = []      # per biome id: Array[name]
var replaceable: Dictionary = {}   # block id -> true
var _biome_cache: Dictionary = {}
var _m := Mutex.new()


func _init(g: VanillaGenerator) -> void:
	gen = g
	ctx_min = g.gen_min_y
	ctx_depth = g.gen_depth
	for b in Tags.blocks("overworld_carver_replaceables"):
		var bid := g.blocks.block_id(b)
		if bid >= 0:
			replaceable[bid] = true
	for bi in g.biomes.names.size():
		var d = g.biomes.data[bi]
		var lst: Array = []
		var cl = d.get("carvers", []) if d is Dictionary else []
		if cl is Dictionary:
			cl = cl.get("air", [])
		if cl is String:
			cl = [cl]
		for c in cl:
			var nm := str(c)
			lst.append(nm)
			if not carvers.has(nm):
				var j = g.source.call("data/minecraft/worldgen/carver/%s.json" % nm.trim_prefix("minecraft:"))
				if j == null:
					j = g.source.call("data/minecraft/worldgen/configured_carver/%s.json" % nm.trim_prefix("minecraft:"))
				carvers[nm] = j if j is Dictionary else {}
		biome_carvers.append(lst)


# ------------------------------------------------------------------ providers (java float/int/height)

static func fsample(r, v) -> float:
	if v is float or v is int:
		return float(v)
	if not (v is Dictionary):
		return 0.0
	var t := str(v.get("type", "constant")).trim_prefix("minecraft:")
	match t:
		"uniform":
			var lo := float(v.get("min_inclusive", 0.0))
			var hi := float(v.get("max_exclusive", 1.0))
			return lo + r.next_float() * (hi - lo)
		"trapezoid":
			var mn := float(v.get("min", 0.0))
			var mx := float(v.get("max", 0.0))
			var pl := float(v.get("plateau", 0.0))
			var f := mx - mn
			var g := (f - pl) / 2.0
			var h := f - g
			return mn + r.next_float() * h + r.next_float() * g
		"constant":
			return float(v.get("value", 0.0))
	return 0.0


## VerticalAnchor resolved against the generation context (noise min_y / height of this dimension).
var ctx_min := -64
var ctx_depth := 384


func _anchor(a) -> int:
	if a is Dictionary:
		if a.has("absolute"):
			return int(a["absolute"])
		if a.has("above_bottom"):
			return ctx_min + int(a["above_bottom"])
		if a.has("below_top"):
			return ctx_min + ctx_depth - 1 - int(a["below_top"])
	return 0


## Mth.randomBetweenInclusive: always consumes one nextInt (also when a == b).
static func _mth_next(r, a: int, b: int) -> int:
	return int(r.next_int_bound(maxi(b - a + 1, 1))) + a


func isample(r, v) -> int:
	if v is int or v is float:
		return int(v)
	if not (v is Dictionary):
		return 0
	var t := str(v.get("type", "constant")).trim_prefix("minecraft:")
	if t == "uniform" and v.get("min_inclusive") is Dictionary:
		var lo := _anchor(v["min_inclusive"])
		var hi := _anchor(v["max_inclusive"])
		return lo + r.next_int_bound(hi - lo + 1) if hi >= lo else lo
	var a := int(v.get("min_inclusive", 0))
	var b := int(v.get("max_inclusive", 0))
	match t:
		"uniform":
			return a + r.next_int_bound(b - a + 1)
		"very_biased_to_bottom":
			var k := _mth_next(r, a + 1, b)
			var l := _mth_next(r, a, k - 1)
			return _mth_next(r, a, l)
		"biased_to_bottom":
			return a + r.next_int_bound(r.next_int_bound(b - a + 1) + 1)
	return int(v.get("value", a))


# ------------------------------------------------------------------ native export (RecraftNative.tg_config)

## [replaceable by block id, carver configs, per-biome carver index lists]; providers flattened as [kind, a, b, c]
## with the exact sampling semantics of fsample / isample (native/src/terrain.cpp).
func export_native(block_count: int) -> Array:
	var idx := {}
	var cfgs: Array = []
	for nm in carvers:
		idx[nm] = cfgs.size()
		cfgs.append(_export_cfg(carvers[nm]))
	var lists: Array = []
	for lst in biome_carvers:
		var p := PackedInt32Array()
		for nm in lst:
			p.append(idx[nm])
		lists.append(p)
	var rep := PackedByteArray()
	rep.resize(block_count)
	for b in replaceable:
		if int(b) >= 0 and int(b) < block_count:
			rep[int(b)] = 1
	return [rep, cfgs, lists]


func _export_cfg(cfg: Dictionary) -> Array:
	var t := str(cfg.get("type", "")).trim_prefix("minecraft:")
	var ty := 1 if t == "cave" else (2 if t == "canyon" else 0)
	var shape: Dictionary = cfg.get("shape", {}) if cfg.get("shape") is Dictionary else {}
	var ints := PackedInt32Array([ty, 1 if cfg.is_empty() else 0, 1 if bool(cfg.get("weird_thickness_bias", false)) else 0, int(shape.get("width_smoothness", 3))])
	var f := PackedFloat64Array([float(cfg.get("probability", 0.0)), float(cfg.get("start_vertical_radius_multiplier", 1.0)),
		float(shape.get("vertical_radius_default_factor", 1.0)), float(shape.get("vertical_radius_center_factor", 0.0))])
	f.append_array(_iprov(cfg.get("count", 14)))
	f.append_array(_iprov(cfg.get("y", 64 if ty == 1 else 40)))
	f.append_array(_fprov(cfg.get("horizontal_radius_multiplier", 1.0)))
	f.append_array(_fprov(cfg.get("vertical_radius_multiplier", 1.0)))
	f.append_array(_fprov(cfg.get("floor_level", -0.7)))
	f.append_array(_fprov(cfg.get("room_vertical_radius_multiplier", 0.5)))
	f.append_array(_fprov(cfg.get("thickness", 2.0)))
	f.append_array(_fprov(cfg.get("vertical_rotation", 0.0)))
	f.append_array(_fprov(shape.get("y_scale", cfg.get("y_scale", 3.0))))
	f.append_array(_fprov(shape.get("thickness", 2.0)))
	f.append_array(_fprov(shape.get("distance_factor", 1.0)))
	f.append_array(_fprov(shape.get("horizontal_radius_factor", 1.0)))
	return [ints, f]


static func _fprov(v) -> Array:
	if v is float or v is int:
		return [0.0, float(v), 0.0, 0.0]
	if not (v is Dictionary):
		return [0.0, 0.0, 0.0, 0.0]
	match str(v.get("type", "constant")).trim_prefix("minecraft:"):
		"uniform":
			return [1.0, float(v.get("min_inclusive", 0.0)), float(v.get("max_exclusive", 1.0)), 0.0]
		"trapezoid":
			return [2.0, float(v.get("min", 0.0)), float(v.get("max", 0.0)), float(v.get("plateau", 0.0))]
		"constant":
			return [0.0, float(v.get("value", 0.0)), 0.0, 0.0]
	return [0.0, 0.0, 0.0, 0.0]


func _iprov(v) -> Array:
	if v is int or v is float:
		return [0.0, float(int(v)), 0.0, 0.0]
	if not (v is Dictionary):
		return [0.0, 0.0, 0.0, 0.0]
	var t := str(v.get("type", "constant")).trim_prefix("minecraft:")
	if t == "uniform" and v.get("min_inclusive") is Dictionary:
		return [1.0, float(_anchor(v["min_inclusive"])), float(_anchor(v["max_inclusive"])), 0.0]
	var a := int(v.get("min_inclusive", 0))
	var b := int(v.get("max_inclusive", 0))
	match t:
		"uniform":
			return [2.0, float(a), float(b), 0.0]
		"very_biased_to_bottom":
			return [3.0, float(a), float(b), 0.0]
		"biased_to_bottom":
			return [4.0, float(a), float(b), 0.0]
	return [0.0, float(int(v.get("value", a))), 0.0, 0.0]


## Carver source biomes of the 17x17 chunks around (cx, cz), dz-major (native carve input).
func source_biomes(cx: int, cz: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(289)
	var w := 0
	for dz in range(-RANGE, RANGE + 1):
		for dx in range(-RANGE, RANGE + 1):
			out[w] = _source_biome(cx + dx, cz + dz) if not biome_carvers.is_empty() else -1
			w += 1
	return out


# ------------------------------------------------------------------ biome of source chunks

func _source_biome(cx: int, cz: int) -> int:
	var key := Vector2i(cx, cz)
	_m.lock()
	var v = _biome_cache.get(key)
	_m.unlock()
	if v != null:
		return v
	var ctx := DensityFunctions.Ctx.new(gen.dfc.node_count())
	var x := cx * 16
	var z := cz * 16
	var name := "plains"
	if gen.single_biome >= 0:
		_m.lock()
		_biome_cache[key] = gen.single_biome
		_m.unlock()
		return gen.single_biome
	name = gen.climate.find(gen.r_temp.point(ctx, x, 0, z), gen.r_veg.point(ctx, x, 0, z), gen.r_cont.point(ctx, x, 0, z), gen.r_eros.point(ctx, x, 0, z), gen.r_depth.point(ctx, x, 0, z), gen.r_ridges.point(ctx, x, 0, z))
	var id: int = gen.biome_ids.get(name, 0)
	_m.lock()
	if _biome_cache.size() > 100000:
		_biome_cache.clear()
	_biome_cache[key] = id
	_m.unlock()
	return id


# ------------------------------------------------------------------ carving

class Job:
	var col: PackedInt32Array
	var mask := PackedByteArray()
	var cx := 0
	var cz := 0
	var aq: Aquifer
	var gen: VanillaGenerator
	var replaceable: Dictionary
	var dirt := 0
	var grass := 0
	var mycelium := 0


func carve(col: PackedInt32Array, cx: int, cz: int, aq: Aquifer) -> void:
	var job := Job.new()
	job.col = col
	job.mask.resize(98304)
	job.cx = cx
	job.cz = cz
	job.aq = aq
	job.gen = gen
	job.replaceable = replaceable
	job.dirt = gen.blocks.block_id("dirt")
	job.grass = gen.blocks.block_id("grass_block")
	job.mycelium = gen.blocks.block_id("mycelium")
	var r := RandomSources.LegacyRandom.new(0)
	for dz in range(-RANGE, RANGE + 1):
		for dx in range(-RANGE, RANGE + 1):
			if gen.aborted:
				return
			var sx := cx + dx
			var sz := cz + dz
			var lst: Array = biome_carvers[_source_biome(sx, sz)] if not biome_carvers.is_empty() else []
			var l := 0
			for nm in lst:
				var cfg: Dictionary = carvers.get(nm, {})
				var fs: int = gen.seed + l
				r.set_seed(fs)
				var a := r.next_long()
				var b := r.next_long()
				r.set_seed((sx * a) ^ (sz * b) ^ fs)
				l += 1
				if cfg.is_empty() or r.next_float() > float(cfg.get("probability", 0.0)):
					continue
				var t := str(cfg.get("type", "")).trim_prefix("minecraft:")
				if t == "cave":
					_cave(job, cfg, r, sx, sz)
				elif t == "canyon":
					_canyon(job, cfg, r, sx, sz)


func _cave(job: Job, cfg: Dictionary, r: RandomSources.LegacyRandom, sx: int, sz: int) -> void:
	var i := (4 * 2 - 1) * 16
	var n := isample(r, cfg.get("count", 14))
	for k in n:
		var d := float(sx * 16 + r.next_int_bound(16))
		var e := float(isample(r, cfg.get("y", 64)))
		var f := float(sz * 16 + r.next_int_bound(16))
		var g := fsample(r, cfg.get("horizontal_radius_multiplier", 1.0))
		var h := fsample(r, cfg.get("vertical_radius_multiplier", 1.0))
		var floor_l := fsample(r, cfg.get("floor_level", -0.7))
		var m := 1
		if r.next_int_bound(4) == 0:
			var ys := fsample(r, cfg.get("room_vertical_radius_multiplier", 0.5))
			var o := 1.0 + r.next_float() * 6.0
			var rad := 1.5 + sin(PI / 2.0) * o
			_ellipsoid(job, d + 1.0, e, f, rad, rad * ys, floor_l, null)
			m += r.next_int_bound(4)
		for p in m:
			var yaw := r.next_float() * TAU
			var pitch := (r.next_float() - 0.5) / 4.0
			var thick := fsample(r, cfg.get("thickness", 2.0))
			if bool(cfg.get("weird_thickness_bias", false)) and r.next_int_bound(10) == 0:
				thick *= r.next_float() * r.next_float() * 3.0 + 1.0
			var s := i - r.next_int_bound(i / 4)
			_tunnel(job, r.next_long(), d, e, f, g, h, thick, yaw, pitch, 0, s, float(cfg.get("start_vertical_radius_multiplier", 1.0)), floor_l)


func _tunnel(job: Job, seed: int, d: float, e: float, f: float, g: float, h: float, thick: float, yaw: float, pitch: float, start: int, end: int, yscale: float, floor_l: float) -> void:
	var r := RandomSources.LegacyRandom.new(seed)
	var o := r.next_int_bound(end / 2) + end / 4
	var steep := r.next_int_bound(6) == 0
	var p := 0.0
	var q := 0.0
	for idx in range(start, end):
		var s := 1.5 + sin(PI * idx / end) * thick
		var t := s * yscale
		var u := cos(pitch)
		d += cos(yaw) * u
		e += sin(pitch)
		f += sin(yaw) * u
		pitch *= 0.92 if steep else 0.7
		pitch += q * 0.1
		yaw += p * 0.1
		q *= 0.9
		p *= 0.75
		q += (r.next_float() - r.next_float()) * r.next_float() * 2.0
		p += (r.next_float() - r.next_float()) * r.next_float() * 4.0
		if idx == o and thick > 1.0:
			_tunnel(job, r.next_long(), d, e, f, g, h, r.next_float() * 0.5 + 0.5, yaw - PI / 2.0, pitch / 3.0, idx, end, 1.0, floor_l)
			_tunnel(job, r.next_long(), d, e, f, g, h, r.next_float() * 0.5 + 0.5, yaw + PI / 2.0, pitch / 3.0, idx, end, 1.0, floor_l)
			return
		if r.next_int_bound(4) == 0:
			continue
		if not _can_reach(job, d, f, idx, end, thick):
			return
		_ellipsoid(job, d, e, f, s * g, t * h, floor_l, null)


func _can_reach(job: Job, d: float, e: float, i: int, j: int, f: float) -> bool:
	var g := job.cx * 16 + 8.0
	var h := job.cz * 16 + 8.0
	var k := d - g
	var l := e - h
	var m := float(j - i)
	var n := f + 2.0 + 16.0
	return k * k + l * l - m * m <= n * n


func _canyon(job: Job, cfg: Dictionary, r: RandomSources.LegacyRandom, sx: int, sz: int) -> void:
	var shape: Dictionary = cfg.get("shape", {})
	var i := (4 * 2 - 1) * 16
	var d := float(sx * 16 + r.next_int_bound(16))
	var j := isample(r, cfg.get("y", 40))
	var e := float(sz * 16 + r.next_int_bound(16))
	var f := r.next_float() * TAU
	var g := fsample(r, cfg.get("vertical_rotation", 0.0))
	var h := fsample(r, shape.get("y_scale", cfg.get("y_scale", 3.0)))
	var k := fsample(r, shape.get("thickness", 2.0))
	var l := int(i * fsample(r, shape.get("distance_factor", 1.0)))
	_canyon_carve(job, cfg, shape, r.next_long(), d, float(j), e, k, f, g, 0, l, h)


func _canyon_carve(job: Job, cfg: Dictionary, shape: Dictionary, seed: int, d: float, e: float, f: float, g: float, yaw: float, pitch: float, start: int, end: int, yscale: float) -> void:
	var r := RandomSources.LegacyRandom.new(seed)
	var widths := PackedFloat32Array()
	widths.resize(gen.gen_depth)
	var w := 1.0
	var smooth := maxi(1, int(shape.get("width_smoothness", 3)))
	for jj in gen.gen_depth:
		if jj == 0 or r.next_int_bound(smooth) == 0:
			w = 1.0 + r.next_float() * r.next_float()
		widths[jj] = w * w
	var m := 0.0
	var n := 0.0
	for o in range(start, end):
		var p := 1.5 + sin(o * PI / end) * g
		var q := p * yscale
		p *= fsample(r, shape.get("horizontal_radius_factor", 1.0))
		var hh := 1.0 - absf(0.5 - float(o) / end) * 2.0
		var vf := float(shape.get("vertical_radius_default_factor", 1.0)) + float(shape.get("vertical_radius_center_factor", 0.0)) * hh
		q = vf * q * (r.next_float() * 0.25 + 0.75)
		var rr := cos(pitch)
		var ss := sin(pitch)
		d += cos(yaw) * rr
		e += ss
		f += sin(yaw) * rr
		pitch *= 0.7
		pitch += n * 0.05
		yaw += m * 0.05
		n *= 0.8
		m *= 0.5
		n += (r.next_float() - r.next_float()) * r.next_float() * 2.0
		m += (r.next_float() - r.next_float()) * r.next_float() * 4.0
		if r.next_int_bound(4) == 0:
			continue
		if not _can_reach(job, d, f, o, end, g):
			return
		_ellipsoid(job, d, e, f, p, q, -INF, widths)


## Java WorldCarver.carveEllipsoid restricted to the target chunk.
func _ellipsoid(job: Job, d: float, e: float, f: float, g: float, h: float, floor_l: float, widths) -> void:
	var mx := job.cx * 16 + 8.0
	var mz := job.cz * 16 + 8.0
	var k := 16.0 + g * 2.0
	if absf(d - mx) > k or absf(f - mz) > k:
		return
	var l := job.cx * 16
	var m := job.cz * 16
	var n := maxi(int(floor(d - g)) - l - 1, 0)
	var o := mini(int(floor(d + g)) - l, 15)
	var p := maxi(int(floor(e - h)) - 1, gen.gen_min_y + 1)
	var r2 := mini(int(floor(e + h)) + 1, gen.gen_min_y + gen.gen_depth - 1 - 7)
	var lava_level := gen.gen_min_y + 8
	var sea := gen.sea_level
	var lava_y := mini(-54, sea)
	var s := maxi(int(floor(f - g)) - m - 1, 0)
	var t := mini(int(floor(f + g)) - m, 15)
	var col := job.col
	var flags := gen.blocks.st_flags
	var blocks_st := gen.blocks.st_block
	for u in range(n, o + 1):
		var wx := ((l + u) + 0.5 - d) / g
		for x in range(s, t + 1):
			var wz := ((m + x) + 0.5 - f) / g
			if wx * wx + wz * wz >= 1.0:
				continue
			var surface := false
			for aa in range(r2, p, -1):
				var ab := (aa - 0.5 - e) / h
				if widths == null:
					if ab <= floor_l or wx * wx + ab * ab + wz * wz >= 1.0:
						continue
				else:
					var wj: float = widths[clampi(aa - gen.gen_min_y - 1, 0, widths.size() - 1)]
					if (wx * wx + wz * wz) * wj + ab * ab / 6.0 >= 1.0:
						continue
				var bi := ((aa - Coords.MIN_Y) << 8) | (x << 4) | u
				if job.mask[bi] == 1:
					continue
				job.mask[bi] = 1
				var cur := col[bi]
				var cb := blocks_st[cur] if cur >= 0 else -1
				if cb == job.grass or cb == job.mycelium:
					surface = true
				if not job.replaceable.has(cb):
					continue
				var ns: int
				if aa <= lava_level:
					ns = gen.S_LAVA
				elif job.aq != null:
					ns = job.aq.substance(l + u, aa, m + x, 0.0)
					if ns < 0:
						continue
				else:
					# disabled aquifer: global fluid picker
					ns = gen.S_LAVA if aa < lava_y else (gen.S_FLUID if aa < sea else 0)
				col[bi] = ns
				if surface and aa - 1 >= Coords.MIN_Y:
					var bi2 := ((aa - 1 - Coords.MIN_Y) << 8) | (x << 4) | u
					if blocks_st[col[bi2]] == job.dirt:
						col[bi2] = gen.S_GRASS if (flags[ns] & BlockRegistry.F_LIQUID) == 0 else col[bi2]
