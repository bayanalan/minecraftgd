## FeaturesExt — additional 26.3 feature types: Nether (netherrack_replace_blobs, delta_feature, huge_fungus,
## stepped_column_cluster, single_block_pillar, projected_random_patchy_square, random_neighbor_spread), composite
## (overlay), End (end_island, end_spike, chorus_plant, end_gateway, end_platform, end_podium), ocean/ice
## (coral_tree/claw, underwater_magma, blue_ice, iceberg, spike, block_blob, vines).
## Sources: Java feature classes recalled (class D) for types that existed before 26.x; the new generalised 26.x
## types (overlay, single_block_pillar, projected_random_patchy_square, random_neighbor_spread,
## stepped_column_cluster, spike, block_blob) are reconstructed from their JSON fields and the Java features they
## replaced (class E, APPROXIMATE — recorded in PARITY_MATRIX).
## Contract: compile(f, t, cfg, out) fills `out`; place(f, c, cf, p) -> bool, or null when the type is unknown.
class_name FeaturesExt
extends RefCounted

const DIRS6 := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const HORIZ := [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]   # N, E, S, W (Direction.Plane.HORIZONTAL)


static func compile(f: Features, t: String, c: Dictionary, out: Dictionary) -> void:
	match t:
		"overlay":
			var fs: Array = []
			var raw = c.get("features", [])
			if raw is Dictionary:
				raw = [raw]
			for e in raw:
				fs.append(f._placed(e))
			out["fs"] = fs
		"single_block_pillar":
			out["block"] = f._prov(c.get("block", {}))
			out["can_replace"] = f._pred(c.get("can_replace", {"type": "minecraft:true"}))
			out["dir"] = Vector3i(0, -1, 0) if str(c.get("direction", "down")) == "down" else Vector3i(0, 1, 0)
			out["chance"] = float(c.get("chance_to_continue", 1.0))
			out["cap"] = f._placed(c["cap_feature"]) if c.has("cap_feature") else {}
		"projected_random_patchy_square":
			out["block"] = f._prov(c.get("block", {}))
			out["size"] = int(c.get("size", 3))
			out["proj"] = int(c.get("max_projection_height", 3))
			out["through"] = f._pred(c.get("project_through", {"type": "minecraft:true"}))
		"random_neighbor_spread":
			out["block"] = f._prov(c.get("block", {}))
			out["attempts"] = int(c.get("attempts", 64))
			out["xz"] = c.get("xz_offset", 0)
			out["y"] = c.get("y_offset", 0)
			out["can_replace"] = f._pred(c.get("can_replace", {"type": "minecraft:true"}))
			out["accepted"] = _ids(f, c.get("accepted_neighbors", []))
		"stepped_column_cluster":
			out["block"] = f._prov(c.get("block", {}))
			out["can_replace"] = f._pred(c.get("can_replace", {"type": "minecraft:true"}))
			out["continue"] = f._pred(c.get("continue_through", {"type": "minecraft:not", "predicate": {"type": "minecraft:true"}}))
			out["cannot_on"] = _ids(f, c.get("cannot_place_on", []))
			out["cluster_reach"] = int(c.get("cluster_reach", 5))
			out["column_count"] = int(c.get("column_count", 50))
			out["column_reach"] = c.get("column_reach", 1)
			out["height"] = c.get("height", 1)
		"netherrack_replace_blobs":
			out["target"] = f.blocks.st_block[maxi(f._state(c.get("target", "minecraft:netherrack")), 0)]
			out["state"] = f._state(c.get("state", "minecraft:basalt"))
			out["radius"] = c.get("radius", 3)
		"delta_feature":
			out["contents"] = f._state(c.get("contents", "minecraft:lava"))
			out["rim"] = f._state(c.get("rim", "minecraft:magma_block"))
			out["size"] = c.get("size", 3)
			out["rim_size"] = c.get("rim_size", 0)
		"huge_fungus":
			out["stem"] = f._state(c.get("stem_state", "minecraft:crimson_stem"))
			out["hat"] = f._state(c.get("hat_state", "minecraft:nether_wart_block"))
			out["decor"] = f._state(c.get("decor_state", "minecraft:shroomlight"))
			out["base"] = f.blocks.st_block[maxi(f._state(c.get("valid_base_block", "minecraft:crimson_nylium")), 0)]
			out["replace"] = f._pred(c.get("replaceable_blocks", {"type": "minecraft:not", "predicate": {"type": "minecraft:true"}}))
			out["planted"] = bool(c.get("planted", false))
		"coral_tree", "coral_claw", "coral_mushroom":
			out["coral"] = f._placed(c.get("feature", {}))
		"spike":
			out["state"] = f._state(c.get("state", "minecraft:packed_ice"))
			out["on"] = f._pred(c.get("can_place_on", {"type": "minecraft:true"}))
			out["can_replace"] = f._pred(c.get("can_replace", {"type": "minecraft:true"}))
		"block_blob":
			out["state"] = f._state(c.get("state", "minecraft:mossy_cobblestone"))
			out["on"] = f._pred(c.get("can_place_on", {"type": "minecraft:true"}))
		"iceberg":
			out["state"] = f._state(c.get("state", "minecraft:packed_ice"))
		"end_gateway":
			out["exit"] = c.get("exit", null)
			out["exact"] = bool(c.get("exact", false))
		"template":
			# 26.x TemplateFeature (desert well, sulfur springs): a weighted template, its processors
			var ts: Array = []
			for e in c.get("templates", []):
				if e is Dictionary:
					var dd = e.get("data", e)
					var tid := str(dd.get("id", "") if dd is Dictionary else dd).trim_prefix("minecraft:")
					ts.append([maxi(1, int(e.get("weight", 1))), tid])
			out["ts"] = ts
			out["procs"] = f.gen.structures.compile_processors(c.get("processors", [])) if f.gen.get("structures") != null else []
		"underwater_magma":
			out["range"] = int(c.get("floor_search_range", 5))
			out["radius"] = int(c.get("placement_radius_around_floor", 1))
			out["prob"] = float(c.get("placement_probability_per_valid_position", 0.5))


static func _ids(f: Features, v) -> Dictionary:
	var out := {}
	if v is String:
		if v.begins_with("#"):
			for b in Tags.blocks(v.substr(1).trim_prefix("minecraft:")):
				var bid := f.blocks.block_id(b)
				if bid >= 0:
					out[bid] = true
			return out
		v = [v]
	if v is Array:
		for b in v:
			var bid2 := f.blocks.block_id(str(b))
			if bid2 >= 0:
				out[bid2] = true
	return out


## Returns true/false when handled, null when the type is not implemented here.
static func place(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, t: String):
	match t:
		"overlay":
			var any := false
			for pf in cf["fs"]:
				if f._sub(c, pf, p):
					any = true
			return any
		"single_block_pillar":
			return _pillar(f, c, cf, p)
		"projected_random_patchy_square":
			return _patchy_square(f, c, cf, p)
		"random_neighbor_spread":
			return _neighbor_spread(f, c, cf, p)
		"stepped_column_cluster":
			return _columns(f, c, cf, p)
		"netherrack_replace_blobs":
			return _replace_blobs(f, c, cf, p)
		"delta_feature":
			return _delta(f, c, cf, p)
		"huge_fungus":
			return _fungus(f, c, cf, p)
		"end_island":
			return _end_island(f, c, p)
		"end_spike":
			return _end_spikes(f, c, p)
		"chorus_plant":
			return _chorus(f, c, p)
		"end_gateway":
			end_gateway(f, c, p, cf.get("exit"), bool(cf.get("exact", false)))
			return true
		"end_platform":
			end_platform(f, c, p)
			return true
		"end_podium":
			end_podium(f, c, p, false)
			return true
		"coral_tree", "coral_claw", "coral_mushroom":
			return _coral(f, c, cf, p, t)
		"template":
			return _template(f, c, cf, p)
		"underwater_magma":
			return _underwater_magma(f, c, cf, p)
		"blue_ice":
			return _blue_ice(f, c, p)
		"spike":
			return _spike(f, c, cf, p)
		"block_blob":
			return _blob(f, c, cf, p)
		"iceberg":
			return _iceberg(f, c, cf, p)
		"vines":
			return _vines(f, c, p)
		"void_start_platform":
			for dz in range(-8, 9):
				for dx in range(-8, 9):
					if maxi(absi(dx), absi(dz)) <= 1:
						f.set_block(c, p + Vector3i(dx, -1, dz), f.blocks.default_state("stone" if dx == 0 and dz == 0 else "cobblestone"))
			return true
	return null


static func _air(f: Features, c: Features.FCtx, p: Vector3i) -> bool:
	var s := f.get_block(c, p)
	return s == 0 or (s > 0 and f.blocks.name_of(s).ends_with("air"))


static func _is(f: Features, c: Features.FCtx, p: Vector3i, block_id: int) -> bool:
	var s := f.get_block(c, p)
	return s >= 0 and f.blocks.st_block[s] == block_id


static func _mth_next(r, a: int, b: int) -> int:
	return a if a >= b else int(r.next_int_bound(b - a + 1)) + a


static func _in_world(f: Features, y: int) -> bool:
	return y >= f.gen.gen_min_y and y < f.gen.gen_min_y + f.gen.gen_depth


# ------------------------------------------------------------------ BlockPos.withinManhattan (Java iteration order)

static func within_manhattan(center: Vector3i, rx: int, ry: int, rz: int) -> Array:
	var out: Array = []
	var total := rx + ry + rz
	for depth in total + 1:
		var max_x := mini(rx, depth)
		for x in range(-max_x, max_x + 1):
			var max_y := mini(ry, depth - absi(x))
			for y in range(-max_y, max_y + 1):
				var m := depth - absi(x) - absi(y)
				if m <= rz:
					out.append(center + Vector3i(x, y, m))
					if m != 0:
						out.append(center + Vector3i(x, y, -m))
	return out


# ------------------------------------------------------------------ Nether

static func _replace_blobs(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var target: int = cf["target"]
	var p := Vector3i(o.x, clampi(o.y, f.gen.gen_min_y + 1, f.gen.gen_min_y + f.gen.gen_depth - 1), o.z)
	var found := false
	while p.y > f.gen.gen_min_y + 1:
		if _is(f, c, p, target):
			found = true
			break
		p.y -= 1
	if not found:
		return false
	var i := f.sample_int(c, cf["radius"])
	var j := f.sample_int(c, cf["radius"])
	var k := f.sample_int(c, cf["radius"])
	var l := maxi(i, maxi(j, k))
	var any := false
	var st: int = cf["state"]
	for dx in range(-i, i + 1):
		for dy in range(-j, j + 1):
			for dz in range(-k, k + 1):
				if absi(dx) + absi(dy) + absi(dz) > l:
					continue
				var q := p + Vector3i(dx, dy, dz)
				if _is(f, c, q, target):
					f.set_block(c, q, st)
					any = true
	return any


static func _delta_clear(f: Features, c: Features.FCtx, p: Vector3i, contents_block: int, bad: Dictionary) -> bool:
	var s := f.get_block(c, p)
	if s < 0:
		return false
	var b := f.blocks.st_block[s]
	if b == contents_block or bad.has(b):
		return false
	for d in DIRS6:
		var air := _air(f, c, p + d)
		if (air and d != Vector3i(0, 1, 0)) or (not air and d == Vector3i(0, 1, 0)):
			return false
	return true


static func _delta(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var r := c.r
	var bad := {}
	for n in ["bedrock", "nether_bricks", "nether_brick_fence", "nether_brick_stairs", "nether_wart", "chest", "spawner"]:
		var bid := f.blocks.block_id(n)
		if bid >= 0:
			bad[bid] = true
	var any := false
	var big := r.next_double() < 0.9
	var i := f.sample_int(c, cf["rim_size"]) if big else 0
	var j := f.sample_int(c, cf["rim_size"]) if big else 0
	var rim := big and i != 0 and j != 0
	var k := f.sample_int(c, cf["size"])
	var l := f.sample_int(c, cf["size"])
	var m := maxi(k, l)
	var contents: int = cf["contents"]
	var cb := f.blocks.st_block[maxi(contents, 0)]
	for p: Vector3i in within_manhattan(o, k, 0, l):
		if absi(p.x - o.x) + absi(p.y - o.y) + absi(p.z - o.z) > m:
			break
		if _delta_clear(f, c, p, cb, bad):
			if rim:
				any = true
				f.set_block(c, p, cf["rim"])
			var q := p + Vector3i(i, 0, j)
			if _delta_clear(f, c, q, cb, bad):
				any = true
				f.set_block(c, q, contents)
	return any


static func _columns(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var r := c.r
	if not _col_can_place(f, c, cf, o):
		return false
	var j := f.sample_int(c, cf["height"])
	var reach: int = cf["cluster_reach"]
	var k := mini(j, reach)
	var any := false
	for n in int(cf["column_count"]):
		var x := o.x - k + r.next_int_bound(2 * k + 1)
		var _y := o.y + r.next_int_bound(1)
		var z := o.z - k + r.next_int_bound(2 * k + 1)
		var p := Vector3i(x, o.y, z)
		var m := j - (absi(x - o.x) + absi(z - o.z))
		if m >= 0:
			if _col_place(f, c, cf, p, m, f.sample_int(c, cf["column_reach"])):
				any = true
	return any


static func _col_can_place(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	if not f.test(c, cf["can_replace"], p):
		return false
	var below := f.get_block(c, p + Vector3i(0, -1, 0))
	return below > 0 and not _air(f, c, p + Vector3i(0, -1, 0)) and not (cf["cannot_on"] as Dictionary).has(f.blocks.st_block[below])


static func _col_place(f: Features, c: Features.FCtx, cf: Dictionary, pos: Vector3i, distance: int, reach: int) -> bool:
	var any := false
	var cannot: Dictionary = cf["cannot_on"]
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var p := pos + Vector3i(dx, 0, dz)
			var i := absi(dx) + absi(dz)
			var q := Vector3i(0, -99999, 0)
			if f.test(c, cf["can_replace"], p):
				# findSurface: walk down up to i steps for a placeable spot
				var s := p
				var n := i
				while s.y > f.gen.gen_min_y + 1 and n > 0:
					n -= 1
					if _col_can_place(f, c, cf, s):
						q = s
						break
					s.y -= 1
			else:
				# findAir: walk up up to i steps for air
				var s2 := p
				var n2 := i
				while s2.y < f.gen.gen_min_y + f.gen.gen_depth and n2 > 0:
					n2 -= 1
					var st := f.get_block(c, s2)
					if st >= 0 and cannot.has(f.blocks.st_block[st]):
						break
					if _air(f, c, s2):
						q = s2
						break
					s2.y += 1
			if q.y == -99999:
				continue
			var hgt := distance - i / 2
			var mpos := q
			while hgt >= 0:
				if f.test(c, cf["can_replace"], mpos):
					f.set_block(c, mpos, f.provide(c, cf["block"], mpos))
					mpos.y += 1
					any = true
				elif f.test(c, cf["continue"], mpos):
					mpos.y += 1
				else:
					break
				hgt -= 1
	return any


static func _pillar(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var dir: Vector3i = cf["dir"]
	var chance: float = cf["chance"]
	var p := o
	var last := o
	var placed := false
	while _in_world(f, p.y) and f.test(c, cf["can_replace"], p):
		f.set_block(c, p, f.provide(c, cf["block"], p))
		placed = true
		last = p
		p += dir
		if chance < 1.0 and c.r.next_float() >= chance:
			break
	if placed and not (cf["cap"] as Dictionary).is_empty():
		f._sub(c, cf["cap"], last)
	return placed


static func _patchy_square(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var n: int = cf["size"]
	var proj: int = cf["proj"]
	var any := false
	for i in range(-n, n + 1):
		for j in range(-n, n + 1):
			var k := absi(i) * absi(j)
			if c.r.next_int_bound(10) >= 10 - k:
				continue
			var q := o + Vector3i(i, 0, j)
			var h := 0
			while h < proj and f.test(c, cf["through"], q + Vector3i(0, -1, 0)):
				q.y -= 1
				h += 1
			if not f.test(c, cf["through"], q):
				continue
			var st := f.provide(c, cf["block"], q)
			if st > 0:
				f.set_block(c, q, st)
				any = true
	return any


static func _neighbor_spread(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var acc: Dictionary = cf["accepted"]
	if not f.test(c, cf["can_replace"], o):
		return false
	var st := f.provide(c, cf["block"], o)
	f.set_block(c, o, st)
	for a in int(cf["attempts"]):
		var p := o + Vector3i(f.sample_int(c, cf["xz"]), f.sample_int(c, cf["y"]), f.sample_int(c, cf["xz"]))
		if not f.test(c, cf["can_replace"], p):
			continue
		var cnt := 0
		for d in DIRS6:
			var s := f.get_block(c, p + d)
			if s > 0 and acc.has(f.blocks.st_block[s]):
				cnt += 1
				if cnt > 1:
					break
		if cnt == 1:
			f.set_block(c, p, f.provide(c, cf["block"], p))
	return true


static func _fungus_replaceable(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i, check: bool) -> bool:
	var s := f.get_block(c, p)
	if s == 0 or (s > 0 and (f.blocks.st_flags[s] & BlockRegistry.F_REPLACEABLE) != 0):
		return true
	return check and f.test(c, cf["replace"], p)


static func _fungus(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var r := c.r
	if not _is(f, c, o + Vector3i(0, -1, 0), cf["base"]):
		return false
	var h := _mth_next(r, 4, 13)
	if r.next_int_bound(12) == 0:
		h *= 2
	var planted: bool = cf["planted"]
	if not planted and o.y + h + 1 >= f.gen.gen_depth:
		return false
	var huge := not planted and r.next_float() < 0.06
	f.set_block(c, o, 0)
	# stem
	var stem: int = cf["stem"]
	var si := 1 if huge else 0
	for j in range(-si, si + 1):
		for k in range(-si, si + 1):
			var corner := huge and absi(j) == si and absi(k) == si
			for l in h:
				var m := o + Vector3i(j, l, k)
				if _fungus_replaceable(f, c, cf, m, true):
					if corner:
						if r.next_float() < 0.1:
							f.set_block(c, m, stem)
					else:
						f.set_block(c, m, stem)
	# hat
	var hat: int = cf["hat"]
	var wart := f.blocks.name_of(hat) == "nether_wart_block"
	var i := mini(r.next_int_bound(1 + h / 3) + 5, h)
	var j0 := h - i
	for k2 in range(j0, h + 1):
		var lr := 2 if k2 < h - r.next_int_bound(3) else 1
		if i > 8 and k2 < j0 + 4:
			lr = 3
		if huge:
			lr += 1
		for n in range(-lr, lr + 1):
			for o2 in range(-lr, lr + 1):
				var e1 := n == -lr or n == lr
				var e2 := o2 == -lr or o2 == lr
				var inner := not e1 and not e2 and k2 != h
				var corner2 := e1 and e2
				var low := k2 < j0 + 3
				var m2 := o + Vector3i(n, k2, o2)
				if not _fungus_replaceable(f, c, cf, m2, false):
					continue
				if low:
					if not inner:
						# placeHatDropBlock
						var bs := f.get_block(c, m2 + Vector3i(0, -1, 0))
						if bs > 0 and f.blocks.st_block[bs] == f.blocks.st_block[hat]:
							f.set_block(c, m2, hat)
						elif r.next_float() < 0.15:
							f.set_block(c, m2, hat)
							if wart and r.next_int_bound(11) == 0:
								_weeping_vines(f, c, m2)
				elif inner:
					_hat_block(f, c, cf, m2, 0.1, 0.2, 0.1 if wart else 0.0)
				elif corner2:
					_hat_block(f, c, cf, m2, 0.01, 0.7, 0.083 if wart else 0.0)
				else:
					_hat_block(f, c, cf, m2, 0.0005, 0.98, 0.07 if wart else 0.0)
	return true


static func _hat_block(f: Features, c: Features.FCtx, cf: Dictionary, m: Vector3i, decor: float, hat: float, vine: float) -> void:
	var r := c.r
	if r.next_float() < decor:
		f.set_block(c, m, cf["decor"])
	elif r.next_float() < hat:
		f.set_block(c, m, cf["hat"])
		if r.next_float() < vine:
			_weeping_vines(f, c, m)


static func _weeping_vines(f: Features, c: Features.FCtx, pos: Vector3i) -> void:
	var r := c.r
	var m := pos + Vector3i(0, -1, 0)
	if not _air(f, c, m):
		return
	var n := _mth_next(r, 1, 5)
	if r.next_int_bound(7) == 0:
		n *= 2
	var plant := f.blocks.default_state("weeping_vines_plant")
	var tip := f.blocks.default_state("weeping_vines")
	for i in n + 1:
		if _air(f, c, m):
			if i == n or not _air(f, c, m + Vector3i(0, -1, 0)):
				f.set_block(c, m, f.blocks.with_prop(tip, "age", str(_mth_next(r, 23, 25))))
				break
			f.set_block(c, m, plant)
		m.y -= 1


# ------------------------------------------------------------------ End

static func _end_island(f: Features, c: Features.FCtx, o: Vector3i) -> bool:
	var r := c.r
	var es := f.blocks.default_state("end_stone")
	var fr := float(r.next_int_bound(3)) + 4.0
	var i := 0
	while fr > 0.5:
		for j in range(floori(-fr), ceili(fr) + 1):
			for k in range(floori(-fr), ceili(fr) + 1):
				if float(j * j + k * k) <= (fr + 1.0) * (fr + 1.0):
					f.set_block(c, o + Vector3i(j, i, k), es)
		fr -= float(r.next_int_bound(2)) + 0.5
		i -= 1
	return true


## Java SpikeFeature.getSpikesForLevel: 10 obsidian pillars from the world seed. [x, z, radius, height, guarded]
static func end_spikes_for_seed(world_seed: int) -> Array:
	var r := RandomSources.LegacyRandom.new(world_seed)
	var l := r.next_long() & 65535
	var r2 := RandomSources.LegacyRandom.new(l)
	var lst: Array = []
	for i in 10:
		lst.append(i)
	var n := lst.size()
	var jj := n
	while jj > 1:
		var k := r2.next_int_bound(jj)
		var tmp = lst[jj - 1]
		lst[jj - 1] = lst[k]
		lst[k] = tmp
		jj -= 1
	var out: Array = []
	for i in 10:
		var x := floori(42.0 * cos(2.0 * (-PI + (PI / 10.0) * i)))
		var z := floori(42.0 * sin(2.0 * (-PI + (PI / 10.0) * i)))
		var m: int = lst[i]
		out.append([x, z, 2 + m / 3, 76 + m * 3, m == 1 or m == 2])
	return out


static func _end_spikes(f: Features, c: Features.FCtx, o: Vector3i) -> bool:
	var any := false
	for sp in end_spikes_for_seed(f.gen.seed):
		if (int(sp[0]) >> 4) == (o.x >> 4) and (int(sp[1]) >> 4) == (o.z >> 4):
			place_spike(f, c, sp)
			any = true
	return any


static func place_spike(f, c, sp: Array) -> void:   # f: Features or DragonFight.SpikeShim (live)
	var cx: int = sp[0]
	var cz: int = sp[1]
	var rad: int = sp[2]
	var hgt: int = sp[3]
	var obs: int = f.blocks.default_state("obsidian")
	for y in range(f.gen.gen_min_y, hgt + 11):
		for z in range(cz - rad, cz + rad + 1):
			for x in range(cx - rad, cx + rad + 1):
				var dx := x - cx
				var dz := z - cz
				if dx * dx + dz * dz <= rad * rad + 1 and y < hgt:
					f.set_block(c, Vector3i(x, y, z), obs)
				elif y > 65:
					f.set_block(c, Vector3i(x, y, z), 0)
	if sp[4]:
		var bars: int = f.blocks.default_state("iron_bars")
		for k in range(-2, 3):
			for l in range(-2, 3):
				for m in range(0, 4):
					var b1 := absi(k) == 2
					var b2 := absi(l) == 2
					var b3 := m == 3
					if b1 or b2 or b3:
						var b4 := k == -2 or k == 2 or b3
						var b5 := l == -2 or l == 2 or b3
						var st: int = f.blocks.with_prop(bars, "north", str(b4 and l != -2))
						st = f.blocks.with_prop(st, "south", str(b4 and l != 2))
						st = f.blocks.with_prop(st, "west", str(b5 and k != -2))
						st = f.blocks.with_prop(st, "east", str(b5 and k != 2))
						f.set_block(c, Vector3i(cx + k, hgt + m, cz + l), st)
	# crystal base (the End Crystal entity is spawned by the dragon-fight manager)
	f.set_block(c, Vector3i(cx, hgt, cz), f.blocks.default_state("bedrock"))
	f.set_block(c, Vector3i(cx, hgt + 1, cz), f.blocks.default_state("fire"))


static func _chorus_state(f: Features, c: Features.FCtx, p: Vector3i) -> int:
	var st := f.blocks.default_state("chorus_plant")
	var plant := f.blocks.block_id("chorus_plant")
	var flower := f.blocks.block_id("chorus_flower")
	var end_stone := f.blocks.block_id("end_stone")
	var names := ["down", "up", "north", "south", "west", "east"]
	var offs := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
	for i in 6:
		var s := f.get_block(c, p + offs[i])
		var b := f.blocks.st_block[s] if s > 0 else -1
		var con := b == plant or b == flower or (i == 0 and b == end_stone)
		st = f.blocks.with_prop(st, names[i], "true" if con else "false")
	return st


static func _chorus_neighbors_empty(f: Features, c: Features.FCtx, p: Vector3i, except: Vector3i) -> bool:
	for d in HORIZ:
		if d != except and not _air(f, c, p + d):
			return false
	return true


static func _chorus(f: Features, c: Features.FCtx, o: Vector3i) -> bool:
	if not _air(f, c, o) or not _is(f, c, o + Vector3i(0, -1, 0), f.blocks.block_id("end_stone")):
		return false
	f.set_block(c, o, _chorus_state(f, c, o))
	_chorus_grow(f, c, o, o, 8, 0)
	return true


static func _chorus_grow(f: Features, c: Features.FCtx, branch: Vector3i, origin: Vector3i, maxd: int, it: int) -> void:
	var r := c.r
	var i := r.next_int_bound(4) + 1
	if it == 0:
		i += 1
	for j in i:
		var p := branch + Vector3i(0, j + 1, 0)
		if not _chorus_neighbors_empty(f, c, p, Vector3i(99, 99, 99)):
			return
		f.set_block(c, p, _chorus_state(f, c, p))
		f.set_block(c, p + Vector3i(0, -1, 0), _chorus_state(f, c, p + Vector3i(0, -1, 0)))
	var grew := false
	if it < 4:
		var k := r.next_int_bound(4)
		if it == 0:
			k += 1
		for l in k:
			var d: Vector3i = HORIZ[r.next_int_bound(4)]
			var q := branch + Vector3i(0, i, 0) + d
			if absi(q.x - origin.x) < maxd and absi(q.z - origin.z) < maxd and _air(f, c, q) and _air(f, c, q + Vector3i(0, -1, 0)) and _chorus_neighbors_empty(f, c, q, -d):
				grew = true
				f.set_block(c, q, _chorus_state(f, c, q))
				f.set_block(c, q - d, _chorus_state(f, c, q - d))
				_chorus_grow(f, c, q, origin, maxd, it + 1)
	if not grew:
		f.set_block(c, branch + Vector3i(0, i, 0), f.blocks.with_prop(f.blocks.default_state("chorus_flower"), "age", "5"))


static func end_gateway(f, c, o: Vector3i, exit, exact: bool) -> void:
	var bed: int = f.blocks.default_state("bedrock")
	var gw: int = f.blocks.default_state("end_gateway")
	for y in range(-2, 3):
		for z in range(-1, 2):
			for x in range(-1, 2):
				var p := o + Vector3i(x, y, z)
				var bx := x == 0
				var by := y == 0
				var bz := z == 0
				var b4 := absi(y) == 2
				if bx and by and bz:
					f.set_block(c, p, gw)
					if exit is Array and exit.size() == 3:
						c.block_entities[p] = {"id": "end_gateway", "exit": [int(exit[0]), int(exit[1]), int(exit[2])], "exact": exact}
				elif by:
					f.set_block(c, p, 0)
				elif b4 and bx and bz:
					f.set_block(c, p, bed)
				elif (bx or bz) and not b4:
					f.set_block(c, p, bed)
				else:
					f.set_block(c, p, 0)


static func end_platform(f, c, o: Vector3i) -> void:
	var obs: int = f.blocks.default_state("obsidian")
	for i in range(-2, 3):
		for j in range(-2, 3):
			for k in range(-1, 3):
				f.set_block(c, o + Vector3i(j, k, i), obs if k == -1 else 0)


## Java EndPodiumFeature (exit portal): active = end_portal blocks inside.
static func end_podium(f, c, o: Vector3i, active: bool) -> void:
	var bed: int = f.blocks.default_state("bedrock")
	var es: int = f.blocks.default_state("end_stone")
	var portal: int = f.blocks.default_state("end_portal")
	for y in range(-1, 33):
		for z in range(-4, 5):
			for x in range(-4, 5):
				var p := o + Vector3i(x, y, z)
				# Vec3i.closerThan: 3D squared distance (above the rim only a 3.5 sphere is cleared: the egg stays)
				var d2 := x * x + y * y + z * z
				if d2 < 12.25:
					var inner := d2 < 6.25
					if y < 0:
						if inner:
							f.set_block(c, p, bed)
						else:
							f.set_block(c, p, es)
					elif y > 0:
						f.set_block(c, p, 0)
					elif not inner:
						f.set_block(c, p, bed)
					elif active:
						f.set_block(c, p, portal)
					else:
						f.set_block(c, p, 0)
	for i in 4:
		f.set_block(c, o + Vector3i(0, i, 0), bed)
	var torch: int = f.blocks.default_state("wall_torch")
	var c2 := o + Vector3i(0, 2, 0)
	for d in [["north", Vector3i(0, 0, -1)], ["south", Vector3i(0, 0, 1)], ["west", Vector3i(-1, 0, 0)], ["east", Vector3i(1, 0, 0)]]:
		f.set_block(c, c2 + d[1], f.blocks.with_prop(torch, "facing", d[0]))


# ------------------------------------------------------------------ oceans / ice / misc

static func _coral_place(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var s := f.get_block(c, p)
	var above := f.get_block(c, p + Vector3i(0, 1, 0))
	var water := f.blocks.block_id("water")
	var ok := (s > 0 and (f.blocks.st_block[s] == water or f.blocks.name_of(s).ends_with("coral_block"))) and above > 0 and f.blocks.st_block[above] == water
	if not ok:
		return false
	f._sub(c, cf["coral"], p)
	var r := c.r
	# decorations above (Java CoralFeature.placeCoralBlock: coral / sea pickle on top, fans on sides)
	if r.next_float() < 0.25:
		var pick: String = ["tube_coral", "brain_coral", "bubble_coral", "fire_coral", "horn_coral"][r.next_int_bound(5)]
		f.set_block(c, p + Vector3i(0, 1, 0), f.blocks.default_state(pick))
	elif r.next_float() < 0.05:
		f.set_block(c, p + Vector3i(0, 1, 0), f.blocks.with_prop(f.blocks.default_state("sea_pickle"), "pickles", str(r.next_int_bound(4) + 1)))
	for d in [["north", Vector3i(0, 0, -1)], ["south", Vector3i(0, 0, 1)], ["west", Vector3i(-1, 0, 0)], ["east", Vector3i(1, 0, 0)]]:
		if r.next_float() < 0.2:
			var q: Vector3i = p + d[1]
			var qs := f.get_block(c, q)
			if qs > 0 and f.blocks.st_block[qs] == water:
				var fan: String = ["tube_coral_wall_fan", "brain_coral_wall_fan", "bubble_coral_wall_fan", "fire_coral_wall_fan", "horn_coral_wall_fan"][r.next_int_bound(5)]
				f.set_block(c, q, f.blocks.with_prop(f.blocks.default_state(fan), "facing", d[0]))
	return true


static func _coral(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i, t: String) -> bool:
	var r := c.r
	if t == "coral_tree":
		var p := o
		var n := r.next_int_bound(3) + 1
		for i in n:
			if not _coral_place(f, c, cf, p):
				return true
			p.y += 1
		var top := p
		var m := r.next_int_bound(3) + 2
		var dirs := HORIZ.duplicate()
		# shuffle (Util.shuffle semantics approximated with nextInt swaps)
		for k in range(dirs.size() - 1, 0, -1):
			var sw := r.next_int_bound(k + 1)
			var tmp = dirs[k]
			dirs[k] = dirs[sw]
			dirs[sw] = tmp
		for d in dirs.slice(0, m):
			var q: Vector3i = top + d
			var len := r.next_int_bound(5) + 2
			var steps := 0
			for s in len:
				if not _coral_place(f, c, cf, q):
					break
				steps += 1
				q.y += 1
				if s == 0 or (steps >= 2 and r.next_float() < 0.25):
					q += d
					steps = 0
		return true
	if t == "coral_claw":
		if not _coral_place(f, c, cf, o):
			return false
		var main: Vector3i = HORIZ[r.next_int_bound(4)]
		var k := r.next_int_bound(2) + 2
		for i in k:
			var d2: Vector3i = HORIZ[r.next_int_bound(4)]
			var q2 := o + d2
			var len2 := r.next_int_bound(3) + 2
			for s in len2:
				if not _coral_place(f, c, cf, q2):
					break
				q2 += main if s % 2 == 1 else Vector3i(0, 1, 0)
		return true
	# coral_mushroom
	var a := r.next_int_bound(3) + 3
	var b := r.next_int_bound(3) + 3
	var h := r.next_int_bound(3) + 3
	var base := o + Vector3i(0, r.next_int_bound(2), 0)
	for x in a + 1:
		for y in h + 1:
			for z in b + 1:
				var edge := int(x == 0 or x == a) + int(y == 0 or y == h) + int(z == 0 or z == b)
				if edge == 1 and r.next_float() < 0.9:
					_coral_place(f, c, cf, base + Vector3i(x, y, z))
	return true


static func _underwater_magma(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var water := f.blocks.block_id("water")
	var p := o
	var found := false
	for i in int(cf["range"]):
		var s := f.get_block(c, p)
		if s > 0 and f.blocks.st_block[s] != water and (f.blocks.st_flags[s] & BlockRegistry.F_COLLIDE) != 0:
			found = true
			break
		p.y -= 1
	if not found:
		return false
	var magma := f.blocks.default_state("magma_block")
	var rad: int = cf["radius"]
	var any := false
	for dx in range(-rad, rad + 1):
		for dy in range(-rad, rad + 1):
			for dz in range(-rad, rad + 1):
				var q := p + Vector3i(dx, dy, dz)
				var s2 := f.get_block(c, q)
				if s2 <= 0 or (f.blocks.st_flags[s2] & BlockRegistry.F_COLLIDE) == 0:
					continue
				var above := f.get_block(c, q + Vector3i(0, 1, 0))
				if above <= 0 or f.blocks.st_block[above] != water:
					continue
				var walled := true
				for d in HORIZ:
					var n := f.get_block(c, q + d)
					if n <= 0 or (f.blocks.st_flags[n] & BlockRegistry.F_COLLIDE) == 0:
						walled = false
						break
				if walled and c.r.next_float() < float(cf["prob"]):
					f.set_block(c, q, magma)
					any = true
	return any


static func _blue_ice(f: Features, c: Features.FCtx, o: Vector3i) -> bool:
	var r := c.r
	if o.y > f.gen.sea_level - 1:
		return false
	var water := f.blocks.block_id("water")
	var pk := f.blocks.block_id("packed_ice")
	var s := f.get_block(c, o)
	if s <= 0 or f.blocks.st_block[s] != water:
		var sb := f.get_block(c, o + Vector3i(0, -1, 0))
		if sb <= 0 or f.blocks.st_block[sb] != water:
			return false
	var touching := false
	for d in DIRS6:
		if d != Vector3i(0, -1, 0) and _is(f, c, o + d, pk):
			touching = true
			break
	if not touching:
		return false
	var bi := f.blocks.default_state("blue_ice")
	f.set_block(c, o, bi)
	for i in 200:
		var j := r.next_int_bound(5) - r.next_int_bound(6)
		var k := 3
		if j < 2:
			k += j / 2
		if k >= 1:
			var q := o + Vector3i(r.next_int_bound(k) - r.next_int_bound(k), j, r.next_int_bound(k) - r.next_int_bound(k))
			var qs := f.get_block(c, q)
			if qs == 0 or (qs > 0 and (f.blocks.st_block[qs] == water or f.blocks.st_block[qs] == pk or f.blocks.name_of(qs) == "ice")):
				for d in DIRS6:
					if _is(f, c, q + d, f.blocks.block_id("blue_ice")):
						f.set_block(c, q, bi)
						break
	return true


static func _spike(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var r := c.r
	var p := o
	while _air(f, c, p) and p.y > f.gen.gen_min_y + 2:
		p.y -= 1
	if not f.test(c, cf["on"], p):
		return false
	p.y += r.next_int_bound(4)
	var i := r.next_int_bound(4) + 7
	var j := i / 4 + r.next_int_bound(2)
	if j > 1 and r.next_int_bound(60) == 0:
		p.y += 10 + r.next_int_bound(30)
	var st: int = cf["state"]
	for k in i:
		var fr := (1.0 - float(k) / float(i)) * j
		var l := ceili(fr)
		for m in range(-l, l + 1):
			var g := float(absi(m)) - 0.25
			for n in range(-l, l + 1):
				var h := float(absi(n)) - 0.25
				if (m == 0 and n == 0 or g * g + h * h <= fr * fr) and (m != -l and m != l and n != -l and n != l or r.next_float() <= 0.75):
					for half in 2:
						# the layer itself, then its mirror below (Java: only when k != 0 and l > 1). Iterating [k, -k] by
						# value skipped the k = 0 layer too (0 == -0): every ice spike had a missing slice at its base
						if half == 1 and (k == 0 or l <= 1):
							continue
						var yy := k if half == 0 else -k
						var q := p + Vector3i(m, yy, n)
						if f.test(c, cf["can_replace"], q) or _air(f, c, q):
							f.set_block(c, q, st)
	var w := j - 1
	if w < 0:
		w = 0
	elif w > 1:
		w = 1
	for m2 in range(-w, w + 1):
		for n2 in range(-w, w + 1):
			var q2 := p + Vector3i(m2, -1, n2)
			var o2 := 50
			if absi(m2) == 1 and absi(n2) == 1:
				o2 = r.next_int_bound(5)
			while q2.y > 50:
				if not (_air(f, c, q2) or f.test(c, cf["can_replace"], q2) or _is(f, c, q2, f.blocks.st_block[st])):
					break
				f.set_block(c, q2, st)
				q2.y -= 1
				o2 -= 1
				if o2 <= 0:
					q2.y -= r.next_int_bound(5) + 1
					o2 = r.next_int_bound(5)
	return true


static func _blob(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	var r := c.r
	var p := o
	while p.y > f.gen.gen_min_y + 3:
		if not _air(f, c, p + Vector3i(0, -1, 0)) and f.test(c, cf["on"], p + Vector3i(0, -1, 0)):
			break
		p.y -= 1
	if p.y <= f.gen.gen_min_y + 3:
		return false
	var st: int = cf["state"]
	for i in 3:
		var j := r.next_int_bound(2)
		var k := r.next_int_bound(2)
		var l := r.next_int_bound(2)
		var fr := float(j + k + l) * 0.333 + 0.5
		for dx in range(-j, j + 1):
			for dy in range(-k, k + 1):
				for dz in range(-l, l + 1):
					if float(dx * dx + dy * dy + dz * dz) <= fr * fr:
						f.set_block(c, p + Vector3i(dx, dy, dz), st)
		p += Vector3i(-1 + r.next_int_bound(2), -r.next_int_bound(2), -1 + r.next_int_bound(2))
	return true


static func _iceberg(f: Features, c: Features.FCtx, cf: Dictionary, o: Vector3i) -> bool:
	# Simplified Java IcebergFeature: elliptical body above and below sea level with snow cap.
	var r := c.r
	var p := Vector3i(o.x, f.gen.sea_level, o.z)
	var st: int = cf["state"]
	var water := f.blocks.block_id("water")
	var h := r.next_int_bound(14) + 8
	var rad := r.next_int_bound(4) + 4
	for y in range(-h, h / 2 + 1):
		var fr := float(rad) * (1.0 - absf(float(y)) / float(h if y < 0 else maxi(h / 2, 1)))
		var ri := ceili(fr)
		for dz in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if dx * dx + dz * dz <= fr * fr:
					var q := p + Vector3i(dx, y, dz)
					var s := f.get_block(c, q)
					if s == 0 or (s > 0 and f.blocks.st_block[s] == water):
						f.set_block(c, q, st)
	return true


static func _vines(f: Features, c: Features.FCtx, o: Vector3i) -> bool:
	if not _air(f, c, o):
		return false
	var vine := f.blocks.default_state("vine")
	for d in [["north", Vector3i(0, 0, -1)], ["east", Vector3i(1, 0, 0)], ["south", Vector3i(0, 0, 1)], ["west", Vector3i(-1, 0, 0)], ["up", Vector3i(0, 1, 0)]]:
		var s := f.get_block(c, o + d[1])
		if s > 0 and (f.blocks.st_flags[s] & BlockRegistry.F_FULL_SHAPE) != 0:
			f.set_block(c, o, f.blocks.with_prop(vine, d[0], "true"))
			return true
	return false


## 26.x TemplateFeature (class E, reconstructed from the data: desert_well and sulfur_spring place 5x5 / 8x9 templates
## whose explicit air clears the space they need): weighted template choice, random rotation about the template's
## horizontal centre, centre on the origin column, template y 0 at the origin; air is placed, structure void is not.
## Writes are clipped to the 3 x 3 chunks around the origin chunk (Java WorldGenRegion).
static func _template(f: Features, c: Features.FCtx, cf: Dictionary, p: Vector3i) -> bool:
	var ts: Array = cf["ts"]
	if ts.is_empty():
		return false
	var tot := 0
	for e in ts:
		tot += int(e[0])
	var k := c.r.next_int_bound(tot)
	var tid := ""
	for e in ts:
		k -= int(e[0])
		if k < 0:
			tid = str(e[1])
			break
	var tpl := StructureTemplate.get_template(tid)
	if tpl == null:
		return false
	var rot := c.r.next_int_bound(4)
	var pivot := Vector3i(tpl.size.x / 2, 0, tpl.size.z / 2)
	var origin := p - StructureTemplate.transform(pivot, rot)
	var ch := c.origin_chunk
	var cmin := Vector3i(ch.cx * 16 - 16, f.gen.gen_min_y, ch.cz * 16 - 16)
	var cmax := Vector3i(ch.cx * 16 + 31, f.gen.gen_min_y + f.gen.gen_depth - 1, ch.cz * 16 + 31)
	tpl.place(f, c, origin, rot, cf["procs"], false, false, cmin, cmax)
	return true
