## Maps (Java MapItem / MapItemSavedData): using an empty map creates a filled_map (component minecraft:map_id)
## centred on Java's 128 << scale grid (center = floor((x + 64) / size) * size + size / 2 - 64). While a map is
## held, columns are scanned incrementally (2 per tick; Java does 1/16 of the columns per tick) and each pixel takes
## the top block's MapColor with Java's height shading (compare with the pixel to the north, +-0.6 thresholds
## with checkerboard dither) or water-depth shading. Pixels are saved per map in <world>/data/map_<id>.bin.
## MapColor: vanilla assignments by name / family (base_color); other blocks snap to the nearest palette colour.
## Zoom (scale 0..4) and locking via the cartography table; the holder's marker is drawn by ViewModel, banner markers
## (toggle_banner) and frame markers (frame_added / frame_removed) by decorations().
class_name Maps
extends RefCounted

static var cache: Dictionary = {}   # id -> {img: Image, tex: ImageTexture, dirty: bool}
static var _col := 0


static func new_map(world, x: float, z: float, scale: int = 0) -> ItemStack:
	var maps: Dictionary = world.level.get("maps", {}) if world.level.get("maps") is Dictionary else {}
	var id := int(world.level.get("next_map_id", 0))
	world.level["next_map_id"] = id + 1
	var size := 128 * (1 << scale)
	var cx := int(floor((x + 64.0) / size)) * size + size / 2 - 64
	var cz := int(floor((z + 64.0) / size)) * size + size / 2 - 64
	maps[str(id)] = {"x": cx, "z": cz, "scale": scale, "dim": world.dimension}
	world.level["maps"] = maps
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	img.fill(Color8(0xE4, 0xD9, 0xBC))   # unexplored parchment
	cache[id] = {"img": img, "tex": ImageTexture.create_from_image(img), "dirty": false}
	var s := ItemStack.named("filled_map", 1)
	s.components["minecraft:map_id"] = id
	return s


## The map id of a filled map or of a 26.x explorer map item (ocean_monument_map, desert_village_map ...: MapItems with
## their own model), -1 for anything else.
static func map_id(s: ItemStack) -> int:
	if s == null or s.is_empty():
		return -1
	var nm := s.name()
	if nm != "filled_map" and not (nm.ends_with("_map") and s.components.has("minecraft:map_id")):
		return -1
	return int(s.components.get("minecraft:map_id", -1))


static func _path(world, id: int) -> String:
	return SaveManager.ROOT.path_join(world.folder).path_join("data").path_join("map_%d.bin" % id)


static func entry(world, id: int) -> Dictionary:
	if not cache.has(id):
		var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
		img.fill(Color8(0xE4, 0xD9, 0xBC))
		var p := _path(world, id)
		if FileAccess.file_exists(p):
			var raw := FileAccess.get_file_as_bytes(p)
			if raw.size() > 4:
				var data := raw.slice(4).decompress(128 * 128 * 3, FileAccess.COMPRESSION_ZSTD)
				if data.size() == 128 * 128 * 3:
					img = Image.create_from_data(128, 128, false, Image.FORMAT_RGB8, data)
		cache[id] = {"img": img, "tex": ImageTexture.create_from_image(img), "dirty": false}
	return cache[id]


static func texture(world, id: int) -> Texture2D:
	return entry(world, id)["tex"]


static func save_all(world) -> void:
	for wv in collect_dirty(world):
		DirAccess.make_dir_recursive_absolute((wv[0] as String).get_base_dir())
		SaveManager.atomic_write(wv[0], wv[1])


## Encoded dirty maps as [path, bytes] (marked clean); the caller writes them (autosave: on the saver thread).
static func collect_dirty(world) -> Array:
	var out_list: Array = []
	for id in cache:
		var e: Dictionary = cache[id]
		if not e["dirty"]:
			continue
		e["dirty"] = false
		var data: PackedByteArray = (e["img"] as Image).get_data()
		var out := PackedByteArray([0x52, 0x43, 0x4D, 0x31])   # "RCM1"
		out.append_array(data.compress(FileAccess.COMPRESSION_ZSTD))
		out_list.append([_path(world, id), out])
	return out_list


static func clear() -> void:
	cache.clear()


## Java MapColor palette (base colours by id; brightness 180 / 220 / 255 / 135 is applied per pixel).
const PALETTE := [0, 0x7FB238, 0xF7E9A3, 0xC7C7C7, 0xFF0000, 0xA0A0FF, 0xA7A7A7, 0x007C00, 0xFFFFFF, 0xA4A8B8, 0x976D4D,
	0x707070, 0x4040FF, 0x8F7748, 0xFFFCF5, 0xD87F33, 0xB24CD8, 0x6699D8, 0xE5E533, 0x7FCC19, 0xF27FA5, 0x4C4C4C, 0x999999,
	0x4C7F99, 0x7F3FB2, 0x334CB2, 0x664C33, 0x667F33, 0x993333, 0x191919, 0xFAEE4D, 0x5CDBD5, 0x4A80FF, 0x00D93A, 0x815631,
	0x700200, 0xD1B1A1, 0x9F5224, 0x95576C, 0x706C8A, 0xBA8524, 0x677535, 0xA04D4E, 0x392923, 0x876B62, 0x575C5C, 0x7A4958,
	0x4C3E5C, 0x4C3223, 0x4C522A, 0x8E3C2E, 0x251610, 0xBD3031, 0x943F61, 0x5C191D, 0x167E86, 0x3A8E8C, 0x562C3E, 0x14B485,
	0x646464, 0xD8AF93, 0x7FA796]
# DyeColor.getMapColor (white wool / concrete is SNOW) and the terracotta set
const DYE := {"white": 0xFFFFFF, "orange": 0xD87F33, "magenta": 0xB24CD8, "light_blue": 0x6699D8, "yellow": 0xE5E533,
	"lime": 0x7FCC19, "pink": 0xF27FA5, "gray": 0x4C4C4C, "light_gray": 0x999999, "cyan": 0x4C7F99, "purple": 0x7F3FB2,
	"blue": 0x334CB2, "brown": 0x664C33, "green": 0x667F33, "red": 0x993333, "black": 0x191919}
const TERRA := {"white": 0xD1B1A1, "orange": 0x9F5224, "magenta": 0x95576C, "light_blue": 0x706C8A, "yellow": 0xBA8524,
	"lime": 0x677535, "pink": 0xA04D4E, "gray": 0x392923, "light_gray": 0x876B62, "cyan": 0x575C5C, "purple": 0x7A4958,
	"blue": 0x4C3E5C, "brown": 0x4C3223, "green": 0x4C522A, "red": 0x8E3C2E, "black": 0x251610}
# wood families (planks / stairs / slabs / fences / doors / signs / log tops)
const WOODS := {"oak": 0x8F7748, "spruce": 0x815631, "birch": 0xF7E9A3, "jungle": 0x976D4D, "acacia": 0xD87F33,
	"dark_oak": 0x664C33, "mangrove": 0x993333, "cherry": 0xD1B1A1, "pale_oak": 0xFFFCF5, "bamboo": 0xE5E533,
	"crimson": 0x943F61, "warped": 0x3A8E8C}
const NAMED := {"stone": 0x707070, "cobblestone": 0x707070, "mossy_cobblestone": 0x707070, "smooth_stone": 0x707070,
	"stone_bricks": 0x707070, "andesite": 0x707070, "gravel": 0x707070, "bedrock": 0x707070, "furnace": 0x707070,
	"granite": 0x976D4D, "diorite": 0xFFFCF5, "calcite": 0xD1B1A1, "tuff": 0x392923, "dripstone_block": 0x4C3223,
	"pointed_dripstone": 0x4C3223, "grass_block": 0x7FB238, "dirt": 0x976D4D, "coarse_dirt": 0x976D4D, "rooted_dirt": 0x976D4D,
	"farmland": 0x976D4D, "dirt_path": 0x976D4D, "podzol": 0x815631, "mycelium": 0x7F3FB2, "mud": 0x575C5C,
	"packed_mud": 0x976D4D, "mud_bricks": 0x876B62, "sand": 0xF7E9A3, "sandstone": 0xF7E9A3, "red_sand": 0xD87F33,
	"red_sandstone": 0xD87F33, "clay": 0xA4A8B8, "snow": 0xFFFFFF, "snow_block": 0xFFFFFF, "powder_snow": 0xFFFFFF,
	"ice": 0xA0A0FF, "packed_ice": 0xA0A0FF, "blue_ice": 0xA0A0FF, "frosted_ice": 0xA0A0FF, "water": 0x4040FF,
	"bubble_column": 0x4040FF, "kelp": 0x4040FF, "kelp_plant": 0x4040FF, "seagrass": 0x4040FF, "tall_seagrass": 0x4040FF,
	"lava": 0xFF0000, "fire": 0xFF0000, "tnt": 0xFF0000, "redstone_block": 0xFF0000, "iron_block": 0xA7A7A7,
	"gold_block": 0xFAEE4D, "diamond_block": 0x5CDBD5, "lapis_block": 0x4A80FF, "emerald_block": 0x00D93A,
	"coal_block": 0x191919, "obsidian": 0x191919, "crying_obsidian": 0x191919, "basalt": 0x191919, "polished_basalt": 0x191919,
	"blackstone": 0x191919, "sculk": 0x191919, "netherrack": 0x700200, "nether_bricks": 0x700200, "red_nether_bricks": 0x700200,
	"magma_block": 0x700200, "nether_wart_block": 0x993333, "warped_wart_block": 0x14B485, "crimson_nylium": 0xBD3031,
	"warped_nylium": 0x167E86, "soul_sand": 0x664C33, "soul_soil": 0x664C33, "glowstone": 0xF7E9A3, "shroomlight": 0x993333,
	"end_stone": 0xF7E9A3, "end_stone_bricks": 0xF7E9A3, "purpur_block": 0xB24CD8, "purpur_pillar": 0xB24CD8,
	"chorus_plant": 0x7F3FB2, "chorus_flower": 0x7F3FB2, "quartz_block": 0xFFFCF5, "bricks": 0x993333, "bone_block": 0xF7E9A3,
	"hay_block": 0xE5E533, "melon": 0x7FCC19, "pumpkin": 0xD87F33, "carved_pumpkin": 0xD87F33, "jack_o_lantern": 0xD87F33,
	"prismarine": 0x4C7F99, "prismarine_bricks": 0x5CDBD5, "dark_prismarine": 0x5CDBD5, "sea_lantern": 0xFFFCF5,
	"sponge": 0xE5E533, "wet_sponge": 0xE5E533, "slime_block": 0x7FB238, "honey_block": 0xD87F33, "moss_block": 0x667F33,
	"moss_carpet": 0x667F33, "pale_moss_block": 0x999999, "pale_moss_carpet": 0x999999, "amethyst_block": 0x7F3FB2,
	"budding_amethyst": 0x7F3FB2, "brown_mushroom_block": 0x976D4D, "red_mushroom_block": 0x993333, "mushroom_stem": 0xC7C7C7,
	"terracotta": 0xD87F33, "raw_iron_block": 0xD8AF93, "raw_gold_block": 0xFAEE4D, "raw_copper_block": 0xD87F33,
	"glow_lichen": 0x7FA796, "spawner": 0x707070, "chest": 0x8F7748, "crafting_table": 0x8F7748, "bookshelf": 0x8F7748}
const PLANT := 0x007C00


## MapColor of a block state (Java BlockBehaviour.Properties.mapColor): NONE (-1: the map looks through it) for air,
## glass, torches, rails, wire; the vanilla assignments by name / family; anything else snaps its average texture
## colour to the nearest palette entry (maps only ever use the 62 MapColors).
static func base_color(st: int) -> int:
	if st <= 0:
		return -1
	var b := Res.blocks
	var nm := b.name_of(st)
	if NAMED.has(nm):
		return NAMED[nm]
	if nm.ends_with("air") or nm.contains("glass") or nm.contains("torch") or nm.ends_with("rail") or nm == "redstone_wire" or nm == "light" or nm == "barrier" or nm == "structure_void" or nm.ends_with("button") or nm == "tripwire" or nm == "ladder" or nm == "lever":
		return -1
	if nm.ends_with("_leaves") or nm.ends_with("_sapling") or nm in ["short_grass", "tall_grass", "fern", "large_fern", "vine", "lily_pad", "cactus", "sugar_cane", "bamboo", "sweet_berry_bush", "dead_bush", "azalea", "flowering_azalea"] or nm.ends_with("_tulip") or nm in ["dandelion", "poppy", "blue_orchid", "allium", "azure_bluet", "oxeye_daisy", "cornflower", "lily_of_the_valley", "sunflower", "lilac", "rose_bush", "peony", "wither_rose", "torchflower"]:
		return PLANT
	for d in DYE:
		var dn: String = d
		if nm.begins_with(dn + "_"):
			var rest := nm.substr(dn.length() + 1)
			if rest == "terracotta":
				return TERRA[dn]
			if rest in ["wool", "carpet", "concrete", "concrete_powder", "glazed_terracotta", "shulker_box", "bed", "banner", "wall_banner", "candle"]:
				return DYE[dn]
	if nm.contains("deepslate"):
		return 0x646464
	if nm.ends_with("_ore"):
		return 0x707070
	if nm.contains("copper"):
		if nm.contains("oxidized"):
			return 0x167E86
		if nm.contains("weathered"):
			return 0x3A8E8C
		if nm.contains("exposed"):
			return 0x876B62
		return 0xD87F33
	for w in WOODS:
		var wn: String = w
		if nm.begins_with(wn + "_"):
			# stripped / plain logs: Java log(top, side) - seen from above the top colour (= planks)
			return WOODS[wn]
		if nm.begins_with("stripped_" + wn + "_"):
			return WOODS[wn]
	for fam in ["stone", "cobblestone", "andesite", "smooth_stone", "stone_brick", "mossy_stone_brick", "cobbled"]:
		if nm.begins_with(fam):
			return 0x707070
	for fam2 in [["sandstone", 0xF7E9A3], ["smooth_sandstone", 0xF7E9A3], ["cut_sandstone", 0xF7E9A3], ["red_sandstone", 0xD87F33],
			["quartz", 0xFFFCF5], ["brick", 0x993333], ["nether_brick", 0x700200], ["polished_blackstone", 0x191919], ["blackstone", 0x191919],
			["prismarine", 0x4C7F99], ["purpur", 0xB24CD8], ["end_stone", 0xF7E9A3], ["granite", 0x976D4D], ["diorite", 0xFFFCF5],
			["polished_andesite", 0x707070], ["tuff", 0x392923], ["mud_brick", 0x876B62], ["resin", 0xD87F33]]:
		if nm.begins_with(str(fam2[0])):
			return int(fam2[1])
	var c := ItemIcons.average_color(st)
	return nearest(int(c.r8), int(c.g8), int(c.b8))


static var _nearest: Dictionary = {}


static func nearest(r: int, g: int, bb: int) -> int:
	var key := (r << 16) | (g << 8) | bb
	if _nearest.has(key):
		return _nearest[key]
	var best := PALETTE[1]
	var bd := 1 << 30
	for k in range(1, PALETTE.size()):
		var pc: int = PALETTE[k]
		var dr := ((pc >> 16) & 255) - r
		var dg := ((pc >> 8) & 255) - g
		var db := (pc & 255) - bb
		var d := dr * dr + dg * dg + db * db
		if d < bd:
			bd = d
			best = pc
	_nearest[key] = best
	return best

## Java MapItem.update while the map is held: each tick the columns congruent to the holder's step (mod 16) inside the
## 128 >> scale circle are rescanned (a column whose pixel changed also triggers the next one); a pixel covers
## 2^scale blocks: the most common MapColor among them, brightness from the mean height against the pixel to the
## north ((d1 - d0) * 4 / (2^scale + 4) + checker * 0.4) or, for water, from the water depth; outside (r - 2)^2 only
## checkerboard pixels update. Locked maps never change.
static func update(world, id: int) -> void:
	var maps: Dictionary = world.level.get("maps", {})
	var md: Dictionary = maps.get(str(id), {})
	if md.is_empty() or str(md.get("dim", "overworld")) != world.dimension or bool(md.get("locked", false)):
		return
	if md.has("explore"):
		ExplorerMaps.ensure(id)   # (an explorer map whose structure search is pending - restarted after a reload)
		return
	var e := entry(world, id)
	var img: Image = e["img"]
	var sc := int(md.get("scale", 0))
	var i := 1 << sc
	var j := int(md["x"])
	var k := int(md["z"])
	var p: Player = world.player
	var l := int(floor(p.pos.x - j)) / i + 64   # Java int division (towards zero), like GDScript's
	var i1 := int(floor(p.pos.z - k)) / i + 64
	var j1 := 128 / i
	if world.dimension == "the_nether":
		j1 /= 2
	var step := int(md.get("step", 0)) + 1
	md["step"] = step
	if (step & 15) == 0 and md.has("banners"):
		check_banners(world, md)
	var b := Res.blocks
	var water_id := b.block_id("water")
	var changed := false
	var flag := false
	for k1 in range(l - j1 + 1, l + j1):
		if (k1 & 15) != (step & 15) and not flag:
			continue
		flag = false
		var d0 := 0.0
		for l1 in range(i1 - j1 - 1, i1 + j1):
			if not (k1 >= 0 and l1 >= -1 and k1 < 128 and l1 < 128):
				continue
			var i2 := (k1 - l) * (k1 - l) + (l1 - i1) * (l1 - i1)
			var outer := i2 > (j1 - 2) * (j1 - 2)
			var j2 := (j / i + k1 - 64) * i
			var k2 := (k / i + l1 - 64) * i
			var counts := {}
			var order: Array = []
			var depth := 0
			var d1 := 0.0
			var any := false
			for i3 in i:
				for j3 in i:
					var wx := j2 + i3
					var wz := k2 + j3
					var ch: Chunk = world.cm.get_chunk(wx >> 4, wz >> 4)
					if ch == null or ch.state < Chunk.DECORATED or ch.heightmap.is_empty():
						continue
					any = true
					var y: int = ch.heightmap[(wx & 15) + (wz & 15) * 16]
					var st := 0
					if y <= Coords.MIN_Y + 1:
						st = b.default_state("bedrock")
					else:
						y -= 1
						st = ch.get_block(wx & 15, y, wz & 15)
						while y > Coords.MIN_Y and base_color(st) < 0:
							y -= 1
							st = ch.get_block(wx & 15, y, wz & 15)
						if y > Coords.MIN_Y and st > 0 and (b.st_flags[st] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0:
							var yy := y - 1
							while yy > Coords.MIN_Y:
								var s2 := ch.get_block(wx & 15, yy, wz & 15)
								depth += 1
								yy -= 1
								if s2 <= 0 or (b.st_flags[s2] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) == 0:
									break
							if (b.st_flags[st] & BlockRegistry.F_LIQUID) == 0:
								st = b.WATER   # getCorrectStateForFluidBlock: the fluid shows over a non-full block
					d1 += float(y) / float(i * i)
					var col := base_color(st)
					if not counts.has(col):
						counts[col] = 0
						order.append(col)
					counts[col] = int(counts[col]) + 1
			if not any:
				continue
			depth /= i * i
			var mc := -1
			var best := 0
			for cc in order:
				if int(counts[cc]) > best:
					best = int(counts[cc])
					mc = cc
			var shade := 220
			if mc == 0x4040FF:
				var d2 := depth * 0.1 + float((k1 + l1) & 1) * 0.2
				shade = 255 if d2 < 0.5 else (180 if d2 > 0.9 else 220)
			else:
				var d3 := (d1 - d0) * 4.0 / float(i + 4) + (float((k1 + l1) & 1) - 0.5) * 0.4
				shade = 255 if d3 > 0.6 else (180 if d3 < -0.6 else 220)
			d0 = d1
			if l1 >= 0 and i2 < j1 * j1 and (not outer or ((k1 + l1) & 1) != 0) and mc >= 0:
				var cl := Color8(((mc >> 16) & 255) * shade / 255, ((mc >> 8) & 255) * shade / 255, (mc & 255) * shade / 255)
				if img.get_pixel(k1, l1) != cl:
					img.set_pixel(k1, l1, cl)
					changed = true
					flag = true
	if changed:
		(e["tex"] as ImageTexture).update(img)
		e["dirty"] = true


## MapItemSavedData.scaled (cartography table + paper): a fresh map one scale up, centred on the 128 << scale grid
## cell holding the old centre.
static func scaled_copy(world, s: ItemStack) -> ItemStack:
	var md: Dictionary = (world.level.get("maps", {}) as Dictionary).get(str(map_id(s)), {})
	if md.is_empty():
		return ItemStack.new()
	var ns := clampi(int(md.get("scale", 0)) + 1, 0, 4)
	var out := new_map(world, float(md["x"]), float(md["z"]), ns)
	(world.level["maps"] as Dictionary)[str(map_id(out))]["dim"] = md.get("dim", world.dimension)
	return out


## MapItemSavedData.locked (cartography table + glass pane): a copy of the pixels under a new id that never updates.
static func locked_copy(world, s: ItemStack) -> ItemStack:
	var oid := map_id(s)
	var md: Dictionary = (world.level.get("maps", {}) as Dictionary).get(str(oid), {})
	if md.is_empty():
		return ItemStack.new()
	var id := int(world.level.get("next_map_id", 0))
	world.level["next_map_id"] = id + 1
	var nd := md.duplicate(true)
	nd["locked"] = true
	(world.level["maps"] as Dictionary)[str(id)] = nd
	var img: Image = (entry(world, oid)["img"] as Image).duplicate()
	cache[id] = {"img": img, "tex": ImageTexture.create_from_image(img), "dirty": true}
	var out := s.copy()
	out.count = 1
	out.components["minecraft:map_id"] = id
	return out


static func info(world, s: ItemStack) -> Dictionary:
	return (world.level.get("maps", {}) as Dictionary).get(str(map_id(s)), {})


# ------------------------------------------------------------------ decorations (Java MapItemSavedData)

static func _md(world, id: int) -> Dictionary:
	var maps = world.level.get("maps", {})
	return (maps as Dictionary).get(str(id), {}) if maps is Dictionary else {}


## MapItemSavedData.addDecoration: map byte coordinates (2 per map pixel, centred) of a world position.
static func _map_xy(md: Dictionary, x: float, z: float) -> Vector2i:
	var sc := float(1 << int(md.get("scale", 0)))
	var fx := (x - float(md["x"])) / sc
	var fz := (z - float(md["z"])) / sc
	return Vector2i(clampi(int(fx * 2.0 + 0.5), -128, 127), clampi(int(fz * 2.0 + 0.5), -128, 127))


static func _inside(md: Dictionary, x: float, z: float) -> bool:
	var sc := float(1 << int(md.get("scale", 0)))
	var fx := (x - float(md["x"])) / sc
	var fz := (z - float(md["z"])) / sc
	return fx >= -63.0 and fz >= -63.0 and fx <= 63.0 and fz <= 63.0


## Rotation byte (16 steps) of a decoration turned by deg (Java: (deg +- 8) * 16 / 360 truncated).
static func _rot16(deg: float) -> int:
	return int((deg + (-8.0 if deg < 0.0 else 8.0)) * 16.0 / 360.0)


## MapBanner.fromWorld: colour and custom name of the banner at pos, {} when there is none.
static func banner_at(world, pos: Vector3i) -> Dictionary:
	var nm := Res.blocks.name_of(maxi(0, world.state_at(pos.x, pos.y, pos.z)))
	if not nm.ends_with("_banner"):
		return {}
	var cn = BlockEntities.get_data(world, pos).get("CustomName", null)
	var label := ""
	if cn is Dictionary:
		label = str((cn as Dictionary).get("text", ""))
	elif cn != null:
		label = str(cn)
	return {"color": nm.trim_suffix("_wall_banner").trim_suffix("_banner"), "name": label}


## MapItemSavedData.toggleBanner (MapItem.useOn a banner): adds the banner's marker - its dye colour, turned 180 deg,
## its name under it - or removes the same marker again. Only inside the map's area; at most 256 tracked markers.
static func toggle_banner(world, s: ItemStack, pos: Vector3i) -> bool:
	var md := _md(world, map_id(s))
	if md.is_empty() or str(md.get("dim", "overworld")) != world.dimension:
		return false
	var x := pos.x + 0.5
	var z := pos.z + 0.5
	if not _inside(md, x, z):
		return false
	var cur := banner_at(world, pos)
	if cur.is_empty():
		return false
	var key := "%d,%d,%d" % [pos.x, pos.y, pos.z]
	var bl: Dictionary = md.get("banners", {})
	if bl.has(key) and str(bl[key]["color"]) == cur["color"] and str(bl[key]["name"]) == cur["name"]:
		bl.erase(key)
	elif bl.size() + (md.get("frames", {}) as Dictionary).size() < 256:
		var mp := _map_xy(md, x, z)
		cur["mx"] = mp.x
		cur["mz"] = mp.y
		bl[key] = cur
	else:
		return false
	md["banners"] = bl
	md["rev"] = int(md.get("rev", 0)) + 1
	return true


## MapItemSavedData.checkBanners: markers whose banner was broken or changed disappear (loaded chunks only).
static func check_banners(world, md: Dictionary) -> void:
	var bl: Dictionary = md.get("banners", {})
	for key in bl.keys():
		var pp: PackedStringArray = str(key).split(",")
		var pos := Vector3i(int(pp[0]), int(pp[1]), int(pp[2]))
		var ch = world.cm.get_chunk(pos.x >> 4, pos.z >> 4) if world.cm != null else null
		if ch == null or ch.state < Chunk.DECORATED:
			continue
		var cur := banner_at(world, pos)
		if cur.is_empty() or cur["color"] != str(bl[key]["color"]) or cur["name"] != str(bl[key]["name"]):
			bl.erase(key)
			md["rev"] = int(md.get("rev", 0)) + 1


## A map put in an item frame shows the green frame marker at the frame (Java tickCarriedBy for framed maps: the frame's
## block position, rotation = horizontal facing * 90; floor / ceiling frames -90).
static func frame_added(world, frame_cell: Vector3i, n: Vector3i, s: ItemStack) -> void:
	var md := _md(world, map_id(s))
	if md.is_empty() or str(md.get("dim", "overworld")) != world.dimension:
		return
	var key := "%d,%d,%d" % [frame_cell.x, frame_cell.y, frame_cell.z]
	var fr: Dictionary = md.get("frames", {})
	if not _inside(md, frame_cell.x, frame_cell.z):
		if fr.erase(key):
			md["rev"] = int(md.get("rev", 0)) + 1
		return
	var deg: float = {Vector3i(0, 0, 1): 0.0, Vector3i(-1, 0, 0): 90.0, Vector3i(0, 0, -1): 180.0, Vector3i(1, 0, 0): 270.0}.get(n, -90.0)
	var mp := _map_xy(md, frame_cell.x, frame_cell.z)
	var nv := {"mx": mp.x, "mz": mp.y, "rot": _rot16(deg)}
	if fr.get(key) == nv:
		return
	fr[key] = nv
	md["frames"] = fr
	md["rev"] = int(md.get("rev", 0)) + 1


## MapItemSavedData.removedFromFrame
static func frame_removed(world, frame_cell: Vector3i, s: ItemStack) -> void:
	var md := _md(world, map_id(s))
	if md.is_empty():
		return
	var fr: Dictionary = md.get("frames", {})
	if fr.erase("%d,%d,%d" % [frame_cell.x, frame_cell.y, frame_cell.z]):
		md["rev"] = int(md.get("rev", 0)) + 1


## Decorations other than the holder's marker: [[sprite, map x, map z, rot16, name, shown on frames]] in Java's order
## (banners, then frames). MapDecorationType.showOnItemFrame: banners yes, the frame marker no.
static func decorations(world, id: int) -> Array:
	var md := _md(world, id)
	var out: Array = []
	var bl: Dictionary = md.get("banners", {})
	for key in bl:
		var b: Dictionary = bl[key]
		out.append(["map/decorations/%s_banner" % b["color"], int(b["mx"]), int(b["mz"]), 8, str(b.get("name", "")), true])
	var fr: Dictionary = md.get("frames", {})
	for key2 in fr:
		var f: Dictionary = fr[key2]
		out.append(["map/decorations/frame", int(f["mx"]), int(f["mz"]), int(f["rot"]), "", false])
	# explorer map targets (MapItemSavedData.addTargetDecoration: rotation 180 = byte 8, ExplorerMaps)
	for tg in md.get("targets", []):
		var txy := _map_xy(md, float(tg["x"]), float(tg["z"]))
		out.append([ExplorerMaps.decoration_texture(str(tg["t"])), txy.x, txy.y, 8, "", false])
	return out


static func rev(world, id: int) -> int:
	return int(_md(world, id).get("rev", 0))


static var _labels: Dictionary = {}
static var _glyphs: Image = null


## A decoration name as a texture: the vanilla ASCII bitmap font (8 x 8 cells, width = rightmost opaque column + 1,
## advance + 1, space 4), white on a 50 % black background one pixel around (Java Font.drawInBatch with a background).
static func label_texture(text: String) -> ImageTexture:
	if _labels.has(text):
		return _labels[text]
	if _glyphs == null:
		_glyphs = Res.load_image("font/ascii")
	var adv: Array = []
	var w := 0
	for ch in text:
		var c := ch.unicode_at(0)
		var a := 4
		if c != 32 and c < 256 and _glyphs != null:
			var gx := (c % 16) * 8
			var gy := (c / 16) * 8
			var right := -1
			for x in 8:
				for y in 8:
					if _glyphs.get_pixel(gx + x, gy + y).a > 0.0:
						right = maxi(right, x)
			a = right + 2 if right >= 0 else 4
		adv.append(a)
		w += a
	var img := Image.create(maxi(w + 1, 2), 10, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0.5))
	var x0 := 1
	var i := 0
	for ch2 in text:
		var c2 := ch2.unicode_at(0)
		if c2 != 32 and c2 < 256 and _glyphs != null:
			var gx2 := (c2 % 16) * 8
			var gy2 := (c2 / 16) * 8
			for x in 8:
				for y in 8:
					if _glyphs.get_pixel(gx2 + x, gy2 + y).a > 0.0 and x0 + x < img.get_width():
						img.set_pixel(x0 + x, 1 + y, Color.WHITE)
		x0 += int(adv[i])
		i += 1
	var tex := ImageTexture.create_from_image(img)
	if _labels.size() > 64:
		_labels.clear()
	_labels[text] = tex
	return tex