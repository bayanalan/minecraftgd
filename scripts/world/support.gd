## Support — Java Block.canSurvive / updateShape for every block that needs a neighbour to stay: torches, wall torches,
## signs, banners, ladders, buttons, levers, tripwire hooks, amethyst buds, rails, redstone dust, repeaters, comparators,
## carpets, pressure plates, plants and crops, doors, beds, tall plants, candles, cakes, lanterns, bells, vines, glow
## lichen, cocoa, snow layers, corals, seagrass, sea pickles, lily pads, frogspawn, hanging roots, spore blossoms,
## mushrooms, mangrove propagules - and, through scheduled ticks like Java, sugar cane, cactus, bamboo, chorus, kelp /
## weeping / twisting / cave vines, pale hanging moss, pointed dripstone and scaffolding. Both halves of doors, tall
## plants and beds go together (the half left behind is destroyed with its drops; the loot tables give one item).
## BlockUpdates.fluids_changed (every notified WorldManager.set_block) hands the six neighbours of a change whose block
## has a rule here (KIND: a byte per block id, no scan) to enqueue; flush runs them like Java updateShape: only the
## neighbour the rule reads (the attachment side) re-checks, a failed rule destroys the block like Level.destroyBlock -
## drops without a tool or entity, break particles + sound, a waterlogged block leaves its water.
## Face support = Java BlockState.isFaceSturdy (SupportType FULL / CENTER / RIGID) of the support shape: the collision
## shape, except leaves (LeavesBlock.getBlockSupportShape: empty), soul sand / mud (a full block), snow layers (their
## layer height) and scaffolding (empty-context collision: none); rasterised once per state on the 16 x 16 pixel grid.
class_name Support

const K_NONE := 0
const K_TORCH := 1         # torches, candles: Block.canSupportCenter below (UP)
const K_WALL := 2          # wall torches, ladders, tripwire hooks, coral wall fans, amethyst: sturdy face behind
const K_SOLID_BELOW := 3   # standing signs / banners, cakes, candle cakes: BlockState.isSolid below
const K_SOLID_BEHIND := 4  # wall signs / banners: isSolid behind
const K_CEIL_SIGN := 5     # ceiling hanging signs: centre support above (DOWN face)
const K_FACE := 6          # buttons, levers (FaceAttachedHorizontalDirectionalBlock)
const K_RAIL := 7          # BaseRailBlock.shouldBeRemoved
const K_DIODE := 8         # repeaters, comparators: rigid support below
const K_WIRE := 9          # redstone dust: sturdy top below or a hopper
const K_CARPET := 10       # CarpetBlock: anything but air below
const K_PLATE := 11        # pressure plates: rigid or centre support below
const K_PLANT := 12        # VegetationBlock.mayPlaceOn (26.3 #supports_* tags)
const K_DOOR := 13
const K_DOUBLE := 14       # DoublePlantBlock (tall flowers / grass / ferns, pitcher plant + crop, small dripleaf, tall seagrass)
const K_BED := 15
const K_LANTERN := 16
const K_BELL := 17
const K_SNOW := 18
const K_VINE := 19
const K_MULTIFACE := 20    # glow lichen, sculk vein, resin clump
const K_COCOA := 21
const K_LILY := 22
const K_PICKLE := 23
const K_CORAL := 24
const K_SEAGRASS := 25
const K_HANG := 26         # hanging roots, spore blossom
const K_FROGSPAWN := 27
const K_MUSHROOM := 28
const K_PROPAGULE := 29
const K_SCHED := 30        # checked by a scheduled tick (Java updateShape -> scheduleTick)

const SCHEDULE := -2

const T_FULL := 0
const T_CENTER := 1
const T_RIGID := 2
const F_DOWN := 0
const F_UP := 1
const F_NORTH := 2
const F_SOUTH := 3
const F_WEST := 4
const F_EAST := 5
## Java Direction order (DOWN, UP, NORTH, SOUTH, WEST, EAST); a face's opposite is f ^ 1
const D := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const FACE_OF := {"down": 0, "up": 1, "north": 2, "south": 3, "west": 4, "east": 5}
const FACE_NAME := ["down", "up", "north", "south", "west", "east"]
const V_DOWN := Vector3i(0, -1, 0)
const V_UP := Vector3i(0, 1, 0)
const HDIRS := [Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
# rasterising: normal axis / u axis / v axis per face (0 x, 1 y, 2 z)
const _NA := [1, 1, 2, 2, 0, 0]
const _UA := [0, 0, 0, 0, 2, 2]
const _VA := [2, 2, 1, 1, 1, 1]

static var KIND := PackedByteArray()
static var _fs := PackedInt32Array()   # per state: support bits (face * 3 + type), collision full (18 + f) / any (24 + f), 1 << 30 = computed
static var _q: Array[Vector3i] = []
static var _qf: Array[Vector3i] = []
static var _flushing := false


static func face_of(v: Vector3i) -> int:
	if v.y < 0:
		return F_DOWN
	if v.y > 0:
		return F_UP
	if v.z < 0:
		return F_NORTH
	if v.z > 0:
		return F_SOUTH
	return F_WEST if v.x < 0 else F_EAST


# ---------------------------------------------------------------- kinds

static func prime() -> void:
	var b := Res.blocks
	KIND = PackedByteArray()
	KIND.resize(b.names.size())
	for bid in b.names.size():
		KIND[bid] = _kind_for(str(b.names[bid]), bid)
	_fs = PackedInt32Array()
	_fs.resize(b.st_block.size())


static func _ensure() -> void:
	if KIND.size() != Res.blocks.names.size() or _fs.size() != Res.blocks.st_block.size():
		prime()


static func kind_of(st: int) -> int:
	if st <= 0:
		return K_NONE
	_ensure()
	return KIND[Res.blocks.st_block[st]]


static func _has_vals(bid: int, prop: String, val: String) -> bool:
	for pr in Res.blocks.block_props[bid]:
		if pr[0] == prop:
			return (pr[1] as PackedStringArray).has(val)
	return false


static func _kind_for(n: String, bid: int) -> int:
	var vanilla := Res.mode == "vanilla"
	if n.ends_with("wall_torch") or n == "ladder" or n == "tripwire_hook" or n.ends_with("_coral_wall_fan") \
			or n in ["small_amethyst_bud", "medium_amethyst_bud", "large_amethyst_bud", "amethyst_cluster"]:
		return K_WALL
	if n.ends_with("torch") or n == "candle" or n.ends_with("_candle"):
		return K_TORCH
	if n.ends_with("_wall_hanging_sign"):
		return K_NONE   # wiki Hanging Sign: a wall-mounted hanging sign floats when its block is broken
	if n.ends_with("_hanging_sign"):
		return K_CEIL_SIGN
	if n.ends_with("_wall_sign") or n.ends_with("_wall_banner"):
		return K_SOLID_BEHIND
	if n.ends_with("_sign") or n.ends_with("_banner") or n == "cake" or n.ends_with("candle_cake"):
		return K_SOLID_BELOW
	if n.ends_with("_button") or n == "lever":
		return K_FACE
	if n == "rail" or n.ends_with("_rail"):
		return K_RAIL
	if n == "repeater" or n == "comparator":
		return K_DIODE
	if n == "redstone_wire":
		return K_WIRE
	if n.ends_with("_carpet"):
		return K_CARPET
	if n.ends_with("_pressure_plate"):
		return K_PLATE
	if n.ends_with("_door") and _has_vals(bid, "half", "lower"):
		return K_DOOR
	if _has_vals(bid, "part", "head") and _has_vals(bid, "part", "foot"):
		return K_BED
	if _has_vals(bid, "hanging", "true") and (Tags.has_block("lanterns", n) if vanilla else n.ends_with("lantern")):
		return K_LANTERN
	if n == "bell":
		return K_BELL
	if n == "snow":
		return K_SNOW
	if n == "vine":
		return K_VINE
	if n in ["glow_lichen", "sculk_vein", "resin_clump"]:
		return K_MULTIFACE
	if n == "cocoa":
		return K_COCOA
	if n == "lily_pad":
		return K_LILY
	if n == "sea_pickle":
		return K_PICKLE
	if n.ends_with("_coral") or n.ends_with("_coral_fan"):
		return K_CORAL
	if n == "seagrass":
		return K_SEAGRASS
	if n == "hanging_roots" or n == "spore_blossom":
		return K_HANG
	if n == "frogspawn":
		return K_FROGSPAWN
	if n == "brown_mushroom" or n == "red_mushroom":
		return K_MUSHROOM
	if n == "mangrove_propagule":
		return K_PROPAGULE
	if n in ["sugar_cane", "cactus", "bamboo", "chorus_plant", "chorus_flower", "weeping_vines", "weeping_vines_plant",
			"twisting_vines", "twisting_vines_plant", "cave_vines", "cave_vines_plant", "kelp", "kelp_plant",
			"pale_hanging_moss", "pointed_dripstone", "scaffolding"]:
		return K_SCHED
	if _has_vals(bid, "half", "lower") and _has_vals(bid, "half", "upper"):
		return K_DOUBLE
	if n == "bamboo_sapling" or n.ends_with("_cushion"):
		return K_PLANT
	if vanilla and BlockUpdates._support_tag(n) != "":
		return K_PLANT
	if n in ["short_grass", "fern", "dandelion", "poppy", "tall_grass", "large_fern", "dead_bush", "sweet_berry_bush", "allium",
			"azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "blue_orchid", "crimson_roots", "warped_roots",
			"nether_sprouts", "crimson_fungus", "warped_fungus", "wheat", "carrots", "potatoes", "beetroots", "melon_stem",
			"pumpkin_stem", "attached_melon_stem", "attached_pumpkin_stem"] or n.ends_with("_tulip") or n.ends_with("_sapling"):
		return K_PLANT
	return K_NONE


# ---------------------------------------------------------------- face support

## Java isFaceSturdy(face, type) of the state's support shape.
static func sturdy(st: int, f: int, t: int = T_FULL) -> bool:
	if st <= 0:
		return false
	return (_bits(st) >> (f * 3 + t)) & 1 == 1


## Block.isFaceFull(collision shape, face) (SnowLayerBlock, MultifaceBlock.canAttachTo).
static func coll_full(st: int, f: int) -> bool:
	return st > 0 and (_bits(st) >> (18 + f)) & 1 == 1


## The collision shape's face shape is not empty (SeaPickleBlock.mayPlaceOn).
static func coll_any(st: int, f: int) -> bool:
	return st > 0 and (_bits(st) >> (24 + f)) & 1 == 1


static func _bits(st: int) -> int:
	_ensure()
	var v := _fs[st]
	if v == 0:
		v = _compute(st)
		_fs[st] = v
	return v


static func _compute(st: int) -> int:
	var b := Res.blocks
	var v := 1 << 30
	var fl := b.st_flags[st]
	var coll := PackedFloat32Array()
	if fl & BlockRegistry.F_COLLIDE:
		coll = b.get_shape(st)
	var n := b.name_of(st)
	var sup := coll
	if (fl & BlockRegistry.F_LEAVES) != 0 or n.ends_with("_leaves") or n == "scaffolding":
		# LeavesBlock.getBlockSupportShape: Shapes.empty() (snow and vines still sit on leaves: they read the collision
		# shape); scaffolding's collision with an empty context is empty. (The wiki does not list these.)
		sup = PackedFloat32Array()
	elif n == "soul_sand" or n == "mud":
		sup = PackedFloat32Array([0, 0, 0, 1, 1, 1])   # SoulSandBlock / MudBlock.getBlockSupportShape: a full block
	elif n == "snow":
		sup = PackedFloat32Array([0, 0, 0, 1, float(int(b.get_prop(st, "layers"))) / 8.0, 1])   # SnowLayerBlock: layers x 2 px
	for f in 6:
		var cov := _raster(sup, f)
		if _covers(cov, f, T_FULL):
			v |= 1 << (f * 3 + T_FULL)
		if _covers(cov, f, T_CENTER):
			v |= 1 << (f * 3 + T_CENTER)
		if _covers(cov, f, T_RIGID):
			v |= 1 << (f * 3 + T_RIGID)
		var cc := cov if sup == coll else _raster(coll, f)
		if _covers(cc, f, T_FULL):
			v |= 1 << (18 + f)
		if cc.has(1):
			v |= 1 << (24 + f)
	return v


## Pixel cells (u, v) of face f covered by boxes reaching across the face plane (Java VoxelShape.getFaceShape: the slice
## just inside the face).
static func _raster(boxes: PackedFloat32Array, f: int) -> PackedByteArray:
	var cov := PackedByteArray()
	cov.resize(256)
	var na: int = _NA[f]
	var ua: int = _UA[f]
	var va: int = _VA[f]
	var c := 0.0001 if (f & 1) == 0 else 0.9999
	for i in range(0, boxes.size() - 5, 6):
		if not (boxes[i + na] < c and boxes[i + 3 + na] > c):
			continue
		var u0 := clampi(int(ceil(boxes[i + ua] * 16.0 - 0.5 - 0.001)), 0, 16)
		var u1 := clampi(int(floor(boxes[i + 3 + ua] * 16.0 - 0.5 + 0.001)), -1, 15)
		var v0 := clampi(int(ceil(boxes[i + va] * 16.0 - 0.5 - 0.001)), 0, 16)
		var v1 := clampi(int(floor(boxes[i + 3 + va] * 16.0 - 0.5 + 0.001)), -1, 15)
		for vv in range(v0, v1 + 1):
			for uu in range(u0, u1 + 1):
				cov[vv * 16 + uu] = 1
	return cov


## FULL: the whole face; CENTER (Block.box(7, 0, 7, 9, 10, 9)): the 2 x 2 px centre of a top / bottom face (2 x 10 px
## from the bottom on a side); RIGID (a block minus box(2, 0, 2, 14, 16, 14)): the 2 px rim of a top / bottom face.
static func _covers(cov: PackedByteArray, f: int, t: int) -> bool:
	var vertical := f <= F_UP
	for vv in 16:
		for uu in 16:
			var need := true
			if t == T_CENTER:
				need = uu >= 7 and uu <= 8 and ((vv >= 7 and vv <= 8) if vertical else vv <= 9)
			elif t == T_RIGID and vertical:
				need = uu < 2 or uu > 13 or vv < 2 or vv > 13
			if need and cov[vv * 16 + uu] == 0:
				return false
	return true


static func _at(world, q: Vector3i) -> int:
	return world.state_at(q.x, q.y, q.z)


## Support face f of the block at q (an unloaded neighbour counts as support: nothing breaks at chunk borders).
static func _sturdy_at(world, q: Vector3i, f: int, t: int = T_FULL) -> bool:
	var s := _at(world, q)
	return s < 0 or sturdy(s, f, t)


## Java Block.canSupportCenter(level, pos, face): a centre-sturdy face; never the underside of a fence gate
## (#unstable_bottom_center).
static func _center_at(world, q: Vector3i, f: int) -> bool:
	var s := _at(world, q)
	if s < 0:
		return true
	if f == F_DOWN and s > 0 and (Tags.has_block("unstable_bottom_center", Res.blocks.name_of(s)) or Res.blocks.name_of(s).ends_with("_fence_gate")):
		return false
	return sturdy(s, f, T_CENTER)


static func _solid_at(world, q: Vector3i) -> bool:
	var s := _at(world, q)
	return s < 0 or (s > 0 and (Res.blocks.st_flags[s] & BlockRegistry.F_SOLID) != 0)


## Fluid at q is a water source (Fluids.WATER: a source block or a waterlogged / always-water block).
static func _water_source_at(world, q: Vector3i) -> bool:
	var s := _at(world, q)
	if s <= 0:
		return s < 0
	var fl := Res.blocks.st_flags[s]
	if fl & BlockRegistry.F_WATERLOGGED:
		return true
	return (fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_LAVA)) == BlockRegistry.F_LIQUID and Res.blocks.st_level[s] == 0


static func _facing(st: int) -> int:
	return int(FACE_OF.get(Res.blocks.get_prop(st, "facing"), F_NORTH))


# ---------------------------------------------------------------- canSurvive

## Java Block.canSurvive (the rule placement checks too; the other half of a two-block block is updateShape's business).
static func can_survive(world, p: Vector3i, st: int) -> bool:
	if st <= 0:
		return true
	_ensure()
	var b := Res.blocks
	var k := KIND[b.st_block[st]]
	match k:
		K_NONE, K_BED:
			return true   # (BedBlock has no canSurvive: beds float)
		K_TORCH:
			return _center_at(world, p + V_DOWN, F_UP)
		K_WALL:
			var f := _facing(st)
			# WallTorchBlock / LadderBlock / TripWireHookBlock / BaseCoralWallFanBlock / AmethystClusterBlock: the block
			# behind has a full sturdy face towards it
			return _sturdy_at(world, p - (D[f] as Vector3i), f)
		K_SOLID_BELOW:
			return _solid_at(world, p + V_DOWN)
		K_SOLID_BEHIND:
			return _solid_at(world, p - (D[_facing(st)] as Vector3i))
		K_CEIL_SIGN:
			return _sturdy_at(world, p + V_UP, F_DOWN, T_CENTER)
		K_FACE:
			var fc := b.get_prop(st, "face")
			if fc == "floor":
				return _sturdy_at(world, p + V_DOWN, F_UP)
			if fc == "ceiling":
				return _sturdy_at(world, p + V_UP, F_DOWN)
			var ff := _facing(st)
			return _sturdy_at(world, p - (D[ff] as Vector3i), ff)
		K_RAIL:
			if not _sturdy_at(world, p + V_DOWN, F_UP, T_RIGID):
				return false
			var sh := b.get_prop(st, "shape")
			if sh.begins_with("ascending_"):
				var af: int = FACE_OF.get(sh.trim_prefix("ascending_"), F_NORTH)
				return _sturdy_at(world, p + (D[af] as Vector3i), F_UP, T_RIGID)
			return true
		K_DIODE:
			return _sturdy_at(world, p + V_DOWN, F_UP, T_RIGID)
		K_WIRE:
			var ws := _at(world, p + V_DOWN)
			return ws < 0 or RedstoneWire.can_survive_on(ws)   # canSurviveOn: a sturdy top or a hopper (redstone_wire.gd)
		K_CARPET:
			var cs := _at(world, p + V_DOWN)
			if b.has_prop(st, "bottom") and b.get_prop(st, "bottom") == "false":
				# MossyCarpetBlock: a pale moss carpet's top part stands on its bottom part
				return cs < 0 or (cs > 0 and b.st_block[cs] == b.st_block[st] and b.get_prop(cs, "bottom") == "true")
			return cs != 0 and (cs < 0 or (b.st_flags[cs] & BlockRegistry.F_AIR) == 0)
		K_PLATE:
			return _sturdy_at(world, p + V_DOWN, F_UP, T_RIGID) or _center_at(world, p + V_DOWN, F_UP)
		K_PLANT:
			return _plant(world, p, st)
		K_DOOR:
			if b.get_prop(st, "half") == "upper":
				var du := _at(world, p + V_DOWN)
				return du < 0 or (du > 0 and b.st_block[du] == b.st_block[st])
			return _sturdy_at(world, p + V_DOWN, F_UP)
		K_DOUBLE:
			if b.get_prop(st, "half") == "upper":
				var pu := _at(world, p + V_DOWN)
				return pu < 0 or (pu > 0 and b.st_block[pu] == b.st_block[st] and b.get_prop(pu, "half") == "lower")
			if b.name_of(st) == "tall_seagrass":
				return _seagrass_ok(world, p)
			return _plant(world, p, st)
		K_LANTERN:
			if b.get_prop(st, "hanging") == "true":
				return _center_at(world, p + V_UP, F_DOWN)
			return _center_at(world, p + V_DOWN, F_UP)
		K_BELL:
			var at := b.get_prop(st, "attachment")
			if at == "floor":
				return _sturdy_at(world, p + V_DOWN, F_UP)
			if at == "ceiling":
				return _center_at(world, p + V_UP, F_DOWN)
			var bf := _facing(st)
			return _sturdy_at(world, p + (D[bf] as Vector3i), bf ^ 1)
		K_SNOW:
			return snow_survives(world, p.x, p.y, p.z)
		K_VINE:
			return _vine_faces(world, p, st) != 0
		K_MULTIFACE:
			var any := false
			for f in 6:
				if b.get_prop(st, FACE_NAME[f]) == "true":
					if not _attach_ok(world, p + (D[f] as Vector3i), f):
						return false
					any = true
			return any
		K_COCOA:
			var cq := _at(world, p + (D[_facing(st)] as Vector3i))
			if cq < 0:
				return true
			var cn := b.name_of(maxi(cq, 0))
			return cq > 0 and (Tags.has_block("supports_cocoa", cn) if Res.mode == "vanilla" else cn in ["jungle_log", "jungle_wood", "stripped_jungle_log", "stripped_jungle_wood"])
		K_LILY:
			# WaterlilyBlock.mayPlaceOn: a water source below (or #supports_lily_pad: ice, frosted ice)
			var lq := _at(world, p + V_DOWN)
			return lq < 0 or _water_source_at(world, p + V_DOWN) or (lq > 0 and (Tags.has_block("supports_lily_pad", b.name_of(lq)) or b.name_of(lq) in ["ice", "frosted_ice"]))
		K_PICKLE:
			var pq := _at(world, p + V_DOWN)
			return pq < 0 or coll_any(pq, F_UP) or sturdy(pq, F_UP)
		K_CORAL:
			return _sturdy_at(world, p + V_DOWN, F_UP)
		K_SEAGRASS:
			return _seagrass_ok(world, p)
		K_HANG:
			if b.name_of(st) == "spore_blossom":
				return _center_at(world, p + V_UP, F_DOWN)
			return _sturdy_at(world, p + V_UP, F_DOWN)
		K_FROGSPAWN:
			return _water_source_at(world, p + V_DOWN)
		K_MUSHROOM:
			# MushroomBlock.canSurvive: on #overrides_mushroom_light_requirement, else on a solid-render block in light
			# below 13 (the light part is not checked here: a lighting update in flight must never pop mushrooms)
			var mq := _at(world, p + V_DOWN)
			if mq < 0:
				return true
			if mq == 0:
				return false
			var mn := b.name_of(mq)
			return Tags.has_block("overrides_mushroom_light_requirement", mn) or mn in ["mycelium", "podzol", "crimson_nylium", "warped_nylium"] \
				or (b.st_flags[mq] & BlockRegistry.F_OPAQUE) != 0
		K_PROPAGULE:
			if b.get_prop(st, "hanging") == "true":
				var hq := _at(world, p + V_UP)
				return hq < 0 or (hq > 0 and (Tags.has_block("supports_hanging_mangrove_propagule", b.name_of(hq)) or b.name_of(hq) == "mangrove_leaves"))
			var gq := _at(world, p + V_DOWN)
			return gq < 0 or (gq > 0 and Tags.has_block("supports_mangrove_propagule", b.name_of(gq)))
		K_SCHED:
			return _sched_ok(world, p, st)
	return true


## SnowLayerBlock.canSurvive: never on #cannot_support_snow_layer (ice, packed ice, barrier); always on
## #support_override_snow_layer (honey block, soul sand, mud); else a full top collision face (leaves too) or 8 layers.
static func snow_survives(world, x: int, y: int, z: int) -> bool:
	var below: int = world.state_at(x, y - 1, z)
	if below < 0:
		return true
	if below == 0:
		return false
	var b := Res.blocks
	var bn := b.name_of(below)
	if Tags.has_block("cannot_support_snow_layer", bn) or bn in ["ice", "packed_ice", "barrier"]:
		return false
	if Tags.has_block("support_override_snow_layer", bn) or bn in ["honey_block", "soul_sand", "mud"]:
		return true
	if bn == "snow":
		return int(b.get_prop(below, "layers")) == 8
	return coll_full(below, F_UP)


## MultifaceBlock.canAttachTo: the neighbour's face towards us is full (support or collision shape).
static func _attach_ok(world, q: Vector3i, f: int) -> bool:
	var s := _at(world, q)
	return s < 0 or sturdy(s, f ^ 1) or coll_full(s, f ^ 1)


## SeagrassBlock.mayPlaceOn: a sturdy top below that is not #cannot_support_seagrass (magma).
static func _seagrass_ok(world, p: Vector3i) -> bool:
	var s := _at(world, p + V_DOWN)
	if s < 0:
		return true
	return sturdy(s, F_UP) and not (Tags.has_block("cannot_support_seagrass", Res.blocks.name_of(s)) or Res.blocks.name_of(s) == "magma_block")


## VineBlock.getUpdatedState: the faces that still hold (up: a full face above; a side: a full face beside or the same
## side of a vine above). Returns the face bits (1 up, 2 north, 4 south, 8 west, 16 east) that remain.
static func _vine_faces(world, p: Vector3i, st: int) -> int:
	var b := Res.blocks
	var out := 0
	if b.get_prop(st, "up") == "true" and _attach_ok(world, p + V_UP, F_UP):
		out |= 1
	var above := -2
	for i in 4:
		var f := 2 + i
		var nm: String = FACE_NAME[f]
		if b.get_prop(st, nm) != "true":
			continue
		var ok := _attach_ok(world, p + (D[f] as Vector3i), f)
		if not ok:
			if above == -2:
				above = _at(world, p + V_UP)
			ok = above < 0 or (above > 0 and b.st_block[above] == b.st_block[st] and b.get_prop(above, nm) == "true")
		if ok:
			out |= 2 << i
	return out


static func _vine_state(st: int, faces: int) -> int:
	var b := Res.blocks
	var s := b.with_prop(st, "up", "true" if faces & 1 else "false")
	for i in 4:
		s = b.with_prop(s, FACE_NAME[2 + i], "true" if faces & (2 << i) else "false")
	return s


## VegetationBlock.mayPlaceOn: the 26.3 #supports_* tags (BlockUpdates._support_tag), dripleaves, cactus flower, leaf
## litter; placeholder content uses the name lists.
static func _plant(world, p: Vector3i, st: int) -> bool:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below < 0:
		return true
	var bname := blocks.name_of(maxi(below, 0))
	if name == "bamboo_sapling":
		# BambooSaplingBlock.canSurvive: #supports_bamboo below
		return below > 0 and (Tags.has_block("supports_bamboo", bname) if Res.mode == "vanilla" else bname in ["sand", "red_sand", "gravel", "dirt", "grass_block", "bamboo", "bamboo_sapling"])
	if name.ends_with("_cushion"):
		return below > 0 and (blocks.st_cull[below] >> 1) & 1 == 1
	if Res.mode == "vanilla":
		var sup := BlockUpdates._support_tag(name)
		if sup == "#dripleaf":
			return BlockUpdates._dripleaf_support(world, p, st, name, below, bname)
		if sup != "":
			# 26.3 data-driven mayPlaceOn tags; the upper half of a tall plant stands on its lower half
			if blocks.has_prop(st, "half") and blocks.get_prop(st, "half") == "upper":
				return below > 0 and blocks.st_block[below] == blocks.st_block[st]
			if sup == "#cactus_flower":
				# Java CactusFlowerBlock.mayPlaceOn: #support_override_cactus_flower or a centre-sturdy top
				return below > 0 and (Tags.has_block("support_override_cactus_flower", bname) or sturdy(below, F_UP, T_CENTER))
			if sup == "#sturdy":
				return below > 0 and sturdy(below, F_UP)   # LeafLitterBlock.canSurvive: a sturdy top below
			return below > 0 and Tags.has_block(sup, bname)
		return true
	if name in ["short_grass", "fern", "dandelion", "poppy", "tall_grass", "large_fern", "dead_bush", "sweet_berry_bush"] or name.ends_with("_tulip") or name.ends_with("_sapling") or name in ["allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "blue_orchid"]:
		return below > 0 and (bname in ["grass_block", "dirt", "podzol", "coarse_dirt", "farmland", "moss_block", "mud", "rooted_dirt", "mycelium", "sand", "red_sand", "terracotta"] or bname == name and blocks.has_prop(st, "half"))
	if name in ["crimson_roots", "warped_roots", "nether_sprouts", "crimson_fungus", "warped_fungus"]:
		return below > 0 and bname in ["crimson_nylium", "warped_nylium", "soul_soil", "grass_block", "dirt", "podzol", "coarse_dirt", "farmland", "moss_block", "mud", "rooted_dirt", "mycelium", "muddy_mangrove_roots", "pale_moss_block"]
	if name in ["wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "attached_melon_stem", "attached_pumpkin_stem"]:
		return bname == "farmland"
	return true


## The blocks Java checks on a scheduled tick: sugar cane, cactus, bamboo, chorus, growing plants, pale hanging moss,
## pointed dripstone, scaffolding.
static func _sched_ok(world, p: Vector3i, st: int) -> bool:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below < 0:
		return true
	var bname := blocks.name_of(maxi(below, 0))
	var vanilla := Res.mode == "vanilla"
	match name:
		"sugar_cane":
			# wiki Sugar Cane: on sugar cane, or on grass / dirt / podzol / mycelium / sand / moss / mud (26.3
			# #supports_sugar_cane) whose side touches water, a waterlogged block or frosted ice
			# (#supports_sugar_cane_adjacently) - not above / diagonal
			if bname == "sugar_cane":
				return true
			var scs := Tags.blocks("supports_sugar_cane")
			if below <= 0 or not (scs.has(bname) if not scs.is_empty() else bname in ["grass_block", "dirt", "coarse_dirt", "rooted_dirt", "podzol", "mycelium", "sand", "red_sand", "suspicious_sand", "moss_block", "pale_moss_block", "mud", "muddy_mangrove_roots"]):
				return false
			for d in BlockUpdates.HDIRS:
				var ws: int = world.state_at(p.x + d.x, p.y - 1, p.z + d.z)
				if ws < 0 or BlockUpdates._same_fluid(ws, false) or (ws > 0 and (blocks.name_of(ws) == "frosted_ice" or Tags.has_block("supports_sugar_cane_adjacently", blocks.name_of(ws)))):
					return true
			return false
		"cactus":
			# wiki Cactus: breaks with a legacy-solid block or lava beside it, or water / lava above; stands on cactus or
			# #supports_cactus (#sand)
			for d2 in BlockUpdates.HDIRS:
				var ss: int = world.state_at(p.x + d2.x, p.y, p.z + d2.z)
				if ss > 0 and (blocks.st_flags[ss] & (BlockRegistry.F_SOLID | BlockRegistry.F_LAVA)) != 0:
					return false
			var cup: int = world.state_at(p.x, p.y + 1, p.z)
			if cup > 0 and (blocks.st_flags[cup] & BlockRegistry.F_LIQUID) != 0:
				return false
			return bname == "cactus" or (Tags.has_block("supports_cactus", bname) if vanilla and not Tags.blocks("supports_cactus").is_empty() else bname in ["sand", "red_sand", "suspicious_sand"])
		"bamboo":
			return below > 0 and (Tags.has_block("supports_bamboo", bname) if vanilla else bname in ["sand", "red_sand", "gravel", "dirt", "grass_block", "bamboo", "bamboo_sapling"])
		"chorus_plant":
			# ChorusPlantBlock.canSurvive
			var vert := _at(world, p + V_UP) != 0 and below != 0
			for d3 in BlockUpdates.HDIRS:
				var hs := _at(world, p + d3)
				if hs > 0 and blocks.name_of(hs) == "chorus_plant":
					if vert:
						return false
					var hb := _at(world, p + d3 + V_DOWN)
					if hb < 0 or (hb > 0 and (blocks.name_of(hb) == "chorus_plant" or _chorus_base(blocks.name_of(hb), "supports_chorus_plant"))):
						return true
			return below > 0 and (bname == "chorus_plant" or _chorus_base(bname, "supports_chorus_plant"))
		"chorus_flower":
			# ChorusFlowerBlock.canSurvive
			if below > 0 and (bname == "chorus_plant" or _chorus_base(bname, "supports_chorus_flower")):
				return true
			if below != 0:
				return false
			var found := false
			for d4 in BlockUpdates.HDIRS:
				var fs := _at(world, p + d4)
				if fs > 0 and blocks.name_of(fs) == "chorus_plant":
					if found:
						return false
					found = true
				elif fs != 0:
					return false
			return found
		"weeping_vines", "weeping_vines_plant", "cave_vines", "cave_vines_plant":
			return _growing_ok(world, p, name, V_UP, F_DOWN)
		"twisting_vines", "twisting_vines_plant", "kelp", "kelp_plant":
			return _growing_ok(world, p, name, V_DOWN, F_UP)
		"pale_hanging_moss":
			# HangingMossBlock.canStayAtPosition: a full face above (support or collision: leaves) or more moss
			var ms := _at(world, p + V_UP)
			return ms < 0 or (ms > 0 and blocks.name_of(ms) == "pale_hanging_moss") or _attach_ok(world, p + V_UP, F_UP)
		"pointed_dripstone":
			# PointedDripstoneBlock.isValidPointedDripstonePlacement: a sturdy face behind the tip or more dripstone
			# pointing the same way
			var up := blocks.get_prop(st, "vertical_direction") != "down"
			var bq := p + (V_DOWN if up else V_UP)
			var bs := _at(world, bq)
			if bs < 0 or sturdy(bs, F_UP if up else F_DOWN):
				return true
			return bs > 0 and blocks.name_of(bs) == "pointed_dripstone" and blocks.get_prop(bs, "vertical_direction") == blocks.get_prop(st, "vertical_direction")
		"scaffolding":
			return scaffold_distance(world, p) < 7
	return true


static func _chorus_base(n: String, tag: String) -> bool:
	return Tags.has_block(tag, n) or n == "end_stone"


## GrowingPlantBlock.canSurvive: the block it grows from is the same plant or has a sturdy face towards it (kelp: not
## #cannot_support_kelp - magma).
static func _growing_ok(world, p: Vector3i, name: String, attach: Vector3i, face: int) -> bool:
	var s := _at(world, p + attach)
	if s < 0:
		return true
	if s == 0:
		return false
	var an := Res.blocks.name_of(s)
	var fam := name.trim_suffix("_plant")
	if an == fam or an == fam + "_plant":
		return true
	if fam == "kelp" and (Tags.has_block("cannot_support_kelp", an) or an == "magma_block"):
		return false
	return sturdy(s, face)


## ScaffoldingBlock.getDistance: 0 on a sturdy top, else the scaffolding below / beside + 1 (7 = unsupported).
static func scaffold_distance(world, p: Vector3i) -> int:
	var b := Res.blocks
	var bs := _at(world, p + V_DOWN)
	if bs < 0:
		return 0
	var d := 7
	if bs > 0 and b.name_of(bs) == "scaffolding":
		d = int(b.get_prop(bs, "distance"))
	elif sturdy(bs, F_UP):
		return 0
	for h in HDIRS:
		var hs := _at(world, p + h)
		if hs > 0 and b.name_of(hs) == "scaffolding":
			d = mini(d, int(b.get_prop(hs, "distance")) + 1)
			if d == 1:
				break
	return d


## ScaffoldingBlock placement state: distance + bottom (distance > 0 and no scaffolding below).
static func scaffold_state(world, p: Vector3i, st: int) -> int:
	var b := Res.blocks
	var d := scaffold_distance(world, p)
	var bs := _at(world, p + V_DOWN)
	var bottom := d > 0 and not (bs > 0 and b.name_of(bs) == "scaffolding")
	return b.with_prop(b.with_prop(st, "distance", str(d)), "bottom", "true" if bottom else "false")


# ---------------------------------------------------------------- updateShape

## Java updateShape of the block at p after its neighbour in direction `from` changed (Vector3i.ZERO: every side).
## Returns st (unchanged), 0 (destroy it), another state (set it) or SCHEDULE (a tick decides).
static func update_shape(world, p: Vector3i, st: int, from: Vector3i) -> int:
	_ensure()
	var b := Res.blocks
	var k := KIND[b.st_block[st]]
	var any := from == Vector3i.ZERO
	match k:
		K_NONE:
			return st
		K_TORCH, K_SOLID_BELOW, K_PLATE, K_CORAL:
			if not any and from != V_DOWN:
				return st
		# (K_DIODE, K_WIRE, K_RAIL: DiodeBlock / RedStoneWireBlock / BaseRailBlock.neighborChanged check canSurvive on
		# a change from any side)
		K_WALL, K_SOLID_BEHIND:
			if not any and from != -(D[_facing(st)] as Vector3i):
				return st
		K_CEIL_SIGN, K_HANG:
			if not any and from != V_UP:
				return st
		K_FACE:
			if not any:
				var fc := b.get_prop(st, "face")
				var sup := V_DOWN if fc == "floor" else (V_UP if fc == "ceiling" else -(D[_facing(st)] as Vector3i))
				if from != sup:
					return st
		K_LANTERN:
			if not any and from != (V_UP if b.get_prop(st, "hanging") == "true" else V_DOWN):
				return st
		K_COCOA:
			if not any and from != (D[_facing(st)] as Vector3i):
				return st
		K_DOOR:
			var upper := b.get_prop(st, "half") == "upper"
			var pq := p + (V_DOWN if upper else V_UP)
			if any or from == (V_DOWN if upper else V_UP):
				# DoorBlock.updateShape: the other half must be a door's other half
				var ps := _at(world, pq)
				if ps == 0 or (ps > 0 and not (b.name_of(ps).ends_with("_door") and b.has_prop(ps, "half") and b.get_prop(ps, "half") != b.get_prop(st, "half"))):
					return 0
			if not upper and (any or from == V_DOWN) and not can_survive(world, p, st):
				return 0
			return st
		K_DOUBLE:
			var up2 := b.get_prop(st, "half") == "upper"
			var young := b.name_of(st) == "pitcher_crop" and int(b.get_prop(st, "age")) < 3   # PitcherCropBlock: single below age 3
			if not up2 and not young and (any or from == V_UP):
				var ps2 := _at(world, p + V_UP)
				if ps2 == 0 or (ps2 > 0 and not (b.st_block[ps2] == b.st_block[st] and b.get_prop(ps2, "half") == "upper")):
					return 0
			return st if can_survive(world, p, st) else 0
		K_BED:
			var head := b.get_prop(st, "part") == "head"
			var bd := D[_facing(st)] as Vector3i
			var toward := -bd if head else bd
			if any or from == toward:
				var bs := _at(world, p + toward)
				if bs == 0 or (bs > 0 and not (b.st_block[bs] == b.st_block[st] and b.get_prop(bs, "part") != b.get_prop(st, "part"))):
					return 0
			return st
		K_BELL:
			return _bell_update(world, p, st, from)
		K_VINE:
			if not any and from == V_DOWN:
				return st
			var vf := _vine_faces(world, p, st)
			return 0 if vf == 0 else _vine_state(st, vf)
		K_MULTIFACE:
			var ns := st
			var left := 0
			for f in 6:
				var fname: String = FACE_NAME[f]
				if b.get_prop(ns, fname) != "true":
					continue
				if (any or from == (D[f] as Vector3i)) and not _attach_ok(world, p + (D[f] as Vector3i), f):
					ns = b.with_prop(ns, fname, "false")
				else:
					left += 1
			return 0 if left == 0 else ns
		K_SCHED:
			if b.name_of(st) == "scaffolding" or not can_survive(world, p, st):
				return SCHEDULE
			return st
	return st if can_survive(world, p, st) else 0


## BellBlock.updateShape: a double-wall bell losing a side hangs from the other one (single wall, facing it); a single
## wall bell meeting a second sturdy side becomes double; otherwise it breaks without its attachment.
static func _bell_update(world, p: Vector3i, st: int, from: Vector3i) -> int:
	var b := Res.blocks
	var at := b.get_prop(st, "attachment")
	var f := _facing(st)
	var dirs: Array = [from] if from != Vector3i.ZERO else D
	var s := st
	for dv in dirs:
		var d: Vector3i = dv
		var fd := face_of(d)
		var conn := V_DOWN if at == "floor" else (V_UP if at == "ceiling" else (D[f] as Vector3i))
		if d == conn and at != "double_wall" and not can_survive(world, p, s):
			return 0
		if (fd >> 1) == (f >> 1) and fd > F_UP:
			var nst := _at(world, p + d)
			if at == "double_wall" and not (nst < 0 or sturdy(nst, fd ^ 1)):
				s = b.with_prop(b.with_prop(s, "attachment", "single_wall"), "facing", FACE_NAME[fd ^ 1])
				at = "single_wall"
				f = fd ^ 1
				if not can_survive(world, p, s):
					return 0
			elif at == "single_wall" and fd == (f ^ 1) and nst > 0 and sturdy(nst, f):
				s = b.with_prop(s, "attachment", "double_wall")
				at = "double_wall"
	return s


# ---------------------------------------------------------------- queue / destroy

## A block at q whose rule may read its neighbour in direction from (q -> the change) - called by
## BlockUpdates.fluids_changed for each neighbour with KIND != 0.
static func enqueue(q: Vector3i, from: Vector3i) -> void:
	_q.append(q)
	_qf.append(from)


## Runs the queued checks (destroying adds more: a queue, like Java's neighbour updater, not deep recursion).
static func flush(world) -> void:
	if _flushing or _q.is_empty():
		return
	_ensure()
	_flushing = true
	var b := Res.blocks
	var i := 0
	while i < _q.size() and i < 16384:
		var q: Vector3i = _q[i]
		var from: Vector3i = _qf[i]
		i += 1
		var st: int = world.state_at(q.x, q.y, q.z)
		if st <= 0 or KIND[b.st_block[st]] == K_NONE:
			continue
		var ns := update_shape(world, q, st, from)
		if ns == st:
			continue
		if ns == SCHEDULE:
			var stal := b.name_of(st) == "pointed_dripstone" and b.get_prop(st, "vertical_direction") == "down"
			BlockUpdates.schedule(world, q, 2 if stal else 1)
		elif ns == 0:
			destroy(world, q, st)
		else:
			world.set_block(q.x, q.y, q.z, ns)
	_q.clear()
	_qf.clear()
	_flushing = false


## Java Level.destroyBlock(pos, true): loot without a tool or entity (snow and chorus flowers drop nothing, doors /
## beds / tall plants one item from the half the loot table names), the block's water stays (waterlogged, seagrass,
## kelp), levelEvent 2001 (break particles + sound), block-entity data removed, redstone / tripwire neighbours told.
static func destroy(world, p: Vector3i, st: int, drops := true) -> void:
	var b := Res.blocks
	var be: Dictionary = {}
	if world.get("cm") != null:
		be = BlockEntities.get_data(world, p).duplicate(true)
	var items: Array = []
	if drops and world.gamerule("doTileDrops", true):
		items = Loot.block_drops(st, null, world, p, be)
	var repl: int = b.WATER if (b.st_flags[st] & BlockRegistry.F_WATERLOGGED) != 0 else 0
	world.set_block(p.x, p.y, p.z, repl)
	var ents = world.get("entities")
	if ents != null:
		for s in items:
			ents.spawn_item(Vector3(p) + Vector3(0.5, 0.3, 0.5), s)
		if ents.has_method("spawn_block_particles"):
			ents.spawn_block_particles(p, st)
			BlockProperties.play_block_sound(st, "break", Vector3(p) + Vector3(0.5, 0.5, 0.5))
	if not be.is_empty():
		BlockEntities.on_removed(world, p, st)
	var n := b.name_of(st)
	if n == "tripwire_hook":
		Tripwires.on_removed(world, p, st, false)
	if n.ends_with("_button") or n == "lever" or n == "redstone_wire" or n == "repeater" or n == "comparator" or n.contains("redstone") \
			or n.ends_with("_pressure_plate") or n.ends_with("rail") or n == "tripwire_hook":
		Redstone.on_changed(world, p)


## Scheduled tick of a K_SCHED block (or any block BlockUpdates scheduled that has a rule): Java tick -> destroyBlock
## when it cannot survive; scaffolding recounts its distance (falls at 7 twice in a row, else breaks); unsupported
## stalactites fall (PointedDripstoneBlock.spawnFallingStalactite), stalagmites break. True when a block was removed.
static func tick(world, p: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var n := b.name_of(st)
	if n == "scaffolding":
		var ns := scaffold_state(world, p, st)
		if b.get_prop(ns, "distance") == "7":
			if b.get_prop(st, "distance") == "7":
				world.set_block(p.x, p.y, p.z, b.WATER if b.get_prop(st, "waterlogged") == "true" else 0)
				if world.get("entities") != null and world.entities.has_method("spawn_falling_block"):
					world.entities.spawn_falling_block(p, b.with_prop(ns, "waterlogged", "false"))
			else:
				destroy(world, p, st)
			return true
		if ns != st:
			world.set_block(p.x, p.y, p.z, ns)
		return false
	var k := kind_of(st)
	if k == K_VINE or k == K_MULTIFACE:
		# (a 1-tick update from schedule_neighbors: vines / lichen lose the faces that no longer hold rather than vanish)
		var us := update_shape(world, p, st, Vector3i.ZERO)
		if us == 0:
			destroy(world, p, st)
			return true
		if us != st and us > 0:
			world.set_block(p.x, p.y, p.z, us)
		return false
	# canSurvive only - never the other-half rule: schedule_neighbors also ticks the block itself, and a lone door half
	# set by /setblock stays like Java's (it goes when its other-half neighbour changes)
	if can_survive(world, p, st):
		return false
	if n == "pointed_dripstone" and b.get_prop(st, "vertical_direction") == "down":
		var q := p
		var qs := st
		while qs > 0 and b.name_of(qs) == "pointed_dripstone" and b.get_prop(qs, "vertical_direction") == "down":
			world.set_block(q.x, q.y, q.z, b.WATER if b.get_prop(qs, "waterlogged") == "true" else 0)
			if world.get("entities") != null and world.entities.has_method("spawn_falling_block"):
				world.entities.spawn_falling_block(q, b.with_prop(qs, "waterlogged", "false"))
			if b.get_prop(qs, "thickness") == "tip":
				break
			q += V_DOWN
			qs = _at(world, q)
		return true
	destroy(world, p, st)
	return true


## DoublePlantBlock.preventDropFromBottomPart / BedBlock.playerWillDestroy (creative): breaking the upper half of a
## door / tall plant, or a bed's foot, first removes the other half without drops (it would otherwise drop the item).
static func creative_break_partner(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var k := kind_of(st)
	var q := Vector3i(0, -99999, 0)
	if (k == K_DOOR or k == K_DOUBLE) and b.get_prop(st, "half") == "upper":
		q = p + V_DOWN
	elif k == K_BED and b.get_prop(st, "part") == "foot":
		q = p + (D[_facing(st)] as Vector3i)
	if q.y == -99999:
		return
	var qs := _at(world, q)
	if qs <= 0 or b.st_block[qs] != b.st_block[st]:
		return
	if (k == K_BED and b.get_prop(qs, "part") != "head") or (k != K_BED and b.get_prop(qs, "half") != "lower"):
		return
	world.set_block(q.x, q.y, q.z, b.WATER if (b.st_flags[qs] & BlockRegistry.F_WATERLOGGED) != 0 else 0)
	if world.get("entities") != null and world.entities.has_method("spawn_block_particles"):
		world.entities.spawn_block_particles(q, qs)


# ---------------------------------------------------------------- placement

## Java BlockPlaceContext.getNearestLookingDirections: the clicked face's opposite first (unless the clicked block is
## being replaced), then Direction.orderedByNearest(player). Faces as ints (Support.F_*).
static func looking_dirs(p, n: Vector3i, replace_clicked: bool) -> Array:
	var dirs := ordered_by_nearest(float(p.yaw), float(p.pitch))
	if replace_clicked:
		return dirs
	var first := face_of(-n)
	var out: Array = [first]
	for d in dirs:
		if d != first:
			out.append(d)
	return out


## Java Direction.orderedByNearest (yaw 0 = south, pitch > 0 = looking down).
static func ordered_by_nearest(yaw: float, pitch: float) -> Array:
	var pr := deg_to_rad(pitch)
	var yr := -deg_to_rad(yaw)
	var sp := sin(pr)
	var cp := cos(pr)
	var sy := sin(yr)
	var cy := cos(yr)
	var east := sy > 0.0
	var up := sp < 0.0
	var south := cy > 0.0
	var ex := sy if east else -sy
	var uy := -sp if up else sp
	var sz := cy if south else -cy
	var hx := ex * cp
	var hz := sz * cp
	var dx := F_EAST if east else F_WEST
	var dy := F_UP if up else F_DOWN
	var dz := F_SOUTH if south else F_NORTH
	if ex > sz:
		if uy > hx:
			return _dir_arr(dy, dx, dz)
		return _dir_arr(dx, dz, dy) if hz > uy else _dir_arr(dx, dy, dz)
	if uy > hz:
		return _dir_arr(dy, dz, dx)
	return _dir_arr(dz, dx, dy) if hx > uy else _dir_arr(dz, dy, dx)


static func _dir_arr(a: int, b: int, c: int) -> Array:
	return [a, b, c, c ^ 1, b ^ 1, a ^ 1]


## The state a block item places at dest (Java getStateForPlacement + BlockItem.canPlace -> canSurvive), or -1 when it
## cannot be placed there: torches / signs / banners / coral fans try the wall and the standing form in the nearest
## looking directions (StandingAndWallBlockItem), buttons and levers every face (FaceAttachedHorizontalDirectionalBlock),
## ladders, tripwire hooks and cocoa the horizontal ones; doors / tall plants need a replaceable block above, beds at the
## head; scaffolding takes its distance; everything else must survive where it is.
static func placement(world, st: int, dest: Vector3i, n: Vector3i, p, replace_clicked: bool) -> int:
	_ensure()
	var b := Res.blocks
	var name := b.name_of(st)
	var k := KIND[b.st_block[st]]
	var dirs := looking_dirs(p, n, replace_clicked)
	var standing := ""
	var wall := ""
	if name.ends_with("_wall_hanging_sign"):
		standing = name.replace("_wall_hanging_sign", "_hanging_sign")
		wall = name
	elif name.ends_with("_hanging_sign"):
		standing = name
		wall = name.replace("_hanging_sign", "_wall_hanging_sign")
	elif name.ends_with("wall_torch"):
		standing = name.replace("wall_torch", "torch")
		wall = name
	elif name.ends_with("torch") and k == K_TORCH:
		standing = name
		wall = name.trim_suffix("torch") + "wall_torch"
	elif name.ends_with("_wall_sign") or name.ends_with("_wall_banner") or name.ends_with("_coral_wall_fan"):
		standing = name.replace("_wall_", "_")
		wall = name
	elif name.ends_with("_sign") or name.ends_with("_banner") or name.ends_with("_coral_fan"):
		standing = name
		wall = name.trim_suffix("_sign").trim_suffix("_banner").trim_suffix("_fan") + ("_wall_sign" if name.ends_with("_sign") else ("_wall_banner" if name.ends_with("_banner") else "_wall_fan"))
	if standing != "" and b.block_id(standing) >= 0 and b.block_id(wall) >= 0:
		var hanging := standing.ends_with("_hanging_sign")
		var attach := F_UP if hanging else F_DOWN   # StandingAndWallBlockItem.attachmentDirection
		var std_st := st if b.name_of(st) == standing else _copy_props(st, b.default_state(standing))
		if b.has_prop(std_st, "rotation") and b.name_of(st) != standing:
			# (signs / banners face the player: yaw + 180, 16 segments)
			std_st = b.with_prop(std_st, "rotation", str(int(floor(fposmod(float(p.yaw) + 180.0, 360.0) * 16.0 / 360.0 + 0.5)) & 15))
		if hanging and b.has_prop(std_st, "attached"):
			# CeilingHangingSignBlock.getStateForPlacement: chains meet (attached, 16 rotations) under a block without a
			# full bottom face or while sneaking; else the sign squares up with the player (4 rotations)
			var above := _at(world, dest + V_UP)
			var attached := bool(p.get("sneaking")) or not coll_full(above, F_DOWN)
			std_st = b.with_prop(std_st, "attached", "true" if attached else "false")
			if not attached:
				var seg := {"south": 0, "west": 4, "north": 8, "east": 12}
				std_st = b.with_prop(std_st, "rotation", str(seg.get(Interaction.opposite(Interaction.horizontal_facing(float(p.yaw))), 0)))
		var wall_st := _wall_placement(world, dest, b.default_state(wall), dirs, n, hanging, st if b.name_of(st) == wall else -1)
		for d in dirs:
			if d == (attach ^ 1):
				continue
			var cand: int = std_st if d == attach else wall_st
			if cand > 0 and can_survive(world, dest, cand):
				return cand
		return -1
	match k:
		K_FACE:
			var look := Interaction.horizontal_facing(float(p.yaw))
			for d in dirs:
				var cand2: int
				if d <= F_UP:
					cand2 = b.with_prop(b.with_prop(st, "face", "ceiling" if d == F_UP else "floor"), "facing", look)
				else:
					cand2 = b.with_prop(b.with_prop(st, "face", "wall"), "facing", FACE_NAME[d ^ 1])
				if can_survive(world, dest, cand2):
					return cand2
			return -1
		K_WALL:
			if name == "ladder" and not replace_clicked:
				# LadderBlock: clicking a ladder's front face places nothing
				var cs := _at(world, dest - n)
				if cs > 0 and b.st_block[cs] == b.st_block[st] and b.get_prop(cs, "facing") == FACE_NAME[face_of(n)]:
					return -1
			if name == "ladder" or name == "tripwire_hook":
				for d in dirs:
					if d > F_UP:
						var cand3 := b.with_prop(st, "facing", FACE_NAME[d ^ 1])
						if can_survive(world, dest, cand3):
							return cand3
				return -1
		K_COCOA:
			for d in dirs:
				if d > F_UP:
					var cand4 := b.with_prop(st, "facing", FACE_NAME[d])
					if can_survive(world, dest, cand4):
						return cand4
			return -1
		K_DOOR, K_DOUBLE:
			# DoorBlock / DoublePlantBlock.getStateForPlacement: the lower half, with a replaceable block above it
			# (PitcherCropBlock: a single block while young)
			st = b.with_prop(st, "half", "lower")
			var au := _at(world, dest + V_UP)
			if name != "pitcher_crop" and (au < 0 or (au > 0 and (b.st_flags[au] & BlockRegistry.F_REPLACEABLE) == 0) or dest.y + 1 >= Coords.MAX_Y):
				return -1
		K_BED:
			var hp := dest + (D[_facing(st)] as Vector3i)
			var hs := _at(world, hp)
			if hs < 0 or (hs > 0 and (b.st_flags[hs] & BlockRegistry.F_REPLACEABLE) == 0):
				return -1
		K_SCHED:
			if name == "scaffolding":
				st = scaffold_state(world, dest, st)
			elif name == "pointed_dripstone":
				# PointedDripstoneBlock.getStateForPlacement: tip away from the nearest vertical looking direction, else
				# the other way when only that one holds
				var want := "down" if float(p.pitch) < 0.0 else "up"
				var cand5 := b.with_prop(st, "vertical_direction", want)
				if not can_survive(world, dest, cand5):
					cand5 = b.with_prop(st, "vertical_direction", "up" if want == "down" else "down")
				st = cand5
		K_BELL:
			return _bell_placement(world, dest, st, n, p)
		K_VINE:
			# VineBlock.getStateForPlacement: the first looking direction (not down) whose side holds a vine face
			var cur := _at(world, dest)
			var base := cur if cur > 0 and b.st_block[cur] == b.st_block[st] else st
			for d in dirs:
				if d == F_DOWN:
					continue
				if b.get_prop(base, FACE_NAME[d]) == "true":
					continue
				var ok := _attach_ok(world, dest + (D[d] as Vector3i), d)
				if not ok and d > F_UP:
					var va := _at(world, dest + V_UP)
					ok = va > 0 and b.st_block[va] == b.st_block[st] and b.get_prop(va, FACE_NAME[d]) == "true"
				if ok:
					return b.with_prop(base, FACE_NAME[d], "true")
			return -1
		K_MULTIFACE:
			# MultifaceBlock.getStateForPlacement: the first looking direction whose neighbour face is full
			var cur2 := _at(world, dest)
			var base2 := cur2 if cur2 > 0 and b.st_block[cur2] == b.st_block[st] else st
			for d in dirs:
				if b.get_prop(base2, FACE_NAME[d]) != "true" and _attach_ok(world, dest + (D[d] as Vector3i), d):
					return b.with_prop(base2, FACE_NAME[d], "true")
			return -1
	if not can_survive(world, dest, st):
		return -1
	# light part of canSurvive (placement only: a relight in flight must never pop placed blocks) - wiki Wheat Seeds:
	# crops need light 8 to be planted (CropBlock.hasSufficientLight); MushroomBlock: light below 13 off mycelium /
	# podzol / nylium
	var lt := _raw_light(world, dest)
	if lt >= 0:
		if (name in ["wheat", "carrots", "potatoes", "beetroots", "torchflower_crop"] or (name == "pitcher_crop" and b.get_prop(st, "half") != "upper")) and lt < 8:
			return -1
		if k == K_MUSHROOM and lt >= 13:
			var mb := _at(world, dest + V_DOWN)
			if not (mb > 0 and (Tags.has_block("overrides_mushroom_light_requirement", b.name_of(mb)) or b.name_of(mb) in ["mycelium", "podzol", "crimson_nylium", "warped_nylium"])):
				return -1
	return st


## Level.getRawBrightness(pos, 0): max(sky, block) light, -1 when the world has no light data here.
static func _raw_light(world, p: Vector3i) -> int:
	var cm = world.get("cm")
	if cm == null or not cm.has_method("get_light"):
		return -1
	var l: int = cm.get_light(p.x, p.y, p.z)
	return maxi(l >> 4, l & 15)


## BellBlock.getStateForPlacement: clicked top / bottom -> floor / ceiling facing the player; a side -> a wall bell
## facing into the clicked block (double when both sides on that axis are sturdy), else floor / ceiling.
static func _bell_placement(world, dest: Vector3i, st: int, n: Vector3i, p) -> int:
	var b := Res.blocks
	if n.y != 0:
		var s := b.with_prop(b.with_prop(st, "attachment", "ceiling" if n.y < 0 else "floor"), "facing", Interaction.horizontal_facing(float(p.yaw)))
		return s if can_survive(world, dest, s) else -1
	var f := face_of(-n)
	var lo := f & ~1
	var dbl := _sturdy_at(world, dest + (D[lo] as Vector3i), lo ^ 1) and _sturdy_at(world, dest + (D[lo ^ 1] as Vector3i), lo)
	var s2 := b.with_prop(b.with_prop(st, "facing", FACE_NAME[f]), "attachment", "double_wall" if dbl else "single_wall")
	if can_survive(world, dest, s2):
		return s2
	s2 = b.with_prop(s2, "attachment", "floor" if _sturdy_at(world, dest + V_DOWN, F_UP) else "ceiling")
	return s2 if can_survive(world, dest, s2) else -1


## The wall form's getStateForPlacement: WallTorchBlock / WallSignBlock / WallBannerBlock / coral wall fans - the first
## horizontal looking direction whose block survives (facing away from it); WallHangingSignBlock - a horizontal looking
## direction not on the clicked face's axis whose either side holds it (canPlace).
static func _wall_placement(world, dest: Vector3i, wall_st: int, dirs: Array, n: Vector3i, hanging: bool, given: int) -> int:
	var b := Res.blocks
	if given > 0:
		wall_st = given
	for d in dirs:
		if d <= F_UP:
			continue
		if hanging:
			if (d >> 1) == (face_of(n) >> 1):
				continue
			var hs := b.with_prop(wall_st, "facing", FACE_NAME[d ^ 1])
			if _wall_hanging_ok(world, dest, d ^ 1):
				return hs
			continue
		var cand := b.with_prop(wall_st, "facing", FACE_NAME[d ^ 1])
		if can_survive(world, dest, cand):
			return cand
	return -1


## WallHangingSignBlock.canPlace: a full sturdy side (or a wall hanging sign on the same axis) on either side of it.
static func _wall_hanging_ok(world, dest: Vector3i, facing: int) -> bool:
	var b := Res.blocks
	# clockwise / counter-clockwise of a horizontal facing: north <-> east / west, south <-> west / east
	var sides: Array = [F_EAST, F_WEST] if (facing >> 1) == 1 else [F_SOUTH, F_NORTH]
	for sd in sides:
		var s := _at(world, dest + (D[sd] as Vector3i))
		if s < 0:
			return true
		if s > 0 and b.name_of(s).ends_with("_wall_hanging_sign"):
			if (_facing(s) >> 1) == (facing >> 1):
				return true
		elif sturdy(s, sd ^ 1):
			return true
	return false


static func _copy_props(from_st: int, to_st: int) -> int:
	var b := Res.blocks
	var s := to_st
	for k in ["rotation", "waterlogged", "facing"]:
		if b.has_prop(from_st, k) and b.has_prop(to_st, k):
			s = b.with_prop(s, k, b.get_prop(from_st, k))
	return s
