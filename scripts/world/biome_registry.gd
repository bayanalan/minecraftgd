## BiomeRegistry — biome IDs (byte) with climate/colour data. Vanilla mode loads every
## data/minecraft/worldgen/biome/*.json from the installed version; placeholder mode uses an original subset.
## Contract: id(name), names[i], temperature[i], downfall[i], grass/foliage/water colours (Color), data[i] (raw json).
## Thread-safety: immutable after build(); grass/foliage colours precomputed so workers never touch Images.
class_name BiomeRegistry
extends RefCounted

const OVERWORLD_26_3 := ["badlands", "bamboo_jungle", "beach", "birch_forest", "cherry_grove", "cold_ocean", "dappled_forest",
	"dark_forest", "deep_cold_ocean", "deep_dark", "deep_frozen_ocean", "deep_lukewarm_ocean", "deep_ocean", "desert",
	"dripstone_caves", "eroded_badlands", "flower_forest", "forest", "frozen_ocean", "frozen_peaks", "frozen_river", "grove",
	"ice_spikes", "jagged_peaks", "jungle", "lukewarm_ocean", "lush_caves", "mangrove_swamp", "meadow", "mushroom_fields", "ocean",
	"old_growth_birch_forest", "old_growth_pine_taiga", "old_growth_spruce_taiga", "pale_garden", "plains", "river", "savanna",
	"savanna_plateau", "snowy_beach", "snowy_plains", "snowy_slopes", "snowy_taiga", "sparse_jungle", "stony_peaks", "stony_shore",
	"sulfur_caves", "sunflower_plains", "swamp", "taiga", "the_void", "warm_ocean", "windswept_forest", "windswept_gravelly_hills",
	"windswept_hills", "windswept_savanna", "wooded_badlands", "basalt_deltas", "crimson_forest", "nether_wastes", "soul_sand_valley",
	"warped_forest", "end_barrens", "end_highlands", "end_midlands", "small_end_islands", "the_end"]

var names := PackedStringArray()
var index: Dictionary = {}
var temperature := PackedFloat32Array()
var downfall := PackedFloat32Array()
var precipitation := PackedByteArray()
var grass := PackedColorArray()
var foliage := PackedColorArray()
var dry_foliage := PackedColorArray()   # Java BiomeColors dry foliage (leaf litter): colormap or dry_foliage_color
var water := PackedColorArray()
var sky := PackedColorArray()
var fog := PackedColorArray()
var data: Array = []
var swamp_mod := PackedByteArray()


func id(name: String) -> int:
	return int(index.get(name.trim_prefix("minecraft:"), 0))


static func _hex(s, fallback: Color) -> Color:
	if s is String and s.begins_with("#"):
		return Color.html(s)
	if s is float or s is int:
		var v := int(s)
		return Color8((v >> 16) & 255, (v >> 8) & 255, v & 255)
	return fallback


func build() -> void:
	var listed: Array = []
	if Res.mode == "vanilla":
		for f in Res.list_files("data/minecraft/worldgen/biome/", ".json"):
			listed.append(f.get_file().get_basename())
	if listed.is_empty():
		listed = OVERWORLD_26_3.duplicate()
	listed.sort()
	if listed.has("plains"):
		listed.erase("plains")
		listed.push_front("plains")
	for n in listed:
		var j = Res.read_json("data/minecraft/worldgen/biome/" + n + ".json") if Res.mode == "vanilla" else null
		if not (j is Dictionary):
			j = _builtin(n)
		var i := names.size()
		names.append(n)
		index[n] = i
		data.append(j)
		var t := float(j.get("temperature", 0.8))
		var d := float(j.get("downfall", 0.4))
		temperature.append(t)
		downfall.append(d)
		precipitation.append(1 if bool(j.get("has_precipitation", true)) else 0)
		var eff: Dictionary = j.get("effects", {}) if j.get("effects") is Dictionary else {}
		var attrs: Dictionary = j.get("attributes", {}) if j.get("attributes") is Dictionary else {}
		var gc := Res.colormap(Res.grass_colormap, t, d, Color(0.47, 0.75, 0.33))
		var fc := Res.colormap(Res.foliage_colormap, t, d, Color(0.35, 0.65, 0.2))
		if eff.has("grass_color"):
			gc = _hex(eff["grass_color"], gc)
		if eff.has("foliage_color"):
			fc = _hex(eff["foliage_color"], fc)
		var mod := str(eff.get("grass_color_modifier", "none"))
		swamp_mod.append(1 if mod == "swamp" else (2 if mod == "dark_forest" else 0))
		if mod == "dark_forest":
			gc = Color8(int((gc.r8 & 0xFE) + 0x28) >> 1, int((gc.g8 & 0xFE) + 0x34) >> 1, int((gc.b8 & 0xFE) + 0x0A) >> 1)
		elif mod == "swamp":
			gc = Color8(0x6A, 0x70, 0x39)
		grass.append(gc)
		foliage.append(fc)
		var dfc := Res.colormap(Res.dry_foliage_colormap, t, d, Color8(0x5C, 0x3C, 0x32)) if Res.dry_foliage_colormap != null else Color8(0x5C, 0x3C, 0x32)
		dry_foliage.append(_hex(eff.get("dry_foliage_color", attrs.get("minecraft:visual/dry_foliage_color", null)), dfc))
		water.append(_hex(eff.get("water_color", attrs.get("minecraft:visual/water_color", "#3f76e4")), Color8(0x3F, 0x76, 0xE4)))
		sky.append(_hex(attrs.get("minecraft:visual/sky_color", eff.get("sky_color", "#78a7ff")), Color8(0x78, 0xA7, 0xFF)))
		fog.append(_hex(attrs.get("minecraft:visual/fog_color", eff.get("fog_color", "#c0d8ff")), Color8(0xC0, 0xD8, 0xFF)))


## Original fallback climate values (placeholder mode only).
static func _builtin(n: String) -> Dictionary:
	var t := 0.8
	var d := 0.4
	if n.contains("snowy") or n.contains("frozen") or n.contains("ice") or n == "grove" or n == "jagged_peaks":
		t = -0.5 if n != "snowy_beach" else 0.05
		d = 0.5
	elif n.contains("desert") or n.contains("badlands") or n.contains("savanna"):
		t = 2.0
		d = 0.0
	elif n.contains("jungle"):
		t = 0.95
		d = 0.9
	elif n.contains("taiga"):
		t = 0.25
		d = 0.8
	elif n.contains("swamp"):
		d = 0.9
	elif n.contains("birch"):
		t = 0.6
		d = 0.6
	elif n.contains("nether") or n.contains("crimson") or n.contains("warped") or n.contains("basalt") or n.contains("soul"):
		t = 2.0
		d = 0.0
	return {"temperature": t, "downfall": d, "has_precipitation": t < 1.5}


## Deep copy for one worker thread (ChunkManager._thread_gen): same content, private packed buffers and containers, so a
## worker's reads never touch the shared registry's reference counts. Every `blocks.st_flags[i]` copies the array (an
## atomic refcount increment + decrement); with the main thread and 5+ workers on the same counters this cache-line
## ping-pong made main-thread GDScript 2-100x slower in bursts (FrameProbe shared-table probe).
func thread_copy():
	var c = get_script().new()
	for p in get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		var v = get(n)
		if v is Array or v is Dictionary:
			c.set(n, v.duplicate(true))
		elif typeof(v) >= TYPE_PACKED_BYTE_ARRAY and typeof(v) <= TYPE_PACKED_VECTOR4_ARRAY:
			c.set(n, v.duplicate())
		else:
			c.set(n, v)
	return c
