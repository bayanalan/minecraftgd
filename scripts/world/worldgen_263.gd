## VanillaGenerator — data-driven terrain from the user's installed 26.3 worldgen data:
## noise_settings router (final_density with cheese/spaghetti/noodle caves, splines, blended noise), 4x8x4 cell
## interpolation, multi-noise biomes (Climate), NoiseBasedAquifer, material rules (surface, bedrock, deepslate,
## copper/iron ore veins, badlands bands), then data-driven feature decoration (Features).
## Profiles: java_26_3 (default/large_biomes/amplified/single_biome world types). java_1_18_2_exact and
## hybrid run the same pipeline and are LABELLED APPROXIMATE (no 1.18.2 reference data installed).
## Contract: WorldGenerator API; thread-safe generate() (per-job contexts; shared caches behind a Mutex).
class_name VanillaGenerator
extends WorldGenerator

var source: Callable
var beard_top := false   # final_density = add(..., beardifier): terrain adaptation around structures (Structures.beard_pieces)
var dfc: DensityFunctions.DFCompiler
var settings_json: Dictionary = {}
var sea_level := 63
var final_density: DensityFunctions.DF
var r_temp: DensityFunctions.DF
var r_veg: DensityFunctions.DF
var r_cont: DensityFunctions.DF
var r_eros: DensityFunctions.DF
var r_depth: DensityFunctions.DF
var r_ridges: DensityFunctions.DF
var prelim_surface: DensityFunctions.DF
var aq_barrier: DensityFunctions.DF
var aq_flood: DensityFunctions.DF
var aq_spread: DensityFunctions.DF
var aq_lava: DensityFunctions.DF
var aq_exclusion: DensityFunctions.DF
var aquifers_enabled := true
var aquifer_rand   # XoroPositional or LegacyPositional
var dim_type: Dictionary = {}     # data/minecraft/dimension_type/<dim>.json
var legacy_random := false
var S_FLUID := 0                  # default_fluid state
var end_biomes := false           # TheEndBiomeSource
var climate: Climate
var surface: SurfaceRules
var features: Features
var carvers: Carvers
var structures: Structures
var biome_ids: Dictionary = {}
var single_biome := -1
var S_DEFAULT := 0
var profile := false
var native_graph := -1    # RecraftNative density graph handle (per generator instance)
var native_tg := -1       # RecraftNative terrain config (fill + aquifer + carvers)
var _mutex := Mutex.new()
var _surface_cache: Dictionary = {}
var stats := {"density_ms": 0.0, "biome_ms": 0.0, "fill_ms": 0.0, "surface_ms": 0.0}


func _setup() -> void:
	source = Res.read_json
	var wt := str(settings.get("world_type", "default"))
	dimension = str(settings.get("dimension", "overworld")).trim_prefix("minecraft:")
	var ns_name := "overworld"
	if dimension == "the_nether":
		ns_name = "nether"
	elif dimension == "the_end":
		ns_name = "end"
	elif wt == "large_biomes":
		ns_name = "large_biomes"
	elif wt == "amplified":
		ns_name = "amplified"
	var dt = source.call("data/minecraft/dimension_type/%s.json" % dimension)
	dim_type = dt if dt is Dictionary else {}
	var j = source.call("data/minecraft/worldgen/noise_settings/%s.json" % ns_name)
	settings_json = j if j is Dictionary else {}
	sea_level = int(settings_json.get("sea_level", 63))
	var nz: Dictionary = settings_json.get("noise", {}) if settings_json.get("noise") is Dictionary else {}
	gen_min_y = int(nz.get("min_y", -64))
	gen_depth = int(nz.get("height", 384))
	legacy_random = bool(settings_json.get("legacy_random_source", false))
	dfc = DensityFunctions.DFCompiler.new(seed, source, legacy_random)
	var router: Dictionary = settings_json.get("noise_router", {})
	final_density = dfc.get_df(router.get("final_density", 0.0))
	# Java Beardifier: added at the top of final_density (add(..., beardifier)) in all three 26.3 routers
	var fdj = router.get("final_density", 0.0)
	if fdj is String:
		fdj = source.call("data/minecraft/worldgen/density_function/" + str(fdj).trim_prefix("minecraft:") + ".json")
	beard_top = false
	if fdj is Dictionary and str(fdj.get("type", "")).trim_prefix("minecraft:") == "add":
		for side in ["left", "right", "argument1", "argument2"]:
			if fdj.get(side) is Dictionary and str(fdj[side].get("type", "")).trim_prefix("minecraft:") == "beardifier":
				beard_top = true
	r_temp = dfc.get_df(router.get("temperature", 0.0))
	r_veg = dfc.get_df(router.get("vegetation", 0.0))
	r_cont = dfc.get_df(router.get("continents", 0.0))
	r_eros = dfc.get_df(router.get("erosion", 0.0))
	r_depth = dfc.get_df(router.get("depth", 0.0))
	r_ridges = dfc.get_df(router.get("ridges", 0.0))
	var aq: Dictionary = settings_json.get("aquifers", {}) if settings_json.get("aquifers") is Dictionary else {}
	aquifers_enabled = not aq.is_empty() and bool(settings_json.get("aquifers_enabled", true))
	aq_barrier = dfc.get_df(aq.get("barrier", 0.0))
	aq_flood = dfc.get_df(aq.get("fluid_level_floodedness", 0.0))
	aq_spread = dfc.get_df(aq.get("fluid_level_spread", 0.0))
	aq_lava = dfc.get_df(aq.get("lava", 0.0))
	aq_exclusion = dfc.get_df(aq.get("exclusion", -1.0))
	prelim_surface = dfc.get_df(aq.get("surface_level", router.get("chunk_surface_level", 0.0)))
	aquifer_rand = dfc.rand.from_hash("minecraft:aquifer").fork_positional()
	S_DEFAULT = _st(str(settings_json.get("default_block", "minecraft:stone")).trim_prefix("minecraft:"))
	var fl := str(settings_json.get("default_fluid", "minecraft:water")).trim_prefix("minecraft:")
	S_FLUID = 0 if fl == "air" else _st(fl)
	end_biomes = dimension == "the_end"
	climate = Climate.nether() if dimension == "the_nether" else Climate.overworld()
	for i in biomes.names.size():
		biome_ids[biomes.names[i]] = i
	if wt == "single_biome":
		single_biome = biomes.id(str(settings.get("single_biome", "plains")))
	surface = SurfaceRules.new(self)
	surface.setup(str(settings_json.get("material_rule", settings_json.get("surface_rule", "minecraft:overworld"))))
	features = Features.new(self)
	ShapeUpdates.prime()
	Support.prime()   # (support-rule kinds per block, built here instead of on the first block change in play)
	features.setup()
	carvers = Carvers.new(self)
	if structures_enabled:
		structures = Structures.new(self, features)
		structures.setup()
	generator_id = generator_id if generator_id != "" else "java_26_3"
	if Native.ok:
		native_graph = int(Native.inst.df_graph(dfc.export_native())[0])
		native_tg = int(Native.inst.tg_config(native_graph, _export_terrain())[0])


func _nid(d: DensityFunctions.DF) -> int:
	return d.id if d != null else -1


func _export_terrain() -> Array:
	var ar = aquifer_rand
	var legacy: bool = ar is RandomSources.LegacyPositional
	var ints: Array = [S_WATER, S_LAVA, sea_level, _nid(aq_barrier), _nid(aq_flood), _nid(aq_spread), _nid(aq_lava), _nid(aq_exclusion),
		_nid(prelim_surface), gen_min_y, gen_depth, 1 if aquifers_enabled else 0, S_FLUID, S_DEFAULT, 1 if legacy else 0,
		ar.seed if legacy else ar.lo, 0 if legacy else ar.hi, S_GRASS, blocks.block_id("grass_block"), blocks.block_id("mycelium"),
		blocks.block_id("dirt"), BlockRegistry.F_LIQUID, final_density.id, seed]
	var nb := 0
	for b in blocks.st_block:
		nb = maxi(nb, b + 1)
	var cv := carvers.export_native(nb)
	return [ints, blocks.st_block, blocks.st_flags, cv[0], cv[1], cv[2], surface.export_native(), _export_climate()]


## Climate parameter points for native biome lookup (same column/pick algorithm and tie-breaking as Climate).
func _export_climate() -> Array:
	var cl := climate
	var multi := single_biome < 0 and not end_biomes
	var flags := PackedInt32Array([1 if multi else 0, 1, single_biome, int(biome_ids.get("plains", 0)),
		_nid(r_temp), _nid(r_veg), _nid(r_cont), _nid(r_eros), _nid(r_depth), _nid(r_ridges)])
	var mn := PackedFloat64Array()
	var mx := PackedFloat64Array()
	for k in 6:
		for v in cl.pmin[k]:
			mn.append(v)
		for v in cl.pmax[k]:
			mx.append(v)
	var of := PackedFloat64Array()
	for v in cl.offs:
		of.append(v)
	var pb := PackedInt32Array()
	for nm in cl.names:
		pb.append(int(biome_ids.get(nm, 0)))
	var gl := PackedFloat64Array()
	var gh := PackedFloat64Array()
	for v in cl.group_lo:
		gl.append(v)
	for v in cl.group_hi:
		gh.append(v)
	return [flags, mn, mx, of, cl.point_group, pb, gl, gh]


func surface_height(x: int, z: int) -> int:
	var ctx := DensityFunctions.Ctx.new(dfc.node_count())
	return chunk_surface(ctx, x, z)


## Preliminary surface interpolated on the 16-block grid (Java chunk_surface_level semantics); shared cache.
func chunk_surface(ctx: DensityFunctions.Ctx, x: int, z: int) -> int:
	var gx := floori(x / 16.0)
	var gz := floori(z / 16.0)
	var fx := (x - gx * 16) / 16.0
	var fz := (z - gz * 16) / 16.0
	var a := _grid_surface(ctx, gx, gz)
	var b := _grid_surface(ctx, gx + 1, gz)
	var c := _grid_surface(ctx, gx, gz + 1)
	var d := _grid_surface(ctx, gx + 1, gz + 1)
	var top := a + fx * (b - a)
	var bot := c + fx * (d - c)
	return floori(top + fz * (bot - top))


func _grid_surface(ctx: DensityFunctions.Ctx, gx: int, gz: int) -> float:
	var key := Vector2i(gx, gz)
	_mutex.lock()
	var v = _surface_cache.get(key)
	_mutex.unlock()
	if v != null:
		return v
	var had := ctx.has_chunk
	ctx.has_chunk = false
	var r := prelim_surface.point(ctx, gx * 16, 0, gz * 16)
	ctx.has_chunk = had
	_mutex.lock()
	if _surface_cache.size() > 200000:
		_surface_cache.clear()
	_surface_cache[key] = r
	_mutex.unlock()
	return r


func biome_temperature_at(bio: int, _x: int, y: int, _z: int) -> float:
	var t: float = biomes.temperature[bio]
	var lim := sea_level + 17
	if y > lim:
		t -= float(y - lim) * 0.05 / 40.0
	return t


func generate(ch: Chunk) -> void:
	if aborted:
		return
	var t0 := Time.get_ticks_usec()
	# the GDScript density context is only needed by fallback paths; allocating it costs ~90 ms per chunk under
	# multi-threaded contention, so the all-native path skips it
	# (the End's biome source needs one erosion sample per chunk: native point evaluation, end_biome_at)
	var all_native := native_tg >= 0 and Native.density_ok and Native.surface_ok and Native.climate_ok and not profile
	var ctx: DensityFunctions.Ctx = null
	var blocks_pts: DensityFunctions.Pts = null
	if not all_native:
		ctx = DensityFunctions.Ctx.new(dfc.node_count())
		ctx.x0 = ch.cx * 16
		ctx.z0 = ch.cz * 16
		ctx.has_chunk = true
		blocks_pts = ctx.chunk_blocks()
	if profile:
		ctx.prof[-1] = [0, 0, 0]
		var tc := Time.get_ticks_usec()
		final_density.batch(ctx, ctx.corners(4, 8))
		print("[gen] corners %.1f ms" % ((Time.get_ticks_usec() - tc) / 1000.0))
		var ids: Array = ctx.prof.keys()
		ids.erase(-1)
		ids.sort_custom(func(p, q): return ctx.prof[p][0] > ctx.prof[q][0])
		for id in ids.slice(0, 14):
			var node: DensityFunctions.DF = dfc.nodes[id]
			print("   node %d %s %s: %.1f ms incl, calls %d, pts %d" % [id, DensityFunctions.K.keys()[node.k], node.name, ctx.prof[id][0] / 1000.0, ctx.prof[id][1], ctx.prof[id][2]])
		ctx.prof.clear()
	var tb := Time.get_ticks_usec()
	if _gprof_init == 0:
		_gprof_init = 1
		_gprof = OS.has_environment("RC_DFPROF")
	# native path: density + noise fill + aquifer (+ carvers below) in RecraftNative (bit-exact, see --nativecheck)
	var tg_job := -1
	var native_bio := PackedByteArray()
	var col := PackedInt32Array()
	var skip_above := gen_min_y + gen_depth
	var dens: PackedFloat64Array
	# Java Beardifier pieces (structure starts are computed here, before the noise, as Java's STRUCTURE_STARTS status)
	var tbp := Time.get_ticks_usec()
	var beard := structures.beard_pieces(ch.cx, ch.cz) if beard_top and structures != null else PackedInt32Array()
	var tbp1 := Time.get_ticks_usec()
	if native_tg >= 0 and Native.density_ok:
		var tg: Array = Native.inst.tg_begin(native_tg, ch.cx, ch.cz, beard)
		tg_job = tg[0]
		col = tg[1]
		skip_above = tg[2]
		if tg.size() > 3 and Native.climate_ok:
			native_bio = tg[3]
	else:
		skip_above = _aquifer_ceiling(ctx, ch) if aquifers_enabled else gen_min_y + gen_depth
		if profile:
			print("[gen] ceiling %.1f ms (ceiling y=%d)" % [(Time.get_ticks_usec() - tb) / 1000.0, skip_above])
		dens = _cell_density(ctx, blocks_pts, skip_above, not beard.is_empty())
		if not beard.is_empty():
			for di in 98304:
				var by := Coords.MIN_Y + (di >> 8)
				if by >= gen_min_y and by < gen_min_y + gen_depth:
					dens[di] += Structures.beard_at(beard, ch.cx * 16 + (di & 15), by, ch.cz * 16 + ((di >> 4) & 15))
	var gtop := gen_min_y + gen_depth
	if profile:
		print("[gen] blocks %.1f ms" % ((Time.get_ticks_usec() - tb) / 1000.0))
	var t1 := Time.get_ticks_usec()
	if aborted:
		if tg_job >= 0:
			Native.inst.tg_end(tg_job)
		return
	if native_bio.size() == 1536:
		ch.biomes = native_bio
	else:
		_biomes(ctx, ch)
	var t2 := Time.get_ticks_usec()
	# --- noise fill + aquifer
	var aq: Aquifer = null
	var water := S_WATER
	var lava := S_LAVA
	var stone := S_DEFAULT
	var x0 := ch.cx * 16
	var z0 := ch.cz * 16
	var sea := sea_level
	var lava_y := mini(-54, sea)
	if tg_job < 0:
		col.resize(98304)
		aq = Aquifer.new(self, ctx, ch.cx, ch.cz) if aquifers_enabled else null
	for i in (98304 if tg_job < 0 else 0):
		var d := dens[i]
		if d > 0.0:
			col[i] = stone
			continue
		var y := -64 + (i >> 8)
		if aq == null:
			# disabled aquifer: global fluid picker (lava below min(-54, sea), default fluid below sea level)
			if y < gen_min_y or y >= gtop:
				continue
			col[i] = lava if y < lava_y else (S_FLUID if y < sea else 0)
			continue
		if y > skip_above:
			continue
		if y < lava_y:
			col[i] = lava
			continue
		var s := aq.substance(x0 + (i & 15), y, z0 + ((i >> 4) & 15), d)
		col[i] = stone if s < 0 else s
	var t3 := Time.get_ticks_usec()
	# --- heightmap (WORLD_SURFACE_WG) + material rules
	var hm := PackedInt32Array()
	hm.resize(256)
	var native_surface := tg_job >= 0 and Native.surface_ok
	for c in (0 if native_surface else 256):
		var top := Coords.MIN_Y
		for ly in range(Coords.HEIGHT - 1, -1, -1):
			if col[(ly << 8) | c] != 0:
				top = Coords.MIN_Y + ly + 1
				break
		hm[c] = top
	var tsf0 := Time.get_ticks_usec()
	if native_surface:
		col = Native.inst.tg_surface(tg_job, col, ch.biomes)[0]
	else:
		surface.apply_chunk(ctx, blocks_pts, col, ch.biomes, hm, stone)
	var tsf1 := Time.get_ticks_usec()
	var tc0 := Time.get_ticks_usec()
	if tg_job >= 0:
		col = Native.inst.tg_carve(tg_job, col, PackedInt32Array() if Native.climate_ok else carvers.source_biomes(ch.cx, ch.cz))[0]
		Native.inst.tg_end(tg_job)
	else:
		carvers.carve(col, ch.cx, ch.cz, aq)
	if _gprof:
		print("[genprof] beard %.2f | begin %.2f | biomes %.2f | surface %.2f | carve %.2f ms" % [(tbp1 - tbp) / 1000.0, (t1 - tbp1) / 1000.0, (t2 - t1) / 1000.0, (tsf1 - tsf0) / 1000.0, (Time.get_ticks_usec() - tc0) / 1000.0])
	_mutex.lock()
	stats["carve_ms"] = lerpf(stats.get("carve_ms", 0.0), (Time.get_ticks_usec() - tc0) / 1000.0, 0.1)
	_mutex.unlock()
	if tg_job >= 0 and Native.chunkops_ok:
		var tfin := Time.get_ticks_usec()
		# native tail: WORLD_SURFACE_WG scan, pristine surface/floor, section packing, heightmap
		var fin: Array = Native.inst.chunk_finish(col, blocks.st_flags, blocks.st_opacity, BlockRegistry.F_LIQUID)
		ch.set_sections(fin[0])
		ch.heightmap = fin[1]
		ch.gen_surface = fin[2]
		ch.gen_top = fin[3]
		ch.gen_floor = fin[4]
		if structures != null and Native.features_ok:
			structures.prefetch(ch.cx, ch.cz)
		_mutex.lock()
		stats["n"] = int(stats.get("n", 0)) + 1
		stats["sum_total_us"] = int(stats.get("sum_total_us", 0)) + Time.get_ticks_usec() - t0
		stats["sum_begin_us"] = int(stats.get("sum_begin_us", 0)) + t1 - tb
		stats["sum_pre_us"] = int(stats.get("sum_pre_us", 0)) + tb - t0
		stats["sum_finish_us"] = int(stats.get("sum_finish_us", 0)) + Time.get_ticks_usec() - tfin
		stats["sum_mid_us"] = int(stats.get("sum_mid_us", 0)) + tfin - t1
		stats["total_ms"] = lerpf(stats.get("total_ms", 0.0), (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
		stats["density_ms"] = lerpf(stats["density_ms"], (t1 - t0) / 1000.0, 0.1)
		stats["biome_ms"] = lerpf(stats["biome_ms"], (t2 - t1) / 1000.0, 0.1)
		stats["fill_ms"] = lerpf(stats["fill_ms"], (t3 - t2) / 1000.0, 0.1)
		_mutex.unlock()
		return
	for c in 256:
		var top2 := Coords.MIN_Y
		for ly in range(Coords.HEIGHT - 1, -1, -1):
			if col[(ly << 8) | c] != 0:
				top2 = Coords.MIN_Y + ly + 1
				break
		hm[c] = top2
	var t4 := Time.get_ticks_usec()
	ch.gen_surface.resize(256)
	ch.gen_top.resize(256)
	ch.gen_floor.resize(256)
	var fl := blocks.st_flags
	for c in 256:
		var fy := hm[c] - 1
		while fy >= Coords.MIN_Y:
			var fs := col[((fy - Coords.MIN_Y) << 8) | c]
			if fs != 0 and (fl[fs] & BlockRegistry.F_LIQUID) == 0:
				break
			fy -= 1
		ch.gen_floor[c] = fy + 1
		var y2 := hm[c] - 1
		# motion-blocking pristine top (skip fluids for tree placement decisions, keep fluid as top block)
		ch.gen_surface[c] = y2
		ch.gen_top[c] = col[((y2 - Coords.MIN_Y) << 8) | c] if y2 >= Coords.MIN_Y else 0
	var t5 := Time.get_ticks_usec()
	ch.fill_from_column(col)
	var t6 := Time.get_ticks_usec()
	ch.recompute_heightmap(blocks)
	_mutex.lock()
	stats["gsurf_ms"] = lerpf(stats.get("gsurf_ms", 0.0), (t5 - t4) / 1000.0, 0.1)
	stats["fillsec_ms"] = lerpf(stats.get("fillsec_ms", 0.0), (t6 - t5) / 1000.0, 0.1)
	stats["hmap_ms"] = lerpf(stats.get("hmap_ms", 0.0), (Time.get_ticks_usec() - t6) / 1000.0, 0.1)
	stats["total_ms"] = lerpf(stats.get("total_ms", 0.0), (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	stats["density_ms"] = lerpf(stats["density_ms"], (t1 - t0) / 1000.0, 0.1)
	stats["biome_ms"] = lerpf(stats["biome_ms"], (t2 - t1) / 1000.0, 0.1)
	stats["fill_ms"] = lerpf(stats["fill_ms"], (t3 - t2) / 1000.0, 0.1)
	stats["surface_ms"] = lerpf(stats["surface_ms"], (t4 - t3) / 1000.0, 0.1)
	_mutex.unlock()


## Exact cell classification: interval bounds of final_density over each 4x8x4 cell (trilinear values lie
## within corner min/max). Fully solid cells -> +1, fully non-solid cells above the aquifer ceiling -> -1 (air);
## only remaining cells are evaluated per block (cell-major sub-batch). Output identical to full evaluation for
## every decision the fill/aquifer stages make.
func _cell_density(ctx: DensityFunctions.Ctx, blocks_pts: DensityFunctions.Pts, ceiling: int, exact := false) -> PackedFloat64Array:
	var dens := PackedFloat64Array()
	dens.resize(98304)
	var cvc := {}
	var ti := Time.get_ticks_usec()
	var active := PackedInt32Array()
	var bounds := final_density.interval_all(ctx, cvc)
	var blo: PackedFloat64Array = bounds[0]
	var bhi: PackedFloat64Array = bounds[1]
	var nlo := gen_min_y
	var nhi := gen_min_y + gen_depth
	for cell in 768:
		var iv := Vector2(blo[cell], bhi[cell])
		var iy := cell >> 4
		var y0 := Coords.MIN_Y + iy * 8
		var fill := 0.0
		if y0 < nlo or y0 >= nhi:
			fill = -1.0   # outside the noise range: no terrain (Java NoiseChunk only fills min_y..min_y+height)
		elif exact:
			active.append(cell)   # a beardifier term follows: sign-only shortcuts would be wrong
			continue
		elif iv.x > 0.0:
			fill = 1.0
		elif iv.y <= 0.0 and y0 > ceiling:
			fill = -1.0
		else:
			active.append(cell)
			continue
		var ix := cell & 3
		var iz := (cell >> 2) & 3
		for ly in 8:
			var row := ((iy * 8 + ly) << 8) | (iz * 4 << 4) | (ix * 4)
			for lz in 4:
				var o := row + (lz << 4)
				dens[o] = fill
				dens[o + 1] = fill
				dens[o + 2] = fill
				dens[o + 3] = fill
	if profile:
		print("[gen] active cells %d / 768, classify %.1f ms" % [active.size(), (Time.get_ticks_usec() - ti) / 1000.0])
	if active.is_empty():
		return dens
	var idx := PackedInt32Array()
	idx.resize(active.size() * 128)
	var w := 0
	for cell in active:
		var ix2 := cell & 3
		var iz2 := (cell >> 2) & 3
		var iy2 := cell >> 4
		for ly in 8:
			for lz in 4:
				var base := ((iy2 * 8 + ly) << 8) | ((iz2 * 4 + lz) << 4) | (ix2 * 4)
				idx[w] = base
				idx[w + 1] = base + 1
				idx[w + 2] = base + 2
				idx[w + 3] = base + 3
				w += 4
	var sub := ctx.sub(blocks_pts, idx)
	sub.cells = active
	if profile:
		ctx.prof[-1] = [0, 0, 0]
	var tv := Time.get_ticks_usec()
	var vals := final_density.batch(ctx, sub)
	if profile:
		print("[gen] block eval %.1f ms for %d pts" % [(Time.get_ticks_usec() - tv) / 1000.0, idx.size()])
		var ids: Array = ctx.prof.keys()
		ids.erase(-1)
		ids.sort_custom(func(p, q): return ctx.prof[p][0] > ctx.prof[q][0])
		for id in ids.slice(0, 12):
			var node: DensityFunctions.DF = dfc.nodes[id]
			print("   bnode %d %s %s: %.1f ms incl, calls %d, pts %d" % [id, DensityFunctions.K.keys()[node.k], node.name, ctx.prof[id][0] / 1000.0, ctx.prof[id][1], ctx.prof[id][2]])
		ctx.prof.clear()
	for i in idx.size():
		dens[idx[i]] = vals[i]
	return dens


## Exact early-out bound for aquifer evaluation: above max(sea level, max nearby preliminary surface)+6 every
## aquifer status yields air with negative barrier pressure (see Aquifer._pressure: v < -2 => no barrier).
func _aquifer_ceiling(ctx: DensityFunctions.Ctx, ch: Chunk) -> int:
	var m := sea_level
	for gz in range(ch.cz - 4, ch.cz + 6):
		for gx in range(ch.cx - 4, ch.cx + 6):
			m = maxi(m, ceili(_grid_surface(ctx, gx, gz)) + 8)
	return m + 6


func _biomes(ctx: DensityFunctions.Ctx, ch: Chunk) -> void:
	if single_biome >= 0:
		ch.biomes.fill(single_biome)
		return
	if end_biomes:
		ch.biomes.fill(end_biome_at(ctx, ch.cx, ch.cz))
		return
	var xs := PackedInt32Array()
	var ys := PackedInt32Array()
	var zs := PackedInt32Array()
	for qy in 96:
		for qz in 4:
			for qx in 4:
				xs.append(ctx.x0 + qx * 4)
				ys.append(Coords.MIN_Y + qy * 4)
				zs.append(ctx.z0 + qz * 4)
	var t: PackedFloat64Array
	var h: PackedFloat64Array
	var c: PackedFloat64Array
	var e: PackedFloat64Array
	var w: PackedFloat64Array
	var d: PackedFloat64Array
	if native_graph >= 0 and Native.density_ok:
		var all: PackedFloat64Array = Native.inst.df_points(native_graph, PackedInt32Array([r_temp.id, r_veg.id, r_cont.id, r_eros.id, r_ridges.id, r_depth.id]), xs, ys, zs, ch.cx, ch.cz, 1)[0]
		t = all.slice(0, 1536)
		h = all.slice(1536, 3072)
		c = all.slice(3072, 4608)
		e = all.slice(4608, 6144)
		w = all.slice(6144, 7680)
		d = all.slice(7680, 9216)
	else:
		var pts := ctx.new_root(xs, ys, zs)
		t = r_temp.batch(ctx, pts)
		h = r_veg.batch(ctx, pts)
		c = r_cont.batch(ctx, pts)
		e = r_eros.batch(ctx, pts)
		w = r_ridges.batch(ctx, pts)
		d = r_depth.batch(ctx, pts)
	var cols: Array = []
	for qc in 16:
		cols.append(climate.column(t[qc], h[qc], c[qc], e[qc], w[qc]))
	for qy in 96:
		for qc in 16:
			var i := qy * 16 + qc
			var name := climate.pick(cols[qc], d[i])
			ch.biomes[(qc & 3) + (qc >> 2) * 4 + qy * 16] = int(biome_ids.get(name, 0))


## Java TheEndBiomeSource: main island within 64 chunks; else by erosion (end islands) at the chunk centre.
## Biome at a block position from the biome source (quart resolution, Java BiomeSource.getNoiseBiome).
func biome_at_block(ctx: DensityFunctions.Ctx, x: int, y: int, z: int) -> int:
	if end_biomes:
		return end_biome_at(ctx, x >> 4, z >> 4)
	if single_biome >= 0:
		return single_biome
	var qx := (x >> 2) << 2
	var qy := (y >> 2) << 2
	var qz := (z >> 2) << 2
	var nm := climate.find(r_temp.point(ctx, qx, qy, qz), r_veg.point(ctx, qx, qy, qz), r_cont.point(ctx, qx, qy, qz), r_eros.point(ctx, qx, qy, qz), r_depth.point(ctx, qx, qy, qz), r_ridges.point(ctx, qx, qy, qz))
	return int(biome_ids.get(nm, 0))


## Java Mth.outFromOrigin(y, lo, hi, step): y, y + step, y - step, y + 2 step, ... within [lo, hi]; empty when y is
## outside.
static func out_from_origin(y: int, lo: int, hi: int, step: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if y < lo or y > hi:
		return out
	var i := y
	while true:
		out.append(i)
		var n := absi(y - i)
		var below := i <= y
		var nxt := y + n + step
		if not below or y + n + step > hi:
			var o := y - n - (step if below else 0)
			if o >= lo:
				nxt = o
		i = nxt
		var m := absi(y - i)
		if not (y - m >= lo or y + m <= hi):
			break
	return out


var last_found_biome := -1   # biome id of the last find_biome hit (/locate biome with a tag)
var native_find := true      # false: the GDScript reference search (--biomecheck compares both)


## Java ChunkGenerator.findClosestBiome3d (/locate biome: radius 6400, step 32, vertical step 64): columns in
## BlockPos.spiralAround order, at each the heights out from y; the first quart biome in `ids` wins. Native when the
## generator has its multi-noise biome source (RecraftNative.tg_find_biome, the same order and sampling).
func find_biome(bid, x: int, y: int, z: int, radius: int = 6400, step: int = 32, vstep: int = 64) -> Vector3i:
	var ids: Array = bid if bid is Array else [bid]
	var ys := out_from_origin(y, gen_min_y + 1, gen_min_y + gen_depth, vstep)
	if ys.is_empty():
		return Vector3i(0, -999999, 0)
	var size := floori(float(radius) / step)
	if native_find and native_tg >= 0 and Native.density_ok and not end_biomes and Native.inst.has_method("tg_find_biome"):
		var want := PackedByteArray()
		var top := 0
		for i in ids:
			top = maxi(top, int(i) + 1)
		want.resize(top)
		for i2 in ids:
			want[int(i2)] = 1
		var r: Array = Native.inst.tg_find_biome(native_tg, want, x, z, ys, size, step)
		if int(r[0]) == 1:
			last_found_biome = int(r[4])
			return Vector3i(int(r[1]), int(r[2]), int(r[3]))
		if int(r[0]) == 0:
			return Vector3i(0, -999999, 0)
	var ctx := DensityFunctions.Ctx.new(dfc.node_count())
	var dirs := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]
	var total := (2 * size + 1) * (2 * size + 1)
	var c := Vector2i.ZERO
	var leg := 0
	var li := 0
	for e in total:
		if e > 0:
			c += dirs[leg & 3]
			li += 1
			if li >= leg / 2 + 1:
				li = 0
				leg += 1
		for yy in ys:
			var fb := biome_at_block(ctx, x + c.x * step, yy, z + c.y * step)
			if ids.has(fb):
				last_found_biome = fb
				return Vector3i(x + c.x * step, yy, z + c.y * step)
	return Vector3i(0, -999999, 0)


func end_biome_at(ctx: DensityFunctions.Ctx, cx: int, cz: int) -> int:
	if cx * cx + cz * cz <= 4096:
		return int(biome_ids.get("the_end", 0))
	var d: float
	if ctx == null and native_graph >= 0 and Native.density_ok:
		# Java TheEndBiomeSource: erosion (end islands) at the chunk centre, y 0; native point mode (no GDScript context:
		# building one per chunk cost ~90 ms under contention)
		d = float((Native.inst.df_points(native_graph, PackedInt32Array([r_eros.id]), PackedInt32Array([cx * 16 + 8]), PackedInt32Array([0]), PackedInt32Array([cz * 16 + 8]), cx, cz, 0)[0] as PackedFloat64Array)[0])
	else:
		if ctx == null:
			ctx = DensityFunctions.Ctx.new(dfc.node_count())
		d = r_eros.point(ctx, cx * 16 + 8, 0, cz * 16 + 8)
	var nm := "small_end_islands"
	if d > 0.25:
		nm = "end_highlands"
	elif d >= -0.0625:
		nm = "end_midlands"
	elif d >= -0.21875:
		nm = "end_barrens"
	return int(biome_ids.get(nm, 0))


func climate_at(x: int, y: int, z: int) -> Dictionary:
	var ctx := DensityFunctions.Ctx.new(dfc.node_count())
	return {"T": r_temp.point(ctx, x, y, z), "H": r_veg.point(ctx, x, y, z), "C": r_cont.point(ctx, x, y, z),
		"E": r_eros.point(ctx, x, y, z), "D": r_depth.point(ctx, x, y, z), "W": r_ridges.point(ctx, x, y, z)}


func uses_feature_stage() -> bool:
	return true


func compute_features(c: Chunk, region: ChunkRegion) -> PackedInt32Array:
	return features.compute(c, region)


func decorate(ch: Chunk, region: ChunkRegion) -> void:
	if not features.apply(ch, region.chunks):
		ch.recompute_heightmap(blocks)


static var _gprof := false
static var _gprof_init := 0
