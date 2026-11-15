## MobAI — special behaviour archetypes on top of EntityManager's generic walker AI (source D, Java goals recalled):
## flyers (Ghast float + fireball goal, Blaze height control + 3-shot burst), hoppers (Slime/Magma Cube jump
## control + contact damage + size), stationary Shulkers (homing bullets), neutral targeting (Enderman stare,
## Zombified Piglin group anger, Piglins pacified by gold armour).
## Contract: wants_target(em, e, p, dist) -> bool; tick_special(...) performs AI + physics for one tick.
class_name MobAI
extends RefCounted


## wiki Difficulty: mob damage to players is scaled - Peaceful 0, Easy min(D, 0.5D + 1), Normal D, Hard 1.5D (mobs
## hitting other mobs always deal the Normal damage).
static func diff_dmg(difficulty: int, d: float) -> float:
	match difficulty:
		0:
			return 0.0
		1:
			return minf(d, d * 0.5 + 1.0)
		3:
			return d * 1.5
	return d


## Hostile target acquisition range (wiki: Zombie / Husk / Drowned pursue from 35 blocks, Pillager sees 32, Ravager
## targets within 32, Evoker attacks within 12; the other walkers see 16).
const SIGHT := {"zombie": 35.0, "husk": 35.0, "drowned": 35.0, "pillager": 32.0, "ravager": 32.0, "evoker": 12.0}


static func sight(id: String) -> float:
	return float(SIGHT.get(id, 16.0))


## wiki Difficulty#Regional difficulty (Java): Peaceful 0; time factor (day time - 72000) / 5760000 between day 3 and
## day 63 (0.25 after); chunk factor inhabited / 3600000 (1 after 50 hours) x 0.75 on Easy / Normal, plus
## min(moon brightness x 0.25, time factor), x 0.5 on Easy; (0.75 + time + chunk) x 1 / 2 / 3 by difficulty.
const MOON_BRIGHTNESS := {"full_moon": 1.0, "waning_gibbous": 0.75, "third_quarter": 0.5, "waning_crescent": 0.25, "new_moon": 0.0,
	"waxing_crescent": 0.25, "first_quarter": 0.5, "waxing_gibbous": 0.75}


static func regional_difficulty(world, at: Vector3) -> float:
	var d := int(world.difficulty)
	if d <= 0:
		return 0.0
	var t := float(world.day_time)
	var tf := 0.0
	if t > 1512000.0:
		tf = 0.25
	elif t >= 72000.0:
		tf = (t - 72000.0) / 5760000.0
	var inh := 0.0
	var cm = world.get("cm")
	if cm != null and cm.has_method("get_chunk"):
		var ch = cm.get_chunk(floori(at.x) >> 4, floori(at.z) >> 4)
		if ch != null and "inhabited" in ch:
			inh = float(ch.inhabited)
	var cf := 1.0 if inh > 3600000.0 else inh / 3600000.0
	if d <= 2:
		cf *= 0.75
	var ss = world.get("sky_state")
	var mb := float(MOON_BRIGHTNESS.get(str(ss.moon_phase), 1.0)) if ss != null and "moon_phase" in ss else 1.0
	cf += minf(mb * 0.25, tf)
	if d == 1:
		cf *= 0.5
	return (0.75 + tf + cf) * float(d)


## wiki Difficulty: clamped regional difficulty - 0 below 2, 1 above 4, (regional - 2) / 2 between.
static func clamped_regional(world, at: Vector3) -> float:
	var r := regional_difficulty(world, at)
	if r < 2.0:
		return 0.0
	if r > 4.0:
		return 1.0
	return (r - 2.0) / 2.0


## Java Level.isBrightOutside: the Overworld sky darkening below 4 (day, no thunderstorm).
static func bright_outside(world) -> bool:
	if str(world.get("dimension")) != "overworld":
		return false
	return not world.has_method("sky_darken_level") or int(world.sky_darken_level()) < 4


## Spawn category of a mob type, read from the biomes' natural_mob_spawns lists (monster, creature, ambient, axolotls,
## underground_water_creature, water_creature, water_ambient); types no biome lists are monsters if hostile, else misc.
static var _cat: Dictionary = {}
static var _cat_world := 0


static func spawn_category(world, id: String) -> String:
	var wid: int = world.get_instance_id() if world != null else 0
	if _cat_world != wid and world != null and world.biomes != null and not world.biomes.data.is_empty():
		_cat_world = wid
		_cat.clear()
		for d in world.biomes.data:
			if not (d is Dictionary):
				continue
			var attrs = d.get("attributes", {})
			var ns = attrs.get("minecraft:gameplay/natural_mob_spawns", null) if attrs is Dictionary else null
			var by_cat = null
			if ns is Dictionary:
				var arg = ns.get("argument", ns)
				if arg is Dictionary:
					by_cat = arg.get("spawns_by_category", null)
			if by_cat == null:
				by_cat = d.get("spawners", {})
			if not (by_cat is Dictionary):
				continue
			for c in by_cat:
				var lst = by_cat[c]
				if lst is Array:
					for s in lst:
						if s is Dictionary:
							var t := str(s.get("type", "")).trim_prefix("minecraft:")
							if not _cat.has(t):
								_cat[t] = str(c)
	if _cat.has(id):
		return str(_cat[id])
	return "monster" if str(MobRegistry.get_def(id).get("kind", "")) == "hostile" else "misc"


## Java Level.getMaxLocalRawBrightness: max(sky light - sky darkening, block light) of a packed light value.
static func raw_light(world, light: int) -> int:
	var dk: int = int(world.sky_darken_level()) if world.has_method("sky_darken_level") else 0
	return maxi((light >> 4) - dk, light & 15)


## Java LightTexture.getBrightness / Entity.getLightLevelDependentMagicValue: raw light 0..15 -> 0..1 (ambient 0).
static func brightness(raw: int) -> float:
	var f := raw / 15.0
	return f / (4.0 - 3.0 * f)


## Java Monster.isDarkEnoughToSpawn (wiki Mob spawning): raw sky light <= rand(0..31), block light <= the dimension's
## monster_spawn_block_light_limit (Overworld 0), max(sky - darkening, block) (thunder: darkening 10) <= the
## dimension's monster_spawn_light_level (Overworld 0..7).
static func dark_enough(world, rng: RandomNumberGenerator, light: int) -> bool:
	var dt: Dictionary = world.dim_type
	var sky := light >> 4
	var blk := light & 15
	if sky > rng.randi_range(0, 31) or blk > int(dt.get("monster_spawn_block_light_limit", 0)):
		return false
	var dk: int = int(world.sky_darken_level()) if world.has_method("sky_darken_level") else 0
	if bool(world.get("thundering")):
		dk = 10
	var lvl_test = dt.get("monster_spawn_light_level", 7)
	var lvl := rng.randi_range(int(lvl_test.get("min_inclusive", 0)), int(lvl_test.get("max_inclusive", 7))) if lvl_test is Dictionary else int(lvl_test)
	return maxi(sky - dk, blk) <= lvl


## wiki Mob spawning: per-category mob caps (Java)
const CAPS := {"monster": 70, "creature": 10, "ambient": 15, "axolotls": 5, "underground_water_creature": 5, "water_creature": 5, "water_ambient": 20}


## Neutral anger that wears off (wiki: Zombified Piglin forgives after 20-55 s, Piglin stays hostile for 30 s, Bee
## anger 20-39 s inclusive).
static func anger(e: EntityManager.Ent, rng: RandomNumberGenerator) -> void:
	e.angry = true
	if e.id == "zombified_piglin":
		e.rt["anger_t"] = rng.randi_range(400, 1100)
	elif e.id == "piglin":
		e.rt["anger_t"] = 600
	elif e.id == "bee":
		e.rt["anger_t"] = rng.randi_range(400, 780)


static func wears_gold(p: Player) -> bool:
	for i in range(Inventory.ARMOR0, Inventory.ARMOR0 + 4):
		var s: ItemStack = p.inventory.get_slot(i)
		if not s.is_empty() and s.name().begins_with("golden_"):
			return true
	return false


## Java EnderMan.isLookingAtMe: view vector within 0.025/d of the eye direction, line of sight, no carved pumpkin.
static func player_stares(em: EntityManager, e: EntityManager.Ent, p: Player) -> bool:
	var helmet: ItemStack = p.inventory.get_slot(Inventory.ARMOR0 + 3)
	if not helmet.is_empty() and helmet.name() == "carved_pumpkin":
		return false
	var eye := p.eye_pos()
	var to := Vector3(e.pos.x, e.pos.y + e.h * 0.9, e.pos.z) - eye
	var d := to.length()
	if d > 64.0 or d < 0.01:
		return false
	var dot := p.look_dir().normalized().dot(to / d)
	if dot <= 1.0 - 0.025 / d:
		return false
	return VoxelRaycast.cast(eye, to / d, d, em.world.state_at, Res.blocks).is_empty()


static func wants_target(em: EntityManager, e: EntityManager.Ent, p: Player, dist: float) -> bool:
	var def: Dictionary = e.def
	if e.angry and e.rt.has("anger_t"):
		e.rt["anger_t"] = int(e.rt["anger_t"]) - 1
		if int(e.rt["anger_t"]) <= 0:
			e.rt.erase("anger_t")
			e.angry = false
			e.target_player = false
	if str(def.get("kind", "")) != "hostile":
		return e.angry   # neutral animals (polar bears, llamas, bees, wolves, nautiluses): only when provoked
	if e.baby_age < 0 and e.id == "piglin":
		return false   # wiki Piglin: babies are passive
	# wiki Drowned: during the day (no thunderstorm) they ignore players who are not in the water unless provoked
	if e.id == "drowned" and not e.angry and not p.in_water and bright_outside(em.world):
		return false
	if def.get("neutral", false):
		if not e.angry and def.get("teleports", false):
			# wiki Enderman: provoked by a player looking at its eyes for 5 game ticks
			var st := int(e.rt.get("stare", 0)) + 1 if player_stares(em, e, p) else 0
			e.rt["stare"] = st
			if st >= 5:
				e.angry = true
				Audio.play("entity.enderman.stare", e.pos, "Hostile")
		return e.angry
	if def.get("gold_peace", false) and not e.angry and wears_gold(p):
		return false
	return true


static func _has_los(em: EntityManager, from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var l := d.length()
	if l < 0.01:
		return true
	return VoxelRaycast.cast(from, d / l, l, em.world.state_at, Res.blocks).is_empty()


## wiki Iron Golem (Java IronGolem goals): attacks hostile mobs (Enemy, not creepers) within its follow range 16;
## melee every 20 ticks within reach, damage f / 2 + rand(0 .. f - 1) with attack 15 (7.5-21.5), throws the target up
## 0.4 (entity.iron_golem.attack); attackAnimationTick 10 swings both arms. Runs every 2 ticks (Raids.tick).
static func iron_golem(world, e) -> void:
	var em = world.entities
	if int(e.rt.get("atk_anim", 0)) > 0:
		e.rt["atk_anim"] = int(e.rt["atk_anim"]) - 2
	var tgt = e.rt.get("golem_tgt")
	if tgt != null and (not is_instance_valid(tgt) or tgt.dead or tgt.pos.distance_to(e.pos) > 16.0):
		tgt = null
	if tgt == null:
		var bd := 16.0
		for o in em.ents:
			if o.kind == "mob" and not o.dead and o.def.get("kind", "") == "hostile" and o.id != "creeper" and o.pos.distance_to(e.pos) < bd:
				bd = o.pos.distance_to(e.pos)
				tgt = o
	e.rt["golem_tgt"] = tgt
	if tgt == null:
		return
	e.has_target = true
	e.target_pos = tgt.pos
	e.ai_timer = 40
	# Java MeleeAttackGoal: reach (attacker width x 2)^2 + target width, horizontally
	var reach2: float = pow(float(e.w) * 2.0, 2.0) + float(tgt.w)
	var dx: float = tgt.pos.x - e.pos.x
	var dz: float = tgt.pos.z - e.pos.z
	if dx * dx + dz * dz <= reach2 and absf(tgt.pos.y - e.pos.y) < 3.0 and e.attack_cd <= 0:
		var f := float(e.def.get("attack", 15.0))
		var dmg: float = f / 2.0 + float(em.rng.randi_range(0, int(f) - 1))
		em._damage(tgt, dmg, e)
		tgt.vel.y += 0.4
		e.attack_cd = 20
		e.rt["atk_anim"] = 10
		Audio.play("entity.iron_golem.attack", e.pos, "Neutral")


static func tick_special(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float, fl: int) -> void:
	var def: Dictionary = e.def
	var hostile: bool = def["kind"] == "hostile"
	var can_target := (hostile or e.angry) and not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE)
	var range_ := 100.0 if def.get("rig", "") == "ghast" else 48.0
	# wiki: Ghast targets players within 64 blocks horizontally and 4 vertically; Wither detection range 40 blocks
	var acquire := 16.0
	if def.get("rig", "") == "ghast":
		acquire = 64.0 if absf(p.pos.y - e.pos.y) <= 4.0 else 0.0
	elif e.id == "wither":
		acquire = 40.0
	if can_target and wants_target(em, e, p, dist) and dist < (range_ if e.target_player else acquire):
		e.target_player = true
	elif not can_target or dist > range_:
		e.target_player = false
	if def.get("dragon", false):
		DragonFight.tick_dragon(em, e, p, gs, blocks, dist)
		return
	if def.get("crystal", false):
		e.vel = Vector3.ZERO
		# Java EndCrystal.tick: with a dragon fight (the End) the crystal keeps a fire burning in its block
		if em.world.dimension == "the_end" and em.world.get("dragon_fight") != null:
			var bp := Vector3i(e.pos.floor())
			if em.world.state_at(bp.x, bp.y, bp.z) == 0:
				em.world.set_block(bp.x, bp.y, bp.z, BlockUpdates.fire_state(em.world, bp))
		return
	if def.get("swims", false) and (e.id == "squid" or e.id == "glow_squid") and fl == 1:
		_squid(em, e, gs, blocks)   # (Java Squid.aiStep + SquidRandomMovementGoal)
	elif def.get("swims", false):
		_swimmer(em, e, p, gs, blocks, dist, fl)
	elif def.get("flies", false):
		if def.get("rig", "") == "ghast":
			_ghast(em, e, p, gs, blocks, dist)
		elif e.id == "allay":
			Allay.tick(em, e, p, gs, blocks)   # (Java AllayAi brain, FlyingMoveControl)
		elif e.id == "bat":
			_bat(em, e, gs, blocks)   # (Java Bat.customServerAiStep)
		elif def.get("small_flyer", false):
			_small_flyer(em, e, p, gs, blocks, dist)
		else:
			_blaze(em, e, p, gs, blocks, dist)
	elif def.get("hops", false):
		_hopper(em, e, p, gs, blocks, dist, fl)
	elif def.get("stationary", false):
		_shulker(em, e, p, dist)
	e.body_yaw = rad_to_deg(lerp_angle(deg_to_rad(e.body_yaw), deg_to_rad(e.yaw), 0.3))
	e.head_yaw = e.body_yaw
	var mv := Vector2(e.pos.x - e.prev.x, e.pos.z - e.prev.z).length()
	e.limb_amt = lerpf(e.limb_amt, minf(mv * 4.0, 1.0), 0.4)
	e.limb += e.limb_amt
	if e.pos.y < Coords.MIN_Y - 64:
		em._remove(e)


static func _face(e: EntityManager.Ent, at: Vector3, rate: float = 0.35) -> void:
	var d := at - e.pos
	var want := rad_to_deg(atan2(-d.x, d.z))
	e.yaw = rad_to_deg(lerp_angle(deg_to_rad(e.yaw), deg_to_rad(want), rate))


## Ghast: RandomFloatAroundGoal (+-16 blocks), LookGoal, ShootFireballGoal (charge 20 ticks, cooldown 40).
static func _ghast(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var rng := em.rng
	var tempt := false
	if e.id == "happy_ghast" and not p.dead and dist < 10.0:
		# wiki Happy Ghast: follows players holding snowballs, or a harness while it has none (tempt range: TemptGoal's 10
		# blocks; no stop distance on the wiki - ghastlings stop within 5 blocks of what they follow, used here)
		var th := p.inventory.held()
		var hn := "" if th.is_empty() else th.name()
		if hn == "snowball" or (hn.ends_with("_harness") and not e.data.has("harness") and e.baby_age >= 0):
			tempt = true
			e.target_pos = p.pos if dist > 5.0 else e.pos
			e.has_target = true
			_face(e, p.pos, 0.3)
	if not tempt and (not e.has_target or e.pos.distance_to(e.target_pos) < 1.0 or e.pos.distance_to(e.target_pos) > 60.0 or e.hcollide):
		e.target_pos = e.pos + Vector3(rng.randf_range(-16, 16), rng.randf_range(-16, 16), rng.randf_range(-16, 16))
		e.has_target = true
	var d: Vector3 = e.target_pos - e.pos
	if d.length() > 1.0:
		e.vel += d.normalized() * 0.1 * 0.1
	var eye := e.pos + Vector3(0, 2.6, 0)
	var peye := p.pos + Vector3(0, p.eye_height(), 0)
	if e.target_player and dist < 64.0 and _has_los(em, eye, peye):
		_face(e, p.pos, 0.5)
		e.charge += 1
		if e.charge == 10:
			Audio.play("entity.ghast.warn", e.pos, "Hostile")
		if e.charge >= 20:
			var look := (peye - eye).normalized()
			var from := eye + look * 4.0
			Audio.play("entity.ghast.shoot", e.pos, "Hostile")
			# start speed = the 0.1 acceleration along the aim (Java AbstractHurtingProjectile.assignDirectionalMovement;
			# the wiki gives only the acceleration 0.1 / drag 0.95): it speeds up toward 1.9 blocks per tick
			em.spawn_projectile("fireball", from, (peye - from).normalized() * 0.1, e)
			e.charge = -40
	else:
		if e.charge > 0:
			e.charge -= 1
		_face(e, e.pos + Vector3(e.vel.x, 0, e.vel.z) * 10.0, 0.1)
	if e.charge < 0:
		e.charge += 1
	em._physics(e, gs, blocks, 0.0, 1.0, 0.0)
	e.vel *= 0.91
	if em.rng.randi_range(0, 199) == 0 and dist < 48.0:
		Audio.play("entity.ghast.ambient", e.pos, "Hostile")


## Blaze: height control toward the target's eyes, slow fall, melee within 2 blocks, 3-fireball burst.
## Also drives the Wither (wither skulls instead of fireballs; 220-tick invulnerable charge ending in a blast).
static func _blaze(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var rng := em.rng
	if e.id == "wither":
		if e.charge < 0:
			e.charge += 1
			e.hp = minf(float(e.def["hp"]), e.hp + 200.0 / 220.0)
			e.vel = Vector3.ZERO
			if e.charge == 0:
				em.explode(e.pos + Vector3(0, 1.75, 0), 7.0, em.world.gamerule("mobGriefing", true))
				Audio.play("entity.wither.spawn", e.pos, "Hostile")
			return
		if e.age % 20 == 0:
			e.hp = minf(float(e.def["hp"]), e.hp + 1.0)
	var move_to := Vector3.INF
	# wiki Blaze: every 5 s a new rise threshold 0.5 + 6.891 * (r1 - r2) relative to its eyes is picked
	if e.id != "wither":
		var ht := int(e.rt.get("hover_t", 0)) - 1
		if ht <= 0:
			ht = 100
			e.rt["hover_off"] = 0.5 + 6.891 * (rng.randf() - rng.randf())
		e.rt["hover_t"] = ht
	if e.target_player:
		var peye := p.pos.y + p.eye_height()
		# wiki Wither: hovers about 5 blocks above its target, within 3 blocks horizontally
		# (wiki Wither: with its wither armor - below half health - it flies at the height of its target)
		var rise := e.pos.y < p.pos.y + (0.0 if e.hp < float(e.def["hp"]) / 2.0 else 5.0) if e.id == "wither" else peye > e.pos.y + 1.6 + float(e.rt.get("hover_off", 0.5))
		if rise:
			e.vel.y += (0.3 - e.vel.y) * 0.3
		_face(e, p.pos, 0.5)
		if e.id == "wither":
			_wither_heads(em, e, p, dist)
			if Vector2(p.pos.x - e.pos.x, p.pos.z - e.pos.z).length() > 3.0:
				move_to = p.pos
		elif dist < 2.0:
			# wiki Blaze: melee once per second within 2 blocks (not fire damage, does not ignite)
			if e.attack_cd <= 0:
				p.hurt(diff_dmg(em.world.difficulty, float(e.def.get("attack", 6.0))), "mob", false, e.pos, e)
				e.attack_cd = 20
			move_to = p.pos
		elif dist < 48.0:
			e.charge -= 1
			if e.charge <= 0:
				e.burst += 1
				if e.burst == 1:
					e.charge = 60
				elif e.burst <= 4:
					e.charge = 6
					var from := e.pos + Vector3(0, e.h * 0.5 + 0.5, 0)
					# wiki Blaze: each horizontal component + 1.1485 * sqrt(D) * (r1 - r2), D = distance to the target
					var h := 1.1485 * sqrt(dist)
					var dirv := p.pos + Vector3(0, p.eye_height() * 0.5, 0) - from
					dirv += Vector3(h * (rng.randf() - rng.randf()), 0, h * (rng.randf() - rng.randf()))
					Audio.play("entity.blaze.shoot", e.pos, "Hostile")
					em.spawn_projectile("small_fireball", from, dirv.normalized() * 0.1, e)   # (start speed as the ghast fireball)
				else:
					e.charge = 100
					e.burst = 0
			if not _has_los(em, e.pos + Vector3(0, 1.5, 0), p.pos + Vector3(0, p.eye_height(), 0)):
				move_to = p.pos
	else:
		e.ai_timer -= 1
		if e.ai_timer <= 0:
			e.ai_timer = rng.randi_range(60, 200)
			e.target_pos = e.pos + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
		move_to = e.target_pos
	if move_to != Vector3.INF and Vector2(move_to.x - e.pos.x, move_to.z - e.pos.z).length() > 1.0:
		_face(e, move_to)
		var yr := deg_to_rad(e.yaw)
		e.vel += Vector3(-sin(yr), 0, cos(yr)) * float(e.def["speed"]) * 0.1
	if not e.on_ground and e.vel.y < 0.0:
		e.vel.y *= 0.6
	em._physics(e, gs, blocks, 0.08, 0.91, 0.6)
	if rng.randi_range(0, 23) == 0:
		Audio.play("entity.blaze.burn", e.pos, "Hostile", 0.3)


## wiki Wither: the main head fires a skull every 2 s, each side head every 40-59 ticks (here all at the player).
static func _wither_heads(em: EntityManager, e: EntityManager.Ent, p: Player, dist: float) -> void:
	if dist > 40.0:
		return
	for k in 3:
		var key := "wh%d" % k
		var cd := int(e.rt.get(key, 0)) - 1
		if cd <= 0:
			cd = 40 if k == 0 else em.rng.randi_range(40, 59)
			var from := e.pos + Vector3(0, e.h * 0.5 + 0.5, 0)
			Audio.play("entity.wither.shoot", e.pos, "Hostile")
			em.spawn_projectile("wither_skull", from, (p.pos + Vector3(0, p.eye_height() * 0.5, 0) - from).normalized() * 0.8, e)
		e.rt[key] = cd


## Slime / Magma Cube: SlimeMoveControl jump cadence, contact damage scaled by size.
static func _hopper(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float, fl: int) -> void:
	var rng := em.rng
	var magma: bool = e.id == "magma_cube"
	if e.target_player:
		_face(e, p.pos, 0.6)
	elif rng.randi_range(0, 59) == 0:
		e.yaw += rng.randf_range(-90, 90)
	if e.on_ground or fl != 0:
		e.vel.x *= 0.5
		e.vel.z *= 0.5
		e.charge -= 1
		if e.charge <= 0:
			e.charge = (rng.randi_range(0, 19) + 10) * (4 if magma else 1)
			if e.target_player:
				e.charge /= 3
			var jump := 0.42 + (0.1 * e.size if magma else 0.0)
			e.vel.y = jump
			var yr := deg_to_rad(e.yaw)
			# movement_speed 0.2 + 0.1 x size (wiki Attribute: slimes; sulfur cubes large 0.4 / small 0.3 per the Sulfur Cube
			# infobox - size 2 / 1 here); the hop cadence and height are not on the wiki (Java SlimeMoveControl)
			var sp := (float(e.def["speed"]) if e.id == "sulfur_cube" and e.size >= 2 else (0.3 if e.id == "sulfur_cube" else 0.2 + 0.1 * e.size)) * 0.5
			e.vel += Vector3(-sin(yr), 0, cos(yr)) * sp
			Audio.play("entity.%s.jump%s" % [e.id, "" if e.size > 1 else "_small"], e.pos, "Hostile")
	# contact damage (Java Slime.dealDamage: distance < 0.6 * size, small slimes harmless)
	var deals := e.size > 1 or magma
	if e.target_player and deals and e.attack_cd <= 0 and dist < 0.6 * e.size + 0.6:
		# wiki Slime: Large 4 / Medium 2 (= size), the smallest none; wiki Magma Cube: attack strength is size + 2
		var dmg := float(e.size) + (2.0 if magma else 0.0)
		if p.hurt(diff_dmg(em.world.difficulty, dmg), "mob", false, e.pos, e):
			e.attack_cd = 10
	em._physics(e, gs, blocks, 0.08 if fl == 0 else 0.02, 0.91 if fl == 0 else 0.8, 0.0)


## Shulker: stationary, homing bullets every 20..220 ticks while a target is within 16 blocks.
static func _shulker(em: EntityManager, e: EntityManager.Ent, p: Player, dist: float) -> void:
	e.vel = Vector3.ZERO
	if e.target_player and dist < 16.0:
		_face(e, p.pos, 0.5)
		e.charge -= 1
		if e.charge <= 0:
			e.charge = em.rng.randi_range(20, 110)   # wiki Shulker: fires every 1-5.5 s while the target is in range
			Audio.play("entity.shulker.shoot", e.pos, "Hostile")
			em.spawn_projectile("shulker_bullet", e.pos + Vector3(0, 1.2, 0), (p.pos - e.pos).normalized() * 0.15, e)


## Small flyers (bat, parrot, bee, allay, vex, phantom): free 3D wander near the spawn height; hostile flyers
## home in on the player (phantoms circle above, then swoop) and melee on contact.
## Java Bat (flying part of customServerAiStep + tick + travel): a target block re-picked when reached (2 blocks), not
## air, or 1 in 30 per tick - x / z +-(nextInt(7) - nextInt(7)), y + nextInt(6) - 2; velocity eased 0.1 toward
## sign(d) x (0.5, 0.7, 0.5), y velocity x 0.6 each tick, then the air travel (gravity 0.08, drag 0.91 / 0.98).
static func _bat(em: EntityManager, e: EntityManager.Ent, gs: Callable, blocks: BlockRegistry) -> void:
	var rng := em.rng
	var tp = e.data.get("bat_target")
	if tp != null:
		var tv: Vector3i = tp
		var ts: int = gs.call(tv.x, tv.y, tv.z)
		if (ts != 0 and (ts < 0 or (blocks.st_flags[ts] & BlockRegistry.F_AIR) == 0)) or tv.y <= Coords.MIN_Y:
			tp = null
	if tp == null or rng.randi_range(0, 29) == 0 or (Vector3(tp) + Vector3(0.5, 0.5, 0.5)).distance_to(e.pos) < 2.0:
		tp = Vector3i((e.pos + Vector3(rng.randi_range(0, 6) - rng.randi_range(0, 6), rng.randi_range(0, 5) - 2.0, rng.randi_range(0, 6) - rng.randi_range(0, 6))).floor())
		e.data["bat_target"] = tp
	var t: Vector3i = tp
	var d := Vector3(t.x + 0.5 - e.pos.x, t.y + 0.1 - e.pos.y, t.z + 0.5 - e.pos.z)
	var v := e.vel
	v += Vector3((signf(d.x) * 0.5 - v.x) * 0.1, (signf(d.y) * 0.7 - v.y) * 0.1, (signf(d.z) * 0.5 - v.z) * 0.1)
	e.vel = v
	e.yaw = rad_to_deg(atan2(-v.x, v.z))
	e.body_yaw = e.yaw
	e.vel.y *= 0.6
	em._physics(e, gs, blocks, 0.08, 0.91, 0.0)


## Java Squid in water: SquidRandomMovementGoal picks a movement vector (cos / sin of a random angle x 0.2, y -0.1..0.1)
## 1 in 50 per tick or when it has none; the tentacle cycle (speed 1 / (r + 1) x 0.2, re-rolled 1 in 10 per cycle)
## sets the swim speed to 1 in the stroke (f > 0.75) and lets it fade x 0.9 between strokes; velocity = vector x speed.
static func _squid(em: EntityManager, e: EntityManager.Ent, gs: Callable, blocks: BlockRegistry) -> void:
	var rng := em.rng
	var rt: Dictionary = e.rt
	if not rt.has("sq_ts"):
		rt["sq_ts"] = 1.0 / (rng.randf() + 1.0) * 0.2
		rt["sq_tm"] = 0.0
		rt["sq_sp"] = 0.0
	var mv = e.data.get("sq_vec")
	if mv == null or rng.randi_range(0, 49) == 0:
		var a := rng.randf() * TAU
		mv = Vector3(cos(a) * 0.2, -0.1 + rng.randf() * 0.2, sin(a) * 0.2)
		e.data["sq_vec"] = mv
	var tm: float = rt["sq_tm"] + float(rt["sq_ts"])
	if tm > TAU:
		tm -= TAU
		if rng.randi_range(0, 9) == 0:
			rt["sq_ts"] = 1.0 / (rng.randf() + 1.0) * 0.2
	rt["sq_tm"] = tm
	var sp: float = rt["sq_sp"]
	if tm < PI:
		if tm / PI > 0.75:
			sp = 1.0
	else:
		sp *= 0.9
	rt["sq_sp"] = sp
	var v: Vector3 = mv
	e.vel = v * sp
	if v.length() > 0.001:
		_face(e, e.pos + v, 0.2)
	em._physics(e, gs, blocks, 0.0, 1.0, 0.0)


## Bees and parrots (Java FlyingAnimal + FlyingMoveControl) on their attributes: toward the move target the speed is
## modifier x flying_speed (def fly_speed: bee 0.6, parrot 0.4; on the ground movement_speed), the input pushes along
## the facing (turning up to 90 degrees per tick) and up / down by +-speed, scaled by the air movement factor 0.02
## (on the ground by the speed itself); drag 0.91 on every axis. Modifiers: wander / follow 1.0, bee attack 1.4
## (BeeAttackGoal), panic 1.25 (wiki Parrot: hurt parrots fly upward several blocks). Without a target bees hover and
## parrots drop (wiki Parrot: wings slow the fall - x0.6 per tick while falling) and land. Wander (Java BeeWanderGoal 1
## in 20 per tick, 8 blocks / hovering 1-3 above the ground; parrots WaterAvoidingRandomFlyingGoal 1 in 120 per tick,
## mostly landing spots). Vexes / phantoms: _vex / _phantom.
static func _small_flyer(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	if e.id == "vex":
		_vex(em, e, p, gs, blocks, dist)
		return
	if e.def.get("swoops", false):
		_phantom(em, e, p, gs, blocks, dist)
		return
	var rng := em.rng
	var def: Dictionary = e.def
	var target := Vector3.INF
	var mod := 1.0
	if e.target_player:
		target = p.pos + Vector3(0, p.eye_height() * 0.6, 0)
		if e.id == "bee":
			mod = 1.4
		if dist < 1.6 and e.attack_cd <= 0:
			if p.hurt(diff_dmg(em.world.difficulty, float(def.get("attack", 2.0)) + HeldItems.attack_bonus(e)), "mob", false, e.pos, e) and e.id == "bee":
				MobBehaviors.bee_stung(em, e, p)
			e.attack_cd = 20
	elif e.panic > 0:
		e.panic -= 1
		if not e.has_target or e.pos.distance_to(e.target_pos) < 1.0:
			e.target_pos = e.pos + Vector3(rng.randf_range(-5, 5), rng.randf_range(1.0, 4.0), rng.randf_range(-5, 5))
			e.has_target = true
		target = e.target_pos
		mod = 1.25
	elif bool(e.data.get("sitting", false)):
		e.has_target = false   # (a parrot told to sit drops onto its perch and stays)
	else:
		if e.has_target and e.pos.distance_to(e.target_pos) < 1.0:
			e.has_target = false
		if not e.has_target and rng.randi_range(0, 19 if e.id == "bee" else 119) == 0:
			e.target_pos = _flyer_spot(e, gs, blocks, rng)
			e.has_target = true
		if e.has_target:
			target = e.target_pos
	fly_animal(em, e, target, mod, gs, blocks)


## One tick of FlyingAnimal travel toward target (INF: no move target).
static func fly_animal(em: EntityManager, e: EntityManager.Ent, target: Vector3, mod: float, gs: Callable, blocks: BlockRegistry) -> void:
	var def: Dictionary = e.def
	if target != Vector3.INF and e.pos.distance_squared_to(target) > 2.5000003e-7:
		var d := target - e.pos
		if d.x * d.x + d.z * d.z > 1e-10:
			e.yaw = MobControl.rotlerp(e.yaw, rad_to_deg(atan2(-d.x, d.z)), 90.0)
		var f := (float(def["speed"]) if e.on_ground else float(def.get("fly_speed", def["speed"]))) * mod
		var inp := Vector3(0.0, (f if d.y > 0.0 else -f) if absf(d.y) > 1e-5 else 0.0, f)
		if inp.length_squared() > 1.0:
			inp = inp.normalized()
		var amt := f if e.on_ground else 0.02
		var yr := deg_to_rad(e.yaw)
		e.vel += Vector3(-sin(yr) * inp.z, inp.y, cos(yr) * inp.z) * amt
	elif e.id == "parrot":
		e.vel.y -= 0.08
		if not e.on_ground and e.vel.y < 0.0:
			e.vel.y *= 0.6
	em._physics(e, gs, blocks, 0.0, 0.91, 0.0, 0.91)


static func _flyer_spot(e: EntityManager.Ent, gs: Callable, blocks: BlockRegistry, rng: RandomNumberGenerator) -> Vector3:
	var x := floori(e.pos.x) + rng.randi_range(-8, 8)
	var z := floori(e.pos.z) + rng.randi_range(-8, 8)
	var y0 := floori(e.pos.y)
	for dy in range(7, -8, -1):
		var st: int = gs.call(x, y0 + dy - 1, z)
		if st > 0 and (blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0 and gs.call(x, y0 + dy, z) == 0:
			var ground := float(y0 + dy)
			if e.id == "parrot":
				return Vector3(x + 0.5, ground, z + 0.5)   # (a landing spot)
			return Vector3(x + 0.5, ground + rng.randf_range(1.0, 3.0), z + 0.5)
	return Vector3(x + 0.5, e.pos.y + rng.randf_range(-3.0, 3.0), z + 0.5)


## Java VexMoveControl / VexRandomMoveGoal / VexChargeAttackGoal: the vex's control ignores its movement_speed
## attribute - velocity += direction x modifier x 0.05 per tick toward the wanted point (charge 1.0, wander 0.25),
## stopping (x0.5) within its box size; drag 0.91 / 0.98, no gravity. wiki Vex: idle vexes pick air blocks in the
## 15 x 11 x 15 box around where their evoker summoned them (else around themselves), chase a target up to about 128
## blocks from the evoker, pass through blocks; they lunge at their target (a hit when the boxes touch). Goal starts:
## 1 in 8 per tick (reducedTickDelay(7) every other tick); a charge needs the target more than 2 blocks away.
static func _vex(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var rng := em.rng
	var bound = e.data.get("bound")
	if e.target_player and bound is Array and e.pos.distance_to(Vector3(float(bound[0]), float(bound[1]), float(bound[2]))) > 128.0:
		e.target_player = false
	var wanted = e.rt.get("vex_to")
	var mod := float(e.rt.get("vex_mod", 0.25))
	var charging := bool(e.rt.get("vex_charge", false)) and e.target_player
	if e.target_player:
		var eye := p.pos + Vector3(0, p.eye_height(), 0)
		if not charging and wanted == null and rng.randi_range(0, 7) == 0 and e.pos.distance_squared_to(p.pos) > 4.0:
			charging = true
			wanted = eye
			mod = 1.0
			Audio.play("entity.vex.charge", e.pos, "Hostile")
		if charging:
			var hw: float = e.w * 0.5
			var pmn := p.aabb_min()
			var pmx := p.aabb_max()
			if e.pos.x + hw > pmn.x and e.pos.x - hw < pmx.x and e.pos.z + hw > pmn.z and e.pos.z - hw < pmx.z and e.pos.y + e.h > pmn.y and e.pos.y < pmx.y:
				if e.attack_cd <= 0:
					p.hurt(diff_dmg(em.world.difficulty, float(e.def.get("attack", 9.0))), "mob", false, e.pos, e)
					e.attack_cd = 20
				charging = false
			elif e.pos.distance_squared_to(p.pos) < 9.0:
				wanted = eye
		_face(e, p.pos, 0.5)
	elif wanted == null and rng.randi_range(0, 7) == 0:
		var o := Vector3i(int(bound[0]), int(bound[1]), int(bound[2])) if bound is Array else Vector3i(e.pos.floor())
		for i in 3:
			var q := o + Vector3i(rng.randi_range(-7, 7), rng.randi_range(-5, 5), rng.randi_range(-7, 7))
			if gs.call(q.x, q.y, q.z) == 0:
				wanted = Vector3(q) + Vector3(0.5, 0.5, 0.5)
				mod = 0.25
				break
	if wanted != null:
		var d: Vector3 = wanted - e.pos
		var l := d.length()
		if l < (e.w * 2.0 + e.h) / 3.0:
			e.vel *= 0.5
			wanted = null
			charging = false
		else:
			e.vel += d / l * mod * 0.05
			if not e.target_player:
				_face(e, e.pos + e.vel, 1.0)
	e.rt["vex_to"] = wanted
	e.rt["vex_mod"] = mod
	e.rt["vex_charge"] = charging
	e.pos += e.vel
	e.on_ground = false
	e.hcollide = false
	e.vel.x *= 0.91
	e.vel.z *= 0.91
	e.vel.y *= 0.98


## wiki Phantom: circles 15-25 blocks from the player horizontally and 24-35 vertically, swoops every 8-12 s (a hit,
## being stopped or hurt during the swoop sends it back up); up to 20 blocks per second when attacking. Movement as
## Java PhantomMoveControl: turns at most 4 degrees per tick toward its point, speeds up while lined up (+0.005 x
## max / speed per tick) and slows toward 0.2 while turning, velocity eased 0.2 per tick toward speed along the
## (vertically flattened) direction, drag 0.91, no gravity; circling points 15 degrees apart around the player (the
## next one within 2 blocks). Its top speed is set so the eased, damped motion peaks at the wiki's 20 blocks per
## second (moved per tick = 0.2 S / (1 - 0.8 x 0.91) = 0.735 S = 1 block; Java's constant is not on the wiki).
const PHANTOM_MAX := 1.36


static func _phantom(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var rng := em.rng
	var def: Dictionary = e.def
	var target := Vector3.INF
	if e.target_player:
		e.charge += 1
		if e.rt.has("ph_swoop") and e.charge >= int(e.rt["ph_swoop"]) and (e.hurt_time > 0 or e.hcollide or e.on_ground):
			e.charge = 0
			e.rt.erase("ph_swoop")
		if not e.rt.has("ph_swoop"):
			e.rt["ph_swoop"] = rng.randi_range(160, 240)
			e.rt["ph_r"] = rng.randf_range(15.0, 25.0)
			e.rt["ph_h"] = rng.randf_range(24.0, 35.0)
		if e.charge < int(e.rt["ph_swoop"]):
			var ang := float(e.rt.get("ph_ang", rng.randf() * TAU))
			target = p.pos + Vector3(cos(ang) * float(e.rt["ph_r"]), float(e.rt["ph_h"]), sin(ang) * float(e.rt["ph_r"]))
			if e.pos.distance_squared_to(target) < 4.0:
				ang += deg_to_rad(15.0)
				target = p.pos + Vector3(cos(ang) * float(e.rt["ph_r"]), float(e.rt["ph_h"]), sin(ang) * float(e.rt["ph_r"]))
			e.rt["ph_ang"] = ang
		else:
			target = p.pos + Vector3(0, p.eye_height() * 0.6, 0)
			# wiki Phantom: phantoms attacking a player keep 16 blocks away from cats (walls do not matter), which hiss at
			# them - the swoop is called off and it circles again (checked every 20 ticks: Java; ocelots: Bedrock only)
			if (e.age + e.uid) % 20 == 0 and _cats_hiss(em, e):
				e.charge = 0
				e.rt.erase("ph_swoop")
		if dist < 1.6 and e.attack_cd <= 0:
			p.hurt(diff_dmg(em.world.difficulty, float(def.get("attack", 2.0))), "mob", false, e.pos, e)
			e.attack_cd = 20
			e.charge = 0
			e.rt.erase("ph_swoop")
	else:
		if not e.has_target or e.pos.distance_to(e.target_pos) < 2.0 or rng.randi_range(0, 199) == 0:
			e.target_pos = e.pos + Vector3(rng.randf_range(-16, 16), rng.randf_range(-4, 4), rng.randf_range(-16, 16))
			e.has_target = true
		target = e.target_pos
	var spd := float(e.rt.get("ph_spd", 0.1))
	if e.hcollide:
		e.yaw += 180.0
		spd = 0.1
	var d := target - e.pos
	var d3 := Vector2(d.x, d.z).length()
	if d3 > 1e-5:
		var d4 := 1.0 - absf(d.y * 0.7) / d3
		d.x *= d4
		d.z *= d4
		d3 = Vector2(d.x, d.z).length()
		var d5 := d.length()
		var old := e.yaw
		var want := rad_to_deg(atan2(-d.x, d.z))
		e.yaw = e.yaw + clampf(MobControl.wrap_deg(want - e.yaw), -4.0, 4.0)
		if absf(MobControl.wrap_deg(old - e.yaw)) < 3.0:
			spd = move_toward(spd, PHANTOM_MAX, 0.005 * (PHANTOM_MAX / maxf(spd, 0.01)))
		else:
			spd = move_toward(spd, 0.2, 0.025)
		var pitch := atan2(d.y, d3)
		var yr := deg_to_rad(e.yaw)
		var tv := Vector3(-sin(yr) * spd * absf(d.x / d5), sin(pitch) * spd * absf(d.y / d5), cos(yr) * spd * absf(d.z / d5)) if d5 > 1e-5 else Vector3.ZERO
		e.vel += (tv - e.vel) * 0.2
	e.rt["ph_spd"] = spd
	em._physics(e, gs, blocks, 0.0, 0.91, 0.0, 0.91)


## Cats within 16 blocks of the phantom (box, through walls) hiss; true when there were any.
static func _cats_hiss(em, e) -> bool:
	var any := false
	for c in MobBehaviors.near_list(em, "cat"):
		var d: Vector3 = c.pos - e.pos
		if not c.dead and absf(d.x) <= 16.0 and absf(d.y) <= 16.0 and absf(d.z) <= 16.0:
			any = true
			Audio.play("entity.cat.hiss", c.pos, "Neutral")
	return any


## Java AbstractFish movement on the movement_speed attribute (0.7, wiki Attribute): FishMoveControl eases the swim
## speed 0.125 per tick toward attribute x modifier, turns up to 90 degrees per tick, rises / dives by speed x dy /
## distance x 0.1 per tick; travel in water pushes along the facing by 0.01 x speed (moveRelative 0.01) with drag 0.9
## (about 1.4 blocks per second at 1.0). Goals: PanicGoal 1.25 after damage, RandomSwimmingGoal 1.0 (1 in 40 per tick
## while idle: a water block within 10 horizontally / 7 vertically), AvoidEntityGoal from players within 8 blocks
## (1.6, 1.4 within 7). The wiki gives no fish speeds or goals beyond the attribute: these are Java's.
const FISH := {"cod": true, "salmon": true, "tropical_fish": true, "pufferfish": true}


static func _fish(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var rng := em.rng
	var mod := 1.0
	var target := Vector3.INF
	if e.panic > 0:
		e.panic -= 1
		mod = 1.25
		if not e.has_target or e.pos.distance_to(e.target_pos) < 1.0:
			e.target_pos = _water_spot(e, gs, blocks, rng, 5, 4, e.pos)
			e.has_target = e.target_pos != Vector3.INF
	elif dist < 8.0 and not p.dead and not p.is_spectator():
		mod = 1.4 if dist < 7.0 else 1.6
		if not e.has_target or e.age % 10 == 0 or e.pos.distance_to(e.target_pos) < 1.0:
			var away := Vector3(e.pos.x - p.pos.x, 0.0, e.pos.z - p.pos.z)
			away = away.normalized() if away.length_squared() > 1e-4 else Vector3(1, 0, 0)
			e.target_pos = _water_spot(e, gs, blocks, rng, 4, 3, e.pos + away * 8.0)
			e.has_target = e.target_pos != Vector3.INF
	else:
		var lead := _flock(em, e) if SCHOOL.has(e.id) else Vector3.INF
		if lead != Vector3.INF:
			# a school follower swims after its leader (no random swimming of its own)
			e.has_target = false
			if e.pos.distance_squared_to(lead) > 2.25:
				target = lead
		elif e.has_target and e.pos.distance_to(e.target_pos) < 1.0:
			e.has_target = false
		elif not e.has_target and rng.randi_range(0, 39) == 0:
			e.target_pos = _water_spot(e, gs, blocks, rng, 10, 7, e.pos)
			e.has_target = e.target_pos != Vector3.INF
	if e.has_target:
		target = e.target_pos
	var spd := float(e.rt.get("fish_spd", 0.0))
	if target != Vector3.INF and e.pos.distance_squared_to(target) > 2.5000003e-7:
		var d := target - e.pos
		var l := d.length()
		if d.x * d.x + d.z * d.z > 1e-10:
			e.yaw = MobControl.rotlerp(e.yaw, rad_to_deg(atan2(-d.x, d.z)), 90.0)
		spd = lerpf(spd, mod * float(e.def["speed"]), 0.125)
		e.vel.y += spd * (d.y / l) * 0.1
		var yr := deg_to_rad(e.yaw)
		e.vel += Vector3(-sin(yr), 0.0, cos(yr)) * spd * 0.01
	else:
		spd = 0.0
	e.rt["fish_spd"] = spd
	em._physics(e, gs, blocks, 0.0, 1.0, 0.0, 1.0)
	e.vel *= 0.9


## Fish schools (wiki Cod / Salmon / Tropical Fish: schools of at most 9 cod, 7 salmon, 7 tropical fish). Java
## AbstractSchoolingFish / FollowFlockLeaderGoal (not on the wiki): a fish that leads no school looks every 100-109 ticks
## (Java reducedTickDelay(200 + nextInt(200) % 20)) at the fish of its kind within 8 blocks; the first one leading a
## school with room becomes its leader (else the fish itself leads), and the fish there that follow nobody join it up
## to the size; followers swim to their leader (re-aimed every 10 ticks) and leave beyond 11 blocks; a leader with
## nobody of its kind within 8 blocks forgets its school (1 in 200 per tick).
const SCHOOL := {"cod": 9, "salmon": 7, "tropical_fish": 7}


## A follower's leader position (INF: not following anyone).
static func _flock(em, e) -> Vector3:
	var ld = e.rt.get("leader")
	if ld != null:
		if ld.dead or ld.pos.distance_squared_to(e.pos) > 121.0:
			_leave_school(e)
		else:
			if not e.rt.has("lead_to") or (e.age + e.uid) % 10 == 0:
				e.rt["lead_to"] = ld.pos
			return e.rt["lead_to"]
	if int(e.rt.get("school", 1)) > 1:
		if em.rng.randi_range(0, 199) == 1:
			# (also recounts the followers still alive: Java drops a follower from the count when it dies)
			var alone := true
			var n := 1
			for o in MobBehaviors.near_list(em, e.id):
				if o != e and not o.dead:
					if _within(o.pos, e.pos, 8.0):
						alone = false
					if o.rt.get("leader") == e:
						n += 1
			e.rt["school"] = 1 if alone else n
		return Vector3.INF
	var nt := int(e.rt.get("flock_t", -1))
	if nt < 0:
		nt = e.age + em.rng.randi_range(0, 109)   # (staggered first look)
		e.rt["flock_t"] = nt
	if e.age < nt:
		return Vector3.INF
	e.rt["flock_t"] = e.age + 100 + em.rng.randi_range(0, 9)
	var mx: int = SCHOOL[e.id]
	var leader = null
	var free: Array = []
	for o in MobBehaviors.near_list(em, e.id):
		if o.dead or not _within(o.pos, e.pos, 8.0):
			continue
		var follows: bool = o.rt.get("leader") != null and not o.rt["leader"].dead
		var size := int(o.rt.get("school", 1))
		if leader == null and o != e and size > 1 and size < mx:
			leader = o
		elif not follows and size <= 1:
			free.append(o)
	if leader == null:
		leader = e
	for o in free:
		if o == leader or int(leader.rt.get("school", 1)) >= mx:
			continue
		o.rt["leader"] = leader
		o.rt.erase("lead_to")
		leader.rt["school"] = int(leader.rt.get("school", 1)) + 1
	return e.rt["leader"].pos if e.rt.get("leader") != null else Vector3.INF


static func _leave_school(e) -> void:
	var ld = e.rt.get("leader")
	if ld != null:
		ld.rt["school"] = maxi(1, int(ld.rt.get("school", 1)) - 1)
	e.rt.erase("leader")
	e.rt.erase("lead_to")


static func _within(a: Vector3, b: Vector3, r: float) -> bool:
	return absf(a.x - b.x) <= r and absf(a.y - b.y) <= r and absf(a.z - b.z) <= r


## A water block within +-h horizontally / +-v vertically of around (3 tries), its centre; INF when none.
static func _water_spot(e: EntityManager.Ent, gs: Callable, blocks: BlockRegistry, rng: RandomNumberGenerator, h: int, v: int, around: Vector3) -> Vector3:
	for i in 3:
		var q := Vector3i(around.floor()) + Vector3i(rng.randi_range(-h, h), rng.randi_range(-v, v), rng.randi_range(-h, h))
		var st: int = gs.call(q.x, q.y, q.z)
		if st > 0 and (blocks.st_flags[st] & BlockRegistry.F_LIQUID) != 0 and (blocks.st_flags[st] & BlockRegistry.F_LAVA) == 0:
			return Vector3(q) + Vector3(0.5, 0.5, 0.5)
	return Vector3.INF


## Aquatic AI: in water no gravity, 3D wander inside water (hostiles chase; guardians charge a laser);
## out of water fish flop and dry out (Java AbstractFish/WaterAnimal air supply).
static func _swimmer(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float, fl: int) -> void:
	var rng := em.rng
	var def: Dictionary = e.def
	if fl == 1 and FISH.has(e.id):
		e.charge = maxi(e.charge, 0)
		_fish(em, e, p, gs, blocks, dist)
	elif fl == 1:
		e.charge = maxi(e.charge, 0)
		var target := Vector3.INF
		# TemptGoal (10 blocks, stops within 2.5): wiki Nautilus - players holding any fish or bucket of fish; axolotls
		# their breeding food (bucket of tropical fish)
		if not (e.target_player and p.in_water) and not p.dead and dist < 10.0 and not (def.get("food", []) as Array).is_empty():
			var th := p.inventory.held()
			if not th.is_empty() and ((def.get("food", []) as Array).has(th.name()) or (def.get("tempt", []) as Array).has(th.name())):
				target = p.pos + Vector3(0, p.eye_height() * 0.5, 0) if dist > 2.5 else e.pos
				_face(e, p.pos, 0.3)
		if target == Vector3.INF and e.love > 0 and e.baby_age >= 0:
			# BreedGoal for swimmers (nautiluses / axolotls fed while at full health): swim to a partner in love within 8
			# blocks, a baby when within 1.5 (partner re-picked every 10 ticks)
			var mate = e.rt.get("mate")
			if (e.age + e.uid) % 10 == 0:
				mate = null
				for o in em.ents:
					if o != e and o.kind == "mob" and o.id == e.id and o.love > 0 and not o.dead and o.pos.distance_squared_to(e.pos) < 64.0:
						mate = o
						break
				e.rt["mate"] = mate
			if mate != null and not mate.dead and mate.love > 0:
				target = mate.pos
				if mate.pos.distance_to(e.pos) < 1.5:
					em.spawn_mob(e.id, e.pos, true)
					em.spawn_xp(e.pos, rng.randi_range(1, 7))
					e.love = 0
					mate.love = 0
					e.breed_cd = 6000
					mate.breed_cd = 6000
					e.rt.erase("mate")
		if e.target_player and p.in_water:
			if def.get("laser", false):
				# wiki Guardian: the laser charges 4 s, reaches 15 blocks; it swims 3 s before firing again
				if dist <= 15.0 and e.attack_cd <= 0 and _has_los(em, e.pos + Vector3(0, e.h * 0.5, 0), p.pos + Vector3(0, p.eye_height(), 0)):
					e.charge += 1
					_face(e, p.pos, 0.5)
					if e.charge >= 80:
						p.hurt(diff_dmg(em.world.difficulty, float(def.get("attack", 6.0))), "magic")
						e.charge = 0
						e.attack_cd = 60
				else:
					target = p.pos
			else:
				target = p.pos
				if dist < 1.5 and e.attack_cd <= 0:
					p.hurt(diff_dmg(em.world.difficulty, float(def.get("attack", 2.0)) + HeldItems.attack_bonus(e)), "mob", false, e.pos, e)
					e.attack_cd = 20
		if target == Vector3.INF:
			if not e.has_target or e.pos.distance_to(e.target_pos) < 1.0 or e.hcollide or rng.randi_range(0, 79) == 0:
				e.target_pos = e.pos + Vector3(rng.randf_range(-8, 8), rng.randf_range(-3, 3), rng.randf_range(-8, 8))
				e.has_target = true
			var tst: int = gs.call(int(floor(e.target_pos.x)), int(floor(e.target_pos.y)), int(floor(e.target_pos.z)))
			if tst <= 0 or (blocks.st_flags[tst] & BlockRegistry.F_LIQUID) == 0:
				e.has_target = false
			target = e.target_pos
		var d := target - e.pos
		if d.length() > 0.3:
			e.vel += d.normalized() * float(def["speed"]) * 0.02
			_face(e, target, 0.3)
		em._physics(e, gs, blocks, 0.0, 1.0, 0.0)
		e.vel *= 0.9
	else:
		if def.get("fish", false):
			if e.on_ground and rng.randi_range(0, 9) == 0:
				e.vel += Vector3(rng.randf_range(-0.1, 0.1), 0.4, rng.randf_range(-0.1, 0.1))
				Audio.play("entity.%s.flop" % e.id, e.pos, "Neutral", 0.6)
			e.charge -= 1
			if e.charge < -300 and e.age % 20 == 0:
				em._damage(e, 2.0, null)
		em._physics(e, gs, blocks, 0.08, 0.91, 0.0)
