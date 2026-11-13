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
		if fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED):
			schedule(world, q, 30 if fl & BlockRegistry.F_LAVA else 5)
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
		_spread_from(world, p, true, 1, false)
	if fl & BlockRegistry.F_GRAVITY and name != "scaffolding" and name != "pointed_dripstone":
		var below: int = world.state_at(p.x, p.y - 1, p.z)
		if below == 0 or (below > 0 and (blocks.st_flags[below] & (BlockRegistry.F_REPLACEABLE | BlockRegistry.F_LIQUID))):
			world.set_block(p.x, p.y, p.z, 0)
			world.entities.spawn_falling_block(p, st)
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


static func _fluid(world, p: Vector3i, st: int) -> void:
	var blocks := Res.blocks
	var lava := (blocks.st_flags[st] & BlockRegistry.F_LAVA) != 0
	var drop := 2 if lava else 1
	var lv := blocks.st_level[st]
	var is_source := lv == 0
	var src := blocks.LAVA if lava else blocks.WATER
	# lava/water interactions
	if lava:
		for d in [Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var q: Vector3i = p + d
			if _same_fluid(world.state_at(q.x, q.y, q.z), false):
				world.set_block(p.x, p.y, p.z, blocks.default_state("obsidian" if is_source else "cobblestone"))
				Audio.play("block.lava.extinguish", Vector3(p), "Blocks")
				return
	if not is_source:
		var above: int = world.state_at(p.x, p.y + 1, p.z)
		var best := 0
		var sources := 0
		if _same_fluid(above, lava):
			best = 8
		for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
			var q: Vector3i = p + d
			var ns: int = world.state_at(q.x, q.y, q.z)
			if _same_fluid(ns, lava):
				var a := _amount(ns) - drop
				if (Res.blocks.st_flags[ns] & BlockRegistry.F_LIQUID) and Res.blocks.st_level[ns] == 0:
					sources += 1
					a = 8 - drop
				elif Res.blocks.st_flags[ns] & BlockRegistry.F_WATERLOGGED:
					sources += 1
					a = 8 - drop
				best = maxi(best, a)
		var below: int = world.state_at(p.x, p.y - 1, p.z)
		if not lava and sources >= 2 and world.gamerule("waterSourceConversion", true) and (below > 0 and ((blocks.st_flags[below] & BlockRegistry.F_COLLIDE) or (_same_fluid(below, false) and blocks.st_level[below] == 0))):
			world.set_block(p.x, p.y, p.z, src)
			schedule_neighbors(world, p)
			return
		var new_state := 0
		if best >= 8 and _same_fluid(above, lava):
			new_state = blocks.with_prop(src, "level", "8")
		elif best > 0:
			new_state = blocks.with_prop(src, "level", str(8 - best))
		if new_state != st:
			world.set_block(p.x, p.y, p.z, new_state)
			schedule_neighbors(world, p)
			if new_state == 0:
				return
			st = new_state
	_spread_from(world, p, not lava, _amount(st), lava)


static func _spread_from(world, p: Vector3i, _water: bool, amount: int, lava: bool) -> void:
	var blocks := Res.blocks
	var drop := 2 if lava else 1
	var src := blocks.LAVA if lava else blocks.WATER
	var delay := 30 if lava else 5
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
