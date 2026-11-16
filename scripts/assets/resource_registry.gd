## Res (autoload) â€” single owner of loaded content: block registry, item registry, texture array,
## voxel materials, colormaps, language strings, sound definitions and data-pack JSON from the cached jar.
## Why: one source of truth; worker threads receive immutable references (blocks, colormaps) at job creation.
## Contract: load_vanilla(manifest) / load_placeholder() are awaitable coroutines emitting `progress`;
## read_json(path) for data files; mode is "vanilla" | "placeholder" | "".
extends Node

signal progress(msg: String, frac: float)
signal loaded

var mode := ""
var version := ""
var manifest: Dictionary = {}
var jar: JarAssetReader
const PACK_DIR := "user://resourcepacks"


## Pack folders / zips available in user://resourcepacks.
func available_packs() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(PACK_DIR):
		return out
	for d in DirAccess.get_directories_at(PACK_DIR):
		out.append(d)
	for f in DirAccess.get_files_at(PACK_DIR):
		if f.to_lower().ends_with(".zip"):
			out.append(f)
	return out
var blocks: BlockRegistry
var items: ItemRegistry
var atlas: AtlasBuilder
var baker: ModelBaker
var mat_opaque: ShaderMaterial
var mat_cutout: ShaderMaterial
var mat_item_block: ShaderMaterial   # block models of entities: light per instance (voxel_item.gdshader)
var mat_item_block_translucent: ShaderMaterial   # the same, blended (translucent block items: stained glass, ice)
var mat_translucent: ShaderMaterial
var grass_colormap: Image
var foliage_colormap: Image
var dry_foliage_colormap: Image   # 26.x colormap/dry_foliage.png (leaf litter)
var lang: Dictionary = {}
var sounds_json: Dictionary = {}
var asset_index: Dictionary = {}
var load_ms := 0
var diagnostics: Array = []
var _anim_accum := 0.0
var anim_ticks := 0
var _json_cache: Dictionary = {}


func _ready() -> void:
	pass  # global shader uniforms are declared in project.godot [shader_globals]


func _process(delta: float) -> void:
	if atlas == null:
		return
	_anim_accum += delta
	if _anim_accum >= 0.05:
		_anim_accum = fmod(_anim_accum, 0.05)
		anim_ticks += 1
		atlas.tick(anim_ticks)


func is_loaded() -> bool:
	return blocks != null


func read_json(p: String) -> Variant:
	if mode == "vanilla" and jar != null:
		return jar.read_json(p)
	return null


func has_file(p: String) -> bool:
	return mode == "vanilla" and jar != null and jar.has(p)


func list_files(prefix: String, ext: String = "") -> PackedStringArray:
	if mode == "vanilla" and jar != null:
		return jar.list(prefix, ext)
	return PackedStringArray()


func _cached_json(p: String) -> Variant:
	if _json_cache.has(p):
		return _json_cache[p]
	var j = jar.read_json(p)
	_json_cache[p] = j
	return j


func _vanilla_image(tex: String) -> Image:
	var p := "assets/minecraft/textures/" + tex + ".png"
	# files the launcher downloads through the asset index (26.3: the title panorama; the jar holds 1x1 placeholders)
	var obj := sound_object_path("minecraft/textures/" + tex + ".png") if not asset_index.is_empty() else ""
	if obj != "":
		var im0 := Image.new()
		if im0.load_png_from_buffer(FileAccess.get_file_as_bytes(obj)) == OK:
			return im0
	var b := jar.read_bytes(p)
	if b.is_empty():
		return null
	var im := Image.new()
	if im.load_png_from_buffer(b) != OK:
		return null
	return im


func load_image(tex: String) -> Image:
	if mode == "vanilla":
		return _vanilla_image(tex)
	return PlaceholderContent.image(tex)


func _vanilla_meta(tex: String) -> Variant:
	return jar.read_json("assets/minecraft/textures/" + tex + ".png.mcmeta")


func load_vanilla(m: Dictionary) -> bool:
	var t0 := Time.get_ticks_msec()
	manifest = m
	jar = JarAssetReader.new()
	if jar.open(str(m["cached_jar"])) != OK:
		diagnostics.append("Cannot open cached jar " + str(m["cached_jar"]))
		return false
	mode = "vanilla"
	version = str(m["version"])
	# resource packs (user://resourcepacks, folders or zips) overlay assets/ in priority order
	DirAccess.make_dir_recursive_absolute(PACK_DIR)
	for pn in Settings.get_v("resource_packs"):
		var err := jar.add_overlay(PACK_DIR.path_join(str(pn)))
		if err != "":
			diagnostics.append("Resource pack %s skipped: %s" % [pn, err])
		else:
			diagnostics.append("Resource pack enabled: %s" % pn)
	progress.emit("Reading block states", 0.05)
	await get_tree().process_frame
	var bs_files := jar.list("assets/minecraft/blockstates/", ".json")
	var names := PackedStringArray()
	for f in bs_files:
		names.append(f.get_file().get_basename())
	atlas = AtlasBuilder.new(_vanilla_image, _vanilla_meta)
	baker = ModelBaker.new(_cached_json, atlas.layer_for)
	blocks = BlockRegistry.new()
	print("[Res] blockstates listed: %d at %d ms" % [names.size(), Time.get_ticks_msec() - t0])
	progress.emit("Baking %d block models" % names.size(), 0.15)
	await get_tree().process_frame
	blocks.build(names, func(n): return _cached_json("assets/minecraft/blockstates/" + n + ".json"), baker, atlas.tex_class)
	# fluid textures are not referenced by models; allocate explicitly
	for t in ["block/water_still", "block/water_flow", "block/lava_still", "block/lava_flow", "block/water_overlay"]:
		atlas.layer_for(t)
	blocks.water_layer = atlas.layer_for("block/water_still")
	blocks.lava_layer = atlas.layer_for("block/lava_still")
	blocks.water_flow_layer = atlas.layer_for("block/water_flow")
	blocks.lava_flow_layer = atlas.layer_for("block/lava_flow")
	blocks.water_overlay_layer = atlas.layer_for("block/water_overlay")
	blocks.build_ctm(atlas)
	print("[Res] registry built: %d states, %d textures at %d ms" % [blocks.total_states, atlas.names.size(), Time.get_ticks_msec() - t0])
	progress.emit("Uploading %d texture layers" % atlas.names.size(), 0.6)
	await get_tree().process_frame
	atlas.build()
	grass_colormap = _vanilla_image("colormap/grass")
	foliage_colormap = _vanilla_image("colormap/foliage")
	dry_foliage_colormap = _vanilla_image("colormap/dry_foliage")
	print("[Res] atlas uploaded at %d ms" % (Time.get_ticks_msec() - t0))
	progress.emit("Loading items and language", 0.75)
	await get_tree().process_frame
	var l = jar.read_json("assets/minecraft/lang/en_us.json")
	lang = l if l is Dictionary else {}
	var sj = jar.read_json("assets/minecraft/sounds.json")
	sounds_json = sj if sj is Dictionary else {}
	_load_asset_index()
	lang_en = lang
	if str(Settings.get_v("language")) != "en_us":
		set_language(str(Settings.get_v("language")))
	items = ItemRegistry.new()
	items.build_vanilla(jar, blocks, lang)
	_make_materials()
	_json_cache.clear()
	load_ms = Time.get_ticks_msec() - t0
	diagnostics.append("Loaded %d blocks / %d states / %d textures / %d items in %d ms" % [blocks.names.size(), blocks.total_states, atlas.names.size(), items.names.size(), load_ms])
	if atlas.missing.size() > 0:
		diagnostics.append("Missing textures: %d (e.g. %s)" % [atlas.missing.size(), str(atlas.missing.slice(0, 5))])
	if blocks.missing_models.size() > 0:
		diagnostics.append("Blocks without baked geometry (special renderers pending): %d" % blocks.missing_models.size())
	progress.emit("Ready", 1.0)
	loaded.emit()
	return true


func load_placeholder() -> bool:
	var t0 := Time.get_ticks_msec()
	mode = "placeholder"
	version = "placeholder"
	atlas = AtlasBuilder.new(PlaceholderContent.image, func(_n): return null)
	baker = ModelBaker.new(PlaceholderContent.model, atlas.layer_for)
	blocks = BlockRegistry.new()
	blocks.build(PlaceholderContent.block_names(), PlaceholderContent.blockstate, baker, atlas.tex_class)
	blocks.water_layer = atlas.layer_for("block/water")
	blocks.lava_layer = atlas.layer_for("block/lava")
	blocks.water_flow_layer = blocks.water_layer
	blocks.lava_flow_layer = blocks.lava_layer
	blocks.water_overlay_layer = blocks.water_layer
	atlas.build()
	grass_colormap = null
	foliage_colormap = null
	dry_foliage_colormap = null
	items = ItemRegistry.new()
	items.build_placeholder(blocks)
	_make_materials()
	load_ms = Time.get_ticks_msec() - t0
	diagnostics.append("ORIGINAL PLACEHOLDER MODE: no Minecraft resources imported")
	progress.emit("Ready", 1.0)
	loaded.emit()
	return true


func _load_asset_index() -> void:
	asset_index.clear()
	var dir := str(manifest.get("assets_dir", ""))
	var idx := dir.path_join("indexes").path_join(str(manifest.get("asset_index", "")) + ".json")
	if FileAccess.file_exists(idx):
		var j = JSON.parse_string(FileAccess.get_file_as_string(idx))
		if j is Dictionary and j.get("objects") is Dictionary:
			asset_index = j["objects"]
	_apply_window_icon()


## Java Window.setIcon: the game's window / taskbar icon from the installed version's own assets (icons/icon_*.png in
## the asset index) - read at run time, never shipped (the exported .exe keeps Recraft's own file icon).
func _apply_window_icon() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for n in ["icons/icon_256x256.png", "icons/icon_128x128.png", "icons/icon_48x48.png", "icons/icon_32x32.png"]:
		var p := sound_object_path(n)
		if p == "":
			continue
		var img := Image.new()   # (hashed object files have no extension: decode the PNG bytes directly)
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) == OK and not img.is_empty():
			DisplayServer.set_icon(img)
			return


## Absolute path of a hashed sound object, e.g. "minecraft/sounds/dig/stone1.ogg" -> objects/xx/hash.
func sound_object_path(virtual_path: String) -> String:
	var o = asset_index.get(virtual_path)
	if not (o is Dictionary):
		return ""
	var h := str(o.get("hash", ""))
	var p := str(manifest.get("assets_dir", "")).path_join("objects").path_join(h.substr(0, 2)).path_join(h)
	return p if FileAccess.file_exists(p) else ""


func _make_materials() -> void:
	mat_opaque = ShaderMaterial.new()
	mat_opaque.shader = load("res://shaders/voxel_opaque.gdshader")
	mat_cutout = ShaderMaterial.new()
	mat_cutout.shader = load("res://shaders/voxel_cutout.gdshader")
	mat_item_block = ShaderMaterial.new()
	mat_item_block.shader = load("res://shaders/voxel_item.gdshader")
	mat_item_block_translucent = ShaderMaterial.new()
	mat_item_block_translucent.shader = load("res://shaders/voxel_item_translucent.gdshader")
	mat_translucent = ShaderMaterial.new()
	mat_translucent.shader = load("res://shaders/voxel_translucent.gdshader")
	for m in [mat_opaque, mat_cutout, mat_translucent, mat_item_block, mat_item_block_translucent]:
		m.set_shader_parameter("block_tex", atlas.texture)
	mat_translucent.render_priority = 1


## Java LanguageManager: the chosen language's strings (from the launcher's asset objects) over en_us.
var lang_en: Dictionary = {}


func set_language(code: String) -> bool:
	if lang_en.is_empty():
		lang_en = lang
	if code == "en_us":
		lang = lang_en
		return true
	var p := sound_object_path("minecraft/lang/%s.json" % code)
	if p == "":
		return false
	var j = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not (j is Dictionary):
		return false
	var m := lang_en.duplicate()
	m.merge(j, true)
	lang = m
	return true


## Language codes available locally (jar en_us + the asset index's minecraft/lang/*.json).
func language_codes() -> Array:
	var out := ["en_us"]
	for k in asset_index:
		var s := str(k)
		if s.begins_with("minecraft/lang/") and s.ends_with(".json"):
			var c := s.get_file().get_basename()
			if not out.has(c):
				out.append(c)
	return out


func tr_key(key: String, fallback: String = "") -> String:
	return str(lang.get(key, fallback if fallback != "" else key))


## Java TranslatableContents formatting: %1$s / %2$s positional and plain %s sequential arguments, %% -> %.
func tr_fmt(key: String, args: Array, fallback: String = "") -> String:
	var t := tr_key(key, fallback)
	for i in args.size():
		t = t.replace("%%%d$s" % (i + 1), str(args[i]))
	var k := 0
	while t.contains("%s") and k < args.size():
		var at := t.find("%s")
		t = t.substr(0, at) + str(args[k]) + t.substr(at + 2)
		k += 1
	return t.replace("%%", "%")


func block_display_name(name: String) -> String:
	var k := "block.minecraft." + name
	if lang.has(k):
		return lang[k]
	return name.replace("_", " ").capitalize()


## Biome colormap sampling (Java: temperature/downfall triangle lookup).
func colormap(img: Image, temperature: float, downfall: float, fallback: Color) -> Color:
	if img == null:
		return fallback
	var t := clampf(temperature, 0.0, 1.0)
	var d := clampf(downfall, 0.0, 1.0) * t
	var x := int((1.0 - t) * 255.0)
	var y := int((1.0 - d) * 255.0)
	return img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
