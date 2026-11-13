## BlockUpdates — 20 TPS scheduled ticks + random ticks (randomTickSpeed per section, only sections whose
## palette contains a random-ticking state), neighbour-triggered checks: fluid flow (water 5t / lava 30t,
## falling columns, source creation, lava/water -> obsidian/cobblestone/stone), gravity blocks -> falling
## entities, crops/saplings/stems growth, grass spread/decay, leaf decay, ice/snow melt, fire burn-out,
## plant support breaking, button release. Bounded work per tick (MAX_PER_TICK).
## Contract: schedule(world, pos, delay), schedule_neighbors(world, pos), tick(world), bonemeal(world,pos,st).
class_name BlockUpdates

const MAX_PER_TICK := 2000
static var queue: Dictionary = {}   # due tick -> Array[Vector3i]
static var pending: Dictionary = {} # Vector3i -> due (dedupe)
static var _rt_rng := RandomNumberGenerator.new()
static var last_sched := 0
static var last_random_us := 0
static var prof := false           # load-test tracing: per-block random tick handler time
static var prof_us: Dictionary = {}
static var prof_n: Dictionary = {}


static func reset() -> void:
	queue.clear()
	pending.clear()
	rtl_dirty = true
	_rtb_active = false
	_rtb_again = false
	_rts_active = false
	_rtl_lst = []
	_rtl_chs = []
	_rt_hits = PackedInt32Array()
	_rt_chs = []
	_rt_hi = 0


## Java LavaFluid.getTickDelay: 10 where lava is fast (dimension attribute minecraft:gameplay/fast_lava: the Nether), else 30.
static func lava_delay(world) -> int:
	var at = world.dim_type.get("attributes", {}) if world.dim_type is Dictionary else {}
	return 10 if at is Dictionary and bool((at as Dictionary).get("minecraft:gameplay/fast_lava", false)) else 30


static func schedule(world, p: Vector3i, delay: int) -> void:
	var due: int = world.game_time + maxi(1, delay)
	if pending.has(p) and int(pending[p]) <= due:
		return
	pending[p] = due
	if not queue.has(due):
		queue[due] = []
	queue[due].append(p)


static func schedule_neighbors(world, p: Vector3i) -> void:
	for d in [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i.ZERO]:
		var q: Vector3i = p + d
		var st: int = world.state_at(q.x, q.y, q.z)
		if st <= 0:
			continue
		var fl := Res.blocks.st_flags[st]
		if fl & BlockRegistry.F_LIQUID:
			# only the fluid's own tick delay (water is non-colliding too: the generic 1-tick update below made flows
			# advance every tick wherever neighbour updates fired)
			schedule(world, q, lava_delay(world) if fl & BlockRegistry.F_LAVA else 5)
			continue
		if fl & BlockRegistry.F_WATERLOGGED:
			schedule(world, q, 5)
		if Res.blocks.st_block[st] == _fire_id():
			fire_update_shape(world, q, st)   # FireBlock.updateShape: survive check now, its own tick keeps going
			continue
		if fl & (BlockRegistry.F_GRAVITY):
			schedule(world, q, 2)
		elif (fl & BlockRegistry.F_COLLIDE) == 0 or fl & BlockRegistry.F_MODEL:
			schedule(world, q, 1)


## Whole block-update step of a tick: scheduled ticks, then random ticks (the world's phased tick calls the two parts
## on consecutive frames).
static func tick(world) -> void:
	tick_scheduled(world)
	_random_ticks(world)


static func tick_scheduled(world) -> void:
	var t: int = world.game_time
	var n := 0
	if queue.has(t):
		var lst: Array = queue[t]
		queue.erase(t)
		for p in lst:
			pending.erase(p)
			if n < MAX_PER_TICK:
				_scheduled(world, p)
				n += 1
			else:
				schedule(world, p, 1)
	last_sched = n
	# drop stale entries (e.g. after time jumps)
	if queue.size() > 0 and t % 200 == 0:
		for k in queue.keys():
			if int(k) < t:
				for p in queue[k]:
					pending.erase(p)
				queue.erase(k)


## Random-tick sampling of the tick (handlers run spread over the following frames: step_hits).
static func tick_random(world) -> void:
	_random_ticks(world)


static func _scheduled(world, p: Vector3i) -> void:
	var blocks := Res.blocks
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return
	var fl := blocks.st_flags[st]
	var name := blocks.name_of(st)
	if fl & BlockRegistry.F_LIQUID:
		_fluid(world, p, st)
		return
	if fl & BlockRegistry.F_WATERLOGGED:
		_spread_java(world, p, st, false)   # a waterlogged block spreads as a water source
	if fl & BlockRegistry.F_GRAVITY and name != "scaffolding" and name != "pointed_dripstone":
		var below: int = world.state_at(p.x, p.y - 1, p.z)
		if below == 0 or (below > 0 and (blocks.st_flags[below] & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LIQUID))):
			world.set_block(p.x, p.y, p.z, 0)
			world.entities.spawn_falling_block(p, st)
		return
	if blocks.st_block[st] == _fire_id():
		fire_tick(world, p, st)
		return
	if Redstone.scheduled(world, p, st):
		return
	if name == "composter" and blocks.get_prop(st, "level") == "7":
		world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "level", "8"))
		Audio.play("block.composter.ready", Vector3(p), "Blocks")
		return
	if name.ends_with("_button") and blocks.get_prop(st, "powered") == "true":
		world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "powered", "false"))
		Redstone.on_changed(world, p)
		Audio.play("block.stone_button.click_off", Vector3(p), "Blocks")
		return
	if not _has_support(world, p, st):
		world.set_block(p.x, p.y, p.z, 0)
		if world.gamerule("doTileDrops", true):
			for s in Loot.block_drops(st, null, world, p):
				world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.3, 0.5), s)
		schedule_neighbors(world, p)


static func _has_support(world, p: Vector3i, st: int) -> bool:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below < 0:
		return true
	var bname := blocks.name_of(maxi(below, 0))
	if name in ["short_grass", "fern", "dandelion", "poppy", "tall_grass", "large_fern", "dead_bush", "sweet_berry_bush"] or name.ends_with("_tulip") or name.ends_with("_sapling") or name in ["allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "blue_orchid"]:
		return below > 0 and (bname in ["grass_block", "dirt", "podzol", "coarse_dirt", "farmland", "moss_block", "mud", "rooted_dirt", "mycelium", "sand", "red_sand", "terracotta"] or bname == name and blocks.has_prop(st, "half"))
	if name in ["crimson_roots", "warped_roots", "nether_sprouts", "crimson_fungus", "warped_fungus"]:
		# Java RootsBlock / NetherSproutsBlock / FungusBlock.mayPlaceOn: #nylium, soul soil, #dirt (mycelium), farmland
		return below > 0 and bname in ["crimson_nylium", "warped_nylium", "soul_soil", "grass_block", "dirt", "podzol", "coarse_dirt", "farmland", "moss_block", "mud", "rooted_dirt", "mycelium", "muddy_mangrove_roots", "pale_moss_block"]
	if name in ["wheat", "carrots", "potatoes", "beetroots"] or name.ends_with("_stem"):
		return bname == "farmland"
	if name == "torch" or name == "redstone_torch" or name == "soul_torch" or name.ends_with("_carpet") or name.ends_with("_pressure_plate") or name == "redstone_wire" or name.ends_with("rail") or name == "snow":
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_COLLIDE) != 0
	if name == "sugar_cane":
		return bname == "sugar_cane" or bname in ["grass_block", "dirt", "sand", "red_sand", "podzol"]
	if name == "cactus":
		return bname == "cactus" or bname == "sand" or bname == "red_sand"
	if name.ends_with("_wall_torch") or name.ends_with("_wall_sign") or name == "ladder" or (name.ends_with("_button") and blocks.get_prop(st, "face") == "wall"):
		var f := blocks.get_prop(st, "facing")
		var off := {"north": Vector3i(0, 0, 1), "south": Vector3i(0, 0, -1), "west": Vector3i(1, 0, 0), "east": Vector3i(-1, 0, 0)}.get(f, Vector3i.ZERO)
		var q: Vector3i = p + off
		var s2: int = world.state_at(q.x, q.y, q.z)
		return s2 != 0 and (s2 < 0 or (blocks.st_flags[s2] & BlockRegistry.F_COLLIDE) != 0)
	if name.ends_with("_door") and blocks.get_prop(st, "half") == "lower":
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_COLLIDE) != 0
	if name.ends_with("_cushion"):
		return below > 0 and (blocks.st_cull[below] >> 1) & 1 == 1
	return true


# ---------------------------------------------------------------- fluids

static func _amount(st: int) -> int:
	var lv: int = Res.blocks.st_level[st]
	if lv == 0 or lv >= 8:
		return 8
	return 8 - lv


static func _same_fluid(st: int, lava: bool) -> bool:
	if st <= 0:
		return false
	var fl := Res.blocks.st_flags[st]
	if lava:
		return (fl & BlockRegistry.F_LAVA) != 0
	return (fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and (fl & BlockRegistry.F_LAVA) == 0


## Java FlowingFluid.tick / spread / getSpread / getNewLiquid / getSlopeDistance for water and lava. Fluid states:
## liquid blocks (level 0 source, 1..7 flowing with amount 8 - level, >= 8 falling with amount 8) and waterlogged
## blocks (a water source). Horizontal order N, E, S, W (Direction.Plane.HORIZONTAL).
const HDIRS := [Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0)]


static func _is_this(st: int, lava: bool) -> bool:
	return _same_fluid(st, lava)


static func _is_source_this(st: int, lava: bool) -> bool:
	if not _same_fluid(st, lava):
		return false
	var fl := Res.blocks.st_flags[st]
	return (fl & BlockRegistry.F_WATERLOGGED) != 0 or Res.blocks.st_level[st] == 0


static func _fluid_amount(st: int) -> int:
	if st <= 0:
		return 0
	var fl := Res.blocks.st_flags[st]
	if fl & BlockRegistry.F_WATERLOGGED:
		return 8
	if fl & BlockRegistry.F_LIQUID:
		return _amount(st)
	return 0


static func _falling(st: int) -> bool:
	return st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_LIQUID) != 0 and Res.blocks.st_level[st] >= 8


## FlowingFluid.canHoldAnyFluid: liquid containers (waterloggable blocks) and non-motion-blocking blocks except doors,
## signs, ladders, sugar cane, bubble columns, portals, gateways, structure voids.
static func _can_hold(st: int, _lava: bool) -> bool:
	if st == 0:
		return true
	var b := Res.blocks
	if b.has_prop(st, "waterlogged"):
		return true   # LiquidBlockContainer
	var fl := b.st_flags[st]
	if fl & BlockRegistry.F_LIQUID:
		return true
	if fl & BlockRegistry.F_COLLIDE:
		return false   # blocksMotion
	var nm := b.name_of(st)
	if nm.ends_with("_door") or nm == "ladder" or nm.ends_with("_sign") or nm == "sugar_cane" or nm == "bubble_column" or nm == "nether_portal" or nm == "end_portal" or nm == "end_gateway" or nm == "structure_void":
		return false
	return true


## FlowingFluid.canHoldSpecificFluid for the fluid about to go there: a waterloggable block takes only a water SOURCE
## (SimpleWaterloggedBlock.canPlaceLiquid: fluid == Fluids.WATER) - flowing water passes stairs / fences / slabs by.
static func _can_hold_specific(st: int, lava: bool, source: bool) -> bool:
	if st > 0 and Res.blocks.has_prop(st, "waterlogged"):
		return not lava and source and Res.blocks.get_prop(st, "waterlogged") == "false"
	return _can_hold(st, lava)


## FlowingFluid.canPassThroughWall, simplified: a full collision cube on either side blocks the face.
static func _wall_ok(st: int) -> bool:
	return st <= 0 or (Res.blocks.st_flags[st] & (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)) != (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)


static func _flowing_state(lava: bool, amount: int, falling: bool) -> int:
	var src := Res.blocks.LAVA if lava else Res.blocks.WATER
	return Res.blocks.with_prop(src, "level", str(8 if falling else 8 - amount))


static func _drop_off(world, lava: bool) -> int:
	return (1 if lava_delay(world) == 10 else 2) if lava else 1


## FlowingFluid.getNewLiquid: the fluid state this position should hold (0 = empty).
static func _new_liquid(world, p: Vector3i, lava: bool) -> int:
	var maxa := 0
	var sources := 0
	for d in HDIRS:
		var q: Vector3i = p + d
		var ns: int = world.state_at(q.x, q.y, q.z)
		if _is_this(ns, lava) and _wall_ok(ns):
			if _is_source_this(ns, lava):
				sources += 1
			maxa = maxi(maxa, _fluid_amount(ns))
	if sources >= 2 and not lava and world.gamerule("waterSourceConversion", true):
		var below: int = world.state_at(p.x, p.y - 1, p.z)
		if (below > 0 and (Res.blocks.st_flags[below] & BlockRegistry.F_SOLID) != 0) or _is_source_this(below, lava):
			return Res.blocks.WATER
	if sources >= 2 and lava and world.gamerule("lavaSourceConversion", false):
		var below2: int = world.state_at(p.x, p.y - 1, p.z)
		if (below2 > 0 and (Res.blocks.st_flags[below2] & BlockRegistry.F_SOLID) != 0) or _is_source_this(below2, lava):
			return Res.blocks.LAVA
	var above: int = world.state_at(p.x, p.y + 1, p.z)
	if _is_this(above, lava) and _wall_ok(above):
		return _flowing_state(lava, 8, true)
	var k := maxa - _drop_off(world, lava)
	return 0 if k <= 0 else _flowing_state(lava, k, false)


static func _fluid(world, p: Vector3i, st: int) -> void:
	var blocks := Res.blocks
	var lava := (blocks.st_flags[st] & BlockRegistry.F_LAVA) != 0
	var is_source := blocks.st_level[st] == 0
	# lava / water reactions (LiquidBlock.shouldSpreadLiquid on lava: obsidian from a source, else cobblestone)
	if lava:
		for d in [Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]:
			var q: Vector3i = p + d
			if _same_fluid(world.state_at(q.x, q.y, q.z), false):
				world.set_block(p.x, p.y, p.z, blocks.default_state("obsidian" if is_source else "cobblestone"))
				Audio.play("block.lava.extinguish", Vector3(p), "Blocks")
				return
	if not is_source:
		var nl := _new_liquid(world, p, lava)
		var delay := _spread_delay(world, lava, st, nl)
		if nl == 0:
			world.set_block(p.x, p.y, p.z, 0)
			schedule_neighbors(world, p)
			return
		if nl != st:
			world.set_block(p.x, p.y, p.z, nl)
			schedule(world, p, delay)
			schedule_neighbors(world, p)
			st = nl
	_spread_java(world, p, st, lava)


## LavaFluid.getSpreadDelay: x4 (3 in 4) when a non-falling flow rises; water: 5.
static func _spread_delay(world, lava: bool, cur: int, nl: int) -> int:
	if not lava:
		return 5
	var i := lava_delay(world)
	if cur > 0 and nl > 0 and not _falling(cur) and not _falling(nl) and _fluid_amount(nl) > _fluid_amount(cur) and _rt_rng.randi_range(0, 3) != 0:
		i *= 4
	return i


## FlowingFluid.spread: down first, then sideways (sources, or flows not standing over a hole).
static func _spread_java(world, p: Vector3i, st: int, lava: bool) -> void:
	var below_p := p + Vector3i(0, -1, 0)
	var below: int = world.state_at(below_p.x, below_p.y, below_p.z)
	if below >= 0 and not _is_source_this(below, lava) and _can_hold(below, lava) and _wall_ok(below):
		var nb := _new_liquid(world, below_p, lava)
		# FluidState.canBeReplacedWith(.., DOWN) of what is below: empty / non-fluid yes; the same fluid never (it
		# updates itself on its own tick); water under falling lava turns to stone (LavaFluid.spreadTo); lava under
		# water when at least 0.444 high (LavaFluid.canBeReplacedWith)
		var replaceable := true
		if below > 0 and _fluid_amount(below) > 0:
			if _same_fluid(below, lava):
				replaceable = false
			elif lava:
				world.set_block(below_p.x, below_p.y, below_p.z, Res.blocks.default_state("stone"))
				Audio.play("block.lava.extinguish", Vector3(below_p), "Blocks")
				return
			else:
				replaceable = _fluid_amount(below) >= 4
		if replaceable and nb != 0 and _can_hold_specific(below, lava, Res.blocks.st_level[nb] == 0):
			_spread_to(world, below_p, below, nb, lava)
			var srcn := 0
			for d in HDIRS:
				var q: Vector3i = p + d
				if _is_source_this(world.state_at(q.x, q.y, q.z), lava):
					srcn += 1
			if srcn >= 3:
				_spread_sides(world, p, st, lava)
			return
	if _is_source_this(st, lava) or not _is_hole(world, p, lava, {}):
		_spread_sides(world, p, st, lava)


static func _spread_sides(world, p: Vector3i, st: int, lava: bool) -> void:
	var i := _fluid_amount(st) - _drop_off(world, lava)
	if _falling(st):
		i = 7
	if i <= 0:
		return
	var best := 1000
	var targets: Array = []
	var holes := {}
	for d in HDIRS:
		var q: Vector3i = p + d
		var ns: int = world.state_at(q.x, q.y, q.z)
		if ns < 0 or _is_source_this(ns, lava) or not _can_hold(ns, lava) or not _wall_ok(ns):
			continue
		var nf := _new_liquid(world, q, lava)
		if not _can_hold_specific(ns, lava, nf > 0 and Res.blocks.st_level[nf] == 0):
			continue
		var j := 0 if _is_hole(world, q, lava, holes) else _slope_java(world, q, 1, -d, lava, holes)
		if j < best:
			targets.clear()
		if j <= best:
			# FluidState.canBeReplacedWith of what is there now
			var ok := true
			if ns > 0 and _fluid_amount(ns) > 0:
				if _same_fluid(ns, lava):
					ok = false   # the same fluid is never replaced sideways (it recomputes itself)
				else:
					ok = not lava and _fluid_amount(ns) >= 4   # water into lava >= 0.444 high; lava never into water
			if ok and nf != 0:
				targets.append([q, ns, nf])
			best = j
	for tg in targets:
		_spread_to(world, tg[0], tg[1], tg[2], lava)


## SpreadContext.isHole: the fluid can go down from q.
static func _is_hole(world, q: Vector3i, lava: bool, cache: Dictionary) -> bool:
	if cache.has(q):
		return cache[q]
	var b: int = world.state_at(q.x, q.y - 1, q.z)
	var r := b >= 0 and _wall_ok(b) and (_is_this(b, lava) or (_can_hold(b, lava) and _can_hold_specific(b, lava, false)))
	cache[q] = r
	return r


## FlowingFluid.getSlopeDistance (distance to the nearest hole, up to the slope find distance; 1000 = none).
static func _slope_java(world, p: Vector3i, distance: int, from_dir: Vector3i, lava: bool, holes: Dictionary) -> int:
	var best := 1000
	var find := (4 if lava_delay(world) == 10 else 2) if lava else 4
	for d in HDIRS:
		if d == from_dir:
			continue
		var q: Vector3i = p + d
		var ns: int = world.state_at(q.x, q.y, q.z)
		if ns < 0 or _is_source_this(ns, lava) or not _can_hold(ns, lava) or not _wall_ok(ns):
			continue
		if _is_hole(world, q, lava, holes):
			return distance
		if distance < find:
			best = mini(best, _slope_java(world, q, distance + 1, -d, lava, holes))
	return best


## FlowingFluid.spreadTo: waterloggable blocks take water as waterlogging; others are destroyed (drops; lava fizzes)
## and replaced; the new fluid schedules its tick (LiquidBlock.onPlace).
static func _spread_to(world, q: Vector3i, cur: int, nf: int, lava: bool) -> void:
	var b := Res.blocks
	if cur > 0 and b.has_prop(cur, "waterlogged"):
		if not lava:
			world.set_block(q.x, q.y, q.z, b.with_prop(cur, "waterlogged", "true"))
			schedule(world, q, 5)
		return
	if cur > 0 and (b.st_flags[cur] & BlockRegistry.F_LIQUID) == 0:
		if lava:
			Audio.play("block.lava.extinguish", Vector3(q) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 2.6)
		elif world.gamerule("doTileDrops", true):
			for s in Loot.block_drops(cur, null, world, q):
				world.entities.spawn_item(Vector3(q) + Vector3(0.5, 0.3, 0.5), s)
	world.set_block(q.x, q.y, q.z, nf)
	schedule(world, q, lava_delay(world) if lava else 5)
	schedule_neighbors(world, q)


static func _spread_from(world, p: Vector3i, _water: bool, amount: int, lava: bool) -> void:
	var blocks := Res.blocks
	var drop := 2 if lava else 1
	var src := blocks.LAVA if lava else blocks.WATER
	var delay := lava_delay(world) if lava else 5
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below >= 0 and _can_flow_into(below, lava):
		if _same_fluid(below, not lava) and below > 0:
			world.set_block(p.x, p.y - 1, p.z, blocks.default_state("stone") if lava else blocks.default_state("cobblestone"))
			return
		world.set_block(p.x, p.y - 1, p.z, blocks.with_prop(src, "level", "8"))
		schedule(world, p + Vector3i(0, -1, 0), delay)
		if not (_same_fluid(world.state_at(p.x, p.y, p.z), lava) and Res.blocks.st_level[world.state_at(p.x, p.y, p.z)] == 0):
			return
	var na := amount - drop
	if na <= 0:
		return
	# Java prefers directions leading to the nearest drop (slope search up to 4 blocks); simplified to 2.
	var dirs := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	var best_d := 99
	var costs := []
	for d in dirs:
		var c := _slope(world, p + d, lava, 1)
		costs.append(c)
		best_d = mini(best_d, c)
	for i in 4:
		if costs[i] > best_d:
			continue
		var q: Vector3i = p + dirs[i]
		var ns: int = world.state_at(q.x, q.y, q.z)
		if ns < 0 or not _can_flow_into(ns, lava):
			continue
		if _same_fluid(ns, lava) and _amount(ns) >= na:
			continue
		world.set_block(q.x, q.y, q.z, blocks.with_prop(src, "level", str(8 - na)))
		schedule(world, q, delay)


static func _slope(world, p: Vector3i, lava: bool, depth: int) -> int:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st < 0 or not _can_flow_into(st, lava):
		return 1000
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below >= 0 and _can_flow_into(below, lava):
		return depth
	if depth >= (2 if lava else 4):
		return 1000
	var best := 1000
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		best = mini(best, _slope(world, p + d, lava, depth + 1)) if depth < 2 else best
	return best if best < 1000 else depth + 4


static func _can_flow_into(st: int, lava: bool) -> bool:
	if st == 0:
		return true
	var fl := Res.blocks.st_flags[st]
	if fl & BlockRegistry.F_LIQUID:
		return Res.blocks.st_level[st] != 0 or ((fl & BlockRegistry.F_LAVA) != 0) != lava
	return (fl & BlockRegistry.F_REPLACEABLE) != 0 and (fl & BlockRegistry.F_WATERLOGGED) == 0


# ---------------------------------------------------------------- random ticks

## Random ticks are queued per game tick and processed in per-frame time slices (step); a tick's pass always
## completes before the next tick queues its own, so the rate stays 20 passes/s and only the frame they land in moves.
static var _rt_queue: Array = []   # chunks of the current pass (processed from the back)
static var _xs := 2463534242      # xorshift32 state for random-tick positions
static var _rt_speed := 3


static var _rt_native := -1   # 1: RecraftNative.rt_sample available


static func _random_ticks(world) -> void:
	var t_rt := Time.get_ticks_usec()
	if _rt_native < 0:
		_rt_native = 1 if (Native.chunkops_ok and Native.inst != null and Native.inst.has_method("rt_sample")) else 0
	if _rt_native == 1:
		_random_ticks_native(world)
	else:
		_random_ticks2(world)
		_drain(world, -1)
	last_random_us = Time.get_ticks_usec() - t_rt
	if prof:
		prof_us["<all random ticks>"] = int(prof_us.get("<all random ticks>", 0)) + Time.get_ticks_usec() - t_rt


## Rebuilds a chunk's random-tick section list and the live array references handed to native sampling.
static func _rt_rebuild(c: Chunk, tf: PackedByteArray) -> void:
	c.rt_dirty = false
	var secs: Array = c.sections
	var lst := PackedInt32Array()
	var data: Array = [null]
	for s0 in Coords.SECTIONS:
		var sec0: Chunk.Section = secs[s0]
		var rtf := sec0.rt
		if rtf < 0 or sec0.rt_n != sec0.pal.size():
			rtf = 0
			for pst in sec0.pal:
				if pst != 0 and tf[pst] == 1:
					rtf = 1
					break
			sec0.rt = rtf
			sec0.rt_n = sec0.pal.size()
		if rtf == 1:
			lst.append(s0)
			data.append(sec0.pal)
			data.append(sec0.idx)
			data.append(sec0.wide)
	c.rt_secs = lst
	data[0] = lst
	if c.rt_data.is_empty():
		c.rt_data = data
	else:
		# in place: the cached random-tick list holds this array by reference
		c.rt_data.assign(data)


## Same sampling as _random_ticks2 + _drain (chunk order, xorshift stream, speed cells per tickable section), with the
## per-cell loop in native code; handlers then run for the hits in order. A hit whose block was changed by an earlier
## handler of this tick ticks the current block if that one is random-tickable.
static func _random_ticks_native(world) -> void:
	_rt_sample_slice(1 << 30)   # previous pass not sampled completely (low frame rate): finish it first
	if _rt_hi < _rt_hits.size():
		_rt_process(world, _rt_hits.size())   # previous pass not finished (low frame rate): complete it first
	_rt_hits = PackedInt32Array()
	_rt_hi = 0
	var speed := int(world.gamerule("randomTickSpeed", 3))
	if speed <= 0:
		return
	var tf := RandomTickable.table()
	var p: Player = world.player
	var sim := int(Settings.get_v("simulation_distance"))
	var pcx := int(floor(p.pos.x)) >> 4
	var pcz := int(floor(p.pos.z)) >> 4
	var chunks: Dictionary = world.cm.chunks
	# the chunk list (live section references of the tickable sections) is rebuilt only when the area moves, a chunk
	# of the area became ready (rtl_dirty), or every 5 s; same chunks, same order. The rebuild runs a few rows per frame
	# (step_hits -> _rt_build_steps) while sampling keeps using the previous list; only without a usable list (first
	# pass, dimension change, teleport) is it built at once.
	var lkey := Vector4i(pcx, pcz, sim, world.cm.get_instance_id() & 0x7FFFFFFF)
	var tq0 := Time.get_ticks_usec()
	if lkey != _rtl_key or rtl_dirty or world.game_time >= _rtl_until:
		if not _rtb_active or _rtb_key != lkey:
			_rt_build_start(lkey)
		elif rtl_dirty:
			# a chunk became ready while this area's rebuild runs: finish it, then rebuild once more (restarting on every
			# ready chunk while flying meant the time-budgeted rebuild never completed)
			_rtb_again = true
			rtl_dirty = false
		if _rtl_lst.is_empty() or _rtl_key.w != lkey.w or _rtl_key.z != lkey.z or absi(lkey.x - _rtl_key.x) > 2 or absi(lkey.y - _rtl_key.y) > 2:
			_rt_build_steps(world, 1 << 30)
	if not _rtl_pending.is_empty():
		for c4 in _rtl_pending:
			var ch4: Chunk = c4
			if ch4.rt_dirty and ch4.state != Chunk.EVICTED:
				_rt_rebuild(ch4, tf)
	_rtl_pending.clear()
	if prof:
		prof_us["<rt list>"] = int(prof_us.get("<rt list>", 0)) + Time.get_ticks_usec() - tq0
	# this tick's sampling pass over the list: RT_SLICE chunks now, the rest on the next frames (step_hits) — the same
	# chunk order and xorshift stream as one call, so the hits are identical; handlers start on the hits sampled so far
	_rt_hits = PackedInt32Array()
	_rt_hi = 0
	_rt_chs = _rtl_chs
	_rts_lst = _rtl_lst
	_rts_crd = _rtl_coords
	_rts_grid = _rtl_grid
	_rts_key = _rtl_key
	_rts_leaf = _rtl_leaf
	_rts_speed = speed
	_rts_pos = 0
	_rts_active = true
	_rt_sample_slice(RT_SLICE if Native.inst.has_method("rt_sample_range") else 1 << 30)


const RT_SLICE := 220   # chunks sampled per frame (a 25x25 area takes 3 frames of the ~10-20 per tick at high FPS)
static var _rts_active := false
static var _rts_pos := 0
static var _rts_speed := 3
static var _rts_lst: Array = []
static var _rts_crd := PackedInt32Array()
static var _rts_grid: Array = []
static var _rts_key := Vector4i(1 << 30, 0, 0, 0)
static var _rts_leaf := false


static func _rt_sample_slice(n: int) -> void:
	if not _rts_active:
		return
	var t0 := Time.get_ticks_usec()
	var tf := RandomTickable.table()
	var end := mini(_rts_pos + n, _rts_lst.size())
	var r: Array
	if _rts_pos == 0 and end == _rts_lst.size():
		r = Native.inst.rt_sample(_rts_lst, tf, _rts_speed, _xs)
	else:
		r = Native.inst.rt_sample_range(_rts_lst, tf, _rts_speed, _xs, _rts_pos, end)
	_xs = int(r[0])
	var h: PackedInt32Array = r[1]
	var t1 := Time.get_ticks_usec()
	if _rts_leaf and not h.is_empty():
		# supported leaves would do nothing on their random tick: dropped natively (same leaf search as the handler)
		var lsim := _rts_key.z
		h = Native.inst.rt_leaf_filter(h, _rts_crd, _rts_grid, _rts_key.x - lsim - 1, _rts_key.y - lsim - 1, 2 * lsim + 3, RandomTickable.ltab(), 6)[0]
	_rt_hits.append_array(h)
	_rts_pos = end
	if _rts_pos >= _rts_lst.size():
		_rts_active = false
	if prof:
		prof_us["<rt sample>"] = int(prof_us.get("<rt sample>", 0)) + t1 - t0
		prof_us["<rt leaf filter>"] = int(prof_us.get("<rt leaf filter>", 0)) + Time.get_ticks_usec() - t1
		prof_n["<rt sample>"] = int(prof_n.get("<rt sample>", 0)) + 1

static var _rtl_key := Vector4i(1 << 30, 0, 0, 0)
static var _rtl_until := 0
static var _rtl_lst: Array = []
static var _rtl_chs: Array = []
static var _rtl_leaf := false
static var _rtl_coords := PackedInt32Array()
static var _rtl_grid: Array = []
static var rtl_dirty := true   # the cached random-tick area must be rebuilt (a chunk became ready in it, reset)
static var _rtl_pending: Array = []   # listed chunks whose random-tick sections changed (refreshed in place)
static var _rtb_active := false       # incremental list rebuild in progress
static var _rtb_again := false        # another rebuild is due when this one completes
static var _rtb_key := Vector4i(1 << 30, 0, 0, 0)
static var _rtb_row := 0
static var _rtb_lst: Array = []
static var _rtb_chs: Array = []
static var _rtb_crd := PackedInt32Array()
static var _rtb_grid: Array = []


static func _rt_build_start(k: Vector4i) -> void:
	_rtb_active = true
	_rtb_key = k
	_rtb_row = 0
	_rtb_lst = []
	_rtb_chs = []
	_rtb_crd = PackedInt32Array()
	var gw := 2 * k.z + 3
	_rtb_grid = []
	_rtb_grid.resize(gw * gw)
	rtl_dirty = false


const BUILD_BUDGET_US := 250   # incremental list rebuild: minimum time per frame (the previous list stays in use meanwhile)


## Advances the list rebuild by up to `rows` rows (and at most BUILD_BUDGET_US per frame): first the leaf-filter grid
## (area + 1 ring of section references), then the list itself (dz-major, same order as before); swaps it in when
## complete.
static func _rt_build_steps(world, rows: int) -> void:
	if not _rtb_active or world.cm == null:
		return
	var k := _rtb_key
	var sim := k.z
	var gw := 2 * sim + 3
	var chunks: Dictionary = world.cm.chunks
	var tf := RandomTickable.table()
	var leaf: bool = Native.inst.has_method("rt_leaf_filter")
	# time per frame scales with the frame time (8 %, 0.25 .. 1.5 ms): at 60-144 FPS the rebuild still finishes in a
	# few frames (a rebuild that falls behind ends in a synchronous one inside the tick = a spike)
	var budget := clampi(int(float(world._last_delta) * 80000.0), BUILD_BUDGET_US, 1500)
	var t_end := Time.get_ticks_usec() + (budget if rows < (1 << 20) else (1 << 40))
	var first := true
	while rows > 0 and (first or rows >= (1 << 20) or Time.get_ticks_usec() < t_end):
		first = false
		var r := _rtb_row
		if r < gw:
			if leaf:
				for gx in gw:
					var c3: Chunk = chunks.get(((k.x - sim - 1 + gx) << 32) | ((k.y - sim - 1 + r) & 0xFFFFFFFF))
					if c3 != null and c3.state >= Chunk.DATA_READY:
						_rtb_grid[r * gw + gx] = c3.sec_refs()
		else:
			var cz := k.y + (r - gw - sim)
			for dx in range(-sim, sim + 1):
				var cx := k.x + dx
				var c: Chunk = chunks.get((cx << 32) | (cz & 0xFFFFFFFF))
				if c == null or c.state < Chunk.DECORATED:
					continue
				c.rt_listed = true
				if c.rt_dirty or c.rt_data.is_empty():
					_rt_rebuild(c, tf)
				# listed even without tickable sections: an edit refreshes its entry in place (rt_chunk_dirty)
				_rtb_lst.append(c.rt_data)
				_rtb_chs.append(c)
				_rtb_crd.append(c.cx)
				_rtb_crd.append(c.cz)
		_rtb_row += 1
		rows -= 1
		if _rtb_row >= gw + 2 * sim + 1:
			_rtl_key = k
			_rtl_lst = _rtb_lst
			_rtl_chs = _rtb_chs
			_rtl_coords = _rtb_crd
			_rtl_grid = _rtb_grid
			_rtl_leaf = leaf
			_rtl_until = int(world.game_time) + 100
			_rtb_active = false
			if _rtb_again:
				_rtb_again = false
				rtl_dirty = true
			if prof:
				prof_n["<rt list rebuilds>"] = int(prof_n.get("<rt list rebuilds>", 0)) + 1
			return


## A listed chunk's random-tick data became stale (section edit / copy-on-write): refresh its entry before sampling.
static func rt_chunk_dirty(c: Chunk) -> void:
	_rtl_pending.append(c)


## A chunk became decorated (generated or loaded): refresh the random-tick list if it lies in the current area.
static func on_chunk_ready(cx: int, cz: int) -> void:
	var sim := int(Settings.get_v("simulation_distance"))
	if maxi(absi(cx - _rtl_key.x), absi(cz - _rtl_key.y)) <= sim:
		rtl_dirty = true


## Random-tick hits of the current pass are handled spread over the frames until the next game tick (step_hits), so a
## tick's handlers never land in one frame; any rest is finished before the next pass samples (one pass per tick).
static var _rt_hits := PackedInt32Array()
static var _rt_chs: Array = []
static var _rt_hi := 0


static func step_hits(world, frames_left: int) -> void:
	var tr: bool = world.cm.tracing
	var ta := Time.get_ticks_usec()
	if _rtb_active:
		_rt_build_steps(world, 6)   # incremental random-tick list rebuild (~160 chunks per frame)
	var tb := Time.get_ticks_usec()
	if _rts_active:
		# spread evenly over the frames left in this tick (a fixed slice was 3 frames of heavy work at high FPS)
		_rt_sample_slice(maxi(60, ceili(float(_rts_lst.size() - _rts_pos) / maxi(1, frames_left - 1))))
	if tr:
		var tc := Time.get_ticks_usec()
		if tb - ta > 300:
			world.frame_tparts["rt:list build"] = tb - ta
		if tc - tb > 300:
			world.frame_tparts["rt:sample"] = tc - tb
	var rem := (_rt_hits.size() - _rt_hi) / 4
	if rem <= 0:
		return
	var t := Time.get_ticks_usec()
	var n0 := _rt_hi
	# per-frame cap scales with the frame time (10 %, 0.15 .. 1.5 ms): a fixed 1.5 ms was 60 % of a 400 FPS frame
	var cap := clampi(int(float(world._last_delta) * 100000.0), 150, STEP_BUDGET_US)
	_rt_process(world, _rt_hi + ceili(float(rem) / maxi(1, frames_left)) * 4, t + cap)
	last_random_us += Time.get_ticks_usec() - t
	if tr and Time.get_ticks_usec() - t > 300:
		world.frame_tparts["rt:handlers (%d)" % ((_rt_hi - n0) / 4)] = Time.get_ticks_usec() - t


const STEP_BUDGET_US := 1500   # per-frame cap for spread random-tick handlers (the rest waits for later frames)


static func _rt_process(world, upto: int, deadline := 0) -> void:
	var tf := RandomTickable.table()
	var hits := _rt_hits
	var chs := _rt_chs
	var i := _rt_hi
	var nh := mini(upto, hits.size())
	while i < nh:
		if deadline > 0 and Time.get_ticks_usec() > deadline:   # every hit: single handlers cost up to ~0.25 ms (emulated)
			return
		var c2: Chunk = chs[hits[i]]
		var s := hits[i + 1]
		var k := hits[i + 2]
		var st := hits[i + 3]
		i += 4
		_rt_hi = i
		if c2.state == Chunk.EVICTED:
			continue
		var cur := (c2.sections[s] as Chunk.Section).get_at(k)
		if cur != st:
			if cur == 0 or tf[cur] != 1:
				continue
			st = cur
		var wp := Vector3i(c2.cx * 16 + (k & 15), Coords.MIN_Y + s * 16 + (k >> 8), c2.cz * 16 + ((k >> 4) & 15))
		if prof:
			var th := Time.get_ticks_usec()
			RandomTickable.random_tick(world, wp, st, _rt_rng)
			var nm := Res.blocks.name_of(st)
			var dth := Time.get_ticks_usec() - th
			prof_us[nm] = int(prof_us.get(nm, 0)) + dth
			prof_n[nm] = int(prof_n.get(nm, 0)) + 1
			if dth > 150:   # rare expensive handlers (the averages hide them)
				var kn := "<slow> " + nm + " " + ("changed" if world.state_at(wp.x, wp.y, wp.z) != st else "same")
				prof_us[kn] = int(prof_us.get(kn, 0)) + dth
				prof_n[kn] = int(prof_n.get(kn, 0)) + 1
		else:
			var th0 := Time.get_ticks_usec()
			RandomTickable.random_tick(world, wp, st, _rt_rng)
			if world.cm.tracing and Time.get_ticks_usec() - th0 > 2000:
				world.frame_tparts["rt:" + Res.blocks.name_of(st)] = Time.get_ticks_usec() - th0


static func _random_ticks2(world) -> void:
	var speed := int(world.gamerule("randomTickSpeed", 3))
	if speed <= 0:
		return
	var blocks := Res.blocks
	var p: Player = world.player
	var sim := int(Settings.get_v("simulation_distance"))
	var pcx := int(floor(p.pos.x)) >> 4
	var pcz := int(floor(p.pos.z)) >> 4
	_rt_speed = speed
	var lst0: Array = []
	for dz in range(-sim, sim + 1):
		for dx in range(-sim, sim + 1):
			var c0: Chunk = world.cm.get_chunk(pcx + dx, pcz + dz)
			if c0 != null and c0.state >= Chunk.DECORATED:
				lst0.append(c0)
	lst0.reverse()
	_rt_queue = lst0


## Process queued random-tick chunks for up to budget_us microseconds (budget < 0: everything). Called each frame.
static func step(world, budget_us: int) -> void:
	if _rt_queue.is_empty():
		return
	var t := Time.get_ticks_usec()
	_drain(world, budget_us)
	last_random_us += Time.get_ticks_usec() - t


static func _drain(world, budget_us: int) -> void:
	var t0 := Time.get_ticks_usec()
	var speed := _rt_speed
	var tf := RandomTickable.table()
	var nsec := Coords.SECTIONS
	while not _rt_queue.is_empty():
		if budget_us >= 0 and Time.get_ticks_usec() - t0 >= budget_us:
			return
		var c: Chunk = _rt_queue.pop_back()
		if c.state == Chunk.EVICTED:
			continue
		if true:
			var secs: Array = c.sections
			if c.rt_dirty:
				# cached per chunk/section; rebuilt only after a palette grew (same sections tick as a full scan)
				c.rt_dirty = false
				var lst := PackedInt32Array()
				for s0 in nsec:
					var sec0: Chunk.Section = secs[s0]
					var rtf := sec0.rt
					if rtf < 0 or sec0.rt_n != sec0.pal.size():
						rtf = 0
						for pst in sec0.pal:
							if pst != 0 and tf[pst] == 1:
								rtf = 1
								break
						sec0.rt = rtf
						sec0.rt_n = sec0.pal.size()
					if rtf == 1:
						lst.append(s0)
				c.rt_secs = lst
			for s in c.rt_secs:
				var sec: Chunk.Section = secs[s]
				# inlined Section.get_at + local xorshift positions (GDScript calls dominate this loop)
				var pal := sec.pal
				var wide := sec.wide
				var idx := sec.idx
				var np := pal.size()
				var use_wide := wide.size() > 0
				for i in speed:
					var xs := _xs
					xs ^= (xs << 13) & 0xFFFFFFFF
					xs ^= xs >> 17
					xs ^= (xs << 5) & 0xFFFFFFFF
					_xs = xs
					var k := xs & 4095
					var st: int = pal[0] if np == 1 else (pal[wide[k]] if use_wide else pal[idx[k]])
					if st == 0 or tf[st] != 1:
						continue
					var wp := Vector3i(c.cx * 16 + (k & 15), Coords.MIN_Y + s * 16 + (k >> 8), c.cz * 16 + ((k >> 4) & 15))
					if prof:
						var th := Time.get_ticks_usec()
						RandomTickable.random_tick(world, wp, st, _rt_rng)
						var nm := Res.blocks.name_of(st)
						prof_us[nm] = int(prof_us.get(nm, 0)) + Time.get_ticks_usec() - th
						prof_n[nm] = int(prof_n.get(nm, 0)) + 1
					else:
						RandomTickable.random_tick(world, wp, st, _rt_rng)


static func _section_ticks(sec: Chunk.Section, _blocks: BlockRegistry) -> bool:
	for st in sec.pal:
		if st != 0 and RandomTickable.ticks(st):
			return true
	return false


static func bonemeal(world, p: Vector3i, st: int) -> bool:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	if blocks.has_prop(st, "age") and (name in ["wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "sweet_berry_bush", "cocoa", "torchflower_crop", "pitcher_crop"]):
		var vals := 0
		for pr in blocks.block_props[blocks.st_block[st]]:
			if pr[0] == "age":
				vals = (pr[1] as PackedStringArray).size() - 1
		var a := mini(vals, int(blocks.get_prop(st, "age")) + world.rng.randi_range(2, 5))
		world.set_block(p.x, p.y, p.z, blocks.with_prop(st, "age", str(a)))
		return true
	if name.ends_with("_sapling"):
		if world.rng.randf() < 0.45:
			RandomTickable.grow_tree(world, p, name.trim_suffix("_sapling"))
		return true
	if name == "grass_block":
		var grass := blocks.default_state("short_grass")
		for i in 24:
			var q := p + Vector3i(world.rng.randi_range(-3, 3), 1, world.rng.randi_range(-3, 3))
			if world.state_at(q.x, q.y, q.z) == 0 and blocks.name_of(maxi(0, world.state_at(q.x, q.y - 1, q.z))) == "grass_block":
				world.set_block(q.x, q.y, q.z, grass if world.rng.randi_range(0, 7) > 0 else blocks.default_state("poppy" if world.rng.randf() < 0.5 else "dandelion"))
		return true
	return false

# ------------------------------------------------------------------ fire (Java FireBlock)

static var _fire_odds := PackedInt32Array()   # per block id: ignite odds << 8 | burn odds (FireBlock.bootStrap)
static var _fire_b := -2


static func _fire_id() -> int:
	if _fire_b == -2:
		_fire_b = Res.blocks.block_id("fire")
	return _fire_b


static func _fire_table() -> PackedInt32Array:
	if not _fire_odds.is_empty():
		return _fire_odds
	var b := Res.blocks
	var t := PackedInt32Array()
	t.resize(b.names.size())
	var put := func(nm: String, ig: int, bu: int) -> void:
		var id := b.block_id(nm)
		if id >= 0:
			t[id] = (ig << 8) | bu
	for w in ["oak", "spruce", "birch", "jungle", "acacia", "cherry", "dark_oak", "pale_oak", "mangrove", "bamboo"]:
		for suf in ["_planks", "_slab", "_fence_gate", "_fence", "_stairs"]:
			put.call(w + suf, 5, 20)
	for nm in ["bamboo_mosaic", "bamboo_mosaic_slab", "bamboo_mosaic_stairs", "mangrove_roots", "composter", "beehive"]:
		put.call(nm, 5, 20)
	for w2 in ["oak", "spruce", "birch", "jungle", "acacia", "cherry", "dark_oak", "pale_oak", "mangrove"]:
		for pre in ["", "stripped_"]:
			put.call(pre + w2 + "_log", 5, 5)
			put.call(pre + w2 + "_wood", 5, 5)
	for nm2 in ["bamboo_block", "stripped_bamboo_block", "coal_block"]:
		put.call(nm2, 5, 5)
	for nm3 in Tags.blocks("#minecraft:leaves"):
		put.call(nm3, 30, 60)
	for nm4 in Tags.blocks("#minecraft:wool"):
		put.call(nm4, 30, 60)
	for nm5 in Tags.blocks("#minecraft:wool_carpets"):
		put.call(nm5, 60, 20)
	for nm6 in ["short_grass", "fern", "dead_bush", "sunflower", "lilac", "rose_bush", "peony", "tall_grass", "large_fern", "dandelion",
			"poppy", "blue_orchid", "allium", "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip", "oxeye_daisy",
			"cornflower", "lily_of_the_valley", "torchflower", "pitcher_plant", "wither_rose", "pink_petals", "wildflowers",
			"open_eyeblossom", "closed_eyeblossom", "sweet_berry_bush", "spore_blossom", "leaf_litter", "short_dry_grass",
			"tall_dry_grass", "bush", "firefly_bush", "cactus_flower", "golden_dandelion"]:
		put.call(nm6, 60, 100)
	for nm7 in [["bookshelf", 30, 20], ["chiseled_bookshelf", 30, 20], ["lectern", 30, 20], ["bee_nest", 30, 20], ["tnt", 15, 100],
			["vine", 15, 100], ["hay_block", 60, 20], ["target", 15, 20], ["moss_carpet", 5, 100], ["pale_moss_carpet", 5, 100],
			["dried_kelp_block", 30, 60], ["bamboo", 60, 60], ["scaffolding", 60, 60], ["azalea", 30, 60], ["flowering_azalea", 30, 60],
			["cave_vines", 15, 60], ["cave_vines_plant", 15, 60], ["moss_block", 5, 100], ["big_dripleaf", 15, 100],
			["big_dripleaf_stem", 15, 100], ["small_dripleaf", 15, 100], ["hanging_roots", 30, 60], ["glow_lichen", 15, 100],
			["pale_hanging_moss", 5, 100], ["pale_moss_block", 5, 100]]:
		put.call(str(nm7[0]), int(nm7[1]), int(nm7[2]))
	_fire_odds = t
	return t


static func _wl(st: int) -> bool:
	return Res.blocks.has_prop(st, "waterlogged") and Res.blocks.get_prop(st, "waterlogged") == "true"


static func ignite_odds(st: int) -> int:
	if st <= 0 or _wl(st):
		return 0
	return _fire_table()[Res.blocks.st_block[st]] >> 8


static func burn_odds(st: int) -> int:
	if st <= 0 or _wl(st):
		return 0
	return _fire_table()[Res.blocks.st_block[st]] & 255


const DIRS6 := [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]


static func _sturdy_up(st: int) -> bool:
	if st <= 0:
		return false
	var fl := Res.blocks.st_flags[st]
	return (fl & BlockRegistry.F_COLLIDE) != 0 and (fl & BlockRegistry.F_FULL_SHAPE) != 0


static func _valid_fire_location(world, p: Vector3i) -> bool:
	for d in DIRS6:
		var q: Vector3i = p + d
		if ignite_odds(world.state_at(q.x, q.y, q.z)) > 0:
			return true
	return false


static func fire_can_survive(world, p: Vector3i) -> bool:
	return _sturdy_up(world.state_at(p.x, p.y - 1, p.z)) or _valid_fire_location(world, p)


## BaseFireBlock.getState + FireBlock.getStateForPlacement: soul fire on soul fire bases, else fire attached to the
## burnable sides when the block below can neither burn nor hold it.
static func fire_state(world, p: Vector3i, age: int = 0) -> int:
	var b := Res.blocks
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below > 0 and Tags.has_block("#minecraft:soul_fire_base_blocks", b.name_of(below)):
		return b.default_state("soul_fire")
	var st := b.with_prop(b.default_state("fire"), "age", str(age))
	if ignite_odds(below) <= 0 and not _sturdy_up(below):
		for dn in [["north", Vector3i(0, 0, -1)], ["south", Vector3i(0, 0, 1)], ["west", Vector3i(-1, 0, 0)], ["east", Vector3i(1, 0, 0)], ["up", Vector3i(0, 1, 0)]]:
			var q: Vector3i = p + dn[1]
			if b.has_prop(st, dn[0]):
				st = b.with_prop(st, dn[0], "true" if ignite_odds(world.state_at(q.x, q.y, q.z)) > 0 else "false")
	return st


static func _raining_at(world, p: Vector3i) -> bool:
	return world.weather_at(Vector3(p) + Vector3(0.5, 0.0, 0.5)) == "rain"


static func _near_rain(world, p: Vector3i) -> bool:
	for d in [Vector3i.ZERO, Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1)]:
		if _raining_at(world, p + d):
			return true
	return false


## FireBlock.updateShape (neighbour changed): gone when it cannot survive, else its side attachments refresh.
static func fire_update_shape(world, p: Vector3i, st: int) -> void:
	if not fire_can_survive(world, p):
		world.set_block(p.x, p.y, p.z, 0)
		return
	var ns := fire_state(world, p, int(Res.blocks.get_prop(st, "age")) if Res.blocks.has_prop(st, "age") else 0)
	if ns != st and Res.blocks.st_block[ns] == Res.blocks.st_block[st]:
		world.set_block(p.x, p.y, p.z, ns, false)


## FireBlock.onPlace: the first tick in 30..39 ticks (WorldManager.set_block calls this for new fire).
static func fire_placed(world, p: Vector3i) -> void:
	schedule(world, p, 30 + world.rng.randi_range(0, 9))


## FireBlock.tick: reschedule; burn out in rain, age, die without fuel (or at age 15 on a non-burnable floor, 1 in 4),
## burn the 6 neighbours (checkBurnOut: replaced by fire or destroyed, TNT primed) and spread into the air cells of a
## 3 x 6 x 3 box above-around (more likely next to better fuel, less likely higher up), all unless the floor is the
## dimension's infiniburn block.
static func fire_tick(world, p: Vector3i, st: int) -> void:
	var rng: RandomNumberGenerator = world.rng
	schedule(world, p, 30 + rng.randi_range(0, 9))
	if not world.gamerule("doFireTick", true):
		return
	if not fire_can_survive(world, p):
		world.set_block(p.x, p.y, p.z, 0)
		return
	var b := Res.blocks
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	var inf_tag := str((world.dim_type as Dictionary).get("infiniburn", "#minecraft:infiniburn_overworld"))
	var infini: bool = below > 0 and Tags.has_block(inf_tag if inf_tag.begins_with("#") else "#" + inf_tag, b.name_of(below))
	var age := int(b.get_prop(st, "age")) if b.has_prop(st, "age") else 0
	if not infini and world.raining and _near_rain(world, p) and rng.randf() < 0.2 + age * 0.03:
		world.set_block(p.x, p.y, p.z, 0)
		return
	var age2 := mini(15, age + rng.randi_range(0, 2) / 2)
	if age2 != age and b.has_prop(st, "age"):
		st = b.with_prop(st, "age", str(age2))
		world.set_block(p.x, p.y, p.z, st, false)
	if not infini:
		if not _valid_fire_location(world, p):
			if not _sturdy_up(below) or age > 3:
				world.set_block(p.x, p.y, p.z, 0)
			return
		if age == 15 and rng.randi_range(0, 3) == 0 and ignite_odds(below) <= 0:
			world.set_block(p.x, p.y, p.z, 0)
			return
	var bio := -1
	var ch: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if ch != null:
		bio = ch.biome_at(p.x & 15, p.y, p.z & 15)
	var humid := bio >= 0 and Tags.resolve("worldgen/biome", "#minecraft:increased_fire_burnout").has(str(world.biomes.names[bio]))
	var k := -50 if humid else 0
	for bo in [[Vector3i(1, 0, 0), 300], [Vector3i(-1, 0, 0), 300], [Vector3i(0, -1, 0), 250], [Vector3i(0, 1, 0), 250], [Vector3i(0, 0, -1), 300], [Vector3i(0, 0, 1), 300]]:
		_check_burn_out(world, p + bo[0], int(bo[1]) + k, age)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for dy in range(-1, 5):
				if dx == 0 and dy == 0 and dz == 0:
					continue
				var chance := 100 + ((dy - 1) * 100 if dy > 1 else 0)
				var q := p + Vector3i(dx, dy, dz)
				if world.state_at(q.x, q.y, q.z) != 0:
					continue
				var odds := 0
				for d in DIRS6:
					var r: Vector3i = q + d
					odds = maxi(odds, ignite_odds(world.state_at(r.x, r.y, r.z)))
				if odds <= 0:
					continue
				var m := (odds + 40 + int(world.difficulty) * 7) / (age2 + 30)
				if humid:
					m /= 2
				if m > 0 and rng.randi_range(0, chance - 1) <= m and (not world.raining or not _near_rain(world, q)):
					world.set_block(q.x, q.y, q.z, fire_state(world, q, mini(15, age2 + rng.randi_range(0, 4) / 4)))


static func _check_burn_out(world, q: Vector3i, chance: int, age: int) -> void:
	var rng: RandomNumberGenerator = world.rng
	var st: int = world.state_at(q.x, q.y, q.z)
	var bo := burn_odds(st)
	if bo <= 0 or rng.randi_range(0, chance - 1) >= bo:
		return
	if rng.randi_range(0, age + 9) < 5 and not _raining_at(world, q):
		world.set_block(q.x, q.y, q.z, fire_state(world, q, mini(age + rng.randi_range(0, 4) / 4, 15)))
	else:
		world.set_block(q.x, q.y, q.z, 0)
	if Res.blocks.name_of(st) == "tnt":
		MiscEntities.spawn_tnt(world.entities, Vector3(q) + Vector3(0.5, 0.0, 0.5), 80)   # TntBlock.prime
