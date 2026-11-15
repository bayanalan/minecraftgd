## Raids and illager behaviour (Java Raid, PatrolSpawner, Evoker spell goals, Witch.performRangedAttack):
## - Patrols: every 12000-13199 ticks, from day 5, in daylight, 1 in 5 chance: a captain pillager plus
##   ceil(local difficulty) more, 24-47 blocks from a player on X and Z, outside villages. Captains drop an ominous
##   bottle (amplifier 0-4) when killed by a player.
## - Ominous bottle -> Bad Omen (100 min). Bad Omen in a village (is_village: a point of interest - bed, job site
##   block, bell - in the 3 x 3 x 3 sub-chunks around the player) -> Raid Omen (600 ticks) -> raid centred on the
##   average position of the POIs within 64 blocks (village_center); the centre moves to the nearest village sub-chunk
##   in the 5 x 5 x 5 around it when its own area stops being a village (defeat when none is left). There is no POI
##   claiming here: POI blocks count while a villager lives within 64 blocks of the spot.
##   Waves: Easy 3 / Normal 5 / Hard 7, +1 bonus wave when the omen level > 1.
##   Wave composition (Java Raid.RaiderType, by wave 1-7): vindicator {0,2,0,1,4,2,5}, evoker {0,0,0,1,1,0,2},
##   pillager {4,3,3,4,4,4,2}, witch {0,0,0,3,0,0,1}, ravager {0,0,1,0,1,0,2} (Easy/Normal reductions skipped).
##   Raid bar = remaining raider health; 300-tick pause between waves; victory -> Hero of the Village (48000
##   ticks); defeat when every villager near the centre died or after 48000 ticks.
## - Raiders walk to and attack villagers when no player is close. Evokers (within 12 blocks): 3 vexes every 340 ticks
##   (max 8 nearby) and cast fangs (ring of 5 + 8 within 3 blocks, otherwise a line of 16) with a 100-tick
##   cooldown. Witches throw splash potions (harming / poison / slowness / weakness) every 60 ticks.
## Each wave gets bonus raiders (bonus_raiders) and a captain wearing the ominous banner (MobBehaviors.render_captain).
## Villagers in the raid area ring the bell before the first wave, hide in houses and do not work (Villagers.raid_at).
## APPROXIMATE: no raider celebration, fangs hit instantly.
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
		if is_raider(e) and not MobBehaviors.HUNTS.has(e.id) and e.pos.distance_to(p.pos) > 16.0:   # (vindicators / ravagers: MobBehaviors.mob_target)
			_hunt_villagers(world, e)
		elif e.id == "iron_golem":
			MobAI.iron_golem(world, e)


# ------------------------------------------------------------------ patrols

static func _patrols(world) -> void:
	_next_patrol -= 1
	if _next_patrol > 0:
		return
	_next_patrol = 12000 + world.rng.randi_range(0, 1199)   # wiki Patrol: every 10-11 minutes (13200 excluded)
	if world.dimension != "overworld" or world.difficulty == 0 or int(world.game_time / 24000) < 5:
		return
	if not world.gamerule("doPatrolSpawning", true) or not world.gamerule("doMobSpawning", true) or world.player.is_spectator():
		return
	if world.day_time % 24000 > 12000 or world.rng.randi_range(0, 4) != 0:
		return
	spawn_patrol(world)


## wiki Patrol: the captain 24-47 blocks from the player along each of X and Z, then ceil(local difficulty) more
## pillagers, each within a 4-block square of the previous one; block light 8 or less, not in mushroom fields; nothing
## spawns if the captain can't.
static func spawn_patrol(world) -> int:
	var p: Player = world.player
	var rng: RandomNumberGenerator = world.rng
	var x := int(floor(p.pos.x)) + (24 + rng.randi_range(0, 23)) * (1 if rng.randi_range(0, 1) == 0 else -1)
	var z := int(floor(p.pos.z)) + (24 + rng.randi_range(0, 23)) * (1 if rng.randi_range(0, 1) == 0 else -1)
	if is_village(world, Vector3(x, p.pos.y, z), 2):
		return 0   # (Java PatrolSpawner: not within 2 sub-chunks of a village)
	var n := int(ceil([0.0, 0.75, 1.5, 2.25][world.difficulty]))
	var made := 0
	for i in n + 1:
		if i > 0:
			x += rng.randi_range(-4, 4)
			z += rng.randi_range(-4, 4)
		var q := _surface(world, x, z)
		var ok: bool = q.y > -9000 and (world.cm.get_light(int(q.x), int(q.y), int(q.z)) & 15) <= 8
		if ok:
			var ch: Chunk = world.cm.get_chunk(x >> 4, z >> 4)
			var bi := ch.biome_at(x & 15, int(q.y), z & 15) if ch != null else -1
			ok = bi < 0 or not str(world.biomes.names[bi]).ends_with("mushroom_fields")
		if not ok:
			if i == 0:
				return 0
			continue
		var m = world.entities.spawn_mob("pillager", q)
		if m != null:
			m.persistent = true
			m.data["patrol"] = true
			if i == 0:
				m.data["captain"] = true
			made += 1
		elif i == 0:
			return 0
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
	# wiki Raid: Raids cannot start in the Nether
	if p.effects.has("bad_omen") and world.difficulty > 0 and not (world.level.get("raid") is Dictionary) and str(world.get("dimension")) != "the_nether":
		if is_village(world, p.pos, 1):
			var amp := int(p.effects["bad_omen"].get("amp", 0))
			p.effects.erase("bad_omen")
			p.add_effect("raid_omen", amp, 600)   # wiki Raid Omen: 30 s, the raid starts when it expires
			world.level["raid_pending"] = {"center": [floori(p.pos.x), floori(p.pos.y), floori(p.pos.z)], "omen": amp + 1, "at": world.game_time + 600}
			Audio.play("event.mob_effect.raid_omen", p.pos, "Ambient", 0.8)
	var pend = world.level.get("raid_pending")
	if pend is Dictionary and world.game_time >= int(pend["at"]):
		world.level.erase("raid_pending")
		# wiki Raid: the centre is the average position of the claimed POIs within 64 blocks of the player when the raid
		# triggers (the omen position when the player is no longer in a village)
		var at := p.pos if is_village(world, p.pos, 1) else Vector3(int(pend["center"][0]), int(pend["center"][1]), int(pend["center"][2]))
		var c := village_center(world, at, 64.0)
		if c != Vector3.INF:
			start_raid(world, Vector3i(c.floor()), int(pend["omen"]))


# ------------------------------------------------------------------ villages (points of interest)

## wiki Villager: job site blocks (+ all cauldrons), beds (the head) and bells are the village points of interest.
const POI_BLOCKS := {"bell": true, "composter": true, "smoker": true, "blast_furnace": true, "cartography_table": true, "brewing_stand": true,
	"barrel": true, "fletching_table": true, "cauldron": true, "water_cauldron": true, "lava_cauldron": true, "powder_snow_cauldron": true,
	"lectern": true, "stonecutter": true, "loom": true, "smithing_table": true, "grindstone": true}
static var _poi_cache: Dictionary = {}


static func is_poi(st: int) -> bool:
	var v = _poi_cache.get(st)
	if v == null:
		var nm := Res.blocks.name_of(st)
		v = POI_BLOCKS.has(nm) or (nm.ends_with("_bed") and Res.blocks.get_prop(st, "part") == "head")
		_poi_cache[st] = v
	return v


static func _section_has_poi(sec) -> bool:
	for st in sec.pal:
		if st > 0 and is_poi(st):
			return true
	return false


## Java ServerLevel.isCloseToVillage(pos, r): a POI in the (2r + 1)^3 sub-chunks around the spot (palette checks only),
## with a villager within 64 blocks standing in for POI claiming.
static func is_village(world, at: Vector3, r: int) -> bool:
	var cm = world.get("cm")
	if cm == null or not cm.has_method("get_chunk"):
		return false
	var sx := floori(at.x) >> 4
	var sz := floori(at.z) >> 4
	var sy := (floori(at.y) - Coords.MIN_Y) >> 4
	var found := false
	for cx in range(sx - r, sx + r + 1):
		for cz in range(sz - r, sz + r + 1):
			var ch: Chunk = cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			for s in range(maxi(0, sy - r), mini(Coords.SECTIONS - 1, sy + r) + 1):
				if _section_has_poi(ch.sections[s]):
					found = true
					break
			if found:
				break
		if found:
			break
	if not found:
		return false
	for v in MobBehaviors.near_list(world.entities, "villager"):
		if not v.dead and v.pos.distance_squared_to(at) <= 4096.0:
			return true
	return false


## Average position of the POIs within radius of at (sections without a POI in their palette are skipped; the
## others are searched with the packed arrays' native find). INF when there is none.
static func village_center(world, at: Vector3, radius: float) -> Vector3:
	var cm = world.get("cm")
	if cm == null or not cm.has_method("get_chunk"):
		return Vector3.INF
	var r := ceili(radius)
	var sum := Vector3.ZERO
	var n := 0
	for cx in range((floori(at.x) - r) >> 4, ((floori(at.x) + r) >> 4) + 1):
		for cz in range((floori(at.z) - r) >> 4, ((floori(at.z) + r) >> 4) + 1):
			var ch: Chunk = cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			for s in range(maxi(0, (floori(at.y) - r - Coords.MIN_Y) >> 4), mini(Coords.SECTIONS - 1, (floori(at.y) + r - Coords.MIN_Y) >> 4) + 1):
				var sec: Chunk.Section = ch.sections[s]
				if sec.pal.size() < 2 or not _section_has_poi(sec):
					continue
				var base := Vector3i(cx * 16, Coords.MIN_Y + s * 16, cz * 16)
				for pi in sec.pal.size():
					if sec.pal[pi] <= 0 or not is_poi(sec.pal[pi]):
						continue
					var i: int = sec.wide.find(pi) if sec.wide.size() > 0 else sec.idx.find(pi)
					while i >= 0:
						var q := Vector3(base.x + (i & 15) + 0.5, base.y + (i >> 8) + 0.5, base.z + ((i >> 4) & 15) + 0.5)
						if q.distance_to(at) <= radius:
							sum += q
							n += 1
						i = sec.wide.find(pi, i + 1) if sec.wide.size() > 0 else sec.idx.find(pi, i + 1)
	return sum / float(n) if n > 0 else Vector3.INF


## wiki Raid: when the sub-chunks around the raid centre no longer count as a village, the centre moves to the centre
## of the nearest sub-chunk in the surrounding 5 x 5 x 5 that still does; none -> INF.
static func move_center(world, c: Vector3) -> Vector3:
	var best := Vector3.INF
	var bd := INF
	var cs := Vector3i(floori(c.x) >> 4, (floori(c.y) - Coords.MIN_Y) >> 4, floori(c.z) >> 4)
	for dx in range(-2, 3):
		for dy in range(-2, 3):
			for dz in range(-2, 3):
				var q := Vector3((cs.x + dx) * 16 + 8, Coords.MIN_Y + (cs.y + dy) * 16 + 8, (cs.z + dz) * 16 + 8)
				var d := q.distance_squared_to(c)
				if d < bd and is_village(world, q, 1):
					bd = d
					best = q
	return best


static func start_raid(world, center: Vector3i, omen: int) -> void:
	var waves: int = [3, 3, 5, 7][clampi(world.difficulty, 0, 3)]
	var base := waves
	if omen > 1:
		waves += 1   # wiki Raid: Raid Omen II+ adds one wave as strong as the final one
	world.level["raid"] = {"center": [center.x, center.y, center.z], "omen": omen, "waves": waves, "base_waves": base, "wave": 0, "state": "pause",
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
	if str(rd["state"]) != "over" and world.game_time % 20 == 0 and not is_village(world, center, 1):
		var nc := move_center(world, center)
		if nc == Vector3.INF:
			if int(rd["wave"]) > 0:
				_end(world, rd, false)   # wiki Raid: no village sub-chunk left around the centre - defeat
			else:
				world.level.erase("raid")
				if world.level.get("bossbars") is Dictionary:
					(world.level["bossbars"] as Dictionary).erase("raid")
			return
		rd["center"] = [floori(nc.x), floori(nc.y), floori(nc.z)]
		center = Vector3(rd["center"][0], rd["center"][1], rd["center"][2])
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
		if bool(e.data.get("raid", false)) and e.pos.distance_to(center) <= 112.0:   # wiki Raid: farther raiders leave
			alive += 1
			hp += e.hp
		elif e.id == "villager" and e.pos.distance_to(center) < 64.0:
			villagers += 1
	if world.game_time - int(rd["started"]) > 48000 or (villagers == 0 and int(rd["wave"]) > 0):
		_end(world, rd, false)
		return
	if str(rd["state"]) == "active":
		_bar(world, "Raid", int(hp), int(maxf(1.0, float(rd["total_hp"]))), world.player.pos.distance_to(center) <= 96.0)
		if alive == 0:
			if int(rd["wave"]) >= int(rd["waves"]):
				_end(world, rd, true)
			else:
				rd["state"] = "pause"
				rd["timer"] = 300
		return
	# pause between waves: the bar fills up as the next wave approaches (Java)
	rd["timer"] = int(rd["timer"]) - 1
	_bar(world, "Raid", 300 - int(rd["timer"]), 300, world.player.pos.distance_to(center) <= 96.0)   # wiki Raid: the bar shows within 96 blocks
	if int(rd["timer"]) <= 0:
		_spawn_wave(world, rd, center)


static func _spawn_wave(world, rd: Dictionary, center: Vector3) -> void:
	var w := int(rd["wave"]) + 1
	rd["wave"] = w
	var idx := mini(w, int(rd.get("base_waves", 7)))
	var ang: float = world.rng.randf() * TAU
	var sx := int(floor(center.x + cos(ang) * 32.0))
	var sz := int(floor(center.z + sin(ang) * 32.0))
	var total := 0.0
	var has_captain := false
	var bonus_wave: bool = w > int(rd.get("base_waves", 7))
	for id in WAVES:
		var n: int = WAVES[id][idx] + bonus_raiders(world, str(id), w, bonus_wave)
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
				# each wave's first vindicator / evoker / pillager leads it as the raid captain (ominous banner)
				if not has_captain and id in ["vindicator", "evoker", "pillager"]:
					has_captain = true
					m.data["captain"] = true
	rd["total_hp"] = total
	rd["state"] = "active"
	Audio.play("event.raid.horn", world.player.pos + Vector3(cos(ang), 0, sin(ang)) * 16.0, "Hostile", 4.0)


## Extra raiders on top of the wave table (wiki Raid): pillagers / vindicators Easy 25 % one more, Normal 50 % one more,
## Hard 0-2 more ("50 % chance of extras"); witches 50 % one more on waves 3+ except 4 (not Easy); ravagers 50 % one
## more in the bonus wave (not Easy).
static func bonus_raiders(world, id: String, wave: int, bonus_wave: bool) -> int:
	var rng: RandomNumberGenerator = world.rng
	var d := int(world.difficulty)
	var i := 0
	match id:
		"pillager", "vindicator":
			i = rng.randi_range(0, 1) if d <= 1 else (1 if d == 2 else 2)
		"witch":
			if d <= 1 or wave <= 2 or wave == 4:
				return 0
			i = 1
		"ravager":
			i = 1 if d > 1 and bonus_wave else 0
	return rng.randi_range(0, i) if i > 0 else 0


static func _end(world, rd: Dictionary, victory: bool) -> void:
	rd["state"] = "over"
	rd["timer"] = 100
	rd["victory"] = victory   # (villagers in the raid area cheer meanwhile: Villagers._raid_goal)
	_bar(world, "Raid - " + ("Victory" if victory else "Defeat"), 1 if victory else 0, 1, true)
	if victory:
		var p: Player = world.player
		# wiki Hero of the Village: 40 minutes, the raid's Bad Omen level, for players who killed a raider
		if bool(rd.get("killed", false)):
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
		em._damage(best, float(e.def.get("attack", 4.0)), e)   # wiki Difficulty: mobs hitting mobs deal Normal damage
		e.attack_cd = 20


## wiki Evoker: attacks targets within 12 blocks; summons 3 vexes (fewer than 8 within 16 blocks; vex cooldown 340
## ticks, then 5 s before another spell) or casts fangs (fang cooldown 100 ticks, then 2 s before another spell).
static func _evoker(world, e, p: Player) -> void:
	# wiki Evoker: spell particles for two seconds before the vexes appear (the evoker does not flee while casting)
	var cast := int(e.rt.get("cast", 0))
	if cast > 0:
		cast -= 2
		e.rt["cast"] = cast
		for k in 2:
			Particles.emit("effect", e.pos + Vector3(world.rng.randf_range(-0.6, 0.6), e.h * 0.9, world.rng.randf_range(-0.6, 0.6)), Vector3(0, 0.05, 0), Color(0.7, 0.7, 0.8))
		if cast <= 0:
			e.rt.erase("cast")
			for i in 3:
				var v = world.entities.spawn_mob("vex", e.pos + Vector3(world.rng.randf_range(-2, 2), 1.0, world.rng.randf_range(-2, 2)))
				if v != null:
					v.target_player = true
					v.data["life"] = 20 * (30 + world.rng.randi_range(0, 89))   # wiki Vex: damage starts after 30-119 s
					v.data["bound"] = [e.pos.x, e.pos.y, e.pos.z]   # wiki Vex: idles in a 15 x 11 x 15 box around this spot
			Audio.play("entity.evoker.cast_spell", e.pos, "Hostile")
		return
	var d: float = e.pos.distance_to(p.pos)
	if d > 12.0 or p.dead or p.is_creative() or p.is_spectator():
		return
	var sc := int(e.data.get("spell_cd", 0)) - 2
	var cd := int(e.data.get("vex_cd", 100)) - 2
	var fc := int(e.data.get("fang_cd", 60)) - 2
	if sc <= 0:
		var vexes := 0
		if cd <= 0:
			for o in world.entities.ents:
				if o.kind == "mob" and o.id == "vex" and o.pos.distance_to(e.pos) < 16.0:
					vexes += 1
		if cd <= 0 and vexes < 8:
			e.rt["cast"] = 40
			Audio.play("entity.evoker.prepare_summon", e.pos, "Hostile")
			cd = 340
			sc = 100
		elif fc <= 0:
			_fangs(world, e, p, d)
			fc = 100
			sc = 40
	e.data["spell_cd"] = sc
	e.data["vex_cd"] = cd
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
			p.hurt(MobAI.diff_dmg(world.difficulty, 6.0), "magic")   # wiki Evoker: fangs 4 / 6 / 9
			Audio.play("entity.evoker_fangs.attack", q, "Hostile")


static func _witch(world, e, p: Player) -> void:
	if int(e.rt.get("drink", 0)) > 0:
		return   # wiki Witch: no attacks while drinking (MobBehaviors._witch_tick)
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
