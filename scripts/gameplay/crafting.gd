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
static var campfire: Dictionary = {}   # campfire_cooking: item name -> [result, count, xp, time] (was mixed into smoking)
static var stonecutting: Dictionary = {}  # input name -> Array[[result, count]]
static var loaded := false
static var last_keep: Array = []   # grid indices the last special match leaves in place (book/banner copies)
static var count := 0

const REMAINDERS := {"water_bucket": "bucket", "lava_bucket": "bucket", "milk_bucket": "bucket", "powder_snow_bucket": "bucket", "honey_bottle": "glass_bottle", "dragon_breath": "glass_bottle"}
# Furnace fuel burn times in ticks (wiki: Smelting, fuel table, Java values).
const FUEL := {"lava_bucket": 20000, "coal_block": 16000, "dried_kelp_block": 4000, "blaze_rod": 2400, "coal": 1600, "charcoal": 1600,
	"bamboo_mosaic": 300, "bamboo_mosaic_slab": 150, "bamboo_mosaic_stairs": 300, "chiseled_bookshelf": 300, "mangrove_roots": 300,
	"ladder": 300, "crafting_table": 300, "cartography_table": 300, "fletching_table": 300, "smithing_table": 300, "loom": 300,
	"bookshelf": 300, "lectern": 300, "composter": 300, "chest": 300, "trapped_chest": 300, "barrel": 300, "daylight_detector": 300,
	"jukebox": 300, "note_block": 300, "bow": 300, "crossbow": 300, "fishing_rod": 300, "wooden_pickaxe": 200, "wooden_shovel": 200,
	"wooden_hoe": 200, "wooden_axe": 200, "wooden_sword": 200, "wooden_spear": 200, "bowl": 100, "stick": 100, "dead_bush": 100,
	"azalea": 100, "leaf_litter": 100, "short_dry_grass": 100, "tall_dry_grass": 100, "bamboo": 50, "scaffolding": 50}
# Item tags burning as fuel (same wiki table); members of #non_flammable_wood (crimson / warped wood) never burn.
const FUEL_TAGS := {"boats": 1200, "bamboo_blocks": 300, "logs_that_burn": 300, "planks": 300, "wooden_slabs": 150, "wooden_stairs": 300,
	"wooden_pressure_plates": 300, "wooden_trapdoors": 300, "fence_gates": 300, "wooden_fences": 300, "wooden_shelves": 300, "banners": 300,
	"wooden_doors": 200, "signs": 200, "hanging_signs": 200, "wooden_buttons": 100, "saplings": 100, "wool": 100, "wool_stairs": 100,
	"wool_carpets": 67, "wool_slabs": 50, "cushions": 50}
static var _fuel: Dictionary = {}   # item name -> ticks, built on first use


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
				var target: Dictionary = smelting if tp == "smelting" else (blasting if tp == "blasting" else (smoking if tp == "smoking" else campfire))
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
	var table: Dictionary = smelting if kind == "smelting" else (blasting if kind == "blasting" else (campfire if kind == "campfire_cooking" else smoking))
	var e = table.get(Res.items.names[item])
	if e == null:
		return null
	var it := Res.items.id(e[0])
	return ItemStack.of(it, e[1]) if it > 0 else null


static func smelt_info(item: int, kind: String = "smelting") -> Array:
	load_all()
	var table: Dictionary = smelting if kind == "smelting" else (blasting if kind == "blasting" else (campfire if kind == "campfire_cooking" else smoking))
	return table.get(Res.items.names[item], [])


static func fuel_time(item: int) -> int:
	if _fuel.is_empty():
		var tbl: Dictionary = FUEL.duplicate()
		if Res.mode == "vanilla":
			var nonflam := Tags.items("non_flammable_wood")
			for t in FUEL_TAGS:
				for n in Tags.items(t):
					if not nonflam.has(n) and not tbl.has(n):
						tbl[n] = FUEL_TAGS[t]
		else:
			for n2 in Res.items.names:
				if n2.ends_with("_planks") or n2.ends_with("_log"):
					tbl[n2] = 300
		_fuel = tbl
	return int(_fuel.get(Res.items.names[item], 0))
