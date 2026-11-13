## Vehicles — boats (Java Boat: status IN_WATER/UNDER_WATER/ON_LAND/IN_AIR, floatBoat buoyancy
## (waterLevel - y)/height * 0.06153846 then *0.75, invFriction 0.9 water / land friction (halved when a player
## steers) / 0.45 under water, controlBoat: left/right +-1 deg/tick rotation, forward +0.04, back -0.005, turning
## in place +0.005) and minecarts (Java AbstractMinecart.moveAlongTrack: velocity projected onto the rail's exit
## segment, position snapped to that segment, slope accel 0.0078125, powered rail boost 0.06 / brake x0.5,
## friction 0.997 ridden / 0.96 empty, max 0.4 blocks/tick; a rider pushes a slow cart with W).
## Models: Java BoatModel / MinecartModel part layouts on the installed entity/boat/<wood>.png and
## entity/minecart/minecart.png textures. APPROXIMATE: no paddle animation, no chest/hopper/TNT/furnace carts,
## boats do not carry mobs, no boat-on-boat collisions, single rider.
class_name Vehicles
extends RefCounted

const BOAT_PARTS := [["bottom", [0, 3, 1], [-14, -9, -3], [28, 16, 3], [0, 0], 90, 0, 0],
	["back", [-15, 4, 4], [-13, -7, -1], [18, 6, 2], [0, 19], 0, 0, 270],
	["front", [15, 4, 0], [-8, -7, -1], [16, 6, 2], [0, 27], 0, 0, 90],
	["right", [0, 4, -9], [-14, -7, -1], [28, 6, 2], [0, 35], 0, 0, 180],
	["left", [0, 4, 9], [-14, -7, -1], [28, 6, 2], [0, 43], 0, 0, 0]]
const CART_PARTS := [["bottom", [0, 4, 0], [-10, -8, -1], [20, 16, 2], [0, 10], 90, 0, 0],
	["front", [-9, 4, 0], [-8, -9, -1], [16, 8, 2], [0, 0], 0, 0, 270],
	["back", [9, 4, 0], [-8, -9, -1], [16, 8, 2], [0, 0], 0, 0, 90],
	["left", [0, 4, -7], [-8, -9, -1], [16, 8, 2], [0, 0], 0, 0, 180],
	["right", [0, 4, 7], [-8, -9, -1], [16, 8, 2], [0, 0], 0, 0, 0]]
# rail shape -> [exit a, exit b] (Java AbstractMinecart.EXITS); y = 1 marks the raised end of a slope
const EXITS := {"north_south": [Vector3i(0, 0, -1), Vector3i(0, 0, 1)], "east_west": [Vector3i(-1, 0, 0), Vector3i(1, 0, 0)],
	"ascending_east": [Vector3i(-1, 0, 0), Vector3i(1, 1, 0)], "ascending_west": [Vector3i(-1, 1, 0), Vector3i(1, 0, 0)],
	"ascending_north": [Vector3i(0, 1, -1), Vector3i(0, 0, 1)], "ascending_south": [Vector3i(0, 0, -1), Vector3i(0, 1, 1)],
	"south_east": [Vector3i(0, 0, 1), Vector3i(1, 0, 0)], "south_west": [Vector3i(0, 0, 1), Vector3i(-1, 0, 0)],
	"north_west": [Vector3i(0, 0, -1), Vector3i(-1, 0, 0)], "north_east": [Vector3i(0, 0, -1), Vector3i(1, 0, 0)]}
const RAILS := ["rail", "powered_rail", "detector_rail", "activator_rail"]
const SEAT := {"boat": -0.45, "minecart": -0.25, "cushion": -0.5}
# minecart variants: the block shown inside and the container size (0 = none)
const CART_BLOCK := {"chest_minecart": ["chest", 27], "hopper_minecart": ["hopper", 5], "tnt_minecart": ["tnt", 0], "furnace_minecart": ["furnace", 0]}


static func is_cart_item(nm: String) -> bool:
	return nm == "minecart" or CART_BLOCK.has(nm)


static func container_size(e) -> int:
	if e.kind == "minecart":
		return int(CART_BLOCK.get(e.id, ["", 0])[1])
	return 27 if e.id.contains("chest") else 0


static func is_boat_item(nm: String) -> bool:
	return nm.ends_with("_boat") or nm.ends_with("_raft")


static func spawn(em, kind: String, item: String, p: Vector3, yaw: float):
	var e := EntityManager.Ent.new()
	e.kind = kind
	e.id = item
	e.pos = p
	e.prev = p
	e.yaw = yaw
	e.body_yaw = yaw
	e.hp = 4.0
	e.persistent = true
	if kind == "boat":
		e.w = 1.375
		e.h = 0.5625
		var wood := item.trim_suffix("_chest_boat").trim_suffix("_boat").trim_suffix("_chest_raft").trim_suffix("_raft")
		e.node = EntityRenderer.build_rig({"tex": "entity/boat/" + wood, "tex_size": [128, 64], "parts": BOAT_PARTS, "model_y": 0.375})
	else:
		e.w = 0.98
		e.h = 0.7
		e.node = EntityRenderer.build_rig({"tex": "entity/minecart/minecart", "tex_size": [64, 32], "parts": CART_PARTS, "model_y": 0.375})
	var model: Node3D = e.node.get_node("model")
	model.rotation.y = deg_to_rad(-90.0)   # Java renderers turn the model 90 degrees after the flip
	var inner := ""
	if kind == "minecart" and CART_BLOCK.has(item):
		inner = str(CART_BLOCK[item][0])
	elif kind == "boat" and item.contains("chest"):
		inner = "chest"
	if inner != "" and BERender.tracked(Res.blocks.default_state(inner)):
		var cn := BERender.build(BERender.item_state(Res.blocks.default_state(inner)), {})
		if cn != null:
			var ch := Node3D.new()
			ch.scale = Vector3.ONE * 0.75
			ch.position = Vector3(0, 0.25, 0.35 if kind == "boat" else 0.0)
			cn.position = Vector3(-0.5, 0, -0.5)
			ch.add_child(cn)
			e.node.add_child(ch)
	elif inner != "":
		var bm := EntityRenderer.block_item_mesh(Res.blocks.default_state(inner))
		if bm != null:
			var mi := MeshInstance3D.new()
			mi.mesh = bm
			mi.scale = Vector3.ONE * 0.75
			mi.position = Vector3(0, 0.25, 0.35 if kind == "boat" else 0.0)
			e.node.add_child(mi)
	var n := container_size(e)
	if n > 0:
		var items: Array = []
		items.resize(n)
		items.fill({})
		e.data["items"] = items
	em.add_child(e.node)
	em.ents.append(e)
	return e


## Use a boat/minecart item on the targeted block. Returns true when placed.
static func use_item(world, held: ItemStack, tgt: Dictionary) -> bool:
	var nm := held.name()
	var p: Vector3i = tgt["pos"]
	var em = world.entities
	if is_cart_item(nm):
		if not _is_rail(world.state_at(p.x, p.y, p.z)):
			return false
		spawn(em, "minecart", nm, Vector3(p) + Vector3(0.5, 0.0625, 0.5), world.player.yaw)
	elif is_boat_item(nm):
		var n: Vector3i = tgt.get("normal", Vector3i(0, 1, 0))
		var q: Vector3i = p + n
		var wet := false
		while q.y < Coords.MAX_Y and _watery(world.state_at(q.x, q.y, q.z)):
			q.y += 1
			wet = true
		var at := Vector3(q) + Vector3(0.5, -0.4 if wet else 0.0, 0.5)
		spawn(em, "boat", nm, at, world.player.yaw)
	else:
		return false
	if not world.player.is_creative():
		world.player.inventory.consume_held()
	return true


static func _watery(st: int) -> bool:
	return st > 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_LIQUID) != 0 and (Res.blocks.st_flags[st] & BlockRegistry.F_LAVA) == 0


static func _is_rail(st: int) -> bool:
	return st > 0 and Res.blocks.name_of(st) in RAILS


static func hit(em, e, p: Player) -> void:
	e.hp -= 1.0
	e.hurt_time = 10
	Audio.play("entity.boat.paddle_water" if e.kind == "boat" else "entity.minecart.riding", e.pos, "Neutral", 0.4)
	if e.hp <= 0.0 or p.is_creative():
		if p.vehicle == e:
			Taming.dismount(em, p)
		if not p.is_creative() and em.world.gamerule("doEntityDrops", true):
			em.spawn_item(e.pos + Vector3(0, 0.3, 0), ItemStack.named(e.id, 1))
		for it in e.data.get("items", []):
			var s := ItemStack.from_dict(it)
			if not s.is_empty():
				em.spawn_item(e.pos + Vector3(0, 0.3, 0), s)
		if e.id == "tnt_minecart" and not p.is_creative():
			em.explode(e.pos + Vector3(0, 0.3, 0), 4.0, em.world.gamerule("tntExplodes", true))
		em._remove(e)


## Right-click a vehicle. Chest boats: sneak opens the chest (Java); container carts open their inventory; furnace
## carts take coal/charcoal (3600 ticks of fuel each) and push away from the player; TNT carts prime with flint.
static func interact(em, e, p: Player, held: ItemStack) -> void:
	var nm := "" if held.is_empty() else held.name()
	var n := container_size(e)
	if n > 0 and (e.kind == "minecart" or p.sneaking):
		var cs = load("res://scripts/ui/container_screen.gd").new()
		cs.entity = e
		cs.kind = "hopper" if n == 5 else "chest"
		em.world.open_screen(cs)
		return
	if e.id == "furnace_minecart":
		if nm == "coal" or nm == "charcoal":
			e.data["fuel"] = mini(32000, int(e.data.get("fuel", 0)) + 3600)
			if not p.is_creative():
				p.inventory.consume_held()
		var dv: Vector3 = e.pos - p.pos
		e.data["push"] = [dv.x, dv.z]
		return
	if e.id == "tnt_minecart":
		if nm == "flint_and_steel" or nm == "fire_charge":
			prime_tnt(e)
		return
	if e.kind == "minecart" and e.id != "minecart":
		return
	if p.vehicle == null and not p.sneaking:
		Taming.mount(em, e, p)


static func prime_tnt(e) -> void:
	if int(e.data.get("fuse", -1)) < 0:
		e.data["fuse"] = 80
		Audio.play("entity.tnt.primed", e.pos, "Blocks")


## Per-tick behaviour of minecart variants (Java MinecartFurnace / MinecartTNT / MinecartHopper).
static func cart_extras(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	match e.id:
		"furnace_minecart":
			var fuel := int(e.data.get("fuel", 0))
			if fuel > 0:
				e.data["fuel"] = fuel - 1
				var pu: Array = e.data.get("push", [0.0, 0.0])
				var pv := Vector2(float(pu[0]), float(pu[1]))
				if pv.length() > 0.01:
					var hv := Vector2(e.vel.x, e.vel.z)
					if hv.length() > 0.01 and hv.dot(pv) < 0.0:
						pv = hv
					pv = pv.normalized()
					e.data["push"] = [pv.x, pv.y]
					# Java: the furnace cart keeps itself moving at about 0.2 blocks/tick on rails
					if hv.length() < 0.2:
						e.vel += Vector3(pv.x, 0, pv.y) * 0.05
				if em.rng.randf() < 0.25:
					Particles.emit("large_smoke", e.pos + Vector3(0, 0.9, 0))
		"tnt_minecart":
			var below: int = gs.call(int(floor(e.pos.x)), int(floor(e.pos.y)), int(floor(e.pos.z)))
			if below > 0 and blocks.name_of(below) == "activator_rail" and blocks.get_prop(below, "powered") == "true":
				prime_tnt(e)
			var fuse := int(e.data.get("fuse", -1))
			if fuse >= 0:
				fuse -= 1
				e.data["fuse"] = fuse
				if fuse % 5 == 0:
					Particles.emit("smoke", e.pos + Vector3(0, 1.0, 0))
				if fuse <= 0:
					em._remove(e)
					var sp := Vector2(e.vel.x, e.vel.z).length()
					em.explode(e.pos + Vector3(0, 0.3, 0), 4.0 + em.rng.randf() * 1.5 * minf(5.0, sp), em.world.gamerule("tntExplodes", true))
		"hopper_minecart":
			if e.age % 4 != 0:
				return
			var items: Array = e.data.get("items", [])
			for o in em.ents:
				if o.kind == "item" and not o.dead and o.pos.distance_to(e.pos + Vector3(0, 0.5, 0)) < 1.0:
					for i in items.size():
						var cur := ItemStack.from_dict(items[i])
						if cur.is_empty():
							items[i] = o.stack.to_dict()
							em._remove(o)
							break
						if cur.can_merge(o.stack) and cur.count + o.stack.count <= cur.max_stack():
							cur.count += o.stack.count
							items[i] = cur.to_dict()
							em._remove(o)
							break
					break
			e.data["items"] = items


static func seat(e, p: Player) -> void:
	var h: float = SEAT.get(e.kind, 0.0)
	p.prev_pos = e.prev + Vector3(0, h, 0)
	p.pos = e.pos + Vector3(0, h, 0)
	p.vel = Vector3.ZERO
	p.fall_distance = 0.0


# ------------------------------------------------------------------ boats

static func tick_boat(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	var p: Player = em.world.player
	var rider: Player = p if p.vehicle == e else null
	if e.hurt_time > 0:
		e.hurt_time -= 1
	# status (Java Boat.getStatus): water level over the boat's bottom slice
	var lvl := -1e9
	var under := false
	var x0 := int(floor(e.pos.x - e.w / 2))
	var x1 := int(floor(e.pos.x + e.w / 2))
	var z0 := int(floor(e.pos.z - e.w / 2))
	var z1 := int(floor(e.pos.z + e.w / 2))
	var y0 := int(floor(e.pos.y))
	for x in range(x0, x1 + 1):
		for z in range(z0, z1 + 1):
			for y in range(y0 - 1, y0 + 2):
				var st: int = gs.call(x, y, z)
				if st > 0 and (blocks.st_flags[st] & BlockRegistry.F_LIQUID) != 0 and (blocks.st_flags[st] & BlockRegistry.F_LAVA) == 0:
					var top := float(y) + _fluid_h(gs, blocks, x, y, z, st)
					lvl = maxf(lvl, top)
					if top > e.pos.y + e.h - 0.001 and y == y0:
						under = true
	var status := "air"
	if lvl > e.pos.y:
		status = "under" if under else "water"
	elif e.on_ground:
		status = "land"
	var grav := -0.04
	var inv := 0.05
	var buoy := 0.0
	match status:
		"water":
			buoy = (lvl - e.pos.y) / e.h
			inv = 0.9
		"under":
			buoy = 0.01
			inv = 0.45
		"air":
			inv = 0.9
		"land":
			var below: int = gs.call(int(floor(e.pos.x)), int(floor(e.pos.y - 0.1)), int(floor(e.pos.z)))
			inv = float(blocks.block_info[blocks.st_block[maxi(below, 0)]]["friction"]) if below > 0 else 0.6
			if rider != null:
				inv /= 2.0
	e.vel = Vector3(e.vel.x * inv, e.vel.y + grav, e.vel.z * inv)
	e.charge = int(float(e.charge) * inv)   # deltaRotation (stored x1000)
	if buoy > 0.0:
		e.vel.y = (e.vel.y + buoy * 0.06153846) * 0.75
	if rider != null:
		var turn := 0.0
		if rider.in_strafe > 0.0:
			turn -= 1.0
		elif rider.in_strafe < 0.0:
			turn += 1.0
		var f := 0.0
		if turn != 0.0 and rider.in_forward == 0.0:
			f += 0.005
		e.charge += int(turn * 1000.0)
		if rider.in_forward > 0.0:
			f += 0.04
		elif rider.in_forward < 0.0:
			f -= 0.005
		e.yaw += float(e.charge) / 1000.0
		var yr := deg_to_rad(e.yaw)
		e.vel += Vector3(-sin(yr) * f, 0, cos(yr) * f)
		rider.yaw += float(e.charge) / 1000.0
	else:
		e.yaw += float(e.charge) / 1000.0
	e.body_yaw = e.yaw
	_move(em, e, gs, blocks)
	if rider != null:
		seat(e, rider)


static func _fluid_h(gs: Callable, blocks: BlockRegistry, x: int, y: int, z: int, st: int) -> float:
	var above: int = gs.call(x, y + 1, z)
	if above > 0 and (blocks.st_flags[above] & BlockRegistry.F_LIQUID) != 0:
		return 1.0
	var nm := blocks.name_of(st)
	if nm != "water":
		return 1.0   # waterlogged blocks
	var lv := int(blocks.get_prop(st, "level")) if blocks.has_prop(st, "level") else 0
	return float(8 - (lv if lv < 8 else 0)) / 9.0


static func _move(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	var r := Collision.move(Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2), Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2), e.vel, gs, blocks, 0.0, e.on_ground)
	var m: Vector3 = r["motion"]
	e.pos += m
	if r["hit_x"]:
		e.vel.x = 0.0
	if r["hit_z"]:
		e.vel.z = 0.0
	if r["hit_y"]:
		e.vel.y = 0.0
	e.on_ground = r["on_ground"]
	if e.pos.y < Coords.MIN_Y - 64:
		em._remove(e)


# ------------------------------------------------------------------ minecarts

static func tick_cart(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	var p: Player = em.world.player
	var rider: Player = p if p.vehicle == e else null
	if e.hurt_time > 0:
		e.hurt_time -= 1
	var bx := int(floor(e.pos.x))
	var bz := int(floor(e.pos.z))
	var by := int(floor(e.pos.y))
	var st: int = gs.call(bx, by, bz)
	if not _is_rail(st):
		by -= 1
		st = gs.call(bx, by, bz)
	if not _is_rail(st):
		# off the rails: gravity + ground drag (Java comeOffTrack, max 0.4)
		e.vel.y -= 0.04
		_move(em, e, gs, blocks)
		if e.on_ground:
			e.vel.x *= 0.5
			e.vel.z *= 0.5
		e.vel.x *= 0.95
		e.vel.z *= 0.95
		if rider != null:
			seat(e, rider)
		return
	var shape := str(blocks.get_prop(st, "shape")) if blocks.has_prop(st, "shape") else "north_south"
	var ex: Array = EXITS.get(shape, EXITS["north_south"])
	var a: Vector3i = ex[0]
	var b: Vector3i = ex[1]
	var nm := blocks.name_of(st)
	var powered := nm == "powered_rail" and blocks.has_prop(st, "powered") and str(blocks.get_prop(st, "powered")) == "true"
	var brake := nm == "powered_rail" and not powered
	# slope acceleration (downhill = toward the low exit)
	if a.y == 1:
		e.vel += Vector3(b.x - a.x, 0, b.z - a.z).normalized() * 0.0078125
	elif b.y == 1:
		e.vel += Vector3(a.x - b.x, 0, a.z - b.z).normalized() * 0.0078125
	var d := Vector3(b.x - a.x, 0, b.z - a.z)
	var dl := d.length()
	var hv := Vector2(e.vel.x, e.vel.z)
	if e.vel.x * d.x + e.vel.z * d.z < 0.0:
		d = -d
	var spd := minf(2.0, hv.length())
	e.vel = Vector3(spd * d.x / dl, 0.0, spd * d.z / dl)
	# rider push (Java: player input when the cart is nearly stopped)
	if rider != null and rider.in_forward > 0.0 and spd < 0.01:
		var look := rider.look_dir()
		e.vel += Vector3(look.x, 0, look.z).normalized() * 0.1
	if brake:
		if e.vel.length() < 0.03:
			e.vel = Vector3.ZERO
		else:
			e.vel *= 0.5
	# snap to the exit segment, then move
	var p0 := Vector3(bx + 0.5 + a.x * 0.5, by, bz + 0.5 + a.z * 0.5)
	var p1 := Vector3(bx + 0.5 + b.x * 0.5, by, bz + 0.5 + b.z * 0.5)
	var seg := p1 - p0
	var t := clampf(((e.pos.x - p0.x) * seg.x + (e.pos.z - p0.z) * seg.z) / maxf(seg.x * seg.x + seg.z * seg.z, 1e-6), 0.0, 1.0)
	e.pos = Vector3(p0.x + seg.x * t, by + (t if b.y == 1 else (1.0 - t if a.y == 1 else 0.0)) + 0.0625, p0.z + seg.z * t)
	var mx := clampf(e.vel.x, -0.4, 0.4)
	var mz := clampf(e.vel.z, -0.4, 0.4)
	var np: Vector3 = e.pos + Vector3(mx, 0, mz)
	var t2 := clampf(((np.x - p0.x) * seg.x + (np.z - p0.z) * seg.z) / maxf(seg.x * seg.x + seg.z * seg.z, 1e-6), -0.5, 1.5)
	var hy := 0.0
	if b.y == 1:
		hy = t2
	elif a.y == 1:
		hy = 1.0 - t2
	var nxt: int = gs.call(int(floor(np.x)), by, int(floor(np.z)))
	var solid_ahead := nxt > 0 and (blocks.st_flags[nxt] & BlockRegistry.F_COLLIDE) != 0 and not _is_rail(nxt) and hy < 0.5
	if solid_ahead:
		e.vel = Vector3.ZERO
	else:
		e.pos = Vector3(np.x, by + maxf(hy, 0.0) + 0.0625, np.z)
	if powered:
		var sp := Vector2(e.vel.x, e.vel.z).length()
		if sp > 0.01:
			e.vel += Vector3(e.vel.x / sp, 0, e.vel.z / sp) * 0.06
		else:
			# Java: a stopped cart on a powered rail is pushed away from a solid block at either end
			for q in [a, b]:
				var w: int = gs.call(bx + q.x, by, bz + q.z)
				if w > 0 and (blocks.st_flags[w] & BlockRegistry.F_FULL_SHAPE) != 0:
					e.vel = Vector3(-q.x, 0, -q.z) * 0.02
	var fr := 0.997 if rider != null else 0.96
	e.vel = Vector3(e.vel.x * fr, 0.0, e.vel.z * fr)
	e.vel.x = clampf(e.vel.x, -0.4, 0.4)
	e.vel.z = clampf(e.vel.z, -0.4, 0.4)
	if Vector2(e.vel.x, e.vel.z).length() > 0.001:
		e.yaw = rad_to_deg(atan2(-e.vel.x, e.vel.z))
		e.body_yaw = e.yaw
	e.on_ground = true
	if rider != null:
		seat(e, rider)
