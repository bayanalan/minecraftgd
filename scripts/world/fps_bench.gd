class_name FpsBench
extends RefCounted
## Frame-rate benchmarks, separate from the world-loading test (load_test.gd). Fresh world, render distance 16 /
## simulation 12, V-Sync and every FPS cap off (in memory only), borderless fullscreen at native resolution (or --res=WxH
## windowed), default graphics.
## --fpsbench=F (default): FLIGHT — once the world has loaded, the player (creative) sprint-flies forward continuously
##     through fresh terrain using the real movement code (forward + sprint held, jump to climb), high above the terrain
##     (at least y 120 and 32 blocks above the terrain ahead), looking just below the horizon (pitch 6 degrees), for
##     --fsecs (default 60) seconds. Measures FPS / 1% / 0.1% lows while chunks stream in, holes around the player,
##     chunk wait times, distance flown and time frozen at unloaded chunks.
## --fpsbench=A : stationary player, four fixed views, fully loaded world (steady-state rendering cost).
## Output: user://perf/fps_<stamp>/summary.json + screenshots; printed lines "[fps] ...".
## With --remote-debug (tools/profile.ps1) the measured window is marked for the script profiler.

const VIEWS := [[45.0, 12.0], [135.0, 12.0], [225.0, 12.0], [315.0, 12.0]]   # [yaw, pitch] (Java degrees)
const FLY_PITCH := 6.0
static var spike_log: PackedStringArray = []   # per-spike lines, printed after the measurement
static var SLOW_MS := 16.7   # slow-frame attribution threshold (--slowms=X)
const FLY_MIN_Y := 120.0
const FLY_CLEARANCE := 32.0


static func _pct(a: Array, q: float) -> float:
	if a.is_empty():
		return 0.0
	return a[clampi(int(a.size() * q), 0, a.size() - 1)]


## Frame-time statistics of a list of frame times (ms).
static func _ft_stats(ft_in: Array) -> Dictionary:
	var ft := ft_in.duplicate()
	ft.sort()
	var n := ft.size()
	if n == 0:
		return {}
	var tot := 0.0
	for f in ft:
		tot += f
	var low1 := 0.0
	var n1 := maxi(1, n / 100)
	for i in n1:
		low1 += ft[n - 1 - i]
	var low01 := 0.0
	var n01 := maxi(1, n / 1000)
	for i in n01:
		low01 += ft[n - 1 - i]
	var over := [0, 0, 0]
	for f in ft:
		if f > 16.7:
			over[0] += 1
		if f > 33.3:
			over[1] += 1
		if f > 50.0:
			over[2] += 1
	return {"frames": n, "fps_avg": snappedf(1000.0 * n / tot, 0.1), "fps_median": snappedf(1000.0 / _pct(ft, 0.5), 0.1),
		"fps_1pct_low": snappedf(1000.0 / (low1 / n1), 0.1), "fps_0_1pct_low": snappedf(1000.0 / (low01 / n01), 0.1),
		"ms_p50": snappedf(_pct(ft, 0.5), 0.01), "ms_p95": snappedf(_pct(ft, 0.95), 0.01), "ms_p99": snappedf(_pct(ft, 0.99), 0.01),
		"ms_max": snappedf(ft[n - 1], 0.01), "frames_over_16_7ms": over[0], "frames_over_33ms": over[1], "frames_over_50ms": over[2]}


## On-screen readout during the measured run: FPS (last 0.25 s) with the 1% and 0.1% lows of the run so far.
class Overlay:
	var layer: CanvasLayer
	var label: Label
	var hist := PackedInt32Array()   # frame-time histogram, 0.05 ms buckets up to 200 ms (constant cost per frame)
	var hn := 0
	var acc_n := 0
	var acc_ms := 0.0
	var last_upd := 0

	func _init(parent: Node) -> void:
		layer = CanvasLayer.new()
		layer.layer = 100
		label = Label.new()
		label.position = Vector2(16, 12)
		label.add_theme_font_size_override("font_size", 30)
		label.add_theme_color_override("font_color", Color(1, 1, 1))
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		label.add_theme_constant_override("outline_size", 6)
		label.text = "FPS --"
		hist.resize(4001)
		layer.add_child(label)
		parent.add_child(layer)

	func frame(ms: float, now_us: int) -> void:
		hist[mini(4000, int(ms * 20.0))] += 1
		hn += 1
		acc_n += 1
		acc_ms += ms
		if now_us - last_upd < 250000:
			return
		last_upd = now_us
		label.text = "FPS %d     1%% low %d     0.1%% low %d" % [roundi(1000.0 * acc_n / maxf(acc_ms, 0.001)), roundi(_low(maxi(1, hn / 100))), roundi(_low(maxi(1, hn / 1000)))]
		acc_n = 0
		acc_ms = 0.0

	## FPS of the average of the slowest k frames, from the histogram (bucket centres).
	func _low(k: int) -> float:
		var need := k
		var tot := 0.0
		var b := 4000
		while b >= 0 and need > 0:
			var c := mini(hist[b], need)
			tot += c * (b + 0.5) / 20.0
			need -= c
			b -= 1
		return 1000.0 * k / maxf(tot, 0.001)

	func close() -> void:
		layer.queue_free()


## Whole-frame GPU timeline of the last finished frame (every RD timestamp, incl. work outside the viewport timer):
## "[gpu] +offset_ms name" lines, buffered into spike_log (printed after the run).
static func _gpu_timeline() -> void:
	var rd := RenderingServer.get_rendering_device()
	if rd == null:
		return
	var n := rd.get_captured_timestamps_count()
	if n == 0:
		return
	var t0 := rd.get_captured_timestamp_gpu_time(0)
	var c0 := rd.get_captured_timestamp_cpu_time(0)
	for i in n:
		spike_log.append("[gpu] +%.3f ms (cpu +%.3f) %s" % [(rd.get_captured_timestamp_gpu_time(i) - t0) / 1000.0, (rd.get_captured_timestamp_cpu_time(i) - c0) / 1000.0, rd.get_captured_timestamp_name(i)])


class Sampler:
	var vp: RID
	var sums := {"render_cpu": 0.0, "render_gpu": 0.0, "draw_calls": 0.0, "primitives": 0.0}
	var n := 0

	func add() -> void:
		n += 1
		sums["render_cpu"] += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		sums["render_gpu"] += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		sums["draw_calls"] += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		sums["primitives"] += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)

	func result() -> Dictionary:
		var r := {}
		for k in sums:
			r[k] = snappedf(sums[k] / maxi(1, n), 0.001)
		return r


static func run(w) -> void:
	var cm: ChunkManager = w.cm
	var tree: SceneTree = w.get_tree()
	if w.autoplay.has("workers"):
		cm.max_jobs = int(w.autoplay["workers"])
	if w.autoplay.has("vcompress"):
		cm.vertex_compress = str(w.autoplay["vcompress"]) == "1"
	print("[fps] texture layers: %d" % Res.atlas.names.size())
	if w.autoplay.has("prepass"):
		ProjectSettings.set_setting("rendering/driver/depth_prepass/enable", str(w.autoplay["prepass"]) == "1")
	if w.autoplay.has("flatshader"):
		# experiment: terrain fragment cost — replace the voxel shader code with a constant colour
		for mat in [Res.mat_opaque, Res.mat_cutout]:
			var sh := Shader.new()
			sh.code = "shader_type spatial;\nrender_mode unshaded, cull_back, depth_draw_opaque;\nvoid fragment() { ALBEDO = vec3(0.4, 0.6, 0.3); }\n"
			(mat as ShaderMaterial).shader = sh
	if w.autoplay.has("hidegroup"):
		cm.debug_hide_group = int(w.autoplay["hidegroup"])
	var scen := str(w.autoplay.get("fpsbench", "F"))
	if scen == "" or scen == "1":
		scen = "F"
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var dir := "user://perf/fps_" + stamp
	DirAccess.make_dir_recursive_absolute(dir)
	var vp_rid: RID = w.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, not w.autoplay.has("nomeasure"))
	if w.autoplay.has("time"):   # fixed time of day for sky / lighting screenshots (daylight cycle frozen)
		w.day_time = int(w.autoplay["time"])
		w.gamerules["doDaylightCycle"] = false
	if w.autoplay.has("hold"):   # held item for view-model checks (A screenshots)
		w.player.inventory.set_slot(w.player.inventory.selected, ItemStack.named(str(w.autoplay["hold"]), 1))
	FrameProbe.busy_us = int(w.autoplay.get("busy", "0"))
	SLOW_MS = float(w.autoplay.get("slowms", "16.7"))
	if w.autoplay.has("rtprof"):
		BlockUpdates.prof = true
	# ---- wait for the fully loaded world (whole render distance visible, worker queue idle for 2 s)
	var t0 := Time.get_ticks_usec()
	var rd := int(Settings.get_v("render_distance"))
	var last_print := 0
	var idle_since := 0
	while Time.get_ticks_usec() - t0 < 150 * 1000000:
		await tree.process_frame
		if not w.spawn_ready:
			continue
		var now0 := Time.get_ticks_usec()
		var pc := LoadTest._pc(w)
		var vis := LoadTest._ring_visible(w, pc, rd)
		var pj := cm.pending_jobs()
		if now0 - last_print > 5000000:
			last_print = now0
			print("[fps] loading: visible %d / %d, pending jobs %d, chunks %d" % [vis, (2 * rd + 1) * (2 * rd + 1), pj, cm.chunks.size()])
		if vis == (2 * rd + 1) * (2 * rd + 1) and pj <= 2:
			if idle_since == 0:
				idle_since = now0
			elif now0 - idle_since > 2000000:
				break
		else:
			idle_since = 0
	var load_s := (Time.get_ticks_usec() - t0) / 1e6
	print("[fps] world loaded in %.1f s (%d chunks)" % [load_s, cm.chunks.size()])
	w._auto_input = true
	for i in 60:
		await tree.process_frame
	var summary := {"stamp": stamp, "scenario": scen, "arch": Engine.get_architecture_name(), "debug_build": OS.is_debug_build(),
		"window": DisplayServer.window_get_size(), "window_mode": DisplayServer.window_get_mode(), "screen": DisplayServer.screen_get_size(), "render_distance": rd, "simulation_distance": int(Settings.get_v("simulation_distance")),
		"vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps, "renderer": RenderingServer.get_current_rendering_driver_name(),
		"gpu": RenderingServer.get_video_adapter_name(), "workers": cm.max_jobs, "load_s": load_s,
		"chunk_manager_radius": cm.radius, "chunks_loaded_at_start": cm.chunks.size(), "fresh_world": OS.get_cmdline_user_args().has("--fresh")}
	var prof0: Dictionary = w.prof_us.duplicate()
	var cm0: Dictionary = cm.main_us.duplicate()
	var ds0: Dictionary = cm.disp_stats.duplicate()
	var bc0: Dictionary = w.block_change_log.duplicate()
	if EngineDebugger.is_active():
		EngineDebugger.send_message("recraft:bench", ["begin"])
	var n_all := 0
	var ov := Overlay.new(w)
	if scen == "V":
		n_all = await _vsync_test(w, summary)
	elif scen == "A":
		n_all = await _static(w, summary, vp_rid, ov, dir)
	else:
		n_all = await _flight(w, summary, vp_rid, dir, ov)
	_gpu_timeline()
	ov.close()
	if EngineDebugger.is_active():
		EngineDebugger.send_message("recraft:bench", ["end"])
		for i in 30:
			await tree.process_frame
	var main := {}
	for k in w.prof_us:
		main[k] = snappedf((int(w.prof_us[k]) - int(prof0.get(k, 0))) / 1000.0 / maxi(1, n_all), 0.001)
	for k in cm.main_us:
		main["cm." + k] = snappedf((int(cm.main_us[k]) - int(cm0.get(k, 0))) / 1000.0 / maxi(1, n_all), 0.001)
	summary["main_ms_per_frame"] = main
	var ds := {}
	for k in cm.disp_stats:
		ds[k] = snappedf((int(cm.disp_stats[k]) - int(ds0.get(k, 0))) / float(maxi(1, n_all)), 0.01)
	summary["dispatch_per_frame"] = ds
	var bl: Array = []
	for k in w.block_change_log:
		var dn := int(w.block_change_log[k]) - int(bc0.get(k, 0))
		if dn > 0:
			bl.append([dn, k])
	bl.sort()
	bl.reverse()
	summary["block_changes_during_run"] = bl.slice(0, 20)
	summary["memory_static_mb"] = snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1)
	summary["video_mem_mb"] = snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1)
	summary["entities"] = w.entities.ents.size() if w.entities != null else -1
	var f := FileAccess.open(dir + "/summary.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(summary, "  "))
	f.close()
	if w._trd != null:
		print("[trd] quads resident %d, pages %d, indirect cmds %d, cull %d us" % [int(w._trd.stats.get("quads_resident", 0)), w._trd.pages.size(), int(w._trd.stats.get("cmds", 0)), int(w._trd.stats.get("cull_us", 0))])
		var qn := maxi(1, int(w._trd.stats.get("q_n", 0)))
		print("[trd] per frame: quads drawn %d, groups %d, cmds %d" % [int(w._trd.stats.get("q_sum", 0)) / qn, int(w._trd.stats.get("g_sum", 0)) / qn, int(w._trd.stats.get("c_sum", 0)) / qn])
	if w.sky_rd != null:
		var sr: SkyRD = w.sky_rd
		print("[sky] clouds mode %d faces %d key %s cells %dx%d setting %s dist %s buf %s" % [sr.clouds_mode, sr.cloud_faces, str(sr._cloud_key), sr.cloud_w, sr.cloud_h, str(Settings.get_v("clouds")), str(Settings.get_v("cloud_distance")), str(sr.cloud_buf.is_valid())])
	for ln in spike_log:
		print(ln)
	spike_log.clear()
	if w._trd != null:
		for ln in w._trd.page_log:
			print(ln)
	if Native.inst != null and Native.inst.has_method("thread_cycles"):
		var c0: int = Native.inst.thread_cycles()[0]
		var tc0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - tc0 < 2000:
			pass
		print("[spike] cycle calibration: %.2f Mcyc per busy ms" % ((Native.inst.thread_cycles()[0] - c0) / 2.0e6))
	print("[fps] RESULT %s %s" % [scen, JSON.stringify(summary.get("frames", {}))])
	print("[fps] render per frame: %s" % JSON.stringify(summary.get("render", {})))
	if summary.has("streaming"):
		print("[fps] streaming: %s" % JSON.stringify(summary["streaming"]))
	print("[fps] main thread ms/frame: %s" % JSON.stringify(main))
	print("[fps] distances in use at the end: chunk manager radius %d, loaded chunks %d, random-tick area radius %d, entity tick distance setting %d" % [cm.radius, cm.chunks.size(), BlockUpdates._rtl_key.z, int(Settings.get_v("simulation_distance"))])
	print("[fps] chunks this run: generated %d, loaded from disk %d (fresh world: %s)" % [int(cm.stats["generated"]) - int(cm.stats.get("loaded_from_disk", 0)), int(cm.stats.get("loaded_from_disk", 0)), str(OS.get_cmdline_user_args().has("--fresh"))])
	if BlockUpdates.prof:
		var rtl: Array = []
		for rk in BlockUpdates.prof_us:
			rtl.append([snappedf(BlockUpdates.prof_us[rk] / 1000.0, 0.1), rk, int(BlockUpdates.prof_n.get(rk, 0))])
		rtl.sort_custom(func(a, b): return a[0] > b[0])
		print("[fps] random-tick handlers (total ms, block, count): %s" % JSON.stringify(rtl.slice(0, 24)))
	print("[fps] dispatch per frame: %s" % JSON.stringify(ds))
	print("[fps] block changes during run: %s" % JSON.stringify(bl.slice(0, 8)))
	print("[fps] summary: %s" % ProjectSettings.globalize_path(dir + "/summary.json"))
	cm.shutdown()
	tree.quit()


static func _static(w, summary: Dictionary, vp_rid: RID, ov: Overlay, dir := "") -> int:
	var tree: SceneTree = w.get_tree()
	var shot_done := false
	if w.autoplay.has("merged"):
		_merge_terrain(w)
		for i in 30:
			await tree.process_frame
	var secs := float(w.autoplay.get("fsecs", "6"))
	var all_ft: Array = []
	var smp := Sampler.new()
	smp.vp = vp_rid
	var views: Array = []
	for v in VIEWS:
		w.player.yaw = v[0]
		w.player.pitch = v[1]
		for i in 30:
			await tree.process_frame
		var ft: Array = []
		var vs := Sampler.new()
		vs.vp = vp_rid
		var last := Time.get_ticks_usec()
		var end := last + int(secs * 1e6)
		while true:
			await tree.process_frame
			var now := Time.get_ticks_usec()
			ft.append((now - last) / 1000.0)
			ov.frame((now - last) / 1000.0, now)
			last = now
			vs.add()
			smp.add()
			if now >= end:
				break
		if (not shot_done or w.autoplay.has("shots")) and dir != "":   # --shots=1: every view (render A/B checks)
			LoadTest._shot(w, dir, "A_view%d" % views.size())
			shot_done = true   # after this view's measurement (a readback stalls the frame)
		var vr := _ft_stats(ft)
		vr.merge(vs.result())
		if w._trd != null:
			vr["trd"] = w._trd.stats.duplicate()
			print("[fps] view %d: TerrainRD %s" % [int(v[0]), JSON.stringify(vr["trd"])])
		vr["yaw"] = v[0]
		views.append(vr)
		all_ft.append_array(ft)
	summary["views"] = views
	summary["frames"] = _ft_stats(all_ft)
	summary["render"] = smp.result()
	return all_ft.size()


## Settings check: the same Settings.set_v calls as the Video options page, 3 s each.
static func _vsync_test(w, summary: Dictionary) -> int:
	var tree: SceneTree = w.get_tree()
	var res := {}
	var n_all := 0
	for step in [["vsync", "on", 0], ["vsync", "off", 0], ["vsync", "adaptive", 0], ["vsync", "off", 60]]:
		Settings.set_v("vsync", step[1])
		Settings.set_v("max_fps", step[2])
		for i in 20:
			await tree.process_frame
		var n := 0
		var t0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - t0 < 3000000:
			await tree.process_frame
			n += 1
		n_all += n
		var label := "vsync %s, max_fps %d" % [step[1], step[2]]
		res[label] = {"fps": snappedf(n / ((Time.get_ticks_usec() - t0) / 1e6), 0.1), "driver_vsync_mode": DisplayServer.window_get_vsync_mode(), "engine_max_fps": Engine.max_fps}
		print("[fps] %s -> %s" % [label, JSON.stringify(res[label])])
	Settings.set_v("vsync", "off")
	Settings.set_v("max_fps", 0)
	summary["vsync_test"] = res
	summary["frames"] = {}
	return n_all


## Experiment (--merged=1): the same chunk geometry as ONE mesh per material (3 draws instead of ~1,750) to measure the
## per-draw cost of Godot's instance path. Chunk instances are hidden.
static func _merge_terrain(w) -> void:
	var cm: ChunkManager = w.cm
	var by_mat := {}   # material RID -> Array of [arrays, origin]
	var t0 := Time.get_ticks_msec()
	for c in cm.chunks.values():
		var ch: Chunk = c
		for g in ch.mesh_rids.size():
			var e = ch.mesh_rids[g]
			if e == null:
				continue
			var mesh: RID = e[0]
			var inst: RID = e[1]
			RenderingServer.instance_set_visible(inst, false)
			var org := PackedFloat32Array([ch.cx * 16 - cm.origin.x, Coords.MIN_Y + g * Mesher.GH - cm.origin.y, ch.cz * 16 - cm.origin.z])
			for si in RenderingServer.mesh_get_surface_count(mesh):
				var mat := RenderingServer.mesh_surface_get_material(mesh, si)
				var arrs := RenderingServer.mesh_surface_get_arrays(mesh, si)
				if by_mat.is_empty():
					var tl: Array = []
					for ai in arrs.size():
						tl.append(type_string(typeof(arrs[ai])))
					print("[fps] surface array types: %s" % str(tl))
				if not by_mat.has(mat):
					by_mat[mat] = []
				by_mat[mat].append([arrs, org])
	var t1 := Time.get_ticks_msec()
	var nverts := 0
	for mat in by_mat:
		var r: Array = Native.inst.merge_surfaces(by_mat[mat])
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = r[0]
		arrays[Mesh.ARRAY_TEX_UV] = r[1]
		arrays[Mesh.ARRAY_COLOR] = r[2]
		arrays[Mesh.ARRAY_CUSTOM0] = r[3]
		arrays[Mesh.ARRAY_INDEX] = r[4]
		nverts += (r[0] as PackedVector3Array).size()
		var mesh2 := RenderingServer.mesh_create()
		RenderingServer.mesh_add_surface_from_arrays(mesh2, RenderingServer.PRIMITIVE_TRIANGLES, arrays, [], {}, (RenderingServer.ARRAY_CUSTOM_RGBA_HALF << RenderingServer.ARRAY_FORMAT_CUSTOM0_SHIFT) | RenderingServer.ARRAY_FLAG_COMPRESS_ATTRIBUTES)
		RenderingServer.mesh_surface_set_material(mesh2, 0, mat)
		var inst2 := RenderingServer.instance_create2(mesh2, w.get_world_3d().scenario)
		RenderingServer.instance_geometry_set_cast_shadows_setting(inst2, RenderingServer.SHADOW_CASTING_SETTING_OFF)
	print("[fps] merged terrain: %d materials, %d vertices (read %d ms, merge+upload %d ms)" % [by_mat.size(), nverts, t1 - t0, Time.get_ticks_msec() - t1])


static func _surface(cm: ChunkManager, x: int, z: int) -> int:
	var c: Chunk = cm.chunks.get(Coords.chunk_key(x >> 4, z >> 4))
	if c == null or c.state < Chunk.DATA_READY or c.heightmap.size() < 256:
		return -9999
	return c.heightmap[(x & 15) + (z & 15) * 16]


## Scenario P actions for the frame that just ended; returns what happened (for the spike log).
## The events run right after the frame's measurement so their cost lands in the next measured frame.
static func _play_step(w, p: Player, dirv: Vector3, now: int, ps: int, stone: int, st: Dictionary) -> String:
	var ev := ""
	var el := (now - ps) / 1e6
	if now - int(st["edit"]) > 300000:
		st["edit"] = now
		if st["edit_at"] != null:
			var bp: Vector3i = st["edit_at"]
			w._break_block(bp, false)
			st["edit_at"] = null
			ev += "break "
		else:
			var q: Vector3 = p.pos + dirv * 3.0
			var bp := Vector3i(int(floor(q.x)), int(floor(p.pos.y)) + 2, int(floor(q.z)))
			if w.state_at(bp.x, bp.y, bp.z) == 0:
				w.set_block(bp.x, bp.y, bp.z, stone)
				st["edit_at"] = bp
				ev += "place "
	if now - int(st["dig"]) > 1000000:
		st["dig"] = now
		var q2: Vector3 = p.pos + dirv * 4.0
		var gp := Vector3i(int(floor(q2.x)), int(floor(p.pos.y)) - 1, int(floor(q2.z)))
		if w.state_at(gp.x, gp.y, gp.z) > 0:
			w._break_block(gp, false)
			ev += "dig "
	if el > float(st["next_inv"]) and w.screen == null:
		st["next_inv"] = float(st["next_inv"]) + 10.0
		st["inv_at"] = now
		var i0 := Time.get_ticks_usec()
		var inv_s = w.inventory_screen()
		var i1 := Time.get_ticks_usec()
		var i2 := Time.get_ticks_usec()
		w.open_screen(inv_s)
		ev += "inventory-open (load %.1f new %.1f open %.1f ms) " % [(i1 - i0) / 1000.0, (i2 - i1) / 1000.0, (Time.get_ticks_usec() - i2) / 1000.0]
	elif int(st["inv_at"]) > 0 and now - int(st["inv_at"]) > 1000000:
		st["inv_at"] = 0
		w.close_screen()
		ev += "inventory-close "
	if el > 20.0 and not st["saved"]:
		st["saved"] = true
		w._begin_autosave()
		ev += "autosave "
	return ev


static func _flight(w, summary: Dictionary, vp_rid: RID, dir: String, ov: Overlay) -> int:
	var cm: ChunkManager = w.cm
	var tree: SceneTree = w.get_tree()
	var secs := float(w.autoplay.get("fsecs", "60"))
	var dirv := Vector3(1, 0, -0.5).normalized()
	var p: Player = w.player
	# W: normal play on foot (sprinting, jumping over obstacles, swimming up) instead of the flight
	# P: W plus interaction (a block placed / broken every 0.3 s, ground dug every second, the inventory
	# opened for a second every 10 s, an autosave at 20 s)
	var play := str(w.autoplay.get("fpsbench", "F")) == "P"
	var walk := play or str(w.autoplay.get("fpsbench", "F")) == "W"
	var play_state := {"edit": 0, "dig": 0, "edit_at": null, "next_inv": 5.0, "inv_at": 0, "saved": false}
	var stone: int = Res.blocks.default_state("stone")
	var play_ev := ""
	p.mode = Player.Mode.CREATIVE
	p.flying = not walk
	p.yaw = rad_to_deg(atan2(-dirv.x, dirv.z))
	p.pitch = float(w.autoplay.get("fpitch", "10.0" if walk else str(FLY_PITCH)))
	# start high: climb straight up to cruising altitude before the measured flight (vanilla players take off first)
	var hstart := _surface(cm, int(floor(p.pos.x)), int(floor(p.pos.z)))
	if not walk:   # walking starts where the world placed the player (standing on the ground)
		p.pos.y = maxf(FLY_MIN_Y, float(hstart) + FLY_CLEARANCE)
		if w.autoplay.has("fy"):   # fixed altitude (sky / cloud checks)
			p.pos.y = float(w.autoplay["fy"])
	p.prev_pos = p.pos
	for i in 30:
		await tree.process_frame
	var smp := Sampler.new()
	smp.vp = vp_rid
	var ft: Array = []
	var entered := {}        # chunk key -> usec it came within ring 4 (-1 once visible)
	var waits: Array = []
	var miss := {2: 0, 4: 0, 8: 0}
	var miss_max := {2: 0, 4: 0, 8: 0}
	var samples := 0
	var frozen_s := 0.0
	var gen0: int = cm.stats["generated"]
	var start_pos := p.pos
	var timeline: Array = []
	var shots := [0.25, 0.5, 0.75]
	var ps := Time.get_ticks_usec()
	var lt := ps
	var last_sample := ps
	var last_pos := p.pos
	var slow := {}            # frames > 25 ms: summed main-thread parts (ms)
	var slow_n := 0
	var last_tick_no := -1
	var last_gt: int = w.game_time
	var last_up: int = cm.stats["uploaded"]
	var hist := {}   # slow frames by count of ticks run in the frame
	var fp := FrameProbe.install(w.get_tree().root)
	FrameProbe.speed_probe = w.autoplay.has("trace")
	var probe_sum := 0
	var probe2_sum := 0
	var probe_n := 0
	var prev_fp := fp.duplicate()
	var phase_sum := {}   # slow frames: process phase / draw / other (physics, input, pacing) of the PREVIOUS frame
	var all_ph := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]   # all frames: process phase, draw, other, world_manager, chunk_manager, ticks
	var last_freed: int = cm.freed_total
	var pipe_mons := [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH, Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW, Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]
	var pipe0 := 0.0
	for pm in pipe_mons:
		pipe0 += Performance.get_monitor(pm)
	var last_pipe := pipe0
	var pipe_slow := 0.0
	var stuck_at := ps
	var stuck_pos := p.pos
	# main-thread CPU time per frame (thread cycles; calibrated with a busy wait): a slow frame whose CPU time is far
	# below its wall time was descheduled / waiting, not computing
	var has_cyc: bool = Native.inst != null and Native.inst.has_method("thread_cycles")
	var cyc_ms := 1.0
	var last_cyc := 0
	if has_cyc:
		var cc0: int = Native.inst.thread_cycles()[0]
		var tc0 := Time.get_ticks_usec()
		while Time.get_ticks_usec() - tc0 < 3000:
			pass
		cyc_ms = maxf(1.0, (Native.inst.thread_cycles()[0] - cc0) / ((Time.get_ticks_usec() - tc0) / 1000.0))
		last_cyc = Native.inst.thread_cycles()[0]
	while Time.get_ticks_usec() - ps < secs * 1e6:
		if walk and Time.get_ticks_usec() - stuck_at > 1000000:
			# walking: blocked (under 1.5 blocks in the last second) -> turn 70 degrees
			if Vector2(p.pos.x - stuck_pos.x, p.pos.z - stuck_pos.z).length() < 1.5:
				dirv = dirv.rotated(Vector3.UP, deg_to_rad(70.0))
			stuck_at = Time.get_ticks_usec()
			stuck_pos = p.pos
		# controls: forward + sprint held all the time, jump (fly up) while below cruising altitude
		p.in_forward = 1.0
		p.in_strafe = 0.0
		p.in_sprint = true
		p.in_sneak = false
		var hmax := -9999
		for d in [0, 16, 32, 48, 64, 96]:
			var q: Vector3 = p.pos + dirv * float(d)
			hmax = maxi(hmax, _surface(cm, int(floor(q.x)), int(floor(q.z))))
		var target := maxf(FLY_MIN_Y, float(hmax) + FLY_CLEARANCE)
		if w.autoplay.has("fy"):
			target = float(w.autoplay["fy"])
		p.in_jump = (p.hcollide or p.in_water) if walk else p.pos.y < target
		p.yaw = rad_to_deg(atan2(-dirv.x, dirv.z))
		p.pitch = float(w.autoplay.get("fpitch", "10.0" if walk else str(FLY_PITCH)))
		await tree.process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - lt) / 1e6
		ft.append(dt * 1000.0)
		var cpu_ms := 0.0
		probe_sum += int(fp.get("probe_us", 0))
		probe2_sum += int(fp.get("probe2_us", 0))
		probe_n += 1
		if has_cyc:
			var cyc: int = Native.inst.thread_cycles()[0]
			cpu_ms = (cyc - last_cyc) / cyc_ms
			last_cyc = cyc
		var ev_before := play_ev   # events run after the previous frame's measurement land in this frame
		if play:
			play_ev = _play_step(w, p, dirv, now, ps, stone, play_state)
		ov.frame(dt * 1000.0, now)
		lt = now
		smp.add()
		var lp: Array = w.last_parts
		var ltp: Dictionary = w.last_tick_parts
		var ticked := int(ltp.get("tick_no", -1)) != last_tick_no
		last_tick_no = int(ltp.get("tick_no", -1))
		var gt: int = w.game_time
		var ticks_run := gt - last_gt
		last_gt = gt
		var up: int = cm.stats["uploaded"]
		var ups := up - last_up
		last_up = up
		var fr: int = cm.freed_total
		var frees := fr - last_freed
		last_freed = fr
		var pipe := 0.0
		for pm in pipe_mons:
			pipe += Performance.get_monitor(pm)
		var pipes := pipe - last_pipe
		last_pipe = pipe
		# phases of the frame that just ended: process [proc_start, proc_end], draw [pre_draw, post_draw], rest until now
		var ph_proc := (int(fp["proc_end"]) - int(fp["proc_start"])) / 1000.0
		var ph_draw := (int(fp["post_draw"]) - int(fp["pre_draw"])) / 1000.0
		var ph_gap1 := (int(fp["pre_draw"]) - int(fp["proc_end"])) / 1000.0
		var ph_before := (now - int(fp["post_draw"])) / 1000.0   # after draw until this frame's process starts
		prev_fp = fp.duplicate()
		all_ph[0] += ph_proc
		all_ph[1] += ph_draw
		all_ph[2] += ph_before + ph_gap1
		all_ph[3] += lp[5] / 1000.0
		all_ph[4] += lp[3] / 1000.0
		all_ph[5] += lp[0] / 1000.0
		if dt * 1000.0 > minf(20.0, SLOW_MS) and spike_log.size() < 600:
			# individual spike log: time, phases of the previous frame, chunk / tick work, TerrainRD pages
			var trd_pages: int = w._trd.pages.size() if w._trd != null else 0
			if ev_before != "":
				spike_log.append("[spike] (play events before this frame: %s)" % ev_before)
			# buffered: printing here (stdout to a file can block 20-40 ms) would itself cause the next spike
			spike_log.append("[spike] t=%.2fs %.1f ms (main cpu %.1f, probe %d us / avg %d, shared %d / avg %d, private %d): proc %.1f draw %.1f gap %.1f after %.1f | cm commit %.1f dispatch %.1f rebuild %.1f uploads %d | ticks %d | pages %d | %s" % [(now - ps) / 1e6, dt * 1000.0, cpu_ms, int(fp.get("probe_us", 0)), probe_sum / maxi(1, probe_n), int(fp.get("probe2_us", 0)), probe2_sum / maxi(1, probe_n), int(fp.get("probe3_us", 0)), ph_proc, ph_draw, ph_gap1, ph_before, cm.last_commit_us / 1000.0, cm.last_dispatch_us / 1000.0, cm.last_rebuild_us / 1000.0, ups, ticks_run, trd_pages, JSON.stringify(w.frame_tparts)])
			spike_log.append("[spike]   upload_slow %d | commit by kind %s | world parts ticks %.1f cam %.1f berender %.1f cm %.1f target+sky %.1f total %.1f" % [cm.frame_upload_slow, JSON.stringify(cm.last_commit_parts), lp[0] / 1000.0, lp[1] / 1000.0, lp[2] / 1000.0, lp[3] / 1000.0, lp[4] / 1000.0, lp[5] / 1000.0])
		if dt * 1000.0 > SLOW_MS:
			slow_n += 1
			hist[ticks_run] = int(hist.get(ticks_run, 0)) + 1
			phase_sum["E after draw: input+physics+pacing"] = float(phase_sum.get("E after draw: input+physics+pacing", 0.0)) + ph_before
			phase_sum["B process phase (all nodes)"] = float(phase_sum.get("B process phase (all nodes)", 0.0)) + ph_proc
			phase_sum["C process end -> pre_draw"] = float(phase_sum.get("C process end -> pre_draw", 0.0)) + ph_gap1
			phase_sum["D draw (render cpu + gpu sync)"] = float(phase_sum.get("D draw (render cpu + gpu sync)", 0.0)) + ph_draw
			slow["  render_cpu (prev frame)"] = float(slow.get("  render_cpu (prev frame)", 0.0)) + RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
			slow["  render_gpu (prev frame)"] = float(slow.get("  render_gpu (prev frame)", 0.0)) + RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
			slow["  mesh uploads"] = float(slow.get("  mesh uploads", 0.0)) + ups
			slow["  mesh frees"] = float(slow.get("  mesh frees", 0.0)) + frees
			pipe_slow += pipes
			var names := ["ticks", "camera+beacons+signs", "berender", "chunk_manager", "target+sky"]
			for q in 5:
				slow[names[q]] = float(slow.get(names[q], 0.0)) + lp[q] / 1000.0
			slow["outside world_manager._process (render, other nodes, engine)"] = float(slow.get("outside world_manager._process (render, other nodes, engine)", 0.0)) + dt * 1000.0 - lp[5] / 1000.0
			slow["  cm.dispatch"] = float(slow.get("  cm.dispatch", 0.0)) + cm.last_dispatch_us / 1000.0
			slow["  cm.commit"] = float(slow.get("  cm.commit", 0.0)) + cm.last_commit_us / 1000.0
			slow["  cm.rebuild+unload"] = float(slow.get("  cm.rebuild+unload", 0.0)) + cm.last_rebuild_us / 1000.0
			for fk in w.frame_tparts:
				slow["  f:" + str(fk)] = float(slow.get("  f:" + str(fk), 0.0)) + int(w.frame_tparts[fk]) / 1000.0
			if ticked:
				for tk in ltp:
					if tk != "tick_no":
						slow["  tick:" + tk] = float(slow.get("  tick:" + tk, 0.0)) + ltp[tk] / 1000.0
		var pc := LoadTest._pc(w)
		for dz in range(-4, 5):
			for dx in range(-4, 5):
				var key := Coords.chunk_key(pc.x + dx, pc.y + dz)
				if not entered.has(key):
					entered[key] = now
				var c: Chunk = cm.chunks.get(key)
				if c != null and c.shown and int(entered[key]) >= 0:
					waits.append(maxf(0.0, (c.shown_us - int(entered[key])) / 1000.0))
					entered[key] = -1
		if now - last_sample >= 250000:
			var moved := Vector2(p.pos.x - last_pos.x, p.pos.z - last_pos.z).length()
			if moved < 0.5:
				frozen_s += (now - last_sample) / 1e6
			last_pos = p.pos
			last_sample = now
			samples += 1
			var row := [snappedf((now - ps) / 1e6, 0.01), snappedf(1.0 / maxf(dt, 0.0001), 1.0), cm.pending_jobs(), snappedf(p.pos.y, 0.1), snappedf(moved * 4.0, 0.1)]
			for r in [2, 4, 8]:
				var m: int = (2 * r + 1) * (2 * r + 1) - LoadTest._ring_visible(w, pc, r)
				miss_max[r] = maxi(miss_max[r], m)
				if m > 0:
					miss[r] += 1
				row.append(m)
			timeline.append(row)

	p.in_forward = 0.0
	p.in_sprint = false
	p.in_jump = false
	LoadTest._shot(w, dir, "F_end")   # after the measured window (a readback stalls the frame)
	var fly_s := (Time.get_ticks_usec() - ps) / 1e6
	var still := 0
	for k in entered:
		if int(entered[k]) >= 0:
			still += 1
	waits.sort()
	var dist := Vector2(p.pos.x - start_pos.x, p.pos.z - start_pos.z).length()
	summary["frames"] = _ft_stats(ft)
	summary["render"] = smp.result()
	summary["streaming"] = {"seconds": snappedf(fly_s, 0.1), "distance_blocks": snappedf(dist, 0.1), "avg_speed": snappedf(dist / fly_s, 0.01),
		"frozen_at_unloaded_s": snappedf(frozen_s, 0.01), "altitude_end": snappedf(p.pos.y, 0.1),
		"generated_per_s": snappedf((cm.stats["generated"] - gen0) / fly_s, 0.1),
		"ring4_chunks_entered": entered.size(), "ring4_wait_ms_median": waits[waits.size() / 2] if not waits.is_empty() else -1.0,
		"ring4_wait_ms_p90": waits[int(waits.size() * 0.9)] if not waits.is_empty() else -1.0,
		"ring4_wait_ms_max": waits[waits.size() - 1] if not waits.is_empty() else -1.0, "ring4_never_visible": still,
		"samples": samples, "ring2_incomplete_pct": snappedf(100.0 * miss[2] / maxi(1, samples), 0.1),
		"ring4_incomplete_pct": snappedf(100.0 * miss[4] / maxi(1, samples), 0.1), "ring8_incomplete_pct": snappedf(100.0 * miss[8] / maxi(1, samples), 0.1),
		"ring2_missing_max": miss_max[2], "ring4_missing_max": miss_max[4], "ring8_missing_max": miss_max[8]}
	summary["timeline"] = timeline
	var sl := {}
	for k in slow:
		sl[k] = snappedf(slow[k] / maxi(1, slow_n), 0.01)
	summary["slow_frames_over_25ms"] = {"count": slow_n, "avg_ms_per_slow_frame": sl, "by_ticks_in_frame": hist}
	print("[fps] slow frames by number of game ticks in the frame: %s" % JSON.stringify(hist))
	var phs := {}
	for k in phase_sum:
		phs[k] = snappedf(phase_sum[k] / maxi(1, slow_n), 0.01)
	summary["slow_frame_phases_ms"] = phs
	var nf := maxf(1.0, float(ft.size()))
	var allp := {"process_phase": snappedf(all_ph[0] / nf, 0.001), "  world_manager": snappedf(all_ph[3] / nf, 0.001), "    chunk_manager": snappedf(all_ph[4] / nf, 0.001),
		"    ticks": snappedf(all_ph[5] / nf, 0.001), "  other nodes": snappedf((all_ph[0] - all_ph[3]) / nf, 0.001), "draw": snappedf(all_ph[1] / nf, 0.001), "other": snappedf(all_ph[2] / nf, 0.001)}
	summary["avg_frame_phases_ms"] = allp
	print("[fps] average frame phases (ms): %s" % JSON.stringify(allp))
	print("[fps] slow-frame phases (avg ms): %s" % JSON.stringify(phs))
	print("[fps] pipeline compilations during flight: %d (in slow frames: %d)" % [int(last_pipe - pipe0), int(pipe_slow)])
	summary["pipeline_compilations"] = [int(last_pipe - pipe0), int(pipe_slow)]
	print("[fps] slow frames (>16.7 ms): %d, avg ms per slow frame: %s" % [slow_n, JSON.stringify(sl)])
	return ft.size()
