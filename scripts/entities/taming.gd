## Taming / riding — Java TamableAnimal (wolf, cat: tame food with 1/3 chance, sit toggle, FollowOwnerGoal start 10 /
## teleport beyond 12 blocks, wolves OwnerHurtByTarget/OwnerHurtTarget, tamed wolf health 40), AbstractHorse
## (RunAroundLikeCrazyGoal: 1/50 per tick nextInt(maxTemper=100) < temper -> tamed, else temper +5 and the rider is
## thrown; temper food; saddles; rider-controlled travel: forward input (backwards x0.25), strafe x0.5, ground
## accel = speed * 0.216/0.546^3, air x0.1, jump 0.7), saddled pigs/striders steered with carrot/warped fungus on a
## stick, camels (saddle only), happy ghasts (harness, flying).
## APPROXIMATE: fixed per-species speed/jump (no random attributes), no jump charge bar, no horse armor/chests,
## no sitting pose, riding is single-player only (LAN clients cannot ride).
class_name Taming
extends RefCounted

# rider feet height above the mount's feet (standing player model; Java uses a sitting pose)
const SEAT := {"horse": 0.75, "donkey": 0.6, "mule": 0.65, "skeleton_horse": 0.75, "zombie_horse": 0.75, "camel": 1.45,
	"pig": 0.15, "strider": 0.95, "llama": 0.6, "trader_llama": 0.6, "happy_ghast": 3.8}
const NEEDS_TAMING := ["horse", "donkey", "mule", "llama", "trader_llama", "skeleton_horse", "zombie_horse"]
const SADDLE_ONLY := ["pig", "strider", "camel"]
const STEER_ITEM := {"pig": "carrot_on_a_stick", "strider": "warped_fungus_on_a_stick"}
const TEMPER_FOOD := {"sugar": 3, "wheat": 3, "apple": 3, "hay_block": 3, "golden_carrot": 5, "golden_apple": 10, "enchanted_golden_apple": 10}
const BREED_FOOD := ["golden_carrot", "golden_apple", "enchanted_golden_apple"]


static func owner_name() -> String:
	return Net.my_name if Net.active() else "Player"


static func is_tamed(e) -> bool:
	return e.data.has("owner")


## Right-click on a mob (local player). Returns true when handled.
static func interact(em, e, p: Player, held: ItemStack) -> bool:
	var def: Dictionary = e.def
	var nm := "" if held.is_empty() else held.name()
	if def.has("tame_food"):
		return _pet_interact(em, e, p, held, nm)
	if not SEAT.has(e.id) or e.baby_age < 0:
		return false
	if nm == "chest" and e.id in ["donkey", "mule", "llama", "trader_llama"] and is_tamed(e) and not bool(e.data.get("chest", false)):
		e.data["chest"] = true
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("entity.donkey.chest", e.pos, "Neutral")
		return true
	if p.sneaking and is_tamed(e) and e.id in NEEDS_TAMING:
		open_inventory(em, e)
		return true
	if nm == "saddle" and not bool(e.data.get("saddle", false)) and (is_tamed(e) or e.id in SADDLE_ONLY):
		e.data["saddle"] = true
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("entity.horse.saddle" if e.id != "pig" else "entity.pig.saddle", e.pos, "Neutral")
		return true
	if e.id == "happy_ghast" and nm.ends_with("_harness") and not e.data.has("harness"):
		e.data["harness"] = nm
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	if e.id in NEEDS_TAMING and TEMPER_FOOD.has(nm) and not (is_tamed(e) and nm in BREED_FOOD):
		e.data["temper"] = mini(100, int(e.data.get("temper", 0)) + int(TEMPER_FOOD[nm]))
		e.hp = minf(float(def["hp"]), e.hp + 2.0)
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("entity.horse.eat", e.pos, "Neutral")
		return true
	if p.sneaking or p.vehicle != null:
		return false
	if e.id in SADDLE_ONLY and not bool(e.data.get("saddle", false)):
		return false
	if e.id == "happy_ghast" and not e.data.has("harness"):
		return false
	mount(em, e, p)
	return true


static func _pet_interact(em, e, p: Player, held: ItemStack, nm: String) -> bool:
	var def: Dictionary = e.def
	var tame_food: Array = [def["tame_food"]] if def["tame_food"] is String else def["tame_food"]
	if e.id == "cat":
		tame_food = ["cod", "salmon"]
	if not is_tamed(e):
		if not tame_food.has(nm) or e.baby_age < 0 and e.id != "wolf":
			return false
		if not p.is_creative():
			p.inventory.consume_held()
		if em.rng.randi_range(0, 2) == 0:
			e.data["owner"] = owner_name()
			e.data["sitting"] = true
			e.persistent = true
			e.angry = false
			e.target_player = false
			if e.id == "wolf":
				e.data["max_hp"] = 40.0
				e.hp = 40.0
			Audio.play("entity.%s.ambient" % e.id, e.pos, "Neutral")
			em.spawn_hearts(e.pos + Vector3(0, e.h, 0))
		else:
			Audio.play("entity.%s.ambient" % e.id, e.pos, "Neutral", 0.5)
		return true
	if str(e.data["owner"]) != owner_name():
		return false
	var food: Array = def.get("food", [])
	if food.has(nm) and e.hp < float(e.data.get("max_hp", def["hp"])):
		e.hp = minf(float(e.data.get("max_hp", def["hp"])), e.hp + maxf(1.0, float(Res.items.food_nutrition[held.item])))
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	if food.has(nm):
		return false   # breeding
	e.data["sitting"] = not bool(e.data.get("sitting", false))
	e.has_target = false
	e.vel = Vector3(0, e.vel.y, 0)
	return true


static func open_inventory(em, e) -> void:
	var hs = load("res://scripts/ui/horse_screen.gd").new()
	hs.mount = e
	em.world.open_screen(hs)


static func mount(_em, e, p: Player) -> void:
	p.vehicle = e
	p.vel = Vector3.ZERO
	p.sneaking = false
	if e.kind == "cushion":
		Audio.play("entity.cushion.sit", e.pos, "Players")
	elif e.kind == "mob":
		Audio.play("entity.horse.saddle" if e.id != "pig" else "entity.pig.saddle", e.pos, "Players", 0.4)


static func dismount(em, p: Player) -> void:
	var e = p.vehicle
	p.vehicle = null
	if e == null or e.dead:
		return
	if e.kind == "cushion":
		Audio.play("entity.cushion.get_up", e.pos, "Players")
	var yr := deg_to_rad(e.yaw)
	var side: Vector3 = Vector3(cos(yr), 0, sin(yr)) * (float(e.w) * 0.5 + 0.5)
	var gs: Callable = em.world.state_at
	for cand in [e.pos + side, e.pos - side, e.pos + Vector3(0, e.h, 0)]:
		var q: Vector3 = cand
		if not Collision.overlaps_any(Vector3(q.x - 0.3, q.y, q.z - 0.3), Vector3(q.x + 0.3, q.y + 1.8, q.z + 0.3), gs, Res.blocks):
			p.pos = q
			break
	p.prev_pos = p.pos
	p.vel = Vector3.ZERO
	p.fall_distance = 0.0


## Mob currently carrying the local player: replaces the AI for this tick.
static func ride_tick(em, e, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	var def: Dictionary = e.def
	var fwd := 0.0
	var strafe := 0.0
	var yaw_to: float = e.yaw
	if e.id in NEEDS_TAMING and not is_tamed(e):
		# RunAroundLikeCrazyGoal
		if em.rng.randi_range(0, 49) == 0:
			if em.rng.randi_range(0, 99) < int(e.data.get("temper", 0)):
				e.data["owner"] = owner_name()
				e.persistent = true
				em.spawn_hearts(e.pos + Vector3(0, e.h, 0))
				Audio.play("entity.horse.ambient", e.pos, "Neutral")
			else:
				e.data["temper"] = mini(100, int(e.data.get("temper", 0)) + 5)
				Audio.play("entity.horse.angry", e.pos, "Neutral")
				dismount(em, p)
				p.vel = Vector3(em.rng.randf_range(-0.3, 0.3), 0.4, em.rng.randf_range(-0.3, 0.3))
				return
		if not e.has_target or e.pos.distance_to(e.target_pos) < 1.5:
			e.target_pos = e.pos + Vector3(em.rng.randf_range(-8, 8), 0, em.rng.randf_range(-8, 8))
			e.has_target = true
		var d: Vector3 = e.target_pos - e.pos
		yaw_to = rad_to_deg(atan2(-d.x, d.z))
		fwd = 1.0
	elif _controllable(e, p):
		yaw_to = p.yaw
		fwd = p.in_forward
		if fwd < 0.0:
			fwd *= 0.25
		strafe = p.in_strafe * 0.5
		if e.id in STEER_ITEM:
			fwd = 1.0
			strafe = 0.0
	e.yaw = rad_to_deg(lerp_angle(deg_to_rad(e.yaw), deg_to_rad(yaw_to), 0.5))
	e.body_yaw = e.yaw
	var speed := float(def["speed"])
	if e.id == "pig":
		speed = 0.25 * 0.225          # Java Pig.getRiddenSpeed (no boost)
	elif e.id == "strider":
		speed = 0.175 * 0.55          # Java Strider.getRiddenSpeed out of lava
	var fly: bool = def.get("flies", false)
	var yr := deg_to_rad(e.yaw)
	var f_dir := Vector3(-sin(yr), 0, cos(yr))
	var r_dir := Vector3(cos(yr), 0, sin(yr))
	if fly:
		var look := p.look_dir()
		e.vel += (look * fwd + r_dir * strafe) * speed * 0.6
		if p.in_jump:
			e.vel.y += speed * 0.5
		e.vel *= 0.9
		em._physics(e, gs, blocks, 0.0, 0.91, 0.0)
	else:
		# 0.76: calibrates our integration to Java's measured horse speeds (0.225 -> ~9.5 m/s)
		var accel := speed * 1.327 * 0.76 if e.on_ground else speed * 0.1
		e.vel += (f_dir * fwd + r_dir * strafe) * accel
		if p.in_jump and e.on_ground and (e.id in NEEDS_TAMING) and is_tamed(e):
			e.vel.y = 0.7
			Audio.play("entity.horse.jump", e.pos, "Neutral", 0.4)
		var fl: int = em._in_fluid(e, gs, blocks)
		if fl == 2 and def.get("lava_walker", false):
			e.vel.y = maxf(e.vel.y, 0.06)
		elif fl == 1:
			e.vel.y += 0.04 if e.vel.y < 0.1 else 0.0
		em._physics(e, gs, blocks, 0.08, 0.91, 1.0)
	var mv := Vector2(e.pos.x - e.prev.x, e.pos.z - e.prev.z).length()
	e.limb_amt = lerpf(e.limb_amt, minf(mv * 4.0, 1.0), 0.4)
	e.limb += e.limb_amt
	seat(e, p)


static func _controllable(e, p: Player) -> bool:
	if e.id in STEER_ITEM:
		return bool(e.data.get("saddle", false)) and not p.inventory.held().is_empty() and p.inventory.held().name() == STEER_ITEM[e.id]
	if e.id == "happy_ghast":
		return e.data.has("harness")
	return bool(e.data.get("saddle", false))


static func seat(e, p: Player) -> void:
	var h: float = SEAT.get(e.id, e.h * 0.6)
	p.prev_pos = e.prev + Vector3(0, h, 0)
	p.pos = e.pos + Vector3(0, h, 0)
	p.vel = Vector3.ZERO
	p.fall_distance = 0.0
	p.on_ground = false


## Tamed pet goals. Returns [mode, move_to]: 0 = normal AI, 1 = sitting (no movement), 2 = move toward move_to.
static func pet_goal(em, e) -> Array:
	var owner: Player = _owner_of(em, e)
	if owner == null:
		return [0, Vector3.INF]
	if bool(e.data.get("sitting", false)):
		return [1, Vector3.INF]
	if e.id == "wolf":
		var t = em.pet_target
		if t != null and not t.dead and t != e and t.kind == "mob" and not t.data.has("owner") and t.pos.distance_to(e.pos) < 24.0:
			if t.pos.distance_to(e.pos) < e.w * 0.5 + t.w * 0.5 + 1.0 and e.attack_cd <= 0:
				em._damage(t, 4.0, e)
				e.attack_cd = 20
			return [2, t.pos]
	var d: float = e.pos.distance_to(owner.pos)
	if d >= 12.0 and not owner.flying:
		if _teleport_near(em, e, owner):
			return [2, Vector3.INF]
	if d > 10.0 or (d > 2.0 and e.has_target and e.target_pos == owner.pos):
		e.has_target = true
		e.target_pos = owner.pos
		return [2, owner.pos]
	return [0, Vector3.INF]


static func _owner_of(em, e) -> Player:
	var on := str(e.data.get("owner", ""))
	if on == owner_name():
		return em.world.player
	for px in Net.proxies():
		if str(Net.players.get(px.peer_id, {}).get("name", "")) == on:
			return px
	return null


## Java FollowOwnerGoal.teleportToOwner: 10 tries within +-3 (x/z) / +-1 (y), not adjacent to the owner, standable.
static func _teleport_near(em, e, owner: Player) -> bool:
	var gs: Callable = em.world.state_at
	var blocks := Res.blocks
	for i in 10:
		var dx: int = em.rng.randi_range(-3, 3)
		var dz: int = em.rng.randi_range(-3, 3)
		if absi(dx) < 2 and absi(dz) < 2:
			continue
		var x: int = int(floor(owner.pos.x)) + dx
		var z: int = int(floor(owner.pos.z)) + dz
		var y: int = int(floor(owner.pos.y)) + int(em.rng.randi_range(-1, 1))
		var below: int = gs.call(x, y - 1, z)
		if below <= 0 or (blocks.st_flags[below] & BlockRegistry.F_COLLIDE) == 0 or (blocks.st_flags[below] & BlockRegistry.F_LIQUID) != 0:
			continue
		if gs.call(x, y, z) != 0 or gs.call(x, y + 1, z) != 0:
			continue
		e.pos = Vector3(x + 0.5, y, z + 0.5)
		e.prev = e.pos
		e.vel = Vector3.ZERO
		return true
	return false
