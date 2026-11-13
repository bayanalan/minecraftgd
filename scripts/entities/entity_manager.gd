## EntityManager — all non-player entities: item drops (pickup delay, merge, despawn 6000t), XP orbs,
## falling blocks, thrown projectiles/arrows, and living mobs with goal-based AI (wander, panic, tempt,
## breed, chase/melee, ranged skeletons, creeper fuse+explosion, spider climb, daylight burning),
## natural spawning from the biome's 26.3 `natural_mob_spawns` attribute with caps, despawning,
## persistence per chunk, and box-rig rendering. Runs at 20 TPS on the main thread with a spatial cap.
## Contract: tick(); spawn_item/spawn_mob/...; raycast(origin, dir, max) -> [ent, dist] or null.
class_name EntityManager
extends Node3D

const MAX_ITEMS := 600
const HOSTILE_CAP := 70
const PASSIVE_CAP := 10


class Ent:
	var kind := ""
	var id := ""
	var pos := Vector3.ZERO
	var prev := Vector3.ZERO
	var tick_us := 0   # when this entity last ticked (render interpolation origin; the entity phase may span frames)
	var vel := Vector3.ZERO
	var w := 0.25
	var h := 0.25
	var on_ground := false
	var hcollide := false
	var ccache: Array = [PackedInt32Array(), PackedFloat32Array()]   # Collision.gather cache (region + block epoch)
	var age := 0
	var dead := false
	var node: Node3D
	var stack: ItemStack
	var pickup_delay := 10
	var xp := 0
	var state := 0
	var yaw := 0.0
	var body_yaw := 0.0
	var head_pitch := 0.0
	var hp := 10.0
	var def: Dictionary = {}
	var target_pos := Vector3.ZERO
	var has_target := false
	var target_player := false
	var ai_timer := 0
	var panic := 0
	var hurt_time := 0
	var invuln := 0
	var attack_cd := 0
	var fuse := -1
	var love := 0
	var breed_cd := 0
	var baby_age := 0
	var fire := 0
	var limb := 0.0
	var limb_amt := 0.0
	# previous-tick values: the renderer interpolates rotations / walk animation between ticks (Java yBodyRotO,
	# yHeadRotO, xRotO, WalkAnimationState.speedOld)
	var body_yaw_o := 0.0
	var head_yaw := 0.0
	var head_yaw_o := 0.0
	var head_pitch_o := 0.0
	var limb_amt_o := 0.0
	# Java LookControl / BodyRotationControl / look goals (MobControl)
	var look_cd := 0
	var look_at := Vector3.ZERO
	var look_ymax := 10.0
	var look_xmax := 40.0
	var look_goal := 0
	var look_t := 0
	var look_dir := Vector2.ZERO
	var head_stable := 0
	var head_last := 0.0
	var jump_delay := 0
	# Java PathNavigation (MobPath): node path, next node index, pending search, goal block, repath cooldown
	var path_i := 0
	var nav_job: MobPath = null
	var nav_goal := Vector3i(0, -9999, 0)
	var nav_cd := 0
	var nav_stuck_t := 0
	var nav_stuck_pos := Vector3.ZERO
	var parent_pos := Vector3.INF   # Java FollowParentGoal target (babies)
	var death_time := 0             # Java LivingEntity.deathTime: > 0 while the death animation plays (20 ticks)
	var rt: Dictionary = {}         # runtime-only state (not saved): dragon phase paths / targets ...
	var owner = null
	var persistent := false
	var sheared := false
	var fall := 0.0
	var path: Array = []
	var path_timer := 0
	var size := 1          # slime / magma cube size (1, 2, 4)
	var charge := 0        # ranged attack charge (ghast / blaze)
	var burst := 0         # blaze fireballs left in the current burst
	var angry := false     # neutral mobs provoked
	var tp_cd := 0         # teleport cooldown
	var noai := false      # Java NoAI tag: physics only
	var data: Dictionary = {}  # per-entity extra state (villager profession/offers, ...)
	var uid := 0           # network id (LAN snapshots)
	var remote := false    # client-side puppet driven by host snapshots


var world
var ents: Array = []
var rng := RandomNumberGenerator.new()
var spawn_timer := 0
var spawn_cycle := 0
var sleeping := false
var sleep_timer := 0
var seat: Ent = null
var _proxies: Array = []   # LAN host: remote player stand-ins (Net.Proxy)
var pet_target = null      # last mob the local player attacked or was hurt by (tamed wolves join in)
var hook = null            # the local player's fishing hook (MiscEntities)


func _ready() -> void:
	rng.randomize()
	if Res.blocks != null:
		var tc := Time.get_ticks_usec()
		MobPath.class_table(Res.blocks)
		print_verbose("[mobpath] class table %d states in %d us" % [Res.blocks.total_states, Time.get_ticks_usec() - tc])   # path classes of every state, while the world loads (first path search stays cheap)


func count_kind(k: String) -> int:
	var n := 0
	for e in ents:
		if e.kind == k:
			n += 1
	return n


# ------------------------------------------------------------------ spawning

func spawn_item(p: Vector3, s: ItemStack, scatter: bool = false) -> Ent:
	if s == null or s.is_empty():
		return null
	if Net.is_client() and not Net.applying:
		Net.forward("item", [p.x, p.y, p.z, s.to_dict()])
		return null
	var e := Ent.new()
	e.kind = "item"
	e.pos = p
	e.prev = p
	e.stack = s
	e.vel = Vector3(rng.randf_range(-0.1, 0.1), 0.2, rng.randf_range(-0.1, 0.1)) if scatter or true else Vector3.ZERO
	e.node = _item_node(s)
	add_child(e.node)
	ents.append(e)
	if count_kind("item") > MAX_ITEMS:
		for o in ents:
			if o.kind == "item":
				_remove(o)
				break
	return e


func _item_node(s: ItemStack) -> Node3D:
	var root := Node3D.new()
	var pb: int = Res.items.place_block[s.item]
	var spec := BERender.item_node(s.item, "ground", {"patterns": Banners.layers(s), "base_color": s.components.get("minecraft:base_color")})
	if spec != null:
		spec.position.y += 0.125
		root.add_child(spec)
		root.set_meta("special", true)
		return root
	# Java ItemEntityRenderer: the ground-context model at its display.ground transform (flat items extruded at half
	# a block: translation (0, 2, 0) / 16, scale 0.5; blocks a quarter: (0, 3, 0) / 16, 0.25), 1..5 copies by stack
	# size (3D models scattered +-0.15, flat ones +-0.075 and stacked 0.09375 * scale apart along z).
	var mesh: Mesh = null
	var mat: Material = null
	var off := Vector3.ZERO
	var flat := false
	if pb > 0 and (Res.blocks.st_flags[pb] & (BlockRegistry.F_CUBE | BlockRegistry.F_MODEL)) and not Res.items.model_ref[s.item].begins_with("item/"):
		mesh = EntityRenderer.block_item_mesh(pb)
		off = Vector3(0, -0.5, 0)
	if mesh == null:
		var ref := ItemRegistry.ctx_model(s.name(), "ground") if Res.mode == "vanilla" else ""
		if ref == "":
			ref = Res.items.model_ref[s.item]
		var em: Array = ItemIcons.extruded_model(ref)
		if em.size() == 2:
			mesh = em[0]
			var sm := ShaderMaterial.new()
			sm.shader = load("res://shaders/entity.gdshader")
			sm.set_shader_parameter("tex", em[1])
			sm.set_shader_parameter("has_tex", true)
			mat = sm
			flat = true
	if mesh == null:
		return root
	var d := ItemIcons.item_display(s.item, "ground")
	var dt: Array = d.get("translation", [0, 2, 0])
	var dr: Array = d.get("rotation", [0, 0, 0])
	var dsc: Array = d.get("scale", [0.5, 0.5, 0.5])
	var basis := Basis(Vector3.RIGHT, deg_to_rad(float(dr[0]))) * Basis(Vector3.UP, deg_to_rad(float(dr[1]))) * Basis(Vector3.BACK, deg_to_rad(float(dr[2])))
	basis = basis * Basis.from_scale(Vector3(float(dsc[0]), float(dsc[1]), float(dsc[2])))
	var disp := Transform3D(basis, Vector3(float(dt[0]), float(dt[1]), float(dt[2])) / 16.0)
	var n := 5 if s.count > 48 else (4 if s.count > 32 else (3 if s.count > 16 else (2 if s.count > 1 else 1)))
	var r := RandomNumberGenerator.new()
	r.seed = s.item * 31 + s.count
	var z := 0.0
	for k in n:
		var o := Vector3(0, 0, z)
		if k > 0:
			if flat:
				o += Vector3(r.randf_range(-1, 1) * 0.075, r.randf_range(-1, 1) * 0.075, 0)
			else:
				o += Vector3(r.randf_range(-1, 1) * 0.15, r.randf_range(-1, 1) * 0.15, r.randf_range(-1, 1) * 0.15)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		if mat != null:
			mi.material_override = mat
		mi.transform = Transform3D(Basis(), o) * disp * Transform3D(Basis(), off)
		root.add_child(mi)
		if flat:
			z += 0.09375 * float(dsc[2])
	root.set_meta("gsy", float(dsc[1]))
	root.set_meta("bob", randf() * TAU)
	return root


func spawn_xp(p: Vector3, amount: int) -> void:
	if Net.is_client() and not Net.applying:
		Net.forward("xp", [p.x, p.y, p.z, amount])
		return
	while amount > 0:
		var v := mini(amount, 7)
		amount -= v
		var e := Ent.new()
		e.kind = "xp"
		e.pos = p
		e.prev = p
		e.xp = v
		e.vel = Vector3(rng.randf_range(-0.1, 0.1), 0.2, rng.randf_range(-0.1, 0.1))
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.08
		sm.height = 0.16
		mi.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(0.6, 1.0, 0.2)
		mi.material_override = mat
		e.node = Node3D.new()
		e.node.add_child(mi)
		add_child(e.node)
		ents.append(e)


func spawn_falling_block(p: Vector3i, st: int) -> void:
	if Net.is_client() and not Net.applying:
		return
	var e := Ent.new()
	e.kind = "falling"
	e.pos = Vector3(p) + Vector3(0.5, 0, 0.5)
	e.prev = e.pos
	e.state = st
	e.w = 0.98
	e.h = 0.98
	e.node = Node3D.new()
	var mesh := EntityRenderer.block_item_mesh(st)
	if mesh != null:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		e.node.add_child(mi)
	add_child(e.node)
	ents.append(e)


func spawn_projectile(kind: String, p: Vector3, v: Vector3, owner_ref) -> void:
	if Net.is_client() and not Net.applying:
		Net.forward("projectile", [p.x, p.y, p.z, kind, v.x, v.y, v.z])
		return
	var e := Ent.new()
	e.kind = "projectile"
	e.id = kind
	e.pos = p
	e.prev = p
	e.vel = v
	e.owner = owner_ref
	# Java ThrownItemRenderer: thrown items (and fireballs as fire charges) are their item's ground model facing the
	# camera - half a block for 16 px sprites (small fireball 0.75x, ghast fireball 3x)
	var thrown := {"snowball": "snowball", "egg": "egg", "blue_egg": "blue_egg", "brown_egg": "brown_egg", "ender_pearl": "ender_pearl",
		"experience_bottle": "experience_bottle", "splash_potion": "splash_potion", "lingering_potion": "lingering_potion",
		"eye_of_ender": "ender_eye", "small_fireball": "fire_charge", "fireball": "fire_charge"}
	if thrown.has(kind) and Res.mode == "vanilla" and Res.items.id(thrown[kind]) > 0:
		var tim := ItemIcons.flat_image(Res.items.model_ref[Res.items.id(thrown[kind])])
		if tim != null:
			var spr := Sprite3D.new()
			spr.texture = ImageTexture.create_from_image(tim)
			spr.pixel_size = 0.5 / float(tim.get_width()) * (0.75 if kind == "small_fireball" else (3.0 if kind == "fireball" else 1.0))
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			spr.shaded = false
			e.node = Node3D.new()
			e.node.add_child(spr)
			add_child(e.node)
			ents.append(e)
			return
	if kind == "arrow" or kind == "trident":
		e.node = Node3D.new()
		e.node.add_child(projectile_rig(kind))
		add_child(e.node)
		ents.append(e)
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = {"arrow": Vector3(0.05, 0.05, 0.5), "trident": Vector3(0.08, 0.08, 1.1), "fireball": Vector3(1.0, 1.0, 1.0), "small_fireball": Vector3(0.3, 0.3, 0.3), "shulker_bullet": Vector3(0.3, 0.3, 0.3)}.get(kind, Vector3(0.12, 0.12, 0.12))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = {"snowball": Color.WHITE, "egg": Color(0.9, 0.85, 0.7), "ender_pearl": Color(0.1, 0.5, 0.4), "arrow": Color(0.5, 0.4, 0.3), "fireball": Color(1.0, 0.45, 0.1), "small_fireball": Color(1.0, 0.6, 0.15), "shulker_bullet": Color(0.95, 0.9, 0.7), "eye_of_ender": Color(0.3, 0.8, 0.5), "experience_bottle": Color(0.55, 0.85, 0.35), "trident": Color(0.35, 0.6, 0.55), "dragon_fireball": Color(0.7, 0.2, 0.9), "wither_skull": Color(0.15, 0.15, 0.15)}.get(kind, Color.GRAY)
	mi.material_override = mat
	e.node = Node3D.new()
	e.node.add_child(mi)
	add_child(e.node)
	ents.append(e)


## Java ArrowModel / TridentModel (layer definitions, 32x32 textures) oriented so the tip points along -Z (the
## projectile node looks along its flight). Arrow: two crossed 16x4 planes (texture v scale 0.8: built 5 px tall and
## squashed to 4) and the 5x5 fletching plane scaled 0.8, the whole mesh x0.9. Trident: pole + base + three spikes.
const ARROW_DEF := {"tex": "entity/projectiles/arrow", "tex_size": [32, 32], "model_y": 0.0, "scale": 0.9, "parts": [
	["back", [-11, 0, 0], [0, -2.5, -2.5], [0, 5, 5], [0, 0], 45.0],
	["cross_1", [0, 0, 0], [-12, -2.5, 0], [16, 5, 0], [0, 0], 45.0],
	["cross_2", [0, 0, 0], [-12, -2.5, 0], [16, 5, 0], [0, 0], 135.0]]}
const TRIDENT_DEF := {"tex": "entity/trident/trident", "tex_size": [32, 32], "model_y": 0.0, "parts": [
	["pole", [0, 0, 0], [-0.5, 2, -0.5], [1, 25, 1], [0, 6], 0],
	["base", [0, 0, 0], [-1.5, 0, -0.5], [3, 2, 1], [4, 0], 0],
	["left_spike", [0, 0, 0], [-2.5, -3, -0.5], [1, 4, 1], [4, 3], 0],
	["middle_spike", [0, 0, 0], [-0.5, -4, -0.5], [1, 4, 1], [0, 0], 0],
	["right_spike", [0, 0, 0], [1.5, -3, -0.5], [1, 4, 1], [4, 3], 0]]}


static func projectile_rig(kind: String, tex: String = "") -> Node3D:
	var def: Dictionary = (ARROW_DEF if kind == "arrow" else TRIDENT_DEF).duplicate()
	if tex != "":
		def["tex"] = tex
	var rig := EntityRenderer.build_rig(def)
	var md: Node3D = rig.get_node("model")
	if kind == "arrow":
		md.rotation.y = -PI / 2.0   # Java +x (tip) -> our -x after the model flip -> -Z
		for cn in ["cross_1", "cross_2"]:
			(md.get_node(cn) as Node3D).scale = Vector3(1, 0.8, 1)
		(md.get_node("back") as Node3D).scale = Vector3.ONE * 0.8
	else:
		md.rotation.x = -PI / 2.0   # spikes (Java -y -> our +y) -> -Z
	return rig


## Java EyeOfEnder.signalTo: aim at most 12 blocks toward the target, 8 blocks up; survives 4 in 5 throws.
## Dragon breath (area effect cloud): purple disc, 3 magic damage every 10 ticks within 3 blocks, 30 s.
func spawn_cloud(at: Vector3) -> void:
	if Net.is_client() and not Net.applying:
		return
	var e := Ent.new()
	e.kind = "cloud"
	e.pos = at
	e.prev = at
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.0
	cm.bottom_radius = 3.0
	cm.height = 0.1
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.7, 0.2, 0.9, 0.45)
	mi.material_override = mat
	e.node = Node3D.new()
	e.node.add_child(mi)
	add_child(e.node)
	ents.append(e)


func throw_eye(from: Vector3, target: Vector3) -> void:
	if Net.is_client():
		Net.forward("eye", [from.x, from.y, from.z, target.x, target.y, target.z])
		return
	spawn_projectile("eye_of_ender", from, Vector3.ZERO, null)
	var e: Ent = ents[ents.size() - 1]
	var d := Vector2(target.x - from.x, target.z - from.z)
	if d.length() > 12.0:
		var n := d.normalized() * 12.0
		e.target_pos = Vector3(from.x + n.x, from.y + 8.0, from.z + n.y)
	else:
		e.target_pos = target
	e.persistent = rng.randi_range(0, 4) > 0


func spawn_mob(id: String, p: Vector3, baby: bool = false) -> Ent:
	if Net.is_client() and not Net.applying:
		Net.forward("mob", [p.x, p.y, p.z, id, baby])
		return null
	var def := MobRegistry.get_def(id)
	if def.is_empty():
		if not _unimplemented_warned.has(id):   # once per id, in the log (it was a chat message per spawn)
			_unimplemented_warned[id] = true
			print_verbose("Mob '%s' is registered but not yet implemented (see docs/MOB_PARITY.md)" % id)
		return null
	var e := Ent.new()
	e.kind = "mob"
	e.id = id
	e.def = def
	e.pos = p
	e.prev = p
	e.w = float(def["w"]) * (0.5 if baby else 1.0)
	e.h = float(def["h"]) * (0.5 if baby else 1.0)
	e.hp = float(def["hp"])
	e.yaw = rng.randf_range(0, 360)
	e.body_yaw = e.yaw
	e.body_yaw_o = e.yaw
	e.head_yaw = e.yaw
	e.head_yaw_o = e.yaw
	e.head_last = e.yaw
	e.baby_age = -24000 if baby else 0
	e.persistent = def["kind"] == "passive"
	e.node = EntityRenderer.build_rig(def)
	EntityRenderer.group_head(e.node)
	if def.has("children"):
		EntityRenderer.group_children(e.node, def["children"])
	if baby:
		e.node.scale = Vector3.ONE * 0.5
	if def.get("trader", false):
		Trading.assign(e, rng)
	if id == "villager" or id == "zombie_villager":
		# Java VillagerRenderer layers: base + biome type + profession (VillagerProfessionLayer)
		var vt := "plains"
		if world != null and world.cm != null:
			var vch: Chunk = world.cm.get_chunk(floori(p.x) >> 4, floori(p.z) >> 4)
			if vch != null and not vch.biomes.is_empty():
				var vb := vch.biome_at(floori(p.x) & 15, floori(p.y), floori(p.z) & 15)
				if vb >= 0:
					vt = EntityRenderer.villager_type(world.biomes.names[vb])
		e.data["vtype"] = vt
		var root := "entity/zombie_villager/" if id == "zombie_villager" else "entity/villager/"
		var layers := [root + ("zombie_villager" if id == "zombie_villager" else "villager"), root + "type/" + vt]
		var prof := str(e.data.get("prof", ""))
		if prof != "" and prof != "none" and prof != "wandering_trader":
			layers.append(root + "profession/" + prof)
		var vm := EntityRenderer.material_layers(layers)
		for mi in _meshes(e.node):
			(mi as MeshInstance3D).material_override = vm
	if world != null and not baby:
		ArmorRender.equip_mob(e, rng, world.difficulty)
	if world != null:
		HeldItems.equip(e, rng, world.difficulty)
	if def.get("splits", false):
		# Java Slime.finalizeSpawn: size 1 << i, i in 0..2 (bumped with probability by difficulty)
		var i := rng.randi_range(0, 2)
		if i < 2 and rng.randf() < 0.5 * float(world.difficulty) / 3.0:
			i += 1
		set_size(e, 1 << i)
	add_child(e.node)
	ents.append(e)
	return e


func set_size(e: Ent, s: int) -> void:
	e.size = s
	e.w = 0.52 * s
	e.h = 0.52 * s
	e.hp = float(s * s)
	if e.node != null:
		e.node.scale = Vector3.ONE * float(s)


func _remove(e: Ent) -> void:
	e.dead = true
	if e.node != null:
		e.node.queue_free()
		e.node = null
	ents.erase(e)


# ------------------------------------------------------------------ tick

var last_tick_us := 0   # when the entity tick last ran (render interpolation origin)


func tick() -> void:
	tick_begin()
	while not tick_slice(1 << 30):
		pass


## Entity step of a game tick, in slices: tick_begin, then tick_slice until it returns true (WorldManager runs one
## slice per frame at high frame rates so a tick's entity AI never lands in one frame). Same entities, same order.
var _tick_list: Array = []
var _tick_i := 0


func tick_begin() -> void:
	last_tick_us = Time.get_ticks_usec()
	_tick_list = []
	_tick_i = 0
	if Net.is_client():
		for e in ents:
			e.age += 1   # puppets: positions come from host snapshots
		return
	_proxies = Net.proxies()
	Leads.tick(self)
	_tick_list = ents.duplicate()
	_nav_step(NAV_BUDGET_US)


## Mob path searches (MobPath jobs): Java finds a path inline when a goal asks for one; here the searches queue up
## and run within a per-tick time budget (a long search spans ticks instead of spiking one frame). A mob keeps
## following its previous path while the new one is searched.
const NAV_BUDGET_US := 400
var _nav_q: Array = []
var nav_max_us := 0   # longest _nav_step (probe statistic)


func nav_queue(e: Ent) -> void:
	if not _nav_q.has(e):
		_nav_q.append(e)


func _nav_step(budget_us: int) -> void:
	var t0 := Time.get_ticks_usec()
	_nav_step_inner(t0 + budget_us)
	nav_max_us = maxi(nav_max_us, Time.get_ticks_usec() - t0)


func _nav_step_inner(end: int) -> void:
	while not _nav_q.is_empty():
		var e: Ent = _nav_q[0]
		var j: MobPath = e.nav_job
		if j == null or e.dead:
			_nav_q.pop_front()
			continue
		if not j.step(end):
			break
		_nav_q.pop_front()
		e.nav_job = null
		e.path = j.result
		e.path_i = 0
		e.nav_stuck_t = e.age
		e.nav_stuck_pos = e.pos
		if j.mode == 0 and not j.reached:
			e.nav_cd += 15   # Java MeleeAttackGoal: an unreachable target is re-pathed less often
		if Time.get_ticks_usec() >= end:
			break


## Ticks up to max_n entities of the current pass (stopping early once Time.get_ticks_usec() passes deadline_us,
## after at least one entity); true when the pass (and the post-entity steps) are done.
func tick_slice(max_n: int, deadline_us: int = 0) -> bool:
	if Net.is_client():
		return true
	var p: Player = world.player
	var gs: Callable = world.state_at
	var blocks := Res.blocks
	var now := Time.get_ticks_usec()
	var end := mini(_tick_i + max_n, _tick_list.size())
	var tracing: bool = world.cm.tracing
	var worst_us := 0
	var worst_id := ""
	var n_ticked := 0
	while _tick_i < end:
		var e: Ent = _tick_list[_tick_i]
		_tick_i += 1
		if e.dead:
			continue
		var et0 := Time.get_ticks_usec() if tracing else 0
		_tick_one(e, p, gs, blocks, now)
		if deadline_us > 0 and Time.get_ticks_usec() >= deadline_us:
			break
		if tracing:
			n_ticked += 1
			var et := Time.get_ticks_usec() - et0
			if et > worst_us:
				worst_us = et
				worst_id = "%s/%s" % [e.kind, e.id]
	if tracing and worst_us > 300:
		world.frame_tparts["ent:worst " + worst_id] = worst_us
		world.frame_tparts["ent:ticked"] = n_ticked
	return _tick_rest(p)


func _tick_one(e: Ent, p: Player, gs: Callable, blocks, now: int) -> void:
	if true:
		e.tick_us = now
		e.prev = e.pos
		e.body_yaw_o = e.body_yaw
		e.head_yaw_o = e.head_yaw
		e.head_pitch_o = e.head_pitch
		e.limb_amt_o = e.limb_amt
		e.age += 1
		if not world.column_ready(e.pos.x, e.pos.z):
			return
		var pp: Player = p if _proxies.is_empty() else _nearest_player(e.pos, p)
		match e.kind:
			"item":
				_tick_item(e, pp, gs, blocks)
			"xp":
				_tick_xp(e, pp, gs, blocks)
			"falling":
				_tick_falling(e, gs, blocks)
			"projectile":
				_tick_projectile(e, pp, gs, blocks)
			"mob":
				if e.death_time > 0 or e.data.has("tear"):
					_tick_dying(e, gs, blocks)
				else:
					_tick_mob(e, pp, gs, blocks)
			"tnt":
				MiscEntities.tick_tnt(self, e, gs, blocks)
			"bobber":
				MiscEntities.tick_bobber(self, e, gs, blocks)
			"frame", "painting":
				MiscEntities.tick_hanging(self, e)
			"armor_stand":
				_physics(e, gs, blocks, 0.08, 0.91, 0.0)
			"cushion":
				MiscEntities.tick_cushion(self, e, gs, blocks)
			"boat":
				Vehicles.tick_boat(self, e, gs, blocks)
			"minecart":
				Vehicles.tick_cart(self, e, gs, blocks)
				if not e.dead and e.id != "minecart":
					Vehicles.cart_extras(self, e, gs, blocks)
			"cloud":
				if e.age % 10 == 0 and pp.pos.distance_to(e.pos) < 3.0 and absf(pp.pos.y - e.pos.y) < 2.0:
					pp.hurt(3.0, "magic")
				if e.age > 600:
					_remove(e)


func _tick_rest(p: Player) -> bool:
	if _tick_i < _tick_list.size():
		return false
	_tick_list = []
	if world.day_time == 2000 or world.day_time == 9000:
		for v in ents:
			if v.kind == "mob" and v.def.get("trader", false):
				Trading.restock(v)
	spawn_timer += 1
	if spawn_timer >= 20:
		spawn_timer = 0
		var tsp := Time.get_ticks_usec()
		_natural_spawn(p)
		for px in _proxies:
			_natural_spawn(px)
		if world.cm.tracing:
			world.frame_tparts["ent:natural_spawn"] = Time.get_ticks_usec() - tsp
	# Java ServerLevel.tick: everyone deep asleep (sleep counter 100) -> skip to the next morning, clear the weather,
	# wake up (no chat message)
	if p.sleeping and p.sleep_counter >= 100:
		if world.gamerule("doDaylightCycle", true):
			world.day_time = 0
		world.raining = false
		world.thundering = false
		wake_up()
	return true


## LAN host: nearest living, non-spectator player (local or remote stand-in) for targeting and pickup.
func _nearest_player(at: Vector3, p: Player) -> Player:
	var best: Player = p
	var bd := at.distance_squared_to(p.pos) if not p.dead and not p.is_spectator() else INF
	for px in _proxies:
		if px.dead or px.is_spectator():
			continue
		var d := at.distance_squared_to(px.pos)
		if d < bd:
			bd = d
			best = px
	return best


## LAN client: create a puppet from a host snapshot entry [uid, kind, id, x, y, z, yaw, pitch, flags, extra].
func spawn_puppet(en: Array) -> Ent:
	var p := Vector3(en[3], en[4], en[5])
	var n0 := ents.size()
	var e: Ent = null
	match str(en[1]):
		"mob":
			e = spawn_mob(str(en[2]), p, (int(en[8]) & 2) != 0)
			if e != null and en[9] is int and int(en[9]) > 1:
				set_size(e, int(en[9]))
		"item":
			if en[9] is Dictionary:
				e = spawn_item(p, ItemStack.from_dict(en[9]))
		"xp":
			spawn_xp(p, 1)
		"falling":
			spawn_falling_block(Vector3i(p.floor()), int(en[9]))
		"projectile":
			var v: Array = en[9] if en[9] is Array else [0, 0, 0]
			spawn_projectile(str(en[2]), p, Vector3(v[0], v[1], v[2]), null)
		"cloud":
			spawn_cloud(p)
	if e == null and ents.size() > n0:
		e = ents[ents.size() - 1]
	if e == null:
		return null
	e.remote = true
	e.uid = int(en[0])
	e.pos = p
	e.prev = p
	e.vel = Vector3.ZERO
	return e


func _physics(e: Ent, gs: Callable, blocks: BlockRegistry, gravity: float, drag: float, step: float = 0.0) -> void:
	var r := Collision.move(Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2), Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2), e.vel, gs, blocks, step, e.on_ground, e.ccache)
	var m: Vector3 = r["motion"]
	e.pos += m
	e.hcollide = r["hit_x"] or r["hit_z"]
	if r["hit_x"]:
		e.vel.x = 0
	if r["hit_z"]:
		e.vel.z = 0
	if r["hit_y"]:
		if e.vel.y < 0 and e.kind == "mob" and e.fall > 3.0:
			_damage(e, ceilf(e.fall - 3.0), null)
		e.vel.y = 0
	e.on_ground = r["on_ground"]
	if e.on_ground:
		e.fall = 0.0
	elif m.y < 0:
		e.fall -= m.y
	e.vel.y -= gravity
	e.vel.y *= 0.98
	var f := drag
	if e.on_ground:
		var below: int = gs.call(int(floor(e.pos.x)), int(floor(e.pos.y - 0.5)), int(floor(e.pos.z)))
		f = (float(blocks.block_info[blocks.st_block[maxi(below, 0)]]["friction"]) if below > 0 else 0.6) * 0.91
	e.vel.x *= f
	e.vel.z *= f


func _in_fluid(e: Ent, gs: Callable, blocks: BlockRegistry) -> int:
	var st: int = gs.call(int(floor(e.pos.x)), int(floor(e.pos.y + 0.1)), int(floor(e.pos.z)))
	if st > 0 and (blocks.st_flags[st] & (BlockRegistry.F_LIQUID | BlockRegistry.F_WATERLOGGED)):
		return 2 if blocks.st_flags[st] & BlockRegistry.F_LAVA else 1
	return 0


func _tick_item(e: Ent, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	if e.pickup_delay > 0:
		e.pickup_delay -= 1
	var fl := _in_fluid(e, gs, blocks)
	if fl == 1:
		e.vel.y += 0.05 if e.vel.y < 0.06 else 0.0
	elif fl == 2:
		_remove(e)
		return
	_physics(e, gs, blocks, 0.04, 0.98)
	if e.age >= 6000:
		_remove(e)
		return
	# merge
	if e.age % 10 == 0:
		for o in ents:
			if o != e and o.kind == "item" and not o.dead and o.pos.distance_squared_to(e.pos) < 0.5 * 0.5 + 0.25 and o.stack.can_merge(e.stack):
				var room := e.stack.max_stack() - e.stack.count
				if room > 0:
					var mv := mini(room, o.stack.count)
					e.stack.count += mv
					o.stack.count -= mv
					e.age = mini(e.age, o.age)
					if o.stack.count <= 0:
						_remove(o)
	# pickup
	if e.pickup_delay <= 0 and not p.dead and not p.is_spectator():
		var c := p.pos + Vector3(0, 0.9, 0)
		if absf(e.pos.x - p.pos.x) < 1.3 and absf(e.pos.z - p.pos.z) < 1.3 and e.pos.y > p.pos.y - 0.5 and e.pos.y < p.pos.y + 2.3:
			var left := p.inventory.add(e.stack)
			if left < e.stack.count:
				Audio.play("entity.item.pickup", c, "Players", 0.2, rng.randf_range(1.4, 2.0))
			if left == 0:
				_pickup_fly(e, p)
			else:
				e.stack.count = left


func _tick_xp(e: Ent, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	var to := p.pos + Vector3(0, p.eye_height() / 2, 0) - e.pos
	var d := to.length()
	if d < 8.0 and not p.dead:
		var k := 1.0 - d / 8.0
		e.vel += to.normalized() * k * k * 0.1
	_physics(e, gs, blocks, 0.03, 0.98)
	if d < 1.0 and not p.dead and not p.is_spectator():
		p.add_xp(e.xp)
		Audio.play("entity.experience_orb.pickup", p.pos, "Players", 0.1, rng.randf_range(0.55, 1.45))
		_pickup_fly(e, p)
	elif e.age > 6000:
		_remove(e)


## Java ItemPickupParticle: the picked-up item / orb keeps its look and flies into the player over 3 ticks
## (progress ((age + pt) / 3)^2 from where it lay to the player's position + 0.5).
var _pickups: Array = []   # [node, from (world), start usec, player]


func _pickup_fly(e: Ent, p: Player) -> void:
	var nd: Node3D = e.node
	e.node = null
	_remove(e)
	if nd != null:
		_pickups.append([nd, e.pos, Time.get_ticks_usec(), p])


func _animate_pickups() -> void:
	if _pickups.is_empty():
		return
	var now := Time.get_ticks_usec()
	for i in range(_pickups.size() - 1, -1, -1):
		var pk: Array = _pickups[i]
		var nd: Node3D = pk[0]
		var f := float(now - int(pk[2])) / 150000.0
		if f >= 1.0 or not is_instance_valid(nd):
			if is_instance_valid(nd):
				nd.queue_free()
			_pickups.remove_at(i)
			continue
		f *= f
		var pl: Player = pk[3]
		var to: Vector3 = pl.pos + Vector3(0, 0.5, 0)
		nd.position = world.vis((pk[1] as Vector3).lerp(to, f))


func _tick_falling(e: Ent, gs: Callable, blocks: BlockRegistry) -> void:
	_physics(e, gs, blocks, 0.04, 0.98)
	if e.on_ground or e.age > 600:
		var bp := Vector3i(int(floor(e.pos.x)), int(floor(e.pos.y + 0.01)), int(floor(e.pos.z)))
		var cur: int = gs.call(bp.x, bp.y, bp.z)
		if cur >= 0 and (blocks.st_flags[cur] & BlockRegistry.F_REPLACEABLE):
			world.set_block(bp.x, bp.y, bp.z, e.state)
		else:
			var it := Res.items.id(blocks.name_of(e.state))
			if it > 0:
				spawn_item(e.pos, ItemStack.of(it, 1))
		_remove(e)


func _tick_projectile(e: Ent, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	if e.id == "eye_of_ender":
		var dx := e.target_pos.x - e.pos.x
		var dz := e.target_pos.z - e.pos.z
		var dist := sqrt(dx * dx + dz * dz)
		var ang := atan2(dz, dx)
		var h := lerpf(Vector2(e.vel.x, e.vel.z).length(), dist, 0.0025)
		var vy := e.vel.y
		if dist < 1.0:
			h *= 0.8
			vy *= 0.8
		var j := 1.0 if e.pos.y < e.target_pos.y else -1.0
		e.vel = Vector3(cos(ang) * h, vy + (j - vy) * 0.015, sin(ang) * h)
		e.pos += e.vel
		if e.age > 80:
			Audio.play("entity.ender_eye.death", e.pos, "Neutral")
			if e.persistent:
				spawn_item(e.pos, ItemStack.named("ender_eye", 1))
			_remove(e)
		return
	if e.data.get("ground", false) or e.data.get("returning", false):
		_tick_stuck(e, p)
		return
	if e.id == "firework_rocket":
		# Java FireworkRocketEntity.tick (not attached): accelerate x1.15 horizontally, +0.04 up; explode at life end
		e.vel = Vector3(e.vel.x * 1.15, e.vel.y + 0.04, e.vel.z * 1.15)
		var fhit := VoxelRaycast.cast(e.pos, e.vel, e.vel.length(), gs, blocks)
		if fhit.is_empty():
			e.pos += e.vel
		else:
			e.data["life"] = 0
		if e.age % 2 == 0:
			Particles.emit("firework", e.pos, Vector3(rng.randfn(0, 0.02), -e.vel.y * 0.5, rng.randfn(0, 0.02)), Color.WHITE)
		if e.age >= int(e.data.get("life", 30)):
			_firework_explode(e, p)
			_remove(e)
		return
	var start := e.pos
	var hit := VoxelRaycast.cast(start, e.vel, e.vel.length(), gs, blocks)
	# entity hit
	var victim = null
	if e.owner != p and _seg_hits_box(start, e.vel, p.aabb_min(), p.aabb_max()):
		victim = p
	for o in ents:
		if o.kind == "mob" and o != e.owner and _seg_hits_box(start, e.vel, Vector3(o.pos.x - o.w / 2, o.pos.y, o.pos.z - o.w / 2), Vector3(o.pos.x + o.w / 2, o.pos.y + o.h, o.pos.z + o.w / 2)):
			victim = o
			break
	if victim != null:
		var dmg := 0.0
		if e.id == "arrow":
			# Java AbstractArrow.onHitEntity: ceil(speed * baseDamage), crits add random(0..dmg/2+1)
			dmg = ceilf(e.vel.length() * float(e.data.get("base_damage", 2.0)))
			if bool(e.data.get("crit", false)):
				dmg += rng.randi_range(0, int(dmg / 2.0) + 1)
		elif e.id == "trident":
			dmg = float(e.data.get("base_damage", 8.0))
		elif e.id == "fireball":
			dmg = 6.0
		elif e.id == "small_fireball":
			dmg = 5.0
		elif e.id == "shulker_bullet":
			dmg = 4.0
		elif e.id == "wither_skull":
			dmg = 8.0
		elif e.id == "snowball" and victim is Ent and (victim as Ent).id == "blaze":
			dmg = 3.0
		if victim is Player:
			if e.id == "small_fireball" or e.id == "fireball":
				(victim as Player).fire_ticks = maxi((victim as Player).fire_ticks, 100)
			if e.id == "shulker_bullet":
				(victim as Player).add_effect("levitation", 0, 200)
			if e.id == "wither_skull":
				(victim as Player).add_effect("wither", 1, 200)
			if e.data.has("potion"):
				Potions.apply(victim as Player, str(e.data["potion"]), 0.125)
			if dmg > 0:
				(victim as Player).hurt(dmg, "fireball" if e.id.ends_with("fireball") else "arrow")
				(victim as Player).vel += e.vel.normalized() * 0.4 + Vector3(0, 0.1, 0)
		else:
			_damage(victim, dmg, e.owner)
			(victim as Ent).vel += e.vel.normalized() * 0.4 + Vector3(0, 0.1, 0)
			if e.data.get("flame", false):
				(victim as Ent).fire = maxi((victim as Ent).fire, 100)
			if str(e.data.get("ammo", "")) == "spectral_arrow":
				(victim as Ent).data["glowing"] = 200
			var punch := int(e.data.get("punch", 0))
			if punch > 0:
				var hv := Vector3(e.vel.x, 0, e.vel.z).normalized() * punch * 0.6
				(victim as Ent).vel += Vector3(hv.x, 0.1, hv.z)
		if e.id == "trident":
			# Java ThrownTrident: bounces off the target, then lies there (or returns with Loyalty)
			e.vel = e.vel * Vector3(-0.01, -0.1, -0.01)
			_trident_landed(e, p)
			return
		_projectile_end(e, e.pos, p)
		return
	if not hit.is_empty():
		if e.id == "arrow" and e.data.has("pickup"):
			# Java AbstractArrow inGround: stays stuck, can be picked up
			e.pos = Vector3(hit["point"]) - e.vel.normalized() * 0.1
			e.data["ground"] = true
			e.data["ground_age"] = 0
			Audio.play("entity.arrow.hit", e.pos, "Neutral", 1.0, rng.randf_range(1.0, 1.2) / 1.1)
			Sculk.vibrate(world, e.pos, e.owner == world.player)
			return
		if e.id == "trident":
			e.pos = Vector3(hit["point"]) - e.vel.normalized() * 0.3
			Audio.play("item.trident.hit_ground", e.pos, "Neutral")
			_trident_landed(e, p)
			return
		_projectile_end(e, hit["point"], p)
		return
	e.pos += e.vel
	if e.id == "fireball" or e.id == "small_fireball" or e.id == "dragon_fireball" or e.id == "wither_skull":
		pass   # AbstractHurtingProjectile: constant acceleration, no gravity
	elif e.id == "shulker_bullet":
		var want := (p.pos + Vector3(0, p.eye_height() * 0.5, 0) - e.pos).normalized() * 0.15
		e.vel = e.vel.lerp(want, 0.08)
	else:
		e.vel *= 0.99
		e.vel.y -= 0.03 if e.id != "arrow" else 0.05
	if e.age > 1200:
		_remove(e)


## Java FireworkRocketEntity.explode / dealExplosionDamage: rockets with stars deal 5 + 2 per star, scaled by
## sqrt((5 - distance) / 5) within 5 blocks; spark balls in the star colors.
func _firework_explode(e: Ent, p: Player) -> void:
	var fw = e.stack.components.get("minecraft:fireworks", {}) if e.stack != null else {}
	var stars: Array = fw.get("explosions", []) if fw is Dictionary else []
	if stars.is_empty():
		return
	var large := false
	for st in stars:
		var sd: Dictionary = st if st is Dictionary else {}
		large = large or str(sd.get("shape", "small_ball")).ends_with("large_ball")
		var cols: Array = sd.get("colors", [0xFFFFFF])
		var n := 160 if str(sd.get("shape", "")).ends_with("large_ball") else 80
		var spd := 0.5 if n == 160 else 0.25
		for i in n:
			var dir := Vector3(rng.randfn(0, 1), rng.randfn(0, 1), rng.randfn(0, 1)).normalized()
			var cv := int(cols[rng.randi_range(0, cols.size() - 1)]) if not cols.is_empty() else 0xFFFFFF
			Particles.emit("firework", e.pos, dir * spd * rng.randf_range(0.85, 1.0), Color8((cv >> 16) & 255, (cv >> 8) & 255, cv & 255))
	Audio.play("entity.firework_rocket.large_blast" if large else "entity.firework_rocket.blast", e.pos, "Ambient", 3.0)
	var dmg := 5.0 + stars.size() * 2.0
	var pd := e.pos.distance_to(p.pos + Vector3(0, 0.9, 0))
	if pd <= 5.0:
		p.hurt(dmg * sqrt((5.0 - pd) / 5.0), "fireworks", false, e.pos)
	for o in ents:
		if o.kind == "mob" and not o.dead and o.pos.distance_to(e.pos) <= 5.0:
			_damage(o, dmg * sqrt((5.0 - o.pos.distance_to(e.pos)) / 5.0), e.owner)


## Arrow stuck in a block (pickup when the player touches it, gone after 1200 ticks) or a returning Loyalty trident.
func _tick_stuck(e: Ent, p: Player) -> void:
	if e.data.get("returning", false):
		var to := p.eye_pos() - e.pos
		var loy := float(e.data.get("loyalty", 1))
		e.pos.y += to.y * 0.015 * loy
		e.vel = e.vel * 0.95 + to.normalized() * 0.05 * loy
		e.pos += e.vel
		if to.length() < 1.5 or p.dead:
			_give_back(e, p)
		return
	e.data["ground_age"] = int(e.data.get("ground_age", 0)) + 1
	if int(e.data["ground_age"]) > 1200:
		_remove(e)
		return
	if e.data.get("pickup", false) and not p.dead and not p.is_spectator() and e.pos.distance_to(p.pos + Vector3(0, 0.9, 0)) < 1.4:
		_give_back(e, p)


func _give_back(e: Ent, p: Player) -> void:
	var s: ItemStack = e.stack.copy() if e.stack != null else ItemStack.named("arrow", 1)
	if e.data.get("pickup", false) and p.inventory.add(s) > 0:
		spawn_item(p.pos, s)
	Audio.play("entity.item.pickup", p.pos, "Players", 0.2, rng.randf_range(1.4, 2.0))
	world.inv_changed()
	_remove(e)


func _trident_landed(e: Ent, p: Player) -> void:
	if int(e.data.get("loyalty", 0)) > 0 and e.owner == p:
		e.data["returning"] = true
		Audio.play("item.trident.return", e.pos, "Neutral")
		return
	if e.data.get("pickup", false) and e.stack != null:
		var it = spawn_item(e.pos, e.stack.copy())
		if it != null:
			it.pickup_delay = 10
	_remove(e)


func _projectile_end(e: Ent, at: Vector3, p: Player) -> void:
	if e.id == "ender_pearl" and e.owner == p:
		p.pos = at
		p.prev_pos = at
		p.hurt(5.0, "fall")
	elif e.id in ["egg", "blue_egg", "brown_egg"]:
		# Java ThrownEgg.onHit: 1 in 8 hatches a chick (1 in 32 of those: four); item-break particles
		if rng.randi_range(0, 7) == 0:
			for k in (4 if rng.randi_range(0, 31) == 0 else 1):
				var chick := spawn_mob("chicken", at, true)
				if chick != null and e.id != "egg":
					chick.data["variant"] = "cold" if e.id == "blue_egg" else "warm"
		var est := e.stack if e.stack != null else ItemStack.named(e.id, 1)
		var eim := ItemIcons.flat_image(Res.items.model_ref[est.item]) if not est.is_empty() else null
		if eim != null:
			for k2 in 8:
				Particles.emit("item", at, Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.05, 0.15), rng.randf_range(-0.08, 0.08)), Color(1, 1, 1))
	elif e.id == "dragon_fireball":
		spawn_cloud(at)
	elif e.id == "wind_charge":
		Trials.wind_burst(world, at)
	elif e.id == "experience_bottle":
		# Java ThrownExperienceBottle.onHit: 3 + r(5) + r(5) XP, potion splash particles
		spawn_xp(at, 3 + rng.randi_range(0, 4) + rng.randi_range(0, 4))
		for i in 16:
			Particles.emit("effect", at, Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.05, 0.2), rng.randf_range(-0.15, 0.15)), Color(0.4, 0.8, 1.0))
		Audio.play("entity.splash_potion.break", at, "Neutral")
	if e.id in ["arrow", "snowball", "egg", "blue_egg", "brown_egg", "ender_pearl", "splash_potion", "trident"]:
		Sculk.vibrate(world, at, e.owner == world.player)
	if e.id == "splash_potion" or e.id == "lingering_potion":
		var pid := Potions.potion_of(e.stack) if e.stack != null else ""
		Audio.play("entity.splash_potion.break", at, "Neutral")
		var pd := p.pos.distance_to(at)
		if pd < 4.0:
			Potions.apply(p, pid, 1.0 - pd / 4.0 if e.id == "splash_potion" else 0.25)
	elif e.id == "wither_skull":
		explode(at, 1.0, world.gamerule("mobGriefing", true))
	elif e.id == "fireball":
		explode(at, 1.0, world.gamerule("mobGriefing", true))
		_ignite_near(at, 1)
	elif e.id == "small_fireball":
		_ignite_near(at, 0)
	_remove(e)


## Fire placed on air blocks above solid ground around an impact (fire spread itself is a block tick).
func _ignite_near(at: Vector3, r: int) -> void:
	if not world.gamerule("mobGriefing", true):
		return
	var fire := Res.blocks.default_state("fire")
	var c := Vector3i(int(floor(at.x)), int(floor(at.y)), int(floor(at.z)))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var q := c + Vector3i(dx, dy, dz)
				if world.state_at(q.x, q.y, q.z) == 0:
					var below: int = world.state_at(q.x, q.y - 1, q.z)
					if below > 0 and (Res.blocks.st_flags[below] & BlockRegistry.F_FULL_SHAPE) != 0 and (r == 0 or rng.randi_range(0, 2) == 0):
						world.set_block(q.x, q.y, q.z, fire)


static func _seg_hits_box(o: Vector3, v: Vector3, mn: Vector3, mx: Vector3) -> bool:
	var r := VoxelRaycast._ray_box(o, v.normalized(), mn, mx)
	return r.x >= 0.0 and r.x <= v.length()


# ------------------------------------------------------------------ mobs

func _light_at(p: Vector3) -> int:
	return world.cm.get_light(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)))


func _tick_mob(e: Ent, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	var def := e.def
	if e.noai:
		if not def.get("flies", false) and not def.get("stationary", false):
			_physics(e, gs, blocks, 0.08, 0.91, 0.0)
		return
	if e.hurt_time > 0:
		e.hurt_time -= 1
	if e.invuln > 0:
		e.invuln -= 1
	if e.attack_cd > 0:
		e.attack_cd -= 1
	if e.breed_cd > 0:
		e.breed_cd -= 1
	if e.love > 0:
		e.love -= 1
	if e.baby_age < 0:
		e.baby_age += 1
		if e.baby_age == 0:
			e.w = float(def["w"])
			e.h = float(def["h"])
			e.node.scale = Vector3.ONE
	if e == world.player.vehicle:
		Taming.ride_tick(self, e, world.player, gs, blocks)
		e.head_yaw = e.body_yaw
		return
	if e.id == "creaking" and Creaking.looked_at(world, e):
		# Java Creaking: cannot move while watched
		e.vel.x = 0.0
		e.vel.z = 0.0
		e.limb_amt = 0.0
		_physics(e, gs, blocks, 0.08, 0.91, 0.0)
		return
	var dist := e.pos.distance_to(p.pos)
	# despawn hostile mobs far away
	if def["kind"] == "hostile" and not e.persistent:
		if dist > 128.0 or (dist > 32.0 and rng.randi_range(0, 799) == 0):
			_remove(e)
			return
	if def["kind"] == "hostile" and world.difficulty == 0 and not def.get("boss", false):
		_remove(e)
		return
	var fl := _in_fluid(e, gs, blocks)
	var fire_immune: bool = def.get("fire_immune", false)
	if fl == 2 and def.get("lava_walker", false):
		e.vel.y = maxf(e.vel.y, 0.06)   # striders float on lava
	if fl == 2 and not fire_immune:
		e.fire = 300
		_damage(e, 4.0, null)
	if fl == 1 and def.get("water_hurts", false):
		_damage(e, 1.0, null)
		if def.get("teleports", false):
			_teleport(e, gs, blocks)
	if e.tp_cd > 0:
		e.tp_cd -= 1
	# daylight burning
	if def.get("burns", false) and e.baby_age >= 0 and world.sky_darken() > 0.8 and e.age % 20 == 0 and fl == 0 and str((e.data.get("armor", ["", "", "", ""]) as Array)[3]) == "":
		var l := _light_at(e.pos + Vector3(0, e.h, 0))
		if (l >> 4) >= 15 and not world.raining:
			e.fire = maxi(e.fire, 160)
	if e.fire > 0:
		e.fire -= 1
		if fl == 1:
			e.fire = 0
		elif e.fire % 20 == 0 and not fire_immune:
			_damage(e, 1.0, null)
	# special archetypes (flyers, hoppers, stationary shulkers) run their own movement
	if def.get("flies", false) or def.get("hops", false) or def.get("stationary", false) or def.get("swims", false):
		MobAI.tick_special(self, e, p, gs, blocks, dist, fl)
		return
	# --- AI goal selection (Java GoalSelector priorities: owner / attack, panic, breed, tempt, follow parent, stroll;
	# the look goals run beside them). nav_target: this tick's navigation.moveTo target; nav_rand: following a stroll
	# (1) / panic (2) path whose random target the path job picks. direct: steer straight (close melee, climbers).
	var nav_target := Vector3.INF
	var nav_rand := 0
	var direct := false
	var look_busy := false
	var pet_mode := 0
	if e.data.has("owner"):
		var pg: Array = Taming.pet_goal(self, e)
		pet_mode = pg[0]
		nav_target = pg[1]
		if pet_mode == 1:
			e.vel.x = 0.0
			e.vel.z = 0.0
			MobControl.nav_stop(e)
			_physics(e, gs, blocks, 0.08, 0.91, 0.6)
			e.limb_amt = lerpf(e.limb_amt, 0.0, 0.4)
			MobControl.look_goals(self, e, p, dist, false, false)
			MobControl.look_tick(e, false)
			MobControl.body_tick(e)
			return
	var speed := float(def["speed"])
	var hostile: bool = def["kind"] == "hostile"
	if pet_mode == 2:
		e.target_player = false
	elif hostile and not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE):
		var aggressive := MobAI.wants_target(self, e, p, dist)
		if e.id in ["spider", "cave_spider"] and ((_light_at(e.pos) >> 4) > 11 and world.sky_darken() > 0.6) and e.hurt_time == 0 and not e.target_player:
			aggressive = false
		if aggressive and dist < 16.0 + (19.0 if e.id in ["zombie", "husk", "drowned"] else 0.0):
			e.target_player = true
	else:
		e.target_player = false
	if pet_mode == 2:
		speed *= 1.3
	elif e.target_player:
		look_busy = true
		MobControl.set_look(e, p.pos + Vector3(0, p.eye_height(), 0), 30.0, 30.0)
		if dist > 40.0:
			e.target_player = false
		elif def.get("ranged", false):
			if dist > 12.0:
				nav_target = p.pos
			elif dist < 6.0:
				nav_target = e.pos + (e.pos - p.pos).normalized() * 3.0
			if e.attack_cd <= 0 and dist < 16.0:
				var from := e.pos + Vector3(0, e.h * 0.85, 0)
				var aim := p.pos + Vector3(0, p.eye_height() * 0.7, 0) - from
				aim.y += Vector2(aim.x, aim.z).length() * 0.2
				spawn_projectile("arrow", from, aim.normalized() * 1.6, e)
				Audio.play("entity.skeleton.shoot", e.pos, "Hostile")
				e.attack_cd = [60, 40, 20][clampi(world.difficulty - 1, 0, 2)]
		elif def.get("explodes", false):
			nav_target = p.pos
			direct = dist < 2.5 and absf(p.pos.y - e.pos.y) < 1.0
			if dist < 3.0 or e.fuse >= 0:
				if e.fuse < 0:
					e.fuse = 0
					Audio.play("entity.creeper.primed", e.pos, "Hostile")
				if dist > 7.0:
					e.fuse = -1
				else:
					e.fuse += 1
					nav_target = Vector3.INF
					if e.fuse >= 30:
						explode(e.pos + Vector3(0, 0.5, 0), 3.0, world.gamerule("mobGriefing", true))
						_remove(e)
						return
		else:
			nav_target = p.pos
			# Java WallClimberNavigation heads straight for the target; melee mobs close the last block directly
			direct = def.get("climbs", false) or (dist < 2.5 and absf(p.pos.y - e.pos.y) < 1.0)
			if dist < e.w * 0.5 + 0.3 + 1.0 and e.attack_cd <= 0 and absf(p.pos.y - e.pos.y) < 1.5:
				var dmg: float = (float(def.get("attack", 2.0)) + HeldItems.attack_bonus(e)) * [0.0, 0.5, 1.0, 1.5][world.difficulty]
				if def.get("wither_hit", false):
					p.add_effect("wither", 0, 200)
				if p.hurt(dmg, "mob", false, e.pos, e):
					if p == world.player:
						pet_target = e
					var kb := (p.pos - e.pos)
					kb.y = 0
					p.vel += kb.normalized() * 0.4 + Vector3(0, 0.36, 0)
					if e.id == "cave_spider" and world.difficulty >= 2:
						p.add_effect("poison", 0, 140 if world.difficulty == 2 else 300)
					if e.id == "husk":
						p.add_effect("hunger", 0, 140)
				e.attack_cd = 20
	elif e.panic > 0:
		# Java PanicGoal: runs to random spots within 5 / 4 blocks until the panic ends
		e.panic -= 1
		speed *= 1.75
		e.has_target = false
		if MobControl.nav_idle(e):
			MobControl.nav_random(self, e, 2)
		nav_rand = 2
	else:
		# Java TemptGoal (stops within 2.5 blocks, watches the player) / BreedGoal / FollowParentGoal / RandomStrollGoal
		var food: Array = def.get("food", [])
		var held := p.inventory.held()
		if not food.is_empty() and not held.is_empty() and food.has(held.name()) and dist < 10.0 and not p.dead:
			look_busy = true
			MobControl.set_look(e, p.pos + Vector3(0, p.eye_height(), 0), 95.0, 40.0)
			nav_target = p.pos if dist > 2.5 else Vector3.INF
			e.has_target = false
		elif e.love > 0:
			for o in ents:
				if o != e and o.kind == "mob" and o.id == e.id and o.love > 0 and o.pos.distance_to(e.pos) < 8.0:
					nav_target = o.pos
					look_busy = true
					MobControl.set_look(e, o.pos + Vector3(0, o.h * 0.85, 0), 10.0, 40.0)
					e.has_target = false
					if o.pos.distance_to(e.pos) < 1.5:
						var baby := spawn_mob(e.id, e.pos, true)
						if baby != null and world.advancements != null:
							world.advancements.trigger("bred_animals", {"entity": e.id})
						if baby != null:
							spawn_xp(e.pos, rng.randi_range(1, 7))
						e.love = 0
						o.love = 0
						e.breed_cd = 6000
						o.breed_cd = 6000
					break
		elif e.baby_age < 0 and not hostile and e.age % 10 == 0:
			# Java FollowParentGoal: the nearest adult of the kind within 8 blocks, followed while 3+ blocks away
			var best: Ent = null
			var bd := 64.0
			for o in ents:
				if o != e and o.kind == "mob" and o.id == e.id and o.baby_age >= 0:
					var d2: float = o.pos.distance_squared_to(e.pos)
					if d2 < bd:
						bd = d2
						best = o
			e.parent_pos = best.pos if best != null and bd >= 9.0 else Vector3.INF
		if nav_target == Vector3.INF and not look_busy and e.love <= 0:
			if e.baby_age < 0 and e.parent_pos != Vector3.INF:
				nav_target = e.parent_pos
				speed *= 1.25
				e.has_target = false
			else:
				# Java RandomStrollGoal: 1 in 120 per tick while idle (not when no player is within 32 blocks)
				if not e.has_target and dist < 32.0 and rng.randi_range(0, 119) == 0:
					MobControl.nav_random(self, e, 1)
					e.has_target = true
				if e.has_target:
					if MobControl.nav_idle(e):
						e.has_target = false
					else:
						nav_rand = 1
	# --- navigation (Java PathNavigation / MoveControl / JumpControl)
	if e.nav_cd > 0:
		e.nav_cd -= 1
	if e.jump_delay > 0:
		e.jump_delay -= 1
	var wanted := Vector3.INF
	if direct and nav_target != Vector3.INF:
		MobControl.nav_stop(e)
		wanted = nav_target
	elif nav_target != Vector3.INF:
		MobControl.nav_to(self, e, nav_target, dist)
		wanted = MobControl.nav_next(e, speed)
	elif nav_rand > 0:
		wanted = MobControl.nav_next(e, speed)
	elif e.nav_job != null or not e.path.is_empty():
		MobControl.nav_stop(e)
	var fwd := 0.0
	var jump := false
	if wanted != Vector3.INF:
		var mc := MobControl.move_control(e, wanted)
		if mc > 0:
			fwd = 1.0
		jump = mc == 2 or (direct and e.hcollide)
		if def.get("climbs", false) and e.hcollide:
			e.vel.y = 0.2
	if jump:
		if e.on_ground and e.jump_delay == 0:
			e.vel.y = 0.42
			e.jump_delay = 10
	else:
		e.jump_delay = 0
	MobControl.look_goals(self, e, p, dist, fwd > 0.0, look_busy)
	MobControl.look_tick(e, wanted != Vector3.INF)
	if fl == 1:
		e.vel.y += 0.04 if e.vel.y < 0.1 else 0.0
		if e.hcollide:
			e.vel.y = 0.3
	# Java: input length = speed, friction-influenced multiplier = speed * 0.216/slip^3 (slip 0.6 -> 1.0)
	var accel := speed * speed if e.on_ground else speed * 0.02
	if fwd > 0.0:
		var yr := deg_to_rad(e.yaw)
		e.vel += Vector3(-sin(yr), 0, cos(yr)) * accel
	_physics(e, gs, blocks, 0.08 if fl == 0 else 0.02, 0.91 if fl == 0 else 0.8, 0.6)
	MobControl.body_tick(e)
	var mv := Vector2(e.pos.x - e.prev.x, e.pos.z - e.prev.z).length()
	e.limb_amt = lerpf(e.limb_amt, minf(mv * 4.0, 1.0), 0.4)
	e.limb += e.limb_amt
	if e.pos.y < Coords.MIN_Y - 64:
		_remove(e)
		return
	# ambient sound
	if rng.randi_range(0, 239) == 0 and dist < 16.0:
		Audio.play("entity.%s.ambient" % e.id, e.pos, "Hostile" if hostile else "Neutral")
	# fall damage handled in _physics


func _damage(e: Ent, amount: float, source) -> void:
	if e.dead or e.death_time > 0 or e.data.has("tear") or e.invuln > 10 or amount <= 0.0:
		return
	if e.id == "creaking" and Creaking.absorb_hit(world, e):
		e.invuln = 10
		return
	if e.id == "wither" and e.charge < 0:
		return   # invulnerable while charging
	if e.def.get("dragon", false):
		if e.state == DragonFight.Ph.DYING:
			return
		if not (e.state in [DragonFight.Ph.SITTING_SCANNING, DragonFight.Ph.SITTING_ATTACKING, DragonFight.Ph.SITTING_FLAMING]):
			amount = amount / 4.0 + minf(amount, 1.0)   # Java: hits off the head part (perched: the head is in reach)
	var harmor := ArmorRender.horse_armor_points(e) if e.data.has("horse_armor") else 0
	if harmor > 0:
		amount *= 1.0 - minf(20.0, float(harmor)) / 25.0   # Java armor formula without toughness
	e.hp -= amount
	e.hurt_time = 10
	e.invuln = 20
	if e.def.get("kind") == "passive":
		e.panic = 60
	elif source is Player:
		e.target_player = true
		e.angry = true
		if e.def.get("group_anger", false):
			for o in ents:
				if o.kind == "mob" and o.id == e.id and o.pos.distance_to(e.pos) < 20.0:
					o.angry = true
					o.target_player = true
	if e.def.get("teleports", false) and e.hp > 0.0 and rng.randf() < 0.5:
		_teleport(e, world.state_at, Res.blocks)
	Audio.play("entity.%s.hurt" % e.id, e.pos, "Neutral")
	if e.hp <= 0.0:
		_die(e, source is Player)


## Java EnderMan.teleport: random target within 32 blocks, dropping to the ground; up to 16 tries.
func _teleport(e: Ent, gs: Callable, blocks: BlockRegistry) -> bool:
	if e.tp_cd > 0:
		return false
	for i in 16:
		var t := e.pos + Vector3(rng.randf_range(-32, 32), rng.randi_range(-32, 32), rng.randf_range(-32, 32))
		var x := int(floor(t.x))
		var z := int(floor(t.z))
		var y := int(floor(t.y))
		if not world.column_ready(t.x, t.z):
			continue
		while y > world.gen.gen_min_y and gs.call(x, y - 1, z) <= 0:
			y -= 1
		var below: int = gs.call(x, y - 1, z)
		if below <= 0 or (blocks.st_flags[below] & BlockRegistry.F_COLLIDE) == 0 or (blocks.st_flags[below] & BlockRegistry.F_LIQUID) != 0:
			continue
		var clear := true
		for hy in int(ceil(e.h)):
			if gs.call(x, y + hy, z) != 0:
				clear = false
				break
		if not clear:
			continue
		Audio.play("entity.enderman.teleport", e.pos, "Hostile")
		e.pos = Vector3(x + 0.5, y, z + 0.5)
		e.prev = e.pos
		e.vel = Vector3.ZERO
		e.tp_cd = 20
		return true
	return false


func _die(e: Ent, by_player: bool) -> void:
	if e.id == "end_crystal":
		_remove(e)
		explode(e.pos + Vector3(0, 0.5, 0), 6.0, true)
		for o in ents:
			if o.kind == "mob" and o.id == "ender_dragon" and o.pos.distance_to(e.pos) < 32.0:
				_damage(o, 10.0, null)
		return
	if e.id == "ender_dragon":
		DragonFight.start_dying(e)   # 200 ticks rising and spinning, then on_dragon_death
		return
	if e.def.get("splits", false) and e.size > 1:
		var n := 2 + rng.randi_range(0, 2)
		for i in n:
			var c := spawn_mob(e.id, e.pos + Vector3(rng.randf_range(-0.5, 0.5) * e.size * 0.5, 0.5, rng.randf_range(-0.5, 0.5) * e.size * 0.5))
			if c != null:
				set_size(c, e.size / 2)
	Audio.play("entity.%s.death" % e.id, e.pos, "Neutral")
	if world.gamerule("doMobLoot", true) and e.baby_age >= 0:
		var ctx := {"tool": world.player.inventory.held(), "rng": world.rng, "by_player": by_player, "on_fire": e.fire > 0,
			"entity_id": e.id, "size": e.size, "captain": bool(e.data.get("captain", false)), "sheared": e.sheared,
			"sheep_color": str(e.data.get("color", "white")), "baby": e.baby_age < 0}
		var tid := "entities/" + e.id
		var got_bottle := false
		for s in Loot.roll(tid, ctx):
			got_bottle = got_bottle or (s as ItemStack).name() == "ominous_bottle"
			spawn_item(e.pos + Vector3(0, 0.5, 0), s)
		if Res.mode != "vanilla" or Loot.table(tid) == null:
			var fallback := {"pig": "porkchop", "cow": "beef", "chicken": "chicken", "sheep": "mutton", "zombie": "rotten_flesh", "skeleton": "bone", "creeper": "gunpowder", "spider": "string"}
			if fallback.has(e.id):
				spawn_item(e.pos + Vector3(0, 0.5, 0), ItemStack.named(fallback[e.id], 1 + rng.randi_range(0, 1)))
		ArmorRender.death_drops(self, e)
		HeldItems.drops(self, e, by_player)
		if by_player and bool(e.data.get("captain", false)) and not got_bottle:
			var ob := ItemStack.named("ominous_bottle", 1)
			ob.components["minecraft:ominous_bottle_amplifier"] = rng.randi_range(0, 4)
			spawn_item(e.pos + Vector3(0, 0.5, 0), ob)
		if by_player:
			world.player.stats["killed." + e.id] = int(world.player.stats.get("killed." + e.id, 0)) + 1
			if world.advancements != null:
				world.advancements.trigger("player_killed_entity", {"entity": e.id})
			var xr: Array = e.def.get("xp", [1, 3])
			spawn_xp(e.pos, rng.randi_range(int(xr[0]), int(xr[1])))
	# Java LivingEntity.tickDeath: the body stays 20 ticks (red, falling onto its side), then poofs (_tick_dying)
	e.death_time = 1
	e.hp = 0.0
	e.target_player = false
	MobControl.nav_stop(e)


## Java LivingEntity.tickDeath / makePoofParticles; Creaking tear-down (45 ticks of twitching, then it crumbles).
func _tick_dying(e: Ent, gs: Callable, blocks: BlockRegistry) -> void:
	if e.hurt_time > 0:
		e.hurt_time -= 1
	_physics(e, gs, blocks, 0.08, 0.91, 0.0)
	e.limb_amt = lerpf(e.limb_amt, 0.0, 0.4)
	if e.data.has("tear"):
		e.data["tear"] = int(e.data["tear"]) + 1
		if int(e.data["tear"]) >= 45:
			var pw := Res.blocks.default_state("pale_oak_wood")
			for k in 6:
				Particles.terrain(e.pos + Vector3(rng.randf_range(-0.4, 0.4), rng.randf() * e.h, rng.randf_range(-0.4, 0.4)), pw)
			Audio.play("entity.creaking.death", e.pos, "Hostile")
			_remove(e)
		return
	e.death_time += 1
	if e.death_time >= 20:
		for k in 20:
			Particles.emit("smoke", e.pos + Vector3(rng.randf_range(-1, 1) * e.w, rng.randf() * e.h, rng.randf_range(-1, 1) * e.w),
				Vector3(rng.randfn() * 0.02, rng.randfn() * 0.02, rng.randfn() * 0.02), Color(1, 1, 1))
		_remove(e)


## Java Explosion: 16^3 surface rays from the centre, each with radius * (0.7..1.3) strength losing
## (resistance + 0.3) * 0.3 per 0.3-block step (water / lava stop them); entities within 2 * radius take
## (k^2 + k) / 2 * 7 * 2r + 1 damage (k = (1 - d / 2r), line-of-sight not modelled) and items there are destroyed -
## BEFORE the blocks go, so the destroyed blocks' drops survive (loot survives_explosion: 1 / radius); TNT in the blast
## primes with a 10..29 tick fuse; the touched chunks remesh at once.
func explode(at: Vector3, power: float, destroy: bool) -> void:
	Audio.play("entity.generic.explode", at, "Blocks", 4.0)
	Sculk.vibrate(world, at, false)
	# Java HugeExplosionSeedParticle: six explosion sprites within 4 blocks
	for i in (6 if power >= 2.0 else 1):
		Particles.emit("explosion", at + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2)) * (1.0 if power >= 2.0 else 0.0))
	var hit := {}
	if destroy:
		var res_cache := {}
		for j in 16:
			for k in 16:
				for l in 16:
					if not (j == 0 or j == 15 or k == 0 or k == 15 or l == 0 or l == 15):
						continue
					var d := Vector3(j / 15.0 * 2.0 - 1.0, k / 15.0 * 2.0 - 1.0, l / 15.0 * 2.0 - 1.0).normalized()
					var f := power * (0.7 + rng.randf() * 0.6)
					var q := at
					while f > 0.0:
						var bp := Vector3i(floori(q.x), floori(q.y), floori(q.z))
						if bp.y < Coords.MIN_Y or bp.y >= Coords.MAX_Y:
							break
						var rk := (bp.x << 40) ^ (bp.z << 16) ^ (bp.y + 64)
						var r = res_cache.get(rk)
						if r == null:
							var st: int = world.state_at(bp.x, bp.y, bp.z)
							if st < 0:
								r = 3600000.0
							elif st == 0:
								r = -1.0
							else:
								var bi: int = Res.blocks.st_block[st]
								r = 100.0 if Res.blocks.st_flags[st] & BlockRegistry.F_LIQUID else (3600000.0 if Res.blocks.hardness[bi] < 0.0 else float(Res.blocks.block_info[bi]["resistance"]))
								if Res.blocks.st_flags[st] & BlockRegistry.F_WATERLOGGED:
									r = maxf(r, 100.0)
							res_cache[rk] = r
						if r >= 0.0:
							f -= (r + 0.3) * 0.3
							if f > 0.0:
								hit[bp] = true
						f -= 0.22500001
						q += d * 0.3
	# entities first (Java hurtEntities), then the blocks (finalizeExplosion)
	var p: Player = world.player
	var pd := p.pos.distance_to(at)
	if pd < power * 2.0:
		var impact := (1.0 - pd / (power * 2.0))
		p.hurt(floorf((impact * impact + impact) / 2.0 * 7.0 * power * 2.0 + 1.0), "explosion", false, at)
		p.vel += (p.pos - at).normalized() * impact
	for o in ents.duplicate():
		if o.kind == "mob" and o.pos.distance_to(at) < power * 2.0:
			var imp: float = 1.0 - o.pos.distance_to(at) / (power * 2.0)
			_damage(o, floorf((imp * imp + imp) / 2.0 * 7.0 * power * 2.0 + 1.0), null)
			o.vel += (o.pos - at).normalized() * imp
		elif o.kind == "item" and o.pos.distance_to(at) < power * 2.0 and o.stack != null and o.stack.name() != "nether_star":
			_remove(o)
	if hit.is_empty():
		return
	var lst: Array = hit.keys()
	lst.shuffle()
	var touched := {}
	for bp2 in lst:
		var st2: int = world.state_at(bp2.x, bp2.y, bp2.z)
		if st2 <= 0 or (Res.blocks.st_flags[st2] & BlockRegistry.F_LIQUID):
			continue
		var nm := Res.blocks.name_of(st2)
		touched[((bp2.x >> 4) << 32) | ((bp2.z >> 4) & 0xFFFFFFFF)] = bp2
		if nm == "tnt":
			world.set_block(bp2.x, bp2.y, bp2.z, 0)
			MiscEntities.spawn_tnt(self, Vector3(bp2) + Vector3(0.5, 0.0, 0.5), rng.randi_range(0, 19) + 10)
			continue
		world.set_block(bp2.x, bp2.y, bp2.z, 0)
		var ctx := {"tool": null, "rng": world.rng, "explosion": true, "explosion_radius": power, "state": st2, "pos": bp2}
		var t = Loot.table("blocks/" + nm)
		if t is Dictionary:
			for s in Loot.roll_table(t, ctx):
				spawn_item(Vector3(bp2) + Vector3(0.5, 0.5, 0.5), s)
	for ck in touched:
		var tp: Vector3i = touched[ck]
		world.cm.mark_urgent(tp.x, tp.z)

func player_attack(e: Ent) -> void:
	if e == null or e.dead:
		return
	var p: Player = world.player
	var held := p.inventory.held()
	if e.kind == "boat" or e.kind == "minecart":
		Vehicles.hit(self, e, p)
		return
	if e.kind in ["frame", "painting", "armor_stand", "cushion"]:
		MiscEntities.attack(self, e, p)
		return
	# Java Player.attack (1.9+ combat): attack strength scales damage, gates crits / sweeps / sprint knockback
	var f := p.attack_strength(0.5)
	var dmg: float = 1.0 if held.is_empty() else Res.items.attack_damage[held.item]
	var ench := _ench_damage(held, e)
	dmg *= 0.2 + f * f * 0.8
	ench *= f
	var strong := f > 0.9
	var kb_bonus := Loot._ench(held, "knockback")
	var sprint_kb := false
	if p.sprinting and strong:
		kb_bonus += 1
		sprint_kb = true
		Audio.play("entity.player.attack.knockback", e.pos, "Players")
	var crit := strong and p.fall_distance > 0.0 and not p.on_ground and not p.on_climbable and not p.in_water and not p.effects.has("blindness") and p.vehicle == null and not p.sprinting
	if crit:
		dmg *= 1.5
	dmg += ench
	var is_sword := not held.is_empty() and Res.items.tool_kind[held.item] == "sword"
	var sweep := strong and not crit and not sprint_kb and p.on_ground and Vector2(p.pos.x - p.prev_pos.x, p.pos.z - p.prev_pos.z).length() < 0.13 and is_sword
	var snd := "crit" if crit else ("sweep" if sweep else ("strong" if strong else "weak"))
	if e.remote:
		var yr0 := deg_to_rad(p.yaw)
		var kb := Vector3(-sin(yr0) * 0.4, 0.36, cos(yr0) * 0.4) * (1.0 + 0.5 * kb_bonus)
		Net.forward("attack", [e.uid, dmg, kb.x, kb.y, kb.z])
		Audio.play("entity.player.attack." + snd, e.pos, "Players")
		if not held.is_empty():
			Interaction.damage_tool(p, 1 if is_sword else 2)
		return
	if e.kind != "mob":
		return
	if not (e.data.has("owner") and str(e.data["owner"]) == Taming.owner_name()):
		pet_target = e
	var yr := deg_to_rad(p.yaw)
	var hp0: float = e.hp
	_damage(e, dmg, p)
	if e.hp < hp0 or e.dead:
		# Java LivingEntity.hurt knockback 0.4 from the attacker, plus Knockback / sprint bonus * 0.5 along the look
		_knockback(e, 0.4, e.pos.x - p.pos.x, e.pos.z - p.pos.z)
		if kb_bonus > 0:
			_knockback(e, kb_bonus * 0.5, -sin(yr), cos(yr))
			p.vel.x *= 0.6
			p.vel.z *= 0.6
			p.sprinting = false
		if sweep:
			var sratio := 0.0
			var se := Loot._ench(held, "sweeping_edge")
			if se > 0:
				sratio = 1.0 - 1.0 / (se + 1.0)
			for o in ents.duplicate():
				if o == e or o.kind != "mob" or o.dead or o.remote:
					continue
				if absf(o.pos.x - e.pos.x) > (o.w + e.w) * 0.5 + 1.0 or absf(o.pos.z - e.pos.z) > (o.w + e.w) * 0.5 + 1.0 or o.pos.y > e.pos.y + e.h + 0.25 or o.pos.y + o.h < e.pos.y - 0.25:
					continue
				if o.pos.distance_squared_to(p.pos) >= 9.0 or (o.data.has("owner") and str(o.data["owner"]) == Taming.owner_name()):
					continue
				_knockback(o, 0.4, -sin(yr), cos(yr))   # Java knockback(0.4, sin, -cos): along the look
				_damage(o, 1.0 + sratio * dmg, p)
			Particles.emit("sweep_attack", p.pos + Vector3(-sin(yr), p.eye_height() * 0.5, cos(yr)), Vector3.ZERO)
		if crit:
			for i in 12:
				Particles.emit("crit", e.pos + Vector3(0, e.h * 0.5, 0), Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)) * 0.3)
		if ench > 0.0:
			for i in 8:
				Particles.emit("enchanted_hit", e.pos + Vector3(0, e.h * 0.5, 0), Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 1), rng.randf_range(-1, 1)) * 0.3)
		if Loot._ench(held, "fire_aspect") > 0:
			e.fire = maxi(e.fire, 80 * Loot._ench(held, "fire_aspect"))
		Audio.play("entity.player.attack." + snd, e.pos, "Players")
	else:
		Audio.play("entity.player.attack.nodamage", e.pos, "Players")
	if not held.is_empty():
		Interaction.damage_tool(p, 1 if is_sword else 2)


## Java EntityRenderer.renderNameTag: custom names show when the crosshair is on the mob (or CustomNameVisible).
func _nameplate(e: Ent) -> void:
	var lb: Label3D = e.node.get_node_or_null("nameplate")
	if lb == null:
		lb = Label3D.new()
		lb.name = "nameplate"
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.font = UiKit.font()
		lb.font_size = 32
		lb.pixel_size = 0.025 * 9.0 / 32.0
		lb.outline_size = 0
		lb.modulate = Color(1, 1, 1, 1)
		lb.no_depth_test = false
		e.node.add_child(lb)
	lb.text = str(e.data["CustomName"])
	lb.position = Vector3(0, e.h + 0.5, 0)
	var looked: bool = world.target.has("entity") and world.target["entity"] == e
	lb.visible = looked or bool(e.data.get("CustomNameVisible", false))


## Java Enchantment damage bonus: Sharpness 0.5*lvl+0.5, Smite / Bane of Arthropods 2.5*lvl against their mob groups,
## Impaling 2.5*lvl against aquatic mobs.
const UNDEAD := ["zombie", "husk", "drowned", "zombie_villager", "skeleton", "stray", "bogged", "wither_skeleton", "wither", "phantom", "zombified_piglin", "zoglin", "skeleton_horse", "zombie_horse", "parched", "zombie_nautilus"]
const ARTHROPODS := ["spider", "cave_spider", "bee", "silverfish", "endermite"]
const AQUATIC := ["cod", "salmon", "pufferfish", "tropical_fish", "squid", "glow_squid", "dolphin", "guardian", "elder_guardian", "turtle", "axolotl", "tadpole", "drowned", "nautilus"]


func _ench_damage(held: ItemStack, e: Ent) -> float:
	if held.is_empty():
		return 0.0
	var b := 0.0
	var sh := Loot._ench(held, "sharpness")
	if sh > 0:
		b += 0.5 * sh + 0.5
	if e.kind == "mob":
		if e.id in UNDEAD:
			b += 2.5 * Loot._ench(held, "smite")
		if e.id in ARTHROPODS:
			b += 2.5 * Loot._ench(held, "bane_of_arthropods")
		if e.id in AQUATIC:
			b += 2.5 * Loot._ench(held, "impaling")
	return b


## Java LivingEntity.knockback(strength, x, z): halve velocity, push away from (x, z), lift on ground.
func _knockback(e: Ent, strength: float, x: float, z: float) -> void:
	strength *= 1.0 - float(e.def.get("knockback_resistance", 0.0))
	if strength <= 0.0:
		return
	var d := Vector2(x, z)
	if d.length() < 0.0001:
		return
	d = d.normalized() * strength
	e.vel = Vector3(e.vel.x / 2.0 + d.x, minf(0.4, e.vel.y / 2.0 + strength) if e.on_ground else e.vel.y, e.vel.z / 2.0 + d.y)

func player_interact(e: Ent, held: ItemStack) -> void:
	if e != null and not e.dead and (e.kind == "frame" or e.kind == "armor_stand" or e.kind == "cushion"):
		MiscEntities.interact(self, e, world.player, held)
		return
	if e != null and not e.dead and (e.kind == "boat" or e.kind == "minecart"):
		Vehicles.interact(self, e, world.player, held)
		return
	if e == null or e.dead or e.kind != "mob":
		return
	if e.remote:
		Net.forward("interact", [e.uid, held.to_dict()])
		return
	var p: Player = world.player
	if Leads.interact(self, e, p, held):
		world.swing_hand()
		return
	# Java NameTagItem.interactLivingEntity: a renamed name tag names the mob and keeps it from despawning
	if not held.is_empty() and held.name() == "name_tag" and held.components.has("minecraft:custom_name") and e.id != "ender_dragon":
		e.data["CustomName"] = str(held.components["minecraft:custom_name"])
		e.persistent = true
		if not p.is_creative():
			p.inventory.consume_held()
		world.swing_hand()
		world.inv_changed()
		return
	if Taming.interact(self, e, p, held):
		return
	if e.def.get("trader", false) and e.baby_age >= 0 and str(e.data.get("prof", "")) != "nitwit":
		var ts = load("res://scripts/ui/trade_screen.gd").new()
		ts.villager = e
		world.open_screen(ts)
		Audio.play("entity.villager.trade", e.pos, "Neutral")
		return
	var food: Array = e.def.get("food", [])
	if not held.is_empty() and food.has(held.name()) and e.baby_age >= 0 and e.breed_cd <= 0 and e.love <= 0:
		e.love = 600
		if not p.is_creative():
			p.inventory.consume_held()
		return
	if not held.is_empty() and held.name() == "shears" and e.id == "sheep" and not e.sheared:
		e.sheared = true
		spawn_item(e.pos + Vector3(0, 1, 0), ItemStack.named("white_wool", rng.randi_range(1, 3)))
		Audio.play("entity.sheep.shear", e.pos, "Players")
		Interaction.damage_tool(p, 1)
		return
	if not held.is_empty() and held.name() == "bucket" and e.id == "cow":
		Interaction._replace_held(p, "milk_bucket")
		Audio.play("entity.cow.milk", e.pos, "Players")


func raycast(o: Vector3, d: Vector3, max_d: float):
	var best = null
	var bd := max_d
	for e in ents:
		if not (e.kind in ["mob", "boat", "minecart", "frame", "painting", "armor_stand", "cushion"]) or e == world.player.vehicle:
			continue
		var bmin := Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2)
		var bmax := Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2)
		if e.kind == "frame" or e.kind == "painting":
			var na: Array = e.data.get("n", [0, 0, 1])
			var nv := Vector3(na[0], na[1], na[2])
			var c: Vector3 = e.pos + Vector3(0, e.h / 2.0, 0)
			var half := Vector3(e.w / 2.0, e.h / 2.0, e.w / 2.0)
			if absf(nv.x) > 0.5:
				half.x = 0.04
			elif absf(nv.z) > 0.5:
				half.z = 0.04
			else:
				half = Vector3(e.w / 2.0, 0.04, e.w / 2.0)
			bmin = c - half
			bmax = c + half
		var r := VoxelRaycast._ray_box(o, d.normalized(), bmin, bmax)
		if r.x >= 0.0 and r.x < bd:
			bd = r.x
			best = e
	return [best, bd] if best != null else null


## Java BedBlock.useWithoutItem + ServerPlayer.startSleepInBed: beds explode outside natural dimensions; sleep only at
## night (day time 12542..23459) or in thunder, within 3 / 2 blocks, with no monster within 8 x 5 x 8 of the bed;
## the respawn point is set (message when it changes); the player lies down on the head half (InBedChatScreen).
func try_sleep(pos: Vector3i, st: int) -> bool:
	var b := Res.blocks
	var p: Player = world.player
	var head := pos
	var facing := b.get_prop(st, "facing")
	var off: Vector3i = {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}.get(facing, Vector3i.ZERO)
	if b.get_prop(st, "part") == "foot":
		head = pos + off
	if world.dimension != "overworld":
		world.set_block(pos.x, pos.y, pos.z, 0)
		explode(Vector3(head) + Vector3(0.5, 0.5, 0.5), 5.0, true)
		return true
	var dt: int = world.day_time % 24000
	if (dt < 12542 or dt > 23459) and not world.thundering:
		world.hud.set_title(null, null, Res.tr_key("block.minecraft.bed.no_sleep", "You can sleep only at night or during thunderstorms"))
		return true
	var c := Vector3(head) + Vector3(0.5, 0.0, 0.5)
	if absf(p.pos.x - c.x) > 3.5 or absf(p.pos.z - c.z) > 3.5 or absf(p.pos.y - c.y) > 2.5:
		world.hud.set_title(null, null, Res.tr_key("block.minecraft.bed.too_far_away", "You may not rest now; the bed is too far away"))
		return true
	for e in ents:
		if e.kind == "mob" and e.def.get("kind") == "hostile" and absf(e.pos.x - c.x) <= 8.0 and absf(e.pos.z - c.z) <= 8.0 and absf(e.pos.y - c.y) <= 5.0:
			world.hud.set_title(null, null, Res.tr_key("block.minecraft.bed.not_safe", "You may not rest now; there are monsters nearby"))
			return true
	# 26.3 straw bed: a one-night bed - no respawn point, it breaks when you get up (block.straw_bed.break_leave)
	if b.name_of(st) != "straw_bed":
		if not p.has_spawn or p.spawn_point != head:
			world.hud.chat_message(Res.tr_key("block.minecraft.set_spawn", "Respawn point set"))
		p.spawn_point = head
		p.has_spawn = true
	else:
		p.stats["sleep_in_straw_bed"] = int(p.stats.get("sleep_in_straw_bed", 0)) + 1
	# Java LivingEntity.startSleeping / setPosToBed: on the head half, 0.6875 up, still
	p.sleeping = true
	p.sleep_counter = 0
	p.bed_pos = head
	p.bed_facing = facing
	p.pos = Vector3(head) + Vector3(0.5, 0.6875, 0.5)
	p.prev_pos = p.pos
	p.vel = Vector3.ZERO
	var sc = load("res://scripts/ui/in_bed_screen.gd").new()
	sc.world = world
	world.open_screen(sc)
	return true


## Java Player.stopSleepInBed / BedBlock.findStandUpPosition: stand on a free spot beside the bed (else on it).
func wake_up() -> void:
	var p: Player = world.player
	if not p.sleeping:
		return
	p.sleeping = false
	p.sleep_counter = 100
	var hb := p.bed_pos
	var bst: int = world.state_at(hb.x, hb.y, hb.z)
	if bst > 0 and Res.blocks.name_of(bst) == "straw_bed":
		# the straw bed falls apart as you leave it (with its other half)
		var parts: Array = [hb]
		var bf := Res.blocks.get_prop(bst, "facing")
		var bo: Vector3i = {"north": Vector3i(0, 0, -1), "south": Vector3i(0, 0, 1), "west": Vector3i(-1, 0, 0), "east": Vector3i(1, 0, 0)}.get(bf, Vector3i.ZERO)
		for q in [hb + bo, hb - bo]:
			var qs: int = world.state_at(q.x, q.y, q.z)
			if qs > 0 and Res.blocks.name_of(qs) == "straw_bed":
				parts.append(q)
		for q2 in parts:
			Particles.terrain(q2, world.state_at(q2.x, q2.y, q2.z))
			world.set_block(q2.x, q2.y, q2.z, 0)
		Audio.play("block.straw_bed.break_leave", Vector3(hb) + Vector3(0.5, 0.5, 0.5), "Blocks")
	var stand := Vector3(hb) + Vector3(0.5, 0.5625, 0.5)
	for d in [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1), Vector3i(1, 0, 1), Vector3i(-1, 0, -1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1)]:
		var q: Vector3i = hb + d
		var b0: int = world.state_at(q.x, q.y, q.z)
		var b1: int = world.state_at(q.x, q.y + 1, q.z)
		var bb: int = world.state_at(q.x, q.y - 1, q.z)
		if b0 >= 0 and b1 >= 0 and bb > 0 and not Res.blocks.collides(b0) and not Res.blocks.collides(b1) and Res.blocks.collides(bb):
			stand = Vector3(q) + Vector3(0.5, 0.0, 0.5)
			break
	p.pos = stand
	p.prev_pos = stand
	if world.screen != null and world.screen.get_script() != null and str(world.screen.get_script().resource_path).ends_with("in_bed_screen.gd"):
		world.close_screen()


## Lightning bolt (Java LightningBolt): flash column, thunder, 5 damage within 3 blocks, fire on the ground block.
func lightning(at: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.3, 128.0, 0.3)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.85, 0.9, 1.0)
	mi.material_override = mat
	mi.position = world.vis(at + Vector3(0, 64, 0))
	add_child(mi)
	get_tree().create_timer(0.35).timeout.connect(mi.queue_free)
	Audio.play("entity.lightning_bolt.thunder", at, "Weather", 1.0)
	Audio.play("entity.lightning_bolt.impact", at, "Weather", 0.8)
	for e in ents.duplicate():
		if e.kind == "mob" and e.pos.distance_to(at) < 3.0:
			e.fire = maxi(e.fire, 160)
			_damage(e, 5.0, null)
	if world.player.pos.distance_to(at) < 3.0:
		world.player.hurt(5.0, "lightning_bolt")
		world.player.fire_ticks = maxi(world.player.fire_ticks, 160)
	var g := Vector3i(at.floor())
	if world.gamerule("doFireTick", true) and world.state_at(g.x, g.y, g.z) == 0 and world.state_at(g.x, g.y - 1, g.z) > 0:
		world.set_block(g.x, g.y, g.z, Res.blocks.default_state("fire"))


func spawn_hearts(at: Vector3) -> void:
	if Particles.instance != null:
		for i in 7:
			Particles.emit("heart", at + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.2, 0.3), rng.randf_range(-0.5, 0.5)), Vector3(rng.randf_range(-0.02, 0.02), 0.1, rng.randf_range(-0.02, 0.02)))
		return
	var part := CPUParticles3D.new()
	part.one_shot = true
	part.amount = 7
	part.lifetime = 1.0
	part.explosiveness = 0.9
	part.direction = Vector3(0, 1, 0)
	part.spread = 40.0
	part.initial_velocity_min = 0.6
	part.initial_velocity_max = 1.2
	part.gravity = Vector3.ZERO
	var qm := QuadMesh.new()
	qm.size = Vector2(0.2, 0.2)
	part.mesh = qm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var tex := UiKit.sprite("particle/heart")
	if tex == null:
		tex = ItemIcons.icon(Res.items.id("red_dye"))
	mat.albedo_texture = tex
	mat.albedo_color = Color(1, 0.3, 0.35) if tex == null else Color.WHITE
	part.material_override = mat
	part.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	part.emission_sphere_radius = 0.5
	part.position = world.vis(at)
	add_child(part)
	part.emitting = true
	get_tree().create_timer(1.5).timeout.connect(part.queue_free)


func sit_on(pos: Vector3i) -> bool:
	world.player.pos = Vector3(pos) + Vector3(0.5, 0.2, 0.5)
	world.player.prev_pos = world.player.pos
	return true


# ------------------------------------------------------------------ natural spawning

func _biome_spawns(bio: int, category: String) -> Array:
	var d = world.biomes.data[bio]
	if not (d is Dictionary):
		return []
	var attrs = d.get("attributes", {})
	var ns = attrs.get("minecraft:gameplay/natural_mob_spawns", null) if attrs is Dictionary else null
	var by_cat = null
	if ns is Dictionary:
		var arg = ns.get("argument", ns)
		if arg is Dictionary:
			by_cat = arg.get("spawns_by_category", null)
	if by_cat == null:
		var sp = d.get("spawners", {})
		by_cat = sp if sp is Dictionary else {}
	var lst = by_cat.get(category, [])
	return lst if lst is Array else []


func _natural_spawn(p: Player) -> void:
	if not world.gamerule("doMobSpawning", true) or p.dead:
		return
	var hostiles := 0
	var passives := 0
	for e in ents:
		if e.kind == "mob":
			if e.def.get("kind") == "hostile":
				hostiles += 1
			else:
				passives += 1
	var sim := int(Settings.get_v("simulation_distance")) * 16
	var dt: Dictionary = world.dim_type
	spawn_cycle += 1
	for attempt in 4:
		var a := rng.randf() * TAU
		var r := rng.randf_range(24.0, float(sim))
		var x := int(floor(p.pos.x + cos(a) * r))
		var z := int(floor(p.pos.z + sin(a) * r))
		var c: Chunk = world.cm.get_chunk(x >> 4, z >> 4)
		if c == null or not c.light_valid:
			continue
		var y := rng.randi_range(maxi(Coords.MIN_Y, world.gen.gen_min_y) + 1, c.heightmap[(x & 15) + (z & 15) * 16] + 1)
		var below: int = world.state_at(x, y - 1, z)
		var at: int = world.state_at(x, y, z)
		var above: int = world.state_at(x, y + 1, z)
		var bio := c.biome_at(x & 15, y, z & 15)
		var light: int = world.cm.get_light(x, y, z)
		var sky := int((light >> 4) * world.sky_darken()) if world.dimension == "overworld" else 0
		var blk := light & 15
		# Java Monster.isDarkEnoughToSpawn: sky <= rand(32), block <= dimension limit, raw light <= dimension test
		var blk_limit := int(dt.get("monster_spawn_block_light_limit", 0))
		var lvl_test = dt.get("monster_spawn_light_level", 7)
		var lvl := rng.randi_range(int(lvl_test.get("min_inclusive", 0)), int(lvl_test.get("max_inclusive", 7))) if lvl_test is Dictionary else int(lvl_test)
		var is_dark := sky <= rng.randi_range(0, 31) and blk <= blk_limit and maxi(sky, blk) <= lvl
		var category: String = ["monster", "creature", "monster", "water_ambient", "monster", "water_creature", "ambient", "creature"][(spawn_cycle + attempt) % 8]
		if category == "monster" and (not is_dark or hostiles >= HOSTILE_CAP or world.difficulty == 0):
			continue
		if category != "monster" and passives >= PASSIVE_CAP * 3:
			continue
		var lst := _biome_spawns(bio, category)
		if lst.is_empty():
			lst = [{"type": "zombie", "weight": 100}, {"type": "skeleton", "weight": 100}, {"type": "creeper", "weight": 100}, {"type": "spider", "weight": 100}] if category == "monster" else [{"type": "pig", "weight": 10}, {"type": "cow", "weight": 8}, {"type": "sheep", "weight": 12}, {"type": "chicken", "weight": 10}]
		var total := 0
		var cands: Array = []
		for s in lst:
			var t := str(s.get("type", "")).trim_prefix("minecraft:")
			if MobRegistry.has_def(t) and _placement_ok(t, category, x, y, z, below, at, above, light):
				cands.append(s)
				total += int(s.get("weight", 1))
		if total <= 0:
			continue
		var pick := rng.randi_range(0, total - 1)
		for s in cands:
			pick -= int(s.get("weight", 1))
			if pick < 0:
				var cnt = s.get("count", 1)
				var n := 1
				if cnt is Dictionary:
					n = rng.randi_range(int(cnt.get("min_inclusive", 1)), int(cnt.get("max_inclusive", 1)))
				elif cnt is int or cnt is float:
					n = int(cnt)
				else:
					n = rng.randi_range(int(s.get("minCount", 1)), int(s.get("maxCount", 4)))
				for k in mini(n, 4):
					var px := x + rng.randi_range(-2, 2)
					var pz := z + rng.randi_range(-2, 2)
					var lava_mob := str(MobRegistry.get_def(str(s["type"]).trim_prefix("minecraft:")).get("spawn", "")) == "in_lava"
					var at2: int = world.state_at(px, y, pz)
					if (lava_mob and at2 > 0 and (Res.blocks.st_flags[at2] & BlockRegistry.F_LAVA) != 0) or (not lava_mob and at2 == 0 and world.state_at(px, y - 1, pz) > 0):
						spawn_mob(str(s["type"]).trim_prefix("minecraft:"), Vector3(px + 0.5, y, pz + 0.5))
				break


## Spawn placement (Java SpawnPlacements): on_ground (solid below, free feet/head), in_lava (striders),
## animals on grass with light >= 9 (overworld), plus mob-specific chances (ghast 1/20).
func _placement_ok(id: String, category: String, x: int, y: int, z: int, below: int, at: int, above: int, light: int) -> bool:
	var d := MobRegistry.get_def(id)
	var fl := Res.blocks.st_flags
	var aquatic := category.begins_with("water") or category == "underground_water_creature" or category == "axolotls"
	if aquatic != (str(d.get("spawn", "")) == "in_water"):
		return false
	match str(d.get("spawn", "on_ground")):
		"in_lava":
			if at <= 0 or (fl[at] & BlockRegistry.F_LAVA) == 0:
				return false
		"in_water":
			if at <= 0 or above <= 0 or (fl[at] & BlockRegistry.F_LIQUID) == 0 or (fl[at] & BlockRegistry.F_LAVA) != 0 or (fl[above] & BlockRegistry.F_LIQUID) == 0:
				return false
		_:
			if below <= 0 or (fl[below] & BlockRegistry.F_FULL_SHAPE) == 0 or at != 0 or above != 0:
				return false
			if category == "creature" and world.dimension == "overworld" and (Res.blocks.name_of(below) != "grass_block" or (light >> 4) < 9 or rng.randi_range(0, 9) != 0):
				return false
	if d.has("spawn_chance") and rng.randf() >= float(d["spawn_chance"]):
		return false
	if float(d.get("w", 0.6)) > 1.5:
		var r := int(ceil(float(d["w"]) / 2.0))
		for dy in int(ceil(float(d["h"]))):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if world.state_at(x + dx, y + dy, z + dz) != 0:
						return false
	return true


# ------------------------------------------------------------------ persistence & rendering

func store_chunk_entities(c: Chunk) -> void:
	var out: Array = []
	for e in ents:
		if (int(floor(e.pos.x)) >> 4) == c.cx and (int(floor(e.pos.z)) >> 4) == c.cz:
			var d := _ser(e)
			if not d.is_empty():
				out.append(d)
	for it in _deser_q:   # not yet created (spread over frames): still the chunk's entities
		if it[0] == c:
			out.append(it[1])
	c.saved_entities = out


## Remove every entity (after unload_all stored them into their chunks).
func clear_all() -> void:
	_deser_q.clear()
	for e in ents.duplicate():
		_remove(e)


func on_chunk_unloading(c: Chunk) -> void:
	store_chunk_entities(c)
	if not _deser_q.is_empty():
		_deser_q = _deser_q.filter(func(it): return it[0] != c)
	if not c.saved_entities.is_empty():
		c.modified = true
	for e in ents.duplicate():
		if (int(floor(e.pos.x)) >> 4) == c.cx and (int(floor(e.pos.z)) >> 4) == c.cz:
			_remove(e)


## Entities stored in a chunk (saved ones, or the animals of fresh world generation) are created a few per frame
## (_drain_deser, ~0.6 ms budget): building mob nodes for a whole chunk in its commit frame stalled 20-30 ms.
var _deser_q: Array = []   # [Chunk, serialized entity]
var _unimplemented_warned: Dictionary = {}


func on_chunk_loaded(c: Chunk) -> void:
	for d in c.saved_entities:
		_deser_q.append([c, d])
	c.saved_entities = []


func _drain_deser() -> void:
	var t := Time.get_ticks_usec()
	var n := 0
	while not _deser_q.is_empty() and (n == 0 or Time.get_ticks_usec() - t < 600):
		var it: Array = _deser_q.pop_front()
		n += 1
		var ch: Chunk = it[0]
		if ch.state == Chunk.EVICTED:
			continue
		var tracing: bool = world.cm.tracing
		var cd: int = Native.inst.thread_cycles()[0] if tracing else 0
		var td := Time.get_ticks_usec()
		_deser(it[1])
		if tracing:
			var dd := Time.get_ticks_usec() - td
			if dd > 2000:
				world.frame_tparts["deser:" + str((it[1] as Dictionary).get("id", "?"))] = [dd, "Mcyc", (Native.inst.thread_cycles()[0] - cd) / 1000000.0]


func _ser(e: Ent) -> Dictionary:
	match e.kind:
		"item":
			return {"k": "item", "p": [e.pos.x, e.pos.y, e.pos.z], "s": e.stack.to_dict(), "a": e.age}
		"boat", "minecart":
			return {"k": e.kind, "id": e.id, "p": [e.pos.x, e.pos.y, e.pos.z], "y": e.yaw, "d": e.data}
		"frame", "painting", "armor_stand", "cushion":
			return MiscEntities.ser(e)
		"mob":
			if e.def.get("kind") == "hostile" and not e.persistent:
				return {}
			return {"k": "mob", "id": e.id, "p": [e.pos.x, e.pos.y, e.pos.z], "hp": e.hp, "y": e.yaw, "b": e.baby_age, "sh": e.sheared, "d": e.data}
	return {}


func _deser(d: Dictionary) -> void:
	var p: Array = d.get("p", [0, 0, 0])
	var pos := Vector3(p[0], p[1], p[2])
	match str(d.get("k", "")):
		"boat", "minecart":
			var vv = Vehicles.spawn(self, str(d["k"]), str(d.get("id", "oak_boat")), pos, float(d.get("y", 0.0)))
			if d.get("d") is Dictionary and not (d["d"] as Dictionary).is_empty():
				vv.data = d["d"]
		"frame", "painting", "armor_stand", "cushion":
			MiscEntities.deser(self, d)
		"item":
			var e := spawn_item(pos, ItemStack.from_dict(d.get("s", {})))
			if e != null:
				e.age = int(d.get("a", 0))
				e.vel = Vector3.ZERO
		"mob":
			var m := spawn_mob(str(d.get("id", "")), pos, int(d.get("b", 0)) < 0)
			if m != null:
				m.hp = float(d.get("hp", m.hp))
				m.yaw = float(d.get("y", 0))
				m.baby_age = int(d.get("b", 0))
				m.sheared = bool(d.get("sh", false))
				if d.get("d") is Dictionary and not (d["d"] as Dictionary).is_empty():
					m.data = d["d"]


func on_block_changed(_p: Vector3i, _old: int, _new: int) -> void:
	pass


func spawn_block_particles(p: Vector3i, st: int) -> void:
	if Settings.get_v("particles") == "minimal":
		return
	if Particles.instance != null:
		Particles.terrain(p, st)   # Java TerrainParticle billboards (one MultiMesh); the node below is the fallback
		return
	var part := CPUParticles3D.new()
	part.one_shot = true
	part.amount = 16 if Settings.get_v("particles") == "all" else 6
	part.lifetime = 0.8
	part.explosiveness = 1.0
	part.direction = Vector3(0, 1, 0)
	part.spread = 90.0
	part.initial_velocity_min = 1.0
	part.initial_velocity_max = 2.5
	part.gravity = Vector3(0, -9.8, 0)
	part.scale_amount_min = 0.06
	part.scale_amount_max = 0.12
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE
	part.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ItemIcons.average_color(st)
	part.material_override = mat
	part.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	part.emission_box_extents = Vector3(0.4, 0.4, 0.4)
	part.position = world.vis(Vector3(p) + Vector3(0.5, 0.5, 0.5))
	add_child(part)
	part.emitting = true
	get_tree().create_timer(1.2).timeout.connect(part.queue_free)


func _process(_delta: float) -> void:
	if world == null or world.cm == null:
		return
	if not _deser_q.is_empty():
		_drain_deser()
	# entities tick in their own phase of the game tick (WorldManager._tick_step): interpolate from that moment
	var now_us := Time.get_ticks_usec()
	var alpha := clampf((now_us - last_tick_us) / 50000.0, 0.0, 1.0)
	Leads.render(self)
	_animate_pickups()
	var cam_pos: Vector3 = world.player.pos
	var max_d := 64.0 * float(Settings.get_v("entity_distance")) / 100.0
	for e in ents:
		if e.node == null:
			continue
		var ea := alpha if e.tick_us == 0 else clampf((now_us - e.tick_us) / 50000.0, 0.0, 1.0)
		var ip: Vector3 = e.prev.lerp(e.pos, ea)
		e.node.visible = ip.distance_to(cam_pos) < max_d
		if not e.node.visible:
			continue
		e.node.position = world.vis(ip)
		var l := _light_at(ip + Vector3(0, 0.2, 0))
		if e.kind == "mob" and e.data.has("CustomName"):
			_nameplate(e)
		match e.kind:
			"projectile":
				# long projectiles point along their flight (stuck arrows keep the last direction)
				if e.id == "arrow" and not e.rt.has("arrow_tex"):
					# Java TippedArrowRenderer / SpectralArrowRenderer textures (the ammo is set after the spawn)
					e.rt["arrow_tex"] = true
					var am := str(e.data.get("ammo", ""))
					if am == "spectral_arrow" or am == "tipped_arrow":
						for c0 in e.node.get_children():
							c0.queue_free()
						e.node.add_child(projectile_rig("arrow", "entity/projectiles/arrow_spectral" if am == "spectral_arrow" else "entity/projectiles/arrow_tipped"))
				if (e.id == "arrow" or e.id == "trident") and e.vel.length() > 0.01 and not e.data.get("ground", false):
					var fwd: Vector3 = e.vel.normalized()
					var up := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.RIGHT
					e.node.basis = Basis.looking_at(fwd, up)
			"bobber":
				MiscEntities.draw_line(self, e)
			"tnt":
				# Java TntRenderer: swells by f^4 * 0.3 in the last 10 ticks, flashes white every other 5 ticks
				var tf := clampf(1.0 - (float(e.fuse) - ea + 1.0) / 10.0, 0.0, 1.0)
				tf *= tf
				tf *= tf
				e.node.scale = Vector3.ONE * (1.0 + tf * 0.3)
				var fl_n: Node3D = e.node.get_node_or_null("flash")
				if fl_n != null:
					fl_n.visible = (e.fuse / 5) % 2 == 0
			"frame":
				e.node.position.y += 0.375
				MiscEntities.light_tint(self, e)
			"painting":
				MiscEntities.light_tint(self, e)
			"cushion":
				e.node.rotation.y = deg_to_rad(180.0 - e.yaw)
				for mi in _meshes(e.node):
					mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			"armor_stand":
				ArmorRender.apply(e.node, ArmorRender.slots_of_dicts(e.data.get("armor", [])))
				e.node.rotation.y = deg_to_rad(180.0 - e.yaw)
				for mi in _meshes(e.node):
					mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			"boat", "minecart":
				e.node.rotation.y = deg_to_rad(180.0 - e.yaw)
				e.node.rotation.z = sin(e.hurt_time * 0.6) * 0.1 if e.hurt_time > 0 else 0.0
				for mi in _meshes(e.node):
					mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			"item":
				if e.age % 10 == 0 or not e.node.has_meta("lit"):
					e.node.set_meta("lit", true)
					for mi in _meshes(e.node):
						mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
				# Java ItemEntityRenderer: bob sin((age + pt) / 10 + bobOffs) * 0.1 + 0.1 (+ 0.25 * ground scale y),
				# spin (age + pt) / 20 + bobOffs radians
				var bo: float = e.node.get_meta("bob", 0.0)
				e.node.rotation.y = (e.age + ea) / 20.0 + bo
				e.node.position.y += sin((e.age + ea) / 10.0 + bo) * 0.1 + 0.1 + 0.25 * float(e.node.get_meta("gsy", 0.0))
			"mob":
				if e.data.has("armor"):
					ArmorRender.apply(e.node, e.data["armor"])
				if e.def.get("illager", false):
					# Java IllagerModel: CROSSED arm pose (vindicator / evoker / illusioner while not attacking) shows the
					# folded arms and hides the separate ones; pillagers never fold theirs
					var crossed: bool = e.id != "pillager" and not e.target_player
					if bool(e.rt.get("crossed", not crossed)) != crossed:
						e.rt["crossed"] = crossed
						var mdl: Node = e.node.get_node_or_null("model")
						if mdl != null:
							for an in [["arms", crossed], ["arm0", not crossed], ["arm1", not crossed]]:
								var anode := mdl.get_node_or_null(str(an[0])) as Node3D
								if anode != null:
									anode.visible = bool(an[1])
				if e.data.has("held") or e.data.has("offhand"):
					# Java ItemInHandLayer (VindicatorRenderer: the axe only while aggressive)
					var show_main: bool = e.id != "vindicator" or e.target_player
					var hk := "%s|%s|%s" % [e.data.get("held", ""), e.data.get("offhand", ""), show_main]
					if str(e.rt.get("hk", "")) != hk:
						e.rt["hk"] = hk
						HeldItems.update(e.node, ItemStack.named(str(e.data["held"]), 1) if show_main and e.data.has("held") else ItemStack.new(),
							ItemStack.named(str(e.data["offhand"]), 1) if e.data.has("offhand") else ItemStack.new())
				if e.id in Taming.NEEDS_TAMING and (e.data.has("saddle") or e.data.has("horse_armor")):
					var ha = e.data.get("horse_armor", {})
					ArmorRender.apply_horse(e.node, e.def.get("parts", []), ItemStack.from_dict(ha).name() if ha is Dictionary and not ha.is_empty() else "", bool(e.data.get("saddle", false)))
				# Java LivingEntityRenderer: rotY(180 - bodyYaw) after the model's (-1,-1,1) flip. Body yaw, head yaw /
				# pitch and the walk animation are interpolated between ticks (rotLerp(partialTick, yBodyRotO, yBodyRot),
				# WalkAnimationState.position(partialTick) / speed(partialTick)), so turning and walking stay smooth at
				# any frame rate.
				var by: float = e.body_yaw_o + MobControl.wrap_deg(e.body_yaw - e.body_yaw_o) * ea
				e.node.rotation.y = deg_to_rad(180.0 - by)
				# Java LivingEntityRenderer.setupRotations: dying bodies tip over sideways, sqrt(t / 20 * 1.6) x 90 degrees
				e.node.rotation.z = deg_to_rad(sqrt(clampf((e.death_time + ea - 1.0) / 20.0 * 1.6, 0.0, 1.0)) * 90.0) if e.death_time > 0 else 0.0
				var model: Node = e.node.get_node_or_null("model")
				if model != null:
					# Java Creaking tearing down: the whole body twitches
					(model as Node3D).rotation = Vector3(randf_range(-0.08, 0.08), randf_range(-0.15, 0.15), randf_range(-0.08, 0.08)) if e.data.has("tear") else Vector3.ZERO
					var amt: float = 0.0 if e.dead or e.death_time > 0 else minf(lerpf(e.limb_amt_o, e.limb_amt, ea), 1.0)
					var lpos: float = e.limb - e.limb_amt * (1.0 - ea)
					var sw: float = cos(lpos * 0.6662) * 1.4 * amt
					var age_t: float = e.age + ea
					var hyaw := 0.0
					var hpitch := 0.0
					if not (e.def.get("flies", false) or e.def.get("hops", false) or e.def.get("stationary", false) or e.def.get("swims", false) or e.def.get("dragon", false)):
						var hy: float = e.head_yaw_o + MobControl.wrap_deg(e.head_yaw - e.head_yaw_o) * ea
						hyaw = clampf(MobControl.wrap_deg(hy - by), -85.0, 85.0)
						hpitch = lerpf(e.head_pitch_o, e.head_pitch, ea)
					for c in model.get_children():
						var nm: String = c.name
						if nm == "head":
							# Java model setupAnim: head.yRot = netHeadYaw, head.xRot = headPitch (attachments are children)
							var r0: Vector3 = c.get_meta("r0", Vector3.ZERO)
							c.rotation = r0 + Vector3(-deg_to_rad(hpitch), -deg_to_rad(hyaw), 0.0)
						elif nm.begins_with("leg"):
							var idx := int(nm.substr(3))
							if e.id in ["spider", "cave_spider"]:
								c.rotation.y = sin(lpos * 0.6662 + idx * 0.8) * 0.4 * amt
							elif e.id == "iron_golem":
								c.rotation.x = 1.5 * _triangle_wave(lpos, 13.0) * amt * (1.0 if idx == 0 else -1.0)
							else:
								c.rotation.x = -sw * (1.0 if idx % 2 == 0 else -1.0) * (1.0 if idx < 2 else -1.0)
						elif nm == "arm0" or nm == "arm1":
							_arm_pose(e, c, nm == "arm0", lpos, amt, age_t, hyaw, hpitch)
						elif nm.begins_with("wing") and not e.def.get("dragon", false):
							c.rotation.z = sin(age_t * 0.6) * 0.5 if not e.on_ground else 0.0

						elif nm.begins_with("tent"):
							c.rotation.x = 0.2 * sin((e.age + alpha) * 0.3 + int(nm.substr(4))) + 0.4
						elif nm.begins_with("rod") and e.id == "blaze":
							# Java BlazeModel.setupAnim: three rings of 4 rods orbiting at different heights/radii
							var ring := nm.unicode_at(3) - 65
							var ri := int(nm.substr(4))
							var t: float = (e.age + alpha) * PI * float([-0.1, 0.05, -0.0125][ring])
							var ang: float = t + ri * PI / 2.0 + float([0.0, PI / 4.0, 0.47123894][ring])
							var rad: float = float([9.0, 7.0, 5.0][ring])
							var yy: float = float([-2.0, 2.0, 11.0][ring]) + cos((e.age + alpha) * 0.25 + ri)
							c.position = Vector3(-cos(ang) * rad, -yy, sin(ang) * rad) / 16.0
						elif nm == "glass" or nm == "cube":
							c.rotation = Vector3((e.age + alpha) * (0.05 if nm == "glass" else -0.07), (e.age + alpha) * 0.06, 0.7)
							c.position.y = (-4.0 / 16.0) + sin((e.age + alpha) * 0.1) * 0.2 + 0.4
						elif nm == "lid":
							c.position.y = (-24.0 / 16.0) + (0.5 if e.target_player else 0.0) * 0.4
					if e.def.get("dragon", false):
						_dragon_pose(e, model, ea)
					for mi in _meshes(model):
						mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
						mi.set_instance_shader_parameter("hurt", 1.0 if e.hurt_time > 0 or e.death_time > 0 or (e.fuse >= 0 and (e.fuse / 4) % 2 == 0) else 0.0)
				if e.fuse >= 0:
					e.node.scale = Vector3.ONE * (1.0 + e.fuse / 30.0 * 0.2)


## Java EnderDragonModel.setupAnim wings / jaw from the interpolated flap time (Java model space; x / y negated here).
func _dragon_pose(e: Ent, model: Node, ea: float) -> void:
	var f8: float = lerpf(float(e.rt.get("flap_o", 0.0)), float(e.rt.get("flap", 0.0)), ea) * TAU
	for side in [["wing0", "wing4", 1.0], ["wing2", "wing5", -1.0]]:
		var w: Node3D = model.find_child(side[0], true, false)
		var tip: Node3D = model.find_child(side[1], true, false)
		var sg: float = side[2]
		if w != null:
			w.rotation_order = EULER_ORDER_ZYX
			w.rotation = Vector3(-(0.125 - cos(f8) * 0.2), 0.25 * sg, -(sin(f8) + 0.125) * 0.8 * sg)
		if tip != null:
			tip.rotation = Vector3(0, 0, (sin(f8 + 2.0) + 0.5) * 0.75 * sg)
	var jaw: Node3D = model.find_child("jaw", true, false)
	if jaw != null:
		jaw.rotation.x = -(sin(f8) + 1.0) * 0.2


## Java Mth.triangleWave
static func _triangle_wave(f: float, period: float) -> float:
	return (absf(fmod(f, period) - period * 0.5) - period * 0.25) / (period * 0.25)


## Arm poses (Java model setupAnim; values in Java's model space, flipped to ours: x / y negated, z kept):
## zombies hold their arms out (AnimationUtils.animateZombieArms, raised higher when aggressive), skeletons aim
## their bow with the head (ArmPose.BOW_AND_ARROW), iron golems swing on a triangle wave, others swing opposite
## to the legs (HumanoidModel); humanoid arms also bob gently (AnimationUtils.bobModelPart).
func _arm_pose(e: Ent, c: Node3D, right: bool, lpos: float, amt: float, age_t: float, hyaw: float, hpitch: float) -> void:
	if not c.has_meta("r0"):
		c.set_meta("r0", c.rotation)
		c.rotation_order = EULER_ORDER_ZYX   # Java ModelPart: rotationZYX
	var r0: Vector3 = c.get_meta("r0")
	var rig := str(e.def.get("rig", ""))
	var ax := 0.0
	var ay := 0.0
	var az := 0.0
	var bob := true
	if e.id == "iron_golem":
		ax = (-0.2 + 1.5 * _triangle_wave(lpos, 13.0) * (1.0 if right else -1.0)) * amt
		bob = false
	elif rig == "humanoid" or e.id == "zombie_villager":
		ax = -PI / (1.5 if e.target_player else 2.25)
		ay = -0.1 if right else 0.1
	elif rig == "skeleton" and e.target_player and e.def.get("ranged", false):
		ay = (-0.1 if right else 0.5) + deg_to_rad(hyaw)
		ax = -PI / 2.0 + deg_to_rad(hpitch)
	else:
		ax = cos(lpos * 0.6662 + (PI if right else 0.0)) * amt
	if bob:
		var bz := cos(age_t * 0.09) * 0.05 + 0.05
		var bx := sin(age_t * 0.067) * 0.05
		az += bz if right else -bz
		ax += bx if right else -bx
	c.rotation = r0 + Vector3(-ax, -ay, az)


func _meshes(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out
