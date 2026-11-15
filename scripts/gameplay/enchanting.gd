## Enchanting — data-driven enchantments from the installed data/minecraft/enchantment/*.json (max_level, weight,
## min_cost/max_cost, supported/primary item tags, exclusive sets, anvil cost) with Java algorithms recalled
## (source D): EnchantmentMenu costs + EnchantmentHelper.selectEnchantment (LegacyRandom seeded with the
## player's enchantment seed + slot), bookshelf power, AnvilMenu repair/combine/rename costs, grindstone removal,
## smithing_transform. Enchantability per material is a documented table (item components are code-defined).
## Contract: static API; enchantments live in ItemStack.components["minecraft:enchantments"] (books:
## "minecraft:stored_enchantments") as {"minecraft:id": level}.
class_name Enchanting
extends RefCounted

static var defs: Dictionary = {}     # id -> {max, weight, min_b, min_p, max_b, max_p, supported, primary, exclusive, anvil, curse}
static var table_order: Array = []   # enchantments in #minecraft:in_enchanting_table order
static var smithing: Array = []      # [{template, base, addition, result}]
static var _loaded := false

# wiki: Enchantability (Java). Only these items carry the enchantable component, so only they can use the table.
const ENCHANTABILITY := {"book": 1, "bow": 1, "crossbow": 1, "trident": 1, "fishing_rod": 1, "mace": 15}
const TOOL_ENCH := {"wooden": 15, "stone": 5, "copper": 13, "iron": 14, "golden": 22, "diamond": 10, "netherite": 15}
const TOOL_KINDS := ["sword", "pickaxe", "axe", "shovel", "hoe", "spear"]
const ARMOR_KINDS := ["helmet", "chestplate", "leggings", "boots"]
## Java items with provides_trim_material.
const TRIM_MATERIALS := {"amethyst_shard": "amethyst", "copper_ingot": "copper", "diamond": "diamond", "emerald": "emerald",
	"gold_ingot": "gold", "iron_ingot": "iron", "lapis_lazuli": "lapis", "netherite_ingot": "netherite", "quartz": "quartz",
	"redstone": "redstone", "resin_brick": "resin"}
const ARMOR_ENCH := {"leather": 15, "chainmail": 12, "copper": 8, "iron": 9, "golden": 25, "diamond": 10, "netherite": 15, "turtle": 9}
const REPAIR := {"wooden": "#wooden_tool_materials", "stone": "#stone_tool_materials", "iron": "iron_ingot", "golden": "gold_ingot", "diamond": "diamond",
	"netherite": "netherite_ingot", "copper": "copper_ingot", "leather": "leather", "chainmail": "iron_ingot", "turtle": "turtle_scute",
	"elytra": "phantom_membrane", "mace": "breeze_rod", "shield": "#wooden_tool_materials", "wolf_armor": "armadillo_scute"}


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for f in Res.list_files("data/minecraft/enchantment/", ".json"):
		var j = Res.read_json(f)
		if not (j is Dictionary):
			continue
		var id := "minecraft:" + f.get_file().get_basename()
		var mn: Dictionary = j.get("min_cost", {})
		var mx: Dictionary = j.get("max_cost", {})
		defs[id] = {"max": int(j.get("max_level", 1)), "weight": int(j.get("weight", 1)),
			"min_b": int(mn.get("base", 1)), "min_p": int(mn.get("per_level_above_first", 0)),
			"max_b": int(mx.get("base", 50)), "max_p": int(mx.get("per_level_above_first", 0)),
			"supported": Tags.items(str(j.get("supported_items", ""))) if str(j.get("supported_items", "")).begins_with("#") else {str(j.get("supported_items", "")).trim_prefix("minecraft:"): true},
			"primary": Tags.items(str(j["primary_items"])) if j.get("primary_items") is String and str(j["primary_items"]).begins_with("#") else {},
			"exclusive": Tags.resolve("enchantment", str(j.get("exclusive_set", ""))) if str(j.get("exclusive_set", "")).begins_with("#") else {},
			"anvil": int(j.get("anvil_cost", 1)), "curse": id.contains("curse")}
	for e in Tags.resolve("enchantment", "#minecraft:in_enchanting_table"):
		table_order.append("minecraft:" + str(e))
	for f2 in Res.list_files("data/minecraft/recipe/", ".json"):
		var r = Res.read_json(f2)
		if r is Dictionary and str(r.get("type", "")).ends_with("smithing_trim"):
			smithing.append({"template": Crafting._ingredient(r.get("template", "")), "base": Crafting._ingredient(r.get("base", "")),
				"addition": Crafting._ingredient(r.get("addition", "")), "trim": str(r.get("pattern", ""))})
		if r is Dictionary and str(r.get("type", "")).ends_with("smithing_transform"):
			var res = r.get("result", {})
			smithing.append({"template": Crafting._ingredient(r.get("template", "")), "base": Crafting._ingredient(r.get("base", "")),
				"addition": Crafting._ingredient(r.get("addition", "")), "result": str(res.get("id", "") if res is Dictionary else res).trim_prefix("minecraft:")})


static func name_of(id: String) -> String:
	return Res.tr_key("enchantment." + id.replace(":", "."), id.trim_prefix("minecraft:").capitalize())


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][clampi(n, 0, 10)]


static func enchantability(item_name: String) -> int:
	if ENCHANTABILITY.has(item_name):
		return ENCHANTABILITY[item_name]
	var cut := item_name.find("_")
	if cut < 0:
		return 0
	var mat := item_name.substr(0, cut)
	var kind := item_name.substr(cut + 1)
	if ARMOR_KINDS.has(kind):
		return int(ARMOR_ENCH.get(mat, 0))
	if TOOL_KINDS.has(kind):
		return int(TOOL_ENCH.get(mat, 0))
	return 0


static func get_enchants(s: ItemStack) -> Dictionary:
	var key := "minecraft:stored_enchantments" if s.name() == "enchanted_book" else "minecraft:enchantments"
	var e = s.components.get(key, {})
	return (e as Dictionary).duplicate() if e is Dictionary else {}


static func set_enchants(s: ItemStack, e: Dictionary) -> void:
	var key := "minecraft:stored_enchantments" if s.name() == "enchanted_book" else "minecraft:enchantments"
	if e.is_empty():
		s.components.erase(key)
	else:
		s.components[key] = e


static func _cost(base: int, per: int, lvl: int) -> int:
	return base + per * (lvl - 1)


## Bookshelves (#enchantment_power_provider) in the Java 5x5x2 ring with an #enchantment_power_transmitter block
## in between (wiki: Enchanting mechanics).
static func bookshelves(world, p: Vector3i) -> int:
	var prov := Tags.blocks("enchantment_power_provider")
	var trans := Tags.blocks("enchantment_power_transmitter")
	var n := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			if absi(dx) != 2 and absi(dz) != 2:
				continue
			for dy in 2:
				var q := p + Vector3i(dx, dy, dz)
				var mid := p + Vector3i(dx / 2, dy, dz / 2)
				var st: int = world.state_at(q.x, q.y, q.z)
				var ms: int = world.state_at(mid.x, mid.y, mid.z)
				var clear := ms == 0 or (ms > 0 and (trans.has(Res.blocks.name_of(ms)) if not trans.is_empty() else (Res.blocks.st_flags[ms] & BlockRegistry.F_REPLACEABLE) != 0))
				if st > 0 and prov.has(Res.blocks.name_of(st)) and clear:
					n += 1
	return mini(n, 15)


## EnchantmentMenu.slotsChanged: the three level costs.
static func costs(seed: int, shelves: int, item_name: String) -> Array:
	var r := RandomSources.LegacyRandom.new(seed)
	var out := [0, 0, 0]
	if enchantability(item_name) <= 0:
		return out
	for slot in 3:
		var j := r.next_int_bound(8) + 1 + (shelves >> 1) + r.next_int_bound(shelves + 1)
		if slot == 0:
			out[slot] = maxi(j / 3, 1)
		elif slot == 1:
			out[slot] = j * 2 / 3 + 1
		else:
			out[slot] = maxi(j, shelves * 2)
		if out[slot] < slot + 1:
			out[slot] = 0
	return out


static func _applies(id: String, item_name: String, table: bool) -> bool:
	if item_name == "book":
		return true
	var d: Dictionary = defs.get(id, {})
	if d.is_empty():
		return false
	if table and not (d["primary"] as Dictionary).is_empty():
		return (d["primary"] as Dictionary).has(item_name)
	return (d["supported"] as Dictionary).has(item_name)


static func _compatible(a: String, b: String) -> bool:
	if a == b:
		return false
	var da: Dictionary = defs.get(a, {})
	var db: Dictionary = defs.get(b, {})
	return not (da.get("exclusive", {}) as Dictionary).has(b.trim_prefix("minecraft:")) and not (db.get("exclusive", {}) as Dictionary).has(a.trim_prefix("minecraft:"))


## EnchantmentHelper.selectEnchantment (+ book removal) -> [[id, level], ...].
static func select(seed: int, slot: int, item_name: String, level: int) -> Array:
	var r := RandomSources.LegacyRandom.new(seed + slot)
	var out := select_from(r, item_name, level, table_order)
	if item_name == "book" and out.size() > 1:
		out.remove_at(r.next_int_bound(out.size()))
	return out


## EnchantmentHelper.selectEnchantment over the given enchantment ids (the table's #in_enchanting_table, or a trade's
## enchant_with_levels options): eCost = round((level + 1 + randInt(ench/4) + randInt(ench/4)) * (1 + randTri(0.15)))
## (wiki: Enchanting mechanics).
static func select_from(r: RandomSources.LegacyRandom, item_name: String, level: int, options: Array) -> Array:
	load_all()
	var out: Array = []
	var ench := enchantability(item_name)
	if ench <= 0:
		return out
	level += 1 + r.next_int_bound(ench / 4 + 1) + r.next_int_bound(ench / 4 + 1)
	var f := (r.next_float() + r.next_float() - 1.0) * 0.15
	level = maxi(roundi(level + level * f), 1)
	var avail: Array = []
	for id in options:
		if not _applies(id, item_name, true):
			continue
		var d: Dictionary = defs.get(id, {})
		if d.is_empty():
			continue
		for lv in range(int(d["max"]), 0, -1):
			if level >= _cost(d["min_b"], d["min_p"], lv) and level <= _cost(d["max_b"], d["max_p"], lv):
				avail.append([id, lv, int(d["weight"])])
				break
	if avail.is_empty():
		return out
	out.append(_weighted(r, avail))
	while r.next_int_bound(50) <= level:
		var last: String = out[out.size() - 1][0]
		var keep: Array = []
		for a in avail:
			if _compatible(a[0], last):
				keep.append(a)
		avail = keep
		if avail.is_empty():
			break
		out.append(_weighted(r, avail))
		level /= 2
	return out


static func _weighted(r: RandomSources.LegacyRandom, lst: Array) -> Array:
	var tot := 0
	for a in lst:
		tot += int(a[2])
	var k := r.next_int_bound(maxi(tot, 1))
	for a in lst:
		k -= int(a[2])
		if k < 0:
			return [a[0], a[1]]
	return [lst[0][0], lst[0][1]]


# ------------------------------------------------------------------ anvil / grindstone / smithing

static func repair_material(item_name: String) -> String:
	var mat := item_name.split("_")[0]
	return str(REPAIR.get(item_name, REPAIR.get(mat, "")))


static func _matches(s: ItemStack, spec: String) -> bool:
	if spec == "":
		return false
	if spec.begins_with("#"):
		return Tags.items(spec.substr(1)).has(s.name())
	return s.name() == spec


## AnvilMenu.createResult (wiki: Anvil mechanics): unit repair 25 % of max durability per material (1 level each),
## combining two items = sum of both + 12 % (2 levels), enchantment cost = final level x anvil_cost (halved from
## books, min 1), +1 per incompatible enchantment on the target (sacrifice enchantments that cannot apply are
## ignored), rename 1, both prior-work penalties added; the result's penalty is 2 x max(left, right) + 1 (renaming
## alone keeps it); rename-only cost is capped at 39. Returns {result: ItemStack, cost: int, use_right: int}.
static func anvil(left: ItemStack, right: ItemStack, new_name: String) -> Dictionary:
	if left.is_empty():
		return {}
	var res := left.copy()
	var cost := 0
	var use_right := 0
	var md: int = Res.items.max_damage[left.item]
	var lrc := int(left.components.get("minecraft:repair_cost", 0))
	var rrc := int(right.components.get("minecraft:repair_cost", 0)) if not right.is_empty() else 0
	var prior := lrc + rrc
	if not right.is_empty():
		var book := right.name() == "enchanted_book"
		if md > 0 and _matches(right, repair_material(left.name())):
			var dmg := mini(res.damage, md / 4)
			if dmg <= 0:
				return {}
			var k := 0
			while dmg > 0 and k < right.count:
				res.damage -= dmg
				cost += 1
				dmg = mini(res.damage, md / 4)
				k += 1
			use_right = k
		else:
			if not book and right.item != left.item:
				return {}
			if md > 0 and not book:
				var rem := (md - left.damage) + (md - right.damage) + md * 12 / 100
				var nd := maxi(md - rem, 0)
				if nd < res.damage:
					res.damage = nd
					cost += 2
			var le := get_enchants(res)
			var any := false
			var re := get_enchants(right)
			for id in re:
				var rl := int(re[id])
				if not _applies(id, left.name(), false) and left.name() != "enchanted_book":
					continue
				var bad := 0
				for ex in le:
					if ex != id and not _compatible(id, ex):
						bad += 1
				if bad > 0:
					cost += bad
					continue
				var ll := int(le.get(id, 0))
				var nl := mini(ll + 1, int(defs.get(id, {}).get("max", 1))) if ll == rl else maxi(ll, rl)
				le[id] = nl
				any = true
				var ac := int(defs.get(id, {}).get("anvil", 1))
				if book:
					ac = maxi(1, ac / 2)
				cost += ac * nl
			if not any and res.damage == left.damage:
				return {}
			set_enchants(res, le)
			use_right = 1
	var renamed := false
	if new_name != "" and new_name != str(left.components.get("minecraft:custom_name", "")):
		res.components["minecraft:custom_name"] = new_name
		cost += 1
		renamed = true
	if cost <= 0:
		return {}
	cost += prior
	if renamed and use_right == 0 and cost >= 40:
		cost = 39
	res.components["minecraft:repair_cost"] = maxi(lrc, rrc) * 2 + 1 if use_right > 0 else lrc
	return {"result": res, "cost": cost, "use_right": use_right}


## Grindstone: strips non-curse enchantments; two equal damageable items combine (+5% durability).
static func grindstone(a: ItemStack, b: ItemStack) -> ItemStack:
	if a.is_empty() and b.is_empty():
		return ItemStack.new()
	var base := a if not a.is_empty() else b
	var other := b if not a.is_empty() else ItemStack.new()
	if not other.is_empty() and other.item != base.item:
		return ItemStack.new()
	var res := base.copy()
	res.count = 1
	if not other.is_empty():
		var md: int = Res.items.max_damage[base.item]
		if md <= 0:
			return ItemStack.new()
		res.damage = maxi(md - ((md - base.damage) + (md - other.damage) + md * 5 / 100), 0)
	var keep := {}
	for id in get_enchants(base):
		if bool(defs.get(id, {}).get("curse", false)):
			keep[id] = get_enchants(base)[id]
	if res.name() == "enchanted_book" and keep.is_empty():
		res = ItemStack.named("book", 1)
	else:
		set_enchants(res, keep)
	res.components.erase("minecraft:repair_cost")
	return res


static func smith(template: ItemStack, base: ItemStack, addition: ItemStack) -> ItemStack:
	if template.is_empty() or base.is_empty() or addition.is_empty():
		return ItemStack.new()
	for r in smithing:
		if (r["template"] as Dictionary).has(template.name()) and (r["base"] as Dictionary).has(base.name()) and (r["addition"] as Dictionary).has(addition.name()):
			if r.has("trim"):
				# Java SmithingTrimRecipe: base + {material from the addition, pattern from the recipe}; same trim -> nothing
				var mat: String = TRIM_MATERIALS.get(addition.name(), "")
				if mat == "":
					continue
				var trim := {"material": "minecraft:" + mat, "pattern": str(r["trim"])}
				if base.components.get("minecraft:trim") == trim:
					return ItemStack.new()
				var tout := base.copy()
				tout.count = 1
				tout.components["minecraft:trim"] = trim
				return tout
			var out := ItemStack.named(r["result"], 1)
			out.components = base.components.duplicate(true)
			out.damage = base.damage
			return out
	return ItemStack.new()
