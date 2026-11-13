## MobAI — special behaviour archetypes on top of EntityManager's generic walker AI (source D, Java goals recalled):
## flyers (Ghast float + fireball goal, Blaze height control + 3-shot burst), hoppers (Slime/Magma Cube jump
## control + contact damage + size), stationary Shulkers (homing bullets), neutral targeting (Enderman stare,
## Zombified Piglin group anger, Piglins pacified by gold armour).
## Contract: wants_target(em, e, p, dist) -> bool; tick_special(...) performs AI + physics for one tick.
class_name MobAI
extends RefCounted


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
	if def.get("neutral", false):
		if not e.angry and def.get("teleports", false) and player_stares(em, e, p):
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


static func tick_special(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float, fl: int) -> void:
	var def: Dictionary = e.def
	var hostile: bool = def["kind"] == "hostile"
	var can_target := hostile and not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE)
	var range_ := 100.0 if def.get("rig", "") == "ghast" else 48.0
	if can_target and wants_target(em, e, p, dist) and dist < (range_ if e.target_player else 16.0 + (48.0 if def.get("rig", "") == "ghast" else 0.0)):
		e.target_player = true
	elif not can_target or dist > range_:
		e.target_player = false
	if def.get("dragon", false):
		DragonFight.tick_dragon(em, e, p, gs, blocks, dist)
		return
	if def.get("crystal", false):
		e.vel = Vector3.ZERO
		return
	if def.get("swims", false):
		_swimmer(em, e, p, gs, blocks, dist, fl)
	elif def.get("flies", false):
		if def.get("rig", "") == "ghast":
			_ghast(em, e, p, gs, blocks, dist)
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
	if not e.has_target or e.pos.distance_to(e.target_pos) < 1.0 or e.pos.distance_to(e.target_pos) > 60.0 or e.hcollide:
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
			em.spawn_projectile("fireball", from, (peye - from).normalized() * 0.9, e)
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
	if e.target_player:
		var peye := p.pos.y + p.eye_height()
		if peye > e.pos.y + 1.6 + float(e.def.get("hover_y", 2.5)) * 0.5:
			e.vel.y += (0.3 - e.vel.y) * 0.3
		_face(e, p.pos, 0.5)
		if dist < 2.0:
			if e.attack_cd <= 0:
				if p.hurt(float(e.def.get("attack", 6.0)) * [0.0, 0.5, 1.0, 1.5][em.world.difficulty], "mob", false, e.pos, e):
					p.fire_ticks = maxi(p.fire_ticks, 100)
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
					var h := sqrt(sqrt(dist)) * 0.5
					var dirv := p.pos + Vector3(0, p.eye_height() * 0.5, 0) - from
					dirv += Vector3(rng.randfn(0, 1) * h * 2.297, 0, rng.randfn(0, 1) * h * 2.297)
					var kind := "wither_skull" if str(e.def.get("fireball", "")) == "wither_skull" else "small_fireball"
					Audio.play("entity.wither.shoot" if kind == "wither_skull" else "entity.blaze.shoot", e.pos, "Hostile")
					em.spawn_projectile(kind, from, dirv.normalized() * 0.8, e)
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
			var sp := (0.2 + 0.1 * e.size) * 0.5
			e.vel += Vector3(-sin(yr), 0, cos(yr)) * sp
			Audio.play("entity.%s.jump%s" % [e.id, "" if e.size > 1 else "_small"], e.pos, "Hostile")
	# contact damage (Java Slime.dealDamage: distance < 0.6 * size, small slimes harmless)
	var deals := e.size > 1 or magma
	if e.target_player and deals and e.attack_cd <= 0 and dist < 0.6 * e.size + 0.6:
		var dmg := float(e.def.get("attack", 4.0)) * float(e.size) / 4.0 * (1.5 if magma else 1.0)
		if p.hurt(maxf(dmg, 1.0) * [0.0, 0.5, 1.0, 1.5][em.world.difficulty], "mob", false, e.pos, e):
			e.attack_cd = 10
	em._physics(e, gs, blocks, 0.08 if fl == 0 else 0.02, 0.91 if fl == 0 else 0.8, 0.0)


## Shulker: stationary, homing bullets every 20..220 ticks while a target is within 16 blocks.
static func _shulker(em: EntityManager, e: EntityManager.Ent, p: Player, dist: float) -> void:
	e.vel = Vector3.ZERO
	if e.target_player and dist < 16.0:
		_face(e, p.pos, 0.5)
		e.charge -= 1
		if e.charge <= 0:
			e.charge = 20 + em.rng.randi_range(0, 9) * 20
			Audio.play("entity.shulker.shoot", e.pos, "Hostile")
			em.spawn_projectile("shulker_bullet", e.pos + Vector3(0, 1.2, 0), (p.pos - e.pos).normalized() * 0.15, e)


## Small flyers (bat, parrot, bee, allay, vex, phantom): free 3D wander near the spawn height; hostile flyers
## home in on the player (phantoms circle above, then swoop) and melee on contact.
static func _small_flyer(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float) -> void:
	var rng := em.rng
	var def: Dictionary = e.def
	var sp := float(def["speed"]) * 0.25
	var target := Vector3.INF
	if e.target_player:
		var peye := p.pos + Vector3(0, p.eye_height() * 0.6, 0)
		if def.get("swoops", false):
			e.charge += 1
			if e.charge % 200 < 140:
				var ang := e.charge * 0.05
				target = p.pos + Vector3(cos(ang) * 12.0, 14.0, sin(ang) * 12.0)
			else:
				target = peye
		else:
			target = peye
		if dist < 1.6 and e.attack_cd <= 0:
			p.hurt((float(def.get("attack", 2.0)) + HeldItems.attack_bonus(e)) * [0.0, 0.5, 1.0, 1.5][em.world.difficulty], "mob", false, e.pos, e)
			e.attack_cd = 20
			if def.get("swoops", false):
				e.charge = 0
	else:
		if not e.has_target or e.pos.distance_to(e.target_pos) < 1.0 or rng.randi_range(0, 99) == 0:
			e.target_pos = e.pos + Vector3(rng.randf_range(-7, 7), rng.randf_range(-3, 3), rng.randf_range(-7, 7))
			e.has_target = true
		target = e.target_pos
	var d := target - e.pos
	if d.length() > 0.3:
		e.vel += d.normalized() * sp * 0.25
		_face(e, target, 0.4)
	em._physics(e, gs, blocks, 0.0, 1.0, 0.0)
	e.vel *= 0.85


## Aquatic AI: in water no gravity, 3D wander inside water (hostiles chase; guardians charge a laser);
## out of water fish flop and dry out (Java AbstractFish/WaterAnimal air supply).
static func _swimmer(em: EntityManager, e: EntityManager.Ent, p: Player, gs: Callable, blocks: BlockRegistry, dist: float, fl: int) -> void:
	var rng := em.rng
	var def: Dictionary = e.def
	if fl == 1:
		e.charge = maxi(e.charge, 0)
		var target := Vector3.INF
		if e.target_player and p.in_water:
			if def.get("laser", false):
				if dist < 16.0 and _has_los(em, e.pos + Vector3(0, e.h * 0.5, 0), p.pos + Vector3(0, p.eye_height(), 0)):
					e.charge += 1
					_face(e, p.pos, 0.5)
					if e.charge >= 80:
						p.hurt(float(def.get("attack", 6.0)) * [0.0, 0.5, 1.0, 1.5][em.world.difficulty], "magic")
						e.charge = 0
				else:
					target = p.pos
			else:
				target = p.pos
				if dist < 1.5 and e.attack_cd <= 0:
					p.hurt((float(def.get("attack", 2.0)) + HeldItems.attack_bonus(e)) * [0.0, 0.5, 1.0, 1.5][em.world.difficulty], "mob", false, e.pos, e)
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