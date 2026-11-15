## Sensors — redstone inputs driven by entities, daylight, projectiles and lightning (minecraft.wiki values; Java
## BasePressurePlateBlock / WeightedPressurePlateBlock / DaylightDetectorBlock / TargetBlock / LightningRodBlock):
## - Pressure plates: an entity touching the plate's box (1..15 px wide, 4 px tall) presses it; wooden plates count
##   every entity, stone / polished blackstone plates only mobs and players; light weighted plates output
##   ceil(min(n, 15) / 15 x 15), heavy ones ceil(min(n, 150) / 150 x 15). While pressed they re-check every 20 ticks
##   (weighted: 10) and release when empty. Spectators never press.
## - Daylight detectors: every 20 ticks (dimensions with sky light): sky light - sky darkening, scaled by the sun angle
##   (round(i x cos(angle eased 20 % toward 0 / 2 pi))); inverted: 15 - (sky light - darkening). Use toggles inverted.
## - Target blocks: a projectile hit outputs max(1, ceil(15 x clamp((0.5 - d) / 0.5))) by the distance d of the hit
##   from the face centre, for 20 ticks (arrows, tridents) or 8 ticks (other projectiles).
## - Lightning rods: powered for 8 ticks when struck; natural strikes go to the closest exposed rod within 128 blocks.
## - Tripwires: the entity loop hands strings an entity crosses to Tripwires.check_pressed.
## - Detector rails: 15 while a minecart touches them, re-checked every 20 ticks; comparators read chest / hopper carts.
## Contract: static; tick(world) every game tick (host), on_projectile_hit(world, hit, kind), lightning(world, pos),
## find_rod(world, at), detector_check(world, pos, state).
class_name Sensors

const PLATE_BOX_MIN := Vector3(1.0 / 16.0, 0.0, 1.0 / 16.0)
const PLATE_BOX_MAX := Vector3(15.0 / 16.0, 4.0 / 16.0, 15.0 / 16.0)

static var _pressed: Dictionary = {}   # plate pos -> game tick of its next re-check


static func is_plate(name: String) -> bool:
	return name.ends_with("_pressure_plate")


## Sound set of a plate / button (Java BlockSetType): stone, wooden, cherry_wood, bamboo_wood, nether_wood, metal.
static func set_type(name: String) -> String:
	if name.begins_with("stone_") or name.begins_with("polished_blackstone_"):
		return "stone"
	if name.ends_with("weighted_pressure_plate"):
		return "metal"
	if name.begins_with("cherry_"):
		return "cherry_wood"
	if name.begins_with("bamboo_"):
		return "bamboo_wood"
	if name.begins_with("crimson_") or name.begins_with("warped_"):
		return "nether_wood"
	return "wooden"


## Entity boxes [min, max, living, triggers tripwires] (wiki String: area effect clouds, markers, thrown eyes of ender
## and the ender dragon never trigger tripwire; spectators trigger nothing).
static func _boxes(world) -> Array:
	var out: Array = []
	var p = world.get("player")
	if p != null and not p.dead and not p.is_spectator():
		out.append([p.aabb_min(), p.aabb_max(), true, true])
	if world.get("entities") != null and world.entities != null:
		for e in world.entities.ents:
			if e.dead or e.kind == "frame" or e.kind == "painting":
				continue
			var hw: float = e.w / 2.0
			out.append([e.pos - Vector3(hw, 0, hw), e.pos + Vector3(hw, e.h, hw), e.kind == "mob" or e.kind == "armor_stand",
				e.kind != "cloud" and e.id != "eye_of_ender" and e.id != "ender_dragon" and e.id != "marker"])
	return out


## Per state: 1 = pressure plate, 2 = tripwire (built once; the entity loop checks cells by table, not by name).
static var _kind := PackedByteArray()


static func _kind_table() -> PackedByteArray:
	var b := Res.blocks
	if _kind.size() != b.total_states:
		var per_block := PackedByteArray()
		per_block.resize(b.names.size())
		for i in b.names.size():
			var n: String = b.names[i]
			per_block[i] = 1 if is_plate(n) else (2 if n == "tripwire" else 0)
		var t := PackedByteArray()
		t.resize(b.total_states)
		for s in range(1, b.total_states):
			t[s] = per_block[b.st_block[s]]
		_kind = t
	return _kind


static func _count(world, boxes: Array, q: Vector3i, living_only: bool) -> int:
	var mn := Vector3(q) + PLATE_BOX_MIN
	var mx := Vector3(q) + PLATE_BOX_MAX
	var n := 0
	for bx in boxes:
		if living_only and not bx[2]:
			continue
		var a: Vector3 = bx[0]
		var b: Vector3 = bx[1]
		if a.x < mx.x and b.x > mn.x and a.y < mx.y and b.y > mn.y and a.z < mx.z and b.z > mn.z:
			n += 1
	return n


## Java getSignalStrength for the plate at q.
static func plate_signal(world, boxes: Array, q: Vector3i, name: String) -> int:
	if name == "light_weighted_pressure_plate" or name == "heavy_weighted_pressure_plate":
		var mw := 15 if name.begins_with("light") else 150
		var c := mini(_count(world, boxes, q, false), mw)
		return ceili(float(c) / float(mw) * 15.0) if c > 0 else 0
	return 15 if _count(world, boxes, q, set_type(name) == "stone") > 0 else 0


static func _plate_power(st: int) -> int:
	var b := Res.blocks
	if b.has_prop(st, "power"):
		return int(b.get_prop(st, "power"))
	return 15 if b.get_prop(st, "powered") == "true" else 0


## Java BasePressurePlateBlock.checkPressed.
static func _check_plate(world, boxes: Array, q: Vector3i, st: int) -> void:
	var b := Res.blocks
	var name := b.name_of(st)
	var old := _plate_power(st)
	var nw := plate_signal(world, boxes, q, name)
	if nw != old:
		var ns := b.with_prop(st, "power", str(nw)) if b.has_prop(st, "power") else b.with_prop(st, "powered", "true" if nw > 0 else "false")
		world.set_block(q.x, q.y, q.z, ns)
		Redstone.on_changed(world, q)
		Redstone.on_changed(world, q + Vector3i.DOWN)
	var snd := "block.%s_pressure_plate.click_%s" % [set_type(name), "on" if nw > 0 else "off"]
	if nw > 0 and old == 0:
		Audio.play(snd, Vector3(q) + Vector3(0.5, 0.1, 0.5), "Blocks")
	elif nw == 0 and old > 0:
		Audio.play(snd, Vector3(q) + Vector3(0.5, 0.1, 0.5), "Blocks")
	if nw > 0:
		_pressed[q] = int(world.game_time) + (10 if name.ends_with("weighted_pressure_plate") else 20)
	else:
		_pressed.erase(q)


## True when a section the block range covers may hold a pressure plate or tripwire string (or its chunk is not in the
## table: no data to decide on).
static func _sensor_sections(chunks: Dictionary, x0: int, x1: int, y0: int, y1: int, z0: int, z1: int) -> bool:
	var s0 := clampi((y0 - Coords.MIN_Y) >> 4, 0, Coords.SECTIONS - 1)
	var s1 := clampi((y1 - Coords.MIN_Y) >> 4, 0, Coords.SECTIONS - 1)
	for cx in range(x0 >> 4, (x1 >> 4) + 1):
		for cz in range(z0 >> 4, (z1 >> 4) + 1):
			var ch = chunks.get((cx << 32) | (cz & 0xFFFFFFFF))
			if ch == null or (ch as Chunk).sections.is_empty():
				return true
			for s in range(s0, s1 + 1):
				if Interest.section_mask((ch as Chunk).sections[s]) & Interest.SENSOR:
					return true
	return false


static func tick(world) -> void:
	var b := Res.blocks
	var boxes := _boxes(world)
	var now := int(world.game_time)
	var kt := _kind_table()
	# entityInside: unpressed plates the entities stand in, unpowered tripwires their box crosses (every block of the
	# box: Java checks each block state the entity's bounding box touches). Boxes whose sections hold no plate or string
	# at all (Interest.SENSOR, cached per section palette) are skipped without block lookups.
	var cmv = world.get("cm")
	var chunks = cmv.get("chunks") if cmv != null else null
	for bx in boxes:
		var a: Vector3 = bx[0]
		var c: Vector3 = bx[1]
		var y := int(floor(a.y))
		var y1 := int(floor(c.y - 1.0e-6)) if bx[3] else y
		var x0 := int(floor(a.x))
		var x1 := int(floor(c.x - 1.0e-6))
		var z0 := int(floor(a.z))
		var z1 := int(floor(c.z - 1.0e-6))
		if chunks is Dictionary and not _sensor_sections(chunks, x0, x1, y, y1, z0, z1):
			continue
		for x in range(x0, x1 + 1):
			for z in range(z0, z1 + 1):
				for yy in range(y, y1 + 1):
					var st: int = world.state_at(x, yy, z)
					if st <= 0 or st >= kt.size() or kt[st] == 0:
						continue
					if kt[st] == 1:
						if yy == y and _plate_power(st) == 0:
							_check_plate(world, boxes, Vector3i(x, yy, z), st)
					elif b.get_prop(st, "powered") != "true":
						Tripwires.check_pressed(world, Vector3i(x, yy, z), st, boxes)
	# scheduled re-checks of pressed plates
	for q in _pressed.keys():
		if now >= int(_pressed[q]):
			var st2: int = world.state_at(q.x, q.y, q.z)
			if st2 > 0 and is_plate(b.name_of(st2)):
				_check_plate(world, boxes, q, st2)
			else:
				_pressed.erase(q)
	if now % 20 == 0:
		_daylight(world)
	_rods(world, now)


# ------------------------------------------------------------------ daylight detectors

static func _daylight(world) -> void:
	var dt = world.get("dim_type")
	if dt is Dictionary and not bool((dt as Dictionary).get("has_skylight", true)):
		return
	var b := Res.blocks
	for ch in BlockEntities.chunks_with(world, ["daylight_detector"]):
		for k in (ch as Chunk).block_entities:
			var d = ch.block_entities[k]
			if not (d is Dictionary) or str(d.get("id", "")) != "daylight_detector":
				continue
			var p := BlockEntities.pos_of(ch, k)
			var st: int = world.state_at(p.x, p.y, p.z)
			if st > 0 and b.name_of(st) == "daylight_detector":
				update_detector(world, p, st)


## Java DaylightDetectorBlock.updateSignalStrength.
static func update_detector(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var l: int = world.cm.get_light(p.x, p.y, p.z) if world.get("cm") != null else 0xF0
	var i := (l >> 4) - int(world.sky_darken_level())
	var f: float = float(world.celestial_angle()) * TAU
	if b.get_prop(st, "inverted") == "true":
		i = 15 - i
	elif i > 0:
		var g := 0.0 if f < PI else TAU
		f += (g - f) * 0.2
		i = roundi(i * cos(f))
	i = clampi(i, 0, 15)
	if int(b.get_prop(st, "power")) != i:
		world.set_block(p.x, p.y, p.z, b.with_prop(st, "power", str(i)))
		Redstone.on_changed(world, p)


## Use: toggles inverted and updates at once (Java DaylightDetectorBlock.useWithoutItem).
static func use_detector(world, p: Vector3i, st: int) -> void:
	var b := Res.blocks
	var ns := b.with_prop(st, "inverted", "false" if b.get_prop(st, "inverted") == "true" else "true")
	world.set_block(p.x, p.y, p.z, ns)
	if BlockEntities.get_data(world, p).is_empty():
		BlockEntities.set_data(world, p, {"id": "daylight_detector"})
	update_detector(world, p, ns)


# ------------------------------------------------------------------ target blocks / lightning rods

static var _timed: Dictionary = {}   # pos -> [game tick to switch off, "power" | "powered"]


## Java TargetBlock.onProjectileHit (hit = VoxelRaycast result).
static func on_projectile_hit(world, hit: Dictionary, projectile: String) -> void:
	var p: Vector3i = hit.get("pos", Vector3i.ZERO)
	var st: int = world.state_at(p.x, p.y, p.z)
	if st > 0 and Res.blocks.name_of(st) == "bell":
		# wiki Bell: rings when hit by any projectile
		var hn := Vector3i(Vector3(hit.get("normal", Vector3.UP)).round())
		Bells.ring(world, p, hn if hn.y == 0 else Vector3i.ZERO)
		return
	if st <= 0 or Res.blocks.name_of(st) != "target":
		return
	var loc: Vector3 = hit.get("point", Vector3(p) + Vector3(0.5, 0.5, 0.5))
	var n: Vector3 = Vector3(hit.get("normal", Vector3.UP))
	var dx := absf(loc.x - floorf(loc.x) - 0.5)
	var dy := absf(loc.y - floorf(loc.y) - 0.5)
	var dz := absf(loc.z - floorf(loc.z) - 0.5)
	var g := maxf(dx, dz) if absf(n.y) > 0.5 else (maxf(dx, dy) if absf(n.z) > 0.5 else maxf(dy, dz))
	var s := maxi(1, ceili(15.0 * clampf((0.5 - g) / 0.5, 0.0, 1.0)))
	var ticks := 20 if projectile == "arrow" or projectile == "trident" else 8
	var b := Res.blocks
	world.set_block(p.x, p.y, p.z, b.with_prop(st, "power", str(s)))
	Redstone.on_changed(world, p)
	_timed[p] = [int(world.game_time) + ticks, "power"]


## Java LightningRodBlock.onLightningStrike: powered for 8 ticks.
static func lightning(world, p: Vector3i) -> void:
	var st: int = world.state_at(p.x, p.y, p.z)
	if st <= 0 or not Res.blocks.name_of(st).ends_with("lightning_rod") or not Res.blocks.has_prop(st, "powered"):
		return
	world.set_block(p.x, p.y, p.z, Res.blocks.with_prop(st, "powered", "true"))
	Redstone.on_changed(world, p)
	_timed[p] = [int(world.game_time) + 8, "powered"]


static func _rods(world, now: int) -> void:
	if _timed.is_empty():
		return
	var b := Res.blocks
	for p in _timed.keys():
		var t: Array = _timed[p]
		if now < int(t[0]):
			continue
		_timed.erase(p)
		var st: int = world.state_at(p.x, p.y, p.z)
		if st <= 0 or not b.has_prop(st, str(t[1])):
			continue
		world.set_block(p.x, p.y, p.z, b.with_prop(st, str(t[1]), "0" if t[1] == "power" else "false"))
		Redstone.on_changed(world, p)


## wiki Lightning Rod (Java): a natural strike goes to the lightning rod within 128 blocks that is closest to the strike
## point, counting only rods with nothing but air above them (the highest block of their column). Placed rods carry a
## {"id": "lightning_rod"} block-entity entry (like Java's lightning rod POI), so only chunks holding one are visited.
## Runs once per natural bolt. Returns NONE without a rod.
const ROD_RADIUS := 128
const NONE := Vector3i(0, -99999, 0)


static func find_rod(world, at: Vector3, radius: int = ROD_RADIUS) -> Vector3i:
	if world.get("cm") == null:
		return NONE
	var b := Res.blocks
	var best := NONE
	var bd := float(radius * radius) + 0.001
	for c in BlockEntities.chunks_with(world, ["lightning_rod"]):
		var ch: Chunk = c
		if absf(ch.cx * 16 + 8 - at.x) > radius + 8 or absf(ch.cz * 16 + 8 - at.z) > radius + 8:
			continue
		for k in ch.block_entities:
			var d = ch.block_entities[k]
			if not (d is Dictionary) or str((d as Dictionary).get("id", "")) != "lightning_rod":
				continue
			var rp := BlockEntities.pos_of(ch, k)
			var st: int = world.state_at(rp.x, rp.y, rp.z)
			if st <= 0 or not b.name_of(st).ends_with("lightning_rod"):
				continue
			var d2 := (Vector3(rp) + Vector3(0.5, 0.5, 0.5)).distance_squared_to(at)
			if d2 < bd and _open_above(world, rp):
				bd = d2
				best = rp
	return best


static func _open_above(world, p: Vector3i) -> bool:
	for y in range(p.y + 1, Coords.MAX_Y):
		if world.state_at(p.x, y, p.z) != 0:
			return false
	return true


# ------------------------------------------------------------------ detector rails

## Minecarts whose box touches the block at q.
static func _carts_on(world, q: Vector3i) -> Array:
	var out: Array = []
	if world.get("entities") == null or world.entities == null:
		return out
	var mn := Vector3(q)
	var mx := mn + Vector3.ONE
	for e in world.entities.ents:
		if e.kind != "minecart" or e.dead:
			continue
		var hw: float = e.w / 2.0
		if e.pos.x - hw < mx.x and e.pos.x + hw > mn.x and e.pos.y < mx.y and e.pos.y + e.h > mn.y and e.pos.z - hw < mx.z and e.pos.z + hw > mn.z:
			out.append(e)
	return out


## wiki Detector Rail: powered (15; strong power into the block under it) while any part of a minecart's box touches
## the rail; once powered it re-checks every 20 game ticks and turns off when no cart is on it. Called by a cart on an
## unpowered detector rail (Vehicles) and by the rail's scheduled tick.
static func detector_check(world, q: Vector3i, st: int) -> void:
	var b := Res.blocks
	if st <= 0 or b.name_of(st) != "detector_rail":
		return
	var on := not _carts_on(world, q).is_empty()
	var was := b.get_prop(st, "powered") == "true"
	if on != was:
		world.set_block(q.x, q.y, q.z, b.with_prop(st, "powered", "true" if on else "false"), false)
		Redstone.on_changed(world, q)
		Redstone.on_changed(world, q + Vector3i(0, -1, 0))
	elif on:
		Redstone.request(world, q)   # comparators follow the cart's contents
	if on:
		BlockUpdates.schedule(world, q, 20)


## wiki Detector Rail: a comparator reads the fullness of a chest / hopper minecart on it (several carts: the one
## placed first), 0 for other carts and while unpowered.
static func detector_signal(world, q: Vector3i, st: int) -> int:
	if Res.blocks.get_prop(st, "powered") != "true":
		return 0
	var carts := _carts_on(world, q)
	if carts.is_empty():
		return 0
	var e = carts[0]
	if e.id != "chest_minecart" and e.id != "hopper_minecart":
		return 0
	return Redstone.items_signal(e.data.get("items", []))


static func reset() -> void:
	_pressed.clear()
	_timed.clear()
	Tripwires.reset()
	Bells.reset()
	Conduits.reset()
