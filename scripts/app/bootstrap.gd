## Bootstrap â€” main scene controller: asset detection/import -> title -> world list/create -> loading -> game.
## Why: one owner of top-level screen flow; screens are code-built Control trees (no fake buttons).
## Contract: command-line flags: --test (run headless test suite), --bench (benchmarks),
## --autoplay=<world> (smoke-load a world), --placeholder (force original placeholder mode).
extends Node

var ui_root: CanvasLayer
var screen_host: Control
var current: Node
var world: Node
var args: PackedStringArray


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	Native.init(args.has("--nonative=1") or args.has("--nonative"))
	ui_root = CanvasLayer.new()
	ui_root.layer = 10
	add_child(ui_root)
	# menu screens live in a host Control sized to the viewport: full-rect anchors directly under the CanvasLayer
	# resolved to 0x0, collapsing lists/tab pages and pushing buttons off screen
	screen_host = Control.new()
	screen_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(screen_host)
	_fit_host()
	get_viewport().size_changed.connect(_fit_host)
	Settings.changed.connect(func(k: String):
		if k == "gui_scale":
			_scale_dirty = true)
	if args.has("--check"):
		var bad := 0
		var n := 0
		for root in ["res://scripts", "res://scenes", "res://benchmarks"]:
			for p in _walk(root):
				n += 1
				var s = load(p)
				if s == null or not (s is GDScript) or not (s as GDScript).can_instantiate():
					print("FAIL ", p)
					bad += 1
		print("CHECKED %d scripts, %d failed" % [n, bad])
		get_tree().quit(1 if bad > 0 else 0)
		return
	if args.has("--test"):
		var t = load("res://scenes/tests/test_runner.gd").new()
		add_child(t)
		return
	await _boot_assets()
	for a in args:
		if a.begins_with("--rigtree="):
			var rt_root := EntityRenderer.build_rig(MobRegistry.get_def(a.substr(10)))
			var dump := func(n: Node, depth: int, f: Callable) -> void:
				var pos3: Vector3 = (n as Node3D).position if n is Node3D else Vector3.ZERO
				print("RIGTREE %s%s %s %s" % ["  ".repeat(depth), n.name, n.get_class(), str(pos3 * 16.0)])
				for ch in n.get_children():
					f.call(ch, depth + 1, f)
			dump.call(rt_root, 0, dump)
			get_tree().quit()
			return
		if a.begins_with("--rigcheck"):
			# every mob rig against its texture's Java box-UV layout: per box the opaque share of its six face rects
			# (wrong size / offset -> transparent), per texture the opaque texels no box uses (missing parts)
			var only := a.substr(11) if a.length() > 11 else ""
			var ids: Array = MobRegistry.ALL.duplicate()
			ids.append("end_crystal")
			for mid in ids:
				if only != "" and not (mid in only.split(",")):
					continue
				var d := MobRegistry.get_def(mid)
				if d.is_empty() or not d.has("parts"):
					print("RIGCHECK %s: no def" % mid)
					continue
				var img: Image = Res.load_image(str(d.get("tex", "")).trim_prefix("textures/"))
				if img == null:
					print("RIGCHECK %s: no texture %s" % [mid, d.get("tex", "")])
					continue
				if img.is_compressed():
					img.decompress()
				var ts: Array = d.get("tex_size", [64, 64])
				var sx := float(img.get_width()) / float(ts[0])
				var sy := float(img.get_height()) / float(ts[1])
				var used := PackedByteArray()
				used.resize(int(ts[0]) * int(ts[1]))
				var bad: Array = []
				var boxes: Array = []
				for p in d["parts"]:
					boxes.append([str(p[0]), p[3], p[4]])
					if p.size() > 9 and p[9] is Array:
						for ex in p[9]:
							boxes.append([str(ex[0]), ex[2], ex[3]])
				for bx in boxes:
					var s: Array = bx[1]
					var uv: Array = bx[2]
					var w := int(ceil(absf(float(s[0]))))
					var h := int(ceil(absf(float(s[1]))))
					var dd := int(ceil(absf(float(s[2]))))
					var u := int(uv[0])
					var v := int(uv[1])
					var rects := [Rect2i(u + dd, v, w, dd), Rect2i(u + dd + w, v, w, dd), Rect2i(u, v + dd, dd, h), Rect2i(u + dd, v + dd, w, h),
						Rect2i(u + dd + w, v + dd, dd, h), Rect2i(u + 2 * dd + w, v + dd, w, h)]
					var tot := 0
					var opq := 0
					var outside := 0
					for r in rects:
						for yy in range(r.position.y, r.end.y):
							for xx in range(r.position.x, r.end.x):
								tot += 1
								if xx < 0 or yy < 0 or xx >= int(ts[0]) or yy >= int(ts[1]):
									outside += 1
									continue
								used[yy * int(ts[0]) + xx] = 1
								if img.get_pixel(int(xx * sx), int(yy * sy)).a > 0.05:
									opq += 1
					if tot > 0 and (float(opq) / tot < 0.6 or outside > 0):
						bad.append("%s %d%%%s" % [bx[0], int(100.0 * opq / tot), " OUT" if outside > 0 else ""])
				var unused := 0
				var opaque := 0
				for yy in int(ts[1]):
					for xx in int(ts[0]):
						if img.get_pixel(int(xx * sx), int(yy * sy)).a > 0.05:
							opaque += 1
							if used[yy * int(ts[0]) + xx] == 0:
								unused += 1
				print("RIGCHECK %-16s unused %3d%% of %5d opaque | low boxes: %s" % [mid, int(100.0 * unused / maxi(1, opaque)), opaque, ", ".join(bad)])
			get_tree().quit()
			return
		if a.begins_with("--tpldump="):
			# layer maps of a template (y up, rows = z, columns = x); '.' = air, ' ' = no block (ignored by legacy elements)
			var raw3 := NBT.parse(Res.jar.read_bytes("data/minecraft/structure/%s.nbt" % a.substr(10)))
			var pal3: Array = raw3.get("palettes", [raw3.get("palette", [])])[0] if raw3.has("palettes") else raw3.get("palette", [])
			var sz3: Array = raw3.get("size", [0, 0, 0])
			var chars := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789#$%&*+=?"
			var legend := []
			for pi in pal3.size():
				var pn := str(pal3[pi].get("Name", pal3[pi].get("id", ""))).trim_prefix("minecraft:")
				legend.append("%s=%s" % ["." if pn == "air" else chars[pi % chars.length()], pn])
			print("TPLDUMP size ", sz3, " ", ", ".join(legend))
			var grid := {}
			for b3 in raw3.get("blocks", []):
				var p3: Array = b3["pos"]
				var pn3 := str(pal3[int(b3["state"])].get("Name", pal3[int(b3["state"])].get("id", ""))).trim_prefix("minecraft:")
				grid[Vector3i(int(p3[0]), int(p3[1]), int(p3[2]))] = "." if pn3 == "air" else chars[int(b3["state"]) % chars.length()]
			for yy in int(sz3[1]):
				print("TPLDUMP y=%d" % yy)
				for zz in int(sz3[2]):
					var row := ""
					for xx in int(sz3[0]):
						row += str(grid.get(Vector3i(xx, yy, zz), " "))
					print("TPLDUMP   |" + row + "|")
			get_tree().quit()
			return
		if a == "--tplcheck":
			# every structure template's palette entries that do not resolve to a block state (they would place air)
			var bad_names := {}
			var nt := 0
			for fpath in Res.list_files("data/minecraft/structure/"):
				if not str(fpath).ends_with(".nbt"):
					continue
				nt += 1
				var raw2 := NBT.parse(Res.jar.read_bytes(str(fpath)))
				var pls: Array = raw2.get("palettes", [raw2.get("palette", [])])
				for pl in pls:
					for e in pl:
						var nm := str(e.get("Name", e.get("id", "minecraft:air")))
						var props: Dictionary = e.get("Properties", e.get("properties", {}))
						if nm in ["minecraft:air", "minecraft:structure_void"]:
							continue
						var st := Res.blocks.state_of(nm, props)
						var why := ""
						if st < 0:
							why = "props" if Res.blocks.default_state(nm.trim_prefix("minecraft:")) > 0 else "NAME"
						if why != "":
							var k := "%s %s %s" % [why, nm, str(props) if why == "props" else ""]
							if not bad_names.has(k):
								bad_names[k] = str(fpath).get_file()
			print("TPLCHECK %d templates, %d unresolved" % [nt, bad_names.size()])
			for k in bad_names:
				print("TPLCHECK ", k, " in ", bad_names[k])
			get_tree().quit()
			return
		if a.begins_with("--tpl="):
			var raw := NBT.parse(Res.jar.read_bytes("data/minecraft/structure/%s.nbt" % a.substr(6)))
			print("TPL keys ", raw.keys(), " size ", raw.get("size"))
			var pal: Array = raw.get("palette", raw.get("palettes", [[]])[0] if raw.has("palettes") else [])
			for e in pal:
				if str(e.get("Name", "")).contains("jigsaw"):
					print("TPL palette ", e, " -> state ", Res.blocks.state_of(str(e["Name"]), e.get("Properties", {})), " name ", Res.blocks.name_of(maxi(Res.blocks.state_of(str(e["Name"]), e.get("Properties", {})), 0)))
			print("TPL pal16 ", pal[16] if pal.size() > 16 else "n/a", " pal size ", pal.size())
			var nb := 0
			for b2 in raw.get("blocks", []):
				if b2.has("nbt"):
					nb += 1
					if nb < 3:
						print("TPL nbt block ", b2)
			var t := StructureTemplate.get_template(a.substr(6))
			print("TPL loaded jigsaws ", t.jigsaws.size() if t != null else -1, " blocks with nbt ", nb)
			get_tree().quit()
			return
		if a.begins_with("--listraw="):
			for f in Res.list_files(a.substr(10)):
				print("RAW ", f)
			get_tree().quit()
			return
		if a.begins_with("--listassets="):
			for f in Res.list_files("assets/minecraft/" + a.substr(13)):
				print("ASSET ", f)
			get_tree().quit()
			return
		if a.begins_with("--listfiles="):
			for f in Res.list_files("data/minecraft/" + a.substr(12), ".json"):
				var j2 = Res.read_json(f)
				print("FILE ", f.get_file().get_basename(), " ", str(j2.get("type", "?")) if j2 is Dictionary else "?")
			get_tree().quit()
			return
		if a.begins_with("--listtypes="):
			# --listtypes=<dir under data/minecraft/>: histogram of "type" fields (dev tool)
			var hist := {}
			for f in Res.list_files("data/minecraft/" + a.substr(12), ".json"):
				var j = Res.read_json(f)
				var t := str(j.get("type", "?")) if j is Dictionary else "?"
				hist[t] = int(hist.get(t, 0)) + 1
			print("TYPES ", JSON.stringify(hist))
			get_tree().quit()
			return
		if a.begins_with("--dumpmany="):
			# --dumpdir= unused; --dumpmany=<dir>:<name1>,<name2>,... (dev tool)
			var parts := a.substr(11).split(":")
			for nm in parts[1].split(","):
				print("DUMP ", nm, " ", JSON.stringify(Res.read_json("data/minecraft/%s/%s.json" % [parts[0], nm])))
			get_tree().quit()
			return
		if a.begins_with("--dumptext="):   # local reference only: prints a text asset (e.g. a vanilla shader) from the user's jar
			print("DUMPTEXT_BEGIN")
			print(Res.jar.read_text(a.substr(11)) if Res.jar != null else "")
			print("DUMPTEXT_END")
			get_tree().quit()
			return
		if a.begins_with("--dumpjson="):
			print("DUMP ", JSON.stringify(Res.read_json(a.substr(11))))
			get_tree().quit()
			return
	if args.has("--report"):
		add_child(load("res://scenes/tests/report.gd").new())
		return
	if args.has("--emptybench"):
		add_child(load("res://scripts/app/empty_bench.gd").new())
		return
	if args.has("--contention"):
		add_child(load("res://benchmarks/contention_probe.gd").new())
		return
	if args.has("--bench-contention"):
		add_child(load("res://benchmarks/bench_contention.gd").new())
		return
	if args.has("--bench-mt"):
		add_child(load("res://benchmarks/bench_mt.gd").new())
		return
	if args.has("--bench"):
		var b = load("res://benchmarks/bench_runner.gd").new()
		add_child(b)
		return
	if args.has("--crawl"):
		await _crawl()
		return
	for a in args:
		if a.begins_with("--ui="):
			# dev: open a menu screen, save a screenshot to user://autoplay/ui_<name>.png and quit
			var nm := a.substr(5)
			match nm:
				"create_world", "create_world_go":
					show_create_world()
				"world_list":
					show_world_list()
				"multiplayer":
					var mp = load("res://scripts/ui/multiplayer_screen.gd").new()
					mp.app = self
					_set_screen(mp)
				"create_world_world", "create_world_more", "game_rules", "flat", "presets", "single_biome":
					show_create_world()
					await get_tree().process_frame
					match nm:
						"create_world_world":
							current._show(1)
						"create_world_more":
							current._show(2)
						"game_rules":
							current._game_rules()
						"flat", "presets":
							current.st["type"] = 1
							current._customize()
							if nm == "presets":
								await get_tree().process_frame
								current.get_child(current.get_child_count() - 1)._presets()
						"single_biome":
							current.st["type"] = 4
							current._customize()
				"options", "options_video", "options_sounds", "options_controls", "options_keybinds", "options_language", "options_packs", "options_access", "options_online", "options_advanced":
					show_options(func(): show_title())
					await get_tree().process_frame
					var sub := {"options_video": "_video", "options_sounds": "_sounds", "options_controls": "_controls", "options_keybinds": "_keybinds",
						"options_language": "_language", "options_packs": "_packs", "options_access": "_accessibility", "options_online": "_online_screen", "options_advanced": "_advanced_video"}
					if sub.has(nm):
						current._open(current.call(sub[nm]))
						if args.has("--uiclose"):   # dev: close the sub-screen again (back-navigation checks)
							for i in 20:
								await get_tree().process_frame
							if current._sub != null:
								current._sub.close()
							for i in 20:
								await get_tree().process_frame
							print("[ui] after close: current %s visible children %d" % [current.get_script().resource_path.get_file() if current != null else "-", current.get_children().filter(func(ch): return ch is Control and ch.visible).size() if current != null else -1])
					for b3 in args:
						if b3.begins_with("--uiscale="):   # dev: change the GUI scale like the Video Settings slider does
							for i in 10:
								await get_tree().process_frame
							Settings.set_v("gui_scale", int(b3.substr(10)))
							print("[ui] gui scale set to %d (effective %d)" % [int(b3.substr(10)), UiKit.scale()])
							for i in 20:
								await get_tree().process_frame
							if current != null and current.get("_sub") != null and current._sub.get("list") != null:
								var lst: McList = current._sub.list
								for ri in [1, 2]:
									for e in lst.row_widgets.get(ri, []):
										var wc: Control = e[0]
										print("[ui] row %d %s pos %s size %s min %s combined %s" % [ri, wc.get_class(), str(wc.position), str(wc.size), str(wc.custom_minimum_size), str(wc.get_combined_minimum_size())])
							if args.has("--uishot"):
								DirAccess.make_dir_recursive_absolute("user://autoplay")
								await RenderingServer.frame_post_draw
								get_viewport().get_texture().get_image().save_png("user://autoplay/ui_after_scale.png")
					if args.has("--uidone"):   # dev: press Done on the options screen (return-to-title checks)
						for i in 20:
							await get_tree().process_frame
						if current != null and current.has_method("_done_pressed"):
							if current._sub != null:
								current._sub.close()
								for i in 10:
									await get_tree().process_frame
							current._done_pressed()
						for i in 30:
							await get_tree().process_frame
						var vis: Array = []
						if current != null and is_instance_valid(current):
							for ch in current.get_children():
								if ch is Control:
									var cc: Control = ch
									vis.append("%s%s@%s %s" % [cc.get_class(), "" if cc.is_visible_in_tree() else "(hidden)", str(cc.position.round()), str(cc.size.round())])
						print("[ui] after done: current %s in tree %s visible %s modulate %s children: %s" % [current.get_script().resource_path.get_file() if current != null and is_instance_valid(current) else "-", str(current.is_inside_tree()) if current != null and is_instance_valid(current) else "-", str(current.is_visible_in_tree()) if current != null and is_instance_valid(current) else "-", str(current.modulate) if current != null and is_instance_valid(current) else "-", ", ".join(vis)])
				"edit_world", "delete_world":
					show_world_list()
					await get_tree().process_frame
					if nm == "edit_world":
						current._edit()
					else:
						current._delete()
				_:
					show_title()
			for i in 30:
				await get_tree().process_frame
			for b2 in OS.get_cmdline_user_args():
				if b2.begins_with("--uiclicks="):
					# dev: real mouse clicks at GUI-pixel points, "x,y;x,y;..." (back-navigation / input checks)
					for pt in b2.substr(11).split(";"):
						var cp2 := pt.split(",")
						var at2 := Vector2(float(cp2[0]), float(cp2[1])) * float(UiKit.scale())
						Input.warp_mouse(at2)
						var mv := InputEventMouseMotion.new()
						mv.position = at2
						mv.global_position = at2
						Input.parse_input_event(mv)
						for i in 5:
							await get_tree().process_frame
						for down in [true, false]:
							var mb := InputEventMouseButton.new()
							mb.button_index = MOUSE_BUTTON_LEFT
							mb.pressed = down
							mb.position = at2
							mb.global_position = at2
							Input.parse_input_event(mb)
							await get_tree().process_frame
						for i in 30:
							await get_tree().process_frame
						print("[ui] clicked %s -> current %s" % [pt, current.get_script().resource_path.get_file() if current != null and is_instance_valid(current) else "-"])
				if b2.begins_with("--uihover="):
					# dev: hover a GUI-pixel point (tooltips / highlight / hit tests) before the screenshot
					var hp := b2.substr(10).split(",")
					var mm := InputEventMouseMotion.new()
					mm.position = Vector2(float(hp[0]), float(hp[1])) * float(UiKit.scale())
					mm.global_position = mm.position
					Input.warp_mouse(mm.position)
					Input.parse_input_event(mm)
					for i in 40:
						await get_tree().process_frame
					var hov: Control = get_viewport().gui_get_hovered_control()
					if hov != null:
						print("[ui] hovered %s (%s) scale %d tooltip %s" % [hov.name, hov.get_class(), UiKit.scale(), JSON.stringify(hov.get_tooltip(hov.get_local_mouse_position()))])
			if nm == "create_world_go":
				# end-to-end: press Create, wait for the spawn, screenshot the game
				current.st["name"] = "UI Test World"
				current._create()
				var t0 := Time.get_ticks_msec()
				var shot_loading := false
				while Time.get_ticks_msec() - t0 < 60000 and (world == null or not world.spawn_ready):
					await get_tree().process_frame
					if not shot_loading and Time.get_ticks_msec() - t0 > 1500 and world != null:
						shot_loading = true
						await RenderingServer.frame_post_draw
						DirAccess.make_dir_recursive_absolute("user://autoplay")
						get_viewport().get_texture().get_image().save_png("user://autoplay/ui_loading.png")
				print("[ui] world visible after %d ms (preload %.0f%%)" % [Time.get_ticks_msec() - t0, world.preload_progress() * 100.0 if world != null else -1.0])
				for i in 120:
					await get_tree().process_frame
				print("[ui] world started: %s, folder %s, spawn ready %s" % [str(world != null), world.folder if world != null else "-", str(world.spawn_ready) if world != null else "-"])
			DirAccess.make_dir_recursive_absolute("user://autoplay")
			var img := get_viewport().get_texture().get_image()
			if img != null:
				img.save_png("user://autoplay/ui_%s.png" % nm)
			get_tree().quit()
			return
		if a.begins_with("--netjoin="):
			# dev: join a LAN host directly (--netjoin=ip:port), passing the other flags as autoplay options
			var opts := {}
			for b in args:
				if b.begins_with("--") and b.contains("="):
					var kv := b.substr(2).split("=")
					opts[kv[0]] = kv[1]
			var hp := a.substr(10)
			Net.join(self, hp.get_slice(":", 0), int(hp.get_slice(":", 1)), str(opts.get("name", "Tester")), opts)
			return
		if a.begins_with("--autoplay"):
			_autoplay()
			return
	show_title()


## Render/gameplay probe: --autoplay [--seed=N] [--gen=id] [--mode=0..3] [--fresh] [--secs=N]
func _autoplay() -> void:
	var opts := {"seed": "12345", "gen": "java_26_3" if Res.mode == "vanilla" else "approx_original", "mode": "1", "secs": "25"}
	for a in args:
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)   # values may contain '=' (--cmds block states)
			opts[kv[0]] = kv[1]
	# every automated run: borderless fullscreen (in memory only; --res=WxH keeps a window for resolution tests)
	if not opts.has("res"):
		Settings.values["display_mode"] = "borderless"
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var folder := "autoplay_" + str(opts["gen"]) + "_" + str(opts["seed"])
	if opts.has("fpsbench"):
		# FPS benchmark: RD16 / SD12, uncapped (V-Sync off, no FPS cap, no background cap / focus pause), 1920x1080;
		# in memory only, the settings file is not saved
		Settings.values["render_distance"] = int(opts.get("rd", "16"))
		Settings.values["simulation_distance"] = int(opts.get("sd", "12"))
		Settings.values["vsync"] = "off"
		if opts.has("aa"):
			Settings.values["antialiasing"] = str(opts["aa"])
		if opts.has("rscale"):
			Settings.values["render_scale"] = int(opts["rscale"])
		Settings.values["max_fps"] = 0
		Settings.values["background_fps"] = 0
		Settings.values["pause_on_lost_focus"] = false
		if opts.has("set"):   # cost experiments: --set=clouds:off,biome_blend:2 (typed like the current value)
			for kv in str(opts["set"]).split(","):
				var p := kv.split(":")
				if p.size() == 2 and Settings.values.has(p[0]):
					var cur = Settings.values[p[0]]
					Settings.values[p[0]] = int(p[1]) if cur is int else (float(p[1]) if cur is float else (p[1] == "true" if cur is bool else p[1]))
		# borderless fullscreen at the display's native resolution, as in normal play (--res=WxH: windowed at that size)
		Settings.values["display_mode"] = "windowed" if opts.has("res") else "borderless"
		if str(opts.get("wmode", "")) == "exclusive":
			Settings.values["display_mode"] = "fullscreen"
		Settings.apply_all()
		if opts.has("res"):
			var res := str(opts["res"]).split("x")
			DisplayServer.window_set_size(Vector2i(int(res[0]), int(res[1])))
			DisplayServer.window_set_position(Vector2i(0, 0))
	if opts.has("loadtest"):
		# load test: render distance 16 / simulation 12, V-Sync and FPS caps off, in memory only (settings file not saved)
		Settings.values["render_distance"] = int(opts.get("rd", "16"))
		Settings.values["simulation_distance"] = int(opts.get("sd", "12"))
		Settings.values["vsync"] = "off"
		if opts.has("aa"):
			Settings.values["antialiasing"] = str(opts["aa"])
		if opts.has("rscale"):
			Settings.values["render_scale"] = int(opts["rscale"])
		Settings.values["max_fps"] = 0
		Settings.values["background_fps"] = 0
		Settings.values["pause_on_lost_focus"] = false
		Settings.apply_all()
	if args.has("--fresh") and DirAccess.dir_exists_absolute(SaveManager.ROOT.path_join(folder)):
		SaveManager.delete_world(folder)
	if not DirAccess.dir_exists_absolute(SaveManager.ROOT.path_join(folder)):
		var sm := SaveManager.new()
		var meta := {"name": folder, "seed": RandomSources.parse_seed(str(opts["seed"])), "game_mode": int(opts["mode"]), "difficulty": 2,
			"allow_commands": true, "generator_id": str(opts["gen"]), "generator_version": 1, "generator_settings": {"structures": true}, "content_version": Res.version}
		sm.create_world(meta)
		DirAccess.rename_absolute(SaveManager.ROOT.path_join(sm.folder), SaveManager.ROOT.path_join(folder))
	start_world(folder, opts)


func _walk(d: String) -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(d):
		return out
	for f in DirAccess.get_files_at(d):
		if f.ends_with(".gd"):
			out.append(d.path_join(f))
	for sub in DirAccess.get_directories_at(d):
		out.append_array(_walk(d.path_join(sub)))
	return out


func _boot_assets() -> void:
	if args.has("--placeholder") or Settings.get_v("placeholder_mode"):
		await Res.load_placeholder()
		return
	var cached := AssetImporter.find_any_cached()
	var found := MinecraftLocator.scan([Settings.get_v("custom_mc_dir")] if Settings.get_v("custom_mc_dir") != "" else [])
	var best := MinecraftLocator.pick_best(found)
	if not best.is_empty() and AssetImporter.is_cache_valid(best):
		await _load_with_screen(AssetImporter.load_manifest(best["version"]))
		return
	if best.is_empty() and not cached.is_empty():
		await _load_with_screen(cached)
		return
	if DisplayServer.get_name() == "headless":
		if not best.is_empty():
			var rep := AssetImporter.run(best, func(_m, _f): pass)
			if rep["ok"]:
				await Res.load_vanilla(rep["manifest"])
				return
		await Res.load_placeholder()
		return
	# interactive import screen
	var scr = load("res://scripts/ui/import_screen.gd").new()
	scr.found = found
	scr.best = best
	_set_screen(scr)
	var result: Dictionary = await scr.finished
	if result.get("placeholder", false):
		await Res.load_placeholder()
	else:
		await _load_with_screen(result["manifest"])


func _load_with_screen(manifest: Dictionary) -> void:
	var ls = load("res://scripts/ui/loading_screen.gd").new()
	_set_screen(ls)
	Res.progress.connect(ls.set_progress)
	var ok: bool = await Res.load_vanilla(manifest)
	Res.progress.disconnect(ls.set_progress)
	if not ok:
		await Res.load_placeholder()


## Menu crawler (spec 28): every menu screen must fill the window, and every Button must be on screen, non-zero
## sized and connected (no dead buttons). Tab pages of TabContainers are visited too. Prints CRAWL lines + summary.
func _crawl() -> void:
	var fails := 0
	var checked := 0
	var screens := {"title": show_title, "world_list": show_world_list, "create_world": show_create_world,
		"options": func(): show_options(func(): show_title()), "multiplayer": func():
			var m = load("res://scripts/ui/multiplayer_screen.gd").new()
			m.app = self
			_set_screen(m)}
	var vp := get_viewport().get_visible_rect()
	for sname in screens:
		(screens[sname] as Callable).call()
		for i in 10:
			await get_tree().process_frame
		var scr: Control = current
		if scr.size.x < vp.size.x - 1 or scr.size.y < vp.size.y - 1:
			print("CRAWL FAIL %s: screen is %s, window %s" % [sname, str(scr.size), str(vp.size)])
			fails += 1
		var tabsets: Array = []
		_collect(scr, "TabContainer", tabsets)
		var pages := 1
		for tc in tabsets:
			pages = maxi(pages, (tc as TabContainer).get_tab_count())
		for page in pages:
			for tc in tabsets:
				if page < (tc as TabContainer).get_tab_count():
					(tc as TabContainer).current_tab = page
			for i in 3:
				await get_tree().process_frame
			var buttons: Array = []
			_collect(scr, "Button", buttons)
			for b in buttons:
				var bt: BaseButton = b
				if not bt.is_visible_in_tree():
					continue
				checked += 1
				var r := bt.get_global_rect()
				var label := str(bt.get("text")) if bt.get("text") != null else bt.name
				var in_scroll := false
				var anc: Node = bt.get_parent()
				while anc != null and anc != scr:
					if anc is ScrollContainer:
						in_scroll = true
					anc = anc.get_parent()
				# inside a ScrollContainer vertical overflow is reachable by scrolling; horizontal overflow is not OK
				var off := (r.position.x < 0 or r.end.x > vp.size.x + 1) if in_scroll else not vp.encloses(r.grow(-1))
				if r.size.x < 2 or r.size.y < 2 or off:
					print("CRAWL FAIL %s[tab %d]: button '%s' off screen or zero size %s" % [sname, page, label, str(r)])
					fails += 1
				elif bt is Button and not (bt is OptionButton) and not (bt is CheckBox) and bt.get_signal_connection_list("pressed").is_empty() and bt.get_signal_connection_list("toggled").is_empty():
					print("CRAWL FAIL %s[tab %d]: button '%s' has no action" % [sname, page, label])
					fails += 1
	print("CRAWL RESULT %d controls checked, %d failures" % [checked, fails])
	get_tree().quit(1 if fails > 0 else 0)


func _collect(n: Node, cls: String, out: Array) -> void:
	for c in n.get_children():
		if c.is_class(cls):
			out.append(c)
		_collect(c, cls, out)


func _fit_host() -> void:
	if screen_host != null:
		screen_host.position = Vector2.ZERO
		screen_host.size = get_viewport().get_visible_rect().size
	_scale_dirty = true   # Auto / clamped GUI scales follow the window size (Java resizeDisplay)


## GUI scale changes apply when the mouse button is up (the Video Settings slider is not rebuilt under the drag),
## to the menu screens and the world's HUD / screens (UiKit.apply_scale).
var _scale_dirty := false


func _process(_delta: float) -> void:
	if _scale_dirty and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_scale_dirty = false
		var roots: Array = [screen_host]
		if world != null and is_instance_valid(world) and world.get("hud") != null:
			roots.append(world.hud)
		UiKit.apply_scale(roots)


func _set_screen(n: Node) -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = n
	_sync_panorama(n != null and world == null)
	if n != null:
		screen_host.add_child(n)
		if n is Control:
			(n as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Java: one panorama renders behind every screen while no level is loaded.
var panorama: Control


func _sync_panorama(want: bool) -> void:
	want = want and Res.is_loaded()   # boot / import screens come before the assets
	if want and panorama != null and is_instance_valid(panorama) and panorama.get_meta("mode", "") != Res.mode:
		panorama.queue_free()
		panorama = null
	if want and (panorama == null or not is_instance_valid(panorama)):
		panorama = PanoramaBg.new()
		panorama.set_meta("mode", Res.mode)
		screen_host.add_child(panorama)
		screen_host.move_child(panorama, 0)
	elif not want and panorama != null and is_instance_valid(panorama):
		panorama.queue_free()
		panorama = null


func show_title() -> void:
	Audio.set_music_context("menu")
	var t = load("res://scripts/ui/title_menu.gd").new()
	t.app = self
	_set_screen(t)


func show_world_list() -> void:
	var w = load("res://scripts/ui/world_list.gd").new()
	w.app = self
	_set_screen(w)


func show_create_world() -> void:
	var c = load("res://scripts/ui/create_world.gd").new()
	c.app = self
	_set_screen(c)


func show_options(back: Callable) -> void:
	var o = load("res://scripts/ui/options_menu.gd").new()
	o.back = back
	_set_screen(o)


func start_world(folder: String, autoplay_opts: Dictionary = {}) -> void:
	_set_screen(null)
	var w = load("res://scripts/world/world_manager.gd").new()
	w.app = self
	w.folder = folder
	w.autoplay = autoplay_opts
	world = w
	add_child(w)


func leave_world() -> void:
	if world != null and is_instance_valid(world):
		await world.save_and_close()
		world.queue_free()
	world = null
	show_title()


func quit() -> void:
	if world != null and is_instance_valid(world):
		await world.save_and_close()
	Settings.save()
	get_tree().quit()
