## Explorer maps (the 26.3 exploration_map item modifier of the cartographer trades and of chest loot - buried treasure
## maps in shipwrecks / ocean ruins, abandoned camp maps; wiki Explorer Map, Buried Treasure Map, Item modifier):
## the nearest start of a structure in the destination tag within search_radius chunks (square, like /locate; trades
## use 100 = a 201 x 201 chunk area) around the villager, skipping starts earlier maps already pointed at
## (skip_existing_chunks, default true). The map is centred on the target on the 128 << zoom grid (zoom default 2: a
## 512 x 512 block area), shows the land / water outline before it is explored (water and swamps - 26.3
## #water_on_map_outlines - "an orange striated texture", land blank) and carries the target decoration (decoration,
## default mansion). "The map is not offered if no target could be found": the offer is removed.
## The search runs on a worker thread (the main thread never waits; Java's synchronous search is a known lag spike):
## the offer's map id is allocated at once and the offer stays out of stock (Trading.can_pay) until the search is done.
## Contract: begin(spec, villager) -> map id (or -1: discard); pending(id); ensure(world, id) after a reload.
class_name ExplorerMaps
extends RefCounted

static var world = null              # set by EntityManager._ready (null in headless tests: no explorer maps)
static var _running: Dictionary = {}  # map id -> Job


## Decoration type id -> map/decorations texture (26.3 asset names).
static func decoration_texture(deco: String) -> String:
	var d := deco.trim_prefix("minecraft:")
	match d:
		"monument":
			return "map/decorations/ocean_monument"
		"mansion":
			return "map/decorations/woodland_mansion"
	if d.begins_with("village_"):
		return "map/decorations/%s_village" % d.trim_prefix("village_")
	return "map/decorations/" + d


## Starts an explorer map for a trade made by villager `v` (spec = the modifier json). Returns the new map id.
static func begin(spec: Dictionary, v) -> int:
	if v == null:
		return -1
	return begin_at(spec, v.pos, null)


## Chest loot (the exploration_map function of shipwreck_map / underwater_ruin / abandoned camp tables: buried treasure
## and camp maps): the search starts at the container. Java searches at once and the table's "filtered" modifier
## discards a map that found nothing; here the search is async, so a map that found nothing is taken back afterwards
## from that container, the player's inventory or the ground (_drop_loot_map). loot_pos: the container (null: trades).
static func begin_at(spec: Dictionary, from: Vector3, loot_pos) -> int:
	if world == null or not is_instance_valid(world) or not (world.get("gen") is VanillaGenerator) or (world.gen as VanillaGenerator).structures == null:
		return -1
	var dest := str(spec.get("destination", "#minecraft:on_treasure_maps"))
	var names: Array = Tags.resolve("worldgen/structure", dest).keys() if dest.begins_with("#") else [dest.trim_prefix("minecraft:")]
	if names.is_empty():
		return -1
	var maps: Dictionary = world.level.get("maps", {}) if world.level.get("maps") is Dictionary else {}
	var id := int(world.level.get("next_map_id", 0))
	world.level["next_map_id"] = id + 1
	maps[str(id)] = {"x": 0, "z": 0, "scale": int(spec.get("zoom", 2)), "dim": world.dimension,
		"explore": {"names": names, "deco": str(spec.get("decoration", "minecraft:mansion")), "radius": int(spec.get("search_radius", 50)),
			"skip": bool(spec.get("skip_existing_chunks", true)), "from": [floori(from.x), floori(from.z)]}}
	if loot_pos is Vector3i:
		(maps[str(id)]["explore"] as Dictionary)["loot"] = [loot_pos.x, loot_pos.y, loot_pos.z]
	world.level["maps"] = maps
	_start(id)
	return id


## True while the map's target is still being searched (its trade cannot be bought yet).
static func pending(id: int) -> bool:
	if world == null or not is_instance_valid(world):
		return false
	var md = (world.level.get("maps", {}) as Dictionary).get(str(id))
	return md is Dictionary and (md as Dictionary).has("explore")


## A map whose search did not finish before the world was saved: search again.
static func ensure(id: int) -> void:
	if pending(id) and not _running.has(id):
		_start(id)


static func _start(id: int) -> void:
	var md: Dictionary = (world.level["maps"] as Dictionary)[str(id)]
	var ex: Dictionary = md["explore"]
	var job := Job.new()
	job.id = id
	job.sts = (world.gen as VanillaGenerator).structures
	job.names = ex["names"]
	job.radius = int(ex["radius"])
	job.scale = int(md.get("scale", 2))
	job.from = Vector2i(int(ex["from"][0]), int(ex["from"][1]))
	if bool(ex.get("skip", true)):
		var known = world.level.get("explored_starts", {})
		job.skip = (known as Dictionary).duplicate() if known is Dictionary else {}
	var gen: VanillaGenerator = world.gen
	for bn in gen.biome_ids:
		if Tags.resolve("worldgen/biome", "#minecraft:water_on_map_outlines").has(str(bn).trim_prefix("minecraft:")):
			job.water[int(gen.biome_ids[bn])] = true
	_running[id] = job
	WorkerThreadPool.add_task(job.run)


class Job:
	extends RefCounted
	var id := 0
	var sts
	var names: Array = []
	var radius := 50
	var scale := 2
	var from := Vector2i.ZERO
	var skip: Dictionary = {}       # "name x z" -> true: starts earlier maps pointed at
	var water: Dictionary = {}      # biome id -> true (#water_on_map_outlines)
	var found := false
	var target := Vector2i.ZERO     # block x / z of the structure start (chunk centre)
	var start_key := ""
	var preview := PackedByteArray()
	const NB := [-131, -130, -129, -1, 1, 129, 130, 131]   # 8 neighbours in the 130-wide sample grid

	func run() -> void:
		var best := 1 << 60
		var cx := from.x >> 4
		var cz := from.y >> 4
		for nm in names:
			var res: Dictionary = sts.locate(str(nm), cx, cz, radius, skip)
			if res.is_empty():
				continue
			var ch: Vector2i = res["chunk"]
			var d := (ch - Vector2i(cx, cz)).length_squared()
			if d < best:
				best = d
				found = true
				target = Vector2i(ch.x * 16 + 8, ch.y * 16 + 8)
				start_key = "%s %d %d" % [str(nm), ch.x, ch.y]
		if found:
			_preview()
		call_deferred("finish")

	func finish() -> void:
		ExplorerMaps._done(self)

	## Land / water outline of the map area (wiki: water and swamps "an orange striated texture", land blank): water
	## biome pixels on every other row in orange (MapColor ORANGE 0xD87F33) in brightness bands that drift with the row,
	## land next to water in brown (0x664C33) as the coast line. (The wiki shows no exact pattern: visual match.)
	func _preview() -> void:
		var size := 128 << scale
		var mcx := floori((target.x + 64.0) / size) * size + size / 2 - 64
		var mcz := floori((target.y + 64.0) / size) * size + size / 2 - 64
		var step := 1 << scale
		var wet := PackedByteArray()
		wet.resize(130 * 130)
		for pz in 130:
			for px in 130:
				var b: int = sts.biome_id_at(mcx + (px - 65) * step, 64, mcz + (pz - 65) * step)
				wet[pz * 130 + px] = 1 if water.has(b) else 0
		preview.resize(128 * 128 * 3)
		for pz in 128:
			for px in 128:
				var i := (pz + 1) * 130 + px + 1
				var n := 0
				for k in NB:
					n += wet[i + k]
				var col := 0xE4D9BC   # parchment
				var shade := 255
				if wet[i] == 1:
					if pz % 2 == 0:
						col = 0xD87F33
						var band := posmod(px + int(sin(float(pz)) * 7.0), 40) / 8
						shade = 255 if band == 2 else (220 if band == 1 or band == 3 else 180)
				elif n > 0:
					col = 0x664C33
					shade = 220 if n > 3 else 135
				var o := (pz * 128 + px) * 3
				if col == 0xE4D9BC:
					preview[o] = 0xE4
					preview[o + 1] = 0xD9
					preview[o + 2] = 0xBC
				else:
					preview[o] = ((col >> 16) & 255) * shade / 255
					preview[o + 1] = ((col >> 8) & 255) * shade / 255
					preview[o + 2] = (col & 255) * shade / 255


## Main thread: the search finished.
static func _done(job: Job) -> void:
	_running.erase(job.id)
	if world == null or not is_instance_valid(world) or not (world.level.get("maps") is Dictionary):
		return   # (the world was closed meanwhile)
	var maps: Dictionary = world.level["maps"]
	var md = maps.get(str(job.id))
	if not (md is Dictionary) or not (md as Dictionary).has("explore"):
		return
	var ex: Dictionary = md["explore"]
	md.erase("explore")
	print_verbose("[explorer] map %d %s: %s" % [job.id, str(job.names), ("start " + job.start_key) if job.found else "nothing found - offer dropped"])
	if not job.found:
		maps.erase(str(job.id))
		if ex.get("loot") is Array:
			_drop_loot_map(job.id, ex["loot"])
		else:
			_drop_offer(job.id)
		return
	var size := 128 << job.scale
	md["x"] = floori((job.target.x + 64.0) / size) * size + size / 2 - 64
	md["z"] = floori((job.target.y + 64.0) / size) * size + size / 2 - 64
	md["targets"] = [{"t": str(ex.get("deco", "minecraft:mansion")), "x": job.target.x, "z": job.target.y}]
	md["rev"] = int(md.get("rev", 0)) + 1
	if bool(ex.get("skip", true)):
		if not (world.level.get("explored_starts") is Dictionary):
			world.level["explored_starts"] = {}
		world.level["explored_starts"][job.start_key] = true
	var e := Maps.entry(world, job.id)
	if job.preview.size() == 128 * 128 * 3:
		var img := Image.create_from_data(128, 128, false, Image.FORMAT_RGB8, job.preview)
		e["img"] = img
		(e["tex"] as ImageTexture).set_image(img)
		e["dirty"] = true


## No target for a chest-loot map: the map is discarded (the loot table's filtered / discard modifier) - removed from
## its container, the local player's inventory / cursor, or the ground.
static func _drop_loot_map(id: int, at: Array) -> void:
	var pos := Vector3i(int(at[0]), int(at[1]), int(at[2]))
	var d: Dictionary = BlockEntities.get_data(world, pos)
	if d.get("items") is Array:
		var items: Array = d["items"]
		for i in items.size():
			if items[i] is Dictionary and Maps.map_id(ItemStack.from_dict(items[i])) == id:
				items[i] = {}
				BlockEntities.set_data(world, pos, d)
				return
	var p = world.get("player")
	if p != null:
		for i in Inventory.SIZE:
			var s: ItemStack = p.inventory.get_slot(i)
			if not s.is_empty() and Maps.map_id(s) == id:
				s.clear()
				world.inv_changed()
				return
		if not p.inventory.cursor.is_empty() and Maps.map_id(p.inventory.cursor) == id:
			p.inventory.cursor.clear()
			return
	var em = world.get("entities")
	if em != null:
		for e in em.ents:
			if e.kind == "item" and not e.dead and e.stack != null and Maps.map_id(e.stack) == id:
				em._remove(e)
				return


## No target: the trade holding this map is not offered.
static func _drop_offer(id: int) -> void:
	var em = world.get("entities")
	if em == null:
		return
	for v in em.ents:
		if v.kind != "mob" or not v.def.get("trader", false):
			continue
		var offers: Array = v.data.get("offers", [])
		for i in range(offers.size() - 1, -1, -1):
			var c = offers[i].get("comp")
			if c is Dictionary and int((c as Dictionary).get("minecraft:map_id", -1)) == id:
				offers.remove_at(i)
				return
