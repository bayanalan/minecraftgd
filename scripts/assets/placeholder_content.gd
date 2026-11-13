## PlaceholderContent — ORIGINAL procedurally generated blocks/textures used only when no Minecraft
## install is available ("Original Placeholder Mode", clearly labelled in UI). No Mojang data.
## Contract: block_names(), blockstate(name), model(path), image(tex) — same shapes the vanilla path uses.
class_name PlaceholderContent

const BLOCKS := {
	"air": null, "stone": [0.5, 0.5, 0.52], "deepslate": [0.3, 0.3, 0.33], "dirt": [0.45, 0.32, 0.2],
	"grass_block": "grass", "sand": [0.86, 0.82, 0.6], "red_sand": [0.75, 0.4, 0.2], "gravel": [0.55, 0.52, 0.5],
	"bedrock": [0.2, 0.2, 0.2], "water": [0.25, 0.4, 0.9, 0.7], "lava": [0.95, 0.45, 0.1], "oak_log": "log",
	"oak_leaves": [0.3, 0.6, 0.25, -1.0], "oak_planks": [0.7, 0.55, 0.35], "cobblestone": [0.45, 0.45, 0.45],
	"glass": [0.8, 0.9, 1.0, -1.0], "coal_ore": [0.4, 0.4, 0.4], "iron_ore": [0.6, 0.5, 0.45], "gold_ore": [0.7, 0.65, 0.3],
	"diamond_ore": [0.4, 0.7, 0.75], "snow_block": [0.95, 0.97, 1.0], "ice": [0.6, 0.75, 0.95, 0.75], "clay": [0.62, 0.65, 0.72],
	"sandstone": [0.85, 0.8, 0.6], "terracotta": [0.6, 0.38, 0.28], "crafting_table": [0.6, 0.42, 0.25], "torch": "torch",
	"short_grass": "plant", "poppy": "flower", "dandelion": "flower", "cactus": [0.3, 0.55, 0.2], "spruce_log": "log",
	"spruce_leaves": [0.2, 0.4, 0.25, -1.0], "birch_log": "log", "birch_leaves": [0.45, 0.65, 0.3, -1.0], "furnace": [0.4, 0.4, 0.4],
	"glowstone": [0.95, 0.85, 0.5], "obsidian": [0.1, 0.05, 0.15], "tuff": [0.42, 0.43, 0.38], "calcite": [0.88, 0.88, 0.86],
	"netherrack": [0.45, 0.18, 0.18], "soul_sand": [0.33, 0.26, 0.2], "magma_block": [0.6, 0.25, 0.08], "end_stone": [0.86, 0.87, 0.65],
	"nether_portal": [0.45, 0.1, 0.8, 0.6], "end_portal": [0.03, 0.05, 0.08], "quartz_block": [0.92, 0.9, 0.86],
}


static func block_names() -> PackedStringArray:
	return PackedStringArray(BLOCKS.keys())


static func blockstate(name: String) -> Dictionary:
	if name == "oak_log" or name == "spruce_log" or name == "birch_log":
		return {"variants": {"axis=y": {"model": "block/" + name}, "axis=x": {"model": "block/" + name, "x": 90, "y": 90}, "axis=z": {"model": "block/" + name, "x": 90}}}
	if name == "air":
		return {"variants": {"": {"model": "block/air"}}}
	return {"variants": {"": {"model": "block/" + name}}}


static func model(path: String) -> Variant:
	var id := path.trim_prefix("assets/minecraft/models/").trim_suffix(".json")
	if id == "block/cube":
		return {"elements": [{"from": [0, 0, 0], "to": [16, 16, 16], "faces": {
			"down": {"texture": "#down", "cullface": "down"}, "up": {"texture": "#up", "cullface": "up"},
			"north": {"texture": "#north", "cullface": "north"}, "south": {"texture": "#south", "cullface": "south"},
			"west": {"texture": "#west", "cullface": "west"}, "east": {"texture": "#east", "cullface": "east"}}}]}
	if id == "block/cube_all":
		return {"parent": "block/cube", "textures": {"particle": "#all", "down": "#all", "up": "#all", "north": "#all", "south": "#all", "west": "#all", "east": "#all"}}
	if id == "block/cross":
		return {"ambientocclusion": false, "elements": [
			{"from": [0.8, 0, 8], "to": [15.2, 16, 8], "rotation": {"origin": [8, 8, 8], "axis": "y", "angle": 45, "rescale": true}, "shade": false, "faces": {"north": {"uv": [0, 0, 16, 16], "texture": "#cross"}, "south": {"uv": [0, 0, 16, 16], "texture": "#cross"}}},
			{"from": [8, 0, 0.8], "to": [8, 16, 15.2], "rotation": {"origin": [8, 8, 8], "axis": "y", "angle": 45, "rescale": true}, "shade": false, "faces": {"west": {"uv": [0, 0, 16, 16], "texture": "#cross"}, "east": {"uv": [0, 0, 16, 16], "texture": "#cross"}}}]}
	var name := id.trim_prefix("block/")
	if not BLOCKS.has(name) or name == "air":
		return null
	var kind = BLOCKS[name]
	if kind is String:
		match kind:
			"grass":
				return {"parent": "block/cube", "textures": {"particle": "block/dirt", "down": "block/dirt", "up": "block/grass_block_top", "north": "block/grass_block_side", "south": "block/grass_block_side", "west": "block/grass_block_side", "east": "block/grass_block_side"}}
			"log":
				return {"parent": "block/cube", "textures": {"down": "block/%s_top" % name, "up": "block/%s_top" % name, "north": "block/" + name, "south": "block/" + name, "west": "block/" + name, "east": "block/" + name}}
			"plant", "flower":
				return {"parent": "block/cross", "textures": {"cross": "block/" + name}}
			"torch":
				return {"elements": [{"from": [7, 0, 7], "to": [9, 10, 9], "faces": {
					"up": {"texture": "#t", "uv": [7, 6, 9, 8]}, "down": {"texture": "#t", "uv": [7, 13, 9, 15]},
					"north": {"texture": "#t", "uv": [7, 6, 9, 16]}, "south": {"texture": "#t", "uv": [7, 6, 9, 16]},
					"west": {"texture": "#t", "uv": [7, 6, 9, 16]}, "east": {"texture": "#t", "uv": [7, 6, 9, 16]}}}], "textures": {"t": "block/torch"}}
	return {"parent": "block/cube_all", "textures": {"all": "block/" + name}}


## Deterministic original pixel textures (value-noise speckle) per texture name.
static func image(tex: String) -> Image:
	var name := tex.trim_prefix("block/")
	var im := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var base := Color(0.6, 0.6, 0.6)
	var alpha := 1.0
	var cutout := false
	var key := name.trim_suffix("_top").trim_suffix("_side")
	if name == "grass_block_top" or name == "short_grass":
		base = Color(0.62, 0.62, 0.62)
	elif name == "grass_block_side":
		base = Color(0.45, 0.32, 0.2)
	elif name.ends_with("_log_top"):
		base = Color(0.65, 0.5, 0.3)
	elif name.ends_with("_log"):
		base = Color(0.4, 0.3, 0.18)
	elif name == "torch":
		base = Color(0.95, 0.75, 0.3)
	elif name == "poppy":
		base = Color(0.85, 0.15, 0.1)
	elif name == "dandelion":
		base = Color(0.95, 0.85, 0.15)
	elif BLOCKS.get(key) is Array:
		var c: Array = BLOCKS[key]
		base = Color(c[0], c[1], c[2])
		if c.size() > 3:
			if c[3] < 0:
				cutout = true
			else:
				alpha = c[3]
	var h := name.hash()
	for y in 16:
		for x in 16:
			var n := float((h ^ (x * 73856093) ^ (y * 19349663)) & 255) / 255.0
			var c := base * (0.82 + 0.3 * n)
			c.a = alpha
			if cutout and n < 0.25:
				c.a = 0.0
			if name == "grass_block_side" and y < 3:
				c = Color(0.55, 0.55, 0.55)
			if (name == "short_grass" or name == "poppy" or name == "dandelion" or name == "torch") and (abs(x - 8) > 3 + (y / 5) or (name != "short_grass" and y < 6 and abs(x - 8) > 1)):
				c.a = 0.0
			im.set_pixel(x, y, c)
	return im
