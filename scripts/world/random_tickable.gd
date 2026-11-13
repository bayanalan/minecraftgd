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
		if n in ["wheat", "carrots", "potatoes", "beetroots", "grass_block", "mycelium", "sugar_cane", "cactus", "ice", "snow", "fire", "lava", "melon_stem", "pumpkin_stem", "sweet_berry_bush", "farmland", "kelp", "bamboo", "cocoa", "nether_wart", "torchflower_crop", "pitcher_crop"]:
			t = true
		elif n.ends_with("_sapling"):
			t = true
		elif n.ends_with("_leaves") and blocks.get_prop(st, "persistent") == "false":
			t = true
		elif n.contains("copper") and not n.begins_with("waxed") and not n.begins_with("oxidized") and not n.ends_with("_ore") and n != "raw_copper_block" and not n.ends_with("_torch"):
			# Java WeatheringCopper blocks only (ores, raw blocks and copper torches never random-tick)
			t = true
		_flag[st] = 1 if t else 0


static func _max_age(st: int) -> int:
	var blocks := Res.blocks
	for pr in blocks.block_props[blocks.st_block[st]]:
		if pr[0] == "age":
			return (pr[1] as PackedStringArray).size() - 1
	return 0


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
			kt[s0] = 1 if (n0 == "grass_block" or n0 == "mycelium") else (2 if n0.ends_with("_leaves") else (3 if n0 == "snow" else (4 if n0 == "ice" else 0)))
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
	var eff := maxi(blk, int(sky * world.sky_darken()))
	match n:
		"wheat", "carrots", "potatoes", "beetroots", "torchflower_crop", "nether_wart", "melon_stem", "pumpkin_stem", "sweet_berry_bush", "cocoa", "pitcher_crop":
			if eff >= 9 or n == "nether_wart" or n == "cocoa":
				var age := int(blocks.get_prop(st, "age"))
				var mx := _max_age(st)
				if age < mx and rng.randi_range(0, 6) == 0:
					world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(age + 1)))
				elif age >= mx and n.ends_with("_stem") and rng.randi_range(0, 3) == 0:
					var fruit := "melon" if n.begins_with("melon") else "pumpkin"
					for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
						var q: Vector3i = p + d
						if world.state_at(q.x, q.y, q.z) == 0 and blocks.name_of(maxi(0, world.state_at(q.x, q.y - 1, q.z))) in ["dirt", "grass_block", "farmland"]:
							world.set_block(q.x, q.y, q.z, blocks.default_state(fruit))
							break
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
			# Java GrowingPlantHeadBlock (kelp): age < 25, 14 % per random tick, grows into a water source above; the
			# new tip has age + 1 and the old tip becomes kelp_plant (updateBodyAfterConvertedFromHead)
			var ka := int(blocks.get_prop(st, "age")) if blocks.has_prop(st, "age") else 25
			if ka < 25 and rng.randf() < 0.14:
				var kup: int = world.state_at(p.x, p.y + 1, p.z)
				if kup > 0 and (blocks.st_flags[kup] & BlockRegistry.F_LIQUID) != 0 and (blocks.st_flags[kup] & BlockRegistry.F_LAVA) == 0 and blocks.st_level[kup] == 0:
					world.set_block(p.x, p.y + 1, p.z, blocks.with_prop(st, "age", str(ka + 1)))
					world.set_block(p.x, p.y, p.z, blocks.default_state("kelp_plant"))
		"sugar_cane", "cactus", "bamboo":
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
			var wet := false
			for dx in range(-4, 5):
				for dz in range(-4, 5):
					for dy in range(0, 2):
						var ws: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
						if ws > 0 and (blocks.st_flags[ws] & BlockRegistry.F_LIQUID) and not (blocks.st_flags[ws] & BlockRegistry.F_LAVA):
							wet = true
							break
					if wet:
						break
				if wet:
					break
			var m := int(blocks.get_prop(st, "moisture"))
			if wet and m < 7:
				world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "moisture", "7"))
			elif not wet:
				if m > 0:
					world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "moisture", str(m - 1)))
				elif world.state_at(p.x, p.y + 1, p.z) == 0:
					world.set_block(p.x, p.y, p.z, blocks.default_state("dirt"))
		_:
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


## grass_block / mycelium: dies under a light-blocking block, else (light >= 9) 4 spread attempts onto dirt below
## light-passing blocks with sky light >= 4 above (same checks and random draws as the generic path).
static func _grass_tick(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var blocks := Res.blocks
	var chunks: Dictionary = world.cm.chunks
	var opa := blocks.st_opacity
	var light: int = world.cm.get_light(p.x, p.y + 1, p.z)
	var eff := maxi(light & 15, int((light >> 4) * world.sky_darken()))
	var above := _st(chunks, p.x, p.y + 1, p.z)
	if above > 0 and opa[above] >= 15:
		world.set_block(p.x, p.y, p.z, _dirt)
		return
	if eff < 9:
		return
	var self_st := blocks.default_state(blocks.name_of(st))
	for i in 4:
		var qx := p.x + rng.randi_range(-1, 1)
		var qy := p.y + rng.randi_range(-3, 1)
		var qz := p.z + rng.randi_range(-1, 1)
		if _st(chunks, qx, qy, qz) != _dirt:
			continue
		var qa := _st(chunks, qx, qy + 1, qz)
		if qa >= 0 and opa[qa] < 15 and (world.cm.get_light(qx, qy + 1, qz) >> 4) >= 4:
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
	for s0 in blocks.total_states:
		var nm0 := blocks.name_of(s0)
		t0[s0] = 1 if (nm0.ends_with("_log") or nm0.ends_with("_wood") or nm0.ends_with("_stem")) else (2 if nm0.ends_with("_leaves") else 0)
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


static func grow_tree(world, p: Vector3i, kind: String) -> void:
	var nine: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			nine.append(world.cm.get_chunk((p.x >> 4) + dx, (p.z >> 4) + dz))
	world.set_block(p.x, p.y, p.z, 0)
	# grow via region writes then re-apply as world edits so meshes/light/saves update
	var before: Dictionary = {}
	for dx in range(-3, 4):
		for dz in range(-3, 4):
			for dy in range(0, 14):
				before[Vector3i(p.x + dx, p.y + dy, p.z + dz)] = world.state_at(p.x + dx, p.y + dy, p.z + dz)
	var tmp := TreeSink.new(world, before)
	FeaturesBasic.tree(tmp, RandomSources.Xoroshiro.from_seed(hash(p)), p.x, p.y, p.z, kind, Res.blocks)


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


## BlockBehaviour.Properties.ignitedByLava: the burnable blocks (wood, wool, leaves, plants, ...).
static func _ignited_by_lava(st: int) -> bool:
	return st > 0 and (BlockUpdates.ignite_odds(st) > 0 or (Res.blocks.st_flags[st] & BlockRegistry.F_FLAMMABLE) != 0)
