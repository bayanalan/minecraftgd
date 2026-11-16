## Settings (autoload) — persisted per-user options in user://settings.cfg with validation, schema
## migration, presets and real engine application (window mode, vsync, fps caps, FOV, render scale, MSAA...).
## Contract: get_v(key), set_v(key, value, apply := true), apply_all(), save(); signal changed(key).
## Invariants: every key has a typed default and a valid range; invalid stored values fall back to defaults.
extends Node

signal changed(key: String)

const PATH := "user://settings.cfg"
const SCHEMA := 4

# key: [default, min/choices, max]
const SPEC := {
	"preset": ["balanced", ["low", "fast", "balanced", "fancy", "ultra", "custom"]],
	"display_mode": ["windowed", ["windowed", "borderless", "fullscreen"]],
	"vsync": ["on", ["off", "on", "adaptive"]],
	"max_fps": [120, [30, 60, 90, 120, 144, 240, 0]],
	"show_fps": ["off", ["off", "fps", "fps_lows"]],
	"terrain_renderer": ["rd", ["rd", "godot"]],   # takes effect when a world is loaded
	"background_fps": [30, [15, 30, 60]],
	"render_distance": [16, 2, 32],   # user default: 16 render / 12 simulation
	"simulation_distance": [12, 5, 32],   # wiki: Options (minimum 5, values as Render Distance)
	"lod_distance": [0, 0, 64],
	"fov": [70.0, 30.0, 110.0],
	"graphics": ["fancy", ["fast", "fancy", "fabulous"]],
	"smooth_lighting": ["high", ["off", "low", "high"]],
	"shadows": ["off", ["off", "low", "medium", "high"]],
	"clouds": ["fancy", ["off", "fast", "fancy"]],
	"cloud_distance": [128, 2, 128],   # Java Cloud Distance (chunks)
	"menu_blur": [5, 0, 10],   # Java Menu Background Blurriness
	"panorama_speed": [1.0, 0.0, 2.0],   # Java Panorama Scroll Speed
	"chat_visibility": ["full", ["full", "system", "hidden"]],   # Java Chat: Shown / Commands Only / Hidden
	"chat_opacity": [1.0, 0.0, 1.0],          # Chat Text Opacity
	"text_bg_opacity": [0.5, 0.0, 1.0],       # Text Background Opacity
	"chat_scale": [1.0, 0.0, 1.0],            # Chat Text Size
	"chat_width": [1.0, 0.0, 1.0],            # Width: floor(w * 280 + 40) px
	"chat_height_focused": [1.0, 0.0, 1.0],   # Focused Height: floor(h * 160 + 20) px
	"chat_height_unfocused": [0.4375, 0.0, 1.0],
	"chat_line_spacing": [0.0, 0.0, 1.0],
	"skin_hat": [true], "skin_jacket": [true], "skin_left_sleeve": [true], "skin_right_sleeve": [true],
	"skin_left_pants_leg": [true], "skin_right_pants_leg": [true],   # Java Skin Customization model parts
	"attack_indicator": ["crosshair", ["off", "crosshair", "hotbar"]],
	"particles": ["all", ["minimal", "decreased", "all"]],
	"entity_distance": [100, 50, 500],
	"biome_blend": [2, 0, 7],
	"texture_filter": ["nearest", ["nearest", "bilinear", "trilinear"]],
	"anisotropy": [4, [0, 2, 4, 8, 16]],
	"antialiasing": ["off", ["off", "fxaa", "taa", "msaa2", "msaa4", "msaa8"]],
	"mipmaps": [true],
	"fog": ["vanilla", ["off", "vanilla", "enhanced"]],
	"view_bobbing": [true],
	"distortion": [1.0, 0.0, 1.0],
	"vignette": [true],
	"weather_visuals": ["full", ["off", "reduced", "full"]],
	"chunk_upload": ["auto", ["auto", "low", "normal", "high"]],
	"gui_scale": [0, 0, 16],   # 0 = Auto
	"debug_metrics": [false],
	# Advanced video (Recraft optimizations, each can be switched off)
	"adv_threads": [0, 0, 16],          # chunk builder threads, 0 = auto
	"adv_pin_main": [true],             # main thread on the fastest core cluster
	"adv_leaf_cull": [false],           # skip leaf faces buried two leaves deep (off: vanilla, every leaf face)
	"adv_merge_faces": [true],          # greedy merging of identical faces (off = one quad per face, like Java)
	"adv_occlusion": [true],            # skip sections hidden behind terrain (visibility graph)
	"adv_dir_cull": [true],             # skip face directions turned away from the camera
	"adv_ctm": [false],                 # QoL: connected glass textures
	"adv_fullbright": [false],          # QoL: full brightness (night-vision lightmap)
	"adv_zoom": [true],                 # QoL: hold C to zoom
	"adv_coords": [false],              # QoL: coordinates on the HUD
	"render_scale": [100, 50, 100],
	"dynamic_resolution": [false],
	"brightness": [0.5, 0.0, 1.0],
	"sensitivity": [0.5, 0.0, 1.0],
	"invert_y": [false],
	"toggle_sneak": [false],
	"toggle_sprint": [false],
	"double_tap_sprint": [true],
	"auto_jump": [false],
	"subtitles": [false],
	"vol_master": [1.0, 0.0, 1.0], "vol_music": [0.6, 0.0, 1.0], "vol_jukebox": [1.0, 0.0, 1.0],
	"vol_weather": [1.0, 0.0, 1.0], "vol_blocks": [1.0, 0.0, 1.0], "vol_hostile": [1.0, 0.0, 1.0],
	"vol_neutral": [1.0, 0.0, 1.0], "vol_players": [1.0, 0.0, 1.0], "vol_ambient": [1.0, 0.0, 1.0],
	"vol_voice": [1.0, 0.0, 1.0], "vol_ui": [1.0, 0.0, 1.0],
	"pause_on_lost_focus": [true],
	"language": ["en_us"],
	"high_contrast": [false],
	"text_shadow": [true],
	"damage_tilt": [1.0, 0.0, 1.0],
	"fov_effects": [1.0, 0.0, 1.0],         # wiki: Options (FOV Effects 100 %)
	"darkness_pulsing": [1.0, 0.0, 1.0],    # wiki: Options (Darkness Pulsing 100 %)
	"glint_speed": [0.5, 0.0, 1.0],         # wiki: Options (Glint Speed 50 %)
	"glint_strength": [0.75, 0.0, 1.0],     # wiki: Options (Glint Strength 75 %)
	"hide_lightning": [false],
	"main_hand": ["right", ["right", "left"]],
	"skin_path": [""],
	"player_name": ["Player"],
	"resource_packs": [[]],     # enabled pack names in user://resourcepacks, highest priority first
	"slim_arms": [false],
	"keybinds": [{}],
	"last_asset_version": [""],
	"placeholder_mode": [false],
	"custom_mc_dir": [""],
	"memory_cap_mb": [2048, 512, 16384],
}

const PRESETS := {
	"low": {"render_distance": 6, "graphics": "fast", "smooth_lighting": "off", "clouds": "off", "particles": "minimal", "biome_blend": 0, "antialiasing": "off", "anisotropy": 0, "shadows": "off", "render_scale": 75, "fog": "vanilla"},
	"fast": {"render_distance": 8, "graphics": "fast", "smooth_lighting": "low", "clouds": "fast", "particles": "decreased", "biome_blend": 1, "antialiasing": "off", "anisotropy": 2, "shadows": "off", "render_scale": 100},
	"balanced": {"render_distance": 12, "graphics": "fancy", "smooth_lighting": "high", "clouds": "fast", "particles": "all", "biome_blend": 2, "antialiasing": "off", "anisotropy": 4, "shadows": "off", "render_scale": 100},
	"fancy": {"render_distance": 16, "graphics": "fancy", "smooth_lighting": "high", "clouds": "fancy", "particles": "all", "biome_blend": 3, "antialiasing": "fxaa", "anisotropy": 8, "shadows": "off", "render_scale": 100},
	"ultra": {"render_distance": 24, "graphics": "fabulous", "smooth_lighting": "high", "clouds": "fancy", "particles": "all", "biome_blend": 5, "antialiasing": "taa", "anisotropy": 16, "shadows": "medium", "render_scale": 100},
}

var values: Dictionary = {}
var _applying_preset := false


var fps_counter: FpsCounter


func _ready() -> void:
	load_settings()
	fps_counter = FpsCounter.new()
	add_child(fps_counter)
	apply_all()
	get_window().focus_entered.connect(_on_focus.bind(true))
	get_window().focus_exited.connect(_on_focus.bind(false))


var _focused := true
## No world loaded (title screen, world list, options from the title): Java caps menus at 60 FPS
## (Minecraft.getFramerateLimit) - here also with V-Sync on, so the menus do not burn power at hundreds of FPS.
var in_menu := true


func _on_focus(focused: bool) -> void:
	_focused = focused
	_apply_rate()
	if focused and DisplayServer.get_name() != "headless" and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		# back from alt-tab while still minimised: restore the chosen mode
		apply_key("display_mode")


func set_in_menu(v: bool) -> void:
	if in_menu == v:
		return
	in_menu = v
	_apply_rate()


func _apply_rate() -> void:
	var lim := int(values["max_fps"]) if _focused else int(values["background_fps"])
	if in_menu:
		lim = 60 if lim == 0 else mini(lim, 60)
	Engine.max_fps = lim
	# Java caps menus by frame rate only (Minecraft.getFramerateLimit), never by V-Sync. A present-mode change rebuilds
	# the window's swap chain: it ran on every focus change / menu (V-Sync forced on in menus), and a rebuild while
	# alt-tab activates the window sometimes kept the game from coming back. Set only when it differs.
	var want := DisplayServer.VSYNC_ENABLED
	match str(values["vsync"]):
		"off": want = DisplayServer.VSYNC_DISABLED
		"adaptive": want = DisplayServer.VSYNC_ADAPTIVE
	if DisplayServer.get_name() != "headless" and DisplayServer.window_get_vsync_mode() != want:
		DisplayServer.window_set_vsync_mode(want)


func default_of(key: String):
	var d = SPEC[key][0]
	return d.duplicate() if d is Dictionary else d


func validate(key: String, v):
	if not SPEC.has(key):
		return null
	var spec: Array = SPEC[key]
	var d = spec[0]
	if spec.size() >= 2 and spec[1] is Array:
		return v if (spec[1] as Array).has(v) else d
	if spec.size() >= 3:
		if d is float:
			return clampf(float(v), float(spec[1]), float(spec[2])) if (v is float or v is int) else d
		if d is int:
			return clampi(int(v), int(spec[1]), int(spec[2])) if (v is float or v is int) else d
	if typeof(v) == typeof(d):
		return v
	if d is float and v is int:
		return float(v)
	return d


func load_settings() -> void:
	for k in SPEC:
		values[k] = default_of(k)
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var schema := int(cf.get_value("meta", "schema", 1))
	for k in SPEC:
		if cf.has_section_key("options", k):
			values[k] = validate(k, cf.get_value("options", k))
	if schema < 2 and values["max_fps"] == 260:
		values["max_fps"] = 0
	if schema < 3:
		values["adv_leaf_cull"] = false   # leaf culling became opt-in (vanilla: every face between leaves is drawn)
	if schema < 4:
		# the defaults became 16 render / 12 simulation (2026-11-15): settings saved with the old ones move once
		values["render_distance"] = 16
		values["simulation_distance"] = 12


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "schema", SCHEMA)
	for k in values:
		cf.set_value("options", k, values[k])
	cf.save(PATH)


func get_v(key: String):
	return values.get(key, default_of(key) if SPEC.has(key) else null)


## Java KeyboardHandler: the fullscreen key (F11) toggles fullscreen on every screen (title, menus, in game).
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and InputMap.has_action("fullscreen") and event.is_action_pressed("fullscreen"):
		set_v("display_mode", "windowed" if str(values["display_mode"]) != "windowed" else "borderless")
		save()
		get_viewport().set_input_as_handled()


func set_v(key: String, v, apply := true) -> void:
	var nv = validate(key, v)
	if nv == null:
		return
	values[key] = nv
	if key == "preset" and nv != "custom":
		_applying_preset = true
		var p: Dictionary = PRESETS.get(nv, {})
		for k in p:
			values[k] = p[k]
			apply_key(k)   # presets take effect immediately (they were only stored before)
			changed.emit(k)
		_applying_preset = false
	elif PRESETS["balanced"].has(key) and not _applying_preset:
		values["preset"] = "custom"
	if apply:
		apply_key(key)
	changed.emit(key)


func apply_all() -> void:
	for k in ["display_mode", "vsync", "max_fps", "show_fps", "antialiasing", "render_scale", "brightness", "texture_filter", "anisotropy"]:
		apply_key(k)


func apply_key(key: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	match key:
		"display_mode":
			match str(values["display_mode"]):
				"windowed": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
				"borderless": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
				# full screen without exclusive mode: alt-tab back into an exclusive D3D12 window sometimes never reactivated it
				# (no FPS difference measured between the two)
				"fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		"vsync", "max_fps":
			_apply_rate()
		"show_fps":
			if fps_counter != null:
				fps_counter.set_mode(str(values["show_fps"]))
		"antialiasing":
			var vp := get_viewport()
			var aa := str(values["antialiasing"])
			vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == "fxaa" else Viewport.SCREEN_SPACE_AA_DISABLED
			vp.use_taa = aa == "taa"
			vp.msaa_3d = Viewport.MSAA_2X if aa == "msaa2" else (Viewport.MSAA_4X if aa == "msaa4" else (Viewport.MSAA_8X if aa == "msaa8" else Viewport.MSAA_DISABLED))
		"render_scale", "dynamic_resolution":
			var vp2 := get_viewport()
			vp2.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
			vp2.scaling_3d_scale = float(values["render_scale"]) / 100.0
		"brightness":
			ShaderGlobals.put("gamma_boost", float(values["brightness"]))
		"texture_filter", "anisotropy", "mipmaps":
			var vp3 := get_viewport()
			vp3.anisotropic_filtering_level = [Viewport.ANISOTROPY_DISABLED, Viewport.ANISOTROPY_2X, Viewport.ANISOTROPY_4X, Viewport.ANISOTROPY_8X, Viewport.ANISOTROPY_16X][[0, 2, 4, 8, 16].find(int(values["anisotropy"]))]


## Effective GUI scale (auto picks the largest scale keeping a 320x240 virtual area).
## Java Window.calculateScale: Auto = the largest integer scale that keeps a 320 x 240 GUI; an explicit scale is
## clamped to that maximum (UI spec 2.3).
func gui_scale() -> int:
	var sz := DisplayServer.window_get_size() if DisplayServer.get_name() != "headless" else Vector2i(1280, 720)
	var mx := max_gui_scale(sz)
	var s := int(values["gui_scale"])
	return mx if s <= 0 else clampi(s, 1, mx)


static func max_gui_scale(sz: Vector2i) -> int:
	return maxi(1, mini(floori(float(sz.x) / 320.0), floori(float(sz.y) / 240.0)))
