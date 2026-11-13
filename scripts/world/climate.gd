## Climate — multi-noise biome parameter lists and nearest-point lookup in 6D climate space.
## Overworld list re-implements Java's OverworldBiomeBuilder (code-defined, not in data packs; source D) incl.
## 1.21.4 Pale Garden. 26.2/26.3 additions whose placement is code-defined and unpublished are APPROXIMATED and
## labelled: Dappled Forest (cool forest variant), Sulfur Caves (hot/dry underground). Nether list = Java preset.
## Lookup: parameters quantised x10000 (Java Climate.quantizeCoord); fitness = sum of squared interval distances.
## Exactness strategy: per column, T/H/C/E/W are constant, so the best point per depth-interval group is found
## once, then each quart Y only compares ~4 groups (same argmin as brute force; ties resolved by list order).
## Contract: Climate.overworld() -> Climate; find(t,h,c,e,d,w) -> biome name; column(t,h,c,e,w) -> ColumnLookup.
class_name Climate
extends RefCounted

const Q := 10000.0

var names := PackedStringArray()      # biome per point
var pmin: Array = []                   # 6 x PackedInt64Array (T,H,C,E,D,W)
var pmax: Array = []
var offs := PackedInt64Array()
var groups: Dictionary = {}            # "dmin,dmax" -> group index
var group_lo := PackedInt64Array()
var group_hi := PackedInt64Array()
var point_group := PackedInt32Array()
# unique intervals per param for fast partial distances
var uniq: Array = []                   # 5 x Array of [lo, hi]
var uidx: Array = []                   # 5 x PackedInt32Array (per point)
var builder_note := ""


static func q(f: float) -> int:
	return int(f * Q)


func _init() -> void:
	for i in 6:
		pmin.append(PackedInt64Array())
		pmax.append(PackedInt64Array())


func add(t: Vector2, h: Vector2, c: Vector2, e: Vector2, d: Vector2, w: Vector2, offset: float, biome: String) -> void:
	var ps := [t, h, c, e, d, w]
	for i in 6:
		var v: Vector2 = ps[i]
		var a: PackedInt64Array = pmin[i]
		a.append(q(v.x))
		var b: PackedInt64Array = pmax[i]
		b.append(q(v.y))
	offs.append(q(offset))
	names.append(biome)


func finalize() -> void:
	var n := names.size()
	point_group.resize(n)
	for i in n:
		var key := "%d,%d" % [pmin[4][i], pmax[4][i]]
		if not groups.has(key):
			groups[key] = group_lo.size()
			group_lo.append(pmin[4][i])
			group_hi.append(pmax[4][i])
		point_group[i] = groups[key]
	uniq.clear()
	uidx.clear()
	for pi in [0, 1, 2, 3, 5]:
		var seen := {}
		var lst: Array = []
		var idx := PackedInt32Array()
		idx.resize(n)
		for i in n:
			var key2 := Vector2i(pmin[pi][i], pmax[pi][i])
			if not seen.has(key2):
				seen[key2] = lst.size()
				lst.append(key2)
			idx[i] = seen[key2]
		uniq.append(lst)
		uidx.append(idx)


static func _dist(lo: int, hi: int, v: int) -> int:
	var a := v - hi
	var b := lo - v
	if a > 0:
		return a
	if b > 0:
		return b
	return 0


## Per-column best point per depth group. Returns {best: PackedInt64Array partial, biome: PackedStringArray}.
func column(t: float, h: float, c: float, e: float, w: float) -> Dictionary:
	var tv := [q(t), q(h), q(c), q(e), q(w)]
	var dd: Array = []
	for k in 5:
		var lst: Array = uniq[k]
		var arr := PackedInt64Array()
		arr.resize(lst.size())
		for j in lst.size():
			var iv: Vector2i = lst[j]
			var dk := _dist(iv.x, iv.y, tv[k])
			arr[j] = dk * dk
		dd.append(arr)
	var g := group_lo.size()
	var best := PackedInt64Array()
	best.resize(g)
	best.fill(9223372036854775807)
	var bi := PackedInt32Array()
	bi.resize(g)
	bi.fill(-1)
	var d0: PackedInt64Array = dd[0]
	var d1: PackedInt64Array = dd[1]
	var d2: PackedInt64Array = dd[2]
	var d3: PackedInt64Array = dd[3]
	var d4: PackedInt64Array = dd[4]
	var u0: PackedInt32Array = uidx[0]
	var u1: PackedInt32Array = uidx[1]
	var u2: PackedInt32Array = uidx[2]
	var u3: PackedInt32Array = uidx[3]
	var u4: PackedInt32Array = uidx[4]
	for i in names.size():
		var s := d0[u0[i]] + d1[u1[i]] + d2[u2[i]] + d3[u3[i]] + d4[u4[i]] + offs[i] * offs[i]
		var gi := point_group[i]
		if s < best[gi]:
			best[gi] = s
			bi[gi] = i
	var bn := PackedStringArray()
	for gi in g:
		bn.append(names[bi[gi]] if bi[gi] >= 0 else "plains")
	return {"best": best, "biome": bn}


func pick(col: Dictionary, depth: float) -> String:
	var dv := q(depth)
	var best: PackedInt64Array = col["best"]
	var bm := 9223372036854775807
	var res := ""
	for gi in group_lo.size():
		if best[gi] == 9223372036854775807:
			continue
		var dk := _dist(group_lo[gi], group_hi[gi], dv)
		var s := best[gi] + dk * dk
		if s < bm:
			bm = s
			res = (col["biome"] as PackedStringArray)[gi]
	return res


func find(t: float, h: float, c: float, e: float, d: float, w: float) -> String:
	return pick(column(t, h, c, e, w), d)


# ------------------------------------------------------------------ Overworld builder (Java OverworldBiomeBuilder)

const TEMPS := [Vector2(-1.0, -0.45), Vector2(-0.45, -0.15), Vector2(-0.15, 0.2), Vector2(0.2, 0.55), Vector2(0.55, 1.0)]
const HUMS := [Vector2(-1.0, -0.35), Vector2(-0.35, -0.1), Vector2(-0.1, 0.1), Vector2(0.1, 0.3), Vector2(0.3, 1.0)]
const EROS := [Vector2(-1.0, -0.78), Vector2(-0.78, -0.375), Vector2(-0.375, -0.2225), Vector2(-0.2225, 0.05), Vector2(0.05, 0.45), Vector2(0.45, 0.55), Vector2(0.55, 1.0)]
const FULL := Vector2(-1.0, 1.0)
const MUSHROOM_C := Vector2(-1.2, -1.05)
const DEEP_OCEAN_C := Vector2(-1.05, -0.455)
const OCEAN_C := Vector2(-0.455, -0.19)
const COAST_C := Vector2(-0.19, -0.11)
const INLAND_C := Vector2(-0.11, 0.55)
const NEAR_C := Vector2(-0.11, 0.03)
const MID_C := Vector2(0.03, 0.3)
const FAR_C := Vector2(0.3, 1.0)

const OCEANS := [["deep_frozen_ocean", "deep_cold_ocean", "deep_ocean", "deep_lukewarm_ocean", "warm_ocean"],
	["frozen_ocean", "cold_ocean", "ocean", "lukewarm_ocean", "warm_ocean"]]
const MIDDLE := [["snowy_plains", "snowy_plains", "snowy_plains", "snowy_taiga", "taiga"],
	["plains", "plains", "forest", "taiga", "old_growth_spruce_taiga"],
	["flower_forest", "plains", "forest", "birch_forest", "dark_forest"],
	["savanna", "savanna", "forest", "jungle", "jungle"],
	["desert", "desert", "desert", "desert", "desert"]]
const MIDDLE_VAR := [["ice_spikes", "", "snowy_taiga", "", ""],
	["", "", "dappled_forest", "", "old_growth_pine_taiga"],
	["sunflower_plains", "", "", "old_growth_birch_forest", ""],
	["", "", "plains", "sparse_jungle", "bamboo_jungle"],
	["", "", "", "", ""]]
const PLATEAU := [["snowy_plains", "snowy_plains", "snowy_plains", "snowy_taiga", "snowy_taiga"],
	["meadow", "meadow", "forest", "taiga", "old_growth_spruce_taiga"],
	["meadow", "meadow", "meadow", "meadow", "pale_garden"],
	["savanna_plateau", "savanna_plateau", "forest", "forest", "jungle"],
	["badlands", "badlands", "badlands", "wooded_badlands", "wooded_badlands"]]
const PLATEAU_VAR := [["ice_spikes", "", "", "", ""],
	["cherry_grove", "", "meadow", "meadow", "old_growth_pine_taiga"],
	["cherry_grove", "cherry_grove", "forest", "birch_forest", ""],
	["", "", "", "", ""],
	["eroded_badlands", "eroded_badlands", "", "", ""]]
const SHATTERED := [["windswept_gravelly_hills", "windswept_gravelly_hills", "windswept_hills", "windswept_forest", "windswept_forest"],
	["windswept_gravelly_hills", "windswept_gravelly_hills", "windswept_hills", "windswept_forest", "windswept_forest"],
	["windswept_hills", "windswept_hills", "windswept_hills", "windswept_forest", "windswept_forest"],
	["", "", "", "", ""],
	["", "", "", "", ""]]


static func _span(a: Vector2, b: Vector2) -> Vector2:
	return Vector2(a.x, b.y)


func _surface(t: Vector2, h: Vector2, c: Vector2, e: Vector2, w: Vector2, b: String) -> void:
	add(t, h, c, e, Vector2(0, 0), w, 0.0, b)
	add(t, h, c, e, Vector2(1, 1), w, 0.0, b)


func _middle(i: int, j: int, w: Vector2) -> String:
	if w.y < 0.0:
		return MIDDLE[i][j]
	var v: String = MIDDLE_VAR[i][j]
	return MIDDLE[i][j] if v == "" else v


func _middle_or_badlands(i: int, j: int, w: Vector2) -> String:
	return _badlands(j, w) if i == 4 else _middle(i, j, w)


func _middle_badlands_slope(i: int, j: int, w: Vector2) -> String:
	return _slope(i, j, w) if i == 0 else _middle_or_badlands(i, j, w)


func _windswept_savanna(i: int, j: int, w: Vector2, b: String) -> String:
	return "windswept_savanna" if i > 1 and j < 4 and w.y >= 0.0 else b


func _shattered_coast(i: int, j: int, w: Vector2) -> String:
	var b := _middle(i, j, w) if w.y >= 0.0 else _beach(i, j)
	return _windswept_savanna(i, j, w, b)


func _beach(i: int, _j: int) -> String:
	if i == 0:
		return "snowy_beach"
	return "desert" if i == 4 else "beach"


func _badlands(i: int, w: Vector2) -> String:
	if i < 2:
		return "badlands" if w.y < 0.0 else "eroded_badlands"
	return "badlands" if i < 3 else "wooded_badlands"


func _plateau(i: int, j: int, w: Vector2) -> String:
	if w.y >= 0.0:
		var v: String = PLATEAU_VAR[i][j]
		if v != "":
			return v
	return PLATEAU[i][j]


func _peak(i: int, j: int, w: Vector2) -> String:
	if i <= 2:
		return "jagged_peaks" if w.y < 0.0 else "frozen_peaks"
	return "stony_peaks" if i == 3 else _badlands(j, w)


func _slope(i: int, j: int, w: Vector2) -> String:
	if i >= 3:
		return _plateau(i, j, w)
	return "snowy_slopes" if j <= 1 else "grove"


func _shattered(i: int, j: int, w: Vector2) -> String:
	var b: String = SHATTERED[i][j]
	return _middle(i, j, w) if b == "" else b


func _peaks(w: Vector2) -> void:
	for i in 5:
		var t: Vector2 = TEMPS[i]
		for j in 5:
			var h: Vector2 = HUMS[j]
			var r1 := _middle(i, j, w)
			var r2 := _middle_or_badlands(i, j, w)
			var r3 := _middle_badlands_slope(i, j, w)
			var r4 := _plateau(i, j, w)
			var r5 := _shattered(i, j, w)
			var r6 := _windswept_savanna(i, j, w, r5)
			var r7 := _peak(i, j, w)
			_surface(t, h, _span(COAST_C, FAR_C), EROS[0], w, r7)
			_surface(t, h, _span(COAST_C, NEAR_C), EROS[1], w, r3)
			_surface(t, h, _span(MID_C, FAR_C), EROS[1], w, r7)
			_surface(t, h, _span(COAST_C, NEAR_C), _span(EROS[2], EROS[3]), w, r1)
			_surface(t, h, _span(MID_C, FAR_C), EROS[2], w, r4)
			_surface(t, h, MID_C, EROS[3], w, r2)
			_surface(t, h, FAR_C, EROS[3], w, r4)
			_surface(t, h, _span(COAST_C, FAR_C), EROS[4], w, r1)
			_surface(t, h, _span(COAST_C, NEAR_C), EROS[5], w, r6)
			_surface(t, h, _span(MID_C, FAR_C), EROS[5], w, r5)
			_surface(t, h, _span(COAST_C, FAR_C), EROS[6], w, r1)


func _high(w: Vector2) -> void:
	for i in 5:
		var t: Vector2 = TEMPS[i]
		for j in 5:
			var h: Vector2 = HUMS[j]
			var r1 := _middle(i, j, w)
			var r2 := _middle_or_badlands(i, j, w)
			var r3 := _middle_badlands_slope(i, j, w)
			var r4 := _plateau(i, j, w)
			var r5 := _shattered(i, j, w)
			var r6 := _windswept_savanna(i, j, w, r1)
			var r7 := _slope(i, j, w)
			var r8 := _peak(i, j, w)
			_surface(t, h, COAST_C, _span(EROS[0], EROS[1]), w, r1)
			_surface(t, h, NEAR_C, EROS[0], w, r7)
			_surface(t, h, _span(MID_C, FAR_C), EROS[0], w, r8)
			_surface(t, h, NEAR_C, EROS[1], w, r3)
			_surface(t, h, _span(MID_C, FAR_C), EROS[1], w, r7)
			_surface(t, h, _span(COAST_C, NEAR_C), _span(EROS[2], EROS[3]), w, r1)
			_surface(t, h, _span(MID_C, FAR_C), EROS[2], w, r4)
			_surface(t, h, MID_C, EROS[3], w, r2)
			_surface(t, h, FAR_C, EROS[3], w, r4)
			_surface(t, h, _span(COAST_C, FAR_C), EROS[4], w, r1)
			_surface(t, h, _span(COAST_C, NEAR_C), EROS[5], w, r6)
			_surface(t, h, _span(MID_C, FAR_C), EROS[5], w, r5)
			_surface(t, h, _span(COAST_C, FAR_C), EROS[6], w, r1)


func _mid(w: Vector2) -> void:
	_surface(FULL, FULL, COAST_C, _span(EROS[0], EROS[2]), w, "stony_shore")
	_surface(_span(TEMPS[1], TEMPS[2]), FULL, _span(NEAR_C, FAR_C), EROS[6], w, "swamp")
	_surface(_span(TEMPS[3], TEMPS[4]), FULL, _span(NEAR_C, FAR_C), EROS[6], w, "mangrove_swamp")
	for i in 5:
		var t: Vector2 = TEMPS[i]
		for j in 5:
			var h: Vector2 = HUMS[j]
			var r1 := _middle(i, j, w)
			var r2 := _middle_or_badlands(i, j, w)
			var r3 := _middle_badlands_slope(i, j, w)
			var r4 := _shattered(i, j, w)
			var r5 := _plateau(i, j, w)
			var r6 := _beach(i, j)
			var r7 := _windswept_savanna(i, j, w, r1)
			var r8 := _shattered_coast(i, j, w)
			var r9 := _slope(i, j, w)
			_surface(t, h, _span(NEAR_C, FAR_C), EROS[0], w, r9)
			_surface(t, h, _span(NEAR_C, MID_C), EROS[1], w, r3)
			_surface(t, h, FAR_C, EROS[1], w, r9 if i == 0 else r5)
			_surface(t, h, NEAR_C, EROS[2], w, r1)
			_surface(t, h, MID_C, EROS[2], w, r2)
			_surface(t, h, FAR_C, EROS[2], w, r5)
			_surface(t, h, _span(COAST_C, NEAR_C), EROS[3], w, r1)
			_surface(t, h, _span(MID_C, FAR_C), EROS[3], w, r2)
			if w.y < 0.0:
				_surface(t, h, COAST_C, EROS[4], w, r6)
				_surface(t, h, _span(NEAR_C, FAR_C), EROS[4], w, r1)
			else:
				_surface(t, h, _span(COAST_C, FAR_C), EROS[4], w, r1)
			_surface(t, h, COAST_C, EROS[5], w, r8)
			_surface(t, h, NEAR_C, EROS[5], w, r7)
			_surface(t, h, _span(MID_C, FAR_C), EROS[5], w, r4)
			if w.y < 0.0:
				_surface(t, h, COAST_C, EROS[6], w, r6)
			else:
				_surface(t, h, COAST_C, EROS[6], w, r1)
			if i == 0:
				_surface(t, h, _span(NEAR_C, FAR_C), EROS[6], w, r1)


func _low(w: Vector2) -> void:
	_surface(FULL, FULL, COAST_C, _span(EROS[0], EROS[2]), w, "stony_shore")
	_surface(_span(TEMPS[1], TEMPS[2]), FULL, _span(NEAR_C, FAR_C), EROS[6], w, "swamp")
	_surface(_span(TEMPS[3], TEMPS[4]), FULL, _span(NEAR_C, FAR_C), EROS[6], w, "mangrove_swamp")
	for i in 5:
		var t: Vector2 = TEMPS[i]
		for j in 5:
			var h: Vector2 = HUMS[j]
			var r1 := _middle(i, j, w)
			var r2 := _middle_or_badlands(i, j, w)
			var r3 := _middle_badlands_slope(i, j, w)
			var r4 := _beach(i, j)
			var r5 := _windswept_savanna(i, j, w, r1)
			var r6 := _shattered_coast(i, j, w)
			_surface(t, h, NEAR_C, _span(EROS[0], EROS[1]), w, r2)
			_surface(t, h, _span(MID_C, FAR_C), _span(EROS[0], EROS[1]), w, r3)
			_surface(t, h, NEAR_C, _span(EROS[2], EROS[3]), w, r1)
			_surface(t, h, _span(MID_C, FAR_C), _span(EROS[2], EROS[3]), w, r2)
			_surface(t, h, COAST_C, _span(EROS[3], EROS[4]), w, r4)
			_surface(t, h, _span(NEAR_C, FAR_C), EROS[4], w, r1)
			_surface(t, h, COAST_C, EROS[5], w, r6)
			_surface(t, h, NEAR_C, EROS[5], w, r5)
			_surface(t, h, _span(MID_C, FAR_C), EROS[5], w, r1)
			_surface(t, h, COAST_C, EROS[6], w, r4)
			if i == 0:
				_surface(t, h, _span(NEAR_C, FAR_C), EROS[6], w, r1)


func _valleys(w: Vector2) -> void:
	var frozen: Vector2 = TEMPS[0]
	var unfrozen := _span(TEMPS[1], TEMPS[4])
	_surface(frozen, FULL, COAST_C, _span(EROS[0], EROS[1]), w, "stony_shore" if w.y < 0.0 else "frozen_river")
	_surface(unfrozen, FULL, COAST_C, _span(EROS[0], EROS[1]), w, "stony_shore" if w.y < 0.0 else "river")
	_surface(frozen, FULL, NEAR_C, _span(EROS[0], EROS[1]), w, "frozen_river")
	_surface(unfrozen, FULL, NEAR_C, _span(EROS[0], EROS[1]), w, "river")
	_surface(frozen, FULL, _span(COAST_C, FAR_C), _span(EROS[2], EROS[5]), w, "frozen_river")
	_surface(unfrozen, FULL, _span(COAST_C, FAR_C), _span(EROS[2], EROS[5]), w, "river")
	_surface(frozen, FULL, COAST_C, EROS[6], w, "frozen_river")
	_surface(unfrozen, FULL, COAST_C, EROS[6], w, "river")
	_surface(_span(TEMPS[1], TEMPS[2]), FULL, _span(INLAND_C, FAR_C), EROS[6], w, "swamp")
	_surface(_span(TEMPS[3], TEMPS[4]), FULL, _span(INLAND_C, FAR_C), EROS[6], w, "mangrove_swamp")
	_surface(frozen, FULL, _span(INLAND_C, FAR_C), EROS[6], w, "frozen_river")
	for i in 5:
		for j in 5:
			_surface(TEMPS[i], HUMS[j], _span(MID_C, FAR_C), _span(EROS[0], EROS[1]), w, _middle_or_badlands(i, j, w))


static func overworld() -> Climate:
	var c := Climate.new()
	c._surface(FULL, FULL, MUSHROOM_C, FULL, FULL, "mushroom_fields")
	for i in 5:
		c._surface(TEMPS[i], FULL, DEEP_OCEAN_C, FULL, FULL, OCEANS[0][i])
		c._surface(TEMPS[i], FULL, OCEAN_C, FULL, FULL, OCEANS[1][i])
	c._mid(Vector2(-1.0, -0.93333334))
	c._high(Vector2(-0.93333334, -0.7666667))
	c._peaks(Vector2(-0.7666667, -0.56666666))
	c._high(Vector2(-0.56666666, -0.4))
	c._mid(Vector2(-0.4, -0.26666668))
	c._low(Vector2(-0.26666668, -0.05))
	c._valleys(Vector2(-0.05, 0.05))
	c._low(Vector2(0.05, 0.26666668))
	c._mid(Vector2(0.26666668, 0.4))
	c._high(Vector2(0.4, 0.56666666))
	c._peaks(Vector2(0.56666666, 0.7666667))
	c._high(Vector2(0.7666667, 0.93333334))
	c._mid(Vector2(0.93333334, 1.0))
	# underground
	c.add(FULL, FULL, Vector2(0.8, 1.0), FULL, Vector2(0.2, 0.9), FULL, 0.0, "dripstone_caves")
	c.add(FULL, Vector2(0.7, 1.0), FULL, FULL, Vector2(0.2, 0.9), FULL, 0.0, "lush_caves")
	# APPROXIMATION (26.2 placement code-defined & unpublished): hot + dry underground
	c.add(Vector2(0.55, 1.0), Vector2(-1.0, -0.35), FULL, FULL, Vector2(0.2, 0.9), FULL, 0.0, "sulfur_caves")
	c.add(FULL, FULL, FULL, _span(EROS[0], EROS[1]), Vector2(1.1, 1.1), FULL, 0.0, "deep_dark")
	c.builder_note = "OverworldBiomeBuilder re-implementation (1.21.4 layout); dappled_forest & sulfur_caves placement approximated"
	c.finalize()
	return c


static func nether() -> Climate:
	var c := Climate.new()
	var z := Vector2(0, 0)
	c.add(z, z, z, z, z, z, 0.0, "nether_wastes")
	c.add(z, Vector2(-0.5, -0.5), z, z, z, z, 0.0, "soul_sand_valley")
	c.add(Vector2(0.4, 0.4), z, z, z, z, z, 0.0, "crimson_forest")
	c.add(z, Vector2(0.5, 0.5), z, z, z, z, 0.375, "warped_forest")
	c.add(Vector2(-0.5, -0.5), z, z, z, z, z, 0.175, "basalt_deltas")
	c.finalize()
	return c
