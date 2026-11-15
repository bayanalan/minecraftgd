## ChunkManager — streams chunks around the player through staged worker jobs:
## GENERATE(<=R+2) -> DECORATE(<=R+1, needs 3x3 generated) -> LIGHT(<=R, needs 3x3 decorated) -> MESH(<=R).
## Why: bounded, prioritised (distance + view direction), cancellable background work; main thread only
## commits results within a per-frame time budget (RenderingServer instances, no per-block nodes).
## Contract: update(player_pos, cam_forward) each frame; get_block/set_block world coords; is_ready(x,z).
## Invariants: worker jobs read COW snapshots / immutable neighbour data; stale results are discarded
## via per-chunk epochs; unload never drops unsaved edits (save_chunk callback first).
class_name ChunkManager
extends RefCounted

signal chunk_loaded(c: Chunk)
signal chunk_unloading(c: Chunk)

var blocks: BlockRegistry
var biomes: BiomeRegistry
var gen: WorldGenerator
var scenario: RID
var chunks: Dictionary = {}
var radius := 8
var max_jobs := 4
## World loading screen (WorldManager preload): more workers and larger per-frame budgets until the area around the
## player is visible; set_loading(false) returns to the in-game values.
var loading := false
var _base_jobs := -1


## Adaptive workers (Chunk Builder Threads = auto): the full count only while a chunk within ADAPT_NEAR_RING is still
## missing (spawn, teleport, fast travel into new land), ADAPT_LOW_JOBS otherwise. Busy workers on every core cost the
## main thread and the GPU their shared power budget / clocks on SoC laptops: flight bench at 2 workers ran +30 % avg
## FPS and +15 % 1 % low (fewer main-thread slowdowns); the far rings fill in a little later under the fog.
const ADAPT_NEAR_RING := 8
const ADAPT_LOW_JOBS := 2
var adaptive_jobs: bool = OS.get_cmdline_user_args().has("--adapt")   # off by default: avg FPS +20 %, 1 % lows not yet better
var _full_jobs := 4
var adapt_boosted := true


var _inner_since := 0
var _fill_phase := false
var _fill_t0 := 0
static var _pininfo: bool = OS.get_cmdline_user_args().has("--pininfo")


var _fill_check_ms := 0
const FILL_SHARE := 0.4   # main-thread dispatch / upload share of the frame while boosted (0.7 measured: no faster)
var _boost := false       # fill / catching up: boosted workers and main-thread budgets
var _user_jobs := false   # Chunk Builder Threads set to a fixed count (--workers=N / the video option)


func _adapt_workers() -> void:
	# background cluster set: wide (every cluster but the main thread's) while loading or while incomplete chunks lie
	# 3+ rings inside the render distance (initial fill, after a teleport, falling behind); the low-class cluster once
	# only the outer rings stream (steady flight keeps up there at 65 chunks / s)
	# (0.4 s hysteresis: the frontier restarts at the centre whenever the wanted list moves and catches up over a few
	# frames)
	var inner := false
	var fring := 1 << 20
	if _frontier < _wanted_n:
		var fw0: Vector2i = _w_at(_frontier)
		fring = maxi(absi(fw0.x - _center.x), absi(fw0.y - _center.y))
		inner = fring <= radius - 3
	# the fill after a loading screen stays wide until every ring inside the render distance is complete once
	if _fill_phase and not loading:
		# done once every chunk within the render distance is shown (the dispatch frontier also passes chunks that only
		# wait for neighbours, so it ended the fill almost at once); checked 4x a second
		var fm := Time.get_ticks_msec()
		if fm - _fill_check_ms >= 250:
			_fill_check_ms = fm
			var all_shown := true
			for wi in _wanted_n:
				var ww: Vector2i = _w_at(wi)
				if maxi(absi(ww.x - _center.x), absi(ww.y - _center.y)) > radius:
					continue
				var wc: Chunk = chunks.get((ww.x << 32) | (ww.y & 0xFFFFFFFF))
				if wc == null or not wc.shown:
					all_shown = false
					break
			if all_shown or fm - _fill_t0 > 30000:
				_fill_phase = false
	if not inner:
		_inner_since = 0
	elif _inner_since == 0:
		_inner_since = Time.get_ticks_usec()
	var wide := loading or _fill_phase or (inner and Time.get_ticks_usec() - _inner_since > 400000)
	if wide != bg_wide:
		if _pininfo:
			print("[pin] %d ms: background clusters %s (frontier ring inner %s, loading %s)" % [Time.get_ticks_msec(), "wide" if wide else "low", str(inner), str(loading)])
		bg_wide = wide
		pin_epoch += 1
	if loading:
		return
	# the first fill of the render distance after a loading screen, and catching up after falling 3+ rings behind
	# (teleport, fast travel), use the loading-screen worker count until the chunks are shown (with 5 workers the fill
	# from ring 2 to 16 took ~12 s); steady streaming keeps the normal count (more workers cost main-thread FPS)
	if not _user_jobs:
		var boost := _fill_phase or (inner and Time.get_ticks_usec() - _inner_since > 400000)
		_boost = boost
		var bj := clampi(OS.get_processor_count() * 2 / 3, _full_jobs, 10) if boost else _full_jobs
		if not adaptive_jobs or boost:
			if bj != max_jobs:
				max_jobs = bj   # surplus workers retire when they finish their current job (_worker_loop)
			return
	if not adaptive_jobs:
		return
	var near := false
	if _frontier < _wanted_n:
		var fw: Vector2i = _w_at(_frontier)
		near = maxi(absi(fw.x - _center.x), absi(fw.y - _center.y)) <= ADAPT_NEAR_RING
	adapt_boosted = near
	var want := _full_jobs if near else mini(ADAPT_LOW_JOBS, _full_jobs)
	if want != max_jobs:
		max_jobs = want
		if near:
			kick()


## Advanced video "Chunk Builder Threads": 0 = auto (1/3 of the CPU threads, 2..5, adaptive), else that many workers.
func set_worker_count(n: int) -> void:
	var base := clampi(OS.get_processor_count() / 3, 2, 5) if n <= 0 else clampi(n, 1, 16)
	_full_jobs = base
	_user_jobs = n > 0
	if n > 0:
		adaptive_jobs = false
	if loading:
		_base_jobs = base
		max_jobs = maxi(max_jobs, base)
	else:
		max_jobs = base
	kick()


## Mesher options (Advanced video): bit 0 = no smart leaf culling, bit 1 = no face merging. Changing them rebuilds
## every loaded chunk's meshes.
var mesh_opts := 0


func set_mesh_opts(o: int) -> void:
	if o == mesh_opts:
		return
	mesh_opts = o
	for rc in chunks.values():
		var rch: Chunk = rc
		if rch.light_valid:
			rch.dirty_groups = 0x3F
	kick()


func set_loading(on: bool) -> void:
	if on == loading:
		return
	loading = on
	if on:
		_fill_phase = true
		_fill_t0 = Time.get_ticks_msec()
	if on and not bg_wide:
		bg_wide = true
		pin_epoch += 1
	if on:
		_base_jobs = max_jobs
		max_jobs = clampi(OS.get_processor_count() * 2 / 3, max_jobs, 10)
	elif _base_jobs > 0:
		max_jobs = _base_jobs   # surplus workers retire when they finish their current job (_worker_loop)
	kick()


var _ovl_map := PackedByteArray()   # TerrainRD.overlay_map (set by set_trd; overlay layer -> 6-bit palette index)
var section_buckets: bool = not OS.get_cmdline_user_args().has("--trsec=0")   # TerrainRD per-section culling (tr_pack flag 1)
var queue_depth := 12            # ready jobs queued beyond max_jobs: workers pull the next job without waiting a frame
var _q: Array = []                # [priority, Callable]; workers take the lowest priority value (nearest ring first)
var _q_mutex := Mutex.new()
var _alive := 0                   # running worker-loop tasks (guarded by _q_mutex)
var _running := 0                 # diagnostics: jobs executing right now
var _ran := 0                     # diagnostics: jobs finished by worker loops
var _submitted := 0
var _committed := 0
var upload_budget_ms := 4.0     # upper bound of the per-frame mesh upload budget
var _upload_budget_us := 4000.0 # this frame's budget: 20% of the recent frame time, 0.8 .. upload_budget_ms
var _last_update_us := 0
var _frame_us_avg := 16000.0
var origin := Vector3i.ZERO           # floating origin (chunk aligned)
var biome_blend := 2
var load_chunk_fn: Callable           # func(cx, cz) -> Chunk or null (saved data)
var save_chunk_fn: Callable           # func(Chunk) -> void

var _mutex := Mutex.new()
var _results: Array = []
var _inflight := 0
## Wanted chunks in priority order: the cached offset order of (radius, look bucket) around _wanted_c (no per-entry
## rebuild when the centre moves), then the rings around extra centres. _w_at(i) gives entry i.
var _wanted_offs := PackedInt32Array()
var _wanted_c := Vector2i.ZERO
var _wanted_extra: Array = []
var _wanted_n := 0
var _center := Vector2i(1 << 30, 0)
var _last_sort_ms := 0
var _jobs_light: Dictionary = {}      # key -> epoch
var _jobs_mesh: Dictionary = {}       # key*8+group -> epoch
var _jobs_decor: Dictionary = {}
var _jobs_feat: Dictionary = {}
var _jobs_gen: Dictionary = {}
var _jobs_raw: Dictionary = {}        # key -> true: pristine terrain of a from-disk chunk being regenerated (Chunk.raw)
var _light_dirty: Dictionary = {}     # key -> true (pipeline: neighbour decorated after a partial light)
var main_us: Dictionary = {}   # tracing: main-thread time per ChunkManager phase
var _moving := false
var _mv_pos := Vector3.ZERO
var _mv_ms := 0
var last_commit_us := 0
var last_dispatch_us := 0
var last_rebuild_us := 0
var _gen_load_us := 0           # tracing: time spent in load_chunk_fn inside generation jobs (racy sum, diagnostics only)
var busy_us: Dictionary = {}   # tracing: summed worker time per job kind
var busy_n: Dictionary = {}
var _light_update: Dictionary = {}    # key -> true (block change in a lit chunk; throttled update work)
## Update jobs (relight/remesh caused by block changes in chunks already shown) share max_update_jobs worker
## slots (+1 while the player edits nearby) and are coalesced per chunk, so random ticks (grass spread, leaf decay,
## fluids) can never starve generation of missing terrain.
var max_update_jobs := 2
var _upd_inflight := 0
var _next_update: Dictionary = {}    # key -> earliest usec for the next non-urgent update job
var _urgent_until: Dictionary = {}   # key -> usec until which updates of this chunk are urgent (player edits)
const MESH_UPDATE_US := 200000    # below a water flow step (5 ticks = 250 ms): 300 ms beat against it (steps merged)
const LIGHT_UPDATE_US := 150000   # per-chunk relight batching for frequent changes (flowing water, TNT); was 600 ms
const MESH_UPDATE_NEAR_US := 50000    # within 2 chunks of the player: flows / pistons / farms update like Java (next frames)
const LIGHT_UPDATE_NEAR_US := 50000
## A relight started by an update and the remesh it needs are one update: the remesh starts when the light commits
## (it waited for the throttle the relight had just set - 50 / 150 ms more per flow step) and keeps the relight's period.
var _chain: Dictionary = {}          # key -> true: the update relight committed, its remesh may start now
## BlockUpdates: block changes made by a game tick's scheduled updates that run in slices over several frames mark their
## chunks here (hold_marks); their update work waits until the last slice ran (release_held), so the whole step of a
## flow is remeshed and shown together.
var hold_marks := false
var _held: Dictionary = {}           # chunk key -> true
var _held_us := 0
var thread_registries: bool = not OS.get_cmdline_user_args().has("--sharedreg")   # A/B: --sharedreg = old shared registries
var _tl_gens: Dictionary = {}         # worker thread id -> private WorldGenerator (avoids shared-refcount contention)
var _tl_mutex := Mutex.new()
var stats := {"generated": 0, "meshed": 0, "lit": 0, "uploaded": 0, "gen_ms": 0.0, "mesh_ms": 0.0, "light_ms": 0.0, "verts": 0}
var shutting_down := false
var has_skylight := true      # false in the Nether: sky light stays 0
var extra_centers: Array = []  # LAN host: other players' chunk positions (generated/simulated, not meshed)
var extra_radius := 4
## Perf tracing (load test): per-chunk stage timestamps in Chunk.trace (usec, Time.get_ticks_usec), finished traces
## of evicted chunks kept in trace_log. Worker results carry their own start/end times.
var tracing := false
var trace_log: Array = []


func _tr(c: Chunk, k: String, t: int = -1) -> void:
	if tracing and not c.trace.has(k):
		c.trace[k] = t if t >= 0 else Time.get_ticks_usec()


func _tr_add(c: Chunk, k: String) -> void:
	if tracing:
		c.trace[k] = int(c.trace.get(k, 0)) + 1


func setup(p_blocks: BlockRegistry, p_biomes: BiomeRegistry, p_gen: WorldGenerator, p_scenario: RID) -> void:
	blocks = p_blocks
	biomes = p_biomes
	gen = p_gen
	scenario = p_scenario
	# GDScript calls/member access contend across threads (benchmarks/contention_probe.gd); with world generation,
	# lighting, meshing and most features native, the real-game load test (--loadtest) peaks at 5 workers on the
	# 18-thread reference machine (6+ only raise frame times: the remaining GDScript features still contend).
	max_jobs = clampi(OS.get_processor_count() / 3, 2, 5)
	_full_jobs = max_jobs


## Thread-local generator: identical config/seed, separate object graph per worker thread.
func _thread_gen() -> WorldGenerator:
	var tid := OS.get_thread_caller_id()
	_tl_mutex.lock()
	var g = _tl_gens.get(tid)
	_tl_mutex.unlock()
	if g != null:
		return g
	var tsu := Time.get_ticks_usec()
	var ng := WorldGenerator.create(gen.generator_id)
	ng.generator_id = gen.generator_id
	# private registry copies: worker reads never share reference counts with the main thread (BlockRegistry.thread_copy)
	ng.setup(gen.seed, blocks.thread_copy() if thread_registries else blocks, biomes.thread_copy() if thread_registries else biomes, gen.settings)
	if tracing and ng is VanillaGenerator and ng.features != null:
		ng.features.profiling = true
	if tracing:
		print("[trace] thread %d generator setup %.0f ms (%d gens)" % [tid, (Time.get_ticks_usec() - tsu) / 1000.0, _tl_gens.size() + 1])
	_tl_mutex.lock()
	_tl_gens[tid] = ng
	_tl_mutex.unlock()
	return ng


## The calling worker's private registry (BlockRegistry.thread_copy via _thread_gen). Mesh / light / load jobs used the
## main thread's tables: every worker read took a reference on arrays the main thread was reading at the same time
## (contended atomic refcounts made main-thread GDScript 10-20x slower in those frames: the play-test microstutters).
func _thread_blocks() -> BlockRegistry:
	return _thread_gen().blocks if thread_registries else blocks


## The calling worker's private copy of the TerrainRD overlay map (same reason).
func _thread_ovl_map() -> PackedByteArray:
	var g := _thread_gen()
	var om = g.get_meta("ovl_map") if g.has_meta("ovl_map") else null   # (a null default counts as "no default")
	if om == null or (om as PackedByteArray).size() != _ovl_map.size():
		om = _ovl_map.duplicate()
		g.set_meta("ovl_map", om)
	return om


func get_chunk(cx: int, cz: int) -> Chunk:
	return chunks.get(Coords.chunk_key(cx, cz))


func get_block(x: int, y: int, z: int) -> int:
	var c: Chunk = chunks.get(Coords.chunk_key(x >> 4, z >> 4))
	if c == null or c.state < Chunk.DATA_READY:
		return -1
	return c.get_block(x & 15, y, z & 15)


## True when the column's chunk has decorated terrain (safe for collision).
func is_ready(x: int, z: int) -> bool:
	var c: Chunk = chunks.get(Coords.chunk_key(x >> 4, z >> 4))
	return c != null and c.state >= Chunk.DECORATED


func get_light(x: int, y: int, z: int) -> int:
	var c: Chunk = chunks.get(Coords.chunk_key(x >> 4, z >> 4))
	if c == null or not c.light_valid:
		return 0xF0
	return Lighting.halo_get(c.light_halo_secs, x & 15, y, z & 15)


## Random-tick leaf decay caches (Chunk.leaf_ok) of the 3x3 chunks around (cx, cz); the leaf search reaches 6 blocks.
func _leaf_cache_clear(cx: int, cz: int) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n: Chunk = chunks.get(Coords.chunk_key(cx + dx, cz + dz))
			if n != null and not n.leaf_ok.is_empty():
				n.leaf_ok.clear()


## Bumped whenever a block or a chunk's availability changes (Collision's per-entity box caches key on it).
var block_epoch := 0


func set_block(x: int, y: int, z: int, st: int) -> int:
	if y < Coords.MIN_Y or y >= Coords.MAX_Y:
		return -1
	var c: Chunk = chunks.get(Coords.chunk_key(x >> 4, z >> 4))
	if c == null or c.state < Chunk.DECORATED:
		return -1
	var old := c.set_block(x & 15, y, z & 15, st)
	if old == st:
		return old
	block_epoch += 1
	c.modified = true
	if RandomTickable.leaf_class(old) != 0 or RandomTickable.leaf_class(st) != 0:
		_leaf_cache_clear(c.cx, c.cz)   # a log or leaf changed: cached leaf-support results nearby may be stale
	c.update_height_at(x & 15, y, z & 15, blocks)
	var lx := x & 15
	var lz := z & 15
	var g := (y - Coords.MIN_Y) / Mesher.GH
	var ly := (y - Coords.MIN_Y) % Mesher.GH
	_batch_ids.clear()
	_collecting = true
	_mark_mesh(c, g)
	if ly == 0 and g > 0:
		_mark_mesh(c, g - 1)
	if ly == Mesher.GH - 1:
		_mark_mesh(c, g + 1)
	# neighbours whose padded border includes this cell
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			if (dx == -1 and lx != 0) or (dx == 1 and lx != 15) or (dz == -1 and lz != 0) or (dz == 1 and lz != 15):
				continue
			var n := get_chunk(c.cx + dx, c.cz + dz)
			if n != null:
				_mark_mesh(n, g)
	_collecting = false
	# (a flow step - air / fluid to air / fluid - opens no batch: no solid faces appear or vanish, and the batch held
	# flow steps on chunk / group borders until the neighbour's relight and remesh, up to EDIT_BATCH_US)
	if _batch_ids.size() > 1 and ((blocks.st_flags[old] & (BlockRegistry.F_AIR | BlockRegistry.F_LIQUID)) == 0 or (blocks.st_flags[st] & (BlockRegistry.F_AIR | BlockRegistry.F_LIQUID)) == 0):
		_open_edit_batch()
	# relight: centre always; neighbours if within 15 blocks of their border
	var light_changes := blocks.st_opacity[old] != blocks.st_opacity[st] or blocks.st_emit[old] != blocks.st_emit[st]
	if light_changes:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n2 := get_chunk(c.cx + dx, c.cz + dz)
				if n2 == null:
					continue
				var near := (dx == 0 or (dx == -1 and lx < 15) or (dx == 1 and lx > 0)) and (dz == 0 or (dz == -1 and lz < 15) or (dz == 1 and lz > 0))
				if near:
					if n2.light_valid:
						_light_update[Coords.chunk_key(n2.cx, n2.cz)] = true
						_work[Coords.chunk_key(n2.cx, n2.cz)] = true
						if hold_marks:
							_held[Coords.chunk_key(n2.cx, n2.cz)] = true
					else:
						_light_dirty[Coords.chunk_key(n2.cx, n2.cz)] = true
						_work[Coords.chunk_key(n2.cx, n2.cz)] = true
	return old


## The mesh group holding block (x, y, z) was rebuilt from blocks at least as new as `epoch` (cm.block_epoch right
## after an edit): the edit is on screen.
func mesh_caught_up(x: int, y: int, z: int, epoch: int) -> bool:
	if y < Coords.MIN_Y or y >= Coords.MAX_Y:
		return true
	var gid := Coords.chunk_key(x >> 4, z >> 4) * 8 + (y - Coords.MIN_Y) / Mesher.GH
	return int(dbg_bepoch.get(gid, -1)) >= epoch


func _mark_mesh(c: Chunk, g: int) -> void:
	if g < 0 or g >= Coords.SECTIONS / Mesher.GROUP:
		return
	if _collecting and c.shown:
		_batch_ids.append(Coords.chunk_key(c.cx, c.cz) * 8 + g)
	_work[(c.cx << 32) | (c.cz & 0xFFFFFFFF)] = true
	if c.shown:
		c.update_groups |= 1 << g
		if hold_marks:
			if _held.is_empty():
				_held_us = Time.get_ticks_usec()
			_held[(c.cx << 32) | (c.cz & 0xFFFFFFFF)] = true
	else:
		c.dirty_groups |= 1 << g


## BlockUpdates finished the sliced updates of a tick: their chunks' update work may start (this frame's dispatch).
func release_held() -> void:
	if _held.is_empty():
		return
	for k in _held:
		_work[k] = true
	_held.clear()


## Edit batches: one block change that touches several mesh groups (a block on a group / chunk border) swaps all their
## new meshes in the same frame. Committed one by one (the per-frame upload budget spreads them over frames) the edited
## group showed its new faces before the neighbour group added the faces the block had covered: see-through holes into
## caves, far more often than Java's threaded rebuilds. Results built from a snapshot older than the edit pass through;
## a batch is flushed after EDIT_BATCH_US even if a group never remeshes.
const EDIT_BATCH_US := 150000
var _batch_ids: Array = []
var dbg_bepoch: Dictionary = {}   # group id -> block epoch of the newest committed mesh (probes)
var _collecting := false
var _edit_batch: Dictionary = {}   # group id (chunk key * 8 + group) -> batch {ids, held, epoch, t}
var _batches: Array = []


func _open_edit_batch() -> void:
	var b := {"ids": {}, "held": [], "epoch": block_epoch, "t": Time.get_ticks_usec()}
	for id in _batch_ids:
		b["ids"][id] = true
		_edit_batch[id] = b
	_batches.append(b)


## A mesh result of a batched group: held until every group of its batch has a result built after the edit.
## Returns true when the caller must not commit it (held, or committed here with the rest of its batch).
func _hold_for_batch(r: Array, key: int) -> bool:
	var id: int = key * 8 + int(r[3])
	var b = _edit_batch.get(id)
	if b == null or int(r[9]) < int(b["epoch"]):
		return false
	_edit_batch.erase(id)
	(b["ids"] as Dictionary).erase(id)
	(b["held"] as Array).append(r)
	if not (b["ids"] as Dictionary).is_empty():
		return true
	_flush_batch(b)
	return true


func _flush_batch(b: Dictionary) -> void:
	_batches.erase(b)
	for id in (b["ids"] as Dictionary).keys():
		if _edit_batch.get(id) == b:
			_edit_batch.erase(id)
	for r in b["held"]:
		var hc: Chunk = r[1]
		var hk := Coords.chunk_key(hc.cx, hc.cz)
		_commit_one("mesh", r, hc, hk, chunks.get(hk) == hc and hc.state != Chunk.EVICTED)
	(b["held"] as Array).clear()


func _flush_old_batches() -> void:
	var now := Time.get_ticks_usec()
	for b in _batches.duplicate():
		if now - int(b["t"]) > EDIT_BATCH_US:
			_flush_batch(b)


## Player edits: update work for the 3x3 chunks around (x, z) runs immediately for the next second.
func mark_urgent(x: int, z: int) -> void:
	var t := Time.get_ticks_usec() + 1000000
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var uk := Coords.chunk_key((x >> 4) + dx, (z >> 4) + dz)
			_urgent_until[uk] = t
			_work[uk] = true


func _can_update(key: int, now: int, chained := false) -> bool:
	var urgent: bool = int(_urgent_until.get(key, 0)) > now
	if not _held.is_empty() and not urgent and _held.has(key):
		if now - _held_us < 500000:
			return false   # (release_held puts it back in the work set)
		release_held()   # (safety: a tick's slices never take this long)
	if _upd_inflight >= max_update_jobs + (1 if urgent else 0):
		_upd_wait[key] = true   # re-evaluated when a running update commits
		return false
	if urgent or chained:
		return true
	var nu := int(_next_update.get(key, 0))
	if now >= nu:
		return true
	_timed[key] = true   # throttled: re-evaluated when the timer expires
	_disp_wake_us = mini(_disp_wake_us, nu)
	return false


## Dispatch work set: block edits, job commits (3x3 around the chunk: neighbour gating), urgent marks, expired update
## timers and finished updates put chunk keys in _work; only those are evaluated. The whole wanted list is walked
## (cheap skip of complete chunks) after the player changes chunk / radius changes, and every frame while worker capacity
## limits dispatch (loading). An idle loaded world costs nothing per frame. External code marking chunk work calls kick().
var vertex_compress := true   # 16-bit positions / UVs (Godot attribute compression; --vcompress=0 to compare)
var debug_hide_group := -1   # experiment: --hidegroup=N hides mesh group N (never in normal play)
var disp_stats := {"full": 0, "full_cap": 0, "one": 0, "work_passes": 0, "work_keys": 0}
var _work: Dictionary = {}          # chunk key -> true
var _timed: Dictionary = {}         # chunk key -> true: update throttled by _next_update
var _upd_wait: Dictionary = {}      # chunk key -> true: update blocked by max_update_jobs
var _full := true
var _full_cursor := 0
var _frontier := 0   # index in _wanted before which every chunk is complete or idle (reset when _wanted changes)
const DISPATCH_BUDGET_US := 1000   # upper bound of the per-frame dispatch budget
var _disp_budget_us := 1000        # this frame's: 15 % of the recent frame time, 300 .. DISPATCH_BUDGET_US
var _idle: Dictionary = {}          # chunk key -> packed centre it was evaluated at: nothing to start until an event
var _ckey := 0                       # packed current centre (the value idle entries store)
var _disp_wake_us := 1 << 62


## Idle state depends on the Chebyshev distance to the centre only through the radius thresholds (create <= r+2,
## features <= r+1, decorate / light / mesh <= r): after a centre move only chunks in that band can change status.
## Chunks near the render distance edge may need work after the centre moved (their neighbours / wanted state
## changed): idle entries in the band radius - 1 .. radius + 3 recorded at another centre are treated as not idle by the
## walk (was ~750 dictionary erases in the frame of every chunk crossing).
func _unidle_band(pcx: int, pcz: int) -> void:
	_ckey = (pcx << 32) | (pcz & 0xFFFFFFFF)


func _idle_now(key: int) -> bool:
	var iv = _idle.get(key)
	if iv == null:
		return false
	if int(iv) == _ckey:
		return true
	return maxi(absi((key >> 32) - _center.x), absi(((key << 32) >> 32) - _center.y)) < radius - 1


## First index of the current wanted order whose ring (Chebyshev distance to the centre) is >= r.
func _first_at_ring(r: int) -> int:
	var offs := _wanted_offs
	for i in offs.size():
		var o: int = offs[i]
		if maxi(absi((o >> 10) - 512), absi((o & 1023) - 512)) >= r:
			return i
	return 0


func kick() -> void:
	_full = true
	_idle.clear()
	_frontier = 0
	_full_cursor = 0


func set_radius(r: int) -> void:
	_full = true
	_idle.clear()
	_frontier = 0
	_full_cursor = 0
	radius = clampi(r, 0, 32)
	_center = Vector2i(1 << 30, 0)


## Main-thread per-frame entry point.
func update(pos: Vector3, forward: Vector3) -> void:
	if shutting_down:
		return
	var pcx := int(floor(pos.x)) >> 4
	var pcz := int(floor(pos.z)) >> 4
	var now := Time.get_ticks_msec()
	var m0 := Time.get_ticks_usec()
	if _last_update_us > 0:
		_frame_us_avg = lerpf(_frame_us_avg, float(mini(m0 - _last_update_us, 100000)), 0.05)
	_last_update_us = m0
	_upload_budget_us = clampf(_frame_us_avg * 0.2, 800.0, upload_budget_ms * 1000.0)
	_disp_budget_us = int(clampf(_frame_us_avg * 0.15, 300.0, float(DISPATCH_BUDGET_US)))
	if loading:   # loading screen: no gameplay to keep smooth -> large main-thread budgets
		_upload_budget_us = 12000.0
		_disp_budget_us = 4000
	elif _boost:
		# first fill after the loading screen: the world appearing fast matters more than these few seconds of frame
		# time (main-thread dispatch / upload were the limit at ~150 chunks / s, not the workers)
		_upload_budget_us = clampf(_frame_us_avg * FILL_SHARE, 800.0, 6000.0)
		_disp_budget_us = int(clampf(_frame_us_avg * FILL_SHARE, 300.0, 3000.0))
	# look-ahead bias only while travelling (> 4 blocks/s): standing still, rings complete strictly inside-out
	if now - _mv_ms >= 500:
		var sp := Vector2(pos.x - _mv_pos.x, pos.z - _mv_pos.z).length() / maxf(0.001, (now - _mv_ms) / 1000.0)
		_moving = sp > 4.0
		_mv_pos = pos
		_mv_ms = now
	if Vector2i(pcx, pcz) != _center or now - _last_sort_ms > 750:
		var old_center := _center
		var old_fring := -1
		if _frontier < _wanted_n and _frontier < _wanted_offs.size():
			var ofw: Vector2i = _w_at(_frontier)
			old_fring = maxi(absi(ofw.x - old_center.x), absi(ofw.y - old_center.y))
		_center = Vector2i(pcx, pcz)
		_last_sort_ms = now
		var center_moved := Vector2i(pcx, pcz) != _rb_center
		_rb_center = Vector2i(pcx, pcz)
		if _rebuild_wanted(pcx, pcz, forward):
			_full = true   # new order / new positions: walk the wanted list (idle chunks are skipped cheaply)
			# a move of at most one chunk (or a new heading): every chunk 3+ rings inside the old frontier ring was
			# before the old frontier (complete or idle), so the walk restarts there instead of at the centre (the walk
			# over ~1400 entries after every chunk crossing was ~20 % of the main thread on x86); heading biases are
			# < 0.6 ring
			var nf := 0
			if old_fring > 3 and extra_centers.is_empty() and absi(pcx - old_center.x) <= 1 and absi(pcz - old_center.y) <= 1:
				nf = _first_at_ring(old_fring - 3)
			_full_cursor = nf
			_frontier = nf
		if center_moved or not extra_centers.is_empty():
			_unload_far(pcx, pcz)
		if not extra_centers.is_empty():
			_idle.clear()
			_frontier = 0
		elif center_moved:
			_unidle_band(pcx, pcz)
	if not _drop_q.is_empty():
		_drain_drops(pcx, pcz, 6)
	if not _free_q.is_empty():
		_drain_frees()
	var m1 := Time.get_ticks_usec()
	if tracing:
		last_commit_parts = {}
		frame_upload_slow = 0
	_commit_results()
	var m2 := Time.get_ticks_usec()
	# while every worker is busy and jobs are queued behind them, dispatch passes are batched (at most one per
	# DISPATCH_BATCH_US): at high frame rates this de-duplicates chunk keys woken by several commits and skips passes
	# that could not start anything sooner than the queued jobs anyway
	if _inflight <= max_jobs or m2 - _last_dispatch_at >= DISPATCH_BATCH_US:
		_last_dispatch_at = m2
		_dispatch(pcx, pcz)
	var m3b := Time.get_ticks_usec()
	last_rebuild_us = m1 - m0
	last_commit_us = m2 - m1
	last_dispatch_us = m3b - m2
	if tracing:
		var m3 := Time.get_ticks_usec()
		_mt("rebuild+unload", m1 - m0)
		_mt("commit", m2 - m1)
		_mt("dispatch", m3 - m2)


var _rb_center := Vector2i(1 << 30, 0)
var _last_dispatch_at := 0
var last_commit_parts: Dictionary = {}
var frame_upload_slow := 0   # tracing: duration of a slow _upload in this frame (usec)   # tracing: this frame's commit time by result kind (usec)
const DISPATCH_BATCH_US := 4000


func _mt(k: String, us: int) -> void:
	main_us[k] = int(main_us.get(k, 0)) + us


var _order_cache: Dictionary = {}   # r * 64 + direction bucket + 1 -> PackedInt32Array of ((dx + 512) << 10) | (dz + 512)
var _wb_key := Vector4i(1 << 30, 0, 0, 0)


## Priority order of the offsets around the player: Chebyshev ring, then distance; while travelling biased towards the
## look direction (32 direction buckets). Sorted once per (radius, bucket) and cached; returns false when unchanged.
func _rebuild_wanted(pcx: int, pcz: int, forward: Vector3) -> bool:
	var r := radius + (2 if gen.uses_feature_stage() else 1)
	var f2 := Vector2(forward.x, forward.z)
	var bucket := -1
	if _moving and f2.length() > 0.1:
		bucket = posmod(roundi(atan2(f2.y, f2.x) / TAU * 32.0), 32)
	var wk := Vector4i(pcx, pcz, bucket, r)
	if wk == _wb_key and extra_centers.is_empty() and _wanted_n > 0:
		return false
	_wb_key = wk
	var ck := r * 64 + bucket + 1
	var offs: PackedInt32Array = _order_cache.get(ck, PackedInt32Array())
	if offs.is_empty():
		var fd := Vector2.ZERO
		if bucket >= 0:
			fd = Vector2(cos(bucket * TAU / 32.0), sin(bucket * TAU / 32.0))
		# packed (priority in 1/1000 units << 20 | index) keys sorted natively: the GDScript sort_custom over the
		# (2r+3)^2 entries cost up to ~12 ms in the frame a new heading bucket first appeared (a flight stutter)
		var keys := PackedInt64Array()
		var side := 2 * r + 1
		keys.resize(side * side)
		var ki := 0
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var d2 := dx * dx + dz * dz
				var pri := float(maxi(absi(dx), absi(dz))) * 100.0 + float(d2) * 0.01
				if d2 > 4 and bucket >= 0:
					pri -= 60.0 * Vector2(dx, dz).normalized().dot(fd)
				keys[ki] = (int(roundf((pri + 10000.0) * 1000.0)) << 20) | ki
				ki += 1
		keys.sort()
		for k2 in keys:
			var idx := k2 & 0xFFFFF
			offs.append(((idx % side - r + 512) << 10) | (idx / side - r + 512))
		_order_cache[ck] = offs
	_wanted_offs = offs
	_wanted_c = Vector2i(pcx, pcz)
	_wanted_extra = []
	var er := extra_radius + 2
	for ec in extra_centers:
		for ring in er + 1:
			for dz in range(-ring, ring + 1):
				for dx in range(-ring, ring + 1):
					if maxi(absi(dx), absi(dz)) == ring:
						_wanted_extra.append(Vector2i(ec.x + dx, ec.y + dz))
	_wanted_n = offs.size() + _wanted_extra.size()
	return true


func _w_at(i: int) -> Vector2i:
	if i < _wanted_offs.size():
		var o := _wanted_offs[i]
		return Vector2i(_wanted_c.x + (o >> 10) - 512, _wanted_c.y + (o & 1023) - 512)
	return _wanted_extra[i - _wanted_offs.size()]


func _cheb(a: Vector2i, cx: int, cz: int) -> int:
	return maxi(absi(a.x - cx), absi(a.y - cz))


func _dist2(cx: int, cz: int) -> int:
	return (cx - _center.x) * (cx - _center.x) + (cz - _center.y) * (cz - _center.y)


func _all_neighbors_at_least(c: Chunk, st: int) -> bool:
	var cx := c.cx
	var cz := c.cz
	for dz in range(-1, 2):
		var zk := (cz + dz) & 0xFFFFFFFF
		for dx in range(-1, 2):
			var n: Chunk = chunks.get(((cx + dx) << 32) | zk)
			if n == null or n.state < st:
				return false
	return true


var _snap_cache: Dictionary = {}   # chunk key -> snapshot, valid within one _dispatch pass (no edits happen during it)


func _snap(n: Chunk) -> Array:
	var k := Coords.chunk_key(n.cx, n.cz)
	var s = _snap_cache.get(k)
	if s == null:
		s = n.snapshot()
		_snap_cache[k] = s
	return s


func _kz(key: int) -> int:
	var z := key & 0xFFFFFFFF
	return z - 0x100000000 if z >= 0x80000000 else z


func _dispatch(pcx: int, pcz: int) -> void:
	_adapt_workers()
	var now := Time.get_ticks_usec()
	if now >= _disp_wake_us:
		# wake only the throttled chunks whose own update timer expired; the rest keep waiting for theirs
		_disp_wake_us = 1 << 62
		var keep := {}
		for k in _timed:
			var nu := int(_next_update.get(k, 0))
			if nu <= now:
				_work[k] = true
				disp_stats["wake_timed"] = int(disp_stats.get("wake_timed", 0)) + 1
			else:
				keep[k] = true
				_disp_wake_us = mini(_disp_wake_us, nu)
		_timed = keep
	if not _upd_wait.is_empty():
		# chunks blocked on update capacity: wake as many as there are free update slots (oldest first); a woken chunk
		# that no longer needs its slot leaves it free, so the next waiters are woken on the following frame
		var free_slots := max_update_jobs - _upd_inflight
		if free_slots > 0:
			var wk: Array = _upd_wait.keys()
			if wk.size() > free_slots:
				# nearest first (a flow step near the player queues 9 relights; far ones must not delay them)
				var wr: Array = []
				for wi2 in wk.size():
					var wkk: int = wk[wi2]
					wr.append(maxi(absi((wkk >> 32) - _center.x), absi(((wkk << 32) >> 32) - _center.y)) * 0x100000000 + wi2)
				wr.sort()
				var wk2: Array = []
				for wv in wr.slice(0, free_slots):
					wk2.append(wk[wv & 0xFFFFFFFF])
				wk = wk2
			for k in wk.slice(0, free_slots):
				_upd_wait.erase(k)
				_work[k] = true
				disp_stats["wake_updwait"] = int(disp_stats.get("wake_updwait", 0)) + 1
	if not _full and _work.is_empty():
		return
	if _inflight >= max_jobs + queue_depth:
		return   # worker queue full: nothing can start this frame (events stay in _work / _full for later)
	_snap_cache.clear()
	var rr := float(radius) + 0.5
	var feat_stage := gen.uses_feature_stage()
	# 1) event work set (nearest ring first): chunks touched by commits, edits, timers. While the full walk is active,
	#    only events nearer than the walk's frontier are handled here; farther ones wait for their turn in the walk
	#    (nearest-first order: far commits must not pull far chunks ahead of near ones).
	if not _work.is_empty():
		var ks: Array
		if _full and _frontier < _wanted_n:
			var fw: Vector2i = _w_at(_frontier)
			var fring := maxi(absi(fw.x - _center.x), absi(fw.y - _center.y))
			ks = []
			for k1 in _work.keys():
				if maxi(absi((k1 >> 32) - _center.x), absi(_kz(k1) - _center.y)) <= fring:
					ks.append(k1)
					_work.erase(k1)
		else:
			ks = _work.keys()
			_work.clear()
		disp_stats["work_passes"] += 1
		disp_stats["work_keys"] += ks.size()
		if ks.size() > 1:
			var ring: Array = []
			for k2 in ks:
				ring.append(maxi(absi((k2 >> 32) - _center.x), absi(_kz(k2) - _center.y)) * 0x100000000 + ring.size())
			ring.sort()
			var ks2: Array = []
			for rv in ring:
				ks2.append(ks[rv & 0xFFFFFFFF])
			ks = ks2
		var w_end := now + _disp_budget_us
		for i in ks.size():
			var key2: int = ks[i]
			if i > 0 and Time.get_ticks_usec() > w_end:
				# frame budget used: the rest (farther keys) stays in the work set for the next frame
				for j in range(i, ks.size()):
					_work[ks[j]] = true
				return
			if _dispatch_one(key2 >> 32, _kz(key2), key2, chunks.get(key2), rr, feat_stage, now) == 1:
				for j in range(i, ks.size()):
					_work[ks[j]] = true
				return
			_idle[key2] = _ckey
	if not _full:
		return
	# 2) walk of the wanted list from the frontier: every entry before _frontier is complete or idle (they only need
	#    work again through an event, which lands in the work set above). Time-sliced (resumes at _full_cursor).
	disp_stats["full"] += 1
	var t_end := now + _disp_budget_us
	var nw := _wanted_n
	var i0 := maxi(_full_cursor, _frontier)
	var adv := i0 == _frontier
	var wi := i0
	while wi < nw:
		if wi > i0 and (wi & 15) == 0 and Time.get_ticks_usec() > t_end:
			_full_cursor = wi
			return
		var w: Vector2i = _w_at(wi)
		wi += 1
		var cx: int = w.x
		var cz: int = w.y
		var key := (cx << 32) | (cz & 0xFFFFFFFF)
		var c: Chunk = chunks.get(key)
		# complete chunks need nothing until an event puts them in the work set
		var skip := c != null and c.shown and c.light_valid and c.dirty_groups == 0 and c.update_groups == 0 and not _light_update.has(key) and not _light_dirty.has(key)
		# evaluated before with nothing startable (waiting for neighbours / its own job): skip until an event
		if not skip and not _work.has(key) and _idle_now(key):
			skip = true
		if skip:
			if adv:
				_frontier = wi
			continue
		adv = false
		disp_stats["one"] += 1
		_work.erase(key)
		if _dispatch_one(cx, cz, key, c, rr, feat_stage, now) == 1:
			_work[key] = true
			_full_cursor = _frontier   # capacity-limited (loading / travelling): walk again from the frontier
			disp_stats["full_cap"] += 1
			return
		_idle[key] = _ckey
	_full = false
	_full_cursor = _frontier

## One chunk's next pipeline step. Returns 1 when worker capacity is exhausted (stop dispatching), else 0.
func _dispatch_one(cx: int, cz: int, key: int, c: Chunk, rr: float, feat_stage: bool, now: int) -> int:
	if _inflight >= max_jobs + queue_depth:
		return 1
	var d_main := float(maxi(absi(cx - _center.x), absi(cz - _center.y)))  # Chebyshev: matches 3x3 stage dependencies
	var d := d_main
	for ec in extra_centers:
		d = minf(d, float(maxi(absi(cx - ec.x), absi(cz - ec.y)) + radius - extra_radius))
	if c == null:
		if d <= rr + (2.0 if feat_stage else 1.0):
			_flush_pending_save(key)
			c = Chunk.new(cx, cz)
			c.state = Chunk.QUEUED
			chunks[key] = c
			_tr(c, "req")
			_start_gen(c)
		return 0
	if feat_stage and c.state >= Chunk.DATA_READY and not c.features_ready and d <= rr + 1.0 and not _jobs_feat.has(key):
		# a chunk loaded from a save needs its feature writes only for neighbours that still have to decorate; then its
		# features (and theirs) run on the pristine terrain (Chunk.raw), so regenerated neighbours match first generation
		if not c.from_disk or _undecorated_neighbor(c):
			if _all_neighbors_at_least(c, Chunk.DATA_READY) and _raw_ready(c):
				_start_features(c)
		if not c.from_disk:
			return 0
	if c.state == Chunk.DATA_READY and d <= (rr if feat_stage else rr + 1.0) and not _jobs_decor.has(key):
		if _all_neighbors_at_least(c, Chunk.DATA_READY) and (not feat_stage or _all_features_ready(c)):
			_start_decorate(c)
		return 0
	if c.state < Chunk.DECORATED or d > rr:
		return 0
	if (not c.light_valid or _light_dirty.has(key)) and not _jobs_light.has(key):
		# first light waits for neighbours inside the decoration radius (avoids a relight per neighbour); border
		# chunks light against generated neighbours and are redone when those decorate
		if _light_ready(c, rr):
			_light_dirty.erase(key)
			_light_update.erase(key)
			_start_light(c, false)
			return 0
		if not c.light_valid:
			return 0
		# lit (partially) and waiting for a relight: keep meshing with the current light meanwhile
	if _light_update.has(key) and not _jobs_light.has(key) and c.light_valid:
		if _can_update(key, now):
			_light_update.erase(key)
			_next_update[key] = now + (LIGHT_UPDATE_NEAR_US if d_main <= 2.0 else LIGHT_UPDATE_US)
			_start_light(c, true)
			return 0
	if c.light_valid and c.dirty_groups != 0 and d_main <= rr and _all_neighbors_at_least(c, Chunk.DATA_READY):
		for g in Coords.SECTIONS / Mesher.GROUP:
			if (c.dirty_groups >> g) & 1 and not _jobs_mesh.has(key * 8 + g):
				if _inflight >= max_jobs:
					return 1
				c.dirty_groups &= ~(1 << g)
				c.update_groups &= ~(1 << g)
				_start_mesh(c, g, false)
	elif c.light_valid and c.update_groups != 0 and d_main <= rr and _can_update(key, now, _chain.has(key) and not _jobs_light.has(key)):
		# every pending group of the chunk starts together (one update slot per chunk; the per-chunk throttle let one
		# group through per period, so a chunk's groups trickled in over seconds); throttle period shorter near the player
		var started := false
		for g in Coords.SECTIONS / Mesher.GROUP:
			if (c.update_groups >> g) & 1 and not _jobs_mesh.has(key * 8 + g):
				if _inflight >= max_jobs + queue_depth:
					break
				c.update_groups &= ~(1 << g)
				_start_mesh(c, g, true)
				started = true
		if started:
			if _chain.has(key):
				_chain.erase(key)   # (the remesh of a relight keeps the relight's throttle period)
			else:
				_next_update[key] = now + (MESH_UPDATE_NEAR_US if d_main <= 2.0 else MESH_UPDATE_US)
		if c.update_groups != 0 and _inflight >= max_jobs + queue_depth:
			return 1
	return 0


## Job priority: Chebyshev ring from the player, then stage (mesh 0 < light < decorate < features < generate 4) so the
## work that completes near chunks runs first even when the queue holds farther jobs.
func _pri(c: Chunk, stage: int) -> int:
	return maxi(absi(c.cx - _center.x), absi(c.cz - _center.y)) * 10 + stage


## Queue a worker job; keeps up to max_jobs worker-loop tasks alive draining the queue by priority.
var sub_kinds: Dictionary = {}   # diagnostics: submitted jobs per kind


func _submit(job: Callable, pri: int = 0) -> void:
	if tracing:
		var kn := str(job.get_method())
		sub_kinds[kn] = int(sub_kinds.get(kn, 0)) + 1
	_q_mutex.lock()
	_submitted += 1
	_q.append([pri, job])
	var spawn := _alive < max_jobs
	if spawn:
		_alive += 1
	_q_mutex.unlock()
	if spawn:
		WorkerThreadPool.add_task(_worker_loop)


## OS thread priorities: the main thread above normal, chunk workers / saver below normal, so a burst of
## background work can never take the main thread's core for a scheduler quantum (--noprio disables).
static var thread_prio: bool = not OS.get_cmdline_user_args().has("--noprio") and ClassDB.class_exists("RecraftNative")

## Core clusters (CPU sets sharing one last-level cache): the main thread prefers the last cluster of the fastest
## efficiency class, background threads (chunk workers, saver) every other cluster, so world generation never shares the
## main thread's L2 cache or cluster clock. Soft preference (SetThreadSelectedCpuSets).
static var _pin_main := PackedInt32Array()
static var _pin_bg := PackedInt32Array()
static var _pin_bg_wide := PackedInt32Array()   # every cluster but the main thread's (world loading: speed over FPS)
## true while the loading screen runs (set_loading): background threads may use every cluster but the main thread's;
## workers re-pin when pin_epoch changes
static var bg_wide := false
static var pin_epoch := 0
static var _pin_ready := false


## bits: 1 main thread, 2 background threads (--pin=N). Default 1: on CPUs with core classes (Snapdragon clusters, Intel
## P/E cores) the scheduler moved the main thread to a slow core while workers were busy - a fixed GDScript probe ran 10x
## slower in those frames (play bench: 105 -> 39 frames over 8 ms). 3 (workers pinned off the main cluster) hurts lows.
static var pin_mode := -1


static func pin_thread(main: bool) -> void:
	if pin_mode < 0:
		# Advanced video "Fast-Core Pinning": main thread on the fastest cluster AND the chunk workers off it (flight
		# benchmark, Snapdragon X2: both 383 / 1 % low 104 FPS; main only 308 / 74; workers only 257 / 71; off 291 / 68;
		# since 2026-11-13 the workers use the lower-class cluster only: 415 / 166)
		pin_mode = 3 if Settings.get_v("adv_pin_main") else 0
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--pin="):
				pin_mode = int(a.substr(6))
	if pin_mode & (1 if main else 2) == 0 or not thread_prio or not Native.inst.has_method("cpu_sets"):
		return
	if not _pin_ready:
		_pin_ready = true
		var a: PackedInt32Array = Native.inst.cpu_sets()[0]
		if OS.get_cmdline_user_args().has("--pininfo"):
			print("[pin] cpu sets (id, logical, core, llc, eff class): ", a)
		var best := -1
		var llcs := {}
		for i in range(0, a.size(), 5):
			best = maxi(best, a[i + 4])
			llcs[a[i + 3]] = maxi(int(llcs.get(a[i + 3], -1)), a[i + 4])
		var main_llc := -1
		for l in llcs:
			if int(llcs[l]) == best and int(l) > main_llc:
				main_llc = int(l)
		if llcs.size() < 2 or main_llc < 0:
			return
		# --pinbg=L1,L2: background threads only on these last-level-cache clusters (experiments)
		var bg_only := {}
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--pinbg="):
				for s in arg.substr(8).split(","):
					bg_only[int(s)] = true
		# background threads: the clusters of a lower efficiency class when the CPU has them (Snapdragon X2: the 6
		# Performance cores), else every cluster but the main thread's. Workers on the second Prime cluster pulled the
		# main thread's clock down with them (flight bench, same 65 chunks / s: avg 240 -> 415 FPS, 1 % low 70 -> 166,
		# max 38 -> 17 ms; slowed main-thread frames 195 -> 8)
		var low_bg := PackedInt32Array()
		for i in range(0, a.size(), 5):
			if a[i + 3] == main_llc:
				_pin_main.append(a[i])
			else:
				_pin_bg.append(a[i])
				if a[i + 4] < best:
					low_bg.append(a[i])
		_pin_bg_wide = _pin_bg.duplicate()
		if low_bg.size() >= 4 and not OS.get_cmdline_user_args().has("--pinprime"):
			_pin_bg = low_bg
		if not bg_only.is_empty():
			_pin_bg.clear()
			for i in range(0, a.size(), 5):
				if bg_only.has(a[i + 3]):
					_pin_bg.append(a[i])
			_pin_bg_wide = _pin_bg.duplicate()
	var ids := _pin_main if main else (_pin_bg_wide if bg_wide and not _pin_bg_wide.is_empty() else _pin_bg)
	if not ids.is_empty():
		Native.inst.set_thread_cpu_sets(ids)

## --ecoworkers: chunk workers under EcoQoS (efficiency cores, lower clocks) - their load kept off the main thread's
## cluster and power budget (experiment: main-thread slowdowns follow worker activity).
static var eco_workers: bool = OS.get_cmdline_user_args().has("--ecoworkers")


func _worker_loop() -> void:
	if thread_prio and Native.inst.has_method("set_thread_priority"):
		Native.inst.set_thread_priority(-1)
	if eco_workers and Native.inst.has_method("thread_eco"):
		Native.inst.thread_eco(1)
	pin_thread(false)
	var my_epoch := pin_epoch
	while true:
		if my_epoch != pin_epoch:   # loading screen started / ended: background cluster set changed
			my_epoch = pin_epoch
			pin_thread(false)
		_q_mutex.lock()
		if _q.is_empty() or shutting_down or _alive > max_jobs:   # (more workers than wanted after the loading screen)
			_alive -= 1
			_q_mutex.unlock()
			return
		var bi := 0
		var bp: int = _q[0][0]
		for qi in range(1, _q.size()):
			if int(_q[qi][0]) < bp:
				bp = _q[qi][0]
				bi = qi
		var job: Callable = _q[bi][1]
		_q.remove_at(bi)
		_running += 1
		_q_mutex.unlock()
		job.call()
		_q_mutex.lock()
		_running -= 1
		_ran += 1
		_q_mutex.unlock()


func _push_result(r: Array) -> void:
	_mutex.lock()
	_results.append(r)
	_mutex.unlock()


# ---------------------------------------------------------------- jobs

func _start_gen(c: Chunk) -> void:
	_inflight += 1
	c.state = Chunk.GENERATING
	var key := Coords.chunk_key(c.cx, c.cz)
	_jobs_gen[key] = true
	_submit(_job_gen.bind(c, c.mesh_epoch), _pri(c, 4))


## Chunks of dimensions the player left (decorated data kept in memory, entities stored, modified ones also saved):
## dimension -> {chunk key: Chunk}. A chunk wanted again is adopted from here instead of being read from the region
## files or generated (WorldManager.change_dimension fills it; cleared when a world closes).
static var dim_cache: Dictionary = {}
static var _dc_mutex := Mutex.new()
static var cache_hits := 0
var dim_name := ""


static func cache_take(dim: String, key: int) -> Chunk:
	_dc_mutex.lock()
	var m = dim_cache.get(dim)
	var r: Chunk = null
	if m != null:
		r = (m as Dictionary).get(key)
		if r != null:
			(m as Dictionary).erase(key)
			cache_hits += 1
	_dc_mutex.unlock()
	return r


## Takes over a cached chunk's data (same result as SaveManager.apply_chunk_data on its saved form).
static func adopt(c: Chunk, src: Chunk) -> void:
	c.sections = src.sections
	c.biomes = src.biomes
	c.gen_surface = src.gen_surface
	c.gen_top = src.gen_top
	c.gen_floor = src.gen_floor
	c.heightmap = src.heightmap
	c.block_entities = src.block_entities
	c.saved_entities = src.saved_entities
	c.scheduled = src.scheduled
	c.feature_writes = src.feature_writes
	c.unknown_states = src.unknown_states
	c.features_ready = true
	c.modified = src.modified


func _job_gen(c: Chunk, epoch: int) -> void:
	var t0 := Time.get_ticks_usec()
	var loaded := false
	if dim_name != "":
		var cached := cache_take(dim_name, Coords.chunk_key(c.cx, c.cz))
		if cached != null:
			adopt(c, cached)
			loaded = true
	if not loaded and load_chunk_fn.is_valid():
		var saved = load_chunk_fn.call(c.cx, c.cz)
		if tracing:
			_gen_load_us += Time.get_ticks_usec() - t0
		if saved is Dictionary and not saved.is_empty():
			SaveManager.apply_chunk_data(c, saved, _thread_blocks())
			loaded = true
	if not loaded:
		_thread_gen().generate(c)
	_push_result(["gen", c, epoch, Time.get_ticks_usec() - t0, loaded, t0, Time.get_ticks_usec()])


func _all_features_ready(c: Chunk) -> bool:
	var cx := c.cx
	var cz := c.cz
	for dz in range(-1, 2):
		var zk := (cz + dz) & 0xFFFFFFFF
		for dx in range(-1, 2):
			var n: Chunk = chunks.get(((cx + dx) << 32) | zk)
			if n == null or not n.features_ready:
				return false
	return true


func _start_features(c: Chunk) -> void:
	_inflight += 1
	_jobs_feat[Coords.chunk_key(c.cx, c.cz)] = true
	var nine: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := get_chunk(c.cx + dx, c.cz + dz)
			nine.append(n.raw if n != null and n.raw != null else n)   # from-disk chunks: pristine terrain
	_submit(_job_features.bind(c, ChunkRegion.new(c.cx, c.cz, nine), c.mesh_epoch, c.raw), _pri(c, 3))


func _job_features(c: Chunk, region: ChunkRegion, epoch: int, origin: Chunk = null) -> void:
	var t0 := Time.get_ticks_usec()
	var w := _thread_gen().compute_features(origin if origin != null else c, region)
	_push_result(["feat", c, epoch, w, Time.get_ticks_usec() - t0, t0, Time.get_ticks_usec(), origin])


## A from-disk chunk with a 3x3 neighbour that is missing or not decorated yet (its feature writes are still needed).
func _undecorated_neighbor(c: Chunk) -> bool:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := get_chunk(c.cx + dx, c.cz + dz)
			if n == null or n.state < Chunk.DECORATED:
				return true
	return false


## Every from-disk chunk in the 3x3 has its pristine terrain (Chunk.raw); starts the missing regenerations.
func _raw_ready(c: Chunk) -> bool:
	var ok := true
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := get_chunk(c.cx + dx, c.cz + dz)
			if n == null or not n.from_disk or n.raw != null:
				continue
			ok = false
			var nk := Coords.chunk_key(n.cx, n.cz)
			if not _jobs_raw.has(nk):
				_jobs_raw[nk] = true
				_inflight += 1
				_submit(_job_raw.bind(n, n.mesh_epoch), _pri(n, 3))
	return ok


func _job_raw(c: Chunk, epoch: int) -> void:
	var t0 := Time.get_ticks_usec()
	var tmp := Chunk.new(c.cx, c.cz)
	_thread_gen().generate(tmp)
	_push_result(["raw", c, epoch, tmp, Time.get_ticks_usec() - t0, t0, Time.get_ticks_usec()])


## After a decoration: from-disk neighbours whose 3x3 is now fully decorated no longer need their pristine terrain.
func _release_raw_around(c: Chunk) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := get_chunk(c.cx + dx, c.cz + dz)
			if n != null and n.raw != null and not _undecorated_neighbor(n):
				n.raw = null


func _start_decorate(c: Chunk) -> void:
	_inflight += 1
	var key := Coords.chunk_key(c.cx, c.cz)
	_jobs_decor[key] = true
	var nine: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			nine.append(get_chunk(c.cx + dx, c.cz + dz))
	var region := ChunkRegion.new(c.cx, c.cz, nine)
	# feature-stage generators write only the centre chunk: decorate a private copy (Chunk.decor_shell), installed by the
	# main thread at commit, so neighbour snapshots never see a half-decorated chunk
	var shell: Chunk = c.decor_shell() if gen.uses_feature_stage() else null
	_submit(_job_decorate.bind(c, region, c.mesh_epoch, shell), _pri(c, 2))


func _job_decorate(c: Chunk, region: ChunkRegion, epoch: int, shell: Chunk = null) -> void:
	var t0 := Time.get_ticks_usec()
	_thread_gen().decorate(shell if shell != null else c, region)
	_push_result(["decor", c, epoch, shell, 0, t0, Time.get_ticks_usec()])


## First light: every neighbour inside the decoration radius is decorated (others only need to be generated).
func _light_ready(c: Chunk, rr: float) -> bool:
	var cx := c.cx
	var cz := c.cz
	for dz in range(-1, 2):
		var zk := (cz + dz) & 0xFFFFFFFF
		for dx in range(-1, 2):
			var n: Chunk = chunks.get(((cx + dx) << 32) | zk)
			if n == null or n.state < Chunk.DATA_READY:
				return false
			if n.state < Chunk.DECORATED and float(maxi(absi(n.cx - _center.x), absi(n.cz - _center.y))) <= rr:
				return false
	return true


func _start_light(c: Chunk, update := false) -> void:
	_inflight += 1
	if update:
		_upd_inflight += 1
	var key := Coords.chunk_key(c.cx, c.cz)
	c.light_epoch += 1
	_jobs_light[key] = c.light_epoch
	var snaps: Array = []
	var hms: Array = []
	c.light_partial = false
	var no_sky := PackedInt32Array()
	if not has_skylight:
		no_sky.resize(256)
		no_sky.fill(Coords.MAX_Y)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := get_chunk(c.cx + dx, c.cz + dz)
			if n == null or n.state < Chunk.DECORATED:
				c.light_partial = true
			snaps.append(_snap(n) if n != null else null)
			hms.append((n.heightmap.duplicate() if has_skylight else no_sky) if n != null else null)
	# updates of chunks on screen (block changes: flowing water, player edits) go before generation work: behind the
	# generation queue they waited seconds while terrain streamed in
	_submit(_job_light.bind(c, snaps, hms, c.light_epoch, update), _pri(c, 1) - (1000 if update else 0))


func _job_light(c: Chunk, snaps: Array, hms: Array, epoch: int, update: bool) -> void:
	var t0 := Time.get_ticks_usec()
	var res := Lighting.compute(snaps, hms, _thread_blocks())
	_push_result(["light", c, epoch, res, Time.get_ticks_usec() - t0, t0, Time.get_ticks_usec(), update])


func _start_mesh(c: Chunk, g: int, update := false) -> void:
	var tsm := Time.get_ticks_usec() if tracing else 0
	_inflight += 1
	if update:
		_upd_inflight += 1
	var key := Coords.chunk_key(c.cx, c.cz)
	_jobs_mesh[key * 8 + g] = c.mesh_epoch
	var snaps: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n := get_chunk(c.cx + dx, c.cz + dz)
			snaps.append(_snap(n) if n != null else null)
			if (dx != 0 or dz != 0) and (n == null or n.state < Chunk.DECORATED):
				c.mesh_undecor |= 1 << ((dz + 1) * 3 + dx + 1)
	var tt := Time.get_ticks_usec()
	var tints := _tints(c)
	if tracing:
		_mt("  tints", Time.get_ticks_usec() - tt)
	var job := {"snaps": snaps, "light": c.light_halo_secs, "group": g, "tints": tints, "opts": mesh_opts, "bepoch": block_epoch}   # registry: the worker's own
	_submit(_job_mesh.bind(c, g, job, c.mesh_epoch, update, trd != null), _pri(c, 0) - (1000 if update else 0))
	if tracing:
		_mt("  start_mesh", Time.get_ticks_usec() - tsm)


func _job_mesh(c: Chunk, g: int, job: Dictionary, epoch: int, update: bool, use_trd: bool = false) -> void:
	var t0 := Time.get_ticks_usec()
	job["blocks"] = _thread_blocks()
	var res := Mesher.build(job)
	if use_trd and not res.is_empty():
		var om := _thread_ovl_map()
		# RenderingDevice terrain renderer: pack the quads here on the worker (native, thread-safe)
		var packed: Array = [null, null, null]
		var mi := 0
		for cls in ["opaque", "cutout", "translucent"]:
			var arrays: Array = res[cls]
			if not arrays.is_empty():
				packed[mi] = Native.inst.tr_pack(arrays, (1 if mi < 2 and section_buckets else 0), om)   # opaque / cutout: per-section buckets
			mi += 1
		res["packed"] = packed
	_push_result(["mesh", c, epoch, g, res, Time.get_ticks_usec() - t0, t0, Time.get_ticks_usec(), update, int(job.get("bepoch", 0))])


## Biome-blended grass/foliage/water colours for the 16x16 columns (surface biome).
func _tints(c: Chunk) -> PackedColorArray:
	# cached per chunk: depends only on this heightmap and which neighbour chunks are loaded (biomes are immutable)
	var mask := 0
	var bit := 1
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var nb: Chunk = chunks.get(Coords.chunk_key(c.cx + dx, c.cz + dz))
			if nb != null:
				mask |= bit << (9 if nb.state >= Chunk.DATA_READY else 0)
			bit <<= 1
	var key := (hash(c.heightmap) << 9) ^ mask
	if key == c.tints_key and c.tints_cache.size() == 1024:
		return c.tints_cache
	var res := _tints_compute(c)
	c.tints_cache = res
	c.tints_key = key
	return res


func _tints_compute(c: Chunk) -> PackedColorArray:
	if Native.ok and Native.chunkops_ok:
		var b9: Array = []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nb: Chunk = c if dx == 0 and dz == 0 else chunks.get(Coords.chunk_key(c.cx + dx, c.cz + dz))
				b9.append(nb.biomes if nb != null else null)
		return Native.inst.tints(b9, c.heightmap, c.cx, c.cz, biome_blend, biomes.grass, biomes.foliage, biomes.water, biomes.dry_foliage)[0]
	return _tints_gd(c)


func _tints_gd(c: Chunk) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(1024)
	var r := biome_blend
	for z in 16:
		for x in 16:
			var hy := c.heightmap[x + z * 16]
			var gs := Color(0, 0, 0)
			var fs := Color(0, 0, 0)
			var ws := Color(0, 0, 0)
			var ds := Color(0, 0, 0)
			var n := 0
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var wx := c.cx * 16 + x + dx * 2
					var wz := c.cz * 16 + z + dz * 2
					var nc: Chunk = c if (wx >> 4) == c.cx and (wz >> 4) == c.cz else chunks.get(Coords.chunk_key(wx >> 4, wz >> 4))
					if nc == null:
						continue
					var b := nc.biome_at(wx & 15, hy, wz & 15)
					gs += biomes.grass[b]
					fs += biomes.foliage[b]
					ws += biomes.water[b]
					ds += biomes.dry_foliage[b]
					n += 1
			if n == 0:
				n = 1
				gs = Color(0.5, 0.75, 0.35)
				fs = gs
				ws = Color(0.25, 0.46, 0.89)
				ds = Color8(0x5C, 0x3C, 0x32)
			out[x + z * 16] = gs / n
			out[256 + x + z * 16] = fs / n
			out[512 + x + z * 16] = ws / n
			out[768 + x + z * 16] = ds / n
	for i in 1024:
		out[i].a = 1.0
	return out


# ---------------------------------------------------------------- commits

func _commit_results() -> void:
	if not _batches.is_empty():
		_flush_old_batches()
	_mutex.lock()
	var res := _results
	_results = []
	_mutex.unlock()
	if res.is_empty():
		return
	for r0 in res:
		var c0: Chunk = r0[1]
		var k0: String = r0[0]
		disp_stats["commit_" + k0] = int(disp_stats.get("commit_" + k0, 0)) + 1
		if k0 == "light" or k0 == "mesh":
			# own chunk only: neighbours gate on chunk *state*, which light / mesh results don't change (relights of
			# neighbours are marked explicitly and put in the work set where they are marked)
			_work[(c0.cx << 32) | (c0.cz & 0xFFFFFFFF)] = true
			continue
		for dz0 in range(-1, 2):
			for dx0 in range(-1, 2):
				_work[((c0.cx + dx0) << 32) | ((c0.cz + dz0) & 0xFFFFFFFF)] = true
	var t0 := Time.get_ticks_usec()
	var deferred: Array = []
	for r in res:
		var kind: String = r[0]
		var c: Chunk = r[1]
		var key := Coords.chunk_key(c.cx, c.cz)
		if kind == "mesh" and (Time.get_ticks_usec() - t0) > _upload_budget_us:
			deferred.append(r)
			continue
		_inflight -= 1
		_committed += 1
		if tracing:
			var dur: int = r[3] if kind == "gen" else (r[4] if kind == "feat" or kind == "light" else (r[5] if kind == "mesh" else r[6] - r[5]))
			busy_us[kind] = int(busy_us.get(kind, 0)) + dur
			busy_n[kind] = int(busy_n.get(kind, 0)) + 1
		var alive: bool = chunks.get(key) == c and c.state != Chunk.EVICTED
		if kind == "mesh" and not _edit_batch.is_empty() and r.size() > 9 and _hold_for_batch(r, key):
			continue
		var tk0 := Time.get_ticks_usec()
		_commit_one(kind, r, c, key, alive)
		if tracing:
			last_commit_parts[kind] = int(last_commit_parts.get(kind, 0)) + Time.get_ticks_usec() - tk0
	if not deferred.is_empty():
		_mutex.lock()
		_results = deferred + _results
		_mutex.unlock()


## A commit may write blocks into loaded neighbours (features / decoration reach across chunk borders): new block
## versions for the chunk and its 8 neighbours (Collision region caches).
func _bump_around(c: Chunk) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var n: Chunk = chunks.get(Coords.chunk_key(c.cx + dx, c.cz + dz))
			if n != null:
				Chunk._bseq += 1
				n.bepoch = Chunk._bseq


## One worker result applied on the main thread.
func _commit_one(kind: String, r: Array, c: Chunk, key: int, alive: bool) -> void:
	block_epoch += 1   # any commit may write blocks (features / decoration reach into loaded neighbours)
	if true:
		match kind:
			"gen":
				_jobs_gen.erase(key)
				if not alive:
					return
				stats["generated"] += 1
				if r[4]:
					stats["loaded_from_disk"] = int(stats.get("loaded_from_disk", 0)) + 1
				stats["gen_ms"] = lerpf(stats["gen_ms"], r[3] / 1000.0, 0.1)
				_tr(c, "gen_s", r[5])
				_tr(c, "gen_e", r[6])
				_tr(c, "gen_c")
				c.from_disk = r[4]
				c.state = Chunk.DECORATED if r[4] else Chunk.DATA_READY
				block_epoch += 1
				_bump_around(c)
				if r[4]:
					c.decorated = true
					_remesh_built_against(c)
					BlockEntities.index_chunk(self, c)
					_leaf_cache_clear(c.cx, c.cz)
					BlockUpdates.on_chunk_ready(c.cx, c.cz)
				c.dirty_groups = 0x3F
			"feat":
				_jobs_feat.erase(key)
				if not alive:
					return
				c.feature_writes = r[3]
				if r.size() > 7 and r[7] != null:
					c.feature_bes = (r[7] as Chunk).feature_bes   # computed on the pristine twin
					c.feature_postproc = (r[7] as Chunk).feature_postproc
				c.features_ready = true
				_tr(c, "feat_s", r[5])
				_tr(c, "feat_e", r[6])
				_tr(c, "feat_c")
				stats["feat_ms"] = lerpf(stats.get("feat_ms", 0.0), r[4] / 1000.0, 0.1)
			"raw":
				_jobs_raw.erase(key)
				if alive:
					c.raw = r[3]
			"decor":
				_jobs_decor.erase(key)
				if not alive:
					return
				if r[3] is Chunk:
					c.adopt_decoration(r[3])
				c.state = Chunk.DECORATED
				_remesh_built_against(c)
				c.decorated = true
				_release_raw_around(c)
				block_epoch += 1
				_bump_around(c)
				BlockEntities.index_chunk(self, c)
				_leaf_cache_clear(c.cx, c.cz)
				BlockUpdates.on_chunk_ready(c.cx, c.cz)
				_tr(c, "dec_s", r[5])
				_tr(c, "dec_e", r[6])
				_tr(c, "dec_c")
				chunk_loaded.emit(c)
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var nb := get_chunk(c.cx + dx, c.cz + dz)
						if nb != null and nb != c and nb.light_valid and nb.light_partial:
							_light_dirty[Coords.chunk_key(nb.cx, nb.cz)] = true
			"light":
				if r[7]:
					_upd_inflight -= 1
				if _jobs_light.get(key, -1) == r[2]:
					_jobs_light.erase(key)
				if not alive or r[2] != c.light_epoch:
					return
				stats["lit"] += 1
				stats["light_ms"] = lerpf(stats["light_ms"], r[4] / 1000.0, 0.1)
				_tr(c, "light_s", r[5])
				_tr(c, "light_e", r[6])
				_tr(c, "light_c")
				_tr_add(c, "lights")
				var first := not c.light_valid
				var old_halo: Array = c.light_halo_secs
				c.light_halo_secs = r[3]
				c.light_valid = true
				if first:
					c.dirty_groups = 0x3F
				elif r[7] and c.shown:
					# only the groups whose light changed (every relight remeshed all of the chunk's groups one by one: with
					# flowing water the group holding the water surface waited behind the others and the flow showed late)
					c.update_groups |= _light_changed_groups(old_halo, r[3]) & _nonempty_groups(c)
					if c.update_groups != 0:
						_chain[key] = true
				else:
					c.dirty_groups |= _nonempty_groups(c)
			"mesh":
				if r[8]:
					_upd_inflight -= 1
				var g: int = r[3]
				_jobs_mesh.erase(key * 8 + g)
				if not alive:
					return
				if r.size() > 9 and int(r[9]) > int(dbg_bepoch.get(key * 8 + g, -1)):
					dbg_bepoch[key * 8 + g] = int(r[9])   # probes: newest block epoch on screen per group
				stats["meshed"] += 1
				stats["mesh_ms"] = lerpf(stats["mesh_ms"], r[5] / 1000.0, 0.1)
				var tu := Time.get_ticks_usec()
				_upload(c, g, r[4])
				if tracing and Time.get_ticks_usec() - tu > 3000:
					frame_upload_slow = Time.get_ticks_usec() - tu
				if tracing:
					_mt("  upload", Time.get_ticks_usec() - tu)
				if tracing:
					_tr(c, "mesh_s", r[6])
					c.trace["mesh_e"] = maxi(int(c.trace.get("mesh_e", 0)), r[7])
					c.trace["upload_us"] = int(c.trace.get("upload_us", 0)) + Time.get_ticks_usec() - tu
					_tr_add(c, "meshes")
				if not c.shown and c.light_valid and c.dirty_groups == 0 and not _mesh_pending(key):
					c.shown = true
					c.shown_us = Time.get_ticks_usec()
					_tr(c, "vis")


## A chunk just became decorated: neighbours whose meshes were built while it was still undecorated (their border
## faces saw its pre-decoration blocks, e.g. water before FreezeTopLayer -> ice seams along chunk borders) are rebuilt.
func _remesh_built_against(c: Chunk) -> void:
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dz == 0:
				continue
			var n := get_chunk(c.cx + dx, c.cz + dz)
			if n == null:
				continue
			var bit := 1 << ((1 - dz) * 3 + (1 - dx))   # c as seen from n
			if n.mesh_undecor & bit:
				n.mesh_undecor &= ~bit
				if n.light_valid:
					n.dirty_groups |= _nonempty_groups(n)
				_work[Coords.chunk_key(n.cx, n.cz)] = true


func _mesh_pending(key: int) -> bool:
	for g in Coords.SECTIONS / Mesher.GROUP:
		if _jobs_mesh.has(key * 8 + g):
			return true
	return false


## Chunk counts as visible: lit and every mesh group built and uploaded at least once.
func is_visible_chunk(c: Chunk) -> bool:
	return c != null and c.shown


## Mesh groups whose light differs between two Lighting.compute results: a changed section marks its group, and the
## neighbouring group when it is a group's first / last section (faces on the border read light across it).
func _light_changed_groups(old: Array, new: Array) -> int:
	var ng := Coords.SECTIONS / Mesher.GROUP
	if old.size() != new.size():
		return (1 << ng) - 1
	var m := 0
	for s in new.size():
		var a = old[s]
		var b = new[s]
		if typeof(a) == typeof(b) and a == b:
			continue
		var g := s / Mesher.GROUP
		m |= 1 << g
		if s % Mesher.GROUP == 0 and g > 0:
			m |= 1 << (g - 1)
		if s % Mesher.GROUP == Mesher.GROUP - 1 and g + 1 < ng:
			m |= 1 << (g + 1)
	return m


func _nonempty_groups(c: Chunk) -> int:
	var m := 0
	for g in Coords.SECTIONS / Mesher.GROUP:
		for s in range(g * Mesher.GROUP, g * Mesher.GROUP + Mesher.GROUP):
			if not c.is_section_air(s):
				m |= 1 << g
				break
	return m


var trd = null   # TerrainRD when the RenderingDevice terrain renderer is active (set by WorldManager)


func _upload(c: Chunk, g: int, res: Dictionary) -> void:
	if trd != null:
		trd.upload(c.cx, c.cz, g, res)
		stats["uploaded"] += 1
		return
	if c.mesh_rids.size() < Coords.SECTIONS / Mesher.GROUP:
		c.mesh_rids.resize(Coords.SECTIONS / Mesher.GROUP)
	var old = c.mesh_rids[g]
	if old != null:
		RenderingServer.free_rid(old[1])   # instance: gone from the scene now
		_free_q.append(old[0])             # mesh buffers: destroyed a few per frame (slow on the main thread)
		c.mesh_rids[g] = null
	if res.is_empty():
		return
	var mesh := RenderingServer.mesh_create()
	var fmt := RenderingServer.ARRAY_CUSTOM_RGBA_HALF << RenderingServer.ARRAY_FORMAT_CUSTOM0_SHIFT   # 8 bytes (layers < 2048 exact)
	if vertex_compress:
		fmt |= RenderingServer.ARRAY_FLAG_COMPRESS_ATTRIBUTES   # 16-bit positions / UVs (Godot attribute compression)
	var si := 0
	var verts := 0
	for pair in [["opaque", Res.mat_opaque], ["cutout", Res.mat_cutout], ["translucent", Res.mat_translucent]]:
		var arrays: Array = res[pair[0]]
		if arrays.is_empty():
			continue
		RenderingServer.mesh_add_surface_from_arrays(mesh, RenderingServer.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
		RenderingServer.mesh_surface_set_material(mesh, si, (pair[1] as Material).get_rid())
		verts += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		si += 1
	if si == 0:
		RenderingServer.free_rid(mesh)
		return
	stats["verts"] += verts
	stats["uploaded"] += 1
	var inst := RenderingServer.instance_create2(mesh, scenario)
	if debug_hide_group == g or debug_hide_group == 99:
		RenderingServer.instance_set_visible(inst, false)   # benchmark experiment only (--hidegroup=N)
	RenderingServer.instance_set_transform(inst, Transform3D(Basis(), _chunk_origin(c, g)))
	RenderingServer.instance_geometry_set_cast_shadows_setting(inst, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	c.mesh_rids[g] = [mesh, inst]


func _chunk_origin(c: Chunk, g: int) -> Vector3:
	return Vector3(c.cx * 16 - origin.x, Coords.MIN_Y + g * Mesher.GH - origin.y, c.cz * 16 - origin.z)


func set_origin(o: Vector3i) -> void:
	origin = o
	for c in chunks.values():
		for g in c.mesh_rids.size():
			var e = c.mesh_rids[g]
			if e != null:
				RenderingServer.instance_set_transform(e[1], Transform3D(Basis(), _chunk_origin(c, g)))


func _free_meshes(c: Chunk) -> void:
	if trd != null:
		trd.free_chunk(c.cx, c.cz)
	for e in c.mesh_rids:
		if e != null:
			RenderingServer.free_rid(e[1])
			_free_q.append(e[0])
	c.mesh_rids.clear()


## Mesh RIDs waiting to be destroyed: freeing GPU buffers is expensive on the main thread (D3D12/Vulkan allocator), so
## at most FREE_PER_FRAME per frame (the queue keeps up: frees and uploads happen at the same average rate).
var _free_q: Array = []
var freed_total := 0
const FREE_PER_FRAME := 4


func _drain_frees() -> void:
	var n := mini(FREE_PER_FRAME + _free_q.size() / 64, _free_q.size())
	for i in n:
		RenderingServer.free_rid(_free_q.pop_back())
	freed_total += n


# ---------------------------------------------------------------- background saving
var _save_q: Array = []              # Chunk (evicted or frozen copy) to save, or Callable to run after earlier saves
var _save_pending: Dictionary = {}   # chunk key -> Chunk queued or being saved
var _save_mutex := Mutex.new()
var _saver_alive := false


## Queue a save on the background saver (chunk must not change any more: evicted or a frozen copy).
func queue_save(c: Chunk) -> void:
	if not save_chunk_fn.is_valid():
		return
	_save_mutex.lock()
	_save_q.append(c)
	_save_pending[Coords.chunk_key(c.cx, c.cz)] = c
	var spawn := not _saver_alive
	_saver_alive = true
	_save_mutex.unlock()
	if spawn:
		WorkerThreadPool.add_task(_saver_loop)


## Run fn on the saver after every save queued so far (e.g. SaveManager.flush).
func queue_after_saves(fn: Callable) -> void:
	_save_mutex.lock()
	_save_q.append(fn)
	var spawn := not _saver_alive
	_saver_alive = true
	_save_mutex.unlock()
	if spawn:
		WorkerThreadPool.add_task(_saver_loop)


func _saver_loop() -> void:
	if thread_prio and Native.inst.has_method("set_thread_priority"):
		Native.inst.set_thread_priority(-1)
	pin_thread(false)
	while true:
		_save_mutex.lock()
		if _save_q.is_empty():
			_saver_alive = false
			_save_mutex.unlock()
			return
		var item = _save_q.pop_front()
		_save_mutex.unlock()
		if item is Callable:
			(item as Callable).call()
			continue
		var c: Chunk = item
		if save_chunk_fn.is_valid():
			save_chunk_fn.call(c)
		var key := Coords.chunk_key(c.cx, c.cz)
		_save_mutex.lock()
		if _save_pending.get(key) == c:
			_save_pending.erase(key)
		_save_mutex.unlock()


## Before a chunk at key is loaded again: make sure its pending save is in the store (main thread).
func _flush_pending_save(key: int) -> void:
	_save_mutex.lock()
	var c = _save_pending.get(key)
	if c == null:
		_save_mutex.unlock()
		return
	var qi := _save_q.find(c)
	if qi >= 0:
		_save_q.remove_at(qi)
		_save_pending.erase(key)
		_save_mutex.unlock()
		save_chunk_fn.call(c)
		return
	_save_mutex.unlock()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 5000:
		_save_mutex.lock()
		var still := _save_pending.has(key)
		_save_mutex.unlock()
		if not still:
			return
		OS.delay_usec(200)


## Synchronously finish every queued save (main thread; quit / dimension change / explicit save).
func flush_saves() -> void:
	while true:
		_save_mutex.lock()
		if _save_q.is_empty():
			var busy := _saver_alive
			_save_mutex.unlock()
			if not busy:
				return
			OS.delay_usec(500)
			continue
		var item = _save_q.pop_front()
		_save_mutex.unlock()
		if item is Callable:
			(item as Callable).call()
			continue
		var c: Chunk = item
		save_chunk_fn.call(c)
		_save_mutex.lock()
		var key := Coords.chunk_key(c.cx, c.cz)
		if _save_pending.get(key) == c:
			_save_pending.erase(key)
		_save_mutex.unlock()


var _drop_q: Array = []   # chunk keys to unload, drained a few per frame (_drain_drops)
var _unload_c := Vector2i(1 << 30, 0)   # centre of the last unload scan
var _unload_lim := -1


## Finds chunks beyond the unload distance (after the player changed chunk); they are unloaded a few per frame.
func _unload_far(pcx: int, pcz: int) -> void:
	var lim := radius + 6
	var old := _unload_c
	_unload_c = Vector2i(pcx, pcz)
	var mdx := pcx - old.x
	var mdz := pcz - old.y
	if not extra_centers.is_empty() or absi(mdx) > 3 or absi(mdz) > 3 or _unload_lim != lim:
		# full scan (first call, teleports, radius changes, extra load centres)
		_unload_lim = lim
		_drop_q.clear()
		for key in chunks:
			var c: Chunk = chunks[key]
			if maxi(absi(c.cx - pcx), absi(c.cz - pcz)) > lim and not _near_extra(c.cx, c.cz, extra_radius + 6):
				_drop_q.append(key)
		return
	# incremental: only the strip of the previous square that is outside the new one (queue kept; drains re-check)
	for z in range(old.y - lim, old.y + lim + 1):
		for x in range(old.x - lim, old.x + lim + 1):
			if maxi(absi(x - pcx), absi(z - pcz)) <= lim:
				if mdx == 0 or (mdx > 0 and x > old.x - lim + mdx - 1) or (mdx < 0 and x < old.x + lim + mdx + 1):
					if mdz == 0 or (mdz > 0 and z > old.y - lim + mdz - 1) or (mdz < 0 and z < old.y + lim + mdz + 1):
						continue
				continue
			var key := Coords.chunk_key(x, z)
			if chunks.has(key):
				_drop_q.append(key)


func _drain_drops(pcx: int, pcz: int, n: int) -> void:
	var lim := radius + 6
	while n > 0 and not _drop_q.is_empty():
		var key: int = _drop_q.pop_back()
		var c: Chunk = chunks.get(key)
		if c == null or maxi(absi(c.cx - pcx), absi(c.cz - pcz)) <= lim or _near_extra(c.cx, c.cz, extra_radius + 6):
			continue
		if c.state == Chunk.GENERATING or _jobs_decor.has(key) or _jobs_feat.has(key):
			continue
		n -= 1
		if tracing and not c.trace.is_empty():
			var tcopy := c.trace.duplicate()
			tcopy["cx"] = c.cx
			tcopy["cz"] = c.cz
			trace_log.append(tcopy)
		chunk_unloading.emit(c)
		_free_meshes(c)
		c.state = Chunk.EVICTED
		block_epoch += 1
		if c.modified and save_chunk_fn.is_valid():
			queue_save(c)   # encoded on the background saver (evicted chunks no longer change)
		c.mesh_epoch += 1
		chunks.erase(key)
		_light_dirty.erase(key)
		_light_update.erase(key)
		_next_update.erase(key)
		_chain.erase(key)
		_urgent_until.erase(key)


## Unload every chunk (entities stored, modified chunks saved) — used before a dimension change.
func unload_all() -> void:
	flush_saves()
	for r in _free_q:
		RenderingServer.free_rid(r)
	_free_q.clear()
	for key in chunks.keys():
		var c: Chunk = chunks[key]
		if c.state >= Chunk.DECORATED:
			chunk_unloading.emit(c)
			if c.modified and save_chunk_fn.is_valid():
				save_chunk_fn.call(c)


func _near_extra(cx: int, cz: int, lim: int) -> bool:
	for ec in extra_centers:
		if maxi(absi(cx - ec.x), absi(cz - ec.y)) <= lim:
			return true
	return false


func pending_jobs() -> int:
	return _inflight


func shutdown() -> void:
	flush_saves()
	for c in chunks.values():
		_free_meshes(c)
	for r in _free_q:
		RenderingServer.free_rid(r)
	_free_q.clear()
	shutting_down = true
	gen.aborted = true
	_tl_mutex.lock()
	for g in _tl_gens.values():
		g.aborted = true
	_tl_mutex.unlock()
	_q_mutex.lock()
	_inflight -= _q.size()
	_q.clear()
	_q_mutex.unlock()
	var t0 := Time.get_ticks_msec()
	while _inflight > 0 and Time.get_ticks_msec() - t0 < 10000:
		_mutex.lock()
		var n := _results.size()
		_inflight -= n
		_results.clear()
		_mutex.unlock()
		OS.delay_msec(5)
	for c in chunks.values():
		_free_meshes(c)
	chunks.clear()


func visible_groups() -> int:
	var n := 0
	for c in chunks.values():
		for e in c.mesh_rids:
			if e != null:
				n += 1
	return n
