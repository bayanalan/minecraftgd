## Allay — Java Allay + AllayAi (brain activities in priority order) and AllayModel.setupAnim.
## Giving an item (use key, one of the held stack) makes the allay like that player; an empty hand takes it back
## (and the carried stack is dropped). Idle activity, first that applies: GoToWantedItem (nearest visible matching
## item entity within 32 blocks, speed x1.75), GoAndGiveItemsToTarget (carrying items: fly to the liked note block or
## player, speed x2.25; within 3 blocks of the target's eyes throw one item per tick, then a 60-tick pickup
## cooldown), StayCloseToTarget (not seeing a wanted item and farther than 16 blocks: back to within 4, x2.25), else a
## random stroll (fly target within 10 / 7 blocks) / pause. The liked player must be within 64 blocks (wiki: follows
## from a 64-block sphere). A note block heard within 16 blocks becomes the delivery target for 30 s (600 ticks,
## renewed by each note). Items are picked up within the bounding box grown by 1 (wiki: about 1.3 blocks), only with
## mobGriefing on, one stack carried. Flight: FlyingMoveControl (speed = modifier x flying speed 0.1, acceleration
## speed^2 per tick toward the target) and travel friction 0.91. Regenerates 1 HP every 10 ticks (EntityManager), takes
## no damage from its owner, panics (x2.5) when hurt by others. Dances while a jukebox plays within 10 blocks
## (GameEvent.JUKEBOX_PLAY radius); an amethyst shard given while dancing duplicates it (6000-tick cooldown on both).
class_name Allay

const FLY_SPEED := 0.1
const PICKUP_COOLDOWN := 60
const NOTE_LIKED_TICKS := 600
const DUPLICATION_COOLDOWN := 6000
# Java Allay.THROW_SOUND_PITCHES
const THROW_PITCHES := [0.5625, 0.625, 0.75, 0.9375, 1.0, 1.0, 1.125, 1.25, 1.5, 1.875, 2.0, 2.25, 2.5, 3.0, 3.75, 4.5]


static func held(e) -> ItemStack:
	var h = e.data.get("held_stack")
	return ItemStack.from_dict(h) if h is Dictionary and not (h as Dictionary).is_empty() else ItemStack.new()


static func _set_held(e, s: ItemStack) -> void:
	if s == null or s.is_empty():
		e.data.erase("held_stack")
	else:
		e.data["held_stack"] = s.to_dict()   # (drawn by pose: AllayModel.translateToHand)


static func inv(e) -> ItemStack:
	var h = e.data.get("inv")
	return ItemStack.from_dict(h) if h is Dictionary and not (h as Dictionary).is_empty() else ItemStack.new()


static func _set_inv(e, s: ItemStack) -> void:
	if s == null or s.is_empty():
		e.data.erase("inv")
	else:
		e.data["inv"] = s.to_dict()


## Allay.allayConsidersItemEqual: the same item (components ignored) and, for potions, the same potion.
static func _same(a: ItemStack, b: ItemStack) -> bool:
	if a.is_empty() or b.is_empty() or a.name() != b.name():
		return false
	if a.components.has("minecraft:potion_contents") or b.components.has("minecraft:potion_contents"):
		return str(a.components.get("minecraft:potion_contents", "")) == str(b.components.get("minecraft:potion_contents", ""))
	return true


## Allay.wantsToPickUp: holding something, room in the one-stack inventory, the same item, mob griefing on.
static func wants(em, e, s: ItemStack) -> bool:
	if not bool(em.world.gamerule("mobGriefing", true)):
		return false
	var h := held(e)
	if h.is_empty() or not _same(h, s):
		return false
	var cur := inv(e)
	return cur.is_empty() or (cur.can_merge(s) and cur.count < cur.max_stack())


## Allay.mobInteract. Returns true when the interaction was used.
static func interact(em, e, p: Player, hs: ItemStack) -> bool:
	var h := held(e)
	# duplication: dancing, an item of #duplicates_allays (amethyst shard), cooldown over
	if bool(e.rt.get("dancing", false)) and not hs.is_empty() and (Tags.items("duplicates_allays").has(hs.name()) if Res.mode == "vanilla" else hs.name() == "amethyst_shard") and int(e.data.get("dup_cd", 0)) <= 0:
		var twin = em.spawn_mob("allay", e.pos)
		if twin != null:
			twin.persistent = true
			twin.data["dup_cd"] = DUPLICATION_COOLDOWN
		e.data["dup_cd"] = DUPLICATION_COOLDOWN
		e.persistent = true
		for i in 3:   # entity event 18: heart particles
			Particles.emit("heart", e.pos + Vector3(em.rng.randf_range(-0.3, 0.3), 0.6 + em.rng.randf_range(0.0, 0.3), em.rng.randf_range(-0.3, 0.3)), Vector3.ZERO)
		Audio.play("block.amethyst_block.chime", e.pos, "Neutral", 2.0, 1.0)
		if not p.is_creative():
			p.inventory.consume_held()
		em.world.swing_hand()
		return true
	if h.is_empty() and not hs.is_empty():
		var one := hs.copy()
		one.count = 1
		_set_held(e, one)
		if not p.is_creative():
			p.inventory.consume_held()
		e.data["liked"] = true
		Audio.play("entity.allay.item_given", e.pos, "Neutral", 2.0, 1.0)
		em.world.swing_hand()
		em.world.inv_changed()
		return true
	if not h.is_empty() and hs.is_empty():
		_set_held(e, ItemStack.new())
		Audio.play("entity.allay.item_taken", e.pos, "Neutral", 2.0, 1.0)
		em.world.swing_hand()
		var carried := inv(e)
		_set_inv(e, ItemStack.new())
		if not carried.is_empty():
			_throw(em, e, carried, e.pos)   # BehaviorUtils.throwItem(this, stack, position())
		e.data.erase("liked")
		var left := p.inventory.add(h)
		if left > 0:
			var rest := h.copy()
			rest.count = left
			em.spawn_item(p.pos + Vector3(0, 1, 0), rest)
		em.world.inv_changed()
		return true
	return false


## Damage from the owner is ignored (Allay.hurtServer).
static func ignores_damage_from(e, source) -> bool:
	return source is Player and bool(e.data.get("liked", false))


## A note block played at pos: allays within 16 blocks (vibration range) like it (AllayAi.hearNoteblock).
static func hear_noteblock(em, pos: Vector3i) -> void:
	var c := Vector3(pos) + Vector3(0.5, 0.5, 0.5)
	for e in em.ents:
		if e.kind != "mob" or e.id != "allay" or e.dead or e.pos.distance_to(c) > 16.0:
			continue
		var cur = e.data.get("note")
		if cur == null:
			e.data["note"] = [pos.x, pos.y, pos.z]
			e.data["note_cd"] = NOTE_LIKED_TICKS
		elif Vector3i(int(cur[0]), int(cur[1]), int(cur[2])) == pos:
			e.data["note_cd"] = NOTE_LIKED_TICKS


## Delivery target (AllayAi.getItemDepositPosition): the liked note block (still a note block, liked within the
## last 30 s) above its top, else the liked player's eyes within 64 blocks (survival / creative).
static func _deposit_target(em, e, p: Player) -> Vector3:
	var nb = e.data.get("note")
	if nb != null:
		var np := Vector3i(int(nb[0]), int(nb[1]), int(nb[2]))
		if int(e.data.get("note_cd", 0)) > 0 and Res.blocks.name_of(maxi(em.world.state_at(np.x, np.y, np.z), 0)) == "note_block":
			return Vector3(np) + Vector3(0.5, 1.0, 0.5)
		e.data.erase("note")
	if bool(e.data.get("liked", false)) and p != null and not p.dead and not p.is_spectator() and p.pos.distance_to(e.pos) < 64.0:
		return p.pos + Vector3(0, p.eye_height(), 0)
	return Vector3.INF


## BehaviorUtils.throwItem from the eyes (- 0.2) toward the target, speed (0.2, 0.3, 0.2) of the unit direction.
static func _throw(em, e, s: ItemStack, target: Vector3) -> void:
	var from: Vector3 = e.pos + Vector3(0, e.h * 0.6 - 0.2, 0)
	var it = em.spawn_item(Vector3(e.pos.x, from.y, e.pos.z), s)
	if it == null:
		return
	var d: Vector3 = target - e.pos
	d = d.normalized() if d.length() > 0.0001 else Vector3.ZERO
	it.vel = Vector3(d.x * 0.2, d.y * 0.3, d.z * 0.2)
	it.pickup_delay = 10   # ItemEntity.setDefaultPickUpDelay


## One AI tick (the mob's brain + movement). Returns nothing; physics and drag included.
static func tick(em, e, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	var rng: RandomNumberGenerator = em.rng
	for k in ["note_cd", "pickup_cd", "dup_cd"]:
		if int(e.data.get(k, 0)) > 0:
			e.data[k] = int(e.data[k]) - 1
	_dance_tick(em, e)
	# Mob.baseTick ambient sound: nextInt(1000) < ambientSoundTime++ (reset to -80); with / without an item
	var amb_t := int(e.rt.get("amb", -80)) + 1
	if rng.randi_range(0, 999) < amb_t:
		amb_t = -80
		if p != null and p.pos.distance_to(e.pos) < 16.0:
			Audio.play("entity.allay.ambient_with_item" if not held(e).is_empty() else "entity.allay.ambient_without_item", e.pos, "Neutral")
	e.rt["amb"] = amb_t
	var target := Vector3.INF
	var mod := 1.0
	var close := 0.0
	# CORE: AnimalPanic (x2.5) after being hurt by something other than the owner
	if e.panic > 0:
		e.panic -= 1
		if not e.has_target or e.pos.distance_to(e.target_pos) < 1.0:
			e.target_pos = e.pos + Vector3(rng.randf_range(-5, 5), rng.randf_range(-4, 4), rng.randf_range(-5, 5))
			e.has_target = true
		target = e.target_pos
		mod = 2.5
	else:
		var wanted = null
		if int(e.data.get("pickup_cd", 0)) <= 0 and not held(e).is_empty() and e.age % 5 == 0:
			wanted = _nearest_wanted(em, e)
			e.rt["wanted"] = wanted
		elif int(e.data.get("pickup_cd", 0)) <= 0 and not held(e).is_empty():
			wanted = e.rt.get("wanted")
			if wanted != null and (wanted.dead or not em.ents.has(wanted)):
				wanted = null
		else:
			e.rt.erase("wanted")
		var dep := _deposit_target(em, e, p)
		if wanted != null:
			# GoToWantedItem (x1.75)
			target = wanted.pos
			mod = 1.75
		elif not inv(e).is_empty() and dep != Vector3.INF:
			# GoAndGiveItemsToTarget (x2.25, close enough 3): throw one item per tick within 3 blocks of the eyes
			target = dep
			mod = 2.25
			close = 3.0
			if dep.distance_to(e.pos + Vector3(0, e.h * 0.6, 0)) < 3.0:
				var cur := inv(e)
				var one := ItemStack.from_dict(cur.to_dict())
				one.count = 1
				cur.count -= 1
				_set_inv(e, cur if cur.count > 0 else ItemStack.new())
				_throw(em, e, one, dep + Vector3(0, 1, 0))
				if em.world.game_time % 7 == 0 and rng.randf() < 0.9:
					Audio.play("entity.allay.item_thrown", e.pos, "Neutral", 1.0, THROW_PITCHES[rng.randi_range(0, THROW_PITCHES.size() - 1)])
				e.data["pickup_cd"] = PICKUP_COOLDOWN
		elif dep != Vector3.INF and e.pos.distance_to(dep) >= 16.0:
			# StayCloseToTarget (x2.25, back to within 4)
			target = dep
			mod = 2.25
			close = 4.0
		else:
			# RunOne: RandomStroll.fly (x1.0) 2 / look-target approach 2 / DoNothing(30-60) 1
			if e.ai_timer > 0:
				e.ai_timer -= 1
			elif not e.has_target or e.pos.distance_to(e.target_pos) < 1.0:
				var pick := rng.randi_range(0, 4)
				if pick == 4:
					e.has_target = false
					e.ai_timer = rng.randi_range(30, 60)
				else:
					e.target_pos = e.pos + Vector3(rng.randf_range(-10, 10), rng.randf_range(-7, 7), rng.randf_range(-10, 10))
					e.target_pos.y = maxf(e.target_pos.y, _ground_y(em, e, gs, blocks) + 1.0)
					e.has_target = true
			if e.has_target:
				target = e.target_pos
			mod = 1.0
		_pickup(em, e)
	_fly(em, e, target, mod, close, gs, blocks)


static func _ground_y(_em, e, gs: Callable, blocks: BlockRegistry) -> float:
	var x := int(floor(e.pos.x))
	var z := int(floor(e.pos.z))
	var y := int(floor(e.pos.y))
	for i in 12:
		var st: int = gs.call(x, y - i, z)
		if st > 0 and (blocks.st_flags[st] & BlockRegistry.F_COLLIDE) != 0:
			return float(y - i + 1)
	return e.pos.y - 12.0


## NearestItemSensor + GoToWantedItem: the nearest item entity within 32 blocks the allay wants, in line of sight.
static func _nearest_wanted(em, e):
	var best = null
	var bd := 32.0 * 32.0
	var eye: Vector3 = e.pos + Vector3(0, e.h * 0.6, 0)
	for o in em.ents:
		if o.kind != "item" or o.dead or o.stack == null:
			continue
		var d2: float = o.pos.distance_squared_to(e.pos)
		if d2 >= bd:
			continue
		if not wants(em, e, o.stack):
			continue
		if not MobAI._has_los(em, eye, o.pos + Vector3(0, 0.2, 0)):
			continue
		best = o
		bd = d2
	return best


## Mob.aiStep item pickup: item entities touching the bounding box grown by (1, 1, 1) (Allay.getPickupReach).
static func _pickup(em, e) -> void:
	if held(e).is_empty() or int(e.data.get("pickup_cd", 0)) > 0:
		return
	var hw: float = e.w / 2.0 + 1.0
	for o in em.ents:
		if o.kind != "item" or o.dead or o.stack == null or o.pickup_delay > 0:
			continue
		if absf(o.pos.x - e.pos.x) > hw + 0.125 or absf(o.pos.z - e.pos.z) > hw + 0.125 or o.pos.y < e.pos.y - 1.25 or o.pos.y > e.pos.y + e.h + 1.0:
			continue
		if not wants(em, e, o.stack):
			continue
		var cur := inv(e)
		if cur.is_empty():
			cur = ItemStack.from_dict(o.stack.to_dict())
			cur.count = 0
		var mv: int = mini(cur.max_stack() - cur.count, o.stack.count)
		if mv <= 0:
			continue
		cur.count += mv
		_set_inv(e, cur)
		o.stack.count -= mv
		if o.stack.count <= 0:
			em._remove(o)


## FlyingMoveControl + Allay.travel: toward the target with speed = modifier x 0.1; velocity += (horizontal facing,
## vertical sign) x speed^2 per tick; friction 0.91. No target: hover (no gravity) and slow down.
static func _fly(em, e, target: Vector3, mod: float, close: float, gs: Callable, blocks: BlockRegistry) -> void:
	if target != Vector3.INF:
		var d: Vector3 = target - e.pos
		var hd := Vector2(d.x, d.z).length()
		if d.length() > maxf(close, 0.5):
			var f1 := mod * float(e.def.get("fly_speed", FLY_SPEED))   # (flying_speed attribute, wiki Attribute 0.1)
			var acc := f1 * f1
			if hd > 0.00001:
				e.vel.x += d.x / hd * acc
				e.vel.z += d.z / hd * acc
				MobAI._face(e, target, 1.0)
			if absf(d.y) > 0.00001:
				e.vel.y += (acc if d.y > 0.0 else -acc)
		else:
			e.has_target = false
	em._physics(e, gs, blocks, 0.0, 0.91)
	e.vel.y *= 0.91 / 0.98   # (_physics damps y by 0.98; Allay.travel scales the whole motion by 0.91)


# ------------------------------------------------------------------ dancing

## Allay.setJukeboxPlaying / shouldStopDancing: dance while a jukebox within 10 blocks plays (checked every 10 ticks).
static func _dance_tick(em, e) -> void:
	var dancing := bool(e.rt.get("dancing", false))
	if e.age % 10 == 0:
		var playing := BlockEntities.playing_jukebox_near(em.world, e.pos, 10.0)
		dancing = playing
		e.rt["dancing"] = dancing
	# dancingAnimationTicks / spinningAnimationTicks (0..15, spinning while dance ticks % 55 < 15)
	if dancing:
		var dt := int(e.rt.get("dance_t", 0)) + 1
		e.rt["dance_t"] = dt
		var sp := float(e.rt.get("spin", 0.0))
		e.rt["spin_o"] = sp
		sp = clampf(sp + (1.0 if (dt % 55) < 15 else -1.0), 0.0, 15.0)
		e.rt["spin"] = sp
	else:
		e.rt["dance_t"] = 0
		e.rt["spin"] = 0.0
		e.rt["spin_o"] = 0.0
	# holdingItemAnimationTicks (0..5)
	var ht := float(e.rt.get("hold", 0.0))
	e.rt["hold_o"] = ht
	e.rt["hold"] = clampf(ht + (1.0 if not held(e).is_empty() else -1.0), 0.0, 5.0)


# ------------------------------------------------------------------ animation

## Java AllayModel.setupAnim. Model-space rotations (x, y, z) map to ours as (-x, -y, z); positions (-x, -y, z) / 16.
static func pose(e, model: Node3D, ea: float, amt: float, lpos: float, hyaw: float, hpitch: float) -> void:
	var age := float(e.age) + ea
	var f := amt                                     # walkAnimationSpeed
	var f2 := age * 20.0 * PI / 180.0 + lpos
	var f3 := cos(f2) * PI * 0.15 + f
	var f4 := age * 9.0 * PI / 180.0
	var f5 := minf(f / 0.3, 1.0)
	var f6 := 1.0 - f5
	var f7 := lerpf(float(e.rt.get("hold_o", 0.0)), float(e.rt.get("hold", 0.0)), ea) / 5.0   # holdingAnimationProgress
	var head := model.get_node_or_null("head") as Node3D
	var body := model.get_node_or_null("body") as Node3D
	var root_rot := Vector3.ZERO
	if bool(e.rt.get("dancing", false)):
		var f8 := age * 8.0 * PI / 180.0 + f
		var f9 := cos(f8) * 16.0 * PI / 180.0
		var f10 := lerpf(float(e.rt.get("spin_o", 0.0)), float(e.rt.get("spin", 0.0)), ea) / 15.0   # spinningProgress
		var f11 := cos(f8) * 14.0 * PI / 180.0
		var f12 := cos(f8) * 30.0 * PI / 180.0
		var spinning := (int(e.rt.get("dance_t", 0)) % 55) < 15
		root_rot = Vector3(0.0, (PI * 4.0 * f10) if spinning else 0.0, f9 * (1.0 - f10))
		if head != null:
			head.rotation = Vector3(0.0, -(f12 * (1.0 - f10)), f11 * (1.0 - f10))
	elif head != null:
		head.rotation = Vector3(-deg_to_rad(hpitch), -deg_to_rad(hyaw), 0.0)
	model.rotation = Vector3(-root_rot.x, -root_rot.y, root_rot.z)
	# root.y += cos(f4) * 0.25 * f6 (model space, y down)
	model.position.y += -cos(f4) * 0.25 * f6 / 16.0 * model.scale.y   # (on top of the base offset)
	if body != null:
		body.rotation = Vector3(-(f5 * PI / 4.0), 0.0, 0.0)
		var rw := body.get_node_or_null("wing0") as Node3D
		var lw := body.get_node_or_null("wing1") as Node3D
		if rw != null:
			rw.rotation = Vector3(-(0.43633232 * (1.0 - f5)), -(-PI / 4.0 + f3), 0.0)
		if lw != null:
			lw.rotation = Vector3(-(0.43633232 * (1.0 - f5)), -(PI / 4.0 - f3), 0.0)
		var f13 := f7 * lerpf(-PI / 3.0, -1.134464, f5)
		var f14 := f6 * (1.0 - f7)
		var f15 := 0.43633232 - cos(f4 + PI * 3.0 / 2.0) * PI * 0.075 * f14
		var ra := body.get_node_or_null("arm0") as Node3D
		var la := body.get_node_or_null("arm1") as Node3D
		if ra != null:
			ra.rotation = Vector3(-f13, -(0.27925268 * f7), f15)
		if la != null:
			la.rotation = Vector3(-f13, -(-0.27925268 * f7), -f15)
		_hand_item(e, body, f13)


## AllayModel.translateToHand + ItemInHandLayer: root, body, translate(0, 1/16, 3/16), rotX(right arm xRot),
## scale 0.7, translate(1/16, 0, 0), then rotX(-90) rotY(180) translate(1/16, 0.125, -0.625); thirdperson right hand.
static func _hand_item(e, body: Node3D, arm_x: float) -> void:
	var hs := held(e)
	var hn := body.get_node_or_null("allay_item") as Node3D
	var key := "" if hs.is_empty() else "%d|%d" % [hs.item, hash(str(hs.components))]
	if hn != null and str(hn.get_meta("key", "")) != key:
		body.remove_child(hn)
		hn.queue_free()
		hn = null
	if key == "":
		return
	if hn == null:
		hn = Node3D.new()
		hn.name = "allay_item"
		hn.set_meta("key", key)
		var inner := HeldItems.item_node(hs, "thirdperson_righthand", false)
		if inner != null:
			hn.add_child(inner)
		body.add_child(hn)
	var j := Transform3D(Basis(), Vector3(0.0, 0.0625, 0.1875))
	j = j * Transform3D(Basis(Vector3.RIGHT, arm_x), Vector3.ZERO)
	j = j * Transform3D(Basis.from_scale(Vector3.ONE * 0.7), Vector3.ZERO)
	j = j * Transform3D(Basis(), Vector3(0.0625, 0.0, 0.0))
	j = j * Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3.ZERO)
	j = j * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	j = j * Transform3D(Basis(), Vector3(1.0 / 16.0, 0.125, -0.625))
	# (relative to the body: Java's body pose is already applied by the node; ours = S * Java with S = (-1, -1, 1))
	hn.transform = Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO) * j


## Allay.dropEquipment: the carried stack and the held item always drop on death.
static func drops(em, e) -> void:
	var c := inv(e)
	if not c.is_empty():
		em.spawn_item(e.pos + Vector3(0, 0.3, 0), c)
	var h := held(e)
	if not h.is_empty():
		em.spawn_item(e.pos + Vector3(0, 0.3, 0), h)
	_set_inv(e, ItemStack.new())
	_set_held(e, ItemStack.new())
