## BenchRunner — `godot --headless --path . -- --bench [--gen=java_26_3] [--n=4]`.
## Single-threaded worldgen/feature/light/mesh timings per stage; prints BENCH lines and writes
## user://bench/worldgen.json (consumed by docs/BENCHMARKS.md).
extends Node

var _ox := 0
var _oz := 0


func _ready() -> void:
	var opts := {"gen": "java_26_3" if Res.mode == "vanilla" else "approx_original", "n": "4", "seed": "12345"}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=")
			opts[kv[0]] = kv[1]
	var biomes := BiomeRegistry.new()
	biomes.build()
	var t0 := Time.get_ticks_msec()
	var g := WorldGenerator.create(str(opts["gen"]))
	g.setup(int(opts["seed"]), Res.blocks, biomes, {"structures": true, "dimension": str(opts.get("dim", "overworld"))})
	var ox := int(opts.get("cx", "0"))
	var oz := int(opts.get("cz", "0"))
	_ox = ox
	_oz = oz
	var setup_ms := Time.get_ticks_msec() - t0
	if g is VanillaGenerator:
		(g as VanillaGenerator).features.profiling = true
	if g is VanillaGenerator and OS.get_cmdline_user_args().has("--sprof"):
		(g as VanillaGenerator).surface.prof_on = true
	if g is VanillaGenerator and OS.get_cmdline_user_args().has("--profile"):
		(g as VanillaGenerator).profile = true
	print("BENCH setup %s: %d ms" % [opts["gen"], setup_ms])
	if opts.has("locate") and g is VanillaGenerator:
		var sg: Structures = (g as VanillaGenerator).structures
		var want := str(opts["locate"])
		var tq := Time.get_ticks_msec()
		print("LOCATE-CMD %s -> %s in %d ms" % [want, str(sg.locate(want, 0, 0)), Time.get_ticks_msec() - tq])
		if opts.has("cmdonly"):
			get_tree().quit()
			return
		var tl := Time.get_ticks_msec()
		var hits := 0
		if want == "stronghold":
			var shc := sg.nearest_stronghold(0, 0)
			for st0 in sg.sets:
				if str(st0["placement"].get("type", "")).ends_with("concentric_rings"):
					var rs := sg._start(st0, shc)
					print("LOCATE stronghold chunk %s -> %s blocks-chunks %d" % [str(shc), str(rs.get("center", "none")), (rs.get("blocks", {}) as Dictionary).size()])
		for st in sg.sets:
			var has := false
			for e in st["entries"]:
				if str(e["name"]) == want or str(e["name"]).begins_with(want):
					has = true
			if not has:
				continue
			for rz in range(-6, 7):
				for rx in range(-6, 7):
					for scn in sg._candidates(st, rx * 16, rz * 16):
						var res := sg._start(st, scn)
						if not res.is_empty() and str(res["structure"]).begins_with(want):
							print("LOCATE %s at chunk %s center %s pieces %d" % [res["structure"], str(scn), str(res["center"]), (res.get("pieces", []) as Array).size()])
							for pc in res.get("pieces", []):
								var el: Dictionary = pc["el"]
								var tp: StructureTemplate = StructureTemplate.get_template(str(el.get("loc", ""))) if el["t"] == "single" else null
								print("  piece %s rot %d pos %s jigsaws %s" % [el.get("loc", el["t"]), pc["rot"], str(pc["pos"]), str(tp.jigsaws if tp != null else "null")])
							hits += 1
					if hits >= 2:
						break
				if hits >= 2:
					break
		print("LOCATE done in %d ms " % (Time.get_ticks_msec() - tl), sg.stats)
		get_tree().quit()
		return
	if opts.has("findbiome") and g is VanillaGenerator:
		var tb := Time.get_ticks_msec()
		var bid0: int = (g as VanillaGenerator).biome_ids.get("minecraft:" + str(opts["findbiome"]), (g as VanillaGenerator).biome_ids.get(str(opts["findbiome"]), -1))
		print("FINDBIOME %s (id %d) -> %s in %d ms" % [opts["findbiome"], bid0, str((g as VanillaGenerator).find_biome(bid0, 0, 0, 0)), Time.get_ticks_msec() - tb])
		get_tree().quit()
		return
	if opts.has("ftypes") and g is VanillaGenerator:
		# histogram of configured feature types used by this dimension's biomes (dev tool)
		var fh := {}
		var ex := {}
		for k in (g as VanillaGenerator).features.configured:
			var cfx: Dictionary = (g as VanillaGenerator).features.configured[k]
			var ft := str(cfx.get("t", "?"))
			fh[ft] = int(fh.get(ft, 0)) + 1
			ex[ft] = k
		for ft in fh:
			print("FTYPE %s %d e.g. %s" % [ft, fh[ft], ex[ft]])
		get_tree().quit()
		return
	if opts.has("ftree") and g is VanillaGenerator:
		var fe: Features = (g as VanillaGenerator).features
		for nm in str(opts["ftree"]).split(","):
			print("FTREE ", nm, ": ", _ftree(fe, fe._placed("minecraft:" + nm), 0))
		get_tree().quit()
		return
	if opts.has("mt"):
		_mt_bench(int(opts["mt"]), biomes, int(opts["seed"]))
		get_tree().quit()
		return
	var n := int(opts["n"])
	var chunks := {}
	var gen_times: Array = []
	for z in range(-1, n + 1):
		for x in range(-1, 2):
			var c := Chunk.new(x + ox, z + oz)
			var t1 := Time.get_ticks_usec()
			g.generate(c)
			gen_times.append((Time.get_ticks_usec() - t1) / 1000.0)
			c.state = Chunk.DATA_READY
			chunks[Vector2i(x, z)] = c
	print("BENCH generate: avg %.1f ms over %d chunks" % [_avg(gen_times), gen_times.size()])
	if g is VanillaGenerator:
		print("BENCH   breakdown density %.1f / biome %.1f / fill+aquifer %.1f / surface %.1f ms" % [g.stats["density_ms"], g.stats["biome_ms"], g.stats["fill_ms"], g.stats["surface_ms"]])
		print("BENCH   stats ", g.stats)
		if g.surface.prof_on:
			print("BENCH   surface prof ", g.surface.prof, " C enum ", SurfaceRules.C.keys())
	var feat_times: Array = []
	if g.uses_feature_stage():
		for z in range(0, n):
			var c2: Chunk = chunks[Vector2i(0, z)]
			var t2 := Time.get_ticks_usec()
			c2.feature_writes = g.compute_features(c2, _region(chunks, 0, z))
			feat_times.append((Time.get_ticks_usec() - t2) / 1000.0)
		print("BENCH features: avg %.1f ms (%d writes last)" % [_avg(feat_times), chunks[Vector2i(0, n - 1)].feature_writes.size() / 5])
		if g is VanillaGenerator:
			var pr: Dictionary = (g as VanillaGenerator).features.profile
			var ks: Array = pr.keys()
			ks.sort_custom(func(a, b): return pr[a] > pr[b])
			for k in ks.slice(0, 40):
				print("BENCH   feature %s %.1f ms" % [k, pr[k] / 1000.0 / feat_times.size()])
		if g is VanillaGenerator:
			print("BENCH unsupported feature types: ", (g as VanillaGenerator).features.unsupported)
			if (g as VanillaGenerator).structures != null:
				print("BENCH structure stats: ", (g as VanillaGenerator).structures.stats)
	var dec_times: Array = []
	for z in range(1, n - 1):
		var c3: Chunk = chunks[Vector2i(0, z)]
		var t3 := Time.get_ticks_usec()
		g.decorate(c3, _region(chunks, 0, z))
		dec_times.append((Time.get_ticks_usec() - t3) / 1000.0)
	print("BENCH decorate: avg %.1f ms" % _avg(dec_times))
	# light + mesh on chunk (0,1)
	var mid := 1
	var snaps: Array = []
	var hms: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cc: Chunk = chunks.get(Vector2i(dx, mid + dz))
			cc.recompute_heightmap(Res.blocks)
			snaps.append(cc.snapshot())
			hms.append(cc.heightmap)
	Lighting.profile = true
	var t4 := Time.get_ticks_usec()
	var light := Lighting.compute(snaps, hms, Res.blocks)
	print("BENCH light: %.1f ms" % ((Time.get_ticks_usec() - t4) / 1000.0))
	var tints := PackedColorArray()
	tints.resize(768)
	tints.fill(Color(0.5, 0.75, 0.35))
	var mesh_total := 0.0
	var verts := 0
	for gi in Coords.SECTIONS / Mesher.GROUP:
		var t5 := Time.get_ticks_usec()
		var res := Mesher.build({"snaps": snaps, "light": light, "group": gi, "blocks": Res.blocks, "tints": tints})
		mesh_total += (Time.get_ticks_usec() - t5) / 1000.0
		if not res.is_empty():
			for k in ["opaque", "cutout", "translucent"]:
				var arr: Array = res[k]
				if not arr.is_empty():
					verts += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	print("BENCH mesh: %.1f ms for one chunk column, %d verts" % [mesh_total, verts])
	var out := {"generator": opts["gen"], "setup_ms": setup_ms, "generate_ms": _avg(gen_times), "features_ms": _avg(feat_times),
		"decorate_ms": _avg(dec_times), "mesh_column_ms": mesh_total, "verts": verts, "cpu": OS.get_processor_name(), "threads": OS.get_processor_count(),
		"godot": Engine.get_version_info()["string"], "time": Time.get_datetime_string_from_system()}
	if g is VanillaGenerator:
		out["breakdown"] = g.stats
	DirAccess.make_dir_recursive_absolute("user://bench")
	var f := FileAccess.open("user://bench/worldgen_%s.json" % opts["gen"], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	get_tree().quit()


## Contention probe: K generators, K disjoint chunk strips; feature jobs timed sequentially vs on K threads.
var _mt_gens: Array = []
var _mt_strips: Array = []
var _mt_times: Array = []


func _mt_bench(k: int, biomes: BiomeRegistry, seed: int) -> void:
	for i in k:
		var g := WorldGenerator.create("java_26_3")
		g.setup(seed, Res.blocks.clone() if OS.get_cmdline_user_args().has("--clone") else Res.blocks, biomes, {"structures": true, "dimension": "overworld"})
		_mt_gens.append(g)
		var ch := {}
		for z in range(-1, 5):
			for x in range(-1, 2):
				var c := Chunk.new(x + i * 37, z - i * 23)
				g.generate(c)
				c.state = Chunk.DATA_READY
				ch[Vector2i(x, z)] = c
		_mt_strips.append(ch)
		_mt_times.append(0)
	for i in k:
		_mt_job(i)
	var seq := 0
	for i in k:
		seq += _mt_times[i]
	# warm-up done (structure starts / templates cached); repeat sequentially, then in parallel
	for i in k:
		_mt_times[i] = 0
		_mt_job(i)
	seq = 0
	for i in k:
		seq += _mt_times[i]
	var threads: Array = []
	var tw := Time.get_ticks_usec()
	for i in k:
		_mt_times[i] = 0
		var th := Thread.new()
		th.start(_mt_job.bind(i))
		threads.append(th)
	for th in threads:
		th.wait_to_finish()
	var wall := Time.get_ticks_usec() - tw
	var par := 0
	for i in k:
		par += _mt_times[i]
	print("BENCH mt=%d features: sequential avg %.1f ms/job, parallel avg %.1f ms/job (slowdown x%.2f), parallel wall %.0f ms vs sequential %.0f ms" % [k, seq / 1000.0 / (4 * k), par / 1000.0 / (4 * k), float(par) / maxf(1.0, float(seq)), wall / 1000.0, seq / 1000.0])
	var gseq := 0
	for i in k:
		var tg := Time.get_ticks_usec()
		for z in 4:
			_mt_gens[i].generate(Chunk.new(1000 + z, i * 50))
		gseq += Time.get_ticks_usec() - tg
	_mt_gen_us.resize(k)
	threads.clear()
	tw = Time.get_ticks_usec()
	for i in k:
		var th2 := Thread.new()
		th2.start(_mt_gen_job.bind(i))
		threads.append(th2)
	for th2 in threads:
		th2.wait_to_finish()
	var gpar := 0
	for i in k:
		gpar += _mt_gen_us[i]
	print("BENCH mt=%d generate: sequential avg %.1f ms/chunk, parallel avg %.1f ms/chunk (slowdown x%.2f)" % [k, gseq / 1000.0 / (4 * k), gpar / 1000.0 / (4 * k), float(gpar) / maxf(1.0, float(gseq))])


var _mt_gen_us: Array = []


func _mt_gen_job(i: int) -> void:
	var t := Time.get_ticks_usec()
	for z in 4:
		_mt_gens[i].generate(Chunk.new(2000 + z, i * 50))
	_mt_gen_us[i] = Time.get_ticks_usec() - t


func _mt_job(i: int) -> void:
	var g = _mt_gens[i]
	var ch: Dictionary = _mt_strips[i]
	var t := Time.get_ticks_usec()
	for z in 4:
		var nine: Array = []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				nine.append(ch.get(Vector2i(dx, z + dz)))
		var c: Chunk = ch[Vector2i(0, z)]
		g.compute_features(c, ChunkRegion.new(c.cx, c.cz, nine))
	_mt_times[i] = Time.get_ticks_usec() - t


## Dev: compact description of a compiled placed feature (modifier types + configured feature types, recursive).
func _ftree(fe: Features, pf: Dictionary, depth: int) -> String:
	if pf.is_empty() or depth > 6:
		return "{}"
	var mods: Array = []
	for m in pf.get("mods", []):
		var raw: Dictionary = m.get("raw", {})
		var extra := ""
		if str(m["t"]) in ["count", "random_offset", "height_range", "environment_scan", "heightmap", "rarity_filter", "block_predicate_filter"]:
			extra = JSON.stringify(raw).replace("minecraft:", "").left(160)
		mods.append(str(m["t"]) + extra)
	return "[%s] -> %s" % [", ".join(mods), _fcf(fe, pf.get("cf", {}), depth)]


func _fcf(fe: Features, cf: Dictionary, depth: int) -> String:
	var t := str(cf.get("t", "?"))
	var subs: Array = []
	for k in cf:
		var v = cf[k]
		if v is Dictionary and v.has("cf"):
			subs.append("%s=%s" % [k, _ftree(fe, v, depth + 1)])
		elif v is Array:
			for e in v:
				if e is Array and e.size() >= 2 and e[1] is Dictionary and e[1].has("cf"):
					subs.append("%s:%s" % [k, _ftree(fe, e[1], depth + 1)])
				elif e is Dictionary and e.has("cf"):
					subs.append("%s:%s" % [k, _ftree(fe, e, depth + 1)])
	var keys := ", ".join(cf.keys().filter(func(x): return not (cf[x] is Dictionary and cf[x].has("cf"))))
	return "%s{%s}%s" % [t, keys, (" " + " ; ".join(subs)) if not subs.is_empty() else ""]


func _region(chunks: Dictionary, cx: int, cz: int) -> ChunkRegion:
	var nine: Array = []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			nine.append(chunks.get(Vector2i(cx + dx, cz + dz)))
	return ChunkRegion.new(cx + _ox, cz + _oz, nine)


func _avg(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / a.size()
