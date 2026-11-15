## CopperGolem — the Java 26.x copper golem (minecraft.wiki "Copper Golem"): building it, item sorting (copper chests ->
## chests / trapped chests), oxidation, waxing / scraping, and turning into a copper golem statue.
## - Sorting: empty-handed it examines the nearest unvisited copper chest for 3 s and takes up to 16 of the first item;
##   holding items it examines the nearest unvisited chest or trapped chest for 3 s and puts them into the frontmost
##   empty slot if the chest is empty or already holds that item type (other stacks are not topped up). Up to 9
##   examined chests are remembered; after the 10th fruitless check it wanders 7 s and forgets them; a delivery forgets
##   them too. Search box 65 x 17 x 65 around its block, chests at most 1 block above / 2 below where it stands.
## - Oxidation: every 504000..552000 game ticks one stage (unless waxed); fully oxidized and unwaxed: 0.58 % per tick it
##   becomes a copper golem statue (random pose) when it stands fully in air, dropping what it holds.
## Contract: static functions on EntityManager.Ent mobs with id "copper_golem" (state in e.data).
class_name CopperGolem

const CARRY := 16
const EXAMINE_TICKS := 60
const MEMORY := 9
const WANDER_TICKS := 140
const SEARCH_XZ := 32
const SEARCH_Y := 8
const STAGE_MIN := 504000
const STAGE_MAX := 552000
const STATUE_CHANCE := 0.0058
const GIVE_UP_TICKS := 400
const POSES := ["standing", "sitting", "running", "star"]
const SOURCE_IDS := ["copper_chest", "exposed_copper_chest", "weathered_copper_chest", "oxidized_copper_chest", "waxed_copper_chest",
	"waxed_exposed_copper_chest", "waxed_weathered_copper_chest", "waxed_oxidized_copper_chest"]
const DEST_IDS := ["chest", "trapped_chest"]


static func held(e) -> ItemStack:
	var d = e.data.get("held_stack")
	return ItemStack.from_dict(d) if d is Dictionary else ItemStack.new()


static func _set_held(e, s: ItemStack) -> void:
	if s == null or s.is_empty():
		e.data.erase("held_stack")
		e.data.erase("held")
	else:
		e.data["held_stack"] = s.to_dict()
		e.data["held"] = s.name()   # (ItemInHandLayer: the carried item shows in its hand)


static func stage(e) -> int:
	return int(e.data.get("oxidation", 0))


static func waxed(e) -> bool:
	return bool(e.data.get("waxed", false))


## A new golem (spawn egg / building): the oxidation timer starts now (Java next_weather_age).
static func init(em, e, oxidation: int = 0) -> void:
	e.data["oxidation"] = clampi(oxidation, 0, 3)
	e.data["next_weather_age"] = int(em.world.game_time) + em.rng.randi_range(STAGE_MIN, STAGE_MAX)


## Java CopperGolemSpawning: a carved pumpkin / jack o'lantern placed on (or beside / under) a copper block. The block
## becomes a copper chest of the same oxidation facing like the pumpkin, the golem appears where the pumpkin was.
static func try_build(world, pos: Vector3i, st: int) -> bool:
	var b := Res.blocks
	for d in [Vector3i(0, -1, 0), Vector3i(0, 1, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]:
		var q: Vector3i = pos + d
		var qs: int = world.state_at(q.x, q.y, q.z)
		if qs <= 0:
			continue
		var cp := Copper.parse(b.name_of(qs))
		if cp.is_empty() or cp[0] != "copper_block":
			continue
		var chest_st := b.default_state(Copper.name_of("copper_chest", cp[1], false))
		if chest_st <= 0:
			return false
		if b.has_prop(chest_st, "facing") and b.has_prop(st, "facing"):
			chest_st = b.with_prop(chest_st, "facing", b.get_prop(st, "facing"))
		world.set_block(pos.x, pos.y, pos.z, 0)
		world.set_block(q.x, q.y, q.z, chest_st)
		BlockEntities.on_placed(world, q, chest_st)
		var e = world.entities.spawn_mob("copper_golem", Vector3(pos) + Vector3(0.5, 0.0, 0.5))
		if e != null:
			init(world.entities, e, cp[1])
			e.persistent = true
		Audio.play("entity.copper_golem.spawn", Vector3(pos), "Neutral")
		return true
	return false


## Java CopperGolemRenderer: copper_golem / _exposed / _weathered / _oxidized texture by oxidation stage.
static func retexture(e) -> void:
	if e.node == null:
		return
	var st := stage(e)
	e.node.set_meta("cg_tex", st)
	var m := EntityRenderer.material(["entity/copper_golem/copper_golem", "entity/copper_golem/copper_golem_exposed",
		"entity/copper_golem/copper_golem_weathered", "entity/copper_golem/copper_golem_oxidized"][st])
	var stack: Array = [e.node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			(n as MeshInstance3D).material_override = m
		stack.append_array(n.get_children())


## Per-tick: oxidation and the statue conversion. Returns false when the golem is gone (became a statue).
static func tick_body(em, e) -> bool:
	var w = em.world
	if int(e.node.get_meta("cg_tex", -1)) != stage(e):
		retexture(e)
	if waxed(e):
		return true
	if not e.data.has("next_weather_age"):
		init(em, e, stage(e))
	var st := stage(e)
	if st < 3 and int(w.game_time) >= int(e.data["next_weather_age"]):
		e.data["oxidation"] = st + 1
		e.data["next_weather_age"] = int(w.game_time) + em.rng.randi_range(STAGE_MIN, STAGE_MAX)
		retexture(e)
	elif st >= 3 and em.rng.randf() < STATUE_CHANCE:
		return not _to_statue(em, e)
	return true


static func _to_statue(em, e) -> bool:
	var w = em.world
	var bp := Vector3i(e.pos.floor())
	for dy in [0, 1]:
		var s: int = w.state_at(bp.x, bp.y + dy, bp.z)
		if s != 0 and (s < 0 or (Res.blocks.st_flags[s] & BlockRegistry.F_AIR) == 0):
			return false   # Java: only fully inside air
	var sst := Res.blocks.default_state("oxidized_copper_golem_statue")
	if sst <= 0:
		return false
	var facing: String = ["south", "west", "north", "east"][int(posmod(roundi(e.body_yaw / 90.0), 4))]
	if Res.blocks.has_prop(sst, "facing"):
		sst = Res.blocks.with_prop(sst, "facing", facing)
	if Res.blocks.has_prop(sst, "copper_golem_pose"):
		sst = Res.blocks.with_prop(sst, "copper_golem_pose", POSES[em.rng.randi_range(0, 3)])
	var h := held(e)
	if not h.is_empty():
		em.spawn_item(e.pos + Vector3(0, 0.5, 0), h)
	w.set_block(bp.x, bp.y, bp.z, sst)
	Audio.play("entity.copper_golem_become_statue", e.pos, "Neutral")
	em._remove(e)
	return true


## Axe on an unoxidized, unwaxed statue: it comes back to life (Java CopperGolemStatueBlock).
static func reanimate(world, pos: Vector3i, st: int) -> bool:
	if Res.blocks.name_of(st) != "copper_golem_statue":
		return false
	world.set_block(pos.x, pos.y, pos.z, 0)
	var e = world.entities.spawn_mob("copper_golem", Vector3(pos) + Vector3(0.5, 0.0, 0.5))
	if e != null:
		init(world.entities, e, 0)
		e.persistent = true
	Audio.play("item.axe.scrape", Vector3(pos), "Blocks")
	return true


## Statue right-click (not an axe): the next of the four poses.
static func cycle_pose(world, pos: Vector3i, st: int) -> bool:
	var b := Res.blocks
	if not b.name_of(st).ends_with("copper_golem_statue") or not b.has_prop(st, "copper_golem_pose"):
		return false
	var i := POSES.find(b.get_prop(st, "copper_golem_pose"))
	world.set_block(pos.x, pos.y, pos.z, b.with_prop(st, "copper_golem_pose", POSES[(i + 1) % 4]))
	Audio.play("block.copper_golem_statue.hit", Vector3(pos), "Blocks")
	return true


## Player interaction: honeycomb waxes, an axe removes wax or one oxidation stage, an empty hand takes the item it holds.
static func interact(em, e, p: Player, hand: ItemStack) -> bool:
	var name := hand.name() if not hand.is_empty() else ""
	if name == "honeycomb" and not waxed(e):
		e.data["waxed"] = true
		e.data["next_weather_age"] = -2
		Audio.play("item.honeycomb.wax_on", e.pos, "Neutral")
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	if name.ends_with("_axe"):
		if waxed(e):
			e.data["waxed"] = false
			init(em, e, stage(e))
			Audio.play("item.axe.wax_off", e.pos, "Neutral")
		elif stage(e) > 0:
			e.data["oxidation"] = stage(e) - 1
			e.data["next_weather_age"] = int(em.world.game_time) + em.rng.randi_range(STAGE_MIN, STAGE_MAX) + 1
			retexture(e)
			Audio.play("item.axe.scrape", e.pos, "Neutral")
		else:
			return false
		Interaction.damage_tool(p, 1)
		return true
	if hand.is_empty() and not held(e).is_empty():
		em.spawn_item(e.pos + Vector3(0, 0.6, 0), held(e))
		_set_held(e, ItemStack.new())
		return true
	return false


static func lightning(em, e) -> void:
	if not waxed(e) and stage(e) > 0:
		e.data["oxidation"] = stage(e) - 1
		retexture(e)


static var _gc := 0


static func golem_open_cleanup_due(now: int) -> bool:
	if BERender.golem_open.size() > 64 and now - _gc > 200:
		_gc = now
		return true
	return false


## Sorting goal: the navigation target this tick, Vector3.INF to let the golem stroll (no work / wandering).
static func goal(em, e) -> Vector3:
	var w = em.world
	var now: int = w.game_time
	if int(e.data.get("cg_wander", 0)) > now:
		return Vector3.INF
	var carrying := not held(e).is_empty()
	var ex = e.data.get("cg_open")
	if ex != null:
		var ep := Vector3i(ex[0], ex[1], ex[2])
		e.vel.x = 0.0
		e.vel.z = 0.0
		MobControl.set_look(e, Vector3(ep) + Vector3(0.5, 0.5, 0.5), 30.0, 30.0)
		BERender.golem_open[ep] = now + 2
		if golem_open_cleanup_due(now):
			BERender.golem_open.clear()
			BERender.golem_open[ep] = now + 2
		if now < int(ex[3]):
			return e.pos   # examining (standing at the chest)
		e.data.erase("cg_open")
		var done := _deposit(w, e, ep) if carrying else _take(w, e, ep)
		_visit(e, ep, done, now)
		Audio.play(("entity.copper_golem.item_drop" if done else "entity.copper_golem.item_no_drop") if carrying else ("entity.copper_golem.no_item_get" if done else "entity.copper_golem.no_item_no_get"), e.pos, "Neutral")
		Audio.play("block.chest.close" if not ex[4] else "block.copper_chest.close", Vector3(ep), "Blocks", 0.5)
		return Vector3.INF
	var tg = e.data.get("cg_target")
	if tg != null:
		var tp := Vector3i(tg[0], tg[1], tg[2])
		var ok := _is_kind(w, tp, carrying)
		if not ok or now - int(tg[3]) > GIVE_UP_TICKS:
			e.data.erase("cg_target")
			_visit(e, tp, false, now)
			return Vector3.INF
		var c := Vector3(tp) + Vector3(0.5, 0.0, 0.5)
		var dy := tp.y - int(floor(e.pos.y))
		if Vector2(c.x - e.pos.x, c.z - e.pos.z).length() <= 1.7 and dy <= 1 and dy >= -2:
			e.data.erase("cg_target")
			e.data["cg_open"] = [tp.x, tp.y, tp.z, now + EXAMINE_TICKS, not carrying]
			Audio.play("block.copper_chest.open" if not carrying else "block.chest.open", Vector3(tp), "Blocks", 0.5)
			return e.pos
		return c
	if now % 10 != int(e.age) % 10:
		return Vector3.INF   # (look for the next chest twice a second)
	var found = _nearest(w, e, carrying)
	if found == null:
		return Vector3.INF
	var fp: Vector3i = found
	e.data["cg_target"] = [fp.x, fp.y, fp.z, now]
	return Vector3(fp) + Vector3(0.5, 0.0, 0.5)


static func _visit(e, p: Vector3i, success: bool, now: int) -> void:
	var v: Array = e.data.get("cg_visited", [])
	if success:
		e.data["cg_visited"] = []
		e.data["cg_fails"] = 0
		return
	v.append([p.x, p.y, p.z])
	while v.size() > MEMORY:
		v.pop_front()
	e.data["cg_visited"] = v
	var f := int(e.data.get("cg_fails", 0)) + 1
	e.data["cg_fails"] = f
	if f >= MEMORY + 1:
		# Java: after checking 10 chests in vain: wander 7 s, forget them, keep searching
		e.data["cg_fails"] = 0
		e.data["cg_visited"] = []
		e.data["cg_wander"] = now + WANDER_TICKS


static func _is_kind(w, p: Vector3i, carrying: bool) -> bool:
	var s: int = w.state_at(p.x, p.y, p.z)
	if s <= 0:
		return false
	var n := Res.blocks.name_of(s)
	return DEST_IDS.has(n) if carrying else SOURCE_IDS.has(n)


static func _nearest(w, e, carrying: bool):
	var ids: Array = DEST_IDS if carrying else SOURCE_IDS
	var bp := Vector3i(e.pos.floor())
	var visited: Array = e.data.get("cg_visited", [])
	var best = null
	var bd := INF
	for c in BlockEntities.chunks_with(w, ids):
		var ch: Chunk = c
		if absi(ch.cx * 16 + 8 - bp.x) > SEARCH_XZ + 8 or absi(ch.cz * 16 + 8 - bp.z) > SEARCH_XZ + 8:
			continue
		for k in ch.block_entities:
			var d = ch.block_entities[k]
			if not (d is Dictionary) or not ids.has(str((d as Dictionary).get("id", ""))):
				continue
			var kk: int = k
			var p := Vector3i(ch.cx * 16 + (kk & 15), (kk >> 8) + Coords.MIN_Y, ch.cz * 16 + ((kk >> 4) & 15))
			if absi(p.x - bp.x) > SEARCH_XZ or absi(p.z - bp.z) > SEARCH_XZ or absi(p.y - bp.y) > SEARCH_Y:
				continue
			if visited.has([p.x, p.y, p.z]):
				continue
			var dd := Vector3(p).distance_squared_to(e.pos)
			if dd < bd:
				bd = dd
				best = p
	return best


## Items of a chest, its double-chest partner's after them (Java CompoundContainer).
static func _containers(w, p: Vector3i) -> Array:
	var out: Array = [p]
	var st: int = w.state_at(p.x, p.y, p.z)
	var b := Res.blocks
	if st > 0 and b.has_prop(st, "type") and b.get_prop(st, "type") != "single":
		var f := b.get_prop(st, "facing")
		var left := b.get_prop(st, "type") == "left"
		var cw := {"north": Vector3i(1, 0, 0), "east": Vector3i(0, 0, 1), "south": Vector3i(-1, 0, 0), "west": Vector3i(0, 0, -1)}
		var dvec: Vector3i = cw.get(f, Vector3i(1, 0, 0))
		var other := p + (dvec if left else -dvec)
		var os: int = w.state_at(other.x, other.y, other.z)
		if os > 0 and b.st_block[os] == b.st_block[st]:
			out.append(other)
	return out


static func _take(w, e, p: Vector3i) -> bool:
	for cp in _containers(w, p):
		var d := BlockEntities.ensure_loot(w, cp)
		var items: Array = d.get("items", [])
		for i in items.size():
			var s := ItemStack.from_dict(items[i])
			if s.is_empty():
				continue
			var take := s.split(mini(CARRY, s.count))
			items[i] = s.to_dict() if not s.is_empty() else {}
			d["items"] = items
			BlockEntities.set_data(w, cp, d)
			_set_held(e, take)
			return true
	return false


static func _deposit(w, e, p: Vector3i) -> bool:
	var h := held(e)
	var conts := _containers(w, p)
	var all_empty := true
	var has_same := false
	for cp in conts:
		var d := BlockEntities.ensure_loot(w, cp)
		for it in d.get("items", []):
			var s := ItemStack.from_dict(it)
			if s.is_empty():
				continue
			all_empty = false
			if s.item == h.item:
				has_same = true
	if not all_empty and not has_same:
		return false
	for cp in conts:
		var d2 := BlockEntities.ensure_loot(w, cp)
		var items: Array = d2.get("items", [])
		for i in items.size():
			if ItemStack.from_dict(items[i]).is_empty():
				items[i] = h.to_dict()
				d2["items"] = items
				BlockEntities.set_data(w, cp, d2)
				_set_held(e, ItemStack.new())
				return true
	return false
