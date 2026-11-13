## Crafting — recipe registry loaded from the installed version's data/minecraft/recipe/*.json:
## crafting_shaped (mirroring allowed), crafting_shapeless, smelting/blasting/smoking/campfire_cooking,
## stonecutting, smithing_transform. Ingredients support items, "#tags" and arrays (26.x string form).
## Contract: load(); match_grid(grid: Array[ItemStack], w, h) -> {recipe, result: ItemStack} or {};
## craft(grid,...) consumes ingredients (with remainders: buckets/bottles); smelt_result(item); fuel_time(item).
## Placeholder mode: a few ORIGINAL built-in recipes so the loop is testable.
class_name Crafting

static var shaped: Array = []
static var shapeless: Array = []
static var smelting: Dictionary = {}   # item name -> [result name, count, xp, time]
static var blasting: Dictionary = {}
static var smoking: Dictionary = {}
static var stonecutting: Dictionary = {}  # input name -> Array[[result, count]]
static var loaded := false
static var last_keep: Array = []   # grid indices the last special match leaves in place (book/banner copies)
static var count := 0

const REMAINDERS := {"water_bucket": "bucket", "lava_bucket": "bucket", "milk_bucket": "bucket", "powder_snow_bucket": "bucket", "honey_bottle": "glass_bottle", "dragon_breath": "glass_bottle"}
const FUEL := {"coal": 1600, "charcoal": 1600, "coal_block": 16000, "lava_bucket": 20000, "blaze_rod": 2400, "stick": 100, "bamboo": 50, "dried_kelp_block": 4001, "scaffolding": 50}


static func _ingredient(v) -> Dictionary:
	var out := {}
	if v is String:
		if v.begins_with("#"):
			out.merge(Tags.items(v))
		else:
			out[v.trim_prefix("minecraft:")] = true
	elif v is Array:
		for e in v:
			out.merge(_ingredient(e))
	elif v is Dictionary:
		if v.has("item"):
			out[str(v["item"]).trim_prefix("minecraft:")] = true
		if v.has("tag"):
			out.merge(Tags.items(str(v["tag"])))
	return out


static func load_all() -> void:
	if loaded:
		return
	loaded = true
	shaped.clear()
	shapeless.clear()
	SpecialRecipes.recipes.clear()
	Potions.data_mixes.clear()
	if Res.mode != "vanilla":
		_builtin()
		return
	for f in Res.list_files("data/minecraft/recipe/", ".json"):
		var j = Res.read_json(f)
		if not (j is Dictionary):
			continue
		var tp := str(j.get("type", "")).trim_prefix("minecraft:")
		var res = j.get("result", {})
		var rname := ""
		var rcount := 1
		if res is Dictionary:
			rname = str(res.get("id", res.get("item", ""))).trim_prefix("minecraft:")
			rcount = int(res.get("count", 1))
		elif res is String:
			rname = res.trim_prefix("minecraft:")
		match tp:
			"crafting_shaped":
				var pat: Array = j.get("pattern", [])
				var key: Dictionary = j.get("key", {})
				var h := pat.size()
				var w := 0
				for row in pat:
					w = maxi(w, str(row).length())
				var cells: Array = []
				for row in pat:
					var s := str(row)
					for x in w:
						var ch := s[x] if x < s.length() else " "
						cells.append({} if ch == " " else _ingredient(key.get(ch, "")))
				shaped.append({"w": w, "h": h, "cells": cells, "result": rname, "count": rcount, "id": f.get_file().get_basename(), "category": str(j.get("category", "misc"))})
			"crafting_shapeless":
				var ings: Array = []
				for i in j.get("ingredients", []):
					ings.append(_ingredient(i))
				shapeless.append({"ings": ings, "result": rname, "count": rcount, "id": f.get_file().get_basename(), "category": str(j.get("category", "misc"))})
			"smelting", "blasting", "smoking", "campfire_cooking":
				var ing := _ingredient(j.get("ingredient", ""))
				var target: Dictionary = smelting if tp == "smelting" else (blasting if tp == "blasting" else smoking)
				for n in ing:
					target[n] = [rname, rcount, float(j.get("experience", 0.0)), int(j.get("cookingtime", 200))]
			"crafting_transmute", "crafting_dye", "crafting_imbue", "crafting_decorated_pot", "crafting_special_firework_rocket", "crafting_special_firework_star", "crafting_special_firework_star_fade", "crafting_special_bannerduplicate", "crafting_special_bookcloning", "crafting_special_repairitem", "crafting_special_shielddecoration":
				SpecialRecipes.recipes.append(j)
			"brewing":
				Potions.add_data_mix(j)
			"stonecutting":
				for n in _ingredient(j.get("ingredient", "")):
					if not stonecutting.has(n):
						stonecutting[n] = []
					stonecutting[n].append([rname, rcount])
	count = shaped.size() + shapeless.size() + smelting.size()


static func _builtin() -> void:
	shapeless.append({"ings": [{"oak_log": true}], "result": "oak_planks", "count": 4, "id": "planks"})
	shaped.append({"w": 1, "h": 2, "cells": [{"oak_planks": true}, {"oak_planks": true}], "result": "stick", "count": 4, "id": "stick"})
	shaped.append({"w": 2, "h": 2, "cells": [{"oak_planks": true}, {"oak_planks": true}, {"oak_planks": true}, {"oak_planks": true}], "result": "crafting_table", "count": 1, "id": "crafting_table"})
	var p := {"oak_planks": true}
	var s := {"stick": true}
	shaped.append({"w": 3, "h": 3, "cells": [p, p, p, {}, s, {}, {}, s, {}], "result": "wooden_pickaxe", "count": 1, "id": "wooden_pickaxe"})
	var c := {"cobblestone": true}
	shaped.append({"w": 3, "h": 3, "cells": [c, c, c, c, {}, c, c, c, c], "result": "furnace", "count": 1, "id": "furnace"})
	smelting["iron_ore"] = ["iron_ingot", 1, 0.7, 200]
	smelting["sand"] = ["glass", 1, 0.1, 200]


static func _name_of(s: ItemStack) -> String:
	return "" if s == null or s.is_empty() else s.name()


## grid: Array of ItemStack (size w*h, row-major).
static func match_grid(grid: Array, gw: int, gh: int) -> Dictionary:
	load_all()
	last_keep = []
	# bounding box of non-empty cells
	var minx := gw
	var miny := gh
	var maxx := -1
	var maxy := -1
	var names: Array = []
	for y in gh:
		for x in gw:
			var n := _name_of(grid[y * gw + x])
			if n != "":
				minx = mini(minx, x)
				maxx = maxi(maxx, x)
				miny = mini(miny, y)
				maxy = maxi(maxy, y)
				names.append(n)
	if maxx < 0:
		return {}
	var w := maxx - minx + 1
	var h := maxy - miny + 1
	for r in shaped:
		if r["w"] != w or r["h"] != h:
			continue
		for mirror in [false, true]:
			var ok := true
			for y in h:
				for x in w:
					var rx: int = (w - 1 - x) if mirror else x
					var need: Dictionary = r["cells"][y * w + rx]
					var have := _name_of(grid[(miny + y) * gw + minx + x])
					if need.is_empty() != (have == ""):
						ok = false
						break
					if have != "" and not need.has(have):
						ok = false
						break
				if not ok:
					break
			if ok:
				var it := Res.items.id(r["result"])
				if it > 0:
					return {"recipe": r, "result": ItemStack.of(it, r["count"])}
	for r in shapeless:
		var ings: Array = r["ings"]
		if ings.size() != names.size():
			continue
		var used := []
		used.resize(names.size())
		used.fill(false)
		var ok2 := true
		for ing in ings:
			var found := false
			for i in names.size():
				if not used[i] and (ing as Dictionary).has(names[i]):
					used[i] = true
					found = true
					break
			if not found:
				ok2 = false
				break
		if ok2:
			var it2 := Res.items.id(r["result"])
			if it2 > 0:
				return {"recipe": r, "result": ItemStack.of(it2, r["count"])}
	var sp := SpecialRecipes.match(grid, gw, gh)
	if not sp.is_empty():
		last_keep = sp.get("keep", [])
		return {"recipe": {"id": "special", "result": (sp["result"] as ItemStack).name()}, "result": sp["result"]}
	return {}


## Consumes one of each ingredient; returns remainders to place back in the grid.
static func consume(grid: Array) -> void:
	for i in grid.size():
		var s: ItemStack = grid[i]
		if s == null or s.is_empty() or last_keep.has(i):
			continue
		var rem: String = REMAINDERS.get(s.name(), "")
		s.count -= 1
		if s.count <= 0:
			s.clear()
			if rem != "":
				var it := Res.items.id(rem)
				if it > 0:
					grid[i] = ItemStack.of(it, 1)


static func smelt_result(item: int, kind: String = "smelting") -> ItemStack:
	load_all()
	var table: Dictionary = smelting if kind == "smelting" else (blasting if kind == "blasting" else smoking)
	var e = table.get(Res.items.names[item])
	if e == null:
		return null
	var it := Res.items.id(e[0])
	return ItemStack.of(it, e[1]) if it > 0 else null


static func smelt_info(item: int, kind: String = "smelting") -> Array:
	load_all()
	var table: Dictionary = smelting if kind == "smelting" else (blasting if kind == "blasting" else smoking)
	return table.get(Res.items.names[item], [])


static func fuel_time(item: int) -> int:
	var n: String = Res.items.names[item]
	if FUEL.has(n):
		return FUEL[n]
	if n.ends_with("_planks") or n.ends_with("_log") or n.ends_with("_wood") or n.ends_with("_stem") or n.ends_with("_hyphae") or n.ends_with("_slab") and Tags.items("wooden_slabs").has(n) or n.ends_with("_fence") or n.ends_with("_stairs") and Tags.items("wooden_stairs").has(n) or n == "crafting_table" or n == "bookshelf" or n == "chest" or n.ends_with("_pressure_plate") and n.contains("_") and Tags.items("planks").size() > 0 and false:
		return 300 if not n.ends_with("_slab") else 150
	if n.begins_with("wooden_"):
		return 200
	if n.ends_with("_wool"):
		return 100
	if n.ends_with("_carpet"):
		return 67
	if n.ends_with("_sapling"):
		return 100
	return 0
