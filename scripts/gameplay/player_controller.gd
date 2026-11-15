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
var _in_scaffolding := false   # the climbable at the feet is scaffolding (sneaking descends instead of holding)
var _eyes_in_bubbles := false  # eyes in a bubble column (air refills)
var _soul_block_pos := Vector3i(0, -10000, 0)   # Soul Speed location_changed tracking
var _soul_t := 0                                 # Soul Speed periodic_tick counter (particles / sound every 5 ticks)
var crawling := false   # Java Pose.SWIMMING on land: neither standing nor crouching fits (height 0.6, eye 0.4)
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
var last_hurt := 0.0     # Java LivingEntity.lastHurt: the hit that started the damage immunity
var spawn_invuln := 0    # respawn protection ticks (kept from the earlier 50-tick window; no wiki value)
var dead := false
var fire_ticks := 0
var age := 0
var spawn_point := Vector3i(0, 80, 0)
var has_spawn := false
var sleeping := false            # Java Player.isSleeping (lying in a bed)
var sleep_counter := 0           # Java sleepCounter: 0..100 asleep, 100..110 waking up (screen fades)
var bed_pos := Vector3i.ZERO
var spawn_dim := "overworld"   # dimension of spawn_point (respawn anchors: the_nether)
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
var move_dist := 0.0   # Java Entity.moveDist / nextStep (step sounds)
var item_cooldowns: Dictionary = {}   # Java ItemCooldowns: item name -> [start tick, end tick] (ender pearl, chorus ...)
var _stuck := Vector3.ZERO   # Java Entity.stuckSpeedMultiplier (cobweb, sweet berry bush, powder snow)
var in_powder_snow := false
var ticks_frozen := 0        # Java Entity.ticksFrozen (powder snow; fully frozen at 140)
var next_step := 1.0
var fly_speed := 0.05
var spectator_speed := 1.0
# per-tick input (set by World from InputMap)
var in_forward := 0.0
var in_strafe := 0.0
var in_jump := false
var in_sneak := false
var in_sprint := false
var vehicle = null    # EntityManager.Ent being ridden (Taming)
var shoulder: Array = [{}, {}]   # parrots perched on the left / right shoulder (serialized mobs: MobBehaviors)
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
	if swimming or fall_flying or crawling:
		return 0.6
	return 1.5 if sneaking and not flying else 1.8


func eye_height() -> float:
	if sleeping:
		return 0.2   # Java Pose.SLEEPING eye height
	if swimming or fall_flying or crawling:
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


## Java Player.getCurrentItemAttackStrengthDelay: 20 / attack speed (ticks). Haste +10 %, Mining Fatigue -10 % attack
## speed per level (add_multiplied_total; wiki: Attribute, Haste).
func attack_delay() -> float:
	var h := inventory.held()
	var spd: float = 4.0 if h.is_empty() else Res.items.attack_speed[h.item]
	spd *= (1.0 + 0.1 * _effect_amp("haste")) * maxf(0.0, 1.0 - 0.1 * _effect_amp("mining_fatigue"))
	return 20.0 / maxf(0.1, spd)


## movement_speed attribute (wiki: Attribute): base 0.1 plus add_value bonuses (Soul Speed), then add_multiplied_total
## sprinting +30 %, Speed +20 % and Slowness -15 % per level.
func movement_speed(sprint: bool, add: float = 0.0) -> float:
	# Java LivingEntity.tryAddFrost: -0.05 x the frozen fraction (ADD_VALUE) while standing on a block
	if ticks_frozen > 0 and on_ground:
		add -= 0.05 * minf(1.0, ticks_frozen / 140.0)
	return (0.1 + add) * (1.3 if sprint else 1.0) * (1.0 + 0.2 * _effect_amp("speed")) * maxf(0.0, 1.0 - 0.15 * _effect_amp("slowness"))


func _survival_like() -> bool:
	return mode == Mode.SURVIVAL or mode == Mode.ADVENTURE


## Java Player.getAttackStrengthScale(partial).
func attack_strength(partial: float = 0.5) -> float:
	return clampf((attack_ticks + partial) / attack_delay(), 0.0, 1.0)


## Java LivingEntity.knockback(strength, x, z): strength x (1 - knockback resistance: armour, netherite 0.1 per piece);
## the motion halves and is pushed away from (x, z) (the attacker's offset); on the ground it also rises to at most 0.4.
func knockback(strength: float, from_x: float, from_z: float) -> void:
	strength *= 1.0 - inventory.knockback_resistance()
	if strength <= 0.0:
		return
	var d := Vector2(from_x, from_z)
	if d.length_squared() < 1.0e-5:
		return
	d = d.normalized() * strength
	vel = Vector3(vel.x / 2.0 - d.x, minf(0.4, vel.y / 2.0 + strength) if on_ground else vel.y, vel.z / 2.0 - d.y)


## Java ItemCooldowns.addCooldown / isOnCooldown / getCooldownPercent (the white hotbar overlay).
func add_cooldown(item_name: String, ticks: int) -> void:
	item_cooldowns[item_name] = [age, age + ticks]


func on_cooldown(item_name: String) -> bool:
	return item_cooldowns.has(item_name)


func cooldown_percent(item_name: String, partial: float = 0.0) -> float:
	var c = item_cooldowns.get(item_name)
	if c == null:
		return 0.0
	return clampf((float(c[1]) - (float(age) + partial)) / float(maxi(1, int(c[1]) - int(c[0]))), 0.0, 1.0)


func tick(w) -> void:
	age += 1
	attack_ticks += 1
	inventory.tick_pop()
	if not item_cooldowns.is_empty():
		for k in item_cooldowns.keys():
			if age >= int(item_cooldowns[k][1]):
				item_cooldowns.erase(k)
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
		# Java LivingEntity.baseTick counts hurtTime down while dying too: frozen at 10, the hurt tilt
		# sin(((10 - partialTick) / 10)^4 pi) swung with every frame's partial tick (the death screen shook wildly)
		if hurt_time > 0:
			hurt_time -= 1
		if invuln > 0:
			invuln -= 1
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
	# wiki Crawling (Java Player.updatePlayerPose): when neither the standing (1.8) nor the crouching (1.5) hitbox fits -
	# a trapdoor closing above, a 1-block gap - the player crawls (0.6 tall, eyes 0.4) at the sneaking speed
	crawling = false
	if not flying and not fall_flying and not sleeping and vehicle == null and not (eyes_in_water and in_water) and not is_spectator():
		crawling = Collision.overlaps_any(Vector3(pos.x - 0.3, pos.y, pos.z - 0.3), Vector3(pos.x + 0.3, pos.y + 1.5, pos.z + 0.3), gs, blocks)
	if sneaking or crawling:
		# sneaking_speed attribute 0.3, Swift Sneak +0.15 per level (26.3 enchantment data; wiki: Attribute)
		var sneak_mul := clampf(0.3 + 0.15 * Loot._ench(inventory.get_slot(Inventory.ARMOR0 + 1), "swift_sneak"), 0.0, 1.0)
		fwd *= sneak_mul
		strafe *= sneak_mul
	if using_slot >= 0 and vehicle == null:
		fwd *= 0.2
		strafe *= 0.2
	# wiki Sprinting: no sprinting at food 6 or below or under Blindness; a wall stops it, except sprint-swimming
	var blind := effects.has("blindness")
	if in_sprint and fwd > 0.0 and not sneaking and (food > 6 or mode == Mode.CREATIVE or flying) and not hcollide and not blind:
		sprinting = true
	if fwd <= 0.0 or (hcollide and not flying and not swimming) or (food <= 6 and mode != Mode.CREATIVE and not flying) or using_slot >= 0 or blind:
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
	_check_inside(w, gs, blocks)
	_survival_tick(w, gs, blocks)
	var hv := Vector2(pos.x - prev_pos.x, pos.z - prev_pos.z).length()
	walk_dist += hv
	walk_phase += hv * 0.6
	# Java Player.aiStep: bob eases towards min(0.1, horizontal speed) on the ground, towards 0 otherwise
	var bf := minf(0.1, Vector2(vel.x, vel.z).length()) if on_ground and not dead and not swimming else 0.0
	bob += (bf - bob) * 0.4
	if hv > 0.0 and _survival_like():
		# wiki Hunger: swimming 0.01 / m, sprinting 0.1 / m (Sprinting: only while on the ground)
		if in_water:
			exhaustion += 0.01 * hv
		elif sprinting and on_ground:
			exhaustion += 0.1 * hv
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
		vel += look * 0.1 + (look * 1.5 - vel) * 0.5   # sparks: the attached rocket entity
	var before := Vector2(vel.x, vel.z).length()
	_move(vel, gs, blocks, 0.6)
	if hcollide:
		var after := Vector2(vel.x, vel.z).length()
		var dmg := (before - after) * 10.0 - 3.0
		if dmg > 0.0:
			Audio.play("entity.player.big_fall" if dmg > 4.0 else "entity.player.small_fall", pos, "Players")
			hurt(dmg, "fly_into_wall")
	fly_ticks += 1
	if (fly_ticks + 1) % 20 == 0 and _survival_like():
		var c := inventory.get_slot(Inventory.ARMOR0 + 2)
		var unb := Loot._ench(c, "unbreaking")
		if unb <= 0 or randf() < 1.0 / (unb + 1):
			c.damage += 1
			inventory.set_slot(Inventory.ARMOR0 + 2, c)
	if vel.y > -0.5:
		fall_distance = 1.0


## Java Entity.checkInsideBlocks -> Block.entityInside for every block the hitbox (deflated 1e-5) touches, and
## stepOn for the block under the feet (wiki values):
## - cobweb: stuck (0.25, 0.05, 0.25), Weaving (0.5, 0.25, 0.5); sweet berry bush: stuck (0.8, 0.75, 0.8) and 1 damage
##   when moving (>= 0.003 per tick) at age >= 1; powder snow: stuck (0.9, 1.5, 0.9) with the feet in it, freezing;
##   being stuck resets the fall distance
## - fire 1 / soul fire 2 damage (in_fire) and 8 s of burning; cactus 1; lit campfire 1 / soul campfire 2; wither rose
##   Wither for 2 s (not on Peaceful); magma block (stepOn, not sneaking) 1 hot_floor. Frost Walker boots are immune to
##   #burn_from_stepping (campfire, hot_floor; 26.3 enchantment data)
func _check_inside(w, gs: Callable, blocks: BlockRegistry) -> void:
	if mode == Mode.SPECTATOR:
		in_powder_snow = false
		return
	in_powder_snow = false
	var mn := aabb_min() + Vector3(1.0e-5, 1.0e-5, 1.0e-5)
	var mx := aabb_max() - Vector3(1.0e-5, 1.0e-5, 1.0e-5)
	var feet := Vector3i(int(floor(pos.x)), int(floor(pos.y)), int(floor(pos.z)))
	var boots := inventory.get_slot(Inventory.ARMOR0)
	var frost_walker := Loot._ench(boots, "frost_walker") > 0
	var moved := absf(pos.x - prev_pos.x) >= 0.003 or absf(pos.z - prev_pos.z) >= 0.003
	for x in range(int(floor(mn.x)), int(floor(mx.x)) + 1):
		for z in range(int(floor(mn.z)), int(floor(mx.z)) + 1):
			for y in range(int(floor(mn.y)), int(floor(mx.y)) + 1):
				var st: int = gs.call(x, y, z)
				if st <= 0:
					continue
				match blocks.name_of(st):
					"cobweb":
						_stuck = Vector3(0.5, 0.25, 0.5) if effects.has("weaving") else Vector3(0.25, 0.05, 0.25)
						fall_distance = 0.0
					"sweet_berry_bush":
						_stuck = Vector3(0.8, 0.75, 0.8)
						fall_distance = 0.0
						if int(blocks.get_prop(st, "age")) > 0 and moved:
							hurt(1.0, "sweet_berry_bush")
					"powder_snow":
						in_powder_snow = true
						if Vector3i(x, y, z) == feet:
							_stuck = Vector3(0.9, 1.5, 0.9)
							fall_distance = 0.0
					"fire", "soul_fire":
						if _effect_amp("fire_resistance") == 0:
							fire_ticks = maxi(fire_ticks, 160)
						hurt(2.0 if blocks.name_of(st) == "soul_fire" else 1.0, "in_fire")
					"cactus":
						hurt(1.0, "cactus")
					"campfire", "soul_campfire":
						if blocks.get_prop(st, "lit") == "true" and not frost_walker:
							hurt(2.0 if blocks.name_of(st) == "soul_campfire" else 1.0, "campfire")
					"wither_rose":
						if int(w.difficulty) > 0:
							add_effect("wither", 0, 40)
	if on_ground and not sneaking and not frost_walker:
		var below: int = maxi(0, gs.call(int(floor(pos.x)), int(floor(pos.y - 0.2)), int(floor(pos.z))))
		if below > 0 and blocks.name_of(below) == "magma_block":
			hurt(1.0, "hot_floor")
		elif below > 0 and blocks.name_of(below).ends_with("redstone_ore") and w != null and w.has_method("set_block"):
			Interaction.redstone_ore_interact(w, Vector3i(int(floor(pos.x)), int(floor(pos.y - 0.2)), int(floor(pos.z))), below)
	# Java LivingEntity.aiStep: +1 frozen tick in powder snow (unless wearing leather: #freeze_immune_wearables), else -2;
	# fully frozen (140) takes 1 freeze damage every 40 ticks
	var can_freeze := true
	for i in 4:
		var a := inventory.get_slot(Inventory.ARMOR0 + i)
		if not a.is_empty() and Tags.items("freeze_immune_wearables").has(a.name()):
			can_freeze = false
	if in_powder_snow and can_freeze:
		ticks_frozen = mini(140, ticks_frozen + 1)
		fire_ticks = 0
	else:
		ticks_frozen = maxi(0, ticks_frozen - 2)
	if ticks_frozen >= 140 and can_freeze and age % 40 == 0:
		hurt(1.0, "freeze")


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
	_eyes_in_bubbles = eyes_in_water and blocks.name_of(est) == "bubble_column"
	var fst: int = gs.call(int(floor(pos.x)), int(floor(pos.y)), int(floor(pos.z)))
	_in_scaffolding = false
	if fst > 0 and (blocks.st_flags[fst] & BlockRegistry.F_CLIMB):
		on_climbable = true
		_in_scaffolding = blocks.name_of(fst) == "scaffolding"


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
	# Java Entity.move: a stuck multiplier from the last tick's blocks scales this move and stops the motion
	if _stuck.length_squared() > 1.0e-7:
		m *= _stuck
		_stuck = Vector3.ZERO
		vel = Vector3.ZERO
	var r := Collision.move(aabb_min(), aabb_max(), m, gs, blocks, step, on_ground, _ccache)
	var mv: Vector3 = r["motion"]
	pos += mv
	_step_sounds(mv, gs, blocks)
	hcollide = r["hit_x"] or r["hit_z"]
	var landed: bool = r["on_ground"]
	if r["hit_x"]:
		vel.x = 0.0
	if r["hit_z"]:
		vel.z = 0.0
	# Java Entity.checkFallDamage: the downward movement counts first (the landing tick too), then a grounded entity
	# lands (Block.fallOn) and its fall distance resets
	if mv.y < 0.0:
		fall_distance -= mv.y
	if r["hit_y"]:
		if m.y < 0.0 and fall_distance > 0.0:
			_land(gs, blocks)
		vel.y = 0.0
	on_ground = landed
	if on_ground:
		fall_distance = 0.0


## Java Entity.applyMovementEmissionAndPlaySound + Player.playStepSound: moveDist grows by 0.6 x the distance moved
## (horizontal; full 3D on climbables); past nextStep (int(moveDist) + 1) a step sounds from the block 0.2 below the
## feet (a fence / wall / gate under an air gap counts): volume x 0.15 at the sound type's pitch, or the carpet /
## snow layer / plant at the feet (#combination_step_sound_blocks: that x 0.15 + the block below x 0.05 at pitch x 0.8;
## #inside_step_sound_blocks: that block alone). In water: the swim sound + a muffled step (x 0.05, pitch x 0.8).
## Silent while flying or sneaking on the ground (Player.getMovementEmission), riding or swimming (sprint-swim).
func _step_sounds(mv: Vector3, gs: Callable, blocks: BlockRegistry) -> void:
	if flying or vehicle != null or (on_ground and sneaking) or mode == Mode.SPECTATOR:
		return
	var op := Vector3i(int(floor(pos.x)), int(floor(pos.y - 0.2)), int(floor(pos.z)))
	var st: int = maxi(0, gs.call(op.x, op.y, op.z))
	if st == 0:
		var below: int = maxi(0, gs.call(op.x, op.y - 1, op.z))
		var bn := blocks.name_of(below)
		if below > 0 and (Tags.has_block("fences", bn) or Tags.has_block("walls", bn) or Tags.has_block("fence_gates", bn)):
			op.y -= 1
			st = below
	var climb := on_climbable
	move_dist += (mv.length() if climb else Vector2(mv.x, mv.z).length()) * 0.6
	if move_dist <= next_step or st == 0:
		return
	if not (on_ground or climb or (sneaking and mv.y == 0.0)) or swimming:
		if in_water:
			next_step = float(int(move_dist) + 1)
			_swim_sound()
		return
	next_step = float(int(move_dist) + 1)
	if in_water:
		_swim_sound()
		_play_step(st, op, 0.05, 0.8)
		return
	var up_st: int = maxi(0, gs.call(op.x, op.y + 1, op.z))
	var un := blocks.name_of(up_st)
	if up_st > 0 and Tags.has_block("combination_step_sound_blocks", un):
		_play_step(up_st, op + Vector3i.UP, 1.0, 1.0)
		_play_step(st, op, 0.05 / 0.15, 0.8)
	elif up_st > 0 and Tags.has_block("inside_step_sound_blocks", un):
		_play_step(up_st, op + Vector3i.UP, 1.0, 1.0)
	else:
		_play_step(st, op, 1.0, 1.0)


func _play_step(st: int, at: Vector3i, vol_k: float, pitch_k: float) -> void:
	var info: Dictionary = Res.blocks.block_info[Res.blocks.st_block[st]]
	var vp: Array = BlockProperties.sound_volume_pitch(str(info["sound"]))
	Audio.play(BlockProperties.sound_event(str(info["sound"]), "step"), pos, "Players", float(vp[0]) * 0.15 * vol_k, float(vp[1]) * pitch_k)


## Java Entity.waterSwimSound: volume min(1, sqrt(vx^2 x 0.2 + vy^2 + vz^2 x 0.2) x 0.35), pitch 1 +- 0.4.
func _swim_sound() -> void:
	var v := minf(1.0, sqrt(vel.x * vel.x * 0.2 + vel.y * vel.y + vel.z * vel.z * 0.2) * 0.35)
	Audio.play("entity.player.swim", pos, "Players", v, 1.0 + (randf() - randf()) * 0.4)


func _land(gs: Callable, blocks: BlockRegistry) -> void:
	var below := _block_below(gs, blocks)
	var name := blocks.name_of(below)
	# Block.fallOn overrides: hay bale / honey block damage x 0.2, beds half the distance, slime none unless sneaking,
	# pointed dripstone tip up: distance + 2.5, damage x 2 (wiki Damage#Fall damage)
	var mult := 1.0
	var dist := fall_distance
	if name == "hay_block" or name == "honey_block":
		mult = 0.2
	elif name.ends_with("_bed"):
		dist *= 0.5
	elif name == "slime_block" and not sneaking:
		mult = 0.0
	elif name == "pointed_dripstone" and blocks.get_prop(below, "vertical_direction") == "up" and blocks.get_prop(below, "thickness") == "tip":
		dist += 2.5
		mult = 2.0
	if in_water or flying or mode == Mode.CREATIVE or mode == Mode.SPECTATOR or _effect_amp("slow_falling") > 0:
		mult = 0.0
	# Java LivingEntity.calculateFallDamage: floor((fallDistance + 1e-6 - safe_fall_distance) * multiplier); the
	# safe_fall_distance attribute is 3, +1 per Jump Boost level
	var dmg := floorf((dist + 1.0e-6 - 3.0 - _effect_amp("jump_boost")) * mult)
	if dmg > 0.0:
		# Java LivingEntity.causeFallDamage: the small (<= 4) / big fall sound at 1.0 / 1.0, then the damage
		Audio.play("entity.player.big_fall" if dmg > 4.0 else "entity.player.small_fall", pos, "Players")
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
		if _survival_like():
			exhaustion += 0.2 if sprinting else 0.05
		if w.has_method("on_jump"):
			w.on_jump(self)
	elif not in_jump:
		jump_delay = 0
	var spf := float(info["speed"])
	# Soul Speed on #soul_speed_blocks (26.3 enchantment data; wiki: Attribute): movement_speed +0.0405 +0.0105 per
	# level above I, movement_efficiency 1 (no soul sand slowdown); 4 % chance to damage the boots per block moved
	var soul := 0.0
	if on_ground and vehicle == null:
		var bname := blocks.name_of(below)
		if bname == "soul_sand" or bname == "soul_soil":
			var boots := inventory.get_slot(Inventory.ARMOR0)
			var ss := Loot._ench(boots, "soul_speed")
			if ss > 0:
				soul = 0.0405 + 0.0105 * (ss - 1)
				spf = 1.0
				var bp := Vector3i(floori(pos.x), floori(pos.y), floori(pos.z))
				if bp != _soul_block_pos and _survival_like() and randf() < 0.04:
					var unb := Loot._ench(boots, "unbreaking")
					if unb <= 0 or randf() < 1.0 / (unb + 1):
						boots.damage += 1
						inventory.set_slot(Inventory.ARMOR0, boots if boots.damage < Res.items.max_damage[boots.item] else ItemStack.new())
				_soul_block_pos = bp
				# 26.3 soul_speed enchantment effects: every 5th tick while moving horizontally, a soul particle in the
				# bounding box (0.1 up, rising 0.1, -0.2 x the horizontal motion) and a 35 % particle.soul_escape (volume
				# 0.6, pitch 0.6 - 1.0)
				_soul_t += 1
				if _soul_t % 5 == 0 and Vector2(vel.x, vel.z).length_squared() > 1.0e-6:
					Particles.emit("soul", pos + Vector3(randf_range(-0.3, 0.3), 0.1, randf_range(-0.3, 0.3)), Vector3(-vel.x * 0.2, 0.1, -vel.z * 0.2))
					if randf() < 0.35:
						Audio.play("particle.soul_escape", pos, "Players", 0.6, randf_range(0.6, 1.0))
	var spd := movement_speed(sprinting, soul)
	# Java getFrictionInfluencedSpeed uses the raw block friction (slipperiness), drag uses friction*0.91
	var accel := spd * (0.21600002 / (slip * slip * slip)) if on_ground else (0.025999999 if sprinting else 0.02)
	vel += _input_vector(fwd, strafe, accel)
	if on_climbable:
		vel.x = clampf(vel.x, -0.15, 0.15)
		vel.z = clampf(vel.z, -0.15, 0.15)
		vel.y = maxf(vel.y, -0.15)
		# wiki Sneaking: sneaking holds on ladders / vines, but descends in scaffolding
		if sneaking and vel.y < 0.0 and not _in_scaffolding:
			vel.y = 0.0
		fall_distance = 0.0
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
	var spd := 0.02   # sprint-swimming: 0.02 * 0.98 / (1 - 0.9) = 3.92 m/s (wiki Swimming: ~3.918 m/s)
	if not lava:
		# Depth Strider: water_movement_efficiency 1/3 per level (max 1; 26.3 enchantment data), halved off the ground,
		# pulls drag towards 0.546 and the acceleration towards movement_speed; Dolphin's Grace drag 0.96. Matches the
		# wiki speeds: Depth Strider III = walking speed on the bottom (Depth Strider), 5.305 m/s sprint-swimming
		# (Swimming); Dolphin's Grace 9.8 m/s, 18.783 / 27.767 / 36.75 m/s with Depth Strider I-III (Dolphin's Grace)
		var h := minf(1.0, Loot._ench(inventory.get_slot(Inventory.ARMOR0), "depth_strider") / 3.0)
		if not on_ground:
			h *= 0.5
		if h > 0.0:
			drag += (0.546 - drag) * h
			spd += (movement_speed(sprinting) - spd) * h
		if _effect_amp("dolphins_grace") > 0:
			drag = 0.96
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
	# water resets the fall distance, lava halves it every tick (wiki Damage#Fall damage)
	fall_distance = fall_distance * 0.5 if lava else 0.0


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


## wiki Effect: a higher level overwrites a lower one, a longer duration of the same level overwrites a shorter one; a
## weaker effect with a longer duration stays hidden and returns when the stronger one ends. Instant Health heals
## 2 x 2^level, Instant Damage deals 3 x 2^level (Instant Health, Damage); Absorption adds 4 per level (Absorption).
func add_effect(id: String, amp: int, ticks: int) -> void:
	if id == "instant_health":
		heal(float(4 << amp))
		return
	if id == "instant_damage":
		hurt(float(6 << amp), "magic", true)
		return
	var cur = effects.get(id)
	if cur is Dictionary:
		var ca := int(cur["amp"])
		var ct := int(cur["ticks"])
		if amp < ca or (amp == ca and ticks <= ct):
			if amp < ca and ticks > ct:
				var hd = cur.get("hidden")
				if not (hd is Dictionary) or int(hd["ticks"]) < ticks:
					cur["hidden"] = {"amp": amp, "ticks": ticks}
			return
		if amp == ca:
			cur["ticks"] = ticks
			return
		var ne := {"amp": amp, "ticks": ticks}
		if ct > ticks:
			ne["hidden"] = cur
		effects[id] = ne
	else:
		effects[id] = {"amp": amp, "ticks": ticks}
	if id == "absorption":
		absorption = maxf(absorption, 4.0 * (amp + 1))
	elif id == "glowing":
		GlowOutline.wake()   # (third-person outline of the player model)


func _survival_tick(w, gs: Callable, blocks: BlockRegistry) -> void:
	if hurt_time > 0:
		hurt_time -= 1
	if invuln > 0:
		invuln -= 1
	if spawn_invuln > 0:
		spawn_invuln -= 1
	for id in effects.keys():
		var e: Dictionary = effects[id]
		e["ticks"] = int(e["ticks"]) - 1
		var hd = e.get("hidden")
		if hd is Dictionary:
			hd["ticks"] = int(hd["ticks"]) - 1
		if id == "regeneration" and age % maxi(1, 50 >> int(e["amp"])) == 0:
			heal(1.0)
		elif id == "poison" and age % maxi(1, 25 >> int(e["amp"])) == 0 and health > 1.0:
			hurt(1.0, "magic", true)
		elif id == "wither" and age % maxi(1, 40 >> int(e["amp"])) == 0:
			hurt(1.0, "wither", true)
		elif id == "hunger":
			exhaustion += 0.005 * (int(e["amp"]) + 1)
		elif id == "saturation":
			# wiki Saturation (effect): +1 food and +2 saturation per level every tick
			var sp := int(e["amp"]) + 1
			food = mini(20, food + sp)
			saturation = minf(float(food), saturation + 2.0 * sp)
		elif id == "absorption" and absorption <= 0.0:
			e["ticks"] = 0   # wiki Absorption: the effect is removed once its hearts are gone
			hd = null
		if int(e["ticks"]) <= 0:
			if hd is Dictionary and int(hd["ticks"]) > 0:
				effects[id] = hd
			else:
				effects.erase(id)
	# wiki Health Boost: +4 max health per level, removed with the effect; Absorption hearts vanish with the effect
	max_health = 20.0 + 4.0 * _effect_amp("health_boost")
	health = minf(health, max_health)
	absorption = clampf(absorption, 0.0, 4.0 * _effect_amp("absorption"))
	# wiki Void: below 64 blocks under the dimension's minimum Y (-128 in the Overworld, -64 in the Nether / End)
	var dt = w.get("dim_type") if w is Object else null
	var min_y := float(dt.get("min_y", Coords.MIN_Y)) if dt is Dictionary else float(Coords.MIN_Y)
	if pos.y < min_y - 64.0:
		hurt(4.0, "out_of_world", true)
	if mode == Mode.CREATIVE or mode == Mode.SPECTATOR:
		air = 300
		fire_ticks = 0
		return
	# air / drowning: Water Breathing or Conduit Power keep (and refill) the air, as does a bubble column (wiki Conduit
	# Power, Damage#Drowning); Respiration: no air lost with chance level / (level + 1) (wiki Respiration)
	var helmet := inventory.get_slot(Inventory.ARMOR0 + 3)
	if not helmet.is_empty() and helmet.name() == "turtle_helmet" and not eyes_in_water:
		add_effect("water_breathing", 0, 200)   # wiki Turtle Shell: 10 s of Water Breathing, recharged in air
	var breathe := _effect_amp("water_breathing") > 0 or _effect_amp("conduit_power") > 0 or _eyes_in_bubbles
	if eyes_in_water and not breathe and _effect_amp("breath_of_the_nautilus") > 0:
		pass   # wiki Nautilus: Breath of the Nautilus (riding one) pauses the oxygen bar underwater
	elif eyes_in_water and not breathe:
		var resp := Loot._ench(helmet, "respiration")
		if resp <= 0 or randf() < 1.0 / (resp + 1):
			air -= 1
		if air <= -20:
			# Java LivingEntity.baseTick: 8 bubbles around the body with the entity's motion, then 2 drowning damage
			air = 0
			for bi in 8:
				Particles.emit("bubble", pos + Vector3(randf() - randf(), randf() - randf(), randf() - randf()), vel)
			hurt(2.0, "drown")
	else:
		air = mini(300, air + 4)
	# lava / fire: lava sets 15 s (300 ticks) of fire and deals 4 (wiki Lava); Fire Protection shortens burn time 15 % per
	# level, stacking over the armour pieces (wiki Fire Protection); water and rain put the fire out (wiki Fire)
	if in_lava:
		var fp := 0
		for i in 4:
			fp += Loot._ench(inventory.get_slot(Inventory.ARMOR0 + i), "fire_protection")
		fire_ticks = int(300.0 * maxf(0.0, 1.0 - 0.15 * fp))
		hurt(4.0, "lava")
	if fire_ticks > 0:
		if in_water or (w.has_method("weather_at") and w.weather_at(pos) == "rain"):
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


## 26.3 damage type tags (data/minecraft/tags/damage_type; "mob" = mob_attack). #bypasses_armor is also the set of
## damage types with 0 food exhaustion (data/minecraft/damage_type/*.json "exhaustion").
const FIRE_SOURCES := ["in_fire", "campfire", "on_fire", "lava", "hot_floor", "sulfur_cube_hot", "unattributed_fireball", "fireball"]
const EXPLOSION_SOURCES := ["fireworks", "explosion", "player_explosion", "bad_respawn_point"]
const PROJECTILE_SOURCES := ["arrow", "trident", "mob_projectile", "unattributed_fireball", "fireball", "wither_skull", "thrown", "wind_charge"]
const FALL_SOURCES := ["fall", "ender_pearl", "stalagmite"]
const BYPASS_ARMOR := ["on_fire", "in_wall", "cramming", "drown", "fly_into_wall", "generic", "wither", "dragon_breath", "starve",
	"fall", "ender_pearl", "freeze", "stalagmite", "magic", "indirect_magic", "out_of_world", "generic_kill", "sonic_boom", "outside_border"]
const BYPASS_INVULNERABILITY := ["out_of_world", "generic_kill"]   # also #bypasses_resistance


## Total enchantment protection factor of the worn armour against a damage source (26.3 enchantment data:
## protection / fire_protection / blast_protection / projectile_protection / feather_falling damage_protection effects;
## #bypasses_invulnerability (void, kill), #bypasses_effects (starving) and #bypasses_enchantments (sonic boom) get none).
func _enchant_protection(source: String) -> float:
	if source in BYPASS_INVULNERABILITY or source == "starve" or source == "sonic_boom":
		return 0.0
	var epf := 0.0
	for i in 4:
		var a := inventory.get_slot(Inventory.ARMOR0 + i)
		if a.is_empty():
			continue
		epf += Loot._ench(a, "protection")
		if source in FIRE_SOURCES:
			epf += 2.0 * Loot._ench(a, "fire_protection")
		if source in EXPLOSION_SOURCES:
			epf += 2.0 * Loot._ench(a, "blast_protection")
		if source in PROJECTILE_SOURCES:
			epf += 2.0 * Loot._ench(a, "projectile_protection")
		if source in FALL_SOURCES:
			epf += 3.0 * Loot._ench(a, "feather_falling")
	return epf


## from: damage source position (shield blocking); attacker: the mob for shield knockback / axe disabling.
func hurt(amount: float, source: String, bypass_armor: bool = false, from: Vector3 = Vector3.INF, attacker = null) -> bool:
	# Java LivingEntity.hurtServer: a dead / dying entity takes no more damage (void ticks on a dead player restarted the
	# hurt tilt and red flash every tick - violent flashing on the death screen)
	if dead:
		return false
	# wiki Void: the void still kills in Creative and Spectator (#bypasses_invulnerability)
	var bypass_inv: bool = source in BYPASS_INVULNERABILITY
	if (mode == Mode.CREATIVE or mode == Mode.SPECTATOR or spawn_invuln > 0) and not bypass_inv:
		return false
	if UseItem.try_block(self, amount, source, from, attacker):
		return false
	# wiki Fire Resistance / Damage: no damage from fire sources (#is_fire)
	if source in FIRE_SOURCES and _effect_amp("fire_resistance") > 0:
		return false
	# wiki Damage: 10 ticks of damage immunity after a hit; a bigger hit meanwhile deals only the difference and does
	# not restart the timer (26.3 #bypasses_cooldown is empty: void, drowning and starving obey it too)
	var dmg := amount
	var fresh := invuln <= 10
	if not fresh:
		if amount <= last_hurt:
			return false
		dmg = amount - last_hurt
	last_hurt = amount
	# wiki Armor: reduction min(20, max(armor / 5, armor - 4 damage / (toughness + 8))) / 25; #bypasses_armor skips it
	if not bypass_armor and not (source in BYPASS_ARMOR):
		var armor := float(inventory.armor_points())
		var tough := inventory.armor_toughness()
		var f := clampf(armor - dmg / (2.0 + tough / 4.0), armor * 0.2, 20.0)
		dmg = dmg * (1.0 - f / 25.0)
	# wiki Resistance: 20 % per level, not against void / kill (#bypasses_resistance) or starving (#bypasses_effects)
	var res := _effect_amp("resistance")
	if res > 0 and not bypass_inv and source != "starve":
		dmg *= maxf(0.0, 1.0 - 0.2 * res)
	# Java LivingEntity.getDamageAfterMagicAbsorb: armour enchantments' damage protection (Protection 1 / level, Fire,
	# Blast, Projectile Protection 2 / level, Feather Falling 3 / level for their damage), capped at 20, 4 % each
	var epf := _enchant_protection(source)
	if epf > 0.0 and dmg > 0.0:
		dmg *= 1.0 - clampf(epf, 0.0, 20.0) / 25.0
	if absorption > 0.0:
		var a := minf(absorption, dmg)
		absorption -= a
		dmg -= a
	health -= dmg
	# wiki Totem of Undying: no protection from the void or /kill
	if health <= 0.0 and not bypass_inv and _use_totem():
		health = 1.0
	if fresh:
		hurt_time = 10
		invuln = 20
		# Java LivingEntity.indicateDamage: hurtDir = atan2(dz, dx) - yRot (no source position: 0)
		hurt_dir = (rad_to_deg(atan2(from.z - pos.z, from.x - pos.x)) - yaw) if from != Vector3.INF else 0.0
	if sleeping:
		sleeping = false   # Java LivingEntity.hurt: damage wakes a sleeper (InBedScreen closes itself)
		sleep_counter = 100
	last_damage_source = source
	last_attacker_id = str(attacker.id) if attacker != null and "id" in attacker else ""
	# damage type exhaustion (26.3 data): 0.1, or 0 for the #bypasses_armor types (wiki Hunger: armor-protectable damage)
	if not (source in BYPASS_ARMOR) and _survival_like():
		exhaustion += 0.1
	if health <= 0.0:
		health = 0.0
		dead = true
		Audio.play("entity.player.death", pos, "Players", 1.0, 1.0 + (randf() - randf()) * 0.2)
	elif fresh:
		# Java LivingEntity.playHurtSound: Player.getHurtSound per damage type, volume 1, pitch 1 +- 0.2
		var hs := {"on_fire": "entity.player.hurt_on_fire", "in_fire": "entity.player.hurt_on_fire", "drown": "entity.player.hurt_drown",
			"sweet_berry_bush": "entity.player.hurt_sweet_berry_bush", "freeze": "entity.player.hurt_freeze"}.get(source, "entity.player.hurt")
		Audio.play(hs, pos, "Players", 1.0, 1.0 + (randf() - randf()) * 0.2)
	return true


## Java LivingEntity.checkTotemDeathProtection: a totem in either hand (main first) saves the player.
func _use_totem() -> bool:
	for slot in [inventory.selected, Inventory.OFFHAND]:
		var s := inventory.get_slot(slot)
		if not s.is_empty() and s.name() == "totem_of_undying":
			s.count -= 1
			inventory.set_slot(slot, s if s.count > 0 else ItemStack.new())
			# wiki Totem of Undying: clears all effects, then Regeneration II 45 s, Absorption II 5 s, Fire Resistance 40 s
			effects.clear()
			absorption = 0.0
			add_effect("regeneration", 1, 900)
			add_effect("absorption", 1, 100)
			add_effect("fire_resistance", 0, 800)
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
	# wiki Golden Apple / Enchanted Golden Apple / Pufferfish (item) / Poison / Hunger (effect)
	if nm == "golden_apple":
		add_effect("regeneration", 1, 100)
		add_effect("absorption", 0, 2400)
	elif nm == "enchanted_golden_apple":
		add_effect("regeneration", 1, 400)
		add_effect("absorption", 3, 2400)
		add_effect("resistance", 0, 6000)
		add_effect("fire_resistance", 0, 6000)
	elif nm == "rotten_flesh" and randf() < 0.8:
		add_effect("hunger", 0, 600)
	elif nm == "chicken" and randf() < 0.3:
		add_effect("hunger", 0, 600)
	elif nm == "spider_eye":
		add_effect("poison", 0, 100)
	elif nm == "pufferfish":
		add_effect("hunger", 2, 300)
		add_effect("poison", 1, 1200)
		add_effect("nausea", 0, 300)
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
	max_health = 20.0
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
	invuln = 0
	last_hurt = 0.0
	spawn_invuln = 50


func to_dict() -> Dictionary:
	return {"pos": [pos.x, pos.y, pos.z], "rot": [yaw, pitch], "vel": [vel.x, vel.y, vel.z], "mode": int(mode),
		"health": health, "food": food, "sat": saturation, "exh": exhaustion, "air": air, "xp": [xp_level, xp_progress, xp_total],
		"fire": fire_ticks, "flying": flying, "inv": inventory.to_array(), "sel": inventory.selected, "effects": effects,
		"spawn": [spawn_point.x, spawn_point.y, spawn_point.z, has_spawn, spawn_dim], "fall": fall_distance, "abs": absorption, "stats": stats, "dead": dead,
		"shoulder": shoulder}


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
	spawn_dim = str(sp[4]) if sp.size() > 4 else "overworld"
	fall_distance = float(d.get("fall", 0.0))
	absorption = float(d.get("abs", 0.0))
	stats = d.get("stats", {})
	dead = bool(d.get("dead", false))
	var sh = d.get("shoulder", [{}, {}])
	shoulder = sh if sh is Array and sh.size() == 2 else [{}, {}]
