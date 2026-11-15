## Growth — random-tick and timed block behaviours that were missing (minecraft.wiki Java values; the algorithms follow
## the Java blocks, the chances / limits are the wiki's):
## - budding amethyst: a random face; 20 % to start a small bud in air / still water or advance the bud on that face
## - pointed dripstone: 64/5625 per random tick at the top of a stalactite under a dripstone block with water above it
##   to lengthen the stalactite (max 8) or a stalagmite below (floor < 11 below); water / lava above the root block
##   fills a cauldron below the tip (45/256 water, 15/256 lava; 50 + drop ticks later); mud above turns to clay
##   (45/256, not where water evaporates)
## - vines: 25 % per random tick in a random direction (sides, up, down; 50 % per face; < 4 other vines in 9 x 3 x 9)
## - cave vines, twisting / weeping vines: 10 % per random tick to grow one block (age < 25); cave vines 11 % berries
## - chorus flower: grows up (chance by the plant below: 100 / 60 / 50 / 40 / 25 / 20 %), else branches (1-4 tries,
##   0-3 when branched), else dies (age 5)
## - mushrooms: 4 % to spread (< 5 of the type in 9 x 3 x 9; 5 hops), on mushroom soil or at light < 13
## - nylium dies to netherrack under a light-blocking block; frosted ice melts (1/3 or < 4 frosted neighbours, light >
##   11 - age - 1); lit redstone ore goes out; bamboo / shoot grow (1/3, light 9, 12-16 tall); cactus flowers (10 % /
##   25 % at 3 tall)
## - turtle eggs crack (1/500 by day, always at celestial angle 0.65-0.69, on #sand) and hatch after 3; sniffer eggs
##   crack every 1/3 of 24000 (12000 on moss) + 0-299 ticks; frogspawn hatches 2-5 tadpoles after 3600-12000 ticks;
##   dried ghasts hydrate (5000 ticks per stage in water, drying back out of it); coral dies 60-99 ticks after it has
##   no water; eyeblossoms open at day time 12600 and close at 23401 (26.3 timeline), neighbours within 3 / 2 follow;
##   nether portals spawn zombified piglins (difficulty / 2000 per random tick, in dimensions that allow it).
## Contract: static; handles(name) / random_tick(world, p, st, name, rng) -> bool; tick(world) per game tick (timers);
## coral_check(world, p) from block updates.
class_name Growth

const DIRS6 := [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
const DIR6_NAMES := ["up", "down", "north", "south", "west", "east"]
const H4 := {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}
const CW := {"north": "east", "east": "south", "south": "west", "west": "north"}
const BUDS := ["small_amethyst_bud", "medium_amethyst_bud", "large_amethyst_bud", "amethyst_cluster"]
const HANDLED := ["budding_amethyst", "pointed_dripstone", "vine", "cave_vines", "twisting_vines", "weeping_vines", "chorus_flower",
	"brown_mushroom", "red_mushroom", "crimson_nylium", "warped_nylium", "frosted_ice", "redstone_ore", "deepslate_redstone_ore",
	"bamboo", "bamboo_sapling", "turtle_egg", "sniffer_egg", "frogspawn", "dried_ghast", "nether_portal", "open_eyeblossom",
	"closed_eyeblossom", "mangrove_propagule"]

static var _timers: Dictionary = {}   # Vector3i -> [due game tick, kind]


static var _coral_t := PackedByteArray()


static func is_coral_state(st: int) -> bool:
	var b := _b()
	if _coral_t.size() != b.total_states:
		_coral_t.resize(b.total_states)
		for s in b.total_states:
			_coral_t[s] = 1 if s > 0 and is_live_coral(b.names[b.st_block[s]]) else 0
	return st > 0 and _coral_t[st] == 1


## Block change at p (WorldManager.set_block): live coral at p or next to it checks for water.
static func on_changed(world, p: Vector3i) -> void:
	for d in [Vector3i.ZERO, Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]:
		var q: Vector3i = p + d
		if is_coral_state(world.state_at(q.x, q.y, q.z)):
			coral_check(world, q)


static func handles(name: String) -> bool:
	return HANDLED.has(name)


static func reset() -> void:
	_timers.clear()


static func _b() -> BlockRegistry:
	return Res.blocks


static func _name(world, p: Vector3i) -> String:
	var st: int = world.state_at(p.x, p.y, p.z)
	return _b().name_of(st) if st > 0 else ("air" if st == 0 else "")


static func _air(world, p: Vector3i) -> bool:
	return world.state_at(p.x, p.y, p.z) == 0


static func _water_source(st: int) -> bool:
	return st > 0 and _b().st_block[st] == _b().st_block[Res.blocks.WATER] and _b().st_level[st] == 0


static func _raw_light(world, p: Vector3i) -> int:
	var l: int = world.cm.get_light(p.x, p.y, p.z)
	return maxi(l >> 4, l & 15)


static func _full(st: int) -> bool:
	return st > 0 and (_b().st_flags[st] & BlockRegistry.F_FULL_SHAPE) != 0


static func random_tick(world, p: Vector3i, st: int, name: String, rng: RandomNumberGenerator) -> bool:
	match name:
		"budding_amethyst":
			_amethyst(world, p, rng)
		"pointed_dripstone":
			_dripstone(world, p, st, rng)
		"vine":
			_vine(world, p, st, rng)
		"cave_vines":
			_grow_head(world, p, st, Vector3i.DOWN, "cave_vines_plant", rng, true)
		"weeping_vines":
			_grow_head(world, p, st, Vector3i.DOWN, "weeping_vines_plant", rng, false)
		"twisting_vines":
			_grow_head(world, p, st, Vector3i.UP, "twisting_vines_plant", rng, false)
		"chorus_flower":
			_chorus(world, p, st, rng)
		"brown_mushroom", "red_mushroom":
			_mushroom(world, p, st, name, rng)
		"crimson_nylium", "warped_nylium":
			var up: int = world.state_at(p.x, p.y + 1, p.z)
			if up > 0 and _b().st_opacity[up] >= 15:
				world.set_block(p.x, p.y, p.z, _b().default_state("netherrack"))
		"frosted_ice":
			frosted_ice_tick(world, p, st, rng)
		"redstone_ore", "deepslate_redstone_ore":
			if _b().get_prop(st, "lit") == "true":
				world.set_block(p.x, p.y, p.z, _b().with_prop(st, "lit", "false"))   # wiki Redstone Ore: the next random tick
		"bamboo":
			_bamboo(world, p, st, rng)
		"bamboo_sapling":
			if rng.randi_range(0, 2) == 0 and _air(world, p + Vector3i.UP) and _raw_light(world, p + Vector3i.UP) >= 9:
				world.set_block(p.x, p.y + 1, p.z, _b().with_prop(_b().default_state("bamboo"), "leaves", "small"))
				world.set_block(p.x, p.y, p.z, _b().default_state("bamboo"))   # (BambooSaplingBlock.updateShape: bamboo above)
		"turtle_egg":
			_turtle_egg(world, p, st, rng)
		"sniffer_egg", "frogspawn":
			if not _timers.has(p):
				schedule_hatch(world, p, st, rng)
		"dried_ghast":
			if not _timers.has(p):
				var h := int(_b().get_prop(st, "hydration")) if _b().has_prop(st, "hydration") else 0
				var wet := _b().get_prop(st, "waterlogged") == "true"
				if (wet and h < 4) or (not wet and h > 0):
					_timers[p] = [int(world.game_time) + 5000, "dried_ghast"]   # wiki Dried Ghast: 250 s per stage
		"nether_portal":
			_portal_piglin(world, p, rng)
		"open_eyeblossom", "closed_eyeblossom":
			_eyeblossom(world, p, st, name, rng, true)
		"mangrove_propagule":
			if _b().get_prop(st, "hanging") != "true":
				var light := _raw_light(world, p + Vector3i.UP)
				if light >= 9 and rng.randi_range(0, 6) == 0:
					if _b().get_prop(st, "stage") == "0":
						world.set_block(p.x, p.y, p.z, _b().with_prop(st, "stage", "1"))
					else:
						TreeGrower.grow(world, p, st)
		_:
			return false
	return true


# ------------------------------------------------------------------ amethyst

static func _amethyst(world, p: Vector3i, rng: RandomNumberGenerator) -> void:
	var di := rng.randi_range(0, 5)
	if rng.randi_range(0, 4) != 0:
		return
	var q: Vector3i = p + DIRS6[di]
	var qs: int = world.state_at(q.x, q.y, q.z)
	var face: String = DIR6_NAMES[di]
	var b := _b()
	if qs == 0 or _water_source(qs):
		var ns := b.with_prop(b.default_state(BUDS[0]), "facing", face)
		world.set_block(q.x, q.y, q.z, b.with_prop(ns, "waterlogged", "true" if qs != 0 else "false"))
		return
	var qn := b.name_of(qs)
	var i := BUDS.find(qn)
	if i >= 0 and i < 3 and b.get_prop(qs, "facing") == face:
		var ns2 := b.with_prop(b.default_state(BUDS[i + 1]), "facing", face)
		world.set_block(q.x, q.y, q.z, b.with_prop(ns2, "waterlogged", b.get_prop(qs, "waterlogged")))


# ------------------------------------------------------------------ dripstone

static func _is_drip(world, q: Vector3i, dir: String) -> bool:
	var st: int = world.state_at(q.x, q.y, q.z)
	return st > 0 and _b().name_of(st) == "pointed_dripstone" and _b().get_prop(st, "vertical_direction") == dir


## Java PointedDripstoneBlock.calculateDripstoneThickness for every block of the column through q (direction dir).
static func _rethick(world, q: Vector3i, dir: String) -> void:
	var step := Vector3i.DOWN if dir == "down" else Vector3i.UP
	var top := q
	while _is_drip(world, top - step, dir):
		top -= step
	var c := top
	while _is_drip(world, c, dir):
		var st: int = world.state_at(c.x, c.y, c.z)
		var toward := c + step
		var opp := "up" if dir == "down" else "down"
		var th := "tip"
		if _is_drip(world, toward, opp):
			th = "tip_merge"
		elif _is_drip(world, toward, dir):
			var ts: int = world.state_at(toward.x, toward.y, toward.z)
			var tt := _b().get_prop(ts, "thickness")
			if tt != "tip" and tt != "tip_merge":
				th = "base" if not _is_drip(world, c - step, dir) else "middle"
			else:
				th = "frustum"
		if _b().get_prop(st, "thickness") != th:
			world.set_block(c.x, c.y, c.z, _b().with_prop(st, "thickness", th))
		c += step


static func _dripstone(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	if b.get_prop(st, "vertical_direction") != "down" or _is_drip(world, p + Vector3i.UP, "down"):
		return   # only the top block of a stalactite acts (isStalactiteStartPos)
	var f := rng.randf()
	# fluid transfer: the liquid (or mud) above the block the stalactite hangs from
	if f <= 45.0 / 256.0:
		var root := p + Vector3i.UP
		var src := root + Vector3i.UP
		var ss: int = world.state_at(src.x, src.y, src.z)
		var evap: bool = bool((world.dim_type.get("attributes", {}) as Dictionary).get("minecraft:gameplay/water_evaporates", false)) if world.get("dim_type") is Dictionary else false
		var fluid := ""
		if ss > 0 and b.name_of(ss) == "mud" and not evap:
			fluid = "mud"
		elif ss > 0 and b.st_level[ss] == 0 and (b.st_flags[ss] & BlockRegistry.F_LIQUID) != 0:
			fluid = "lava" if (b.st_flags[ss] & BlockRegistry.F_LAVA) != 0 else "water"
		elif ss > 0 and (b.st_flags[ss] & BlockRegistry.F_WATERLOGGED) != 0 and b.get_prop(ss, "waterlogged") == "true":
			fluid = "water"
		var chance := 15.0 / 256.0 if fluid == "lava" else 45.0 / 256.0
		if fluid != "" and f < chance:
			var tip := p
			var n := 0
			while _is_drip(world, tip + Vector3i.DOWN, "down") and n < 11:
				tip += Vector3i.DOWN
				n += 1
			if fluid == "mud":
				world.set_block(src.x, src.y, src.z, b.default_state("clay"))
			else:
				for i in range(1, 12):
					var cq := tip + Vector3i(0, -i, 0)
					var cs: int = world.state_at(cq.x, cq.y, cq.z)
					if cs == 0:
						continue
					var cn := b.name_of(cs)
					var ok := cn == "cauldron" or (fluid == "water" and cn == "water_cauldron" and int(b.get_prop(cs, "level")) < 3)
					if ok and not _timers.has(cq):   # (a scheduled tick is never re-scheduled)
						_timers[cq] = [int(world.game_time) + 50 + tip.y - cq.y, "cauldron_" + fluid]
					break
	# growth (64 / 5625): needs a dripstone block above with a water source above that
	if rng.randf() >= 0.011377778:
		return
	var a1: int = world.state_at(p.x, p.y + 1, p.z)
	var a2: int = world.state_at(p.x, p.y + 2, p.z)
	if a1 <= 0 or b.name_of(a1) != "dripstone_block" or not (_water_source(a2) or (a2 > 0 and b.get_prop(a2, "waterlogged") == "true")):
		return
	var tip2 := p
	var len := 1
	while _is_drip(world, tip2 + Vector3i.DOWN, "down"):
		tip2 += Vector3i.DOWN
		len += 1
	var ts: int = world.state_at(tip2.x, tip2.y, tip2.z)
	if b.get_prop(ts, "waterlogged") == "true" or not _air(world, tip2 + Vector3i.DOWN):
		return
	if rng.randi_range(0, 1) == 0:
		if len < 8:
			_place_tip(world, tip2 + Vector3i.DOWN, "down")
	else:
		# a stalagmite below: an upward tip within 10 blocks grows, or a new one starts on a sturdy floor
		var q := tip2
		for i in 10:
			q += Vector3i.DOWN
			var qs: int = world.state_at(q.x, q.y, q.z)
			if qs > 0 and (b.st_flags[qs] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and b.get_prop(qs, "waterlogged") != "false":
				return
			if _is_drip(world, q, "up"):
				if _air(world, q + Vector3i.UP):
					_place_tip(world, q + Vector3i.UP, "up")
				return
			if qs == 0:
				var fl: int = world.state_at(q.x, q.y - 1, q.z)
				if fl > 0 and _full(fl) and not _is_drip(world, q + Vector3i.DOWN, "up"):
					_place_tip(world, q, "up")
					return
				continue
			return


static func _place_tip(world, q: Vector3i, dir: String) -> void:
	var b := _b()
	var ns := b.with_prop(b.with_prop(b.default_state("pointed_dripstone"), "vertical_direction", dir), "thickness", "tip")
	world.set_block(q.x, q.y, q.z, ns)
	_rethick(world, q, dir)


# ------------------------------------------------------------------ vines

static func _vine_face_ok(world, q: Vector3i, dir: Vector3i) -> bool:
	# MultifaceBlock.canAttachTo: the block's face toward the vine is full
	return _full(world.state_at(q.x, q.y, q.z))


static func _vine_can_spread(world, p: Vector3i) -> bool:
	var b := _b()
	var vid := b.block_id("vine")
	var j := 5
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for dy in range(-1, 2):
				var s: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
				if s > 0 and b.st_block[s] == vid:
					j -= 1
					if j <= 0:
						return false
	return true


static func _has_side(st: int) -> bool:
	for d in H4:
		if _b().get_prop(st, d) == "true":
			return true
	return false


static func _vine(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	if not world.gamerule("doVinesSpread", true) or rng.randi_range(0, 3) != 0:
		return
	var b := _b()
	var di := rng.randi_range(0, 5)
	var dname: String = DIR6_NAMES[di]
	var dv: Vector3i = DIRS6[di]
	var vine0 := b.default_state("vine")
	if H4.has(dname) and b.get_prop(st, dname) != "true":
		if not _vine_can_spread(world, p):
			return
		var t := p + dv
		if _air(world, t):
			var cw: String = CW[dname]
			var ccw: String = CW[CW[CW[dname]]]
			var b1 := b.get_prop(st, cw) == "true"
			var b2 := b.get_prop(st, ccw) == "true"
			var t1: Vector3i = t + H4[cw]
			var t2: Vector3i = t + H4[ccw]
			var opp: String = CW[CW[dname]]
			if b1 and _vine_face_ok(world, t1, H4[cw]):
				world.set_block(t.x, t.y, t.z, b.with_prop(vine0, cw, "true"))
			elif b2 and _vine_face_ok(world, t2, H4[ccw]):
				world.set_block(t.x, t.y, t.z, b.with_prop(vine0, ccw, "true"))
			elif b1 and _air(world, t1) and _vine_face_ok(world, p + H4[cw], dv):
				world.set_block(t1.x, t1.y, t1.z, b.with_prop(vine0, opp, "true"))
			elif b2 and _air(world, t2) and _vine_face_ok(world, p + H4[ccw], dv):
				world.set_block(t2.x, t2.y, t2.z, b.with_prop(vine0, opp, "true"))
			elif rng.randf() < 0.05 and _vine_face_ok(world, t + Vector3i.UP, Vector3i.UP):
				world.set_block(t.x, t.y, t.z, b.with_prop(vine0, "up", "true"))
		elif _vine_face_ok(world, t, dv):
			world.set_block(p.x, p.y, p.z, b.with_prop(st, dname, "true"))
		return
	if dname == "up":
		if _vine_face_ok(world, p + Vector3i.UP, Vector3i.UP) and b.get_prop(st, "up") != "true":
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "up", "true"))
			return
		if _air(world, p + Vector3i.UP):
			if not _vine_can_spread(world, p):
				return
			var ns := st
			for d in H4:
				if rng.randi_range(0, 1) == 1 or not _vine_face_ok(world, p + Vector3i.UP + H4[d], H4[d]):
					ns = b.with_prop(ns, d, "false")
			ns = b.with_prop(ns, "up", "false")
			if _has_side(ns):
				world.set_block(p.x, p.y + 1, p.z, ns)
			return
	var bq := p + Vector3i.DOWN
	var bs: int = world.state_at(bq.x, bq.y, bq.z)
	if bs == 0 or (bs > 0 and b.name_of(bs) == "vine"):
		var cur := vine0 if bs == 0 else bs
		var ns2 := cur
		for d in H4:
			if rng.randi_range(0, 1) == 1 and b.get_prop(st, d) == "true":
				ns2 = b.with_prop(ns2, d, "true")
		if ns2 != cur and _has_side(ns2):
			world.set_block(bq.x, bq.y, bq.z, ns2)


# ------------------------------------------------------------------ growing plant heads

## Java GrowingPlantHeadBlock.randomTick: age < 25 and 10 % to grow one block into air; the old head becomes the body
## (cave vines keep their berries; the new head has berries 11 % of the time).
static func _grow_head(world, p: Vector3i, st: int, dir: Vector3i, body: String, rng: RandomNumberGenerator, berries: bool) -> void:
	var b := _b()
	var age := int(b.get_prop(st, "age"))
	if age >= 25 or rng.randf() >= 0.1:
		return
	var q := p + dir
	if not _air(world, q):
		return
	var ns := b.with_prop(st, "age", str(age + 1))
	if berries:
		ns = b.with_prop(ns, "berries", "true" if rng.randf() < 0.11 else "false")
	world.set_block(q.x, q.y, q.z, ns)
	var bd := b.default_state(body)
	if berries and b.has_prop(bd, "berries"):
		bd = b.with_prop(bd, "berries", b.get_prop(st, "berries"))
	world.set_block(p.x, p.y, p.z, bd)


# ------------------------------------------------------------------ chorus

static func _chorus_plant_state(world, q: Vector3i) -> int:
	var b := _b()
	var st := b.default_state("chorus_plant")
	for i in 6:
		var n := _name(world, q + DIRS6[i])
		var on: bool = n == "chorus_plant" or n == "chorus_flower" or (DIR6_NAMES[i] == "down" and n == "end_stone")
		if b.has_prop(st, DIR6_NAMES[i]):
			st = b.with_prop(st, DIR6_NAMES[i], "true" if on else "false")
	return st


static func _all_air_around(world, q: Vector3i, except: String) -> bool:
	for d in H4:
		if d != except and not _air(world, q + H4[d]):
			return false
	return true


static func _chorus(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	var age := int(b.get_prop(st, "age"))
	if age >= 5 or not _air(world, p + Vector3i.UP):
		return
	var grow := false
	var stone_below := false
	var below := _name(world, p + Vector3i.DOWN)
	if below == "end_stone":
		grow = true
	elif below == "chorus_plant":
		var j := 1
		for k in 4:
			var bn := _name(world, p + Vector3i(0, -(j + 1), 0))
			if bn != "chorus_plant":
				if bn == "end_stone":
					stone_below = true
				break
			j += 1
		if j < 2 or j <= rng.randi_range(0, 4 if stone_below else 3):
			grow = true
	elif below == "air":
		grow = true
	var up := p + Vector3i.UP
	if grow and _all_air_around(world, up, "") and _air(world, p + Vector3i(0, 2, 0)):
		world.set_block(up.x, up.y, up.z, b.with_prop(b.default_state("chorus_flower"), "age", str(age)))
		world.set_block(p.x, p.y, p.z, _chorus_plant_state(world, p))
		Audio.play("block.chorus_flower.grow", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
	elif age < 4:
		var tries := rng.randi_range(0, 3)
		if stone_below:
			tries += 1
		var placed := false
		for m in tries:
			var d: String = H4.keys()[rng.randi_range(0, 3)]
			var t: Vector3i = p + H4[d]
			if _air(world, t) and _air(world, t + Vector3i.DOWN) and _all_air_around(world, t, CW[CW[d]]):
				world.set_block(t.x, t.y, t.z, b.with_prop(b.default_state("chorus_flower"), "age", str(age + 1)))
				placed = true
		if placed:
			world.set_block(p.x, p.y, p.z, _chorus_plant_state(world, p))
			Audio.play("block.chorus_flower.grow", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
		else:
			_chorus_dead(world, p, st)
	else:
		_chorus_dead(world, p, st)


static func _chorus_dead(world, p: Vector3i, st: int) -> void:
	world.set_block(p.x, p.y, p.z, _b().with_prop(st, "age", "5"))
	Audio.play("block.chorus_flower.death", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")


# ------------------------------------------------------------------ mushrooms

static func _mushroom_ok(world, q: Vector3i) -> bool:
	var bl: int = world.state_at(q.x, q.y - 1, q.z)
	if bl <= 0:
		return false
	if Tags.has_block("mushroom_grow_block", _b().name_of(bl)):
		return true
	return _raw_light(world, q) < 13 and _full(bl) and (_b().st_flags[bl] & BlockRegistry.F_OPAQUE) != 0


static func _mushroom(world, p: Vector3i, st: int, name: String, rng: RandomNumberGenerator) -> void:
	if rng.randi_range(0, 24) != 0:
		return
	var i := 5
	var b := _b()
	var mid: int = b.st_block[st]
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			for dy in range(-1, 2):
				var s: int = world.state_at(p.x + dx, p.y + dy, p.z + dz)
				if s > 0 and b.st_block[s] == mid:
					i -= 1
					if i <= 0:
						return
	var origin := p
	var t := origin + Vector3i(rng.randi_range(0, 2) - 1, rng.randi_range(0, 1) - rng.randi_range(0, 1), rng.randi_range(0, 2) - 1)
	for k in 4:
		if _air(world, t) and _mushroom_ok(world, t):
			origin = t
		t = origin + Vector3i(rng.randi_range(0, 2) - 1, rng.randi_range(0, 1) - rng.randi_range(0, 1), rng.randi_range(0, 2) - 1)
	if _air(world, t) and _mushroom_ok(world, t):
		world.set_block(t.x, t.y, t.z, st)


# ------------------------------------------------------------------ frosted ice / bamboo / cactus

## Java FrostedIceBlock.tick: (1/3 or fewer than 4 frosted neighbours) and raw light > 11 - age - 1 -> age + 1; at age 3
## it melts to water and nudges neighbouring frosted ice.
static func frosted_ice_tick(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	var age := int(b.get_prop(st, "age"))
	var fn := 0
	for d in DIRS6:
		if _name(world, p + d) == "frosted_ice":
			fn += 1
	if (rng.randi_range(0, 2) == 0 or fn < 4) and _raw_light(world, p) > 11 - age - 1:
		if age < 3:
			world.set_block(p.x, p.y, p.z, b.with_prop(st, "age", str(age + 1)))
		else:
			world.set_block(p.x, p.y, p.z, Res.blocks.WATER)
			for d in DIRS6:
				var q: Vector3i = p + d
				var qs: int = world.state_at(q.x, q.y, q.z)
				if qs > 0 and b.name_of(qs) == "frosted_ice":
					var qa := int(b.get_prop(qs, "age"))
					world.set_block(q.x, q.y, q.z, b.with_prop(qs, "age", str(qa + 1)) if qa < 3 else Res.blocks.WATER)


## Java BambooStalkBlock.randomTick / growBamboo (wiki Bamboo: 1/3, light 9 at the top, 12-16 tall).
static func _bamboo(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	if b.get_prop(st, "stage") != "0" or rng.randi_range(0, 2) != 0:
		return
	var up := p + Vector3i.UP
	if not _air(world, up) or _raw_light(world, up) < 9:
		return
	var h := 1
	while h < 16 and _name(world, p - Vector3i(0, h, 0)) == "bamboo":
		h += 1
	if h >= 16:
		return
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	var below2: int = world.state_at(p.x, p.y - 2, p.z)
	var below_b := below > 0 and b.name_of(below) == "bamboo"
	var below2_b := below2 > 0 and b.name_of(below2) == "bamboo"
	var leaves := "small"
	if below_b and b.get_prop(below, "leaves") != "none":
		leaves = "large"
		if below2_b:
			world.set_block(p.x, p.y - 1, p.z, b.with_prop(below, "leaves", "small"))
			world.set_block(p.x, p.y - 2, p.z, b.with_prop(below2, "leaves", "none"))
	var age := "1" if (b.get_prop(st, "age") == "1" or below2_b) else "0"
	var stage := "1" if (h >= 11 and rng.randf() < 0.25) or h == 15 else "0"
	var ns := b.with_prop(b.with_prop(b.with_prop(b.default_state("bamboo"), "age", age), "leaves", leaves), "stage", stage)
	world.set_block(up.x, up.y, up.z, ns)


## Java CactusBlock.randomTick (with the 26.x cactus flower; wiki Cactus Flower: 10 % on a 1-2 tall cactus, 25 % at 3).
## wiki Concrete Powder: placed into / next to water (source, flowing or a waterlogged block whose water can flow out
## toward it: not a sturdy face such as the back of stairs), landing in or next to it, or a block update next to it
## turns it into concrete; water below only counts when the powder itself is in water. Rain / splash bottles don't.
static func concrete_touches_water(world, p: Vector3i) -> bool:
	var b := _b()
	var self_wet := _is_water(world.state_at(p.x, p.y, p.z))
	for i in 6:
		if i == 1 and not self_wet:
			continue   # (DIRS6[1] = down)
		var q: Vector3i = p + DIRS6[i]
		var s: int = world.state_at(q.x, q.y, q.z)
		if not _is_water(s):
			continue
		if (b.st_flags[s] & BlockRegistry.F_LIQUID) == 0 and (b.st_flags[s] & (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)) == (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE):
			continue   # (a waterlogged full block (leaves) has no open side toward the powder)
		if (b.st_flags[s] & BlockRegistry.F_LIQUID) == 0 and _sturdy_face(s, i ^ 1):
			continue
		return true
	return false


static func _is_water(s: int) -> bool:
	if s <= 0:
		return false
	var f := _b().st_flags[s]
	return ((f & BlockRegistry.F_LIQUID) != 0 and (f & BlockRegistry.F_LAVA) == 0) or (f & BlockRegistry.F_WATERLOGGED) != 0


## Does the block's face toward direction index fi (DIRS6 order) cover the whole side (stairs' back, slab bottoms ...).
static func _sturdy_face(s: int, fi: int) -> bool:
	var b := _b()
	var n := b.name_of(s)
	if n.ends_with("_stairs"):
		var facing := b.get_prop(s, "facing")
		var half := b.get_prop(s, "half")
		return (fi == 0 and half == "top") or (fi == 1 and half == "bottom") or FACE_OF.get(fi, "") == facing
	if n.ends_with("_slab"):
		var t := b.get_prop(s, "type")
		return t == "double" or (fi == 0 and t == "top") or (fi == 1 and t == "bottom")
	return false


const FACE_OF := {2: "north", 3: "south", 4: "west", 5: "east"}


## Concrete powder at p next to (or in) water becomes concrete; true when it did.
static func concrete_check(world, p: Vector3i, st: int = -1) -> bool:
	var b := _b()
	var s: int = st if st > 0 else world.state_at(p.x, p.y, p.z)
	if s <= 0:
		return false
	var n := b.name_of(s)
	if not n.ends_with("_concrete_powder") or not concrete_touches_water(world, p):
		return false
	world.set_block(p.x, p.y, p.z, b.default_state(n.trim_suffix("_powder")))
	return true


## Pitcher crop: grows on its lower half (age 0..4); from age 3 it is two blocks tall (the 26.3 pitcher_crop_top_stage
## models are empty below stage 3), so reaching 3+ needs air (or its own upper half) above. The upper half mirrors the
## lower half's age. False when it cannot grow.
static func pitcher_grow(world, p: Vector3i, st: int, inc: int) -> bool:
	var b := _b()
	var base := p - Vector3i.UP if b.get_prop(st, "half") == "upper" else p
	var lo: int = world.state_at(base.x, base.y, base.z)
	if lo <= 0 or b.name_of(lo) != "pitcher_crop" or b.get_prop(lo, "half") != "lower":
		return false
	var age := int(b.get_prop(lo, "age"))
	var na := mini(4, age + inc)
	if na <= age:
		return false
	if na >= 3:
		var up: int = world.state_at(base.x, base.y + 1, base.z)
		if not (up == 0 or (up > 0 and b.name_of(up) == "pitcher_crop")):
			return false
		world.set_block(base.x, base.y + 1, base.z, b.with_prop(b.with_prop(lo, "age", str(na)), "half", "upper"))
	world.set_block(base.x, base.y, base.z, b.with_prop(lo, "age", str(na)))
	return true


static func cactus_tick(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	var up := p + Vector3i.UP
	if not _air(world, up):
		return
	var age := int(b.get_prop(st, "age"))
	var h := 1
	while _name(world, p - Vector3i(0, h, 0)) == "cactus":
		h += 1
		if h == 3 and age == 15:
			return
	if age == 8 and _all_air_around(world, up, ""):
		if rng.randf() <= (0.25 if h >= 3 else 0.1):
			var fl := b.default_state("cactus_flower")
			if fl > 0:
				world.set_block(up.x, up.y, up.z, fl)
	elif age == 15 and h < 3:
		world.set_block(up.x, up.y, up.z, b.default_state("cactus"))
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "age", "0"))
		return
	if age < 15:
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "age", str(age + 1)))


# ------------------------------------------------------------------ eggs, frogspawn, dried ghast

static func _turtle_egg(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	var below := _name(world, p + Vector3i.DOWN)
	if not Tags.has_block("sand", below):
		return
	var ca: float = float(world.celestial_angle()) if world.has_method("celestial_angle") else 0.0
	if not ((ca < 0.69 and ca > 0.65) or rng.randi_range(0, 499) == 0):
		return
	var hatch := int(b.get_prop(st, "hatch"))
	var at := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	if hatch < 2:
		Audio.play("entity.turtle.egg_crack", at, "Blocks", 0.7, 0.9 + rng.randf() * 0.2)
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "hatch", str(hatch + 1)))
	else:
		Audio.play("entity.turtle.egg_hatch", at, "Blocks", 0.7, 0.9 + rng.randf() * 0.2)
		world.set_block(p.x, p.y, p.z, 0)
		for j in int(b.get_prop(st, "eggs")):
			var e = world.entities.spawn_mob("turtle", Vector3(p) + Vector3(0.3 + j * 0.2, 0, 0.3), true)
			if e != null:
				e.data["home"] = [p.x, p.y, p.z]


## Sniffer egg (wiki: 24000 ticks to hatch, 12000 on moss; two cracks) / frogspawn (3600-12000 ticks).
static func schedule_hatch(world, p: Vector3i, st: int, rng: RandomNumberGenerator) -> void:
	var b := _b()
	var now := int(world.game_time)
	if b.name_of(st) == "frogspawn":
		_timers[p] = [now + rng.randi_range(3600, 12000), "frogspawn"]
	else:
		var boost := Tags.has_block("sniffer_egg_hatch_boost", _name(world, p + Vector3i.DOWN))
		_timers[p] = [now + (12000 if boost else 24000) / 3 + rng.randi_range(0, 299), "sniffer_egg"]


static func tick(world) -> void:
	if _timers.is_empty():
		return
	var now := int(world.game_time)
	var b := _b()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for p in _timers.keys():
		var t: Array = _timers[p]
		if now < int(t[0]):
			continue
		_timers.erase(p)
		var st: int = world.state_at(p.x, p.y, p.z)
		var n := b.name_of(st) if st > 0 else ("air" if st == 0 else "")
		var at := Vector3(p) + Vector3(0.5, 0.5, 0.5)
		match str(t[1]):
			"frogspawn":
				if n != "frogspawn":
					continue
				Audio.play("block.frogspawn.hatch", at, "Blocks")
				world.set_block(p.x, p.y, p.z, 0)
				for i in rng.randi_range(2, 5):
					world.entities.spawn_mob("tadpole", Vector3(p) + Vector3(rng.randf_range(0.2, 0.8), 0.1, rng.randf_range(0.2, 0.8)))
			"sniffer_egg":
				if n != "sniffer_egg":
					continue
				var h := int(b.get_prop(st, "hatch"))
				if h < 2:
					Audio.play("block.sniffer_egg.crack", at, "Blocks", 0.7, 0.9 + rng.randf() * 0.2)
					world.set_block(p.x, p.y, p.z, b.with_prop(st, "hatch", str(h + 1)))
					schedule_hatch(world, p, world.state_at(p.x, p.y, p.z), rng)
				else:
					Audio.play("block.sniffer_egg.hatch", at, "Blocks", 0.7, 0.9 + rng.randf() * 0.2)
					world.set_block(p.x, p.y, p.z, 0)
					world.entities.spawn_mob("sniffer", Vector3(p) + Vector3(0.5, 0, 0.5), true)
			"dried_ghast":
				if n != "dried_ghast":
					continue
				var hy := int(b.get_prop(st, "hydration"))
				if b.get_prop(st, "waterlogged") == "true":
					if hy < 3:
						world.set_block(p.x, p.y, p.z, b.with_prop(st, "hydration", str(hy + 1)))
					else:
						world.set_block(p.x, p.y, p.z, Res.blocks.WATER)
						world.entities.spawn_mob("happy_ghast", Vector3(p) + Vector3(0.5, 0, 0.5), true)
				elif hy > 0:
					world.set_block(p.x, p.y, p.z, b.with_prop(st, "hydration", str(hy - 1)))
			"cauldron_water":
				if n == "cauldron":
					world.set_block(p.x, p.y, p.z, b.default_state("water_cauldron"))
				elif n == "water_cauldron" and int(b.get_prop(st, "level")) < 3:
					world.set_block(p.x, p.y, p.z, b.with_prop(st, "level", str(int(b.get_prop(st, "level")) + 1)))
			"cauldron_lava":
				if n == "cauldron":
					world.set_block(p.x, p.y, p.z, b.default_state("lava_cauldron"))
			"coral":
				coral_check(world, p, false)
			"eyeblossom":
				if n == "open_eyeblossom" or n == "closed_eyeblossom":
					_eyeblossom(world, p, st, n, rng, false)


# ------------------------------------------------------------------ coral

static func is_live_coral(name: String) -> bool:
	return not name.begins_with("dead_") and (name.ends_with("_coral") or name.ends_with("_coral_block") or name.ends_with("_coral_fan") or name.ends_with("_coral_wall_fan"))


static func _coral_wet(world, p: Vector3i, st: int) -> bool:
	var b := _b()
	if b.get_prop(st, "waterlogged") == "true":
		return true
	for d in DIRS6:
		var q: Vector3i = p + d
		var qs: int = world.state_at(q.x, q.y, q.z)
		if qs > 0 and (b.st_flags[qs] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and (b.st_flags[qs] & BlockRegistry.F_LAVA) == 0:
			if (b.st_flags[qs] & BlockRegistry.F_LIQUID) != 0 or b.get_prop(qs, "waterlogged") == "true":
				return true
	return false


## Java CoralBlock / BaseCoralPlantTypeBlock: without water next to it a coral schedules its death 60-99 ticks later
## (wiki: 3-4.95 s); the tick turns it into the dead variant if it is still dry.
static func coral_check(world, p: Vector3i, schedule := true) -> void:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return
	var b := _b()
	var n := b.name_of(st)
	if not is_live_coral(n) or _coral_wet(world, p, st):
		return
	if schedule:
		if not _timers.has(p):
			_timers[p] = [int(world.game_time) + 60 + randi_range(0, 39), "coral"]
		return
	var dead := b.default_state("dead_" + n)
	if dead <= 0:
		return
	var ns := dead
	for pr in b.block_props[b.st_block[st]]:
		if b.has_prop(ns, pr[0]):
			ns = b.with_prop(ns, pr[0], b.get_prop(st, pr[0]))
	world.set_block(p.x, p.y, p.z, ns)


# ------------------------------------------------------------------ nether portal / eyeblossom

static func _portal_piglin(world, p: Vector3i, rng: RandomNumberGenerator) -> void:
	var attrs: Dictionary = (world.dim_type.get("attributes", {}) as Dictionary) if world.get("dim_type") is Dictionary else {}
	if not bool(attrs.get("minecraft:gameplay/nether_portal_spawns_piglin", false)) or not world.gamerule("doMobSpawning", true):
		return
	if rng.randi_range(0, 1999) >= int(world.difficulty):
		return
	var q := p
	while _name(world, q) == "nether_portal":
		q += Vector3i.DOWN
	var fl: int = world.state_at(q.x, q.y, q.z)
	if fl > 0 and _full(fl):
		var e = world.entities.spawn_mob("zombified_piglin", Vector3(q) + Vector3(0.5, 1.0, 0.5))
		if e != null:
			e.data["portal_cooldown"] = 300


static func _eyeblossom(world, p: Vector3i, st: int, name: String, rng: RandomNumberGenerator, spread: bool) -> void:
	var dt := int(fposmod(float(world.day_time), 24000.0))
	var want_open := dt >= 12600 and dt < 23401   # 26.3 timeline day.json gameplay/eyeblossom_open keyframes
	var is_open := name == "open_eyeblossom"
	if want_open == is_open:
		return
	world.set_block(p.x, p.y, p.z, _b().default_state("open_eyeblossom" if want_open else "closed_eyeblossom"))
	var at := Vector3(p) + Vector3(0.5, 0.5, 0.5)
	if spread:
		Audio.play("block.eyeblossom.open_long" if want_open else "block.eyeblossom.close_long", at, "Blocks")
		for dx in range(-3, 4):
			for dz in range(-3, 4):
				for dy in range(-2, 3):
					var q := p + Vector3i(dx, dy, dz)
					if q != p and (_name(world, q) == ("closed_eyeblossom" if want_open else "open_eyeblossom")) and not _timers.has(q):
						_timers[q] = [int(world.game_time) + rng.randi_range(1, 3), "eyeblossom"]   # (delay: no wiki value)
	else:
		Audio.play("block.eyeblossom.open" if want_open else "block.eyeblossom.close", at, "Blocks")
