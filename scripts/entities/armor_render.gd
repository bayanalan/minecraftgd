## Armor rendering (Java HumanoidArmorLayer / HumanoidModel.createMesh): outer layer (helmet, chestplate, boots)
## is the humanoid model inflated by 1.0, inner layer (leggings) by 0.5, on the installed
## entity/equipment/humanoid[_leggings]/<material>.png (64x32). Parts per slot: head (+hat) / body+arms /
## body+legs / legs. Meshes are attached to the rig's part pivots so they animate with the limbs.
## Mob equipment: Java Mob.populateDefaultEquipmentSlots (chance 0.15 * local difficulty, tier 0-4 with three
## 9.5% upgrades, per-slot stop chance 0.25 (0.1 on Hard)); drops at 8.5%.
## APPROXIMATE: leather uses the default dye color, no leather overlay, no armor trims, no enchantment glint.
class_name ArmorRender
extends RefCounted

const SLOT_PARTS := {0: ["leg0", "leg1"], 1: ["body", "leg0", "leg1"], 2: ["body", "arm0", "arm1"], 3: ["head"]}
const BOXES := {"head": [[-4, -8, -4], [8, 8, 8], [0, 0]], "body": [[-4, 0, -2], [8, 12, 4], [16, 16]],
	"arm0": [[-3, -2, -2], [4, 12, 4], [40, 16]], "arm1": [[-1, -2, -2], [4, 12, 4], [40, 16]],
	"leg0": [[-2, 0, -2], [4, 12, 4], [0, 16]], "leg1": [[-2, 0, -2], [4, 12, 4], [0, 16]]}
const PIECES := ["boots", "leggings", "chestplate", "helmet"]
const TIERS := ["leather", "golden", "chainmail", "iron", "diamond"]
const MATERIALS := ["leather", "chainmail", "iron", "golden", "diamond", "netherite", "copper"]
const ARMOR_MOBS := ["zombie", "husk", "drowned", "zombie_villager", "skeleton", "stray", "bogged", "piglin", "zombified_piglin", "wither_skeleton", "parched"]


static func material_of(nm: String) -> String:
	if nm == "turtle_helmet":
		return "turtle_scute"
	for m in MATERIALS:
		if nm.begins_with(m + "_"):
			return "gold" if m == "golden" else m
	return ""


## slots: 4 item names (feet, legs, chest, head); "" = empty. Rebuilds only when the set changes.
static func apply(rig: Node3D, slots: Array) -> void:
	var model: Node = rig.get_node_or_null("model")
	if model == null:
		return
	var key := str(slots)
	if str(rig.get_meta("armor_key", "[]")) == key:
		return
	rig.set_meta("armor_key", key)
	for part in model.get_children():
		for c in part.get_children():
			if str(c.name).begins_with("armor"):
				c.queue_free()
	for slot in 4:
		var full := str(slots[slot]) if slot < slots.size() else ""
		var raw := full.get_slice("#", 0)
		var trim := full.get_slice("#", 1) if full.contains("#") else ""
		var nm := raw.get_slice("@", 0)
		var mat := material_of(nm)
		if mat == "":
			continue
		var legs := slot == 1
		var tex := "entity/equipment/%s/%s" % ["humanoid_leggings" if legs else "humanoid", mat]
		var inflate := 0.5 if legs else 1.0
		var tint := Color(0.627, 0.396, 0.251) if mat == "leather" else Color.WHITE
		if mat == "leather" and raw.contains("@"):
			var dc := raw.get_slice("@", 1).to_int()
			tint = Color8((dc >> 16) & 255, (dc >> 8) & 255, dc & 255)
		for pn in SLOT_PARTS[slot]:
			var pivot: Node = model.get_node_or_null(pn)
			if pivot == null:
				continue
			var b: Array = BOXES[pn]
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			EntityRenderer.box_arrays(Vector3(b[0][0], b[0][1], b[0][2]), Vector3(b[1][0], b[1][1], b[1][2]), Vector2(b[2][0], b[2][1]), Vector2(64, 32), st, inflate, tint)
			if slot == 3:
				EntityRenderer.box_arrays(Vector3(-4, -8, -4), Vector3(8, 8, 8), Vector2(32, 0), Vector2(64, 32), st, inflate + 0.5, tint)
			var mi := MeshInstance3D.new()
			mi.name = "armor_%d_%s" % [slot, pn]
			mi.mesh = st.commit()
			mi.material_override = EntityRenderer.material(tex)
			pivot.add_child(mi)
			if trim != "":
				var tt := trim_texture(trim.get_slice(":", 0), trim.get_slice(":", 1), legs, mat)
				if tt != null:
					var stt := SurfaceTool.new()
					stt.begin(Mesh.PRIMITIVE_TRIANGLES)
					EntityRenderer.box_arrays(Vector3(b[0][0], b[0][1], b[0][2]), Vector3(b[1][0], b[1][1], b[1][2]), Vector2(b[2][0], b[2][1]), Vector2(64, 32), stt, inflate + 0.02)
					if slot == 3:
						EntityRenderer.box_arrays(Vector3(-4, -8, -4), Vector3(8, 8, 8), Vector2(32, 0), Vector2(64, 32), stt, inflate + 0.52)
					var mt := MeshInstance3D.new()
					mt.name = "armor_%d_%s_trim" % [slot, pn]
					mt.mesh = stt.commit()
					mt.material_override = _trim_mat(tt)
					pivot.add_child(mt)
			if mat == "leather" and EntityRenderer.texture(tex + "_overlay") != null:
				# Java leather overlay layer (untinted), slightly outside the dyed layer
				var so := SurfaceTool.new()
				so.begin(Mesh.PRIMITIVE_TRIANGLES)
				EntityRenderer.box_arrays(Vector3(b[0][0], b[0][1], b[0][2]), Vector3(b[1][0], b[1][1], b[1][2]), Vector2(b[2][0], b[2][1]), Vector2(64, 32), so, inflate + 0.01)
				if slot == 3:
					EntityRenderer.box_arrays(Vector3(-4, -8, -4), Vector3(8, 8, 8), Vector2(32, 0), Vector2(64, 32), so, inflate + 0.51)
				var mo := MeshInstance3D.new()
				mo.name = "armor_%d_%s_ov" % [slot, pn]
				mo.mesh = so.commit()
				mo.material_override = EntityRenderer.material(tex + "_overlay")
				pivot.add_child(mo)


## Horse saddle + body armor layers (Java HorseArmorLayer / saddle layer): the horse model's parts again, inflated
## slightly, with the installed entity/equipment/horse_body/<material>.png and horse_saddle/saddle.png textures.
const HORSE_ARMOR := {"leather": 3, "copper": 4, "iron": 5, "golden": 7, "diamond": 11, "netherite": 19}


static func apply_horse(rig: Node3D, parts: Array, armor_item: String, saddle: bool) -> void:
	var model: Node = rig.get_node_or_null("model")
	if model == null:
		return
	var key := armor_item + "|" + str(saddle)
	if str(rig.get_meta("horse_key", "|false")) == key:
		return
	rig.set_meta("horse_key", key)
	for part in model.get_children():
		for c in part.get_children():
			if str(c.name).begins_with("hlayer"):
				c.queue_free()
	var layers: Array = []
	if armor_item.ends_with("_horse_armor"):
		var mat := armor_item.trim_suffix("_horse_armor")
		layers.append(["entity/equipment/horse_body/" + ("gold" if mat == "golden" else mat), 0.1, Color(0.627, 0.396, 0.251) if mat == "leather" else Color.WHITE])
	if saddle:
		layers.append(["entity/equipment/horse_saddle/saddle", 0.05, Color.WHITE])
	var li := 0
	for layer in layers:
		for p in parts:
			var pivot: Node = model.get_node_or_null(str(p[0]))
			if pivot == null:
				continue
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			EntityRenderer.box_arrays(Vector3(p[2][0], p[2][1], p[2][2]), Vector3(p[3][0], p[3][1], p[3][2]), Vector2(p[4][0], p[4][1]), Vector2(64, 64), st, float(layer[1]), layer[2])
			var mi := MeshInstance3D.new()
			mi.name = "hlayer%d" % li
			mi.mesh = st.commit()
			mi.material_override = EntityRenderer.material(str(layer[0]))
			pivot.add_child(mi)
		li += 1


static func horse_armor_points(e) -> int:
	var d = e.data.get("horse_armor", {})
	if not (d is Dictionary) or d.is_empty():
		return 0
	return int(HORSE_ARMOR.get(ItemStack.from_dict(d).name().trim_suffix("_horse_armor"), 0))


static var _trim_tex: Dictionary = {}
static var _trim_mats: Dictionary = {}


## Java armor trim atlas (PalettedPermutations): pattern texture colours from trims/color_palettes/trim_palette
## replaced by the material palette (material override_armor_assets, e.g. iron_darker on iron armour).
static func trim_texture(pattern: String, material: String, legs: bool, armor_mat: String) -> Texture2D:
	# 26.3: trim_material/<m>.json palette_id -> textures/palettes/<id>.png, key palette palettes/trim_base;
	# armour of the trim's own material uses the <palette>_darker variant (Java override for e.g. iron on iron)
	var pal := "trim/" + material
	var mj = Res.read_json("data/minecraft/trim_material/%s.json" % material)
	if mj is Dictionary and mj.has("palette_id"):
		pal = str(mj["palette_id"]).trim_prefix("minecraft:")
	if armor_mat == material and Res.load_image("palettes/" + pal + "_darker") != null:
		pal += "_darker"
	var key := "%s|%s|%s" % [pattern, pal, legs]
	if _trim_tex.has(key):
		return _trim_tex[key]
	var t: Texture2D = null
	var src := Res.load_image("trims/entity/%s/%s" % ["humanoid_leggings" if legs else "humanoid", pattern])
	var kp := Res.load_image("palettes/trim_base")
	if kp == null:
		kp = Res.load_image("trims/color_palettes/trim_palette")
	var mp := Res.load_image("palettes/" + pal)
	if mp == null:
		mp = Res.load_image("trims/color_palettes/" + pal.trim_prefix("trim/"))
	if src != null and kp != null and mp != null:
		src = src.duplicate()
		src.convert(Image.FORMAT_RGBA8)
		kp.convert(Image.FORMAT_RGBA8)
		mp.convert(Image.FORMAT_RGBA8)
		var lut := {}
		for i in mini(kp.get_width(), mp.get_width()):
			lut[kp.get_pixel(i, 0).to_rgba32() & 0xFFFFFF00] = mp.get_pixel(i, 0)
		for y in src.get_height():
			for x in src.get_width():
				var c := src.get_pixel(x, y)
				if c.a <= 0.0:
					continue
				var m = lut.get(c.to_rgba32() & 0xFFFFFF00)
				if m != null:
					src.set_pixel(x, y, Color((m as Color).r, (m as Color).g, (m as Color).b, c.a))
		t = ImageTexture.create_from_image(src)
	_trim_tex[key] = t
	return t

static func _trim_mat(t: Texture2D) -> ShaderMaterial:
	if _trim_mats.has(t):
		return _trim_mats[t]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/entity.gdshader")
	m.set_shader_parameter("tex", t)
	m.set_shader_parameter("has_tex", true)
	_trim_mats[t] = m
	return m


static func _suffix(s: ItemStack) -> String:
	var out := ""
	if s.components.has("minecraft:dyed_color"):
		out += "@%d" % int(s.components["minecraft:dyed_color"])
	var tr = s.components.get("minecraft:trim")
	if tr is Dictionary:
		out += "#%s:%s" % [str(tr.get("pattern", "")).trim_prefix("minecraft:"), str(tr.get("material", "")).trim_prefix("minecraft:")]
	return out


static func slots_of_inventory(inv: Inventory) -> Array:
	var out: Array = []
	for i in 4:
		var s := inv.get_slot(Inventory.ARMOR0 + i)
		out.append("" if s.is_empty() else s.name() + _suffix(s))
	return out


static func slots_of_dicts(arr: Array) -> Array:
	var out: Array = []
	for i in 4:
		var d = arr[i] if i < arr.size() else {}
		if d is String:
			out.append(d)
		elif d is Dictionary and not d.is_empty():
			var ds := ItemStack.from_dict(d)
			out.append(ds.name() + _suffix(ds))
		else:
			out.append("")
	return out


## Java Mob.populateDefaultEquipmentSlots for armor-wearing hostile mobs.
static func equip_mob(e, rng: RandomNumberGenerator, difficulty: int) -> void:
	if not (e.id in ARMOR_MOBS) or e.id in ["piglin", "zombified_piglin", "wither_skeleton"]:
		return
	var local_diff: float = [0.0, 0.0, 0.25, 0.5][clampi(difficulty, 0, 3)]
	if rng.randf() >= 0.15 * local_diff:
		return
	var tier := rng.randi_range(0, 1)
	for i in 3:
		if rng.randf() < 0.095:
			tier += 1
	var stop := 0.1 if difficulty == 3 else 0.25
	var armor: Array = ["", "", "", ""]
	var first := true
	for slot in 4:
		if not first and rng.randf() < stop:
			break
		first = false
		armor[slot] = TIERS[mini(tier, 4)] + "_" + PIECES[slot]
	e.data["armor"] = armor


static func death_drops(em, e) -> void:
	var armor: Array = e.data.get("armor", [])
	for nm in armor:
		if str(nm) != "" and em.rng.randf() < 0.085:
			em.spawn_item(e.pos + Vector3(0, 0.5, 0), ItemStack.named(str(nm), 1))
