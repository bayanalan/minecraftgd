## Raids and illager behaviour (Java Raid, PatrolSpawner, Evoker spell goals, Witch.performRangedAttack):
## - Patrols: every 12000 + rand(1200) ticks, from day 5, in daylight, 1 in 5 chance: a captain pillager plus
##   ceil(local difficulty) + 1 members 24-48 blocks from a player, outside villages. Captains drop an ominous
##   bottle (amplifier 0-4) when killed by a player.
## - Ominous bottle -> Bad Omen (100 min). Bad Omen in a village (bell within 48 blocks) -> Raid Omen (300 ticks)
##   -> raid centred on that bell. Waves: Easy 3 / Normal 5 / Hard 7, +1 bonus wave when the omen level > 1.
##   Wave composition (Java Raid.RaiderType, by wave 1-7): vindicator {0,2,0,1,4,2,5}, evoker {0,0,0,1,1,0,2},
##   pillager {4,3,3,4,4,4,2}, witch {0,0,0,3,0,0,1}, ravager {0,0,1,0,1,0,2} (Easy/Normal reductions skipped).
##   Raid bar = remaining raider health; 300-tick pause between waves; victory -> Hero of the Village (48000
##   ticks); defeat when every villager near the centre died or after 48000 ticks.
## - Raiders walk to and attack villagers when no player is close. Evokers: summon 3 vexes every 340 ticks
##   (max 8 nearby) and cast fangs (ring of 5 + 8 within 3 blocks, otherwise a line of 16) with a 100-tick
##   cooldown. Witches throw splash potions (harming / poison / slowness / weakness) every 60 ticks.
## APPROXIMATE: no captain banners, no raider celebration/omen effects on villagers, fangs hit instantly.
class_name Raids
extends RefCounted

const WAVES := {"vindicator": [0, 0, 2, 0, 1, 4, 2, 5], "evoker": [0, 0, 0, 0, 1, 1, 0, 2], "pillager": [0, 4, 3, 3, 4, 4, 4, 2],
	"witch": [0, 0, 0, 0, 3, 0, 0, 1], "ravager": [0, 0, 0, 1, 0, 1, 0, 2]}
const RAIDERS := ["pillager", "vindicator", "evoker", "witch", "ravager", "illusioner"]

static var _next_patrol := 12000


static func is_raider(e) -> bool:
	return e.kind == "mob" and e.id in RAIDERS


static func tick(world) -> void:
	var em = world.entities
	var p: Player = world.player
	_patrols(world)
	_omen(world)
	_raid(world)
	if world.game_time % 2 != 0:
		return
	for e in em.ents.duplicate():
		if e.dead or e.kind != "mob" or e.noai:   # Java NoAI: no goals, no spells
			continue
		if e.id == "vex" and e.data.has("life"):
			e.data["life"] = int(e.data["life"]) - 2
			if int(e.data["life"]) <= 0 and world.game_time % 20 == 0:
				em._damage(e, 1.0, null)   # Java Vex: limited life, then 1 damage per second
		if e.id == "breeze":
			Trials.breeze_tick(world, e, p)
		if e.id == "evoker":
			_evoker(world, e, p)
		elif e.id == "witch":
			_witch(world, e, p)
		if is_raider(e) and e.pos.distance_to(p.pos) > 16.0:
			_hunt_villagers(world, e)


# ------------------------------------------------------------------ patrols

static func _patrols(world) -> void:
	_next_patrol -= 1
	if _next_patrol > 0:
		return
	_next_patrol = 12000 + world.rng.randi_range(0, 1200)
	if world.dimension != "overworld" or world.difficulty == 0 or int(world.game_time / 24000) < 5:
		return
	if world.day_time > 12000 or world.rng.randi_range(0, 4) != 0:
		return
	spawn_patrol(world)


static func spawn_patrol(world) -> int:
	var p: Player = world.player
	var ang: float = world.rng.randf() * TAU
	var dist: float = world.rng.randf_range(24.0, 48.0)
	var x := int(floor(p.pos.x + cos(ang) * dist))
	var z := int(floor(p.pos.z + sin(ang) * dist))
	if find_bell(world, Vector3(x, p.pos.y, z), 48) != Vector3i(0, -9999, 0):
		return 0
	var n := int(ceil([0.0, 0.75, 1.5, 2.25][world.difficulty])) + 1
	var made := 0
	for i in n + 1:
		var q := _surface(world, x + world.rng.randi_range(-3, 3), z + world.rng.randi_range(-3, 3))
		if q.y < -9000:
			continue
		var m = world.entities.spawn_mob("pillager", q)
		if m != null:
			m.persistent = true
			m.data["patrol"] = true
			if i == 0:
				m.data["captain"] = true
			made += 1
	return made


static func _surface(world, x: int, z: int) -> Vector3:
	var ch: Chunk = world.cm.get_chunk(x >> 4, z >> 4)
	if ch == null or ch.state < Chunk.DECORATED or ch.heightmap.is_empty():
		return Vector3(0, -9999, 0)
	return Vector3(x + 0.5, ch.heightmap[(x & 15) + (z & 15) * 16], z + 0.5)


## Nearest bell within r blocks (chunk palettes are checked first, so only sections containing a bell are scanned).
static func find_bell(world, at: Vector3, r: int) -> Vector3i:
	var b := Res.blocks
	var bell := b.block_id("bell")
	var best := Vector3i(0, -9999, 0)
	var bd := INF
	if bell < 0:
		return best
	for cx in range((int(at.x) - r) >> 4, ((int(at.x) + r) >> 4) + 1):
		for cz in range((int(at.z) - r) >> 4, ((int(at.z) + r) >> 4) + 1):
			var ch: Chunk = world.cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			for s in Coords.SECTIONS:
				var sec: Chunk.Section = ch.sections[s]
				var has := false
				for st in sec.pal:
					if st > 0 and b.st_block[st] == bell:
						has = true
						break
				if not has:
					continue
				var y0 := Coords.MIN_Y + s * 16
				for y in 16:
					for z in 16:
						for x in 16:
							var st2 := ch.get_block(x, y0 + y, z)
							if st2 > 0 and b.st_block[st2] == bell:
								var q := Vector3i(cx * 16 + x, y0 + y, cz * 16 + z)
								var d := Vector3(q).distance_to(at)
								if d < bd and d <= r:
									bd = d
									best = q
	return best


# ------------------------------------------------------------------ omen -> raid

static func _omen(world) -> void:
	var p: Player = world.player
	if world.game_time % 20 != 0 or p.dead:
		return
	if p.effects.has("bad_omen") and world.difficulty > 0 and not (world.level.get("raid") is Dictionary):
		var bell := find_bell(world, p.pos, 48)
		if bell.y > -9000:
			var amp := int(p.effects["bad_omen"].get("amp", 0))
			p.effects.erase("bad_omen")
			p.add_effect("raid_omen", amp, 300)
			world.level["raid_pending"] = {"center": [bell.x, bell.y, bell.z], "omen": amp + 1, "at": world.game_time + 300}
			Audio.play("event.mob_effect.raid_omen", p.pos, "Ambient", 0.8)
	var pend = world.level.get("raid_pending")
	if pend is Dictionary and world.game_time >= int(pend["at"]):
		world.level.erase("raid_pending")
		start_raid(world, Vector3i(int(pend["center"][0]), int(pend["center"][1]), int(pend["center"][2])), int(pend["omen"]))


static func start_raid(world, center: Vector3i, omen: int) -> void:
	var waves: int = [3, 3, 5, 7][clampi(world.difficulty, 0, 3)]
	if omen > 1:
		waves += 1
	world.level["raid"] = {"center": [center.x, center.y, center.z], "omen": omen, "waves": waves, "wave": 0, "state": "pause",
		"timer": 300, "started": world.game_time, "total_hp": 1.0}
	_bar(world, "Raid", 0, 100, true)
	Audio.play("event.raid.horn", Vector3(center), "Hostile", 4.0)


static func _bar(world, name: String, value: int, mx: int, visible: bool) -> void:
	if not (world.level.get("bossbars") is Dictionary):
		world.level["bossbars"] = {}
	world.level["bossbars"]["raid"] = {"name": name, "value": value, "max": mx, "color": "red", "visible": visible}


static func _raid(world) -> void:
	var r = world.level.get("raid")
	if not (r is Dictionary):
		return
	var rd: Dictionary = r
	var center := Vector3(rd["center"][0], rd["center"][1], rd["center"][2])
	var em = world.entities
	if str(rd["state"]) == "over":
		rd["timer"] = int(rd["timer"]) - 1
		if int(rd["timer"]) <= 0:
			world.level.erase("raid")
			(world.level["bossbars"] as Dictionary).erase("raid")
		return
	var alive := 0
	var hp := 0.0
	var villagers := 0
	for e in em.ents:
		if e.dead or e.kind != "mob":
			continue
		if bool(e.data.get("raid", false)) and e.pos.distance_to(center) < 160.0:
			alive += 1
			hp += e.hp
		elif e.id == "villager" and e.pos.distance_to(center) < 64.0:
			villagers += 1
	if world.game_time - int(rd["started"]) > 48000 or (villagers == 0 and int(rd["wave"]) > 0):
		_end(world, rd, false)
		return
	if str(rd["state"]) == "active":
		_bar(world, "Raid", int(hp), int(maxf(1.0, float(rd["total_hp"]))), true)
		if alive == 0:
			if int(rd["wave"]) >= int(rd["waves"]):
				_end(world, rd, true)
			else:
				rd["state"] = "pause"
				rd["timer"] = 300
		return
	# pause between waves: the bar fills up as the next wave approaches (Java)
	rd["timer"] = int(rd["timer"]) - 1
	_bar(world, "Raid", 300 - int(rd["timer"]), 300, true)
	if int(rd["timer"]) <= 0:
		_spawn_wave(world, rd, center)


static func _spawn_wave(world, rd: Dictionary, center: Vector3) -> void:
	var w := int(rd["wave"]) + 1
	rd["wave"] = w
	var idx := mini(w, 7)
	var ang: float = world.rng.randf() * TAU
	var sx := int(floor(center.x + cos(ang) * 32.0))
	var sz := int(floor(center.z + sin(ang) * 32.0))
	var total := 0.0
	for id in WAVES:
		var n: int = WAVES[id][idx]
		for i in n:
			var q := _surface(world, sx + world.rng.randi_range(-4, 4), sz + world.rng.randi_range(-4, 4))
			if q.y < -9000:
				q = center + Vector3(cos(ang) * 20.0, 1.0, sin(ang) * 20.0)
			var m = world.entities.spawn_mob(id, q)
			if m != null:
				m.persistent = true
				m.data["raid"] = true
				m.target_player = true
				total += m.hp
	if w == 1 or w == int(rd["waves"]):
		var leader = world.entities.spawn_mob("pillager", _surface(world, sx, sz) if _surface(world, sx, sz).y > -9000 else center + Vector3(0, 1, 0))
		if leader != null:
			leader.persistent = true
			leader.data["raid"] = true
			leader.data["captain"] = true
			total += leader.hp
	rd["total_hp"] = total
	rd["state"] = "active"
	Audio.play("event.raid.horn", world.player.pos + Vector3(cos(ang), 0, sin(ang)) * 16.0, "Hostile", 4.0)


static func _end(world, rd: Dictionary, victory: bool) -> void:
	rd["state"] = "over"
	rd["timer"] = 100
	_bar(world, "Raid - " + ("Victory" if victory else "Defeat"), 1 if victory else 0, 1, true)
	if victory:
		var p: Player = world.player
		if p.pos.distance_to(Vector3(rd["center"][0], rd["center"][1], rd["center"][2])) < 96.0:
			p.add_effect("hero_of_the_village", int(rd["omen"]) - 1, 48000)
		world.hud.chat_message("Raid - Victory")
		if world.advancements != null:
			world.advancements.trigger("hero_of_the_village", {})
	else:
		world.hud.chat_message("Raid - Defeat")


# ------------------------------------------------------------------ raider behaviour

static func _hunt_villagers(world, e) -> void:
	var em = world.entities
	var best = null
	var bd := 32.0
	for v in em.ents:
		if v.kind == "mob" and not v.dead and (v.id == "villager" or v.id == "iron_golem") and v.pos.distance_to(e.pos) < bd:
			bd = v.pos.distance_to(e.pos)
			best = v
	if best == null:
		return
	e.has_target = true
	e.target_pos = best.pos
	e.ai_timer = 40
	if bd < e.w * 0.5 + best.w * 0.5 + 1.0 and e.attack_cd <= 0 and not e.def.get("ranged", false):
		em._damage(best, float(e.def.get("attack", 4.0)) * [0.0, 0.5, 1.0, 1.5][world.difficulty], e)
		e.attack_cd = 20


static func _evoker(world, e, p: Player) -> void:
	var d: float = e.pos.distance_to(p.pos)
	if d > 16.0 or p.dead or p.is_creative() or p.is_spectator():
		return
	var cd := int(e.data.get("vex_cd", 100))
	cd -= 2
	if cd <= 0:
		var vexes := 0
		for o in world.entities.ents:
			if o.kind == "mob" and o.id == "vex" and o.pos.distance_to(e.pos) < 16.0:
				vexes += 1
		if vexes < 8:
			for i in 3:
				var v = world.entities.spawn_mob("vex", e.pos + Vector3(world.rng.randf_range(-2, 2), 1.0, world.rng.randf_range(-2, 2)))
				if v != null:
					v.target_player = true
					v.data["life"] = 20 * (30 + world.rng.randi_range(0, 89))
			Audio.play("entity.evoker.prepare_summon", e.pos, "Hostile")
		cd = 340
	e.data["vex_cd"] = cd
	var fc := int(e.data.get("fang_cd", 60)) - 2
	if fc <= 0:
		_fangs(world, e, p, d)
		fc = 100
	e.data["fang_cd"] = fc


static func _fangs(world, e, p: Player, d: float) -> void:
	var spots: Array = []
	var ang := atan2(p.pos.z - e.pos.z, p.pos.x - e.pos.x)
	if d < 3.0:
		for i in 5:
			var a := ang + i * PI * 0.4
			spots.append(e.pos + Vector3(cos(a) * 1.5, 0, sin(a) * 1.5))
		for i in 8:
			var a2 := ang + i * PI * 2.0 / 8.0 + PI * 2.0 / 5.0
			spots.append(e.pos + Vector3(cos(a2) * 2.5, 0, sin(a2) * 2.5))
	else:
		for i in 16:
			var dd := 1.25 * (i + 1)
			spots.append(e.pos + Vector3(cos(ang) * dd, 0, sin(ang) * dd))
	Audio.play("entity.evoker.prepare_attack", e.pos, "Hostile")
	for q in spots:
		Particles.emit("crit", q + Vector3(0, 0.3, 0), Vector3(0, 0.15, 0), Color(0.6, 0.6, 0.65), 2)
		if Vector2(q.x - p.pos.x, q.z - p.pos.z).length() < 0.8 and absf(q.y - p.pos.y) < 2.0:
			p.hurt(6.0, "magic")
			Audio.play("entity.evoker_fangs.attack", q, "Hostile")


static func _witch(world, e, p: Player) -> void:
	var d: float = e.pos.distance_to(p.pos)
	var cd := int(e.data.get("throw_cd", 0)) - 2
	if cd > 0:
		e.data["throw_cd"] = cd
		return
	if d > 10.0 or p.dead or p.is_creative() or p.is_spectator():
		e.data["throw_cd"] = 0
		return
	var pot := "harming"
	if d >= 8.0 and not p.effects.has("slowness"):
		pot = "slowness"
	elif p.health >= 8.0 and not p.effects.has("poison"):
		pot = "poison"
	elif d <= 3.0 and not p.effects.has("weakness") and world.rng.randf() < 0.25:
		pot = "weakness"
	var from: Vector3 = e.pos + Vector3(0, e.h * 0.8, 0)
	var dv: Vector3 = p.pos + Vector3(0, 1.1, 0) - from
	dv.y += Vector2(dv.x, dv.z).length() * 0.2
	var em = world.entities
	var before: int = em.ents.size()
	em.spawn_projectile("splash_potion", from, dv.normalized() * 0.75, e)
	if em.ents.size() > before:
		em.ents[em.ents.size() - 1].stack = Potions.make("splash_potion", pot)
	Audio.play("entity.witch.throw", e.pos, "Hostile")
	e.data["throw_cd"] = 60
