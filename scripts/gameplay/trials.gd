## Spawners, trial spawners, vaults, wind charges.
## - Spawner (Java BaseSpawner): active while a player is within 16 blocks; delay 20 then rand 200-800 ticks; spawns
##   up to 4 of its mob within +-4 blocks (y -1..+1) when fewer than 6 are nearby; flame/smoke particles.
##   Dungeon spawners: skeleton / zombie / zombie / spider (Java MonsterRoomFeature.MOBS).
## - Trial spawner (Java TrialSpawner + installed trial_spawner configs): waiting -> active when a player is within
##   14 blocks; spawns total_mobs (+ per extra player) with at most simultaneous_mobs alive, ticks_between_spawn
##   apart, within spawn_range 4; when all are spawned and dead it ejects one reward roll per player (consumables or
##   key, 20 ticks apart) and cools down for 36000 ticks (30 min).
## - Vault (Java VaultBlockEntity): active when a player is within 4 blocks; a trial key (ominous vaults: ominous
##   trial key) unlocks it once per player and ejects chests/trial_chambers/reward[_ominous] one item per 20 ticks.
## - Breeze wind charge (Java BreezeWindCharge): every 40 ticks within 16 blocks; burst knocks back within 1.2 blocks.
## - Spawn eggs used on either spawner set its mob (set_spawner_mob); trial spawners show the mob they spawn next.
## - Ominous trials (_omen_check): Bad Omen -> Trial Omen (15 min per level), spawners within 15 blocks turn ominous and
##   use their ominous config until their cooldown ends: mobs wear the config's equipment loot table
##   (equip_from_config: trial_chamber_melee / _ranged, no drops), and every 8 s an ominous item spawner appears 2-5
##   blocks above a player in range or one of the spawner's mobs and drops / shoots its item after 3-6 s
##   (_ominous_items / tick_ominous_item; items from items_to_drop_when_ominous).
class_name Trials
extends RefCounted

const DUNGEON_MOBS := ["skeleton", "zombie", "zombie", "spider"]
const TS_STATES := {"waiting": "waiting_for_players", "active": "active", "ejecting": "ejecting_reward", "cooldown": "cooldown"}

static var _tracked: Dictionary = {}   # Vector3i -> Array[Ent] spawned by that trial spawner (not persisted)
static var _cfg_cache: Dictionary = {}


static var _bes_cache: Array = []
static var _bes_key := Vector3i(-1, -1, -1)
static var _bes_at := -1000


## Spawner / trial spawner / vault entries [pos, data, chunk]; rebuilt only when block entities changed (the full scan
## over every block entity of their chunks ran every 2 ticks: 2-4 ms with trial chambers loaded). Edits rebuild it at
## once; chunks loading in (far away, at the render-distance edge) at most once per second.
static func _bes(world) -> Array:
	var key := Vector3i(BlockEntities.epoch, BlockEntities.edit_epoch, world.cm.get_instance_id() & 0x7FFFFFFF if world.cm != null else 0)
	if key == _bes_key or (key.y == _bes_key.y and key.z == _bes_key.z and int(world.game_time) - _bes_at < 20 and int(world.game_time) >= _bes_at):
		return _bes_cache
	_bes_key = key
	_bes_at = int(world.game_time)
	var out: Array = []
	for c in BlockEntities.chunks_with(world, ["spawner", "trial_spawner", "vault"]):
		var ch: Chunk = c
		if ch.block_entities.is_empty() or ch.state < Chunk.DECORATED:
			continue
		for k in ch.block_entities:
			var d: Dictionary = ch.block_entities[k]
			var id := str(d.get("id", ""))
			if id == "spawner" or id == "trial_spawner" or id == "vault":
				out.append([Vector3i(ch.cx * 16 + (k & 15), (k >> 8) + Coords.MIN_Y, ch.cz * 16 + ((k >> 4) & 15)), d, ch])
	_bes_cache = out
	return out


static func tick(world) -> void:
	if world.game_time % 2 != 0:
		return
	var p: Player = world.player
	for e in _bes(world):
		if (e[2] as Chunk).state == Chunk.EVICTED:
			continue
		var pos: Vector3i = e[0]
		var d: Dictionary = e[1]
		var dist := p.pos.distance_to(Vector3(pos) + Vector3(0.5, 0.5, 0.5))
		match str(d["id"]):
			"spawner":
				if dist <= 16.0 and not p.is_spectator():
					_spawner(world, pos, d)
					(e[2] as Chunk).modified = true
			"trial_spawner":
				_trial(world, pos, d, dist)
				(e[2] as Chunk).modified = true
			"vault":
				_vault(world, pos, d, dist)


# ------------------------------------------------------------------ classic spawner

static func _spawner(world, pos: Vector3i, d: Dictionary) -> void:
	var rng: RandomNumberGenerator = world.rng
	if rng.randf() < 0.3:
		Particles.emit("smoke", Vector3(pos) + Vector3(rng.randf(), rng.randf(), rng.randf()))
		Particles.emit("flame", Vector3(pos) + Vector3(rng.randf(), rng.randf(), rng.randf()))
	var delay := int(d.get("delay", 20)) - 2
	if delay > 0:
		d["delay"] = delay
		return
	var mob := str(d.get("mob", "pig"))
	var near := 0
	# wiki Monster Spawner: no spawning while 6 or more of its mob are in the 9 x 9 x 9 volume around it
	var c := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	for o in world.entities.ents:
		if o.kind == "mob" and o.id == mob and absf(o.pos.x - c.x) < 4.5 and absf(o.pos.y + o.h * 0.5 - c.y) < 4.5 and absf(o.pos.z - c.z) < 4.5:
			near += 1
	var mdef := MobRegistry.get_def(mob)
	for i in 4:
		if near >= 6:
			break
		var q := Vector3(pos.x + (rng.randf() - rng.randf()) * 4.0 + 0.5, pos.y + rng.randi_range(-1, 1), pos.z + (rng.randf() - rng.randf()) * 4.0 + 0.5)
		if not _free(world, q):
			continue
		# wiki Monster Spawner: dark-spawning monsters need the usual darkness (a torch stops it), blazes and
		# silverfish a light level below 12
		if str(mdef.get("kind", "")) == "hostile":
			var ql: int = world.cm.get_light(int(floor(q.x)), int(floor(q.y)), int(floor(q.z)))
			if mob == "blaze" or mob == "silverfish":
				if MobAI.raw_light(world, ql) >= 12:
					continue
			elif not MobAI.dark_enough(world, rng, ql):
				continue
		var m = world.entities.spawn_mob(mob, q)
		if m != null:
			near += 1
			for k in 3:
				Particles.emit("smoke", q + Vector3(0, 0.5, 0), Vector3(rng.randf_range(-0.05, 0.05), 0.05, rng.randf_range(-0.05, 0.05)))
	d["delay"] = rng.randi_range(200, 799)   # wiki Monster Spawner: waits 200-799 ticks


static func _free(world, q: Vector3) -> bool:
	var b := Res.blocks
	var x := int(floor(q.x))
	var y := int(floor(q.y))
	var z := int(floor(q.z))
	var below: int = world.state_at(x, y - 1, z)
	if below <= 0 or (b.st_flags[below] & BlockRegistry.F_COLLIDE) == 0:
		return false
	for dy in 2:
		var s: int = world.state_at(x, y + dy, z)
		if s > 0 and (b.st_flags[s] & BlockRegistry.F_COLLIDE) != 0:
			return false
	return true


# ------------------------------------------------------------------ trial spawner

static func config(name: String) -> Dictionary:
	if _cfg_cache.has(name):
		return _cfg_cache[name]
	var j = Res.read_json("data/minecraft/trial_spawner/%s.json" % name.trim_prefix("minecraft:"))
	var cfg: Dictionary = j if j is Dictionary else {"spawn_potentials": [{"data": {"entity": {"id": "minecraft:zombie"}}, "weight": 1}]}
	_cfg_cache[name] = cfg
	return cfg


static func _set_state(world, pos: Vector3i, d: Dictionary, s: String) -> void:
	d["state"] = s
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	var b := Res.blocks
	if st > 0 and b.has_prop(st, "trial_spawner_state"):
		var ns := b.with_prop(st, "trial_spawner_state", TS_STATES.get(s, "inactive"))
		if ns != st:
			world.set_block(pos.x, pos.y, pos.z, ns, false)


static func _trial(world, pos: Vector3i, d: Dictionary, dist: float) -> void:
	var rng: RandomNumberGenerator = world.rng
	var p: Player = world.player
	_omen_check(world, pos, d, dist, p)
	var ominous := bool(d.get("is_ominous", false)) and str(d.get("ominous", "")) != ""
	var cfg := config(str(d.get("ominous", "")) if ominous else str(d.get("normal", "trial_chamber/melee/zombie/normal")))
	var state := str(d.get("state", "waiting"))
	match state:
		"waiting":
			# wiki Trial Spawner: a player within 14 blocks with line of sight to it; nothing on Peaceful
			var eye := p.eye_pos()
			var sc := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
			if dist <= 14.0 and not p.is_spectator() and not p.is_creative() and world.difficulty > 0 and _los(world, eye, sc, pos):
				d["players"] = 1 + Net.proxies().size()
				d["spawned"] = 0
				d["next"] = world.game_time
				_tracked[pos] = []
				_set_state(world, pos, d, "active")
				Audio.play("block.trial_spawner.detect_player", Vector3(pos), "Blocks")
		"active":
			var players := int(d.get("players", 1))
			var total := int(float(cfg.get("total_mobs", 6)) + float(cfg.get("total_mobs_added_per_player", 2)) * (players - 1))
			var sim := int(float(cfg.get("simultaneous_mobs", 2)) + float(cfg.get("simultaneous_mobs_added_per_player", 1)) * (players - 1))
			var live: Array = []
			for m in _tracked.get(pos, []):
				if m != null and not m.dead:
					live.append(m)
			_tracked[pos] = live
			if rng.randf() < 0.2:
				Particles.emit("flame", Vector3(pos) + Vector3(rng.randf(), 0.9, rng.randf()))
			if int(d.get("spawned", 0)) >= total and live.is_empty():
				d["eject"] = players
				d["next"] = world.game_time + 40
				_set_state(world, pos, d, "ejecting")
				return
			if int(d.get("spawned", 0)) < total and live.size() < sim and world.game_time >= int(d.get("next", 0)) and world.difficulty > 0:
				var mob := str(d.get("next_mob", "")) if str(d.get("next_mob", "")) != "" else next_mob(d, cfg, rng)
				var nm := next_mob(d, cfg, rng)
				if nm != str(d.get("next_mob", "")):
					d["next_mob"] = nm
					BERender.refresh(pos)
				var rngd := float(cfg.get("spawn_range", 4))
				for attempt in 8:
					var q := Vector3(pos.x + 0.5 + rng.randf_range(-rngd, rngd), pos.y + rng.randi_range(-1, 1), pos.z + 0.5 + rng.randf_range(-rngd, rngd))
					# wiki Trial Spawner: within a 4-block spherical radius, with line of sight to the spawner
					if not _free(world, q) or q.distance_to(Vector3(pos) + Vector3(0.5, 0.0, 0.5)) > rngd or not _los(world, q + Vector3(0, 0.5, 0), Vector3(pos) + Vector3(0.5, 0.5, 0.5), pos):
						continue
					var m2 = world.entities.spawn_mob(mob, q)
					if m2 != null:
						m2.persistent = true
						m2.target_player = true
						m2.data["trial"] = true
						equip_from_config(world, m2, cfg, mob)
						(_tracked[pos] as Array).append(m2)
						d["spawned"] = int(d.get("spawned", 0)) + 1
						Audio.play("block.trial_spawner.spawn_mob", q, "Blocks")
						for k in 4:
							Particles.emit("flame", q + Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3)))
					break
				d["next"] = world.game_time + int(cfg.get("ticks_between_spawn", 40))
			if ominous:
				_ominous_items(world, pos, d, cfg, dist)
			# (wiki Trial Spawner: once active it no longer needs players in range; its mobs don't despawn)
		"ejecting":
			if world.game_time < int(d.get("next", 0)):
				return
			if int(d.get("eject", 0)) <= 0:
				d["until"] = world.game_time + int(cfg.get("target_cooldown_length", 36000))
				_set_state(world, pos, d, "cooldown")
				return
			d["eject"] = int(d["eject"]) - 1
			d["next"] = world.game_time + 30   # wiki Trial Spawner: 30 ticks between reward ejections
			var tables: Array = cfg.get("loot_tables_to_eject", [{"data": "minecraft:spawners/trial_chamber/consumables", "weight": 1}, {"data": "minecraft:spawners/trial_chamber/key", "weight": 1}])
			var tot := 0
			for t in tables:
				tot += int(t.get("weight", 1))
			var k2 := rng.randi_range(0, maxi(tot - 1, 0))
			var pick := "spawners/trial_chamber/consumables"
			for t in tables:
				k2 -= int(t.get("weight", 1))
				if k2 < 0:
					pick = str(t.get("data", pick)).trim_prefix("minecraft:")
					break
			for s in Loot.roll(pick, {"rng": rng, "tool": ItemStack.new()}):
				var it = world.entities.spawn_item(Vector3(pos) + Vector3(0.5, 1.2, 0.5), s)
				if it != null:
					it.vel = Vector3(rng.randf_range(-0.1, 0.1), 0.3, rng.randf_range(-0.1, 0.1))
			Audio.play("block.trial_spawner.eject_item", Vector3(pos), "Blocks")
		"cooldown":
			if world.game_time >= int(d.get("until", 0)):
				# wiki Ominous Trial Spawner: after its 30-minute cooldown it turns back into a regular trial spawner
				if bool(d.get("is_ominous", false)):
					_set_ominous(world, pos, d, false)
				_set_state(world, pos, d, "waiting")


## wiki Trial Omen / Trial Spawner: a player with Bad Omen seen by a trial spawner (14 blocks) gets Trial Omen for 15
## minutes x the Bad Omen level (at least its remaining time); trial spawners within 15 blocks of a player with Trial
## Omen and in sight of them turn ominous - their mobs despawn, they become active at once (a cooldown from a normal
## trial is skipped) and use their ominous config (mobs, loot tables, ominous keys, equipment, item spawners).
static func _omen_check(world, pos: Vector3i, d: Dictionary, dist: float, p: Player) -> void:
	if p.dead or p.is_spectator() or p.is_creative() or dist > 15.0 or str(d.get("ominous", "")) == "":
		return
	var has_bad: bool = p.effects.has("bad_omen")
	if not has_bad and not p.effects.has("trial_omen"):
		return
	if bool(d.get("is_ominous", false)) and not has_bad:
		return
	if world.game_time % 10 != 0:
		return   # (line-of-sight checks every 10 ticks)
	var sc := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	if not _los(world, p.eye_pos(), sc, pos):
		return
	if has_bad and dist <= 14.0:
		var lvl := int(p.effects["bad_omen"].get("amp", 0)) + 1
		var cur := int(p.effects["trial_omen"].get("ticks", 0)) if p.effects.has("trial_omen") else 0
		p.effects.erase("bad_omen")
		p.effects.erase("trial_omen")
		p.add_effect("trial_omen", 0, maxi(cur, 18000 * lvl))
		Audio.play("event.mob_effect.trial_omen", p.pos, "Ambient", 0.8)
	if not p.effects.has("trial_omen") or bool(d.get("is_ominous", false)):
		return
	for m in _tracked.get(pos, []):
		if m != null and not m.dead:
			world.entities._remove(m)
	_tracked[pos] = []
	var was := str(d.get("state", "waiting"))
	_set_ominous(world, pos, d, true)
	d["players"] = 1 + Net.proxies().size()
	d["spawned"] = 0
	d["next"] = world.game_time
	d.erase("next_mob")
	if was != "ejecting":
		_set_state(world, pos, d, "active")
	Audio.play("block.trial_spawner.ominous_activate", sc, "Blocks", 1.0, rng_pitch(world))


static func rng_pitch(world) -> float:
	return world.rng.randf_range(0.8, 1.2)


static func _set_ominous(world, pos: Vector3i, d: Dictionary, on: bool) -> void:
	d["is_ominous"] = on
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	if st > 0 and Res.blocks.has_prop(st, "ominous"):
		var ns := Res.blocks.with_prop(st, "ominous", "true" if on else "false")
		if ns != st:
			world.set_block(pos.x, pos.y, pos.z, ns, false)
	BERender.refresh(pos)


## Line of sight between two points, ignoring the spawner block itself.
static func _los(world, a: Vector3, b: Vector3, own: Vector3i) -> bool:
	var dv := b - a
	var l := dv.length()
	if l < 0.01:
		return true
	var hit: Dictionary = VoxelRaycast.cast(a, dv / l, l, world.state_at, Res.blocks)
	return hit.is_empty() or hit.get("pos") == own


## wiki Spawn Egg / Trial Spawner: a spawn egg used on a (trial) spawner sets the mob it spawns.
static func set_spawner_mob(world, pos: Vector3i, kind: String, mob: String) -> void:
	if MobRegistry.get_def(mob).is_empty():
		return
	var d := BlockEntities.get_data(world, pos)
	if d.is_empty():
		d = {"id": kind}
	d["mob"] = mob
	if kind == "trial_spawner":
		d["next_mob"] = mob
		var st: int = world.state_at(pos.x, pos.y, pos.z)
		if st > 0 and Res.blocks.get_prop(st, "trial_spawner_state") == "inactive":
			_set_state(world, pos, d, "waiting")
	BlockEntities.set_data(world, pos, d)
	BERender.refresh(pos)


## The mob a trial spawner spawns next (shown inside it): a spawn-egg mob, else a roll of its spawn_potentials.
static func next_mob(d: Dictionary, cfg: Dictionary, rng: RandomNumberGenerator) -> String:
	if str(d.get("mob", "")) != "":
		return str(d["mob"])
	return _pick_mob(cfg, rng)


## Mob shown in a trial spawner (BERender): the one it spawns next.
static func display_mob(d: Dictionary) -> String:
	if str(d.get("next_mob", "")) != "":
		return str(d["next_mob"])
	if str(d.get("mob", "")) != "":
		return str(d["mob"])
	var pots: Array = config(str(d.get("normal", "trial_chamber/melee/zombie/normal"))).get("spawn_potentials", [])
	if pots.is_empty() or not (pots[0] is Dictionary):
		return ""
	var ent = (pots[0] as Dictionary).get("data", {}).get("entity", {})
	return str(ent.get("id", "")).trim_prefix("minecraft:") if ent is Dictionary else ""


static func _pick_mob(cfg: Dictionary, rng: RandomNumberGenerator) -> String:
	var pots: Array = cfg.get("spawn_potentials", [])
	var tot := 0.0
	for e in pots:
		tot += float(e.get("weight", 1))
	var r := rng.randf() * tot
	for e in pots:
		r -= float(e.get("weight", 1))
		if r <= 0.0:
			var ent = e.get("data", {}).get("entity", {})
			return str(ent.get("id", "minecraft:zombie")).trim_prefix("minecraft:") if ent is Dictionary else "zombie"
	return "zombie"


# ------------------------------------------------------------------ ominous equipment / item spawners

## The spawn potential's equipment (26.3 trial_spawner configs: ominous melee / ranged mobs roll
## equipment/trial_chamber_melee / _ranged): its items go to their slots (Java Mob.equip - armour by piece, anything
## else into the main hand, the first item per slot); slot_drop_chances 0 = never dropped.
static func equip_from_config(world, m, cfg: Dictionary, mob: String) -> void:
	var eq = null
	for pot in cfg.get("spawn_potentials", []):
		var dat = pot.get("data", {}) if pot is Dictionary else {}
		var ent = dat.get("entity", {}) if dat is Dictionary else {}
		if ent is Dictionary and str(ent.get("id", "")).trim_prefix("minecraft:") == mob:
			eq = dat.get("equipment")
			break
	if not (eq is Dictionary):
		return
	var table = eq.get("loot_table", "")
	var ctx := {"rng": world.rng, "tool": ItemStack.new(), "entity_id": mob}
	var stacks: Array = []
	if table is Dictionary:
		stacks = Loot.roll_table(table, ctx)
	elif str(table) != "":
		stacks = Loot.roll(str(table).trim_prefix("minecraft:"), ctx)
	equip_stacks(m, stacks)
	var dc = eq.get("slot_drop_chances", null)
	if (dc is float or dc is int) and float(dc) <= 0.0:
		m.data["no_equip_drop"] = true


static func equip_stacks(m, stacks: Array) -> void:
	var armor: Array = (m.data.get("armor", ["", "", "", ""]) as Array).duplicate()
	while armor.size() < 4:
		armor.append("")
	var used := {}
	for s in stacks:
		var st: ItemStack = s
		if st == null or st.is_empty():
			continue
		var nm := st.name()
		var slot := -1
		if nm.ends_with("_helmet"):
			slot = 3
		elif nm.ends_with("_chestplate"):
			slot = 2
		elif nm.ends_with("_leggings"):
			slot = 1
		elif nm.ends_with("_boots"):
			slot = 0
		if slot >= 0:
			if not used.has(slot):
				used[slot] = true
				armor[slot] = st.to_dict()   # (dicts keep the trims / enchantments: ArmorRender.slots_of_dicts)
		elif not used.has(-1):
			used[-1] = true
			m.data["held"] = nm
			m.data["held_stack"] = st.to_dict()   # (enchantments: HeldItems.ench)
	m.data["armor"] = armor


## wiki Ominous Item Spawner: while an ominous trial spawner detects a player within its activation range, every 8
## seconds it spawns an ominous item spawner above that player or one of its own mobs: a raycast from the feet to a
## random height 2-5 blocks up; the hit block (else the end of the line) is used and the spawner sits at the bottom
## centre of the block below it, unless that block has a collision box. The item (one of a roll of the config's
## items_to_drop_when_ominous) is shown for 3-6 seconds.
static func _ominous_items(world, pos: Vector3i, d: Dictionary, cfg: Dictionary, dist: float) -> void:
	var gt := int(world.game_time)
	if gt < int(d.get("oi_next", 0)):
		return
	var p: Player = world.player
	if dist > float(cfg.get("player_detection_range", 14)) or p.dead or p.is_spectator() or p.is_creative():
		return
	d["oi_next"] = gt + 160
	var rng: RandomNumberGenerator = world.rng
	var cands: Array = [p]
	for m in _tracked.get(pos, []):
		if m != null and not m.dead:
			cands.append(m)
	var t = cands[rng.randi_range(0, cands.size() - 1)]
	var feet: Vector3 = t.pos
	var h := rng.randf_range(2.0, 5.0)
	var hit: Dictionary = VoxelRaycast.cast(feet, Vector3.UP, h, world.state_at, Res.blocks)
	var hb: Vector3i = hit["pos"] if not hit.is_empty() else Vector3i((feet + Vector3(0, h, 0)).floor())
	var at := Vector3i(hb.x, hb.y - 1, hb.z)
	var st: int = world.state_at(at.x, at.y, at.z)
	if st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0:
		return
	var table := str(cfg.get("items_to_drop_when_ominous", "minecraft:spawners/trial_chamber/items_to_drop_when_ominous")).trim_prefix("minecraft:")
	var items: Array = Loot.roll(table, {"rng": rng, "tool": ItemStack.new()})
	if items.is_empty():
		return
	spawn_ominous_item(world.entities, Vector3(at.x + 0.5, at.y, at.z + 0.5), items[rng.randi_range(0, items.size() - 1)], rng.randi_range(60, 120))


## The ominous item spawner entity (kind "ominous_item", drawn like a dropped item; saved with its chunk -
## EntityManager._ser - and sent to LAN clients as a puppet). sound: the spawn_item_begin sound (not on reloads).
static func spawn_ominous_item(em, at: Vector3, s: ItemStack, ticks: int, sound: bool = true):
	var e := EntityManager.Ent.new()
	e.kind = "ominous_item"
	e.id = "ominous_item_spawner"
	e.pos = at
	e.prev = at
	e.stack = s
	e.data["spawn_after"] = ticks
	if em.has_method("_item_node"):
		e.node = em._item_node(s)
		em.add_child(e.node)
	em.ents.append(e)
	if sound:
		Audio.play("block.trial_spawner.spawn_item_begin", at, "Blocks", 1.0, em.rng.randf_range(0.8, 1.2))
	return e


## wiki Ominous Item Spawner: after its display time the item is dispensed downward - projectiles (arrows, fire
## charges, wind charges, splash / lingering potions) are shot as entities, anything else is dropped. Sounds
## spawn_item_begin / about_to_spawn_item / spawn_item (when "prepares" plays is not on the wiki: 36 ticks before,
## Java OminousItemSpawner). Launch speed not on the wiki: the dispenser's 1.1 (potions x1.25, Java DispenseConfig).
static func tick_ominous_item(em, e) -> void:
	var total := int(e.data.get("spawn_after", 60))
	if e.age % 5 == 0:
		Particles.emit("smoke", e.pos + Vector3(em.rng.randf_range(-0.3, 0.3), em.rng.randf_range(0.0, 0.5), em.rng.randf_range(-0.3, 0.3)), Vector3(0, 0.02, 0), Color(0.35, 0.8, 0.9))
	if e.age == total - 36:
		Audio.play("block.trial_spawner.about_to_spawn_item", e.pos, "Blocks")
	if e.age < total:
		return
	var s: ItemStack = e.stack
	var nm := s.name() if s != null else ""
	var down := Vector3(em.rng.randfn(0, 0.0075), -1.0, em.rng.randfn(0, 0.0075)).normalized()
	var n0: int = em.ents.size()
	match nm:
		"arrow", "tipped_arrow", "spectral_arrow":
			em.spawn_projectile("arrow", e.pos, down * 1.1, null)
			if em.ents.size() > n0:
				var a = em.ents[em.ents.size() - 1]
				var pot := Potions.potion_of(s)
				if pot != "":
					a.data["potion"] = pot
				if nm == "spectral_arrow":
					a.data["ammo"] = "spectral_arrow"
		"fire_charge":
			em.spawn_projectile("small_fireball", e.pos, down * 1.1, null)
		"wind_charge", "snowball", "egg":
			em.spawn_projectile(nm, e.pos, down * 1.1, null)
		"splash_potion", "lingering_potion":
			em.spawn_projectile(nm, e.pos, down * 1.375, null)
			if em.ents.size() > n0:
				em.ents[em.ents.size() - 1].stack = s.copy()
		"":
			pass
		_:
			em.spawn_item(e.pos, s)
	Audio.play("block.trial_spawner.spawn_item", e.pos, "Blocks", 1.0, em.rng.randf_range(0.8, 1.2))
	em._remove(e)


# ------------------------------------------------------------------ vault

static func _vault(world, pos: Vector3i, d: Dictionary, dist: float) -> void:
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	var b := Res.blocks
	if st > 0 and b.has_prop(st, "vault_state"):
		var want := "active" if dist <= 4.0 else "inactive"
		if int(d.get("eject_left", 0)) > 0:
			want = "ejecting"
		if b.get_prop(st, "vault_state") != want:
			world.set_block(pos.x, pos.y, pos.z, b.with_prop(st, "vault_state", want), false)
	var left: Array = d.get("pending", [])
	if not left.is_empty() and world.game_time >= int(d.get("next", 0)):
		var s := ItemStack.from_dict(left.pop_front())
		var it = world.entities.spawn_item(Vector3(pos) + Vector3(0.5, 1.1, 0.5), s)
		if it != null:
			it.vel = Vector3(world.rng.randf_range(-0.05, 0.05), 0.25, world.rng.randf_range(-0.05, 0.05))
		Audio.play("block.vault.eject_item", Vector3(pos), "Blocks")
		d["pending"] = left
		d["eject_left"] = left.size()
		d["next"] = world.game_time + 20


static func use_vault(world, pos: Vector3i, pl: Player) -> bool:
	var d := BlockEntities.get_data(world, pos)
	if d.is_empty():
		d = {"id": "vault"}
	var st: int = world.state_at(pos.x, pos.y, pos.z)
	var ominous: bool = st > 0 and Res.blocks.has_prop(st, "ominous") and Res.blocks.get_prop(st, "ominous") == "true"
	var held := pl.inventory.held()
	var key := "ominous_trial_key" if ominous else "trial_key"
	var who := Taming.owner_name()
	var rewarded: Array = d.get("rewarded", [])
	if held.is_empty() or held.name() != key:
		return false
	if rewarded.has(who) or not (d.get("pending", []) as Array).is_empty():
		Audio.play("block.vault.insert_item_fail", Vector3(pos), "Blocks")
		return true
	if not pl.is_creative():
		pl.inventory.consume_held()
	var cfg: Dictionary = d.get("config", {}) if d.get("config") is Dictionary else {}
	var table := str(cfg.get("loot_table", "minecraft:chests/trial_chambers/reward" + ("_ominous" if ominous else ""))).trim_prefix("minecraft:")
	var pend: Array = []
	for s in Loot.roll(table, {"rng": world.rng, "tool": ItemStack.new()}):
		pend.append((s as ItemStack).to_dict())
	rewarded.append(who)
	d["id"] = "vault"
	d["rewarded"] = rewarded
	d["pending"] = pend
	d["eject_left"] = pend.size()
	d["next"] = world.game_time + 20
	BlockEntities.set_data(world, pos, d)
	Audio.play("block.vault.insert_item", Vector3(pos), "Blocks")
	world.inv_changed()
	return true


# ------------------------------------------------------------------ breeze wind charge

static func breeze_tick(world, e, p: Player) -> void:
	# called every 2 ticks (Raids.tick): 20 calls = 40 ticks
	var cd := int(e.data.get("wind_cd", 20)) - 1
	if cd > 0:
		e.data["wind_cd"] = cd
		return
	e.data["wind_cd"] = 20
	if p.dead or p.is_creative() or p.is_spectator() or e.pos.distance_to(p.pos) > 16.0:
		return
	var from: Vector3 = e.pos + Vector3(0, e.h * 0.6, 0)
	var dv: Vector3 = p.pos + Vector3(0, 0.9, 0) - from
	world.entities.spawn_projectile("wind_charge", from, dv.normalized() * 0.7, e)
	Audio.play("entity.breeze.shoot", e.pos, "Hostile")


## Java AbstractWindCharge.explode: no block damage, knockback burst (radius 1.2).
static func wind_burst(world, at: Vector3) -> void:
	Audio.play("entity.wind_charge.wind_burst", at, "Neutral")
	for i in 6:
		Particles.emit("smoke", at + Vector3(world.rng.randf_range(-0.6, 0.6), world.rng.randf_range(-0.3, 0.6), world.rng.randf_range(-0.6, 0.6)), Vector3.ZERO, Color(0.85, 0.9, 1.0))
	var p: Player = world.player
	var d := p.pos.distance_to(at)
	if d < 2.5:
		var push: Vector3 = (p.pos + Vector3(0, 0.9, 0) - at).normalized() * (1.0 - d / 2.5) * 1.1
		p.vel += push + Vector3(0, 0.5, 0)
		p.hurt(1.0, "mob")
	for o in world.entities.ents:
		if o.kind == "mob" and o.pos.distance_to(at) < 2.5 and o.id != "breeze":
			o.vel += (o.pos - at).normalized() * 0.8 + Vector3(0, 0.4, 0)
