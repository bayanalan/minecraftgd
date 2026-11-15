## RandomTickable — per-state random tick behaviours (crops, saplings, grass, leaves decay, ice/snow
## melt, sugar cane/cactus growth, fire). `ticks(st)` is a cached per-state flag used for section skipping.
class_name RandomTickable

static var _flag := PackedByteArray()


## Per-state flag table (1 = random-tickable), built on first use.
static func table() -> PackedByteArray:
	if _flag.size() != Res.blocks.total_states:
		_build()
	return _flag


static func ticks(st: int) -> bool:
	if _flag.size() != Res.blocks.total_states:
		_build()
	return _flag[st] == 1


static func _build() -> void:
	var blocks := Res.blocks
	_flag.resize(blocks.total_states)
	_flag.fill(0)
	for st in blocks.total_states:
		var n := blocks.names[blocks.st_block[st]]
		var t := false
		# (bamboo: its growth is not implemented yet - it was run through the sugar cane rule, which only thickened it)
		if n in ["wheat", "carrots", "potatoes", "beetroots", "grass_block", "mycelium", "sugar_cane", "cactus", "ice", "snow", "fire", "lava", "melon_stem", "pumpkin_stem", "sweet_berry_bush", "farmland", "kelp", "cocoa", "nether_wart", "torchflower_crop", "pitcher_crop"]:
			t = true
		elif n.ends_with("_sapling") or Growth.handles(n):
			t = true
		elif n.ends_with("_leaves") and blocks.get_prop(st, "persistent") == "false":
			t = true
		elif (n.contains("copper") or n.ends_with("lightning_rod")) and not n.begins_with("waxed") and not n.begins_with("oxidized") and not n.ends_with("_ore") and n != "raw_copper_block" and not n.ends_with("_torch"):
			# Java WeatheringCopper blocks only (ores, raw blocks and copper torches never random-tick)
			t = true
		_flag[st] = 1 if t else 0


static func _max_age(st: int) -> int:
	var blocks := Res.blocks
	for pr in blocks.block_props[blocks.st_block[st]]:
		if pr[0] == "age":
			return (pr[1] as PackedStringArray).size() - 1
	return 0


## wiki Light, internal sky light: the sky light level minus a darkening that is 0 at a clear noon, 3 at noon in rain, 5 in
## a thunderstorm and 11 at midnight (internal 15 / 12 / 10 / 4 under the open sky). world.sky_darken() is the 0.2..1
## brightness factor of the same day / rain / thunder curve; this turns it into that subtraction.
static func _sky_sub(world) -> int:
	return int((1.0 - (float(world.sky_darken()) - 0.2) / 0.8) * 11.0)


static var _farm_id := -2


## wiki Tutorial:Crop farming growth speed: own farmland 2 (dry) / 4 (hydrated), each of the 8 farmland around it +0.25
## (dry) / +0.75 (hydrated); halved when the same crop grows diagonally or both north-south and east-west of it.
static func _growth_speed(world, p: Vector3i, bid: int) -> float:
	var blocks := Res.blocks
	if _farm_id == -2:
		_farm_id = blocks.block_id("farmland")
	var f := 1.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var s: int = world.state_at(p.x + dx, p.y - 1, p.z + dz)
			if s > 0 and blocks.st_block[s] == _farm_id:
				var g := 3.0 if blocks.get_prop(s, "moisture") != "0" else 1.0
				f += g if (dx == 0 and dz == 0) else g * 0.25
	var ew := _is_block(world, p.x - 1, p.y, p.z, bid) or _is_block(world, p.x + 1, p.y, p.z, bid)
	var ns := _is_block(world, p.x, p.y, p.z - 1, bid) or _is_block(world, p.x, p.y, p.z + 1, bid)
	if (ew and ns) or _is_block(world, p.x - 1, p.y, p.z - 1, bid) or _is_block(world, p.x + 1, p.y, p.z - 1, bid) \
			or _is_block(world, p.x - 1, p.y, p.z + 1, bid) or _is_block(world, p.x + 1, p.y, p.z + 1, bid):
		f /= 2.0
	return f


static func _is_block(world, x: int, y: int, z: int, bid: int) -> bool:
	var s: int = world.state_at(x, y, z)
	return s > 0 and Res.blocks.st_block[s] == bid


const _H4 := [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const _H4_NAMES := ["north", "south", "west", "east"]
const _FRUIT_SOIL := ["dirt", "coarse_dirt", "rooted_dirt", "grass_block", "farmland", "podzol", "mycelium", "moss_block", "pale_moss_block", "mud", "muddy_mangrove_roots"]


## A grown melon / pumpkin stem's growth tick: one random side (wiki Tutorial:Crop farming: 1 free side = 1/4 of the
## growth chance); an empty cell over a block that supports the fruit (wiki Melon Seeds list, 26.3
## #supports_<fruit>_stem_fruit) gets the fruit and the stem becomes the attached stem facing it.
static func _stem_fruit(world, p: Vector3i, fruit: String, rng: RandomNumberGenerator) -> void:
	var blocks := Res.blocks
	var k := rng.randi_range(0, 3)
	var q: Vector3i = p + _H4[k]
	if world.state_at(q.x, q.y, q.z) != 0:
		return
	var bs: int = world.state_at(q.x, q.y - 1, q.z)
	if bs <= 0:
		return
	var bn := blocks.name_of(bs)
	var soil := Tags.blocks("supports_" + fruit + "_stem_fruit")
	if not (soil.has(bn) if not soil.is_empty() else _FRUIT_SOIL.has(bn)):
		return
	world.set_block(q.x, q.y, q.z, blocks.default_state(fruit))
	if blocks.block_id("attached_" + fruit + "_stem") >= 0:
		world.set_block(p.x, p.y, p.z, blocks.with_prop(blocks.default_state("attached_" + fruit + "_stem"), "facing", _H4_NAMES[k]))


static var _kind := PackedByteArray()   # per state: 1 grass_block / mycelium, 2 leaves, 0 generic path
static var _dirt := -1


## world.state_at without the call chain (same result: -1 when the chunk has no data, 0 outside the height range).
static func _st(chunks: Dictionary, x: int, y: int, z: int) -> int:
	var c: Chunk = chunks.get(((x >> 4) << 32) | ((z >> 4) & 0xFFFFFFFF))
	if c == null or c.state < Chunk.DATA_READY:
		return -1
	if y < -64 or y >= 320:
		return 0
	var sec: Chunk.Section = c.sections[(y + 64) >> 4]
	var spal := sec.pal
	if spal.size() == 1:
		return spal[0]
	var li := ((y & 15) << 8) | ((z & 15) << 4) | (x & 15)
	return spal[sec.wide[li]] if sec.wide.size() > 0 else spal[sec.idx[li]]


static func random_tick(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var blocks := Res.blocks
	if _kind.size() != blocks.total_states:
		var kt := PackedByteArray()
		kt.resize(blocks.total_states)
		for s0 in blocks.total_states:
			var n0 := blocks.names[blocks.st_block[s0]]
			kt[s0] = 1 if (n0 == "grass_block" or n0 == "mycelium") else (2 if n0.ends_with("_leaves") else (3 if n0 == "snow" else (4 if n0 == "ice" else (5 if not Copper.parse(n0).is_empty() else 0))))
		_kind = kt
		_dirt = blocks.default_state("dirt")
	var kd := _kind[st]
	if kd == 2:
		# leaves decay (no light needed); a leaf found supported stays supported until a log or leaf changes nearby
		var lc: Chunk = world.cm.chunks.get(((p.x >> 4) << 32) | ((p.z >> 4) & 0xFFFFFFFF))
		var lk := ((p.y + 64) << 8) | ((p.z & 15) << 4) | (p.x & 15)
		if lc != null and lc.leaf_ok.has(lk):
			return
		if _log_nearby(world, p, 6):
			if lc != null:
				lc.leaf_ok[lk] = true
		else:
			world.set_block(p.x, p.y, p.z, 0)
			for s in Loot.block_drops(st, null, world, p):
				world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), s)
		return
	if kd == 1:
		_grass_tick(world, p, st, rng)
		return
	if kd == 5:
		Copper.random_tick(world, p, st, rng)   # Java WeatheringCopper.randomTick
		return
	if kd == 3 or kd == 4:
		# Java SnowLayerBlock / IceBlock.randomTick: melt when the BLOCK light at the block itself exceeds 11 (ice: 11 - its
		# light block 1); nearly every tick is a no-op, so no name lookup / match here
		var bl: int = world.cm.get_light(p.x, p.y, p.z) & 15
		if bl > (11 if kd == 3 else 10):
			if kd == 3:
				world.set_block(p.x, p.y, p.z, 0)
				for s3 in Loot.block_drops(st, null, world, p):
					world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), s3)
			else:
				# IceBlock.melt: evaporates where water evaporates (Nether), else water
				var evap: bool = bool((world.dim_type.get("attributes", {}) as Dictionary).get("minecraft:gameplay/water_evaporates", false))
				world.set_block(p.x, p.y, p.z, 0 if evap else Res.blocks.WATER)
		return
	var n := blocks.name_of(st)
	var light: int = world.cm.get_light(p.x, p.y + 1, p.z)
	var sky := light >> 4
	var blk := light & 15
	var eff := maxi(blk, sky - _sky_sub(world))
	match n:
		"wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "torchflower_crop", "pitcher_crop":
			# wiki Tutorial:Crop farming / Melon Seeds: light 9+ at the plant block itself (not the block above); the time of
			# day does not matter (crops keep growing at night under the open sky)
			var lo: int = world.cm.get_light(p.x, p.y, p.z)
			if maxi(lo & 15, lo >> 4) < 9:
				return
			# wiki Beetroot Seeds: each growth tick has a 1/3 chance of not advancing
			if n == "beetroots" and rng.randi_range(0, 2) == 0:
				return
			if n == "torchflower_crop" or n == "pitcher_crop":
				if rng.randi_range(0, 6) != 0:   # (no wiki value for these two: kept at 1/7)
					return
			elif rng.randi_range(0, int(25.0 / _growth_speed(world, p, blocks.st_block[st]))) != 0:
				return   # wiki Tutorial:Crop farming: 1 / (floor(25 / growth speed) + 1)
			var age := int(blocks.get_prop(st, "age"))
			if n == "pitcher_crop":
				if blocks.get_prop(st, "half") != "upper":   # (the lower half grows both: Growth.pitcher_grow)
					Growth.pitcher_grow(world, p, st, 1)
			elif age < _max_age(st):
				world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(age + 1)))
			elif n == "torchflower_crop":
				world.set_block(p.x, p.y, p.z, blocks.default_state("torchflower"))   # wiki Torchflower Seeds: last stage = torchflower
			elif n.ends_with("_stem"):
				_stem_fruit(world, p, n.trim_suffix("_stem"), rng)
		"nether_wart":
			# wiki Nether Wart: 10 % per random tick, no light needed
			var wa := int(blocks.get_prop(st, "age"))
			if wa < _max_age(st) and rng.randi_range(0, 9) == 0:
				world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(wa + 1)))
		"cocoa":
			# wiki Cocoa Beans: 20 % per random tick, no light needed
			var ca := int(blocks.get_prop(st, "age"))
			if ca < _max_age(st) and rng.randi_range(0, 4) == 0:
				world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(ca + 1)))
		"sweet_berry_bush":
			# wiki Sweet Berries: 20 % per random tick; the block above needs light level 10 or more
			var ba := int(blocks.get_prop(st, "age"))
			if ba < _max_age(st) and eff >= 10 and rng.randi_range(0, 4) == 0:
				world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(ba + 1)))
		"grass_block", "mycelium":
			var above: int = world.state_at(p.x, p.y + 1, p.z)
			if above > 0 and blocks.st_opacity[above] >= 15:
				world.set_block(p.x, p.y, p.z, blocks.default_state("dirt"))
			elif eff >= 9:
				for i in 4:
					var q := p + Vector3i(rng.randi_range(-1, 1), rng.randi_range(-3, 1), rng.randi_range(-1, 1))
					var qs: int = world.state_at(q.x, q.y, q.z)
					if qs > 0 and blocks.name_of(qs) == "dirt":
						var qa: int = world.state_at(q.x, q.y + 1, q.z)
						if qa >= 0 and blocks.st_opacity[qa] < 15 and (world.cm.get_light(q.x, q.y + 1, q.z) >> 4) >= 4:
							world.set_block(q.x, q.y, q.z, blocks.default_state(n))
		"kelp":
			# Java GrowingPlantHeadBlock (kelp), wiki Kelp: age < 25, 14 % per random tick, grows into the water above
			# (a source or flowing water); the new tip has age + 1 and the old tip becomes kelp_plant
			var ka := int(blocks.get_prop(st, "age")) if blocks.has_prop(st, "age") else 25
			if ka < 25 and rng.randf() < 0.14:
				var kup: int = world.state_at(p.x, p.y + 1, p.z)
				if kup > 0 and blocks.st_block[kup] == blocks.st_block[Res.blocks.WATER]:
					world.set_block(p.x, p.y + 1, p.z, blocks.with_prop(st, "age", str(ka + 1)))
					world.set_block(p.x, p.y, p.z, blocks.default_state("kelp_plant"))
		"cactus":
			Growth.cactus_tick(world, p, st, rng)
		"sugar_cane":
			# wiki Sugar Cane: with all of its water gone, cane uproots on its next block update or random tick
			if n == "sugar_cane" and not BlockUpdates._has_support(world, p, st):
				world.set_block(p.x, p.y, p.z, 0)
				for sc in Loot.block_drops(st, null, world, p):
					world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), sc)
				BlockUpdates.schedule_neighbors(world, p)   # the cane above follows
				return
			# wiki Sugar Cane / Cactus: age 0..15 (+1 per random tick), at 15 a new block on top while the stalk is under 3
			if world.state_at(p.x, p.y + 1, p.z) == 0:
				var h := 1
				while h < 4 and blocks.name_of(maxi(0, world.state_at(p.x, p.y - h, p.z))) == n:
					h += 1
				if h < 3 and blocks.has_prop(st, "age"):
					var age2 := int(blocks.get_prop(st, "age"))
					if age2 >= 15:
						world.set_block(p.x, p.y + 1, p.z, blocks.default_state(n))
						world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", "0"))
					else:
						world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(age2 + 1)))
		"ice":
			if blk > 11:
				world.set_block(p.x, p.y, p.z, Res.blocks.WATER)
		"snow":
			if blk > 11:
				world.set_block(p.x, p.y, p.z, 0)
		"fire":
			# Java fire has no random tick: it runs on its scheduled tick (FireBlock.tick). Fire loaded without one
			# (scheduled ticks are not saved) gets it back here.
			if not BlockUpdates.pending.has(p):
				BlockUpdates.fire_placed(world, p)
		"lava":
			_lava_tick(world, p, st, rng)
		"farmland":
			# wiki Farmland: water up to 4 blocks away horizontally (diagonals too) at the same level or one above - flowing or
			# still, waterlogged blocks hold water too - or rain on it hydrates it (moisture jumps to 7); dry farmland counts
			# down and reverts to dirt when nothing planted on it keeps it (26.3 #maintains_farmland)
			var wet := false
			for dx in range(-4, 5):
				for dz in range(-4, 5):
					for dy in range(0, 2):
						var ws: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
						if ws > 0 and (blocks.st_flags[ws] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and not (blocks.st_flags[ws] & BlockRegistry.F_LAVA):
							wet = true
							break
					if wet:
						break
				if wet:
					break
			if not wet and world.raining and BlockUpdates._raining_at(world, p + Vector3i(0, 1, 0)):
				wet = true
			var m := int(blocks.get_prop(st, "moisture"))
			if wet and m < 7:
				world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "moisture", "7"))
			elif not wet:
				if m > 0:
					world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "moisture", str(m - 1)))
				else:
					var fup: int = world.state_at(p.x, p.y + 1, p.z)
					var mt := Tags.blocks("maintains_farmland")
					if fup == 0 or (fup > 0 and not mt.is_empty() and not mt.has(blocks.name_of(fup))):
						world.set_block(p.x, p.y, p.z, blocks.default_state("dirt"))
		_:
			if Growth.random_tick(world, p, st, n, rng):
				return
			if n.ends_with("_sapling"):
				if eff >= 9 and rng.randi_range(0, 6) == 0:
					var stage := blocks.get_prop(st, "stage")
					if stage == "0":
						world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "stage", "1"))
					else:
						grow_tree(world, p, n.trim_suffix("_sapling"))
			elif n.ends_with("_leaves"):
				if not _log_nearby(world, p, 6):
					world.set_block(p.x, p.y, p.z, 0)
					for s in Loot.block_drops(st, null, world, p):
						world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), s)


## SpreadingSnowyDirtBlock.canBeGrass per state of the block above (lazy table: 1 = grass / mycelium can stay): one
## snow layer keeps it; a full fluid (source, falling or waterlogged: amount 8) kills it; otherwise the light blocked
## into the block from above - a full opaque block (light block 15), or the full bottom face of a block whose shape
## blocks light (slabs, stairs, snow layers, farmland, dirt paths, daylight detectors, enchanting tables,
## stonecutters, lecterns, end portal frames: useShapeForLightOcclusion). The wiki (Grass Block) only says "an opaque
## block above", and water as a transparent example; the rest is Java's rule.
static var _grass_ok := PackedByteArray()
static func grass_ok(above: int) -> bool:
	if above <= 0:
		return above == 0
	var b := Res.blocks
	if _grass_ok.size() != b.total_states:
		_grass_ok.resize(b.total_states)
		for s in b.total_states:
			var ok := 1
			var fl := b.st_flags[s]
			var nm := b.name_of(s) if s > 0 else "air"
			var lv: int = b.st_level[s]
			if nm == "snow" and b.get_prop(s, "layers") == "1":
				ok = 1
			elif (fl & BlockRegistry.F_WATERLOGGED) != 0 or ((fl & BlockRegistry.F_LIQUID) != 0 and (lv == 0 or lv >= 8)):
				ok = 0
			elif b.st_opacity[s] >= 15:
				ok = 0
			elif (b.st_cull[s] & 1) != 0 and (nm.ends_with("_slab") or nm.ends_with("_stairs") or nm in ["snow", "farmland", "dirt_path", "daylight_detector", "enchanting_table", "stonecutter", "lectern", "end_portal_frame"]):
				ok = 0
			_grass_ok[s] = ok
	return _grass_ok[above] == 1


## grass_block / mycelium: dies under a light-blocking block, else (light >= 9 above it, wiki Grass Block / Mycelium) 4
## spread attempts in x +-1, y -3..+1, z +-1 onto dirt under a light-passing block (grass: not water / lava / waterlogged;
## mycelium: light >= 4 there).
static func _grass_tick(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var blocks := Res.blocks
	var chunks: Dictionary = world.cm.chunks
	var light: int = world.cm.get_light(p.x, p.y + 1, p.z)
	var eff := maxi(light & 15, (light >> 4) - _sky_sub(world))
	var above := _st(chunks, p.x, p.y + 1, p.z)
	if above > 0 and not grass_ok(above):
		world.set_block(p.x, p.y, p.z, _dirt)
		return
	if eff < 9:
		return
	var nm := blocks.name_of(st)
	var self_st := blocks.default_state(nm)
	var myc := nm == "mycelium"
	for i in 4:
		var qx := p.x + rng.randi_range(-1, 1)
		var qy := p.y + rng.randi_range(-3, 1)
		var qz := p.z + rng.randi_range(-1, 1)
		if _st(chunks, qx, qy, qz) != _dirt:
			continue
		var qa := _st(chunks, qx, qy + 1, qz)
		if qa < 0 or not grass_ok(qa):
			continue
		if myc:
			# wiki Mycelium: the dirt needs light level 4 or more above it
			var ql: int = world.cm.get_light(qx, qy + 1, qz)
			if maxi(ql & 15, ql >> 4) < 4:
				continue
		elif qa > 0 and (blocks.st_flags[qa] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0:
			continue   # wiki Grass Block: not under lava, water or a waterlogged block; the light level there does not matter
		world.set_block(qx, qy, qz, self_st)


## Per-state leaf-search classes (see leaf_class).
static func ltab() -> PackedByteArray:
	if _ltab.size() != Res.blocks.total_states:
		_build_ltab()
	return _ltab


## 1: log / wood / stem, 2: leaves, 0: other (leaf-support cache invalidation and the leaf search).
static func leaf_class(st: int) -> int:
	if st <= 0:
		return 0
	if _ltab.size() != Res.blocks.total_states:
		_build_ltab()
	return _ltab[st]


static func _build_ltab() -> void:
	var blocks := Res.blocks
	var t0 := PackedByteArray()
	t0.resize(blocks.total_states)
	# wiki Leaves: a log or wood within 6 steps (through leaves) keeps leaves; Java reads #prevents_nearby_leaf_decay (#logs:
	# overworld logs / wood and crimson / warped stems / hyphae - not melon, pumpkin or mushroom stems)
	var keep := Tags.blocks("prevents_nearby_leaf_decay")
	for s0 in blocks.total_states:
		var nm0 := blocks.name_of(s0)
		var lg := keep.has(nm0) if not keep.is_empty() else ((nm0.ends_with("_log") or nm0.ends_with("_wood") or nm0.ends_with("_hyphae") or nm0.ends_with("_stem")) and not (nm0.ends_with("melon_stem") or nm0.ends_with("pumpkin_stem") or nm0 == "mushroom_stem"))
		t0[s0] = 1 if lg else (2 if nm0.ends_with("_leaves") else 0)
	_ltab = t0


static var _leaf_native := -1
static var _ltab := PackedByteArray()   # per state: 1 = *_log / *_wood / *_stem, 2 = *_leaves
const _OFFS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]


## BFS through leaves (FIFO, same visit order as before) for a log within r steps; unloaded chunks count as found.
## Per-state class table + inlined chunk reads (this ran per leaf random tick and dominated forests).
static func _log_nearby(world, p: Vector3i, r: int) -> bool:
	var blocks := Res.blocks
	if _ltab.size() != blocks.total_states:
		_build_ltab()
	var tab := _ltab
	var chunks: Dictionary = world.cm.chunks
	if _leaf_native < 0:
		_leaf_native = 1 if (Native.chunkops_ok and Native.inst != null and Native.inst.has_method("leaf_search")) else 0
	if _leaf_native == 1:
		var nine: Array = []
		nine.resize(9)
		var pcx := p.x >> 4
		var pcz := p.z >> 4
		for dz in 3:
			for dx in 3:
				var nc: Chunk = chunks.get(((pcx + dx - 1) << 32) | ((pcz + dz - 1) & 0xFFFFFFFF))
				if nc != null and nc.state >= Chunk.DATA_READY:
					nine[dz * 3 + dx] = nc.sec_refs()
		return int(Native.inst.leaf_search(nine, tab, p.x, p.y, p.z, r)[0]) == 1
	return _log_nearby_gd(world, p, r)


## GDScript reference of the leaf search (fallback without the native library; --nativecheck compares both).
static func _log_nearby_gd(world, p: Vector3i, r: int) -> bool:
	var tab := _ltab
	var chunks: Dictionary = world.cm.chunks
	var seen := {p: 0}
	var q: Array = [p]
	var qi := 0
	while qi < q.size():
		var c: Vector3i = q[qi]
		qi += 1
		var d: int = seen[c]
		for o in _OFFS:
			var n: Vector3i = c + o
			if seen.has(n):
				continue
			var st := -1
			var ck: Chunk = chunks.get(((n.x >> 4) << 32) | ((n.z >> 4) & 0xFFFFFFFF))
			if ck != null and ck.state >= Chunk.DATA_READY:
				if n.y < -64 or n.y >= 320:
					st = 0
				else:
					var sec: Chunk.Section = ck.sections[(n.y + 64) >> 4]
					var spal := sec.pal
					if spal.size() == 1:
						st = spal[0]
					else:
						var li := ((n.y & 15) << 8) | ((n.z & 15) << 4) | (n.x & 15)
						st = spal[sec.wide[li]] if sec.wide.size() > 0 else spal[sec.idx[li]]
			if st < 0:
				return true
			var t := tab[st]
			if t == 1:
				return true
			if d + 1 < r and t == 2:
				seen[n] = d + 1
				q.append(n)
	return false


## A sapling / propagule / azalea at p grows its 26.3 configured tree (TreeGrower); false when it does not fit.
static func grow_tree(world, p: Vector3i, _kind: String = "") -> bool:
	return TreeGrower.grow(world, p, world.state_at(p.x, p.y, p.z))


## Adapter so FeaturesBasic.tree() can write through WorldManager.set_block for player-grown trees.
class TreeSink:
	extends ChunkRegion
	var world
	var cache: Dictionary

	func _init(w, c: Dictionary) -> void:
		super(0, 0, [])
		world = w
		cache = c

	func chunk_at(x: int, z: int) -> Chunk:
		return world.cm.get_chunk(x >> 4, z >> 4)

	func get_block(x: int, y: int, z: int) -> int:
		return world.state_at(x, y, z)

	func set_block(x: int, y: int, z: int, st: int) -> bool:
		world.set_block(x, y, z, st)
		return true

## Java LavaFluid.randomTick (lava sources and flows): 1-2 steps up and around looking for an air cell next to
## something lava ignites, else 3 tries to light the top of an ignitable block beside it.
static func _lava_tick(world, p: Vector3i, _st: int, rng: RandomNumberGenerator) -> void:
	if not world.gamerule("doFireTick", true):
		return
	var b := Res.blocks
	var i := rng.randi_range(0, 2)
	if i > 0:
		var q := p
		for _j in i:
			q += Vector3i(rng.randi_range(0, 2) - 1, 1, rng.randi_range(0, 2) - 1)
			if not world.cm.is_ready(q.x, q.z):
				return
			var s: int = world.state_at(q.x, q.y, q.z)
			if s == 0:
				for d in BlockUpdates.DIRS6:
					var r: Vector3i = q + d
					if _ignited_by_lava(world.state_at(r.x, r.y, r.z)):
						world.set_block(q.x, q.y, q.z, BlockUpdates.fire_state(world, q))
						return
			elif s > 0 and (b.st_flags[s] & BlockRegistry.F_COLLIDE) != 0:
				return
	else:
		for _k in 3:
			var q2 := p + Vector3i(rng.randi_range(0, 2) - 1, 0, rng.randi_range(0, 2) - 1)
			if not world.cm.is_ready(q2.x, q2.z):
				return
			if world.state_at(q2.x, q2.y + 1, q2.z) == 0 and _ignited_by_lava(world.state_at(q2.x, q2.y, q2.z)):
				var up := q2 + Vector3i(0, 1, 0)
				world.set_block(up.x, up.y, up.z, BlockUpdates.fire_state(world, up))


## wiki Fire, flammable blocks that do NOT catch fire from lava ("Lava: No"); 1-block flowers (#small_flowers) too.
const _LAVA_NO := ["cave_vines", "cave_vines_plant", "azalea", "flowering_azalea", "dried_kelp_block", "hay_block", "scaffolding",
	"sweet_berry_bush", "big_dripleaf", "big_dripleaf_stem", "small_dripleaf", "spore_blossom", "pink_petals", "wildflowers",
	"leaf_litter", "red_shrub"]
## wiki Fire: blocks that do not burn away but catch fire from lava (+ banners, beds, overworld wooden doors / trapdoors /
## pressure plates / signs / hanging signs below).
const _LAVA_YES := ["bamboo_sapling", "barrel", "campfire", "soul_campfire", "cartography_table", "chest", "trapped_chest",
	"chiseled_bookshelf", "crafting_table", "daylight_detector", "fletching_table", "jukebox", "loom", "smithing_table", "note_block",
	"brown_mushroom_block", "red_mushroom_block", "mushroom_stem", "nether_sprouts", "resin_clump"]
static var _lava_ign := PackedByteArray()   # per block id: 1 = ignited by lava


## BlockBehaviour.Properties.ignitedByLava (wiki Fire "catches fire from lava" column), per block.
static func _ignited_by_lava(st: int) -> bool:
	if st <= 0:
		return false
	var b := Res.blocks
	if _lava_ign.size() != b.names.size():
		var t := PackedByteArray()
		t.resize(b.names.size())
		var small := Tags.blocks("small_flowers")
		var wood_parts := {}
		for tg in ["banners", "beds", "wooden_doors", "wooden_trapdoors", "wooden_pressure_plates", "all_signs"]:
			wood_parts.merge(Tags.blocks(tg))
		for bid in b.names.size():
			var nm: String = b.names[bid]
			var st0 := b.default_state(nm)
			var on := false
			if _LAVA_YES.has(nm) or (wood_parts.has(nm) and not nm.begins_with("crimson_") and not nm.begins_with("warped_")):
				on = true
			elif not _LAVA_NO.has(nm) and not small.has(nm):
				on = BlockUpdates._fire_table()[bid] > 0 or (st0 > 0 and (b.st_flags[st0] & BlockRegistry.F_FLAMMABLE) != 0)
			t[bid] = 1 if on else 0
		_lava_ign = t
	return _lava_ign[b.st_block[st]] == 1
