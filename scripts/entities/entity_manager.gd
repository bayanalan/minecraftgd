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
	var glow := GlowOutline.new()   # (idle until an entity glows)
	glow.name = "GlowOutline"
	glow.world = world
	add_child(glow)
	ExplorerMaps.world = world   # (cartographer explorer maps search on workers)
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
	e.hp = 5.0   # wiki: Item (entity) - starts at 5 HP (explosions / fire / cacti destroy it)
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
	var glint_mat: ShaderMaterial = null
	if pb > 0 and not Res.items.model_ref[s.item].begins_with("item/"):
		mesh = EntityRenderer.item_block_mesh(s.item)   # (the item's model: wall / fence / shelf inventory models)
		off = Vector3(0, -0.5, 0)
	if mesh == null:
		var ref := ItemRegistry.ctx_model(s.name(), "ground") if Res.mode == "vanilla" else ""
		if ref == "":
			ref = Res.items.model_ref[s.item]
		var em: Array = ItemIcons.extruded_model(ref)
		if em.size() == 2:
			mesh = em[0]
			if Glint.has_glint(s):
				glint_mat = Glint.material_3d(em[1], s)
			mat = EntityRenderer.flat_item_material(em[1])   # (translucent sprites blend: stained glass panes)
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
		if glint_mat != null:
			var gmi := MeshInstance3D.new()
			gmi.mesh = mesh
			gmi.material_override = glint_mat
			gmi.transform = mi.transform
			root.add_child(gmi)
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
		# wiki: Experience orb - orbs are built from the base values 1, 3, 7, 17, 37, 73, 149, 307, 617, 1237, 2477,
		# higher values first (1000 -> 617 + 307 + 73 + 3)
		var v := 1
		for b in [2477, 1237, 617, 307, 149, 73, 37, 17, 7, 3]:
			if amount >= b:
				v = b
				break
		amount -= v
		var e := Ent.new()
		e.kind = "xp"
		e.pos = p
		e.prev = p
		e.xp = v
		e.w = 0.5   # wiki: Hitbox - experience orb 0.5 x 0.5 (Java), 5 HP
		e.h = 0.5
		e.hp = 5.0
		e.vel =Vector3(rng.randf_range(-0.1, 0.1), 0.2, rng.randf_range(-0.1, 0.1))
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
	e.data["y0"] = e.pos.y   # fall start (anvil damage / degrading on landing)
	# drawn only once the terrain mesh without the block is on screen (both at once z-fought: GH#15)
	if world != null and world.cm != null:
		e.data["show_at"] = [p.x, p.y, p.z, world.cm.block_epoch]
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
	e.rt["from"] = p   # (launch point: wiki Warden ignores projectiles shot from more than 30 blocks away)
	# Java ThrownItemRenderer: thrown items (and fireballs as fire charges) are their item's ground model facing the
	# camera - half a block for 16 px sprites (small fireball 0.75x, ghast fireball 3x)
	var thrown := {"snowball": "snowball", "egg": "egg", "blue_egg": "blue_egg", "brown_egg": "brown_egg", "ender_pearl": "ender_pearl",
		"experience_bottle": "experience_bottle", "splash_potion": "splash_potion", "lingering_potion": "lingering_potion",
		"eye_of_ender": "ender_eye", "small_fireball": "fire_charge", "fireball": "fire_charge", "firework_rocket": "firework_rocket"}
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
	bm.size = {"arrow": Vector3(0.05, 0.05, 0.5), "trident": Vector3(0.08, 0.08, 1.1), "fireball": Vector3(1.0, 1.0, 1.0), "small_fireball": Vector3(0.3, 0.3, 0.3), "shulker_bullet": Vector3(0.3, 0.3, 0.3), "llama_spit": Vector3(0.25, 0.25, 0.25)}.get(kind, Vector3(0.12, 0.12, 0.12))
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = {"snowball": Color.WHITE, "egg": Color(0.9, 0.85, 0.7), "ender_pearl": Color(0.1, 0.5, 0.4), "arrow": Color(0.5, 0.4, 0.3), "fireball": Color(1.0, 0.45, 0.1), "small_fireball": Color(1.0, 0.6, 0.15), "shulker_bullet": Color(0.95, 0.9, 0.7), "eye_of_ender": Color(0.3, 0.8, 0.5), "experience_bottle": Color(0.55, 0.85, 0.35), "trident": Color(0.35, 0.6, 0.55), "dragon_fireball": Color(0.7, 0.2, 0.9), "wither_skull": Color(0.15, 0.15, 0.15), "llama_spit": Color(0.93, 0.93, 0.88)}.get(kind, Color.GRAY)
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
## Dragon clouds (area effect clouds, MiscEntities.spawn_cloud): kind "dragon" (fireball impact) or "breath" (perch).
func spawn_cloud(at: Vector3, kind: String = "dragon") -> void:
	MiscEntities.spawn_cloud(self, at, "", kind)


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
	# baby hitbox: the def's baby_w / baby_h (wiki Hitbox: baby zombies 0.49 x 0.98, ...), else half the adult's
	e.w = float(def.get("baby_w", float(def["w"]) * 0.5)) if baby else float(def["w"])
	e.h = float(def.get("baby_h", float(def["h"]) * 0.5)) if baby else float(def["h"])
	e.hp = float(def["hp"])
	e.yaw = rng.randf_range(0, 360)
	e.body_yaw = e.yaw
	e.body_yaw_o = e.yaw
	e.head_yaw = e.yaw
	e.head_yaw_o = e.yaw
	e.head_last = e.yaw
	e.baby_age = -24000 if baby else 0
	# animals (creature category) and misc mobs stay; bats, squid, fish, axolotls despawn like monsters (wiki Mob spawning)
	e.persistent = def["kind"] == "passive" and MobAI.spawn_category(world, id) in ["creature", "misc"]
	if def.get("horse_regen", false) and id != "skeleton_horse" and id != "zombie_horse" and not id.begins_with("camel"):
		# Java AbstractHorse.generateMaxHealth (15 + nextInt(8) + nextInt(9)); horses also roll their speed
		# (generateSpeed: (0.45 + 0.3 * (r + r + r)) * 0.25)
		var mh := 15.0 + rng.randi_range(0, 7) + rng.randi_range(0, 8)
		e.data["max_hp"] = mh
		e.hp = mh
		if id == "horse":
			e.data["speed"] = (0.45 + rng.randf() * 0.3 + rng.randf() * 0.3 + rng.randf() * 0.3) * 0.25
	# wiki Attribute: jump_strength random 0.4 - 1.0 for horses, skeleton horses and mules (rolled like the speed: three
	# summed randoms), zombie horses 0.5 - 0.7 with speed 0.2135 - 0.2846 (the wiki gives only the ranges: uniform),
	# llamas / trader llamas / unbred donkeys 0.5
	if id in ["horse", "skeleton_horse", "mule"]:
		e.data["jump"] = 0.4 + rng.randf() * 0.2 + rng.randf() * 0.2 + rng.randf() * 0.2
	elif id == "zombie_horse":
		e.data["jump"] = rng.randf_range(0.5, 0.7)
		e.data["speed"] = rng.randf_range(0.2135, 0.2846)
	elif id in ["llama", "trader_llama", "donkey"]:
		e.data["jump"] = 0.5
	if id == "end_crystal":
		e.rt["t0"] = rng.randi_range(0, 99999)   # Java EndCrystal.time starts at random.nextInt(100000)
	e.node = EntityRenderer.build_rig(def)
	EntityRenderer.group_head(e.node)
	if def.has("children"):
		EntityRenderer.group_children(e.node, def["children"])
	if baby:
		e.node.scale = Vector3.ONE * 0.5
	var vt := "plains"
	if id == "villager" or id == "zombie_villager":
		# the biome type first: trades with a villager/variant merchant_predicate read it (Trading._merchant_ok)
		if world != null and world.cm != null:
			var vch: Chunk = world.cm.get_chunk(floori(p.x) >> 4, floori(p.z) >> 4)
			if vch != null and not vch.biomes.is_empty():
				var vb := vch.biome_at(floori(p.x) & 15, floori(p.y), floori(p.z) & 15)
				if vb >= 0:
					vt = EntityRenderer.villager_type(world.biomes.names[vb])
		e.data["vtype"] = vt
	if def.get("trader", false):
		Trading.assign(e, rng)
	elif id == "zombie_villager":
		Villagers.zombie_profession(e, rng)   # (infected villagers get their own data after the spawn)
	if id == "villager" or id == "zombie_villager":
		# Java VillagerRenderer layers: base + biome type + profession (VillagerProfessionLayer)
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
	if id == "sulfur_cube":
		set_size(e, 2)   # wiki Sulfur Cube: large cubes spawn; small ones come from splitting
	elif def.get("splits", false):
		# Java Slime.finalizeSpawn: size 1 << i, i in 0..2 (bumped with probability by difficulty)
		var i := rng.randi_range(0, 2)
		if i < 2 and rng.randf() < 0.5 * float(world.difficulty) / 3.0:
			i += 1
		set_size(e, 1 << i)
	MobBehaviors.on_spawn(self, e, baby)
	add_child(e.node)
	ents.append(e)
	return e


## wiki Hitbox / Slime / Magma Cube / Sulfur Cube: slimes and magma cubes 0.5202 x 0.52 per size with size^2 health;
## sulfur cubes 0.49 per size (small 1, large 2) with 4 health per size.
func set_size(e: Ent, s: int) -> void:
	e.size = s
	if e.id == "sulfur_cube":
		e.w = 0.49 * s
		e.h = 0.49 * s
		e.hp = 4.0 * s
	else:
		e.w = 0.5202 * s
		e.h = 0.52 * s
		e.hp = float(s * s)
	if e.node != null:
		e.node.scale = Vector3.ONE * float(s)


var _ghosts: Array = []   # [node, block pos, block epoch, ms]: landed falling blocks shown until the terrain mesh has them


func _update_ghosts() -> void:
	var i := 0
	while i < _ghosts.size():
		var g: Array = _ghosts[i]
		var bp: Vector3i = g[1]
		if world.cm.mesh_caught_up(bp.x, bp.y, bp.z, int(g[2])) or Time.get_ticks_msec() - int(g[3]) > 500:
			(g[0] as Node3D).queue_free()
			_ghosts.remove_at(i)
		else:
			(g[0] as Node3D).position = world.vis(Vector3(bp) + Vector3(0.5, 0.0, 0.5))
			i += 1


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


var _pick_mn := Vector3.ZERO   # player pickup box of this entity pass (the player moves at the tick start only)
var _pick_mx := Vector3.ZERO


func tick_begin() -> void:
	var pp: Player = world.player
	if pp != null:
		_pick_mn = pp.aabb_min() - Vector3(1.0, 0.5, 1.0)
		_pick_mx = pp.aabb_max() + Vector3(1.0, 0.5, 1.0)
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
				MiscEntities.tick_cloud(self, e, pp)
			"ominous_item":
				Trials.tick_ominous_item(self, e)


func _tick_rest(p: Player) -> bool:
	if _tick_i < _tick_list.size():
		return false
	_tick_list = []
	MobBehaviors.shoulder_tick(self, p)
	MobBehaviors.cat_spawner(self, p)
	if world.game_time % 24000 == 0:
		for gv in ents:
			if gv.kind == "mob" and gv.id == "villager":
				Trading.gossip_decay(gv)   # wiki Villager: gossip decays every 20 minutes
	_creature_tick(p)
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
		MobBehaviors.cat_gifts(self, p)   # (wiki Cat: morning gifts after a night's sleep)
		# Java ServerLevel: dayTime jumps to the next whole day (the day count, and so the moon phase, keeps going);
		# the weather resets only when it is raining (resetWeatherCycle: timers 0, rain and thunder off)
		if world.gamerule("doDaylightCycle", true):
			var nl: int = int(world.day_time) + 24000
			world.day_time = nl - nl % 24000
		if world.gamerule("doWeatherCycle", true) and world.raining:
			world.raining = false
			world.thundering = false
			world.weather_timer = 0
			world.thunder_timer = 0
			world._thunder_flag = false
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
		"ominous_item":
			if en[9] is Dictionary:
				e = Trials.spawn_ominous_item(self, p, ItemStack.from_dict(en[9]), 1 << 30, false)   # (the host dispenses it)
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


## Java entity type tag minecraft:fall_damage_immune (read from the game data: allay, bat, bee, blaze, chicken, ...)
## plus the flyers whose Java class never takes fall damage (FlyingMob.checkFallDamage: ghast, phantom).
static var _fall_immune_ids: Dictionary = {}
static var _fall_immune_loaded := false


## Java LivingEntity.calculateFallDamage: floor((fall + 1e-6 - safe_fall_distance) x fall_damage_multiplier), wiki
## Damage#Fall damage: horses / donkeys / mules / llamas / camels / skeleton and zombie horses safe 6 blocks at half
## damage, foxes safe 5, goats 10 and frogs 5 less.
const HORSE_FALL := ["horse", "donkey", "mule", "llama", "trader_llama", "camel", "camel_husk", "skeleton_horse", "zombie_horse"]


func _mob_fall_damage(e: Ent) -> float:
	var safe := 3.0
	var mult := 1.0
	var less := 0.0
	if e.id in HORSE_FALL:
		safe = 6.0
		mult = 0.5
	elif e.id == "fox":
		safe = 5.0
	elif e.id == "goat":
		less = 10.0
	elif e.id == "frog":
		less = 5.0
	return maxf(0.0, floorf((e.fall + 1.0e-6 - safe) * mult) - less)


func _fall_immune(e: Ent) -> bool:
	if not _fall_immune_loaded:
		_fall_immune_loaded = true
		for n in Tags.resolve("entity_type", "#minecraft:fall_damage_immune"):
			_fall_immune_ids[str(n).trim_prefix("minecraft:")] = true
		for n2 in ["ghast", "happy_ghast", "phantom", "ender_dragon", "vex"]:
			_fall_immune_ids[n2] = true
	return _fall_immune_ids.has(e.id)


func _physics(e: Ent, gs: Callable, blocks: BlockRegistry, gravity: float, drag: float, step: float = 0.0, ydrag: float = 0.98) -> void:
	var r := Collision.move(Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2), Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2), e.vel, gs, blocks, step, e.on_ground, e.ccache)
	var m: Vector3 = r["motion"]
	e.pos += m
	e.hcollide = r["hit_x"] or r["hit_z"]
	if r["hit_x"]:
		e.vel.x = 0
	if r["hit_z"]:
		e.vel.z = 0
	# Java Entity.checkFallDamage: the downward move counts first (the landing tick too), then the landing
	if m.y < 0:
		e.fall -= m.y
	if r["hit_y"]:
		if e.vel.y < 0 and e.kind == "mob" and e.fall > 0.0 and not _fall_immune(e):
			var fd := _mob_fall_damage(e)
			if fd > 0.0:
				_damage(e, fd, null)
		e.vel.y = 0
	e.on_ground = r["on_ground"]
	if e.on_ground:
		e.fall = 0.0
	e.vel.y -= gravity
	e.vel.y *= ydrag
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
	# wiki: Item (entity) - netherite items are immune to fire and float on top of lava
	var lava_float := false
	if fl == 2:
		var nn := e.stack.name()
		if nn == "ancient_debris" or (nn.begins_with("netherite_") and not nn.ends_with("_smithing_template")):
			fl = 1
			lava_float = true
	# Java ItemEntity.tick: in water / lava setUnderwaterMovement / setUnderLavaMovement (x / z x 0.99 / 0.95, rising
	# 5e-4 per tick while slower than 0.06), otherwise gravity 0.04
	if fl == 1:
		var hk := 0.95 if lava_float else 0.99
		e.vel = Vector3(e.vel.x * hk, e.vel.y + (0.0005 if e.vel.y < 0.06 else 0.0), e.vel.z * hk)
	elif fl == 2:
		# wiki Item (entity): destroyed by lava with the burning sound (volume 0.4, pitch 2.0-2.4)
		Audio.play("entity.generic.burn", e.pos, "Neutral", 0.4, 2.0 + rng.randf() * 0.4)
		_remove(e)
		return
	else:
		e.vel.y -= 0.04
	if not lava_float and _item_hazards(e, gs, blocks):
		return
	# Java: an item lying still on the ground moves (and collides) only every 4th tick ((tickCount + id) % 4)
	if not e.on_ground or e.vel.x * e.vel.x + e.vel.z * e.vel.z > 1e-5 or (e.age + e.get_instance_id()) % 4 == 0:
		_item_move(e, gs, blocks)
	# wiki: Item (entity) - despawns after 6000 ticks, at once below the world bottom - 64
	if e.age >= 6000 or e.pos.y < Coords.MIN_Y - 64:
		_remove(e)
		return
	# merge (wiki: Item (entity) - every 40 ticks, every 2 ticks while crossing block boundaries; the other item within
	# a 0.5 x 0.25 x 0.5 box around it)
	if e.age % 40 == 0 or (e.age % 2 == 0 and Vector3i(e.pos.floor()) != Vector3i(e.prev.floor())):
		for o in _items_near(e):
			if o != e and not o.dead and absf(o.pos.x - e.pos.x) <= 0.5 and absf(o.pos.y - e.pos.y) <= 0.25 and absf(o.pos.z - e.pos.z) <= 0.5 and o.stack.can_merge(e.stack):
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
		# wiki: Item (entity) - the pickup box is the player's hitbox + 1 block to the sides (inclusive) and 0.5 up / down
		# (exclusive), touching the item's 0.25 box
		var pmn := _pick_mn
		var pmx := _pick_mx
		var hw := e.w * 0.5
		if e.pos.x + hw >= pmn.x and e.pos.x - hw <= pmx.x and e.pos.z + hw >= pmn.z and e.pos.z - hw <= pmx.z and e.pos.y + e.h > pmn.y and e.pos.y < pmx.y:
			var left := p.inventory.add(e.stack)
			if left < e.stack.count:
				Audio.play("entity.item.pickup", c, "Players", 0.2, rng.randf_range(1.4, 2.0))
			if left == 0:
				_pickup_fly(e, p)
			else:
				e.stack.count = left


## wiki Item (entity): fire and cacti destroy items (5 HP). Java block contact damage on non-living entities has no
## invulnerability time: fire 1 / soul fire 2 per tick (and 8 s burning: 1 per 20 ticks), cactus 1 per tick. The cells
## the item's box overlaps are rescanned when it changes cell or every 10 ticks. Netherite / ancient debris items are
## fire immune. True when the item was destroyed.
var _haz_ids := PackedInt32Array()   # [fire, soul_fire, cactus] block ids


func _item_hazards(e: Ent, gs: Callable, blocks: BlockRegistry) -> bool:
	if _haz_ids.is_empty():
		_haz_ids = PackedInt32Array([blocks.block_id("fire"), blocks.block_id("soul_fire"), blocks.block_id("cactus")])
	var nn := e.stack.name() if e.stack != null else ""
	var fireproof := nn == "ancient_debris" or (nn.begins_with("netherite_") and not nn.ends_with("_smithing_template"))
	var cell := Vector3i(e.pos.floor())
	var hz: int = e.rt.get("hz", -1)
	if hz < 0 or e.age % 10 == 0 or e.rt.get("hzc", cell) != cell:
		e.rt["hzc"] = cell
		hz = 0
		var hw := e.w * 0.5
		for y in range(floori(e.pos.y), floori(e.pos.y + e.h) + 1):
			for z in range(floori(e.pos.z - hw), floori(e.pos.z + hw) + 1):
				for x in range(floori(e.pos.x - hw), floori(e.pos.x + hw) + 1):
					var s: int = gs.call(x, y, z)
					if s <= 0:
						continue
					var bid := blocks.st_block[s]
					if bid == _haz_ids[0]:
						hz = maxi(hz, 1)
					elif bid == _haz_ids[1]:
						hz = 2
					elif bid == _haz_ids[2]:
						hz |= 4
		e.rt["hz"] = hz
	if hz == 0 and e.fire <= 0:
		return false
	var dmg := 0.0
	if not fireproof:
		if hz & 3:
			dmg += 2.0 if (hz & 3) == 2 else 1.0
			e.fire = maxi(e.fire, 160)
		elif e.fire > 0 and e.fire % 20 == 0:
			dmg += 1.0
	if hz & 4:
		dmg += 1.0
	if e.fire > 0:
		e.fire -= 1
	if dmg <= 0.0:
		return false
	e.hp -= dmg
	if e.hp <= 0.0:
		_remove(e)
		return true
	return false


## Items by block cell, built once per game tick on first use (merge candidates: Java queries the entity section storage
## around the item; scanning every entity for every moving item was quadratic - 1.3 ms for one item tick on x86).
var _igrid := {}
var _igrid_tick := -1


func _items_near(e: Ent) -> Array:
	if _igrid_tick != int(world.game_time):
		_igrid_tick = int(world.game_time)
		_igrid.clear()
		for o in ents:
			if o.kind == "item" and not o.dead:
				var k := Vector3i(o.pos.floor())
				var lst = _igrid.get(k)
				if lst == null:
					_igrid[k] = [o]
				else:
					(lst as Array).append(o)
	var out: Array = []
	var c := Vector3i(e.pos.floor())
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var l2 = _igrid.get(c + Vector3i(dx, dy, dz))
				if l2 != null:
					out.append_array(l2)
	return out


## Java ItemEntity movement: move with collisions (a clipped axis stops; landing or hitting a ceiling zeroes y:
## Block.updateEntityMovementAfterFallOn), then x / z x friction 0.98 in the air or block friction x 0.98 on the ground,
## y x 0.98, and a downward speed on the ground bounces at -0.5.
func _item_move(e: Ent, gs: Callable, blocks: BlockRegistry) -> void:
	var r := Collision.move(Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2), Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2), e.vel, gs, blocks, 0.0, e.on_ground, e.ccache)
	var m: Vector3 = r["motion"]
	e.pos += m
	e.hcollide = r["hit_x"] or r["hit_z"]
	if r["hit_x"]:
		e.vel.x = 0
	if r["hit_z"]:
		e.vel.z = 0
	if r["hit_y"]:
		e.vel.y = 0
	e.on_ground = r["on_ground"]
	var f := 0.98
	if e.on_ground:
		var below: int = gs.call(int(floor(e.pos.x)), int(floor(e.pos.y - 0.5000001)), int(floor(e.pos.z)))
		f = (float(blocks.block_info[blocks.st_block[below]]["friction"]) if below > 0 else 0.6) * 0.98
	e.vel = Vector3(e.vel.x * f, e.vel.y * 0.98, e.vel.z * f)
	if e.on_ground and e.vel.y < 0.0:
		e.vel.y *= -0.5


func _tick_xp(e: Ent, p: Player, gs: Callable, blocks: BlockRegistry) -> void:
	var to := p.pos + Vector3(0, p.eye_height() / 2, 0) - e.pos
	var d := to.length()
	# wiki: Experience orb - drawn toward the player from up to 7.25 blocks (player's feet to the orb's center), faster
	# when closer (the speed-up curve itself is not on the wiki)
	if d < 8.0 and not p.dead and p.pos.distance_to(e.pos + Vector3(0, e.h * 0.5, 0)) <= 7.25:
		var k := 1.0 - d / 8.0
		e.vel += to.normalized() * k * k * 0.1
	_physics(e, gs, blocks, 0.03, 0.98)
	if _in_fluid(e, gs, blocks) == 2:
		_remove(e)   # wiki: Experience orb - fire, lava, explosions and cacti destroy orbs
		return
	# wiki: Experience orb - collected one at a time, 10 orbs / second (one every 2 ticks)
	var took: int = world.game_time - int(p.get_meta("xp_took", -100))
	if d < 1.0 and not p.dead and not p.is_spectator() and (took >= 2 or took < 0):
		p.set_meta("xp_took", world.game_time)
		var pts: int = e.xp
		if p == world.player:
			# wiki: Mending - each orb repairs one random damaged Mending item worn or in hand, 2 durability per XP point
			# (1 XP per 2 durability repaired); what is left goes to the player
			var cand: Array = []
			for si in [p.inventory.selected, Inventory.OFFHAND, Inventory.ARMOR0, Inventory.ARMOR0 + 1, Inventory.ARMOR0 + 2, Inventory.ARMOR0 + 3]:
				var ms := p.inventory.get_slot(si)
				if not ms.is_empty() and ms.damage > 0 and Loot._ench(ms, "mending") > 0:
					cand.append(si)
			if not cand.is_empty():
				var mslot: int = cand[rng.randi_range(0, cand.size() - 1)]
				var mst := p.inventory.get_slot(mslot)
				var rep := mini(pts * 2, mst.damage)
				mst.damage -= rep
				p.inventory.set_slot(mslot, mst)
				pts -= ceili(rep / 2.0)
				world.inv_changed()
		if pts > 0:
			p.add_xp(pts)
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
	var fname := blocks.name_of(e.state)
	var bp := Vector3i(int(floor(e.pos.x)), int(floor(e.pos.y + 0.01)), int(floor(e.pos.z)))
	var cur: int = gs.call(bp.x, bp.y, bp.z)
	# wiki: Falling Block - concrete powder becomes concrete when it intersects water while falling
	var into_water := fname.ends_with("_concrete_powder") and cur > 0 and (blocks.st_flags[cur] & BlockRegistry.F_LIQUID) != 0 and (blocks.st_flags[cur] & BlockRegistry.F_LAVA) == 0
	if not e.on_ground and not into_water:
		# wiki: Falling Block - dropped as an item after more than 600 ticks; deleted after 100 below the world bottom or
		# above the build limit (it was placed in mid-air after 600 ticks)
		if e.age > 100 and (e.pos.y < Coords.MIN_Y or e.pos.y >= Coords.MAX_Y):
			_remove(e)
		elif e.age > 600:
			var it0 := Res.items.id(fname)
			if it0 > 0:
				spawn_item(e.pos, ItemStack.of(it0, 1))
			_remove(e)
		return
	var land_st: int = e.state
	if (into_water or (fname.ends_with("_concrete_powder") and Growth.concrete_touches_water(world, bp))) and blocks.block_id(fname.trim_suffix("_powder")) >= 0:
		land_st = blocks.default_state(fname.trim_suffix("_powder"))   # (landing in / next to water)
	var fall: float = float(e.data.get("y0", e.pos.y)) - e.pos.y
	if fname in ["anvil", "chipped_anvil", "damaged_anvil"] and fall > 0.0:
		# wiki: Anvil - 2 HP per block fallen after the first, at most 40; helmets take 25 % off. It degrades one stage
		# with a 5 % x blocks fallen chance (a damaged anvil is destroyed)
		var fb := ceili(fall - 1.0)
		if fb > 0:
			var admg := minf(2.0 * fb, 40.0)
			var amn := Vector3(e.pos.x - e.w / 2, e.pos.y, e.pos.z - e.w / 2)
			var amx := Vector3(e.pos.x + e.w / 2, e.pos.y + e.h, e.pos.z + e.w / 2)
			var pl: Player = world.player
			var pmn := pl.aabb_min()
			var pmx := pl.aabb_max()
			if pmn.x < amx.x and pmx.x > amn.x and pmn.y < amx.y and pmx.y > amn.y and pmn.z < amx.z and pmx.z > amn.z:
				var helm := pl.inventory.get_slot(Inventory.ARMOR0 + 3)
				pl.hurt(admg * (0.75 if not helm.is_empty() and helm.name().ends_with("_helmet") else 1.0), "falling_anvil")
			for o in ents.duplicate():
				if o.kind == "mob" and not o.dead and o.pos.x - o.w / 2 < amx.x and o.pos.x + o.w / 2 > amn.x and o.pos.y < amx.y and o.pos.y + o.h > amn.y and o.pos.z - o.w / 2 < amx.z and o.pos.z + o.w / 2 > amn.z:
					_damage(o, admg, null)
		if rng.randf() < 0.05 * ceilf(fall):
			if fname == "damaged_anvil":
				land_st = -1
			else:
				land_st = blocks.default_state("chipped_anvil" if fname == "anvil" else "damaged_anvil")
				if blocks.has_prop(e.state, "facing"):
					land_st = blocks.with_prop(land_st, "facing", blocks.get_prop(e.state, "facing"))
		Audio.play("block.anvil.destroy" if land_st < 0 else "block.anvil.land", e.pos, "Blocks")
		if land_st < 0:
			_remove(e)
			return
	if cur >= 0 and (blocks.st_flags[cur] & BlockRegistry.F_REPLACEABLE):
		world.set_block(bp.x, bp.y, bp.z, land_st)
		# the landed block keeps being drawn where it came to rest until the terrain mesh shows it (it vanished for
		# the frames the remesh took)
		if e.node != null:
			e.node.position = world.vis(Vector3(bp) + Vector3(0.5, 0.0, 0.5))
			_ghosts.append([e.node, bp, world.cm.block_epoch, Time.get_ticks_msec()])
			e.node = null
	else:
		var it := Res.items.id(fname)
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
		if e.data.get("attached", false):
			# Java FireworkRocketEntity.tick attached to a gliding player: it rides at the hand (the boost itself is
			# applied in Player._travel_elytra while rocket_ticks last), at the feet when not gliding
			var hand := Vector3.ZERO
			if p.fall_flying:
				var yr := deg_to_rad(p.yaw)
				hand = Vector3(-cos(yr), 0.0, -sin(yr)) * 0.35 + Vector3(0, 0.3, 0)
			e.pos = p.pos + hand
			e.vel = p.vel
		else:
			# Java FireworkRocketEntity.tick (not attached): accelerate x1.15 horizontally, +0.04 up; explode at life end.
			# Shot from a crossbow (shotAtAngle): straight at its speed, exploding on contact with blocks and entities
			var angled: bool = e.data.get("angle", false)
			if not angled:
				e.vel = Vector3(e.vel.x * 1.15, e.vel.y + 0.04, e.vel.z * 1.15)
			var fhit := VoxelRaycast.cast(e.pos, e.vel, e.vel.length(), gs, blocks)
			var fent := false
			if angled:
				if e.owner != p and _seg_hits_box(e.pos, e.vel, p.aabb_min(), p.aabb_max()):
					fent = true
				for fo in ents:
					if not fent and fo.kind == "mob" and fo != e.owner and not fo.dead and _seg_hits_box(e.pos, e.vel, Vector3(fo.pos.x - fo.w / 2, fo.pos.y, fo.pos.z - fo.w / 2), Vector3(fo.pos.x + fo.w / 2, fo.pos.y + fo.h, fo.pos.z + fo.w / 2)):
						fent = true
			if fhit.is_empty() and not fent:
				e.pos += e.vel
			else:
				if not fhit.is_empty():
					e.pos = Vector3(fhit["point"]) - e.vel.normalized() * 0.1
				e.data["life"] = 0
		if e.age == 1:
			Audio.play("entity.firework_rocket.launch", e.pos, "Ambient", 3.0)
		# client tick: a spark every tick (life % 2 < 2), gaussian 0.05 sideways, against the vertical motion
		Particles.emit("firework", e.pos, Vector3(rng.randfn(0, 1) * 0.05, -e.vel.y * 0.5, rng.randfn(0, 1) * 0.05), Color.WHITE)
		if e.age >= int(e.data.get("life", 30)):
			_firework_explode(e, p)
			_remove(e)
		return
	var start := e.pos
	# wiki: Entity / Snowball / Egg / Ender Pearl / Splash Potion / Bottle o' Enchanting - thrown items: gravity 0.03
	# (potions 0.05, bottles o' enchanting 0.07), drag 0.99, ticked acceleration -> drag -> position
	var tg := -1.0
	match e.id:
		"snowball", "egg", "blue_egg", "brown_egg", "ender_pearl":
			tg = 0.03
		"splash_potion", "lingering_potion":
			tg = 0.05
		"experience_bottle":
			tg = 0.07
		"llama_spit":
			tg = 0.06   # wiki Llama Spit: gravity 0.06, drag 0.99
	if tg >= 0.0:
		e.vel.y -= tg
		e.vel *= 0.99
	elif (e.id == "fireball" or e.id == "small_fireball") and e.vel.length() > 0.0001:
		# wiki: Entity - fireballs: acceleration 0.1 along the flight, drag 0.95 (terminal 1.9 blocks/tick), no gravity;
		# acceleration -> drag -> position
		e.vel = (e.vel + e.vel.normalized() * 0.1) * 0.95
	var hit := VoxelRaycast.cast(start, e.vel, e.vel.length(), gs, blocks)
	# entity hit (a trident that already hit something only falls: wiki Trident - it damages one entity)
	var victim = null
	var dealt: bool = e.data.get("dealt", false)
	var pierced = e.rt.get("pierced")   # wiki Piercing: already pierced entities are passed through
	if not dealt and e.owner != p and _seg_hits_box(start, e.vel, p.aabb_min(), p.aabb_max()) and not (pierced is Array and (pierced as Array).has(p)):
		victim = p
	var hang = null
	for o in ents:
		if dealt:
			break
		if o.kind == "mob" and o != e.owner and _seg_hits_box(start, e.vel, Vector3(o.pos.x - o.w / 2, o.pos.y, o.pos.z - o.w / 2), Vector3(o.pos.x + o.w / 2, o.pos.y + o.h, o.pos.z + o.w / 2)) and not (pierced is Array and (pierced as Array).has(o)):
			victim = o
			break
		if hang == null and (o.kind == "frame" or o.kind == "painting") and not o.dead and e.id != "wind_charge" and o.pos.distance_squared_to(start) < 64.0:
			var hb: Array = MiscEntities.hanging_box(o)
			if _seg_hits_box(start, e.vel, hb[0], hb[1]):
				hang = o
	if victim is Ent and MobBehaviors.dodge_projectile(self, victim, e.id):
		victim = null   # wiki Enderman: teleports away before being hit (the projectile flies on)
	if victim == null and hang != null:
		# projectiles break paintings / item frames (a frame with an item drops the item first)
		MiscEntities.projectile_break(self, hang, e.owner)
		if e.id == "trident":
			_channel(e, hang.pos)
			e.vel = e.vel * Vector3(-0.01, -0.1, -0.01)
			e.data["dealt"] = true
			if int(e.data.get("loyalty", 0)) > 0:
				_trident_landed(e, p)
			return
		_projectile_end(e, e.pos, p)
		return
	if victim != null:
		var dmg := 0.0
		if e.id == "arrow":
			# Java AbstractArrow.onHitEntity: ceil(speed * baseDamage), crits add random(0..dmg/2+1)
			dmg = ceilf(e.vel.length() * float(e.data.get("base_damage", 2.0)))
			if bool(e.data.get("crit", false)):
				dmg += rng.randi_range(0, int(dmg / 2.0) + 1)
		elif e.id == "trident":
			dmg = float(e.data.get("base_damage", 8.0))
			if victim is Ent and e.stack != null:
				dmg += _ench_damage(e.stack, victim)   # wiki: Trident - Impaling: extra damage to aquatic mobs
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
		elif e.id == "wind_charge":
			dmg = 1.0   # wiki: Wind Charge - a direct hit deals 1 HP
		elif e.id == "llama_spit":
			dmg = 1.0   # wiki: Llama Spit - 1 HP
		if victim is Player:
			# 26.3 damage types scale a mob's projectile with difficulty (when_caused_by_living_non_player)
			var pdmg := MobAI.diff_dmg(int(world.difficulty), dmg) if dmg > 0 and e.owner is Ent else dmg
			if UseItem.block_projectile(victim as Player, e, start, pdmg):
				_projectile_blocked(e, p)
				return
			if e.id == "small_fireball" or e.id == "fireball":
				(victim as Player).fire_ticks = maxi((victim as Player).fire_ticks, 100)
			if e.id == "shulker_bullet":
				(victim as Player).add_effect("levitation", 0, 200)
			if e.id == "wither_skull":
				(victim as Player).add_effect("wither", 1, 200)
			if e.data.has("potion"):
				Potions.apply(victim as Player, str(e.data["potion"]), 0.125)
			if str(e.data.get("ammo", "")) == "spectral_arrow":
				(victim as Player).add_effect("glowing", 0, 200)   # wiki Spectral Arrow: Glowing for 10 seconds
			if e.id == "splash_potion" or e.id == "lingering_potion":
				e.data["direct"] = true   # wiki: Splash Potion - a direct hit gets the full effect
			# 26.3 damage types (arrow, fireball, mob_projectile, wither_skull ...): scaling when_caused_by_living_non_player -
			# a mob's projectile scales with difficulty (wiki Difficulty)
			dmg = pdmg
			if dmg > 0:
				# (no source position: the shield check above already decided; the shooter gets the death message credit)
				if (victim as Player).hurt(dmg, "fireball" if e.id.ends_with("fireball") else ("wind_charge" if e.id == "wind_charge" else ("spit" if e.id == "llama_spit" else "arrow")), false, Vector3.INF, e.owner if e.owner is Ent else null) and p.hurt_time == 10:
					(victim as Player).hurt_dir = rad_to_deg(atan2(start.z - p.pos.z, start.x - p.pos.x)) - p.yaw
				(victim as Player).knockback(0.4, -e.vel.x, -e.vel.z)   # (projectiles push along their flight)
				var ppunch := int(e.data.get("punch", 0))
				if ppunch > 0:
					# wiki Punch: arrows knock back further (Java AbstractArrow.doKnockback: horizontal flight x level x 0.6, + 0.1 up)
					var phv := Vector3(e.vel.x, 0, e.vel.z).normalized() * ppunch * 0.6
					(victim as Player).vel += Vector3(phv.x, 0.1, phv.z)
		else:
			_damage(victim, dmg, e.owner)
			if e.data.has("potion"):
				MobBehaviors.apply_potion(self, victim, str(e.data["potion"]), 0.125)   # (tipped arrows: 1/8 of the potion)
			if e.id == "splash_potion" or e.id == "lingering_potion":
				e.rt["direct_mob"] = victim
			if e.id != "dragon_fireball":   # wiki: Dragon Fireball - no damage or knockback on impact
				(victim as Ent).vel += e.vel.normalized() * 0.4 + Vector3(0, 0.1, 0)
			if e.data.get("flame", false):
				(victim as Ent).fire = maxi((victim as Ent).fire, 100)
			if str(e.data.get("ammo", "")) == "spectral_arrow":
				MobBehaviors.add_effect(victim, "glowing", 0, 200)   # wiki Spectral Arrow: Glowing for 10 seconds
			var punch := int(e.data.get("punch", 0))
			if punch > 0:
				var hv := Vector3(e.vel.x, 0, e.vel.z).normalized() * punch * 0.6
				(victim as Ent).vel += Vector3(hv.x, 0.1, hv.z)
		if e.id == "trident":
			# wiki: Trident - it bounces off the entity and lands nearby (Loyalty: returns)
			_channel(e, victim.pos)
			e.vel = e.vel * Vector3(-0.01, -0.1, -0.01)
			e.data["dealt"] = true
			if int(e.data.get("loyalty", 0)) > 0:
				_trident_landed(e, p)
			return
		var pierce := int(e.data.get("pierce", 0))
		var flies_on := false
		if e.id == "arrow" and pierce > 0:
			# wiki Piercing: the arrow passes through `level` entities (level + 1 are hit), never the same one twice
			var pl: Array = pierced if pierced is Array else []
			pl.append(victim)
			e.rt["pierced"] = pl
			flies_on = pl.size() <= pierce
		if not flies_on:
			_projectile_end(e, e.pos, p)
			return
	if not hit.is_empty():
		Sensors.on_projectile_hit(world, hit, e.id)
		if e.id == "trident" and Res.blocks.name_of(int(hit.get("state", 0))).ends_with("lightning_rod"):
			_channel(e, Vector3(hit["pos"]) + Vector3(0.5, 1.0, 0.5))   # wiki Channeling: a trident hitting a lightning rod
		if e.id == "arrow":
			# wiki: Arrow - stuck arrows stay for one minute (mob / Infinity / creative / extra Multishot arrows cannot be
			# picked up in survival)
			e.pos = Vector3(hit["point"]) - e.vel.normalized() * 0.1
			e.data["ground"] = true
			e.data["ground_age"] = 0
			Audio.play("entity.arrow.hit", e.pos, "Neutral", 1.0, rng.randf_range(1.0, 1.2) / 1.1)
			Sculk.vibrate(world, e.pos, e.owner == world.player, true, e.rt.get("from", Vector3.INF))
			return
		if e.id == "trident":
			e.pos = Vector3(hit["point"]) - e.vel.normalized() * 0.3
			Audio.play("item.trident.hit_ground", e.pos, "Neutral")
			_trident_landed(e, p, true)
			return
		_projectile_end(e, hit["point"], p)
		return
	e.pos += e.vel
	if tg >= 0.0 or e.id == "fireball" or e.id == "small_fireball" or e.id == "dragon_fireball" or e.id == "wither_skull" or e.id == "wind_charge":
		pass   # thrown items / fireballs: done above; dragon fireballs, wither skulls and wind charges fly straight (wiki: Wind Charge)
	elif e.id == "shulker_bullet":
		var want := (p.pos + Vector3(0, p.eye_height() * 0.5, 0) - e.pos).normalized() * 0.15
		e.vel = e.vel.lerp(want, 0.08)
	elif e.id == "arrow" or e.id == "trident":
		# wiki: Arrow / Trident - gravity 0.05, drag 0.99; arrows 0.6 in water (tridents do not slow down in water)
		e.vel *= 0.6 if e.id == "arrow" and _in_fluid(e, gs, blocks) == 1 else 0.99
		e.vel.y -= 0.05
	else:
		e.vel *= 0.99
		e.vel.y -= 0.03
	if e.age > 1200:
		_remove(e)


## Java FireworkRocketEntity.explode / dealExplosionDamage: rockets with stars deal 5 + 2 per star, scaled by
## sqrt((5 - distance) / 5) within 5 blocks; spark balls in the star colors.
func _firework_explode(e: Ent, p: Player) -> void:
	var fw = e.stack.components.get("minecraft:fireworks", {}) if e.stack != null else {}
	var stars: Array = fw.get("explosions", []) if fw is Dictionary else []
	if stars.is_empty():
		# entity event 17 without explosions: 2-4 poof particles
		for i0 in rng.randi_range(0, 2) + 2:
			Particles.emit("poof", e.pos, Vector3(rng.randfn(0, 1) * 0.05, 0.005, rng.randfn(0, 1) * 0.05))
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
	# wiki: Firework Rocket - damage within 5 blocks when not blocked by solid blocks (7 HP max with one star, +2 per star)
	var clear := func(to: Vector3) -> bool:
		var dv: Vector3 = to - e.pos
		if dv.length() < 0.02:
			return true
		var gsc := func(x: int, y: int, z: int) -> int:
			var s: int = world.state_at(x, y, z)
			return s if s > 0 and (Res.blocks.st_flags[s] & BlockRegistry.F_COLLIDE) != 0 else 0
		return VoxelRaycast.cast(e.pos, dv, dv.length() - 0.01, gsc, Res.blocks).is_empty()
	var pd := e.pos.distance_to(p.pos + Vector3(0, 0.9, 0))
	if pd <= 5.0 and clear.call(p.pos + Vector3(0, 0.9, 0)):
		p.hurt(dmg * sqrt((5.0 - pd) / 5.0), "fireworks", false, e.pos)
	for o in ents:
		if o.kind == "mob" and not o.dead and o.pos.distance_to(e.pos) <= 5.0 and clear.call(o.pos + Vector3(0, o.h * 0.5, 0)):
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
	var ga := int(e.data.get("ground_age", 0)) + 1
	e.data["ground_age"] = ga
	# wiki: Arrow / Trident - stuck arrows and tridents despawn after one minute
	if ga > 1200:
		_remove(e)
		return
	# wiki: Arrow - a tipped arrow in the ground for 600 ticks or more becomes a regular arrow
	if ga == 600 and e.id == "arrow" and str(e.data.get("ammo", "")) == "tipped_arrow":
		e.data.erase("potion")
		e.data["ammo"] = "arrow"
		e.stack = ItemStack.named("arrow", 1)
		if e.node != null:
			for c0 in e.node.get_children():
				c0.queue_free()
			e.node.add_child(projectile_rig("arrow"))
	if p.dead or p.is_spectator():
		return
	# wiki: Arrow - arrows shot by players can always be picked up in creative mode
	if not (bool(e.data.get("pickup", false)) or (p.is_creative() and e.owner is Player)):
		return
	# wiki: Item (entity) pickup box (player hitbox + 1 sideways, + 0.5 up / down) touching the 0.5 x 0.5 arrow /
	# trident box (wiki: Hitbox)
	var pmn := p.aabb_min() - Vector3(1.0, 0.5, 1.0)
	var pmx := p.aabb_max() + Vector3(1.0, 0.5, 1.0)
	if e.pos.x + 0.25 >= pmn.x and e.pos.x - 0.25 <= pmx.x and e.pos.z + 0.25 >= pmn.z and e.pos.z - 0.25 <= pmx.z and e.pos.y + 0.5 > pmn.y and e.pos.y < pmx.y:
		_give_back(e, p)


func _give_back(e: Ent, p: Player) -> void:
	var s: ItemStack = e.stack.copy() if e.stack != null else ItemStack.named("arrow", 1)
	if e.data.get("pickup", false) and p.inventory.add(s) > 0:
		if not e.data.get("returning", false):
			return   # a full inventory leaves the arrow / trident in the ground
		spawn_item(p.pos, s)
	Audio.play("entity.item.pickup", p.pos, "Players", 0.2, rng.randf_range(1.4, 2.0))
	world.inv_changed()
	_remove(e)


func _trident_landed(e: Ent, p: Player, stuck: bool = false) -> void:
	if int(e.data.get("loyalty", 0)) > 0 and e.owner == p:
		e.data["returning"] = true
		Audio.play("item.trident.return", e.pos, "Neutral")
		return
	if stuck:
		# wiki: Trident - it stays in the block and despawns after 60 seconds if not picked up (_tick_stuck)
		e.data["ground"] = true
		e.data["ground_age"] = 0
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
		# wiki: Ender Pearl - 5 % (1/20) chance to spawn an endermite where it lands
		if rng.randi_range(0, 19) == 0:
			spawn_mob("endermite", at)
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
			for k2 in 8:   # Java ThrownEgg.handleEntityEvent(3): 8 fragments of the item
				Particles.item_fragment(at, Vector3((rng.randf() - 0.5) * 0.08, (rng.randf() - 0.5) * 0.08, (rng.randf() - 0.5) * 0.08), est.item)
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
		Sculk.vibrate(world, at, e.owner == world.player, true, e.rt.get("from", Vector3.INF))
	if e.id == "lingering_potion":
		# wiki Lingering Potion: no splash effect, an area effect cloud where it breaks (MiscEntities.spawn_cloud)
		Audio.play("entity.splash_potion.break", at, "Neutral")
		var lpid := Potions.potion_of(e.stack) if e.stack != null else ""
		var lcol := Potions.color_of(lpid)
		for i in 16:
			Particles.emit("effect", at, Vector3(rng.randf_range(-0.15, 0.15), rng.randf_range(0.05, 0.2), rng.randf_range(-0.15, 0.15)), lcol)
		MiscEntities.spawn_cloud(self, at, lpid)
	elif e.id == "splash_potion":
		var pid := Potions.potion_of(e.stack) if e.stack != null else ""
		Audio.play("entity.splash_potion.break", at, "Neutral")
		# wiki: Splash Potion - entities in the 8.25 x 8.25 x 4.25 box centred on the impact and within 4 blocks of it
		# (measured to the closest point of their hitbox); the effect falls linearly to 0 at 4 blocks, a direct hit gets
		# it in full
		var pmn := p.aabb_min()
		var pmx := p.aabb_max()
		var direct: bool = e.data.get("direct", false)
		var cpt := Vector3(clampf(at.x, pmn.x, pmx.x), clampf(at.y, pmn.y, pmx.y), clampf(at.z, pmn.z, pmx.z))
		var pd := 0.0 if direct else cpt.distance_to(at)
		var inbox := pmn.x <= at.x + 4.125 and pmx.x >= at.x - 4.125 and pmn.z <= at.z + 4.125 and pmx.z >= at.z - 4.125 and pmn.y <= at.y + 2.125 and pmx.y >= at.y - 2.125
		if direct or (inbox and pd < 4.0):
			Potions.apply(p, pid, 1.0 - pd / 4.0 if e.id == "splash_potion" else 0.25)
		# the same box and distance rule for mobs (MobBehaviors.apply_potion: undead swap healing / harming)
		var dm = e.rt.get("direct_mob")
		for o in ents.duplicate():
			if o.kind != "mob" or o.dead or o.death_time > 0:
				continue
			var omn := Vector3(o.pos.x - o.w / 2.0, o.pos.y, o.pos.z - o.w / 2.0)
			var omx := Vector3(o.pos.x + o.w / 2.0, o.pos.y + o.h, o.pos.z + o.w / 2.0)
			var od := 0.0 if o == dm else Vector3(clampf(at.x, omn.x, omx.x), clampf(at.y, omn.y, omx.y), clampf(at.z, omn.z, omx.z)).distance_to(at)
			var oin := omn.x <= at.x + 4.125 and omx.x >= at.x - 4.125 and omn.z <= at.z + 4.125 and omx.z >= at.z - 4.125 and omn.y <= at.y + 2.125 and omx.y >= at.y - 2.125
			if o == dm or (oin and od < 4.0):
				MobBehaviors.apply_potion(self, o, pid, 1.0 - od / 4.0 if e.id == "splash_potion" else 0.25)
	elif e.id == "wither_skull":
		explode(at, 1.0, world.gamerule("mobGriefing", true))
	elif e.id == "fireball":
		# wiki: Explosion - ghast fireballs: power 1, fire in 1/3 of the blast's blocks (mob griefing)
		var grief: bool = world.gamerule("mobGriefing", true)
		explode(at, 1.0, grief, grief)
	elif e.id == "small_fireball":
		_ignite_near(at, 0)
	_remove(e)


## A projectile stopped by the player's raised shield (UseItem.block_projectile). wiki Arrow: when the damage fails, the
## arrow's velocity is multiplied by -0.1 (then moved, drag 0.99 and gravity 0.05 as every tick) - it bounces back and
## drops, and "can hit other targets"; wiki Trident: it bounces off and lands nearby (Loyalty: returns; no Channeling -
## that needs a hit); ghast fireballs / wither skulls still explode (the shield then blocks the blast from the front),
## the rest break as on a hit with none of their effects. Advancement "Not Today, Thank You" (entity_hurt_player with
## blocked #is_projectile damage).
func _projectile_blocked(e: Ent, p: Player) -> void:
	if world.get("advancements") != null:
		world.advancements.trigger("entity_hurt_player", {"blocked": true, "projectile": true})
	if e.id == "arrow":
		e.vel *= -0.1
		e.pos += e.vel
		e.vel *= 0.99
		e.vel.y -= 0.05
		return
	if e.id == "trident":
		e.vel = e.vel * Vector3(-0.01, -0.1, -0.01)
		e.data["dealt"] = true
		if int(e.data.get("loyalty", 0)) > 0:
			_trident_landed(e, p)
		return
	_projectile_end(e, e.pos, p)


## wiki Channeling: a thrown Channeling trident hitting an entity (also paintings / frames) or a lightning rod during a
## thunderstorm (dry biomes too) summons a lightning bolt there when nothing opaque or partly transparent is above it.
func _channel(e: Ent, at: Vector3) -> void:
	if e.stack == null or Loot._ench(e.stack, "channeling") <= 0 or not world.thundering:
		return
	if not MiscEntities._sees_sky(world, at):
		return
	lightning(at)


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


## Bells.ring sent this villager home: done once it reaches the bed, or after its paths there ran out three times.
func _bell_home_done(e: Ent, home: Vector3) -> bool:
	var reached := Vector2(e.pos.x - home.x, e.pos.z - home.z).length() < 1.5 and absf(e.pos.y - home.y) < 2.0
	if not reached and MobControl.nav_idle(e) and e.nav_cd <= 0:
		e.rt["bell_tries"] = int(e.rt.get("bell_tries", 0)) + 1
		reached = int(e.rt["bell_tries"]) > 3
	if reached:
		e.rt.erase("bell_home")
		e.rt.erase("bell_tries")
	return reached


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
	# Java mob healing outside effects: Allay.aiStep heals 1 every 10 ticks (2 HP/s); AbstractHorse.aiStep (horses,
	# donkeys, mules, llamas, camels) 1 with a 1 in 900 chance per tick
	var regen_every := int(def.get("regen_every", 0))
	if regen_every > 0 and e.age % regen_every == 0 and e.hp < float(def["hp"]) and e.death_time == 0:
		e.hp = minf(float(def["hp"]), e.hp + 1.0)
	elif def.get("horse_regen", false) and e.hp < float(e.data.get("max_hp", def["hp"])) and e.death_time == 0 and rng.randi_range(0, 899) == 0:
		e.hp = minf(float(e.data.get("max_hp", def["hp"])), e.hp + 1.0)
	if e.breed_cd > 0:
		e.breed_cd -= 1
	if e.love > 0:
		e.love -= 1
	if e.id == "zombie_villager" and e.data.has("cure"):
		Villagers.cure_tick(self, e)   # (golden apple cure in progress)
		if e.dead:
			return
	if e.baby_age < 0 and not MobBehaviors.FOREVER_BABY.has(e.id):   # wiki: baby zombies / piglins never grow up
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
	if e.rt.has("riding"):
		# a passenger of a boat (Vehicles._boat_passengers places it every tick); wiki Boat: no despawning while aboard
		var rv = e.rt["riding"]
		if rv == null or not is_instance_valid(rv) or rv.dead:
			e.rt.erase("riding")
		else:
			e.limb_amt = 0.0
			return
	var dist := e.pos.distance_to(p.pos)
	# wiki Mob spawning#Despawning: no player within 128 blocks (fish 64) -> removed at once; beyond 32 blocks a mob
	# whose inactivity counter passed 600 (+2 more per tick for monsters in light above 12 and for illagers / their
	# allies, i.e. 200 ticks) despawns with 1/800 per tick; a player within 32 blocks or damage resets the counter
	if not e.persistent:
		var dcat := MobAI.spawn_category(world, e.id)
		if def["kind"] == "hostile" or (dcat != "creature" and dcat != "misc"):
			if dist > (64.0 if dcat == "water_ambient" else 128.0):
				_remove(e)
				return
			if dist <= 32.0:
				e.rt["idle"] = 0
			else:
				if e.age % 10 == 0:
					var dl := _light_at(e.pos)
					e.rt["bright"] = def["kind"] == "hostile" and MobAI.brightness(MobAI.raw_light(world, dl)) > 0.5
				var idle := int(e.rt.get("idle", 0)) + 1 + (2 if e.rt.get("bright", false) else 0) + (2 if Raids.is_raider(e) or e.id == "vex" else 0)
				e.rt["idle"] = idle
				if idle > 600 and rng.randi_range(0, 799) == 0:
					_remove(e)
					return
	# wiki: monsters despawn on Peaceful, except hoglins, piglins, shulkers and sulfur cubes
	if def["kind"] == "hostile" and world.difficulty == 0 and not def.get("boss", false) and not (e.id in ["hoglin", "piglin", "shulker", "sulfur_cube"]):
		_remove(e)
		return
	var fl := _in_fluid(e, gs, blocks)
	if e.data.has("fx"):
		MobBehaviors.tick_effects(self, e)
		if e.dead or e.death_time > 0:
			return
	var fire_immune: bool = def.get("fire_immune", false) or (e.data.has("fx") and MobBehaviors.has_effect(e, "fire_resistance"))
	if fl == 1:
		e.fall = 0.0   # Java Entity: being in water resets the fall distance
	elif fl == 2:
		e.fall *= 0.5   # wiki Lava: each tick in lava halves the fall distance
	if fl == 2 and def.get("lava_walker", false):
		e.vel.y = maxf(e.vel.y, 0.06)   # striders float on lava
	if fl == 2 and not fire_immune:
		e.fire = 300
		_damage(e, 4.0, null)
	if def.get("water_hurts", false) and fl == 0 and world.raining:
		# wiki Enderman / Blaze / Snow Golem / Strider: rain hurts them like water (endermen keep teleporting until dry);
		# the sky check is refreshed every 10 ticks
		if e.age % 10 == 0 or not e.rt.has("rain"):
			e.rt["rain"] = BlockUpdates._raining_at(world, Vector3i((e.pos + Vector3(0, e.h, 0)).floor()))
		if bool(e.rt["rain"]):
			fl = 3
	if (fl == 1 or fl == 3) and def.get("water_hurts", false):
		_damage(e, 1.0, null)
		if def.get("teleports", false):
			_teleport(e, gs, blocks)
	if fl == 3:
		fl = 0
	if e.tp_cd > 0:
		e.tp_cd -= 1
	if e.id == "copper_golem" and not CopperGolem.tick_body(self, e):
		return   # (became a statue)
	# daylight burning (Java Mob.isSunBurnTick): while the 26.3 timeline's gameplay/monsters_burn is on (day time 23460 ..
	# 12542), brightness f at the eyes > 0.5 and random x 30 < (f - 0.4) x 2 per tick, under the open sky, not in water /
	# rain; a helmet takes the damage instead (wiki Zombie: helmets protect)
	var dtm := int(fposmod(float(world.day_time), 24000.0))
	if def.get("burns", false) and e.baby_age >= 0 and fl == 0 and (dtm >= 23460 or dtm < 12542) and world.dimension == "overworld":
		var l := _light_at(e.pos + Vector3(0, e.h * 0.85, 0))
		var bf := MobAI.brightness(MobAI.raw_light(world, l))
		if bf > 0.5 and rng.randf() * 30.0 < (bf - 0.4) * 2.0 and (l >> 4) >= 15 and not (world.raining and BlockUpdates._raining_at(world, Vector3i(e.pos.floor()))):
			# (wiki Zombie Nautilus: nautilus armor keeps it from burning)
			if str((e.data.get("armor", ["", "", "", ""]) as Array)[3]) == "" and (e.id != "zombie_nautilus" or ArmorRender.horse_armor_points(e) == 0):
				e.fire = maxi(e.fire, 160)
	if e.fire > 0:
		e.fire -= 1
		if fl == 1:
			e.fire = 0
		elif e.fire % 20 == 0 and not fire_immune:
			_damage(e, 1.0, null)
	if e.data.has("sleep") and Villagers.sleep_tick(self, e):
		return   # (a villager asleep in its bed: Villagers)
	if MobBehaviors.TICK_IDS.has(e.id) and MobBehaviors.pre_tick(self, e, p, dist, fl):
		if not MobBehaviors.self_moved:
			_physics(e, gs, blocks, 0.08 if fl == 0 else 0.02, 0.91 if fl == 0 else 0.8, float(def.get("step_height", 0.6)))
		e.limb_amt = lerpf(e.limb_amt, 0.0, 0.4)
		return   # (stunned ravager, goat preparing / in a long jump)
	if e.dead or e.death_time > 0:
		return
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
	if e.baby_age < 0 and def.has("baby_speed"):
		speed = float(def["baby_speed"])   # wiki Attribute: baby zombie variants 0.345
	if e.data.has("fx"):
		speed *= MobBehaviors.speed_mult(e)
	var hostile: bool = def["kind"] == "hostile"
	var follow := MobControl.follow_range(e)
	if pet_mode == 2:
		e.target_player = false
	elif (hostile or e.angry) and not p.dead and (p.mode == Player.Mode.SURVIVAL or p.mode == Player.Mode.ADVENTURE):
		var aggressive := MobAI.wants_target(self, e, p, dist)
		if e.id in ["spider", "cave_spider"] and e.hurt_time == 0 and not e.target_player:
			# wiki Spider: hostile while the light level around it is 11 or less, neutral above unless attacked
			var sl := _light_at(e.pos)
			if MobAI.brightness(MobAI.raw_light(world, sl)) >= 0.5:   # Java SpiderTargetGoal: magic value >= 0.5 (raw 12+)
				aggressive = false
		# wiki Attribute: targets are picked within the follow range (16 unless listed: zombies 35, enderman 64 ...)
		if aggressive and dist < follow:
			e.target_player = true
		elif not aggressive and not hostile:
			e.target_player = false
	else:
		e.target_player = false
	var flee := MobBehaviors.flee_point(self, e, p, dist) if MobBehaviors.FLEES.has(e.id) else Vector3.INF
	if e.id == "villager" and (flee != Vector3.INF or e.panic > 0) and world.game_time % 100 == 0:
		Villagers.summon_golem(self, e, 3)   # wiki Iron Golem: every 5 s while panicking (3 villagers)
	var mob_tgt = null
	var stay := false
	if hostile and not e.target_player and pet_mode == 0 and MobBehaviors.HUNTS.has(e.id):
		mob_tgt = MobBehaviors.mob_target(self, e)
	if flee != Vector3.INF:
		nav_target = flee
		speed *= float(MobBehaviors.FLEES[e.id])
		e.has_target = false
	elif pet_mode == 2:
		speed *= 1.3
	elif e.target_player:
		look_busy = true
		MobControl.set_look(e, p.pos + Vector3(0, p.eye_height(), 0), 30.0, 30.0)
		if dist > follow:
			e.target_player = false   # (Java TargetGoal: lost beyond the follow range)
			if not hostile:
				e.angry = false
		elif MobBehaviors.ATTACKS.has(e.id) and MobBehaviors.attack(self, e, p, dist):
			nav_target = MobBehaviors.nav_out
			direct = MobBehaviors.direct_out
		elif def.get("ranged", false):
			# wiki Skeleton: shoots within 15 blocks, every 3 s on Easy / Normal and 2 s on Hard, backs off within 4
			# blocks and closes in from 14; Bogged: 4.5 s / 3.5 s on Hard; Pillager: every 3 s from up to 8 blocks.
			# Bows are drawn for 20 ticks first (wiki Bow: a full draw takes 1 s; the interval includes it), aim error
			# 14 - 4 x difficulty (wiki Skeleton: 10 / 6 / 2)
			var pill: bool = e.id == "pillager"
			var reach := 8.0 if pill else 15.0
			if dist >= (reach if pill else 14.0):
				nav_target = p.pos
			elif dist < (6.0 if pill else 4.0):
				nav_target = e.pos + (e.pos - p.pos).normalized() * 3.0
			var draw := int(e.rt.get("draw", 0))
			if e.attack_cd <= 0 and dist <= reach:
				draw += 1
				if pill or draw >= 20:
					draw = 0
					MobBehaviors.shoot(self, e, p, "arrow", 1.6, 0.35)
					Audio.play("item.crossbow.shoot" if pill else "entity.skeleton.shoot", e.pos, "Hostile")
					var hard: bool = world.difficulty >= 3
					if pill:
						e.attack_cd = 60
					elif e.id == "bogged":
						e.attack_cd = 50 if hard else 70
					else:
						e.attack_cd = 20 if hard else 40
			else:
				draw = 0
			e.rt["draw"] = draw
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
						# wiki Creeper: explosion power 3, charged 6
						explode(e.pos + Vector3(0, 0.5, 0), 6.0 if e.data.get("powered", false) else 3.0, world.gamerule("mobGriefing", true))
						_remove(e)
						return
		else:
			nav_target = p.pos
			# Java WallClimberNavigation heads straight for the target; melee mobs close the last block directly
			direct = def.get("climbs", false) or (dist < 2.5 and absf(p.pos.y - e.pos.y) < 1.0)
			if dist < e.w * 0.5 + 0.3 + 1.0 and e.attack_cd <= 0 and absf(p.pos.y - e.pos.y) < 1.5:
				var dmg: float = MobAI.diff_dmg(world.difficulty, float(def.get("attack", 2.0)) + HeldItems.attack_bonus(e))
				if def.get("wither_hit", false):
					p.add_effect("wither", 0, 200)
				if p.hurt(dmg, "mob", false, e.pos, e):
					if p == world.player:
						pet_target = e
					# Java LivingEntity.hurtServer knockback 0.4 from the attacker (+ attack_knockback x 0.5 along its facing)
					p.knockback(0.4, e.pos.x - p.pos.x, e.pos.z - p.pos.z)
					var akb := float(def.get("attack_knockback", 0.0)) + HeldItems.ench(e, "knockback")   # (+ a Knockback weapon)
					if akb > 0.0:
						p.knockback(akb * 0.5, sin(deg_to_rad(e.yaw)), -cos(deg_to_rad(e.yaw)))
					if e.id == "cave_spider" and world.difficulty >= 2:
						p.add_effect("poison", 0, 140 if world.difficulty == 2 else 300)
					if e.id == "husk" and str(e.data.get("held", "")) == "":
						# wiki Husk: unarmed hits inflict Hunger for 7 x floor(regional difficulty) seconds
						var hsec := 7 * floori(MobAI.regional_difficulty(world, e.pos))
						if hsec > 0:
							p.add_effect("hunger", 0, hsec * 20)
				elif e.id == "ravager" and UseItem.is_blocking(p):
					MobBehaviors.ravager_blocked(self, e)
				e.attack_cd = 36 if e.id == "warden" else 20   # wiki Warden: melee cooldown 36 ticks
	elif mob_tgt != null:
		# zombies / vindicators / ravagers after a villager, wandering trader or iron golem (MobBehaviors.mob_target)
		nav_target = mob_tgt.pos
		look_busy = true
		MobControl.set_look(e, mob_tgt.pos + Vector3(0, mob_tgt.h * 0.85, 0), 30.0, 30.0)
		direct = e.pos.distance_squared_to(mob_tgt.pos) < 6.25 and absf(mob_tgt.pos.y - e.pos.y) < 1.0
		e.has_target = false
		MobBehaviors.melee_mob(self, e, mob_tgt)
	elif e.panic > 0:
		# Java PanicGoal: runs to random spots within 5 / 4 blocks until the panic ends
		e.panic -= 1
		speed *= float(def.get("panic_speed", 1.75))   # (per-mob PanicGoal / panic activity speed modifier)
		e.has_target = false
		if MobControl.nav_idle(e):
			MobControl.nav_random(self, e, 2)
		nav_rand = 2
	else:
		# Java TemptGoal (stops within 2.5 blocks, watches the player) / BreedGoal / FollowParentGoal / RandomStrollGoal
		var food: Array = def.get("food", [])
		var held := p.inventory.held()
		var cg_t := CopperGolem.goal(self, e) if e.id == "copper_golem" else Vector3.INF
		var ig = e.rt.get("golem_tgt") if e.id == "iron_golem" else null
		var bell_home = e.rt.get("bell_home")
		var ram_to = e.rt.get("ram_to")
		var vgoal := Villagers.tick(self, e) if e.id == "villager" else Vector3.INF   # job site / work / gathering / beds
		if e.data.has("sleep"):
			e.vel = Vector3.ZERO
			return   # (just lay down: Villagers.start_sleep)
		if ram_to is Vector3:
			# goat ram charge toward the locked target position (MobBehaviors._goat_tick)
			nav_target = ram_to
			direct = true
			speed *= MobBehaviors.GOAT_RAM_SPEED
			look_busy = true
			e.has_target = false
		elif bell_home is Vector3 and not _bell_home_done(e, bell_home):
			nav_target = bell_home   # wiki Bell: villagers that hear a bell run to the nearest bed (Bells.ring)
			speed *= float(def.get("hide_speed", 1.0))
			e.has_target = false
		elif vgoal == Villagers.STAY:
			stay = true   # (hiding indoors / waiting at its bed: stands still, no strolls)
			e.has_target = false
			if e.nav_job != null or not e.path.is_empty():
				MobControl.nav_stop(e)
		elif vgoal != Vector3.INF:
			nav_target = vgoal
			speed *= float(def["stroll_speed"]) if def.has("stroll_speed") else 1.0   # (the wiki gives no goal speed modifiers)
			e.has_target = false
		elif ig != null and is_instance_valid(ig) and not ig.dead:
			nav_target = ig.pos   # iron golem chasing its target (MobAI.iron_golem)
			e.has_target = false
		elif cg_t != Vector3.INF:
			# copper golem sorting (CopperGolem.goal): walking to a chest, or examining one
			e.has_target = false
			if e.data.has("cg_open"):
				look_busy = true
			else:
				nav_target = cg_t
		elif not held.is_empty() and (food.has(held.name()) or (def.get("tempt", []) as Array).has(held.name())) and dist < 10.0 and not p.dead:   # (TemptGoal: breeding food or the def's tempt items)
			look_busy = true
			MobControl.set_look(e, p.pos + Vector3(0, p.eye_height(), 0), 95.0, 40.0)
			nav_target = p.pos if dist > 2.5 else Vector3.INF
			e.has_target = false
		elif e.love > 0:
			for o in ents:
				# Java canMate: wolves, cats, horses, donkeys, mules, llamas only breed when both are tamed
				if o != e and o.kind == "mob" and o.id == e.id and o.love > 0 and o.pos.distance_to(e.pos) < 8.0 and (not (e.id in ["wolf", "cat", "horse", "donkey", "mule", "llama", "trader_llama", "camel"]) or (Taming.is_tamed(e) and Taming.is_tamed(o)) or e.id == "camel"):
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
							if e.id == "llama" or e.id == "trader_llama":
								baby.data["strength"] = MobBehaviors.llama_bred_strength(rng, e, o)
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
		if nav_target == Vector3.INF and not look_busy and e.love <= 0 and not stay:
			if e.baby_age < 0 and e.parent_pos != Vector3.INF:
				nav_target = e.parent_pos
				speed *= float(def["stroll_speed"]) if def.has("stroll_speed") else 1.25   # (villager babies walk to adults at the walk speed)
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
						speed *= float(def.get("stroll_speed", 1.0))   # (RandomStrollGoal speed modifier: villagers 0.5, traders 0.35)
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
	# wiki Lava: an entity in lava moves 50 % slower horizontally and 20 % slower vertically (water: drag 0.8)
	_physics(e, gs, blocks, 0.08 if fl == 0 else 0.02, 0.91 if fl == 0 else (0.5 if fl == 2 else 0.8), float(def.get("step_height", 0.6)), 0.8 if fl == 2 else 0.98)   # wiki Attribute: step_height (0.6 default)
	MobControl.body_tick(e)
	var mv := Vector2(e.pos.x - e.prev.x, e.pos.z - e.prev.z).length()
	e.limb_amt = lerpf(e.limb_amt, minf(mv * 4.0, 1.0), 0.4)
	e.limb += e.limb_amt
	if e.pos.y < Coords.MIN_Y - 64:
		_remove(e)
		return
	# Java Mob.baseTick ambient sound: ambientSoundTime counts up from -80 (getAmbientSoundInterval); each tick plays
	# with chance ambientSoundTime / 1000, then resets
	var amb_t := int(e.data.get("amb_t", -80))
	if rng.randi_range(0, 999) < amb_t:
		e.data["amb_t"] = -80
		var amb := "entity.%s.ambient" % e.id
		if e.id == "allay":   # Java Allay.getAmbientSound: with / without an item in hand
			amb = "entity.allay.ambient_with_item" if e.data.has("held_stack") else "entity.allay.ambient_without_item"
		mob_sound(e, amb)
	else:
		e.data["amb_t"] = amb_t + 1
	# fall damage handled in _physics


## Java Mob sounds: LivingEntity.getSoundVolume (1; ghast / ender dragon 5, slime and magma cube 0.4 x size) and
## getVoicePitch ((r - r) x 0.2 + 1, babies + 0.5), on the HOSTILE channel for monsters, NEUTRAL otherwise.
func mob_sound(e: Ent, event: String) -> void:
	var vol := 1.0
	if e.id == "ghast" or e.id == "ender_dragon":
		vol = 5.0
	elif e.id == "slime" or e.id == "magma_cube":
		vol = 0.4 * float(maxi(1, e.size))
	var pitch := (rng.randf() - rng.randf()) * 0.2 + (1.5 if e.baby_age < 0 else 1.0)
	Audio.play(event, e.pos, "Hostile" if e.def.get("kind", "") == "hostile" else "Neutral", vol, pitch)


## XP for a player kill (wiki Experience): the mob's range; babies none except baby zombies (x 2.5: 12) and baby
## hoglins / piglins (5); slimes / magma cubes their size; +1-3 per piece of natural equipment (worn armour, held weapon).
func mob_xp(e: Ent) -> int:
	var xr: Array = e.def.get("xp", [1, 3])
	var xp := rng.randi_range(int(xr[0]), int(xr[1]))
	if e.id == "slime" or e.id == "magma_cube":
		xp = e.size
	elif e.id == "sulfur_cube" and e.size < 2:
		return 0   # wiki Sulfur Cube: small cubes drop no experience
	if e.baby_age < 0:
		if e.id in ["zombie", "husk", "drowned", "zombie_villager", "zombified_piglin"]:
			xp = int(float(xp) * 2.5)
		elif e.id == "hoglin" or e.id == "piglin":
			xp = 5
		else:
			return 0
	if xp > 0 and e.def.get("kind", "") == "hostile":
		var pieces := 0
		for a in e.data.get("armor", []):
			if (a is Dictionary and not (a as Dictionary).is_empty()) or (a is String and a != ""):
				pieces += 1
		if str(e.data.get("held", "")) != "":
			pieces += 1
		for i in pieces:
			xp += 1 + rng.randi_range(0, 2)
	return xp


## Armor points (x) and toughness (y) of a mob: def armor_points (magma cubes 3 per size), worn pieces, horse armour.
func mob_armor(e: Ent) -> Vector2:
	var pts := float(e.def.get("armor_points", 0))
	if e.id == "shulker" and not e.target_player:
		pts = 20.0   # wiki Shulker: 20 armor while its shell is closed, none when open
	if e.id == "magma_cube":
		pts = 3.0 * float(e.size)
	var tough := 0.0
	for a in e.data.get("armor", []):
		var s := ItemStack.from_dict(a) if a is Dictionary else (ItemStack.named(str(a)) if str(a) != "" else ItemStack.new())
		if not s.is_empty():
			pts += float(Res.items.armor_points[s.item])
			tough += float(Res.items.armor_tough[s.item])
	if e.data.has("horse_armor"):
		pts += float(ArmorRender.horse_armor_points(e))
		var ha = e.data.get("horse_armor")
		var hn := str(ha.get("id", "")) if ha is Dictionary else str(ha)
		hn = hn.trim_prefix("minecraft:").trim_suffix("_horse_armor").trim_suffix("_nautilus_armor")
		tough += float(ArmorRender.HORSE_ARMOR_TOUGHNESS.get(hn, 0.0))
	return Vector2(pts, tough)


func _damage(e: Ent, amount: float, source, dtype: String = "") -> void:
	if e.dead or e.death_time > 0 or e.data.has("tear") or e.invuln > 10 or amount <= 0.0:
		return
	if dtype == "magic" and e.id == "witch":
		amount *= 0.15   # wiki Witch: magic damage (poison, instant damage, fangs, sonic boom, Thorns) 85 % less effective
	if e.id == "creaking" and Creaking.absorb_hit(world, e):
		e.invuln = 10
		return
	if e.id == "wither" and e.charge < 0:
		return   # invulnerable while charging
	if e.data.get("Invulnerable", false):
		return   # Java Entity.isInvulnerable (respawned spike crystals until the dragon is back)
	if e.def.get("dragon", false):
		if e.state == DragonFight.Ph.DYING:
			return
		var perched: bool = e.state in [DragonFight.Ph.SITTING_SCANNING, DragonFight.Ph.SITTING_ATTACKING, DragonFight.Ph.SITTING_FLAMING]
		if not e.data.has("head_hit") and not perched:
			amount = amount / 4.0 + minf(amount, 1.0)   # Java: hits off the head part (perched: the head is in reach)
		if perched:
			# wiki Ender Dragon: a perched dragon takes off once the damage taken while perched exceeds 50
			e.rt["perch_dmg"] = float(e.rt.get("perch_dmg", 0.0)) + amount
			if float(e.rt["perch_dmg"]) > 50.0:
				e.rt["perch_dmg"] = 0.0
				DragonFight._set_phase(e, DragonFight.Ph.TAKEOFF)
	e.rt["idle"] = 0   # (despawn inactivity counter)
	# Java armour on mobs (attacks only - fire, falls and other sourceless damage bypass it): the natural armor attribute
	# (wiki Attribute: zombies 2, magma cubes 3 x size ...), worn armour and horse armour, with toughness:
	# x (1 - clamp(armor - dmg / (2 + toughness / 4), armor / 5, 20) / 25)
	if source != null:
		var at := mob_armor(e)
		if at.x > 0.0:
			var fa := clampf(at.x - amount / (2.0 + at.y / 4.0), at.x * 0.2, 20.0)
			amount *= 1.0 - fa / 25.0
			# wiki Protection: worn Protection adds its level to the enchantment protection factor (cap 20), 4 % less damage
			# each (ominous trial mobs' Protection IV pieces; fire / projectile protection need a damage type: not here)
			var epf := 0
			for a in e.data.get("armor", []):
				if a is Dictionary and (a as Dictionary).has("components"):
					epf += Loot._ench(ItemStack.from_dict(a), "protection")
			if epf > 0:
				amount *= 1.0 - minf(20.0, float(epf)) / 25.0
	e.hp -= amount
	e.hurt_time = 10
	e.invuln = 20
	if e.data.has("sleep"):
		Villagers.wake(self, e)   # wiki Villager: attacked villagers wake up
	var fights_back := MobBehaviors.RETALIATES.has(e.id) and MobBehaviors.retaliate(self, e, source)
	if fights_back:
		pass   # (neutral animal turning on its attacker: MobBehaviors.retaliate)
	elif e.def.get("kind") == "passive":
		e.panic = 60
		if e.id == "wolf" and e.data.get("sitting", false):
			e.data["sitting"] = false   # wiki Wolf: a sitting wolf stands up when injured
	elif source is Player:
		e.target_player = true
		MobAI.anger(e, rng)
		# wiki Zombified Piglin: others in a 67 x 22 x 67 (up to 111 x 22 x 111) area join in; wiki Piglin: piglins
		# within 16 blocks of a piglin the player damaged
		if e.def.get("group_anger", false) or e.id == "piglin":
			for o in ents:
				if o.kind == "mob" and o.id == e.id and not o.dead:
					var dd: Vector3 = o.pos - e.pos
					if (e.id == "piglin" and dd.length() <= 16.0) or (e.id != "piglin" and absf(dd.x) <= 33.5 and absf(dd.z) <= 33.5 and absf(dd.y) <= 11.0):
						MobAI.anger(o, rng)
						o.target_player = true
	# wiki Enderman: always tries to teleport when hurt by natural sources (not when hit by a player or mob);
	# wiki Shulker: a chance to teleport once below half health
	if e.def.get("teleports", false) and e.hp > 0.0:
		if (e.id == "shulker" and e.hp < float(e.def["hp"]) / 2.0 and rng.randf() < 0.25) or (e.id != "shulker" and source == null):
			_teleport(e, world.state_at, Res.blocks)
	if e.hp > 0.0 and e.data.has("reinf"):
		MobBehaviors.on_damaged(self, e, source)
	mob_sound(e, "entity.%s.hurt" % e.id)
	if e.hp <= 0.0:
		_die(e, source is Player)


## Random teleport, dropping to the ground. wiki Enderman: up to 32 blocks on each axis, 64 attempts when hurt;
## wiki Shulker: five attempts within a 17 x 17 x 17 cube.
func _teleport(e: Ent, gs: Callable, blocks: BlockRegistry) -> bool:
	if e.tp_cd > 0:
		return false
	var shul: bool = e.id == "shulker"
	var tr := 8 if shul else 32
	for i in (5 if shul else 64):
		var t := e.pos + Vector3(rng.randf_range(-tr, tr), rng.randi_range(-tr, tr), rng.randf_range(-tr, tr))
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
	if by_player and e.id == "villager":
		# wiki Villager: killing a villager gives every villager within 16 blocks +25 major_negative gossip
		for gv in ents:
			if gv != e and gv.kind == "mob" and gv.id == "villager" and not gv.dead and absf(gv.pos.x - e.pos.x) <= 16.0 and absf(gv.pos.y - e.pos.y) <= 16.0 and absf(gv.pos.z - e.pos.z) <= 16.0:
				Trading.gossip(gv, "major_negative")
	if e.id == "end_crystal":
		# Java EndCrystal.hurtServer -> EnderDragon.onCrystalDestroyed: the dragon healing from this crystal takes 10
		# damage to the head; a holding / strafing dragon turns on the player
		_remove(e)
		explode(e.pos, 6.0, true)
		if world.dragon_fight != null:
			world.dragon_fight.on_crystal_destroyed(e)
		for o in ents:
			if o.kind == "mob" and o.id == "ender_dragon" and not o.dead:
				if o.rt.get("crystal") == e:
					o.rt.erase("crystal")
					o.data["head_hit"] = true
					_damage(o, 10.0, null)
					o.data.erase("head_hit")
				if by_player and o.state == DragonFight.Ph.HOLDING:
					DragonFight._set_phase(o, DragonFight.Ph.STRAFE)
		return
	if e.id == "ender_dragon":
		DragonFight.start_dying(e)   # 200 ticks rising and spinning, then on_dragon_death
		return
	MobBehaviors.on_death(self, e)
	if e.def.get("splits", false) and e.size > 1:
		var n := 2 if e.id == "sulfur_cube" else 2 + rng.randi_range(0, 2)   # wiki Sulfur Cube: two small cubes
		for i in n:
			var c := spawn_mob(e.id, e.pos + Vector3(rng.randf_range(-0.5, 0.5) * e.size * 0.5, 0.5, rng.randf_range(-0.5, 0.5) * e.size * 0.5))
			if c != null:
				set_size(c, e.size / 2)
	mob_sound(e, "entity.%s.death" % e.id)
	if by_player and bool(e.data.get("raid", false)) and world.level.get("raid") is Dictionary:
		world.level["raid"]["killed"] = true   # wiki Hero of the Village: the player must have killed a raider
	if world.gamerule("doMobLoot", true) and (e.baby_age >= 0 or e.def.get("kind") == "hostile"):
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
		if e.id == "allay":
			Allay.drops(self, e)
		HeldItems.drops(self, e, by_player)
		if by_player and bool(e.data.get("captain", false)) and not got_bottle:
			var ob := ItemStack.named("ominous_bottle", 1)
			ob.components["minecraft:ominous_bottle_amplifier"] = rng.randi_range(0, 4)
			spawn_item(e.pos + Vector3(0, 0.5, 0), ob)
		if by_player:
			world.player.stats["killed." + e.id] = int(world.player.stats.get("killed." + e.id, 0)) + 1
			if world.advancements != null:
				world.advancements.trigger("player_killed_entity", {"entity": e.id})
			spawn_xp(e.pos, mob_xp(e))
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
		for k in 20:   # LivingEntity.makePoofParticles
			Particles.emit("poof", e.pos + Vector3(rng.randf_range(-1, 1) * e.w, rng.randf() * e.h, rng.randf_range(-1, 1) * e.w),
				Vector3(rng.randfn() * 0.02, rng.randfn() * 0.02, rng.randfn() * 0.02))
		_remove(e)


## Java Explosion: 16^3 surface rays from the centre, each with radius * (0.7..1.3) strength losing
## (resistance + 0.3) * 0.3 per 0.3-block step (water / lava stop them); entities within 2 * radius take
## (k^2 + k) / 2 * 7 * 2r + 1 damage (k = (1 - d / 2r) * exposure; players scaled by difficulty) and are pushed by k
## toward their eyes (primed TNT: feet) - BEFORE the blocks go, so the destroyed blocks' drops survive (loot
## survives_explosion: 1 / radius, none for TNT: drop_decay false); TNT in the blast primes with a 10..29 tick fuse;
## fire: 1 in 3 of the blast's blocks above an opaque block catch fire; the touched chunks remesh at once.
## (wiki: Explosion, Item (entity), Experience orb, Painting, Item Frame, Armor Stand, Boat, Minecart)
func explode(at: Vector3, power: float, destroy: bool, fire: bool = false, drop_decay: bool = true) -> void:
	Audio.play("entity.generic.explode", at, "Blocks", 4.0)
	Sculk.vibrate(world, at, false)
	# Java HugeExplosionSeedParticle: six explosion sprites within 4 blocks
	for i in (6 if power >= 2.0 else 1):
		Particles.emit("explosion", at + Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2)) * (1.0 if power >= 2.0 else 0.0))
	var hit := {}
	var air := {}   # air cells the rays reached (fire candidates)
	if destroy or fire:
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
							if f > 0.0 and destroy:
								hit[bp] = true
						elif fire:
							air[bp] = true
						f -= 0.22500001
						q += d * 0.3
	# entities first (Java hurtEntities), then the blocks (finalizeExplosion)
	var two_p := power * 2.0
	# wiki: Explosion - exposure: the share of rays from sample points on a ceil(2 * size + 1) grid over the hitbox
	# (offset sideways to centre it) to the centre that no block hitbox stops
	var gsc := func(x: int, y: int, z: int) -> int:
		var s: int = world.state_at(x, y, z)
		return s if s > 0 and (Res.blocks.st_flags[s] & BlockRegistry.F_COLLIDE) != 0 else 0
	var expo := func(mn: Vector3, mx: Vector3) -> float:
		var size := mx - mn
		var stx := 1.0 / (size.x * 2.0 + 1.0)
		var sty := 1.0 / (size.y * 2.0 + 1.0)
		var stz := 1.0 / (size.z * 2.0 + 1.0)
		var ox := (1.0 - floorf(1.0 / stx) * stx) / 2.0
		var oz := (1.0 - floorf(1.0 / stz) * stz) / 2.0
		var seen := 0
		var tot := 0
		var fx := 0.0
		while fx <= 1.0:
			var fy := 0.0
			while fy <= 1.0:
				var fz := 0.0
				while fz <= 1.0:
					var sp := Vector3(lerpf(mn.x, mx.x, fx) + ox, lerpf(mn.y, mx.y, fy), lerpf(mn.z, mx.z, fz) + oz)
					var dv: Vector3 = at - sp
					tot += 1
					if dv.length() < 0.02 or VoxelRaycast.cast(sp, dv, dv.length() - 0.01, gsc, Res.blocks).is_empty():
						seen += 1
					fz += stz
				fy += sty
			fx += stx
		return float(seen) / float(maxi(tot, 1))
	var p: Player = world.player
	var pd := p.pos.distance_to(at)
	if pd < two_p:
		var pex: float = expo.call(p.aabb_min(), p.aabb_max())
		var impact := (1.0 - pd / two_p) * pex
		var pdmg := (impact * impact + impact) / 2.0 * 7.0 * two_p + 1.0
		# wiki: Explosion - players by difficulty: peaceful none, easy min(d / 2 + 1, d), normal d, hard d * 3 / 2
		match int(world.difficulty):
			0:
				pdmg = 0.0
			1:
				pdmg = minf(pdmg / 2.0 + 1.0, pdmg)
			3:
				pdmg *= 1.5
		if pdmg > 0.0:
			p.hurt(pdmg, "explosion", false, at)
		var pk := p.eye_pos() - at
		if pk.length() > 0.0001:
			# wiki Blast Protection: explosion knockback reduced by 15 % per level, the levels of all worn pieces stacking
			var bp_lv := 0
			for ai in 4:
				var arm := p.inventory.get_slot(Inventory.ARMOR0 + ai)
				if not arm.is_empty():
					bp_lv += Loot._ench(arm, "blast_protection")
			p.vel += pk.normalized() * impact * maxf(0.0, 1.0 - 0.15 * bp_lv)
	for o in ents.duplicate():
		if o.dead or o.pos.distance_to(at) >= two_p:
			continue
		var od: float = o.pos.distance_to(at)
		match o.kind:
			"frame", "painting":
				# wiki: Painting / Item Frame - broken by explosions (any damage), dropping as items
				if o.kind == "frame" and not o.stack.is_empty():
					if Maps.map_id(o.stack) >= 0:
						Maps.frame_removed(world, MiscEntities.frame_cell(o), o.stack)
					spawn_item(o.pos + Vector3(0, 0.4, 0), o.stack)
				spawn_item(o.pos + Vector3(0, 0.4, 0), ItemStack.named(o.id if o.kind == "frame" else "painting", 1))
				_remove(o)
				continue
			"mob", "item", "xp", "tnt", "falling", "armor_stand", "boat", "minecart":
				pass
			_:
				continue
		var oex: float = expo.call(Vector3(o.pos.x - o.w / 2, o.pos.y, o.pos.z - o.w / 2), Vector3(o.pos.x + o.w / 2, o.pos.y + o.h, o.pos.z + o.w / 2))
		var imp: float = (1.0 - od / two_p) * oex
		var odmg: float = (imp * imp + imp) / 2.0 * 7.0 * two_p + 1.0
		# knockback toward the eyes (wiki: Hitbox - eye height 0.85 x height), primed TNT toward its feet
		var ok: Vector3 = o.pos + Vector3(0, 0.0 if o.kind == "tnt" else o.h * 0.85, 0) - at
		if ok.length() > 0.0001:
			o.vel += ok.normalized() * imp
		match o.kind:
			"mob":
				_damage(o, odmg, null)
			"item", "xp":
				# wiki: Item (entity) / Experience orb - 5 HP, destroyed by explosions (nether stars are immune)
				if o.kind == "item" and o.stack != null and o.stack.name() == "nether_star":
					continue
				o.hp -= odmg
				if o.hp <= 0.0:
					_remove(o)
			"armor_stand":
				# wiki: Armor Stand - 20 HP; destroyed by an explosion it does not drop itself (its equipment does)
				o.hp -= odmg
				if o.hp <= 0.0:
					for a in o.data.get("armor", []):
						if a is Dictionary and not (a as Dictionary).is_empty():
							spawn_item(o.pos + Vector3(0, 0.4, 0), ItemStack.from_dict(a))
					Audio.play("entity.armor_stand.break", o.pos, "Blocks")
					_remove(o)
			"boat", "minecart":
				Vehicles.damage(self, o, odmg, null)
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
		# wiki: Explosion - blocks destroyed by TNT always drop (no 1 / power decay)
		var ctx := {"tool": null, "rng": world.rng, "explosion": drop_decay, "explosion_radius": power, "state": st2, "pos": bp2}
		var t = Loot.table("blocks/" + nm)
		if t is Dictionary:
			for s in Loot.roll_table(t, ctx):
				spawn_item(Vector3(bp2) + Vector3(0.5, 0.5, 0.5), s)
	if fire:
		# wiki: Explosion - fire in 1/3 of the blast's blocks, only above an opaque block
		var fst := Res.blocks.default_state("fire")
		for bp3 in hit:
			air[bp3] = true
		for bp4 in air:
			if rng.randi_range(0, 2) != 0 or world.state_at(bp4.x, bp4.y, bp4.z) != 0:
				continue
			var below3: int = world.state_at(bp4.x, bp4.y - 1, bp4.z)
			if below3 > 0 and Res.blocks.is_opaque(below3):
				world.set_block(bp4.x, bp4.y, bp4.z, fst)
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
	if e.kind == "mob" and e.id == "villager":
		Trading.gossip(e, "minor_negative")   # wiki Villager: attacking a villager +25 minor_negative (max 200)
	if e.kind == "mob" and e.id == "allay" and Allay.ignores_damage_from(e, p):
		return   # Java Allay.hurtServer: its liked player cannot hurt it
	# Java Player.attack (1.9+ combat): attack strength scales damage, gates crits / sweeps / sprint knockback
	var f := p.attack_strength(0.5)
	var dmg: float = 1.0 if held.is_empty() else Res.items.attack_damage[held.item]
	# wiki Melee attack: Strength +3 and Weakness -4 per level on the base damage (attack_damage attribute, min 0)
	dmg = maxf(0.0, dmg + 3.0 * p._effect_amp("strength") - 4.0 * p._effect_amp("weakness"))
	var ench := _ench_damage(held, e)
	dmg *= 0.2 + f * f * 0.8
	ench *= f
	var base := dmg   # cooldown-scaled base damage (sweep: 1 + ratio * base + enchantment damage)
	var strong := f > 0.9
	var kb_bonus := Loot._ench(held, "knockback")
	var sprint_kb := false
	if p.sprinting and strong:
		kb_bonus += 1
		sprint_kb = true
		Audio.play("entity.player.attack.knockback", e.pos, "Players")
	# wiki Melee attack: no crit while climbing, in water, riding, sprinting or with Blindness / Slow Falling / Levitation
	var crit := strong and p.fall_distance > 0.0 and not p.on_ground and not p.on_climbable and not p.in_water and not p.effects.has("blindness") and not p.effects.has("slow_falling") and not p.effects.has("levitation") and p.vehicle == null and not p.sprinting
	if crit:
		dmg *= 1.5
	dmg += ench
	var is_sword := not held.is_empty() and Res.items.tool_kind[held.item] == "sword"
	# wiki Melee attack: sweeping needs the movement between ticks below the movement_speed attribute
	var sweep := strong and not crit and not sprint_kb and p.on_ground and Vector2(p.pos.x - p.prev_pos.x, p.pos.z - p.prev_pos.z).length() < p.movement_speed(p.sprinting) and is_sword
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
				_damage(o, 1.0 + sratio * base + _ench_damage(held, o) * f, p)   # wiki Melee attack: 1 + r b + e
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
		# 26.3 enchantment data: entity tags #sensitive_to_smite / _bane_of_arthropods / _impaling (lists as fallback)
		var t_sm: Dictionary = Tags.resolve("entity_type", "sensitive_to_smite")
		var t_ba: Dictionary = Tags.resolve("entity_type", "sensitive_to_bane_of_arthropods")
		var t_im: Dictionary = Tags.resolve("entity_type", "sensitive_to_impaling")
		if (t_sm.has(e.id) if not t_sm.is_empty() else e.id in UNDEAD):
			b += 2.5 * Loot._ench(held, "smite")
		if (t_ba.has(e.id) if not t_ba.is_empty() else e.id in ARTHROPODS):
			b += 2.5 * Loot._ench(held, "bane_of_arthropods")
		if (t_im.has(e.id) if not t_im.is_empty() else e.id in AQUATIC):
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
	# wiki Iron Golem: an iron ingot heals 25 (only when hurt), sound entity.iron_golem.repair pitch 1 +- 0.2
	if e.id == "iron_golem" and not held.is_empty() and held.name() == "iron_ingot" and e.hp < float(e.def.get("hp", 100.0)):
		e.hp = minf(float(e.def.get("hp", 100.0)), e.hp + 25.0)
		Audio.play("entity.iron_golem.repair", e.pos, "Neutral", 1.0, 1.0 + (rng.randf() - rng.randf()) * 0.2)
		if not world.player.is_creative():
			world.player.inventory.consume_held()
		return
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
	if e.id == "allay" and Allay.interact(self, e, p, held):
		return
	if e.id == "copper_golem" and CopperGolem.interact(self, e, p, held):
		world.swing_hand()
		world.inv_changed()
		return
	if MobBuckets.pickup(self, e, p, held):   # water bucket on a fish / axolotl / tadpole (Bucketable.bucketMobPickup)
		return
	if Taming.interact(self, e, p, held):
		return
	if Villagers.try_cure(self, e, p, held):
		world.swing_hand()
		world.inv_changed()
		return
	if e.id == "villager" and (e.baby_age < 0 or (e.data.get("offers", []) as Array).is_empty()):
		# wiki Villager: unemployed villagers, nitwits and babies do not trade - entity.villager.no (babies 1.3-1.7), head shake
		e.rt["unhappy"] = 40
		Audio.play("entity.villager.no", e.pos, "Neutral", 1.0, rng.randf_range(1.3, 1.7) if e.baby_age < 0 else rng.randf_range(0.8, 1.2))
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
	if not held.is_empty() and food.has(held.name()) and e.baby_age < 0 and e.def.get("kind") == "passive":
		# wiki Breeding: feeding a baby cuts 10 % of its remaining growth time (in whole seconds)
		e.baby_age = mini(0, e.baby_age + int(-e.baby_age / 20.0 * 0.1) * 20)
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


const RAY_KINDS := {"mob": true, "boat": true, "minecart": true, "frame": true, "painting": true, "armor_stand": true, "cushion": true}


func raycast(o: Vector3, d: Vector3, max_d: float):
	var best = null
	var bd := max_d
	var veh = world.player.vehicle
	var reach2 := (max_d + 10.0) * (max_d + 10.0)   # (box centre to surface: the ender dragon is 16 wide)
	for e in ents:
		# distance first: every frame, every entity (dropped items included) went through the kind list and a box test
		if (e.pos - o).length_squared() > reach2 or not RAY_KINDS.has(e.kind) or e == veh:
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
## night (sky darkening >= 4: clear 12523..23477, rain 12002..23998, any time in thunder), within 3 / 2 blocks, with no monster within 8 x 5 x 8 of the bed;
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
		explode(Vector3(head) + Vector3(0.5, 0.5, 0.5), 5.0, true, true)   # wiki Bed / Explosion: power 5 with fire
		return true
	if Villagers.kick_out(self, head):
		return true   # wiki Villager: a villager asleep in the bed is kicked out (the player does not lie down)
	# 26.3 bed_rule can_sleep "when_dark" (Java Level.isDarkOutside: sky darkening >= 4): wiki Bed - day time 12523..23477
	# when clear, 12002..23998 in rain, any time in a thunderstorm
	if int(world.sky_darken_level()) < 4:
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
		p.spawn_dim = str(world.dimension)
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
	if world.get("sky_flash") != null:
		world.sky_flash = 2   # Java LightningBolt (client): level.setSkyFlashTime(2)
	# wiki Lightning: thunder volume 10000 (heard everywhere), pitch 0.8-1.0; impact 2.0, pitch 0.5-0.7
	Audio.play("entity.lightning_bolt.thunder", at, "Weather", 10000.0, 0.8 + rng.randf() * 0.2)
	Audio.play("entity.lightning_bolt.impact", at, "Weather", 2.0, 0.5 + rng.randf() * 0.2)
	for e in ents.duplicate():
		if e.kind == "mob" and e.pos.distance_to(at) < 3.0:
			if e.id == "copper_golem":
				CopperGolem.lightning(self, e)   # (Java: a struck copper golem loses one oxidation stage)
			elif e.id == "creeper":
				e.data["powered"] = true   # wiki Creeper: a lightning strike makes it charged (explosion power 6)
			e.fire = maxi(e.fire, 160)
			_damage(e, 5.0, null)
	if world.player.pos.distance_to(at) < 3.0:
		world.player.hurt(5.0, "lightning_bolt")
		world.player.fire_ticks = maxi(world.player.fire_ticks, 160)
	var g := Vector3i(at.floor())
	Sensors.lightning(world, g + Vector3i(0, -1, 0))   # Java LightningBolt.powerLightningRod
	Copper.lightning_clean(world, g + Vector3i(0, -1, 0), rng)   # Java LightningBolt.clearCopperOnLightningStrike
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


## wiki Mob spawning (Java): per-category caps (MobAI.CAPS) over the mobs within 128 blocks; packs centred 24+ blocks
## from the player and within 128 (fish 64); each member offset +-5 (triangular) from the pack centre and placed by the
## usual rules; at most 4 per pack (wolves, cod, tropical fish 8; horses, donkeys 6); zombies 5 % babies.
const PACK_MAX := {"wolf": 8, "cod": 8, "tropical_fish": 8, "horse": 6, "donkey": 6, "ghast": 1}   # (wiki Ghast: packs capped at 1)


## Mobs per spawn category within 128 blocks of the player (mobs that must persist don't count, animals do).
func _spawn_counts(p: Player) -> Dictionary:
	var counts := {}
	for e in ents:
		if e.kind == "mob" and Vector2(e.pos.x - p.pos.x, e.pos.z - p.pos.z).length_squared() <= 16384.0:
			var ecat := MobAI.spawn_category(world, e.id)
			if not e.persistent or ecat == "creature":
				counts[ecat] = int(counts.get(ecat, 0)) + 1
	return counts


func _natural_spawn(p: Player) -> void:
	if not world.gamerule("doMobSpawning", true) or p.dead:
		return
	var counts := _spawn_counts(p)
	var sim := int(Settings.get_v("simulation_distance")) * 16
	spawn_cycle += 1
	for attempt in 5:
		var category: String = ["monster", "creature", "monster", "water_ambient", "monster", "water_creature", "ambient", "creature"][(spawn_cycle + attempt) % 8]
		if attempt == 4:
			category = "axolotls" if spawn_cycle % 2 == 0 else "underground_water_creature"
		if category == "creature":
			continue   # (passive mobs: their own cycle every 400 ticks - _creature_tick)
		if int(counts.get(category, 0)) >= int(MobAI.CAPS.get(category, 0)) or (category == "monster" and world.difficulty == 0):
			continue
		var maxd := minf(float(sim), 64.0 if category == "water_ambient" else 128.0)
		if maxd < 24.0:
			continue
		var a := rng.randf() * TAU
		var r := rng.randf_range(24.0, maxd)
		_spawn_try(p, category, int(floor(p.pos.x + cos(a) * r)), int(floor(p.pos.z + sin(a) * r)), maxd, counts)


## wiki Mob spawning: passive mobs have one spawning cycle every 400 game ticks (20 s) - each chunk with its centre
## within 128 blocks of a player (and inside the simulation distance) gets one pack attempt at a random spot (Java
## NaturalSpawner, chunks in random order) while the creature cap is not full. The chunk attempts of a cycle are spread
## over the following ticks, 16 per tick (no burst in one tick).
var _creature_q: Array = []        # [player, block x, block z, max distance]
var _creature_counts: Dictionary = {}   # player instance id -> category counts of this cycle


func _creature_tick(p: Player) -> void:
	if int(world.game_time) % 400 == 0 and _creature_q.is_empty() and world.gamerule("doMobSpawning", true):
		var sim := int(Settings.get_v("simulation_distance")) * 16
		var maxd := minf(float(sim), 128.0)
		_creature_counts.clear()
		var pls: Array = [p]
		pls.append_array(_proxies)
		for pl in pls:
			if pl.dead or pl.is_spectator() or maxd < 24.0:
				continue
			var counts := _spawn_counts(pl)
			if int(counts.get("creature", 0)) >= int(MobAI.CAPS.get("creature", 10)):
				continue
			_creature_counts[pl.get_instance_id()] = counts
			var pcx := floori(pl.pos.x) >> 4
			var pcz := floori(pl.pos.z) >> 4
			var cr := ceili(maxd / 16.0)
			for cx in range(pcx - cr, pcx + cr + 1):
				for cz in range(pcz - cr, pcz + cr + 1):
					if Vector2(cx * 16 + 8 - pl.pos.x, cz * 16 + 8 - pl.pos.z).length_squared() <= maxd * maxd:
						_creature_q.append([pl, cx * 16 + rng.randi_range(0, 15), cz * 16 + rng.randi_range(0, 15), maxd])
		for i in range(_creature_q.size() - 1, 0, -1):   # (Java shuffles the chunk list)
			var j := rng.randi_range(0, i)
			var tmp = _creature_q[i]
			_creature_q[i] = _creature_q[j]
			_creature_q[j] = tmp
	var n := 0
	while not _creature_q.is_empty() and n < 16:
		var it: Array = _creature_q.pop_back()
		n += 1
		var pl: Player = it[0]
		var counts = _creature_counts.get(pl.get_instance_id())
		if counts == null or pl.dead or int(counts.get("creature", 0)) >= int(MobAI.CAPS.get("creature", 10)):
			continue
		_spawn_try(pl, "creature", int(it[1]), int(it[2]), float(it[3]), counts)


## One pack attempt of a category at column (x, z): a random height up to the surface, the biome / structure spawn
## list, the placement rules, then up to the pack size around it (counts updated).
func _spawn_try(p: Player, category: String, x: int, z: int, maxd: float, counts: Dictionary) -> void:
	var c: Chunk = world.cm.get_chunk(x >> 4, z >> 4)
	if c == null or not c.light_valid:
		return
	var y := rng.randi_range(maxi(Coords.MIN_Y, world.gen.gen_min_y) + 1, c.heightmap[(x & 15) + (z & 15) * 16] + 1)
	var at: int = world.state_at(x, y, z)
	if at > 0 and (Res.blocks.st_flags[at] & BlockRegistry.F_LIQUID) == 0 and (Res.blocks.st_flags[at] & BlockRegistry.F_COLLIDE) != 0:
		return   # (inside a solid block: nothing can spawn - skips the spawn-list lookups for most underground picks)
	var below: int = world.state_at(x, y - 1, z)
	var above: int = world.state_at(x, y + 1, z)
	var bio := c.biome_at(x & 15, y, z & 15)
	var light: int = world.cm.get_light(x, y, z)
	if category == "monster" and not MobAI.dark_enough(world, rng, light):
		return
	# structure spawn overrides (fortress enemies, witches in huts, guardians, pillagers; none in trial chambers)
	var ov = null
	var sgen = world.gen
	if sgen != null and "structures" in sgen and sgen.structures != null:
		ov = sgen.structures.spawn_override(x, y, z, category, Res.blocks.name_of(below) if below > 0 else "")
	var lst: Array = ov if ov != null else _biome_spawns(bio, category)
	if lst.is_empty() and ov == null and (category == "monster" or category == "creature") and Res.mode != "vanilla":
		lst = [{"type": "zombie", "weight": 100}, {"type": "skeleton", "weight": 100}, {"type": "creeper", "weight": 100}, {"type": "spider", "weight": 100}] if category == "monster" else [{"type": "pig", "weight": 10}, {"type": "cow", "weight": 8}, {"type": "sheep", "weight": 12}, {"type": "chicken", "weight": 10}]
	var total := 0
	var cands: Array = []
	for s in lst:
		var t := str(s.get("type", "")).trim_prefix("minecraft:")
		if MobRegistry.has_def(t) and _placement_ok(t, category, x, y, z, below, at, above, light):
			cands.append(s)
			total += int(s.get("weight", 1))
	if total <= 0:
		return
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
			var t2 := str(s["type"]).trim_prefix("minecraft:")
			for k in mini(n, int(PACK_MAX.get(t2, 4))):
				if int(counts.get(category, 0)) >= int(MobAI.CAPS.get(category, 0)):
					break
				var px := x + rng.randi_range(0, 5) - rng.randi_range(0, 5)
				var pz := z + rng.randi_range(0, 5) - rng.randi_range(0, 5)
				var pd := Vector3(px + 0.5 - p.pos.x, y - p.pos.y, pz + 0.5 - p.pos.z).length()
				var pc: Chunk = world.cm.get_chunk(px >> 4, pz >> 4)
				if pd < 24.0 or pd > maxd or pc == null or not pc.light_valid:
					continue
				var light2: int = world.cm.get_light(px, y, pz)
				if category == "monster" and not MobAI.dark_enough(world, rng, light2):
					continue
				if not _placement_ok(t2, category, px, y, pz, world.state_at(px, y - 1, pz), world.state_at(px, y, pz), world.state_at(px, y + 1, pz), light2, false):
					continue
				if spawn_mob(t2, Vector3(px + 0.5, y, pz + 0.5), rng.randf() < (0.05 if t2 in MobBehaviors.ZOMBIES or t2 == "zombified_piglin" else (0.2 if t2 == "piglin" else 0.0))) != null:   # wiki: zombie variants 5 % babies, piglins 20 %
					counts[category] = int(counts.get(category, 0)) + 1
			break


## Spawn placement (Java SpawnPlacements): on_ground (solid below, free feet/head), in_lava (striders),
## animals on grass with light >= 9 (overworld), plus mob-specific chances (ghast 1/20). rolls: false skips the
## random chances (pack members after the pack's first check).
func _placement_ok(id: String, category: String, x: int, y: int, z: int, below: int, at: int, above: int, light: int, rolls: bool = true) -> bool:
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
			# wiki Mob spawning: animals need a grass block below and a light level of 9 or more (no extra chance roll:
			# their rarity comes from the 400-tick cycle)
			if category == "creature" and world.dimension == "overworld" and (Res.blocks.name_of(below) != "grass_block" or maxi(light >> 4, light & 15) < 9):
				return false
	if rolls and d.has("spawn_chance") and rng.randf() >= float(d["spawn_chance"]):
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
		"ominous_item":
			# Java OminousItemSpawner is saved with its item and spawn_item_after_ticks (age counts toward it)
			return {"k": "ominous_item", "p": [e.pos.x, e.pos.y, e.pos.z], "s": e.stack.to_dict() if e.stack != null else {}, "a": e.age,
				"t": int(e.data.get("spawn_after", 60))}
		"boat", "minecart":
			return {"k": e.kind, "id": e.id, "p": [e.pos.x, e.pos.y, e.pos.z], "y": e.yaw, "d": e.data}
		"frame", "painting", "armor_stand", "cushion":
			return MiscEntities.ser(e)
		"mob":
			if e.def.get("kind") == "hostile" and not e.persistent:
				return {}
			return {"k": "mob", "id": e.id, "p": [e.pos.x, e.pos.y, e.pos.z], "hp": e.hp, "y": e.yaw, "b": e.baby_age, "sh": e.sheared, "d": e.data, "pers": e.persistent}
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
		"ominous_item":
			var oi = Trials.spawn_ominous_item(self, pos, ItemStack.from_dict(d.get("s", {})), int(d.get("t", 60)), false)
			if oi != null:
				oi.age = int(d.get("a", 0))
		"mob":
			var m := spawn_mob(str(d.get("id", "")), pos, int(d.get("b", 0)) < 0)
			if m != null:
				m.hp = float(d.get("hp", m.hp))
				m.yaw = float(d.get("y", 0))
				m.baby_age = int(d.get("b", 0))
				m.sheared = bool(d.get("sh", false))
				if d.get("d") is Dictionary and not (d["d"] as Dictionary).is_empty():
					m.data = d["d"]
					m.data.erase("glowing")   # (pre-effect spectral arrow / bell glow timer)
					if GlowOutline.glowing(m):
						GlowOutline.track(m)
				if d.has("vp") and m.id == "villager":
					m.data["prof"] = str(d["vp"])   # (village template villagers: unemployed / nitwit)
					MobBehaviors.villager_layers(m)
				if d.get("pers", false):
					m.persistent = true   # structure mobs (swamp hut witch / cat) never despawn


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
	if not _ghosts.is_empty():
		_update_ghosts()
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
			"falling":
				var sa = e.data.get("show_at")
				if sa != null:
					if e.age < 10 and not world.cm.mesh_caught_up(int(sa[0]), int(sa[1]), int(sa[2]), int(sa[3])):
						e.node.visible = false
						continue
					e.data.erase("show_at")
				if e.age % 5 == 0 or not e.node.has_meta("lit"):
					e.node.set_meta("lit", true)
					for mi in _meshes(e.node):
						mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			"tnt":
				for mi in _meshes(e.node):
					mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
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
				# Java ArmorStandRenderer: wobble sin(t / 1.5 pi) x 3 degrees for 5 ticks after a hit
				var wt: float = float(world.game_time - int(e.rt.get("last_hit", -100))) + clampf(float(world.tick_accum) / 0.05, 0.0, 1.0)
				if wt < 5.0:
					e.node.rotation.y += deg_to_rad(sin(wt / 1.5 * PI) * 3.0)
				for mi in _meshes(e.node):
					mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			"boat", "minecart":
				e.node.rotation.y = deg_to_rad(180.0 - e.yaw)
				e.node.rotation.z = sin(e.hurt_time * 0.6) * 0.1 if e.hurt_time > 0 else 0.0
				for mi in _meshes(e.node):
					mi.set_instance_shader_parameter("light", Vector2((l >> 4) / 15.0, (l & 15) / 15.0))
			"item", "ominous_item":
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
					var ah: int = (e.data["armor"] as Array).hash()
					if int(e.rt.get("armor_h", 0)) != ah:
						e.rt["armor_h"] = ah
						ArmorRender.apply(e.node, ArmorRender.slots_of_dicts(e.data["armor"]))   # (names or item dicts: trims, glint)
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
				if e.data.has("captain") and not e.rt.has("banner"):
					e.rt["banner"] = true
					MobBehaviors.render_captain(e)   # (ominous banner on the head)
				if e.id == "vex" and bool(e.rt.get("vex_tex", false)) != bool(e.rt.get("vex_charge", false)):
					_vex_texture(e, bool(e.rt.get("vex_charge", false)))   # wiki Vex: attacking vexes glow red
				if e.id == "cat" and str(e.rt.get("var_tex", "")) != str(e.data.get("variant", "")):
					e.rt["var_tex"] = str(e.data.get("variant", ""))
					MobBehaviors.cat_texture(e)   # (26.3 cat_variant asset)
				if e.id == "enderman" and (e.data.has("carried") or e.node.get_node_or_null("model/carried") != null):
					MobBehaviors.render_carried(e)
				if e.id in Taming.NAUTILI and (e.data.has("saddle") or e.data.has("horse_armor")):
					Taming.render_gear(e)   # (saddle / nautilus armor layers, rebuilt only when they change)
				elif e.id in Taming.NEEDS_TAMING and (e.data.has("saddle") or e.data.has("horse_armor")):
					var ha = e.data.get("horse_armor", {})
					ArmorRender.apply_horse(e.node, e.def.get("parts", []), ItemStack.from_dict(ha).name() if ha is Dictionary and not ha.is_empty() else "", bool(e.data.get("saddle", false)))
				# Java LivingEntityRenderer: rotY(180 - bodyYaw) after the model's (-1,-1,1) flip. Body yaw, head yaw /
				# pitch and the walk animation are interpolated between ticks (rotLerp(partialTick, yBodyRotO, yBodyRot),
				# WalkAnimationState.position(partialTick) / speed(partialTick)), so turning and walking stay smooth at
				# any frame rate.
				var by: float = e.body_yaw_o + MobControl.wrap_deg(e.body_yaw - e.body_yaw_o) * ea
				if e.id == "zombie_villager" and e.data.has("cure"):
					by += cos(floorf(e.age + ea) * 3.25) * PI * 0.4   # (curing: the body shudders; the wiki gives no amount)
				e.node.rotation.y = deg_to_rad(180.0 - by)
				# Java LivingEntityRenderer.setupRotations: dying bodies tip over sideways, sqrt(t / 20 * 1.6) x 90 degrees
				e.node.rotation.z = deg_to_rad(sqrt(clampf((e.death_time + ea - 1.0) / 20.0 * 1.6, 0.0, 1.0)) * 90.0) if e.death_time > 0 else 0.0
				var sdir = e.rt.get("sleep_dir")
				if sdir != null:
					_sleep_pose(e, int(sdir))
				elif e.rt.has("posed"):
					e.rt.erase("posed")
					e.node.rotation.x = 0.0
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
					var msig: int = model.get_child_count()
					for c in model.get_children():
						var nm: String = c.name
						msig = msig * 31 + c.get_child_count()
						if nm == "head":
							# Java model setupAnim: head.yRot = netHeadYaw, head.xRot = headPitch (attachments are children)
							var r0: Vector3 = c.get_meta("r0", Vector3.ZERO)
							c.rotation = r0 + Vector3(-deg_to_rad(hpitch), -deg_to_rad(hyaw), 0.0)
							if e.rt.has("unhappy"):
								c.rotation += Vector3(-0.4, 0.0, 0.3 * sin(0.45 * age_t))   # villager shaking its head (no trade)
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
					if e.id == "allay":
						if not model.has_meta("p0"):
							model.set_meta("p0", (model as Node3D).position)
						(model as Node3D).position = model.get_meta("p0")
						Allay.pose(e, model as Node3D, ea, amt, lpos, hyaw, hpitch)
					if e.def.get("dragon", false):
						_dragon_pose(e, model, ea)
					elif e.id == "end_crystal":
						_crystal_pose(e, model, ea)
					# light / hurt flash per mesh part: only when they change or parts were added / removed (armour, held
					# items) - walking the rig and setting instance uniforms every frame cost ~20-40 us per mob
					var hurt_v := 1.0 if e.hurt_time > 0 or e.death_time > 0 or (e.fuse >= 0 and (e.fuse / 4) % 2 == 0) else 0.0
					var mkey: int = l * 2 + int(hurt_v)
					if int(e.rt.get("mkey", -1)) != mkey or int(e.rt.get("msig", -1)) != msig:
						e.rt["mkey"] = mkey
						e.rt["msig"] = msig
						var lv2 := Vector2((l >> 4) / 15.0, (l & 15) / 15.0)
						for mi in _meshes(model):
							mi.set_instance_shader_parameter("light", lv2)
							mi.set_instance_shader_parameter("hurt", hurt_v)
				if e.fuse >= 0:
					e.node.scale = Vector3.ONE * (1.0 + e.fuse / 30.0 * 0.2)


## Java EnderDragonRenderer + EnderDragonModel.setupAnim from the flight history (64 ticks of yaw / y): the body turns
## with the yaw 7 ticks back and pitches with the climb, the neck, head and tail follow older samples (curving behind
## turns and waving with the flap phase), wings flap, legs tuck, the whole model bobs. Java model-space values; ours
## is flipped on x / y: positions (-x, -y, z) / 16, rotations (-x, -y, z).
func _dragon_pose(e: Ent, model: Node, ea: float) -> void:
	var hist: PackedFloat32Array = e.rt.get("hist", PackedFloat32Array())
	if hist.size() != 128:
		return
	var hi: int = int(e.rt.get("hist_i", 0))
	var pt := ea
	var hs := func(i: int) -> Vector2:
		var a := (hi - i) & 63
		var b := (hi - i - 1) & 63
		var yb := hist[b * 2]
		return Vector2(yb + wrapf(hist[a * 2] - yb, -180.0, 180.0) * pt, lerpf(hist[b * 2 + 1], hist[a * 2 + 1], pt))
	var fl: float = lerpf(float(e.rt.get("flap_o", 0.0)), float(e.rt.get("flap", 0.0)), ea)
	var fr := fl * TAU
	var f1 := sin(fr - 1.0) + 1.0
	f1 = (f1 * f1 + f1 * 2.0) * 0.05
	# renderer: rotY(-yaw 7 back), rotX((y 5 back - y 10 back) * 10), translate (0, 0, 1); root bob (0, f1 - 2, -3), f1 * 2 deg
	var h7: Vector2 = hs.call(7)
	var climb: float = (hs.call(5) as Vector2).y - (hs.call(10) as Vector2).y
	e.node.rotation = Vector3(deg_to_rad(climb * 10.0), deg_to_rad(-h7.x), 0.0)
	var m3 := model as Node3D
	m3.position = Vector3(0.0, 3.501 - f1, -2.0)
	m3.rotation = Vector3(-deg_to_rad(f1 * 2.0), 0.0, 0.0)
	var sitting: bool = e.state in [DragonFight.Ph.SITTING_SCANNING, DragonFight.Ph.SITTING_ATTACKING, DragonFight.Ph.SITTING_FLAMING]
	var landing: bool = e.state == DragonFight.Ph.LANDING or e.state == DragonFight.Ph.TAKEOFF
	var egg_d: float = float(e.rt.get("egg_d", 0.0))
	var s6: Vector2 = hs.call(6)
	var f6 := wrapf((hs.call(5) as Vector2).x - (hs.call(10) as Vector2).x, -180.0, 180.0)
	var f7 := wrapf((hs.call(5) as Vector2).x + f6 / 2.0, -180.0, 180.0)
	var px := 0.0
	var py := 20.0
	var pz := -12.0
	var dg := PI / 180.0
	for i in 5:
		var s: Vector2 = hs.call(5 - i)
		var off := (float(i) / maxf(egg_d / 4.0, 1.0)) if sitting else (float(i) if landing else s.y - s6.y)
		var yr := wrapf(s.x - s6.x, -180.0, 180.0) * dg * 1.5
		var xr := cos(i * 0.45 + fr) * 0.15 + off * dg * 1.5 * 5.0
		var zr := -wrapf(s.x - f7, -180.0, 180.0) * dg * 1.5
		var nk := m3.get_node_or_null("neck%d" % i) as Node3D
		if nk != null:
			nk.position = Vector3(-px, -py, pz) / 16.0
			nk.rotation = Vector3(-xr, -yr, zr)
		py += sin(xr) * 10.0
		pz -= cos(yr) * cos(xr) * 10.0
		px -= sin(yr) * cos(xr) * 10.0
	var hd := m3.get_node_or_null("head") as Node3D
	if hd != null:
		var s0: Vector2 = hs.call(0)
		var off6 := (6.0 / maxf(egg_d / 4.0, 1.0)) if sitting else (6.0 if landing else 0.0)
		hd.position = Vector3(-px, -py, pz) / 16.0
		hd.rotation = Vector3(-wrapf(off6, -180.0, 180.0) * dg * 1.5 * 5.0, -wrapf(s0.x - s6.x, -180.0, 180.0) * dg, -wrapf(s0.x - f7, -180.0, 180.0) * dg)
	var jaw := m3.find_child("jaw", true, false) as Node3D
	if jaw != null:
		jaw.rotation.x = -(sin(fr) + 1.0) * 0.2
	var torso := m3.get_node_or_null("torso") as Node3D
	if torso != null:
		torso.rotation = Vector3(0.0, 0.0, deg_to_rad(-f6 * 1.5))
	# wings (Java left: x 0.125 - cos f * 0.2, y -0.25, z -(sin f + 0.125) * 0.8; tip z (sin(f + 2) + 0.5) * 0.75;
	# the right one mirrored) and legs
	var wx := 0.125 - cos(fr) * 0.2
	var wz := (sin(fr) + 0.125) * 0.8
	var tz := (sin(fr + 2.0) + 0.5) * 0.75
	for sd in [["left", 1.0], ["right", -1.0]]:
		var n: String = sd[0]
		var sg: float = sd[1]
		var w := m3.find_child(n + "_wing", true, false) as Node3D
		if w != null:
			w.rotation = Vector3(-wx, 0.25 * sg, -wz * sg)
		var wt := m3.find_child(n + "_wing_tip", true, false) as Node3D
		if wt != null:
			wt.rotation = Vector3(0.0, 0.0, tz * sg)
		for lg in [["_hind_leg", 1.0], ["_hind_leg_tip", 0.5], ["_hind_foot", 0.75], ["_front_leg", 1.3], ["_front_leg_tip", -0.5], ["_front_foot", 0.75]]:
			var ln := m3.find_child(n + str(lg[0]), true, false) as Node3D
			if ln != null:
				var base: float = lg[1]
				ln.rotation.x = -(base + (f1 * 0.1 if base > 0.0 else -f1 * 0.1))
	var tx := 0.0
	var ty := 10.0
	var tzp := 60.0
	var s11: Vector2 = hs.call(11)
	var f10 := 0.0
	for j in 12:
		var s3: Vector2 = hs.call(12 + j)
		f10 += sin(j * 0.45 + fr) * 0.05
		var yr2 := (wrapf(s3.x - s11.x, -180.0, 180.0) * 1.5 + 180.0) * dg
		var xr2 := f10 + (s3.y - s11.y) * dg * 1.5 * 5.0
		var zr2 := wrapf(s3.x - f7, -180.0, 180.0) * dg * 1.5
		var tl := m3.get_node_or_null("tail%d" % j) as Node3D
		if tl != null:
			tl.position = Vector3(-tx, -ty, tzp) / 16.0
			tl.rotation = Vector3(-xr2, -yr2, zr2)
		ty += sin(xr2) * 10.0
		tzp -= cos(yr2) * cos(xr2) * 10.0
		tx -= sin(yr2) * cos(xr2) * 10.0
	_crystal_beam(e, ea)


## EnderDragonRenderer.renderCrystalBeams: 8 quads from 2 blocks above the dragon (radius 0.15, black) to the healing
## crystal's glass (radius 0.75, white), end_crystal_beam texture scrolling with the age.
var _beam_mat: ShaderMaterial = null


func _crystal_beam(e: Ent, ea: float) -> void:
	var c = e.rt.get("crystal")
	if c == null or not (c is Ent) or (c as Ent).node == null or (c as Ent).dead:
		_beam_draw(e, Vector3.INF, Vector3.ZERO, 0.0)
		return
	var ce: Ent = c
	var ca := float(ce.rt.get("t0", 0)) + ce.age + ea
	_beam_draw(e, world.vis(e.prev.lerp(e.pos, ea)) + Vector3(0, 2, 0), world.vis(ce.prev.lerp(ce.pos, ea)) + Vector3(0, 2.0 + _crystal_y(ca), 0), float(e.age) + ea)


## renderCrystalBeams between two points (render space): radius 0.15 and black at dp, 0.75 and white at cp.
## dp = INF hides the owner's beam.
func _beam_draw(e: Ent, dp: Vector3, cp: Vector3, age: float) -> void:
	var bm: MeshInstance3D = e.node.get_node_or_null("beam")
	if dp == Vector3.INF:
		if bm != null:
			bm.visible = false
		return
	if bm == null:
		bm = MeshInstance3D.new()
		bm.name = "beam"
		bm.top_level = true
		bm.mesh = ImmediateMesh.new()
		if _beam_mat == null:
			_beam_mat = ShaderMaterial.new()
			_beam_mat.shader = load("res://shaders/crystal_beam.gdshader")
			_beam_mat.set_shader_parameter("tex", EntityRenderer.texture("entity/end_crystal/end_crystal_beam"))
		bm.material_override = _beam_mat
		e.node.add_child(bm)
	bm.visible = true
	bm.global_transform = Transform3D.IDENTITY
	var d := cp - dp
	var ln := d.length()
	if ln < 0.01:
		bm.visible = false
		return
	var fwd := d / ln
	var ax := Vector3.UP if absf(fwd.y) < 0.99 else Vector3.RIGHT
	var u := fwd.cross(ax).normalized()
	var v := fwd.cross(u)
	var v0 := -age * 0.01
	var v1 := ln / 32.0 - age * 0.01
	var im := bm.mesh as ImmediateMesh
	im.clear_surfaces()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var pa := Vector2(0.0, 0.75)
	var ua := 0.0
	for j in range(1, 9):
		var pb := Vector2(sin(j * TAU / 8.0) * 0.75, cos(j * TAU / 8.0) * 0.75)
		var ub := j / 8.0
		var q := [dp + (u * pa.x + v * pa.y) * 0.2, cp + u * pa.x + v * pa.y, cp + u * pb.x + v * pb.y, dp + (u * pb.x + v * pb.y) * 0.2]
		var quv := [Vector2(ua, v0), Vector2(ua, v1), Vector2(ub, v1), Vector2(ub, v0)]
		var qc := [Color.BLACK, Color.WHITE, Color.WHITE, Color.BLACK]
		for k in [0, 1, 2, 0, 2, 3]:
			im.surface_set_color(qc[k])
			im.surface_set_uv(quv[k])
			im.surface_add_vertex(q[k])
		pa = pb
		ua = ub
	im.surface_end()


## EndCrystalRenderer.getY: the bobbing offset of the glass (-1.4 .. -0.6).
static func _crystal_y(age: float) -> float:
	var f := sin(age * 0.2) / 2.0 + 0.5
	f = (f * f + f) * 0.4
	return f - 1.4


const SIN45 := 0.70710677


## EndCrystalRenderer / EndCrystalModel: scale 2, translate (0, -0.5, 0) (no model flip); base plate (hidden on
## crystals players place), outer glass at y 24 px + getY * 8 px, inner glass (x 0.875) and cube (x 0.875 again),
## each turned by Ry(age * 3 deg) * R(60 deg about (sin 45, 0, sin 45)). Our part meshes are built flipped (F) at the
## model node (y 1.5): part transform = T(0, -1.5, 0) * S2 * T(0, -0.5, 0) * P * F.
func _crystal_pose(e: Ent, model: Node, ea: float) -> void:
	e.node.rotation = Vector3.ZERO
	var m3 := model as Node3D
	m3.rotation = Vector3.ZERO
	var age := float(e.rt.get("t0", 0)) + e.age + ea
	var q := Basis(Vector3.UP, deg_to_rad(age * 3.0)) * Basis(Vector3(SIN45, 0.0, SIN45), PI / 3.0)
	var root := Transform3D(Basis.from_scale(Vector3.ONE * 2.0), Vector3(0.0, -1.5 - 1.0, 0.0))
	var flip := Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO)
	var p_outer := Transform3D(q, Vector3(0.0, 1.5 + _crystal_y(age) / 2.0, 0.0))
	var p_inner := p_outer * Transform3D(q.scaled(Vector3.ONE * 0.875), Vector3.ZERO)
	var p_cube := p_inner * Transform3D(q.scaled(Vector3.ONE * 0.875), Vector3.ZERO)
	for pr in [["base", Transform3D.IDENTITY], ["outer_glass", p_outer], ["inner_glass", p_inner], ["crystal_cube", p_cube]]:
		var nd := m3.get_node_or_null(str(pr[0])) as Node3D
		if nd != null:
			nd.transform = root * (pr[1] as Transform3D) * flip
	var bs := m3.get_node_or_null("base") as Node3D
	if bs != null:
		bs.visible = bool(e.data.get("ShowBottom", true))
	# EndCrystalRenderer: a beam from 2 above the beam target's centre to the glass (dragon respawn sequence)
	var bt = e.data.get("BeamTarget")
	if bt is Vector3i:
		_beam_draw(e, world.vis(Vector3(bt) + Vector3(0.5, 2.5, 0.5)), world.vis(e.prev.lerp(e.pos, ea)) + Vector3(0, 2.0 + _crystal_y(age), 0), age)
	else:
		_beam_draw(e, Vector3.INF, Vector3.ZERO, 0.0)

## Java Mth.triangleWave
static func _triangle_wave(f: float, period: float) -> float:
	return (absf(fmod(f, period) - period * 0.5) - period * 0.25) / (period * 0.25)


## wiki Vex: "Attacking vexes glow red" - the installed entity/illager/vex_charging texture while charging (Java
## VexRenderer), vex otherwise; held items keep theirs.
func _vex_texture(e: Ent, charging: bool) -> void:
	e.rt["vex_tex"] = charging
	var base := EntityRenderer.material(str(e.def.get("tex", "entity/illager/vex")))
	var red := EntityRenderer.material("entity/illager/vex_charging")
	var model: Node = e.node.get_node_or_null("model")
	if model == null:
		return
	for mi in _meshes(model):
		var m = (mi as MeshInstance3D).material_override
		if m == (red if not charging else base):
			(mi as MeshInstance3D).material_override = base if not charging else red
	e.rt.erase("mkey")   # (re-apply light / hurt uniforms)


## Java LivingEntityRenderer for a sleeping entity (villagers in beds): moved back toward the foot by the standing eye
## height - 0.1 along the bed's facing, then rotY(sleepDirectionToRotation) * rotZ(90) * rotY(270) in place of the body
## yaw - lying on its back, head on the pillow. dir: Villagers.FACINGS index (south 90, west 0, north 270, east 180).
const SLEEP_ROT := [90.0, 0.0, 270.0, 180.0]
static var _sleep_q: Array = []


func _sleep_pose(e: Ent, dir: int) -> void:
	dir = clampi(dir, 0, 3)
	e.rt["posed"] = true
	if _sleep_q.is_empty():
		for r in SLEEP_ROT:
			var q := Basis(Vector3.UP, deg_to_rad(float(r))) * Basis(Vector3.BACK, PI / 2.0) * Basis(Vector3.UP, deg_to_rad(270.0))
			_sleep_q.append(q.get_rotation_quaternion())
	e.node.quaternion = _sleep_q[dir]
	var eye: float = float(e.def.get("eye", float(e.def.get("h", 1.95)) * 0.85)) * (0.5 if e.baby_age < 0 else 1.0) - 0.1
	var fv: Vector3i = Villagers.FACING_VEC[dir]
	e.node.position += Vector3(-fv.x * eye, 0.0, -fv.z * eye)


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
		if int(e.rt.get("atk_anim", 0)) > 0:
			ax = -2.0 + 1.5 * _triangle_wave(float(e.rt["atk_anim"]), 10.0)   # IronGolemModel attack swing
		bob = false
	elif rig == "humanoid" or e.id == "zombie_villager":
		ax = -PI / (1.5 if e.target_player else 2.25)
		ay = -0.1 if right else 0.1
	elif rig == "skeleton" and e.target_player and e.def.get("ranged", false):
		ay = (-0.1 if right else 0.5) + deg_to_rad(hyaw)
		ax = -PI / 2.0 + deg_to_rad(hpitch)
	elif e.id == "evoker" and int(e.rt.get("cast", 0)) > 0:
		# Java IllagerModel SPELLCASTING: arms raised to the sides, waving
		ax = cos(age_t * 0.6662) * 0.25
		az = 2.3561945 if right else -2.3561945
		bob = false
	elif e.id == "vex":
		# Java VexModel: arms out by pi / 5 + f (f = cos(age x 5.5 deg) x 0.1); charging (wiki Vex: they raise their
		# hands to attack) empty-handed vexes raise both arms forward, armed ones swing the arm holding the item back
		var f := cos(deg_to_rad(age_t * 5.5)) * 0.1
		var sg := 1.0 if right else -1.0
		az = (PI / 5.0 + f) * sg
		if bool(e.rt.get("vex_charge", false)):
			var any_item := str(e.data.get("held", "")) != "" or str(e.data.get("offhand", "")) != ""
			if not any_item or str(e.data.get("held" if right else "offhand", "")) != "":
				ax = -1.2217305 if not any_item else 3.6651914
				ay = 0.2617994 * sg
				az = -(0.47123888 + f) * sg
		bob = false
	elif e.id == "enderman" and e.data.has("carried"):
		# Java EndermanModel.setupAnim while carrying a block: both arms forward -0.5, z +-0.05
		ax = -0.5
		az = 0.05 if right else -0.05
		bob = false
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
