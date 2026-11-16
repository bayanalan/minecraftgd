## Non-living gameplay entities:
## - Primed TNT (Java PrimedTnt): fuse 80 ticks, initial hop (random horizontal 0.02, +0.2 up), gravity 0.04,
##   drag 0.98, ground friction 0.7 with -0.5 bounce, power 4 explosion; TNT caught in an explosion primes with
##   a 10-29 tick fuse.
## - Fishing hook (Java FishingHook): cast vector from the player's rotation (0.6 / |v| + triangular jitter),
##   gravity 0.03, drag 0.92, floats in water; lure wait 100-600 ticks (-100 per Lure level; ~20 % shorter in rain,
##   ~doubled without open sky), approach 20-80 ticks,
##   bite window 20-40 ticks; reeling during a bite rolls the installed gameplay/fishing loot table, pulls the
##   catch toward the player and gives 1-6 XP; rod durability -1 (catch) / -2 (snagged on ground).
## - Item frames / glow item frames (item + 8 rotations), paintings (largest installed painting variant that fits
##   the wall), armor stands (Java ArmorStandModel; stores up to 4 armor pieces).
## APPROXIMATE: hanging entities support a simple "wall still there" check; armor on stands is not drawn;
## no hook entity catching, no open-water treasure rule.
class_name MiscEntities
extends RefCounted

const STAND_PARTS := [["head", [0, 1, 0], [-1, -7, -1], [2, 7, 2], [0, 0], 0], ["body", [0, 0, 0], [-6, 0, -1.5], [12, 3, 3], [0, 26], 0],
	["arm0", [-5, 2, 0], [-2, -2, -1], [2, 12, 2], [24, 0], 0], ["arm1", [5, 2, 0], [0, -2, -1], [2, 12, 2], [32, 16], 0],
	["leg0", [-1.9, 12, 0], [-1, 0, -1], [2, 11, 2], [8, 0], 0], ["leg1", [1.9, 12, 0], [-1, 0, -1], [2, 11, 2], [40, 16], 0],
	["stick0", [0, 0, 0], [-3, 3, -1], [2, 7, 2], [16, 0], 0], ["stick1", [0, 0, 0], [1, 3, -1], [2, 7, 2], [48, 16], 0],
	["shoulder", [0, 0, 0], [-4, 10, -1], [8, 2, 2], [0, 48], 0], ["base", [0, 12, 0], [-6, 11, -6], [12, 1, 12], [0, 32], 0]]
const ARMOR_SLOT := {"helmet": 3, "chestplate": 2, "leggings": 1, "boots": 0}

static var _paintings: Array = []   # [asset_id, w, h]


# ------------------------------------------------------------------ primed TNT

static func spawn_tnt(em, p: Vector3, fuse: int) -> void:
	var e := EntityManager.Ent.new()
	e.kind = "tnt"
	e.id = "tnt"
	e.pos = p
	e.prev = p
	e.w = 0.98
	e.h = 0.98
	e.fuse = fuse
	var ang: float = em.rng.randf() * TAU
	e.vel = Vector3(-sin(ang) * 0.02, 0.2, -cos(ang) * 0.02)
	e.node = Node3D.new()
	var mesh := EntityRenderer.block_item_mesh(Res.blocks.default_state("tnt"))
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		e.node.add_child(mi)
		# Java TntMinecartRenderer.renderWhiteSolidBlock: the white flash overlay
		var fl := MeshInstance3D.new()
		fl.name = "flash"
		fl.mesh = mesh
		var wm := StandardMaterial3D.new()
		wm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		wm.albedo_color = Color(1, 1, 1, 0.75)
		fl.material_override = wm
		fl.scale = Vector3.ONE * 1.002
		fl.position = Vector3(0, -0.001, 0)
		fl.visible = false
		e.node.add_child(fl)
	em.add_child(e.node)
	em.ents.append(e)
	Audio.play("entity.tnt.primed", p, "Blocks")


static func tick_tnt(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	e.vel.y -= 0.04
	var r := Collision.move(Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2), Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2), e.vel, gs, blocks, 0.0, e.on_ground)
	var m: Vector3 = r["motion"]
	e.pos += m
	if r["hit_x"]:
		e.vel.x = 0.0
	if r["hit_z"]:
		e.vel.z = 0.0
	e.on_ground = r["on_ground"]
	e.vel *= 0.98
	if e.on_ground:
		e.vel = Vector3(e.vel.x * 0.7, e.vel.y * -0.5, e.vel.z * 0.7)
	e.fuse -= 1
	if e.fuse <= 0:
		em._remove(e)
		# wiki: TNT - power 4, the explosion 0.06125 (0.98 / 16) above the entity's position; wiki: Explosion - blocks
		# destroyed by TNT always drop (tnt_explosion_drop_decay)
		em.explode(e.pos + Vector3(0, 0.06125, 0), 4.0, em.world.gamerule("tntExplodes", true), false, em.world.gamerule("tntExplosionDropDecay", false))


# ------------------------------------------------------------------ fishing

static func cast(em, p: Player) -> void:
	var f := p.pitch
	var g := p.yaw
	var h := cos(-g * 0.017453292 - PI)
	var i := sin(-g * 0.017453292 - PI)
	var j := -cos(-f * 0.017453292)
	var k := sin(-f * 0.017453292)
	var v := Vector3(-i, clampf(-(k / j), -5.0, 5.0), -h)
	var m := v.length()
	v = Vector3(v.x * (0.6 / m + _tri(em)), v.y * (0.6 / m + _tri(em)), v.z * (0.6 / m + _tri(em)))
	var e := EntityManager.Ent.new()
	e.kind = "bobber"
	e.id = "fishing_bobber"
	e.pos = Vector3(p.pos.x - i * 0.3, p.eye_pos().y, p.pos.z - h * 0.3)
	e.prev = e.pos
	e.vel = v
	e.w = 0.25
	e.h = 0.25
	e.owner = p
	e.data = {"lure": 0, "hooked": 0, "nibble": 0, "state": "flying"}
	var lure := Loot._ench(p.inventory.held(), "lure")
	e.data["lure_lvl"] = lure
	e.data["luck_lvl"] = Loot._ench(p.inventory.held(), "luck_of_the_sea")
	var spr := Sprite3D.new()
	spr.texture = UiKit.sprite("entity/fishing_hook")
	spr.pixel_size = 0.03
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	e.node = Node3D.new()
	e.node.add_child(spr)
	var line := MeshInstance3D.new()
	line.name = "line"
	line.mesh = ImmediateMesh.new()
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(0.1, 0.1, 0.1)
	line.material_override = lm
	line.top_level = true
	e.node.add_child(line)
	em.add_child(e.node)
	em.ents.append(e)
	em.hook = e
	Audio.play("entity.fishing_bobber.throw", p.pos, "Neutral", 0.5, 0.4 / (em.rng.randf() * 0.4 + 0.8))


static func _tri(em) -> float:
	return 0.0103365 * (em.rng.randf() - em.rng.randf())


static func tick_bobber(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	var p: Player = e.owner
	var held := p.inventory.held()
	if p.dead or held.is_empty() or held.name() != "fishing_rod" or p.pos.distance_squared_to(e.pos) > 1024.0:
		em._remove(e)
		em.hook = null
		return
	var st: int = gs.call(int(floor(e.pos.x)), int(floor(e.pos.y)), int(floor(e.pos.z)))
	var in_water := st > 0 and (blocks.st_flags[st] & BlockRegistry.F_LIQUID) != 0 and (blocks.st_flags[st] & BlockRegistry.F_LAVA) == 0
	var d: Dictionary = e.data
	if in_water:
		d["state"] = "bobbing"
		var depth: float = floorf(e.pos.y) + 0.89 - e.pos.y
		e.vel.y += clampf(depth, -0.1, 0.1) * 0.25 + 0.01
		e.vel *= Vector3(0.9, 0.8, 0.9)
		_fish_tick(em, e, d)
	else:
		e.vel.y -= 0.03
		e.vel *= 0.92
	var r := Collision.move(Vector3(e.pos.x - 0.125, e.pos.y, e.pos.z - 0.125), Vector3(e.pos.x + 0.125, e.pos.y + 0.25, e.pos.z + 0.125), e.vel, gs, blocks, 0.0, e.on_ground)
	e.pos += r["motion"]
	e.on_ground = r["on_ground"]
	if r["hit_x"] or r["hit_z"]:
		e.vel.x = 0.0
		e.vel.z = 0.0
	if e.on_ground:
		e.vel = Vector3.ZERO
		d["state"] = "ground"


static func _fish_tick(em, e, d: Dictionary) -> void:
	if int(d["nibble"]) > 0:
		d["nibble"] = int(d["nibble"]) - 1
		if int(d["nibble"]) <= 0:
			d["lure"] = 0
			d["hooked"] = 0
		return
	if int(d["hooked"]) > 0:
		d["hooked"] = int(d["hooked"]) - 1
		if int(d["hooked"]) <= 0:
			d["nibble"] = em.rng.randi_range(20, 40)
			e.vel.y -= 0.4 * em.rng.randf_range(0.6, 1.0)
			Audio.play("entity.fishing_bobber.splash", e.pos, "Neutral", 0.25, 1.0 + (em.rng.randf() - em.rng.randf()) * 0.4)
		return
	if int(d["lure"]) <= 0:
		d["lure"] = maxi(20, em.rng.randi_range(100, 600) - int(d.get("lure_lvl", 0)) * 100)
		return
	# wiki: Fishing - rain on the bobber shortens the wait by ~20 %, no direct sky about doubles it, rain without sky
	# lengthens it by ~33.3 %: the wait drops 1 per tick, +1 with a 1/4 chance in rain, -1 with a 1/2 chance without sky
	# (average rates 1.25 / 0.5 / 0.75)
	var step := 1
	var above: Vector3 = e.pos + Vector3(0, 1, 0)
	if em.rng.randf() < 0.25 and em.world.weather_at(above) == "rain":
		step += 1
	if em.rng.randf() < 0.5 and not _sees_sky(em.world, above):
		step -= 1
	d["lure"] = int(d["lure"]) - step
	if int(d["lure"]) <= 0:
		d["hooked"] = em.rng.randi_range(20, 80)


## Open to the sky at p (the chunk heightmap, as WorldManager.weather_at uses it).
static func _sees_sky(world, p: Vector3) -> bool:
	var x := floori(p.x)
	var z := floori(p.z)
	var ch = world.cm.get_chunk(x >> 4, z >> 4)
	if ch == null or ch.heightmap.is_empty():
		return true
	return floori(p.y) >= int(ch.heightmap[(x & 15) + (z & 15) * 16])


## Java FishingHook.calculateOpenWater: the 5x4x5 area around the hook (y -1..2) must be layers of only water sources
## (below) and only air / lily pads (above), never mixed and never water above air.
static func open_water(world, c: Vector3i) -> bool:
	var b := Res.blocks
	var seen_air := false
	for dy in range(-1, 3):
		var all_water := true
		var all_air := true
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var st: int = world.state_at(c.x + dx, c.y + dy, c.z + dz)
				var nm := b.name_of(st) if st > 0 else "air"
				if not (nm == "water" and b.st_level[st] == 0):
					all_water = false
				if not (st == 0 or nm == "lily_pad"):
					all_air = false
		if all_water:
			if seen_air:
				return false
		elif all_air:
			seen_air = true
		else:
			return false
	return true


## Right-click with a rod while the hook is out. Returns the durability cost (Java retrieve).
static func reel(em, p: Player) -> int:
	var e = em.hook
	em.hook = null
	if e == null or e.dead:
		return 0
	var cost := 0
	if int(e.data.get("nibble", 0)) > 0:
		var ctx := {"rng": em.world.rng, "tool": p.inventory.held(), "luck": int(e.data.get("luck_lvl", 0)), "fishing": true, "open_water": open_water(em.world, Vector3i(e.pos.floor()))}
		var stacks: Array = Loot.roll("gameplay/fishing", ctx)
		if stacks.is_empty():
			stacks = [ItemStack.named("cod", 1)]
		for s in stacks:
			var it = em.spawn_item(e.pos + Vector3(0, 0.2, 0), s)
			if it != null:
				var dv: Vector3 = p.pos - e.pos
				it.vel = Vector3(dv.x * 0.1, dv.y * 0.1 + sqrt(dv.length()) * 0.08, dv.z * 0.1)
				it.pickup_delay = 0
		em.spawn_xp(p.pos + Vector3(0, 0.5, 0), em.rng.randi_range(1, 6))
		p.stats["fish_caught"] = int(p.stats.get("fish_caught", 0)) + 1
		cost = 1
	elif str(e.data.get("state", "")) == "ground":
		cost = 2
	em._remove(e)
	Audio.play("entity.fishing_bobber.retrieve", p.pos, "Neutral", 0.5)
	return cost


static func draw_line(em, e) -> void:
	var line: MeshInstance3D = e.node.get_node_or_null("line")
	if line == null:
		return
	var p: Player = e.owner
	var yr := deg_to_rad(p.yaw)
	var hand := p.eye_pos() + Vector3(-cos(yr) * 0.35, -0.35, -sin(yr) * 0.35) + p.look_dir() * 0.4
	var im: ImmediateMesh = line.mesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var a: Vector3 = em.world.vis(hand)
	var b: Vector3 = em.world.vis(e.pos + Vector3(0, 0.15, 0))
	for i in 9:
		var t := i / 8.0
		var q := a.lerp(b, t)
		q.y -= sin(t * PI) * 0.25 * a.distance_to(b) / 8.0
		im.surface_add_vertex(q)
	im.surface_end()


# ------------------------------------------------------------------ hanging + armor stands

static func is_placeable(nm: String) -> bool:
	return nm in ["item_frame", "glow_item_frame", "painting", "armor_stand"] or nm.ends_with("_cushion")


static func use_item(world, held: ItemStack, tgt: Dictionary) -> bool:
	var nm := held.name()
	var p: Vector3i = tgt["pos"]
	var n: Vector3i = tgt.get("normal", Vector3i(0, 1, 0))
	var em = world.entities
	var ok := false
	match nm:
		"item_frame", "glow_item_frame":
			ok = spawn_frame(em, nm, p + n, n, 0, ItemStack.new()) != null
		"painting":
			if n.y != 0:
				return false
			ok = place_painting(em, p + n, n)
		"armor_stand":
			var at := Vector3(p + n) + Vector3(0.5, 0.0, 0.5)
			ok = spawn_stand(em, at, snappedf(world.player.yaw + 180.0, 45.0), []) != null
		_:
			if nm.ends_with("_cushion"):
				# 26.x cushion: a seat entity on the floor of the cell in front of the clicked face
				var cell := p + n
				var cs: int = world.state_at(cell.x, cell.y, cell.z)
				if cs > 0 and (Res.blocks.st_flags[cs] & BlockRegistry.F_COLLIDE) != 0:
					return false
				for o in em.ents:
					if o.kind == "cushion" and not o.dead and Vector3i(o.pos.floor()) == cell:
						return false
				# grid-aligned: centred in the cell, facing one of the four horizontal directions
				ok = spawn_cushion(em, Vector3(cell) + Vector3(0.5, 0.0, 0.5), snappedf(world.player.yaw + 180.0, 90.0), nm) != null
				if ok:
					Audio.play("entity.cushion.place", Vector3(cell) + Vector3(0.5, 0.1, 0.5), "Blocks")
	if ok and not world.player.is_creative():
		world.player.inventory.consume_held()
	return ok


static func spawn_frame(em, kind: String, cell: Vector3i, n: Vector3i, rot: int, item: ItemStack):
	var e := EntityManager.Ent.new()
	e.kind = "frame"
	e.id = kind
	e.w = 0.75
	e.h = 0.75
	var c := Vector3(cell) + Vector3(0.5, 0.5, 0.5) - Vector3(n) * (0.5 - 1.0 / 32.0)
	e.pos = c - Vector3(0, 0.375, 0)
	e.prev = e.pos
	e.data = {"n": [n.x, n.y, n.z], "rot": rot}
	e.stack = item
	e.persistent = true
	e.node = Node3D.new()
	# Java ItemFrameRenderer: from the entity position (the block centre - facing * 0.46875) back to the block centre,
	# rotated X (horizontal: 0; up -90, down 90) then Y (horizontal: 180 - Direction.toYRot; up / down 180); there the
	# block/item_frame (or item_frame_map) model at translate(-0.5) - its 1 px frame and back plate at model z 15..16
	var fr := Node3D.new()
	fr.name = "frame"
	var xr := 0.0
	var yr := 180.0
	if n.y != 0:
		xr = -90.0 * n.y
	else:
		yr = 180.0 - float(YROT_OF.get(n, 0.0))
	fr.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(xr)) * Basis(Vector3.UP, deg_to_rad(yr)), Vector3(n) * 0.46875)
	e.node.add_child(fr)
	var face := MeshInstance3D.new()
	face.name = "face"
	face.position = Vector3(0, -0.5, 0)   # (model meshes are x / z centred, y from 0)
	fr.add_child(face)
	var it := Node3D.new()
	it.name = "item"
	fr.add_child(it)
	em.add_child(e.node)
	em.ents.append(e)
	_refresh_frame(em, e)
	return e


## Java Direction.toYRot of a horizontal facing (south 0, west 90, north 180, east 270).
const YROT_OF := {Vector3i(0, 0, 1): 0.0, Vector3i(-1, 0, 0): 90.0, Vector3i(0, 0, -1): 180.0, Vector3i(1, 0, 0): 270.0}


## Unshaded hanging-entity materials follow the block/sky light at their position (glow frames stay bright).
static func light_tint(em, e) -> void:
	if e.kind == "frame":
		_frame_light(em, e)
		return
	var face: MeshInstance3D = e.node.get_node_or_null("face")
	if face == null:
		return
	var na: Array = e.data.get("n", [0, 0, 1])
	var q: Vector3 = e.pos + Vector3(0, e.h / 2.0, 0) + Vector3(na[0], na[1], na[2]) * 0.3
	var l: int = em.world.cm.get_light(int(floor(q.x)), int(floor(q.y)), int(floor(q.z)))
	var sky := float(l >> 4) / 15.0 * clampf(em.world.sky_darken(), 0.2, 1.0)   # sky_darken = daylight factor
	var v := maxf(sky, float(l & 15) / 15.0)
	if e.id == "glow_item_frame":
		v = 1.0
	var b := 0.12 + 0.88 * v * v
	(face.material_override as StandardMaterial3D).albedo_color = Color(b, b, b)
	var spr: Sprite3D = e.node.get_node_or_null("item")
	if spr != null:
		spr.modulate = Color(b, b, b)


static func _orient(node: Node3D, n: Vector3i) -> void:
	if n.y > 0:
		node.rotation = Vector3(-PI / 2, 0, 0)
	elif n.y < 0:
		node.rotation = Vector3(PI / 2, 0, 0)
	else:
		node.rotation = Vector3(0, atan2(float(n.x), float(n.z)), 0)


## The block an item frame occupies (Java HangingEntity.getPos).
static func frame_cell(e) -> Vector3i:
	var n_a: Array = e.data.get("n", [0, 0, 1])
	var n := Vector3i(int(n_a[0]), int(n_a[1]), int(n_a[2]))
	return Vector3i((e.pos + Vector3(0, 0.375, 0) + Vector3(n) * (0.5 - 1.0 / 32.0)).floor())


static func _frame_n(e) -> Vector3i:
	var n_a: Array = e.data.get("n", [0, 0, 1])
	return Vector3i(int(n_a[0]), int(n_a[1]), int(n_a[2]))


## Java HangingEntity bounding box: 1/16 thick along its facing, its width x height across it (frames 12 x 12 px).
static func hanging_box(e) -> Array:
	var n := _frame_n(e)
	var c: Vector3 = e.pos + (Vector3(0, e.h * 0.5, 0) if e.kind == "painting" else Vector3(0, 0.375, 0))
	var hw: float = e.w * 0.5
	var hh: float = e.h * 0.5
	var t := 1.0 / 32.0
	var ext := Vector3(hw, t, hh) if n.y != 0 else (Vector3(t, hh, hw) if n.x != 0 else Vector3(hw, hh, t))
	return [c - ext, c + ext]


## A projectile hit a painting / item frame (Java HangingEntity.hurt / ItemFrame.hurt): a frame holding an item drops
## the item first, otherwise the entity breaks and drops itself - nothing drops when the shooter is a Creative player.
static func projectile_break(em, e, shooter) -> void:
	var creative: bool = shooter is Player and (shooter as Player).is_creative()
	if e.kind == "frame":
		if not e.stack.is_empty():
			if Maps.map_id(e.stack) >= 0:
				Maps.frame_removed(em.world, frame_cell(e), e.stack)
			var it: ItemStack = e.stack
			e.stack = ItemStack.new()
			_refresh_frame(em, e)
			Audio.play("entity.item_frame.remove_item", e.pos, "Blocks")
			if not creative:
				em.spawn_item(e.pos + Vector3(0, 0.4, 0), it)
			return
		Audio.play("entity.item_frame.break", e.pos, "Blocks")
		if not creative:
			em.spawn_item(e.pos + Vector3(0, 0.4, 0), ItemStack.named(e.id, 1))
	else:
		Audio.play("entity.painting.break", e.pos, "Blocks")
		if not creative:
			em.spawn_item(e.pos + Vector3(0, 0.4, 0), ItemStack.named("painting", 1))
	em._remove(e)


## Java ItemFrameRenderer light: the frame model takes the light at the frame (a glow frame's block light at least 5),
## the framed item the same - a glow frame's at full brightness (getLightCoords: 0xF000F0 for items, 0xF000D2 for
## maps). Map sprites are unshaded: modulated like paintings. Re-applied only when the light there changes.
static func _frame_light(em, e) -> void:
	if em.get("world") == null or em.world.get("cm") == null:
		return
	var na: Array = e.data.get("n", [0, 0, 1])
	var q: Vector3 = e.pos + Vector3(0, 0.375, 0) + Vector3(na[0], na[1], na[2]) * 0.3
	var l: int = em.world.cm.get_light(int(floor(q.x)), int(floor(q.y)), int(floor(q.z)))
	var dk := clampf(em.world.sky_darken(), 0.2, 1.0)
	var key := l * 1000 + int(dk * 100.0)
	if int(e.node.get_meta("lkey", -1)) == key:
		return
	e.node.set_meta("lkey", key)
	var glow: bool = e.id == "glow_item_frame"
	var sky := float(l >> 4) / 15.0
	var blk := float(l & 15) / 15.0
	var fr: Node = e.node.get_node_or_null("frame")
	if fr == null:
		return
	var face: MeshInstance3D = fr.get_node_or_null("face")
	if face != null:
		face.set_instance_shader_parameter("light", Vector2(sky, maxf(blk, 5.0 / 15.0) if glow else blk))
	var it: Node = fr.get_node_or_null("item")
	if it == null:
		return
	BERender.set_light(it, Vector2(1.0, 1.0) if glow else Vector2(sky, blk))
	var v := 1.0 if glow else maxf(sky * dk, blk)
	var b := 0.12 + 0.88 * v * v
	for s in it.find_children("*", "Sprite3D", true, false):
		(s as Sprite3D).modulate = Color(b, b, b)


static func _refresh_frame(em, e) -> void:
	var fr: Node3D = e.node.get_node("frame")
	var it: Node3D = fr.get_node("item")
	for ch in it.get_children():
		it.remove_child(ch)
		ch.queue_free()
	e.node.remove_meta("lkey")
	var mid := Maps.map_id(e.stack)
	var glow: bool = e.id == "glow_item_frame"
	var face: MeshInstance3D = fr.get_node("face")
	face.mesh = EntityRenderer.model_mesh("block/%s%s" % ["glow_item_frame" if glow else "item_frame", "_map" if mid >= 0 else ""])
	var rot := int(e.data.get("rot", 0))
	if mid >= 0:
		# Java: translate(0, 0, 0.4375), Z by rotation % 4 * 90 deg, Z 180, scale 1/128, translate(-64, -64, -1): the
		# 128 x 128 map over the whole block face, image up = frame up, facing out of the wall (frame space +z is the
		# wall). The banner markers are drawn on framed maps (MapDecorationType.showOnItemFrame), frame / player not.
		var spr := Sprite3D.new()
		spr.texture = Maps.texture(em.world, mid)
		spr.pixel_size = 1.0 / 128.0
		spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		spr.double_sided = false
		spr.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(float(rot % 4) * 90.0)) * Basis(Vector3.UP, PI), Vector3(0, 0, 0.4375 - 1.0 / 128.0))
		it.add_child(spr)
		e.data["map_rev"] = Maps.rev(em.world, mid)
		var k := 0
		for d in Maps.decorations(em.world, mid):
			if not bool(d[5]):
				continue
			k += 1
			var ds := Sprite3D.new()
			ds.texture = UiKit.sprite(str(d[0]))
			ds.pixel_size = 1.0 / 128.0
			ds.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			ds.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			ds.double_sided = false
			ds.position = Vector3(float(d[1]) / 2.0 / 128.0, -float(d[2]) / 2.0 / 128.0, 0.001 * k)
			ds.rotation.z = -float(d[3]) * TAU / 16.0
			spr.add_child(ds)
	elif not e.stack.is_empty():
		# Java: translate(0, 0, 0.4375), Z by rotation x 45 deg, scale 0.5, the item's FIXED display transform (blocks
		# 3D at a quarter, flat items extruded at half a block)
		var nd := HeldItems.item_node(e.stack, "fixed", false)
		if nd != null:
			var hold := Node3D.new()
			hold.transform = Transform3D(Basis(Vector3.BACK, deg_to_rad(float(rot) * 45.0)).scaled_local(Vector3.ONE * 0.5), Vector3(0, 0, 0.4375))
			hold.add_child(nd)
			it.add_child(hold)
	_frame_light(em, e)


static func interact(em, e, p: Player, held: ItemStack) -> bool:
	match e.kind:
		"frame":
			if e.stack.is_empty():
				if held.is_empty():
					return false
				e.stack = held.copy()
				e.stack.count = 1
				if not p.is_creative():
					p.inventory.consume_held()
				if Maps.map_id(e.stack) >= 0:
					Maps.frame_added(em.world, frame_cell(e), _frame_n(e), e.stack)
				Audio.play("entity.item_frame.add_item", e.pos, "Blocks")
			else:
				e.data["rot"] = (int(e.data.get("rot", 0)) + 1) % 8
				Audio.play("entity.item_frame.rotate_item", e.pos, "Blocks")
			_refresh_frame(em, e)
			em.world.inv_changed()
			return true
		"cushion":
			if p.vehicle == null and not p.sneaking:
				Taming.mount(em, e, p)
				return true
			return false
		"armor_stand":
			var nm := "" if held.is_empty() else held.name()
			var armor: Array = e.data.get("armor", [{}, {}, {}, {}])
			for suffix in ARMOR_SLOT:
				if nm.ends_with("_" + suffix) or (suffix == "helmet" and (nm.ends_with("_head") or nm.ends_with("_skull") or nm == "carved_pumpkin" or nm == "turtle_helmet")):
					var slot: int = ARMOR_SLOT[suffix]
					var old := ItemStack.from_dict(armor[slot]) if armor[slot] is Dictionary else ItemStack.new()
					var one := held.copy()
					one.count = 1
					armor[slot] = one.to_dict()
					p.inventory.consume_held()
					if not old.is_empty():
						p.inventory.add(old)
					e.data["armor"] = armor
					Audio.play("item.armor.equip_generic", e.pos, "Players")
					em.world.inv_changed()
					return true
			if held.is_empty():
				for slot2 in [3, 2, 1, 0]:
					if armor[slot2] is Dictionary and not (armor[slot2] as Dictionary).is_empty():
						p.inventory.add(ItemStack.from_dict(armor[slot2]))
						armor[slot2] = {}
						e.data["armor"] = armor
						em.world.inv_changed()
						return true
			return false
	return false


## Attack: frames drop their item first, then themselves; paintings/stands break (Java hurt with player source).
static func attack(em, e, p: Player) -> void:
	var drops: Array = []
	match e.kind:
		"frame":
			if not e.stack.is_empty():
				drops.append(e.stack)
				if Maps.map_id(e.stack) >= 0:
					Maps.frame_removed(em.world, frame_cell(e), e.stack)
				e.stack = ItemStack.new()
				_refresh_frame(em, e)
				Audio.play("entity.item_frame.remove_item", e.pos, "Blocks")
				if not p.is_creative():
					em.spawn_item(e.pos + Vector3(0, 0.4, 0), drops[0])
				return
			drops.append(ItemStack.named(e.id, 1))
			Audio.play("entity.item_frame.break", e.pos, "Blocks")
		"painting":
			drops.append(ItemStack.named("painting", 1))
			Audio.play("entity.painting.break", e.pos, "Blocks")
		"cushion":
			drops.append(ItemStack.named(e.id, 1))
			Audio.play("entity.cushion.break", e.pos, "Blocks")
			if p.vehicle == e:
				Taming.dismount(em, p)
		"armor_stand":
			# wiki Armor Stand: broken by quickly attacking it twice (a first hit only wobbles it; the window, 5 ticks,
			# and the one-hit Creative break are Java's ArmorStand.hurt); hit sound entity.armor_stand.hit
			var now: int = em.world.game_time
			if not p.is_creative() and now - int(e.rt.get("last_hit", -100)) > 5:
				e.rt["last_hit"] = now
				Audio.play("entity.armor_stand.hit", e.pos, "Blocks")
				return
			drops.append(ItemStack.named("armor_stand", 1))
			for a in e.data.get("armor", []):
				if a is Dictionary and not a.is_empty():
					drops.append(ItemStack.from_dict(a))
			Audio.play("entity.armor_stand.break", e.pos, "Blocks")
	em._remove(e)
	if not p.is_creative() or e.kind == "armor_stand":
		for s in drops:
			if not p.is_creative() or (s as ItemStack).name() != "armor_stand":
				em.spawn_item(e.pos + Vector3(0, 0.4, 0), s)


static func _load_paintings() -> void:
	if not _paintings.is_empty():
		return
	for f in Res.list_files("data/minecraft/painting_variant/", ".json"):
		var j = Res.read_json(f)
		if j is Dictionary:
			var placeable := Tags.resolve("painting_variant", "#minecraft:placeable")
			var id := f.get_file().get_basename()
			if placeable.is_empty() or placeable.has(id):
				_paintings.append([str(j.get("asset_id", id)).trim_prefix("minecraft:"), int(j.get("width", 1)), int(j.get("height", 1))])
	if _paintings.is_empty():
		for v in [["kebab", 1, 1], ["aztec", 1, 1], ["pool", 2, 1], ["courbet", 2, 1], ["wanderer", 1, 2], ["fighters", 4, 2], ["skeleton", 4, 3], ["pointer", 4, 4]]:
			_paintings.append(v)


static func _fits(world, cell: Vector3i, n: Vector3i, w: int, h: int) -> bool:
	var right := Vector3i(n.z, 0, -n.x)   # along the wall
	var x0 := -((w - 1) / 2)
	var y0 := -((h - 1) / 2)
	for i in w:
		for j in h:
			var q: Vector3i = cell + right * (x0 + i) + Vector3i(0, y0 + j, 0)
			if world.state_at(q.x, q.y, q.z) != 0:
				return false
			var b: Vector3i = q - n
			var bs: int = world.state_at(b.x, b.y, b.z)
			if bs <= 0 or (Res.blocks.st_flags[bs] & BlockRegistry.F_COLLIDE) == 0:
				return false
	for o in world.entities.ents:
		if o.kind == "painting" and o.pos.distance_to(Vector3(cell)) < 0.5:
			return false
	return true


static func place_painting(em, cell: Vector3i, n: Vector3i) -> bool:
	_load_paintings()
	var best: Array = []
	var area := 0
	for v in _paintings:
		if not _fits(em.world, cell, n, int(v[1]), int(v[2])):
			continue
		var a: int = int(v[1]) * int(v[2])
		if a > area:
			area = a
			best = [v]
		elif a == area:
			best.append(v)
	if best.is_empty():
		return false
	var pick: Array = best[em.rng.randi_range(0, best.size() - 1)]
	spawn_painting(em, cell, n, str(pick[0]), int(pick[1]), int(pick[2]))
	Audio.play("entity.painting.place", Vector3(cell), "Blocks")
	return true


static func spawn_painting(em, cell: Vector3i, n: Vector3i, asset: String, w: int, h: int):
	var e := EntityManager.Ent.new()
	e.kind = "painting"
	e.id = asset
	var right := Vector3i(n.z, 0, -n.x)
	var x0 := -((w - 1) / 2)
	var y0 := -((h - 1) / 2)
	var center := Vector3(cell) + Vector3(0.5, 0.5, 0.5) + Vector3(right) * (x0 + (w - 1) / 2.0) + Vector3(0, y0 + (h - 1) / 2.0, 0) - Vector3(n) * (0.5 - 1.0 / 32.0)
	e.pos = center - Vector3(0, h / 2.0, 0)
	e.prev = e.pos
	e.w = float(maxi(w, 1))
	e.h = float(h)
	e.data = {"n": [n.x, n.y, n.z], "cell": [cell.x, cell.y, cell.z], "w": w, "hh": h}
	e.persistent = true
	e.node = Node3D.new()
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(w, h)
	mi.mesh = qm
	mi.position = Vector3(0, h / 2.0, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = UiKit.sprite("painting/" + asset)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.name = "face"
	e.node.add_child(mi)
	_orient(e.node, n)
	em.add_child(e.node)
	em.ents.append(e)
	return e


static func spawn_stand(em, at: Vector3, yaw: float, armor: Array):
	var e := EntityManager.Ent.new()
	e.kind = "armor_stand"
	e.id = "armor_stand"
	e.pos = at
	e.prev = at
	e.yaw = yaw
	e.body_yaw = yaw
	e.w = 0.5
	e.h = 1.975
	e.hp = 20.0   # wiki: Armor Stand - 20 HP (Java)
	e.persistent = true
	e.data = {"armor": armor if armor.size() == 4 else [{}, {}, {}, {}]}
	e.node = EntityRenderer.build_rig({"tex": "entity/armorstand/wood", "tex_size": [64, 64], "parts": STAND_PARTS})
	em.add_child(e.node)
	em.ents.append(e)
	Audio.play("entity.armor_stand.place", at, "Blocks")
	return e


## 26.x cushion (CushionModel: one 16 x 4 x 16 box, texture entity/cushion/<colour>_cushion.png, box UV at 0, 0): a
## placed seat - right-click sits (riding pose), sneak gets up, a hit breaks it and drops the item. Falls with gravity.
const CUSHION_PARTS := [["base", [0, 24, 0], [-8, -4, -8], [16, 4, 16], [0, 0], 0]]
static func spawn_cushion(em, at: Vector3, yaw: float, item: String):
	var e := EntityManager.Ent.new()
	e.kind = "cushion"
	e.id = item
	e.pos = at
	e.prev = at
	e.yaw = yaw
	e.body_yaw = yaw
	e.w = 1.0
	e.h = 0.25
	e.persistent = true
	e.node = EntityRenderer.build_rig({"tex": "entity/cushion/" + item, "tex_size": [64, 64], "parts": CUSHION_PARTS})
	em.add_child(e.node)
	em.ents.append(e)
	return e


static func tick_cushion(em, e, gs: Callable, blocks: BlockRegistry) -> void:
	em._physics(e, gs, blocks, 0.08, 0.91, 0.0)
	var p: Player = em.world.player
	if p.vehicle == e:
		Vehicles.seat(e, p)


## Hanging entities pop off when the supporting block is gone (checked every 20 ticks).
static func tick_hanging(em, e) -> void:
	if e.age % 20 != 0:
		return
	if e.kind == "frame" and Maps.map_id(e.stack) >= 0:
		# framed map: keep its frame marker (Java ServerEntity ticks tickCarriedBy for framed maps) and redraw the
		# banner markers when the map's decorations changed
		Maps.frame_added(em.world, frame_cell(e), _frame_n(e), e.stack)
		if int(e.data.get("map_rev", -1)) != Maps.rev(em.world, Maps.map_id(e.stack)):
			_refresh_frame(em, e)
	var n := Vector3i(e.data["n"][0], e.data["n"][1], e.data["n"][2])
	var c: Vector3i = Vector3i((e.pos + Vector3(0, e.h / 2.0, 0) + Vector3(n) * 0.4).floor()) - n
	var bs: int = em.world.state_at(c.x, c.y, c.z)
	if bs <= 0 or (Res.blocks.st_flags[bs] & BlockRegistry.F_COLLIDE) == 0:
		em.spawn_item(e.pos + Vector3(0, 0.4, 0), ItemStack.named(e.id if e.kind == "frame" else "painting", 1))
		if e.kind == "frame" and not e.stack.is_empty():
			if Maps.map_id(e.stack) >= 0:
				Maps.frame_removed(em.world, frame_cell(e), e.stack)
			em.spawn_item(e.pos + Vector3(0, 0.4, 0), e.stack)
		em._remove(e)


static func ser(e) -> Dictionary:
	var d := {"k": e.kind, "id": e.id, "p": [e.pos.x, e.pos.y, e.pos.z], "y": e.yaw, "d": e.data}
	if e.kind == "frame":
		d["s"] = e.stack.to_dict()
	return d


static func deser(em, d: Dictionary) -> void:
	var p: Array = d.get("p", [0, 0, 0])
	var dd: Dictionary = d.get("d", {})
	var n_a: Array = dd.get("n", [0, 0, 1])
	var n := Vector3i(int(n_a[0]), int(n_a[1]), int(n_a[2]))
	match str(d.get("k", "")):
		"frame":
			var c := Vector3(p[0], p[1], p[2]) + Vector3(0, 0.375, 0) + Vector3(n) * (0.5 - 1.0 / 32.0)
			spawn_frame(em, str(d.get("id", "item_frame")), Vector3i(c.floor()), n, int(dd.get("rot", 0)), ItemStack.from_dict(d.get("s", {})))
		"painting":
			var cl: Array = dd.get("cell", [p[0], p[1], p[2]])
			spawn_painting(em, Vector3i(int(cl[0]), int(cl[1]), int(cl[2])), n, str(d.get("id", "kebab")), int(dd.get("w", 1)), int(dd.get("hh", 1)))
		"armor_stand":
			spawn_stand(em, Vector3(p[0], p[1], p[2]), float(d.get("y", 0.0)), dd.get("armor", []))
		"cushion":
			spawn_cushion(em, Vector3(p[0], p[1], p[2]), float(d.get("y", 0.0)), str(d.get("id", "white_cushion")))


# ------------------------------------------------------------------ area effect clouds

## Java AreaEffectCloud (wiki Area Effect Cloud / Lingering Potion / Dragon Fireball):
## - lingering potion: radius 3 shrinking to 0 over 30 s (600 ticks, -3 / 600 per tick), nobody affected during the
##   first second (wait 20), each affected entity shrinks it by 1/2 block and cuts 5 s (100 ticks) off its life; timed
##   effects at 1/4 of the potion's duration, instant ones at 1/2 potency; an entity can be affected again after the
##   reapplication delay (20 ticks; the delay and the 5-tick check interval are Java's defaults, not on the wiki);
##   0.5 tall; gone below radius 0.5; drawn as the potion's coloured effect particles (no model)
## - dragon fireball: Instant Damage II as a lingering Harming II, grows instead of shrinking and does not shrink on
##   use (wiki; the growth 3 -> 7 over its 600 ticks is Java's DragonFireball, not on the wiki); purple
## - dragon perch breath: a 5-6 block disc for 3 s, harmful core of 3-4 blocks at 3 HP per second (wiki Dragon
##   Fireball: Perching breath attack)
static func spawn_cloud(em, at: Vector3, potion: String, kind: String = "potion"):
	if Net.is_client() and not Net.applying:
		return null
	var e := EntityManager.Ent.new()
	e.kind = "cloud"
	e.id = kind
	e.pos = at
	e.prev = at
	e.w = 6.0
	e.h = 0.5
	var d := {"r": 3.0, "rpt": -3.0 / 600.0, "dur": 600, "wait": 20, "ron": -0.5, "don": -100, "delay": 20, "pot": potion}
	match kind:
		"dragon":
			d["pot"] = "strong_harming"
			d["rpt"] = (7.0 - 3.0) / 600.0
			d["ron"] = 0.0
			d["don"] = 0
			d["wait"] = 0
		"breath":
			d["pot"] = ""
			d["rpt"] = 0.0
			d["dur"] = 60
			d["wait"] = 0
			d["ron"] = 0.0
			d["don"] = 0
	var col := Color(0.6, 0.15, 0.85) if kind != "potion" else Potions.color_of(potion)
	e.rt["col"] = col
	e.rt["vic"] = {}
	e.data = d
	em.ents.append(e)
	return e


static func tick_cloud(em, e, p: Player) -> void:
	var d: Dictionary = e.data
	var r := float(d["r"])
	var waiting: bool = e.age < int(d["wait"])
	_cloud_particles(em, e, 0.2 if waiting else r, waiting)
	if e.age >= int(d["wait"]) + int(d["dur"]):
		em._remove(e)
		return
	if waiting:
		return
	var rpt := float(d["rpt"])
	if rpt != 0.0:
		r += rpt
		if r < 0.5:
			em._remove(e)
			return
		d["r"] = r
	if e.age % 5 != 0:
		return
	var vic: Dictionary = e.rt["vic"]
	for k in vic.keys():
		if int(vic[k]) <= e.age:
			vic.erase(k)
	var pot := str(d["pot"])
	var breath: bool = e.id == "breath"
	var reach := 1.75 if breath else r   # (breath: the 3-4 block harmful core of the wiki)
	var targets: Array = []
	if p != null and not p.dead and not p.is_spectator() and _in_cloud(e, reach, p.aabb_min(), p.aabb_max()):
		targets.append(p)
	for o in em.ents:
		if o.kind == "mob" and not o.dead and o.death_time == 0 and o.id != "ender_dragon" and o.id != "armor_stand":
			if _in_cloud(e, reach, Vector3(o.pos.x - o.w / 2.0, o.pos.y, o.pos.z - o.w / 2.0), Vector3(o.pos.x + o.w / 2.0, o.pos.y + o.h, o.pos.z + o.w / 2.0)):
				targets.append(o)
	if pot == "" and not breath:
		return   # (water / awkward ...: particles only)
	var scale := 0.5 if Potions.all_instant(pot) else 0.25
	for t in targets:
		if vic.has(t):
			continue
		vic[t] = e.age + (20 if breath else int(d["delay"]))
		if breath:
			if t is Player:
				(t as Player).hurt(3.0, "dragon_breath", true)
			else:
				em._damage(t, 3.0, null, "magic")
		elif t is Player:
			Potions.apply(t, pot, scale)
		else:
			MobBehaviors.apply_potion(em, t, pot, scale)
		var ron := float(d["ron"])
		if ron != 0.0:
			r += ron
			d["r"] = r
			if r < 0.5:
				em._remove(e)
				return
		var don := int(d["don"])
		if don != 0:
			d["dur"] = int(d["dur"]) + don
			if int(d["dur"]) <= 0:
				em._remove(e)
				return


## Java AreaEffectCloud entity check: the entity's box touches the cloud box (radius, 0.5 tall) and its position is
## within the radius horizontally.
static func _in_cloud(e, r: float, mn: Vector3, mx: Vector3) -> bool:
	if mx.y < e.pos.y or mn.y > e.pos.y + 0.5:
		return false
	var cx: float = (mn.x + mx.x) * 0.5 - e.pos.x
	var cz: float = (mn.z + mx.z) * 0.5 - e.pos.z
	return cx * cx + cz * cz <= r * r


## Java AreaEffectCloud client tick: while waiting 2 particles in a 0.2 radius every other tick, then ceil(pi r^2)
## per tick spread uniformly over the disc (capped at 48 per tick here), the potion colour; purple for the dragon.
static func _cloud_particles(em, e, r: float, waiting: bool) -> void:
	var rng: RandomNumberGenerator = em.rng
	if waiting and rng.randi_range(0, 1) == 0:
		return
	var n := 2 if waiting else mini(48, ceili(PI * r * r))
	var col: Color = e.rt.get("col", Color.WHITE)
	var dragon: bool = e.id != "potion"
	for i in n:
		var a := rng.randf() * TAU
		var dist := sqrt(rng.randf()) * r
		var at := Vector3(e.pos.x + cos(a) * dist, e.pos.y, e.pos.z + sin(a) * dist)
		var v := Vector3((0.5 - rng.randf()) * 0.15, 0.01, (0.5 - rng.randf()) * 0.15) if dragon else Vector3.ZERO
		Particles.emit("effect", at, v, col)
