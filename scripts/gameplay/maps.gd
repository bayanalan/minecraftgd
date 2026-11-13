## Maps (Java MapItem / MapItemSavedData): using an empty map creates a filled_map (component minecraft:map_id)
## centred on Java's 128 << scale grid (center = floor((x + 64) / size) * size + size / 2 - 64). While a map is
## held, columns are scanned incrementally (2 per tick; Java does 1/16 of the columns per tick) and each pixel takes
## the top block's MapColor with Java's height shading (compare with the pixel to the north, +-0.6 thresholds
## with checkerboard dither) or water-depth shading. Pixels are saved per map in <world>/data/map_<id>.bin.
## APPROXIMATE: MapColor bases are listed for common blocks; others use the block's average texture color.
## No banners/markers, no zoom via cartography table, no locked maps.
class_name Maps
extends RefCounted

# Java MapColor base colors by block name / suffix
const COLORS := {"grass_block": 0x7FB238, "sand": 0xF7E9A3, "sandstone": 0xF7E9A3, "end_stone": 0xF7E9A3, "birch": 0xF7E9A3,
	"lava": 0xFF0000, "fire": 0xFF0000, "tnt": 0xFF0000, "ice": 0xA0A0FF, "packed_ice": 0xA0A0FF, "blue_ice": 0xA0A0FF,
	"iron_block": 0xA7A7A7, "snow": 0xFFFFFF, "snow_block": 0xFFFFFF, "powder_snow": 0xFFFFFF, "clay": 0xA4A8B8,
	"dirt": 0x976D4D, "coarse_dirt": 0x976D4D, "farmland": 0x976D4D, "rooted_dirt": 0x976D4D, "dirt_path": 0x976D4D,
	"stone": 0x707070, "cobblestone": 0x707070, "gravel": 0x707070, "andesite": 0x707070, "water": 0x4040FF,
	"oak": 0x8F7748, "quartz_block": 0xFFFCF5, "diorite": 0xFFFCF5, "netherrack": 0x700200, "deepslate": 0x646464,
	"podzol": 0x815631, "mycelium": 0x7F3FB2, "red_sand": 0xD87F33, "terracotta": 0xD1B1A1, "gold_block": 0xFAEE4D,
	"diamond_block": 0x5CDBD5, "lapis_block": 0x4A80FF, "emerald_block": 0x00D93A, "obsidian": 0x191919,
	"soul_sand": 0x664C33, "soul_soil": 0x664C33, "mud": 0x575C5C, "moss_block": 0x667F33, "pale_moss_block": 0xA0A0A0,
	"spruce": 0x815631, "jungle": 0x976D4D, "acacia": 0xD87F33, "dark_oak": 0x664C33, "mangrove": 0x993333,
	"cherry": 0xD1B1A1, "crimson": 0x943F61, "warped": 0x3A8E8C, "basalt": 0x191919, "blackstone": 0x191919,
	"calcite": 0xD1B1A1, "tuff": 0x575C5C, "granite": 0x976D4D, "prismarine": 0x4C7F99}
const PLANT := 0x007C00

static var cache: Dictionary = {}   # id -> {img: Image, tex: ImageTexture, dirty: bool}
static var _col := 0


static func new_map(world, x: float, z: float) -> ItemStack:
	var maps: Dictionary = world.level.get("maps", {}) if world.level.get("maps") is Dictionary else {}
	var id := int(world.level.get("next_map_id", 0))
	world.level["next_map_id"] = id + 1
	var size := 128
	var cx := int(floor((x + 64.0) / size)) * size + size / 2 - 64
	var cz := int(floor((z + 64.0) / size)) * size + size / 2 - 64
	maps[str(id)] = {"x": cx, "z": cz, "scale": 0, "dim": world.dimension}
	world.level["maps"] = maps
	var img := Image.create(128, 128, false, Image.FORMAT_RGB8)
	img.fill(Color8(0xE4, 0xD9, 0xBC))   # unexplored parchment
	cache[id] = {"img": img, "tex": ImageTexture.create_from_image(img), "dirty": false}
	var s := ItemStack.named("filled_map", 1)
	s.components["minecraft:map_id"] = id
	return s


static func map_id(s: ItemStack) -> int:
	if s == null or s.is_empty() or s.name() != "filled_map":
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


static func base_color(st: int) -> int:
	if st <= 0:
		return -1
	var b := Res.blocks
	var nm := b.name_of(st)
	if COLORS.has(nm):
		return COLORS[nm]
	if nm.ends_with("_leaves") or nm in ["short_grass", "tall_grass", "fern", "vine", "lily_pad", "kelp", "seagrass"] or nm.ends_with("_sapling"):
		return PLANT
	for k in ["oak", "spruce", "birch", "jungle", "acacia", "dark_oak", "mangrove", "cherry", "crimson", "warped", "deepslate", "terracotta", "prismarine", "sandstone"]:
		if nm.begins_with(k):
			return COLORS[k]
	if nm.ends_with("_ore"):
		return COLORS["stone"]
	var c := ItemIcons.average_color(st)
	return (int(c.r8) << 16) | (int(c.g8) << 8) | int(c.b8)


## While the map is held: scan two columns per tick (Java MapItem.update within the player's 128-pixel circle).
static func update(world, id: int) -> void:
	var maps: Dictionary = world.level.get("maps", {})
	var md: Dictionary = maps.get(str(id), {})
	if md.is_empty() or str(md.get("dim", "overworld")) != world.dimension:
		return
	var e := entry(world, id)
	var img: Image = e["img"]
	var cx := int(md["x"])
	var cz := int(md["z"])
	var p: Player = world.player
	var px := int(floor(p.pos.x)) - cx + 64
	var pz := int(floor(p.pos.z)) - cz + 64
	var b := Res.blocks
	var water_id := b.block_id("water")
	var changed := false
	for k in 2:
		_col = (_col + 1) % 128
		var x := _col
		if absi(x - px) > 64:
			continue
		var prev_h := -1
		for z in range(-1, 128):
			if (x - px) * (x - px) + (z - pz) * (z - pz) > 64 * 64:
				prev_h = -1
				continue
			var wx := cx - 64 + x
			var wz := cz - 64 + z
			var ch: Chunk = world.cm.get_chunk(wx >> 4, wz >> 4)
			if ch == null or ch.state < Chunk.DECORATED or ch.heightmap.is_empty():
				prev_h = -1
				continue
			var y: int = ch.heightmap[(wx & 15) + (wz & 15) * 16] - 1
			var st := ch.get_block(wx & 15, y, wz & 15)
			while y > Coords.MIN_Y and (st <= 0 or base_color(st) < 0):
				y -= 1
				st = ch.get_block(wx & 15, y, wz & 15)
			if z < 0:
				prev_h = y
				continue
			var depth := 0
			if st > 0 and b.st_block[st] == water_id:
				var yy := y - 1
				while yy > Coords.MIN_Y and depth < 10:
					var s2 := ch.get_block(wx & 15, yy, wz & 15)
					if s2 <= 0 or b.st_block[s2] != water_id:
						break
					depth += 1
					yy -= 1
			var base := base_color(st)
			var shade := 220
			if depth > 0 or (st > 0 and b.st_block[st] == water_id):
				var dd := depth * 0.1 + float((x + z) & 1) * 0.2
				shade = 255 if dd < 0.5 else (180 if dd > 0.9 else 220)
			elif prev_h >= 0:
				var dh := float(y - prev_h) * 4.0 / 4.0 + (float((x + z) & 1) - 0.5) * 0.4
				shade = 255 if dh > 0.6 else (180 if dh < -0.6 else 220)
			prev_h = y
			var col := Color8(((base >> 16) & 255) * shade / 255, ((base >> 8) & 255) * shade / 255, (base & 255) * shade / 255)
			if img.get_pixel(x, z) != col:
				img.set_pixel(x, z, col)
				changed = true
	if changed:
		(e["tex"] as ImageTexture).update(img)
		e["dirty"] = true
