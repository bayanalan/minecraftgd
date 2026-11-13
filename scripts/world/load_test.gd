## LoadTest — end-to-end chunk visibility benchmark of the real game loop (autoplay --loadtest).
## Fresh world, render distance 16 / simulation distance 12 (in-memory overrides, the user's settings file is not
## touched), then:
##   A. world entry: time until the player's chunk and Chebyshev rings 1/2/4/8/12/16 are fully visible
##   B. walk: constant 5.6 b/s through unexplored terrain (spectator, no collision stalls)
##   C. fly: constant 22 b/s
##   D. teleport 30000 blocks away: time until rings 0/1/2/4/8 are visible
## "Visible" = ChunkManager trace 'vis': lit + every mesh group built and uploaded. During B/C every chunk that enters
## ring <= 4 records its wait until visible. Writes user://perf/<stamp>/{summary.json, traces.csv, timeline.csv,
## *.png} and prints a one-line summary per phase.
class_name LoadTest
extends RefCounted

const RINGS := [0, 1, 2, 4, 8, 12, 16]


static func _pc(w) -> Vector2i:
	return Vector2i(int(floor(w.player.pos.x)) >> 4, int(floor(w.player.pos.z)) >> 4)


## Fraction of chunks within Chebyshev ring r that are visible.
static func _ring_visible(w, pc: Vector2i, r: int) -> int:
	var n := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c: Chunk = w.cm.get_chunk(pc.x + dx, pc.y + dz)
			if c != null and c.shown:
				n += 1
	return n


static func _shot(w, dir: String, name: String) -> void:
	var img: Image = w.get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(dir.path_join(name + ".png"))


## --nativecheck: native vs GDScript output equality + timing on real chunks (lighting, then other ported stages).
static func native_check(w) -> void:
	var tree: SceneTree = w.get_tree()
	var cm: ChunkManager = w.cm
	var t0 := Time.get_ticks_msec()
	while (not w.spawn_ready or cm.stats["lit"] < 9) and Time.get_ticks_msec() - t0 < 120000:
		await tree.process_frame
	print("[nativecheck] native ok=%s arch=%s" % [Native.ok, Native.arch])
	var n := 0
	var bad := 0
	var tg := 0
	var tn := 0
	for c in cm.chunks.values():
		if n >= 12 or c.state < Chunk.DECORATED:
			continue
		var snaps: Array = []
		var hms: Array = []
		var full := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nb: Chunk = cm.get_chunk(c.cx + dx, c.cz + dz)
				if nb == null or nb.state < Chunk.DATA_READY:
					full = false
				snaps.append(nb.snapshot() if nb != null else null)
				hms.append(nb.heightmap.duplicate() if nb != null else null)
		if not full:
			continue
		n += 1
		var a := Time.get_ticks_usec()
		var g: Array = Lighting.compute_gd(snaps, hms, Res.blocks)
		var b := Time.get_ticks_usec()
		var nv: Array = Native.inst.light(snaps, hms, Res.blocks.st_opacity, Res.blocks.st_emit) if Native.ok else []
		var e := Time.get_ticks_usec()
		tg += b - a
		tn += e - b
		for s in 24:
			if nv.size() != 24 or typeof(g[s]) != typeof(nv[s]) or g[s] != nv[s]:
				bad += 1
				print("[nativecheck] light mismatch chunk %d,%d section %d" % [c.cx, c.cz, s])
				break
	print("[nativecheck] light: %d chunks, %d mismatching, gdscript %.1f ms/chunk, native %.2f ms/chunk" % [n, bad, tg / 1000.0 / maxi(1, n), tn / 1000.0 / maxi(1, n)])
	# mesher: every group of every checked chunk, all arrays compared exactly
	var mn := 0
	var mbad := 0
	var mg := 0
	var mnat := 0
	for c in cm.chunks.values():
		if mn >= 8 or not c.light_valid:
			continue
		var snaps2: Array = []
		var full2 := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var nb2: Chunk = cm.get_chunk(c.cx + dx, c.cz + dz)
				if nb2 == null or nb2.state < Chunk.DATA_READY:
					full2 = false
				snaps2.append(nb2.snapshot() if nb2 != null else null)
		if not full2:
			continue
		mn += 1
		for g in Coords.SECTIONS / Mesher.GROUP:
			var job := {"snaps": snaps2, "light": c.light_halo_secs, "group": g, "blocks": Res.blocks, "tints": cm._tints(c)}
			var a2 := Time.get_ticks_usec()
			var gd: Dictionary = Mesher.build_gd(job)
			var b2 := Time.get_ticks_usec()
			var nat: Dictionary = Mesher.build(job) if Native.ok else {}
			mg += b2 - a2
			mnat += Time.get_ticks_usec() - b2
			if gd.is_empty() != nat.is_empty():
				mbad += 1
				print("[nativecheck] mesh empty mismatch %d,%d g%d" % [c.cx, c.cz, g])
				continue
			if gd.is_empty():
				continue
			for sk in ["opaque", "cutout", "translucent"]:
				var ga: Array = gd[sk]
				var na: Array = nat[sk]
				if ga.size() != na.size():
					mbad += 1
					print("[nativecheck] mesh %s size mismatch %d,%d g%d: %d vs %d" % [sk, c.cx, c.cz, g, ga.size(), na.size()])
					continue
				if ga.is_empty():
					continue
				for ai in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_INDEX]:
					if ga[ai] != na[ai]:
						mbad += 1
						var gsz: int = ga[ai].size()
						var nsz: int = na[ai].size()
						var first := -1
						for q in mini(gsz, nsz):
							if ga[ai][q] != na[ai][q]:
								first = q
								break
						print("[nativecheck] mesh %s array %d mismatch %d,%d g%d: sizes %d/%d first diff @%d %s vs %s" % [sk, ai, c.cx, c.cz, g, gsz, nsz, first, str(ga[ai][first]) if first >= 0 else "", str(na[ai][first]) if first >= 0 else ""])
						break
	print("[nativecheck] mesh: %d chunks, %d mismatching arrays, gdscript %.1f ms/chunk, native %.2f ms/chunk" % [mn, mbad, mg / 1000.0 / maxi(1, mn), mnat / 1000.0 / maxi(1, mn)])
	# biome tints: GDScript blend vs native
	var tb_bad := 0
	var tb_n := 0
	for tc in w.cm.chunks.values():
		if tc.state < Chunk.DECORATED or tb_n >= 40:
			continue
		tb_n += 1
		if w.cm._tints_gd(tc) != w.cm._tints_compute(tc):
			tb_bad += 1
	print("[nativecheck] tints: %d chunks, %d differing" % [tb_n, tb_bad])
	# density: per-block sign agreement + numeric difference, then full generate() with native density on/off
	var vg = w.gen
	if vg is VanillaGenerator and vg.native_graph >= 0:
		var pc := _pc(w)
		var sign_bad := 0
		var maxdiff := 0.0
		var dg := 0
		var dn := 0
		var block_bad := 0
		var nchk := int(w.autoplay.get("dchunks", "6"))
		var spread := int(w.autoplay.get("dspread", "1"))
		var bset := {}
		for t in nchk:
			var cx: int = pc.x + 40 + t * 7 * spread
			var cz: int = pc.y - 25 + t * 11 * spread - (t % 3) * 97 * spread
			var dctx := DensityFunctions.Ctx.new(vg.dfc.node_count())
			dctx.x0 = cx * 16
			dctx.z0 = cz * 16
			dctx.has_chunk = true
			var bp := dctx.chunk_blocks()
			var ceiling: int = vg._aquifer_ceiling(dctx, Chunk.new(cx, cz))
			var ta := Time.get_ticks_usec()
			var gdd: PackedFloat64Array = vg._cell_density(dctx, bp, ceiling)
			var tb := Time.get_ticks_usec()
			var nd: PackedFloat64Array = Native.inst.df_chunk(vg.native_graph, vg.final_density.id, cx, cz, vg.gen_min_y, vg.gen_min_y + vg.gen_depth)[0]
			dn += Time.get_ticks_usec() - tb
			dg += tb - ta
			for i in 98304:
				if (gdd[i] > 0.0) != (nd[i] > 0.0):
					sign_bad += 1
				if absf(gdd[i]) != 1.0:
					maxdiff = maxf(maxdiff, absf(gdd[i] - nd[i]))
			var c1 := Chunk.new(cx, cz)
			var c2 := Chunk.new(cx, cz)
			Native.density_ok = false
			vg.generate(c1)
			Native.density_ok = true
			vg.generate(c2)
			for bb in c2.biomes:
				bset[int(bb)] = true
			if c1.heightmap != c2.heightmap or c1.gen_surface != c2.gen_surface or c1.gen_top != c2.gen_top or c1.gen_floor != c2.gen_floor:
				print("[nativecheck] heightmap / pristine surface arrays differ in chunk %d,%d" % [cx, cz])
			if c1.biomes != c2.biomes:
				print("[nativecheck] biome arrays differ in chunk %d,%d" % [cx, cz])
			for y in range(Coords.MIN_Y, Coords.MAX_Y):
				for z in 16:
					for x in 16:
						if c1.get_block(x, y, z) != c2.get_block(x, y, z):
							block_bad += 1
		print("[nativecheck] density: %d chunks, sign mismatches %d, max |diff| %s, gdscript %.1f ms/chunk, native %.2f ms/chunk; generated blocks differing %d, biomes covered %d" % [nchk, sign_bad, str(maxdiff), dg / 1000.0 / nchk, dn / 1000.0 / nchk, block_bad, bset.size()])
		# jigsaw assembly: original dictionary-copy path vs index shuffle (pieces must be identical)
		var stc0 = vg.structures
		if stc0 != null and int(w.autoplay.get("jigs", "0")) > 0:
			var want := int(w.autoplay.get("jigs", "0"))
			var jn := 0
			var jbad := 0
			var t_old := 0
			var t_new := 0
			for probe in [Vector2i(1880, 1870), Vector2i(0, 0), Vector2i(-14, 4), Vector2i(400, -300), Vector2i(-500, 900), Vector2i(5630, 1870), Vector2i(-2000, -2000), Vector2i(3000, 100)]:
				if jn >= want:
					break
				for st in stc0.sets:
					if jn >= want:
						break
					for sc in stc0._candidates(st, probe.x, probe.y):
						var ta3 := Time.get_ticks_usec()
						Structures.old_jig = true
						var r_old: Dictionary = stc0._make_start(st, sc)
						var tb3 := Time.get_ticks_usec()
						Structures.old_jig = false
						for sk in ["cands", "fits", "jigsaws_tried", "pool_shuffle_ms", "eljig_ms", "elinfo_ms", "elinfo_miss", "ffh_ms", "ffh_calls"]: stc0.stats[sk] = 0
						var r_new: Dictionary = stc0._make_start(st, sc)
						if r_new.get("structure", "") == "trial_chambers": print("[nativecheck]   stats ", JSON.stringify(stc0.stats))
						var tc3 := Time.get_ticks_usec()
						if not r_old.has("pieces") or (r_old["pieces"] as Array).size() < 2:
							continue
						t_old += tb3 - ta3
						t_new += tc3 - tb3
						jn += 1
						var s_old := ""
						var s_new := ""
						for pz in r_old["pieces"]:
							s_old += "%s|%s|%d|%s;" % [str(pz["el"].get("loc", pz["el"]["t"])), str(pz["pos"]), int(pz["rot"]), str(pz["box"])]
						for pz in r_new.get("pieces", []):
							s_new += "%s|%s|%d|%s;" % [str(pz["el"].get("loc", pz["el"]["t"])), str(pz["pos"]), int(pz["rot"]), str(pz["box"])]
						if s_old != s_new:
							jbad += 1
							print("[nativecheck]   jigsaw differs: %s at %s (%d vs %d pieces)" % [str(r_old.get("structure", "")), str(sc), (r_old["pieces"] as Array).size(), (r_new.get("pieces", []) as Array).size()])
						else:
							print("[nativecheck]   jigsaw %s at %s: %d pieces identical, %.0f ms -> %.0f ms" % [str(r_old.get("structure", "")), str(sc), (r_old["pieces"] as Array).size(), (tb3 - ta3) / 1000.0, (tc3 - tb3) / 1000.0])
						if jn >= want:
							break
			print("[nativecheck] jigsaw: %d starts, %d differing, old %.0f ms, new %.0f ms total" % [jn, jbad, t_old / 1000.0, t_new / 1000.0])
		# structure first-free-height columns: native density vs GDScript batch
		var ffh_bad := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = 99
		var stc = vg.structures
		if stc != null:
			for t in 40:
				var fx := rng.randi_range(-4000, 4000)
				var fz := rng.randi_range(-4000, 4000)
				Native.density_ok = false
				stc._heights.clear()
				var h1: int = stc.first_free_height(fx, fz, t % 2 == 0)
				Native.density_ok = true
				stc._heights.clear()
				var h2: int = stc.first_free_height(fx, fz, t % 2 == 0)
				if h1 != h2:
					ffh_bad += 1
			print("[nativecheck] first_free_height: 40 columns, %d differing" % ffh_bad)
		# features: original overlay/region access vs job-private flat region (write lists must be identical)
		var fbad := 0
		var fl_t := 0
		var ff_t := 0
		var nwr := 0
		var fn := int(w.autoplay.get("fchunks", "4"))
		if w.autoplay.has("fonly"):
			# isolate: stop dispatching world jobs and wait for in-flight ones
			w.cm.adaptive_jobs = false
			w.cm.max_jobs = 0
			w.cm.queue_depth = 0   # no new queued jobs either (nothing would run them)
			var tw := Time.get_ticks_msec()
			while w.cm._inflight > 0 and Time.get_ticks_msec() - tw < 600000:
				await w.get_tree().process_frame
			printerr("[nativecheck] world workers idle after %d ms" % (Time.get_ticks_msec() - tw))
		for t in fn:
			var ox: int = pc.x - 60 + t * 13 * spread
			var oz: int = pc.y + 33 - t * 5 * spread - (t % 2) * 71 * spread
			if w.autoplay.has("fonly"):
				var fo: PackedStringArray = str(w.autoplay["fonly"]).split(",")
				ox = int(fo[0])
				oz = int(fo[1])
				vg.features.profiling = true
				vg.features.trace_names = true
				vg.features.profile.clear()
			var nine: Array = []
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var gc := Chunk.new(ox + dx, oz + dz)
					vg.generate(gc)
					nine.append(gc)
			var origin: Chunk = nine[4]
			printerr("[nativecheck] features origin %d,%d generated" % [ox, oz])
			if w.autoplay.has("fonly"):
				var tf := Time.get_ticks_usec()
				vg.features.legacy_region = false
				var wf: PackedInt32Array = vg.compute_features(origin, ChunkRegion.new(ox, oz, nine))
				printerr("[nativecheck]   flat-only %.0f ms, %d writes" % [(Time.get_ticks_usec() - tf) / 1000.0, wf.size() / 5])
				var pk: Array = vg.features.profile.keys()
				pk.sort_custom(func(a, b): return vg.features.profile[a] > vg.features.profile[b])
				for k in pk.slice(0, 8):
					printerr("[nativecheck]     %s %.1f ms" % [k, vg.features.profile[k] / 1000.0])
			vg.features.legacy_region = true
			Structures.old_scan = true
			Native.features_ok = false
			var ta2 := Time.get_ticks_usec()
			var w1: PackedInt32Array = vg.compute_features(origin, ChunkRegion.new(ox, oz, nine))
			var b1: Array = vg.features.bounds.duplicate()
			var be1 := str(origin.feature_bes)
			var tb2 := Time.get_ticks_usec()
			printerr("[nativecheck]   legacy %.0f ms" % ((tb2 - ta2) / 1000.0))
			vg.features.legacy_region = false
			Structures.old_scan = false
			Native.features_ok = true
			var w2: PackedInt32Array = vg.compute_features(origin, ChunkRegion.new(ox, oz, nine))
			ff_t += Time.get_ticks_usec() - tb2
			fl_t += tb2 - ta2
			nwr += w2.size() / 5
			if str(origin.feature_bes) != be1:
				fbad += 1
				print("[nativecheck]   block entities differ at %d,%d" % [ox, oz])
			if w1 != w2:
				fbad += 1
				var b2: Array = vg.features.bounds
				for bi in mini(b1.size(), b2.size()):
					var e1: int = b1[bi + 1][1] if bi + 1 < b1.size() else w1.size()
					var e2: int = b2[bi + 1][1] if bi + 1 < b2.size() else w2.size()
					if b1[bi][1] != b2[bi][1] or e1 != e2 or w1.slice(b1[bi][1], e1) != w2.slice(b2[bi][1], e2):
						print("[nativecheck]   first differing feature at %d,%d: %s (legacy %d writes from %d, new %d writes from %d)" % [ox, oz, b1[bi][0], (e1 - b1[bi][1]) / 5, b1[bi][1] / 5, (e2 - b2[bi][1]) / 5, b2[bi][1] / 5])
						var fi := 0
						while fi < mini(w1.size(), w2.size()) and w1[fi] == w2[fi]:
							fi += 1
						fi -= fi % 5
						print("[nativecheck]   first differing write #%d: legacy %s / new %s" % [fi / 5, str(w1.slice(fi, fi + 5)), str(w2.slice(fi, fi + 5))])
						break
				print("[nativecheck] feature writes differ at %d,%d: %d vs %d" % [ox, oz, w1.size(), w2.size()])
		# decorate: GDScript apply + freeze vs native chunk_decorate on identical centre chunks
		var dn2 := int(w.autoplay.get("decchunks", "2"))
		var dbad := 0
		var td_g := 0
		var td_n := 0
		for t in dn2:
			var ox2: int = pc.x + 90 + t * 31 * spread
			var oz2: int = pc.y - 70 + t * 17 * spread
			var grid := {}
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var gc2 := Chunk.new(ox2 + dx, oz2 + dz)
					vg.generate(gc2)
					grid[Vector2i(dx, dz)] = gc2
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nine2: Array = []
					for ez in range(-1, 2):
						for ex in range(-1, 2):
							nine2.append(grid[Vector2i(dx + ex, dz + ez)])
					var oc: Chunk = grid[Vector2i(dx, dz)]
					var tfx := Time.get_ticks_msec()
					oc.feature_writes = vg.compute_features(oc, ChunkRegion.new(ox2 + dx, oz2 + dz, nine2))
					printerr("[nativecheck]   decorate prep features %d,%d: %d ms" % [ox2 + dx, oz2 + dz, Time.get_ticks_msec() - tfx])
			var ca := Chunk.new(ox2, oz2)
			vg.generate(ca)
			var cb := Chunk.new(ox2, oz2)
			vg.generate(cb)
			var center0: Chunk = grid[Vector2i(0, 0)]
			for cc in [ca, cb]:
				cc.feature_writes = center0.feature_writes
				cc.feature_bes = center0.feature_bes
			var nine_a: Array = []
			var nine_b: Array = []
			for ez in range(-1, 2):
				for ex in range(-1, 2):
					nine_a.append(ca if ex == 0 and ez == 0 else grid[Vector2i(ex, ez)])
					nine_b.append(cb if ex == 0 and ez == 0 else grid[Vector2i(ex, ez)])
			Native.chunkops_ok = false
			var tq := Time.get_ticks_usec()
			vg.decorate(ca, ChunkRegion.new(ox2, oz2, nine_a))
			var tq2 := Time.get_ticks_usec()
			Native.chunkops_ok = true
			vg.decorate(cb, ChunkRegion.new(ox2, oz2, nine_b))
			td_g += tq2 - tq
			td_n += Time.get_ticks_usec() - tq2
			var nd2 := 0
			for y in range(Coords.MIN_Y, Coords.MAX_Y):
				for z in 16:
					for x in 16:
						if ca.get_block(x, y, z) != cb.get_block(x, y, z):
							nd2 += 1
			if nd2 > 0 or ca.heightmap != cb.heightmap:
				dbad += 1
				print("[nativecheck]   decorate differs at %d,%d: %d blocks, heightmap equal %s" % [ox2, oz2, nd2, str(ca.heightmap == cb.heightmap)])
		print("[nativecheck] decorate: %d centres, %d differing, gdscript %.1f ms, native %.1f ms per centre" % [dn2, dbad, td_g / 1000.0 / maxi(1, dn2), td_n / 1000.0 / maxi(1, dn2)])
		var fnat := FeaturesNative.shared(vg.features)
		print("[nativecheck] native feature engine: %d of %d placed features exported" % [int(fnat.get("count", 0)), int(fnat.get("of", 0))])
		var wh: Dictionary = fnat.get("why", {})
		var wl: Array = []
		for wk in wh:
			wl.append([int(wh[wk][0]), wk, wh[wk][1]])
		wl.sort()
		wl.reverse()
		for e in wl:
			print("[nativecheck]   not native: %3d x %s (e.g. %s)" % [e[0], e[1], e[2]])
		print("[nativecheck] features: %d origins, %d differing write lists (%d writes), legacy %.1f ms, flat %.1f ms per origin" % [fn, fbad, nwr, fl_t / 1000.0 / fn, ff_t / 1000.0 / fn])
	# leaf decay search: native leaf_search vs GDScript BFS on leaves in loaded, decorated chunks
	if Native.chunkops_ok and Native.inst.has_method("leaf_search"):
		var lb := Res.blocks
		var ln := 0
		var lbad := 0
		var lfound := 0
		var lfn := 0
		var lfbad := 0
		RandomTickable._log_nearby(w, Vector3i(0, 0, 0), 6)   # builds the class table
		for ck in w.cm.chunks.values():
			var lc: Chunk = ck
			if lc.state < Chunk.DECORATED or ln >= 600:
				continue
			for s in range(8, 16):
				var sec: Chunk.Section = lc.sections[s]
				for li in range(0, 4096, 7):
					var lst := sec.get_at(li)
					if lst > 0 and lb.name_of(lst).ends_with("_leaves"):
						var lp := Vector3i(lc.cx * 16 + (li & 15), -64 + s * 16 + (li >> 8), lc.cz * 16 + ((li >> 4) & 15))
						var a1 := RandomTickable._log_nearby(w, lp, 6)
						var a2 := RandomTickable._log_nearby_gd(w, lp, 6)
						ln += 1
						lfound += 1 if a2 else 0
						if a1 != a2:
							lbad += 1
						if Native.inst.has_method("rt_leaf_filter"):
							# batch random-tick filter on the same leaf: kept exactly when no log is in reach
							var g9: Array = []
							for gz in 3:
								for gx in 3:
									var gc: Chunk = w.cm.chunks.get(Coords.chunk_key(lc.cx - 1 + gx, lc.cz - 1 + gz))
									g9.append(gc.sec_refs() if gc != null and gc.state >= Chunk.DATA_READY else null)
							var kept: PackedInt32Array = Native.inst.rt_leaf_filter(PackedInt32Array([0, s, li, lst]), PackedInt32Array([lc.cx, lc.cz]), g9, lc.cx - 1, lc.cz - 1, 3, RandomTickable.ltab(), 6)[0]
							lfn += 1
							if (kept.size() == 4) == a2:
								lfbad += 1
		print("[nativecheck] leaf_search: %d leaves, %d differing (%d with a log in reach)" % [ln, lbad, lfound])
		print("[nativecheck] rt_leaf_filter: %d leaves, %d differing from the GDScript leaf search" % [lfn, lfbad])
	w.cm.shutdown()
	w.get_tree().quit()


static func run(w) -> void:
	var cm: ChunkManager = w.cm
	cm.tracing = true
	BlockUpdates.prof = true
	if w.autoplay.has("workers"):
		cm.max_jobs = int(w.autoplay["workers"])
		cm.adaptive_jobs = false
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir := "user://perf/" + stamp
	DirAccess.make_dir_recursive_absolute(dir)
	var summary := {"stamp": stamp, "render_distance": int(Settings.get_v("render_distance")), "simulation_distance": int(Settings.get_v("simulation_distance")),
		"workers": cm.max_jobs, "cpu_threads": OS.get_processor_count(), "generator": w.gen.generator_id, "seed": w.gen.seed, "native": ClassDB.class_exists("RecraftNative")}
	var timeline: Array = []
	var t0: int = w.created_us
	var tree: SceneTree = w.get_tree()
	# ---------------- A: world entry
	var ms := {}
	var max_frame := 0.0
	var frame_ms: Array = []
	var last := Time.get_ticks_usec()
	var last_sample := 0
	var quick: int = int(w.autoplay.get("ltquick", "0"))
	var deadline := Time.get_ticks_usec() + (quick if quick > 0 else 240) * 1000000
	while Time.get_ticks_usec() < deadline:
		await tree.process_frame
		var now := Time.get_ticks_usec()
		max_frame = maxf(max_frame, (now - last) / 1000.0)
		if w.spawn_ready:
			frame_ms.append((now - last) / 1000.0)
		last = now
		if w.spawn_ready and not ms.has("spawn_ready"):
			ms["spawn_ready"] = (now - t0) / 1000.0
			_shot(w, dir, "A_spawn")
		if not w.spawn_ready:
			continue
		if now - last_sample < 250000:
			continue
		last_sample = now
		var pc := _pc(w)
		var row := [(now - t0) / 1000.0, cm.chunks.size(), cm.pending_jobs()]
		for r in RINGS:
			var v := _ring_visible(w, pc, r)
			row.append(v)
			if v == (2 * r + 1) * (2 * r + 1) and not ms.has("ring%d" % r):
				ms["ring%d" % r] = (now - t0) / 1000.0
				print("[loadtest] ring %d visible at %.1f s" % [r, (now - t0) / 1e6])
				if r == 4:
					_shot(w, dir, "A_ring4")
		timeline.append(row)
		if ms.has("ring16"):
			break
	summary["A_entry_ms"] = ms
	var a_secs := (Time.get_ticks_usec() - t0) / 1e6
	summary["A_seconds"] = a_secs
	summary["A_gen_per_s"] = snappedf(cm.stats["generated"] / a_secs, 0.01)
	summary["A_visible_chunks"] = _ring_visible(w, _pc(w), 16)
	summary["A_max_frame_ms"] = max_frame
	frame_ms.sort()
	if not frame_ms.is_empty():
		var fsum := 0.0
		for fm in frame_ms:
			fsum += fm
		summary["A_frames"] = {"n": frame_ms.size(), "avg_ms": snappedf(fsum / frame_ms.size(), 0.1), "p50": frame_ms[frame_ms.size() / 2], "p95": frame_ms[int(frame_ms.size() * 0.95)]}
	var busy := {}
	var btot := 0
	for bk in cm.busy_us:
		busy[bk] = {"n": cm.busy_n[bk], "total_s": snappedf(cm.busy_us[bk] / 1e6, 0.01), "avg_ms": snappedf(cm.busy_us[bk] / 1000.0 / maxi(1, cm.busy_n[bk]), 0.1)}
		btot += int(cm.busy_us[bk])
	summary["A_busy"] = busy
	var mt := {}
	for mk in cm.main_us:
		mt[mk] = snappedf(cm.main_us[mk] / 1000.0 / maxi(1, frame_ms.size()), 0.01)
	for pk in w.prof_us:
		mt[pk] = snappedf(w.prof_us[pk] / 1000.0 / maxi(1, frame_ms.size()), 0.01)
	summary["A_main_ms_per_frame"] = mt
	var rtp := {}
	for rk in BlockUpdates.prof_us:
		rtp[rk] = [snappedf(BlockUpdates.prof_us[rk] / 1000.0 / maxi(1, frame_ms.size()), 0.01), int(BlockUpdates.prof_n.get(rk, 0))]
	summary["A_random_tick_ms_per_frame"] = rtp
	var fprof := {}
	cm._tl_mutex.lock()
	for tg in cm._tl_gens.values():
		if tg is VanillaGenerator and tg.features != null:
			for fk in tg.features.profile:
				fprof[fk] = int(fprof.get(fk, 0)) + int(tg.features.profile[fk])
	cm._tl_mutex.unlock()
	var fl: Array = []
	for fk in fprof:
		fl.append([snappedf(fprof[fk] / 1e6, 0.01), fk])
	fl.sort()
	fl.reverse()
	summary["A_feature_seconds_top"] = fl.slice(0, 300)
	var gsum := {}
	cm._tl_mutex.lock()
	for tg in cm._tl_gens.values():
		if tg is VanillaGenerator:
			for sk in ["n", "sum_total_us", "sum_begin_us", "sum_pre_us", "sum_finish_us", "sum_mid_us"]:
				gsum[sk] = int(gsum.get(sk, 0)) + int(tg.stats.get(sk, 0))
	cm._tl_mutex.unlock()
	var gn := maxi(1, int(gsum.get("n", 0)))
	summary["A_generate_parts_ms"] = {"n": gn, "total": gsum.get("sum_total_us", 0) / 1000.0 / gn, "pre": gsum.get("sum_pre_us", 0) / 1000.0 / gn, "tg_begin": gsum.get("sum_begin_us", 0) / 1000.0 / gn, "surface+carve+mid": gsum.get("sum_mid_us", 0) / 1000.0 / gn, "finish": gsum.get("sum_finish_us", 0) / 1000.0 / gn, "load_fn_per_job": cm._gen_load_us / 1000.0 / maxi(1, int(cm.busy_n.get("gen", 1)))}
	summary["A_worker_utilization_pct"] = snappedf(100.0 * btot / 1e6 / (a_secs * cm.max_jobs), 0.1)
	_shot(w, dir, "A_end")
	# ---------------- B / C: constant-speed travel through new terrain (spectator: no collision stalls)
	for phase_skip in [0]:
		if quick > 0:
			break
	w._auto_input = true
	w.player.mode = Player.Mode.SPECTATOR
	w.player.flying = true
	var phases: Array = [] if quick > 0 else [["B_walk", 5.6, Vector3(1, 0, 0), 40.0], ["C_fly", 22.0, Vector3(0, 0, -1), 30.0]]
	for phase in phases:
		var speed: float = phase[1]
		var dirv: Vector3 = phase[2]
		var dur: float = phase[3]
		var entered := {}   # key -> usec when the chunk first came within ring 4
		var waits: Array = []
		var missing_max := {2: 0, 4: 0}
		var miss_samples := {2: 0, 4: 0}
		var samples := 0
		var mf := 0.0
		var ps := Time.get_ticks_usec()
		var lt := ps
		var y_fixed: float = w.player.pos.y + 20.0
		while Time.get_ticks_usec() - ps < dur * 1e6:
			await tree.process_frame
			var now2 := Time.get_ticks_usec()
			var dt := (now2 - lt) / 1e6
			mf = maxf(mf, dt * 1000.0)
			if dt > 0.08:
				print("[stall] frame %.0f ms in %s (process %.1f ms)" % [dt * 1000.0, phase[0], Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
			lt = now2
			w.player.pos += dirv * speed * dt
			w.player.pos.y = y_fixed
			w.player.yaw = rad_to_deg(atan2(-dirv.x, dirv.z))
			w.player.pitch = 25.0
			var pc2 := _pc(w)
			for dz in range(-4, 5):
				for dx in range(-4, 5):
					var key := Coords.chunk_key(pc2.x + dx, pc2.y + dz)
					var c: Chunk = cm.chunks.get(key)
					if not entered.has(key):
						entered[key] = now2
					if c != null and c.trace.has("vis") and entered[key] >= 0:
						waits.append(maxf(0.0, (c.trace["vis"] - entered[key]) / 1000.0))
						entered[key] = -1
			if now2 - last_sample >= 250000:
				last_sample = now2
				samples += 1
				for r2 in [2, 4]:
					var miss: int = (2 * r2 + 1) * (2 * r2 + 1) - _ring_visible(w, pc2, r2)
					missing_max[r2] = maxi(missing_max[r2], miss)
					if miss > 0:
						miss_samples[r2] += 1
				timeline.append([(now2 - t0) / 1000.0, cm.chunks.size(), cm.pending_jobs(), phase[0], (2 * 4 + 1) * (2 * 4 + 1) - _ring_visible(w, pc2, 4)])
			if now2 - ps > dur * 0.5e6 and not summary.has(phase[0] + "_shot"):
				summary[phase[0] + "_shot"] = true
				_shot(w, dir, phase[0])
		var still := 0
		for k in entered:
			if int(entered[k]) >= 0:
				still += 1
		waits.sort()
		summary[phase[0]] = {"speed": speed, "seconds": dur, "chunks_entered_ring4": entered.size(), "became_visible": waits.size(),
			"still_missing_at_end": still,
			"wait_ms_median": waits[waits.size() / 2] if not waits.is_empty() else -1.0,
			"wait_ms_p90": waits[int(waits.size() * 0.9)] if not waits.is_empty() else -1.0,
			"wait_ms_max": waits[waits.size() - 1] if not waits.is_empty() else -1.0,
			"ring2_missing_max": missing_max[2], "ring4_missing_max": missing_max[4],
			"ring2_samples_incomplete_pct": 100.0 * miss_samples[2] / maxi(1, samples), "ring4_samples_incomplete_pct": 100.0 * miss_samples[4] / maxi(1, samples),
			"max_frame_ms": mf}
		print("[loadtest] %s %s" % [phase[0], JSON.stringify(summary[phase[0]])])
	# ---------------- D: teleport into unexplored terrain
	if w.autoplay.has("ltd"):
		w._auto_input = true
		w.player.mode = Player.Mode.SPECTATOR
		w.player.flying = true
	var tele := int(w.autoplay.get("ltd", "1"))
	w.player.pos += Vector3(30000 * tele, 0, 30000)
	w.player.prev_pos = w.player.pos
	var td := Time.get_ticks_usec()
	var dm := {}
	var mf2 := 0.0
	var lt2 := td
	var d_last_print := td
	var run_d: bool = quick == 0 or w.autoplay.has("ltd")
	while run_d and Time.get_ticks_usec() - td < 120 * 1000000:
		await tree.process_frame
		var now3 := Time.get_ticks_usec()
		mf2 = maxf(mf2, (now3 - lt2) / 1000.0)
		lt2 = now3
		var pc3 := _pc(w)
		if w.autoplay.has("ltd") and now3 - d_last_print >= 1000000:
			d_last_print = now3
			cm._q_mutex.lock()
			var qn: int = cm._q.size()
			var al: int = cm._alive
			cm._q_mutex.unlock()
			cm._mutex.lock()
			var rn: int = cm._results.size()
			cm._mutex.unlock()
			print("[loadtest]   fps %d, last dispatch %.1f ms commit %.1f ms process %.1f ms; submitted by kind: %s, light_update %d, light_dirty %d" % [Engine.get_frames_per_second(), cm.last_dispatch_us / 1000.0, cm.last_commit_us / 1000.0, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, JSON.stringify(cm.sub_kinds), cm._light_update.size(), cm._light_dirty.size()])
			cm.sub_kinds.clear()
			print("[loadtest] D t=%d s chunks %d inflight %d queue %d alive %d running %d submitted %d ran %d results %d committed %d jobs gen %d feat %d dec %d light %d mesh %d" % [(now3 - td) / 1000000, cm.chunks.size(), cm._inflight, qn, al, cm._running, cm._submitted, cm._ran, rn, cm._committed, cm._jobs_gen.size(), cm._jobs_feat.size(), cm._jobs_decor.size(), cm._jobs_light.size(), cm._jobs_mesh.size()])
		for r3 in [0, 1, 2, 4, 8]:
			if not dm.has("ring%d" % r3) and _ring_visible(w, pc3, r3) == (2 * r3 + 1) * (2 * r3 + 1):
				dm["ring%d" % r3] = (now3 - td) / 1000.0
				if r3 == 2:
					_shot(w, dir, "D_ring2")
		if dm.has("ring8"):
			break
	summary["D_teleport_ms"] = dm
	if run_d:
		var fp2 := {}
		cm._tl_mutex.lock()
		for tg2 in cm._tl_gens.values():
			if tg2 is VanillaGenerator and tg2.features != null:
				for fk in tg2.features.profile:
					fp2[fk] = int(fp2.get(fk, 0)) + int(tg2.features.profile[fk])
		cm._tl_mutex.unlock()
		var prev := {}
		for e0 in summary.get("A_feature_seconds_top", []):
			prev[e0[1]] = float(e0[0])
		var dl: Array = []
		for fk in fp2:
			dl.append([snappedf(fp2[fk] / 1e6 - float(prev.get(fk, 0.0)), 0.01), fk])
		dl.sort()
		dl.reverse()
		summary["D_feature_seconds_top"] = dl.slice(0, 15)
		print("[loadtest] D features: %s" % JSON.stringify(dl.slice(0, 15)))
		var rtl: Array = []
		for rk in BlockUpdates.prof_us:
			rtl.append([snappedf(BlockUpdates.prof_us[rk] / 1000.0, 0.1), rk, int(BlockUpdates.prof_n.get(rk, 0))])
		rtl.sort()
		rtl.reverse()
		print("[loadtest] random tick ms (whole run): %s" % JSON.stringify(rtl.slice(0, 10)))
	summary["D_max_frame_ms"] = mf2
	print("[loadtest] D_teleport %s" % JSON.stringify(dm))
	# ---------------- correctness: every visible chunk must be decorated + lit
	var bad := 0
	for c in cm.chunks.values():
		if c.trace.has("vis") and (c.state < Chunk.DECORATED or not c.light_valid):
			bad += 1
	summary["visible_but_incomplete"] = bad
	var bcl: Array = []
	for k in w.block_change_log:
		bcl.append([int(w.block_change_log[k]), k])
	bcl.sort()
	bcl.reverse()
	summary["block_changes_top"] = bcl.slice(0, 15)
	# ---------------- per-chunk traces + stage stats
	var all: Array = cm.trace_log.duplicate()
	for c in cm.chunks.values():
		var tc: Dictionary = c.trace.duplicate()
		tc["cx"] = c.cx
		tc["cz"] = c.cz
		all.append(tc)
	var keys := ["cx", "cz", "req", "gen_s", "gen_e", "gen_c", "feat_s", "feat_e", "feat_c", "dec_s", "dec_e", "dec_c", "light_s", "light_e", "light_c", "mesh_s", "mesh_e", "vis", "lights", "meshes", "upload_us"]
	var f := FileAccess.open(dir.path_join("traces.csv"), FileAccess.WRITE)
	f.store_line(",".join(keys))
	var sums := {}
	var cnts := {}
	for tr in all:
		var vals: Array = []
		for k in keys:
			var v = tr.get(k, "")
			vals.append(str(v - t0) if (v is int and k not in ["cx", "cz", "lights", "meshes", "upload_us"]) else str(v))
		f.store_line(",".join(vals))
		for pair in [["gen", "gen_s", "gen_e"], ["feat", "feat_s", "feat_e"], ["dec", "dec_s", "dec_e"], ["light", "light_s", "light_e"], ["mesh", "mesh_s", "mesh_e"],
				["gen_queue", "req", "gen_s"], ["gen_commit_lag", "gen_e", "gen_c"], ["req_to_vis", "req", "vis"]]:
			if tr.has(pair[1]) and tr.has(pair[2]):
				sums[pair[0]] = float(sums.get(pair[0], 0.0)) + (int(tr[pair[2]]) - int(tr[pair[1]])) / 1000.0
				cnts[pair[0]] = int(cnts.get(pair[0], 0)) + 1
	f.close()
	var avg := {}
	for k in sums:
		avg[k] = snappedf(sums[k] / maxi(1, cnts[k]), 0.1)
	summary["stage_avg_ms"] = avg
	summary["stage_counts"] = cnts
	var tl := FileAccess.open(dir.path_join("timeline.csv"), FileAccess.WRITE)
	for row in timeline:
		tl.store_line(",".join(row.map(func(x): return str(x))))
	tl.close()
	var sf := FileAccess.open(dir.path_join("summary.json"), FileAccess.WRITE)
	sf.store_string(JSON.stringify(summary, "  "))
	sf.close()
	print("[loadtest] SUMMARY %s" % JSON.stringify(summary))
	print("[loadtest] written to %s" % ProjectSettings.globalize_path(dir))
	w.cm.shutdown()
	w.get_tree().quit()
