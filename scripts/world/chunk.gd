## Chunk — one 16x384x16 column: 24 palette-compressed Sections, light, heightmaps, biome grid.
## Why: compact storage (uniform sections store only a 1-entry palette) with O(1) block access and
## in-place edits (Section methods mutate members directly, avoiding copy-on-write churn).
## Contract: get_block/set_block take LOCAL x,z (0..15) and WORLD y (-64..319). snapshot() hands
## workers COW references that stay immutable while the main thread edits.
## Invariants: Section.pal.size()==1 <=> Section is uniform (idx empty); idx is bytes while pal<=256.
class_name Chunk
extends RefCounted

enum { ABSENT, QUEUED, GENERATING, DATA_READY, DECORATED, LIGHT_READY, READY, EVICTED }


class Section:
	extends RefCounted
	var pal := PackedInt32Array([0])
	var idx := PackedByteArray()
	var wide := PackedInt32Array()
	var light := PackedByteArray()    # sky<<4|block per voxel; empty => light_u everywhere
	var light_u := 0
	var rt := -1                      # cached "palette has a random-tickable state" (-1 unknown)
	var rt_n := 0                     # palette size when rt was computed
	var rs := -1                      # cached Interest bits of the palette (-1 unknown; see Interest.section_mask)
	var rs_n := 0                     # palette size when rs was computed
	var shared := false               # arrays are referenced by a snapshot: copy before the next in-place write

	## Copy-on-write: packed arrays are shared by reference in Godot 4, so a section handed to a worker snapshot gets
	## private copies on its first later write (the snapshot keeps the old, now immutable, arrays). rt = -1 makes the
	## chunk rebuild its random-tick array references.
	func _unshare() -> void:
		pal = pal.duplicate()
		idx = idx.duplicate()
		wide = wide.duplicate()
		light = light.duplicate()
		shared = false
		rt = -1

	func get_at(i: int) -> int:
		if pal.size() == 1:
			return pal[0]
		if wide.size() > 0:
			return pal[wide[i]]
		return pal[idx[i]]

	func set_at(i: int, st: int) -> int:
		var old: int
		if shared:
			if get_at(i) == st:
				return st
			_unshare()
		if pal.size() == 1:
			old = pal[0]
			if old == st:
				return old
			idx.resize(4096)
			idx.fill(0)
			pal.append(st)
			rt = -1
			idx[i] = 1
			return old
		old = get_at(i)
		if old == st:
			return old
		var p := pal.find(st)
		if p < 0:
			p = pal.size()
			pal.append(st)
			rt = -1
			if p == 256 and wide.is_empty():
				wide.resize(4096)
				for k in 4096:
					wide[k] = idx[k]
				idx = PackedByteArray()
		if wide.size() > 0:
			wide[i] = p
		else:
			idx[i] = p
		return old

	func fill_raw(raw: PackedInt32Array, off: int) -> void:
		rt = -1
		rs = -1
		shared = false   # fresh arrays below
		var first := raw[off]
		var uniform := true
		for k in 4096:
			if raw[off + k] != first:
				uniform = false
				break
		wide = PackedInt32Array()
		if uniform:
			pal = PackedInt32Array([first])
			idx = PackedByteArray()
			return
		pal = PackedInt32Array()
		var lut := {}
		idx = PackedByteArray()
		idx.resize(4096)
		var last_v := -1
		var last_p := 0
		for k in 4096:
			var v := raw[off + k]
			var p: int
			if v == last_v:
				p = last_p
			elif lut.has(v):
				p = lut[v]
				last_v = v
				last_p = p
			else:
				p = pal.size()
				lut[v] = p
				pal.append(v)
				last_v = v
				last_p = p
				if p == 256:
					wide.resize(4096)
					for q in k:
						wide[q] = idx[q]
			if wide.size() > 0:
				wide[k] = p
			else:
				idx[k] = p
		if wide.size() > 0:
			idx = PackedByteArray()

	## Write expanded states into out[off .. off+4096).
	func expand_into(out: PackedInt32Array, off: int) -> void:
		if pal.size() == 1:
			var v := pal[0]
			for k in 4096:
				out[off + k] = v
			return
		if wide.size() > 0:
			for k in 4096:
				out[off + k] = pal[wide[k]]
		else:
			for k in 4096:
				out[off + k] = pal[idx[k]]

	func is_uniform() -> bool:
		return pal.size() == 1

	func set_light(i: int, v: int) -> void:
		if shared:
			_unshare()
		if light.is_empty():
			light.resize(4096)
			light.fill(light_u)
		light[i] = v

	func get_light(i: int) -> int:
		return light_u if light.is_empty() else light[i]


var cx: int
var cz: int
var state := ABSENT
var sections: Array = []              # Array[Section]
var heightmap := PackedInt32Array()   # first y above the highest light-blocking block per column (x + z*16)
var biomes := PackedByteArray()       # 4x4 quart columns x 96 quart levels: idx = qx + qz*4 + qy*16
var gen_surface := PackedInt32Array() # pristine terrain top solid y per column (immutable after generation)
var gen_top := PackedInt32Array()     # pristine top block state per column
var gen_floor := PackedInt32Array()   # pristine OCEAN_FLOOR height (first y above top non-fluid solid)
var decorated := false
var features_ready := false
var feature_writes := PackedInt32Array()  # [x,y,z,state,mode]* from Features.compute (origin = this chunk)
var feature_bes: Dictionary = {}          # world Vector3i -> block entity data produced by this chunk's features/structures
var feature_postproc := PackedInt32Array() # [x,y,z]* structure blocks marked for shape post-processing (Java markPosForPostprocessing)
var light_valid := false
var light_partial := false            # lit while some 3x3 neighbour was not yet decorated (relight pending)
var light_halo_secs: Array = []       # 24 x (PackedByteArray 18x18x16 | int uniform), from Lighting.compute
var light_epoch := 0
var mesh_epoch := 0
## Collision version for caches keyed by region (Collision): a fresh value from one global sequence whenever this
## chunk's collision may have changed (set_block, generated / decorated sections installed), so a reloaded chunk never
## repeats an old value.
static var _bseq := 0
var bepoch := 0
var mesh_undecor := 0                 # 3x3 neighbours (bit (dz+1)*3+(dx+1)) still undecorated when a mesh group was last built
var modified := false                 # contains player edits -> must be saved
var from_disk := false                # loaded from a save (decorated data, no pristine heightmaps)
var gen_ticked := false               # worldgen fluid ticks queued (BlockUpdates.gen_fluid_ticks)
var raw: Chunk = null                 # from_disk only: the pristine generated terrain, regenerated on demand so this chunk's
                                      # features (and its neighbours' features) are computed exactly as on first generation
var dirty_groups := 0                 # bitmask of mesh groups needing rebuild (pipeline progress: first build, relight)
var update_groups := 0
var tints_cache := PackedColorArray()   # ChunkManager._tints result
var rt_secs := PackedInt32Array()      # sections whose palette has a random-tickable state (BlockUpdates)
var rt_dirty := true
var _snap: Array = []    # cached snapshot() (dropped on section writes)
var rt_listed := false   # scanned into BlockUpdates' cached random-tick area (its changes refresh that list)
var rt_data: Array = []
var shown_us := 0                      # Time.get_ticks_usec() when the chunk first became visible (always recorded)
var refs_gen := 0                      # bumped whenever a section's arrays may have been replaced (see sec_refs)
var _refs: Array = []
var _refs_gen := -1                # [rt_secs, pal, idx, wide per listed section]: live refs for native rt_sample
var tints_key := -1                # bitmask of groups changed by block edits after the chunk was shown (throttled)
var shown := false                    # every group built + uploaded at least once
var mesh_rids: Array = []             # per group: [mesh_rid, instance_rid] (owned by ChunkManager)
var block_entities: Dictionary = {}   # packed local pos -> Dictionary
var scheduled: Array = []             # scheduled ticks
var unknown_states: Dictionary = {}   # packed pos -> original state string (unknown IDs round-trip)
var saved_entities: Array = []        # serialized entities restored when the chunk loads
var last_access := 0
var trace: Dictionary = {}              # perf: stage timestamps (usec, main thread only; ChunkManager.tracing)
var inhabited := 0


func _init(x: int = 0, z: int = 0) -> void:
	cx = x
	cz = z
	sections.resize(Coords.SECTIONS)
	for s in Coords.SECTIONS:
		sections[s] = Section.new()
	heightmap.resize(256)
	heightmap.fill(Coords.MIN_Y)
	biomes.resize(16 * 96)


func get_block(lx: int, y: int, lz: int) -> int:
	if y < Coords.MIN_Y or y >= Coords.MAX_Y:
		return 0
	var sec: Section = sections[(y - Coords.MIN_Y) >> 4]
	return sec.get_at(((y & 15) << 8) | (lz << 4) | lx)


func set_block(lx: int, y: int, lz: int, st: int) -> int:
	if y < Coords.MIN_Y or y >= Coords.MAX_Y:
		return 0
	var sec: Section = sections[(y - Coords.MIN_Y) >> 4]
	var old := sec.set_at(((y & 15) << 8) | (lz << 4) | lx, st)
	if old != st:
		# only changes that can alter collision boxes (flowing water / air churn left every cache valid)
		var fl: PackedInt32Array = Res.blocks.st_flags
		var nfl := fl.size()
		if (old > 0 and (old >= nfl or (fl[old] & BlockRegistry.F_COLLIDE) != 0)) or (st > 0 and (st >= nfl or (fl[st] & BlockRegistry.F_COLLIDE) != 0)):
			_bseq += 1
			bepoch = _bseq
		_snap = []
		refs_gen += 1   # an in-place write may have copied a packed array another holder shared: sec_refs must rebuild
	if sec.rt < 0:
		if rt_listed and not rt_dirty:
			BlockUpdates.rt_chunk_dirty(self)
		rt_dirty = true
		refs_gen += 1
	return old


## Fill all sections from a full-column raw array (98304 entries, index ((y-MIN_Y)<<8)|(z<<4)|x).
func fill_from_column(col: PackedInt32Array) -> void:
	_snap = []
	if rt_listed and not rt_dirty:
		BlockUpdates.rt_chunk_dirty(self)
	rt_dirty = true
	refs_gen += 1
	for s in Coords.SECTIONS:
		(sections[s] as Section).fill_raw(col, s * 4096)


func to_column() -> PackedInt32Array:
	var col := PackedInt32Array()
	col.resize(98304)
	for s in Coords.SECTIONS:
		(sections[s] as Section).expand_into(col, s * 4096)
	return col


func is_section_air(s: int) -> bool:
	var sec: Section = sections[s]
	return sec.pal.size() == 1 and sec.pal[0] == 0


func get_light(lx: int, y: int, lz: int) -> int:
	if y >= Coords.MAX_Y:
		return 0xF0
	if y < Coords.MIN_Y:
		return 0
	var sec: Section = sections[(y - Coords.MIN_Y) >> 4]
	return sec.get_light(((y & 15) << 8) | (lz << 4) | lx)


func biome_at(lx: int, y: int, lz: int) -> int:
	var qy := clampi((y - Coords.MIN_Y) >> 2, 0, 95)
	return biomes[(lx >> 2) + (lz >> 2) * 4 + qy * 16]


func recompute_heightmap(blocks: BlockRegistry) -> void:
	for z in 16:
		for x in 16:
			heightmap[x + z * 16] = _column_top(x, z, blocks)


func _column_top(x: int, z: int, blocks: BlockRegistry) -> int:
	for s in range(Coords.SECTIONS - 1, -1, -1):
		var sec: Section = sections[s]
		if sec.pal.size() == 1 and blocks.st_opacity[sec.pal[0]] == 0:
			continue
		var base := Coords.MIN_Y + s * 16
		for ly in range(15, -1, -1):
			if blocks.st_opacity[sec.get_at((ly << 8) | (z << 4) | x)] > 0:
				return base + ly + 1
	return Coords.MIN_Y


func update_height_at(x: int, y: int, z: int, blocks: BlockRegistry) -> void:
	var i := x + z * 16
	var st := get_block(x, y, z)
	if blocks.st_opacity[st] > 0:
		if y + 1 > heightmap[i]:
			heightmap[i] = y + 1
	elif y + 1 == heightmap[i]:
		heightmap[i] = _column_top(x, z, blocks)


## Immutable view for worker jobs: per-section [pal, idx, wide, light, light_u] references; the sections are marked
## shared so the next main-thread write copies them first (Section._unshare) and the snapshot never changes
## (test "snapshot immutable"). O(24) instead of copying every array.
## Section references for worker jobs (read-only there); the sections become copy-on-write. Cached until the next
## section write (set_block / fill_from_column / set_sections drop it), so jobs started between edits share one.
func snapshot() -> Array:
	if not _snap.is_empty():
		return _snap
	var out: Array = []
	out.resize(Coords.SECTIONS)
	for s in Coords.SECTIONS:
		var sec: Section = sections[s]
		sec.shared = true
		out[s] = [sec.pal, sec.idx, sec.wide, sec.light, sec.light_u]
	_snap = out
	return out


## Immutable copy for background saving (SaveManager.encode_chunk reads only these fields).
func frozen_copy() -> Chunk:
	var c := Chunk.new(cx, cz)
	for s in Coords.SECTIONS:
		var src: Section = sections[s]
		var dst: Section = c.sections[s]
		src.shared = true   # copy-on-write: the live section copies before its next edit
		dst.pal = src.pal
		dst.idx = src.idx
		dst.wide = src.wide
	c.biomes = biomes.duplicate()
	c.gen_surface = gen_surface.duplicate()
	c.gen_top = gen_top.duplicate()
	c.block_entities = block_entities.duplicate(true)
	c.saved_entities = saved_entities.duplicate(true)
	c.unknown_states = unknown_states.duplicate(true)
	c.scheduled = scheduled.duplicate(true)
	c.feature_writes = feature_writes
	c.modified = modified
	c.state = state
	return c


## Private copy for a decoration job (created on the main thread): sections share the live arrays copy-on-write, so
## the worker decorates without touching the live chunk. The live chunk used to be decorated in place on the worker
## while the main thread snapshotted it for a neighbour's mesh / light job: a snapshot taken mid-swap kept the
## undecorated sections (e.g. water before FreezeTopLayer) cached, and every later neighbour mesh drew faces against
## them (ice seams along chunk borders).
func decor_shell() -> Chunk:
	var c := Chunk.new(cx, cz)
	for s in Coords.SECTIONS:
		var src: Section = sections[s]
		var dst: Section = c.sections[s]
		src.shared = true
		dst.shared = true
		dst.pal = src.pal
		dst.idx = src.idx
		dst.wide = src.wide
		dst.rt = src.rt
		dst.rs = -1
	c.biomes = biomes
	c.heightmap = heightmap.duplicate()
	c.gen_surface = gen_surface
	c.gen_top = gen_top
	c.gen_floor = gen_floor
	c.block_entities = block_entities.duplicate()
	c.state = state
	return c


## Main thread, decoration commit: take over the decorated sections / heightmap / block entities of the job's shell.
func adopt_decoration(shell: Chunk) -> void:
	_bseq += 1
	bepoch = _bseq
	for s in Coords.SECTIONS:
		var src: Section = shell.sections[s]
		var dst: Section = sections[s]
		dst.pal = src.pal
		dst.idx = src.idx
		dst.wide = src.wide
		dst.rt = -1
		dst.rs = -1
		dst.shared = true   # the shell (and native results) may still reference the arrays
	heightmap = shell.heightmap
	block_entities = shell.block_entities
	_snap = []
	if rt_listed and not rt_dirty:
		BlockUpdates.rt_chunk_dirty(self)
	rt_dirty = true
	refs_gen += 1


## Install packed sections from native code (RecraftNative.chunk_finish / chunk_decorate): [pal, idx, wide] x 24.
func set_sections(arr: Array) -> void:
	_bseq += 1
	bepoch = _bseq
	_snap = []
	for s in Coords.SECTIONS:
		var sec: Section = sections[s]
		var e: Array = arr[s]
		sec.pal = e[0]
		sec.idx = e[1]
		sec.wide = e[2]
		sec.rt = -1
		sec.rs = -1
		sec.shared = true   # the arrays may also be referenced by the native caller's result: copy before editing
	if rt_listed and not rt_dirty:
		BlockUpdates.rt_chunk_dirty(self)
	rt_dirty = true
	refs_gen += 1


## Live references [pal, idx, wide] x 24 for native read-only queries on the main thread (RecraftNative.leaf_search);
## rebuilt after any section array replacement (refs_gen).
var leaf_ok: Dictionary = {}   # random-tick leaf decay: local keys of leaves found supported by a log (cleared on nearby log/leaf changes)


func sec_refs() -> Array:
	if _refs_gen != refs_gen or _refs.is_empty():
		_refs_gen = refs_gen
		var a: Array = []
		a.resize(Coords.SECTIONS * 3)
		for s in Coords.SECTIONS:
			var sec: Section = sections[s]
			a[s * 3] = sec.pal
			a[s * 3 + 1] = sec.idx
			a[s * 3 + 2] = sec.wide
		_refs = a
	return _refs


## Section storage by reference (no copies) for read-only native expansion (RecraftNative.region_flat).
func raw_sections() -> Array:
	var out: Array = []
	out.resize(Coords.SECTIONS)
	for s in Coords.SECTIONS:
		var sec: Section = sections[s]
		out[s] = [sec.pal, sec.idx, sec.wide]
	return out


## Expand a snapshot (from snapshot()) to a full column array.
static func snapshot_column(snap: Array) -> PackedInt32Array:
	var col := PackedInt32Array()
	col.resize(98304)
	for s in Coords.SECTIONS:
		var e: Array = snap[s]
		var pal: PackedInt32Array = e[0]
		var off := s * 4096
		if pal.size() == 1:
			var v := pal[0]
			if v != 0:
				for k in 4096:
					col[off + k] = v
			continue
		var wide: PackedInt32Array = e[2]
		if wide.size() > 0:
			for k in 4096:
				col[off + k] = pal[wide[k]]
		else:
			var idx: PackedByteArray = e[1]
			for k in 4096:
				col[off + k] = pal[idx[k]]
	return col
