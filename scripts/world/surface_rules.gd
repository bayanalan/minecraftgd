## SurfaceRules — compiler/evaluator for 26.3 `worldgen/material_rule` + `material_condition` JSON (and the
## equivalent pre-26.3 `surface_rule` shape): sequence, condition, block, bandlands, ore_vein; conditions
## biome, noise_threshold (2D/3D), vertical_gradient, y_above, water, stone_depth, not, steep, hole,
## above_preliminary_surface, temperature. Column walk follows Java SurfaceSystem.buildSurface semantics
## (stoneDepthAbove/Below, waterHeight, surfaceDepth = noise*2.75+3+rand*0.25), only replacing default stone.
## Contract: SurfaceRules.new(gen).compile(name) ; apply_column(...) mutates a column array in place.
class_name SurfaceRules
extends RefCounted

enum R { SEQ, COND, BLOCK, BANDS, VEIN, NONE }
enum C { BIOME, NOISE, VGRAD, YABOVE, WATER, DEPTH, NOT, STEEP, HOLE, ABOVE_PRELIM, TEMP, TRUE }

var gen: VanillaGenerator
var rules: Dictionary = {}
var conds: Dictionary = {}
var root: Dictionary
var bands := PackedInt32Array()
var band_noise: MCNoise.Normal
var surface_noise: MCNoise.Normal
var secondary_noise: MCNoise.Normal
var vgrad_rand: Dictionary = {}
var ore_rand   # RandomSources.XoroPositional or LegacyPositional


func _init(g: VanillaGenerator) -> void:
	gen = g


func setup(rule_name: String) -> void:
	surface_noise = gen.dfc.noise("minecraft:surface")
	secondary_noise = gen.dfc.noise("minecraft:surface_secondary")
	band_noise = gen.dfc.noise("minecraft:clay_bands_offset")
	ore_rand = gen.dfc.rand.from_hash("minecraft:ore").fork_positional()
	_make_bands()
	root = _rule(rule_name)


func _src(kind: String, name: String):
	return gen.source.call("data/minecraft/worldgen/%s/%s.json" % [kind, name.trim_prefix("minecraft:")])


func _rule(v) -> Dictionary:
	if v is String:
		if rules.has(v):
			return rules[v]
		var j = _src("material_rule", v)
		if j == null:
			j = _src("surface_rule", v)
		var r := _rule(j) if j != null else {"t": R.NONE}
		rules[v] = r
		return r
	if not (v is Dictionary):
		return {"t": R.NONE}
	var t := str(v.get("type", "")).trim_prefix("minecraft:")
	match t:
		"sequence":
			var seq: Array = []
			for s in v.get("sequence", []):
				seq.append(_rule(s))
			return {"t": R.SEQ, "seq": seq}
		"condition":
			return {"t": R.COND, "if": _cond(v.get("if_true", {})), "then": _rule(v.get("then_run", {}))}
		"block":
			var rs = v.get("result_state", "minecraft:stone")
			var st := -1
			if rs is String:
				st = gen.blocks.parse_state(rs)
			elif rs is Dictionary:
				st = gen.blocks.state_of(str(rs.get("Name", "minecraft:stone")), rs.get("Properties", {}))
			if st < 0:
				st = gen.blocks.STONE
			return {"t": R.BLOCK, "s": st}
		"bandlands":
			return {"t": R.BANDS}
		"ore_vein":
			var vd := gen.dfc.get_df(v.get("density", 0.0))
			var cj := conj_of(vd)
			var vr := {"t": R.VEIN, "density": vd, "richness": gen.dfc.get_df(v.get("richness", 0.0)),
				"gap": gen.dfc.get_df(v.get("filler_gap", 0.0)), "ore": _st(v.get("ore_block")), "raw": _st(v.get("raw_ore_block")),
				"filler": _st(v.get("filler_block")), "raw_chance": float(v.get("raw_ore_chance", 0.02))}
			if not cj.is_empty():
				vr["conj"] = cj
			return vr
	return {"t": R.NONE}


func _st(v) -> int:
	var s := gen.blocks.parse_state(str(v)) if v is String else -1
	return s if s >= 0 else gen.blocks.STONE


func _anchor(a) -> int:
	if a is Dictionary:
		if a.has("absolute"):
			return int(a["absolute"])
		if a.has("above_bottom"):
			return gen.gen_min_y + int(a["above_bottom"])
		if a.has("below_top"):
			return gen.gen_min_y + gen.gen_depth - 1 - int(a["below_top"])
	return 0


func _cond(v) -> Dictionary:
	if v is String:
		if conds.has(v):
			return conds[v]
		var j = _src("material_condition", v)
		var c := _cond(j) if j != null else {"t": C.TRUE}
		conds[v] = c
		return c
	if not (v is Dictionary):
		return {"t": C.TRUE}
	var t := str(v.get("type", "")).trim_prefix("minecraft:")
	match t:
		"biome":
			var lst = v.get("biome_is", [])
			if lst is String:
				lst = [lst]
			var ids := {}
			for b in lst:
				ids[gen.biomes.id(str(b))] = true
			return {"t": C.BIOME, "ids": ids}
		"noise_threshold":
			return {"t": C.NOISE, "noise": gen.dfc.noise(str(v.get("noise", ""))), "min": float(v.get("min_threshold", -1e30)), "max": float(v.get("max_threshold", 1e30)), "3d": bool(v.get("is_3d", false))}
		"vertical_gradient":
			var rn := str(v.get("random_name", "x"))
			if not vgrad_rand.has(rn):
				vgrad_rand[rn] = gen.dfc.rand.from_hash(rn).fork_positional()
			return {"t": C.VGRAD, "r": vgrad_rand[rn], "lo": _anchor(v.get("true_at_and_below")), "hi": _anchor(v.get("false_at_and_above"))}
		"y_above":
			return {"t": C.YABOVE, "y": _anchor(v.get("anchor")), "mul": int(v.get("surface_depth_multiplier", 0)), "add": bool(v.get("add_stone_depth", false))}
		"water":
			return {"t": C.WATER, "off": int(v.get("offset", 0)), "mul": int(v.get("surface_depth_multiplier", 0)), "add": bool(v.get("add_stone_depth", false))}
		"stone_depth":
			return {"t": C.DEPTH, "off": int(v.get("offset", 0)), "add": bool(v.get("add_surface_depth", false)), "range": int(v.get("secondary_depth_range", 0)), "ceil": str(v.get("surface_type", "floor")) == "ceiling"}
		"not":
			return {"t": C.NOT, "c": _cond(v.get("invert", {}))}
		"steep":
			return {"t": C.STEEP}
		"hole":
			return {"t": C.HOLE}
		"above_preliminary_surface":
			return {"t": C.ABOVE_PRELIM}
		"temperature":
			return {"t": C.TEMP}
	return {"t": C.TRUE}


func _make_bands() -> void:
	var r = gen.dfc.rand.from_hash("minecraft:clay_bands")
	var b := gen.blocks
	var terr := b.default_state("terracotta")
	bands.resize(192)
	bands.fill(terr)
	var i := 0
	while i < 192:
		i += int(r.next_int_bound(5)) + 1
		if i < 192:
			bands[i] = b.default_state("orange_terracotta")
		i += 1
	_make_band(r, 1, b.default_state("yellow_terracotta"))
	_make_band(r, 2, b.default_state("brown_terracotta"))
	_make_band(r, 1, b.default_state("red_terracotta"))
	var n: int = 9 + r.next_int_bound(7)
	var j := 0
	var k := 0
	while j < n and k < 192:
		bands[k] = b.default_state("white_terracotta")
		if k - 1 > 0 and r.next_bool():
			bands[k - 1] = b.default_state("light_gray_terracotta")
		if k + 1 < 192 and r.next_bool():
			bands[k + 1] = b.default_state("light_gray_terracotta")
		j += 1
		k += int(r.next_int_bound(16)) + 4


func _make_band(r, base: int, st: int) -> void:
	var j: int = 6 + r.next_int_bound(10)
	for kk in j:
		var l: int = base + int(r.next_int_bound(3))
		var m: int = r.next_int_bound(192)
		var n := 0
		while m + n < 192 and n < l:
			bands[m + n] = st
			n += 1


# ------------------------------------------------------------------ evaluation context (per column)

class Ctx:
	var x := 0
	var y := 0
	var z := 0
	var biome := 0
	var above := 0      # stoneDepthAbove
	var below := 0      # stoneDepthBelow
	var water := -2147483648
	var depth := 0      # surfaceDepth
	var secondary := INF
	var min_surface := -2147483648
	var steep := -1
	var hm: PackedInt32Array
	var dfctx: DensityFunctions.Ctx
	var chunk: Chunk


func surface_depth(x: int, z: int) -> int:
	var d := surface_noise.value(x, 0.0, z)
	var r = gen.dfc.rand.at(x, 0, z)
	return int(d * 2.75 + 3.0 + float(r.next_double()) * 0.25)


func apply(r: Dictionary, c: Ctx) -> int:
	match int(r["t"]):
		R.BLOCK:
			return r["s"]
		R.SEQ:
			for s in r["seq"]:
				var v := apply(s, c)
				if v >= 0:
					return v
			return -1
		R.COND:
			if test(r["if"], c):
				return apply(r["then"], c)
			return -1
		R.BANDS:
			var l := int(roundf(band_noise.value(c.x, 0.0, c.z) * 4.0))
			return bands[posmod(c.y + l + 192, 192)]
		R.VEIN:
			var d := (r["density"] as DensityFunctions.DF).point(c.dfctx, c.x, c.y, c.z)
			if d < 0.0:
				return -1
			var rs = ore_rand.at(c.x, c.y, c.z)
			if rs.next_float() > d:
				return -1
			var rich := (r["richness"] as DensityFunctions.DF).point(c.dfctx, c.x, c.y, c.z)
			if rs.next_float() < rich and (r["gap"] as DensityFunctions.DF).point(c.dfctx, c.x, c.y, c.z) < 0.0:
				return r["raw"] if rs.next_float() < float(r["raw_chance"]) else r["ore"]
			return r["filler"]
	return -1


func test(cd: Dictionary, c: Ctx) -> bool:
	match int(cd["t"]):
		C.BIOME:
			return (cd["ids"] as Dictionary).has(c.biome)
		C.NOISE:
			var nv := (cd["noise"] as MCNoise.Normal).value(c.x, c.y if cd["3d"] else 0.0, c.z)
			return nv >= cd["min"] and nv <= cd["max"]
		C.VGRAD:
			var lo: int = cd["lo"]
			var hi: int = cd["hi"]
			if c.y <= lo:
				return true
			if c.y >= hi:
				return false
			var prob := remap(float(c.y), float(lo), float(hi), 1.0, 0.0)
			return float(cd["r"].at(c.x, c.y, c.z).next_float()) < prob
		C.YABOVE:
			return c.y + (c.above if cd["add"] else 0) >= int(cd["y"]) + c.depth * int(cd["mul"])
		C.WATER:
			return c.water == -2147483648 or c.y + (c.above if cd["add"] else 0) >= c.water + int(cd["off"]) + c.depth * int(cd["mul"])
		C.DEPTH:
			var dv := c.below if cd["ceil"] else c.above
			var sd := c.depth if cd["add"] else 0
			var rng: int = cd["range"]
			var sec := 0
			if rng != 0:
				if c.secondary == INF:
					c.secondary = secondary_noise.value(c.x, 0.0, c.z)
				sec = int(remap(c.secondary, -1.0, 1.0, 0.0, float(rng)))
			return dv <= 1 + int(cd["off"]) + sd + sec
		C.NOT:
			return not test(cd["c"], c)
		C.STEEP:
			if c.steep < 0:
				c.steep = 1 if _steep(c) else 0
			return c.steep == 1
		C.HOLE:
			return c.depth <= 0
		C.ABOVE_PRELIM:
			if c.min_surface == -2147483648:
				c.min_surface = gen.chunk_surface(c.dfctx, c.x, c.z) + c.depth - 8
			return c.y >= c.min_surface
		C.TEMP:
			return gen.biome_temperature_at(c.biome, c.x, c.y, c.z) < 0.15
	return true


# ------------------------------------------------------------------ batch application (whole chunk)

class BCtx:
	var cand := PackedInt32Array()     # block index ((y-MIN)<<8)|(z<<4)|x
	var above := PackedInt32Array()
	var below := PackedInt32Array()
	var water := PackedInt32Array()
	var res := PackedInt32Array()
	var depth := PackedInt32Array()    # per column
	var secondary := PackedFloat64Array()
	var min_surface := PackedInt32Array()
	var steep := PackedByteArray()     # 0 unknown, 1 false, 2 true
	var noise2d: Dictionary = {}       # noise -> PackedFloat64Array(256) (NaN = unknown)
	var hm: PackedInt32Array
	var biomes: PackedByteArray
	var dctx: DensityFunctions.Ctx
	var blocks_pts: DensityFunctions.Pts
	var cvc = null                     # interval_all cache (per chunk)
	var x0 := 0
	var z0 := 0


const MINI := -2147483648


## Java SurfaceSystem.buildSurface column walk + batched rule application. Mutates `col` in place.
func apply_chunk(dctx: DensityFunctions.Ctx, blocks_pts: DensityFunctions.Pts, col: PackedInt32Array, biomes_arr: PackedByteArray, hm: PackedInt32Array, stone: int) -> void:
	var bc := BCtx.new()
	bc.dctx = dctx
	bc.blocks_pts = blocks_pts
	bc.hm = hm
	bc.biomes = biomes_arr
	bc.x0 = dctx.x0
	bc.z0 = dctx.z0
	bc.depth.resize(256)
	bc.secondary.resize(256)
	bc.secondary.fill(NAN)
	bc.min_surface.resize(256)
	bc.min_surface.fill(MINI)
	bc.steep.resize(256)
	var tw0 := Time.get_ticks_usec()
	var flags := gen.blocks.st_flags
	var cand := PackedInt32Array()
	var above := PackedInt32Array()
	var below := PackedInt32Array()
	var wat := PackedInt32Array()
	var dep := bc.depth
	var LIQ := BlockRegistry.F_LIQUID
	for c in 256:
		var x := bc.x0 + (c & 15)
		var z := bc.z0 + (c >> 4)
		dep[c] = surface_depth(x, z)
		var q := 0
		var r := MINI
		var s := 2147483647
		var top := hm[c]
		for y in range(mini(top, Coords.MAX_Y - 1), Coords.MIN_Y - 1, -1):
			var i := ((y - Coords.MIN_Y) << 8) | c
			var st := col[i]
			if st == 0:
				q = 0
				r = MINI
				continue
			if flags[st] & LIQ:
				if r == MINI:
					r = y + 1
				continue
			if s >= y:
				s = -2032
				for v in range(y - 1, Coords.MIN_Y - 2, -1):
					if v < Coords.MIN_Y:
						s = v + 1
						break
					var sv := col[((v - Coords.MIN_Y) << 8) | c]
					if sv == 0 or (flags[sv] & LIQ):
						s = v + 1
						break
			q += 1
			if st != stone:
				continue
			cand.append(i)
			above.append(q)
			below.append(y - s + 1)
			wat.append(r)
	bc.cand = cand
	bc.above = above
	bc.below = below
	bc.water = wat
	var tw := Time.get_ticks_usec()
	var n := cand.size()
	bc.res.resize(n)
	bc.res.fill(-1)
	var idx := PackedInt32Array()
	idx.resize(n)
	for k in n:
		idx[k] = k
	_apply_b(root, bc, idx)
	if prof_on:
		prof["walk"] = prof.get("walk", 0) + (tw - tw0)
		prof["rules"] = prof.get("rules", 0) + (Time.get_ticks_usec() - tw)
		prof["cands"] = prof.get("cands", 0) + n
	var res := bc.res
	for k in n:
		if res[k] >= 0:
			col[cand[k]] = res[k]


func _apply_b(r: Dictionary, bc: BCtx, idx: PackedInt32Array) -> PackedInt32Array:
	if idx.is_empty():
		return idx
	var res := bc.res
	match int(r["t"]):
		R.BLOCK:
			var s: int = r["s"]
			for k in idx:
				res[k] = s
			return PackedInt32Array()
		R.SEQ:
			var rem := idx
			for child in r["seq"]:
				rem = _apply_b(child, bc, rem)
				if rem.is_empty():
					break
			return rem
		R.COND:
			var m := _test_b(r["if"], bc, idx)
			var pas := PackedInt32Array()
			var fail := PackedInt32Array()
			for j in idx.size():
				if m[j] == 1:
					pas.append(idx[j])
				else:
					fail.append(idx[j])
			if not pas.is_empty():
				fail.append_array(_apply_b(r["then"], bc, pas))
			return fail
		R.BANDS:
			var nv_arr := _noise2d_all(bc, band_noise)
			var cand := bc.cand
			var bnd := bands
			for k in idx:
				var i := cand[k]
				var y := -64 + (i >> 8)
				res[k] = bnd[posmod(y + int(roundf(nv_arr[i & 255] * 4.0)) + 192, 192)]
			return PackedInt32Array()
		R.VEIN:
			if prof_on:
				var tv := Time.get_ticks_usec()
				var rv := _vein_b(r, bc, idx)
				prof["vein"] = prof.get("vein", 0) + (Time.get_ticks_usec() - tv)
				prof["vein_n"] = prof.get("vein_n", 0) + idx.size()
				return rv
			return _vein_b(r, bc, idx)
	return idx


## Full 256-column 2D noise plane at y=0 (cached per chunk and noise).
func _noise2d_all(bc: BCtx, nz: MCNoise.Normal) -> PackedFloat64Array:
	var arr = bc.noise2d.get(nz)
	if arr != null:
		return arr
	var a := PackedFloat64Array()
	a.resize(256)
	var x0 := bc.x0
	var z0 := bc.z0
	for c in 256:
		a[c] = nz.value(x0 + (c & 15), 0.0, z0 + (c >> 4))
	bc.noise2d[nz] = a
	return a

func _vein_b(r: Dictionary, bc: BCtx, idx: PackedInt32Array) -> PackedInt32Array:
	var blocks_idx := PackedInt32Array()
	blocks_idx.resize(idx.size())
	for j in idx.size():
		blocks_idx[j] = bc.cand[idx[j]]
	var tvb := Time.get_ticks_usec()
	var dens: PackedFloat64Array
	if r.has("conj"):
		dens = _conj_eval(r["conj"], bc, blocks_idx)
	else:
		var sub := bc.dctx.sub(bc.blocks_pts, blocks_idx)
		dens = (r["density"] as DensityFunctions.DF).batch(bc.dctx, sub)
	if prof_on:
		prof["vein_dens"] = prof.get("vein_dens", 0) + (Time.get_ticks_usec() - tvb)
	var inv := PackedInt32Array()
	var rem := PackedInt32Array()
	for j in idx.size():
		if dens[j] >= 0.0:
			inv.append(j)
		else:
			rem.append(idx[j])
	if inv.is_empty():
		return rem
	var bi2 := PackedInt32Array()
	for j in inv:
		bi2.append(blocks_idx[j])
	var sub2 := bc.dctx.sub(bc.blocks_pts, bi2)
	var rich := (r["richness"] as DensityFunctions.DF).batch(bc.dctx, sub2)
	var gap := (r["gap"] as DensityFunctions.DF).batch(bc.dctx, sub2)
	for t in inv.size():
		var j := inv[t]
		var k := idx[j]
		var i := bc.cand[k]
		var x := bc.x0 + (i & 15)
		var z := bc.z0 + ((i >> 4) & 15)
		var y := Coords.MIN_Y + (i >> 8)
		var rs = ore_rand.at(x, y, z)
		if rs.next_float() > dens[j]:
			rem.append(k)
			continue
		if rs.next_float() < rich[t] and gap[t] < 0.0:
			bc.res[k] = r["raw"] if rs.next_float() < float(r["raw_chance"]) else r["ore"]
		else:
			bc.res[k] = r["filler"]
	return rem


## Nested range_choice chains whose out-of-range branches are one shared constant form a conjunction; their
## conditions can be tested in any order with identical results, so cheap ones (y, interpolated) run first and
## expensive noise masks only see survivors. Returns {} when the DF does not have that shape.
static func conj_of(df: DensityFunctions.DF) -> Dictionary:
	var conds: Array = []
	var out_v := NAN
	var node := df
	var K := DensityFunctions.K
	while node != null and node.k == K.RANGE:
		var cv := _const_val(node.c)
		if is_nan(cv):
			return {}
		if is_nan(out_v):
			out_v = cv
		elif cv != out_v:
			return {}
		conds.append([_cost(node.a, {}), node.a, node.v0, node.v1])
		node = node.b
	var val := _const_val(node)
	if conds.size() < 2 or is_nan(val):
		return {}
	conds.sort_custom(func(p, q): return p[0] < q[0])
	return {"conds": conds, "val": val, "out": out_v}


static func _const_val(d: DensityFunctions.DF) -> float:
	if d == null:
		return NAN
	match d.k:
		DensityFunctions.K.CONST:
			return d.v0
		DensityFunctions.K.ONE:
			return 1.0
		DensityFunctions.K.ZERO:
			return 0.0
	return NAN


static func _cost(d: DensityFunctions.DF, seen: Dictionary) -> float:
	if d == null or seen.has(d.id):
		return 0.0
	seen[d.id] = true
	var K := DensityFunctions.K
	if d.k == K.INTERP:
		return 1.0
	var c := 0.0
	if d.k == K.NOISE or d.k == K.BLENDED or d.k == K.SHIFT_A or d.k == K.SHIFT_B or d.k == K.SHIFT:
		c += 10.0
	c += _cost(d.a, seen) + _cost(d.b, seen) + _cost(d.c, seen)
	for f in d.funcs:
		if f is DensityFunctions.DF:
			c += _cost(f, seen)
	return c


func _conj_eval(cj: Dictionary, bc: BCtx, blocks_idx: PackedInt32Array) -> PackedFloat64Array:
	var n := blocks_idx.size()
	var out := PackedFloat64Array()
	out.resize(n)
	out.fill(float(cj["out"]))
	var alive := PackedInt32Array()
	alive.resize(n)
	for j in n:
		alive[j] = j
	var ci := 0
	if bc.cvc == null:
		bc.cvc = {}
	for cond in cj["conds"]:
		ci += 1
		var tq := Time.get_ticks_usec()
		if alive.is_empty():
			return out
		var df: DensityFunctions.DF = cond[1]
		var lo: float = cond[2]
		var hi: float = cond[3]
		# exact per-cell interval classification: 0 = all fail, 1 = all pass, 2 = evaluate per point
		var bounds: Array = df.interval_all(bc.dctx, bc.cvc)
		var blo: PackedFloat64Array = bounds[0]
		var bhi: PackedFloat64Array = bounds[1]
		var cls := PackedByteArray()
		cls.resize(768)
		for cell in 768:
			if bhi[cell] < lo or blo[cell] >= hi:
				cls[cell] = 0
			elif blo[cell] >= lo and bhi[cell] < hi:
				cls[cell] = 1
			else:
				cls[cell] = 2
		var nxt := PackedInt32Array()
		var pend := PackedInt32Array()
		for t in alive.size():
			var a := alive[t]
			var i := blocks_idx[a]
			var cell := ((i & 15) >> 2) | ((((i >> 4) & 15) >> 2) << 2) | ((i >> 11) << 4)
			var cc := cls[cell]
			if cc == 1:
				nxt.append(a)
			elif cc == 2:
				pend.append(a)
		if not pend.is_empty():
			var bi := PackedInt32Array()
			bi.resize(pend.size())
			for t in pend.size():
				bi[t] = blocks_idx[pend[t]]
			var vals := df.batch(bc.dctx, bc.dctx.sub(bc.blocks_pts, bi))
			for t in pend.size():
				var v := vals[t]
				if v >= lo and v < hi:
					nxt.append(pend[t])
		if prof_on:
			var key := "cj%d_%s_cost%d" % [ci, DensityFunctions.K.keys()[df.k], int(cond[0])]
			prof[key] = prof.get(key, 0) + (Time.get_ticks_usec() - tq)
			prof[key + "_n"] = prof.get(key + "_n", 0) + alive.size()
			prof[key + "_pts"] = prof.get(key + "_pts", 0) + pend.size()
		alive = nxt
	var val: float = cj["val"]
	for j in alive:
		out[j] = val
	return out


var prof_on := false
var prof: Dictionary = {}


func _test_b(cd: Dictionary, bc: BCtx, idx: PackedInt32Array) -> PackedByteArray:
	if prof_on:
		var tt := Time.get_ticks_usec()
		var rr := _test_b2(cd, bc, idx)
		var key := "C%d" % int(cd["t"])
		prof[key] = prof.get(key, 0) + (Time.get_ticks_usec() - tt)
		prof[key + "n"] = prof.get(key + "n", 0) + idx.size()
		return rr
	return _test_b2(cd, bc, idx)


func _test_b2(cd: Dictionary, bc: BCtx, idx: PackedInt32Array) -> PackedByteArray:
	var n := idx.size()
	var m := PackedByteArray()
	m.resize(n)
	var cand := bc.cand
	match int(cd["t"]):
		C.TRUE:
			m.fill(1)
		C.BIOME:
			var ids: Dictionary = cd["ids"]
			var bio := bc.biomes
			for j in n:
				var i := cand[idx[j]]
				var b := bio[((i & 15) >> 2) + (((i >> 4) & 15) >> 2) * 4 + ((i >> 8) >> 2) * 16]
				m[j] = 1 if ids.has(int(b)) else 0
		C.NOISE:
			var nz: MCNoise.Normal = cd["noise"]
			var lo: float = cd["min"]
			var hi: float = cd["max"]
			var is3d: bool = cd["3d"]
			if is3d:
				var x0 := bc.x0
				var z0 := bc.z0
				for j in n:
					var i2 := cand[idx[j]]
					var v := nz.value(x0 + (i2 & 15), -64 + (i2 >> 8), z0 + ((i2 >> 4) & 15))
					m[j] = 1 if v >= lo and v <= hi else 0
			else:
				var plane := _noise2d_all(bc, nz)
				for j in n:
					var v2 := plane[cand[idx[j]] & 255]
					m[j] = 1 if v2 >= lo and v2 <= hi else 0
		C.VGRAD:
			var lo2: int = cd["lo"]
			var hi2: int = cd["hi"]
			var rp = cd["r"]
			var legacy_r: bool = rp is RandomSources.LegacyPositional
			var rlo: int = rp.seed if legacy_r else rp.lo
			var rhi: int = 0 if legacy_r else rp.hi
			var x0g := bc.x0
			var z0g := bc.z0
			var span := float(hi2 - lo2)
			for j in n:
				var i3 := cand[idx[j]]
				var y := -64 + (i3 >> 8)
				if y <= lo2:
					m[j] = 1
				elif y >= hi2:
					m[j] = 0
				else:
					var prob := 1.0 - float(y - lo2) / span
					# inlined XoroPositional.at(x, y, z).next_float() (Mth.getSeed + one xoroshiro128++ step)
					var t := ((x0g + (i3 & 15)) * 3129871) & 0xFFFFFFFF
					if t >= 0x80000000:
						t -= 0x100000000
					var ls: int = t ^ ((z0g + ((i3 >> 4) & 15)) * 116129781) ^ y
					ls = ls * ls * 42317861 + ls * 11
					if legacy_r:
						# inlined LegacyPositional.at(x, y, z).next_float(): java.util.Random(seed ^ getSeed).next(24)
						var lsd: int = (((ls >> 16) ^ rlo) ^ 0x5DEECE66D) & 0xFFFFFFFFFFFF
						lsd = (lsd * 0x5DEECE66D + 0xB) & 0xFFFFFFFFFFFF
						m[j] = 1 if float(lsd >> 24) / 16777216.0 < prob else 0
						continue
					var sl: int = (ls >> 16) ^ rlo
					var sh := rhi
					if sl == 0 and sh == 0:
						sl = -7046029254386353131
						sh = 7640891576956012809
					var su := sl + sh
					var nl: int = ((su << 17) | ((su >> 47) & 0x1FFFF)) + sl
					var fv := float((nl >> 40) & 0xFFFFFF) * 5.9604645e-8
					m[j] = 1 if fv < prob else 0
		C.YABOVE:
			var ay: int = cd["y"]
			var mul: int = cd["mul"]
			var add: bool = cd["add"]
			var above := bc.above
			var depth := bc.depth
			for j in n:
				var k := idx[j]
				var i4 := cand[k]
				var y4 := -64 + (i4 >> 8)
				m[j] = 1 if y4 + (above[k] if add else 0) >= ay + depth[i4 & 255] * mul else 0
		C.WATER:
			var off: int = cd["off"]
			var mul2: int = cd["mul"]
			var add2: bool = cd["add"]
			var above2 := bc.above
			var depth2 := bc.depth
			var wat := bc.water
			for j in n:
				var k2 := idx[j]
				var w := wat[k2]
				if w == MINI:
					m[j] = 1
					continue
				var i5 := cand[k2]
				var y5 := -64 + (i5 >> 8)
				m[j] = 1 if y5 + (above2[k2] if add2 else 0) >= w + off + depth2[i5 & 255] * mul2 else 0
		C.DEPTH:
			var ceil_: bool = cd["ceil"]
			var add3: bool = cd["add"]
			var rng: int = cd["range"]
			var off2: int = cd["off"]
			var below3 := bc.below
			var above3 := bc.above
			var depth3 := bc.depth
			var sec_plane := PackedFloat64Array()
			if rng != 0:
				sec_plane = _noise2d_all(bc, secondary_noise)
			for j in n:
				var k3 := idx[j]
				var c3 := cand[k3] & 255
				var dv := below3[k3] if ceil_ else above3[k3]
				var sec := 0
				if rng != 0:
					sec = int((sec_plane[c3] + 1.0) * 0.5 * float(rng))
				m[j] = 1 if dv <= 1 + off2 + (depth3[c3] if add3 else 0) + sec else 0
		C.NOT:
			var inner := _test_b(cd["c"], bc, idx)
			for j in n:
				m[j] = 1 - inner[j]
		C.STEEP:
			var stp := bc.steep
			var hm := bc.hm
			for j in n:
				var c4 := cand[idx[j]] & 255
				if stp[c4] == 0:
					var lx := c4 & 15
					var lz := c4 >> 4
					var steep := false
					if hm[lx + mini(lz + 1, 15) * 16] >= hm[lx + maxi(lz - 1, 0) * 16] + 4:
						steep = true
					elif hm[maxi(lx - 1, 0) + lz * 16] >= hm[mini(lx + 1, 15) + lz * 16] + 4:
						steep = true
					stp[c4] = 2 if steep else 1
				m[j] = 1 if stp[c4] == 2 else 0
		C.HOLE:
			var depth4 := bc.depth
			for j in n:
				m[j] = 1 if depth4[cand[idx[j]] & 255] <= 0 else 0
		C.ABOVE_PRELIM:
			var ms := bc.min_surface
			var depth5 := bc.depth
			for j in n:
				var i6 := cand[idx[j]]
				var c6 := i6 & 255
				if ms[c6] == MINI:
					ms[c6] = gen.chunk_surface(bc.dctx, bc.x0 + (c6 & 15), bc.z0 + (c6 >> 4)) + depth5[c6] - 8
				m[j] = 1 if -64 + (i6 >> 8) >= ms[c6] else 0
		C.TEMP:
			var bio2 := bc.biomes
			var temps: PackedFloat32Array = gen.biomes.temperature
			var lim := gen.sea_level + 17
			for j in n:
				var i7 := cand[idx[j]]
				var b7 := bio2[((i7 & 15) >> 2) + (((i7 >> 4) & 15) >> 2) * 4 + ((i7 >> 8) >> 2) * 16]
				var y7 := -64 + (i7 >> 8)
				var tv := temps[b7]
				if y7 > lim:
					tv -= float(y7 - lim) * 0.05 / 40.0
				m[j] = 1 if tv < 0.15 else 0
	return m

func _steep(c: Ctx) -> bool:
	var lx := c.x & 15
	var lz := c.z & 15
	var hm := c.hm
	var m := hm[lx + maxi(lz - 1, 0) * 16]
	var n := hm[lx + mini(lz + 1, 15) * 16]
	if n >= m + 4:
		return true
	var q := hm[maxi(lx - 1, 0) + lz * 16]
	var r := hm[mini(lx + 1, 15) + lz * 16]
	return q >= r + 4

# ------------------------------------------------------------------ native export (RecraftNative.tg_config)

class NExport:
	var sr
	var rule_ids := {}
	var rints := PackedInt32Array()     # 4 per rule: t, a, b, c
	var kids := PackedInt32Array()
	var cond_ids := {}
	var cints := PackedInt32Array()     # 5 per cond: t, i0..i3
	var cfl := PackedFloat64Array()     # 2 per cond
	var bsets := PackedByteArray()
	var vints := PackedInt32Array()     # 6 per vein: density, richness, gap, ore, raw, filler
	var vfl := PackedFloat64Array()     # 1 per vein: raw chance
	var noise_ids := {}
	var noises: Array = []
	var pos_ids := {}
	var poss: Array = []
	var nb := 0

	func noise(nz: MCNoise.Normal) -> int:
		var k := nz.get_instance_id()
		if not noise_ids.has(k):
			noise_ids[k] = noises.size()
			noises.append(sr.gen.dfc._export_noise(nz))
		return noise_ids[k]

	func pos(pr) -> int:
		var k: int = pr.get_instance_id()
		if not pos_ids.has(k):
			pos_ids[k] = poss.size()
			var legacy: bool = pr is RandomSources.LegacyPositional
			poss.append([1 if legacy else 0, pr.seed if legacy else pr.lo, 0 if legacy else pr.hi])
		return pos_ids[k]

	func rule(r: Dictionary) -> int:
		if rule_ids.has(r):
			return rule_ids[r]
		var id := rints.size() / 4
		rule_ids[r] = id
		rints.append_array([R.NONE, 0, 0, 0])
		var t := int(r["t"])
		var a := 0
		var b := 0
		match t:
			R.SEQ:
				var ch: Array = []
				for sub in r["seq"]:
					ch.append(rule(sub))
				a = kids.size()
				b = ch.size()
				kids.append_array(ch)
			R.COND:
				a = cond(r["if"])
				b = rule(r["then"])
			R.BLOCK:
				a = int(r["s"])
			R.VEIN:
				a = vints.size() / 6
				vints.append_array([(r["density"] as DensityFunctions.DF).id, (r["richness"] as DensityFunctions.DF).id, (r["gap"] as DensityFunctions.DF).id,
					int(r["ore"]), int(r["raw"]), int(r["filler"])])
				vfl.append(float(r["raw_chance"]))
		rints[id * 4] = t
		rints[id * 4 + 1] = a
		rints[id * 4 + 2] = b
		return id

	func cond(cd: Dictionary) -> int:
		if cond_ids.has(cd):
			return cond_ids[cd]
		var id := cints.size() / 5
		cond_ids[cd] = id
		cints.append_array([C.TRUE, 0, 0, 0, 0])
		cfl.append_array([0.0, 0.0])
		var t := int(cd["t"])
		var iv := [0, 0, 0, 0]
		match t:
			C.BIOME:
				iv[0] = bsets.size()
				var bs := PackedByteArray()
				bs.resize(nb)
				for bid in cd["ids"]:
					if int(bid) >= 0 and int(bid) < nb:
						bs[int(bid)] = 1
				bsets.append_array(bs)
			C.NOISE:
				iv[0] = noise(cd["noise"])
				iv[1] = 1 if cd["3d"] else 0
				cfl[id * 2] = float(cd["min"])
				cfl[id * 2 + 1] = float(cd["max"])
			C.VGRAD:
				iv = [pos(cd["r"]), int(cd["lo"]), int(cd["hi"]), 0]
			C.YABOVE:
				iv = [int(cd["y"]), int(cd["mul"]), 1 if cd["add"] else 0, 0]
			C.WATER:
				iv = [int(cd["off"]), int(cd["mul"]), 1 if cd["add"] else 0, 0]
			C.DEPTH:
				iv = [int(cd["off"]), 1 if cd["add"] else 0, int(cd["range"]), 1 if cd["ceil"] else 0]
			C.NOT:
				iv[0] = cond(cd["c"])
		cints[id * 5] = t
		for k in 4:
			cints[id * 5 + 1 + k] = iv[k]
		return id


## Flattened rule tree + noises/randoms/bands for native/src/surface.cpp (same semantics as apply_chunk).
func export_native() -> Array:
	var ex := NExport.new()
	ex.sr = self
	ex.nb = gen.biomes.names.size()
	var root_id := ex.rule(root)
	var misc := [root_id, ex.noise(surface_noise), ex.noise(secondary_noise), ex.noise(band_noise), ex.pos(ore_rand), ex.pos(gen.dfc.rand), ex.nb, gen.sea_level]
	var temps := PackedFloat64Array()
	for tv in gen.biomes.temperature:
		temps.append(tv)
	return [misc, ex.rints, ex.kids, ex.cints, ex.cfl, ex.bsets, ex.vints, ex.vfl, ex.noises, ex.poss, bands, temps]
