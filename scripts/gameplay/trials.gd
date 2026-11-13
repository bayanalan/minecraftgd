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
## APPROXIMATE: no line-of-sight checks, no ominous trial spawners (Bad Omen variant), no spawner mob preview.
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
	for o in world.entities.ents:
		if o.kind == "mob" and o.id == mob and absf(o.pos.x - pos.x) < 9.0 and absf(o.pos.y - pos.y) < 5.0 and absf(o.pos.z - pos.z) < 9.0:
			near += 1
	for i in 4:
		if near >= 6:
			break
		var q := Vector3(pos.x + (rng.randf() - rng.randf()) * 4.0 + 0.5, pos.y + rng.randi_range(-1, 1), pos.z + (rng.randf() - rng.randf()) * 4.0 + 0.5)
		if not _free(world, q):
			continue
		var m = world.entities.spawn_mob(mob, q)
		if m != null:
			near += 1
			for k in 3:
				Particles.emit("smoke", q + Vector3(0, 0.5, 0), Vector3(rng.randf_range(-0.05, 0.05), 0.05, rng.randf_range(-0.05, 0.05)))
	d["delay"] = rng.randi_range(200, 800)


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
	var cfg := config(str(d.get("normal", "trial_chamber/melee/zombie/normal")))
	var state := str(d.get("state", "waiting"))
	var p: Player = world.player
	match state:
		"waiting":
			if dist <= 14.0 and not p.is_spectator() and not p.is_creative():
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
			if int(d.get("spawned", 0)) < total and live.size() < sim and world.game_time >= int(d.get("next", 0)):
				var mob := _pick_mob(cfg, rng)
				var rngd := float(cfg.get("spawn_range", 4))
				for attempt in 8:
					var q := Vector3(pos.x + 0.5 + rng.randf_range(-rngd, rngd), pos.y + rng.randi_range(-1, 1), pos.z + 0.5 + rng.randf_range(-rngd, rngd))
					if not _free(world, q):
						continue
					var m2 = world.entities.spawn_mob(mob, q)
					if m2 != null:
						m2.persistent = true
						m2.target_player = true
						m2.data["trial"] = true
						(_tracked[pos] as Array).append(m2)
						d["spawned"] = int(d.get("spawned", 0)) + 1
						Audio.play("block.trial_spawner.spawn_mob", q, "Blocks")
						for k in 4:
							Particles.emit("flame", q + Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3)))
					break
				d["next"] = world.game_time + int(cfg.get("ticks_between_spawn", 40))
			# players left: reset (Java: the spawner goes back to waiting when nobody is in range)
			if dist > 40.0:
				for m3 in _tracked.get(pos, []):
					if m3 != null and not m3.dead:
						world.entities._remove(m3)
				_tracked[pos] = []
				_set_state(world, pos, d, "waiting")
		"ejecting":
			if world.game_time < int(d.get("next", 0)):
				return
			if int(d.get("eject", 0)) <= 0:
				d["until"] = world.game_time + int(cfg.get("target_cooldown_length", 36000))
				_set_state(world, pos, d, "cooldown")
				return
			d["eject"] = int(d["eject"]) - 1
			d["next"] = world.game_time + 20
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
				_set_state(world, pos, d, "waiting")


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
