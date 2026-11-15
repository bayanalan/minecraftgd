## OptionsMenu — Java OptionsScreen (`options.main`): HeaderAndFooterLayout(61, 33); header = "Options" + [FOV
## slider | Online...] (150 each, 8 apart); contents (at min(header + 30, h - footer - height)) = 2-column grid of
## 150-px buttons (cell padding 4): Skin Customization / Music & Sounds, Video Settings / Controls, Language / Chat
## Settings, Resource Packs / Accessibility Settings, Telemetry Data / Credits & Attribution; footer Done (200).
## Sub-screens are OptionsSub lists built from Settings (see each _xxx() below); they replace this screen visually
## and return to it. Opened from the title (panorama) or the pause menu (in-world background); Done returns to
## the right parent through `back`.
extends Control

var back: Callable
var world = null
var _title: Label
var _fov: McSlider
var _online: Button
var _grid: Array = []
var _done: Button
var _sub: Control


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UiKit.theme()
	UiKit.background(self)
	Settings.changed.connect(_on_setting_changed)
	_title = McW.text(Res.tr_key("options.title", "Options"), Color(1, 1, 1), HORIZONTAL_ALIGNMENT_CENTER)
	add_child(_title)
	_fov = OptionsSub.sld("fov", 30, 110, 1, func(v): return Res.tr_key("options.fov", "FOV") + ": " + (Res.tr_key("options.fov.min", "Normal") if int(v) == 70 else (Res.tr_key("options.fov.max", "Quake Pro") if int(v) == 110 else str(int(v)))))
	add_child(_fov)
	_online = UiKit.button(Res.tr_key("options.online", "Online..."), func(): _open(_online_screen()), 150)
	add_child(_online)
	var items := [
		["options.skinCustomisation", "Skin Customization...", _skin],
		["options.sounds", "Music & Sounds...", _sounds],
		["options.video", "Video Settings...", _video],
		["options.controls", "Controls...", _controls],
		["options.language", "Language...", _language],
		["options.chat", "Chat Settings...", _chat],
		["options.resourcepack", "Resource Packs...", _packs],
		["options.accessibility", "Accessibility Settings...", _accessibility],
		["options.telemetry", "Telemetry Data...", _telemetry],
		["options.credits_and_attribution", "Credits & Attribution...", _credits],
	]
	for it in items:
		var mk: Callable = it[2]
		var b := UiKit.button(Res.tr_key(it[0], it[1]), func(): _open(mk.call()), 150)
		add_child(b)
		_grid.append(b)
	_done = UiKit.button(Res.tr_key("gui.done", "Done"), _done_pressed, 200)
	add_child(_done)
	_layout()
	resized.connect(_layout)


func _layout() -> void:
	var s := float(UiKit.scale())
	var gw := size.x / s
	var gh := size.y / s
	var c := floorf(gw / 2.0)
	# header 61: [title 9, 8, row 20] centred -> starts at 12
	McW.place(_title, 0, 12 - 1, gw, 9)
	McW.place(_fov, c - 154, 29, 150, 20)
	McW.place(_online, c + 4, 29, 150, 20)
	var rows := int(ceil(_grid.size() / 2.0))
	var gh_grid := rows * 24.0
	var top := minf(61.0 + 30.0, gh - 33.0 - gh_grid)
	for i in _grid.size():
		McW.place(_grid[i], c - 154 + (i % 2) * 158, top + (i / 2) * 24, 150, 20)
	McW.place(_done, c - 100, gh - 27, 200, 20)


var _hidden: Array = []   # this screen's own controls hidden while a sub-screen is open (restored when it goes away)


## Shows a sub-screen in place of this one. The controls hidden here are recorded once and restored whenever the
## sub-screen goes away by any route (its Done / Esc -> on_close, or simply leaving the tree); a sub-screen opened
## while another is open replaces it without re-recording (re-recording saved "hidden" and left a blank screen).
func _open(scr: Control) -> void:
	if scr == null:
		return
	if _sub != null and is_instance_valid(_sub) and _sub != scr:
		var old := _sub
		_sub = null
		old.queue_free()
	if _hidden.is_empty():
		for ch in get_children():
			if ch is CanvasItem and (ch as CanvasItem).visible:
				_hidden.append(ch)
				(ch as CanvasItem).visible = false
	_sub = scr
	scr.set("on_close", func():
		if _sub == scr:
			_restore())
	scr.tree_exited.connect(func():
		if _sub == scr:
			_restore())
	add_child(scr)


func _restore() -> void:
	_sub = null
	for ch in _hidden:
		if is_instance_valid(ch):
			(ch as CanvasItem).visible = true
	_hidden.clear()


## Esc in game: close the open sub-screen first, then behave like Done.
func on_escape() -> void:
	if _sub != null and is_instance_valid(_sub):
		if _sub.has_method("close"):
			_sub.close()
		return
	_done_pressed()


func _done_pressed() -> void:
	Settings.save()
	UiKit.reset_theme()
	if back.is_valid():
		back.call()
	else:
		queue_free()
		UiKit.return_fallback(self)


static func _sub_screen(title: String, rows: Array, footer: Array = []) -> OptionsSub:
	var o := OptionsSub.new()
	o.title = title
	o.rows = rows
	o.footer = footer
	return o


const NA_ENGINE := "Not implemented in Recraft yet"


# ---------------------------------------------------------------- Video Settings

func _video() -> Control:
	var T := func(k, f): return Res.tr_key(k, f)
	var onoff := func(v): return Res.tr_key("options.on", "ON") if v else Res.tr_key("options.off", "OFF")
	var gmax := Settings.max_gui_scale(DisplayServer.window_get_size())
	var gui := OptionsSub.sld("gui_scale", 0, gmax, 1, func(v): return T.call("options.guiScale", "GUI Scale") + ": " + (T.call("options.guiScale.auto", "Auto") if int(v) == 0 else str(int(v))))
	var fps := OptionsSub.sld_list("max_fps", [30, 60, 90, 120, 144, 240, 0], func(v): return T.call("options.framerateLimit", "Max Framerate") + ": " + (T.call("options.framerateLimit.max", "Unlimited") if int(v) == 0 else T.call("options.framerate", "%s fps").replace("%s", str(v))))
	var fullscreen := McW.on_off(T.call("options.fullscreen", "Fullscreen"), str(Settings.get_v("display_mode")) != "windowed", func(v): Settings.set_v("display_mode", "borderless" if v else "windowed"))
	var exclusive := McW.on_off(T.call("options.exclusiveFullscreen", "Exclusive Fullscreen"), str(Settings.get_v("display_mode")) == "fullscreen", func(v): Settings.set_v("display_mode", "fullscreen" if v else "borderless"))
	var bright := OptionsSub.sld("brightness", 0.0, 1.0, 0.01, func(v):
		var t: String = T.call("options.gamma", "Brightness") + ": "
		if v <= 0.0:
			return t + T.call("options.gamma.min", "Moody")
		if v >= 1.0:
			return t + T.call("options.gamma.max", "Bright")
		if is_equal_approx(v, 0.5):
			return t + T.call("options.gamma.default", "Default")
		return t + "+%d%%" % int(roundf(v * 200.0)))
	var api := OptionsSub.na(T.call("options.graphicsApi", "Graphics API") + ": " + T.call("options.graphicsApi.default", "Default"), "Recraft renders through Godot's Forward+ renderer (Vulkan / Direct3D 12); not selectable here")
	var preset := OptionsSub.cyc(T.call("options.graphics.preset", "Preset"), "preset", ["low", "fast", "balanced", "fancy", "ultra", "custom"],
		["Low", T.call("options.graphics.fast", "Fast"), "Balanced", T.call("options.graphics.fancy", "Fancy"), T.call("options.graphics.fabulous", "Fabulous!"), T.call("options.graphics.custom", "Custom")])
	var rd := OptionsSub.sld("render_distance", 2, 32, 1, func(v): return T.call("options.renderDistance", "Render Distance") + ": " + T.call("options.chunks", "%s Chunks").replace("%s", str(int(v))))
	var sd := OptionsSub.sld("simulation_distance", 5, 32, 1, func(v): return T.call("options.simulationDistance", "Simulation Distance") + ": " + T.call("options.chunks", "%s Chunks").replace("%s", str(int(v))))
	var ao := OptionsSub.cyc(T.call("options.ao", "Smooth Lighting"), "smooth_lighting", ["off", "low", "high"], [T.call("options.ao.off", "OFF"), T.call("options.ao.min", "Minimum"), T.call("options.ao.max", "Maximum")])
	var blend := OptionsSub.sld("biome_blend", 0, 7, 1, func(v): return T.call("options.biomeBlendRadius", "Biome Blend") + ": " + (T.call("options.off", "OFF") if int(v) == 0 else "%dx%d" % [int(v) * 2 + 1, int(v) * 2 + 1]))
	var clouds := OptionsSub.cyc(T.call("options.renderClouds", "Clouds"), "clouds", ["off", "fast", "fancy"], [T.call("options.off", "OFF"), T.call("options.graphics.fast", "Fast"), T.call("options.graphics.fancy", "Fancy")])
	var cdist := OptionsSub.sld("cloud_distance", 2, 128, 1, func(v): return T.call("options.renderCloudsDistance", "Cloud Distance") + ": " + T.call("options.chunks", "%s Chunks").replace("%s", str(int(v))))
	var parts := OptionsSub.cyc(T.call("options.particles", "Particles"), "particles", ["all", "decreased", "minimal"], [T.call("options.particles.all", "All"), T.call("options.particles.decreased", "Decreased"), T.call("options.particles.minimal", "Minimal")])
	var edist := OptionsSub.sld("entity_distance", 50, 500, 25, func(v): return T.call("options.entityDistanceScaling", "Entity Distance") + ": %d%%" % int(v))
	var mip := OptionsSub.tog(T.call("options.mipmapLevels", "Mipmap Levels"), "mipmaps", "Recraft builds 4 mipmap levels when on")
	var aniso := OptionsSub.sld_list("anisotropy", [0, 2, 4, 8, 16], func(v): return T.call("options.maxAnisotropy", "Anisotropic Filtering") + ": " + (T.call("options.off", "OFF") if int(v) == 0 else T.call("options.multiplier", "%sx").replace("%s", str(v))))
	var vig := OptionsSub.tog(T.call("options.vignette", "Show Vignette"), "vignette")
	var bob := OptionsSub.tog(T.call("options.viewBobbing", "View Bobbing"), "view_bobbing")
	var atk := OptionsSub.cyc(T.call("options.attackIndicator", "Attack Indicator"), "attack_indicator", ["off", "crosshair", "hotbar"], [T.call("options.off", "OFF"), T.call("options.attack.crosshair", "Crosshair"), T.call("options.attack.hotbar", "Hotbar")])
	var rows := [
		["header", T.call("options.video.display.header", "Display")],
		[fullscreen, exclusive],
		[gui, fps],
		[OptionsSub.cyc(T.call("options.vsync", "VSync"), "vsync", ["off", "on", "adaptive"], [T.call("options.off", "OFF"), T.call("options.on", "ON"), "Adaptive"]), bright],
		[api, OptionsSub.sld_list("background_fps", [15, 30, 60], func(v): return T.call("options.inactivityFpsLimit", "Reduce fps when") + ": %s fps" % str(v))],
		["header", T.call("options.video.quality.header", "Quality & Performance")],
		[preset, rd],
		[sd, ao],
		[blend, clouds],
		[cdist, parts],
		[OptionsSub.na(T.call("options.entityShadows", "Entity Shadows") + ": OFF", NA_ENGINE), edist],
		[mip, aniso],
		[OptionsSub.na(T.call("options.textureFiltering", "Texture Filtering") + ": " + T.call("options.textureFiltering.none", "None"), "Recraft samples terrain with nearest + mipmaps; RGSS is not implemented yet"),
			OptionsSub.na(T.call("options.improvedTransparency", "Improved Transparency") + ": OFF", NA_ENGINE)],
		[OptionsSub.na(T.call("options.chunkFade.none", "Chunk Fade: None"), "Chunk fade-in is not implemented yet"),
			OptionsSub.cyc(T.call("options.weatherRadius", "Weather Effect Radius"), "weather_visuals", ["off", "reduced", "full"], [T.call("options.off", "OFF"), "5", "10"])],
		[vig, OptionsSub.na(T.call("options.cutoutLeaves", "See-Through Leaves") + ": " + T.call("options.on", "ON"), "Leaves always render cut-out (fancy) in Recraft")],
		["header", T.call("options.video.preferences.header", "Preferences")],
		[bob, atk],
		[OptionsSub.na(T.call("options.autosaveIndicator", "Autosave Indicator") + ": OFF", NA_ENGINE), OptionsSub.na(T.call("options.showNowPlayingToast", "Show Music Toast") + ": OFF", NA_ENGINE)],
		["header", "Recraft"],
		[OptionsSub.cyc("Terrain Renderer", "terrain_renderer", ["rd", "godot"], ["RD", "Godot"], "Takes effect when a world loads"),
			OptionsSub.cyc("FPS Counter", "show_fps", ["off", "fps", "fps_lows"], [T.call("options.off", "OFF"), "FPS", "FPS + lows"])],
		[OptionsSub.cyc("Antialiasing", "antialiasing", ["off", "fxaa", "taa", "msaa2", "msaa4", "msaa8"], [T.call("options.off", "OFF"), "FXAA", "TAA", "MSAA 2x", "MSAA 4x", "MSAA 8x"]),
			OptionsSub.sld("render_scale", 50, 100, 5, func(v): return "Render Scale: %d%%" % int(v))],
		[OptionsSub.cyc("Fog", "fog", ["off", "vanilla", "enhanced"], [T.call("options.off", "OFF"), "Vanilla", "Enhanced"]), OptionsSub.tog("Debug Metrics", "debug_metrics")],
		[OptionsSub.btn("Re-import Assets", func():
			var m := AssetImporter.find_any_cached()
			if not m.is_empty():
				DirAccess.remove_absolute(AssetImporter.manifest_path(str(m["version"])))),
			OptionsSub.tog("Placeholder Assets", "placeholder_mode", "Use Recraft's original placeholder art instead of your Minecraft install (restart)")],
		[OptionsSub.btn("Advanced...", func(): _open_advanced()), null],
	]
	var vs := _sub_screen(T.call("options.videoTitle", "Video Settings"), rows)
	vs.set_meta("video", true)
	_video_preset_btn = preset
	return vs


## Java VideoSettingsScreen: picking a preset updates every option on the screen; changing an option the presets set
## turns the preset into Custom.
var _video_preset_btn: Button
var _video_rebuild_pending := false


func _on_setting_changed(key: String) -> void:
	if _sub == null or not is_instance_valid(_sub) or not _sub.has_meta("video"):
		return
	if key == "preset":
		if not _video_rebuild_pending:
			_video_rebuild_pending = true
			call_deferred("_rebuild_video")
	elif _video_preset_btn != null and is_instance_valid(_video_preset_btn):
		var pi := ["low", "fast", "balanced", "fancy", "ultra", "custom"].find(str(Settings.get_v("preset")))
		if pi >= 0:
			McW.cycle_set(_video_preset_btn, pi)


func _rebuild_video() -> void:
	_video_rebuild_pending = false
	if _sub != null and is_instance_valid(_sub) and _sub.has_meta("video"):
		_open(_video())


## Advanced video: Recraft's optimizations, each one switchable (Done returns to Video Settings).
func _open_advanced() -> void:
	var a := _advanced_video()
	_open(a)
	a.set("on_close", func(): _open(_video()))


func _advanced_video() -> Control:
	var onoff := func(v): return Res.tr_key("options.on", "ON") if v else Res.tr_key("options.off", "OFF")
	var thr := OptionsSub.sld("adv_threads", 0, 16, 1, func(v): return "Chunk Builder Threads: " + ("Auto" if int(v) == 0 else str(int(v))))
	thr.tooltip_text = "Worker threads generating, lighting and meshing chunks. Auto = 1/3 of the CPU threads (2..5), more while a world loads. More threads load faster but compete with the game for the CPU."
	var rows := [
		["header", "CPU"],
		[thr, OptionsSub.tog("Fast-Core Pinning", "adv_pin_main", "Keeps the game thread on the fastest core cluster and chunk generation on the other cores (CPUs with mixed core types: Snapdragon clusters, Intel P/E cores). Fewer stutters while chunks load.")],
		["header", "Chunk Meshes (rebuilds loaded chunks)"],
		[OptionsSub.tog("Leaf Culling", "adv_leaf_cull", "Off (vanilla): every leaf face is drawn. On: skips leaf faces that sit behind two layers of leaves, where the leaf textures cannot be seen through - forests look the same with far fewer faces (faster in dense forests)."),
			OptionsSub.tog("Face Merging", "adv_merge_faces", "Merges neighbouring faces with identical texture and lighting into one quad (pixel-identical). OFF = one quad per block face like Java.")],
		["header", "Rendering"],
		[OptionsSub.tog("Occlusion Culling", "adv_occlusion", "Skips 16-block sections hidden behind solid terrain (Java's chunk visibility graph)."),
			OptionsSub.tog("Face Direction Culling", "adv_dir_cull", "Skips faces that point away from the camera before drawing them.")],
		["header", "Quality of Life (not in vanilla)"],
		[OptionsSub.tog("Connected Glass", "adv_ctm", "Glass and stained glass panes of the same kind join without their frames (connected textures)."),
			OptionsSub.tog("Fullbright", "adv_fullbright", "Everything lit as under Night Vision: caves and nights stay bright.")],
		[OptionsSub.tog("Zoom Key (C)", "adv_zoom", "Hold C to zoom in (a quarter of the field of view)."),
			OptionsSub.tog("Show Coordinates", "adv_coords", "Your position and facing in the top-left corner (without the F3 screen).")],
	]
	return _sub_screen("Advanced Video Settings", rows)


# ---------------------------------------------------------------- Music & Sounds

func _sounds() -> Control:
	var vol := func(cat: String, key: String) -> McSlider:
		return OptionsSub.sld(key, 0.0, 1.0, 0.01, func(v): return Res.tr_key("soundCategory." + cat, cat) + ": " + (Res.tr_key("options.off", "OFF") if v <= 0.0 else "%d%%" % int(roundf(v * 100.0))))
	var rows := [
		["big", vol.call("master", "vol_master")],
		[vol.call("music", "vol_music"), vol.call("record", "vol_jukebox")],
		[vol.call("weather", "vol_weather"), vol.call("block", "vol_blocks")],
		[vol.call("hostile", "vol_hostile"), vol.call("neutral", "vol_neutral")],
		[vol.call("player", "vol_players"), vol.call("ambient", "vol_ambient")],
		[vol.call("voice", "vol_voice"), vol.call("ui", "vol_ui")],
		["big", OptionsSub.na(Res.tr_key("options.audioDevice", "Device") + ": " + Res.tr_key("options.audioDevice.default", "System Default"), "Recraft plays through the system default audio device")],
		[OptionsSub.tog(Res.tr_key("options.showSubtitles", "Closed Captions"), "subtitles"), OptionsSub.na(Res.tr_key("options.directionalAudio", "Directional Audio"), NA_ENGINE)],
		[OptionsSub.na(Res.tr_key("options.music_frequency", "Music Frequency"), NA_ENGINE), OptionsSub.na(Res.tr_key("options.showNowPlayingToast", "Show Music Toast"), NA_ENGINE)],
	]
	return _sub_screen(Res.tr_key("options.sounds.title", "Music & Sound Options"), rows)


# ---------------------------------------------------------------- Controls / Mouse / Key binds

func _controls() -> Control:
	var hold := [Res.tr_key("options.key.hold", "Hold"), Res.tr_key("options.key.toggle", "Toggle")]
	var mk := func(label_key: String, fb: String, key: String) -> Button:
		return McW.cycle(Res.tr_key(label_key, fb), hold, 1 if Settings.get_v(key) else 0, func(i): Settings.set_v(key, i == 1))
	var rows := [
		[OptionsSub.btn(Res.tr_key("options.mouse_settings", "Mouse Settings..."), func(): _open(_mouse())),
			OptionsSub.btn(Res.tr_key("controls.keybinds", "Key Binds..."), func(): _open(_keybinds()))],
		[mk.call("key.sneak", "Sneak", "toggle_sneak"), mk.call("key.sprint", "Sprint", "toggle_sprint")],
		[OptionsSub.tog(Res.tr_key("options.autoJump", "Auto-Jump"), "auto_jump"), OptionsSub.na(Res.tr_key("options.operatorItemsTab", "Operator Items Tab"), NA_ENGINE)],
		[OptionsSub.na(Res.tr_key("options.quitShortcuts", "Quit Shortcuts"), NA_ENGINE), OptionsSub.tog("Double-tap Sprint", "double_tap_sprint")],
	]
	return _sub_screen(Res.tr_key("controls.title", "Controls"), rows)


func _mouse() -> Control:
	var rows := [
		[OptionsSub.sld("sensitivity", 0.0, 1.0, 0.005, func(v): return Res.tr_key("options.sensitivity", "Sensitivity") + ": " + ("*yawn*" if v <= 0.0 else ("HYPERSPEED!!!" if v >= 1.0 else "%d%%" % int(roundf(v * 200.0))))),
			OptionsSub.na(Res.tr_key("options.invertMouseX", "Invert Mouse X"), NA_ENGINE)],
		[OptionsSub.tog(Res.tr_key("options.invertMouseY", "Invert Mouse Y"), "invert_y"), OptionsSub.na(Res.tr_key("options.mouseWheelSensitivity", "Scroll Sensitivity"), NA_ENGINE)],
		[OptionsSub.na(Res.tr_key("options.discrete_mouse_scroll", "Discrete Scrolling"), NA_ENGINE), OptionsSub.na(Res.tr_key("options.touchscreen", "Touchscreen Mode"), NA_ENGINE)],
		[OptionsSub.na(Res.tr_key("options.allowCursorChanges", "Allow Cursor Changes"), NA_ENGINE), null],
	]
	return _sub_screen(Res.tr_key("options.mouse_settings.title", "Mouse Settings"), rows)


## Java KeyBindsList: category headers (key.categories.*), rows = name (left, white), key button 75 px and
## Reset 50 px at the right (Reset active only when changed); conflicts in red; "> key <" in yellow while
## listening. Footer: Reset Keys | Done.
const KEYBIND_CATS := [
	["movement", [["move_forward", "key.forward"], ["move_left", "key.left"], ["move_back", "key.back"], ["move_right", "key.right"], ["jump", "key.jump"], ["sneak", "key.sneak"], ["sprint", "key.sprint"]]],
	["gameplay", [["attack", "key.attack"], ["use", "key.use"], ["pick_block", "key.pickItem"]]],
	["inventory", [["drop", "key.drop"], ["hotbar_1", "key.hotbar.1"], ["hotbar_2", "key.hotbar.2"], ["hotbar_3", "key.hotbar.3"], ["hotbar_4", "key.hotbar.4"], ["hotbar_5", "key.hotbar.5"], ["hotbar_6", "key.hotbar.6"], ["hotbar_7", "key.hotbar.7"], ["hotbar_8", "key.hotbar.8"], ["hotbar_9", "key.hotbar.9"], ["inventory", "key.inventory"], ["swap_offhand", "key.swapOffhand"]]],
	["multiplayer", [["player_list", "key.playerlist"], ["chat", "key.chat"], ["command", "key.command"]]],
	["misc", [["screenshot", "key.screenshot"], ["perspective", "key.togglePerspective"], ["fullscreen", "key.fullscreen"], ["hide_hud", "key.hideGui"], ["debug", "key.debug.overlay"], ["pause", "key.pause"]]],
]


func _keybinds() -> Control:
	var o := OptionsSub.new()
	o.title = Res.tr_key("controls.keybinds.title", "Key Binds")
	o.rows = []
	var conflicted := {}
	for c in Controls.conflicts():
		for a in c:
			conflicted[a] = true
	for cat in KEYBIND_CATS:
		o.rows.append(["header", Res.tr_key("key.categories." + str(cat[0]), str(cat[0]).capitalize())])
		for e in cat[1]:
			var a: String = e[0]
			if not Controls.DEFAULTS.has(a):
				continue
			var b := UiKit.button(Controls.label(a), func(): pass, 75)
			if conflicted.has(a):
				(b as McButton).set_color(Color8(255, 85, 85))
			var rst := UiKit.button(Res.tr_key("controls.reset", "Reset"), func(): pass, 50)
			rst.disabled = Controls.code_of(a) == int(Controls.DEFAULTS[a])
			for c in b.pressed.get_connections():
				b.pressed.disconnect(c["callable"])
			b.pressed.connect(func():
				Audio.play_ui("ui.button.click")
				b.text = "> " + Controls.label(a) + " <"
				(b as McButton).set_color(Color8(255, 255, 85))
				_pending = [a, b, rst])
			for c in rst.pressed.get_connections():
				rst.pressed.disconnect(c["callable"])
			rst.pressed.connect(func():
				Audio.play_ui("ui.button.click")
				Controls.rebind(a, int(Controls.DEFAULTS[a]))
				b.text = Controls.label(a)
				rst.disabled = true)
			var lab := McW.text(Res.tr_key(e[1], a.replace("_", " ").capitalize()))
			o.rows.append(["at", [lab, 0, 170], [b, 310 - 4 - 50 - 5 - 75, 75], [rst, 310 - 4 - 50, 50]])
	o.footer = [[Res.tr_key("controls.resetAll", "Reset Keys"), func():
		Controls.reset_all()
		o.close()
		_open(_keybinds()), 150], [Res.tr_key("gui.done", "Done"), func(): o.close(), 150]]
	return o

var _pending: Array = []


func _input(event: InputEvent) -> void:
	if _pending.is_empty():
		return
	var code := 0
	if event is InputEventKey and event.pressed:
		code = event.physical_keycode
		if event.keycode == KEY_ESCAPE:
			code = 0
			(_pending[1] as Button).text = Controls.label(_pending[0])
			(_pending[1] as McButton).set_color(null)
			_pending = []
			get_viewport().set_input_as_handled()
			return
	elif event is InputEventMouseButton and event.pressed:
		code = -int(event.button_index)
	if code == 0:
		return
	get_viewport().set_input_as_handled()
	Controls.rebind(_pending[0], code)
	var kb := _pending[1] as Button
	kb.text = Controls.label(_pending[0])
	(kb as McButton).set_color(null)
	if _pending.size() > 2:
		(_pending[2] as Button).disabled = code == int(Controls.DEFAULTS[_pending[0]])
	_pending = []


# ---------------------------------------------------------------- Accessibility / Skin / Chat / Online etc.

func _accessibility() -> Control:
	var T := func(k, f): return Res.tr_key(k, f)
	var rows := [
		[OptionsSub.na(T.call("options.narrator", "Narrator") + ": " + T.call("options.narrator.notavailable", "Not Available"), "No text-to-speech narrator in Recraft yet"),
			OptionsSub.tog(T.call("options.showSubtitles", "Closed Captions"), "subtitles")],
		[OptionsSub.tog(T.call("options.accessibility.high_contrast", "High Contrast"), "high_contrast"), OptionsSub.tog(T.call("options.autoJump", "Auto-Jump"), "auto_jump")],
		[OptionsSub.sld("menu_blur", 0, 10, 1, func(v): return T.call("options.accessibility.menu_background_blurriness", "Menu Background Blur") + ": " + (T.call("options.off", "OFF") if int(v) == 0 else str(int(v)))),
			OptionsSub.sld("panorama_speed", 0.0, 2.0, 0.01, func(v): return T.call("options.accessibility.panorama_speed", "Panorama Scroll Speed") + ": " + (T.call("options.off", "OFF") if v <= 0.0 else "%d%%" % int(roundf(v * 100.0))))],
		[OptionsSub.sld("distortion", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.screenEffectScale", "Distortion Effects"))),
			OptionsSub.sld("damage_tilt", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.damageTiltStrength", "Damage Tilt")))],
		[OptionsSub.tog(T.call("options.hideLightningFlashes", "Hide Sky Flashes"), "hide_lightning"), OptionsSub.tog("Text Shadow", "text_shadow")],
		[OptionsSub.sld("fov_effects", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.fovEffectScale", "FOV Effects"))),
			OptionsSub.sld("darkness_pulsing", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.darknessEffectScale", "Darkness Pulsing")))],
		[OptionsSub.sld("glint_speed", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.glintSpeed", "Glint Speed"))),
			OptionsSub.sld("glint_strength", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.glintStrength", "Glint Strength")))],
		[OptionsSub.sld("text_bg_opacity", 0.0, 1.0, 0.01, OptionsSub.pct(T.call("options.accessibility.text_background_opacity", "Text Background Opacity"))), OptionsSub.tog("Pause on Lost Focus", "pause_on_lost_focus")],
	]
	return _sub_screen(T.call("options.accessibility.title", "Accessibility Settings"), rows)


func _skin() -> Control:
	# Recraft addition: the name used on LAN (Java uses the signed-in account's name)
	var name_edit := McW.edit(str(Settings.get_v("player_name")), "", 16)
	name_edit.text_changed.connect(func(t): Settings.set_v("player_name", t))
	var rows := [
		["at", [McW.text("Player Name (LAN)"), 0, 150], [name_edit, 158, 150]],
		[OptionsSub.cyc(Res.tr_key("options.mainHand", "Main Hand"), "main_hand", ["left", "right"], [Res.tr_key("options.mainHand.left", "Left"), Res.tr_key("options.mainHand.right", "Right")]),
			OptionsSub.tog("Slim Arms", "slim_arms")],
	]
	# Java PlayerModelPart toggles: live on the player rigs (third person, inventory preview); no cape texture exists
	var reapply := func():
		if world != null and world.get("player_model") != null:
			EntityRenderer.apply_skin_parts(world.player_model)
		EntityRenderer.apply_skin_parts(InventoryPreview.rig)
	for pair in [["cape", "jacket"], ["left_sleeve", "right_sleeve"], ["left_pants_leg", "right_pants_leg"], ["hat", ""]]:
		var row: Array = []
		for p in pair:
			if p == "":
				row.append(null)
			elif p == "cape":
				row.append(OptionsSub.na(Res.tr_key("options.modelPart.cape", "Cape") + ": " + Res.tr_key("options.off", "OFF"), "Capes come from Minecraft accounts; Recraft has none to show"))
			else:
				var key: String = "skin_" + str(p)
				row.append(McW.on_off(Res.tr_key("options.modelPart." + p, p.replace("_", " ").capitalize()), bool(Settings.get_v(key)), func(v):
					Settings.set_v(key, v)
					reapply.call()))
		rows.append(row)
	return _sub_screen(Res.tr_key("options.skinCustomisation.title", "Skin Customization"), rows)


func _chat() -> Control:
	var T := func(k, f): return Res.tr_key(k, f)
	var na := "Not implemented in Recraft yet"
	var vis := OptionsSub.cyc(T.call("options.chat.visibility", "Chat"), "chat_visibility", ["full", "system", "hidden"],
		[T.call("options.chat.visibility.full", "Shown"), T.call("options.chat.visibility.system", "Commands Only"), T.call("options.chat.visibility.hidden", "Hidden")])
	var pct := func(label: String) -> Callable: return func(v): return label + ": %d%%" % int(roundf(v * 100.0))
	var px := func(label: String, mul: float, add: float) -> Callable: return func(v): return label + ": %dpx" % int(floorf(v * mul + add))
	var rows := [
		[vis, OptionsSub.na(T.call("options.chat.color", "Colors"), na)],
		[OptionsSub.na(T.call("options.chat.links", "Web Links"), na), OptionsSub.na(T.call("options.chat.links.prompt", "Prompt on Links"), na)],
		[OptionsSub.sld("chat_opacity", 0.0, 1.0, 0.01, pct.call(T.call("options.chat.opacity", "Chat Text Opacity"))),
			OptionsSub.sld("text_bg_opacity", 0.0, 1.0, 0.01, pct.call(T.call("options.accessibility.text_background_opacity", "Text Background Opacity")))],
		[OptionsSub.sld("chat_scale", 0.0, 1.0, 0.01, pct.call(T.call("options.chat.scale", "Chat Text Size"))),
			OptionsSub.sld("chat_line_spacing", 0.0, 1.0, 0.01, pct.call(T.call("options.chat.line_spacing", "Line Spacing")))],
		[OptionsSub.na(T.call("options.chat.delay_none", "Chat Delay: None"), na),
			OptionsSub.sld("chat_width", 0.0, 1.0, 0.01, px.call(T.call("options.chat.width", "Width"), 280.0, 40.0))],
		[OptionsSub.sld("chat_height_focused", 0.0, 1.0, 0.01, px.call(T.call("options.chat.height.focused", "Focused Height"), 160.0, 20.0)),
			OptionsSub.sld("chat_height_unfocused", 0.0, 1.0, 0.01, px.call(T.call("options.chat.height.unfocused", "Unfocused Height"), 160.0, 20.0))],
		[OptionsSub.na(T.call("options.autoSuggestCommands", "Command Suggestions"), na), OptionsSub.na(T.call("options.hideMatchedNames", "Hide Matched Names"), na)],
		[OptionsSub.na(T.call("options.reducedDebugInfo", "Reduced Debug Info"), na), OptionsSub.na(T.call("options.onlyShowSecureChat", "Only Show Secure Chat"), "No chat signing in Recraft")],
	]
	return _sub_screen(T.call("options.chat.title", "Chat Settings"), rows)

func _online_screen() -> Control:
	var why := "Microsoft account / Realms / Friends services are not available in Recraft"
	var rows := [
		["header", Res.tr_key("options.online.friends.header", "Friends List")],
		[OptionsSub.na(Res.tr_key("options.allowFriendRequests", "Allow Requests"), why), OptionsSub.na(Res.tr_key("options.sharePresence", "Visibility"), why)],
		["header", Res.tr_key("options.online.realms.header", "Realms")],
		[OptionsSub.na(Res.tr_key("options.realmsNotifications", "Realms News & Invites"), why), null],
		["header", Res.tr_key("options.online.servers.header", "Servers")],
		[OptionsSub.na(Res.tr_key("options.allowServerListing", "Allow Server Listings"), why), OptionsSub.na(Res.tr_key("options.online.xboxSettings", "Xbox Settings..."), why)],
	]
	return _sub_screen(Res.tr_key("options.online.title", "Online Options"), rows)


func _info_screen(title: String, lines: Array) -> Control:
	var rows: Array = []
	for l in lines:
		var lab := McW.text(str(l), McW.GRAY)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rows.append(["big", lab])
	return _sub_screen(title, rows)


func _telemetry() -> Control:
	return _info_screen(Res.tr_key("telemetry_info.screen.title", "Telemetry Data Collection"), [
		"Recraft collects no telemetry. Nothing is sent anywhere.",
		"Minecraft's telemetry settings apply to the official game only."])


func _credits() -> Control:
	return _info_screen(Res.tr_key("credits_and_attribution.screen.title", "Credits and Attribution"), [
		"Designed by Claude Code under bayanalan on GitHub",
		"Logo designed by textcraft.net",
		"Prompt design by ChatGPT",
		"AI has been used to code this project in its entirety. If you have strong feelings about the matter, you don't have to use it at all. This is purely a proof of concept to show that if Claude Code can generate a feature-complete Minecraft: Java Edition clone in a week, the hundreds of Mojang devs could rewrite Minecraft in GDScript or Rust just as easily. Xbox and Microsoft just don't pay them enough or care enough to go through with it.",
		"This project was inspired by Horizon, the Rust Minecraft remake. It ran so well that I wanted to try it in my favourite game engine, Godot. And it worked great, even beating vanilla Minecraft in frame rate and frame time.",
		"Mojang is lazy, and this just proves it more. It would be cool to see this become a trend of people recreating Minecraft to bully Mojang into fixing their own slopfest of technical debt that is Minecraft: Java Edition and Bedrock Edition.",
		"I do not take credit for any of this code, as it is 100% AI. Please do not harass me or anyone involved. Once again, this is just a proof of concept, and I do not massively support AI usage as a whole.",
		"Recraft is not an official Minecraft product.",
		"Game assets and text are read at runtime from your own Minecraft %s installation." % Res.version,
		"Minecraft is a trademark of Mojang Synergies AB / Microsoft."])


# ---------------------------------------------------------------- Language / Resource packs

func _language() -> Control:
	return load("res://scripts/ui/language_screen.gd").new()


func _packs() -> Control:
	return load("res://scripts/ui/pack_screen.gd").new()
