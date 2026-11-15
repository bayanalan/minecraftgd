## Structures â€” 26.3 data-driven structure generation (source D: Java ChunkGenerator.createStructures,
## RandomSpreadStructurePlacement, ConcentricRingsStructurePlacement, JigsawPlacement/Placer, pool elements,
## processors) plus template-based simple structures and approximate legacy-piece structures (StructuresLegacy).
## Starts are computed once per (structure set, start chunk) in a shared thread-safe cache; every chunk places only
## the parts of pieces inside itself during its feature stage, per generation step, before that step's features.
## Terrain adaptation: Java Beardifier from rigid pool pieces and the jigsaw junctions between pieces (beard_pieces ->
## native density).
## APPROXIMATIONS: noise-based ground height uses the density column without
## aquifers (sea level used for water); pool aliases other than direct are ignored.
class_name Structures
extends RefCounted

const STEP_NAMES := ["raw_generation", "lakes", "local_modifications", "underground_structures", "surface_structures", "strongholds",
	"underground_ores", "underground_decoration", "fluid_springs", "vegetal_decoration", "top_layer_modification"]
const SEARCH := 8   # chunks: max horizontal reach of a structure from its start chunk

static var _starts: Dictionary = {}
static var _heights: Dictionary = {}
static var _sm := Mutex.new()
static var old_scan := false   # verification: original per-step scan
static var _computing: Dictionary = {}   # start keys being assembled by some thread (others wait instead of duplicating)

var gen: VanillaGenerator
var f: Features
var sets: Array = []            # [{name, placement, entries: [{name, weight, cfg}]}]
var structures: Dictionary = {} # name -> cfg (with compiled biome id set + step)
var pools: Dictionary = {}
var proc_lists: Dictionary = {}
var by_step: Array = []         # step -> Array[structure names] (alphabetical, Java index order)
var _uid := 0
var _el_cache: Dictionary = {}    # uid*4+rot -> [box_at_zero, jigsaws_at_zero, expansion_max]
var stats := {"ffh_calls": 0, "ffh_ms": 0.0, "jigsaw_ms": 0.0}


func _init(g: VanillaGenerator, feats: Features) -> void:
	gen = g
	f = feats


func setup() -> void:
	for s in STEP_NAMES.size():
		by_step.append([])
	var present := {}
	for bi in gen.biomes.names.size():
		present[gen.biomes.names[bi]] = bi
	var dim_biomes := _dimension_biomes()
	for path in Res.list_files("data/minecraft/worldgen/structure_set/", ".json"):
		var j = Res.read_json(path)
		if not (j is Dictionary):
			continue
		var entries: Array = []
		for e in j.get("structures", []):
			var nm := str(e.get("structure", "")).trim_prefix("minecraft:")
			var cfg := _structure(nm, present)
			if cfg.is_empty():
				continue
			var ok := false
			for b in cfg["biomes"]:
				if dim_biomes.has(b):
					ok = true
					break
			if ok:
				entries.append({"name": nm, "weight": int(e.get("weight", 1)), "cfg": cfg})
		if entries.is_empty():
			continue
		sets.append({"name": path.get_file().get_basename(), "placement": j.get("placement", {}), "entries": entries})
	for nm in structures:
		var cfg2: Dictionary = structures[nm]
		(by_step[cfg2["step"]] as Array).append(nm)
	for s in by_step.size():
		(by_step[s] as Array).sort()


func _dimension_biomes() -> Dictionary:
	var out := {}
	match gen.dimension:
		"the_nether":
			for b in ["nether_wastes", "soul_sand_valley", "crimson_forest", "warped_forest", "basalt_deltas"]:
				out[gen.biomes.id(b)] = true
		"the_end":
			for b in ["the_end", "end_highlands", "end_midlands", "small_end_islands", "end_barrens"]:
				out[gen.biomes.id(b)] = true
		_:
			for bi in gen.biomes.names.size():
				var n: String = gen.biomes.names[bi]
				if not (n in ["nether_wastes", "soul_sand_valley", "crimson_forest", "warped_forest", "basalt_deltas", "the_end", "end_highlands", "end_midlands", "small_end_islands", "end_barrens"]):
					out[bi] = true
	return out


func _structure(nm: String, present: Dictionary) -> Dictionary:
	if structures.has(nm):
		return structures[nm]
	var j = Res.read_json("data/minecraft/worldgen/structure/%s.json" % nm)
	if not (j is Dictionary):
		return {}
	var cfg: Dictionary = j.duplicate()
	var ids := {}
	var bl = j.get("biomes", [])
	if bl is String:
		if bl.begins_with("#"):
			for b in Tags.resolve("worldgen/biome", bl):
				if present.has(b):
					ids[present[b]] = true
		elif present.has(bl.trim_prefix("minecraft:")):
			ids[present[bl.trim_prefix("minecraft:")]] = true
	elif bl is Array:
		for b2 in bl:
			var bn := str(b2).trim_prefix("minecraft:")
			if present.has(bn):
				ids[present[bn]] = true
	cfg["biomes"] = ids
	cfg["step"] = maxi(STEP_NAMES.find(str(j.get("step", "surface_structures"))), 0)
	cfg["name"] = nm
	structures[nm] = cfg
	return cfg


# ------------------------------------------------------------------ placement (structure sets)

static func large_feature_seed(world_seed: int, x: int, z: int) -> RandomSources.LegacyRandom:
	var r := RandomSources.LegacyRandom.new(world_seed)
	var a := r.next_long()
	var b := r.next_long()
	r.set_seed((x * a) ^ (z * b) ^ world_seed)
	return r


## Start chunks of `set` that may reach chunk (cx, cz).
func _candidates(st: Dictionary, cx: int, cz: int, search: int = SEARCH) -> Array:
	var pl: Dictionary = st["placement"]
	var t := str(pl.get("type", "")).trim_prefix("minecraft:")
	var out: Array = []
	if t == "random_spread":
		var spacing := maxi(int(pl.get("spacing", 32)), 1)
		var sep := int(pl.get("separation", 8))
		var salt := int(pl.get("salt", 0))
		var tri := str(pl.get("spread_type", "linear")) == "triangular"
		if Native.ok and Native.features_ok:
			var pr: PackedInt32Array = Native.inst.rs_candidates(gen.seed, spacing, sep, salt, 1 if tri else 0, float(pl.get("frequency", 1.0)),
				1 if str(pl.get("frequency_reduction_method", "default")) == "legacy_type_3" else 0, cx, cz, search)[0]
			for k in range(0, pr.size(), 2):
				out.append(Vector2i(pr[k], pr[k + 1]))
			return out
		for rz in range(floori(float(cz - search) / spacing), floori(float(cz + search) / spacing) + 1):
			for rx in range(floori(float(cx - search) / spacing), floori(float(cx + search) / spacing) + 1):
				var r := RandomSources.LegacyRandom.new(0)
				r.set_seed(rx * 341873128712 + rz * 132897987541 + gen.seed + salt)
				var k := maxi(spacing - sep, 1)
				var ox: int = (r.next_int_bound(k) + r.next_int_bound(k)) / 2 if tri else r.next_int_bound(k)
				var oz: int = (r.next_int_bound(k) + r.next_int_bound(k)) / 2 if tri else r.next_int_bound(k)
				var sx := rx * spacing + ox
				var sz := rz * spacing + oz
				if absi(sx - cx) > search or absi(sz - cz) > search:
					continue
				var freq := float(pl.get("frequency", 1.0))
				if freq < 1.0:
					var meth := str(pl.get("frequency_reduction_method", "default"))
					var fr: RandomSources.LegacyRandom
					if meth == "legacy_type_3":
						fr = large_feature_seed(gen.seed, sx, sz)
						if fr.next_double() >= freq:
							continue
					else:
						fr = RandomSources.LegacyRandom.new(0)
						fr.set_seed(salt * 341873128712 + sx * 132897987541 + gen.seed + sz)
						if fr.next_float() >= freq:
							continue
				out.append(Vector2i(sx, sz))
	elif t == "concentric_rings":
		# snapping moves a ring by at most 112 blocks (7 chunks): only snap rings that could land nearby
		var raw := _ring_raw(st)
		for i in raw.size():
			var v0: Vector2i = raw[i][0]
			if absi(v0.x - cx) <= search + 8 and absi(v0.y - cz) <= search + 8:
				var v := _ring_snapped(st, i)
				if absi(v.x - cx) <= search and absi(v.y - cz) <= search:
					out.append(v)
	return out


static var _rings: Dictionary = {}   # "dim|set|seed" -> Array[[Vector2i unsnapped, fork_seed]]
static var _snaps: Dictionary = {}   # "dim|set|seed|i" -> Vector2i


## Java ChunkGeneratorStructureState.generateRingPositions: ring centres + the forked random each ring's
## biome snap uses (shared across worker threads; snapping is done lazily per ring).
func _ring_raw(st: Dictionary) -> Array:
	var key := "%s|%s|%d" % [gen.dimension, st["name"], gen.seed]
	_sm.lock()
	var cached = _rings.get(key)
	_sm.unlock()
	if cached != null:
		return cached
	var pl: Dictionary = st["placement"]
	var dist := int(pl.get("distance", 32))
	var count := int(pl.get("count", 128))
	var spread := int(pl.get("spread", 3))
	var r := RandomSources.LegacyRandom.new(gen.seed)
	var d := r.next_double() * PI * 2.0
	var l := 0
	var m := 0
	var out: Array = []
	var k := spread
	for n in count:
		var e := float(4 * dist + dist * m * 6) + (r.next_double() - 0.5) * float(dist) * 2.5
		var o := int(roundf(cos(d) * e))
		var p := int(roundf(sin(d) * e))
		out.append([Vector2i(o, p), r.next_long()])
		d += PI * 2.0 / float(k)
		l += 1
		if l == k:
			m += 1
			l = 0
			k += 2 * k / (m + 1)
			k = mini(k, count - n)
			d += r.next_double() * PI * 2.0
	_sm.lock()
	_rings[key] = out
	_sm.unlock()
	return out


func _ring_snapped(st: Dictionary, i: int) -> Vector2i:
	var key := "%s|%s|%d|%d" % [gen.dimension, st["name"], gen.seed, i]
	_sm.lock()
	var v = _snaps.get(key)
	_sm.unlock()
	if v != null:
		return v
	var e: Array = _ring_raw(st)[i]
	var o: Vector2i = e[0]
	var res := _snap_ring(o.x, o.y, RandomSources.LegacyRandom.new(int(e[1])), st["placement"])
	_sm.lock()
	_snaps[key] = res
	_sm.unlock()
	return res


## BiomeSource.findBiomeHorizontal(center, 112, preferred) at quart resolution (reservoir sampling like Java).
func _snap_ring(o: int, p: int, r: RandomSources.LegacyRandom, pl: Dictionary) -> Vector2i:
	var pref: Dictionary = Tags.resolve("worldgen/biome", str(pl.get("preferred_biomes", "")))
	var bx := o * 16 + 8
	var bz := p * 16 + 8
	if pref.is_empty() or gen.end_biomes:
		return Vector2i(o, p)
	# coarse search (every 4th quart) keeps this affordable in GDScript; documented approximation
	var qi := bx >> 2
	var qj := bz >> 2
	var kq := 28
	var found := Vector2i(o, p)
	var cnt := 0
	var ctx := DensityFunctions.Ctx.new(gen.dfc.node_count())
	for dz in range(-kq, kq + 1, 4):
		for dx in range(-kq, kq + 1, 4):
			var x := (qi + dx) << 2
			var z := (qj + dz) << 2
			var nm := gen.climate.find(gen.r_temp.point(ctx, x, 0, z), gen.r_veg.point(ctx, x, 0, z), gen.r_cont.point(ctx, x, 0, z), gen.r_eros.point(ctx, x, 0, z), gen.r_depth.point(ctx, x, 0, z), gen.r_ridges.point(ctx, x, 0, z))
			if not pref.has(nm):
				continue
			if cnt == 0 or r.next_int_bound(cnt + 1) == 0:
				found = Vector2i(x >> 4, z >> 4)
			cnt += 1
	return found


## Nearest stronghold start chunk (eye of ender / locate): nearest unsnapped ring, then snapped.
func nearest_stronghold(cx: int, cz: int) -> Vector2i:
	for st in sets:
		if str(st["placement"].get("type", "")).ends_with("concentric_rings"):
			var raw := _ring_raw(st)
			var best := -1
			var bd := 1 << 62
			for i in raw.size():
				var v: Vector2i = raw[i][0]
				var d: int = (v.x - cx) * (v.x - cx) + (v.y - cz) * (v.y - cz)
				if d < bd:
					bd = d
					best = i
			if best >= 0:
				return _ring_snapped(st, best)
	return Vector2i(1 << 29, 0)

# ------------------------------------------------------------------ starts (cached, shared)

func _start(st: Dictionary, sc: Vector2i) -> Dictionary:
	var key := "%s|%s|%d|%d,%d" % [gen.dimension, st["name"], gen.seed, sc.x, sc.y]
	_sm.lock()
	if _starts.has(key):
		var v: Dictionary = _starts[key]
		_sm.unlock()
		return v
	if _computing.has(key):
		# another worker is assembling this start: wait for its result (same deterministic value)
		_sm.unlock()
		var tw := Time.get_ticks_msec()
		var warned := false
		while Time.get_ticks_msec() - tw < 10000:
			OS.delay_msec(2)
			if not warned and Time.get_ticks_msec() - tw > 1000:
				warned = true
				printerr("[struct] waited > 1 s for start %s (thread %d)" % [key, OS.get_thread_caller_id()])
			_sm.lock()
			if _starts.has(key):
				var v2: Dictionary = _starts[key]
				_sm.unlock()
				return v2
			var still := _computing.has(key)
			_sm.unlock()
			if not still or gen.aborted:
				break
		_sm.lock()
	_computing[key] = true
	_sm.unlock()
	var tms := Time.get_ticks_usec()
	var res := _make_start(st, sc)
	var dms := (Time.get_ticks_usec() - tms) / 1000.0
	if dms > 300.0:
		printerr("[struct] start %s at %s: %.0f ms -> %s, pieces %d, stats %s" % [st["name"], str(sc), dms, str(res.get("structure", "-")), (res.get("pieces", []) as Array).size(), JSON.stringify(stats)])
	_sm.lock()
	if _starts.size() > 4000:
		_starts.clear()
	_starts[key] = res
	_computing.erase(key)
	_sm.unlock()
	return res


var _spawn_sets: Array = []
var _spawn_sets_ready := false
var _spawn_q: Dictionary = {}   # start keys computed in the background for spawn lookups


## Java NaturalSpawner.mobsAt + ChunkGenerator.getMobsAt, the structure part: a monster on nether bricks inside a
## fortress's box gets the fortress enemies; otherwise the first structure here with spawn_overrides for the category
## (by piece or by its whole box) replaces the biome list. Returns the spawner entries, [] for "nothing spawns", or
## null (the biome list applies). Main thread: only cached starts are read, missing ones are made on a worker.
func spawn_override(x: int, y: int, z: int, category: String, below_name: String):
	if not _spawn_sets_ready:
		_spawn_sets_ready = true
		for st in sets:
			if str((st["placement"] as Dictionary).get("type", "")).trim_prefix("minecraft:") != "random_spread":
				continue
			for e in st["entries"]:
				var cfg0: Dictionary = e.get("cfg", {})
				if cfg0.has("spawn_overrides") and not (cfg0["spawn_overrides"] as Dictionary).is_empty():
					_spawn_sets.append(st)
					break
	if _spawn_sets.is_empty():
		return null
	var p := Vector3i(x, y, z)
	var hits: Array = []
	for st in _spawn_sets:
		for sc in _candidates(st, x >> 4, z >> 4):
			var key := "%s|%s|%d|%d,%d" % [gen.dimension, st["name"], gen.seed, sc.x, sc.y]
			_sm.lock()
			var res = _starts.get(key)
			_sm.unlock()
			if res == null:
				if not _spawn_q.has(key):
					if _spawn_q.size() > 2048:
						_spawn_q.clear()
					_spawn_q[key] = true
					WorkerThreadPool.add_task(_start.bind(st, sc))
				continue
			if (res as Dictionary).is_empty():
				continue
			var b: Array = res["box"]
			if p.x >= b[0].x and p.x <= b[1].x and p.y >= b[0].y and p.y <= b[1].y and p.z >= b[0].z and p.z <= b[1].z:
				hits.append(res)
	if hits.is_empty():
		return null
	if category == "monster" and below_name == "nether_bricks":
		for res2 in hits:
			if str(res2["structure"]) == "fortress":
				return structures["fortress"]["spawn_overrides"]["monster"]["spawns"]
	for res3 in hits:
		var cfg: Dictionary = structures.get(str(res3["structure"]), {})
		var ovs: Dictionary = cfg.get("spawn_overrides", {})
		if not ovs.has(category):
			continue
		var ov: Dictionary = ovs[category]
		var ok := str(ov.get("bounding_box", "piece")) == "full"
		if not ok:
			for pc in res3.get("pieces", []):
				var pb: Array = pc.get("sbox", pc["box"])
				if p.x >= pb[0].x and p.x <= pb[1].x and p.y >= pb[0].y and p.y <= pb[1].y and p.z >= pb[0].z and p.z <= pb[1].z:
					ok = true
					break
		if ok:
			return ov.get("spawns", [])
	return null

## /locate: nearest start of the named structure within max_r units of its set's spacing (placement + biome stub check only). skip:
## "name cx cz" keys of starts to pass over (explorer maps skip structures earlier maps found: ExplorerMaps).
func locate(name: String, cx: int, cz: int, max_r: int = 100, skip: Dictionary = {}) -> Dictionary:
	if name == "stronghold":
		var s := nearest_stronghold(cx, cz)
		return {"chunk": s} if s.x < (1 << 28) else {}
	var best := {}
	var bd := 1 << 60
	for st in sets:
		var has := false
		for e in st["entries"]:
			if str(e["name"]) == name:
				has = true
		if not has:
			continue
		# wiki /locate (Java): "the horizontal search range is 201x201 units of the Structure's spacing" (mansions
		# +-128,000 blocks); explorer maps search the same way (wiki Explorer Map)
		var pl: Dictionary = st["placement"]
		var spacing := maxi(int(pl.get("spacing", 1)), 1) if str(pl.get("type", "")).trim_prefix("minecraft:") == "random_spread" else 1
		var cand: Array = _candidates(st, cx, cz, max_r * spacing)
		# nearest first: distance keys sorted natively (a lambda sort over the ~40000 candidates took ~0.5 s)
		var keys := PackedInt64Array()
		keys.resize(cand.size())
		var c0 := Vector2i(cx, cz)
		for ki in cand.size():
			var cv: Vector2i = cand[ki]
			keys[ki] = ((cv - c0).length_squared() << 20) | ki
		keys.sort()
		for kk in keys:
			var sc: Vector2i = cand[kk & 0xFFFFF]
			var d: int = kk >> 20
			if d >= bd:
				break
			if _choose(st, sc) == name and (skip.is_empty() or not skip.has("%s %d %d" % [name, sc.x, sc.y])):
				bd = d
				best = {"chunk": sc}
				break
	return best


## Which structure of the set would start at sc (stub/biome checks only, same random order as _make_start).
func _choose(st: Dictionary, sc: Vector2i) -> String:
	var entries: Array = (st["entries"] as Array).duplicate()
	var r := large_feature_seed(gen.seed, sc.x, sc.y)
	var total := 0
	for e in entries:
		total += int(e["weight"])
	while not entries.is_empty() and total > 0:
		var k := 0
		if entries.size() > 1 or (st["entries"] as Array).size() > 1:
			var j := r.next_int_bound(total)
			for e in entries:
				j -= int(e["weight"])
				if j < 0:
					break
				k += 1
		k = mini(k, entries.size() - 1)
		var e2: Dictionary = entries[k]
		if _stub_ok(e2["cfg"], sc):
			return str(e2["name"])
		entries.remove_at(k)
		total -= int(e2["weight"])
	return ""


func _stub_ok(cfg: Dictionary, sc: Vector2i) -> bool:
	var r := large_feature_seed(gen.seed, sc.x, sc.y)
	if str(cfg.get("type", "")).ends_with("jigsaw"):
		var stub := _jigsaw_stub(cfg, sc, r)
		if stub.is_empty():
			return false
		var c: Vector3i = stub["center"]
		return (cfg["biomes"] as Dictionary).has(biome_id_at(c.x, c.y, c.z))
	var t := str(cfg.get("type", "")).trim_prefix("minecraft:")
	if t == "woodland_mansion":
		# WoodlandMansionStructure.findGenerationPoint: lowest corner of the rotated 5 x 5 box >= 60, biome at the stub
		var mrot := r.next_int_bound(4)
		var mi := -5 if mrot == 1 or mrot == 2 else 5
		var mj := -5 if mrot == 2 or mrot == 3 else 5
		var mk := sc.x * 16 + 7
		var ml := sc.y * 16 + 7
		var mlo := 1 << 30
		for cxz in [Vector2i(mk, ml), Vector2i(mk, ml + mj), Vector2i(mk + mi, ml), Vector2i(mk + mi, ml + mj)]:
			mlo = mini(mlo, base_height(cxz.x, cxz.y, false) - 1)
		return mlo >= 60 and (cfg["biomes"] as Dictionary).has(biome_id_at(mk, mlo, ml))
	if t == "end_city":
		# EndCityStructure.findGenerationPoint: the lowest corner of the rotated 5 x 5 box must reach y 60
		var rot := r.next_int_bound(4)
		var ci := -5 if rot == 1 or rot == 2 else 5
		var cj := -5 if rot == 2 or rot == 3 else 5
		var ek := sc.x * 16 + 7
		var el := sc.y * 16 + 7
		for cxz in [Vector2i(ek, el), Vector2i(ek, el + cj), Vector2i(ek + ci, el), Vector2i(ek + ci, el + cj)]:
			if base_height(cxz.x, cxz.y, false) - 1 < 60:
				return false
	if t == "ocean_monument":
		# the stub biome first (cheap), then the 29-block surrounding check
		if not (cfg["biomes"] as Dictionary).has(biome_id_at(sc.x * 16 + 8, _stub_y(cfg, sc.x * 16 + 8, sc.y * 16 + 8), sc.y * 16 + 8)):
			return false
		return JavaPieces.monument_surroundings_ok(self, sc)
	if t == "desert_pyramid" or t == "jungle_temple":
		# SinglePieceStructure.findGenerationPoint: nothing when the lowest box corner is below sea level (Java's locate
		# runs the same check through StructureCheck)
		var size := Vector2i(21, 21) if t == "desert_pyramid" else Vector2i(12, 15)
		var x0 := sc.x * 16
		var z0 := sc.y * 16
		for cxz in [Vector2i(x0, z0), Vector2i(x0, z0 + size.y), Vector2i(x0 + size.x, z0), Vector2i(x0 + size.x, z0 + size.y)]:
			if base_height(cxz.x, cxz.y, false) - 1 < gen.sea_level:
				return false
	return (cfg["biomes"] as Dictionary).has(biome_id_at(sc.x * 16 + 8, _stub_y(cfg, sc.x * 16 + 8, sc.y * 16 + 8), sc.y * 16 + 8))


## Height of the generation stub whose biome Java checks (Structure.isValidBiome at stub.position()). Structures built
## onTopOfChunkCenter (igloo, desert pyramid, jungle temple, swamp hut) use the exact WORLD_SURFACE_WG top block; the
## others keep the preliminary surface estimate.
func _stub_y(cfg: Dictionary, x: int, z: int) -> int:
	if gen.dimension != "overworld":
		return 64
	var t := str(cfg.get("type", "")).trim_prefix("minecraft:")
	if t in ["igloo", "desert_pyramid", "jungle_temple", "swamp_hut"]:
		return first_free_height(x, z) - 1
	var ctx := DensityFunctions.Ctx.new(gen.dfc.node_count())
	return gen.chunk_surface(ctx, x, z)


func _make_start(st: Dictionary, sc: Vector2i) -> Dictionary:
	var entries: Array = (st["entries"] as Array).duplicate()
	if entries.size() == 1:
		return _try_structure(entries[0]["cfg"], sc)
	var r := large_feature_seed(gen.seed, sc.x, sc.y)
	var total := 0
	for e in entries:
		total += int(e["weight"])
	while not entries.is_empty() and total > 0:
		var j := r.next_int_bound(total)
		var k := 0
		for e in entries:
			j -= int(e["weight"])
			if j < 0:
				break
			k += 1
		k = mini(k, entries.size() - 1)
		var e2: Dictionary = entries[k]
		var res := _try_structure(e2["cfg"], sc)
		if not res.is_empty():
			return res
		entries.remove_at(k)
		total -= int(e2["weight"])
	return {}


func biome_id_at(x: int, y: int, z: int) -> int:
	if not gen.end_biomes and gen.single_biome < 0 and gen.native_tg >= 0 and Native.density_ok and Native.inst.has_method("tg_biome_at"):
		# native multi-noise lookup (the stub biome checks of /locate and structure starts; GDScript climate took ms each)
		var nb: int = int(Native.inst.tg_biome_at(gen.native_tg, x, y, z)[0])
		if nb >= 0:
			return nb
	var ctx := DensityFunctions.Ctx.new(gen.dfc.node_count())
	if gen.end_biomes:
		return gen.end_biome_at(ctx, x >> 4, z >> 4)
	if gen.single_biome >= 0:
		return gen.single_biome
	var qx := (x >> 2) << 2
	var qy := (y >> 2) << 2
	var qz := (z >> 2) << 2
	var nm := gen.climate.find(gen.r_temp.point(ctx, qx, qy, qz), gen.r_veg.point(ctx, qx, qy, qz), gen.r_cont.point(ctx, qx, qy, qz), gen.r_eros.point(ctx, qx, qy, qz), gen.r_depth.point(ctx, qx, qy, qz), gen.r_ridges.point(ctx, qx, qy, qz))
	return int(gen.biome_ids.get(nm, 0))


func _try_structure(cfg: Dictionary, sc: Vector2i) -> Dictionary:
	var t := str(cfg.get("type", "")).trim_prefix("minecraft:")
	var r := large_feature_seed(gen.seed, sc.x, sc.y)
	var res := {}
	# Java Structure.generate: biome test on the generation stub position BEFORE pieces are built
	match t:
		"jigsaw":
			var tj := Time.get_ticks_usec()
			if f.trace_names:
				printerr("[struct]     jigsaw stub %s" % str(cfg.get("name", "")))
			var stub := _jigsaw_stub(cfg, sc, r)
			if f.trace_names:
				printerr("[struct]     stub done: %s" % str(not stub.is_empty()))
			if stub.is_empty():
				return {}
			var sp: Vector3i = stub["center"]
			if not (cfg["biomes"] as Dictionary).has(biome_id_at(sp.x, sp.y, sp.z)):
				return {}
			res = _jigsaw_finish(cfg, stub, r)
			stats["jigsaw_ms"] += (Time.get_ticks_usec() - tj) / 1000.0
		"ruined_portal":
			res = StructuresLegacy.generate(self, t, cfg, sc, r)   # biome test on its stub inside (y comes from the random)
		"woodland_mansion":
			res = MansionPieces.generate(self, cfg, sc, r)   # biome test on its stub (block 7, 7) inside
		_:
			var cx := sc.x * 16 + 8
			var cz := sc.y * 16 + 8
			if not (cfg["biomes"] as Dictionary).has(biome_id_at(cx, _stub_y(cfg, cx, cz), cz)):
				return {}
			res = StructuresLegacy.generate(self, t, cfg, sc, r)
	if res.is_empty():
		return {}
	res["structure"] = cfg["name"]
	res["step"] = cfg["step"]
	return res


## Java NoiseBasedChunkGenerator.getBaseColumn: the noise-stage block classes of column (x, z), index y - gen_min_y:
## 0 air, 1 solid, 2 water, 3 lava (native: cell-interpolated final density + aquifer, no beard). Cached and shared.
var _cols := {}


func base_column(x: int, z: int) -> PackedByteArray:
	var key := Vector2i(x, z)
	_sm.lock()
	var v = _cols.get(key)
	_sm.unlock()
	if v != null:
		return v
	var out := PackedByteArray()
	if gen.native_tg >= 0 and Native.density_ok and Native.inst.has_method("tg_column"):
		out = Native.inst.tg_column(gen.native_tg, x, z)[0]
	else:
		out.resize(gen.gen_depth)
		var top := first_free_height(x, z, true)
		for i in gen.gen_depth:
			var y := gen.gen_min_y + i
			out[i] = 1 if y < top else (2 if y < gen.sea_level and gen.dimension == "overworld" else 0)
	_sm.lock()
	if _cols.size() > 20000:
		_cols.clear()
	_cols[key] = out
	_sm.unlock()
	return out


## Java ChunkGenerator.getBaseHeight: one above the top block the worldgen heightmap counts (WORLD_SURFACE_WG: any
## non-air block, fluids included; OCEAN_FLOOR_WG: blocks motion).
func base_height(x: int, z: int, ocean_floor: bool) -> int:
	var col := base_column(x, z)
	for i in range(col.size() - 1, -1, -1):
		var k := col[i]
		if (k == 1) if ocean_floor else (k != 0):
			return gen.gen_min_y + i + 1
	return gen.gen_min_y


## Noise-based first free height (ChunkGenerator.getFirstFreeHeight approx), cached and shared.
func first_free_height(x: int, z: int, ocean_floor: bool = false) -> int:
	var key := Vector3i(x, z, 1 if ocean_floor else 0)
	_sm.lock()
	var v = _heights.get(key)
	_sm.unlock()
	if v != null:
		return v
	var tf := Time.get_ticks_usec()
	var ctx := DensityFunctions.Ctx.new(gen.dfc.node_count())
	var top := gen.gen_min_y + gen.gen_depth - 1
	# evaluate only a window around the preliminary surface estimate, widening if the surface lies outside it
	var est := gen.chunk_surface(ctx, x, z) if gen.dimension == "overworld" else top
	var hi := mini(top, est + 24)
	var lo := maxi(gen.gen_min_y, est - 40)
	var h := gen.gen_min_y
	var found := false
	var up_from := -2147483648   # top of a solid window we moved up from
	while true:
		var xs := PackedInt32Array()
		var ys := PackedInt32Array()
		var zs := PackedInt32Array()
		for y in range(hi, lo - 1, -1):
			xs.append(x)
			ys.append(y)
			zs.append(z)
		var d: PackedFloat64Array
		if gen.native_graph >= 0 and Native.density_ok:
			# Java iterateNoiseColumn: the cell-interpolated density of the generated terrain (chunk corner grid, block
			# interpolation order) - uninterpolated values put pieces up to a few blocks off the real ground
			d = Native.inst.df_points(gen.native_graph, PackedInt32Array([gen.final_density.id]), xs, ys, zs, x >> 4, z >> 4, 2)[0]
		else:
			d = gen.final_density.batch(ctx, ctx.new_root(xs, ys, zs))
		for i in d.size():
			if d[i] > 0.0:
				h = hi - i + 1
				found = true
				break
		if not found and up_from != -2147483648:
			# moved up from a solid window top and found only air: the surface is that top (previously this case
			# ping-ponged between the two windows forever and hung the worker)
			h = up_from + 1
			break
		if found and h - 1 == hi and hi < top:
			# solid at the window top: terrain continues upward
			up_from = hi
			lo = hi + 1
			hi = mini(top, hi + 64)
			found = false
			continue
		if found or lo <= gen.gen_min_y:
			break
		hi = lo - 1
		lo = maxi(gen.gen_min_y, lo - 96)
	if not ocean_floor and h < gen.sea_level and gen.dimension == "overworld":
		h = gen.sea_level
	stats["ffh_calls"] += 1
	stats["ffh_ms"] += (Time.get_ticks_usec() - tf) / 1000.0
	_sm.lock()
	if _heights.size() > 200000:
		_heights.clear()
	_heights[key] = h
	_sm.unlock()
	return h


# ------------------------------------------------------------------ jigsaw

func _pool(name: String) -> Dictionary:
	var key := name.trim_prefix("minecraft:")
	if pools.has(key):
		return pools[key]
	var out := {"elements": [], "fallback": "empty", "max": -1}
	pools[key] = out
	var j = Res.read_json("data/minecraft/worldgen/template_pool/%s.json" % key)
	if j is Dictionary:
		for e in j.get("elements", []):
			var el := _element(e.get("element", {}))
			for w in int(e.get("weight", 1)):
				(out["elements"] as Array).append(el)
		out["fallback"] = str(j.get("fallback", "minecraft:empty")).trim_prefix("minecraft:")
	return out


func _element(e: Dictionary) -> Dictionary:
	var el := _element2(e)
	_uid += 1
	el["uid"] = _uid
	return el


func _element2(e: Dictionary) -> Dictionary:
	var t := str(e.get("element_type", "")).trim_prefix("minecraft:")
	var proj := str(e.get("projection", "rigid"))
	match t:
		"single_pool_element", "legacy_single_pool_element":
			var loc = e.get("location", "")
			return {"t": "single", "loc": str(loc), "legacy": t.begins_with("legacy"), "proj": proj, "procs": compile_processors(e.get("processors", {}))}
		"list_pool_element":
			var subs: Array = []
			for s in e.get("elements", []):
				subs.append(_element(s))
			return {"t": "list", "subs": subs, "proj": proj}
		"feature_pool_element":
			return {"t": "feature", "feature": str(e.get("feature", "")), "proj": proj}
	return {"t": "empty"}


func _el_template(el: Dictionary) -> StructureTemplate:
	return StructureTemplate.get_template(el["loc"]) if el["t"] == "single" else null


## Cached [box, jigsaws] of an element at the origin for a rotation (immutable; callers offset/copy).
func _el_info(el: Dictionary, rot: int) -> Array:
	var key := int(el.get("uid", 0)) * 4 + rot
	var v = _el_cache.get(key)
	if v != null:
		return v
	stats["elinfo_miss"] = int(stats.get("elinfo_miss", 0)) + 1
	var tmiss := Time.get_ticks_usec()
	var jl0 := _el_jigsaws_raw(el, rot)
	# private copies with precomputed attach fields (front vector, name/target strings, selection priority)
	var jl: Array = []
	var sels := PackedInt32Array()
	for jx0 in jl0:
		var jxd: Dictionary = (jx0 as Dictionary).duplicate()
		jxd["fv"] = StructureTemplate.DIRS[jxd["front"]]
		jxd["nm_s"] = str(jxd["name"])
		jxd["tg_s"] = str(jxd["target"])
		jl.append(jxd)
		sels.append(int(jxd["sel"]))
	var prios := {}
	for jx in jl:
		prios[int(jx["sel"])] = true
	var order: Array = prios.keys()
	order.sort()
	order.reverse()
	# jigsaw name -> PackedByteArray mask over jl (attach candidates are filtered by name before any dictionary access)
	var names := {}
	for k in jl.size():
		var nm: String = jl[k]["nm_s"]
		if not names.has(nm):
			var mk := PackedByteArray()
			mk.resize(jl.size())
			names[nm] = mk
		var mk2: PackedByteArray = names[nm]
		mk2[k] = 1
		names[nm] = mk2
	# [box, jigsaws, expansion cache, distinct priorities (descending), selection priorities, priorities packed, name masks]
	var info := [_el_box_raw(el, Vector3i.ZERO, rot), jl, -1, order, sels, PackedInt32Array(order), names]
	stats["elinfo_ms"] = float(stats.get("elinfo_ms", 0.0)) + (Time.get_ticks_usec() - tmiss) / 1000.0
	stats["max_jigsaws"] = maxi(int(stats.get("max_jigsaws", 0)), jl.size())
	_el_cache[key] = info
	return info


func _el_box(el: Dictionary, pos: Vector3i, rot: int) -> Array:
	var b: Array = _el_info(el, rot)[0]
	return [b[0] + pos, b[1] + pos]


func _el_box_raw(el: Dictionary, pos: Vector3i, rot: int) -> Array:
	match el["t"]:
		"single":
			var tpl := _el_template(el)
			return tpl.box(pos, rot) if tpl != null else [pos, pos]
		"list":
			var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
			var mx := -mn
			for s in el["subs"]:
				var b := _el_box(s, pos, rot)
				mn = Vector3i(mini(mn.x, b[0].x), mini(mn.y, b[0].y), mini(mn.z, b[0].z))
				mx = Vector3i(maxi(mx.x, b[1].x), maxi(mx.y, b[1].y), maxi(mx.z, b[1].z))
			return [mn, mx]
	return [pos, pos]


func _el_jigsaws_raw(el: Dictionary, rot: int) -> Array:
	match el["t"]:
		"single":
			var tpl := _el_template(el)
			if tpl != null:
				return tpl.jigsaws_at(Vector3i.ZERO, rot)
		"list":
			if not (el["subs"] as Array).is_empty():
				return _el_jigsaws_raw(el["subs"][0], rot)
		"feature":
			return [{"pos": Vector3i.ZERO, "front": "down", "top": StructureTemplate.rot_dir("south", rot), "name": "minecraft:bottom", "target": "minecraft:empty", "pool": "minecraft:empty", "rollable": false, "sel": 0, "place": 0}]
	return []


## SinglePoolElement.getShuffledJigsawBlocks: template order, Util.shuffle, stable sort by selection priority.
## Returned dicts are shared/immutable and positioned at the origin unless pos != 0 (then offset copies).
func _el_jigsaws(el: Dictionary, pos: Vector3i, rot: int, r: RandomSources.LegacyRandom) -> Array:
	var lst: Array = (_el_info(el, rot)[1] as Array).duplicate()
	if pos != Vector3i.ZERO:
		for i in lst.size():
			var d: Dictionary = (lst[i] as Dictionary).duplicate()
			d["pos"] = d["pos"] + pos
			lst[i] = d
	# Java Util.shuffle then a stable sort by selection priority (descending). Most elements have one priority,
	# so the sort is skipped; otherwise a stable bucket pass gives the same order as List.sort (sort_custom with a
	# lambda was 0.5 ms per call and dominated trial-chamber assembly).
	var i := lst.size()
	while i > 1:
		var j := r.next_int_bound(i)
		var t = lst[i - 1]
		lst[i - 1] = lst[j]
		lst[j] = t
		i -= 1
	var order: Array = _el_info(el, rot)[3]
	if order.size() <= 1:
		return lst
	var out: Array = []
	for pr in order:
		for e in lst:
			if int(e["sel"]) == int(pr):
				out.append(e)
	return out


func _pool_max(name: String) -> int:
	var p := _pool(name)
	if int(p["max"]) >= 0:
		return p["max"]
	var m := 0
	var seen := {}
	for el in p["elements"]:
		if seen.has(el):
			continue
		seen[el] = true
		if el["t"] == "empty":
			continue
		var b := _el_box(el, Vector3i.ZERO, 0)
		m = maxi(m, b[1].y - b[0].y + 1)
	p["max"] = m
	return m


## Index form of _el_jigsaws(el, ZERO, rot, r): same Util.shuffle random calls and stable priority order, without
## copying the jigsaw dictionaries (that copy dominated trial-chamber assembly).
static func _el_jig_idx(info: Array, r: RandomSources.LegacyRandom) -> PackedInt32Array:
	var sels: PackedInt32Array = info[4]
	var n := sels.size()
	if n > 2 and Native.ok:
		if info.size() < 6:
			info.append(PackedInt32Array(info[3]))
		var res: Array = Native.inst.jig_shuffle(r.seed, sels, info[5])
		r.seed = res[0]
		return res[1]
	var idx := PackedInt32Array()
	idx.resize(n)
	for k in n:
		idx[k] = k
	var i := n
	while i > 1:
		var j := r.next_int_bound(i)
		var t := idx[i - 1]
		idx[i - 1] = idx[j]
		idx[j] = t
		i -= 1
	var order: Array = info[3]
	if order.size() <= 1:
		return idx
	var out := PackedInt32Array()
	for pr in order:
		var pv := int(pr)
		for e in idx:
			if sels[e] == pv:
				out.append(e)
	return out


static var old_jig := false   # verification: original dictionary-copy jigsaw path


static func _shuffled(arr: Array, r: RandomSources.LegacyRandom) -> Array:
	var lst := arr.duplicate()
	for i in range(lst.size(), 1, -1):
		var j := r.next_int_bound(i)
		var t = lst[i - 1]
		lst[i - 1] = lst[j]
		lst[j] = t
	return lst


static func _inside(b: Array, p: Vector3i) -> bool:
	return p.x >= b[0].x and p.x <= b[1].x and p.y >= b[0].y and p.y <= b[1].y and p.z >= b[0].z and p.z <= b[1].z


## Java: the piece box (deflated 0.25) must lie in the free shape = container minus placed boxes.
## Holes are a flat PackedInt32Array (6 ints per box): Array-of-Vector3i access was the jigsaw hot spot.
static func _fits(shape: Dictionary, b: Array) -> bool:
	var c: Array = shape["box"]
	var b0: Vector3i = b[0]
	var b1: Vector3i = b[1]
	var c0: Vector3i = c[0]
	var c1: Vector3i = c[1]
	if b0.x < c0.x or b0.y < c0.y or b0.z < c0.z or b1.x > c1.x or b1.y > c1.y or b1.z > c1.z:
		return false
	var hp: PackedInt32Array = shape["hp"]
	if hp.size() > 60 and Native.ok and not old_jig:
		return int(Native.inst.boxes_hit(hp, b0.x, b0.y, b0.z, b1.x, b1.y, b1.z)[0]) == 0
	var x0 := b0.x
	var y0 := b0.y
	var z0 := b0.z
	var x1 := b1.x
	var y1 := b1.y
	var z1 := b1.z
	var n := hp.size()
	var i := 0
	while i < n:
		if x0 <= hp[i + 3] and x1 >= hp[i] and y0 <= hp[i + 4] and y1 >= hp[i + 1] and z0 <= hp[i + 5] and z1 >= hp[i + 2]:
			return false
		i += 6
	return true


func _jigsaw_stub(cfg: Dictionary, sc: Vector2i, r: RandomSources.LegacyRandom) -> Dictionary:
	var sh = cfg.get("start_height", {"absolute": 0})
	var y0 := 0
	if sh is Dictionary:
		if sh.has("absolute") or sh.has("above_bottom") or sh.has("below_top"):
			y0 = f._anchor(sh)
		else:
			y0 = f._anchor(sh.get("min_inclusive", {"absolute": 0}))
			var y1 := f._anchor(sh.get("max_inclusive", {"absolute": 0}))
			y0 = y0 + r.next_int_bound(maxi(y1 - y0 + 1, 1))
	var pos := Vector3i(sc.x * 16, y0, sc.y * 16)
	var rot := r.next_int_bound(4)
	var start_pool := _pool(str(cfg.get("start_pool", "")))
	var els: Array = start_pool["elements"]
	if els.is_empty():
		return {}
	var el: Dictionary = els[r.next_int_bound(els.size())]
	if el["t"] == "empty":
		return {}
	var anchor := pos
	if cfg.has("start_jigsaw_name"):
		var want := str(cfg["start_jigsaw_name"])
		var found := false
		for jb in _el_jigsaws(el, pos, rot, r):
			if str(jb["name"]) == want or str(jb["name"]).trim_prefix("minecraft:") == want.trim_prefix("minecraft:"):
				anchor = jb["pos"]
				found = true
				break
		if not found:
			return {}
	var off := anchor - pos
	var ppos := pos - off
	var box := _el_box(el, ppos, rot)
	var ci: int = (box[0].x + box[1].x) / 2
	var cj: int = (box[0].z + box[1].z) / 2
	var k := ppos.y
	if cfg.has("project_start_to_heightmap"):
		k = pos.y + first_free_height(ci, cj, str(cfg["project_start_to_heightmap"]).begins_with("OCEAN"))
	var dy: int = k - (box[0].y + 1)   # Java: piece.move(0, k - (minY + groundLevelDelta), 0), delta = 1
	var piece := {"el": el, "pos": ppos + Vector3i(0, dy, 0), "rot": rot, "box": [box[0] + Vector3i(0, dy, 0), box[1] + Vector3i(0, dy, 0)], "gld": _el_gld(el)}
	var m := k + off.y
	return {"piece": piece, "center": Vector3i(ci, m, cj), "ci": ci, "cj": cj, "m": m}


func _jigsaw_finish(cfg: Dictionary, stub: Dictionary, r: RandomSources.LegacyRandom) -> Dictionary:
	var piece: Dictionary = stub["piece"]
	var ci: int = stub["ci"]
	var cj: int = stub["cj"]
	var m: int = stub["m"]
	var pieces: Array = [piece]
	var depth := int(cfg.get("size", 0))
	if depth > 0:
		var md := int(cfg.get("max_distance_from_center", 80))
		var pb: Array = piece["box"]
		var free := {"box": [Vector3i(ci - md, maxi(m - md, gen.gen_min_y), cj - md), Vector3i(ci + md, mini(m + md, gen.gen_min_y + gen.gen_depth - 1), cj + md)], "holes": [pb],
			"hp": PackedInt32Array([pb[0].x, pb[0].y, pb[0].z, pb[1].x, pb[1].y, pb[1].z])}
		_place_children(cfg, pieces, piece, free, depth, r)
	var mn := Vector3i(1 << 30, 1 << 30, 1 << 30)
	var mx := -mn
	for p in pieces:
		mn = Vector3i(mini(mn.x, p["box"][0].x), mini(mn.y, p["box"][0].y), mini(mn.z, p["box"][0].z))
		mx = Vector3i(maxi(mx.x, p["box"][1].x), maxi(mx.y, p["box"][1].y), maxi(mx.z, p["box"][1].z))
	return {"pieces": pieces, "center": Vector3i(ci, m, cj), "box": [mn, mx]}


## JigsawPlacement.Placer: priority queue by selection priority (FIFO within equal priority).
func _place_children(cfg: Dictionary, pieces: Array, start: Dictionary, free: Dictionary, max_depth: int, r: RandomSources.LegacyRandom) -> void:
	var queue: Array = [[start, free, 0, 0]]   # [piece, free_shape, depth, priority]
	var expansion := bool(cfg.get("use_expansion_hack", false))
	var guard := 0
	while not queue.is_empty() and guard < 400:
		guard += 1
		var best := 0
		for qi in queue.size():
			if int(queue[qi][3]) > int(queue[best][3]):
				best = qi
		var st: Array = queue[best]
		queue.remove_at(best)
		if f.trace_names and guard % 10 == 1:
			printerr("[struct]       jigsaw iter %d queue %d pieces %d stats %s" % [guard, queue.size(), pieces.size(), JSON.stringify(stats)])
		_try_children(cfg, pieces, st[0], st[1], int(st[2]), max_depth, expansion, r, queue)


func _try_children(cfg: Dictionary, pieces: Array, piece: Dictionary, free: Dictionary, depth: int, max_depth: int, expansion: bool, r: RandomSources.LegacyRandom, queue: Array) -> void:
	var el: Dictionary = piece["el"]
	var rigid: bool = el["proj"] == "rigid"
	var box: Array = piece["box"]
	var i := int(box[0].y)
	var interior: Dictionary = {}
	# index form (no per-jigsaw dictionary copies); the piece offset is added to each jigsaw position here
	var ppos0: Vector3i = piece["pos"]
	var pinfo: Array = _el_info(el, piece["rot"])
	var pjl: Array = pinfo[1]
	var pord: PackedInt32Array
	if old_jig:
		pjl = _el_jigsaws(el, Vector3i.ZERO, piece["rot"], r)
		pord.resize(pjl.size())
		for qq in pjl.size():
			pord[qq] = qq
	else:
		pord = _el_jig_idx(pinfo, r)
	for pji in pord:
		var jb: Dictionary = pjl[pji]
		var jpos: Vector3i = jb["pos"] + ppos0
		var front: Vector3i = StructureTemplate.DIRS[jb["front"]]
		var target_pos := jpos + front
		var j := jpos.y - i
		var k := -1
		var pool_name := str(jb["pool"]).trim_prefix("minecraft:")
		if f.trace_names:
			printerr("[struct]         jb pool %s ..." % pool_name)
		var pool := _pool(pool_name)
		if f.trace_names:
			printerr("[struct]         pool %d elements, fallback %s" % [(pool["elements"] as Array).size(), str(pool["fallback"])])
		if (pool["elements"] as Array).is_empty() and pool_name != "empty":
			continue
		var fb := _pool(str(pool["fallback"]))
		var shape: Dictionary
		if _inside(box, target_pos):
			if interior.is_empty():
				interior = {"box": box, "holes": [], "hp": PackedInt32Array()}
			shape = interior
		else:
			shape = free
		var t_sh := Time.get_ticks_usec()
		var cands: Array = []
		if depth != max_depth:
			cands.append_array(_shuffled(pool["elements"], r))
		cands.append_array(_shuffled(fb["elements"], r))
		stats["pool_shuffle_ms"] = float(stats.get("pool_shuffle_ms", 0.0)) + (Time.get_ticks_usec() - t_sh) / 1000.0
		stats["pool_len"] = maxi(int(stats.get("pool_len", 0)), cands.size())
		stats["jigsaws_tried"] = int(stats.get("jigsaws_tried", 0)) + 1
		var placed := false
		var tg_want: String = jb["tg_s"]
		var failed := {}   # element uids that attached in no rotation to this jigsaw (the shape only changes on a placement)
		for el2 in cands:
			if el2["t"] == "empty":
				break
			stats["cands"] = int(stats.get("cands", 0)) + 1
			if f.trace_names:
				printerr("[struct]           cand %s %s" % [str(el2.get("loc", el2["t"])), JSON.stringify(stats)])
			var uid2 := int(el2["uid"])
			if failed.has(uid2) and not old_jig:
				# a repeat of an element that already failed here: same outcome, only its random calls are replayed
				# (Java still shuffles the rotations and each rotation's jigsaw blocks)
				for rot3 in _shuffled([0, 1, 2, 3], r):
					_el_jig_idx(_el_info(el2, rot3), r)
				continue
			for rot2 in _shuffled([0, 1, 2, 3], r):
				var t_ej := Time.get_ticks_usec()
				var info2: Array = _el_info(el2, rot2)
				var jl2: Array = info2[1]
				var jbs2: Array = _el_jigsaws(el2, Vector3i.ZERO, rot2, r) if old_jig else []
				var jord := PackedInt32Array() if old_jig else _el_jig_idx(info2, r)
				if old_jig:
					jord.resize(jbs2.size())
					for qq in jbs2.size():
						jord[qq] = qq
					jl2 = jbs2
				stats["eljig_ms"] = float(stats.get("eljig_ms", 0.0)) + (Time.get_ticks_usec() - t_ej) / 1000.0
				# only jigsaws named like this one's target can attach
				var nmv = null if old_jig else (info2[6] as Dictionary).get(tg_want)
				if nmv == null and not old_jig:
					continue
				var use_mask := nmv != null
				var nmask: PackedByteArray = nmv if use_mask else PackedByteArray()
				var b2 := _el_box(el2, Vector3i.ZERO, rot2)
				var mexp := 0
				if expansion and b2[1].y - b2[0].y + 1 <= 16:
					var info: Array = _el_info(el2, rot2)
					if int(info[2]) < 0:
						var mm := 0
						for jx in info[1]:
							if not _inside(b2, jx["pos"] + StructureTemplate.DIRS[jx["front"]]):
								continue
							var pn := str(jx["pool"]).trim_prefix("minecraft:")
							mm = maxi(mm, maxi(_pool_max(pn), _pool_max(str(_pool(pn)["fallback"]))))
						info[2] = mm
					mexp = int(info[2])
				for jo in jord:
					if use_mask and nmask[jo] == 0:
						continue
					var jb2: Dictionary = jl2[jo]
					# JigsawBlock.canAttach
					if (jb["fv"] as Vector3i) != -(jb2["fv"] as Vector3i):
						continue
					if not bool(jb["rollable"]) and jb["top"] != jb2["top"]:
						continue
					if jb["tg_s"] != jb2["nm_s"]:
						continue
					var p4: Vector3i = jb2["pos"]
					var p5 := target_pos - p4
					var b3 := _el_box(el2, p5, rot2)
					var n := int(b3[0].y)
					var rigid2: bool = el2["proj"] == "rigid"
					var o := p4.y
					var pp := j - o + front.y
					var q: int
					if rigid and rigid2:
						q = i + pp
					else:
						if k == -1:
							k = first_free_height(jpos.x, jpos.z)
						q = k - o
					var rr := q - n
					var b4 := [b3[0] + Vector3i(0, rr, 0), b3[1] + Vector3i(0, rr, 0)]
					var p6 := p5 + Vector3i(0, rr, 0)
					if mexp > 0:
						var s := maxi(mexp + 1, b4[1].y - b4[0].y)
						b4[1] = Vector3i(b4[1].x, maxi(b4[1].y, b4[0].y + s), b4[1].z)
					stats["fits"] = int(stats.get("fits", 0)) + 1
					if not _fits(shape, b4):
						continue
					(shape["holes"] as Array).append(b4)
					var hpa: PackedInt32Array = shape["hp"]
					hpa.append_array([b4[0].x, b4[0].y, b4[0].z, b4[1].x, b4[1].y, b4[1].z])
					shape["hp"] = hpa
					# Java: a rigid child's ground level is its parent's shifted by the connection's step (k2 = j3 - k1);
					# both pieces record a JigsawJunction (the beardifier blends terrain toward it, weight 0.4)
					var j3 := int(piece.get("gld", 1))
					var k2 := j3 - pp if rigid2 else _el_gld(el2)
					var l2: int
					if rigid:
						l2 = i + j
					elif rigid2:
						l2 = q + o
					else:
						if k == -1:
							k = first_free_height(jpos.x, jpos.z)
						l2 = k + pp / 2
					if not piece.has("junctions"):
						piece["junctions"] = PackedInt32Array()
					var pjn: PackedInt32Array = piece["junctions"]
					pjn.append_array([target_pos.x, l2 - j + j3, target_pos.z])
					piece["junctions"] = pjn
					var np := {"el": el2, "pos": p6, "rot": rot2, "box": b4, "gld": k2, "junctions": PackedInt32Array([jpos.x, l2 - o + k2, jpos.z])}
					pieces.append(np)
					if depth + 1 <= max_depth:
						queue.append([np, shape, depth + 1, int(jb2["place"])])
					placed = true
					break
				if placed:
					break
			if placed:
				break
			failed[uid2] = true


# ------------------------------------------------------------------ processors

func compile_processors(v) -> Array:
	if v is String:
		var key := str(v).trim_prefix("minecraft:")
		if proc_lists.has(key):
			return proc_lists[key]
		var j = Res.read_json("data/minecraft/worldgen/processor_list/%s.json" % key)
		var lst := compile_processors(j) if j != null else []
		proc_lists[key] = lst
		return lst
	var arr: Array = []
	if v is Dictionary:
		arr = v.get("processors", [])
	elif v is Array:
		arr = v
	var out: Array = []
	for p in arr:
		if not (p is Dictionary):
			continue
		var t := str(p.get("processor_type", "")).trim_prefix("minecraft:")
		match t:
			"rule":
				var rules: Array = []
				for ru in p.get("rules", []):
					# block_entity_modifier append_loot: the output block's loot table (suspicious sand / gravel archaeology)
					var bem = ru.get("block_entity_modifier", {})
					var loot := str(bem.get("loot_table", "")).trim_prefix("minecraft:") if bem is Dictionary and str(bem.get("type", "")).ends_with("append_loot") else ""
					rules.append([_rtest(ru.get("input_predicate", {})), _rtest(ru.get("location_predicate", {})), f._state(ru.get("output_state", "minecraft:air")), loot])
				out.append({"t": "rule", "rules": rules})
			"block_ignore":
				var ids := {}
				for b in p.get("blocks", []):
					var nm := str(b.get("Name", b) if b is Dictionary else b).trim_prefix("minecraft:")
					ids[gen.blocks.block_id(nm)] = true
				out.append({"t": "ignore", "ids": ids})
			"block_rot":
				out.append({"t": "rot", "integrity": float(p.get("integrity", 1.0))})
			"protected_blocks":
				var ids2 := {}
				for nm2 in Tags.blocks(str(p.get("value", "#minecraft:features_cannot_replace"))):
					ids2[gen.blocks.block_id(nm2)] = true
				out.append({"t": "protect", "ids": ids2})
			"block_age":
				out.append({"t": "age", "moss": float(p.get("mossiness", 0.0))})
			"capped":
				# Java CappedProcessor: per block nothing; finalizeProcessing applies the delegate to up to limit random
				# processed blocks (StructureTemplate.place runs the two-pass path for these)
				var dl := compile_processors([p.get("delegate", {})])
				if not dl.is_empty():
					out.append({"t": "capped", "limit": p.get("limit", 1), "delegate": dl[0]})
	return out


func _rtest(v) -> Dictionary:
	if not (v is Dictionary):
		return {"t": "true"}
	var t := str(v.get("predicate_type", "always_true")).trim_prefix("minecraft:")
	match t:
		"block_match":
			return {"t": "block", "id": gen.blocks.block_id(str(v.get("block", "")).trim_prefix("minecraft:"))}
		"blockstate_match":
			return {"t": "state", "s": f._state(v.get("block_state", {}))}
		"tag_match":
			var ids := {}
			for nm in Tags.blocks(str(v.get("tag", ""))):
				ids[gen.blocks.block_id(nm)] = true
			return {"t": "tag", "ids": ids}
		"random_block_match":
			return {"t": "rblock", "id": gen.blocks.block_id(str(v.get("block", "")).trim_prefix("minecraft:")), "p": float(v.get("probability", 1.0))}
		"random_blockstate_match":
			return {"t": "rstate", "s": f._state(v.get("block_state", {})), "p": float(v.get("probability", 1.0))}
	return {"t": "true"}


static func _rt_ok(blocks: BlockRegistry, t: Dictionary, st: int, r: RandomSources.LegacyRandom) -> bool:
	match str(t["t"]):
		"block":
			return st >= 0 and blocks.st_block[st] == int(t["id"])
		"state":
			return st == int(t["s"])
		"tag":
			return st >= 0 and (t["ids"] as Dictionary).has(blocks.st_block[st])
		"rblock":
			return st >= 0 and blocks.st_block[st] == int(t["id"]) and r.next_float() < float(t["p"])
		"rstate":
			return st == int(t["s"]) and r.next_float() < float(t["p"])
	return true


## Apply one compiled processor; returns the new state, -1 to skip placement, -2 to abort.
static func process(f: Features, c: Features.FCtx, pr: Dictionary, st: int, wp: Vector3i, _lp: Vector3i) -> int:
	var blocks := f.blocks
	match str(pr["t"]):
		"rule":
			var r := RandomSources.LegacyRandom.new(RandomSources.pos_seed(wp.x, wp.y, wp.z))
			var existing := f.get_block(c, wp)
			for ru in pr["rules"]:
				if _rt_ok(blocks, ru[0], st, r) and _rt_ok(blocks, ru[1], existing, r):
					if ru.size() > 3 and str(ru[3]) != "" and int(ru[2]) > 0:
						c.block_entities[wp] = {"id": blocks.name_of(int(ru[2])), "loot_table": str(ru[3]), "loot_seed": RandomSources.pos_seed(wp.x, wp.y, wp.z)}
					return int(ru[2])
			return st
		"ignore":
			return -1 if st >= 0 and (pr["ids"] as Dictionary).has(blocks.st_block[st]) else st
		"rot":
			var r2 := RandomSources.LegacyRandom.new(RandomSources.pos_seed(wp.x, wp.y, wp.z))
			return st if r2.next_float() <= float(pr["integrity"]) else -1
		"protect":
			var ex := f.get_block(c, wp)
			return -1 if ex >= 0 and (pr["ids"] as Dictionary).has(blocks.st_block[ex]) else st
		"age":
			return _block_age(blocks, st, wp, float(pr["moss"]))
		"lava_sub":
			# LavaSubmergedBlockProcessor: lava already there stays unless the new block is a full cube
			var ex2 := f.get_block(c, wp)
			if ex2 > 0 and blocks.name_of(ex2) == "lava" and (st <= 0 or (blocks.st_flags[st] & BlockRegistry.F_FULL_SHAPE) == 0):
				return blocks.default_state("lava")
			return st
		"blackstone":
			return _blackstone(blocks, st)
	return st


## Java BlockAgeProcessor (ruined portals): stone bricks / stone / chiseled -> cracked or mossy bricks or random
## stairs (50 %), stairs -> slabs or mossy stairs (50 %), slabs / walls -> mossy (mossiness), obsidian -> crying (15 %).
static func _block_age(blocks: BlockRegistry, st: int, wp: Vector3i, moss: float) -> int:
	if st <= 0:
		return st
	var r := RandomSources.LegacyRandom.new(RandomSources.pos_seed(wp.x, wp.y, wp.z))
	var nm := blocks.name_of(st)
	if nm == "stone_bricks" or nm == "stone" or nm == "chiseled_stone_bricks":
		if r.next_float() >= 0.5:
			return st
		var s1 := _age_stairs(blocks, r, "stone_brick_stairs")
		var s2 := _age_stairs(blocks, r, "mossy_stone_brick_stairs")
		if r.next_float() < moss:
			return [blocks.default_state("mossy_stone_bricks"), s2][r.next_int_bound(2)]
		return [blocks.default_state("cracked_stone_bricks"), s1][r.next_int_bound(2)]
	if Tags.has_block("#minecraft:stairs", nm):
		if r.next_float() >= 0.5:
			return st
		if r.next_float() < moss:
			var ms := blocks.with_prop(blocks.with_prop(blocks.default_state("mossy_stone_brick_stairs"), "facing", blocks.get_prop(st, "facing")), "half", blocks.get_prop(st, "half"))
			return [ms, blocks.default_state("mossy_stone_brick_slab")][r.next_int_bound(2)]
		return [blocks.default_state("stone_slab"), blocks.default_state("stone_brick_slab")][r.next_int_bound(2)]
	if Tags.has_block("#minecraft:slabs", nm):
		return blocks.default_state("mossy_stone_brick_slab") if r.next_float() < moss else st
	if Tags.has_block("#minecraft:walls", nm):
		return blocks.default_state("mossy_stone_brick_wall") if r.next_float() < moss else st
	if nm == "obsidian":
		return blocks.default_state("crying_obsidian") if r.next_float() < 0.15 else st
	return st


static func _age_stairs(blocks: BlockRegistry, r: RandomSources.LegacyRandom, nm: String) -> int:
	var facing: String = ["north", "east", "south", "west"][r.next_int_bound(4)]
	var half: String = ["top", "bottom"][r.next_int_bound(2)]
	return blocks.with_prop(blocks.with_prop(blocks.default_state(nm), "facing", facing), "half", half)


const BLACKSTONE := {"cobblestone": "blackstone", "mossy_cobblestone": "blackstone", "stone": "polished_blackstone",
	"stone_bricks": "polished_blackstone_bricks", "mossy_stone_bricks": "polished_blackstone_bricks",
	"cobblestone_stairs": "blackstone_stairs", "mossy_cobblestone_stairs": "blackstone_stairs",
	"stone_stairs": "polished_blackstone_stairs", "stone_brick_stairs": "polished_blackstone_brick_stairs",
	"mossy_stone_brick_stairs": "polished_blackstone_brick_stairs", "cobblestone_slab": "blackstone_slab",
	"mossy_cobblestone_slab": "blackstone_slab", "smooth_stone_slab": "polished_blackstone_slab",
	"stone_slab": "polished_blackstone_slab", "stone_brick_slab": "polished_blackstone_brick_slab",
	"mossy_stone_brick_slab": "polished_blackstone_brick_slab", "stone_brick_wall": "polished_blackstone_brick_wall",
	"mossy_stone_brick_wall": "polished_blackstone_brick_wall", "cobblestone_wall": "blackstone_wall",
	"mossy_cobblestone_wall": "blackstone_wall", "chiseled_stone_bricks": "chiseled_polished_blackstone",
	"cracked_stone_bricks": "cracked_polished_blackstone_bricks", "iron_bars": "iron_chain"}


## Java BlackstoneReplaceProcessor: stone-family blocks -> blackstone family, properties kept.
static func _blackstone(blocks: BlockRegistry, st: int) -> int:
	if st <= 0:
		return st
	var to := str(BLACKSTONE.get(blocks.name_of(st), ""))
	if to == "":
		return st
	if blocks.block_id(to) < 0 and to == "iron_chain":
		to = "chain"
	var out := blocks.default_state(to)
	if out < 0:
		return st
	for pr in blocks.props_of(st):
		if blocks.has_prop(out, pr):
			out = blocks.with_prop(out, pr, blocks.get_prop(st, pr))
	return out


# ------------------------------------------------------------------ chunk placement

## Place all structure pieces of `step` that intersect the origin chunk (called from Features.compute).
## Surface structure parts of the 8 neighbour chunks of the region, placed into this origin's private view only (writes,
## block entities, entities and post-processing discarded). Java places a piece's part during its chunk's decoration;
## a neighbour decorated afterwards sees it, so its trees fail TreeFeature's free-space checks and leaves only fill
## air (the clearing around villages, temples, igloos ...). Neighbour origins here otherwise read pristine terrain and
## grew trees through the pieces (the parts inside the piece's own chunk then overwrote them: legacy village templates
## ignore air, so leaves and trunks stayed inside the houses).
const NEIGHBOUR_VIEW_STEP := 4   # SURFACE_STRUCTURES


static var _nview: Dictionary = {}   # "dim|seed|cx,cz" -> PackedInt32Array [x, y, z, state]* (that chunk's part)
static var _nscan: Dictionary = {}   # "dim|seed|cx,cz" -> _scan_at result of that chunk
static var _nvm := Mutex.new()


func place_neighbour_view(c: Features.FCtx, origin: Chunk, step: int) -> void:
	if step != NEIGHBOUR_VIEW_STEP or by_step[step].is_empty() or old_scan:
		return
	var nw0 := c.writes.size()
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			if dx == 0 and dz == 0:
				continue
			if not c.has.is_empty() and c.has[(dz + 1) * 3 + dx + 1] == 0:
				continue
			var ncx: int = origin.cx + dx
			var ncz: int = origin.cz + dz
			var key := "%s|%d|%d,%d" % [gen.dimension, gen.seed, ncx, ncz]
			_nvm.lock()
			var cached = _nview.get(key)
			_nvm.unlock()
			if cached != null:
				var cw: PackedInt32Array = cached
				if c.flat.is_empty():
					for k in range(0, cw.size(), 4):
						f.set_block(c, Vector3i(cw[k], cw[k + 1], cw[k + 2]), cw[k + 3])
					continue
				# (inline Features.set_block without the write record; unchanged blocks skipped)
				var flat: PackedInt32Array = c.flat
				var fx0 := c.fx0
				var fz0 := c.fz0
				var hl_on := not c.hl.is_empty()
				for k in range(0, cw.size(), 4):
					var lx := cw[k] - fx0
					var lz := cw[k + 2] - fz0
					var y := cw[k + 1]
					if lx < 0 or lx >= 48 or lz < 0 or lz >= 48 or y < -64 or y >= 320:
						continue
					var ci := (lz >> 4) * 3 + (lx >> 4)
					if c.has[ci] == 0:
						continue
					var idx := ci * 98304 + ((y + 64) << 8) + ((lz & 15) << 4) + (lx & 15)
					var st := cw[k + 3]
					if flat[idx] == st:
						continue
					flat[idx] = st
					if hl_on and c.hstate[ci] == 2:
						f._hl_update(c, lx, y, lz, ci, st)
				continue
			# first origin to need this chunk's part: place it here (view only) and share the blocks
			var nmin := Vector3i(ncx * 16, gen.gen_min_y, ncz * 16)
			var nmax := nmin + Vector3i(15, gen.gen_depth, 15)
			var found: Dictionary = _scan_cached(ncx, ncz).get(step, {})
			var out := PackedInt32Array()
			if not found.is_empty():
				var nw1 := c.writes.size()
				var be_keep := c.block_entities
				var en_keep := c.entities
				var pp_keep := c.postproc
				c.block_entities = {}
				c.entities = []
				c.postproc = PackedInt32Array()
				_place_found(c, found, by_step[step], step, Features.decoration_seed(gen.seed, ncx * 16, ncz * 16), nmin, nmax)
				c.block_entities = be_keep
				c.entities = en_keep
				c.postproc = pp_keep
				for k in range(nw1, c.writes.size(), 5):
					out.append_array([c.writes[k], c.writes[k + 1], c.writes[k + 2], c.writes[k + 3]])
			if gen.aborted:
				break
			_nvm.lock()
			if _nview.size() > 3000:
				_nview.clear()
			_nview[key] = out
			_nvm.unlock()
	c.writes.resize(nw0)


## _scan_at of a chunk, shared by every origin (the own pass and the 8 neighbour views read the same result).
func _scan_cached(cx: int, cz: int) -> Dictionary:
	var key := "%s|%d|%d,%d" % [gen.dimension, gen.seed, cx, cz]
	_nvm.lock()
	var v = _nscan.get(key)
	_nvm.unlock()
	if v != null:
		return v
	var nmin := Vector3i(cx * 16, gen.gen_min_y, cz * 16)
	var res := _scan_at(cx, cz, nmin, nmin + Vector3i(15, gen.gen_depth, 15))
	if gen.aborted:
		return res
	_nvm.lock()
	if _nscan.size() > 3000:
		_nscan.clear()
	_nscan[key] = res
	_nvm.unlock()
	return res


func place_step(c: Features.FCtx, origin: Chunk, step: int, deco: int) -> void:
	var names: Array = by_step[step]
	if names.is_empty():
		return
	var cmin := Vector3i(origin.cx * 16, gen.gen_min_y, origin.cz * 16)
	var cmax := cmin + Vector3i(15, gen.gen_depth, 15)
	if old_scan:
		_place_step_old(c, origin, step, deco)
		return
	# one scan of every structure set per chunk, shared by all steps (results are pure, same order as per-step scans)
	if c.struct_scan.is_empty():
		c.struct_scan = _scan_cached(origin.cx, origin.cz)
	var found: Dictionary = c.struct_scan.get(step, {})
	_place_found(c, found, names, step, deco, cmin, cmax)


## Assemble (and cache) every structure start located in chunk (cx, cz). Called from that chunk's generation job, so
## starts are built in parallel ahead of the feature jobs that place them (pure + cached: no output change).
const ADAPT := {"beard_thin": 1, "beard_box": 2, "bury": 3, "encapsulate": 4}


## Java Beardifier.forStructuresInChunk: structures with a terrain adaptation whose start references this chunk (its
## box covers the chunk column); their rigid pool pieces within 12 blocks of the chunk ->
## [min x, y, z, max x, y, z, adaptation, ground level delta]* (the delta the jigsaw placer gave each piece; 0 for
## non-pool pieces), then the pieces' jigsaw junctions near the chunk as [x, ground y, z, 0, 0, 0, 5, 0]*.
func beard_pieces(cx: int, cz: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var jout := PackedInt32Array()
	var x0 := cx * 16
	var z0 := cz * 16
	for st in sets:
		for sc in _candidates(st, cx, cz):
			if gen.aborted:
				return out
			var res := _start(st, sc)
			if res.is_empty() or not res.has("pieces"):
				continue
			var cfg: Dictionary = structures.get(str(res["structure"]), {})
			var ad := int(ADAPT.get(str(cfg.get("terrain_adaptation", "none")).trim_prefix("minecraft:"), 0))
			if ad == 0:
				continue
			var b: Array = res["box"]
			if b[1].x < x0 or b[0].x > x0 + 15 or b[1].z < z0 or b[0].z > z0 + 15:
				continue
			for pc in res["pieces"]:
				var pb: Array = pc["box"]
				if pb[1].x < x0 - 12 or pb[0].x > x0 + 15 + 12 or pb[1].z < z0 - 12 or pb[0].z > z0 + 15 + 12:
					continue
				var el: Dictionary = pc["el"]
				var jn = pc.get("junctions")
				if jn != null:
					var jp: PackedInt32Array = jn
					for q in range(0, jp.size(), 3):
						if jp[q] > x0 - 12 and jp[q + 2] > z0 - 12 and jp[q] < x0 + 15 + 12 and jp[q + 2] < z0 + 15 + 12:
							jout.append_array([jp[q], jp[q + 1], jp[q + 2], 0, 0, 0, 5, 0])
				if str(el.get("proj", "rigid")) != "rigid":
					continue
				# StructurePiece (non-pool, "java"): Rigid(box, adaptation, 0)
				var delta := 0 if str(el.get("t", "")) == "java" else int(pc.get("gld", _el_gld(el)))
				out.append_array([pb[0].x, pb[0].y, pb[0].z, pb[1].x, pb[1].y, pb[1].z, ad, delta])
	out.append_array(jout)
	return out


## StructurePoolElement.getGroundLevelDelta (template elements 1; feature / empty 0).
static func _el_gld(el: Dictionary) -> int:
	return 0 if str(el.get("t", "")) in ["feature", "empty", "java"] else 1


## Java Beardifier.compute for one block (GDScript reference of the native version in terrain.cpp).
static var _kernel := PackedFloat32Array()


static func beard_at(pieces: PackedInt32Array, x: int, y: int, z: int) -> float:
	if _kernel.is_empty():
		_kernel.resize(24 * 24 * 24)
		for k in 24:
			for i in 24:
				for j in 24:
					var fx := float(i - 12)
					var fy := float(j - 12) + 0.5
					var fz := float(k - 12)
					_kernel[k * 576 + i * 24 + j] = exp(-(fx * fx + fy * fy + fz * fz) / 16.0)
	var d := 0.0
	for o in range(0, pieces.size(), 8):
		var dx := maxi(0, maxi(pieces[o] - x, x - pieces[o + 3]))
		var dz := maxi(0, maxi(pieces[o + 2] - z, z - pieces[o + 5]))
		var yb := pieces[o + 1] + pieces[o + 7]
		var dyb := y - yb
		var ad := pieces[o + 6]
		if ad == 1:
			d += _beard(dx, dyb, dz, dyb) * 0.8
		elif ad == 2:
			d += _beard(dx, maxi(0, maxi(yb - y, y - pieces[o + 4])), dz, dyb) * 0.8
		elif ad == 3:
			d += _bury(float(dx), float(dyb) / 2.0, float(dz))
		elif ad == 4:
			d += _bury(float(dx) / 2.0, float(maxi(0, maxi(pieces[o + 1] - y, y - pieces[o + 4]))) / 2.0, float(dz) / 2.0) * 0.8
		elif ad == 5:   # JigsawJunction
			var jy := y - pieces[o + 1]
			d += _beard(x - pieces[o], jy, z - pieces[o + 2], jy) * 0.4
	return d


static func _bury(a: float, b: float, c: float) -> float:
	return 1.0 - clampf(sqrt(a * a + b * b + c * c) / 6.0, 0.0, 1.0)


static func _beard(x: int, y: int, z: int, y_to_ground: int) -> float:
	var i := x + 12
	var j := y + 12
	var k := z + 12
	if i < 0 or i >= 24 or j < 0 or j >= 24 or k < 0 or k >= 24:
		return 0.0
	var d0 := float(y_to_ground) + 0.5
	var d1 := float(x * x) + d0 * d0 + float(z * z)
	var d2 := -d0 / sqrt(d1 / 2.0) / 2.0
	return d2 * _kernel[k * 576 + i * 24 + j]


func prefetch(cx: int, cz: int) -> void:
	for st in sets:
		if gen.aborted:
			return
		var pl: Dictionary = st["placement"]
		if str(pl.get("type", "")).trim_prefix("minecraft:") != "random_spread":
			continue
		for sc in _candidates(st, cx, cz, 0):
			if sc.x == cx and sc.y == cz:
				_start(st, sc)


func _scan(origin: Chunk, cmin: Vector3i, cmax: Vector3i) -> Dictionary:
	return _scan_at(origin.cx, origin.cz, cmin, cmax)


func _scan_at(cx: int, cz: int, cmin: Vector3i, cmax: Vector3i) -> Dictionary:
	var by: Dictionary = {"_": true}
	var prof_on := f.profiling
	for st in sets:
		var tset := Time.get_ticks_usec() if prof_on else 0
		for sc in _candidates(st, cx, cz):
			if gen.aborted:
				return by
			var res := _start(st, sc)
			if res.is_empty():
				continue
			var b: Array = res["box"]
			if b[1].x < cmin.x or b[0].x > cmax.x or b[1].z < cmin.z or b[0].z > cmax.z:
				continue
			var stp := int(res["step"])
			if not by.has(stp):
				by[stp] = {}
			var nm := str(res["structure"])
			if not (by[stp] as Dictionary).has(nm):
				by[stp][nm] = []
			(by[stp][nm] as Array).append(res)
		if prof_on:
			var pk := "  set %s (scan)" % st["name"]
			f.profile[pk] = int(f.profile.get(pk, 0)) + Time.get_ticks_usec() - tset
	return by


func _place_found(c: Features.FCtx, found: Dictionary, names: Array, step: int, deco: int, cmin: Vector3i, cmax: Vector3i) -> void:
	var prof_on := f.profiling
	for idx in names.size():
		var nm2: String = names[idx]
		if not found.has(nm2):
			continue
		c.r = RandomSources.WorldgenXoro.seeded(deco + idx + 10000 * step)
		var tpl := Time.get_ticks_usec() if prof_on else 0
		for res in found[nm2]:
			_place_start(c, res, cmin, cmax)
		if prof_on:
			var pk2 := "  place %s" % nm2
			f.profile[pk2] = int(f.profile.get(pk2, 0)) + Time.get_ticks_usec() - tpl


func _place_step_old(c: Features.FCtx, origin: Chunk, step: int, deco: int) -> void:
	var names: Array = by_step[step]
	var cmin := Vector3i(origin.cx * 16, gen.gen_min_y, origin.cz * 16)
	var cmax := cmin + Vector3i(15, gen.gen_depth, 15)
	var found: Dictionary = {}
	var prof_on := f.profiling
	for st in sets:
		var tset := Time.get_ticks_usec() if prof_on else 0
		if f.trace_names:
			printerr("[struct] set %s candidates..." % st["name"])
		for sc in _candidates(st, origin.cx, origin.cz):
			if gen.aborted:
				return
			if f.trace_names:
				printerr("[struct]   start %s at %s" % [st["name"], str(sc)])
			var res := _start(st, sc)
			if res.is_empty() or int(res["step"]) != step:
				continue
			var b: Array = res["box"]
			if b[1].x < cmin.x or b[0].x > cmax.x or b[1].z < cmin.z or b[0].z > cmax.z:
				continue
			var nm := str(res["structure"])
			if not found.has(nm):
				found[nm] = []
			(found[nm] as Array).append(res)
		if prof_on:
			var pk := "  set %s (step %d scan)" % [st["name"], step]
			f.profile[pk] = int(f.profile.get(pk, 0)) + Time.get_ticks_usec() - tset
	for idx in names.size():
		var nm2: String = names[idx]
		if not found.has(nm2):
			continue
		c.r = RandomSources.WorldgenXoro.seeded(deco + idx + 10000 * step)
		var tpl := Time.get_ticks_usec() if prof_on else 0
		for res in found[nm2]:
			_place_start(c, res, cmin, cmax)
		if prof_on:
			var pk2 := "  place %s" % nm2
			f.profile[pk2] = int(f.profile.get(pk2, 0)) + Time.get_ticks_usec() - tpl


func _place_start(c: Features.FCtx, res: Dictionary, cmin: Vector3i, cmax: Vector3i) -> void:
	if res.has("blocks"):
		var key := Vector2i(cmin.x >> 4, cmin.z >> 4)
		var lst = (res["blocks"] as Dictionary).get(key)
		var skipped := {}   # positions of skipped parts (no block entity there)
		if lst != null:
			var arr: PackedInt32Array = lst
			var dry := bool(res.get("dry", false))
			var wet_mask := BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED
			var pi_arr: PackedInt32Array = (res["pidx"] as Dictionary).get(key, PackedInt32Array()) if res.has("pidx") else PackedInt32Array()
			var bad := {}     # part index -> invalid in this chunk
			for k in range(0, arr.size(), 4):
				var bp0 := Vector3i(arr[k], arr[k + 1], arr[k + 2])
				if pi_arr.size() > k / 4:
					var pi := pi_arr[k / 4]
					if not bad.has(pi):
						bad[pi] = _part_touches_liquid(c, res["parts"][pi], cmin, cmax)
					if bad[pi]:
						skipped[bp0] = true
						continue
				if arr[k + 3] == 0 or dry:
					# air never replaces liquid (Java: shipwreck / ocean ruin templates ignore air, the sea stays); mineshafts
					# place nothing into liquid (Java skips pieces touching liquid, isInInvalidLocation) - no air pockets
					var cur := f.get_block(c, bp0)
					if cur > 0 and (f.blocks.st_flags[cur] & wet_mask) != 0:
						continue
				f.set_block(c, bp0, arr[k + 3])
		for bp in res.get("bes", {}):
			if bp.x >= cmin.x and bp.x <= cmax.x and bp.z >= cmin.z and bp.z <= cmax.z and not skipped.has(bp):
				c.block_entities[bp] = res["bes"][bp]
	for p in res.get("pieces", []):
		var b: Array = p["box"]
		if b[1].x < cmin.x or b[0].x > cmax.x or b[1].z < cmin.z or b[0].z > cmax.z:
			continue
		_place_element(c, p["el"], p["pos"], int(p["rot"]), cmin, cmax)
	if str(res.get("after", "")) == "mansion":
		_mansion_after(c, res, cmin, cmax)
	elif str(res.get("after", "")) == "pyramid":
		_pyramid_after(c, res, cmin, cmax)


## DesertPyramidStructure.afterPlace for this chunk: the collapsed roof random block and the first 5..7 shuffled cellar
## candidates become suspicious sand (loot archaeology/desert_pyramid), the other candidates sand.
func _pyramid_after(c: Features.FCtx, res: Dictionary, cmin: Vector3i, cmax: Vector3i) -> void:
	var sus := f.blocks.default_state("suspicious_sand")
	var sand := f.blocks.default_state("sand")
	var picks: Array = [res["sus_roof"]]
	picks.append_array(res["sus"])
	for q in picks:
		var qv: Vector3i = q
		if qv.x >= cmin.x and qv.x <= cmax.x and qv.z >= cmin.z and qv.z <= cmax.z:
			f.set_block(c, qv, sus)
			c.block_entities[qv] = {"id": "suspicious_sand", "loot_table": "archaeology/desert_pyramid", "loot_seed": 0}
	for q2 in res["sand"]:
		var qw: Vector3i = q2
		if qw.x >= cmin.x and qw.x <= cmax.x and qw.z >= cmin.z and qw.z <= cmax.z:
			f.set_block(c, qw, sand)


## WoodlandMansionStructure.afterPlace: under every column of this chunk whose block at the structure's bottom layer is
## not air and lies inside a piece, cobblestone replaces air and liquid downwards until the first other block.
func _mansion_after(c: Features.FCtx, res: Dictionary, cmin: Vector3i, cmax: Vector3i) -> void:
	var bb: Array = res["box"]
	var y0: int = bb[0].y
	var lo := f.gen.gen_min_y
	var blocks := f.blocks
	var cob := blocks.default_state("cobblestone")
	var cave_air := blocks.default_state("cave_air")
	var void_air := blocks.default_state("void_air")
	var fl := blocks.st_flags
	# only pieces spanning the bottom layer inside this chunk can contain the tested positions
	var near: Array = []
	for pc in res["pieces"]:
		var pb: Array = pc["box"]
		if pb[0].y <= y0 and pb[1].y >= y0 and pb[1].x >= cmin.x and pb[0].x <= cmax.x and pb[1].z >= cmin.z and pb[0].z <= cmax.z:
			near.append(pb)
	if near.is_empty():
		return
	for x in range(maxi(cmin.x, bb[0].x), mini(cmax.x, bb[1].x) + 1):
		for z in range(maxi(cmin.z, bb[0].z), mini(cmax.z, bb[1].z) + 1):
			var p := Vector3i(x, y0, z)
			var b0 := f.get_block(c, p)
			if b0 <= 0 or b0 == cave_air or b0 == void_air:
				continue
			var inside := false
			for pb2 in near:
				if _inside(pb2, p):
					inside = true
					break
			if not inside:
				continue
			for m in range(y0 - 1, lo, -1):
				var q := Vector3i(x, m, z)
				var b := f.get_block(c, q)
				if b > 0 and b != cave_air and b != void_air and (fl[b] & BlockRegistry.F_LIQUID) == 0:
					break
				f.set_block(c, q, cob)


## Java StructurePiece.isInInvalidLocation: liquid on the faces of the piece's box grown by 1, within this chunk.
func _part_touches_liquid(c: Features.FCtx, box: Array, cmin: Vector3i, cmax: Vector3i) -> bool:
	var a: Vector3i = box[0] - Vector3i.ONE
	var b: Vector3i = box[1] + Vector3i.ONE
	var x0 := maxi(a.x, cmin.x)
	var z0 := maxi(a.z, cmin.z)
	var x1 := mini(b.x, cmax.x)
	var z1 := mini(b.z, cmax.z)
	var y0 := a.y
	var y1 := b.y
	if x0 > x1 or z0 > z1:
		return false
	var fl := f.blocks.st_flags
	var liq := func(x: int, y: int, z: int) -> bool:
		var s := f.get_block(c, Vector3i(x, y, z))
		return s > 0 and (fl[s] & BlockRegistry.F_LIQUID) != 0
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			if liq.call(x, y0, z) or liq.call(x, y1, z):
				return true
	for x in range(x0, x1 + 1):
		for y in range(y0, y1 + 1):
			if liq.call(x, y, z0) or liq.call(x, y, z1):
				return true
	for z in range(z0, z1 + 1):
		for y in range(y0, y1 + 1):
			if liq.call(x0, y, z) or liq.call(x1, y, z):
				return true
	return false


func _place_element(c: Features.FCtx, el: Dictionary, pos: Vector3i, rot: int, cmin: Vector3i, cmax: Vector3i) -> void:
	match el["t"]:
		"single":
			var tpl := _el_template(el)
			if tpl != null:
				var pv: Vector3i = el.get("pivot", Vector3i.ZERO)
				tpl.place(f, c, pos, rot, el["procs"], bool(el["legacy"]), el["proj"] == "terrain_matching", cmin, cmax, 0, int(el.get("mirror", 0)), pv, str(el.get("markers", "")), not bool(el.get("noents", false)))
				if str(el.get("loc", "")) == "igloo/top":
					# IglooPiece.postProcess: the floor hatch (template (3, 0, 5)) becomes snow unless air or a ladder is below
					var hq := pos + StructureTemplate.transform(Vector3i(3, 0, 5), rot, pv)
					if hq.x >= cmin.x and hq.x <= cmax.x and hq.z >= cmin.z and hq.z <= cmax.z:
						var bs := f.get_block(c, hq + Vector3i(0, -1, 0))
						if bs > 0 and not f.blocks.name_of(bs) in ["ladder", "cave_air", "void_air"]:
							f.set_block(c, hq, f.blocks.default_state("snow_block"))
		"list":
			for s in el["subs"]:
				_place_element(c, s, pos, rot, cmin, cmax)
		"ruined_portal":
			StructuresLegacy.place_ruined_portal(self, c, el, pos, rot, cmin, cmax)
		"java":
			JavaPieces.place(self, c, el, cmin, cmax)
		"feature":
			if pos.x >= cmin.x and pos.x <= cmax.x and pos.z >= cmin.z and pos.z <= cmax.z:
				var pf := f._placed(str(el["feature"]))
				if not pf.is_empty():
					f.place_placed(c, pf, pos)
