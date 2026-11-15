## TreeGrower — saplings, mangrove propagules and azaleas grow the 26.3 configured tree features (worldgen/feature data
## from the jar, placed by the worldgen tree code: Features.place_feature -> Trees.place) like Java's TreeGrower:
## - 2x2 of the same sapling (spruce, jungle, dark oak, pale oak; the four 2x2 squares containing the sapling are tried
##   from the north-west) grows the mega tree at the square's north-west sapling: mega spruce / mega pine, mega jungle
##   tree, dark oak, pale oak (wiki Sapling: dark / pale oak only as 2x2; "saplings in more than one 2x2 square fail" is
##   covered by the first square that matches growing)
## - single: oak (wiki Oak: fancy oak 1/10), birch, cherry (bee variants when a #flowers block is within 2 blocks: wiki
##   Oak / Sapling "within 2 blocks of a flower ... 5 % chance ... bee nest" = the *_bees_005 features), spruce, jungle
##   (jungle_tree_no_vine), acacia, poplar (wiki Poplar: one of the three leaf colours at random), mangrove propagule
##   (mangrove / tall_mangrove; the 1 % bee nest is in the feature data), azalea -> azalea_tree
## The sapling is removed first and put back when the feature does not fit (wiki Poplar: "the growth attempt fails and
## the sapling stays"). Worlds without data-driven features (flat / approximate generators) use FeaturesBasic.tree.
## Contract: grow(world, p, st) -> bool; place_feature(world, id, p) -> bool (any configured feature at a world position,
## writes applied as world edits; also used by bone meal: huge mushrooms / fungi, moss / nylium patches).
class_name TreeGrower

# wiki Oak: "1/10 chance to grow in place of a small oak tree, including from saplings"
const FANCY_OAK_CHANCE := 0.1
# wiki Spruce / Mangrove give no split between mega spruce / mega pine and mangrove / tall mangrove; these are Java
# TreeGrower's secondary chances (SPRUCE 0.5 mega pine, MANGROVE 0.85 tall mangrove) - not on the wiki
const MEGA_PINE_CHANCE := 0.5
const TALL_MANGROVE_CHANCE := 0.85
const MEGA := {"spruce_sapling": true, "jungle_sapling": true, "dark_oak_sapling": true, "pale_oak_sapling": true}


static func grow(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var name := b.name_of(st)
	var rng: RandomNumberGenerator = world.rng
	var fe = world.gen.get("features") if world.gen != null else null
	if fe == null:
		if not name.ends_with("_sapling"):
			return false
		world.set_block(p.x, p.y, p.z, 0)
		var tmp := RandomTickable.TreeSink.new(world, {})
		FeaturesBasic.tree(tmp, RandomSources.Xoroshiro.from_seed(rng.randi()), p.x, p.y, p.z, name.trim_suffix("_sapling"), b)
		return true
	if MEGA.has(name):
		for o in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1)]:
			var nw := p + Vector3i(o.x, 0, o.y)
			if not _square(world, nw, b.st_block[st]):
				continue
			var mega := ""
			match name:
				"spruce_sapling":
					mega = "mega_pine" if rng.randf() < MEGA_PINE_CHANCE else "mega_spruce"
				"jungle_sapling":
					mega = "mega_jungle_tree"
				"dark_oak_sapling":
					mega = "dark_oak"
				"pale_oak_sapling":
					mega = "pale_oak_bonemeal"
			var olds: Array = []
			for d in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
				var q: Vector3i = nw + d
				olds.append(world.state_at(q.x, q.y, q.z))
				world.set_block(q.x, q.y, q.z, 0, false)
			if place_feature(world, mega, nw):
				return true
			var k := 0
			for d2 in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
				var q2: Vector3i = nw + d2
				world.set_block(q2.x, q2.y, q2.z, olds[k], false)
				k += 1
			return false
	var id := ""
	var bees := name in ["oak_sapling", "birch_sapling", "cherry_sapling"] and _flowers_near(world, p)
	match name:
		"oak_sapling":
			id = ("fancy_oak" if rng.randf() < FANCY_OAK_CHANCE else "oak") + ("_bees_005" if bees else "")
		"birch_sapling":
			id = "birch_bees_005" if bees else "birch"
		"cherry_sapling":
			id = "cherry_bees_005" if bees else "cherry"
		"spruce_sapling":
			id = "spruce"
		"jungle_sapling":
			id = "jungle_tree_no_vine"
		"acacia_sapling":
			id = "acacia"
		"poplar_sapling":
			id = ["orange_poplar", "yellow_poplar", "red_poplar"][rng.randi_range(0, 2)]
		"mangrove_propagule":
			id = "tall_mangrove" if rng.randf() < TALL_MANGROVE_CHANCE else "mangrove"
		"azalea", "flowering_azalea":
			id = "azalea_tree"
	if id == "":
		return false   # dark oak / pale oak need the 2x2
	# the sapling's spot takes its fluid (a waterlogged propagule leaves water) while the tree is placed
	var keep: int = b.WATER if b.get_prop(st, "waterlogged") == "true" else 0
	world.set_block(p.x, p.y, p.z, keep, false)
	if place_feature(world, id, p):
		return true
	world.set_block(p.x, p.y, p.z, st, false)
	return false


static func _square(world, nw: Vector3i, bid: int) -> bool:
	var b := Res.blocks
	for d in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(1, 0, 1)]:
		var q: Vector3i = nw + d
		var s: int = world.state_at(q.x, q.y, q.z)
		if s <= 0 or b.st_block[s] != bid:
			return false
	return true


## wiki Sapling: within 2 blocks of a flower, flowering azalea or flowering azalea leaves (26.3 #flowers): x / z +-2,
## y -1..+1 around the sapling.
static func _flowers_near(world, p: Vector3i) -> bool:
	var b := Res.blocks
	for dy in range(-1, 2):
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var s: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
				if s > 0 and Tags.has_block("flowers", b.name_of(s)):
					return true
	return false


## Runs a configured feature (26.3 worldgen/feature id) at p on a private copy of the 3 x 3 loaded chunks and applies
## its writes (placement modes as Features.apply), block entities (bee nests) and mobs to the world. False when the
## feature did not place or the chunk is not loaded.
static func place_feature(world, id: String, p: Vector3i, rseed: int = 0) -> bool:
	var fe = world.gen.get("features") if world.gen != null else null
	if fe == null:
		return false
	var cf: Dictionary = fe._cf("minecraft:" + id.trim_prefix("minecraft:"))
	if cf.is_empty() or str(cf.get("t", "none")) == "none":
		return false
	var ccx := p.x >> 4
	var ccz := p.z >> 4
	var nine: Array = []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			nine.append(world.cm.get_chunk(ccx + dx, ccz + dz))
	if nine[4] == null:
		return false
	var region := ChunkRegion.new(ccx, ccz, nine)
	var c := Features.FCtx.new()
	c.region = region
	fe._load_region(c, nine[4], region)
	c.origin_chunk = nine[4]
	c.r = RandomSources.Xoroshiro.from_seed(rseed if rseed != 0 else world.rng.randi())
	if not fe.place_feature(c, cf, p):
		return false
	apply_writes(world, c)
	return true


static func apply_writes(world, c: Features.FCtx) -> void:
	var w: PackedInt32Array = c.writes
	var fl := Res.blocks.st_flags
	var om := Features.ore_table()
	for k in range(0, w.size(), 5):
		var st := w[k + 3]
		var mode := w[k + 4]
		if mode != Features.W_FORCE and not Features.write_ok(mode, world.state_at(w[k], w[k + 1], w[k + 2]), fl, om):
			continue
		world.set_block(w[k], w[k + 1], w[k + 2], st)
	for bpos in c.block_entities:
		BlockEntities.set_data(world, bpos, (c.block_entities[bpos] as Dictionary).duplicate(true))
	for en in c.entities:
		var ep: Array = en.get("p", [])
		if str(en.get("k", "")) == "mob" and ep.size() == 3:
			var m = world.entities.spawn_mob(str(en["id"]), Vector3(ep[0], ep[1], ep[2]))
			if m != null and en.get("pers", false):
				m.persistent = true
