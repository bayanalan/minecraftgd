## Player — first-person player simulation at 20 TPS with Java-style movement: input*0.98, ground
## acceleration 0.1*(0.216/f^3) (f = slipperiness*0.91), air 0.02 (sprint 0.026), gravity 0.08, drag 0.98,
## jump 0.42 (+0.2 sprint boost), step-up 0.6, sneak edge guard, ladders, swimming/buoyancy, creative and
## spectator flight; survival stats (health, food/saturation/exhaustion, air, fall damage, XP).
## Contract: tick(world) once per game tick; pos is feet-centre in WORLD coords; render via interp(alpha).
## Hitbox: 0.6 x 1.8 (sneak 1.5, swim 0.6); eye 1.62 (sneak 1.27, swim 0.4).
class_name Player
extends RefCounted

enum Mode { SURVIVAL, CREATIVE, ADVENTURE, SPECTATOR }

var pos := Vector3(0, 100, 0)
var prev_pos := Vector3(0, 100, 0)
var vel := Vector3.ZERO
var yaw := 0.0      # Java degrees: 0 = +Z (south), 90 = -X (west)
var pitch := 0.0    # positive = looking down
var on_ground := false
var was_on_ground := false
var hcollide := false
var sneaking := false
var sprinting := false
var flying := false
var swimming := false
var in_water := false
var in_lava := false
var eyes_in_water := false
var on_climbable := false
var jump_delay := 0
var fall_distance := 0.0
var mode := Mode.SURVIVAL
var health := 20.0
var max_health := 20.0
var absorption := 0.0
var food := 20
var saturation := 5.0
var exhaustion := 0.0
var food_timer := 0
var air := 300
var xp_level := 0
var xp_progress := 0.0
var xp_total := 0
var enchant_seed := randi()   # Java Player.enchantmentSeed (re-rolled after each enchant)
var hurt_time := 0
var hurt_dir := 0.0      # Java LivingEntity.hurtDir: damage source direction relative to the yaw (camera tilt axis)
var death_ticks := 0     # Java deathTime (dying camera tilt)
var invuln := 0
var dead := false
var fire_ticks := 0
var age := 0
var spawn_point := Vector3i(0, 80, 0)
var has_spawn := false
var sleeping := false            # Java Player.isSleeping (lying in a bed)
var sleep_counter := 0           # Java sleepCounter: 0..100 asleep, 100..110 waking up (screen fades)
var bed_pos := Vector3i.ZERO
var bed_facing := "south"
var inventory := Inventory.new()
var effects: Dictionary = {}   # effect id -> {amp, ticks}
var last_damage_source := ""
var last_attacker_id := ""   # entity id of the last attacker (death message "slain by")
var stats: Dictionary = {}
var bob := 0.0          # Java Player.bob: view-bobbing amplitude, smoothed (0 off the ground)
var prev_bob := 0.0
var walk_phase := 0.0   # Java Entity.walkDist: 0.6 * horizontal distance moved (bobbing phase)
var prev_walk_phase := 0.0
var walk_dist := 0.0
var fly_speed := 0.05
var spectator_speed := 1.0
# per-tick input (set by World from InputMap)
var in_forward := 0.0
var in_strafe := 0.0
var in_jump := false
var in_sneak := false
var in_sprint := false
var vehicle = null    # EntityManager.Ent being ridden (Taming)
# item use (UseItem): inventory slot being used, its item id, ticks used; shield disabled ticks (axe hit)
var fall_flying := false       # elytra gliding (Java isFallFlying)
var fly_ticks := 0
var rocket_ticks := 0           # firework boost left (attached FireworkRocketEntity life)
var totem_anim := 0             # HUD item activation animation (Java displayItemActivation, 40 ticks)
var _was_jump := false
var attack_ticks := 100        # Java attackStrengthTicker (ticks since the last swing / item change)
var _last_main := -1
var using_slot := -1
var use_item := 0
var use_ticks := 0
var shield_cooldown := 0


var _ccache: Array = [PackedInt32Array(), PackedFloat32Array()]   # Collision.gather cache

func width() -> float:
	return 0.6


func height() -> float:
	if swimming or fall_flying:
		return 0.6
	return 1.5 if sneaking and not flying else 1.8


func eye_height() -> float:
	if sleeping:
		return 0.2   # Java Pose.SLEEPING eye height
	if swimming or fall_flying:
		return 0.4
	return 1.27 if sneaking and not flying else 1.62


func aabb_min(p: Vector3 = pos) -> Vector3:
	return Vector3(p.x - 0.3, p.y, p.z - 0.3)


func aabb_max(p: Vector3 = pos) -> Vector3:
	return Vector3(p.x + 0.3, p.y + height(), p.z + 0.3)


func eye_pos() -> Vector3:
	return pos + Vector3(0, eye_height(), 0)


func look_dir() -> Vector3:
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	return Vector3(-sin(yr) * cos(pr), -sin(pr), cos(yr) * cos(pr))


func is_creative() -> bool:
	return mode == Mode.CREATIVE


func is_spectator() -> bool:
	return mode == Mode.SPECTATOR


func can_fly() -> bool:
	return mode == Mode.CREATIVE or mode == Mode.SPECTATOR


func interp_pos(alpha: float) -> Vector3:
	return prev_pos.lerp(pos, alpha)


func block_reach() -> float:
	return 5.0 if mode == Mode.CREATIVE else 4.5


## Java Player.getCurrentItemAttackStrengthDelay: 20 / attack speed (ticks).
func attack_delay() -> float:
	var h := inventory.held()
	var spd: float = 4.0 if h.is_empty() else Res.items.attack_speed[h.item]
	return 20.0 / maxf(0.1, spd)


## Java Player.getAttackStrengthScale(partial).
func attack_strength(partial: float = 0.5) -> float:
	return clampf((attack_ticks + partial) / attack_delay(), 0.0, 1.0)


func tick(w) -> void:
	age += 1
	attack_ticks += 1
	var mh := inventory.held()
	var mk := mh.item * 1000 + mh.count if not mh.is_empty() else -1
	if mk / 1000 != _last_main / 1000:
		attack_ticks = 0   # Java resetAttackStrengthTicker when the main-hand item changes
	_last_main = mk
	prev_pos = pos
	prev_bob = bob
	prev_walk_phase = walk_phase
	if dead:
		vehicle = null
		death_ticks += 1
		sleeping = false
		return
	death_ticks = 0
	# Java Player.tick: sleep counter up to 100 in bed, then 100 -> 110 after waking (fade out)
	if sleeping:
		sleep_counter = mini(sleep_counter + 1, 100)
		vel = Vector3.ZERO
		prev_pos = pos
		return
	elif sleep_counter > 0:
		sleep_counter += 1
		if sleep_counter >= 110:
			sleep_counter = 0
	if vehicle != null:
		if vehicle.dead:
			vehicle = null
		elif in_sneak:
			Taming.dismount(w.entities, self)
		else:
			_survival_tick(w, w.state_at, Res.blocks)
			return   # the mount moves this player (Taming.seat)
	var gs: Callable = w.state_at
	var blocks: BlockRegistry = Res.blocks
	if mode == Mode.SPECTATOR:
		flying = true
	elif mode != Mode.CREATIVE:
		flying = false
	# environment probes
	_probe_fluids(gs, blocks)
	# input shaping
	var fwd := in_forward * 0.98
	var strafe := in_strafe * 0.98
	var want_sneak := in_sneak and not flying
	if sneaking and not want_sneak:
		# can we stand up?
		if not Collision.overlaps_any(Vector3(pos.x - 0.3, pos.y, pos.z - 0.3), Vector3(pos.x + 0.3, pos.y + 1.8, pos.z + 0.3), gs, blocks):
			sneaking = false
	else:
		sneaking = want_sneak
	if sneaking:
		fwd *= 0.3
		strafe *= 0.3
	if using_slot >= 0 and vehicle == null:
		fwd *= 0.2
		strafe *= 0.2
	if in_sprint and fwd > 0.0 and not sneaking and (food > 6 or mode == Mode.CREATIVE or flying) and not hcollide:
		sprinting = true
	if fwd <= 0.0 or (hcollide and not flying) or (food <= 6 and mode != Mode.CREATIVE and not flying) or using_slot >= 0:
		sprinting = false
	swimming = sprinting and eyes_in_water and in_water
	if jump_delay > 0:
		jump_delay -= 1
	# chunk not ready: freeze to avoid falling into unloaded terrain
	if not w.column_ready(pos.x, pos.z):
		vel = Vector3.ZERO
		return
	# Java LocalPlayer.aiStep: jump pressed in mid-air with a usable elytra starts gliding
	var jump_edge := in_jump and not _was_jump
	_was_jump = in_jump
	if jump_edge and not on_ground and not fall_flying and not flying and not in_water and not in_lava and not on_climbable and vehicle == null and elytra_ok():
		fall_flying = true
		fly_ticks = 0
	if fall_flying and (on_ground or in_water or in_lava or flying or vehicle != null or not elytra_ok()):
		fall_flying = false
		rocket_ticks = 0
	if totem_anim > 0:
		totem_anim -= 1
	if flying:
		_travel_fly(fwd, strafe, gs, blocks)
	elif fall_flying:
		_travel_elytra(gs, blocks)
	elif in_water or in_lava:
		_travel_fluid(fwd, strafe, gs, blocks)
	else:
		_travel_ground(fwd, strafe, gs, blocks, w)
	_survival_tick(w, gs, blocks)
	var hv := Vector2(pos.x - prev_pos.x, pos.z - prev_pos.z).length()
	walk_dist += hv
	walk_phase += hv * 0.6
	# Java Player.aiStep: bob eases towards min(0.1, horizontal speed) on the ground, towards 0 otherwise
	var bf := minf(0.1, Vector2(vel.x, vel.z).length()) if on_ground and not dead and not swimming else 0.0
	bob += (bf - bob) * 0.4
	if hv > 0.0 and mode == Mode.SURVIVAL:
		if sprinting:
			exhaustion += 0.1 * hv
		elif in_water:
			exhaustion += 0.01 * hv
	if on_ground and not was_on_ground and w.has_method("on_land"):
		w.on_land(self)
	was_on_ground = on_ground


func elytra_ok() -> bool:
	var c := inventory.get_slot(Inventory.ARMOR0 + 2)
	return not c.is_empty() and c.name() == "elytra" and c.damage < Res.items.max_damage[c.item] - 1


## Java LivingEntity.travelFallFlying / updateFallFlyingMovement, firework boost (FireworkRocketEntity.tick),
## FLY_INTO_WALL damage, elytra durability every 20 ticks.
func _travel_elytra(gs: Callable, blocks: BlockRegistry) -> void:
	var look := look_dir()
	var pr := deg_to_rad(pitch)
	var horiz := sqrt(look.x * look.x + look.z * look.z)
	var hvel := Vector2(vel.x, vel.z).length()
	var g := 0.01 if effects.has("slow_falling") and vel.y <= 0.0 else 0.08
	var f := cos(pr)
	f = f * f * minf(1.0, look.length() / 0.4)
	vel.y += g * (-1.0 + f * 0.75)
	if vel.y < 0.0 and horiz > 0.0:
		var d := vel.y * -0.1 * f
		vel += Vector3(look.x * d / horiz, d, look.z * d / horiz)
	if pr < 0.0 and horiz > 0.0:
		var d2 := hvel * -sin(pr) * 0.04
		vel += Vector3(-look.x * d2 / horiz, d2 * 3.2, -look.z * d2 / horiz)
	if horiz > 0.0:
		vel += Vector3((look.x / horiz * hvel - vel.x) * 0.1, 0.0, (look.z / horiz * hvel - vel.z) * 0.1)
	vel *= Vector3(0.99, 0.98, 0.99)
	if rocket_ticks > 0:
		rocket_ticks -= 1
		vel += look * 0.1 + (look * 1.5 - vel) * 0.5
		if rocket_ticks % 2 == 0:
			Particles.emit("firework", pos - look * 0.5, Vector3(randf_range(-0.05, 0.05), -0.05, randf_range(-0.05, 0.05)), Color.WHITE)
	var before := Vector2(vel.x, vel.z).length()
	_move(vel, gs, blocks, 0.6)
	if hcollide:
		var after := Vector2(vel.x, vel.z).length()
		var dmg := (before - after) * 10.0 - 3.0
		if dmg > 0.0:
			Audio.play("entity.player.big_fall" if dmg > 4.0 else "entity.player.small_fall", pos, "Players")
			hurt(dmg, "fly_into_wall")
	fly_ticks += 1
	if (fly_ticks + 1) % 20 == 0 and mode == Mode.SURVIVAL:
		var c := inventory.get_slot(Inventory.ARMOR0 + 2)
		var unb := Loot._ench(c, "unbreaking")
		if unb <= 0 or randf() < 1.0 / (unb + 1):
			c.damage += 1
			inventory.set_slot(Inventory.ARMOR0 + 2, c)
	if vel.y > -0.5:
		fall_distance = 1.0


func _probe_fluids(gs: Callable, blocks: BlockRegistry) -> void:
	in_water = false
	in_lava = false
	on_climbable = false
	var mn := aabb_min() + Vector3(0.001, 0.001, 0.001)
	var mx := aabb_max() - Vector3(0.001, 0.001, 0.001)
	for x in range(int(floor(mn.x)), int(floor(mx.x)) + 1):
		for z in range(int(floor(mn.z)), int(floor(mx.z)) + 1):
			for y in range(int(floor(mn.y)), int(floor(mx.y)) + 1):
				var st: int = gs.call(x, y, z)
				if st <= 0:
					continue
				var fl := blocks.st_flags[st]
				if fl & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED):
					var top := y + (0.889 if blocks.st_level[st] == 0 else (8.0 - blocks.st_level[st]) / 9.0)
					if top > mn.y:
						if fl & BlockRegistry.F_LAVA:
							in_lava = true
						else:
							in_water = true
	var est: int = gs.call(int(floor(pos.x)), int(floor(pos.y + eye_height())), int(floor(pos.z)))
	eyes_in_water = est > 0 and (blocks.st_flags[est] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and (blocks.st_flags[est] & BlockRegistry.F_LAVA) == 0
	var fst: int = gs.call(int(floor(pos.x)), int(floor(pos.y)), int(floor(pos.z)))
	if fst > 0 and (blocks.st_flags[fst] & BlockRegistry.F_CLIMB):
		on_climbable = true


func _input_vector(fwd: float, strafe: float, speed: float) -> Vector3:
	var v := Vector3(strafe, 0, fwd)
	var l2 := v.length_squared()
	if l2 < 1.0e-7:
		return Vector3.ZERO
	if l2 > 1.0:
		v = v.normalized()
	v *= speed
	var s := sin(deg_to_rad(yaw))
	var c := cos(deg_to_rad(yaw))
	return Vector3(v.x * c - v.z * s, 0, v.z * c + v.x * s)


func _block_below(gs: Callable, blocks: BlockRegistry) -> int:
	var st: int = gs.call(int(floor(pos.x)), int(floor(pos.y - 0.5000001)), int(floor(pos.z)))
	return maxi(st, 0)


func _move(m: Vector3, gs: Callable, blocks: BlockRegistry, step: float) -> void:
	if mode == Mode.SPECTATOR:
		pos += m
		on_ground = false
		hcollide = false
		return
	# sneak edge guard (Java maybeBackOffFromEdge)
	if sneaking and on_ground and m.y <= 0.0:
		var probe := 0.05
		while absf(m.x) > 0.0 and not Collision.overlaps_any(aabb_min(pos + Vector3(m.x, -0.6, 0)), aabb_max(pos + Vector3(m.x, -0.6, 0)) - Vector3(0, height() - 0.59, 0), gs, blocks):
			m.x = 0.0 if absf(m.x) < probe else m.x - signf(m.x) * probe
		while absf(m.z) > 0.0 and not Collision.overlaps_any(aabb_min(pos + Vector3(0, -0.6, m.z)), aabb_max(pos + Vector3(0, -0.6, m.z)) - Vector3(0, height() - 0.59, 0), gs, blocks):
			m.z = 0.0 if absf(m.z) < probe else m.z - signf(m.z) * probe
	var r := Collision.move(aabb_min(), aabb_max(), m, gs, blocks, step, on_ground, _ccache)
	var mv: Vector3 = r["motion"]
	pos += mv
	hcollide = r["hit_x"] or r["hit_z"]
	var landed: bool = r["on_ground"]
	if r["hit_x"]:
		vel.x = 0.0
	if r["hit_z"]:
		vel.z = 0.0
	if r["hit_y"]:
		if m.y < 0.0 and fall_distance > 0.0:
			_land(gs, blocks)
		vel.y = 0.0
	on_ground = landed
	if not on_ground and mv.y < 0.0:
		fall_distance -= mv.y
	elif on_ground:
		fall_distance = 0.0


func _land(gs: Callable, blocks: BlockRegistry) -> void:
	var below := _block_below(gs, blocks)
	var name := blocks.name_of(below)
	var mult := 1.0
	if name == "hay_block":
		mult = 0.2
	elif name == "slime_block" or name.ends_with("_bed"):
		mult = 0.0 if name == "slime_block" and not sneaking else 0.5
	elif name == "honey_block":
		mult = 0.2
	if in_water or flying or mode == Mode.CREATIVE or mode == Mode.SPECTATOR:
		mult = 0.0
	var dmg := ceilf((fall_distance - 3.0) * mult)
	if dmg > 0.0:
		hurt(dmg, "fall")
	fall_distance = 0.0


func _travel_ground(fwd: float, strafe: float, gs: Callable, blocks: BlockRegistry, w) -> void:
	var below := _block_below(gs, blocks)
	var info: Dictionary = blocks.block_info[blocks.st_block[below]]
	var slip := float(info["friction"]) if on_ground else 1.0
	var f := slip * 0.91 if on_ground else 0.91
	# jumping
	if in_jump and on_ground and jump_delay == 0:
		var jf := float(info["jump"])
		vel.y = 0.42 * jf + _effect_amp("jump_boost") * 0.1
		if sprinting:
			var yr := deg_to_rad(yaw)
			vel.x -= sin(yr) * 0.2
			vel.z += cos(yr) * 0.2
		jump_delay = 10
		if mode == Mode.SURVIVAL:
			exhaustion += 0.2 if sprinting else 0.05
		if w.has_method("on_jump"):
			w.on_jump(self)
	elif not in_jump:
		jump_delay = 0
	var spd := 0.1 * (1.3 if sprinting else 1.0) * (1.0 + 0.2 * _effect_amp("speed")) * maxf(0.0, 1.0 - 0.15 * _effect_amp("slowness"))
	# Java getFrictionInfluencedSpeed uses the raw block friction (slipperiness), drag uses friction*0.91
	var accel := spd * (0.21600002 / (slip * slip * slip)) if on_ground else (0.025999999 if sprinting else 0.02)
	vel += _input_vector(fwd, strafe, accel)
	if on_climbable:
		vel.x = clampf(vel.x, -0.15, 0.15)
		vel.z = clampf(vel.z, -0.15, 0.15)
		vel.y = maxf(vel.y, -0.15)
		if sneaking and vel.y < 0.0:
			vel.y = 0.0
		fall_distance = 0.0
	var spf := float(info["speed"])
	var m := vel
	if spf < 1.0 and on_ground:
		m.x *= spf
		m.z *= spf
	_move(m, gs, blocks, 0.6)
	if on_climbable and (hcollide or in_jump):
		vel.y = 0.2
	if _effect_amp("levitation") > 0:
		vel.y += (0.05 * _effect_amp("levitation") - vel.y) * 0.2
	else:
		vel.y -= 0.01 if (_effect_amp("slow_falling") > 0 and vel.y < 0.0) else 0.08
	vel.y *= 0.98
	vel.x *= f
	vel.z *= f


func _travel_fluid(fwd: float, strafe: float, gs: Callable, blocks: BlockRegistry) -> void:
	var lava := in_lava and not in_water
	var drag := 0.5 if lava else (0.9 if sprinting else 0.8)
	var spd := 0.02
	if swimming:
		spd = 0.04
	vel += _input_vector(fwd, strafe, spd)
	if swimming:
		var ld := look_dir()
		vel.y += (ld.y * 0.08 - vel.y) * (0.06 if ld.y < -0.2 else 0.1)
	if in_jump:
		vel.y += 0.04
	elif sneaking:
		vel.y -= 0.04
	_move(vel, gs, blocks, 0.6 if on_ground else 0.0)
	vel *= Vector3(drag, 0.8 if not lava else 0.5, drag)
	vel.y -= 0.02 if lava else (0.005 if not swimming else 0.0)
	if hcollide and in_jump:
		vel.y = 0.3
	fall_distance = 0.0


func _travel_fly(fwd: float, strafe: float, gs: Callable, blocks: BlockRegistry) -> void:
	var fs := fly_speed * (2.0 if sprinting else 1.0)
	if mode == Mode.SPECTATOR:
		fs *= spectator_speed
	if in_jump:
		vel.y += fly_speed * 3.0
	if in_sneak:
		vel.y -= fly_speed * 3.0
	vel += _input_vector(fwd, strafe, fs)
	_move(vel, gs, blocks, 0.0)
	vel.y *= 0.6
	vel.x *= 0.91
	vel.z *= 0.91
	if on_ground and mode == Mode.CREATIVE:
		flying = false
	fall_distance = 0.0


func _effect_amp(id: String) -> int:
	var e = effects.get(id)
	return int(e["amp"]) + 1 if e is Dictionary else 0


func add_effect(id: String, amp: int, ticks: int) -> void:
	effects[id] = {"amp": amp, "ticks": ticks}


func _survival_tick(w, gs: Callable, blocks: BlockRegistry) -> void:
	if hurt_time > 0:
		hurt_time -= 1
	if invuln > 0:
		invuln -= 1
	for id in effects.keys():
		var e: Dictionary = effects[id]
		e["ticks"] = int(e["ticks"]) - 1
		if id == "regeneration" and age % maxi(1, 50 >> int(e["amp"])) == 0:
			heal(1.0)
		elif id == "poison" and age % maxi(1, 25 >> int(e["amp"])) == 0 and health > 1.0:
			hurt(1.0, "magic", true)
		elif id == "wither" and age % maxi(1, 40 >> int(e["amp"])) == 0:
			hurt(1.0, "wither", true)
		elif id == "hunger":
			exhaustion += 0.005 * (int(e["amp"]) + 1)
		if int(e["ticks"]) <= 0:
			effects.erase(id)
	if pos.y < Coords.MIN_Y - 64:
		hurt(4.0, "out_of_world", true)
	if mode == Mode.CREATIVE or mode == Mode.SPECTATOR:
		air = 300
		fire_ticks = 0
		return
	# air / drowning
	if eyes_in_water and _effect_amp("water_breathing") == 0:
		air -= 1
		if air <= -20:
			air = 0
			hurt(2.0, "drown")
	else:
		air = mini(300, air + 4)
	# lava / fire
	if in_lava:
		fire_ticks = 300
		hurt(4.0, "lava")
	if fire_ticks > 0:
		if in_water:
			fire_ticks = 0
		else:
			fire_ticks -= 1
			if fire_ticks % 20 == 0 and _effect_amp("fire_resistance") == 0:
				hurt(1.0, "on_fire")
	# suffocation
	var head: int = gs.call(int(floor(pos.x)), int(floor(pos.y + eye_height())), int(floor(pos.z)))
	if head > 0 and (blocks.st_flags[head] & BlockRegistry.F_OPAQUE) and (blocks.st_flags[head] & BlockRegistry.F_FULL_SHAPE):
		if age % 10 == 0:
			hurt(1.0, "in_wall")
	# food
	var diff: int = w.difficulty
	if exhaustion > 4.0:
		exhaustion -= 4.0
		if saturation > 0.0:
			saturation = maxf(0.0, saturation - 1.0)
		elif diff != 0:
			food = maxi(0, food - 1)
	var regen: bool = w.gamerule("naturalRegeneration", true)
	if diff == 0 and age % 20 == 0:
		if health < max_health:
			heal(1.0)
		if food < 20 and age % 200 == 0:
			food += 1
	if regen and saturation > 0.0 and food >= 20 and health < max_health:
		food_timer += 1
		if food_timer >= 10:
			var amt := minf(saturation, 6.0)
			heal(amt / 6.0)
			exhaustion += amt
			food_timer = 0
	elif regen and food >= 18 and health < max_health:
		food_timer += 1
		if food_timer >= 80:
			heal(1.0)
			exhaustion += 6.0
			food_timer = 0
	elif food <= 0:
		food_timer += 1
		if food_timer >= 80:
			if health > 10.0 or diff >= 3 or (health > 1.0 and diff == 2):
				hurt(1.0, "starve", true)
			food_timer = 0
	else:
		food_timer = 0


func heal(a: float) -> void:
	health = minf(max_health, health + a)


## from: damage source position (shield blocking); attacker: the mob for shield knockback / axe disabling.
func hurt(amount: float, source: String, bypass_armor: bool = false, from: Vector3 = Vector3.INF, attacker = null) -> bool:
	# Java LivingEntity.hurtServer: a dead / dying entity takes no more damage (void ticks on a dead player restarted the
	# hurt tilt and red flash every tick - violent flashing on the death screen)
	if dead:
		return false
	if mode == Mode.CREATIVE or mode == Mode.SPECTATOR:
		if source != "out_of_world" or mode == Mode.SPECTATOR:
			return false
	if UseItem.try_block(self, amount, source, from, attacker):
		return false
	if invuln > 10 and source != "out_of_world" and source != "starve" and source != "drown":
		return false
	var dmg := amount
	if source in ["on_fire", "lava", "in_fire"] and _effect_amp("fire_resistance") > 0:
		return false
	if not bypass_armor and not (source in ["fall", "drown", "starve", "out_of_world", "magic", "wither", "fly_into_wall"]):
		var armor := float(inventory.armor_points())
		var tough := inventory.armor_toughness()
		var f := clampf(armor - dmg / (2.0 + tough / 4.0), armor * 0.2, 20.0)
		dmg = dmg * (1.0 - f / 25.0)
	var res := _effect_amp("resistance")
	if res > 0:
		dmg *= maxf(0.0, 1.0 - 0.2 * res)
	if absorption > 0.0:
		var a := minf(absorption, dmg)
		absorption -= a
		dmg -= a
	health -= dmg
	if health <= 0.0 and source != "out_of_world" and _use_totem():
		health = 1.0
	hurt_time = 10
	invuln = 20
	if sleeping:
		sleeping = false   # Java LivingEntity.hurt: damage wakes a sleeper (InBedScreen closes itself)
		sleep_counter = 100
	# Java LivingEntity.indicateDamage: hurtDir = atan2(dz, dx) - yRot (no source position: 0)
	hurt_dir = (rad_to_deg(atan2(from.z - pos.z, from.x - pos.x)) - yaw) if from != Vector3.INF else 0.0
	last_damage_source = source
	last_attacker_id = str(attacker.id) if attacker != null and "id" in attacker else ""
	exhaustion += 0.1
	if health <= 0.0:
		health = 0.0
		dead = true
	return true


## Java LivingEntity.checkTotemDeathProtection: a totem in either hand (main first) saves the player.
func _use_totem() -> bool:
	for slot in [inventory.selected, Inventory.OFFHAND]:
		var s := inventory.get_slot(slot)
		if not s.is_empty() and s.name() == "totem_of_undying":
			s.count -= 1
			inventory.set_slot(slot, s if s.count > 0 else ItemStack.new())
			effects.clear()
			add_effect("regeneration", 1, 900)
			add_effect("absorption", 1, 100)
			add_effect("fire_resistance", 0, 800)
			absorption = maxf(absorption, 8.0)
			totem_anim = 40
			Audio.play("item.totem.use", pos, "Players")
			for i in 40:
				var c := Color(0.55 + randf() * 0.4, 0.75 + randf() * 0.2, 0.1 + randf() * 0.2) if randf() < 0.75 else Color(0.95, 0.85, 0.3)
				Particles.emit("totem_of_undying", pos + Vector3(randf_range(-0.5, 0.5), randf() * 1.8, randf_range(-0.5, 0.5)), Vector3(randf_range(-0.6, 0.6), randf_range(0.2, 0.9), randf_range(-0.6, 0.6)), c)
			stats["used.totem_of_undying"] = int(stats.get("used.totem_of_undying", 0)) + 1
			return true
	return false


func eat(item: int) -> bool:
	var n: int = Res.items.food_nutrition[item]
	if n <= 0:
		return false
	if food >= 20 and mode != Mode.CREATIVE and not Res.items.names[item] in ["golden_apple", "enchanted_golden_apple", "chorus_fruit", "honey_bottle", "milk_bucket"]:
		return false
	food = mini(20, food + n)
	saturation = minf(float(food), saturation + n * Res.items.food_saturation[item] * 0.0 + Res.items.food_saturation[item])
	var nm: String = Res.items.names[item]
	if nm == "golden_apple":
		add_effect("regeneration", 1, 100)
		absorption = maxf(absorption, 4.0)
	elif nm == "enchanted_golden_apple":
		add_effect("regeneration", 1, 400)
		add_effect("resistance", 0, 6000)
		add_effect("fire_resistance", 0, 6000)
		absorption = maxf(absorption, 16.0)
	elif nm == "rotten_flesh" and randf() < 0.8:
		add_effect("hunger", 0, 600)
	elif nm == "spider_eye" or nm == "pufferfish":
		add_effect("poison", 0 if nm == "spider_eye" else 1, 100 if nm == "spider_eye" else 1200)
	elif nm == "poisonous_potato" and randf() < 0.6:
		add_effect("poison", 0, 100)
	return true


func add_xp(points: int) -> void:
	xp_total += points
	var p := float(points)
	while p > 0.0:
		var need := xp_to_next()
		var room := (1.0 - xp_progress) * need
		if p >= room:
			p -= room
			xp_level += 1
			xp_progress = 0.0
		else:
			xp_progress += p / need
			p = 0.0


func xp_to_next() -> float:
	if xp_level >= 30:
		return 112.0 + (xp_level - 30) * 9.0
	if xp_level >= 15:
		return 37.0 + (xp_level - 15) * 5.0
	return 7.0 + xp_level * 2.0


func respawn(at: Vector3) -> void:
	vehicle = null
	pos = at
	prev_pos = at
	vel = Vector3.ZERO
	health = max_health
	food = 20
	saturation = 5.0
	exhaustion = 0.0
	air = 300
	fire_ticks = 0
	fall_distance = 0.0
	effects.clear()
	absorption = 0.0
	dead = false
	invuln = 60


func to_dict() -> Dictionary:
	return {"pos": [pos.x, pos.y, pos.z], "rot": [yaw, pitch], "vel": [vel.x, vel.y, vel.z], "mode": int(mode),
		"health": health, "food": food, "sat": saturation, "exh": exhaustion, "air": air, "xp": [xp_level, xp_progress, xp_total],
		"fire": fire_ticks, "flying": flying, "inv": inventory.to_array(), "sel": inventory.selected, "effects": effects,
		"spawn": [spawn_point.x, spawn_point.y, spawn_point.z, has_spawn], "fall": fall_distance, "abs": absorption, "stats": stats, "dead": dead}


func from_dict(d: Dictionary) -> void:
	var p: Array = d.get("pos", [0, 100, 0])
	pos = Vector3(p[0], p[1], p[2])
	prev_pos = pos
	var r: Array = d.get("rot", [0, 0])
	yaw = r[0]
	pitch = r[1]
	var v: Array = d.get("vel", [0, 0, 0])
	vel = Vector3(v[0], v[1], v[2])
	mode = int(d.get("mode", 0)) as Mode
	health = float(d.get("health", 20))
	food = int(d.get("food", 20))
	saturation = float(d.get("sat", 5))
	exhaustion = float(d.get("exh", 0))
	air = int(d.get("air", 300))
	var xp: Array = d.get("xp", [0, 0.0, 0])
	xp_level = int(xp[0])
	xp_progress = float(xp[1])
	xp_total = int(xp[2])
	fire_ticks = int(d.get("fire", 0))
	flying = bool(d.get("flying", false))
	inventory.from_array(d.get("inv", []))
	inventory.selected = int(d.get("sel", 0))
	effects = d.get("effects", {})
	var sp: Array = d.get("spawn", [0, 80, 0, false])
	spawn_point = Vector3i(sp[0], sp[1], sp[2])
	has_spawn = bool(sp[3])
	fall_distance = float(d.get("fall", 0.0))
	absorption = float(d.get("abs", 0.0))
	stats = d.get("stats", {})
	dead = bool(d.get("dead", false))
