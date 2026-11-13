## Sculk (Java VibrationSystem, SculkSensorBlock, SculkShriekerBlockEntity, WardenSpawnTracker, Warden):
## - Vibrations: block place/break, player steps (not sneaking, on ground, every 10 ticks of movement), item drops,
##   projectile landings, explosions, eating, container opening. Wool between source and listener absorbs them
##   (straight-line check). Sneaking players make no step vibrations.
## - Sculk sensor: listens within 8 blocks (calibrated 16): phase active for 30 ticks with redstone power
##   max(1, 15 - floor(15 * distance / 8)) (Java signal strength by distance), then cooldown 10 ticks, then inactive.
## - Sculk shrieker (can_summon from ancient cities): a player-caused vibration within 8 blocks makes it shriek
##   (shrieking 90 ticks) when the player's warning cooldown (200 ticks) has passed: warning level +1 (0-4, decays
##   by 1 every 12000 ticks without shrieks), Darkness for 12 s within 40 blocks; level 4 summons a Warden within
##   5 blocks of the shrieker if none is within 48 blocks.
## - Warden: anger from vibrations (+35 per event at the source, +10 near), targets the source above 80 anger,
##   melee 30 (Normal) every 18 ticks, sonic boom (10, ignores armor) when the target is 3-15 blocks away with a
##   40-tick cooldown, digs away after 1200 ticks without vibrations.
## APPROXIMATE: no vibration frequencies / comparator output by event type, no item sculk catalyst spreading.
class_name Sculk
extends RefCounted

static var _step_t := 0
static var _last_pos := Vector3.ZERO
static var _pending: Dictionary = {}   # Vector3i -> [phase, ticks_left]
## Active sensor output. Kept here because our block states only carry model-visible properties and the 26.3
## sculk_sensor blockstate JSON has no power variants.
static var power: Dictionary = {}     # Vector3i -> 0..15


static func power_at(p: Vector3i) -> int:
	return int(power.get(p, 0))


static func _listeners(world, at: Vector3, r: int) -> Array:
	var b := Res.blocks
	var ids := {}
	for nm in ["sculk_sensor", "calibrated_sculk_sensor", "sculk_shrieker"]:
		var bid := b.block_id(nm)
		if bid >= 0:
			ids[bid] = nm
	var out: Array = []
	var c := Vector3i(at.floor())
	for cx in range((c.x - r) >> 4, ((c.x + r) >> 4) + 1):
		for cz in range((c.z - r) >> 4, ((c.z + r) >> 4) + 1):
			var ch: Chunk = world.cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			var s0 := clampi((c.y - r - Coords.MIN_Y) >> 4, 0, Coords.SECTIONS - 1)
			var s1 := clampi((c.y + r - Coords.MIN_Y) >> 4, 0, Coords.SECTIONS - 1)
			for s in range(s0, s1 + 1):
				var sec: Chunk.Section = ch.sections[s]
				var has := false
				for st in sec.pal:
					if st > 0 and ids.has(b.st_block[st]):
						has = true
						break
				if not has:
					continue
				var y0 := Coords.MIN_Y + s * 16
				for y in 16:
					for z in 16:
						for x in 16:
							var st2 := ch.get_block(x, y0 + y, z)
							if st2 > 0 and ids.has(b.st_block[st2]):
								var q := Vector3i(cx * 16 + x, y0 + y, cz * 16 + z)
								if Vector3(q).distance_to(at) <= r:
									out.append([q, ids[b.st_block[st2]], st2])
	return out


static func _occluded(world, a: Vector3, b2: Vector3) -> bool:
	var d := b2 - a
	var n := int(ceil(d.length() * 2.0))
	var b := Res.blocks
	for i in range(1, n):
		var q := a + d * (float(i) / n)
		var st: int = world.state_at(int(floor(q.x)), int(floor(q.y)), int(floor(q.z)))
		if st > 0 and b.name_of(st).ends_with("_wool"):
			return true
	return false


## A game event at `at` (player_caused: the local player made it).
static func vibrate(world, at: Vector3, player_caused: bool) -> void:
	if world.dimension == "the_end":
		return
	var b := Res.blocks
	for l in _listeners(world, at, 16):
		var q: Vector3i = l[0]
		var nm: String = l[1]
		var st: int = l[2]
		var src := Vector3(q) + Vector3(0.5, 0.5, 0.5)
		var dist := src.distance_to(at)
		var rng := 16.0 if nm == "calibrated_sculk_sensor" else 8.0
		if dist > rng or _occluded(world, at, src):
			continue
		if nm.ends_with("sculk_sensor"):
			if b.get_prop(st, "sculk_sensor_phase") != "inactive":
				continue
			var sig := maxi(1, 15 - int(floor(15.0 * dist / rng)))
			power[q] = sig
			world.set_block(q.x, q.y, q.z, b.with_prop(st, "sculk_sensor_phase", "active"), false)
			Redstone.on_changed(world, q)
			_pending[q] = ["active", 30]
			Audio.play("block.sculk_sensor.clicking", src, "Blocks", 0.6)
			Particles.emit("effect", src + Vector3(0, 0.5, 0), Vector3(0, 0.05, 0), Color(0.2, 0.8, 0.85), 3)
		elif nm == "sculk_shrieker" and player_caused:
			_shriek(world, q, st)
	# wardens hear everything within 16 blocks
	for e in world.entities.ents:
		if e.kind == "mob" and e.id == "warden" and not e.dead and e.pos.distance_to(at) <= 16.0:
			var anger := int(e.data.get("anger", 0)) + (35 if player_caused else 10)
			e.data["anger"] = mini(150, anger)
			e.data["heard"] = [at.x, at.y, at.z]
			e.data["quiet"] = 0
			if anger >= 80 and player_caused:
				e.target_player = true


static func _shriek(world, q: Vector3i, st: int) -> void:
	var b := Res.blocks
	var p: Player = world.player
	if b.get_prop(st, "shrieking") == "true" or world.game_time < int(world.level.get("warden_warn_cd", 0)):
		return
	world.level["warden_warn_cd"] = world.game_time + 200
	world.set_block(q.x, q.y, q.z, b.with_prop(st, "shrieking", "true"), false)
	_pending[q] = ["shriek", 90]
	Audio.play("block.sculk_shrieker.shriek", Vector3(q), "Blocks", 2.0)
	var can_summon := b.get_prop(st, "can_summon") == "true"
	if not can_summon or world.difficulty == 0:
		return
	var level := mini(4, int(world.level.get("warden_warning", 0)) + 1)
	world.level["warden_warning"] = level
	world.level["warden_warn_decay"] = world.game_time + 12000
	if p.pos.distance_to(Vector3(q)) < 40.0:
		p.add_effect("darkness", 0, 260)
	if level >= 4:
		for e in world.entities.ents:
			if e.kind == "mob" and e.id == "warden" and e.pos.distance_to(Vector3(q)) < 48.0:
				return
		for i in 20:
			var sp := Vector3(q) + Vector3(world.rng.randi_range(-5, 5) + 0.5, 0, world.rng.randi_range(-5, 5) + 0.5)
			for dy in range(-5, 6):
				var y := int(sp.y) + dy
				var below: int = world.state_at(int(sp.x), y - 1, int(sp.z))
				if below > 0 and (b.st_flags[below] & BlockRegistry.F_COLLIDE) != 0 and world.state_at(int(sp.x), y, int(sp.z)) == 0 and world.state_at(int(sp.x), y + 1, int(sp.z)) == 0 and world.state_at(int(sp.x), y + 2, int(sp.z)) == 0:
					var w = world.entities.spawn_mob("warden", Vector3(sp.x, y, sp.z))
					if w != null:
						w.persistent = true
						w.data["anger"] = 80
						w.data["quiet"] = 0
						w.data["heard"] = [p.pos.x, p.pos.y, p.pos.z]
						Audio.play("entity.warden.emerge", w.pos, "Hostile", 2.0)
						world.level["warden_warning"] = 0
						world.hud.chat_message("A Warden emerges...")
					return


static func tick(world) -> void:
	var p: Player = world.player
	var b := Res.blocks
	# pending sensor/shrieker phase changes
	for q in _pending.keys():
		var e: Array = _pending[q]
		e[1] = int(e[1]) - 1
		if int(e[1]) > 0:
			continue
		var st: int = world.state_at(q.x, q.y, q.z)
		_pending.erase(q)
		if st <= 0:
			continue
		match str(e[0]):
			"active":
				power.erase(q)
				world.set_block(q.x, q.y, q.z, b.with_prop(st, "sculk_sensor_phase", "cooldown"), false)
				Redstone.on_changed(world, q)
				_pending[q] = ["cooldown", 10]
			"cooldown":
				world.set_block(q.x, q.y, q.z, b.with_prop(st, "sculk_sensor_phase", "inactive"), false)
			"shriek":
				if b.has_prop(st, "shrieking"):
					world.set_block(q.x, q.y, q.z, b.with_prop(st, "shrieking", "false"), false)
	# warning decay
	if not world.level.has("warden_warn_decay"):
		world.level["warden_warn_decay"] = world.game_time + 12000
	if int(world.level.get("warden_warning", 0)) > 0 and world.game_time >= int(world.level.get("warden_warn_decay", 0)):
		world.level["warden_warning"] = int(world.level["warden_warning"]) - 1
		world.level["warden_warn_decay"] = world.game_time + 12000
	# player steps
	if p.on_ground and not p.sneaking and not p.is_spectator() and Vector2(p.pos.x - _last_pos.x, p.pos.z - _last_pos.z).length() > 0.05:
		_step_t += 1
		if _step_t >= 10:
			_step_t = 0
			vibrate(world, p.pos, true)
	_last_pos = p.pos
	if world.game_time % 2 == 0:
		for e in world.entities.ents.duplicate():
			if e.kind == "mob" and e.id == "warden" and not e.dead:
				_warden(world, e, p)


static func _warden(world, e, p: Player) -> void:
	e.data["quiet"] = int(e.data.get("quiet", 0)) + 2
	if int(e.data["quiet"]) > 1200:
		Audio.play("entity.warden.dig", e.pos, "Hostile", 2.0)
		world.entities._remove(e)
		return
	if world.game_time % 40 == 0:
		e.data["anger"] = maxi(0, int(e.data.get("anger", 0)) - 1)
		Audio.play("entity.warden.heartbeat", e.pos, "Hostile", 0.8)
	var d: float = e.pos.distance_to(p.pos)
	var angry := int(e.data.get("anger", 0)) >= 80 and not p.dead and not p.is_creative() and not p.is_spectator()
	e.target_player = angry and d < 40.0
	if not e.target_player:
		var h = e.data.get("heard")
		if h is Array:
			e.has_target = true
			e.target_pos = Vector3(h[0], h[1], h[2])
			e.ai_timer = 40
		return
	var cd := int(e.data.get("boom_cd", 0)) - 2
	if cd <= 0 and d > 3.0 and d < 15.0:
		# Java SonicBoom: 10 damage ignoring armor, knockback
		p.hurt(10.0, "sonic_boom", true)
		var kb: Vector3 = (p.pos - e.pos).normalized()
		p.vel += Vector3(kb.x * 2.5, 0.5, kb.z * 2.5)
		Audio.play("entity.warden.sonic_boom", e.pos, "Hostile", 3.0)
		var from: Vector3 = e.pos + Vector3(0, 1.6, 0)
		var to: Vector3 = p.pos + Vector3(0, 1.0, 0)
		for i in int(d):
			Particles.emit("explosion", from.lerp(to, float(i) / d), Vector3.ZERO, Color(0.45, 0.85, 0.95))
		cd = 40
	e.data["boom_cd"] = cd
