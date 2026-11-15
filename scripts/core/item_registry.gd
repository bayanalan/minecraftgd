## ItemRegistry — every item ID from the installed version's assets/minecraft/items/ (26.3 item model
## definitions) plus original gameplay stat tables (stack size, durability, tools, armor, food).
## Contract: id(name) -> int; fields by index (names, max_stack, max_damage, place_block, model, tool_*...).
## Invariants: index 0 = "air" (empty). Unknown names never alias other items.
class_name ItemRegistry
extends RefCounted

# material -> [mining tier (0 = hand), mining efficiency, durability, attack damage bonus] (wiki: Tiers)
const TIERS := {
	"wooden": [1, 2.0, 59, 0.0], "stone": [2, 4.0, 131, 1.0], "copper": [2, 5.0, 190, 1.0], "iron": [3, 6.0, 250, 2.0],
	"diamond": [4, 8.0, 1561, 3.0], "golden": [1, 12.0, 32, 0.0], "netherite": [5, 9.0, 2031, 4.0],
}
# tool kind -> [base attack damage, attack speed]
const TOOL_KIND := {"sword": [3.0, 1.6], "pickaxe": [1.0, 1.2], "axe": [6.0, 0.9], "shovel": [1.5, 1.0], "hoe": [0.0, 1.0], "spear": [2.0, 1.0]}
# material -> [head, chest, legs, feet armor points, durability multiplier, toughness, knockback resistance] (wiki: Armor materials)
const ARMOR := {
	"leather": [1, 3, 2, 1, 5, 0.0, 0.0], "chainmail": [2, 5, 4, 1, 15, 0.0, 0.0], "copper": [2, 4, 3, 1, 11, 0.0, 0.0], "iron": [2, 6, 5, 2, 15, 0.0, 0.0],
	"golden": [2, 5, 3, 1, 7, 0.0, 0.0], "diamond": [3, 8, 6, 3, 33, 2.0, 0.0], "netherite": [3, 8, 6, 3, 37, 3.0, 0.1], "turtle": [2, 0, 0, 0, 25, 0.0, 0.0],
}
const FOOD := {
	"apple": [4, 2.4], "bread": [5, 6.0], "beef": [3, 1.8], "cooked_beef": [8, 12.8], "porkchop": [3, 1.8], "cooked_porkchop": [8, 12.8],
	"chicken": [2, 1.2], "cooked_chicken": [6, 7.2], "mutton": [2, 1.2], "cooked_mutton": [6, 9.6], "cod": [2, 0.4], "cooked_cod": [5, 6.0],
	"salmon": [2, 0.4], "cooked_salmon": [6, 9.6], "carrot": [3, 3.6], "potato": [1, 0.6], "baked_potato": [5, 6.0],
	"golden_carrot": [6, 14.4], "golden_apple": [4, 9.6], "enchanted_golden_apple": [4, 9.6], "melon_slice": [2, 1.2], "cookie": [2, 0.4],
	"pumpkin_pie": [8, 4.8], "beetroot": [1, 1.2], "beetroot_soup": [6, 7.2], "mushroom_stew": [6, 7.2], "rabbit_stew": [10, 12.0],
	"rotten_flesh": [4, 0.8], "spider_eye": [2, 3.2], "sweet_berries": [2, 0.4], "glow_berries": [2, 0.4], "dried_kelp": [1, 0.6],
	"honey_bottle": [6, 1.2], "rabbit": [3, 1.8], "cooked_rabbit": [5, 6.0], "tropical_fish": [1, 0.2], "pufferfish": [1, 0.2],
	"poisonous_potato": [2, 1.2], "chorus_fruit": [4, 2.4], "suspicious_stew": [6, 7.2],
}
const STACK16 := ["ender_pearl", "snowball", "egg", "bucket", "honey_bottle", "armor_stand", "written_book", "blue_egg", "brown_egg", "wind_charge_x"]
const ITEM_TO_BLOCK := {
	"redstone": "redstone_wire", "string": "tripwire", "wheat_seeds": "wheat", "carrot": "carrots", "potato": "potatoes",
	"beetroot_seeds": "beetroots", "melon_seeds": "melon_stem", "pumpkin_seeds": "pumpkin_stem", "sweet_berries": "sweet_berry_bush",
	"glow_berries": "cave_vines", "cocoa_beans": "cocoa", "torchflower_seeds": "torchflower_crop", "pitcher_pod": "pitcher_crop",
	"water_bucket": "water", "lava_bucket": "lava", "powder_snow_bucket": "powder_snow",
}

var names := PackedStringArray()
var index: Dictionary = {}
var max_stack := PackedInt32Array()
var max_damage := PackedInt32Array()
var place_block := PackedInt32Array()   # block state placed, -1 if none
var model_ref := PackedStringArray()    # model id (item/... or block/...)
var tool_kind := PackedStringArray()
var tool_tier := PackedInt32Array()
var tool_speed := PackedFloat32Array()
var attack_damage := PackedFloat32Array()
var attack_speed := PackedFloat32Array()
var armor_slot := PackedInt32Array()     # -1 none, 0 feet 1 legs 2 chest 3 head
var armor_points := PackedInt32Array()
var armor_tough := PackedFloat32Array()
var armor_kb := PackedFloat32Array()      # knockback resistance per piece (netherite 0.1)
var food_nutrition := PackedInt32Array()
var food_saturation := PackedFloat32Array()


func id(name: String) -> int:
	return int(index.get(name.trim_prefix("minecraft:"), -1))


func _add(name: String, model: String, blocks: BlockRegistry) -> void:
	var i := names.size()
	names.append(name)
	index[name] = i
	model_ref.append(model)
	var stack := 64
	var dmg := 0
	var kind := ""
	var tier := 0
	var speed := 1.0
	var ad := 1.0
	var aspd := 4.0
	var aslot := -1
	var apts := 0
	var atough := 0.0
	var akb := 0.0
	for k in TOOL_KIND:
		if name.ends_with("_" + k):
			var mat := name.trim_suffix("_" + k)
			if TIERS.has(mat):
				var t: Array = TIERS[mat]
				kind = k
				tier = t[0]
				speed = t[1]
				dmg = t[2]
				ad = 1.0 + float(TOOL_KIND[k][0]) + float(t[3])
				aspd = TOOL_KIND[k][1]
				if k == "axe":
					ad = {"wooden": 7.0, "stone": 9.0, "copper": 9.0, "iron": 9.0, "golden": 7.0, "diamond": 9.0, "netherite": 10.0}.get(mat, 7.0)
					aspd = {"wooden": 0.8, "stone": 0.8, "copper": 0.8, "iron": 0.9, "golden": 1.0, "diamond": 1.0, "netherite": 1.0}.get(mat, 0.9)
				elif k == "hoe":
					ad = 1.0
					aspd = {"wooden": 1.0, "stone": 2.0, "copper": 2.0, "iron": 3.0, "golden": 1.0, "diamond": 4.0, "netherite": 4.0}.get(mat, 1.0)
				elif k == "spear":
					# wiki: Spear (Java tooltip "N Attack Damage" and attack speed per tier)
					ad = {"wooden": 1.0, "stone": 2.0, "copper": 2.0, "iron": 3.0, "golden": 1.0, "diamond": 4.0, "netherite": 5.0}.get(mat, 1.0)
					aspd = {"wooden": 1.54, "stone": 1.33, "copper": 1.18, "iron": 1.05, "golden": 1.05, "diamond": 0.95, "netherite": 0.87}.get(mat, 1.0)
				stack = 1
	var slots := ["boots", "leggings", "chestplate", "helmet"]
	for si in 4:
		if name.ends_with("_" + slots[si]):
			var mat2 := name.trim_suffix("_" + slots[si])
			if ARMOR.has(mat2):
				var a: Array = ARMOR[mat2]
				aslot = si
				apts = [a[3], a[2], a[1], a[0]][si] if mat2 != "turtle" else 2
				dmg = int(a[4]) * [13, 15, 16, 11][si]
				atough = a[5]
				akb = a[6]
				stack = 1
	if name in ["shears"]:
		kind = "shears"; dmg = 238; stack = 1
	elif name in ["flint_and_steel"]:
		dmg = 64; stack = 1
	elif name == "fishing_rod":
		dmg = 64; stack = 1
	elif name == "bow":
		dmg = 384; stack = 1
	elif name == "crossbow":
		dmg = 465; stack = 1
	elif name == "trident":
		dmg = 250; stack = 1; ad = 9.0; aspd = 1.1
	elif name == "shield":
		dmg = 336; stack = 1
	elif name == "elytra":
		dmg = 432; stack = 1; aslot = 2
	elif name == "mace":
		dmg = 500; stack = 1; ad = 6.0; aspd = 0.6
	elif name == "brush":
		dmg = 64; stack = 1
	elif name == "carrot_on_a_stick":
		dmg = 25; stack = 1   # wiki: Durability
	elif name == "warped_fungus_on_a_stick":
		dmg = 100; stack = 1   # wiki: Durability
	elif name == "wolf_armor":
		dmg = 64; stack = 1   # wiki: Wolf Armor
	elif name.ends_with("_bucket") and name != "bucket" or name.ends_with("_boat") or name.ends_with("_raft") or name.ends_with("minecart") or name.ends_with("_horse_armor") or name.ends_with("_stew") or name == "beetroot_soup" or name.begins_with("music_disc") or name == "saddle" or name == "totem_of_undying" or name.ends_with("potion") or name == "cake" or name.ends_with("_bed") or name == "writable_book" or name == "enchanted_book" or name == "spyglass" or name == "debug_stick" or name.ends_with("_shulker_box") or name == "shulker_box" or name == "knowledge_book" or name == "bundle" or name.ends_with("_bundle") or name == "goat_horn" or name.ends_with("_harness") or name.ends_with("_nautilus_armor") or name.ends_with("_banner_pattern"):
		stack = 1
	elif STACK16.has(name) or name.ends_with("_sign") or name.ends_with("_hanging_sign") or name.ends_with("_banner"):
		# eggs via STACK16 (egg / blue_egg / brown_egg); turtle and sniffer eggs stack to 64 (wiki: Turtle Egg, Sniffer Egg)
		stack = 16
	max_stack.append(stack)
	max_damage.append(dmg)
	tool_kind.append(kind)
	tool_tier.append(tier)
	tool_speed.append(speed)
	attack_damage.append(ad)
	attack_speed.append(aspd)
	armor_slot.append(aslot)
	armor_points.append(apts)
	armor_tough.append(atough)
	armor_kb.append(akb)
	var f: Array = FOOD.get(name, [0, 0.0])
	food_nutrition.append(int(f[0]))
	food_saturation.append(float(f[1]))
	var pb := -1
	if blocks != null:
		var bn: String = ITEM_TO_BLOCK.get(name, name)
		var b := blocks.block_id(bn)
		if b >= 0:
			pb = blocks.block_default[b]
	place_block.append(pb)


func build_vanilla(jar: JarAssetReader, blocks: BlockRegistry, _lang: Dictionary) -> void:
	_add("air", "", null)
	for f in jar.list("assets/minecraft/items/", ".json"):
		var n := f.get_file().get_basename()
		if n == "air":
			continue
		var j = jar.read_json(f)
		var model := ""
		if j is Dictionary and j.get("model") is Dictionary:
			model = ModelBaker.norm_id(ctx_ref(j["model"], "gui"))
			if model == "":
				model = _first_model(j["model"])
		_add(n, model, blocks)


## The model an item definition (26.x items/<name>.json) uses in one display context (gui, ground, fixed,
## firstperson_righthand, thirdperson_righthand, head ...): select on minecraft:display_context picks the matching
## case (spears: a flat model in the GUI, a long in-hand model otherwise); other selects / conditions / range
## dispatches use their default branch (fallback, on_false); special models their base.
static func ctx_ref(m, ctx: String) -> String:
	if not (m is Dictionary):
		return ""
	var t := str(m.get("type", "minecraft:model")).trim_prefix("minecraft:")
	match t:
		"model":
			return str(m.get("model", ""))
		"special":
			return str(m.get("base", ""))
		"select":
			if str(m.get("property", "")).trim_prefix("minecraft:") == "display_context":
				for c in m.get("cases", []):
					var w = (c as Dictionary).get("when")
					if (w is Array and (w as Array).has(ctx)) or (w is String and w == ctx):
						return ctx_ref(c.get("model"), ctx)
			if m.get("fallback") is Dictionary:
				return ctx_ref(m["fallback"], ctx)
			for c2 in m.get("cases", []):
				var r := ctx_ref((c2 as Dictionary).get("model"), ctx)
				if r != "":
					return r
		"condition":
			var r2 := ctx_ref(m.get("on_false"), ctx)
			return r2 if r2 != "" else ctx_ref(m.get("on_true"), ctx)
		"range_dispatch":
			if m.get("fallback") is Dictionary:
				return ctx_ref(m["fallback"], ctx)
			for en in m.get("entries", []):
				var r3 := ctx_ref((en as Dictionary).get("model"), ctx)
				if r3 != "":
					return r3
		"composite":
			for mm in m.get("models", []):
				var r4 := ctx_ref(mm, ctx)
				if r4 != "":
					return r4
	return ""


static var _ctx_cache: Dictionary = {}


## Normalised model id ("item/wooden_spear_in_hand") of an item in a display context; cached.
static func ctx_model(item_name: String, ctx: String) -> String:
	var k := item_name + "|" + ctx
	if _ctx_cache.has(k):
		return _ctx_cache[k]
	var j = Res.read_json("assets/minecraft/items/%s.json" % item_name) if Res.mode == "vanilla" else null
	var r := ModelBaker.norm_id(ctx_ref(j["model"], ctx)) if j is Dictionary and j.get("model") is Dictionary else ""
	_ctx_cache[k] = r
	return r


static func _first_model(m: Dictionary) -> String:
	if m.has("model") and m["model"] is String:
		return ModelBaker.norm_id(m["model"])
	for k in ["fallback", "on_false", "on_true", "base"]:
		if m.get(k) is Dictionary:
			var r := _first_model(m[k])
			if r != "":
				return r
	for k in ["cases", "entries", "models"]:
		if m.get(k) is Array:
			for c in m[k]:
				if c is Dictionary:
					var r2 := _first_model(c.get("model", c)) if c.get("model") is Dictionary else _first_model(c)
					if r2 != "":
						return r2
	return ""


func build_placeholder(blocks: BlockRegistry) -> void:
	_add("air", "", null)
	for n in blocks.names:
		if n != "air" and n != "water" and n != "lava":
			_add(n, "block/" + n, blocks)
	for n in ["stick", "wooden_pickaxe", "stone_pickaxe", "iron_pickaxe", "wooden_axe", "wooden_shovel", "coal", "iron_ingot", "diamond", "apple", "bread"]:
		_add(n, "item/" + n, blocks)


func display_name(i: int) -> String:
	var n := names[i]
	var k := "item.minecraft." + n
	if Res.lang.has(k):
		return Res.lang[k]
	return Res.block_display_name(n)
