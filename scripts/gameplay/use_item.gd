## UseItem — Java LivingEntity.startUsingItem / updatingUsingItem / releaseUsingItem / completeUsingItem for the
## local player:
## - consumables: food 32 ticks (dried kelp 16, honey bottle 40), potions / milk / ominous bottle 32; eat/drink
##   particles + sound every 4 ticks after the first 7 (Java shouldTriggerItemUseEffects); effect applied on completion.
## - bow (BowItem.releaseUsing): power f = (t/20)^2/3 + 2(t/20)/3 capped at 1, no shot below 0.1, arrow speed 3f,
##   inaccuracy 1, crit at full power, Power +0.5*lvl+0.5 damage, Punch knockback, Flame, Infinity (plain arrows),
##   projectile search offhand -> main hand -> inventory, arrow pickup unless infinite/creative.
## - crossbow (CrossbowItem): charge 25 - 5*Quick Charge ticks, loads on release when charged (Multishot loads 3),
##   next use fires at 3.15 speed (Multishot +-10 degrees), durability 1 per shot (3 with Multishot).
## - trident (TridentItem): thrown after >= 10 ticks at speed 2.5 (damage 8, Loyalty returns), Riptide launches the
##   player in water/rain instead.
## - shield (blocks_attacks component): blocking after 5 ticks (block_delay_seconds 0.25), frontal 90 degree cone, full
##   reduction, durability 1 + floor(damage) for damage >= 3, axes disable it for 5 s (no knockback to attackers in Java).
## - spyglass: zoom (FOV x0.1) while used.
## - brush (BrushItem / BrushableBlockEntity): used on a block for up to 200 ticks, a stroke every 10 ticks (tick 5,
##   15, ...): dust particles + brushing sound; on suspicious sand / gravel 10 strokes (10-tick cooldown) dig the loot out,
##   dusted 0-3 = brush count 0 / <3 / <6 / more, idle 40 ticks -> the count falls by 2 every 2 ticks; completion drops
##   the loot item on the brushed face, turns the block into sand / gravel and costs 1 durability.
## While using: movement x0.2 and no sprinting (Java LocalPlayer.aiStep isUsingItem).
## - crossbow ammo: firework rockets from the offhand (straight flight 1.6 / tick, 3 durability per rocket shot),
##   Piercing arrows pass through level entities (EntityManager), Channeling tridents call lightning (EntityManager).
class_name UseItem
extends RefCounted

const FOREVER := 72000
const ARROWS := ["arrow", "spectral_arrow", "tipped_arrow"]


static func anim(s: ItemStack) -> String:
	if s == null or s.is_empty():
		return ""
	var n := s.name()
	if Res.items.food_nutrition[s.item] > 0:
		return "drink" if n == "honey_bottle" else "eat"
	match n:
		"potion", "milk_bucket", "ominous_bottle":
			return "drink"
		"bow":
			return "bow"
		"crossbow":
			return "crossbow"
		"trident":
			return "spear"
		"shield":
			return "block"
		"spyglass":
			return "spyglass"
		"brush":
			return "brush"
	return ""


static func duration(s: ItemStack) -> int:
	match anim(s):
		"eat", "drink":
			var n := s.name()
			return 16 if n == "dried_kelp" else (40 if n == "honey_bottle" else 32)
		"crossbow":
			return charge_time(s) + 3
		"spyglass":
			return 1200
		"brush":
			return 200
		"bow", "spear", "block":
			return FOREVER
	return 0


static func charge_time(s: ItemStack) -> int:
	return maxi(0, 25 - 5 * Loot._ench(s, "quick_charge"))


static func is_using(p: Player) -> bool:
	return p.using_slot >= 0


static func using_stack(p: Player) -> ItemStack:
	return p.inventory.get_slot(p.using_slot) if p.using_slot >= 0 else ItemStack.new()


static func is_blocking(p: Player) -> bool:
	return p.using_slot >= 0 and anim(using_stack(p)) == "block" and p.use_ticks >= 5 and p.shield_cooldown <= 0


static func _find_ammo(p: Player) -> int:
	var inv := p.inventory
	var order: Array = [Inventory.OFFHAND, inv.selected]
	for i in 36:
		order.append(i)
	for i in order:
		var s := inv.get_slot(i)
		if not s.is_empty() and s.name() in ARROWS:
			return i
	return -1


## Right-click with the item in `slot` (main hand or offhand). True when the click was consumed.
static func start(world, p: Player, slot: int) -> bool:
	var s := p.inventory.get_slot(slot)
	var a := anim(s)
	if a == "":
		return false
	match a:
		"eat":
			var n := s.name()
			# wiki: Food - at full hunger only chorus fruit, golden apples, honey bottles and suspicious stew can be eaten
			if p.food >= 20 and not p.is_creative() and not n in ["golden_apple", "enchanted_golden_apple", "chorus_fruit", "suspicious_stew"]:
				return true
		"bow":
			if not p.is_creative() and _find_ammo(p) < 0:
				return false
		"crossbow":
			var ch = s.components.get("minecraft:charged_projectiles", [])
			if ch is Array and not ch.is_empty():
				_fire_crossbow(world, p, slot)
				return true
			var offr := p.inventory.get_slot(Inventory.OFFHAND)
			if not p.is_creative() and _find_ammo(p) < 0 and not (slot != Inventory.OFFHAND and not offr.is_empty() and offr.name() == "firework_rocket"):
				return false
		"spear":
			var md: int = Res.items.max_damage[s.item]
			if md > 0 and s.damage >= md - 1:
				return true
			if Loot._ench(s, "riptide") > 0 and not (p.in_water or world.weather_at(p.pos) == "rain"):
				return true
		"block":
			if p.shield_cooldown > 0:
				return true
		"spyglass":
			Audio.play("item.spyglass.use", p.pos, "Players")
		"brush":
			# BrushItem.useOn: only aimed at a block
			if not world.target.has("pos"):
				return false
	p.using_slot = slot
	p.use_item = s.item
	p.use_ticks = 0
	return true


static func stop(p: Player) -> void:
	if p.using_slot >= 0 and anim(using_stack(p)) == "spyglass":
		Audio.play("item.spyglass.stop_using", p.pos, "Players")
	p.using_slot = -1
	p.use_ticks = 0
	p.use_item = 0


## Every game tick; held = the use button is down.
static func tick(world, p: Player, held: bool) -> void:
	if p.shield_cooldown > 0:
		p.shield_cooldown -= 1
	if not _brushing.is_empty():
		_tick_brushables(world)
	if p.using_slot < 0:
		return
	var s := using_stack(p)
	if s.is_empty() or s.item != p.use_item or p.dead or world.screen != null:
		stop(p)
		return
	if not held:
		release(world, p)
		return
	p.use_ticks += 1
	var a := anim(s)
	var d := duration(s)
	var remaining := d - p.use_ticks
	if a == "eat" or a == "drink":
		if remaining <= d - 7 and remaining % 4 == 0:
			_use_effects(world, p, s, a)
		if remaining <= 0:
			_finish(world, p, s)
			stop(p)
	elif a == "crossbow":
		var ct := charge_time(s)
		if p.use_ticks == int(ct * 0.2):
			Audio.play("item.crossbow.loading_start", p.pos, "Players")
		elif p.use_ticks == int(ct * 0.5):
			Audio.play("item.crossbow.loading_middle", p.pos, "Players")
	elif a == "spyglass" and remaining <= 0:
		stop(p)
	elif a == "brush":
		if remaining < 0 or not world.target.has("pos"):
			stop(p)
		elif p.use_ticks % 10 == 5:
			_brush_stroke(world, p, p.using_slot)


static func release(world, p: Player) -> void:
	var s := using_stack(p)
	var t := p.use_ticks
	match anim(s):
		"bow":
			_shoot_bow(world, p, p.using_slot, t)
		"crossbow":
			if t >= charge_time(s):
				_load_crossbow(world, p, p.using_slot)
		"spear":
			if t >= 10:
				_trident(world, p, p.using_slot)
	stop(p)


static var _colors: Dictionary = {}


static func _item_color(item: int) -> Color:
	if _colors.has(item):
		return _colors[item]
	var c := Color(0.8, 0.6, 0.4)
	var t := ItemIcons.icon(item)
	var img: Image = t.get_image() if t != null and t is ImageTexture else null
	if img != null:
		var acc := Color(0, 0, 0)
		var n := 0
		for y in range(0, img.get_height(), 2):
			for x in range(0, img.get_width(), 2):
				var px := img.get_pixel(x, y)
				if px.a > 0.5:
					acc += px
					n += 1
		if n > 0:
			c = acc / n
			c.a = 1.0
	_colors[item] = c
	return c


## Java LivingEntity.spawnItemParticles: n fragments of the item's sprite 0.3-0.9 below the eye, 0.6 ahead (eating,
## an item breaking).
static func spawn_item_particles(p: Player, item: int, n: int) -> void:
	var yr := deg_to_rad(-p.yaw)
	var pr := deg_to_rad(p.pitch)   # Java Vec3.xRot(-pitch) == Godot rotation about +X by +pitch
	for i in n:
		var v := Vector3((randf() - 0.5) * 0.1, randf() * 0.1 + 0.1, 0).rotated(Vector3.RIGHT, pr).rotated(Vector3.UP, yr)
		var off := Vector3((randf() - 0.5) * 0.3, -randf() * 0.6 - 0.3, 0.6).rotated(Vector3.RIGHT, pr).rotated(Vector3.UP, yr)
		Particles.item_fragment(p.eye_pos() + off, v + Vector3(0, 0.05, 0), item)


## Java LivingEntity.triggerItemUseEffects (5 fragments per use effect).
static func _use_effects(world, p: Player, s: ItemStack, a: String) -> void:
	if a == "eat":
		Audio.play("entity.generic.eat", p.pos, "Players", 0.5 + 0.5 * randi_range(0, 1), randf_range(0.8, 1.2))
		spawn_item_particles(p, s.item, 5)
	else:
		Audio.play("entity.generic.drink", p.pos, "Players", 0.5, randf_range(0.9, 1.0))

## wiki Chorus Fruit (consume effect teleport_randomly, diameter 16): up to 16 tries at x / z +- 8 and y +- 8 (within
## the dimension's build range); the target column is searched downward to the first solid floor and must have room
## for the player without liquid; sounds item.chorus_fruit.teleport at both ends; fall distance resets.
static func chorus_teleport(world, p: Player) -> bool:
	var b := Res.blocks
	var dt = world.get("dim_type")
	var min_y := int(dt.get("min_y", Coords.MIN_Y)) if dt is Dictionary else Coords.MIN_Y
	var height := int(dt.get("logical_height", dt.get("height", 384))) if dt is Dictionary else 384
	for i in 16:
		var tx := p.pos.x + (randf() - 0.5) * 16.0
		var ty := clampf(p.pos.y + float(randi_range(0, 15) - 8), float(min_y), float(min_y + height - 1))
		var tz := p.pos.z + (randf() - 0.5) * 16.0
		var bx := int(floor(tx))
		var bz := int(floor(tz))
		var by := int(floor(ty))
		while by > min_y and not _solid(world, bx, by - 1, bz):
			by -= 1
		if by <= min_y or not _solid(world, bx, by - 1, bz):
			continue
		var free := true
		for dy in 2:
			var st: int = world.state_at(bx, by + dy, bz)
			if st > 0 and ((b.st_flags[st] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)) != 0 or _solid(world, bx, by + dy, bz)):
				free = false
		if not free:
			continue
		var from := p.pos
		Audio.play("item.chorus_fruit.teleport", from, "Players")
		p.pos = Vector3(tx, float(by), tz)
		p.prev_pos = p.pos
		p.vel = Vector3.ZERO
		p.fall_distance = 0.0
		Audio.play("item.chorus_fruit.teleport", p.pos, "Players")
		return true
	return false


static func _solid(world, x: int, y: int, z: int) -> bool:
	var st: int = world.state_at(x, y, z)
	return st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_SOLID) != 0


## Java Item.finishUsingItem for consumables.
static func _finish(world, p: Player, s: ItemStack) -> void:
	var iname := s.name()
	var slot := p.using_slot
	if world.advancements != null:
		world.advancements.trigger("consume_item", {"item": iname})
	if Res.items.food_nutrition[s.item] > 0:
		if p.eat(s.item):
			Audio.play("entity.player.burp", p.pos, "Players", 0.5, randf_range(0.9, 1.0))
			if iname == "chorus_fruit":
				chorus_teleport(world, p)
				p.add_cooldown("chorus_fruit", 20)   # wiki Chorus Fruit: 1 s cooldown
			if not p.is_creative():
				var rem := "bowl" if iname.ends_with("_stew") or iname == "beetroot_soup" else ("glass_bottle" if iname == "honey_bottle" else "")
				_consume(p, slot, rem)
			if iname == "honey_bottle":
				p.effects.erase("poison")
		return
	match iname:
		"potion":
			Potions.apply(p, Potions.potion_of(s))
			if not p.is_creative():
				_consume(p, slot, "glass_bottle")
		"milk_bucket":
			p.effects.clear()
			if not p.is_creative():
				_consume(p, slot, "bucket")
		"ominous_bottle":
			p.add_effect("bad_omen", clampi(int(s.components.get("minecraft:ominous_bottle_amplifier", 0)), 0, 4), 120000)
			Audio.play("item.ominous_bottle.dispose", p.pos, "Players")
			if not p.is_creative():
				_consume(p, slot, "")
	world.inv_changed()


static func _consume(p: Player, slot: int, remainder: String) -> void:
	var inv := p.inventory
	var s := inv.get_slot(slot)
	s.count -= 1
	if s.count <= 0:
		inv.set_slot(slot, ItemStack.named(remainder, 1) if remainder != "" else ItemStack.new())
	else:
		inv.set_slot(slot, s)
		if remainder != "" and inv.add(ItemStack.named(remainder, 1)) > 0:
			pass
	inv.changed.emit()


static func _damage_item(p: Player, slot: int, n: int) -> void:
	if p.is_creative():
		return
	var s := p.inventory.get_slot(slot)
	var md: int = Res.items.max_damage[s.item]
	if md <= 0:
		return
	var unb := Loot._ench(s, "unbreaking")
	for i in n:
		if unb > 0 and randf() >= 1.0 / (unb + 1):
			continue
		s.damage += 1
	if s.damage >= md:
		Audio.play("entity.item.break", p.pos, "Players")
		spawn_item_particles(p, s.item, 5)   # Java LivingEntity.breakItem
		p.inventory.set_slot(slot, ItemStack.new())
	else:
		p.inventory.set_slot(slot, s)


static func _spawn_arrow(world, p: Player, dir: Vector3, speed: float, inaccuracy: float, base_damage: float, crit: bool, pickup: bool, src: ItemStack, ammo: ItemStack = null) -> void:
	var v := dir.normalized()
	v += Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075 * inaccuracy
	world.entities.spawn_projectile("arrow", p.eye_pos() - Vector3(0, 0.1, 0), v * speed, p)
	var e = world.entities.ents[world.entities.ents.size() - 1]
	e.data["base_damage"] = base_damage
	e.data["crit"] = crit
	e.data["pickup"] = pickup
	e.data["punch"] = Loot._ench(src, "punch")
	if Loot._ench(src, "flame") > 0:
		e.data["flame"] = true
	# Java Arrow (tipped: potion effects at 1/8 duration) / SpectralArrow (Glowing 200 ticks)
	if ammo != null and not ammo.is_empty():
		e.data["ammo"] = ammo.name()
		if ammo.name() == "tipped_arrow":
			e.data["potion"] = Potions.potion_of(ammo)
		e.stack = ammo.copy()
		e.stack.count = 1


static func _shoot_bow(world, p: Player, slot: int, t: int) -> void:
	var f := t / 20.0
	f = minf(1.0, (f * f + f * 2.0) / 3.0)
	if f < 0.1:
		return
	var bow := p.inventory.get_slot(slot)
	var ammo := _find_ammo(p)
	if ammo < 0 and not p.is_creative():
		return
	var ammo_name := p.inventory.get_slot(ammo).name() if ammo >= 0 else "arrow"
	var infinite := p.is_creative() or (Loot._ench(bow, "infinity") > 0 and ammo_name == "arrow")
	var pw := Loot._ench(bow, "power")
	_spawn_arrow(world, p, p.look_dir(), f * 3.0, 1.0, 2.0 + (0.5 * pw + 0.5 if pw > 0 else 0.0), f >= 1.0, not infinite, bow, p.inventory.get_slot(ammo) if ammo >= 0 else null)
	Audio.play("entity.arrow.shoot", p.pos, "Players", 1.0, 1.0 / (randf() * 0.4 + 1.2) + f * 0.5)
	_damage_item(p, slot, 1)
	if not infinite and ammo >= 0:
		var a := p.inventory.get_slot(ammo)
		a.count -= 1
		p.inventory.set_slot(ammo, a if a.count > 0 else ItemStack.new())
	p.stats["used.bow"] = int(p.stats.get("used.bow", 0)) + 1
	world.inv_changed()


static func _load_crossbow(world, p: Player, slot: int) -> void:
	var cb := p.inventory.get_slot(slot)
	var n := 3 if Loot._ench(cb, "multishot") > 0 else 1
	var ammo := _find_ammo(p)
	# wiki Crossbow: a firework rocket in the offhand is loaded instead of arrows
	var off := p.inventory.get_slot(Inventory.OFFHAND)
	if slot != Inventory.OFFHAND and not off.is_empty() and off.name() == "firework_rocket":
		ammo = Inventory.OFFHAND
	if ammo < 0 and not p.is_creative():
		return
	var loaded: Array = []
	var one := p.inventory.get_slot(ammo).copy() if ammo >= 0 else ItemStack.named("arrow", 1)
	one.count = 1
	for i in n:
		loaded.append(one.to_dict())
	if not p.is_creative() and ammo >= 0:
		var a := p.inventory.get_slot(ammo)
		a.count -= 1
		p.inventory.set_slot(ammo, a if a.count > 0 else ItemStack.new())
	cb.components["minecraft:charged_projectiles"] = loaded
	p.inventory.set_slot(slot, cb)
	Audio.play("item.crossbow.loading_end", p.pos, "Players")
	world.inv_changed()


static func _fire_crossbow(world, p: Player, slot: int) -> void:
	var cb := p.inventory.get_slot(slot)
	var loaded: Array = cb.components.get("minecraft:charged_projectiles", [])
	var angles := [0.0, -10.0, 10.0]
	var rockets := false
	var pierce := Loot._ench(cb, "piercing")
	for i in loaded.size():
		var dir := p.look_dir().rotated(Vector3.UP, deg_to_rad(angles[mini(i, 2)]))
		var am := ItemStack.from_dict(loaded[i])
		if am.name() == "firework_rocket":
			rockets = true
			_spawn_rocket(world, p, dir, am)
			continue
		_spawn_arrow(world, p, dir, 3.15, 1.0, 2.0, true, i == 0 and not p.is_creative(), cb, am)
		if pierce > 0:
			world.entities.ents[world.entities.ents.size() - 1].data["pierce"] = pierce
	Audio.play("item.crossbow.shoot", p.pos, "Players", 1.0, randf_range(0.9, 1.1))
	cb.components.erase("minecraft:charged_projectiles")
	p.inventory.set_slot(slot, cb)
	# wiki Crossbow: 1 durability per shot (3 with Multishot); a firework rocket costs 3 (9 with Multishot)
	_damage_item(p, slot, (3 if rockets else 1) * (3 if loaded.size() > 1 else 1))
	world.inv_changed()


## wiki Crossbow: a firework rocket shot from a crossbow flies in a straight line at 32 m/s (1.6 blocks per tick) and
## explodes on contact with blocks and entities (or when its flight time ends: Java lifetime 10 x (flight + 1) +
## random 0-5 + random 0-6 ticks, as launched rockets); inaccuracy 1 like the arrows. Piercing does not apply.
static func _spawn_rocket(world, p: Player, dir: Vector3, am: ItemStack) -> void:
	var v := dir.normalized() + Vector3(randfn(0, 1), randfn(0, 1), randfn(0, 1)) * 0.0075
	world.entities.spawn_projectile("firework_rocket", p.eye_pos() - Vector3(0, 0.15, 0), v.normalized() * 1.6, p)
	var e = world.entities.ents[world.entities.ents.size() - 1]
	e.stack = am.copy()
	e.stack.count = 1
	e.data["angle"] = true
	var fw = am.components.get("minecraft:fireworks", {})
	e.data["life"] = 10 * ((int((fw as Dictionary).get("flight_duration", 1)) if fw is Dictionary else 1) + 1) + randi_range(0, 5) + randi_range(0, 6)


static func _trident(world, p: Player, slot: int) -> void:
	var tr := p.inventory.get_slot(slot)
	var rip := Loot._ench(tr, "riptide")
	_damage_item(p, slot, 1)
	if rip > 0:
		# Java TridentItem.releaseUsing riptide: push along the look vector, spin attack
		var f := 3.0 * ((1.0 + rip) / 4.0)
		p.vel += p.look_dir() * f
		if p.on_ground:
			p.vel.y += 1.1999999
		Audio.play("item.trident.riptide_%d" % clampi(rip, 1, 3), p.pos, "Players")
		return
	world.entities.spawn_projectile("trident", p.eye_pos(), p.look_dir() * 2.5, p)
	var e = world.entities.ents[world.entities.ents.size() - 1]
	e.stack = p.inventory.get_slot(slot).copy()
	e.data["base_damage"] = 8.0
	e.data["pickup"] = not p.is_creative()
	e.data["loyalty"] = Loot._ench(tr, "loyalty")
	Audio.play("item.trident.throw", p.pos, "Players")
	if not p.is_creative():
		p.inventory.set_slot(slot, ItemStack.new())
	world.inv_changed()


## Shield block check for incoming damage from `from` (Java LivingEntity.applyItemBlocking). Returns true if blocked.
static func try_block(p: Player, amount: float, source: String, from: Vector3, attacker = null) -> bool:
	if not is_blocking(p) or from == Vector3.INF:
		return false
	# 26.3 #bypasses_shield: #bypasses_armor + cactus, campfire, dry_out, falling anvil / stalactite, hot_floor,
	# sulfur_cube_hot, in_fire, lava, lightning_bolt, sweet_berry_bush
	if source in Player.BYPASS_ARMOR or source in ["cactus", "campfire", "dry_out", "falling_anvil", "falling_stalactite", "hot_floor", "sulfur_cube_hot", "in_fire", "lava", "lightning_bolt", "sweet_berry_bush"]:
		return false
	if not _shield_faces(p, from):
		return false
	_shield_absorb(p, amount)
	# wiki: Shield - an axe hit disables it for 5 s (100 ticks); attackers are knocked back only in Bedrock Edition
	# (Java 18w43a: shields no longer knock back attackers)
	if attacker != null and attacker is Object and attacker.get("kind") == "mob":
		var held_name := str(attacker.data.get("held", ""))
		if held_name.ends_with("_axe"):
			p.shield_cooldown = 100
			p.add_cooldown("shield", 100)   # (ItemCooldowns: the hotbar overlay)
			Audio.play("item.shield.break", p.pos, "Players", 0.8, randf_range(0.8, 1.2))
			stop(p)
	return true


## wiki Shield: "directionally blocks all attacks coming from within the horizontal direction the wielder is facing"
## (a half cylinder; pitch is unaccounted for) - blocks_attacks horizontal_blocking_angle 90 to either side.
static func _shield_faces(p: Player, from: Vector3) -> bool:
	var rx := from.x - p.pos.x
	var rz := from.z - p.pos.z
	var rl := sqrt(rx * rx + rz * rz)
	if rl < 0.001:
		return false
	var yr := deg_to_rad(p.yaw)
	# (horizontal view vector of look_dir with the pitch dropped)
	return (-sin(yr) * rx + cos(yr) * rz) / rl >= 0.0


## A blocked hit: wiki Item durability - "damage equal to the strength of the attack (rounded down) plus 1" when it
## deals 3 or more (blocks_attacks item_damage threshold 3); wiki Shield sound item.shield.block, pitch 0.8-1.2.
static func _shield_absorb(p: Player, amount: float) -> void:
	if amount >= 3.0:
		_damage_item(p, p.using_slot, 1 + int(floor(amount)))
	Audio.play("item.shield.block", p.pos, "Players", 1.0, randf_range(0.8, 1.2))


## A projectile `proj` (EntityManager.Ent) about to hit the player for `amount` from `from` (its position, Java
## DamageSource.getSourcePosition). wiki Shield: a raised shield blocks arrows, thrown tridents, ghast / blaze fireballs
## and fire charges, wither skulls, shulker bullets, llama spit, snowballs and eggs from the front; the burning, potion
## effects and Levitation they carry do not reach the blocker (the caller skips them). "Arrows from a crossbow enchanted
## with Piercing" are not blocked and cost no durability; splash / lingering potion effects are not blocked. Shooters
## of any kind (mobs, players, dispensers): only the projectile's position counts. True = blocked (the caller then
## deflects or ends the projectile as on a failed hit).
static func block_projectile(p: Player, proj, from: Vector3, amount: float) -> bool:
	if not is_blocking(p):
		return false
	var id: String = proj.id
	if id == "arrow" and int(proj.data.get("pierce", 0)) > 0:
		return false
	if amount <= 0.0 and not (id in ["snowball", "egg", "blue_egg", "brown_egg"]):
		return false   # (splash / lingering potions, bottles o' enchanting, dragon fireballs deal no hit damage)
	if not _shield_faces(p, from):
		return false
	_shield_absorb(p, amount)
	return true


# ------------------------------------------------------------------ brush / archaeology

static var _brushing: Dictionary = {}   # Vector3i -> true: suspicious blocks with a brush count (decay ticks)


static func _completion(n: int) -> int:
	return 0 if n == 0 else (1 if n < 3 else (2 if n < 6 else 3))


static func _brush_stroke(world, p: Player, slot: int) -> void:
	var tp: Vector3i = world.target["pos"]
	var st: int = world.state_at(tp.x, tp.y, tp.z)
	if st <= 0:
		return
	var nm := Res.blocks.name_of(st)
	var nrm: Vector3 = world.target.get("normal", Vector3.UP)
	var face := Vector3i(roundi(nrm.x), roundi(nrm.y), roundi(nrm.z))
	# BrushItem.spawnDustParticles: block dust drifting off the brushed face
	var hitp: Vector3 = world.target.get("point", Vector3(tp) + Vector3(0.5, 0.5, 0.5))
	for i in 3 + randi() % 4:
		Particles.emit("item", hitp + Vector3(face) * 0.05, Vector3(face) * 0.03 + Vector3(randf_range(-0.03, 0.03), 0.02, randf_range(-0.03, 0.03)), _block_color(st))
	var snd := "item.brush.brushing.generic"
	if nm == "suspicious_sand":
		snd = "item.brush.brushing.sand"
	elif nm == "suspicious_gravel":
		snd = "item.brush.brushing.gravel"
	Audio.play(snd, Vector3(tp) + Vector3(0.5, 0.5, 0.5), "Players")
	if nm == "suspicious_sand" or nm == "suspicious_gravel":
		if _brush_block(world, tp, st, face):
			_damage_item(p, slot, 1)
			world.inv_changed()


static func _block_color(st: int) -> Color:
	var nm := Res.blocks.name_of(st)
	return Color(0.86, 0.81, 0.62) if nm.contains("sand") else Color(0.55, 0.52, 0.5)


## BrushableBlockEntity.brush: true when the block was dug out.
static func _brush_block(world, pos: Vector3i, st: int, face: Vector3i) -> bool:
	var d: Dictionary = BlockEntities.get_data(world, pos).duplicate(true)
	var now: int = world.game_time
	if not d.has("hit_dir"):
		d["hit_dir"] = [face.x, face.y, face.z]
	d["reset_at"] = now + 40
	if now < int(d.get("cool_end", 0)):
		_save_brushable(world, pos, st, d)
		return false
	d["cool_end"] = now + 10
	if d.has("loot_table"):
		# unpackLootTable: the first item the table rolls (a single item in every archaeology table)
		var items := Loot.roll(str(d["loot_table"]), {"tool": null, "rng": world.rng, "by_player": true})
		d["item"] = (items[0] as ItemStack).to_dict() if not items.is_empty() else {}
		d.erase("loot_table")
	var n0 := int(d.get("count", 0))
	var before := _completion(n0)
	d["count"] = n0 + 1
	if n0 + 1 >= 10:
		_brush_complete(world, pos, st, d)
		return true
	var after := _completion(n0 + 1)
	if after != before and Res.blocks.has_prop(st, "dusted"):
		world.set_block(pos.x, pos.y, pos.z, Res.blocks.with_prop(st, "dusted", str(after)))
	_save_brushable(world, pos, world.state_at(pos.x, pos.y, pos.z), d)
	_brushing[pos] = true
	return false


static func _save_brushable(world, pos: Vector3i, st: int, d: Dictionary) -> void:
	d["id"] = Res.blocks.name_of(st)
	BlockEntities.set_data(world, pos, d)


## brushingCompleted: drop the item on the brushed side (ItemEntity at rest), turn into sand / gravel, sound, dust.
static func _brush_complete(world, pos: Vector3i, st: int, d: Dictionary) -> void:
	var nm := Res.blocks.name_of(st)
	var hd: Array = d.get("hit_dir", [0, 1, 0])
	var q := Vector3(pos) + Vector3(float(hd[0]), float(hd[1]), float(hd[2]))
	var item := ItemStack.from_dict(d.get("item", {}))
	if not item.is_empty():
		var e = world.entities.spawn_item(q + Vector3(0.5, 0.5 + 0.125, 0.5), item)
		if e != null:
			e.vel = Vector3.ZERO
	var into := "sand" if nm == "suspicious_sand" else "gravel"
	var c: Chunk = world.cm.get_chunk(pos.x >> 4, pos.z >> 4)
	if c != null:
		c.block_entities.erase(BlockEntities._key(pos))
	_brushing.erase(pos)
	world.set_block(pos.x, pos.y, pos.z, Res.blocks.default_state(into))
	Audio.play("item.brush.brushing.%s.complete" % into, Vector3(pos) + Vector3(0.5, 0.5, 0.5), "Players")
	Particles.terrain(pos, st)


## BrushableBlockEntity.checkReset (scheduled every 2 ticks): 40 idle ticks -> brush count -2 per 2 ticks.
static func _tick_brushables(world) -> void:
	var now: int = world.game_time
	if now % 2 != 0:
		return
	for pos in _brushing.keys():
		var st: int = world.state_at(pos.x, pos.y, pos.z)
		var nm := Res.blocks.name_of(st) if st > 0 else ""
		if nm != "suspicious_sand" and nm != "suspicious_gravel":
			_brushing.erase(pos)
			continue
		var d: Dictionary = BlockEntities.get_data(world, pos).duplicate(true)
		var n := int(d.get("count", 0))
		if n == 0:
			_brushing.erase(pos)
			continue
		if now < int(d.get("reset_at", 0)):
			continue
		var before := _completion(n)
		n = maxi(0, n - 2)
		d["count"] = n
		if n == 0:
			d.erase("hit_dir")
			_brushing.erase(pos)
		var after := _completion(n)
		if after != before and Res.blocks.has_prop(st, "dusted"):
			world.set_block(pos.x, pos.y, pos.z, Res.blocks.with_prop(st, "dusted", str(after)))
			st = world.state_at(pos.x, pos.y, pos.z)
		_save_brushable(world, pos, st, d)
