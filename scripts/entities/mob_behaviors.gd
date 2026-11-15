## MobBehaviors — mob-specific combat and neutral-animal behaviour on top of EntityManager's generic goal AI (Java
## Edition values from minecraft.wiki; where the wiki gives no number the comment says so and names the source):
## drowned trident throwing, crossbow piglins, llama spit, witches (approach to 10, potion drinking, 85 % magic
## resistance), enderman projectile dodging / staring freeze / teleporting toward far targets / carried blocks,
## zombie reinforcements / leaders / door breaking / villager targeting + infection, raiders hunting villagers,
## creepers fleeing cats, evokers fleeing players, villagers / traders fleeing raiders and zombies, polar bears
## defending cubs, bee stings, ravager stun + roar, goat rams + horns, llamas spitting at wolves, cat variants, neutral
## animals retaliating, sulfur cube growth, and a small mob effect system (potions on mobs).
## Contract (EntityManager hooks): on_spawn, pre_tick, flee_point, attack (nav_out / direct_out), mob_target +
## melee_mob, retaliate, on_damaged, dodge_projectile, on_death, tick_effects, apply_potion, speed_mult.
class_name MobBehaviors
extends RefCounted

const ZOMBIES := ["zombie", "husk", "drowned", "zombie_villager"]
## mobs with per-tick behaviour (pre_tick)
const TICK_IDS := {"enderman": true, "witch": true, "bee": true, "polar_bear": true, "ravager": true, "zombie": true, "husk": true,
	"drowned": true, "zombie_villager": true, "sulfur_cube": true, "parrot": true, "warden": true, "goat": true, "llama": true, "trader_llama": true}
## mobs whose attack replaces the generic melee while they target the player (attack)
const ATTACKS := {"drowned": true, "piglin": true, "llama": true, "trader_llama": true, "enderman": true, "witch": true, "evoker": true}
## mobs that run from a threat: speed multiplier (flee_point). wiki Creeper: flees cats / ocelots within 6 blocks "with
## faster movement than when pursuing" (no number: Java AvoidEntityGoal sprint modifier 1.2); wiki Evoker: flees players
## within 10 blocks (no speed given); wiki Villager: flee zombies / illagers (Java panic walk speed 0.5 x 1.5 = 0.75 on
## the 0.5 attribute); wiki Wandering Trader: avoids them (Java AvoidEntityGoal 0.5)
const FLEES := {"creeper": 1.2, "evoker": 1.0, "villager": 0.75, "wandering_trader": 0.5, "wolf": 1.5}
## wiki Wolf: wild wolves flee llamas within 24 blocks, 50 % faster; wiki Llama: always from strength 4 / 5, less often
## from weaker ones (Java Wolf.avoidLlama: strength >= nextInt(5), rolled on each check - (s + 1) / 5; the vertical
## reach is AvoidEntityGoal's 3 blocks - neither is on the wiki); tamed wolves never flee
const WOLF_LLAMA_R := 24.0
## wiki Villager "panic radii" (Java hostile sensor: villagers see these mobs as threats within the distance); wiki
## Wandering Trader: stays at least 8 blocks from zombies (the same table is used for the other mobs)
const VILLAGER_THREATS := {"zombie": 8.0, "husk": 8.0, "drowned": 8.0, "zombie_villager": 8.0, "vex": 8.0, "vindicator": 10.0, "zoglin": 10.0,
	"evoker": 12.0, "illusioner": 12.0, "ravager": 12.0, "pillager": 15.0}
## mobs that hunt villagers / wandering traders / iron golems when not after a player (mob_target)
const HUNTS := {"zombie": true, "husk": true, "drowned": true, "zombie_villager": true, "vindicator": true, "ravager": true}
## neutral animals that fight back instead of panicking (retaliate)
const RETALIATES := {"polar_bear": true, "llama": true, "trader_llama": true, "bee": true, "wolf": true, "nautilus": true, "warden": true}
## babies that never grow up (wiki: baby zombie variants, baby piglins)
const FOREVER_BABY := {"zombie": true, "husk": true, "drowned": true, "zombie_villager": true, "zombified_piglin": true, "piglin": true}
const UNDEAD := ["zombie", "husk", "drowned", "zombie_villager", "skeleton", "stray", "bogged", "wither_skeleton", "wither", "phantom",
	"zombified_piglin", "zoglin", "skeleton_horse", "zombie_horse", "parched", "zombie_nautilus"]

static var nav_out := Vector3.INF   # attack(): this tick's navigation target (INF: stand still)
static var direct_out := false      # attack(): steer straight at nav_out


# ------------------------------------------------------------------ shared lookups

## Mobs of a few ids, gathered in one pass over the entities every 10 ticks (no per-mob scans over all entities).
const CACHED := {"villager": true, "wandering_trader": true, "iron_golem": true, "cat": true, "ocelot": true, "polar_bear": true, "bee": true,
	"wolf": true, "zombie": true, "husk": true, "drowned": true, "zombie_villager": true, "vex": true, "vindicator": true, "zoglin": true, "evoker": true,
	"illusioner": true, "ravager": true, "pillager": true, "llama": true, "trader_llama": true, "cod": true, "salmon": true, "tropical_fish": true}
static var _cache_key := -1
static var _cache_em := 0
static var _by_id: Dictionary = {}
const _NONE: Array = []


static func near_list(em, id: String) -> Array:
	var k := int(em.world.game_time) / 10
	var eid: int = em.get_instance_id()
	if k != _cache_key or eid != _cache_em:
		_cache_key = k
		_cache_em = eid
		_by_id.clear()
		for o in em.ents:
			if o.kind == "mob" and not o.dead and CACHED.has(o.id):
				if not _by_id.has(o.id):
					_by_id[o.id] = []
				(_by_id[o.id] as Array).append(o)
	return _by_id.get(id, _NONE)


static func reset_cache() -> void:
	_cache_key = -1
	_by_id.clear()


static func max_hp(e) -> float:
	return float(e.data.get("max_hp", e.def.get("hp", 20.0)))


## Line of sight between two points (no block in the way).
static func _los(em, from: Vector3, to: Vector3) -> bool:
	var d := to - from
	var l := d.length()
	return l < 0.01 or VoxelRaycast.cast(from, d / l, l, em.world.state_at, Res.blocks).is_empty()


## Line of sight from the mob's eyes to the player's, re-checked every 5 ticks.
static func _sees(em, e, p: Player) -> bool:
	if e.age % 5 == 0 or not e.rt.has("sees"):
		e.rt["sees"] = MobAI._has_los(em, e.pos + Vector3(0, e.h * 0.85, 0), p.eye_pos())
	return bool(e.rt["sees"])


## Java Projectile.shoot spread (wiki Arrow: each axis +-0.0172275 x inaccuracy, triangular) on a unit direction.
static func spread(rng: RandomNumberGenerator, dir: Vector3, inaccuracy: float) -> Vector3:
	var s := 0.0172275 * inaccuracy
	return dir.normalized() + Vector3((rng.randf() - rng.randf()) * s, (rng.randf() - rng.randf()) * s, (rng.randf() - rng.randf()) * s)


## wiki Skeleton: arrow error 10 / 6 / 2 on Easy / Normal / Hard (14 - 4 x difficulty); used for every mob arrow and
## trident (the wiki lists no separate values for crossbow mobs / drowned).
static func mob_inaccuracy(world) -> float:
	return float(14 - 4 * clampi(int(world.difficulty), 0, 3))


## A mob projectile aimed at the player's body (+ 0.2 per horizontal block against gravity: wiki Skeleton), returns it.
static func shoot(em, e, p: Player, kind: String, speed: float, aim_h: float = 0.333):
	var from: Vector3 = e.pos + Vector3(0, e.h * 0.85, 0)
	var aim: Vector3 = p.pos + Vector3(0, p.eye_height() * aim_h * 2.0, 0) - from
	aim.y += Vector2(aim.x, aim.z).length() * 0.2
	var n0: int = em.ents.size()
	em.spawn_projectile(kind, from, spread(em.rng, aim, mob_inaccuracy(em.world)) * speed, e)
	var pr = em.ents[em.ents.size() - 1] if em.ents.size() > n0 else null
	if pr != null and kind == "arrow" and e.data.has("held_stack"):
		# an enchanted bow (ominous trial skeletons): wiki Power +0.5 x level + 0.5 base damage, Punch knockback
		var pw := HeldItems.ench(e, "power")
		if pw > 0:
			pr.data["base_damage"] = 2.0 + 0.5 * pw + 0.5
		var pu := HeldItems.ench(e, "punch")
		if pu > 0:
			pr.data["punch"] = pu
	return pr


# ------------------------------------------------------------------ spawning

static func on_spawn(em, e, baby: bool) -> void:
	var w = em.world
	if w == null:
		return
	if e.id in ZOMBIES:
		# wiki Zombie: spawn_reinforcements random 0 - 0.1; up to 10 % (by clamped regional difficulty) can break doors;
		# leaders (Normal / Hard, up to 5 % by clamped regional difficulty): +50-75 % reinforcement chance, 2-5 x max
		# health, always break doors
		var f := MobAI.clamped_regional(w, e.pos)
		var reinf: float = em.rng.randf() * 0.1
		if em.rng.randf() < f * 0.1:
			e.data["breaks_doors"] = true
		if int(w.difficulty) >= 2 and not baby and em.rng.randf() < f * 0.05:
			e.data["leader"] = true
			e.data["breaks_doors"] = true
			reinf += 0.5 + em.rng.randf() * 0.25
			var mh: float = float(e.def["hp"]) * em.rng.randf_range(2.0, 5.0)
			e.data["max_hp"] = mh
			e.hp = mh
		e.data["reinf"] = reinf
	elif e.id == "goat":
		goat_init(em, e, baby)
	elif e.id == "llama" or e.id == "trader_llama":
		# wiki Llama: strength 1-5 - wild llamas 32.8 % each for 1 / 2 / 3, 0.8 % each for 4 / 5 (a 4 % roll over all five,
		# else 1-3; trader llamas: not on the wiki, the same roll); bred ones: llama_bred_strength
		e.data["strength"] = 1 + em.rng.randi_range(0, 4 if em.rng.randf() < 0.04 else 2)
	elif e.id == "cat":
		e.data["variant"] = cat_variant(w, e.pos, em.rng)


# ------------------------------------------------------------------ per-tick behaviour

## Called from EntityManager._tick_mob before movement for TICK_IDS; true = the mob is busy this tick (stunned); with
## self_moved also set, pre_tick already ran its physics (a goat mid long jump).
static var self_moved := false


static func pre_tick(em, e, p: Player, dist: float, fl: int) -> bool:
	self_moved = false
	match e.id:
		"enderman":
			_enderman_tick(em, e, p, dist)
		"witch":
			_witch_tick(em, e, p, dist, fl)
		"bee":
			_bee_tick(em, e)
		"polar_bear":
			_polar_bear_tick(em, e, p, dist)
		"ravager":
			return _ravager_tick(em, e, p)
		"zombie", "husk", "drowned", "zombie_villager":
			_door_tick(em, e, p)
		"parrot":
			_parrot_tick(em, e, p)
		"warden":
			_warden_tick(em, e, p)
		"goat":
			return _goat_tick(em, e, p, dist, fl)
		"llama", "trader_llama":
			_llama_wolf_tick(em, e)
		"sulfur_cube":
			# wiki Sulfur Cube: small cubes grow into large ones after 20 minutes
			if e.size == 1:
				var g := int(e.data.get("grow_t", 0)) + 1
				e.data["grow_t"] = g
				if g >= 24000:
					e.data.erase("grow_t")
					em.set_size(e, 2)
	return false


## Flee target (INF when none) for FLEES ids; checked against cached threat lists.
static func flee_point(em, e, p: Player, dist: float) -> Vector3:
	var threat := Vector3.INF
	if e.id == "creeper":
		if e.fuse >= 0:
			return Vector3.INF   # wiki Creeper: a detonating creeper does not flee
		var bd := 36.0
		for id in ["cat", "ocelot"]:
			for o in near_list(em, id):
				if not o.dead:
					var d2: float = o.pos.distance_squared_to(e.pos)
					if d2 < bd:
						bd = d2
						threat = o.pos
	elif e.id == "wolf":
		if Taming.is_tamed(e) or e.angry or e.target_player:
			return Vector3.INF
		if (e.age + e.uid) % 10 == 0 or not e.rt.has("threat"):
			var best := Vector3.INF
			var bd := WOLF_LLAMA_R * WOLF_LLAMA_R
			for id in ["llama", "trader_llama"]:
				for o in near_list(em, id):
					if o.dead or absf(o.pos.y - e.pos.y) > 3.0:
						continue
					var d2: float = Vector2(o.pos.x - e.pos.x, o.pos.z - e.pos.z).length_squared()
					if d2 < bd and int(o.data.get("strength", 3)) >= em.rng.randi_range(0, 4):
						bd = d2
						best = o.pos
			e.rt["threat"] = best
		threat = e.rt["threat"]
	elif e.id == "evoker":
		# wiki Evoker: flees a player within 10 blocks while not in the middle of casting a spell
		if dist < 10.0 and int(e.rt.get("cast", 0)) <= 0 and not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE):
			threat = p.pos
	elif e.id == "villager" or e.id == "wandering_trader":
		# the nearest threat within its VILLAGER_THREATS distance, re-checked every 10 ticks (staggered)
		if (e.age + e.uid) % 10 == 0 or not e.rt.has("threat"):
			var best := Vector3.INF
			var bd := INF
			for id in VILLAGER_THREATS:
				var r: float = VILLAGER_THREATS[id]
				for o in near_list(em, id):
					if not o.dead:
						var d2: float = o.pos.distance_squared_to(e.pos)
						if d2 < r * r and d2 < bd:
							bd = d2
							best = o.pos
			e.rt["threat"] = best
		threat = e.rt["threat"]
	if threat == Vector3.INF:
		return Vector3.INF
	var away := Vector3(e.pos.x - threat.x, 0.0, e.pos.z - threat.z)
	if away.length_squared() < 0.0001:
		away = Vector3(1, 0, 0)
	# (Java AvoidEntityGoal picks a random spot up to 16 blocks away from the threat; straight away here)
	return e.pos + away.normalized() * 10.0


## Replaces the generic melee for ATTACKS ids while targeting the player; true = handled (nav_out / direct_out set).
static func attack(em, e, p: Player, dist: float) -> bool:
	nav_out = Vector3.INF
	direct_out = false
	match e.id:
		"drowned":
			if str(e.data.get("held", "")) != "trident":
				return false
			# wiki Drowned: throws its trident every 1.5 s up to 20 blocks (Easy 5 / Normal 8 / Hard 12; not picked up);
			# no melee while holding one (26.3). (Launch speed not on the wiki: Java ThrownTrident from mobs, 1.6.)
			if dist <= 20.0 and _sees(em, e, p):
				if e.attack_cd <= 0:
					var t = shoot(em, e, p, "trident", 1.6)
					if t != null:
						t.data["base_damage"] = 8.0
						t.data["pickup"] = false
						t.stack = ItemStack.named("trident", 1)
					Audio.play("entity.drowned.shoot", e.pos, "Hostile")
					e.attack_cd = 30
			else:
				nav_out = p.pos
			return true
		"piglin":
			if e.baby_age < 0 or str(e.data.get("held", "")) != "crossbow":
				return false
			# wiki Piglin: crossbow piglins shoot every 2 s and walk backward as soon as the target is close (no range on
			# the wiki: the pillager's crossbow distances 8 / 6 are used)
			if dist >= 8.0:
				nav_out = p.pos
			elif dist < 6.0:
				nav_out = e.pos + (e.pos - p.pos).normalized() * 3.0
			if e.attack_cd <= 0 and dist <= 8.0 and _sees(em, e, p):
				shoot(em, e, p, "arrow", 1.6)
				Audio.play("item.crossbow.shoot", e.pos, "Hostile")
				e.attack_cd = 40
			return true
		"llama", "trader_llama":
			# wiki Llama: spits at an attacker every 2 s, 1 damage (Hard 1.5); no spit range on the wiki (the follow range
			# 16 is used); it calms down after its spit until provoked again (Java LlamaHurtByTargetGoal)
			if dist <= 16.0 and _sees(em, e, p):
				if e.attack_cd <= 0:
					shoot(em, e, p, "llama_spit", 1.5, 0.25)   # (launch speed not on the wiki: Java LlamaSpit 1.5)
					Audio.play("entity.llama.spit", e.pos, "Neutral")
					e.attack_cd = 40
					e.angry = false
					e.target_player = false
			else:
				nav_out = p.pos
			return true
		"enderman":
			# Java EndermanFreezeWhenLookedAtGoal: stands still while the target stares at it within 16 blocks
			if bool(e.rt.get("stared", false)) and dist < 16.0:
				return true
			return false
		"witch":
			# wiki Witch: throws potions within 10 blocks every 3 s (Raids._witch); no melee - it walks into range
			if dist > 10.0 or not _sees(em, e, p):
				nav_out = p.pos
			return true
		"evoker":
			return true   # wiki Evoker: spells only (Raids._evoker); it keeps its distance (flee_point)
	return false


# ------------------------------------------------------------------ villager hunting (zombies, vindicators, ravagers)

## wiki Zombie: zombies target villagers / wandering traders (35) and iron golems (42) - drowned only at night or in the
## dark; vindicators / ravagers attack villagers and iron golems. Within the follow range, re-picked every 10 ticks.
static func mob_target(em, e):
	var t = e.rt.get("mtgt")
	var fr := MobControl.follow_range(e)
	if t != null and (t.dead or t.pos.distance_squared_to(e.pos) > fr * fr):
		t = null
		e.rt.erase("mtgt")
	if t == null and (e.age + e.uid) % 10 == 0:
		if e.id == "drowned" and MobAI.bright_outside(em.world):
			return null
		var bd := fr * fr
		for id in ["villager", "wandering_trader", "iron_golem"]:
			for o in near_list(em, id):
				if not o.dead:
					var d2: float = o.pos.distance_squared_to(e.pos)
					if d2 < bd:
						bd = d2
						t = o
		if t != null:
			e.rt["mtgt"] = t
	return t


## Melee against a mob target: Java MeleeAttackGoal reach (2 x width)^2 + target width horizontally, every 20 ticks,
## the Normal damage (wiki Difficulty: mobs hitting mobs). wiki Zombie: a villager killed by a zombie becomes a zombie
## villager on Normal (50 %) and Hard (100 %).
static func melee_mob(em, e, t) -> void:
	var dx: float = t.pos.x - e.pos.x
	var dz: float = t.pos.z - e.pos.z
	var reach2: float = pow(float(e.w) * 2.0, 2.0) + float(t.w)
	if e.attack_cd > 0 or dx * dx + dz * dz > reach2 or absf(t.pos.y - e.pos.y) > 2.0:
		return
	e.attack_cd = 20
	var dmg := float(e.def.get("attack", 2.0)) + HeldItems.attack_bonus(e)
	var diff := int(em.world.difficulty)
	if t.id == "villager" and e.id in ZOMBIES and dmg >= t.hp and (diff == 3 or (diff == 2 and em.rng.randf() < 0.5)):
		infect(em, t)
		return
	em._damage(t, dmg, e)


## Villager -> zombie villager (keeps profession, biome type, trades, baby state; persistent).
static func infect(em, v) -> void:
	var zv = em.spawn_mob("zombie_villager", v.pos, v.baby_age < 0)
	if zv == null:
		return
	for k in ["prof", "vtype", "level", "offers", "vxp", "gossip", "CustomName"]:   # (vxp: the trading experience)
		if v.data.has(k):
			zv.data[k] = v.data[k]
	zv.yaw = v.yaw
	zv.body_yaw = v.body_yaw
	zv.persistent = true
	villager_layers(zv)
	Audio.play("entity.zombie.infect", v.pos, "Hostile")
	em._remove(v)


## Java VillagerRenderer layers: base + biome type + profession (spawn_mob builds them before data is known).
static func villager_layers(e) -> void:
	if e.node == null:
		return
	var root := "entity/zombie_villager/" if e.id == "zombie_villager" else "entity/villager/"
	var layers := [root + ("zombie_villager" if e.id == "zombie_villager" else "villager"), root + "type/" + str(e.data.get("vtype", "plains"))]
	var prof := str(e.data.get("prof", ""))
	if prof != "" and prof != "none" and prof != "wandering_trader":
		layers.append(root + "profession/" + prof)
	var vm := EntityRenderer.material_layers(layers)
	for mi in _meshes(e.node):
		(mi as MeshInstance3D).material_override = vm


static func _meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


# ------------------------------------------------------------------ damage hooks

## Neutral animals hit by a player fight back (true: no panic). wiki Polar Bear: adults turn on the attacker; hitting a
## cub angers every adult in a 41 x 21 x 41 box (unless the cub dies), hitting an adult within 16 x 8 x 16 of a cub also
## provokes the adults within 21 x 21 x 21 of it; wiki Bee: all nearby bees are angered (no radius on the wiki: the
## follow range 16) unless the bee dies from the hit; wiki Llama / Wolf / Nautilus: they attack whoever hurt them.
static func retaliate(em, e, source) -> bool:
	if not (source is Player) or (source as Player).is_creative() or (source as Player).is_spectator():
		return false
	if Taming.is_tamed(e) and e.id != "llama" and e.id != "trader_llama":
		return false
	match e.id:
		"warden":
			warden_anger(e, 100)   # wiki Warden: +100 when directly attacked
			return false
		"polar_bear":
			if e.baby_age < 0:
				if e.hp > 0.0:
					_anger_bears(em, e.pos, Vector3(20.5, 10.5, 20.5))
				return false
			_provoke(em, e)
			for o in near_list(em, "polar_bear"):
				if o.baby_age < 0 and not o.dead and _in_box(o.pos, e.pos, Vector3(8, 4, 8)):
					_anger_bears(em, e.pos, Vector3(10.5, 10.5, 10.5))
					break
			return true
		"bee":
			if e.data.has("stung") or e.hp <= 0.0:
				return false
			_provoke(em, e)
			for o in near_list(em, "bee"):
				if o != e and not o.dead and not o.data.has("stung") and o.pos.distance_squared_to(e.pos) <= 256.0:
					_provoke(em, o)
			return true
		"llama", "trader_llama", "wolf", "nautilus":
			if e.baby_age < 0:
				return false
			_provoke(em, e)
			return true
	return false


static func _provoke(em, e) -> void:
	MobAI.anger(e, em.rng)
	e.target_player = true
	e.panic = 0


static func _anger_bears(em, at: Vector3, half: Vector3) -> void:
	for o in near_list(em, "polar_bear"):
		if o.baby_age >= 0 and not o.dead and _in_box(o.pos, at, half):
			_provoke(em, o)


static func _in_box(q: Vector3, c: Vector3, half: Vector3) -> bool:
	return absf(q.x - c.x) <= half.x and absf(q.y - c.y) <= half.y and absf(q.z - c.z) <= half.z


## After a mob took damage (still alive). wiki Zombie: on Hard, a zombie-type mob damaged while targeting something
## summons a reinforcement when a random float is below its spawn_reinforcements chance: up to 50 tries 0 or +-7-40
## blocks away on each axis, solid ground, light 0 (Nether: 7 or less), no player within 7 blocks; each summon costs
## the summoner 5 % and the reinforcement starts 5 % lower.
static func on_damaged(em, e, source) -> void:
	if e.hp <= 0.0 or not (e.id in ZOMBIES) or not e.data.has("reinf") or int(em.world.difficulty) < 3:
		return
	if not (e.target_player or e.rt.has("mtgt") or source is Player):
		return
	if em.rng.randf() >= float(e.data["reinf"]):
		return
	var w = em.world
	var gs: Callable = w.state_at
	var bl := Res.blocks
	var nether: bool = str(w.get("dimension")) == "the_nether"
	var b := Vector3i(e.pos.floor())
	for i in 50:
		var q := b + Vector3i(em.rng.randi_range(7, 40) * em.rng.randi_range(-1, 1), em.rng.randi_range(7, 40) * em.rng.randi_range(-1, 1),
			em.rng.randi_range(7, 40) * em.rng.randi_range(-1, 1))
		if not w.column_ready(q.x + 0.5, q.z + 0.5):
			continue
		var below: int = gs.call(q.x, q.y - 1, q.z)
		if below <= 0 or (bl.st_flags[below] & BlockRegistry.F_FULL_SHAPE) == 0 or gs.call(q.x, q.y, q.z) != 0 or gs.call(q.x, q.y + 1, q.z) != 0:
			continue
		var lt: int = MobAI.raw_light(w, w.cm.get_light(q.x, q.y, q.z))
		if lt > (7 if nether else 0):
			continue
		var c := Vector3(q.x + 0.5, q.y, q.z + 0.5)
		if c.distance_to(w.player.pos) < 7.0:
			continue
		var r = em.spawn_mob(e.id, c)
		if r == null:
			return
		r.data["reinf"] = maxf(0.0, float(r.data.get("reinf", 0.0)) - 0.05)
		r.target_player = e.target_player or source is Player
		if e.rt.has("mtgt"):
			r.rt["mtgt"] = e.rt["mtgt"]
		e.data["reinf"] = maxf(0.0, float(e.data["reinf"]) - 0.05)
		return


## wiki Enderman: teleports away from projectiles (snowballs are absorbed, splash water hurts it) - true = the
## projectile misses and flies on.
static func dodge_projectile(em, victim, proj_id: String) -> bool:
	if victim.id == "wither":
		# wiki Wither: below half health its wither armor makes it immune to arrows, thrown tridents and wind charges
		return proj_id in ["arrow", "trident", "wind_charge"] and victim.hp < float(victim.def.get("hp", 300.0)) / 2.0
	if victim.id != "enderman" or proj_id in ["snowball", "splash_potion", "lingering_potion"]:
		return false
	victim.tp_cd = 0
	em._teleport(victim, em.world.state_at, Res.blocks)
	return true


static func on_death(em, e) -> void:
	if e.id == "enderman" and e.data.has("carried"):
		# wiki Enderman: drops its carried block on death
		var st := Res.blocks.default_state(str(e.data["carried"]))
		var item := Res.items.id(str(e.data["carried"])) if Res.items != null else -1
		if st > 0 and item > 0:
			em.spawn_item(e.pos + Vector3(0, 0.5, 0), ItemStack.named(str(e.data["carried"]), 1))
		e.data.erase("carried")


# ------------------------------------------------------------------ enderman

static var _holdable: Dictionary = {}


static func holdable() -> Dictionary:
	if _holdable.is_empty():
		for n in Tags.resolve("block", "#minecraft:enderman_holdable"):
			_holdable[str(n).trim_prefix("minecraft:")] = true
	return _holdable


static func _enderman_tick(em, e, p: Player, dist: float) -> void:
	var w = em.world
	# wiki Enderman: 1/20 per tick to pick a random block of a 4 x 3 x 4 region it can see (#enderman_holdable), 1/2000
	# per tick to place it silently in a 2 x 2 x 2 region on air above a full block; not with mobGriefing off
	if not e.data.has("carried"):
		if em.rng.randi_range(0, 19) == 0 and w.gamerule("mobGriefing", true):
			_take_block(em, e)
	elif em.rng.randi_range(0, 1999) == 0 and w.gamerule("mobGriefing", true):
		_place_block(em, e)
	if not e.target_player or p.dead:
		e.rt.erase("stared")
		return
	# wiki Enderman: an aggravated enderman teleports away when its starer comes within 4 blocks, and teleports up to
	# 19 blocks horizontally / 22 vertically toward a target 16+ blocks away every 1.5-2 s
	var st := MobAI.player_stares(em, e, p)
	e.rt["stared"] = st
	if st:
		e.rt["tpt"] = 0
		if dist < 4.0:
			e.tp_cd = 0
			em._teleport(e, w.state_at, Res.blocks)
	elif dist > 16.0:
		var t := int(e.rt.get("tpt", 0)) + 1
		if t >= int(e.rt.get("tpn", 30)):
			var dv: Vector3 = (e.pos - p.pos).normalized()
			var rng: RandomNumberGenerator = em.rng
			var dest: Vector3 = e.pos + Vector3((rng.randf() - 0.5) * 6.0 - dv.x * 16.0, rng.randf_range(-6.0, 6.0) - dv.y * 16.0, (rng.randf() - 0.5) * 6.0 - dv.z * 16.0)
			if teleport_at(em, e, dest):
				t = 0
				e.rt["tpn"] = rng.randi_range(30, 40)
		e.rt["tpt"] = t


static func _take_block(em, e) -> void:
	var w = em.world
	var rng: RandomNumberGenerator = em.rng
	var x := floori(e.pos.x - 2.0 + rng.randf() * 4.0)
	var y := floori(e.pos.y + rng.randf() * 3.0)
	var z := floori(e.pos.z - 2.0 + rng.randf() * 4.0)
	var st: int = w.state_at(x, y, z)
	if st <= 0:
		return
	var nm := Res.blocks.name_of(st)
	if not holdable().has(nm):
		return
	var eye: Vector3 = e.pos + Vector3(0, e.h * 0.88, 0)
	var c := Vector3(x + 0.5, y + 0.5, z + 0.5)
	var hit := VoxelRaycast.cast(eye, c - eye, eye.distance_to(c) + 0.5, w.state_at, Res.blocks)
	if hit.is_empty() or Vector3i(hit["pos"]) != Vector3i(x, y, z):
		return
	w.set_block(x, y, z, 0)
	e.data["carried"] = nm


static func _place_block(em, e) -> void:
	var w = em.world
	var rng: RandomNumberGenerator = em.rng
	var x := floori(e.pos.x - 1.0 + rng.randf() * 2.0)
	var y := floori(e.pos.y + rng.randf() * 2.0)
	var z := floori(e.pos.z - 1.0 + rng.randf() * 2.0)
	var nm := str(e.data["carried"])
	var st := Res.blocks.default_state(nm)
	if st <= 0:
		e.data.erase("carried")
		return
	var below: int = w.state_at(x, y - 1, z)
	if w.state_at(x, y, z) != 0 or below <= 0 or (Res.blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) == 0 or Res.blocks.name_of(below) == "bedrock":
		return
	# plants only where they can stand (dirt-like ground)
	if (Res.blocks.st_flags[st] & BlockRegistry.F_FULL_SHAPE) == 0:
		var bn := Res.blocks.name_of(below)
		if not (Tags.resolve("block", "#minecraft:dirt").has("minecraft:" + bn) or Tags.resolve("block", "#minecraft:dirt").has(bn) or bn.ends_with("nylium") or bn == "mycelium"):
			return
	var p: Player = w.player
	var pmn := p.aabb_min()
	var pmx := p.aabb_max()
	if pmx.x > x and pmn.x < x + 1 and pmx.y > y and pmn.y < y + 1 and pmx.z > z and pmn.z < z + 1:
		return
	w.set_block(x, y, z, st)
	e.data.erase("carried")


## Java EnderMan.teleport(x, y, z): drop to the first block that blocks motion, no fluid at the feet, room for the body.
static func teleport_at(em, e, t: Vector3) -> bool:
	var w = em.world
	if not w.column_ready(t.x, t.z):
		return false
	var gs: Callable = w.state_at
	var bl := Res.blocks
	var x := floori(t.x)
	var z := floori(t.z)
	var y := floori(t.y)
	var miny: int = Coords.MIN_Y
	if w.get("gen") != null and "gen_min_y" in w.gen:
		miny = int(w.gen.gen_min_y)
	while y > miny and gs.call(x, y - 1, z) <= 0:
		y -= 1
	var below: int = gs.call(x, y - 1, z)
	if below <= 0 or (bl.st_flags[below] & BlockRegistry.F_COLLIDE) == 0 or (bl.st_flags[below] & BlockRegistry.F_LIQUID) != 0:
		return false
	for hy in int(ceil(e.h)):
		if gs.call(x, y + hy, z) != 0:
			return false
	Audio.play("entity.enderman.teleport", e.pos, "Hostile")
	e.pos = Vector3(x + 0.5, y, z + 0.5)
	e.prev = e.pos
	e.vel = Vector3.ZERO
	MobControl.nav_stop(e)
	return true


## Java CarriedBlockLayer (block at 0.5 scale held in front, arms raised): pose-stack ops in Java model space after the
## model's (-1, -1, 1) flip, block mesh centred like EntityRenderer block layers.
static func render_carried(e) -> void:
	var model: Node3D = e.node.get_node_or_null("model") if e.node != null else null
	if model == null:
		return
	var nm := str(e.data.get("carried", ""))
	var cur: Node3D = model.get_node_or_null("carried")
	if cur != null and str(cur.get_meta("block", "")) == nm:
		return
	if cur != null:
		model.remove_child(cur)
		cur.queue_free()
	if nm == "":
		return
	var st := Res.blocks.default_state(nm)
	var mesh := EntityRenderer.block_item_mesh(st) if st > 0 else null
	if mesh == null:
		return
	var j := Transform3D(Basis(), Vector3(0.0, 0.6875, -0.75))
	j = j * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20.0)), Vector3.ZERO)
	j = j * Transform3D(Basis(Vector3.UP, deg_to_rad(45.0)), Vector3.ZERO)
	j = j * Transform3D(Basis(), Vector3(0.25, 0.1875, 0.25))
	j = j * Transform3D(Basis.from_scale(Vector3(-0.5, -0.5, 0.5)), Vector3.ZERO)
	j = j * Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3.ZERO)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.transform = Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO) * j * Transform3D(Basis(), Vector3(0.5, 0.0, 0.5))
	var host := Node3D.new()   # (Java layer space = the model origin)
	host.name = "carried"
	host.set_meta("block", nm)
	host.add_child(mi)
	model.add_child(host)


# ------------------------------------------------------------------ witch

## wiki Witch: when not drinking, each tick: Water Breathing 15 % while mostly underwater (no effect yet), Fire
## Resistance 15 % while burning, Healing (4 HP) 5 % when hurt, Swiftness 50 % when its target is 11+ blocks away;
## drinking takes 1.6 s, no attacks meanwhile (it also slows "a little" - no value on the wiki, not applied).
## Potion effects: the potions' standard 3:00 durations (Potions.EFFECTS).
static func _witch_tick(em, e, p: Player, dist: float, fl: int) -> void:
	var dr := int(e.rt.get("drink", 0))
	if dr > 0:
		dr -= 1
		e.rt["drink"] = dr
		if dr == 0:
			apply_potion(em, e, str(e.rt.get("drink_pot", "")), 1.0)
			e.rt.erase("drink_pot")
			e.data.erase("held")
		return
	var rng: RandomNumberGenerator = em.rng
	var pot := ""
	var head_wet := false
	if fl == 1:
		var hs: int = em.world.state_at(floori(e.pos.x), floori(e.pos.y + e.h * 0.8), floori(e.pos.z))
		head_wet = hs > 0 and (Res.blocks.st_flags[hs] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 and (Res.blocks.st_flags[hs] & BlockRegistry.F_LAVA) == 0
	if head_wet and not has_effect(e, "water_breathing") and rng.randf() < 0.15:
		pot = "water_breathing"
	elif e.fire > 0 and not has_effect(e, "fire_resistance") and rng.randf() < 0.15:
		pot = "fire_resistance"
	elif e.hp < max_hp(e) and rng.randf() < 0.05:
		pot = "healing"
	elif e.target_player and dist >= 11.0 and not has_effect(e, "speed") and rng.randf() < 0.5:
		pot = "swiftness"
	if pot == "":
		return
	e.rt["drink"] = 32
	e.rt["drink_pot"] = pot
	e.data["held"] = "potion"
	Audio.play("entity.witch.drink", e.pos, "Hostile")


# ------------------------------------------------------------------ bees, polar bears, ravagers, zombies

## wiki Bee: a successful sting poisons (Normal 10 s, Hard 18 s, Easy none); the bee loses its stinger, cannot attack
## again and dies about a minute later.
static func bee_stung(em, e, p: Player) -> void:
	var d := int(em.world.difficulty)
	if d >= 2:
		p.add_effect("poison", 0, 200 if d == 2 else 360)
	e.data["stung"] = true
	e.data["sting_t"] = 0
	e.angry = false
	e.target_player = false
	e.rt.erase("anger_t")


static func _bee_tick(em, e) -> void:
	if not e.data.has("stung"):
		return
	var t := int(e.data.get("sting_t", 0)) + 1
	e.data["sting_t"] = t
	# (death roll each 5 ticks with 1 in max(1, 1200 - t): about one minute, as the wiki describes)
	if t % 5 == 0 and em.rng.randi_range(0, maxi(1, 1200 - t) - 1) == 0:
		e.invuln = 0
		em._damage(e, 1.0e6, null)


## wiki Polar Bear: adults become hostile when a player comes close to a cub near them (the wiki gives no distance:
## the bear's follow range 20 is used; cubs count within 16 x 8 x 16 of the adult). Every 20 ticks.
static func _polar_bear_tick(em, e, p: Player, dist: float) -> void:
	if e.baby_age < 0 or e.angry or (e.age + e.uid) % 20 != 0 or p.dead or not (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE):
		return
	if dist > MobControl.follow_range(e):
		return
	for o in near_list(em, "polar_bear"):
		if o.baby_age < 0 and not o.dead and _in_box(o.pos, e.pos, Vector3(8, 4, 8)):
			_provoke(em, e)
			return


## wiki Ravager: a bite blocked by a shield has a 50 % chance to stun it for 2 s (no moving or attacking); then it
## roars: 6 damage (scaled by difficulty for players: 4 / 6 / 9) and knockback to everything nearby (no radius on the
## wiki: Java's roar box, 4 blocks).
static func ravager_blocked(em, e) -> void:
	if em.rng.randf() < 0.5:
		e.rt["stun"] = 40
		Audio.play("entity.ravager.stunned", e.pos, "Hostile")


static func _ravager_tick(em, e, p: Player) -> bool:
	var s := int(e.rt.get("stun", 0))
	if s <= 0:
		_ravager_trample(em, e)
		return false
	s -= 1
	e.rt["stun"] = s
	e.vel.x = 0.0
	e.vel.z = 0.0
	if s == 0:
		Audio.play("entity.ravager.roar", e.pos, "Hostile")
		if not p.dead and p.pos.distance_to(e.pos) <= 4.0 + e.w * 0.5:
			if p.hurt(MobAI.diff_dmg(int(em.world.difficulty), 6.0), "mob", false, e.pos, e):
				p.knockback(1.0, e.pos.x - p.pos.x, e.pos.z - p.pos.z)
		for o in em.ents.duplicate():
			if o != e and o.kind == "mob" and not o.dead and not Raids.is_raider(o) and o.pos.distance_to(e.pos) <= 4.0 + e.w * 0.5:
				em._damage(o, 6.0, e)
				em._knockback(o, 1.0, o.pos.x - e.pos.x, o.pos.z - e.pos.z)
	return true


## wiki Ravager: breaks leaves and some crops (beetroots, carrots, potatoes, wheat, pitcher / torchflower crops) by
## charging through them; not with mobGriefing off. Checked when it bumps into something.
const RAVAGER_BREAKS := {"beetroots": true, "carrots": true, "potatoes": true, "wheat": true, "pitcher_crop": true, "torchflower_crop": true}


static func _ravager_trample(em, e) -> void:
	if not e.hcollide or not e.target_player and not e.rt.has("mtgt"):
		return
	var w = em.world
	if not w.gamerule("mobGriefing", true):
		return
	var r: float = e.w * 0.5 + 0.2
	for y in range(floori(e.pos.y), floori(e.pos.y + e.h) + 1):
		for z in range(floori(e.pos.z - r), floori(e.pos.z + r) + 1):
			for x in range(floori(e.pos.x - r), floori(e.pos.x + r) + 1):
				var st: int = w.state_at(x, y, z)
				if st <= 0:
					continue
				var nm := Res.blocks.name_of(st)
				if nm.ends_with("_leaves") or RAVAGER_BREAKS.has(nm):
					var q := Vector3i(x, y, z)
					em.spawn_block_particles(q, st)
					for s in Loot.block_drops(st, null, w, q):
						em.spawn_item(Vector3(x + 0.5, y + 0.5, z + 0.5), s)
					w.set_block(x, y, z, 0)


## wiki Zombie: door-breaking zombies (CanBreakDoors) bang on a closed wooden or copper door in their way; on Hard it
## breaks after about 10 seconds (Haste / tools / Mining Fatigue do not matter). Checked toward the target every tick.
static func _door_tick(em, e, p: Player) -> void:
	if not e.data.has("breaks_doors"):
		return
	var tgt := Vector3.INF
	if e.target_player:
		tgt = p.pos
	elif e.rt.has("mtgt") and e.rt["mtgt"] != null:
		tgt = e.rt["mtgt"].pos
	if tgt == Vector3.INF:
		e.rt.erase("door_t")
		return
	var w = em.world
	var dir := Vector3(tgt.x - e.pos.x, 0, tgt.z - e.pos.z)
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var door := Vector3i(0, -9999, 0)
	for k in 2:
		var q := Vector3i((e.pos + dir * (0.6 + 0.4 * k) + Vector3(0, 0.5, 0)).floor())
		for dy in 2:
			var st: int = w.state_at(q.x, q.y + dy, q.z)
			if st > 0:
				var nm := Res.blocks.name_of(st)
				if nm.ends_with("_door") and nm != "iron_door" and Res.blocks.get_prop(st, "open") == "false":
					door = Vector3i(q.x, q.y + dy, q.z)
					break
		if door.y > -9999:
			break
	if door.y <= -9999:
		e.rt.erase("door_t")
		return
	var t := int(e.rt.get("door_t", 0)) + 1
	e.rt["door_t"] = t
	if t % 20 == 1:
		Audio.play("entity.zombie.attack_wooden_door", Vector3(door) + Vector3(0.5, 0.5, 0.5), "Hostile")
		e.rt["swing"] = 10
	if t >= 200 and int(w.difficulty) >= 3:
		e.rt.erase("door_t")
		var st0: int = w.state_at(door.x, door.y, door.z)
		var other := door + (Vector3i.DOWN if Res.blocks.get_prop(st0, "half") == "upper" else Vector3i.UP)
		em.spawn_block_particles(door, st0)
		w.set_block(door.x, door.y, door.z, 0)
		if Res.blocks.name_of(w.state_at(other.x, other.y, other.z)).ends_with("_door"):
			w.set_block(other.x, other.y, other.z, 0)
		Audio.play("entity.zombie.break_wooden_door", Vector3(door) + Vector3(0.5, 0.5, 0.5), "Hostile")


# ------------------------------------------------------------------ goats

## wiki Goat: every 30 s - 5 min (screaming goats 5 - 15 s) a goat tries to ram a single unmoving target it can see
## 4-16 blocks away (players outside Creative / Peaceful, armor stands, any mob but ghasts and goats): it locks onto the
## target's position, lowers its head, stomps and speeds at it - a target that leaves its block meanwhile is not rammed;
## a hit deals 2 (Hard 3; babies 1 / 1.5) and 9 blocks of knockback (babies 4.5); a miss stops a couple of blocks on,
## unless it hits a solid block first; ramming a #snaps_goat_horn block (stone, ores, logs, packed ice) drops one of its
## horns. Holding wheat stops a preparing goat. 2 % of goats scream; adults spawn without one horn 10 % of the time;
## both horns share a variant (regular: ponder / sing / seek / feel, screaming: admire / call / yearn / dream).
## Not on the wiki (Java GoatAi / RamTarget): the 20-tick head-lowering, the charge speed modifier 3.0.
const GOAT_RAM_PREP := 20
const GOAT_RAM_SPEED := 3.0
## knockback strength that carries a standing player the wiki's 9 / 4.5 blocks (lifted 0.4, air drag 0.91, then ground
## friction 0.546: distance = 7.96 x strength)
const GOAT_KB := 1.13
const GOAT_KB_BABY := 0.565
static var _snaps: Dictionary = {}


static func goat_init(em, e, baby: bool) -> void:
	var rng: RandomNumberGenerator = em.rng
	e.data["screaming"] = rng.randf() < 0.02
	var horns := [true, true]
	if not baby and rng.randf() < 0.1:
		horns[rng.randi_range(0, 1)] = false
	e.data["horns"] = horns
	var opts: Array = Tags.resolve("instrument", "#minecraft:" + ("screaming_goat_horns" if e.data["screaming"] else "regular_goat_horns")).keys()
	if not opts.is_empty():
		e.data["horn"] = "minecraft:" + str(opts[rng.randi_range(0, opts.size() - 1)]).trim_prefix("minecraft:")
	e.data["ram_cd"] = _ram_cooldown(em, e)
	_goat_jump_cooldown(em, e)


static func _ram_cooldown(em, e) -> int:
	return em.rng.randi_range(100, 300) if bool(e.data.get("screaming", false)) else em.rng.randi_range(600, 6000)


## Hides the horn model parts the goat has lost (GoatModel left / right horn visibility).
static func goat_horns_render(e) -> void:
	if e.node == null:
		return
	var horns: Array = e.data.get("horns", [true, true])
	for k in 2:
		var n := e.node.find_child("horn_l" if k == 0 else "horn_r", true, false) as Node3D
		if n != null:
			n.visible = bool(horns[k])
	e.rt["horn_vis"] = true


static func _goat_tick(em, e, p: Player, dist: float, fl: int = 0) -> bool:
	if not e.data.has("horns"):
		goat_init(em, e, e.baby_age < 0)
	if not e.rt.has("horn_vis"):
		goat_horns_render(e)
	if e.rt.has("lj_air") or e.rt.has("lj_prep"):
		return _goat_long_jump(em, e, fl)
	var held := p.inventory.held()
	var tempted: bool = not p.dead and dist < 10.0 and not held.is_empty() and held.name() == "wheat"
	if not e.rt.has("ram_t") and not e.rt.has("ram_to") and not tempted and e.panic <= 0 and e.love <= 0:
		var jcd := int(e.data.get("jump_cd", 0))
		if jcd > 0:
			e.data["jump_cd"] = jcd - 1
		elif e.on_ground and fl == 0 and not e.data.has("leash") and _goat_find_jump(em, e):
			return true   # (Java: no long jumps on a lead)
	if e.rt.has("ram_to"):
		_goat_charge(em, e, p)
		return false
	if e.rt.has("ram_t"):
		var t = e.rt.get("ram_tgt")
		if tempted or e.panic > 0 or t == null or t.dead or Vector3i(t.pos.floor()) != Vector3i((e.rt["ram_at"] as Vector3).floor()):
			_goat_end(em, e, not tempted and e.panic <= 0)   # (target moved off its block: Java's cooldown on fail)
			return false
		MobAI._face(e, t.pos, 0.5)
		e.body_yaw = e.yaw
		e.vel.x = 0.0
		e.vel.z = 0.0
		var rt := int(e.rt["ram_t"]) - 1
		e.rt["ram_t"] = rt
		if rt <= 0:
			e.rt.erase("ram_t")
			e.rt["ram_to"] = e.rt["ram_at"]
			e.rt["ram_from"] = e.pos
			e.rt["ram_n"] = 0
			return false
		return true
	var cd := int(e.data.get("ram_cd", 0)) - 1
	e.data["ram_cd"] = maxi(cd, 0)
	if cd > 0 or tempted or e.panic > 0 or e.love > 0 or (e.age + e.uid) % 10 != 0:
		return false
	var tgt = _ram_target(em, e, p, dist)
	if tgt == null:
		return false
	e.rt["ram_t"] = GOAT_RAM_PREP
	e.rt["ram_tgt"] = tgt
	e.rt["ram_at"] = tgt.pos
	var pitch: float = em.rng.randf_range(1.3, 1.7) if e.baby_age < 0 else em.rng.randf_range(0.8, 1.2)
	Audio.play("entity.goat.screaming.prepare_ram" if bool(e.data.get("screaming", false)) else "entity.goat.prepare_ram", e.pos, "Neutral", 0.8, pitch)
	return true


## The nearest visible ram target 4-16 blocks away that is standing still.
static func _ram_target(em, e, p: Player, dist: float):
	var eye: Vector3 = e.pos + Vector3(0, e.h * 0.85, 0)
	var best = null
	var bd := 257.0
	if not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE) and int(em.world.difficulty) > 0 and dist >= 4.0 and dist <= 16.0:
		if Vector2(p.pos.x - p.prev_pos.x, p.pos.z - p.prev_pos.z).length_squared() < 1e-6 and _los(em, eye, p.eye_pos()):
			best = p
			bd = dist * dist
	for o in em.ents:
		if o == e or o.dead or not (o.kind == "mob" or o.kind == "armor_stand") or o.id == "goat" or o.id == "ghast" or o.id == "happy_ghast":
			continue
		var d2: float = o.pos.distance_squared_to(e.pos)
		if d2 < 16.0 or d2 >= bd or Vector2(o.pos.x - o.prev.x, o.pos.z - o.prev.z).length_squared() > 1e-6:
			continue
		if _los(em, eye, o.pos + Vector3(0, o.h * 0.5, 0)):
			best = o
			bd = d2
	return best


## Charging (EntityManager steers at rt.ram_to x GOAT_RAM_SPEED): hit whatever box it runs into, stop at a block or
## past the locked spot.
static func _goat_charge(em, e, p: Player) -> void:
	var n := int(e.rt.get("ram_n", 0)) + 1
	e.rt["ram_n"] = n
	var from: Vector3 = e.rt.get("ram_from", e.pos)
	var to: Vector3 = e.rt["ram_to"]
	var dir := Vector3(to.x - from.x, 0.0, to.z - from.z)
	dir = dir.normalized() if dir.length_squared() > 1e-6 else Vector3(-sin(deg_to_rad(e.yaw)), 0, cos(deg_to_rad(e.yaw)))
	var baby: bool = e.baby_age < 0
	var hw: float = e.w * 0.5 + 0.1
	var mn := Vector3(e.pos.x - hw, e.pos.y, e.pos.z - hw)
	var mx := Vector3(e.pos.x + hw, e.pos.y + e.h, e.pos.z + hw)
	var victim = null
	if not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE) and _boxes_touch(mn, mx, p.aabb_min(), p.aabb_max()):
		victim = p
	else:
		for o in em.ents:
			if o != e and not o.dead and (o.kind == "mob" or o.kind == "armor_stand") and o.id != "goat":
				var ow: float = o.w * 0.5
				if _boxes_touch(mn, mx, Vector3(o.pos.x - ow, o.pos.y, o.pos.z - ow), Vector3(o.pos.x + ow, o.pos.y + o.h, o.pos.z + ow)):
					victim = o
					break
	var scream: bool = bool(e.data.get("screaming", false))
	if victim != null:
		var dmg := 1.0 if baby else 2.0
		var kb := GOAT_KB_BABY if baby else GOAT_KB
		if victim is Player:
			var hurt: bool = (victim as Player).hurt(MobAI.diff_dmg(int(em.world.difficulty), dmg), "mob", false, e.pos, e)
			if not hurt and UseItem.is_blocking(victim):
				kb *= 0.5   # (a blocking shield halves it: Java RamTarget)
			(victim as Player).knockback(kb, -dir.x, -dir.z)
		elif victim.kind == "armor_stand":
			victim.vel += dir * kb + Vector3(0, 0.4, 0)
		else:
			em._damage(victim, dmg, e)
			em._knockback(victim, kb, dir.x, dir.z)
		Audio.play("entity.goat.screaming.ram_impact" if scream else "entity.goat.ram_impact", e.pos, "Neutral", 0.8)
		_goat_end(em, e, true)
		return
	if e.hcollide:
		var w = em.world
		var ahead: Vector3 = e.pos + dir * (e.w * 0.5 + 0.3)
		var snapped := false
		if not baby:
			if _snaps.is_empty():
				_snaps = Tags.resolve("block", "#minecraft:snaps_goat_horn")
			for dy in [0.2, 0.8]:
				var st: int = w.state_at(floori(ahead.x), floori(e.pos.y + dy), floori(ahead.z))
				if st > 0 and _snaps.has(Res.blocks.name_of(st)):
					snapped = true
					break
		if snapped:
			drop_horn(em, e)
		_goat_end(em, e, true)
		return
	var flat := Vector2(to.x - e.pos.x, to.z - e.pos.z)
	if flat.dot(Vector2(dir.x, dir.z)) < -1.0 or n > 60:
		_goat_end(em, e, true)   # (missed: past the locked spot)


## wiki Goat long jump: to cross obstacles a goat "lowers its head, then it leaps up to 10 blocks vertically and up to 5
## blocks laterally" (a +-5 box here), never more than 5 blocks down, not again for 30-60 s (entity.goat.long_jump /
## screaming.long_jump, volume 0.8), not on honey blocks. Not on the wiki (Java LongJumpToRandomPos / LongJumpUtil):
## up to 20 landing spots tried (one per tick, far ones likelier), launch angles 65 / 70 / 75 / 80 degrees with the
## ballistic speed (gravity 0.08, no drag in flight) up to 1.5 blocks per tick, a clear path for the goat's box, 40
## ticks of preparation; failed searches wait the same cooldown.
const GOAT_JUMP_TRIES := 20
const GOAT_JUMP_PREP := 40
const GOAT_JUMP_MAX_V := 1.5
const GOAT_JUMP_ANGLES := [65.0, 70.0, 75.0, 80.0]


static func _goat_jump_cooldown(em, e) -> void:
	e.data["jump_cd"] = em.rng.randi_range(600, 1200)


## One landing candidate per tick; true when a jump was chosen (the goat then prepares).
static func _goat_find_jump(em, e) -> bool:
	var tries := int(e.rt.get("lj_tries", 0)) + 1
	if tries > GOAT_JUMP_TRIES:
		e.rt.erase("lj_tries")
		_goat_jump_cooldown(em, e)
		return false
	e.rt["lj_tries"] = tries
	var rng: RandomNumberGenerator = em.rng
	var dx := rng.randi_range(-5, 5)
	var dy := rng.randi_range(-5, 5)
	var dz := rng.randi_range(-5, 5)
	var d2 := dx * dx + dy * dy + dz * dz
	if dx * dx + dz * dz < 4 or rng.randi_range(0, 74) >= d2:
		return false   # (too close for a long jump / weighted toward far spots)
	var w = em.world
	var c := Vector3i(e.pos.floor())
	var q := c + Vector3i(dx, dy, dz)
	var b := Res.blocks
	var fl := b.st_flags
	var below: int = w.state_at(q.x, q.y - 1, q.z)
	if below <= 0 or (fl[below] & BlockRegistry.F_COLLIDE) == 0 or (fl[below] & BlockRegistry.F_LIQUID) != 0:
		return false
	var bn := b.name_of(below)
	if bn == "honey_block" or bn == "powder_snow" or bn == "magma_block" or bn == "cactus":
		return false
	for k in 2:
		var s: int = w.state_at(q.x, q.y + k, q.z)
		if s > 0 and ((fl[s] & BlockRegistry.F_COLLIDE) != 0 or (fl[s] & BlockRegistry.F_LIQUID) != 0 or b.name_of(s) == "powder_snow"):
			return false
	var stand: int = w.state_at(c.x, c.y - 1, c.z)
	if stand > 0 and b.name_of(stand) == "honey_block":
		return false
	var to := Vector3(q.x + 0.5, q.y, q.z + 0.5)
	var angs: Array = GOAT_JUMP_ANGLES.duplicate()
	angs.shuffle()
	for a in angs:
		var v := _goat_jump_vector(e, to, deg_to_rad(float(a)))
		if v != Vector3.ZERO and _goat_path_clear(w, e, v, to):
			e.rt.erase("lj_tries")
			e.rt["lj_prep"] = GOAT_JUMP_PREP
			e.rt["lj_v"] = v
			e.rt["lj_to"] = to
			MobControl.nav_stop(e)
			e.has_target = false
			return true
	return false


## Launch velocity for the angle (Java LongJumpUtil: v^2 = g x^2 / (x sin 2a - 2 y cos^2 a)), ZERO when too fast.
static func _goat_jump_vector(e, to: Vector3, a: float) -> Vector3:
	var d: Vector3 = to - e.pos
	var x := Vector2(d.x, d.z).length()
	var den: float = x * sin(2.0 * a) - 2.0 * d.y * cos(a) * cos(a)
	if x < 0.01 or den <= 0.0:
		return Vector3.ZERO
	var v := sqrt(0.08 * x * x / den)
	if v > GOAT_JUMP_MAX_V:
		return Vector3.ZERO
	var h := Vector2(d.x, d.z) / x * v * cos(a)
	return Vector3(h.x, v * sin(a), h.y)


## The goat's box along the flight (gravity 0.08 per tick, no drag) meets no block until it is over the landing spot.
static func _goat_path_clear(w, e, v: Vector3, to: Vector3) -> bool:
	var pos: Vector3 = e.pos
	var vel := v
	var fl := Res.blocks.st_flags
	var hw: float = e.w * 0.5 - 0.05
	for i in 40:
		pos += vel
		vel.y -= 0.08
		if Vector2(to.x - pos.x, to.z - pos.z).dot(Vector2(v.x, v.z)) <= 0.0:
			return pos.y >= to.y - 0.5
		for o in [Vector3(-hw, 0.1, -hw), Vector3(hw, 0.1, hw), Vector3(-hw, 0.1, hw), Vector3(hw, 0.1, -hw), Vector3(0, e.h - 0.1, 0)]:
			var s: int = w.state_at(floori(pos.x + o.x), floori(pos.y + o.y), floori(pos.z + o.z))
			if s > 0 and (fl[s] & BlockRegistry.F_COLLIDE) != 0:
				return false
	return false


## Preparing (stands still facing the spot, head toward it) then the leap; in flight no drag until it lands.
static func _goat_long_jump(em, e, fl: int) -> bool:
	if e.rt.has("lj_prep"):
		var to: Vector3 = e.rt["lj_to"]
		MobAI._face(e, to, 0.5)
		e.body_yaw = e.yaw
		MobControl.set_look(e, to, 30.0, 40.0)
		e.vel.x = 0.0
		e.vel.z = 0.0
		var t := int(e.rt["lj_prep"]) - 1
		if t > 0:
			e.rt["lj_prep"] = t
			return true
		e.rt.erase("lj_prep")
		e.vel = e.rt["lj_v"]
		e.rt["lj_air"] = true
		e.rt["lj_t0"] = e.age
		var scream: bool = bool(e.data.get("screaming", false))
		Audio.play("entity.goat.screaming.long_jump" if scream else "entity.goat.long_jump", e.pos, "Neutral", 0.8)
	self_moved = true
	em._physics(e, em.world.state_at, Res.blocks, 0.08, 1.0, 0.0, 1.0)
	if (e.on_ground and e.vel.y <= 0.0) or fl != 0 or e.age - int(e.rt.get("lj_t0", e.age)) > 100:
		for k in ["lj_air", "lj_v", "lj_to", "lj_t0"]:
			e.rt.erase(k)
		_goat_jump_cooldown(em, e)
	return true


static func _boxes_touch(a0: Vector3, a1: Vector3, b0: Vector3, b1: Vector3) -> bool:
	return a0.x < b1.x and a1.x > b0.x and a0.y < b1.y and a1.y > b0.y and a0.z < b1.z and a1.z > b0.z


static func _goat_end(em, e, cooldown: bool) -> void:
	for k in ["ram_t", "ram_tgt", "ram_at", "ram_to", "ram_from", "ram_n"]:
		e.rt.erase(k)
	if cooldown:
		e.data["ram_cd"] = _ram_cooldown(em, e)


## A goat horn of the goat's variant from a side it still has (entity.goat.horn_break 0.9).
static func drop_horn(em, e) -> bool:
	var horns: Array = e.data.get("horns", [true, true])
	var sides: Array = []
	for k in 2:
		if bool(horns[k]):
			sides.append(k)
	if sides.is_empty():
		return false
	horns[sides[em.rng.randi_range(0, sides.size() - 1)]] = false
	e.data["horns"] = horns
	var s := ItemStack.named("goat_horn", 1)
	s.components["minecraft:instrument"] = str(e.data.get("horn", "minecraft:ponder_goat_horn"))
	em.spawn_item(e.pos + Vector3(0, e.h * 0.5, 0), s)
	Audio.play("entity.goat.horn_break", e.pos, "Neutral", 0.9)
	goat_horns_render(e)
	return true


# ------------------------------------------------------------------ llamas and wolves

## wiki Llama: a bred llama's strength is a random 1 .. the stronger parent's strength, +1 3 % of the time (max 5).
static func llama_bred_strength(rng: RandomNumberGenerator, a, b) -> int:
	var s := rng.randi_range(1, maxi(int(a.data.get("strength", 3)), int(b.data.get("strength", 3))))
	if rng.randf() < 0.03:
		s += 1
	return mini(s, 5)


## wiki Llama: llamas are hostile toward wolves and spit at them without provocation (not at tamed wolves), every 2 s.
## Range not on the wiki: the llama's follow range 16 (as for players). Target re-picked every 10 ticks.
static func _llama_wolf_tick(em, e) -> void:
	if e.target_player or e.baby_age < 0 or Taming.is_tamed(e) and em.world.player.vehicle == e:
		return
	var wt = e.rt.get("wolf_tgt")
	if (e.age + e.uid) % 10 == 0:
		wt = null
		var bd := 256.0
		for o in near_list(em, "wolf"):
			if not o.dead and not Taming.is_tamed(o):
				var d2: float = o.pos.distance_squared_to(e.pos)
				if d2 < bd:
					bd = d2
					wt = o
		e.rt["wolf_tgt"] = wt
	if wt == null or wt.dead:
		return
	MobControl.set_look(e, wt.pos + Vector3(0, wt.h * 0.5, 0), 30.0, 30.0)
	if e.attack_cd > 0:
		return
	var from: Vector3 = e.pos + Vector3(0, e.h * 0.85, 0)
	var aim: Vector3 = wt.pos + Vector3(0, wt.h * 0.5, 0) - from
	if not _los(em, from, from + aim):
		return
	aim.y += Vector2(aim.x, aim.z).length() * 0.2
	em.spawn_projectile("llama_spit", from, spread(em.rng, aim, mob_inaccuracy(em.world)) * 1.5, e)
	Audio.play("entity.llama.spit", e.pos, "Neutral")
	e.attack_cd = 40


# ------------------------------------------------------------------ warden anger

## wiki Warden: anger toward a player 0-150 (decays 1 per second: Sculk._warden); reaching 80 makes it roar, add 20 more
## and pursue. Sources: vibrations +35 / projectiles +10 (Sculk.vibrate), touching it +35 (1 s cooldown), a direct
## attack +100.
static func warden_anger(e, add: int) -> void:
	if add <= 0:
		return
	var a0 := int(e.data.get("anger", 0))
	var a := mini(150, a0 + add)
	if a0 < 80 and a >= 80:
		a = mini(150, a + 20)
		Audio.play("entity.warden.roar", e.pos, "Hostile", 3.0)
	e.data["anger"] = a
	if a >= 80:
		e.target_player = true


static func _warden_tick(em, e, p: Player) -> void:
	if p.dead or p.is_creative() or p.is_spectator() or int(em.world.game_time) < int(e.rt.get("touch_until", -1)):
		return
	var pmn := p.aabb_min()
	var pmx := p.aabb_max()
	var hw: float = e.w * 0.5
	if e.pos.x + hw > pmn.x and e.pos.x - hw < pmx.x and e.pos.z + hw > pmn.z and e.pos.z - hw < pmx.z and e.pos.y + e.h > pmn.y and e.pos.y < pmx.y:
		e.rt["touch_until"] = int(em.world.game_time) + 20
		warden_anger(e, 35)


# ------------------------------------------------------------------ parrots on shoulders

## wiki Parrot: a tamed parrot that is not sitting follows its owner (teleporting when 12 blocks away) and perches on
## a free shoulder - the left one first, two at most - when it touches its owner (walking through it or flying there on
## its own); the owner must stand on the ground, out of water / powder snow, not flying. (No remount delay on the
## wiki: Java's ride cooldown, 100 ticks after spawning or hopping off.)
static func _parrot_tick(em, e, p: Player) -> void:
	if not Taming.is_tamed(e) or str(e.data.get("owner", "")) != Taming.owner_name():
		return
	if bool(e.data.get("sitting", false)):
		e.target_pos = e.pos
		e.has_target = true
		e.vel = Vector3(0.0, minf(e.vel.y, 0.0), 0.0)
		return
	var cd := int(e.rt.get("ride_cd", 100)) - 1
	e.rt["ride_cd"] = cd
	var d2: float = e.pos.distance_squared_to(p.pos)
	if d2 > 144.0 and not p.flying and not p.dead:
		Taming._teleport_near(em, e, p)
		return
	var free := -1
	if (p.shoulder[0] as Dictionary).is_empty():
		free = 0
	elif (p.shoulder[1] as Dictionary).is_empty():
		free = 1
	if d2 > 25.0 or (cd <= 0 and free >= 0 and can_carry(p)):
		e.target_pos = p.pos + Vector3(0, p.eye_height() * 0.8, 0)
		e.has_target = true
	if cd > 0 or free < 0 or not can_carry(p):
		return
	var pmn := p.aabb_min()
	var pmx := p.aabb_max()
	var hw: float = e.w * 0.5
	if e.pos.x + hw > pmn.x and e.pos.x - hw < pmx.x and e.pos.z + hw > pmn.z and e.pos.z - hw < pmx.z and e.pos.y + e.h > pmn.y and e.pos.y < pmx.y:
		var d: Dictionary = em._ser(e)
		if d.is_empty():
			return
		p.shoulder[free] = d
		em._remove(e)


static func can_carry(p: Player) -> bool:
	return p.on_ground and not p.in_water and not p.in_powder_snow and not p.flying and not p.fall_flying and not p.sleeping and not p.dead and not p.is_spectator()


## wiki Parrot: shoulder parrots hop off when the player falls (about 0.75 blocks), takes damage, touches water /
## powder snow, touches lava or fire in survival, flies, glides, sleeps or becomes a spectator. Once per tick.
static func shoulder_tick(em, p: Player) -> void:
	if (p.shoulder[0] as Dictionary).is_empty() and (p.shoulder[1] as Dictionary).is_empty():
		return
	var off := p.fall_distance > 0.5 or p.hurt_time >= 9 or p.in_water or p.in_powder_snow or p.flying or p.fall_flying or p.sleeping or p.dead or p.is_spectator()
	if not off and not p.is_creative() and (p.in_lava or p.fire_ticks > 0):
		off = true
	if not off:
		return
	for k in 2:
		var d: Dictionary = p.shoulder[k]
		if d.is_empty():
			continue
		var side := Vector3(-cos(deg_to_rad(p.yaw)), 0.0, -sin(deg_to_rad(p.yaw))) * (0.4 if k == 0 else -0.4)
		var at := p.pos + side + Vector3(0, 1.4, 0)
		d["p"] = [at.x, at.y, at.z]
		var n0: int = em.ents.size()
		em._deser(d)
		if em.ents.size() > n0:
			var m = em.ents[em.ents.size() - 1]
			m.rt["ride_cd"] = 100
		p.shoulder[k] = {}


## Java ParrotOnShoulderLayer: the parrot model at (+-0.4, -1.5) in the player's model space (-1.3 when crouching), the
## left shoulder at Java +x (ours -x after the model flip).
static func render_shoulders(player_model: Node3D, p: Player, crouch: bool) -> void:
	var model: Node3D = player_model.get_node_or_null("model") if player_model != null else null
	if model == null:
		return
	for k in 2:
		var nm := "shoulder%d" % k
		var cur: Node3D = model.get_node_or_null(nm)
		var has: bool = not (p.shoulder[k] as Dictionary).is_empty()
		if has and cur == null:
			cur = EntityRenderer.build_rig(MobRegistry.get_def("parrot"))
			cur.name = nm
			model.add_child(cur)
		elif not has and cur != null:
			model.remove_child(cur)
			cur.queue_free()
			continue
		if cur != null:
			cur.position = Vector3(-0.4 if k == 0 else 0.4, -0.2 if crouch else 0.0, 0.0)


## wiki Parrot: feeding a cookie kills it (poison particles; counts as a kill by the feeding player).
static func parrot_cookie(em, e, p: Player) -> void:
	if not p.is_creative():
		p.inventory.consume_held()
	for k in 8:
		Particles.emit("effect", e.pos + Vector3(em.rng.randf_range(-0.3, 0.3), e.h * 0.5, em.rng.randf_range(-0.3, 0.3)), Vector3(0, 0.05, 0), Color(0.53, 0.64, 0.19))
	e.invuln = 0
	em._damage(e, 3.4028e38, p)


# ------------------------------------------------------------------ raid captains

## wiki Ominous Banner: a white banner with cyan lozenge, light gray base, gray pale, light gray bordure, black fess,
## light gray per fess, light gray roundel, black bordure.
static func ominous_banner() -> ItemStack:
	var s := ItemStack.named("white_banner", 1)
	s.components["minecraft:banner_patterns"] = [{"pattern": "minecraft:rhombus", "color": "cyan"}, {"pattern": "minecraft:stripe_bottom", "color": "light_gray"},
		{"pattern": "minecraft:stripe_center", "color": "gray"}, {"pattern": "minecraft:border", "color": "light_gray"},
		{"pattern": "minecraft:stripe_middle", "color": "black"}, {"pattern": "minecraft:half_horizontal", "color": "light_gray"},
		{"pattern": "minecraft:circle", "color": "light_gray"}, {"pattern": "minecraft:border", "color": "black"}]
	return s


## wiki Ominous Banner: raid captains / patrol leaders wear it on the head. Java CustomHeadLayer for a non-skull item:
## translate(0, -0.25, 0), rotY(180), scale(0.625, -0.625, -0.625), then the item's HEAD display transform; on the head
## part (ours = S * J like HeldItems).
static func render_captain(e) -> void:
	var model: Node3D = e.node.get_node_or_null("model") if e.node != null else null
	var head: Node3D = model.get_node_or_null("head") if model != null else null
	if head == null or head.get_node_or_null("captain_banner") != null:
		return
	var inner := HeldItems.item_node(ominous_banner(), "head", false)
	if inner == null:
		return
	var n := Node3D.new()
	n.name = "captain_banner"
	var j := Transform3D(Basis(), Vector3(0.0, -0.25, 0.0))
	j = j * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	j = j * Transform3D(Basis.from_scale(Vector3(0.625, -0.625, -0.625)), Vector3.ZERO)
	n.transform = Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO) * j
	n.add_child(inner)
	head.add_child(n)


# ------------------------------------------------------------------ cats

## wiki Cat: a 70 % chance per tamed cat for a morning gift (loot table gameplay/cat_morning_gift) when its owner
## sleeps through the night - not after daytime thunderstorm sleep, not from cats ordered to sit; the gift lands by the
## bed. (Cats do not lie on the bed here: tamed cats within 10 blocks of the bed count, the wiki's radius for cats
## that cannot reach it.)
static func cat_gifts(em, p: Player) -> void:
	var w = em.world
	var dtm := int(fposmod(float(w.day_time), 24000.0))
	if dtm < 12000 or dtm >= 24000:
		return
	var bed := Vector3(p.bed_pos) + Vector3(0.5, 1.0, 0.5)
	for o in near_list(em, "cat"):
		if o.dead or not Taming.is_tamed(o) or str(o.data.get("owner", "")) != Taming.owner_name() or bool(o.data.get("sitting", false)):
			continue
		if o.pos.distance_to(bed) > 10.0 or em.rng.randf() >= 0.7:
			continue
		var ctx := {"rng": w.rng, "entity_id": "cat", "by_player": false, "tool": ItemStack.new()}
		for s in Loot.roll("gameplay/cat_morning_gift", ctx):
			em.spawn_item(bed + Vector3(em.rng.randf_range(-0.5, 0.5), 0.0, em.rng.randf_range(-0.5, 0.5)), s)


## wiki Cat: every 1200 ticks a stray cat may spawn 8-32 blocks from the player at the same height in a village - at
## least five claimed beds within 48 blocks (beds are counted: no villager bed claiming here) - while fewer than five
## cats are in the 97 x 17 x 97 box around the spot. (Black cats at a full moon: no cat variants here yet.)
static var _cat_t := 0


static func cat_spawner(em, p: Player) -> void:
	_cat_t += 1
	if _cat_t < 1200:
		return
	_cat_t = 0
	var w = em.world
	if str(w.get("dimension")) != "overworld" or not w.gamerule("doMobSpawning", true) or p.dead or p.is_spectator():
		return
	var rng: RandomNumberGenerator = em.rng
	var a := rng.randf() * TAU
	var r := rng.randf_range(8.0, 32.0)
	var x := floori(p.pos.x + cos(a) * r)
	var z := floori(p.pos.z + sin(a) * r)
	if not w.column_ready(x + 0.5, z + 0.5):
		return
	var y := -99999
	for dy in [0, 1, -1, 2, -2]:
		var yy := floori(p.pos.y) + int(dy)
		var below: int = w.state_at(x, yy - 1, z)
		if below > 0 and (Res.blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0 and w.state_at(x, yy, z) == 0 and w.state_at(x, yy + 1, z) == 0:
			y = yy
			break
	if y == -99999:
		return
	var c := Vector3(x + 0.5, y, z + 0.5)
	var cats := 0
	var hut_cats := 0
	for o in near_list(em, "cat"):
		if not o.dead and absf(o.pos.x - c.x) <= 48.5 and absf(o.pos.y - c.y) <= 8.5 and absf(o.pos.z - c.z) <= 48.5:
			cats += 1
			if absf(o.pos.x - c.x) <= 8.0 and absf(o.pos.y - c.y) <= 4.0 and absf(o.pos.z - c.z) <= 8.0:
				hut_cats += 1
	if count_beds(w, c, 48) >= 5:
		if cats < 5:
			em.spawn_mob("cat", c)
	elif hut_cats == 0 and in_cat_structure(w, c):
		# wiki Cat: cats also spawn inside swamp huts (always black there), not while another cat is within the 16 x 8 x 16
		# volume around the spot
		var hc = em.spawn_mob("cat", c)
		if hc != null:
			hc.persistent = true


## In a structure of #cats_spawn_as_black (swamp huts): its "creature" spawn override (a cat) covers the spot.
static func in_cat_structure(w, at: Vector3) -> bool:
	var g = w.get("gen")
	if g == null or not ("structures" in g) or g.structures == null:
		return false
	var ov = g.structures.spawn_override(floori(at.x), floori(at.y), floori(at.z), "creature", "")
	if ov is Array:
		for s in ov:
			if s is Dictionary and str(s.get("type", "")).trim_prefix("minecraft:") == "cat":
				return true
	return false


## 26.3 cat_variant data (spawn_conditions with priorities): the variants whose best matching condition has the highest
## priority, one at random - all_black has priority 1 inside #cats_spawn_as_black structures (swamp huts) and 0 at a
## moon brightness >= 0.9 (full moon), the other ten priority 0 always: black cats in huts, at a full moon 1 in 11
## elsewhere (wiki Cat: black cats only during a full moon; one black cat per swamp hut).
static var _cat_vars: Array = []


static func cat_variant(w, at: Vector3, rng: RandomNumberGenerator, moon: float = -1.0) -> String:
	if _cat_vars.is_empty():
		for f in Res.list_files("data/minecraft/cat_variant/", ".json"):
			var j = Res.read_json(f)
			if j is Dictionary:
				_cat_vars.append([str(f).get_file().get_basename(), str(j.get("asset_id", "")), j.get("spawn_conditions", [])])
		if _cat_vars.is_empty():
			return "tabby"
	if moon < 0.0:
		var ss = w.get("sky_state") if w != null else null
		moon = float(MobAI.MOON_BRIGHTNESS.get(str(ss.moon_phase), 0.0)) if ss != null and "moon_phase" in ss else 0.0
	var hut := -1   # (structure lookups only when a variant asks)
	var best := -1000000
	var picks: Array = []
	for v in _cat_vars:
		var pr := -1000000
		for sc in v[2]:
			if not (sc is Dictionary):
				continue
			var cond = sc.get("condition")
			var ok := true
			if cond is Dictionary:
				match str(cond.get("type", "")).trim_prefix("minecraft:"):
					"structure":
						if hut < 0:
							hut = 1 if in_cat_structure(w, at) else 0
						ok = hut == 1
					"moon_brightness":
						var rg = cond.get("range", {})
						ok = moon >= float(rg.get("min", -INF)) and moon <= float(rg.get("max", INF)) if rg is Dictionary else moon == float(rg)
					_:
						ok = false
			if ok:
				pr = maxi(pr, int(sc.get("priority", 0)))
		if pr > best:
			best = pr
			picks = [v[0]]
		elif pr == best and pr > -1000000:
			picks.append(v[0])
	return str(picks[rng.randi_range(0, picks.size() - 1)]) if not picks.is_empty() else "tabby"


## The cat's variant texture (asset_id of its cat_variant).
static func cat_texture(e) -> void:
	if e.node == null:
		return
	var tex := "entity/cat/cat_" + str(e.data.get("variant", "tabby"))
	for v in _cat_vars:
		if v[0] == str(e.data.get("variant", "")):
			tex = str(v[1]).trim_prefix("minecraft:")
	var m := EntityRenderer.material(tex)
	for mi in _meshes(e.node):
		(mi as MeshInstance3D).material_override = m


## Bed heads within r blocks (chunk palettes first: only sections holding a bed are scanned).
static func count_beds(w, at: Vector3, r: int) -> int:
	var b := Res.blocks
	var n := 0
	if w.get("cm") == null or not ("chunks" in w.cm):
		return 0
	for cx in range((floori(at.x) - r) >> 4, ((floori(at.x) + r) >> 4) + 1):
		for cz in range((floori(at.z) - r) >> 4, ((floori(at.z) + r) >> 4) + 1):
			var ch: Chunk = w.cm.get_chunk(cx, cz)
			if ch == null or ch.state < Chunk.DECORATED:
				continue
			for s in Coords.SECTIONS:
				var sec: Chunk.Section = ch.sections[s]
				var has := false
				for st in sec.pal:
					if st > 0 and b.name_of(st).ends_with("_bed"):
						has = true
						break
				if not has:
					continue
				var y0 := Coords.MIN_Y + s * 16
				for yy in 16:
					for zz in 16:
						for xx in 16:
							var st2 := ch.get_block(xx, y0 + yy, zz)
							if st2 > 0 and b.name_of(st2).ends_with("_bed") and b.get_prop(st2, "part") == "head":
								if Vector3(cx * 16 + xx + 0.5, y0 + yy, cz * 16 + zz + 0.5).distance_to(at) <= float(r):
									n += 1
	return n


# ------------------------------------------------------------------ mob effects

## Mob effects in e.data["fx"] = {id: [amplifier, ticks]} (wiki Effect): poison 1 per 25 >> amp ticks (not below 1 HP;
## undead and spiders immune), wither 1 per 40 >> amp, regeneration +1 per 50 >> amp; speed / slowness change the
## movement speed (+20 % / -15 % per level), fire resistance blocks fire damage.
static func has_effect(e, id: String) -> bool:
	var fx = e.data.get("fx")
	return fx is Dictionary and (fx as Dictionary).has(id)


static func add_effect(e, id: String, amp: int, ticks: int) -> void:
	if (id == "poison" or id == "regeneration") and e.id in UNDEAD:
		return   # wiki Poison / Regeneration: no effect on undead mobs
	if id == "poison" and e.id in ["spider", "cave_spider"]:
		return   # wiki Spider: immune to poison
	if not (e.data.get("fx") is Dictionary):
		e.data["fx"] = {}
	var fx: Dictionary = e.data["fx"]
	var cur = fx.get(id)
	if cur is Array and (int(cur[0]) > amp or (int(cur[0]) == amp and int(cur[1]) >= ticks)):
		return
	fx[id] = [amp, ticks]
	if id == "glowing":
		GlowOutline.track(e)   # (the outline renderer follows it until the effect ends)


static func tick_effects(em, e) -> void:
	var fx = e.data.get("fx")
	if not (fx is Dictionary) or (fx as Dictionary).is_empty():
		e.data.erase("fx")
		return
	for id in (fx as Dictionary).keys():
		var v: Array = fx[id]
		var amp := int(v[0])
		var t := int(v[1]) - 1
		match str(id):
			"poison":
				if t % maxi(1, 25 >> amp) == 0 and e.hp > 1.0:
					e.invuln = 0
					em._damage(e, 1.0, null, "magic")
			"wither":
				if t % maxi(1, 40 >> amp) == 0:
					e.invuln = 0
					em._damage(e, 1.0, null)
			"regeneration":
				if t % maxi(1, 50 >> amp) == 0:
					e.hp = minf(max_hp(e), e.hp + 1.0)
		if t <= 0:
			(fx as Dictionary).erase(id)
		else:
			v[1] = t
	if (fx as Dictionary).is_empty():
		e.data.erase("fx")


static func speed_mult(e) -> float:
	var fx = e.data.get("fx")
	if not (fx is Dictionary):
		return 1.0
	var m := 1.0
	if (fx as Dictionary).has("speed"):
		m *= 1.0 + 0.2 * (int(fx["speed"][0]) + 1)
	if (fx as Dictionary).has("slowness"):
		m *= maxf(0.0, 1.0 - 0.15 * (int(fx["slowness"][0]) + 1))
	return m


## A potion's effects on a mob (Potions.EFFECTS; scale < 1 for splash distance). Instant Health heals 4 << amp and
## Instant Damage deals 6 << amp magic damage - swapped for undead mobs (wiki Instant Health / Instant Damage).
static func apply_potion(em, e, potion: String, scale: float = 1.0) -> void:
	for ef in Potions.EFFECTS.get(potion, []):
		var id: String = ef[0]
		var undead: bool = e.id in UNDEAD
		if id == "instant_health" or id == "instant_damage":
			if (id == "instant_health") != undead:
				e.hp = minf(max_hp(e), e.hp + float(4 << int(ef[1])) * scale)
			else:
				e.invuln = 0
				em._damage(e, float(6 << int(ef[1])) * scale, null, "magic")
		else:
			var ticks := roundi(float(ef[2]) * scale)
			if ticks > 20:
				add_effect(e, id, int(ef[1]), ticks)
