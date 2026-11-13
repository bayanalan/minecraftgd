## WorldManager — in-game root: owns save, generator, chunk streaming, player, entities, environment,
## HUD/screens and the fixed 20 TPS simulation (render-interpolated camera, floating origin).
## Contract: created by Bootstrap with `folder`; save_and_close() persists everything atomically.
## Invariants: all world edits go through set_block() (marks meshes/light/save dirty); game logic never
## depends on frame rate; visual coordinates = world - origin (origin chunk-aligned, rebased > 512 blocks).
extends Node3D

const TICK := 0.05
const REBASE := 512

var app
var folder := ""
var save: SaveManager
var gen: WorldGenerator
var cm: ChunkManager
var biomes: BiomeRegistry
var player: Player
var entities: EntityManager
var level: Dictionary = {}
var camera: Camera3D
var env: Environment
var sky_mat: ShaderMaterial
var hud
var outline: MeshInstance3D
var crack: MeshInstance3D
var crack_mat: ShaderMaterial
var _crack_meshes: Dictionary = {}   # block state -> crack decal mesh
var crack_textures: Array = []
var screen = null           # open GUI screen (inventory, pause...)
var paused := false
var game_time := 0          # total ticks
var day_time := 1000        # 0..24000 cycle
var tick_accum := 0.0
var tick_ms := 0.0
var autosave_timer := 0.0
var difficulty := 2
var hardcore := false
var gamerules: Dictionary = {}
var rain := 0.0
var thunder := 0.0
var weather_timer := 12000
var raining := false
var thundering := false
var spawn_ready := false
var target: Dictionary = {}
var mining_pos := Vector3i(0, -999, 0)
var mining_progress := 0.0
var mining_cooldown := 0
var _attack_on_entity := false   # the held attack hit an entity: no block mining until the button is released
var use_cooldown := 0
var auto_use := 0     # probes: ticks to keep the use button "held"
var third_person := 0
var hud_hidden := false
var show_debug := false
var mouse_captured := false
var fps_samples := PackedFloat32Array()
var last_tap_forward := 0
var rng := RandomNumberGenerator.new()
var closing := false
var loading_overlay: Control
var commands: CommandParser
var dimension := "overworld"     # overworld | the_nether | the_end (only the player's dimension is loaded)
var dim_type: Dictionary = {}
var portal_time := 0
var portal_cooldown := 0
var changing_dim := false
var _arrival: Dictionary = {}       # pending arrival after a dimension change: {kind, pos, axis}
var dragon_fight: DragonFight
var advancements: Advancements
var _inv_dirty := false
var _auto_input := false
var hand_swing := 0          # Java swingTime countdown (6 ticks), drives the first-person swing
var player_model: Node3D
var _pm_limb := 0.0


## In-game screens are compiled on a background thread when the world starts: the first load() of a screen script
## on the main thread cost 40+ ms (measured: inventory_screen.gd 41.5 ms at the first E press).
const PRELOAD_SCREENS := ["inventory_screen", "creative_screen", "container_screen", "crafting_screen", "workstation_screen", "pause_menu",
	"options_menu", "chat_screen", "death_screen", "sign_screen", "book_screen", "beacon_screen", "trade_screen",
	"horse_screen", "command_block_screen"]


func _preload_screens() -> void:
	for nm in PRELOAD_SCREENS:
		var path := "res://scripts/ui/%s.gd" % nm
		if not ResourceLoader.has_cached(path):
			ResourceLoader.load_threaded_request(path, "", true)


## Item icons (software-rasterised per item on first draw: a creative inventory page cost ~25 ms the first time)
## are built in the background after spawn, under 0.8 ms per frame, while no screen is open.
var _icon_warm_i := 0


func _warm_icons() -> void:
	if screen != null or autoplay.has("nowarm") or DisplayServer.get_name() == "headless":
		return
	var n: int = Res.items.names.size()
	var t := Time.get_ticks_usec()
	while _icon_warm_i < n and Time.get_ticks_usec() - t < 800:
		ItemIcons.icon(_icon_warm_i)
		_icon_warm_i += 1
	if _icon_warm_i >= n:
		_icon_warm_i = -1


## The inventory key's screen: Java CreativeModeInventoryScreen in Creative, the survival inventory otherwise.
func inventory_screen() -> Control:
	if player.is_creative():
		return load("res://scripts/ui/creative_screen.gd").new()
	return load("res://scripts/ui/inventory_screen.gd").new()


## Inventory player preview rendered once while the world loads (InventoryPreview).
func _warm_ui() -> void:
	if hud != null and is_inside_tree():
		InventoryPreview.warm(hud)


func _ready() -> void:
	ChunkManager._dc_mutex.lock()
	ChunkManager.dim_cache.clear()   # chunks kept from another world's dimensions never carry over
	ChunkManager._dc_mutex.unlock()
	if ChunkManager.thread_prio and Native.inst.has_method("set_thread_priority"):
		Native.inst.set_thread_priority(1)   # main thread above normal (see ChunkManager.thread_prio)
	if Native.inst != null and Native.inst.has_method("no_power_throttling") and not OS.get_cmdline_user_args().has("--ecoqos"):
		print("[power] throttling opt-out result %d" % int(Native.inst.no_power_throttling(1)[0]))   # no EcoQoS bursts on efficiency cores when the window loses focus
	ChunkManager.pin_thread(true)   # main thread: its own core cluster (see ChunkManager.pin_thread)
	Settings.set_in_menu(false)   # in a world: the player's V-Sync / framerate settings (menus: 60 FPS)
	if DisplayServer.get_name() != "headless":
		_preload_screens()
		_warm_ui.call_deferred()
	rng.randomize()
	Controls.setup()
	BlockUpdates.reset()
	Beacons.clear()
	Signs.clear()
	BERender.setup()
	Maps.clear()
	Crafting.load_all()
	save = SaveManager.new()
	# private copy: chunk loads (workers) and saves (saver thread) never share refcounts with the main thread's tables
	save.blocks = Res.blocks.thread_copy()
	if not save.open(folder):
		push_error("Cannot open world " + folder)
		app.show_title()
		return
	level = save.level
	Net.attach(self)
	biomes = BiomeRegistry.new()
	biomes.build()
	dimension = str(level.get("dimension", "overworld"))
	save.set_dimension(dimension)
	gen = _create_gen(dimension)
	_load_dim_type(dimension)
	difficulty = int(level.get("difficulty", 2))
	hardcore = bool(level.get("hardcore", false))
	gamerules = GameRules.defaults()
	gamerules.merge(level.get("gamerules", {}), true)
	game_time = int(level.get("game_time", 0))
	day_time = int(level.get("day_time", 1000))
	raining = bool(level.get("raining", false))
	thundering = bool(level.get("thundering", false))
	weather_timer = int(level.get("weather_timer", 12000))
	_setup_environment()
	camera = Camera3D.new()
	camera.fov = float(Settings.get_v("fov"))
	camera.near = 0.05
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	_setup_outline()
	_make_chunk_manager()
	entities = EntityManager.new()
	entities.world = self
	add_child(entities)
	player = Player.new()
	commands = CommandParser.new()
	commands.world = self
	if level.get("player") is Dictionary and not (level["player"] as Dictionary).is_empty():
		player.from_dict(level["player"])
		_begin_preload()   # the world shows once the chunks around the saved position are visible
	else:
		player.mode = int(level.get("game_mode", 0)) as Player.Mode
		var sp := _find_spawn_xz()
		if autoplay.has("at"):
			var at_parts: PackedStringArray = str(autoplay["at"]).split(",")
			sp = Vector2i(int(at_parts[0]), int(at_parts[1]))
		if autoplay.has("atbiome") and gen.has_method("find_biome"):   # --atbiome=name: spawn in the nearest such biome
			var fb: Vector3i = gen.find_biome(biomes.id(str(autoplay["atbiome"])), 0, 64, 0, 4096, 64)
			print("[atbiome] %s at %s" % [str(autoplay["atbiome"]), str(fb)])
			if fb.y > -999999:
				sp = Vector2i(fb.x, fb.z)
		if level.get("net_client", false) and level.get("spawn") is Array:
			sp = Vector2i(int(level["spawn"][0]), int(level["spawn"][2]))
		player.pos = Vector3(sp.x + 0.5, 320, sp.y + 0.5)
		player.prev_pos = player.pos
		level["spawn"] = [sp.x, 64, sp.y]
		if bool(level.get("bonus_chest", false)):
			level["bonus_pending"] = true
	_update_origin(true)
	hud = load("res://scripts/ui/hud.gd").new()
	hud.world = self
	add_child(hud)
	var vm := ViewModel.new()
	vm.world = self
	if autoplay.has("nohand"):   # experiment: no first-person hand
		vm.world = null
	add_child(vm)
	var ps := Particles.new()
	ps.world = self
	add_child(ps)
	weather_fx = WeatherFX.new()
	weather_fx.world = self
	add_child(weather_fx)
	Settings.changed.connect(_on_setting)
	_apply_dimension_env()
	dragon_fight = DragonFight.new(self)
	advancements = Advancements.new(self)
	player.inventory.changed.connect(func(): _inv_dirty = true)
	_capture_mouse(true)
	Audio.set_music_context("creative" if player.mode == Player.Mode.CREATIVE else "game")


## Generator for a dimension: the Overworld uses the world's chosen generator; Nether/End use the data-driven
## 26.3 pipeline (vanilla assets) or the original placeholder dimension generator.
func _create_gen(dim: String) -> WorldGenerator:
	var gid := str(level.get("generator_id", "approx_original"))
	var gs: Dictionary = (level.get("generator_settings", {}) as Dictionary).duplicate()
	if dim != "overworld":
		gs["dimension"] = dim
		gid = "java_26_3" if Res.mode == "vanilla" else "approx_dims"
	var g := WorldGenerator.create(gid)
	g.generator_id = gid
	g.setup(int(level.get("seed", 0)), Res.blocks, biomes, gs)
	return g


func _load_dim_type(dim: String) -> void:
	var j = Res.read_json("data/minecraft/dimension_type/%s.json" % dim) if Res.mode == "vanilla" else null
	if j is Dictionary:
		dim_type = j
	else:
		dim_type = {"has_skylight": dim != "the_nether", "ambient_light": {"the_nether": 0.1, "the_end": 0.25}.get(dim, 0.0), "coordinate_scale": 8.0 if dim == "the_nether" else 1.0}


func dim_attr(key: String, default = null):
	var a: Dictionary = dim_type.get("attributes", {}) if dim_type.get("attributes") is Dictionary else {}
	return a.get(key, default)


var _trd: TerrainRD = null


## RenderingDevice terrain renderer (TerrainRD): Video setting "terrain_renderer", needs the native library (MSAA is supported:
## it draws into the multisampled buffers); autoplay --tr=0 forces Godot meshes.
func _trd_wanted() -> bool:
	if DisplayServer.get_name() == "headless" or not (Native.ok and Native.inst != null and Native.inst.has_method("tr_cull_all")):
		return false
	if autoplay.has("tr") and str(autoplay["tr"]) == "0":
		return false
	return str(Settings.get_v("terrain_renderer")) == "rd"


## Compositor effects in drawing order: TerrainRD opaque + cutout, SkyRD sky (behind everything drawn so far),
## TerrainRD translucent, SkyRD clouds.
func _install_compositor() -> void:
	var fx: Array = []
	if _trd != null:
		_trd.sky_rd = sky_rd   # sky and clouds share TerrainRD's render passes
		fx.append(_trd.opaque_effect())
		if not _trd.merged:
			fx.append(_trd.translucent_effect())
	elif sky_rd != null:
		fx.append(sky_rd.sky_effect())
		fx.append(sky_rd.clouds_effect())
	if fx.is_empty():
		camera.compositor = null
		return
	var comp := Compositor.new()
	comp.compositor_effects = fx
	camera.compositor = comp


func _make_chunk_manager() -> void:
	cm = ChunkManager.new()
	cm.dim_name = dimension   # adopts this dimension's chunks kept in memory (ChunkManager.dim_cache)
	Collision.fast_cm = cm
	Collision.fast_world = self
	cm.setup(Res.blocks, biomes, gen, get_world_3d().scenario)
	cm.has_skylight = bool(dim_type.get("has_skylight", true)) and dimension != "the_nether"
	cm.set_radius(1)   # spawn/arrival area first (3x3 chunks); full render distance once the player is placed
	cm.biome_blend = int(Settings.get_v("biome_blend"))
	if _trd == null and _trd_wanted():
		_trd = TerrainRD.new(self)
		_trd.debug_flags = int(autoplay.get("trhide", "0"))
		_trd.merged = str(autoplay.get("trmerge", "1")) != "0"
	_install_compositor()
	if _trd != null:
		_trd.free_all()
		cm.trd = _trd
		cm._ovl_map = TerrainRD.overlay_map()
	_apply_advanced()   # Advanced video settings (worker count, mesher options, culler flags)
	cm.load_chunk_fn = save.load_chunk
	cm.save_chunk_fn = save.save_chunk
	if Net.is_client():
		cm.load_chunk_fn = Net.client_load_chunk   # host supplies modified chunks; pristine ones generate locally
		cm.save_chunk_fn = Callable()
	cm.chunk_unloading.connect(_on_chunk_unloading)
	cm.chunk_loaded.connect(_on_chunk_loaded)


## Travel to another dimension: store + unload everything, rebuild generator/streaming, then resolve the arrival
## (portal link/creation, End platform, or respawn point) once the destination chunks are ready.
func change_dimension(dim: String, arrival: Dictionary) -> void:
	if changing_dim or closing:
		return
	changing_dim = true
	# keep the decorated chunks around the player in memory for the way back (unload_all below stores their entities
	# in them and saves the modified ones)
	var keep := {}
	var pc := Vector2i(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4)
	for kc in cm.chunks:
		var cc: Chunk = cm.chunks[kc]
		if cc.state >= Chunk.DECORATED and maxi(absi(cc.cx - pc.x), absi(cc.cz - pc.y)) <= 10:
			keep[kc] = cc
	cm.unload_all()
	ChunkManager._dc_mutex.lock()
	ChunkManager.dim_cache[dimension] = keep
	ChunkManager._dc_mutex.unlock()
	entities.clear_all()
	save.flush()
	cm.shutdown()
	var from_dim := dimension
	dimension = dim
	level["dimension"] = dim
	if advancements != null:
		advancements.trigger("changed_dimension", {"from": from_dim, "to": dim})
	save.set_dimension(dim)
	gen = _create_gen(dim)
	_load_dim_type(dim)
	_make_chunk_manager()
	_arrival = arrival
	var p: Vector3 = arrival.get("pos", Vector3(0, 100, 0))
	player.pos = p
	player.prev_pos = p
	player.vel = Vector3.ZERO
	spawn_ready = false
	_spawn_placed = false
	portal_time = 0
	portal_cooldown = 10
	_update_origin(true)
	_apply_dimension_env()
	Audio.set_music_context({"the_nether": "nether", "the_end": "end"}.get(dim, "creative" if player.mode == Player.Mode.CREATIVE else "game"))
	changing_dim = false


func _apply_dimension_env() -> void:
	var mode := {"the_nether": 1, "the_end": 2}.get(dimension, 0)
	sky_mat.set_shader_parameter("mode", mode)
	ShaderGlobals.put("ambient_light", float(dim_type.get("ambient_light", 0.0)))
	# dimension type cardinal_light "nether" (Java Lighting NETHER entry): entities' second diffuse light points down
	ShaderGlobals.put("mc_nether_light", 1.0 if str(dim_type.get("cardinal_light", "default")) == "nether" else 0.0)
	sky_state.setup(dim_type)
	_apply_fog_distance()

func gamerule(name: String, default = null):
	return gamerules.get(name, default)


var sky_state := SkyState.new()
var sky_stars: SkyStars
var sky_rd: SkyRD
var _moon_tex: Dictionary = {}    # 26.3 moon phase name -> texture (textures/environment/celestial/moon/<phase>.png)
var _moon_shown := ""
var _fog_env := Vector2(1e6, 1e6)   # environmental fog start / end (dimension attributes; water / lava override)
var _fog_rd := Vector2(230.0, 256.0)  # render-distance fog start / end


func _setup_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	# 26.3: textures/environment/celestial/sun.png and one texture per moon phase
	var sun := Res.load_image("environment/celestial/sun") if Res.mode == "vanilla" else null
	if sun != null:
		sky_mat.set_shader_parameter("sun_tex", ImageTexture.create_from_image(sun))
		sky_mat.set_shader_parameter("has_textures", true)
	var end_sky := Res.load_image("environment/end_sky") if Res.mode == "vanilla" else null
	if end_sky != null:
		sky_mat.set_shader_parameter("end_tex", ImageTexture.create_from_image(end_sky))
		sky_mat.set_shader_parameter("has_end_tex", true)
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = false   # vanilla fog is applied by our shaders (shaders/mc_fog.gdshaderinc)
	# sky + clouds drawn by SkyRD inside the frame (no Godot sky pass); the Godot sky shader stays as the fallback
	# (headless / no RenderingDevice, or --skyrd=0)
	if DisplayServer.get_name() != "headless" and RenderingServer.get_rendering_device() != null and str(autoplay.get("skyrd", "1")) != "0":
		sky_rd = SkyRD.new(self)
		if sun != null:
			sky_rd.sun_tex = sky_mat.get_shader_parameter("sun_tex")
		if end_sky != null:
			sky_rd.end_tex = sky_mat.get_shader_parameter("end_tex")
		# no colour clear: SkyRD's full-screen sky writes every pixel nothing else covered (Godot's clear of the
		# 2880x1800 RGBA16F buffer cost ~0.36 ms GPU per frame); --bgkeep=0 restores the clear
		env.background_mode = Environment.BG_KEEP if str(autoplay.get("bgkeep", "1")) != "0" else Environment.BG_COLOR
		env.background_color = Color(0.75, 0.85, 1.0)
	sky_state.setup(dim_type)
	_apply_fog_distance()
	we.environment = env
	add_child(we)
	if sky_rd == null:
		sky_stars = SkyStars.new()
		add_child(sky_stars)


func _moon_texture(phase: String) -> Texture2D:
	if not _moon_tex.has(phase):
		var img := Res.load_image("environment/celestial/moon/" + phase) if Res.mode == "vanilla" else null
		_moon_tex[phase] = ImageTexture.create_from_image(img) if img != null else null
	return _moon_tex[phase]


## Java FogRenderer distances: render-distance fog (cylindrical) renderDistance - clamp(renderDistance / 10, 4, 64) ..
## renderDistance; environmental fog (spherical) from the dimension's fog_start / fog_end attributes (Nether 10 .. 96),
## none in the Overworld. "Enhanced" (our option) starts the render-distance fog at half the distance.
func _apply_fog_distance() -> void:
	var rd := float(Settings.get_v("render_distance")) * 16.0
	var start := rd - clampf(rd / 10.0, 4.0, 64.0)
	if Settings.get_v("fog") == "enhanced":
		start = rd * 0.5
	_fog_rd = Vector2(start, rd)
	_fog_env = Vector2(1e6, 1e6)
	if dim_attr("minecraft:visual/fog_end_distance") != null:
		_fog_env = Vector2(float(dim_attr("minecraft:visual/fog_start_distance", 0.0)), float(dim_attr("minecraft:visual/fog_end_distance", 1e6)))

func _setup_outline() -> void:
	outline = MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0, 0, 0, 0.45)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	outline.material_override = m
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(outline)
	crack = MeshInstance3D.new()
	crack_mat = ShaderMaterial.new()
	crack_mat.shader = load("res://shaders/crumbling.gdshader")
	crack.material_override = crack_mat
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crack.visible = false
	add_child(crack)
	for i in 10:
		var img := Res.load_image("block/destroy_stage_%d" % i) if Res.mode == "vanilla" else null
		crack_textures.append(ImageTexture.create_from_image(img) if img != null else null)


func _find_spawn_xz() -> Vector2i:
	var r := RandomSources.Xoroshiro.from_seed(int(level.get("seed", 0)))
	for i in 200:
		var ring := i * 8
		var x := r.next_int_bound(ring * 2 + 1) - ring
		var z := r.next_int_bound(ring * 2 + 1) - ring
		var h := gen.surface_height(x, z)
		if h > Coords.SEA_LEVEL and h < 200:
			return Vector2i(x, z)
	return Vector2i(0, 0)


var weather_fx: WeatherFX = null


## Java Level.isRainingAt / Biome.getPrecipitationAt: "rain", "snow" or "none" at a position (raining, open to the sky,
## the biome has precipitation; snow below 0.15 height-adjusted temperature).
func weather_at(p: Vector3) -> String:
	if not raining or dimension != "overworld" or rain < 0.2:
		return "none"
	var x := floori(p.x)
	var z := floori(p.z)
	var ch := cm.get_chunk(x >> 4, z >> 4)
	if ch == null or ch.heightmap.is_empty() or floori(p.y) < ch.heightmap[(x & 15) + (z & 15) * 16]:
		return "none"
	var bio := ch.biome_at(x & 15, floori(p.y), z & 15)
	if bio < 0 or biomes.precipitation[bio] == 0:
		return "none"
	var t: float = biomes.temperature[bio]
	if p.y > 80.0:
		t -= (p.y - 80.0) * 0.05 / 40.0
	return "snow" if t < 0.15 else "rain"


func state_at(x: int, y: int, z: int) -> int:
	return cm.get_block(x, y, z)


func column_ready(x: float, z: float) -> bool:
	return cm.is_ready(int(floor(x)), int(floor(z)))


var block_change_log: Dictionary = {}   # perf: "old -> new" counts while ChunkManager.tracing
var _f3_combo := false   # an F3+key combination was used while F3 was held (F3 release then keeps the debug screen)
var prev_gamemode := -1  # Java previousPlayerMode (F3+N, F3+F4)


func set_block(x: int, y: int, z: int, st: int, notify := true) -> int:
	var old := cm.set_block(x, y, z, st)
	if cm.tracing and old >= 0 and old != st:
		var bk := Res.blocks.name_of(old) + " -> " + Res.blocks.name_of(st)
		block_change_log[bk] = int(block_change_log.get(bk, 0)) + 1
	if old >= 0 and old != st and st > 0 and Res.blocks.st_block[st] == BlockUpdates._fire_id() and (old == 0 or Res.blocks.st_block[old] != Res.blocks.st_block[st]):
		BlockUpdates.fire_placed(self, Vector3i(x, y, z))   # FireBlock.onPlace: first tick in 30..39
	if old >= 0 and old != st:
		BERender.on_block_changed(Vector3i(x, y, z), old, st)
		Interaction.chest_unlink(self, Vector3i(x, y, z), old, st)
		Creaking.on_block_changed(self, Vector3i(x, y, z), old)
	if old >= 0 and old != st and Net.active():
		Net.on_local_block(x, y, z, st)
	if old >= 0 and notify and entities != null:
		entities.on_block_changed(Vector3i(x, y, z), old, st)
	if old >= 0 and old != st and not Net.is_client():
		Portals.on_block_changed(self, Vector3i(x, y, z), old, st)
		if notify:
			Redstone.notify_observers(self, Vector3i(x, y, z))
			Redstone.request(self, Vector3i(x, y, z))
			ShapeUpdates.on_changed(self, Vector3i(x, y, z), old, st)   # fences / walls / panes / stairs / gates / paths
	return old


func _update_origin(force := false) -> void:
	var p := player.pos
	var o := cm.origin
	if force or absf(p.x - o.x) > REBASE or absf(p.z - o.z) > REBASE:
		var no := Vector3i(int(floor(p.x / 16.0)) * 16, 0, int(floor(p.z / 16.0)) * 16)
		cm.set_origin(no)


func vis(p: Vector3) -> Vector3:
	return p - Vector3(cm.origin)


# ---------------------------------------------------------------- main loop

## Java GameRenderer.tryTakeScreenshotIfNeeded: a world without icon.png gets one from the rendered world (no GUI)
## once the area around the player has finished meshing; centre square, 64 x 64, written off the main thread.
var _icon_state := 0      # 0 waiting, 1 capturing, 2 done
var _icon_try_ms := 0
var _spawn_ready_ms := 0


func _try_world_icon() -> void:
	if _icon_state != 0 or not spawn_ready or screen != null or Net.is_client() or folder == "" or (not autoplay.is_empty() and not autoplay.has("icon")):
		return
	var now := Time.get_ticks_msec()
	if _spawn_ready_ms == 0:
		_spawn_ready_ms = now
	if now - _spawn_ready_ms < 2000 or now - _icon_try_ms < 1000 or player.dead:
		return
	_icon_try_ms = now
	var p := SaveManager.ROOT.path_join(folder).path_join("icon.png")
	if FileAccess.file_exists(p):
		_icon_state = 2
		return
	if cm.pending_jobs() > 0 and now - _spawn_ready_ms < (2500 if autoplay.has("icon") else 6000):   # far chunks may still stream; the view is complete by then
		return
	_icon_state = 1
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_disable_2d(vp, true)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	RenderingServer.viewport_set_disable_2d(vp, false)
	_icon_state = 2
	if img == null or img.is_empty():
		return
	var sq := mini(img.get_width(), img.get_height())
	var icon := img.get_region(Rect2i((img.get_width() - sq) / 2, (img.get_height() - sq) / 2, sq, sq))
	WorkerThreadPool.add_task(func():
		icon.resize(64, 64, Image.INTERPOLATE_LANCZOS)
		icon.save_png(p))


func _process(delta: float) -> void:
	if closing or cm == null:
		return
	_try_world_icon()
	var t0 := Time.get_ticks_usec()
	if cm.tracing:
		frame_tparts = {}
	_last_delta = delta
	if not paused:
		tick_accum += delta
		var n := 0
		while tick_accum >= TICK and n < 10:
			var tt0 := Time.get_ticks_usec()
			_tick()
			if cm.tracing:
				frame_tparts["tick start (phase 0 + finish)"] = int(frame_tparts.get("tick start (phase 0 + finish)", 0)) + Time.get_ticks_usec() - tt0
			tick_accum -= TICK
			n += 1
		if n >= 10:
			tick_accum = 0.0
		if n == 0:
			_tick_continue(delta)   # spread the rest of the game tick in progress over the frames until the next one
		if not Net.is_client():
			# random-tick handlers of the current pass, spread evenly over the frames left until the next tick
			var th0 := Time.get_ticks_usec()
			BlockUpdates.step_hits(self, int((TICK - tick_accum) / maxf(delta, 0.0005)))
			if cm.tracing:
				frame_tparts["random-tick handlers"] = Time.get_ticks_usec() - th0
	tick_ms = lerpf(tick_ms, (Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	var tr := cm.tracing
	var p0 := Time.get_ticks_usec()
	var alpha := clampf(tick_accum / TICK, 0.0, 1.0)
	_update_camera(alpha)
	if weather_fx != null:
		weather_fx.set_partial(alpha)
	Beacons.render(self)
	Signs.render(self)
	var p1 := Time.get_ticks_usec()
	BERender.update(self)
	var p2 := Time.get_ticks_usec()
	cm.update(player.pos, -camera.global_transform.basis.z)
	var p3 := Time.get_ticks_usec()
	var pt0 := Time.get_ticks_usec()
	_update_target()
	var pt1 := Time.get_ticks_usec()
	_update_sky(alpha)
	if tr:
		frame_tparts["target"] = pt1 - pt0
		frame_tparts["sky"] = Time.get_ticks_usec() - pt1
		var p4 := Time.get_ticks_usec()
		_pf("ticks", p0 - t0)
		_pf("camera+beacons+signs", p1 - p0)
		_pf("berender", p2 - p1)
		_pf("chunk_manager", p3 - p2)
		_pf("target+sky", p4 - p3)
		_pf("process_total", p4 - t0)
		last_parts = [p0 - t0, p1 - p0, p2 - p1, p3 - p2, p4 - p3, p4 - t0]
		if p4 - t0 > 50000:
			print("[stall] process %.0f ms: ticks %.0f, berender %.0f, chunk_manager %.0f (commit %.0f dispatch %.0f rebuild+unload %.0f), target+sky %.0f, autosave_timer %.1f" % [(p4 - t0) / 1000.0, (p0 - t0) / 1000.0, (p2 - p1) / 1000.0, (p3 - p2) / 1000.0, cm.last_commit_us / 1000.0, cm.last_dispatch_us / 1000.0, cm.last_rebuild_us / 1000.0, (p4 - p3) / 1000.0, autosave_timer])
	if not spawn_ready:
		_try_place_spawn()
	elif _icon_warm_i >= 0:
		_warm_icons()
	if not autoplay.is_empty() and not _auto_started:
		_auto_started = true
		_auto_run()
	autosave_timer += delta
	if autosave_timer > 120.0 and bool(level.get("autosave", true)):
		autosave_timer = 0.0
		_begin_autosave()
	if not _autosave_q.is_empty():
		_autosave_step()
	fps_samples.append(delta)
	if fps_samples.size() > 240:
		fps_samples = fps_samples.slice(fps_samples.size() - 240)


var autoplay: Dictionary = {}
var _auto_started := false
var created_us := Time.get_ticks_usec()   # world entry (load test timing origin)


## Render probe: waits for spawn + streaming, captures 5 screenshots and timing stats, then quits.
func _stubstat(sts2: Structures, want: String) -> void:
	var nb := 0
	var nbio := 0
	var lows: Array = []
	for sset2 in sts2.sets:
		for e2 in sset2["entries"]:
			if str(e2["name"]) != want:
				continue
			var cfg2: Dictionary = e2["cfg"]
			for scv2 in sts2._candidates(sset2, 0, 0, 64):
				nb += 1
				var bx2: int = scv2.x * 16 + 8
				var bz2: int = scv2.y * 16 + 8
				if (cfg2["biomes"] as Dictionary).has(sts2.biome_id_at(bx2, sts2._stub_y(cfg2, bx2, bz2), bz2)):
					nbio += 1
					lows.append("%s ok=%s" % [str(scv2), str(sts2._stub_ok(cfg2, scv2))])
	print("[stubstat] %s: %d candidates, %d in biome: %s" % [want, nb, nbio, " ".join(lows.slice(0, 20))])


func _auto_run() -> void:
	if autoplay.has("dim") and str(autoplay["dim"]) != dimension and (autoplay.has("loadtest") or autoplay.has("nativecheck") or autoplay.has("fpsbench") or autoplay.has("dragonshots") or autoplay.has("rpcheck") or autoplay.has("respawntest") or autoplay.has("stubstat") or autoplay.has("ecdump") or autoplay.has("cam")):
		# probes in another dimension (--dim=the_nether|the_end): travel first, then run the probe there
		var tq := Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - tq < 60000:
			await get_tree().process_frame
		var dimq := str(autoplay["dim"])
		var arrq := {"kind": "nether_portal", "pos": Portals.scaled_target(dimension, dimq, player.pos), "axis": "x"} if dimq == "the_nether" else {"kind": "end_platform", "pos": Vector3(100.5, 49, 0.5)}
		change_dimension(dimq, arrq)
		tq = Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - tq < 60000:
			await get_tree().process_frame
		print("[dim] probe in %s at %s" % [dimension, str(player.pos)])
	if autoplay.has("respawntest"):   # --respawntest=1 (with --dim=the_end): kill the dragon, 4 crystals on the portal, respawn
		var tr0 := Time.get_ticks_msec()
		player.mode = Player.Mode.SPECTATOR
		player.pos = Vector3(0.5, 90.0, -60.0)
		player.prev_pos = player.pos
		_update_origin(true)
		while (dragon_fight == null or not dragon_fight.ready or dragon_fight._find("ender_dragon") == null) and Time.get_ticks_msec() - tr0 < 90000:
			await get_tree().process_frame
		for en1 in entities.ents.duplicate():
			if en1.kind == "mob" and en1.id == "ender_dragon":
				dragon_fight.on_dragon_death(en1)
				entities._remove(en1)
		var pyr := int(dragon_fight.state["podium_y"])
		print("[respawntest] killed: %s, portal at y %d: %s" % [dragon_fight.state["killed"], pyr, Res.blocks.name_of(maxi(0, state_at(1, pyr, 0)))])
		for cp2 in [Vector3(3.5, pyr + 1, 0.5), Vector3(-2.5, pyr + 1, 0.5), Vector3(0.5, pyr + 1, 3.5), Vector3(0.5, pyr + 1, -2.5)]:
			var ce2 = entities.spawn_mob("end_crystal", cp2)
			ce2.data["ShowBottom"] = false
		dragon_fight.try_respawn()
		print("[respawntest] stage %d, crystals %d, portal now %s" % [dragon_fight.respawn_stage, dragon_fight.respawn_crystals.size(), Res.blocks.name_of(maxi(0, state_at(1, pyr, 0)))])
		var gt1: int = game_time
		var last := -2
		while Time.get_ticks_msec() - tr0 < 400000:
			await get_tree().process_frame
			if dragon_fight.respawn_stage != last:
				last = dragon_fight.respawn_stage
				print("[respawntest] t%d stage %d" % [game_time - gt1, last])
				if last == -1:
					break
		var drn := 0
		for en2 in entities.ents:
			if en2.kind == "mob" and en2.id == "ender_dragon":
				drn += 1
		print("[respawntest] done after %d ticks: dragons %d, killed %s" % [game_time - gt1, drn, dragon_fight.state["killed"]])
		get_tree().quit()
		return
	if autoplay.has("dragonshots"):   # --dragonshots=N (with --dim=the_end): N screenshots aimed at the dragon, 1.5 s apart
		var td0 := Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - td0 < 60000:
			await get_tree().process_frame
		player.mode = Player.Mode.SPECTATOR
		player.pos = Vector3(0.5, 90.0, -60.0)
		player.prev_pos = player.pos
		_update_origin(true)
		var has_dr := false
		while not has_dr and Time.get_ticks_msec() - td0 < 90000:
			await get_tree().process_frame
			for en0 in entities.ents:
				has_dr = has_dr or (en0.kind == "mob" and en0.id == "ender_dragon")
			if Engine.get_process_frames() % 300 == 0:
				print("[dragonshots] wait: dim %s ready %s fight %s init %s c00 %s ents %d" % [dimension, spawn_ready, dragon_fight != null, dragon_fight.ready if dragon_fight != null else false, cm.is_ready(0, 0), entities.ents.size()])
		for _w in 200:
			await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute("user://autoplay")
		for k in int(autoplay["dragonshots"]):
			var dr = null
			for en in entities.ents:
				if en.kind == "mob" and en.id == "ender_dragon":
					dr = en
			if dr == null:
				print("[dragonshots] no dragon")
				break
			var dpos: Vector3 = dr.pos + Vector3(0, 2, 0)
			var ang := k * 1.3
			player.mode = Player.Mode.SPECTATOR
			player.pos = dpos + Vector3(cos(ang), 0.35, sin(ang)) * float(autoplay.get("dragondist", "28"))
			player.prev_pos = player.pos
			_update_origin(true)
			for _f in 3:
				var dirv: Vector3 = (dr.pos + Vector3(0, 2, 0) - player.eye_pos()).normalized()
				player.yaw = rad_to_deg(atan2(-dirv.x, dirv.z))
				player.pitch = rad_to_deg(-asin(dirv.y))
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png("user://autoplay/dragon_%d.png" % k)
			print("[dragonshots] %d phase %d pos %s crystal %s" % [k, dr.state, str(dr.pos), str(dr.rt.has("crystal"))])
			for _f2 in 90:
				player.pos = dr.pos + Vector3(0, 2, 0) + Vector3(cos(ang), 0.35, sin(ang)) * float(autoplay.get("dragondist", "28"))
				player.prev_pos = player.pos
				await get_tree().process_frame
		get_tree().quit()
		return
	if autoplay.has("boxdump"):   # --boxdump=x0,y0,z0,x1,y1,z1 (after load, + optional --bdticks=N): block counts in the box
		var bv: PackedStringArray = str(autoplay["boxdump"]).split(",")
		var tb0 := Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - tb0 < 60000:
			await get_tree().process_frame
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tb0 < 90000:
			await get_tree().process_frame
		if autoplay.has("cmds"):
			for cl1 in str(autoplay["cmds"]).split(";"):
				var cl2 := cl1.replace("+", " ").strip_edges()
				if cl2 != "":
					print("[cmds] %s -> %s" % [cl2, commands.execute(cl2)])
		var gt0: int = game_time
		while game_time - gt0 < int(autoplay.get("bdticks", "0")) and Time.get_ticks_msec() - tb0 < 600000:
			await get_tree().process_frame
		var cnt := {}
		for by2 in range(int(bv[1]), int(bv[4]) + 1):
			for bz2 in range(int(bv[2]), int(bv[5]) + 1):
				for bx2 in range(int(bv[0]), int(bv[3]) + 1):
					var sn := Res.blocks.name_of(maxi(0, state_at(bx2, by2, bz2)))
					cnt[sn] = int(cnt.get(sn, 0)) + 1
		print("[boxdump] %s" % str(cnt))
		get_tree().quit()
		return
	if autoplay.has("ecdump"):   # --ecdump=1 (with --dim=the_end): first end city start along +x from chunk 62: pieces
		var sts3: Structures = gen.structures
		var ecfg: Dictionary = sts3.structures.get("end_city", {})
		var ecz := 0
		var ecx0 := 62
		var ecx1 := 200
		if str(autoplay["ecdump"]).contains(","):
			var ev: PackedStringArray = str(autoplay["ecdump"]).split(",")
			ecx0 = int(ev[0])
			ecx1 = ecx0 + 1
			ecz = int(ev[1])
		for ecx in range(ecx0, ecx1):
			var r3 := Structures.large_feature_seed(gen.seed, ecx, ecz)
			var res3 := StructuresLegacy.generate(sts3, "end_city", ecfg, Vector2i(ecx, ecz), r3)
			if res3.is_empty():
				print("[ecdump] chunk (%d, %d): no start (lowest corner below 60?)" % [ecx, ecz])
				continue
			var names := {}
			for pc3 in res3["pieces"]:
				var nm3 := str(pc3["el"]["loc"]).trim_prefix("end_city/")
				names[nm3] = int(names.get(nm3, 0)) + 1
			print("[ecdump] chunk (%d, %d): %d pieces %s centre %s box %s" % [ecx, ecz, (res3["pieces"] as Array).size(), str(names), str(res3["center"]), str(res3["box"])])
			break
		get_tree().quit()
		return
	if autoplay.has("stubstat"):   # --stubstat=name: candidates of that structure within 64 chunks: biome / corner checks
		var sts2: Structures = gen.structures
		for want in str(autoplay["stubstat"]).split(","):
			_stubstat(sts2, want)
		get_tree().quit()
		return
	if false:
		var sts2: Structures = gen.structures
		var want := ""
		var nb := 0
		var nbio := 0
		var lows: Array = []
		for sset2 in sts2.sets:
			for e2 in sset2["entries"]:
				if str(e2["name"]) != want:
					continue
				var cfg2: Dictionary = e2["cfg"]
				for scv2 in sts2._candidates(sset2, 0, 0, 64):
					nb += 1
					var bx2: int = scv2.x * 16 + 8
					var bz2: int = scv2.y * 16 + 8
					if (cfg2["biomes"] as Dictionary).has(sts2.biome_id_at(bx2, sts2._stub_y(cfg2, bx2, bz2), bz2)):
						nbio += 1
						var lo3 := 1 << 30
						for cc in [Vector2i(scv2.x * 16, scv2.y * 16), Vector2i(scv2.x * 16 + 21, scv2.y * 16 + 21)]:
							lo3 = mini(lo3, sts2.base_height(cc.x, cc.y, false) - 1)
						lows.append("%s:%d/ffh%d" % [str(scv2), lo3, sts2.first_free_height(bx2, bz2) - 1])
		print("[stubstat] %s: %d candidates, %d in biome; lowest corner: %s" % [want, nb, nbio, " ".join(lows.slice(0, 20))])
		get_tree().quit()
		return
	if autoplay.has("rpcheck"):   # --rpcheck=R: ruined portal starts within R chunks: placement, y, centre surface
		var sts: Structures = gen.structures if gen != null and "structures" in gen else null
		var rr := int(autoplay.get("rpcheck", "20"))
		var pc0 := Vector2i(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4)
		var seen := {}
		var lines: Array = []
		if sts != null:
			for sset in sts.sets:
				var is_rp := false
				for e in sset["entries"]:
					if str(e["name"]).begins_with("ruined_portal"):
						is_rp = true
				if not is_rp:
					continue
				for cz3 in range(pc0.y - rr, pc0.y + rr + 1, 8):
					for cx3 in range(pc0.x - rr, pc0.x + rr + 1, 8):
						for scv in sts._candidates(sset, cx3, cz3):
							if seen.has(scv):
								continue
							seen[scv] = true
							var res: Dictionary = sts._start(sset, scv)
							if res.is_empty() or not res.has("pieces"):
								continue
							var el: Dictionary = res["pieces"][0]["el"]
							var tb: Array = el.get("tbox", res["box"])
							var cxm: int = (tb[0].x + tb[1].x) / 2
							var czm: int = (tb[0].z + tb[1].z) / 2
							lines.append("%s %s %s y=%d surf=%d air=%s mirror=%s box=%s" % [res["structure"], str(scv), str(el.get("placement", "?")), int(res["pieces"][0]["pos"].y), sts.base_height(cxm, czm, false) - 1, str(not bool(el["legacy"])), str(el.get("mirror", false)), str(tb)])
		for ln in lines:
			print("[rpcheck] " + ln)
		print("[rpcheck] %d portals" % lines.size())
		get_tree().quit()
		return
	if autoplay.has("icegap"):   # --icegap=1 (with --atbiome=ice_spikes): air cells sandwiched in packed ice, by y
		var tg0 := Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - tg0 < 60000:
			await get_tree().process_frame
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tg0 < 90000:
			await get_tree().process_frame
		var pk := Res.blocks.default_state("packed_ice")
		var pcg := Vector2i(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4)
		var by_y := {}
		var samples: Array = []
		for cz2 in range(pcg.y - 6, pcg.y + 7):
			for cx2 in range(pcg.x - 6, pcg.x + 7):
				var ch2: Chunk = cm.get_chunk(cx2, cz2)
				if ch2 == null or ch2.state < Chunk.DECORATED:
					continue
				for lz in 16:
					for lx in 16:
						for yy in range(60, 220):
							if ch2.get_block(lx, yy, lz) == 0 and ch2.get_block(lx, yy + 1, lz) == pk and ch2.get_block(lx, yy - 1, lz) == pk:
								by_y[yy] = int(by_y.get(yy, 0)) + 1
								if samples.size() < 12:
									samples.append(Vector3i(cx2 * 16 + lx, yy, cz2 * 16 + lz))
		var ys: Array = by_y.keys()
		ys.sort_custom(func(a, b): return by_y[a] > by_y[b])
		var top: Array = []
		for yk in ys.slice(0, 12):
			top.append("y%d:%d" % [yk, by_y[yk]])
		print("[icegap] sandwiched air cells by y: %s | samples %s" % [" ".join(top), str(samples)])
		if not samples.is_empty():
			var s0: Vector3i = samples[0]
			for yy2 in range(s0.y + 3, s0.y - 4, -1):
				var row := ""
				for dz2 in range(-3, 4):
					for dx2 in range(-3, 4):
						var st2: int = state_at(s0.x + dx2, yy2, s0.z + dz2)
						row += "#" if st2 == pk else ("." if st2 == 0 else "o")
					row += " "
				print("[icegap] y%d %s" % [yy2, row])
		get_tree().quit()
		return
	if autoplay.has("flowtest"):   # --flowtest=1: a water source on flat ground; water blocks per game tick (Java: +1 ring / 5 ticks)
		var tf := Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - tf < 60000:
			await get_tree().process_frame
		for f11 in 60:
			await get_tree().process_frame
		var src := Vector3i(int(floor(player.pos.x)) + 6, int(floor(player.pos.y)), int(floor(player.pos.z)) + 6)
		set_block(src.x, src.y, src.z, Res.blocks.WATER)
		BlockUpdates.schedule(self, src, 1)
		var t_start := game_time
		var log := []
		var last := -1
		while game_time - t_start < 80:
			await get_tree().process_frame
			var cnt := 0
			var maxd := 0
			for dz in range(-9, 10):
				for dx in range(-9, 10):
					var s11: int = state_at(src.x + dx, src.y, src.z + dz)
					if s11 > 0 and (Res.blocks.st_flags[s11] & BlockRegistry.F_LIQUID) != 0:
						cnt += 1
						maxd = maxi(maxd, absi(dx) + absi(dz))
			if cnt != last:
				last = cnt
				log.append("t%d:%d(r%d)" % [game_time - t_start, cnt, maxd])
		print("[flowtest] %s" % " ".join(log))
		get_tree().quit()
		return
	if autoplay.has("dimtrip"):   # --dimtrip=1: overworld -> nether -> overworld; the way back adopts cached chunks
		var t9 := Time.get_ticks_msec()
		while not spawn_ready and Time.get_ticks_msec() - t9 < 60000:
			await get_tree().process_frame
		for f9 in 120:
			await get_tree().process_frame
		var home := player.pos
		for leg in ["the_nether", "overworld"]:
			var arr9 := {"kind": "nether_portal", "pos": Portals.scaled_target(dimension, leg, player.pos) if leg == "the_nether" else home, "axis": "x"}
			var hits0 := ChunkManager.cache_hits
			var tl := Time.get_ticks_msec()
			change_dimension(leg, arr9)
			while not spawn_ready and Time.get_ticks_msec() - tl < 60000:
				await get_tree().process_frame
			var t_spawn9 := Time.get_ticks_msec() - tl
			var pc9 := Vector2i(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4)
			var shown := 0
			while Time.get_ticks_msec() - tl < 30000:
				shown = 0
				for dz9 in range(-4, 5):
					for dx9 in range(-4, 5):
						var c9: Chunk = cm.get_chunk(pc9.x + dx9, pc9.y + dz9)
						if c9 != null and c9.shown:
							shown += 1
				if shown >= 81:
					break
				await get_tree().process_frame
			print("[dimtrip] %s: spawn ready %d ms, ring 4 visible %d ms (%d / 81), chunks from memory %d" % [leg, t_spawn9, Time.get_ticks_msec() - tl, shown, ChunkManager.cache_hits - hits0])
			for f10 in 60:
				await get_tree().process_frame
		get_tree().quit()
		return
	if autoplay.has("loadtest"):
		await LoadTest.run(self)
		return
	if autoplay.has("fpsbench"):
		# tracing adds per-commit / per-tick bookkeeping that normal play doesn't have: only for attribution runs
		cm.tracing = autoplay.has("trace")
		await FpsBench.run(self)
		return
	if autoplay.has("nativecheck"):
		await LoadTest.native_check(self)
		return
	if autoplay.has("nettest"):
		Net.run_test(self, str(autoplay["nettest"]))
		return
	var t0 := Time.get_ticks_msec()
	var secs := float(autoplay.get("secs", "25"))
	while not spawn_ready and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame
	var t_spawn := Time.get_ticks_msec() - t0
	if autoplay.has("dim") and str(autoplay["dim"]) != dimension:
		# travel test: nether via portal arrival (links/creates a portal), End via the obsidian platform
		var dim := str(autoplay["dim"])
		var arr := {"kind": "nether_portal", "pos": Portals.scaled_target(dimension, dim, player.pos), "axis": "x"} if dim == "the_nether" else {"kind": "end_platform", "pos": Vector3(100.5, 49, 0.5)}
		var td := Time.get_ticks_msec()
		change_dimension(dim, arr)
		while not spawn_ready and Time.get_ticks_msec() - t0 < secs * 1000.0:
			await get_tree().process_frame
		print("[dim] arrived in %s at %s after %d ms" % [dimension, str(player.pos), Time.get_ticks_msec() - td])
	if autoplay.has("dragonsim"):   # --dim=the_end --dragonsim=N: run N game ticks, log the dragon's path / phase
		var dr = null
		var tw0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - tw0 < 90000:
			for de in entities.ents:
				if de.kind == "mob" and de.id == "ender_dragon" and not de.dead:
					dr = de
			if dr != null:
				break
			_tick()
			await get_tree().process_frame
		if dr == null:
			print("[dragonsim] no dragon")
		else:
			var path := []
			var turn_sum := 0.0
			var last_yaw: float = dr.yaw
			for t in int(autoplay["dragonsim"]):
				_tick()
				entities.tick()
				if t % 4 == 0:
					await get_tree().process_frame   # chunk loading finishes on the main thread
				turn_sum += absf(MobControl.wrap_deg(dr.yaw - last_yaw))
				last_yaw = dr.yaw
				if t % 40 == 0:
					path.append("t%d (%.0f,%.0f,%.0f) yaw %.0f ph %s" % [t, dr.pos.x, dr.pos.y, dr.pos.z, dr.yaw, str(dr.rt.get("phase", "?"))])
			print("[dragonsim] total |turn| %.0f deg over %s ticks" % [turn_sum, str(autoplay["dragonsim"])])
			for pl2 in path:
				print("[dragonsim] " + pl2)
	if autoplay.has("third"):
		third_person = int(autoplay["third"])
		player.mode = Player.Mode.SURVIVAL
		if autoplay.has("hold") and not autoplay.has("entblocks"):   # --hold / --offhold: held items (third-person checks)
			player.inventory.set_slot(player.inventory.selected, ItemStack.named(str(autoplay["hold"]), 1))
		if autoplay.has("offhold"):
			player.inventory.set_slot(Inventory.OFFHAND, ItemStack.named(str(autoplay["offhold"]), 1))
		if autoplay.has("cushiontest"):   # --cushiontest=1: place a red cushion, sit on it, get up, break it
			var below := Vector3i(player.pos.floor()) + Vector3i(0, -1, 2)
			player.inventory.set_slot(player.inventory.selected, ItemStack.named("red_cushion", 2))
			var placed := MiscEntities.use_item(self, player.inventory.held(), {"pos": below, "normal": Vector3i(0, 1, 0)})
			var cu = null
			for ce in entities.ents:
				if ce.kind == "cushion":
					cu = ce
			print("[cushion] placed %s at %s, items left %d" % [placed, str(cu.pos) if cu != null else "-", player.inventory.held().count])
			if cu != null:
				MiscEntities.interact(entities, cu, player, ItemStack.new())
				for k in 5:
					entities.tick()
				print("[cushion] riding %s, player y %.3f cushion y %.3f" % [player.vehicle == cu, player.pos.y, cu.pos.y])
				if not autoplay.has("stay"):
					Taming.dismount(entities, player)
					print("[cushion] after get up: riding %s, player at %s" % [player.vehicle != null, str(player.pos)])
					MiscEntities.attack(entities, cu, player)
					var drops2: Array = entities.ents.filter(func(x): return x.kind == "item" and x.stack.name() == "red_cushion")
					print("[cushion] after break: cushion dead %s, dropped items %d" % [cu.dead, drops2.size()])
		if autoplay.has("mobs"):   # --mobs=a,b,c: NoAI mobs in a row 3.5 blocks in front, facing the player
			var mids: PackedStringArray = str(autoplay["mobs"]).split(",")
			var fwd := Vector3(-sin(deg_to_rad(player.yaw)), 0, cos(deg_to_rad(player.yaw)))
			var side := Vector3(fwd.z, 0, -fwd.x)
			for mi_i in mids.size():
				var mp := player.pos + fwd * float(autoplay.get("mobdist", 4.5)) + side * (float(mi_i) - (mids.size() - 1) / 2.0) * float(autoplay.get("mobgap", 1.6))
				var me = entities.spawn_mob(mids[mi_i], mp)
				if me != null:
					me.noai = true
					me.persistent = true
					me.yaw = player.yaw + 180.0 + float(autoplay.get("mobyaw", 0.0))
					me.body_yaw = me.yaw
					me.body_yaw_o = me.yaw
					me.head_yaw = me.yaw
					me.head_yaw_o = me.yaw
					if autoplay.has("mobheld"):
						me.data["held"] = str(autoplay["mobheld"])
	if autoplay.has("projs"):   # --projs=1: arrow / spectral / tipped / trident hanging sideways in front (render check)
		var pfwd := Vector3(-sin(deg_to_rad(player.yaw)), 0, cos(deg_to_rad(player.yaw)))
		var pside := Vector3(pfwd.z, 0, -pfwd.x)
		var kinds := [["arrow", ""], ["arrow", "spectral_arrow"], ["arrow", "tipped_arrow"], ["trident", ""]]
		for pi in kinds.size():
			var pp := player.eye_pos() + pfwd * 1.6 + Vector3(0, 0.35 - pi * 0.25, 0)
			entities.spawn_projectile(kinds[pi][0], pp, pside * 0.5, null)
			var pe = entities.ents[entities.ents.size() - 1]
			pe.data["ground"] = true
			pe.vel = Vector3.ZERO
			if kinds[pi][1] != "":
				pe.data["ammo"] = kinds[pi][1]
			pe.node.basis = Basis.looking_at(pside.rotated(Vector3.UP, 0.5), Vector3.UP)
	if autoplay.has("entblocks"):
		var eo := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 5)
		player.pos = Vector3(eo) + Vector3(0.5, 0, -float(autoplay.get("entblocks", "1.2")))
		player.prev_pos = player.pos
		var EB := Res.blocks
		var names := ["chest", "piglin_head", "red_banner", "shulker_box", "skeleton_skull", "decorated_pot", "ender_chest", "conduit", "dragon_head", "bell"]
		for i in names.size():
			var st := EB.default_state(names[i])
			if EB.has_prop(st, "facing"):
				st = EB.with_prop(st, "facing", "north")
			if EB.has_prop(st, "rotation"):
				st = EB.with_prop(st, "rotation", "8")
			set_block(eo.x - 4 + i, eo.y, eo.z, st, false)
		var cl := EB.state_of("minecraft:chest", {"facing": "north", "type": "left"})
		var cr := EB.state_of("minecraft:chest", {"facing": "north", "type": "right"})
		set_block(eo.x - 1, eo.y, eo.z + 2, cl, false)
		set_block(eo.x, eo.y, eo.z + 2, cr, false)
		set_block(eo.x + 2, eo.y, eo.z + 2, EB.with_prop(EB.default_state("red_shulker_box"), "facing", "up"), false)
		set_block(eo.x - 3, eo.y + 1, eo.z + 2, EB.state_of("minecraft:zombie_wall_head", {"facing": "north"}), false)
		set_block(eo.x - 3, eo.y, eo.z + 3, EB.default_state("stone"), false)
		set_block(eo.x - 3, eo.y + 1, eo.z + 3, EB.default_state("stone"), false)
		print("[entblocks] double chest types: %s / %s" % [EB.get_prop(cl, "type"), EB.get_prop(cr, "type")])
		var dz := -float(autoplay.get("entblocks", "1.2")) + 1.6
		for di in 4:
			var dn: String = ["chest", "red_banner", "zombie_head", "lime_shulker_box"][di]
			var ds := ItemStack.named(dn, 1)
			var dent = entities.spawn_item(Vector3(eo) + Vector3(-0.6 + di * 0.6, 0.2, dz), ds)
			if dent != null:
				dent.vel = Vector3.ZERO
				dent.pickup_delay = 9999
		player.inventory.set_slot(player.inventory.selected, ItemStack.named(str(autoplay.get("hold", "chest")), 1))
	if autoplay.has("signs"):
		var so := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 5)
		player.pos = Vector3(so) + Vector3(0.5, 0, -2.5)
		player.prev_pos = player.pos
		var SB := Res.blocks
		set_block(so.x - 1, so.y, so.z, SB.state_of("minecraft:oak_sign", {"rotation": "8"}), false)
		BlockEntities.set_data(self, Vector3i(so.x - 1, so.y, so.z), {"id": "sign", "front": ["Hello", "Recraft", "signs work", "line 4"], "back": ["", "", "", ""], "front_color": "black", "back_color": "black", "front_glow": false, "back_glow": false, "waxed": false})
		for x in range(1, 4):
			for y in range(0, 2):
				set_block(so.x + x, so.y + y, so.z + 1, SB.default_state("stone"), false)
		set_block(so.x + 2, so.y, so.z, SB.state_of("minecraft:spruce_wall_sign", {"facing": "north"}), false)
		BlockEntities.set_data(self, Vector3i(so.x + 2, so.y, so.z), {"id": "sign", "front": ["", "Wall sign", "glowing", ""], "back": ["", "", "", ""], "front_color": "light_blue", "back_color": "black", "front_glow": true, "back_glow": false, "waxed": false})
		Signs.mark_dirty()
	if autoplay.has("screen"):
		# UI probe: open an in-game screen and save a screenshot
		if autoplay.has("gm"):
			player.mode = {"survival": Player.Mode.SURVIVAL, "creative": Player.Mode.CREATIVE, "adventure": Player.Mode.ADVENTURE}.get(str(autoplay["gm"]), player.mode)
		var sname := str(autoplay["screen"])
		if autoplay.has("ctab"):   # --ctab=N: creative tab to open (12 = Survival Inventory)
			CreativeScreen.selected = int(autoplay["ctab"])
		if autoplay.has("giveitems"):   # --giveitems=a,b,c: fill the hotbar first (icon / held-item checks)
			var gi := 0
			for gn in str(autoplay["giveitems"]).split(","):
				if gi < 9 and Res.items.id(gn) > 0:
					player.inventory.set_slot(gi, ItemStack.named(gn, 1))
					gi += 1
		if sname.begins_with("ws_") or sname.begins_with("ct_"):
			# probe: place the block and open its workstation / container screen
			var kd := sname.substr(3)
			var wp := Vector3i(player.pos.floor()) + Vector3i(0, 0, 2)
			var wst := Res.blocks.state_of("minecraft:" + kd, {})
			set_block(wp.x, wp.y, wp.z, wst)
			BlockEntities.on_placed(self, wp, wst)
			for it in [["iron_pickaxe", 1], ["lapis_lazuli", 12], ["coal", 8], ["iron_ore", 5], ["stone", 32], ["blaze_powder", 2], ["glass_bottle", 3]]:
				player.inventory.add(ItemStack.named(it[0], it[1]))
			var ws = load("res://scripts/ui/workstation_screen.gd" if sname.begins_with("ws_") else "res://scripts/ui/container_screen.gd").new()
			ws.world = self
			ws.kind = kd
			ws.pos = wp
			open_screen(ws)
		if sname == "tabdump":   # creative tab coverage: registry items the vanilla-order lists do not name
			var named := CreativeTabs.lists()
			var known := {}
			for tk in named:
				for nm in named[tk]:
					known[nm] = true
			var miss: Array = []
			for ii in range(1, Res.items.names.size()):
				var inm: String = Res.items.names[ii]
				if not known.has(inm) and not inm.ends_with("_spawn_egg") and not (inm in CreativeScreen.OP_ITEMS) and not (inm in CreativeTabs.EXCLUDED) and inm != "spawner" and inm != "trial_spawner":
					miss.append(inm + "(" + CreativeScreen.category(ii).left(5) + ")")
			print("[tabdump] %d items, %d not in the vanilla lists: %s" % [Res.items.names.size(), miss.size(), ", ".join(miss)])
		if autoplay.has("cmds") and not autoplay.has("cam"):   # --cmds also before a --screen shot
			for cl3 in str(autoplay["cmds"]).split(";"):
				var cl4 := cl3.replace("+", " ").strip_edges()
				if cl4 != "":
					print("[cmds] %s -> %s" % [cl4, commands.execute(cl4)])
		match sname:
			"pause":
				var pm = load("res://scripts/ui/pause_menu.gd").new()
				open_screen(pm)
			"pause_options":
				var pm2 = load("res://scripts/ui/pause_menu.gd").new()
				open_screen(pm2)
				await get_tree().process_frame
				pm2._options()
				if autoplay.has("screendone"):   # back-navigation check: Done on Options must return to the Game Menu
					for i in 20:
						await get_tree().process_frame
					screen._done_pressed()
					for i in 20:
						await get_tree().process_frame
					print("[ui] in-world options Done -> screen %s" % (screen.get_script().resource_path.get_file() if screen != null and is_instance_valid(screen) else "none"))
			"inventory":
				open_screen(inventory_screen())
			"hud":
				# HUD probe: a realistic survival state (vitals, armour, xp, offhand, damaged tool, stacks)
				player.health = 13.0
				player.food = 15
				player.xp_level = 7
				player.xp_progress = 0.42
				var inv = player.inventory
				var sw := ItemStack.named("iron_sword")
				sw.damage = 120
				inv.set_slot(0, sw)
				inv.set_slot(1, ItemStack.named("cobblestone", 64))
				inv.set_slot(2, ItemStack.named("torch", 23))
				inv.set_slot(3, ItemStack.named("bread", 5))
				inv.set_slot(4, ItemStack.named("oak_planks", 12))
				inv.set_slot(Inventory.OFFHAND, ItemStack.named("shield"))
				inv.set_slot(Inventory.ARMOR0 + 1, ItemStack.named("iron_chestplate"))
				inv.set_slot(Inventory.ARMOR0 + 2, ItemStack.named("iron_leggings"))
				inv.selected = 1
			"cartography", "cartography_copy", "cartography_lock":   # cartography table with a map + paper / map / pane
				var fm := Maps.new_map(self, player.pos.x, player.pos.z)
				for i in 300:
					Maps.update(self, Maps.map_id(fm))
				var cws = load("res://scripts/ui/workstation_screen.gd").new()
				cws.kind = "cartography_table"
				open_screen(cws)
				await get_tree().process_frame
				cws.inp[0] = fm
				cws.inp[1] = ItemStack.named({"cartography": "paper", "cartography_copy": "map", "cartography_lock": "glass_pane"}[sname], 1)
				cws.on_changed()
				print("[screen] cartography result %s x%d" % [cws.result.name(), cws.result.count])
			"stats", "advancements":
				var sc = load("res://scripts/ui/%s_screen.gd" % sname).new()
				sc.world = self
				player.stats["mined.stone"] = 12
				player.stats["crafted.crafting_table"] = 1
				player.stats["killed.zombie"] = 3
				if advancements != null:
					for aid in ["story/root", "story/mine_stone", "story/upgrade_tools", "story/smelt_iron", "adventure/root"]:
						advancements.done[aid] = true
				open_screen(sc)
			"sign", "hanging_sign":
				var sp := Vector3i(player.pos.floor()) + Vector3i(0, 0, 2)
				var sst := Res.blocks.state_of("minecraft:oak_sign", {}) if sname == "sign" else Res.blocks.state_of("minecraft:oak_hanging_sign", {})
				set_block(sp.x, sp.y, sp.z, sst)
				BlockEntities.on_placed(self, sp, sst)
				var ss = load("res://scripts/ui/sign_screen.gd").new()
				ss.world = self
				ss.pos = sp
				open_screen(ss)
				await get_tree().process_frame
				(ss.edits[0] as LineEdit).text = "Welcome to"
				(ss.edits[1] as LineEdit).text = "Recraft"
			"book":
				var bk := ItemStack.named("writable_book")
				bk.components["minecraft:writable_book_content"] = {"pages": ["Day 1: found a village near the birch forest. Built a small hut.", "Day 2: mining."]}
				player.inventory.set_slot(player.inventory.selected, bk)
				var bs = load("res://scripts/ui/book_screen.gd").new()
				bs.world = self
				bs.stack = bk
				open_screen(bs)
			"titles":
				level["bossbars"] = {"b1": {"name": "Ender Dragon", "value": 70, "max": 100, "color": "pink", "visible": true}}
				hud.toast(Res.tr_key("advancements.toast.task", "Advancement Made!"), "Stone Age", "wooden_pickaxe")
				hud.set_title("Welcome", "to Recraft", "Action bar message")
			"chat":
				for m in ["<Player> hello", "Player joined the game", "[Debug]: Advanced tooltips: shown", "<Player> a much longer chat line to check the width of the chat background box"]:
					hud.chat_message(m)
				var cs = load("res://scripts/ui/chat_screen.gd").new()
				cs.world = self
				cs.prefill = "/give @s dia"
				open_screen(cs)
			"death":
				player.last_damage_source = "mob"
				player.last_attacker_id = "zombie"
				player.xp_total = 37
				open_screen(load("res://scripts/ui/death_screen.gd").new())
			"world_options", "world_options_mp":
				var wo = load("res://scripts/ui/world_options.gd").new()
				wo.world = self
				open_screen(wo)
				if sname == "world_options_mp":
					await get_tree().process_frame
					wo._show(1)
			"options":
				var om = load("res://scripts/ui/options_menu.gd").new()
				om.world = self
				om.back = func(): close_screen()
				open_screen(om)
			"crafting":
				for it in [["oak_log", 8], ["cobblestone", 16], ["stick", 6], ["iron_ingot", 3]]:
					player.inventory.add(ItemStack.named(it[0], it[1]))
				var crs = load("res://scripts/ui/crafting_screen.gd").new()
				open_screen(crs)
				await get_tree().process_frame
				crs.rb_open = true
				crs._rb_refresh()
				print("[screen] craftable recipes: %d" % crs.rb_list.size())
				if not crs.rb_list.is_empty():
					for k in crs.rb_list.size():
						if str(crs.rb_list[k][0]["result"]) == "stone_pickaxe":
							RecipeBook.fill(self, crs.rb_list[k], 9, crs.rb_get, crs.rb_set)
							crs.on_changed()
							print("[screen] filled stone_pickaxe -> result %s" % crs.result.name())
			"loom":
				for it in [["white_banner", 2], ["red_dye", 4], ["blue_dye", 4], ["creeper_banner_pattern", 1], ["chest", 1], ["shulker_box", 1], ["skeleton_skull", 1], ["decorated_pot", 1], ["conduit", 1], ["ender_chest", 1], ["dragon_head", 1], ["lime_shulker_box", 1], ["piglin_head", 1], ["creeper_head", 1], ["trapped_chest", 1], ["bell", 1], ["leather_helmet", 1], ["leather_chestplate", 1]]:
					player.inventory.add(ItemStack.named(it[0], it[1]))
				var lc := ItemStack.named("leather_boots", 1)
				lc.components["minecraft:dyed_color"] = 0x3C44AA
				player.inventory.add(lc)
				player.inventory.set_slot(Inventory.ARMOR0, lc.copy())
				var lh2 := ItemStack.named("leather_helmet", 1)
				lh2.components["minecraft:dyed_color"] = 0xB02E26
				player.inventory.set_slot(Inventory.ARMOR0 + 3, lh2)
				var lm = load("res://scripts/ui/workstation_screen.gd").new()
				lm.kind = "loom"
				lm.pos = Vector3i(player.pos.floor())
				open_screen(lm)
				await get_tree().process_frame
				lm.inp[0] = ItemStack.named("white_banner", 1)
				lm.inp[1] = ItemStack.named("red_dye", 1)
				lm.on_changed()
				print("[screen] loom patterns without item: %d" % lm.loom_list.size())
				lm.loom_sel = lm.loom_list.find("minecraft:stripe_top")
				lm.on_changed()
				var first: ItemStack = lm.result.copy()
				lm.inp[0] = first
				lm.inp[1] = ItemStack.named("blue_dye", 1)
				lm.inp[2] = ItemStack.named("creeper_banner_pattern", 1)
				lm.on_changed()
				print("[screen] loom patterns with creeper item: %s sel %d" % [str(lm.loom_list), lm.loom_sel])
				var res2: ItemStack = lm.result.copy()
				print("[screen] loom result layers: %s" % str(Banners.layers(res2)))
				# place it in the world through the normal placement path and look at it after closing
				var bp := Vector3i(player.pos.floor()) + Vector3i(0, 0, 3)
				set_block(bp.x, bp.y, bp.z, Res.blocks.state_of("minecraft:white_banner", {"rotation": "8"}))
				BlockEntities.apply_item(self, bp, res2)
				player.yaw = 0.0
				player.pitch = -10.0
			"chest", "largechest":
				var cs = load("res://scripts/ui/container_screen.gd").new()
				cs.pos = Vector3i(player.pos.floor())
				cs.kind = "chest"
				if sname == "largechest":
					# a real double chest 2 blocks ahead, placed through the Java placement rules
					var cpos := Vector3i(player.pos.floor()) + Vector3i(0, 0, 2)
					var CB := Res.blocks
					set_block(cpos.x, cpos.y, cpos.z, CB.state_of("minecraft:chest", {"facing": "north"}))
					set_block(cpos.x + 1, cpos.y, cpos.z, CB.state_of("minecraft:chest", {"facing": "north", "type": "right"}))
					set_block(cpos.x, cpos.y, cpos.z, CB.state_of("minecraft:chest", {"facing": "north", "type": "left"}))
					BlockEntities.on_placed(self, cpos, state_at(cpos.x, cpos.y, cpos.z))
					BlockEntities.on_placed(self, cpos + Vector3i(1, 0, 0), state_at(cpos.x + 1, cpos.y, cpos.z))
					var d1 := BlockEntities.get_data(self, cpos)
					var it1: Array = []
					it1.resize(27)
					for k in 27:
						it1[k] = {}
					it1[0] = ItemStack.named("diamond", 5).to_dict()
					d1["items"] = it1
					BlockEntities.set_data(self, cpos, d1)
					var d2 := BlockEntities.get_data(self, cpos + Vector3i(1, 0, 0))
					var it2: Array = it1.duplicate()
					it2[0] = ItemStack.named("emerald", 7).to_dict()
					d2["items"] = it2
					BlockEntities.set_data(self, cpos + Vector3i(1, 0, 0), d2)
					cs.pos = cpos
					player.yaw = 0.0
					player.pitch = 20.0
				open_screen(cs)
				if sname == "largechest":
					print("[screen] large chest rows %d title %s slot0 %s slot27 %s" % [cs.rows, cs.title, cs.items[0].name(), cs.items[27].name()])
					# break the left half: the right half must turn single
					await get_tree().create_timer(1.0).timeout
					var limg := get_viewport().get_texture().get_image()
					if limg != null:
						limg.save_png("user://autoplay/screen_largechest_open.png")
					var cpos2: Vector3i = cs.pos
					close_screen()
					set_block(cpos2.x + 1, cpos2.y, cpos2.z, 0)
					print("[screen] after breaking partner: %s" % Res.blocks.state_string(state_at(cpos2.x, cpos2.y, cpos2.z)))
		for i in 20:
			await get_tree().process_frame
		if autoplay.has("hover"):
			# dev: hover a GUI-pixel point (tooltips / highlights) before the screenshot
			var hp := str(autoplay["hover"]).split(",")
			var mm := InputEventMouseMotion.new()
			mm.position = Vector2(float(hp[0]), float(hp[1])) * float(UiKit.scale())
			mm.global_position = mm.position
			Input.warp_mouse(mm.position)
			Input.parse_input_event(mm)
			for i in 30:
				await get_tree().process_frame
		var simg: Image = get_viewport().get_texture().get_image() if DisplayServer.get_name() != "headless" else null
		if simg != null:
			simg.save_png("user://autoplay/screen_%s.png" % sname)
		print("[screen] %s size %s" % [sname, str(screen.size) if screen != null else "none"])
	if autoplay.has("sculk"):
		var so2 := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 8)
		var tws := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tws < 20000:
			await get_tree().process_frame
		var SB2 := Res.blocks
		player.mode = Player.Mode.SURVIVAL
		player.pos = Vector3(so2) + Vector3(0.5, 0, -3.5)
		player.prev_pos = player.pos
		set_block(so2.x, so2.y, so2.z, SB2.default_state("sculk_sensor"), false)
		set_block(so2.x + 1, so2.y, so2.z, SB2.default_state("redstone_lamp"), false)
		set_block(so2.x - 3, so2.y, so2.z + 2, SB2.state_of("minecraft:sculk_shrieker", {"can_summon": "true"}), false)
		level["warden_warning"] = 3
		set_block(so2.x, so2.y, so2.z - 2, SB2.default_state("stone"), false)
		for i in 5:
			await get_tree().process_frame
		_break_block(Vector3i(so2.x, so2.y, so2.z - 2), true)
		for i in 6:
			await get_tree().process_frame
		var s_st := state_at(so2.x, so2.y, so2.z)
		var lamp := state_at(so2.x + 1, so2.y, so2.z)
		var wardens := 0
		for e in entities.ents:
			if e.kind == "mob" and e.id == "warden":
				wardens += 1
		print("[sculk] sensor phase %s power %d, lamp lit %s, warning %d, wardens %d, darkness %s" % [SB2.get_prop(s_st, "sculk_sensor_phase"), Sculk.power_at(so2), SB2.get_prop(lamp, "lit"), int(level.get("warden_warning", -1)), wardens, str(player.effects.has("darkness"))])
	if autoplay.has("trial"):
		var to := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 8)
		var twt := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - twt < 20000:
			await get_tree().process_frame
		var TB := Res.blocks
		player.mode = Player.Mode.SURVIVAL
		player.pos = Vector3(to) + Vector3(0.5, 0, -4.5)
		player.prev_pos = player.pos
		set_block(to.x, to.y, to.z, TB.default_state("trial_spawner"), false)
		BlockEntities.set_data(self, to, {"id": "trial_spawner", "normal": "minecraft:trial_chamber/melee/zombie/normal"})
		set_block(to.x + 6, to.y, to.z, TB.default_state("spawner"), false)
		BlockEntities.set_data(self, to + Vector3i(6, 0, 0), {"id": "spawner", "mob": "zombie"})
		var vst := TB.state_of("minecraft:vault", {"facing": "north", "ominous": "false", "vault_state": "inactive"})
		print("[trial] default vault ominous=%s, explicit state %d" % [TB.get_prop(TB.default_state("vault"), "ominous"), vst])
		set_block(to.x - 4, to.y, to.z - 4, vst if vst > 0 else TB.default_state("vault"), false)
		BlockEntities.set_data(self, to + Vector3i(-4, 0, -4), {"id": "vault"})
		var kills := 0
		var ttr := game_time
		while game_time - ttr < 400:
			await get_tree().process_frame
			player.health = 20.0
			for e in entities.ents.duplicate():
				if e.kind == "mob" and bool(e.data.get("trial", false)) and not e.dead and game_time % 10 == 0:
					entities._damage(e, 100.0, player)
					kills += 1
		var ts_state := str(BlockEntities.get_data(self, to).get("state", "?"))
		var spawned_zombies := 0
		var items := 0
		for e in entities.ents:
			if e.kind == "mob" and e.id == "zombie" and not bool(e.data.get("trial", false)):
				spawned_zombies += 1
			if e.kind == "item":
				items += 1
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("trial_key", 1))
		print("[trial] holding '%s' (item id %d), vault block '%s'" % [player.inventory.held().name(), Res.items.id("trial_key"), Res.blocks.name_of(maxi(state_at(to.x - 4, to.y, to.z - 4), 0))])
		var opened := Trials.use_vault(self, to + Vector3i(-4, 0, -4), player)
		var tv := game_time
		while game_time - tv < 60:
			await get_tree().process_frame
		var items2 := 0
		for e in entities.ents:
			if e.kind == "item":
				items2 += 1
		print("[trial] trial kills %d, spawner state %s, ground items after trial %d, classic spawner zombies %d, vault opened %s, items after vault %d" % [kills, ts_state, items, spawned_zombies, str(opened), items2])
	if autoplay.has("raid"):
		var ro := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 8)
		var twr := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - twr < 20000:
			await get_tree().process_frame
		set_block(ro.x, ro.y, ro.z, Res.blocks.default_state("bell"), false)
		for i in 3:
			entities.spawn_mob("villager", Vector3(ro) + Vector3(i - 1, 0, 3))
		var patrol := Raids.spawn_patrol(self)
		player.mode = Player.Mode.CREATIVE
		player.add_effect("bad_omen", 0, 120000)
		var trd := game_time
		while game_time - trd < 700:
			await get_tree().process_frame
		var rinfo = level.get("raid")
		var raiders := 0
		var kinds := {}
		for e in entities.ents:
			if e.kind == "mob" and bool(e.data.get("raid", false)):
				raiders += 1
				kinds[e.id] = int(kinds.get(e.id, 0)) + 1
		print("[raid] patrol spawned %d, raid %s, raiders %d %s, bar %s" % [patrol, str(rinfo.get("wave", -1)) + "/" + str(rinfo.get("waves", -1)) if rinfo is Dictionary else "none", raiders, str(kinds), str((level.get("bossbars", {}) as Dictionary).get("raid", {}))])
	if autoplay.has("particles"):
		var po := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 2)
		player.pos = Vector3(po) + Vector3(0.5, 0, 0.5)
		player.prev_pos = player.pos
		var PB := Res.blocks
		for i in 5:
			set_block(po.x - 4 + i * 2, po.y, po.z + 3, PB.default_state("torch"), false)
		set_block(po.x, po.y, po.z + 6, PB.state_of("minecraft:campfire", {"lit": "true", "facing": "north", "signal_fire": "false", "waterlogged": "false"}), false)
		set_block(po.x + 3, po.y - 1, po.z + 5, PB.default_state("netherrack"), false)
		set_block(po.x + 3, po.y, po.z + 5, PB.default_state("fire"), false)
		var tp0 := game_time
		while game_time - tp0 < 30:
			await get_tree().process_frame
		entities.spawn_hearts(Vector3(po) + Vector3(-2.5, 1.5, 4.5))
		Particles.emit("explosion", Vector3(po) + Vector3(2.5, 2.5, 9))
		for i in 10:
			Particles.emit("crit", Vector3(po) + Vector3(-1.5, 1.2, 3.5), Vector3(randf_range(-1, 1), randf(), randf_range(-1, 1)) * 0.3)
		for fr in 4:
			await get_tree().process_frame
		var pimg := get_viewport().get_texture().get_image()
		if pimg != null:
			pimg.save_png("user://autoplay/particles_probe.png")
		var pk := {}
		for pp2 in Particles.instance.parts:
			pk[pp2[0]] = int(pk.get(pp2[0], 0)) + 1
		print("[particles] live kinds %s" % str(pk))
		var ex_info := []
		for pp in Particles.instance.parts:
			if pp[0] == "explosion":
				ex_info.append([pp[4], pp[5], pp[6], pp[8], Particles.instance.uv.has(pp[8])])
		print("[particles] live %d explosion %s, atlas sprites %d of %d, missing %s" % [Particles.instance.parts.size(), str(ex_info), Particles.instance.uv.size(), Particles.SPRITES.size(), str(Particles.SPRITES.filter(func(x): return not Particles.instance.uv.has(x)))])
	if autoplay.has("usetest"):
		var tw5 := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw5 < 30000:
			await get_tree().process_frame
		player.mode = Player.Mode.SURVIVAL
		target = {}
		var inv5 := player.inventory
		var wait := func(n: int) -> void:
			var g0 := game_time
			while game_time - g0 < n:
				await get_tree().process_frame
		# 1) eating takes 32 ticks
		player.food = 10
		inv5.set_slot(inv5.selected, ItemStack.named("cooked_beef", 2))
		auto_use = 40
		_use()
		await wait.call(5)
		var food_early := player.food
		var shot := get_viewport().get_texture().get_image()
		await wait.call(8)
		shot = get_viewport().get_texture().get_image()
		if shot != null:
			shot.save_png("user://autoplay/use_eat.png")
		await wait.call(30)
		print("[use] eat: food after 5 ticks %d, after 43 ticks %d, beef left %d" % [food_early, player.food, inv5.held().count])
		# 2) bow: full draw, release
		auto_use = 0
		await wait.call(2)
		inv5.set_slot(inv5.selected, ItemStack.named("bow", 1))
		inv5.set_slot(8 if inv5.selected != 8 else 7, ItemStack.named("arrow", 3))
		auto_use = 25
		_use()
		await wait.call(18)
		shot = get_viewport().get_texture().get_image()
		if shot != null:
			shot.save_png("user://autoplay/use_bow.png")
		await wait.call(10)
		var arrow_e = null
		for e5 in entities.ents:
			if e5.kind == "projectile" and e5.id == "arrow":
				arrow_e = e5
		print("[use] bow: arrow %s speed %.2f crit %s, arrows left %d, bow damage %d" % [str(arrow_e != null), arrow_e.vel.length() if arrow_e != null else 0.0, str(arrow_e.data.get("crit") if arrow_e != null else false), inv5.count_item(Res.items.id("arrow")), inv5.held().damage])
		# 3) crossbow: charge, load on release, fire on the next use
		inv5.set_slot(inv5.selected, ItemStack.named("crossbow", 1))
		auto_use = 30
		_use()
		await wait.call(32)
		var loaded := (inv5.held().components.get("minecraft:charged_projectiles", []) as Array).size()
		use_cooldown = 0
		_use()
		await wait.call(2)
		print("[use] crossbow: loaded %d, after firing %d, arrows left %d" % [loaded, (inv5.held().components.get("minecraft:charged_projectiles", []) as Array).size(), inv5.count_item(Res.items.id("arrow"))])
		# 4) shield in the offhand behind a sword: blocks frontal hits after 5 ticks
		inv5.set_slot(inv5.selected, ItemStack.named("iron_sword", 1))
		var dsh := ItemStack.named("shield", 1)
		dsh.components["minecraft:base_color"] = "red"
		dsh.components["minecraft:banner_patterns"] = [{"pattern": "minecraft:border", "color": "yellow"}, {"pattern": "minecraft:creeper", "color": "black"}]
		inv5.set_slot(Inventory.OFFHAND, dsh)
		auto_use = 40
		use_cooldown = 0
		_use()
		await wait.call(3)
		var early_block := UseItem.is_blocking(player)
		await wait.call(4)
		var hp0 := player.health
		player.invuln = 0
		var front_ok := not player.hurt(5.0, "mob", false, player.pos + player.look_dir() * 2.0)
		player.invuln = 0
		var back_hit := player.hurt(5.0, "mob", false, player.pos - player.look_dir() * 2.0)
		shot = get_viewport().get_texture().get_image()
		if shot != null:
			shot.save_png("user://autoplay/use_shield.png")
		print("[use] shield: using slot %d, blocking at 3 ticks %s, front blocked %s, back hurt %s, hp %.1f -> %.1f, shield damage %d" % [player.using_slot, str(early_block), str(front_ok), str(back_hit), hp0, player.health, inv5.get_slot(Inventory.OFFHAND).damage])
		auto_use = 0
	if autoplay.has("elytra"):
		var tw7 := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw7 < 30000:
			await get_tree().process_frame
		var wait7 := func(n: int) -> void:
			var g0 := game_time
			while game_time - g0 < n:
				await get_tree().process_frame
		_auto_input = true
		player.mode = Player.Mode.SURVIVAL
		player.inventory.set_slot(Inventory.ARMOR0 + 2, ItemStack.named("elytra", 1))
		player.pos.y += 80.0
		player.prev_pos = player.pos
		player.vel = Vector3.ZERO
		player.yaw = 0.0
		player.pitch = 10.0
		player.in_forward = 0.0
		player.in_jump = false
		await wait7.call(8)
		player.in_jump = true
		await wait7.call(2)
		player.in_jump = false
		var p0 := player.pos
		await wait7.call(60)
		var glide_h := Vector2(player.pos.x - p0.x, player.pos.z - p0.z).length()
		var glide_v := p0.y - player.pos.y
		var spd0 := player.vel.length()
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("firework_rocket", 3))
		Interaction.use_item(self, player.inventory.held())
		await wait7.call(10)
		var shot7 := get_viewport().get_texture().get_image()
		if shot7 != null:
			shot7.save_png("user://autoplay/elytra.png")
		await wait7.call(10)
		print("[elytra] gliding %s, 60 ticks: %.1f forward / %.1f down (glide ratio %.1f), speed %.2f -> after rocket %.2f, rockets left %d, elytra damage %d" % [str(player.fall_flying), glide_h, glide_v, glide_h / maxf(0.01, glide_v), spd0, player.vel.length(), player.inventory.held().count, player.inventory.get_slot(Inventory.ARMOR0 + 2).damage])
		# totem: lethal hit while holding a totem in the offhand
		player.inventory.set_slot(Inventory.ARMOR0 + 2, ItemStack.new())
		player.inventory.set_slot(Inventory.OFFHAND, ItemStack.named("totem_of_undying", 1))
		player.health = 3.0
		player.invuln = 0
		player.hurt(10.0, "mob")
		await wait7.call(8)
		shot7 = get_viewport().get_texture().get_image()
		if shot7 != null:
			shot7.save_png("user://autoplay/totem.png")
		print("[totem] dead %s health %.1f effects %s totem left %s" % [str(player.dead), player.health, str(player.effects.keys()), player.inventory.get_slot(Inventory.OFFHAND).name()])
		# name tag
		var nz = entities.spawn_mob("pig", player.pos + Vector3(0, 0, 2))
		var tag := ItemStack.named("name_tag", 1)
		tag.components["minecraft:custom_name"] = "Wilbur"
		player.inventory.set_slot(player.inventory.selected, tag)
		if nz != null:
			entities.player_interact(nz, player.inventory.held())
			print("[nametag] pig name %s persistent %s tag left %d" % [str(nz.data.get("CustomName", "")), str(nz.persistent), player.inventory.held().count])
		_auto_input = false
	if autoplay.has("count"):
		var tw9 := Time.get_ticks_msec()
		while (cm.pending_jobs() > 0 or cm.chunks.size() < 20) and Time.get_ticks_msec() - tw9 < 60000:
			await get_tree().process_frame
		var want := {}
		for nm in str(autoplay["count"]).split("+"):
			var bid := Res.blocks.block_id(nm)
			if bid >= 0:
				want[bid] = nm
		var counts := {}
		for key in cm.chunks:
			var ch: Chunk = cm.chunks[key]
			if ch.state < Chunk.DECORATED:
				continue
			for s in Coords.SECTIONS:
				var sec: Chunk.Section = ch.sections[s]
				var has := false
				for st in sec.pal:
					if st > 0 and want.has(Res.blocks.st_block[st]):
						has = true
				if not has:
					continue
				for y in 16:
					for z in 16:
						for x in 16:
							var st2 := ch.get_block(x, Coords.MIN_Y + s * 16 + y, z)
							if st2 > 0 and want.has(Res.blocks.st_block[st2]):
								var n2: String = want[Res.blocks.st_block[st2]]
								counts[n2] = int(counts.get(n2, 0)) + 1
		print("[count] %d chunks: %s" % [cm.chunks.size(), str(counts)])
	if autoplay.has("findbiome"):
		for bn in str(autoplay["findbiome"]).split("+"):
			var bid2: int = biomes.id(bn)
			var fb: Vector3i = gen.find_biome(bid2, 0, 64, 0, 4096, 32) if gen.has_method("find_biome") else Vector3i(0, -999999, 0)
			print("[findbiome] %s %s" % [bn, str(fb)])
	if autoplay.has("audit"):
		# worldgen audit: snowy grass vs snow above, leaf litter supports, unfrozen surface water in freezing biomes
		if autoplay.has("auditat"):   # --auditat=x,z: audit the area around that column instead of the spawn
			var ap: PackedStringArray = str(autoplay["auditat"]).split(",")
			player.mode = Player.Mode.SPECTATOR
			player.pos = Vector3(float(ap[0]), 120.0, float(ap[1]))
			player.prev_pos = player.pos
			_update_origin(true)
			for i in 30:
				await get_tree().process_frame
		var twa := Time.get_ticks_msec()
		while (cm.pending_jobs() > 0 or cm.chunks.size() < 40) and Time.get_ticks_msec() - twa < 90000:
			await get_tree().process_frame
		var B := Res.blocks
		var g_id := B.block_id("grass_block")
		var snow_ids := [B.block_id("snow"), B.block_id("snow_block"), B.block_id("powder_snow")]
		var litter_id := B.block_id("leaf_litter")
		var res := {"snowy_no_snow": 0, "snow_not_snowy": 0, "litter_on": {}, "cold_water_unfrozen": 0, "cold_water_frozen": 0, "examples": []}
		for key in cm.chunks:
			var ch: Chunk = cm.chunks[key]
			if ch.state < Chunk.DECORATED:
				continue
			for z in 16:
				for x in 16:
					var top := ch.heightmap[x + z * 16]
					for y in range(maxi(Coords.MIN_Y, top - 40), mini(Coords.MAX_Y - 1, top + 2)):
						var st := ch.get_block(x, y, z)
						if st <= 0:
							continue
						var bid: int = B.st_block[st]
						var above := ch.get_block(x, y + 1, z)
						var ab: int = B.st_block[above] if above > 0 else -1
						if bid == g_id:
							var snowy := B.get_prop(st, "snowy") == "true"
							if snowy and not (ab in snow_ids):
								res["snowy_no_snow"] += 1
								if (res["examples"] as Array).size() < 6:
									res["examples"].append("snowy grass %d,%d,%d above %s" % [ch.cx * 16 + x, y, ch.cz * 16 + z, B.name_of(above) if above > 0 else "air"])
							elif not snowy and ab in snow_ids:
								res["snow_not_snowy"] += 1
						elif bid == litter_id:
							var below := ch.get_block(x, y - 1, z)
							var bn := B.name_of(below) if below > 0 else "air"
							res["litter_on"][bn] = int(res["litter_on"].get(bn, 0)) + 1
					# surface water in a freezing biome (FreezeTopLayer: temperature < 0.15 at the top)
					var ty := top - 1
					var ts := ch.get_block(x, ty, z)
					var bio := ch.biome_at(x, top, z)
					if gen.biome_temperature_at(bio, 0, top, 0) < 0.15:
						if ts == B.WATER:
							res["cold_water_unfrozen"] += 1
							if (res["examples"] as Array).size() < 12:
								res["examples"].append("unfrozen water %d,%d,%d" % [ch.cx * 16 + x, ty, ch.cz * 16 + z])
						elif ts > 0 and B.name_of(ts) == "ice":
							res["cold_water_frozen"] += 1
		print("[audit] %d chunks: %s" % [cm.chunks.size(), JSON.stringify(res)])
	if autoplay.has("creaking"):
		var twc := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - twc < 30000:
			await get_tree().process_frame
		var waitc := func(n: int) -> void:
			var g0 := game_time
			while game_time - g0 < n:
				await get_tree().process_frame
		player.mode = Player.Mode.SURVIVAL
		day_time = 18000
		var CB := Res.blocks
		var hb := Vector3i(int(floor(player.pos.x)) + 6, int(floor(player.pos.y)), int(floor(player.pos.z)) + 6)
		var plog := CB.default_state("pale_oak_log")
		set_block(hb.x, hb.y, hb.z, plog)
		set_block(hb.x, hb.y + 1, hb.z, CB.default_state("creaking_heart"))
		set_block(hb.x, hb.y + 2, hb.z, plog)
		set_block(hb.x + 1, hb.y + 1, hb.z, plog)
		Creaking._scan_t = 0
		Creaking._tick_t = 0
		await waitc.call(60)
		var hs: int = state_at(hb.x, hb.y + 1, hb.z)
		var cr = Creaking._protector(self, hb + Vector3i(0, 1, 0))
		print("[creaking] heart %s night %s protector %s" % [CB.state_string(hs), str(Creaking.night(self)), str(cr != null)])
		if cr != null:
			cr.pos = player.pos + Vector3(10, 0, 0)
			cr.prev = cr.pos
			cr.vel = Vector3.ZERO
			# look straight at it: frozen
			var dv: Vector3 = cr.pos + Vector3(0, 1.5, 0) - player.eye_pos()
			player.yaw = rad_to_deg(atan2(-dv.x, dv.z))
			player.pitch = rad_to_deg(-asin(dv.normalized().y))
			var p0: Vector3 = cr.pos
			await waitc.call(30)
			var moved_watched: float = cr.pos.distance_to(p0)
			player.yaw += 180.0
			p0 = cr.pos
			await waitc.call(30)
			var moved_free: float = cr.pos.distance_to(p0)
			print("[creaking] distance to player %.1f, target_player %s, has_target %s" % [cr.pos.distance_to(player.pos), str(cr.target_player), str(cr.has_target)])
			var hp0: float = cr.hp
			cr.invuln = 0
			entities._damage(cr, 5.0, player)
			var resin := 0
			for dx in range(-3, 4):
				for dy in range(-3, 4):
					for dz in range(-3, 4):
						var rs: int = state_at(hb.x + dx, hb.y + 1 + dy, hb.z + dz)
						if rs > 0 and CB.name_of(rs) == "resin_clump":
							resin += 1
			print("[creaking] moved while watched %.2f, unwatched %.2f, hp %.1f -> %.1f, resin clumps %d" % [moved_watched, moved_free, hp0, cr.hp, resin])
			set_block(hb.x, hb.y + 1, hb.z, 0)
			await waitc.call(2)
			print("[creaking] after breaking the heart: alive %s" % str(not cr.dead))
	if autoplay.has("leadtest"):
		var tw8 := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw8 < 30000:
			await get_tree().process_frame
		var wait8 := func(n: int) -> void:
			var g0 := game_time
			while game_time - g0 < n:
				await get_tree().process_frame
		player.mode = Player.Mode.SURVIVAL
		var cow = entities.spawn_mob("cow", player.pos + Vector3(1.5, 0, 3))
		var zomb = entities.spawn_mob("zombie", player.pos + Vector3(-1.5, 0, 3))
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("lead", 2))
		entities.player_interact(cow, player.inventory.held())
		var zl := Leads.leashable(zomb) if zomb != null else false
		print("[lead] cow leashed %s, zombie leashable %s, leads left %d" % [str(cow.data.get("leash", "")), str(zl), player.inventory.held().count])
		await wait8.call(10)
		var shot8 := get_viewport().get_texture().get_image()
		if shot8 != null:
			shot8.save_png("user://autoplay/lead.png")
		# pull: walk the player away 8 blocks, the cow follows; 14 blocks snaps it
		player.pos += Vector3(0, 0, -5)
		player.prev_pos = player.pos
		var dist0: float = cow.pos.distance_to(player.pos)
		await wait8.call(40)
		var dist1: float = cow.pos.distance_to(player.pos)
		print("[lead] pulled from %.1f to %.1f, still leashed %s" % [dist0, dist1, str(cow.data.has("leash"))])
		player.pos += Vector3(0, 0, -20)
		player.prev_pos = player.pos
		await wait8.call(3)
		print("[lead] after moving 8 away: distance %.1f (leashed %s); after 28 away: leashed %s" % [dist1, str(cow.data.has("leash") or dist1 < 0), str(cow.data.has("leash"))])
		# XP bottle
		var xp0 := player.xp_total
		player.pos += Vector3(0, 0, 25)
		player.prev_pos = player.pos
		player.pitch = 80.0
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("experience_bottle", 1))
		Interaction.use_item(self, player.inventory.held())
		await wait8.call(60)
		print("[xpbottle] xp %d -> %d" % [xp0, player.xp_total])
	if autoplay.has("combat"):
		var tw6 := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw6 < 30000:
			await get_tree().process_frame
		player.mode = Player.Mode.SURVIVAL
		var wait6 := func(n: int) -> void:
			var g0 := game_time
			while game_time - g0 < n:
				await get_tree().process_frame
		var zs: Array = []
		for zi in 3:
			var z = entities.spawn_mob("zombie", player.pos + Vector3(-0.9 + zi * 0.9, 0, 2.0))
			if z != null:
				z.persistent = true
				z.noai = true
				zs.append(z)
		await wait6.call(2)
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("diamond_sword", 1))
		await wait6.call(1)
		var hp := zs.map(func(z): return z.hp)
		target = {"entity": zs[1]}
		_attack()
		var weak := zs.map(func(z): return snappedf(z.hp, 0.01))
		await wait6.call(6)
		var shot6 := get_viewport().get_texture().get_image()
		if shot6 != null:
			shot6.save_png("user://autoplay/combat_indicator.png")
		await wait6.call(10)
		for zi2 in zs.size():
			var z = zs[zi2]
			z.hp = 20.0
			z.invuln = 0
			z.pos = player.pos + Vector3(-0.9 + zi2 * 0.9, 0, 2.0)
			z.prev = z.pos
			z.vel = Vector3.ZERO
		var f6 := player.attack_strength(0.5)
		print("[combat] pre: on_ground %s sprint %s kind %s dpos %.3f fall %.2f zpos %s" % [player.on_ground, player.sprinting, Res.items.tool_kind[player.inventory.held().item], Vector2(player.pos.x - player.prev_pos.x, player.pos.z - player.prev_pos.z).length(), player.fall_distance, str(zs.map(func(z): return z.pos))])
		target = {"entity": zs[1]}
		_attack()
		var strong := zs.map(func(z): return snappedf(z.hp, 0.01))
		print("[combat] start %s, weak hit %s, strength before 2nd %.2f, strong hit + sweep %s" % [str(hp), str(weak), f6, str(strong)])
	if autoplay.has("maptest"):
		var tw3 := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw3 < 30000:
			await get_tree().process_frame
		player.mode = Player.Mode.SURVIVAL
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("map", 1))
		Interaction.use_item(self, player.inventory.held())
		var tmp := game_time
		while game_time - tmp < 140:
			await get_tree().process_frame
		var mdd: Dictionary = level["maps"]["0"]
		var mimg: Image = Maps.entry(self, 0)["img"]
		var drawn := 0
		var nodata := 0
		for yy in 128:
			for xx in 128:
				if mimg.get_pixel(xx, yy) != Color8(0xE4, 0xD9, 0xBC):
					drawn += 1
		for xx in range(0, 128, 8):
			var wx := int(mdd["x"]) - 64 + xx
			var chh: Chunk = cm.get_chunk(wx >> 4, (int(mdd["z"]) - 64 + 64) >> 4)
			if chh == null or chh.state < Chunk.DECORATED:
				nodata += 1
		print("[map] held %s id %d center %d,%d player px %d pz %d drawn %d, columns without data %d/16, chunks %d radius %d" % [player.inventory.held().name(), Maps.map_id(player.inventory.held()), int(mdd["x"]), int(mdd["z"]), int(floor(player.pos.x)) - int(mdd["x"]) + 64, int(floor(player.pos.z)) - int(mdd["z"]) + 64, drawn, nodata, cm.chunks.size(), cm.radius])
	if autoplay.has("book"):
		var wbk := ItemStack.named("written_book" if str(autoplay["book"]) == "read" else "writable_book", 1)
		wbk.components["minecraft:written_book_content"] = {"title": "Test", "author": "Player", "pages": ["The quick brown fox jumps over the lazy dog. Recraft 2 book pages wrap across several lines like Java.", "Second page"]}
		wbk.components["minecraft:writable_book_content"] = {"pages": ["Editable page one"]}
		player.inventory.set_slot(player.inventory.selected, wbk)
		Interaction.use_item(self, player.inventory.held())
	if autoplay.has("armor"):
		var inv := player.inventory
		for i in 4:
			inv.set_slot(Inventory.ARMOR0 + i, ItemStack.named(["iron_boots", "diamond_leggings", "golden_chestplate", "leather_helmet"][i], 1))
		var ap := player.pos + Vector3(-1.5, 0, 3)
		var z := entities.spawn_mob("zombie", ap)
		if z != null:
			z.data["armor"] = ["chainmail_boots", "iron_leggings", "diamond_chestplate", "netherite_helmet"]
			z.noai = true
			z.yaw = 180.0
			z.body_yaw = 180.0
		# trims through the smithing table logic: bolt/amethyst on an iron chestplate, coast/gold on iron leggings, iron on iron (darker)
		Enchanting.load_all()
		var tc := Enchanting.smith(ItemStack.named("bolt_armor_trim_smithing_template"), ItemStack.named("iron_chestplate"), ItemStack.named("amethyst_shard"))
		var tl := Enchanting.smith(ItemStack.named("coast_armor_trim_smithing_template"), ItemStack.named("diamond_leggings"), ItemStack.named("gold_ingot"))
		var th := Enchanting.smith(ItemStack.named("sentry_armor_trim_smithing_template"), ItemStack.named("iron_helmet"), ItemStack.named("iron_ingot"))
		print("[armor] trims: %s / %s / %s" % [str(tc.components.get("minecraft:trim")), str(tl.components.get("minecraft:trim")), str(th.components.get("minecraft:trim"))])
		var stand = MiscEntities.spawn_stand(entities, player.pos + Vector3(1.5, 0, 3), 180.0, [{}, tl.to_dict(), tc.to_dict(), th.to_dict()])
	if autoplay.has("hold"):
		player.mode = Player.Mode.SURVIVAL
		if str(autoplay["hold"]) != "none":
			player.inventory.set_slot(player.inventory.selected, ItemStack.named(str(autoplay["hold"]), 1))
	if autoplay.has("misc"):
		# decorative/explosive/fishing entity test (inside the spawn chunk)
		var tw2 := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw2 < 20000:
			await get_tree().process_frame
		var B2 := Res.blocks
		var o := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 2)
		player.pos = Vector3(o) + Vector3(0.5, 0, 0.5)
		player.prev_pos = player.pos
		player.mode = Player.Mode.SURVIVAL
		for x in range(-4, 5):
			for y in range(0, 4):
				set_block(o.x + x, o.y + y, o.z + 6, B2.default_state("stone"), false)
		MiscEntities.spawn_frame(entities, "item_frame", Vector3i(o.x - 2, o.y + 1, o.z + 5), Vector3i(0, 0, -1), 1, ItemStack.named("diamond_sword", 1))
		var painted := MiscEntities.place_painting(entities, Vector3i(o.x + 2, o.y + 1, o.z + 5), Vector3i(0, 0, -1))
		MiscEntities.spawn_stand(entities, Vector3(o.x + 0.5, o.y, o.z + 4.5), 180.0, [])
		set_block(o.x + 6, o.y, o.z + 12, B2.default_state("stone"), false)
		MiscEntities.spawn_tnt(entities, Vector3(o.x + 6.5, o.y + 1, o.z + 12.5), 30)
		for x in range(-6, -3):
			for z in range(1, 4):
				set_block(o.x + x, o.y - 1, o.z + z, B2.default_state("water"), false)
		player.inventory.set_slot(player.inventory.selected, ItemStack.named("fishing_rod", 1))
		MiscEntities.cast(entities, player)
		var hk = entities.hook
		hk.pos = Vector3(o.x - 4.5, o.y - 0.2, o.z + 2.5)
		hk.prev = hk.pos
		hk.vel = Vector3.ZERO
		var tm := game_time
		while game_time - tm < 10:
			await get_tree().process_frame
		hk.data["nibble"] = 15
		var inv_before := player.inventory.count_item(Res.items.id("cod")) + player.inventory.count_item(Res.items.id("salmon"))
		var cost := MiscEntities.reel(entities, player)
		while game_time - tm < 60:
			await get_tree().process_frame
		var kinds := {}
		for e in entities.ents:
			kinds[e.kind] = int(kinds.get(e.kind, 0)) + 1
		print("[misc] painting placed %s, entities %s, tnt crater %s, fishing cost %d caught %d (hook state was bobbing), items %s" % [str(painted), str(kinds), str(state_at(o.x + 6, o.y, o.z + 12) == 0), cost, int(player.stats.get("fish_caught", 0)), str(player.inventory.count_item(Res.items.id("cod")) + player.inventory.count_item(Res.items.id("salmon")) - inv_before)])
		player.mode = Player.Mode.CREATIVE
	if autoplay.has("cmdblock"):
		# command block test: redstone-triggered impulse -> chain, plus an always-active repeating counter
		var cb := Vector3i((int(floor(player.pos.x)) & ~15) + 4, int(floor(player.pos.y)), (int(floor(player.pos.z)) & ~15) + 8)
		var B := Res.blocks
		set_block(cb.x, cb.y, cb.z, B.state_of("minecraft:command_block", {"facing": "east", "conditional": "false"}), false)
		set_block(cb.x + 1, cb.y, cb.z, B.state_of("minecraft:chain_command_block", {"facing": "east", "conditional": "true"}), false)
		set_block(cb.x, cb.y, cb.z + 3, B.state_of("minecraft:repeating_command_block", {"facing": "up", "conditional": "false"}), false)
		level["allow_commands"] = true
		commands.execute("/scoreboard objectives add ticks dummy")
		var d1 := CommandBlocks.data(self, cb)
		d1["Command"] = "setblock ~ ~2 ~ gold_block"
		var d2 := CommandBlocks.data(self, cb + Vector3i(1, 0, 0))
		d2["Command"] = "setblock ~ ~2 ~ diamond_block"
		d2["auto"] = true
		var d3 := CommandBlocks.data(self, cb + Vector3i(0, 0, 3))
		d3["Command"] = "scoreboard players add #counter ticks 1"
		d3["auto"] = true
		set_block(cb.x, cb.y, cb.z - 1, B.default_state("redstone_block"))
		var tc := game_time
		while game_time - tc < 40:
			await get_tree().process_frame
		print("[cmdblock] impulse placed %s, chain placed %s, repeating counter %s after %d ticks" % [B.name_of(maxi(state_at(cb.x, cb.y + 2, cb.z), 0)), B.name_of(maxi(state_at(cb.x + 1, cb.y + 2, cb.z), 0)), str(commands._get_score("#counter", "ticks")), game_time - tc])
	if autoplay.has("beacon"):
		# beacon test: 2-level iron pyramid 6 blocks ahead, speed selected, wait for the 80-tick pulse
		var bp := Vector3i((int(floor(player.pos.x)) & ~15) + 8, int(floor(player.pos.y)) + 2, (int(floor(player.pos.z)) & ~15) + 8)
		player.pos = Vector3(bp.x + 0.5, player.pos.y, bp.z - 7.5)
		player.prev_pos = player.pos
		for i in range(1, 3):
			for x in range(-i, i + 1):
				for z in range(-i, i + 1):
					set_block(bp.x + x, bp.y - i, bp.z + z, Res.blocks.default_state("iron_block"), false)
		set_block(bp.x, bp.y, bp.z, Res.blocks.default_state("beacon"), false)
		BlockEntities.set_data(self, bp, {"id": "beacon", "levels": 0, "primary": "speed", "secondary": ""})
		var tb := game_time
		while game_time - tb < 100:
			await get_tree().process_frame
		print("[beacon] levels %d, active %s, player speed effect %s" % [int(BlockEntities.get_data(self, bp).get("levels", 0)), str(Beacons.active.has(bp)), str(player.effects.has("speed"))])
	if autoplay.has("vehicle"):
		# vehicle test: water channel or rail line along +z, then ride it for 4 s
		var vk := str(autoplay["vehicle"])
		var tw := Time.get_ticks_msec()
		while cm.pending_jobs() > 0 and Time.get_ticks_msec() - tw < 20000:
			await get_tree().process_frame
		var bx := (int(floor(player.pos.x)) & ~15) + 6   # stay inside the (loaded) spawn chunk column
		var by := int(floor(player.pos.y))
		var bz := int(floor(player.pos.z))
		var water := Res.blocks.default_state("water")
		var rail := Res.blocks.state_of("minecraft:rail", {"shape": "north_south"})
		var prail := Res.blocks.state_of("minecraft:powered_rail", {"shape": "north_south", "powered": "true"})
		for dz in range(1, 80):
			for dx in range(-1, 2):
				if vk == "boat":
					set_block(bx + dx, by - 1, bz + dz, water, false)
			if vk == "minecart":
				set_block(bx, by, bz + dz, prail if dz % 8 == 1 else rail, false)
		var cart_id := str(autoplay.get("cart", "minecart"))
		var veh = Vehicles.spawn(entities, vk, "oak_boat" if vk == "boat" else cart_id, Vector3(bx + 0.5, by - 0.4 if vk == "boat" else by + 0.0625, bz + 2.5), 0.0)
		if cart_id == "furnace_minecart":
			veh.data["fuel"] = 3600
			veh.data["push"] = [0.0, 1.0]
		else:
			Taming.mount(entities, veh, player)
		player.yaw = 0.0
		_auto_input = true
		player.in_forward = 1.0
		var vs: Vector3 = veh.pos
		var vt := game_time
		while game_time - vt < 80:
			await get_tree().process_frame
		print("[vehicle] %s moved %.1f blocks in 80 ticks (speed %.2f b/t); rider at %s" % [vk, Vector2(veh.pos.x - vs.x, veh.pos.z - vs.z).length(), Vector2(veh.vel.x, veh.vel.z).length(), str(player.pos)])
		player.in_forward = 0.0
	if autoplay.has("ride"):
		# riding test: tamed + saddled mount, ride forward for 3 s
		var mount := entities.spawn_mob(str(autoplay["ride"]), player.pos + Vector3(0, 0, 2))
		if mount != null:
			mount.data["owner"] = Taming.owner_name()
			mount.data["saddle"] = true
			if autoplay.has("harmor"):
				mount.data["horse_armor"] = ItemStack.named(str(autoplay["harmor"]), 1).to_dict()
			Taming.mount(entities, mount, player)
			_auto_input = true
			player.in_forward = 1.0
			if mount.id in Taming.STEER_ITEM:
				player.inventory.set_slot(player.inventory.selected, ItemStack.named(Taming.STEER_ITEM[mount.id], 1))
			var start := mount.pos
			var tr := game_time
			while game_time - tr < 60:
				await get_tree().process_frame
			print("[ride] %s moved %.1f blocks in 60 ticks; rider at %s, mount at %s" % [mount.id, Vector2(mount.pos.x - start.x, mount.pos.z - start.z).length(), str(player.pos), str(mount.pos)])
			player.in_forward = 0.0
			if autoplay.has("hscreen"):
				Taming.open_inventory(entities, mount)
				for i in 10:
					await get_tree().process_frame
				var himg := get_viewport().get_texture().get_image()
				if himg != null:
					himg.save_png("user://autoplay/screen_horse.png")
				close_screen()
	if autoplay.has("cam"):
		var cp: PackedStringArray = str(autoplay["cam"]).split(",")
		player.mode = Player.Mode.CREATIVE if autoplay.has("survival") else Player.Mode.SPECTATOR
		player.pos = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
		player.prev_pos = player.pos
		_update_origin(true)
		var cw0 := Time.get_ticks_msec()
		for i in 200:
			await get_tree().process_frame
		# --camwait=1: also wait until the chunks around the camera are generated (far --cam positions)
		while autoplay.has("camwait") and cm.pending_jobs() > 0 and Time.get_ticks_msec() - cw0 < 60000:
			await get_tree().process_frame
		if autoplay.has("cmds"):   # --cmds="fill ...;setblock ...": build a test scene before the screenshot (render checks)
			for cl0 in str(autoplay["cmds"]).split(";"):
				var cl := cl0.replace("+", " ").strip_edges()   # '+' = space (command-line safe)
				if cl != "":
					print("[cmds] %s -> %s" % [cl, commands.execute(cl)])
			for i in 120:
				await get_tree().process_frame
			var cw1 := Time.get_ticks_msec()
			while autoplay.has("camwait") and cm.pending_jobs() > 0 and Time.get_ticks_msec() - cw1 < 60000:
				await get_tree().process_frame
			for i in (60 if autoplay.has("camwait") else 0):
				await get_tree().process_frame
		if autoplay.has("spawnov"):   # --spawnov=x,z: structure spawn override on the top nether brick of a column
			var so: PackedStringArray = str(autoplay["spawnov"]).split(",")
			var sx := int(so[0])
			var sz := int(so[1])
			for yy in range(120, 20, -1):
				if Res.blocks.name_of(maxi(0, state_at(sx, yy, sz))) == "nether_bricks" and state_at(sx, yy + 1, sz) == 0:
					for cat in ["monster", "creature"]:
						var ov = gen.structures.spawn_override(sx, yy + 1, sz, cat, "nether_bricks")
						print("[spawnov] %d,%d,%d %s -> %s" % [sx, yy + 1, sz, cat, str(ov)])
					break
			print("[spawnov] off-structure -> %s" % str(gen.structures.spawn_override(sx + 400, 64, sz + 400, "monster", "netherrack")))
		if autoplay.has("craftertest"):   # --craftertest=1: crafter -> chest in front, one log, redstone block power
			var cp0 := Vector3i(int(floor(player.pos.x)) + 3, int(floor(player.pos.y)) + 2, int(floor(player.pos.z)))
			var B0 := Res.blocks
			set_block(cp0.x, cp0.y, cp0.z, B0.with_prop(B0.default_state("crafter"), "orientation", "north_up"))
			BlockEntities.on_placed(self, cp0, state_at(cp0.x, cp0.y, cp0.z))
			set_block(cp0.x, cp0.y, cp0.z - 1, B0.default_state("chest"))
			BlockEntities.on_placed(self, cp0 + Vector3i(0, 0, -1), state_at(cp0.x, cp0.y, cp0.z - 1))
			var cd0 := BlockEntities.get_data(self, cp0)
			var it0: Array = cd0["items"]
			it0[0] = ItemStack.named("oak_log", 1).to_dict()
			cd0["items"] = it0
			BlockEntities.set_data(self, cp0, cd0)
			set_block(cp0.x + 1, cp0.y, cp0.z, B0.default_state("redstone_block"))
			var tw0 := game_time
			while game_time - tw0 < 20:
				await get_tree().process_frame
			var chest_items := []
			for ci in BlockEntities.get_data(self, cp0 + Vector3i(0, 0, -1)).get("items", []):
				var cs0 := ItemStack.from_dict(ci)
				if not cs0.is_empty():
					chest_items.append("%s x%d" % [cs0.name(), cs0.count])
			print("[craftertest] crafter state %s, crafter slot0 %s, chest %s" % [B0.state_string(state_at(cp0.x, cp0.y, cp0.z)), str(BlockEntities.get_data(self, cp0)["items"][0]), str(chest_items)])
		if autoplay.has("poolscan"):   # --poolscan=r: cave water (y < 50) with air beside / below, chunks within r of the camera
			var pr := int(autoplay["poolscan"])
			var pc0 := Vector2i(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4)
			var open := 0
			var total := 0
			var first := []
			var wst: int = Res.blocks.WATER
			for pcz in range(pc0.y - pr, pc0.y + pr + 1):
				for pcx in range(pc0.x - pr, pc0.x + pr + 1):
					var pch: Chunk = cm.get_chunk(pcx, pcz)
					if pch == null or pch.state < Chunk.DECORATED:
						continue
					for ly in range(-50, 50):
						for lz in 16:
							for lx in 16:
								if pch.get_block(lx, ly, lz) != wst:
									continue
								total += 1
								var wx := pcx * 16 + lx
								var wz := pcz * 16 + lz
								for dv in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(0, -1, 0)]:
									var ns: int = state_at(wx + dv.x, ly + dv.y, wz + dv.z)
									if ns == 0 or Res.blocks.name_of(ns) == "cave_air":
										open += 1
										if first.size() < 6:
											first.append(Vector3i(wx, ly, wz))
										break
			print("[poolscan] cave water %d, open to air %d, e.g. %s" % [total, open, str(first)])
		if autoplay.has("modebug"):   # --modebug=1: monument candidates near the player, stub biome / surroundings
			var sts: Structures = gen.structures
			for stx in sts.sets:
				if str(stx["name"]) != "ocean_monuments":
					continue
				var cfgm: Dictionary = stx["entries"][0]["cfg"]
				var nshow := 0
				var cands: Array = sts._candidates(stx, 0, 0, int(autoplay["modebug"]))
				print("[modebug] %d candidates, cfg type %s, biomes %d, placement %s" % [cands.size(), str(cfgm.get("type")), (cfgm["biomes"] as Dictionary).size(), str(stx["placement"])])
				for scm in cands:
					var bx := sts.biome_id_at(scm.x * 16 + 8, sts._stub_y(cfgm, scm.x * 16 + 8, scm.y * 16 + 8), scm.y * 16 + 8)
					if not (cfgm["biomes"] as Dictionary).has(bx):
						if nshow < 3:
							print("[modebug] %s stub biome %s rejected" % [str(scm), biomes.names[bx]])
							nshow += 1
						continue
					var ids: PackedInt32Array = Native.inst.tg_biomes_within(gen.native_tg, scm.x * 16 + 9, gen.sea_level, scm.y * 16 + 9, 29)[0]
					var names := []
					for bi in ids:
						names.append(biomes.names[bi])
					print("[modebug] %s stub %s ok=%s within %s" % [str(scm), biomes.names[bx], str(JavaPieces.monument_surroundings_ok(sts, scm)), str(names)])
					nshow += 1
					if nshow > 8:
						break
			print("[modebug] ring set %s" % str(JavaPieces._mo_ring.keys()))
		if autoplay.has("shdump"):   # --shdump=1: nearest stronghold's layout (piece kinds, portal room centre)
			var shc: Vector2i = gen.structures.nearest_stronghold(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4)
			var sht0 := Time.get_ticks_usec()
			var shr := JavaPieces.stronghold(gen.structures, shc)
			var kc := {}
			for pc in shr["pieces"]:
				kc[pc["el"]["k"]] = int(kc.get(pc["el"]["k"], 0)) + 1
			print("[shdump] start chunk %s, %d pieces in %.1f ms, portal centre %s, box %s, kinds %s" % [str(shc), (shr["pieces"] as Array).size(), (Time.get_ticks_usec() - sht0) / 1000.0, str(shr["center"]), str(shr["box"]), str(kc)])
			for pc2 in shr["pieces"]:
				if pc2["el"]["k"] == "portal_room":
					print("[shdump] portal room %s..%s facing %s" % [str(pc2["el"]["min"]), str(pc2["el"]["max"]), pc2["el"]["ori"]])
		if autoplay.has("mapshot"):   # --mapshot=1: hold a fresh filled map (player marker / map colours check)
			player.mode = Player.Mode.CREATIVE
			player.inventory.set_slot(player.inventory.selected, Maps.new_map(self, player.pos.x, player.pos.z))
			if autoplay.has("mapbanner"):   # --mapbanner=1: a named banner 12 blocks north-east, its marker toggled on
				var bp0 := Vector3i(int(floor(player.pos.x)) + 12, int(floor(player.pos.y)) + 3, int(floor(player.pos.z)) - 12)
				set_block(bp0.x, bp0.y, bp0.z, Res.blocks.default_state("red_banner"))
				var bd0 := BlockEntities.get_data(self, bp0).duplicate()
				bd0["CustomName"] = "Base"
				BlockEntities.set_data(self, bp0, bd0)
				print("[mapbanner] toggled %s" % str(Maps.toggle_banner(self, player.inventory.held(), bp0)))
			for i in 400:
				await get_tree().process_frame
		if autoplay.has("propline"):   # --propline=x0,x1,y,z: wall / fence connection props along a row
			var pl: PackedStringArray = str(autoplay["propline"]).split(",")
			for px in range(int(pl[0]), int(pl[1]) + 1):
				var ps := state_at(px, int(pl[2]), int(pl[3]))
				var props := []
				for pn in ["up", "north", "south", "west", "east"]:
					if Res.blocks.has_prop(ps, pn):
						props.append("%s=%s" % [pn, Res.blocks.get_prop(ps, pn)])
				print("[propline] x=%d %s %s (state %d)" % [px, Res.blocks.name_of(ps), " ".join(props), ps])
				if px == int(pl[0]) and ps > 0:
					print("[propline] props table %s" % str(Res.blocks.block_props[Res.blocks.st_block[ps]]))
					var cps := ShapeUpdates.computed(self, Vector3i(px, int(pl[2]), int(pl[3])), ps)
					print("[propline] computed -> %s (state %d), with_prop north none -> %s" % [str(Res.blocks.props_of(cps)), cps, str(Res.blocks.props_of(Res.blocks.with_prop(ps, "north", "none")))])
		if autoplay.has("dumpcol"):   # --dumpcol=x,z0,z1,y0,y1: block names of a vertical slice (worldgen checks)
			var dc: PackedStringArray = str(autoplay["dumpcol"]).split(",")
			for zz in range(int(dc[1]), int(dc[2]) + 1):
				var names: Array = []
				for yy in range(int(dc[3]), int(dc[4]) + 1):
					var dst := state_at(int(dc[0]), yy, zz)
					names.append(Res.blocks.name_of(dst) if dst > 0 else ("air" if dst == 0 else "?"))
				var bch := cm.get_chunk(int(dc[0]) >> 4, zz >> 4)
				var sb: int = bch.biome_at(int(dc[0]) & 15, 63, zz & 15) if bch != null else -1
				var fresh := -1
				if gen.has_method("biome_at_block"):
					fresh = gen.biome_at_block(DensityFunctions.Ctx.new(gen.dfc.node_count()), int(dc[0]), 63, zz)
				print("[dumpcol] x=%s z=%d y%s..%s: %s | stored biome %s, recomputed %s" % [dc[0], zz, dc[3], dc[4], ", ".join(names), biomes.names[sb] if sb >= 0 else "?", biomes.names[fresh] if fresh >= 0 else "?"])
		if autoplay.has("findbiome") and gen.has_method("biome_at_block"):   # --findbiome=name: nearest column of that biome (spiral, 32-block steps)
			var want := str(autoplay["findbiome"])
			var fctx := DensityFunctions.Ctx.new(gen.dfc.node_count())
			var found_at := Vector2i(1 << 30, 0)
			for ring in range(0, 120):
				for k in range(-ring, ring + 1):
					for pt in [Vector2i(k, -ring), Vector2i(k, ring), Vector2i(-ring, k), Vector2i(ring, k)]:
						var bxz: Vector2i = pt * 32
						var bid: int = gen.biome_at_block(fctx, bxz.x, 70, bxz.y)
						if bid >= 0 and biomes.names[bid].trim_prefix("minecraft:") == want:
							found_at = bxz
							break
					if found_at.x != (1 << 30):
						break
				if found_at.x != (1 << 30):
					break
			print("[findbiome] %s at %s, surface y %d" % [want, str(found_at), gen.surface_height(found_at.x, found_at.y) if found_at.x != (1 << 30) else -1])
		if autoplay.has("ffhcheck") and gen.get("structures") != null:   # --ffhcheck=1: structure ground height vs generated terrain
			var sts2 = gen.structures
			var dh := {}
			var terr := {}
			for tn in ["stone", "deepslate", "dirt", "grass_block", "sand", "red_sand", "gravel", "water", "podzol", "mycelium", "snow_block", "terracotta", "sandstone", "coarse_dirt", "mud", "clay", "andesite", "diorite", "granite", "tuff", "calcite", "powder_snow", "packed_ice", "ice", "pale_moss_block", "moss_block", "rooted_dirt", "lava", "red_sandstone", "white_terracotta", "orange_terracotta", "yellow_terracotta", "brown_terracotta", "red_terracotta", "light_gray_terracotta", "dripstone_block", "suspicious_sand", "suspicious_gravel"]:
				terr[tn] = true
			var px0 := int(floor(player.pos.x))
			var pz0 := int(floor(player.pos.z))
			var worst := []
			for gx in range(-60, 61, 5):
				for gz in range(-60, 61, 5):
					var wx := px0 + gx
					var wz := pz0 + gz
					var ch := cm.get_chunk(wx >> 4, wz >> 4)
					if ch == null or ch.state < Chunk.DECORATED:
						continue
					var top := Coords.MIN_Y
					for yy in range(Coords.MAX_Y - 1, Coords.MIN_Y, -1):
						var ts := state_at(wx, yy, wz)
						if ts > 0 and terr.has(Res.blocks.name_of(ts)):
							top = yy
							break
					var ffh: int = sts2.first_free_height(wx, wz)
					var dd := ffh - (top + 1)
					dh[dd] = int(dh.get(dd, 0)) + 1
					if absi(dd) >= 2 and worst.size() < 12:
						worst.append("(%d,%d) ffh %d terrain %d" % [wx, wz, ffh, top + 1])
			var ks := dh.keys()
			ks.sort()
			print("[ffhcheck] diff histogram: %s" % ", ".join(ks.map(func(k): return "%d:%d" % [k, dh[k]])))
			print("[ffhcheck] worst: %s" % "; ".join(worst))
		if autoplay.has("raincheck") and weather_fx != null and DisplayServer.get_name() != "headless":
			# --raincheck=1: the same frozen rain drawn as visible-texel runs (current) and as whole column quads (previous
			# shader): images must match (third shot = current again, the noise floor)
			player.yaw = float(autoplay.get("yaw", "0"))
			player.pitch = float(autoplay.get("pitch", "40"))
			raining = true
			rain = 1.0
			gamerules["doWeatherCycle"] = false
			for i in 80:
				await get_tree().process_frame
			weather_fx.frozen = true
			var rimgs: Array = []
			for mode in [0, 1, 0]:
				weather_fx.set_full_quad(mode == 1)
				for i in 4:
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				rimgs.append(get_viewport().get_texture().get_image())
			var rdir := "user://autoplay"
			DirAccess.make_dir_recursive_absolute(rdir)
			for ri in rimgs.size():
				(rimgs[ri] as Image).save_png(rdir.path_join("raincheck_%d.png" % ri))
			for pair in [[0, 1], [0, 2]]:
				var ia: Image = rimgs[pair[0]]
				var ib: Image = rimgs[pair[1]]
				var nd := 0
				var md := 0.0
				var dimg := Image.create(ia.get_width(), ia.get_height(), false, Image.FORMAT_RGB8)
				var dlist: PackedStringArray = []
				for py in range(90, ia.get_height()):   # (the top rows hold the FPS counter text)
					for px in range(0, ia.get_width()):
						var ca := ia.get_pixel(px, py)
						var cb := ib.get_pixel(px, py)
						var dd := maxf(maxf(absf(ca.r - cb.r), absf(ca.g - cb.g)), absf(ca.b - cb.b))
						if dd > 0.0:
							nd += 1
							md = maxf(md, dd)
							dimg.set_pixel(px, py, Color(1, 0, 0) if ca.get_luminance() > cb.get_luminance() else Color(0, 1, 0))
							if dlist.size() < 12:
								dlist.append("(%d,%d) %s vs %s" % [px, py, ca.to_html(false), cb.to_html(false)])
				dimg.save_png(rdir.path_join("raincheck_diff_%d_%d.png" % [pair[0], pair[1]]))
				print("[raincheck]   e.g. ", ", ".join(dlist))
				print("[raincheck] shots %d vs %d: %d pixels differ, max channel difference %d / 255" % [pair[0], pair[1], nd, roundi(md * 255.0)])
			# GPU time per frame (viewport timer, 120 frames each, twice): visible-texel runs, whole quads, no weather
			var gvp := get_viewport().get_viewport_rid()
			RenderingServer.viewport_set_measure_render_time(gvp, true)
			var gsum := {"runs": 0.0, "full quads": 0.0, "none": 0.0}
			for rep in 2:
				for gm in ["runs", "full quads", "none"]:
					weather_fx.set_full_quad(gm == "full quads")
					weather_fx.visible = gm != "none"
					for i in 20:
						await get_tree().process_frame
					for i in 120:
						await get_tree().process_frame
						gsum[gm] += RenderingServer.viewport_get_measured_render_time_gpu(gvp) / 240.0
			weather_fx.visible = true
			weather_fx.set_full_quad(false)
			print("[raincheck] gpu ms per frame: visible-texel runs %.3f, whole column quads %.3f, no weather %.3f" % [gsum["runs"], gsum["full quads"], gsum["none"]])
			weather_fx.frozen = false
		if autoplay.has("locatest") and gen.get("structures") != null:   # --locatest=name: synchronous structure locate
			for lname0 in str(autoplay["locatest"]).split(","):
				var lname := lname0.get_slice(":", 0)   # name[:radius in chunks]
				var lrad := int(lname0.get_slice(":", 1)) if lname0.contains(":") else 100
				var tl0 := Time.get_ticks_usec()
				var lr: Dictionary = gen.structures.locate(lname, int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4, lrad)
				print("[locatest] %s %s in %.1f ms" % [lname, str(lr), (Time.get_ticks_usec() - tl0) / 1000.0])
		if autoplay.has("brushtest"):   # --brushtest=1: brush a suspicious sand block with desert-well loot to completion
			var bpos := Vector3i(int(floor(player.pos.x)) + 2, int(floor(player.pos.y)), int(floor(player.pos.z)))
			set_block(bpos.x, bpos.y - 1, bpos.z, Res.blocks.default_state("stone"))
			set_block(bpos.x, bpos.y, bpos.z, Res.blocks.default_state("suspicious_sand"))
			BlockEntities.set_data(self, bpos, {"id": "suspicious_sand", "loot_table": "archaeology/desert_well"})
			player.mode = Player.Mode.SURVIVAL
			player.inventory.set_slot(player.inventory.selected, ItemStack.named("brush", 1))
			var n_items0: int = entities.ents.filter(func(e): return e.kind == "item").size()
			var dusted_seen := {}
			target = {"pos": bpos, "state": state_at(bpos.x, bpos.y, bpos.z), "normal": Vector3(-1, 0, 0), "point": Vector3(bpos) + Vector3(0, 0.5, 0.5)}
			var started := UseItem.start(self, player, player.inventory.selected)
			for t in 220:
				var cs := state_at(bpos.x, bpos.y, bpos.z)
				if Res.blocks.name_of(cs) != "suspicious_sand":
					break
				dusted_seen[Res.blocks.get_prop(cs, "dusted")] = true
				target["state"] = cs
				game_time += 1
				UseItem.tick(self, player, true)
			var fin := Res.blocks.name_of(state_at(bpos.x, bpos.y, bpos.z))
			var drops: Array = entities.ents.filter(func(e): return e.kind == "item")
			print("[brushtest] started %s, block now %s, dusted seen %s, items %d -> %d (%s), brush damage %d" % [started, fin, str(dusted_seen.keys()),
				n_items0, drops.size(), drops[drops.size() - 1].stack.name() if drops.size() > n_items0 else "-", player.inventory.held().damage])
		if autoplay.has("leafseam"):   # --leafseam=block: continuity of that block across chunk seams vs interior columns
			var lname := str(autoplay["leafseam"])
			var lid: int = Res.blocks.block_id(lname)
			var seam := [0, 0]
			var inner := [0, 0]
			var lcx := int(floor(player.pos.x)) >> 4
			var lcz := int(floor(player.pos.z)) >> 4
			var seam_cols := {}
			for xx in range((lcx - 4) * 16, (lcx + 4) * 16):
				for zz in range((lcz - 4) * 16, (lcz + 4) * 16):
					var lc := cm.get_chunk(xx >> 4, zz >> 4)
					var lc2 := cm.get_chunk((xx + 1) >> 4, zz >> 4)
					if lc == null or lc2 == null or lc.state < Chunk.DECORATED or lc2.state < Chunk.DECORATED:
						continue
					for yy in range(60, 200):
						var a0 := state_at(xx, yy, zz)
						if a0 <= 0 or Res.blocks.st_block[a0] != lid:
							continue
						var a1 := state_at(xx + 1, yy, zz)
						var same := 1 if a1 > 0 and Res.blocks.st_block[a1] == lid else 0
						if (xx & 15) == 15:
							seam[0] += 1
							seam[1] += same
							if same == 0:
								seam_cols[Vector2i(xx, zz)] = int(seam_cols.get(Vector2i(xx, zz), 0)) + 1
						elif (xx & 15) == 7:
							inner[0] += 1
							inner[1] += same
			var worst_cols := seam_cols.keys().filter(func(k): return seam_cols[k] >= 3).slice(0, 8)
			print("[leafseam] %s: seam x15->x0 %d/%d continue (%.2f), interior x7->x8 %d/%d (%.2f); seam columns with >=3 breaks: %s" % [lname, seam[1], seam[0],
				float(seam[1]) / maxf(1, seam[0]), inner[1], inner[0], float(inner[1]) / maxf(1, inner[0]), str(worst_cols)])
		if autoplay.has("runstat"):   # --runstat=block: histogram of vertical run lengths of that block in loaded chunks
			var rname := str(autoplay["runstat"])
			var hist := {}
			var nch := 0
			var pcx := int(floor(player.pos.x)) >> 4
			var pcz := int(floor(player.pos.z)) >> 4
			for rcx in range(pcx - 4, pcx + 5):
				for rcz in range(pcz - 4, pcz + 5):
					var rc := cm.get_chunk(rcx, rcz)
					if rc == null or rc.state < Chunk.DECORATED:
						continue
					nch += 1
					for lx in 16:
						for lz in 16:
							var run := 0
							for yy in range(Coords.MAX_Y - 1, Coords.MIN_Y, -1):
								var rs := state_at(rcx * 16 + lx, yy, rcz * 16 + lz)
								if rs > 0 and Res.blocks.name_of(rs) == rname:
									run += 1
								elif run > 0:
									hist[run] = int(hist.get(run, 0)) + 1
									run = 0
			var keys := hist.keys()
			keys.sort()
			print("[runstat] %s in %d chunks: %s" % [rname, nch, ", ".join(keys.map(func(k): return "%d:%d" % [k, hist[k]]))])
		if autoplay.has("regionhash"):   # --regionhash=cx0,cz0,cx1,cz1: per-chunk block hashes (generation / reload determinism)
			var rh: PackedStringArray = str(autoplay["regionhash"]).split(",")
			var rw := Time.get_ticks_msec()
			var all_ok := false
			while not all_ok and Time.get_ticks_msec() - rw < 60000:
				all_ok = true
				for hcx in range(int(rh[0]), int(rh[2]) + 1):
					for hcz in range(int(rh[1]), int(rh[3]) + 1):
						var hc := cm.get_chunk(hcx, hcz)
						if hc == null or hc.state < Chunk.DECORATED:
							all_ok = false
				if not all_ok:
					await get_tree().process_frame
			var lines: Array = []
			var logs := 0
			for hcx in range(int(rh[0]), int(rh[2]) + 1):
				for hcz in range(int(rh[1]), int(rh[3]) + 1):
					var hc2 := cm.get_chunk(hcx, hcz)
					if hc2 == null or hc2.state < Chunk.DECORATED:
						lines.append("%d,%d:-" % [hcx, hcz])
						continue
					var col := Chunk.snapshot_column(hc2.snapshot())
					var nlog := 0
					var lava_told := false
					for vi in col.size():
						var v := col[vi]
						if v > 0:
							var vn := Res.blocks.name_of(v)
							if vn.ends_with("_log"):
								nlog += 1
							elif vn == "lava" and (vi >> 8) - 64 >= 55 and not lava_told:
								lava_told = true
								print("[regionhash] surface lava in chunk %d,%d at %d,%d,%d" % [hcx, hcz, hcx * 16 + (vi & 15), (vi >> 8) - 64, hcz * 16 + ((vi >> 4) & 15)])
					logs += nlog
					lines.append("%d,%d:%x/%d%s" % [hcx, hcz, hash(col), nlog, "d" if hc2.from_disk else ""])
			print("[regionhash] logs %d | %s" % [logs, " ".join(lines)])
		if autoplay.has("waterscan"):   # --waterscan=x0,z0,x1,z1: air below sea level touching water (air-pocket checks)
			var ws: PackedStringArray = str(autoplay["waterscan"]).split(",")
			var ww := Time.get_ticks_msec()
			while cm.pending_jobs() > 0 and Time.get_ticks_msec() - ww < 90000:
				await get_tree().process_frame
			var nfound := 0
			var kinds := {}
			for wx in range(int(ws[0]), int(ws[2]) + 1):
				for wz in range(int(ws[1]), int(ws[3]) + 1):
					for wy in range(30, 63):
						var wst := state_at(wx, wy, wz)
						if wst < 0:
							continue
						var wname: String = Res.blocks.name_of(wst)
						# kelp / seagrass in a column: report the cell's top neighbour if it is air (plant poking out)
						if wname == "lava":
							for ld in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, 1, 0)]:
								var lst := state_at(wx + ld.x, wy + ld.y, wz + ld.z)
								if lst > 0 and (Res.blocks.st_flags[lst] & BlockRegistry.F_LIQUID) != 0 and (Res.blocks.st_flags[lst] & BlockRegistry.F_LAVA) == 0:
									kinds["lava touching water"] = int(kinds.get("lava touching water", 0)) + 1
									if int(kinds["lava touching water"]) <= 5:
										print("[waterscan] lava touching water at %d,%d,%d" % [wx, wy, wz])
									break
						if wname in ["kelp", "kelp_plant", "seagrass", "tall_seagrass"]:
							var up := state_at(wx, wy + 1, wz)
							if up == 0 and wy < 62:
								kinds["plant under air"] = int(kinds.get("plant under air", 0)) + 1
								if nfound < 25:
									print("[waterscan] %s at %d,%d,%d has air above" % [wname, wx, wy, wz])
								nfound += 1
						if wst != 0:
							continue
						var wet := 0
						var near: Array = []
						for nd in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, 1, 0)]:
							var nst := state_at(wx + nd.x, wy + nd.y, wz + nd.z)
							if nst > 0 and (Res.blocks.st_flags[nst] & (BlockRegistry.F_FLUID | BlockRegistry.F_WATERLOGGED)) != 0:
								wet += 1
							near.append(Res.blocks.name_of(nst) if nst > 0 else "air")
						if wet > 0:
							var key := str(near)
							kinds[key] = int(kinds.get(key, 0)) + 1
							if nfound < 25:
								print("[waterscan] air at %d,%d,%d neighbours -x +x -z +z up: %s" % [wx, wy, wz, ", ".join(near)])
							nfound += 1
			print("[waterscan] %d found; kinds %s" % [nfound, str(kinds).left(1500)])
		if autoplay.has("mobprobe"):   # --mobprobe=N: N cows + N zombies (night) near the player for 30 s
			var mpw := Time.get_ticks_msec()
			while cm.pending_jobs() > 0 and Time.get_ticks_msec() - mpw < 60000:
				await get_tree().process_frame
			player.mode = Player.Mode.SURVIVAL
			day_time = 18000
			var nmob := int(autoplay["mobprobe"])
			var mobs: Array = []
			var rngp := RandomNumberGenerator.new()
			rngp.seed = 7
			for i in nmob * 2:
				var mx := player.pos.x + rngp.randf_range(-14, 14)
				var mz := player.pos.z + rngp.randf_range(-14, 14)
				var my := int(player.pos.y) + 24
				while my > Coords.MIN_Y and not (state_at(floori(mx), my - 1, floori(mz)) > 0 and Res.blocks.collides(state_at(floori(mx), my - 1, floori(mz)))):
					my -= 1
				var mob = entities.spawn_mob("cow" if i < nmob else "zombie", Vector3(mx, my, mz))
				if mob != null:
					mobs.append(mob)
			MobPath.stat_reset()
			entities.nav_max_us = 0
			var start_pos := {}
			for mob in mobs:
				start_pos[mob] = mob.pos
			var last_age := {}
			var big_turns := 0
			var head_off := 0
			var samples := 0
			var pitched := 0
			var looking := 0
			var t_end := Time.get_ticks_msec() + 30000
			while Time.get_ticks_msec() < t_end:
				await get_tree().process_frame
				for mob in mobs:
					if mob.dead or last_age.get(mob, -1) == mob.age:
						continue
					last_age[mob] = mob.age
					samples += 1
					if absf(MobControl.wrap_deg(mob.body_yaw - mob.body_yaw_o)) > 45.0:
						big_turns += 1
					if absf(MobControl.wrap_deg(mob.head_yaw - mob.body_yaw)) > 5.0:
						head_off += 1
					if absf(mob.head_pitch) > 1.0:
						pitched += 1
					if mob.look_goal == 1 or mob.target_player:
						looking += 1
			var dists: Array = []
			for mob in mobs:
				dists.append(snappedf(Vector2(mob.pos.x - start_pos[mob].x, mob.pos.z - start_pos[mob].z).length(), 0.1))
			var nj := maxi(MobPath.stat_jobs, 1)
			print("[mobprobe] mobs %d; path searches %d (reached %d), avg %d us, max %d us, avg nodes %.1f; worst nav step %d us" % [mobs.size(), MobPath.stat_jobs, MobPath.stat_reached, MobPath.stat_us / nj, MobPath.stat_max_us, float(MobPath.stat_nodes) / nj, entities.nav_max_us])
			print("[mobprobe] displacement %s" % str(dists))
			print("[mobprobe] tick samples %d: body turn > 45 deg %d, head off body %d, head pitched %d, looking at player %d" % [samples, big_turns, head_off, pitched, looking])
			print("[mobprobe] native split us (grid, class table, search, convert): %s; player %s mode %d" % [str(MobPath.stat_t), str(player.pos), player.mode])
			print("[mobprobe] done")
		if autoplay.has("meshprobe"):   # --meshprobe=cx,cz,g: translucent quads of one mesh group lying on its chunk border planes
			var mp: PackedStringArray = str(autoplay["meshprobe"]).split(",")
			var mc := cm.get_chunk(int(mp[0]), int(mp[1]))
			var mw := Time.get_ticks_msec()
			while (mc == null or not mc.light_valid or cm.pending_jobs() > 0) and Time.get_ticks_msec() - mw < 30000:
				await get_tree().process_frame
				mc = cm.get_chunk(int(mp[0]), int(mp[1]))
			print("[meshprobe] chunk %s state %s lit %s halo %d" % [mp, str(mc.state) if mc != null else "-", str(mc.light_valid) if mc != null else "-", mc.light_halo_secs.size() if mc != null else -1])
			if mc != null and mc.light_valid and mc.light_halo_secs.size() == Coords.SECTIONS:
				var msn: Array = []
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var mn := cm.get_chunk(mc.cx + dx, mc.cz + dz)
						msn.append(mn.snapshot() if mn != null else null)
				var mres := Mesher.build({"snaps": msn, "light": mc.light_halo_secs, "group": int(mp[2]), "blocks": Res.blocks, "tints": cm._tints(mc)})
				for cls in ["opaque", "cutout", "translucent"]:
					var ma: Array = mres.get(cls, [])
					if ma.is_empty():
						continue
					var mv: PackedVector3Array = ma[Mesh.ARRAY_VERTEX]
					var cus: PackedByteArray = ma[Mesh.ARRAY_CUSTOM0]
					var nb := 0
					for q in range(0, mv.size(), 4):
						var a: Vector3 = mv[q]
						var on_x := absf(a.x) < 0.001 or absf(a.x - 16.0) < 0.001
						var on_z := absf(a.z) < 0.001 or absf(a.z - 16.0) < 0.001
						var flat_x := true
						var flat_z := true
						for k in 4:
							flat_x = flat_x and absf(mv[q + k].x - a.x) < 0.001
							flat_z = flat_z and absf(mv[q + k].z - a.z) < 0.001
						if (on_x and flat_x) or (on_z and flat_z):
							nb += 1
							if nb <= 12:
								var lay := PackedByteArray([cus[q * 8], cus[q * 8 + 1]]).decode_half(0)
								print("[meshprobe] %s border quad %s %s %s %s layer %s" % [cls, str(mv[q]), str(mv[q + 1]), str(mv[q + 2]), str(mv[q + 3]), str(lay)])
					print("[meshprobe] %s: %d quads, %d on border planes" % [cls, mv.size() / 4, nb])
					if cls == "translucent":
						# top-face coverage of the border columns (x = 0 and x = 15) at the top of each column's ice
						var cov := {}
						for q2 in range(0, mv.size(), 4):
							var a2: Vector3 = mv[q2]
							var flat_y := true
							var mnx := a2.x
							var mxx := a2.x
							var mnz := a2.z
							var mxz := a2.z
							for k2 in 4:
								flat_y = flat_y and absf(mv[q2 + k2].y - a2.y) < 0.001
								mnx = minf(mnx, mv[q2 + k2].x)
								mxx = maxf(mxx, mv[q2 + k2].x)
								mnz = minf(mnz, mv[q2 + k2].z)
								mxz = maxf(mxz, mv[q2 + k2].z)
							if flat_y and absf(a2.y - 63.0) < 0.001:
								for xx in [0, 15]:
									if mnx <= xx + 0.5 and mxx >= xx + 0.5:
										for zz in range(int(mnz), int(ceil(mxz))):
											cov["%d,%d" % [xx, zz]] = int(cov.get("%d,%d" % [xx, zz], 0)) + 1
						var miss: Array = []
						for xx in [0, 15]:
							for zz in 16:
								var wst := state_at(mc.cx * 16 + xx, 62, mc.cz * 16 + zz)
								if wst > 0 and Res.blocks.name_of(wst) == "ice" and not cov.has("%d,%d" % [xx, zz]):
									miss.append("%d,%d" % [xx, zz])
						print("[meshprobe] ice columns without a y=63 top face (local x,z): %s" % str(miss))
						# draw order of the +Y quads covering a border column and an inner column (index in the buffer)
						for col2 in [Vector2(0.5, 5.5), Vector2(5.5, 5.5), Vector2(15.5, 5.5)]:
							var order: Array = []
							for q3 in range(0, mv.size(), 4):
								var a3: Vector3 = mv[q3]
								var fy := true
								var bx0 := a3.x
								var bx1 := a3.x
								var bz0 := a3.z
								var bz1 := a3.z
								for k3 in 4:
									fy = fy and absf(mv[q3 + k3].y - a3.y) < 0.001
									bx0 = minf(bx0, mv[q3 + k3].x)
									bx1 = maxf(bx1, mv[q3 + k3].x)
									bz0 = minf(bz0, mv[q3 + k3].z)
									bz1 = maxf(bz1, mv[q3 + k3].z)
								if fy and bx0 <= col2.x and bx1 >= col2.x and bz0 <= col2.y and bz1 >= col2.y:
									var lay3 := PackedByteArray([cus[q3 * 8], cus[q3 * 8 + 1]]).decode_half(0)
									order.append("#%d y%.2f L%d" % [q3 / 4, a3.y, int(lay3)])
							print("[meshprobe] flat quads over column %s in buffer order: %s" % [str(col2), str(order)])
		if autoplay.has("blockmesh"):   # --blockmesh=x,y,z[;x,y,z]: quads inside one block with per-vertex brightness (AO checks)
			for bspec in str(autoplay["blockmesh"]).split(";"):
				var bp: PackedStringArray = bspec.split(",")
				var bx := int(bp[0])
				var by := int(bp[1])
				var bz := int(bp[2])
				var bc := cm.get_chunk(bx >> 4, bz >> 4)
				if bc == null or not bc.light_valid or bc.light_halo_secs.size() != Coords.SECTIONS:
					print("[blockmesh] %s: chunk not ready" % bspec)
					continue
				var bsn: Array = []
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						var bn := cm.get_chunk(bc.cx + dx, bc.cz + dz)
						bsn.append(bn.snapshot() if bn != null else null)
				var bg := (by - Coords.MIN_Y) / Mesher.GH
				var bres := Mesher.build({"snaps": bsn, "light": bc.light_halo_secs, "group": bg, "blocks": Res.blocks, "tints": cm._tints(bc)})
				var lo := Vector3(bx & 15, by - (Coords.MIN_Y + bg * Mesher.GH), bz & 15)
				var bst := state_at(bx, by, bz)
				print("[blockmesh] %s %s flags %d" % [bspec, Res.blocks.name_of(bst), Res.blocks.st_flags[bst]])
				for nd in [Vector3i(-1, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(0, 1, 0), Vector3i(0, -1, 0)]:
					var nst := state_at(bx + nd.x, by + nd.y, bz + nd.z)
					print("[blockmesh]   neighbour %s %s flags %d full %s" % [str(nd), Res.blocks.name_of(nst), Res.blocks.st_flags[nst], str((Res.blocks.st_flags[nst] & BlockRegistry.F_FULL_SHAPE) != 0)])
				for cls in ["opaque", "cutout", "translucent"]:
					var ba: Array = bres.get(cls, [])
					if ba.is_empty():
						continue
					var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
					var bcol: PackedColorArray = ba[Mesh.ARRAY_COLOR]
					for q in range(0, bv.size(), 4):
						var ctr := (bv[q] + bv[q + 1] + bv[q + 2] + bv[q + 3]) / 4.0 - lo
						if ctr.x < 0.0 or ctr.x > 1.0 or ctr.y < 0.0 or ctr.y > 1.0 or ctr.z < 0.0 or ctr.z > 1.0:
							continue
						var parts: Array = []
						for k in 4:
							parts.append("%s a=%.3f" % [str(bv[q + k] - lo), bcol[q + k].a])
						print("[blockmesh]   %s %s" % [cls, ", ".join(parts)])
		if autoplay.has("remesh"):   # stale-mesh check: rebuild every loaded chunk's meshes from current data (like F3+A)
			for rc in cm.chunks.values():
				var rch: Chunk = rc
				if rch.light_valid:
					rch.dirty_groups = 0x3F
			cm.kick()
			for i in 300:
				await get_tree().process_frame
	if autoplay.has("mobs"):
		# rig check: spawn the listed mobs in a row in front of the player (yaw 0 = +z)
		var names: PackedStringArray = str(autoplay["mobs"]).split(",")
		var i := 0
		for nm in names:
			var big := nm == "ghast"
			var at := player.pos + Vector3((i - names.size() / 2.0) * 2.2, 2.0 if big else 0.0, 14.0 if big else 4.0 + names.size() * 0.9)
			var e := entities.spawn_mob(nm, at)
			if e != null:
				e.yaw = 180.0   # facing -z, toward the camera
				e.body_yaw = 180.0
				e.persistent = true
				e.noai = true
			i += 1
		autoplay["yaw"] = autoplay.get("yaw", "0")
		autoplay["pitch"] = autoplay.get("pitch", "5")
	var gen_start: int = cm.stats["generated"]
	while cm.pending_jobs() > 0 and Time.get_ticks_msec() - t0 < secs * 1000.0:
		await get_tree().process_frame
	var t_settle := Time.get_ticks_msec() - t0
	var dir := "user://autoplay"
	DirAccess.make_dir_recursive_absolute(dir)
	var shots: Array = []
	var frame_ms: Array = []
	var views := [[0.0, 10.0], [90.0, 10.0], [180.0, 10.0], [270.0, 10.0], [45.0, 60.0], [30.0, 25.0, 40.0], [210.0, 20.0, 60.0]]
	if autoplay.has("yaw"):
		views = [[float(autoplay["yaw"]), float(autoplay.get("pitch", "10"))]]
	var ground := player.pos
	for vi in views.size():
		if autoplay.has("cam"):
			views[vi] = [views[vi][0], views[vi][1]]
		player.yaw = views[vi][0]
		player.pitch = views[vi][1]
		if views[vi].size() > 2:
			player.mode = Player.Mode.SPECTATOR
			player.pos = ground + Vector3(0, views[vi][2], 0)
			player.prev_pos = player.pos
		for f in 45:
			await get_tree().process_frame
			frame_ms.append(get_process_delta_time() * 1000.0)
		if autoplay.has("breakfx"):   # --breakfx=block,block,...: breaking particles in front of the camera just before the shot
			var fwd := Vector3(-sin(deg_to_rad(player.yaw)), 0, cos(deg_to_rad(player.yaw)))
			var side := Vector3(fwd.z, 0, -fwd.x)
			var names: PackedStringArray = str(autoplay["breakfx"]).split(",")
			for bi in names.size():
				var at := player.eye_pos() + fwd * 2.5 + side * (float(bi) - (names.size() - 1) / 2.0) * 1.2 - Vector3(0.5, 0.9, 0.5)
				entities.spawn_block_particles(Vector3i(at.floor()), Res.blocks.default_state(names[bi]))
			for f in 3:
				await get_tree().process_frame
		if DisplayServer.get_name() != "headless":   # the dummy renderer never emits frame_post_draw (headless probes hung)
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var p := dir.path_join("%s_view%d.png" % [folder, vi])
			img.save_png(p)
			shots.append(ProjectSettings.globalize_path(p))
	frame_ms.sort()
	var stats := {
		"world": folder, "generator": gen.generator_id, "seed": gen.seed, "assets": Res.mode + " " + Res.version,
		"time_to_spawn_ms": t_spawn, "time_to_settle_ms": t_settle, "chunks_loaded": cm.chunks.size(),
		"chunks_generated": cm.stats["generated"], "gen_ms_avg": cm.stats["gen_ms"], "light_ms_avg": cm.stats["light_ms"],
		"mesh_ms_avg": cm.stats["mesh_ms"], "mesh_groups": cm.visible_groups(), "verts": cm.stats["verts"],
		"frame_ms_median": frame_ms[frame_ms.size() / 2] if frame_ms.size() > 0 else 0.0,
		"frame_ms_p95": frame_ms[int(frame_ms.size() * 0.95)] if frame_ms.size() > 0 else 0.0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"player": [player.pos.x, player.pos.y, player.pos.z], "screenshots": shots, "render_distance": cm.radius,
		"cpu_threads": OS.get_processor_count(), "gpu": RenderingServer.get_video_adapter_name(),
	}
	var f2 := FileAccess.open(dir.path_join(folder + "_stats.json"), FileAccess.WRITE)
	f2.store_string(JSON.stringify(stats, "  "))
	f2.close()
	print("AUTOPLAY ", JSON.stringify(stats))
	app.quit()


var _spawn_log: Dictionary = {}
var _t_start := 0

# World loading screen (Java LevelLoadingScreen): after the player is placed, the world appears only once every chunk
# within PRELOAD_R of the player is visible (generated, decorated, lit, meshed), at most PRELOAD_MAX_MS. Meanwhile the
# chunk manager runs in loading mode (more workers, larger budgets) and the HUD draws the progress screen.
const PRELOAD_R := 3
const PRELOAD_MAX_MS := 15000
var _spawn_placed := false
var _preload_t0 := 0


func _begin_preload() -> void:
	_spawn_placed = true
	_preload_t0 = Time.get_ticks_msec()
	cm.set_radius(int(Settings.get_v("render_distance")))
	cm.set_loading(true)


## Fraction of the chunks within PRELOAD_R of the player that are visible (0 before the player is placed).
func preload_progress() -> float:
	if not _spawn_placed or cm == null:
		return 0.0
	var r := mini(PRELOAD_R, int(Settings.get_v("render_distance")))
	var pcx := int(floor(player.pos.x)) >> 4
	var pcz := int(floor(player.pos.z)) >> 4
	var n := 0
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if cm.is_visible_chunk(cm.get_chunk(pcx + dx, pcz + dz)):
				n += 1
	return float(n) / float((2 * r + 1) * (2 * r + 1))


func _try_place_spawn() -> void:
	var x := int(floor(player.pos.x))
	var z := int(floor(player.pos.z))
	if not autoplay.is_empty():
		if _t_start == 0:
			_t_start = Time.get_ticks_msec()
		var sc := cm.get_chunk(x >> 4, z >> 4)
		var stage := "absent" if sc == null else ("lit" if sc.light_valid else ("decorated" if sc.state >= Chunk.DECORATED else ("features" if sc.features_ready else ("data" if sc.state >= Chunk.DATA_READY else "queued"))))
		if not _spawn_log.has(stage):
			_spawn_log[stage] = Time.get_ticks_msec() - _t_start
			print("[spawn] %s at %d ms (chunks %d, jobs %d, gen %d)" % [stage, _spawn_log[stage], cm.chunks.size(), cm.pending_jobs(), cm.stats["generated"]])
	if not _arrival.is_empty():
		_resolve_arrival()
		return
	if _spawn_placed:
		if preload_progress() >= 1.0 or Time.get_ticks_msec() - _preload_t0 > PRELOAD_MAX_MS:
			spawn_ready = true
			cm.set_loading(false)
		return
	if not cm.is_ready(x, z):
		return
	var c := cm.get_chunk(x >> 4, z >> 4)
	if not c.light_valid:
		return
	var y := Coords.MAX_Y - 1
	while y > Coords.MIN_Y:
		var st := c.get_block(x & 15, y, z & 15)
		if st != 0 and (Res.blocks.st_flags[st] & (BlockRegistry.F_COLLIDE | BlockRegistry.F_LIQUID)) != 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_LEAVES) == 0:
			break
		y -= 1
	player.pos = Vector3(x + 0.5, y + 1, z + 0.5)
	player.prev_pos = player.pos
	level["spawn"] = [x, y + 1, z]
	_begin_preload()
	if level.get("bonus_pending", false):
		level.erase("bonus_pending")
		_place_bonus_chest(x + 2, y + 1, z)


## Destination chunks (3x3 around the target) decorated + lit -> link/build portal or platform, place player.
func _resolve_arrival() -> void:
	var t: Vector3 = _arrival.get("pos", player.pos)
	var tx := int(floor(t.x))
	var tz := int(floor(t.z))
	for d in [Vector2i(-16, -16), Vector2i(16, -16), Vector2i(-16, 16), Vector2i(16, 16), Vector2i(0, 0)]:
		if not cm.is_ready(tx + d.x, tz + d.y):
			return
	var c := cm.get_chunk(tx >> 4, tz >> 4)
	if c == null or not c.light_valid:
		return
	var at := t
	match str(_arrival.get("kind", "spawn")):
		"nether_portal":
			at = Portals.arrive_nether_portal(self, Vector3i(tx, int(t.y), tz), str(_arrival.get("axis", "x")))
		"end_platform":
			at = Portals.end_platform(self)
		"end_gateway_out":
			at = dragon_fight.resolve_outer_arrival(t, _arrival.get("from", [0, 75, 0]))
		"exact":
			at = t
		_:
			var y := Coords.MAX_Y - 1
			while y > Coords.MIN_Y:
				var st := c.get_block(tx & 15, y, tz & 15)
				if st != 0 and (Res.blocks.st_flags[st] & (BlockRegistry.F_COLLIDE | BlockRegistry.F_LIQUID)) != 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_LEAVES) == 0:
					break
				y -= 1
			at = Vector3(tx + 0.5, y + 1, tz + 0.5)
	player.pos = at
	player.prev_pos = at
	player.vel = Vector3.ZERO
	player.fall_distance = 0.0
	_arrival = {}
	portal_cooldown = 10
	_begin_preload()
	_update_origin(true)
	Net.host_arrived()


## Java portal processing: nether portal needs 80 ticks (1 in creative); end portals are instant. While on cooldown
## inside a portal the cooldown is refreshed, so arriving players must step out first.
func _portal_tick() -> void:
	var in_np := false
	var in_ep := false
	var in_gw := Vector3i(0, -99999, 0)
	var axis := "x"
	var mn := player.aabb_min()
	var mx := player.aabb_max()
	for y in range(int(floor(mn.y)), int(floor(mx.y)) + 1):
		for z in range(int(floor(mn.z)), int(floor(mx.z)) + 1):
			for x in range(int(floor(mn.x)), int(floor(mx.x)) + 1):
				var st := state_at(x, y, z)
				if st <= 0:
					continue
				var n := Res.blocks.name_of(st)
				if n == "nether_portal":
					in_np = true
					var a := Res.blocks.get_prop(st, "axis")
					if a != "":
						axis = a
				elif n == "end_portal":
					in_ep = true
				elif n == "end_gateway":
					in_gw = Vector3i(x, y, z)
	if in_gw.y != -99999 and dimension == "the_end" and dragon_fight != null:
		if portal_cooldown > 0:
			portal_cooldown = 10
			return
		teleport_within(dragon_fight.gateway_target(in_gw))
		Audio.play("block.end_gateway.spawn", player.pos, "Blocks")
		return
	if (in_np or in_ep) and portal_cooldown > 0:
		portal_cooldown = 10
		return
	if portal_cooldown > 0:
		portal_cooldown -= 1
	if in_ep:
		if dimension == "the_end":
			_go_respawn_dimension()
		else:
			change_dimension("the_end", {"kind": "end_platform", "pos": Vector3(100.5, 49, 0.5)})
		return
	if in_np and dimension != "the_end":
		portal_time += 1
		var wait := 1 if player.is_creative() else 80
		if portal_time >= wait:
			portal_time = 0
			var to := "overworld" if dimension == "the_nether" else "the_nether"
			change_dimension(to, {"kind": "nether_portal", "pos": Portals.scaled_target(dimension, to, player.pos), "axis": axis})
	else:
		portal_time = maxi(portal_time - 4, 0)


## Teleport inside the current dimension, resolving the arrival once the destination chunks are ready.
func teleport_within(arrival: Dictionary) -> void:
	_arrival = arrival
	var p: Vector3 = arrival.get("pos", player.pos)
	player.pos = p
	player.prev_pos = p
	player.vel = Vector3.ZERO
	spawn_ready = false
	_spawn_placed = false
	portal_cooldown = 10
	cm.set_radius(1)
	_update_origin(true)


## Third-person player model (Java PlayerModel layout, installed default skin or a custom skin file).
func _update_player_model(p: Vector3) -> void:
	if player_model == null:
		var def := {"tex": "entity/player/wide/steve", "tex_size": [64, 64], "parts": MobRegistry.PLAYER}
		player_model = EntityRenderer.build_rig(def)
		EntityRenderer.apply_skin_parts(player_model)
		var custom := str(Settings.get_v("skin_path"))
		if custom != "" and FileAccess.file_exists(custom):
			var img := Image.load_from_file(custom)
			if img != null:
				var tex := ImageTexture.create_from_image(img)
				for mi in entities._meshes(player_model):
					var m: ShaderMaterial = (mi as MeshInstance3D).material_override.duplicate()
					m.set_shader_parameter("tex", tex)
					(mi as MeshInstance3D).material_override = m
		add_child(player_model)
	player_model.visible = third_person > 0 and not player.is_spectator()
	if not player_model.visible:
		return
	var crouch: bool = player.sneaking and player.on_ground and not player.flying
	# Java PlayerRenderer.getRenderOffset: a crouching player is drawn 2 px lower
	player_model.position = vis(p) + (Vector3(0, -2.0 / 16.0, 0) if crouch else Vector3.ZERO)
	player_model.rotation.y = deg_to_rad(180.0 - player.yaw + float(autoplay.get("pmyaw", 0.0)))
	var spd := Vector2(player.pos.x - player.prev_pos.x, player.pos.z - player.prev_pos.z).length()
	_pm_limb += spd * 4.0
	var amt := clampf(spd * 4.0, 0.0, 1.0)
	ArmorRender.apply(player_model, ArmorRender.slots_of_inventory(player.inventory))
	var main_s := player.inventory.held()
	var off_s := player.inventory.get_slot(Inventory.OFFHAND)
	HeldItems.update(player_model, main_s, off_s)
	var model: Node = player_model.get_node_or_null("model")
	if model == null:
		return
	# Java HumanoidModel.setupAnim (values in Java model space; ours: x / y rotations and x / y positions negated)
	var pt := clampf(tick_accum / 0.05, 0.0, 1.0)
	var age_t := float(game_time) + pt
	var attack := 0.0
	if hand_swing > 0:
		attack = clampf((6.0 - float(hand_swing) + pt) / 6.0, 0.0, 1.0)
	var body_y := sin(sqrt(attack) * TAU) * 0.2 if attack > 0.0 else 0.0
	var head_x := deg_to_rad(player.pitch)
	var l := cm.get_light(int(floor(p.x)), int(floor(p.y + 1.0)), int(floor(p.z)))
	for c in model.get_children():
		var nm: String = c.name
		if not c.has_meta("p0"):
			c.set_meta("p0", c.position)
			c.rotation_order = EULER_ORDER_ZYX
		var p0: Vector3 = c.get_meta("p0")
		if nm == "head" or nm == "hat":
			c.rotation = Vector3(-head_x, 0, 0)
			c.position = p0 + (Vector3(0, -4.2, 0) / 16.0 if crouch else Vector3.ZERO)
		elif nm == "body":
			c.rotation = Vector3(-0.5 if crouch else 0.0, -body_y, 0)
			c.position = p0 + (Vector3(0, -3.2, 0) / 16.0 if crouch else Vector3.ZERO)
		elif nm.begins_with("leg"):
			var right_leg := nm == "leg0"
			var lx := -1.4137167 if player.vehicle != null else cos(_pm_limb * 0.6662 + (0.0 if right_leg else PI)) * 1.4 * amt
			c.rotation = Vector3(-lx, 0, 0)
			c.position = p0 + (Vector3(0, -0.2, 3.9) / 16.0 if crouch else Vector3.ZERO)
		elif nm.begins_with("arm"):
			var right := nm == "arm0"
			var ax := cos(_pm_limb * 0.6662 + (PI if right else 0.0)) * amt
			var ay := 0.0
			var az := 0.0
			if player.vehicle != null:
				ax += -PI / 5.0
			var hand_item := main_s if right else off_s
			if not hand_item.is_empty():
				ax = ax * 0.5 - PI / 10.0   # ArmPose.ITEM
			if crouch:
				ax += 0.4
			# AnimationUtils.bobModelPart
			az += (cos(age_t * 0.09) * 0.05 + 0.05) * (1.0 if right else -1.0)
			ax += sin(age_t * 0.067) * 0.05 * (1.0 if right else -1.0)
			var arm_pos := Vector3(5.0 if right else -5.0, -2.0, 0) / 16.0
			if attack > 0.0:
				# setupAttackAnimation: the body turns, both shoulders follow, the swinging arm chops down
				arm_pos = Vector3(cos(body_y) * 5.0 * (1.0 if right else -1.0), -2.0, sin(body_y) * 5.0 * (1.0 if right else -1.0)) / 16.0
				ay += body_y
				if not right:
					ax += body_y
				if right:
					var f := 1.0 - attack
					f = 1.0 - f * f * f * f
					var g := sin(f * PI)
					var h := sin(attack * PI) * -(head_x - 0.7) * 0.75
					ax -= g * 1.2 + h
					ay += body_y * 2.0
					az += sin(attack * PI) * -0.4
			if crouch:
				arm_pos.y = -5.2 / 16.0
			c.position = arm_pos
			c.rotation = Vector3(-ax, -ay, az)
		for mi in entities._meshes(c):
			mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			mi.set_instance_shader_parameter("hurt", 1.0 if player.hurt_time > 0 else 0.0)


func _player_biome() -> int:
	var c := cm.get_chunk(int(floor(player.pos.x)) >> 4, int(floor(player.pos.z)) >> 4) if cm != null else null
	if c == null:
		return -1
	return c.biome_at(int(floor(player.pos.x)) & 15, clampi(int(player.pos.y), Coords.MIN_Y, Coords.MAX_Y - 1), int(floor(player.pos.z)) & 15)


func _go_respawn_dimension() -> void:
	var sp: Array = level.get("spawn", [0, 80, 0])
	var at := Vector3(sp[0] + 0.5, sp[1], sp[2] + 0.5)
	if player.has_spawn:
		at = Vector3(player.spawn_point) + Vector3(0.5, 0.6, 0.5)
	change_dimension("overworld", {"kind": "exact" if player.has_spawn else "spawn", "pos": at})


func _place_bonus_chest(x: int, y: int, z: int) -> void:
	var chest := Res.blocks.default_state("chest")
	if chest < 0:
		return
	set_block(x, y, z, chest)
	var items := [["oak_log", 4], ["oak_planks", 12], ["stick", 8], ["apple", 3], ["bread", 2], ["wooden_axe", 1], ["wooden_pickaxe", 1]]
	var inv: Array = []
	for i in items:
		var s := ItemStack.named(i[0], i[1])
		inv.append(s.to_dict())
	BlockEntities.set_data(self, Vector3i(x, y, z), {"id": "chest", "items": inv})


var prof_us: Dictionary = {}   # load-test tracing: main-thread time per subsystem
var last_parts: Array = [0, 0, 0, 0, 0, 0]   # tracing: last frame's [ticks, camera+beacons+signs, berender, chunk_manager, target+sky, total] usec
var last_tick_parts: Dictionary = {}
var frame_tparts: Dictionary = {}             # tracing: this frame's tick work by phase (usec)          # tracing: last tick's per-part usec


func _pf(k: String, us: int) -> void:
	prof_us[k] = int(prof_us.get(k, 0)) + us


## Game tick, split into phases so a tick's work never lands in one frame: phase 0 (time, weather, input, player,
## portals, mining, item use) runs when the tick is due, phases 1-5 run on the following frames within a per-frame time
## budget (_tick_continue), in the original order: particles, entities, scheduled block updates, random-tick sampling,
## redstone + block entities + beacons/commands/raids, trials/sculk/creaking/commands + origin. A tick always completes before the next one starts,
## so every system still runs exactly once per game tick at 20 ticks/s.
var _tick_phase := 0            # next phase of the game tick in progress (0: none)
var _ent_slicing := false       # the entity phase is in progress (EntityManager.tick_slice)
var _ent_slice := 1 << 30       # (unused: slices are time-budgeted now)
var _ent_budgeted := false      # this pass spreads over frames with ENT_BUDGET_US per frame
const ENT_BUDGET_US := 1000
var _last_delta := 0.016
var _tick_meas: Dictionary = {} # tracing: usec per part of the tick in progress
var _tick_us := 0               # tracing: total usec of the tick in progress
const TICK_LAST_PHASE := 6
const TICK_PHASE_BUDGET_US := 1500


func _tick() -> void:
	if _tick_phase > 0:
		var tf0 := Time.get_ticks_usec()
		var ph0 := _tick_phase
		_tick_finish()
		if cm.tracing:
			frame_tparts["tick:finish from phase %d" % ph0] = Time.get_ticks_usec() - tf0
	var t0 := Time.get_ticks_usec()
	game_time += 1
	# Java LightTexture.tick: block light flicker random walk
	block_flicker += (randf() - randf()) * randf() * randf() * 0.1
	block_flicker *= 0.9
	if gamerule("doDaylightCycle", true):
		day_time = (day_time + 1) % 24000
	_weather_tick()
	if not spawn_ready:
		return
	var g0 := Time.get_ticks_usec()
	_settle_tick()
	_gather_input()
	player.tick(self)
	_tick_camera()
	if weather_fx != null:
		weather_fx.tick()
	var g1 := Time.get_ticks_usec()
	if not Net.is_client():
		_portal_tick()
		if dragon_fight != null:
			dragon_fight.tick()
	if advancements != null:
		if _inv_dirty:
			_inv_dirty = false
			advancements.on_inventory(player.inventory)
		if game_time % 20 == 0:
			advancements.trigger("location", {"dimension": dimension, "biome": biomes.names[_player_biome()] if _player_biome() >= 0 else ""})
	var g2 := Time.get_ticks_usec()
	player.stats["play_time"] = int(player.stats.get("play_time", 0)) + 1
	if player.dead and hud != null and not hud.death_shown:
		_on_player_death()
	_mining_tick()
	var mid := Maps.map_id(player.inventory.held())
	if mid >= 0:
		Maps.update(self, mid)
	if hand_swing > 0:
		hand_swing -= 1
	var g4 := Time.get_ticks_usec()
	if use_cooldown > 0:
		use_cooldown -= 1
	if auto_use > 0:
		auto_use -= 1
	UseItem.tick(self, player, (Input.is_action_pressed("use") and mouse_captured and screen == null) or auto_use > 0)
	# particles tick with the tick start: their render interpolation (prev -> cur by tick_accum) restarts on this frame,
	# so a tick on a later frame showed them one step back for a frame (falling particles jittered back and forth)
	if Particles.instance != null:
		Particles.instance.tick()
	var q0 := Time.get_ticks_usec()
	_tick_phase = 1
	if cm.tracing:
		_tick_meas = {"time+weather": g0 - t0, "player": g1 - g0, "portal+adv": g2 - g1, "mining+maps": g4 - g2, "useitem": q0 - g4}
		for k in _tick_meas:
			if int(_tick_meas[k]) > 300:
				frame_tparts["tick0:" + k] = _tick_meas[k]
		_tick_us = q0 - t0
		_pf("  tick:pre-entities", q0 - t0)


## Runs the remaining phases of the tick in progress now (a new tick is due).
func _tick_finish() -> void:
	while _tick_phase > 0:
		_tick_step()


## Per frame: one pending phase; more (within the frame's phase budget) only when the frames left before the next tick
## are too few for one phase each (low frame rates).
func _tick_continue(delta: float) -> void:
	if _tick_phase == 0:
		return
	var end := Time.get_ticks_usec() + TICK_PHASE_BUDGET_US
	_tick_step()
	var frames_left := (TICK - tick_accum) / maxf(delta, 0.0005)
	while _tick_phase > 0 and float(TICK_LAST_PHASE - _tick_phase + 1) + 1.0 >= frames_left and Time.get_ticks_usec() < end:
		_tick_step()


func _tick_step() -> void:
	var t := Time.get_ticks_usec()
	var stay := false
	var net_client := Net.is_client()
	var part := ""
	match _tick_phase:
		1:
			part = "particles"   # (ticked with the tick start, see _tick)
		2:
			part = "entities"
			# at high frame rates the entity step spans the frames until the next tick with a per-frame time budget
			# (was ~3 equal slices: a village's villagers put 10 ms into one frame); a new tick finishes the rest
			var deadline := Time.get_ticks_usec() + ENT_BUDGET_US if _ent_budgeted else 0
			if _ent_slicing:
				stay = not entities.tick_slice(1 << 30, deadline)
			else:
				entities.tick_begin()
				var fpt := (TICK - tick_accum) / maxf(_last_delta, 0.0005)
				_ent_budgeted = fpt >= 12.0
				deadline = Time.get_ticks_usec() + ENT_BUDGET_US if _ent_budgeted else 0
				_ent_slicing = true
				stay = not entities.tick_slice(1 << 30, deadline)
			if not stay:
				_ent_slicing = false
		3:
			part = "block_updates"
			if net_client:
				BlockUpdates.reset()   # the host simulates block updates and sends the results
			else:
				BlockUpdates.tick_scheduled(self)
		4:
			part = "random_ticks"
			if not net_client:
				BlockUpdates.tick_random(self)
		5:
			part = "redstone+furnaces+beacon+cmd+raids"
			if not net_client:
				var r0 := Time.get_ticks_usec()
				Redstone.flush(self)
				var r1 := Time.get_ticks_usec()
				BlockEntities.tick_furnaces(self)
				var r2 := Time.get_ticks_usec()
				Beacons.tick(self)
				CommandBlocks.tick(self)
				Raids.tick(self)
				if cm.tracing:
					_tick_meas["redstone"] = r1 - r0
					_tick_meas["furnaces"] = r2 - r1
					_tick_meas["beacon+cmd+raids"] = Time.get_ticks_usec() - r2
					_pf("  tick:redstone", r1 - r0)
					_pf("  tick:furnaces", r2 - r1)
					_pf("  tick:beacon+cmd+raids", Time.get_ticks_usec() - r2)
		6:
			part = "trials+sculk+creaking+cmds+origin"
			if not net_client:
				var q0 := Time.get_ticks_usec()
				Trials.tick(self)
				var q1 := Time.get_ticks_usec()
				Sculk.tick(self)
				var q2 := Time.get_ticks_usec()
				Creaking.tick(self)
				var q3 := Time.get_ticks_usec()
				commands.tick()
				if cm.tracing:
					frame_tparts["p6:trials"] = q1 - q0
					frame_tparts["p6:sculk"] = q2 - q1
					frame_tparts["p6:creaking"] = q3 - q2
					frame_tparts["p6:commands"] = Time.get_ticks_usec() - q3
			var q4 := Time.get_ticks_usec()
			_update_origin()
			if cm.tracing:
				frame_tparts["p6:origin"] = Time.get_ticks_usec() - q4
	if not stay:
		_tick_phase = 0 if _tick_phase >= TICK_LAST_PHASE else _tick_phase + 1
	if cm.tracing:
		var dt := Time.get_ticks_usec() - t
		_tick_us += dt
		frame_tparts[part] = int(frame_tparts.get(part, 0)) + dt
		if part != "redstone+furnaces+beacon+cmd+raids":
			_tick_meas[part] = dt
			_pf("  tick:" + part, dt)
		if _tick_phase == 0:
			_tick_meas["tick_no"] = game_time
			last_tick_parts = _tick_meas
			_pf("  tick:total", _tick_us)

func _weather_tick() -> void:
	if gamerule("doWeatherCycle", true) and not Net.is_client():
		weather_timer -= 1
		if weather_timer <= 0:
			raining = not raining
			thundering = raining and rng.randf() < 0.3
			weather_timer = rng.randi_range(12000, 180000) if not raining else rng.randi_range(12000, 24000)
	var wet := dimension == "overworld"
	rain = move_toward(rain, 1.0 if raining and wet else 0.0, 0.01)
	thunder = move_toward(thunder, 1.0 if thundering and wet else 0.0, 0.01)


func celestial_angle() -> float:
	var d := fposmod(day_time / 24000.0 - 0.25, 1.0)
	var e := 0.5 - cos(d * PI) / 2.0
	return (d * 2.0 + e) / 3.0


func sky_darken() -> float:
	var g := 1.0 - (cos(celestial_angle() * TAU) * 2.0 + 0.5)
	g = 1.0 - clampf(g, 0.0, 1.0)
	g *= 1.0 - rain * 5.0 / 16.0
	g *= 1.0 - thunder * 5.0 / 16.0
	return g * 0.8 + 0.2


## Per frame: Java 26.3 sky / fog / light state (SkyState) -> sky shader, stars, vanilla fog globals, lightmap inputs.
const CLOUD_MODES := {"off": 0, "fast": 1, "fancy": 2}
const DIM_SKY_MODES := {"the_nether": 1, "the_end": 2}


func _update_sky(alpha: float) -> void:
	var cam_w := camera.global_position + Vector3(cm.origin)
	var look := -camera.global_transform.basis.z
	var ticks := float(day_time) + clampf(alpha, 0.0, 1.0)
	var rdc := int(Settings.get_v("render_distance"))
	var ss := sky_state
	var st0 := Time.get_ticks_usec()
	ss.update(self, cam_w, look, ticks, rdc, rain, thunder)
	if cm.tracing:
		frame_tparts["sky:state"] = Time.get_ticks_usec() - st0
	ShaderGlobals.put("sky_light_factor", ss.sky_light_factor)
	var fogc: Color = ss.fog_color
	var env_f := _fog_env
	var rd_f := _fog_rd
	var fluid := false
	if player.eyes_in_water:
		# Java water fog: environmental -8 .. 96 (spherical), biome water fog colour
		var bio := _player_biome()
		var day := clampf((ss.sky_light_factor - 0.24) / 0.76, 0.0, 1.0)
		fogc = (biomes.water[bio] if bio >= 0 else Color8(0x3f, 0x76, 0xe4)) * (0.3 + 0.5 * day)
		env_f = Vector2(-8.0, 96.0)
		fluid = true
	elif player.in_lava:
		fogc = Color(0.6, 0.1, 0.0)
		env_f = Vector2(0.0, 5.0) if player.effects.has("fire_resistance") else Vector2(0.25, 1.0)
		fluid = true
	var strength := 0.0 if Settings.get_v("fog") == "off" and not fluid else 1.0
	ShaderGlobals.put_v("mc_fog_color", Vector4(fogc.r, fogc.g, fogc.b, strength))
	ShaderGlobals.put_v("mc_fog_dist", Vector4(env_f.x, env_f.y, rd_f.x, rd_f.y))
	var overworld := dimension == "overworld"
	if sky_rd == null:
		# Godot sky material path (no RenderingDevice sky): sky_rd.update below takes the same values otherwise; ~10
		# set_shader_parameter calls per frame were spent on this unused material
		sky_mat.set_shader_parameter("fog_color", Vector4(fogc.r, fogc.g, fogc.b, 1.0))
		sky_mat.set_shader_parameter("sky_color", Vector3(ss.sky_color.r, ss.sky_color.g, ss.sky_color.b))
		sky_mat.set_shader_parameter("sky_end", minf(rd_f.y, env_f.y) if fluid else rd_f.y)
	if overworld:
		if sky_rd == null:
			# dark disc while the camera is below the horizon height (sea level; flat worlds: the bottom)
			var horizon := 63.0 if gen == null or gen.generator_id != "flat" else float(dim_type.get("min_y", -64.0))
			sky_mat.set_shader_parameter("dark_disc", cam_w.y - horizon < 0.0)
			sky_mat.set_shader_parameter("sunrise", Vector4(ss.sunrise.r, ss.sunrise.g, ss.sunrise.b, ss.sunrise.a))
			sky_mat.set_shader_parameter("sunrise_side", -1.0 if sin(ss.sun_angle) < 0.0 else 1.0)
			sky_mat.set_shader_parameter("sun_angle", ss.sun_angle)
			sky_mat.set_shader_parameter("moon_angle", ss.moon_angle)
			sky_mat.set_shader_parameter("celestial_alpha", 1.0 - rain)
		if ss.moon_phase != _moon_shown:
			_moon_shown = ss.moon_phase
			var mt := _moon_texture(ss.moon_phase)
			if mt != null:
				sky_mat.set_shader_parameter("moon_tex", mt)
				if sky_rd != null:
					sky_rd.moon_tex = mt
	if sky_rd != null:
		if env.background_color != fogc:
			env.background_color = fogc
		var cdist := int(Settings.get_v("cloud_distance"))
		var cmode: int = CLOUD_MODES.get(str(Settings.get_v("clouds")), 2)
		var mode: int = DIM_SKY_MODES.get(dimension, 0)
		var horizon2 := 63.0 if gen == null or gen.generator_id != "flat" else float(dim_type.get("min_y", -64.0))
		var cc := ss.cloud_color
		sky_rd.update(camera, cm.origin, mode, ss.sky_color, fogc, minf(rd_f.y, env_f.y) if fluid else rd_f.y,
			ss.sunrise, -1.0 if sin(ss.sun_angle) < 0.0 else 1.0, ss.sun_angle, ss.moon_angle, 1.0 - rain,
			cam_w.y - horizon2 < 0.0, ss.star_brightness, ss.star_angle, cc,
			SkyState.attr_float(dim_type, "minecraft:visual/cloud_height", 192.33), float(game_time) + clampf(alpha, 0.0, 1.0),
			cmode, cdist, env_f.y if fluid else float(cdist) * 16.0)
		var far := maxf(2000.0, float(cdist) * 16.0 + 400.0)
		if camera.far != far:
			camera.far = far
	elif sky_stars != null:
		sky_stars.update(camera.global_position, ss.star_angle, ss.star_brightness if overworld else 0.0)
	var nv := 1.0 if player.effects.has("night_vision") else 0.0
	ShaderGlobals.put("night_vision", nv * 0.7)
	var st1 := Time.get_ticks_usec()
	_update_lightmap(nv)
	if cm.tracing:
		frame_tparts["sky:lightmap"] = Time.get_ticks_usec() - st1


## Java 26.3 lightmap (core/lightmap.fsh) as the 16x16 texture Java renders each frame: x = block level, y = sky level.
## Inputs: timeline sky light colour / factor, dimension ambient colour, block light flicker (1.5 + Java's per-tick
## random walk), night vision, Brightness option. BLOCK_LIGHT_TINT and NIGHT_VISION_COLOR are code constants in Java
## (not data): ESTIMATED here (tint from the pre-26 warm block-light curve at mid levels).
const BLOCK_LIGHT_TINT := Color(1.0, 0.76, 0.47)
const NIGHT_VISION_COLOR := Color(1.0, 1.0, 1.0)
var lightmap_img: Image
var lightmap_tex: ImageTexture
var _lm_params := PackedFloat32Array()
var block_flicker := 0.0


func _update_lightmap(nv: float) -> void:
	if Settings.get_v("adv_fullbright"):
		nv = 1.0   # QoL Fullbright: the lightmap as under Night Vision
	if lightmap_tex == null:
		lightmap_img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		lightmap_tex = ImageTexture.create_from_image(lightmap_img)
		RenderingServer.global_shader_parameter_set("mc_lightmap", lightmap_tex)
	var ss := sky_state
	var p := PackedFloat32Array([ss.sky_light_factor, 1.5 + block_flicker, nv, 0.0, 0.0, float(Settings.get_v("brightness")),
		BLOCK_LIGHT_TINT.r, BLOCK_LIGHT_TINT.g, BLOCK_LIGHT_TINT.b, ss.sky_light_color.r, ss.sky_light_color.g, ss.sky_light_color.b,
		ss.ambient_color.r, ss.ambient_color.g, ss.ambient_color.b, NIGHT_VISION_COLOR.r, NIGHT_VISION_COLOR.g, NIGHT_VISION_COLOR.b])
	if p == _lm_params:
		return
	_lm_params = p
	var data: PackedByteArray
	if Native.ok and Native.inst != null and Native.inst.has_method("lightmap"):
		data = Native.inst.lightmap(p)[0]
	else:
		data = _lightmap_gd(p)
	lightmap_img.set_data(16, 16, false, Image.FORMAT_RGBA8, data)
	lightmap_tex.update(lightmap_img)


## GDScript reference of the native lightmap (no native library).
static func _lightmap_gd(p: PackedFloat32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(1024)
	for y in 16:
		for x in 16:
			var bl := x / 15.0
			var sl := y / 15.0
			var bb := bl / (4.0 - 3.0 * bl) * p[1]
			var sb := sl / (4.0 - 3.0 * sl) * p[0]
			var pm := (2.0 * bl - 1.0) * (2.0 * bl - 1.0) * 0.9
			var c := [0.0, 0.0, 0.0]
			var mx := 0.0
			for k in 3:
				var v := maxf(p[12 + k], p[15 + k] * p[2]) + p[9 + k] * sb + (p[6 + k] + (1.0 - p[6 + k]) * pm) * bb
				v = v + (v * [0.7, 0.6, 0.6][k] - v) * p[4] - p[3]
				c[k] = clampf(v, 0.0, 1.0)
				mx = maxf(mx, c[k])
			for k in 3:
				var v2: float = c[k]
				if mx > 0.0:
					var inv := 1.0 - mx
					v2 = v2 + (v2 * (1.0 - inv * inv * inv * inv) / mx - v2) * p[5]
				out[(y * 16 + x) * 4 + k] = roundi(clampf(v2, 0.0, 1.0) * 255.0)
			out[(y * 16 + x) * 4 + 3] = 255
	return out

## Java Camera.tick / GameRenderer.tickFov: the eye height and the FOV modifier move half way to their targets per game
## tick and render interpolated between ticks, so crouching, swimming, gliding, sprinting, flying and bow zoom ease in
## and out (both used to snap: the eye height instantly, the FOV with a per-frame ease that depended on the frame rate).
var _zoom := 1.0
var _eye_h := -1.0
var _eye_h_old := 1.62
var _fov_mod := 1.0
var _fov_mod_old := 1.0


func _tick_camera() -> void:
	if _eye_h < 0.0:
		_eye_h = player.eye_height()
	_eye_h_old = _eye_h
	_eye_h += (player.eye_height() - _eye_h) * 0.5
	_fov_mod_old = _fov_mod
	_fov_mod = clampf(_fov_mod + (_fov_target() - _fov_mod) * 0.5, 0.1, 1.5)


## Java AbstractClientPlayer.getFieldOfViewModifier: flying x1.1, (speed / walking speed + 1) / 2 (sprint 1.15, speed /
## slowness effects), bow pull, spyglass 0.1; scaled by FOV Effects.
func _fov_target() -> float:
	var ua := UseItem.anim(UseItem.using_stack(player)) if UseItem.is_using(player) else ""
	if ua == "spyglass" and third_person == 0:
		return 0.1
	var f := 1.0
	if player.flying:
		f *= 1.1
	var spd := 0.1 * (1.3 if player.sprinting else 1.0) * (1.0 + 0.2 * player._effect_amp("speed")) * maxf(0.0, 1.0 - 0.15 * player._effect_amp("slowness"))
	f *= (spd / 0.1 + 1.0) / 2.0
	if ua == "bow":
		var bf := minf(1.0, player.use_ticks / 20.0)
		f *= 1.0 - bf * bf * 0.15
	return lerpf(1.0, f, float(Settings.get_v("distortion")))


func _update_camera(alpha: float) -> void:
	var p := player.interp_pos(alpha)
	if _eye_h < 0.0:
		_eye_h = player.eye_height()
		_eye_h_old = _eye_h
	var eye := p + Vector3(0, lerpf(_eye_h_old, _eye_h, alpha), 0)
	var basis := Basis.from_euler(Vector3(deg_to_rad(-player.pitch), PI - deg_to_rad(player.yaw), 0.0), EULER_ORDER_YXZ)
	if player.sleeping:
		# Java Camera.setup while sleeping: yaw = bed facing toYRot - 180, pitch 0, moved 0.3 up
		var fy: float = {"south": 0.0, "west": 90.0, "north": 180.0, "east": 270.0}.get(player.bed_facing, 0.0) - 180.0
		basis = Basis.from_euler(Vector3(0.0, PI - deg_to_rad(fy), 0.0), EULER_ORDER_YXZ)
		eye = p + Vector3(0, 0.2 + 0.3, 0)
	var off := Vector3.ZERO
	if Settings.get_v("view_bobbing") and third_person == 0 and not player.sleeping:
		# Java GameRenderer.bobView on the view: M = T(sin(h pi) i / 2, -|cos(h pi) i|, 0) * Rz(sin(h pi) i 3 deg) *
		# Rx(|cos(h pi - 0.2) i| 5 deg); the camera becomes C * M^-1. i: interpolated amplitude (eases out in the air)
		var bm := ViewModel.bob_transform(player, alpha)
		var inv := bm.affine_inverse()
		off = basis * inv.origin
		basis = basis * inv.basis
	var cam_pos := eye + off
	if third_person > 0:
		var back := -player.look_dir() if third_person == 1 else player.look_dir()
		var dist := 4.0
		var hit := VoxelRaycast.cast(eye, back, dist, state_at, Res.blocks)
		if not hit.is_empty():
			dist = maxf(0.5, float(hit["dist"]) - 0.2)
		cam_pos = eye + back * dist
		if third_person == 2:
			basis = Basis.from_euler(Vector3(deg_to_rad(player.pitch), -deg_to_rad(player.yaw), 0.0), EULER_ORDER_YXZ)
	# Java GameRenderer.bobHurt: f = (hurtTime - partialTick) / 10, roll -sin(f^4 pi) * 14 degrees (x Damage Tilt)
	# about the hurt direction; dying: 40 - 8000 / (deathTime + pt + 200) degrees
	var tilt := float(Settings.get_v("damage_tilt"))
	if player.dead:
		var dt: float = minf(float(player.get("death_ticks") if player.get("death_ticks") != null else 20) + alpha, 20.0)
		basis = basis * Basis(Vector3(0, 0, 1), deg_to_rad(40.0 - 8000.0 / (dt + 200.0)))
	var hf: float = (float(player.hurt_time) - alpha) / 10.0
	if hf >= 0.0 and player.hurt_time > 0 and tilt > 0.0:
		var sf := sin(hf * hf * hf * hf * PI)
		var hd: float = float(player.get("hurt_dir")) if player.get("hurt_dir") != null else 0.0
		basis = basis * Basis(Vector3.UP, deg_to_rad(-hd)) * Basis(Vector3(0, 0, 1), deg_to_rad(-sf * 14.0 * tilt)) * Basis(Vector3.UP, deg_to_rad(hd))
	camera.global_transform = Transform3D(basis, vis(cam_pos))
	# Java GameRenderer.getFov: option x interpolated modifier; x 6/7 with the camera in water or lava (FOV Effects)
	var fov := float(Settings.get_v("fov")) * lerpf(_fov_mod_old, _fov_mod, alpha)
	# QoL zoom key (hold C): eased to a quarter of the field of view
	var zoom_on: bool = Settings.get_v("adv_zoom") and screen == null and mouse_captured and Input.is_physical_key_pressed(KEY_C) and not Input.is_physical_key_pressed(KEY_CTRL)
	_zoom = lerpf(_zoom, 0.25 if zoom_on else 1.0, clampf(get_process_delta_time() * 12.0, 0.0, 1.0))
	fov *= _zoom
	if player.eyes_in_water:
		fov *= lerpf(1.0, 0.85714287, float(Settings.get_v("distortion")))
	camera.fov = fov
	Audio.listener_pos = cam_pos
	_update_player_model(p)


# ---------------------------------------------------------------- input

func _capture_mouse(on: bool) -> void:
	mouse_captured = on
	if DisplayServer.get_name() == "headless" or not autoplay.is_empty():
		return   # automated runs never grab the OS cursor (the user keeps working while tests run)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _gather_input() -> void:
	if _auto_input:
		return   # autoplay test drives the inputs
	if screen != null or not mouse_captured:
		player.in_forward = 0.0
		player.in_strafe = 0.0
		player.in_jump = false
		player.in_sneak = false
		player.in_sprint = false
		return
	player.in_forward = Input.get_action_strength("move_forward") - Input.get_action_strength("move_back")
	player.in_strafe = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
	player.in_jump = Input.is_action_pressed("jump")
	if Settings.get_v("toggle_sneak"):
		pass
	else:
		player.in_sneak = Input.is_action_pressed("sneak")
	if not Settings.get_v("toggle_sprint"):
		player.in_sprint = Input.is_action_pressed("sprint") or player.sprinting and player.in_forward > 0.0


func _unhandled_input(event: InputEvent) -> void:
	if closing or not autoplay.is_empty():  # autoplay probes ignore stray OS/user input
		return
	if screen != null:
		if event.is_action_pressed("pause") and screen.has_method("on_escape"):
			screen.on_escape()   # e.g. Options: save and go back to the pause menu
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("pause") or (event.is_action_pressed("inventory") and screen.has_method("closes_on_inventory_key")):
			close_screen()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and mouse_captured:
		var s := float(Settings.get_v("sensitivity")) * 0.6 + 0.2
		var k := s * s * s * 8.0 * 0.15
		player.yaw = fposmod(player.yaw + event.relative.x * k, 360.0)
		var dy: float = event.relative.y * k * (-1.0 if Settings.get_v("invert_y") else 1.0)
		player.pitch = clampf(player.pitch + dy, -90.0, 90.0)
		return
	if event is InputEventMouseButton and event.pressed and not mouse_captured:
		_capture_mouse(true)
		return
	if event is InputEventMouseButton and event.pressed and mouse_captured:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if player.is_spectator():
				player.spectator_speed = clampf(player.spectator_speed + 0.2, 0.2, 5.0)
			else:
				player.inventory.selected = (player.inventory.selected + 8) % 9
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if player.is_spectator():
				player.spectator_speed = clampf(player.spectator_speed - 0.2, 0.2, 5.0)
			else:
				player.inventory.selected = (player.inventory.selected + 1) % 9
			return
	if event.is_action_pressed("pause"):
		open_screen(load("res://scripts/ui/pause_menu.gd").new())
		return
	if event.is_action_pressed("inventory") and not player.is_spectator():
		if player.vehicle != null and player.vehicle.kind == "mob" and Taming.is_tamed(player.vehicle) and player.vehicle.id in Taming.NEEDS_TAMING:
			Taming.open_inventory(entities, player.vehicle)   # Java: the inventory key opens the mount's screen
			return
		open_screen(inventory_screen())
		return
	if event.is_action_pressed("chat") or event.is_action_pressed("command"):
		var ch = load("res://scripts/ui/chat_screen.gd").new()
		ch.prefill = "/" if event.is_action_pressed("command") else ""
		open_screen(ch)
		return
	for i in 9:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			# Java saved hotbars (Creative): C + n saves the hotbar into row n, X + n loads it
			if player.is_creative() and Input.is_physical_key_pressed(KEY_C):
				CreativeScreen.save_hotbar(player.inventory, i)
				hud.chat_message(Res.tr_key("inventory.hotbarSaved", "Item hotbar saved (restore with %s+%s)") % ["X", str(i + 1)])
				continue
			if player.is_creative() and Input.is_physical_key_pressed(KEY_X):
				CreativeScreen.load_hotbar(player.inventory, i)
				continue
			player.inventory.selected = i
	# Java KeyboardHandler: F3 toggles the debug screen on release unless an F3+key combination was used meanwhile
	if event.is_action_pressed("debug"):
		_f3_combo = false
	elif event.is_action_released("debug"):
		if not _f3_combo:
			show_debug = not show_debug
	elif event is InputEventKey and event.pressed and not event.echo and Input.is_action_pressed("debug"):
		_f3_combo = true
		if event.physical_keycode == KEY_F4 and screen == null:
			# Java GameModeSwitcherScreen
			var sw = load("res://scripts/ui/gamemode_switcher.gd").new()
			sw.world = self
			open_screen(sw)
			return
		if event.physical_keycode == KEY_N:
			# Java KeyboardHandler F3+N: spectator <-> the previous game mode
			var to := Player.Mode.SPECTATOR
			if player.mode == Player.Mode.SPECTATOR:
				to = prev_gamemode if prev_gamemode >= 0 and prev_gamemode != Player.Mode.SPECTATOR else Player.Mode.CREATIVE
			prev_gamemode = player.mode
			commands.execute("gamemode " + ["survival", "creative", "adventure", "spectator"][to])
			return
		if event.physical_keycode == KEY_H:
			ContainerUI.advanced_tooltips = not ContainerUI.advanced_tooltips
			hud.chat_message(Res.tr_key("debug.prefix", "[Debug]:") + " " + Res.tr_key("debug.advanced_tooltips." + ("on" if ContainerUI.advanced_tooltips else "off"), "Advanced tooltips: " + ("shown" if ContainerUI.advanced_tooltips else "hidden")))
		return
	if event.is_action_pressed("hide_hud"):
		hud_hidden = not hud_hidden
	if event.is_action_pressed("perspective"):
		third_person = (third_person + 1) % 3
	if event.is_action_pressed("screenshot"):
		_screenshot()
	if event.is_action_pressed("fullscreen"):
		Settings.set_v("display_mode", "windowed" if Settings.get_v("display_mode") != "windowed" else "borderless")
	if event.is_action_pressed("jump") and player.can_fly() and not player.is_spectator():
		var now := Time.get_ticks_msec()
		if now - last_tap_forward < 300:
			player.flying = not player.flying
			player.vel.y = 0.0
		last_tap_forward = now
	if event.is_action_pressed("drop"):
		_drop_held(Input.is_key_pressed(KEY_CTRL))
	if event.is_action_pressed("swap_offhand"):
		var inv := player.inventory
		var a := inv.get_slot(inv.selected)
		inv.set_slot(inv.selected, inv.get_slot(Inventory.OFFHAND))
		inv.set_slot(Inventory.OFFHAND, a)
	if event.is_action_pressed("pick_block"):
		_pick_block()
	if event.is_action_pressed("use"):
		_use()
	if event.is_action_pressed("attack"):
		_attack()
	if event.is_action_pressed("move_forward") and Settings.get_v("double_tap_sprint"):
		if Time.get_ticks_msec() - player.age * 0 - _last_fwd < 250:
			player.sprinting = true
		_last_fwd = Time.get_ticks_msec()


var _last_fwd := 0


## Game Menu (Esc): also the persistent return target of screens opened from it (a lambda made inside the pause
## menu becomes invalid when that menu is replaced -> Done used to leave no screen at all).
func open_pause_menu() -> void:
	open_screen(load("res://scripts/ui/pause_menu.gd").new())


func open_screen(s: Control) -> void:
	if screen != null:
		close_screen()
	screen = s
	s.set("world", self)
	hud.add_child(s)
	# explicit full-viewport size (full-rect anchors under a CanvasLayer resolved to 0x0 for menu screens)
	s.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	s.position = Vector2.ZERO
	s.size = get_viewport().get_visible_rect().size
	_capture_mouse(false)


func close_screen() -> void:
	if screen != null:
		if screen.has_method("on_close"):
			screen.on_close()
		screen.queue_free()
	screen = null
	paused = false
	if not closing:
		_capture_mouse(true)


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://screenshots")
	var p := "user://screenshots/%s.png" % Time.get_datetime_string_from_system().replace(":", "-")
	img.save_png(p)
	hud.chat_message("Saved screenshot as " + p.get_file())


func _exit_tree() -> void:
	ChunkManager._dc_mutex.lock()
	ChunkManager.dim_cache.clear()
	ChunkManager._dc_mutex.unlock()
	if Collision.fast_world == self:
		Collision.fast_cm = null
		Collision.fast_world = null
	if _trd != null or sky_rd != null:
		camera.compositor = null
	if _trd != null:
		_trd.destroy()
		_trd = null
	if sky_rd != null:
		sky_rd.destroy()
		sky_rd = null
	InventoryPreview.free_shared()
	Settings.set_in_menu(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and autoplay.is_empty() and Settings.get_v("pause_on_lost_focus") and screen == null and not closing and cm != null and DisplayServer.get_name() != "headless":
		open_screen(load("res://scripts/ui/pause_menu.gd").new())


# ---------------------------------------------------------------- interaction

func _update_target() -> void:
	target = {}
	if player.is_spectator() or player.dead:
		outline.visible = false
		return
	var hit := VoxelRaycast.cast(player.eye_pos(), player.look_dir(), player.block_reach(), state_at, Res.blocks)
	var ent = entities.raycast(player.eye_pos(), player.look_dir(), 3.0 if not player.is_creative() else 5.0)
	if ent != null and (hit.is_empty() or ent[1] < float(hit["dist"])):
		target = {"entity": ent[0], "dist": ent[1]}
		outline.visible = false
		return
	target = hit
	if hit.is_empty() or hud_hidden:
		outline.visible = false
		crack.visible = false
		return
	var p: Vector3i = hit["pos"]
	# the outline mesh only changes with the targeted state (a new ImmediateMesh every frame created / freed a render
	# resource per frame: RID allocation under the RenderingServer lock, waits of several ms while workers held it)
	var ost := int(hit["state"])
	if ost != _outline_state or outline.mesh == null:
		_outline_state = ost
		outline.mesh = _outline_mesh(ost)
	outline.position = vis(Vector3(p))
	outline.visible = true
	_update_crack(p)


var _outline_state := -1


func _outline_mesh(st: int) -> Mesh:
	var boxes := Res.blocks.get_outline(st)
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for b in range(0, boxes.size(), 6):
		var a := Vector3(boxes[b], boxes[b + 1], boxes[b + 2]) - Vector3(0.002, 0.002, 0.002)
		var c := Vector3(boxes[b + 3], boxes[b + 4], boxes[b + 5]) + Vector3(0.002, 0.002, 0.002)
		var pts := [Vector3(a.x, a.y, a.z), Vector3(c.x, a.y, a.z), Vector3(c.x, a.y, c.z), Vector3(a.x, a.y, c.z),
			Vector3(a.x, c.y, a.z), Vector3(c.x, c.y, a.z), Vector3(c.x, c.y, c.z), Vector3(a.x, c.y, c.z)]
		for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
			im.surface_add_vertex(pts[e[0]])
			im.surface_add_vertex(pts[e[1]])
	im.surface_end()
	return im


func _update_crack(p: Vector3i) -> void:
	if mining_progress > 0.0 and p == mining_pos:
		var stage := clampi(int(mining_progress * 10.0), 0, 9)
		var tex = crack_textures[stage]
		var cst := state_at(p.x, p.y, p.z)
		if tex != null and cst > 0:
			crack_mat.set_shader_parameter("tex", tex)
			crack.mesh = _crack_mesh(cst)
			crack.position = vis(Vector3(p))
			crack.visible = crack.mesh != null
	else:
		crack.visible = false


## Java ModelBlockRenderer with SheetedDecalTextureGenerator: the block's own quads, pushed out 0.002 along their
## normal, with UVs projected from the world position (one destroy-stage tile per block face).
func _crack_mesh(st: int) -> ArrayMesh:
	if _crack_meshes.has(st):
		return _crack_meshes[st]
	var b := Res.blocks
	var quads: Array = []
	if b.st_flags[st] & BlockRegistry.F_CUBE:
		for d in 6:
			quads.append([ModelBaker.face_corners(d, Vector3.ZERO, Vector3.ONE), d])
	elif b.st_model[st] >= 0:
		var q: PackedFloat32Array = b.models[b.st_model[st]]
		for qi in q.size() / ModelBaker.QUAD_FLOATS:
			var o := qi * ModelBaker.QUAD_FLOATS
			var pts: Array = []
			for k in 4:
				pts.append(Vector3(q[o + k * 5], q[o + k * 5 + 1], q[o + k * 5 + 2]))
			quads.append([pts, int(q[o + 23])])
	if quads.is_empty():
		_crack_meshes[st] = null
		return null
	var nrm := [Vector3.DOWN, Vector3.UP, Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
	var stt := SurfaceTool.new()
	stt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for qd in quads:
		var pts2: Array = qd[0]
		var d2: int = clampi(int(qd[1]), 0, 5)
		var nv: Vector3 = nrm[d2]
		var uvq: Array = []
		var vq: Array = []
		for pp in pts2:
			var v: Vector3 = pp
			var uv := Vector2.ZERO
			match d2:
				0: uv = Vector2(v.x, 1.0 - v.z)
				1: uv = Vector2(v.x, v.z)
				2: uv = Vector2(1.0 - v.x, 1.0 - v.y)
				3: uv = Vector2(v.x, 1.0 - v.y)
				4: uv = Vector2(v.z, 1.0 - v.y)
				5: uv = Vector2(1.0 - v.z, 1.0 - v.y)
			uvq.append(uv)
			vq.append(v + nv * 0.002)
		for ix in [0, 1, 2, 0, 2, 3]:
			stt.set_uv(uvq[ix])
			stt.add_vertex(vq[ix])
	var m := stt.commit()
	_crack_meshes[st] = m
	return m


func swing_hand() -> void:
	if hand_swing <= 3:
		hand_swing = 6


func _attack() -> void:
	swing_hand()
	if not target.is_empty() and target.has("pos"):
		cm.mark_urgent(int(target["pos"].x), int(target["pos"].z))
	if target.has("entity"):
		entities.player_attack(target["entity"])
		player.exhaustion += 0.1
		player.attack_ticks = 0
		# a one-hit entity (cushion, painting, item frame ...) leaves the block behind it targeted: holding the button
		# must not go on to mine it (creative broke the block under a cushion 5 ticks later)
		_attack_on_entity = true
		mining_progress = 0.0
		return
	_attack_on_entity = false
	player.attack_ticks = 0   # Java resetAttackStrengthTicker on every swing
	if target.is_empty() or player.is_spectator():
		return
	if player.is_creative():
		if mining_cooldown <= 0:
			_break_block(target["pos"], false)
			mining_cooldown = 5


func _mining_tick() -> void:
	if mining_cooldown > 0:
		mining_cooldown -= 1
	if _attack_on_entity:
		if Input.is_action_pressed("attack"):
			mining_progress = 0.0
			mining_pos = Vector3i(0, -999, 0)
			return
		_attack_on_entity = false
	if player.is_creative() and Input.is_action_pressed("attack") and screen == null and mouse_captured and not target.is_empty() and not target.has("entity"):
		# Java continueAttack -> continueDestroyBlock (true every tick, a break every 5): the arm swings continuously
		swing_hand()
		if mining_cooldown <= 0:
			_break_block(target["pos"], false)
			mining_cooldown = 5
		return
	if player.is_creative() or player.is_spectator() or screen != null or not mouse_captured:
		mining_progress = 0.0
		return
	if not Input.is_action_pressed("attack") or target.is_empty() or target.has("entity"):
		mining_progress = 0.0
		mining_pos = Vector3i(0, -999, 0)
		return
	var p: Vector3i = target["pos"]
	if p != mining_pos:
		mining_pos = p
		mining_progress = 0.0
	if player.mode == Player.Mode.ADVENTURE and not Interaction.adventure_can_break(player.inventory.held(), int(target["state"])):
		return
	var st: int = target["state"]
	swing_hand()   # Java: swing every tick while destroying (also on unbreakable blocks)
	var d := Interaction.destroy_progress(player, st, self)
	if d <= 0.0:
		return
	mining_progress += d
	if game_time % 4 == 0:
		Audio.play("block." + Res.blocks.block_info[Res.blocks.st_block[st]]["sound"] + ".hit", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks", 0.25, 0.5)
	if mining_progress >= 1.0:
		_break_block(p, true)
		mining_progress = 0.0
		mining_cooldown = 5


func _break_block(p: Vector3i, survival: bool) -> void:
	cm.mark_urgent(p.x, p.z)
	var st := state_at(p.x, p.y, p.z)
	if st <= 0:
		return
	var blocks := Res.blocks
	if blocks.hardness[blocks.st_block[st]] < 0.0 and survival:
		return
	var nm := blocks.name_of(st)
	var replacement := 0
	if blocks.st_flags[st] & BlockRegistry.F_WATERLOGGED:
		replacement = blocks.WATER
	var be_data: Dictionary = BlockEntities.get_data(self, p).duplicate(true)
	set_block(p.x, p.y, p.z, replacement)
	Interaction.on_block_broken(self, p, st)
	# Java ShulkerBoxBlock.playerWillDestroy: creative players still get a non-empty box with its contents
	if not survival and nm.ends_with("shulker_box") and BlockEntities.component_of(be_data, "minecraft:container") != null:
		var sb := ItemStack.named(nm, 1)
		sb.components["minecraft:container"] = BlockEntities.component_of(be_data, "minecraft:container")
		entities.spawn_item(Vector3(p) + Vector3(0.5, 0.25, 0.5), sb)
	Sculk.vibrate(self, Vector3(p) + Vector3(0.5, 0.5, 0.5), true)
	Audio.play("block." + str(blocks.block_info[blocks.st_block[st]]["sound"]) + ".break", Vector3(p) + Vector3(0.5, 0.5, 0.5), "Blocks")
	entities.spawn_block_particles(p, st)
	if survival:
		player.exhaustion += 0.005
		var held := player.inventory.held()
		if gamerule("doTileDrops", true):
			for s in Loot.block_drops(st, held, self, p, be_data):
				entities.spawn_item(Vector3(p) + Vector3(0.5, 0.25, 0.5), s)
		Interaction.damage_tool(player, 1)
		player.stats["mined." + nm] = int(player.stats.get("mined." + nm, 0)) + 1


## Java Minecraft.startUseItem: entity, block, item - main hand first, offhand when the main hand does nothing.
func _use() -> void:
	if player.is_spectator() or use_cooldown > 0 or UseItem.is_using(player):
		return
	cm.mark_urgent(int(floor(player.pos.x)), int(floor(player.pos.z)))
	use_cooldown = 4
	var held := player.inventory.held()
	if target.has("entity"):
		swing_hand()
		entities.player_interact(target["entity"], held)
		return
	if not target.is_empty():
		if not player.sneaking or held.is_empty():
			if Interaction.use_block(self, target):
				swing_hand()
				return
		if not held.is_empty():
			if Interaction.use_item_on(self, held, target):
				swing_hand()
				return
	if UseItem.start(self, player, player.inventory.selected):
		return
	if not held.is_empty() and Interaction.has_use(held):
		swing_hand()
		Interaction.use_item(self, held)
		return
	UseItem.start(self, player, Inventory.OFFHAND)


func _pick_block() -> void:
	if target.is_empty() or target.has("entity"):
		return
	var nm := Res.blocks.name_of(int(target["state"]))
	var it := Res.items.id(nm)
	if it <= 0:
		return
	var inv := player.inventory
	for i in 9:
		if inv.get_slot(i).item == it:
			inv.selected = i
			return
	if player.is_creative():
		inv.set_slot(inv.selected, ItemStack.of(it, 1))


func _drop_held(all: bool) -> void:
	var inv := player.inventory
	var h := inv.held()
	if h.is_empty():
		return
	var s := h.split(h.count if all else 1)
	inv.changed.emit()
	Sculk.vibrate(self, player.pos, true)
	if Net.is_client():
		var ep := player.eye_pos() - Vector3(0, 0.3, 0)
		var dv := player.look_dir() * 0.3 + Vector3(0, 0.1, 0)
		Net.forward("item", [ep.x, ep.y, ep.z, s.to_dict(), dv.x, dv.y, dv.z, 40])
		return
	var e = entities.spawn_item(player.eye_pos() - Vector3(0, 0.3, 0), s)
	if e != null:
		e.vel = player.look_dir() * 0.3 + Vector3(0, 0.1, 0)
		e.pickup_delay = 40


func on_land(_p: Player) -> void:
	var st := state_at(int(floor(player.pos.x)), int(floor(player.pos.y - 0.2)), int(floor(player.pos.z)))
	if st > 0:
		Audio.play("block." + str(Res.blocks.block_info[Res.blocks.st_block[st]]["sound"]) + ".fall", player.pos, "Players", 0.5)


func _on_player_death() -> void:
	if player.sleeping:
		entities.wake_up()   # (a straw bed breaks)
	hud.death_shown = true
	player.vehicle = null
	if not gamerule("keepInventory", false):
		var inv := player.inventory
		for i in Inventory.SIZE:
			var s := inv.get_slot(i)
			if not s.is_empty():
				entities.spawn_item(player.pos + Vector3(0, 1, 0), s.copy(), true)
				s.clear()
		var xp := mini(player.xp_level * 7, 100)
		entities.spawn_xp(player.pos, xp)
		player.xp_level = 0
		player.xp_progress = 0.0
	inv_changed()
	var ds = load("res://scripts/ui/death_screen.gd").new()
	if gamerule("showDeathMessages", true):
		hud.chat_message(ds.death_message(str(Settings.get_v("player_name")), str(player.last_damage_source), str(player.last_attacker_id)))
	open_screen(ds)


## Respawn settling: once the respawn column has loaded, move the player to the nearest free 0.6 x 1.8 spot (world
## spawn: onto the surface) - never inside blocks.
var _settle_spawn := 0
var _settle_surface := false


func _settle_tick() -> void:
	if _settle_spawn <= 0 or player.dead:
		return
	_settle_spawn -= 1
	var x := int(floor(player.pos.x))
	var z := int(floor(player.pos.z))
	if not column_ready(x, z):
		player.vel = Vector3.ZERO
		return
	_settle_spawn = 0
	var y := player.pos.y
	if _settle_surface:
		var c := cm.get_chunk(x >> 4, z >> 4)
		if c != null and not c.heightmap.is_empty():
			y = float(c.heightmap[(x & 15) + (z & 15) * 16])
	var q := _free_spot(Vector3(player.pos.x, y, player.pos.z))
	player.pos = q
	player.prev_pos = q
	player.vel = Vector3.ZERO
	player.fall_distance = 0.0


func _free_spot(at: Vector3) -> Vector3:
	var gs := Callable(self, "state_at")
	for dy in 96:
		var yy := floorf(at.y) + dy
		if not Collision.overlaps_any(Vector3(at.x - 0.3, yy, at.z - 0.3), Vector3(at.x + 0.3, yy + 1.8, at.z + 0.3), gs, Res.blocks):
			return Vector3(at.x, yy, at.z)
	return at


## Java BedBlock.findStandUpPosition (simplified): a free spot with ground around the bed's head / foot, else on it.
func _stand_up_spot(hp: Vector3i):
	var gs := Callable(self, "state_at")
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 1), Vector3i(-1, 0, -1),
			Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(2, 0, 0), Vector3i(-2, 0, 0), Vector3i(0, 0, 2), Vector3i(0, 0, -2)]:
		for dy in [0, 1, -1]:
			var q := Vector3(hp + d) + Vector3(0.5, dy, 0.5)
			var below := state_at(int(floor(q.x)), int(floor(q.y)) - 1, int(floor(q.z)))
			if below > 0 and (Res.blocks.st_flags[below] & BlockRegistry.F_COLLIDE) != 0 \
					and not Collision.overlaps_any(Vector3(q.x - 0.3, q.y, q.z - 0.3), Vector3(q.x + 0.3, q.y + 1.8, q.z + 0.3), gs, Res.blocks):
				return q
	var on_bed := Vector3(hp) + Vector3(0.5, 0.5625, 0.5)
	if not Collision.overlaps_any(Vector3(on_bed.x - 0.3, on_bed.y, on_bed.z - 0.3), Vector3(on_bed.x + 0.3, on_bed.y + 1.8, on_bed.z + 0.3), gs, Res.blocks):
		return on_bed
	return null


func inv_changed() -> void:
	player.inventory.changed.emit()


func respawn() -> void:
	if hardcore:
		player.mode = Player.Mode.SPECTATOR
		player.dead = false
		player.health = 20.0
		hud.death_shown = false
		return
	var sp: Array = level.get("spawn", [0, 80, 0])
	var at := Vector3(sp[0] + 0.5, sp[1], sp[2] + 0.5)
	_settle_spawn = 1200
	_settle_surface = true
	if player.has_spawn:
		# Java ServerPlayer.findRespawnAndUseSpawnBlock: the bed (or charged anchor) must still be there, the player
		# stands up beside it (BedBlock.findStandUpPosition); else "no home bed" and the world spawn
		var hp := player.spawn_point
		at = Vector3(hp) + Vector3(0.5, 0.6, 0.5)
		_settle_surface = false
		if dimension == "overworld" and column_ready(hp.x, hp.z):
			var bs := state_at(hp.x, hp.y, hp.z)
			var bn := Res.blocks.name_of(bs) if bs > 0 else ""
			var stand = null
			if bn.ends_with("_bed") or (bn == "respawn_anchor" and int(Res.blocks.get_prop(bs, "charges")) > 0):
				stand = _stand_up_spot(hp)
			if stand == null:
				hud.chat_message(Res.tr_key("block.minecraft.spawn.not_valid", "You have no home bed or charged respawn anchor, or it was obstructed"))
				player.has_spawn = false
				at = Vector3(sp[0] + 0.5, sp[1], sp[2] + 0.5)
				_settle_surface = true
			else:
				at = stand
				_settle_spawn = 0
	player.respawn(at)
	hud.death_shown = false
	if dimension != "overworld":
		change_dimension("overworld", {"kind": "exact" if player.has_spawn else "spawn", "pos": at})
		return
	_update_origin(true)


## Advanced video settings (Video Settings > Advanced...): worker count, fast-core pinning, mesher options, culler flags.
func _apply_advanced(key := "") -> void:
	if cm == null:
		return
	cm.set_worker_count(int(Settings.get_v("adv_threads")))
	if key == "adv_pin_main":
		ChunkManager.pin_mode = 3 if Settings.get_v("adv_pin_main") else 0   # workers re-pin on their next start
		if Settings.get_v("adv_pin_main"):
			ChunkManager.pin_thread(true)
		elif Native.ok and Native.inst.has_method("set_thread_cpu_sets"):
			Native.inst.set_thread_cpu_sets(PackedInt32Array())   # no preference: any core
	cm.set_mesh_opts((0 if Settings.get_v("adv_leaf_cull") else 1) | (0 if Settings.get_v("adv_merge_faces") else 2) | (4 if Settings.get_v("adv_ctm") else 0))
	if _trd != null:
		_trd.debug_flags = (_trd.debug_flags & ~(64 | 2)) | (0 if Settings.get_v("adv_occlusion") else 64) | (0 if Settings.get_v("adv_dir_cull") else 2)


func _on_setting(key: String) -> void:
	if key.begins_with("adv_"):
		_apply_advanced(key)
		return
	match key:
		"render_distance":
			cm.set_radius(int(Settings.get_v("render_distance")))
			_apply_fog_distance()
		"fog":
			_apply_fog_distance()
		"biome_blend":
			cm.biome_blend = int(Settings.get_v("biome_blend"))
		"fov":
			camera.fov = float(Settings.get_v("fov"))


func _on_chunk_unloading(c: Chunk) -> void:
	entities.on_chunk_unloading(c)


func _on_chunk_loaded(c: Chunk) -> void:
	entities.on_chunk_loaded(c)


# ---------------------------------------------------------------- persistence

var _autosave_q: Array = []


## Incremental autosave: chunk snapshots taken under a 2 ms/frame budget, encoded on the background saver,
## region files + level data written after the queue drains (no main-thread stall every 2 minutes).
func _begin_autosave() -> void:
	if save == null or cm == null:
		return
	if Net.is_client():
		Net.client_save()
		return
	_autosave_q = cm.chunks.values()
	if _autosave_q.is_empty():
		save_all()


func _autosave_step() -> void:
	var t := Time.get_ticks_usec()
	while not _autosave_q.is_empty() and Time.get_ticks_usec() - t < 2000:
		var ch: Chunk = _autosave_q.pop_back()
		if ch.state < Chunk.DECORATED or ch.state == Chunk.EVICTED:
			continue
		entities.store_chunk_entities(ch)
		if not ch.saved_entities.is_empty():
			ch.modified = true
		if ch.modified:
			cm.queue_save(ch.frozen_copy())
		ch.saved_entities = []
	if _autosave_q.is_empty():
		cm.queue_after_saves(_finish_autosave_bg)


func _finish_autosave_bg() -> void:
	save.flush()
	call_deferred("_save_level_data", true)


func save_all() -> void:
	if save == null or cm == null:
		return
	cm.flush_saves()
	_autosave_q.clear()
	if Net.is_client():
		Net.client_save()   # the host owns the world; it stores this player's data
		return
	for c in cm.chunks.values():
		var ch: Chunk = c
		if ch.state < Chunk.DECORATED:
			continue
		# persist entities of every loaded chunk (a chunk holding persistent mobs must be saved even if no block changed)
		entities.store_chunk_entities(ch)
		if not ch.saved_entities.is_empty():
			ch.modified = true
		if ch.modified:
			save.save_chunk(ch)
		ch.saved_entities = []
	save.flush()
	_save_level_data()


## Player / level metadata and maps: encoded on the main thread; with background (autosave) the files are written
## by the saver thread (opening / renaming files can block for tens of ms here).
func _save_level_data(background := false) -> void:
	if save == null or closing and cm == null:
		return
	var writes: Array = Maps.collect_dirty(self)
	level["player"] = player.to_dict()
	level["game_time"] = game_time
	level["day_time"] = day_time
	level["raining"] = raining
	level["thundering"] = thundering
	level["weather_timer"] = weather_timer
	level["gamerules"] = gamerules
	level["difficulty"] = difficulty
	level["last_version"] = Res.version
	writes.append([save.dir.path_join("level.json"), save.level_bytes(level)])
	var write_all := func() -> void:
		for wv in writes:
			DirAccess.make_dir_recursive_absolute((wv[0] as String).get_base_dir())
			SaveManager.atomic_write(wv[0], wv[1])
	if background and cm != null and not closing:
		cm.queue_after_saves(write_all)
	else:
		write_all.call()


func save_and_close() -> void:
	if closing:
		return
	closing = true
	_capture_mouse(false)
	save_all()
	Net.on_world_closed(self)
	cm.shutdown()
	save.close()
	await get_tree().process_frame
