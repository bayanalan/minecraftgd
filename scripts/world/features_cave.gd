## FeaturesCave — speleothem (Java PointedDripstoneFeature), speleothem_cluster (DripstoneClusterFeature),
## large_dripstone (LargeDripstoneFeature + DripstoneUtils, Column.scan, WindOffsetter), root_system
## (RootSystemFeature), fossil (FossilFeature). Source D (Java recalled); 26.x generalises the base/pointed blocks
## (dripstone and sulfur spikes share these types) and adds level_test_distance/max_level_deviation to root_system
## (APPROXIMATE: flatness test reconstructed from the field names).
## Contract: compile(f, t, cfg, out) -> bool (handled); place(f, c, cf, p, t) -> bool or null.
class_name FeaturesCave
extends RefCounted

const UP := Vector3i(0, 1, 0)
const DOWN := Vector3i(0, -1, 0)
const THICK := ["tip_merge", "tip", "frustum", "middle", "base"]


static func compile(f: Features, t: String, c: Dictionary, out: Dictionary) -> bool:
	match t:
		"speleothem", "speleothem_cluster", "large_dripstone":
			_ids_common(f, out)
			var base_name := str(c.get("base_block", "minecraft:dripstone_block"))
			out["base"] = f._state(base_name)
			out["base_b"] = f.blocks.st_block[maxi(int(out["base"]), 0)]
			var pname := str(c.get("pointed_block", "minecraft:pointed_dripstone"))
			out["pointed_b"] = f.blocks.block_id(pname)
			var ps := {}
			for up in [true, false]:
				for th in THICK:
					for w in [false, true]:
						var s := f.blocks.state_of(pname, {"vertical_direction": "up" if up else "down", "thickness": th, "waterlogged": "true" if w else "false"})
						if s < 0:
							s = f._state(pname)
						ps[_pk(up, th, w)] = s
			out["ps"] = ps
			out["repl"] = FeaturesExt._ids(f, c.get("replaceable_blocks", "#minecraft:dripstone_replaceable_blocks"))
			out["cfg"] = c
			return true
		"root_system":
			_ids_common(f, out)
			out["tree"] = f._placed(c.get("feature", {}))
			out["allowed"] = f._pred(c.get("allowed_tree_position", {"type": "minecraft:true"}))
			out["root_prov"] = f._prov(c.get("root_state_provider", {}))
			out["hang_prov"] = f._prov(c.get("hanging_root_state_provider", {}))
			out["root_repl"] = FeaturesExt._ids(f, c.get("root_replaceable", "#minecraft:azalea_root_replaceable"))
			out["cfg"] = c
			return true
		"fossil":
			_ids_common(f, out)
			out["fossils"] = c.get("fossil_structures", [])
			out["overlays"] = c.get("overlay_structures", [])
			out["fproc"] = c.get("fossil_processors", "")
			out["oproc"] = c.get("overlay_processors", "")
			out["corners"] = int(c.get("max_empty_corners_allowed", 4))
			return true
	return false


static func _ids_common(f: Features, out: Dictionary) -> void:
	out["w"] = f.blocks.block_id("water")
	out["l"] = f.blocks.block_id("lava")
	out["ca"] = f.blocks.block_id("cave_air")
	out["va"] = f.blocks.block_id("void_air")
	out["stone"] = FeaturesExt._ids(f, "#minecraft:base_stone_overworld")


static func _pk(up: bool, th: String, w: bool) -> String:
	return ("u" if up else "d") + th + ("w" if w else "")


static func place(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, t: String):
	match t:
		"speleothem":
			return _speleothem(f, c, cf, p)
		"speleothem_cluster":
			return _cluster(f, c, cf, p)
		"large_dripstone":
			return _large(f, c, cf, p)
		"root_system":
			return _roots(f, c, cf, p)
		"fossil":
			return _fossil(f, c, cf, p)
	return null


# ------------------------------------------------------------------ DripstoneUtils

static func _bid(f: Features, st: int) -> int:
	return f.blocks.st_block[st] if st > 0 else 0


static func _is_air(cf: Dictionary, b: int) -> bool:
	return b == 0 or b == cf["ca"] or b == cf["va"]


static func _ew(f: Features, cf: Dictionary, st: int) -> bool:
	var b := _bid(f, st)
	return _is_air(cf, b) or b == cf["w"]


static func _ewl(f: Features, cf: Dictionary, st: int) -> bool:
	var b := _bid(f, st)
	return _is_air(cf, b) or b == cf["w"] or b == cf["l"]


static func _is_base(f: Features, cf: Dictionary, st: int) -> bool:
	var b := _bid(f, st)
	return b != 0 and (b == cf["base_b"] or (cf["repl"] as Dictionary).has(b))


static func _place_base(f: Features, c: Features.FCtx, cf: Dictionary, q: Vector3i) -> bool:
	if (cf["repl"] as Dictionary).has(_bid(f, f.get_block(c, q))):
		f.set_block(c, q, cf["base"])
		return true
	return false


## DripstoneUtils.growPointedDripstone: base -> middle... -> frustum -> tip, waterlogged where water was.
static func _grow(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, dir: int, h: int, merge: bool) -> void:
	if h <= 0 or not _is_base(f, cf, f.get_block(c, p - Vector3i(0, dir, 0))):
		return
	var seq: Array = []
	if h >= 3:
		seq.append("base")
		for i in h - 3:
			seq.append("middle")
	if h >= 2:
		seq.append("frustum")
	seq.append("tip_merge" if merge else "tip")
	var q := p
	var ps: Dictionary = cf["ps"]
	for th in seq:
		var w: bool = _bid(f, f.get_block(c, q)) == int(cf["w"])
		f.set_block(c, q, ps[_pk(dir > 0, th, w)])
		q.y += dir


static func _fs(f: Features, c: Features.FCtx, v) -> float:
	if v is int or v is float:
		return float(v)
	if not (v is Dictionary):
		return 0.0
	var r = c.r
	match str(v.get("type", "constant")).trim_prefix("minecraft:"):
		"constant":
			return float(v.get("value", 0.0))
		"uniform":
			var lo := float(v.get("min_inclusive", 0.0))
			return lo + r.next_float() * (float(v.get("max_exclusive", 1.0)) - lo)
		"clamped_normal":
			return clampf(float(v.get("mean", 0.0)) + f._gauss(r) * float(v.get("deviation", 1.0)), float(v.get("min", -1e9)), float(v.get("max", 1e9)))
		"trapezoid":
			var mn := float(v.get("min", 0.0))
			var rg := float(v.get("max", 0.0)) - mn
			var slope := (rg - float(v.get("plateau", 0.0))) / 2.0
			return mn + r.next_float() * (rg - slope) + r.next_float() * slope
	return 0.0


static func _imin(v) -> int:
	if v is int or v is float:
		return int(v)
	if v is Dictionary:
		match str(v.get("type", "")).trim_prefix("minecraft:"):
			"clamped":
				return maxi(int(v.get("min_inclusive", 0)), _imin(v.get("source", 0)))
			"constant":
				return int(v.get("value", 0))
		return int(v.get("min_inclusive", 0))
	return 0


static func _imax(v) -> int:
	if v is int or v is float:
		return int(v)
	if v is Dictionary:
		match str(v.get("type", "")).trim_prefix("minecraft:"):
			"clamped":
				return mini(int(v.get("max_inclusive", 0)), _imax(v.get("source", 0)))
			"constant":
				return int(v.get("value", 0))
		return int(v.get("max_inclusive", 0))
	return 0


static func _clamped_map(v: float, a: float, b: float, lo: float, hi: float) -> float:
	var tt := clampf((v - a) / (b - a), 0.0, 1.0) if b != a else 1.0
	return lo + tt * (hi - lo)


## Column.scan: [has_floor, floor_y, has_ceil, ceil_y], or [] when the origin is not inside the column.
static func _scan(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, rng: int, lava_edge: bool) -> Array:
	if not _ew(f, cf, f.get_block(c, p)):
		return []
	var out: Array = []
	for dir in [-1, 1]:
		var y := p.y
		var i := 1
		while i < rng:
			y += dir
			if not _ew(f, cf, f.get_block(c, Vector3i(p.x, y, p.z))):
				break
			i += 1
		var st := f.get_block(c, Vector3i(p.x, y, p.z))
		var edge: bool = (_is_base(f, cf, st) or _bid(f, st) == int(cf["l"])) if lava_edge else not _ew(f, cf, st)
		out.append(edge and y != p.y)
		out.append(y)
	return out


# ------------------------------------------------------------------ speleothem (PointedDripstoneFeature)

static func _speleothem(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var r = c.r
	var cfg: Dictionary = cf["cfg"]
	var can_up := _is_base(f, cf, f.get_block(c, p + UP))
	var can_down := _is_base(f, cf, f.get_block(c, p + DOWN))
	var dir := 0
	if can_up and can_down:
		dir = -1 if r.next_bool() else 1
	elif can_up:
		dir = -1
	elif can_down:
		dir = 1
	else:
		return false
	var root := p - Vector3i(0, dir, 0)
	_place_base(f, c, cf, root)
	for d in FeaturesExt.HORIZ:
		if r.next_float() > float(cfg.get("chance_of_directional_spread", 0.7)):
			continue
		var p2: Vector3i = root + d
		_place_base(f, c, cf, p2)
		if r.next_float() > float(cfg.get("chance_of_spread_radius2", 0.5)):
			continue
		var p3: Vector3i = p2 + FeaturesExt.DIRS6[r.next_int_bound(6)]
		_place_base(f, c, cf, p3)
		if r.next_float() > float(cfg.get("chance_of_spread_radius3", 0.5)):
			continue
		_place_base(f, c, cf, p3 + FeaturesExt.DIRS6[r.next_int_bound(6)])
	var h := 2 if r.next_float() < float(cfg.get("chance_of_taller_dripstone", 0.2)) and _ew(f, cf, f.get_block(c, p + Vector3i(0, dir, 0))) else 1
	_grow(f, c, cf, p, dir, h, false)
	return true


# ------------------------------------------------------------------ speleothem_cluster (DripstoneClusterFeature)

static func _cluster(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	if not _ew(f, cf, f.get_block(c, p)):
		return false
	var cfg: Dictionary = cf["cfg"]
	var height := f.sample_int(c, cfg.get("height", 6))
	var wet := _fs(f, c, cfg.get("wetness", 0.0))
	var dens := _fs(f, c, cfg.get("density", 0.5))
	var rx := f.sample_int(c, cfg.get("radius", 4))
	var rz := f.sample_int(c, cfg.get("radius", 4))
	var edge_max := float(cfg.get("max_distance_from_edge_affecting_chance_of_speleothem", cfg.get("max_distance_from_edge_affecting_chance_of_dripstone_column", 3)))
	var chance_far := float(cfg.get("chance_of_speleothem_at_max_distance_from_center", cfg.get("chance_of_dripstone_column_at_max_distance_from_center", 0.1)))
	for dx in range(-rx, rx + 1):
		for dz in range(-rz, rz + 1):
			var k := mini(rx - absi(dx), rz - absi(dz))
			var ch := _clamped_map(float(k), 0.0, edge_max, chance_far, 1.0)
			_cluster_column(f, c, cf, p + Vector3i(dx, 0, dz), dx, dz, wet, ch, height, dens, cfg)
	return true


static func _cluster_column(f: Features, c: Features.FCtx, cf: Dictionary, q: Vector3i, dx: int, dz: int, wet: float, chance: float, height: int, dens: float, cfg: Dictionary) -> void:
	var r = c.r
	var col := _scan(f, c, cf, q, int(cfg.get("floor_to_ceiling_search_range", 12)), false)
	if col.is_empty():
		return
	var has_floor: bool = col[0]
	var floor_y: int = col[1]
	var has_ceil: bool = col[2]
	var ceil_y: int = col[3]
	if not has_ceil and not has_floor:
		return
	var col_h := ceil_y - floor_y - 1 if has_ceil and has_floor else -1
	var pool := r.next_float() < wet
	var f_has := has_floor
	var f_y := floor_y
	if pool and has_floor and _can_pool(f, c, cf, Vector3i(q.x, floor_y, q.z)):
		f.set_block(c, Vector3i(q.x, floor_y, q.z), f.blocks.default_state("water"))
		f_y = floor_y - 1
	var thick_v = cfg.get("speleothem_block_layer_thickness", cfg.get("dripstone_block_layer_thickness", 3))
	var ch := 0
	if has_ceil and r.next_double() < chance and _bid(f, f.get_block(c, Vector3i(q.x, ceil_y, q.z))) != cf["l"]:
		var th := f.sample_int(c, thick_v)
		_replace_layer(f, c, cf, Vector3i(q.x, ceil_y, q.z), th, 1)
		var mh := mini(height, ceil_y - f_y) if f_has else height
		ch = _drip_height(f, c, dx, dz, dens, mh, cfg)
	var fh := 0
	if f_has and r.next_double() < chance and _bid(f, f.get_block(c, Vector3i(q.x, f_y, q.z))) != cf["l"]:
		var th2 := f.sample_int(c, thick_v)
		_replace_layer(f, c, cf, Vector3i(q.x, f_y, q.z), th2, -1)
		if has_ceil:
			var dev := int(cfg.get("max_stalagmite_stalactite_height_diff", 1))
			fh = maxi(0, ch + FeaturesExt._mth_next(r, -dev, dev))
		else:
			fh = _drip_height(f, c, dx, dz, dens, height, cfg)
	var ch2 := ch
	var fh2 := fh
	if has_ceil and f_has and ceil_y - ch <= f_y + fh:
		var lo := maxi(ceil_y - ch, f_y + 1)
		var hi := mini(f_y + fh, ceil_y - 1)
		var mid := FeaturesExt._mth_next(r, lo, hi + 1)
		ch2 = ceil_y - mid
		fh2 = mid - 1 - f_y
	var merge := r.next_bool() and ch2 > 0 and fh2 > 0 and col_h >= 0 and ch2 + fh2 == col_h
	if has_ceil:
		_grow(f, c, cf, Vector3i(q.x, ceil_y - 1, q.z), -1, ch2, merge)
	if f_has:
		_grow(f, c, cf, Vector3i(q.x, f_y + 1, q.z), 1, fh2, merge)


static func _drip_height(f: Features, c: Features.FCtx, dx: int, dz: int, dens: float, max_h: int, cfg: Dictionary) -> int:
	var r = c.r
	if r.next_float() > dens:
		return 0
	var mean := _clamped_map(float(absi(dx) + absi(dz)), 0.0, float(cfg.get("max_distance_from_center_affecting_height_bias", 8)), max_h / 2.0, 0.0)
	return int(clampf(mean + f._gauss(r) * float(cfg.get("height_deviation", 3)), 0.0, float(max_h)))


static func _replace_layer(f: Features, c: Features.FCtx, cf: Dictionary, q: Vector3i, n: int, dir: int) -> void:
	var m := q
	for i in n:
		if not _place_base(f, c, cf, m):
			return
		m.y += dir


static func _can_pool(f: Features, c: Features.FCtx, cf: Dictionary, q: Vector3i) -> bool:
	var b := _bid(f, f.get_block(c, q))
	if b == cf["w"] or b == cf["base_b"] or b == cf["pointed_b"]:
		return false
	if _bid(f, f.get_block(c, q + UP)) == cf["w"]:
		return false
	for d in FeaturesExt.HORIZ:
		if not _adj_water_ok(f, cf, f.get_block(c, q + d)):
			return false
	return _adj_water_ok(f, cf, f.get_block(c, q + DOWN))


static func _adj_water_ok(f: Features, cf: Dictionary, st: int) -> bool:
	var b := _bid(f, st)
	return (cf["stone"] as Dictionary).has(b) or b == cf["w"]


# ------------------------------------------------------------------ large_dripstone (LargeDripstoneFeature)

class Drip:
	var root: Vector3i
	var up: bool
	var radius: int
	var blunt: float
	var scale: float

	func height_at(rr: float) -> int:
		var x := maxf(rr, blunt) / float(radius) * 0.384
		var h := scale * (0.75 * pow(x, 4.0 / 3.0) - pow(x, 2.0 / 3.0) - log(x) / 3.0)
		return int(maxf(h, 0.0) / 0.384 * radius)


static func _wind(wind: Array, oy: int, q: Vector3i) -> Vector3i:
	if wind.is_empty():
		return q
	var dy := oy - q.y
	return q + Vector3i(floori(wind[0] * dy), 0, floori(wind[1] * dy))


static func _embedded(f: Features, c: Features.FCtx, cf: Dictionary, q: Vector3i, radius: int) -> bool:
	if _ewl(f, cf, f.get_block(c, q)):
		return false
	var step := 6.0 / radius
	var a := 0.0
	while a < TAU:
		if _ewl(f, cf, f.get_block(c, q + Vector3i(int(cos(a) * radius), 0, int(sin(a) * radius)))):
			return false
		a += step
	return true


static func _move_back(f: Features, c: Features.FCtx, cf: Dictionary, d: Drip, wind: Array, oy: int) -> bool:
	while d.radius > 1:
		var m := d.root
		var n := mini(10, d.height_at(0.0))
		for i in n:
			if _bid(f, f.get_block(c, m)) == cf["l"]:
				return false
			if _embedded(f, c, cf, _wind(wind, oy, m), d.radius):
				d.root = m
				return true
			m.y += -1 if d.up else 1
		d.radius /= 2
	return false


static func _place_drip(f: Features, c: Features.FCtx, cf: Dictionary, d: Drip, wind: Array, oy: int) -> void:
	var r = c.r
	for dx in range(-d.radius, d.radius + 1):
		for dz in range(-d.radius, d.radius + 1):
			var dist := sqrt(float(dx * dx + dz * dz))
			if dist > d.radius:
				continue
			var h := d.height_at(dist)
			if h <= 0:
				continue
			if r.next_float() < 0.2:
				h = int(h * (0.8 + r.next_float() * 0.2))
			var m := d.root + Vector3i(dx, 0, dz)
			var placed := false
			var max_y := f.height(c, "WORLD_SURFACE_WG", m.x, m.z) if d.up else 2147483647
			for i in h:
				if m.y >= max_y:
					break
				var q := _wind(wind, oy, m)
				var st := f.get_block(c, q)
				if _ewl(f, cf, st):
					placed = true
					f.set_block(c, q, cf["base"])
				elif placed and (cf["stone"] as Dictionary).has(_bid(f, st)):
					break
				m.y += 1 if d.up else -1


static func _large(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var r = c.r
	var cfg: Dictionary = cf["cfg"]
	if not _ew(f, cf, f.get_block(c, p)):
		return false
	var col := _scan(f, c, cf, p, int(cfg.get("floor_to_ceiling_search_range", 30)), true)
	if col.is_empty() or not col[0] or not col[2]:
		return false
	var h: int = int(col[3]) - int(col[1]) - 1
	if h < 4:
		return false
	var crv = cfg.get("column_radius", 3)
	var max_r := clampi(int(h * float(cfg.get("max_column_radius_to_cave_height_ratio", 0.33))), _imin(crv), _imax(crv))
	var radius := FeaturesExt._mth_next(r, _imin(crv), max_r)
	var top := Drip.new()
	top.root = Vector3i(p.x, int(col[3]) - 1, p.z)
	top.up = false
	top.radius = radius
	top.blunt = _fs(f, c, cfg.get("stalactite_bluntness", 0.5))
	top.scale = _fs(f, c, cfg.get("height_scale", 1.0))
	var bot := Drip.new()
	bot.root = Vector3i(p.x, int(col[1]) + 1, p.z)
	bot.up = true
	bot.radius = radius
	bot.blunt = _fs(f, c, cfg.get("stalagmite_bluntness", 0.5))
	bot.scale = _fs(f, c, cfg.get("height_scale", 1.0))
	var wind: Array = []
	var mr := float(cfg.get("min_radius_for_wind", 4))
	var mb := float(cfg.get("min_bluntness_for_wind", 0.6))
	if top.radius >= mr and top.blunt >= mb and bot.radius >= mr and bot.blunt >= mb:
		var spd := _fs(f, c, cfg.get("wind_speed", 0.0))
		var ang: float = r.next_float() * PI
		wind = [cos(ang) * spd, sin(ang) * spd]
	var a := _move_back(f, c, cf, top, wind, p.y)
	var b := _move_back(f, c, cf, bot, wind, p.y)
	if a:
		_place_drip(f, c, cf, top, wind, p.y)
	if b:
		_place_drip(f, c, cf, bot, wind, p.y)
	return true


# ------------------------------------------------------------------ root_system (RootSystemFeature)

static func _roots(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	if not _is_air(cf, _bid(f, f.get_block(c, p))):
		return false
	var r = c.r
	var cfg: Dictionary = cf["cfg"]
	var need := int(cfg.get("required_vertical_space_for_tree", 3))
	var water_ok := int(cfg.get("allowed_vertical_water_for_tree", 2))
	var test_d := int(cfg.get("level_test_distance", 0))
	var dev := int(cfg.get("max_level_deviation", 0))
	var m := p
	for i in int(cfg.get("root_column_max_height", 100)):
		m.y += 1
		if not f.test(c, cf["allowed"], m) or not _tree_space(f, c, cf, m, need, water_ok):
			continue
		var below := f.get_block(c, m + DOWN)
		if _bid(f, below) == cf["l"] or below <= 0 or (f.blocks.st_flags[below] & BlockRegistry.F_COLLIDE) == 0:
			return false
		if test_d > 0 and not _level_ok(f, c, cf, m, test_d, dev):
			continue
		if f._sub(c, cf["tree"], m):
			for y in range(p.y, p.y + i):
				_rooted_dirt(f, c, cf, p.x, y, p.z)
			_hanging(f, c, cf, p)
			return true
	return true


static func _tree_space(f: Features, c: Features.FCtx, cf: Dictionary, m: Vector3i, need: int, water_ok: int) -> bool:
	for i in range(1, need + 1):
		var st := f.get_block(c, m + Vector3i(0, i, 0))
		var b := _bid(f, st)
		if _is_air(cf, b):
			continue
		if i + 1 <= water_ok and b == cf["w"]:
			continue
		return false
	return true


## Ground around the tree position may deviate at most `dev` blocks at `dist` in the four horizontal directions.
static func _level_ok(f: Features, c: Features.FCtx, cf: Dictionary, m: Vector3i, dist: int, dev: int) -> bool:
	for d in FeaturesExt.HORIZ:
		var q: Vector3i = m + d * dist
		var found := false
		for dy in range(-dev, dev + 1):
			var g := f.get_block(c, q + Vector3i(0, dy - 1, 0))
			var a := f.get_block(c, q + Vector3i(0, dy, 0))
			if g > 0 and (f.blocks.st_flags[g] & BlockRegistry.F_COLLIDE) != 0 and _ew(f, cf, a):
				found = true
				break
		if not found:
			return false
	return true


static func _rooted_dirt(f: Features, c: Features.FCtx, cf: Dictionary, x: int, y: int, z: int) -> void:
	var r = c.r
	var rad := maxi(1, int(cf["cfg"].get("root_radius", 3)))
	for i in int(cf["cfg"].get("root_placement_attempts", 20)):
		var q := Vector3i(x + r.next_int_bound(rad) - r.next_int_bound(rad), y, z + r.next_int_bound(rad) - r.next_int_bound(rad))
		if (cf["root_repl"] as Dictionary).has(_bid(f, f.get_block(c, q))):
			f.set_block(c, q, f.provide(c, cf["root_prov"], q))


static func _hanging(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> void:
	var r = c.r
	var rad := maxi(1, int(cf["cfg"].get("hanging_root_radius", 3)))
	var vs := maxi(1, int(cf["cfg"].get("hanging_roots_vertical_span", 2)))
	for i in int(cf["cfg"].get("hanging_root_placement_attempts", 20)):
		var q := o + Vector3i(r.next_int_bound(rad) - r.next_int_bound(rad), r.next_int_bound(vs) - r.next_int_bound(vs), r.next_int_bound(rad) - r.next_int_bound(rad))
		if not _is_air(cf, _bid(f, f.get_block(c, q))):
			continue
		var s := f.provide(c, cf["hang_prov"], q)
		var above := f.get_block(c, q + UP)
		if above > 0 and (f.blocks.st_flags[above] & BlockRegistry.F_FULL_SHAPE) != 0:
			f.set_block(c, q, s)


# ------------------------------------------------------------------ fossil (FossilFeature)

static func _fossil(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var fl: Array = cf["fossils"]
	if fl.is_empty():
		return false
	var r = c.r
	var rot: int = r.next_int_bound(4)
	var idx: int = r.next_int_bound(fl.size())
	var fos := StructureTemplate.get_template(str(fl[idx]))
	if fos == null:
		return false
	var ovl: Array = cf["overlays"]
	var ov: StructureTemplate = StructureTemplate.get_template(str(ovl[idx])) if idx < ovl.size() else null
	var ch := c.origin_chunk
	var cmin := Vector3i(ch.cx * 16 - 16, f.gen.gen_min_y, ch.cz * 16 - 16)
	var cmax := Vector3i(ch.cx * 16 + 31, f.gen.gen_min_y + f.gen.gen_depth - 1, ch.cz * 16 + 31)
	var sz := fos.size if rot % 2 == 0 else Vector3i(fos.size.z, fos.size.y, fos.size.x)
	var corner := p + Vector3i(-sz.x / 2, 0, -sz.z / 2)
	var y := p.y
	for x in sz.x:
		for z in sz.z:
			y = mini(y, f.height(c, "OCEAN_FLOOR_WG", corner.x + x, corner.z + z))
	var depth := maxi(y - 15 - r.next_int_bound(10), f.gen.gen_min_y + 10)
	var i := fos.size.x - 1
	var j := fos.size.z - 1
	var pos := Vector3i(corner.x, depth, corner.z)
	match rot:
		3:
			pos += Vector3i(0, 0, i)
		1:
			pos += Vector3i(j, 0, 0)
		2:
			pos += Vector3i(i, 0, j)
	var bb := fos.box(pos, rot)
	var empty := 0
	for cx2 in [bb[0].x, bb[1].x]:
		for cy in [bb[0].y, bb[1].y]:
			for cz2 in [bb[0].z, bb[1].z]:
				var st := f.get_block(c, Vector3i(cx2, cy, cz2))
				var b := _bid(f, st)
				if _is_air(cf, b) or b == cf["l"] or b == cf["w"]:
					empty += 1
	if empty > int(cf["corners"]):
		return false
	var procs: Array = []
	var oprocs: Array = []
	if f.gen.structures != null:
		procs = f.gen.structures.compile_processors(cf["fproc"])
		oprocs = f.gen.structures.compile_processors(cf["oproc"])
	fos.place(f, c, pos, rot, procs, true, false, cmin, cmax)
	if ov != null:
		ov.place(f, c, pos, rot, oprocs, true, false, cmin, cmax)
	return true
