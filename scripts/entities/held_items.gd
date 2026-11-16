## HeldItems — Java mob hand equipment and ItemInHandLayer:
## - equip(e): Mob.populateDefaultEquipmentSlots per mob (zombie / husk: 1% (5% on Hard) iron sword or shovel, drowned:
##   10% trident (10/16) or fishing rod + 3% nautilus shell offhand, skeleton / stray / bogged / illusioner bow, wither
##   skeleton stone sword, piglin crossbow or golden sword, brute golden axe, zombified piglin golden sword,
##   vindicator iron axe, pillager crossbow, vex iron sword) into e.data["held"] / e.data["offhand"].
## - update(rig, main, off): the items as children of the arm pivots (arm0 = right, arm1 = left) with Java's chain
##   translateToHand -> rotX(-90) -> rotY(180) -> translate(+-1/16, 0.125, -0.625) -> the model's display transform for
##   thirdperson_right/lefthand (left hand mirrored: translation x, rotation y and z negated), model centred.
##   Our rigs map Java model space (x, y, z) to (-x, -y, z) / 16, a 180 degree turn about Z: child = S * J.
## - drops(em, e, by_player): equipment drop chance 0.085 (recently hit by a player), random wear like Java.
class_name HeldItems
extends RefCounted

## mobs whose attack value excludes the weapon: the held weapon adds its attack damage (wiki Piglin: golden sword 8 on
## Normal vs 5 unarmed)
const RANDOM_WEAPON_MOBS := ["zombie", "husk", "drowned", "zombie_villager", "piglin"]


static func equip(e, rng: RandomNumberGenerator, difficulty: int) -> void:
	var main := ""
	var off := ""
	match e.id:
		"zombie", "husk", "zombie_villager":
			if rng.randf() < (0.05 if difficulty == 3 else 0.01):
				main = "iron_sword" if rng.randi_range(0, 2) == 0 else "iron_shovel"
		"drowned":
			if rng.randf() > 0.9:
				main = "trident" if rng.randi_range(0, 15) < 10 else "fishing_rod"
			if rng.randf() < 0.03:
				off = "nautilus_shell"
		"skeleton", "stray", "bogged", "illusioner":
			main = "bow"
		"wither_skeleton":
			main = "stone_sword"
		"piglin":
			if e.baby_age >= 0:   # wiki Piglin: babies never spawn with weapons
				main = "crossbow" if rng.randf() < 0.5 else "golden_sword"
		"piglin_brute":
			main = "golden_axe"
		"zombified_piglin":
			main = "golden_sword"
		"vindicator":
			main = "iron_axe"
		"pillager":
			main = "crossbow"
		"vex":
			main = "iron_sword"
	if main != "":
		e.data["held"] = main
	if off != "":
		e.data["offhand"] = off


## Extra melee damage of a randomly equipped weapon (the fixed-weapon mobs' attack values already include theirs).
static func attack_bonus(e) -> float:
	if not (e.id in RANDOM_WEAPON_MOBS):
		return 0.0
	var h := str(e.data.get("held", ""))
	if h == "" or Res.items == null:
		return 0.0
	var id: int = Res.items.id(h)
	var b := maxf(0.0, float(Res.items.attack_damage[id]) - 1.0) if id > 0 else 0.0
	var sh := ench(e, "sharpness")
	if sh > 0:
		b += 0.5 * sh + 0.5   # wiki Sharpness (Java): +0.5 x level + 0.5
	return b


## Enchantment level on the mob's main-hand item (e.data["held_stack"]: equipment rolled from a loot table, e.g. the
## ominous trial weapons - Sharpness / Knockback swords, Power / Punch bows).
static func ench(e, id: String) -> int:
	var hs = e.data.get("held_stack")
	if not (hs is Dictionary) or not (hs as Dictionary).has("components"):
		return 0
	var en = (hs["components"] as Dictionary).get("minecraft:enchantments", {})
	return int(en.get("minecraft:" + id, 0)) if en is Dictionary else 0


static func drops(em, e, by_player: bool) -> void:
	if not by_player or e.data.has("no_equip_drop"):
		return
	for key in ["held", "offhand"]:
		var nm := str(e.data.get(key, ""))
		if nm == "" or em.rng.randf() >= 0.085:
			continue
		var hsd = e.data.get("held_stack") if key == "held" else null
		var s := ItemStack.named(nm, 1)
		if hsd is Dictionary and str(hsd.get("id", "")).trim_prefix("minecraft:") == nm and int(hsd.get("count", 1)) == 1:
			s = ItemStack.from_dict(hsd)   # (keeps its enchantments)
		var md: int = Res.items.max_damage[s.item]
		if md > 0:
			s.damage = md - em.rng.randi_range(0, em.rng.randi_range(0, maxi(md - 3, 1)))
			s.damage = clampi(s.damage, 0, md - 1)
		em.spawn_item(e.pos + Vector3(0, 0.5, 0), s)


## Shows main / offhand items in the rig's hands (cached per item key; "" removes).
static func update(rig: Node3D, main: ItemStack, off: ItemStack, left_handed: bool = false) -> void:
	if rig == null:
		return
	var model := rig.get_node_or_null("model")
	if model == null:
		return
	_slot(model.get_node_or_null("arm0"), off if left_handed else main, false)
	_slot(model.get_node_or_null("arm1"), main if left_handed else off, true)


static func _slot(arm: Node, s: ItemStack, left: bool) -> void:
	if arm == null:
		return
	var cur := arm.get_node_or_null("held_item")
	var key := "" if s == null or s.is_empty() else "%d|%d" % [s.item, hash(str(s.components))]
	if cur != null and str(cur.get_meta("key", "")) == key:
		return
	if cur != null:
		arm.remove_child(cur)
		cur.queue_free()
	if key == "":
		return
	var n := Node3D.new()
	n.name = "held_item"
	n.set_meta("key", key)
	# S * rotX(-90) * rotY(180) * translate(+-1/16, 0.125, -0.625)
	var j := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3.ZERO)
	j = j * Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)
	j = j * Transform3D(Basis(), Vector3((-1.0 if left else 1.0) / 16.0, 0.125, -0.625))
	n.transform = Transform3D(Basis.from_scale(Vector3(-1, -1, 1)), Vector3.ZERO) * j
	var inner := item_node(s, "thirdperson_lefthand" if left else "thirdperson_righthand", left)
	if inner != null:
		n.add_child(inner)
	arm.add_child(n)


## The item's model for a display context with its display transform applied (left hand mirrored), centred like
## Java's translate(-0.5, -0.5, -0.5): block models (block_item_mesh) or the extruded / elements item model.
static func item_node(s: ItemStack, ctx: String, left: bool) -> Node3D:
	var spec: Node3D = BERender.item_node(s.item, ctx, {"patterns": Banners.layers(s), "base_color": s.components.get("minecraft:base_color")})
	if spec != null:
		return spec
	var pb: int = Res.items.place_block[s.item]
	var mesh: Mesh = null
	var mat: Material = null
	var off := Vector3.ZERO
	var disp: Dictionary = {}
	if pb > 0 and not Res.items.model_ref[s.item].begins_with("item/"):
		mesh = EntityRenderer.item_block_mesh(s.item)   # (null when neither the item nor the state has block geometry)
		off = Vector3(0, -0.5, 0)
		disp = ItemIcons.item_display(s.item, ctx.replace("lefthand", "righthand"))
	if mesh == null:
		var ref := ItemRegistry.ctx_model(s.name(), ctx) if Res.mode == "vanilla" else ""
		if ref == "":
			ref = Res.items.model_ref[s.item]
		var em: Array = ItemIcons.extruded_model(ref)
		if em.size() != 2:
			return null
		mesh = em[0]
		mat = EntityRenderer.flat_item_material(em[1])   # (translucent sprites blend: stained glass panes)
		disp = ItemIcons.model_display(ref, ctx.replace("lefthand", "righthand"))
	var dt: Array = disp.get("translation", [0, 0, 0])
	var dr: Array = disp.get("rotation", [0, 0, 0])
	var dsc: Array = disp.get("scale", [1, 1, 1])
	var tx := float(dt[0]) * (-1.0 if left else 1.0)
	var ry := float(dr[1]) * (-1.0 if left else 1.0)
	var rz := float(dr[2]) * (-1.0 if left else 1.0)
	var b := Basis(Vector3.RIGHT, deg_to_rad(float(dr[0]))) * Basis(Vector3.UP, deg_to_rad(ry)) * Basis(Vector3.BACK, deg_to_rad(rz))
	b = b * Basis.from_scale(Vector3(float(dsc[0]), float(dsc[1]), float(dsc[2])))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if mat != null:
		mi.material_override = mat
	mi.transform = Transform3D(b, Vector3(tx, float(dt[1]), float(dt[2])) / 16.0) * Transform3D(Basis(), off)
	var root := Node3D.new()
	root.add_child(mi)
	return root
