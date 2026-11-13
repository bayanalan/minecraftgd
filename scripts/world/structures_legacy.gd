## StructuresLegacy — non-jigsaw structures. Template-based (installed .nbt): igloo, shipwreck(+beached),
## ruined_portal (+nether), nether_fossil, ocean_ruin, end_city (simplified recursion). Approximate original
## builders (APPROXIMATE in PARITY_MATRIX; Java piece generators not reproduced block-for-block): stronghold (with a
## complete End portal room), fortress (bridges, corridors, blaze spawners, nether wart), mineshaft, desert_pyramid,
## jungle_temple, swamp_hut, buried_treasure, ocean_monument. woodland_mansion: not generated (documented).
## Contract: generate(structs, type, cfg, start_chunk, random) -> {} or {center, box, pieces? , blocks?, bes?, ents?}.
class_name StructuresLegacy
extends RefCounted


class Builder:
	var blocks: Dictionary = {}     # Vector2i chunk -> PackedInt32Array [x, y, z, st]*
	var bes: Dictionary = {}        # Vector3i -> block entity data
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var mx := -Vector3i(1 << 30, 1 << 30, 1 << 30)
	var reg: BlockRegistry
	# optional pieces (Java StructurePiece): blocks tagged with a part index, each part with its own bounding box, so a
	# part can be skipped per chunk (mineshaft pieces touching liquid, Java isInInvalidLocation)
	var part := -1
	var parts: Array = []        # [min, max] per part
	var pidx: Dictionary = {}    # Vector2i chunk -> PackedInt32Array part index per block

	func begin_part() -> void:
		parts.append([Vector3i(1 << 30, 1 << 30, 1 << 30), -Vector3i(1 << 30, 1 << 30, 1 << 30)])
		part = parts.size() - 1

	func put(p: Vector3i, st: int) -> void:
		if st < 0:
			return
		var k := Vector2i(p.x >> 4, p.z >> 4)
		var a = blocks.get(k)
		if a == null:
			a = PackedInt32Array()
		var arr: PackedInt32Array = a
		arr.append_array([p.x, p.y, p.z, st])
		blocks[k] = arr
		if part >= 0:
			var pa: PackedInt32Array = pidx.get(k, PackedInt32Array())
			pa.append(part)
			pidx[k] = pa
			parts[part] = [Vector3i(mini(parts[part][0].x, p.x), mini(parts[part][0].y, p.y), mini(parts[part][0].z, p.z)),
				Vector3i(maxi(parts[part][1].x, p.x), maxi(parts[part][1].y, p.y), maxi(parts[part][1].z, p.z))]
		mn = Vector3i(mini(mn.x, p.x), mini(mn.y, p.y), mini(mn.z, p.z))
		mx = Vector3i(maxi(mx.x, p.x), maxi(mx.y, p.y), maxi(mx.z, p.z))

	func s(name: String) -> int:
		return reg.default_state(name)

	func fill(a: Vector3i, b: Vector3i, st: int) -> void:
		for y in range(mini(a.y, b.y), maxi(a.y, b.y) + 1):
			for z in range(mini(a.z, b.z), maxi(a.z, b.z) + 1):
				for x in range(mini(a.x, b.x), maxi(a.x, b.x) + 1):
					put(Vector3i(x, y, z), st)

	## Hollow box: walls via `wall` callable(pos) -> state, interior air.
	func room(a: Vector3i, b: Vector3i, wall: Callable) -> void:
		for y in range(a.y, b.y + 1):
			for z in range(a.z, b.z + 1):
				for x in range(a.x, b.x + 1):
					var edge := x == a.x or x == b.x or y == a.y or y == b.y or z == a.z or z == b.z
					put(Vector3i(x, y, z), wall.call(Vector3i(x, y, z)) if edge else 0)

	func chest(p: Vector3i, table: String, facing: String = "north") -> void:
		put(p, reg.with_prop(s("chest"), "facing", facing))
		bes[p] = {"id": "chest", "loot_table": table}

	func spawner(p: Vector3i, mob: String) -> void:
		put(p, s("spawner"))
		bes[p] = {"id": "spawner", "mob": mob}

	func result(center: Vector3i) -> Dictionary:
		if blocks.is_empty():
			return {}
		var r := {"blocks": blocks, "bes": bes, "center": center, "box": [mn, mx]}
		if not parts.is_empty():
			r["parts"] = parts
			r["pidx"] = pidx
		return r


static func generate(st: Structures, t: String, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	match t:
		"igloo":
			return _igloo(st, sc, r)
		"shipwreck":
			return _shipwreck(st, cfg, sc, r)
		"ruined_portal":
			return _ruined_portal(st, cfg, sc, r)
		"nether_fossil":
			return _nether_fossil(st, sc, r)
		"ocean_ruin":
			return _ocean_ruin(st, cfg, sc, r)
		"end_city":
			return _end_city(st, sc, r)
		"stronghold":
			return _stronghold(st, sc, r)
		"fortress":
			return _fortress(st, sc, r)
		"mineshaft":
			return _mineshaft(st, cfg, sc, r)
		"desert_pyramid":
			return _desert_pyramid(st, sc, r)
		"jungle_temple":
			return _jungle_temple(st, sc, r)
		"swamp_hut":
			return _swamp_hut(st, sc, r)
		"buried_treasure":
			return _buried_treasure(st, sc)
		"ocean_monument":
			return _monument(st, sc, r)
	return {}


static func _tpl_piece(loc: String, pos: Vector3i, rot: int, procs: Array = [], ignore_air: bool = true) -> Dictionary:
	var tpl := StructureTemplate.get_template(loc)
	if tpl == null:
		return {}
	var el := {"t": "single", "loc": loc, "legacy": ignore_air, "proj": "rigid", "procs": procs}
	return {"el": el, "pos": pos, "rot": rot, "box": tpl.box(pos, rot)}


static func _pieces_result(pieces: Array, center: Vector3i) -> Dictionary:
	var ps: Array = []
	for p in pieces:
		if not (p as Dictionary).is_empty():
			ps.append(p)
	if ps.is_empty():
		return {}
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var mx := -mn
	for p in ps:
		mn = Vector3i(mini(mn.x, p["box"][0].x), mini(mn.y, p["box"][0].y), mini(mn.z, p["box"][0].z))
		mx = Vector3i(maxi(mx.x, p["box"][1].x), maxi(mx.y, p["box"][1].y), maxi(mx.z, p["box"][1].z))
	return {"pieces": ps, "center": center, "box": [mn, mx]}


static func _centered(tpl_loc: String, base: Vector3i, rot: int) -> Vector3i:
	var tpl := StructureTemplate.get_template(tpl_loc)
	if tpl == null:
		return base
	var b := tpl.box(Vector3i.ZERO, rot)
	return base - Vector3i((b[0].x + b[1].x) / 2, 0, (b[0].z + b[1].z) / 2)


# ------------------------------------------------------------------ template structures

static func _igloo(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var rot := r.next_int_bound(4)
	var cx := sc.x * 16 + 8
	var cz := sc.y * 16 + 8
	var y := st.first_free_height(cx, cz) - 1
	var top := _centered("igloo/top", Vector3i(cx, y, cz), rot)
	# Java IglooPieces: BlockIgnoreProcessor.STRUCTURE_BLOCK only -> template air is placed (hollows the room /
	# ladder shaft out of the terrain)
	var pieces: Array = [_tpl_piece("igloo/top", top, rot, [], false)]
	if r.next_double() < 0.5:
		var n := r.next_int_bound(8) + 4
		var lad := top + StructureTemplate.transform(Vector3i(3, 0, 5), rot)
		for j in n - 1:
			pieces.append(_tpl_piece("igloo/middle", lad + Vector3i(-1, -3 - j * 3, -1), rot, [], false))
		pieces.append(_tpl_piece("igloo/bottom", lad + StructureTemplate.transform(Vector3i(-3, 0, -7), rot) + Vector3i(0, -3 - n * 3, 0), rot, [], false))
	return _pieces_result(pieces, Vector3i(cx, y, cz))


const SHIP_OCEAN := ["shipwreck/with_mast", "shipwreck/sideways_full", "shipwreck/sideways_fronthalf", "shipwreck/sideways_backhalf", "shipwreck/rightsideup_full",
	"shipwreck/rightsideup_fronthalf", "shipwreck/rightsideup_backhalf", "shipwreck/with_mast_degraded", "shipwreck/rightsideup_full_degraded",
	"shipwreck/rightsideup_fronthalf_degraded", "shipwreck/rightsideup_backhalf_degraded", "shipwreck/upsidedown_full", "shipwreck/upsidedown_fronthalf",
	"shipwreck/upsidedown_backhalf", "shipwreck/upsidedown_full_degraded", "shipwreck/upsidedown_fronthalf_degraded", "shipwreck/upsidedown_backhalf_degraded",
	"shipwreck/sideways_full_degraded", "shipwreck/sideways_fronthalf_degraded", "shipwreck/sideways_backhalf_degraded"]
const SHIP_BEACHED := ["shipwreck/with_mast", "shipwreck/sideways_full", "shipwreck/sideways_fronthalf", "shipwreck/sideways_backhalf", "shipwreck/rightsideup_full",
	"shipwreck/rightsideup_fronthalf", "shipwreck/rightsideup_backhalf", "shipwreck/with_mast_degraded", "shipwreck/rightsideup_full_degraded",
	"shipwreck/rightsideup_fronthalf_degraded", "shipwreck/rightsideup_backhalf_degraded"]


static func _shipwreck(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var rot := r.next_int_bound(4)
	var beached := bool(cfg.get("is_beached", false))
	var lst: Array = SHIP_BEACHED if beached else SHIP_OCEAN
	var loc: String = lst[r.next_int_bound(lst.size())]
	var cx := sc.x * 16 + 8
	var cz := sc.y * 16 + 8
	var y := st.first_free_height(cx, cz, not beached)
	if beached:
		var tpl := StructureTemplate.get_template(loc)
		y -= (tpl.size.y / 2 if tpl != null else 2) + r.next_int_bound(3)
	return _pieces_result([_tpl_piece(loc, _centered(loc, Vector3i(cx, y, cz), rot), rot)], Vector3i(cx, y, cz))


static func _ruined_portal(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var setups: Array = cfg.get("setups", [{}])
	var tot := 0.0
	for s in setups:
		tot += float(s.get("weight", 1.0))
	var pick := r.next_float() * tot
	var setup: Dictionary = setups[0]
	for s in setups:
		pick -= float(s.get("weight", 1.0))
		if pick <= 0.0:
			setup = s
			break
	var giant := r.next_float() < 0.05
	var loc := "ruined_portal/giant_portal_%d" % (r.next_int_bound(3) + 1) if giant else "ruined_portal/portal_%d" % (r.next_int_bound(10) + 1)
	var rot := r.next_int_bound(4)
	var cx := sc.x * 16 + 8
	var cz := sc.y * 16 + 8
	var y := st.first_free_height(cx, cz) - 1
	match str(setup.get("placement", "on_land_surface")):
		"underground":
			y = maxi(st.gen.gen_min_y + 15, y - 15 - r.next_int_bound(20))
		"partly_buried":
			y -= 4
		"in_nether":
			y = 32 + r.next_int_bound(60)
		"on_ocean_floor":
			y = st.first_free_height(cx, cz, true) - 1
	var procs: Array = [{"t": "age", "moss": float(setup.get("mossiness", 0.2))},
		{"t": "rule", "rules": [[{"t": "rblock", "id": st.gen.blocks.block_id("obsidian"), "p": 0.07}, {"t": "true"}, st.gen.blocks.default_state("crying_obsidian")]]}]
	if bool(setup.get("replace_with_blackstone", false)):
		procs.append({"t": "rule", "rules": [[{"t": "block", "id": st.gen.blocks.block_id("stone_bricks")}, {"t": "true"}, st.gen.blocks.default_state("polished_blackstone_bricks")]]})
	return _pieces_result([_tpl_piece(loc, _centered(loc, Vector3i(cx, y, cz), rot), rot, procs)], Vector3i(cx, y, cz))


static func _nether_fossil(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var x := sc.x * 16 + r.next_int_bound(16)
	var z := sc.y * 16 + r.next_int_bound(16)
	var start_y := 32 + r.next_int_bound(126 - 32 + 1)
	var col := _density_column(st, x, z)
	var y := start_y
	var found := false
	while y > st.gen.sea_level:
		if col.get(y, 1.0) <= 0.0 and col.get(y - 1, -1.0) > 0.0:
			found = true
			break
		y -= 1
	if not found:
		return {}
	var loc := "nether_fossils/fossil_%d" % (r.next_int_bound(14) + 1)
	var rot := r.next_int_bound(4)
	return _pieces_result([_tpl_piece(loc, Vector3i(x, y, z), rot)], Vector3i(x, y, z))


static func _density_column(st: Structures, x: int, z: int) -> Dictionary:
	var g := st.gen
	var ctx := DensityFunctions.Ctx.new(g.dfc.node_count())
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var zs := PackedInt32Array()
	for y in range(g.gen_min_y, g.gen_min_y + g.gen_depth):
		xs.append(x)
		ys.append(y)
		zs.append(z)
	var d := g.final_density.batch(ctx, ctx.new_root(xs, ys, zs))
	var out := {}
	for i in d.size():
		out[g.gen_min_y + i] = d[i]
	return out


static func _ocean_ruin(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var warm := str(cfg.get("biome_temp", "cold")) == "warm"
	var big := r.next_float() <= float(cfg.get("large_probability", 0.3))
	var kinds := ["warm"] if warm else ["brick", "cracked", "mossy"]
	var kind: String = kinds[r.next_int_bound(kinds.size())]
	var n := (r.next_int_bound(4) + 4) if (big and kind != "warm") else (r.next_int_bound(4) + 1 if big else r.next_int_bound(8) + 1)
	var loc := "underwater_ruin/%s%s_%d" % ["big_" if big else "", kind, n if not big or kind == "warm" else [1, 2, 3, 8][r.next_int_bound(4)]]
	if StructureTemplate.get_template(loc) == null:
		loc = "underwater_ruin/%s_%d" % [kind, r.next_int_bound(8) + 1]
	var rot := r.next_int_bound(4)
	var cx := sc.x * 16 + 8
	var cz := sc.y * 16 + 8
	var y := st.first_free_height(cx, cz, true) - 1
	var procs: Array = [{"t": "rot", "integrity": float(cfg.get("large_probability", 0.9)) * 0.0 + 0.9}]
	return _pieces_result([_tpl_piece(loc, _centered(loc, Vector3i(cx, y, cz), rot), rot, procs)], Vector3i(cx, y, cz))


## Simplified EndCityPieces: base floor + roof, stacked floors and a tower; ship on large cities.
static func _end_city(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var rot := r.next_int_bound(4)
	var cx := sc.x * 16 + 8
	var cz := sc.y * 16 + 8
	var y := st.first_free_height(cx, cz)
	if y < 60:
		return {}
	var base := _centered("end_city/base_floor", Vector3i(cx, y, cz), rot)
	# Java EndCityPieces "overwrite": true -> STRUCTURE_BLOCK (air placed), false -> STRUCTURE_AND_AIR
	var pieces: Array = [_tpl_piece("end_city/base_floor", base, rot, [], false)]
	var h := 8
	var levels := r.next_int_bound(3)
	var floors := [["end_city/second_floor_1", "end_city/second_roof"], ["end_city/third_floor_1", "end_city/third_roof"]]
	var cur := base + Vector3i(0, 4, 0)
	for i in levels:
		var fl: Array = floors[mini(i, 1)]
		pieces.append(_tpl_piece(fl[0], cur, rot, [], true))
		var tp := StructureTemplate.get_template(fl[0])
		cur += Vector3i(0, (tp.size.y if tp != null else h), 0)
	var roof: String = "end_city/base_roof" if levels == 0 else floors[mini(levels - 1, 1)][1]
	pieces.append(_tpl_piece(roof, cur, rot, [], roof == "end_city/second_roof"))
	var tw := base + StructureTemplate.transform(Vector3i(3, cur.y - base.y + 4, 3), rot)
	pieces.append(_tpl_piece("end_city/tower_base", tw, rot, [], false))
	var tcur := tw + Vector3i(0, 3, 0)
	for i in r.next_int_bound(3) + 2:
		pieces.append(_tpl_piece("end_city/tower_piece", tcur + Vector3i(1, 0, 1), rot, [], false))
		tcur += Vector3i(0, 4, 0)
	pieces.append(_tpl_piece("end_city/tower_top", tcur, rot, [], false))
	if r.next_int_bound(10) < 4:
		pieces.append(_tpl_piece("end_city/ship", tcur + StructureTemplate.transform(Vector3i(-4, 8, -12), rot), rot, [], false))
	return _pieces_result(pieces, Vector3i(cx, y, cz))


# ------------------------------------------------------------------ approximate builders

static func _sb(b: Builder, r: RandomSources.LegacyRandom) -> int:
	var fl := r.next_float()
	if fl < 0.2:
		return b.s("cracked_stone_bricks")
	if fl < 0.5:
		return b.s("mossy_stone_bricks")
	if fl < 0.55:
		return b.s("infested_stone_bricks")
	return b.s("stone_bricks")


static func _stronghold(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var top := mini(st.gen.sea_level - 10 - r.next_int_bound(10), st.first_free_height(sc.x * 16 + 8, sc.y * 16 + 8) - 12)
	var o := Vector3i(sc.x * 16 + 2, top, sc.y * 16 + 2)
	var wall := func(_p: Vector3i) -> int: return _sb(b, r)
	# spiral staircase down from the start room
	b.room(o, o + Vector3i(4, 10, 4), wall)
	for i in 10:
		var yy := o.y + 9 - i
		var spots := [Vector3i(1, 0, 1), Vector3i(2, 0, 1), Vector3i(3, 0, 1), Vector3i(3, 0, 2), Vector3i(3, 0, 3), Vector3i(2, 0, 3), Vector3i(1, 0, 3), Vector3i(1, 0, 2)]
		var sp: Vector3i = spots[i % spots.size()]
		b.put(Vector3i(o.x + sp.x, yy, o.z + sp.z), b.s("stone_brick_slab"))
	# corridor network (random walk of 5x5 corridors and rooms)
	var cur := o + Vector3i(2, 0, 2)
	var dirs := [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]
	var d: Vector3i = dirs[r.next_int_bound(4)]
	var steps := 10 + r.next_int_bound(6)
	for i in steps:
		var ln := 7 + r.next_int_bound(9)
		var a := cur + Vector3i(-2, 0, -2)
		var e := cur + d * ln + Vector3i(2, 4, 2)
		b.room(Vector3i(mini(a.x, e.x), a.y, mini(a.z, e.z)), Vector3i(maxi(a.x, e.x), e.y, maxi(a.z, e.z)), wall)
		cur += d * ln
		var kind := r.next_int_bound(6)
		if kind == 0:
			# library
			var la := cur + Vector3i(-7, 0, -7)
			b.room(la, la + Vector3i(14, 6, 14), wall)
			for z in range(la.z + 1, la.z + 14):
				b.put(Vector3i(la.x + 1, la.y + 1, z), b.s("bookshelf"))
				b.put(Vector3i(la.x + 1, la.y + 2, z), b.s("bookshelf"))
				b.put(Vector3i(la.x + 13, la.y + 1, z), b.s("bookshelf"))
				b.put(Vector3i(la.x + 13, la.y + 2, z), b.s("bookshelf"))
			b.chest(la + Vector3i(7, 1, 2), "chests/stronghold_library")
		elif kind == 1:
			var ra := cur + Vector3i(-4, 0, -4)
			b.room(ra, ra + Vector3i(8, 6, 8), wall)
			b.chest(ra + Vector3i(4, 1, 4), "chests/stronghold_crossing")
		elif kind == 2:
			b.put(cur + Vector3i(0, 1, 0), b.s("torch"))
		if r.next_int_bound(3) == 0:
			d = dirs[r.next_int_bound(4)]
	# portal room at the end
	var pr := cur + d * 3 + Vector3i(-5, 0, -7)
	b.room(pr, pr + Vector3i(10, 7, 15), wall)
	for x in range(pr.x + 1, pr.x + 10):
		for z in range(pr.z + 1, pr.z + 15):
			b.put(Vector3i(x, pr.y + 1, z), 0)
	# lava pool + stairs + frames
	var c := pr + Vector3i(5, 3, 8)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			b.put(c + Vector3i(dx, -1, dz), b.s("lava"))
	var frame := b.s("end_portal_frame")
	var ring := [[Vector3i(-1, 0, -2), "south"], [Vector3i(0, 0, -2), "south"], [Vector3i(1, 0, -2), "south"], [Vector3i(-1, 0, 2), "north"], [Vector3i(0, 0, 2), "north"], [Vector3i(1, 0, 2), "north"],
		[Vector3i(-2, 0, -1), "east"], [Vector3i(-2, 0, 0), "east"], [Vector3i(-2, 0, 1), "east"], [Vector3i(2, 0, -1), "west"], [Vector3i(2, 0, 0), "west"], [Vector3i(2, 0, 1), "west"]]
	var all_eyes := true
	for e2 in ring:
		var eye := r.next_float() > 0.9
		all_eyes = all_eyes and eye
		b.put(c + e2[0], b.reg.with_prop(b.reg.with_prop(frame, "facing", e2[1]), "eye", "true" if eye else "false"))
	if all_eyes:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				b.put(c + Vector3i(dx, 0, dz), b.s("end_portal"))
	for i in 3:
		b.put(c + Vector3i(0, -2 + i, -4 - i), b.s("stone_brick_stairs"))
	b.spawner(pr + Vector3i(5, 2, 13), "silverfish")
	return b.result(c)


static func _fortress(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var nb := b.s("nether_bricks")
	var fence := b.s("nether_brick_fence")
	var y := 48 + r.next_int_bound(23)
	var o := Vector3i(sc.x * 16 + 2, y, sc.y * 16 + 2)
	var cur := o
	var dirs := [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]
	var d: Vector3i = dirs[r.next_int_bound(4)]
	for i in 8 + r.next_int_bound(6):
		var ln := 10 + r.next_int_bound(10)
		for k in ln:
			var p := cur + d * k
			var side := Vector3i(d.z, 0, d.x)
			for w in range(-2, 3):
				b.put(p + side * w, nb)
				b.put(p + side * w + Vector3i(0, 1, 0), fence if absi(w) == 2 else 0)
				for hgt in range(2, 5):
					b.put(p + side * w + Vector3i(0, hgt, 0), 0)
			# support pillars
			if k % 6 == 0:
				for py in range(1, 20):
					b.put(p + Vector3i(0, -py, 0), nb)
		cur += d * ln
		var room := r.next_int_bound(4)
		if room == 0:
			var a := cur + Vector3i(-3, 0, -3)
			b.fill(a, a + Vector3i(6, 0, 6), nb)
			b.spawner(cur + Vector3i(0, 1, 0), "blaze")
			for x in range(-3, 4):
				b.put(cur + Vector3i(x, 1, -3), fence)
				b.put(cur + Vector3i(x, 1, 3), fence)
		elif room == 1:
			var a2 := cur + Vector3i(-4, 0, -4)
			b.fill(a2, a2 + Vector3i(8, 0, 8), nb)
			for x in range(-2, 3):
				b.put(cur + Vector3i(x, 0, 0), b.s("soul_sand"))
				b.put(cur + Vector3i(x, 1, 0), b.reg.with_prop(b.s("nether_wart"), "age", str(r.next_int_bound(4))))
			b.chest(cur + Vector3i(3, 1, 3), "chests/nether_bridge")
		if r.next_int_bound(2) == 0:
			d = dirs[r.next_int_bound(4)]
	return b.result(o)


static func _mineshaft(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var mesa := str(cfg.get("mineshaft_type", "normal")) == "mesa"
	var plank := b.s("dark_oak_planks" if mesa else "oak_planks")
	var fence := b.s("dark_oak_fence" if mesa else "oak_fence")
	var y := (st.gen.sea_level - 10 - r.next_int_bound(30)) if not mesa else st.gen.sea_level + r.next_int_bound(20)
	y = maxi(y, st.gen.gen_min_y + 12)
	var o := Vector3i(sc.x * 16 + 8, y, sc.y * 16 + 8)
	b.begin_part()   # room
	b.fill(o + Vector3i(-4, 0, -4), o + Vector3i(4, 4, 4), 0)
	b.fill(o + Vector3i(-4, -1, -4), o + Vector3i(4, -1, 4), b.s("dirt"))
	var dirs := [Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]
	var stack: Array = [[o, dirs[0], 0], [o, dirs[1], 0], [o, dirs[2], 0], [o, dirs[3], 0]]
	var budget := 30
	while not stack.is_empty() and budget > 0:
		budget -= 1
		var e: Array = stack.pop_back()
		var cur: Vector3i = e[0]
		var d: Vector3i = e[1]
		var depth: int = e[2]
		var ln := 10 + r.next_int_bound(20)
		var side := Vector3i(d.z, 0, d.x)
		b.begin_part()   # corridor
		for k in ln:
			var p := cur + d * k
			for w in range(-1, 2):
				for h in range(0, 3):
					b.put(p + side * w + Vector3i(0, h, 0), 0)
			if k % 4 == 0:
				b.put(p + side * -1, fence)
				b.put(p + side * -1 + Vector3i(0, 1, 0), fence)
				b.put(p + side * 1, fence)
				b.put(p + side * 1 + Vector3i(0, 1, 0), fence)
				for w2 in range(-1, 2):
					b.put(p + side * w2 + Vector3i(0, 2, 0), plank)
			elif r.next_int_bound(3) == 0:
				b.put(p, b.reg.with_prop(b.s("rail"), "shape", "east_west" if d.x != 0 else "north_south"))
			if r.next_int_bound(40) == 0:
				b.put(p + side * w_rand(r) + Vector3i(0, 2, 0), b.s("cobweb"))
			if r.next_int_bound(100) == 0:
				b.chest(p + side, "chests/abandoned_mineshaft")
		if r.next_int_bound(23) == 0 and not mesa:
			b.spawner(cur + d * (ln / 2), "cave_spider")
		var end := cur + d * ln
		if depth < 6:
			stack.append([end, d, depth + 1])
			if r.next_int_bound(3) == 0:
				stack.append([end, Vector3i(d.z, 0, -d.x), depth + 1])
			if r.next_int_bound(3) == 0:
				stack.append([end, Vector3i(-d.z, 0, d.x), depth + 1])
	var res := b.result(o)
	if not res.is_empty():
		res["dry"] = true   # parts touching liquid are skipped per chunk, nothing replaces liquid (structures.gd _place_start)
	return res


static func w_rand(r: RandomSources.LegacyRandom) -> int:
	return r.next_int_bound(3) - 1


static func _desert_pyramid(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var o := Vector3i(sc.x * 16, st.first_free_height(sc.x * 16 + 10, sc.y * 16 + 10) - 1, sc.y * 16)
	var ss := b.s("sandstone")
	for lvl in 10:
		b.fill(o + Vector3i(lvl, lvl, lvl), o + Vector3i(20 - lvl, lvl, 20 - lvl), ss)
		if lvl > 0 and lvl < 9:
			b.fill(o + Vector3i(lvl + 1, lvl, lvl + 1), o + Vector3i(19 - lvl, lvl, 19 - lvl), 0 if lvl < 5 else ss)
	b.fill(o + Vector3i(1, -14, 1), o + Vector3i(19, -1, 19), ss)
	b.fill(o + Vector3i(8, -13, 8), o + Vector3i(12, -10, 12), 0)
	b.put(o + Vector3i(10, -14, 10), b.s("stone_pressure_plate") if false else b.s("tnt"))
	b.chest(o + Vector3i(10, -13, 8), "chests/desert_pyramid", "south")
	b.chest(o + Vector3i(10, -13, 12), "chests/desert_pyramid", "north")
	b.chest(o + Vector3i(8, -13, 10), "chests/desert_pyramid", "east")
	b.chest(o + Vector3i(12, -13, 10), "chests/desert_pyramid", "west")
	b.fill(o + Vector3i(10, -9, 10), o + Vector3i(10, 0, 10), 0)
	b.put(o + Vector3i(10, 0, 10), b.s("blue_terracotta"))
	return b.result(o + Vector3i(10, 0, 10))


static func _jungle_temple(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var o := Vector3i(sc.x * 16, st.first_free_height(sc.x * 16 + 6, sc.y * 16 + 7) - 1, sc.y * 16)
	var wall := func(_p: Vector3i) -> int: return b.s("mossy_cobblestone") if r.next_float() < 0.4 else b.s("cobblestone")
	b.room(o + Vector3i(0, -4, 0), o + Vector3i(11, 4, 14), wall)
	b.room(o + Vector3i(2, 4, 2), o + Vector3i(9, 9, 12), wall)
	b.chest(o + Vector3i(8, -3, 3), "chests/jungle_temple", "west")
	b.chest(o + Vector3i(9, -3, 10), "chests/jungle_temple", "north")
	b.put(o + Vector3i(3, -3, 6), b.reg.with_prop(b.s("dispenser"), "facing", "south"))
	b.bes[o + Vector3i(3, -3, 6)] = {"id": "dispenser", "loot_table": "chests/jungle_temple_dispenser"}
	for dz in range(5, 9):
		b.put(o + Vector3i(5, 0, dz), 0)
		b.put(o + Vector3i(6, 0, dz), 0)
	return b.result(o + Vector3i(6, 0, 7))


static func _swamp_hut(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var o := Vector3i(sc.x * 16, st.first_free_height(sc.x * 16 + 3, sc.y * 16 + 4), sc.y * 16)
	var plank := b.s("spruce_planks")
	var log_ := b.s("oak_log")
	for p in [Vector3i(1, 0, 2), Vector3i(5, 0, 2), Vector3i(1, 0, 7), Vector3i(5, 0, 7)]:
		for yy in range(-3, 4):
			b.put(o + p + Vector3i(0, yy, 0), log_)
	b.fill(o + Vector3i(1, 1, 1), o + Vector3i(5, 1, 7), plank)
	var wall := func(_p: Vector3i) -> int: return plank
	b.room(o + Vector3i(1, 1, 2), o + Vector3i(5, 5, 7), wall)
	b.put(o + Vector3i(3, 3, 2), 0)
	b.put(o + Vector3i(3, 2, 2), 0)
	b.put(o + Vector3i(4, 2, 6), b.s("cauldron"))
	b.put(o + Vector3i(2, 2, 6), b.s("crafting_table"))
	b.put(o + Vector3i(2, 3, 6), b.s("potted_red_mushroom"))
	return b.result(o + Vector3i(3, 2, 4))


static func _buried_treasure(st: Structures, sc: Vector2i) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var x := sc.x * 16 + 9
	var z := sc.y * 16 + 9
	var y := st.first_free_height(x, z, true) - 2
	b.fill(Vector3i(x - 1, y - 1, z - 1), Vector3i(x + 1, y - 1, z + 1), b.s("sandstone"))
	b.chest(Vector3i(x, y, z), "chests/buried_treasure")
	return b.result(Vector3i(x, y, z))


static func _monument(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var o := Vector3i(sc.x * 16 - 29, 39, sc.y * 16 - 29)
	var pr := b.s("prismarine")
	var pb := b.s("prismarine_bricks")
	var dp := b.s("dark_prismarine")
	var sea := b.s("sea_lantern")
	var water := b.s("water")
	for yy in 23:
		var inset := maxi(0, yy - 12)
		for z in range(inset, 58 - inset):
			for x in range(inset, 58 - inset):
				var edge := x == inset or x == 57 - inset or z == inset or z == 57 - inset or yy == 0 or yy == 22
				var p := o + Vector3i(x, yy, z)
				if edge:
					b.put(p, sea if (x % 8 == 0 and z % 8 == 0) else (pb if yy % 4 == 0 else pr))
				elif yy == 8 or yy == 16:
					b.put(p, dp if (x + z) % 5 != 0 else water)
				else:
					b.put(p, water)
	for dz in range(26, 32):
		for dx in range(26, 32):
			for dy in range(9, 11):
				b.put(o + Vector3i(dx, dy, dz), b.s("gold_block") if dy == 10 and dx in [28, 29] and dz in [28, 29] else dp)
	return b.result(o + Vector3i(29, 11, 29))
