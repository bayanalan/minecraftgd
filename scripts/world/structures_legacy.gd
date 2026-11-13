## StructuresLegacy — non-jigsaw structures. Template-based (game .nbt templates): igloo, shipwreck (+beached),
## ruined_portal (+nether), nether_fossil, ocean_ruin, end_city (EndCityPieces recursion). StructurePiece code ported
## in JavaPieces: stronghold, fortress, ocean monument, mineshaft, desert pyramid, jungle temple, swamp hut, buried
## treasure. woodland_mansion: MansionPieces (WoodlandMansionPieces grid + piece placer).
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
			return JavaPieces.stronghold(st, sc)
		"fortress":
			return JavaPieces.fortress(st, sc, r)
		"mineshaft":
			return JavaPieces.mineshaft(st, cfg, sc, r)   # Java MineshaftPieces
		"desert_pyramid", "jungle_temple", "swamp_hut":
			return JavaPieces.scattered(st, t, sc, r)   # Java DesertPyramidPiece / JungleTemplePiece / SwampHutPiece
		"buried_treasure":
			return JavaPieces.buried_treasure(sc)   # Java BuriedTreasurePieces
		"ocean_monument":
			return JavaPieces.monument(st, sc, r)
	return {}


static func _tpl_piece(loc: String, pos: Vector3i, rot: int, procs: Array = [], ignore_air: bool = true) -> Dictionary:
	var tpl := StructureTemplate.get_template(loc)
	if tpl == null:
		return {}
	var el := {"t": "single", "loc": loc, "legacy": ignore_air, "proj": "rigid", "procs": procs}
	return {"el": el, "pos": pos, "rot": rot, "box": tpl.box(pos, rot)}


## Marks template pieces for TemplateStructurePiece.handleDataMarker (StructureTemplate._data_marker kinds).
static func _with_markers(pieces: Array, kind: String) -> Array:
	for p in pieces:
		if not (p as Dictionary).is_empty():
			p["el"]["markers"] = kind
	return pieces


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
	return _pieces_result(_with_markers(pieces, "igloo"), Vector3i(cx, y, cz))


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
	return _pieces_result(_with_markers([_tpl_piece(loc, _centered(loc, Vector3i(cx, y, cz), rot), rot)], "shipwreck"), Vector3i(cx, y, cz))


## Java RuinedPortalStructure.findGenerationPoint: setup (weighted), air pocket, template (5 % giant), rotation, mirror,
## pivot = template centre; y from the placement (findSuitableY: the highest y at or below the placement's y where 3 of
## the box's 4 corner columns hold a block, from the noise-stage base columns); the biome test is on the stub position
## (chunk corner at that y), done here because y depends on the random. Returns the start with one ruined_portal piece.
static func _ruined_portal(st: Structures, cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var setups: Array = cfg.get("setups", [{}])
	var setup: Dictionary = setups[0]
	if setups.size() > 1:
		var tot := 0.0
		for s in setups:
			tot += float(s.get("weight", 1.0))
		var fsel := r.next_float()
		setup = setups[setups.size() - 1]
		for s in setups:
			fsel -= float(s.get("weight", 1.0)) / tot
			if fsel < 0.0:
				setup = s
				break
	var app := float(setup.get("air_pocket_probability", 0.0))
	var air_pocket := app >= 1.0 or (app > 0.0 and r.next_float() < app)
	var placement := str(setup.get("placement", "on_land_surface"))
	var loc := ""
	if r.next_float() < 0.05:
		loc = "ruined_portal/giant_portal_%d" % (r.next_int_bound(3) + 1)
	else:
		loc = "ruined_portal/portal_%d" % (r.next_int_bound(10) + 1)
	var tpl := StructureTemplate.get_template(loc)
	if tpl == null:
		return {}
	var rot := r.next_int_bound(4)
	var mirror := 1 if r.next_float() >= 0.5 else 0   # Mirror.FRONT_BACK
	var pivot := Vector3i(tpl.size.x / 2, 0, tpl.size.z / 2)
	var origin := Vector3i(sc.x * 16, 0, sc.y * 16)
	var bb := tpl.box_m(origin, rot, mirror, pivot)
	var bmin: Vector3i = bb[0]
	var bmax: Vector3i = bb[1]
	var ctr := Vector3i(bmin.x + (bmax.x - bmin.x + 1) / 2, 0, bmin.z + (bmax.z - bmin.z + 1) / 2)
	var ocean := placement == "on_ocean_floor"
	var surface_y := st.base_height(ctr.x, ctr.z, ocean) - 1
	var y := _rp_find_y(st, r, placement, air_pocket, surface_y, bmax.y - bmin.y + 1, bmin, bmax)
	var pos := Vector3i(origin.x, y, origin.z)
	if not (cfg.get("biomes", {}) as Dictionary).has(st.biome_id_at(pos.x, pos.y, pos.z)):
		return {}
	var cold := false
	if bool(setup.get("can_be_cold", false)):
		cold = st.gen.biome_temperature_at(st.biome_id_at(pos.x, pos.y, pos.z), pos.x, pos.y, pos.z) < 0.15
	var blocks := st.gen.blocks
	# RuinedPortalPiece.makeSettings: ignore (air kept only with an air pocket), rules, block age, protected blocks,
	# lava-submerged blocks, blackstone
	var rules: Array = [[{"t": "rblock", "id": blocks.block_id("gold_block"), "p": 0.3}, {"t": "true"}, 0]]
	var lava_id := blocks.block_id("lava")
	if ocean:
		rules.append([{"t": "block", "id": lava_id}, {"t": "true"}, blocks.default_state("magma_block")])
	elif cold:
		rules.append([{"t": "block", "id": lava_id}, {"t": "true"}, blocks.default_state("netherrack")])
	else:
		rules.append([{"t": "rblock", "id": lava_id, "p": 0.2}, {"t": "true"}, blocks.default_state("magma_block")])
	if not cold:
		rules.append([{"t": "rblock", "id": blocks.block_id("netherrack"), "p": 0.07}, {"t": "true"}, blocks.default_state("magma_block")])
	var prot := {}
	for nm in Tags.blocks("#minecraft:features_cannot_replace"):
		prot[blocks.block_id(nm)] = true
	var procs: Array = [{"t": "rule", "rules": rules}, {"t": "age", "moss": float(setup.get("mossiness", 0.0))},
		{"t": "protect", "ids": prot}, {"t": "lava_sub"}]
	if bool(setup.get("replace_with_blackstone", false)):
		procs.append({"t": "blackstone"})
	var pbox := tpl.box_m(pos, rot, mirror, pivot)
	var el := {"t": "ruined_portal", "loc": loc, "legacy": not air_pocket, "proj": "rigid", "procs": procs, "mirror": mirror,
		"pivot": pivot, "placement": placement, "cold": cold, "overgrown": bool(setup.get("overgrown", false)),
		"vines": bool(setup.get("vines", false)), "tbox": pbox, "seed": RandomSources.pos_seed(pos.x, pos.y, pos.z) ^ st.gen.seed}
	# the piece's reach: the template plus the netherrack spread around its centre (14) and drip columns below it
	var pc: Vector3i = (pbox[0] + pbox[1]) / 2
	var reach := [Vector3i(mini(pbox[0].x, pc.x - 14), pbox[0].y - 12, mini(pbox[0].z, pc.z - 14)), Vector3i(maxi(pbox[1].x, pc.x + 14), pbox[1].y + 1, maxi(pbox[1].z, pc.z + 14))]
	return _pieces_result([{"el": el, "pos": pos, "rot": rot, "box": reach}], pos)


static func _rp_between(r: RandomSources.LegacyRandom, a: int, b: int) -> int:
	return r.next_int_bound(b - a + 1) + a


## RuinedPortalStructure.findSuitableY.
static func _rp_find_y(st: Structures, r: RandomSources.LegacyRandom, placement: String, air_pocket: bool, surface_y: int, yspan: int, bmin: Vector3i, bmax: Vector3i) -> int:
	var min_y := st.gen.gen_min_y + 15
	var y := surface_y
	match placement:
		"in_nether":
			if air_pocket:
				y = _rp_between(r, 32, 100)
			elif r.next_float() < 0.5:
				y = _rp_between(r, 27, 29)
			else:
				y = _rp_between(r, 29, 100)
		"in_mountain":
			var hi := surface_y - yspan
			y = _rp_between(r, 70, hi) if 70 < hi else hi
		"underground":
			var hi2 := surface_y - yspan
			y = _rp_between(r, min_y, hi2) if min_y < hi2 else hi2
		"partly_buried":
			y = surface_y - yspan + _rp_between(r, 2, 8)
	var cols: Array = [st.base_column(bmin.x, bmin.z), st.base_column(bmax.x, bmin.z), st.base_column(bmin.x, bmax.z), st.base_column(bmax.x, bmax.z)]
	var ocean := placement == "on_ocean_floor"
	var yy := y
	while yy > min_y:
		var n := 0
		var i := yy - st.gen.gen_min_y
		for col in cols:
			var k: int = (col as PackedByteArray)[i] if i >= 0 and i < (col as PackedByteArray).size() else 0
			if (k == 1) if ocean else (k != 0):
				n += 1
				if n == 3:
					return yy
		yy -= 1
	return yy


const RP_SPREAD := [1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 0.9, 0.9, 0.8, 0.7, 0.6, 0.4, 0.2]
const RP_DIRS := [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]
const RP_DIR_NAMES := ["north", "east", "south", "west"]


## RuinedPortalPiece placement + postProcess, clipped to this chunk: the template, then the netherrack / magma spread
## around the portal (spreadNetherrack), drip columns under its netherrack floor, vines and leaves. Java draws these
## from the decorating chunk's random in one pass; chunks here are placed in parallel, so each column / block uses
## its own random from the start seed - every chunk computes the same blocks for the columns it owns.
static func place_ruined_portal(st: Structures, c: Features.FCtx, el: Dictionary, pos: Vector3i, rot: int, cmin: Vector3i, cmax: Vector3i) -> void:
	var f := st.f
	var tpl := StructureTemplate.get_template(str(el["loc"]))
	if tpl == null:
		return
	tpl.place(f, c, pos, rot, el["procs"], bool(el["legacy"]), false, cmin, cmax, 0, int(el["mirror"]), el["pivot"])
	var blocks := f.blocks
	var bb: Array = el["tbox"]
	var bmin: Vector3i = bb[0]
	var bmax: Vector3i = bb[1]
	var seed := int(el["seed"])
	var placement := str(el["placement"])
	var cold := bool(el["cold"])
	var overgrown := bool(el["overgrown"])
	var nr := blocks.default_state("netherrack")
	var magma := blocks.default_state("magma_block")
	var nr_id := blocks.block_id("netherrack")
	var obs_id := blocks.block_id("obsidian")
	var lava_id := blocks.block_id("lava")
	var prot := Tags.blocks("#minecraft:features_cannot_replace")
	var leaves := blocks.with_prop(blocks.default_state("jungle_leaves"), "persistent", "true")
	var place_nm := func(rr: RandomSources.LegacyRandom, p: Vector3i) -> void:
		f.set_block(c, p, magma if (not cold and rr.next_float() < 0.07) else nr)
	var drip := func(rr: RandomSources.LegacyRandom, p: Vector3i) -> void:
		var q := p
		place_nm.call(rr, q)
		var n := 8
		while n > 0 and rr.next_float() < 0.5:
			q.y -= 1
			n -= 1
			place_nm.call(rr, q)
	var leaves_above := func(rr: RandomSources.LegacyRandom, p: Vector3i) -> void:
		if rr.next_float() < 0.5 and blocks.st_block[maxi(0, f.get_block(c, p))] == nr_id and f.get_block(c, p + Vector3i(0, 1, 0)) == 0:
			f.set_block(c, p + Vector3i(0, 1, 0), leaves)
	var inside := func(x: int, z: int) -> bool:
		return x >= cmin.x and x <= cmax.x and z >= cmin.z and z <= cmax.z
	# spreadNetherrack
	var surf_follow := placement == "on_land_surface" or placement == "on_ocean_floor"
	var ctr := Vector3i(bmin.x + (bmax.x - bmin.x + 1) / 2, 0, bmin.z + (bmax.z - bmin.z + 1) / 2)
	var k := ((bmax.x - bmin.x + 1) + (bmax.z - bmin.z + 1)) / 2
	var r0 := RandomSources.LegacyRandom.new(seed)
	var l := r0.next_int_bound(maxi(1, 8 - k / 2))
	var n := RP_SPREAD.size()
	for x in range(ctr.x - n, ctr.x + n + 1):
		for z in range(ctr.z - n, ctr.z + n + 1):
			if not inside.call(x, z):
				continue
			var e := maxi(0, absi(x - ctr.x) + absi(z - ctr.z) + l)
			if e >= n:
				continue
			var rr := RandomSources.LegacyRandom.new(RandomSources.pos_seed(x, 0, z) ^ seed)
			if rr.next_double() >= float(RP_SPREAD[e]):
				continue
			var y := _rp_surface_y(f, c, x, z, placement, bmax.y)
			var y2 := y if surf_follow else mini(bmin.y, y)
			var mp := Vector3i(x, y2, z)
			if absi(y2 - bmin.y) > 3:
				continue
			var cur := f.get_block(c, mp)
			if cur <= 0:
				continue
			var cb := blocks.st_block[cur]
			if cb == obs_id or prot.has(blocks.name_of(cur)) or (placement != "in_nether" and cb == lava_id):
				continue
			place_nm.call(rr, mp)
			if overgrown:
				leaves_above.call(rr, mp)
			drip.call(rr, mp + Vector3i(0, -1, 0))
	# addNetherrackDripColumnsBelowPortal
	for x in range(bmin.x + 1, bmax.x):
		for z in range(bmin.z + 1, bmax.z):
			if not inside.call(x, z):
				continue
			var p := Vector3i(x, bmin.y, z)
			var s0 := f.get_block(c, p)
			if s0 > 0 and blocks.st_block[s0] == nr_id:
				drip.call(RandomSources.LegacyRandom.new(RandomSources.pos_seed(x, bmin.y - 1, z) ^ seed), p + Vector3i(0, -1, 0))
	# vines / leaves over the piece box
	var vines := bool(el["vines"])
	if not (vines or overgrown):
		return
	var vine := blocks.default_state("vine")
	var vine_id := blocks.block_id("vine")
	for y in range(bmin.y, bmax.y + 1):
		for z in range(bmin.z - 1, bmax.z + 2):
			for x in range(bmin.x - 1, bmax.x + 2):
				var p2 := Vector3i(x, y, z)
				var rr2 := RandomSources.LegacyRandom.new(RandomSources.pos_seed(x, y, z) ^ seed)
				var in_box := x >= bmin.x and x <= bmax.x and z >= bmin.z and z <= bmax.z
				if vines and in_box:
					var s1 := f.get_block(c, p2)
					var di := rr2.next_int_bound(4)
					var q: Vector3i = p2 + RP_DIRS[di]
					if s1 > 0 and blocks.st_block[s1] != vine_id and inside.call(q.x, q.z) and f.get_block(c, q) == 0:
						var fl := blocks.st_flags[s1]
						if (fl & BlockRegistry.F_FULL_SHAPE) and (fl & BlockRegistry.F_COLLIDE):
							f.set_block(c, q, blocks.with_prop(vine, RP_DIR_NAMES[(di + 2) % 4], "true"))
				if overgrown and in_box and inside.call(x, z):
					leaves_above.call(rr2, p2)


## getSurfaceY: the WORLD_SURFACE_WG (OCEAN_FLOOR_WG on the ocean floor) height - 1, counting this chunk's placed
## blocks (Java's worldgen heightmaps follow the blocks the template just placed).
static func _rp_surface_y(f: Features, c: Features.FCtx, x: int, z: int, placement: String, top: int) -> int:
	var ocean := placement == "on_ocean_floor"
	var h := f.height(c, "OCEAN_FLOOR_WG" if ocean else "WORLD_SURFACE_WG", x, z) - 1
	for y in range(top + 1, h, -1):
		var s := f.get_block(c, Vector3i(x, y, z))
		if s > 0 and (not ocean or (f.blocks.st_flags[s] & BlockRegistry.F_COLLIDE) != 0):
			return y
	return h

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
	return _pieces_result(_with_markers([_tpl_piece(loc, _centered(loc, Vector3i(cx, y, cz), rot), rot, procs)], "ocean_ruin_big" if big else "ocean_ruin_small"), Vector3i(cx, y, cz))


## Java EndCityStructure + EndCityPieces: random rotation, the start 7 blocks into the chunk at the lowest of the
## 5 x 5 box corners (nothing below y 60), base floor + second / third floor + roof, then the recursive section
## generators (tower, tower bridge with the one ship, house tower, fat tower) with their collision rule (a batch is
## dropped when it hits a piece of another batch). Pieces are templates; data markers give chest loot, shulkers and
## the elytra frame (StructureTemplate._data_marker).
const EC_TOWER_BRIDGES := [[0, Vector3i(1, -1, 0)], [1, Vector3i(6, -1, 1)], [3, Vector3i(0, -1, 5)], [2, Vector3i(5, -1, 6)]]
const EC_FAT_BRIDGES := [[0, Vector3i(4, -1, 0)], [1, Vector3i(12, -1, 4)], [3, Vector3i(0, -1, 8)], [2, Vector3i(8, -1, 12)]]


static func _end_city(st: Structures, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var rot := r.next_int_bound(4)
	var i := 5
	var j := 5
	match rot:
		1:
			i = -5
		2:
			i = -5
			j = -5
		3:
			j = -5
	var k := sc.x * 16 + 7
	var l := sc.y * 16 + 7
	var lo := 1 << 30
	for cxz in [Vector2i(k, l), Vector2i(k, l + j), Vector2i(k + i, l), Vector2i(k + i, l + j)]:
		lo = mini(lo, st.base_height(cxz.x, cxz.y, false) - 1)
	if lo < 60:
		return {}
	var start := Vector3i(k, lo, l)
	var pieces: Array = []
	var gens := {"ship": false}
	var p := _ec_new(pieces, "base_floor", start, rot, true)
	p = _ec_add(pieces, _ec_child(p, Vector3i(-1, 0, -1), "second_floor_1", rot, false))
	p = _ec_add(pieces, _ec_child(p, Vector3i(-1, 4, -1), "third_floor_1", rot, false))
	p = _ec_add(pieces, _ec_child(p, Vector3i(-1, 8, -1), "third_roof", rot, true))
	_ec_recursive(r, gens, "tower", 1, p, null, pieces)
	var out: Array = []
	for pc in pieces:
		out.append(_tpl_piece("end_city/" + str(pc["loc"]), pc["pos"], int(pc["rot"]), [], not bool(pc["ow"])))
	return _pieces_result(_with_markers(out, "end_city"), start)


static func _ec_new(pieces: Array, loc: String, pos: Vector3i, rot: int, ow: bool) -> Dictionary:
	var pc := _ec_piece(loc, pos, rot, ow)
	pieces.append(pc)
	return pc


static func _ec_piece(loc: String, pos: Vector3i, rot: int, ow: bool) -> Dictionary:
	var tpl := StructureTemplate.get_template("end_city/" + loc)
	var bx: Array = tpl.box(pos, rot) if tpl != null else [pos, pos]
	return {"loc": loc, "pos": pos, "rot": rot, "ow": ow, "box": bx, "gd": 0}


## EndCityPieces.addPiece: the child template at the parent's position + the offset turned by the parent's rotation
## (calculateConnectedPosition with a zero child anchor).
static func _ec_child(parent: Dictionary, off: Vector3i, loc: String, rot: int, ow: bool) -> Dictionary:
	return _ec_piece(loc, parent["pos"] + StructureTemplate.transform(off, int(parent["rot"])), rot, ow)


static func _ec_add(lst: Array, pc: Dictionary) -> Dictionary:
	lst.append(pc)
	return pc


static func _ec_hit(pieces: Array, bx: Array) -> Dictionary:
	for o in pieces:
		var ob: Array = o["box"]
		if bx[1].x >= ob[0].x and bx[0].x <= ob[1].x and bx[1].y >= ob[0].y and bx[0].y <= ob[1].y and bx[1].z >= ob[0].z and bx[0].z <= ob[1].z:
			return o
	return {}


static func _ec_recursive(r: RandomSources.LegacyRandom, gens: Dictionary, gen: String, depth: int, parent: Dictionary, pos, pieces: Array) -> bool:
	if depth > 8:
		return false
	var lst: Array = []
	var ok := false
	match gen:
		"tower":
			ok = _ec_tower(r, gens, depth, parent, lst)
		"bridge":
			ok = _ec_bridge(r, gens, depth, parent, lst)
		"house":
			ok = _ec_house(r, gens, depth, parent, pos, lst)
		"fat":
			ok = _ec_fat(r, gens, depth, parent, lst)
	if not ok:
		return false
	var gd := r.next_int()
	for sp in lst:
		sp["gd"] = gd
		var hit := _ec_hit(pieces, sp["box"])
		if not hit.is_empty() and int(hit["gd"]) != int(parent["gd"]):
			return false
	pieces.append_array(lst)
	return true


static func _ec_house(r: RandomSources.LegacyRandom, gens: Dictionary, depth: int, parent: Dictionary, pos: Vector3i, lst: Array) -> bool:
	if depth > 8:
		return false
	var rot: int = parent["rot"]
	var p := _ec_add(lst, _ec_child(parent, pos, "base_floor", rot, true))
	var i := r.next_int_bound(3)
	if i == 0:
		_ec_add(lst, _ec_child(p, Vector3i(-1, 4, -1), "base_roof", rot, true))
	elif i == 1:
		p = _ec_add(lst, _ec_child(p, Vector3i(-1, 0, -1), "second_floor_2", rot, false))
		p = _ec_add(lst, _ec_child(p, Vector3i(-1, 8, -1), "second_roof", rot, false))
		_ec_recursive(r, gens, "tower", depth + 1, p, null, lst)
	else:
		p = _ec_add(lst, _ec_child(p, Vector3i(-1, 0, -1), "second_floor_2", rot, false))
		p = _ec_add(lst, _ec_child(p, Vector3i(-1, 4, -1), "third_floor_2", rot, false))
		p = _ec_add(lst, _ec_child(p, Vector3i(-1, 8, -1), "third_roof", rot, true))
		_ec_recursive(r, gens, "tower", depth + 1, p, null, lst)
	return true


static func _ec_tower(r: RandomSources.LegacyRandom, gens: Dictionary, depth: int, parent: Dictionary, lst: Array) -> bool:
	var rot: int = parent["rot"]
	var ox := 3 + r.next_int_bound(2)
	var oz := 3 + r.next_int_bound(2)
	var p := _ec_add(lst, _ec_child(parent, Vector3i(ox, -3, oz), "tower_base", rot, true))
	p = _ec_add(lst, _ec_child(p, Vector3i(0, 7, 0), "tower_piece", rot, true))
	var p1 = p if r.next_int_bound(3) == 0 else null
	var i := 1 + r.next_int_bound(3)
	for j in i:
		p = _ec_add(lst, _ec_child(p, Vector3i(0, 4, 0), "tower_piece", rot, true))
		if j < i - 1 and r.next_bool():
			p1 = p
	if p1 != null:
		for tb in EC_TOWER_BRIDGES:
			if r.next_bool():
				var p2 := _ec_add(lst, _ec_child(p1, tb[1], "bridge_end", (rot + int(tb[0])) % 4, true))
				_ec_recursive(r, gens, "bridge", depth + 1, p2, null, lst)
		_ec_add(lst, _ec_child(p, Vector3i(-1, 4, -1), "tower_top", rot, true))
	else:
		if depth != 7:
			return _ec_recursive(r, gens, "fat", depth + 1, p, null, lst)
		_ec_add(lst, _ec_child(p, Vector3i(-1, 4, -1), "tower_top", rot, true))
	return true


static func _ec_bridge(r: RandomSources.LegacyRandom, gens: Dictionary, depth: int, parent: Dictionary, lst: Array) -> bool:
	var rot: int = parent["rot"]
	var i := r.next_int_bound(4) + 1
	var p := _ec_add(lst, _ec_child(parent, Vector3i(0, 0, -4), "bridge_piece", rot, true))
	p["gd"] = -1
	var j := 0
	for k in i:
		if r.next_bool():
			p = _ec_add(lst, _ec_child(p, Vector3i(0, j, -4), "bridge_piece", rot, true))
			j = 0
		else:
			if r.next_bool():
				p = _ec_add(lst, _ec_child(p, Vector3i(0, j, -4), "bridge_steep_stairs", rot, true))
			else:
				p = _ec_add(lst, _ec_child(p, Vector3i(0, j, -8), "bridge_gentle_stairs", rot, true))
			j = 4
	if not bool(gens["ship"]) and r.next_int_bound(10 - depth) == 0:
		var sx := -8 + r.next_int_bound(8)
		var sz := -70 + r.next_int_bound(10)
		_ec_add(lst, _ec_child(p, Vector3i(sx, j, sz), "ship", rot, true))
		gens["ship"] = true
	elif not _ec_recursive(r, gens, "house", depth + 1, p, Vector3i(-3, j + 1, -11), lst):
		return false
	p = _ec_add(lst, _ec_child(p, Vector3i(4, j, 0), "bridge_end", (rot + 2) % 4, true))
	p["gd"] = -1
	return true


static func _ec_fat(r: RandomSources.LegacyRandom, gens: Dictionary, depth: int, parent: Dictionary, lst: Array) -> bool:
	var rot: int = parent["rot"]
	var p := _ec_add(lst, _ec_child(parent, Vector3i(-3, 4, -3), "fat_tower_base", rot, true))
	p = _ec_add(lst, _ec_child(p, Vector3i(0, 4, 0), "fat_tower_middle", rot, true))
	var i := 0
	while i < 2 and r.next_int_bound(3) != 0:
		p = _ec_add(lst, _ec_child(p, Vector3i(0, 8, 0), "fat_tower_middle", rot, true))
		for tb in EC_FAT_BRIDGES:
			if r.next_bool():
				var p1 := _ec_add(lst, _ec_child(p, tb[1], "bridge_end", (rot + int(tb[0])) % 4, true))
				_ec_recursive(r, gens, "bridge", depth + 1, p1, null, lst)
		i += 1
	_ec_add(lst, _ec_child(p, Vector3i(-2, 8, -2), "fat_tower_top", rot, true))
	return true


static func _buried_treasure(st: Structures, sc: Vector2i) -> Dictionary:
	var b := Builder.new()
	b.reg = st.gen.blocks
	var x := sc.x * 16 + 9
	var z := sc.y * 16 + 9
	var y := st.first_free_height(x, z, true) - 2
	b.fill(Vector3i(x - 1, y - 1, z - 1), Vector3i(x + 1, y - 1, z + 1), b.s("sandstone"))
	b.chest(Vector3i(x, y, z), "chests/buried_treasure")
	return b.result(Vector3i(x, y, z))

