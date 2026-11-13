## BlockEntities — typed per-block data stored in Chunk.block_entities (key = packed local pos):
## containers (chest/barrel/shulker 27, hopper 5, dispenser/dropper 9, furnace family 3 + burn/cook
## progress), jukebox disc, note block sounds. Furnaces tick while their chunk is loaded.
## Contract: get_data/set_data(world, pos, dict); on_placed/on_removed; container_size(kind); tick_furnaces(world).
class_name BlockEntities

const INSTRUMENTS := {"harp": "harp", "basedrum": "basedrum", "snare": "snare", "hat": "hat", "bass": "bass", "flute": "flute",
	"bell": "bell", "guitar": "guitar", "chime": "chime", "xylophone": "xylophone", "iron_xylophone": "iron_xylophone",
	"cow_bell": "cow_bell", "didgeridoo": "didgeridoo", "bit": "bit", "banjo": "banjo", "pling": "pling", "trumpet": "trumpet"}


static func _key(p: Vector3i) -> int:
	return ((p.y - Coords.MIN_Y) << 8) | ((p.z & 15) << 4) | (p.x & 15)


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
	if changed:
		set_data(world, p, d)


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
	var ctx := {"tool": null, "rng": world.rng, "by_player": true}
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
	if d.has("book"):
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.0, 0.5), ItemStack.from_dict(d["book"]))
	var c: Chunk = world.cm.get_chunk(p.x >> 4, p.z >> 4)
	if c != null:
		c.block_entities.erase(_key(p))
		epoch += 1
		edit_epoch += 1


static func play_note(world, p: Vector3i) -> void:
	var b := Res.blocks
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0 or world.state_at(p.x, p.y + 1, p.z) != 0:
		return
	var inst := b.get_prop(st, "instrument")
	if inst == "":
		inst = "harp"
	var note := int(b.get_prop(st, "note"))
	var pitch := pow(2.0, (note - 12) / 12.0)
	Audio.play("block.note_block." + INSTRUMENTS.get(inst, inst), Vector3(p) + Vector3(0.5, 0.5, 0.5), "Jukebox", 3.0, pitch)
	# Java NoteParticle: hue from the note (0-24)
	var hue := float(note) / 24.0
	Particles.emit("note", Vector3(p) + Vector3(0.5, 1.2, 0.5), Vector3.ZERO, Color(maxf(0.0, sin((hue + 0.0) * TAU) * 0.65 + 0.35), maxf(0.0, sin((hue + 1.0 / 3.0) * TAU) * 0.65 + 0.35), maxf(0.0, sin((hue + 2.0 / 3.0) * TAU) * 0.65 + 0.35)))


static func use_jukebox(world, p: Vector3i, pl: Player) -> bool:
	var d := get_data(world, p)
	if d.has("disc"):
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.0, 0.5), ItemStack.from_dict(d["disc"]))
	if d.has("book"):
		world.entities.spawn_item(Vector3(p) + Vector3(0.5, 1.0, 0.5), ItemStack.from_dict(d["book"]))
		d.erase("disc")
		set_data(world, p, d)
		Audio.stop_music()
		return true
	var h := pl.inventory.held()
	if h.is_empty() or not h.name().begins_with("music_disc"):
		return false
	d["disc"] = h.split(1).to_dict()
	set_data(world, p, d)
	pl.inventory.changed.emit()
	var song := h.name().trim_prefix("music_disc_") if not h.is_empty() else str(d["disc"]["id"]).trim_prefix("minecraft:music_disc_")
	Audio.play("music_disc." + song, Vector3(p) + Vector3(0.5, 0.5, 0.5), "Jukebox", 4.0)
	return true


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
	if int(d.get("burn", 0)) > 0 and can:
		d["cook"] = int(d.get("cook", 0)) + 1
		var info := Crafting.smelt_info(input.item, rk)
		var total := int(info[3]) if info.size() > 3 else 200
		if int(d["cook"]) >= total:
			d["cook"] = 0
			input.count -= 1
			if input.count <= 0:
				input.clear()
			if out.is_empty():
				out = result
			else:
				out.count += result.count
			d["xp"] = float(d.get("xp", 0.0)) + (float(info[2]) if info.size() > 2 else 0.1)
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
	if c.block_entities.is_empty():
		return
	_index_owner(cm)
	for k in c.block_entities:
		var d = c.block_entities[k]
		if d is Dictionary:
			_index_put(c, str((d as Dictionary).get("id", "")))


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


const TICKED_KINDS := ["furnace", "blast_furnace", "smoker", "brewing_stand", "hopper"]


static func tick_furnaces(world) -> void:
	var b := Res.blocks
	for c in chunks_with(world, TICKED_KINDS):
		var ch: Chunk = c
		if ch.state == Chunk.EVICTED or ch.block_entities.is_empty():
			continue
		for k in ch.block_entities:
			var d: Dictionary = ch.block_entities[k]
			var id := str(d.get("id", ""))
			if id in ["furnace", "blast_furnace", "smoker"]:
				var was := int(d.get("burn", 0)) > 0
				if furnace_step(d):
					ch.modified = true
					var lit := int(d.get("burn", 0)) > 0
					if lit != was:
						var p := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
						var st: int = world.state_at(p.x, p.y, p.z)
						if st > 0 and b.has_prop(st, "lit"):
							world.set_block(p.x, p.y, p.z, b.with_prop(st, "lit", "true" if lit else "false"), false)
			elif id == "brewing_stand":
				if Potions.step(d):
					ch.modified = true
			elif id == "hopper" and world.game_time % 8 == 0:
				var hp := Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15))
				if hopper_step(world, hp, d):
					ch.modified = true


## Java HopperBlockEntity (8-tick cooldown): push one item toward "facing", then pull one item from above;
## locked while powered (enabled=false). Furnace faces: from above -> input, from the side -> fuel, below -> output.
static func hopper_step(world, p: Vector3i, d: Dictionary) -> bool:
	var b := Res.blocks
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0 or b.get_prop(st, "enabled") == "false":
		return false
	var items: Array = d.get("items", [])
	var moved := false
	var f: Vector3i = Redstone.H.get(b.get_prop(st, "facing"), Vector3i(0, -1, 0))
	var tgt := p + f
	var td := ensure_loot(world, tgt)
	if not td.is_empty() and td.has("items"):
		for i in items.size():
			var s := ItemStack.from_dict(items[i])
			if s.is_empty():
				continue
			var one := s.copy()
			one.count = 1
			if _insert(td, one, str(td.get("id", "")), f):
				s.count -= 1
				items[i] = s.to_dict() if s.count > 0 else {}
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
			slots = [2]
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
	return moved


static func _insert(d: Dictionary, s: ItemStack, id: String, dir: Vector3i) -> bool:
	if id == "crafter":
		return Crafter.insert_one(d, s)
	var items: Array = d.get("items", [])
	var slots: Array = range(items.size())
	if id in ["furnace", "blast_furnace", "smoker"]:
		slots = [0] if dir.y < 0 else ([1] if dir.y == 0 else [])
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
