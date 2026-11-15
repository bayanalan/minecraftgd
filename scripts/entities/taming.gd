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
const TEMPER_FOOD := {"sugar": 3, "wheat": 3, "apple": 3, "hay_block": 0, "golden_carrot": 5, "golden_apple": 10, "enchanted_golden_apple": 10}
# wiki Horse: health restored / foal growth speed-up (ticks) per food
const HORSE_HEAL := {"sugar": 1.0, "wheat": 2.0, "apple": 3.0, "golden_carrot": 4.0, "golden_apple": 10.0, "hay_block": 20.0}
const HORSE_GROW := {"sugar": 600, "wheat": 400, "apple": 1200, "golden_carrot": 1200, "golden_apple": 4800, "hay_block": 3600}
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
	if e.baby_age < 0 and e.id in ["horse", "donkey", "mule"] and HORSE_GROW.has(nm):
		# wiki Horse: food speeds up a foal's growth
		e.baby_age = mini(0, e.baby_age + int(HORSE_GROW[nm]))
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("entity.horse.eat", e.pos, "Neutral")
		return true
	if e.id in NAUTILI:
		return _nautilus_interact(em, e, p, held, nm)
	if (e.id == "camel" and nm == "cactus") or (e.id == "camel_husk" and nm == "rabbit_foot"):
		# wiki Camel: cactus heals a hurt camel 2; wiki Camel Husk: a rabbit's foot heals it (no amount on the wiki: the
		# camel's 2 is used)
		var cmax := float(e.data.get("max_hp", def["hp"]))
		if e.hp < cmax:
			e.hp = minf(cmax, e.hp + 2.0)
			if not p.is_creative():
				p.inventory.consume_held()
			Audio.play("entity.%s.eat" % e.id, e.pos, "Neutral")
			return true
	if e.id == "happy_ghast" and e.baby_age < 0 and nm == "snowball":
		# wiki Happy Ghast: each snowball fed to a ghastling cuts its remaining growth time by 10 %
		e.baby_age = mini(0, e.baby_age + int(-e.baby_age * 0.1))
		if not p.is_creative():
			p.inventory.consume_held()
		return true
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
	var max_hp := float(e.data.get("max_hp", def["hp"]))
	if e.id == "zombie_horse" and nm == "red_mushroom":
		# wiki Zombie Horse: a red mushroom heals it by 3; feeding an untamed one raises its temper by 3
		if e.hp >= max_hp and is_tamed(e):
			return true
		e.hp = minf(max_hp, e.hp + 3.0)
		if not is_tamed(e):
			e.data["temper"] = mini(100, int(e.data.get("temper", 0)) + 3)
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("entity.horse.eat", e.pos, "Neutral")
		return true
	if e.id == "zombie_horse" and is_tamed(e) and TEMPER_FOOD.has(nm):
		return true   # wiki Zombie Horse: tamed zombie horses can no longer be fed horse food items
	if e.id in NEEDS_TAMING and TEMPER_FOOD.has(nm) and not (is_tamed(e) and nm in BREED_FOOD):
		if is_tamed(e) and e.hp >= max_hp and e.id in ["horse", "donkey", "mule"]:
			return true   # wiki Horse: a tamed horse at full health refuses food (and is not mounted while holding it)
		e.data["temper"] = mini(100, int(e.data.get("temper", 0)) + int(TEMPER_FOOD[nm]))
		e.hp = minf(max_hp, e.hp + (float(HORSE_HEAL.get(nm, 2.0)) if e.id in ["horse", "donkey", "mule"] else 2.0))
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
	if e.id == "parrot" and nm == "cookie":
		MobBehaviors.parrot_cookie(em, e, p)
		return true
	if not is_tamed(e):
		if not tame_food.has(nm) or e.baby_age < 0 and e.id != "wolf":
			return false
		if not p.is_creative():
			p.inventory.consume_held()
		# wiki Parrot: 1/10 per seed; wolves / cats 1/3 (Java nextInt(10) / nextInt(3))
		if em.rng.randi_range(0, (9 if e.id == "parrot" else 2)) == 0:
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
	if e.id == "wolf":
		var wf: Dictionary = Tags.resolve("item", "#minecraft:wolf_food")   # (game data: meat, fish, rabbit stew)
		if not wf.is_empty():
			food = wf.keys()
	if food.has(nm) and e.hp < float(e.data.get("max_hp", def["hp"])):
		# wiki Wolf: healing 2x the food's hunger points (raw chicken 4, rabbit stew 20); wiki Cat: fish heal 2
		var heal := maxf(1.0, float(Res.items.food_nutrition[held.item])) * (2.0 if e.id == "wolf" else 1.0)
		e.hp = minf(float(e.data.get("max_hp", def["hp"])), e.hp + heal)
		if not p.is_creative():
			p.inventory.consume_held()
		return true
	if food.has(nm):
		return false   # breeding
	e.data["sitting"] = not bool(e.data.get("sitting", false))
	e.has_target = false
	e.vel = Vector3(0, e.vel.y, 0)
	return true


## wiki Nautilus: each pufferfish / bucket of pufferfish fed to an untamed adult tames it with a 1/3 chance; any fish or
## bucket of fish heals a hurt adult (pufferfish 2, raw cod 4, cooked cod 10, cooked salmon 12: twice the food's
## nutrition - buckets count as their fish) and cuts a baby's remaining growth time by 10 %; at full health it is
## bred (EntityManager love mode: false here). A fed bucket comes back as a water bucket (as with axolotls: not on
## the wiki). Tamed nautiluses are passive (no retaliation: MobBehaviors.retaliate).
static func _nautilus_feed(em, e, p: Player, held: ItemStack, nm: String) -> bool:
	var fish := nm.trim_suffix("_bucket")
	var used := false
	if e.baby_age < 0:
		e.baby_age = mini(0, e.baby_age + int(-e.baby_age * 0.1))
		used = true
	elif not is_tamed(e) and fish == "pufferfish":
		# (wiki Zombie Nautilus: tamed the same way, 1/3 per pufferfish / bucket of pufferfish)
		used = true
		if em.rng.randi_range(0, 2) == 0:
			e.data["owner"] = owner_name()
			e.persistent = true
			e.angry = false
			e.target_player = false
			e.rt.erase("anger_t")
			em.spawn_hearts(e.pos + Vector3(0, e.h, 0))
		else:
			for k in 7:
				Particles.emit("smoke", e.pos + Vector3(em.rng.randf_range(-0.5, 0.5), em.rng.randf_range(0.3, 1.0), em.rng.randf_range(-0.5, 0.5)))
	elif e.id == "nautilus" and e.hp < float(e.data.get("max_hp", e.def["hp"])):
		var fid: int = Res.items.id(fish)
		var heal := 2.0 * maxf(1.0, float(Res.items.food_nutrition[fid]) if fid > 0 else 1.0)
		e.hp = minf(float(e.data.get("max_hp", e.def["hp"])), e.hp + heal)
		used = true
	if not used:
		return false
	Audio.play("entity.%s.eat" % e.id, e.pos, "Neutral")
	if not p.is_creative():
		if nm.ends_with("_bucket"):
			p.inventory.set_slot(p.inventory.selected, ItemStack.named("water_bucket", 1))
		else:
			p.inventory.consume_held()
	return true


## wiki Nautilus / Zombie Nautilus: tamed adults take a saddle and nautilus armor (used on it; shears take the armor off
## first, then the saddle; sneaking opens its inventory) and are ridden once saddled. Fish go to _nautilus_feed first.
static func _nautilus_interact(em, e, p: Player, held: ItemStack, nm: String) -> bool:
	if (e.def.get("food", []) as Array).has(nm) or nm == "pufferfish" or nm == "pufferfish_bucket":
		return _nautilus_feed(em, e, p, held, nm)   # (false: breeding food for EntityManager's love mode)
	if e.baby_age < 0 or not is_tamed(e) or str(e.data.get("owner", "")) != owner_name():
		return false
	var wet: bool = em._in_fluid(e, em.world.state_at, Res.blocks) == 1
	var armored: bool = e.data.get("horse_armor") is Dictionary and not (e.data["horse_armor"] as Dictionary).is_empty()
	var saddled := bool(e.data.get("saddle", false))
	if nm == "saddle" and not saddled:
		e.data["saddle"] = true
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("item.nautilus_saddle_underwater_equip" if wet else "item.nautilus_saddle_equip", e.pos, "Neutral")
		return true
	if nm.ends_with("_nautilus_armor") and not armored:
		var one := held.copy()
		one.count = 1
		e.data["horse_armor"] = one.to_dict()
		if not p.is_creative():
			p.inventory.consume_held()
		Audio.play("item.armor.equip_nautilus", e.pos, "Neutral")
		return true
	if nm == "shears" and (armored or saddled):
		if armored:
			em.spawn_item(e.pos + Vector3(0, e.h, 0), ItemStack.from_dict(e.data["horse_armor"]))
			e.data["horse_armor"] = {}
			Audio.play("item.armor.unequip_nautilus", e.pos, "Neutral")
		else:
			em.spawn_item(e.pos + Vector3(0, e.h, 0), ItemStack.named("saddle", 1))
			e.data["saddle"] = false
			Audio.play("item.saddle.unequip", e.pos, "Neutral")
		Audio.play("item.shears.snip", e.pos, "Players")
		if not p.is_creative():
			Interaction.damage_tool(p, 1)
		return true
	if p.sneaking:
		open_inventory(em, e)
		return true
	if p.vehicle != null or not saddled:
		return false
	mount(em, e, p)
	return true


## wiki Nautilus riding: forward moves it the way the rider faces (in water in 3D), the speed building up toward 6.5 m/s
## (the zombie nautilus 10 % faster: 7.15) - on land 0.88 / 0.97 m/s; the jump control charges a dash (longer the
## longer it is held) of up to about 12 blocks (zombie 13) every 2 s, the dash bar replacing the XP bar; dashing up out
## of the water breaches like a ~6 block jump. The rider has Breath of the Nautilus (air paused underwater). Not on the
## wiki: the build-up (water drag 0.9 / ground friction carry the input to the wiki's top speeds) and the 10-tick charge
## (Java's jump bar).
const NAUTILI := ["nautilus", "zombie_nautilus"]
const NAUT_SWIM := 6.5 / 20.0      # blocks per tick
const NAUT_LAND := 0.88 / 20.0
const NAUT_DASH := 12.0            # blocks (water drag 0.9: a dash at v carries 10 v)
const NAUT_DASH_CD := 40           # wiki: every 2 seconds


static func _nautilus_ride(em, e, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	var mult := 1.1 if e.id == "zombie_nautilus" else 1.0
	var wet: bool = em._in_fluid(e, gs, blocks) == 1
	var ctrl := _controllable(e, p)
	if ctrl:
		e.yaw = rad_to_deg(lerp_angle(deg_to_rad(e.yaw), deg_to_rad(p.yaw), 0.5))
	e.body_yaw = e.yaw
	var fwd: float = p.in_forward if ctrl else 0.0
	if fwd < 0.0:
		fwd *= 0.25
	var strafe: float = p.in_strafe * 0.5 if ctrl else 0.0
	var yr := deg_to_rad(e.yaw)
	var f_dir := Vector3(-sin(yr), 0, cos(yr))
	var r_dir := Vector3(cos(yr), 0, sin(yr))
	var sfx := "" if wet else "_land"
	var cd := int(e.rt.get("dash_cd", 0))
	if cd > 0:
		cd -= 1
		if cd == 0:
			Audio.play("entity.%s.dash_ready%s" % [e.id, sfx], e.pos, "Neutral")
		e.rt["dash_cd"] = cd
	var ch := float(e.rt.get("dash_charge", 0.0))
	if ctrl and p.in_jump and cd == 0:
		ch = minf(1.0, ch + 0.1)
	elif ch > 0.0:
		var dir: Vector3 = p.look_dir().normalized() if wet else f_dir
		e.vel = dir * (NAUT_DASH * mult * 0.1 * ch)
		e.rt["dash_cd"] = NAUT_DASH_CD
		Audio.play("entity.%s.dash%s" % [e.id, sfx], e.pos, "Neutral")
		ch = 0.0
	e.rt["dash_charge"] = ch
	if wet:
		e.vel += (p.look_dir().normalized() * fwd + r_dir * strafe) * NAUT_SWIM * mult * 0.1
		em._physics(e, gs, blocks, 0.0, 1.0, 0.0, 1.0)
		e.vel *= 0.9
	else:
		if e.on_ground:
			e.vel += (f_dir * fwd + r_dir * strafe) * NAUT_LAND * mult * (1.0 - 0.546)
		em._physics(e, gs, blocks, 0.08, 0.91, 0.6)
	var mv := Vector2(e.pos.x - e.prev.x, e.pos.z - e.prev.z).length()
	e.limb_amt = lerpf(e.limb_amt, minf(mv * 4.0, 1.0), 0.4)
	e.limb += e.limb_amt
	seat(e, p)
	p.add_effect("breath_of_the_nautilus", 0, 2)


## The nautilus dash bar (HUD, in place of the XP bar): [charge 0..1, cooling down] or [] when not riding one.
static func dash_bar(p: Player) -> Array:
	var v = p.vehicle
	if v == null or not (v is EntityManager.Ent) or v.kind != "mob" or not (v.id in NAUTILI) or not _controllable(v, p):
		return []
	return [float(v.rt.get("dash_charge", 0.0)), int(v.rt.get("dash_cd", 0)) > 0]


## Saddle / armour layers of a nautilus (the shell parts again, slightly inflated, with the installed
## entity/equipment/nautilus_body/<material>.png and nautilus_saddle/saddle.png - same UV layout as the nautilus).
static func render_gear(e) -> void:
	var ha = e.data.get("horse_armor", {})
	var an := ItemStack.from_dict(ha).name() if ha is Dictionary and not (ha as Dictionary).is_empty() else ""
	var key := an + "|" + str(bool(e.data.get("saddle", false)))
	if str(e.rt.get("gear_k", "|false")) == key:
		return
	e.rt["gear_k"] = key
	var model: Node = e.node.get_node_or_null("model") if e.node != null else null
	var body: Node = model.get_node_or_null("body") if model != null else null
	if body == null:
		return
	for c in body.get_children():
		if str(c.name).begins_with("gear"):
			c.queue_free()
	var layers: Array = []
	if an.ends_with("_nautilus_armor"):
		var m := an.trim_suffix("_nautilus_armor")
		layers.append(["entity/equipment/nautilus_body/" + ("gold" if m == "golden" else m), 0.3])
	if bool(e.data.get("saddle", false)):
		layers.append(["entity/equipment/nautilus_saddle/saddle", 0.4])
	var parts: Array = MobRigs.NAUTILUS[0]
	var boxes: Array = [[parts[2], parts[3], parts[4]]]
	for ch in parts[9]:
		boxes.append([ch[1], ch[2], ch[3]])
	var li := 0
	for layer in layers:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for bx in boxes:
			EntityRenderer.box_arrays(Vector3(bx[0][0], bx[0][1], bx[0][2]), Vector3(bx[1][0], bx[1][1], bx[1][2]), Vector2(bx[2][0], bx[2][1]), Vector2(128, 128), st, float(layer[1]))
		var mi := MeshInstance3D.new()
		mi.name = "gear%d" % li
		mi.mesh = st.commit()
		mi.material_override = EntityRenderer.material(str(layer[0]))
		body.add_child(mi)
		li += 1


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
	if e.id in NAUTILI:
		_nautilus_ride(em, e, p, gs, blocks)
		return
	var def: Dictionary = e.def
	var fwd := 0.0
	var strafe := 0.0
	var yaw_to: float = e.yaw
	if e.id in NEEDS_TAMING and not is_tamed(e):
		# RunAroundLikeCrazyGoal (wiki Horse: every 2 ticks a 2 % chance to compare the temper with a 0-99 roll)
		if e.age % 2 == 0 and em.rng.randi_range(0, 49) == 0:
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
	var speed := float(e.data.get("speed", def["speed"]))   # horses: their rolled speed (AbstractHorse.generateSpeed)
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
			e.vel.y = float(e.data.get("jump", 0.7))   # (rolled jump_strength, full charge: no jump bar)
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
	if d > 12.0 and not owner.flying:   # wiki Wolf: follows beyond 10 blocks, teleports beyond 12
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
