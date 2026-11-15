## BlockUpdates — 20 TPS scheduled ticks + random ticks (randomTickSpeed per section, only sections whose
## palette contains a random-ticking state), neighbour-triggered checks: fluid flow (water 5t / lava 30t,
## falling columns, source creation, lava/water -> obsidian/cobblestone/stone), gravity blocks -> falling
## entities, crops/saplings/stems growth, grass spread/decay, leaf decay, ice/snow melt, fire burn-out,
## plant support breaking, button release. Bounded work per tick (MAX_PER_TICK).
## Contract: schedule(world, pos, delay), schedule_neighbors(world, pos), tick(world), bonemeal(world,pos,st).
class_name BlockUpdates

const MAX_PER_TICK := 2000
static var queue: Dictionary = {}   # due tick -> Array[Vector3i] (entries whose pending due differs are stale)
static var pending: Dictionary = {} # Vector3i -> due (dedupe)
static var by_chunk: Dictionary = {} # chunk key -> {Vector3i: true}: positions with a pending tick (saved with the chunk)
static var _min_due := 1 << 62
static var _rt_rng := RandomNumberGenerator.new()
static var last_sched := 0
static var last_random_us := 0
static var prof := false           # load-test tracing: per-block random tick handler time
static var prof_us: Dictionary = {}
static var prof_n: Dictionary = {}


static func reset() -> void:
	queue.clear()
	_release_pending = true   # (chunks held for the dropped updates: released on the next step_hits)
	if Res.blocks != null:
		_fluid_tables()   # (built at world start: ~30 ms over the registry, it was a hitch on the first fluid tick)
	_gen_wait.clear()
	_due.clear()
	_due_t.clear()
	_due_i = 0
	_fdue.clear()
	_fdue_t.clear()
	_fdue_i = 0
	_due_ck.clear()
	_exec_tick = -1
	_last_run_t = -1
	pending.clear()
	by_chunk.clear()
	_min_due = 1 << 62
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
	# (a tick's updates sliced over later frames count their delays from their own tick: _exec_tick)
	var due: int = (_exec_tick if _exec_tick >= 0 else int(world.game_time)) + maxi(1, delay)
	var cur = pending.get(p)
	if cur != null and int(cur) <= due:
		return
	pending[p] = due
	var ck := Coords.chunk_key(p.x >> 4, p.z >> 4)
	var bc = by_chunk.get(ck)
	if bc == null:
		bc = {}
		by_chunk[ck] = bc
	bc[p] = true
	if not queue.has(due):
		queue[due] = []
	queue[due].append(p)
	if due < _min_due:
		_min_due = due


static func _unindex(p: Vector3i) -> void:
	var ck := Coords.chunk_key(p.x >> 4, p.z >> 4)
	var bc = by_chunk.get(ck)
	if bc != null:
		bc.erase(p)
		if bc.is_empty():
			by_chunk.erase(ck)


## Java ChunkAccess ticks container: the chunk's pending ticks as [x, y, z, delay]* (saved with it). drop: the chunk
## unloads, its ticks leave the queue (LevelTicks keeps ticks only for loaded chunks; they resume when it loads).
static func store_ticks(world, c: Chunk, drop: bool) -> void:
	var ck := Coords.chunk_key(c.cx, c.cz)
	if drop:
		_gen_wait.erase(ck)   # (an unloading chunk stops waiting for its worldgen fluid ticks)
	var bc = by_chunk.get(ck)
	var out: Array = []
	if bc != null:
		for p in bc:
			out.append([p.x, p.y, p.z, maxi(0, int(pending.get(p, world.game_time)) - world.game_time)])
			if drop:
				pending.erase(p)
		if drop:
			by_chunk.erase(ck)
	# collected updates not run yet (step_hits slices) are due now: saved with delay 0, dropped from the run lists
	if _due_ck.has(ck):
		for i in range(_due_i, _due.size()):
			var q: Vector3i = _due[i]
			if q.y > -100000 and (q.x >> 4) == c.cx and (q.z >> 4) == c.cz:
				out.append([q.x, q.y, q.z, 0])
				if drop:
					_due[i] = Vector3i(0, -100000, 0)   # (skipped: below the world)
		for i in range(_fdue_i, _fdue.size()):
			var q: Vector3i = _fdue[i]
			if q.y > -100000 and (q.x >> 4) == c.cx and (q.z >> 4) == c.cz:
				out.append([q.x, q.y, q.z, 0])
				if drop:
					_fdue[i] = Vector3i(0, -100000, 0)
		if drop:
			_due_ck.erase(ck)
	c.scheduled = out
	if not out.is_empty():
		c.modified = true


## Java worldgen fluid ticks: aquifer water where the aquifer status changes (NoiseBasedChunkGenerator / carvers mark
## it for post-processing; LevelChunk.postProcessGeneration ticks it when the chunk becomes full) and SpringFeature's
## scheduled tick make generated water / lava next to open space flow on load: waterfalls out of cliff springs,
## cave aquifer edges, lava pools meeting water. Here: every generated fluid cell with air below or beside it (or the
## other fluid next to it) gets a tick when its chunk is first decorated (native scan, one chunk per frame).
static var _gen_q: Array = []
static var _kinds := PackedByteArray()


static var _gen_wait: Dictionary = {}   # chunk key -> Chunk: decorated, waiting for its 3 x 3 neighbours to decorate


## A chunk that just decorated / loaded from disk may complete a waiting neighbour's 3 x 3 (event driven: no polling;
## called from on_chunk_ready).
static func _gen_wake(cx: int, cz: int) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var wk := Coords.chunk_key(cx + dx, cz + dz)
			var wc = _gen_wait.get(wk)
			if wc != null:
				_gen_wait.erase(wk)
				_gen_q.append(wc)


static func gen_fluid_ticks(_world, c: Chunk) -> void:
	if c.from_disk or c.gen_ticked:
		return
	c.gen_ticked = true
	_gen_q.append(c)


static func _gen_step(world) -> void:
	# Java LevelChunk.postProcessGeneration runs when the chunk becomes FULL, i.e. after its 3 x 3 neighbourhood has
	# finished its features: exposure is judged against decorated neighbours only. A neighbour that is still raw has
	# cave air where its pool walls, moss and plants come later - water flowed into it and broke worldgen plants (lush
	# caves dropped dripleaves, glow berries, azaleas while chunks loaded). Chunks still waiting go to the back.
	var c: Chunk = _gen_q.pop_front()
	if c == null or c.state == Chunk.EVICTED or not world.cm.chunks.has(Coords.chunk_key(c.cx, c.cz)):
		return
	if not _neighbours_decorated(world, c):
		_gen_wait[Coords.chunk_key(c.cx, c.cz)] = c   # (woken by on_chunk_ready of a neighbour; dropped on unload)
		if _gen_wait.size() > 4096:
			_gen_wait.clear()   # (safety: far unloaded leftovers)
		return
	var blocks := Res.blocks
	if _kinds.size() != blocks.total_states:
		_kinds.resize(blocks.total_states)
		for s in blocks.total_states:
			var fl := blocks.st_flags[s]
			var nm := blocks.name_of(s)
			_kinds[s] = 1 if (s == 0 or nm == "air" or nm == "cave_air" or nm == "void_air") else (3 if (fl & BlockRegistry.F_LIQUID) and (fl & BlockRegistry.F_LAVA) else (2 if fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED) else 0))
	if not (Native.chunkops_ok and Native.inst != null and Native.inst.has_method("fluid_exposed")):
		return
	var nine: Array = []
	nine.resize(9)
	for dz in 3:
		for dx in 3:
			var nc: Chunk = world.cm.chunks.get(Coords.chunk_key(c.cx + dx - 1, c.cz + dz - 1))
			if nc != null and nc.state >= Chunk.DATA_READY:
				nine[dz * 3 + dx] = nc.sec_refs()
	var pos: PackedInt32Array = Native.inst.fluid_exposed(nine, _kinds, c.cx, c.cz)[0]
	var x0 := c.cx * 16
	var z0 := c.cz * 16
	# spread over 10 ticks: a chunk can expose hundreds of fluid cells (cave aquifers), and a tick's updates are shown
	# together once they all ran (Java ticks them on the first tick; here the waterfalls start within half a second)
	var gi := 0
	for v in pos:
		schedule(world, Vector3i(x0 + (v & 15), (v >> 8) - 64, z0 + ((v >> 4) & 15)), 1 + gi % 10)
		gi += 1


static func _neighbours_decorated(world, c: Chunk) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nc: Chunk = world.cm.chunks.get(Coords.chunk_key(c.cx + dx, c.cz + dz))
			if nc == null or not nc.decorated:
				return false
	return true


## A chunk loaded from a save: its stored ticks back into the queue.
static func restore_ticks(world, c: Chunk) -> void:
	for e in c.scheduled:
		if e is Array and (e as Array).size() >= 4:
			schedule(world, Vector3i(int(e[0]), int(e[1]), int(e[2])), int(e[3]))
	c.scheduled = []


const _NB_SCHED := [Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i.ZERO]


static func schedule_neighbors(world, p: Vector3i) -> void:
	for d in _NB_SCHED:
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


## Java LevelTicks.tick: every tick due at or before now runs, oldest first (a tick whose game tick was skipped -
## world not ready yet, a long frame - runs late instead of being lost; ticks were only taken from the exact current
## tick and older ones were thrown away every 200 ticks, leaving flows standing until a block next to them changed).
static var sched_peak_us := 0   # (probes) worst tick_scheduled time / count
static var sched_peak_n := 0
static var sched_calls := 0
static var sched_total_us := 0
static var sched_total_n := 0
static var sched_first_us := 0


static func tick_scheduled(world) -> void:
	# the game: a tick's due updates run in budgeted slices over the frames that follow (step_hits) - a burst of fluid
	# ticks (chunks loading next to cave water / lava) never lands in one frame. A rest of earlier ticks keeps running
	# first (in tick order; each update schedules from its own tick: _exec_tick). Test worlds (no player) run them at once.
	var defer: bool = world.get("player") != null
	var t: int = world.game_time
	var n := 0
	if _min_due > t:
		last_sched = 0
		return
	var keys: Array = []
	for k in queue:
		if int(k) <= t:
			keys.append(k)
	keys.sort()
	# Java: only chunks within the simulation distance tick; ticks elsewhere wait (checked again a second later)
	var sim := int(Settings.get_v("simulation_distance"))
	var pl = world.get("player")
	if pl == null:
		sim = 1 << 20   # (test worlds have no player)
	var pcx := int(floor(pl.pos.x)) >> 4 if pl != null else 0
	var pcz := int(floor(pl.pos.z)) >> 4 if pl != null else 0
	for k in keys:
		var lst: Array = queue[k]
		queue.erase(k)
		for p in lst:
			if int(pending.get(p, -1)) != int(k):
				continue   # stale: re-scheduled earlier (already ran) or its chunk unloaded
			if maxi(absi((p.x >> 4) - pcx), absi((p.z >> 4) - pcz)) > sim:
				pending.erase(p)
				schedule(world, p, 20)
				continue
			pending.erase(p)
			_unindex(p)
			if n < MAX_PER_TICK:
				if defer:
					_due_add(p, t, maxi(absi((p.x >> 4) - pcx), absi((p.z >> 4) - pcz)) <= NEAR_CHUNKS)
				else:
					_scheduled(world, p)
				n += 1
			else:
				schedule(world, p, 1)
	_min_due = 1 << 62
	for k2 in queue:
		_min_due = mini(_min_due, int(k2))
	last_sched = n


## Collected due updates, in tick order: near the player (NEAR_CHUNKS) and farther away. Each frame's share runs the
## near ones first (a backlog of far ticks - chunks streaming in with springs / aquifer water - never delays the flows
## the player watches) and holds their block changes until their tick's updates all ran; far ones take the rest.
const NEAR_CHUNKS := 3
static var _due: Array = []
static var _due_t := PackedInt64Array()   # the game tick each collected update belongs to
static var _due_i := 0
static var _fdue: Array = []
static var _fdue_t := PackedInt64Array()
static var _fdue_i := 0
static var _due_ck: Dictionary = {}       # chunk key -> collected updates not run yet (store_ticks scans only those)
## While an update runs, schedule() counts delays from its own tick: Java runs a tick's due updates inside that tick,
## so a flow advances exactly every 5 ticks - counting from the frame's game_time made slices that spilled into the next
## tick schedule their followers a tick late, and the flow front frayed into steps on consecutive ticks (measured:
## changes on ticks 35, 36 and 37 of one step).
static var _exec_tick := -1
static var _last_run_t := -1   # tick of the last near update run (its block changes are held until that tick's all ran)
static var _release_pending := false


static func _due_add(p: Vector3i, t: int, near: bool) -> void:
	if near:
		_due.append(p)
		_due_t.append(t)
	else:
		_fdue.append(p)
		_fdue_t.append(t)
	var ck := Coords.chunk_key(p.x >> 4, p.z >> 4)
	_due_ck[ck] = int(_due_ck.get(ck, 0)) + 1


static func _due_ran(p: Vector3i) -> void:
	var ck := Coords.chunk_key(p.x >> 4, p.z >> 4)
	var c := int(_due_ck.get(ck, 0)) - 1
	if c > 0:
		_due_ck[ck] = c
	else:
		_due_ck.erase(ck)


static func due_count() -> int:
	return (_due.size() - _due_i) + (_fdue.size() - _fdue_i)


static func _run_due(world, n: int, budget_us: int = 1 << 40) -> void:
	var t0 := Time.get_ticks_usec()
	var done := 0
	if _due_i < _due.size():
		# block changes of a sliced tick are shown together when the tick's last update ran (ChunkManager holds their
		# chunks' update work meanwhile): a step of a flow appears at once instead of in pieces over the frames
		var cmh = world.cm if world.get("cm") is ChunkManager else null
		if cmh != null:
			cmh.hold_marks = true
		while _due_i < _due.size() and done < n and (done == 0 or Time.get_ticks_usec() - t0 < budget_us):
			var tt: int = _due_t[_due_i]
			if tt != _last_run_t:
				if _last_run_t >= 0 and cmh != null:
					cmh.release_held()   # every update of the previous tick ran
				_last_run_t = tt
			_exec_tick = tt
			var p: Vector3i = _due[_due_i]
			_due_i += 1
			done += 1
			if p.y > -100000:
				_due_ran(p)
				_scheduled(world, p)
		_exec_tick = -1
		if cmh != null:
			cmh.hold_marks = false
		if _due_i >= _due.size():
			_due.clear()
			_due_t.clear()
			_due_i = 0
			_last_run_t = -1
			if cmh != null:
				cmh.release_held()
		elif _due_i >= 4096:
			_due = _due.slice(_due_i)   # (a long backlog: drop the part already run)
			_due_t = _due_t.slice(_due_i)
			_due_i = 0
	while _fdue_i < _fdue.size() and done < n and (done == 0 or Time.get_ticks_usec() - t0 < budget_us):
		_exec_tick = _fdue_t[_fdue_i]
		var fp: Vector3i = _fdue[_fdue_i]
		_fdue_i += 1
		done += 1
		if fp.y > -100000:
			_due_ran(fp)
			_scheduled(world, fp)
	_exec_tick = -1
	if _fdue_i >= _fdue.size():
		_fdue.clear()
		_fdue_t.clear()
		_fdue_i = 0
	elif _fdue_i >= 4096:
		_fdue = _fdue.slice(_fdue_i)
		_fdue_t = _fdue_t.slice(_fdue_i)
		_fdue_i = 0
	var dt := Time.get_ticks_usec() - t0
	sched_calls += 1
	sched_total_us += dt
	sched_total_n += done
	if dt > sched_peak_us:
		sched_peak_us = dt
		sched_peak_n = done


## Random-tick sampling of the tick (handlers run spread over the following frames: step_hits).
static func tick_random(world) -> void:
	_random_ticks(world)
	tick_precipitation(world)


## Java ServerLevel.tickChunk weather column: per ticking chunk, randomTickSpeed rolls of 1 in 48 (the wiki's 1/16 per
## chunk tick at the default speed 3), each picking a random column for tickPrecipitation. Hits are drawn directly
## (geometric gaps over all rolls of the simulation area) instead of rolling every chunk.
static var _pr_rng := RandomNumberGenerator.new()
static var pr_stats := PackedInt32Array([0, 0, 0, 0])   # (probes) calls, columns, snow placed, ice placed


static func tick_precipitation(world) -> void:
	pr_stats[0] += 1
	if world.dimension != "overworld":
		return
	var speed := int(world.gamerule("randomTickSpeed", 3))
	var pl = world.get("player")
	if speed <= 0 or pl == null:
		return
	var sim := int(Settings.get_v("simulation_distance"))
	var side := sim * 2 + 1
	var total := side * side * speed
	var lq := log(1.0 - 1.0 / 48.0)
	var pcx := int(floor(pl.pos.x)) >> 4
	var pcz := int(floor(pl.pos.z)) >> 4
	var i := int(log(1.0 - _pr_rng.randf()) / lq)
	while i < total:
		var cell := i / speed
		var cx := pcx - sim + cell % side
		var cz := pcz - sim + cell / side
		var c: Chunk = world.cm.get_chunk(cx, cz)
		if c != null and c.state >= Chunk.DECORATED and c.state != Chunk.EVICTED:
			pr_stats[1] += 1
			_precip_column(world, c, cx * 16 + _pr_rng.randi_range(0, 15), cz * 16 + _pr_rng.randi_range(0, 15))
		i += 1 + int(log(1.0 - _pr_rng.randf()) / lq)


## Java ServerLevel.tickPrecipitation at the MOTION_BLOCKING top of a column: still water at the edge of a cold area
## freezes (any weather); while it rains, snow falls on cold ground (adding layers up to snowAccumulationHeight) and
## the block below gets Block.handlePrecipitation (cauldrons: rain 5 %, snow 10 % per hit).
static var _pblock := PackedByteArray()   # per state: 1 = stops the precipitation column search (fluid, or collides and not snow)


static func _precip_column(world, c: Chunk, x: int, z: int) -> void:
	var blocks := Res.blocks
	var snow_id := blocks.block_id("snow")
	if _pblock.size() != blocks.total_states:
		var fl: PackedInt32Array = blocks.st_flags
		_pblock.resize(blocks.total_states)
		for s0 in range(1, blocks.total_states):
			_pblock[s0] = 1 if (fl[s0] & BlockRegistry.F_LIQUID) != 0 or ((fl[s0] & BlockRegistry.F_COLLIDE) != 0 and blocks.st_block[s0] != snow_id) else 0
	var pb := _pblock
	# the topmost fluid / colliding non-snow block of the column, read straight from the section palettes
	var y := Coords.MIN_Y - 1
	var col := ((z & 15) << 4) | (x & 15)
	for s in range(Coords.SECTIONS - 1, -1, -1):
		var sec: Chunk.Section = c.sections[s]
		var pal := sec.pal
		if pal.size() == 1:
			if pb[pal[0]] != 0:
				y = Coords.MIN_Y + s * 16 + 15
				break
			continue
		var wide := sec.wide
		var idx := sec.idx
		var found := -1
		for ly in range(15, -1, -1):
			var vi := (ly << 8) | col
			if pb[pal[wide[vi]] if wide.size() > 0 else pal[idx[vi]]] != 0:
				found = ly
				break
		if found >= 0:
			y = Coords.MIN_Y + s * 16 + found
			break
	var top := y + 1   # blockpos (MOTION_BLOCKING height); y = blockpos.below()
	if top >= Coords.MAX_Y:
		return
	var bio := c.biome_at(x & 15, top, z & 15)
	if bio < 0:
		return
	var cold_top := _temperature(world, bio, top) < 0.15
	var cold_below := _temperature(world, bio, y) < 0.15
	# Biome.shouldFreeze(pos below, mustBeAtEdge): a water source block, block light < 10, not surrounded by water
	if cold_below and y >= Coords.MIN_Y and (c.get_light(x & 15, y, z & 15) & 15) < 10:
		var bst := c.get_block(x & 15, y, z & 15)
		if blocks.name_of(bst) == "water" and int(blocks.st_level[bst]) == 0:
			var edge := false
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if not _is_water(world.state_at(x + d.x, y, z + d.y)):
					edge = true
					break
			if edge:
				world.set_block(x, y, z, blocks.default_state("ice"))
				pr_stats[3] += 1
	if not world.raining:
		return
	var has_precip: bool = world.biomes.precipitation[bio] != 0
	# Biome.shouldSnow(blockpos): cold, block light < 10, air or snow there, and snow could stay (SnowLayerBlock.canSurvive)
	var maxh := int(world.gamerule("snowAccumulationHeight", 1))
	if maxh > 0 and has_precip and cold_top and (c.get_light(x & 15, top, z & 15) & 15) < 10:
		var cur := c.get_block(x & 15, top, z & 15)
		if (cur == 0 or blocks.st_block[cur] == snow_id) and _snow_survives(world, x, top, z):
			if cur != 0 and blocks.st_block[cur] == snow_id:
				var layers := int(blocks.get_prop(cur, "layers"))
				if layers < mini(maxh, 8):
					world.set_block(x, top, z, blocks.with_prop(cur, "layers", str(layers + 1)))
			else:
				world.set_block(x, top, z, blocks.default_state("snow"))
				pr_stats[2] += 1
	# Block.handlePrecipitation on the block below (Biome.getPrecipitationAt there)
	if has_precip and y >= Coords.MIN_Y:
		var bst2 := c.get_block(x & 15, y, z & 15)
		var bn := blocks.name_of(bst2)
		var snowing := cold_below
		if bn == "cauldron":
			if _pr_rng.randf() < (0.1 if snowing else 0.05):
				world.set_block(x, y, z, blocks.default_state("powder_snow_cauldron" if snowing else "water_cauldron"))
		elif (bn == "water_cauldron" and not snowing) or (bn == "powder_snow_cauldron" and snowing):
			var lv := int(blocks.get_prop(bst2, "level"))
			if lv != 3 and _pr_rng.randf() < (0.1 if snowing else 0.05):
				world.set_block(x, y, z, blocks.with_prop(bst2, "level", str(lv + 1)))


## Biome.getTemperature(pos) (height-adjusted above sea level + 17).
static func _temperature(world, bio: int, y: int) -> float:
	var gen = world.gen
	if gen != null and gen.has_method("biome_temperature_at"):
		return gen.biome_temperature_at(bio, 0, y, 0)
	var t: float = world.biomes.temperature[bio]
	if y > 80:
		t -= float(y - 80) * 0.05 / 40.0
	return t


## Level.isWaterAt: the fluid there is water (source, flowing or waterlogged).
static func _is_water(st: int) -> bool:
	if st <= 0:
		return false
	var b := Res.blocks
	return b.name_of(st) == "water" or b.name_of(st) == "bubble_column" or (b.has_prop(st, "waterlogged") and b.get_prop(st, "waterlogged") == "true")


## SnowLayerBlock.canSurvive: not on #cannot_support_snow_layer (ice, packed ice, barrier); always on
## #support_override_snow_layer (honey block, soul sand, mud); else a full top face or a full snow stack.
static func _snow_survives(world, x: int, y: int, z: int) -> bool:
	var below: int = world.state_at(x, y - 1, z)
	if below <= 0:
		return false
	var b := Res.blocks
	var bn := b.name_of(below)
	if bn in ["ice", "packed_ice", "barrier"]:
		return false
	if bn in ["honey_block", "soul_sand", "mud"]:
		return true
	if bn == "snow":
		return int(b.get_prop(below, "layers")) == 8
	return ((b.st_cull[below] >> 1) & 1) == 1   # full top face


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
		if name.ends_with("_concrete_powder") and Growth.concrete_check(world, p, st):
			return   # (wiki Concrete Powder: a block update next to water)
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
		Audio.play("block.%s_button.click_off" % Sensors.set_type(name), Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
		return
	if not _has_support(world, p, st):
		world.set_block(p.x, p.y, p.z, 0)
		if world.gamerule("doTileDrops", true):
			for s in Loot.block_drops(st, null, world, p):
				world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.3, 0.5), s)
		schedule_neighbors(world, p)


## The block tag a plant's mayPlaceOn reads in 26.3 (data/minecraft/tags/block/supports_*), "" when the plant is not
## covered here ("#cactus_flower" / "#sturdy": code rules).
static var _sup_cache: Dictionary = {}


static func _support_tag(name: String) -> String:
	var c = _sup_cache.get(name)
	if c != null:
		return c
	var t := ""
	if name == "cactus_flower":
		t = "#cactus_flower"
	elif name == "leaf_litter":
		t = "#sturdy"
	elif name == "wither_rose":
		t = "supports_wither_rose"
	elif name in ["dead_bush", "short_dry_grass", "tall_dry_grass"]:
		t = "supports_dry_vegetation"
	elif name in ["azalea", "flowering_azalea"]:
		t = "supports_azalea"
	elif name in ["big_dripleaf", "big_dripleaf_stem", "small_dripleaf"]:
		t = "#dripleaf"
	elif name in ["mangrove_propagule", "spore_blossom", "chorus_flower", "chorus_plant"]:
		t = ""   # (own rules: hanging propagules, ceiling blossoms, chorus on end stone)
	elif name in ["wheat", "carrots", "potatoes", "beetroots", "torchflower_crop", "pitcher_crop"]:
		t = "supports_crops"
	elif name in ["melon_stem", "pumpkin_stem", "attached_melon_stem", "attached_pumpkin_stem"]:
		t = "supports_stem_crops"
	elif name == "nether_wart":
		t = "supports_nether_wart"
	elif name in ["crimson_roots", "warped_roots", "crimson_fungus", "warped_fungus", "nether_sprouts"]:
		t = "supports_" + name
	elif name in ["short_grass", "fern", "tall_grass", "large_fern", "sweet_berry_bush", "bush", "firefly_bush", "pink_petals", "wildflowers"] \
			or name.ends_with("_sapling") and name != "bamboo_sapling" or Tags.has_block("small_flowers", name) or Tags.has_block("flowers", name) and name != "cactus_flower" and name != "flowering_azalea" and not name.ends_with("_leaves"):
		t = "supports_vegetation"
	_sup_cache[name] = t
	return t


static func _has_support(world, p: Vector3i, st: int) -> bool:
	var blocks := Res.blocks
	var name := blocks.name_of(st)
	var below: int = world.state_at(p.x, p.y - 1, p.z)
	if below < 0:
		return true
	var bname := blocks.name_of(maxi(below, 0))
	if Res.mode == "vanilla":
		var sup := _support_tag(name)
		if sup == "#dripleaf":
			return _dripleaf_support(world, p, st, name, below, bname)
		if sup != "":
			# 26.3 data-driven mayPlaceOn tags; the upper half of a tall plant stands on its lower half
			if blocks.has_prop(st, "half") and blocks.get_prop(st, "half") == "upper":
				return below > 0 and blocks.st_block[below] == blocks.st_block[st]
			if sup == "#cactus_flower":
				# Java CactusFlowerBlock.mayPlaceOn: #support_override_cactus_flower or a sturdy centre on top
				return below > 0 and (Tags.has_block("support_override_cactus_flower", bname) or (blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0)
			if sup == "#sturdy":
				return below > 0 and (blocks.st_flags[below] & (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)) == (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)
			return below > 0 and Tags.has_block(sup, bname)
	if name in ["short_grass", "fern", "dandelion", "poppy", "tall_grass", "large_fern", "dead_bush", "sweet_berry_bush"] or name.ends_with("_tulip") or name.ends_with("_sapling") or name in ["allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "blue_orchid"]:
		return below > 0 and (bname in ["grass_block", "dirt", "podzol", "coarse_dirt", "farmland", "moss_block", "mud", "rooted_dirt", "mycelium", "sand", "red_sand", "terracotta"] or bname == name and blocks.has_prop(st, "half"))
	if name in ["crimson_roots", "warped_roots", "nether_sprouts", "crimson_fungus", "warped_fungus"]:
		# Java RootsBlock / NetherSproutsBlock / FungusBlock.mayPlaceOn: #nylium, soul soil, #dirt (mycelium), farmland
		return below > 0 and bname in ["crimson_nylium", "warped_nylium", "soul_soil", "grass_block", "dirt", "podzol", "coarse_dirt", "farmland", "moss_block", "mud", "rooted_dirt", "mycelium", "muddy_mangrove_roots", "pale_moss_block"]
	if name in ["wheat", "carrots", "potatoes", "beetroots", "melon_stem", "pumpkin_stem", "attached_melon_stem", "attached_pumpkin_stem"]:
		return bname == "farmland"   # (only these: big_dripleaf_stem / mushroom_stem / crimson_stem used to match "_stem")
	if name == "torch" or name == "redstone_torch" or name == "soul_torch" or name.ends_with("_carpet") or name.ends_with("_pressure_plate") or name == "redstone_wire" or name.ends_with("rail") or name == "snow":
		return below > 0 and (blocks.st_flags[below] & BlockRegistry.F_COLLIDE) != 0
	if name == "sugar_cane":
		# wiki Sugar Cane: on sugar cane, or on grass / dirt / podzol / mycelium / sand / moss / mud (26.3 #supports_sugar_cane)
		# whose side touches water, a waterlogged block or frosted ice (#supports_sugar_cane_adjacently) - not above / diagonal
		if bname == "sugar_cane":
			return true
		var scs := Tags.blocks("supports_sugar_cane")
		if below <= 0 or not (scs.has(bname) if not scs.is_empty() else bname in ["grass_block", "dirt", "coarse_dirt", "rooted_dirt", "podzol", "mycelium", "sand", "red_sand", "suspicious_sand", "moss_block", "pale_moss_block", "mud", "muddy_mangrove_roots"]):
			return false
		for d in HDIRS:
			var ws: int = world.state_at(p.x + d.x, p.y - 1, p.z + d.z)
			if ws < 0 or _same_fluid(ws, false) or (ws > 0 and (blocks.name_of(ws) == "frosted_ice" or Tags.has_block("supports_sugar_cane_adjacently", blocks.name_of(ws)))):
				return true
		return false
	if name == "cactus":
		# wiki Cactus: breaks with a legacy-solid block or lava beside it, or water / lava above; stands on cactus or #sand
		for d2 in HDIRS:
			var ss: int = world.state_at(p.x + d2.x, p.y, p.z + d2.z)
			if ss > 0 and (blocks.st_flags[ss] & (BlockRegistry.F_SOLID | BlockRegistry.F_LAVA)) != 0:
				return false
		var cup: int = world.state_at(p.x, p.y + 1, p.z)
		if cup > 0 and (blocks.st_flags[cup] & BlockRegistry.F_LIQUID) != 0:
			return false
		return bname == "cactus" or bname == "sand" or bname == "red_sand" or bname == "suspicious_sand"
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


## Dripleaves (wiki Big Dripleaf / Small Dripleaf, 26.3 #supports_big_dripleaf / #supports_small_dripleaf): a big
## dripleaf stands on its stem or a support block; a stem needs a stem or support below and a stem or the leaf above
## (breaking any part collapses the plant); a small dripleaf stands on clay / moss, or underwater (waterlogged) on the
## big dripleaf supports; its upper half on the lower half.
static func _dripleaf_support(world, p: Vector3i, st: int, name: String, below: int, bname: String) -> bool:
	var blocks := Res.blocks
	if name == "small_dripleaf":
		if blocks.get_prop(st, "half") == "upper":
			return below > 0 and bname == "small_dripleaf"
		return below > 0 and (Tags.has_block("supports_small_dripleaf", bname) or (blocks.get_prop(st, "waterlogged") == "true" and Tags.has_block("supports_big_dripleaf", bname)))
	var ok_below := below > 0 and (bname == "big_dripleaf_stem" or (name == "big_dripleaf" and bname == "big_dripleaf") or Tags.has_block("supports_big_dripleaf", bname))
	if not ok_below or name == "big_dripleaf":
		return ok_below
	var above: int = world.state_at(p.x, p.y + 1, p.z)
	if above < 0:
		return true
	var an := blocks.name_of(maxi(above, 0))
	return above > 0 and (an == "big_dripleaf_stem" or an == "big_dripleaf")


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


## Per-state fluid tables (built once per registry; the flow code is hot): canHoldAnyFluid / canHoldSpecificFluid
## classes and the collision faces for canPassThroughWall. Read through string property lookups and face-mask
## dictionaries a scheduled fluid update cost ~370 us (a flow step of ~40 updates ~15 ms, sliced over the tick's frames
## and spilling into the next tick).
const FK_HOLD := 1     # FlowingFluid.canHoldAnyFluid
const FK_TAKES := 2    # a dry waterloggable block: takes a water source (SimpleWaterloggedBlock.canPlaceLiquid)
const FK_FULL := 4     # a liquid container that takes nothing (waterlogged, double slab, kelp / seagrass / bubble column)
const FK_W := 8        # its fluid is water (water block, waterlogged, kelp / seagrass / bubble column)
const FK_L := 16       # lava block
const FK_SRC := 32     # its fluid is a source (level 0, or waterlogged)
static var _fk := PackedByteArray()
static var _famt := PackedByteArray()      # fluid amount (FluidState.getAmount): 8 source / falling, 8 - level flowing
static var _ffaces := PackedInt32Array()   # bits 0-5: face fully covered by the collision shape, 6-11: face touched at all
static var _flowst := PackedInt32Array()   # FlowingFluid.getFlowing states: (lava ? 9 : 0) + (falling ? 8 : amount - 1)
static var _fsolid := PackedByteArray()    # BlockState.isSolid (source conversion over solid ground)


static func _fluid_tables() -> void:
	var b := Res.blocks
	if _fk.size() == b.total_states:
		return
	var n := b.total_states
	_fk.resize(n)
	_famt.resize(n)
	_ffaces.resize(n)
	_fsolid.resize(n)
	_flowst.resize(18)
	for fi in 18:
		var lv: int = 8 if fi % 9 == 8 else 8 - (fi % 9 + 1)
		_flowst[fi] = b.with_prop(b.LAVA if fi >= 9 else b.WATER, "level", str(lv))
	var by_shape := {}
	for st in n:
		var k := 0
		var fl := b.st_flags[st]
		_fsolid[st] = 1 if (fl & BlockRegistry.F_SOLID) != 0 else 0
		_famt[st] = 0
		if st > 0 and (fl & BlockRegistry.F_LIQUID) != 0:
			var lv2: int = b.st_level[st]
			_famt[st] = 8 if lv2 == 0 or lv2 >= 8 else 8 - lv2
			k |= (FK_L if fl & BlockRegistry.F_LAVA else FK_W) | (FK_SRC if lv2 == 0 else 0)
		elif st > 0 and (fl & BlockRegistry.F_WATERLOGGED) != 0:
			_famt[st] = 8
			k |= FK_W | FK_SRC
		if st == 0 or (fl & BlockRegistry.F_AIR) != 0:
			k |= FK_HOLD
		elif b.has_prop(st, "waterlogged"):
			k |= FK_HOLD   # LiquidBlockContainer
			var dbl := b.name_of(st).ends_with("_slab") and b.get_prop(st, "type") == "double"   # (SlabBlock.canPlaceLiquid)
			k |= FK_TAKES if b.get_prop(st, "waterlogged") == "false" and not dbl else FK_FULL
		elif fl & BlockRegistry.F_WATERLOGGED:
			# kelp / seagrass (KelpBlock, SeagrassBlock.canPlaceLiquid: false - lava doesn't flow into them); bubble columns
			# hold no fluid at all (canHoldAnyFluid)
			k |= FK_FULL | (0 if b.name_of(st) == "bubble_column" else FK_HOLD)
		elif fl & BlockRegistry.F_LIQUID:
			k |= FK_HOLD
		else:
			# not BlockState.blocksMotion = isSolid (the collision-bounds rule, F_SOLID), never for cobwebs / bamboo
			# saplings. The wiki's fluid notes override it: banners and pressure plates keep water and lava out (Banner:
			# "water and lava flow around banners"; Pressure Plate: "cannot be broken by water and lava"), snow layers and
			# end rods wash away (Water: plants, snow, torches, carpets, redstone dust / components, cobweb, end rods,
			# heads and flower pots); every other solid-or-not answer is the bounds rule (the wiki lists no more)
			var nm := b.name_of(st)
			var solid := (fl & BlockRegistry.F_SOLID) != 0
			if nm == "cobweb" or nm == "bamboo_sapling" or nm == "snow" or nm == "end_rod":
				solid = false
			elif nm.ends_with("_banner") or nm.ends_with("pressure_plate"):
				solid = true
			if not solid and not (nm.ends_with("_door") or nm == "ladder" or nm.ends_with("_sign") or nm == "sugar_cane" or nm == "nether_portal" or nm == "end_portal" or nm == "end_gateway" or nm == "structure_void"):
				k |= FK_HOLD
		_fk[st] = k
		var si: int = b.st_shape[st]
		var f = by_shape.get(si)
		if f == null:
			var bits := 0
			for face in 6:
				var m := _face_mask(st, face)
				if m[0] == -1 and m[1] == -1 and m[2] == -1 and m[3] == -1:
					bits |= 1 << face
				if m[0] != 0 or m[1] != 0 or m[2] != 0 or m[3] != 0:
					bits |= 1 << (6 + face)
			f = bits
			by_shape[si] = bits
		_ffaces[st] = 0 if st == 0 else int(f)


## FlowingFluid.canHoldAnyFluid: liquid containers (waterloggable blocks) and non-motion-blocking (not solid) blocks
## except doors, signs, ladders, sugar cane, bubble columns, portals, gateways, structure voids - a flow into one of
## those destroys it (water drops it, lava fizzes: _spread_to).
static func _can_hold(st: int, _lava: bool) -> bool:
	if _fk.is_empty():
		_fluid_tables()
	return st >= 0 and (_fk[st] & FK_HOLD) != 0


## FlowingFluid.canHoldSpecificFluid for the fluid about to go there: a waterloggable block takes only a water SOURCE
## (SimpleWaterloggedBlock.canPlaceLiquid: fluid == Fluids.WATER) - flowing water passes stairs / fences / slabs by.
static func _can_hold_specific(st: int, lava: bool, source: bool) -> bool:
	if st < 0:
		return false
	var k := _fk[st]
	if k & FK_TAKES:
		return source and not lava
	if k & FK_FULL:
		return false
	return (k & FK_HOLD) != 0


## Faces: 0 down, 1 up, 2 north, 3 south, 4 west, 5 east. HDIRS order N, E, S, W -> faces 2, 5, 3, 4; the opposite
## horizontal index is k ^ 2.
const HFACE := [2, 5, 3, 4]
static var _fmask: Dictionary = {}   # collision shape index * 6 + face -> PackedInt64Array(4): 16 x 16 face coverage
static var _no_mask := PackedInt64Array([0, 0, 0, 0])


## The 1/16 cells of one face plane of a state's collision shape covered by its boxes touching that face
## (VoxelShape.getFaceShape), as 4 x 64 bits (4 rows of 16 per word).
static func _face_mask(st: int, face: int) -> PackedInt64Array:
	if st <= 0:
		return _no_mask
	var si: int = Res.blocks.st_shape[st]
	var key := si * 6 + face
	var m = _fmask.get(key)
	if m != null:
		return m
	var out := PackedInt64Array([0, 0, 0, 0])
	var boxes: PackedFloat32Array = Res.blocks.shapes[si]
	var ai: int = [1, 2, 0][face >> 1]   # component of the face normal (y, z, x)
	var ui: int = [0, 0, 2][face >> 1]
	var vi: int = [2, 1, 1][face >> 1]
	var pos := (face & 1) == 1
	for i in range(0, boxes.size(), 6):
		var mn := Vector3(boxes[i], boxes[i + 1], boxes[i + 2])
		var mx := Vector3(boxes[i + 3], boxes[i + 4], boxes[i + 5])
		if (pos and mx[ai] < 1.0 - 1e-5) or (not pos and mn[ai] > 1e-5):
			continue
		var u0 := clampi(int(floor(mn[ui] * 16.0 + 0.001)), 0, 16)
		var u1 := clampi(int(ceil(mx[ui] * 16.0 - 0.001)), 0, 16)
		var v0 := clampi(int(floor(mn[vi] * 16.0 + 0.001)), 0, 16)
		var v1 := clampi(int(ceil(mx[vi] * 16.0 - 0.001)), 0, 16)
		if u1 <= u0 or v1 <= v0:
			continue
		var row := ((1 << (u1 - u0)) - 1) << u0
		for v in range(v0, v1):
			out[v >> 2] |= row << ((v & 3) * 16)
	_fmask[key] = out
	return out


## FlowingFluid.canPassThroughWall: fluid crosses from `src` to `dst` (face = side of src toward dst) unless the two
## collision faces together cover the whole shared face (Shapes.mergedFaceOccludes; a full cube on either side always
## does). Waterlogged stairs / slabs keep water in on their solid sides.
static func _pass_wall(src: int, dst: int, face: int) -> bool:
	var fa: int = _ffaces[src] if src > 0 else 0
	var fb: int = _ffaces[dst] if dst > 0 else 0
	var of := face ^ 1
	if ((fa >> face) & 1) != 0 or ((fb >> of) & 1) != 0:
		return false   # a full face on either side
	if ((fa >> (6 + face)) & 1) == 0 or ((fb >> (6 + of)) & 1) == 0:
		return true    # at most one side has a (partial) face there
	var a := _face_mask(src, face)
	var b := _face_mask(dst, of)
	for i in 4:
		if (a[i] | b[i]) != -1:
			return true
	return false


static func _flowing_state(lava: bool, amount: int, falling: bool) -> int:
	if _flowst.is_empty():
		_fluid_tables()
	return _flowst[(9 if lava else 0) + (8 if falling else amount - 1)]


static func _drop_off(world, lava: bool) -> int:
	return (1 if lava_delay(world) == 10 else 2) if lava else 1


## FlowingFluid.getNewLiquid: the fluid state position p (holding pst) should hold (0 = empty).
static func _new_liquid(world, p: Vector3i, lava: bool, pst: int = -2, _cached := false) -> int:
	_gbegin(world, p, lava)
	if pst == -2:
		pst = _gget(0, 0, 0)
	return _gnew(0, 0, pst)


# ---- FlowingFluid.SpreadContext: the states around the spreading cell, read once per spread into a flat grid
# (dx, dz within SR of it, dy -1 / 0 / +1) straight from the chunk sections; holes and slope distances cached the same
# way (Java memoises states and holes per spread, keyed by relative position). Packed arrays filled per spread: no
# Dictionary / Vector3i per visited cell (the slope search visits up to ~160 cells per spread).
const SR := 5            # neighbour (1) + slope find distance (4)
const SW := 11
const SL := 121          # SW * SW
const HDX := [0, 1, 0, -1]
const HDZ := [-1, 0, 1, 0]
static var _g := PackedInt32Array()    # 3 layers of SW x SW: state, -2 = not read yet
static var _gh := PackedByteArray()    # holes (layer dy 0): 0 unknown, 1 no, 2 yes
static var _gm := PackedInt32Array()   # slope memo: ((cell * 4 + came-from side) * 5 + depth) -> distance + 1, 0 unknown
static var _gm_stale := true   # (the memo is only used by the reference DFS: cleared on its first call of a spread)
static var _gp := Vector3i.ZERO
static var _gw = null
static var _gcm: ChunkManager = null
static var _gck := 1 << 62
static var _gch: Chunk = null
static var _glava := false
static var _gfind := 4
static var _gdrop := 1
static var _gconv := true


static func _gbegin(world, p: Vector3i, lava: bool) -> void:
	if _fk.is_empty():
		_fluid_tables()
	if _g.size() != 3 * SL:
		_g.resize(3 * SL)
		_gh.resize(SL)
		_gm.resize(SL * 20)
	_g.fill(-2)
	_gh.fill(0)
	_gm_stale = true
	_gp = p
	_gw = world
	var cmv = world.get("cm")
	_gcm = cmv if cmv is ChunkManager else null
	_gck = 1 << 62
	_gch = null
	_glava = lava
	var fast := lava_delay(world) == 10
	_gfind = (4 if fast else 2) if lava else 4
	_gdrop = (1 if fast else 2) if lava else 1
	_gconv = bool(world.gamerule("lavaSourceConversion", false) if lava else world.gamerule("waterSourceConversion", true))


## State at (dx, dy, dz) from the spread origin (WorldManager.state_at: -1 where the chunk isn't loaded).
static func _gget(dx: int, dy: int, dz: int) -> int:
	var i := (dy + 1) * SL + (dz + SR) * SW + dx + SR
	var v := _g[i]
	if v != -2:
		return v
	var x := _gp.x + dx
	var y := _gp.y + dy
	var z := _gp.z + dz
	if _gcm != null:
		var ck := ((x >> 4) << 32) | ((z >> 4) & 0xFFFFFFFF)
		if ck != _gck:
			_gck = ck
			_gch = _gcm.chunks.get(ck)
			if _gch != null and _gch.state < Chunk.DATA_READY:
				_gch = null
		if _gch == null:
			v = -1
		elif y < Coords.MIN_Y or y >= Coords.MAX_Y:
			v = 0
		else:
			var sec: Chunk.Section = _gch.sections[(y - Coords.MIN_Y) >> 4]
			if sec.pal.size() == 1:
				v = sec.pal[0]
			else:
				var si := ((y & 15) << 8) | ((z & 15) << 4) | (x & 15)
				v = sec.pal[sec.wide[si]] if sec.wide.size() > 0 else sec.pal[sec.idx[si]]
	else:
		v = _gw.state_at(x, y, z)
	_g[i] = v
	return v


## getNewLiquid for the cell (dx, 0, dz) holding pst.
static func _gnew(dx: int, dz: int, pst: int) -> int:
	var tb := FK_L if _glava else FK_W
	var maxa := 0
	var sources := 0
	for k in 4:
		var ns := _gget(dx + HDX[k], 0, dz + HDZ[k])
		if ns > 0 and (_fk[ns] & tb) != 0 and _pass_wall(pst, ns, HFACE[k]):
			if _fk[ns] & FK_SRC:
				sources += 1
			maxa = maxi(maxa, _famt[ns])
	if sources >= 2 and _gconv:
		var below := _gget(dx, -1, dz)
		if below > 0 and (_fsolid[below] != 0 or (_fk[below] & (tb | FK_SRC)) == (tb | FK_SRC)):
			return Res.blocks.LAVA if _glava else Res.blocks.WATER
	var above := _gget(dx, 1, dz)
	if above > 0 and (_fk[above] & tb) != 0 and _pass_wall(pst, above, 1):
		return _flowst[(9 if _glava else 0) + 8]
	var k2 := maxa - _gdrop
	return 0 if k2 <= 0 else _flowst[(9 if _glava else 0) + k2 - 1]


## SpreadContext.isHole / FlowingFluid.isWaterHole for the cell (dx, 0, dz) holding qst: the fluid can go down there.
static func _ghole(dx: int, dz: int, qst: int) -> bool:
	var hi := (dz + SR) * SW + dx + SR
	var h := _gh[hi]
	if h != 0:
		return h == 2
	var b := _g[hi]   # (layer dy -1)
	if b == -2:
		b = _gget(dx, -1, dz)
	var r := false
	if b >= 0 and ((_ffaces[qst] | _ffaces[b]) == 0 or _pass_wall(qst, b, 0)):
		var kb := _fk[b]
		r = (kb & (FK_L if _glava else FK_W)) != 0 or (kb & (FK_HOLD | FK_TAKES | FK_FULL)) == FK_HOLD
	_gh[hi] = 2 if r else 1
	return r


## FlowingFluid.getSlopeDistance from the cell (dx, 0, dz) holding pst, reached from side from_k at depth `depth`:
## steps to the nearest hole (up to the slope find distance: water 4, lava 2 / 4 where lava is fast), 1000 = none.
## canPassThrough includes canHoldSpecificFluid of the flowing fluid (waterloggable blocks take only sources, so they
## are walls for the search). Memoised by (cell, side, depth): pure within one spread. (Grid reads, hole and wall
## checks inlined on their fast paths: it runs for up to ~120 cells per side.)
const HDC := [-SW, 1, SW, -1]   # cell index step of HDIRS in the grid
static func _gslope(dx: int, dz: int, pst: int, depth: int, from_k: int) -> int:
	if _gm_stale:
		_gm.fill(0)
		_gm_stale = false
	var cell := (dz + SR) * SW + dx + SR
	var mi := (cell * 4 + from_k) * 5 + depth
	var mv := _gm[mi]
	if mv != 0:
		return mv - 1
	var best := 1000
	var sb := (FK_L if _glava else FK_W) | FK_SRC
	var fa := _ffaces[pst]
	for k in 4:
		if k == from_k:
			continue
		var nc: int = cell + HDC[k]
		var ns := _g[SL + nc]
		if ns == -2:
			ns = _gget(dx + HDX[k], 0, dz + HDZ[k])
		if ns < 0:
			continue
		var kk := _fk[ns]
		if (kk & sb) == sb or (kk & (FK_HOLD | FK_TAKES | FK_FULL)) != FK_HOLD:
			continue
		if (fa | _ffaces[ns]) != 0 and not _pass_wall(pst, ns, HFACE[k]):
			continue
		var h := _gh[nc]
		if h == 0:
			h = 2 if _ghole(dx + HDX[k], dz + HDZ[k], ns) else 1
		if h == 2:
			best = depth
			break
		if depth < _gfind:
			best = mini(best, _gslope(dx + HDX[k], dz + HDZ[k], ns, depth + 1, k ^ 2))
	_gm[mi] = best + 1
	return best


## getSlopeDistance for the four sides of the spread origin at once (_gsl[k], 1000 = no hole within the slope find
## distance), equal to the DFS above (kept as the reference: tests compare the two on random terrain). The DFS's
## minimum over non-backtracking walks of <= find steps is the shortest path over passable cells (a shortest path
## never backtracks), so one breadth-first pass outward from the holes (cells within find + 1 of the origin, never
## through the origin) gives every side's distance; walks through the origin itself (possible only when it is a
## flowing cell, reached at step 3 around a corner) are checked apart. The DFS visited up to ~120 cells per side:
## ~85 % of a flat-floor flow update.
static var _gsl := PackedInt32Array([1000, 1000, 1000, 1000])
static var _gcells := PackedInt32Array()   # grid cells at distance 1..SR from the origin, nearest first
static var _gcd := PackedByteArray()       # distance of each grid cell from the origin
static var _gnb := PackedInt32Array()      # cell * 4 + side -> neighbour cell, -1 outside the distance-SR diamond
static var _gd := PackedByteArray()        # steps from each cell to the nearest hole (255 unknown)
static var _gpass := PackedByteArray()     # 1: canPassThrough(flowing) cell
static var _gq := PackedInt32Array()


static func _side_slopes(st: int) -> void:
	if _gcells.is_empty():
		_gcd.resize(SL)
		_gnb.resize(SL * 4)
		_gd.resize(SL)
		_gpass.resize(SL)
		_gq.resize(SL)
		for d in range(1, SR + 1):
			for dz in range(-SR, SR + 1):
				for dx in range(-SR, SR + 1):
					if absi(dx) + absi(dz) == d:
						_gcells.append((dz + SR) * SW + dx + SR)
		for c in SL:
			var cx := c % SW - SR
			var cz := c / SW - SR
			_gcd[c] = absi(cx) + absi(cz)
			for k in 4:
				var nx: int = cx + HDX[k]
				var nz: int = cz + HDZ[k]
				_gnb[c * 4 + k] = (nz + SR) * SW + nx + SR if absi(nx) + absi(nz) <= SR else -1
	var find := _gfind
	var sb := (FK_L if _glava else FK_W) | FK_SRC
	var origin := SR * SW + SR
	_gd.fill(255)
	_gpass.fill(0)
	# passable cells and holes within find + 1 of the origin
	var qn := 0
	for c in _gcells:
		if _gcd[c] > find + 1:
			break
		var s := _g[SL + c]
		if s == -2:
			s = _gget(c % SW - SR, 0, c / SW - SR)
		if s < 0:
			continue
		var kk := _fk[s]
		if (kk & sb) == sb or (kk & (FK_HOLD | FK_TAKES | FK_FULL)) != FK_HOLD:
			continue
		_gpass[c] = 1
		if _ghole(c % SW - SR, c / SW - SR, s):
			_gd[c] = 0
			_gq[qn] = c
			qn += 1
	var opass := (_fk[st] & sb) != sb and (_fk[st] & (FK_HOLD | FK_TAKES | FK_FULL)) == FK_HOLD
	var ohole := opass and find >= 3 and _ghole(0, 0, st)
	if qn == 0 and not ohole:
		_gsl.fill(1000)
		return
	# breadth-first outward from the holes, at most find - 1 steps (a side adds its own step)
	var qi := 0
	while qi < qn:
		var c := _gq[qi]
		qi += 1
		var dc := _gd[c]
		if dc >= find - 1:
			continue
		var sc := _g[SL + c]
		for k in 4:
			var a := _gnb[c * 4 + k]
			if a < 0 or a == origin or _gpass[a] == 0 or _gd[a] != 255:
				continue
			var sa := _g[SL + a]
			if (_ffaces[sa] | _ffaces[sc]) != 0 and not _pass_wall(sc, sa, HFACE[k]):
				continue
			_gd[a] = dc + 1
			_gq[qn] = a
			qn += 1
	for k in 4:
		var q := _gnb[origin * 4 + k]
		var sq := _g[SL + q]
		var best := 1000
		if sq >= 0:
			for k2 in 4:
				if k2 == (k ^ 2):
					continue   # (not straight back to the origin)
				var b := _gnb[q * 4 + k2]
				if b < 0 or _gpass[b] == 0 or _gd[b] == 255 or _gd[b] + 1 >= best:
					continue
				var sbb := _g[SL + b]
				if (_ffaces[sq] | _ffaces[sbb]) != 0 and not _pass_wall(sq, sbb, HFACE[k2]):
					continue
				best = _gd[b] + 1
			# walks through a flowing origin: q -> q+s -> origin+s -> origin (step 3; a hole there), then one more step
			if opass and find >= 3 and best > 3:
				for s in [(k + 1) & 3, (k + 3) & 3]:
					var a2 := _gnb[q * 4 + s]
					var b2 := _gnb[origin * 4 + s]
					if a2 < 0 or b2 < 0 or _gpass[a2] == 0 or _gpass[b2] == 0:
						continue
					var sa2 := _g[SL + a2]
					var sb2 := _g[SL + b2]
					if not _pass_wall(sq, sa2, HFACE[s]) or not _pass_wall(sa2, sb2, HFACE[k ^ 2]) or not _pass_wall(sb2, st, HFACE[s ^ 2]):
						continue
					if ohole:
						best = 3
						break
					if find >= 4:
						for k3 in 4:
							if k3 == s or k3 == k:
								continue
							var h3 := _gnb[origin * 4 + k3]
							if _gd[h3] == 0 and _pass_wall(st, _g[SL + h3], HFACE[k3]):
								best = 4
		_gsl[k] = best if best <= find else 1000


## FluidState.canBeReplacedWith: what holds `st` now taking the spreading fluid (down: from above). Air / no fluid:
## always; water: only by lava from above (WaterFluid); lava: by water when at least 4/9 high (LavaFluid).
static func _replaceable_by(st: int, lava: bool, down: bool) -> bool:
	var a := _fluid_amount(st)
	if a == 0:
		return true
	if _same_fluid(st, true):
		return not lava and a >= 4
	return down and lava


## Java LevelEvent 1501 (LAVA_FIZZ): extinguish sound (0.5, 2.6 +- 0.8) and 8 large smoke particles 1.2 above.
static func _fizz(world, p: Vector3i) -> void:
	Audio.play("block.lava.extinguish", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.5, 2.6 + (_rt_rng.randf() - _rt_rng.randf()) * 0.8)
	for i in 8:
		Particles.emit("large_smoke", Vector3(p) + Vector3(_rt_rng.randf(), 1.2, _rt_rng.randf()))


## LiquidBlock.shouldSpreadLiquid on lava: water above or beside (water / waterlogged blocks) turns it to obsidian
## (source) or cobblestone; over soul soil, blue ice beside turns it to basalt. Java runs this when the lava is placed
## and whenever a neighbour changes - at once, not on the lava's 30-tick flow tick. True when the lava was converted.
static func lava_react(world, p: Vector3i, st: int) -> bool:
	var soul := false
	var bs: int = world.state_at(p.x, p.y - 1, p.z)
	if bs > 0 and Res.blocks.name_of(bs) == "soul_soil":
		soul = true
	for d in [Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]:
		var q: Vector3i = p + d
		var ns: int = world.state_at(q.x, q.y, q.z)
		if ns <= 0:
			continue
		if _same_fluid(ns, false):
			world.set_block(p.x, p.y, p.z, Res.blocks.default_state("obsidian" if Res.blocks.st_level[st] == 0 else "cobblestone"))
			_fizz(world, p)
			return true
		if soul and Res.blocks.name_of(ns) == "blue_ice":
			world.set_block(p.x, p.y, p.z, Res.blocks.default_state("basalt"))
			_fizz(world, p)
			return true
	return false


## Java Level.setBlock neighbour updates for fluids (LiquidBlock.onPlace / neighborChanged / updateShape): the block
## at p and its 6 neighbours that hold a fluid get their fluid tick (water 5, lava 30 / 10); lava touching water reacts
## right away. Called by WorldManager.set_block for every notified change.
static var _react_q: Array = []
static var _reacting := false
const _NB7 := [Vector3i.ZERO, Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0)]
static var _sponge_q: Array = []   # [position, placed] of sponges / wet sponges to update (Sponges.on_update)
static var _sponging := false
static var _sp_dry := -2
static var _sp_wet := -2


static func fluids_changed(world, p: Vector3i) -> void:
	if _sp_dry == -2:
		_sp_dry = Res.blocks.block_id("sponge")
		_sp_wet = Res.blocks.block_id("wet_sponge")
	for d in _NB7:
		var q: Vector3i = p + d
		var st: int = world.state_at(q.x, q.y, q.z)
		if st <= 0:
			continue
		var fl := Res.blocks.st_flags[st]
		if fl & BlockRegistry.F_LIQUID:
			if fl & BlockRegistry.F_LAVA:
				_react_q.append(q)
			else:
				schedule(world, q, 5)
		elif fl & BlockRegistry.F_WATERLOGGED:
			schedule(world, q, 5)
		else:
			var sb := Res.blocks.st_block[st]
			if sb == _sp_dry or (sb == _sp_wet and d == Vector3i.ZERO):
				_sponge_q.append([q, d == Vector3i.ZERO])   # SpongeBlock.onPlace / neighborChanged, WetSpongeBlock.onPlace
		if fl & BlockRegistry.F_GRAVITY:
			# Java FallingBlock.onPlace / updateShape: any change next to (or of) a gravity block schedules its fall check
			# in 2 ticks - a falling block's removal reaches the one above, so columns and floating clumps come down
			schedule(world, q, 2)
	if not _sponge_q.is_empty() and not _sponging:
		_sponging = true   # (absorbing changes neighbours of other sponges: queued, run here in order)
		var si := 0
		while si < _sponge_q.size():
			var e: Array = _sponge_q[si]
			si += 1
			var sq: Vector3i = e[0]
			var sst: int = world.state_at(sq.x, sq.y, sq.z)
			if sst > 0:
				Sponges.on_update(world, sq, sst, e[1])
		_sponge_q.clear()
		_sponging = false
	if _reacting or _react_q.is_empty():
		return
	# conversions update their own neighbours (a lava lake under poured water converts cell by cell): a queue, not
	# recursion (Java CollectingNeighborUpdater)
	_reacting = true
	var i := 0
	while i < _react_q.size():
		var r: Vector3i = _react_q[i]
		i += 1
		var rs: int = world.state_at(r.x, r.y, r.z)
		if rs > 0 and (Res.blocks.st_flags[rs] & (BlockRegistry.F_LIQUID | BlockRegistry.F_LAVA)) == (BlockRegistry.F_LIQUID | BlockRegistry.F_LAVA):
			if not lava_react(world, r, rs):
				schedule(world, r, lava_delay(world))
	_react_q.clear()
	_reacting = false


static func _fluid(world, p: Vector3i, st: int) -> void:
	var blocks := Res.blocks
	var lava := (blocks.st_flags[st] & BlockRegistry.F_LAVA) != 0
	if lava and lava_react(world, p, st):
		return
	if blocks.st_level[st] != 0:
		# FlowingFluid.tick: a flowing state recomputes itself (empty -> air; changed -> set and ticks again)
		var nl := _new_liquid(world, p, lava, st)
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


static func _source_neighbors(world, p: Vector3i, lava: bool) -> int:
	var n := 0
	for d in HDIRS:
		var q: Vector3i = p + d
		if _is_source_this(world.state_at(q.x, q.y, q.z), lava):
			n += 1
	return n


## FlowingFluid.spread: down first (canMaybePassThrough, canBeReplacedWith, canHoldSpecificFluid; LavaFluid.spreadTo
## turns water below into stone), then sideways (sources, or flows not standing over a hole).
static func _spread_java(world, p: Vector3i, st: int, lava: bool) -> void:
	_gbegin(world, p, lava)
	var below := _gget(0, -1, 0)
	var sb := (FK_L if lava else FK_W) | FK_SRC
	if below >= 0 and (_fk[below] & sb) != sb and (_fk[below] & FK_HOLD) != 0 and _pass_wall(st, below, 0):
		var below_p := p + Vector3i(0, -1, 0)
		var nb := _new_liquid(world, below_p, lava, below)
		if nb != 0 and _replaceable_by(below, lava, true) and _can_hold_specific(below, lava, (_fk[nb] & FK_SRC) != 0):
			if lava and _fluid_amount(below) > 0:
				# LavaFluid.spreadTo(DOWN) into water: a water block becomes stone, a waterlogged block only fizzes
				if Res.blocks.st_flags[below] & BlockRegistry.F_LIQUID:
					world.set_block(below_p.x, below_p.y, below_p.z, Res.blocks.default_state("stone"))
				_fizz(world, below_p)
			else:
				_spread_to(world, below_p, below, nb, lava)
			if _source_neighbors(world, p, lava) >= 3:
				_spread_sides(world, p, st, lava)
			return
	# (nothing was written: `below` is current) isWaterHole(p)
	var hole := below >= 0 and _pass_wall(st, below, 0) and ((_fk[below] & (FK_L if lava else FK_W)) != 0 or (_fk[below] & (FK_HOLD | FK_TAKES | FK_FULL)) == FK_HOLD)
	if (_fk[st] & sb) == sb or not hole:
		_spread_sides(world, p, st, lava)


## FlowingFluid.spreadToSides / getSpread: the neighbours at the smallest slope distance (0 = a hole next to it) that
## can take the new flow (all reads through the spread's SpreadContext grid, writes after).
static func _spread_sides(world, p: Vector3i, st: int, lava: bool) -> void:
	var i := _fluid_amount(st) - _drop_off(world, lava)
	if _falling(st):
		i = 7
	if i <= 0:
		return
	_gbegin(world, p, lava)
	var sb := (FK_L if lava else FK_W) | FK_SRC
	var best := 1000
	var tn := 0
	var tk := PackedInt32Array([0, 0, 0, 0])
	var ts := PackedInt32Array([0, 0, 0, 0])
	var tf := PackedInt32Array([0, 0, 0, 0])
	# the sides that can take the flow, with their new liquid; slope distances only matter between two or more of them
	var nfs := PackedInt32Array([-1, -1, -1, -1])
	var ne := 0
	var nh := 0
	for k in 4:
		var dx: int = HDX[k]
		var dz: int = HDZ[k]
		var ns := _gget(dx, 0, dz)
		if ns < 0:
			continue
		var kk := _fk[ns]
		if (kk & sb) == sb or (kk & FK_HOLD) == 0 or not _pass_wall(st, ns, HFACE[k]):
			continue
		var nf := _gnew(dx, dz, ns)
		if not _can_hold_specific(ns, lava, nf > 0 and (_fk[nf] & FK_SRC) != 0):
			continue
		nfs[k] = nf
		ne += 1
		if _ghole(dx, dz, ns):
			nh += 1
	# (one side alone, or a hole next to the origin - holes win at distance 0: the other sides' distances don't matter)
	var slopes := ne >= 2 and nh == 0
	if slopes:
		_side_slopes(st)
	for k in 4:
		var nf: int = nfs[k]
		if nf < 0:
			continue
		var dx: int = HDX[k]
		var dz: int = HDZ[k]
		var ns := _gget(dx, 0, dz)
		var j := 0 if _ghole(dx, dz, ns) else (_gsl[k] if slopes else 1000)
		if j < best:
			tn = 0
		if j <= best:
			if nf != 0 and _replaceable_by(ns, lava, false):
				tk[tn] = k
				ts[tn] = ns
				tf[tn] = nf
				tn += 1
			best = j
	for t in tn:
		_spread_to(world, p + HDIRS[tk[t]], ts[t], tf[t], lava)


## FlowingFluid.spreadTo: waterloggable blocks take water as waterlogging; others are destroyed (drops; lava fizzes)
## and replaced; the new fluid's tick comes from the neighbour update (LiquidBlock.onPlace via set_block).
static func _spread_to(world, q: Vector3i, cur: int, nf: int, lava: bool) -> void:
	var b := Res.blocks
	if cur > 0 and b.has_prop(cur, "waterlogged"):
		if not lava:
			Interaction.waterlog(world, q, cur)   # LiquidBlockContainer.placeLiquid (lit campfires / candles go out)
		return
	if cur > 0 and (b.st_flags[cur] & BlockRegistry.F_LIQUID) == 0:
		if lava:
			_fizz(world, q)
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
	# the first slice is this frame's share of the frames until the next tick (a fixed 220 chunks was 1-2 ms on x86)
	var fpt := 0.05 / maxf(float(world._last_delta), 0.0005)
	var n0 := clampi(ceili(float(_rts_lst.size()) / maxf(1.0, fpt - 2.0)), 60, RT_SLICE)
	_rt_sample_slice(n0 if Native.inst.has_method("rt_sample_range") else 1 << 30)


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
	_rtb_col = 0
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
static var _rtb_col := 0   # chunk column inside the current list row (resumable rebuild)


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
			# resumable within the row: chunks needing a rebuild cost up to ~0.5 ms each on x86 (a whole row in one go was
			# a 1.4-3.7 ms frame there)
			while _rtb_col <= 2 * sim:
				var cx := k.x - sim + _rtb_col
				_rtb_col += 1
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
				if rows < (1 << 20) and Time.get_ticks_usec() >= t_end:
					return
			_rtb_col = 0
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
	if not _gen_wait.is_empty():
		_gen_wake(cx, cz)
	var sim := int(Settings.get_v("simulation_distance"))
	if maxi(absi(cx - _rtl_key.x), absi(cz - _rtl_key.y)) <= sim:
		rtl_dirty = true


## Random-tick hits of the current pass are handled spread over the frames until the next game tick (step_hits), so a
## tick's handlers never land in one frame; any rest is finished before the next pass samples (one pass per tick).
static var _rt_hits := PackedInt32Array()
static var _rt_chs: Array = []
static var _rt_hi := 0


static func step_hits(world, frames_left: int) -> void:
	if _release_pending:
		_release_pending = false
		if world.get("cm") is ChunkManager:
			world.cm.release_held()
	var drem := due_count()
	if drem > 0:
		# a share of the collected updates per frame (spread over the frames until the next tick), at most ~2 ms
		_run_due(world, maxi(2, ceili(float(drem) / maxi(1, frames_left - 1))), 2000)
	if not _gen_q.is_empty():
		_gen_step(world)
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
	# per-frame cap: 10 % of the frame time (0.15 .. 1.5 ms), raised to what this frame's share of the pass needs at
	# the measured cost per handler (otherwise a slow build fell behind and the next pass finished the rest at once:
	# 5-6 ms frames on x86)
	var need := ceili(float(rem) / maxi(1, frames_left))
	var cap := clampi(int(float(world._last_delta) * 100000.0), 150, STEP_BUDGET_US)
	cap = clampi(maxi(cap, int(_hit_us_avg * float(need) * 1.25)), 150, 4000)
	_rt_process(world, _rt_hi + need * 4, t + cap)
	var done := (_rt_hi - n0) / 4
	if done > 0:
		_hit_us_avg = lerpf(_hit_us_avg, float(Time.get_ticks_usec() - t) / float(done), 0.2)
	last_random_us += Time.get_ticks_usec() - t
	if tr and Time.get_ticks_usec() - t > 300:
		world.frame_tparts["rt:handlers (%d)" % ((_rt_hi - n0) / 4)] = Time.get_ticks_usec() - t


static var _hit_us_avg := 20.0   # measured cost per random-tick handler (us)
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
	return Bonemeal.apply(world, p, st)   # (targets, chances, particles + sound: Bonemeal)

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
	# wiki Fire, flammable blocks table: [ignite (encouragement), burn (flammability)]
	for w in ["oak", "spruce", "birch", "jungle", "acacia", "cherry", "dark_oak", "pale_oak", "mangrove", "bamboo", "poplar"]:
		for suf in ["_planks", "_slab", "_fence_gate", "_fence", "_stairs"]:
			put.call(w + suf, 5, 20)
	for nm in ["bamboo_mosaic", "bamboo_mosaic_slab", "bamboo_mosaic_stairs", "mangrove_roots", "composter", "beehive"]:
		put.call(nm, 5, 20)
	for w2 in ["oak", "spruce", "birch", "jungle", "acacia", "cherry", "dark_oak", "pale_oak", "mangrove", "poplar"]:
		for pre in ["", "stripped_"]:
			put.call(pre + w2 + "_log", 5, 5)
			put.call(pre + w2 + "_wood", 5, 5)
	for nm2 in ["bamboo_block", "stripped_bamboo_block", "coal_block"]:
		put.call(nm2, 5, 5)
	for nm3 in Tags.blocks("#minecraft:leaves"):
		put.call(nm3, 30, 60)
	for wt in ["#minecraft:wool", "#minecraft:wool_slabs", "#minecraft:wool_stairs"]:   # wiki: wool (and slabs / stairs)
		for nm4 in Tags.blocks(wt):
			put.call(nm4, 30, 60)
	for nm5 in Tags.blocks("#minecraft:wool_carpets"):
		put.call(nm5, 60, 20)
	for nm6 in ["short_grass", "fern", "dead_bush", "sunflower", "lilac", "rose_bush", "peony", "tall_grass", "large_fern", "dandelion",
			"poppy", "blue_orchid", "allium", "azure_bluet", "red_tulip", "orange_tulip", "white_tulip", "pink_tulip", "oxeye_daisy",
			"cornflower", "lily_of_the_valley", "torchflower", "pitcher_plant", "wither_rose", "pink_petals", "wildflowers",
			"open_eyeblossom", "closed_eyeblossom", "sweet_berry_bush", "spore_blossom", "leaf_litter", "short_dry_grass",
			"tall_dry_grass", "bush", "firefly_bush", "cactus_flower", "golden_dandelion", "red_shrub", "big_dripleaf", "big_dripleaf_stem",
			"small_dripleaf"]:
		put.call(nm6, 60, 100)
	# (moss block / moss carpet / chiseled bookshelf: not flammable per the wiki - Moss Carpet "not flammable", infoboxes "No")
	for nm7 in [["bookshelf", 30, 20], ["lectern", 30, 20], ["bee_nest", 30, 20], ["tnt", 15, 100],
			["vine", 15, 100], ["hay_block", 60, 20], ["target", 15, 20], ["pale_moss_carpet", 5, 100],
			["dried_kelp_block", 30, 60], ["bamboo", 60, 60], ["scaffolding", 60, 60], ["azalea", 30, 60], ["flowering_azalea", 30, 60],
			["cave_vines", 15, 60], ["cave_vines_plant", 15, 60], ["hanging_roots", 30, 60], ["glow_lichen", 15, 100],
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
