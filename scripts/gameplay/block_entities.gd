## BlockEntities — typed per-block data stored in Chunk.block_entities (key = packed local pos):
## containers (chest/barrel/shulker 27, hopper 5, dispenser/dropper 9, furnace family 3 + burn/cook
## progress), jukebox disc, note block sounds. Furnaces tick while their chunk is loaded.
## Contract: get_data/set_data(world, pos, dict); on_placed/on_removed; container_size(kind); tick_furnaces(world).
class_name BlockEntities

const INSTRUMENTS := {"harp": "harp", "basedrum": "basedrum", "snare": "snare", "hat": "hat", "bass": "bass", "flute": "flute",
	"bell": "bell", "guitar": "guitar", "chime": "chime", "xylophone": "xylophone", "iron_xylophone": "iron_xylophone",
	"cow_bell": "cow_bell", "didgeridoo": "didgeridoo", "bit": "bit", "banjo": "banjo", "pling": "pling", "trumpet": "trumpet",
	"trumpet_exposed": "trumpet_exposed", "trumpet_weathered": "trumpet_weathered", "trumpet_oxidized": "trumpet_oxidized"}


static func _key(p: Vector3i) -> int:
	return ((p.y - Coords.MIN_Y) << 8) | ((p.z & 15) << 4) | (p.x & 15)


## World position of block entity key k in chunk c (inverse of _key).
static func pos_of(c: Chunk, k: int) -> Vector3i:
	return Vector3i(c.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, c.cz * 16 + ((k >> 4) & 15))


static func get_data(world, p: Vector3i) -> Dictionary:
	if world.cm == null:
		return {}
	var c: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if c == null:
		return {}
	return c.block_entities.get(_key(p), {})


static func set_data(world, p: Vector3i, d: Dictionary) -> void:
	if world.cm == null:
		return
	var c: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if c == null:
		return
	c.block_entities[_key(p)] = d
	be_dirty = true
	epoch += 1
	edit_epoch += 1
	c.modified = true
	_index_add(world.cm, c, str(d.get("id", "")))
	if not Net.is_client():
		Redstone.request(world, p)   # comparators reading this block (container contents, lectern page, disc, ...)


## Removes and returns the block entity data at p without dropping anything (pistons carry it to the new position).
static func take(world, p: Vector3i) -> Dictionary:
	if world.cm == null:
		return {}
	var c: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if c == null or not c.block_entities.has(_key(p)):
		return {}
	var d: Dictionary = c.block_entities[_key(p)]
	c.block_entities.erase(_key(p))
	c.modified = true
	epoch += 1
	edit_epoch += 1
	return d


static func container_size(kind: String) -> int:
	if kind in ["furnace", "blast_furnace", "smoker"]:
		return 3
	if kind == "hopper" or kind == "brewing_stand":
		return 5
	if kind in ["dispenser", "dropper", "crafter"]:
		return 9
	return 27


static func on_placed(world, p: Vector3i, st: int) -> void:
	var n := Res.blocks.name_of(st)
	if n == "beacon":
		set_data(world, p, {"id": "beacon", "levels": 0, "primary": "", "secondary": ""})
		return
	if CommandBlocks.is_command_block(n):
		CommandBlocks.data(world, p)
		return
	if Signs.is_sign(n):
		Signs.data(world, p)
		Signs.mark_dirty()
		return
	if Shelf.is_shelf(n):
		set_data(world, p, {"id": n, "items": [{}, {}, {}]})
		return
	if n == "daylight_detector" or n == "conduit":
		set_data(world, p, {"id": n})   # (DaylightDetectorBlockEntity / ConduitBlockEntity: Sensors / Conduits tick them)
		return
	if n.ends_with("lightning_rod"):
		set_data(world, p, {"id": "lightning_rod"})   # (index entry, Java's lightning rod POI: Sensors.find_rod)
		return
	if Villagers.is_poi_block(n):
		Villagers.poi_placed(p, st)   # (job site / bell / bed: villager POI index; barrels / brewing stands / lecterns go on below)
	if n == "campfire" or n == "soul_campfire":
		set_data(world, p, {"id": n, "items": [{}, {}, {}, {}], "cook": [0, 0, 0, 0], "total": [0, 0, 0, 0]})
		return
	if n in ["chest", "trapped_chest", "barrel", "hopper", "dispenser", "dropper", "crafter", "furnace", "blast_furnace", "smoker", "brewing_stand"] or n.ends_with("shulker_box") or n.ends_with("copper_chest"):
		var items: Array = []
		items.resize(container_size(n))
		items.fill({})
		set_data(world, p, {"id": n, "items": items, "burn": 0, "burn_max": 0, "cook": 0})


## Item data component read from block entity data (Java BlockEntity.collectComponents) for copy_components.
static func component_of(d: Dictionary, comp: String) -> Variant:
	match comp.trim_prefix("minecraft:"):
		"container":
			var items: Array = d.get("items", [])
			for it in items:
				if not ItemStack.from_dict(it).is_empty():
					return items.duplicate(true)
			return null
		"container_loot":
			return {"loot_table": d["loot_table"]} if d.has("loot_table") else null
		"banner_patterns":
			var pt: Array = d.get("patterns", [])
			return pt.duplicate(true) if not pt.is_empty() else null
		"custom_name":
			return d.get("CustomName", null)
		"pot_decorations":
			return d.get("sherds", null)
	return null


## Block entity data from the placed item's components (Java BlockEntity.applyComponentsFromItemStack).
static func apply_item(world, p: Vector3i, s: ItemStack) -> void:
	if s == null or s.is_empty() or s.components.is_empty():
		return
	var d := get_data(world, p)
	var changed := false
	var c := s.components
	if c.get("minecraft:container") is Array and d.has("items"):
		var items: Array = (c["minecraft:container"] as Array).duplicate(true)
		items.resize(container_size(str(d.get("id", "chest"))))
		for i in items.size():
			if items[i] == null:
				items[i] = {}
		d["items"] = items
		changed = true
	if c.get("minecraft:container_loot") is Dictionary:
		d["loot_table"] = c["minecraft:container_loot"].get("loot_table", "")
		changed = true
	if c.get("minecraft:banner_patterns") is Array:
		d["id"] = d.get("id", "banner")
		d["patterns"] = (c["minecraft:banner_patterns"] as Array).duplicate(true)
		changed = true
	if c.has("minecraft:custom_name"):
		d["CustomName"] = c["minecraft:custom_name"]
		changed = true
	if c.get("minecraft:pot_decorations") is Array:
		# Java DecoratedPotBlockEntity: the item's pot_decorations (back, left, right, front) become its sherds
		d["id"] = "decorated_pot"
		d["sherds"] = (c["minecraft:pot_decorations"] as Array).duplicate()
		changed = true
	if changed:
		set_data(world, p, d)
		BERender.refresh(p)


## Java RandomizableContainer.unpackLootTable: structure chests carry a loot table until first opened/broken;
## generated stacks go to random empty slots.
static func ensure_loot(world, p: Vector3i) -> Dictionary:
	var d := get_data(world, p)
	if d.is_empty() or not d.has("loot_table"):
		return d
	var n := container_size(str(d.get("id", "chest")))
	var items: Array = d.get("items", [])
	items.resize(n)
	for i in n:
		if items[i] == null:
			items[i] = {}
	# origin / container: explorer maps in the loot search from the chest (Loot exploration_map, ExplorerMaps.begin_at)
	var ctx := {"tool": null, "rng": world.rng, "by_player": true, "origin": Vector3(p) + Vector3(0.5, 0.5, 0.5), "container": p}
	var empty: Array = []
	for i in n:
		if ItemStack.from_dict(items[i]).is_empty():
			empty.append(i)
	for s in Loot.roll(str(d["loot_table"]), ctx):
		if empty.is_empty():
			break
		var k: int = empty.pop_at(world.rng.randi_range(0, empty.size() - 1))
		items[k] = (s as ItemStack).to_dict()
	d["items"] = items
	d.erase("loot_table")
	set_data(world, p, d)
	return d


static func on_removed(world, p: Vector3i, st: int) -> void:
	var d := ensure_loot(world, p)
	if d.is_empty():
		return
	var n := Res.blocks.name_of(st)
	if not n.ends_with("shulker_box"):
		for it in d.get("items", []):
			var s := ItemStack.from_dict(it)
			if not s.is_empty():
				world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), s)
	if d.has("disc"):
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.0, 0.5), ItemStack.from_dict(d["disc"]))
		jukebox_stop(p)   # (breaking a playing jukebox stops its record)
	if d.has("book"):
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.0, 0.5), ItemStack.from_dict(d["book"]))
	var c: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if c != null:
		c.block_entities.erase(_key(p))
		epoch += 1
		edit_epoch += 1


## wiki Note Block: a mob head on top plays that mob (pitch ignored; player heads are silent without a custom sound),
## otherwise the block below picks the instrument (harp for anything not listed, including air).
const HEAD_INSTRUMENTS := {"skeleton_skull": "skeleton", "wither_skeleton_skull": "wither_skeleton", "zombie_head": "zombie",
	"creeper_head": "creeper", "piglin_head": "piglin", "dragon_head": "dragon", "player_head": "custom_head"}
const HEAD_SOUNDS := {"skeleton": "block.note_block.imitate.skeleton", "wither_skeleton": "block.note_block.imitate.wither_skeleton",
	"zombie": "block.note_block.imitate.zombie", "creeper": "block.note_block.imitate.creeper", "piglin": "block.note_block.imitate.piglin",
	"dragon": "block.note_block.imitate.ender_dragon"}
const NOTE_SINGLE := {"gold_block": "bell", "clay": "flute", "packed_ice": "chime", "bone_block": "xylophone",
	"iron_block": "iron_xylophone", "soul_sand": "cow_bell", "pumpkin": "didgeridoo", "emerald_block": "bit", "hay_block": "banjo",
	"glowstone": "pling", "sand": "snare", "red_sand": "snare", "suspicious_sand": "snare", "gravel": "snare",
	"suspicious_gravel": "snare", "heavy_core": "snare", "glass": "hat", "glass_pane": "hat", "tinted_glass": "hat",
	"sea_lantern": "hat", "beacon": "hat", "conduit": "hat"}
const NOTE_BASS := ["mangrove_roots", "brown_mushroom_block", "red_mushroom_block", "mushroom_stem", "bee_nest", "bamboo_block",
	"stripped_bamboo_block", "bamboo_mosaic", "bamboo_mosaic_stairs", "bamboo_mosaic_slab", "chest", "trapped_chest", "barrel",
	"crafting_table", "cartography_table", "fletching_table", "smithing_table", "loom", "campfire", "soul_campfire", "composter",
	"note_block", "jukebox", "bookshelf", "chiseled_bookshelf", "lectern", "beehive"]
const NOTE_BASS_TAGS := ["logs", "planks", "wooden_stairs", "wooden_slabs", "wooden_doors", "wooden_trapdoors", "wooden_pressure_plates",
	"wooden_fences", "fence_gates", "all_signs", "banners", "wooden_shelves", "bamboo_blocks"]
const NOTE_BASEDRUM := ["stone", "cobblestone", "mossy_cobblestone", "smooth_stone", "granite", "polished_granite", "diorite",
	"polished_diorite", "andesite", "polished_andesite", "deepslate", "cobbled_deepslate", "chiseled_deepslate", "polished_deepslate",
	"reinforced_deepslate", "tuff", "chiseled_tuff", "polished_tuff", "sandstone", "chiseled_sandstone", "smooth_sandstone",
	"cut_sandstone", "red_sandstone", "chiseled_red_sandstone", "smooth_red_sandstone", "cut_red_sandstone", "prismarine", "netherrack",
	"basalt", "smooth_basalt", "polished_basalt", "blackstone", "gilded_blackstone", "polished_blackstone", "chiseled_polished_blackstone",
	"end_stone", "stone_bricks", "cracked_stone_bricks", "chiseled_stone_bricks", "mossy_stone_bricks", "deepslate_bricks",
	"cracked_deepslate_bricks", "deepslate_tiles", "cracked_deepslate_tiles", "tuff_bricks", "chiseled_tuff_bricks", "bricks", "mud_bricks",
	"resin_block", "resin_bricks", "chiseled_resin_bricks", "prismarine_bricks", "dark_prismarine", "nether_bricks", "cracked_nether_bricks",
	"chiseled_nether_bricks", "red_nether_bricks", "polished_blackstone_bricks", "cracked_polished_blackstone_bricks", "end_stone_bricks",
	"purpur_block", "purpur_pillar", "sulfur", "polished_sulfur", "sulfur_bricks", "chiseled_sulfur", "potent_sulfur", "sulfur_spike",
	"cinnabar", "polished_cinnabar", "cinnabar_bricks", "chiseled_cinnabar", "quartz_block", "chiseled_quartz_block", "quartz_pillar",
	"smooth_quartz", "quartz_bricks", "crimson_nylium", "warped_nylium", "dripstone_block", "pointed_dripstone", "magma_block", "obsidian",
	"crying_obsidian", "bedrock", "creaking_heart", "coal_ore", "copper_ore", "diamond_ore", "emerald_ore", "gold_ore", "iron_ore",
	"lapis_ore", "nether_quartz_ore", "redstone_ore", "deepslate_coal_ore", "deepslate_copper_ore", "deepslate_diamond_ore",
	"deepslate_emerald_ore", "deepslate_gold_ore", "deepslate_iron_ore", "deepslate_lapis_ore", "deepslate_redstone_ore",
	"raw_copper_block", "raw_gold_block", "raw_iron_block", "coal_block", "furnace", "smoker", "blast_furnace", "dispenser", "dropper",
	"observer", "respawn_anchor", "ender_chest", "stonecutter", "enchanting_table", "vault", "end_portal_frame", "spawner", "trial_spawner",
	"petrified_oak_slab", "stone_pressure_plate", "polished_blackstone_pressure_plate"]
static var _inst_cache: Dictionary = {}


## Instrument a block plays when it is directly below a note block (wiki Note Block table, Java).
static func note_instrument(name: String) -> String:
	if _inst_cache.has(name):
		return _inst_cache[name]
	var r := "harp"
	if NOTE_SINGLE.has(name):
		r = NOTE_SINGLE[name]
	elif Tags.has_block("wool", name) or name.ends_with("_wool_slab") or name.ends_with("_wool_stairs"):
		r = "guitar"
	elif name.ends_with("_concrete_powder"):
		r = "snare"
	elif name.ends_with("_stained_glass") or name.ends_with("_stained_glass_pane"):
		r = "hat"
	elif NOTE_BASS.has(name) or name.ends_with("_shelf"):
		r = "bass"
	elif _note_basedrum(name):
		r = "basedrum"
	else:
		var cp := Copper.parse(name)
		if not cp.is_empty() and str(cp[0]) in ["copper_block", "chiseled_copper", "cut_copper", "cut_copper_slab", "cut_copper_stairs"]:
			r = ["trumpet", "trumpet_exposed", "trumpet_weathered", "trumpet_oxidized"][int(cp[1])]
		else:
			for t in NOTE_BASS_TAGS:
				if Tags.has_block(t, name):
					r = "bass"
					break
	_inst_cache[name] = r
	return r


static func _note_basedrum(name: String) -> bool:
	if NOTE_BASEDRUM.has(name) or name.ends_with("_concrete") or name == "terracotta" or name.ends_with("_terracotta"):
		return true
	if name.ends_with("_coral_block") or (name.begins_with("dead_") and (name.ends_with("_coral_fan") or name.ends_with("_coral_wall_fan"))):
		return true
	# slabs / stairs / walls copy their base block's instrument (Java Properties.ofLegacyCopy)
	for suf in ["_slab", "_stairs", "_wall"]:
		if name.ends_with(suf):
			var base := name.trim_suffix(suf)
			for cand in [base, base + "s", base + "_block"]:
				if NOTE_BASEDRUM.has(cand):
					return true
	return false


## Java NoteBlock.setInstrument: a head above wins, else the block below (a head below counts as harp).
static func note_instrument_at(world, p: Vector3i) -> String:
	var b := Res.blocks
	var up: int = world.state_at(p.x, p.y + 1, p.z)
	if up > 0 and HEAD_INSTRUMENTS.has(b.name_of(up)):
		return HEAD_INSTRUMENTS[b.name_of(up)]
	var dn: int = world.state_at(p.x, p.y - 1, p.z)
	return note_instrument(b.name_of(dn)) if dn > 0 else "harp"


## Java NoteBlock.triggerEvent: plays only with air above unless a mob head sits there; tunable instruments use
## 2^((note - 12) / 12) and show the note particle, heads play their mob sound at pitch 1; RECORDS volume 3.
static func play_note(world, p: Vector3i) -> void:
	var b := Res.blocks
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return
	var inst := note_instrument_at(world, p)
	if b.has_prop(st, "instrument") and b.get_prop(st, "instrument") != inst:
		st = b.with_prop(st, "instrument", inst)
		world.set_block(p.x, p.y, p.z, st, false)
	var head := HEAD_INSTRUMENTS.values().has(inst)
	if not head and world.state_at(p.x, p.y + 1, p.z) != 0:
		return
	if inst == "custom_head":
		return   # (player heads: silent without a note_block_sound)
	var note := int(b.get_prop(st, "note"))
	if head:
		Audio.play(str(HEAD_SOUNDS[inst]), Vector3(p) + Vector3(0.5, 0.5, 0.5), "Jukebox", 3.0, 1.0)
		Allay.hear_noteblock(world.entities, p)
		return
	var pitch := pow(2.0, (note - 12) / 12.0)
	Audio.play("block.note_block." + INSTRUMENTS.get(inst, inst), Vector3(p) + Vector3(0.5, 0.5, 0.5), "Jukebox", 3.0, pitch)
	Allay.hear_noteblock(world.entities, p)   # (GameEvent.NOTE_BLOCK_PLAY: allays within 16 blocks)
	# Java NoteParticle: hue from the note (0-24)
	var hue := float(note) / 24.0
	Particles.emit("note", Vector3(p) + Vector3(0.5, 1.2, 0.5), Vector3.ZERO, Color(maxf(0.0, sin((hue + 0.0) * TAU) * 0.65 + 0.35), maxf(0.0, sin((hue + 1.0 / 3.0) * TAU) * 0.65 + 0.35), maxf(0.0, sin((hue + 2.0 / 3.0) * TAU) * 0.65 + 0.35)))


static func use_jukebox(world, p: Vector3i, pl: Player) -> bool:
	var d := get_data(world, p)
	if d.has("disc"):
		# eject: the disc pops out and the record stops (the disc stayed inside before: every click copied it)
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.0, 0.5), ItemStack.from_dict(d["disc"]))
		d.erase("disc")
		set_data(world, p, d)
		_set_has_record(world, p, false)
		jukebox_stop(p)
		return true
	var h := pl.inventory.held()
	if h.is_empty() or not h.name().begins_with("music_disc"):
		return false
	d["disc"] = h.split(1).to_dict()
	if not d.has("id"):
		d["id"] = "jukebox"
	set_data(world, p, d)
	_set_has_record(world, p, true)
	pl.inventory.changed.emit()
	var song := h.name().trim_prefix("music_disc_") if not h.is_empty() else str(d["disc"]["id"]).trim_prefix("minecraft:music_disc_")
	Audio.play("music_disc." + song, Vector3(p) + Vector3(0.5, 0.5, 0.5), "Jukebox", 4.0)
	# JukeboxSongPlayer: plays for the song's length_in_seconds (jukebox_song data); allays dance meanwhile
	var sj = Res.read_json("data/minecraft/jukebox_song/%s.json" % song)
	var secs: float = float(sj.get("length_in_seconds", 180.0)) if sj is Dictionary else 180.0
	playing[p] = [int(world.game_time), int(secs * 20.0)]
	return true


## Java JukeboxBlock has_record state (comparators and observers see the disc go in / out).
static func _set_has_record(world, p: Vector3i, on: bool) -> void:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st > 0 and Res.blocks.has_prop(st, "has_record"):
		world.set_block(p.x, p.y, p.z, Res.blocks.with_prop(st, "has_record", "true" if on else "false"))


static var _items_touched := false   # furnace_step moved an item (fuel used / item smelted): comparators update


## Furnace family logic for one container dictionary; returns true when changed.
static func furnace_step(d: Dictionary) -> bool:
	var items: Array = d.get("items", [])
	if items.size() < 3:
		return false
	var kind := str(d.get("id", "furnace"))
	var input := ItemStack.from_dict(items[0])
	var fuel := ItemStack.from_dict(items[1])
	var out := ItemStack.from_dict(items[2])
	var speed := 2 if kind != "furnace" else 1
	var rk := "smelting" if kind == "furnace" else ("blasting" if kind == "blast_furnace" else "smoking")
	var result := Crafting.smelt_result(input.item, rk) if not input.is_empty() else null
	var can := result != null and (out.is_empty() or (out.can_merge(result) and out.count + result.count <= out.max_stack()))
	var changed := false
	if int(d.get("burn", 0)) > 0:
		d["burn"] = int(d["burn"]) - 1
		changed = true
	if int(d.get("burn", 0)) <= 0 and can and not fuel.is_empty():
		var ft := Crafting.fuel_time(fuel.item) / speed
		if ft > 0:
			d["burn"] = ft
			d["burn_max"] = ft
			var rem := "bucket" if fuel.name() == "lava_bucket" else ""
			fuel.count -= 1
			if fuel.count <= 0:
				fuel = ItemStack.named(rem) if rem != "" else ItemStack.new()
			changed = true
			_items_touched = true
	if int(d.get("burn", 0)) > 0 and can:
		# wiki Smoker / Blast Furnace: twice as fast as a furnace (26.3 smoking / blasting recipes list 200 ticks like
		# smelting, so the block advances 2 per tick: 5 s per item)
		d["cook"] = int(d.get("cook", 0)) + speed
		var info := Crafting.smelt_info(input.item, rk)
		var total := int(info[3]) if info.size() > 3 else 200
		if int(d["cook"]) >= total:
			d["cook"] = 0
			# wiki Sponge: a bucket in the fuel slot when a wet sponge finishes drying fills with its water (Java
			# AbstractFurnaceBlockEntity.burn replaces the fuel stack with one water bucket)
			if input.name() == "wet_sponge" and fuel.name() == "bucket":
				fuel = ItemStack.named("water_bucket", 1)
			input.count -= 1
			if input.count <= 0:
				input.clear()
			if out.is_empty():
				out = result
			else:
				out.count += result.count
			d["xp"] = float(d.get("xp", 0.0)) + (float(info[2]) if info.size() > 2 else 0.1)
			_items_touched = true
		changed = true
	elif int(d.get("cook", 0)) > 0:
		d["cook"] = maxi(0, int(d["cook"]) - 2)
		changed = true
	items[0] = input.to_dict()
	items[1] = fuel.to_dict()
	items[2] = out.to_dict()
	return changed


static var be_dirty := true

## Index of loaded chunks by block-entity id, so the systems that tick block entities (furnaces, spawners, signs,
## command blocks, beacons) visit only the chunks holding their kinds instead of every block entity of every loaded
## chunk each tick. Incremental: ChunkManager indexes a chunk when it becomes decorated (generated or loaded),
## set_data indexes the chunk for the new id; unloaded chunks and kinds no longer present are dropped when visited.
static var _idx: Dictionary = {}      # id -> Dictionary(Chunk -> true)
static var epoch := 0                 # bumped whenever a block entity is set / removed or a chunk's are indexed (caches)
static var edit_epoch := 0            # bumped only by set_data / removal (live edits)
static var _idx_cm_id := 0


static func index_chunk(cm, c: Chunk) -> void:
	# palette check of the loaded sections (cached per section): rods without an entry, villager job sites / bells
	var m := 0
	for sec in c.sections:
		m |= Interest.section_mask(sec)
	if m & Interest.ROD:
		_index_rods(c)
	Villagers.index_chunk(c, (m & Interest.POI) != 0)
	if c.block_entities.is_empty():
		return
	# lightning rod entries whose block is no rod (a build of 2026-11-15 flagged water / lava / cave air as rods and
	# could save hundreds per chunk): dropped on load
	var bad: Array = []
	for k0 in c.block_entities:
		var d0 = c.block_entities[k0]
		if d0 is Dictionary and str((d0 as Dictionary).get("id", "")) == "lightning_rod":
			var s0 := c.sections[k0 >> 12] as Chunk.Section
			var st0: int = s0.get_at(k0 & 4095)
			if st0 <= 0 or (Interest.table()[st0] & Interest.ROD) == 0:
				bad.append(k0)
	for k1 in bad:
		c.block_entities.erase(k1)
	if c.block_entities.is_empty():
		return
	_index_owner(cm)
	for k in c.block_entities:
		var d = c.block_entities[k]
		if d is Dictionary:
			_index_put(c, str((d as Dictionary).get("id", "")))


## Lightning rods without their {"id": "lightning_rod"} entry (placed before rods got one, or written by a structure)
## get it when their chunk loads - like Java's POI check of a loaded section, only sections whose palette holds a rod
## state are scanned (Interest.ROD, cached per section palette). The entries are re-derived on every load, so the
## chunk is not marked modified.
static func _index_rods(c: Chunk) -> void:
	var t: PackedByteArray
	for si in c.sections.size():
		var sec: Chunk.Section = c.sections[si]
		if (Interest.section_mask(sec) & Interest.ROD) == 0:
			continue
		if t.is_empty():
			t = Interest.table()
		for i in section_find(sec, t, Interest.ROD):
			var k := (si << 12) | i
			if not c.block_entities.has(k):
				c.block_entities[k] = {"id": "lightning_rod"}


## Section indices (((y & 15) << 8) | (z << 4) | x) of the blocks whose Interest bits include `bit`: the palette
## entries with the bit are looked up with the packed arrays' native find, not a 4096-step GDScript loop.
static func section_find(sec: Chunk.Section, t: PackedByteArray, bit: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if sec.pal.size() == 1:
		var s0: int = sec.pal[0]
		if s0 > 0 and s0 < t.size() and (t[s0] & bit) != 0:
			out.resize(4096)
			for i in 4096:
				out[i] = i
		return out
	var wide := sec.wide.size() > 0
	for pi in sec.pal.size():
		var st: int = sec.pal[pi]
		if st <= 0 or st >= t.size() or (t[st] & bit) == 0:
			continue
		var i := sec.wide.find(pi) if wide else sec.idx.find(pi)
		while i >= 0:
			out.append(i)
			i = sec.wide.find(pi, i + 1) if wide else sec.idx.find(pi, i + 1)
	return out


static func _index_add(cm, c: Chunk, id: String) -> void:
	_index_owner(cm)
	_index_put(c, id)


static func _index_put(c: Chunk, id: String) -> void:
	epoch += 1
	var s = _idx.get(id)
	if s == null:
		s = {}
		_idx[id] = s
	(s as Dictionary)[c] = true


## A different ChunkManager (dimension change, new world): rebuild the index from its loaded chunks.
static func _index_owner(cm) -> void:
	if cm == null or cm.get_instance_id() == _idx_cm_id:
		return
	_idx_cm_id = cm.get_instance_id()
	_idx.clear()
	for c in cm.chunks.values():
		var ch: Chunk = c
		if ch.state >= Chunk.DECORATED:
			for k in ch.block_entities:
				var d = ch.block_entities[k]
				if d is Dictionary:
					_index_put(ch, str((d as Dictionary).get("id", "")))


## Loaded, decorated chunks that hold at least one block entity of the given ids (each chunk once).
static func chunks_with(world, ids: Array) -> Array:
	var cm = world.cm
	if cm == null:
		return []
	_index_owner(cm)
	var out: Array = []
	var seen: Dictionary = {}
	for id in ids:
		var s = _idx.get(id)
		if s == null:
			continue
		var drop: Array = []
		for c in s:
			var ch: Chunk = c
			if ch.state == Chunk.EVICTED or cm.chunks.get(Coords.chunk_key(ch.cx, ch.cz)) != ch or not _holds(ch, id):
				drop.append(ch)
				continue
			if not seen.has(ch):
				seen[ch] = true
				out.append(ch)
		for ch in drop:
			(s as Dictionary).erase(ch)
	return out


static func _holds(c: Chunk, id: String) -> bool:
	for k in c.block_entities:
		var d = c.block_entities[k]
		if d is Dictionary and str((d as Dictionary).get("id", "")) == id:
			return true
	return false


const TICKED_KINDS := ["furnace", "blast_furnace", "smoker", "brewing_stand", "hopper", "campfire", "soul_campfire"]
static var _campfire_st := PackedByteArray()


## Every campfire has a block entity (Java CampfireBlockEntity: cooking and the smoke): created for campfires set by
## commands / structures / anything else that is not the player placement path.
static func ensure_campfire(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	if _campfire_st.size() != b.total_states:
		_campfire_st.resize(b.total_states)
		for s0 in range(1, b.total_states):
			_campfire_st[s0] = 1 if b.names[b.st_block[s0]].ends_with("campfire") else 0
	if st <= 0 or st >= _campfire_st.size() or _campfire_st[st] == 0:
		return
	if get_data(world, p).is_empty():
		set_data(world, p, {"id": b.name_of(st)})


static func tick_furnaces(world) -> void:
	var b := Res.blocks
	tick_jukeboxes(world)
	Conduits.tick(world)
	for c in chunks_with(world, TICKED_KINDS):
		var ch: Chunk = c
		if ch.state == Chunk.EVICTED or ch.block_entities.is_empty():
			continue
		for k in ch.block_entities:
			var d: Dictionary = ch.block_entities[k]
			var id := str(d.get("id", ""))
			if id in ["furnace", "blast_furnace", "smoker"]:
				var was := int(d.get("burn", 0)) > 0
				_items_touched = false
				if furnace_step(d):
					ch.modified = true
					var lit := int(d.get("burn", 0)) > 0
					var p := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
					if lit != was:
						var st: int = world.state_at(p.x, p.y, p.z)
						if st > 0 and b.has_prop(st, "lit"):
							world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "true" if lit else "false"), false)
					if _items_touched:
						Redstone.request(world, p)
			elif id == "brewing_stand":
				if Potions.step(d):
					ch.modified = true
			elif id == "campfire" or id == "soul_campfire":
				if campfire_step(world, pos_of(ch, k), d):
					ch.modified = true
			elif id == "hopper":
				# wiki Hopper: each hopper has its own transfer cooldown - 8 game ticks after it pushes / pulls (7 after an
				# item was pushed into it while it was empty); without a cooldown it tries every tick
				d["t"] = int(world.game_time)
				var cd := int(d.get("cd", 0)) - 1
				if cd > 0:
					d["cd"] = cd
					continue
				d["cd"] = 0
				var hp := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
				if hopper_step(world, hp, d):
					d["cd"] = HOPPER_COOLDOWN
					ch.modified = true
					Redstone.request(world, hp)


## wiki Campfire: right-clicking with food that has a campfire_cooking recipe puts one on the first free of 4 slots;
## while lit each cooks for its recipe time (600 ticks) and then pops off as the cooked item; unlit, progress drops by
## 2 per tick (Java CampfireBlockEntity.cookTick / cooldownTick).
static func campfire_place(world, p: Vector3i, held: ItemStack, pl: Player) -> bool:
	if held.is_empty() or Crafting.smelt_result(held.item, "campfire_cooking") == null:
		return false
	var d := get_data(world, p)
	if d.is_empty():
		d = {"id": Res.blocks.name_of(world.state_at(p.x, p.y, p.z)), "items": [{}, {}, {}, {}], "cook": [0, 0, 0, 0], "total": [0, 0, 0, 0]}
	var items: Array = d.get("items", [{}, {}, {}, {}])
	for i in 4:
		if ItemStack.from_dict(items[i]).is_empty():
			var one := held.copy()
			one.count = 1
			items[i] = one.to_dict()
			(d["cook"] as Array)[i] = 0
			(d["total"] as Array)[i] = int(Crafting.smelt_info(held.item, "campfire_cooking")[3])
			d["items"] = items
			set_data(world, p, d)
			BERender.refresh(p)
			if not pl.is_creative():
				pl.inventory.consume_held()
			return true
	return false


static func campfire_step(world, p: Vector3i, d: Dictionary) -> bool:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0:
		return false
	var lit := Res.blocks.get_prop(st, "lit") == "true"
	if lit:
		Particles.campfire_tick(p, Res.blocks.get_prop(st, "signal_fire") == "true")
	var items: Array = d.get("items", [])
	var cook: Array = d.get("cook", [0, 0, 0, 0])
	var changed := false
	for i in mini(4, items.size()):
		var s := ItemStack.from_dict(items[i])
		if s.is_empty():
			continue
		if lit:
			cook[i] = int(cook[i]) + 1
			if int(cook[i]) >= int((d.get("total", [600, 600, 600, 600]) as Array)[i]):
				var out := Crafting.smelt_result(s.item, "campfire_cooking")
				items[i] = {}
				cook[i] = 0
				if out != null:
					world.entities.spawn_item(Vector3(p) + Vector3(0.5, 0.5, 0.5), out)
				BERender.refresh(p)
				changed = true
		elif int(cook[i]) > 0:
			cook[i] = maxi(0, int(cook[i]) - 2)
	d["cook"] = cook
	return changed


## Java HopperBlockEntity (8-tick cooldown): push one item toward "facing", then pull one item from above;
## locked while powered (enabled=false). Furnace faces: from above -> input, from the side -> fuel, below -> output.
static func hopper_step(world, p: Vector3i, d: Dictionary) -> bool:
	var items: Array = d.get("items", [])
	# idle fast path (hoppers off cooldown try every tick): nothing to push, no container above, no item entity to collect
	if not _any_item(items):
		var above := get_data(world, p + Vector3i(0, 1, 0))
		if (above.is_empty() or not (above.has("items") or above.has("loot_table"))) and _hopper_items(world, p).is_empty():
			return false
	var b := Res.blocks
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0 or b.get_prop(st, "enabled") == "false":
		return false
	var moved := false
	var f: Vector3i = Redstone.H.get(b.get_prop(st, "facing"), Vector3i(0, -1, 0))
	var tgt := p + f
	var td := ensure_loot(world, tgt)
	if not td.is_empty() and td.has("items") and _any_item(items):
		var into_empty_hopper: bool = str(td.get("id", "")) == "hopper" and not _any_item(td["items"])
		for i in items.size():
			var s := ItemStack.from_dict(items[i])
			if s.is_empty():
				continue
			var one := s.copy()
			one.count = 1
			if _insert(td, one, str(td.get("id", "")), f):
				s.count -= 1
				items[i] = s.to_dict() if s.count > 0 else {}
				if into_empty_hopper:
					# wiki Hopper: an item pushed into an empty hopper gives it a 7 game tick cooldown (8 when the receiving
					# hopper has not ticked yet this game tick: its own tick takes one off)
					td["cd"] = HOPPER_COOLDOWN if int(td.get("t", -1)) < int(world.game_time) else HOPPER_COOLDOWN - 1
				set_data(world, tgt, td)
				moved = true
				break
	var src := p + Vector3i(0, 1, 0)
	var sd := ensure_loot(world, src)
	if not sd.is_empty() and sd.has("items"):
		var sitems: Array = sd["items"]
		var sid := str(sd.get("id", ""))
		var slots: Array = range(sitems.size())
		if sid in ["furnace", "blast_furnace", "smoker"]:
			# wiki: Hopper - from below: the output slot, and empty buckets left in the fuel slot
			slots = [2]
			if sitems.size() > 1 and ItemStack.from_dict(sitems[1]).name() == "bucket":
				slots.append(1)
		for i in slots:
			var s2 := ItemStack.from_dict(sitems[i])
			if s2.is_empty():
				continue
			var one2 := s2.copy()
			one2.count = 1
			if _insert(d, one2, "hopper", Vector3i(0, -1, 0)):
				s2.count -= 1
				sitems[i] = s2.to_dict() if s2.count > 0 else {}
				sd["items"] = sitems
				set_data(world, src, sd)
				moved = true
				break
	elif _collect_items(world, p, d):
		moved = true
	return moved


const HOPPER_COOLDOWN := 8   # wiki Hopper: 8 game ticks after a transfer
static var _item_cells: Dictionary = {}   # block cell -> item entities in it (rebuilt at most once per game tick)
static var _item_cells_t := -1


## Item entities a hopper at p can reach: inside its bowl (its own block) and in the block space above it.
static func _hopper_items(world, p: Vector3i) -> Array:
	var now := int(world.game_time)
	if _item_cells_t != now:
		_item_cells_t = now
		_item_cells.clear()
		var em = world.get("entities")
		if em != null:
			for e in em.ents:
				if e.kind == "item" and not e.dead and e.stack != null:
					var c := Vector3i(floori(e.pos.x), floori(e.pos.y), floori(e.pos.z))
					var l = _item_cells.get(c)
					if l == null:
						_item_cells[c] = [e]
					else:
						(l as Array).append(e)
	if _item_cells.is_empty():
		return []
	var out: Array = []
	var l0 = _item_cells.get(p)
	if l0 != null:
		out.append_array(l0)
	var l1 = _item_cells.get(p + Vector3i(0, 1, 0))
	if l1 != null:
		out.append_array(l1)
	return out


## wiki Hopper: with no container above it collects item entities from the whole block space above it (a full block
## there blocks that unless tagged #does_not_block_hoppers; items in the bowl are always taken), as much of the stack
## as fits; the rest stays on the ground.
static func _collect_items(world, p: Vector3i, d: Dictionary) -> bool:
	var found := _hopper_items(world, p)
	if found.is_empty():
		return false
	var b := Res.blocks
	var up: int = world.state_at(p.x, p.y + 1, p.z)
	var blocked: bool = up > 0 and (b.st_flags[up] & (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE)) == (BlockRegistry.F_FULL_SHAPE | BlockRegistry.F_COLLIDE) \
		and not Tags.has_block("does_not_block_hoppers", b.name_of(up))
	var em = world.get("entities")
	for e in found:
		if e.dead or e.stack == null or e.stack.is_empty() or (blocked and floori(e.pos.y) > p.y):
			continue
		var before: int = e.stack.count
		while not e.stack.is_empty():
			var one: ItemStack = e.stack.copy()
			one.count = 1
			if not _insert(d, one, "hopper", Vector3i(0, -1, 0)):
				break
			e.stack.count -= 1
		if e.stack.count < before:
			if e.stack.count <= 0:
				if em != null:
					em._remove(e)
				else:
					e.dead = true
			return true
	return false


static func _any_item(items: Array) -> bool:
	for it in items:
		if it is Dictionary and not (it as Dictionary).is_empty() and not ItemStack.from_dict(it).is_empty():
			return true
	return false


static func _insert(d: Dictionary, s: ItemStack, id: String, dir: Vector3i) -> bool:
	if id == "crafter":
		return Crafter.insert_one(d, s)
	var items: Array = d.get("items", [])
	var slots: Array = range(items.size())
	if id in ["furnace", "blast_furnace", "smoker"]:
		slots = [0] if dir.y < 0 else ([1] if dir.y == 0 else [])
		if dir.y == 0 and Crafting.fuel_time(s.item) <= 0:
			return false   # wiki: Hopper - from the side only items that work as fuel go into the fuel slot
	for i in slots:
		var cur := ItemStack.from_dict(items[i])
		if cur.is_empty():
			items[i] = s.to_dict()
			d["items"] = items
			return true
		if cur.can_merge(s) and cur.count < cur.max_stack():
			cur.count += 1
			items[i] = cur.to_dict()
			d["items"] = items
			return true
	return false


# ------------------------------------------------------------------ jukebox playback (allay dancing)

static var playing: Dictionary = {}   # jukebox position -> [start game time, length in ticks]


static func jukebox_stop(p: Vector3i) -> void:
	playing.erase(p)
	Audio.stop_at(Vector3(p) + Vector3(0.5, 0.5, 0.5), "Jukebox")


## A jukebox playing a record within r blocks of pos (Java GameEvent.JUKEBOX_PLAY reach: closerToCenterThan).
static func playing_jukebox_near(world, pos: Vector3, r: float) -> bool:
	var t: int = int(world.game_time)
	for jp in playing.keys():
		var v: Array = playing[jp]
		if t - int(v[0]) >= int(v[1]):
			continue   # (tick_jukeboxes ends it and updates redstone)
		if Res.blocks.name_of(maxi(world.state_at(jp.x, jp.y, jp.z), 0)) != "jukebox":
			playing.erase(jp)
			continue
		if (Vector3(jp) + Vector3(0.5, 0.5, 0.5)).distance_to(pos) < r:
			return true
	return false


## wiki Jukebox: a redstone signal of 15 while the disc's music plays.
static func jukebox_playing(world, p: Vector3i) -> bool:
	var v = playing.get(p)
	return v != null and int(world.game_time) - int(v[0]) < int(v[1])


## Per tick (O(playing jukeboxes)): a finished track ends the jukebox's redstone output (the disc stays inside).
static func tick_jukeboxes(world) -> void:
	if playing.is_empty():
		return
	var t: int = int(world.game_time)
	for jp in playing.keys():
		var v: Array = playing[jp]
		if t - int(v[0]) >= int(v[1]):
			playing.erase(jp)
			Redstone.on_changed(world, jp)
