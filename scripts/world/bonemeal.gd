## Bonemeal — Java BoneMealItem.growCrop / BonemealableBlock per target (minecraft.wiki Bone Meal and the block pages):
## a valid target uses up the bone meal (also when its chance roll fails: "wasted bone meal"), shows 15 happy villager
## particles and plays item.bone_meal.use (wiki Bone Meal: Sounds). Targets:
## - crops / stems 2-5 stages, beetroots 75 % one stage, cocoa / sweet berries / torchflower / pitcher crops one stage
##   (not at their last stage: not a target)
## - saplings, azalea / flowering azalea, mangrove propagules (not hanging): 45 % to advance a stage / grow the tree
##   (TreeGrower); hanging propagules age + 1 (wiki Mangrove Propagule); mangrove leaves grow a hanging propagule below
## - brown / red mushrooms 40 % -> huge mushroom, crimson / warped fungus 40 % -> huge fungus on its own nylium (wiki)
## - nylium -> nylium_bonemeal patch, netherrack next to nylium -> that nylium, moss / pale moss block -> the
##   *_patch_bonemeal features (26.3 data); grass block: 128 random walks over the 15 x 15 x 15 area (wiki Bone Meal),
##   1 in 8 a flower of the biome's flower feature, else short grass; short grass -> tall grass, fern -> large fern
## - tall flowers drop a copy; pink petals / wildflowers + 1 (a full block drops one: wiki Pink Petals)
## - big dripleaf + 1 block (air / water above the leaf), small dripleaf -> big dripleaf 2-5 tall (wiki)
## - glow lichen spreads to one adjacent spot (not a target when it cannot), cave vines get berries, rooted dirt grows
##   hanging roots below, kelp + 1 into water, seagrass -> tall seagrass (water above), sea pickles on live coral
##   blocks spread (wiki Sea Pickle: coral within taxicab 2, at the pickle's level or one below) and become 4
## - pale hanging moss grows one block down. Vines are not a target in Java (wiki Bone Meal: "not affected").
## Contract: apply(world, p, st) -> bool (true = bone meal used).
class_name Bonemeal

const DIRS6 := [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const FACE := ["up", "down", "north", "south", "west", "east"]
const TALL_FLOWERS := ["sunflower", "lilac", "rose_bush", "peony"]


static func apply(world, p: Vector3i, st: int) -> bool:
	if st <= 0:
		return false
	var used := _apply(world, p, st)
	if used:
		effects(world, p)
	return used


## Java levelEvent 1505 (BoneMealItem.addGrowthParticles): 15 happy villager particles in the block + the use sound.
static func effects(world, p: Vector3i) -> void:
	var rng: RandomNumberGenerator = world.rng
	for i in 15:
		Particles.emit("happy_villager", Vector3(p) + Vector3(rng.randf(), rng.randf(), rng.randf()))
	Audio.play("item.bone_meal.use", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")


static func _apply(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var name := b.name_of(st)
	var rng: RandomNumberGenerator = world.rng
	if b.has_prop(st, "age") and name in ["wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "sweet_berry_bush", "cocoa", "torchflower_crop", "pitcher_crop"]:
		return _crop(world, p, st, name)
	if name.ends_with("_sapling") and name != "bamboo_sapling" or name == "azalea" or name == "flowering_azalea":
		if name.contains("azalea") and _fluid_above(world, p):
			return false   # (Java AzaleaBlock: only without fluid above)
		# wiki Bone Meal: 45 % to advance one stage (stage 0 -> 1, then the tree)
		if rng.randf() < 0.45:
			if b.has_prop(st, "stage") and b.get_prop(st, "stage") == "0":
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "stage", "1"))
			else:
				TreeGrower.grow(world, p, st)
		return true
	match name:
		"mangrove_propagule":
			if b.get_prop(st, "hanging") == "true":
				var age := int(b.get_prop(st, "age"))
				if age >= 4:
					return false
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "age", str(age + 1)))   # wiki: raises its age by 1
				return true
			if rng.randf() < 0.45:
				if b.get_prop(st, "stage") == "0":
					world.set_block(p.x, p.y, p.z, b.with_prop(st, "stage", "1"))
				else:
					TreeGrower.grow(world, p, st)
			return true
		"mangrove_leaves":
			if world.state_at(p.x, p.y - 1, p.z) != 0:
				return false
			var hp := b.with_prop(b.with_prop(b.default_state("mangrove_propagule"), "hanging", "true"), "age", "0")
			world.set_block(p.x, p.y - 1, p.z, hp)   # wiki: a hanging propagule at age 0 underneath
			return true
		"brown_mushroom", "red_mushroom":
			if rng.randf() < 0.4:   # wiki Bone Meal: 40 %
				_grow_huge(world, p, st, "huge_" + name)
			return true
		"crimson_fungus", "warped_fungus":
			var below: int = world.state_at(p.x, p.y - 1, p.z)
			var nyl := name.trim_suffix("_fungus") + "_nylium"
			if below > 0 and b.name_of(below) == nyl and rng.randf() < 0.4:   # wiki: 40 %, only on the matching nylium
				_grow_huge(world, p, st, name + "_planted")
			return true
		"crimson_nylium", "warped_nylium":
			if world.state_at(p.x, p.y + 1, p.z) != 0:
				return false
			TreeGrower.place_feature(world, "nylium_bonemeal", p + Vector3i.UP)
			return true
		"netherrack":
			return _netherrack(world, p)
		"moss_block", "pale_moss_block":
			if world.state_at(p.x, p.y + 1, p.z) != 0:
				return false
			TreeGrower.place_feature(world, name.trim_suffix("_block") + "_patch_bonemeal", p + Vector3i.UP)
			return true
		"grass_block":
			_grass(world, p)
			return true
		"short_grass", "fern":
			return _double(world, p, "tall_grass" if name == "short_grass" else "large_fern", false)
		"seagrass":
			_double(world, p, "tall_seagrass", true)
			return true   # (wiki: wasted without water above)
		"pink_petals", "wildflowers":
			var n := int(b.get_prop(st, "flower_amount"))
			if n < 4:
				world.set_block(p.x, p.y, p.z, b.with_prop(st, "flower_amount", str(n + 1)))
			else:
				world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), ItemStack.named(name, 1))
			return true
		"big_dripleaf", "big_dripleaf_stem":
			return _big_dripleaf(world, p)
		"small_dripleaf":
			return _small_dripleaf(world, p, st)
		"glow_lichen":
			return _lichen(world, p, st, rng)
		"cave_vines", "cave_vines_plant":
			if b.get_prop(st, "berries") == "true":
				return false
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "berries", "true"))
			return true
		"rooted_dirt":
			if world.state_at(p.x, p.y - 1, p.z) != 0:
				return false
			world.set_block(p.x, p.y - 1, p.z, b.default_state("hanging_roots"))
			return true
		"kelp", "kelp_plant":
			return _kelp(world, p, st)
		"sea_pickle":
			_sea_pickle(world, p, st, rng)
			return true
		"pale_hanging_moss":
			var bot := p
			while b.name_of(maxi(0, world.state_at(bot.x, bot.y - 1, bot.z))) == "pale_hanging_moss":
				bot.y -= 1
			if world.state_at(bot.x, bot.y - 1, bot.z) != 0:
				return false
			var cur: int = world.state_at(bot.x, bot.y, bot.z)
			world.set_block(bot.x, bot.y, bot.z, b.with_prop(cur, "tip", "false"))
			world.set_block(bot.x, bot.y - 1, bot.z, b.with_prop(b.default_state("pale_hanging_moss"), "tip", "true"))
			return true
	if name in TALL_FLOWERS:
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), ItemStack.named(name, 1))   # wiki: drops a copy
		return true
	return false


static func _fluid_above(world, p: Vector3i) -> bool:
	var s: int = world.state_at(p.x, p.y + 1, p.z)
	return s > 0 and (Res.blocks.st_flags[s] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0


static func _crop(world, p: Vector3i, st: int, name: String) -> bool:
	var b := Res.blocks
	var vals := 0
	for pr in b.block_props[b.st_block[st]]:
		if pr[0] == "age":
			vals = (pr[1] as PackedStringArray).size() - 1
	var a0 := int(b.get_prop(st, "age"))
	if a0 >= vals and name != "torchflower_crop":
		return false   # (Java CropBlock.isValidBonemealTarget: not at the last stage)
	# wiki Bone Meal: wheat / carrots / potatoes / stems 2-5 stages; beetroots 75 % chance of one stage; cocoa, sweet berry
	# bush, torchflower and pitcher crops one stage
	var inc := 1
	if name == "beetroots":
		inc = 1 if world.rng.randf() < 0.75 else 0
	elif not (name in ["sweet_berry_bush", "cocoa", "torchflower_crop", "pitcher_crop"]):
		inc = world.rng.randi_range(2, 5)
	if name == "torchflower_crop" and a0 + inc > vals:
		world.set_block(p.x, p.y, p.z, b.default_state("torchflower"))   # wiki Torchflower Seeds: last stage = torchflower
		return true
	if name == "pitcher_crop":
		return Growth.pitcher_grow(world, p, st, inc)
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "age", str(mini(vals, a0 + inc))))
	return true


## Java MushroomBlock.growMushroom / FungusBlock: the plant makes way for the feature, back when it does not fit.
static func _grow_huge(world, p: Vector3i, st: int, feature: String) -> void:
	world.set_block(p.x, p.y, p.z, 0, false)
	if not TreeGrower.place_feature(world, feature, p):
		world.set_block(p.x, p.y, p.z, st, false)


## Java NetherrackBlock: nylium among the 3 x 3 x 3 neighbours and a light-passing block above; becomes one of those
## nylium types at random.
static func _netherrack(world, p: Vector3i) -> bool:
	var b := Res.blocks
	var up: int = world.state_at(p.x, p.y + 1, p.z)
	if up < 0 or (up > 0 and b.st_opacity[up] >= 15):
		return false
	var crimson := false
	var warped := false
	for dy in range(-1, 2):
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var s: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
				if s > 0:
					var n := b.name_of(s)
					crimson = crimson or n == "crimson_nylium"
					warped = warped or n == "warped_nylium"
	if not crimson and not warped:
		return false
	var pick := "crimson_nylium" if crimson and (not warped or world.rng.randi_range(0, 1) == 0) else "warped_nylium"
	world.set_block(p.x, p.y, p.z, b.default_state(pick))
	return true


## Grass block: 128 tries; try i walks i / 16 random steps from the block above (x / z +-1, y +-1 at half the rate)
## over grass blocks through non-full blocks (wiki Bone Meal: a 15 x 15 x 15 area); in air 1 in 8 the biome's flower
## (its first flower_* placed feature), else short grass; short grass there 1 in 10 grows tall.
static func _grass(world, p: Vector3i) -> void:
	var b := Res.blocks
	var rng: RandomNumberGenerator = world.rng
	var grass_id := b.st_block[b.default_state("grass_block")]
	var short := b.default_state("short_grass")
	for i in 128:
		var q := p + Vector3i.UP
		var ok := true
		for j in i / 16:
			q += Vector3i(rng.randi_range(0, 2) - 1, (rng.randi_range(0, 2) - 1) * rng.randi_range(0, 2) / 2, rng.randi_range(0, 2) - 1)
			var bl: int = world.state_at(q.x, q.y - 1, q.z)
			var qs: int = world.state_at(q.x, q.y, q.z)
			if bl <= 0 or b.st_block[bl] != grass_id or qs < 0 or (qs > 0 and (b.st_flags[qs] & BlockRegistry.F_FULL_SHAPE) != 0 and (b.st_flags[qs] & BlockRegistry.F_COLLIDE) != 0):
				ok = false
				break
		if not ok:
			continue
		var cur: int = world.state_at(q.x, q.y, q.z)
		if cur == short and rng.randi_range(0, 9) == 0:
			_double(world, q, "tall_grass", false)
		elif cur == 0:
			var below: int = world.state_at(q.x, q.y - 1, q.z)
			if below <= 0 or b.st_block[below] != grass_id:
				continue
			if rng.randi_range(0, 7) == 0:
				var ff := _flower_feature(world, q)
				if ff != "" and TreeGrower.place_feature(world, ff, q):
					continue
				if ff != "":
					continue
			world.set_block(q.x, q.y, q.z, short)


static var _flower_cache: Dictionary = {}   # biome id -> configured flower feature ("" none)


static func _flower_feature(world, q: Vector3i) -> String:
	var c: Chunk = world.cm.get_chunk(q.x >> 4, q.z >> 4)
	if c == null or c.biomes.is_empty():
		return "flower_default"
	var bi := c.biome_at(q.x & 15, q.y, q.z & 15)
	var cached = _flower_cache.get(bi)
	if cached != null:
		return cached
	var out := ""
	var reg = world.get("biomes")
	if reg != null and bi >= 0 and bi < reg.data.size() and reg.data[bi] is Dictionary:
		var feats = (reg.data[bi] as Dictionary).get("features", [])
		if feats is Array:
			for step in feats:
				if out != "" or not (step is Array):
					continue
				for pf in step:
					var pn := str(pf).trim_prefix("minecraft:")
					if pn.begins_with("flower_"):
						var pj = Res.read_json("data/minecraft/worldgen/placed_feature/" + pn + ".json")
						if pj is Dictionary and pj.get("feature") is String:
							out = str(pj["feature"]).trim_prefix("minecraft:")
						break
	_flower_cache[bi] = out
	return out


## Short grass / fern / seagrass -> their two-block plant when the block above is free (air; water for seagrass).
static func _double(world, p: Vector3i, tall: String, water: bool) -> bool:
	var b := Res.blocks
	var up: int = world.state_at(p.x, p.y + 1, p.z)
	if water:
		if not (up > 0 and b.st_block[up] == b.st_block[b.WATER] and b.st_level[up] == 0):
			return false
	elif up != 0:
		return false
	var lo := b.with_prop(b.default_state(tall), "half", "lower")
	world.set_block(p.x, p.y, p.z, lo)
	world.set_block(p.x, p.y + 1, p.z, b.with_prop(lo, "half", "upper"))
	return true


static func _grow_into(world, q: Vector3i) -> int:
	# -1 blocked, 0 air, 1 water source
	var b := Res.blocks
	var s: int = world.state_at(q.x, q.y, q.z)
	if s == 0:
		return 0
	if s > 0 and b.st_block[s] == b.st_block[b.WATER] and b.st_level[s] == 0:
		return 1
	return -1


## wiki Big Dripleaf: one block higher unless something other than air / water is above the leaf.
static func _big_dripleaf(world, p: Vector3i) -> bool:
	var b := Res.blocks
	var top := p
	while b.name_of(maxi(0, world.state_at(top.x, top.y, top.z))) == "big_dripleaf_stem":
		top.y += 1
	var head: int = world.state_at(top.x, top.y, top.z)
	if head <= 0 or b.name_of(head) != "big_dripleaf":
		return false
	var g := _grow_into(world, top + Vector3i.UP)
	if g < 0 or top.y + 1 >= Coords.MAX_Y:
		return false
	var facing := b.get_prop(head, "facing")
	var stem := b.with_prop(b.with_prop(b.default_state("big_dripleaf_stem"), "facing", facing), "waterlogged", b.get_prop(head, "waterlogged"))
	world.set_block(top.x, top.y, top.z, stem)
	world.set_block(top.x, top.y + 1, top.z, b.with_prop(b.with_prop(head, "tilt", "none"), "waterlogged", "true" if g == 1 else "false"))
	return true


## wiki Small Dripleaf: becomes a big dripleaf 2-5 blocks tall (shorter where the space above runs out).
static func _small_dripleaf(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var base := p if b.get_prop(st, "half") != "upper" else p - Vector3i.UP
	var bst: int = world.state_at(base.x, base.y, base.z)
	if bst <= 0 or b.name_of(bst) != "small_dripleaf":
		return false
	var facing := b.get_prop(bst, "facing")
	var want: int = world.rng.randi_range(2, 5)
	var h := 2   # the small dripleaf's two blocks
	while h < want and _grow_into(world, base + Vector3i(0, h, 0)) >= 0 and base.y + h < Coords.MAX_Y:
		h += 1
	var stem0 := b.with_prop(b.default_state("big_dripleaf_stem"), "facing", facing)
	for i in h:
		var q := base + Vector3i(0, i, 0)
		var wet := b.get_prop(world.state_at(q.x, q.y, q.z), "waterlogged") == "true" if i < 2 else _grow_into(world, q) == 1
		var s := stem0 if i < h - 1 else b.with_prop(b.default_state("big_dripleaf"), "facing", facing)
		world.set_block(q.x, q.y, q.z, b.with_prop(s, "waterlogged", "true" if wet else "false"))
	return true


## Java GrowingPlantHeadBlock (kelp): one block per use (wiki Bone Meal) into the water source above the tip.
static func _kelp(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var top := p
	while b.name_of(maxi(0, world.state_at(top.x, top.y, top.z))) == "kelp_plant":
		top.y += 1
	var head: int = world.state_at(top.x, top.y, top.z)
	if head <= 0 or b.name_of(head) != "kelp" or _grow_into(world, top + Vector3i.UP) != 1:
		return false
	var age := mini(int(b.get_prop(head, "age")) + 1, 25)
	world.set_block(top.x, top.y, top.z, b.default_state("kelp_plant"))
	world.set_block(top.x, top.y + 1, top.z, b.with_prop(head, "age", str(age)))
	return true


## wiki Sea Pickle: on a live coral block underwater the colony becomes 4; spots above live coral blocks within taxicab
## distance 2 (at the pickle's level or one below, in water) can get 1-3 pickles. (The per-spot chance is not on the
## wiki: Java's 1 in 6.)
static func _sea_pickle(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := Res.blocks
	if b.get_prop(st, "waterlogged") != "true":
		return
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below <= 0 or not Tags.has_block("coral_blocks", b.name_of(below)):
		return
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if absi(dx) + absi(dz) > 2:
				continue
			for dy in [-1, 0]:
				var q := p + Vector3i(dx, dy, dz)
				if q == p or rng.randi_range(0, 5) != 0:
					continue
				var qs: int = world.state_at(q.x, q.y, q.z)
				if not (qs > 0 and b.st_block[qs] == b.st_block[b.WATER] and b.st_level[qs] == 0):
					continue
				var qb: int = world.state_at(q.x, q.y - 1, q.z)
				if qb > 0 and Tags.has_block("coral_blocks", b.name_of(qb)):
					var np := b.with_prop(b.with_prop(b.default_state("sea_pickle"), "waterlogged", "true"), "pickles", str(rng.randi_range(1, 3)))
					world.set_block(q.x, q.y, q.z, np)
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "pickles", "4"))


static func _sturdy(world, q: Vector3i) -> bool:
	var s: int = world.state_at(q.x, q.y, q.z)
	return s > 0 and (Res.blocks.st_flags[s] & (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)) == (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)


## Can glow lichen take face fi at q: air / water source / lichen without that face, attached to a sturdy block.
static func _lichen_ok(world, q: Vector3i, fi: int) -> bool:
	var b := Res.blocks
	var s: int = world.state_at(q.x, q.y, q.z)
	var free := s == 0 or (s > 0 and b.st_block[s] == b.st_block[b.WATER] and b.st_level[s] == 0) or (s > 0 and b.name_of(s) == "glow_lichen" and b.get_prop(s, FACE[fi]) != "true")
	return free and _sturdy(world, q + DIRS6[fi])


static func _lichen_set(world, q: Vector3i, fi: int) -> void:
	var b := Res.blocks
	var s: int = world.state_at(q.x, q.y, q.z)
	var ns: int
	if s > 0 and b.name_of(s) == "glow_lichen":
		ns = b.with_prop(s, FACE[fi], "true")
	else:
		ns = b.default_state("glow_lichen")
		for f in FACE:
			ns = b.with_prop(ns, f, "false")
		ns = b.with_prop(b.with_prop(ns, FACE[fi], "true"), "waterlogged", "true" if s > 0 else "false")
	world.set_block(q.x, q.y, q.z, ns)


## Java MultifaceSpreader (wiki Glow Lichen: "spread to a random adjacent block if possible", sides and top of an
## adjacent block but not its back): a random face, a random direction across it; same block (new face), same plane
## (the next block, same face) or wrapped around the edge. Not a target when nothing fits.
static func _lichen(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> bool:
	var b := Res.blocks
	var faces: Array = []
	for i in 6:
		if b.get_prop(st, FACE[i]) == "true":
			faces.append(i)
	_shuffle(faces, rng)
	for fi in faces:
		var dirs: Array = []
		for di in 6:
			if di != fi and di != (fi ^ 1):
				dirs.append(di)
		_shuffle(dirs, rng)
		for di in dirs:
			if _lichen_ok(world, p, di):   # same position
				_lichen_set(world, p, di)
				return true
			var q: Vector3i = p + DIRS6[di]
			if _lichen_ok(world, q, fi):   # same plane
				_lichen_set(world, q, fi)
				return true
			var w: Vector3i = q + DIRS6[fi]
			var qs: int = world.state_at(q.x, q.y, q.z)
			if (qs == 0 or (qs > 0 and (b.st_flags[qs] & BlockRegistry.F_COLLIDE) == 0)) and _lichen_ok(world, w, di ^ 1):   # wrap around
				_lichen_set(world, w, di ^ 1)
				return true
	return false


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
